#!/usr/bin/env python3
"""
docs_v1_lab.py - honest validation of the strategies described in docs_v1/ (2026-09-29).

Pre-registration (criteria, trial budget, gates) lives in
docs/research/findings/findings_docs_v1_validation.md sections 1-4 and was committed BEFORE this
file existed. Do not change gates here to get a different verdict.

Engines (all defined by docs_v1, see the findings file for sources)
  E1  SMC core      : H4 bias -> M15 sweep of a swing -> M15 CHoCH -> OB/FVG zone -> limit
  E2  Asian raid    : sweep of the 00:00-06:00 London range in the 07:00-10:00 killzone -> CHoCH -> zone
  E3  FVG re-engage : impulse >= 2 ATR + 3-candle FVG -> limit at 50% of the gap
  E4  Rank book     : 20-day currency-strength rank, long strongest / short weakest, daily
  E5  Rank book 24h : 24h z-score currency-strength rank, 24h hold

Honesty rules implemented here (profile R2-R6)
  * signals use completed bars only; limit orders must be RE-TOUCHED on M5 bars after the signal bar closed
  * fills/exits are scanned on M5; same-bar stop/target ordering is resolved at two bounds
    (pessimistic: stop first; optimistic: target first); the "coin" bound picks one per position (seeded)
  * costs inside every trade: raw account (55% of standard spread + $7/lot RT) via validation.speed_lab.engine.cost_R
  * gap-through-stop fills at the open, never at the stop level
  * London wall clock (DST aware) for sessions

Usage
  python tools/docs_v1_lab.py --help
"""
from __future__ import annotations

import argparse
import dataclasses
import json
import math
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from validation.speed_lab.engine import (  # noqa: E402
    COMM_RT, RAW_SCALE, SPECS, SPREAD_STD, cost_R,
)

DATA_DIR = ROOT / "validation" / "HistoryData"
CACHE_DIR = Path("/tmp/docs_v1_cache")
OUT_DIR = Path("/tmp/docs_v1_out")
CACHE_DIR.mkdir(exist_ok=True)
OUT_DIR.mkdir(exist_ok=True)

ALL_PAIRS = ["EURUSD", "GBPUSD", "EURGBP", "AUDUSD", "NZDUSD", "USDCAD",
             "USDCHF", "USDJPY", "EURJPY", "GBPJPY", "XAUUSD"]
DOCS_PAIRS_E1 = ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD"]      # docs unified parameter sheet
FX10 = [p for p in ALL_PAIRS if p != "XAUUSD"]

MS_M5, MS_M15, MS_H1, MS_H4, MS_D1 = 300_000, 900_000, 3_600_000, 14_400_000, 86_400_000
LON = ZoneInfo("Europe/London")
NYC = ZoneInfo("America/New_York")

TRAIN = ("2022-09-11", "2024-09-11")
TEST = ("2024-09-11", "2026-09-11")
FORWARD = ("2026-09-13", "2026-09-30")


def ms(date_str: str) -> int:
    return int(datetime.strptime(date_str, "%Y-%m-%d").replace(tzinfo=timezone.utc).timestamp() * 1000)


# --------------------------------------------------------------------------------------
# data + timeframes
# --------------------------------------------------------------------------------------
def load_m5(sym: str, data_dir: Path = DATA_DIR) -> dict:
    files = sorted(data_dir.glob(f"{sym.lower()}-m5-2022-09-11_2026-*.csv"))
    if not files:
        raise FileNotFoundError(f"no M5 file for {sym} in {data_dir}")
    p = files[0]
    key = f"{p.parent.name}_{p.name}_{p.stat().st_size}.npy"
    npy = CACHE_DIR / key
    if npy.exists():
        a = np.load(npy)
    else:
        a = np.loadtxt(p, delimiter=",", skiprows=1, usecols=(0, 1, 2, 3, 4), dtype=np.float64)
        a = a[np.argsort(a[:, 0], kind="stable")]
        np.save(npy, a)
    return dict(ts=a[:, 0].astype(np.int64), o=a[:, 1], h=a[:, 2], l=a[:, 3], c=a[:, 4])


