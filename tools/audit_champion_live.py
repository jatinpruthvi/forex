"""
Champion-config live-friction audit
===================================
Audits the challenge-winning configuration (orb_atr, T=3.0R, ORB=8 bars,
ATR stop=0.25xATR — and the RB=6 variant) under progressively realistic
execution assumptions that tools/aggressive_optimizer.py does NOT model:

  1. Same-bar target/stop ambiguity  -> resolved PESSIMISTICALLY (stop first).
     The base code awards the WIN when one M5 bar covers both levels.
  2. Spread                          -> round-trip spread charged per trade
     (base code charges none; data is bid/mid so buys at ask lose the spread).
  3. Entry overshoot (market entry)  -> fill at signal-bar CLOSE instead of the
     orb level (live market order after bar close; base fills at the level).
  4. Stop slippage                   -> extra cost on stop exits only.
  5. Commission                      -> $7/lot round turn (base assumes $4).

Usage:
    python tools/audit_champion_live.py
"""
from __future__ import annotations

import os
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.abspath("."))
import tools.aggressive_optimizer as m  # noqa: E402

# --------------------------------------------------------------------------
# Realistic friction inputs (Eightcap-style standard/raw account, London hours)
# price units = same units as the pair's prices; "spread" is FULL round trip.
# --------------------------------------------------------------------------
SPREAD = {   # full spread in price units (typical London-session, standard acct)
    "EURUSD": 0.00010, "GBPUSD": 0.00014, "EURGBP": 0.00014,
    "AUDUSD": 0.00012, "NZDUSD": 0.00016, "USDCAD": 0.00018,
    "USDCHF": 0.00014, "USDJPY": 0.014,  "EURJPY": 0.016,
    "GBPJPY": 0.020,   "XAUUSD": 0.28,
}
STOP_SLIP = {  # extra adverse fill on stop exits (news-free normal conditions)
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


def simulate_x(sig, future_bars, end_utc, symbol, *, stop_first=False,
               entry_mode="level", charge=0.0, spread_scale=1.0, slip=False,
               commission=4.0):
    """Extended simulator: captures timing, supports pessimistic fills.

    Returns None when a market-entry fill is too small to size (skipped live).
    """
    spec = m.SPECS[symbol]
    direction = sig["direction"]
    stop, target0 = sig["stop"], sig["target"]
    bbar = sig["bbar"]
    bbar_end = bbar.ts + timedelta(minutes=5)
    fwd = [b for b in future_bars if bbar_end <= b.ts < end_utc]

    if entry_mode == "close":
        # Live market order: filled at the signal bar's close (overshoot cost).
        # Lots are RE-SIZED from the actual (larger) stop distance, same $10 risk.
        entry = bbar.close
        stop_d = abs(entry - stop)
        lots = m.calc_lots(stop_d, symbol)
        if lots < m.VOLUME_MIN:
            return None
        rr = abs(target0 - sig["entry"]) / max(abs(sig["entry"] - stop), 1e-12)
        target = entry + stop_d * rr if direction == "long" else entry - stop_d * rr
    else:
        entry, lots = sig["entry"], sig["lots"]
        stop_d = abs(entry - stop)
        target = target0

    exit_price, exit_reason = entry, "time"
    exit_ts = fwd[-1].ts + timedelta(minutes=5) if fwd else bbar_end
    for bar in fwd:
        if direction == "long":
            hit_t = bar.high >= target
            hit_s = bar.low <= stop
        else:
            hit_t = bar.low <= target
            hit_s = bar.high >= stop
        if hit_t and hit_s:
            # Ambiguous bar: base code books a WIN; pessimistic books the STOP.
            exit_price, exit_reason = (stop, "stop") if stop_first else (target, "target")
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

    pv = spec["pv"]
    gpips = ((exit_price - entry) if direction == "long" else (entry - exit_price)) / spec["pip"]
    gross = gpips * pv * lots
    spread_cash = charge and (SPREAD[symbol] * spread_scale / spec["pip"]) * pv * lots or 0.0
    net = gross - commission * lots - spread_cash
    risk_c = stop_d / spec["pip"] * pv * lots + commission * lots + spread_cash
    pnl_r = net / risk_c if risk_c > 0 else 0.0
    return XTrade(symbol, bbar_end, exit_ts, net, pnl_r, exit_reason)


def run_variant(cache, target_r, orb_bars, atr_stop, *, stop_first=False,
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
        # -- London --
        ls, le = m.lw_utc(d, 7), m.lw_utc(d, 11)
        for sym in m.LONDON_PAIRS:
            if sym not in cache:
                continue
            by_date_sym, atr_map = cache[sym]
            if d not in by_date_sym:
                continue
            atr = atr_map.get(d, 0.0)
            if atr <= 0:
                continue
            day_bars = by_date_sym[d]
            eb = [b for b in day_bars if ls <= b.ts < le]
            if len(eb) <= orb_bars + 1:
                continue
            sig = m.sig_orb_atr(eb, atr, sym, orb_bars, atr_stop, target_r)
            if sig:
                cands.append((0, sig, sym, day_bars, le))
        # -- New York --
        ns, ne = m.ny_utc(d, 8, 30), m.ny_utc(d, 11, 0)
        for sym in m.NY_PAIRS:
            if sym not in cache:
                continue
            by_date_sym, atr_map = cache[sym]
            if d not in by_date_sym:
                continue
            atr = atr_map.get(d, 0.0)
            if atr <= 0:
                continue
            day_bars = by_date_sym[d]
            eb = [b for b in day_bars if ns <= b.ts < ne]
            if len(eb) <= orb_bars + 1:
                continue
            sig = m.sig_orb_atr(eb, atr, sym, orb_bars, atr_stop, target_r)
            if sig:
                cands.append((1, sig, sym, day_bars, ne))
        cands.sort(key=lambda x: (x[0], x[2]))

        traded_syms = set()
        for prio, sig, sym, day_bars, end_utc in cands:
            if traded >= max_per_day or balance <= daily_floor or halted:
                break
            if sym in traded_syms:
                continue
            t = simulate_x(sig, day_bars, end_utc, sym, stop_first=stop_first,
                           entry_mode=entry_mode, charge=spread,
                           spread_scale=spread_scale, slip=slip,
                           commission=commission)
            if t is None:   # live EA skips un-sizeable market entry
                continue
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
    loss = sum(1 for t in trades if t.exit_reason == "stop")
    wr = wins / n if n else 0.0
    gw = sum(t.pnl_cash for t in trades if t.pnl_cash > 0)
    gl = abs(sum(t.pnl_cash for t in trades if t.pnl_cash <= 0))
    pf = gw / gl if gl > 0 else float("inf")
    tc = sum(t.pnl_cash for t in trades)
    peak = run_pk = m.ACCOUNT_BALANCE
    mdd = 0.0
    for _, v in equity:
        peak = max(peak, v)
        mdd = max(mdd, peak - v)
    mdd_pct = mdd / peak * 100 if peak > 0 else 0.0
    return {
        "n": n, "wr": wr, "avg_r": (sum(t.pnl_r for t in trades) / n if n else 0.0),
        "pf": pf, "total": tc, "monthly": tc * 21.0 / max(tdays, 1),
        "dd": mdd_pct, "p1_days": days_to_p1, "p1": p1,
        "final": balance, "trades": trades,
    }


def fill_rate_analysis(cache, target_r, orb_bars, atr_stop):
    """Of all signals the base backtest 'fills at the orb level', how many
    would a live LIMIT order actually fill (price must re-touch the level)?"""
    touched_pnl = 0.0
    missed_n = 0
    touched_n = 0
    missed_pnl = 0.0
    missed_wins = 0
    for d in sorted({dd for sym in cache for dd in cache[sym][0] if dd.weekday() < 5}):
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
            if len(eb) > orb_bars + 1:
                sig = m.sig_orb_atr(eb, atr, sym, orb_bars, atr_stop, target_r)
                if sig:
                    cands.append((sig, sym, day_bars, le))
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
            if len(eb) > orb_bars + 1:
                sig = m.sig_orb_atr(eb, atr, sym, orb_bars, atr_stop, target_r)
                if sig:
                    cands.append((sig, sym, day_bars, ne))
        cands.sort(key=lambda x: x[1])
        seen = set()
        for sig, sym, day_bars, end_utc in cands:
            if sym in seen:
                continue
            seen.add(sym)
            t = m.simulate(sig, day_bars, end_utc, sym)
            entry, direction = sig["entry"], sig["direction"]
            bbar_end = sig["bbar"].ts + timedelta(minutes=5)
            fwd = [b for b in day_bars if bbar_end <= b.ts < end_utc]
            if direction == "long":
                touches = any(b.low <= entry for b in fwd)
            else:
                touches = any(b.high >= entry for b in fwd)
            if touches:
                touched_n += 1
                touched_pnl += t.pnl_cash
            else:
                missed_n += 1
                missed_pnl += t.pnl_cash
                missed_wins += 1 if t.pnl_cash > 0 else 0
    total = touched_pnl + missed_pnl
    print(f"  Signals: {touched_n + missed_n} | limit would fill: {touched_n} "
          f"| NEVER touched level (no trade live): {missed_n} "
          f"({missed_n/(touched_n+missed_n)*100:.1f}%)")
    print(f"  P&L booked by backtest on never-filled signals: ${missed_pnl:.2f} "
          f"({missed_pnl/total*100:.1f}% of total P&L); "
          f"{missed_wins}/{missed_n} of them were winners")


def overlap_stats(trades):
    """Max simultaneous open positions and #days with overlapping holds."""
    by_day = defaultdict(list)
    for t in trades:
        by_day[t.entry_ts.date()].append(t)
    overlap_days = 0
    max_sim = 0
    for d, ts_ in by_day.items():
        events = []
        for t in ts_:
            events.append((t.entry_ts, 1))
            events.append((t.exit_ts, -1))
        events.sort(key=lambda x: (x[0], x[1]))
        cur = 0
        day_sim = 0
        for _, delta in events:
            cur += delta
            day_sim = max(day_sim, cur)
        if day_sim > 1:
            overlap_days += 1
        max_sim = max(max_sim, day_sim)
    return max_sim, overlap_days


def fmt(name, r):
    p1 = f"{r['p1_days']}d" if r["p1"] else "NO"
    print(f"  {name:<38} {r['n']:>5} {r['wr']*100:>5.1f}% {r['avg_r']:>6.3f} "
          f"{r['pf']:>5.2f} {r['total']:>10.2f} {r['monthly']:>8.2f} "
          f"{r['dd']:>5.2f}%  {p1:>5} ${r['final']:>9.2f}")


def main():
    print("=" * 100)
    print("CHAMPION LIVE-FRICTION AUDIT  (orb_atr London+NY, fixed $10 risk)")
    print("=" * 100)
    cache = {}
    for sym in m.SPECS:
        bars = m.load_pair(sym)
        if bars:
            by_date, atr_map = m.preprocess(bars)
            cache[sym] = (by_date, atr_map)
    print(f"Loaded {len(cache)} pairs, 2022-09-11 -> 2026-09-11\n")

    # --- Self-check: baseline must reproduce committed numbers -------------
    print(f"{'Variant':<38} {'N':>5} {'WR%':>6} {'AvgR':>6} {'PF':>5} "
          f"{'Total$':>10} {'Mth$':>8} {'DD%':>6}  {'P1':>5} {'Final':>10}")
    print("  " + "-" * 96)

    for tr, rb in ((3.0, 8), (3.0, 6)):
        print(f"\n=== Champion T={tr}R RB={rb} bars ATR=0.25 ===")
        base = run_variant(cache, tr, rb, 0.25)
        fmt("A. Backtest as coded (baseline)", base)

        amb = run_variant(cache, tr, rb, 0.25, stop_first=True)
        fmt("B. + same-bar ambiguity -> STOP", amb)

        spr = run_variant(cache, tr, rb, 0.25, spread=True)
        fmt("C. + full standard spread only", spr)

        ent = run_variant(cache, tr, rb, 0.25, entry_mode="close")
        fmt("D. + market entry at bar close", ent)

        com = run_variant(cache, tr, rb, 0.25, commission=7.0)
        fmt("E. + $7/lot commission (RT)", com)

        real = run_variant(cache, tr, rb, 0.25, spread=True, commission=7.0)
        fmt("F. std spreads + $7 comm", real)

        raw = run_variant(cache, tr, rb, 0.25, spread=True, spread_scale=0.55,
                          commission=7.0)
        fmt("F2. RAW acct: 55% spread + $7", raw)

        full = run_variant(cache, tr, rb, 0.25, stop_first=True, spread=True,
                           spread_scale=0.55, commission=7.0)
        fmt("G. PESSIMISTIC: B+F2 (path coin-flip)", full)

        worst = run_variant(cache, tr, rb, 0.25, stop_first=True, spread=True,
                            spread_scale=0.55, slip=True, commission=7.0)
        fmt("H. WORST: G + stop slippage", worst)

        ms, od = overlap_stats(base["trades"])
        n_flip = sum(1 for a, b in zip(base["trades"], amb["trades"])
                     if a.exit_reason == "target" and b.exit_reason == "stop")
        print(f"\n  Same-bar target/stop flips (wins that become losses): "
              f"{n_flip} of {base['n']} trades ({n_flip/base['n']*100:.1f}%)")
        print(f"  Max simultaneous open positions in backtest: {ms}; "
              f"days with overlapping holds: {od}")
        for label, v in (("F  (std spread+$7)", real), ("F2 (raw acct)", raw),
                         ("H  (worst)", worst)):
            d_base = v["total"] - base["total"]
            print(f"  {label} vs baseline: {d_base:+.2f}$ "
                  f"({d_base/abs(base['total'])*100 if base['total'] else 0:+.1f}% of P&L)")

        pp = defaultdict(lambda: [0, 0.0])
        for t in raw["trades"]:
            pp[t.pair][0] += 1
            pp[t.pair][1] += t.pnl_cash
        print("  Per-pair under F2 (raw acct): "
              + ", ".join(f"{s}:{n}/${p:.0f}" for s, (n, p) in
                          sorted(pp.items(), key=lambda x: -x[1][1])))

    # --- Limit-fill rate (adverse selection) --------------------------------
    print("\n=== Limit-fill analysis: does price ever return to the entry level? ===")
    for tr, rb in ((3.0, 8), (3.0, 6)):
        print(f"  --- T={tr}R RB={rb} ---")
        fill_rate_analysis(cache, tr, rb, 0.25)

    # --- Pip-value drift over the window -----------------------------------
    print("\n=== Pip-value constant drift (pv frozen at 2024-26 mids) ===")
    yearly = defaultdict(lambda: defaultdict(list))
    for sym in ("GBPJPY", "EURJPY", "USDJPY"):
        for b in m.load_pair(sym):
            yearly[b.ts.year][sym].append(b.close)
    for sym in ("GBPJPY", "EURJPY", "USDJPY"):
        assumed = m.SPECS[sym]["pv"]
        row = f"  {sym:<8} assumed pv=${assumed:.2f} | "
        for yr in sorted(yearly):
            avg = sum(yearly[yr][sym]) / len(yearly[yr][sym])
            true_pv = 100000 * 0.01 / avg
            row += f"{yr}:{true_pv:.2f} ({(true_pv/assumed-1)*100:+.0f}%)  "
        print(row)


if __name__ == "__main__":
    main()
