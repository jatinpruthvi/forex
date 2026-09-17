"""
speed_lab / engine.py — vectorised signal + exit-resolution engine.

Purpose: answer "what actually minimises days-to-pass the The5ers $2,500
Phase 1 (+10%, >=3 qualifying days) on the data in this repo?" without any of
the modelling shortcuts that sank PR #9.

Everything is costed with the repo's own canonical model (tools/optimizer_v2.py):
    round-trip spread = SPREAD_STD[sym] * RAW_SCALE
    commission        = COMM_RT $/lot round turn
    sizing            = risk_cash / (stop_pips*pv + COMM_RT), floored to 0.01 lot

Exits are resolved PESSIMISTICALLY (a bar that spans both stop and target is
booked as the stop), which is the honest bound for OHLC data.

numpy is used for the research sweep only. The final chosen configuration is
re-verified by a stdlib-only script so the repo keeps its no-dependency rule.
"""
from __future__ import annotations

import numpy as np
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
M5_4Y = ROOT / "validation/HistoryData"
M1_2Y = ROOT / "validation/HistoryData/m1-data"
CACHE = Path("/tmp/speedlab_cache")
CACHE.mkdir(exist_ok=True)

# ---- repo-canonical instrument specs (tools/aggressive_optimizer.py @003df25) ----
SPECS = {
    "EURUSD": dict(pip=0.0001, pv=10.00), "GBPUSD": dict(pip=0.0001, pv=10.00),
    "EURGBP": dict(pip=0.0001, pv=12.70), "AUDUSD": dict(pip=0.0001, pv=10.00),
    "NZDUSD": dict(pip=0.0001, pv=10.00), "USDCAD": dict(pip=0.0001, pv=9.80),
    "USDCHF": dict(pip=0.0001, pv=9.80), "USDJPY": dict(pip=0.01,   pv=6.76),
    "EURJPY": dict(pip=0.01,   pv=6.13), "GBPJPY": dict(pip=0.01,   pv=5.18),
    "XAUUSD": dict(pip=0.10,   pv=10.00),
}
# round-trip spread in PRICE units, standard account (tools/optimizer_v2.py)
SPREAD_STD = {
    "EURUSD": 0.00010, "GBPUSD": 0.00014, "EURGBP": 0.00014, "AUDUSD": 0.00012,
    "NZDUSD": 0.00016, "USDCAD": 0.00018, "USDCHF": 0.00014, "USDJPY": 0.014,
    "EURJPY": 0.016, "GBPJPY": 0.020, "XAUUSD": 0.28,
}
RAW_SCALE = 0.55
COMM_RT = 7.0
VOL_STEP = 0.01
VOL_MIN = 0.01

# ---- challenge constants ----
ACCOUNT = 2500.0
FLOOR = 2250.0
TARGET = ACCOUNT * 1.10
DAILY_LOSS = 0.05
QUAL_DAY = 12.50
QUAL_DAYS_N = 3
SERVER_OFF_H = 3          # Eightcap/The5ers server = UTC+3

ALL_PAIRS = list(SPECS)


def spread_pips(sym: str, scale: float = 1.0) -> float:
    return SPREAD_STD[sym] * RAW_SCALE * scale / SPECS[sym]["pip"]


def cost_R(sym: str, stop_pips: float, scale: float = 1.0) -> float:
    """Round-trip cost as a fraction of 1R. Independent of lot size."""
    pv = SPECS[sym]["pv"]
    return (spread_pips(sym, scale) * pv + COMM_RT) / (stop_pips * pv + COMM_RT)


# ---------------------------------------------------------------------------
# data loading (cached to .npy)
# ---------------------------------------------------------------------------
def _parse_csv(path: Path) -> np.ndarray:
    a = np.loadtxt(path, delimiter=",", skiprows=1, usecols=(0, 1, 2, 3, 4),
                   dtype=np.float64)
    a = a[a[:, 0].argsort(kind="stable")]
    return a


_MEM: dict = {}


