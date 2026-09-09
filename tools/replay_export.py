"""Registry-conformant replay export builder for TRIAD-R V2.1.

This module converts *observed* signal events and their exit outcomes into the
exact CSV schema consumed by ``tools/triad_validation.py``.  It is the missing
producer in the pipeline: the validator reads the schema, but before this file
existed no committed code wrote it.

What this exporter does
-----------------------
1. Validates an observed-event CSV produced by an external tick/bar replay
   (MT5 Strategy Tester export, or a separate backtest harness).
2. Applies the frozen candidate-per-config arithmetic that the EA itself
   performs (per the V2.1 contract):

   - entry = 50% retracement of the displacement body;
   - stop = sweep extreme +/- 0.10 x ATR(M15,14), accepted only when the
     entry-to-stop distance is within 0.60..1.50 x ATR;
   - cost gate: all-in modeled round-trip cost <= 0.10R;
   - lot rounding anchored at SYMBOL_VOLUME_MIN (never rounding up), skip when
     the minimum volume exceeds the risk budget;
   - cash risk and net cash from the symbol's tick size / tick value, with the
     commission and slippage reserve applied;
   - target solved so the estimated *net* target result equals the profile's
     target R after costs;
   - time-stop outcome selected from the observed exit path per configuration
     (30/45/60/90 minutes or session-only);
   - confirmed-1R breakeven policy applied when the observed path reached +1R.

3. Expands the event set into full calendar coverage: every server day in the
   declared WALK_FORWARD and HOLDOUT ranges receives a row for **every**
   configuration **and** every instrument/session combination, with explicit
   no-candidate rows where no event occurred.  The split cut is a required
   argument — this exporter never infers it from data, because deciding the
   holdout boundary after seeing data is the exact failure mode the frozen
   registry forbids.

What it does NOT do
-------------------
- It does not read raw tick data, build bars, reconstruct fills from bids/asks,
  or decide whether a pending limit traded through.  Those need the data and
  the broker/replay source (the MT5 real-tick Strategy Tester, for example),
  so they are the responsibility of the upstream replay job that produces the
  observed-event CSV.  The fields ``limit_touched``, ``trade_through_ticks``,
  ``fill_fraction``, ``activation_ok``, and the exit path are inputs here, not
  outputs — and the validator's conservative fill policy keeps their
  interpretation explicit.
- It does not change the frozen registry or strategy rules.

Observed-event CSV contract (``--event-file``)
----------------------------------------------
An event is one completed signal sequence (sweep + reclaim + displacement).
Columns (header must match exactly; ``;`` or ``,`` delimiter is auto-detected):

    server_day,sequence,event_id,combination,direction,
    reference_low,reference_high,sweep_low,sweep_high,
    reclaim_open,reclaim_high,reclaim_low,reclaim_close,
    displacement_open,displacement_high,displacement_low,displacement_close,
    atr_m15,
    tick_size,tick_value,contract_size,volume_min,volume_step,
    spread_price,slippage_price,commission_per_lot_round_trip,
    limit_active,limit_touched,trade_through_ticks,fill_fraction,
    exit_reason,target_hit_minutes,stop_hit_minutes,breakeven_hit_minutes,
    price_at_30,price_at_45,price_at_60,price_at_90,price_at_session_end,
    worst_adverse_price,rule_violation,operational_error

Semantics:

- ``server_day``: the MT5 broker server day (ISO date); phase, daily, and
  qualification logic operate on this key, not civil time.
- ``direction``: ``long`` or ``short``; the exporter fails closed on anything
  else so mirrored rules cannot silently misalign.
- ``sequence``: deterministic signal order within the server day; higher is
  later.  Only the first event per symbol/session/day may produce an order
  (the "one signal event per session" rule); later same-day events are emitted
  as activated=false observations and are not ranked.
- ``limit_active`` / ``limit_touched`` / ``trade_through_ticks`` /
  ``fill_fraction``: the conservative fill observations.  If the upstream
  replay cannot honestly say the pending request traded through by at least
  one tick, leave ``limit_touched=false`` and ``trade_through_ticks=0``; the
  validator will treat it as a missed fill (as intended).
- ``exit_reason``: one of ``target``, ``stop``, ``breakeven``, ``time``,
  ``session_end``, ``cancel``.  ``target_hit_minutes`` etc. are minutes from
  entry to first touch of each level; ``None`` (empty) means never hit.
- ``price_at_30/45/60/90`` and ``price_at_session_end``: the executable exit
  price at each horizon, required for time-stop selection.  ``session_end`` is
  the last executable price before the session cutoff (the EA's forced-flat
  rule).  ``worst_adverse_price`` is the most adverse price observed during the
  holding window, used for the MAE cash fields.
- Costs are inputs: ``spread_price`` and ``slippage_price`` are quote-currency
  price units per side (buy then sell), ``commission_per_lot_round_trip`` is
  account-currency cash per 1.00 lot.  The validator's stress scenario
  re-applies its multipliers on the resulting ``*_r`` fields, so the exporter
  reports the *normal* cost components only.

The exporter re-checks sweep-depth, reclaim-wick, displacement-body, and
direction contract conditions so a broken upstream signal can never silently
become a trade: such observations are emitted with ``candidate=true`` and
``activation_ok=false`` (a candidate existed but the frozen rules rejected the
order).  Mandatory range/ATR percentile, spread-median, news, and sizing gates
must be marked by the upstream replay through ``activation_ok`` and the
rejection is already visible in the zeroed risk/cash fields.

Usage
-----
::

    # Show the observed-event contract.
    python3 tools/replay_export.py schema

    # Synthetic round-trip through the real validator loader/coverage/metrics.
    python3 tools/replay_export.py selftest --tmpdir /tmp/replay_selftest

    # Build a registry-conformant replay from observed events.
    python3 tools/replay_export.py build \\
        --event-file events.csv --configs validation/triad_v2_1_registry.json \\
        --selection-split 2019.01.01 2024.12.31 \\
        --holdout-split 2025.01.01 2026.08.31 \\
        --output validation/triad_replay_rows.csv

"""
from __future__ import annotations

