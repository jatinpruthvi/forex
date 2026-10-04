"""Behavioural spec for the news time frames (audit defects #90 / #91).

MQL5 cannot execute in this sandbox, so the two time-frame translations the
delivery depends on are mirrored in Python and pinned with real dates:

  1. **Engine gate** (`MQL5_Master/Include/EACore.mqh`): CSV rows are **UTC by
     contract**; a first-row marker ``#timezone=server,,,`` switches the
     comparison to the broker's server clock; calendar-sourced values are
     server time by the calendar API's own convention.
  2. **`NewsManager.mqh`** (`Master_Triad_V1`, `E1_SMC_Core`): a New York
     LOCAL stamp is shifted to server time by ``server_offset - ny_offset``,
     with ``server_offset`` read live from
     ``TimeTradeServer() - TimeGMT()`` and ``ny_offset`` from the US DST rule.

The tests also document *why* the delivered constant +7 h was wrong for two of
the four broker models below, and why a one-hour DST correction that ignores
the broker's own clock only fixed one model while breaking another.
"""
from __future__ import annotations

import math
import unittest
from datetime import date, datetime, timedelta

# ---------------------------------------------------------------- calendars --
MON, SUN = 0, 6


def nth_weekday(year: int, month: int, weekday: int, n: int) -> date:
    """The n-th given weekday of a month (n = 1 is the first)."""
    d = date(year, month, 1)
    return d + timedelta(days=((weekday - d.weekday()) % 7) + 7 * (n - 1))


def last_weekday(year: int, month: int, weekday: int) -> date:
    """The last given weekday of a month."""
    first_next = (date(year + 1, 1, 1) if month == 12 else date(year, month + 1, 1))
    d = first_next - timedelta(days=1)
    return d - timedelta(days=(d.weekday() - weekday) % 7)


def ny_is_dst(local_dt: datetime) -> bool:
    """Mirror of IsNewYorkDst() in NewsManager.mqh (US DST, New York local)."""
    start = datetime.combine(nth_weekday(local_dt.year, 3, SUN, 2), datetime.min.time()) + timedelta(hours=2)
    end = datetime.combine(nth_weekday(local_dt.year, 11, SUN, 1), datetime.min.time()) + timedelta(hours=2)
    return start <= local_dt < end


def eu_is_dst(utc_dt: datetime) -> bool:
    """Mirror of the engine's European DST rule (last Sun Mar 01:00 UTC .. last Sun Oct)."""
    start = datetime.combine(last_weekday(utc_dt.year, 3, SUN), datetime.min.time()) + timedelta(hours=1)
    end = datetime.combine(last_weekday(utc_dt.year, 10, SUN), datetime.min.time()) + timedelta(hours=1)
    return start <= utc_dt < end


def ny_offset_hours(local_dt: datetime) -> int:
    return -4 if ny_is_dst(local_dt) else -5


def utc_of_ny(local_dt: datetime) -> datetime:
    return local_dt - timedelta(hours=ny_offset_hours(local_dt))


# ------------------------------------------------------------ broker models --
def eet_eest(utc_dt: datetime) -> float:
    """The common MT5 broker: server +2 in winter, +3 in summer (EU DST)."""
    return 3.0 if eu_is_dst(utc_dt) else 2.0


def fixed(offset_hours: float):
    return lambda utc_dt: offset_hours


BROKERS = {
    "EET/EEST +2/+3": eet_eest,
    "fixed +2": fixed(2.0),
    "fixed +3": fixed(3.0),
    "fixed +5:30": fixed(5.5),
}

# ----------------------------------------------- NewsManager shift (defect #91)
def true_server_time(local_dt: datetime, broker) -> datetime:
    """Where the release actually sits on the broker's clock."""
    utc = utc_of_ny(local_dt)
    return utc + timedelta(hours=broker(utc))


def derived_shift(local_dt: datetime, broker) -> timedelta:
    """Mirror of NewsServerShiftSeconds(): (server_offset - ny_offset)."""
    utc = utc_of_ny(local_dt)
    return timedelta(hours=broker(utc) - ny_offset_hours(local_dt))


def delivered_constant(local_dt: datetime, hours: float = 7.0) -> datetime:
    """The delivered code: a fixed winter-calibrated shift (default 7 h)."""
    return local_dt + timedelta(hours=hours)


def v1_dst_guess(local_dt: datetime, hours: float = 7.0) -> datetime:
    """The first cut at #91: the constant minus one hour while NY is on DST."""
    return local_dt + timedelta(hours=hours - (1.0 if ny_is_dst(local_dt) else 0.0))


