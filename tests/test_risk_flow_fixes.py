"""Behavioural spec for the risk / order-flow fixes of top-25 sweep #2.

Python mirrors, each pinned against the delivered defect:

  governor flatten   fire-and-forget close -> retried until flat; freeze message throttled
  E1 placement       the sweep was consumed BEFORE the order was sent
  staged exits       partial / break-even flag set whether or not the broker accepted them
  lot arithmetic     0.03 / 0.01 floors to 2; a 0.02-lot position "25%" partial became 50%
  HWM                a stale peak locked two EAs out for good; keys shared by every account
  3110 cashflow      every trading day's P/L tripped the "external cashflow" halt next morning
  R12A scoreboard    sweep + rejection + displacement credited 2 points, capping the board at 7/8
"""
from __future__ import annotations

import math
import re
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
ADD = REPO / "MQL5_Master" / "Experts" / "additionalEAs"
INC = REPO / "MQL5_Master" / "Include"


def code_only(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


# =============================================================================
# governor: flatten until flat
# =============================================================================
class FlakyBroker:
    """Rejects the first `fail_first` close/delete attempts per item, then accepts."""

    def __init__(self, items, fail_first):
        self.open = set(items)
        self.fail_first = fail_first
        self.attempts = {i: 0 for i in items}

    def close(self, item):
        self.attempts[item] += 1
        if self.attempts[item] <= self.fail_first:
            return False
        self.open.discard(item)
        return True


def legacy_close_all(broker):
    for i in list(broker.open):
        broker.close(i)                              # return code ignored


def close_all(broker):
    for i in list(broker.open):
        broker.close(i)
    return len(broker.open)                          # what is STILL open


class GovernorFlattenTests(unittest.TestCase):
    def test_a_rejected_close_used_to_stay_open_for_the_whole_freeze(self):
        b = FlakyBroker({"EURUSD#1", "GBPUSD#2", "pending#3"}, fail_first=1)
        legacy_close_all(b)                          # the breaker trips: one shot
        self.assertEqual(len(b.open), 3)             # nothing closed, and nothing ever tries again
        for _ in range(48 * 3600):                   # the freeze: OnTimer returns before maintenance
            pass
        self.assertEqual(len(b.open), 3)

    def test_the_fixed_flow_retries_until_the_book_is_flat(self):
        b = FlakyBroker({"EURUSD#1", "GBPUSD#2", "pending#3"}, fail_first=3)
        clock, last_attempt, attempts, flat_at = 0, -999, 0, None
        left = close_all(b)                          # the trip itself
        for second in range(1, 120):                 # 1-second timer ticks while frozen
            clock = second
            if len(b.open) == 0:
                flat_at = second if flat_at is None else flat_at
                continue                             # silent once flat
            if clock - last_attempt < 5:             # FlattenResidual's rate limit
                continue
            last_attempt = clock
            attempts += 1
            left = close_all(b)
        self.assertEqual(left, 0)
        self.assertEqual(len(b.open), 0)
        self.assertLess(attempts, 20)                # retried, not hammered

    def test_the_freeze_message_is_throttled(self):
        printed, last = 0, -10 ** 9
        for second in range(48 * 3600):              # 48 h of 1-second timer ticks
            if second - last >= 900:
                printed += 1
                last = second
        self.assertEqual(printed, 192)               # was 172 800 lines

    def test_source(self):
        rg = (INC / "RiskGovernor.mqh").read_text(encoding="utf-8")
        self.assertIn("int            CloseAllPositions();", rg)
        self.assertIn("void           FlattenResidual();", rg)
        body = rg[rg.index("int CRiskGovernor::CloseAllPositions()"):rg.index("double CRiskGovernor::GetTotalPortfolioHeat()")]
        self.assertIn("m_trade.SetTypeFillingBySymbol(sym);", body)
        self.assertIn("return CountExposure();", body)
        self.assertGreaterEqual(rg.count("FlattenResidual();"), 2)
        self.assertIn("TimeCurrent() - m_lastFreezeLog >= 900", rg)
        triad = (REPO / "MQL5_Master" / "Experts" / "Master_Triad_V1.mq5").read_text(encoding="utf-8")
        self.assertIn("RiskGovernor.FlattenResidual();", triad)
        self.assertNotIn("RiskGovernor.CloseAllPositions();", code_only(triad))


# =============================================================================
# E1: the sweep is consumed only when the bracket was placed
# =============================================================================
class Placement:
    def __init__(self, fixed):
        self.fixed = fixed
        self.traded = 0
        self.fail_count = 0
        self.fail_sweep = 0

    def register(self, sweep_time, placed):
        if not self.fixed:                            # delivered: consumed before the call, result ignored
            self.traded = sweep_time
            return
        if placed:
            self.traded, self.fail_count, self.fail_sweep = sweep_time, 0, 0
            return
        if self.fail_sweep == sweep_time:
            self.fail_count += 1
        else:
            self.fail_sweep, self.fail_count = sweep_time, 1
        if self.fail_count >= 3:
            self.traded, self.fail_count, self.fail_sweep = sweep_time, 0, 0

    def available(self, sweep_time):
        return sweep_time > self.traded


class E1PlacementTests(unittest.TestCase):
    def test_a_transient_rejection_burned_the_setup_for_good(self):
        legacy = Placement(fixed=False)
        legacy.register(1000, placed=False)           # spread blip at the moment of placement
        self.assertFalse(legacy.available(1000))      # the sweep is gone - and persisted in a GV
        fixed = Placement(fixed=True)
        fixed.register(1000, placed=False)
        self.assertTrue(fixed.available(1000))        # still tradable on the next M15 candle

    def test_success_consumes_the_sweep(self):
        p = Placement(fixed=True)
        p.register(1000, placed=True)
        self.assertFalse(p.available(1000))
        self.assertTrue(p.available(2000))

    def test_three_failures_abandon_the_setup(self):
        p = Placement(fixed=True)
        for _ in range(2):
            p.register(1000, placed=False)
            self.assertTrue(p.available(1000))
        p.register(1000, placed=False)
        self.assertFalse(p.available(1000))

    def test_failures_of_different_sweeps_do_not_accumulate(self):
        p = Placement(fixed=True)
        p.register(1000, placed=False)
        p.register(2000, placed=False)
        p.register(3000, placed=False)
        self.assertTrue(p.available(3000))

    def test_source(self):
        e1 = (INC / "E1_SMC_Core.mqh").read_text(encoding="utf-8")
        self.assertIn("void CE1SMCCore::RegisterPlacement(bool placed)", e1)
        self.assertEqual(e1.count("RegisterPlacement(placed);"), 2)
        for side in ("ORDER_TYPE_BUY_LIMIT", "ORDER_TYPE_SELL_LIMIT"):
            self.assertIn(f"bool placed = m_execManager.SendDualBracketLimit(symbol, {side},", e1)
        tick = e1[e1.index("void CE1SMCCore::OnTickEngine("):e1.index("int CE1SMCCore::GetTrendBias(")]
        self.assertNotIn("m_lastTradedSweepTime = m_setupSweepTime;", tick)     # not before the call
        grade = tick[tick.index("if(grade < 5)"):]
        self.assertLess(grade.index("m_lastAttemptTime = currentCandleTime;"), grade.index("return;"))


# =============================================================================
# ExecutionManager: staged exits + lot arithmetic
# =============================================================================
class Position:
    def __init__(self, volume):
        self.volume = volume
        self.sl = 99.0
        self.entry = 100.0


def floor_to_step(x, step):
    return math.floor(x / step + 1e-9) * step


def normalise2(x):
    return round(x + 1e-12, 2)


def legacy_staged(pos, flags, partial_ok, modify_ok, min_lot=0.01, step=0.01):
    """The delivered flow: ONE flag, set no matter what the broker said."""
    if flags.get("done"):
        return
    pv = floor_to_step(normalise2(pos.volume * 0.25), step)
    if pv >= min_lot and partial_ok():
        pos.volume = round(pos.volume - pv, 2)
    modify_ok(pos)
    flags["done"] = True


def fixed_staged(pos, flags, partial_ok, modify_ok, min_lot=0.01, step=0.01):
    partial_done = flags.get("partial", False)
    if not partial_done:
        pv = floor_to_step(pos.volume * 0.25, step)
        if pv >= min_lot and pv < pos.volume:
            if partial_ok():
                pos.volume = round(pos.volume - pv, 2)
                partial_done = True
        else:
            partial_done = True                       # too small to split
        if partial_done:
            flags["partial"] = True
    if pos.sl < pos.entry + 0.2:                      # break-even + 0.2R not yet applied
        modify_ok(pos)


class StagedExitTests(unittest.TestCase):
    def test_one_requote_used_to_cost_the_trade_its_partial_and_its_break_even(self):
        pos, flags = Position(0.40), {}
        legacy_staged(pos, flags, partial_ok=lambda: False, modify_ok=lambda p: None)   # broker says no
        legacy_staged(pos, flags, partial_ok=lambda: True, modify_ok=lambda p: setattr(p, "sl", 100.2))
        self.assertEqual(pos.volume, 0.40)            # the partial was never taken
        self.assertEqual(pos.sl, 99.0)                # nor was the stop moved

    def test_the_fixed_flow_retries_each_step_until_it_works(self):
        pos, flags = Position(0.40), {}
        results = iter([False, True])                 # partial: rejected once, then accepted
        sl_results = iter([False, False, True])       # stop move: rejected twice, then accepted

        def modify(p):
            if next(sl_results):
                p.sl = 100.2

        for _ in range(4):
            fixed_staged(pos, flags, partial_ok=lambda: next(results, True), modify_ok=modify)
        self.assertEqual(pos.volume, 0.30)            # exactly ONE 25% partial (0.10 of 0.40)
        self.assertEqual(pos.sl, 100.2)
        self.assertTrue(flags["partial"])

    def test_no_second_partial_while_the_stop_move_is_being_retried(self):
        pos, flags = Position(0.40), {}
        for _ in range(5):                            # partial succeeds, stop move keeps failing
            fixed_staged(pos, flags, partial_ok=lambda: True, modify_ok=lambda p: None)
        self.assertEqual(pos.volume, 0.30)

    def test_half_lot_floor_is_not_off_by_a_step(self):
        # IEEE doubles: 0.29 / 0.01 = 28.999999999999996, so a bare floor() dropped a whole step
        self.assertEqual(math.floor((0.58 / 2.0) / 0.01), 28)         # delivered: a 0.58-lot order -> 2 x 0.28
        self.assertAlmostEqual(floor_to_step(0.58 / 2.0, 0.01), 0.29)  # fixed: 2 x 0.29
        wrong_before = wrong_after = 0
        for k in range(2, 801):                                        # every lot 0.02 .. 8.00
            total = round(k * 0.01, 2)
            want = (round(total * 100) // 2)                           # half, in whole 0.01 steps
            wrong_before += math.floor((total / 2.0) / 0.01) != want
            wrong_after += round(floor_to_step(total / 2.0, 0.01) / 0.01) != want
        self.assertGreater(wrong_before, 0)                            # the defect is real (14 sizes)
        self.assertEqual(wrong_after, 0)                               # and the fix removes all of them

    def test_a_small_position_is_not_split_in_half(self):
        self.assertEqual(normalise2(0.02 * 0.25), 0.01)               # delivered: 25% of 0.02 -> 0.01 (= 50%)
        self.assertEqual(floor_to_step(0.02 * 0.25, 0.01), 0.0)       # fixed: too small to split
        pos, flags = Position(0.02), {}
        fixed_staged(pos, flags, partial_ok=lambda: True, modify_ok=lambda p: None)
        self.assertEqual(pos.volume, 0.02)
        self.assertTrue(flags["partial"])

    def test_source(self):
        em = (INC / "ExecutionManager.mqh").read_text(encoding="utf-8")
        body = em[em.index("void CExecutionManager::ManageStagedExits()"):em.index("//| Manage Dead-Money Exit")]
        code = code_only(body)
        self.assertIn("bool partialDone = GlobalVariableCheck(gvName);", code)
        self.assertIn("if(m_trade.PositionClosePartial(ticket, partialVol)) partialDone = true;", code)
        self.assertIn("if(partialDone) GlobalVariableSet(gvName, 1.0);", code)
        self.assertIn("if(!m_trade.PositionModify(ticket, newSL, tp))", code)
        self.assertNotIn("if(GlobalVariableCheck(gvName)) continue;", code)
        self.assertIn("MathFloor(currentVolume * 0.25 / lotStep + 1e-9) * lotStep", code)
        self.assertIn("MathFloor((totalLotSize / 2.0) / step + 1e-9) * step", code_only(em))
        self.assertNotIn("ManageH1Bailout", em)
        self.assertIn("void CExecutionManager::OnTickMaintenance(bool isNewsBlocked)", em)


# =============================================================================
# strategy-level equity high-water marks
# =============================================================================
def month_key(year, mon):
    return f"{year:04d}{mon:02d}"


class HwmTests(unittest.TestCase):
    SHUTDOWN_PCT = 6.0

    def run_months(self, monthly):
        gv = {}
        trades = []
        equity = 100_000.0
        for (y, m), eq in (((2026, 7), 100_000.0), ((2026, 7), 93_000.0),      # a -7% drawdown in July
                           ((2026, 8), 93_000.0), ((2026, 8), 93_500.0)):      # August: nothing changed
            key = "R11E_HWM" + ("_" + month_key(y, m) if monthly else "")
            hwm = gv.get(key, 0.0)
            if hwm <= 0.0 or eq > hwm:
                gv[key] = max(eq, hwm)
                dd = 0.0
            else:
                dd = 100.0 * (hwm - eq) / hwm
            trades.append(dd < self.SHUTDOWN_PCT)       # LotsMultiplier > 0 ?
        return trades

    def test_a_stale_peak_locked_the_ea_out_for_good(self):
        legacy = self.run_months(monthly=False)
        self.assertEqual(legacy, [True, False, False, False])      # shut down in July... and August, September...

    def test_the_monthly_key_makes_shutdown_for_the_month_literally_true(self):
        fixed = self.run_months(monthly=True)
        self.assertEqual(fixed, [True, False, True, True])         # trading resumes in the new month

    def test_the_key_is_scoped_by_account_and_magic(self):
        def key(login, magic, tag, monthly=False):
            return f"EA_{login}_{magic}_{tag}_HWM" + (("_" + month_key(2026, 10)) if monthly else "")
        self.assertNotEqual(key(111, 2038, "R11D"), key(222, 2038, "R11D"))   # another account does not inherit it
        self.assertNotEqual(key(111, 2038, "R11D"), key(111, 2039, "R11D"))
        self.assertLessEqual(len(key(1234567890, 2039, "R10KIMI", True)), 63)  # MQL5 GV names are capped at 63

    def test_source(self):
        sig = (INC / "EASignals.mqh").read_text(encoding="utf-8")
        self.assertIn("string EA_HwmKey(const string tag, const bool monthly)", sig)
        self.assertIn("ACCOUNT_LOGIN", sig[sig.index("string EA_HwmKey("):sig.index("//| Clock helpers for bars")])
        want = {"EA_studyarena_round10_kimi_k3_high_reasoning": ('"R10KIMI"', "false"),
                "EA_studyarena_round11_contestant_c": ('"R11C"', "false"),
                "EA_studyarena_round11_contestant_d": ('"R11D"', "false"),
                "EA_studyarena_round11_contestant_e": ('"R11E"', "true"),
                "EA_studyarena_round12_contestant_b": ('"R12B"', "true")}
        for ea, (tag, monthly) in want.items():
            text = (ADD / f"{ea}.mq5").read_text(encoding="utf-8")
            self.assertIn(f"EA_HwmKey({tag}, {monthly})", text, ea)
            self.assertNotRegex(code_only(text), r'GlobalVariable(?:Get|Set)\("R\w+_HWM"')


# =============================================================================
# 3110: external cashflow
# =============================================================================
def legacy_cashflow_days(days):
    """days: list of (realised_pl_that_day, trades_that_day).  Returns the days the EA halted."""
    balance, ref, halted = 10_000.0, -1.0, []
    for n, (pl, trades) in enumerate(days, 1):
        # first check of the day: flat, no trades yet today
        if ref < 0:
            ref = balance
        if abs(balance - ref) > 1.0:
            halted.append(n)
        ref = balance
        if n in halted:
            continue                                  # halted: no trading today
        balance += pl                                 # the day's closed trades
    return halted


def fixed_cashflow_halts(deals):
    """deals: list of deal types seen in the history window."""
    return any(d in ("BALANCE", "CREDIT", "CHARGE", "CORRECTION") for d in deals)


class CashflowTests(unittest.TestCase):
    def test_every_trading_day_used_to_cost_the_next_day(self):
        days = [(+50.0, 1), (0.0, 0), (-30.0, 1), (0.0, 0), (+20.0, 1), (0.0, 0)]
        halted = legacy_cashflow_days(days)
        self.assertEqual(halted, [2, 4, 6])           # the EA traded every OTHER day

    def test_ordinary_trades_are_not_cashflow(self):
        self.assertFalse(fixed_cashflow_halts(["BUY", "SELL", "COMMISSION", "SWAP"]))

    def test_a_deposit_or_withdrawal_is_detected(self):
        for kind in ("BALANCE", "CREDIT", "CHARGE", "CORRECTION"):
            self.assertTrue(fixed_cashflow_halts(["BUY", kind]))

    def test_source(self):
        ea = code_only((ADD / "EA_TRIAD_R_HS_CODE_REVIEW.mq5").read_text(encoding="utf-8"))
        self.assertNotIn("balanceRef", ea)
        for needle in ("DEAL_TYPE_BALANCE", "DEAL_TYPE_CREDIT", "DEAL_TYPE_CHARGE", "DEAL_TYPE_CORRECTION",
                       "cashflowScanFrom = nowSrv + 1;"):
            self.assertIn(needle, ea)


# =============================================================================
# R12A scoreboard
# =============================================================================
def r12a_score(range_ok, bias, spread, participation, clean, fixed):
    s = int(range_ok) + int(bias) + int(spread)
    s += 3 if fixed else 2                            # sweep + rejection + displacement (hard-gated)
    s += int(participation) + int(clean)
    return s


class ScoreboardTests(unittest.TestCase):
    def test_the_delivered_board_topped_out_at_seven(self):
        self.assertEqual(r12a_score(1, 1, 1, 1, 1, fixed=False), 7)
        self.assertEqual(r12a_score(1, 1, 1, 1, 1, fixed=True), 8)

    def test_a_threshold_of_seven_allows_exactly_one_miss_when_fixed(self):
        threshold = 7
        self.assertTrue(r12a_score(1, 1, 1, 1, 0, fixed=True) >= threshold)       # one miss still fires
        self.assertFalse(r12a_score(1, 1, 1, 0, 0, fixed=True) >= threshold)      # two misses do not
        # delivered: ONE miss already blocked the trade ("score >= 7" demanded a perfect run)
        self.assertFalse(r12a_score(1, 1, 1, 1, 0, fixed=False) >= threshold)

    def test_source(self):
        ea = code_only((ADD / "EA_studyarena_round12_contestant_a.mq5").read_text(encoding="utf-8"))
        self.assertIn("score += 3;", ea)
        self.assertNotIn("score += 2;", ea)
        self.assertIn("SigSweepVolumeRatio(ctx, plan.sweepBarsAgo)", ea)
        fable = code_only((ADD / "EA_studyarena_round12_claude_fable_5_high_reasoning.mq5").read_text(encoding="utf-8"))
        self.assertIn("SigSweepVolumeRatio(ctx, plan.sweepBarsAgo)", fable)
        f = code_only((ADD / "EA_studyarena_round12_contestant_f.mq5").read_text(encoding="utf-8"))
        self.assertIn("SigSweepVolumeRatio(ctx, plan.sweepBarsAgo) >= 1.2", f)


# =============================================================================
# the remaining one-liners
# =============================================================================
class SmallFixTests(unittest.TestCase):
    def test_r4c2_derives_the_regime_before_shaping_the_plan(self):
        ea = code_only((ADD / "EA_studyarena_round4_contestant_c__1_.mq5").read_text(encoding="utf-8"))
        body = ea[ea.index("bool BuildPlan("):]
        self.assertLess(body.index("RegimeParams(ctx);"), body.index("SpreadDivergence(ctx, plan)"))

    def test_r4a_gamma_hedge_requires_a_hedging_account(self):
        ea = code_only((ADD / "EA_studyarena_round4_contestant_a__1_.mq5").read_text(encoding="utf-8"))
        body = ea[ea.index("void SyncGamma("):]
        self.assertIn("ACCOUNT_MARGIN_MODE_RETAIL_HEDGING", body)
        self.assertLess(body.index("ACCOUNT_MARGIN_MODE_RETAIL_HEDGING"), body.index("m_hedgeCount - 1"))

    def test_the_session_counters_use_the_london_clock(self):
        for ea in ("EA_studyarena_round11_contestant_a", "EA_studyarena_round12_qwen3_8_2_4t_a95b_high_reasoning",
                   "EA_studyarena_round12_contestant_c"):
            text = code_only((ADD / f"{ea}.mq5").read_text(encoding="utf-8"))
            self.assertIn("EA_ClockToServer(StructToTime(dt))", text, ea)
            self.assertIn("TimeToStruct(EA_ClockNow(), dt);", text, ea)

    def test_range_between_and_median_range_are_bounded_and_on_the_london_clock(self):
        users = [p for p in ADD.glob("*.mq5") if "bool RangeBetween(" in p.read_text(encoding="utf-8")]
        self.assertEqual(len(users), 6)
        for p in users:
            text = code_only(p.read_text(encoding="utf-8"))
            self.assertIn("EA_MinutesOfDay(EA_BarClockTime(r[i].time))", text, p.name)
            self.assertNotIn("i < 400", text, p.name)
        meds = [p for p in ADD.glob("*.mq5") if re.search(r"double Median(?:Daily)?Range\(", p.read_text(encoding="utf-8"))]
        self.assertEqual(len(meds), 8)
        for p in meds:
            text = code_only(p.read_text(encoding="utf-8"))
            self.assertNotIn("ArrayResize(s, 20);", text, p.name)
            self.assertIn("return s[got / 2];", text, p.name)


if __name__ == "__main__":
    unittest.main()
