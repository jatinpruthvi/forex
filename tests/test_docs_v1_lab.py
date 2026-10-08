"""Regression tests for tools/docs_v1_lab.py (the docs_v1 validation simulator).

These prove MECHANICS only (fills, exits, ordering bounds, no look-ahead, mirror symmetry, account rules).
They never show that any strategy has an edge.
"""
from __future__ import annotations

import unittest
from datetime import datetime, timezone
from pathlib import Path

try:
    import numpy as np
    from tools import docs_v1_lab as L
except ModuleNotFoundError:            # numpy is not installed in the bare system interpreter
    np = None
    L = None

DATA_OK = L is not None and (L.DATA_DIR / "eurusd-m5-2022-09-11_2026-09-11.csv").exists()


def frame(bars):
    """bars: list of (o,h,l,c) -> long-frame dict as consumed by sim_leg (no H1 swings)."""
    a = np.array(bars, float)
    n = len(a)
    return dict(O=a[:, 0], H=a[:, 1], L=a[:, 2], C=a[:, 3], ts=np.arange(n, dtype=np.int64) * 300_000,
                sw=dict(t=np.zeros(0, np.int64), conf=np.zeros(0, np.int64), p=np.zeros(0)))


def leg(bars, spec, mode, pool=float("nan"), entry=100.0, stop=99.0, dead=0):
    fr = frame(bars)
    return L.sim_leg(fr, entry, stop, 0, L.EXITS[spec] if isinstance(spec, str) else spec, pool, 0.5, mode, dead, 10_000)


FILL = (100.2, 100.5, 99.9, 100.3)      # limit at 100.0 fills here; stop 99.0


