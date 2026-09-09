"""Tests for the preregistered P2 ablation scaffold.

The scaffold is deliberately data-gated: these tests prove contract and
mechanics only, never that any variant has an edge.  Everything the evaluator
may conclude is fixed in ``validation/triad_v2_2_ablation_registry.json`` and
committed before any real data is generated.
"""
from __future__ import annotations

import csv
import json
import tempfile
import unittest
from datetime import date
from dataclasses import asdict
from pathlib import Path

from tools import replay_export as re
from tools import triad_ablation as abl
from tools.triad_validation import ValidationError, validate_replay_coverage

ROOT = Path(__file__).resolve().parents[1]
REGISTRY_PATH = ROOT / "validation" / "triad_v2_2_ablation_registry.json"


def _event(day: date, event_id: str, *,
           combination: str = "EURUSD_LONDON",
           overrides: dict | None = None) -> re.ObservedEvent:
    payload = dict(re._BASE_EVENT)
    payload.pop("combination")
    if overrides:
        payload.update(overrides)
    return re.ObservedEvent(
        server_day=day,
        sequence=1,
        event_id=event_id,
        combination=combination,
        **payload,
    )


def _config(variant_id: str = "ABL-V0-BASELINE") -> re.ConfigSpec:
    return abl.fixed_config_spec(variant_id)


class AblationRegistryTests(unittest.TestCase):
    def test_registry_file_matches_tool_declaration(self):
        self.assertTrue(REGISTRY_PATH.exists(), "preregistered registry is missing")
        registry = abl.load_registry(REGISTRY_PATH)
        self.assertEqual(registry, abl.build_registry())
        self.assertEqual(registry["schema_version"], abl.ABLATION_SCHEMA_VERSION)
        self.assertIn("registry_sha256", registry)

    def test_six_runs_with_baseline_first(self):
        runs = abl.load_runs(abl.load_registry(REGISTRY_PATH))
        self.assertEqual(len(runs), 6)
        self.assertEqual(runs[0].variant_id, "ABL-V0-BASELINE")
        self.assertEqual(runs[0].entry_spec, abl.BASELINE_ENTRY_SPEC)
        self.assertFalse(runs[0].simplicity_bonus)
        for run in runs[1:]:
            self.assertIn(run.question, {"Q1", "Q2", "Q3"})
            self.assertIn(run.entry_spec.entry_mode, abl.ENTRY_MODES)

    def test_each_variant_changes_at_least_one_entry_parameter(self):
        baseline = abl.BASELINE_ENTRY_SPEC
        runs = abl.load_runs(abl.load_registry(REGISTRY_PATH))
        for run in runs[1:]:
            changed = [
                field
                for field in baseline.__dataclass_fields__
                if getattr(run.entry_spec, field) != getattr(baseline, field)
            ]
            self.assertTrue(changed, f"{run.variant_id} changes nothing")
            # The sweep band and the stop parameters are never touched.
            self.assertEqual(run.entry_spec.sweep_atr_min, baseline.sweep_atr_min)
            self.assertEqual(run.entry_spec.sweep_atr_max, baseline.sweep_atr_max)

    def test_tamper_is_rejected(self):
        registry = abl.load_registry(REGISTRY_PATH)
        registry["decision"]["accept_delta_r"] = 0.99
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "tampered.json"
            path.write_text(json.dumps(registry), encoding="utf-8")
            with self.assertRaises(ValidationError):
                abl.load_registry(path)

    def test_split_change_requires_reregistration(self):
        registry = abl.load_registry(REGISTRY_PATH)
        abb = abl.build_registry()
        selection_start, selection_end, holdout_start, holdout_end = abl.declared_splits(abb)
        with self.assertRaises(ValidationError):
            abl.guard_split_args(
                abb,
                ("2018-01-01", selection_end.isoformat()),
                (holdout_start.isoformat(), holdout_end.isoformat()),
            )
        self.assertIsNone(abl.guard_split_args(
            abb,
            (selection_start.isoformat(), selection_end.isoformat()),
            (holdout_start.isoformat(), holdout_end.isoformat()),
        ))


