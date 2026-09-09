"""Regression tests for defects found in the P2/P0 tooling review.

Each test here encodes a specific finding; see
``THE5ERS-STRATEGY-IMPROVEMENT-SUGGESTION-REVIEW.md`` Appendix D/E notes.
"""
from __future__ import annotations

import csv
import tempfile
import unittest
from dataclasses import asdict
from datetime import date
from pathlib import Path

from tools import replay_export as re
from tools import triad_ablation as abl
from tools.triad_validation import ValidationError

from tests.test_ablation_scaffold import _event, _write_event_csv


class BreakevenConsistencyTests(unittest.TestCase):
    """net_r and net_cash must tell the same story for a breakeven cap.

    The old frozen derive priced net cash from the raw path exit even when the
    confirmed-1R cap applied, so a trade could report net_r < 0 (capped at
    entry, net of costs) while net_cash_full > 0 (raw path price).  The EA
    actually moves the stop to entry, so the effective fill price is entry.
    """

    def _time_exit_below_one_r(self) -> re.ObservedEvent:
        payload = dict(re._BASE_EVENT)
        payload.pop("combination")
        payload.update(
            exit_reason="time",
            target_hit_minutes=None,
            price_at_30=1.08070,
            price_at_45=1.08075,
            price_at_60=1.08080,
            price_at_90=1.08085,
            price_at_session_end=1.08080,
            breakeven_hit_minutes=15.0,
        )
        return re.ObservedEvent(
            server_day=date(2023, 1, 3),
            sequence=1,
            event_id="E-BE",
            combination="EURUSD_LONDON",
            **payload,
        )

    def test_breakeven_cap_prices_cash_at_entry(self):
        config = re.ConfigSpec(
            config_id="BE-TEST",
            profile="A",
            risk_fraction=0.004,
            target_r=1.5,
            time_stop_minutes=45,
            move_stop_to_entry_after_confirmed_1r=True,
        )
        row = re.derive_event_rows(self._time_exit_below_one_r(), config)[0]
        self.assertLess(row.net_r, 0.0, "breakeven cap must show net-of-costs R")
        self.assertLess(
            row.net_cash_full, 0.0,
            "breakeven cap must price net cash at entry (net of costs), not at the raw path exit",
        )
        implied_r = row.net_cash_full / row.risk_cash_full
        self.assertAlmostEqual(implied_r, row.net_r, places=4)
        # Exactly the modeled round-trip cost times the rounded volume.
        cost_cash = (
            100000.0 * (re._BASE_EVENT["spread_price"] + 2.0 * re._BASE_EVENT["slippage_price"])
            + re._BASE_EVENT["commission_per_lot_round_trip"]
        ) * (row.risk_cash_full / (100000.0 * 0.00094))
        self.assertAlmostEqual(row.net_cash_full, -cost_cash, places=2)

    def test_stop_before_breakeven_confirmation_is_not_capped(self):
        # The +1R "confirmation" at minute 15 cannot move a stop that was
        # already hit at minute 10; the raw stop outcome must stand.
        payload = dict(re._BASE_EVENT)
        payload.pop("combination")
        payload.update(
            exit_reason="stop",
            stop_hit_minutes=10.0,
            target_hit_minutes=None,
            breakeven_hit_minutes=15.0,
        )
        event = re.ObservedEvent(
            server_day=date(2023, 1, 3), sequence=1,
            event_id="E-BE-LATE", combination="EURUSD_LONDON", **payload,
        )
        config = re.ConfigSpec(
            config_id="BE-TEST", profile="A", risk_fraction=0.004,
            target_r=1.5, time_stop_minutes=45,
            move_stop_to_entry_after_confirmed_1r=True,
        )
        row = re.derive_event_rows(event, config)[0]
        # Raw stop = 1R gross of costs -> roughly +0.925R, cash positive.
        self.assertGreater(row.net_r, 0.0)
        self.assertGreater(row.net_cash_full, 0.0)

    def test_stop_after_breakeven_confirmation_is_capped(self):
        payload = dict(re._BASE_EVENT)
        payload.pop("combination")
        payload.update(
            exit_reason="stop",
            stop_hit_minutes=10.0,
            target_hit_minutes=None,
            breakeven_hit_minutes=5.0,
        )
        event = re.ObservedEvent(
            server_day=date(2023, 1, 3), sequence=1,
            event_id="E-BE-LATE2", combination="EURUSD_LONDON", **payload,
        )
        config = re.ConfigSpec(
            config_id="BE-TEST", profile="A", risk_fraction=0.004,
            target_r=1.5, time_stop_minutes=45,
            move_stop_to_entry_after_confirmed_1r=True,
        )
        row = re.derive_event_rows(event, config)[0]
        self.assertLess(row.net_r, 0.0, "capped exit must be net of costs")
        self.assertAlmostEqual(
            row.net_cash_full / row.risk_cash_full, row.net_r, places=3
        )

    def test_non_breakeven_config_logs_raw_path(self):
        config = re.ConfigSpec(
            config_id="NO-BE",
            profile="A",
            risk_fraction=0.004,
            target_r=1.5,
            time_stop_minutes=45,
            move_stop_to_entry_after_confirmed_1r=False,
        )
        row = re.derive_event_rows(self._time_exit_below_one_r(), config)[0]
        self.assertGreater(row.net_r, 0.0)
        self.assertGreater(row.net_cash_full, 0.0)
        self.assertAlmostEqual(row.net_cash_full / row.risk_cash_full, row.net_r, places=4)


