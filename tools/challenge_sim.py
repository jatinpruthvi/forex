#!/usr/bin/env python3
"""Two-phase prop-challenge simulator on a list of R-denominated trades (The5ers High Stakes as modelled in the repo profile):
Phase 1 +10%, Phase 2 +5% (balance reset to 100 after phase 1), static floor -10% of the phase's initial balance,
daily closed-P&L loss limit (default 4.5%, i.e. the repo's buffer under the 5% rule) on the UTC+3 server day,
whole challenge must finish inside `max_days` calendar days from the start date. Fixed-fractional risk on the PHASE INITIAL balance
(non-compounding, like a fixed-dollar risk). Slots: `max_conc` concurrent positions (default 1, the repo's one-slot rule).
Not modelled: the minimum qualifying-days rule (>=3 days at +0.5%), the 30-day inactivity rule, intra-trade equity drawdown.
Both are stated in every report that uses this module.

A trade is dict(t_fill, t_exit, R (gross, strict), cost (R units)). Net R = R - cost.
"""
from __future__ import annotations

import numpy as np

MS_D = 86_400_000
SRV_OFF = 3 * 3_600_000


def simulate_start(trades: list[dict], t0: int, risk: float, max_days: int = 90, p1: float = 10.0, p2: float = 5.0,
                   floor: float = 10.0, daily: float = 4.5, max_conc: int = 1, net=None) -> dict:
    """trades sorted by t_fill. Returns outcome for a challenge started at ms t0."""
    end = t0 + max_days * MS_D
    bal, phase, base = 100.0, 1, 100.0
    open_x: list[float] = []          # exit times of open positions
    day, day_start, day_pnl = None, bal, 0.0
    ev = []
    for t in trades:
        if t["t_fill"] < t0 or t["t_fill"] >= end:
            continue
        ev.append(t)
    p1_day = None
    for t in ev:
        # positions that exited before this fill free their slot; realise them in exit order first
        open_x = [x for x in open_x if x > t["t_fill"]]
        if len(open_x) >= max_conc:
            continue
        r = (t["R"] - t["cost"]) if net is None else net(t)
        if t["t_exit"] > end:
            continue                    # would not have closed inside the window -> ignored (conservative for both sides)
        open_x.append(t["t_exit"])
        dk = (t["t_exit"] + SRV_OFF) // MS_D
        if dk != day:
            day, day_start, day_pnl = dk, bal, 0.0
        pnl = r * risk * base            # risk % of the phase's initial balance
        bal += pnl
        day_pnl += pnl
        if bal <= base * (1 - floor / 100) + 1e-9:
            return dict(res="floor", phase=phase, days=(t["t_exit"] - t0) / MS_D)
        if day_pnl <= -(daily / 100) * base:
            return dict(res="daily", phase=phase, days=(t["t_exit"] - t0) / MS_D)
        tgt = p1 if phase == 1 else p2
        if bal >= base * (1 + tgt / 100) - 1e-9:
            if phase == 1:
                phase, p1_day = 2, (t["t_exit"] - t0) / MS_D
                bal = base = 100.0
                day, day_start, day_pnl = None, bal, 0.0
            else:
                return dict(res="pass", phase=2, days=(t["t_exit"] - t0) / MS_D, p1_days=p1_day)
    return dict(res="timeout", phase=phase, days=max_days, p1_days=p1_day)


def pass_rates(trades: list[dict], lo: int, hi: int, risk: float, step_days: int = 7, max_days: int = 90, **kw) -> dict:
    """Start a challenge every `step_days` inside [lo, hi - max_days]; summarise outcomes."""
    tr = sorted(trades, key=lambda t: t["t_fill"])
    starts = list(range(lo, hi - max_days * MS_D + 1, step_days * MS_D))
    out = [simulate_start(tr, s, risk, max_days=max_days, **kw) for s in starts]
    n = len(out)
    if not n:
        return dict(n_starts=0)
    c = lambda k: sum(o["res"] == k for o in out) / n
    reach1 = sum((o["res"] == "pass") or (o["phase"] == 2) for o in out) / n
    pd_ = [o["days"] for o in out if o["res"] == "pass"]
    return dict(n_starts=n, pass_rate=c("pass"), phase1_reached=reach1, floor=c("floor"), daily=c("daily"), timeout=c("timeout"),
                median_days_pass=float(np.median(pd_)) if pd_ else None, risk=risk)


def zero_edge(trades: list[dict], seed: int = 1) -> list[dict]:
    """Null: keep timing, sizes and costs, remove the mean gross edge (gross R minus its mean). Shows the lottery baseline."""
    g = np.array([t["R"] for t in trades])
    return [dict(t, R=float(t["R"] - g.mean())) for t in trades]
