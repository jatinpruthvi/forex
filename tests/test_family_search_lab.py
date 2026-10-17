import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools import family_search_lab as F  # noqa: E402

DAY_M5 = 288


def synth(daily_ohlc, sym="EURUSD"):
    """Each daily bar = 288 M5 bars: open, then flat at close, with the day's high/low placed on bars 10 and 20."""
    ts, o, h, l, c = [], [], [], [], []
    t0 = 1_600_000_000_000 - (1_600_000_000_000 % 86_400_000) + 22 * 3_600_000       # a 22:00 UTC start; NY-17 bucket = one bar-day each
    for i, (a, hi, lo, cl) in enumerate(daily_ohlc):
        for b in range(DAY_M5):
            ts.append(t0 + (i * DAY_M5 + b) * 300_000)
            if b == 0: o.append(a); h.append(a); l.append(a); c.append(a)
            elif b == 10: o.append(a); h.append(hi); l.append(a); c.append(a)
            elif b == 20: o.append(a); h.append(a); l.append(lo); c.append(a)
            elif b == DAY_M5 - 1: o.append(cl); h.append(cl); l.append(cl); c.append(cl)
            else: o.append(a); h.append(a); l.append(a); c.append(a)
    p = object.__new__(F.Pair)
    p.sym = sym
    p.d = dict(ts=np.array(ts, np.int64), o=np.array(o), h=np.array(h), l=np.array(l), c=np.array(c))
    p.dd = F.daily(p.d)
    p.pip, p.pv, p.spread_pips = 0.0001, 10.0, 0.5
    return p


class Sim(unittest.TestCase):
    def base(self, n=40, px=1.10):
        return [(px, px + 0.0010, px - 0.0010, px)] * n           # ATR = 0.0020

    def test_daily_shape(self):
        p = synth(self.base(30))
        self.assertGreaterEqual(len(p.dd["c"]), 28)
        self.assertAlmostEqual(float(p.dd["atr"][-1]), 0.0020, places=9)

    def test_long_stop_fills_at_stop_when_no_gap(self):
        days = self.base(30) + [(1.10, 1.101, 1.0940, 1.095)] + self.base(5, 1.095)
        p = synth(days)
        di = 24
        t, kx = F.simulate(p, di, 1, 2.0, hold_max=10)      # entry ~1.10, dist 0.004, stop 1.096
        self.assertIsNotNone(t)
        self.assertAlmostEqual(t["R_pess"], -1.0, places=6)
        self.assertEqual(t["R_opt"], -1.0)

    def test_gap_through_stop_is_worse_than_minus_one(self):
        days = self.base(26) + [(1.10, 1.101, 1.099, 1.10)] + [(1.090, 1.091, 1.089, 1.090)] * 3 + self.base(5, 1.09)
        p = synth(days)
        t, _ = F.simulate(p, 25, 1, 2.0, hold_max=10)
        self.assertLess(t["R_pess"], -1.5)                   # opens 0.010 below a 0.004 stop distance -> about -2.5R
        self.assertEqual(t["R_opt"], -1.0)

    def test_short_mirror(self):
        days = self.base(26) + [(1.10, 1.101, 1.099, 1.10)] + [(1.110, 1.111, 1.109, 1.110)] * 3 + self.base(5, 1.11)
        p = synth(days)
        t, _ = F.simulate(p, 25, -1, 2.0, hold_max=10)
        self.assertLess(t["R_pess"], -1.5)

    def test_time_exit_at_next_open_and_no_lookahead_in_entry(self):
        days = self.base(26) + [(1.10, 1.1010, 1.0990, 1.10)] * 20
        p = synth(days)
        t, kx = F.simulate(p, 25, 1, 3.0, hold_max=4)
        self.assertEqual(kx, 25 + 4)
        self.assertAlmostEqual(t["R_pess"], 0.0, places=6)
        self.assertEqual(t["t_fill"], int(p.d["ts"][p.dd["js"][26]]))  # entry = first bar of the NEXT day

    def test_cost_R_small_on_daily_stop(self):
        p = synth(self.base(30))
        self.assertLess(F.cost_R(p, 0.004), 0.25)


class NoLookahead(unittest.TestCase):
    def test_truncation_invariance_F1_F2(self):
        path = next(F.X.CI.glob("eurusd-m5-2016-09-11_*.csv"), None)
        if path is None:
            self.skipTest("10y set not present")
        full = F.Pair("EURUSD", path)
        cut = int(np.searchsorted(full.d["ts"], F.ms("2022-01-01")))
        half = object.__new__(F.Pair)
        half.__dict__.update(full.__dict__)
        half.d = {k: v[:cut] for k, v in full.d.items()}
        half.dd = F.daily(half.d)
        for fn, args in ((F.run_F1, (20, 3.0)), (F.run_F2, (3, 2.0))):
            a = {(t["t_fill"], t["dir"], round(t["R_pess"], 9)) for t in fn(full, *args) if t["t_exit"] < half.d["ts"][-1] - 86_400_000 * 3}
            b = {(t["t_fill"], t["dir"], round(t["R_pess"], 9)) for t in fn(half, *args) if t["t_exit"] < half.d["ts"][-1] - 86_400_000 * 3}
            self.assertTrue(len(b) > 10)
            self.assertEqual(a & {x for x in a if x[0] < half.d["ts"][-1] - 86_400_000 * 10}, b & {x for x in b if x[0] < half.d["ts"][-1] - 86_400_000 * 10})


if __name__ == "__main__":
    unittest.main()
