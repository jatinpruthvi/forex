#!/usr/bin/env python3
"""Bounded search over three NEW strategy families on the 10-year Dukascopy M5 set (2016-09-11 .. 2026-09-11).
Pre-registered in docs/research/findings/findings_family_search.md (committed before any P&L was computed).

Daily bars on the NY-17:00 clock (from M5). Signal at a daily close, entry at the first M5 open of the next NY day.
Stops are tested on M5 bars (gap-aware: fill = min(stop, bar open) for a long); the repo rule (-1R) is kept as the optimistic bound.
Costs: repo model (SPECS x 0.55 + $7/lot round turn) in R units. Swap/carry is NOT modelled (no data).

  python tools/family_search_lab.py train        # 12 configs on TRAIN only; prints table, writes /tmp/fam_out/train.json
  python tools/family_search_lab.py valid        # per-family pick (rule-based) on VALID, writes finalists.json
  python tools/family_search_lab.py test --confirm   # finalists on TEST, ONCE (lock file), gates T1-T7
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from numpy.lib.stride_tricks import sliding_window_view as swv

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "validation" / "speed_lab"))
from tools import exhaustion_oos_lab as X  # noqa: E402
from tools import docs_v1_lab as L  # noqa: E402
import verify_final_config as V  # noqa: E402

OUT = Path("/tmp/fam_out")
OUT.mkdir(exist_ok=True)
MIN_BARS = 100                       # NY days with fewer M5 bars are merged into the previous day (weekend/holiday stubs)
FX10 = [s for s in V.SPECS if s != "XAUUSD"]
ms = X.ms

# ----------------------------------------------------------------------------- configs (the whole trial budget: 12)
CONFIGS = {}
for N in (20, 55):
    for k in (3.0, 4.5):
        CONFIGS[f"F1_trend_N{N}_k{k}"] = dict(fam="F1", N=N, k=k)
for Lb in (3, 5):
    for S in (2.0, 3.0):
        CONFIGS[f"F2_pullback_L{Lb}_S{S}"] = dict(fam="F2", L=Lb, S=S)
for lb in (20, 60):
    for mode in ("mom", "rev"):
        CONFIGS[f"F3_xsec_{mode}_lb{lb}"] = dict(fam="F3", lb=lb, mode=mode)

SPLITS = {
    "train": ("2016-09-11", "2020-09-11", [f"{y}-09-11" for y in range(2016, 2021)]),
    "valid": ("2020-09-11", "2022-09-11", ["2020-09-11", "2021-09-11", "2022-09-11"]),
    "test": ("2022-09-11", "2026-09-11", [f"{y}-09-11" for y in range(2022, 2027)]),
}


# ----------------------------------------------------------------------------- data
def daily(d: dict) -> dict:
    key = L._ny_bucket(d["ts"])
    starts = np.flatnonzero(np.r_[True, key[1:] != key[:-1]])
    n = np.diff(np.r_[starts, len(key)])
    ks = starts[n >= MIN_BARS]
    ke = np.r_[ks[1:], len(key)]
    dd = dict(js=ks, je=ke, key=key[ks], o=d["o"][ks], h=np.maximum.reduceat(d["h"], ks), l=np.minimum.reduceat(d["l"], ks),
              c=d["c"][ke - 1])
    # reduceat over [ks[i], ks[i+1]) covers merged stub days; the last segment runs to the end
    dd["dow"] = (dd["key"] + 4) % 7
    c, h, l = dd["c"], dd["h"], dd["l"]
    pc = np.r_[c[0], c[:-1]]
    tr = np.maximum(h - l, np.maximum(np.abs(h - pc), np.abs(l - pc)))
    cs = np.cumsum(np.r_[0.0, tr])
    atr = np.full(len(c), np.nan)
    atr[19:] = (cs[20:] - cs[:-20]) / 20            # ATR20 including the signal day's own (completed) range
    dd["atr"] = atr
    cs2 = np.cumsum(np.r_[0.0, c])
    sma = np.full(len(c), np.nan)
    sma[99:] = (cs2[100:] - cs2[:-100]) / 100
    dd["sma100"] = sma
    return dd


class Pair:
    def __init__(self, sym: str, path: Path):
        self.sym = sym
        self.d = X.load(sym, path)
        self.dd = daily(self.d)
        pip, pv, sprd = V.SPECS[sym]
        self.pip, self.pv, self.spread_pips = pip, pv, sprd * V.RAW_SCALE / pip


def cost_R(p: Pair, dist: float, mult: float = 1.0) -> float:
    sp = dist / p.pip
    return (p.spread_pips * mult * p.pv + V.COMM_RT) / (sp * p.pv + V.COMM_RT)


# ----------------------------------------------------------------------------- trade simulation
def simulate(p: Pair, di: int, dirn: int, s_atr: float, hold_max: int, trail_k: float | None = None, exit_fn=None):
    """Signal on daily bar di (completed). Entry: first M5 open of day di+1. Returns trade dict (or None) and the exit day index."""
    dd, d = p.dd, p.d
    nd = len(dd["c"])
    if di + 1 >= nd or not np.isfinite(dd["atr"][di]):
        return None, di
    atr = float(dd["atr"][di])
    j0 = int(dd["js"][di + 1])
    entry = float(d["o"][j0])
    dist = s_atr * atr
    if dist <= 0:
        return None, di
    stop = entry - dirn * dist
    best = entry
    kmax = min(di + hold_max, nd - 1)
    for k in range(di + 1, kmax + 1):
        breach = dd["l"][k] <= stop if dirn > 0 else dd["h"][k] >= stop
        if breach:
            a, b = int(dd["js"][k]), int(dd["je"][k])
            seg = (d["l"][a:b] <= stop) if dirn > 0 else (d["h"][a:b] >= stop)
            jj = a + int(np.argmax(seg))
            if jj == j0:
                fill = stop
            else:
                fill = min(stop, d["o"][jj]) if dirn > 0 else max(stop, d["o"][jj])
            return _trade(p, di, dirn, entry, dist, (fill - entry) * dirn / dist, -1.0, j0, jj, k), k
        c = float(dd["c"][k])
        if trail_k is not None:
            best = max(best, c) if dirn > 0 else min(best, c)
            new = best - dirn * trail_k * atr
            stop = max(stop, new) if dirn > 0 else min(stop, new)
        if k == kmax or (exit_fn is not None and exit_fn(dd, k, dirn)):
            je = int(dd["je"][k])
            px = float(d["o"][je]) if je < len(d["o"]) else float(d["c"][-1])
            r = (px - entry) * dirn / dist
            return _trade(p, di, dirn, entry, dist, r, r, j0, min(je, len(d["o"]) - 1), k), k
    return None, di


def _trade(p, di, dirn, entry, dist, r_strict, r_repo, j0, jx, kx):
    ts = p.d["ts"]
    sp = dist / p.pip
    return dict(sym=p.sym, dir=dirn, R_pess=float(r_strict), R_opt=float(r_repo), cost=cost_R(p, dist), cost15=cost_R(p, dist, 1.5),
                cost2=cost_R(p, dist, 2.0), cost3=cost_R(p, dist, 3.0), t_sig=int(ts[p.dd["js"][di + 1] - 1]),
                t_fill=int(ts[j0]), t_exit=int(ts[jx]), stop_pips=float(sp), di=di, kx=kx)


# ----------------------------------------------------------------------------- families
def run_F1(p: Pair, N: int, k: float) -> list[dict]:
    dd = p.dd
    c, h, l = dd["c"], dd["h"], dd["l"]
    n = len(c)
    hi = np.full(n, np.nan); lo = np.full(n, np.nan)
    if n > N:
        hi[N:] = swv(h, N)[:n - N].max(1)             # max high of the N days BEFORE day i
        lo[N:] = swv(l, N)[:n - N].min(1)
    out, i = [], 20
    while i < n - 1:
        if not np.isfinite(dd["atr"][i]) or not np.isfinite(hi[i]) or dd["je"][i] - dd["js"][i] < MIN_BARS:
            i += 1; continue
        dirn = 1 if c[i] > hi[i] else (-1 if c[i] < lo[i] else 0)
        if dirn:
            t, kx = simulate(p, i, dirn, k, hold_max=250, trail_k=k)
            if t:
                out.append(t); i = kx + 1; continue
        i += 1
    return out


def run_F2(p: Pair, Lb: int, S: float) -> list[dict]:
    dd = p.dd
    c = dd["c"]
    n = len(c)
    minL = np.full(n, np.nan); maxL = np.full(n, np.nan)
    minL[Lb - 1:] = swv(c, Lb).min(1); maxL[Lb - 1:] = swv(c, Lb).max(1)   # includes today's close

    def ex(dd_, k, dirn):
        return dd_["c"][k] > dd_["h"][k - 1] if dirn > 0 else dd_["c"][k] < dd_["l"][k - 1]

    out, i = [], 100
    while i < n - 1:
        if not np.isfinite(dd["sma100"][i]) or not np.isfinite(dd["atr"][i]) or dd["je"][i] - dd["js"][i] < MIN_BARS:
            i += 1; continue
        dirn = 1 if (c[i] > dd["sma100"][i] and c[i] <= minL[i]) else (-1 if (c[i] < dd["sma100"][i] and c[i] >= maxL[i]) else 0)
        if dirn:
            t, kx = simulate(p, i, dirn, S, hold_max=10, exit_fn=ex)
            if t:
                out.append(t); i = kx + 1; continue
        i += 1
    return out


def run_F3(pairs: dict[str, Pair], lb: int, mode: str) -> list[dict]:
    base = pairs["EURUSD"].dd
    idx = {s: {int(k): i for i, k in enumerate(pairs[s].dd["key"])} for s in FX10}
    out = []

    def fri(dd_, k, dirn):
        return dd_["dow"][k] == 4

    for bi in np.flatnonzero(base["dow"] == 4):
        key = int(base["key"][bi])
        sc = {}
        for s in FX10:
            i = idx[s].get(key)
            if i is None or i < lb + 20 or i + 1 >= len(pairs[s].dd["c"]):
                continue
            dd = pairs[s].dd
            if not np.isfinite(dd["atr"][i]) or dd["je"][i] - dd["js"][i] < MIN_BARS:
                continue
            sc[s] = (dd["c"][i] / dd["c"][i - lb] - 1.0) / (dd["atr"][i] / dd["c"][i])   # vol-normalised lb-day return
        if len(sc) < 8:
            continue
        rk = sorted(sc, key=lambda s: sc[s])
        longs, shorts = (rk[-3:], rk[:3]) if mode == "mom" else (rk[:3], rk[-3:])
        for s, dirn in [(s, 1) for s in longs] + [(s, -1) for s in shorts]:
            t, _ = simulate(pairs[s], idx[s][key], dirn, 3.0, hold_max=8, exit_fn=fri)
            if t:
                out.append(t)
    return out


def load_pairs(kind: str = "ci") -> dict[str, Pair]:
    return {s: Pair(s, p) for s, p in X.files(kind).items()}


def run_config(name: str, pairs: dict[str, Pair]) -> list[dict]:
    c = CONFIGS[name]
    if c["fam"] == "F1":
        tr = [t for p in pairs.values() for t in run_F1(p, c["N"], c["k"])]
    elif c["fam"] == "F2":
        tr = [t for p in pairs.values() for t in run_F2(p, c["L"], c["S"])]
    else:
        tr = run_F3(pairs, c["lb"], c["mode"])
    tr.sort(key=lambda t: (t["t_fill"], t["sym"]))
    return tr


# ----------------------------------------------------------------------------- evaluation
def window(tr: list[dict], split: str) -> list[dict]:
    lo, hi, _ = SPLITS[split]
    return [t for t in tr if ms(lo) <= t["t_fill"] < ms(hi)]


def stats_for(tr: list[dict], split: str, B: int = 3000, q: float = 10.0) -> dict:
    w = window(tr, split)
    if not w:
        return dict(n=0)
    st = L.stats(w, SPLITS[split][2], B=B)
    st["lb"] = L.bootstrap_lb(w, B=B, q=q)
    x = L.net_R(w)
    st["exp_slip10"] = float((x - 0.10).mean())
    st["by_spread"] = {m: float(np.mean([t["R_pess"] - t[k] for t in w])) for m, k in ((1.0, "cost"), (1.5, "cost15"), (2.0, "cost2"), (3.0, "cost3"))}
    st["hold_days_med"] = float(np.median([(t["t_exit"] - t["t_fill"]) / 86_400_000 for t in w]))
    st["long_share"] = float(np.mean([t["dir"] > 0 for t in w]))
    return st


def fmt(name: str, st: dict) -> str:
    if not st.get("n"):
        return f"{name:26s} n=0"
    return (f"{name:26s} n={st['n']:5d} exp={st['exp']:+.3f} PF={st['pf']:.2f} gross={st['exp_gross']:+.3f} cost={st['cost_mean_R']:.3f} "
            f"lb90={st['lb']:+.3f} yrs={[round(h, 2) for h in st['halves']]} x1.5={st['exp_x15']:+.3f} med_hold={st['hold_days_med']:.1f}d")


def cmd_train() -> None:
    pairs = load_pairs("ci")
    res = {}
    for name in CONFIGS:
        tr = run_config(name, pairs)
        st = stats_for(tr, "train")
        res[name] = st
        print(fmt(name, st), flush=True)
    json.dump(res, (OUT / "train.json").open("w"), default=float, indent=1)
    print(f"TRIALS USED: {len(CONFIGS)} of 12")


def candidate(st: dict) -> bool:
    ys = [h for h in st.get("halves", []) if h == h]
    return st.get("n", 0) >= 100 and st["exp"] >= 0.05 and st["pf"] >= 1.15 and sum(h > 0 for h in ys) >= 3


def pick_per_family(train: dict) -> dict:
    picks = {}
    for fam in ("F1", "F2", "F3"):
        c = [(n, s) for n, s in train.items() if CONFIGS[n]["fam"] == fam and candidate(s)]
        if c:
            picks[fam] = max(c, key=lambda x: x[1]["exp"] * np.sqrt(x[1]["n"]))[0]
    return picks


def cmd_valid() -> None:
    train = json.load((OUT / "train.json").open())
    picks = pick_per_family(train)
    print("TRAIN picks (candidate rule; max exp*sqrt(n) per family):", picks or "NONE")
    pairs = load_pairs("ci")
    fin = {}
    for fam, name in picks.items():
        st = stats_for(run_config(name, pairs), "valid")
        ok = st.get("n", 0) >= 40 and st["exp"] > 0 and st["pf"] >= 1.10
        print(fmt(name, st), "->", "FINALIST" if ok else "dropped")
        if ok:
            fin[fam] = name
    json.dump(fin, (OUT / "finalists.json").open("w"))
    print("FINALISTS:", fin or "NONE")


def gates_test(name: str, tr: list[dict], tr_fsb: list[dict]) -> dict:
    st = stats_for(tr, "test", B=10_000, q=5.0)
    w = window(tr, "test")
    ys = [h for h in st["halves"] if h == h]
    fs = window(tr_fsb, "test")
    kw = {(t["sym"], t["t_fill"], t["dir"]) for t in w}
    kf = {(t["sym"], t["t_fill"], t["dir"]) for t in fs}
    overlap = len(kw & kf) / max(len(kw), len(kf), 1)
    fexp = float(L.net_R(fs).mean()) if fs else float("nan")
    g = {
        "T1": (st["n"] >= 150, f"n={st['n']}"),
        "T2": (st["exp"] >= 0.10 and st["lb"] > 0, f"exp={st['exp']:+.4f} lb95={st['lb']:+.4f}"),
        "T3": (st["pf"] >= 1.20, f"pf={st['pf']:.3f}"),
        "T4": (st["exp_x15"] > 0 and st["exp_slip10"] > 0, f"x1.5={st['exp_x15']:+.4f} +0.10R={st['exp_slip10']:+.4f}"),
        "T5": (sum(h > 0 for h in ys) >= 3, f"years={[round(h, 3) for h in ys]}"),
        "T6": (st["top_share"] <= 0.40 and st["exp_ex_top"] > 0, f"top {st['top_pair']} {st['top_share']:.0%}, ex-top {st['exp_ex_top']:+.4f}"),
        "T7": (overlap >= 0.85 and fexp > 0, f"FSB overlap={overlap:.1%} FSB exp={fexp:+.4f} (n={len(fs)})"),
    }
    return dict(name=name, stats=st, gates={k: [bool(v[0]), v[1]] for k, v in g.items()}, passed=all(v[0] for v in g.values()))


def cmd_test(confirm: bool) -> None:
    lock = OUT / "test.lock"
    if not confirm or lock.exists():
        sys.exit("refusing: TEST is one look per frozen finalist (needs --confirm; lock exists=%s)" % lock.exists())
    fin = json.load((OUT / "finalists.json").open())
    if not fin:
        sys.exit("no finalists: nothing to test")
    lock.write_text(json.dumps(fin))
    pairs, fsb = load_pairs("ci"), load_pairs("tracked")
    res = {}
    for fam, name in fin.items():
        r = gates_test(name, run_config(name, pairs), run_config(name, fsb))
        res[name] = r
        st = r["stats"]
        print("\n" + fmt(name, st))
        for k, (ok, msg) in r["gates"].items():
            print(f"   {k}: {'PASS' if ok else 'FAIL'}  {msg}")
        print("   =>", "ALL GATES PASS" if r["passed"] else "NOT VALIDATED")
    json.dump(res, (OUT / "test.json").open("w"), default=float, indent=1)


def main() -> None:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("train"); sub.add_parser("valid")
    t = sub.add_parser("test"); t.add_argument("--confirm", action="store_true")
    a = ap.parse_args()
    {"train": cmd_train, "valid": cmd_valid}.get(a.cmd, lambda: cmd_test(a.confirm))()


if __name__ == "__main__":
    main()
