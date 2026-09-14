"""Research-only bounded grid experiment for the personal-account track.

This module deliberately does *not* modify either MQL5 EA.  It tests a
selective, finite grid layered only on top of the repository's TRIAD
sweep/reclaim signals.  It is not a martingale:

* a grid has a fixed number of equal-size entries;
* all layers share one hard stop and one basket risk budget;
* size is never increased after a loss;
* the basket is abandoned at the session/time boundary; and
* the account has a closed-equity drawdown halt.

The experiment is intended to answer whether a bounded basket improves the
existing edge, not to justify hiding a grid from a broker or prop firm.

Usage:
    python tools/bounded_grid_lab.py
    python tools/bounded_grid_lab.py --confirm

The 2-year run is the selection gate.  The selected configuration is then
replayed unchanged on the 4-year data.  All ranking uses stop-first ambiguity
and raw-account spread/commission costs.
"""
from __future__ import annotations

import argparse
import hashlib
import math
import os
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

sys.path.insert(0, os.path.abspath("."))
import tools.aggressive_optimizer as m  # noqa: E402
import tools.optimizer_v2 as v2  # noqa: E402
import tools.triad_honest as th  # noqa: E402

DATA_2Y = v2.DATA_2Y
DATA_4Y = v2.DATA_4Y
LONDON = ZoneInfo("Europe/London")
START_BALANCE = m.ACCOUNT_BALANCE
VOLUME_STEP = m.VOLUME_STEP
VOLUME_MIN = m.VOLUME_MIN

# The five pair-fitted TRIAD symbols are used as the cleanest known signal
# source.  Gold is deliberately not made into a mean-reversion grid here:
# its validated edge is a separate Donchian swing leg.
PAIRFIT = {
    "AUDUSD": {"T": 2.5},
    "EURJPY": {"buf": 0.05, "end": (13, 30), "ts": 120},
    "GBPJPY": {"sweep": 0.01},
    "USDJPY": {"end": (13, 30)},
    "XAUUSD": {"buf": 0.05, "end": (13, 30), "no_late": True},
}

# Geometry is selected as a family, not digit-by-digit.  The relaxed family
# is the geometry used by the current research champion; canonical is the
# frozen V2.1 geometry.  The intermediate family is intentionally broad.
QUALITY = {
    "relaxed": {"sweep": 0.02, "wick": 0.45, "body": 0.50},
    "strict": {"sweep": 0.04, "wick": 0.55, "body": 0.60},
    "canonical": {"sweep": 0.05, "wick": 0.60, "body": 0.60},
}

# Grid variants: (number of equal-size layers, deepest layer as a fraction of
# the original entry-to-stop distance).  depth=0 is the single-entry control.
GRID_VARIANTS = {
    "single": (1, 0.00),
    "g2_50": (2, 0.50),
    "g3_50": (3, 0.50),
    "g3_75": (3, 0.75),
    "g4_75": (4, 0.75),
}

# Personal-account research ceiling supplied by the user.  This is a research
# governor, not a promise that a real gap can never exceed it.
MAX_DD_PERCENT = 15.0
DAILY_STOP_PERCENT = 4.0
MAX_BASKETS_PER_DAY = 2
STOP_SLIPPAGE_R = 0.10  # adverse exit reserve, measured in initial-R units


@dataclass(frozen=True)
class Candidate:
    day: date
    symbol: str
    side: str
    signal_ts: datetime
    end_ts: datetime
    time_stop_min: int
    entry: float
    stop: float
    target_r: float
    ref_high: float
    ref_low: float
    atr: float
    pip_value: float
    body_ratio: float
    wick_ratio: float
    sweep_atr: float


@dataclass
class Basket:
    candidate: Candidate
    levels: list[float]
    lots: float
    target: float
    fill_count: int
    fill_indices: list[int]
    entry_ts: datetime | None
    exit_ts: datetime
    exit_reason: str
    pnl: float
    risk_budget: float
    worst_case_risk: float


def _coin(key: str) -> bool:
    return int(hashlib.md5(key.encode()).hexdigest(), 16) % 2 == 0


def _set_quality(name: str) -> None:
    q = QUALITY[name]
    th.tsb.SWEEP_ATR_MIN = q["sweep"]
    th.tsb.RECLAIM_WICK_MIN = q["wick"]
    th.tsb.DISPLACEMENT_BODY_MIN = q["body"]


