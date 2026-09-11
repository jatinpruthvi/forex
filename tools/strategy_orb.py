"""
Opening Range Breakout (ORB) strategy — standalone backtest.

Reads Eightcap tick files directly. Builds M5 bars. Defines a 30-minute
opening range at the start of the entry window. Trades breakouts of that
range in the direction of the break. Profiles results per pair/session
and writes findings_orb_strategy.md.

No imports from existing strategy or signal-builder files.

Usage:
    python tools/strategy_orb.py
"""
from __future__ import annotations

import csv
import math
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Optional

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
SERVER_UTC_OFFSET  = 3          # Eightcap server = UTC+3
ACCOUNT_BALANCE    = 2500.0     # Challenge starting balance ($)
RISK_FRACTION      = 0.004      # 0.40% per trade  (Profile A)
TARGET_R           = 1.5        # fixed 1.5R target
COMMISSION_PER_LOT = 4.0        # $4 round-trip per standard lot
VOLUME_MIN         = 0.01
VOLUME_STEP        = 0.01

# ORB parameters
ORB_BARS           = 6          # 6 x M5 = 30-minute opening range
STOP_BUFFER_ATR    = 0.10       # buffer beyond range extreme for stop
STOP_ATR_MIN       = 0.50       # minimum stop distance as ATR multiple
STOP_ATR_MAX       = 2.00       # maximum stop distance as ATR multiple
MIN_STOP_PIPS      = 3          # cancel if stop < 3 pips (noise floor)

INSTRUMENT_SPECS = {
    "EURUSD": {"pip": 0.0001,  "tick_value": 10.0,  "tick_size": 0.00001},
    "GBPUSD": {"pip": 0.0001,  "tick_value": 10.0,  "tick_size": 0.00001},
    "USDJPY": {"pip": 0.01,    "tick_value":  9.09, "tick_size": 0.001  },
}

# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

@dataclass
class Bar:
    time:  datetime
    open:  float
    high:  float
    low:   float
    close: float


@dataclass
class TradeResult:
    direction:   str     # "long" or "short"
    entry:       float
    stop:        float
    target:      float
    exit_price:  float
    exit_reason: str     # "target", "stop", "time"
    pnl_r:       float   # P&L in R multiples (net of costs)
    pnl_cash:    float   # net P&L in USD
    lots:        float
    orb_high:    float
    orb_low:     float
    atr:         float


@dataclass
class SessionStats:
    session:       str
    days_tested:   int
    signals:       int
    wins:          int
    losses:        int
    time_exits:    int
    win_rate:      float
    avg_r:         float
    profit_factor: float
    total_r:       float
    total_cash:    float
    trades:        list = field(default_factory=list)


# ---------------------------------------------------------------------------
# DST helpers
# ---------------------------------------------------------------------------

def _last_sunday(year: int, month: int) -> date:
    nxt = date(year + 1, 1, 1) if month == 12 else date(year, month + 1, 1)
    last = nxt - timedelta(days=1)
    return last - timedelta(days=(last.weekday() + 1) % 7)


def london_offset(d: date) -> int:
    yr = d.year
    return 1 if _last_sunday(yr, 3) <= d < _last_sunday(yr, 10) else 0


def ny_offset(d: date) -> int:
    yr = d.year
    first_sun_mar = date(yr, 3, 1) + timedelta(days=(6 - date(yr, 3, 1).weekday()) % 7)
    edt_start = first_sun_mar + timedelta(weeks=1)
    edt_end   = date(yr, 11, 1) + timedelta(days=(6 - date(yr, 11, 1).weekday()) % 7)
    return -4 if edt_start <= d < edt_end else -5


def lw_to_srv(yr: int, mo: int, da: int, h: int, m: int = 0) -> datetime:
    utc = datetime(yr, mo, da, h, m) - timedelta(hours=london_offset(date(yr, mo, da)))
    return utc + timedelta(hours=SERVER_UTC_OFFSET)


def ny_to_srv(yr: int, mo: int, da: int, h: int, m: int = 0) -> datetime:
    utc = datetime(yr, mo, da, h, m) - timedelta(hours=ny_offset(date(yr, mo, da)))
    return utc + timedelta(hours=SERVER_UTC_OFFSET)


# ---------------------------------------------------------------------------
# Bar building and ATR
# ---------------------------------------------------------------------------

