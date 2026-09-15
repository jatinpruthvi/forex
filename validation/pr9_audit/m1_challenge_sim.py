"""
PR #9 (M1 Momentum Reversion) — challenge-rule validation engine.

Rebuilds tools/m1_holy_grail.py as an exactly-equivalent but ~50x faster
trade-list engine, then layers on the things the PR omitted:

  * real transaction costs (repo-canonical model from tools/optimizer_v2.py:
    SPREAD_STD["EURUSD"] * RAW_SCALE round-trip spread + COMM_RT $/lot)
  * real position sizing with 0.01 lot step rounding + min-lot reject
  * The5ers $2,500 New High Stakes rule gates:
      - $2,250 equity termination floor (10% overall loss)
      - 5% daily loss boundary
      - personal -5% drawdown stop (THE5ERS-2.5K-CHALLENGE-PLAN.md s.8)
      - +10% target AND >= 3 qualifying days (net >= $12.50 at midnight snapshot)
  * correct server-time (UTC+3) day bucketing instead of UTC calendar date
  * walk-forward start-date sampling (the PR reports one lucky window)
"""
from __future__ import annotations

import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.m1_holy_grail import load_m1_data, atr  # noqa: E402

# --------------------------------------------------------------------------
# Constants
# --------------------------------------------------------------------------
ACCOUNT      = 2500.0
FLOOR        = 2250.0          # firm static termination floor (equity)
DAILY_LOSS   = 0.05            # firm daily loss boundary
PERSONAL_DD  = 0.05            # plan s.8 personal shutdown
TARGET       = ACCOUNT * 1.10  # Phase 1 = $2,750
QUAL_DAY_MIN = 12.50           # min net profit for a qualifying day
QUAL_DAYS_N  = 3

PIP          = 0.0001
PV           = 10.0            # $/pip per standard lot, EURUSD
SPREAD_RT    = (0.00010 * 0.55) / PIP   # pips, repo raw-account model = 0.55
COMM_RT      = 7.0             # $/lot round turn, repo raw-account model
VOL_MIN      = 0.01
VOL_STEP     = 0.01
SERVER_OFF   = 3               # Eightcap/The5ers server = UTC+3

DATA = ROOT / "validation/HistoryData/m1-data/eurusd-m1-2024-09-11_2026-09-11.csv"


@dataclass
class Cand:
    """A pre-resolved candidate trade (entry bar -> outcome)."""
    i: int               # entry bar index
    ts: datetime         # entry bar timestamp (UTC)
    direction: int       # +1 long, -1 short
    entry: float
    stop: float
    target: float
    stop_pips: float
    exit_i: int          # bar index where it resolves
    exit_ts: datetime
    win: bool
    timed_out: bool = False


def build_candidates(bars, threshold=2.5, stop_atr=1.5, target_r=1.5,
                     max_trades_per_day=5, day_offset_hours=0,
                     max_hold_min=None, flat_at_rollover=False):
    """Pre-resolve every signal exactly as m1_holy_grail.py does.

    The PR's engine is single-position, so a candidate's outcome depends only
    on forward bars -> outcomes can be resolved once and replayed for any
    start date / cost model.
    """
    cands: list[Cand] = []
    n = len(bars)
    off = timedelta(hours=day_offset_hours)
    cur_day = None
    trades_today = 0
    busy_until = -1

    for i in range(14, n):
        if i <= busy_until:
            continue
        b = bars[i]
        d = (b.ts + off).date()
        if d != cur_day:
            cur_day, trades_today = d, 0
        if trades_today >= max_trades_per_day:
            continue

        a = atr(bars[i - 14:i], 14)   # == PR's bars[bi-15:bi-1] with bi = i+1
        if a == 0:
            continue
        body = abs(b.open - b.close)
        if body <= threshold * a:
            continue

        trades_today += 1
        if b.close > b.open:
            direction = -1
            stop = b.high + stop_atr * a
            target = b.close - target_r * (stop - b.close)
        else:
            direction = 1
            stop = b.low - stop_atr * a
            target = b.close + target_r * (b.close - stop)

        # --- forward scan: PESSIMISTIC (stop checked before target) ---------
        win, exit_i, timed_out = False, n - 1, True
        deadline = b.ts + timedelta(minutes=max_hold_min) if max_hold_min else None
        for j in range(i + 1, n):
            bj = bars[j]
            if flat_at_rollover and (bj.ts + off).date() != d:
                exit_i, timed_out = j - 1, True
                break
            if deadline is not None and bj.ts >= deadline:
                exit_i, timed_out = j - 1, True
                break
            if direction == 1:
                if bj.low <= stop:
                    win, exit_i, timed_out = False, j, False; break
                if bj.high >= target:
                    win, exit_i, timed_out = True, j, False; break
            else:
                if bj.high >= stop:
                    win, exit_i, timed_out = False, j, False; break
                if bj.low <= target:
                    win, exit_i, timed_out = True, j, False; break
        else:
            exit_i = n - 1

        cands.append(Cand(i=i, ts=b.ts, direction=direction, entry=b.close,
                          stop=stop, target=target,
                          # TRUE entry->stop distance. The PR books P&L as a flat
                          # +/- risk_pct, i.e. it assumes R == stop_atr*ATR, but it
                          # enters at the bar CLOSE and puts the stop beyond the bar
                          # WICK, so the real R is |close-stop| = wick + stop_atr*ATR.
                          stop_pips=abs(b.close - stop) / PIP,
                          exit_i=exit_i, exit_ts=bars[exit_i].ts,
                          win=win, timed_out=timed_out))
        busy_until = exit_i
    return cands


