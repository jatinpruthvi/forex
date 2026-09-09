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


if __name__ == "__main__":
    unittest.main()
