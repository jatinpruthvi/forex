"""
speed_lab/sweep6.py — honest-fill re-optimisation and final protocol.

sweep5 exposed two things that change the answer:
  * filling at the SIGNAL BAR CLOSE is not attainable live (you only know the
    bar is extreme once it has closed). Refilling at the NEXT bar's open cut
    E_net from +0.41R to +0.10R. Every number from here on uses next-open fill.
  * the SHORT side of the fade is negative in BOTH the TRAIN and TEST halves,
    while the LONG side is positive on 10/11 pairs in BOTH. So long-only is
    tested as its own candidate rather than assumed.

Stages:
  1  boundary re-search under honest fill (stop width, target R, threshold,
     timeframe, max hold), both-sides vs long-only
  2  CLEAN PROTOCOL: select config + controls on TRAIN only (2022-09..2024-09),
     then evaluate TEST (2024-09..2026-09) exactly once
  3  robustness on the selected config: cost stress, FX-only, yearly, per-pair,
     plan-compliant 1-position variant
"""
from __future__ import annotations

import sys, time, json, itertools
import numpy as np
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import engine as E
import portfolio as P

TRAIN_END = 1726012800000
T0 = 1662940800000
T_NOW = 1789000000000
CACHE = Path("/tmp/speedlab_cache")
FILL = "next"          # honest: detect on bar close, fill next bar open


def trades_for(syms, lo, hi, tf=5, k=4.0, sa=1.5, tr=6.0, hh=96,
               side="both", spread_scale=1.0):
    per, det = {}, {}
    for sym in syms:
        d = E.load_ohlc(sym, tf, "m5")
        hold = max(8, int(hh * 60 / tf))
        s = E.signals(d, sym, "rev", k=k, stop_atr=sa, target_r=tr, n_ch=20, entry=FILL)
        if s is None:
            continue
        r = E.resolve(s, d, max_hold_bars=hold)
        m = (r["ts"] >= lo) & (r["ts"] < hi)
        if side == "long":
            m &= r["direction"] > 0
        elif side == "short":
            m &= r["direction"] < 0
        if m.sum() < 5:
            continue
        per[sym] = {kk: vv[m] for kk, vv in r.items()}
        det[sym] = E.expectancy(s, per[sym], sym, spread_scale)
    return P.build_trades(per, spread_scale), per, det


def agg(det, days=730.0):
    if not det:
        return dict(pairs=0, n=0, en=0.0, eg=0.0, cost=0.0, tpd=0.0, pos=0, wr=0.0, amb=0.0)
    n = sum(e["n"] for e in det.values())
    w = lambda key: sum(e[key] * e["n"] for e in det.values()) / max(n, 1)
    return dict(pairs=len(det), n=n, en=w("e_net"), eg=w("e_gross"), cost=w("cost_R"),
                wr=w("wr"), amb=w("amb"), tpd=n / days,
                pos=sum(1 for e in det.values() if e["e_net"] > 0))


def line(lbl, wf):
    if wf is None or wf["n_pass"] == 0:
        return f"  {lbl:<52} pass   0.0%  --"
    return (f"  {lbl:<52} pass {wf['pass_rate']*100:>5.1f}%  med {wf['med_days']:>4}d  "
            f"p25 {wf['p25_days']:>3}  p75 {wf['p75_days']:>3}  p90 {wf['p90_days']:>3}  "
            f"worst {wf['worst_days']:>4}  maxDD {wf['max_dd']*100:>5.1f}%  "
            f"day ${wf['worst_day']:>6.0f}  qual {wf['med_qual']:>2}  tr {wf['med_trades']:>3}")