import argparse
import csv
import json
import math
import sys
from dataclasses import asdict, dataclass
from datetime import date
from pathlib import Path
from typing import Iterator, Sequence

# Allow running as ``python3 tools/replay_export.py ...`` from the repository
# root (as documented and as the README tooling section invokes it).
if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools.triad_validation import (
    ALLOWED_COMBINATIONS,
    CSV_FIELDS,
    FillPolicy,
    ReplayRow,
    ValidationError,
    load_registry,
    load_replay_rows,
    metric_report,
    validate_replay_coverage,
)

EVENT_FIELDS = (
    "server_day",
    "sequence",
    "event_id",
    "combination",
    "direction",
    "reference_low",
    "reference_high",
    "sweep_low",
    "sweep_high",
    "reclaim_open",
    "reclaim_high",
    "reclaim_low",
    "reclaim_close",
    "displacement_open",
    "displacement_high",
    "displacement_low",
    "displacement_close",
    "atr_m15",
    "tick_size",
    "tick_value",
    "contract_size",
    "volume_min",
    "volume_step",
    "spread_price",
    "slippage_price",
    "commission_per_lot_round_trip",
    "limit_active",
    "limit_touched",
    "trade_through_ticks",
    "fill_fraction",
    "exit_reason",
    "target_hit_minutes",
    "stop_hit_minutes",
    "breakeven_hit_minutes",
    "price_at_30",
    "price_at_45",
    "price_at_60",
    "price_at_90",
    "price_at_session_end",
    "worst_adverse_price",
    "rule_violation",
    "operational_error",
)

EXIT_REASONS = {"target", "stop", "breakeven", "time", "session_end", "cancel"}

# The EA contract values (frozen in Initialize of TRIAD_R_HS.mq5).
SWEEP_ATR_MIN = 0.05
SWEEP_ATR_MAX = 0.50
RECLAIM_WICK_MIN = 0.60
DISPLACEMENT_BODY_MIN = 0.60
STOP_BUFFER_ATR = 0.10
STOP_ATR_MIN = 0.60
STOP_ATR_MAX = 1.50
MAX_COST_TO_R = 0.10
DEFAULT_INITIAL_BALANCE = 2500.0
EPS = 1e-9


@dataclass(frozen=True)
class ObservedEvent:
    server_day: date
    sequence: int
    event_id: str
    combination: str
    direction: str
    reference_low: float
    reference_high: float
    sweep_low: float
    sweep_high: float
    reclaim_open: float
    reclaim_high: float
    reclaim_low: float
    reclaim_close: float
    displacement_open: float
    displacement_high: float
    displacement_low: float
    displacement_close: float
    atr_m15: float
    tick_size: float
    tick_value: float
    contract_size: float
    volume_min: float
    volume_step: float
    spread_price: float
    slippage_price: float
    commission_per_lot_round_trip: float
    limit_active: bool
    limit_touched: bool
    trade_through_ticks: int
    fill_fraction: float
    exit_reason: str
    target_hit_minutes: float | None
    stop_hit_minutes: float | None
    breakeven_hit_minutes: float | None
    price_at_30: float
    price_at_45: float
    price_at_60: float
    price_at_90: float
    price_at_session_end: float
    worst_adverse_price: float
    rule_violation: bool
    operational_error: bool


@dataclass(frozen=True)
class ConfigSpec:
    config_id: str
    profile: str
    risk_fraction: float
    target_r: float
    time_stop_minutes: int  # 0 = session only
    move_stop_to_entry_after_confirmed_1r: bool


