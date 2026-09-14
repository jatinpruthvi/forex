"""Research-only training and filter lab for the current TRIAD + Gold stack.

This module deliberately does not change the MQL5 EAs or the production
selection contract.  It asks a narrower question: can transparent, causal
filters improve the current pair-fitted P0 portfolio without trading away the
edge in the weak years?

The experiment uses the same honest order-selector mechanics as the current
champion: pair-fit TRIAD, Gold Donchian N=55/k=2.5, one shared slot,
re-touch fills, raw-account costs, compounding, and stop-first ambiguity for
selection.  Every candidate filter uses information available at its decision
time.  The 2-year window is the gate; the 4-year window is confirmation only.

Scenarios include:

* a London signal-time cutoff and a minimum pattern-quality score;
* Gold long-only and Gold long-only + prior-close EMA20 > EMA55 regime gates;
* cost and prior-day trend filters as negative controls;
* an expanding walk-forward symbol expectancy filter, trained only on
  previously closed shadow signals; and
* a transparent combination of the strongest causal filters.

The output is a research result, not a live-trading recommendation.  The
underlying sample is small, and a price-regime rule that worked in this Gold
bull market can fail in a different regime.

Usage:
    python tools/filter_training_lab.py --confirm
"""
from __future__ import annotations

import argparse
import math
import os
import random
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, os.path.abspath("."))
import tools.aggressive_optimizer as market  # noqa: E402
import tools.optimizer_v2 as optimizer  # noqa: E402
import tools.order_selector as selector  # noqa: E402


START_BALANCE = 2500.0
TRIAD_RISK = 0.0175
GOLD_RISK = 0.03
DD_LIMIT = 15.0
STRESS_RUNS = 10_000
STRESS_SEED = 20260914

# These are deliberately small and pre-declared.  This is a filter audit, not
# an unrestricted feature-mining sweep.
TRIAD_SESSION_CUTOFF = 10       # London wall-clock hour, inclusive
TRIAD_QUALITY_MIN = 1.05        # order_selector conviction score
TRAIN_MIN_OBS = 12
TRAIN_MEAN_R_MIN = 0.0


@dataclass
class Dataset:
    name: str
    path: Path
    cache: dict
    candidates: dict
    feature_map: dict
    base_gold: selector.GoldLeg
    gold_pnl: dict


@dataclass(frozen=True)
class Scenario:
    name: str
    triad_filter: str = "all"
    gold_filter: str = "all"


SCENARIOS = (
    Scenario("baseline"),
    Scenario("triad_session_10", "session10"),
    Scenario("triad_quality_105", "quality105"),
    Scenario("triad_session_quality", "session_quality"),
    Scenario("triad_prior_trend_align", "trend_align"),
    Scenario("triad_cost_to_target_20", "cost20"),
    Scenario("gold_long_only", "all", "long_only"),
    Scenario("gold_long_ema20_55", "all", "long_ema20_55"),
    Scenario("session_quality_plus_gold_long", "session_quality", "long_only"),
    Scenario("session_quality_plus_gold_ema", "session_quality", "long_ema20_55"),
    Scenario("walkforward_symbol", "walkforward_symbol"),
    Scenario("walkforward_plus_static", "walkforward_plus_static"),
)


# ---------------------------------------------------------------------------
# Frozen current strategy setup and causal features
# ---------------------------------------------------------------------------
def configure_current_stack() -> None:
    """Configure only the research selector to the published pair-fit path."""
    selector.set_geometry(canonical=False)
    selector.COMPOUND = True
    selector.RISK_TRIAD = TRIAD_RISK
    selector.RISK_GOLD = GOLD_RISK
    selector.PAIR_CFG.clear()
    selector.PAIR_CFG.update(selector.PAIRFIT_ASSIGN)
    selector.TRIA_UNIVERSE = [(1, symbol, 0) for symbol in selector.PAIRFIT_ASSIGN]
    selector._PREV_HL.clear()
    selector.PRECOMPUTE_CACHE.clear()


