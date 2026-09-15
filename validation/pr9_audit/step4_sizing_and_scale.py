"""Step 4: lot/margin feasibility of the PR's 0.5%-risk M1 stops, and the
   cost of the merged aggressive_optimizer.py rewrite."""
import sys, time, statistics
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from m1_challenge_sim import build_candidates, load_m1_data, size_lots, DATA, PV, COMM_RT

bars = load_m1_data(DATA)
cands = build_candidates(bars, threshold=2.5, stop_atr=1.5, target_r=1.5,
                         max_trades_per_day=5, day_offset_hours=0)
RISK = 12.50
lots = [size_lots(c.stop_pips, RISK) for c in cands]
lots = [l for l in lots if l > 0]
lots.sort()
n = len(lots)
print("=" * 92)
print("G. LOT SIZE REQUIRED TO RISK $12.50 WITH THE PR'S STOPS (EURUSD, 1.00 lot = 100k notional)")
print("=" * 92)
print(f"  trades sized: {n}")
print(f"  lots  min {lots[0]:.2f}  p25 {lots[int(.25*(n-1))]:.2f}  median "
      f"{lots[int(.5*(n-1))]:.2f}  p75 {lots[int(.75*(n-1))]:.2f}  p95 {lots[int(.95*(n-1))]:.2f}  max {lots[-1]:.2f}")
for cap, lev in ((0.75, "1:30"), (2.50, "1:10"), (25.0, "1:100")):
    over = sum(1 for l in lots if l > cap)
    print(f"  trades needing > {cap:>5.2f} lots (${cap*100000:>9,.0f} notional, "
          f"max at leverage {lev} on $2,500): {over:>5} = {over/n*100:>5.1f}%")
print(f"  -> at 1:30 leverage ($2,500 x 30 = $75,000 max notional = 0.75 lots) "
      f"{sum(1 for l in lots if l > 0.75)/n*100:.1f}% of signals cannot be sized as specified")

print()
print("=" * 92)
print("H. COST OF THE PR's aggressive_optimizer.py REWRITE (10 pairs x 24 configs)")
print("=" * 92)
t0 = time.time()
one = build_candidates(bars, 2.5, 1.5, 1.5, 5, 0)
print(f"  single-pair candidate build: {time.time()-t0:.1f}s")
print("  PR main() re-parses ALL 10 CSVs from disk inside every one of the 24 grid")
print("  configs (test_config calls load_m1_data each time): 24 x ~7.4M rows parsed,")
print("  plus a full 7.4M-element list sort per config.")
t0 = time.time()
from tools.m1_holy_grail import load_m1_data as lmd
files = sorted(Path("validation/HistoryData/m1-data").glob("*.csv"))[:1]
_ = lmd(files[0])
per = time.time() - t0
print(f"  measured: parsing ONE M1 csv = {per:.1f}s  ->  10 pairs = {per*10:.0f}s  "
      f"->  x24 configs = {per*240/60:.0f} min of pure CSV re-parsing")
