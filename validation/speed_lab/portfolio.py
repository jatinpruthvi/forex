"""
speed_lab/portfolio.py — gate-aware portfolio replay.

Takes a fixed trade list (from engine.signals + engine.resolve) and replays it
as a The5ers $2,500 Phase-1 attempt, enforcing the rules the firm actually
enforces:

  * equity termination floor $2,250  (checked conservatively: balance minus the
    full risk of every open position must stay above the floor)
  * 5% daily loss boundary on the SERVER day (UTC+3), same conservative basis
  * >= 3 qualifying days, each with closed net >= $12.50 at the server midnight
  * +10% target on closed balance
  * optional flat-at-weekend, max concurrent positions, max trades/day,
    intra-day circuit breaker after N net losing R

Because the trade list is fixed, the same list can be replayed from many start
dates -> an honest distribution of days-to-pass instead of one lucky window.
"""
from __future__ import annotations

import numpy as np
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone

import engine as E

MS_DAY = 86_400_000
SRV = E.SERVER_OFF_H * 3_600_000


@dataclass
class Trade:
    sym: str
    entry_ts: int          # ms UTC
    exit_ts: int
    win: bool
    R_gross: float         # gross R (+target_r or -1 or mtm fraction)
    stop_pips: float
    cost_R: float          # round-trip cost as a fraction of 1R


@dataclass
class Cfg:
    risk_pct: float = 0.01          # risk per trade, fraction of sizing base
    risk_mode: str = "initial"      # "initial" | "equity"
    max_trades_day: int = 99
    max_concurrent: int = 99
    daily_stop_R: float = 1e9       # stop opening after this many net losing R on the day
    flat_weekend: bool = True
    spread_scale: float = 1.0
    slippage_R: float = 0.0         # extra cost in R (stress)
    account: float = E.ACCOUNT


@dataclass
class Result:
    passed: bool = False
    fail_reason: str = ""
    days: int = -1                  # calendar days first trade -> pass
    tdays: int = -1                 # server trading days
    trades: int = 0
    wins: int = 0
    max_dd: float = 0.0
    qual_days: int = 0
    end_balance: float = 0.0
    worst_day: float = 0.0
    daily_breaches: int = 0
    max_concurrent_seen: int = 0
    net_R: float = 0.0
    first_ts: int = 0
    pass_ts: int = 0


def build_trades(per_pair: dict, spread_scale: float = 1.0) -> list[Trade]:
    """per_pair: {sym: resolved dict from engine.resolve}. Merged, time-sorted."""
    out = []
    for sym, r in per_pair.items():
        cr = E.cost_R(sym, r["stop_pips"], spread_scale)
        for i in range(len(r["win"])):
            out.append(Trade(sym, int(r["ts"][i]), int(r["exit_ts"][i]),
                             bool(r["win"][i]), float(r["R_gross"][i]),
                             float(r["stop_pips"][i]), float(cr[i])))
    out.sort(key=lambda t: t.entry_ts)
    return out


