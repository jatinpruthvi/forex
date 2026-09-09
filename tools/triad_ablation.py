"""Preregistered ablation research round for TRIAD-R V2.1 (P2 plan).

Purpose
-------
After the frozen-baseline evidence pipeline (P0/P1) is complete, this module
runs the *separate, small, preregistered* research round that tests whether the
complicated V2.1 entry actually earns its complexity.  It is deliberately NOT
part of the frozen 160-config selection:

- The v2.1 registry and its walk-forward/holdout evidence remain untouched and
  are never reused as ablation evidence.
- This round declares its own variants, its own calendar splits (frozen here,
  before any data is generated), its own fill policy, and its own predeclared
  decision rules; every one of those values is covered by the registry SHA-256.
- The decision logic lives here and cannot be changed without re-registering.

Hypotheses
----------
Q1  Does displacement confirmation help?            -> V1 (simpler reclaim)
Q2  Does the 50% retracement limit help?            -> V2 (quote entry)
Q3  Are geometry filters useful?                    -> V3/V4/V5 (one at a time)

Every variant changes exactly one entry element; stops, target, time stop,
breakeven policy, cost gate, lot rounding, symbol economics, session clocks,
news gates, and the fill policy are the fixed controls (Profile A, +1.5R,
45-minute time stop, no breakeven move, range band 30-80, ATR band 20-80).

Decision rules (predeclared in the registry; enforced by ``evaluate``)
----------------------------------------------------------------------
R1  Per-variant selection gates (WALK_FORWARD):
    zero rule violations/operational errors; per combination >= 100 fills;
    aggregate >= 300 fills; positive expectancy per combination; profit factor
    >= 1.15 per combination; calendar-year robustness (>= 2 positive years);
    positive expectancy under 1.5x spread / 2x slippage stress.

R2  Superiority: R1 plus the familywise-adjusted lower bound of the paired
    day-level expectancy difference (variant - baseline, 5-day block bootstrap,
    Bonferroni over the 5 competing variants, 95%) must exceed +0.05R.

R5  Simplicity tie (only for variants declared simpler than baseline): R1 plus
    variant fills >= 1.2 x baseline fills, mean paired difference >= -0.05R,
    and the adjusted interval covering zero (no significant harm).  If a
    simpler rule performs within -0.05R with reliably more opportunity, it
    replaces the complex rule.

R3  Holdout confirmation (fresh window, evaluated only after R2/R5 decisions):
    variant holdout expectancy >= 0, >= baseline - 0.05R, and a positive
    ordinary bootstrap lower bound.

R4  Conflict rule: if more than one variant is confirmed, nothing is adopted
    this round; a follow-up round must re-register with the best variant as
    the new baseline and test combinations of changes (never stack changes
    from the same round).

No live/EA parameter changes are permitted as a result of this round.  Any
adoption requires a fresh P0/P1-style pipeline run on new evidence first.

Commands
--------
    # Print the CSV contract (the v2.1 schema, plus variant IDs).
    python3 tools/triad_ablation.py schema

    # Write the frozen ablation registry (refuses to overwrite without --force).
    python3 tools/triad_ablation.py preregister --output validation/triad_v2_2_ablation_registry.json

    # Build rows for every declared variant from observed events.
    python3 tools/triad_ablation.py build \
        --event-file observed_events.csv \
        --registry validation/triad_v2_2_ablation_registry.json \
        --selection-split 2019.01.01 2024.12.31 \
        --holdout-split 2025.01.01 2026.08.31 \
        --output ablation_rows.csv

    # Evaluate on WALK_FORWARD, freeze decisions, then confirm on HOLDOUT.
    python3 tools/triad_ablation.py validate \
        --registry validation/triad_v2_2_ablation_registry.json \
        --input ablation_rows.csv \
        --output ablation_report.json
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import statistics
import sys
from collections import defaultdict
from dataclasses import asdict, dataclass
from datetime import date
from pathlib import Path
from typing import Iterator, Mapping, Sequence

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools.replay_export import (
    EVENT_FIELDS,
    BASELINE_ENTRY_SPEC,
    ENTRY_MODES,
    ConfigSpec,
    EntrySpec,
    ExportPlan,
    ObservedEvent,
    _no_candidate,
    _rejected,
    derive_ablation_event_rows,
    load_observed_events,
    write_rows_csv,
)
from tools.triad_validation import (
    ALLOWED_COMBINATIONS,
    CSV_FIELDS,
    FillPolicy,
    ReplayRow,
    ValidationError,
    _percentile,
    apply_fill_policy,
    load_replay_rows,
    metric_report,
    validate_replay_coverage,
)

ABLATION_SCHEMA_VERSION = "TRIAD_ABLATION_V1"
ABLATION_REGISTRY_VERSION = "TRIAD_R_V2_2_ABLATION_6"
SELECTION_SPLIT = "WALK_FORWARD"
HOLDOUT_SPLIT = "HOLDOUT"

# Fixed controls for the whole round (V2.1 Profile A at 45 minutes, no BE).
FIXED_CONTROL_PROFILE = "A"
FIXED_CONTROL_RISK_FRACTION = 0.004
FIXED_CONTROL_TARGET_R = 1.5
FIXED_CONTROL_TIME_STOP_MINUTES = 45
FIXED_CONTROL_BREAKEVEN = False
FIXED_CONTROL_INITIAL_BALANCE = 2500.0
FIXED_CONTROL_RANGE_BAND = (30, 80)
FIXED_CONTROL_ATR_BAND = (20, 80)

# Predeclared split cut (fixed at registration; re-register before seeing
# outcomes if the acquired data cannot cover this range).
SELECTION_START = "2019-01-01"
SELECTION_END = "2024-12-31"
HOLDOUT_START = "2025-01-01"
HOLDOUT_END = "2026-08-31"

# Predeclared decision thresholds (registry payload covers these).
ACCEPT_DELTA_R = 0.05
OPPORTUNITY_FLOOR_FRACTION = 0.80
SIMPLER_TIE_DELTA_R = 0.05
SIMPLER_OPPORTUNITY_PREMIUM = 1.20
MINIMUM_COMBINATION_FILLS = 100
MINIMUM_AGGREGATE_FILLS = 300
MINIMUM_COMBINATION_PROFIT_FACTOR = 1.15
BOOTSTRAP_SAMPLES = 2000
BLOCK_DAYS = 5
FAMILYWISE_ALPHA = 0.05


@dataclass(frozen=True)
class AblationRun:
    variant_id: str
    question: str
    description: str
    changed_element: str
    simplicity_bonus: bool
    entry_spec: EntrySpec

    @property
    def config_id(self) -> str:
        return self.variant_id


@dataclass(frozen=True)
class AblationSettings:
    accept_delta_r: float = ACCEPT_DELTA_R
    opportunity_floor_fraction: float = OPPORTUNITY_FLOOR_FRACTION
    simpler_tie_delta_r: float = SIMPLER_TIE_DELTA_R
    simpler_opportunity_premium: float = SIMPLER_OPPORTUNITY_PREMIUM
    minimum_combination_fills: int = MINIMUM_COMBINATION_FILLS
    minimum_aggregate_fills: int = MINIMUM_AGGREGATE_FILLS
    minimum_combination_profit_factor: float = MINIMUM_COMBINATION_PROFIT_FACTOR
    bootstrap_samples: int = BOOTSTRAP_SAMPLES
    block_days: int = BLOCK_DAYS
    familywise_alpha: float = FAMILYWISE_ALPHA


def build_runs() -> list[AblationRun]:
    return [
        AblationRun(
            variant_id="ABL-V0-BASELINE",
            question="Q0",
            description="Frozen V2.1 entry: sweep, 3-bar reclaim (60% wick), displacement (60% body, midpoint), limit at 50% displacement body.",
            changed_element="none (baseline)",
            simplicity_bonus=False,
            entry_spec=BASELINE_ENTRY_SPEC,
        ),
        AblationRun(
            variant_id="ABL-V1-SIMPLER-RECLAIM",
            question="Q1",
            description="Displacement confirmation removed; limit at 50% of the reclaim body. Tests whether displacement adds selection value or removes opportunities.",
            changed_element="displacement module removed; entry moved to reclaim-body retracement",
            simplicity_bonus=True,
            entry_spec=EntrySpec(
                displacement_body_min=None,
                entry_mode="limit_reclaim_body_0.5",
            ),
        ),
        AblationRun(
            variant_id="ABL-V2-QUOTE-ENTRY",
            question="Q2",
            description="First executable quote after confirmation instead of the 50% retracement limit. Cost and stop band are evaluated after the actual quote entry (documented confound).",
            changed_element="entry mode changed from limit-retracement to immediate quote",
            simplicity_bonus=False,
            entry_spec=EntrySpec(
                entry_mode="first_executable_quote_after_displacement",
            ),
        ),
        AblationRun(
            variant_id="ABL-V3-NO-RECLAIM-WICK",
            question="Q3",
            description="Reclaim-bar 60% wick filter removed; all other entry conditions unchanged.",
            changed_element="reclaim wick minimum removed",
            simplicity_bonus=True,
            entry_spec=EntrySpec(reclaim_wick_min=None),
        ),
        AblationRun(
            variant_id="ABL-V4-BODY-40",
            question="Q3",
            description="Displacement body threshold lowered from 60% to 40% of bar range.",
            changed_element="displacement body minimum 0.60 -> 0.40",
            simplicity_bonus=False,
            entry_spec=EntrySpec(displacement_body_min=0.40),
        ),
        AblationRun(
            variant_id="ABL-V5-NO-MIDPOINT",
            question="Q3",
            description="Reclaim-midpoint direction filter removed; displacement direction derives from the body.",
            changed_element="midpoint confirmation removed",
            simplicity_bonus=False,
            entry_spec=EntrySpec(require_midpoint=False),
        ),
    ]


def fixed_config_spec(variant_id: str) -> ConfigSpec:
    return ConfigSpec(
        config_id=variant_id,
        profile=FIXED_CONTROL_PROFILE,
        risk_fraction=FIXED_CONTROL_RISK_FRACTION,
        target_r=FIXED_CONTROL_TARGET_R,
        time_stop_minutes=FIXED_CONTROL_TIME_STOP_MINUTES,
        move_stop_to_entry_after_confirmed_1r=FIXED_CONTROL_BREAKEVEN,
    )


# In-memory declaration (no file dependency); the committed registry is the
# frozen copy that is hashed and enforced by load_registry().
ABL_RUNS = tuple(build_runs())


# ---------------------------------------------------------------------------
# Registry (same mutation-protection pattern as the frozen v2.1 registry)
# ---------------------------------------------------------------------------


def _canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def _payload_hash(payload: Mapping[str, object]) -> str:
    return hashlib.sha256(_canonical_json(payload).encode("utf-8")).hexdigest()


def build_registry() -> dict[str, object]:
    policy = FillPolicy()
    settings = AblationSettings()
    payload: dict[str, object] = {
        "schema_version": ABLATION_SCHEMA_VERSION,
        "registry_version": ABLATION_REGISTRY_VERSION,
        "canonical_strategy": "THE5ERS-CHALLENGE-STRATEGY-V2.md revision 2.1 (ablations only; no rule changed)",
        "purpose": (
            "Preregistered P2 research round: does the V2.1 entry complexity earn "
            "itself? Separate from the frozen 160-config selection; its evidence "
            "never reuses the v2.1 holdout."
        ),
        "questions": {
            "Q1": "Does displacement confirmation help?",
            "Q2": "Does the 50% retracement limit help?",
            "Q3": "Are geometry filters useful?",
        },
        "fixed_controls": {
            "profile": FIXED_CONTROL_PROFILE,
            "risk_fraction": FIXED_CONTROL_RISK_FRACTION,
            "target_r": FIXED_CONTROL_TARGET_R,
            "time_stop_minutes": FIXED_CONTROL_TIME_STOP_MINUTES,
            "move_stop_to_entry_after_confirmed_1r": FIXED_CONTROL_BREAKEVEN,
            "range_band_percentile": list(FIXED_CONTROL_RANGE_BAND),
            "atr_band_percentile": list(FIXED_CONTROL_ATR_BAND),
            "initial_balance": FIXED_CONTROL_INITIAL_BALANCE,
            "stops_exits_sizing_locked": True,
            "one_change_per_variant": True,
            "no_stacking_this_round": True,
            "no_live_parameter_change": True,
        },
        "splits": {
            SELECTION_SPLIT: [SELECTION_START, SELECTION_END],
            HOLDOUT_SPLIT: [HOLDOUT_START, HOLDOUT_END],
            "note": (
                "Frozen at registration before any data was generated; if the "
                "acquired data cannot cover these ranges, re-register with the "
                "new dates before seeing any outcome."
            ),
        },
        "evaluation": {
            "selection_split": SELECTION_SPLIT,
            "holdout_split": HOLDOUT_SPLIT,
            "paired_comparison": (
                "per calendar day and combination: sum(net R of variant fills) "
                "minus sum(net R of baseline fills); days with no fill on either "
                "side contribute zero, so opportunity differences are visible."
            ),
            "bootstrap": {
                "method": "5-calendar-day moving block bootstrap of the paired day mean",
                "familywise_adjustment": "Bonferroni over the competing variants",
            },
            "decision_rules": [
                "R1 per-variant selection gates (fills, expectancy, profit factor, year robustness, stress)",
                "R2 superiority: familywise-adjusted paired-difference lower bound > +0.05R",
                "R5 simplicity tie: for variants declared simpler than baseline, "
                ">= 1.2x opportunity AND adjusted lower bound > -0.05R (no significant harm)",
                "R3 holdout confirmation after R2/R5 decisions",
                "R4 conflict: multiple confirmed variants require a fresh combined round",
            ],
        },
        "fill_policy": asdict(policy),
        "decision": asdict(settings),
        "csv_fields": list(CSV_FIELDS),
        "runs": [
            {
                **{
                    key: value
                    for key, value in asdict(run).items()
                    if key != "entry_spec"
                },
                "entry_spec": asdict(run.entry_spec),
            }
            for run in build_runs()
        ],
    }
    return {**payload, "registry_sha256": _payload_hash(payload)}


def load_registry(path: Path) -> dict[str, object]:
    try:
        registry = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValidationError(f"cannot load ablation registry {path}: {exc}") from exc
    if not isinstance(registry, dict) or "registry_sha256" not in registry:
        raise ValidationError("ablation registry is missing its commit hash")
    stored = registry["registry_sha256"]
    payload = {key: value for key, value in registry.items() if key != "registry_sha256"}
    if stored != _payload_hash(payload):
        raise ValidationError("ablation registry hash mismatch; protocol was changed")
    expected = build_registry()
    if registry != expected:
        raise ValidationError("ablation registry does not match this tool's frozen declaration")
    return registry


def write_registry(path: Path, overwrite: bool = False) -> dict[str, object]:
    if path.exists() and not overwrite:
        raise ValidationError(f"refusing to overwrite existing ablation registry: {path}")
    registry = build_registry()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(registry, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return registry


def load_runs(registry: Mapping[str, object]) -> list[AblationRun]:
    runs: list[AblationRun] = []
    for item in registry["runs"]:  # type: ignore[index]
        entry_spec = EntrySpec(**item["entry_spec"])
        runs.append(
            AblationRun(
                variant_id=str(item["variant_id"]),
                question=str(item["question"]),
                description=str(item["description"]),
                changed_element=str(item["changed_element"]),
                simplicity_bonus=bool(item["simplicity_bonus"]),
                entry_spec=entry_spec,
            )
        )
    if not runs:
        raise ValidationError("ablation registry contains no runs")
    if runs[0].variant_id != "ABL-V0-BASELINE":
        raise ValidationError("the baseline run must be declared first")
    return runs


def load_settings(registry: Mapping[str, object]) -> AblationSettings:
    return AblationSettings(**registry["decision"])  # type: ignore[arg-type]


# ---------------------------------------------------------------------------
# Row loading / coverage (same CSV contract as v2.1, validated IDs only)
# ---------------------------------------------------------------------------


def load_ablation_rows(path: Path, runs: Sequence[AblationRun]) -> list[ReplayRow]:
    synthetic_registry: dict[str, object] = {
        "configurations": [{"config_id": run.variant_id} for run in runs]
    }
    return load_replay_rows(path, synthetic_registry)


def _coverage_configs(runs: Sequence[AblationRun]) -> list[AblationRun]:
    """Duck-typed so the v2.1 coverage checker can validate ablation rows."""
    return list(runs)


def declared_splits(registry: Mapping[str, object]) -> tuple[date, date, date, date]:
    splits = registry["splits"]
    return (
        date.fromisoformat(str(splits[SELECTION_SPLIT][0])),  # type: ignore[index]
        date.fromisoformat(str(splits[SELECTION_SPLIT][1])),  # type: ignore[index]
        date.fromisoformat(str(splits[HOLDOUT_SPLIT][0])),  # type: ignore[index]
        date.fromisoformat(str(splits[HOLDOUT_SPLIT][1])),  # type: ignore[index]
    )


def guard_split_args(registry: Mapping[str, object], selection: tuple[str, str],
                     holdout: tuple[str, str]) -> None:
    declared = declared_splits(registry)
    actual = (
        _parse_date(selection[0], "selection_start"),
        _parse_date(selection[1], "selection_end"),
        _parse_date(holdout[0], "holdout_start"),
        _parse_date(holdout[1], "holdout_end"),
    )
    if actual != declared:
        raise ValidationError(
            "the announced WALK_FORWARD/HOLDOUT cuts differ from the preregistered "
            f"declaration {actual} != {declared}; re-register before seeing data "
            "instead of moving the cut"
        )


def guard_row_days(rows: Sequence[ReplayRow], registry: Mapping[str, object]) -> None:
    selection_start, selection_end, holdout_start, holdout_end = declared_splits(registry)
    for row in rows:
        if row.split == SELECTION_SPLIT:
            ok = selection_start <= row.server_day <= selection_end
        elif row.split == HOLDOUT_SPLIT:
            ok = holdout_start <= row.server_day <= holdout_end
        else:  # pragma: no cover - the loader rejects unknown splits.
            ok = False
        if not ok:
            raise ValidationError(
                f"row {row.config_id}/{row.server_day} falls outside the preregistered "
                f"{row.split} window; the cuts must be frozen before data generation"
            )


# ---------------------------------------------------------------------------
# Evaluation
# ---------------------------------------------------------------------------


def _run_rows(rows: Sequence[ReplayRow], run: AblationRun, split: str) -> list[ReplayRow]:
    return [
        row
        for row in rows
        if row.config_id == run.variant_id and row.split == split
    ]


def _r1_failures(report: Mapping[str, object], settings: AblationSettings) -> list[str]:
    failures: list[str] = []
    if int(report["rule_violations"]) != 0:
        failures.append("rule_violations")
    if int(report["operational_errors"]) != 0:
        failures.append("operational_errors")
    if int(report["fills"]) < settings.minimum_aggregate_fills:
        failures.append("aggregate_fill_count")
    if report["expectancy_r"] is None or float(report["expectancy_r"]) <= 0.0:
        failures.append("aggregate_expectancy")
    if not bool(report.get("year_robustness_ok", False)):
        failures.append("year_robustness")
    for combination in sorted(ALLOWED_COMBINATIONS):
        combo = report["per_combination"][combination]  # type: ignore[index]
        if int(combo["fills"]) < settings.minimum_combination_fills:
            failures.append(f"{combination}:fill_count")
        if combo["expectancy_r"] is None or float(combo["expectancy_r"]) <= 0.0:
            failures.append(f"{combination}:expectancy")
        pf = combo["profit_factor"]
        numeric_pf = math.inf if pf == "Infinity" else (0.0 if pf is None else float(pf))
        if numeric_pf < settings.minimum_combination_profit_factor:
            failures.append(f"{combination}:profit_factor")
    return failures


def _stress_failures(report: Mapping[str, object]) -> list[str]:
    failures: list[str] = []
    if report["expectancy_r"] is None or float(report["expectancy_r"]) <= 0.0:
        failures.append("stressed_aggregate_expectancy")
    return failures


def _day_net_totals(rows: Sequence[ReplayRow], policy: FillPolicy, *,
                    stressed: bool, seed: int) -> dict[tuple[date, str], tuple[int, int, float]]:
    """(fills, candidate-signals, net R total) per day/combination."""
    totals: dict[tuple[date, str], list[float]] = defaultdict(list)
    candidates: dict[tuple[date, str], int] = defaultdict(int)
    for row in rows:
        if row.candidate:
            candidates[(row.server_day, row.combination)] += 1
        trade = apply_fill_policy(row, policy, stressed=stressed, seed=seed)
        if trade is not None:
            totals[(row.server_day, row.combination)].append(trade.net_r)
    return {
        key: (len(values), candidates[key], float(sum(values)))
        for key, values in totals.items()
    }


def paired_day_differences(variant_rows: Sequence[ReplayRow], baseline_rows: Sequence[ReplayRow],
                           policy: FillPolicy, *, seed: int
                           ) -> tuple[list[tuple[date, str, float, int, int, float, float]], float, float]:
    """Paired day-level differences and per-side fill totals.

    Pairing key is (server_day, combination).  A day where one side has no fill
    contributes the other side's net R as the difference (opportunity effect is
    visible), and is recorded with the zero side's fill count so the audit can
    separate "same opportunity" from "extra opportunity".
    """
    baseline = _day_net_totals(baseline_rows, policy, stressed=False, seed=seed)
    variant = _day_net_totals(variant_rows, policy, stressed=False, seed=seed)
    keys = sorted(set(baseline) | set(variant))
    differences: list[tuple[date, str, float, int, int, float, float]] = []
    variant_fills = 0
    baseline_fills = 0
    for key in keys:
        b = baseline.get(key, (0, 0, 0.0))
        v = variant.get(key, (0, 0, 0.0))
        differences.append(
            (
                key[0],
                key[1],
                float(v[2] - b[2]),
                int(v[0]),
                int(b[0]),
                float(b[2]),
                float(v[2]),
            )
        )
        variant_fills += int(v[0])
        baseline_fills += int(b[0])
    return differences, float(variant_fills), float(baseline_fills)


def paired_bootstrap_interval(differences: Sequence[tuple[date, str, float, int, int, float, float]],
                              *, samples: int, block_days: int, alpha: float,
                              family_size: int, seed: int) -> dict[str, object]:
    """Block bootstrap of the mean paired day-level difference (Bonferroni).

    The statistic is the mean over calendar days of the per-day paired
    difference (variant total minus baseline total for that day/combination,
    combined across combinations on the same day).  The resampling unit is the
    calendar day, resampled in contiguous 5-day moving blocks; days with no
    fill on either side contribute zero, so opportunity differences are
    visible.  The interval is widened by a Bonferroni adjustment over the
    competing variants.
    """
    if samples <= 0 or family_size <= 0 or not 0 < alpha < 1:
        raise ValidationError("invalid ablation bootstrap settings")
    by_day: dict[date, list[float]] = defaultdict(list)
    for day, _combination, diff, _vf, _bf, _bnet, _vnet in differences:
        by_day[day].append(diff)
    days = sorted(by_day)
    if not days:
        return {
            "observed_mean_difference_r": None,
            "ordinary_interval": [None, None],
            "familywise_adjusted_interval": [None, None],
            "usable_samples": 0,
        }
    day_means = [statistics.fmean(by_day[day]) for day in days]
    observed = statistics.fmean(day_means)
    rng = random.Random(seed)
    means: list[float] = []
    for _ in range(samples):
        sampled: list[float] = []
        position = 0
        while position < len(days):
            start = rng.randrange(len(days))
            take = min(max(1, block_days), len(days) - position)
            for offset in range(take):
                sampled.append(day_means[(start + offset) % len(days)])
            position += take
        if sampled:
            means.append(statistics.fmean(sampled))
    if not means:
        raise ValidationError("every ablation bootstrap replicate contained no paired days")
    ordinary_tail = alpha / 2.0
    adjusted_tail = alpha / (2.0 * family_size)
    return {
        "observed_mean_difference_r": observed,
        "paired_day_count": len(days),
        "paired_observations": len(differences),
        "ordinary_interval": [
            _percentile(means, ordinary_tail),
            _percentile(means, 1.0 - ordinary_tail),
        ],
        "familywise_adjusted_interval": [
            _percentile(means, adjusted_tail),
            _percentile(means, 1.0 - adjusted_tail),
        ],
        "method": "5-day moving block bootstrap of the mean paired day-level difference, "
                  "Bonferroni familywise adjustment",
        "family_size": family_size,
        "familywise_alpha": alpha,
        "requested_samples": samples,
        "usable_samples": len(means),
        "block_days": block_days,
    }


def decide(run: AblationRun, r1_failures: list[str], stress_failures: list[str],
           paired: Mapping[str, object], settings: AblationSettings,
           baseline_fills: float) -> tuple[str, list[str]]:
    """Apply the predeclared R2/R5 decision rules.

    Returns (decision, justification).  ``decision`` is one of:
    ``not_eligible``, ``superior``, ``simpler_tie``, or ``not_adopted``.
    """
    if r1_failures or stress_failures:
        return "not_eligible", [*r1_failures, *stress_failures]
    adjusted = paired["familywise_adjusted_interval"]
    mean = float(paired["observed_mean_difference_r"])
    lower = adjusted[0]
    variant_fills = float(paired["variant_fills"])
    if lower is not None and float(lower) > settings.accept_delta_r:
        return "superior", [
            f"adjusted lower bound {lower:.4f}R > +{settings.accept_delta_r:.2f}R",
            f"mean paired difference {mean:.4f}R",
        ]
    if run.simplicity_bonus:
        if variant_fills + 1e-9 < settings.simpler_opportunity_premium * baseline_fills:
            return "not_adopted", [
                f"opportunity {variant_fills:.0f} < "
                f"{settings.simpler_opportunity_premium:.2f}x baseline {baseline_fills:.0f}"
            ]
        if mean + 1e-9 < -settings.simpler_tie_delta_r:
            return "not_adopted", [
                f"mean paired difference {mean:.4f}R below -{settings.simpler_tie_delta_r:.2f}R"
            ]
        if lower is None or float(lower) <= -settings.simpler_tie_delta_r:
            return "not_adopted", [
                f"adjusted lower bound {lower} fails the -{settings.simpler_tie_delta_r:.2f}R "
                "no-significant-harm floor"
            ]
        return "simpler_tie", [
            f"within -{settings.simpler_tie_delta_r:.2f}R of baseline with >= "
            f"{settings.simpler_opportunity_premium:.2f}x opportunity and no "
            "familywise-significant harm"
        ]
    return "not_adopted", ["no superiority and no simplicity-tie eligibility"]


def evaluate(registry_path: Path, input_path: Path, output_path: Path) -> dict[str, object]:
    registry = load_registry(registry_path)
    runs = load_runs(registry)
    settings = load_settings(registry)
    policy = FillPolicy(**registry["fill_policy"])  # type: ignore[arg-type,index]
    rows = load_ablation_rows(input_path, runs)
    guard_row_days(rows, registry)
    validate_replay_coverage(rows, _coverage_configs(runs))

    baseline = runs[0]
    baseline_rows = _run_rows(rows, baseline, SELECTION_SPLIT)
    baseline_report = metric_report(
        baseline_rows,
        policy,
        stressed=False,
        seed=20260904,
        config_risk_fractions={run.variant_id: FIXED_CONTROL_RISK_FRACTION for run in runs},
        initial_balance=FIXED_CONTROL_INITIAL_BALANCE,
        qualifying_cash=FIXED_CONTROL_INITIAL_BALANCE * 0.005,
    )
    baseline_fills = float(baseline_report["fills"])

    variant_blocks: list[dict[str, object]] = []
    for run in runs[1:]:
        var_rows = _run_rows(rows, run, SELECTION_SPLIT)
        report = metric_report(
            var_rows,
            policy,
            stressed=False,
            seed=20260904,
            config_risk_fractions={run.variant_id: FIXED_CONTROL_RISK_FRACTION},
            initial_balance=FIXED_CONTROL_INITIAL_BALANCE,
            qualifying_cash=FIXED_CONTROL_INITIAL_BALANCE * 0.005,
        )
        stressed = metric_report(
            var_rows,
            policy,
            stressed=True,
            seed=20260904,
            config_risk_fractions={run.variant_id: FIXED_CONTROL_RISK_FRACTION},
            initial_balance=FIXED_CONTROL_INITIAL_BALANCE,
            qualifying_cash=FIXED_CONTROL_INITIAL_BALANCE * 0.005,
        )
        differences, variant_fills, baseline_fills = paired_day_differences(
            var_rows, baseline_rows, policy, seed=20260904
        )
        paired = paired_bootstrap_interval(
            differences,
            samples=settings.bootstrap_samples,
            block_days=settings.block_days,
            alpha=settings.familywise_alpha,
            family_size=len(runs) - 1,
            seed=20260904,
        )
        paired["variant_fills"] = variant_fills
        paired["baseline_fills"] = baseline_fills
        r1 = _r1_failures(report, settings)
        stress = _stress_failures(stressed)
        decision, justification = decide(
            run, r1, stress, paired, settings, baseline_fills
        )
        variant_blocks.append(
            {
                "variant_id": run.variant_id,
                "question": run.question,
                "description": run.description,
                "r1_gates_pass": not r1,
                "r1_failures": r1,
                "stress_gates_pass": not stress,
                "stress_failures": stress,
                "metrics": {
                    "fills": report["fills"],
                    "expectancy_r": report["expectancy_r"],
                    "profit_factor": report["profit_factor"],
                    "year_robustness_ok": report["year_robustness_ok"],
                    "per_combination": report["per_combination"],
                    "stress_expectancy_r": stressed["expectancy_r"],
                },
                "paired": paired,
                "decision": decision,
                "justification": justification,
            }
        )

    adopted = [block for block in variant_blocks if block["decision"] in {"superior", "simpler_tie"}]
    holdout_confirmations: dict[str, dict[str, object]] = {}
    for block in adopted:
        run = next(item for item in runs if item.variant_id == block["variant_id"])
        variant_holdout = metric_report(
            _run_rows(rows, run, HOLDOUT_SPLIT),
            policy,
            stressed=False,
            seed=20260904,
            config_risk_fractions={run.variant_id: FIXED_CONTROL_RISK_FRACTION},
            initial_balance=FIXED_CONTROL_INITIAL_BALANCE,
            qualifying_cash=FIXED_CONTROL_INITIAL_BALANCE * 0.005,
        )
        baseline_holdout = metric_report(
            _run_rows(rows, baseline, HOLDOUT_SPLIT),
            policy,
            stressed=False,
            seed=20260904,
            config_risk_fractions={baseline.variant_id: FIXED_CONTROL_RISK_FRACTION},
            initial_balance=FIXED_CONTROL_INITIAL_BALANCE,
            qualifying_cash=FIXED_CONTROL_INITIAL_BALANCE * 0.005,
        )
        variant_expectancy = (
            None if variant_holdout["expectancy_r"] is None else float(variant_holdout["expectancy_r"])
        )
        baseline_expectancy = (
            None if baseline_holdout["expectancy_r"] is None else float(baseline_holdout["expectancy_r"])
        )
        confirmed = (
            variant_expectancy is not None
            and variant_expectancy >= 0.0
            and baseline_expectancy is not None
            and variant_expectancy >= baseline_expectancy - settings.accept_delta_r
        )
        holdout_confirmations[block["variant_id"]] = {
            "variant_holdout_expectancy_r": variant_expectancy,
            "baseline_holdout_expectancy_r": baseline_expectancy,
            "confirmed": confirmed,
        }

    confirmed = [vid for vid, info in holdout_confirmations.items() if info["confirmed"]]
    if len(confirmed) > 1:
        final = {
            "result": "MULTIPLE_ADOPTIONS_REQUIRE_COMBINED_FOLLOWUP_ROUND",
            "confirmed_variants": confirmed,
            "note": (
                "R4: do not stack changes from one round. Re-register a follow-up "
                "round with the best variant as the new baseline and test the "
                "other change(s) combined, on fresh evidence."
            ),
        }
    elif len(confirmed) == 1:
        final = {
            "result": "VARIANT_SUPPORTED",
            "confirmed_variant": confirmed[0],
            "note": (
                "Adoption is not automatic: the candidate must then pass a fresh "
                "P0/P1-style pipeline (replay + section-13 gates + forward demo) "
                "with the variant as the new baseline before any live change."
            ),
        }
    else:
        final = {
            "result": "NO_CHANGE_SUPPORTED",
            "confirmed_variants": [],
            "note": "Keep the frozen entry; reconsider only with new evidence or a new question.",
        }

    report = {
        "schema_version": ABLATION_SCHEMA_VERSION,
        "registry_version": ABLATION_REGISTRY_VERSION,
        "registry_sha256": registry["registry_sha256"],
        "input_sha256": hashlib.sha256(input_path.read_bytes()).hexdigest(),
        "baseline_variant": baseline.variant_id,
        "baseline_metrics": {
            "fills": baseline_report["fills"],
            "expectancy_r": baseline_report["expectancy_r"],
            "profit_factor": baseline_report["profit_factor"],
            "year_robustness_ok": baseline_report["year_robustness_ok"],
        },
        "variants": variant_blocks,
        "holdout_confirmations": holdout_confirmations,
        "outcome": final,
        "warnings": [
            "This report is not evidence that the source replay was look-ahead-free or broker-representative.",
            "No ablation outcome authorizes a change to the EA, the frozen v2.1 registry, or any live parameter.",
        ],
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return report


# ---------------------------------------------------------------------------
# Export builder for the ablation round (same observed-event contract)
# ---------------------------------------------------------------------------


def build_ablation_export(events: Sequence[ObservedEvent], runs: Sequence[AblationRun],
                          plan: ExportPlan) -> list[ReplayRow]:
    """Expand events into the ablation matrix for every declared run.

    Mirror of :func:`build_export_rows` with one difference: each run carries
    its own preregistered entry spec, and rows are labelled with the run's
    variant ID instead of a V2.1 profile config.  Stop, target, time stop,
    breakeven policy, cost gate, lot rounding, and fill fields are the fixed
    controls for every variant.
    """
    by_day_combination: dict[tuple[date, str], list[ObservedEvent]] = {}
    for event in events:
        by_day_combination.setdefault((event.server_day, event.combination), []).append(event)

    def split_for(day: date) -> str:
        if plan.selection_start <= day <= plan.selection_end:
            return "WALK_FORWARD"
        if plan.holdout_start <= day <= plan.holdout_end:
            return "HOLDOUT"
        raise ValidationError(
            f"server day {day} falls outside the declared WALK_FORWARD and HOLDOUT "
            "splits; the cuts must be predeclared before data generation"
        )

    # Enforce the predeclared cut against EVERY observed event before any row
    # is produced; otherwise an out-of-cut day would silently disappear.
    for event in events:
        split_for(event.server_day)

    rows: list[ReplayRow] = []
    for split, start, end in (
        (SELECTION_SPLIT, plan.selection_start, plan.selection_end),
        (HOLDOUT_SPLIT, plan.holdout_start, plan.holdout_end),
    ):
        for day in _iter_days(start, end):
            day_rows: list[ReplayRow] = []
            for run in runs:
                config = fixed_config_spec(run.variant_id)
                for combination in ALLOWED_COMBINATIONS:
                    matches = sorted(
                        by_day_combination.get((day, combination), []),
                        key=lambda event: (event.sequence, event.event_id),
                    )
                    if not matches:
                        day_rows.append(_no_candidate(config, day, combination, split=split))
                        continue
                    first = matches[0]
                    derived = derive_ablation_event_rows(
                        first, config, run.entry_spec, variant_id=run.variant_id
                    )
                    row = derived[0]
                    day_rows.append(ReplayRow(**{**asdict(row), "split": split}))
                    for extra in matches[1:]:
                        # Same-session repeated sweep: logged, never an order.
                        day_rows.append(
                            ReplayRow(
                                **{
                                    **asdict(_rejected(extra, config, "same_session_repeat")),
                                    "config_id": run.variant_id,
                                    "split": split,
                                }
                            )
                        )
            rows.extend(day_rows)
    # Deterministic export order.
    rows.sort(
        key=lambda row: (row.config_id, row.server_day, row.combination, row.sequence, row.event_id)
    )
    return rows


def _iter_days(start: date, end: date) -> Iterator[date]:
    current = start
    while current <= end:
        yield current
        try:
            current = date.fromordinal(current.toordinal() + 1)
        except OverflowError:
            return


def schema_text() -> str:
    lines = [
        "Ablation rows use the exact v2.1 replay CSV schema; the first column "
        "(config_id) carries the ablation variant ID from the frozen registry:",
        "",
        ",".join(CSV_FIELDS),
        "",
        "Variant IDs: " + ", ".join(run.variant_id for run in build_runs()),
        "",
        "build: python3 tools/triad_ablation.py build --event-file ... --registry ... \"\n"
        "  --selection-split START END --holdout-split START END --output ...",
    ]
    return "\n".join(lines) + "\n"


def _parse_date(value: str, field_name: str) -> date:
    normalized = value.strip().replace(".", "-")
    try:
        return date.fromisoformat(normalized)
    except ValueError as exc:
        raise ValidationError(
            f"{field_name} must be YYYY-MM-DD (or YYYY.MM.DD), got {value!r}"
        ) from exc


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("schema", help="print the ablation row contract")
    preregister = subparsers.add_parser("preregister", help="write the frozen ablation registry")
    preregister.add_argument("--output", type=Path, required=True)
    preregister.add_argument("--force", action="store_true")
    build = subparsers.add_parser("build", help="build ablation rows for every declared variant")
    build.add_argument("--event-file", type=Path, required=True)
    build.add_argument("--registry", type=Path, required=True)
    build.add_argument("--selection-split", nargs=2, metavar=("START", "END"), required=True)
    build.add_argument("--holdout-split", nargs=2, metavar=("START", "END"), required=True)
    build.add_argument("--output", type=Path, required=True)
    validate = subparsers.add_parser("validate", help="evaluate the preregistered ablations")
    validate.add_argument("--registry", type=Path, required=True)
    validate.add_argument("--input", type=Path, required=True)
    validate.add_argument("--output", type=Path, required=True)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.command == "schema":
            print(schema_text(), end="")
        elif args.command == "preregister":
            registry = write_registry(args.output, overwrite=args.force)
            print(
                f"wrote {len(registry['runs'])} ablation runs to {args.output} "
                f"sha256={registry['registry_sha256']}"
            )
        elif args.command == "build":
            registry = load_registry(args.registry)
            runs = load_runs(registry)
            guard_split_args(registry, args.selection_split, args.holdout_split)
            events = load_observed_events(args.event_file)
            selection_start, selection_end = args.selection_split
            holdout_start, holdout_end = args.holdout_split
            plan = ExportPlan(
                _parse_date(selection_start, "selection_start"),
                _parse_date(selection_end, "selection_end"),
                _parse_date(holdout_start, "holdout_start"),
                _parse_date(holdout_end, "holdout_end"),
            )
            rows = build_ablation_export(events, runs, plan)
            write_rows_csv(rows, args.output)
            print(f"wrote {len(rows)} ablation rows to {args.output}")
        elif args.command == "validate":
            report = evaluate(args.registry, args.input, args.output)
            outcome = report["outcome"]
            print(f"ablation outcome: {outcome['result']} -> {args.output}")
        else:  # pragma: no cover - argparse enforces this.
            raise AssertionError(args.command)
    except ValidationError as exc:
        print(f"ablation error: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
