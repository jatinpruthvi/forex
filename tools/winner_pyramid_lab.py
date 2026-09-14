"""Research-only winner-pyramiding lab.

This tests the safer enhancement discussed in the project conversation:
add one position only after the original TRIAD entry has moved in profit.  The
initial position's stop is moved to breakeven before the add is allowed, and
the added position is sized from the same basket risk budget.  The lab never
adds to a losing position and never widens a stop.

Scope is deliberately narrow: the current relaxed, pair-fitted TRIAD signal
on the five research symbols, with a one-account-wide slot and compounding.
The two-year data is the gate; the selected configuration is replayed unchanged
on the four-year data.  This is not an MQL5 release and does not modify either
EA.

Usage:
    python tools/winner_pyramid_lab.py --confirm
"""
from __future__ import annotations

import argparse
import hashlib
import math
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

sys.path.insert(0, os.path.abspath("."))
import tools.aggressive_optimizer as m  # noqa: E402
import tools.optimizer_v2 as v2  # noqa: E402
from tools.bounded_grid_lab import (  # noqa: E402
    Candidate,
    DATA_2Y,
    DATA_4Y,
    PAIRFIT,
    build_candidates,
)

START_BALANCE = m.ACCOUNT_BALANCE
VOLUME_STEP = m.VOLUME_STEP
VOLUME_MIN = m.VOLUME_MIN
MAX_DD_PERCENT = 15.0
DAILY_STOP_PERCENT = 4.0
MAX_BASKETS_PER_DAY = 2
STOP_SLIPPAGE_R = 0.10


@dataclass(frozen=True)
class Config:
    name: str
    trigger_r: float
    add_mode: str  # next_open or retest
    confirm: str  # touch or close


CONFIGS = [
    Config("base_control", 0.0, "none", "touch"),
    *[
        Config(f"p{trigger:g}_{mode}_{confirm}", trigger, mode, confirm)
        for trigger in (0.25, 0.50, 0.75)
        for mode in ("next_open", "retest")
        for confirm in ("touch", "close")
    ],
]


@dataclass
class Position:
    label: str
    entry: float
    stop: float
    lots: float


def _round_lots(raw: float) -> float:
    return max(0.0, math.floor((raw + 1e-12) / VOLUME_STEP) * VOLUME_STEP)


def _cost_per_lot(c: Candidate) -> float:
    spread = v2.SPREAD_STD[c.symbol] * v2.RAW_SCALE
    spread_cash = spread / m.SPECS[c.symbol]["pip"] * c.pip_value
    return v2.COMM_RT + spread_cash


def _cash_move(c: Candidate, entry: float, exit_price: float,
               lots: float) -> float:
    direction = 1.0 if c.side == "long" else -1.0
    move = (exit_price - entry) * direction
    return move / m.SPECS[c.symbol]["pip"] * c.pip_value * lots


def _adverse_stop(c: Candidate) -> float:
    slip = STOP_SLIPPAGE_R * abs(c.entry - c.stop)
    return c.stop - slip if c.side == "long" else c.stop + slip


def _level_touched(c: Candidate, bar, level: float) -> bool:
    return bar.low <= level if c.side == "long" else bar.high >= level


def _favorable_touched(c: Candidate, bar, level: float) -> bool:
    return bar.high >= level if c.side == "long" else bar.low <= level


def _favorable_close(c: Candidate, bar, level: float) -> bool:
    return bar.close >= level if c.side == "long" else bar.close <= level


def _target_touched(c: Candidate, bar, target: float) -> bool:
    return _favorable_touched(c, bar, target)


def _size_for_risk(c: Candidate, entry: float, stop: float,
                   budget: float) -> float:
    per_lot = abs(entry - stop) / m.SPECS[c.symbol]["pip"] * c.pip_value \
        + _cost_per_lot(c)
    return _round_lots(budget / per_lot) if per_lot > 0 else 0.0


def _close_position(c: Candidate, position: Position, exit_price: float,
                    *, stopped: bool = False) -> float:
    if stopped:
        exit_price = _adverse_stop(c) if position.stop == c.stop else position.stop
    return (_cash_move(c, position.entry, exit_price, position.lots)
            - _cost_per_lot(c) * position.lots)