def load_ohlc(sym: str, tf_minutes: int, source: str = "m5") -> dict:
    """Return ts(ms int64), o, h, l, c arrays for `sym` at `tf_minutes`.

    source="m5" -> 4-year M5 files (2022-09-11..2026-09-11), resampled up.
    source="m1" -> 2-year M1 files (2024-09-11..2026-09-11), resampled up.
    """
    base_min = 5 if source == "m5" else 1
    key = f"{sym}_{source}_{tf_minutes}"
    if key in _MEM:
        return _MEM[key]
    npy = CACHE / f"{key}.npy"
    if npy.exists():
        a = np.load(npy)
    else:
        bkey = f"{sym}_{source}_{base_min}"
        bnpy = CACHE / f"{bkey}.npy"
        if bnpy.exists():
            a = np.load(bnpy)
        else:
            if source == "m5":
                p = M5_4Y / f"{sym.lower()}-m5-2022-09-11_2026-09-11.csv"
            else:
                p = M1_2Y / f"{sym.lower()}-m1-2024-09-11_2026-09-11.csv"
            a = _parse_csv(p)
            np.save(bnpy, a)
        if tf_minutes != base_min:
            a = resample(a, base_min, tf_minutes)
        np.save(npy, a)
    out = dict(ts=a[:, 0].astype(np.int64), o=a[:, 1].copy(), h=a[:, 2].copy(),
               l=a[:, 3].copy(), c=a[:, 4].copy(), n=len(a))
    _MEM[key] = out
    return out


