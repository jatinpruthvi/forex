"""Research-only smart Fibonacci sizing experiment.

This lab tests loss-streak sizing schedules on the current four-year P0
TRIAD-plus-Gold outcome sequence.  It is deliberately not an EA change and
must not be used to conceal a sizing rule from a broker or account provider.

A Fibonacci progression is still a martingale family.  "Smart" here means
pre-declared limits and safety rules, not hindsight selection:

* the progression may be account-wide, per instrument, or per leg;
* every schedule is capped;
* a 4% internal daily loss stop blocks the rest of that day;
* a drawdown guard can halve risk once the account is 5% below its high water;
* the 15% user ceiling is a halt, never a target; and
* the two-year run selects the configuration before the unchanged four-year
  confirmation is shown.

The sizing calculation uses normalized net-R outcomes from the existing honest
research run.  It therefore tests the risk policy and path dependence, but it
does not claim to reproduce broker lot rounding at every new risk fraction.
The final decision still requires tick-level/forward validation.

Usage:
    python tools/smart_fibonacci_lab.py --confirm
"""
from __future__ import annotations

import argparse
import hashlib
import math
import os
import random
import sys
from dataclasses import dataclass
from datetime import date
from pathlib import Path

sys.path.insert(0, os.path.abspath("."))
import tools.order_selector as selector  # noqa: E402
import tools.optimizer_v2 as optimizer  # noqa: E402

START_BALANCE = 2500.0
DD_LIMIT_PERCENT = 15.0
DAILY_STOP_PERCENT = 4.0
DD_GUARD_PERCENT = 5.0

# Every tuple is a capped multiplier schedule.  The final value is repeated
# after the schedule is exhausted; no schedule is unbounded.
SCHEDULES = {
    "fixed": (1,),
    "fib_cap2": (1, 1, 2),
    "fib_cap3": (1, 1, 2, 3),
    "fib_cap5": (1, 1, 2, 3, 5),
    "fib_cap8": (1, 1, 2, 3, 5, 8),
    "soft_fib3": (1, 1, 1, 2, 3),
    "soft_fib5": (1, 1, 1, 2, 3, 5),
    "linear_cap3": (1, 1, 2, 2, 3),
}
SCOPES = ("account", "instrument", "leg")
BASE_RISKS = (0.0025, 0.005, 0.01, 0.015)


@dataclass(frozen=True)
class Outcome:
    day: date | None
    symbol: str
    leg: str
    r: float


@dataclass(frozen=True)
class Policy:
    schedule: str
    scope: str
    base_risk: float
    dd_guard: bool


def _key(outcome: Outcome, scope: str) -> str:
    if scope == "account":
        return "account"
    if scope == "instrument":
        return outcome.symbol
    if scope == "leg":
        return outcome.leg
    raise ValueError(scope)


def load_outcomes(data_dir: Path) -> list[Outcome]:
    """Load a fixed sequence from the established P0 research model."""
    selector.set_geometry(canonical=False)
    selector.COMPOUND = False
    selector.RISK_TRIAD = 0.0175
    selector.PAIR_CFG.update(selector.PAIRFIT_ASSIGN)
    selector.TRIA_UNIVERSE = [(1, symbol, 0) for symbol in selector.PAIRFIT_ASSIGN]
    selector.PRECOMPUTE_CACHE.clear()
    cache = optimizer.load_cache(data_dir)
    result = selector.run_one(
        cache, "P0", 0.0, selector.DEFAULT_PRIORS,
        ambiguity="stop", challenge=False,
    )
    return [Outcome(
        day=trade.get("date"),
        symbol=str(trade.get("symbol", "")),
        leg="gold" if "entry_date" in trade else "triad",
        r=float(trade["r"]),
    ) for trade in result["trades"]]