class CashAndRAgreementTests(unittest.TestCase):
    """Every exit path must produce net_cash/risk == net_r internally."""

    def test_all_exit_paths_agree_for_both_breakeven_policies(self):
        variants = {
            "target": {"exit_reason": "target", "target_hit_minutes": 20.0, "stop_hit_minutes": None},
            "stop": {"exit_reason": "stop", "stop_hit_minutes": 10.0, "target_hit_minutes": None},
            "time": {
                "exit_reason": "time", "target_hit_minutes": None, "stop_hit_minutes": None,
                "price_at_30": 1.08075, "price_at_45": 1.08075,
                "price_at_60": 1.08075, "price_at_90": 1.08075,
            },
            "session_end": {
                "exit_reason": "session_end", "target_hit_minutes": None,
                "stop_hit_minutes": None, "price_at_session_end": 1.08040,
            },
        }
        for be in (False, True):
            for name, changes in variants.items():
                payload = dict(re._BASE_EVENT)
                payload.pop("combination")
                payload.update(changes)
                if name == "time":
                    payload["breakeven_hit_minutes"] = 15.0 if be else None
                elif name == "session_end":
                    # Below +1R so a BE config applies the cap; above entry.
                    payload["breakeven_hit_minutes"] = 15.0 if be else None
                else:
                    payload["breakeven_hit_minutes"] = 15.0 if be else None
                event = re.ObservedEvent(
                    server_day=date(2023, 1, 3), sequence=1,
                    event_id=f"E-{name}-{be}", combination="EURUSD_LONDON", **payload,
                )
                config = re.ConfigSpec(
                    config_id="INV", profile="A", risk_fraction=0.004,
                    target_r=1.5, time_stop_minutes=45,
                    move_stop_to_entry_after_confirmed_1r=be,
                )
                row = re.derive_event_rows(event, config)[0]
                if not row.activation_ok or row.risk_cash_full <= 0.0:
                    continue
                implied = row.net_cash_full / row.risk_cash_full
                self.assertAlmostEqual(
                    implied, row.net_r, places=3,
                    msg=f"{name} be={be}: cash {implied:.6f}R != net_r {row.net_r:.6f}R",
                )