def simulate(c: Candidate, bars: list, config: Config, balance: float,
             risk_fraction: float, ambiguity: str = "stop") -> dict | None:
    """Simulate one candidate with a fixed basket-risk ceiling.

    The base order is a limit at the TRIAD entry.  After the trigger is
    confirmed, the base stop becomes entry and one add is either filled at the
    next bar open or on a later retest of the trigger.  Same-bar target/stop
    conflicts use stop-first for the stress run.
    """
    fwd = [bar for bar in bars if c.signal_ts <= bar.ts < c.end_ts]
    if not fwd:
        return None
    budget = balance * risk_fraction
    base_lots = _size_for_risk(c, c.entry, c.stop, budget)
    if base_lots < VOLUME_MIN:
        return None
    span = abs(c.entry - c.stop)
    target = c.entry + c.target_r * span if c.side == "long" \
        else c.entry - c.target_r * span
    trigger = c.entry + config.trigger_r * span if c.side == "long" \
        else c.entry - config.trigger_r * span

    positions: list[Position] = []
    pending_add = False
    protected = False
    first_fill_ts = None
    exit_reason = "session_end"
    from datetime import timedelta
    exit_ts = fwd[-1].ts + timedelta(minutes=5)
    pnl = 0.0
    add_filled = False
    add_entry = None

    for i, bar in enumerate(fwd):
        # The original pending order fills on a retouch.  A fill is allowed to
        # be stopped on the same M5 bar; stress ordering is stop-first.
        if not positions:
            if _level_touched(c, bar, c.entry):
                positions.append(Position("base", c.entry, c.stop, base_lots))
                first_fill_ts = bar.ts
            else:
                continue

        # A winner confirmation happens only after the bar's protective checks.
        # If the same bar also hits the original stop, no add is permitted.
        active_stops = [p.stop for p in positions]
        hit_stop = any(_level_touched(c, bar, stop) for stop in active_stops)
        hit_target = _target_touched(c, bar, target)
        if hit_stop and hit_target:
            if ambiguity == "target":
                for p in positions:
                    pnl += _close_position(c, p, target)
                return dict(pnl=pnl, reason="target", exit_ts=bar.ts + timedelta(minutes=5),
                            add_filled=add_filled, fills=len(positions))
            if ambiguity == "coin":
                key = f"{c.day}|{c.symbol}|{c.signal_ts}|{config.name}"
                target_first = int(hashlib.md5(key.encode()).hexdigest(), 16) % 2 == 0
                if target_first:
                    for p in positions:
                        pnl += _close_position(c, p, target)
                    return dict(pnl=pnl, reason="target", exit_ts=bar.ts + timedelta(minutes=5),
                                add_filled=add_filled, fills=len(positions))
            # Conservative stop-first resolution for the pessimistic path.
            for p in positions:
                pnl += _close_position(c, p, p.stop, stopped=True)
            return dict(pnl=pnl, reason="stop", exit_ts=bar.ts + timedelta(minutes=5),
                        add_filled=add_filled, fills=len(positions))
        if hit_stop:
            survivors = []
            for p in positions:
                if _level_touched(c, bar, p.stop):
                    pnl += _close_position(c, p, p.stop, stopped=True)
                else:
                    survivors.append(p)
            positions = survivors
            if not positions:
                return dict(pnl=pnl, reason="stop", exit_ts=bar.ts + timedelta(minutes=5),
                            add_filled=add_filled, fills=0)
        if hit_target:
            for p in positions:
                pnl += _close_position(c, p, target)
            return dict(pnl=pnl, reason="target", exit_ts=bar.ts + timedelta(minutes=5),
                        add_filled=add_filled, fills=len(positions))

        # Fill a winner add only after the trigger bar.  For next_open, require
        # the next open still to be on the favorable side of the trigger.  For
        # retest, the level must be touched by a later bar.
        if (pending_add and not add_filled and config.add_mode == "next_open"
                and i > 0):
            add_price = bar.open
            favorable_open = (add_price >= trigger if c.side == "long"
                              else add_price <= trigger)
            if favorable_open:
                add_lots = _size_for_risk(c, add_price, c.stop, budget)
                if add_lots >= VOLUME_MIN:
                    positions.append(Position("add", add_price, c.stop, add_lots))
                    add_filled, add_entry = True, add_price
            pending_add = False
        elif (pending_add and not add_filled and config.add_mode == "retest"
              and i > 0 and _level_touched(c, bar, trigger)):
            add_lots = _size_for_risk(c, trigger, c.stop, budget)
            if add_lots >= VOLUME_MIN:
                positions.append(Position("add", trigger, c.stop, add_lots))
                add_filled, add_entry = True, trigger
            pending_add = False

        # Confirm the winner only after the bar's stop/target checks.  The base
        # stop moves to entry for the following bar; this avoids using the same
        # bar's high and low to grant both protection and an add.
        if (config.trigger_r > 0 and not protected):
            trigger_hit = (_favorable_close(c, bar, trigger)
                           if config.confirm == "close"
                           else _favorable_touched(c, bar, trigger))
            if trigger_hit and positions and any(p.label == "base" for p in positions):
                protected = True
                for p in positions:
                    if p.label == "base":
                        p.stop = p.entry
                pending_add = True

        if (first_fill_ts is not None
                and bar.ts >= first_fill_ts + timedelta(minutes=c.time_stop_min)):
            for p in positions:
                pnl += _close_position(c, p, bar.close)
            return dict(pnl=pnl, reason="time", exit_ts=bar.ts + timedelta(minutes=5),
                        add_filled=add_filled, fills=len(positions))

    for p in positions:
        pnl += _close_position(c, p, fwd[-1].close)
    return dict(pnl=pnl, reason=exit_reason, exit_ts=exit_ts,
                add_filled=add_filled, fills=len(positions))


