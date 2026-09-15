"""
speed_lab/sweep4.py — refine the optimum and then try to break it.

Stage 1  local grid refinement around the sweep3 leader (threshold, stop width,
         target, timeframe, max hold)
Stage 2  portfolio-control search (risk, concurrency, daily cap, circuit breaker)
Stage 3  ROBUSTNESS SUITE — every check PR #9 skipped:
           a) frozen config re-run on the untouched TRAIN half (2022-2024)
           b) cost stress: spread x1.5, and +0.10R slippage per trade
           c) FX-only (drop XAUUSD, which is a trending-regime instrument)
           d) year-by-year stability
           e) per-pair contribution (is one pair carrying it?)
           f) intrabar ambiguity rate (how much is decided by an unknowable path)
           g) long/short balance (is it just a directional bet?)

  python3 validation/speed_lab/sweep4.py
"""
from __future__ import annotations

import sys, time, json, itertools
import numpy as np
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import engine as E
import portfolio as P

TRAIN_END = 1726012800000
CACHE = Path("/tmp/speedlab_cache")


def resolve_pair(sym, tf, fam, k, sa, tr, hold_h, n_ch=20):
    d = E.load_ohlc(sym, tf, "m5")
    hold = max(8, int(hold_h * 60 / tf))
    kw = (dict(k=k, stop_atr=sa, target_r=tr, n_ch=n_ch) if fam in ("rev", "mom")
          else dict(n_ch=n_ch, stop_atr=sa, target_r=tr))
    s = E.signals(d, sym, fam, **kw)
    if s is None:
        return None, None
    return E.resolve(s, d, max_hold_bars=hold), s


def build(sym_list, tf, fam, k, sa, tr, hold_h, lo=0, hi=1 << 62):
    per, det = {}, {}
    for sym in sym_list:
        r, s = resolve_pair(sym, tf, fam, k, sa, tr, hold_h)
        if r is None:
            continue
        m = (r["ts"] >= lo) & (r["ts"] < hi)
        if m.sum() < 10:
            continue
        per[sym] = {kk: vv[m] for kk, vv in r.items()}
        det[sym] = E.expectancy(s, per[sym], sym)
    return per, det


def agg(det):
    if not det:
        return dict(pairs=0, n=0, en=0, eg=0, cost=0, tpd=0, pos=0, amb=0, wr=0)
    n = sum(e["n"] for e in det.values())
    w = lambda key: sum(e[key] * e["n"] for e in det.values()) / max(n, 1)
    return dict(pairs=len(det), n=n, en=w("e_net"), eg=w("e_gross"), cost=w("cost_R"),
                wr=w("wr"), amb=w("amb"), pos=sum(1 for e in det.values() if e["e_net"] > 0),
                tpd=n / 730.0)


def wf_report(trades, cfg, n_starts=40, label=""):
    wf = P.walk_forward(trades, cfg, n_starts=n_starts)
    if wf["n"] == 0:
        return None
    return wf