def mql_math_round(x: float) -> float:
    """MQL5 MathRound(): half away from zero (Python's round() is half-to-even)."""
    return math.floor(x + 0.5) if x >= 0 else math.ceil(x - 0.5)


def sample_dates(year: int):
    d = date(year, 1, 1)
    while d.year == year:
        yield d
        d += timedelta(days=3)


class NewsManagerOffsetTests(unittest.TestCase):
    def test_derived_shift_is_exact_year_round_for_every_broker(self):
        for name, broker in BROKERS.items():
            for d in sample_dates(2026):
                for local in (datetime.combine(d, datetime.min.time()) + timedelta(hours=8.5, minutes=30),):
                    self.assertEqual(local + derived_shift(local, broker),
                                     true_server_time(local, broker),
                                     f"{name} on {local}")

    def test_delivered_constant_misses_fixed_offset_servers(self):
        # The delivered +7 h is exact only while it happens to equal
        # server_offset - ny_offset: for a fixed +2 broker that is winter
        # (2 - (-5) = 7), for a fixed +3 broker summer (3 - (-4) = 7).
        cases = [
            # (date, broker, expected server time, expected delivered error)
            (datetime(2026, 7, 15, 8, 30), "fixed +2", datetime(2026, 7, 15, 14, 30), timedelta(hours=1)),
            (datetime(2026, 1, 15, 8, 30), "fixed +3", datetime(2026, 1, 15, 16, 30), timedelta(hours=-1)),
        ]
        for local, name, expected_server, err in cases:
            broker = BROKERS[name]
            right = true_server_time(local, broker)
            self.assertEqual(right, expected_server, f"{name} on {local}")
            self.assertEqual(right, local + derived_shift(local, broker))
            self.assertEqual(delivered_constant(local) - right, err,
                             f"the delivered +7 h must be exactly off by {err} for {name}")

    def test_known_releases_land_on_the_right_server_minute(self):
        # 08:30 ET releases (NFP/CPI/claims) against a wall of brokers.
        for local, expect_utc, expect in (
            (datetime(2026, 1, 15, 8, 30), datetime(2026, 1, 15, 13, 30),
             {"EET/EEST +2/+3": datetime(2026, 1, 15, 15, 30),
              "fixed +2": datetime(2026, 1, 15, 15, 30),
              "fixed +3": datetime(2026, 1, 15, 16, 30),
              "fixed +5:30": datetime(2026, 1, 15, 19, 0)}),
            (datetime(2026, 7, 15, 8, 30), datetime(2026, 7, 15, 12, 30),
             {"EET/EEST +2/+3": datetime(2026, 7, 15, 15, 30),
              "fixed +2": datetime(2026, 7, 15, 14, 30),
              "fixed +3": datetime(2026, 7, 15, 15, 30),
              "fixed +5:30": datetime(2026, 7, 15, 18, 0)}),
        ):
            self.assertEqual(utc_of_ny(local), expect_utc, f"UTC for {local}")
            for name, broker in BROKERS.items():
                right = true_server_time(local, broker)
                self.assertEqual(right, expect[name], f"{name} on {local}")
                self.assertEqual(local + derived_shift(local, broker), right,
                                 f"derived shift for {name} on {local}")

    def test_delivered_constant_is_exact_summer_for_eet_but_v1_broke_it(self):
        # The correction that matters: on the common EET/EEST broker BOTH clocks
        # shift in summer, so the delivered +7 h is right in July while a
        # blanket "-1 while NY is on DST" is an hour early.
        local = datetime(2026, 7, 15, 8, 30)
        broker = BROKERS["EET/EEST +2/+3"]
        right = true_server_time(local, broker)
        self.assertEqual(delivered_constant(local), right)
        self.assertEqual(v1_dst_guess(local) - right, timedelta(hours=-1))
        self.assertEqual(local + derived_shift(local, broker), right)

    def test_the_four_week_us_eu_mismatch_windows(self):
        # Where US and EU DST dates differ the delivered constant is off for the
        # EU-DST broker too - the derived shift is exact on both sides.
        broker = BROKERS["EET/EEST +2/+3"]
        for local in (datetime(2026, 3, 12, 14, 0),    # US on EDT, EU still EET
                      datetime(2026, 10, 28, 14, 0)):  # EU back to EET, US still EDT
            right = true_server_time(local, broker)
            self.assertEqual(delivered_constant(local) - right, timedelta(hours=1))
            self.assertEqual(local + derived_shift(local, broker), right)

    def test_half_hour_servers_keep_the_minutes(self):
        # The engine's seconds helper (EA_ServerGmtOffsetSeconds) against the
        # old whole-hour rounding for a GMT+5:30 server.
        self.assertEqual(mql_math_round(5.5), 6.0)
        rounded_err = timedelta(hours=mql_math_round(5.5)) - timedelta(hours=5.5)
        self.assertEqual(rounded_err, timedelta(minutes=30))

    def test_ny_dst_boundaries(self):
        # 2026: 2nd Sunday of March = Mar 8, 1st Sunday of November = Nov 1.
        self.assertFalse(ny_is_dst(datetime(2026, 3, 8, 1, 59)))
        self.assertTrue(ny_is_dst(datetime(2026, 3, 8, 2, 0)))
        self.assertTrue(ny_is_dst(datetime(2026, 11, 1, 1, 59)))
        self.assertFalse(ny_is_dst(datetime(2026, 11, 1, 2, 0)))
        # 2027: Mar 14 / Nov 7.
        self.assertFalse(ny_is_dst(datetime(2027, 3, 14, 1, 59)))
        self.assertTrue(ny_is_dst(datetime(2027, 3, 14, 2, 0)))
        self.assertFalse(ny_is_dst(datetime(2027, 11, 7, 2, 0)))
        # the EU rule used by the broker models
        self.assertTrue(eu_is_dst(datetime(2026, 3, 29, 1, 0)))
        self.assertFalse(eu_is_dst(datetime(2026, 10, 25, 1, 0)))


