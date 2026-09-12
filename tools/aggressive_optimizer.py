"""
Aggressive Multi-Pair Challenge Optimizer
==========================================
Goal: pass The5ers $2,500 New High Stakes challenge in minimum trading days.

Challenge rules:
  Phase 1: +10% profit ($250), min 3 qualifying days (day net >= $12.50)
  Phase 2: +5%  profit ($125), min 3 qualifying days
  Daily loss limit:   5%  of current balance
  Total drawdown:    10%  of starting balance (floor = $2,250)

Strategies:
  orb_atr  — ORB with ATR-fixed stop (stop = fixed ATR fraction from entry)
  orb_half — ORB with midpoint stop  (stop = midpoint of opening range)
  vola     — Volatility Expansion: enter on bar with range > 1.5x ATR

Lot sizing uses FIXED balance ($2,500) throughout to prevent compounding blow-up.
Phase 1 completes when balance >= $2,750 AND qualifying_days >= 3.

Usage:
    python tools/aggressive_optimizer.py
"""
from __future__ import annotations

import csv
import math
import statistics
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Optional

# ---------------------------------------------------------------------------
# Challenge constants
# ---------------------------------------------------------------------------
ACCOUNT_BALANCE    = 2500.0
RISK_FRACTION      = 0.004         # 0.40% fixed per trade
COMMISSION_PER_LOT = 4.0
VOLUME_MIN         = 0.01
VOLUME_STEP        = 0.01

PHASE1_TARGET      = ACCOUNT_BALANCE * 1.10   # $2,750
QUALIFYING_DAY_MIN = 12.50
DAILY_LOSS_LIMIT   = 0.05                      # 5%
TOTAL_FLOOR_PCT    = 0.90                      # never below $2,250
SAFETY_BUFFER      = 0.005                     # stop 0.5% before hard limit

# ---------------------------------------------------------------------------
# Parameter grid
# ---------------------------------------------------------------------------
TARGET_R_GRID   = [1.5, 2.0, 2.5, 3.0]
ORB_BARS_GRID   = [4, 6, 8]
ATR_STOP_GRID   = [0.25, 0.35, 0.50]
STRATEGY_GRID   = ["orb_atr", "orb_half", "vola"]

# ---------------------------------------------------------------------------
# Instrument specs
# ---------------------------------------------------------------------------
# pv (pip value) = USD value of 1 pip per standard lot (100,000 units for FX, 100 oz for Gold).
# FX USD-quote pairs (EURUSD, GBPUSD, AUDUSD, NZDUSD): pv = $10 exactly.
# FX USD-base pairs (USDCAD, USDCHF): pv ≈ $10 (quote-rate varies; $10 is a reasonable mid).
# FX GBP-cross (EURGBP): pv ≈ $12-13 (depends on GBPUSD rate); using $12.70 mid.
# JPY pairs: pv = 100,000 * 0.01 / rate. Rates for 2024-2026 mid: USDJPY≈148, EURJPY≈163, GBPJPY≈193.
# XAUUSD: 100 oz * $0.10/pip/oz = $10 per pip per lot (exact).
SPECS = {
    "EURUSD": {"pip": 0.0001, "pv": 10.00},
    "GBPUSD": {"pip": 0.0001, "pv": 10.00},
    "EURGBP": {"pip": 0.0001, "pv": 12.70},
    "AUDUSD": {"pip": 0.0001, "pv": 10.00},
    "NZDUSD": {"pip": 0.0001, "pv": 10.00},
    "USDCAD": {"pip": 0.0001, "pv":  9.80},
    "USDCHF": {"pip": 0.0001, "pv":  9.80},
    "USDJPY": {"pip": 0.01,   "pv":  6.76},   # 100,000*0.01/148
    "EURJPY": {"pip": 0.01,   "pv":  6.13},   # 100,000*0.01/163
    "GBPJPY": {"pip": 0.01,   "pv":  5.18},   # 100,000*0.01/193
    "XAUUSD": {"pip": 0.10,   "pv": 10.00},   # 100oz * $0.10/pip/oz
}

# Session pair lists
LONDON_PAIRS = ["EURUSD","GBPUSD","EURGBP","GBPJPY","EURJPY",
                "AUDUSD","USDCHF","NZDUSD","XAUUSD"]
NY_PAIRS     = ["USDJPY","USDCAD","EURUSD","GBPUSD","XAUUSD"]

DATA_DIR = Path("validation/HistoryData")

# ---------------------------------------------------------------------------
# DST helpers
# ---------------------------------------------------------------------------