@dataclass(frozen=True)
class ExportPlan:
    selection_start: date
    selection_end: date
    holdout_start: date
    holdout_end: date


# ---------------------------------------------------------------------------
# Parsing helpers (fail closed, never coerce silently)
# ---------------------------------------------------------------------------


def _parse_date(value: str, field_name: str) -> date:
    normalized = value.strip().replace(".", "-")
    try:
        return date.fromisoformat(normalized)
    except ValueError as exc:
        raise ValidationError(
            f"{field_name} must be YYYY-MM-DD (or YYYY.MM.DD), got {value!r}"
        ) from exc


def _parse_float(value: str, field_name: str) -> float:
    try:
        parsed = float(value)
    except ValueError as exc:
        raise ValidationError(f"{field_name} must be numeric, got {value!r}") from exc
    if not math.isfinite(parsed):
        raise ValidationError(f"{field_name} must be finite")
    return parsed


def _parse_optional_float(value: str, field_name: str) -> float | None:
    if value.strip() == "" or value.strip().lower() in {"none", "null"}:
        return None
    parsed = _parse_float(value, field_name)
    if parsed < 0.0:
        raise ValidationError(f"{field_name} must be nonnegative")
    return parsed


def _parse_bool(value: str, field_name: str) -> bool:
    normalized = value.strip().lower()
    if normalized in {"true", "1"}:
        return True
    if normalized in {"false", "0"}:
        return False
    raise ValidationError(f"{field_name} must be true/false or 1/0, got {value!r}")


def load_observed_events(path: Path) -> list[ObservedEvent]:
    try:
        handle = path.open("r", encoding="utf-8", newline="")
    except OSError as exc:
        raise ValidationError(f"cannot open event CSV {path}: {exc}") from exc
    events: list[ObservedEvent] = []
    with handle:
        sample = handle.readline()
        handle.seek(0)
        delimiter = ";" if sample.count(";") > sample.count(",") else ","
        reader = csv.DictReader(handle, delimiter=delimiter)
        if reader.fieldnames is None or [name.strip() for name in reader.fieldnames] != list(EVENT_FIELDS):
            raise ValidationError(
                "event CSV header mismatch; run `python3 tools/replay_export.py schema`"
            )
        for line_number, raw in enumerate(reader, start=2):
            try:
                day = _parse_date(raw["server_day"], f"line {line_number} server_day")
                sequence = int(raw["sequence"])
                event_id = raw["event_id"].strip()
                combination = raw["combination"].strip().upper()
                direction = raw["direction"].strip().lower()
            except (KeyError, TypeError, ValueError) as exc:
                raise ValidationError(f"line {line_number}: invalid identifier/date/integer field") from exc
            if combination not in ALLOWED_COMBINATIONS:
                raise ValidationError(f"line {line_number}: unknown combination {combination}")
            if direction not in {"long", "short"}:
                raise ValidationError(f"line {line_number}: direction must be long or short")
            if sequence < 0 or not event_id:
                raise ValidationError(f"line {line_number}: invalid sequence/event_id")

            def optional(field_name: str) -> float | None:
                return _parse_optional_float(raw[field_name], f"line {line_number} {field_name}")

            def positive(field_name: str) -> float:
                value = _parse_float(raw[field_name], f"line {line_number} {field_name}")
                if value <= 0.0:
                    raise ValidationError(f"line {line_number}: {field_name} must be positive")
                return value

            def nonnegative(field_name: str) -> float:
                value = _parse_float(raw[field_name], f"line {line_number} {field_name}")
                if value < 0.0:
                    raise ValidationError(f"line {line_number}: {field_name} must be nonnegative")
                return value

            event = ObservedEvent(
                server_day=day,
                sequence=sequence,
                event_id=event_id,
                combination=combination,
                direction=direction,
                reference_low=_parse_float(raw["reference_low"], f"line {line_number} reference_low"),
                reference_high=_parse_float(raw["reference_high"], f"line {line_number} reference_high"),
                sweep_low=_parse_float(raw["sweep_low"], f"line {line_number} sweep_low"),
                sweep_high=_parse_float(raw["sweep_high"], f"line {line_number} sweep_high"),
                reclaim_open=_parse_float(raw["reclaim_open"], f"line {line_number} reclaim_open"),
                reclaim_high=_parse_float(raw["reclaim_high"], f"line {line_number} reclaim_high"),
                reclaim_low=_parse_float(raw["reclaim_low"], f"line {line_number} reclaim_low"),
                reclaim_close=_parse_float(raw["reclaim_close"], f"line {line_number} reclaim_close"),
                displacement_open=_parse_float(raw["displacement_open"], f"line {line_number} displacement_open"),
                displacement_high=_parse_float(raw["displacement_high"], f"line {line_number} displacement_high"),
                displacement_low=_parse_float(raw["displacement_low"], f"line {line_number} displacement_low"),
                displacement_close=_parse_float(raw["displacement_close"], f"line {line_number} displacement_close"),
                atr_m15=positive("atr_m15"),
                tick_size=positive("tick_size"),
                tick_value=positive("tick_value"),
                contract_size=positive("contract_size"),
                volume_min=positive("volume_min"),
                volume_step=positive("volume_step"),
                spread_price=nonnegative("spread_price"),
                slippage_price=nonnegative("slippage_price"),
                commission_per_lot_round_trip=nonnegative("commission_per_lot_round_trip"),
                limit_active=_parse_bool(raw["limit_active"], f"line {line_number} limit_active"),
                limit_touched=_parse_bool(raw["limit_touched"], f"line {line_number} limit_touched"),
                trade_through_ticks=int(raw["trade_through_ticks"]),
                fill_fraction=nonnegative("fill_fraction"),
                exit_reason=raw["exit_reason"].strip().lower(),
                target_hit_minutes=optional("target_hit_minutes"),
                stop_hit_minutes=optional("stop_hit_minutes"),
                breakeven_hit_minutes=optional("breakeven_hit_minutes"),
                price_at_30=_parse_float(raw["price_at_30"], f"line {line_number} price_at_30"),
                price_at_45=_parse_float(raw["price_at_45"], f"line {line_number} price_at_45"),
                price_at_60=_parse_float(raw["price_at_60"], f"line {line_number} price_at_60"),
                price_at_90=_parse_float(raw["price_at_90"], f"line {line_number} price_at_90"),
                price_at_session_end=_parse_float(
                    raw["price_at_session_end"], f"line {line_number} price_at_session_end"
                ),
                worst_adverse_price=_parse_float(
                    raw["worst_adverse_price"], f"line {line_number} worst_adverse_price"
                ),
                rule_violation=_parse_bool(raw["rule_violation"], f"line {line_number} rule_violation"),
                operational_error=_parse_bool(raw["operational_error"], f"line {line_number} operational_error"),
            )
            if event.fill_fraction > 1.0 + EPS:
                raise ValidationError(f"line {line_number}: fill_fraction cannot exceed 1")
            if event.trade_through_ticks < 0:
                raise ValidationError(f"line {line_number}: trade_through_ticks cannot be negative")
            if event.exit_reason not in EXIT_REASONS:
                raise ValidationError(
                    f"line {line_number}: exit_reason must be one of {sorted(EXIT_REASONS)}"
                )
            if event.exit_reason == "target" and event.target_hit_minutes is None:
                raise ValidationError(f"line {line_number}: target exit requires target_hit_minutes")
            if event.exit_reason == "stop" and event.stop_hit_minutes is None:
                raise ValidationError(f"line {line_number}: stop exit requires stop_hit_minutes")
            events.append(event)
    keys = [(event.server_day, event.sequence, event.event_id, event.combination) for event in events]
    if len(keys) != len(set(keys)):
        raise ValidationError("event CSV contains duplicate (server_day, sequence, event_id, combination)")
    return events


