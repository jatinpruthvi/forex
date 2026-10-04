"""Behavioural spec for the top-25 fixes on the Triad path and the harness tools.

MQL5 cannot run in this sandbox, so the rules that were fixed are mirrored in
Python and pinned against the *defect* they replace:

  #4  a pending order's risk-free test must use the ORDER's own type
  #5  the liquidity sweep must be a real precondition (takeout + reclaim)
  #6  heat/exposure count only this EA's magic
  #7  the news gate fails CLOSED on an unusable calendar; impact is case-insensitive
  #8  rows whose timestamp does not parse are rejected and counted
  #9  state keys are namespaced; the day key is the full date
  #10 the daily freeze lifts at the day boundary, the trailing freeze does not
  #11 the bearish structure search mirrors the bullish one
  #12 the cooldown keys on the setup timeframe, not the chart's
  #18 equal end_time ties are broken by file mtime (tested against the real tool)
  #19 gen_launcher writes the universe union (tested against the real tool)
"""
from __future__ import annotations

import csv
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]

# ---------------------------------------------------------------- #4 / #6 -----
ORDER_TYPE_BUY, ORDER_TYPE_SELL = 0, 1
ORDER_TYPE_BUY_LIMIT, ORDER_TYPE_SELL_LIMIT = 2, 3
ORDER_TYPE_BUY_STOP, ORDER_TYPE_SELL_STOP = 4, 5
POSITION_TYPE_BUY, POSITION_TYPE_SELL = 0, 1


def risk_free(order_is_buy: bool, sl: float, price: float) -> bool:
    """Mirror of the FIXED pending-order test in RiskGovernor.mqh."""
    if order_is_buy and sl >= price:
        return True
    if (not order_is_buy) and sl <= price:
        return True
    return False


def delivered_pending_risk_free(position_type: int, sl: float, price: float) -> bool:
    """The delivered rule: judged the ORDER with the stale position object."""
    if position_type == POSITION_TYPE_BUY and sl >= price:
        return True
    if position_type == POSITION_TYPE_SELL and sl <= price:
        return True
    return False


def heat(positions, magic: int | None) -> float:
    """Sum of stop-distance risk / balance; `magic=None` mirrors the delivered no-filter."""
    total = 0.0
    for pos in positions:
        if magic is not None and pos["magic"] != magic:
            continue
        if pos["sl"] == 0.0:
            total += 1.0                     # synthetic 100% for a stop-less position
            continue
        total += pos["risk"]
    return total


class PendingOrderRiskTests(unittest.TestCase):
    def test_sell_limit_was_classified_by_the_stale_position(self):
        # A stale BUY position (from an earlier loop) + a genuine SELL LIMIT whose
        # stop sits ABOVE entry: the delivered rule asked the *position* object,
        # `sl >= price` was true, so the order was declared risk-free and its 1.5%
        # currency exposure vanished from the cap.
        sl, price = 1.1100, 1.1000            # sell limit: stop above entry -> at risk
        self.assertTrue(delivered_pending_risk_free(POSITION_TYPE_BUY, sl, price))
        self.assertFalse(risk_free(False, sl, price))

    def test_fixed_rule_judges_the_order_itself(self):
        self.assertTrue(risk_free(True, 1.1100, 1.1000))     # buy, stop above -> BE+
        self.assertFalse(risk_free(True, 1.0900, 1.1000))    # buy, stop below -> at risk
        self.assertTrue(risk_free(False, 1.0900, 1.1000))    # sell, stop below -> BE+
        self.assertFalse(risk_free(False, 1.1100, 1.1000))   # sell, stop above -> at risk

    def test_foreign_magic_and_stop_less_positions(self):
        positions = [
            {"magic": 777112, "sl": 0.0, "risk": 0.5},   # ours, stop-less
            {"magic": 0, "sl": 0.0, "risk": 0.0},        # manual, stop-less
            {"magic": 999999, "sl": 1.0, "risk": 0.5},   # another EA
        ]
        self.assertEqual(heat(positions, None), 2.5, "delivered: every account-wide position counted")
        self.assertEqual(heat(positions, 777112), 1.0, "fixed: only our stop-less position blocks")


# ---------------------------------------------------------------- #5 / #11 -----
def sweep_ok(rates, bias: int) -> bool:
    """Mirror of DetectLiquiditySweep: bars 50..59 are prior liquidity, 1..49 the candidate."""
    prior = min(r["low"] for r in rates[50:60]) if bias == 1 else max(r["high"] for r in rates[50:60])
    idx, price = -1, (rates[1]["low"] if bias == 1 else rates[1]["high"])
    for i in range(1, 50):
        if bias == 1 and rates[i]["low"] <= price:
            price, idx = rates[i]["low"], i
        if bias == -1 and rates[i]["high"] >= price:
            price, idx = rates[i]["high"], i
    if idx < 0:
        return False
    if bias == 1:
        return price < prior and rates[idx]["close"] > prior
    return price > prior and rates[idx]["close"] < prior


