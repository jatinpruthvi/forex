from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_PATH = ROOT / "MQL5" / "Experts" / "TRIAD_R_HS" / "TRIAD_R_HS.mq5"
CANONICAL_PATH = ROOT / "THE5ERS-CHALLENGE-STRATEGY-V2.md"
README_PATH = SOURCE_PATH.with_name("README.md")
NEWS_EXAMPLE_PATH = ROOT / "MQL5" / "Files" / "triad_red_news.csv.example"


class SourceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = SOURCE_PATH.read_text(encoding="utf-8")

    def test_canonical_and_runtime_files_exist(self) -> None:
        self.assertTrue(CANONICAL_PATH.is_file())
        self.assertTrue(README_PATH.is_file())
        self.assertTrue(NEWS_EXAMPLE_PATH.is_file())
        self.assertIn("THE5ERS-CHALLENGE-STRATEGY-V2.md", self.source)
        self.assertIn('EA_BUILD_ID = "TRIAD_R_HS_2.1.5_20260904"', self.source)

    def test_news_example_has_the_declared_utc_schema(self) -> None:
        rows = NEWS_EXAMPLE_PATH.read_text(encoding="utf-8").splitlines()
        self.assertEqual(rows[0], "utc_time,currency,impact,title")
        self.assertGreaterEqual(len(rows), 5)
        coverage_rows = 0
        for row in rows[1:]:
            fields = row.split(",")
            self.assertEqual(len(fields), 4)
            self.assertRegex(fields[0], r"^\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}$")
            if fields[2] == "COVERAGE":
                coverage_rows += 1
                self.assertEqual(fields[1], "ALL")
            else:
                self.assertRegex(fields[1], r"^[A-Z]{3}$")
                self.assertIn(fields[2], {"RED", "HIGH"})
        self.assertGreaterEqual(coverage_rows, 1)

    def test_order_submission_and_all_release_gates_default_closed(self) -> None:
        self.assertRegex(self.source, r"InpEnableOrderSubmission\s*=\s*false\s*;")
        self.assertRegex(self.source, r'InpValidationReleaseId\s*=\s*"LOCKED"\s*;')
        for name in (
            "InpStatisticalGatePassed",
            "InpStressGatePassed",
            "InpOperationalGatePassed",
            "InpExternalRulesGatePassed",
            "InpAccountSpecificGatePassed",
            "InpForwardDemoGatePassed",
            "InpCompilationGatePassed",
            "InpExplicitUserApproval",
        ):
            self.assertRegex(self.source, rf"{name}\s*=\s*false\s*;", name)
        self.assertIn("VALIDATION_GATES_INCOMPLETE", self.source)
        manage = self.source.split("void ManageExposure()", 1)[1].split("datetime now=TimeTradeServer();", 1)[0]
        self.assertIn("if(!InpEnableOrderSubmission)", manage)

    def test_only_four_paired_profiles_and_max_risk_is_point_four_percent(self) -> None:
        expected = {
            "PROFILE_A_040_R150": ("0.0040", "1.50"),
            "PROFILE_B_035_R175": ("0.0035", "1.75"),
            "PROFILE_C_030_R200": ("0.0030", "2.00"),
            "PROFILE_D_025_R250": ("0.0025", "2.50"),
        }
        for profile, (risk, target) in expected.items():
            self.assertRegex(self.source, rf"case\s+{profile}:\s+return\s+{re.escape(risk)}\s*;")
            self.assertRegex(self.source, rf"case\s+{profile}:\s+return\s+{re.escape(target)}\s*;")
        risk_literals = [float(value) for value in re.findall(r"return\s+(0\.00\d+)\s*;", self.source)]
        self.assertTrue(risk_literals)
        self.assertLessEqual(max(risk_literals), 0.004)

    def test_removed_trade_behaviors_are_not_implemented(self) -> None:
        forbidden_tokens = (
            "PositionClosePartial",
            "ORDER_TYPE_CLOSE_BY",
            ".Buy(",
            ".Sell(",
            "OrderSend(",
            "OrderSendAsync(",
        )
        for token in forbidden_tokens:
            self.assertNotIn(token, self.source, token)
        self.assertNotRegex(self.source, r"risk\s*\*=\s*0\.25")

    def test_pending_orders_send_visible_stop_and_target(self) -> None:
        compact = re.sub(r"\s+", " ", self.source)
        self.assertIn(
            "g_trade.BuyLimit(candidate.volume,candidate.entry,candidate.symbol,candidate.stop,candidate.target,",
            compact,
        )
        self.assertIn(
            "g_trade.SellLimit(candidate.volume,candidate.entry,candidate.symbol,candidate.stop,candidate.target,",
            compact,
        )
        self.assertIn("pending_missing_visible_stop_or_target", self.source)
        self.assertIn("missing_visible_stop", self.source)

    def test_single_half_risk_tier_and_five_percent_shutdown(self) -> None:
        self.assertRegex(self.source, r"InpDrawdownReducePercent\s*=\s*2\.00\s*;")
        self.assertRegex(self.source, r"InpDrawdownShutdownPercent\s*=\s*5\.00\s*;")
        self.assertEqual(self.source.count("risk*=0.5;"), 1)
        self.assertIn("strategy_drawdown_shutdown", self.source)

    def test_daily_state_uses_first_net_positive_and_two_trade_lock(self) -> None:
        self.assertIn("count>=2", self.source)
        self.assertIn("count==1 && first_net>0.0", self.source)
        self.assertIn('reason="first_trade_net_positive"', self.source)

    def test_daily_and_weekly_governors_reset_by_calendar_not_halt_reset(self) -> None:
        policy = self.source.split("bool RiskGuardRequiresPersistentHalt", 1)[1].split(
            "bool GlobalRiskGuards", 1
        )[0]
        self.assertIn('reason!="internal_daily_stop"', policy)
        self.assertIn('reason!="internal_weekly_stop"', policy)
        self.assertIn("RiskGuardRequiresPersistentHalt(guard_reason)", self.source)
        self.assertIn("RiskGuardRequiresPersistentHalt(reason)", self.source)

    def test_required_persisted_state_fails_closed_when_incomplete(self) -> None:
        self.assertIn("PERSISTED_STATE_INCOMPLETE", self.source)
        self.assertIn("STATE_PERSIST_FAILED", self.source)
        self.assertIn("session_state_persistence_failure", self.source)
        self.assertIn("daily_history_unavailable", self.source)

    def test_initialization_cannot_succeed_after_session_refresh_halts(self) -> None:
        init = self.source.split("int OnInit()", 1)[1].split("void OnDeinit", 1)[0]
        refresh = init.split("RefreshSession(i,TimeTradeServer());", 1)[1]
        guard = refresh.split("return INIT_SUCCEEDED;", 1)[0]
        self.assertIn("if(g_halted)", guard)
        self.assertIn("CancelAllPending", guard)
        self.assertIn("CloseAllPositions", guard)
        self.assertIn("ReleaseLiveInstanceLock", guard)
        self.assertIn("return INIT_FAILED;", guard)

    def test_fresh_state_rejects_cancelled_order_history_without_deals(self) -> None:
        history = self.source.split("bool HasTradingHistory()", 1)[1].split(
            "bool LoadOrCreateAccountState", 1
        )[0]
        self.assertIn("HistoryOrdersTotal()>0", history)

    def test_state_load_failure_cleans_owned_exposure_only_after_lock(self) -> None:
        init = self.source.split("int OnInit()", 1)[1].split("void OnDeinit", 1)[0]
        lock_at = init.index("AcquireLiveInstanceLock")
        initialize_at = init.index("InitializeSessions")
        load_at = init.index("LoadOrCreateAccountState")
        cleanup_at = init.index('CancelAllPending("initialization_state_failure",true)')
        self.assertLess(lock_at, initialize_at)
        self.assertLess(initialize_at, load_at)
        self.assertLess(load_at, cleanup_at)
        self.assertIn('CloseAllPositions("initialization_state_failure",true)', init)
        self.assertIn("ReleaseLiveInstanceLock();", init[cleanup_at:])

    def test_trade_plan_is_persisted_and_reconciled(self) -> None:
        for token in (
            'GVWrite("ExpectedEntry",candidate.entry)',
            'GVWrite("ExpectedSL",candidate.stop)',
            'GVWrite("ExpectedTP",candidate.target)',
            'GVWrite("ExpectedVolume",candidate.volume)',
            'GVWrite("ExpectedExpiry",(double)candidate.expiry_time)',
            "LoadExpectedTradePlan",
            "position_plan_mismatch",
        ):
            self.assertIn(token, self.source)

    def test_account_wide_exposure_and_persistent_halt_are_present(self) -> None:
        self.assertIn("PositionsTotal()>0 || PendingEntryCount()>0", self.source)
        self.assertIn("multiple_or_overlapping_exposure", self.source)
        self.assertIn("DUPLICATE_LIVE_INSTANCE", self.source)
        self.assertIn("runtime_account_identity_mismatch", self.source)
        self.assertIn("WriteHaltLatch(1.0,(double)HashText(reason))", self.source)
        self.assertIn("PERSISTED_HALT_LOCK", self.source)

    def test_instance_lock_publishes_heartbeat_before_owner_claim(self) -> None:
        acquire = self.source.split("bool AcquireLiveInstanceLock()", 1)[1].split(
            "void RefreshLiveInstanceLock", 1
        )[0]
        beat_at = acquire.index("GlobalVariableSet(beat_name,(double)now)")
        claim_at = acquire.index("GlobalVariableSetOnCondition(owner_name,this_owner,owner)")
        self.assertLess(beat_at, claim_at)
        release = self.source.split("void ReleaseLiveInstanceLock()", 1)[1].split(
            "bool PersistAccountState", 1
        )[0]
        self.assertNotIn('GlobalVariableSet(g_account_lock_prefix+"Beat",0.0)', release)

    def test_actual_symbol_cash_sizing_and_round_down_are_present(self) -> None:
        self.assertIn("OrderCalcProfit", self.source)
        self.assertIn("SYMBOL_VOLUME_STEP", self.source)
        self.assertIn("SYMBOL_VOLUME_LIMIT", self.source)
        self.assertIn("MathFloor((raw-minimum+1e-12)/step)", self.source)
        self.assertIn("minimum+MathMin(units,maximum_units)*step", self.source)
        self.assertNotIn("$10/pip", self.source)

    def test_atr_regime_uses_session_open_not_signal_time(self) -> None:
        self.assertIn("ComputeAtrBefore(s.symbol,es,av)", self.source)
        self.assertIn(
            "ComputeAtrBefore(candidate.symbol,g_sessions[session_index].entry_start,atr)",
            self.source,
        )
        self.assertNotIn("ComputeAtrBefore(s.symbol,comparable_time,av)", self.source)

    def test_atr_uses_canonical_indicator_buffer_and_closed_bar(self) -> None:
        self.assertIn("iATR(g_sessions[i].symbol,PERIOD_M15,14)", self.source)
        self.assertIn("iBarShift(symbol,PERIOD_M15,before_time-1,false)", self.source)
        self.assertIn("CopyBuffer(handle,0,shift,1,values)", self.source)
        self.assertIn("bar_open+PeriodSeconds(PERIOD_M15)>before_time", self.source)
        self.assertIn("IndicatorRelease(g_atr_handles[i])", self.source)
        self.assertNotIn("atr=total/14.0", self.source)

    def test_news_coverage_cannot_silently_expire_at_runtime(self) -> None:
        self.assertIn("NewsCalendarCurrent", self.source)
        self.assertIn("NEWS_RUNTIME_COVERAGE_STALE", self.source)
        self.assertIn('impact=="COVERAGE"', self.source)
        self.assertIn('currency!="ALL"', self.source)
        self.assertIn("g_news_coverage_end_utc=declared_coverage_end", self.source)
        self.assertNotIn("g_news_coverage_end_utc=maximum_time", self.source)
        self.assertIn(
            "g_news_coverage_end_utc>=now_utc+InpRequiredNewsCoverageHours*3600",
            self.source,
        )
        position_controls = self.source.split("// Position controls.", 1)[1]
        self.assertIn("RecentRelevantNews(ccy1,ccy2,now,InpNewsBlockMinutes)", position_controls)
        self.assertNotIn(
            "IsRelevantNewsWindow(ccy1,ccy2,now,InpNewsBlockMinutes)",
            position_controls,
        )

    def test_first_sweep_is_reconstructed_and_repeats_cannot_reset_event(self) -> None:
        for token in (
            "GetCompletedSessionBars",
            "ambiguous_two_sided_sweep",
            "sweep_too_deep",
            "no_reclaim_within_three",
            "weak_displacement",
            "stale_signal_event",
            "One detected event consumes this symbol/session",
        ):
            self.assertIn(token, self.source)
        self.assertIn("g_sessions[session_index].entry_start>g_sessions[session_index].range_end", self.source)

    def test_range_and_candle_sequence_semantics_are_locked(self) -> None:
        read_range = self.source.split("bool ReadRange", 1)[1].split(
            "bool ComputeAtrBefore", 1
        )[0]
        compact_range = re.sub(r"\s+", "", read_range)
        # Reference ranges are half-open: [start_time, end_time).  The entry
        # boundary bar must not leak into the range it is attempting to sweep.
        self.assertIn(
            "CopyRates(symbol,PERIOD_M5,start_time,end_time-1,rates)",
            compact_range,
        )
        self.assertIn("expected=(int)((end_time-start_time)/period)", compact_range)

        pattern = self.source.split("bool DetectPattern", 1)[1].split(
            "bool BrokerDistancesValid", 1
        )[0]
        compact_pattern = re.sub(r"\s+", "", pattern)
        # The sweep candle is eligible to reclaim, and displacement is exactly
        # the immediately following completed M5 candle.
        self.assertIn("for(inti=sweep_index;i<=last_reclaim_bar;i++)", compact_pattern)
        self.assertIn("MqlRatesdisplacement=bars[reclaim_index+1]", compact_pattern)
        # A long displacement must be bullish and a short displacement bearish;
        # crossing the reclaim midpoint alone is insufficient.
        self.assertIn("displacement.close>displacement.open", compact_pattern)
        self.assertIn("displacement.close<displacement.open", compact_pattern)

    def test_state_commit_signature_detects_partial_global_updates(self) -> None:
        self.assertIn("AccountStateSignature", self.source)
        self.assertIn('GVWrite("StateSig",AccountStateSignature())', self.source)
        self.assertIn('GVRead("StateSig",state_signature)', self.source)
        self.assertIn("PERSISTED_STATE_SIGNATURE_MISMATCH", self.source)

    def test_halt_latch_and_reason_have_a_dedicated_commit_signature(self) -> None:
        signature = self.source.split("int HaltLatchSignature", 1)[1].split(
            "bool HaltLatchValuesValid", 1
        )[0]
        for token in (
            '"HALT_LATCH_V1|"',
            "g_config_hash",
            "g_runtime_identity_hash",
            "halt_value>0.5 ? 1 : 0",
            "(int)halt_reason_hash",
        ):
            self.assertIn(token, signature)

        writer = self.source.split("bool WriteHaltLatch", 1)[1].split(
            "bool ReadHaltLatch", 1
        )[0]
        halt_at = writer.index('GVWrite("Halt",halt_value)')
        reason_at = writer.index('GVWrite("HaltReason",halt_reason_hash)')
        signature_at = writer.index('GVWrite("HaltSig",HaltLatchSignature')
        self.assertLess(halt_at, reason_at)
        self.assertLess(reason_at, signature_at)

        reader = self.source.split("bool ReadHaltLatch", 1)[1].split(
            "bool AcquireLiveInstanceLock", 1
        )[0]
        self.assertIn('GVRead("HaltSig",stored_signature)', reader)
        self.assertIn(
            "stored_signature==(double)HaltLatchSignature(halt_value,halt_reason_hash)",
            reader,
        )

        halt = self.source.split("void Halt(const string reason)", 1)[1].split(
            "int HashText", 1
        )[0]
        self.assertIn("WriteHaltLatch(1.0,(double)HashText(reason))", halt)
        self.assertGreaterEqual(self.source.count("ReadHaltLatch("), 3)
        self.assertIn("WriteHaltLatch(0.0,0.0)", self.source)
        self.assertIn("PERSISTED_HALT_SIGNATURE_MISMATCH", self.source)

    def test_persisted_identity_is_frozen_across_account_context_changes(self) -> None:
        self.assertIn("g_runtime_identity_hash=RuntimeIdentityHash()", self.source)
        self.assertIn('GVWrite("Identity",g_runtime_identity_hash)', self.source)
        self.assertIn("RuntimeIdentityHash()==g_runtime_identity_hash", self.source)
        self.assertIn("bool AuthorizedAccountContext()", self.source)
        self.assertIn("deinitialization_account_context_changed", self.source)
        self.assertIn("authorized_context && owns_live_lock && HasAnyExposure()", self.source)
        self.assertGreaterEqual(self.source.count("runtime_account_context_changed"), 4)
        timer = self.source.split("void OnTimer()", 1)[1].split(
            "void OnTradeTransaction", 1
        )[0]
        identity_at = timer.index("RuntimeAccountIdentityValid")
        journal_at = timer.index("RuntimeJournalValid")
        rollover_at = timer.index("ProcessRollover")
        self.assertLess(identity_at, journal_at)
        self.assertLess(journal_at, rollover_at)
        self.assertIn("!g_instance_lock_held", timer)
        self.assertIn("PERSISTED_RUNTIME_LATCH", self.source)
        self.assertGreaterEqual(self.source.count("STALE_INSTANCE_FENCED"), 3)
        deinit = self.source.split("void OnDeinit", 1)[1].split("void OnTick", 1)[0]
        self.assertIn("owns_live_lock", deinit)
        self.assertIn("DEINITIALIZATION_STATE_WRITE_SKIPPED", deinit)
        self.assertGreaterEqual(self.source.count("!OwnsLiveInstanceLock()"), 4)
        self.assertIn(
            "if(!InpEnableOrderSubmission || !AuthorizedAccountContext() || !OwnsLiveInstanceLock())",
            self.source,
        )

    def test_external_account_incident_cannot_migrate_risk_baselines(self) -> None:
        rollover = self.source.split("void ProcessRollover()", 1)[1].split(
            "void UpdateHighWater()", 1
        )[0]
        high_water = self.source.split("void UpdateHighWater()", 1)[1].split(
            "bool NearlyEqual", 1
        )[0]
        self.assertIn("g_external_cashflow_detected || g_account_history_fault", rollover)
        self.assertIn("g_halted || g_external_cashflow_detected", high_water)
        self.assertIn('GVWrite("Rebase",g_rebaseline_required ? 1.0 : 0.0)', self.source)
        self.assertIn("PERSISTED_STATE_MIGRATION_LOCK", self.source)
        self.assertIn('RequireStateMigration("external_cashflow_requires_rebaseline_release")', self.source)
        self.assertIn("HistoryOrdersTotal", self.source)
        self.assertIn("UNAUTHORIZED_ORDER_HISTORY", self.source)
        self.assertIn('RequireStateMigration("unauthorized_order_history")', self.source)

    def test_offline_exposure_crossing_rollover_is_reconstructed(self) -> None:
        reconstruction = self.source.split("bool MissedRolloverExposure", 1)[1].split(
            "void ProcessRollover()", 1
        )[0]
        self.assertIn("HistoryOrdersTotal", reconstruction)
        self.assertIn("ORDER_TIME_SETUP", reconstruction)
        self.assertIn("ORDER_TIME_DONE", reconstruction)
        self.assertIn("ServerDayKey(entry_times[i])!=ServerDayKey(exit_times[i])", reconstruction)
        self.assertIn('RequireStateMigration("missed_rollover_exposure")', self.source)
        self.assertIn('RequireStateMigration("unexpected_rollover_exposure")', self.source)
        self.assertIn('Halt("missed_rollover_exposure")', self.source)
        self.assertIn('Halt("rollover_history_unavailable")', self.source)

    def test_quote_checks_use_the_same_tick_snapshot(self) -> None:
        self.assertIn("bool TickIsFresh(const MqlTick &tick)", self.source)
        self.assertIn("SymbolInfoTick(candidate.symbol,recheck_tick) || !TickIsFresh(recheck_tick)", self.source)
        self.assertNotIn("IsQuoteFresh", self.source)

    def test_breakeven_has_only_one_persisted_retry(self) -> None:
        self.assertIn('GVWrite("BreakEvenAttempts",0.0)', self.source)
        self.assertIn("if(attempts>=2)", self.source)
        self.assertIn("BREAKEVEN_RETRY_ARMED", self.source)
        self.assertIn("TransientTradeRetcode", self.source)

    def test_failed_submission_latches_and_reconciles_before_plan_clear(self) -> None:
        submit = self.source.split("bool SubmitCandidate", 1)[1]
        failure_block = submit.split("if(!ok)", 1)[1].split("if(request_latency>", 1)[0]
        self.assertIn('Halt("order_submission_failed")', failure_block)
        self.assertIn("CancelAllPending", failure_block)
        self.assertIn("CloseAllPositions", failure_block)
        self.assertIn("if(!HasAnyExposure())", failure_block)
        success_tail = submit.split('LogEvent("INFO","ORDER_SUBMITTED"', 1)[1]
        self.assertIn("ManageExposure();", success_tail)
        self.assertIn("return !g_halted;", success_tail)

    def test_each_enabled_combination_needs_its_own_release_gate(self) -> None:
        for name in (
            "InpEURUSDLondonGatePassed",
            "InpGBPUSDLondonGatePassed",
            "InpUSDJPYNewYorkGatePassed",
        ):
            self.assertRegex(self.source, rf"{name}\s*=\s*false\s*;")
        self.assertIn("COMBINATION_GATE_INCOMPLETE", self.source)

    def test_collision_ranking_uses_frozen_priority_before_cost_and_time(self) -> None:
        for name in (
            "InpEURUSDLondonPriority",
            "InpGBPUSDLondonPriority",
            "InpUSDJPYNewYorkPriority",
        ):
            self.assertIn(f"IntegerToString({name})", self.source)
        scan = self.source.split("void ScanForSignals()", 1)[1].split(
            "// MQL5 event handlers", 1
        )[0]
        self.assertIn("RefreshCandidateQuoteState(candidates[index])", scan)
        self.assertIn("COLLISION_REVALIDATION_REJECTED", scan)
        priority_at = scan.index("g_sessions[index].priority<g_sessions[winner].priority")
        cost_at = scan.index("candidates[index].cost_to_r<candidates[winner].cost_to_r")
        time_at = scan.index("candidates[index].signal_bar_time<candidates[winner].signal_bar_time")
        self.assertLess(priority_at, cost_at)
        self.assertLess(cost_at, time_at)
        self.assertIn("INPUT_COLLISION_PRIORITY", self.source)

    def test_server_offset_is_checked_in_seconds_not_rounded_hours(self) -> None:
        self.assertIn("SERVER_OFFSET_TOLERANCE_SECONDS = 5", self.source)
        self.assertIn("error_seconds>SERVER_OFFSET_TOLERANCE_SECONDS", self.source)
        self.assertIn("offset_error<=SERVER_OFFSET_TOLERANCE_SECONDS", self.source)
        self.assertNotIn("MathRound((double)(server-gmt)/3600.0)", self.source)

    def test_operational_guards_are_present(self) -> None:
        required = (
            "InpNewsBlockMinutes            = 30",
            "InpNewsFlatMinutes             = 15",
            "InpRolloverFlatMinutes         = 15",
            "InpMaxNonEmergencyRequestsDay  = 20",
            "SERVER_OFFSET_MISMATCH",
            "server_day_regression",
            "SAFETY_TIME_LEAD_SECONDS = 10",
            "InpRolloverFlatMinutes*60+SAFETY_TIME_LEAD_SECONDS",
            "broker_stop_or_freeze_level",
            "theoretical_1R_without_fill",
            "friday_flat",
            "INACTIVITY_ALERT",
            "DIRECTION_CONCENTRATION_REVIEW",
            "ONE_R_CONFIRMED",
            "OneRConfirmed",
            "HasConfirmedOneRClose",
            "ActualTradeNet",
            "pending_plan_mismatch",
            "visible_exit_plan_mismatch",
            "ORDER_REQUEST_LATENCY_BREACH",
            "emergency_order_delete_failed_",
            "emergency_position_close_failed_",
            "ORDER_ALREADY_ABSENT_AFTER_DELETE",
            "POSITION_ALREADY_ABSENT_AFTER_CLOSE",
            "timer_initialization_failure",
            "INSTANCE_LOCK_LOST_DURING_INITIALIZATION",
            "deinitialization_with_exposure",
            "audit_log_failure_during_deinitialization",
            "AUDIT_LOG_OPEN_FAILED",
            "audit_log_failure",
            "EXTERNAL_CASHFLOW_DETECTED",
            "UNAUTHORIZED_TRADING_HISTORY",
            "PROFITABLE_DAY_NOT_ESTIMATED",
            "payout_request_lock",
            "phase_transition_lock",
            "scale_transition_lock",
        )
        for token in required:
            self.assertIn(token, self.source, token)

    def test_worst_case_terminal_global_names_fit_platform_limit(self) -> None:
        login = "9" * 19
        config_hash = "9" * 10
        ticket = "9" * 20
        live_prefix = f"TR.{login}.3.L."
        tester_prefix = f"TR.{login}.3.T.{config_hash}."
        account_lock = f"TRL.{login}.{config_hash}.Owner"
        for name in (
            live_prefix + "PredictedNetTarget",
            live_prefix + "HaltSig",
            live_prefix + "XB." + ticket,
            tester_prefix + "PredictedNetTarget",
            tester_prefix + "HaltSig",
            tester_prefix + "XB." + ticket,
            account_lock,
        ):
            self.assertLessEqual(len(name), 63, name)

    def test_delimiters_are_balanced_outside_strings_and_comments(self) -> None:
        # Lightweight lexical check, not an MQL compiler.
        text = re.sub(r"//.*", "", self.source)
        text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
        text = re.sub(r'"(?:\\.|[^"\\])*"', '""', text)
        pairs = {')': '(', ']': '[', '}': '{'}
        stack: list[str] = []
        for char in text:
            if char in "([{":
                stack.append(char)
            elif char in pairs:
                self.assertTrue(stack, f"unmatched {char}")
                self.assertEqual(stack.pop(), pairs[char])
        self.assertFalse(stack, f"unclosed delimiters: {stack}")


if __name__ == "__main__":
    unittest.main()
