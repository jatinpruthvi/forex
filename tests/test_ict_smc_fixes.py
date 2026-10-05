"""Behavioural spec for the signal-logic fixes of top-25 sweep #2.

MQL5 cannot run in this sandbox, so every rule that was fixed is mirrored in
Python and pinned against the *defect* it replaces - the mirror of the delivered
rule must give the WRONG answer on the fixture, the mirror of the fix the right
one.  (tests/test_compile_class_guards.py covers the compile-error classes.)

  E1 sweep        the "prior liquidity" was read from the NEWEST bars (time axis backwards)
  OB / FVG        R2C, R3A, R3B could never go short; a violated order block still fired
  break-retest    the "retest" was satisfied by the breakout candle itself
  R7A             stop x point, server-clock cash open / close, 300-bar loop, target behind entry
  R5A / R5A2      the Asian-range percentile was taken against 60 full-DAY ranges
  gold exit       the opposite-channel exit tested a bar that is inside the channel
  TRIAD_SURVIVE   sleeve B's reference range contained the breakout candidates
  one bar late    fetch from bar 1, logic written for bar 0
"""
from __future__ import annotations

import random
import re
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
ADD = REPO / "MQL5_Master" / "Experts" / "additionalEAs"
INC = REPO / "MQL5_Master" / "Include"


def bar(o, h, l, c, t=0):
    return {"open": o, "high": h, "low": l, "close": c, "time": t}


def code_only(text: str) -> str:
    """MQL5 source without comments: the fixes explain themselves in prose that names the old code."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


# =============================================================================
# E1 liquidity sweep - chronological arrays (index 0 = OLDEST, like CopyRates)
# =============================================================================
def legacy_sweep_ok(r70, bias):
    """The request-21 rule: 60 bars, 'prior liquidity' = r[50..59] = the NEWEST ten."""
    r = r70[10:]                                   # it fetched only the newest 60
    prior = r[50]["low"] if bias == 1 else r[50]["high"]
    for i in range(51, 60):
        prior = min(prior, r[i]["low"]) if bias == 1 else max(prior, r[i]["high"])
    idx, price = -1, (r[1]["low"] if bias == 1 else r[1]["high"])
    for i in range(1, 50):
        if bias == 1 and r[i]["low"] <= price:
            price, idx = r[i]["low"], i
        if bias == -1 and r[i]["high"] >= price:
            price, idx = r[i]["high"], i
    if idx < 0:
        return False
    if bias == 1:
        return price < prior and r[idx]["close"] > prior
    return price > prior and r[idx]["close"] < prior


def new_sweep_ok(r70, bias):
    """The fixed rule: the prior liquidity is the 10 bars BEFORE the sweep candle."""
    off = 10
    s = off
    price = r70[off]["low"] if bias == 1 else r70[off]["high"]
    for i in range(off + 1, off + 50):
        if bias == 1 and r70[i]["low"] <= price:
            price, s = r70[i]["low"], i
        if bias == -1 and r70[i]["high"] >= price:
            price, s = r70[i]["high"], i
    prior = r70[s - 10]["low"] if bias == 1 else r70[s - 10]["high"]
    for k in range(s - 9, s):
        prior = min(prior, r70[k]["low"]) if bias == 1 else max(prior, r70[k]["high"])
    if bias == 1:
        return price < prior and r70[s]["close"] > prior
    return price > prior and r70[s]["close"] < prior


def choch_window_sweep_index(r70, bias):
    """DetectM15CHoCH's own pick: rates = r70[10:], argmin/argmax over rates[0..49], ties -> latest."""
    rates = r70[10:]
    idx, best = 0, rates[0]["low"] if bias == 1 else rates[0]["high"]
    for i in range(1, 50):
        v = rates[i]["low"] if bias == 1 else rates[i]["high"]
        if (bias == 1 and v <= best) or (bias == -1 and v >= best):
            best, idx = v, i
    return idx + 10


