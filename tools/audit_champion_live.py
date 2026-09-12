"""
Champion live-friction audit (FIXED fill model)
===============================================
Sits on top of the corrected simulator in tools/aggressive_optimizer.py
(limit re-touch fills, one account-wide order/position slot, per-day pip
values, deterministic-coin ambiguous bars) and stacks REALISTIC costs:

  spread (standard or raw account), $7/lot round-turn commission, market
  entry instead of limit (chase variant), stop slippage.

Ambiguity bounds are reported per variant:
  opt = target-first, coin = deterministic 50/50, pess = stop-first.

Usage:
    python tools/audit_champion_live.py
"""
from __future__ import annotations

import hashlib
import os
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.abspath("."))
import tools.aggressive_optimizer as m  # noqa: E402

# --------------------------------------------------------------------------
# Realistic friction inputs (Eightcap-style, London hours; FULL round trip)
# --------------------------------------------------------------------------
SPREAD = {
    "EURUSD": 0.00010, "GBPUSD": 0.00014, "EURGBP": 0.00014,
    "AUDUSD": 0.00012, "NZDUSD": 0.00016, "USDCAD": 0.00018,
    "USDCHF": 0.00014, "USDJPY": 0.014,  "EURJPY": 0.016,
    "GBPJPY": 0.020,   "XAUUSD": 0.28,
}
STOP_SLIP = {
    "EURUSD": 0.00005, "GBPUSD": 0.00007, "EURGBP": 0.00007,
    "AUDUSD": 0.00006, "NZDUSD": 0.00008, "USDCAD": 0.00009,
    "USDCHF": 0.00007, "USDJPY": 0.007,  "EURJPY": 0.008,
    "GBPJPY": 0.010,   "XAUUSD": 0.14,
}


@dataclass
class XTrade:
    pair: str
    entry_ts: object
    exit_ts: object
    pnl_cash: float
    pnl_r: float
    exit_reason: str


def _coin(key: str) -> bool:
    return int(hashlib.md5(key.encode()).hexdigest(), 16) % 2 == 0


def simulate_x(sig, future_bars, end_utc, symbol, *, ambiguity="coin",
               entry_mode="level", spread=False, spread_scale=1.0, slip=False,
               commission=4.0):
    """Fixed-fill simulator with cost knobs. Returns None when unfilled."""
    spec = m.SPECS[symbol]
    pv = sig.get("pv") or spec["pv"]
    direction = sig["direction"]
    stop, target = sig["stop"], sig["target"]
    bbar = sig["bbar"]
    bbar_end = bbar.ts + timedelta(minutes=5)
    fwd = [b for b in future_bars if bbar_end <= b.ts < end_utc]

    if entry_mode == "close":
        # Market chase: fill at signal-bar close, re-sized lots, same R geometry
        entry = bbar.close
        stop_d = abs(entry - stop)
        lots = m.calc_lots(stop_d, symbol, pv)
        if lots < m.VOLUME_MIN:
            return None
        rr = abs(target - sig["entry"]) / max(abs(sig["entry"] - stop), 1e-12)
        target = entry + stop_d * rr if direction == "long" else entry - stop_d * rr
        fill_i = 0
        fill_ts = bbar_end
    else:
        entry, lots = sig["entry"], sig["lots"]
        fill_i = None
        for i, bar in enumerate(fwd):
            if (direction == "long" and bar.low <= entry) or \
               (direction == "short" and bar.high >= entry):
                fill_i = i
                break
        if fill_i is None:
            return None
        fill_ts = fwd[fill_i].ts
        stop_d = abs(entry - stop)

    exit_price, exit_reason = entry, "time"
    exit_ts = fwd[-1].ts + timedelta(minutes=5) if fwd else bbar_end
    for bar in fwd[fill_i:]:
        if direction == "long":
            hit_t, hit_s = bar.high >= target, bar.low <= stop
        else:
            hit_t, hit_s = bar.low <= target, bar.high >= stop
        if hit_t and hit_s:
            if ambiguity == "coin":
                sf = _coin(f"{bbar.ts.isoformat()}|{symbol}|{direction}")
            else:
                sf = ambiguity == "stop"
            exit_price = stop if sf else target
            exit_reason = "stop" if sf else "target"
            exit_ts = bar.ts + timedelta(minutes=5)
            break
        if hit_t:
            exit_price, exit_reason = target, "target"
            exit_ts = bar.ts + timedelta(minutes=5)
            break
        if hit_s:
            px = stop
            if slip:
                px = px - STOP_SLIP[symbol] if direction == "long" else px + STOP_SLIP[symbol]
            exit_price, exit_reason = px, "stop"
            exit_ts = bar.ts + timedelta(minutes=5)
            break
    else:
        if fwd:
            exit_price = fwd[-1].close

    gpips = ((exit_price - entry) if direction == "long" else (entry - exit_price)) / spec["pip"]
    gross = gpips * pv * lots
    spread_cash = (SPREAD[symbol] * spread_scale / spec["pip"]) * pv * lots if spread else 0.0
    net = gross - commission * lots - spread_cash
    risk_c = stop_d / spec["pip"] * pv * lots + commission * lots + spread_cash
    pnl_r = net / risk_c if risk_c > 0 else 0.0
    return XTrade(symbol, bbar_end, exit_ts, net, pnl_r, exit_reason)


