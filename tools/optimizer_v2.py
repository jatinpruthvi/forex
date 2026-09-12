"""
Optimizer v2 — cost-aware, ambiguity-aware (2026-09-12)
=======================================================
Engineering answer to the session-7 finding that the old champion's expectancy
was dominated by (a) optimistic same-bar target/stop resolution and (b) uncosted
microstructure. This optimizer SELECTS FOR configs that do not depend on either:

  * wider ATR stops (0.25 -> 1.0 xATR) + a minimum-stop-pips floor
    -> far fewer bars that can span both stop and target,
    -> cost share per trade drops (spread pips / stop pips).
  * every trade is charged REAL costs (raw account: 55% standard spread + $7/lot
    round-turn commission) inside the backtest — not as an afterthought.
  * ambiguous exits (fill bar spans stop AND target) are counted per config;
    the ranking uses the deterministic 50/50 coin bound (honest mid).

Run "python tools/optimizer_v2.py"  -> gate on the 2-year FSB dataset
    "python tools/optimizer_v2.py --confirm" -> re-run top configs on 4-year
"""
from __future__ import annotations

import argparse
import hashlib
import os
import sys
from collections import defaultdict
from datetime import timedelta
from pathlib import Path

sys.path.insert(0, os.path.abspath("."))
import tools.aggressive_optimizer as m  # noqa: E402

DATA_2Y = Path("validation/HistoryData/2-years-data")
DATA_4Y = Path("validation/HistoryData")

# Full round-trip spread in PRICE units (standard account, London hours)
SPREAD_STD = {
    "EURUSD": 0.00010, "GBPUSD": 0.00014, "EURGBP": 0.00014,
    "AUDUSD": 0.00012, "NZDUSD": 0.00016, "USDCAD": 0.00018,
    "USDCHF": 0.00014, "USDJPY": 0.014,  "EURJPY": 0.016,
    "GBPJPY": 0.020,   "XAUUSD": 0.28,
}
RAW_SCALE = 0.55          # raw account spreads ~55% of standard
COMM_RT   = 7.0           # $/lot round turn (raw accounts charge commission)

# Grid: wide stops + min-stop floor are the ambiguity/cost killers
TARGET_GRID    = [1.5, 2.0, 2.5]
ORB_GRID       = [6, 8]
ATRSTOP_GRID   = [0.25, 0.50, 0.75, 1.00]
MINSTOP_GRID   = [2, 6, 10]          # pips; signal skipped if stop < this


def _coin(key: str) -> bool:
    return int(hashlib.md5(key.encode()).hexdigest(), 16) % 2 == 0


def sim_v2(sig, day_bars, end_utc, symbol, *, ambiguity="coin", costs=True):
    """Cost-charged fill simulator. Returns dict-trade or None (unfilled)."""
    spec = m.SPECS[symbol]
    pv = sig.get("pv") or spec["pv"]
    d = sig["direction"]
    entry, stop, target, lots = sig["entry"], sig["stop"], sig["target"], sig["lots"]
    bbar_end = sig["bbar"].ts + timedelta(minutes=5)
    fwd = [b for b in day_bars if bbar_end <= b.ts < end_utc]

    fill_i = None
    for i, b in enumerate(fwd):
        if (d == "long" and b.low <= entry) or (d == "short" and b.high >= entry):
            fill_i = i
            break
    if fill_i is None:
        return None

    exit_px, reason = entry, "time"
    exit_ts = fwd[-1].ts + timedelta(minutes=5) if fwd else bbar_end
    ambiguous = False
    for b in fwd[fill_i:]:
        if d == "long":
            hit_t, hit_s = b.high >= target, b.low <= stop
        else:
            hit_t, hit_s = b.low <= target, b.high >= stop
        if hit_t and hit_s:
            ambiguous = True
            sf = _coin(f"{sig['bbar'].ts.isoformat()}|{symbol}|{d}") if ambiguity == "coin" \
                else (ambiguity == "stop")
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
    else:
        if fwd:
            exit_px = fwd[-1].close

    stop_d = abs(entry - stop)
    gpips = ((exit_px - entry) if d == "long" else (entry - exit_px)) / spec["pip"]
    spread_cash = ((SPREAD_STD[symbol] * RAW_SCALE) / spec["pip"]) * pv * lots if costs else 0.0
    comm = COMM_RT * lots if costs else 4.0 * lots
    net = gpips * pv * lots - comm - spread_cash
    risk_c = stop_d / spec["pip"] * pv * lots + comm + spread_cash
    return dict(symbol=symbol, pnl=net, r=net / risk_c if risk_c > 0 else 0.0,
                reason=reason, ambiguous=ambiguous, lots=lots,
                cost=comm + spread_cash, stop_pips=stop_d / spec["pip"],
                exit_ts=exit_ts)


