"""Tests for the P0 evidence-pipeline extensions.

Covers:
- the section-12 account-wide router (priority, cost/R, sequence, session);
- the extended metric report (fill rates, cash, lot-underuse, year robustness);
- the extended phase report (confidence bounds, draws, median DD, time in DD);
- the replay exporter (contract checks, lot math, time-stop selection,
  calendar coverage, split-cut enforcement, round trip).
"""
from __future__ import annotations

import csv
import random
import tempfile
import unittest
from datetime import date, timedelta
from pathlib import Path

from tools.replay_export import (
    _BASE_EVENT,
    ExportPlan,
    ObservedEvent,
    build_export_rows,
    derive_event_rows,
    load_observed_events,
    write_rows_csv,
)
from tools.replay_export import _run_selftest as run_replay_selftest
from tools.triad_validation import (
    SELECTION_SPLIT,
    CandidateConfig,
    FillPolicy,
    PhaseOutcome,
    ReplayRow,
    SimulationSettings,
    ValidationError,
    enumerate_candidate_configs,
    firm_floor_check,
    load_registry,
    load_replay_rows,
    metric_report,
    parse_combination_priorities,
    phase_simulation_report,
    route_daily_rows,
    simulate_phase,
    validate_replay_coverage,
)

ROOT = Path(__file__).resolve().parents[1]
COMMITTED_REGISTRY = ROOT / "validation" / "triad_v2_1_registry.json"


def make_row(
    config: CandidateConfig,
    day: date,
    *,
    sequence: int = 1,
    combination: str = "EURUSD_LONDON",
    split: str = SELECTION_SPLIT,
    candidate: bool = True,
    activation_ok: bool = True,
    limit_touched: bool = True,
    trade_through_ticks: int = 1,
    fill_fraction: float = 1.0,
    net_r: float = 1.5,
    risk_cash_full: float = 10.0,
    net_cash_full: float = 15.0,
    spread_r: float = 0.03,
    slippage_r: float = 0.02,
    commission_r: float = 0.01,
    suffix: str = "",
) -> ReplayRow:
    return ReplayRow(
        config_id=config.config_id,
        split=split,
        server_day=day,
        sequence=sequence,
        event_id=f"{day.isoformat()}-{sequence}-{combination}{suffix}",
        combination=combination,
        candidate=candidate,
        activation_ok=activation_ok,
        limit_touched=limit_touched,
        trade_through_ticks=trade_through_ticks,
        fill_fraction=fill_fraction,
        net_r=net_r,
        risk_cash_full=risk_cash_full,
        risk_cash_half=risk_cash_full / 2.0,
        net_cash_full=net_cash_full,
        net_cash_half=net_cash_full / 2.0,
        mae_cash_full=2.0 if net_r > 0 else risk_cash_full,
        mae_cash_half=1.0 if net_r > 0 else risk_cash_full / 2.0,
        spread_r=spread_r,
        slippage_r=slippage_r,
        commission_r=commission_r,
        rule_violation=False,
        operational_error=False,
    )


class RouterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.config = enumerate_candidate_configs()[0]
        self.day = date(2025, 1, 6)
        self.fill_policy = FillPolicy(stressed_profitable_limit_miss_fraction=0.0)

    def test_priority_selects_one_combination_per_day(self) -> None:
        rows = [
            make_row(self.config, self.day, combination="EURUSD_LONDON"),
            make_row(
                self.config,
                self.day,
                sequence=2,
                combination="GBPUSD_LONDON",
                suffix="-gbp",
            ),
        ]
        routed, diagnostics = route_daily_rows(
            rows, {"EURUSD_LONDON": 1, "GBPUSD_LONDON": 2, "USDJPY_NEW_YORK": 3}
        )
        report = metric_report(routed, self.fill_policy, stressed=False, seed=1)
        self.assertEqual(report["fills"], 1)
        self.assertEqual(report["activation_refusals"], 1)
        self.assertEqual(
            diagnostics["rejected_candidate_counts"], {"GBPUSD_LONDON->EURUSD_LONDON": 1}
        )
        self.assertEqual(diagnostics["winner_rows"], 1)

    def test_priority_tie_breaks_by_lower_cost_r(self) -> None:
        rows = [
            make_row(
                self.config,
                self.day,
                combination="EURUSD_LONDON",
                spread_r=0.10,
                suffix="-eur",
            ),
            make_row(
                self.config,
                self.day,
                sequence=2,
                combination="GBPUSD_LONDON",
                spread_r=0.01,
                suffix="-gbp",
            ),
        ]
        routed, diagnostics = route_daily_rows(rows)  # equal priorities
        report = metric_report(routed, self.fill_policy, stressed=False, seed=1)
        self.assertEqual(report["fills"], 1)
        self.assertEqual(
            diagnostics["rejected_candidate_counts"], {"EURUSD_LONDON->GBPUSD_LONDON": 1}
        )

    def test_first_signal_wins_within_same_combination(self) -> None:
        rows = [
            make_row(self.config, self.day, sequence=1, suffix="-first"),
            make_row(self.config, self.day, sequence=2, suffix="-second"),
        ]
        routed, _ = route_daily_rows(rows)
        report = metric_report(routed, self.fill_policy, stressed=False, seed=1)
        self.assertEqual(report["fills"], 1)
        self.assertEqual(report["activated_orders"], 1)

    def test_demoted_rows_keep_candidate_flag_for_audit(self) -> None:
        rows = [
            make_row(self.config, self.day, combination="EURUSD_LONDON"),
            make_row(
                self.config,
                self.day,
                sequence=2,
                combination="GBPUSD_LONDON",
                suffix="-gbp",
            ),
        ]
        routed, _ = route_daily_rows(rows)
        gbp = [row for row in routed if row.combination == "GBPUSD_LONDON"][0]
        self.assertTrue(gbp.candidate)
        self.assertFalse(gbp.activation_ok)
        self.assertEqual(gbp.net_r, 0.0)
        self.assertEqual(gbp.risk_cash_full, 0.0)

    def test_no_candidate_day_passes_through_unchanged(self) -> None:
        rows = [
            make_row(self.config, self.day, candidate=False, activation_ok=False)
        ]
        routed, diagnostics = route_daily_rows(rows)
        self.assertEqual(len(routed), 1)
        self.assertEqual(diagnostics["winner_rows"], 0)

    def test_parse_priorities_validates_names_and_range(self) -> None:
        parsed = parse_combination_priorities("EURUSD_LONDON:2")
        self.assertEqual(parsed["EURUSD_LONDON"], 2)
        self.assertEqual(parsed["GBPUSD_LONDON"], 1)
        with self.assertRaises(ValidationError):
            parse_combination_priorities("BAD:1")
        with self.assertRaises(ValidationError):
            parse_combination_priorities("EURUSD_LONDON:9")


class MetricExtensionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.config = enumerate_candidate_configs()[0]
        self.policy = FillPolicy(stressed_profitable_limit_miss_fraction=0.0)

    def test_fill_rate_and_activation_metrics(self) -> None:
        rows = [
            make_row(self.config, date(2025, 1, 1), activation_ok=False, candidate=True),
            make_row(self.config, date(2025, 1, 2), limit_touched=False, trade_through_ticks=0),
            make_row(self.config, date(2025, 1, 3)),
            make_row(
                self.config,
                date(2025, 1, 4),
                sequence=2,
                fill_fraction=0.5,
                suffix="-partial",
            ),
        ]
        report = metric_report(rows, self.policy, stressed=False, seed=1)
        self.assertEqual(report["candidate_signals"], 4)
        # The missed-limit row is an activated order (the pending was active;
        # it simply never traded through), so only the gate-rejected row is a
        # refusal.
        self.assertEqual(report["activated_orders"], 3)
        self.assertEqual(report["activation_refusals"], 1)
        self.assertAlmostEqual(report["fill_rate"], 1.0 / 3.0)
        self.assertAlmostEqual(report["signal_fill_rate"], 0.25)

    def test_cash_metrics_and_small_positive_winners(self) -> None:
        rows = [
            make_row(self.config, date(2025, 1, 1), net_cash_full=12.00),  # just below 12.50
            make_row(self.config, date(2025, 1, 2), sequence=2, net_cash_full=18.00),
            make_row(
                self.config,
                date(2025, 1, 3),
                sequence=3,
                net_r=-1.0,
                net_cash_full=-10.0,
                risk_cash_full=10.0,
            ),
        ]
        report = metric_report(
            rows,
            self.policy,
            stressed=False,
            seed=1,
            config_risk_fractions={self.config.config_id: 0.004},
            initial_balance=2500.0,
            qualifying_cash=12.50,
        )
        self.assertEqual(report["small_positive_wins_full"], 1)
        self.assertEqual(report["qualifying_wins_full"], 1)
        self.assertAlmostEqual(report["net_cash_total_full"], 20.0)
        self.assertAlmostEqual(report["executed_risk_fraction_mean"], 1.0)

    def test_min_lot_budget_underuse_is_measured(self) -> None:
        rows = [
            make_row(
                self.config,
                date(2025, 1, 1),
                risk_cash_full=5.0,
                net_cash_full=7.5,
                suffix="-half",
            )
        ]
        report = metric_report(
            rows,
            self.policy,
            stressed=False,
            seed=1,
            config_risk_fractions={self.config.config_id: 0.004},
            initial_balance=2500.0,
            qualifying_cash=12.50,
        )
        self.assertEqual(report["budget_underuse_fills"], 1)
        self.assertAlmostEqual(report["budget_underuse_share"], 1.0)

    def test_year_robustness_rejects_single_year_profit(self) -> None:
        rows = [
            make_row(self.config, date(2023, 3, 1), net_r=1.5, net_cash_full=15.0),
            make_row(self.config, date(2023, 6, 1), sequence=2, net_r=1.0, net_cash_full=10.0),
            make_row(self.config, date(2024, 6, 1), sequence=3, net_r=-0.5, net_cash_full=-5.0),
        ]
        report = metric_report(rows, self.policy, stressed=False, seed=1)
        self.assertFalse(report["year_robustness_ok"])
        self.assertEqual(report["calendar_years_with_fills"], [2023, 2024])

    def test_year_robustness_accepts_two_positive_years(self) -> None:
        rows = [
            make_row(self.config, date(2023, 3, 1), net_r=1.0, net_cash_full=10.0),
            make_row(self.config, date(2024, 3, 1), sequence=2, net_r=1.0, net_cash_full=10.0),
            make_row(self.config, date(2024, 6, 1), sequence=3, net_r=-0.5, net_cash_full=-5.0),
        ]
        report = metric_report(rows, self.policy, stressed=False, seed=1)
        self.assertTrue(report["year_robustness_ok"])


class PhaseExtensionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.config = enumerate_candidate_configs()[0]
        self.policy = FillPolicy(stressed_profitable_limit_miss_fraction=0.0)

    def test_report_contains_confidence_draws_and_median_stats(self) -> None:
        start = date(2024, 1, 1)
        rows = [
            make_row(self.config, start + timedelta(days=offset))
            for offset in range(40)
        ]
        settings = SimulationSettings(
            holdout_paths=80,
            max_phase_calendar_days=60,
            random_seed=7,
            block_days=1,
        )
        report = phase_simulation_report(
            rows,
            self.policy,
            stressed=False,
            paths=80,
            settings=settings,
            seed=7,
        )
        confidence = report["joint_confidence"]
        self.assertIn("lower", confidence)
        self.assertIn("upper", confidence)
        self.assertEqual(confidence["trials"], 80)
        self.assertEqual(report["joint_draws"]["joint_pass"], 80)
        self.assertIsNotNone(report["maximum_drawdown_p50_fraction"])
        self.assertIsNotNone(report["median_time_in_drawdown_days"])
        self.assertEqual(
            report["median_joint_completion_calendar_days"],
            report["median_joint_calendar_days_all_paths"],
        )

    def test_simulate_phase_counts_days_in_drawdown(self) -> None:
        from tools.triad_validation import apply_fill_policy

        config = enumerate_candidate_configs()[0]
        loss_day = date(2024, 1, 1)
        win_day = date(2024, 1, 2)
        policy = self.policy
        loss_trades = [
            trade
            for row in [make_row(config, loss_day, net_r=-1.0, net_cash_full=-10.0)]
            if (trade := apply_fill_policy(row, policy, stressed=False, seed=1)) is not None
        ]
        win_trades = [
            trade
            for row in [make_row(config, win_day, sequence=2, net_r=1.5, net_cash_full=15.0)]
            if (trade := apply_fill_policy(row, policy, stressed=False, seed=1)) is not None
        ]
        days = [(loss_day, loss_trades), (win_day, win_trades)]
        settings = SimulationSettings(
            max_phase_calendar_days=1,
            block_days=1,
        )
        seen = False
        for seed in range(200):
            outcome = simulate_phase(
                days,
                phase_target_fraction=0.10,
                settings=settings,
                rng=random.Random(seed),
            )
            self.assertIsInstance(outcome, PhaseOutcome)
            if outcome.reason == "maximum_duration" and outcome.days_in_drawdown == 1:
                seen = True
                break
        self.assertTrue(seen, "should find a seed whose single day is the loss day")

    def test_firm_floor_check_detects_repeated_full_losses(self) -> None:
        config = enumerate_candidate_configs()[0]
        # Two -$200 days bring $2500 to $2100, below the $2250 firm overall
        # floor.  Wider internal daily/weekly stops in this *test fixture* keep
        # the path trading long enough to reach the firm floor; the registered
        # 1%/2% stops are deliberately not used here because they would (and
        # should) halt the path first.
        loss_rows = [
            make_row(
                config,
                date(2024, 1, 1) + timedelta(days=offset),
                sequence=1,
                net_r=-1.0,
                net_cash_full=-200.0,
                risk_cash_full=200.0,
            )
            for offset in range(4)
        ]
        settings = SimulationSettings(
            max_phase_calendar_days=10,
            block_days=4,
            daily_stop_fraction=0.08,   # $200
            weekly_stop_fraction=0.20,  # $500
        )
        check = firm_floor_check(
            loss_rows,
            self.policy,
            stressed=False,
            seed=1,
            settings=settings,
        )
        self.assertTrue(check["firm_overall_floor_breached"])
        self.assertGreater(check["firm_overall_floor_breach_rate"], 0.0)