def _window_for(symbol: str, day: date):
    cfg = PAIRFIT[symbol]
    ref_s = m.lw_utc(day, 0)
    ref_e = m.lw_utc(day, 7)
    ent_s = ref_e
    end = cfg.get("end", (11, 0))
    ent_e = m.lw_utc(day, *end)
    return ref_s, ref_e, ent_s, ent_e


def build_candidates(cache: dict, quality: str) -> dict[date, list[Candidate]]:
    """Build one candidate per pair/day from the selected TRIAD geometry."""
    _set_quality(quality)
    out: dict[date, list[Candidate]] = defaultdict(list)
    all_days = sorted({d for sym in cache for d in cache[sym][0]
                       if d.weekday() < 5})
    for day in all_days:
        for symbol, cfg in PAIRFIT.items():
            if symbol not in cache or day not in cache[symbol][0]:
                continue
            bars = cache[symbol][0][day]
            atr = cache[symbol][1].get(day, 0.0)
            if atr <= 0:
                continue
            ref_s, ref_e, ent_s, ent_e = _window_for(symbol, day)
            pre = [b for b in bars if ref_s <= b.ts < ref_e]
            if len(pre) < 12:
                continue
            ref_high = max(b.high for b in pre)
            ref_low = min(b.low for b in pre)
            sig = th.detect(
                bars, ref_s, ref_e, ent_s, ent_e, atr, symbol,
                stop_buffer=cfg.get("buf"),
                sweep_min=cfg.get("sweep"),
            )
            if sig is None:
                continue
            if cfg.get("no_late") and sig["sig_ts"].astimezone(LONDON).hour >= 10:
                continue
            out[day].append(Candidate(
                day=day,
                symbol=symbol,
                side=sig["side"],
                signal_ts=sig["sig_ts"],
                end_ts=ent_e,
                time_stop_min=cfg.get("ts", 90),
                entry=sig["entry"],
                stop=sig["stop"],
                target_r=cfg.get("T", 1.5),
                ref_high=ref_high,
                ref_low=ref_low,
                atr=atr,
                pip_value=m.day_pv(symbol, day, cache),
                body_ratio=sig.get("body_ratio", 0.0),
                wick_ratio=sig.get("wick_ratio", 0.0),
                sweep_atr=sig.get("sweep_atr", 0.0),
            ))
    for day in out:
        out[day].sort(key=lambda c: (c.signal_ts, c.symbol))
    return dict(out)


def _money_per_price(symbol: str, pip_value: float, price_delta: float) -> float:
    return abs(price_delta) / m.SPECS[symbol]["pip"] * pip_value


def _round_lots(raw: float) -> float:
    return max(0.0, math.floor((raw + 1e-12) / VOLUME_STEP) * VOLUME_STEP)


def _levels(c: Candidate, layers: int, depth: float) -> list[float]:
    span = abs(c.entry - c.stop)
    if layers <= 1:
        fractions = [0.0]
    else:
        fractions = [depth * i / (layers - 1) for i in range(layers)]
    if c.side == "long":
        return [c.entry - span * f for f in fractions]
    return [c.entry + span * f for f in fractions]


def _target(c: Candidate, mode: str) -> float | None:
    span = abs(c.entry - c.stop)
    if mode == "rr":
        return c.entry + span * c.target_r if c.side == "long" else c.entry - span * c.target_r
    # A midpoint target is only valid when it is on the profitable side of the
    # original signal entry.  Otherwise this candidate is not a mean-reversion
    # setup and is rejected rather than silently turning the target into a loss.
    mid = (c.ref_high + c.ref_low) / 2.0
    if c.side == "long" and mid > c.entry:
        return mid
    if c.side == "short" and mid < c.entry:
        return mid
    return None


def _cost_per_lot(c: Candidate) -> float:
    spread = v2.SPREAD_STD[c.symbol] * v2.RAW_SCALE
    spread_cash = spread / m.SPECS[c.symbol]["pip"] * c.pip_value
    return v2.COMM_RT + spread_cash


