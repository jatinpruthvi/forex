"""Tick-to-observed-events builder for TRIAD-R V2.1 EURUSD London session.

Reads the raw Eightcap bid/ask tick CSV and produces the observed-event CSV
required by tools/replay_export.py.

The pipeline:
  1. Parse tick CSV (DATE, TIME, BID, ASK columns; tab-delimited).
  2. For each trading day:
     a. Build ask-side M5 OHLC bars (ask price = buy fill price).
        Ask bars are built from ALL rows that have a non-empty ask column
        (flag=4 ask-only rows AND flag=6 both-side rows).  Using only the 53%
        of ticks that carry both bid and ask was the original bug — M5 bars
        built from half the data missed price extremes and produced
        artificially small bodies/wicks.
     b. Build mid-price M5 and M15 bars from both-side (flag=6) ticks only.
        Mid-price is used for the Asian reference range and ATR; it should
        *not* be contaminated by one-sided quotes.
     c. Compute M15 ATR(14) at the London-session open using Wilder smoothing.
     d. Build the Asian-session reference range (prior-session high/low) from
        mid-price bars.
     e. Run the frozen V2.1 Sleeve A signal detector on M5 ask bars in the
        London entry window (07:00–11:00 Europe/London civil time).
     f. For each detected signal (sweep→reclaim→displacement), record the
        observed exit path by scanning forward mid-price ticks.
  3. Write one row per signal event to observed_events.csv.

Assumptions / limitations
--------------------------
- Server time = UTC+3 (Eightcap standard offset).
- Europe/London DST handled via the same last-Sunday-of-month rule as the EA.
- Ask bars use ALL rows with a non-empty ask value (flag 4 + flag 6).
- Mid bars use ONLY rows where both bid and ask are present (flag 6).
- ATR uses a simple 14-period mean of M15 bar ranges (H-L) from mid-price bars
  as an approximation of Wilder's smoothing.
- Commission assumed $4 round-trip per lot (EA default).
- Volume_min=0.01, volume_step=0.01, tick_size=0.00001, tick_value=$10/lot/pip
  (standard EURUSD on 1:100 leverage with $-denominated account).
- No news calendar is applied here; all events are emitted as activation_ok=true
  from a signal-geometry perspective.

Usage
-----
    python tools/tick_signal_builder.py \\
        --tick-file validation/HistoryData/EURUSD.i_202406190501_202609102250.csv \\
        --output    validation/EURUSD_London_observed_events.csv \\
        --combination EURUSD_LONDON [--verbose]
"""
from __future__ import annotations

import argparse
import csv
import math
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Optional

# ---------------------------------------------------------------------------
# Constants (frozen EA contract values)
# ---------------------------------------------------------------------------

SWEEP_ATR_MIN        = 0.05
SWEEP_ATR_MAX        = 0.50
RECLAIM_WICK_MIN     = 0.60
DISPLACEMENT_BODY_MIN = 0.60
STOP_BUFFER_ATR      = 0.10
STOP_ATR_MIN         = 0.60
STOP_ATR_MAX         = 1.50

TICK_SIZE            = 0.00001   # EURUSD 5-digit pricing
TICK_VALUE_PER_LOT   = 10.0      # $10 per pip per standard lot
CONTRACT_SIZE        = 100_000.0
VOLUME_MIN           = 0.01
VOLUME_STEP          = 0.01
COMMISSION_PER_LOT   = 4.0       # $4 round-trip

SERVER_UTC_OFFSET    = 3         # Eightcap server = UTC+3


# ---------------------------------------------------------------------------
# DST helpers (mirrors EA civil-time code)
# ---------------------------------------------------------------------------

def _last_sunday(year: int, month: int) -> date:
    """Last Sunday of the given year/month."""
    if month == 12:
        next_month = date(year + 1, 1, 1)
    else:
        next_month = date(year, month + 1, 1)
    last_day = next_month - timedelta(days=1)
    offset = last_day.weekday()  # Mon=0 … Sun=6
    return last_day - timedelta(days=(offset + 1) % 7)


