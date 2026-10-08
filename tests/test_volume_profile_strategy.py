"""Regression fences for the Volume Profile EA's price/profile geometry.

MetaEditor is Windows-only, so these tests pin the MQL5 source decisions and exercise
small reference cases for the boundary math that had produced the audit findings.
They are not a substitute for Strategy Tester validation.
"""
from __future__ import annotations

import math
import unittest
from datetime import datetime, timedelta
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
EA_PATH = REPO / "chartfanatics" / "mql5-eas" / "EA_CF_VolumeProfileStrategy.mq5"
SOURCE = EA_PATH.read_text(encoding="utf-8")


def method(name: str) -> str:
    """Return one MQL method, including its signature and balanced body."""
    start = SOURCE.index(name)
    opening = SOURCE.index("{", start)
    depth = 0
    for pos in range(opening, len(SOURCE)):
        if SOURCE[pos] == "{":
            depth += 1
        elif SOURCE[pos] == "}":
            depth -= 1
            if depth == 0:
                return SOURCE[start:pos + 1]
    raise AssertionError(f"unterminated method {name}")


def nearest_edge(states: list[str], start: int, direction: int) -> int | None:
    step = 1 if direction > 0 else -1
    for i in range(start, len(states) if step > 0 else -1, step):
        nb = i + step
        if not 0 <= nb < len(states):
            break
        if (states[i], states[nb]) in (("H", "L"), ("L", "H")):
            return nb if step > 0 else i
    return None


def select_swept_edge(candidates: list[tuple[str, float, float, bool, bool]]) -> str | None:
    """Pick the closest signal-close level among all swept levels that are real edges."""
    valid = [(abs(close - level), name) for name, level, close, swept, edge in candidates
             if swept and edge]
    return min(valid)[1] if valid else None

def prior_day_qualifies(body_in_direction: float, close: float, previous_high: float,
                        previous_low: float, direction: int, atr: float,
                        trend_atr: float) -> bool:
    """Reference the source's alternative: a directional breakout OR a trend day."""
    trend = body_in_direction > 0.0 and atr > 0.0 and body_in_direction >= trend_atr * atr
    breakout = close > previous_high if direction > 0 else close < previous_low
    return trend or breakout


def choose_target(direction: int, entry: float, risk: float, min_r: float, fallback_r: float,
                  *, shelf: float | None = None, poc_extreme: float | None = None) -> float | None:
    """Keep the named POC extreme / nearest shelf; never leapfrog it to a fallback."""
    candidate = poc_extreme if poc_extreme is not None else shelf
    if candidate is not None:
        distance = direction * (candidate - entry)
        return candidate if distance > min_r * risk else None
    return entry + direction * fallback_r * risk


def next_shelf_edge(volumes: list[float], start: int, direction: int, lo: float,
                    step_size: float, hvn_factor: float = 1.30) -> float | None:
    """Reference the entry-facing edge of the nearest high-volume shelf."""
    if not volumes:
        return None
    avg = sum(volumes) / len(volumes)
    step = 1 if direction > 0 else -1
    for i in range(start + step, len(volumes) if step > 0 else -1, step):
        if volumes[i] >= hvn_factor * avg:
            return lo + (i if direction > 0 else i + 1) * step_size
    return None


def resolved_window(now: datetime, start_minute: int, end_minute: int) -> tuple[datetime, datetime]:
    """Reference the most recent in-progress/completed same-day or overnight window."""
    today = now.replace(hour=0, minute=0, second=0, microsecond=0)
    now_minute = now.hour * 60 + now.minute
    if start_minute > end_minute:
        if now_minute >= start_minute:
            start = today + timedelta(minutes=start_minute)
            end = today + timedelta(days=1, minutes=end_minute)
        else:
            start = today - timedelta(days=1) + timedelta(minutes=start_minute)
            end = today + timedelta(minutes=end_minute)
    elif now_minute < start_minute:
        start = today - timedelta(days=1) + timedelta(minutes=start_minute)
        end = today - timedelta(days=1) + timedelta(minutes=end_minute)
    else:
        start = today + timedelta(minutes=start_minute)
        end = today + timedelta(minutes=end_minute)
    return start, min(end, now)


