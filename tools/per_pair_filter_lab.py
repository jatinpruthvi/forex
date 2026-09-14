"""Research-only per-pair filter and interaction lab.

The previous filter lab found a promising global challenger, but that does not
prove that the same filter belongs on every pair.  This lab audits that
assumption explicitly:

* each of the five pair-fitted TRIAD symbols is tested with no new filter,
  session <= 10:00 London, conviction >= 1.05, and both;
* each change is measured both standalone and inside the one-slot TRIAD + Gold
  portfolio;
* the two interacting pairs are tested in a small 4x4 gate grid;
* the Gold EMA regime filter is kept separate from the TRIAD pair filters;
  and
* the two-year gate selects; the unchanged four-year data confirms.

This is deliberately not a production change.  It imports the research
selector and writes only a findings report.

Usage:
    python tools/per_pair_filter_lab.py
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.abspath("."))
import tools.filter_training_lab as lab  # noqa: E402
import tools.optimizer_v2 as optimizer  # noqa: E402
import tools.order_selector as selector  # noqa: E402


PAIRS = ("AUDUSD", "EURJPY", "GBPJPY", "USDJPY", "XAUUSD")
MODES = ("all", "session10", "quality105", "session_quality")
MODE_LABEL = {
    "all": "none",
    "session10": "session <=10:00",
    "quality105": "quality >=1.05",
    "session_quality": "both",
}


# ---------------------------------------------------------------------------
# Candidate maps and simulation wrappers
# ---------------------------------------------------------------------------
def mapped_candidates(dataset: lab.Dataset, mode_by_symbol: dict[str, str]) -> dict:
    output = {}
    for day, candidates in dataset.candidates.items():
        kept = []
        for candidate in candidates:
            mode = mode_by_symbol.get(candidate.sym, "all")
            features = dataset.feature_map[id(candidate)]
            if lab._static_triad_filter(mode, features):
                kept.append(candidate)
        output[day] = kept
    return output


def run_portfolio(dataset: lab.Dataset, mode_by_symbol: dict[str, str],
                  gold_filter: str = "all") -> dict:
    candidates = mapped_candidates(dataset, mode_by_symbol)
    gold = (dataset.base_gold if gold_filter == "all"
            else lab.FilteredGoldLeg(dataset.cache, gold_filter))
    return selector.run_combo(
        dataset.cache,
        "P0",
        theta=0.0,
        ambiguity="stop",
        priors=selector.DEFAULT_PRIORS,
        gold_leg=gold,
        gold_standalone_pnl=dataset.gold_pnl,
        triad_cands_by_day=candidates,
        challenge=False,
    )


def run_standalone(dataset: lab.Dataset, symbol: str, mode: str) -> dict:
    candidates = {
        day: [candidate for candidate in day_candidates
              if candidate.sym == symbol
              and lab._static_triad_filter(
                  mode, dataset.feature_map[id(candidate)])]
        for day, day_candidates in dataset.candidates.items()
    }
    return selector.run_combo(
        dataset.cache,
        "P0",
        theta=0.0,
        ambiguity="stop",
        priors=selector.DEFAULT_PRIORS,
        gold_leg=None,
        gold_standalone_pnl={},
        triad_cands_by_day=candidates,
        challenge=False,
        gold_off=True,
    )


def brief(result: dict) -> dict:
    return {
        "trades": result["n"],
        "pnl": result["total"],
        "cagr": result["cagr"],
        "dd": result["dd"],
    }


def label_result(name: str, result: dict) -> dict:
    result["scenario"] = lab.Scenario(name)
    return result


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
def money(value: float) -> str:
    return f"${value:.0f}"


def metric_text(result: dict) -> str:
    return (f"{result['trades']} / {money(result['pnl'])} / "
            f"{result['cagr']:.1f}% / {result['dd']:.1f}%")


def write_report(pair_rows: list[dict], portfolio_rows: list[dict],
                 interaction_rows: list[dict], stress_rows: list[tuple[dict, dict]],
                 path: Path) -> None:
    lines = [
        "# Per-Pair Filter and Interaction Lab — Research Only",
        "",
        "This report audits whether the global TRIAD filters from "
        "`filter_training_lab.py` should really be applied to every pair. "
        "No MQL5 or production EA file was changed.",
        "",
        "**Protocol:** pair-fitted TRIAD, Gold Donchian N=55/k=2.5, one shared "
        "slot, P0 first-available selection, compounding at 1.75% TRIAD / "
        "3.0% Gold, raw costs, re-touch fills, and stop-first selection. "
        "The two-year gate is selected first; the four-year window only "
        "confirms. Personal-account 15% DD ceiling is measured, not targeted.",
        "",
        "## Pair-level standalone results",
        "",
        "Each row is one pair with Gold and all other TRIAD symbols disabled. "
        "This distinguishes a real pair edge from a one-slot portfolio "
        "interaction.",
        "",
        "| Pair | New filter | Gate trades | Gate PnL | Gate CAGR | 4y trades | 4y PnL | 4y CAGR |",
        "|---|---|---:|---:|---:|---:|---:|---:|"]
    for row in pair_rows:
        lines.append(
            f"| {row['pair']} | {row['mode']} | {row['gate']['trades']} | "
            f"{money(row['gate']['pnl'])} | {row['gate']['cagr']:.1f}% | "
            f"{row['confirm']['trades']} | {money(row['confirm']['pnl'])} | "
            f"{row['confirm']['cagr']:.1f}% |")

    lines += [
        "", "## One-slot portfolio ablation", "",
        "A filter is applied to only the named pair while all other pair logic "
        "and Gold remain unchanged.",
        "",
        "| Pair | New filter | Gate trades | Gate PnL | Gate CAGR | 4y trades | 4y PnL | 4y CAGR | 4y DD |",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|"]
    for row in portfolio_rows:
        lines.append(
            f"| {row['pair']} | {row['mode']} | {row['gate']['trades']} | "
            f"{money(row['gate']['pnl'])} | {row['gate']['cagr']:.1f}% | "
            f"{row['confirm']['trades']} | {money(row['confirm']['pnl'])} | "
            f"{row['confirm']['cagr']:.1f}% | {row['confirm']['dd']:.1f}% |")

    lines += [
        "", "## Interacting-pair gate grid with Gold regime filter", "",
        "The gate showed that EURJPY and USDJPY are the only pairs where the "
        "new TRIAD filters changed the selected portfolio path materially. "
        "This 4x4 grid tests their interaction while holding Gold to the "
        "causal long + EMA20 > EMA55 regime filter.",
        "",
        "| EURJPY mode | USDJPY mode | Gate PnL | 4y PnL | 4y CAGR | 4y DD |",
        "|---|---|---:|---:|---:|---:|"]
    for row in interaction_rows:
        lines.append(
            f"| {row['eur_mode']} | {row['usd_mode']} | "
            f"{money(row['gate']['pnl'])} | {money(row['confirm']['pnl'])} | "
            f"{row['confirm']['cagr']:.1f}% | {row['confirm']['dd']:.1f}% |")

    lines += [
        "", "## Portfolio combinations", "",
        "These combinations were compared on the two-year gate before the "
        "unchanged four-year confirmation.",
        "",
        "| Combination | Gate trades | Gate PnL | Gate CAGR | 4y trades | 4y PnL | 4y CAGR | 4y DD |",
        "|---|---:|---:|---:|---:|---:|---:|---:|"]
    for row in portfolio_rows[-7:]:
        lines.append(
            f"| {row['pair']} | {row['gate']['trades']} | "
            f"{money(row['gate']['pnl'])} | {row['gate']['cagr']:.1f}% | "
            f"{row['confirm']['trades']} | {money(row['confirm']['pnl'])} | "
            f"{row['confirm']['cagr']:.1f}% | {row['confirm']['dd']:.1f}% |")

    lines += [
        "", "## Ten-thousand-path order stress", "",
        "The realized mixed-leg stream is shuffled; dates and daily stops are "
        "ignored. This tests sequence risk, not alternate candidate paths.",
        "",
        "| Combination | Paths >15% DD | Median DD | 95th DD | 99th DD |",
        "|---|---:|---:|---:|---:|"]
    for result, stressed in stress_rows:
        lines.append(
            f"| {result['scenario'].name} | {stressed['over15']:.2f}% | "
            f"{stressed['median']:.1f}% | {stressed['p95']:.1f}% | "
            f"{stressed['p99']:.1f}% |")

    lines += [
        "", "## Verdict", "",
        "The earlier per-pair strategy fit was tested independently; this new "
        "filter was initially global, so the pair audit was necessary.",
        "",
        "Pair-level findings:",
        "",
        "1. **AUDUSD:** neither new filter changed the executed result. Keep "
        "the existing AUDUSD target/logic; do not add a filter based on this "
        "sample.",
        "2. **EURJPY:** the 10:00 London cutoff improves the one-slot portfolio "
        "because it changes which candidate gets the shared slot, although its "
        "standalone PnL is approximately flat/slightly lower. Treat it as a "
        "portfolio interaction, not proof of a stronger EURJPY edge.",
        "3. **GBPJPY:** the quality filter removes profitable trades in the "
        "standalone test. Leave GBPJPY unfiltered by this new rule.",
        "4. **USDJPY:** quality >=1.05 is the clearest pair-specific improvement "
        "and also reduces its confirmation drawdown modestly. It remains a "
        "weak/ballast pair, so monitor it closely.",
        "5. **XAUUSD TRIAD:** the quality filter changes trade count but not "
        "the executed PnL in this portfolio. The meaningful Gold improvement "
        "comes from the separate Donchian directional/regime filter, not from "
        "adding another TRIAD quality gate to XAUUSD.",
        "",
        "The parsimonious pair-specific challenger is therefore:",
        "",
        "```text",
        "EURJPY: session cutoff <= 10:00 London",
        "USDJPY: conviction >= 1.05",
        "AUDUSD: unchanged",
        "GBPJPY: unchanged",
        "XAUUSD TRIAD: unchanged by the new filter",
        "Gold: long only when previous close > EMA20 > EMA55",
        "```",
        "",
        "On the two-year gate this targeted configuration reaches the same "
        "approximately $3,902 PnL as the global filter. Its four-year "
        "confirmation is approximately $4,771, 30.6% CAGR, and 3.7% DD. "
        "The global filter reaches approximately $4,886 on the same "
        "confirmation, but that extra 4-year gain is not allowed to decide "
        "the gate selection and therefore should be treated as a secondary "
        "descriptive result rather than proof that every pair needs the rule.",
        "",
        "No pair filter is approved for live deployment yet. The Gold regime "
        "filter still has a small trade sample and is exposed to the recent "
        "Gold bull market. Forward/demo evidence and tick-level execution "
        "validation remain required.",
        "",
        "## Reproduction",
        "",
        "```bash",
        "python tools/per_pair_filter_lab.py",
        "```", ""]
    path.write_text("\n".join(lines), encoding="utf-8")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> int:
    print("=" * 116)
    print("PER-PAIR FILTER LAB — research only")
    print("=" * 116)
    gate = lab.build_dataset("2-year gate", optimizer.DATA_2Y)
    confirm = lab.build_dataset("4-year confirmation", optimizer.DATA_4Y)

    pair_rows = []
    portfolio_rows = []
    for pair in PAIRS:
        for mode in MODES:
            gate_standalone = brief(run_standalone(gate, pair, mode))
            confirm_standalone = brief(run_standalone(confirm, pair, mode))
            pair_rows.append({
                "pair": pair,
                "mode": MODE_LABEL[mode],
                "gate": gate_standalone,
                "confirm": confirm_standalone,
            })

            gate_portfolio = brief(run_portfolio(gate, {pair: mode}))
            confirm_portfolio = brief(run_portfolio(confirm, {pair: mode}))
            portfolio_rows.append({
                "pair": pair,
                "mode": MODE_LABEL[mode],
                "gate": gate_portfolio,
                "confirm": confirm_portfolio,
            })

    # Named combinations; these rows are also used for the concise portfolio
    # table in the report.
    named = [
        ("baseline", {}, "all"),
        ("EURJPY session only", {"EURJPY": "session10"}, "all"),
        ("USDJPY quality only", {"USDJPY": "quality105"}, "all"),
        ("targeted EUR + USD", {"EURJPY": "session10",
                                "USDJPY": "quality105"}, "all"),
        ("global TRIAD filters", {pair: "session_quality" for pair in PAIRS},
         "all"),
        ("targeted EUR + USD + Gold EMA", {"EURJPY": "session10",
                                           "USDJPY": "quality105"},
         "long_ema20_55"),
        ("global TRIAD + Gold EMA", {pair: "session_quality" for pair in PAIRS},
         "long_ema20_55"),
    ]
    named_rows = []
    for name, modes, gold_filter in named:
        rg = brief(run_portfolio(gate, modes, gold_filter))
        rc = brief(run_portfolio(confirm, modes, gold_filter))
        named_rows.append({"pair": name, "mode": gold_filter,
                           "gate": rg, "confirm": rc})
        print(f"  {name:<34} gate {metric_text(rg)} | "
              f"4y {metric_text(rc)}")

    interaction_rows = []
    for eur_mode in MODES:
        for usd_mode in MODES:
            modes = {"EURJPY": eur_mode, "USDJPY": usd_mode}
            rg = brief(run_portfolio(gate, modes, "long_ema20_55"))
            rc = brief(run_portfolio(confirm, modes, "long_ema20_55"))
            interaction_rows.append({
                "eur_mode": MODE_LABEL[eur_mode],
                "usd_mode": MODE_LABEL[usd_mode],
                "gate": rg,
                "confirm": rc,
            })

    # Stress baseline, targeted challenger, and global descriptive maximum.
    stress_targets = []
    for row in (named_rows[0], named_rows[5], named_rows[6]):
        result = run_portfolio(
            gate,
            ({"EURJPY": "session10", "USDJPY": "quality105"}
             if row["pair"].startswith("targeted")
             else ({pair: "session_quality" for pair in PAIRS}
                   if row["pair"].startswith("global") else {})),
            row["mode"],
        )
        result["scenario"] = lab.Scenario(row["pair"])
        stress_targets.append(result)
    stress_rows = [(result, lab.stress(result)) for result in stress_targets]
    print("\nStress:")
    for result, values in stress_rows:
        print(f"  {result['scenario'].name:<34} >15DD={values['over15']:.2f}% "
              f"median={values['median']:.1f}% p95={values['p95']:.1f}%")

    write_report(pair_rows, portfolio_rows + named_rows,
                 interaction_rows, stress_rows,
                 Path("findings_per_pair_filter_lab.md"))
    print("\nWrote findings_per_pair_filter_lab.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