def run_v2(cache, target_r, orb_bars, atr_stop, min_stop_pips, *,
           ambiguity="coin", costs=True, max_per_day=2, universe=None):
    all_dates = sorted({d for sym in cache for d in cache[sym][0] if d.weekday() < 5})
    balance = m.ACCOUNT_BALANCE
    total_floor = balance * m.TOTAL_FLOOR_PCT
    trades, equity = [], [(all_dates[0], balance)]
    halted = qual = 0
    p1, days_to_p1, tdays = False, None, 0

    lp = (universe or {}).get("london", m.LONDON_PAIRS)
    np_ = (universe or {}).get("ny", m.NY_PAIRS)

    for d in all_dates:
        if halted:
            break
        tdays += 1
        day_start = balance
        daily_floor = day_start * (1.0 - m.DAILY_LOSS_LIMIT + m.SAFETY_BUFFER)
        day_pnl = 0.0
        traded = 0
        cands = []
        for prio, syms, s_utc, e_h, e_m in ((0, lp, m.lw_utc, 11, 0),
                                            (1, np_, m.ny_utc, 11, 0)):
            s, e = s_utc(d, 7 if prio == 0 else 8, 0 if prio == 0 else 30), s_utc(d, e_h, e_m)
            if prio == 1:
                s = s_utc(d, 8, 30)
            for sym in syms:
                if sym not in cache or d not in cache[sym][0]:
                    continue
                by_date_sym, atr_map = cache[sym]
                atr = atr_map.get(d, 0.0)
                if atr <= 0:
                    continue
                day_bars = by_date_sym[d]
                eb = [b for b in day_bars if s <= b.ts < e]
                if len(eb) <= orb_bars + 1:
                    continue
                sig = m.sig_orb_atr(eb, atr, sym, orb_bars, atr_stop, target_r,
                                    pv=m.day_pv(sym, d, cache))
                if not sig:
                    continue
                # v2 filter: minimum stop distance in pips
                if abs(sig["entry"] - sig["stop"]) / m.SPECS[sym]["pip"] < min_stop_pips:
                    continue
                cands.append((sig["bbar"].ts + timedelta(minutes=5), prio, sig, sym, day_bars, e))
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
            t = sim_v2(sig, day_bars, end_utc, sym, ambiguity=ambiguity, costs=costs)
            if t is None:
                slot_busy_until = end_utc
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
    return {
        "params": (target_r, orb_bars, atr_stop, min_stop_pips),
        "n": n, "wr": wins / n if n else 0.0,
        "pf": gw / gl if gl > 0 else float("inf"),
        "total": tc, "monthly": tc * 21.0 / max(tdays, 1),
        "dd": mdd / peak * 100 if peak > 0 else 0.0,
        "amb_rate": (sum(1 for t in trades if t["ambiguous"]) / n) if n else 0.0,
        "avg_cost": (sum(t["cost"] for t in trades) / n) if n else 0.0,
        "avg_r": (sum(t["r"] for t in trades) / n) if n else 0.0,
        "p1": p1, "p1_days": days_to_p1, "halted": halted,
        "qual": qual, "per_pair": dict(pp), "trades": trades,
    }


def load_cache(data_dir: Path):
    m.DATA_DIR = data_dir
    cache = {}
    for sym in m.SPECS:
        bars = m.load_pair(sym)
        if bars:
            cache[sym] = m.preprocess(bars)
    return cache