class ExportTests(unittest.TestCase):
    def setUp(self) -> None:
        self.registry = load_registry(COMMITTED_REGISTRY)
        self.configs = [
            CandidateConfig(**item)
            for item in [
                {
                    "config_id": "R30_80-A20_80-T30-PA-BE0",
                    "range_low_percentile": 30,
                    "range_high_percentile": 80,
                    "atr_low_percentile": 20,
                    "atr_high_percentile": 80,
                    "time_stop_minutes": 30,
                    "profile": "A",
                    "risk_fraction": 0.004,
                    "target_r": 1.5,
                    "move_stop_to_entry_after_confirmed_1r": False,
                },
                {
                    "config_id": "R30_80-A20_80-T45-PA-BE0",
                    "range_low_percentile": 30,
                    "range_high_percentile": 80,
                    "atr_low_percentile": 20,
                    "atr_high_percentile": 80,
                    "time_stop_minutes": 45,
                    "profile": "A",
                    "risk_fraction": 0.004,
                    "target_r": 1.5,
                    "move_stop_to_entry_after_confirmed_1r": False,
                },
            ]
        ]

    def _event(self, day: date, **overrides) -> ObservedEvent:
        payload = {**_BASE_EVENT, **overrides}
        payload["server_day"] = day
        payload.setdefault("sequence", 1)
        payload.setdefault("event_id", f"EV-{day.isoformat()}")
        return ObservedEvent(**payload)

    def test_derive_target_math_and_rounded_lots(self) -> None:
        row = derive_event_rows(
            self._event(date(2025, 1, 2)), self.configs[0]
        )[0]
        self.assertTrue(row.activation_ok)
        # 0.10 lots (risk budget $10 / $94 per-lot risk = 0.106 -> 0.10).
        self.assertAlmostEqual(row.risk_cash_full, 9.40, places=2)
        # Net target: gross ≈ 94 * (1.5 + comm/slip ~0.0426) ≈ 145.0; minus
        # $7 modeled cost = $138.0 per lot * 0.10 lots = $13.80.
        self.assertAlmostEqual(row.net_cash_full, 13.80, places=2)
        self.assertGreater(row.net_r, 1.0)
        self.assertLess(row.net_r, 2.0)
        self.assertAlmostEqual(row.spread_r, 3.0 / 94.0, places=4)
        self.assertTrue(row.limit_touched)

    def test_derive_rejects_weak_displacement(self) -> None:
        row = derive_event_rows(
            self._event(
                date(2025, 1, 3),
                displacement_open=1.08035,
                displacement_close=1.08035,
            ),
            self.configs[0],
        )[0]
        self.assertTrue(row.candidate)
        self.assertFalse(row.activation_ok)
        self.assertEqual(row.risk_cash_full, 0.0)

    def test_derive_min_volume_skip_small_account(self) -> None:
        row = derive_event_rows(
            self._event(date(2025, 1, 4)),
            self.configs[0],
            initial_balance=100.0,
        )[0]
        self.assertTrue(row.candidate)
        self.assertFalse(row.activation_ok)

    def test_derive_time_stop_uses_horizon_price(self) -> None:
        row = derive_event_rows(
            self._event(
                date(2025, 1, 5),
                exit_reason="time",
                target_hit_minutes=None,
                stop_hit_minutes=None,
            ),
            self.configs[1],  # 45-minute time stop
        )[0]
        # Entry 1.08045, exit at price_at_45 = 1.08170 -> +125 ticks.
        # gross per lot = $125, modeled cost $7 -> $118 / 94 = ~1.255R.
        self.assertTrue(row.activation_ok)
        self.assertAlmostEqual(row.net_r, 118.0 / 94.0, places=3)

    def test_build_export_covers_every_config_combination_day(self) -> None:
        plan = ExportPlan(
            selection_start=date(2025, 1, 1),
            selection_end=date(2025, 1, 5),
            holdout_start=date(2025, 1, 6),
            holdout_end=date(2025, 1, 7),
        )
        events = [self._event(date(2025, 1, 2))]
        rows = build_export_rows(events, self.configs, plan)
        expected = 7 * len(self.configs) * 3
        self.assertEqual(len(rows), expected)
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "replay_rows.csv"
            write_rows_csv(rows, path)
            loaded = load_replay_rows(path, self.registry)
            validate_replay_coverage(loaded, self.configs)
        fills = sum(
            1
            for row in loaded
            if row.activation_ok and row.limit_touched and row.trade_through_ticks > 0
        )
        self.assertGreater(fills, 0)

    def test_same_session_repeat_is_not_an_order(self) -> None:
        plan = ExportPlan(
            selection_start=date(2025, 1, 1),
            selection_end=date(2025, 1, 1),
            holdout_start=date(2026, 1, 1),
            holdout_end=date(2026, 1, 1),
        )
        events = [
            self._event(date(2025, 1, 1), sequence=1, event_id="EV-1"),
            self._event(date(2025, 1, 1), sequence=2, event_id="EV-2"),
        ]
        rows = build_export_rows(events, self.configs, plan)
        matching = [
            row
            for row in rows
            if row.config_id == self.configs[0].config_id
            and row.combination == "EURUSD_LONDON"
            and row.server_day == date(2025, 1, 1)
        ]
        self.assertEqual(len(matching), 2)
        self.assertTrue(matching[0].activation_ok)
        self.assertFalse(matching[1].activation_ok)

    def test_split_cut_must_be_predeclared(self) -> None:
        plan = ExportPlan(
            selection_start=date(2025, 1, 1),
            selection_end=date(2025, 1, 5),
            holdout_start=date(2025, 1, 6),
            holdout_end=date(2025, 1, 7),
        )
        events = [self._event(date(2024, 6, 1))]
        with self.assertRaisesRegex(ValidationError, "outside the declared"):
            build_export_rows(events, self.configs, plan)

    def test_observed_event_loader_rejects_unknown_combination(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "events.csv"
            with path.open("w", encoding="utf-8", newline="") as handle:
                writer = csv.DictWriter(
                    handle,
                    fieldnames=["server_day", "sequence", "event_id", *_BASE_EVENT.keys()],
                )
                writer.writeheader()
                row_data = dict(_BASE_EVENT)
                row_data["server_day"] = "2025-01-02"
                row_data["sequence"] = "1"
                row_data["event_id"] = "EV-1"
                row_data["combination"] = "TOTALLY_MADE_UP"
                writer.writerow({**row_data, "sequence": 1})
            with self.assertRaises(ValidationError):
                load_observed_events(path)

    def test_selftest_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            exit_code = run_replay_selftest(Path(temporary))
            self.assertEqual(exit_code, 0)


if __name__ == "__main__":
    unittest.main()