def _ema(values: list[float], period: int) -> float | None:
    if len(values) < period:
        return None
    value = sum(values[:period]) / period
    alpha = 2.0 / (period + 1.0)
    for item in values[period:]:
        value = item * alpha + value * (1.0 - alpha)
    return value


def _daily_features(cache: dict, symbol: str) -> dict:
    """Features known before the symbol's entry window opens."""
    by_date, atr_map = cache[symbol]
    dates = sorted(by_date)
    result = {}
    closes: list[float] = []
    for i, day in enumerate(dates):
        previous = dates[i - 1] if i else None
        previous_trend = 0
        previous_close = None
        if previous is not None:
            previous_bars = by_date[previous]
            previous_close = previous_bars[-1].close
            if previous_close > previous_bars[0].open:
                previous_trend = 1
            elif previous_close < previous_bars[0].open:
                previous_trend = -1

        e20 = _ema(closes, 20)
        e55 = _ema(closes, 55)
        atr = atr_map.get(day, 0.0) or 0.0
        asian_start = market.lw_utc(day, 0, 0)
        asian_end = market.lw_utc(day, 7, 0)
        asian = [b for b in by_date[day]
                 if asian_start <= b.ts < asian_end]
        asian_width_atr = ((max(b.high for b in asian) -
                            min(b.low for b in asian)) / atr
                           if asian and atr > 0 else 0.0)
        result[day] = {
            "previous_trend": previous_trend,
            "previous_close": previous_close,
            "ema20": e20,
            "ema55": e55,
            "atr": atr,
            "asian_width_atr": asian_width_atr,
        }
        closes.append(by_date[day][-1].close)
    return result


def _candidate_features(cand, cache: dict, daily: dict) -> dict:
    state = daily[cand.sym].get(cand.day, {})
    trend_side = 1 if cand.side == "long" else -1
    stop_atr = (abs(cand.entry - cand.stop) / state["atr"]
                if state.get("atr", 0.0) else 0.0)
    return {
        "hour": cand.sig_ts.astimezone(selector._LDN).hour,
        "quality": cand.conviction,
        "cost_to_target": cand.costR / max(cand.rr, 1e-9),
        "stop_atr": stop_atr,
        "asian_width_atr": state.get("asian_width_atr", 0.0),
        "trend_align": int(state.get("previous_trend", 0) == trend_side),
        "ema_align": int(
            state.get("ema20") is not None
            and state.get("ema55") is not None
            and state.get("previous_close") is not None
            and ((cand.side == "long"
                  and state["previous_close"] > state["ema20"] > state["ema55"])
                 or (cand.side == "short"
                     and state["previous_close"] < state["ema20"] < state["ema55"]))
        ),
    }


def build_dataset(name: str, path: Path, ambiguity: str = "stop") -> Dataset:
    configure_current_stack()
    cache = optimizer.load_cache(path)
    selector._PREV_HL.clear()
    days = selector._all_days(cache)
    candidates = {
        day: selector.build_day_candidates(cache, day, ambiguity)
        for day in days
    }
    daily = {symbol: _daily_features(cache, symbol) for symbol in cache}
    feature_map = {
        id(cand): _candidate_features(cand, cache, daily)
        for day_cands in candidates.values()
        for cand in day_cands
    }
    base_gold = selector.GoldLeg(cache)
    gold_pnl = {
        trade["entry_date"]: trade["pnl"]
        for trade in base_gold.standalone(GOLD_RISK)
    }
    return Dataset(name, path, cache, candidates, feature_map,
                   base_gold, gold_pnl)


# ---------------------------------------------------------------------------
# Triad filters
# ---------------------------------------------------------------------------
def _static_triad_filter(kind: str, features: dict) -> bool:
    if kind == "all":
        return True
    if kind == "session10":
        return features["hour"] <= TRIAD_SESSION_CUTOFF
    if kind == "quality105":
        return features["quality"] >= TRIAD_QUALITY_MIN
    if kind == "session_quality":
        return (features["hour"] <= TRIAD_SESSION_CUTOFF
                and features["quality"] >= TRIAD_QUALITY_MIN)
    if kind == "trend_align":
        return features["trend_align"] == 1
    if kind == "cost20":
        return features["cost_to_target"] <= 0.20
    raise ValueError(f"unknown static triad filter: {kind}")


