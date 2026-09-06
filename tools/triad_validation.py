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
from dataclasses import asdict, dataclass
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
            if row.candidate and (row.risk_cash_full <= 0 or row.risk_cash_half <= 0):
                raise ValidationError(f"line {line_number}: candidates require positive cash-risk values")
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


def metric_report(rows: Sequence[ReplayRow], policy: FillPolicy, *, stressed: bool,
                  seed: int) -> dict[str, object]:
    trades = [
        trade
        for row in rows
        if (trade := apply_fill_policy(row, policy, stressed=stressed, seed=seed)) is not None
    ]
    values = [trade.net_r for trade in trades]
    by_combination: dict[str, list[float]] = defaultdict(list)
    for trade in trades:
        by_combination[trade.row.combination].append(trade.net_r)
    per_combination: dict[str, object] = {}
    for combination in sorted(ALLOWED_COMBINATIONS):
        combination_values = by_combination[combination]
        per_combination[combination] = {
            "fills": len(combination_values),
            "expectancy_r": statistics.fmean(combination_values) if combination_values else None,
            "profit_factor": _json_number(_profit_factor(combination_values)),
        }
    return {
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


def simulate_phase(days: Sequence[tuple[date, list[AppliedTrade]]], *, phase_target_fraction: float,
                   settings: SimulationSettings, rng: random.Random) -> PhaseOutcome:
    initial = settings.initial_balance
    balance = initial
    high_water = initial
    max_drawdown = 0.0
    qualifying_days = 0
    inactive_days = 0
    weekly_start = initial
    sampled = _moving_block_days(days, rng, settings.block_days)
    target = initial * (1.0 + phase_target_fraction)
    qualifying_cash = initial * settings.qualifying_day_fraction

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
                return PhaseOutcome(False, "strategy_drawdown_shutdown", day_number, max_drawdown, qualifying_days)
            half_risk = drawdown >= settings.drawdown_reduce_fraction
            adverse = trade.adverse_cash(half_risk)
            interim_equity = balance - adverse
            interim_drawdown = max(0.0, (high_water - interim_equity) / high_water)
            max_drawdown = max(max_drawdown, interim_drawdown)
            if interim_drawdown >= settings.drawdown_shutdown_fraction:
                return PhaseOutcome(False, "strategy_drawdown_shutdown", day_number, max_drawdown, qualifying_days)

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
            return PhaseOutcome(False, "inactivity", day_number, max_drawdown, qualifying_days)
        if day_net >= qualifying_cash:
            qualifying_days += 1
        if target_reached:
            passed = qualifying_days >= settings.required_qualifying_days
            reason = "passed" if passed else "target_pending_days"
            return PhaseOutcome(passed, reason, day_number, max_drawdown, qualifying_days)
        drawdown = max(0.0, (high_water - balance) / high_water)
        max_drawdown = max(max_drawdown, drawdown)
        if drawdown >= settings.drawdown_shutdown_fraction:
            return PhaseOutcome(False, "strategy_drawdown_shutdown", day_number, max_drawdown, qualifying_days)

    return PhaseOutcome(False, "maximum_duration", settings.max_phase_calendar_days, max_drawdown, qualifying_days)


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


def phase_simulation_report(rows: Sequence[ReplayRow], policy: FillPolicy, *, stressed: bool,
                            paths: int, settings: SimulationSettings, seed: int) -> dict[str, object]:
    if paths <= 0:
        raise ValidationError("phase simulation requires at least one path")
    days = _trades_by_day(rows, policy, stressed=stressed, seed=seed)
    rng = random.Random(seed)
    phase1_outcomes: list[PhaseOutcome] = []
    phase2_outcomes: list[PhaseOutcome] = []
    joint_days: list[float] = []
    joint_passes = 0
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
        if phase1.passed and phase2.passed:
            joint_passes += 1
            joint_days.append(float(phase1.calendar_days + phase2.calendar_days))
    drawdowns = [
        max(phase1.maximum_drawdown_fraction, phase2.maximum_drawdown_fraction)
        for phase1, phase2 in zip(phase1_outcomes, phase2_outcomes)
    ]
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
        "phase1_pass_probability": phase1_passes / paths,
        "phase2_pass_probability": phase2_passes / paths,
        "joint_pass_probability": joint_passes / paths,
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
        "median_joint_completion_calendar_days": statistics.median(joint_days) if joint_days else None,
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
                    settings: SimulationSettings) -> tuple[CandidateConfig | None, dict[str, object]]:
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
        normal = metric_report(
            portfolio_rows, policy, stressed=False, seed=settings.random_seed
        )
        stressed = metric_report(
            portfolio_rows, policy, stressed=True, seed=settings.random_seed
        )
        passed, failures = gates_pass(
            normal, stressed, thresholds, enabled_combinations
        )
        if not passed:
            rejected[config.config_id] = failures
            continue
        phase = phase_simulation_report(
            portfolio_rows,
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
    provisional_rows = [
        row
        for row in selection_rows
        if row.config_id == provisional.config_id
        and row.combination in enabled_combinations
    ]
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


def validate(registry_path: Path, input_path: Path, output_path: Path) -> dict[str, object]:
    registry = load_registry(registry_path)
    configs = [CandidateConfig(**item) for item in registry["configurations"]]  # type: ignore[index]
    policy = FillPolicy(**registry["fill_policy"])  # type: ignore[arg-type,index]
    thresholds = ValidationThresholds(**registry["thresholds"])  # type: ignore[arg-type,index]
    settings = SimulationSettings(**registry["simulation"])  # type: ignore[arg-type,index]
    rows = load_replay_rows(input_path, registry)
    validate_replay_coverage(rows, configs)

    # HOLDOUT is partitioned before the selector is called.  No holdout metric,
    # digest, or outcome is passed into select_champion().
    selection_rows = [row for row in rows if row.split == SELECTION_SPLIT]
    champion, selection_report = select_champion(
        selection_rows, configs, policy, thresholds, settings
    )
    report: dict[str, object] = {
        "schema_version": SCHEMA_VERSION,
        "registry_sha256": registry["registry_sha256"],
        "input_sha256": hashlib.sha256(input_path.read_bytes()).hexdigest(),
        "selection": selection_report,
        "holdout_evaluated_after_selection": champion is not None,
        "warnings": [
            "This report is not evidence that the source replay was look-ahead-free or broker-representative.",
            "A passing report does not authorize challenge or funded trading.",
        ],
    }
    if champion is None:
        report["holdout"] = None
    else:
        # This is the first point at which holdout outcomes are evaluated.
        all_holdout_rows = _config_rows(rows, champion.config_id, HOLDOUT_SPLIT)
        enabled_combinations = tuple(selection_report["champion_enabled_combinations"])
        holdout_rows = [
            row for row in all_holdout_rows if row.combination in enabled_combinations
        ]
        seed = settings.random_seed ^ int(
            hashlib.sha256(champion.config_id.encode()).hexdigest()[:8], 16
        ) ^ 0x5A5A5A5A
        holdout_combination_diagnostics = metric_report(
            all_holdout_rows, policy, stressed=False, seed=settings.random_seed
        )
        normal = metric_report(holdout_rows, policy, stressed=False, seed=settings.random_seed)
        stressed = metric_report(holdout_rows, policy, stressed=True, seed=settings.random_seed)
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
            holdout_rows,
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
            holdout_rows,
            policy,
            stressed=False,
            paths=settings.holdout_paths,
            settings=settings,
            seed=seed,
        )
        phase_stressed = phase_simulation_report(
            holdout_rows,
            policy,
            stressed=True,
            paths=settings.holdout_paths,
            settings=settings,
            seed=seed ^ 0x3C3C3C3C,
        )
        phase_passed, phase_failures = phase_gates_pass(phase_normal, thresholds)
        report["holdout"] = {
            "champion": asdict(champion),
            "enabled_combinations_frozen_before_holdout": list(enabled_combinations),
            "all_combination_diagnostics": holdout_combination_diagnostics,
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
            "all_holdout_gates_pass": passed and confidence_passed and phase_passed,
        }
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
            report = validate(args.registry, args.input, args.output)
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
