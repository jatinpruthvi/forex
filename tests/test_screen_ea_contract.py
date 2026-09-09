"""Static source-contract tests for the TRIAD_SCREEN multi-symbol demo EA.

These mirror the approach of ``test_source_contract.py`` for the canonical EA:
no MQL5 compiler exists here, so the tests pin the *contract* (support symbols,
window enum, challenge-rule defaults, fail-closed order submission, dashboard
objects, canonical EA non-interference) so an accidental drift is caught.

The canonical frozen EA and both registries must remain byte-identical.
"""

from __future__ import annotations

import hashlib
import re
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCREEN_PATH = ROOT / "MQL5" / "Experts" / "TRIAD_SCREEN" / "TRIAD_SCREEN.mq5"
SCREEN_README = ROOT / "MQL5" / "Experts" / "TRIAD_SCREEN" / "README.md"
CANONICAL_PATH = ROOT / "MQL5" / "Experts" / "TRIAD_R_HS" / "TRIAD_R_HS.mq5"
REGISTRY_V21 = ROOT / "validation" / "triad_v2_1_registry.json"
REGISTRY_V22 = ROOT / "validation" / "triad_v2_2_ablation_registry.json"


def git_head_sha(path: Path) -> str:
    """SHA-256 of a tracked file at HEAD (verifies canonical non-interference)."""
    rel = path.relative_to(ROOT).as_posix()
    proc = subprocess.run(
        ["git", "show", f"HEAD:{rel}"], cwd=ROOT, capture_output=True, text=True
    )
    if proc.returncode != 0:
        raise AssertionError(f"cannot read {rel} at HEAD: {proc.stderr}")
    return hashlib.sha256(proc.stdout.encode()).hexdigest()


class ScreenEaContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.src = SCREEN_PATH.read_text(encoding="utf-8")

    def test_screen_ea_and_readme_exist(self) -> None:
        self.assertTrue(SCREEN_PATH.is_file())
        self.assertTrue(SCREEN_README.is_file())
        self.assertIn("#property strict", self.src)
        self.assertIn('TSC_BUILD_ID', self.src)

    def test_order_submission_defaults_closed(self) -> None:
        self.assertRegex(
            self.src,
            r"InpEnableOrderSubmission\s*=\s*false\s*;",
        )
        self.assertIn("Order submission is disabled by default", self.src)

    def test_supported_symbol_universe_is_required(self) -> None:
        # The universe chosen: 7 majors + EURJPY/GBPJPY.
        for symbol in (
            "EURUSD", "GBPUSD", "USDCHF", "AUDUSD", "USDCAD",
            "NZDUSD", "USDJPY", "EURJPY", "GBPJPY",
        ):
            self.assertIn(f'"{symbol}"', self.src)
        self.assertIn("TSC_SYMBOLS[]", self.src)
        self.assertIn("SymbolSupported", self.src)
        self.assertIn("SYMBOL_UNSUPPORTED", self.src)

    def test_both_session_windows_are_supported(self) -> None:
        self.assertIn("TSC_WINDOW_LONDON", self.src)
        self.assertIn("TSC_WINDOW_NEW_YORK", self.src)
        # London: range 0-7, entry 7-11 local. New York: entry 8:30-11.
        self.assertIn("LocalWallToUtc(year,mon,day,0,0,TSC_WINDOW_LONDON)", self.src)
        self.assertIn("LocalWallToUtc(year,mon,day,8,30,TSC_WINDOW_NEW_YORK)", self.src)

    def test_fiveers_rule_preset_is_editable_and_has_plan_defaults(self) -> None:
        for name, value in (
            ("InpPhaseInitialBalance", "2500.0"),
            ("InpPhase1TargetPercent", "10.0"),
            ("InpPhase2TargetPercent", "5.0"),
            ("InpMinQualifyingDays", "3"),
            ("InpQualifyingDayPercent", "0.5"),
            ("InpDailyLossPercent", "5.0"),
            ("InpOverallLossPercent", "10.0"),
            ("InpInactivityDays", "30"),
        ):
            self.assertRegex(self.src, rf"{name}\s*=\s*{value}\s*;")
        # Editable: the values must be `input`, not constants.
        for name in (
            "InpPhase1TargetPercent", "InpPhase2TargetPercent",
            "InpQualifyingDayPercent", "InpDailyLossPercent",
            "InpOverallLossPercent", "InpInactivityDays",
        ):
            self.assertRegex(self.src, rf"input\s+double\s+{name}\b|input\s+int\s+{name}\b")

    def test_challenge_status_machine_is_present(self) -> None:
        for marker in (
            "ChallengeStatus",
            "PASSED",
            "FAILED_OVERALL_FLOOR",
            "FAILED_DAILY_FLOOR",
            "FAILED_INACTIVITY",
            "TARGET_REACHED_DAYS_PENDING",
            "PhaseTargetBalance",
            "FirmOverallFloor",
            "EffectiveConfirmedDays",
        ):
            self.assertIn(marker, self.src)
        # Floor math: overall = initial * (1 - loss%) and phase target formulas.
        self.assertIn("InpPhaseInitialBalance*(1.0-InpOverallLossPercent/100.0)", self.src)
        self.assertIn("InpPhaseInitialBalance*(1.0+percent/100.0)", self.src)

    def test_qualifying_day_uses_published_test(self) -> None:
        self.assertIn(
            "MathMin(balance,equity)-g_prev_day_balance", self.src
        )
        self.assertIn("InpPhaseInitialBalance*InpQualifyingDayPercent/100.0", self.src)

    def test_dashboard_is_on_chart(self) -> None:
        self.assertIn('OBJ_LABEL', self.src)
        self.assertIn('ObjectCreate(0,name,OBJ_LABEL', self.src)
        self.assertIn('ChartRedraw()', self.src)
        self.assertIn('DashName', self.src)
        self.assertIn('InpDashboardRefreshSeconds', self.src)
        # Dashboard must surface the settings fingerprint.
        self.assertIn('ConfigHash', self.src)

    def test_one_combo_per_account_design(self) -> None:
        # One symbol + one window input; combo label auto-derived.
        self.assertIn("InpComboLabel", self.src)
        self.assertIn("g_combo=", self.src)
        self.assertIn("TscFileName", self.src)

    def test_canonical_ea_and_registries_untouched(self) -> None:
        # The screen EA must not be the canonical file nor modify it.
        self.assertNotEqual(SCREEN_PATH, CANONICAL_PATH)
        # Empty diff at HEAD for canonical EA and registries (they are tracked
        # and clean on branch b21eb38; any local change fails here).
        proc = subprocess.run(
            ["git", "status", "--porcelain",
             CANONICAL_PATH.relative_to(ROOT).as_posix(),
             REGISTRY_V21.relative_to(ROOT).as_posix(),
             REGISTRY_V22.relative_to(ROOT).as_posix()],
            cwd=ROOT, capture_output=True, text=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stdout.strip(), "", "canonical EA or registry modified")

    def test_strategy_port_markers_present(self) -> None:
        for marker in (
            "DetectPattern", "PrepareCandidate", "SolveTargetPrice",
            "CalculateVolume", "CashLossForVolume", "CurrentCostToR",
            "ComparableStatistics", "DailyStateAllowsEntry",
            "GlobalRiskGuards", "CanTakeCashRisk", "RefreshSession",
            "HandleRollover", "RebuildDailyClosedTrades",
        ):
            self.assertIn(marker, self.src)

    def test_zero_memory_not_used_on_string_structs(self) -> None:
        # TSC_Candidate contains string members; ZeroMemory is undefined for
        # such structs in MQL5. The reset must stay field-by-field.
        self.assertNotIn("ZeroMemory(candidate)", self.src)
        self.assertIn("candidate.rejection=\"\";", self.src)

    def test_no_obvious_undefined_identifiers(self) -> None:
        # Cheap static tripwire: any call to an identifier below is a bug
        # class (comments already stripped by scanning only code lines).
        import re
        code_lines = []
        for line in self.src.splitlines():
            code_lines.append(line.split("//", 1)[0])
        code = "\n".join(code_lines)
        # Names that are deliberately NOT defined in this file or MQL5 stdlib.
        for bad in ("TRIAD_PHASE_1", "TRIAD_PHASE_2", "g_open.entry", "g_day_closed_net"):
            self.assertNotIn(bad, code, bad)
        self.assertNotIn("fabs(", code, "use MathAbs in MQL5")

    def test_range_loads_after_range_end_not_inside(self) -> None:
        # Canonical: the completed range is read once every bar exists
        # (now>=range_end). Reading only inside [rs,re) starves the New York
        # window, whose London reference range closes before its entry window.
        code = self._code_lines()
        self.assertIn("if(!g_range_ready && now>=g_range_end)", code)
        self.assertNotIn("!g_range_ready && now>=rs && now<re", code)
        self.assertIn("InpSkipFreshMidSessionStart", code)

    def test_emergency_cleanup_bypasses_request_cap(self) -> None:
        # Canonical: protective closes/deletes are never gated by the
        # non-emergency request cap, only per-ticket throttled.
        code = self._code_lines()
        self.assertIn("if(emergency && !SafetyRequestDue(ticket,0,10))", code)
        self.assertIn("if(emergency && !SafetyRequestDue(ticket,1,10))", code)
        self.assertIn("if(!emergency && !CanSendNonEmergencyRequest())", code)

    def test_manage_exposure_applies_risk_guards(self) -> None:
        # Floor breach / phase complete must flatten exposure, not just block
        # new entries (canonical parity).
        code = self._code_lines()
        idx = code.find("void ManageExposure()")
        segment = code[idx:code.find("bool PriceMatches(")]
        self.assertIn("if(!GlobalRiskGuards(guard_reason))", segment)
        self.assertIn("CancelAllPending(guard_reason,true);", segment)
        self.assertIn("CloseAllPositions(guard_reason,true);", segment)

    def test_fill_adoption_covers_same_ticket_fill(self) -> None:
        # A filled pending order keeps its ticket; the fill must still be
        # adopted when the plan is marked pending (opened==0).
        code = self._code_lines()
        self.assertIn("bool same_plan=(g_open.ticket==pos_ticket && g_open.opened==0", code)
        self.assertIn("bool adopt=(g_open.ticket!=pos_ticket) || same_plan;", code)
        self.assertIn("WritePlanEntry(pos_ticket,planned_risk);", code)

    def test_retcode_acceptance_is_strict(self) -> None:
        code = self._code_lines()
        self.assertIn("const bool allow_placed=false,const bool allow_no_changes=true", code)
        # REQUOTE/TIMEOUT must never be treated as success.
        idx = code.find("bool TradeRetcodeAccepted")
        seg = code[idx:idx+500]
        self.assertNotIn("REQUOTE", seg)
        self.assertNotIn("TIMEOUT", seg)
        self.assertIn("(allow_placed && code==TRADE_RETCODE_PLACED)", seg)

    def test_last_sunday_utc_matches_canonical_signature(self) -> None:
        code = self._code_lines()
        self.assertIn("datetime LastSundayUtc(const int year,const int month,const int hour)", code)
        # Canonical call sites: (year, 3, 1) / (year, 10, 1) are (month, hour).
        self.assertIn("LastSundayUtc(p.year,3,1)", code)
        self.assertIn("LastSundayUtc(p.year,10,1)", code)
        self.assertNotIn("LastSundayUtc(const int year,const int month,const int day)", code)

    def test_price_normalizers_are_tick_size_anchored(self) -> None:
        code = self._code_lines()
        idx = code.find("double NormalizePriceToTick")
        seg = code[idx:idx+900]
        self.assertIn("SYMBOL_TRADE_TICK_SIZE", seg)
        self.assertIn("MathRound(price/tick_size)", seg)

    def test_config_hash_covers_behavior_inputs(self) -> None:
        code = self._code_lines()
        idx = code.find("int ConfigHash()")
        seg = code[idx:idx+3200]
        for marker in ("BoolText(InpEnableOrderSubmission)",
                       "BoolText(InpSkipFreshMidSessionStart)",
                       "InpExpectedServerUtcOffsetHours",
                       "InpMaxQuoteAgeSeconds",
                       "InpMaxDeviationPoints",
                       "InpMaxNonEmergencyRequestsDay",
                       "InpMaxTradeRequestLatencyMs",
                       "InpNewsCsvFile",
                       "BoolText(InpAllowPhaseReset)",
                       "InpDashboardConfirmedDays"):
            self.assertIn(marker, seg, marker)
        self.assertIn("ArrayResize(parts,64)", seg)

    def test_missed_rollover_uses_cross_day_check(self) -> None:
        code = self._code_lines()
        idx = code.find("bool MissedRolloverExposure")
        seg = code[idx:idx+3200]
        self.assertIn("ServerDayKey(setup)!=ServerDayKey(done)", seg)
        self.assertIn("ServerDayKey(entry_times[i])!=ServerDayKey(exit_times[i])", seg)
        self.assertNotIn("ServerDayKey(opened)", seg)

    def test_high_water_updates_only_while_flat(self) -> None:
        code = self._code_lines()
        self.assertIn("if(!HasAnyExposure())", code)
        idx = code.find("if(!HasAnyExposure())")
        seg = code[idx:idx+260]
        self.assertIn("balance>g_high_water", seg)

    def test_ledger_double_count_and_partial_close_guards(self) -> None:
        code = self._code_lines()
        self.assertIn("ArrayResize(g_ledger_position_ids,0)", code)
        self.assertIn("g_ledger_position_ids[j]==position_id", code)
        # partial-close guards in both ledger paths
        self.assertEqual(code.count("PositionSelectByTicket((ulong)position_id)"), 2)

    def test_inactivity_uses_deal_history(self) -> None:
        code = self._code_lines()
        self.assertIn("datetime LastTradingActivityTime()", code)
        idx = code.find("string ChallengeStatus()")
        seg = code[idx:idx+1400]
        self.assertIn("LastTradingActivityTime()", seg)

    def test_deinit_releases_handle_and_flattens_exposure(self) -> None:
        code = self._code_lines()
        self.assertIn("IndicatorRelease(g_atr_handle)", code)
        self.assertIn("DEINIT_EXPOSURE_CLEANUP", code)
        self.assertIn("CancelAllPending(\"deinitialization_with_exposure\",true)", code)

    def test_friday_flat_and_latency_measured(self) -> None:
        code = self._code_lines()
        self.assertIn("friday_flat_utc", code)
        self.assertIn("ORDER_REQUEST_LATENCY", code)
        self.assertIn("InpMaxTradeRequestLatencyMs", code)

    def test_expected_account_currency_is_checked(self) -> None:
        code = self._code_lines()
        self.assertIn("ACCOUNT_CURRENCY_MISMATCH", code)

    def _code_lines(self) -> str:
        lines = []
        for line in self.src.splitlines():
            lines.append(line.split("//", 1)[0])
        return "\n".join(lines)

    def test_system_cli_surface_is_separate(self) -> None:
        # No changes to existing tooling in this feature.
        for f in (
            ROOT / "tools" / "replay_export.py",
            ROOT / "tools" / "triad_validation.py",
            ROOT / "tools" / "triad_ablation.py",
        ):
            proc = subprocess.run(
                ["git", "status", "--porcelain", f.relative_to(ROOT).as_posix()],
                cwd=ROOT, capture_output=True, text=True,
            )
            self.assertEqual(proc.stdout.strip(), "", f"{f.name} modified")


if __name__ == "__main__":
    unittest.main()