class StopSideTests(unittest.TestCase):
    def test_stop_must_be_on_protective_side(self):
        # Long event whose displacement midpoint sits BELOW the computed stop.
        # Earlier geometry gates are bypassed by removing the midpoint filter,
        # so the only thing left to catch this is the side guard.
        payload = dict(re._BASE_EVENT)
        payload.pop("combination")
        payload.update(
            reference_low=1.08000,
            reference_high=1.08100,
            sweep_low=1.07995,
            sweep_high=1.08120,
            reclaim_open=1.08020,
            reclaim_high=1.08040,
            reclaim_low=1.07990,
            reclaim_close=1.08025,
            displacement_open=1.07990,
            displacement_high=1.07992,
            displacement_low=1.07978,
            displacement_close=1.07980,
        )
        event = re.ObservedEvent(
            server_day=date(2023, 1, 3),
            sequence=1,
            event_id="E-SIDE",
            combination="EURUSD_LONDON",
            **payload,
        )
        entry, stop, rejection = re.resolve_entry(
            event, re.EntrySpec(require_midpoint=False)
        )
        self.assertIsNone(entry)
        self.assertIsNone(stop)
        self.assertEqual(rejection, "stop_on_wrong_side")
        # And through the row builder it must never become an order.
        row = re.derive_event_rows(event, abl.fixed_config_spec("SIDE"))[0]
        self.assertTrue(row.candidate)
        self.assertFalse(row.activation_ok)
        self.assertEqual(row.risk_cash_full, 0.0)


class LoaderErrorHandlingTests(unittest.TestCase):
    def test_non_integer_trade_through_ticks_is_a_validation_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "events.csv"
            _write_event_csv(path, [_event(date(2023, 1, 3), "E1")])
            with path.open("r", encoding="utf-8", newline="") as handle:
                rows = list(csv.DictReader(handle))
            rows[0]["trade_through_ticks"] = "not-a-number"
            with path.open("w", encoding="utf-8", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=list(re.EVENT_FIELDS))
                writer.writeheader()
                writer.writerows(rows)
            with self.assertRaises(ValidationError):
                re.load_observed_events(path)

    def test_negative_trade_through_ticks_is_a_validation_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "events.csv"
            _write_event_csv(path, [_event(date(2023, 1, 3), "E1")])
            with path.open("r", encoding="utf-8", newline="") as handle:
                rows = list(csv.DictReader(handle))
            rows[0]["trade_through_ticks"] = "-1"
            with path.open("w", encoding="utf-8", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=list(re.EVENT_FIELDS))
                writer.writeheader()
                writer.writerows(rows)
            with self.assertRaises(ValidationError):
                re.load_observed_events(path)


class DecideRobustnessTests(unittest.TestCase):
    def test_decide_without_paired_days_does_not_crash(self):
        empty = {
            "observed_mean_difference_r": None,
            "familywise_adjusted_interval": [None, None],
            "variant_fills": 0.0,
            "baseline_fills": 0.0,
        }
        decision, why = abl.decide(
            abl.ABL_RUNS[1], [], [], empty, abl.AblationSettings(), 0.0
        )
        self.assertEqual(decision, "not_adopted")
        self.assertTrue(any("no paired" in line for line in why))

    def test_decide_with_none_interval_does_not_crash(self):
        paired = {
            "observed_mean_difference_r": 0.01,
            "familywise_adjusted_interval": [None, None],
            "variant_fills": 200.0,
            "baseline_fills": 100.0,
        }
        decision, _ = abl.decide(
            abl.ABL_RUNS[1], [], [], paired, abl.AblationSettings(), 100.0
        )
        self.assertIn(decision, {"not_adopted"})


class PreregistrationSettingsTests(unittest.TestCase):
    def test_registry_declares_holdout_fill_floor_and_no_dead_config(self):
        registry = abl.build_registry()
        decision = registry["decision"]
        self.assertEqual(decision["minimum_holdout_fills"], 300)
        self.assertNotIn("opportunity_floor_fraction", decision)

    def test_schema_output_is_clean(self):
        text = abl.schema_text()
        self.assertIn("build: python3 tools/triad_ablation.py build", text)
        self.assertNotIn('"\\n', text)  # no stray quote artifact

    def test_lattice_never_returns_below_minimum(self):
        self.assertEqual(re._max_inclusive_multiple(0.01, 0.01, 0.009999999), 0.0)
        self.assertEqual(re._max_inclusive_multiple(0.01, 0.01, 0.01 + 1e-12), 0.01)
        self.assertEqual(re._max_inclusive_multiple(0.01, 0.02, 0.055), 0.05)