def make_rates(sweep_idx: int, sweep_bias: int, close_back: bool):
    rates = [{"high": 1.1050, "low": 1.1000, "close": 1.1025} for _ in range(60)]
    for i in range(50, 60):                      # prior liquidity floor 1.0950 / ceiling 1.1050
        rates[i] = {"high": 1.1060, "low": 1.0950, "close": 1.1000}
    for i in range(1, 50):
        rates[i] = {"high": 1.1030, "low": 1.0990, "close": 1.1020}
    if sweep_bias == 1:
        rates[sweep_idx] = {"high": 1.1010, "low": 1.0930,
                            "close": 1.0970 if close_back else 1.0940}
    else:
        rates[sweep_idx] = {"high": 1.1070, "low": 1.0990,
                            "close": 1.1030 if close_back else 1.1060}
    return rates


class SweepTests(unittest.TestCase):
    def test_takeout_with_reclaim_is_a_sweep(self):
        self.assertTrue(sweep_ok(make_rates(5, 1, True), 1))
        self.assertTrue(sweep_ok(make_rates(7, -1, True), -1))

    def test_breakdown_that_holds_is_not_a_sweep(self):
        self.assertFalse(sweep_ok(make_rates(5, 1, False), 1))
        self.assertFalse(sweep_ok(make_rates(7, -1, False), -1))

    def test_no_takeout_fails_both_directions(self):
        flat = make_rates(5, 1, True)
        for r in flat:
            r["low"] = max(r["low"], 1.0960)      # nothing below the prior floor 1.0950
        self.assertFalse(sweep_ok(flat, 1))
        flat2 = make_rates(7, -1, True)
        for r in flat2:
            r["high"] = min(r["high"], 1.1040)    # nothing above the prior ceiling 1.1050
        self.assertFalse(sweep_ok(flat2, -1))


# ---------------------------------------------------------------- #7 / #8 -----
def impact_kept(impact: str) -> bool:
    """Mirror of the FIXED impact filter (both load paths)."""
    return impact.strip().lower() == "high"


def load_result(rows, delivered: bool):
    """(load_ok, events) for a list of (timestamp_or_0, impact) rows."""
    events = []
    bad = 0
    for ts, impact in rows:
        if delivered:
            if impact != "High":
                continue
            if ts:
                events.append(ts)
            continue
        if not impact_kept(impact):
            continue
        if ts is None or ts <= 0:
            bad += 1
            continue
        events.append(ts)
    if delivered:
        return True, events                      # the delivered loader always "succeeded"
    return (len(rows) > 0 and bad == 0), events


def gate_blocks(load_ok: bool, events, delivered: bool) -> bool:
    if delivered:
        return False if not events else True     # empty list -> fail OPEN
    if not load_ok:
        return True                              # fail closed
    return bool(events)


class NewsGateTests(unittest.TestCase):
    def test_impact_casing(self):
        for ok in ("High", "HIGH", "high", " High "):
            self.assertTrue(impact_kept(ok), ok)
        for no in ("Medium", "Low", "COVERAGE", ""):
            self.assertFalse(impact_kept(no), no)

    def test_unparseable_rows_fail_closed(self):
        rows = [(None, "High"), (1_700_000_000, "High")]     # first row's time did not parse
        ok, events = load_result(rows, delivered=False)
        self.assertFalse(ok)
        self.assertEqual(len(events), 1)
        self.assertTrue(gate_blocks(ok, events, delivered=False))

        ok_old, events_old = load_result(rows, delivered=True)
        self.assertTrue(ok_old, "the delivered loader reported success regardless")
        self.assertEqual(len(events_old), 1, "the delivered loader silently dropped the bad row")

    def test_quiet_week_is_not_a_blackout(self):
        rows = [(1_700_000_000, "Medium"), (1_700_100_000, "COVERAGE")]
        ok, events = load_result(rows, delivered=False)
        self.assertTrue(ok, "the file was readable and had rows")
        self.assertEqual(events, [])
        self.assertFalse(gate_blocks(ok, events, delivered=False))

    def test_empty_file_fails_closed(self):
        ok, events = load_result([], delivered=False)
        self.assertFalse(ok)
        self.assertTrue(gate_blocks(ok, events, delivered=False))


# ---------------------------------------------------------------- #9 / #10 ----
def day_key_delivered(year: int, day_of_year: int) -> int:
    return day_of_year


def day_key_fixed(year: int, month: int, day: int) -> tuple[int, int, int]:
    return (year, month, day)