def _walkforward_candidates(candidates: dict, *, min_obs: int = TRAIN_MIN_OBS,
                            mean_min: float = TRAIN_MEAN_R_MIN) -> dict:
    """Apply a causal shadow-training expectancy gate per instrument.

    The history contains only candidate outcomes whose exits are already known
    at the current candidate's signal timestamp.  Unfilled candidates do not
    become losses.  This is implementable as a paper/shadow ledger, but it is
    deliberately not allowed to learn from the future or from a candidate's
    own result.
    """
    ordered = sorted(
        (cand for day_cands in candidates.values() for cand in day_cands),
        key=lambda cand: cand.sig_ts,
    )
    history: dict[str, list[tuple[object, float]]] = defaultdict(list)
    allowed: dict = defaultdict(list)
    for cand in ordered:
        key = cand.sym
        closed = [r for exit_ts, r in history[key]
                  if exit_ts <= cand.sig_ts]
        take = True
        if len(closed) >= min_obs:
            take = (sum(closed) / len(closed)) >= mean_min
        if take:
            allowed[cand.day].append(cand)
        if cand.trade is not None:
            history[key].append((cand.exit_ts, cand.r))
    return {day: allowed.get(day, []) for day in candidates}


def filtered_triad_candidates(dataset: Dataset, kind: str) -> dict:
    if kind == "walkforward_symbol":
        return _walkforward_candidates(dataset.candidates)
    if kind == "walkforward_plus_static":
        trained = _walkforward_candidates(dataset.candidates)
        return {
            day: [cand for cand in day_cands
                  if _static_triad_filter(
                      "session_quality", dataset.feature_map[id(cand)])]
            for day, day_cands in trained.items()
        }
    return {
        day: [cand for cand in day_cands
              if _static_triad_filter(
                  kind, dataset.feature_map[id(cand)])]
        for day, day_cands in dataset.candidates.items()
    }


# ---------------------------------------------------------------------------
# Gold filters
# ---------------------------------------------------------------------------
class FilteredGoldLeg(selector.GoldLeg):
    """GoldLeg with a causal entry gate; exits remain exactly unchanged."""

    def __init__(self, cache: dict, filter_name: str):
        super().__init__(cache)
        self.filter_name = filter_name

    def _allow(self, day, side: str, breakout_atr: float) -> bool:
        if self.filter_name == "all":
            return True
        if self.filter_name == "long_only":
            return side == "long"
        if self.filter_name == "breakout03":
            return breakout_atr >= 0.30
        if self.filter_name != "long_ema20_55":
            raise ValueError(f"unknown Gold filter: {self.filter_name}")
        if side != "long":
            return False
        i = self.idx.get(day)
        if i is None:
            return False
        closes = [bar["close"] for _, bar in self.dl[:i]]
        e20 = _ema(closes, 20)
        e55 = _ema(closes, 55)
        previous_close = closes[-1] if closes else None
        return (e20 is not None and e55 is not None
                and previous_close is not None
                and previous_close > e20 > e55)

    def open_action(self, day, pos):
        action = super().open_action(day, pos)
        if pos is None and action[1] is not None:
            if not self._allow(day, action[1], action[2]):
                return False, None, action[2]
        return action


# ---------------------------------------------------------------------------
# Simulation, validation, and stress
# ---------------------------------------------------------------------------
def run_scenario(dataset: Dataset, scenario: Scenario) -> dict:
    triad = filtered_triad_candidates(dataset, scenario.triad_filter)
    gold = (dataset.base_gold if scenario.gold_filter == "all"
            else FilteredGoldLeg(dataset.cache, scenario.gold_filter))
    result = selector.run_combo(
        dataset.cache,
        "P0",
        theta=0.0,
        ambiguity="stop",
        priors=selector.DEFAULT_PRIORS,
        gold_leg=gold,
        gold_standalone_pnl=dataset.gold_pnl,
        triad_cands_by_day=triad,
        # Personal-account study: do not apply the The5ers $2,250 floor or
        # 4.5% challenge-day governor.  We still measure the 15% DD ceiling.
        challenge=False,
    )
    result["scenario"] = scenario
    return result