def london_utc_offset(utc_dt: datetime) -> int:
    """Return London UTC offset in hours: +1 (BST) or 0 (GMT)."""
    d = utc_dt.date() if hasattr(utc_dt, 'date') else utc_dt
    year = d.year
    bst_start = _last_sunday(year, 3)
    bst_end   = _last_sunday(year, 10)
    if bst_start <= d < bst_end:
        return 1
    return 0


def server_to_utc(server_dt: datetime) -> datetime:
    return server_dt - timedelta(hours=SERVER_UTC_OFFSET)


def utc_to_london_wall(utc_dt: datetime) -> datetime:
    return utc_dt + timedelta(hours=london_utc_offset(utc_dt))


def server_to_london_wall(server_dt: datetime) -> datetime:
    return utc_to_london_wall(server_to_utc(server_dt))


def london_wall_to_server(year: int, month: int, day: int,
                           hour: int, minute: int) -> datetime:
    """Convert London civil time to server (UTC+3) datetime."""
    wall = datetime(year, month, day, hour, minute)
    utc_dt = wall - timedelta(hours=london_utc_offset(
        datetime(year, month, day, hour, minute)))
    return utc_dt + timedelta(hours=SERVER_UTC_OFFSET)


# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

@dataclass
class Bar:
    time: datetime   # bar open (server time)
    open: float
    high: float
    low:  float
    close: float
    ticks: int = 0


def _bar_key(dt: datetime, period_minutes: int) -> datetime:
    total_minutes = dt.hour * 60 + dt.minute
    floored = total_minutes // period_minutes * period_minutes
    return dt.replace(hour=floored // 60, minute=floored % 60,
                      second=0, microsecond=0)


def build_bars(ticks: list[tuple[datetime, float]],
               period_minutes: int) -> list[Bar]:
    """Build OHLC bars from (datetime, price) pairs."""
    bar_map: dict[datetime, Bar] = {}
    for dt, price in ticks:
        key = _bar_key(dt, period_minutes)
        if key not in bar_map:
            bar_map[key] = Bar(key, price, price, price, price, 1)
        else:
            b = bar_map[key]
            if price > b.high: b.high = price
            if price < b.low:  b.low  = price
            b.close = price
            b.ticks += 1
    return [bar_map[k] for k in sorted(bar_map)]


def compute_atr14(bars_m15: list[Bar], before_server: datetime) -> float:
    """Simple 14-period mean ATR (H-L) from completed M15 bars before a time."""
    completed = [b for b in bars_m15 if b.time < before_server]
    if len(completed) < 14:
        return 0.0
    recent = completed[-14:]
    return sum(b.high - b.low for b in recent) / 14.0


# ---------------------------------------------------------------------------
# Bar geometry helpers (mirrors EA logic)
# ---------------------------------------------------------------------------

def lower_wick_ratio(bar: Bar) -> float:
    total = bar.high - bar.low
    if total <= 0: return 0.0
    body_low = min(bar.open, bar.close)
    return (body_low - bar.low) / total


def upper_wick_ratio(bar: Bar) -> float:
    total = bar.high - bar.low
    if total <= 0: return 0.0
    body_high = max(bar.open, bar.close)
    return (bar.high - body_high) / total


def body_ratio(bar: Bar) -> float:
    total = bar.high - bar.low
    if total <= 0: return 0.0
    return abs(bar.close - bar.open) / total


# ---------------------------------------------------------------------------
# Signal detection (frozen V2.1 Sleeve A logic)
# ---------------------------------------------------------------------------

@dataclass
class SignalEvent:
    server_day:          str
    sequence:            int
    event_id:            str
    direction:           str    # "long" or "short"
    reference_low:       float
    reference_high:      float
    sweep_low:           float
    sweep_high:          float
    reclaim_open:        float
    reclaim_high:        float
    reclaim_low:         float
    reclaim_close:       float
    displacement_open:   float
    displacement_high:   float
    displacement_low:    float
    displacement_close:  float
    atr_m15:             float
    spread_price:        float
    signal_bar_server:   datetime   # displacement bar open time (server)
    entry_price:         float      # 50% retrace of displacement body
    stop_price:          float
    sweep_extreme:       float


