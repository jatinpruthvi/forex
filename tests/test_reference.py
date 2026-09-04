from __future__ import annotations

import unittest
from datetime import date, datetime, timezone
from decimal import Decimal

from triad_reference import (
    DayState,
    PROFILES,
    active_risk_fraction,
    firm_floors,
    firm_reserve,
    next_day_state,
    phase_locked,
    profitable_day_result,
    profile_cash,
    round_volume_down,
    session_bounds_utc,
    utc_to_server,
)


D = Decimal


class ProfileMathTests(unittest.TestCase):
    def test_paired_profile_cash_math_on_2500(self) -> None:
        expected = {
            "A": (D("10.0000"), D("15.000000")),
            "B": (D("8.7500"), D("15.312500")),
            "C": (D("7.5000"), D("15.000000")),
            "D": (D("6.2500"), D("15.625000")),
        }
        for name, values in expected.items():
            with self.subTest(profile=name):
                self.assertEqual(profile_cash(D("2500"), name), values)
                self.assertLessEqual(PROFILES[name].risk_fraction, D("0.0040"))

    def test_drawdown_has_one_half_risk_tier_and_shutdown(self) -> None:
        self.assertEqual(active_risk_fraction("A", D("0")), D("0.0040"))
        self.assertEqual(active_risk_fraction("A", D("1.9999")), D("0.0040"))
        self.assertEqual(active_risk_fraction("A", D("2.0")), D("0.00200"))
        self.assertEqual(active_risk_fraction("D", D("4.9999")), D("0.00125"))
        with self.assertRaises(ValueError):
            active_risk_fraction("A", D("5.0"))

    def test_nominal_winner_is_not_assumed_to_be_qualifying_cash(self) -> None:
        # The nominal figures exceed $12.50, but execution/rounding are absent
        # from this reference calculation and therefore cannot prove a day.
        for name in PROFILES:
            _, nominal = profile_cash(D("2500"), name)
            self.assertGreater(nominal, D("12.50"))


class DailyStateTests(unittest.TestCase):
    def test_first_net_positive_locks_day(self) -> None:
        self.assertEqual(next_day_state([D("0.01")]), DayState.LOCKED)
        self.assertEqual(next_day_state([D("12.49")]), DayState.LOCKED)

    def test_zero_or_loss_allows_only_second_trade(self) -> None:
        self.assertEqual(next_day_state([]), DayState.READY)
        self.assertEqual(next_day_state([D("0")]), DayState.SECOND_ELIGIBLE)
        self.assertEqual(next_day_state([D("-10")]), DayState.SECOND_ELIGIBLE)
        self.assertEqual(next_day_state([D("-10"), D("15")]), DayState.LOCKED)

    def test_profitable_day_uses_lower_midnight_value(self) -> None:
        self.assertEqual(profitable_day_result(D("2515"), D("2514"), D("2500")), D("14"))
        self.assertEqual(profitable_day_result(D("2515"), D("2510"), D("2500")), D("10"))

    def test_phase_target_requires_dashboard_days(self) -> None:
        self.assertEqual(phase_locked(D("2750"), D("2500"), 1, 2), (False, True))
        self.assertEqual(phase_locked(D("2750"), D("2500"), 1, 3), (True, False))
        self.assertEqual(phase_locked(D("2625"), D("2500"), 2, 3), (True, False))
        self.assertEqual(phase_locked(D("2624.99"), D("2500"), 2, 3), (False, False))


class FloorAndVolumeTests(unittest.TestCase):
    def test_firm_floor_math(self) -> None:
        self.assertEqual(
            firm_floors(D("2500"), D("2520"), D("2510")),
            (D("2250.00"), D("2394.00"), D("2394.00")),
        )
        self.assertEqual(
            firm_floors(D("2500"), D("2300"), D("2400")),
            (D("2250.00"), D("2280.00"), D("2280.00")),
        )

    def test_floor_reserve_is_greater_of_percent_and_twice_slippage(self) -> None:
        self.assertEqual(firm_reserve(D("2500"), D("0.5"), D("2")), D("12.5"))
        self.assertEqual(firm_reserve(D("2500"), D("0.5"), D("8")), D("16"))

    def test_volume_always_rounds_down(self) -> None:
        self.assertEqual(round_volume_down(D("0.0199"), D("0.01"), D("100"), D("0.01")), D("0.01"))
        self.assertEqual(round_volume_down(D("1.234"), D("0.01"), D("100"), D("0.001")), D("1.234"))
        self.assertEqual(round_volume_down(D("101"), D("0.01"), D("100"), D("0.01")), D("100"))
        self.assertEqual(round_volume_down(D("2"), D("0.01"), D("1.005"), D("0.01")), D("1.00"))
        self.assertEqual(round_volume_down(D("0.08"), D("0.03"), D("1.00"), D("0.02")), D("0.07"))
        self.assertIsNone(round_volume_down(D("0.0099"), D("0.01"), D("100"), D("0.01")))


class CivilTimeTests(unittest.TestCase):
    def test_london_winter_and_summer(self) -> None:
        winter = session_bounds_utc("london", date(2026, 1, 15))
        summer = session_bounds_utc("london", date(2026, 7, 15))
        self.assertEqual(winter[0], datetime(2026, 1, 15, 0, 0, tzinfo=timezone.utc))
        self.assertEqual(winter[2], datetime(2026, 1, 15, 7, 0, tzinfo=timezone.utc))
        self.assertEqual(summer[0], datetime(2026, 7, 14, 23, 0, tzinfo=timezone.utc))
        self.assertEqual(summer[2], datetime(2026, 7, 15, 6, 0, tzinfo=timezone.utc))

    def test_us_uk_dst_mismatch_week_is_independent(self) -> None:
        # US DST began 8 March 2026; UK DST did not begin until 29 March.
        bounds = session_bounds_utc("new_york", date(2026, 3, 9))
        self.assertEqual(bounds[0], datetime(2026, 3, 9, 7, 0, tzinfo=timezone.utc))
        self.assertEqual(bounds[1], datetime(2026, 3, 9, 13, 0, tzinfo=timezone.utc))
        self.assertEqual(bounds[2], datetime(2026, 3, 9, 12, 30, tzinfo=timezone.utc))
        self.assertEqual(bounds[3], datetime(2026, 3, 9, 15, 0, tzinfo=timezone.utc))

    def test_after_uk_dst_transition_london_reference_shifts_only_london(self) -> None:
        bounds = session_bounds_utc("new_york", date(2026, 3, 30))
        self.assertEqual(bounds[0], datetime(2026, 3, 30, 6, 0, tzinfo=timezone.utc))
        self.assertEqual(bounds[1], datetime(2026, 3, 30, 12, 0, tzinfo=timezone.utc))
        self.assertEqual(bounds[2], datetime(2026, 3, 30, 12, 30, tzinfo=timezone.utc))

    def test_utc_to_server_is_fixed_plus_three(self) -> None:
        utc_value = datetime(2026, 3, 9, 12, 30, tzinfo=timezone.utc)
        self.assertEqual(utc_to_server(utc_value), datetime(2026, 3, 9, 15, 30, tzinfo=timezone.utc))


if __name__ == "__main__":
    unittest.main()
