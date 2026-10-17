#!/usr/bin/env python3
"""Independent numpy re-implementation of the frozen M5 long-only extreme-bar exhaustion fade, for the out-of-sample
validation in docs/research/findings/findings_best_strategy_oos.md.

The rule is the one in validation/speed_lab/verify_final_config.py (K=4 ATR body, stop low-2ATR, +10R, 96h, min stop 1 ATR),
written again from its docstring and checked against it trade-for-trade on the tracked window (see `repro`).
Two exit conventions are computed for every signal:
  * repo rule   : a stop books exactly -1R (what verify_final_config.py does), ties go to the stop
  * strict rule : a stop fills at min(stop, bar open) (gap-aware), ties go to the stop      <- the GATE
Nothing here tunes anything. Usage:
  python tools/exhaustion_oos_lab.py repro                 # match the repo verifier on the tracked set
  python tools/exhaustion_oos_lab.py run --window oos|rep|fwd
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
import verify_final_config as V  # noqa: E402  (repo constants only: SPECS, RAW_SCALE, COMM_RT)
from tools import docs_v1_lab as L  # noqa: E402  (stats, bootstrap, account helpers)

K, STOP_ATR, TARGET_R, HOLD_BARS, MIN_STOP_ATR = 4.0, 2.0, 10.0, 96 * 12, 1.0
CACHE = Path("/tmp/exh_cache")
CACHE.mkdir(exist_ok=True)
TRACKED = ROOT / "validation" / "HistoryData"
CI = Path("/tmp/ci/forex-data-m5-history")
PAIRS = list(V.SPECS)
DAY = 86_400_000


def ms(d: str) -> int:
    return L.ms(d)


def load(sym: str, path: Path) -> dict:
    key = CACHE / f"{path.parent.name}_{path.name}_{path.stat().st_size}.npy"
    if key.exists():
        a = np.load(key)
    else:
        a = np.loadtxt(path, delimiter=",", skiprows=1, usecols=(0, 1, 2, 3, 4), dtype=np.float64)
        a = a[np.argsort(a[:, 0], kind="stable")]
        np.save(key, a)
    return dict(ts=a[:, 0].astype(np.int64), o=a[:, 1], h=a[:, 2], l=a[:, 3], c=a[:, 4])


def files(kind: str) -> dict[str, Path]:
    if kind == "tracked":
        return {s: TRACKED / f"{s.lower()}-m5-2022-09-11_2026-09-11.csv" for s in PAIRS}
    return {s: next(CI.glob(f"{s.lower()}-m5-2016-09-11_*.csv")) for s in PAIRS}


def resolve(d: dict, i: int, entry: float, stop: float, dist: float) -> tuple[float, float, int]:
    """Walk the M5 bars after signal bar i. Returns (R by repo rule, R by strict rule, exit bar index)."""
    o, h, l, c = d["o"], d["h"], d["l"], d["c"]
    n = len(c)
    target = entry + TARGET_R * dist
    j_end = min(i + HOLD_BARS, n - 1)                     # last bar index scanned (inclusive)
    lo, hi = l[i + 1:j_end + 1], h[i + 1:j_end + 1]
    s_hit = np.flatnonzero(lo <= stop)
    t_hit = np.flatnonzero(hi >= target)
    js = i + 1 + int(s_hit[0]) if len(s_hit) else 10 ** 12
    jt = i + 1 + int(t_hit[0]) if len(t_hit) else 10 ** 12
    if js <= jt and js < 10 ** 12:                        # stop wins ties
        fill = stop if js == i + 1 else min(stop, o[js])  # gap-aware only when a LATER bar opens below the stop
        return -1.0, (fill - entry) / dist, js
    if jt < 10 ** 12:
        return TARGET_R, TARGET_R, jt
    r = (c[j_end] - entry) / dist
    return r, r, j_end


def atr_prior(d: dict) -> np.ndarray:
    h, l, c = d["h"], d["l"], d["c"]
    n = len(c)
    pc = np.r_[c[0], c[:-1]]
    tr = np.maximum(h - l, np.maximum(np.abs(h - pc), np.abs(l - pc)))
    # ATR for signal bar i = mean(TR[i-14 .. i-1]) (prior bars only). Sliding add/subtract, in the same floating-point order as the
    # repo verifier, so that touches of a stop exactly on the price grid resolve identically (a 4e-17 difference flips such a tie).
    atr = np.full(n, np.nan)
    run = 0.0
    trl = tr.tolist()
    for j in range(n):
        run += trl[j]
        if j >= 14:
            run -= trl[j - 14]
        if j >= 14 and j + 1 < n:
            atr[j + 1] = run / 14
    return atr


def signals(sym: str, d: dict) -> list[dict]:
    """All long signals with both exit conventions. Signal bar index i, entry on bar i+1."""
    ts, o, h, l, c = d["ts"], d["o"], d["h"], d["l"], d["c"]
    n = len(c)
    atr = atr_prior(d)
    body = np.abs(c - o)
    cand = np.flatnonzero((body > K * atr) & (c < o) & (atr > 0))
    cand = cand[(cand >= 15) & (cand < n - 1)]
    pip, pv, sprd = V.SPECS[sym]
    spread_pips = sprd * V.RAW_SCALE / pip
    out = []
    for i in cand:
        a = atr[i]
        entry = o[i + 1]
        stop = l[i] - STOP_ATR * a
        dist = entry - stop
        if dist <= 0 or dist < MIN_STOP_ATR * a:
            continue
        R_repo, R_strict, jx = resolve(d, int(i), entry, stop, dist)
        sp = dist / pip
        out.append(dict(sym=sym, i=int(i), t_sig=int(ts[i]), t_fill=int(ts[i + 1]), t_exit=int(ts[jx]),
                        R_repo=float(R_repo), R_strict=float(R_strict), dist=float(dist), atr=float(a),
                        stop_pips=float(sp), rng_atr=float((h[i] - l[i]) / a),
                        cost=float((spread_pips * pv + V.COMM_RT) / (sp * pv + V.COMM_RT)),
                        cost15=float((spread_pips * 1.5 * pv + V.COMM_RT) / (sp * pv + V.COMM_RT)),
                        cost2=float((spread_pips * 2.0 * pv + V.COMM_RT) / (sp * pv + V.COMM_RT)),
                        cost3=float((spread_pips * 3.0 * pv + V.COMM_RT) / (sp * pv + V.COMM_RT))))
    return out


def all_signals(kind: str) -> list[dict]:
    res = []
    for s, p in files(kind).items():
        res += signals(s, load(s, p))
    res.sort(key=lambda t: (t["t_fill"], t["sym"]))
    return res


def as_lab_trades(sig: list[dict], lo: int, hi: int, rule_gross: str = "R_strict") -> list[dict]:
    """Convert to the docs_v1_lab trade schema (pess = strict, opt = repo rule)."""
    out = []
    for t in sig:
        if not (lo <= t["t_sig"] < hi):
            continue
        out.append(dict(sym=t["sym"], R_pess=t["R_strict"], R_opt=t["R_repo"], cost=t["cost"], cost15=t["cost15"],
                        t_fill=t["t_fill"], t_exit=t["t_exit"], t_exit_opt=t["t_exit"], stop_pips=t["stop_pips"],
                        risk=0.005, engine="EXH", kind="exh", dir=1, wsum=1.0, t_sig=t["t_sig"]))
    return out


def repro() -> None:
    """Trade-for-trade match against verify_final_config.build() on the tracked window."""
    lo = V.TRAIN_END
    tot_n = tot_bad = 0
    for s in PAIRS:
        mine = [t for t in signals(s, load(s, TRACKED / f"{s.lower()}-m5-2022-09-11_2026-09-11.csv")) if t["t_sig"] >= lo]
        ref = [t for t in V.build(s) if t.ets >= lo]
        same_n = len(mine) == len(ref)
        bad = 0
        if same_n:
            for a, b in zip(mine, ref):
                if a["t_sig"] != b.ets or abs(a["R_repo"] - b.R) > 1e-9 or abs(a["cost"] - b.cost_R) > 1e-9:
                    bad += 1
        print(f"{s:7s} mine n={len(mine):4d} repo n={len(ref):4d} mismatched={bad if same_n else 'n/a'}")
        tot_n += len(mine)
        tot_bad += bad if same_n else 10 ** 6
    print("REPRO", "PASS" if tot_bad == 0 else "FAIL", "total n", tot_n)


def placebo(kind: str, lo: int, hi: int, seed: int = 11) -> dict:
    """Diagnostic: the same long geometry (stop = dist/ATR ratio of the real signals, +10R, 96h) at RANDOM bars, same count per pair.
    Shows how much of a 10R long-only payoff is generic drift/volatility rather than the exhaustion trigger."""
    rng = np.random.default_rng(seed)
    g, net, n_all = [], [], 0
    for s_, p in files(kind).items():
        d = load(s_, p)
        real = [t for t in signals(s_, d) if lo <= t["t_sig"] < hi]
        if not real:
            continue
        ratios = np.array([t["dist"] / t["atr"] for t in real])
        atr = atr_prior(d)
        ok = np.flatnonzero((d["ts"] >= lo) & (d["ts"] < hi) & (atr > 0) & (np.arange(len(atr)) < len(atr) - 1))
        pick = rng.choice(ok, size=len(real), replace=False)
        pip, pv, sprd = V.SPECS[s_]
        spread_pips = sprd * V.RAW_SCALE / pip
        for k in pick:
            a_ = atr[k]
            entry = d["o"][k + 1]
            dist = float(rng.choice(ratios)) * a_
            R_repo, R_strict, _ = resolve(d, int(k), entry, entry - dist, dist)
            sp = dist / pip
            cost = (spread_pips * pv + V.COMM_RT) / (sp * pv + V.COMM_RT)
            g.append(R_strict); net.append(R_strict - cost)
    g, net = np.array(g), np.array(net)
    return dict(n=len(g), gross=float(g.mean()), net=float(net.mean()), target_rate=float((g >= TARGET_R - 1e-9).mean()))


def _utc_day(ts: np.ndarray) -> np.ndarray:
    return ts // DAY


def evaluate(sig: list[dict], lo: int, hi: int, edges: list[str], label: str, boot: int = 10_000) -> dict:
    """Numbers behind gates O1-O7 and O9 for one window. Strict rule = gate."""
    tr = as_lab_trades(sig, lo, hi)
    st = L.stats(tr, edges, B=boot)
    if not st.get("n"):
        return dict(label=label, stats=st)
    x = L.net_R(tr)
    x_slip = x - 0.10
    ts = np.array([t["t_fill"] for t in tr], dtype=np.int64)
    dk = _utc_day(ts)
    u, inv = np.unique(dk, return_inverse=True)
    day_sum = np.bincount(inv, weights=x)
    tot = float(x.sum())
    top_day_share = float(day_sum.max() / tot) if tot > 0 else float("nan")
    top5_share = float(np.sort(day_sum)[-5:].sum() / tot) if tot > 0 else float("nan")
    sub = [t for t in sig if lo <= t["t_sig"] < hi]
    by_spread = {m: float(np.mean([t["R_strict"] - t[k] for t in sub])) for m, k in
                 ((1.0, "cost"), (1.5, "cost15"), (2.0, "cost2"), (3.0, "cost3"))}
    # walk-forward with the repo's firm-rule replay (strict R, sorted like the repo does)
    vt = [V.T(t["sym"], t["t_sig"], t["t_exit"], t["R_strict"], t["cost"], t["stop_pips"]) for t in sub]
    vt.sort(key=lambda t: (t.ets, t.sym))
    wf = {r: V.replay(vt, r) for r in (0.0025, 0.005, 0.0075)}
    # glitch screen sensitivity: drop signal bars with range > 25 ATR
    scr = [t for t in tr if True]
    keep = {(t["sym"], t["t_sig"]) for t in sub if t["rng_atr"] <= 25}
    scr = [t for t in tr if (t["sym"], t["t_sig"]) in keep]
    st_scr = L.stats(scr, edges, B=200) if scr else {}
    per_pair = {}
    for s_ in PAIRS:
        pp = [t for t in tr if t["sym"] == s_]
        if pp:
            xp = L.net_R(pp)
            per_pair[s_] = dict(n=len(pp), exp=float(xp.mean()), wr=float((L.net_R(pp) > 0).mean()),
                                gross_win_rate=float(np.mean([t["R_pess"] >= TARGET_R - 1e-9 for t in pp])))
    n_tgt = sum(1 for t in tr if t["R_pess"] >= TARGET_R - 1e-9)
    n_to = sum(1 for t in sub if -1.0 + 1e-9 < t["R_strict"] < TARGET_R - 1e-9)
    n_stop = sum(1 for t in sub if t["R_strict"] <= -1.0 + 1e-9)
    gap_excess = float(np.mean([t["R_strict"] - t["R_repo"] for t in sub]))
    gates = {
        "O1": (st["n"] >= 300, f"n={st['n']}"),
        "O2": (st["exp"] >= 0.10 and st["lb90"] > 0, f"exp={st['exp']:+.4f} lb90={st['lb90']:+.4f}"),
        "O3": (st["pf"] >= 1.20, f"pf={st['pf']:.3f}"),
        "O4": (st["exp_x15"] > 0 and float(x_slip.mean()) > 0, f"x1.5 spread={st['exp_x15']:+.4f}, +0.10R slippage={float(x_slip.mean()):+.4f}"),
        "O5": (sum(1 for h in st["halves"] if h == h and h > 0) >= 4, f"years={[round(h, 3) for h in st['halves']]}"),
        "O6": (st["top_share"] <= 0.40 and st["exp_ex_top"] > 0 and top_day_share <= 0.15,
               f"top pair {st['top_pair']} {st['top_share']:.0%}, ex-top exp={st['exp_ex_top']:+.4f}, top day {top_day_share:.1%}, top5 days {top5_share:.1%}"),
        "O7": (wf[0.005]["pass_rate"] >= 0.70 and wf[0.005]["worst_day"] >= -125.0,
               f"pass={wf[0.005]['pass_rate']:.1%} med_days={wf[0.005]['med_days']} floor_busts={wf[0.005]['floor_busts']} daily_busts={wf[0.005]['daily_busts']} maxDD={wf[0.005]['max_dd']:.1%}"),
    }
    susp = []
    if st["pf"] > 3: susp.append("PF>3")
    if (st["exp"] > 0) != (st["exp_opt"] > 0): susp.append("sign flip strict vs repo rule")
    if wf[0.005]["max_dd"] < 0.01: susp.append("DD<1%")
    coin_ok = st["exp_coin"] > 0
    gates["O9"] = (not susp and coin_ok, f"triggers={susp or 'none'}; coin exp={st['exp_coin']:+.4f}; strict={st['exp']:+.4f}; repo-rule={st['exp_opt']:+.4f}")
    return dict(label=label, stats=st, gates={k: [bool(v[0]), v[1]] for k, v in gates.items()}, by_spread_multiple=by_spread,
                walk_forward={str(k): v for k, v in wf.items()}, per_pair=per_pair, screened_25atr=dict(n=st_scr.get("n"), exp=st_scr.get("exp"), pf=st_scr.get("pf")),
                outcome=dict(target=n_tgt, timeout=n_to, stop=n_stop, target_rate=n_tgt / len(sub)), gap_penalty_mean_R=gap_excess,
                top_day_share=top_day_share, top5_day_share=top5_share, n_signals_raw=len(sub))


def print_eval(ev: dict) -> None:
    st = ev["stats"]
    if not st.get("n"):
        print(ev["label"], "n=0")
        return
    print(f"== {ev['label']}: n={st['n']} target-rate={ev['outcome']['target_rate']:.3f} (stop {ev['outcome']['stop']}, timeout {ev['outcome']['timeout']}) "
          f"strict net exp={st['exp']:+.4f}R PF={st['pf']:.3f} gross={st['exp_gross']:+.4f} cost={st['cost_mean_R']:.3f} repo-rule exp={st['exp_opt']:+.4f} "
          f"coin={st['exp_coin']:+.4f} lb90={st['lb90']:+.4f} gap penalty={ev['gap_penalty_mean_R']:+.4f}R")
    print("   net exp by spread multiple:", {k: round(v, 4) for k, v in ev["by_spread_multiple"].items()})
    print("   years:", [round(h, 3) for h in st["halves"]], " per pair:", {k: (v["n"], round(v["exp"], 3)) for k, v in ev["per_pair"].items()})
    print("   glitch screen (range<=25 ATR):", ev["screened_25atr"])
    for r, w in ev["walk_forward"].items():
        print(f"   walk-forward risk {float(r)*100:.2f}%: pass={w['pass_rate']:.1%} med={w['med_days']}d p90={w['p90']}d maxDD={w['max_dd']:.1%} worstDay=${w['worst_day']:.0f} floorBust={w['floor_busts']} dailyBust={w['daily_busts']}")
    for k, (ok, txt) in ev["gates"].items():
        print(f"   {k}: {'PASS' if ok else 'FAIL'}  {txt}")


OUT = Path("/tmp/exh_out")
OUT.mkdir(exist_ok=True)
YEARS_OOS = [f"{y}-09-11" for y in range(2016, 2023)]
YEARS_REP = [f"{y}-09-11" for y in range(2022, 2027)]


def cmd_run(window: str) -> None:
    if window == "placebo":
        for lbl, lo, hi in (("2016-09..2022-09", "2016-09-11", "2022-09-11"), ("2022-09..2026-09", "2022-09-11", "2026-09-11")):
            r = placebo("ci", ms(lo), ms(hi))
            sig = [t for t in all_signals("ci") if ms(lo) <= t["t_sig"] < ms(hi)]
            real_g = float(np.mean([t["R_strict"] for t in sig]))
            print(f"placebo {lbl}: random bars n={r['n']} gross={r['gross']:+.4f} net={r['net']:+.4f} target-rate={r['target_rate']:.3f} | "
                  f"real signals n={len(sig)} gross={real_g:+.4f} target-rate={np.mean([t['R_strict']>=TARGET_R-1e-9 for t in sig]):.3f}")
        return
    if window == "oos":
        sig = all_signals("ci")
        ev = evaluate(sig, ms("2016-09-11"), ms("2022-09-11"), YEARS_OOS, "OOS-A 2016-09-11..2022-09-11 (Dukascopy)")
    elif window == "rep":
        ci = all_signals("ci")
        fsb = all_signals("tracked")
        lo, hi = ms("2022-09-11"), ms("2026-09-11")
        A = {(t["sym"], t["t_sig"]) for t in ci if lo <= t["t_sig"] < hi}
        B = {(t["sym"], t["t_sig"]) for t in fsb if lo <= t["t_sig"] < hi}
        inter = len(A & B)
        ev = evaluate(ci, lo, hi, YEARS_REP, "REP 2022-09-11..2026-09-11 (Dukascopy source)")
        ev["overlap"] = dict(ci=len(A), fsb=len(B), both=inter, match_over_max=inter / max(len(A), len(B)))
        ev_f = evaluate(fsb, lo, hi, YEARS_REP, "REP-FSB same window, tracked source", boot=2000)
        ev["fsb_same_window"] = ev_f["stats"]
        print_eval(ev_f)
        print(f"   O8: overlap (pair,signal-bar) ci={len(A)} fsb={len(B)} both={inter} match/max={inter/max(len(A),len(B)):.1%}")
    else:
        sig = all_signals("ci")
        ev = evaluate(sig, ms("2026-09-13"), ms("2027-01-01"), ["2026-09-13", "2027-01-01"], "FWD 2026-09-13..end", boot=2000)
    print_eval(ev)
    (OUT / f"{window}.json").write_text(json.dumps(ev, indent=1, default=float))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("repro")
    r = sub.add_parser("run")
    r.add_argument("--window", choices=["oos", "rep", "fwd", "placebo"], required=True)
    a = ap.parse_args()
    if a.cmd == "repro":
        repro()
    else:
        cmd_run(a.window)
