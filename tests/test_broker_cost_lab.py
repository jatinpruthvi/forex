import sys, unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools import broker_cost_lab as B


class T(unittest.TestCase):
    def test_eurusd_cost(self):
        # 10-pip stop, 0.2 pip spread, $4: (0.2*10 + 4) / (10*10 + 4)
        self.assertAlmostEqual(B.cost_R("EURUSD", 10.0, 4.0, 2.0), (0.1 * 2 * 10 + 4) / (100 + 4), places=9)

    def test_commission_dominates_tight_stop(self):
        self.assertGreater(B.cost_R("EURUSD", 3.0, 4.5, 1.0), B.cost_R("EURUSD", 12.0, 4.5, 1.0))

    def test_cheaper_than_repo_model(self):
        self.assertLess(B.cost_R("GBPUSD", 8.0, 4.0, 2.0), (0.55 * 1.4 * 10 + 7) / (8 * 10 + 7))

    def test_rollover_window_dst_aware(self):
        import datetime as dt
        ms = lambda y, m, d, h, mi: int(dt.datetime(y, m, d, h, mi, tzinfo=dt.timezone.utc).timestamp() * 1000)
        self.assertTrue(B.in_rollover({"t_sig": ms(2021, 7, 7, 21, 0)}))      # summer: 17:00 NY = 21:00 UTC
        self.assertFalse(B.in_rollover({"t_sig": ms(2021, 7, 7, 23, 0)}))
        self.assertTrue(B.in_rollover({"t_sig": ms(2021, 1, 7, 22, 0)}))      # winter: 17:00 NY = 22:00 UTC
        self.assertFalse(B.in_rollover({"t_sig": ms(2021, 1, 7, 21, 0)}))
        self.assertTrue(B.in_rollover({"t_sig": ms(2021, 7, 7, 20, 55)}))


if __name__ == "__main__":
    unittest.main()