class R3HoldoutFloorTests(unittest.TestCase):
    def test_holdout_fill_floor_blocks_confirmation(self):
        # Selection says V1 is superior, but the fresh-window evidence is too
        # thin (120 baseline fills < 300): R3 must refuse to confirm.
        from tests.test_ablation_scaffold import AblationEvaluateEndToEndTests

        case = AblationEvaluateEndToEndTests()
        with tempfile.TemporaryDirectory() as tmp:
            _, report = case._scenario(Path(tmp), 50, 10, holdout_base_days=40)
            confirmation = report["holdout_confirmations"]["ABL-V1-SIMPLER-RECLAIM"]
            self.assertFalse(confirmation["confirmed"])
            self.assertLess(confirmation["baseline_holdout_fills"], 300)
            self.assertEqual(report["outcome"]["result"], "NO_CHANGE_SUPPORTED")



class BootstrapIntervalInvariantTests(unittest.TestCase):
    """Adjusted (Bonferroni) interval must contain the ordinary interval."""

    def test_adjusted_interval_contains_ordinary(self):
        import random as rnd
        from tools.triad_ablation import paired_bootstrap_interval
        rng = rnd.Random(7)
        days = [date.fromordinal(date(2023, 1, 1).toordinal() + i) for i in range(40)]
        differences = []
        for index, day in enumerate(days):
            for _combination in ("EURUSD_LONDON", "GBPUSD_LONDON"):
                diff = rng.uniform(-0.3, 0.4) + (0.1 if index % 5 == 0 else 0.0)
                differences.append((day, _combination, diff, 1, 1, diff, 0.0))
        result = paired_bootstrap_interval(
            differences, samples=300, block_days=5, alpha=0.05, family_size=5, seed=3
        )
        ordinary = result["ordinary_interval"]
        adjusted = result["familywise_adjusted_interval"]
        self.assertLessEqual(adjusted[0], ordinary[0])
        self.assertGreaterEqual(adjusted[1], ordinary[1])
        # Larger family must widen the adjusted interval.
        wide = paired_bootstrap_interval(
            differences, samples=300, block_days=5, alpha=0.05, family_size=20, seed=3
        )
        self.assertLessEqual(wide["familywise_adjusted_interval"][0], adjusted[0])
        self.assertGreaterEqual(wide["familywise_adjusted_interval"][1], adjusted[1])



if __name__ == "__main__":
    unittest.main()