class AblationEntryBehaviorTests(unittest.TestCase):
    def test_baseline_spec_is_byte_equivalent_to_frozen_derive(self):
        event = _event(date(2023, 1, 3), "EUR-1")
        config = _config()
        frozen = re.derive_event_rows(event, config)[0]
        ablation = abl.derive_ablation_event_rows(
            event, config, abl.BASELINE_ENTRY_SPEC, variant_id="ABL-V0-BASELINE"
        )[0]
        frozen_fields = {**asdict(frozen), "config_id": "ABL-V0-BASELINE"}
        self.assertEqual(frozen_fields, asdict(ablation))

    def test_v1_simpler_reclaim_accepts_weak_displacement(self):
        event = _event(
            date(2023, 1, 3),
            "EUR-WEAK",
            overrides={"displacement_open": 1.08035, "displacement_close": 1.08035},
        )
        baseline = re.derive_event_rows(event, _config("ABL-V0-BASELINE"))[0]
        self.assertFalse(baseline.activation_ok)
        self.assertEqual(baseline.risk_cash_full, 0.0)
        variant = abl.derive_ablation_event_rows(
            event, _config(), abl.ABL_RUNS[1].entry_spec, variant_id="ABL-V1-SIMPLER-RECLAIM"
        )[0]
        self.assertTrue(variant.activation_ok)
        self.assertEqual(variant.config_id, "ABL-V1-SIMPLER-RECLAIM")
        # Entry is the reclaim-body midpoint 1.080775; stop is 1.07951; the
        # budget allows 0.07 lots -> 0.07 * 100000 * 0.001265 = 8.8550 cash risk.
        self.assertAlmostEqual(variant.risk_cash_full, 8.8550, places=4)

    def test_v2_quote_entry_prices_from_displacement_close(self):
        event = _event(date(2023, 1, 3), "EUR-QUOTE")
        variant = abl.derive_ablation_event_rows(
            event, _config(), abl.ABL_RUNS[2].entry_spec, variant_id="ABL-V2-QUOTE-ENTRY"
        )[0]
        self.assertTrue(variant.activation_ok)
        # entry 1.08055, stop 1.07951 -> 0.00104 risk distance, 0.09 lots.
        self.assertAlmostEqual(variant.risk_cash_full, 9.36, places=4)

    def test_v3_skips_low_reclaim_wick_filter(self):
        event = _event(
            date(2023, 1, 3),
            "EUR-LOWWICK",
            overrides={
                "reclaim_open": 1.08040,
                "reclaim_close": 1.08050,
                "reclaim_high": 1.08090,
                "reclaim_low": 1.07990,
            },
        )
        baseline = re.derive_event_rows(event, _config("ABL-V0-BASELINE"))[0]
        self.assertFalse(baseline.activation_ok)
        variant = abl.derive_ablation_event_rows(
            event, _config(), abl.ABL_RUNS[3].entry_spec, variant_id="ABL-V3-NO-RECLAIM-WICK"
        )[0]
        self.assertTrue(variant.activation_ok)

    def test_v4_lowers_displacement_body_threshold(self):
        event = _event(
            date(2023, 1, 3),
            "EUR-BODY50",
            overrides={"displacement_close": 1.08050},
        )
        baseline = re.derive_event_rows(event, _config("ABL-V0-BASELINE"))[0]
        self.assertFalse(baseline.activation_ok)
        variant = abl.derive_ablation_event_rows(
            event, _config(), abl.ABL_RUNS[4].entry_spec, variant_id="ABL-V4-BODY-40"
        )[0]
        self.assertTrue(variant.activation_ok)
        # entry 1.080425, stop 1.07951 -> 0.000915 risk distance, 0.10 lots.
        self.assertAlmostEqual(variant.risk_cash_full, 9.15, places=4)

    def test_v5_skips_midpoint_confirmation(self):
        event = _event(
            date(2023, 1, 3),
            "EUR-BELOWMID",
            overrides={
                "sweep_low": 1.07956,
                "spread_price": 0.00002,
                "displacement_low": 1.08020,
                "displacement_open": 1.08022,
                "displacement_close": 1.08038,
                "displacement_high": 1.08045,
            },
        )
        baseline = re.derive_event_rows(event, _config("ABL-V0-BASELINE"))[0]
        self.assertFalse(baseline.activation_ok)
        variant = abl.derive_ablation_event_rows(
            event, _config(), abl.ABL_RUNS[5].entry_spec, variant_id="ABL-V5-NO-MIDPOINT"
        )[0]
        self.assertTrue(variant.activation_ok)
        # entry 1.08030, stop 1.07947 -> 0.00083 risk distance, 0.12 lots.
        self.assertAlmostEqual(variant.risk_cash_full, 9.96, places=4)

    def test_rejections_are_audited_as_candidates(self):
        event = _event(
            date(2023, 1, 3),
            "EUR-WEAK",
            overrides={"displacement_open": 1.08035, "displacement_close": 1.08035},
        )
        baseline = re.derive_event_rows(event, _config("ABL-V0-BASELINE"))[0]
        self.assertTrue(baseline.candidate)
        self.assertFalse(baseline.activation_ok)
        self.assertEqual(baseline.net_r, 0.0)
        self.assertEqual(baseline.net_cash_full, 0.0)


