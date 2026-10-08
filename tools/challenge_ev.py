#!/usr/bin/env python3
"""Expected value of buying prop-firm challenges with a ZERO-EDGE bracket strategy (fair random walk, cost drag only), one trade/day, no time limit.
Rule sets are from public pages read 2026-09 (fees/rules change; verify). Research only, not advice.  python tools/challenge_ev.py"""
import numpy as np
rng = np.random.default_rng(11)

def phase(target, floor, risk, R, c, n=40000, maxsteps=6000):
    """fair bracket trade, 1 per day: win prob so expectancy = -c R. returns P(hit target before -floor)."""
    p = (1 - c) / (R + 1)
    eq = np.zeros(n); alive = np.ones(n, bool); hit = np.zeros(n, bool)
    for _ in range(maxsteps):
        if not alive.any(): break
        step = np.where(rng.random(n) < p, risk * R, -risk)
        eq = np.where(alive, eq + step, eq)
        h = alive & (eq >= target - 1e-12); l = alive & (eq <= -floor + 1e-12)
        hit |= h; alive &= ~(h | l)
    return hit.mean()

FIRMS = {  # target steps, floor per step, split, fee as fraction of account, fee refunded at first payout, max risk per trade allowed by daily rule
    "5ers HighStakes 10/5":   dict(steps=[(.10,.10),(.05,.10)], split=.80, fee=.0060, refund=0, maxr=.045, fw=.05, ff=.10),
    "5ers HighStakes 8/5":    dict(steps=[(.08,.10),(.05,.10)], split=.80, fee=.0065, refund=0, maxr=.045, fw=.05, ff=.10),
    "FTMO 10/5 (fee refund)": dict(steps=[(.10,.10),(.05,.10)], split=.80, fee=.0090, refund=1, maxr=.045, fw=.05, ff=.10),
    "90%-split 2-step 8/5":   dict(steps=[(.08,.10),(.05,.10)], split=.90, fee=.0070, refund=1, maxr=.045, fw=.05, ff=.10),
    "5ers Bootcamp 6/6/6":    dict(steps=[(.06,.05)]*3,        split=.50, fee=.0060, refund=0, maxr=.025, fw=.05, ff=.04),
    "5ers HyperGrowth 10 (1-step)": dict(steps=[(.10,.06)], split=.50, fee=.0100, refund=0, maxr=.025, fw=.10, ff=.06),
}
def ev(f, risk, R, c, cap=5):
    risk = min(risk, f["maxr"])
    P = 1.0
    for t, fl in f["steps"]:
        P *= phase(t, fl, risk, R, c, n=15000)
    q = phase(f["fw"], f["ff"], risk, R, c, n=15000)
    pay = sum(q ** k for k in range(1, cap + 1)) * f["split"] * f["fw"]
    return P, q, P * pay + f["refund"] * f["fee"] * P * q - f["fee"]

for c in (0.05, 0.10):
    print(f"\n=== cost drag {c:.2f}R per trade (zero edge) ; EV per attempt as % of account size (fee shown as %) ===")
    for name, f in FIRMS.items():
        best = None
        for risk, R in [(.01,1),(.02,2),(.025,1),(.025,2),(.04,1),(.04,2),(.045,2)]:
            P, q, e = ev(f, risk, R, c)
            if best is None or e > best[0]: best = (e, risk, R, P, q)
        e, risk, R, P, q = best
        print(f"{name:30s} fee {f['fee']*100:4.2f}% | best: risk {min(risk,f['maxr'])*100:.1f}% payoff {R}:1 | P(pass all steps) {P:.2f} | P(funded round) {q:.2f} | EV {e*100:+.2f}% of acct = {e/f['fee']:+.1f}x fee")
