"""Research-only Fibonacci progression lab.

A Fibonacci progression after losses is still a martingale family.  This tool
exists to quantify its tail risk on the repository's latest validated P0 trade
sequence; it does not modify an EA and it must not be used to conceal a risk
schedule from a broker or account provider.

The simulation uses the normalized net-R outcomes from the 4-year
pair-fitted TRIAD + Gold P0 research run.  Risk sizing is intentionally
abstracted as ``balance * risk_fraction * R`` so that the progression can be
compared without pretending that M5 OHLC data proves live lot rounding.  The
report includes a shuffled-outcome stress test because the historical order
is only one path.

Usage:
    python tools/fibonacci_martingale_lab.py
"""
from __future__ import annotations

import argparse
import random
import statistics
from dataclasses import dataclass
from pathlib import Path
import os
import sys

sys.path.insert(0, os.path.abspath("."))
import tools.order_selector as selector  # noqa: E402
import tools.optimizer_v2 as optimizer  # noqa: E402

START_BALANCE = 2500.0
DD_LIMIT_PERCENT = 15.0
DEFAULT_FIB = (1, 1, 2, 3, 5, 8, 13)


@dataclass(frozen=True)
class Outcome:
    day: object
    symbol: str
    r: float
    leg: str


def load_outcomes() -> list[Outcome]:
    """Load the exact current research sequence, with no compounding."""
    selector.set_geometry(canonical=False)
    selector.COMPOUND = False
    selector.RISK_TRIAD = 0.0175
    selector.PAIR_CFG.update(selector.PAIRFIT_ASSIGN)
    selector.TRIA_UNIVERSE = [(1, symbol, 0) for symbol in selector.PAIRFIT_ASSIGN]
    selector.PRECOMPUTE_CACHE.clear()
    cache = optimizer.load_cache(optimizer.DATA_4Y)
    result = selector.run_one(
        cache, "P0", 0.0, selector.DEFAULT_PRIORS,
        ambiguity="stop", challenge=False,
    )
    return [Outcome(
        day=trade.get("date"),
        symbol=trade.get("symbol", ""),
        r=float(trade["r"]),
        leg="gold" if "entry_date" in trade else "triad",
    ) for trade in result["trades"]]


def simulate(outcomes: list[Outcome], base_risk: float,
             fib: tuple[int, ...] = DEFAULT_FIB,
             multiplier_cap: int | None = None,
             stop_after_losses: int | None = None,
             dd_limit: float = DD_LIMIT_PERCENT) -> dict:
    balance = START_BALANCE
    peak = balance
    max_dd = 0.0
    loss_streak = 0
    max_loss_streak = 0
    max_risk = 0.0
    used = 0
    halted = False
    halt_reason = ""
    for outcome in outcomes:
        if stop_after_losses is not None and loss_streak >= stop_after_losses:
            halted = True
            halt_reason = "loss_streak_limit"
            break
        index = min(loss_streak, len(fib) - 1)
        multiplier = fib[index]
        if multiplier_cap is not None:
            multiplier = min(multiplier, multiplier_cap)
        risk = base_risk * multiplier
        max_risk = max(max_risk, risk)
        balance += balance * risk * outcome.r
        used += 1
        peak = max(peak, balance)
        max_dd = max(max_dd, (peak - balance) / peak * 100.0)
        if outcome.r > 0:
            loss_streak = 0
        else:
            loss_streak += 1
            max_loss_streak = max(max_loss_streak, loss_streak)
        if max_dd >= dd_limit or balance <= START_BALANCE * (1 - dd_limit / 100):
            halted = True
            halt_reason = "drawdown_limit"
            break
    return {
        "base_risk": base_risk,
        "cap": multiplier_cap,
        "stop_after_losses": stop_after_losses,
        "final": balance,
        "roi": (balance / START_BALANCE - 1) * 100.0,
        "dd": max_dd,
        "trades": used,
        "max_risk": max_risk,
        "max_loss_streak": max_loss_streak,
        "halted": halted,
        "halt_reason": halt_reason,
    }


def monte_carlo(outcomes: list[Outcome], base_risk: float,
                multiplier_cap: int | None, runs: int = 10000,
                seed: int = 20260913) -> dict:
    rng = random.Random(seed)
    values = [outcome.r for outcome in outcomes]
    dds: list[float] = []
    finals: list[float] = []
    for _ in range(runs):
        shuffled = values[:]
        rng.shuffle(shuffled)
        synthetic = [Outcome(None, "", value, "") for value in shuffled]
        result = simulate(synthetic, base_risk, multiplier_cap=multiplier_cap,
                          dd_limit=100.0)
        dds.append(result["dd"])
        finals.append(result["final"])
    dds.sort()
    finals.sort()
    q50 = runs // 2
    q95 = int(runs * 0.95)
    q99 = int(runs * 0.99)
    return {
        "base_risk": base_risk,
        "cap": multiplier_cap,
        "runs": runs,
        "over_15_pct": sum(dd >= DD_LIMIT_PERCENT for dd in dds) / runs * 100,
        "dd_median": dds[q50],
        "dd_p95": dds[q95],
        "dd_p99": dds[q99],
        "final_p05": finals[int(runs * 0.05)],
        "final_median": finals[q50],
        "final_p95": finals[q95],
    }