def main():
    t0 = time.time()
    FX = [s for s in E.ALL_PAIRS if s != "XAUUSD"]

    # =============== 1. honest-fill boundary re-search ===============
    print("=" * 130)
    print(f"1. BOUNDARY RE-SEARCH UNDER HONEST FILL (next-bar open), TEST half")
    print("=" * 130)
    print(f"{'tf':>4}{'k':>5}{'SA':>5}{'TR':>5}{'hold':>6}{'side':>7} | {'pairs':>6}{'n':>6}"
          f"{'t/day':>7}{'stopP':>8}{'cost%':>7}{'WR%':>6}{'Egross':>9}{'Enet':>9}"
          f"{'R/day':>8}{'+pr':>6}")
    print("-" * 130)
    cells = []
    for tf, k, sa, tr, hh, side in itertools.product(
            [5, 15], [3.0, 4.0, 5.0], [1.0, 1.5, 2.0, 3.0], [4.0, 6.0, 8.0, 10.0],
            [96], ["both", "long"]):
        _, _, det = trades_for(E.ALL_PAIRS, TRAIN_END, 1 << 62, tf=tf, k=k, sa=sa,
                               tr=tr, hh=hh, side=side)
        a = agg(det)
        if a["n"] < 200 or a["en"] <= 0:
            continue
        stop = sum(det[s]["med_stop"] * det[s]["n"] for s in det) / a["n"]
        cells.append(dict(tf=tf, k=k, sa=sa, tr=tr, hh=hh, side=side, stop=stop, **a))
        print(f"{tf:>4}{k:>5.1f}{sa:>5.1f}{tr:>5.1f}{hh:>6}{side:>7} | {a['pairs']:>6}"
              f"{a['n']:>6}{a['tpd']:>7.2f}{stop:>8.2f}{a['cost']*100:>7.1f}"
              f"{a['wr']*100:>6.1f}{a['eg']:>+9.4f}{a['en']:>+9.4f}"
              f"{a['en']*a['tpd']:>+8.3f}{a['pos']:>4}/{a['pairs']:<2}")
    cells.sort(key=lambda c: -c["en"] * c["tpd"])
    print(f"\n  cells with positive TEST E_net: {len(cells)}")
    print("  top 10 by R/day (= E_net x trades/day, the days-to-pass driver):")
    for c in cells[:10]:
        print(f"    M{c['tf']:<3} k={c['k']:<4} SA={c['sa']:<4} TR={c['tr']:<4} hold={c['hh']:<3}"
              f" {c['side']:<5} E_net {c['en']:+.4f}R x {c['tpd']:.2f}/d = {c['en']*c['tpd']:+.3f} R/d"
              f"  stop {c['stop']:>6.2f}p cost {c['cost']*100:>5.1f}%  {c['pos']}/{c['pairs']} pairs +")
    top = cells[0]
    CACHE.joinpath("sweep6_cells.json").write_text(json.dumps(cells))

    # =============== 2. CLEAN PROTOCOL ===============
    print("\n" + "=" * 130)
    print("2. CLEAN PROTOCOL — select config AND controls on TRAIN ONLY, evaluate TEST ONCE")
    print("=" * 130)
    tr_cells = []
    for tf, k, sa, tr, hh, side in itertools.product(
            [5, 15], [3.0, 4.0, 5.0], [1.0, 1.5, 2.0, 3.0], [4.0, 6.0, 8.0, 10.0],
            [96], ["both", "long"]):
        trs, _, det = trades_for(E.ALL_PAIRS, T0, TRAIN_END, tf=tf, k=k, sa=sa, tr=tr,
                                 hh=hh, side=side)
        a = agg(det, (TRAIN_END - T0) / 86_400_000)
        if a["n"] < 200 or a["en"] <= 0 or not trs:
            continue
        tr_cells.append((a["en"] * a["tpd"], dict(tf=tf, k=k, sa=sa, tr=tr, hh=hh,
                                                  side=side), a, trs))
    tr_cells.sort(key=lambda x: -x[0])
    print(f"  TRAIN-viable cells: {len(tr_cells)}   (top 5)")
    for sc, kw, a, _ in tr_cells[:5]:
        print(f"    M{kw['tf']:<3} k={kw['k']:<4} SA={kw['sa']:<4} TR={kw['tr']:<4} "
              f"hold={kw['hh']:<3} {kw['side']:<5} TRAIN E_net {a['en']:+.4f}R x "
              f"{a['tpd']:.2f}/d = {sc:+.3f} R/d   ({a['pos']}/{a['pairs']} pairs +, n={a['n']})")

    SEL = tr_cells[0][1]
    A_TR = tr_cells[0][2]
    TRS_TR = tr_cells[0][3]
    print(f"\n  TRAIN-selected: M{SEL['tf']} rev k={SEL['k']} SA={SEL['sa']} TR={SEL['tr']} "
          f"hold={SEL['hh']}h side={SEL['side']}")

    best = None
    for r, mc, cap, ds, mode in itertools.product(
            [0.005, 0.0075, 0.01, 0.0125, 0.015, 0.02, 0.025, 0.03],
            [1, 2, 3, 4, 6], [1, 2, 3, 5, 8, 100], [1.0, 1.5, 2.0, 3.0, 1e9],
            ["initial", "equity"]):
        cfg = P.Cfg(risk_pct=r, max_concurrent=mc, max_trades_day=cap,
                    daily_stop_R=ds, risk_mode=mode)
        wf = P.walk_forward(TRS_TR, cfg, 40)
        if wf["n_pass"] == 0:
            continue
        if wf["worst_day"] < -(E.ACCOUNT * E.DAILY_LOSS):
            continue                      # must not breach the firm daily loss limit
        key = (wf["pass_rate"], -wf["med_days"])
        if best is None or key > best[0]:
            best = (key, cfg, wf)
    CFG = best[1]
    print(f"  TRAIN-selected controls: {CFG.risk_pct*100:.2f}% risk, <= {CFG.max_concurrent} "
          f"concurrent, <= {CFG.max_trades_day}/day, breaker {CFG.daily_stop_R:g}R, "
          f"base={CFG.risk_mode}")
    print(line("TRAIN (in-sample for selection)", best[2]))

    TRS_TE, PER_TE, DET_TE = trades_for(E.ALL_PAIRS, TRAIN_END, 1 << 62, **SEL)
    A_TE = agg(DET_TE)
    WF_TE = P.walk_forward(TRS_TE, CFG, 60)
    print(line("TEST (UNTOUCHED — evaluated exactly once)", WF_TE))
    print(f"    TEST aggregate: {A_TE['pairs']} pairs, n={A_TE['n']} ({A_TE['tpd']:.2f}/day), "
          f"E_gross {A_TE['eg']:+.4f}R, cost {A_TE['cost']*100:.1f}%, "
          f"E_net {A_TE['en']:+.4f}R, WR {A_TE['wr']*100:.1f}%, "
          f"{A_TE['pos']}/{A_TE['pairs']} pairs positive")

    # =============== 3. robustness on the SELECTED config ===============
    print("\n" + "=" * 130)
    print("3. ROBUSTNESS OF THE SELECTED CONFIG (TRAIN-selected, TEST-evaluated)")
    print("=" * 130)
    print("\n  (a) cost stress — repo gate #4 requires profit at spread x1.5 and slippage x2")
    for lbl, ss, sl in (("base (0.55x std spread, $7/lot)", 1.0, 0.0),
                        ("spread x1.5", 1.5, 0.0),
                        ("spread x2.0", 2.0, 0.0),
                        ("+0.10R slippage per trade", 1.0, 0.10),
                        ("spread x1.5 AND +0.10R slip", 1.5, 0.10),
                        ("spread x2.0 AND +0.20R slip", 2.0, 0.20)):
        trs, _, det = trades_for(E.ALL_PAIRS, TRAIN_END, 1 << 62, spread_scale=ss, **SEL)
        a = agg(det)
        c = P.Cfg(**{**CFG.__dict__, "slippage_R": sl})
        wf = P.walk_forward(trs, c, 40)
        print(f"    E_net {a['en']:+.4f}R |{line(lbl, wf)[2:]}")

    print("\n  (b) FX-only — drop XAUUSD (plan s.2 disables it; it is a trending-regime pair)")
    trs, _, det = trades_for(FX, TRAIN_END, 1 << 62, **SEL)
    a = agg(det)
    print(f"    FX-only E_net {a['en']:+.4f}R, {a['pos']}/{a['pairs']} pairs +, n={a['n']}")
    print(line("FX-only walk-forward TEST", P.walk_forward(trs, CFG, 40)))

    print("\n  (c) year-by-year, same frozen config (E_net per 12-month window)")
    for lo, hi, lbl in ((T0, 1694390400000, "2022-09..2023-09"),
                        (1694390400000, TRAIN_END, "2023-09..2024-09"),
                        (TRAIN_END, 1757548800000, "2024-09..2025-09"),
                        (1757548800000, 1 << 62, "2025-09..2026-09")):
        _, _, det = trades_for(E.ALL_PAIRS, lo, hi, **SEL)
        a = agg(det, (min(hi, T_NOW) - lo) / 86_400_000)
        print(f"    {lbl}: {a['pairs']:>2} pairs  n={a['n']:>5} ({a['tpd']:>5.2f}/d)  "
              f"E_gross {a['eg']:+.4f}R  cost {a['cost']*100:>5.1f}%  E_net {a['en']:+.4f}R  "
              f"{a['pos']}/{a['pairs']} pairs +")

    print("\n  (d) per-pair contribution (TEST half)")
    print(f"    {'sym':<8}{'n':>6}{'stopP':>8}{'cost%':>7}{'WR%':>7}{'Egross':>9}{'Enet':>9}"
          f"{'PF':>6}{'totalR':>9}")
    tot = 0.0
    for sym in sorted(DET_TE, key=lambda s: -DET_TE[s]["e_net"] * DET_TE[s]["n"]):
        e = DET_TE[sym]
        tot += e["e_net"] * e["n"]
        print(f"    {sym:<8}{e['n']:>6}{e['med_stop']:>8.2f}{e['cost_R']*100:>7.1f}"
              f"{e['wr']*100:>7.1f}{e['e_gross']:>+9.4f}{e['e_net']:>+9.4f}{e['pf']:>6.2f}"
              f"{e['e_net']*e['n']:>+9.0f}")
    print(f"    {'TOTAL':<8}{'':>6}{'':>8}{'':>7}{'':>7}{'':>9}{'':>9}{'':>6}{tot:>+9.0f}")

    print("\n  (e) plan-compliant variant — 1 concurrent position, <=2 trades/day (plan s.2)")
    for mc, cap in ((1, 2), (1, 3), (2, 2), (1, 100)):
        got = False
        for r in (0.01, 0.0125, 0.015, 0.02, 0.025, 0.03):
            cfg = P.Cfg(risk_pct=r, max_concurrent=mc, max_trades_day=cap,
                        daily_stop_R=CFG.daily_stop_R, risk_mode=CFG.risk_mode)
            wf = P.walk_forward(TRS_TE, cfg, 40)
            if wf["n_pass"] == 0:
                continue
            print(line(f"<= {mc} position(s), <= {cap}/day @ {r*100:.2f}% risk", wf))
            got = True
            break
        if not got:
            print(f"    <= {mc} position(s), <= {cap}/day: no viable risk level")

    print("\n  (f) risk-level sweep at the selected controls (speed vs reliability)")
    print(f"    {'risk%':>7}{'pass%':>8}{'medD':>6}{'p90D':>6}{'worstD':>8}{'maxDD%':>8}"
          f"{'day$':>8}{'floorBust':>11}")
    for r in (0.0025, 0.005, 0.0075, 0.01, 0.015, 0.02, 0.025, 0.03, 0.04, 0.05):
        cfg = P.Cfg(**{**CFG.__dict__, "risk_pct": r})
        wf = P.walk_forward(TRS_TE, cfg, 40)
        fl = sum(1 for x in wf["results"] if "floor" in x.fail_reason)
        if wf["n_pass"] == 0:
            print(f"    {r*100:>7.2f}{0.0:>8.1f}{'-':>6}{'-':>6}{'-':>8}"
                  f"{wf['max_dd']*100:>8.1f}{wf['worst_day']:>8.0f}{fl:>11}")
            continue
        print(f"    {r*100:>7.2f}{wf['pass_rate']*100:>8.1f}{wf['med_days']:>6}"
              f"{wf['p90_days']:>6}{wf['worst_days']:>8}{wf['max_dd']*100:>8.1f}"
              f"{wf['worst_day']:>8.0f}{fl:>11}")

    CACHE.joinpath("final.json").write_text(json.dumps(
        dict(SEL=SEL, CFG={k: v for k, v in CFG.__dict__.items()},
             train=A_TR, test=A_TE,
             wf_test={k: v for k, v in WF_TE.items() if k != "results"}), default=str))
    print(f"\ntotal {time.time()-t0:.0f}s")


if __name__ == "__main__":
    main()