class AblationBuilderTests(unittest.TestCase):
    def _plan(self) -> re.ExportPlan:
        return re.ExportPlan(
            selection_start=date(2023, 1, 2),
            selection_end=date(2023, 1, 10),
            holdout_start=date(2023, 1, 16),
            holdout_end=date(2023, 1, 20),
        )

    def test_build_covers_every_run_combination_and_day(self):
        runs = abl.load_runs(abl.load_registry(REGISTRY_PATH))
        rows = abl.build_ablation_export(re.synthetic_events(), runs, self._plan())
        day_count = 9 + 5
        self.assertEqual(len(rows), len(runs) * len(re.ALLOWED_COMBINATIONS) * day_count)
        self.assertEqual({row.config_id for row in rows}, {run.variant_id for run in runs})
        validate_replay_coverage(rows, runs)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "rows.csv"
            re.write_rows_csv(rows, path)
            loaded = abl.load_ablation_rows(path, runs)
            self.assertEqual(len(loaded), len(rows))

    def test_out_of_cut_day_is_rejected(self):
        runs = abl.load_runs(abl.load_registry(REGISTRY_PATH))
        event = _event(date(2023, 1, 15), "EUR-OUT-OF-CUT")
        with self.assertRaises(ValidationError):
            abl.build_ablation_export([event], runs, self._plan())

    def test_same_session_repeat_is_not_an_order(self):
        runs = abl.load_runs(abl.load_registry(REGISTRY_PATH))
        first = _event(date(2023, 1, 3), "EUR-A")
        second = _event(date(2023, 1, 3), "EUR-B")
        second = re.ObservedEvent(
            server_day=second.server_day,
            sequence=2,
            event_id=second.event_id,
            combination=second.combination,
            **{k: v for k, v in asdict(second).items() if k not in {"server_day", "sequence", "event_id", "combination"}},
        )
        rows = abl.build_ablation_export([first, second], runs, self._plan())
        key = (runs[0].variant_id, "WALK_FORWARD", date(2023, 1, 3), "EURUSD_LONDON")
        day_rows = [row for row in rows if (row.config_id, row.split, row.server_day, row.combination) == key]
        self.assertEqual(len(day_rows), 2)
        activated = [row for row in day_rows if row.activation_ok]
        refused = [row for row in day_rows if not row.activation_ok]
        self.assertEqual(len(activated), 1)
        self.assertEqual(len(refused), 1)


class AblationDecisionTests(unittest.TestCase):
    def _paired(self, mean: float, lower: float, upper: float,
                variant_fills: float, baseline_fills: float) -> dict:
        return {
            "observed_mean_difference_r": mean,
            "familywise_adjusted_interval": [lower, upper],
            "variant_fills": variant_fills,
            "baseline_fills": baseline_fills,
        }

    def test_r1_failure_blocks_everything(self):
        run = abl.load_runs(abl.load_registry(REGISTRY_PATH))[1]
        paired = self._paired(0.2, 0.10, 0.30, 200, 100)
        decision, why = abl.decide(run, ["EURUSD_LONDON:fill_count"], [], paired, abl.AblationSettings(), 100)
        self.assertEqual(decision, "not_eligible")
        self.assertIn("EURUSD_LONDON:fill_count", why)

    def test_superiority_threshold(self):
        run = abl.load_runs(abl.load_registry(REGISTRY_PATH))[1]
        paired = self._paired(0.20, 0.10, 0.30, 200, 100)
        decision, _ = abl.decide(run, [], [], paired, abl.AblationSettings(), 100)
        self.assertEqual(decision, "superior")

    def test_simpler_tie_requires_opportunity_premium_and_no_harm(self):
        run = abl.load_runs(abl.load_registry(REGISTRY_PATH))[1]
        paired = self._paired(-0.01, -0.02, 0.01, 150, 100)
        decision, why = abl.decide(run, [], [], paired, abl.AblationSettings(), 100)
        self.assertEqual(decision, "simpler_tie")
        self.assertTrue(any("1.20x" in line for line in why))

    def test_simpler_without_opportunity_premium_is_not_adopted(self):
        run = abl.load_runs(abl.load_registry(REGISTRY_PATH))[1]
        paired = self._paired(-0.01, -0.02, 0.01, 110, 100)
        decision, _ = abl.decide(run, [], [], paired, abl.AblationSettings(), 100)
        self.assertEqual(decision, "not_adopted")

    def test_simpler_with_significant_harm_is_not_adopted(self):
        run = abl.load_runs(abl.load_registry(REGISTRY_PATH))[1]
        paired = self._paired(-0.06, -0.08, -0.04, 200, 100)
        decision, _ = abl.decide(run, [], [], paired, abl.AblationSettings(), 100)
        self.assertEqual(decision, "not_adopted")

    def test_non_simpler_variant_needs_superiority(self):
        run = abl.load_runs(abl.load_registry(REGISTRY_PATH))[2]
        paired = self._paired(0.01, -0.01, 0.03, 200, 100)
        decision, _ = abl.decide(run, [], [], paired, abl.AblationSettings(), 100)
        self.assertEqual(decision, "not_adopted")