def run(cache: dict, config: Config, risk_fraction: float,
        ambiguity: str = "stop") -> dict:
    candidates = build_candidates(cache, "relaxed")
    all_days = sorted({d for sym in cache for d in cache[sym][0]
                       if d.weekday() < 5})
    balance = START_BALANCE
    equity = [(all_days[0], balance)]
    trades = []
    halted = False
    for day in all_days:
        if halted:
            break
        day_start = balance
        day_pnl = 0.0
        count = 0
        busy_until: Optional[object] = None
        for candidate in candidates.get(day, []):
            if count >= MAX_BASKETS_PER_DAY:
                break
            if busy_until is not None and candidate.signal_ts < busy_until:
                continue
            if day_pnl <= -day_start * DAILY_STOP_PERCENT / 100.0:
                break
            result = simulate(candidate, cache[candidate.symbol][0][day],
                              config, balance, risk_fraction, ambiguity)
            if result is None:
                busy_until = candidate.end_ts
                continue
            balance += result["pnl"]
            day_pnl += result["pnl"]
            result.update(day=day, symbol=candidate.symbol,
                          r=result["pnl"] / max(balance - result["pnl"], 1e-9))
            trades.append(result)
            count += 1
            busy_until = result["exit_ts"]
            if balance <= START_BALANCE * (1 - MAX_DD_PERCENT / 100):
                halted = True
                break
        equity.append((day, balance))
    peak = START_BALANCE
    max_dd = 0.0
    for _, value in equity:
        peak = max(peak, value)
        max_dd = max(max_dd, (peak - value) / peak * 100.0)
    n = len(trades)
    wins = sum(t["pnl"] > 0 for t in trades)
    gross_wins = sum(t["pnl"] for t in trades if t["pnl"] > 0)
    gross_losses = abs(sum(t["pnl"] for t in trades if t["pnl"] <= 0))
    span_years = ((equity[-1][0] - equity[0][0]).days / 365.25
                  if len(equity) > 1 else 0.0)
    final = balance
    cagr = ((final / START_BALANCE) ** (1 / span_years) - 1) * 100 \
        if span_years > 0.5 and final > 0 else 0.0
    return {
        "config": config,
        "risk": risk_fraction,
        "n": n,
        "wr": wins / n if n else 0.0,
        "pf": gross_wins / gross_losses if gross_losses else float("inf"),
        "final": final,
        "roi": (final / START_BALANCE - 1) * 100,
        "cagr": cagr,
        "dd": max_dd,
        "halted": halted,
        "add_rate": sum(t["add_filled"] for t in trades) / n if n else 0.0,
        "equity": equity,
        "trades": trades,
    }


