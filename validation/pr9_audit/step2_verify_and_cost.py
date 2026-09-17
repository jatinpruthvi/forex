"""Step 2: (a) prove the fast engine reproduces the PR's published numbers,
         (b) re-run it with the repo's own canonical transaction-cost model."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from m1_challenge_sim import (DATA, build_candidates, simulate, load_m1_data,
                              ACCOUNT, TARGET, FLOOR, SPREAD_RT, COMM_RT)

bars = load_m1_data(DATA)
print(f"loaded {len(bars)} EURUSD M1 bars\n")

CONFIGS = [(1.0, 1.5), (1.5, 1.5), (1.0, 2.0)]   # (target_r, stop_atr)
PUBLISHED = {(1.0, 1.5): (2976, 51.7, 15.29, 19),
             (1.5, 1.5): (2962, 42.7, 12.62, 20),
             (1.0, 2.0): (2963, 52.1, 12.11, 27)}

print("=" * 96)
print("A. REPLICATION CHECK — PR engine semantics (UTC days, no costs, no rule gates)")
print("=" * 96)
print(f"{'cfg':<14}{'trades':>8}{'WR%':>8}{'maxDD%':>9}{'days':>7}   "
      f"{'published (tools/findings_m1_discovery.md)':<40}{'match':>7}")
cache = {}
for tr, sa in CONFIGS:
    cands = build_candidates(bars, threshold=2.5, stop_atr=sa, target_r=tr,
                             max_trades_per_day=5, day_offset_hours=0)
    cache[(tr, sa)] = cands
    r = simulate(cands, bars, risk_pct=0.005, costs=False,
                 enforce_floor=False, enforce_daily=False, enforce_personal_dd=False,
                 day_offset_hours=0, stop_on_pass=False)
    pt, pw, pd, pdd = PUBLISHED[(tr, sa)]
    ok = (r.trades == pt and abs(r.wr*100-pw) < 0.06 and abs(r.max_dd*100-pd) < 0.02
          and r.days_to_target == pdd)
    print(f"T={tr} SA={sa:<9}{r.trades:>8}{r.wr*100:>8.1f}{r.max_dd*100:>9.2f}"
          f"{r.days_to_target:>7}   {pt} / {pw}% / {pd}% / {pdd}d{'':<12}"
          f"{'YES' if ok else 'NO':>7}")

print("\n" + "=" * 96)
print(f"B. SAME TRADES + REAL COSTS  (EURUSD raw acct: {SPREAD_RT:.2f} pip RT spread "
      f"+ ${COMM_RT:.0f}/lot, 0.01 lot step)")
print("=" * 96)
print(f"{'cfg':<14}{'trades':>8}{'WR%':>8}{'net P&L':>12}{'costs paid':>12}"
      f"{'maxDD%':>9}{'floor bust':>12}{'day':>6}")
for tr, sa in CONFIGS:
    cands = cache[(tr, sa)]
    r = simulate(cands, bars, risk_pct=0.005, costs=True,
                 enforce_floor=True, enforce_daily=True, enforce_personal_dd=False,
                 day_offset_hours=3, stop_on_pass=True)
    print(f"T={tr} SA={sa:<9}{r.trades:>8}{r.wr*100:>8.1f}{r.pnl:>12.2f}"
          f"{r.cost_drag:>12.2f}{r.max_dd*100:>9.2f}"
          f"{'YES @'+str(r.bust_ts)[:10] if r.bust_floor else 'no':>12}"
          f"{'YES' if r.bust_daily else 'no':>6}")
    print(f"{'':14}passed Phase 1: {r.passed}   qualifying days: {r.qual_days}"
          f"   days-to-pass: {r.days_to_pass}   end balance: ${r.end_balance:.2f}")