def _basket_lots(c: Candidate, levels: list[float], balance: float,
                 risk_fraction: float) -> tuple[float, float]:
    """Equal-size layers sized so all layers stopped is within the budget."""
    per_lot = sum(_money_per_price(c.symbol, c.pip_value, c.stop - level)
                  + _cost_per_lot(c) for level in levels)
    budget = balance * risk_fraction
    return _round_lots(budget / per_lot) if per_lot > 0 else 0.0, budget


def _exit_price(c: Candidate, price: float, reason: str) -> float:
    if reason != "stop":
        return price
    slip = STOP_SLIPPAGE_R * abs(c.entry - c.stop)
    if c.side == "long":
        return price - slip
    return price + slip


def simulate_basket(c: Candidate, bars: list, variant: str, target_mode: str,
                    balance: float, risk_fraction: float,
                    ambiguity: str = "stop") -> Basket | None:
    layers, depth = GRID_VARIANTS[variant]
    levels = _levels(c, layers, depth)
    target = _target(c, target_mode)
    if target is None:
        return None
    lots, budget = _basket_lots(c, levels, balance, risk_fraction)
    if lots < VOLUME_MIN:
        return None

    # Work only after the signal; the order expires at the configured session
    # end. A filled basket has its own time stop from the first fill.
    fwd = [b for b in bars if c.signal_ts <= b.ts < c.end_ts]
    if not fwd:
        return None
    filled: list[int] = []
    fill_ts: datetime | None = None
    exit_ts = fwd[-1].ts + timedelta(minutes=5)
    exit_reason = "session_end"
    exit_px = fwd[-1].close

    for bar in fwd:
        # All levels crossed by the OHLC bar are considered touched. This is
        # conservative for exposure (never undercounts a potential fill).
        for i, level in enumerate(levels):
            if i in filled:
                continue
            touched = (bar.low <= level if c.side == "long" else bar.high >= level)
            if touched:
                filled.append(i)
                if fill_ts is None:
                    fill_ts = bar.ts
        if not filled:
            continue

        hit_target = (bar.high >= target if c.side == "long" else bar.low <= target)
        hit_stop = (bar.low <= c.stop if c.side == "long" else bar.high >= c.stop)
        if hit_target and hit_stop:
            if ambiguity == "target":
                exit_reason, exit_px = "target", target
            elif ambiguity == "coin":
                target_first = _coin(f"{c.day}|{c.symbol}|{c.signal_ts}|{variant}")
                exit_reason, exit_px = ("target", target) if target_first else ("stop", c.stop)
            else:
                exit_reason, exit_px = "stop", c.stop
            exit_ts = bar.ts + timedelta(minutes=5)
            break
        if hit_target:
            exit_reason, exit_px = "target", target
            exit_ts = bar.ts + timedelta(minutes=5)
            break
        if hit_stop:
            exit_reason, exit_px = "stop", c.stop
            exit_ts = bar.ts + timedelta(minutes=5)
            break
        if fill_ts is not None and bar.ts >= fill_ts + timedelta(minutes=c.time_stop_min):
            exit_reason, exit_px = "time", bar.close
            exit_ts = bar.ts + timedelta(minutes=5)
            break

    exit_px = _exit_price(c, exit_px, exit_reason)
    cost = _cost_per_lot(c) * lots
    pnl = 0.0
    for i in filled:
        level = levels[i]
        move = (exit_px - level) if c.side == "long" else (level - exit_px)
        pnl += move / m.SPECS[c.symbol]["pip"] * c.pip_value * lots - cost
    stop_risk = 0.0
    for level in levels:
        stop_move = ((level - _exit_price(c, c.stop, "stop"))
                     if c.side == "long" else
                     (_exit_price(c, c.stop, "stop") - level))
        stop_risk += stop_move / m.SPECS[c.symbol]["pip"] * c.pip_value * lots + cost
    return Basket(
        candidate=c,
        levels=levels,
        lots=lots,
        target=target,
        fill_count=len(filled),
        fill_indices=filled,
        entry_ts=fill_ts,
        exit_ts=exit_ts,
        exit_reason=exit_reason,
        pnl=pnl,
        risk_budget=budget,
        worst_case_risk=stop_risk,
    )