def _last_sunday(year: int, month: int) -> date:
    nxt = date(year+1,1,1) if month == 12 else date(year,month+1,1)
    last = nxt - timedelta(days=1)
    return last - timedelta(days=(last.weekday()+1) % 7)

def _lo(d: date) -> int:
    yr = d.year
    return 1 if _last_sunday(yr,3) <= d < _last_sunday(yr,10) else 0

def _nyo(d: date) -> int:
    yr = d.year
    sun_mar = date(yr,3,1) + timedelta(days=(6-date(yr,3,1).weekday())%7)
    edt_s = sun_mar + timedelta(weeks=1)
    edt_e = date(yr,11,1) + timedelta(days=(6-date(yr,11,1).weekday())%7)
    return -4 if edt_s <= d < edt_e else -5

def lw_utc(d: date, h: int, m: int = 0) -> datetime:
    """London wall time -> UTC (tz-aware)."""
    return datetime(d.year, d.month, d.day, h, m, tzinfo=timezone.utc) - timedelta(hours=_lo(d))

def ny_utc(d: date, h: int, m: int = 0) -> datetime:
    """NY wall time -> UTC (tz-aware)."""
    return datetime(d.year, d.month, d.day, h, m, tzinfo=timezone.utc) - timedelta(hours=_nyo(d))

def to_london_date(ts_utc: datetime) -> date:
    return (ts_utc + timedelta(hours=_lo(ts_utc.date()))).date()

# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

@dataclass
class Bar:
    ts:    datetime   # UTC tz-aware
    open:  float
    high:  float
    low:   float
    close: float

@dataclass
class Trade:
    pair:       str
    direction:  str
    entry:      float
    stop:       float
    target:     float
    exit_price: float
    exit_reason: str
    pnl_cash:   float
    pnl_r:      float
    lots:       float
    bar_date:   date
    strategy:   str

# ---------------------------------------------------------------------------
# Loader
# ---------------------------------------------------------------------------

def load_pair(symbol: str) -> list[Bar]:
    fname = f"{symbol.lower()}-m5-fsb.csv"
    path  = DATA_DIR / fname
    if not path.exists():
        return []
    bars = []
    with open(path, newline="") as f:
        rdr = csv.reader(f)
        next(rdr)
        for row in rdr:
            if len(row) < 5: continue
            try:
                ts = datetime.fromtimestamp(int(row[0])/1000, tz=timezone.utc)
                bars.append(Bar(ts, float(row[1]), float(row[2]),
                                float(row[3]), float(row[4])))
            except (ValueError, IndexError):
                continue
    return bars

# ---------------------------------------------------------------------------
# Preprocess: build by_date cache and rolling ATR per date
# ---------------------------------------------------------------------------

def preprocess(bars: list[Bar]) -> tuple[dict, dict]:
    """
    Returns:
      by_date : {london_wall_date: [Bar,...]}  sorted by ts
      atr_map : {london_wall_date: float}      ATR at start of London entry window
    """
    by_date: dict = defaultdict(list)
    for b in bars:
        by_date[to_london_date(b.ts)].append(b)
    for d in by_date:
        by_date[d].sort(key=lambda b: b.ts)

    # Rolling ATR: accumulate M15 ranges (3 M5 bars = 1 M15 bar)
    # from pre-London-07:00 bars across all days in order
    atr_map: dict = {}
    m15_ranges: list[float] = []
    m15_buf: list[Bar] = []

    for d in sorted(by_date.keys()):
        cutoff = lw_utc(d, 7)
        pre = [b for b in by_date[d] if b.ts < cutoff]
        for b in pre:
            m15_buf.append(b)
            if len(m15_buf) == 3:
                m15_ranges.append(
                    max(x.high for x in m15_buf) - min(x.low for x in m15_buf)
                )
                m15_buf = []
        if len(m15_ranges) >= 14:
            atr_map[d] = sum(m15_ranges[-14:]) / 14.0
        elif m15_ranges:
            atr_map[d] = sum(m15_ranges) / len(m15_ranges)

    return dict(by_date), atr_map

# ---------------------------------------------------------------------------
# Lot sizing — FIXED base to prevent compounding blow-up
# ---------------------------------------------------------------------------

