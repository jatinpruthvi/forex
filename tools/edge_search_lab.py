#!/usr/bin/env python3
"""Second bounded search (session drift, weekend-gap fade, fade geometry) on the 10-year Dukascopy M5 set.
Pre-registered in docs/research/findings/findings_edge_search.md (committed before any P&L was computed).

  python tools/edge_search_lab.py train     # all 116 configs on TRAIN only
  python tools/edge_search_lab.py valid     # candidate rule -> VALID -> finalists (max 3)
  python tools/edge_search_lab.py test --confirm    # finalists on TEST, once (lock file)
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "validation" / "speed_lab"))
from tools import exhaustion_oos_lab as X  # noqa: E402
from tools import docs_v1_lab as L  # noqa: E402
from tools import family_search_lab as F  # noqa: E402
from tools import challenge_sim as C  # noqa: E402
import verify_final_config as V  # noqa: E402

OUT = Path("/tmp/edge_out")
OUT.mkdir(exist_ok=True)
ms = X.ms
SPLITS = F.SPLITS
WINDOWS = {"A": (0, 420), "B": (420, 720), "C": (720, 960), "D": (960, 1260)}   # London wall-clock minutes of day: 00-07, 07-12, 12-16, 16-21
SESS_S = 2.0
GAP_GRID = [(g, s) for g in (0.10, 0.25) for s in (1.0, 2.0)]
FADE_GRID = [(K, S, T, dr) for K in (3.0, 4.0, 5.0) for S in (2.0, 3.0) for T in (5.0, 10.0) for dr in ("long", "both")]

CONFIGS: dict[str, dict] = {}
for s in V.SPECS:
    for w in WINDOWS:
        for dr in (1, -1):
            CONFIGS[f"SESS_{s}_{w}_{'L' if dr > 0 else 'S'}"] = dict(fam="SESS", sym=s, win=w, dir=dr)
for g, s in GAP_GRID:
    CONFIGS[f"GAP_g{g}_s{s}"] = dict(fam="GAP", g=g, s=s)
for K, S, T, dr in FADE_GRID:
    CONFIGS[f"FADE_K{K}_S{S}_T{T}_{dr}"] = dict(fam="FADE", K=K, S=S, T=T, dr=dr)


def mk(sym, pip, pv, spp, dirn, entry, dist, r_strict, r_opt, ti, tx, tz):
    def cst(m):
        sp = dist / pip
        return (spp * m * pv + V.COMM_RT) / (sp * pv + V.COMM_RT)
    return dict(sym=sym, dir=dirn, R_pess=float(r_strict), R_opt=float(r_opt), cost=cst(1.0), cost15=cst(1.5), cost2=cst(2.0), cost3=cst(3.0),
                t_fill=int(ti), t_exit=int(tx), t_sig=int(tz), stop_pips=dist / pip)


def spec(sym):
    pip, pv, sprd = V.SPECS[sym]
    return pip, pv, sprd * V.RAW_SCALE / pip


# ---------------------------------------------------------------- SESSION drift
def sess_trades(sym, d, win, dirs=(1, -1)):
    ts, o, h, l = d["ts"], d["o"], d["h"], d["l"]
    mod, day = L.london_parts(ts)
    key = day * 1440 + mod
    m0, m1 = WINDOWS[win]
    ud = np.unique(day)
    ud = ud[((ud + 3) % 7) < 5]
    e = np.searchsorted(key, ud * 1440 + m0, "left")
    x = np.searchsorted(key, ud * 1440 + m1, "left")
    ok = (e < len(key)) & (x < len(key))
    ok[ok] &= (key[e[ok]] - (ud[ok] * 1440 + m0) <= 10) & (key[x[ok]] - (ud[ok] * 1440 + m1) <= 10) & (x[ok] > e[ok] + 12)
    e, x = e[ok], x[ok]
    pip, pv, spp = spec(sym)
    mv = np.abs(o[x] - o[e])
    out = {dr: [] for dr in dirs}
    for j in range(20, len(e)):
        W = mv[j - 20:j].mean()                       # prior 20 windows only
        if W <= 0:
            continue
        dist = SESS_S * W
        i0, i1 = int(e[j]), int(x[j])
        entry = o[i0]
        lo, hi = l[i0:i1].min(), h[i0:i1].max()
        for dr in dirs:
            stop = entry - dr * dist
            hit = lo <= stop if dr > 0 else hi >= stop
            if hit:
                seg = (l[i0:i1] <= stop) if dr > 0 else (h[i0:i1] >= stop)
                jj = i0 + int(np.argmax(seg))
                fill = stop if jj == i0 else (min(stop, o[jj]) if dr > 0 else max(stop, o[jj]))
                out[dr].append(mk(sym, pip, pv, spp, dr, entry, dist, (fill - entry) * dr / dist, -1.0, ts[i0], ts[jj], ts[i0]))
            else:
                r = (o[i1] - entry) * dr / dist
                out[dr].append(mk(sym, pip, pv, spp, dr, entry, dist, r, r, ts[i0], ts[i1], ts[i0]))
    return out


# ---------------------------------------------------------------- weekend gap fade
def gap_trades(sym, d, dd, g, s):
    ts, o, h, l, c = d["ts"], d["o"], d["h"], d["l"], d["c"]
    pip, pv, spp = spec(sym)
    gi = np.flatnonzero(np.diff(ts) >= 36 * 3_600_000) + 1
    out = []
    for i in gi:
        di = int(np.searchsorted(dd["js"], i, "right")) - 1
        if di < 21 or i + 289 >= len(o):
            continue
        atr = dd["atr"][di - 1]
        gap = o[i] - c[i - 1]
        if not np.isfinite(atr) or abs(gap) < g * atr or abs(gap) < 3 * pip:
            continue
        dr = -1 if gap > 0 else 1
        dist = s * abs(gap)
        entry = o[i]
        stop = entry - dr * dist
        tgt = c[i - 1]
        j_end = i + 288
        lo, hi = l[i:j_end], h[i:j_end]
        sh = np.flatnonzero(lo <= stop if dr > 0 else hi >= stop)
        th = np.flatnonzero(hi >= tgt if dr > 0 else lo <= tgt)
        js = int(sh[0]) if len(sh) else 10 ** 9
        jt = int(th[0]) if len(th) else 10 ** 9
        if js <= jt and js < 10 ** 9:
            jj = i + js
            fill = stop if js == 0 else (min(stop, o[jj]) if dr > 0 else max(stop, o[jj]))
            out.append(mk(sym, pip, pv, spp, dr, entry, dist, (fill - entry) * dr / dist, -1.0, ts[i], ts[jj], ts[i]))
        elif jt < 10 ** 9:
            r = abs(gap) / dist
            out.append(mk(sym, pip, pv, spp, dr, entry, dist, r, r, ts[i], ts[i + jt], ts[i]))
        else:
            r = (o[j_end] - entry) * dr / dist
            out.append(mk(sym, pip, pv, spp, dr, entry, dist, r, r, ts[i], ts[j_end], ts[i]))
    return out


# ---------------------------------------------------------------- fade geometry (both directions)
def fade_trades(sym, d, K, S, T, dr):
    ts, o, h, l, c = d["ts"], d["o"], d["h"], d["l"], d["c"]
    n = len(c)
    atr = X.atr_prior(d)
    body = np.abs(c - o)
    pip, pv, spp = spec(sym)
    out = []
    for side in ((1,) if dr == "long" else (1, -1)):
        cand = np.flatnonzero((body > K * atr) & ((c < o) if side > 0 else (c > o)) & (atr > 0))
        cand = cand[(cand >= 15) & (cand < n - 1)]
        for i in cand:
            a = atr[i]
            entry = o[i + 1]
            stop = (l[i] - S * a) if side > 0 else (h[i] + S * a)
            dist = (entry - stop) * side
            if dist <= 0 or dist < a:
                continue
            tgt = entry + side * T * dist
            j_end = min(i + 96 * 12, n - 1)
            lo, hi = l[i + 1:j_end + 1], h[i + 1:j_end + 1]
            sh = np.flatnonzero(lo <= stop if side > 0 else hi >= stop)
            th = np.flatnonzero(hi >= tgt if side > 0 else lo <= tgt)
            js = i + 1 + int(sh[0]) if len(sh) else 10 ** 12
            jt = i + 1 + int(th[0]) if len(th) else 10 ** 12
            if js <= jt and js < 10 ** 12:
                fill = stop if js == i + 1 else (min(stop, o[js]) if side > 0 else max(stop, o[js]))
                out.append(mk(sym, pip, pv, spp, side, entry, dist, (fill - entry) * side / dist, -1.0, ts[i + 1], ts[js], ts[i]))
            elif jt < 10 ** 12:
                out.append(mk(sym, pip, pv, spp, side, entry, dist, T, T, ts[i + 1], ts[jt], ts[i]))
            else:
                r = (c[j_end] - entry) * side / dist
                out.append(mk(sym, pip, pv, spp, side, entry, dist, r, r, ts[i + 1], ts[j_end], ts[i]))
    return out


# ---------------------------------------------------------------- driver
_DATA: dict = {}


def data(kind="ci"):
    if kind not in _DATA:
        _DATA[kind] = {s: X.load(s, p) for s, p in X.files(kind).items()}
    return _DATA[kind]


def daily_of(kind, s, _m={}):
    k = (kind, s)
    if k not in _m:
        _m[k] = F.daily(data(kind)[s])
    return _m[k]


_TR: dict = {}


def trades_for(name, kind="ci"):
    k = (name, kind)
    if k in _TR:
        return _TR[k]
    c = CONFIGS[name]
    D = data(kind)
    if c["fam"] == "SESS":
        kk = ("sess", c["sym"], c["win"], kind)
        if kk not in _TR:
            _TR[kk] = sess_trades(c["sym"], D[c["sym"]], c["win"])
        tr = _TR[kk][c["dir"]]
    elif c["fam"] == "GAP":
        tr = [t for s in D for t in gap_trades(s, D[s], daily_of(kind, s), c["g"], c["s"])]
    else:
        tr = [t for s in D for t in fade_trades(s, D[s], c["K"], c["S"], c["T"], c["dr"])]
    tr = sorted(tr, key=lambda t: (t["t_fill"], t["sym"]))
    _TR[k] = tr
    return tr


def stats_for(tr, split, B=3000, q=2.5):
    w = F.window(tr, split)
    if not w:
        return dict(n=0)
    st = L.stats(w, SPLITS[split][2], B=200)
    st["lb"] = L.bootstrap_lb(w, B=B, q=q)
    x = L.net_R(w)
    st["exp_slip"] = float((x - 0.03).mean())
    return st


def fmt(name, st):
    if not st.get("n"):
        return f"{name:34s} n=0"
    return (f"{name:34s} n={st['n']:5d} exp={st['exp']:+.3f} PF={st['pf']:.2f} gross={st['exp_gross']:+.3f} cost={st['cost_mean_R']:.3f} "
            f"lb={st['lb']:+.3f} yrs={[round(h, 2) for h in st['halves']]}")


def is_candidate(name, st):
    need = {"SESS": 600, "GAP": 100, "FADE": 150}[CONFIGS[name]["fam"]]
    ys = [h for h in st.get("halves", []) if h == h]
    return st.get("n", 0) >= need and st["exp"] > 0 and st["lb"] > 0 and st["pf"] >= 1.10 and sum(h > 0 for h in ys) >= 3


def cmd_train():
    res = {}
    for name in CONFIGS:
        st = stats_for(trades_for(name), "train")
        res[name] = st
    json.dump(res, (OUT / "train.json").open("w"), default=float)
    print(f"TRIALS: {len(CONFIGS)}")
    top = sorted(res.items(), key=lambda kv: -(kv[1].get("exp", -9) if kv[1].get("n") else -9))[:12]
    for n, st in top:
        print(fmt(n, st), "CANDIDATE" if is_candidate(n, st) else "")
    print("candidates:", [n for n, st in res.items() if st.get("n") and is_candidate(n, st)])
    for fam in ("SESS", "GAP", "FADE"):
        xs = [st["exp"] for n, st in res.items() if CONFIGS[n]["fam"] == fam and st.get("n")]
        print(f"{fam}: {len(xs)} configs, mean exp {np.mean(xs):+.4f}, share positive {np.mean([v > 0 for v in xs]):.2f}")


def cmd_valid():
    train = json.load((OUT / "train.json").open())
    cands = [n for n, st in train.items() if st.get("n") and is_candidate(n, st)]
    print("TRAIN candidates:", cands or "NONE")
    ok = []
    for n in cands:
        st = stats_for(trades_for(n), "valid")
        good = st.get("n", 0) >= (60 if CONFIGS[n]["fam"] != "SESS" else 250) and st["exp"] > 0 and st["pf"] >= 1.05
        print(fmt(n, st), "-> FINALIST-ELIGIBLE" if good else "-> dropped")
        if good:
            ok.append(n)
    ok.sort(key=lambda n: -train[n]["lb"])
    fin = ok[:3]
    json.dump(fin, (OUT / "finalists.json").open("w"))
    print("FINALISTS:", fin or "NONE")


def gates(name):
    tr, fs = trades_for(name), trades_for(name, "tracked")
    st = stats_for(tr, "test", B=10_000, q=5.0)
    w, fw = F.window(tr, "test"), F.window(fs, "test")
    kw = {(t["sym"], t["t_fill"], t["dir"]) for t in w}; kf = {(t["sym"], t["t_fill"], t["dir"]) for t in fw}
    ov = len(kw & kf) / max(len(kw), len(kf), 1)
    fexp = float(L.net_R(fw).mean()) if fw else float("nan")
    ys = [h for h in st["halves"] if h == h]
    g = {"T1": (st["n"] >= 150, f"n={st['n']}"),
         "T2": (st["exp"] >= 0.03 and st["lb"] > 0, f"exp={st['exp']:+.4f} lb95={st['lb']:+.4f}"),
         "T3": (st["pf"] >= 1.10, f"pf={st['pf']:.3f}"),
         "T4": (st["exp_x15"] > 0 and st["exp_slip"] > 0, f"x1.5={st['exp_x15']:+.4f} +0.03R={st['exp_slip']:+.4f}"),
         "T5": (sum(h > 0 for h in ys) >= 3, f"years={[round(h, 3) for h in ys]}"),
         "T6": (st["top_share"] <= 0.40 and st["exp_ex_top"] > 0, f"top {st['top_pair']} {st['top_share']:.0%} ex-top {st['exp_ex_top']:+.4f}"),
         "T7": (ov >= 0.85 and fexp > 0, f"FSB overlap {ov:.1%} FSB exp {fexp:+.4f} (n={len(fw)})")}
    # informational: challenge pass rate (not a gate)
    chal = {}
    for r in (0.005, 0.01, 0.015):
        lab = [dict(t_fill=t["t_fill"], t_exit=t["t_exit"], R=t["R_pess"], cost=t["cost"]) for t in tr]
        a = C.pass_rates(lab, ms(SPLITS["test"][0]), ms(SPLITS["test"][1]), r, max_conc=2)
        z = C.pass_rates(C.zero_edge([t for t in lab if ms(SPLITS["test"][0]) <= t["t_fill"] < ms(SPLITS["test"][1])]),
                         ms(SPLITS["test"][0]), ms(SPLITS["test"][1]), r, max_conc=2)
        chal[str(r)] = dict(real=a, null=z)
    return dict(name=name, stats=st, gates={k: [bool(v[0]), v[1]] for k, v in g.items()}, passed=all(v[0] for v in g.values()), challenge=chal)


def cmd_test(confirm):
    lock = OUT / "test.lock"
    if not confirm or lock.exists():
        sys.exit("refusing: TEST is one look (needs --confirm; lock exists=%s)" % lock.exists())
    fin = json.load((OUT / "finalists.json").open())
    if not fin:
        sys.exit("no finalists: nothing to test")
    lock.write_text(json.dumps(fin))
    res = {}
    for n in fin:
        r = gates(n); res[n] = r
        print("\n" + fmt(n, r["stats"]))
        for k, (ok, m) in r["gates"].items():
            print(f"   {k}: {'PASS' if ok else 'FAIL'}  {m}")
        print("   =>", "ALL GATES PASS" if r["passed"] else "NOT VALIDATED")
        for rk, v in r["challenge"].items():
            print(f"   challenge risk {rk}: pass {v['real']['pass_rate']:.2f} (null {v['null']['pass_rate']:.2f})")
    json.dump(res, (OUT / "test.json").open("w"), default=float, indent=1)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("train"); sub.add_parser("valid")
    t = sub.add_parser("test"); t.add_argument("--confirm", action="store_true")
    a = ap.parse_args()
    {"train": cmd_train, "valid": cmd_valid}.get(a.cmd, lambda: cmd_test(a.confirm))()


if __name__ == "__main__":
    main()