@dataclass
class RejectionStats:
    """Tracks per-day rejection reasons for verbose reporting."""
    no_ref_bars:          int = 0
    insufficient_atr:     int = 0
    zero_atr:             int = 0
    no_window_bars:       int = 0
    no_sweep:             int = 0
    ambiguous_sweep:      int = 0
    too_deep:             int = 0
    opp_sweep_in_window:  int = 0
    weak_wick:            int = 0
    no_reclaim_3bars:     int = 0
    no_displace_bar:      int = 0
    displace_wrong_dir:   int = 0
    displace_weak_body:   int = 0
    displace_midpoint:    int = 0
    stop_atr_band:        int = 0
    signal_found:         int = 0

    def total_failed(self) -> int:
        return (self.no_ref_bars + self.insufficient_atr + self.zero_atr +
                self.no_window_bars + self.no_sweep + self.ambiguous_sweep +
                self.too_deep + self.opp_sweep_in_window + self.weak_wick +
                self.no_reclaim_3bars + self.no_displace_bar +
                self.displace_wrong_dir + self.displace_weak_body +
                self.displace_midpoint + self.stop_atr_band)

    def print_summary(self) -> None:
        total = self.total_failed() + self.signal_found
        print(f"\nSignal detection breakdown ({total} days processed):")
        print(f"  {'signal_found':<30} {self.signal_found:>5}  ({self.signal_found/total*100:.1f}%)")
        print("  --- Rejection reasons ---")
        for attr, label in [
            ('no_ref_bars',         'no_ref_bars (no Asian range ticks)'),
            ('insufficient_atr',    'insufficient_atr (< 14 M15 bars)'),
            ('zero_atr',            'zero_atr'),
            ('no_window_bars',      'no_window_bars (no entry-window M5 bars)'),
            ('no_sweep',            'no_sweep (price never exceeded ref range)'),
            ('ambiguous_sweep',     'ambiguous_sweep (two-sided on same bar)'),
            ('too_deep',            'too_deep (sweep > 0.50 ATR during reclaim)'),
            ('opp_sweep_in_window', 'opp_sweep_in_window'),
            ('weak_wick',           'weak_wick (< 0.60 ratio on reclaim bar)'),
            ('no_reclaim_3bars',    'no_reclaim_3bars (no close inside range in 3 bars)'),
            ('no_displace_bar',     'no_displace_bar (reclaim = last bar)'),
            ('displace_wrong_dir',  'displace_wrong_dir'),
            ('displace_weak_body',  'displace_weak_body (< 0.60 body ratio)'),
            ('displace_midpoint',   'displace_midpoint (close < reclaim midpoint)'),
            ('stop_atr_band',       'stop_atr_band (stop distance outside 0.60–1.50 ATR)'),
        ]:
            v = getattr(self, attr)
            if v > 0:
                print(f"  {'  '+label:<30} {v:>5}  ({v/total*100:.1f}%)")


