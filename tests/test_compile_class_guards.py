"""Guards for the compile-error classes the delivered checkers could not see.

There is no MetaEditor in this sandbox, so the repo's static checkers are the only
stand-in for a compiler.  Reading the 65 EAs for strategy bugs (top-25 sweep #2)
turned up SIXTEEN EAs that could not compile - and the one-program portfolio build
that inlines them could not either - because the checkers only looked at *calls*:

  * `bool long = ...` / `bool short = ...`           (reserved words as names)
  * `EA_MAX_SYM`, `InpAplusScore`, host `InpSummary` (identifiers declared nowhere)
  * `ep.emaPeriod`, `ep.maxDistanceAtr`, `ep.requireTrend` on a struct that has no
    such members (13 EAs), and `ctx.adxD1` on a context that never had it (R4B)

Each rule now has a positive control (it fires on the defect), a negative control
(valid MQL5 is not flagged) and a repo-wide assertion (the delivery is clean).
"""
from __future__ import annotations

import importlib.util
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("chk", REPO / "scripts" / "check_mql5_source.py")
chk = importlib.util.module_from_spec(spec)
spec.loader.exec_module(chk)

ADD = REPO / "MQL5_Master" / "Experts" / "additionalEAs"
INC = REPO / "MQL5_Master" / "Include"


def _scan(snippet: str):
    """Run every identifier/scope rule on a snippet written to a temp .mq5."""
    with tempfile.TemporaryDirectory() as td:
        p = Path(td) / "sample.mq5"
        p.write_text(snippet, encoding="utf-8")
        raw = p.read_text(encoding="utf-8")
        src = chk.strip_noise(raw)
        return (chk.check_identifiers(p, src), chk.check_members(p, src),
                chk.check_duplicate_declarations(p, src),
                chk.check_undeclared_variables(p, raw, src))


class ReservedWordTests(unittest.TestCase):
    def test_a_variable_named_after_a_data_type_is_flagged(self):
        ident, *_ = _scan("class C { bool F(){ bool long = true; bool short = false;\n"
                          "  if(!long && !short) return false;\n  int d = long ? 1 : -1; return true; } };")
        text = "\n".join(ident)
        self.assertIn("'long' used as a variable name", text)
        self.assertIn("'short' used as a variable name", text)
        self.assertIn("'long' used as a value", text)

    def test_valid_uses_of_the_type_names_are_not_flagged(self):
        ident, *_ = _scan("input ulong InpMagicNumber = 1;\nclass C { long Id(const long a, ulong b)\n"
                          "{ long x = (long)a + (long)b; ushort s = (ushort)3; int n = (int)MathMin(1,2);\n"
                          "  double d = double(n); return x + (long)sizeof(long); } };")
        self.assertEqual([m for m in ident if "reserved" in m], [])


class UndeclaredIdentifierTests(unittest.TestCase):
    def test_a_misspelt_constant_is_flagged(self):
        ident, *_ = _scan("class C { bool F(SEAContext &ctx){ return ctx.index >= EA_MAX_SYM; } };")
        self.assertTrue(any("EA_MAX_SYM" in m for m in ident), ident)

    def test_the_real_constant_and_declared_inputs_pass(self):
        ident, *_ = _scan("input double InpGood = 1.0;\nclass C { bool F(SEAContext &ctx)\n"
                          "{ return ctx.index >= EA_MAX_SYMBOLS && InpGood > 0.0; } };")
        self.assertEqual(ident, [])

    def test_an_undeclared_input_is_flagged(self):
        ident, *_ = _scan("class C { double F(){ return InpNeverDeclared * 2.0; } };")
        self.assertTrue(any("InpNeverDeclared" in m for m in ident), ident)