class AllInRiskCeilingTests(unittest.TestCase):
    """V2 section 6: volume is sized so ALL-IN loss (stop + slippage + commission) fits the budget."""

    def _ceiling_event(self):
        payload = dict(re._BASE_EVENT)
        payload.pop("combination")
        payload.update(
            atr_m15=0.0007,
            reference_low=1.08000, reference_high=1.08100,
            sweep_low=1.07970, sweep_high=1.08090,
            reclaim_open=1.07985, reclaim_high=1.07995, reclaim_low=1.07965, reclaim_close=1.07990,
            displacement_open=1.08000, displacement_high=1.08050, displacement_low=1.07990,
            displacement_close=1.08040,
            spread_price=0.00002, slippage_price=0.00001, commission_per_lot_round_trip=1.0,
        )
        return re.ObservedEvent(
            server_day=date(2023, 1, 3), sequence=1, event_id="CEIL",
            combination="EURUSD_LONDON", **payload,
        )

    def test_lot_size_keeps_all_in_loss_inside_budget(self):
        event = self._ceiling_event()
        entry, stop, _ = re.resolve_entry(event, re.BASELINE_ENTRY_SPEC)
        row = re.derive_event_rows(event, abl.fixed_config_spec("CEIL"))[0]
        self.assertTrue(row.activation_ok)
        per_lot_pure = 100000.0 * abs(entry - stop)
        per_lot_all_in = per_lot_pure + 100000.0 * event.slippage_price + event.commission_per_lot_round_trip
        lots = row.risk_cash_full / per_lot_pure
        self.assertLessEqual(lots * per_lot_all_in, 2500.0 * 0.004 + 1e-6)
        # The old pure-risk sizing picked 0.17 lots ($10.03 all-in).
        self.assertEqual(round(lots, 2), 0.16)
        self.assertAlmostEqual(row.risk_cash_full, 0.16 * per_lot_pure, places=4)

    def test_minimum_volume_that_breaches_ceiling_is_skipped(self):
        # Tiny risk budget: the minimum lattice volume's all-in loss exceeds it.
        payload = dict(re._BASE_EVENT)
        payload.pop("combination")
        payload.update(
            displacement_open=1.08020, displacement_close=1.08030,
            displacement_high=1.08035, displacement_low=1.08010,
            reclaim_open=1.08050, reclaim_high=1.08060, reclaim_low=1.08040, reclaim_close=1.08055,
            atr_m15=0.0009,
            spread_price=0.00002, slippage_price=0.00001, commission_per_lot_round_trip=1.0,
        )
        event = re.ObservedEvent(
            server_day=date(2023, 1, 3), sequence=1, event_id="TINY",
            combination="EURUSD_LONDON", **payload,
        )
        row = re.derive_event_rows(event, abl.fixed_config_spec("TINY"), initial_balance=50.0)[0]
        # Budget = 50 * 0.004 = $0.20 < one lot's all-in -> no order.
        self.assertTrue(row.candidate)
        self.assertFalse(row.activation_ok)
        self.assertEqual(row.risk_cash_full, 0.0)


class StressedCashConsistencyTests(unittest.TestCase):
    def test_stressed_cash_totals_include_stress_cost(self):
        payload = dict(re._BASE_EVENT)
        payload.pop("combination")
        event = re.ObservedEvent(
            server_day=date(2023, 1, 3), sequence=1, event_id="STRESS",
            combination="EURUSD_LONDON", **payload,
        )
        row = re.derive_event_rows(event, abl.fixed_config_spec("ABL-V0-BASELINE"))[0]
        from tools.triad_validation import FillPolicy, apply_fill_policy, metric_report
        # Zero miss rate isolates the stress COST consistency from the stress
        # miss lottery; extra_cost_r still applies.
        policy = FillPolicy(stressed_profitable_limit_miss_fraction=0.0)
        normal = metric_report([row], policy, stressed=False, seed=1)
        stressed = metric_report([row], policy, stressed=True, seed=1)
        self.assertNotEqual(stressed["net_cash_total_full"], normal["net_cash_total_full"])
        trade = apply_fill_policy(row, policy, stressed=True, seed=1)
        self.assertIsNotNone(trade)
        self.assertAlmostEqual(
            stressed["net_cash_total_full"], trade.cash_result(False), places=6
        )
        self.assertAlmostEqual(
            stressed["all_in_cost_r_mean"],
            row.spread_r + row.slippage_r + row.commission_r + trade.extra_cost_r,
            places=6,
        )