def simulate(outcomes: list[Outcome], policy: Policy,
             *, dd_limit: float = DD_LIMIT_PERCENT) -> dict:
    schedule = SCHEDULES[policy.schedule]
    balance = START_BALANCE
    peak = balance
    max_dd = 0.0
    streaks: dict[str, int] = {}
    used = 0
    skipped_daily = 0
    day_key = None
    day_start = balance
    day_pnl = 0.0
    halted = False
    halt_reason = ""
    max_risk = 0.0
    max_streak = 0
    for outcome in outcomes:
        if outcome.day != day_key:
            day_key = outcome.day
            day_start = balance
            day_pnl = 0.0
        if day_pnl <= -day_start * DAILY_STOP_PERCENT / 100.0:
            skipped_daily += 1
            continue
        key = _key(outcome, policy.scope)
        streak = streaks.get(key, 0)
        multiplier = schedule[min(streak, len(schedule) - 1)]
        current_dd = (peak - balance) / peak * 100.0 if peak else 0.0
        risk = policy.base_risk * multiplier
        if policy.dd_guard and current_dd >= DD_GUARD_PERCENT:
            risk *= 0.5
        max_risk = max(max_risk, risk)
        max_streak = max(max_streak, streak)
        pnl = balance * risk * outcome.r
        balance += pnl
        used += 1
        day_pnl += pnl
        peak = max(peak, balance)
        max_dd = max(max_dd, (peak - balance) / peak * 100.0 if peak else 0.0)
        if outcome.r > 0:
            streaks[key] = 0
        else:
            streaks[key] = streak + 1
        if max_dd >= dd_limit:
            halted = True
            halt_reason = "drawdown_limit"
            break
    first = next((x.day for x in outcomes if x.day is not None), None)
    last = next((x.day for x in reversed(outcomes) if x.day is not None), None)
    span_years = ((last - first).days / 365.25
                  if first is not None and last is not None else 0.0)
    cagr = ((balance / START_BALANCE) ** (1 / span_years) - 1) * 100 \
        if span_years > 0.5 and balance > 0 else 0.0
    return {
        "policy": policy,
        "final": balance,
        "roi": (balance / START_BALANCE - 1) * 100.0,
        "dd": max_dd,
        "cagr": cagr,
        "trades": used,
        "skipped_daily": skipped_daily,
        "max_risk": max_risk,
        "max_streak": max_streak,
        "halted": halted,
        "halt_reason": halt_reason,
    }