def history_bars_for_session(vr_bars: int, volume_bars: int, signal_seconds: int) -> int:
    """Fetch at least one complete server day for the session profile at low TFs."""
    session_bars = (86400 + signal_seconds - 1) // signal_seconds + 2
    return max(vr_bars, volume_bars, session_bars) + 5


def has_current_session_bar(times: list[datetime], today_start: datetime) -> bool:
    """MQL series index 1 is the first closed bar; prior-day data is not today's profile."""
    return len(times) > 1 and times[1] >= today_start


def block_after(source: str, marker: str) -> str:
    """Return a balanced brace block following a source marker."""
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 0
    for pos in range(opening, len(source)):
        if source[pos] == "{":
            depth += 1
        elif source[pos] == "}":
            depth -= 1
            if depth == 0:
                return source[start:pos + 1]
    raise AssertionError(f"unterminated block after {marker}")


def adverse_hvn_boundary(volumes: list[float], start: int, direction: int,
                         hvn_factor: float = 1.30) -> int | None:
    """Reference model for the stop boundary of the nearest adverse-side HVN."""
    avg = sum(volumes) / len(volumes)
    is_hvn = lambda index: volumes[index] >= hvn_factor * avg
    step = -1 if direction > 0 else 1
    node = next((i for i in range(start, len(volumes) if step > 0 else -1, step)
                 if is_hvn(i)), None)
    if node is None:
        return None
    far = node
    for i in range(node + step, len(volumes) if step > 0 else -1, step):
        if not is_hvn(i):
            break
        far = i
    return far if direction > 0 else far + 1


class ProfileBoundaryTests(unittest.TestCase):
    def test_profile_maximum_and_flat_max_bar_stay_inside_last_bucket(self) -> None:
        body = method("void BuildProfileRange(")
        lookup = method("int BucketOf(")
        self.assertIn("if(b1 >= pf.buckets) b1 = pf.buckets - 1;", body)
        self.assertIn("if(b2 >= pf.buckets) b2 = pf.buckets - 1;", body)
        self.assertIn("if(b == pf.buckets && px <= pf.hi) b = pf.buckets - 1;", lookup)
        # A flat candle at the profile maximum used to index vol[buckets].
        lo, hi, buckets = 100.0, 160.0, 60
        raw = math.floor((hi - lo) / ((hi - lo) / buckets))
        self.assertEqual(raw, buckets)
        self.assertEqual(min(raw, buckets - 1), buckets - 1)

    def test_edge_detector_handles_both_hvn_lva_orientations(self) -> None:
        body = method("double NearestEdge(")
        self.assertIn("if(IsHvn(pf, i) && IsLva(pf, nb))", body)
        self.assertIn("if(IsLva(pf, i) && IsHvn(pf, nb))", body)
        self.assertEqual(nearest_edge(["H", "L"], 0, +1), 1)
        self.assertEqual(nearest_edge(["L", "H"], 0, +1), 1)
        self.assertEqual(nearest_edge(["L", "H"], 1, -1), 1)
        self.assertEqual(nearest_edge(["H", "L"], 1, -1), 1)

    def test_all_swept_key_levels_are_checked_for_edge_confluence(self) -> None:
        body = method("bool PlanSignal(")
        self.assertIn("if(!swept || !AtProfileEdge(l, sess, vr, htf)) continue;", body)
        self.assertIn("double gap = MathAbs(d[1].close - l);", body)
        candidates = [
            ("PDH", 100.0, 99.0, True, False),  # earlier swept level, but not an edge
            ("ONL", 96.5, 99.0, True, True),   # valid, but farther from the close
            ("ONH", 98.0, 99.0, True, True),   # nearest edge-qualified level
        ]
        self.assertEqual(select_swept_edge(candidates), "ONH")

    def test_hvn_stop_searches_adverse_side_and_uses_far_node_edge(self) -> None:
        body = method("double HvnBeyond(")
        self.assertIn("int step = (dir > 0) ? -1 : +1;", body)
        self.assertIn("int far = node;", body)
        self.assertIn("pf.lo + (double)far * pf.step", body)
        self.assertIn("pf.lo + (double)(far + 1) * pf.step", body)
        # Bins 2-3 and 6 are HVNs in this profile. For a long at bin 5, ignore
        # the favorable-side node at 6 and put the stop beyond the lower edge at 2.
        volumes = [0, 0, 10, 10, 0, 0, 10, 0]
        self.assertEqual(adverse_hvn_boundary(volumes, 5, +1), 2)
        self.assertEqual(adverse_hvn_boundary(volumes, 1, -1), 4)

    def test_next_shelf_targets_the_entry_facing_edge_of_first_hvn(self) -> None:
        body = method("double NextShelf(")
        self.assertIn("pf.lo + (double)i * pf.step", body)
        self.assertIn("pf.lo + (double)(i + 1) * pf.step", body)
        volumes = [0, 0, 10, 10, 0, 0, 10, 0]
        self.assertEqual(next_shelf_edge(volumes, 0, +1, 100.0, 1.0), 102.0)
        self.assertEqual(next_shelf_edge(volumes, 7, -1, 100.0, 1.0), 107.0)