def detect_signals(bars_m5: list[Bar],
                   ref_high: float, ref_low: float,
                   atr: float,
                   entry_start: datetime,
                   entry_end: datetime,
                   avg_spread: float,
                   server_day: str,
                   stats: RejectionStats) -> list[SignalEvent]:
    """
    Apply the frozen V2.1 signal geometry to the entry-window M5 bars.
    Returns at most one SignalEvent (one-event-per-session rule).
    Updates stats in-place for reporting.
    """
    if atr <= 0:
        stats.zero_atr += 1
        return []

    # Bars in the entry window only
    window_bars = [b for b in bars_m5
                   if entry_start <= b.time < entry_end]
    if not window_bars:
        stats.no_window_bars += 1
        return []

    sweep_index = -1
    sweep_side  = None
    sweep_extreme = 0.0

    for i, bar in enumerate(window_bars):
        long_depth  = (ref_low  - bar.low)  / atr
        short_depth = (bar.high - ref_high) / atr

        long_sweep  = long_depth  >= SWEEP_ATR_MIN
        short_sweep = short_depth >= SWEEP_ATR_MIN

        if not long_sweep and not short_sweep:
            continue

        # Ambiguous two-sided sweep → consume event, no trade
        if long_sweep and short_sweep:
            stats.ambiguous_sweep += 1
            return []

        sweep_index   = i
        sweep_side    = "long" if long_sweep else "short"
        sweep_extreme = bar.low if sweep_side == "long" else bar.high
        break

    if sweep_index < 0:
        stats.no_sweep += 1
        return []

    # Update sweep extreme through the reclaim window
    # 3 bars inclusive from sweep bar (sweep bar + 2 more)
    last_reclaim = min(len(window_bars) - 1, sweep_index + 2)
    reclaim_index = -1
    reclaim_fail_reason = None

    for i in range(sweep_index, last_reclaim + 1):
        bar = window_bars[i]

        if sweep_side == "long":
            sweep_extreme = min(sweep_extreme, bar.low)
            depth = (ref_low - sweep_extreme) / atr
            if depth > SWEEP_ATR_MAX:
                reclaim_fail_reason = "too_deep"
                break
            if (bar.high - ref_high) / atr >= SWEEP_ATR_MIN:
                reclaim_fail_reason = "opp_sweep_in_window"
                break
            if bar.close > ref_low and bar.close < ref_high:
                wr = lower_wick_ratio(bar)
                if wr < RECLAIM_WICK_MIN:
                    reclaim_fail_reason = "weak_wick"
                    break
                reclaim_index = i
                break
        else:
            sweep_extreme = max(sweep_extreme, bar.high)
            depth = (sweep_extreme - ref_high) / atr
            if depth > SWEEP_ATR_MAX:
                reclaim_fail_reason = "too_deep"
                break
            if (ref_low - bar.low) / atr >= SWEEP_ATR_MIN:
                reclaim_fail_reason = "opp_sweep_in_window"
                break
            if bar.close < ref_high and bar.close > ref_low:
                wr = upper_wick_ratio(bar)
                if wr < RECLAIM_WICK_MIN:
                    reclaim_fail_reason = "weak_wick"
                    break
                reclaim_index = i
                break

    if reclaim_index < 0:
        if reclaim_fail_reason == "too_deep":
            stats.too_deep += 1
        elif reclaim_fail_reason == "opp_sweep_in_window":
            stats.opp_sweep_in_window += 1
        elif reclaim_fail_reason == "weak_wick":
            stats.weak_wick += 1
        else:
            stats.no_reclaim_3bars += 1
        return []

    # Need displacement bar (immediately after reclaim)
    if reclaim_index + 1 >= len(window_bars):
        stats.no_displace_bar += 1
        return []

    reclaim     = window_bars[reclaim_index]
    displacement = window_bars[reclaim_index + 1]

    # Displacement validity
    if sweep_side == "long":
        dir_ok  = displacement.close > displacement.open
        body_ok = body_ratio(displacement) >= DISPLACEMENT_BODY_MIN
        mid_ok  = displacement.close > (reclaim.high + reclaim.low) / 2.0
    else:
        dir_ok  = displacement.close < displacement.open
        body_ok = body_ratio(displacement) >= DISPLACEMENT_BODY_MIN
        mid_ok  = displacement.close < (reclaim.high + reclaim.low) / 2.0

    if not dir_ok:
        stats.displace_wrong_dir += 1
        return []
    if not body_ok:
        stats.displace_weak_body += 1
        return []
    if not mid_ok:
        stats.displace_midpoint += 1
        return []

    # Entry price = 50% retrace of displacement body
    disp_body_mid = (displacement.open + displacement.close) / 2.0
    entry = round(disp_body_mid / TICK_SIZE) * TICK_SIZE

    # Stop price
    raw_stop = (sweep_extreme - STOP_BUFFER_ATR * atr
                if sweep_side == "long"
                else sweep_extreme + STOP_BUFFER_ATR * atr)
    stop = (math.floor(raw_stop / TICK_SIZE) * TICK_SIZE
            if sweep_side == "long"
            else math.ceil(raw_stop / TICK_SIZE) * TICK_SIZE)

    stop_distance = abs(entry - stop)
    stop_atr = stop_distance / atr
    if stop_atr < STOP_ATR_MIN or stop_atr > STOP_ATR_MAX:
        stats.stop_atr_band += 1
        return []

    stats.signal_found += 1
    seq = reclaim_index + 1  # 0-based index of displacement bar in window

    return [SignalEvent(
        server_day       = server_day,
        sequence         = seq,
        event_id         = f"{server_day}_EURUSD_LONDON_{seq}",
        direction        = sweep_side,
        reference_low    = ref_low,
        reference_high   = ref_high,
        sweep_low        = sweep_extreme if sweep_side == "long" else ref_low,
        sweep_high       = ref_high if sweep_side == "long" else sweep_extreme,
        reclaim_open     = reclaim.open,
        reclaim_high     = reclaim.high,
        reclaim_low      = reclaim.low,
        reclaim_close    = reclaim.close,
        displacement_open  = displacement.open,
        displacement_high  = displacement.high,
        displacement_low   = displacement.low,
        displacement_close = displacement.close,
        atr_m15          = atr,
        spread_price     = avg_spread,
        signal_bar_server = displacement.time,
        entry_price      = entry,
        stop_price       = stop,
        sweep_extreme    = sweep_extreme,
    )]