class StructMemberTests(unittest.TestCase):
    def test_a_member_the_struct_does_not_have_is_flagged(self):
        _, members, *_ = _scan("class C { void F(){ SEmaPullbackParams ep; ep.Reset();\n"
                               "  ep.noSuchMember = 20; } };")
        self.assertTrue(any("ep.noSuchMember" in m for m in members), members)

    def test_a_context_field_that_was_never_declared_is_flagged(self):
        _, members, *_ = _scan("class C { bool F(SEAContext &ctx){ return ctx.neverDeclared > 1.0; } };")
        self.assertTrue(any("ctx.neverDeclared" in m for m in members), members)

    def test_the_same_name_in_two_functions_is_scoped_not_confused(self):
        # `p` is a sweep-params struct in one method and a signal plan in another;
        # `d` is a struct in one and a rates array in another - no false positives
        _, members, *_ = _scan(
            "class C {\n"
            " bool A(SEAContext &ctx, SSignalPlan &plan){ SSweepParams p; p.Reset(); p.targetR = 2.0; return true; }\n"
            " bool B(SEAContext &ctx, SSignalPlan &p){ return p.riskDist > 0.0; }\n"
            " void D(){ SDonchianParams d; d.lookbackDays = 5; }\n"
            " void E(){ MqlRates d[]; double x = d[0].high - d[0].low; }\n"
            "};")
        self.assertEqual(members, [])


class ScopeTests(unittest.TestCase):
    def test_a_duplicate_declaration_in_one_block_is_flagged_but_shadowing_is_not(self):
        *_, dup, _u = _scan("class C { bool F(SEAContext &ctx){ double hi = 1.0; int dir = 0;\n"
                            " if(ctx.atr > 0.0){ double hi = 2.0; }\n"
                            " double hi = 3.0; int dir = 1; return true; } };")
        self.assertEqual(sorted(re.findall(r"'(\w+)' is declared twice", "\n".join(dup))), ["dir", "hi"])

    def test_a_misspelt_variable_is_flagged(self):
        *_, undeclared = _scan("class C { double m_x;\n bool F(SEAContext &ctx){ double hi = 1.0; int dir = 0;\n"
                               " for(int i = 0; i < 3; i++) hi += i;\n"
                               " return (hi > lo) && (dir == dirr) && (m_x > 0.0) && (ctx.atr > sweepIndx); } };")
        names = sorted(re.findall(r"'(\w+)' is used but never declared", "\n".join(undeclared)))
        self.assertEqual(names, ["dirr", "lo", "sweepIndx"])


class RepoIsCleanTests(unittest.TestCase):
    """The delivery itself: 65 EAs, the shared headers, the Triad, the scripts, the
    tracker and the generated one-program portfolio build."""

    def _run(self, *paths: str):
        out = subprocess.run([sys.executable, str(REPO / "scripts" / "check_mql5_source.py"), *paths],
                             cwd=REPO, capture_output=True, text=True)
        return out.returncode, out.stdout

    def test_the_65_eas_have_no_compile_class_findings(self):
        eas = sorted(str(p.relative_to(REPO)) for p in ADD.glob("*.mq5"))
        # the 13 unpinned legacy skeletons are print-only files outside the delivery
        legacy = {"EA_adaptive_capital_matrix", "EA_apex_eigen_matrix", "EA_asymmetric_alpha_matrix",
                  "EA_master_combination_strategy", "EA_max_roi_out_of_box_strategy",
                  "EA_micro_live_falsification_protocol", "EA_omega_alpha_factory",
                  "EA_preflight_risk_review", "EA_recommendations_and_next_steps",
                  "EA_ruin_proofing_survival_budget", "EA_sovereign_adversarial_matrix",
                  "EA_strategy_recommendation", "EA_studyarena_round1_contestant_a"}
        eas = [e for e in eas if Path(e).stem not in legacy]
        self.assertEqual(len(eas), 65)
        code, out = self._run(*eas)
        self.assertEqual(code, 0, out[-1500:])

    def test_headers_triad_scripts_tracker_and_portfolio_build_are_clean(self):
        paths = [str(p.relative_to(REPO)) for p in sorted(INC.glob("*.mqh"))]
        paths += ["MQL5_Master/Experts/Master_Triad_V1.mq5", "portfolio-EA/src/PortfolioEA.mq5"]
        paths += [str(p.relative_to(REPO)) for p in sorted((REPO / "MQL5_Master" / "Scripts").glob("*.mq5"))]
        build = REPO / "portfolio-EA" / "build"
        if (build / "AllEnginesEA.mq5").exists():
            paths += ["portfolio-EA/build/AllEnginesEA.mq5", "portfolio-EA/build/PortfolioStrategies.mqh"]
        code, out = self._run(*paths)
        self.assertEqual(code, 0, out[-1500:])


