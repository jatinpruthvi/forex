"""Step 8: find the exact transaction-cost level at which the PR's champion dies."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import m1_challenge_sim as S
from m1_challenge_sim import build_candidates, load_m1_data, simulate, DATA, SPREAD_RT, COMM_RT

bars = load_m1_data(DATA)
cands = build_candidates(bars, 2.5, 1.5, 1.5, 5, day_offset_hours=0)

print("=" * 96)
print("J. FINE COST SWEEP — spread only (commission $0), single pair EURUSD, T=1.5R SA=1.5 risk 0.5%")
print("=" * 96)
print(f"{'RT spread (pips)':>18}{'net P&L':>12}{'floor bust':>26}{'P1 pass':>9}")
S.COMM_RT = 0.0
be = None
for sp in [0.0, 0.01, 0.02, 0.03, 0.05, 0.08, 0.10, 0.20, 0.55]:
    S.SPREAD_RT = sp
    r = simulate(cands, bars, risk_pct=0.005, costs=sp > 0, enforce_floor=True,
                 enforce_daily=True, enforce_personal_dd=False,
                 day_offset_hours=3, stop_on_pass=True)
    print(f"{sp:>18.2f}{r.pnl:>12.2f}"
          f"{('YES @ '+str(r.bust_ts)[:10]) if r.bust_floor else 'no':>26}"
          f"{'YES' if r.passed else 'NO':>9}")
    if be is None and not r.passed:
        be = sp
print(f"\n  break-even: the account survives Phase 1 only at a round-trip spread below "
      f"~{be:.2f} pips with ZERO commission.")
print(f"  EURUSD realistic round-trip spread: 0.55 pips on a raw account, ~1.0 pip standard")
print(f"  (repo constants: tools/optimizer_v2.py SPREAD_STD['EURUSD']=0.00010, RAW_SCALE=0.55)")

S.SPREAD_RT, S.COMM_RT = SPREAD_RT, COMM_RT
print()
print("=" * 96)
print("K. SAME SWEEP WITH COMMISSION, AND THE PERSONAL -5% DD STOP FROM PLAN s.8")
print("=" * 96)
print(f"{'RT spread':>10}{'comm':>7}{'net P&L':>12}{'maxDD%':>9}{'outcome':>34}")
for sp, cm in [(0.0, 0.0), (0.0, 2.0), (0.2, 3.5), (0.55, 7.0)]:
    S.SPREAD_RT, S.COMM_RT = sp, cm
    r = simulate(cands, bars, risk_pct=0.005, costs=(sp or cm) > 0, enforce_floor=True,
                 enforce_daily=True, enforce_personal_dd=True,
                 day_offset_hours=3, stop_on_pass=True)
    out = ("PASS Phase 1" if r.passed else
           f"BUST floor {str(r.bust_ts)[:10]}" if r.bust_floor else
           f"BUST daily {str(r.bust_ts)[:10]}" if r.bust_daily else
           f"HALT personal -5% DD {str(r.bust_ts)[:10]}")
    print(f"{sp:>10.2f}{cm:>7.1f}{r.pnl:>12.2f}{r.max_dd*100:>9.2f}{out:>34}")
S.SPREAD_RT, S.COMM_RT = SPREAD_RT, COMM_RT