class ExitReasonHandlingTests(unittest.TestCase):
    def _base(self, **changes):
        payload = dict(re._BASE_EVENT)
        payload.pop("combination")
        payload.update(changes)
        return re.ObservedEvent(
            server_day=date(2023, 1, 3), sequence=1, event_id="X",
            combination="EURUSD_LONDON", **payload,
        )

    def test_breakeven_exit_reason_is_honored(self):
        event = self._base(
            exit_reason="breakeven", target_hit_minutes=None, stop_hit_minutes=None,
            breakeven_hit_minutes=15.0,
            price_at_30=1.08400, price_at_45=1.08400, price_at_60=1.08400,
            price_at_90=1.08400, price_at_session_end=1.08400,
        )
        config = re.ConfigSpec("BE", "A", 0.004, 1.5, 45, True)
        row = re.derive_event_rows(event, config)[0]
        cost_r = row.spread_r + row.slippage_r + row.commission_r
        self.assertAlmostEqual(row.net_r, -cost_r, places=5)
        self.assertLess(row.net_cash_full, 0.0)
        self.assertAlmostEqual(row.net_cash_full / row.risk_cash_full, row.net_r, places=3)

    def test_cancel_never_counts_as_a_fill(self):
        # Contradictory upstream row: order was "cancelled" yet claims a fill.
        event = self._base(
            exit_reason="cancel", target_hit_minutes=None, stop_hit_minutes=None,
            breakeven_hit_minutes=None, limit_active=True, limit_touched=True,
            trade_through_ticks=2, fill_fraction=1.0,
            price_at_30=1.08400, price_at_45=1.08400, price_at_60=1.08400,
            price_at_90=1.08400, price_at_session_end=1.08400,
        )
        row = re.derive_event_rows(event, re.ConfigSpec("C", "A", 0.004, 1.5, 45, False))[0]
        self.assertTrue(row.candidate)
        self.assertTrue(row.activation_ok)
        self.assertFalse(row.limit_touched)
        self.assertEqual(row.net_r, 0.0)
        self.assertEqual(row.net_cash_full, 0.0)
        self.assertEqual(row.risk_cash_full, 0.0)
        from tools.triad_validation import FillPolicy, apply_fill_policy
        self.assertIsNone(apply_fill_policy(row, FillPolicy(), stressed=False, seed=1))

    def test_unsupported_time_stop_horizon_raises_validation_error(self):
        event = self._base(
            exit_reason="time", target_hit_minutes=None, stop_hit_minutes=None
        )
        config = re.ConfigSpec("BAD", "A", 0.004, 1.5, 20, False)
        with self.assertRaises(ValidationError):
            re.derive_event_rows(event, config)

    def test_resolve_exit_refuses_cancelled_order(self):
        # Defense in depth: even a direct caller must not price a cancelled
        # pending order as a time-stop or session-end fill.
        event = self._base(
            exit_reason="cancel", target_hit_minutes=None, stop_hit_minutes=None,
            breakeven_hit_minutes=None,
        )
        entry, stop, _ = re.resolve_entry(event, re.BASELINE_ENTRY_SPEC)
        prices = re.resolve_prices(event, entry, stop)
        config = re.ConfigSpec("C", "A", 0.004, 1.5, 45, False)
        with self.assertRaises(ValidationError):
            re.resolve_exit(event, config, entry, stop, prices)

    def test_loader_requires_breakeven_timestamp(self):
        import tempfile
        from tests.test_ablation_scaffold import _write_event_csv
        event = self._base(
            exit_reason="breakeven", target_hit_minutes=None, stop_hit_minutes=None,
            breakeven_hit_minutes=None,
        )
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "events.csv"
            _write_event_csv(path, [event])
            with self.assertRaises(ValidationError):
                re.load_observed_events(path)