def fmt(result: dict) -> str:
    cap = "none" if result["cap"] is None else str(result["cap"])
    return (f"base={result['base_risk']*100:.2f}% cap={cap:<4} "
            f"final=${result['final']:.0f} ROI={result['roi']:.1f}% "
            f"DD={result['dd']:.1f}% trades={result['trades']} "
            f"max-risk={result['max_risk']*100:.1f}% "
            f"loss-streak={result['max_loss_streak']} "
            f"{'HALT:'+result['halt_reason'] if result['halted'] else ''}")


def write_report(outcomes: list[Outcome], deterministic: list[dict],
                 stress: list[dict], path: Path) -> None:
    lines = [
        "# Fibonacci Progression / Martingale Lab — Research Only",
        "",
        "This is a risk study, not a deployment recommendation. A Fibonacci",
        "progression after losses remains a martingale family. The outcomes are",
        "the current 4-year P0 normalized R sequence; no claim is made that a",
        "different lot size preserves exact live R after broker rounding.",
        "",
        f"Sequence length: {len(outcomes)} realized outcomes. Drawdown limit: "
        f"{DD_LIMIT_PERCENT:.1f}%.",
        "",
        "## Historical sequence",
        "",
        "| Base risk | Multiplier cap | Final | ROI | Max DD | Trades | Max risk |",
        "|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for r in deterministic:
        cap = "none" if r["cap"] is None else str(r["cap"])
        lines.append(f"| {r['base_risk']*100:.2f}% | {cap} | "
                     f"${r['final']:.0f} | {r['roi']:.1f}% | {r['dd']:.1f}% | "
                     f"{r['trades']} | {r['max_risk']*100:.1f}% |")
    lines += [
        "",
        "## Shuffled path stress",
        "",
        "The historical trade outcomes are randomly reordered 10,000 times.",
        "This is not a full block bootstrap, but it demonstrates how much the",
        "martingale result depends on the lucky order of wins and losses.",
        "",
        "| Base risk | Cap | Paths >15% DD | Median DD | 95th DD | 99th DD | Median final |",
        "|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for r in stress:
        cap = "none" if r["cap"] is None else str(r["cap"])
        lines.append(f"| {r['base_risk']*100:.2f}% | {cap} | "
                     f"{r['over_15_pct']:.1f}% | {r['dd_median']:.1f}% | "
                     f"{r['dd_p95']:.1f}% | {r['dd_p99']:.1f}% | "
                     f"${r['final_median']:.0f} |")
    lines += [
        "",
        "## Verdict",
        "",
        "The progression can make a favorable historical path look better, but",
        "it does not create edge. A loss cluster increases the next position",
        "exactly when the strategy is not working. Any cap or loss-stop that",
        "prevents ruin also removes the recovery property, leaving a more complex",
        "risk schedule with no demonstrated expectancy advantage.",
        "",
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-doc", action="store_true")
    args = parser.parse_args()
    outcomes = load_outcomes()
    print("=" * 100)
    print("FIBONACCI MARTINGALE LAB — research only, normalized R sequence")
    print("=" * 100)
    print(f"4-year sequence: {len(outcomes)} realized outcomes; DD limit {DD_LIMIT_PERCENT:.1f}%")

    deterministic = []
    for base in (0.005, 0.010, 0.020):
        for cap in (None, 3, 5):
            result = simulate(outcomes, base, multiplier_cap=cap)
            deterministic.append(result)
            print(fmt(result))
    stress = []
    for base in (0.005, 0.010, 0.020, 0.030):
        for cap in (None, 3, 5):
            result = monte_carlo(outcomes, base, cap)
            stress.append(result)
            cap_text = "none" if cap is None else str(cap)
            print(f"shuffle base={base*100:.2f}% cap={cap_text:<4} "
                  f">15DD={result['over_15_pct']:.1f}% "
                  f"medianDD={result['dd_median']:.1f}% "
                  f"p95DD={result['dd_p95']:.1f}%")
    if not args.no_doc:
        write_report(outcomes, deterministic, stress,
                     Path("findings_fibonacci_martingale_lab.md"))
        print("Wrote findings_fibonacci_martingale_lab.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
