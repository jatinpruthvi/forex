"""Unit tests for the JJ Simon 1-min fair-pricing signal detectors and simulator.

Run:
    cd /home/user/forex
    python3 -m pytest validation/tests/test_jj_sim.py -q
or:
    python3 validation/tests/test_jj_sim.py
"""

from __future__ import annotations

import math
import os
import sys
import unittest
from datetime import datetime, time as dtime, timedelta

import numpy as np
import pandas as pd
import pytz

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from validation.jj_sim.simulator import (  # noqa: E402
    Account,
    FairPriceModel,
    FirmRules,
    Side,
    SignalType,
    Window,
    detect_bos,
    detect_displacement,
    generate_synthetic_m1,
    load_m1_csv,
    ny_window,
    simulate,
)


NY = pytz.timezone("US/Eastern")
UTC = pytz.UTC


def _make_bars(seq, start="2024-09-09 09:30", freq_min=1):
    """Helper: build a structured bar array from a list of (o,h,l,c,v) tuples."""
    start_ts = pd.Timestamp(start, tz=NY).tz_convert(UTC)
    arr = np.zeros(len(seq), dtype=[
        ("ts", "i8"), ("open", "f8"), ("high", "f8"),
        ("low", "f8"), ("close", "f8"), ("volume", "f8"), ("ts_dt", "O"),
    ])
    for i, (o, h, l, c, v) in enumerate(seq):
        ts = start_ts + pd.Timedelta(minutes=i * freq_min)
        arr["ts"][i] = ts.value // 10**6
        arr["open"][i] = o
        arr["high"][i] = h
        arr["low"][i] = l
        arr["close"][i] = c
        arr["volume"][i] = v
        arr["ts_dt"][i] = ts
    return arr


class TestNYWindow(unittest.TestCase):
    def test_windows(self):
        samples = [
            ("2024-09-09 09:00", Window.CLOSED),
            ("2024-09-09 09:30", Window.NY_AM),
            ("2024-09-09 10:30", Window.NY_AM),
            ("2024-09-09 11:00", Window.DEAD),
            ("2024-09-09 12:30", Window.DEAD),
            ("2024-09-09 14:00", Window.NY_PM),
            ("2024-09-09 15:00", Window.NY_PM),
            ("2024-09-09 15:30", Window.CLOSED),
            ("2024-09-09 18:00", Window.CLOSED),
        ]
        for ts_str, expected in samples:
            ts = pd.Timestamp(ts_str, tz=NY).tz_convert(UTC)
            self.assertEqual(ny_window(ts), expected, f"failed on {ts_str}")


class TestDisplacement(unittest.TestCase):
    def test_no_trigger_in_tight_market(self):
        # 12 flat 1-pip bars
        seq = [(1.10 + i * 0.00001, 1.10 + 0.0001, 1.10 - 0.0001,
                1.10 + i * 0.00001, 100) for i in range(12)]
        bars = _make_bars(seq)
        # Fair price far away (would welcome reversion) but no displacement
        self.assertIsNone(detect_displacement(bars, 11, fair_price=1.11))

    def test_bullish_displacement_triggers_short_reversion(self):
        # 10 quiet bars, then one big bull candle away from fair price below
        seq = []
        for _ in range(10):
            seq.append((1.10, 1.1003, 1.0997, 1.10, 100))
        # bull displacement: open 1.10, close 1.1040 (large body), closes at high (no upper wick)
        seq.append((1.10, 1.1040, 1.0997, 1.1040, 500))
        bars = _make_bars(seq)
        sig = detect_displacement(bars, 10, fair_price=1.09)  # fair below → short reversion
        self.assertIsNotNone(sig)
        self.assertEqual(sig.type, SignalType.DISPLACEMENT)
        self.assertEqual(sig.side, Side.SHORT)
        self.assertAlmostEqual(sig.fair_price, 1.09)

    def test_bearish_displacement_triggers_long_reversion(self):
        seq = []
        for _ in range(10):
            seq.append((1.10, 1.1003, 1.0997, 1.10, 100))
        # bear displacement: close at the low (no lower wick), big body down
        seq.append((1.10, 1.1003, 1.0960, 1.0960, 500))
        bars = _make_bars(seq)
        sig = detect_displacement(bars, 10, fair_price=1.11)
        self.assertIsNotNone(sig)
        self.assertEqual(sig.side, Side.LONG)

    def test_displacement_toward_fair_price_ignored(self):
        # Displacement moves TOWARD fair price (not away) → no signal
        seq = []
        for _ in range(10):
            seq.append((1.10, 1.1003, 1.0997, 1.10, 100))
        seq.append((1.10, 1.1001, 1.0960, 1.0960, 500))
        bars = _make_bars(seq)
        sig = detect_displacement(bars, 10, fair_price=1.09)  # fair below, displaces down toward it
        self.assertIsNone(sig)


