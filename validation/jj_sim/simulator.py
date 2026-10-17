"""
JJ Simon 1-Minute Fair Pricing — Prop-Firm Pass-Rate Simulator
==============================================================

Implements the methodology described in docs/strategy/JJ-SIMON-1MIN-FAIR-PRICING-STRATEGY.md.

Key design choices
------------------
* Metric is **pass rate across many simulated evaluation accounts**, not single-account
  equity-curve CAGR / Sharpe. This matches the prop-firm math in JJ's framework.
* All signals are pure functions over a rolling window of M1 bars so they can be unit
  tested against labelled candles independently from the simulator.
* The simulator replays M1 bars chronologically and opens trades on "virtual" accounts
  according to a deterministic layering policy (one trade per setup per account, up to
  N accounts). Each account has its own independent P&L and is checked against the
  firm's rules (trailing drawdown, daily loss, profit target, min days).
* Session windows are in US/Eastern (EST/EDT resolved via pytz).
* Static RR: TP is optimized first (to fair price, capped by RR), SL is the reciprocal.
* Three consecutive reversion losses in a session ⇒ stop trading reversions that session.

Run
---
    python3 jj_sim/simulator.py --data <csv> --accounts 50 --config eval_1to1_5
    python3 jj_sim/simulator.py --synthetic 500 --accounts 50 --config eval_1to1_5

A smoke-test run on synthetic data is executed automatically when this module is run
with no arguments.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import random
import sys  # noqa: E402
from dataclasses import dataclass, field, asdict
from datetime import datetime, time, timedelta, timezone
from enum import Enum
from typing import Callable, Iterable, Iterator

import numpy as np
import pandas as pd
import pytz


# ---------------------------------------------------------------------------
# Time / session constants
# ---------------------------------------------------------------------------

NY_TZ = pytz.timezone("US/Eastern")
UTC = pytz.UTC

# Default session windows (wall-clock in US/Eastern, independent of DST)
NY_AM_OPEN = time(9, 30)
NY_AM_CLOSE = time(11, 0)
NY_PM_OPEN = time(14, 0)
NY_PM_CLOSE = time(15, 30)
DEAD_ZONE_START = time(11, 0)
DEAD_ZONE_END = time(14, 0)


class Window(Enum):
    NY_AM = "ny_am"
    NY_PM = "ny_pm"
    DEAD = "dead"
    CLOSED = "closed"


def ny_window(ts: pd.Timestamp) -> Window:
    """Return the NY session window for a tz-aware UTC timestamp."""
    t = ts.tz_convert(NY_TZ).time()
    if NY_AM_OPEN <= t < NY_AM_CLOSE:
        return Window.NY_AM
    if NY_PM_OPEN <= t < NY_PM_CLOSE:
        return Window.NY_PM
    if DEAD_ZONE_START <= t < DEAD_ZONE_END:
        return Window.DEAD
    return Window.CLOSED


# ---------------------------------------------------------------------------
# Account / firm-rule configuration
# ---------------------------------------------------------------------------

@dataclass
class FirmRules:
    """Prop-firm challenge or funded-account rules.

    All percentages are of starting balance unless noted.
    """
    name: str = "eval_1to1_5"
    start_balance: float = 2_500.0
    profit_target_pct: float = 0.10           # 10% target; use a value >= 1.0 for "grow only"
    overall_drawdown_pct: float = 0.10        # 10% max loss (static or trailing)
    daily_loss_pct: float = 0.05              # 5% daily
    trailing_drawdown: bool = False           # True = DD tracked from peak balance
    consistency_rule: bool = False            # True = biggest-win-day ≤ 50% of total profits
    consistency_max_day_pct: float = 0.50
    min_profitable_days: int = 0              # e.g. The5ers requires 3
    min_profit_per_day_pct: float = 0.005     # 0.5% to count as profitable day
    risk_per_trade_pct: float = 0.01          # 1% risk per trade
    rr: float = 1.5                           # risk-to-reward
    eval_price: float = 100.0                 # cost of the evaluation (for EV math)
    payout_rate: float = 0.30                 # prob you actually get paid (breach/firm risk)
    expected_payout_per_funded: float = 2000.0  # expected $ collected on a funded acct
    grow_only: bool = False                   # if True, there is no upper profit target —
                                              # used for funded "grow" accounts where
                                              # pass/fail is measured differently

    @classmethod
    def presets(cls) -> dict[str, "FirmRules"]:
        return {
            "eval_1to1": cls(
                name="eval_1to1",
                start_balance=2_500.0, profit_target_pct=0.08,
                overall_drawdown_pct=0.08, daily_loss_pct=0.04,
                trailing_drawdown=False, rr=1.0, risk_per_trade_pct=0.01,
            ),
            "eval_1to1_5": cls(
                name="eval_1to1_5",
                start_balance=2_500.0, profit_target_pct=0.10,
                overall_drawdown_pct=0.10, daily_loss_pct=0.05,
                trailing_drawdown=True, rr=1.5, risk_per_trade_pct=0.0075,
            ),
            "funded_consistency": cls(
                name="funded_consistency",
                start_balance=25_000.0, profit_target_pct=0.10,  # 10% target then payout tier
                overall_drawdown_pct=0.06, daily_loss_pct=0.03,
                trailing_drawdown=True, consistency_rule=True,
                rr=1.5, risk_per_trade_pct=0.005,
                eval_price=0.0, expected_payout_per_funded=2_000.0,
            ),
            "funded_noconsistency": cls(
                name="funded_noconsistency",
                start_balance=25_000.0, profit_target_pct=0.10,
                overall_drawdown_pct=0.06, daily_loss_pct=0.03,
                trailing_drawdown=True, rr=4.0, risk_per_trade_pct=0.005,
                eval_price=0.0, expected_payout_per_funded=2_000.0,
            ),
            "the5ers_2500": cls(
                name="the5ers_2500",
                start_balance=2_500.0, profit_target_pct=0.10,
                overall_drawdown_pct=0.10, daily_loss_pct=0.05,
                trailing_drawdown=True, rr=1.5, risk_per_trade_pct=0.005,
                min_profitable_days=3, min_profit_per_day_pct=0.005,
                eval_price=19.0,
            ),
        }


# ---------------------------------------------------------------------------
# Trade / signal data structures
# ---------------------------------------------------------------------------

class Side(Enum):
    LONG = 1
    SHORT = -1


class SignalType(Enum):
    DISPLACEMENT = "DC"
    BREAK_OF_STRUCTURE = "BoS"
    NEWS_REVERSION = "NR"
    SESSION_OPEN_CONTINUATION = "SOC"


@dataclass
class Signal:
    bar_index: int
    timestamp: pd.Timestamp
    type: SignalType
    side: Side
    fair_price: float        # reversion target (TP)
    entry_price: float       # intended entry (close of signal bar)
    strength: float = 1.0    # 0..1 quality score for diagnostics
    window: Window = Window.CLOSED


@dataclass
class Trade:
    trade_id: int
    account_id: int
    signal: Signal
    entry_price: float
    tp: float
    sl: float
    risk_dollars: float
    contracts: float
    side: Side
    entry_bar: int
    entry_time: pd.Timestamp

    exit_price: float | None = None
    exit_time: pd.Timestamp | None = None
    exit_bar: int | None = None
    pnl_dollars: float = 0.0
    won: bool | None = None    # True=hit TP, False=hit SL


# ---------------------------------------------------------------------------
# Signal detectors (pure, testable)
# ---------------------------------------------------------------------------

def median_body_size(bars: np.ndarray, lookback: int, end: int) -> float:
    """Median |close - open| of the `lookback` bars ending at (but not including) `end`.

    Falls back to median candle range when bodies are all zero (e.g. flat doji
    periods), so that a large displacement is still detectable in quiet markets.
    """
    start = max(0, end - lookback)
    bodies = np.abs(bars["close"][start:end] - bars["open"][start:end])
    if len(bodies) == 0:
        return 0.0
    med = float(np.median(bodies))
    if med > 0:
        return med
    # fallback: median range
    rng = bars["high"][start:end] - bars["low"][start:end]
    return float(np.median(rng)) if len(rng) else 0.0


def detect_displacement(
    bars: np.ndarray, i: int, fair_price: float,
    body_mult: float = 1.5, lookback: int = 10, wick_tol: float = 0.10,
) -> Signal | None:
    """Detect a displacement candle at bar `i`.

    Rules (per §5.1 of the spec):
      * body > body_mult * median(lookback) body size
      * candle commits in one direction (close within wick_tol*body of the extreme wick
        on the displacement side)
      * displacement is AWAY from fair price (e.g. if fair > close, displacement is
        downward ⇒ reversion is LONG)
    """
    # Need at least `lookback` prior bars (indices 0..i-1) to compute median body.
    # i is the candidate bar; prior bars are [max(0, i-lookback) .. i-1], which is
    # non-empty as long as i >= 1. For a stable median we require i >= lookback.
    if i < lookback:
        return None
    o, h, l, c = bars["open"][i], bars["high"][i], bars["low"][i], bars["close"][i]
    body = abs(c - o)
    med = median_body_size(bars, lookback, i)
    if med == 0 or body < body_mult * med:
        return None
    bullish = c > o
    # Commitment check: close near the extreme in the direction of the candle
    if bullish:
        if c < h - wick_tol * body:
            return None
        # Displacement is upward (price moved away from fair); we SHORT the reversion
        # only when fair price is BELOW the displaced close (i.e. we overshot upward).
        if fair_price > c:
            return None
        side = Side.SHORT
    else:
        if c > l + wick_tol * body:
            return None
        # Displacement downward; LONG the reversion only when fair is ABOVE the close.
        if fair_price < c:
            return None
        side = Side.LONG
    return Signal(
        bar_index=i,
        timestamp=bars["ts_dt"][i],
        type=SignalType.DISPLACEMENT,
        side=side,
        fair_price=float(fair_price),
        entry_price=float(c),
        strength=float(min(1.0, body / (body_mult * med * 2))),
        window=ny_window(bars["ts_dt"][i]),
    )


def detect_bos(
    bars: np.ndarray, i: int, fair_price: float, swing_lookback: int = 2,
) -> Signal | None:
    """Break of structure (§5.2).

    A swing wick (local high/low across 2*swing_lookback + 1 bars, centered on a pivot
    bar p) was set; bar i closes back THROUGH that wick in the direction of fair price.
    Implementation: we look back up to 15 bars for the most recent qualifying pivot
    and require that bar i's close breaks through it in the fair-price direction.
    """
    # Need swing_lookback bars on each side of a pivot; the pivot can be as far as
    # (i - swing_lookback - 1), and we need at least that in lookback.
    if i < swing_lookback * 2 + 1:
        return None
    # Find the most recent pivot low/high in the last 15 bars
    search_start = max(swing_lookback * 2 + 1, i - 15)
    best_pivot_idx = None
    best_pivot_price = None
    # bias direction: positive = reversion is LONG (fair above current price)
    bias_up = fair_price > bars["close"][i]
    for p in range(search_start, i - swing_lookback):
        window = bars["low" if bias_up else "high"][p - swing_lookback : p + swing_lookback + 1]
        if len(window) < swing_lookback * 2 + 1:
            continue
        extreme = window.min() if bias_up else window.max()
        center = bars["low"][p] if bias_up else bars["high"][p]
        if abs(center - extreme) < 1e-12:
            # p is a local extreme in the bias direction
            best_pivot_idx = p
            best_pivot_price = float(center)
            break
    if best_pivot_idx is None:
        return None
    # Confirm break of that pivot on bar i
    c = bars["close"][i]
    if bias_up and c <= best_pivot_price:
        return None
    if not bias_up and c >= best_pivot_price:
        return None
    side = Side.LONG if bias_up else Side.SHORT
    return Signal(
        bar_index=i,
        timestamp=bars["ts_dt"][i],
        type=SignalType.BREAK_OF_STRUCTURE,
        side=side,
        fair_price=float(fair_price),
        entry_price=float(c),
        strength=0.7,
        window=ny_window(bars["ts_dt"][i]),
    )


# ---------------------------------------------------------------------------
# Fair-price model
# ---------------------------------------------------------------------------

class FairPriceModel:
    """Tracks fair price across sessions and news events.

    * At each new NY AM (9:30) and NY PM (14:00) the fair price resets to the open of
      that session's first bar.
    * On session-open continuation the fair price drifts with the first impulse
      (disabled by default; §5.4 optional).
    * After 3 consecutive reversion losses the fair price is considered "moved"
      for that session and reversions are turned off for the rest of the window.
    * News events: if an expected-news event fires, fair price stays at pre-news
      consolidation. If an unexpected-news event fires, fair price becomes the
      post-move consolidation after cooldown bars.
    """

    def __init__(self, soc_enabled: bool = False, unexpected_cooldown_bars: int = 5):
        self.soc_enabled = soc_enabled
        self.unexpected_cooldown_bars = unexpected_cooldown_bars
        self.fair_price: float | None = None
        self.current_window: Window = Window.CLOSED
        self.session_open_price: float | None = None
        self.session_start_bar: int = -1
        self.consecutive_losses = 0
        self.session_locked_out = False  # set after 3 consecutive losses
        # News state
        self.pending_news: dict | None = None  # expected news pre-level
        self.post_unexpected_bars: int = 0
        self.unexpected_consolidation_low: float = 0.0
        self.unexpected_consolidation_high: float = 0.0

    def on_bar(
        self,
        bars: np.ndarray,
        i: int,
        news_events: list[dict],
    ) -> None:
        ts = bars["ts_dt"][i]
        w = ny_window(ts)

        # Session transitions
        if w != self.current_window:
            if w in (Window.NY_AM, Window.NY_PM):
                # Use open price of this bar as the session open (entry bar of the window)
                self.session_open_price = float(bars["open"][i])
                self.fair_price = self.session_open_price
                self.session_start_bar = i
                self.consecutive_losses = 0
                self.session_locked_out = False
            elif w == Window.DEAD:
                # Between NY AM and NY PM: keep the PM open to reset
                self.fair_price = None
            else:
                self.fair_price = None
            self.current_window = w

        # News events that land on this bar
        for ev in news_events:
            if ev["time"] == ts:
                if ev["kind"] == "expected":
                    # pre-news close is the consolidation fair price
                    self.pending_news = {
                        "pre_price": float(bars["close"][i - 1] if i > 0 else bars["open"][i]),
                        "event_bar": i,
                        "big_move_thresh": ev.get("big_move_mult", 1.5),
                    }
                elif ev["kind"] == "unexpected":
                    # After cooldown, use consolidation as new fair price
                    self.post_unexpected_bars = self.unexpected_cooldown_bars
                    self.unexpected_consolidation_low = float(bars["low"][i])
                    self.unexpected_consolidation_high = float(bars["high"][i])
                    self.fair_price = None  # not yet known

        # Expected-news first post bar
        if self.pending_news is not None and i == self.pending_news["event_bar"] + 1:
            # Check for big-move miss
            move = abs(bars["close"][i] - self.pending_news["pre_price"])
            atr12 = _atr12(bars, i)
            if atr12 > 0 and move > 3.0 * atr12:
                # Treat as unexpected
                self.post_unexpected_bars = self.unexpected_cooldown_bars
                self.unexpected_consolidation_low = float(bars["low"][i])
                self.unexpected_consolidation_high = float(bars["high"][i])
                self.fair_price = None
                self.pending_news = None
            else:
                self.fair_price = self.pending_news["pre_price"]
                self.session_locked_out = False
                self.consecutive_losses = 0

        # Countdown after unexpected
        if self.post_unexpected_bars > 0:
            self.unexpected_consolidation_low = min(
                self.unexpected_consolidation_low, float(bars["low"][i]))
            self.unexpected_consolidation_high = max(
                self.unexpected_consolidation_high, float(bars["high"][i]))
            self.post_unexpected_bars -= 1
            if self.post_unexpected_bars == 0:
                self.fair_price = (
                    self.unexpected_consolidation_low + self.unexpected_consolidation_high
                ) / 2.0
                self.session_locked_out = False
                self.consecutive_losses = 0

    def register_trade_result(self, won: bool) -> None:
        if won:
            self.consecutive_losses = 0
        else:
            self.consecutive_losses += 1
            if self.consecutive_losses >= 3:
                self.session_locked_out = True

    def can_trade(self) -> bool:
        if self.current_window in (Window.DEAD, Window.CLOSED):
            return False
        if self.fair_price is None:
            return False
        if self.session_locked_out:
            return False
        return True

    def current_fair_price(self) -> float | None:
        return self.fair_price


def _atr12(bars: np.ndarray, i: int) -> float:
    """12-period ATR in price units (simple, not RMA)."""
    start = max(1, i - 12)
    trs = []
    for j in range(start, i + 1):
        h = bars["high"][j]
        l = bars["low"][j]
        pc = bars["close"][j - 1]
        trs.append(max(h - l, abs(h - pc), abs(l - pc)))
    if not trs:
        return 0.0
    return float(np.mean(trs))


# ---------------------------------------------------------------------------
# Virtual account
# ---------------------------------------------------------------------------

@dataclass
class Account:
    account_id: int
    rules: FirmRules
    balance: float = 0.0
    peak_balance: float = 0.0
    day_start_balance: float = 0.0
    day_start_equity: float = 0.0
    current_day: object = None
    profitable_days: int = 0
    trades_taken: int = 0
    wins: int = 0
    losses: int = 0
    open_trade: Trade | None = None
    status: str = "active"     # active | passed | failed
    failure_reason: str = ""
    daily_pnls: list[float] = field(default_factory=list)
    closed_trades: list[Trade] = field(default_factory=list)

    def __post_init__(self):
        self.balance = float(self.rules.start_balance)
        self.peak_balance = self.balance
        self.day_start_balance = self.balance

    def equity(self, current_price: float | None = None) -> float:
        if self.open_trade is None:
            return self.balance
        if current_price is None:
            return self.balance
        t = self.open_trade
        direction = 1.0 if t.side == Side.LONG else -1.0
        # convert point pnl to dollars
        point_pnl = (current_price - t.entry_price) * direction
        dollars_per_point = t.risk_dollars / abs(t.entry_price - t.sl)
        return self.balance + point_pnl * dollars_per_point

    def day_pnl(self, current_price: float | None = None) -> float:
        return self.equity(current_price) - self.day_start_balance


# ---------------------------------------------------------------------------
# Prop-firm rule checker
# ---------------------------------------------------------------------------

def check_rules(acct: Account, current_price: float) -> None:
    """Update acct.status if any rule is breached or target met."""
    if acct.status != "active":
        return
    eq = acct.equity(current_price)
    # Daily loss
    day_pnl = eq - acct.day_start_balance
    if day_pnl <= -acct.rules.daily_loss_pct * acct.rules.start_balance:
        acct.status = "failed"
        acct.failure_reason = f"daily loss breached ({day_pnl:.2f})"
        return
    # Overall / trailing drawdown
    floor = acct.rules.start_balance * (1 - acct.rules.profit_target_pct if False
                                        else 1 - acct.rules.overall_drawdown_pct)
    if acct.rules.trailing_drawdown:
        floor = acct.peak_balance - acct.rules.overall_drawdown_pct * acct.rules.start_balance
    if eq <= floor:
        acct.status = "failed"
        acct.failure_reason = f"drawdown floor breached (eq={eq:.2f}, floor={floor:.2f})"
        return
    # Profit target
    target = acct.rules.start_balance * (1 + acct.rules.profit_target_pct)
    # grow_only accounts have no fixed upper target
    if not acct.rules.grow_only and acct.rules.profit_target_pct < 1.0 and eq >= target:
        if acct.rules.min_profitable_days and acct.profitable_days < acct.rules.min_profitable_days:
            return  # wait for more qualifying days
        if acct.rules.consistency_rule:
            # biggest day ≤ consistency_max_day_pct * total profit
            total_profit = eq - acct.rules.start_balance
            if total_profit > 0 and acct.daily_pnls:
                biggest = max(acct.daily_pnls) if acct.daily_pnls else 0
                if biggest > acct.rules.consistency_max_day_pct * total_profit:
                    return  # not yet consistent
        acct.status = "passed"


def roll_day_if_needed(acct: Account, current_ts: pd.Timestamp, current_price: float) -> None:
    day = current_ts.tz_convert(NY_TZ).date()
    if acct.current_day is None:
        acct.current_day = day
        acct.day_start_balance = acct.balance
        acct.day_start_equity = acct.equity(current_price)
        return
    if day != acct.current_day:
        # Close of prior day in NY time: snapshot at 17:00 NY approx
        day_pnl = acct.balance - acct.day_start_balance  # trades should be flat by then
        acct.daily_pnls.append(day_pnl)
        if acct.balance > acct.day_start_balance * (1 + acct.rules.min_profit_per_day_pct):
            # Use start-balance pct threshold per the firm rule
            if day_pnl >= acct.rules.min_profit_per_day_pct * acct.rules.start_balance:
                acct.profitable_days += 1
        acct.current_day = day
        acct.day_start_balance = acct.balance
        acct.peak_balance = max(acct.peak_balance, acct.balance)


# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------

REQUIRED_COLS = ["timestamp", "open", "high", "low", "close", "volume"]


def load_m1_csv(path: str, max_rows: int | None = None,
                timestamp_col: str | None = None,
                tz: str = "UTC") -> np.ndarray:
    """Load M1 OHLCV CSV into a structured numpy array with tz-aware UTC timestamps.

    Supports two layouts auto-detected from the columns:

    * ``timestamp,open,high,low,close,volume`` with epoch-millisecond timestamps
      (existing forex CSVs in validation/HistoryData/m1-data).
    * ``datetime,open,high,low,close,volume`` with ISO-8601 datetimes (CME futures
      datasets such as axb0306/cme-futures-ohlc, whose MNQ/NQ CSVs are already UTC).

    Parameters
    ----------
    timestamp_col : override the timestamp column name (else auto-detect).
    tz : timezone for naive ISO strings; default "UTC".
    """
    df = pd.read_csv(path, nrows=max_rows)
    if timestamp_col is None:
        for cand in ("timestamp", "datetime", "Date", "date", "time", "Time"):
            if cand in df.columns:
                timestamp_col = cand
                break
        if timestamp_col is None:
            raise ValueError(
                f"{path}: no timestamp column. Found: {list(df.columns)}")
    required = ["open", "high", "low", "close"]
    missing = [c for c in required if c not in df.columns]
    if missing:
        raise ValueError(f"{path} is missing columns: {missing}")
    if "volume" not in df.columns:
        df["volume"] = 0.0

    col = df[timestamp_col]
    if pd.api.types.is_numeric_dtype(col):
        ts = pd.to_datetime(col, unit="ms", utc=True)
    else:
        ts = pd.to_datetime(col, utc=True)
        if ts.dt.tz is None:
            ts = ts.dt.tz_localize(tz)
        if str(ts.dt.tz) != "UTC":
            ts = ts.dt.tz_convert("UTC")
    df["timestamp"] = ts
    df = df[["timestamp", "open", "high", "low", "close", "volume"]]
    df = df.sort_values("timestamp").reset_index(drop=True)

    arr = np.zeros(len(df), dtype=[
        ("ts", "i8"), ("open", "f8"), ("high", "f8"),
        ("low", "f8"), ("close", "f8"), ("volume", "f8"),
        ("ts_dt", "O"),
    ])
    arr["ts"] = df["timestamp"].astype("int64").values // 10**6
    arr["open"] = df["open"].values
    arr["high"] = df["high"].values
    arr["low"] = df["low"].values
    arr["close"] = df["close"].values
    arr["volume"] = df["volume"].values
    arr["ts_dt"] = df["timestamp"].tolist()
    return arr


def load_news_csv(path: str) -> list[dict]:
    """Load news events CSV with columns: timestamp_iso, kind (expected|unexpected),
    big_move_mult (optional)."""
    events = []
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            ts = pd.Timestamp(row["timestamp_iso"]).tz_convert(UTC)
            events.append({
                "time": ts,
                "kind": row["kind"],
                "big_move_mult": float(row.get("big_move_mult", 1.5)),
            })
    events.sort(key=lambda e: e["time"])
    return events


# ---------------------------------------------------------------------------
# Synthetic data generator (for smoke testing)
# ---------------------------------------------------------------------------

def generate_synthetic_m1(
    n_sessions: int = 250,
    p_reversal: float = 0.58,
    seed: int = 7,
) -> tuple[np.ndarray, list[dict]]:
    """Generate a synthetic NQ-like M1 series with fair-price session dynamics.

    Each NY AM session gets a random opening displacement away from the prior close;
    with probability p_reversal the price reverts to the open; otherwise it trends.
    A few expected-news events are injected (on average one every 10 sessions).
    Returns (bars, news_events).
    """
    rng = random.Random(seed)
    np_rng = np.random.default_rng(seed)
    tz = NY_TZ
    # Start on a Monday in Sep 2024
    start_date = datetime(2024, 9, 9, 9, 30, tzinfo=tz)
    price = 20000.0
    point_value = 0.25  # NQ quarter-point
    bars: list[tuple] = []
    events: list[dict] = []
    day = start_date
    sessions_made = 0
    while sessions_made < n_sessions:
        # Skip weekends
        if day.weekday() >= 5:
            day += timedelta(days=1)
            day = day.replace(hour=9, minute=30)
            continue
        session_open = price
        # Expected news at 8:31 occasionally — synthesise as a pre-move spike before 9:30
        news_today = sessions_made % 10 == 0 and sessions_made > 0
        if news_today:
            # Add 8:31 bar(s) as the post-news displacement
            pre_news = price
            news_time = day.replace(hour=8, minute=31)
            # pre-news consolidation (5 bars)
            for k in range(5, 0, -1):
                bt = news_time - timedelta(minutes=k)
                bars.append((bt, price, price + 5, price - 5, price, 100))
            # big displacement candle
            direction = 1 if rng.random() < 0.5 else -1
            disp = rng.uniform(80, 160) * point_value * direction
            new_close = price + disp
            events.append({"time": pd.Timestamp(news_time).tz_convert(UTC),
                           "kind": "expected", "big_move_mult": 1.5})
            bars.append((
                news_time, price, max(price, new_close) + 5,
                min(price, new_close) - 5, new_close, 500,
            ))
            price = new_close
            # then trade 9:30 onwards — reversion if p_reversal
            current = day
        # Generate 90 minutes of NY AM bars
        current = day
        open_price = price
        # First bar displacement away from open
        direction = 1 if rng.random() < 0.5 else -1
        impulse = rng.uniform(40, 120) * point_value * direction
        # Walk to the extreme in the first 5 bars
        extreme = open_price + impulse
        n_bars = 90
        for m in range(n_bars):
            bt = current + timedelta(minutes=m)
            if m < 5:
                # continuation toward extreme
                t = (m + 1) / 5
                p = open_price + impulse * t
                hl_range = rng.uniform(3, 10) * point_value
                h = p + hl_range
                l = p - hl_range
                c = p + np_rng.normal(0, 2 * point_value)
                h, l = max(h, c), min(l, c)
                bars.append((bt, p, h, l, c, rng.randint(200, 600)))
            else:
                # Decide: revert to open (p_reversal) or trend
                remaining = n_bars - m
                if rng.random() < p_reversal:
                    # pull back toward open_price linearly plus noise
                    t = (m - 4) / (n_bars - 5)
                    target = extreme + (open_price - extreme) * t
                else:
                    # trend further in direction of impulse
                    per_bar = impulse / 60
                    target = extreme + per_bar * (m - 4)
                p = target + np_rng.normal(0, 6 * point_value)
                hl_range = rng.uniform(4, 12) * point_value
                h = p + hl_range
                l = p - hl_range
                c = p + np_rng.normal(0, 3 * point_value)
                h, l = max(h, c), min(l, c)
                bars.append((bt, target, h, l, c, rng.randint(200, 600)))
        price = bars[-1][4]  # close
        sessions_made += 1
        day = (day + timedelta(days=1)).replace(hour=9, minute=30)

    # Convert bars to structured array with UTC timestamps
    arr = np.zeros(len(bars), dtype=[
        ("ts", "i8"), ("open", "f8"), ("high", "f8"),
        ("low", "f8"), ("close", "f8"), ("volume", "f8"),
        ("ts_dt", "O"),
    ])
    for i, (bt, o, h, l, c, v) in enumerate(bars):
        ts_utc = pd.Timestamp(bt).tz_convert(UTC)
        arr["ts"][i] = ts_utc.value // 10**6  # ms for consistency with CSV format
        arr["open"][i] = o
        arr["high"][i] = h
        arr["low"][i] = l
        arr["close"][i] = c
        arr["volume"][i] = v
        arr["ts_dt"][i] = ts_utc
    return arr, events


# ---------------------------------------------------------------------------
# Simulation core
# ---------------------------------------------------------------------------

@dataclass
class SimulationResult:
    accounts: list[Account]
    signals_fired: int
    trades_taken: int
    pass_rate: float
    cost_per_funded: float
    ev_per_funded: float
    ev_per_eval_dollar: float
    per_signal_stats: dict
    timeline_passes_by_bar: list[int]
    timeline_fails_by_bar: list[int]
    rules: FirmRules

    def summary(self) -> str:
        lines = []
        lines.append(f"=== Sim result: {self.rules.name} ===")
        lines.append(f"  accounts        : {len(self.accounts)}")
        lines.append(f"  signals fired   : {self.signals_fired}")
        lines.append(f"  trades taken    : {self.trades_taken}")
        passed = sum(1 for a in self.accounts if a.status == "passed")
        failed = sum(1 for a in self.accounts if a.status == "failed")
        active = len(self.accounts) - passed - failed
        lines.append(f"  passed / failed / active : {passed} / {failed} / {active}")
        lines.append(f"  pass rate       : {self.pass_rate*100:.2f}%")
        lines.append(f"  cost / funded   : ${self.cost_per_funded:.2f}")
        lines.append(f"  EV per funded   : ${self.ev_per_funded:.2f}")
        lines.append(f"  EV per $1 eval  : ${self.ev_per_eval_dollar:.2f}")
        win = sum(a.wins for a in self.accounts)
        loss = sum(a.losses for a in self.accounts)
        total = win + loss
        lines.append(f"  total closed t  : {total}  win rate: {win / total * 100:.2f}%"
                     if total else "  total closed t  : 0")
        lines.append(f"  per-signal stats:")
        for k, v in self.per_signal_stats.items():
            tot = v["wins"] + v["losses"]
            wr = v["wins"] / tot * 100 if tot else 0
            lines.append(f"    {k:6s}: {v['trades']} trades, winrate {wr:.1f}%")
        # reasons for failure
        reasons: dict[str, int] = {}
        for a in self.accounts:
            if a.status == "failed":
                reasons[a.failure_reason.split("(")[0].strip()] = \
                    reasons.get(a.failure_reason.split("(")[0].strip(), 0) + 1
        if reasons:
            lines.append("  failure reasons :")
            for r, n in sorted(reasons.items(), key=lambda kv: -kv[1]):
                lines.append(f"    {r}: {n}")
        if math.isnan(self.cost_per_funded):
            verdict = "N/A (no eval cost — already funded)"
        else:
            verdict = ("PROFITABLE (EV > cost)"
                       if self.ev_per_funded > self.cost_per_funded
                       else "NOT PROFITABLE (EV <= cost)")
        lines.append(f"  verdict         : {verdict}")
        return "\n".join(lines)


def simulate(
    bars: np.ndarray,
    rules: FirmRules,
    n_accounts: int = 50,
    news_events: list[dict] | None = None,
    signals_enabled: dict[str, bool] | None = None,
    max_trades_per_account_per_session: int = 1,
    point_value_per_dollar: float = 1.0,  # set to NQ multiplier (e.g. $20/point for NQ futures)
    progress_every: int = 0,
) -> SimulationResult:
    """Run n_accounts virtual accounts through the M1 series and return results.

    Layering model
    --------------
    We maintain a pool of n_accounts accounts. For each signal, we pick an account
    that (a) is active, (b) has no open trade, (c) has not yet taken
    max_trades_per_account_per_session trades in the current session. This emulates
    JJ's "one trade per account per setup" layering: a new signal = a fresh account
    is preferred, but an account that already closed a trade earlier in the session
    may also re-enter if accounts are scarce.
    """
    if signals_enabled is None:
        signals_enabled = {"DC": True, "BoS": True, "NR": True, "SOC": False}
    if news_events is None:
        news_events = []

    accounts = [Account(account_id=i, rules=rules) for i in range(n_accounts)]
    fp = FairPriceModel(soc_enabled=signals_enabled.get("SOC", False))

    signals_fired = 0
    trades_taken = 0
    per_signal: dict[str, dict] = {
        s.value: {"trades": 0, "wins": 0, "losses": 0} for s in SignalType
    }
    pass_timeline: list[int] = []
    fail_timeline: list[int] = []
    news_idx = 0
    # group news by bar timestamp
    news_by_ts: dict[pd.Timestamp, list[dict]] = {}
    for ev in news_events:
        news_by_ts.setdefault(ev["time"], []).append(ev)

    n = len(bars)
    for i in range(n):
        ts = bars["ts_dt"][i]
        # Events firing at this bar
        events_now = news_by_ts.get(ts, [])
        fp.on_bar(bars, i, events_now)

        # Update open trades (check TP/SL hit during this bar)
        price = float(bars["close"][i])
        high = float(bars["high"][i])
        low = float(bars["low"][i])
        for acct in accounts:
            if acct.open_trade is None:
                continue
            t = acct.open_trade
            # Determine if SL or TP was hit first (use simple wick-touch heuristic:
            # if both sides touched in the same bar, assume SL first for conservatism).
            hit_sl = hit_tp = False
            if t.side == Side.LONG:
                if low <= t.sl:
                    hit_sl = True
                elif high >= t.tp:
                    hit_tp = True
            else:
                if high >= t.sl:
                    hit_sl = True
                elif low <= t.tp:
                    hit_tp = True
            if hit_sl or hit_tp:
                won = hit_tp and not hit_sl
                exit_price = t.tp if won else t.sl
                pnl = t.risk_dollars * rules.rr if won else -t.risk_dollars
                t.exit_price = exit_price
                t.exit_time = ts
                t.exit_bar = i
                t.pnl_dollars = pnl
                t.won = won
                acct.balance += pnl
                acct.trades_taken += 1
                if won:
                    acct.wins += 1
                else:
                    acct.losses += 1
                per_signal[t.signal.type.value]["trades"] += 1
                per_signal[t.signal.type.value]["wins" if won else "losses"] += 1
                acct.closed_trades.append(t)
                acct.open_trade = None
                fp.register_trade_result(won)
                acct.peak_balance = max(acct.peak_balance, acct.balance)

        # Roll day (NY time) and check rules for all accounts (use current close)
        for acct in accounts:
            roll_day_if_needed(acct, ts, price)
            check_rules(acct, price)

        # Record timelines every full NY AM close for monitoring
        if ny_window(ts) == Window.NY_AM and i + 1 < n and \
                ny_window(bars["ts_dt"][i + 1]) != Window.NY_AM:
            pass_timeline.append(sum(1 for a in accounts if a.status == "passed"))
            fail_timeline.append(sum(1 for a in accounts if a.status == "failed"))

        # Signal detection & entry
        if not fp.can_trade():
            continue
        fair = fp.current_fair_price()
        if fair is None:
            continue
        # Detect each enabled signal type
        signals: list[Signal] = []
        # News reversion: if pending_news armed AND fair == pre_price AND we are one bar
        # after event, fire NR
        if signals_enabled.get("NR", True) and fp.pending_news is not None \
                and i == fp.pending_news["event_bar"] + 1:
            p = fp.pending_news["pre_price"]
            side = Side.LONG if p > price else Side.SHORT
            # Only fire if displacement is actually away
            if abs(price - p) > 0:
                signals.append(Signal(
                    bar_index=i, timestamp=ts, type=SignalType.NEWS_REVERSION,
                    side=side, fair_price=float(p), entry_price=price, strength=1.0,
                    window=ny_window(ts),
                ))
        if signals_enabled.get("DC", True):
            dc = detect_displacement(bars, i, fair)
            if dc is not None:
                signals.append(dc)
        if signals_enabled.get("BoS", True):
            bos = detect_bos(bars, i, fair)
            if bos is not None:
                signals.append(bos)

        for sig in signals:
            signals_fired += 1
            # Entry sizing — constant dollar risk
            # points to TP = abs(fair - entry) (capped by RR so SL = TP/RR is paired)
            pts_to_fair = abs(sig.fair_price - sig.entry_price)
            rr = rules.rr
            # TP is min(fair price, entry + rr * SL_pts); since SL = TP/rr, we compute:
            # tp_pts = pts_to_fair  (aim at fair price) — but if that would make SL < ATR/noise floor
            # we clamp to keep SL out of noise (JJ: SL is "essentially random", just the reciprocal).
            tp_pts = pts_to_fair
            if tp_pts <= 0:
                continue
            sl_pts = tp_pts / rr
            risk_dollars = rules.risk_per_trade_pct * rules.start_balance
            # dollars per point: risk_dollars / sl_pts
            dpp = risk_dollars / sl_pts
            # contract count notional in "units" (for futures: dpp should equal
            # point_value_per_dollar * contracts). For instrument-agnostic simulation
            # we just track dollars and skip a separate contract field unless NQ
            # multiplier supplied.
            contracts = dpp / point_value_per_dollar if point_value_per_dollar else 1.0
            tp_price = sig.entry_price + tp_pts * sig.side.value
            sl_price = sig.entry_price - sl_pts * sig.side.value

            # Pick an account: prefer an active, flat account that hasn't used its
            # slot this session yet.
            acct = _pick_account(accounts, fp.session_start_bar, i,
                                 max_trades_per_account_per_session)
            if acct is None:
                continue  # no capacity this bar
            trade = Trade(
                trade_id=trades_taken,
                account_id=acct.account_id,
                signal=sig,
                entry_price=sig.entry_price,
                tp=tp_price,
                sl=sl_price,
                risk_dollars=risk_dollars,
                contracts=contracts,
                side=sig.side,
                entry_bar=i,
                entry_time=ts,
            )
            acct.open_trade = trade
            # Tag account with "used this session" via simple attribute
            acct.last_session_bar = fp.session_start_bar
            acct.session_trades = getattr(acct, "session_trades", 0) + 1
            trades_taken += 1

    # Final tally — close any still-open trades at last close (marked as forced-exit)
    last_price = float(bars["close"][-1])
    last_ts = bars["ts_dt"][-1]
    for acct in accounts:
        if acct.open_trade is not None:
            t = acct.open_trade
            direction = 1.0 if t.side == Side.LONG else -1.0
            pnl = (last_price - t.entry_price) * direction * \
                  (t.risk_dollars / abs(t.entry_price - t.sl))
            won = pnl > 0
            t.exit_price = last_price
            t.exit_time = last_ts
            t.exit_bar = n - 1
            t.pnl_dollars = pnl
            t.won = won
            acct.balance += pnl
            acct.trades_taken += 1
            if won:
                acct.wins += 1
            else:
                acct.losses += 1
            per_signal[t.signal.type.value]["trades"] += 1
            per_signal[t.signal.type.value]["wins" if won else "losses"] += 1
            acct.closed_trades.append(t)
            acct.open_trade = None
        check_rules(acct, last_price)

    passed = sum(1 for a in accounts if a.status == "passed")
    failed = sum(1 for a in accounts if a.status == "failed")
    pass_rate = passed / len(accounts) if accounts else 0.0
    if rules.eval_price > 0 and pass_rate > 0:
        cost_per_funded = rules.eval_price / pass_rate
    elif rules.eval_price == 0:
        cost_per_funded = float("nan")  # funded acct already paid for; cost is sunk
    else:
        cost_per_funded = float("inf")
    ev_per_funded = rules.expected_payout_per_funded * rules.payout_rate
    if rules.eval_price > 0:
        ev_per_eval_dollar = (ev_per_funded * pass_rate - rules.eval_price) / rules.eval_price
    else:
        ev_per_eval_dollar = float("nan")  # funded accts have no eval cost; EV/$ not defined

    return SimulationResult(
        accounts=accounts,
        signals_fired=signals_fired,
        trades_taken=trades_taken,
        pass_rate=pass_rate,
        cost_per_funded=cost_per_funded,
        ev_per_funded=ev_per_funded,
        ev_per_eval_dollar=ev_per_eval_dollar,
        per_signal_stats=per_signal,
        timeline_passes_by_bar=pass_timeline,
        timeline_fails_by_bar=fail_timeline,
        rules=rules,
    )


def _pick_account(
    accounts: list[Account],
    session_start_bar: int,
    current_bar: int,
    max_per_session: int,
) -> Account | None:
    """Find the best account to take the next signal: active, flat, fewest session trades."""
    candidates = [a for a in accounts if a.status == "active" and a.open_trade is None]
    if not candidates:
        return None
    # Prefer accounts that haven't traded in this session yet
    fresh = [a for a in candidates
             if getattr(a, "last_session_bar", -1) != session_start_bar]
    if fresh:
        return fresh[0]
    # Else allow accounts that have used < max_per_session trades this session
    available = [a for a in candidates
                 if getattr(a, "session_trades", 0) < max_per_session
                 or getattr(a, "last_session_bar", -1) != session_start_bar]
    # reset session_trades for accounts entering this session for first time? handled above.
    return available[0] if available else None


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv: list[str] | None = None):
    p = argparse.ArgumentParser(description="JJ Simon 1-min fair-pricing pass-rate simulator")
    p.add_argument("--data", type=str, help="path to M1 CSV (timestamp ms,OHLCV)")
    p.add_argument("--news", type=str, help="optional news events CSV")
    p.add_argument("--synthetic", type=int, default=0,
                   help="use N synthetic sessions instead of CSV data")
    p.add_argument("--accounts", type=int, default=50)
    p.add_argument("--config", type=str, default="eval_1to1_5",
                   choices=list(FirmRules.presets().keys()) + ["all"])
    p.add_argument("--seed", type=int, default=7)
    p.add_argument("--max-rows", type=int, default=None,
                   help="limit CSV rows loaded")
    p.add_argument("--no-dc", action="store_true", help="disable displacement candles")
    p.add_argument("--no-bos", action="store_true", help="disable break of structure")
    p.add_argument("--no-nr", action="store_true", help="disable news reversions")
    p.add_argument("--enable-soc", action="store_true", help="enable session-open continuation")
    p.add_argument("--json-out", type=str, help="write JSON summary to file")
    args = p.parse_args(argv)

    if args.data:
        bars = load_m1_csv(args.data, max_rows=args.max_rows)
        news = load_news_csv(args.news) if args.news else []
        data_label = os.path.basename(args.data)
    else:
        n = args.synthetic or 200
        bars, news = generate_synthetic_m1(n_sessions=n, seed=args.seed)
        data_label = f"synthetic({n} sessions, seed={args.seed})"

    enabled = {
        "DC": not args.no_dc,
        "BoS": not args.no_bos,
        "NR": not args.no_nr,
        "SOC": args.enable_soc,
    }

    presets = FirmRules.presets()
    if args.config == "all":
        configs = list(presets.values())
    else:
        configs = [presets[args.config]]

    print(f"Data: {data_label}  |  bars: {len(bars):,}  |  news events: {len(news)}")
    print(f"Signals enabled: {enabled}")
    print(f"Accounts per config: {args.accounts}")
    print()

    results = []
    for rules in configs:
        res = simulate(
            bars=bars,
            rules=rules,
            n_accounts=args.accounts,
            news_events=news,
            signals_enabled=enabled,
        )
        print(res.summary())
        print()
        results.append({
            "config": rules.name,
            "pass_rate": res.pass_rate,
            "cost_per_funded": res.cost_per_funded,
            "ev_per_funded": res.ev_per_funded,
            "ev_per_eval_dollar": res.ev_per_eval_dollar,
            "signals_fired": res.signals_fired,
            "trades_taken": res.trades_taken,
            "per_signal_stats": res.per_signal_stats,
        })

    if args.json_out:
        with open(args.json_out, "w") as f:
            json.dump({"data": data_label, "accounts": args.accounts,
                       "enabled_signals": enabled, "results": results}, f, indent=2,
                      default=str)
        print(f"Wrote {args.json_out}")


if __name__ == "__main__":
    main()