def calc_lots(stop_dist: float, symbol: str) -> float:
    spec = SPECS[symbol]
    risk = ACCOUNT_BALANCE * RISK_FRACTION   # always $10
    pv   = spec["pv"]                        # USD per pip per standard lot
    sp   = stop_dist / spec["pip"]           # stop distance in pips
    lpl  = sp * pv + COMMISSION_PER_LOT      # $ loss per lot at stop
    if lpl <= 0: return 0.0
    return max(0.0, math.floor((risk / lpl) / VOLUME_STEP) * VOLUME_STEP)

# ---------------------------------------------------------------------------
# Signal generators
# ---------------------------------------------------------------------------

def sig_orb_atr(entry_bars, atr, symbol, orb_bars, atr_stop, target_r, strat="orb_atr"):
    if atr <= 0 or len(entry_bars) <= orb_bars: return None
    spec = SPECS[symbol]
    ob   = entry_bars[:orb_bars]
    orb_h = max(b.high for b in ob)
    orb_l = min(b.low  for b in ob)
    if (orb_h - orb_l) / spec["pip"] < 2: return None

    for bar in entry_bars[orb_bars:]:
        if   bar.close > orb_h: direction, entry = "long",  orb_h
        elif bar.close < orb_l: direction, entry = "short", orb_l
        else: continue

        stop   = entry - atr_stop*atr if direction=="long" else entry + atr_stop*atr
        stop_d = abs(entry - stop)
        if stop_d/spec["pip"] < 2 or stop_d/atr > 3.0: continue
        target = entry + stop_d*target_r if direction=="long" else entry - stop_d*target_r
        lots   = calc_lots(stop_d, symbol)
        if lots < VOLUME_MIN: continue
        return dict(direction=direction, entry=entry, stop=stop,
                    target=target, lots=lots, bbar=bar, strategy=strat)
    return None

def sig_orb_half(entry_bars, atr, symbol, orb_bars, target_r):
    if atr <= 0 or len(entry_bars) <= orb_bars: return None
    spec = SPECS[symbol]
    ob   = entry_bars[:orb_bars]
    orb_h = max(b.high for b in ob)
    orb_l = min(b.low  for b in ob)
    mid   = (orb_h + orb_l) / 2.0
    if (orb_h - orb_l) / spec["pip"] < 3: return None

    for bar in entry_bars[orb_bars:]:
        if   bar.close > orb_h: direction, entry, stop = "long",  orb_h, mid - 0.05*atr
        elif bar.close < orb_l: direction, entry, stop = "short", orb_l, mid + 0.05*atr
        else: continue

        stop_d = abs(entry - stop)
        if stop_d/spec["pip"] < 2: continue
        target = entry + stop_d*target_r if direction=="long" else entry - stop_d*target_r
        lots   = calc_lots(stop_d, symbol)
        if lots < VOLUME_MIN: continue
        return dict(direction=direction, entry=entry, stop=stop,
                    target=target, lots=lots, bbar=bar, strategy="orb_half")
    return None

def sig_vola(entry_bars, atr, symbol, target_r):
    if atr <= 0 or len(entry_bars) < 6: return None
    spec = SPECS[symbol]
    for bar in entry_bars[3:]:
        if (bar.high - bar.low) < 1.5 * atr: continue
        body = bar.close - bar.open
        if   body > 0: direction, entry, stop = "long",  bar.close, (bar.high+bar.low)/2
        elif body < 0: direction, entry, stop = "short", bar.close, (bar.high+bar.low)/2
        else: continue
        stop_d = abs(entry - stop)
        if stop_d/spec["pip"] < 2: continue
        target = entry + stop_d*target_r if direction=="long" else entry - stop_d*target_r
        lots   = calc_lots(stop_d, symbol)
        if lots < VOLUME_MIN: continue
        return dict(direction=direction, entry=entry, stop=stop,
                    target=target, lots=lots, bbar=bar, strategy="vola")
    return None

# ---------------------------------------------------------------------------
# Trade simulator — bar-level exit scan
# ---------------------------------------------------------------------------

