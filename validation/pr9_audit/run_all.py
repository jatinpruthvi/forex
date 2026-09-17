#!/usr/bin/env python3
"""Reproduce every number in findings_pr9_m1_review.md.

    python3 validation/pr9_audit/run_all.py            # full audit (~3 min)
    python3 validation/pr9_audit/run_all.py --quick    # skip the 10-pair grid (~30 s)

m1_challenge_sim.py is an exactly-equivalent reimplementation of
tools/m1_holy_grail.py's engine (verified in step2 section A: identical trade
count, win rate, max drawdown and days-to-target for all three published
configs), so the cost/rule findings below are not artefacts of a different
simulator.
"""
import subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
STEPS = ["step1_signal_stats.py", "step2_verify_and_cost.py",
         "step3_rules_and_walkforward.py", "step4_sizing_and_scale.py",
         "step5_portfolio_risk.py", "step7_gate12.py", "step8_breakeven.py",
         "step9_fills.py"]
if "--quick" not in sys.argv:
    STEPS.insert(5, "step6_optimizer_grid.py")

t0 = time.time()
for s in STEPS:
    print("\n" + "#" * 100)
    print(f"# {s}")
    print("#" * 100, flush=True)
    r = subprocess.run([sys.executable, str(HERE / s)], cwd=HERE.parents[1])
    if r.returncode != 0:
        print(f"!! {s} exited {r.returncode}")
print(f"\n{'='*100}\naudit complete in {time.time()-t0:.0f}s")
