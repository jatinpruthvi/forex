"""Contract tests for the ChartFanatics plan/build/judge loop (``chartfanatics/loop/cf_loop.py``).

The loop is the worker, not the acceptance officer, so these tests pin the properties that keep it
honest - the same five failure modes the ``loop-design-check`` skill lists, plus the human red line:

* mode 1 (vague goal spins): every card has a spec whose checks are all implemented ids;
* mode 2 (self-verification): the judge must refuse to be edited by the builder (fingerprint);
* mode 3 (agent deletes the tests): a tampered spec, a changed judge script or a deleted test file
  is detected, and the rule floor cannot be lowered once a card has been judged;
* mode 4 (no runtime clarification): a card whose Tracking block is still ``_TBD_`` fails;
* mode 5 (stale docs): specs and ``manifest.json`` must agree, so the queue cannot drift from the
  board;
* red line: the judge can never set ``done`` and the retry cap escalates to a human.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import shutil
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
CF_LOOP = REPO / "chartfanatics" / "loop" / "cf_loop.py"

_spec = importlib.util.spec_from_file_location("cf_loop", CF_LOOP)
cf = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cf)

BUILT_SLUGS = [
    "5-stage-trading-framework", "amd-model", "structure-ote", "smt-divergence-po3",
    "po3-ote-adr", "break-retest", "intraday-liquidity-volatility-model",
]


class PlanTests(unittest.TestCase):
    def test_every_card_has_a_decidable_spec(self) -> None:
        slugs = cf.all_slugs()
        self.assertEqual(len(slugs), 47)
        for slug in slugs:
            spec = cf.load_spec(slug)
            self.assertIsNotNone(spec, f"{slug}: no spec (run `cf_loop.py plan --all`)")
            unknown = [c for c in spec["checks"] if c not in cf.CHECKS]
            self.assertEqual(unknown, [], f"{slug}: unknown check ids {unknown}")
            self.assertGreaterEqual(int(spec["rule_count"]), cf.MIN_RULES_NEW_CARD, slug)
            low, high = cf.family_block()
            self.assertTrue(low <= int(spec["magic"]) <= high, slug)
            self.assertEqual(spec["acceptance_hash"], cf.spec_hash(spec),
                             f"{slug}: stored hash does not match the spec (edited outside replan?)")

    def test_specs_and_manifest_agree(self) -> None:
        for slug, row in cf.manifest_by_slug().items():
            spec = cf.load_spec(slug)
            self.assertEqual(spec["ea"], row["ea"], slug)
            self.assertEqual(int(spec["magic"]), int(row["magic"]), slug)

    def test_magic_block_has_room_and_no_duplicates(self) -> None:
        low, high = cf.family_block()
        self.assertEqual(high - low + 1, len(cf.all_slugs()),
                         "the block must be exactly one magic per card")
        magics = [int(cf.load_spec(s)["magic"]) for s in cf.all_slugs()]
        self.assertEqual(len(magics), len(set(magics)), "duplicate magic allocated")

    def test_plan_all_is_idempotent(self) -> None:
        # running plan --all twice must keep every magic and never exhaust the block
        tmp = Path(tempfile.mkdtemp())
        saved = (cf.SPECS, cf.STATE_PATH)
        cf.SPECS = tmp / "specs"
        cf.STATE_PATH = tmp / "state.json"
        try:
            cf.main(["plan", "--all", "--by", "test"])
            first = {slug: cf.load_spec(slug)["magic"] for slug in cf.all_slugs()}
            cf.main(["plan", "--all", "--by", "test"])
            second = {slug: cf.load_spec(slug)["magic"] for slug in cf.all_slugs()}
            self.assertEqual(first, second)
            self.assertEqual(len(set(second.values())), len(cf.all_slugs()), "magics collided")
            low, high = cf.family_block()
            self.assertTrue(all(low <= m <= high for m in second.values()))
        finally:
            cf.SPECS, cf.STATE_PATH = saved
            shutil.rmtree(tmp, ignore_errors=True)

    def test_replan_cannot_lower_the_rule_floor(self) -> None:
        tmp = Path(tempfile.mkdtemp())
        saved = (cf.SPECS, cf.STATE_PATH)
        cf.SPECS = tmp / "specs"
        cf.STATE_PATH = tmp / "state.json"
        try:
            cf.main(["plan", "amd-model", "--by", "test"])
            cf.main(["plan", "amd-model", "--by", "test", "--rule-count", "1"])
            self.assertGreaterEqual(int(cf.load_spec("amd-model")["rule_count"]), 10)
        finally:
            cf.SPECS, cf.STATE_PATH = saved
            shutil.rmtree(tmp, ignore_errors=True)

    def test_built_eas_have_rule_tables_at_their_floor(self) -> None:
        table = cf.sync_table()
        for slug in BUILT_SLUGS:
            spec = cf.load_spec(slug)
            rules = table.get(spec["ea"], [])
            self.assertGreaterEqual(len(rules), int(spec["rule_count"]),
                                    f"{slug}: rule table shrank below the spec floor")


class JudgeBoundaryTests(unittest.TestCase):
    def _spec(self) -> dict:
        return json.loads((cf.SPECS / "amd-model.json").read_text(encoding="utf-8"))

    def test_tampered_spec_is_detected(self) -> None:
        spec = self._spec()
        spec["rule_count"] = 1                       # the builder "lowers" acceptance
        ok, detail = cf.check_boundaries_intact(spec, argparse.Namespace())
        self.assertFalse(ok)
        self.assertIn("acceptance spec", detail)

    def test_changed_judge_script_is_detected(self) -> None:
        spec = self._spec()
        spec["acceptance_hash"] = cf.spec_hash(spec)  # hash itself is fine
        spec["judge_hash"] = {"scripts/check_mql5_source.py": "0" * 64}
        ok, detail = cf.check_boundaries_intact(spec, argparse.Namespace())
        self.assertFalse(ok)
        self.assertIn("judge changed", detail)

    def test_adding_its_own_rule_table_does_not_trip_the_boundary(self) -> None:
        # the build MUST extend tests/test_chartfanatics_sync.py with the card's own rule table;
        # that is the deliverable, not tampering - the fingerprint excludes this card's own table
        spec = self._spec()
        spec["judge_hash"] = cf.judge_fingerprint(spec["ea"])
        spec["acceptance_hash"] = cf.spec_hash(spec)
        ok, detail = cf.check_boundaries_intact(spec, argparse.Namespace())
        self.assertTrue(ok, detail)

    def test_rewriting_another_cards_rules_is_detected(self) -> None:
        # ... but nobody may touch a table a finished card was judged against
        spec = self._spec()
        spec["judge_hash"] = cf.judge_fingerprint(spec["ea"])
        spec["judge_hash"]["tests/test_chartfanatics_sync.py#other_cards"] = "0" * 64
        spec["acceptance_hash"] = cf.spec_hash(spec)
        ok, detail = cf.check_boundaries_intact(spec, argparse.Namespace())
        self.assertFalse(ok)
        self.assertIn("other_cards", detail)

    def test_sync_machinery_hash_ignores_per_card_surfaces(self) -> None:
        # the docstring (where cards record their [interpretation] notes) must not freeze the judge
        before = cf.sync_machinery_hash()
        original = cf.SYNC_TEST
        text = original.read_text(encoding="utf-8")
        first = text.index('"""')
        second = text.index('"""', first + 3) + 3
        edited = text[:first] + text[first:second].replace("interpretation", "INTERPRETATION") + text[second:]
        self.assertNotEqual(edited, text)
        tmpdir = Path(tempfile.mkdtemp())          # the temp COPY lives here; the repo file is untouched
        try:
            cf.SYNC_TEST = tmpdir / "sync.py"
            cf.SYNC_TEST.write_text(edited, encoding="utf-8")
            self.assertEqual(before, cf.sync_machinery_hash(),
                             "the machinery hash must not depend on the docstring")
            cf.SYNC_TEST.write_text(edited.replace("class SyncTests", "class SyncTestsRenamed"),
                                    encoding="utf-8")
            self.assertNotEqual(before, cf.sync_machinery_hash(),
                                "changing the judging class IS a machinery change")
        finally:
            cf.SYNC_TEST = original                # never leave the module pointing at the temp copy
            shutil.rmtree(tmpdir, ignore_errors=True)

    def test_sync_machinery_hash_ignores_the_table_content(self) -> None:
        # the hash must be blind to which rules are listed, and sensitive to the logic around them
        before = cf.sync_machinery_hash()
        text = cf.SYNC_TEST.read_text(encoding="utf-8")
        start = text.index(cf.SYNC_TABLE_MARK)
        end = text.index(cf.SYNC_TABLE_END)
        tampered = text[:start] + cf.SYNC_TABLE_MARK + "\n    \"EA_X.mq5\": [(r\"r\", \"n\")],\n}" + text[end:]
        self.assertNotEqual(tampered, text)
        self.assertEqual(before, cf.sync_machinery_hash(),
                         "the machinery hash must not depend on the table's contents")

    def test_deleted_test_file_is_detected(self) -> None:
        spec = self._spec()
        spec["acceptance_hash"] = cf.spec_hash(spec)
        spec["tests_snapshot"] = list(spec["tests_snapshot"]) + ["test_that_never_existed.py"]
        ok, detail = cf.check_boundaries_intact(spec, argparse.Namespace())
        self.assertFalse(ok)
        self.assertIn("deleted since plan", detail)

    def test_rule_floor_cannot_be_lowered_after_judging(self) -> None:
        spec = cf.load_spec("amd-model")
        before = cf.spec_path("amd-model").read_text(encoding="utf-8")
        args = argparse.Namespace(slug="amd-model", rule_count=1, by="tester", ea=None)
        with self.assertRaises(SystemExit):
            cf.cmd_replan(args)
        self.assertEqual(before, cf.spec_path("amd-model").read_text(encoding="utf-8"),
                         "a refused replan must not touch the spec")

    def test_tbd_tracking_block_fails_the_card(self) -> None:
        card = REPO / "chartfanatics" / "todos" / "amd-model.md"
        tmp = Path(tempfile.mkdtemp()) / "card.md"
        text = re.sub(r"\*\*Verdict:\*\*[^\n]*", "**Verdict:** _TBD_",
                      card.read_text(encoding="utf-8"), count=1)
        tmp.write_text(text, encoding="utf-8")
        ok, detail = cf.card_tracking_filled(tmp)
        self.assertFalse(ok)
        self.assertIn("Verdict", detail)
        shutil.rmtree(tmp.parent, ignore_errors=True)

    def test_full_judge_passes_for_every_built_card(self) -> None:
        args = argparse.Namespace(reports_dir=str(REPO / "validation" / "mt5_harness" / "out" / "reports"))
        for slug in BUILT_SLUGS:
            spec = cf.load_spec(slug)
            verdict = cf.run_judge(spec, args)
            failed = [f"{r['check']}: {r['detail']}" for r in verdict["failed"]]
            self.assertEqual(verdict["verdict"], "pass", f"{slug}: " + "; ".join(failed))


class DampingAndRedLineTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())
        self._saved = (cf.STATE_PATH, cf.SPECS, cf.CARDS)
        cf.STATE_PATH = self.tmp / "state.json"
        cf.SPECS = self.tmp / "specs"
        cf.SPECS.mkdir(parents=True, exist_ok=True)
        cf.CARDS = self.tmp / "cards"
        cf.CARDS.mkdir(parents=True, exist_ok=True)
        self.slug = "amd-model"
        self.spec = json.loads((self._saved[1] / "amd-model.json").read_text(encoding="utf-8"))
        # only the cheap check, so the test does not shell out - then re-hash, exactly like replan
        self.spec["checks"] = ["ea_exists"]
        self.spec["acceptance_hash"] = cf.spec_hash(self.spec)
        cf.save_json(cf.spec_path(self.slug), self.spec)

    def tearDown(self) -> None:
        cf.STATE_PATH, cf.SPECS, cf.CARDS = self._saved
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _state(self) -> dict:
        return json.loads(cf.STATE_PATH.read_text(encoding="utf-8"))

    def _set_state(self, state: str, attempts: int = 0) -> None:
        cf.save_json(cf.STATE_PATH, {"cards": {self.slug: {"state": state, "attempts": attempts}}})

    def test_judge_never_sets_done(self) -> None:
        self._set_state("built", attempts=1)
        cf.cmd_judge(argparse.Namespace(slug=self.slug, pending=False, reports_dir=None))
        self.assertNotEqual(self._state()["cards"][self.slug]["state"], "done")

    def test_signoff_refuses_without_a_pass(self) -> None:
        self._set_state("planned", attempts=1)
        with self.assertRaises(SystemExit):
            cf.cmd_signoff(argparse.Namespace(slug=self.slug, by="tester"))

    def test_signoff_requires_a_name_and_a_pass(self) -> None:
        self._set_state("awaiting_human", attempts=1)
        cf.save_json(cf.STATE_PATH, {"cards": {self.slug: {
            "state": "awaiting_human", "attempts": 1, "last_verdict": "pass"}}})
        cf.cmd_signoff(argparse.Namespace(slug=self.slug, by="Jatin"))
        entry = self._state()["cards"][self.slug]
        self.assertEqual(entry["state"], "done")
        self.assertEqual(entry["signed_off_by"], "Jatin")

    def test_handoff_escalates_at_the_cap(self) -> None:
        self._set_state("planned", attempts=cf.ATTEMPT_CAP)
        with self.assertRaises(SystemExit):
            cf.cmd_handoff(argparse.Namespace(slug=self.slug, by="tester"))
        self.assertEqual(self._state()["cards"][self.slug]["state"], "escalated")

    def test_diagnostic_judge_does_not_burn_an_attempt(self) -> None:
        spec = dict(self.spec, ea="EA_CF_Not_Written.mq5")
        cf.save_json(cf.spec_path(self.slug), spec)
        self._set_state("planned", attempts=0)
        cf.cmd_judge(argparse.Namespace(slug=self.slug, pending=False, reports_dir=None))
        entry = self._state()["cards"][self.slug]
        self.assertEqual(entry["attempts"], 0)
        self.assertEqual(entry["state"], "planned")
        self.assertIn("diagnostic run", entry["last_reason"])

    def test_handoff_counts_the_attempt_and_judge_consumes_it(self) -> None:
        spec = dict(self.spec, ea="EA_CF_Never_Written.mq5")
        spec["acceptance_hash"] = cf.spec_hash(spec)
        cf.save_json(cf.spec_path(self.slug), spec)
        self._set_state("planned", attempts=0)
        cf.cmd_handoff(argparse.Namespace(slug=self.slug, by="tester"))
        entry = self._state()["cards"][self.slug]
        self.assertEqual((entry["state"], entry["attempts"]), ("built", 1))
        cf.cmd_judge(argparse.Namespace(slug=self.slug, pending=False, reports_dir=None))
        entry = self._state()["cards"][self.slug]
        self.assertEqual(entry["state"], "planned")     # failed: back to the builder
        self.assertEqual(entry["attempts"], 1)


class StatusTests(unittest.TestCase):
    def test_status_write_is_idempotent(self) -> None:
        tmp = Path(tempfile.mkdtemp())
        doc = tmp / "LOOP.md"
        doc.write_text("# doc\n\n" + cf.STATUS_START + "\n" + cf.STATUS_END + "\n", encoding="utf-8")
        saved = cf.LOOP_DOC
        cf.LOOP_DOC = doc
        try:
            cf._write_status_block("first")
            cf._write_status_block("second")
            text = doc.read_text(encoding="utf-8")
            self.assertEqual(text.count(cf.STATUS_START), 1)
            self.assertEqual(text.count(cf.STATUS_END), 1)
            self.assertIn("second", text)
            self.assertNotIn("first", text)
        finally:
            cf.LOOP_DOC = saved
            shutil.rmtree(tmp, ignore_errors=True)

    def test_loop_doc_exists_and_links_the_runner(self) -> None:
        doc = REPO / "chartfanatics" / "LOOP.md"
        self.assertTrue(doc.is_file())
        self.assertIn("loop/cf_loop.py", doc.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