def fmt(r: dict, prefix: str = "") -> str:
    c = r["config"]
    pf = f"{r['pf']:.2f}" if math.isfinite(r["pf"]) else "inf"
    return (f"{prefix}{c.name:<20} risk={r['risk']*100:>4.1f}% "
            f"n={r['n']:>3} WR={r['wr']*100:>5.1f}% PF={pf:>5} "
            f"ROI={r['roi']:>7.1f}% CAGR={r['cagr']:>5.1f}% "
            f"DD={r['dd']:>5.1f}% add={r['add_rate']*100:>5.1f}% "
            f"final=${r['final']:>8.2f} {'HALT' if r['halted'] else ''}")


def write_report(gate: list[dict], selected: dict | None,
                 confirm: list[dict] | None, path: Path) -> None:
    lines = [
        "# Winner-Pyramiding Lab — Research Only", "",
        "One TRIAD add is allowed only after a profitable move; the base stop is",
        "moved to breakeven before the add. No losing-position averaging is used.",
        "Risk is the basket's initial full-stop budget. All runs use raw costs,",
        "a 0.10R adverse stop reserve, one account-wide slot, and a 15% DD halt.",
        "", "## Gate results", "",
        "| Config | Risk | Trades | ROI | CAGR | DD | PF | Add rate | Final |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for r in sorted(gate, key=lambda x: -x["roi"]):
        pf = f"{r['pf']:.2f}" if math.isfinite(r["pf"]) else "inf"
        lines.append(f"| {r['config'].name} | {r['risk']*100:.1f}% | {r['n']} | "
                     f"{r['roi']:.1f}% | {r['cagr']:.1f}% | {r['dd']:.1f}% | "
                     f"{pf} | {r['add_rate']*100:.1f}% | ${r['final']:.2f} |")
    lines += ["", "## Selected configuration", ""]
    lines.append(fmt(selected) if selected else "No configuration survived the gate.")
    if confirm:
        lines += ["", "## Four-year confirmation", ""]
        lines.extend(fmt(r) for r in confirm)
    lines += ["", "## Decision", "",
              "The gate selection is not accepted unless the unchanged configuration",
              "remains positive under the confirmation run and its drawdown remains",
              "inside the personal-account ceiling. This is still research evidence,",
              "not a live-trading authorization.", ""]
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--confirm", action="store_true")
    parser.add_argument("--no-doc", action="store_true")
    args = parser.parse_args()
    print("=" * 118)
    print("WINNER PYRAMID LAB — add only after profit, base stop to breakeven")
    print("=" * 118)
    cache2 = v2.load_cache(DATA_2Y)
    results = []
    for config in CONFIGS:
        for risk in (0.005, 0.010, 0.015):
            results.append(run(cache2, config, risk, ambiguity="stop"))
    viable = [r for r in results if r["n"] >= 15 and not r["halted"]
              and r["dd"] <= MAX_DD_PERCENT]
    print(f"2-year gate: {len(results)} runs; {len(viable)} survived the DD ceiling")
    for r in sorted(viable, key=lambda x: -x["roi"])[:20]:
        print(fmt(r, "  "))
    selected = max(viable, key=lambda r: (r["roi"], r["pf"])) if viable else None
    if selected:
        print("\nSelected on gate:")
        print("  " + fmt(selected))
    confirmation = None
    if args.confirm and selected:
        cache4 = v2.load_cache(DATA_4Y)
        confirmation = []
        for ambiguity in ("target", "coin", "stop"):
            confirmation.append(run(cache4, selected["config"],
                                    selected["risk"], ambiguity))
        print("\n4-year confirmation (same selection):")
        for r in confirmation:
            print("  " + fmt(r))
    if not args.no_doc:
        write_report(results, selected, confirmation,
                     Path("findings_winner_pyramid_lab.md"))
        print("\nWrote findings_winner_pyramid_lab.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