class AblationPairedTests(unittest.TestCase):
    def test_paired_differences_include_extra_opportunity(self):
        config = _config()
        base_days = [date(2023, 1, 3), date(2023, 1, 4), date(2023, 1, 5)]
        weak_days = [date(2023, 1, 6), date(2023, 1, 9)]
        baseline_rows = [re.derive_event_rows(_event(day, f"B-{day}"), config)[0] for day in base_days]
        variant_spec = abl.ABL_RUNS[1].entry_spec
        variant_rows = [
            abl.derive_ablation_event_rows(
                _event(day, f"V-{day}", overrides={"displacement_open": 1.08035, "displacement_close": 1.08035}),
                config, variant_spec, variant_id="ABL-V1-SIMPLER-RECLAIM",
            )[0]
            for day in base_days + weak_days
        ]
        differences, variant_fills, baseline_fills = abl.paired_day_differences(
            variant_rows, baseline_rows, abl.FillPolicy(), seed=1
        )
        self.assertEqual(len(differences), 5)
        self.assertEqual(variant_fills, 5)
        self.assertEqual(baseline_fills, 3)
        # Days with no baseline fill contribute the variant's full net R.
        extra = [entry for entry in differences if entry[1] == "EURUSD_LONDON" and entry[4] == 0]
        self.assertEqual(len(extra), 2)
        self.assertGreater(extra[0][2], 0.0)

    def test_bootstrap_interval_is_finite_and_deterministic(self):
        config = _config()
        days = [date(2023, 1, 3), date(2023, 1, 4), date(2023, 1, 5), date(2023, 1, 6)]
        rows = [
            abl.derive_ablation_event_rows(
                _event(day, f"V-{day}"), config, abl.ABL_RUNS[1].entry_spec,
                variant_id="ABL-V1-SIMPLER-RECLAIM",
            )[0]
            for day in days
        ]
        differences, _, _ = abl.paired_day_differences(rows, [], abl.FillPolicy(), seed=1)
        first = abl.paired_bootstrap_interval(
            differences, samples=100, block_days=5, alpha=0.05, family_size=5, seed=7
        )
        second = abl.paired_bootstrap_interval(
            differences, samples=100, block_days=5, alpha=0.05, family_size=5, seed=7
        )
        self.assertEqual(first, second)
        self.assertEqual(first["usable_samples"], 100)
        self.assertIsNotNone(first["observed_mean_difference_r"])
        lower, upper = first["familywise_adjusted_interval"]
        self.assertLessEqual(lower, upper)


def _write_event_csv(path: Path, events):
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(re.EVENT_FIELDS))
        writer.writeheader()
        for event in events:
            raw = {
                key: (value.isoformat() if isinstance(value, date) else value)
                for key, value in asdict(event).items()
            }
            writer.writerow({
                key: ("" if value is None else (str(value).lower() if isinstance(value, bool) else value))
                for key, value in raw.items()
            })


def _weekdays(range_start, range_end, count):
    result = []
    current = range_start
    while current <= range_end and len(result) < count:
        if current.weekday() < 5:
            result.append(current)
        current = date.fromordinal(current.toordinal() + 1)
    return result