@unittest.skipIf(L is None, "numpy not available")
class ExecutionTests(unittest.TestCase):
    def test_single_target_win_and_loss(self):
        R, j = leg([FILL, (100.3, 103.2, 100.1, 103.0)], "RR3", "pess")
        self.assertAlmostEqual(R, 3.0); self.assertEqual(j, 1)
        R, j = leg([FILL, (100.3, 100.4, 98.9, 99.0)], "RR3", "pess")
        self.assertAlmostEqual(R, -1.0)

    def test_gap_through_stop_fills_at_open(self):
        R, _ = leg([FILL, (98.5, 98.8, 98.4, 98.6)], "RR3", "pess")
        self.assertAlmostEqual(R, -1.5)

    def test_fill_bar_cannot_prove_target_in_pessimistic_mode(self):
        big_fill = (100.2, 103.5, 99.9, 100.3)
        tail = [(100.2, 100.6, 100.0, 100.4)] * 3
        Rp, _ = leg([big_fill] + tail, "RR3", "pess")
        Ro, _ = leg([big_fill] + tail, "RR3", "opt")
        self.assertAlmostEqual(Rp, 0.4)          # rides to the end of data at the last close
        self.assertAlmostEqual(Ro, 3.0)

    def test_same_bar_stop_and_target_ordering_bounds(self):
        amb = (100.3, 101.6, 98.9, 101.0)        # touches stop 99.0 AND the 1.5R target
        after = (101.0, 103.2, 100.6, 103.0)
        spec = dict(targets=[(1.5, .5, 0.0), (3.0, .5, None)], runner=None)
        Rp, _ = leg([FILL, amb, after], spec, "pess")
        Ro, _ = leg([FILL, amb, after], spec, "opt")
        self.assertAlmostEqual(Rp, -1.0)         # stop wins the tie
        self.assertAlmostEqual(Ro, 0.5 * 1.5 + 0.5 * 3.0)
        self.assertLess(Rp, Ro)

    def test_breakeven_stop_applies_to_the_same_bar_in_pessimistic_mode(self):
        spec = dict(targets=[(1.5, .5, 0.0), (3.0, .5, None)], runner=None)
        bar = (100.3, 101.6, 99.95, 100.9)       # target hit, then trades back through the new BE stop
        R, j = leg([FILL, bar, (100.9, 103.2, 100.5, 103.0)], spec, "pess")
        self.assertAlmostEqual(R, 0.75)          # half banked at 1.5R, rest stopped at 0
        self.assertEqual(j, 1)
        Ro, _ = leg([FILL, bar, (100.9, 103.2, 100.5, 103.0)], spec, "opt")
        self.assertAlmostEqual(Ro, 0.75 + 1.5)

    def test_x1_ladder_full_run_and_pool_target(self):
        # pool at 105 => 5R; ladder 25/25/25 then h1 runner absent (no swings) -> runner rides to end-of-data close
        bars = [FILL, (100.3, 101.6, 100.4, 101.5), (101.5, 103.1, 101.1, 103.0), (103.0, 105.2, 102.9, 105.0),
                (105.0, 105.1, 104.9, 105.0)]
        R, _ = leg(bars, "X1", "pess", pool=105.0)
        self.assertAlmostEqual(R, .25 * 1.5 + .25 * 3.0 + .25 * 5.0 + .25 * 5.0)

    def test_tie_break_conventions_are_not_monotone_so_bounds_use_min_max(self):
        spec = dict(targets=[(1.5, .5, 0.3), (3.0, .5, None)], runner=None)
        bars = [(100.2, 101.6, 99.9, 100.3), (100.2, 101.0, 100.1, 100.9), (101.0, 103.2, 100.5, 103.0)]
        Rp, _ = leg(bars, spec, "pess")
        Ro, _ = leg(bars, spec, "opt")
        # optimistic banks 1.5R on the fill bar, then the +0.3R ratchet stops the rest at the gap open: it ends LOWER
        self.assertGreater(Rp, Ro)

    def test_target_resolution(self):
        tg = L._resolve_targets(L.EXITS["X1"], 100.0, 1.0, 105.0)
        self.assertEqual([round(t[0], 2) for t in tg], [1.5, 3.0, 5.0])
        tg = L._resolve_targets(L.EXITS["X1"], 100.0, 1.0, float("nan"))
        self.assertEqual([round(t[0], 2) for t in tg], [1.5, 3.0, 4.5])
        tg = L._resolve_targets(L.EXITS["X1"], 100.0, 1.0, 100.5)     # pool nearer than the ladder -> +0.5R steps
        self.assertEqual([round(t[0], 2) for t in tg], [1.5, 3.0, 3.5])
        tg = L._resolve_targets(L.EXITS["X2"], 100.0, 1.0, 130.0)     # capped at 10R
        self.assertEqual(tg[1][0], 10.0)

    def test_dead_money_exit(self):
        stall = [(100.2, 100.4, 100.05, 100.2)] * 6
        R, j = leg([FILL] + stall, "RR3", "pess", dead=3)
        self.assertEqual(j, 3)
        self.assertAlmostEqual(R, 0.2)           # closed at the close of bar 3: 100.2 vs entry 100

    def test_leg_plan_rejects_limit_above_market_and_weights(self):
        cfg = L.Cfg("t", "E1", entry="dual", min_stop_pips=0)
        ev = dict(z_lo=99.0, z_hi=100.0, atr=1.0, kind="ob")
        stop, legs = L.leg_plan(ev, cfg, 100.5)
        self.assertAlmostEqual(stop, 98.75)
        self.assertEqual(legs, [(100.0, .5), (99.5, .5)])
        stop, legs = L.leg_plan(ev, cfg, 99.8)            # market already below the front edge -> one placeable leg
        self.assertEqual(legs, [(99.5, 1.0)])
        self.assertIsNone(L.leg_plan(ev, cfg, 99.0))