# ---------------------------------------------------------------------------
# Exit path reconstruction
# ---------------------------------------------------------------------------

def compute_exit_path(sig: SignalEvent,
                      entry_window_end: datetime,
                      forward_mids: list[tuple[datetime, float]],
                      ) -> dict:
    """
    Scan forward mid-price ticks after the displacement bar to determine:
    - whether the limit was touched / traded through
    - target, stop, and time-stop outcomes
    """
    stop_dist  = abs(sig.entry_price - sig.stop_price)
    target_r   = 1.50   # Profile A default
    target_prc = (sig.entry_price + stop_dist * target_r
                  if sig.direction == "long"
                  else sig.entry_price - stop_dist * target_r)
    one_r_prc  = (sig.entry_price + stop_dist
                  if sig.direction == "long"
                  else sig.entry_price - stop_dist)

    # Only look at ticks after the displacement bar close
    disp_close = sig.signal_bar_server + timedelta(minutes=5)
    relevant   = [(dt, p) for dt, p in forward_mids if dt >= disp_close]

    # Limit touched = price went through entry by at least 1 pip
    limit_touched       = False
    trade_through_ticks = 0
    fill_time           = None

    for dt, p in relevant:
        if sig.direction == "long":
            if p <= sig.entry_price:
                if not limit_touched:
                    limit_touched = True
                    fill_time = dt
                through = (sig.entry_price - p) / TICK_SIZE
                trade_through_ticks = max(trade_through_ticks, int(through))
        else:
            if p >= sig.entry_price:
                if not limit_touched:
                    limit_touched = True
                    fill_time = dt
                through = (p - sig.entry_price) / TICK_SIZE
                trade_through_ticks = max(trade_through_ticks, int(through))
        if trade_through_ticks >= 1:
            break

    # Default exit values
    exit_reason           = "cancel"
    target_hit_minutes    = None
    stop_hit_minutes      = None
    breakeven_hit_minutes = None
    worst_adverse         = sig.entry_price

    prices_at = {"30": sig.entry_price, "45": sig.entry_price,
                 "60": sig.entry_price, "90": sig.entry_price}
    price_at_session_end = sig.entry_price

    if limit_touched and trade_through_ticks >= 1 and fill_time is not None:
        post_fill = [(dt, p) for dt, p in relevant if dt >= fill_time]

        for dt, p in post_fill:
            elapsed_min = (dt - fill_time).total_seconds() / 60.0

            if sig.direction == "long" and p < worst_adverse:
                worst_adverse = p
            elif sig.direction == "short" and p > worst_adverse:
                worst_adverse = p

            for horizon in (30, 45, 60, 90):
                key = str(horizon)
                if elapsed_min <= horizon:
                    prices_at[key] = p

            if dt < entry_window_end:
                price_at_session_end = p

            if stop_hit_minutes is None:
                if (sig.direction == "long" and p <= sig.stop_price) or \
                   (sig.direction == "short" and p >= sig.stop_price):
                    stop_hit_minutes = elapsed_min

            if target_hit_minutes is None:
                if (sig.direction == "long" and p >= target_prc) or \
                   (sig.direction == "short" and p <= target_prc):
                    target_hit_minutes = elapsed_min

            if breakeven_hit_minutes is None:
                if (sig.direction == "long" and p >= one_r_prc) or \
                   (sig.direction == "short" and p <= one_r_prc):
                    breakeven_hit_minutes = elapsed_min

        events = []
        if target_hit_minutes is not None:
            events.append(("target",     target_hit_minutes))
        if stop_hit_minutes is not None:
            events.append(("stop",       stop_hit_minutes))
        events.append(("time", 45.0))
        session_elapsed = (entry_window_end - fill_time).total_seconds() / 60.0
        events.append(("session_end", max(0.0, session_elapsed)))
        events.sort(key=lambda x: x[1])
        exit_reason = events[0][0]

    return {
        "limit_active":           True,
        "limit_touched":          limit_touched,
        "trade_through_ticks":    trade_through_ticks,
        "fill_fraction":          1.0 if (limit_touched and trade_through_ticks >= 1) else 0.0,
        "exit_reason":            exit_reason,
        "target_hit_minutes":     target_hit_minutes,
        "stop_hit_minutes":       stop_hit_minutes,
        "breakeven_hit_minutes":  breakeven_hit_minutes,
        "price_at_30":            prices_at["30"],
        "price_at_45":            prices_at["45"],
        "price_at_60":            prices_at["60"],
        "price_at_90":            prices_at["90"],
        "price_at_session_end":   price_at_session_end,
        "worst_adverse_price":    worst_adverse,
        "rule_violation":         False,
        "operational_error":      False,
    }


