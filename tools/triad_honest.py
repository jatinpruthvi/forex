"""
TRIAD sweep/reclaim — honest backtester (2026-09-12)
====================================================
Canonical frozen V2.1 geometry (ported from tools/tick_signal_builder.py):
Asian range 00:00-07:00 London -> sweep (0.05-0.50 ATR-M15) -> reclaim within
3 bars (wick >= 0.60, close back inside) -> displacement (body >= 0.60, close
beyond reclaim midpoint) -> LIMIT at 50% retrace of displacement body ->
stop = sweep extreme +/- 0.10 ATR (0.60-1.50 ATR band) -> target R, time stop,
session-end flat. One signal per pair per session.

Honesty layer (identical to the session-7/8 audit standard):
  * limit fills REQUIRE a re-touch of the entry level after the signal bar
  * ambiguous bars (span stop AND target) -> opt / 50-50 coin / pess bounds
  * raw-account costs charged inside every trade (55% std spread + $7/lot RT)
  * per-day pip values from real rates; lots sized from $10 fixed risk
  * ONE account-wide order/position slot (chronological, cancel/replace)
  * The5ers governors: max 2 trades/day, daily 5% floor + buffer, $2,250 floor

Usage:
    python tools/triad_honest.py            # 2-year FSB gate
    python tools/triad_honest.py --confirm  # champions on the 4-year set
"""
from __future__ import annotations

import argparse
import hashlib
import math
import os
import sys
from collections import defaultdict
from datetime import timedelta
from pathlib import Path

sys.path.insert(0, os.path.abspath("."))
import tools.aggressive_optimizer as m  # noqa: E402
import tools.optimizer_v2 as v2  # noqa: E402  (SPREAD_STD, RAW_SCALE, COMM_RT)

sys.path.insert(0, os.path.abspath("tools"))
import tick_signal_builder as tsb  # noqa: E402  (frozen geometry constants)

DATA_2Y = Path("validation/HistoryData/2-years-data")
DATA_4Y = Path("validation/HistoryData")

TARGET_GRID   = [1.5, 2.0, 3.0]
TIMESTOP_GRID = [45, 90]          # minutes from fill
UNIVERSES = {
    "all11": (m.LONDON_PAIRS, []),
    "core3": (["GBPJPY", "EURJPY"], ["XAUUSD"]),
    "gold":  (["XAUUSD"], []),
}


def _coin(key: str) -> bool:
    return int(hashlib.md5(key.encode()).hexdigest(), 16) % 2 == 0


def wick_ratio(bar, side: str) -> float:
    rng = bar.high - bar.low
    if rng <= 0:
        return 0.0
    return ((min(bar.open, bar.close) - bar.low) / rng if side == "long"
            else (bar.high - max(bar.open, bar.close)) / rng)


def body_ratio(bar) -> float:
    rng = bar.high - bar.low
    return abs(bar.close - bar.open) / rng if rng > 0 else 0.0