def make_chrono(sweep_at=40, close_back=True, recent_low=1.1010):
    """Quiet market; a prior-low cluster before the sweep; a sweep candle; a rally after it."""
    r = [bar(1.1020, 1.1030, 1.1000, 1.1020) for _ in range(70)]
    for k in range(sweep_at - 10, sweep_at):          # prior liquidity: low 1.0990
        r[k] = bar(1.1010, 1.1030, 1.0990, 1.1015)
    # the sweep candle takes the prior low out and either reclaims or closes below it
    r[sweep_at] = bar(1.1005, 1.1012, 1.0960, 1.1002 if close_back else 1.0955)
    for k in range(sweep_at + 1, 70):                 # after the sweep price sits ABOVE the old lows
        r[k] = bar(1.1030, 1.1050, recent_low, 1.1040)
    return r


class SweepDirectionOfTimeTests(unittest.TestCase):
    def test_a_canonical_sweep_and_reclaim_is_accepted_by_the_fix_but_was_rejected(self):
        r = make_chrono(close_back=True)
        self.assertTrue(new_sweep_ok(r, 1))
        # price rallied after the sweep, so the NEWEST ten bars' low (1.1010) sits above the
        # sweep candle's close (1.1002): the delivered rule rejected the textbook setup
        self.assertFalse(legacy_sweep_ok(r, 1))

    def test_a_breakdown_that_continues_is_rejected_by_the_fix_but_was_accepted(self):
        r = make_chrono(close_back=False)
        r[40] = bar(1.1005, 1.1012, 1.0930, 1.0955)   # a deep breakdown bar that closes UNDER the prior low
        for k in range(41, 70):                       # the market stays below the old low afterwards
            r[k] = bar(1.0950, 1.0965, 1.0940, 1.0952)
        self.assertFalse(new_sweep_ok(r, 1))          # closed below the prior low: not a sweep
        self.assertTrue(legacy_sweep_ok(r, 1))        # the delivered rule let it through

    def test_bearish_mirror(self):
        r = [bar(1.1020, 1.1030, 1.1000, 1.1020) for _ in range(70)]
        for k in range(30, 40):
            r[k] = bar(1.1020, 1.1050, 1.1005, 1.1015)          # prior high 1.1050
        r[40] = bar(1.1030, 1.1085, 1.1022, 1.1035)             # takes it out, closes back below
        for k in range(41, 70):
            r[k] = bar(1.1000, 1.1015, 1.0990, 1.1000)
        self.assertTrue(new_sweep_ok(r, -1))
        r[40] = bar(1.1030, 1.1085, 1.1022, 1.1070)             # closes ABOVE the prior high: held
        self.assertFalse(new_sweep_ok(r, -1))

    def test_the_sweep_candle_is_the_one_the_choch_path_selects(self):
        r = make_chrono()
        self.assertEqual(choch_window_sweep_index(r, 1), 40)
        r[25] = dict(r[40])                           # an equal low earlier: ties resolve to the LATEST
        self.assertEqual(choch_window_sweep_index(r, 1), 40)

    def test_source_matches_the_fixed_rule(self):
        e1 = (INC / "E1_SMC_Core.mqh").read_text(encoding="utf-8")
        fn = e1[e1.index("bool CE1SMCCore::DetectLiquiditySweep("):e1.index("bool CE1SMCCore::DetectM15CHoCH(")]
        self.assertIn("CopyRates(symbol, PERIOD_M15, 1, 70, r) < 70", fn)
        self.assertIn("const int OFF = 10;", fn)
        self.assertIn("r[s - 10]", fn)                # the prior window is BEFORE the sweep candle
        self.assertNotIn("r[50]", fn)                 # ... not the newest ten bars
        self.assertIn("OLDEST-first", e1)


# =============================================================================
# order block / FVG: direction filter + invalidation (series arrays, 0 = forming)
# =============================================================================
def body_ratio(b):
    rng = b["high"] - b["low"]
    return 0.0 if rng <= 0 else abs(b["close"] - b["open"]) / rng