def size_lots(stop_pips: float, risk_cash: float) -> float:
    loss_per_lot = stop_pips * PV + COMM_RT
    if loss_per_lot <= 0:
        return 0.0
    lots = int((risk_cash / loss_per_lot) / VOL_STEP) * VOL_STEP
    return round(lots, 2)


@dataclass
class SimResult:
    passed: bool
    bust_floor: bool
    bust_daily: bool
    bust_personal_dd: bool
    days_to_pass: int            # calendar days first_trade -> pass
    tdays_to_pass: int           # server trading days first_trade -> pass
    qual_days: int
    trades: int
    wins: int
    wr: float
    max_dd: float
    pnl: float
    end_balance: float
    cost_drag: float
    pass_ts: datetime | None
    bust_ts: datetime | None
    daily_losses: list
    first_target_ts: datetime | None = None
    days_to_target: int = -1


def simulate(cands, bars, *, risk_pct=0.005, costs=True, risk_cash=None,
             enforce_floor=True, enforce_daily=True, enforce_personal_dd=True,
             start_ts=None, day_offset_hours=SERVER_OFF, qual_days_needed=QUAL_DAYS_N,
             stop_on_pass=True):
    risk_cash = risk_cash if risk_cash is not None else ACCOUNT * risk_pct
    off = timedelta(hours=day_offset_hours)

    balance, peak = ACCOUNT, ACCOUNT
    max_dd = 0.0
    pnl = 0.0
    wins = trades = 0
    cost_total = 0.0
    first_ts = None
    pass_ts = None
    bust_ts = None
    bust_floor = bust_daily = bust_personal = False
    qual_days = 0
    daily_losses: list = []
    first_target_ts = None

    day_key = None
    day_start_balance = ACCOUNT
    day_pnl = 0.0
    day_closed = False

    def close_day():
        nonlocal qual_days
        if day_pnl >= QUAL_DAY_MIN:
            qual_days += 1
        if day_pnl <= -(day_start_balance * DAILY_LOSS):
            daily_losses.append((day_key, day_pnl))

    for c in cands:
        if start_ts is not None and c.ts < start_ts:
            continue
        dk = (c.ts + off).date()
        if dk != day_key:
            if day_key is not None:
                close_day()
            day_key, day_start_balance, day_pnl = dk, balance, 0.0
            day_closed = False

        if bust_floor or bust_daily or bust_personal:
            break
        if day_closed:
            continue

        # ---- sizing ----
        if costs:
            lots = size_lots(c.stop_pips, risk_cash)
            if lots < VOL_MIN:
                continue
            spread_cash = lots * SPREAD_RT * PV
            comm_cash = COMM_RT * lots
        else:
            lots = risk_cash / (c.stop_pips * PV) if c.stop_pips > 0 else 0.0
            spread_cash = comm_cash = 0.0

        if c.timed_out:
            # held to end of data / rollover: mark-to-market at exit bar close
            eb = bars[c.exit_i]
            move = ((eb.close - c.entry) if c.direction == 1
                    else (c.entry - eb.close)) / PIP
            gross = lots * move * PV
            win = False
        elif c.win:
            move = abs(c.target - c.entry) / PIP
            gross = lots * move * PV
            win = True
        else:
            move = -c.stop_pips
            gross = lots * move * PV
            win = False

        net = gross - spread_cash - comm_cash
        cost_total += spread_cash + comm_cash

        balance += net
        day_pnl += net
        pnl += net
        trades += 1
        wins += 1 if win else 0
        if first_ts is None:
            first_ts = c.ts

        peak = max(peak, balance)
        dd = (peak - balance) / peak
        max_dd = max(max_dd, dd)

        # ---- rule gates ----
        if enforce_floor and balance <= FLOOR:
            bust_floor, bust_ts = True, c.exit_ts
            break
        if enforce_daily and day_pnl <= -(day_start_balance * DAILY_LOSS):
            bust_daily, bust_ts = True, c.exit_ts
            day_closed = True
            break
        if enforce_personal_dd and dd >= PERSONAL_DD:
            bust_personal, bust_ts = True, c.exit_ts
            break

        if first_target_ts is None and balance >= TARGET:
            first_target_ts = c.exit_ts

        if stop_on_pass and balance >= TARGET and qual_days >= qual_days_needed:
            pass_ts = c.exit_ts
            break

    if day_key is not None and pass_ts is None:
        close_day()

    passed = pass_ts is not None
    days = tdays = -1
    if passed and first_ts:
        days = (pass_ts - first_ts).days
        tdays = len({(b.ts + off).date() for b in bars
                     if first_ts <= b.ts <= pass_ts
                     and (b.ts + off).weekday() < 5})
    return SimResult(passed=passed, bust_floor=bust_floor, bust_daily=bust_daily,
                     bust_personal_dd=bust_personal, days_to_pass=days,
                     tdays_to_pass=tdays, qual_days=qual_days, trades=trades,
                     wins=wins, wr=(wins / trades if trades else 0.0),
                     max_dd=max_dd, pnl=pnl, end_balance=balance,
                     cost_drag=cost_total, pass_ts=pass_ts, bust_ts=bust_ts,
                     daily_losses=daily_losses,
                     first_target_ts=first_target_ts,
                     days_to_target=((first_target_ts - first_ts).days
                                     if first_target_ts and first_ts else -1))