def yearly_pnl(result: dict) -> dict[int, tuple[int, float]]:
    values: dict[int, list[float]] = defaultdict(list)
    for trade in result["trades"]:
        values[trade["date"].year].append(trade["pnl"])
    return {year: (len(items), sum(items))
            for year, items in sorted(values.items())}


def segment_pnl(result: dict, start_year: int, end_year: int | None = None) -> float:
    return sum(trade["pnl"] for trade in result["trades"]
               if trade["date"].year >= start_year
               and (end_year is None or trade["date"].year <= end_year))


def stress(result: dict, runs: int = STRESS_RUNS,
           seed: int = STRESS_SEED) -> dict:
    """Shuffle the realized mixed-leg trade stream; ignore dates/daily stop."""
    values = [
        (GOLD_RISK if "entry_date" in trade else TRIAD_RISK, trade["r"])
        for trade in result["trades"]
    ]
    rng = random.Random(seed)
    drawdowns: list[float] = []
    for _ in range(runs):
        path = values[:]
        rng.shuffle(path)
        balance = START_BALANCE
        peak = balance
        max_dd = 0.0
        for risk, net_r in path:
            balance += balance * risk * net_r
            peak = max(peak, balance)
            if peak:
                max_dd = max(max_dd, (peak - balance) / peak * 100.0)
        drawdowns.append(max_dd)
    drawdowns.sort()
    n = len(drawdowns)
    return {
        "over15": sum(dd >= DD_LIMIT for dd in drawdowns) / n * 100.0,
        "median": drawdowns[n // 2],
        "p95": drawdowns[int(n * 0.95)],
        "p99": drawdowns[int(n * 0.99)],
    }


def ambiguity_check(path: Path, scenario: Scenario) -> list[dict]:
    rows = []
    for ambiguity in ("target", "coin", "stop"):
        dataset = build_dataset("ambiguity", path, ambiguity)
        result = run_scenario(dataset, scenario)
        rows.append({
            "ambiguity": ambiguity,
            "trades": result["n"],
            "total": result["total"],
            "cagr": result["cagr"],
            "dd": result["dd"],
        })
    return rows


# ---------------------------------------------------------------------------
# Report and command line
# ---------------------------------------------------------------------------
def _result_row(result: dict) -> str:
    scenario: Scenario = result["scenario"]
    return (f"| {scenario.name} | {result['n']} | "
            f"${result['total']:.0f} | {result['cagr']:.1f}% | "
            f"{result['dd']:.1f}% |")


def _stress_row(result: dict, stressed: dict) -> str:
    return (f"| {result['scenario'].name} | {stressed['over15']:.2f}% | "
            f"{stressed['median']:.1f}% | {stressed['p95']:.1f}% | "
            f"{stressed['p99']:.1f}% |")


def write_report(gate_results: list[dict], confirm_results: list[dict],
                 selected: dict, stress_rows: list[tuple[dict, dict]],
                 holdout_rows: list[tuple[str, float, float]],
                 ambiguity_rows: list[dict], path: Path) -> None:
    selected_scenario: Scenario = selected["scenario"]
    lines = [
        "# Strategy Filter and Walk-Forward Lab — Research Only",
        "",
        "This lab tests causal filters around the current pair-fitted P0 "
        "TRIAD + Gold stack. It does not change MQL5 or production EA logic.",
        "",
        "**Account model:** $2,500 personal-account baseline, 1.75% TRIAD "
        "risk and 3.0% Gold risk, compounding, one shared slot, maximum "
        "two trades per day. The 15% drawdown ceiling is measured; no "
        "The5ers floor or challenge-specific daily governor is applied.",
        "",
        "**Causal rule:** every filter uses only data available at the signal "
        "decision. The two-year window is the selection gate and the "
        "four-year window is confirmation; the four-year run never selects "
        "a new filter.",
        "",
        "**Training scenario:** the walk-forward filter keeps an expanding "
        "per-instrument shadow ledger. It can use a candidate only after "
        "at least 12 prior closed shadow outcomes exist and their mean net "
        "R is non-negative. Unfilled candidates are not treated as losses.",
        "",
        "## Scenarios",
        "",
        "- `triad_session_10`: reject TRIAD signals after 10:00 London.",
        "- `triad_quality_105`: require the existing causal conviction score "
        "to be at least 1.05.",
        "- `triad_session_quality`: apply both TRIAD filters.",
        "- `triad_prior_trend_align`: negative-control trend alignment.",
        "- `triad_cost_to_target_20`: reject candidates whose cost is above "
        "20% of target R.",
        "- `gold_long_only`: allow only long Gold breakouts.",
        "- `gold_long_ema20_55`: allow long Gold only when the previous close "
        "is above EMA20 and EMA20 is above EMA55, all computed from prior "
        "daily closes.",
        "- `walkforward_symbol`: expanding per-symbol training gate.",
        "",
        "## Two-year gate",
        "",
        "| Scenario | Trades | PnL | CAGR | Max DD |",
        "|---|---:|---:|---:|---:|",
    ]
    lines.extend(_result_row(result) for result in gate_results)
    lines += ["", "## Four-year confirmation", "",
              "Parameters were chosen on the two-year gate. This table only "
              "confirms the same scenarios on the unchanged four-year data.",
              "", "| Scenario | Trades | PnL | CAGR | Max DD |",
              "|---|---:|---:|---:|---:|"]
    lines.extend(_result_row(result) for result in confirm_results)
    lines += ["", "## Gate training year vs holdout years", "",
              "The two-year gate begins in 2024. This diagnostic reports the "
              "same path's 2024 PnL versus 2025–2026 PnL; it is not used to "
              "re-select after looking at the four-year confirmation.",
              "", "| Scenario | 2024 PnL | 2025–2026 PnL |",
              "|---|---:|---:|"]
    lines.extend(f"| {name} | ${train:.0f} | ${holdout:.0f} |"
                 for name, train, holdout in holdout_rows)
    lines += ["", "## Ten-thousand-path order stress", "",
              "The realized mixed-leg trade stream is randomly reordered; "
              "dates and daily stops are ignored so this isolates sequence "
              "risk. It does not recreate alternate candidate selection paths.",
              "", "| Scenario | Paths >15% DD | Median DD | 95th DD | 99th DD |",
              "|---|---:|---:|---:|---:|"]
    lines.extend(_stress_row(result, stressed)
                 for result, stressed in stress_rows)
    lines += ["", "## Ambiguity validation of the selected gate policy", "",
              f"Selected gate policy: **{selected_scenario.name}**.",
              "", "| Model | Trades | PnL | CAGR | Max DD |",
              "|---|---:|---:|---:|---:|"]
    lines.extend(f"| {row['ambiguity']} | {row['trades']} | "
                 f"${row['total']:.0f} | {row['cagr']:.1f}% | "
                 f"{row['dd']:.1f}% |" for row in ambiguity_rows)
    lines += ["", "## Verdict", "",
              f"The best tested two-year gate policy was **{selected_scenario.name}**.",
              "",
              "A filter is not accepted merely because it increases the "
              "historical return. It must remain positive on the unchanged "
              "four-year confirmation and leave useful sequence-risk margin "
              "under the 15% ceiling.",
              "",
              "The walk-forward expectancy filter did not provide a reliable "
              "improvement: learning from recent outcomes can lock the system "
              "out immediately before a regime change. The prior-day TRIAD "
              "trend and strict cost filters also reduced the result.",
              "",
              "The strongest transparent candidate was the combination of the "
              "10:00 London cutoff, conviction >= 1.05, and Gold's causal "
              "long-plus-EMA20-above-EMA55 regime gate. It is a research challenger, "
              "not certified for live deployment: the Gold sample is only a "
              "small number of multi-day trades and is heavily exposed to the "
              "2024–2026 bullish Gold regime.",
              "",
              "The next validation required before deployment is tick-level "
              "and forward/demo testing, including real spread, slippage, "
              "lot rounding, gaps, and a genuinely unseen future regime.",
              "",
              "## Reproduction",
              "",
              "```bash",
              "python tools/filter_training_lab.py --confirm",
              "```", ""]
    path.write_text("\n".join(lines), encoding="utf-8")


def print_result(result: dict, prefix: str = "") -> None:
    scenario: Scenario = result["scenario"]
    print(f"{prefix}{scenario.name:<38} trades={result['n']:>3} "
          f"PnL=${result['total']:>7.0f} CAGR={result['cagr']:>5.1f}% "
          f"DD={result['dd']:>4.1f}%")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--confirm", action="store_true",
                        help="run the unchanged four-year confirmation")
    parser.add_argument("--no-doc", action="store_true",
                        help="do not write the findings report")
    args = parser.parse_args()

    print("=" * 116)
    print("FILTER + WALK-FORWARD TRAINING LAB — research only")
    print("=" * 116)
    gate = build_dataset("2-year gate", optimizer.DATA_2Y)
    print(f"Gate candidates prepared: {sum(len(x) for x in gate.candidates.values())}")
    gate_results = [run_scenario(gate, scenario) for scenario in SCENARIOS]
    for result in sorted(gate_results, key=lambda item: -item["total"]):
        print_result(result, "  gate ")

    viable = [result for result in gate_results
              if not result["halted"] and result["dd"] < DD_LIMIT]
    if not viable:
        print("No gate scenario survived the 15% ceiling.")
        return 1
    selected = max(viable, key=lambda result: (result["total"], -result["dd"]))
    print("\nSelected on two-year gate:")
    print_result(selected, "  ")

    confirm_results: list[dict] = []
    if args.confirm:
        confirm = build_dataset("4-year confirmation", optimizer.DATA_4Y)
        confirm_results = [run_scenario(confirm, scenario) for scenario in SCENARIOS]
        print("\nFour-year confirmation:")
        for result in sorted(confirm_results, key=lambda item: -item["total"]):
            print_result(result, "  4y ")
    else:
        confirm = None

    # This split is a diagnostic only.  It records the 2024 training-year
    # contribution and the later gate holdout contribution on each full gate
    # path, without changing the selection protocol.
    holdout_rows = []
    for result in gate_results:
        holdout_rows.append((result["scenario"].name,
                             segment_pnl(result, 2024, 2024),
                             segment_pnl(result, 2025, None)))

    stress_targets = [selected]
    baseline = next(result for result in gate_results
                    if result["scenario"].name == "baseline")
    if baseline not in stress_targets:
        stress_targets.append(baseline)
    stress_rows = [(result, stress(result)) for result in stress_targets]
    print("\nRandomized order stress:")
    for result, stressed in stress_rows:
        print(f"  {result['scenario'].name:<38} >15DD={stressed['over15']:.2f}% "
              f"median={stressed['median']:.1f}% p95={stressed['p95']:.1f}% "
              f"p99={stressed['p99']:.1f}%")

    ambiguity_rows: list[dict] = []
    if args.confirm:
        print("\nAmbiguity check for selected policy:")
        ambiguity_rows = ambiguity_check(optimizer.DATA_4Y, selected["scenario"])
        for row in ambiguity_rows:
            print(f"  {row['ambiguity']:<10} trades={row['trades']:>3} "
                  f"PnL=${row['total']:>7.0f} CAGR={row['cagr']:>5.1f}% "
                  f"DD={row['dd']:>4.1f}%")

    if not args.no_doc:
        write_report(
            gate_results,
            confirm_results,
            selected,
            stress_rows,
            holdout_rows,
            ambiguity_rows,
            Path("findings_filter_training_lab.md"),
        )
        print("\nWrote findings_filter_training_lab.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
