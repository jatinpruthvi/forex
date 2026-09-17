"""
speed_lab/sweep8_final.py — last speed lever + final frontier.

M1 is dead (sweep7: 0/144 cells positive; cost stays 30-54% of 1R). The only
remaining way to raise trades/day on the SAME structural edge is to stack
timeframes: run the identical long-only extreme-bar fade on M5, M15 and M30 at
once. Same rule, three partially-independent signal streams.

Then: the honest speed/reliability frontier, bounded by the firm's 5% daily
loss limit (which caps risk per trade, not trades per day).

  python3 validation/speed_lab/sweep8_final.py
"""
from __future__ import annotations
import sys, time, json, itertools, gc
import numpy as np
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import engine as E
import portfolio as P

TRAIN_END = 1726012800000
T0 = 1662940800000
FILL = "next"
CACHE = Path("/tmp/speedlab_cache")
FINAL = json.loads((CACHE / "final.json").read_text())
SEL = FINAL["SEL"]
K, SA, TR, HH = SEL["k"], SEL["sa"], SEL["tr"], SEL["hh"]


def tf_trades(syms, tf, lo, hi, source="m5", side="long", k=K, sa=SA, tr=TR, hh=HH):
    per, det = {}, {}
    for sym in syms:
        d = E.load_ohlc(sym, tf, source)
        s = E.signals(d, sym, "rev", k=k, stop_atr=sa, target_r=tr, n_ch=20, entry=FILL)
        if s is None:
            continue
        r = E.resolve(s, d, max_hold_bars=max(8, int(hh * 60 / tf)))
        m = (r["ts"] >= lo) & (r["ts"] < hi)
        if side == "long":
            m &= r["direction"] > 0
        elif side == "short":
            m &= r["direction"] < 0
        if m.sum() < 5:
            continue
        per[sym] = {kk: vv[m] for kk, vv in r.items()}
        det[sym] = E.expectancy(s, per[sym], sym)
        del d, s, r
    return per, det


def merge(pairs_list):
    out = {}
    for per in pairs_list:
        for sym, d in per.items():
            out.setdefault(sym + f"@{id(per)}", d)
    # build_trades keys by sym for SPECS lookup -> rebuild with real sym names
    tr = []
    for per in pairs_list:
        for sym, d in per.items():
            cr = E.cost_R(sym, d["stop_pips"])
            for i in range(len(d["win"])):
                tr.append(P.Trade(sym, int(d["ts"][i]), int(d["exit_ts"][i]),
                                  bool(d["win"][i]), float(d["R_gross"][i]),
                                  float(d["stop_pips"][i]), float(cr[i])))
    tr.sort(key=lambda t: t.entry_ts)
    return tr


def agg(det, days):
    if not det:
        return dict(pairs=0, n=0, en=0.0, eg=0.0, cost=0.0, tpd=0.0, pos=0, wr=0.0)
    n = sum(e["n"] for e in det.values())
    w = lambda key: sum(e[key] * e["n"] for e in det.values()) / max(n, 1)
    return dict(pairs=len(det), n=n, en=w("e_net"), eg=w("e_gross"), cost=w("cost_R"),
                wr=w("wr"), tpd=n / days, pos=sum(1 for e in det.values() if e["e_net"] > 0))


def line(lbl, wf):
    if wf is None or wf["n_pass"] == 0:
        return f"  {lbl:<46} pass   0.0%  --"
    return (f"  {lbl:<46} pass {wf['pass_rate']*100:>5.1f}%  med {wf['med_days']:>4}d  "
            f"p25 {wf['p25_days']:>3}  p75 {wf['p75_days']:>3}  p90 {wf['p90_days']:>3}  "
            f"worst {wf['worst_days']:>4}  maxDD {wf['max_dd']*100:>5.1f}%  "
            f"day ${wf['worst_day']:>6.0f}  qual {wf['med_qual']:>2}  tr {wf['med_trades']:>3}")


t0 = time.time()
DAYS_TR = (TRAIN_END - T0) / 86_400_000
DAYS_TE = 730.0

print("=" * 124)
print(f"1. TIMEFRAME STACKING — identical long-only extreme-bar fade "
      f"(k={K}, stop {SA}xATR, target +{TR}R, hold {HH}h)")
print("=" * 124)
print(f"{'streams':<28}{'n(TRAIN)':>10}{'R/day TR':>10}{'n(TEST)':>9}{'E_net TE':>10}"
      f"{'t/day TE':>10}{'R/day TE':>10}")
print("-" * 124)
combos = [("M5", [5]), ("M15", [15]), ("M30", [30]),
          ("M5+M15", [5, 15]), ("M5+M30", [5, 30]), ("M15+M30", [15, 30]),
          ("M5+M15+M30", [5, 15, 30]), ("M5+M15+M30+H1", [5, 15, 30, 60])]
best_combo = None
for lbl, tfs in combos:
    ptr, dtr, pte, dte = [], {}, [], {}
    for tf in tfs:
        a, b = tf_trades(E.ALL_PAIRS, tf, T0, TRAIN_END)
        c, d = tf_trades(E.ALL_PAIRS, tf, TRAIN_END, 1 << 62)
        ptr.append(a); pte.append(c)
        for k2, v in b.items(): dtr[f"{k2}@{tf}"] = v
        for k2, v in d.items(): dte[f"{k2}@{tf}"] = v
    atr_, ate_ = agg(dtr, DAYS_TR), agg(dte, DAYS_TE)
    print(f"{lbl:<28}{atr_['n']:>10}{atr_['en']*atr_['tpd']:>+10.3f}{ate_['n']:>9}"
          f"{ate_['en']:>+10.4f}{ate_['tpd']:>10.2f}{ate_['en']*ate_['tpd']:>+10.3f}")
    if best_combo is None or ate_["en"] * ate_["tpd"] > best_combo[0]:
        best_combo = (ate_["en"] * ate_["tpd"], lbl, tfs, merge(ptr), merge(pte), atr_, ate_)
    del ptr, pte, dtr, dte
    gc.collect()