def simulate(sig: dict, future_bars: list[Bar], end_utc: datetime, symbol: str) -> Trade:
    spec      = SPECS[symbol]
    direction = sig["direction"]
    entry     = sig["entry"]
    stop      = sig["stop"]
    target    = sig["target"]
    lots      = sig["lots"]
    bbar_end  = sig["bbar"].ts + timedelta(minutes=5)
    fwd       = [b for b in future_bars if bbar_end <= b.ts < end_utc]

    exit_price, exit_reason = entry, "time"
    for bar in fwd:
        if direction == "long":
            if bar.high >= target: exit_price = target; exit_reason = "target"; break
            if bar.low  <= stop:   exit_price = stop;   exit_reason = "stop";   break
        else:
            if bar.low  <= target: exit_price = target; exit_reason = "target"; break
            if bar.high >= stop:   exit_price = stop;   exit_reason = "stop";   break
    else:
        if fwd: exit_price = fwd[-1].close

    pv      = spec["pv"]                     # USD per pip per standard lot
    stop_d  = abs(entry - stop)
    gpips   = ((exit_price-entry) if direction=="long" else (entry-exit_price)) / spec["pip"]
    gross   = gpips * pv * lots
    net     = gross - COMMISSION_PER_LOT * lots
    risk_c  = stop_d / spec["pip"] * pv * lots + COMMISSION_PER_LOT * lots
    pnl_r   = net / risk_c if risk_c > 0 else 0.0

    return Trade(
        pair=symbol, direction=direction, entry=entry, stop=stop, target=target,
        exit_price=exit_price, exit_reason=exit_reason,
        pnl_cash=net, pnl_r=pnl_r, lots=lots,
        bar_date=to_london_date(sig["bbar"].ts), strategy=sig["strategy"],
    )

# ---------------------------------------------------------------------------
# One backtest run
# ---------------------------------------------------------------------------

def run_backtest(
    cache:    dict,   # symbol -> (by_date, atr_map)
    strategy: str,
    target_r: float,
    orb_bars: int,
    atr_stop: float,
    max_per_day: int = 2,
) -> dict:

    # Collect all weekday dates across all symbols
    all_dates = sorted(set(
        d for sym in cache for d in cache[sym][0]
        if d.weekday() < 5
    ))

    balance        = ACCOUNT_BALANCE
    peak_balance   = ACCOUNT_BALANCE
    total_floor    = ACCOUNT_BALANCE * TOTAL_FLOOR_PCT
    all_trades: list[Trade] = []
    equity:     list[tuple] = [(all_dates[0], ACCOUNT_BALANCE)]
    halted         = False
    qual_days      = 0
    phase1_done    = False
    days_to_p1     = None
    trading_days   = 0

    for d in all_dates:
        if halted: break
        trading_days += 1
        day_start    = balance
        daily_floor  = day_start * (1.0 - DAILY_LOSS_LIMIT + SAFETY_BUFFER)
        day_pnl      = 0.0
        day_trades: list[Trade] = []
        traded       = 0

        # Build candidate signals from all sessions/pairs
        candidates: list[tuple] = []   # (priority, sig, sym, by_date_sym, end_utc)

        # --- London session ---
        london_s = lw_utc(d, 7)
        london_e = lw_utc(d, 11)
        for sym in LONDON_PAIRS:
            if sym not in cache: continue
            by_date_sym, atr_map = cache[sym]
            if d not in by_date_sym: continue
            atr = atr_map.get(d, 0.0)
            if atr <= 0: continue
            day_bars   = by_date_sym[d]
            entry_bars = [b for b in day_bars if london_s <= b.ts < london_e]
            if len(entry_bars) <= orb_bars + 1: continue

            if strategy == "orb_atr":
                sig = sig_orb_atr(entry_bars, atr, sym, orb_bars, atr_stop, target_r)
            elif strategy == "orb_half":
                sig = sig_orb_half(entry_bars, atr, sym, orb_bars, target_r)
            else:
                sig = sig_vola(entry_bars, atr, sym, target_r)
            if sig: candidates.append((0, sig, sym, day_bars, london_e))

        # --- New York session ---
        ny_s = ny_utc(d, 8, 30)
        ny_e = ny_utc(d, 11, 0)
        for sym in NY_PAIRS:
            if sym not in cache: continue
            by_date_sym, atr_map = cache[sym]
            if d not in by_date_sym: continue
            atr = atr_map.get(d, 0.0)
            if atr <= 0: continue
            day_bars   = by_date_sym[d]
            entry_bars = [b for b in day_bars if ny_s <= b.ts < ny_e]
            if len(entry_bars) <= orb_bars + 1: continue

            if strategy == "orb_atr":
                sig = sig_orb_atr(entry_bars, atr, sym, orb_bars, atr_stop, target_r)
            elif strategy == "orb_half":
                sig = sig_orb_half(entry_bars, atr, sym, orb_bars, target_r)
            else:
                sig = sig_vola(entry_bars, atr, sym, target_r)
            if sig: candidates.append((1, sig, sym, day_bars, ny_e))

        # Sort: London first, then by symbol alphabetically for determinism
        candidates.sort(key=lambda x: (x[0], x[2]))

        traded_syms: set = set()
        for prio, sig, sym, day_bars, end_utc in candidates:
            if traded >= max_per_day or balance <= daily_floor or halted:
                break
            if sym in traded_syms:   # max 1 trade per symbol per day
                continue
            t       = simulate(sig, day_bars, end_utc, sym)
            balance += t.pnl_cash
            day_pnl += t.pnl_cash
            day_trades.append(t)
            all_trades.append(t)
            traded += 1
            traded_syms.add(sym)
            peak_balance = max(peak_balance, balance)
            if balance < total_floor:
                halted = True; break
            if balance < daily_floor:
                break

        equity.append((d, balance))
        if day_pnl >= QUALIFYING_DAY_MIN:
            qual_days += 1
        if not phase1_done and balance >= PHASE1_TARGET and qual_days >= 3:
            phase1_done = True
            days_to_p1  = trading_days

    # Statistics
    n    = len(all_trades)
    wins = sum(1 for t in all_trades if t.exit_reason == "target")
    loss = sum(1 for t in all_trades if t.exit_reason == "stop")
    tim  = sum(1 for t in all_trades if t.exit_reason == "time")
    wr   = wins / n if n > 0 else 0.0
    ar   = sum(t.pnl_r for t in all_trades) / n if n > 0 else 0.0
    sr   = statistics.stdev(t.pnl_r for t in all_trades) if n > 1 else 0.0
    gw   = sum(t.pnl_cash for t in all_trades if t.pnl_cash > 0)
    gl   = abs(sum(t.pnl_cash for t in all_trades if t.pnl_cash <= 0))
    pf   = gw/gl if gl > 0 else (float("inf") if gw > 0 else 0.0)
    tc   = sum(t.pnl_cash for t in all_trades)
    # True peak-to-trough drawdown: scan equity in sequence, track running peak
    _running_peak = ACCOUNT_BALANCE
    _max_dd_abs   = 0.0
    for _, _v in equity:
        _running_peak = max(_running_peak, _v)
        _max_dd_abs   = max(_max_dd_abs, _running_peak - _v)
    mdd = _max_dd_abs / _running_peak * 100 if _running_peak > 0 else 0.0
    mth  = tc * (21.0 / max(trading_days, 1))
    sha  = ar / sr if sr > 0 else 0.0

    per_pair: dict = defaultdict(lambda: {"n":0,"w":0,"pnl":0.0,"r":0.0})
    for t in all_trades:
        pp = per_pair[t.pair]
        pp["n"]   += 1
        pp["w"]   += 1 if t.exit_reason == "target" else 0
        pp["pnl"] += t.pnl_cash
        pp["r"]   += t.pnl_r

    return {
        "strategy": strategy, "target_r": target_r,
        "orb_bars": orb_bars, "atr_stop": atr_stop,
        "signals": n, "wins": wins, "losses": loss, "time_exits": tim,
        "win_rate": wr, "avg_r": ar, "std_r": sr,
        "profit_factor": pf, "total_cash": tc,
        "monthly_pnl": mth, "sharpe": sha, "max_dd_pct": mdd,
        "trading_days": trading_days, "days_to_p1": days_to_p1,
        "phase1_done": phase1_done, "halted": halted,
        "final_balance": balance, "equity": equity,
        "all_trades": all_trades, "per_pair": dict(per_pair),
        "qual_days": qual_days,
    }