def shuffled_stress(outcomes: list[Outcome], policy: Policy,
                    *, runs: int = 5000, seed: int = 20260914) -> dict:
    rng = random.Random(seed)
    values = outcomes[:]
    dds: list[float] = []
    finals: list[float] = []
    for _ in range(runs):
        shuffled = values[:]
        rng.shuffle(shuffled)
        # Disable the calendar daily stop for a shuffled path: dates no longer
        # describe the order and the test is specifically sequence risk.
        result = simulate_no_daily_stop(shuffled, policy, dd_limit=100.0)
        dds.append(result["dd"])
        finals.append(result["final"])
    dds.sort()
    finals.sort()
    n = len(dds)
    return {
        "policy": policy,
        "over15": sum(value >= DD_LIMIT_PERCENT for value in dds) / n * 100,
        "dd50": dds[n // 2],
        "dd95": dds[int(n * 0.95)],
        "dd99": dds[int(n * 0.99)],
        "final50": finals[n // 2],
    }


def simulate_no_daily_stop(outcomes: list[Outcome], policy: Policy,
                           *, dd_limit: float) -> dict:
    """Same path simulator with dates ignored for order-shuffle stress."""
    schedule = SCHEDULES[policy.schedule]
    balance = START_BALANCE
    peak = balance
    max_dd = 0.0
    streaks: dict[str, int] = {}
    for outcome in outcomes:
        key = _key(outcome, policy.scope)
        streak = streaks.get(key, 0)
        risk = policy.base_risk * schedule[min(streak, len(schedule) - 1)]
        current_dd = (peak - balance) / peak * 100.0 if peak else 0.0
        if policy.dd_guard and current_dd >= DD_GUARD_PERCENT:
            risk *= 0.5
        balance += balance * risk * outcome.r
        peak = max(peak, balance)
        max_dd = max(max_dd, (peak - balance) / peak * 100.0 if peak else 0.0)
        streaks[key] = 0 if outcome.r > 0 else streak + 1
        if max_dd >= dd_limit:
            break
    return {"final": balance, "dd": max_dd}


def policy_text(policy: Policy) -> str:
    guard = "+ddguard" if policy.dd_guard else ""
    return f"{policy.schedule}/{policy.scope}/{policy.base_risk*100:.2f}%{guard}"


def write_report(gate: list[dict], selected: dict | None,
                 confirmation: list[dict] | None, stress: list[dict],
                 path: Path) -> None:
    lines = [
        "# Smart Fibonacci Lab — Research Only", "",
        "All schedules are capped loss-streak multipliers. The daily stop is",
        f"{DAILY_STOP_PERCENT:.1f}%, the drawdown ceiling is {DD_LIMIT_PERCENT:.1f}%,",
        f"and the optional high-water guard halves risk after {DD_GUARD_PERCENT:.1f}% DD.",
        "The input is the current normalized net-R P0 sequence; this is not an",
        "exact live-lot validation at every risk fraction.", "", "## Gate", "",
        "| Policy | Trades | ROI | CAGR | DD | PF-like result | Final |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for r in sorted(gate, key=lambda x: -x["roi"]):
        lines.append(f"| {policy_text(r['policy'])} | {r['trades']} | "
                     f"{r['roi']:.1f}% | {r['cagr']:.1f}% | {r['dd']:.1f}% | "
                     f"max-risk {r['max_risk']*100:.1f}% | ${r['final']:.2f} |")
    lines += ["", "## Selected gate policy", "",
              policy_text(selected["policy"]) if selected else "None", ""]
    lines += ["## Four-year confirmation", ""]
    if confirmation:
        for r in confirmation:
            lines.append(f"- {policy_text(r['policy'])}: ROI {r['roi']:.1f}%, "
                         f"CAGR {r['cagr']:.1f}%, DD {r['dd']:.1f}%, "
                         f"final ${r['final']:.2f}")
    else:
        lines.append("Not run.")
    lines += ["", "## Shuffled sequence stress", "",
              "10,000 random reorderings of the same outcomes; dates are ignored.",
              "", "| Policy | Paths >15% DD | Median DD | 95th DD | 99th DD | Median final |",
              "|---|---:|---:|---:|---:|---:|"]
    for r in stress:
        lines.append(f"| {policy_text(r['policy'])} | {r['over15']:.1f}% | "
                     f"{r['dd50']:.1f}% | {r['dd95']:.1f}% | {r['dd99']:.1f}% | "
                     f"${r['final50']:.0f} |")
    lines += ["", "## Verdict", "",
              "A policy is not accepted because it wins on the historical order.",
              "It must remain positive on the unchanged confirmation window and",
              "leave sufficient sequence-risk margin in the shuffled stress test.",
              "A capped progression is a risk rule, not a source of predictive edge.", ""]
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--confirm", action="store_true")
    parser.add_argument("--no-doc", action="store_true")
    args = parser.parse_args()
    print("=" * 118)
    print("SMART FIBONACCI LAB — capped loss schedules with daily/DD guards")
    print("=" * 118)
    gate_outcomes = load_outcomes(optimizer.DATA_2Y)
    policies = [Policy(schedule, scope, risk, guard)
                for schedule in SCHEDULES
                for scope in SCOPES
                for risk in BASE_RISKS
                for guard in (False, True)]
    gate = [simulate(gate_outcomes, policy) for policy in policies]
    viable = [r for r in gate if not r["halted"] and r["trades"] >= 15
              and r["dd"] < DD_LIMIT_PERCENT]
    print(f"2-year gate: {len(gate)} policies; {len(viable)} survived the DD ceiling")
    for r in sorted(viable, key=lambda x: -x["roi"])[:20]:
        print(f"  {policy_text(r['policy']):<35} ROI={r['roi']:>7.1f}% "
              f"CAGR={r['cagr']:>5.1f}% DD={r['dd']:>5.1f}% "
              f"trades={r['trades']:>3} maxrisk={r['max_risk']*100:>4.1f}%")
    selected = max(viable, key=lambda r: (r["roi"], -r["dd"])) if viable else None
    if selected:
        print("\nSelected on gate:")
        print("  " + policy_text(selected["policy"]))
    confirmation = None
    if args.confirm and selected:
        confirmation_outcomes = load_outcomes(optimizer.DATA_4Y)
        confirmation = [
            simulate(confirmation_outcomes, selected["policy"]),
        ]
        print("\nFour-year confirmation:")
        for r in confirmation:
            print(f"  {policy_text(r['policy']):<35} ROI={r['roi']:>7.1f}% "
                  f"CAGR={r['cagr']:>5.1f}% DD={r['dd']:>5.1f}% "
                  f"trades={r['trades']:>3}")
    # Stress the gate leader and the fixed-risk control at the same base risk.
    stress_policies = []
    if selected:
        stress_policies.append(selected["policy"])
        control = Policy("fixed", selected["policy"].scope,
                         selected["policy"].base_risk,
                         selected["policy"].dd_guard)
        if control not in stress_policies:
            stress_policies.append(control)
    stress = [shuffled_stress(gate_outcomes, policy, runs=10000)
              for policy in stress_policies]
    for r in stress:
        print(f"  stress {policy_text(r['policy']):<35} >15DD={r['over15']:>5.1f}% "
              f"medianDD={r['dd50']:>5.1f}% p95DD={r['dd95']:>5.1f}%")
    if not args.no_doc:
        write_report(gate, selected, confirmation, stress,
                     Path("findings_smart_fibonacci_lab.md"))
        print("Wrote findings_smart_fibonacci_lab.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