def asian_range_atr(day_bars, london_s, london_e):
    """Ref range = bars before window start; ATR = mean of last 14 M15 ranges."""
    pre = [b for b in day_bars if b.ts < london_s]
    if len(pre) < 12:                      # need a real Asian session
        return None, None
    ref_h = max(b.high for b in pre)
    ref_l = min(b.low for b in pre)
    buckets: dict = defaultdict(list)
    for b in pre:
        key = b.ts.replace(minute=(b.ts.minute // 15) * 15, second=0, microsecond=0)
        buckets[key].append(b)
    ranges = [max(x.high for x in g) - min(x.low for x in g)
              for _, g in sorted(buckets.items())]
    use = ranges[-14:] if len(ranges) >= 14 else ranges
    atr = sum(use) / len(use) if use else 0.0
    return (ref_h, ref_l), atr


def detect(day_bars, ref_s, ref_e, ent_s, ent_e, atr, sym):
    """Canonical V2.1 detector; returns at most one signal dict.

    ref range = bars in [ref_s, ref_e); entry window = [ent_s, ent_e)."""
    pre = [b for b in day_bars if ref_s <= b.ts < ref_e]
    if len(pre) < 12:
        return None
    ref_h = max(b.high for b in pre)
    ref_l = min(b.low for b in pre)
    win = [b for b in day_bars if ent_s <= b.ts < ent_e]
    spec = m.SPECS[sym]

    sweep_i, side, extreme = -1, None, 0.0
    for i, b in enumerate(win):
        l_depth = (ref_l - b.low) / atr
        s_depth = (b.high - ref_h) / atr
        if l_depth < tsb.SWEEP_ATR_MIN and s_depth < tsb.SWEEP_ATR_MIN:
            continue
        if l_depth >= tsb.SWEEP_ATR_MIN and s_depth >= tsb.SWEEP_ATR_MIN:
            return None                      # two-sided sweep: consume, no trade
        sweep_i, side = i, ("long" if l_depth >= tsb.SWEEP_ATR_MIN else "short")
        extreme = b.low if side == "long" else b.high
        break
    if sweep_i < 0:
        return None

    rec_i = -1
    for i in range(sweep_i, min(len(win) - 1, sweep_i + 2) + 1):
        b = win[i]
        if side == "long":
            extreme = min(extreme, b.low)
            if (ref_l - extreme) / atr > tsb.SWEEP_ATR_MAX:
                return None
            if (b.high - ref_h) / atr >= tsb.SWEEP_ATR_MIN:
                return None
            if ref_l < b.close < ref_h:
                if wick_ratio(b, "long") < tsb.RECLAIM_WICK_MIN:
                    return None
                rec_i = i
                break
        else:
            extreme = max(extreme, b.high)
            if (extreme - ref_h) / atr > tsb.SWEEP_ATR_MAX:
                return None
            if (ref_l - b.low) / atr >= tsb.SWEEP_ATR_MIN:
                return None
            if ref_l < b.close < ref_h:
                if wick_ratio(b, "short") < tsb.RECLAIM_WICK_MIN:
                    return None
                rec_i = i
                break
    if rec_i < 0 or rec_i + 1 >= len(win):
        return None

    rec, disp = win[rec_i], win[rec_i + 1]
    if side == "long":
        if not (disp.close > disp.open
                and body_ratio(disp) >= tsb.DISPLACEMENT_BODY_MIN
                and disp.close > (rec.high + rec.low) / 2.0):
            return None
    else:
        if not (disp.close < disp.open
                and body_ratio(disp) >= tsb.DISPLACEMENT_BODY_MIN
                and disp.close < (rec.high + rec.low) / 2.0):
            return None

    entry = (disp.open + disp.close) / 2.0
    stop = (extreme - tsb.STOP_BUFFER_ATR * atr if side == "long"
            else extreme + tsb.STOP_BUFFER_ATR * atr)
    stop_d = abs(entry - stop)
    if not (tsb.STOP_ATR_MIN <= stop_d / atr <= tsb.STOP_ATR_MAX):
        return None
    if stop_d / spec["pip"] < 2:             # broker min-stop sanity
        return None
    return dict(side=side, entry=entry, stop=stop, sig_ts=disp.ts + timedelta(minutes=5),
                extreme=extreme)


def sim_triad(sig, day_bars, end_utc, symbol, *, target_r, time_stop_min,
              ambiguity="coin", costs=True, risk_frac=0.004):
    """Honest fill/exit sim. Returns trade dict or None (unfilled)."""
    spec = m.SPECS[symbol]
    pv = sig["pv"]
    d = sig["side"]
    entry, stop = sig["entry"], sig["stop"]
    stop_d = abs(entry - stop)
    lpl = stop_d / spec["pip"] * pv + (v2.COMM_RT if costs else 4.0)
    lots = max(0.0, math.floor((m.ACCOUNT_BALANCE * risk_frac / lpl) / m.VOLUME_STEP) * m.VOLUME_STEP)
    if lots < m.VOLUME_MIN:
        return None
    target = entry + stop_d * target_r if d == "long" else entry - stop_d * target_r

    bbar_end = sig["sig_ts"]
    fwd = [b for b in day_bars if bbar_end <= b.ts < end_utc]
    fill_i = None
    for i, b in enumerate(fwd):
        if (d == "long" and b.low <= entry) or (d == "short" and b.high >= entry):
            fill_i = i
            break
    if fill_i is None:
        return None
    fill_ts = fwd[fill_i].ts
    tstop_ts = fill_ts + timedelta(minutes=time_stop_min)

    exit_px, reason = entry, "cancel"
    exit_ts = fwd[-1].ts + timedelta(minutes=5) if fwd else bbar_end
    ambiguous = False
    for b in fwd[fill_i:]:
        if d == "long":
            hit_t, hit_s = b.high >= target, b.low <= stop
        else:
            hit_t, hit_s = b.low <= target, b.high >= stop
        if hit_t and hit_s:
            ambiguous = True
            sf = (_coin(f"{sig['sig_ts'].isoformat()}|{symbol}|{d}")
                  if ambiguity == "coin" else (ambiguity == "stop"))
            exit_px, reason = (stop, "stop") if sf else (target, "target")
            exit_ts = b.ts + timedelta(minutes=5)
            break
        if hit_t:
            exit_px, reason = target, "target"
            exit_ts = b.ts + timedelta(minutes=5)
            break
        if hit_s:
            exit_px, reason = stop, "stop"
            exit_ts = b.ts + timedelta(minutes=5)
            break
        if b.ts >= tstop_ts:                 # time stop -> market at bar close
            exit_px, reason = b.close, "time"
            exit_ts = b.ts + timedelta(minutes=5)
            break
    else:
        if fwd:                               # session-end flat
            exit_px, reason = fwd[-1].close, "session_end"

    gpips = ((exit_px - entry) if d == "long" else (entry - exit_px)) / spec["pip"]
    spread_cash = ((v2.SPREAD_STD[symbol] * v2.RAW_SCALE) / spec["pip"]) * pv * lots if costs else 0.0
    comm = v2.COMM_RT * lots if costs else 4.0 * lots
    net = gpips * pv * lots - comm - spread_cash
    risk_c = stop_d / spec["pip"] * pv * lots + comm + spread_cash
    return dict(symbol=symbol, pnl=net, r=net / risk_c if risk_c > 0 else 0.0,
                reason=reason, ambiguous=ambiguous, cost=comm + spread_cash,
                stop_pips=stop_d / spec["pip"], exit_ts=exit_ts, sig_ts=sig["sig_ts"])


def run_triad(cache, target_r, time_stop_min, universe, *, ambiguity="coin",
              costs=True, max_per_day=2, risk_frac=0.004):
    lp, np_ = universe
    sessions = [(0, sym) for sym in lp] + [(1, sym) for sym in np_]
    all_dates = sorted({d for sym in cache for d in cache[sym][0] if d.weekday() < 5})
    balance = m.ACCOUNT_BALANCE
    total_floor = balance * m.TOTAL_FLOOR_PCT
    trades, equity = [], [(all_dates[0], balance)]
    halted = qual = 0
    p1, days_to_p1, tdays = False, None, 0

    for d in all_dates:
        if halted:
            break
        tdays += 1
        day_start = balance
        daily_floor = day_start * (1.0 - m.DAILY_LOSS_LIMIT + m.SAFETY_BUFFER)
        day_pnl = 0.0
        traded = 0

        cands = []
        # prio 0: London sweep/reclaim vs Asian range (00:00-07:00, trade 07-11)
        # prio 1: New York sweep/reclaim vs London-morning range (07:00-13:30,
        #         trade 13:30-16:00 London wall = 08:30-11:00 NY)
        for prio, sym in sessions:
            if sym not in cache or d not in cache[sym][0]:
                continue
            by_date_sym, atr_map = cache[sym]
            day_bars = by_date_sym[d]
            if prio == 0:
                ref_s, ref_e = m.lw_utc(d, 0), m.lw_utc(d, 7)
                ent_s, ent_e = m.lw_utc(d, 7), m.lw_utc(d, 11)
                end_utc = ent_e
            else:
                ref_s, ref_e = m.lw_utc(d, 7), m.lw_utc(d, 13, 30)
                ent_s, ent_e = m.lw_utc(d, 13, 30), m.lw_utc(d, 16)
                end_utc = ent_e
            atr = atr_map.get(d, 0.0)        # pre-07:00 M15 ATR (day-level)
            if atr <= 0:
                continue
            sig = detect(day_bars, ref_s, ref_e, ent_s, ent_e, atr, sym)
            if sig:
                sig["pv"] = m.day_pv(sym, d, cache)
                cands.append((sig["sig_ts"], prio, sig, sym, day_bars, end_utc))
        cands.sort(key=lambda x: (x[0], x[1], x[3]))

        traded_syms = set()
        slot_busy_until = None
        for sig_ts, _prio, sig, sym, day_bars, end_utc in cands:
            if traded >= max_per_day or balance <= daily_floor or halted:
                break
            if sym in traded_syms:
                continue
            if slot_busy_until is not None and sig_ts < slot_busy_until:
                continue
            t = sim_triad(sig, day_bars, end_utc, sym, target_r=target_r,
                          time_stop_min=time_stop_min, ambiguity=ambiguity,
                          costs=costs, risk_frac=risk_frac)
            if t is None:
                slot_busy_until = end_utc    # limit rested to session end
                continue
            slot_busy_until = t["exit_ts"]
            balance += t["pnl"]
            day_pnl += t["pnl"]
            t["date"] = d
            trades.append(t)
            traded += 1
            traded_syms.add(sym)
            if balance < total_floor:
                halted = True
                break
            if balance < daily_floor:
                break
        equity.append((d, balance))
        if day_pnl >= m.QUALIFYING_DAY_MIN:
            qual += 1
        if not p1 and balance >= m.PHASE1_TARGET and qual >= 3:
            p1 = True
            days_to_p1 = tdays

    n = len(trades)
    wins = sum(1 for t in trades if t["reason"] == "target")
    gw = sum(t["pnl"] for t in trades if t["pnl"] > 0)
    gl = abs(sum(t["pnl"] for t in trades if t["pnl"] <= 0))
    tc = sum(t["pnl"] for t in trades)
    peak = m.ACCOUNT_BALANCE
    mdd = 0.0
    for _, v in equity:
        peak = max(peak, v)
        mdd = max(mdd, peak - v)
    pp = defaultdict(lambda: [0, 0.0])
    for t in trades:
        pp[t["symbol"]][0] += 1
        pp[t["symbol"]][1] += t["pnl"]
    return dict(params=(target_r, time_stop_min), n=n,
                wr=wins / n if n else 0.0,
                pf=gw / gl if gl > 0 else float("inf"),
                total=tc, monthly=tc * 21.0 / max(tdays, 1),
                dd=mdd / peak * 100 if peak > 0 else 0.0,
                amb=(sum(1 for t in trades if t["ambiguous"]) / n) if n else 0.0,
                avg_cost=(sum(t["cost"] for t in trades) / n) if n else 0.0,
                avg_r=(sum(t["r"] for t in trades) / n) if n else 0.0,
                avg_stop=(sum(t["stop_pips"] for t in trades) / n) if n else 0.0,
                p1=p1, p1_days=days_to_p1, halted=halted, qual=qual,
                risk_frac=risk_frac,
                per_pair=dict(pp), trades=trades)


def show(r, label=""):
    tr, ts_min = r["params"]
    p1 = f"{r['p1_days']}d" if r["p1"] else ("HALT" if r["halted"] else "NO")
    print(f"  {label}T={tr} tStop={ts_min:<3} | {r['n']:>4} WR={r['wr']*100:>4.1f}% "
          f"PF={r['pf']:>4.2f} AvgR={r['avg_r']:>5.2f} avgStop={r['avg_stop']:>5.1f}p "
          f"amb={r['amb']*100:>4.1f}% cost=${r['avg_cost']:>4.2f} DD={r['dd']:>4.1f}% | "
          f"${r['total']:>8.2f} mth=${r['monthly']:>7.2f} P1={p1:>6}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--confirm", action="store_true")
    args = ap.parse_args()

    print("=" * 100)
    print("TRIAD SWEEP/RECLAIM — HONEST BACKTEST (re-touch fills, coin bound, raw costs, one slot)")
    print("=" * 100)
    cache = v2.load_cache(DATA_2Y)
    dts = sorted(cache.get("EURUSD", ({}, {}))[0])
    print(f"2-year FSB gate: {len(cache)} pairs, {dts[0]} -> {dts[-1]}")

    res = []
    for uni_name, uni in UNIVERSES.items():
        for tr in TARGET_GRID:
            for ts_min in TIMESTOP_GRID:
                r = run_triad(cache, tr, ts_min, uni, costs=True)
                r["uni"] = uni_name
                res.append(r)
    res.sort(key=lambda r: (r["p1_days"] if r["p1_days"] else 9999, -r["monthly"]))
    print(f"\n=== 2-year gate: {len(res)} runs, ranked by fastest Phase 1 then monthly ===")
    for r in res:
        lbl = f"[{r['uni']:<5}] "
        show(r, lbl)
    nbust = sum(1 for r in res if r["halted"] or r["total"] <= 0)
    print(f"\n  {nbust}/{len(res)} runs negative or halted")

    if res and res[0]["p1"]:
        best = res[0]
        tr, ts_min = best["params"]
        uni = UNIVERSES[best["uni"]]
        print(f"\n=== Champion {best['uni']} T={tr} tStop={ts_min} — ambiguity bounds (costs on) ===")
        for amb, lbl in (("target", "optimistic "), ("coin", "coin 50/50 "), ("stop", "pessimistic")):
            rb = run_triad(cache, tr, ts_min, uni, ambiguity=amb, costs=True)
            show(rb, lbl + " ")
        print("  per-pair (coin): " + ", ".join(
            f"{s}:{v_[0]}/${v_[1]:.0f}" for s, v_ in
            sorted(best["per_pair"].items(), key=lambda x: -x[1][1])))
        # zero-cost edge split
        zc = run_triad(cache, tr, ts_min, uni, costs=False)
        show(zc, "zero-cost coin  ")

        if args.confirm:
            print("\n" + "=" * 100)
            print("CONFIRMATION on 4-year dataset")
            print("=" * 100)
            cache4 = v2.load_cache(DATA_4Y)
            for amb, lbl in (("target", "4y optimistic "), ("coin", "4y coin 50/50 "), ("stop", "4y pessimistic")):
                rb = run_triad(cache4, tr, ts_min, uni, ambiguity=amb, costs=True)
                show(rb, lbl + " ")
            zc4 = run_triad(cache4, tr, ts_min, uni, costs=False)
            show(zc4, "4y zero-cost coin ")
    else:
        print("\nNo configuration passed Phase 1 on the 2-year gate.")


if __name__ == "__main__":
    main()