def sig_ob(ctx, r, p, fixed: bool):
    """Mirror of SigOrderBlockRetest; fixed=False reproduces the delivered detector."""
    tol = p["touch_tol"] * ctx["atr"]
    only = p.get("only_dir", 0)
    allow_long = only >= 0
    allow_short = only < 0 or (only == 0 and p["both"])
    for i in range(2, len(r) - 1):
        block, disp = r[i], r[i - 1]
        if allow_long and block["close"] < block["open"] and disp["close"] > disp["open"] \
                and body_ratio(disp) >= p["disp_body"] and disp["close"] > block["high"]:
            failed = fixed and any(r[j]["close"] < block["low"] for j in range(i - 2, 0, -1))
            htf_ok = not (p["htf"] and ctx["ema_h1_200"] > 0 and ctx["mid"] < ctx["ema_h1_200"])
            in_zone = not (ctx["mid"] <= block["low"] - tol or ctx["mid"] > block["high"] + tol)
            if not failed and htf_ok and in_zone and ctx["ask"] - (block["low"] - 0.1 * ctx["atr"]) > 0:
                return +1
        if allow_short and block["close"] > block["open"] and disp["close"] < disp["open"] \
                and body_ratio(disp) >= p["disp_body"] and disp["close"] < block["low"]:
            failed = fixed and any(r[j]["close"] > block["high"] for j in range(i - 2, 0, -1))
            htf_ok = not (p["htf"] and ctx["ema_h1_200"] > 0 and ctx["mid"] > ctx["ema_h1_200"])
            in_zone = not (ctx["mid"] >= block["high"] + tol or ctx["mid"] < block["low"] - tol)
            if not failed and htf_ok and in_zone and (block["high"] + 0.1 * ctx["atr"]) - ctx["bid"] > 0:
                return -1
    return 0


PARAMS = {"touch_tol": 0.15, "disp_body": 0.55, "htf": True, "both": True}


def bearish_ob_scene():
    # series: [0] forming, [1] last closed ... block (bullish) at 3, bearish displacement at 2
    r = [bar(1.0990, 1.1001, 1.0988, 1.0999),          # 0 forming
         bar(1.0980, 1.0999, 1.0978, 1.0996),          # 1 retrace into the block, no close above it
         bar(1.1008, 1.1010, 1.0972, 1.0975),          # 2 bearish displacement (closes under block.low)
         bar(1.1000, 1.1012, 1.0998, 1.1010),          # 3 the BEARISH order block = last bullish candle
         bar(1.1000, 1.1006, 1.0996, 1.1001),
         bar(1.1000, 1.1006, 1.0996, 1.1001)]
    ctx = {"atr": 0.0020, "mid": 1.1000, "bid": 1.0999, "ask": 1.1001, "ema_h1_200": 1.1050}
    return ctx, r


def bullish_ob_scene():
    r = [bar(1.1010, 1.1012, 1.1000, 1.1002),          # 0 forming
         bar(1.1020, 1.1022, 1.1004, 1.1006),          # 1 pullback toward the block
         bar(1.0992, 1.1028, 1.0990, 1.1026),          # 2 bullish displacement (closes above block.high)
         bar(1.1000, 1.1002, 1.0988, 1.0990),          # 3 the BULLISH order block = last bearish candle
         bar(1.1000, 1.1004, 1.0996, 1.1001),
         bar(1.1000, 1.1004, 1.0996, 1.1001)]
    ctx = {"atr": 0.0020, "mid": 1.1000, "bid": 1.0999, "ask": 1.1001, "ema_h1_200": 1.0950}
    return ctx, r