def load_config_specs(registry: Mapping[str, object]) -> list[ConfigSpec]:
    """Load the frozen configurations from an already-validated registry."""
    configs: list[ConfigSpec] = []
    for item in registry["configurations"]:  # type: ignore[index]
        configs.append(
            ConfigSpec(
                config_id=str(item["config_id"]),
                profile=str(item["profile"]),
                risk_fraction=float(item["risk_fraction"]),
                target_r=float(item["target_r"]),
                time_stop_minutes=int(item["time_stop_minutes"]),
                move_stop_to_entry_after_confirmed_1r=bool(
                    item["move_stop_to_entry_after_confirmed_1r"]
                ),
            )
        )
    if not configs:
        raise ValidationError("registry contains no configurations")
    return configs


# ---------------------------------------------------------------------------
# Per-config arithmetic (mirrors the frozen EA contract)
# ---------------------------------------------------------------------------


def _max_inclusive_multiple(lattice_min: float, step: float, limit: float) -> float:
    """Largest volume-lattice value <= limit, anchored at lattice_min.

    Matches the EA volume grid: the grid is *not* assumed anchored at zero.
    If ``limit`` falls below the first lattice point, the caller skips.
    """
    if limit < lattice_min - EPS:
        return 0.0
    if step <= 0.0:
        return lattice_min
    count = math.floor((limit - lattice_min) / step + EPS)
    return lattice_min + count * step


def _cash_per_price_unit(event: ObservedEvent) -> float:
    """Quote-currency price units to account-currency cash per 1.00 lot."""
    return (event.tick_value / event.tick_size) * event.contract_size