class RandomizedPropertyTests(unittest.TestCase):
    """Deterministic randomized invariants across many events and configs."""

    SAMPLES = 120

    def _random_event(self, rng, index):
        side = "long" if rng.random() < 0.5 else "short"
        base = 1.0800 if side == "long" else 1.0900
        atr = round(rng.uniform(0.0006, 0.0012), 7)
        if side == "long":
            reference_low = base
            reference_high = base + rng.uniform(0.003, 0.006)
            depth = atr * rng.uniform(0.08, 0.45)
            sweep_low = reference_low - depth
            sweep_high = reference_high + 0.0003
            low_anchor = reference_low - atr * rng.uniform(0.05, 0.4)
            reclaim_low = low_anchor
            reclaim_high = reclaim_low + rng.uniform(0.0002, 0.0006)
            reclaim_open = reclaim_low + rng.uniform(0.00005, 0.0003)
            reclaim_close = reclaim_low + rng.uniform(0.00005, 0.0003)
            displacement_low = reclaim_low + rng.uniform(-0.0002, 0.0002)
            displacement_high = displacement_low + rng.uniform(0.0003, 0.0009)
            displacement_open = displacement_low + rng.uniform(0.00005, 0.0006)
            displacement_close = displacement_high - rng.uniform(0.00005, 0.0005)
            if displacement_close <= displacement_open:
                displacement_close, displacement_open = displacement_open, displacement_close
            mid = (displacement_open + displacement_close) / 2.0
            sweep_extreme = sweep_low
        else:
            reference_high = base
            reference_low = base - rng.uniform(0.003, 0.006)
            depth = atr * rng.uniform(0.08, 0.45)
            sweep_high = reference_high + depth
            sweep_low = reference_low - 0.0003
            high_anchor = reference_high + atr * rng.uniform(0.05, 0.4)
            reclaim_high = high_anchor
            reclaim_low = reclaim_high - rng.uniform(0.0002, 0.0006)
            reclaim_open = reclaim_high - rng.uniform(0.00005, 0.0003)
            reclaim_close = reclaim_high - rng.uniform(0.00005, 0.0003)
            displacement_high = reclaim_high + rng.uniform(-0.0002, 0.0002)
            displacement_low = displacement_high - rng.uniform(0.0003, 0.0009)
            displacement_open = displacement_high - rng.uniform(0.00005, 0.0006)
            displacement_close = displacement_low + rng.uniform(0.00005, 0.0005)
            if displacement_close >= displacement_open:
                displacement_close, displacement_open = displacement_open, displacement_close
            mid = (displacement_open + displacement_close) / 2.0
            sweep_extreme = sweep_high
        stop = (sweep_low - 0.10 * atr) if side == "long" else (sweep_high + 0.10 * atr)
        stop_distance = abs(mid - stop)
        # Force the stop-distance band by repositioning mid via displacement values.
        target_stop_atr = rng.uniform(0.65, 1.45)
        desired_distance = target_stop_atr * atr
        shift = desired_distance - stop_distance
        displacement_open += shift
        displacement_close += shift
        mid = (displacement_open + displacement_close) / 2.0
        stop_distance = abs(mid - stop)
        event = re.ObservedEvent(
            server_day=date(2023, 1, 3 + index % 20), sequence=index + 1,
            event_id=f"R{index}", combination="EURUSD_LONDON", direction=side,
            reference_low=reference_low, reference_high=reference_high,
            sweep_low=sweep_low, sweep_high=sweep_high,
            reclaim_open=reclaim_open, reclaim_high=reclaim_high,
            reclaim_low=reclaim_low, reclaim_close=reclaim_close,
            displacement_open=displacement_open, displacement_high=displacement_high,
            displacement_low=displacement_low, displacement_close=displacement_close,
            atr_m15=atr,
            tick_size=0.00001, tick_value=1.0, contract_size=1.0,
            volume_min=0.01, volume_step=0.01,
            spread_price=rng.choice([0.00001, 0.00003]),
            slippage_price=rng.choice([0.0, 0.00001]),
            commission_per_lot_round_trip=rng.choice([1.0, 2.0, 3.0]),
            limit_active=rng.random() < 0.8, limit_touched=rng.random() < 0.8,
            trade_through_ticks=rng.randint(0, 3), fill_fraction=rng.choice([0.0, 0.5, 1.0]),
            exit_reason=rng.choice(["target", "stop", "time", "session_end"]),
            target_hit_minutes=20.0 if rng.random() < 0.5 else None,
            stop_hit_minutes=10.0 if rng.random() < 0.5 else None,
            breakeven_hit_minutes=15.0 if rng.random() < 0.5 else None,
            price_at_30=1.08100, price_at_45=1.08100, price_at_60=1.08100,
            price_at_90=1.08100, price_at_session_end=1.08100,
            worst_adverse_price=1.08000 if side == "long" else 1.09000,
            rule_violation=False, operational_error=False,
        )
        return event, stop_distance

    def test_randomized_invariants_and_round_trip(self):
        import random as rnd
        rng = rnd.Random(20260904)
        events = []
        for index in range(self.SAMPLES):
            event, distance = self._random_event(rng, index)
            if 0.0003 <= distance <= 0.0016:
                events.append(event)
        self.assertGreater(len(events), 20)
        configs = [
            re.ConfigSpec(f"P{profile}-T{horizon}-BE{int(be)}", profile, risk, target, horizon, be)
            for profile, risk, target in (("A", 0.004, 1.5), ("B", 0.0035, 1.75),
                                          ("C", 0.003, 2.0), ("D", 0.0025, 2.5))
            for horizon in (30, 45, 60, 90, 0)
            for be in (False, True)
        ]
        rows = []
        for event in events:
            for config in configs:
                rows.append((event, config, re.derive_event_rows(event, config)[0]))
        # Row invariants.
        for event, config, row in rows:
            if row.candidate and row.activation_ok:
                self.assertGreater(row.risk_cash_full, 0.0)
                self.assertGreater(row.risk_cash_half, 0.0)
                # V2 section 6 all-in ceiling: pure stop risk + one-side
                # slippage + commission must fit the profile risk budget.
                per_lot_pure = 100000.0 * abs(
                    row.risk_cash_full / round(row.risk_cash_full / max(row.risk_cash_full, 1e-12), 12)
                    if False else 0
                ) if False else None
                entry, stop, _ = re.resolve_entry(event, re.BASELINE_ENTRY_SPEC)
                per_lot_pure = 100000.0 * abs(entry - stop)
                per_lot_all_in = (
                    per_lot_pure
                    + 100000.0 * event.slippage_price
                    + event.commission_per_lot_round_trip
                )
                lots = row.risk_cash_full / per_lot_pure
                self.assertLessEqual(
                    lots * per_lot_all_in, 2500.0 * config.risk_fraction + 1e-6,
                    msg=f"{config.config_id} {row.event_id} exceeds risk ceiling",
                )
                implied = row.net_cash_full / row.risk_cash_full
                self.assertAlmostEqual(implied, row.net_r, places=3,
                                       msg=f"{row.config_id} {row.event_id}: {implied} vs {row.net_r}")
                self.assertGreaterEqual(row.mae_cash_full, 0.0)
                self.assertGreaterEqual(row.spread_r, 0.0)
                self.assertGreaterEqual(row.slippage_r, 0.0)
                self.assertGreaterEqual(row.commission_r, 0.0)
            if row.candidate:
                self.assertTrue(row.activation_ok or row.risk_cash_full == 0.0)
        # CSV round trip preserves everything (floats within 1e-9, exact ints/bools).
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "rows.csv"
            re.write_rows_csv([entry[2] for entry in rows], path)
            synthetic = {"configurations": [{"config_id": c.config_id} for c in configs]}
            loaded = re.load_replay_rows(path, synthetic)
            self.assertEqual(len(loaded), len(rows))
            for (_, _, original), revived in zip(rows, loaded):
                self.assertEqual(original.config_id, revived.config_id)
                self.assertEqual(original.split, revived.split)
                self.assertEqual(original.server_day, revived.server_day)
                self.assertEqual(original.sequence, revived.sequence)
                self.assertEqual(original.event_id, revived.event_id)
                self.assertEqual(original.combination, revived.combination)
                self.assertEqual(original.candidate, revived.candidate)
                self.assertEqual(original.activation_ok, revived.activation_ok)
                self.assertEqual(original.limit_touched, revived.limit_touched)
                self.assertEqual(original.trade_through_ticks, revived.trade_through_ticks)
                self.assertAlmostEqual(original.fill_fraction, revived.fill_fraction, places=12)
                for field in ("net_r", "risk_cash_full", "risk_cash_half", "net_cash_full",
                              "net_cash_half", "mae_cash_full", "mae_cash_half", "spread_r",
                              "slippage_r", "commission_r"):
                    self.assertAlmostEqual(getattr(original, field), getattr(revived, field), places=12)
        # Fill policy: a fill requires activation + touch + trade-through + full fraction.
        from tools.triad_validation import FillPolicy, apply_fill_policy
        for _, _, row in rows:
            trade = apply_fill_policy(row, FillPolicy(), stressed=False, seed=1)
            if trade is not None:
                self.assertTrue(row.activation_ok and row.limit_touched
                                and row.trade_through_ticks >= 1
                                and row.fill_fraction >= 1.0)