def main():
    t0 = time.time()
    FX = [s for s in E.ALL_PAIRS if s != "XAUUSD"]

    # ================= STAGE 1: local refinement =================
    print("=" * 122)
    print("STAGE 1 — LOCAL GRID REFINEMENT (all 11 pairs, TEST half 2024-09-11..2026-09-11)")
    print("=" * 122)
    print(f"{'tf':>4}{'k':>6}{'SA':>6}{'TR':>6}{'hold':>6} | {'pairs':>6}{'n':>7}{'t/day':>7}"
          f"{'cost%':>7}{'WR%':>7}{'amb%':>6}{'Egross':>9}{'Enet':>9}{'+pairs':>8}")
    print("-" * 122)
    stage1 = []
    for tf, k, sa, tr, hh in itertools.product(
            [5, 15], [3.0, 3.5, 4.0, 4.5, 5.0], [1.5, 2.0, 2.5, 3.0, 4.0],
            [3.0, 4.0, 5.0, 6.0], [24, 48, 96]):
        per, det = build(E.ALL_PAIRS, tf, "rev", k, sa, tr, hh)
        a = agg(det)
        if a["n"] < 300:
            continue
        stage1.append(dict(tf=tf, k=k, sa=sa, tr=tr, hh=hh, **a))
        print(f"{tf:>4}{k:>6.1f}{sa:>6.1f}{tr:>6.1f}{hh:>6} | {a['pairs']:>6}{a['n']:>7}"
              f"{a['tpd']:>7.2f}{a['cost']*100:>7.1f}{a['wr']*100:>7.1f}{a['amb']*100:>6.1f}"
              f"{a['eg']:>+9.4f}{a['en']:>+9.4f}{a['pos']:>5}/{a['pairs']:<2}")
    stage1.sort(key=lambda r: -(r["en"] * r["tpd"]))
    print(f"\nranked by E_net x trades/day (the days-to-pass driver), top 12:")
    for r in stage1[:12]:
        print(f"   M{r['tf']:<3} k={r['k']:<4} SA={r['sa']:<4} TR={r['tr']:<4} hold={r['hh']:<3}h"
              f"  E_net {r['en']:+.4f}R x {r['tpd']:.2f}/day = {r['en']*r['tpd']:+.3f} R/day"
              f"   ({r['pos']}/{r['pairs']} pairs +, n={r['n']})")
    CACHE.joinpath("stage1.json").write_text(json.dumps(stage1))

    best = stage1[0]
    KEY = dict(tf=best["tf"], k=best["k"], sa=best["sa"], tr=best["tr"], hh=best["hh"])
    print(f"\n>>> frozen for stage 2/3: M{KEY['tf']} rev k={KEY['k']} SA={KEY['sa']} "
          f"TR={KEY['tr']} hold={KEY['hh']}h   [{time.time()-t0:.0f}s]")

    per_te, det_te = build(E.ALL_PAIRS, KEY["tf"], "rev", KEY["k"], KEY["sa"], KEY["tr"],
                           KEY["hh"], lo=TRAIN_END)
    trades_te = P.build_trades(per_te)

    # ================= STAGE 2: control search =================
    print("\n" + "=" * 122)
    print("STAGE 2 — PORTFOLIO CONTROL SEARCH (TEST half, 40 walk-forward start dates each)")
    print("=" * 122)
    rows = []
    for r, mc, cap, ds, mode in itertools.product(
            [0.005, 0.0075, 0.01, 0.0125, 0.015, 0.02, 0.025],
            [1, 2, 3, 4], [2, 3, 5, 8, 12, 100], [1.0, 1.5, 2.0, 3.0, 1e9],
            ["initial", "equity"]):
        cfg = P.Cfg(risk_pct=r, max_concurrent=mc, max_trades_day=cap,
                    daily_stop_R=ds, risk_mode=mode)
        wf = wf_report(trades_te, cfg, 40)
        if not wf or wf["n_pass"] == 0:
            continue
        rows.append(dict(risk=r, conc=mc, cap=cap, dstop=ds, mode=mode,
                         **{k2: v for k2, v in wf.items() if k2 != "results"}))
    rows.sort(key=lambda x: (-x["pass_rate"], x["med_days"]))
    print(f"viable control settings: {len(rows)}")
    print(f"{'risk%':>7}{'conc':>5}{'cap':>5}{'dstop':>7}{'mode':>9}{'pass%':>7}{'medD':>6}"
          f"{'p25':>5}{'p75':>5}{'p90':>5}{'best':>5}{'worst':>6}{'maxDD%':>8}{'worstDay':>10}"
          f"{'qualD':>6}{'trades':>7}{'mc':>4}")
    print("-" * 122)
    for x in rows[:25]:
        print(f"{x['risk']*100:>7.2f}{x['conc']:>5}{x['cap']:>5}{x['dstop']:>7g}{x['mode']:>9}"
              f"{x['pass_rate']*100:>7.1f}{x['med_days']:>6}{x['p25_days']:>5}{x['p75_days']:>5}"
              f"{x['p90_days']:>5}{x['best_days']:>5}{x['worst_days']:>6}{x['max_dd']*100:>8.1f}"
              f"{x['worst_day']:>10.0f}{x['med_qual']:>6}{x['med_trades']:>7}{x['max_conc']:>4}")
    CH = rows[0]
    CFG = P.Cfg(risk_pct=CH["risk"], max_concurrent=CH["conc"], max_trades_day=CH["cap"],
                daily_stop_R=CH["dstop"], risk_mode=CH["mode"])
    CACHE.joinpath("stage2.json").write_text(json.dumps(rows, default=str))
    print(f"\n>>> chosen controls: {CH['risk']*100:.2f}% risk, <= {CH['conc']} concurrent, "
          f"<= {CH['cap']}/day, circuit-breaker at {CH['dstop']:g}R, base={CH['mode']}")

    # ================= STAGE 3: robustness =================
    print("\n" + "=" * 122)
    print("STAGE 3 — ROBUSTNESS SUITE (the checks PR #9 skipped)")
    print("=" * 122)

    def show(label, wf, extra=""):
        if wf is None or wf["n_pass"] == 0:
            print(f"  {label:<44} pass 0%   {extra}")
            return
        print(f"  {label:<44} pass {wf['pass_rate']*100:>5.1f}%  median {wf['med_days']:>4} d  "
              f"p25 {wf['p25_days']:>3}  p90 {wf['p90_days']:>4}  maxDD {wf['max_dd']*100:>5.1f}%  "
              f"worstDay ${wf['worst_day']:>7.0f}  qualD {wf['med_qual']:>3}  {extra}")

    print("\n(a) FROZEN CONFIG ON THE UNTOUCHED TRAIN HALF (2022-09-11..2024-09-11)")
    per_tr, det_tr = build(E.ALL_PAIRS, KEY["tf"], "rev", KEY["k"], KEY["sa"], KEY["tr"],
                           KEY["hh"], hi=TRAIN_END)
    a_tr = agg(det_tr)
    print(f"    TRAIN aggregate: {a_tr['pairs']} pairs, n={a_tr['n']} ({a_tr['tpd']:.2f}/day), "
          f"E_net {a_tr['en']:+.4f}R (gross {a_tr['eg']:+.4f}R, cost {a_tr['cost']*100:.1f}%), "
          f"{a_tr['pos']}/{a_tr['pairs']} pairs positive")
    show("TRAIN walk-forward", wf_report(P.build_trades(per_tr), CFG, 40))

    print("\n(b) COST STRESS  (repo gate #4: profitable at spread x1.5 and slippage x2)")
    show("TEST, spread x1.0 (base)", wf_report(trades_te, CFG, 40))
    c = P.Cfg(**{**CFG.__dict__, "spread_scale": 1.5})
    show("TEST, spread x1.5", wf_report(P.build_trades(per_te, 1.5), c, 40))
    c2 = P.Cfg(**{**CFG.__dict__, "slippage_R": 0.10})
    show("TEST, +0.10R slippage/trade", wf_report(trades_te, c2, 40))
    c3 = P.Cfg(**{**CFG.__dict__, "spread_scale": 1.5, "slippage_R": 0.10})
    show("TEST, spread x1.5 AND +0.10R slip", wf_report(P.build_trades(per_te, 1.5), c3, 40))

    print("\n(c) FX-ONLY — drop XAUUSD (trending-regime instrument, plan s.2 disables it)")
    per_fx = {s: v for s, v in per_te.items() if s != "XAUUSD"}
    det_fx = {s: v for s, v in det_te.items() if s != "XAUUSD"}
    a_fx = agg(det_fx)
    print(f"    FX-only aggregate: {a_fx['pairs']} pairs, n={a_fx['n']} ({a_fx['tpd']:.2f}/day), "
          f"E_net {a_fx['en']:+.4f}R, {a_fx['pos']}/{a_fx['pairs']} pairs positive")
    show("TEST FX-only", wf_report(P.build_trades(per_fx), CFG, 40))

    print("\n(d) YEAR-BY-YEAR STABILITY (same frozen config)")
    edges = [(1662940800000, 1694390400000, "2022-09..2023-09"),
             (1694390400000, 1726012800000, "2023-09..2024-09"),
             (1726012800000, 1757548800000, "2024-09..2025-09"),
             (1757548800000, 1 << 62, "2025-09..2026-09")]
    for lo, hi, lbl in edges:
        pp, dd_ = build(E.ALL_PAIRS, KEY["tf"], "rev", KEY["k"], KEY["sa"], KEY["tr"],
                        KEY["hh"], lo=lo, hi=hi)
        a = agg(dd_)
        days = (min(hi, 1789000000000) - lo) / 86_400_000
        print(f"    {lbl}: {a['pairs']:>2} pairs n={a['n']:>5} ({a['n']/max(days,1):>5.2f}/day) "
              f"E_gross {a['eg']:+.4f}R  cost {a['cost']*100:>5.1f}%  E_net {a['en']:+.4f}R  "
              f"{a['pos']}/{a['pairs']} pairs +")

    print("\n(e) PER-PAIR CONTRIBUTION (TEST half) — is one pair carrying it?")
    print(f"    {'sym':<8}{'n':>6}{'t/day':>7}{'stopP':>8}{'cost%':>7}{'WR%':>7}"
          f"{'Egross':>9}{'Enet':>9}{'PF':>6}{'totalR':>10}")
    tot = 0.0
    for sym in sorted(det_te, key=lambda s: -det_te[s]["e_net"] * det_te[s]["n"]):
        e = det_te[sym]
        tr_tot = e["e_net"] * e["n"]
        tot += tr_tot
        print(f"    {sym:<8}{e['n']:>6}{e['n']/730:>7.2f}{e['med_stop']:>8.2f}"
              f"{e['cost_R']*100:>7.1f}{e['wr']*100:>7.1f}{e['e_gross']:>+9.4f}"
              f"{e['e_net']:>+9.4f}{e['pf']:>6.2f}{tr_tot:>+10.0f}")
    print(f"    {'TOTAL':<8}{'':>6}{'':>7}{'':>8}{'':>7}{'':>7}{'':>9}{'':>9}{'':>6}{tot:>+10.0f}")

    print("\n(f) INTRABAR AMBIGUITY (bars spanning BOTH stop and target -> unknowable path)")
    amb_all = np.concatenate([per_te[s]["ambiguous"] for s in per_te])
    print(f"    ambiguous exits: {amb_all.sum()} / {len(amb_all)} = {amb_all.mean()*100:.2f}%")
    print(f"    (all results above already use the PESSIMISTIC bound: ambiguity -> stop)")

    print("\n(g) LONG/SHORT BALANCE (TEST half) — is it just a directional bet?")
    for sym in sorted(per_te):
        dr = per_te[sym]["direction"]
        R = per_te[sym]["R_gross"] - E.cost_R(sym, per_te[sym]["stop_pips"])
        lo_m, hi_m = dr < 0, dr > 0
        print(f"    {sym:<8} long  n={hi_m.sum():>5} E_net={R[hi_m].mean() if hi_m.sum() else 0:+.4f}R"
              f"   short n={lo_m.sum():>5} E_net={R[lo_m].mean() if lo_m.sum() else 0:+.4f}R")

    print(f"\ntotal {time.time()-t0:.0f}s")
    CACHE.joinpath("chosen.json").write_text(json.dumps(dict(KEY=KEY, CH=CH)))


if __name__ == "__main__":
    main()