@unittest.skipIf(L is None, "numpy not available")
class UtilityTests(unittest.TestCase):
    def test_frame_mirror(self):
        d = dict(o=np.array([1.0]), h=np.array([3.0]), l=np.array([0.5]), c=np.array([2.0]))
        o, h, l, c = L._frame(d, -1)
        self.assertEqual((o[0], h[0], l[0], c[0]), (-1.0, -0.5, -3.0, -2.0))

    def test_fractals_need_two_bars_each_side(self):
        h = np.array([1, 2, 5, 2, 1, 1, 1.0]); l = h - 0.5
        sh, _ = L.fractals(h, l, 2)
        self.assertEqual(list(np.flatnonzero(sh)), [2])
        self.assertFalse(L.fractals(h[:4], l[:4], 2)[0].any())      # not confirmable with only 1 later bar

    def test_ny_day_bucket_is_dst_aware(self):
        def b(y, m, d, hh, mm):
            return int(datetime(y, m, d, hh, mm, tzinfo=timezone.utc).timestamp() * 1000)
        w = L._ny_bucket(np.array([b(2024, 1, 15, 21, 55), b(2024, 1, 15, 22, 0)]))     # EST: 17:00 = 22:00Z
        self.assertEqual(w[1] - w[0], 1)
        s = L._ny_bucket(np.array([b(2024, 7, 15, 20, 55), b(2024, 7, 15, 21, 0)]))     # EDT: 17:00 = 21:00Z
        self.assertEqual(s[1] - s[0], 1)

    def test_costs_are_charged(self):
        t = [dict(R_pess=1.0, R_opt=1.0, cost=0.1, cost15=0.15)]
        self.assertAlmostEqual(L.net_R(t)[0], 0.9)
        self.assertAlmostEqual(L.net_R(t, "pess", 1.5)[0], 0.85)

    def test_bootstrap_lower_bound_sign(self):
        rng = np.random.default_rng(1)
        base = int(datetime(2025, 1, 6, 8, tzinfo=timezone.utc).timestamp() * 1000)
        mk = lambda mu: [dict(R_pess=float(r), R_opt=float(r), cost=0.0, cost15=0.0, sym="EURUSD",
                              t_fill=base + i * 86_400_000) for i, r in enumerate(rng.normal(mu, 1.0, 400))]
        self.assertGreater(L.bootstrap_lb(mk(0.5), B=2000), 0)
        self.assertLess(L.bootstrap_lb(mk(0.0), B=2000), 0.15)

    def test_candidate_rule(self):
        ok = dict(n=130, pf=1.2, exp=0.05, halves=[0.1, 0.02])
        self.assertTrue(L.is_candidate(ok))
        self.assertFalse(L.is_candidate({**ok, "n": 119}))
        self.assertFalse(L.is_candidate({**ok, "pf": 1.1}))
        self.assertFalse(L.is_candidate({**ok, "halves": [0.1, -0.01]}))

    def test_registry_respects_budget_and_pre_registered_stage_a(self):
        self.assertLessEqual(len(L.CONFIGS), 44)
        a = [n for n in L.CONFIGS if n.startswith("A")]
        self.assertEqual(len(a), 6)
        self.assertEqual(L.CONFIGS["A1_E1_X1"].min_stop_pips, 25.0)     # docs as written: floor on


@unittest.skipIf(L is None, "numpy not available")
class AccountTests(unittest.TestCase):
    T0 = int(datetime(2025, 3, 3, 8, tzinfo=timezone.utc).timestamp() * 1000)

    def tr(self, sym, i, dur, net, day=0):
        f = self.T0 + day * 86_400_000 + i * 60_000
        return dict(sym=sym, R_pess=net, R_opt=net, cost=0.0, cost15=0.0, t_fill=f, t_exit=f + dur * 60_000,
                    t_exit_opt=f + dur * 60_000, risk=0.005)

    def test_sequential_compounding(self):
        a = L.account_sim([self.tr("EURUSD", 0, 10, 1.0), self.tr("EURUSD", 100, 10, -1.0)])
        self.assertAlmostEqual(a["final_pct"], 100 * (1.005 * 0.995 - 1), places=6)
        self.assertEqual(a["n_taken"], 2)

    def test_concurrency_cap_and_one_per_symbol(self):
        syms = ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "NZDUSD"]
        a = L.account_sim([self.tr(s, i, 600, 0.5) for i, s in enumerate(syms)])
        self.assertEqual(a["n_taken"], 4)
        b = L.account_sim([self.tr("EURUSD", 0, 600, 0.5), self.tr("EURUSD", 5, 600, 0.5)])
        self.assertEqual(b["n_taken"], 1)
        c = L.account_sim([self.tr(s, i, 600, 0.5) for i, s in enumerate(syms)], max_conc=1)
        self.assertEqual(c["n_taken"], 1)

    def test_daily_halt_and_floor(self):
        losers = [self.tr("EURUSD", 0, 5, -5.0), self.tr("GBPUSD", 60, 5, -1.0), self.tr("USDJPY", 90, 5, -1.0)]
        a = L.account_sim(losers)                    # -2.5% on the first trade halts the day
        self.assertEqual(a["n_taken"], 1)
        self.assertAlmostEqual(a["worst_day_pct"], -2.5, places=6)
        many = [self.tr("EURUSD", 10 * d, 5, -5.0, day=d) for d in range(12)]
        b = L.account_sim(many)
        self.assertTrue(b["floor_breach"])
        self.assertLess(b["n_taken"], 12)            # trading stops after the floor is breached