class ConcreteFixTests(unittest.TestCase):
    def test_every_member_the_eas_assign_on_the_pullback_params_exists(self):
        sig = (INC / "EASignals.mqh").read_text(encoding="utf-8")
        body = sig[sig.index("struct SEmaPullbackParams"):sig.index("bool SigEmaPullback(")]
        declared = set(re.findall(r"^\s*(?:bool|int|double)\s+(\w+);", body, re.M))
        assigned = set()
        for ea in ADD.glob("*.mq5"):
            assigned |= set(re.findall(r"\bep\.(\w+)\s*=", ea.read_text(encoding="utf-8")))
        self.assertTrue({"emaPeriod", "maxDistanceAtr", "requireTrend"} <= assigned)
        self.assertEqual(sorted(assigned - declared), [])

    def test_the_pullback_params_are_honoured_by_the_detector(self):
        sig = (INC / "EASignals.mqh").read_text(encoding="utf-8")
        fn = sig[sig.index("bool SigEmaPullback("):sig.index("// 5. RANGE FADE") if "// 5. RANGE FADE" in sig
                 else sig.index("struct SRangeFadeParams")]
        self.assertIn("p.emaPeriod == 50", fn)
        self.assertIn("p.emaPeriod == 200", fn)
        self.assertIn("p.maxDistanceAtr > 0.0", fn)
        self.assertIn("!p.requireTrend ||", fn)
        self.assertNotIn("ctx.ema20 + tol", fn, "the touch test must use the selected EMA")

    def test_the_daily_adx_reaches_the_context(self):
        core = (INC / "EACore.mqh").read_text(encoding="utf-8")
        common = (INC / "EACommon.mqh").read_text(encoding="utf-8")
        self.assertRegex(core, r"double\s+adxD1;")
        self.assertIn("ctx.adxD1 = 0;", core)
        self.assertIn("EA_Buf(ind.hAdxD1, 0, 1, ctx.adxD1);", common)

    def test_the_portfolio_host_declares_the_input_its_init_loop_reads(self):
        gen = (REPO / "portfolio-EA" / "gen_portfolio_ea.py").read_text(encoding="utf-8")
        self.assertRegex(gen, r"input bool\s+InpSummary\s*=\s*true;")

    def test_r8b_declares_its_booster_inputs_and_gates_the_booster_on_the_month(self):
        ea = (ADD / "EA_studyarena_round8_contestant_b.mq5").read_text(encoding="utf-8")
        self.assertRegex(ea, r"input double InpAplusScore\s*=\s*95\.0;")
        self.assertRegex(ea, r"input double InpFreeRollMonthPct\s*=\s*5\.0;")
        self.assertIn("g_eaRisk.MonthStartEquity()", ea)
        self.assertIn("(freeRoll && m_setupScore >= InpAplusScore)", ea)
        self.assertIn("double MonthStartEquity() const", (INC / "EATrade.mqh").read_text(encoding="utf-8"))

    def test_r5b_and_r10fable_no_longer_use_the_undeclared_or_reserved_names(self):
        r5b = (ADD / "EA_studyarena_round5_contestant_b.mq5").read_text(encoding="utf-8")
        stripped = chk.strip_noise(r5b)
        self.assertNotRegex(stripped, r"\bbool\s+(long|short)\b")
        self.assertIn("bool goLong", stripped)
        r10 = chk.strip_noise((ADD / "EA_studyarena_round10_claude_fable_5_high_reasoning.mq5")
                              .read_text(encoding="utf-8"))
        self.assertNotRegex(r10, r"\bEA_MAX_SYM\b")


if __name__ == "__main__":
    unittest.main()