class TestBreakOfStructure(unittest.TestCase):
    def test_bos_long_after_swing_low(self):
        # Manufacture a classic pattern: 6 flat bars, a low wick, then a close
        # back above the low wick when fair is above.
        seq = []
        for _ in range(6):
            seq.append((1.10, 1.1005, 1.0995, 1.1000, 100))
        # pivot low bar
        seq.append((1.1000, 1.1000, 1.0970, 1.0980, 200))  # index 6
        # two higher neighbors on each side
        seq.append((1.0980, 1.0995, 1.0980, 1.0990, 200))  # 7
        seq.append((1.0990, 1.1000, 1.0985, 1.0995, 200))  # 8
        # close back above pivot
        seq.append((1.0995, 1.1010, 1.0995, 1.1008, 300))  # 9 → breaks the pivot low's close above
        bars = _make_bars(seq)
        sig = detect_bos(bars, 9, fair_price=1.1050)
        self.assertIsNotNone(sig)
        self.assertEqual(sig.side, Side.LONG)


class TestFirmRulesAndAccount(unittest.TestCase):
    def test_drawdown_breach(self):
        rules = FirmRules(name="test", start_balance=1000,
                          profit_target_pct=0.10,
                          overall_drawdown_pct=0.10,
                          daily_loss_pct=0.05,
                          risk_per_trade_pct=0.01, rr=1.5)
        acct = Account(account_id=0, rules=rules)
        acct.balance = 899  # below 900 floor
        from validation.jj_sim.simulator import check_rules
        check_rules(acct, current_price=0)  # no open trade
        self.assertEqual(acct.status, "failed")

    def test_profit_target_passes(self):
        rules = FirmRules(name="test", start_balance=1000,
                          profit_target_pct=0.10,
                          overall_drawdown_pct=0.10,
                          daily_loss_pct=0.05,
                          risk_per_trade_pct=0.01, rr=1.5)
        acct = Account(account_id=0, rules=rules)
        acct.balance = 1101
        from validation.jj_sim.simulator import check_rules
        check_rules(acct, current_price=0)
        self.assertEqual(acct.status, "passed")


class TestThreeLossRule(unittest.TestCase):
    def test_three_losses_locks_session(self):
        fp = FairPriceModel()
        # fake session setup: set fair price by invoking on_bar at 9:30
        seq = [(1.10, 1.101, 1.099, 1.10, 100)]
        bars = _make_bars(seq, start="2024-09-09 09:30")
        fp.on_bar(bars, 0, [])
        self.assertTrue(fp.can_trade())
        fp.register_trade_result(won=False)
        self.assertTrue(fp.can_trade())
        fp.register_trade_result(won=False)
        self.assertTrue(fp.can_trade())
        fp.register_trade_result(won=False)
        self.assertFalse(fp.can_trade())


class TestSyntheticSimulation(unittest.TestCase):
    def test_end_to_end_on_synthetic(self):
        bars, news = generate_synthetic_m1(n_sessions=250, seed=42)
        rules = FirmRules.presets()["eval_1to1_5"]
        res = simulate(bars=bars, rules=rules, n_accounts=25, news_events=news)
        self.assertEqual(len(res.accounts), 25)
        # Eval config has a fixed profit target (10%) and DD floor — every account
        # should have hit one side or the other within 80 sessions.
        self.assertTrue(all(a.status in ("passed", "failed") for a in res.accounts))
        # With default synthetic p_reversal=0.58 and RR=1.5, pass rate should be
        # materially above zero. 10% is a very conservative lower bound.
        self.assertGreater(res.pass_rate, 0.10)
        self.assertGreater(res.signals_fired, 0)
        self.assertGreater(res.trades_taken, 0)
        if res.pass_rate > 0:
            self.assertGreater(res.cost_per_funded, 0)

    def test_dead_zone_produces_no_trades(self):
        bars, news = generate_synthetic_m1(n_sessions=30, seed=1)
        rules = FirmRules.presets()["eval_1to1_5"]
        res = simulate(bars=bars, rules=rules, n_accounts=10, news_events=news)
        # No trade should have its entry_time in the dead zone
        for acct in res.accounts:
            for t in acct.closed_trades:
                self.assertNotEqual(ny_window(t.entry_time), Window.DEAD,
                                    f"trade in dead zone: {t.entry_time}")

    def test_all_configs_run(self):
        bars, news = generate_synthetic_m1(n_sessions=250, seed=3)
        for name, rules in FirmRules.presets().items():
            res = simulate(bars=bars, rules=rules, n_accounts=10, news_events=news)
            # For non-grow configs every account must resolve within 250 sessions.
            if not rules.grow_only:
                self.assertTrue(
                    all(a.status in ("passed", "failed") for a in res.accounts),
                    f"{name}: {[a.status for a in res.accounts]}",
                )


class TestLoadCSV(unittest.TestCase):
    def test_load_existing_m1_eurusd(self):
        path = os.path.join(ROOT, "validation/HistoryData/m1-data",
                            "eurusd-m1-2024-09-11_2026-09-11.csv")
        if not os.path.exists(path):
            self.skipTest("sample M1 CSV not present")
        bars = load_m1_csv(path, max_rows=2000)
        self.assertEqual(len(bars), 2000)
        # Timestamps strictly increasing (weekend/session gaps allowed, just not
        # backwards or duplicate)
        self.assertTrue(np.all(np.diff(bars["ts"].astype(np.int64)) > 0))


if __name__ == "__main__":
    unittest.main(verbosity=2)