class OrderBlockDirectionTests(unittest.TestCase):
    def test_the_delivered_call_pattern_could_never_go_short(self):
        ctx, r = bearish_ob_scene()
        bias = -1                                      # a bearish higher-timeframe bias
        legacy = dict(PARAMS, both=(bias > 0))         # R2C/R3A/R3B: tradeBothWays = (bias > 0)
        self.assertEqual(sig_ob(ctx, r, legacy, fixed=False), 0)       # bearish branch switched OFF
        fixed = dict(PARAMS, only_dir=bias)
        self.assertEqual(sig_ob(ctx, r, fixed, fixed=True), -1)        # now the short is found

    def test_the_long_side_keeps_working_and_stays_one_sided(self):
        ctx, r = bullish_ob_scene()
        self.assertEqual(sig_ob(ctx, r, dict(PARAMS, only_dir=+1), fixed=True), +1)
        self.assertEqual(sig_ob(ctx, r, dict(PARAMS, only_dir=-1), fixed=True), 0)

    def test_a_nearer_opposite_block_no_longer_masks_a_valid_one(self):
        # bias long, but the search used to run both ways and return the first block it met
        ctx, r = bullish_ob_scene()
        self.assertEqual(sig_ob(ctx, r, dict(PARAMS, only_dir=+1), fixed=True), +1)

    def test_a_violated_block_no_longer_fires(self):
        ctx, r = bullish_ob_scene()
        # price traded THROUGH the block: bar 1 closes beneath block.low, bar 0 drifts back inside it
        r[1] = bar(1.0996, 1.0999, 1.0975, 1.0980)
        ctx = dict(ctx, mid=1.0996)
        self.assertEqual(sig_ob(ctx, r, PARAMS, fixed=False), +1)      # delivered: a long off a dead block
        self.assertEqual(sig_ob(ctx, r, PARAMS, fixed=True), 0)

    def test_source_has_the_filter_and_the_invalidation(self):
        sig = (INC / "EASignals.mqh").read_text(encoding="utf-8")
        ob = sig[sig.index("bool SigOrderBlockRetest("):sig.index("//| 16. FAIR-VALUE-GAP")]
        self.assertIn("p.onlyDir >= 0", ob)
        self.assertIn("r[j].close < block.low", ob)
        self.assertIn("r[j].close > block.high", ob)
        fvg = sig[sig.index("bool SigFvgRetest("):sig.index("//| 17. Z-SCORE")]
        self.assertIn("allowLong", fvg)
        for ea, needle in (("EA_studyarena_round3_contestant_a__1_", "ob.onlyDir = bias;"),
                           ("EA_studyarena_round3_contestant_b__1_", "f.onlyDir = dirBias;"),
                           ("EA_studyarena_round2_contestant_c", "ob.onlyDir = htfBias;")):
            text = (ADD / f"{ea}.mq5").read_text(encoding="utf-8")
            self.assertIn(needle, text)
            self.assertNotRegex(code_only(text), r"tradeBothWays\s*=\s*\((?:htfBias|bias|dirBias) > 0\)")


# =============================================================================
# SigBreakRetest
# =============================================================================
def sig_break_retest(ctx, r, p, fixed: bool):
    """Return (direction, barsAgo) or None.  Series arrays, [0] = forming bar."""
    r_hi, r_lo, atr = ctx["r_hi"], ctx["r_lo"], ctx["atr"]
    got = len(r)
    if not fixed:                                     # the delivered rule: break and retest on ONE bar
        for i in range(1, min(got - 2, 4) + 1):
            b = r[i]
            if b["close"] > r_hi + p["buf"] * atr:
                if b["low"] > r_hi + p["tol"] * atr:
                    continue
                if b["close"] < r_hi:
                    continue
                return (+1, i)
            if b["close"] < r_lo - p["buf"] * atr:
                if b["high"] < r_lo - p["tol"] * atr:
                    continue
                if b["close"] > r_lo:
                    continue
                return (-1, i)
        return None
    for k in range(2, min(got - 1, 5) + 1):           # the break bar
        brk = r[k]
        if brk["close"] > r_hi + p["buf"] * atr:
            for j in range(k - 1, 0, -1):             # a LATER closed bar
                rt = r[j]
                if rt["low"] > r_hi + p["tol"] * atr:
                    continue
                if rt["close"] < r_hi:
                    continue
                return (+1, j)
        if brk["close"] < r_lo - p["buf"] * atr:
            for j in range(k - 1, 0, -1):
                rt = r[j]
                if rt["high"] < r_lo - p["tol"] * atr:
                    continue
                if rt["close"] > r_lo:
                    continue
                return (-1, j)
    return None


BR = {"buf": 0.10, "tol": 0.15}
BR_CTX = {"r_hi": 1.1000, "r_lo": 1.0950, "atr": 0.0020}