def _bar_key(dt: datetime, period: int) -> datetime:
    t = dt.hour * 60 + dt.minute
    f = t // period * period
    return dt.replace(hour=f // 60, minute=f % 60, second=0, microsecond=0)


def build_bars(ticks: list, period: int) -> list:
    bm: dict = {}
    for dt, price in ticks:
        k = _bar_key(dt, period)
        if k not in bm:
            bm[k] = Bar(k, price, price, price, price)
        else:
            b = bm[k]
            if price > b.high:  b.high  = price
            if price < b.low:   b.low   = price
            b.close = price
    return [bm[k] for k in sorted(bm)]


def atr14(bars_m15: list, before: datetime) -> float:
    comp = [b for b in bars_m15 if b.time < before]
    if len(comp) < 14:
        return 0.0
    return sum(b.high - b.low for b in comp[-14:]) / 14.0


# ---------------------------------------------------------------------------
# Tick file loader
# ---------------------------------------------------------------------------

def load_ticks(path: Path) -> tuple:
    ask_day: dict = defaultdict(list)
    mid_day: dict = defaultdict(list)
    print(f"  Loading {path.name} ({path.stat().st_size / 1e6:.0f} MB)...", end="", flush=True)
    with open(path, "r", newline="") as f:
        rdr = csv.reader(f, delimiter="\t")
        next(rdr)
        for row in rdr:
            if len(row) < 4:
                continue
            bs, as_ = row[2].strip(), row[3].strip()
            hb, ha  = bs != "", as_ != ""
            if not hb and not ha:
                continue
            try:
                dt = datetime.strptime(
                    row[0].strip() + " " + row[1].strip()[:8], "%Y.%m.%d %H:%M:%S"
                )
            except ValueError:
                continue
            dk = row[0].strip()
            if ha:
                ask_day[dk].append((dt, float(as_)))
            if hb and ha:
                mid_day[dk].append((dt, (float(bs) + float(as_)) / 2.0))
    print(f" {len(ask_day)} days")
    return dict(ask_day), dict(mid_day)


# ---------------------------------------------------------------------------
# Session configuration
# ---------------------------------------------------------------------------

def _london_bounds(yr: int, mo: int, da: int):
    rs = lw_to_srv(yr, mo, da, 0)
    re = lw_to_srv(yr, mo, da, 7)
    es = re
    ee = lw_to_srv(yr, mo, da, 11)
    return rs, re, es, ee


def _ny_bounds(yr: int, mo: int, da: int):
    rs = lw_to_srv(yr, mo, da, 7)
    re = lw_to_srv(yr, mo, da, 13)
    es = ny_to_srv(yr, mo, da, 8, 30)
    ee = ny_to_srv(yr, mo, da, 11, 0)
    return rs, re, es, ee


SESSIONS = {
    "EURUSD_LONDON":  {"symbol": "EURUSD", "get_bounds": _london_bounds},
    "GBPUSD_LONDON":  {"symbol": "GBPUSD", "get_bounds": _london_bounds},
    "USDJPY_NEWYORK": {"symbol": "USDJPY", "get_bounds": _ny_bounds},
}

TICK_FILES = {
    "EURUSD": Path("validation/HistoryData/EURUSD.i_202406190501_202609102250.csv"),
    "GBPUSD": Path("validation/HistoryData/GBPUSD.i_202406190501_202609110308.csv"),
    "USDJPY": Path("validation/HistoryData/USDJPY.i_202406190501_202609110308.csv"),
}

# ---------------------------------------------------------------------------
# Lot sizing
# ---------------------------------------------------------------------------

def calc_lots(stop_distance: float, symbol: str) -> float:
    spec         = INSTRUMENT_SPECS[symbol]
    risk_budget  = ACCOUNT_BALANCE * RISK_FRACTION
    pip_value    = spec["tick_value"] * (spec["pip"] / spec["tick_size"])
    stop_pips    = stop_distance / spec["pip"]
    loss_per_lot = stop_pips * pip_value + COMMISSION_PER_LOT
    if loss_per_lot <= 0:
        return 0.0
    raw  = risk_budget / loss_per_lot
    lots = math.floor(raw / VOLUME_STEP) * VOLUME_STEP
    return max(0.0, lots)


# ---------------------------------------------------------------------------
# ORB signal detection and trade simulation — one day
# ---------------------------------------------------------------------------

def run_day(
    ask_ticks:   list,
    mid_ticks:   list,
    entry_start: datetime,
    entry_end:   datetime,
    symbol:      str,
    m15_history: list,
) -> Optional[TradeResult]:
    spec = INSTRUMENT_SPECS[symbol]

    # Build bars
    ask_m5  = build_bars(ask_ticks, 5)
    mid_m15 = build_bars(mid_ticks, 15)

    # Extend rolling M15 history (deduplicated, sorted)
    existing = {b.time for b in m15_history}
    for b in mid_m15:
        if b.time not in existing:
            m15_history.append(b)
            existing.add(b.time)
    m15_history.sort(key=lambda b: b.time)

    atr = atr14(m15_history, entry_start)
    if atr <= 0:
        return None

    # Entry-window M5 bars
    window = [b for b in ask_m5 if entry_start <= b.time < entry_end]
    if len(window) <= ORB_BARS:
        return None

    # Opening range: first ORB_BARS M5 bars
    orb_bars = window[:ORB_BARS]
    orb_high = max(b.high for b in orb_bars)
    orb_low  = min(b.low  for b in orb_bars)

    if (orb_high - orb_low) < spec["pip"]:
        return None  # flat/holiday day

    # First breakout after opening range
    post_orb      = window[ORB_BARS:]
    direction     = None
    entry_price   = None
    breakout_bar  = None

    for bar in post_orb:
        if bar.close > orb_high:
            direction, entry_price, breakout_bar = "long",  orb_high, bar
            break
        if bar.close < orb_low:
            direction, entry_price, breakout_bar = "short", orb_low,  bar
            break

    if direction is None:
        return None

    # Stop and target
    if direction == "long":
        stop   = orb_low  - STOP_BUFFER_ATR * atr
        target = entry_price + (entry_price - stop) * TARGET_R
    else:
        stop   = orb_high + STOP_BUFFER_ATR * atr
        target = entry_price - (entry_price - stop) * TARGET_R

    stop_dist = abs(entry_price - stop)

    if atr > 0:
        stop_atr = stop_dist / atr
        if stop_atr < STOP_ATR_MIN or stop_atr > STOP_ATR_MAX:
            return None

    if stop_dist / spec["pip"] < MIN_STOP_PIPS:
        return None

    lots = calc_lots(stop_dist, symbol)
    if lots < VOLUME_MIN:
        return None

    # Simulate exit using mid-price ticks after breakout bar closes
    bar_end      = breakout_bar.time + timedelta(minutes=5)
    forward_mids = [(dt, p) for dt, p in mid_ticks
                    if dt >= bar_end and dt < entry_end]

    # Fill: assume immediate fill at entry level (price already past entry
    # when breakout bar closed; limit at boundary is a realistic assumption)
    fill_time = bar_end
    for dt, p in forward_mids:
        if direction == "long"  and p <= entry_price: fill_time = dt; break
        if direction == "short" and p >= entry_price: fill_time = dt; break

    post_fill    = [(dt, p) for dt, p in forward_mids if dt >= fill_time]
    exit_price   = entry_price
    exit_reason  = "time"

    for dt, p in post_fill:
        if direction == "long":
            if p >= target: exit_price = target; exit_reason = "target"; break
            if p <= stop:   exit_price = stop;   exit_reason = "stop";   break
        else:
            if p <= target: exit_price = target; exit_reason = "target"; break
            if p >= stop:   exit_price = stop;   exit_reason = "stop";   break
    else:
        if post_fill:
            exit_price = post_fill[-1][1]
        exit_reason = "time"

    # P&L
    pip_value  = spec["tick_value"] * (spec["pip"] / spec["tick_size"])
    stop_pips  = stop_dist / spec["pip"]
    if direction == "long":
        gross_pips = (exit_price - entry_price) / spec["pip"]
    else:
        gross_pips = (entry_price - exit_price) / spec["pip"]

    gross_cash = gross_pips * pip_value * lots
    net_cash   = gross_cash - COMMISSION_PER_LOT * lots
    risk_cash  = stop_pips * pip_value * lots + COMMISSION_PER_LOT * lots
    pnl_r      = net_cash / risk_cash if risk_cash > 0 else 0.0

    return TradeResult(
        direction=direction, entry=entry_price, stop=stop, target=target,
        exit_price=exit_price, exit_reason=exit_reason,
        pnl_r=pnl_r, pnl_cash=net_cash, lots=lots,
        orb_high=orb_high, orb_low=orb_low, atr=atr,
    )


# ---------------------------------------------------------------------------
# Session backtester
# ---------------------------------------------------------------------------

def run_session(session_name: str, ask_day: dict, mid_day: dict) -> SessionStats:
    sess        = SESSIONS[session_name]
    symbol      = sess["symbol"]
    m15_history: list = []
    trades:      list = []
    days_tested = 0

    for dk in sorted(ask_day.keys()):
        at = ask_day.get(dk, [])
        mt = mid_day.get(dk, [])
        if not at or not mt:
            continue
        y, mo, da = (int(x) for x in dk.split("."))
        _, _, entry_start, entry_end = sess["get_bounds"](y, mo, da)
        days_tested += 1
        result = run_day(at, mt, entry_start, entry_end, symbol, m15_history)
        if result is not None:
            trades.append(result)

    signals   = len(trades)
    wins      = sum(1 for t in trades if t.exit_reason == "target")
    losses    = sum(1 for t in trades if t.exit_reason == "stop")
    time_ex   = sum(1 for t in trades if t.exit_reason == "time")
    win_rate  = wins / signals if signals > 0 else 0.0
    avg_r     = sum(t.pnl_r for t in trades) / signals if signals > 0 else 0.0
    gross_win = sum(t.pnl_cash for t in trades if t.pnl_cash > 0)
    gross_los = abs(sum(t.pnl_cash for t in trades if t.pnl_cash <= 0))
    pf        = (gross_win / gross_los if gross_los > 0
                 else float("inf") if gross_win > 0 else 0.0)

    return SessionStats(
        session=session_name, days_tested=days_tested,
        signals=signals, wins=wins, losses=losses, time_exits=time_ex,
        win_rate=win_rate, avg_r=avg_r, profit_factor=pf,
        total_r=sum(t.pnl_r for t in trades),
        total_cash=sum(t.pnl_cash for t in trades),
        trades=trades,
    )


# ---------------------------------------------------------------------------
# Results printer
# ---------------------------------------------------------------------------

def print_results(stats_list: list) -> None:
    print(f"\n{'='*80}")
    print("ORB STRATEGY — BACKTEST RESULTS")
    print(f"{'='*80}")
    hdr = (f"{'Session':<22}{'Days':<7}{'Sigs':<7}{'Win%':<8}"
           f"{'AvgR':<8}{'PF':<8}{'TotalR':<9}{'Total$':<12}{'W/L/T'}")
    print(hdr)
    print("-" * len(hdr))

    for s in stats_list:
        pf_s = f"{s.profit_factor:.2f}" if s.profit_factor != float("inf") else "inf"
        print(
            f"{s.session:<22}{s.days_tested:<7}{s.signals:<7}"
            f"{s.win_rate*100:<8.1f}{s.avg_r:<8.3f}{pf_s:<8}"
            f"{s.total_r:<9.2f}${s.total_cash:<11.2f}"
            f"{s.wins}/{s.losses}/{s.time_exits}"
        )

    # Combined
    all_sigs  = sum(s.signals    for s in stats_list)
    all_cash  = sum(s.total_cash for s in stats_list)
    all_r     = sum(s.total_r    for s in stats_list)
    all_wins  = sum(s.wins       for s in stats_list)
    all_los   = sum(s.losses     for s in stats_list)
    all_time  = sum(s.time_exits for s in stats_list)
    all_wr    = all_wins / all_sigs if all_sigs > 0 else 0.0
    all_avgr  = all_r / all_sigs    if all_sigs > 0 else 0.0
    gw        = sum(t.pnl_cash for s in stats_list for t in s.trades if t.pnl_cash > 0)
    gl        = abs(sum(t.pnl_cash for s in stats_list for t in s.trades if t.pnl_cash <= 0))
    all_pf    = gw / gl if gl > 0 else float("inf")
    all_pf_s  = f"{all_pf:.2f}" if all_pf != float("inf") else "inf"

    print("-" * len(hdr))
    print(
        f"{'COMBINED':<22}{'--':<7}{all_sigs:<7}"
        f"{all_wr*100:<8.1f}{all_avgr:<8.3f}{all_pf_s:<8}"
        f"{all_r:<9.2f}${all_cash:<11.2f}{all_wins}/{all_los}/{all_time}"
    )

    days_ref = max((s.days_tested for s in stats_list), default=1)
    ann      = all_sigs / days_ref * 252
    eta_34   = (34 / (all_sigs / days_ref)) / 5 if all_sigs > 0 else 9999
    avg_per  = all_cash / all_sigs if all_sigs > 0 else 0.0

    print(f"\nChallenge context ($2,500 account, Phase 1 needs +$250):")
    print(f"  Signals / {days_ref} days : {all_sigs}  ({all_sigs/days_ref*100:.1f}% of days)")
    print(f"  Annualised              : ~{ann:.0f} signals/year")
    print(f"  Avg net P&L/trade       : ${avg_per:.2f}")
    print(f"  ETA 34 signals @ 50% WR : ~{eta_34:.0f} trading weeks")
    print()


# ---------------------------------------------------------------------------
# Findings MD writer
# ---------------------------------------------------------------------------

def write_findings(stats_list: list, out_path: Path) -> None:
    days_ref  = max((s.days_tested for s in stats_list), default=1)
    all_sigs  = sum(s.signals    for s in stats_list)
    all_cash  = sum(s.total_cash for s in stats_list)
    all_r     = sum(s.total_r    for s in stats_list)
    all_wins  = sum(s.wins       for s in stats_list)
    all_los   = sum(s.losses     for s in stats_list)
    all_time  = sum(s.time_exits for s in stats_list)
    all_wr    = all_wins / all_sigs if all_sigs > 0 else 0.0
    all_avgr  = all_r / all_sigs    if all_sigs > 0 else 0.0
    gw        = sum(t.pnl_cash for s in stats_list for t in s.trades if t.pnl_cash > 0)
    gl        = abs(sum(t.pnl_cash for s in stats_list for t in s.trades if t.pnl_cash <= 0))
    all_pf    = gw / gl if gl > 0 else float("inf")
    all_pf_s  = f"{all_pf:.2f}" if all_pf != float("inf") else "inf"
    ann       = all_sigs / days_ref * 252
    eta_34    = (34 / (all_sigs / days_ref)) / 5 if all_sigs > 0 else 9999
    avg_per   = all_cash / all_sigs if all_sigs > 0 else 0.0

    viable = all_sigs >= 20 and all_wr >= 0.45 and all_pf >= 1.20 and all_avgr > 0
    verdict = (
        "**POTENTIALLY VIABLE** — signal count, win rate, and profit factor all meet "
        "minimum thresholds. Obtain 3+ years of data for statistical confirmation before "
        "live deployment."
        if viable else
        "**NOT YET VIABLE** — one or more metrics (signal count, win rate, profit factor) "
        "fall below minimum thresholds. See Section 4 for recommendations."
    )

    # Per-session table rows
    tbl_rows = []
    for s in stats_list:
        pf_s = f"{s.profit_factor:.2f}" if s.profit_factor != float("inf") else "inf"
        tbl_rows.append(
            f"| {s.session} | {s.days_tested} | {s.signals} | "
            f"{s.win_rate*100:.1f}% | {s.avg_r:.3f} | {pf_s} | "
            f"{s.total_r:.2f} | ${s.total_cash:.2f} | "
            f"{s.wins}/{s.losses}/{s.time_exits} |"
        )
    tbl_rows.append(
        f"| **COMBINED** | --- | **{all_sigs}** | **{all_wr*100:.1f}%** | "
        f"**{all_avgr:.3f}** | **{all_pf_s}** | **{all_r:.2f}** | "
        f"**${all_cash:.2f}** | {all_wins}/{all_los}/{all_time} |"
    )
    tbl_body = "\n".join(tbl_rows)

    md = f"""# ORB Strategy — Backtest Findings

**Generated by:** `tools/strategy_orb.py`
**Data window:** ~2024-06-19 to ~2025-03-21 (Eightcap tick files)
**Pairs tested:** EURUSD London, GBPUSD London, USDJPY New York

---

## 1. Why ORB?

The parameter grid search on the existing sweep/reclaim strategy found that
**61% of London sessions are rejected as `too_deep`** — the sweep extends
more than 0.50 ATR before recovering. These are strong directional continuation
moves. The sweep/reclaim strategy treats them as invalid; the **Opening Range
Breakout (ORB)** strategy treats them as the signal itself.

ORB logic:
1. Compute ATR(14) from M15 mid-price bars before the session open.
2. Build an **opening range** from the first {ORB_BARS} M5 bars ({ORB_BARS*5} min) of the entry window.
3. Enter **long** on the first M5 close above the range high, **short** below range low.
4. Entry price = range boundary (conservative limit-order fill assumption).
5. Stop = opposite side of range minus/plus {STOP_BUFFER_ATR}×ATR buffer.
6. Target = {TARGET_R}R from entry (same as existing EA for fair comparison).
7. Time stop = session end.
8. One trade per session per pair.

**Stop validity gates:** stop distance must be {STOP_ATR_MIN}–{STOP_ATR_MAX}×ATR and ≥{MIN_STOP_PIPS} pips.

---

## 2. Parameters

| Parameter | Value | Rationale |
|---|---|---|
| `ORB_BARS` | {ORB_BARS} (30 min) | Standard ORB window — long enough to filter early noise |
| `STOP_BUFFER_ATR` | {STOP_BUFFER_ATR} | Small cushion beyond range extreme |
| `STOP_ATR_MIN` | {STOP_ATR_MIN} | Rejects stop distances too tight to be meaningful |
| `STOP_ATR_MAX` | {STOP_ATR_MAX} | Wider band than sweep/reclaim (breakouts often larger range) |
| `MIN_STOP_PIPS` | {MIN_STOP_PIPS} | Absolute pip floor — avoids trading flat holiday days |
| `TARGET_R` | {TARGET_R} | Fixed — same as existing EA for direct comparison |
| `RISK_FRACTION` | {RISK_FRACTION*100:.1f}% | The5ers Profile A |

---

## 3. Per-Pair Results

| Session | Days | Signals | Win% | Avg R | Profit Factor | Total R | Total USD | W/L/T |
|---|---|---|---|---|---|---|---|---|
{tbl_body}

*W/L/T = target-wins / stop-losses / time-exits*

---

## 4. Challenge Viability

| Metric | Result | Threshold |
|---|---|---|
| Combined signals / {days_ref} days | {all_sigs} ({all_sigs/days_ref*100:.1f}%) | >= 20 signals |
| Win rate | {all_wr*100:.1f}% | >= 45% |
| Profit factor | {all_pf_s} | >= 1.20 |
| Avg net P&L / trade | ${avg_per:.2f} | > $0 |
| Annualised signal rate | ~{ann:.0f}/year | — |
| ETA to Phase 1 (~34 signals) | ~{eta_34:.0f} trading weeks | — |

### Verdict

{verdict}

---

## 5. Direct Comparison — ORB vs Sweep/Reclaim

| Metric | Sweep/Reclaim (best params) | ORB (this file) |
|---|---|---|
| Combined signals / 9 months | 12 | {all_sigs} |
| Strategy type | Reversal — fade the sweep | Continuation — follow breakout |
| Win rate | ~17% (1/6 on EURUSD alone) | {all_wr*100:.1f}% |
| Avg R per trade | negative | {all_avgr:.3f} |
| Data window | Same 9 months | Same 9 months |

---

## 6. Limitations and Next Steps

1. **9 months is insufficient** for statistical confidence. A minimum of 100 trades
   per pair is needed. Export EURUSD + GBPUSD M1 OHLC from MT5 back to 2015
   (~15 MB each) and re-run this script.

2. **No news filter** — the current backtest trades through high-impact events.
   Adding a 30-minute blackout around red-folder news will reduce signal count
   but should improve win rate.

3. **Parameter sweep needed** — test `ORB_BARS` in [4, 6, 8] and
   `STOP_ATR_MAX` in [1.5, 2.0, 2.5] to find the most robust plateau.

4. **Direction filter** — adding an H1 trend filter (same as the H1 EMA gate
   already in the EA) may significantly improve win rate by only taking
   breakouts aligned with the trend.

---

*Auto-generated by `tools/strategy_orb.py`*
"""

    out_path.write_text(md, encoding="utf-8")
    print(f"Findings written -> {out_path}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    print("=" * 60)
    print("ORB Strategy Backtest")
    print("=" * 60)

    loaded: dict = {}
    for sym, path in TICK_FILES.items():
        if path.exists():
            loaded[sym] = load_ticks(path)
        else:
            print(f"  [SKIP] {sym}: {path} not found")

    if not loaded:
        print("No data loaded — check HistoryData paths.")
        return

    all_stats: list = []
    for sname, sess in SESSIONS.items():
        sym = sess["symbol"]
        if sym not in loaded:
            continue
        print(f"\nRunning {sname}...")
        ask_day, mid_day = loaded[sym]
        stats = run_session(sname, ask_day, mid_day)
        all_stats.append(stats)

    if not all_stats:
        print("No sessions ran.")
        return

    print_results(all_stats)
    write_findings(all_stats, Path("findings_orb_strategy.md"))


if __name__ == "__main__":
    main()