def run(cache: dict, quality: str, variant: str, target_mode: str,
        risk_fraction: float, ambiguity: str = "stop") -> dict:
    candidates = build_candidates(cache, quality)
    all_days = sorted({d for sym in cache for d in cache[sym][0]
                       if d.weekday() < 5})
    balance = START_BALANCE
    equity: list[tuple[date, float]] = [(all_days[0], balance)]
    trades: list[Basket] = []
    halted = False
    day_count = 0
    for day in all_days:
        if halted:
            break
        day_count += 1
        day_start = balance
        day_pnl = 0.0
        baskets_today = 0
        slot_busy_until: datetime | None = None
        for c in candidates.get(day, []):
            if baskets_today >= MAX_BASKETS_PER_DAY:
                break
            if slot_busy_until is not None and c.signal_ts < slot_busy_until:
                continue
            # Personal-account governor: do not open a basket when today's
            # realized path is already at the internal daily stop.
            if day_pnl <= -day_start * DAILY_STOP_PERCENT / 100.0:
                break
            bars = cache[c.symbol][0][day]
            basket = simulate_basket(c, bars, variant, target_mode,
                                     balance, risk_fraction, ambiguity)
            if basket is None:
                slot_busy_until = c.end_ts
                continue
            slot_busy_until = basket.exit_ts
            balance += basket.pnl
            day_pnl += basket.pnl
            trades.append(basket)
            baskets_today += 1
            if balance <= START_BALANCE * (1.0 - MAX_DD_PERCENT / 100.0):
                halted = True
                break
        equity.append((day, balance))
    peak = START_BALANCE
    max_dd_pct = 0.0
    for _, value in equity:
        peak = max(peak, value)
        if peak > 0:
            max_dd_pct = max(max_dd_pct, (peak - value) / peak * 100.0)
    n = len(trades)
    wins = sum(t.pnl > 0 for t in trades)
    gross_wins = sum(t.pnl for t in trades if t.pnl > 0)
    gross_losses = abs(sum(t.pnl for t in trades if t.pnl <= 0))
    span_years = ((equity[-1][0] - equity[0][0]).days / 365.25
                  if equity and equity[-1][0] != equity[0][0] else 0.0)
    final = balance
    cagr = ((final / START_BALANCE) ** (1 / span_years) - 1) * 100 \
        if span_years > 0.5 and final > 0 else 0.0
    return {
        "quality": quality,
        "variant": variant,
        "target_mode": target_mode,
        "risk_fraction": risk_fraction,
        "ambiguity": ambiguity,
        "n": n,
        "wins": wins,
        "wr": wins / n if n else 0.0,
        "pf": gross_wins / gross_losses if gross_losses else float("inf"),
        "total": final - START_BALANCE,
        "final": final,
        "roi": (final / START_BALANCE - 1) * 100,
        "cagr": cagr,
        "dd": max_dd_pct,
        "halted": halted,
        "equity": equity,
        "trades": trades,
        "candidate_days": sum(len(v) for v in candidates.values()),
        "full_fills": sum(t.fill_count == len(t.levels) for t in trades),
        "avg_fills": (sum(t.fill_count for t in trades) / n) if n else 0.0,
        "avg_risk": (sum(t.worst_case_risk for t in trades) / n) if n else 0.0,
        "trading_days": day_count,
    }


def _fmt(r: dict, prefix: str = "") -> str:
    pf = f"{r['pf']:.2f}" if math.isfinite(r["pf"]) else "inf"
    return (f"{prefix}{r['quality']:<9} {r['variant']:<6} {r['target_mode']:<4} "
            f"risk={r['risk_fraction']*100:>4.1f}% n={r['n']:>3} "
            f"WR={r['wr']*100:>5.1f}% PF={pf:>5} "
            f"ROI={r['roi']:>7.1f}% CAGR={r['cagr']:>5.1f}% "
            f"DD={r['dd']:>5.1f}% final=${r['final']:>8.2f} "
            f"fills={r['avg_fills']:.2f} {'HALT' if r['halted'] else ''}")


def select_gate(results: list[dict]) -> dict | None:
    viable = [r for r in results if r["n"] >= 15 and not r["halted"]
              and r["dd"] <= MAX_DD_PERCENT]
    if not viable:
        return None
    # ROI is the user's objective, but only among variants surviving the
    # explicit drawdown ceiling and with a non-trivial trade count.
    return max(viable, key=lambda r: (r["roi"], r["pf"], r["n"]))


