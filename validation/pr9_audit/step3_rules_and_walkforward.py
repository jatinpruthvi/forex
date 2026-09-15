"""Step 3: challenge-rule gates, cost break-even, and walk-forward robustness."""
import sys, statistics
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from m1_challenge_sim import (DATA, build_candidates, simulate, load_m1_data,
                              ACCOUNT, TARGET, FLOOR, SPREAD_RT, COMM_RT, PIP, PV)
import m1_challenge_sim as S

bars = load_m1_data(DATA)
cands = build_candidates(bars, threshold=2.5, stop_atr=1.5, target_r=1.5,
                         max_trades_per_day=5, day_offset_hours=0)

print("=" * 100)
print("C. IS THE 12.62% DRAWDOWN REALLY 'POST-PHASE-1'?  (zero-cost, PR semantics)")
print("=" * 100)
bal, peak, mdd, mdd_ts, first_cross, crossed = ACCOUNT, ACCOUNT, 0.0, None, None, False
risk = 0.005 * ACCOUNT
for c in cands:
    bal += (1.5 if c.win else -1.0) * risk
    peak = max(peak, bal)
    dd = (peak - bal) / peak
    if dd > mdd:
        mdd, mdd_ts = dd, c.exit_ts
    if not crossed and bal >= TARGET:
        first_cross, crossed = c.exit_ts, True
print(f"  +10% target ($2,750) first reached : {first_cross}")
print(f"  max drawdown {mdd*100:.2f}% reached     : {mdd_ts}")
print(f"  -> max DD occurs {'AFTER' if mdd_ts > first_cross else 'BEFORE'} the target is hit"
      f"   (findings_m1_discovery.md claims 'post-Phase 1')")
print(f"  firm overall-loss floor is $2,250 = -10%.  max DD {mdd*100:.2f}% "
      f"{'BREACHES' if mdd > 0.10 else 'within'} the firm limit.")
# first time equity goes below the floor
bal2 = ACCOUNT
for c in cands:
    bal2 += (1.5 if c.win else -1.0) * risk
    if bal2 <= FLOOR:
        print(f"  balance first <= $2,250 (firm TERMINATION) : {c.exit_ts}  "
              f"(${bal2:.2f})  -> {'BEFORE' if c.exit_ts < first_cross else 'AFTER'} passing Phase 1")
        break
else:
    print("  balance never breaches $2,250 in the zero-cost run")

print()
print("=" * 100)
print("D. QUALIFYING-DAY REQUIREMENT (The5ers needs >=3 days with net >= $12.50 at midnight)")
print("=" * 100)
for off, label in ((0, "UTC (what the PR uses)"), (3, "UTC+3 (Eightcap/The5ers server)")):
    r = simulate(cands, bars, risk_pct=0.005, costs=False, enforce_floor=False,
                 enforce_daily=False, enforce_personal_dd=False,
                 day_offset_hours=off, stop_on_pass=True)
    print(f"  {label:<38} zero-cost: passed={r.passed}  qualifying days={r.qual_days}  "
          f"trades={r.trades}  days={r.days_to_pass}")

print()
print("=" * 100)
print(f"E. COST BREAK-EVEN  (repo canonical = {SPREAD_RT:.2f} pip RT spread + ${COMM_RT:.0f}/lot)")
print("=" * 100)
print(f"{'spread(pip RT)':>15}{'comm $/lot':>12}{'trades':>8}{'net P&L':>12}"
      f"{'maxDD%':>9}{'floor bust':>12}{'P1 pass':>9}")
for sp, cm in [(0.0, 0.0), (0.1, 0.0), (0.2, 3.5), (0.3, 3.5), (0.55, 7.0), (1.0, 7.0)]:
    S.SPREAD_RT, S.COMM_RT = sp, cm
    r = simulate(cands, bars, risk_pct=0.005, costs=(sp or cm) != 0,
                 enforce_floor=True, enforce_daily=True, enforce_personal_dd=False,
                 day_offset_hours=3, stop_on_pass=True)
    print(f"{sp:>15.2f}{cm:>12.1f}{r.trades:>8}{r.pnl:>12.2f}{r.max_dd*100:>9.2f}"
          f"{'YES '+str(r.bust_ts)[:10] if r.bust_floor else 'no':>12}"
          f"{'YES' if r.passed else 'NO':>9}")
S.SPREAD_RT, S.COMM_RT = SPREAD_RT, COMM_RT

print()
print("=" * 100)
print("F. WALK-FORWARD: is '20 days' representative, or the luckiest window in 2 years?")
print("=" * 100)
starts = [bars[i].ts for i in range(0, len(bars), 4000)][:120]
for costs, label in ((False, "ZERO-COST (PR's assumption)"), (True, "WITH REAL COSTS")):
    d2p, passed, busted, qd = [], 0, 0, []
    for st in starts:
        r = simulate(cands, bars, risk_pct=0.005, costs=costs, enforce_floor=True,
                     enforce_daily=True, enforce_personal_dd=False,
                     day_offset_hours=3, start_ts=st, stop_on_pass=True)
        if r.passed:
            passed += 1; d2p.append(r.days_to_pass); qd.append(r.qual_days)
        if r.bust_floor:
            busted += 1
    n = len(starts)
    print(f"\n  {label}: {n} rolling start dates")
    print(f"    Phase 1 passed      : {passed}/{n} = {passed/n*100:.1f}%")
    print(f"    busted $2,250 floor : {busted}/{n} = {busted/n*100:.1f}%")
    if d2p:
        d2p.sort()
        print(f"    days-to-pass (of those that passed): median {statistics.median(d2p):.0f}  "
              f"p90 {d2p[int(.9*(len(d2p)-1))]:.0f}  max {max(d2p)}")
        print(f"    qualifying days at pass: median {statistics.median(qd):.0f}  "
              f"min {min(qd)}")