def resample(m5: dict, bucket_ms: int) -> dict:
    """OHLC bars keyed by bucket start (UTC floor). Bar k is complete at ts[k] + bucket_ms."""
    ts = m5["ts"]
    key = (ts // bucket_ms) * bucket_ms
    uniq, start = np.unique(key, return_index=True)
    end = np.append(start[1:], len(ts))
    return dict(
        ts=uniq.astype(np.int64),
        o=m5["o"][start], c=m5["c"][end - 1],
        h=np.maximum.reduceat(m5["h"], start), l=np.minimum.reduceat(m5["l"], start),
    )


def true_range(d: dict) -> np.ndarray:
    pc = np.concatenate([[d["c"][0]], d["c"][:-1]])
    return np.maximum(d["h"] - d["l"], np.maximum(np.abs(d["h"] - pc), np.abs(d["l"] - pc)))


def sma_incl(x: np.ndarray, n: int) -> np.ndarray:
    """mean of x[i-n+1..i] (includes bar i, NaN during warm-up)."""
    cs = np.concatenate([[0.0], np.cumsum(x)])
    out = np.full(len(x), np.nan)
    out[n - 1:] = (cs[n:] - cs[:-n]) / n
    return out


def london_parts(ts_ms: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """(minute_of_day, date_ordinal) in Europe/London wall clock for bar-START timestamps."""
    hours = ts_ms // MS_H1
    uh, inv = np.unique(hours, return_inverse=True)
    off = np.empty(len(uh), dtype=np.int64)
    for i, h in enumerate(uh):
        off[i] = int(datetime.fromtimestamp(int(h) * 3600, tz=LON).utcoffset().total_seconds())
    loc_ms = ts_ms + off[inv] * 1000
    mod = (loc_ms // 60_000) % 1440
    day = loc_ms // MS_D1
    return mod.astype(np.int64), day.astype(np.int64)


def fractals(h: np.ndarray, l: np.ndarray, k: int = 2) -> tuple[np.ndarray, np.ndarray]:
    """Fractal swing flags at index p (needs k bars each side; confirmed at index p+k)."""
    n = len(h)
    sh = np.zeros(n, bool)
    sl = np.zeros(n, bool)
    if n > 2 * k:
        core = slice(k, n - k)
        ok_h = np.ones(n - 2 * k, bool)
        ok_l = np.ones(n - 2 * k, bool)
        for j in range(1, k + 1):
            ok_h &= (h[core] > h[k - j:n - k - j]) & (h[core] > h[k + j:n - k + j])
            ok_l &= (l[core] < l[k - j:n - k - j]) & (l[core] < l[k + j:n - k + j])
        sh[core] = ok_h
        sl[core] = ok_l
    return sh, sl


@dataclass
class Bars:
    sym: str
    m5: dict
    sig: dict                    # signal-timeframe bars (M15 or H1), keyed by bar START
    h1: dict
    h4: dict
    atr_s: np.ndarray            # ATR(14) of M15, includes the bar itself
    sig_to_m5: np.ndarray        # first M5 index starting at/after the M15 bar's CLOSE
    bias: np.ndarray             # H4 bias visible after each M15 bar closes: +1/-1/0
    lon_min: np.ndarray          # London minute-of-day of each M15 bar START
    lon_day: np.ndarray
    h1_sw: dict                  # H1 swing arrays for structure trailing
    tf: int = 15                 # signal timeframe in minutes
    bar_ms: int = MS_M15


def h4_bias(h4: dict, fr: int = 2) -> np.ndarray:
    """EA HTFBias: last 3 confirmed swings; HH&HL -> +1, LH&LL -> -1, or BOS of newest swing. Value AFTER bar k closes."""
    h, l, c = h4["h"], h4["l"], h4["c"]
    sh, sl = fractals(h, l, fr)
    n = len(h)
    out = np.zeros(n, np.int8)
    hi, lo = [], []
    for k in range(n):
        p = k - fr
        if p >= 0:
            if sh[p]:
                hi.append(p)
            if sl[p]:
                lo.append(p)
        if len(hi) >= 2 and len(lo) >= 2:
            h0, h1_ = h[hi[-1]], h[hi[-2]]
            l0, l1_ = l[lo[-1]], l[lo[-2]]
            hh, hl_ = h0 > h1_, l0 > l1_
            lh, ll = h0 < h1_, l0 < l1_
            if (hh and hl_) or c[k] > h0:
                out[k] = 1
            elif (lh and ll) or c[k] < l0:
                out[k] = -1
    return out


def bars_from_m5(sym: str, m5: dict, tf: int = 15) -> Bars:
    bar_ms = tf * 60_000
    sig, h1, h4 = resample(m5, bar_ms), resample(m5, MS_H1), resample(m5, MS_H4)
    atr = sma_incl(true_range(sig), 14)
    close_sig = sig["ts"] + bar_ms
    sig_to_m5 = np.searchsorted(m5["ts"], close_sig, side="left")
    # H4 bias visible at signal-bar close: only H4 bars already COMPLETE at that moment
    h4_close = h4["ts"] + MS_H4
    n_done = np.searchsorted(h4_close, close_sig, side="right")
    hb = h4_bias(h4)
    bias = np.where(n_done > 0, hb[np.maximum(n_done - 1, 0)], 0).astype(np.int8)
    lmin, lday = london_parts(sig["ts"])
    sh1, sl1 = fractals(h1["h"], h1["l"], 2)
    p_hi, p_lo = np.flatnonzero(sh1), np.flatnonzero(sl1)
    h1_sw = dict(
        hi_t=h1["ts"][p_hi], hi_conf=h1["ts"][p_hi] + 3 * MS_H1, hi_p=h1["h"][p_hi],
        lo_t=h1["ts"][p_lo], lo_conf=h1["ts"][p_lo] + 3 * MS_H1, lo_p=h1["l"][p_lo],
    )
    return Bars(sym, m5, sig, h1, h4, atr, sig_to_m5, bias, lmin, lday, h1_sw, tf, bar_ms)


def build_bars(sym: str, data_dir: Path = DATA_DIR, tf: int = 15, _memo: dict = {}) -> Bars:
    key = (sym, str(data_dir), tf)
    if key not in _memo:
        _memo[key] = bars_from_m5(sym, load_m5(sym, data_dir), tf)
    return _memo[key]


# --------------------------------------------------------------------------------------
# configuration
# --------------------------------------------------------------------------------------
# Exit specs. targets: (level_R or "pool", fraction, stop_after_hit_in_R or None). runner: None | "h1" | ("atr", k)
EXITS = {
    # docs unified ladder (strategy-recommendation Step 4): 25% @1.5R (SL->+0.3R), 25% @3R (SL->+1R), 25% @pool, 25% runner
    "X1": dict(targets=[(1.5, .25, .3), (3.0, .25, 1.0), ("pool", .25, None)], runner="h1"),
    # round-1 EA exit: 50% @1.5R -> BE, remaining 50% trails ATRx2 and has a 3R (or liquidity) take profit
    "X2": dict(targets=[(1.5, .50, 0.0), ("pool3", .50, None)], runner=("atr", 2.0)),
    "RR2": dict(targets=[(2.0, 1.0, None)], runner=None),
    "RR3": dict(targets=[(3.0, 1.0, None)], runner=None),
    # E2 as written (max-roi): 25% @1.5R, 25% @3R, 50% to the opposing Asian extreme
    "X_E2": dict(targets=[(1.5, .25, .3), (3.0, .25, 1.0), ("pool", .50, None)], runner=None),
    # E3 as written (AAM Engine B): 30% @2R, 30% @4R, 40% trailing structure
    "X_E3": dict(targets=[(2.0, .30, None), (4.0, .30, None)], runner="h1"),
}


@dataclass
class Cfg:
    name: str
    engine: str                       # E1 | E2 | E3 | E4 | E5
    exit: str = "X1"
    entry: str = "dual"               # mid | front | dual
    bias_on: bool = True
    stop_buf: float = 0.25            # ATR buffer beyond the zone
    pairs: tuple = tuple(DOCS_PAIRS_E1)
    smt: bool = False                 # F1 synthetic-DXY non-confirmation gate
    regime: bool = False              # F2 ATR shock skip
    dead_money: bool = False          # F3
    dead_bars: int = 0                # M5 bars: 1.5x median bars-to-TP1 measured on TRAIN, set by the runner
    min_stop_pips: float = 25.0       # docs unified sheet
    sessions: tuple = ((420, 600), (780, 960))   # London minutes: 07:00-10:00, 13:00-16:00
    risk: float = 0.005
    sig_tf: int = 15                  # signal timeframe (minutes): 15 or 60
    expiry_bars: int = 8              # signal bars a limit stays live
    max_hold_m5: int = 2016           # 7 days
    # rank engines
    rank_lookback: int = 20
    rank_k: int = 4
    rank_hold_days: int = 5
    rank_stop_atr: float = 2.0
    rank_mode: str = "mom"            # mom | rev
    rank_flip_exit: bool = True
    z24: bool = False
    note: str = ""

    def to_json(self) -> dict:
        d = dataclasses.asdict(self)
        d["pairs"] = list(self.pairs)
        return d


# --------------------------------------------------------------------------------------
# E1 / E2 / E3 setup detection (long-frame trick: short = negated prices)
# --------------------------------------------------------------------------------------
def _frame(d: dict, direction: int):
    """Return (O,H,L,C) in long frame. Short trades are mirrored by negating prices."""
    if direction > 0:
        return d["o"], d["h"], d["l"], d["c"]
    return -d["o"], -d["l"], -d["h"], -d["c"]


def in_sessions(lmin_close: np.ndarray, sessions) -> np.ndarray:
    ok = np.zeros(len(lmin_close), bool)
    for a, b in sessions:
        ok |= (lmin_close >= a) & (lmin_close < b)
    return ok


def detect_setups(b: Bars, cfg: Cfg, lo_ts: int, hi_ts: int) -> list[dict]:
    """Raw setup events. Each event: t (M15 index of the bar whose close completes it), dir, zone (real prices),
    atr, pool (real price or nan). No portfolio/state logic here."""
    sig = b.sig
    n = len(sig["ts"])
    atr = b.atr_s
    close_ts = sig["ts"] + b.bar_ms
    lmin_close = (b.lon_min + b.tf) % 1440              # London minute of the bar CLOSE
    sess_ok = in_sessions(lmin_close, cfg.sessions)
    win_ok = (close_ts >= lo_ts) & (close_ts < hi_ts)
    events: list[dict] = []
    if cfg.engine in ("E1", "E2"):
        # Asian range per London day (00:00-06:00), known after 06:00
        if cfg.engine == "E2":
            asia_hi, asia_lo = _asian_range(b)
        sh_r, sl_r = fractals(sig["h"], sig["l"], 2)
        for direction in (1, -1):
            O, H, L, C = _frame(sig, direction)
            sw_low, sw_high = (sl_r, sh_r) if direction > 0 else (sh_r, sl_r)   # swings of the frame's low/high side
            # confirmed swing levels in frame prices, newest first, evaluated as of each bar k
            sweep_at = np.full(n, -1, np.int64)        # index of swept swing (p) or -1
            sweep_lvl = np.full(n, np.nan)
            choch_lvl = np.full(n, np.nan)
            lows_q: list[int] = []
            highs_q: list[int] = []
            for k in range(n):
                p = k - 2
                if p >= 0:
                    if sw_low[p]:
                        lows_q.append(p)
                    if sw_high[p]:
                        highs_q.append(p)
                if not (win_ok[max(k - 12, 0)] or win_ok[k]) or np.isnan(atr[k]):
                    continue
                if highs_q:
                    choch_lvl[k] = H[highs_q[-1]]
                if cfg.engine == "E1":
                    for p_ in reversed(lows_q[-6:]):
                        lvl = L[p_]
                        if L[k] < lvl and C[k] > lvl:
                            sweep_at[k], sweep_lvl[k] = p_, lvl
                            break
                else:  # E2: Asian range extreme of today (frame low side)
                    d_i = int(b.lon_day[k])
                    if d_i in asia_lo:
                        lvl = asia_lo[d_i] if direction > 0 else -asia_hi[d_i]
                        m0 = 420 <= b.lon_min[k] < 600
                        if m0 and L[k] < lvl and C[k] > lvl:
                            sweep_at[k], sweep_lvl[k] = 0, lvl
            # CHoCH time: first close above the pre-sweep swing high within 11 bars after the sweep
            for k in np.flatnonzero(sweep_at >= 0):
                lvl_c = choch_lvl[k]
                if np.isnan(lvl_c):
                    continue
                t_hit = -1
                for t in range(k + 1, min(k + 12, n)):
                    if C[t] > lvl_c:
                        t_hit = t
                        break
                if t_hit < 0 or not (win_ok[t_hit] and sess_ok[t_hit]) or np.isnan(atr[t_hit]):
                    continue
                if cfg.bias_on and cfg.engine == "E1" and b.bias[t_hit] != direction:
                    continue
                zone = _zone(O, H, L, C, k, t_hit, atr[t_hit])
                if zone is None:
                    continue
                z_lo, z_hi = zone
                # liquidity pool: newest confirmed opposing swing high (frame) as of t_hit
                pool = np.nan
                cand = [q for q in highs_q if q <= t_hit - 2]
                if cfg.engine == "E1" and cand:
                    pool = H[cand[-1]]
                if cfg.engine == "E2":
                    d_i = int(b.lon_day[k])
                    pool = asia_hi[d_i] if direction > 0 else -asia_lo[d_i]
                # events stay in FRAME coordinates (short = negated prices); execution also runs in the frame
                events.append(dict(t=int(t_hit), k=int(k), dir=direction, atr=float(atr[t_hit]),
                                   z_lo=float(z_lo), z_hi=float(z_hi), pool=float(pool), kind="ob"))
    elif cfg.engine == "E3":
        for direction in (1, -1):
            O, H, L, C = _frame(sig, direction)
            rng = H - L
            body = C - O
            for i in range(15, n - 1):
                t = i + 1
                if not (win_ok[t] and sess_ok[t]) or np.isnan(atr[t]):
                    continue
                a_prev = atr[i - 1]
                if np.isnan(a_prev) or rng[i] < 2.0 * a_prev or body[i] < 0.5 * rng[i]:
                    continue
                if L[i + 1] <= H[i - 1]:
                    continue                      # no 3-candle FVG
                if cfg.bias_on and b.bias[t] != direction:
                    continue
                z_lo, z_hi = H[i - 1], L[i + 1]
                origin = min(L[i - 1], L[i])
                events.append(dict(t=int(t), k=int(i), dir=direction, atr=float(atr[t]),
                                   z_lo=float(z_lo), z_hi=float(z_hi),
                                   pool=np.nan, kind="fvg", origin=float(origin)))
    return events


def _asian_range(b: Bars) -> tuple[dict, dict]:
    """London 00:00-06:00 high/low per London date, as dicts date_ordinal -> price."""
    sig = b.sig
    mask = (b.lon_min >= 0) & (b.lon_min < 360)
    hi: dict = {}
    lo: dict = {}
    for k in np.flatnonzero(mask):
        d = int(b.lon_day[k])
        hi[d] = max(hi.get(d, -np.inf), sig["h"][k])
        lo[d] = min(lo.get(d, np.inf), sig["l"][k])
    return hi, lo


def _zone(O, H, L, C, k: int, t: int, atr_t: float):
    """EA zone logic in long frame: newest down-candle near the sweep (order block), else the newest bullish FVG."""
    for a in range(t, max(k - 3, 1) - 1, -1):
        if C[a] < O[a] and L[a] <= L[k] + 1.5 * atr_t:
            z_hi, z_lo = max(O[a], H[a]), L[a]
            if z_hi > z_lo:
                return z_lo, z_hi
            break
    for a in range(t, max(k - 3, 2) - 1, -1):
        if a - 2 >= 0 and L[a] > H[a - 2]:
            return H[a - 2], L[a]
    return None


# --------------------------------------------------------------------------------------
# execution on M5 (long frame)
# --------------------------------------------------------------------------------------
_FRAMES: dict = {}


def m5_frame(b: Bars, direction: int) -> dict:
    key = (id(b), direction)
    if key not in _FRAMES:
        m5 = b.m5
        o, h, l, c = _frame(m5, direction)
        sw = b.h1_sw
        if direction > 0:
            sw_f = dict(t=sw["lo_t"], conf=sw["lo_conf"], p=sw["lo_p"])
        else:  # short frame: swing highs, negated
            sw_f = dict(t=sw["hi_t"], conf=sw["hi_conf"], p=-sw["hi_p"])
        _FRAMES[key] = dict(O=o, H=h, L=l, C=c, ts=m5["ts"], sw=sw_f)
    return _FRAMES[key]


def _resolve_targets(spec: dict, entry: float, R0: float, pool: float):
    tg, prev = [], 0.0
    for lvl, frac, sl_after in spec["targets"]:
        if lvl in ("pool", "pool3"):
            pr = (pool - entry) / R0 if not (pool != pool) else None
            if lvl == "pool":
                r = prev + 1.5 if pr is None else max(pr, prev + 0.5)
            else:
                r = 3.0 if pr is None else max(pr, 3.0)
            r = min(r, 10.0)
        else:
            r = float(lvl)
        tg.append((r, frac, sl_after))
        prev = r
    return tg


def sim_leg(fr: dict, entry: float, stop: float, j_fill: int, spec: dict, pool: float,
            atr_val: float, mode: str, dead_bars: int, max_hold: int):
    """Manage one filled leg. Returns (R in units of this leg's R0, exit index). Long frame, M5 bars."""
    O, H, L, C, TS = fr["O"], fr["H"], fr["L"], fr["C"], fr["ts"]
    n = len(L)
    end = min(j_fill + max_hold, n - 1)
    R0 = entry - stop
    if R0 <= 0 or j_fill >= n:
        return None
    opt = mode == "opt"
    tg = _resolve_targets(spec, entry, R0, pool)
    runner = spec["runner"]
    stages = [dict(level=entry + r * R0, frac=f, sl_after=s, r=r) for r, f, s in tg]
    rem_after = 1.0 - sum(f for _, f, _ in tg)
    if runner is not None and rem_after > 1e-9:
        stages.append(dict(level=np.inf, frac=rem_after, sl_after=None, r=None))
    trail_from = len(stages) if runner is None else (len(tg) if runner == "h1" else 1)

    def trail_arr(kind, pos, hi, t_stage_ms):
        if kind == "h1":
            sw = fr["sw"]
            i0 = int(np.searchsorted(sw["t"], t_stage_ms, side="left"))
            conf, p = sw["conf"][i0:], sw["p"][i0:]
            if len(conf) == 0:
                return np.full(hi - pos, -np.inf)
            ii = np.searchsorted(conf, TS[pos:hi], side="right") - 1
            arr = np.where(ii >= 0, p[np.maximum(ii, 0)], -np.inf)
            return np.maximum.accumulate(arr)
        # ATR chandelier from the stage start, includes the current bar's high (pessimistic)
        return np.maximum.accumulate(H[pos:hi]) - kind[1] * atr_val

    rem, realized, sl, pos, first = 1.0, 0.0, stop, j_fill, True
    skip_stop0 = False
    t_stage = TS[j_fill]
    for si, st in enumerate(stages):
        kind = None
        if si >= trail_from and runner is not None:
            kind = "h1" if runner == "h1" else runner
        hi = end + 1
        dead_j = None
        if si == 0 and dead_bars and dead_bars > 0:
            dead_j = min(j_fill + dead_bars, end)
            hi = dead_j + 1
        while True:
            if pos >= hi:
                res = ("end", hi - 1, C[min(hi - 1, n - 1)])
            else:
                Lw, Hw = L[pos:hi], H[pos:hi]
                if kind is None:
                    slv = np.full(hi - pos, sl)
                else:
                    slv = np.maximum(sl, trail_arr(kind, pos, hi, t_stage))
                stop_hit = Lw <= slv
                if skip_stop0:
                    stop_hit[0] = False
                    skip_stop0 = False
                tp_hit = Hw >= st["level"] if np.isfinite(st["level"]) else np.zeros(hi - pos, bool)
                if first and not opt:
                    tp_hit[0] = False            # a limit fill bar cannot also prove a target (order unknown)
                si_ = int(np.argmax(stop_hit)) if stop_hit.any() else 10 ** 9
                ti_ = int(np.argmax(tp_hit)) if tp_hit.any() else 10 ** 9
                if si_ == 10 ** 9 and ti_ == 10 ** 9:
                    res = ("end", hi - 1, C[hi - 1])
                elif si_ < ti_ or (si_ == ti_ and not opt):
                    j = pos + si_
                    px = slv[si_]
                    if j > pos and O[j] < px:     # gap through the stop fills at the open
                        px = O[j]
                    res = ("stop", j, px)
                else:
                    res = ("tp", pos + ti_, st["level"])
            first = False
            kind_res, j, px = res
            if kind_res == "end" and dead_j is not None and j == dead_j and hi == dead_j + 1:
                if (C[dead_j] - entry) / R0 < 0.5:
                    realized += rem * (C[dead_j] - entry) / R0
                    return realized, dead_j
                hi, pos, dead_j = end + 1, dead_j + 1, None
                continue
            break
        if kind_res == "stop":
            realized += rem * (px - entry) / R0
            return realized, j
        if kind_res == "end":
            realized += rem * (px - entry) / R0
            return realized, j
        # target hit
        realized += st["frac"] * st["r"]
        rem -= st["frac"]
        if st["sl_after"] is not None:
            sl = max(sl, entry + st["sl_after"] * R0)
        pos = j                          # the next stage is evaluated on the SAME bar in both bounds
        skip_stop0 = opt                 # optimistic: the freshly raised stop does not apply on that bar
        t_stage = TS[j]
        if rem <= 1e-9:
            return realized, j
    # all stages consumed without closing (should only happen when rem == 0)
    return realized, min(pos, end)


def leg_plan(ev: dict, cfg: Cfg, c_sig: float) -> tuple[float, list[tuple[float, float]]] | None:
    zl, zh, atr = ev["z_lo"], ev["z_hi"], ev["atr"]
    if ev["kind"] == "fvg":
        stop = ev["origin"] - 0.10 * atr
    else:
        stop = zl - cfg.stop_buf * atr
    front, mid = zh, zl + 0.5 * (zh - zl)
    if cfg.entry == "mid":
        legs = [(mid, 1.0)]
    elif cfg.entry == "front":
        legs = [(front, 1.0)]
    else:
        legs = [(front, 0.5), (mid, 0.5)]
    legs = [(e, w) for e, w in legs if e < c_sig and e > stop]    # limit must sit below the market
    if not legs:
        return None
    if len(legs) == 1:
        legs = [(legs[0][0], 1.0)]          # only one leg is placeable -> it carries the full risk
    return stop, legs


def sim_position(b: Bars, ev: dict, cfg: Cfg, mode: str):
    """Simulate one setup. Returns dict or None (not filled / invalid)."""
    d = ev["dir"]
    fr = m5_frame(b, d)
    _, _, _, Cf = _frame(b.sig, d)
    t = ev["t"]
    plan = leg_plan(ev, cfg, Cf[t])
    if plan is None:
        return None
    stop, legs = plan
    pip = SPECS[b.sym]["pip"]
    R0_min = min(e for e, _ in legs) - stop
    if R0_min / pip < cfg.min_stop_pips:
        return None
    j0 = int(b.sig_to_m5[t])
    j_exp = min(j0 + (b.tf // 5) * cfg.expiry_bars, len(fr["L"]))
    if j0 >= j_exp:
        return None
    spec = EXITS[cfg.exit]
    fills = []
    for entry, w in legs:
        seg = fr["L"][j0:j_exp] <= entry
        if not seg.any():
            continue
        fills.append((entry, w, j0 + int(np.argmax(seg))))
    if not fills:
        return dict(unfilled=True)         # a valid limit was placed and never re-touched
    # dual bracket: the second limit is cancelled if the first reaches +1R before the second fills
    if cfg.entry == "dual" and len(fills) == 2:
        e1, _, j1 = fills[0]
        e2, _, j2 = fills[1]
        lvl1 = e1 + 1.0 * (e1 - stop)
        seg = fr["H"][j1:j2] >= lvl1 if j2 > j1 else np.zeros(0, bool)
        if seg.any():
            fills = fills[:1]
    R, cost, cost15, wsum, j_exit, stops = 0.0, 0.0, 0.0, 0.0, 0, []
    first_fill = min(f[2] for f in fills)
    for entry, w, jf in fills:
        r = sim_leg(fr, entry, stop, jf, spec, ev["pool"], ev["atr"], mode,
                    cfg.dead_bars if cfg.dead_money else 0, cfg.max_hold_m5)
        if r is None:
            continue
        Rleg, jx = r
        sp = (entry - stop) / pip
        R += w * Rleg
        cost += w * float(cost_R(b.sym, sp))
        cost15 += w * float(cost_R(b.sym, sp, 1.5))
        wsum += w
        stops.append(sp)
        j_exit = max(j_exit, jx)
    if wsum == 0:
        return None
    ts = fr["ts"]
    return dict(R=R, cost=cost, cost15=cost15, wsum=wsum, j_fill=first_fill, j_exit=j_exit, t_fill=int(ts[first_fill]),
                t_exit=int(ts[j_exit]), stop_pips=float(np.mean(stops)), dir=d, t_sig=int(b.sig["ts"][t] + b.bar_ms),
                sym=b.sym, kind=ev["kind"])


# --------------------------------------------------------------------------------------
# filters
# --------------------------------------------------------------------------------------
_DXY: dict = {}


def synthetic_dxy(data_dir: Path) -> tuple[np.ndarray, np.ndarray]:
    """(sig bar-start timestamps, log-DXY) from EURUSD/USDJPY/GBPUSD/USDCAD/USDCHF closes (USDSEK unavailable)."""
    key = str(data_dir)
    if key in _DXY:
        return _DXY[key]
    w = dict(EURUSD=-0.576, USDJPY=0.136, GBPUSD=-0.119, USDCAD=0.091, USDCHF=0.036)
    base = build_bars("EURUSD", data_dir, 15).sig
    ts = base["ts"]
    total = np.zeros(len(ts))
    for sym, wt in w.items():
        m = build_bars(sym, data_dir, 15).sig
        idx = np.searchsorted(m["ts"], ts, side="right") - 1
        c = np.where(idx >= 0, m["c"][np.maximum(idx, 0)], np.nan)
        total += wt * np.log(c)
    _DXY[key] = (ts, total)
    return _DXY[key]


USD_QUOTE = {"EURUSD", "GBPUSD", "AUDUSD", "NZDUSD", "XAUUSD"}
USD_BASE = {"USDJPY", "USDCAD", "USDCHF"}


def apply_filters(b: Bars, events: list[dict], cfg: Cfg, data_dir: Path) -> list[dict]:
    out = events
    if cfg.regime:
        ratio = b.atr_s / np.concatenate([[np.nan], sma_incl(b.atr_s, 20 * (1440 // b.tf))[:-1]])
        out = [e for e in out if not (ratio[e["t"]] > 1.8)]
    if cfg.smt and b.sym in (USD_QUOTE | USD_BASE):
        ts_d, dx = synthetic_dxy(data_dir)
        s = 1 if b.sym in USD_QUOTE else -1
        keep = []
        for e in out:
            k = e["k"] if e["kind"] == "ob" else e["t"]
            i = int(np.searchsorted(ts_d, b.sig["ts"][k], side="left"))
            if i < 30 or i >= len(dx):
                continue
            c = e["dir"] * s                      # DXY direction that would CONFIRM the sweep
            prior = dx[i - 24:i]
            confirmed = dx[i] > prior.max() if c > 0 else dx[i] < prior.min()
            if not confirmed:
                keep.append(e)                    # non-confirmation = valid raid (docs F1)
        out = keep
    return out


# --------------------------------------------------------------------------------------
# per-symbol state machine for E1/E2/E3
# --------------------------------------------------------------------------------------
def run_symbol(b: Bars, cfg: Cfg, lo_ts: int, hi_ts: int, data_dir: Path = DATA_DIR) -> list[dict]:
    events = detect_setups(b, cfg, lo_ts, hi_ts)
    events = apply_filters(b, events, cfg, data_dir)
    events.sort(key=lambda e: (e["t"], -e["dir"]))
    trades, busy_until, used = [], -1, set()
    for ev in events:
        j0 = int(b.sig_to_m5[ev["t"]])
        if j0 <= busy_until:
            continue
        key = (ev["dir"], ev["k"])
        if key in used:
            continue
        used.add(key)
        pess = sim_position(b, ev, cfg, "pess")
        if pess is None:
            continue                        # no order was placed (geometry / min-stop rule)
        if pess.get("unfilled"):
            busy_until = j0 + (b.tf // 5) * cfg.expiry_bars   # the resting limit blocks the symbol until it expires
            continue
        opt = sim_position(b, ev, cfg, "opt") or pess
        busy_until = pess["j_exit"]
        # Two tie-break conventions are simulated. A path-dependent ladder (bank a target, ratchet the stop) is NOT monotone
        # in the tie-break: on real bars the "optimistic" convention can end below the "pessimistic" one. So the reported
        # pessimistic / optimistic results are the per-trade MIN / MAX of the two conventions (a bound over the two
        # conventions, not over every possible intrabar path). The trade SET and timing come from the pessimistic run.
        r_a, r_b = pess.pop("R"), opt["R"]
        pess["R_pess"], pess["R_opt"] = min(r_a, r_b), max(r_a, r_b)
        pess["R_conv_pess"], pess["R_conv_opt"] = r_a, r_b
        pess["t_exit_opt"] = opt["t_exit"]
        pess["risk"] = cfg.risk
        pess["engine"] = cfg.engine
        trades.append(pess)
    return trades


# --------------------------------------------------------------------------------------
# E4 / E5 rank engines (currency-strength books). Daily decision at NY 17:00.
# --------------------------------------------------------------------------------------
CCY = ["AUD", "CAD", "CHF", "EUR", "GBP", "JPY", "NZD", "USD"]


def _pair_ccy(sym: str) -> tuple[str, str]:
    return sym[:3], sym[3:]


def _ny_bucket(ts_ms: np.ndarray) -> np.ndarray:
    """NY trading-day key: the day starts at 17:00 New York (DST aware). Vectorised via per-hour offsets."""
    hours = ts_ms // MS_H1
    uh, inv = np.unique(hours, return_inverse=True)
    off = np.empty(len(uh), np.int64)
    for i, h in enumerate(uh):
        dt = datetime.fromtimestamp(int(h) * 3600, tz=timezone.utc).astimezone(NYC)
        off[i] = int(dt.utcoffset().total_seconds() * 1000)
    local = ts_ms + off[inv] - 17 * MS_H1
    return local // MS_D1


def build_daily(sym: str, data_dir: Path = DATA_DIR, _memo: dict = {}) -> dict:
    """D1 bars on the NY-17:00 clock: key, o,h,l,c, j_next (index of the first M5 bar AFTER the day closes)."""
    ck = (sym, str(data_dir))
    if ck in _memo:
        return _memo[ck]
    m5 = load_m5(sym, data_dir)
    key = _ny_bucket(m5["ts"])
    starts = np.flatnonzero(np.r_[True, key[1:] != key[:-1]])
    ends = np.r_[starts[1:], len(key)]
    d = dict(key=key[starts], o=m5["o"][starts], h=np.maximum.reduceat(m5["h"], starts),
             l=np.minimum.reduceat(m5["l"], starts), c=m5["c"][ends - 1], j_next=ends,
             n=(ends - starts))
    # bucket key labels the calendar day the NY trading day STARTS on (1970-01-01 = Thursday).
    # d["dow"] = weekday the trading day ENDS on (17:00 NY), 0=Mon..6=Sun; the Thursday-17:00 -> Friday-17:00 day is 4.
    d["dow"] = (d["key"] + 4) % 7
    _memo[ck] = d
    return d


def rank_signals(data_dir: Path, cfg: Cfg) -> dict:
    """Return per-decision-day arrays aligned on the common day index: keys, diff[pair]=strength(base)-strength(quote)."""
    pairs = list(FX10)
    ds = {p: build_daily(p, data_dir) for p in pairs}
    common = ds[pairs[0]]["key"]
    for p in pairs[1:]:
        common = np.intersect1d(common, ds[p]["key"])
    # a decision day needs a full session (drop short partial buckets, e.g. holidays / the Sunday stub)
    idx = {p: np.searchsorted(ds[p]["key"], common) for p in pairs}
    full = np.ones(len(common), bool)
    for p in pairs:
        full &= ds[p]["n"][idx[p]] >= 150
    common, idx = common[full], {p: idx[p][full] for p in pairs}
    logc = np.column_stack([np.log(ds[p]["c"][idx[p]]) for p in pairs])
    A = np.zeros((len(pairs), len(CCY)))
    for i, p in enumerate(pairs):
        bq, qq = _pair_ccy(p)
        A[i, CCY.index(bq)], A[i, CCY.index(qq)] = 1.0, -1.0
    P = np.linalg.pinv(A)                                   # min-norm => strengths sum to zero
    L = cfg.rank_lookback
    if cfg.z24:
        r = np.vstack([np.full((1, len(pairs)), np.nan), np.diff(logc, axis=0)])
        sd = np.full_like(r, np.nan)
        for i in range(60, len(r)):
            sd[i] = r[i - 60:i].std(axis=0, ddof=1)       # prior 60 days only
        R = r / sd
    else:
        R = np.vstack([np.full((L, len(pairs)), np.nan), logc[L:] - logc[:-L]])
    S = R @ P.T
    diff = np.column_stack([S[:, CCY.index(_pair_ccy(p)[0])] - S[:, CCY.index(_pair_ccy(p)[1])] for p in pairs])
    # ATR(14) of D1 on the same clock, known at the decision (includes the day just closed)
    atr = np.column_stack([_daily_atr(ds[p], 14)[idx[p]] for p in pairs])
    return dict(pairs=pairs, key=common, diff=diff, atr=atr, idx=idx, ds=ds)


def _daily_atr(d: dict, n: int) -> np.ndarray:
    pc = np.r_[np.nan, d["c"][:-1]]
    tr = np.maximum(d["h"] - d["l"], np.maximum(np.abs(d["h"] - pc), np.abs(d["l"] - pc)))
    tr[0] = d["h"][0] - d["l"][0]
    return sma_incl(tr, n)


def run_rank(cfg: Cfg, lo_ts: int, hi_ts: int, data_dir: Path = DATA_DIR) -> list[dict]:
    sg = rank_signals(data_dir, cfg)
    pairs, diff, atr, idx, ds = sg["pairs"], sg["diff"], sg["atr"], sg["idx"], sg["ds"]
    m5 = {p: load_m5(p, data_dir) for p in pairs}
    trades, open_pos = [], {}                # sym -> dict(dir, j_fill, stop, entry, day0)
    sgn_mode = 1 if cfg.rank_mode == "mom" else -1
    K = cfg.rank_k
    for i in range(len(sg["key"])):
        if np.isnan(diff[i]).any() or np.isnan(atr[i]).any():
            continue
        dow_close = int(ds[pairs[0]]["dow"][idx[pairs[0]][i]])        # weekday the trading day ends on
        t_dec = int(m5[pairs[0]]["ts"][ds[pairs[0]]["j_next"][idx[pairs[0]][i]] - 1]) + MS_M5
        if t_dec < lo_ts:
            continue
        if t_dec >= hi_ts:
            break
        desired = sgn_mode * np.sign(diff[i])
        order = np.argsort(-np.abs(diff[i]))
        top = {pairs[j]: int(desired[j]) for j in order[:K]}
        friday = dow_close == 4
        # ---- exits at this decision
        for sym in list(open_pos):
            pos = open_pos[sym]
            age = i - pos["i0"]
            j = pairs.index(sym)
            flip = cfg.rank_flip_exit and desired[j] != pos["dir"]
            if friday or age >= cfg.rank_hold_days or flip or (not cfg.rank_flip_exit and age >= 1):
                jn = int(ds[sym]["j_next"][idx[sym][i]])
                if friday:      # flat before the weekend: exit at the Friday 17:00 close, NOT at the Sunday-open gap
                    _close_rank(trades, cfg, sym, pos, m5[sym], jn - 1, data_dir, at_close=True)
                else:
                    _close_rank(trades, cfg, sym, pos, m5[sym], jn, data_dir)
                del open_pos[sym]
        # ---- entries (never on Friday: the book is flat over the weekend)
        if friday:
            continue
        for sym, dr in top.items():
            if sym in open_pos or len(open_pos) >= K:
                continue
            j = pairs.index(sym)
            jn = int(ds[sym]["j_next"][idx[sym][i]])
            if jn >= len(m5[sym]["ts"]) - 1:
                continue
            entry = float(m5[sym]["o"][jn])
            open_pos[sym] = dict(dir=dr, j0=jn, entry=entry, stop=entry - dr * cfg.rank_stop_atr * atr[i][j],
                                 dist=cfg.rank_stop_atr * float(atr[i][j]), i0=i)
    for sym, pos in list(open_pos.items()):        # anything still open at window end is closed at the last bar before hi_ts
        jx = int(np.searchsorted(m5[sym]["ts"], hi_ts, side="left"))
        _close_rank(trades, cfg, sym, pos, m5[sym], jx, data_dir)
    return trades


def _close_rank(trades, cfg, sym, pos, m5, j_exit, data_dir, at_close=False):
    j_exit = int(min(j_exit, len(m5["ts"]) - 1))
    j0, d, stop, entry, dist = pos["j0"], pos["dir"], pos["stop"], pos["entry"], pos["dist"]
    if j_exit < j0 or (j_exit == j0 and not at_close):
        return
    upto = j_exit + 1 if at_close else j_exit          # at_close: bar j_exit is traded through, exit at its close
    seg_h, seg_l = m5["h"][j0:upto], m5["l"][j0:upto]
    hit = (seg_l <= stop) if d > 0 else (seg_h >= stop)
    if hit.any():
        jj = j0 + int(np.argmax(hit))
        o = float(m5["o"][jj])
        px = min(stop, o) if d > 0 else max(stop, o)     # gap through the stop fills at the open
        jx = jj
    else:
        px, jx = (float(m5["c"][j_exit]) if at_close else float(m5["o"][j_exit])), j_exit
    sp = dist / SPECS[sym]["pip"]
    Rg = d * (px - entry) / dist
    c, c15 = float(cost_R(sym, sp)), float(cost_R(sym, sp, 1.5))
    trades.append(dict(R_pess=Rg, R_opt=Rg, cost=c, cost15=c15, wsum=1.0, stop_pips=sp, dir=d, sym=sym,
                       kind="rank", engine=cfg.engine, risk=cfg.risk, t_fill=int(m5["ts"][j0]),
                       t_exit=int(m5["ts"][jx]), t_exit_opt=int(m5["ts"][jx]), t_sig=int(m5["ts"][j0])))


# --------------------------------------------------------------------------------------
# config registry (FIXED before any Stage A/B run; see ledger in the findings file)
# --------------------------------------------------------------------------------------
def _c(name, engine, **kw) -> Cfg:
    if engine == "E2":
        kw.setdefault("sessions", ((420, 600),))
    kw.setdefault("min_stop_pips", 0.0)
    return Cfg(name=name, engine=engine, **kw)


def _registry() -> dict[str, Cfg]:
    R: dict[str, Cfg] = {}

    def add(c):
        assert c.name not in R
        R[c.name] = c

    # ---- Stage A: docs as written (25-pip floor ON, docs pair sheet), 6 configs
    add(Cfg("A1_E1_X1", "E1", exit="X1", entry="dual"))
    add(Cfg("A2_E1_X2", "E1", exit="X2", entry="mid"))
    add(Cfg("A3_E2_X1", "E2", exit="X1", entry="dual", sessions=((420, 600),)))
    add(Cfg("A4_E3_X1", "E3", exit="X1", entry="mid"))
    add(Cfg("A5_E4_mom20", "E4", rank_lookback=20, rank_k=4, rank_hold_days=5, rank_flip_exit=True, rank_stop_atr=2.0))
    add(Cfg("A6_E5_z24", "E5", z24=True, rank_k=4, rank_hold_days=1, rank_flip_exit=False, rank_stop_atr=2.0))
    # ---- Stage B: TRAIN tuning, E1/E2/E3 only (the rank engines have no allowed Stage B dimension)
    E1 = dict(sig_tf=60, exit="X1", entry="dual")
    add(_c("B01_E1_m15_X1", "E1", sig_tf=15, exit="X1", entry="dual"))
    add(_c("B02_E1_m15_X2mid", "E1", sig_tf=15, exit="X2", entry="mid"))
    add(_c("B03_E1_h1_X1", "E1", **E1))
    add(_c("B04_E1_h1_X2mid", "E1", sig_tf=60, exit="X2", entry="mid"))
    add(_c("B05_E1_h1_RR2mid", "E1", sig_tf=60, exit="RR2", entry="mid"))
    add(_c("B06_E1_h1_RR3mid", "E1", sig_tf=60, exit="RR3", entry="mid"))
    add(_c("B07_E1_h1_X1_min25", "E1", min_stop_pips=25.0, **E1))
    add(_c("B08_E1_h1_X1_front", "E1", sig_tf=60, exit="X1", entry="front"))
    add(_c("B09_E1_h1_X1_biasoff", "E1", bias_on=False, **E1))
    add(_c("B10_E1_h1_X1_buf05", "E1", stop_buf=0.5, **E1))
    add(_c("B11_E1_h1_X1_all11", "E1", pairs=tuple(ALL_PAIRS), **E1))
    add(_c("B12_E1_h1_X1_F1", "E1", smt=True, **E1))
    add(_c("B13_E1_h1_X1_F2", "E1", regime=True, **E1))
    add(_c("B14_E1_h1_X1_dead", "E1", dead_money=True, **E1))
    E2 = dict(sig_tf=15, exit="X1", entry="dual")
    add(_c("B15_E2_m15_X1", "E2", **E2))
    add(_c("B16_E2_m15_X2mid", "E2", sig_tf=15, exit="X2", entry="mid"))
    add(_c("B17_E2_m15_RR2mid", "E2", sig_tf=15, exit="RR2", entry="mid"))
    add(_c("B18_E2_m15_X1_min25", "E2", min_stop_pips=25.0, **E2))
    add(_c("B19_E2_m15_X1_buf05", "E2", stop_buf=0.5, **E2))
    add(_c("B20_E2_m15_X1_all11", "E2", pairs=tuple(ALL_PAIRS), **E2))
    add(_c("B21_E2_m15_X1_F1", "E2", smt=True, **E2))
    add(_c("B22_E2_h1_X1", "E2", sig_tf=60, exit="X1", entry="dual"))
    add(_c("B23_E2_m15_X1_front", "E2", sig_tf=15, exit="X1", entry="front"))
    E3 = dict(sig_tf=15, exit="X1", entry="mid")
    add(_c("B24_E3_m15_X1", "E3", **E3))
    add(_c("B25_E3_h1_X1", "E3", sig_tf=60, exit="X1", entry="mid"))
    add(_c("B26_E3_m15_X2", "E3", sig_tf=15, exit="X2", entry="mid"))
    add(_c("B27_E3_m15_RR2", "E3", sig_tf=15, exit="RR2", entry="mid"))
    add(_c("B28_E3_m15_X1_biasoff", "E3", bias_on=False, **E3))
    add(_c("B29_E3_m15_X1_all11", "E3", pairs=tuple(ALL_PAIRS), **E3))
    add(_c("B30_E3_m15_X1_F2", "E3", regime=True, **E3))
    add(_c("B31_E3_m15_X1_min25", "E3", min_stop_pips=25.0, **E3))
    add(_c("B32_E3_m15_X1_front", "E3", sig_tf=15, exit="X1", entry="front"))
    return R


CONFIGS = _registry()


# --------------------------------------------------------------------------------------
# running a config over a window
# --------------------------------------------------------------------------------------
WINDOWS = {"train": TRAIN, "test": TEST, "forward": FORWARD}


def _run_sym_task(args):
    cfg_d, sym, lo, hi, data_dir = args
    pairs = cfg_d.pop("pairs")
    cfg = Cfg(**{**cfg_d, "pairs": tuple(pairs)})
    b = build_bars(sym, Path(data_dir), cfg.sig_tf)
    return run_symbol(b, cfg, lo, hi, Path(data_dir))


def resolve_dead_bars(cfg: Cfg, data_dir: Path = DATA_DIR) -> Cfg:
    """F3 threshold, measured on TRAIN only: 1.5 x median hold (M5 bars) of the dead-money-free twin's trades."""
    if not cfg.dead_money or cfg.dead_bars:
        return cfg
    twin = dataclasses.replace(cfg, dead_money=False)
    tr = run_config(twin, "train", data_dir, workers=1)
    hold = np.array([(t["t_exit"] - t["t_fill"]) / MS_M5 for t in tr])
    return dataclasses.replace(cfg, dead_bars=int(1.5 * np.median(hold)))


def run_config(cfg: Cfg, window: str, data_dir: Path = DATA_DIR, workers: int = 2) -> list[dict]:
    lo, hi = ms(WINDOWS[window][0]), ms(WINDOWS[window][1])
    if cfg.engine in ("E4", "E5"):
        return run_rank(cfg, lo, hi, data_dir)
    cfg = resolve_dead_bars(cfg, data_dir)
    tasks = [(cfg.to_json(), s, lo, hi, str(data_dir)) for s in cfg.pairs]
    if workers > 1 and len(tasks) > 1:
        import multiprocessing as mp
        with mp.get_context("fork").Pool(workers) as pool:
            res = pool.map(_run_sym_task, tasks)
    else:
        res = [_run_sym_task(t) for t in tasks]
    trades = [t for r in res for t in r]
    trades.sort(key=lambda t: (t["t_fill"], t["sym"]))
    return trades


# --------------------------------------------------------------------------------------
# statistics
# --------------------------------------------------------------------------------------
def _pf(x: np.ndarray) -> float:
    g, l = x[x > 0].sum(), -x[x < 0].sum()
    return float("inf") if l == 0 and g > 0 else (g / l if l > 0 else float("nan"))


def net_R(trades: list[dict], bound: str = "pess", spread: float = 1.0) -> np.ndarray:
    if not trades:
        return np.zeros(0)
    Rp = np.array([t["R_pess"] for t in trades]); Ro = np.array([t["R_opt"] for t in trades])
    c = np.array([t["cost"] if spread == 1.0 else t["cost15"] for t in trades])
    g = {"pess": Rp, "opt": Ro, "coin": 0.5 * (Rp + Ro)}[bound]      # coin = midpoint (exact expectation for a fair coin per ambiguity)
    return g - c


def day_key(ts_ms: np.ndarray) -> np.ndarray:
    return _ny_bucket(ts_ms)


def bootstrap_lb(trades: list[dict], B: int = 10_000, q: float = 10.0, seed: int = 20260929) -> float:
    """Day-block bootstrap of expectancy (ratio estimator sum(net)/sum(n) over resampled trade-days). q-th percentile."""
    if len(trades) < 5:
        return float("nan")
    x = net_R(trades)
    dk = day_key(np.array([t["t_fill"] for t in trades], dtype=np.int64))
    u, inv = np.unique(dk, return_inverse=True)
    S = np.bincount(inv, weights=x); N = np.bincount(inv).astype(float)
    rng = np.random.default_rng(seed)
    out = np.empty(B)
    step = 1000
    for a in range(0, B, step):
        idx = rng.integers(0, len(u), size=(min(step, B - a), len(u)))
        out[a:a + step] = S[idx].sum(1) / N[idx].sum(1)
    return float(np.percentile(out, q))


def halves(trades: list[dict], edges: list[str]) -> list[float]:
    e = [ms(x) for x in edges]
    res = []
    for a, b in zip(e[:-1], e[1:]):
        sub = [t for t in trades if a <= t["t_fill"] < b]
        res.append(float(net_R(sub).mean()) if sub else float("nan"))
    return res


TRAIN_EDGES = ["2022-09-11", "2023-09-11", "2024-09-11"]
TEST_EDGES = ["2024-09-11", "2025-03-11", "2025-09-11", "2026-03-11", "2026-09-11"]


def stats(trades: list[dict], edges: list[str], B: int = 2000) -> dict:
    if not trades:
        return dict(n=0)
    x = net_R(trades); xo = net_R(trades, "opt"); xc = net_R(trades, "coin"); x15 = net_R(trades, "pess", 1.5)
    gross = np.array([t["R_pess"] for t in trades])
    syms = sorted({t["sym"] for t in trades})
    by = {s: float(x[[t["sym"] == s for t in trades]].sum()) for s in syms}
    top = max(by, key=lambda s: by[s])
    tot = x.sum()
    keep = np.array([t["sym"] != top for t in trades])
    cum = np.cumsum(x)
    return dict(
        n=len(x), wr=float((x > 0).mean()), exp=float(x.mean()), pf=_pf(x), sumR=float(tot),
        exp_gross=float(gross.mean()), exp_opt=float(xo.mean()), exp_coin=float(xc.mean()),
        pf_opt=_pf(xo), exp_x15=float(x15.mean()), pf_x15=_pf(x15),
        cost_mean_R=float(np.mean([t["cost"] for t in trades])),
        stop_pips_med=float(np.median([t["stop_pips"] for t in trades])),
        halves=halves(trades, edges), lb90=bootstrap_lb(trades, B=B),
        top_pair=top, top_share=float(by[top] / tot) if tot > 0 else float("nan"),
        exp_ex_top=float(x[keep].mean()) if keep.any() else float("nan"),
        maxdd_R=float((np.maximum.accumulate(cum) - cum).max()),
        by_pair={s: round(v, 2) for s, v in by.items()},
    )


def train_score(st: dict) -> float:
    return st["exp"] * math.sqrt(st["n"]) if st.get("n") else float("-inf")


def is_candidate(st: dict) -> bool:
    return (st.get("n", 0) >= 120 and st["pf"] >= 1.15 and st["exp"] > 0
            and all(h > 0 for h in st["halves"]))


# --------------------------------------------------------------------------------------
# account simulation (C-prop / C-slot1)
# --------------------------------------------------------------------------------------
def account_sim(trades: list[dict], start: float = 2500.0, risk: float = 0.005, max_conc: int = 4,
                day_halt: float = 0.022, floor: float = 2250.0, firm_day: float = 0.05,
                bound: str = "pess") -> dict:
    """Realised-balance account walk. Entries are skipped when the concurrency cap is full, the symbol is already open,
    the day is halted (realised day loss <= -2.2% of the day-start balance) or the floor was breached.
    Open-trade floating loss is NOT marked (limit of the model, disclosed)."""
    import heapq
    if not trades:
        return dict(n_taken=0)
    order = sorted(range(len(trades)), key=lambda i: trades[i]["t_fill"])
    xnet = net_R(trades, bound)
    exits = np.array([t["t_exit" if bound == "pess" else "t_exit_opt"] for t in trades], dtype=np.int64)
    dk_exit = day_key(exits)
    bal, peak, maxdd = start, start, 0.0
    day_start: dict[int, float] = {}
    day_pnl: dict[int, float] = {}
    heap: list = []                         # (t_exit, i, pnl, sym)
    open_syms: dict[str, int] = {}
    taken = skipped = 0
    breach = False
    worst_day = 0.0

    def realise(upto):
        nonlocal bal, peak, maxdd, breach, worst_day
        while heap and heap[0][0] <= upto:
            te, i, pnl, sym = heapq.heappop(heap)
            d = int(dk_exit[i])
            day_start.setdefault(d, bal)
            bal += pnl
            day_pnl[d] = day_pnl.get(d, 0.0) + pnl
            peak = max(peak, bal)
            maxdd = max(maxdd, (peak - bal) / start)
            worst_day = min(worst_day, day_pnl[d] / day_start[d])
            open_syms[sym] -= 1
            if bal < floor:
                breach = True

    dk_fill = day_key(np.array([trades[i]["t_fill"] for i in order], dtype=np.int64))
    for pos, i in enumerate(order):
        t = trades[i]
        realise(t["t_fill"])
        if breach:
            skipped += 1
            continue
        d = int(dk_fill[pos])
        ds = day_start.get(d, bal)
        halted = day_pnl.get(d, 0.0) / ds <= -day_halt
        n_open = sum(open_syms.values())
        if halted or n_open >= max_conc or open_syms.get(t["sym"], 0) > 0:
            skipped += 1
            continue
        day_start.setdefault(d, bal)
        pnl = bal * risk * float(xnet[i]) * (t["risk"] / risk if risk else 1.0)
        heapq.heappush(heap, (int(exits[i]), i, pnl, t["sym"]))
        open_syms[t["sym"]] = open_syms.get(t["sym"], 0) + 1
        taken += 1
    realise(2 ** 62)
    return dict(n_taken=taken, n_skipped=skipped, final_pct=100 * (bal / start - 1), maxdd_pct=100 * maxdd,
                worst_day_pct=100 * worst_day, floor_breach=bool(breach or bal < floor),
                day_over_firm=bool(worst_day <= -firm_day))


def gates_test(st: dict, acc: dict) -> dict:
    """Gates T1-T9 on TEST stats. Returns {gate: (pass|fail|inconclusive, text)}."""
    g = {}
    g["T1"] = (st["n"] >= 150, f"n={st['n']}")
    g["T2"] = (st["exp"] >= 0.10 and st["lb90"] > 0, f"exp={st['exp']:+.3f} lb90={st['lb90']:+.3f}")
    g["T3"] = (st["pf"] >= 1.20, f"pf={st['pf']:.2f}")
    g["T4"] = (st["exp_x15"] > 0, f"exp@1.5x spread={st['exp_x15']:+.3f}")
    hp = sum(1 for h in st["halves"] if h == h and h > 0)
    g["T5"] = (hp >= 3, f"half-years {[round(h, 3) for h in st['halves']]}")
    g["T6"] = (not acc["floor_breach"] and not acc["day_over_firm"] and acc["maxdd_pct"] <= 8.0,
               f"maxDD={acc['maxdd_pct']:.1f}% worstDay={acc['worst_day_pct']:.1f}% floor={acc['floor_breach']}")
    g["T7"] = (st["top_share"] <= 0.5 and st["exp_ex_top"] > 0, f"top={st['top_pair']} {st['top_share']:.0%} ex-top exp={st['exp_ex_top']:+.3f}")
    susp = []
    if acc.get("maxdd_pct", 9) < 1.0: susp.append("DD<1%")
    if st["pf"] > 3: susp.append("PF>3")
    if (st["exp"] > 0) != (st["exp_opt"] > 0): susp.append("sign flip between bounds")
    g["T8"] = (not susp, ", ".join(susp) or "none")
    g["T9"] = (st["exp_coin"] >= st["exp"] and st["exp_coin"] > 0, f"coin={st['exp_coin']:+.3f} pess={st['exp']:+.3f} opt={st['exp_opt']:+.3f}")
    return g


# --------------------------------------------------------------------------------------
# null calibration: random entries through the SAME execution model (diagnostic, not a trial)
# --------------------------------------------------------------------------------------
def null_calibration(cfg: Cfg, window: str = "train", n_per_pair: int = 600, seed: int = 7,
                     data_dir: Path = DATA_DIR) -> dict:
    """Random-direction limit setups at random killzone bars, zone a fixed ATR distance below the close (frame coords),
    executed with cfg's entry/exit/cost rules. Shows what 'no edge' looks like under the pess/opt conventions."""
    lo, hi = ms(WINDOWS[window][0]), ms(WINDOWS[window][1])
    rng = np.random.default_rng(seed)
    trades = []
    for sym in cfg.pairs:
        b = build_bars(sym, data_dir, cfg.sig_tf)
        close_ts = b.sig["ts"] + b.bar_ms
        lm = (b.lon_min + b.tf) % 1440
        ok = np.flatnonzero((close_ts >= lo) & (close_ts < hi) & in_sessions(lm, cfg.sessions) & ~np.isnan(b.atr_s))
        pick = np.sort(rng.choice(ok, size=min(n_per_pair, len(ok)), replace=False))
        busy = -1
        for t in pick:
            d = int(rng.choice([-1, 1]))
            _, _, _, Cf = _frame(b.sig, d)
            a_ = float(b.atr_s[t])
            ev = dict(t=int(t), k=int(t), dir=d, atr=a_, z_lo=float(Cf[t] - 0.8 * a_), z_hi=float(Cf[t] - 0.3 * a_),
                      pool=float("nan"), kind="ob")
            if int(b.sig_to_m5[t]) <= busy:
                continue
            pe = sim_position(b, ev, cfg, "pess")
            if pe is None or pe.get("unfilled"):
                continue
            op = sim_position(b, ev, cfg, "opt") or pe
            busy = pe["j_exit"]
            ra, rb = pe.pop("R"), op["R"]
            pe.update(R_pess=min(ra, rb), R_opt=max(ra, rb), t_exit_opt=op["t_exit"], risk=cfg.risk, engine=cfg.engine)
            trades.append(pe)
    return stats(trades, TRAIN_EDGES if window == "train" else TEST_EDGES, B=200)


# --------------------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------------------
def _fmt(st: dict) -> str:
    if not st.get("n"):
        return "n=0"
    return (f"n={st['n']:5d} wr={st['wr']:.2f} exp={st['exp']:+.3f} pf={st['pf']:.2f} sumR={st['sumR']:+8.1f} "
            f"gross={st['exp_gross']:+.3f} cost={st['cost_mean_R']:.3f} stop={st['stop_pips_med']:.1f}p "
            f"opt={st['exp_opt']:+.3f} x1.5={st['exp_x15']:+.3f} lb90={st['lb90']:+.3f} "
            f"halves={[round(h, 3) for h in st['halves']]} top={st['top_pair']}:{st['top_share']:.0%}")


LOOKS = ROOT / "docs" / "research" / "findings" / "docs_v1_test_looks.json"


def _guard_test(names: list[str]) -> None:
    """Pre-registration enforcement: TEST opens only for TRAIN candidates, at most 3 configs, one look each."""
    import os
    if os.environ.get("DOCS_V1_TEST_OK") != "1":
        raise SystemExit("TEST window is locked. Set DOCS_V1_TEST_OK=1 only for the (<=3) pre-selected candidates.")
    looked = json.loads(LOOKS.read_text()) if LOOKS.exists() else []
    if len(set(looked) | set(names)) > 3:
        raise SystemExit(f"refused: at most 3 TEST looks in total (already looked: {looked})")
    for nm in names:
        if nm in looked:
            raise SystemExit(f"refused: {nm} already had its one TEST look")
        f = OUT_DIR / f"{nm}_train.json"
        if not f.exists() or not json.loads(f.read_text()).get("candidate"):
            raise SystemExit(f"refused: {nm} is not a TRAIN candidate")
    LOOKS.write_text(json.dumps(sorted(set(looked) | set(names))))


def cmd_run(args) -> None:
    names = list(CONFIGS) if args.config == "all" else args.config.split(",")
    edges = TRAIN_EDGES if args.window == "train" else TEST_EDGES
    if args.window == "test":
        _guard_test(names)
    for nm in names:
        cfg = CONFIGS[nm]
        tr = run_config(cfg, args.window, Path(args.data_dir), workers=args.workers)
        st = stats(tr, edges, B=args.boot)
        acc = account_sim(tr)
        rec = dict(config=cfg.to_json(), window=args.window, stats=st, account=acc,
                   candidate=is_candidate(st) if st.get("n") else False,
                   score=train_score(st) if args.window == "train" else None)
        tag = args.window + ("" if Path(args.data_dir) == DATA_DIR else "_ci")
        (OUT_DIR / f"{nm}_{tag}.json").write_text(json.dumps(rec, indent=1, default=float))
        (OUT_DIR / f"{nm}_{tag}_trades.json").write_text(json.dumps(tr, default=float))
        print(f"{nm:26s} {args.window:5s} {_fmt(st)}", flush=True)
        if args.window != "train" and st.get("n"):
            print("   account:", {k: (round(v, 2) if isinstance(v, float) else v) for k, v in acc.items()})
            for k, (ok, txt) in gates_test(st, acc).items():
                print(f"   {k}: {'PASS' if ok else 'FAIL'}  {txt}")


def main(argv=None) -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0] if __doc__ else "")
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("--config", required=True, help="config name(s), comma separated, or 'all'")
    r.add_argument("--window", choices=list(WINDOWS), required=True)
    r.add_argument("--workers", type=int, default=2)
    r.add_argument("--boot", type=int, default=2000)
    r.add_argument("--data-dir", default=str(DATA_DIR), help="folder of <sym>-m5-2022-09-11_2026-*.csv (FORWARD: the CI snapshot)")
    r.set_defaults(fn=cmd_run)
    nl = sub.add_parser("null")
    nl.add_argument("--config", required=True)
    nl.add_argument("--n", type=int, default=600)
    nl.set_defaults(fn=lambda a: [print(f"NULL {nm:24s} {_fmt(null_calibration(CONFIGS[nm], 'train', a.n))}", flush=True)
                                  for nm in a.config.split(",")])
    a = ap.parse_args(argv)
    a.fn(a)


if __name__ == "__main__":
    main()
