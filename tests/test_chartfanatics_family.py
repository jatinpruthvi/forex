"""Contract tests for the ChartFanatics EA family (chartfanatics/mql5-eas/).

The family is built from the playbook PDFs archived in ``chartfanatics/`` and each EA is
registered in ``chartfanatics/mql5-eas/manifest.json``, which the tracker generator
(``chartfanatics/gen_todos.py``) reads to fill the work cards.  These tests pin the
properties that keep that chain honest:

* every EA still passes the repository's static contract checker;
* magics are unique and inside the family block reserved for these cards;
* the manifest and the files on disk agree (no orphan EA, no dead manifest row);
* the card-#01 guardrail EA never trades - it is a monitor, not a strategy;
* the per-stage policy helper exists, stages 1-4 tighten, and stage 5 is a true no-op.
"""
from __future__ import annotations

import importlib.util
import json
import re
import subprocess
import sys
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FAMILY_DIR = REPO / "chartfanatics" / "mql5-eas"
MANIFEST_PATH = FAMILY_DIR / "manifest.json"
CHECKER = REPO / "scripts" / "check_mql5_source.py"
EACORE = REPO / "MQL5_Master" / "Include" / "EACore.mqh"

_spec = importlib.util.spec_from_file_location("chk", CHECKER)
chk = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(chk)


class FamilyLayoutTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        cls.entries = cls.manifest["eas"]
        cls.ea_files = sorted(p.name for p in FAMILY_DIR.glob("*.mq5"))

    def test_manifest_and_files_agree(self) -> None:
        listed = sorted(e["ea"] for e in self.entries)
        self.assertEqual(listed, self.ea_files,
                         "manifest.json and chartfanatics/mql5-eas/*.mq5 disagree")
        for entry in self.entries:
            self.assertTrue((FAMILY_DIR / entry["ea"]).is_file(), entry["ea"])
            self.assertTrue((REPO / entry["source"]).is_file(), entry["source"])
            card = REPO / "chartfanatics" / "todos" / f"{entry['slug']}.md"
            self.assertTrue(card.is_file(), f"no work card for {entry['slug']}")

    def test_magics_are_unique_and_inside_the_family_block(self) -> None:
        low, high = self.manifest["magic_block"]
        magics = [e["magic"] for e in self.entries]
        self.assertEqual(len(magics), len(set(magics)), f"duplicate magic in: {magics}")
        for magic in magics:
            self.assertGreaterEqual(magic, low)
            self.assertLessEqual(magic, high)
        # the input default in the source must match the manifest (the engine reads the input)
        for entry in self.entries:
            source = (FAMILY_DIR / entry["ea"]).read_text(encoding="utf-8")
            self.assertRegex(source, rf"InpMagicNumber\s*=\s*{entry['magic']}\s*;", entry["ea"])

    def test_every_ea_passes_the_static_contract_checker(self) -> None:
        out = subprocess.run([sys.executable, str(CHECKER), *[str(FAMILY_DIR / f) for f in self.ea_files]],
                             capture_output=True, text=True)
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
        self.assertIn(f"checked {len(self.ea_files)} files", out.stdout)
        self.assertIn("0 finding(s)", out.stdout)

    def test_deploy_folder_matches_the_include_depth(self) -> None:
        # "..\\..\\Include\\EACommon.mqh" only resolves at MQL5\Experts\chartfanatics\
        self.assertEqual(self.manifest["deploy_to"], "MQL5\\Experts\\chartfanatics\\")
        for name in self.ea_files:
            source = (FAMILY_DIR / name).read_text(encoding="utf-8")
            self.assertIn(r"..\..\Include\EACommon.mqh", source, name)


class StageGuardrailTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        cls.source = (FAMILY_DIR / "EA_CF_Stage_Guardrails.mq5").read_text(encoding="utf-8")

    def test_the_monitor_never_trades(self) -> None:
        entry = next(e for e in self.manifest["eas"] if e["slug"] == "5-stage-trading-framework")
        self.assertIs(entry["trades"], False)
        self.assertIn("bool AllowTrading(SEAContext &ctx) { return false; }", self.source)
        self.assertRegex(self.source, r"bool BuildPlan\(SEAContext &ctx, SSignalPlan &plan\)\s*\{\s*plan\.Reset\(\);\s*return false;\s*\}")
        # no order-submitting or position-closing API may appear anywhere in a monitor
        for forbidden in ("EA_FlattenAll", "CloseAll", "OrderSend", "PositionClose", "SendDualBracket"):
            self.assertNotIn(forbidden, self.source, forbidden)

    def test_the_monitor_reads_the_whole_account_but_not_only_its_own_magic(self) -> None:
        # a monitor that filtered by DEAL_MAGIC would be blind to manual trading and to other EAs
        self.assertIn("HistorySelect(dayStart", self.source)
        self.assertNotIn("DEAL_MAGIC", self.source)

    def test_the_monitor_journals_and_logs_once_per_breach_type(self) -> None:
        self.assertIn('input string InpJournalFile        = "cf_stage_journal.csv"', self.source)
        self.assertIn("m_breachMask", self.source)
        self.assertRegex(self.source, r"if\(\(m_breachMask & flag\) != 0\) return;")

    def test_it_reads_the_stage_table_from_the_engine_helper(self) -> None:
        # one source of truth: the monitor and the playbook EAs share EA_ApplyStagePolicy()
        self.assertIn("EA_ApplyStagePolicy(policy, InpStage);", self.source)
        self.assertNotIn("case 1:  riskMult", self.source)   # no second copy of the table


class StagePolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.engine = EACORE.read_text(encoding="utf-8")
        cls.body = cls.engine.split("void EA_ApplyStagePolicy(SEASettings &cfg, const int stage)", 1)[1]
        cls.body = cls.body.split("\n}", 1)[0]

    def test_stage_five_is_a_true_no_op(self) -> None:
        self.assertIn("if(s == 5) return;", self.body)
        # nothing may be assigned before that early return
        before_return = self.body.split("if(s == 5) return;", 1)[0]
        self.assertNotRegex(before_return, r"cfg\.\w+\s*=")

    def test_stages_one_to_four_tighten_and_never_loosen(self) -> None:
        self.assertRegex(self.body, r"case 1:\s*riskMult = 0\.25; riskCeiling = 0\.25; maxTrades = 1;")
        self.assertRegex(self.body, r"case 2:\s*riskMult = 0\.50; riskCeiling = 0\.50; maxTrades = 2;")
        self.assertRegex(self.body, r"case 3:\s*riskMult = 0\.75; riskCeiling = 0\.75; maxTrades = 3;")
        # caps are only ever lowered, and static-lot sizing is left alone
        self.assertIn("if(maxTrades > 0 && (cfg.maxTradesPerDay == 0 || cfg.maxTradesPerDay > maxTrades))", self.body)
        self.assertIn("if(cfg.staticLots <= 0.0 && cfg.riskPct > 0.0)", self.body)
        self.assertIn("if(riskCeiling > 0.0 && cfg.riskPct > riskCeiling) cfg.riskPct = riskCeiling;", self.body)

    def test_every_playbook_ea_applies_the_stage_policy(self) -> None:
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        for entry in manifest["eas"]:
            if entry.get("trades") is False:
                continue
            source = (FAMILY_DIR / entry["ea"]).read_text(encoding="utf-8")
            self.assertRegex(source, r"input int\s+InpStage\s*=", entry["ea"])
            self.assertIn("EA_ApplyStagePolicy(cfg, InpStage);", source, entry["ea"])
            # default must be the no-op stage, so selecting a stage is always explicit
            self.assertRegex(source, r"InpStage\s*=\s*5\s*;", entry["ea"])


if __name__ == "__main__":
    unittest.main()