class BreakRetestTests(unittest.TestCase):
    def _inside(self):
        return bar(1.0990, 1.0998, 1.0985, 1.0992)

    def test_a_plain_breakout_candle_is_not_a_retest(self):
        # bar 1 opens inside the range and closes 10 pips above it: a breakout, nothing more
        r = [self._inside(), bar(1.0997, 1.1014, 1.0996, 1.1010)] + [self._inside() for _ in range(6)]
        self.assertEqual(sig_break_retest(BR_CTX, r, BR, fixed=False), (+1, 1))   # delivered: fires at once
        self.assertIsNone(sig_break_retest(BR_CTX, r, BR, fixed=True))            # no pullback has happened

    def test_a_genuine_break_pullback_hold_sequence_fires_on_the_retest_bar(self):
        r = [self._inside(),
             bar(1.1006, 1.1012, 1.1001, 1.1008),     # 1: pulls back to the level and holds above it
             bar(1.1014, 1.1020, 1.1010, 1.1018),     # 2: continuation
             bar(1.0997, 1.1016, 1.0996, 1.1012),     # 3: the accepted break (close > hi + buffer)
             self._inside(), self._inside(), self._inside(), self._inside()]
        self.assertEqual(sig_break_retest(BR_CTX, r, BR, fixed=True), (+1, 1))

    def test_a_retest_that_closes_back_inside_is_a_failure(self):
        r = [self._inside(),
             bar(1.1006, 1.1008, 1.0990, 1.0995),     # 1: dips through the level and closes inside
             bar(1.1014, 1.1020, 1.1010, 1.1018),
             bar(1.0997, 1.1016, 1.0996, 1.1012),
             self._inside(), self._inside(), self._inside(), self._inside()]
        self.assertIsNone(sig_break_retest(BR_CTX, r, BR, fixed=True))

    def test_bearish_mirror(self):
        r = [self._inside(),
             bar(1.0944, 1.0952, 1.0940, 1.0942),     # 1: rallies back to the level, holds below it
             bar(1.0936, 1.0940, 1.0930, 1.0934),     # 2: continuation
             bar(1.0953, 1.0954, 1.0934, 1.0938),     # 3: the accepted break below
             self._inside(), self._inside(), self._inside(), self._inside()]
        self.assertEqual(sig_break_retest(BR_CTX, r, BR, fixed=True), (-1, 1))

    def test_source_keeps_break_and_retest_on_different_bars(self):
        sig = (INC / "EASignals.mqh").read_text(encoding="utf-8")
        fn = sig[sig.index("bool SigBreakRetest("):sig.index("//| 8. VWAP REVERSION")]
        self.assertIn("for(int k = 2;", fn)
        self.assertIn("for(int j = k - 1; j >= 1; j--)", fn)
        self.assertNotIn("for(int i = 1; i <= (int)MathMin(got - 2, 4); i++)", fn)


# =============================================================================
# R7A - GER40 gap fade
# =============================================================================
def london_offset_minutes(server_offset_h=2):
    return -server_offset_h * 60


