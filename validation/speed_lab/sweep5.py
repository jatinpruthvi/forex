"""
speed_lab/sweep5.py — try to break the sweep4 winner.

Checks, in order:
  1. GRID BOUNDARY: sweep4's optimum sat at TR=6.0 (grid max) and SA=1.5 (grid
     min). Extend both directions to confirm a plateau, not a cliff.
  2. EXIT COMPOSITION: with TR=6 the target is rarely reached. How much of the
     edge is really a 96h TIME exit? Report stop/target/timeout split.
  3. ENTRY FILL: signal detected on the bar close -> is the edge surviving if we
     fill at the NEXT bar's open instead (no same-bar fill)?
  4. LONG/SHORT: sweep4(g) showed positive long / negative short on most pairs.
     Is that a regime artefact? Score long-only vs short-only on TRAIN and TEST
     independently.
  5. CLEAN PROTOCOL: select config AND controls on TRAIN only, then evaluate TEST
     exactly once, untouched.
  6. PLAN-COMPLIANT VARIANT: max 1 concurrent position (plan s.2 "one open
     position account-wide") and max 2 trades/day.

  python3 validation/speed_lab/sweep5.py
"""
from __future__ import annotations

import sys, time, json, itertools
import numpy as np
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import engine as E
import portfolio as P
from sweep4 import build, agg, resolve_pair

TRAIN_END = 1726012800000
CACHE = Path("/tmp/speedlab_cache")
BEST = json.loads((CACHE / "chosen.json").read_text())
KEY, CH = BEST["KEY"], BEST["CH"]


def trades_for(syms, lo, hi, entry="close", long_only=False, short_only=False, **kw):
    per, det = {}, {}
    for sym in syms:
        d = E.load_ohlc(sym, kw["tf"], "m5")
        hold = max(8, int(kw["hh"] * 60 / kw["tf"]))
        s = E.signals(d, sym, "rev", k=kw["k"], stop_atr=kw["sa"], target_r=kw["tr"],
                      n_ch=20, entry=entry)
        if s is None:
            continue
        r = E.resolve(s, d, max_hold_bars=hold)
        m = (r["ts"] >= lo) & (r["ts"] < hi)
        if long_only:
            m &= r["direction"] > 0
        if short_only:
            m &= r["direction"] < 0
        if m.sum() < 5:
            continue
        per[sym] = {kk: vv[m] for kk, vv in r.items()}
        det[sym] = E.expectancy(s, per[sym], sym)
    return P.build_trades(per), per, det


def line(lbl, wf):
    if wf is None or wf["n_pass"] == 0:
        return f"  {lbl:<46} pass   0.0%   --"
    return (f"  {lbl:<46} pass {wf['pass_rate']*100:>5.1f}%  median {wf['med_days']:>4} d  "
            f"p25 {wf['p25_days']:>3}  p90 {wf['p90_days']:>4}  worst {wf['worst_days']:>4}  "
            f"maxDD {wf['max_dd']*100:>5.1f}%  worstDay ${wf['worst_day']:>6.0f}  "
            f"qualD {wf['med_qual']:>2}  tr {wf['med_trades']:>3}")


