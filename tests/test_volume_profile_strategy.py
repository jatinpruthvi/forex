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


class StrategyTimingTests(unittest.TestCase):
    def test_overnight_levels_use_m1_and_half_open_end(self) -> None:
        body = method("int KeyLevels(")
        self.assertIn("EA_Rates(sym, PERIOD_M1, 0, need, overnight)", body)
        self.assertIn("if(t < onStart || t >= onEnd) continue;", body)
        start = datetime(2026, 10, 7, 18, 0)
        end = datetime(2026, 10, 8, 0, 0)
        self.assertTrue(start <= end - timedelta(minutes=1) < end)
        self.assertFalse(start <= end < end)  # the 00:00 bar cannot leak into ONH/ONL

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
        self.assertIn("return INIT_PARAMETERS_INCORRECT;", SOURCE)

    def test_unused_pending_slot_globals_are_not_written(self) -> None:
        self.assertNotIn("GlobalVariableSet", SOURCE)
        self.assertNotIn("PendingStore(", SOURCE)
        self.assertNotIn("PendingClear(", SOURCE)


if __name__ == "__main__":
    unittest.main()