def replay(trades: list[Trade], cfg: Cfg, start_ts: int = 0,
           end_ts: int = 1 << 62) -> Result:
    """Event-driven replay over a merged entry/exit stream so that daily P&L is
    booked on the SERVER day the position actually closes."""
    A = cfg.account
    floor = E.FLOOR
    bal, peak, max_dd = A, A, 0.0
    qual_days = 0
    day_key, day_start, day_pnl = -1, A, 0.0
    worst_day, daily_breaches = 0.0, 0
    trades_today, day_locked = 0, False
    open_pos: dict[int, float] = {}      # id(trade) -> risk cash committed
    open_risk = 0.0
    first_ts = 0
    ntr = wins = 0
    netR = 0.0
    maxconc = 0
    res = Result(end_balance=A)

    sel = [t for t in trades if start_ts <= t.entry_ts <= end_ts]
    if not sel:
        res.fail_reason = "no trades in window"
        return res

    # merged event stream: 0 = entry, 1 = exit (exits sort before entries at equal ts)
    ev = [(t.entry_ts, 0, t) for t in sel] + [(t.exit_ts, 1, t) for t in sel]
    ev.sort(key=lambda x: (x[0], x[1]))

    def finish(reason, passed, ts):
        res.fail_reason = reason
        res.passed = passed
        return _fin(res, bal, max_dd, qual_days, ntr, wins, worst_day,
                    daily_breaches, maxconc, netR, first_ts, ts if passed else 0)

    for ts, kind, t in ev:
        dk = srv_day_of(ts)
        if dk != day_key:
            if day_key != -1:
                if day_pnl >= E.QUAL_DAY:
                    qual_days += 1
                worst_day = min(worst_day, day_pnl)
            day_key, day_start, day_pnl = dk, bal, 0.0
            trades_today, day_locked = 0, False

        if kind == 1:                                        # ---------- EXIT
            if id(t) not in open_pos:
                continue                                     # never opened (gated)
            r_cash = open_pos.pop(id(t))
            open_risk -= r_cash
            net = (t.R_gross - t.cost_R - cfg.slippage_R) * r_cash
            bal += net
            day_pnl += net
            netR += t.R_gross - t.cost_R - cfg.slippage_R
            ntr += 1
            wins += 1 if net > 0 else 0
            peak = max(peak, bal)
            max_dd = max(max_dd, (peak - bal) / peak)
            if bal <= floor:
                return finish(f"equity floor ${bal:.2f}", False, ts)
            if day_pnl <= -(day_start * E.DAILY_LOSS):
                daily_breaches += 1
                return finish(f"daily loss limit ${day_pnl:.2f}", False, ts)
            if bal >= E.TARGET and qual_days >= E.QUAL_DAYS_N:
                return finish("", True, ts)
            continue

        # ---------- ENTRY ----------
        if day_locked or trades_today >= cfg.max_trades_day:
            continue
        if len(open_pos) >= cfg.max_concurrent:
            continue
        if t.exit_ts <= ts:                                  # zero-length
            continue
        if cfg.flat_weekend:
            dt = datetime.fromtimestamp((ts + SRV) / 1000, tz=timezone.utc)
            if dt.hour >= 21 and dt.weekday() == 4:          # Fri 21:00 server
                day_locked = True
                continue

        base = A if cfg.risk_mode == "initial" else bal
        r_cash = base * cfg.risk_pct
        pv = E.SPECS[t.sym]["pv"]
        loss_per_lot = t.stop_pips * pv + E.COMM_RT
        if loss_per_lot <= 0:
            continue
        lots = int((r_cash / loss_per_lot) / E.VOL_STEP) * E.VOL_STEP
        if lots < E.VOL_MIN:
            continue
        # conservative: assume every open position is sitting at its stop
        if bal - open_risk - r_cash <= floor:
            continue
        if day_pnl - open_risk <= -(day_start * E.DAILY_LOSS) * 0.90:
            day_locked = True
            continue
        if day_pnl <= -(cfg.daily_stop_R * r_cash):
            day_locked = True
            continue

        if first_ts == 0:
            first_ts = ts
        trades_today += 1
        open_pos[id(t)] = r_cash
        open_risk += r_cash
        maxconc = max(maxconc, len(open_pos))

    if day_key != -1:
        if day_pnl >= E.QUAL_DAY:
            qual_days += 1
        worst_day = min(worst_day, day_pnl)
    return finish("target/qual-days not reached in window", False, 0)


def _risk_cash(t: Trade, cfg: Cfg, A: float, bal: float) -> float:
    base = A if cfg.risk_mode == "initial" else bal
    return base * cfg.risk_pct


def _fin(res, bal, max_dd, qual_days, ntr, wins, worst_day, db, maxconc, netR,
         first_ts, pass_ts) -> Result:
    res.end_balance = bal
    res.max_dd = max_dd
    res.qual_days = qual_days
    res.trades = ntr
    res.wins = wins
    res.worst_day = worst_day
    res.daily_breaches = db
    res.max_concurrent_seen = maxconc
    res.net_R = netR
    res.first_ts = first_ts
    res.pass_ts = pass_ts
    if res.passed and first_ts and pass_ts:
        res.days = int((pass_ts - first_ts) // MS_DAY)
        d0 = srv_day_of(first_ts)
        d1 = srv_day_of(pass_ts)
        res.tdays = int(sum(1 for k in range(d0, d1 + 1)
                            if datetime.fromtimestamp(k * 86400 - E.SERVER_OFF_H * 3600,
                                                      tz=timezone.utc).weekday() < 5))
    return res


def srv_day_of(ts): return (ts + SRV) // MS_DAY


def walk_forward(trades: list[Trade], cfg: Cfg, n_starts: int = 60,
                 span_ms: int | None = None) -> dict:
    if not trades:
        return dict(n=0)
    t0, t1 = trades[0].entry_ts, trades[-1].entry_ts
    span = span_ms or (t1 - t0)
    starts = [t0 + int(i * (span) / max(n_starts - 1, 1)) for i in range(n_starts)]
    rs = [replay(trades, cfg, start_ts=s) for s in starts]
    passed = [r for r in rs if r.passed]
    days = sorted(r.days for r in passed)
    reasons: dict[str, int] = {}
    for r in rs:
        if not r.passed:
            key = r.fail_reason.split("$")[0].split("@")[0].strip()[:34]
            reasons[key] = reasons.get(key, 0) + 1
    return dict(
        n=len(rs), n_pass=len(passed),
        pass_rate=len(passed) / len(rs),
        med_days=int(np.median(days)) if days else -1,
        p25_days=int(np.percentile(days, 25)) if days else -1,
        p75_days=int(np.percentile(days, 75)) if days else -1,
        p90_days=int(np.percentile(days, 90)) if days else -1,
        best_days=days[0] if days else -1,
        worst_days=days[-1] if days else -1,
        med_qual=int(np.median([r.qual_days for r in passed])) if passed else 0,
        max_dd=max(r.max_dd for r in rs),
        med_dd=float(np.median([r.max_dd for r in rs])),
        worst_day=min(r.worst_day for r in rs),
        max_conc=max(r.max_concurrent_seen for r in rs),
        med_trades=int(np.median([r.trades for r in rs])),
        reasons=reasons,
        results=rs,
    )