def data_consistency_check(pairs=("eurusd", "gbpjpy", "xauusd"), sample=400):
    """Compare overlapping rows between the 2-year FSB files and 4-year files."""
    print("\n=== Data accuracy check: 2-year FSB vs 4-year files (overlap 2024-2026) ===")
    m.DATA_DIR = DATA_2Y
    for p in pairs:
        b2 = {(b.ts): b for b in m.load_pair(p.upper())}
        m.DATA_DIR = DATA_4Y
        b4 = {(b.ts): b for b in m.load_pair(p.upper())}
        common = sorted(set(b2) & set(b4))
        if not common:
            print(f"  {p.upper():<8} no overlapping timestamps!")
            continue
        step = max(1, len(common) // sample)
        diffs = []
        for ts in common[::step]:
            a, c = b2[ts], b4[ts]
            diffs.append(max(abs(a.open - c.open), abs(a.high - c.high),
                             abs(a.low - c.low), abs(a.close - c.close)))
        exact = sum(1 for x in diffs if x == 0)
        print(f"  {p.upper():<8} overlap={len(common):>7} bars | sampled={len(diffs):>4} | "
              f"exact={exact*100//len(diffs):>3}% | max|diff|={max(diffs):.5f} | "
              f"mean|diff|={sum(diffs)/len(diffs):.6f}")


def grid(cache, universe=None):
    results = []
    combos = [(tr, ob, at, ms) for tr in TARGET_GRID for ob in ORB_GRID
              for at in ATRSTOP_GRID for ms in MINSTOP_GRID]
    print(f"\nRunning {len(combos)} cost-aware combos (coin bound, costs ON)...")
    for i, (tr, ob, at, ms) in enumerate(combos, 1):
        r = run_v2(cache, tr, ob, at, ms, costs=True, universe=universe)
        results.append(r)
        if i % 12 == 0:
            print(f"  {i}/{len(combos)}...", flush=True)
    return results


def show(r, label=""):
    tr, ob, at, ms = r["params"]
    p1 = f"{r['p1_days']}d" if r["p1"] else ("HALT" if r["halted"] else "NO")
    print(f"  {label}T={tr} RB={ob:<2} ATs={at:<4} minSt={ms:<2} | {r['n']:>4} "
          f"WR={r['wr']*100:>4.1f}% PF={r['pf']:>4.2f} AvgR={r['avg_r']:>5.2f} "
          f"amb={r['amb_rate']*100:>4.1f}% cost=${r['avg_cost']:>4.2f}/tr "
          f"DD={r['dd']:>4.1f}% | ${r['total']:>8.2f} mth=${r['monthly']:>6.2f} P1={p1:>6}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--confirm", action="store_true",
                    help="re-run the 2-year champions on the 4-year dataset")
    args = ap.parse_args()

    print("=" * 100)
    print("OPTIMIZER V2 — cost-aware (raw acct), ambiguity-aware (coin bound), min-stop filter")
    print("=" * 100)

    cache2 = load_cache(DATA_2Y)
    n_days = len(cache2.get("EURUSD", ({}, {}))[0])
    dts = sorted(cache2.get("EURUSD", ({}, {}))[0])
    print(f"2-year FSB dataset: {len(cache2)} pairs, {dts[0]} -> {dts[-1]} ({n_days} days/pair)")
    data_consistency_check()

    res = grid(cache2)
    viable = [r for r in res if not r["halted"] and r["n"] >= 100 and r["total"] > 0]
    viable.sort(key=lambda r: -r["total"])
    print("\n=== TOP 10 on 2-year data (ranked by coin-bound, COSTS ON) ===")
    print("  (viable = not halted, >=100 trades, positive after costs)")
    for r in viable[:10]:
        show(r)
    neg = [r for r in res if r["total"] <= 0]
    print(f"\n  {len(neg)}/{len(res)} combos NEGATIVE after costs; "
          f"{sum(1 for r in res if r['halted'])} hit the floor halt")

    if not viable:
        print("\nVERDICT: NOT PROMISING on 2-year data — nothing positive survives "
              "costs on the honest coin bound. Do not proceed to 4-year.")
        return

    # best config: optimistic bound for context + per-pair
    best = viable[0]
    tr, ob, at, ms = best["params"]
    opt = run_v2(cache2, tr, ob, at, ms, ambiguity="target", costs=True)
    pess = run_v2(cache2, tr, ob, at, ms, ambiguity="stop", costs=True)
    print(f"\n=== Champion {best['params']} — ambiguity bounds (costs on) ===")
    show(opt, "optimistic ")
    show(best, "coin 50/50 ")
    show(pess, "pessimistic")
    print("  per-pair (coin): "
          + ", ".join(f"{s}:{v[0]}/${v[1]:.0f}" for s, v in
                      sorted(best["per_pair"].items(), key=lambda x: -x[1][1])))
    core = {s: v for s, v in best["per_pair"].items()
            if s in ("GBPJPY", "EURJPY", "XAUUSD")}
    print(f"  3-core share of coin P&L: "
          f"{sum(v[1] for v in core.values()) / best['total'] * 100:.0f}%")

    # 3-core universe variant of the champion
    uni3 = {"london": ["GBPJPY", "EURJPY"], "ny": ["XAUUSD"]}
    b3 = run_v2(cache2, tr, ob, at, ms, costs=True, universe=uni3)
    print("\n=== Same champion restricted to GBPJPY+EURJPY+XAUUSD ===")
    show(b3)

    if args.confirm:
        print("\n" + "=" * 100)
        print("CONFIRMATION on 4-year dataset (same champion params)")
        print("=" * 100)
        cache4 = load_cache(DATA_4Y)
        r4c = run_v2(cache4, tr, ob, at, ms, costs=True)
        r4o = run_v2(cache4, tr, ob, at, ms, ambiguity="target", costs=True)
        r4p = run_v2(cache4, tr, ob, at, ms, ambiguity="stop", costs=True)
        r43 = run_v2(cache4, tr, ob, at, ms, costs=True, universe=uni3)
        show(r4o, "4y optimistic ")
        show(r4c, "4y coin 50/50 ")
        show(r4p, "4y pessimistic")
        show(r43, "4y 3-core coin")


if __name__ == "__main__":
    main()