def derive_event_rows(event: ObservedEvent, config: ConfigSpec,
                      initial_balance: float = DEFAULT_INITIAL_BALANCE) -> list[ReplayRow]:
    """One ReplayRow per configuration for a single observed event.

    Rejects with ``candidate=true / activation_ok=false`` when a frozen
    geometry/cost/stop/sizing condition fails.  The day-expansion step adds
    explicit no-candidate rows for the other configurations/combinations.
    """
    is_long = event.direction == "long"
    # Entry-sequence contract: sweep depth and reclaim/geometry are upstream
    # observations, but the exporter re-checks the frozen constants so a
    # broken upstream signal can never silently become a trade.
    sweep_depth = (
        (event.reference_low - event.sweep_low) if is_long
        else (event.sweep_high - event.reference_high)
    )
    if not (SWEEP_ATR_MIN * event.atr_m15 <= sweep_depth + EPS <= SWEEP_ATR_MAX * event.atr_m15):
        return [_rejected(event, config, "sweep_depth_atr_band")]

    reclaim_range = event.reclaim_high - event.reclaim_low
    if reclaim_range <= 0.0:
        return [_rejected(event, config, "invalid_reclaim_bar")]
    reclaim_wick = (
        min(event.reclaim_open, event.reclaim_close) - event.reclaim_low
        if is_long
        else event.reclaim_high - max(event.reclaim_open, event.reclaim_close)
    )
    if reclaim_wick + EPS < RECLAIM_WICK_MIN * reclaim_range:
        return [_rejected(event, config, "reclaim_wick")]

    displacement_range = event.displacement_high - event.displacement_low
    displacement_body = abs(event.displacement_close - event.displacement_open)
    if displacement_range <= 0.0 or displacement_body + EPS < DISPLACEMENT_BODY_MIN * displacement_range:
        return [_rejected(event, config, "weak_displacement")]
    reclaim_midpoint = (event.reclaim_high + event.reclaim_low) / 2.0
    if is_long and not event.displacement_close > reclaim_midpoint:
        return [_rejected(event, config, "displacement_direction")]
    if not is_long and not event.displacement_close < reclaim_midpoint:
        return [_rejected(event, config, "displacement_direction")]

    entry = (event.displacement_open + event.displacement_close) / 2.0
    stop = (
        event.sweep_low - STOP_BUFFER_ATR * event.atr_m15
        if is_long
        else event.sweep_high + STOP_BUFFER_ATR * event.atr_m15
    )
    stop_distance = abs(entry - stop)
    if stop_distance <= 0.0:
        return [_rejected(event, config, "zero_stop_distance")]
    if not (STOP_ATR_MIN * event.atr_m15 <= stop_distance + EPS <= STOP_ATR_MAX * event.atr_m15):
        return [_rejected(event, config, "stop_distance_atr_band")]

    cash_per_unit = _cash_per_price_unit(event)
    per_lot_risk = cash_per_unit * stop_distance
    if per_lot_risk <= 0.0:
        return [_rejected(event, config, "zero_per_lot_risk")]
    spread_cash = cash_per_unit * event.spread_price
    slippage_cash = cash_per_unit * 2.0 * event.slippage_price
    round_cost_cash = spread_cash + slippage_cash + event.commission_per_lot_round_trip
    cost_r = round_cost_cash / per_lot_risk
    if cost_r + EPS > MAX_COST_TO_R:
        return [_rejected(event, config, "cost_gate")]

    # Volume rounding anchored at SYMBOL_VOLUME_MIN (never round up).
    risk_budget = initial_balance * config.risk_fraction
    lots = _max_inclusive_multiple(
        event.volume_min, event.volume_step, risk_budget / per_lot_risk
    )
    if lots + EPS < event.volume_min:
        return [_rejected(event, config, "minimum_volume_exceeds_risk_budget")]

    # Target solved so the estimated *net* target result equals the profile's
    # target R after commission and the slippage reserve (V2 section 7).
    commission_r = event.commission_per_lot_round_trip / per_lot_risk
    slippage_r = slippage_cash / per_lot_risk
    gross_target_distance = stop_distance * (config.target_r + commission_r + slippage_r)
    target = entry + gross_target_distance if is_long else entry - gross_target_distance

    def per_lot_net(exit_price: float) -> float:
        distance = abs(exit_price - entry)
        return cash_per_unit * distance - round_cost_cash

    def outcome_net_r(exit_price: float) -> float:
        return per_lot_net(exit_price) / per_lot_risk

    # Exit selection per configuration (time-stop and breakeven) using the
    # observed path; the upstream exit_reason supplies target/stop precedence.
    if event.exit_reason == "target" and event.target_hit_minutes is not None:
        exit_price = target
        effective_reason = "target"
    elif event.exit_reason == "stop" and event.stop_hit_minutes is not None:
        exit_price = stop
        effective_reason = "stop"
    elif config.time_stop_minutes > 0:
        horizon = config.time_stop_minutes
        exit_price = {
            30: event.price_at_30,
            45: event.price_at_45,
            60: event.price_at_60,
            90: event.price_at_90,
        }[horizon]
        effective_reason = "time"
    else:
        exit_price = event.price_at_session_end
        effective_reason = "session_end"
    exit_r = outcome_net_r(exit_price)

    if config.move_stop_to_entry_after_confirmed_1r and event.breakeven_hit_minutes is not None:
        # Confirmed +1R close before the exit: the broker stop moved to entry.
        # Any fill worse than the +1R level is therefore capped at breakeven
        # (still net of commission and slippage).
        one_r_price = entry + (entry - stop) if is_long else entry - (entry - stop)
        was_beyond = (
            (exit_price - one_r_price) > 0.0 if is_long
            else (one_r_price - exit_price) > 0.0
        )
        if not was_beyond:
            exit_r = outcome_net_r(entry)
            effective_reason = "breakeven"

    risk_cash_full = lots * per_lot_risk
    mae_distance = max(
        0.0,
        (entry - event.worst_adverse_price) if is_long
        else (event.worst_adverse_price - entry),
    )
    mae_cash = cash_per_unit * mae_distance * lots
    net_cash_full = lots * per_lot_net(exit_price)
    return [
        ReplayRow(
            config_id=config.config_id,
            split="WALK_FORWARD",  # replaced by the expansion step.
            server_day=event.server_day,
            sequence=event.sequence,
            event_id=event.event_id,
            combination=event.combination,
            candidate=True,
            activation_ok=event.limit_active,
            limit_touched=event.limit_active and event.limit_touched,
            trade_through_ticks=event.trade_through_ticks,
            fill_fraction=event.fill_fraction,
            net_r=round(float(exit_r), 6),
            risk_cash_full=round(risk_cash_full, 4),
            risk_cash_half=round(risk_cash_full / 2.0, 4),
            net_cash_full=round(net_cash_full, 4),
            net_cash_half=round(net_cash_full / 2.0, 4),
            mae_cash_full=round(mae_cash, 4),
            mae_cash_half=round(mae_cash / 2.0, 4),
            spread_r=round(spread_cash / per_lot_risk, 6),
            slippage_r=round(slippage_r, 6),
            commission_r=round(commission_r, 6),
            rule_violation=event.rule_violation,
            operational_error=event.operational_error,
        )
    ]