class StrategyTimingTests(unittest.TestCase):
    def test_overnight_levels_use_m1_and_half_open_end(self) -> None:
        body = method("int KeyLevels(")
        self.assertIn("EA_Rates(sym, PERIOD_M1, 0, need, overnight)", body)
        self.assertIn("OvernightWindow(now, onStart, onEnd);", body)
        self.assertIn("if(t < onStart || t >= onEnd) continue;", body)
        start = datetime(2026, 10, 7, 18, 0)
        end = datetime(2026, 10, 8, 0, 0)
        self.assertTrue(start <= end - timedelta(minutes=1) < end)
        self.assertFalse(start <= end < end)  # the 00:00 bar cannot leak into ONH/ONL

    def test_window_rollover_handles_daytime_and_overnight_inputs(self) -> None:
        body = method("void OvernightWindow(")
        self.assertIn("if(startMinute > endMinute)", body)
        self.assertIn("else if(nowMinute < startMinute)", body)
        self.assertIn("if(onEnd > now) onEnd = now;", body)
        now = datetime(2026, 10, 8, 10, 0)
        # Default 18:00-00:00 uses the last completed overnight interval.
        self.assertEqual(resolved_window(now, 18 * 60, 0),
                         (datetime(2026, 10, 7, 18), datetime(2026, 10, 8, 0)))
        # A same-day 09:00-16:00 window before today's start uses yesterday's
        # completed window, rather than spanning nearly 24 hours to the current time.
        self.assertEqual(resolved_window(datetime(2026, 10, 8, 8), 9 * 60, 16 * 60),
                         (datetime(2026, 10, 7, 9), datetime(2026, 10, 7, 16)))
        self.assertEqual(resolved_window(datetime(2026, 10, 8, 12), 9 * 60, 16 * 60),
                         (datetime(2026, 10, 8, 9), datetime(2026, 10, 8, 12)))

    def test_history_fetch_covers_a_full_server_day_on_lower_signal_timeframes(self) -> None:
        body = method("bool BuildPlan(")
        self.assertIn("int sessionBars = (86400 + signalSeconds - 1) / signalSeconds + 2;", body)
        self.assertIn("MathMax(MathMax(InpVrBars, InpVolAvgBars), sessionBars)", body)
        # 120 M5 bars cover only ten hours; the session profile needs the full day.
        request = history_bars_for_session(120, 20, 5 * 60)
        self.assertGreaterEqual(request, 288 + 2)
        self.assertEqual(history_bars_for_session(120, 20, 60 * 60), 125)

    def test_new_server_day_does_not_reuse_yesterday_as_session_profile(self) -> None:
        body = method("bool BuildSessionProfile(")
        self.assertIn("if(got < 2 || d[1].time < todayStart) return false;", body)
        today_start = datetime(2026, 10, 8, 0, 0)
        self.assertFalse(has_current_session_bar(
            [today_start, today_start - timedelta(hours=4)], today_start))
        self.assertTrue(has_current_session_bar(
            [today_start + timedelta(hours=4), today_start], today_start))

    def test_poc_previous_day_gate_accepts_breakout_or_atr_trend(self) -> None:
        body = method("bool PriorTrendDay(")
        self.assertIn("bool trend = (body > 0.0 && ctx.atrD1 > 0.0 && body >= InpTrendDayAtr * ctx.atrD1);", body)
        self.assertIn("bool breakout = false;", body)
        self.assertIn("return (trend || breakout);", body)
        self.assertIn("PriorTrendDay(ctx, dir)", method("bool PlanSignal("))
        # A broad-bodied trend can qualify without clearing yesterday's extreme;
        # a small-bodied breakout can qualify without being an ATR-sized trend.
        self.assertTrue(prior_day_qualifies(8.0, 105.0, 110.0, 90.0, +1, 10.0, 0.70))
        self.assertTrue(prior_day_qualifies(1.0, 111.0, 110.0, 90.0, +1, 10.0, 0.70))
        # A qualifying close breakout remains a breakout even if the candle body
        # is opposite-coloured; only the trend-day alternative requires a body.
        self.assertTrue(prior_day_qualifies(-1.0, 111.0, 110.0, 90.0, +1, 10.0, 0.70))
        self.assertFalse(prior_day_qualifies(2.0, 105.0, 110.0, 90.0, +1, 10.0, 0.70))

    def test_poc_reads_the_previous_broker_d1_bar_not_a_rolling_24h_slice(self) -> None:
        body = method("double PriorDayPoc(")
        self.assertIn("EA_Rates(sym, PERIOD_D1, 0, 3, days)", body)
        self.assertIn("datetime priorStart = days[1].time;", body)
        self.assertIn("datetime priorEnd = priorStart + (datetime)d1Seconds;", body)
        self.assertIn("h1[i].time >= priorStart && h1[i].time < priorEnd", body)
        self.assertIn("TimeTradeServer() - priorStart", body)
        # Late Monday and a weekend gap still request enough H1 history to include
        # Friday's full daily bar rather than just Friday's last few hours.
        friday = datetime(2026, 10, 2, 0, 0)
        monday_late = datetime(2026, 10, 5, 23, 0)
        need = math.ceil((monday_late - friday).total_seconds() / 3600) + 5
        self.assertGreaterEqual(need, 72)

    def test_weekly_bias_uses_a_prior_week_profile_not_the_intraday_visible_range(self) -> None:
        body = method("int WeeklyBias(")
        self.assertIn("EA_Rates(sym, PERIOD_W1, 1, InpBiasWeeks + 1, w)", body)
        self.assertIn("BuildProfileRange(weekly, w, got, 1, InpBiasWeeks, InpVrBuckets);", body)
        self.assertIn("NearestEdge(weekly, w[0].low", body)
        self.assertIn("NearestEdge(weekly, w[0].high", body)
        self.assertNotIn("NearestEdge(vr", body)

    def test_multisymbol_candidates_are_consumed_once_per_own_signal_bar(self) -> None:
        body = method("bool BuildPlan(")
        self.assertIn("datetime symbolBar = iTime(ctx.symbol, g_eaIndTf, 0);", body)
        self.assertIn("symbolBar <= m_lastPlanBar[ctx.index]", body)
        self.assertIn("m_lastPlanBar[ctx.index] = symbolBar;", body)
        self.assertLess(body.index("m_lastPlanBar[ctx.index] = symbolBar;"),
                        body.index("PlanSignal(ctx, d, got"))
        self.assertIn("for(int i = 0; i < EA_MAX_SYMBOLS; i++) m_lastPlanBar[i] = 0;",
                      method("void OnInitStrategy("))
        # A delayed symbol must not replay the same closed bar on every bar of
        # the first configured symbol, but a genuinely newer bar is eligible.
        last_seen = 10
        self.assertFalse(10 > last_seen)
        self.assertTrue(11 > last_seen)

    def test_optional_profiles_are_initialized_before_history_gates(self) -> None:
        body = method("bool BuildPlan(")
        self.assertIn("CFVP_InitProfile(htf);", body)
        self.assertLess(body.index("CFVP_InitProfile(htf);"), body.index("if(dgot >= 5)"))
        init = method("void CFVP_InitProfile(")
        self.assertIn("pf.step = 0.0;", init)
        self.assertIn("pf.buckets = 0;", init)


