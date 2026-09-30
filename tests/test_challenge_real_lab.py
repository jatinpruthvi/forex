import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools import challenge_real_lab as CR  # noqa: E402


class FakeWorld:
    def __init__(self, nets, n=400):
        self.days = np.arange(20000, 20000 + n)
        self.tab = {int(d): [(nets, 30.0, "EURUSD")] for d in self.days}


class Rules(unittest.TestCase):
    def cfg(self, risk=0.025):
        return dict(risk=risk, mult=0.0)

    def test_always_win_passes_both_then_pays(self):
        # every trade +2R: 5% a day at 2.5% risk -> phase 1 needs 2 days but 3 profitable days, phase 2 then funded payouts every >= 14 days
        w = FakeWorld(2.0)
        r = CR.run_path(w, 0, self.cfg(), np.random.default_rng(1))
        self.assertTrue(r["p1"] and r["p2"])
        self.assertEqual(len(r["payouts"]), 5)
        self.assertTrue(0.04 <= r["payouts"][0] <= 0.085)        # two +5 % wins overshoot the +5 % target; it then stops trading and pays 80 % of the gain

    def test_min_days_delays_pass(self):
        w = FakeWorld(2.0)
        r = CR.run_path(w, 0, self.cfg(0.025), np.random.default_rng(1), dict(CR.RULES, rounds=0 + 1))
        self.assertGreaterEqual(r["days"], 3 + 3 + 14)          # 3 profitable days per step, then a >= 14 day wait for the first payout

    def test_always_lose_is_blown_at_10pct(self):
        w = FakeWorld(-1.0)
        r = CR.run_path(w, 0, self.cfg(0.025), np.random.default_rng(1))
        self.assertEqual(r["end"], "blown_stage1")
        self.assertEqual(r["days"], 4)                           # 4 x 2.5 % = 10 %

    def test_daily_breach_terminates(self):
        w = FakeWorld(-1.3)
        r = CR.run_path(w, 0, dict(risk=0.04, mult=0.0), np.random.default_rng(1))
        self.assertTrue(r["end"].startswith("daily_breach"))     # 4 % x 1.3 = 5.2 % in a day

    def test_costs_reduce_r(self):
        self.assertLess(CR.trade_net((0.5, 30.0, "EURUSD"), 6.0), CR.trade_net((0.5, 30.0, "EURUSD"), 2.0))


@unittest.skipUnless(CR.T.X.CI.exists(), "needs 10y M5")
class Real(unittest.TestCase):
    def test_world_trades_are_zero_edge_and_causal(self):
        w = CR.world(2.0)
        r = np.array([t[0] for v in w.tab.values() for t in v])
        self.assertGreater(len(r), 100_000)
        self.assertLess(abs(r.mean()), 0.06)                      # random direction and time: no edge before costs
        self.assertTrue((r >= -60).all())


if __name__ == "__main__":
    unittest.main()
