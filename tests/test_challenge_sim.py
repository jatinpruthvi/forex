import sys, unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools import challenge_sim as C

D = C.MS_D


def tr(day, r, cost=0.0, hold=0.1):
    return dict(t_fill=int(day * D), t_exit=int((day + hold) * D), R=r, cost=cost)


class T(unittest.TestCase):
    def test_pass_both_phases(self):
        trades = [tr(i, 1.0) for i in range(1, 25)]           # +1R at 1% risk: +1% per trade -> 10 trades P1, 5 trades P2
        o = C.simulate_start(trades, 0, 0.01)
        self.assertEqual(o["res"], "pass")
        self.assertAlmostEqual(o["days"], 15 + 0.1, places=6)

    def test_floor(self):
        trades = [tr(i * 2, -1.0) for i in range(1, 30)]      # -1%/trade, one per 2 days (never breaches daily)
        o = C.simulate_start(trades, 0, 0.01)
        self.assertEqual(o["res"], "floor")

    def test_daily_limit(self):
        trades = [tr(1, -1.0, hold=0.01), tr(1.02, -1.0, hold=0.01)]
        o = C.simulate_start(trades, 0, 0.03, max_conc=2)     # two -3% trades the same server day -> 6% > 4.5%
        self.assertEqual(o["res"], "daily")

    def test_one_slot_skips_overlap(self):
        trades = [tr(1, 1.0, hold=5), tr(2, 1.0, hold=0.1)]
        o = C.simulate_start(trades, 0, 0.1, p1=15, p2=10)    # second is skipped (slot busy): only +10% -> timeout
        self.assertEqual(o["res"], "timeout")

    def test_timeout_and_window(self):
        trades = [tr(1, 0.1), tr(100, 5.0)]
        o = C.simulate_start(trades, 0, 0.01)
        self.assertEqual(o["res"], "timeout")

    def test_zero_edge_null_has_zero_mean_gross(self):
        z = C.zero_edge([tr(1, 2.0), tr(2, -1.0), tr(3, -1.0)])
        self.assertAlmostEqual(sum(t["R"] for t in z), 0.0, places=9)


if __name__ == "__main__":
    unittest.main()