@unittest.skipUnless(DATA_OK, "tracked M5 data not available")
class DataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        m5 = L.load_m5("EURUSD")
        # cut at the first H4-aligned bar >= 120 days in and a 45-day sample window (keeps runtime small)
        lo = int(np.searchsorted(m5["ts"], m5["ts"][0] + 200 * 86_400_000))
        cls.full = {k: v[lo:lo + 12_000 * 3] for k, v in m5.items()}
        h4 = (cls.full["ts"] % 14_400_000 == 0)
        cls.cut = int(np.flatnonzero(h4)[np.flatnonzero(h4) > 12_000][0])
        cls.trunc = {k: v[:cls.cut] for k, v in cls.full.items()}

    def _events(self, m5, cfg):
        b = L.bars_from_m5("EURUSD", m5, cfg.sig_tf)
        return b, L.detect_setups(b, cfg, 0, 2 ** 62)

    def test_no_lookahead_truncating_the_future_changes_nothing(self):
        for cfg in (L.Cfg("a", "E1", min_stop_pips=0), L.Cfg("b", "E1", sig_tf=60, min_stop_pips=0),
                    L.Cfg("c", "E3", min_stop_pips=0), L.Cfg("d", "E2", sessions=((420, 600),), min_stop_pips=0)):
            bf, ef = self._events(self.full, cfg)
            bt, et = self._events(self.trunc, cfg)
            n_t = len(bt.sig["ts"])
            key = lambda e: (e["t"], e["k"], e["dir"], round(e["z_lo"], 8), round(e["z_hi"], 8), round(e["atr"], 8))
            full_early = sorted(key(e) for e in ef if e["t"] < n_t - 1)
            trunc_all = sorted(key(e) for e in et if e["t"] < n_t - 1)
            self.assertEqual(full_early, trunc_all, cfg.name)
            self.assertGreater(len(full_early), 0, f"{cfg.name}: sample produced no events, test is vacuous")

    def test_bias_uses_only_completed_h4_bars(self):
        b = L.bars_from_m5("EURUSD", self.full, 15)
        h4_close = b.h4["ts"] + L.MS_H4
        close_sig = b.sig["ts"] + b.bar_ms
        for i in range(2000, 2000 + 50):
            hb = L.h4_bias(b.h4)
            done = np.flatnonzero(h4_close <= close_sig[i])
            self.assertEqual(b.bias[i], hb[done[-1]])

    def test_mirror_symmetry(self):
        mir = dict(self.full)
        mir.update(o=-self.full["o"], h=-self.full["l"], l=-self.full["h"], c=-self.full["c"])
        # bias off: the EA's H4 bias checks the bullish rule first, so it is intentionally not mirror-symmetric
        cfg = L.Cfg("m", "E1", min_stop_pips=0, bias_on=False)
        _, e0 = self._events(self.full, cfg)
        _, e1 = self._events(mir, cfg)
        k = lambda e: (e["t"], e["k"], e["dir"])
        a = sorted((e["t"], e["k"], e["dir"]) for e in e0)
        b = sorted((e["t"], e["k"], -e["dir"]) for e in e1)
        self.assertEqual(a, b)

    def test_trades_are_retouched_and_time_ordered(self):
        cfg = L.Cfg("r", "E1", sig_tf=15, min_stop_pips=0)
        b = L.bars_from_m5("EURUSD", self.full, 15)
        tr = L.run_symbol(b, cfg, 0, 2 ** 62)
        self.assertGreater(len(tr), 5)
        for t in tr:
            self.assertGreater(t["t_fill"], t["t_sig"] - 1)             # never filled before the signal bar closed
            self.assertGreaterEqual(t["t_exit"], t["t_fill"])
        for a, c in zip(tr, tr[1:]):                                    # one position per symbol at a time
            self.assertGreaterEqual(c["t_fill"], a["t_exit"])
            self.assertLessEqual(a["R_pess"], a["R_opt"] + 1e-9)

    def test_rank_book_is_flat_over_weekends(self):
        from zoneinfo import ZoneInfo
        ny = ZoneInfo("America/New_York")
        cfg = L.CONFIGS["A5_E4_mom20"]
        tr = L.run_rank(cfg, L.ms("2023-01-02"), L.ms("2023-04-01"))
        self.assertGreater(len(tr), 10)
        for t in tr:
            f = datetime.fromtimestamp(t["t_fill"] / 1000, ny)
            x = datetime.fromtimestamp(t["t_exit"] / 1000, ny)
            self.assertLess(f.weekday(), 4 if f.hour >= 17 else 5)      # no fill after Friday 17:00
            self.assertLess((x - f).days, 5)
            self.assertFalse(x.weekday() == 5)
            self.assertFalse(x.weekday() == 4 and x.hour >= 17 and x.minute > 5)


if __name__ == "__main__":
    unittest.main()
