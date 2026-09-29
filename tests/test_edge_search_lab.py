import sys, unittest
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools import edge_search_lab as E  # noqa: E402


def bars(n, base=1.10, start=1_600_000_000_000):
    ts = start - start % 300_000 + np.arange(n) * 300_000
    o = np.full(n, base); return dict(ts=ts.astype(np.int64), o=o.copy(), h=o + 0.0001, l=o - 0.0001, c=o.copy())


class T(unittest.TestCase):
    def test_config_count(self):
        self.assertEqual(len(E.CONFIGS), 88 + 4 + 24)

    def test_fade_short_mirrors_long(self):
        d = bars(400)
        # a huge UP bar at 100 (short signal), then drift down to target
        d["o"][100] = 1.10; d["c"][100] = 1.20; d["h"][100] = 1.20; d["l"][100] = 1.10
        d["o"][101:] = 1.20; d["h"][101:] = 1.2001; d["l"][101:] = 1.1999; d["c"][101:] = 1.20
        d["l"][110] = 1.00                                    # a deep drop -> target hit
        t = E.fade_trades("EURUSD", d, 3.0, 2.0, 5.0, "both")
        self.assertTrue(any(x["dir"] == -1 for x in t))
        s = [x for x in t if x["dir"] == -1][0]
        self.assertAlmostEqual(s["R_pess"], 5.0, places=6)

    def test_gap_fade_target(self):
        d = bars(8000)
        i = 7000
        d["ts"][i:] += 60 * 3_600_000                         # 60h hole (weekend)
        d["o"][i:] = 1.1050; d["h"][i:] = 1.1051; d["l"][i:] = 1.1049; d["c"][i:] = 1.1050
        d["l"][i + 5] = 1.0999                                # gap of 50 pips filled (prior close 1.10)
        dd = E.F.daily(d)
        t = E.gap_trades("EURUSD", d, dd, 0.01, 2.0)
        self.assertEqual(len(t), 1)
        self.assertEqual(t[0]["dir"], -1)
        self.assertAlmostEqual(t[0]["R_pess"], 0.5, places=6)   # gap / (2*gap)

    def test_session_window_long_short(self):
        # 60 winter weekdays (London = UTC): price rises 10 pips between 00:00 and 07:00, flat otherwise
        import datetime as dt
        t0 = int(dt.datetime(2021, 1, 4, tzinfo=dt.timezone.utc).timestamp() * 1000)
        n = 60 * 288
        ts = t0 + np.arange(n) * 300_000
        o = np.empty(n)
        for i in range(n):
            m = (i % 288) * 5
            o[i] = 1.10 + (0.0010 * min(m, 420) / 420)
        d = dict(ts=ts.astype(np.int64), o=o, h=o + 0.00005, l=o - 0.00005, c=o)
        out = E.sess_trades("EURUSD", d, "A")
        self.assertGreater(len(out[1]), 20)
        self.assertGreater(np.mean([t["R_pess"] for t in out[1]]), 0)
        self.assertLess(np.mean([t["R_pess"] for t in out[-1]]), 0)
        self.assertTrue(all(t["t_fill"] % 86_400_000 == 0 for t in out[1]))     # entered at 00:00


if __name__ == "__main__":
    unittest.main()
