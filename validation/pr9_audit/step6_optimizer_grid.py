"""Step 6: replay the merged aggressive_optimizer.py's full 24-config grid with
   the PR's own portfolio semantics and its own leaderboard filter."""
import sys
from pathlib import Path
from collections import defaultdict
sys.path.insert(0, str(Path(__file__).resolve().parent))
from m1_challenge_sim import build_candidates, load_m1_data, ACCOUNT, TARGET, FLOOR

DIR = Path("validation/HistoryData/m1-data")
PAIRS = ["eurusd","gbpusd","usdjpy","audusd","nzdusd","usdcad","usdchf","eurjpy","gbpjpy","eurgbp"]
BARS = {p: load_m1_data(list(DIR.glob(f"{p}-m1-*.csv"))[0]) for p in PAIRS}
print("bars loaded for", len(BARS), "pairs")

TARGET_R = [1.0, 1.2, 1.5]; STOP_ATR = [1.5, 2.0]; THRESH = [2.0, 2.5]; RISK = [0.002, 0.005]
DAILY_LOSS_LIMIT = 0.05

rows, admitted = [], []
for th in THRESH:
    for sa in STOP_ATR:
        for tr in TARGET_R:
            allc = [c for p in PAIRS for c in
                    build_candidates(BARS[p], th, sa, tr, 5, day_offset_hours=0)]
            for risk in RISK:
                rc = ACCOUNT * risk
                bal, peak, mdd, first, days = ACCOUNT, ACCOUNT, 0.0, None, -1
                day_pnl = defaultdict(float); worst_day = 0.0
                for xts, win in sorted((c.exit_ts, c.win) for c in allc):
                    bal += (tr if win else -1.0) * rc
                    peak = max(peak, bal); mdd = max(mdd, (peak - bal) / peak)
                    d = xts.date(); day_pnl[d] += (tr if win else -1.0) * rc
                    worst_day = min(worst_day, day_pnl[d])
                    if first is None: first = xts
                    if days == -1 and bal >= TARGET: days = (xts - first).days
                bust = mdd >= (ACCOUNT - FLOOR) / ACCOUNT
                ok = days != -1 and mdd <= 0.09          # the PR's own filter
                rows.append((tr, risk, sa, th, len(allc), mdd, days, worst_day, bust, ok))
                if ok: admitted.append(rows[-1])
                print(f"  T={tr} risk={risk*100:.1f}% SA={sa} TH={th}: trades={len(allc):>6} "
                      f"maxDD={mdd*100:>6.2f}% days={days:>4} worstDay={worst_day:>9.2f} "
                      f"floorBust={bust!s:<5} admitted={ok}")

print(f"\n{'='*92}")
print(f"configs in PR grid: {len(rows)}   admitted by the PR's own filter (dd<=9%): {len(admitted)}")
print(f"configs breaching the $2,250 firm termination floor: {sum(1 for r in rows if r[8])}")
print(f"configs whose worst single day exceeds the 5% daily-loss boundary "
      f"(${ACCOUNT*DAILY_LOSS_LIMIT:.2f}): {sum(1 for r in rows if r[7] < -ACCOUNT*DAILY_LOSS_LIMIT)}")
if admitted:
    print("admitted rows:", admitted)
else:
    print("-> `python tools/aggressive_optimizer.py` writes an EMPTY leaderboard:")
    print("   '| - | No viable combos met all criteria |'")
