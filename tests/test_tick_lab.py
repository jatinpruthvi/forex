import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools import tick_lab as K  # noqa: E402

MIN = K.MIN


def synth(n=600, bid=1.1000, spr=0.0002):
    ts = 1_700_000_000_000 // MIN * MIN + np.arange(n) * MIN
    b = np.full(n, bid)
    return dict(ts=ts, bid_o=b.copy(), bid_h=b + 0.0001, bid_l=b - 0.0001, bid_c=b.copy(),
                ask_o=b + spr, ask_h=b + spr + 0.0001, ask_l=b + spr - 0.0001, ask_c=b + spr,
                spr_mean=np.full(n, spr), spr_max=np.full(n, spr), spr_min=np.full(n, spr))


class Exec(unittest.TestCase):
    def test_long_enters_at_ask_and_stops_on_bid(self):
        m = synth()
        m["bid_l"][50] = 1.0890                                     # bid dips through the stop at 1.0900 (ask never gets there first)
        e, x, tx, kind = K.execute_long(m, int(m["ts"][10]), stop=1.0900, target=1.1500, hold_min=300)
        self.assertAlmostEqual(e, 1.1002)                           # paid the ask
        self.assertEqual(kind, "stop")
        self.assertAlmostEqual(x, 1.0900)
        self.assertEqual(tx, int(m["ts"][50]))

    def test_stop_gap_fills_at_bid_open(self):
        m = synth()
        m["bid_o"][50:] = 1.0800; m["bid_l"][50:] = 1.0795; m["bid_h"][50:] = 1.0805; m["bid_c"][50:] = 1.0800
        _, x, _, kind = K.execute_long(m, int(m["ts"][10]), stop=1.0900, target=1.1500, hold_min=300)
        self.assertEqual(kind, "stop"); self.assertAlmostEqual(x, 1.0800)

    def test_target_needs_bid_high_not_ask(self):
        m = synth()
        m["ask_h"][40] = 1.1500                                     # only the ASK reached the target: a long's sell limit does not fill
        r = K.execute_long(m, int(m["ts"][10]), stop=1.0500, target=1.1500, hold_min=100)
        self.assertEqual(r[3], "time")
        m["bid_h"][40] = 1.1500
        self.assertEqual(K.execute_long(m, int(m["ts"][10]), stop=1.0500, target=1.1500, hold_min=100)[3], "target")

    def test_tie_goes_to_stop_and_delay_uses_later_minute(self):
        m = synth()
        m["bid_l"][30] = 1.0500; m["bid_h"][30] = 1.1500
        self.assertEqual(K.execute_long(m, int(m["ts"][10]), 1.0600, 1.1400, 100)[3], "stop")
        m2 = synth(); m2["ask_o"][13] = 1.1050
        self.assertAlmostEqual(K.execute_long(m2, int(m2["ts"][10]), 1.0, 2.0, 50, delay_min=3)[0], 1.1050)

    def test_feed_clock_follows_european_dst(self):
        import pandas as pd
        s = lambda t: int(pd.Timestamp(t).timestamp())          # the feed stamps its own wall clock as if it were UTC
        u = lambda t: int(pd.Timestamp(t, tz="UTC").timestamp() * 1000)
        out = K.feed_to_utc_ms(np.array([s("2025-07-01 17:00"), s("2025-12-01 17:00"),
                                        s("2026-03-20 17:00"),      # US already on summer time, Europe not yet: the feed is still UTC-5
                                        s("2025-10-30 17:00")]))    # US still on summer time, Europe already off it: UTC-5
        self.assertEqual(list(out), [u("2025-07-01 21:00"), u("2025-12-01 22:00"), u("2026-03-20 22:00"), u("2025-10-30 22:00")])


@unittest.skipUnless((K.RI).exists() and K.X.CI.exists(), "needs tick minutes and 10y M5")
class Real(unittest.TestCase):
    def test_feed_clock_matches_dukascopy_m5(self):
        m = K.load_minutes("EURUSD")
        d = K.X.load("EURUSD", K.X.files("ci")["EURUSD"])
        b5 = m["ts"] // 300_000 * 300_000
        last = {}
        for t, c in zip(b5, m["bid_c"]):
            last[int(t)] = c
        idx = np.searchsorted(d["ts"], list(last))
        ok = [(i < len(d["ts"]) and d["ts"][i] == t) for i, t in zip(idx, last)]
        ours = np.array([last[t] for t, o in zip(last, ok) if o]); ref = np.array([d["c"][i] for i, o in zip(idx, ok) if o])
        self.assertGreater(len(ours), 50_000)
        self.assertGreater((np.abs(ours - ref) < 0.00006).mean(), 0.97)      # minor mismatches exist around DST weeks and quote-source differences


if __name__ == "__main__":
    unittest.main()