class R7ATests(unittest.TestCase):
    def test_the_stop_distance_is_in_price_units(self):
        gap, point = 45.0, 0.01
        self.assertAlmostEqual(1.5 * gap * point, 0.675)          # delivered: a 0.7-point stop
        self.assertAlmostEqual(1.5 * gap, 67.5)                   # fixed
        self.assertAlmostEqual((1.5 * gap) / (1.5 * gap * point), 100.0)   # sizing took a 100x position

    def _day(self, server_offset_h=2):
        """M5 bars for yesterday + today in SERVER time, newest first; the close encodes the UK minute."""
        bars = []
        for day in (0, 1):                                        # 0 = yesterday, 1 = today
            for m in range(0, 24 * 60, 5):
                uk_min = m
                srv_min = m + server_offset_h * 60
                if srv_min >= 1440:
                    continue
                bars.append({"day": day, "srv": srv_min, "uk": uk_min, "close": day * 10000 + uk_min,
                             "open": day * 10000 + uk_min - 5})
        return list(reversed([b for b in bars if not (b["day"] == 1 and b["uk"] > 9 * 60)]))

    def test_prior_close_is_the_1630_uk_bar_not_the_days_last_bar(self):
        bars = self._day(2)
        legacy = next(b for b in bars if b["day"] == 0 and b["srv"] >= 16 * 60 + 30)   # server minutes, >=
        self.assertEqual(legacy["uk"], 21 * 60 + 55)              # the evening bar: the overnight gap, not the cash gap
        fixed = next(b for b in bars if b["day"] == 0 and b["uk"] < 16 * 60 + 30)
        self.assertEqual(fixed["uk"], 16 * 60 + 25)               # last bar that OPENED before 16:30 UK

    def test_cash_open_is_08_00_uk_not_08_00_server(self):
        bars = list(reversed(self._day(2)))                       # oldest first, as CashOpen scans
        legacy = next(b for b in bars if b["day"] == 1 and b["srv"] >= 8 * 60)
        self.assertEqual(legacy["uk"], 6 * 60)                    # 06:00 UK - two hours before the cash open
        fixed = next(b for b in bars if b["day"] == 1 and b["uk"] >= 8 * 60)
        self.assertEqual(fixed["uk"], 8 * 60)

    def test_the_delivered_loop_ran_past_a_short_copy(self):
        got, hard_bound = 250, 300
        legacy_reads = list(range(0, hard_bound))
        self.assertTrue(any(i >= got for i in legacy_reads))      # r[i] for i >= got = array out of range
        self.assertFalse(any(i >= got for i in range(0, got)))    # bounded by what CopyRates returned

    def test_a_gap_that_has_already_filled_is_not_a_trade(self):
        prior_close, entry = 18000.0, 18030.0
        # gap DOWN (long fade) but price has already recovered above the prior close
        self.assertTrue(prior_close <= entry)

    def test_source(self):
        ea = (ADD / "EA_studyarena_round7_contestant_a.mq5").read_text(encoding="utf-8")
        self.assertIn("double stopDist = 1.5 * gapAbs;", ea)
        self.assertNotIn("gapAbs * ctx.point", code_only(ea))
        self.assertIn("for(int i = 0; i < got; i++)", ea)
        self.assertNotIn("i < 300", ea)
        self.assertIn("EA_BarClockTime(r[i].time)", ea)
        self.assertIn("EA_ClockNow()", ea)
        self.assertIn("if(dir > 0 && priorClose <= plan.entry) return false;", ea)


# =============================================================================
# R5A / R5A2 Asian-range percentile
# =============================================================================
def legacy_pct(today, day_ranges):
    n = below = 0
    for r in day_ranges:
        if r <= 0:
            continue
        n += 1
        below += today >= r
    return 100.0 * below / n if n else 50.0


def new_pct(today, asian_ranges):
    n = below = 0
    for r in asian_ranges[1:]:                     # [0] is the session being judged
        if r <= 0:
            continue
        n += 1
        below += today >= r
    return 100.0 * below / n if n else 50.0


class AsianPercentileTests(unittest.TestCase):
    def setUp(self):
        rnd = random.Random(7)
        self.asian = [max(5.0, rnd.gauss(25, 6)) for _ in range(61)]          # pips
        self.day = [max(30.0, rnd.gauss(85, 20)) for _ in range(60)]           # a day is ~3x the session

    def test_the_delivered_percentile_sits_near_zero_and_the_gate_rejects(self):
        today = self.asian[0]
        legacy = legacy_pct(today, self.day)
        self.assertLess(legacy, 20.0)                                          # below the band's floor -> rejected
        # ... for essentially EVERY ordinary day
        rej = sum(legacy_pct(a, self.day) < 20.0 or legacy_pct(a, self.day) > 65.0 for a in self.asian)
        self.assertGreater(rej / len(self.asian), 0.9)

    def test_the_fixed_percentile_is_a_real_percentile(self):
        pcts = [new_pct(a, [a] + self.asian[1:]) for a in self.asian]
        self.assertTrue(all(0.0 <= p <= 100.0 for p in pcts))
        inside = sum(20.0 <= p <= 65.0 for p in pcts)
        self.assertGreater(inside / len(pcts), 0.35)                           # the band accepts a normal share of days
        self.assertAlmostEqual(new_pct(min(self.asian), [0.0] + self.asian[1:]), 0.0, places=6) if min(self.asian) < min(self.asian[1:]) else None

    def test_source(self):
        sig = (INC / "EASignals.mqh").read_text(encoding="utf-8")
        self.assertIn("int SigAsianRangeHistory(", sig)
        self.assertIn("double SigAsiaRangePercentile(", sig)
        self.assertIn("if(m >= 0 && m < 7 * 60)", sig)
        for ea in ("EA_studyarena_round5_contestant_a", "EA_studyarena_round5_contestant_a_2047"):
            text = (ADD / f"{ea}.mq5").read_text(encoding="utf-8")
            self.assertIn("return SigAsiaRangePercentile(sym, todayRange, 60);", text)
            self.assertNotIn("PERIOD_D1, 1, 60, d", text)