def run_variant(cache, target_r, orb_bars, atr_stop, *, ambiguity="coin",
                entry_mode="level", spread=False, spread_scale=1.0, slip=False,
                commission=4.0, max_per_day=2):
    all_dates = sorted({d for sym in cache for d in cache[sym][0] if d.weekday() < 5})
    balance = m.ACCOUNT_BALANCE
    total_floor = balance * m.TOTAL_FLOOR_PCT
    trades: list[XTrade] = []
    equity = [(all_dates[0], balance)]
    halted = False
    qual = 0
    p1 = False
    days_to_p1 = None
    tdays = 0

    for d in all_dates:
        if halted:
            break
        tdays += 1
        day_start = balance
        daily_floor = day_start * (1.0 - m.DAILY_LOSS_LIMIT + m.SAFETY_BUFFER)
        day_pnl = 0.0
        traded = 0
        cands = []
        ls, le = m.lw_utc(d, 7), m.lw_utc(d, 11)
        for sym in m.LONDON_PAIRS:
            if sym not in cache or d not in cache[sym][0]:
                continue
            by_date_sym, atr_map = cache[sym]
            atr = atr_map.get(d, 0.0)
            if atr <= 0:
                continue
            day_bars = by_date_sym[d]
            eb = [b for b in day_bars if ls <= b.ts < le]
            if len(eb) <= orb_bars + 1:
                continue
            pv = m.day_pv(sym, d, cache)
            sig = m.sig_orb_atr(eb, atr, sym, orb_bars, atr_stop, target_r, pv=pv)
            if sig:
                cands.append((sig["bbar"].ts + timedelta(minutes=5), 0, sig, sym, day_bars, le))
        ns, ne = m.ny_utc(d, 8, 30), m.ny_utc(d, 11, 0)
        for sym in m.NY_PAIRS:
            if sym not in cache or d not in cache[sym][0]:
                continue
            by_date_sym, atr_map = cache[sym]
            atr = atr_map.get(d, 0.0)
            if atr <= 0:
                continue
            day_bars = by_date_sym[d]
            eb = [b for b in day_bars if ns <= b.ts < ne]
            if len(eb) <= orb_bars + 1:
                continue
            pv = m.day_pv(sym, d, cache)
            sig = m.sig_orb_atr(eb, atr, sym, orb_bars, atr_stop, target_r, pv=pv)
            if sig:
                cands.append((sig["bbar"].ts + timedelta(minutes=5), 1, sig, sym, day_bars, ne))
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
            t = simulate_x(sig, day_bars, end_utc, sym, ambiguity=ambiguity,
                           entry_mode=entry_mode, spread=spread,
                           spread_scale=spread_scale, slip=slip,
                           commission=commission)
            if t is None:
                slot_busy_until = end_utc
                continue
            slot_busy_until = t.exit_ts
            balance += t.pnl_cash
            day_pnl += t.pnl_cash
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
    wins = sum(1 for t in trades if t.exit_reason == "target")
    wr = wins / n if n else 0.0
    gw = sum(t.pnl_cash for t in trades if t.pnl_cash > 0)
    gl = abs(sum(t.pnl_cash for t in trades if t.pnl_cash <= 0))
    pf = gw / gl if gl > 0 else float("inf")
    tc = sum(t.pnl_cash for t in trades)
    peak = m.ACCOUNT_BALANCE
    mdd = 0.0
    for _, v in equity:
        peak = max(peak, v)
        mdd = max(mdd, peak - v)
    return {
        "n": n, "wr": wr,
        "avg_r": (sum(t.pnl_r for t in trades) / n if n else 0.0),
        "pf": pf, "total": tc, "monthly": tc * 21.0 / max(tdays, 1),
        "dd": mdd / peak * 100 if peak > 0 else 0.0,
        "p1_days": days_to_p1, "p1": p1, "final": balance,
        "halted": halted, "trades": trades,
    }


