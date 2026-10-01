"""Mechanics tests for tools/exhaustion_oos_lab.py (frozen exhaustion-fade re-implementation). Not evidence of an edge."""
from __future__ import annotations

import unittest

try:
    import numpy as np
    from tools import exhaustion_oos_lab as X
except ModuleNotFoundError:
    np = None
    X = None


def series(bars):
    a = np.array(bars, float)
    n = len(a)
    return dict(ts=np.arange(n, dtype=np.int64) * 300_000, o=a[:, 0], h=a[:, 1], l=a[:, 2], c=a[:, 3])


@unittest.skipIf(X is None, "numpy not available")
class ResolveTests(unittest.TestCase):
    # signal bar index 0, entry 100.0 on bar 1, stop 99.0 (dist 1), target 110.0
    def run_bars(self, later):
        d = series([(100.5, 100.6, 99.5, 99.6), (100.0, 100.2, 99.9, 100.1)] + later)
        return X.resolve(d, 0, 100.0, 99.0, 1.0)

    def test_target(self):
        r_repo, r_strict, j = self.run_bars([(100.1, 110.5, 100.0, 110.0)])
        self.assertEqual((r_repo, r_strict, j), (10.0, 10.0, 2))

    def test_stop_and_tie_go_to_stop(self):
        r_repo, r_strict, j = self.run_bars([(100.1, 110.5, 98.9, 100.0)])        # same bar touches both
        self.assertEqual((r_repo, j), (-1.0, 2))
        self.assertAlmostEqual(r_strict, -1.0)                                     # opens above the stop: fills at the stop

    def test_gap_through_stop_is_worse_in_strict_rule(self):
        r_repo, r_strict, _ = self.run_bars([(98.0, 98.5, 97.5, 98.2)])           # opens 1R below the stop
        self.assertEqual(r_repo, -1.0)
        self.assertAlmostEqual(r_strict, -2.0)

    def test_touch_exactly_on_stop_counts_as_stop(self):
        r_repo, _, _ = self.run_bars([(100.0, 100.3, 99.0, 100.0)])
        self.assertEqual(r_repo, -1.0)

    def test_timeout_closes_at_market(self):
        n_later = X.HOLD_BARS + 5
        r_repo, r_strict, j = self.run_bars([(100.2, 100.4, 100.0, 100.3)] * n_later)
        self.assertEqual(j, X.HOLD_BARS)
        self.assertAlmostEqual(r_repo, 0.3)
        self.assertEqual(r_repo, r_strict)


@unittest.skipIf(X is None, "numpy not available")
class SignalTests(unittest.TestCase):
    def test_only_large_down_bars_are_signals_and_atr_uses_prior_bars(self):
        bars = [(1.1000, 1.1001, 1.0999, 1.1000)] * 30                             # ATR ~ 2e-4 (TR of each bar)
        bars += [(1.1000, 1.1001, 1.0940, 1.0945)]                                 # big DOWN bar, body 55e-4 >> 4 ATR
        bars += [(1.0945, 1.0960, 1.0944, 1.0955)] + [(1.0955, 1.0957, 1.0953, 1.0956)] * 20
        bars_up = [(1.1000, 1.1001, 1.0999, 1.1000)] * 30 + [(1.1000, 1.1060, 1.0999, 1.1055)] + [(1.1055, 1.1056, 1.1050, 1.1052)] * 20
        down = X.signals("EURUSD", series(bars))
        up = X.signals("EURUSD", series(bars_up))
        self.assertEqual([t["i"] for t in down], [30])
        self.assertEqual(up, [])                                                   # long only: rallies are ignored
        self.assertGreater(down[0]["dist"], down[0]["atr"])                        # min-stop guard satisfied


@unittest.skipUnless(X is not None and X.files("tracked")["EURUSD"].exists(), "tracked data not available")
class ReproTests(unittest.TestCase):
    def test_matches_repo_verifier_trade_for_trade_on_one_pair(self):
        s = "EURGBP"
        lo = X.V.TRAIN_END
        mine = [t for t in X.signals(s, X.load(s, X.files("tracked")[s])) if t["t_sig"] >= lo]
        ref = [t for t in X.V.build(s) if t.ets >= lo]
        self.assertEqual(len(mine), len(ref))
        for a, b in zip(mine, ref):
            self.assertEqual(a["t_sig"], b.ets)
            self.assertAlmostEqual(a["R_repo"], b.R, places=9)
            self.assertLessEqual(a["R_strict"], a["R_repo"] + 1e-12)


if __name__ == "__main__":
    unittest.main()