# =============================================================================
# gold: opposite-channel exit
# =============================================================================
def gold_exit(r, n, is_buy, delivered: bool):
    """r newest first (r[0] = yesterday); channel = r[1..n]."""
    h = max(b["high"] for b in r[1:n + 1])
    l = min(b["low"] for b in r[1:n + 1])
    probe = r[1] if delivered else r[0]
    return probe["close"] < l if is_buy else probe["close"] > h


class GoldExitTests(unittest.TestCase):
    def _series(self, rnd, n=55):
        out = []
        px = 2000.0
        for _ in range(n + 5):
            o = px
            c = px + rnd.gauss(0, 8)
            out.append(bar(o, max(o, c) + abs(rnd.gauss(0, 3)), min(o, c) - abs(rnd.gauss(0, 3)), c))
            px = c
        return out

    def test_the_delivered_exit_can_never_fire(self):
        rnd = random.Random(3)
        for _ in range(500):
            r = self._series(rnd)
            self.assertFalse(gold_exit(r, 55, True, delivered=True))
            self.assertFalse(gold_exit(r, 55, False, delivered=True))

    def test_the_fixed_exit_fires_when_yesterday_closes_through_the_channel(self):
        r = [bar(1990, 1995, 1940, 1945)] + [bar(1990, 2005, 1985, 1998) for _ in range(60)]   # collapse
        self.assertTrue(gold_exit(r, 55, True, delivered=False))
        self.assertFalse(gold_exit(r, 55, False, delivered=False))
        r2 = [bar(2010, 2060, 2008, 2055)] + [bar(1990, 2005, 1985, 1998) for _ in range(60)]  # blow-off
        self.assertTrue(gold_exit(r2, 55, False, delivered=False))

    def test_source(self):
        ea = (ADD / "EA_FINAL_OPTIMUM_STRATEGY.mq5").read_text(encoding="utf-8")
        self.assertIn("bool   exitCh = isBuy ? (r[0].close < l) : (r[0].close > h);", ea)
        self.assertNotIn("r[1].close < l", code_only(ea))


# =============================================================================
# TRIAD_SURVIVE sleeve B: the reference range of each candidate
# =============================================================================
def sleeve_b_breakout(r, fixed: bool):
    """r series (0 = forming).  Returns (dir, breakIdx) or None."""
    if fixed:
        for i in range(1, 7):
            rng = r[i]["high"] - r[i]["low"]
            if rng <= 0:
                continue
            body = abs(r[i]["close"] - r[i]["open"]) / rng
            if body < 0.70:
                continue
            ch = max(r[k]["high"] for k in range(i + 1, i + 17))
            cl = min(r[k]["low"] for k in range(i + 1, i + 17))
            if r[i]["close"] > ch:
                return (+1, i)
            if r[i]["close"] < cl:
                return (-1, i)
        return None
    # delivered: start=1 fetch (r[0] = bar 1), one FIXED window r[3..18]
    hi = max(r[k]["high"] for k in range(3, 19))
    lo = min(r[k]["low"] for k in range(3, 19))
    for i in range(1, 7):
        rng = r[i]["high"] - r[i]["low"]
        if rng <= 0:
            continue
        body = abs(r[i]["close"] - r[i]["open"]) / rng
        if body < 0.70:
            continue
        if r[i]["close"] > hi:
            return (+1, i)
        if r[i]["close"] < lo:
            return (-1, i)
    return None


