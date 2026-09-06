"""Independent standard-library reference math for TRIAD-R revision 2.1.

This module is intentionally small and does not call MQL5.  It provides test
oracles for contract arithmetic and civil-time examples; it is not a backtest.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, time, timedelta, timezone
from decimal import Decimal, ROUND_FLOOR
from enum import Enum
from zoneinfo import ZoneInfo


@dataclass(frozen=True)
class Profile:
    risk_fraction: Decimal
    target_r: Decimal


PROFILES = {
    "A": Profile(Decimal("0.0040"), Decimal("1.50")),
    "B": Profile(Decimal("0.0035"), Decimal("1.75")),
    "C": Profile(Decimal("0.0030"), Decimal("2.00")),
    "D": Profile(Decimal("0.0025"), Decimal("2.50")),
}


class DayState(Enum):
    READY = "DAY_READY"
    SECOND_ELIGIBLE = "SECOND_ELIGIBLE_IF_SAFE"
    LOCKED = "DAY_LOCKED"


def hash_text(value: str, seed: int = 216_613_626) -> int:
    """Mirror the EA's 31-bit FNV-style terminal-state checksum for ASCII data."""
    value_hash = seed & 0xFFFFFFFF
    for character in value:
        value_hash ^= ord(character)
        value_hash = (value_hash * 16_777_619) & 0xFFFFFFFF
    return value_hash & 0x7FFFFFFF


def halt_latch_signature(config_hash: int, identity_hash: int, halt_value: int,
                         halt_reason_hash: int) -> int:
    """Reference signature for the dedicated persisted emergency-halt journal."""
    if halt_value not in (0, 1):
        raise ValueError("halt value must be binary")
    if not 0 <= halt_reason_hash <= 0x7FFFFFFF:
        raise ValueError("halt reason hash is outside the persisted range")
    if halt_value == 0 and halt_reason_hash != 0:
        raise ValueError("an unlocked halt journal cannot retain a reason")
    payload = (
        f"HALT_LATCH_V1|{config_hash}|{identity_hash}|"
        f"{halt_value}|{halt_reason_hash}"
    )
    return hash_text(payload)


def profile_cash(initial_balance: Decimal, profile_name: str) -> tuple[Decimal, Decimal]:
    profile = PROFILES[profile_name]
    risk = initial_balance * profile.risk_fraction
    nominal_winner = risk * profile.target_r
    return risk, nominal_winner


def active_risk_fraction(profile_name: str, drawdown_percent: Decimal) -> Decimal:
    """Return the declared fraction; raise at the emergency boundary."""
    if drawdown_percent >= Decimal("5"):
        raise ValueError("strategy shutdown")
    fraction = PROFILES[profile_name].risk_fraction
    if drawdown_percent >= Decimal("2"):
        fraction *= Decimal("0.5")
    return fraction


def next_day_state(completed_trade_nets: list[Decimal]) -> DayState:
    if not completed_trade_nets:
        return DayState.READY
    if len(completed_trade_nets) >= 2:
        return DayState.LOCKED
    return DayState.LOCKED if completed_trade_nets[0] > 0 else DayState.SECOND_ELIGIBLE


def profitable_day_result(midnight_balance: Decimal, midnight_equity: Decimal,
                          previous_day_balance: Decimal) -> Decimal:
    return min(midnight_balance, midnight_equity) - previous_day_balance


def firm_floors(phase_initial: Decimal, rollover_balance: Decimal,
                 rollover_equity: Decimal) -> tuple[Decimal, Decimal, Decimal]:
    overall = phase_initial * Decimal("0.90")
    daily = max(rollover_balance, rollover_equity) * Decimal("0.95")
    return overall, daily, max(overall, daily)


def firm_reserve(phase_initial: Decimal, reserve_percent: Decimal,
                 one_trade_slippage_reserve: Decimal) -> Decimal:
    return max(
        phase_initial * reserve_percent / Decimal("100"),
        Decimal("2") * max(Decimal("0"), one_trade_slippage_reserve),
    )


def round_volume_down(raw: Decimal, minimum: Decimal, maximum: Decimal,
                      step: Decimal) -> Decimal | None:
    if minimum <= 0 or maximum <= 0 or step <= 0:
        raise ValueError("invalid symbol volume properties")
    if maximum < minimum or raw < minimum:
        return None
    units = ((raw - minimum) / step).to_integral_value(rounding=ROUND_FLOOR)
    maximum_units = ((maximum - minimum) / step).to_integral_value(rounding=ROUND_FLOOR)
    return minimum + min(units, maximum_units) * step


def phase_target(initial_balance: Decimal, phase: int) -> Decimal:
    if phase == 1:
        return initial_balance * Decimal("1.10")
    if phase == 2:
        return initial_balance * Decimal("1.05")
    if phase == 3:
        return initial_balance * Decimal("1.10")
    raise ValueError("invalid phase")


def phase_locked(balance: Decimal, initial_balance: Decimal, phase: int,
                 dashboard_confirmed_days: int) -> tuple[bool, bool]:
    """Return (phase_complete, target_pending_days)."""
    at_target = balance >= phase_target(initial_balance, phase)
    return at_target and dashboard_confirmed_days >= 3, at_target and dashboard_confirmed_days < 3


def _local_to_utc(day: date, wall_time: time, zone_name: str) -> datetime:
    local = datetime.combine(day, wall_time, ZoneInfo(zone_name))
    return local.astimezone(timezone.utc)


def session_bounds_utc(kind: str, day: date) -> tuple[datetime, datetime, datetime, datetime]:
    """Return reference start/end and entry start/end as aware UTC values."""
    if kind == "london":
        return (
            _local_to_utc(day, time(0, 0), "Europe/London"),
            _local_to_utc(day, time(7, 0), "Europe/London"),
            _local_to_utc(day, time(7, 0), "Europe/London"),
            _local_to_utc(day, time(11, 0), "Europe/London"),
        )
    if kind == "new_york":
        entry_start = _local_to_utc(day, time(8, 30), "America/New_York")
        entry_end = _local_to_utc(day, time(11, 0), "America/New_York")
        london_day = entry_start.astimezone(ZoneInfo("Europe/London")).date()
        return (
            _local_to_utc(london_day, time(7, 0), "Europe/London"),
            _local_to_utc(london_day, time(13, 0), "Europe/London"),
            entry_start,
            entry_end,
        )
    raise ValueError("unknown session")


def utc_to_server(utc_value: datetime, offset_hours: int = 3) -> datetime:
    if utc_value.tzinfo is None:
        raise ValueError("UTC datetime must be timezone-aware")
    # MQL5 server datetimes are represented as wall-clock epoch values.  Keep an
    # aware UTC object here while shifting its displayed civil fields by +03:00.
    return utc_value + timedelta(hours=offset_hours)
