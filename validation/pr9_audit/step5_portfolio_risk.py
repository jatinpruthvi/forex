"""Step 5: the merged aggressive_optimizer.py runs 10 pairs through ONE shared
   pnl pool. Measure the aggregate risk that actually results."""
import sys, statistics
from pathlib import Path
from collections import defaultdict
sys.path.insert(0, str(Path(__file__).resolve().parent))
from m1_challenge_sim import build_candidates, load_m1_data, FLOOR, ACCOUNT

DIR = Path("validation/HistoryData/m1-data")
PAIRS = ["eurusd","gbpusd","usdjpy","audusd","nzdusd","usdcad","usdchf","eurjpy","gbpjpy","eurgbp"]

intervals = []          # (open_ts, close_ts, pair)
per_pair = {}
for p in PAIRS:
    f = list(DIR.glob(f"{p}-m1-*.csv"))
    if not f: continue
    bars = load_m1_data(f[0])
    c = build_candidates(bars, 2.5, 1.5, 1.5, 5, day_offset_hours=0)
    per_pair[p] = (len(bars), c)
    for cand in c:
        intervals.append((cand.ts, cand.exit_ts, p))
print("loaded pairs:", {k: (v[0], len(v[1])) for k, v in per_pair.items()})
tot = sum(len(v[1]) for v in per_pair.values())
print(f"\ntotal trades over 2 years across 10 pairs: {tot}")

# concurrency sweep
ev = []
for o, c, p in intervals:
    ev.append((o, 1)); ev.append((c, -1))
ev.sort()
cur = mx = 0
for _, d in ev:
    cur += d
    mx = max(mx, cur)
print(f"max SIMULTANEOUS open positions            : {mx}")
print(f"  -> PR risk_pct is applied per pair, so peak aggregate risk = {mx} x 0.5% = {mx*0.5:.1f}% of balance")
print(f"  -> THE5ERS-2.5K-CHALLENGE-PLAN.md s.2 forbids this: 'Maximum one working pending")
print(f"     entry or one open position account-wide - never simultaneous positions'")

# trades per calendar day
by_day = defaultdict(int)
for o, c, p in intervals:
    by_day[o.date()] += 1
vals = sorted(by_day.values())
print(f"\ntrades per calendar day (account-wide): median {statistics.median(vals):.0f}  "
      f"p95 {vals[int(.95*(len(vals)-1))]}  max {vals[-1]}")
print(f"  -> plan s.2 allows 'Maximum two completed sequential trades per day'")

# zero-cost portfolio equity, PR semantics, with the firm floor
bal, peak, mdd, bust = ACCOUNT, ACCOUNT, 0.0, None
merged = sorted(((c.ts, c.exit_ts, c.win)
                 for _, cs in per_pair.values() for c in cs),
                key=lambda x: x[1])
for _, xts, win in merged:
    bal += (1.5 if win else -1.0) * 12.50
    peak = max(peak, bal)
    mdd = max(mdd, (peak - bal) / peak)
    if bust is None and bal <= FLOOR:
        bust = xts
print(f"\nzero-cost 10-pair portfolio: final ${bal:.2f}  maxDD {mdd*100:.2f}%  "
      f"floor breach: {bust or 'none'}")