# ---------------------------------------------------------------------------
# Grid search
# ---------------------------------------------------------------------------

def run_grid(cache: dict) -> list[dict]:
    combos = []
    for stg in STRATEGY_GRID:
        for tr in TARGET_R_GRID:
            for rb in ORB_BARS_GRID:
                for at in ATR_STOP_GRID:
                    if stg != "orb_atr" and at != ATR_STOP_GRID[0]:
                        continue
                    combos.append((stg, tr, rb, at))

    print(f"\nRunning {len(combos)} combinations...")
    results = []
    for i, (stg, tr, rb, at) in enumerate(combos, 1):
        r = run_backtest(cache, stg, tr, rb, at)
        results.append(r)
        if i % 10 == 0:
            print(f"  {i}/{len(combos)}...", flush=True)
    print(f"  {len(combos)}/{len(combos)} done")
    return results

# ---------------------------------------------------------------------------
# Leaderboard
# ---------------------------------------------------------------------------

def print_leaderboard(results: list[dict]) -> list[dict]:
    viable = [r for r in results
              if r["signals"] >= 15 and r["avg_r"] > 0
              and not r["halted"] and r["max_dd_pct"] < 9.0]
    viable.sort(key=lambda r: (
        -(1 if r["phase1_done"] else 0),
        r["days_to_p1"] if r["days_to_p1"] else 9999,
        -r["monthly_pnl"],
    ))
    top = viable[:20]

    print(f"\n{'='*105}")
    print("TOP COMBINATIONS — fastest Phase 1, then monthly P&L  (sigs>=15, avgR>0, dd<9%, not halted)")
    print(f"{'='*105}")
    hdr = (f"{'#':<4}{'Strat':<10}{'TR':<5}{'RB':<4}{'ATs':<6}"
           f"{'Sigs':<7}{'WR%':<7}{'AvgR':<8}{'PF':<7}"
           f"{'DD%':<6}{'Mth$':<11}{'P1?':<6}{'DaysP1':<9}{'FinalBal'}")
    print(hdr); print("-"*len(hdr))

    for i, r in enumerate(top, 1):
        pf_s = f"{r['profit_factor']:.2f}" if r['profit_factor'] != float("inf") else "inf"
        p1   = "YES" if r["phase1_done"] else "no"
        dp1  = str(r["days_to_p1"]) if r["days_to_p1"] else "--"
        print(
            f"{i:<4}{r['strategy']:<10}{r['target_r']:<5}{r['orb_bars']:<4}{r['atr_stop']:<6.2f}"
            f"{r['signals']:<7}{r['win_rate']*100:<7.1f}{r['avg_r']:<8.3f}{pf_s:<7}"
            f"{r['max_dd_pct']:<6.1f}${r['monthly_pnl']:<10.2f}{p1:<6}{dp1:<9}"
            f"${r['final_balance']:.2f}"
        )

    if not viable:
        print("No viable combos found. Showing top 5 by avg_r (no filter):")
        for r in sorted(results, key=lambda r: r["avg_r"], reverse=True)[:5]:
            print(f"  {r['strategy']} T={r['target_r']} RB={r['orb_bars']} at={r['atr_stop']}"
                  f" sigs={r['signals']} wr={r['win_rate']*100:.0f}% avgR={r['avg_r']:.3f}"
                  f" dd={r['max_dd_pct']:.1f}% halted={r['halted']}")

    return top

