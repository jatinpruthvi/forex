"""
speed_lab/sweep7_m1.py — can the SAME edge run faster on M1?

days_to_pass ~ (0.10 / risk) / (E_net x trades_per_day)

The M5 long-only fade delivers ~+0.84 R/day. The only remaining lever that can
multiply that is more trades per day on the SAME structural edge. The repo holds
2 years of M1 data for all 11 pairs covering exactly the TEST window, so this
transfers the TRAIN-selected M5 structure onto M1 unchanged (same k, same stop
multiple, same target multiple, honest next-open fill, long-only) and measures
what happens to E_net and trades/day.

  python3 validation/speed_lab/sweep7_m1.py
"""
from __future__ import annotations
import sys, time, json, itertools, gc
import numpy as np
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import engine as E
import portfolio as P

TRAIN_END = 1726012800000
FILL = "next"
CACHE = Path("/tmp/speedlab_cache")
FINAL = json.loads((CACHE / "final.json").read_text())
SEL = FINAL["SEL"]
print(f"M5 TRAIN-selected structure: k={SEL['k']} SA={SEL['sa']} TR={SEL['tr']} "
      f"hold={SEL['hh']}h side={SEL['side']}")


def m1_trades(syms, k, sa, tr, hh, side="long", tf=1):
    per, det = {}, {}
    for sym in syms:
        d = E.load_ohlc(sym, tf, "m1")
        hold = max(8, int(hh * 60 / tf))
        s = E.signals(d, sym, "rev", k=k, stop_atr=sa, target_r=tr, n_ch=20, entry=FILL)
        if s is None:
            continue
        r = E.resolve(s, d, max_hold_bars=hold)
        m = np.ones(len(r["win"]), bool)
        if side == "long":
            m &= r["direction"] > 0
        elif side == "short":
            m &= r["direction"] < 0
        if m.sum() < 5:
            continue
        per[sym] = {kk: vv[m] for kk, vv in r.items()}
        det[sym] = E.expectancy(s, per[sym], sym)
        del d, s, r
        gc.collect()
    return P.build_trades(per), per, det


def agg(det, days=730.0):
    if not det:
        return dict(pairs=0, n=0, en=0.0, eg=0.0, cost=0.0, tpd=0.0, pos=0, wr=0.0)
    n = sum(e["n"] for e in det.values())
    w = lambda key: sum(e[key] * e["n"] for e in det.values()) / max(n, 1)
    return dict(pairs=len(det), n=n, en=w("e_net"), eg=w("e_gross"), cost=w("cost_R"),
                wr=w("wr"), tpd=n / days, pos=sum(1 for e in det.values() if e["e_net"] > 0))


def line(lbl, wf):
    if wf is None or wf["n_pass"] == 0:
        return f"  {lbl:<50} pass   0.0%  --"
    return (f"  {lbl:<50} pass {wf['pass_rate']*100:>5.1f}%  med {wf['med_days']:>4}d  "
            f"p25 {wf['p25_days']:>3}  p90 {wf['p90_days']:>3}  worst {wf['worst_days']:>4}  "
            f"maxDD {wf['max_dd']*100:>5.1f}%  day ${wf['worst_day']:>6.0f}  "
            f"qual {wf['med_qual']:>2}  tr {wf['med_trades']:>3}")


t0 = time.time()
print("\n" + "=" * 128)
print("1. SAME STRUCTURE ON M1 (2024-09-11..2026-09-11) — does the edge survive the timeframe change?")
print("=" * 128)
print(f"{'k':>5}{'SA':>5}{'TR':>5}{'hold':>6}{'side':>7} | {'pairs':>6}{'n':>7}{'t/day':>8}"
      f"{'cost%':>7}{'WR%':>6}{'Egross':>9}{'Enet':>9}{'R/day':>8}{'+pr':>7}")
print("-" * 128)
m1best = []
for k, sa, tr, hh, side in itertools.product([3.0, 4.0, 5.0], [2.0, 3.0, 4.0, 6.0],
                                             [4.0, 6.0, 10.0], [24, 96], ["long", "both"]):
    trs, per, det = m1_trades(E.ALL_PAIRS, k, sa, tr, hh, side)
    a = agg(det)
    if a["n"] < 100:
        continue
    m1best.append(dict(k=k, sa=sa, tr=tr, hh=hh, side=side, trs=len(trs), **a))
    print(f"{k:>5.1f}{sa:>5.1f}{tr:>5.1f}{hh:>6}{side:>7} | {a['pairs']:>6}{a['n']:>7}"
          f"{a['tpd']:>8.2f}{a['cost']*100:>7.1f}{a['wr']*100:>6.1f}{a['eg']:>+9.4f}"
          f"{a['en']:>+9.4f}{a['en']*a['tpd']:>+8.3f}{a['pos']:>5}/{a['pairs']:<2}")
    del per, det, trs
    gc.collect()
CACHE.joinpath("m1_cells.json").write_text(json.dumps(m1best))
pos = [c for c in m1best if c["en"] > 0]
pos.sort(key=lambda c: -c["en"] * c["tpd"])
print(f"\n  M1 cells with positive E_net: {len(pos)} / {len(m1best)}")
if pos:
    print("  top 6 by R/day:")
    for c in pos[:6]:
        print(f"    k={c['k']:<4} SA={c['sa']:<4} TR={c['tr']:<4} hold={c['hh']:<3} {c['side']:<5}"
              f" E_net {c['en']:+.4f}R x {c['tpd']:.2f}/d = {c['en']*c['tpd']:+.3f} R/d  "
              f"({c['pos']}/{c['pairs']} pairs +, n={c['n']})")
print(f"\n  M5 reference (TRAIN-selected, same window): E_net {FINAL['test']['en']:+.4f}R x "
      f"{FINAL['test']['tpd']:.2f}/d = {FINAL['test']['en']*FINAL['test']['tpd']:+.3f} R/d")
print(f"\n[{time.time()-t0:.0f}s]")
