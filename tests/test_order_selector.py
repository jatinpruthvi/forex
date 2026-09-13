"""
Tests for tools/order_selector.py (Combo Lab: best-order selection under
one shared slot).

Synthetic M5 fixtures drive the full run_combo pipeline (stubbed triad
detector) plus unit tests for the gold-leg port (equivalence with
swing_lab.run_donchian), no-look-ahead, walk-forward stats and policy
rules. No repo data files are required.
"""
import os
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, os.path.abspath("."))
sys.path.insert(0, os.path.abspath("tools"))

import tools.aggressive_optimizer as m   # noqa: E402
import tools.swing_lab as sl             # noqa: E402
import tools.triad_honest as th          # noqa: E402
import tools.order_selector as osel      # noqa: E402

import unittest  # noqa: E402

# ---------------------------------------------------------------------------
# Synthetic fixture: 82 consecutive days (incl. weekends, gold trades them).
#
# XAUUSD daily shape (base rises $2/day -> 55-day channel breaks daily from
# day index 56; base drops $8/day on the last 3 days -> chandelier stop):
#   00:00-07:00 flat base | 07:00-07:30 dip to base-0.5
#   07:30-11:00 rise to base+0.2 | 11:00-17:00 flat base+0.2
#
# GBPJPY / EURJPY (weekdays only, London window) — one dip for the 07:05
# signal (GBPJPY) and a second dip for the 10:05 signal (EURJPY):
#   00:00-07:00 base | 07:00-07:30 base->base-s | 07:30-09:00 ->base+1.2s
#   09:00-10:00 ->base+1.0s | 10:00-10:30 ->base-0.4s | 10:30-11:00 ->base+0.2s
#   11:00-17:00 flat base+0.2s
#
# Stubbed triad detector: long limit at level-0.3s, stop level-1.2s
# (stop below the dip low -> never hit; target/exit via the recovery).
# ---------------------------------------------------------------------------
START = date(2025, 1, 6)                 # a Monday
N_DAYS = 82
LEVELS = {"GBPJPY": 190.0, "EURJPY": 170.0}
SCALES = {"GBPJPY": 0.05, "EURJPY": 0.05}
GOLD_START = 2000.0


def _d(i):
    return START + timedelta(days=i)


def _gold_base(i):
    if i >= N_DAYS - 3:
        return GOLD_START + 2 * (N_DAYS - 3) - 8 * (i - (N_DAYS - 3))
    return GOLD_START + 2 * i


def _london_price(d, minute, level, s):
    """minute = minutes after 00:00 London wall time."""
    if minute < 7 * 60:
        return level
    if minute < 7 * 60 + 30:
        f = (minute - 7 * 60) / 30.0
        return level - s * f
    if minute < 9 * 60:
        f = (minute - (7 * 60 + 30)) / 90.0
        return level - s + (level + 1.2 * s - (level - s)) * f
    if minute < 10 * 60:
        f = (minute - 9 * 60) / 60.0
        return (level + 1.2 * s) + ((level + 1.0 * s) - (level + 1.2 * s)) * f
    if minute < 10 * 60 + 30:
        f = (minute - 10 * 60) / 30.0
        return (level + 1.0 * s) + ((level - 0.4 * s) - (level + 1.0 * s)) * f
    if minute < 11 * 60:
        f = (minute - (10 * 60 + 30)) / 30.0
        return (level - 0.4 * s) + ((level + 0.2 * s) - (level - 0.4 * s)) * f
    return level + 0.2 * s


def _gold_price(d, minute, base):
    if minute < 7 * 60:
        return base
    if minute < 7 * 60 + 30:
        f = (minute - 7 * 60) / 30.0
        return base - 0.5 * f
    if minute < 11 * 60:
        f = (minute - (7 * 60 + 30)) / (4 * 60)
        return (base - 0.5) + ((base + 0.2) - (base - 0.5)) * f
    return base + 0.2