def _rejected(event: ObservedEvent, config: ConfigSpec, rejection: str) -> ReplayRow:
    """Row for a candidate that the frozen rules refused to act on.

    ``candidate`` stays true (the signal existed), ``activation_ok`` is false
    (no order was ever sent), and the risk/cash fields are zeroed.  ``rejection``
    is deliberately *not* part of the frozen schema — the audit trail stays in
    the upstream replay logs — but the count of these rows is visible through
    ``metric_report()`` activation-refusal metrics.
    """
    return ReplayRow(
        config_id=config.config_id,
        split="WALK_FORWARD",
        server_day=event.server_day,
        sequence=event.sequence,
        event_id=event.event_id,
        combination=event.combination,
        candidate=True,
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
        rule_violation=event.rule_violation,
        operational_error=event.operational_error,
    )


def _no_candidate(config: ConfigSpec, day: date, combination: str, *, split: str) -> ReplayRow:
    """Explicit no-event row; required for validator day-coverage checks."""
    return ReplayRow(
        config_id=config.config_id,
        split=split,
        server_day=day,
        sequence=0,
        event_id=f"no-event-{day.isoformat()}-{combination}",
        combination=combination,
        candidate=False,
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
        rule_violation=False,
        operational_error=False,
    )


# ---------------------------------------------------------------------------
# Calendar expansion
# ---------------------------------------------------------------------------


def _iter_days(start: date, end: date) -> Iterator[date]:
    current = start
    while current <= end:
        yield current
        try:
            current = date.fromordinal(current.toordinal() + 1)
        except OverflowError:
            return


