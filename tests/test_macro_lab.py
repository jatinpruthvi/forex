import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools import macro_lab as M  # noqa: E402

HAVE = M.T.X.CI.exists() and any(M.T.X.CI.glob("eurusd-m5-2016-09-11_*.csv")) and (M.RI / "fred_DFF.csv").exists()


class Mech(unittest.TestCase):
    def test_config_count(self):
        self.assertEqual(len(M.CONFIGS), 6 + 8)

    def test_rate_lag_and_staleness(self):
        d = np.array([M.ms("2020-01-01"), M.ms("2020-02-01")]); v = np.array([1.0, 2.0])
        self.assertTrue(np.isnan(M.rate_at(d, v, M.ms("2020-02-15"), 62, 75)))            # nothing usable yet
        self.assertEqual(M.rate_at(d, v, M.ms("2020-03-05"), 62, 75), 1.0)              # Jan value usable from Mar 3
        self.assertEqual(M.rate_at(d, v, M.ms("2020-04-05"), 62, 75), 2.0)              # Feb value usable from Apr 3
        self.assertTrue(np.isnan(M.rate_at(d, v, M.ms("2021-01-01"), 62, 75)))          # stale, not forward-filled

    def test_pct_rank_is_causal(self):
        rng = np.random.default_rng(1)
        x = rng.normal(size=400)
        full = M.pct_rank(x)
        part = M.pct_rank(x[:300])
        self.assertTrue(np.allclose(full[:300], part, equal_nan=True))
        self.assertTrue(np.isnan(full[:100]).all() and np.isfinite(full[103:]).all())
        self.assertEqual(M.pct_rank(np.arange(200.0))[150], 100.0)

    def test_month_uses_end_date(self):
        # key k labels the date the trading day STARTS (17:00 NY the day before it ends): Sunday-start day ends Monday
        import datetime as dt
        k = dt.date(2021, 2, 28).toordinal() - 719163                       # starts Sun 28 Feb 17:00, ends Mon 1 Mar
        self.assertEqual(M._month(k), (2021, 3))

    @unittest.skipUnless(HAVE, "needs 10y data and macro inputs")
    def test_carry_accrual_sign_and_cot_timing(self):
        tr = M.trades_for("CARRY_sign_th0")
        self.assertGreater(len(tr), 500)
        for t in tr[:400]:
            self.assertEqual(np.sign(t["acc_gross_R"]), np.sign(t["side"] * t["carry"]) if t["carry"] else 0)
            self.assertEqual(t["side"], int(np.sign(t["carry"])))
        ct = M.trades_for("COT_lev_contra_80")
        self.assertGreater(len(ct), 500)
        for t in ct:
            # published Friday 15:30 NY = Tuesday as-of + 3 days + 20.5h UTC at the earliest; never trade before it
            self.assertGreater(t["t_fill"], (t["asof"] - 719163 + 4) * 86_400_000)
            self.assertGreater(t["t_fill"], t["t_sig"])

    @unittest.skipUnless(HAVE, "needs 10y data and macro inputs")
    def test_carry_truncation_invariance(self):
        full = {c: M.T.pairs("ci")[p] for c, (p, _) in M.CCY.items()}
        cut_ms = M.ms("2021-01-01")
        half = {}
        for c, P in full.items():
            cut = int(np.searchsorted(P.d["ts"], cut_ms))
            Q = object.__new__(M.T.Pair)
            Q._setup(P.sym, {k: v[:cut].copy() for k, v in P.d.items()})
            half[c] = Q
        lim = cut_ms - 45 * 86_400_000
        rates = M.Rates()
        for mode in ("sign", "xs", "signtr"):
            a = {(t["sym"], t["t_fill"], t["dir"], round(t["R_pess"], 9)) for t in M.run_CARRY(mode, 0.0, rates, full) if t["t_exit"] < lim}
            b = {(t["sym"], t["t_fill"], t["dir"], round(t["R_pess"], 9)) for t in M.run_CARRY(mode, 0.0, rates, half) if t["t_exit"] < lim}
            self.assertGreater(len(b), 100, mode)
            self.assertEqual(a, b, mode)


if __name__ == "__main__":
    unittest.main()