def main():
    t0 = time.time()
    KW = dict(tf=KEY["tf"], k=KEY["k"], sa=KEY["sa"], tr=KEY["tr"], hh=KEY["hh"])
    CFG = P.Cfg(risk_pct=CH["risk"], max_concurrent=CH["conc"], max_trades_day=CH["cap"],
                daily_stop_R=CH["dstop"], risk_mode=CH["mode"])
    print(f"frozen config: M{KW['tf']} rev k={KW['k']} SA={KW['sa']} TR={KW['tr']} hold={KW['hh']}h")
    print(f"frozen controls: {CH['risk']*100:.2f}% risk, <={CH['conc']} concurrent, "
          f"<={CH['cap']}/day, breaker {CH['dstop']:g}R, base={CH['mode']}")

    # ---------------- 1. grid boundary ----------------
    print("\n" + "=" * 124)
    print("1. GRID BOUNDARY CHECK — extend TR above 6 and SA below 1.5 / above 3")
    print("=" * 124)
    print(f"{'SA':>6}{'TR':>6} | {'n':>6}{'t/day':>7}{'stopP':>8}{'cost%':>7}{'WR%':>7}"
          f"{'Egross':>9}{'Enet':>9}{'Enet*t/day':>12}{'+pairs':>8}")
    print("-" * 124)
    grid = []
    for sa, tr in itertools.product([1.0, 1.5, 2.0, 3.0, 4.0], [4.0, 6.0, 8.0, 10.0, 14.0]):
        _, _, det = trades_for(E.ALL_PAIRS, TRAIN_END, 1 << 62, **{**KW, "sa": sa, "tr": tr})
        a = agg(det)
        if a["n"] < 100:
            continue
        grid.append(dict(sa=sa, tr=tr, **a))
        mark = "  <-- sweep4 pick" if (sa == KW["sa"] and tr == KW["tr"]) else ""
        print(f"{sa:>6.1f}{tr:>6.1f} | {a['n']:>6}{a['tpd']:>7.2f}"
              f"{sum(det[s]['med_stop']*det[s]['n'] for s in det)/a['n']:>8.2f}"
              f"{a['cost']*100:>7.1f}{a['wr']*100:>7.1f}{a['eg']:>+9.4f}{a['en']:>+9.4f}"
              f"{a['en']*a['tpd']:>+12.3f}{a['pos']:>5}/{a['pairs']:<2}{mark}")
    b = max(grid, key=lambda r: r["en"] * r["tpd"])
    print(f"\n  best E_net x trades/day in the EXTENDED grid: SA={b['sa']} TR={b['tr']} "
          f"-> {b['en']*b['tpd']:+.3f} R/day  (sweep4 pick gave "
          f"{max((g['en']*g['tpd'] for g in grid if g['sa']==KW['sa'] and g['tr']==KW['tr']), default=0):+.3f})")
    print(f"  plateau width: {sum(1 for g in grid if g['en']*g['tpd'] > 0.8*b['en']*b['tpd'])}"
          f"/{len(grid)} cells reach >80% of the best R/day -> "
          f"{'BROAD PLATEAU (robust)' if sum(1 for g in grid if g['en']*g['tpd'] > 0.8*b['en']*b['tpd']) >= len(grid)//3 else 'SHARP PEAK (suspicious)'}")

    # ---------------- 2. exit composition ----------------
    print("\n" + "=" * 124)
    print("2. EXIT COMPOSITION — how much of the edge is a TIME exit rather than the +6R target?")
    print("=" * 124)
    _, per, det = trades_for(E.ALL_PAIRS, TRAIN_END, 1 << 62, **KW)
    res = np.concatenate([per[s]["resolved"] for s in per])
    win = np.concatenate([per[s]["win"] for s in per])
    R = np.concatenate([per[s]["R_gross"] for s in per])
    to = ~res
    print(f"  total trades {len(R)}")
    for lbl, m in (("stop hit (loss)", res & ~win), ("target hit (+TR)", res & win),
                   ("timeout -> market, profitable", to & (R > 0)),
                   ("timeout -> market, losing", to & (R <= 0))):
        print(f"    {lbl:<34} {m.sum():>6}  ({m.mean()*100:>5.1f}%)   total R {R[m].sum():>+10.1f}"
              f"   mean R {R[m].mean() if m.sum() else 0:>+7.3f}")
    print(f"  -> share of total net R coming from timeouts: "
          f"{R[to].sum()/R.sum()*100:+.1f}%   (from the +TR target: {R[res&win].sum()/R.sum()*100:+.1f}%)")

    # ---------------- 3. entry fill ----------------
    print("\n" + "=" * 124)
    print("3. ENTRY FILL — signal on bar close, filled at the NEXT bar's open (no same-bar fill)")
    print("=" * 124)
    for entry, lbl in (("close", "fill at signal-bar close (as modelled)"),
                       ("next", "fill at NEXT bar open (conservative)")):
        tr, _, dt = trades_for(E.ALL_PAIRS, TRAIN_END, 1 << 62, entry=entry, **KW)
        a = agg(dt)
        print(f"  {lbl:<46} n={a['n']:<6} E_gross {a['eg']:+.4f}R  cost {a['cost']*100:>5.1f}%  "
              f"E_net {a['en']:+.4f}R")
        print(line(f"    walk-forward TEST ({entry} fill)", P.walk_forward(tr, CFG, 40)))

    # ---------------- 4. long/short ----------------
    print("\n" + "=" * 124)
    print("4. LONG/SHORT DECOMPOSITION — regime artefact or structural?")
    print("=" * 124)
    print(f"  {'window':<12}{'side':<8}{'pairs':>6}{'n':>7}{'t/day':>8}{'Egross':>9}{'cost%':>8}{'Enet':>9}{'+pairs':>9}")
    for lo, hi, wl in ((0, TRAIN_END, "TRAIN"), (TRAIN_END, 1 << 62, "TEST")):
        days = (min(hi, 1789000000000) - max(lo, 1662940800000)) / 86_400_000
        for kw2, side in ((dict(), "both"), (dict(long_only=True), "LONG"),
                          (dict(short_only=True), "SHORT")):
            _, _, dt = trades_for(E.ALL_PAIRS, lo, hi, **KW, **kw2)
            a = agg(dt)
            a["tpd"] = a["n"] / days
            print(f"  {wl:<12}{side:<8}{a['pairs']:>6}{a['n']:>7}{a['tpd']:>8.2f}"
                  f"{a['eg']:>+9.4f}{a['cost']*100:>8.1f}{a['en']:>+9.4f}"
                  f"{a['pos']:>6}/{a['pairs']:<2}")
    print("\n  walk-forward, TEST half:")
    for kw2, side in ((dict(), "both sides"), (dict(long_only=True), "LONG only"),
                      (dict(short_only=True), "SHORT only")):
        tr, _, _ = trades_for(E.ALL_PAIRS, TRAIN_END, 1 << 62, **KW, **kw2)
        print(line(f"    {side}", P.walk_forward(tr, CFG, 40)))

    # ---------------- 5. clean protocol ----------------
    print("\n" + "=" * 124)
    print("5. CLEAN PROTOCOL — pick config AND controls on TRAIN ONLY, then touch TEST once")
    print("=" * 124)
    cand = []
    for k, sa, tr in itertools.product([3.0, 3.5, 4.0, 4.5, 5.0], [1.0, 1.5, 2.0, 3.0],
                                       [3.0, 4.0, 6.0, 8.0]):
        trs, _, dt = trades_for(E.ALL_PAIRS, 0, TRAIN_END, k=k, sa=sa, tr=tr,
                                **{**KW, "k": k, "sa": sa, "tr": tr})
        a = agg(dt)
        if a["n"] < 300 or a["en"] <= 0:
            continue
        cand.append((a["en"] * a["tpd"], k, sa, tr, trs))
    cand.sort(key=lambda x: -x[0])
    print(f"  TRAIN-viable parameter cells: {len(cand)}")
    print("  top 5 by TRAIN E_net x trades/day:")
    for sc, k, sa, tr, _ in cand[:5]:
        print(f"    k={k:<4} SA={sa:<4} TR={tr:<4}  TRAIN {sc:+.3f} R/day")
    sel = cand[0]
    _, k_sel, sa_sel, tr_sel, trs_tr = sel
    print(f"\n  TRAIN-selected config: k={k_sel} SA={sa_sel} TR={tr_sel}")
    best_ctrl = None
    for r, mc, cap, ds in itertools.product([0.005, 0.0075, 0.01, 0.015, 0.02],
                                            [1, 2, 3, 4], [2, 3, 5, 8], [1.5, 2.0, 1e9]):
        cfg = P.Cfg(risk_pct=r, max_concurrent=mc, max_trades_day=cap, daily_stop_R=ds)
        wf = P.walk_forward(trs_tr, cfg, 40)
        if wf["n_pass"] == 0:
            continue
        key = (wf["pass_rate"], -wf["med_days"])
        if best_ctrl is None or key > best_ctrl[0]:
            best_ctrl = (key, cfg, wf)
    cfg_tr, wf_tr = best_ctrl[1], best_ctrl[2]
    print(f"  TRAIN-selected controls: {cfg_tr.risk_pct*100:.2f}% risk, <={cfg_tr.max_concurrent} "
          f"concurrent, <={cfg_tr.max_trades_day}/day, breaker {cfg_tr.daily_stop_R:g}R")
    print(line("TRAIN (in-sample for the selection)", wf_tr))
    trs_te, _, det_te = trades_for(E.ALL_PAIRS, TRAIN_END, 1 << 62,
                                   k=k_sel, sa=sa_sel, tr=tr_sel,
                                   **{**KW, "k": k_sel, "sa": sa_sel, "tr": tr_sel})
    print(line("TEST (UNTOUCHED, evaluated once)", P.walk_forward(trs_te, cfg_tr, 40)))
    a_te = agg(det_te)
    print(f"    TEST aggregate E_net {a_te['en']:+.4f}R (gross {a_te['eg']:+.4f}R, cost "
          f"{a_te['cost']*100:.1f}%), {a_te['pos']}/{a_te['pairs']} pairs positive, n={a_te['n']}")

    # ---------------- 6. plan-compliant ----------------
    print("\n" + "=" * 124)
    print("6. PLAN-COMPLIANT VARIANT — 1 concurrent position, <=2 trades/day (plan s.2)")
    print("=" * 124)
    trs_best, _, det_best = trades_for(E.ALL_PAIRS, TRAIN_END, 1 << 62,
                                       k=k_sel, sa=sa_sel, tr=tr_sel,
                                       **{**KW, "k": k_sel, "sa": sa_sel, "tr": tr_sel})
    for mc, cap, lbl in ((1, 2, "1 position, <=2/day  (plan-compliant)"),
                         (1, 5, "1 position, <=5/day"),
                         (2, 2, "2 positions, <=2/day"),
                         (3, 2, "3 positions, <=2/day"),
                         (11, 100, "unconstrained (PR #9 style)")):
        for r in (0.0075, 0.01, 0.015, 0.02, 0.025):
            cfg = P.Cfg(risk_pct=r, max_concurrent=mc, max_trades_day=cap, daily_stop_R=1.5)
            wf = P.walk_forward(trs_best, cfg, 40)
            if wf["n_pass"] == 0:
                continue
            print(line(f"  {lbl} @ {r*100:.2f}% risk", wf))
            break

    print(f"\ntotal {time.time()-t0:.0f}s")


if __name__ == "__main__":
    main()