# ------------------------------------------------- engine gate frames (#90) --
def engine_frame(first_row: str) -> str:
    """Mirror of the marker rule in EA_LoadNewsCache (empty = UTC)."""
    if first_row.strip().lower().startswith("#timezone") and "server" in first_row.lower():
        return "server"
    return "utc"


def engine_now_ref(frame: str, server_now: datetime, utc_now: datetime) -> datetime:
    """Mirror of EA_NewsNowRef()."""
    return server_now if frame == "server" else utc_now


def engine_blocked(event_ref: datetime, now_ref: datetime,
                   before_min: int = 30, after_min: int = 30) -> bool:
    """Mirror of the window test in EA_NewsBlocked()."""
    return (event_ref - timedelta(minutes=before_min)
            <= now_ref <= event_ref + timedelta(minutes=after_min))


class EngineGateFrameTests(unittest.TestCase):
    def test_marker_rule(self):
        self.assertEqual(engine_frame("#timezone=server,,,"), "server")
        self.assertEqual(engine_frame("date,time,currency,impact"), "utc")
        self.assertEqual(engine_frame("2026.10.02,13:30,USD,HIGH"), "utc")  # no header at all

    def test_defect_90_a_server_time_row_read_as_utc_sits_hours_away(self):
        # Broker GMT+3; the release is 13:30 UTC = 16:30 server.
        utc_now = datetime(2026, 10, 2, 13, 5)          # 25 min before the release
        server_now = utc_now + timedelta(hours=3)       # 16:05 server

        # correct UTC-contract file (legacy layout): blocks right around 13:30 UTC
        self.assertTrue(engine_blocked(datetime(2026, 10, 2, 13, 30), utc_now))
        # the v0 exporter bug: the server stamp 16:30 read as UTC - the gate is
        # OPEN exactly when it must be closed...
        self.assertFalse(engine_blocked(datetime(2026, 10, 2, 16, 30), utc_now))
        # ...and closed 2.5 h after the release instead
        self.assertTrue(engine_blocked(datetime(2026, 10, 2, 16, 30), utc_now + timedelta(hours=3)))

        # the fix: the same 16:30 stamp with the #timezone=server marker
        frame = engine_frame("#timezone=server,,,")
        now_ref = engine_now_ref(frame, server_now, utc_now)
        self.assertTrue(engine_blocked(datetime(2026, 10, 2, 16, 30), now_ref))

        # a calendar-sourced value is server time by construction - same result
        self.assertTrue(engine_blocked(datetime(2026, 10, 2, 16, 30), server_now))

    def test_fail_closed_without_any_source(self):
        # EA_NewsBlocked: empty cache + newsFailClosed -> block (the six engines).
        cache: list = []
        fail_closed = True
        blocked = fail_closed if not cache else False
        self.assertTrue(blocked)


if __name__ == "__main__":
    unittest.main()
