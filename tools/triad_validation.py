"""Offline champion-selection and challenge-replay tooling for TRIAD-R V2.1.

This module is deliberately separate from the MQL5 Expert Advisor.  It cannot
submit orders and it never changes live parameters.  It consumes event-level
results exported by a tick/bid-ask replay, verifies them against a frozen
160-configuration registry, selects a provisional champion using WALK_FORWARD
rows only, and evaluates HOLDOUT outcomes only after selection is complete.

The tool does not create trading evidence.  Its output is meaningful only when
its CSV input was produced from independently verified, look-ahead-free data
with realistic symbol economics and historical news/session mapping.

Commands:

    python3 tools/triad_validation.py preregister \
        --output validation/triad_v2_1_registry.json

    python3 tools/triad_validation.py schema

    python3 tools/triad_validation.py validate \
        --registry validation/triad_v2_1_registry.json \
        --input /path/to/replay_rows.csv \
        --output /path/to/validation_report.json

The CSV schema is printed by ``schema``.  There must be at least one row for
every configuration, instrument/session combination, and calendar/server day
in WALK_FORWARD and HOLDOUT; a no-candidate day is represented by
``candidate=false``.  Identical day sets are required across exports so missing
records cannot improve a result or hide an inactivity interval.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import random
import statistics
import sys
from collections import defaultdict
from dataclasses import asdict, dataclass, replace
from datetime import date
from pathlib import Path
from typing import Iterator, Mapping, Sequence


SCHEMA_VERSION = "TRIAD_VALIDATION_V1"
REGISTRY_VERSION = "TRIAD_R_V2_1_160"
SELECTION_SPLIT = "WALK_FORWARD"
HOLDOUT_SPLIT = "HOLDOUT"
ALLOWED_SPLITS = {"TRAIN", SELECTION_SPLIT, HOLDOUT_SPLIT}
ALLOWED_COMBINATIONS = {
    "EURUSD_LONDON",
    "GBPUSD_LONDON",
    "USDJPY_NEW_YORK",
}

RANGE_BANDS = ((30, 80), (35, 75))
ATR_BANDS = ((20, 80), (25, 75))
TIME_STOPS = (30, 45, 60, 90, 0)  # 0 means session-only.
PROFILES = {
    "A": (0.0040, 1.50),
    "B": (0.0035, 1.75),
    "C": (0.0030, 2.00),
    "D": (0.0025, 2.50),
}
BREAKEVEN_POLICIES = (False, True)

CSV_FIELDS = (
    "config_id",
    "split",
    "server_day",
    "sequence",
    "event_id",
    "combination",
    "candidate",
    "activation_ok",
    "limit_touched",
    "trade_through_ticks",
    "fill_fraction",
    "net_r",
    "risk_cash_full",
    "risk_cash_half",
    "net_cash_full",
    "net_cash_half",
    "mae_cash_full",
    "mae_cash_half",
    "spread_r",
    "slippage_r",
    "commission_r",
    "rule_violation",
    "operational_error",
)


@dataclass(frozen=True)
class CandidateConfig:
    config_id: str
    range_low_percentile: int
    range_high_percentile: int
    atr_low_percentile: int
    atr_high_percentile: int
    time_stop_minutes: int
    profile: str
    risk_fraction: float
    target_r: float
    move_stop_to_entry_after_confirmed_1r: bool


@dataclass(frozen=True)
class FillPolicy:
    """Historical pending-order assumptions frozen before replay.

    Baseline requires the limit to trade through by one tick after the modeled
    request was active.  A mere touch is deliberately insufficient.  A partial
    fill is excluded and counted for review because the live EA requires exact
    exposure reconciliation.  The stressed scenario additionally removes a
    deterministic fraction of otherwise profitable limits and increases cost.
    """

    minimum_trade_through_ticks: int = 1
    minimum_fill_fraction: float = 1.0
    stressed_profitable_limit_miss_fraction: float = 0.10
    stressed_spread_multiplier: float = 1.5
    stressed_slippage_multiplier: float = 2.0


@dataclass(frozen=True)
class ValidationThresholds:
    minimum_combination_fills: int = 100
    minimum_aggregate_fills: int = 300
    minimum_combination_expectancy_r: float = 0.0
    minimum_combination_profit_factor: float = 1.15
    minimum_aggregate_expectancy_r: float = 0.20
    minimum_aggregate_profit_factor: float = 1.30
    minimum_stressed_expectancy_r: float = 0.0
    minimum_stressed_profit_factor: float = 0.0
    minimum_phase1_pass_probability: float = 0.70
    minimum_phase2_pass_probability: float = 0.85
    minimum_joint_pass_probability: float = 0.60
    minimum_qualifying_days_by_target_probability: float = 0.99
    maximum_p99_drawdown_fraction: float = 0.06
    require_selection_adjusted_lower_bound_positive: bool = True


# Release gates declared by THE5ERS-CHALLENGE-STRATEGY-V2.md section 13 that
# are NOT part of the frozen registry payload (the registry commits its own
# thresholds, fill policy, and selection rule).  These constants implement the
# canonical Section 13 checklist so that a passing report covers the declared
# "no single year/regime", "firm-floor", "stressed overshoot", and
# "confidence bounds" requirements as well as the frozen point-estimate gates.
# They intentionally do not appear in build_registry().
SPEC_SEC13_MAX_SHUTDOWN_OVERSHOOT_P99 = 0.01
SPEC_SEC13_FIRM_OVERALL_FLOOR_FRACTION = 0.90
SPEC_SEC13_CONFIDENCE_LEVEL = 0.95
SPEC_SEC13_FLOOR_CHECK_PATHS = 1000



@dataclass(frozen=True)
class SimulationSettings:
    initial_balance: float = 2500.0
    phase1_target_fraction: float = 0.10
    phase2_target_fraction: float = 0.05
    qualifying_day_fraction: float = 0.005
    required_qualifying_days: int = 3
    drawdown_reduce_fraction: float = 0.02
    drawdown_shutdown_fraction: float = 0.05
    daily_stop_fraction: float = 0.01
    weekly_stop_fraction: float = 0.02
    inactivity_days: int = 30
    max_phase_calendar_days: int = 730
    block_days: int = 5
    selection_paths: int = 2_000
    holdout_paths: int = 10_000
    bootstrap_samples: int = 10_000
    familywise_alpha: float = 0.05
    random_seed: int = 20_260_904


@dataclass(frozen=True)
class ReplayRow:
    config_id: str
    split: str
    server_day: date
    sequence: int
    event_id: str
    combination: str
    candidate: bool
    activation_ok: bool
    limit_touched: bool
    trade_through_ticks: int
    fill_fraction: float
    net_r: float
    risk_cash_full: float
    risk_cash_half: float
    net_cash_full: float
    net_cash_half: float
    mae_cash_full: float
    mae_cash_half: float
    spread_r: float
    slippage_r: float
    commission_r: float
    rule_violation: bool
    operational_error: bool


@dataclass(frozen=True)
class AppliedTrade:
    row: ReplayRow
    net_r: float
    extra_cost_r: float

    def cash_result(self, half_risk: bool) -> float:
        base = self.row.net_cash_half if half_risk else self.row.net_cash_full
        risk = self.row.risk_cash_half if half_risk else self.row.risk_cash_full
        return base - self.extra_cost_r * risk

    def adverse_cash(self, half_risk: bool) -> float:
        base = self.row.mae_cash_half if half_risk else self.row.mae_cash_full
        risk = self.row.risk_cash_half if half_risk else self.row.risk_cash_full
        return base + self.extra_cost_r * risk


class ValidationError(ValueError):
    """Raised when a frozen registry or replay export is invalid."""


def _config_id(range_band: tuple[int, int], atr_band: tuple[int, int],
               time_stop: int, profile: str, breakeven: bool) -> str:
    time_text = "SESSION" if time_stop == 0 else str(time_stop)
    be_text = "BE1" if breakeven else "BE0"
    return (
        f"R{range_band[0]}_{range_band[1]}-"
        f"A{atr_band[0]}_{atr_band[1]}-"
        f"T{time_text}-P{profile}-{be_text}"
    )


def enumerate_candidate_configs() -> list[CandidateConfig]:
    configs: list[CandidateConfig] = []
    for range_band in RANGE_BANDS:
        for atr_band in ATR_BANDS:
            for time_stop in TIME_STOPS:
                for profile, (risk_fraction, target_r) in PROFILES.items():
                    for breakeven in BREAKEVEN_POLICIES:
                        configs.append(
                            CandidateConfig(
                                config_id=_config_id(
                                    range_band, atr_band, time_stop, profile, breakeven
                                ),
                                range_low_percentile=range_band[0],
                                range_high_percentile=range_band[1],
                                atr_low_percentile=atr_band[0],
                                atr_high_percentile=atr_band[1],
                                time_stop_minutes=time_stop,
                                profile=profile,
                                risk_fraction=risk_fraction,
                                target_r=target_r,
                                move_stop_to_entry_after_confirmed_1r=breakeven,
                            )
                        )
    if len(configs) != 160 or len({item.config_id for item in configs}) != 160:
        raise AssertionError("the declared V2.1 matrix must contain 160 unique configurations")
    return configs


def _canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def _payload_hash(payload: Mapping[str, object]) -> str:
    return hashlib.sha256(_canonical_json(payload).encode("utf-8")).hexdigest()


def build_registry() -> dict[str, object]:
    policy = FillPolicy()
    thresholds = ValidationThresholds()
    settings = SimulationSettings()
    payload: dict[str, object] = {
        "schema_version": SCHEMA_VERSION,
        "registry_version": REGISTRY_VERSION,
        "canonical_strategy": "THE5ERS-CHALLENGE-STRATEGY-V2.md revision 2.1",
        "selection_split": SELECTION_SPLIT,
        "holdout_split": HOLDOUT_SPLIT,
        "selection_rule": [
            "zero rule violations and operational errors",
            "instrument/session combinations pass independently; failing combinations are disabled before portfolio ranking",
            "the frozen enabled-combination set passes all aggregate point-estimate gates",
            "all declared Phase 1, Phase 2, joint, qualifying-day, and drawdown simulation gates pass",
            "maximum joint two-phase pass probability",
            "minimum 95th-percentile drawdown",
            "minimum median joint completion days",
            "lexicographically smallest config_id",
            "selected configuration must retain a positive familywise-adjusted bootstrap lower bound",
        ],
        "fill_policy": asdict(policy),
        "thresholds": asdict(thresholds),
        "simulation": asdict(settings),
        "csv_fields": list(CSV_FIELDS),
        "configurations": [asdict(item) for item in enumerate_candidate_configs()],
    }
    return {**payload, "registry_sha256": _payload_hash(payload)}


def write_registry(path: Path, overwrite: bool = False) -> dict[str, object]:
    if path.exists() and not overwrite:
        raise ValidationError(f"refusing to overwrite existing registry: {path}")
    registry = build_registry()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(registry, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return registry


def load_registry(path: Path) -> dict[str, object]:
    try:
        registry = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValidationError(f"cannot load registry {path}: {exc}") from exc
    if not isinstance(registry, dict) or "registry_sha256" not in registry:
        raise ValidationError("registry is missing its commit hash")
    stored_hash = registry["registry_sha256"]
    payload = {key: value for key, value in registry.items() if key != "registry_sha256"}
    if stored_hash != _payload_hash(payload):
        raise ValidationError("registry hash mismatch; candidate declaration was changed")
    expected = build_registry()
    if registry != expected:
        raise ValidationError("registry does not match this validator's frozen V2.1 declaration")
    return registry


def _strict_bool(value: str, field: str, line_number: int) -> bool:
    normalized = value.strip().lower()
    if normalized in {"true", "1"}:
        return True
    if normalized in {"false", "0"}:
        return False
    raise ValidationError(f"line {line_number}: {field} must be true/false or 1/0")


def _finite_float(value: str, field: str, line_number: int) -> float:
    try:
        parsed = float(value)
    except ValueError as exc:
        raise ValidationError(f"line {line_number}: invalid {field}") from exc
    if not math.isfinite(parsed):
        raise ValidationError(f"line {line_number}: {field} must be finite")
    return parsed


def _nonnegative_float(value: str, field: str, line_number: int) -> float:
    parsed = _finite_float(value, field, line_number)
    if parsed < 0:
        raise ValidationError(f"line {line_number}: {field} must be nonnegative")
    return parsed


def load_replay_rows(path: Path, registry: Mapping[str, object]) -> list[ReplayRow]:
    config_ids = {str(item["config_id"]) for item in registry["configurations"]}  # type: ignore[index]
    rows: list[ReplayRow] = []
    seen: set[tuple[str, str, date, int, str]] = set()
    try:
        handle = path.open("r", encoding="utf-8", newline="")
    except OSError as exc:
        raise ValidationError(f"cannot open replay CSV {path}: {exc}") from exc
    with handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames != list(CSV_FIELDS):
            raise ValidationError(
                "CSV header mismatch; run `python3 tools/triad_validation.py schema`"
            )
        for line_number, raw in enumerate(reader, start=2):
            try:
                config_id = raw["config_id"].strip()
                split = raw["split"].strip().upper()
                server_day = date.fromisoformat(raw["server_day"].strip())
                sequence = int(raw["sequence"])
                event_id = raw["event_id"].strip()
                combination = raw["combination"].strip().upper()
                trade_through_ticks = int(raw["trade_through_ticks"])
            except (KeyError, TypeError, ValueError) as exc:
                raise ValidationError(f"line {line_number}: invalid identifier/date/integer field") from exc
            if config_id not in config_ids:
                raise ValidationError(f"line {line_number}: unknown config_id {config_id}")
            if split not in ALLOWED_SPLITS:
                raise ValidationError(f"line {line_number}: invalid split {split}")
            if combination not in ALLOWED_COMBINATIONS:
                raise ValidationError(f"line {line_number}: invalid combination {combination}")
            if sequence < 0 or trade_through_ticks < 0 or not event_id:
                raise ValidationError(f"line {line_number}: invalid sequence/event/trade-through value")
            key = (config_id, split, server_day, sequence, event_id)
            if key in seen:
                raise ValidationError(f"line {line_number}: duplicate replay row {key}")
            seen.add(key)
            row = ReplayRow(
                config_id=config_id,
                split=split,
                server_day=server_day,
                sequence=sequence,
                event_id=event_id,
                combination=combination,
                candidate=_strict_bool(raw["candidate"], "candidate", line_number),
                activation_ok=_strict_bool(raw["activation_ok"], "activation_ok", line_number),
                limit_touched=_strict_bool(raw["limit_touched"], "limit_touched", line_number),
                trade_through_ticks=trade_through_ticks,
                fill_fraction=_nonnegative_float(raw["fill_fraction"], "fill_fraction", line_number),
                net_r=_finite_float(raw["net_r"], "net_r", line_number),
                risk_cash_full=_nonnegative_float(raw["risk_cash_full"], "risk_cash_full", line_number),
                risk_cash_half=_nonnegative_float(raw["risk_cash_half"], "risk_cash_half", line_number),
                net_cash_full=_finite_float(raw["net_cash_full"], "net_cash_full", line_number),
                net_cash_half=_finite_float(raw["net_cash_half"], "net_cash_half", line_number),
                mae_cash_full=_nonnegative_float(raw["mae_cash_full"], "mae_cash_full", line_number),
                mae_cash_half=_nonnegative_float(raw["mae_cash_half"], "mae_cash_half", line_number),
                spread_r=_nonnegative_float(raw["spread_r"], "spread_r", line_number),
                slippage_r=_nonnegative_float(raw["slippage_r"], "slippage_r", line_number),
                commission_r=_nonnegative_float(raw["commission_r"], "commission_r", line_number),
                rule_violation=_strict_bool(raw["rule_violation"], "rule_violation", line_number),
                operational_error=_strict_bool(raw["operational_error"], "operational_error", line_number),
            )
            if row.fill_fraction > 1.0 + 1e-9:
                raise ValidationError(f"line {line_number}: fill_fraction cannot exceed 1")
            if row.candidate and row.activation_ok and (
                row.risk_cash_full <= 0 or row.risk_cash_half <= 0
            ):
                # A candidate that never activated (gate rejection, sizing
                # skip, router demotion) is a legitimate observation with zero
                # risk and zero cash; only an activated candidate must carry a
                # positive rounded-volume stop risk.
                raise ValidationError(
                    f"line {line_number}: activated candidates require positive cash-risk values"
                )
            rows.append(row)
    if not rows:
        raise ValidationError("replay CSV is empty")
    return rows


def validate_replay_coverage(rows: Sequence[ReplayRow], configs: Sequence[CandidateConfig]) -> None:
    expected_ids = {item.config_id for item in configs}
    by_split_config_combination: dict[tuple[str, str, str], set[date]] = defaultdict(set)
    for row in rows:
        by_split_config_combination[(row.split, row.config_id, row.combination)].add(
            row.server_day
        )
    for split in (SELECTION_SPLIT, HOLDOUT_SPLIT):
        missing = sorted(
            (config_id, combination)
            for config_id in expected_ids
            for combination in ALLOWED_COMBINATIONS
            if not by_split_config_combination[(split, config_id, combination)]
        )
        if missing:
            first_config, first_combination = missing[0]
            raise ValidationError(
                f"{split} is missing {len(missing)} declared configuration/combination exports; "
                f"first={first_config}/{first_combination}"
            )
        keys = [
            (config_id, combination)
            for config_id in sorted(expected_ids)
            for combination in sorted(ALLOWED_COMBINATIONS)
        ]
        reference = by_split_config_combination[(split, *keys[0])]
        for config_id, combination in keys:
            days = by_split_config_combination[(split, config_id, combination)]
            if days != reference:
                raise ValidationError(
                    f"{split} calendar-day coverage differs for {config_id}/{combination}; "
                    "export explicit no-candidate rows for every combination"
                )


def _stable_fraction(config_id: str, event_id: str, seed: int) -> float:
    digest = hashlib.sha256(f"{seed}|{config_id}|{event_id}".encode("utf-8")).digest()
    return int.from_bytes(digest[:8], "big") / float(1 << 64)


def apply_fill_policy(row: ReplayRow, policy: FillPolicy, *, stressed: bool,
                      seed: int) -> AppliedTrade | None:
    if not row.candidate or not row.activation_ok or not row.limit_touched:
        return None
    if row.trade_through_ticks < policy.minimum_trade_through_ticks:
        return None
    if row.fill_fraction + 1e-12 < policy.minimum_fill_fraction:
        return None
    if stressed and row.net_r > 0:
        if _stable_fraction(row.config_id, row.event_id, seed) < policy.stressed_profitable_limit_miss_fraction:
            return None
    extra_cost_r = 0.0
    if stressed:
        extra_cost_r = (
            (policy.stressed_spread_multiplier - 1.0) * row.spread_r
            + (policy.stressed_slippage_multiplier - 1.0) * row.slippage_r
        )
    return AppliedTrade(row=row, net_r=row.net_r - extra_cost_r, extra_cost_r=extra_cost_r)


def _profit_factor(values: Sequence[float]) -> float | None:
    profit = sum(value for value in values if value > 0)
    loss = -sum(value for value in values if value < 0)
    if loss <= 1e-15:
        return None if profit <= 1e-15 else math.inf
    return profit / loss


def _json_number(value: float | None) -> float | str | None:
    if value is None:
        return None
    if math.isinf(value):
        return "Infinity"
    return value


def _all_in_cost_r(row: ReplayRow) -> float:
    """All-in modeled round-trip cost in R (spread + slippage + commission)."""
    return row.spread_r + row.slippage_r + row.commission_r


def _year_net_report(trades: Sequence[AppliedTrade]) -> dict[str, object]:
    """Calendar-year concentration of net R.

    Section 13 requires that no single year/regime is responsible for the
    entire profit.  The operational check: with two or more years carrying
    fills, removing the best calendar year must leave a strictly positive net
    R remainder (which also implies at least two net-positive years).
    """
    by_year: dict[int, float] = defaultdict(float)
    for trade in trades:
        by_year[trade.row.server_day.year] += trade.net_r
    total = float(sum(by_year.values()))
    best_year = max(by_year, key=by_year.get) if by_year else None
    best = float(by_year[best_year]) if best_year is not None else 0.0
    remaining = total - best
    robust = bool(by_year) and len(by_year) >= 2 and total > 0.0 and remaining > 0.0
    return {
        "calendar_years_with_fills": sorted(by_year),
        "positive_net_r_years": sorted(year for year, value in by_year.items() if value > 0),
        "best_year_net_r": best,
        "remaining_net_r_without_best_year": remaining,
        "best_year_net_r_share": (best / total) if total > 0.0 else None,
        "year_robustness_ok": robust,
    }


def _augment_metric_report(entry: dict[str, object], rows: Sequence[ReplayRow],
                           trades: Sequence[AppliedTrade], policy: FillPolicy, *,
                           config_risk_fractions: Mapping[str, float] | None,
                           initial_balance: float | None,
                           qualifying_cash: float | None) -> None:
    """Add §13-motivated execution, cash, and calendar-year metrics.

    Fill-rate denominators: ``candidate_signals`` counts rows where the frozen
    strategy produced an entry candidate; ``activated_orders`` counts only
    candidates whose order became active.  A row that is a candidate but never
    activated encodes a modeled activation refusal (gate, sizing skip, state
    lock), so the two rates have different meanings.
    """
    candidate_signals = sum(1 for row in rows if row.candidate)
    activated = sum(1 for row in rows if row.candidate and row.activation_ok)
    fills = len(trades)
    touched = sum(1 for row in rows if row.candidate and row.activation_ok and row.limit_touched)
    through = sum(
        1
        for row in rows
        if row.candidate
        and row.activation_ok
        and row.limit_touched
        and row.trade_through_ticks >= policy.minimum_trade_through_ticks
    )
    entry["candidate_signals"] = candidate_signals
    entry["activated_orders"] = activated
    entry["activation_refusals"] = candidate_signals - activated
    entry["fill_rate"] = (fills / activated) if activated else None
    entry["signal_fill_rate"] = (fills / candidate_signals) if candidate_signals else None
    entry["limit_touch_rate"] = (touched / activated) if activated else None
    entry["trade_through_rate"] = (through / activated) if activated else None

    if fills:
        # ``trade.cash_result`` embeds the fill-policy stress cost, so cash
        # totals agree with the stressed ``net_r`` used for expectancy; in the
        # normal scenario ``extra_cost_r`` is zero and these equal the row
        # cash columns exactly.
        entry["net_cash_total_full"] = float(sum(trade.cash_result(False) for trade in trades))
        entry["net_cash_total_half"] = float(sum(trade.cash_result(True) for trade in trades))
        entry["net_cash_mean_full"] = statistics.fmean(trade.cash_result(False) for trade in trades)
        entry["net_cash_mean_half"] = statistics.fmean(trade.cash_result(True) for trade in trades)
        entry["all_in_cost_r_mean"] = statistics.fmean(
            _all_in_cost_r(trade.row) + trade.extra_cost_r for trade in trades
        )
    else:
        entry["net_cash_total_full"] = 0.0
        entry["net_cash_total_half"] = 0.0
        entry["net_cash_mean_full"] = None
        entry["net_cash_mean_half"] = None
        entry["all_in_cost_r_mean"] = None

    if qualifying_cash is not None and fills:
        full_results = [trade.cash_result(False) for trade in trades]
        small = sum(0.0 < value < qualifying_cash for value in full_results)
        qualifying = sum(value >= qualifying_cash for value in full_results)
        entry["small_positive_wins_full"] = small
        entry["qualifying_wins_full"] = qualifying
        entry["sub_qualifying_share_full"] = small / fills
    else:
        entry["small_positive_wins_full"] = None
        entry["qualifying_wins_full"] = None
        entry["sub_qualifying_share_full"] = None

    if config_risk_fractions and initial_balance and fills:
        # Utilization is measured against the V2 section 6 all-in ceiling:
        # per lot, the all-in loss = pure stop risk * (1 + commission_r +
        # stop-side slippage_r/2).  The rows report the broker-visible stop
        # risk only, so the fee share is reconstructed from the R components.
        utilizations = []
        for trade in trades:
            fraction = float(config_risk_fractions[trade.row.config_id])
            if fraction > 0.0:
                row = trade.row
                all_in_factor = 1.0 + row.commission_r + row.slippage_r / 2.0
                utilizations.append(
                    row.risk_cash_full * all_in_factor
                    / (initial_balance * fraction)
                )
        if utilizations:
            ordered = sorted(utilizations)
            entry["executed_risk_fraction_mean"] = statistics.fmean(ordered)
            entry["executed_risk_fraction_p10"] = _percentile(ordered, 0.10)
            entry["budget_underuse_fills"] = sum(value < 0.90 for value in ordered)
            entry["budget_underuse_share"] = sum(value < 0.90 for value in ordered) / len(ordered)
        else:
            entry["executed_risk_fraction_mean"] = None
            entry["executed_risk_fraction_p10"] = None
            entry["budget_underuse_fills"] = None
            entry["budget_underuse_share"] = None
    else:
        entry["executed_risk_fraction_mean"] = None
        entry["executed_risk_fraction_p10"] = None
        entry["budget_underuse_fills"] = None
        entry["budget_underuse_share"] = None

    entry.update(_year_net_report(trades))


def metric_report(rows: Sequence[ReplayRow], policy: FillPolicy, *, stressed: bool,
                  seed: int,
                  config_risk_fractions: Mapping[str, float] | None = None,
                  initial_balance: float | None = None,
                  qualifying_cash: float | None = None) -> dict[str, object]:
    trades = [
        trade
        for row in rows
        if (trade := apply_fill_policy(row, policy, stressed=stressed, seed=seed)) is not None
    ]
    values = [trade.net_r for trade in trades]
    per_combination: dict[str, object] = {}
    for combination in sorted(ALLOWED_COMBINATIONS):
        combination_rows = [row for row in rows if row.combination == combination]
        combination_trades = [trade for trade in trades if trade.row.combination == combination]
        combination_values = [trade.net_r for trade in combination_trades]
        combination_report: dict[str, object] = {
            "fills": len(combination_values),
            "expectancy_r": statistics.fmean(combination_values) if combination_values else None,
            "profit_factor": _json_number(_profit_factor(combination_values)),
        }
        _augment_metric_report(
            combination_report,
            combination_rows,
            combination_trades,
            policy,
            config_risk_fractions=config_risk_fractions,
            initial_balance=initial_balance,
            qualifying_cash=qualifying_cash,
        )
        per_combination[combination] = combination_report
    report: dict[str, object] = {
        "fills": len(values),
        "expectancy_r": statistics.fmean(values) if values else None,
        "profit_factor": _json_number(_profit_factor(values)),
        "wins": sum(value > 0 for value in values),
        "losses": sum(value < 0 for value in values),
        "scratches": sum(value == 0 for value in values),
        "per_combination": per_combination,
        "rule_violations": sum(row.rule_violation for row in rows),
        "operational_errors": sum(row.operational_error for row in rows),
        "touch_without_trade_through": sum(
            row.candidate
            and row.activation_ok
            and row.limit_touched
            and row.trade_through_ticks < policy.minimum_trade_through_ticks
            for row in rows
        ),
        "partial_fill_observations": sum(
            row.candidate and 0 < row.fill_fraction < policy.minimum_fill_fraction
            for row in rows
        ),
    }
    _augment_metric_report(
        report,
        rows,
        trades,
        policy,
        config_risk_fractions=config_risk_fractions,
        initial_balance=initial_balance,
        qualifying_cash=qualifying_cash,
    )
    return report


def _numeric_profit_factor(report: Mapping[str, object]) -> float:
    value = report["profit_factor"]
    if value == "Infinity":
        return math.inf
    if value is None:
        return 0.0
    return float(value)


def independently_eligible_combinations(
    diagnostics: Mapping[str, object], thresholds: ValidationThresholds
) -> tuple[tuple[str, ...], dict[str, list[str]]]:
    per_combination = diagnostics["per_combination"]
    assert isinstance(per_combination, dict)
    eligible: list[str] = []
    rejected: dict[str, list[str]] = {}
    for combination in sorted(ALLOWED_COMBINATIONS):
        report = per_combination[combination]
        assert isinstance(report, dict)
        failures: list[str] = []
        if int(report["fills"]) < thresholds.minimum_combination_fills:
            failures.append("fill_count")
        expectancy = report["expectancy_r"]
        if expectancy is None or float(expectancy) <= thresholds.minimum_combination_expectancy_r:
            failures.append("expectancy")
        profit_factor = report["profit_factor"]
        numeric_pf = (
            math.inf
            if profit_factor == "Infinity"
            else (0.0 if profit_factor is None else float(profit_factor))
        )
        if numeric_pf < thresholds.minimum_combination_profit_factor:
            failures.append("profit_factor")
        if failures:
            rejected[combination] = failures
        else:
            eligible.append(combination)
    return tuple(eligible), rejected


# Stable session index used as the final router tie-break (V2 section 12:
# "stable session index").  Priorities default to 1 for every combination,
# matching the EA inputs (InpEURUSDLondonPriority=1, InpGBPUSDLondonPriority=1,
# InpUSDJPYNewYorkPriority=1): ties are allowed and resolve by lower all-in
# cost/R, earlier completed signal (sequence), then stable session index.
COMBINATION_ORDER = (
    "EURUSD_LONDON",
    "GBPUSD_LONDON",
    "USDJPY_NEW_YORK",
)
DEFAULT_COMBINATION_PRIORITIES: dict[str, int] = {
    name: 1 for name in COMBINATION_ORDER
}


def parse_combination_priorities(text: str) -> dict[str, int]:
    """Parse ``EURUSD_LONDON:1,GBPUSD_LONDON:2,USDJPY_NEW_YORK:3``.

    Values must cover at most the three declared combinations, each exactly
    once, with integer priorities in 1..3.  Omitted combinations default to 1
    (the EA default), which the caller records in the report as evidence of
    the predeclared routing rule actually used.
    """
    parsed = dict(DEFAULT_COMBINATION_PRIORITIES)
    if not text.strip():
        return parsed
    for token in text.split(","):
        token = token.strip()
        if not token:
            continue
        if ":" not in token:
            raise ValidationError(f"invalid priority token: {token}")
        name, raw_value = token.split(":", 1)
        name = name.strip().upper()
        if name not in COMBINATION_ORDER:
            raise ValidationError(f"unknown combination in priorities: {name}")
        try:
            value = int(raw_value.strip())
        except ValueError as exc:
            raise ValidationError(f"invalid priority value for {name}") from exc
        if not 1 <= value <= 3:
            raise ValidationError(f"priority for {name} must be in 1..3")
        parsed[name] = value
    return parsed


def _router_key(row: ReplayRow, priorities: Mapping[str, int]) -> tuple[int, float, int, str]:
    cost = _all_in_cost_r(row)
    session_index = COMBINATION_ORDER.index(row.combination)
    return (int(priorities.get(row.combination, 1)), cost, row.sequence, session_index)


def route_daily_rows(rows: Sequence[ReplayRow],
                     priorities: Mapping[str, int] | None = None) -> tuple[list[ReplayRow], dict[str, object]]:
    """Apply the V2 section-12 account-wide candidate router.

    Per frozen configuration and server day, every candidate that passed the
    mandatory gates (``candidate`` and ``activation_ok``) is ranked by the
    frozen combination priority, then lower all-in cost/R, then earlier
    completed signal, then stable session index.  Exactly one candidate wins
    each day.  All other candidate rows are *demoted* (activation_ok=false and
    fill fields zeroed) rather than deleted, so the export keeps the coverage
    the validator requires — one row per configuration/combination/day — while
    the audit trail still shows which signals one-position routing discarded.

    Days with no candidate (or no activated candidate) are returned unchanged:
    their explicit no-candidate rows remain for coverage checks.
    """
    effective = dict(DEFAULT_COMBINATION_PRIORITIES)
    if priorities:
        effective.update(priorities)
    grouped: dict[tuple[str, str, date], list[ReplayRow]] = defaultdict(list)
    for row in rows:
        grouped[(row.config_id, row.split, row.server_day)].append(row)
    routed: list[ReplayRow] = []
    rejected: dict[str, int] = defaultdict(int)
    gate_failed: int = 0
    ties: dict[str, int] = defaultdict(int)
    winner_count = 0
    for key in sorted(grouped):
        day_rows = grouped[key]
        activated_candidates = [
            row for row in day_rows if row.candidate and row.activation_ok
        ]
        if not activated_candidates:
            routed.extend(day_rows)
            continue
        ranked = sorted(activated_candidates, key=lambda row: _router_key(row, effective))
        winner = ranked[0]
        winners = [
            row
            for row in activated_candidates
            if _router_key(row, effective)[:2] == _router_key(winner, effective)[:2]
        ]
        ties_without_winner = len(winners) - 1
        if ties_without_winner > 0:
            ties[key[0]] += ties_without_winner
        for row in day_rows:
            if row is winner:
                winner_count += 1
                routed.append(row)
            elif row.candidate and row.activation_ok:
                rejected[f"{row.combination}->{winner.combination}"] += 1
                routed.append(_demoted(row))
            elif row.candidate:
                # Failed-gate candidates were dropped before ranking
                # (section 12 step 1); they are audited, not routed.
                gate_failed += 1
                routed.append(row)
            else:
                routed.append(row)
    diagnostics: dict[str, object] = {
        "priorities_used": dict(effective),
        "combined_priority_tie_break_rule": (
            "priority, lower all-in cost/R, earlier sequence, stable session index"
        ),
        "rejected_candidate_counts": dict(sorted(rejected.items())),
        "gate_failed_candidates_excluded_from_ranking": gate_failed,
        "priority_tie_event_counts": dict(sorted(ties.items())),
        "routed_rows": len(routed),
        "input_rows": len(rows),
        "winner_rows": winner_count,
        "routed_from_input_rows": len(rows) - winner_count,
    }
    return routed, diagnostics


def _demoted(row: ReplayRow) -> ReplayRow:
    """Copy a candidate row with order/risk fields zeroed (router rejection)."""
    return replace(
        row,
        activation_ok=False,
        limit_touched=False,
        trade_through_ticks=0,
        fill_fraction=0.0,
        net_r=0.0,
        risk_cash_full=0.0,
        risk_cash_half=0.0,
        net_cash_full=0.0,
        net_cash_half=0.0,
        mae_cash_full=0.0,
        mae_cash_half=0.0,
        spread_r=0.0,
        slippage_r=0.0,
        commission_r=0.0,
    )


def gates_pass(normal: Mapping[str, object], stressed: Mapping[str, object],
               thresholds: ValidationThresholds,
               combinations: Sequence[str] = tuple(sorted(ALLOWED_COMBINATIONS))) -> tuple[bool, list[str]]:
    failures: list[str] = []
    if not combinations:
        failures.append("no_independently_eligible_combination")
    if int(normal["rule_violations"]) != 0:
        failures.append("rule_violations")
    if int(normal["operational_errors"]) != 0:
        failures.append("operational_errors")
    if int(normal["fills"]) < thresholds.minimum_aggregate_fills:
        failures.append("aggregate_fill_count")
    expectancy = normal["expectancy_r"]
    if expectancy is None or float(expectancy) < thresholds.minimum_aggregate_expectancy_r:
        failures.append("aggregate_expectancy")
    if _numeric_profit_factor(normal) < thresholds.minimum_aggregate_profit_factor:
        failures.append("aggregate_profit_factor")
    per_combination = normal["per_combination"]
    assert isinstance(per_combination, dict)
    for combination in sorted(combinations):
        if combination not in ALLOWED_COMBINATIONS:
            failures.append(f"unknown_enabled_combination:{combination}")
            continue
        report = per_combination[combination]
        assert isinstance(report, dict)
        if int(report["fills"]) < thresholds.minimum_combination_fills:
            failures.append(f"{combination}:fill_count")
        value = report["expectancy_r"]
        if value is None or float(value) <= thresholds.minimum_combination_expectancy_r:
            failures.append(f"{combination}:expectancy")
        pf = report["profit_factor"]
        numeric_pf = math.inf if pf == "Infinity" else (0.0 if pf is None else float(pf))
        if numeric_pf < thresholds.minimum_combination_profit_factor:
            failures.append(f"{combination}:profit_factor")
    stress_expectancy = stressed["expectancy_r"]
    if stress_expectancy is None or float(stress_expectancy) <= thresholds.minimum_stressed_expectancy_r:
        failures.append("stressed_expectancy")
    if _numeric_profit_factor(stressed) < thresholds.minimum_stressed_profit_factor:
        failures.append("stressed_profit_factor")
    return not failures, failures


def _trades_by_day(rows: Sequence[ReplayRow], policy: FillPolicy, *, stressed: bool,
                   seed: int) -> list[tuple[date, list[AppliedTrade]]]:
    calendar_days = sorted({row.server_day for row in rows})
    grouped: dict[date, list[AppliedTrade]] = defaultdict(list)
    for row in rows:
        trade = apply_fill_policy(row, policy, stressed=stressed, seed=seed)
        if trade is not None:
            grouped[row.server_day].append(trade)
    return [
        (day, sorted(grouped[day], key=lambda item: (item.row.sequence, item.row.event_id)))
        for day in calendar_days
    ]


def _moving_block_days(days: Sequence[tuple[date, list[AppliedTrade]]], rng: random.Random,
                       block_days: int) -> Iterator[list[AppliedTrade]]:
    if not days:
        raise ValidationError("cannot simulate phases without calendar days")
    index = 0
    remaining = 0
    while True:
        if remaining == 0:
            index = rng.randrange(len(days))
            remaining = max(1, block_days)
        yield days[index][1]
        index = (index + 1) % len(days)
        remaining -= 1


@dataclass(frozen=True)
class PhaseOutcome:
    passed: bool
    reason: str
    calendar_days: int
    maximum_drawdown_fraction: float
    qualifying_days: int
    days_in_drawdown: int = 0


def simulate_phase(days: Sequence[tuple[date, list[AppliedTrade]]], *, phase_target_fraction: float,
                   settings: SimulationSettings, rng: random.Random) -> PhaseOutcome:
    initial = settings.initial_balance
    balance = initial
    high_water = initial
    max_drawdown = 0.0
    qualifying_days = 0
    inactive_days = 0
    days_in_drawdown = 0
    weekly_start = initial
    sampled = _moving_block_days(days, rng, settings.block_days)
    target = initial * (1.0 + phase_target_fraction)
    qualifying_cash = initial * settings.qualifying_day_fraction

    def outcome(passed: bool, reason: str, day_number: int,
                drawdown: float) -> PhaseOutcome:
        # The terminating day counts as a drawdown day when the account was
        # below its high-water mark at termination, including the interim
        # adverse-excursion check inside the trade loop.
        counted = days_in_drawdown + (1 if drawdown > 1e-12 else 0)
        return PhaseOutcome(
            passed,
            reason,
            day_number,
            max_drawdown,
            qualifying_days,
            counted,
        )

    for day_number in range(1, settings.max_phase_calendar_days + 1):
        if (day_number - 1) % 7 == 0:
            weekly_start = balance
        day_start = balance
        day_net = 0.0
        completed = 0
        filled_today = False
        target_reached = False
        weekly_locked = balance <= weekly_start - initial * settings.weekly_stop_fraction

        for trade in next(sampled):
            if weekly_locked or completed >= 2 or (completed == 1 and day_net > 0):
                break
            drawdown = max(0.0, (high_water - balance) / high_water)
            if drawdown >= settings.drawdown_shutdown_fraction:
                return outcome(False, "strategy_drawdown_shutdown", day_number, drawdown)
            half_risk = drawdown >= settings.drawdown_reduce_fraction
            adverse = trade.adverse_cash(half_risk)
            interim_equity = balance - adverse
            interim_drawdown = max(0.0, (high_water - interim_equity) / high_water)
            max_drawdown = max(max_drawdown, interim_drawdown)
            if interim_drawdown >= settings.drawdown_shutdown_fraction:
                return outcome(False, "strategy_drawdown_shutdown", day_number, interim_drawdown)

            result = trade.cash_result(half_risk)
            balance += result
            day_net += result
            completed += 1
            filled_today = True
            high_water = max(high_water, balance)
            max_drawdown = max(max_drawdown, max(0.0, (high_water - balance) / high_water))
            if balance >= target:
                target_reached = True
                break
            if balance <= day_start - initial * settings.daily_stop_fraction:
                break
            if balance <= weekly_start - initial * settings.weekly_stop_fraction:
                weekly_locked = True
                break

        inactive_days = 0 if filled_today else inactive_days + 1
        if inactive_days >= settings.inactivity_days:
            return outcome(False, "inactivity", day_number, max(0.0, (high_water - balance) / high_water))
        if day_net >= qualifying_cash:
            qualifying_days += 1
        drawdown = max(0.0, (high_water - balance) / high_water)
        max_drawdown = max(max_drawdown, drawdown)
        if target_reached:
            passed = qualifying_days >= settings.required_qualifying_days
            reason = "passed" if passed else "target_pending_days"
            return outcome(passed, reason, day_number, drawdown)
        if drawdown >= settings.drawdown_shutdown_fraction:
            return outcome(False, "strategy_drawdown_shutdown", day_number, drawdown)
        if drawdown > 1e-12:
            days_in_drawdown += 1

    return PhaseOutcome(
        False,
        "maximum_duration",
        settings.max_phase_calendar_days,
        max_drawdown,
        qualifying_days,
        days_in_drawdown,
    )


def _percentile(values: Sequence[float], probability: float) -> float | None:
    if not values:
        return None
    probability = min(1.0, max(0.0, probability))
    ordered = sorted(values)
    index = probability * (len(ordered) - 1)
    low = math.floor(index)
    high = math.ceil(index)
    if low == high:
        return ordered[low]
    fraction = index - low
    return ordered[low] * (1.0 - fraction) + ordered[high] * fraction


def _binom_wilson_sided(p: float, n: int, z: float) -> tuple[float, float]:
    """Wilson score interval; returns the two-sided [lower, upper] bounds.

    Section 13 requires the joint two-phase pass probability to be "reported
    with confidence bounds".  For n <= 0 the interval is reported as
    [None, None] rather than inventing a value.
    """
    if n <= 0:
        return (float("nan"), float("nan"))
    centre = p + z * z / (2.0 * n)
    radius = z * math.sqrt(p * (1.0 - p) / n + z * z / (4.0 * n * n))
    scale = 1.0 / (1.0 + z * z / n)
    return (max(0.0, scale * (centre - radius)), min(1.0, scale * (centre + radius)))


def _binomial_wilson_interval(successes: int, trials: int,
                              confidence_level: float) -> dict[str, object]:
    proba = successes / trials if trials > 0 else 0.0
    if not 0.0 < confidence_level < 1.0:
        raise ValidationError("confidence level must lie strictly between 0 and 1")
    z = statistics.NormalDist().inv_cdf(1.0 - (1.0 - confidence_level) / 2.0)
    lower, upper = _binom_wilson_sided(proba, trials, z)
    finite = math.isfinite(lower) and math.isfinite(upper)
    return {
        "method": "Wilson score interval (normal approximation, no continuity correction)",
        "confidence_level": confidence_level,
        "successes": successes,
        "trials": trials,
        "lower": lower if finite else None,
        "upper": upper if finite else None,
    }


def phase_simulation_report(rows: Sequence[ReplayRow], policy: FillPolicy, *, stressed: bool,
                            paths: int, settings: SimulationSettings, seed: int) -> dict[str, object]:
    if paths <= 0:
        raise ValidationError("phase simulation requires at least one path")
    days = _trades_by_day(rows, policy, stressed=stressed, seed=seed)
    rng = random.Random(seed)
    phase1_outcomes: list[PhaseOutcome] = []
    phase2_outcomes: list[PhaseOutcome] = []
    joint_passes = 0
    joint_draws: dict[str, int] = defaultdict(int)
    joint_days_passed: list[float] = []
    joint_days_all: list[float] = []
    time_in_drawdown_values: list[float] = []
    reasons1: dict[str, int] = defaultdict(int)
    reasons2: dict[str, int] = defaultdict(int)
    for _ in range(paths):
        phase1 = simulate_phase(
            days,
            phase_target_fraction=settings.phase1_target_fraction,
            settings=settings,
            rng=rng,
        )
        phase2 = simulate_phase(
            days,
            phase_target_fraction=settings.phase2_target_fraction,
            settings=settings,
            rng=rng,
        )
        phase1_outcomes.append(phase1)
        phase2_outcomes.append(phase2)
        reasons1[phase1.reason] += 1
        reasons2[phase2.reason] += 1
        total_days = float(phase1.calendar_days + phase2.calendar_days)
        joint_days_all.append(total_days)
        if phase1.passed and phase2.passed:
            joint_passes += 1
            joint_days_passed.append(total_days)
            joint_draws["joint_pass"] += 1
        elif phase1.passed:
            joint_draws["phase2_failure"] += 1
        elif phase2.passed:
            joint_draws["phase1_failure"] += 1
        else:
            joint_draws["both_failure"] += 1
        time_in_drawdown_values.append(
            float(phase1.days_in_drawdown + phase2.days_in_drawdown)
        )
    drawdowns = [
        max(phase1.maximum_drawdown_fraction, phase2.maximum_drawdown_fraction)
        for phase1, phase2 in zip(phase1_outcomes, phase2_outcomes)
    ]
    joint_confidence = _binomial_wilson_interval(joint_passes, paths, SPEC_SEC13_CONFIDENCE_LEVEL)
    phase1_target_arrivals = sum(
        item.reason in {"passed", "target_pending_days"} for item in phase1_outcomes
    )
    phase2_target_arrivals = sum(
        item.reason in {"passed", "target_pending_days"} for item in phase2_outcomes
    )
    phase1_passes = sum(item.passed for item in phase1_outcomes)
    phase2_passes = sum(item.passed for item in phase2_outcomes)
    return {
        "paths": paths,
        "phase_target_definition": (
            "phase targets are fractions of the $2,500 phase initial balance "
            "(V2 objectives: +10% Phase 1, +5% Phase 2; the external rule set "
            "ambiguity about the Phase-2 base remains a written-support item)"
        ),
        "phase1_pass_probability": phase1_passes / paths,
        "phase2_pass_probability": phase2_passes / paths,
        "joint_pass_probability": joint_passes / paths,
        "joint_confidence": joint_confidence,
        "joint_draws": dict(sorted(joint_draws.items())),
        "phase1_target_arrival_probability": phase1_target_arrivals / paths,
        "phase2_target_arrival_probability": phase2_target_arrivals / paths,
        "phase1_qualifying_days_by_target_probability": (
            phase1_passes / phase1_target_arrivals if phase1_target_arrivals else 0.0
        ),
        "phase2_qualifying_days_by_target_probability": (
            phase2_passes / phase2_target_arrivals if phase2_target_arrivals else 0.0
        ),
        "maximum_drawdown_p95_fraction": _percentile(drawdowns, 0.95),
        "maximum_drawdown_p99_fraction": _percentile(drawdowns, 0.99),
        "maximum_drawdown_p50_fraction": _percentile(drawdowns, 0.50),
        "median_joint_completion_calendar_days": (
            statistics.median(joint_days_passed) if joint_days_passed else None
        ),
        "median_joint_calendar_days_all_paths": statistics.median(joint_days_all),
        "median_time_in_drawdown_days": (
            statistics.median(time_in_drawdown_values) if time_in_drawdown_values else None
        ),
        "phase1_outcomes": dict(sorted(reasons1.items())),
        "phase2_outcomes": dict(sorted(reasons2.items())),
    }


def phase_gates_pass(
    report: Mapping[str, object], thresholds: ValidationThresholds
) -> tuple[bool, list[str]]:
    failures: list[str] = []
    checks = (
        (
            "phase1_pass_probability",
            thresholds.minimum_phase1_pass_probability,
        ),
        (
            "phase2_pass_probability",
            thresholds.minimum_phase2_pass_probability,
        ),
        (
            "joint_pass_probability",
            thresholds.minimum_joint_pass_probability,
        ),
        (
            "phase1_qualifying_days_by_target_probability",
            thresholds.minimum_qualifying_days_by_target_probability,
        ),
        (
            "phase2_qualifying_days_by_target_probability",
            thresholds.minimum_qualifying_days_by_target_probability,
        ),
    )
    for field, minimum in checks:
        if float(report[field]) < minimum:
            failures.append(field)
    drawdown = report["maximum_drawdown_p99_fraction"]
    if drawdown is None or float(drawdown) > thresholds.maximum_p99_drawdown_fraction:
        failures.append("maximum_drawdown_p99_fraction")
    return not failures, failures


def sec13_phase_checks(report: Mapping[str, object],
                       settings: SimulationSettings) -> dict[str, object]:
    """Section-13 report-level checks that the frozen phase gates do not cover.

    ``settings`` is currently accepted for forward compatibility (floor/overshoot
    checks use the same simulation shape); the returned dict contains the items
    that belong on a phase-simulation report: confidence bounds, median
    drawdown, and time in drawdown.
    """
    joint_confidence = report["joint_confidence"]
    assert isinstance(joint_confidence, dict)
    lower = joint_confidence["lower"]
    confidence_lower_positive = lower is not None and float(lower) > 0.0
    return {
        "method": joint_confidence.get("method", "Wilson score interval"),
        "confidence_level": joint_confidence.get("confidence_level", SPEC_SEC13_CONFIDENCE_LEVEL),
        "joint_confidence_lower_positive_95": confidence_lower_positive,
        "joint_confidence_lower": lower,
        "joint_confidence_upper": joint_confidence["upper"],
        "maximum_drawdown_p50_fraction": report.get("maximum_drawdown_p50_fraction"),
        "median_time_in_drawdown_days": report.get("median_time_in_drawdown_days"),
        "progress_days_used": settings.max_phase_calendar_days > 0,
    }


def _simulate_floor_path(days: Sequence[tuple[date, list[AppliedTrade]]], *,
                         settings: SimulationSettings, rng: random.Random) -> tuple[bool, float]:
    """One block-bootstrap account path for the Section-13 floor checks.

    Tracks, per path:

    - whether the deterministic worst-case equity ever falls below the firm
      10% overall floor (``phase_initial_balance * 0.90``);
    - the deepest excursion *beyond* the internal 5% shutdown boundary
      (measured from the strategy high-water mark, as in the phase simulator),
      as a fraction of the phase initial balance.

    The path consumes trades under the same day-lock/two-trade rules as
    :func:`simulate_phase`; the difference is that it does not stop at the 5%
    boundary, because the boundary itself is what Section 13 asks us to
    quantify (overshoot) and the firm floor is what it asks us to test.
    """
    initial = settings.initial_balance
    overall_floor = initial * SPEC_SEC13_FIRM_OVERALL_FLOOR_FRACTION
    target = initial * (1.0 + settings.phase1_target_fraction)
    balance = initial
    high_water = initial
    floor_breached = False
    max_overshoot = 0.0
    sampled = _moving_block_days(days, rng, settings.block_days)
    for day_number in range(1, settings.max_phase_calendar_days + 1):
        if (day_number - 1) % 7 == 0:
            weekly_start = balance
        day_start = balance
        day_net = 0.0
        completed = 0
        daily_lock = False
        weekly_locked = balance <= weekly_start - initial * settings.weekly_stop_fraction

        def shutdown_level() -> float:
            return high_water - initial * settings.drawdown_shutdown_fraction

        def observe(equity: float) -> None:
            nonlocal floor_breached, max_overshoot
            floor_breached = floor_breached or equity < overall_floor
            max_overshoot = max(max_overshoot, max(0.0, (shutdown_level() - equity) / initial))

        for trade in next(sampled):
            if weekly_locked or completed >= 2 or (completed == 1 and day_net > 0) or daily_lock:
                break
            drawdown = max(0.0, (high_water - balance) / high_water)
            half_risk = drawdown >= settings.drawdown_reduce_fraction
            adverse = trade.adverse_cash(half_risk)
            observe(balance - adverse)
            result = trade.cash_result(half_risk)
            balance += result
            day_net += result
            completed += 1
            high_water = max(high_water, balance)
            observe(balance)
            if balance >= target:
                daily_lock = True
                break
            if balance <= day_start - initial * settings.daily_stop_fraction:
                break
            if balance <= weekly_start - initial * settings.weekly_stop_fraction:
                weekly_locked = True
                break
    return floor_breached, max_overshoot


def firm_floor_check(rows: Sequence[ReplayRow], policy: FillPolicy, *,
                     stressed: bool, seed: int,
                     settings: SimulationSettings) -> dict[str, object]:
    """Block-bootstrap Section-13 account-floor and overshoot check.

    ``paths`` comes from the module-level Section-13 constant so that the
    frozen registry payload (and its mutation-protecting hash) is not changed
    by this report-only extension.  The deterministic seed is derived from the
    caller's seed plus a fixed offset.
    """
    days = _trades_by_day(rows, policy, stressed=stressed, seed=seed)
    if not days:
        return {
            "paths": 0,
            "firm_overall_floor_breached": False,
            "maximum_overshoot_beyond_shutdown_p99_fraction": 0.0,
        }
    rng = random.Random(seed ^ 0xF10F10F1)
    breaches = 0
    overshoots: list[float] = []
    for _ in range(SPEC_SEC13_FLOOR_CHECK_PATHS):
        breached, overshoot = _simulate_floor_path(days, settings=settings, rng=rng)
        breaches += 1 if breached else 0
        overshoots.append(overshoot)
    return {
        "paths": SPEC_SEC13_FLOOR_CHECK_PATHS,
        "firm_overall_floor_breach_paths": breaches,
        "firm_overall_floor_breach_rate": breaches / SPEC_SEC13_FLOOR_CHECK_PATHS,
        "firm_overall_floor_breached": breaches > 0,
        "maximum_overshoot_beyond_shutdown_p99_fraction": _percentile(overshoots, 0.99),
        "maximum_overshoot_beyond_shutdown_ok_p99": (
            float(_percentile(overshoots, 0.99) or 0.0)
            <= SPEC_SEC13_MAX_SHUTDOWN_OVERSHOOT_P99
        ),
    }


def sec13_verdict(normal: Mapping[str, object], stressed: Mapping[str, object],
                  normal_phase: Mapping[str, object], stressed_phase: Mapping[str, object],
                  normal_floor: Mapping[str, object], stressed_floor: Mapping[str, object],
                  thresholds: ValidationThresholds) -> dict[str, object]:
    """Combine frozen-point gates with the Section-13 checklist into a verdict.

    This is the report consumers should read first.  It never changes the
    frozen gates themselves; it makes the release gates deployable-truthful by
    surfacing the requirements the registry does not encode (confidence
    bounds, year robustness, firm floor, stress overshoot).  ``sec13_phase_checks``
    covers the report-level items; this function owns the combined verdict.
    """
    normal_checks = sec13_phase_checks(normal_phase, SimulationSettings())
    checks = (
        ("rule_violations", int(normal["rule_violations"]) == 0),
        ("operational_errors", int(normal["operational_errors"]) == 0),
        ("aggregate_fill_count", int(normal["fills"]) >= thresholds.minimum_aggregate_fills),
        (
            "aggregate_expectancy",
            normal["expectancy_r"] is not None
            and float(normal["expectancy_r"]) >= thresholds.minimum_aggregate_expectancy_r,
        ),
        (
            "aggregate_profit_factor",
            float(_numeric_profit_factor(normal)) >= thresholds.minimum_aggregate_profit_factor,
        ),
        (
            "stressed_expectancy",
            stressed["expectancy_r"] is not None
            and float(stressed["expectancy_r"]) >= thresholds.minimum_stressed_expectancy_r,
        ),
        ("year_robustness", bool(normal.get("year_robustness_ok", False))),
        (
            "firm_overall_floor",
            not bool(normal_floor.get("firm_overall_floor_breached", False)),
        ),
        (
            "joint_confidence_95_lower_positive",
            bool(normal_checks["joint_confidence_lower_positive_95"]),
        ),
        (
            "phase1_pass_probability",
            float(normal_phase["phase1_pass_probability"]) >= thresholds.minimum_phase1_pass_probability,
        ),
        (
            "phase2_pass_probability",
            float(normal_phase["phase2_pass_probability"]) >= thresholds.minimum_phase2_pass_probability,
        ),
        (
            "joint_pass_probability",
            float(normal_phase["joint_pass_probability"]) >= thresholds.minimum_joint_pass_probability,
        ),
        (
            "maximum_p99_drawdown",
            normal_phase["maximum_drawdown_p99_fraction"] is not None
            and float(normal_phase["maximum_drawdown_p99_fraction"])
            <= thresholds.maximum_p99_drawdown_fraction,
        ),
        (
            "stress_phase1_pass_probability",
            float(stressed_phase["phase1_pass_probability"]) >= thresholds.minimum_phase1_pass_probability,
        ),
        (
            "stress_phase2_pass_probability",
            float(stressed_phase["phase2_pass_probability"]) >= thresholds.minimum_phase2_pass_probability,
        ),
        (
            "stress_joint_pass_probability",
            float(stressed_phase["joint_pass_probability"]) >= thresholds.minimum_joint_pass_probability,
        ),
        (
            "stress_overshoot_p99",
            bool(stressed_floor.get("maximum_overshoot_beyond_shutdown_ok_p99", False)),
        ),
    )
    failures = [name for name, passed in checks if not passed]
    return {
        "all_sec13_checks_pass": not failures,
        "failed_checks": failures,
        "checked_checks": [name for name, _ in checks],
    }


def _daily_r_values(rows: Sequence[ReplayRow], policy: FillPolicy, *, stressed: bool,
                    seed: int) -> list[list[float]]:
    days = _trades_by_day(rows, policy, stressed=stressed, seed=seed)
    return [[trade.net_r for trade in trades] for _, trades in days]


def bootstrap_expectancy_interval(rows: Sequence[ReplayRow], policy: FillPolicy, *,
                                  stressed: bool, samples: int, block_days: int,
                                  alpha: float, family_size: int, seed: int) -> dict[str, object]:
    if samples <= 0 or family_size <= 0 or not 0 < alpha < 1:
        raise ValidationError("invalid bootstrap settings")
    daily_values = _daily_r_values(rows, policy, stressed=stressed, seed=seed)
    observed = [value for day in daily_values for value in day]
    if not observed:
        return {
            "observed_expectancy_r": None,
            "ordinary_interval": [None, None],
            "familywise_adjusted_interval": [None, None],
            "family_size": family_size,
            "requested_samples": samples,
            "usable_samples": 0,
        }
    rng = random.Random(seed)
    means: list[float] = []
    day_count = len(daily_values)
    for _ in range(samples):
        sampled: list[float] = []
        sampled_days = 0
        while sampled_days < day_count:
            start = rng.randrange(day_count)
            take = min(max(1, block_days), day_count - sampled_days)
            for offset in range(take):
                sampled.extend(daily_values[(start + offset) % day_count])
            sampled_days += take
        # A sparse strategy can occasionally bootstrap an all-no-trade window.
        # Such a draw has no per-trade expectancy and is excluded explicitly;
        # the number of usable replicates remains visible in the report.
        if sampled:
            means.append(statistics.fmean(sampled))
    if not means:
        raise ValidationError("every bootstrap replicate contained zero fills")
    ordinary_tail = alpha / 2.0
    adjusted_tail = alpha / (2.0 * family_size)
    return {
        "observed_expectancy_r": statistics.fmean(observed),
        "ordinary_interval": [
            _percentile(means, ordinary_tail),
            _percentile(means, 1.0 - ordinary_tail),
        ],
        "familywise_adjusted_interval": [
            _percentile(means, adjusted_tail),
            _percentile(means, 1.0 - adjusted_tail),
        ],
        "method": "moving-calendar-day block bootstrap with Bonferroni familywise adjustment",
        "family_size": family_size,
        "familywise_alpha": alpha,
        "requested_samples": samples,
        "usable_samples": len(means),
        "block_days": block_days,
    }


def _config_rows(rows: Sequence[ReplayRow], config_id: str, split: str) -> list[ReplayRow]:
    return [row for row in rows if row.config_id == config_id and row.split == split]


def select_champion(selection_rows: Sequence[ReplayRow], configs: Sequence[CandidateConfig],
                    policy: FillPolicy, thresholds: ValidationThresholds,
                    settings: SimulationSettings,
                    combination_priorities: Mapping[str, int] | None = None,
                    ) -> tuple[CandidateConfig | None, dict[str, object]]:
    if any(row.split == HOLDOUT_SPLIT for row in selection_rows):
        raise ValidationError("holdout rows were supplied to champion selection")
    ranked: list[tuple[tuple[float, float, float, str], CandidateConfig, dict[str, object]]] = []
    rejected: dict[str, list[str]] = {}
    config_seed_base = settings.random_seed
    for config in configs:
        rows = [row for row in selection_rows if row.config_id == config.config_id]
        if not rows:
            rejected[config.config_id] = ["missing_selection_rows"]
            continue
        seed = config_seed_base ^ int(hashlib.sha256(config.config_id.encode()).hexdigest()[:8], 16)
        all_combination_diagnostics = metric_report(
            rows, policy, stressed=False, seed=settings.random_seed
        )
        if (
            int(all_combination_diagnostics["rule_violations"]) != 0
            or int(all_combination_diagnostics["operational_errors"]) != 0
        ):
            rejected[config.config_id] = ["rule_or_operational_error"]
            continue
        enabled_combinations, combination_rejections = independently_eligible_combinations(
            all_combination_diagnostics, thresholds
        )
        portfolio_rows = [
            row for row in rows if row.combination in enabled_combinations
        ]
        routed_rows, router_diagnostics = route_daily_rows(
            portfolio_rows, combination_priorities
        )
        normal = metric_report(
            routed_rows, policy, stressed=False, seed=settings.random_seed
        )
        stressed = metric_report(
            routed_rows, policy, stressed=True, seed=settings.random_seed
        )
        passed, failures = gates_pass(
            normal, stressed, thresholds, enabled_combinations
        )
        if not passed:
            rejected[config.config_id] = failures
            continue
        phase = phase_simulation_report(
            routed_rows,
            policy,
            stressed=False,
            paths=settings.selection_paths,
            settings=settings,
            seed=seed,
        )
        phase_passed, phase_failures = phase_gates_pass(phase, thresholds)
        if not phase_passed:
            rejected[config.config_id] = [
                f"phase:{failure}" for failure in phase_failures
            ]
            continue
        joint = float(phase["joint_pass_probability"])
        drawdown = phase["maximum_drawdown_p95_fraction"]
        duration = phase["median_joint_completion_calendar_days"]
        rank = (
            -joint,
            math.inf if drawdown is None else float(drawdown),
            math.inf if duration is None else float(duration),
            config.config_id,
        )
        ranked.append(
            (
                rank,
                config,
                {
                    "enabled_combinations": list(enabled_combinations),
                    "combination_rejections": combination_rejections,
                    "all_combination_diagnostics": all_combination_diagnostics,
                    "router": router_diagnostics,
                    "portfolio_rows_after_enablement": len(portfolio_rows),
                    "portfolio_rows_after_routing": len(routed_rows),
                    "normal": normal,
                    "stressed": stressed,
                    "phase": phase,
                },
            )
        )
    ranked.sort(key=lambda item: item[0])
    summary: dict[str, object] = {
        "selection_split": SELECTION_SPLIT,
        "holdout_rows_supplied_to_selector": False,
        "declared_configurations": len(configs),
        "selection_gate_passers": len(ranked),
        "selection_gate_rejections": rejected,
        "ranked_selection_gate_passers": [
            {
                "rank": index + 1,
                "config_id": item[1].config_id,
                "enabled_combinations": item[2]["enabled_combinations"],
                "joint_pass_probability": item[2]["phase"]["joint_pass_probability"],  # type: ignore[index]
                "maximum_drawdown_p95_fraction": item[2]["phase"]["maximum_drawdown_p95_fraction"],  # type: ignore[index]
                "median_joint_completion_calendar_days": item[2]["phase"]["median_joint_completion_calendar_days"],  # type: ignore[index]
            }
            for index, item in enumerate(ranked)
        ],
    }
    if not ranked:
        summary["selection_result"] = "NO_CHAMPION_SELECTION_GATES"
        return None, summary

    _, provisional, evaluation = ranked[0]
    seed = config_seed_base ^ int(hashlib.sha256(provisional.config_id.encode()).hexdigest()[:8], 16)
    enabled_combinations = tuple(evaluation["enabled_combinations"])
    provisional_rows, _ = route_daily_rows(
        [
            row
            for row in selection_rows
            if row.config_id == provisional.config_id
            and row.combination in enabled_combinations
        ],
        combination_priorities,
    )
    confidence = bootstrap_expectancy_interval(
        provisional_rows,
        policy,
        stressed=False,
        samples=settings.bootstrap_samples,
        block_days=settings.block_days,
        alpha=settings.familywise_alpha,
        family_size=len(configs),
        seed=seed ^ 0xA5A5A5A5,
    )
    summary["provisional_champion"] = provisional.config_id
    summary["provisional_champion_evaluation"] = evaluation
    summary["selection_aware_confidence"] = confidence
    adjusted_lower = confidence["familywise_adjusted_interval"][0]  # type: ignore[index]
    if (
        thresholds.require_selection_adjusted_lower_bound_positive
        and (adjusted_lower is None or float(adjusted_lower) <= 0.0)
    ):
        summary["selection_result"] = "NO_CHAMPION_SELECTION_ADJUSTED_CI"
        return None, summary
    summary["selection_result"] = "CHAMPION_FROZEN_BEFORE_HOLDOUT"
    summary["champion_id"] = provisional.config_id
    summary["champion_enabled_combinations"] = list(enabled_combinations)
    return provisional, summary


def validate(registry_path: Path, input_path: Path, output_path: Path,
             combination_priorities: Mapping[str, int] | None = None) -> dict[str, object]:
    registry = load_registry(registry_path)
    configs = [CandidateConfig(**item) for item in registry["configurations"]]  # type: ignore[index]
    policy = FillPolicy(**registry["fill_policy"])  # type: ignore[arg-type,index]
    thresholds = ValidationThresholds(**registry["thresholds"])  # type: ignore[arg-type,index]
    settings = SimulationSettings(**registry["simulation"])  # type: ignore[arg-type,index]
    priorities = dict(DEFAULT_COMBINATION_PRIORITIES)
    if combination_priorities:
        priorities.update(combination_priorities)
    config_risk_fractions = {
        config.config_id: config.risk_fraction for config in configs
    }
    initial_balance = settings.initial_balance
    qualifying_cash = initial_balance * settings.qualifying_day_fraction
    rows = load_replay_rows(input_path, registry)
    validate_replay_coverage(rows, configs)

    # HOLDOUT is partitioned before the selector is called.  No holdout metric,
    # digest, or outcome is passed into select_champion().
    selection_rows = [row for row in rows if row.split == SELECTION_SPLIT]
    champion, selection_report = select_champion(
        selection_rows,
        configs,
        policy,
        thresholds,
        settings,
        combination_priorities=priorities,
    )
    report: dict[str, object] = {
        "schema_version": SCHEMA_VERSION,
        "registry_sha256": registry["registry_sha256"],
        "input_sha256": hashlib.sha256(input_path.read_bytes()).hexdigest(),
        "combination_priorities_used": dict(priorities),
        "selection": selection_report,
        "holdout_evaluated_after_selection": champion is not None,
        "warnings": [
            "This report is not evidence that the source replay was look-ahead-free or broker-representative.",
            "A passing report does not authorize challenge or funded trading.",
        ],
    }
    if champion is None:
        report["holdout"] = None
        report["sec13"] = None
    else:
        # This is the first point at which holdout outcomes are evaluated.
        all_holdout_rows = _config_rows(rows, champion.config_id, HOLDOUT_SPLIT)
        enabled_combinations = tuple(selection_report["champion_enabled_combinations"])
        holdout_rows = [
            row for row in all_holdout_rows if row.combination in enabled_combinations
        ]
        routed_rows, router_diagnostics = route_daily_rows(holdout_rows, priorities)
        seed = settings.random_seed ^ int(
            hashlib.sha256(champion.config_id.encode()).hexdigest()[:8], 16
        ) ^ 0x5A5A5A5A
        holdout_combination_diagnostics = metric_report(
            all_holdout_rows,
            policy,
            stressed=False,
            seed=settings.random_seed,
            config_risk_fractions=config_risk_fractions,
            initial_balance=initial_balance,
            qualifying_cash=qualifying_cash,
        )
        normal = metric_report(
            routed_rows,
            policy,
            stressed=False,
            seed=settings.random_seed,
            config_risk_fractions=config_risk_fractions,
            initial_balance=initial_balance,
            qualifying_cash=qualifying_cash,
        )
        stressed = metric_report(
            routed_rows,
            policy,
            stressed=True,
            seed=settings.random_seed,
            config_risk_fractions=config_risk_fractions,
            initial_balance=initial_balance,
            qualifying_cash=qualifying_cash,
        )
        passed, failures = gates_pass(
            normal, stressed, thresholds, enabled_combinations
        )
        if (
            int(holdout_combination_diagnostics["rule_violations"]) != 0
            or int(holdout_combination_diagnostics["operational_errors"]) != 0
        ):
            passed = False
            failures = [*failures, "rule_or_operational_error"]
        confidence = bootstrap_expectancy_interval(
            routed_rows,
            policy,
            stressed=False,
            samples=settings.bootstrap_samples,
            block_days=settings.block_days,
            alpha=settings.familywise_alpha,
            family_size=1,
            seed=seed ^ 0xC3C3C3C3,
        )
        holdout_lower = confidence["ordinary_interval"][0]  # type: ignore[index]
        confidence_passed = holdout_lower is not None and float(holdout_lower) > 0.0
        phase_normal = phase_simulation_report(
            routed_rows,
            policy,
            stressed=False,
            paths=settings.holdout_paths,
            settings=settings,
            seed=seed,
        )
        phase_stressed = phase_simulation_report(
            routed_rows,
            policy,
            stressed=True,
            paths=settings.holdout_paths,
            settings=settings,
            seed=seed ^ 0x3C3C3C3C,
        )
        phase_passed, phase_failures = phase_gates_pass(phase_normal, thresholds)
        floor_normal = firm_floor_check(
            routed_rows,
            policy,
            stressed=False,
            seed=seed,
            settings=settings,
        )
        floor_stressed = firm_floor_check(
            routed_rows,
            policy,
            stressed=True,
            seed=seed ^ 0x3C3C3C3C,
            settings=settings,
        )
        sec13 = sec13_verdict(
            normal,
            stressed,
            phase_normal,
            phase_stressed,
            floor_normal,
            floor_stressed,
            thresholds,
        )
        report["holdout"] = {
            "champion": asdict(champion),
            "enabled_combinations_frozen_before_holdout": list(enabled_combinations),
            "router": router_diagnostics,
            "unrouted_enabled_combination_diagnostics": holdout_combination_diagnostics,
            "normal": normal,
            "stressed": stressed,
            "point_gates_pass": passed,
            "point_gate_failures": failures,
            "confidence": confidence,
            "positive_holdout_confidence_lower_bound": confidence_passed,
            "phase_simulation_normal": phase_normal,
            "phase_simulation_stressed": phase_stressed,
            "phase_gates_pass": phase_passed,
            "phase_gate_failures": phase_failures,
            "firm_floor_normal": floor_normal,
            "firm_floor_stressed": floor_stressed,
            "sec13": sec13,
            "all_holdout_gates_pass": (
                passed and confidence_passed and phase_passed
                and bool(sec13["all_sec13_checks_pass"])
            ),
        }
        report["sec13"] = report["holdout"]["sec13"]
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return report


def schema_text() -> str:
    descriptions = {
        "config_id": "exact ID from the frozen registry",
        "split": "TRAIN, WALK_FORWARD, or HOLDOUT",
        "server_day": "ISO date; export every calendar day for every config/combination",
        "sequence": "deterministic event order within the server day",
        "event_id": "stable unique event identifier within config/split/day",
        "combination": "EURUSD_LONDON, GBPUSD_LONDON, or USDJPY_NEW_YORK",
        "candidate": "whether the frozen strategy produced an entry candidate",
        "activation_ok": "pending request was active before the historical price event",
        "limit_touched": "bid/ask executable side reached the limit",
        "trade_through_ticks": "ticks beyond the limit after activation; baseline requires >=1",
        "fill_fraction": "0..1; baseline requires a complete fill",
        "net_r": "post-normal-cost result in initial-risk R if completely filled",
        "risk_cash_full": "actual rounded-volume full-tier stop cash risk",
        "risk_cash_half": "actual rounded-volume half-tier stop cash risk",
        "net_cash_full": "actual normal-cost full-tier net cash result",
        "net_cash_half": "actual normal-cost half-tier net cash result",
        "mae_cash_full": "nonnegative worst adverse cash excursion at full tier",
        "mae_cash_half": "nonnegative worst adverse cash excursion at half tier",
        "spread_r": "spread component already deducted from net_r",
        "slippage_r": "slippage component already deducted from net_r",
        "commission_r": "commission component already deducted from net_r",
        "rule_violation": "replay detected any compliance-rule violation",
        "operational_error": "replay detected sizing/state/order/restart error",
    }
    lines = [",".join(CSV_FIELDS), ""]
    lines.extend(f"{field}: {descriptions[field]}" for field in CSV_FIELDS)
    return "\n".join(lines) + "\n"


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    preregister = subparsers.add_parser("preregister", help="write the frozen 160-config registry")
    preregister.add_argument("--output", type=Path, required=True)
    preregister.add_argument("--force", action="store_true", help="replace an existing identical-purpose file")
    subparsers.add_parser("schema", help="print the replay CSV header and field contract")
    validate_parser = subparsers.add_parser("validate", help="select on WALK_FORWARD, then evaluate HOLDOUT")
    validate_parser.add_argument("--registry", type=Path, required=True)
    validate_parser.add_argument("--input", type=Path, required=True)
    validate_parser.add_argument("--output", type=Path, required=True)
    validate_parser.add_argument(
        "--combination-priorities",
        default="",
        help=(
            "frozen section-12 router priorities as "
            "EURUSD_LONDON:1,GBPUSD_LONDON:2,USDJPY_NEW_YORK:3; omitted values "
            "default to 1 (the EA default, ties allowed)"
        ),
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.command == "preregister":
            registry = write_registry(args.output, overwrite=args.force)
            print(
                f"wrote {len(registry['configurations'])} configurations to {args.output} "
                f"sha256={registry['registry_sha256']}"
            )
        elif args.command == "schema":
            print(schema_text(), end="")
        elif args.command == "validate":
            priorities = parse_combination_priorities(args.combination_priorities)
            report = validate(
                args.registry, args.input, args.output, combination_priorities=priorities
            )
            selection = report["selection"]
            assert isinstance(selection, dict)
            print(
                f"selection={selection['selection_result']} "
                f"champion={selection.get('champion_id', 'NONE')} report={args.output}"
            )
        else:  # pragma: no cover - argparse enforces this.
            raise AssertionError(args.command)
    except ValidationError as exc:
        print(f"validation error: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