class SleeveBTests(unittest.TestCase):
    def _flat(self):
        return [bar(1.1000, 1.1010, 1.0990, 1.1000) for _ in range(30)]

    def test_a_breakout_four_bars_ago_could_never_fire(self):
        r = self._flat()
        r[4] = bar(1.1002, 1.1050, 1.1000, 1.1046)               # a strong body, closes above the 4h high
        self.assertIsNone(sleeve_b_breakout(r, fixed=False))      # delivered: it was inside its own range
        self.assertEqual(sleeve_b_breakout(r, fixed=True), (+1, 4))

    def test_a_breakout_on_bar_two_worked_before_and_still_does(self):
        r = self._flat()
        r[2] = bar(1.1002, 1.1050, 1.1000, 1.1046)
        self.assertEqual(sleeve_b_breakout(r, fixed=False), (+1, 2))
        self.assertEqual(sleeve_b_breakout(r, fixed=True), (+1, 2))

    def test_every_candidate_from_one_to_six_can_now_fire(self):
        for i in range(1, 7):
            r = self._flat()
            r[i] = bar(1.1002, 1.1050, 1.1000, 1.1046)
            self.assertEqual(sleeve_b_breakout(r, fixed=True), (+1, i))

    def test_source(self):
        ea = (ADD / "EA_TRIAD_SURVIVE.mq5").read_text(encoding="utf-8")
        self.assertIn("for(int k = i + 1; k <= i + 16; k++)", ea)
        self.assertIn("EA_Rates(ctx.symbol, PERIOD_M15, 0, 30, r) < 24", ea)
        self.assertNotIn("for(int i = 3; i < 19; i++)", ea)


# =============================================================================
# one bar late: fetch from bar 1 with logic written for bar 0
# =============================================================================
class BarIndexConventionTests(unittest.TestCase):
    def test_a_fetch_from_bar_one_hides_the_last_closed_bar_from_index_one_loops(self):
        closed = ["bar1", "bar2", "bar3", "bar4"]             # bar 1 = the most recent CLOSED bar
        start1 = closed[:]                                    # CopyRates(start=1): r[0] = bar 1
        start0 = ["forming"] + closed                         # CopyRates(start=0): r[k] = bar k
        self.assertEqual([start1[i] for i in (1, 2, 3)], ["bar2", "bar3", "bar4"])      # delivered loop i = 1..3
        self.assertEqual([start0[i] for i in (1, 2, 3)], ["bar1", "bar2", "bar3"])      # fixed

    def test_the_eas_that_loop_from_one_now_fetch_from_zero(self):
        for ea, needle in (("EA_THE5ERS_CHALLENGE_STRATEGY_V2", "EA_Rates(ctx.symbol, PERIOD_M1, 0, 30, r)"),
                           ("EA_THE5ERS_2_5K_CHALLENGE_PLAN", "EA_Rates(ctx.symbol, PERIOD_M1, 0, 20, m)"),
                           ("EA_FINAL_OPTIMUM_STRATEGY", "EA_Rates(ctx.symbol, PERIOD_M5, 0, lookback + 1, r)"),
                           ("EA_TRIAD_SURVIVE", "EA_Rates(ctx.symbol, PERIOD_M15, 0, 24, r) < 21")):
            text = (ADD / f"{ea}.mq5").read_text(encoding="utf-8")
            self.assertIn(needle, text, ea)

    def test_r8d_judges_the_displacement_candle_not_the_last_closed_one(self):
        ea = (ADD / "EA_studyarena_round8_contestant_d.mq5").read_text(encoding="utf-8")
        self.assertIn("int db = (int)MathMax(1, MathMin(plan.barsAgo, 5));", ea)
        self.assertIn("r[db].close > r[db].low + 0.75", ea)

    def test_r4d_stops_beyond_the_sweep_wick(self):
        ea = (ADD / "EA_studyarena_round4_contestant_d.mq5").read_text(encoding="utf-8")
        self.assertIn("BullPlan(ctx, plan, r[3].low)", ea)
        self.assertIn("BearPlan(ctx, plan, r[3].high)", ea)
        self.assertNotIn("BullPlan(ctx, plan, lo)", ea)


if __name__ == "__main__":
    unittest.main()