def write_report(gate_results: list[dict], selected: dict | None,
                 confirm_results: list[dict] | None, output: Path) -> None:
    lines = [
        "# Bounded Grid Lab — Research Only",
        "",
        "This report tests a finite equal-size grid layered on the existing TRIAD",
        "signal. It is not an MQL5 release and does not recommend hiding a grid",
        "from a broker or account provider.",
        "",
        f"Risk ceiling: {MAX_DD_PERCENT:.1f}% closed-equity drawdown; "
        f"daily stop: {DAILY_STOP_PERCENT:.1f}%.",
        "Ranking uses stop-first ambiguity, raw-account spread/commission, and "
        f"an adverse {STOP_SLIPPAGE_R:.2f}R stop reserve.",
        "",
        "## Gate results",
        "",
        "| Quality | Grid | TP | Risk | Trades | ROI | CAGR | DD | PF | Final |",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for r in sorted(gate_results, key=lambda x: -x["roi"]):
        pf = f"{r['pf']:.2f}" if math.isfinite(r["pf"]) else "inf"
        lines.append(f"| {r['quality']} | {r['variant']} | {r['target_mode']} | "
                     f"{r['risk_fraction']*100:.1f}% | {r['n']} | {r['roi']:.1f}% | "
                     f"{r['cagr']:.1f}% | {r['dd']:.1f}% | {pf} | "
                     f"${r['final']:.2f} |")
    lines += ["", "## Selected gate configuration", ""]
    if selected is None:
        lines.append("No configuration survived the gate.")
    else:
        lines.append("```")
        lines.append(_fmt(selected))
        lines.append("```")
    if confirm_results is not None:
        lines += ["", "## 4-year confirmation using the unchanged gate selection", ""]
        for r in confirm_results:
            lines.append("```")
            lines.append(_fmt(r))
            lines.append("```")
    lines += [
        "",
        "## Interpretation",
        "",
        "A higher ROI is not accepted if the gate selection is unstable on the",
        "confirmation window or if the stop-first path reaches the drawdown halt.",
        "The basket risk is capped before any layer is filled; layers do not add",
        "risk after a loss and the stop is never widened.",
        "",
    ]
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--confirm", action="store_true",
                        help="select on 2-year data and confirm on 4-year data")
    parser.add_argument("--no-doc", action="store_true",
                        help="do not write findings_bounded_grid_lab.md")
    args = parser.parse_args(argv)

    print("=" * 118)
    print("BOUNDED GRID LAB — selective TRIAD setups, finite equal-size layers, stop-first stress")
    print("=" * 118)
    cache2 = v2.load_cache(DATA_2Y)
    results: list[dict] = []
    for quality in QUALITY:
        for variant in GRID_VARIANTS:
            for target_mode in ("rr", "mid"):
                for risk in (0.005, 0.010, 0.015):
                    r = run(cache2, quality, variant, target_mode, risk, ambiguity="stop")
                    results.append(r)
    selected = select_gate(results)
    viable = [r for r in results if r["n"] >= 15 and not r["halted"]
              and r["dd"] <= MAX_DD_PERCENT]
    print(f"2-year gate: {len(results)} runs; {len(viable)} survived "
          f"the {MAX_DD_PERCENT:.1f}% DD ceiling")
    print("\nTop gate configurations (stop-first):")
    for r in sorted(viable, key=lambda x: -x["roi"])[:15]:
        print(_fmt(r, "  "))
    if selected is None:
        print("\nNo bounded-grid configuration survived the gate.")
        return 0
    print("\nSelected on gate:")
    print("  " + _fmt(selected))

    confirmations: list[dict] | None = None
    if args.confirm:
        cache4 = v2.load_cache(DATA_4Y)
        confirmations = []
        for ambiguity in ("target", "coin", "stop"):
            confirmations.append(run(
                cache4, selected["quality"], selected["variant"],
                selected["target_mode"], selected["risk_fraction"],
                ambiguity=ambiguity,
            ))
        print("\n4-year confirmation (same gate selection):")
        for r in confirmations:
            print("  " + _fmt(r))
    if not args.no_doc:
        write_report(results, selected, confirmations, Path("findings_bounded_grid_lab.md"))
        print("\nWrote findings_bounded_grid_lab.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
