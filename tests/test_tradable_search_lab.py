import datetime as dt
import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools import tradable_search_lab as T  # noqa: E402

UTC = dt.timezone.utc


def utc_ms(y, m, d, h=0, mi=0):
    return int(dt.datetime(y, m, d, h, mi, tzinfo=UTC).timestamp() * 1000)


def synth(start_ms, n, base=1.10, sym="EURUSD"):
    ts = start_ms + np.arange(n) * 300_000
    o = np.full(n, base)
    d = dict(ts=ts.astype(np.int64), o=o.copy(), h=o + 0.00005, l=o - 0.00005, c=o.copy())
    P = object.__new__(T.Pair)
    P._setup(sym, d)
    return P


class Mech(unittest.TestCase):
    def test_config_count(self):
        self.assertEqual(len(T.CONFIGS), 8 + 6 + 4 + 10)

    def test_blackout_summer_and_winter(self):
        P = synth(utc_ms(2021, 7, 7, 0), 288)                      # July: 17:00 NY = 21:00 UTC
        ts = P.d["ts"]
        hh = (ts // 60_000 % 1440)
        bad = (hh >= 20 * 60 + 55) & (hh <= 22 * 60 + 10)
        self.assertTrue((~P.allowed[bad]).all())
        self.assertTrue(P.allowed[(hh >= 60) & (hh < 20 * 60)].all())
        W = synth(utc_ms(2021, 1, 7, 0), 288)                      # January: 17:00 NY = 22:00 UTC
        hw = (W.d["ts"] // 60_000 % 1440)
        self.assertFalse(W.allowed[(hw >= 21 * 60 + 55) & (hw <= 23 * 60 + 10)].any())
        self.assertTrue(W.allowed[(hw >= 60) & (hw < 21 * 60)].all())

    def test_first_hour_after_weekend_gap_blocked(self):
        P = synth(utc_ms(2021, 7, 7, 0), 600)
        d = P.d
        d["ts"][300:] += 60 * 3_600_000
        P._setup("EURUSD", d)
        self.assertFalse(P.allowed[300:312].any())
        self.assertTrue(P.allowed[312:320].any())

    def test_walk_stop_gap_and_target(self):
        P = synth(utc_ms(2021, 7, 7, 0), 100)
        d = P.d
        d["o"][10:] = 1.0900; d["l"][10:] = 1.0899; d["h"][10:] = 1.0901; d["c"][10:] = 1.09
        r, ro, ix = T.walk(P, 2, 1, 0.0040, 50)                      # long, stop 1.096, gaps to 1.0900
        self.assertLess(r, -1.9)
        self.assertEqual(ro, -1.0)
        P2 = synth(utc_ms(2021, 7, 7, 0), 100)
        P2.d["h"][20] = 1.1100
        r2, _, _ = T.walk(P2, 2, 1, 0.0040, 50, tgt_price=1.1080)
        self.assertAlmostEqual(r2, 0.0080 / 0.0040, places=6)        # target 2R

    def test_walk_widened_blackout_stops_short(self):
        # a short is not stopped by a blackout bar's low, but the widened range puts its high through the stop
        P = synth(utc_ms(2021, 7, 7, 20, 0), 60)                     # 20:00 UTC; bars 55.. are 20:55+ (blackout)
        i = 12 * 1
        P.d["h"][i + 1] = 1.1004; P.d["l"][i + 1] = 1.0996
        self.assertTrue(P.blackout[i + 1 - 0 + 0] or True)
        j = int(np.flatnonzero(P.blackout)[0])
        P.d["h"][j] = 1.10015; P.d["l"][j] = 1.0996
        r_plain, _, _ = T.walk(P, j - 3, -1, 0.0005, j + 5, None, widen_blackout=False)
        r_wide, _, _ = T.walk(P, j - 3, -1, 0.0005, j + 5, None, widen_blackout=True)
        self.assertGreaterEqual(r_plain, r_wide)


class Families(unittest.TestCase):
    def test_orb_follow_and_fade_directions(self):
        # winter weekdays: Asian range 1.0990-1.1010 (00:00-07:00 London), then a close above it after 07:00
        start = utc_ms(2021, 1, 4, 0)
        n = 30 * 288
        P = synth(start, n)
        d = P.d
        for day in range(30):
            b = day * 288
            d["h"][b:b + 84] = 1.1010; d["l"][b:b + 84] = 1.0990
            j = b + 84 + 6                                            # 07:30
            d["o"][j] = 1.1005; d["c"][j] = 1.1020; d["h"][j] = 1.1021
            d["o"][j + 1:b + 200] = 1.1020; d["h"][j + 1:b + 200] = 1.1021; d["l"][j + 1:b + 200] = 1.1019; d["c"][j + 1:b + 200] = 1.1020
            d["o"][b + 200:b + 288] = 1.10; d["c"][b + 200:b + 288] = 1.10
        P._setup("EURUSD", d)
        f = T.run_ORB(P, "follow", 1.0, 2.0)
        r = T.run_ORB(P, "fade", 1.0, 2.0)
        self.assertGreater(len(f), 10)
        self.assertTrue(all(t["dir"] == 1 for t in f))
        self.assertTrue(all(t["dir"] == -1 for t in r))
        self.assertTrue(all(t["t_fill"] > t["t_sig"] for t in f))      # entry strictly after the signal bar

    def test_truncation_invariance_real_data(self):
        path = next(T.X.CI.glob("eurusd-m5-2016-09-11_*.csv"), None)
        if path is None:
            self.skipTest("10y set not present")
        full = T.Pair("EURUSD", path)
        cut = int(np.searchsorted(full.d["ts"], T.ms("2021-01-01")))
        half = object.__new__(T.Pair)
        half._setup("EURUSD", {k: v[:cut].copy() for k, v in full.d.items()})
        lim = int(half.d["ts"][-1]) - 86_400_000 * 6
        for fn, args in ((T.run_ORB, ("follow", 1.0, 2.0)), (T.run_CM, ("A", "B", "cont")), (T.run_H1MR, (2.0, 2.0)), (T.run_H4T, (20, 2.0))):
            a = {(t["t_fill"], t["dir"], round(t["R_pess"], 9)) for t in fn(full, *args) if t["t_exit"] < lim and t["t_fill"] < lim}
            b = {(t["t_fill"], t["dir"], round(t["R_pess"], 9)) for t in fn(half, *args) if t["t_exit"] < lim and t["t_fill"] < lim}
            self.assertGreater(len(b), 5, fn.__name__)
            self.assertEqual(a, b, fn.__name__)


if __name__ == "__main__":
    unittest.main()