def daily_freeze_active(freeze_day, today, delivered: bool, breaker_time_unix: float,
                        now_unix: float) -> bool:
    if delivered:
        return now_unix < breaker_time_unix       # one timestamp for both breakers
    return freeze_day == today


def trailing_freeze_active(until_unix: float, now_unix: float) -> bool:
    return now_unix < until_unix


class GovernorStateTests(unittest.TestCase):
    def test_day_key_survives_a_year_boundary(self):
        # 2026-01-01 and 2027-01-01 share day_of_year == 1: the delivered key called
        # them the same day and kept a year-old anchor.
        self.assertEqual(day_key_delivered(2026, 1), day_key_delivered(2027, 1))
        self.assertNotEqual(day_key_fixed(2026, 1, 1), day_key_fixed(2027, 1, 1))

    def test_daily_freeze_is_lifted_by_the_day_boundary(self):
        # tripped at 23:50; the day rolls over ten minutes later
        trip_day, next_day = 1_700_000_000.0, 1_700_086_400.0
        # on the trip day the freeze IS active - that is the prop rule
        self.assertTrue(daily_freeze_active(trip_day, trip_day, False, 0.0, trip_day + 60))
        # and on the next day it is gone
        self.assertFalse(daily_freeze_active(trip_day, next_day, False, 0.0, next_day),
                         "the fixed daily freeze is scoped to the day it tripped")
        # the delivered rule claimed a 24h window, so it was still active the next day
        self.assertTrue(daily_freeze_active(None, None, True, trip_day + 86_400, trip_day + 600),
                        "the delivered freeze outlived its own day boundary")

    def test_trailing_freeze_is_not_lifted_by_the_day_boundary(self):
        tripped, later = 1_700_000_000.0, 1_700_000_000.0 + 3_600
        until = tripped + 48 * 3600
        self.assertTrue(trailing_freeze_active(until, later))
        self.assertTrue(trailing_freeze_active(until, later + 86_400),
                        "48h freeze must still be active after the day boundary")


# ---------------------------------------------------------------- #18 / #19 ----
def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, cwd=str(REPO), **kw)


def write_result(path: Path, net: float, mtime: float):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "expert,strategy,magic,test_symbol,timeframe,trades,profit_trades,loss_trades,"
        "net_profit,profit_factor,expected_payoff,equity_dd_pct,recovery_factor,sharpe,end_time\n"
        f"EA_demo,EA_demo,9999,EURUSD,M15,50,30,20,{net},1.5,0.2,5.0,1.2,0.8,2026.09.30 23:59\n",
        encoding="utf-8")
    os.utime(path, (mtime, mtime))               # end_time ties; mtime decides


class HarnessToolTests(unittest.TestCase):
    def test_parse_results_breaks_ties_by_mtime(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            results = tmp / "results"
            write_result(results / "A_stale.csv", 100.0, time.time() - 600)
            write_result(results / "Z_fresh.csv", 200.0, time.time())
            out = tmp / "out"
            r = run([sys.executable, "validation/mt5_harness/parse_results.py",
                     "--dir", str(results), "--manifest", str(tmp / "none.json"),
                     "--out", str(out)])
            self.assertEqual(r.returncode, 0, r.stderr[-400:])
            rows = list(csv.DictReader((out / "portfolio_summary.csv").open(encoding="utf-8")))
            self.assertEqual(len(rows), 1)
            self.assertEqual(float(rows[0]["net_profit"]), 200.0,
                             "the newer FILE must win an end_time tie (was: alphabetical)")

    def test_gen_launcher_writes_the_universe_union(self):
        with tempfile.TemporaryDirectory() as td:
            r = run([sys.executable, "validation/mt5_harness/gen_launcher.py", "--out", td])
            self.assertEqual(r.returncode, 0, r.stderr[-400:])
            syms = (Path(td) / "symbols.txt").read_text(encoding="utf-8").split()
            self.assertGreaterEqual(len(syms), 19)          # the generator reports 19
            for expected in ("EURUSD", "GBPUSD", "XAUUSD", "GER40"):
                self.assertIn(expected, syms)
            readme = (Path(td) / "READ_ME_FIRST.txt").read_text(encoding="utf-8")
            self.assertIn("IMPORTANT", readme, "the synth-template risk must be loud")

    def test_compile_all_matches_the_log_case_insensitively(self):
        ps1 = (REPO / "validation" / "mt5_harness" / "compile_all.ps1").read_text(encoding="utf-8")
        self.assertNotIn('": information: result"', ps1)
        self.assertIn("(?i):\\s*error", ps1)
        self.assertIn("nothing in the log proves a compile happened", ps1)


if __name__ == "__main__":
    unittest.main()