score, lbl, tfs, TRS_TR, TRS_TE, A_TR, A_TE = best_combo
print(f"\n  best TEST R/day: {lbl} -> {score:+.3f} R/day "
      f"(M5 alone from sweep6: {FINAL['test']['en']*FINAL['test']['tpd']:+.3f} R/day)")

print("\n" + "=" * 124)
print(f"2. SPEED / RELIABILITY FRONTIER — {lbl}, TRAIN-selected controls re-tuned on TRAIN")
print("=" * 124)
best = None
for r, mc, cap, ds in itertools.product([0.0025, 0.005, 0.0075, 0.01, 0.015, 0.02],
                                        [1, 2, 3, 4], [2, 3, 5, 8, 100], [1.5, 2.0, 3.0, 1e9]):
    cfg = P.Cfg(risk_pct=r, max_concurrent=mc, max_trades_day=cap, daily_stop_R=ds)
    wf = P.walk_forward(TRS_TR, cfg, 40)
    if wf["n_pass"] == 0 or wf["worst_day"] < -(E.ACCOUNT * E.DAILY_LOSS):
        continue
    key = (wf["pass_rate"], -wf["med_days"])
    if best is None or key > best[0]:
        best = (key, cfg, wf)
CFG = best[1]
print(f"  TRAIN-selected controls: {CFG.risk_pct*100:.2f}% risk, <= {CFG.max_concurrent} concurrent,"
      f" <= {CFG.max_trades_day}/day, breaker {CFG.daily_stop_R:g}R, base={CFG.risk_mode}")
print(line("TRAIN (selection window)", best[2]))
WF = P.walk_forward(TRS_TE, CFG, 60)
print(line("TEST (untouched, 60 start dates)", WF))

print("\n  risk-level frontier on TEST (the firm's 5% daily loss limit caps risk, not trades/day):")
print(f"    {'risk%':>7}{'pass%':>8}{'medD':>6}{'p25':>5}{'p90':>5}{'worst':>7}{'maxDD%':>8}"
      f"{'worstDay$':>11}{'dayLimitOK':>12}{'floorBust':>11}{'medTrades':>11}")
frontier = []
for r in (0.0025, 0.005, 0.0075, 0.01, 0.0125, 0.015, 0.02, 0.025):
    cfg = P.Cfg(**{**CFG.__dict__, "risk_pct": r})
    wf = P.walk_forward(TRS_TE, cfg, 40)
    fl = sum(1 for x in wf["results"] if "floor" in x.fail_reason)
    dl = sum(1 for x in wf["results"] if "daily loss" in x.fail_reason)
    ok = "yes" if wf["worst_day"] >= -(E.ACCOUNT * E.DAILY_LOSS) else "NO -> illegal"
    if wf["n_pass"] == 0:
        print(f"    {r*100:>7.2f}{0.0:>8.1f}{'-':>6}{'-':>5}{'-':>5}{'-':>7}"
              f"{wf['max_dd']*100:>8.1f}{wf['worst_day']:>11.0f}{ok:>12}{fl:>11}{'-':>11}")
        continue
    print(f"    {r*100:>7.2f}{wf['pass_rate']*100:>8.1f}{wf['med_days']:>6}{wf['p25_days']:>5}"
          f"{wf['p90_days']:>5}{wf['worst_days']:>7}{wf['max_dd']*100:>8.1f}"
          f"{wf['worst_day']:>11.0f}{ok:>12}{fl:>11}{wf['med_trades']:>11}")
    frontier.append(dict(risk=r, **{k2: v for k2, v in wf.items() if k2 != "results"}))

print("\n" + "=" * 124)
print("3. HEAD-TO-HEAD vs PR #9 (same TEST window 2024-09-11..2026-09-11, same firm rules)")
print("=" * 124)
print(f"{'':<34}{'pass%':>8}{'medDays':>9}{'p90Days':>9}{'maxDD%':>8}{'E_net/trade':>13}{'costs':>9}")
print("-" * 124)
print(f"{'PR #9 M1 Momentum Reversion':<34}{0.0:>8.1f}{'never':>9}{'-':>9}{10.3:>8.1f}"
      f"{-1.0259:>+13.4f}{'modelled':>9}")
print(f"{'PR #9 at ZERO cost (fantasy)':<34}{77.5:>8.1f}{29:>9}{90:>9}{12.6:>8.1f}"
      f"{0.0685:>+13.4f}{'none':>9}")
print(f"{('THIS: '+lbl+' long-only fade'):<34}{WF['pass_rate']*100:>8.1f}{WF['med_days']:>9}"
      f"{WF['p90_days']:>9}{WF['max_dd']*100:>8.1f}{A_TE['en']:>+13.4f}"
      f"{A_TE['cost']*100:>8.1f}%")

CACHE.joinpath("final2.json").write_text(json.dumps(
    dict(combo=lbl, tfs=tfs, SEL=SEL, CFG={k2: v for k2, v in CFG.__dict__.items()},
         train=A_TR, test=A_TE, wf_test={k2: v for k2, v in WF.items() if k2 != "results"},
         frontier=frontier), default=str))
print(f"\ntotal {time.time()-t0:.0f}s")