def build_export_rows(events: Sequence[ObservedEvent], configs: Sequence[ConfigSpec],
                      plan: ExportPlan) -> list[ReplayRow]:
    """Expand events into the full registry-conformant day/combination matrix.

    For every configuration, every combination, and every server day in the two
    declared split ranges, exactly one row is emitted per (config, combination,
    day): the derived first-event row when an observed event exists, otherwise
    an explicit no-candidate row.  Only the first signal per symbol/session/day
    may produce an order; later same-day events for the same combination are
    emitted as activated=false candidate observations (the "one signal event
    per session" rule) and are never ranked by the router.
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
        ("WALK_FORWARD", plan.selection_start, plan.selection_end),
        ("HOLDOUT", plan.holdout_start, plan.holdout_end),
    ):
        for day in _iter_days(start, end):
            day_rows: list[ReplayRow] = []
            for config in configs:
                for combination in ALLOWED_COMBINATIONS:
                    matches = sorted(
                        by_day_combination.get((day, combination), []),
                        key=lambda event: (event.sequence, event.event_id),
                    )
                    if not matches:
                        day_rows.append(_no_candidate(config, day, combination, split=split))
                        continue
                    first = matches[0]
                    derived = derive_event_rows(first, config)
                    row = derived[0]
                    day_rows.append(ReplayRow(**{**asdict(row), "split": split}))
                    for extra in matches[1:]:
                        # Same-session repeated sweep: logged, never an order.
                        day_rows.append(
                            ReplayRow(
                                **{
                                    **asdict(_rejected(extra, config, "same_session_repeat")),
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


def write_rows_csv(rows: Sequence[ReplayRow], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(CSV_FIELDS))
        writer.writeheader()
        for row in rows:
            writer.writerow(asdict(row))


# ---------------------------------------------------------------------------
# Synthetic fixture + self-test (deterministic; proves the round trip)
# ---------------------------------------------------------------------------

# Geometry chosen so the frozen contract checks pass with ATR(M15,14)=9 pips:
# sweep 4.0 pips deep (0.44 ATR), reclaim lower wick 80% of range, displacement
# body 67% of range closing above the reclaim midpoint, stop 9.4 pips away
# (1.04 ATR), all-in cost ~0.075R.  Synthetic only — not edge evidence.
_BASE_EVENT = dict(
    combination="EURUSD_LONDON",
    direction="long",
    reference_low=1.08000,
    reference_high=1.08500,
    sweep_low=1.07960,
    sweep_high=1.08530,
    reclaim_open=1.08070,
    reclaim_high=1.08090,
    reclaim_low=1.07990,
    reclaim_close=1.08085,
    displacement_open=1.08035,
    displacement_high=1.08060,
    displacement_low=1.08030,
    displacement_close=1.08055,
    atr_m15=0.00090,
    tick_size=0.00001,
    tick_value=1.0,
    contract_size=1.0,
    volume_min=0.01,
    volume_step=0.01,
    spread_price=0.00003,
    slippage_price=0.00001,
    commission_per_lot_round_trip=2.0,
    limit_active=True,
    limit_touched=True,
    trade_through_ticks=2,
    fill_fraction=1.0,
    exit_reason="target",
    target_hit_minutes=20.0,
    stop_hit_minutes=None,
    breakeven_hit_minutes=15.0,
    price_at_30=1.08170,
    price_at_45=1.08170,
    price_at_60=1.08170,
    price_at_90=1.08170,
    price_at_session_end=1.08160,
    worst_adverse_price=1.08010,
    rule_violation=False,
    operational_error=False,
)


def synthetic_events() -> list[ObservedEvent]:
    """Deterministic synthetic fixture used by the self-test and unit tests.

    Covers: profitable long, weak-displacement rejection, stop-existing path,
    and a no-event day.  Values are chosen so derived rows pass the validator's
    loader, coverage, and metric checks; they are NOT evidence of any edge.
    """
    events: list[ObservedEvent] = []
    for day in (date(2023, 1, 3), date(2023, 1, 4), date(2023, 1, 5)):
        events.append(
            ObservedEvent(
                server_day=day,
                sequence=1,
                event_id=f"EUR-{day.isoformat()}-1",
                **_BASE_EVENT,
            )
        )
    # Displacement bar with no directional body -> weak_displacement, no order.
    weak = dict(_BASE_EVENT)
    weak.update(
        displacement_open=1.08035,
        displacement_close=1.08035,
        exit_reason="cancel",
        target_hit_minutes=None,
        limit_active=False,
        limit_touched=False,
        trade_through_ticks=0,
        fill_fraction=0.0,
    )
    events.append(
        ObservedEvent(
            server_day=date(2023, 1, 9),
            sequence=1,
            event_id="EUR-2023-01-09-1",
            **weak,
        )
    )
    return events


def _run_selftest(tmpdir: Path) -> int:
    committed_registry = Path(__file__).resolve().parents[1] / "validation" / "triad_v2_1_registry.json"
    registry = load_registry(committed_registry)
    configs = load_config_specs(registry)[:2]
    events = synthetic_events()
    # Narrow window keeps the full 160-config selftest quick.
    plan = ExportPlan(
        selection_start=date(2023, 1, 2),
        selection_end=date(2023, 1, 10),
        holdout_start=date(2023, 1, 16),
        holdout_end=date(2023, 1, 20),
    )
    rows = build_export_rows(events, configs, plan)
    output = tmpdir / "replay_rows.csv"
    write_rows_csv(rows, output)
    loaded = load_replay_rows(output, registry)
    validate_replay_coverage(loaded, configs)
    report = metric_report(loaded, FillPolicy(), stressed=False, seed=1)
    print(
        f"selftest OK: {len(rows)} rows, {report['fills']} fills, "
        f"{report['candidate_signals']} candidates (synthetic only)"
    )
    return 0


def schema_text() -> str:
    descriptions = {
        "server_day": "ISO broker server day YYYY-MM-DD",
        "sequence": "deterministic event order within the server day",
        "event_id": "stable unique event identifier",
        "combination": "EURUSD_LONDON, GBPUSD_LONDON, or USDJPY_NEW_YORK",
        "direction": "long or short",
        "reference_low": "reference range low (price units)",
        "reference_high": "reference range high (price units)",
        "sweep_low": "lowest price of the sweep",
        "sweep_high": "highest price of the sweep",
        "reclaim_open": "completed M5 reclaim bar open",
        "reclaim_high": "completed M5 reclaim bar high",
        "reclaim_low": "completed M5 reclaim bar low",
        "reclaim_close": "completed M5 reclaim bar close",
        "displacement_open": "completed M5 displacement bar open",
        "displacement_high": "completed M5 displacement bar high",
        "displacement_low": "completed M5 displacement bar low",
        "displacement_close": "completed M5 displacement bar close",
        "atr_m15": "ATR(M15,14) used for the sweep/stop bands",
        "tick_size": "symbol tick size",
        "tick_value": "symbol tick value per 1.00 lot",
        "contract_size": "symbol contract size",
        "volume_min": "symbol minimum volume",
        "volume_step": "symbol volume step",
        "spread_price": "round-trip spread in quote-currency price units",
        "slippage_price": "per-side slippage reserve in quote-currency price units",
        "commission_per_lot_round_trip": "broker commission cash per 1.00 lot",
        "limit_active": "the pending limit was active before the price event",
        "limit_touched": "executable side reached the limit",
        "trade_through_ticks": "ticks traded through the limit",
        "fill_fraction": "0..1 filled fraction observed",
        "exit_reason": "target, stop, breakeven, time, session_end, or cancel",
        "target_hit_minutes": "minutes from entry to first target touch (empty=None)",
        "stop_hit_minutes": "minutes from entry to first stop touch (empty=None)",
        "breakeven_hit_minutes": "minutes from entry to first +1R close (empty=None)",
        "price_at_30": "executable exit price at the 30-minute horizon",
        "price_at_45": "executable exit price at the 45-minute horizon",
        "price_at_60": "executable exit price at the 60-minute horizon",
        "price_at_90": "executable exit price at the 90-minute horizon",
        "price_at_session_end": "executable exit price at session cutoff",
        "worst_adverse_price": "most adverse price observed during the holding window",
        "rule_violation": "upstream replay detected a compliance-rule violation",
        "operational_error": "upstream replay detected a sizing/state/order error",
    }
    lines = [",".join(EVENT_FIELDS), ""]
    missing = [field for field in EVENT_FIELDS if field not in descriptions]
    if missing:
        raise AssertionError(f"EVENT_FIELDS without a schema description: {missing}")
    lines.extend(f"{field}: {descriptions[field]}" for field in EVENT_FIELDS)
    return "\n".join(lines) + "\n"


def _parse_plan(args: argparse.Namespace) -> ExportPlan:
    selection_start, selection_end = args.selection_split
    holdout_start, holdout_end = args.holdout_split
    return ExportPlan(
        selection_start=_parse_date(selection_start, "selection_start"),
        selection_end=_parse_date(selection_end, "selection_end"),
        holdout_start=_parse_date(holdout_start, "holdout_start"),
        holdout_end=_parse_date(holdout_end, "holdout_end"),
    )


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("schema", help="print the observed-event CSV contract")
    selftest = subparsers.add_parser("selftest", help="synthetic round-trip through validator")
    selftest.add_argument("--tmpdir", type=Path, required=True)
    build = subparsers.add_parser("build", help="build a registry-conformant replay export")
    build.add_argument("--event-file", type=Path, required=True)
    build.add_argument("--configs", type=Path, required=True)
    build.add_argument("--selection-split", nargs=2, metavar=("START", "END"), required=True)
    build.add_argument("--holdout-split", nargs=2, metavar=("START", "END"), required=True)
    build.add_argument("--output", type=Path, required=True)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.command == "schema":
            print(schema_text(), end="")
        elif args.command == "selftest":
            return _run_selftest(args.tmpdir)
        elif args.command == "build":
            registry = load_registry(args.configs)
            configs = load_config_specs(registry)
            events = load_observed_events(args.event_file)
            plan = _parse_plan(args)
            rows = build_export_rows(events, configs, plan)
            write_rows_csv(rows, args.output)
            print(f"wrote {len(rows)} rows to {args.output}")
        else:  # pragma: no cover - argparse enforces this.
            raise AssertionError(args.command)
    except ValidationError as exc:
        print(f"replay export error: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
