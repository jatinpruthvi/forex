"""Step 1: characterise the PR#9 M1 signal set (stop distances, trade counts)."""
import sys, statistics
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.m1_holy_grail import load_m1_data, atr

PIP = 0.0001
bars = load_m1_data(Path("validation/HistoryData/m1-data/eurusd-m1-2024-09-11_2026-09-11.csv"))
print(f"EURUSD M1 bars: {len(bars)}  {bars[0].ts} -> {bars[-1].ts}")

THRESH, STOP_ATR = 2.5, 1.5
stops_pips, atrs_pips, bodies_pips = [], [], []
sigs = []
for i in range(15, len(bars)):
    b = bars[i]
    a = atr(bars[i-15:i-1], 14)
    if a == 0: continue
    body = abs(b.open - b.close)
    if body > THRESH * a:
        sd = STOP_ATR * a                      # stop distance from entry(=close)
        stops_pips.append(sd / PIP)
        atrs_pips.append(a / PIP)
        bodies_pips.append(body / PIP)
        sigs.append((b.ts, sd / PIP))

n = len(stops_pips)
stops_pips.sort()
def q(p): return stops_pips[int(p*(n-1))]
print(f"\nRaw trigger signals (before 5/day cap): {n}")
print(f"ATR(M1,14) pips  : median {statistics.median(atrs_pips):.2f}  mean {statistics.mean(atrs_pips):.2f}")
print(f"Body pips        : median {statistics.median(bodies_pips):.2f}")
print(f"Stop distance pips: min {q(0):.2f}  p5 {q(.05):.2f}  p25 {q(.25):.2f}  "
      f"median {q(.50):.2f}  p75 {q(.75):.2f}  p95 {q(.95):.2f}  max {q(1.0):.2f}")
print(f"  stops < 1.0 pip : {sum(1 for s in stops_pips if s < 1.0)/n*100:.1f}%")
print(f"  stops < 2.0 pips: {sum(1 for s in stops_pips if s < 2.0)/n*100:.1f}%")
print(f"  stops < 3.0 pips: {sum(1 for s in stops_pips if s < 3.0)/n*100:.1f}%")

# cost as a fraction of 1R, using the repo's canonical cost model
SPREAD_RT_PIPS = 0.00010 / PIP * 0.55   # optimizer_v2: SPREAD_STD * RAW_SCALE
COMM_RT = 7.0                            # $/lot round turn
RISK = 12.50
PV = 10.0                                # $/pip/lot EURUSD
costR = []
for s in stops_pips:
    loss_per_lot = s * PV + COMM_RT
    lots = int((RISK / loss_per_lot) / 0.01) * 0.01
    if lots < 0.01: lots = 0.0
    spread_cash = lots * SPREAD_RT_PIPS * PV
    costR.append((spread_cash + COMM_RT * lots) / RISK if RISK else 0)
costR.sort()
print(f"\nRound-trip cost as %% of 1R (repo model: {SPREAD_RT_PIPS:.2f}pip spread + ${COMM_RT}/lot):")
print(f"  median {statistics.median(costR)*100:.1f}%   mean {statistics.mean(costR)*100:.1f}%   "
      f"p90 {costR[int(.9*(len(costR)-1))]*100:.1f}%")
print(f"  share of trades where cost >= 50% of 1R : {sum(1 for c in costR if c>=0.5)/len(costR)*100:.1f}%")
print(f"  share of trades where cost >= 100% of 1R: {sum(1 for c in costR if c>=1.0)/len(costR)*100:.1f}%")