def resample(a: np.ndarray, base_min: int, tf_min: int) -> np.ndarray:
    """OHLC resample by flooring timestamps to tf_min buckets."""
    assert tf_min % base_min == 0
    bucket = tf_min * 60_000
    ts = a[:, 0].astype(np.int64)
    key = (ts // bucket) * bucket
    # group boundaries
    uniq, start = np.unique(key, return_index=True)
    end = np.append(start[1:], len(a))
    o = a[start, 1]
    c = a[end - 1, 4]
    h = np.maximum.reduceat(a[:, 2], start)
    l = np.minimum.reduceat(a[:, 3], start)
    return np.column_stack([uniq.astype(np.float64), o, h, l, c])


# ---------------------------------------------------------------------------
# indicators
# ---------------------------------------------------------------------------
def rolling_mean_prior(x: np.ndarray, period: int) -> np.ndarray:
    """out[i] = mean(x[i-period:i])  (strictly prior bars; NaN until warmup)."""
    cs = np.concatenate([[0.0], np.cumsum(x)])
    out = np.full(len(x), np.nan)
    n = len(x)
    out[period:] = (cs[period:n] - cs[0:n - period]) / period
    return out


def atr_prior(d: dict, period: int = 14, true_range: bool = True) -> np.ndarray:
    h, l, c = d["h"], d["l"], d["c"]
    if true_range:
        pc = np.concatenate([[c[0]], c[:-1]])
        tr = np.maximum(h - l, np.maximum(np.abs(h - pc), np.abs(l - pc)))
    else:
        tr = h - l
    return rolling_mean_prior(tr, period)


# ---------------------------------------------------------------------------
# signal families -> candidate arrays
# ---------------------------------------------------------------------------
def signals(d: dict, sym: str, family: str, *, k=2.5, n_ch=20, atr_period=14,
            stop_atr=3.0, target_r=2.0, min_stop_pips=0.0,
            session=None, max_hold=None, entry="close") -> dict | None:
    """Return dict of parallel arrays: idx, dir(+1/-1), entry, stop, target,
    stop_pips, atr — for every raw trigger (no per-day cap applied yet)."""
    o, h, l, c, n = d["o"], d["h"], d["l"], d["c"], d["n"]
    atr = atr_prior(d, atr_period)
    pip = SPECS[sym]["pip"]
    ok = ~np.isnan(atr) & (atr > 0)

    if family in ("rev", "mom"):
        body = np.abs(c - o)
        trig = ok & (body > k * atr)
        sdir = np.where(c > o, 1.0, -1.0)          # bar direction
        direction = -sdir if family == "rev" else sdir
        idx = np.flatnonzero(trig)
        if len(idx) == 0:
            return None
        direction = direction[idx]
        ext = np.where(direction > 0, l[idx], h[idx])   # wick we place stop beyond
        stop = np.where(direction > 0,
                        ext - stop_atr * atr[idx], ext + stop_atr * atr[idx])
        ep = c[idx] if entry == "close" else np.where(idx + 1 < n, o[np.minimum(idx + 1, n - 1)], c[idx])
        target = ep + direction * target_r * np.abs(ep - stop)
    elif family in ("don_break", "don_fade"):
        hh = rolling_max_prior(h, n_ch)
        ll = rolling_min_prior(l, n_ch)
        brk_up = ok & (c > hh)
        brk_dn = ok & (c < ll)
        if family == "don_fade":
            brk_up, brk_dn = brk_dn, brk_up          # fade the break
        idx_u = np.flatnonzero(brk_up)
        idx_d = np.flatnonzero(brk_dn)
        idx = np.sort(np.concatenate([idx_u, idx_d]))
        if len(idx) == 0:
            return None
        direction = np.where(np.isin(idx, idx_u), 1.0, -1.0)
        ext = np.where(direction > 0, l[idx], h[idx])
        stop = np.where(direction > 0, ext - stop_atr * atr[idx], ext + stop_atr * atr[idx])
        ep = c[idx] if entry == "close" else o[np.minimum(idx + 1, n - 1)]
        target = ep + direction * target_r * np.abs(ep - stop)
    else:
        raise ValueError(family)

    stop_pips = np.abs(ep - stop) / pip
    # reject broken geometry: fill price already at/beyond the intended stop
    # (matches verify_final_config.py and plan s.6 stop-distance rejection)
    keep = (stop_pips >= min_stop_pips) & (stop_pips > 0) & (np.abs(ep - stop) > 0)
    keep &= np.sign(ep - stop) == np.sign(direction.astype(float))
    if session is not None:
        hrs = server_hour(d["ts"][idx])
        keep &= np.isin(hrs, session)
    idx, direction, ep, stop, target, stop_pips = (
        idx[keep], direction[keep], ep[keep], stop[keep], target[keep], stop_pips[keep])
    if len(idx) == 0:
        return None
    return dict(idx=idx, direction=direction.astype(np.int8), entry=ep, stop=stop,
                target=target, stop_pips=stop_pips, atr=atr[idx],
                ts=d["ts"][idx])


def rolling_max_prior(x: np.ndarray, period: int) -> np.ndarray:
    out = np.full(len(x), np.nan)
    if len(x) <= period:
        return out
    st = np.lib.stride_tricks.sliding_window_view(x, period)[:-1]
    out[period:] = st.max(axis=1)
    return out


def rolling_min_prior(x: np.ndarray, period: int) -> np.ndarray:
    out = np.full(len(x), np.nan)
    if len(x) <= period:
        return out
    st = np.lib.stride_tricks.sliding_window_view(x, period)[:-1]
    out[period:] = st.min(axis=1)
    return out


def server_hour(ts_ms: np.ndarray) -> np.ndarray:
    return ((ts_ms // 3_600_000) + SERVER_OFF_H) % 24


# ---------------------------------------------------------------------------
# exit resolution (vectorised, pessimistic)
# ---------------------------------------------------------------------------
def resolve(sig: dict, d: dict, *, max_hold_bars: int = 4000,
            chunk: int = 4000) -> dict:
    """First-crossing exit scan. Returns win/exit_idx/exit_ts/R arrays aligned
    to the surviving signals (timeouts dropped)."""
    n = d["n"]
    h, l, ts = d["h"], d["l"], d["ts"]
    idx = sig["idx"]
    H = min(max_hold_bars, n)
    # auto-size the gather chunk so peak memory stays ~200 MB
    chunk = max(32, min(chunk, 4_000_000 // max(H, 1)))
    offs = np.arange(1, H + 1)

    win = np.zeros(len(idx), dtype=bool)
    exit_i = np.full(len(idx), -1, dtype=np.int64)
    resolved = np.zeros(len(idx), dtype=bool)
    ambiguous = np.zeros(len(idx), dtype=bool)

    for s in range(0, len(idx), chunk):
        e = min(s + chunk, len(idx))
        ci = idx[s:e]
        J = ci[:, None] + offs[None, :]
        valid = J < n
        Jc = np.where(valid, J, n - 1)
        dirn = sig["direction"][s:e]
        stop = sig["stop"][s:e]
        targ = sig["target"][s:e]

        Lw = l[Jc]
        Hw = h[Jc]
        if True:
            hs = np.where(dirn[:, None] > 0, Lw <= stop[:, None], Hw >= stop[:, None])
            ht = np.where(dirn[:, None] > 0, Hw >= targ[:, None], Lw <= targ[:, None])
        hs &= valid
        ht &= valid
        any_s = hs.any(axis=1)
        any_t = ht.any(axis=1)
        fs = np.where(any_s, hs.argmax(axis=1), H + 1)
        ft = np.where(any_t, ht.argmax(axis=1), H + 1)
        # pessimistic: stop wins ties (same bar)
        w = any_t & (ft < fs)
        win[s:e] = w
        first = np.minimum(np.where(any_s, fs, H + 1), np.where(any_t, ft, H + 1))
        resolved[s:e] = first <= H
        exit_i[s:e] = np.where(resolved[s:e], ci + first, -1)
        ambiguous[s:e] = any_s & any_t & (fs == ft)

    # Timeouts are NOT dropped (that would be a selection bias): they are closed
    # at market on the last scanned bar and booked at their real mark-to-market R.
    n = d["n"]
    to_exit = np.minimum(idx + H, n - 1)
    exit_i = np.where(resolved, exit_i, to_exit)
    c = d["c"]
    stop_dist = np.abs(sig["entry"] - sig["stop"])
    mtm = np.where(sig["direction"] > 0, c[exit_i] - sig["entry"],
                   sig["entry"] - c[exit_i]) / np.where(stop_dist > 0, stop_dist, 1.0)
    R = np.where(resolved, np.where(win, target_r_of(sig, np.ones(len(idx), bool)), -1.0), mtm)
    out = {k: v for k, v in sig.items()}
    out["win"] = R > 0
    out["resolved"] = resolved
    out["timed_out"] = ~resolved
    out["exit_idx"] = exit_i
    out["exit_ts"] = ts[exit_i]
    out["ambiguous"] = ambiguous
    out["R_gross"] = R
    return out


def target_r_of(sig: dict, keep: np.ndarray) -> np.ndarray:
    """Gross R of a winner = |target-entry| / |entry-stop| (== the target_r used)."""
    return np.abs(sig["target"][keep] - sig["entry"][keep]) / np.where(
        np.abs(sig["entry"][keep] - sig["stop"][keep]) > 0,
        np.abs(sig["entry"][keep] - sig["stop"][keep]), 1.0)


def expectancy(sig: dict, res: dict, sym: str, spread_scale: float = 1.0) -> dict:
    """Net expectancy in R, using the repo's canonical cost model."""
    if len(res["win"]) == 0:
        return dict(n=0, e_gross=0.0, e_net=0.0, cost_R=0.0, wr=0.0,
                    med_stop=0.0, pf=0.0, amb=0.0, to=0.0)
    cr = cost_R(sym, res["stop_pips"], spread_scale)
    e_gross = float(np.mean(res["R_gross"]))
    e_net = float(np.mean(res["R_gross"] - cr))
    gp = float(np.sum(np.clip(res["R_gross"] - cr, 0, None)))
    gl = float(-np.sum(np.clip(res["R_gross"] - cr, None, 0)))
    return dict(n=int(len(res["win"])), e_gross=e_gross, e_net=e_net,
                cost_R=float(np.mean(cr)), wr=float(np.mean(res["win"])),
                med_stop=float(np.median(res["stop_pips"])),
                pf=(gp / gl if gl > 0 else float("inf")),
                amb=float(np.mean(res["ambiguous"])),
                to=float(np.mean(res["timed_out"])))