def _bars_for_day(d, symbol):
    bars = []
    for minute in range(0, 17 * 60, 5):
        ts = m.lw_utc(d, minute // 60, minute % 60)
        if symbol == "XAUUSD":
            p0 = _gold_price(d, minute, _gold_base(_idx(d)))
            p1 = _gold_price(d, minute + 5, _gold_base(_idx(d)))
        else:
            p0 = _london_price(d, minute, LEVELS[symbol], SCALES[symbol])
            p1 = _london_price(d, minute + 5, LEVELS[symbol], SCALES[symbol])
        eps = 0.05 * (SCALES.get(symbol, 1.0))
        bars.append(m.Bar(ts, p0, max(p0, p1) + eps, min(p0, p1) - eps, p1))
    return bars


def _idx(d):
    return (d - START).days


def make_cache():
    """cache: {SYM: (by_date, atr_map)} — XAUUSD all days, FX weekdays.
    atr_map is a placeholder (the stubbed detector ignores its value, but
    build_day_candidates requires atr > 0 to run)."""
    cache = {}
    for sym in ("GBPJPY", "EURJPY", "XAUUSD"):
        by_date = {}
        for i in range(N_DAYS):
            d = _d(i)
            if sym != "XAUUSD" and d.weekday() >= 5:
                continue
            by_date[d] = _bars_for_day(d, sym)
        atr_map = {d: 1.0 for d in by_date}
        cache[sym] = (by_date, atr_map)
    return cache


def make_gold_cache():
    return {s: v for s, v in make_cache().items() if s == "XAUUSD"}


def fake_detect(day_bars, ref_s, ref_e, ent_s, ent_e, atr, sym,
                disp_max=2, ref_override=None, stop_buffer=None,
                sweep_min=None):
    # signature mirrors th.detect's additive kwargs (per-pair strategy
    # fit); the stub ignores them — it exists to isolate slot-policy logic.
    if sym == "XAUUSD":
        # far below the flat NY-session price -> never re-touched (unfilled)
        return dict(side="long", entry=1999.7, stop=1998.5,
                    sig_ts=ent_s + timedelta(minutes=5), extreme=1999.5,
                    body_ratio=0.7, wick_ratio=0.7, sweep_atr=0.2)
    s = SCALES[sym]
    level = LEVELS[sym]
    dt = 5 if sym == "GBPJPY" else 195
    return dict(side="long", entry=level - 0.3 * s, stop=level - 1.2 * s,
                sig_ts=ent_s + timedelta(minutes=dt),
                extreme=level - s, body_ratio=0.7, wick_ratio=0.7,
                sweep_atr=0.2)


def run_policy(policy, theta=0.0, **kw):
    osel.PRECOMPUTE_CACHE.clear()
    cache = make_cache()
    real_detect = osel.th.detect
    osel.th.detect = fake_detect
    try:
        return osel.run_combo(cache, policy, theta=theta,
                              ambiguity="coin", **kw)
    finally:
        osel.th.detect = real_detect


def triad_trades(r, day):
    return [t for t in r["trades"] if "entry_date" not in t and t["date"] == day]


def gold_trades(r):
    return [t for t in r["trades"] if "entry_date" in t]


class TestGoldLegPort(unittest.TestCase):
    """GoldLeg must reproduce swing_lab.run_donchian exactly."""

    def test_equivalence_on_synthetic_data(self):
        cache = make_gold_cache()
        ref = sl.run_donchian(cache, ["XAUUSD"], osel.GOLD_N, osel.GOLD_K,
                              risk_frac=0.02)
        got = osel.GoldLeg(cache).standalone(0.02)
        ref_r = [t["r"] for t in ref["trades"]]
        got_r = [t["r"] for t in got]
        self.assertEqual(len(ref_r), len(got_r))
        for a, b in zip(ref_r, got_r):
            self.assertAlmostEqual(a, b, places=12)
        self.assertGreater(len(got_r), 0)   # the fixture produces trades

    def test_open_action_no_lookahead_flat(self):
        # open_action at day D uses only data through D-1: mutate D and
        # later bars -> same action.
        D = _d(70)
        cache_a = make_gold_cache()
        cache_b = make_gold_cache()
        # corrupt day D's close (and everything after) in cache_b
        for d in sorted(dd for dd in cache_b["XAUUSD"][0] if dd >= D):
            for b in cache_b["XAUUSD"][0][d]:
                b.close = b.close * 1.5
                b.high = b.high * 1.5
        la, lb = osel.GoldLeg(cache_a), osel.GoldLeg(cache_b)
        self.assertEqual(la.open_action(D, None), lb.open_action(D, None))

    def test_open_action_no_lookahead_in_position(self):
        D = _d(70)
        cache_a = make_gold_cache()
        cache_b = make_gold_cache()
        for d in sorted(dd for dd in cache_b["XAUUSD"][0] if dd >= D):
            for b in cache_b["XAUUSD"][0][d]:
                b.close = b.close * 1.5
                b.high = b.high * 1.5
        la, lb = osel.GoldLeg(cache_a), osel.GoldLeg(cache_b)
        pos = dict(side="long", entry=2100.0, stop0=2050.0, atr=20.0,
                   extreme=2110.0, entry_date=_d(60))
        self.assertEqual(la.open_action(D, pos), lb.open_action(D, dict(
            side="long", entry=2100.0, stop0=2050.0, atr=20.0,
            extreme=2110.0, entry_date=_d(60))))


class TestPolicyRules(unittest.TestCase):
    def _cand(self, **kw):
        base = dict(leg="triad", sym="GBPJPY", side="long",
                    sig_ts=datetime(2025, 3, 3, 8, 0, tzinfo=timezone.utc),
                    entry=100.0, stop=98.0, rr=1.5, prio=1,
                    day=date(2025, 3, 3))
        base.update(kw)
        return osel.Cand(**base)

    def test_p0_always_takes(self):
        e_tr, e_go = osel.LegStats(0.1), osel.LegStats(0.3)
        self.assertTrue(osel._decide("P0", self._cand(), 0.99, e_tr, e_go,
                                     None, [], []))

    def test_p1_bar(self):
        e_tr, e_go = osel.LegStats(0.1), osel.LegStats(0.3)
        s = osel.score_of(self._cand(), e_tr, e_go, [])
        self.assertTrue(osel._decide("P1", self._cand(), s * 0.5,
                                     e_tr, e_go, None, [], []))
        self.assertFalse(osel._decide("P1", self._cand(), s * 1.5,
                                      e_tr, e_go, None, [], []))

    def test_p3_never_takes_weaker_than_passed(self):
        e_tr, e_go = osel.LegStats(0.1), osel.LegStats(0.3)
        s = osel.score_of(self._cand(), e_tr, e_go, [])
        self.assertTrue(osel._decide("P3", self._cand(), 0.0, e_tr, e_go,
                                     s * 0.5, [], []))
        self.assertFalse(osel._decide("P3", self._cand(), 0.0, e_tr, e_go,
                                      s * 1.5, [], []))

    def test_negative_expectancy_scores_zero(self):
        e_tr, e_go = osel.LegStats(0.0), osel.LegStats(0.0)
        for i in range(6):            # min sample 5 -> expanding mean used
            e_tr.add(-0.5)
        self.assertEqual(osel.score_of(self._cand(), e_tr, e_go, []), 0.0)

    def test_p4_legbar_gates_gold_but_not_triad(self):
        e_tr, e_go = osel.LegStats(0.1), osel.LegStats(0.3)
        gold = self._cand(leg="gold", sym="XAUUSD")
        s_g = osel.score_of(gold, e_tr, e_go, [])
        # triad always taken (first-available), even with a high bar
        self.assertTrue(osel._decide("P4", self._cand(), 0.99, e_tr, e_go,
                                     None, [], []))
        # gold gated by its own score
        self.assertTrue(osel._decide("P4", gold, s_g * 0.5, e_tr, e_go,
                                     None, [], []))
        self.assertFalse(osel._decide("P4", gold, s_g * 1.5, e_tr, e_go,
                                      None, [], []))

    def test_legstats_walkforward_min_sample(self):
        ls = osel.LegStats(0.10)
        for i in range(4):
            ls.add(1.0)
            self.assertAlmostEqual(ls.e(), 0.10)   # still on the prior
        ls.add(1.0)
        self.assertAlmostEqual(ls.e(), 1.0)        # min sample reached

    def test_jpy_diversity_penalty(self):
        e_tr, e_go = osel.LegStats(0.2), osel.LegStats(0.3)
        c = self._cand()
        base = osel.score_of(c, e_tr, e_go, [])
        pen = osel.score_of(c, e_tr, e_go, ["EURJPY"])
        self.assertAlmostEqual(pen, base * osel.JPY_DIV)
        self.assertEqual(osel.score_of(self._cand(sym="XAUUSD"), e_tr,
                                       e_go, ["GBPJPY"]), base)


class TestSharedSlotPipeline(unittest.TestCase):
    """Full run_combo on the synthetic fixture with the stubbed detector."""

    def setUp(self):
        osel.PRECOMPUTE_CACHE.clear()

    def test_gold_blocks_triad_after_entry(self):
        r = run_policy("P0")
        gt = gold_trades(r)
        self.assertEqual(len(gt), 1)
        entry_d, exit_d = gt[0]["entry_date"], gt[0]["exit_date"]
        # gold entered on the first day after 55 days of history
        self.assertEqual(entry_d, _d(osel.GOLD_N + 1))
        # no triad trade on any day gold holds the slot
        for d in osel._all_days(make_cache()):
            if entry_d <= d < exit_d:
                self.assertEqual(triad_trades(r, d), [],
                                 f"triad traded on gold-held day {d}")

    def test_triad_runs_before_gold_signal(self):
        r = run_policy("P0")
        d = _d(50)
        tt = triad_trades(r, d)
        self.assertEqual(len(tt), 2)          # GBPJPY + EURJPY
        syms = {t["symbol"] for t in tt}
        self.assertEqual(syms, {"GBPJPY", "EURJPY"})
        # slots never overlap within the day
        iv = sorted((t["sig_ts"], t["exit_ts"]) for t in tt)
        self.assertLess(iv[0][1], iv[1][0])
        self.assertTrue(all(t["pnl"] > 0 for t in tt))

    def test_max_two_trades_per_day(self):
        r = run_policy("P0")
        for d in osel._all_days(make_cache()):
            self.assertLessEqual(len(triad_trades(r, d)), 2)

    def test_score_policy_takes_gold_too(self):
        # gold score ~ prior 0.30 x conviction / (1+costR) >> 0.05
        r = run_policy("P1", theta=0.05)
        self.assertEqual(len(gold_trades(r)), 1)
        self.assertEqual(gold_trades(r)[0]["entry_date"], _d(osel.GOLD_N + 1))

    def test_determinism(self):
        r1 = run_policy("P0")
        r2 = run_policy("P0")
        self.assertEqual(
            [(t["date"], t["symbol"], round(t["pnl"], 9))
             for t in r1["trades"]],
            [(t["date"], t["symbol"], round(t["pnl"], 9))
             for t in r2["trades"]])

    def test_no_position_overlap_any_policy(self):
        for p, th_ in (("P0", 0.0), ("P1", 0.05), ("P2", 0.05),
                       ("P3", 0.05)):
            r = run_policy(p, theta=th_)
            spans = []
            for t in r["trades"]:
                if "entry_date" in t:
                    spans.append((t["entry_date"], t["exit_date"], t["symbol"]))
                else:
                    spans.append((t["date"], t["date"], t["symbol"]))
            spans.sort(key=lambda x: (x[0], x[1]))
            for (a0, a1, sa), (b0, b1, sb) in zip(spans, spans[1:]):
                # gold spans days; triad spans are single-day — a triad may
                # share its day with a gold ENTRY only if gold was flat at
                # the open, which the loop forbids; so require disjoint days
                # unless both are the same single-day triad trade.
                if sa == "XAUUSD" and sb == "XAUUSD":
                    continue
                self.assertFalse(a0 < b1 and b0 < a1,
                                 f"{p}: overlap {sa} {a0}-{a1} vs {sb} {b0}-{b1}")


if __name__ == "__main__":
    unittest.main()