def fmt(name, r):
    p1 = f"{r['p1_days']}d" if r["p1"] else ("HALT" if r.get("halted") else "NO")
    print(f"  {name:<40} {r['n']:>5} {r['wr']*100:>5.1f}% {r['avg_r']:>6.3f} "
          f"{r['pf']:>5.2f} {r['total']:>9.2f} {r['monthly']:>8.2f} "
          f"{r['dd']:>5.2f}%  {p1:>6}")


def show_block(cache, tr, rb):
    print(f"\n=== orb_atr T={tr}R RB={rb} ATR=0.25 (fixed fill model) ===")
    hdr = (f"  {'Variant':<40} {'N':>5} {'WR%':>6} {'AvgR':>6} {'PF':>5} "
           f"{'Total$':>9} {'Mth$':>8} {'DD%':>6}  {'P1':>6}")
    print(hdr)
    print("  " + "-" * 92)
    for amb, amb_tag in ((False, "opt"), (None, "coin"), (True, "pess")):
        base = m.run_backtest(cache, "orb_atr", tr, rb, 0.25,
                              stop_first=amb)
        # m.run_backtest has no cost knobs -> only for zero-cost bounds
        lbl = {"opt": "zero-cost, optimistic", "coin": "zero-cost, coin 50/50",
               "pess": "zero-cost, pessimistic"}[amb_tag]
        p1 = f"{base['days_to_p1']}d" if base["phase1_done"] else ("HALT" if base["halted"] else "NO")
        print(f"  {lbl:<40} {base['signals']:>5} {base['win_rate']*100:>5.1f}% "
              f"{base['avg_r']:>6.3f} {base['profit_factor']:>5.2f} "
              f"{base['total_cash']:>9.2f} {base['monthly_pnl']:>8.2f} "
              f"{base['max_dd_pct']:>5.2f}%  {p1:>6}")
        # cost-stacked variants (only for coin + optimistic; pessimistic busts)
        if amb_tag != "pess":
            amb_x = {False: "target", None: "coin", True: "stop"}[amb]
            raw = run_variant(cache, tr, rb, 0.25, ambiguity=amb_x,
                              spread=True, spread_scale=0.55, commission=7.0)
            fmt(f"raw acct ({amb_tag}) + spread+$7", raw)
            worst = run_variant(cache, tr, rb, 0.25, ambiguity=amb_x,
                                spread=True, spread_scale=0.55, slip=True, commission=7.0)
            fmt(f"raw acct ({amb_tag}) + slip", worst)
        else:
            pess = run_variant(cache, tr, rb, 0.25, ambiguity="stop",
                               spread=True, spread_scale=0.55, commission=7.0)
            fmt("raw acct (pess) + spread+$7", pess)


def main():
    print("=" * 96)
    print("CHAMPION LIVE-FRICTION AUDIT — FIXED FILL MODEL (re-touch, one slot, day pip values)")
    print("=" * 96)
    cache = {}
    for sym in m.SPECS:
        bars = m.load_pair(sym)
        if bars:
            by_date, atr_map = m.preprocess(bars)
            cache[sym] = (by_date, atr_map)
    print(f"Loaded {len(cache)} pairs, 2022-09-11 -> 2026-09-11")

    show_block(cache, 3.0, 8)   # previous champion
    show_block(cache, 2.5, 6)   # new #1 on fixed leaderboard

    # 3-core universe
    print("\n" + "=" * 96)
    print("3-CORE UNIVERSE: GBPJPY + EURJPY + XAUUSD only")
    print("=" * 96)
    LP, NP = m.LONDON_PAIRS, m.NY_PAIRS
    m.LONDON_PAIRS, m.NY_PAIRS = ["GBPJPY", "EURJPY"], ["XAUUSD"]
    show_block(cache, 3.0, 8)
    show_block(cache, 2.5, 6)
    m.LONDON_PAIRS, m.NY_PAIRS = LP, NP


if __name__ == "__main__":
    main()