# ---------------------------------------------------------------------------
# Main per-day processing
# ---------------------------------------------------------------------------

EVENT_FIELDS = (
    "server_day", "sequence", "event_id", "combination", "direction",
    "reference_low", "reference_high", "sweep_low", "sweep_high",
    "reclaim_open", "reclaim_high", "reclaim_low", "reclaim_close",
    "displacement_open", "displacement_high", "displacement_low", "displacement_close",
    "atr_m15",
    "tick_size", "tick_value", "contract_size", "volume_min", "volume_step",
    "spread_price", "slippage_price", "commission_per_lot_round_trip",
    "limit_active", "limit_touched", "trade_through_ticks", "fill_fraction",
    "exit_reason", "target_hit_minutes", "stop_hit_minutes", "breakeven_hit_minutes",
    "price_at_30", "price_at_45", "price_at_60", "price_at_90", "price_at_session_end",
    "worst_adverse_price", "rule_violation", "operational_error",
)


def process_file(tick_file: Path, output_file: Path, combination: str,
                 verbose: bool = False) -> None:
    print(f"Reading tick file: {tick_file} ({tick_file.stat().st_size / 1e6:.0f} MB)")

    # ---- Load all ticks grouped by server date ----
    #
    # Tick types by CSV flag column:
    #   flag=6  → both bid AND ask are set (use for mid-price AND ask bars)
    #   flag=4  → ask only (use for ask bars)
    #   flag=2  → bid only (use for bid bars — not currently used)
    #
    # Key fix: ask-price M5 bars must be built from ALL rows that carry an ask
    # value (flag=4 + flag=6).  The original code only loaded rows where both
    # bid AND ask were non-empty, discarding ~47% of ask-only ticks and
    # producing M5 bars with missing price extremes.

    # ask_ticks[day]  = list of (datetime, ask_price)  — for M5 ask bars
    # mid_ticks[day]  = list of (datetime, mid_price)  — for ref range, ATR, exits
    ask_day: dict[str, list[tuple[datetime, float]]] = defaultdict(list)
    mid_day: dict[str, list[tuple[datetime, float]]] = defaultdict(list)

    both_count = 0
    ask_only_count = 0
    total_count = 0

    with open(tick_file, "r", newline="") as f:
        reader = csv.reader(f, delimiter="\t")
        next(reader)  # skip header
        for row in reader:
            if len(row) < 4:
                continue
            bid_s = row[2].strip()
            ask_s = row[3].strip()
            date_str = row[0].strip()
            time_str = row[1].strip()[:8]

            has_bid = bid_s != ""
            has_ask = ask_s != ""

            if not has_bid and not has_ask:
                continue

            try:
                dt = datetime.strptime(date_str + " " + time_str, "%Y.%m.%d %H:%M:%S")
            except (ValueError, IndexError):
                continue

            total_count += 1

            if has_ask:
                ask_day[date_str].append((dt, float(ask_s)))
                if has_bid:
                    both_count += 1
                    mid_day[date_str].append(
                        (dt, (float(bid_s) + float(ask_s)) / 2.0)
                    )
                else:
                    ask_only_count += 1

    all_days = sorted(ask_day.keys())
    print(f"Loaded {total_count:,} total ticks across {len(all_days)} trading days")
    print(f"  Both-side ticks (mid): {both_count:,}  "
          f"Ask-only ticks: {ask_only_count:,}")

    # Accumulate M15 bars for rolling ATR history (mid-price bars)
    all_m15_mid: list[Bar] = []
    seen_m15_times: set[datetime] = set()

    events_written = 0
    stats = RejectionStats()

    with open(output_file, "w", newline="") as fout:
        writer = csv.DictWriter(fout, fieldnames=EVENT_FIELDS)
        writer.writeheader()

        for day_str in all_days:
            ask_ticks = ask_day[day_str]
            mid_ticks = mid_day[day_str]
            day_dt = datetime.strptime(day_str, "%Y.%m.%d")

            # ---- Session boundaries (server time) ----
            range_start = london_wall_to_server(
                day_dt.year, day_dt.month, day_dt.day, 0, 0)
            range_end   = london_wall_to_server(
                day_dt.year, day_dt.month, day_dt.day, 7, 0)
            entry_start = range_end
            entry_end   = london_wall_to_server(
                day_dt.year, day_dt.month, day_dt.day, 11, 0)

            # ---- M15 bars (mid-price, for ATR) — extend rolling history ----
            for b in build_bars(mid_ticks, 15):
                if b.time not in seen_m15_times:
                    all_m15_mid.append(b)
                    seen_m15_times.add(b.time)
            all_m15_mid.sort(key=lambda x: x.time)

            # ---- Reference range (mid-price M5 bars in Asian window) ----
            ref_mid_bars = [b for b in build_bars(mid_ticks, 5)
                            if range_start <= b.time < range_end]
            if not ref_mid_bars:
                stats.no_ref_bars += 1
                if verbose:
                    print(f"  {day_str}: SKIP no_ref_bars")
                continue
            ref_high = max(b.high for b in ref_mid_bars)
            ref_low  = min(b.low  for b in ref_mid_bars)

            # ---- ATR(14) at London open ----
            atr = compute_atr14(all_m15_mid, entry_start)
            if atr <= 0:
                if len([b for b in all_m15_mid if b.time < entry_start]) < 14:
                    stats.insufficient_atr += 1
                else:
                    stats.zero_atr += 1
                if verbose:
                    print(f"  {day_str}: SKIP atr={atr:.6f}")
                continue

            # ---- M5 bars from ask-price ticks (signal detection) ----
            # Using ask-only + both-side ask values so bar geometry matches
            # MT5's CopyRates which is ask-based on a standard broker feed.
            m5_ask_bars = build_bars(ask_ticks, 5)

            # ---- Average spread at London open (first 5 min) ----
            # Require both-side ticks to compute spread
            open_spreads = []
            for dt, mid_p in mid_ticks:
                if entry_start <= dt < entry_start + timedelta(minutes=5):
                    # Find the closest ask in ask_ticks — approximate as the
                    # mid + half the typical spread.  Since we don't have paired
                    # bid/ask here (mid_ticks uses only both-side rows), we can
                    # compute spread directly from the both-side records.
                    pass  # handled below
            # Direct spread from both-side rows
            both_side_by_dt = {dt: mid_p for dt, mid_p in mid_ticks}
            ask_by_dt = dict(ask_ticks)
            for dt, ask_p in ask_ticks:
                if entry_start <= dt < entry_start + timedelta(minutes=5):
                    if dt in both_side_by_dt:
                        mid_p = both_side_by_dt[dt]
                        spread = (ask_p - mid_p) * 2.0   # spread = ask - bid = 2*(ask - mid)
                        if spread > 0:
                            open_spreads.append(spread)
            avg_spread = (sum(open_spreads) / len(open_spreads)
                          if open_spreads else 0.0001)

            # ---- Detect signals ----
            signals = detect_signals(
                m5_ask_bars, ref_high, ref_low, atr,
                entry_start, entry_end, avg_spread, day_str, stats,
            )

            if not signals:
                if verbose:
                    # The stats object was already updated by detect_signals
                    pass
                continue

            # ---- Build exit paths ----
            for sig in signals:
                # Forward mid-price ticks from displacement bar onwards
                forward = [(dt, p) for dt, p in mid_ticks
                           if dt >= sig.signal_bar_server]
                exit_data = compute_exit_path(sig, entry_end, forward)

                row = {
                    "server_day":     sig.server_day,
                    "sequence":       sig.sequence,
                    "event_id":       sig.event_id,
                    "combination":    combination,
                    "direction":      sig.direction,
                    "reference_low":  round(sig.reference_low,  5),
                    "reference_high": round(sig.reference_high, 5),
                    "sweep_low":      round(sig.sweep_low,  5),
                    "sweep_high":     round(sig.sweep_high, 5),
                    "reclaim_open":   round(sig.reclaim_open,  5),
                    "reclaim_high":   round(sig.reclaim_high,  5),
                    "reclaim_low":    round(sig.reclaim_low,   5),
                    "reclaim_close":  round(sig.reclaim_close, 5),
                    "displacement_open":   round(sig.displacement_open,  5),
                    "displacement_high":   round(sig.displacement_high,  5),
                    "displacement_low":    round(sig.displacement_low,   5),
                    "displacement_close":  round(sig.displacement_close, 5),
                    "atr_m15":        round(sig.atr_m15, 6),
                    "tick_size":      TICK_SIZE,
                    "tick_value":     TICK_VALUE_PER_LOT,
                    "contract_size":  CONTRACT_SIZE,
                    "volume_min":     VOLUME_MIN,
                    "volume_step":    VOLUME_STEP,
                    "spread_price":   round(sig.spread_price, 6),
                    "slippage_price": round(TICK_SIZE * 10, 6),  # 1 pip slippage reserve
                    "commission_per_lot_round_trip": COMMISSION_PER_LOT,
                    **{k: ("" if v is None else v) for k, v in exit_data.items()},
                }
                writer.writerow(row)
                events_written += 1
                if verbose:
                    print(f"  {day_str}: SIGNAL {sig.direction} entry={sig.entry_price:.5f} "
                          f"stop={sig.stop_price:.5f} atr={sig.atr_m15:.6f}")

    stats.print_summary()
    print(f"\nDone.  Signal events written: {events_written:,}")
    print(f"Output: {output_file}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tick-file",   required=True,  type=Path)
    parser.add_argument("--output",      required=True,  type=Path)
    parser.add_argument("--combination", default="EURUSD_LONDON")
    parser.add_argument("--verbose",     action="store_true",
                        help="Print per-day status (which gate killed each day)")
    args = parser.parse_args()

    if not args.tick_file.exists():
        print(f"ERROR: tick file not found: {args.tick_file}", file=sys.stderr)
        sys.exit(1)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    process_file(args.tick_file, args.output, args.combination,
                 verbose=args.verbose)


if __name__ == "__main__":
    main()
