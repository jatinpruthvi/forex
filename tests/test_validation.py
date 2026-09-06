from __future__ import annotations

import json
import tempfile
import unittest
from datetime import date, timedelta
from pathlib import Path

from tools.triad_validation import (
    HOLDOUT_SPLIT,
    SELECTION_SPLIT,
    AppliedTrade,
    CandidateConfig,
    FillPolicy,
    ReplayRow,
    SimulationSettings,
    ValidationError,
    ValidationThresholds,
    apply_fill_policy,
    bootstrap_expectancy_interval,
    build_registry,
    enumerate_candidate_configs,
    load_registry,
    metric_report,
    phase_simulation_report,
    select_champion,
    validate_replay_coverage,
    write_registry,
)


ROOT = Path(__file__).resolve().parents[1]
COMMITTED_REGISTRY = ROOT / "validation" / "triad_v2_1_registry.json"


def replay_row(
    config: CandidateConfig,
    day: date,
    *,
    sequence: int = 1,
    combination: str = "EURUSD_LONDON",
    split: str = SELECTION_SPLIT,
    net_r: float = 1.5,
    net_cash_full: float = 15.0,
    net_cash_half: float = 7.5,
    candidate: bool = True,
    activation_ok: bool = True,
    limit_touched: bool = True,
    trade_through_ticks: int = 1,
    fill_fraction: float = 1.0,
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
        risk_cash_full=10.0,
        risk_cash_half=5.0,
        net_cash_full=net_cash_full,
        net_cash_half=net_cash_half,
        mae_cash_full=10.0 if net_r < 0 else 2.0,
        mae_cash_half=5.0 if net_r < 0 else 1.0,
        spread_r=0.03,
        slippage_r=0.02,
        commission_r=0.01,
        rule_violation=False,
        operational_error=False,
    )


class RegistryTests(unittest.TestCase):
    def test_committed_registry_matches_validator_declaration(self) -> None:
        committed = load_registry(COMMITTED_REGISTRY)
        self.assertEqual(committed, build_registry())

    def test_declared_matrix_contains_exactly_160_unique_configs(self) -> None:
        configs = enumerate_candidate_configs()
        self.assertEqual(len(configs), 160)
        self.assertEqual(len({config.config_id for config in configs}), 160)
        dimensions = {
            (
                config.range_low_percentile,
                config.range_high_percentile,
                config.atr_low_percentile,
                config.atr_high_percentile,
                config.time_stop_minutes,
                config.profile,
                config.move_stop_to_entry_after_confirmed_1r,
            )
            for config in configs
        }
        self.assertEqual(len(dimensions), 2 * 2 * 5 * 4 * 2)

    def test_registry_hash_detects_any_candidate_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "registry.json"
            original = write_registry(path)
            self.assertEqual(load_registry(path), original)

            mutated = json.loads(path.read_text(encoding="utf-8"))
            mutated["configurations"][0]["target_r"] = 9.99
            path.write_text(json.dumps(mutated), encoding="utf-8")
            with self.assertRaisesRegex(ValidationError, "hash mismatch"):
                load_registry(path)

    def test_registry_declares_conservative_fill_and_holdout_rules(self) -> None:
        registry = build_registry()
        self.assertEqual(registry["selection_split"], SELECTION_SPLIT)
        self.assertEqual(registry["holdout_split"], HOLDOUT_SPLIT)
        self.assertEqual(registry["fill_policy"]["minimum_trade_through_ticks"], 1)
        self.assertEqual(
            registry["fill_policy"]["stressed_profitable_limit_miss_fraction"],
            0.10,
        )

    def test_coverage_requires_every_config_combination_and_day(self) -> None:
        config = enumerate_candidate_configs()[0]
        incomplete = [
            replay_row(config, date(2025, 1, 1), split=SELECTION_SPLIT),
            replay_row(config, date(2026, 1, 1), split=HOLDOUT_SPLIT),
        ]
        with self.assertRaisesRegex(ValidationError, "configuration/combination"):
            validate_replay_coverage(incomplete, [config])


class FillPolicyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.config = enumerate_candidate_configs()[0]
        self.day = date(2026, 1, 5)
        self.policy = FillPolicy(stressed_profitable_limit_miss_fraction=0.0)

    def test_touch_without_trade_through_is_not_a_fill(self) -> None:
        touched = replay_row(self.config, self.day, trade_through_ticks=0)
        self.assertIsNone(apply_fill_policy(touched, self.policy, stressed=False, seed=1))

    def test_inactive_or_partial_order_is_not_a_fill(self) -> None:
        inactive = replay_row(self.config, self.day, activation_ok=False)
        partial = replay_row(self.config, self.day, fill_fraction=0.5, suffix="-partial")
        self.assertIsNone(apply_fill_policy(inactive, self.policy, stressed=False, seed=1))
        self.assertIsNone(apply_fill_policy(partial, self.policy, stressed=False, seed=1))

    def test_stress_cost_is_deducted_again(self) -> None:
        row = replay_row(self.config, self.day, net_r=1.0)
        trade = apply_fill_policy(row, self.policy, stressed=True, seed=1)
        self.assertIsInstance(trade, AppliedTrade)
        assert trade is not None
        # Additional stress = 0.5 * spread R + 1.0 * slippage R.
        self.assertAlmostEqual(trade.extra_cost_r, 0.035)
        self.assertAlmostEqual(trade.net_r, 0.965)
        self.assertAlmostEqual(trade.cash_result(False), 14.65)

    def test_report_exposes_fill_uncertainty_counts(self) -> None:
        rows = [
            replay_row(self.config, self.day, trade_through_ticks=0),
            replay_row(
                self.config,
                self.day,
                sequence=2,
                fill_fraction=0.5,
                suffix="-partial",
            ),
        ]
        report = metric_report(rows, self.policy, stressed=False, seed=1)
        self.assertEqual(report["fills"], 0)
        self.assertEqual(report["touch_without_trade_through"], 1)
        self.assertEqual(report["partial_fill_observations"], 1)


class SelectionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.configs = enumerate_candidate_configs()[:2]
        self.policy = FillPolicy(stressed_profitable_limit_miss_fraction=0.0)
        self.thresholds = ValidationThresholds(
            minimum_combination_fills=1,
            minimum_aggregate_fills=3,
            minimum_combination_expectancy_r=-1.0,
            minimum_combination_profit_factor=0.0,
            minimum_aggregate_expectancy_r=-1.0,
            minimum_aggregate_profit_factor=0.0,
            minimum_stressed_expectancy_r=-1.0,
            minimum_stressed_profit_factor=0.0,
            require_selection_adjusted_lower_bound_positive=False,
        )
        self.settings = SimulationSettings(
            selection_paths=40,
            holdout_paths=40,
            bootstrap_samples=100,
            max_phase_calendar_days=100,
            random_seed=1234,
        )

    def _rows(self, split: str) -> list[ReplayRow]:
        rows: list[ReplayRow] = []
        start = date(2025, 1, 1)
        combinations = sorted(
            ("EURUSD_LONDON", "GBPUSD_LONDON", "USDJPY_NEW_YORK")
        )
        for config_index, config in enumerate(self.configs):
            for offset in range(45):
                combination = combinations[offset % len(combinations)]
                if config_index == 0:
                    net_r, cash = 1.5, 15.0
                else:
                    net_r, cash = 0.5, 6.0
                # Deliberately make the second config excellent only in HOLDOUT.
                if split == HOLDOUT_SPLIT and config_index == 1:
                    net_r, cash = 4.0, 40.0
                rows.append(
                    replay_row(
                        config,
                        start + timedelta(days=offset),
                        combination=combination,
                        split=split,
                        net_r=net_r,
                        net_cash_full=cash,
                        net_cash_half=cash / 2,
                    )
                )
        return rows

    def test_selector_rejects_holdout_rows(self) -> None:
        with self.assertRaisesRegex(ValidationError, "holdout"):
            select_champion(
                self._rows(SELECTION_SPLIT) + self._rows(HOLDOUT_SPLIT),
                self.configs,
                self.policy,
                self.thresholds,
                self.settings,
            )

    def test_holdout_outcomes_cannot_change_selected_champion(self) -> None:
        selection_rows = self._rows(SELECTION_SPLIT)
        champion, report = select_champion(
            selection_rows,
            self.configs,
            self.policy,
            self.thresholds,
            self.settings,
        )
        self.assertIsNotNone(champion)
        assert champion is not None
        self.assertEqual(champion.config_id, self.configs[0].config_id)
        self.assertEqual(report["selection_result"], "CHAMPION_FROZEN_BEFORE_HOLDOUT")
        # The selector has no API through which the second config's excellent
        # holdout outcomes can influence that result.
        self.assertNotEqual(champion.config_id, self.configs[1].config_id)

    def test_selection_aware_interval_is_never_narrower(self) -> None:
        rows = self._rows(SELECTION_SPLIT)
        interval = bootstrap_expectancy_interval(
            [row for row in rows if row.config_id == self.configs[0].config_id],
            self.policy,
            stressed=False,
            samples=500,
            block_days=5,
            alpha=0.05,
            family_size=160,
            seed=99,
        )
        ordinary = interval["ordinary_interval"]
        adjusted = interval["familywise_adjusted_interval"]
        self.assertLessEqual(adjusted[0], ordinary[0])
        self.assertGreaterEqual(adjusted[1], ordinary[1])


class PhaseReplayTests(unittest.TestCase):
    def test_profitable_daily_sequence_passes_both_phases(self) -> None:
        config = enumerate_candidate_configs()[0]
        start = date(2024, 1, 1)
        combinations = sorted(
            ("EURUSD_LONDON", "GBPUSD_LONDON", "USDJPY_NEW_YORK")
        )
        rows = [
            replay_row(
                config,
                start + timedelta(days=offset),
                combination=combinations[offset % 3],
                net_r=1.5,
                net_cash_full=15.0,
                net_cash_half=7.5,
            )
            for offset in range(40)
        ]
        settings = SimulationSettings(
            holdout_paths=50,
            max_phase_calendar_days=60,
            random_seed=7,
        )
        report = phase_simulation_report(
            rows,
            FillPolicy(stressed_profitable_limit_miss_fraction=0.0),
            stressed=False,
            paths=50,
            settings=settings,
            seed=7,
        )
        self.assertEqual(report["phase1_pass_probability"], 1.0)
        self.assertEqual(report["phase2_pass_probability"], 1.0)
        self.assertEqual(report["joint_pass_probability"], 1.0)
        self.assertEqual(report["phase1_qualifying_days_by_target_probability"], 1.0)
        self.assertEqual(report["phase2_qualifying_days_by_target_probability"], 1.0)
        self.assertEqual(report["phase1_outcomes"], {"passed": 50})
        self.assertEqual(report["phase2_outcomes"], {"passed": 50})


if __name__ == "__main__":
    unittest.main()