class SignalEntryTests(unittest.TestCase):
    def test_retrace_limit_is_inside_the_actual_wick_not_the_body_to_extreme_range(self) -> None:
        body = method("bool PlanSignal(")
        self.assertIn("entry = (dir > 0) ? (bodyLo - InpRetraceFrac * wick)", body)
        self.assertIn("(bodyHi + InpRetraceFrac * wick);", body)
        long_low, long_body_lo, fraction = 90.0, 96.0, 0.50
        short_body_hi, short_high = 104.0, 110.0
        self.assertEqual(long_body_lo - fraction * (long_body_lo - long_low), 93.0)
        self.assertEqual(short_body_hi + fraction * (short_high - short_body_hi), 107.0)
        self.assertTrue(long_low < 93.0 < long_body_lo)
        self.assertTrue(short_body_hi < 107.0 < short_high)

    def test_invalidated_retrace_is_not_sent_as_a_marketable_limit(self) -> None:
        body = method("bool PlanSignal(")
        self.assertIn("if(retrace && ((dir > 0 && ctx.bid <= stop) || (dir < 0 && ctx.ask >= stop))) return false;", body)

    def test_unsafe_input_ranges_fail_initialization(self) -> None:
        body = method("bool InputsValid(")
        self.assertIn("InpVolAvgBars < 1", body)
        self.assertIn("InpRetraceFrac < 0.50 || InpRetraceFrac > 0.80", body)
        self.assertIn("InpTargetR < InpMinTargetR", body)
        self.assertIn("InpStopBufferAtr <= 0.0", body)
        self.assertIn("InpUsePocRetest && InpTrendDayAtr <= 0.0", body)
        self.assertIn("return INIT_PARAMETERS_INCORRECT;", SOURCE)

    def test_target_respects_the_named_poc_extreme_and_nearest_shelf(self) -> None:
        body = method("bool PlanSignal(")
        poc_branch = block_after(body, "if(pocOk)")
        self.assertIn("if(dg < 1) return false;", poc_branch)
        self.assertIn("tgt = (dir > 0) ? dd[0].high : dd[0].low;", poc_branch)
        self.assertIn("InpMinTargetR * risk)) return false;", poc_branch)
        self.assertNotIn("NextShelf", poc_branch)
        self.assertIn("double shelf = NextShelf(vr, entry, dir);", body)
        self.assertIn("if(dir > 0 && !(shelf > entry + InpMinTargetR * risk)) return false;", body)
        self.assertIn("tgt = (dir > 0) ? entry + InpTargetR * risk", body)
        self.assertIn('targetType = "fixed-R fallback";', body)
        # An unavailable/too-close POC objective or nearest shelf rejects the setup;
        # only the absence of a shelf invokes the configured R-multiple fallback.
        self.assertIsNone(choose_target(+1, 100.0, 2.0, 1.5, 3.0, poc_extreme=102.0))
        self.assertIsNone(choose_target(+1, 100.0, 2.0, 1.5, 3.0, shelf=102.0))
        self.assertEqual(choose_target(+1, 100.0, 2.0, 1.5, 3.0), 106.0)
        self.assertEqual(choose_target(+1, 100.0, 2.0, 1.5, 3.0, poc_extreme=104.0), 104.0)

    def test_poc_log_labels_the_edge_requirement_as_an_exception(self) -> None:
        body = method("bool PlanSignal(")
        self.assertIn("named setup exception", body)
        self.assertIn("if(level <= 0.0 && InpUsePocRetest && poc > 0.0)", body)
        self.assertNotIn("prior day's own value edge", body)

    def test_signal_reason_distinguishes_entry_type_from_target_type(self) -> None:
        body = method("bool PlanSignal(")
        self.assertIn('targetType = "prior-day extreme";', body)
        self.assertIn('targetType = "nearest shelf";', body)
        self.assertIn('targetType = "fixed-R fallback";', body)
        self.assertIn('(retrace ? "retrace-limit" : "market"), targetType, tgt);', body)
        self.assertIn('%s entry, %s target %.5f', body)

    def test_unused_pending_slot_globals_are_not_written(self) -> None:
        self.assertNotIn("GlobalVariableSet", SOURCE)
        self.assertNotIn("PendingStore(", SOURCE)
        self.assertNotIn("PendingClear(", SOURCE)


if __name__ == "__main__":
    unittest.main()