class AblationEvaluateEndToEndTests(unittest.TestCase):
    def _scenario(self, tmpdir: Path, weak_days_selection: int, weak_days_holdout: int,
                  holdout_base_days: int = 100):
        registry = abl.load_registry(REGISTRY_PATH)
        selection_start, selection_end, holdout_start, holdout_end = abl.declared_splits(registry)
        # Base days span two calendar years so the year-robustness gate can
        # pass; base days and weak days are DISJOINT (one signal per session/day
        # means a weak event on a base day could never become a variant fill).
        selection_days = (
            _weekdays(date(2019, 1, 1), selection_end, 60)
            + _weekdays(date(2021, 1, 1), selection_end, 60)
        )
        weak_selection_days = _weekdays(date(2022, 1, 1), selection_end, weak_days_selection)
        # R3 requires >= 300 holdout fills on each side: 100 base days *
        # 3 combinations = 300 baseline fills; weak days add variant-only fills.
        holdout_days = _weekdays(holdout_start, holdout_end, holdout_base_days)
        weak_holdout_days = _weekdays(date(2025, 3, 1), holdout_end, weak_days_holdout)
        events = []
        for index, day in enumerate(selection_days + holdout_days):
            for combination in sorted(re.ALLOWED_COMBINATIONS):
                events.append(
                    _event(day, f"BASE-{index}-{combination}", combination=combination)
                )
        # Extra weak-displacement signals: only V1 can act on them.
        for index, day in enumerate(weak_selection_days + weak_holdout_days):
            for combination in sorted(re.ALLOWED_COMBINATIONS):
                events.append(
                    _event(
                        day,
                        f"WEAK-{index}-{combination}",
                        combination=combination,
                        overrides={"displacement_open": 1.08035, "displacement_close": 1.08035},
                    )
                )
        event_path = Path(tmpdir) / "events.csv"
        _write_event_csv(event_path, events)
        rows_path = Path(tmpdir) / "rows.csv"
        report_path = Path(tmpdir) / "report.json"
        self.assertEqual(
            abl.main([
                "build",
                "--event-file", str(event_path),
                "--registry", str(REGISTRY_PATH),
                "--selection-split", selection_start.isoformat(), selection_end.isoformat(),
                "--holdout-split", holdout_start.isoformat(), holdout_end.isoformat(),
                "--output", str(rows_path),
            ]),
            0,
        )
        self.assertEqual(
            abl.main([
                "validate",
                "--registry", str(REGISTRY_PATH),
                "--input", str(rows_path),
                "--output", str(report_path),
            ]),
            0,
        )
        return rows_path, json.loads(report_path.read_text(encoding="utf-8"))

    def test_flat_scenario_recommends_no_change(self):
        with tempfile.TemporaryDirectory() as tmp:
            _, report = self._scenario(Path(tmp), 0, 0)
            self.assertEqual(report["outcome"]["result"], "NO_CHANGE_SUPPORTED")
            self.assertEqual(len(report["variants"]), 5)
            for block in report["variants"]:
                self.assertTrue(block["r1_gates_pass"], block["variant_id"])
                self.assertEqual(block["decision"], "not_adopted")
            self.assertEqual(report["outcome"]["confirmed_variants"], [])

    def test_v1_dominance_is_confirmed_on_holdout(self):
        with tempfile.TemporaryDirectory() as tmp:
            _, report = self._scenario(Path(tmp), 50, 10)
            self.assertEqual(report["outcome"]["result"], "VARIANT_SUPPORTED")
            self.assertEqual(
                report["outcome"]["confirmed_variant"], "ABL-V1-SIMPLER-RECLAIM"
            )
            v1 = next(
                block for block in report["variants"]
                if block["variant_id"] == "ABL-V1-SIMPLER-RECLAIM"
            )
            self.assertIn(v1["decision"], {"superior", "simpler_tie"})
            self.assertGreater(v1["paired"]["variant_fills"], v1["paired"]["baseline_fills"])
            confirmation = report["holdout_confirmations"]["ABL-V1-SIMPLER-RECLAIM"]
            self.assertTrue(confirmation["confirmed"])
            self.assertGreaterEqual(confirmation["variant_holdout_expectancy_r"], 0.0)


class AblationCliTests(unittest.TestCase):
    def test_preregister_refuses_overwrite_then_forces(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "registry.json"
            self.assertEqual(abl.main(["preregister", "--output", str(path)]), 0)
            self.assertEqual(abl.main(["preregister", "--output", str(path)]), 2)
            self.assertEqual(
                abl.main(["preregister", "--output", str(path), "--force"]), 0
            )
            self.assertEqual(abl.load_registry(path), abl.build_registry())

    def test_build_rejects_different_split(self):
        with tempfile.TemporaryDirectory() as tmp:
            event_path = Path(tmp) / "events.csv"
            _write_event_csv(event_path, [_event(date(2023, 1, 3), "EUR-1")])
            self.assertEqual(
                abl.main([
                    "build",
                    "--event-file", str(event_path),
                    "--registry", str(REGISTRY_PATH),
                    "--selection-split", "2023-01-01", "2024-12-31",
                    "--holdout-split", "2025-01-01", "2026-08-31",
                    "--output", str(Path(tmp) / "rows.csv"),
                ]),
                2,
            )


if __name__ == "__main__":
    unittest.main()
