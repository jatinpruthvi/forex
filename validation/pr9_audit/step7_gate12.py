"""Step 7: score the PR's champion against the repo's own Section-12 go/no-go gate."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import m1_challenge_sim as S
from m1_challenge_sim import build_candidates, load_m1_data, simulate, size_lots, DATA

bars = load_m1_data(DATA)
cands = build_candidates(bars, 2.5, 1.5, 1.5, 5, day_offset_hours=0)

def expectancy_and_pf(costs):
    exp = gp = gl = 0.0; n = 0
    for c in cands:
        if costs:
            lots = size_lots(c.stop_pips, 12.50)
            if lots < 0.01: continue
            cost = lots * S.SPREAD_RT * S.PV + S.COMM_RT * lots
        else:
            lots = 12.50 / (c.stop_pips * S.PV); cost = 0.0
        r = c.stop_pips * S.PV * lots
        if c.timed_out:
            continue
        net = (lots * abs(c.target - c.entry) / S.PIP * S.PV - cost) if c.win else (-r - cost)
        exp += net / r if r else 0.0
        if net > 0: gp += net
        else: gl += -net
        n += 1
    return exp / n if n else 0.0, (gp / gl if gl else 0.0), n

print("=" * 100)
print("I. THE5ERS-2.5K-CHALLENGE-PLAN.md SECTION 12 GO/NO-GO GATE vs PR #9's champion")
print("   (champion = M1 Momentum Reversion, EURUSD, thresh 2.5xATR, stop 1.5xATR, T=1.5R, risk 0.5%)")
print("=" * 100)
e0, pf0, n0 = expectancy_and_pf(False)
e1, pf1, n1 = expectancy_and_pf(True)
rows = [
 ("1", "≥300 OUT-OF-SAMPLE trades", "0 out-of-sample — config picked by sweeping the whole 2y set", "FAIL"),
 ("2", "Net expectancy ≥ 0.20R after The5ers-like spread + $4/lot commission",
       f"zero-cost {e0:+.4f}R | with repo costs {e1:+.4f}R", "FAIL" if e1 < 0.20 else "pass"),
 ("3", "Net profit factor ≥ 1.30", f"zero-cost PF {pf0:.2f} | with costs PF {pf1:.2f}", "FAIL" if pf1 < 1.30 else "pass"),
 ("4", "Profitable at spread x1.5 and slippage x2", "not tested by the PR; busts at >=0.05 pip RT spread even with $0 commission", "FAIL"),
 ("5", "Exact 0.01-lot rounding, MT5 cash P&L, server-day grouping, published profitable-day formula",
       "none implemented — P&L is a hard-coded +/- risk_pct, days are UTC calendar dates", "FAIL"),
 ("6", "Historical news blackout + server-time/DST handling", "none implemented", "FAIL"),
 ("7", "≥10,000 day/week block-bootstrap simulations preserving losing clusters", "none run", "FAIL"),
 ("8", "Phase 1 then fresh Phase 2, ranked by joint two-phase pass probability", "Phase 2 never simulated", "FAIL"),
 ("9", "≥70% Phase 1 pass probability before the personal -5% stop",
       "walk-forward: 0% with costs; 77.5% zero-cost but 22.5% bust the floor", "FAIL"),
 ("10","95th-percentile max drawdown < 5%",
       "single-pair zero-cost maxDD 12.62%; 10-pair portfolio 39.07%", "FAIL"),
 ("11","Compare 0.50%/+1.0R vs 0.25% risk + 1.5R using actual lot rounding", "no lot rounding anywhere", "FAIL"),
 ("12","30-50 forward-demo trades with zero implementation errors", "none recorded", "FAIL"),
]
for num, req, actual, verdict in rows:
    print(f"  [{verdict.upper():>4}] #{num:<3}{req}\n{'':>11}actual: {actual}")
print(f"\n  gates passed: {sum(1 for r in rows if r[3]=='pass')}/12")