# ---------------------------------------------------------------------------
# Deep-dive on best result
# ---------------------------------------------------------------------------

def print_deep_dive(r: dict) -> None:
    print(f"\n{'='*65}")
    print("BEST CONFIGURATION DEEP-DIVE")
    print(f"{'='*65}")
    print(f"Strategy : {r['strategy']}  |  Target={r['target_r']}R"
          f"  |  ORB={r['orb_bars']}bars ({r['orb_bars']*5}min)"
          f"  |  ATR stop={r['atr_stop']}")
    print(f"  Signals      : {r['signals']}  ({r['wins']}W/{r['losses']}L/{r['time_exits']}T)")
    print(f"  Win rate     : {r['win_rate']*100:.1f}%")
    print(f"  Avg R        : {r['avg_r']:.3f}")
    pf_s = f"{r['profit_factor']:.2f}" if r['profit_factor'] != float('inf') else "inf"
    print(f"  Prof. factor : {pf_s}")
    print(f"  Max drawdown : {r['max_dd_pct']:.1f}%")
    print(f"  Total P&L    : ${r['total_cash']:.2f}  over {r['trading_days']} days")
    print(f"  Est. monthly : ${r['monthly_pnl']:.2f}")
    print(f"  Sharpe-R     : {r['sharpe']:.3f}")
    print(f"  Final balance: ${r['final_balance']:.2f}")
    print(f"  Phase 1      : {'PASSED in '+str(r['days_to_p1'])+' days' if r['phase1_done'] else 'not completed'}")
    print(f"  Qual. days   : {r['qual_days']}")
    print()
    print("  Per-pair:")
    print(f"  {'Pair':<10}{'N':<6}{'WR%':<8}{'P&L$':<12}{'R'}")
    for sym, pp in sorted(r["per_pair"].items(), key=lambda x: x[1]["pnl"], reverse=True):
        wr = pp["w"]/pp["n"]*100 if pp["n"] > 0 else 0
        print(f"  {sym:<10}{pp['n']:<6}{wr:<8.1f}${pp['pnl']:<11.2f}{pp['r']:.2f}")
    print()

    # ASCII equity curve
    curve = r["equity"]
    step  = max(1, len(curve)//35)
    sample = curve[::step]
    vmin  = min(v for _,v in curve)
    vmax  = max(v for _,v in curve)
    vrang = max(vmax - vmin, 1)
    W     = 45
    print("  Equity curve:")
    for d, v in sample:
        bar = int((v-vmin)/vrang*W)
        flag = " <<TARGET" if v >= PHASE1_TARGET else (" <<FLOOR!" if v < 2250 else "")
        print(f"  {str(d):<12} ${v:>7.0f} |{'#'*bar}{flag}")

# ---------------------------------------------------------------------------
# Findings writer
# ---------------------------------------------------------------------------

def write_findings(results: list[dict], top: list[dict]) -> None:
    best = top[0] if top else None

    # Strategy summary
    strat_rows = ""
    for stg in STRATEGY_GRID:
        rs = [r for r in results if r["strategy"] == stg and r["signals"] >= 5]
        if not rs: continue
        pos  = sum(1 for r in rs if r["avg_r"] > 0)
        bst  = max(rs, key=lambda r: r["monthly_pnl"])
        strat_rows += (f"| `{stg}` | {len(rs)} | {pos}/{len(rs)} | "
                       f"{bst['win_rate']*100:.1f}% | {bst['avg_r']:.3f} | "
                       f"${bst['monthly_pnl']:.2f} |\n")

    # Top table
    top_rows = ""
    for i, r in enumerate(top[:10], 1):
        pf_s = f"{r['profit_factor']:.2f}" if r['profit_factor'] != float('inf') else "inf"
        dp1  = str(r['days_to_p1']) if r['phase1_done'] else "—"
        top_rows += (f"| {i} | {r['strategy']} | {r['target_r']} | {r['orb_bars']} | "
                     f"{r['atr_stop']} | {r['signals']} | {r['win_rate']*100:.1f}% | "
                     f"{r['avg_r']:.3f} | {pf_s} | {r['max_dd_pct']:.1f}% | "
                     f"${r['monthly_pnl']:.2f} | {dp1} | ${r['final_balance']:.2f} |\n")

    # Per-pair aggregated best
    pair_agg: dict = defaultdict(lambda: {"n":0,"w":0,"pnl":0.0})
    for r in results:
        for sym, pp in r["per_pair"].items():
            pair_agg[sym]["n"]   += pp["n"]
            pair_agg[sym]["w"]   += pp["w"]
            pair_agg[sym]["pnl"] += pp["pnl"]
    pair_rows = ""
    for sym, pp in sorted(pair_agg.items(), key=lambda x: x[1]["pnl"]/max(x[1]["n"],1), reverse=True):
        wr = pp["w"]/pp["n"]*100 if pp["n"] > 0 else 0
        pair_rows += f"| {sym} | {pp['n']} | {wr:.1f}% | ${pp['pnl']:.2f} |\n"

    best_sec = ""
    if best:
        dp1 = f"PASSED in {best['days_to_p1']} trading days" if best["phase1_done"] else "NOT completed in test window"
        best_sec = f"""
## 4. Best Configuration

**Strategy: `{best['strategy']}` | Target={best['target_r']}R | ORB={best['orb_bars']} bars ({best['orb_bars']*5} min) | ATR stop={best['atr_stop']}×ATR**

| Metric | Value |
|---|---|
| Total signals | {best['signals']} ({best['wins']}W / {best['losses']}L / {best['time_exits']}T) |
| Win rate | {best['win_rate']*100:.1f}% |
| Avg R per trade | {best['avg_r']:.3f} |
| Profit factor | {f"{best['profit_factor']:.2f}" if best['profit_factor'] != float('inf') else 'inf'} |
| Max drawdown | {best['max_dd_pct']:.1f}% |
| Total P&L ({best['trading_days']} days) | ${best['total_cash']:.2f} |
| Est. monthly P&L | ${best['monthly_pnl']:.2f} |
| Final balance | ${best['final_balance']:.2f} |
| Phase 1 result | {dp1} |
| Qualifying days | {best['qual_days']} |

### Expected challenge timeline

With `${best['monthly_pnl']:.0f}` estimated monthly P&L and Profile A (0.40% risk):
- Phase 1 needs +$250: estimated **{max(1, int(250/max(best['monthly_pnl'],1)*30))} calendar days** at this run rate
- Phase 2 needs +$125: estimated **{max(1, int(125/max(best['monthly_pnl'],1)*30))} calendar days**

### Per-pair contribution (best config)

| Pair | Trades | Win% | Total P&L |
|---|---|---|---|
"""
        for sym, pp in sorted(best["per_pair"].items(), key=lambda x: x[1]["pnl"], reverse=True):
            wr = pp["w"]/pp["n"]*100 if pp["n"] > 0 else 0
            best_sec += f"| {sym} | {pp['n']} | {wr:.1f}% | ${pp['pnl']:.2f} |\n"

    md = f"""# Aggressive Multi-Pair Optimizer — Findings

**Generated by:** `tools/aggressive_optimizer.py`
**Data:** 11 pairs M5 OHLCV, Jan 2024 – Sep 2026 (~2.5 years, 200K bars/pair)
**Pairs:** EURUSD GBPUSD EURGBP GBPJPY EURJPY AUDUSD USDCHF NZDUSD USDJPY USDCAD XAUUSD
**Challenge:** The5ers $2,500 New High Stakes — Phase 1 +10%, Phase 2 +5%

---

## 1. Approach

Three strategies × 4 target R × 3 ORB sizes × 3 ATR stops = {len(results)} combinations.
Lot sizing uses **fixed $2,500 base** (no compounding) to match the challenge risk model.
Max 2 trades per day to respect the challenge's spirit (aggressive but not reckless).

### Strategies tested

| Strategy | Entry | Stop |
|---|---|---|
| `orb_atr` | First M5 close beyond ORB high/low | Fixed ATR fraction from entry |
| `orb_half` | First M5 close beyond ORB high/low | Opening range midpoint |
| `vola` | Bar with range > 1.5×ATR, in bar direction | Bar midpoint |

### Session windows (DST-correct)

| Session | Window | Pairs |
|---|---|---|
| London | 07:00–11:00 Europe/London | EURUSD GBPUSD EURGBP GBPJPY EURJPY AUDUSD USDCHF NZDUSD XAUUSD |
| New York | 08:30–11:00 America/New_York | USDJPY USDCAD EURUSD GBPUSD XAUUSD |

---

## 2. Strategy Comparison

| Strategy | Combos | Positive R | Best WR% | Best AvgR | Best Mth$ |
|---|---|---|---|---|---|
{strat_rows.rstrip()}

---

## 3. Top 10 Results (Phase 1 fastest, then monthly P&L)

| # | Strat | TR | RB | ATs | Sigs | WR% | AvgR | PF | DD% | Mth$ | DaysP1 | FinalBal |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
{top_rows.rstrip() if top_rows.strip() else "| — | No viable combos met all criteria | | | | | | | | | | | |"}
{best_sec}

---

## 5. Per-Pair Performance (aggregated across all combinations)

| Pair | Total Trades | Avg Win% | Total P&L |
|---|---|---|---|
{pair_rows.rstrip()}

---

## 6. Key Design Decisions

1. **Fixed lot sizing** — always size off $2,500 regardless of current balance.
   This prevents compounding from blowing the account on a drawdown sequence.
   The challenge effectively requires this anyway (phase floor = $2,250).

2. **Max 2 trades/day** — avoids overexposure on correlated pairs (EURUSD+GBPUSD
   often move together). A 2-trade limit with 0.40% risk = 0.80% max daily risk.

3. **ATR-fixed stop** — decouples stop size from opening range width. A wide
   opening range no longer forces a wide stop, solving the v1 ORB problem.

4. **All 11 pairs including XAUUSD** — gold has very high ATR and clean session
   breakouts. Its contribution is measured, not assumed.

---

## 7. Next Steps

1. Forward-test best config on MT5 demo for 2 weeks.
2. Add news filter (30-min blackout around high-impact events).
3. Consider compounding at 50% of gains once Phase 1 is passed.

---

*Auto-generated by `tools/aggressive_optimizer.py`*
"""
    out = Path("findings_aggressive_optimizer.md")
    out.write_text(md, encoding="utf-8")
    print(f"Findings written -> {out}")

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    print("=" * 60)
    print("Aggressive Multi-Pair Challenge Optimizer")
    print("=" * 60)
    print("\nLoading and preprocessing all pairs...")

    cache: dict = {}
    for sym in SPECS:
        bars = load_pair(sym)
        if bars:
            by_date, atr_map = preprocess(bars)
            cache[sym] = (by_date, atr_map)
            print(f"  {sym:<8} {len(bars):>7} bars  {len(by_date)} days")
        else:
            print(f"  {sym:<8} [no file]")

    if not cache:
        print("No data loaded."); return

    results = run_grid(cache)
    top     = print_leaderboard(results)
    if top:
        print_deep_dive(top[0])
    write_findings(results, top)


if __name__ == "__main__":
    main()
