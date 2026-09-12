"""
Fast-Track Strategy Lab (2026-09-12)
====================================
Goal: Phase 1 (+10%) in <= 3 months (~63 trading days) inside The5ers floor
math (risk <= 1.5-2%/trade, DD <= 8%). New families ONLY — the long-term TRIAD
track is preserved (see STRATEGY-ROADMAP.md Track A).

Families
--------
F1  Quiet-session range fade  — fade 2-SD band touches back to the mean in the
    00:00-06:30 London window on low-vol FX (founder Sleeve-C idea).
    Market fill at touch-bar close; stop = extreme +/- 0.5 ATR(prev day);
    target = band mean; hard flat 06:30.
F2  Failed-breakout reversal  — London ORB level breaks, then a close back
    inside within W bars => trade against the failure. Market fill at the
    re-entry close; stop beyond break extreme + 0.10 ATR; target 1.0/1.5R.
F3  Breakout rider (diagnostic) — ORB entry (re-touch limit) + stop, NO target;
    session-end exit only. Measures pure ride value of the validated ORB entry.

Honesty layer (identical to sessions 7-9): ambiguity bounds opt/coin/pess,
raw-account costs inside every trade (55% std spread + $7/lot RT), per-day pip
values, ONE account-wide order/position slot, max 2 trades/day, daily 5% +
overall $2,250 governors. ATR for F1 uses the PREVIOUS day's value (no
same-day lookahead; the v1 ATR map includes same-day pre-07:00 bars).

Usage: python tools/fast_track_lab.py
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
import tools.aggressive_optimizer as m      # noqa: E402
import tools.optimizer_v2 as v2             # noqa: E402 (data loader + costs)

DATA_2Y = Path("validation/HistoryData/2-years-data")
DATA_4Y = Path("validation/HistoryData")

QUIET5 = ["EURGBP", "AUDUSD", "NZDUSD", "USDCHF", "EURUSD"]
CORE3  = ["GBPJPY", "EURJPY", "XAUUSD"]
LON11  = m.LONDON_PAIRS


def _coin(key: str) -> bool:
    return int(hashlib.md5(key.encode()).hexdigest(), 16) % 2 == 0


# ---------------------------------------------------------------------------
# detectors — each returns list of candidate signals for one pair-day
# ---------------------------------------------------------------------------

def det_f1(day_bars, atr, sym, sd_k=2.0, lookback=24):
    """Quiet-session fade in 00:00-06:30 London. Market fill at touch close."""
    win = [b for b in day_bars
           if m.lw_utc(b.ts.date(), 0) <= b.ts < m.lw_utc(b.ts.date(), 6, 30)]
    if atr <= 0 or len(win) < lookback + 2:
        return []
    out = []
    for i in range(lookback, len(win)):
        seg = win[i - lookback:i + 1]
        closes = [b.close for b in seg]
        mean = sum(closes) / len(closes)
        var = sum((c - mean) ** 2 for c in closes) / len(closes)
        sd = math.sqrt(var)
        if sd <= 0:
            continue
        b = seg[-1]
        if b.low <= mean - sd_k * sd:                     # lower-band touch -> long
            entry = b.close
            stop = b.low - 0.5 * atr
            if entry <= stop:
                continue
            out.append(dict(side="long", entry=entry, stop=stop, target=mean,
                            sig_ts=b.ts + timedelta(minutes=5),
                            entry_style="market"))
            break                                          # one per pair-day
        if b.high >= mean + sd_k * sd:                     # upper-band touch -> short
            entry = b.close
            stop = b.high + 0.5 * atr
            if entry >= stop:
                continue
            out.append(dict(side="short", entry=entry, stop=stop, target=mean,
                            sig_ts=b.ts + timedelta(minutes=5),
                            entry_style="market"))
            break
    return out


def det_f2(day_bars, atr, sym, orb_bars=8, wait=3, target_r=1.0):
    """Failed London-ORB breakout reversal. Market fill at re-entry close."""
    win = [b for b in day_bars if m.lw_utc(b.ts.date(), 7) <= b.ts < m.lw_utc(b.ts.date(), 11)]
    if atr <= 0 or len(win) <= orb_bars + 1:
        return []
    ob = win[:orb_bars]
    orb_h = max(b.high for b in ob)
    orb_l = min(b.low for b in ob)
    if (orb_h - orb_l) / m.SPECS[sym]["pip"] < 2:
        return []
    break_dir, break_i, extreme = None, -1, 0.0
    for i, b in enumerate(win[orb_bars:], start=orb_bars):
        if b.close > orb_h:
            break_dir, break_i, extreme = "up", i, b.high
            break
        if b.close < orb_l:
            break_dir, break_i, extreme = "down", i, b.low
            break
    if break_dir is None:
        return []
    for j in range(break_i + 1, min(len(win), break_i + 1 + wait)):
        b = win[j]
        if break_dir == "up":
            extreme = max(extreme, b.high)
            if b.close < orb_h:                            # failed -> short
                stop = extreme + 0.10 * atr
                entry = b.close
                stop_d = stop - entry                      # short: stop above entry
                if stop_d <= 0 or stop_d / m.SPECS[sym]["pip"] < 2:
                    return []
                return [dict(side="short", entry=entry, stop=stop,
                             target=entry - stop_d * target_r,
                             sig_ts=b.ts + timedelta(minutes=5),
                             entry_style="market")]
        else:
            extreme = min(extreme, b.low)
            if b.close > orb_l:                            # failed -> long
                stop = extreme - 0.10 * atr
                entry = b.close
                stop_d = entry - stop                      # long: stop below entry
                if stop_d <= 0 or stop_d / m.SPECS[sym]["pip"] < 2:
                    return []
                return [dict(side="long", entry=entry, stop=stop,
                             target=entry + stop_d * target_r,
                             sig_ts=b.ts + timedelta(minutes=5),
                             entry_style="market")]
    return []                                              # break held -> no trade


def det_f3(day_bars, atr, sym, orb_bars=8, atr_stop=0.25):
    """Breakout rider: validated ORB entry, stop only, ride to session end."""
    win = [b for b in day_bars if m.lw_utc(b.ts.date(), 7) <= b.ts < m.lw_utc(b.ts.date(), 11)]
    if atr <= 0 or len(win) <= orb_bars + 1:
        return []
    sig = m.sig_orb_atr(win, atr, sym, orb_bars, atr_stop, 3.0)
    if not sig:
        return []
    return [dict(side=sig["direction"], entry=sig["entry"], stop=sig["stop"],
                 target=None, sig_ts=sig["bbar"].ts + timedelta(minutes=5),
                 entry_style="limit")]


def det_f4(day_bars, atr, sym, fast=20, slow=50, target_r=2.0, stop_k=1.0):
    """Trend pullback: EMA(fast)>EMA(slow) and price pulls back to touch EMA(fast)
    -> enter with the trend at the touch-bar close. Stop = 1x ATR beyond touch.
    Uses the whole pre-11:00 London day (trend established, no session bounds)."""
    day = [b for b in day_bars if b.ts < m.lw_utc(b.ts.date(), 11)]
    if atr <= 0 or len(day) < slow + 10:
        return []
    closes = [b.close for b in day]
    def ema(vals, n):
        k = 2.0 / (n + 1.0)
        e = sum(vals[:n]) / n
        for v in vals[n:]:
            e = v * k + e * (1 - k)
        return e
    for i in range(slow + 10, len(day)):
        seg = closes[:i + 1]
        ef, es = ema(seg, fast), ema(seg, slow)
        b = day[i]
        up = ef > es
        if up and b.low <= ef:                      # uptrend pullback -> long
            entry = b.close
            stop = b.low - stop_k * atr
            stop_d = entry - stop
            if stop_d <= 0 or stop_d / m.SPECS[sym]["pip"] < 2:
                return []
            return [dict(side="long", entry=entry, stop=stop,
                         target=entry + stop_d * target_r,
                         sig_ts=b.ts + timedelta(minutes=5), entry_style="market")]
        if not up and b.high >= ef:                 # downtrend pullback -> short
            entry = b.close
            stop = b.high + stop_k * atr
            stop_d = stop - entry
            if stop_d <= 0 or stop_d / m.SPECS[sym]["pip"] < 2:
                return []
            return [dict(side="short", entry=entry, stop=stop,
                         target=entry - stop_d * target_r,
                         sig_ts=b.ts + timedelta(minutes=5), entry_style="market")]
    return []


DETECTORS = {
    "F1": (det_f1, {"sd_k": [2.0, 2.5]}),
    "F2": (det_f2, {"wait": [3, 5], "target_r": [1.0, 1.5]}),
    "F3": (det_f3, {"orb_bars": [6, 8], "atr_stop": [0.25, 0.5]}),
    "F4": (det_f4, {"target_r": [1.5, 2.0, 3.0], "stop_k": [0.5, 1.0]}),
}


# ---------------------------------------------------------------------------
# shared honest simulator
# ---------------------------------------------------------------------------

def sim(sig, day_bars, end_utc, symbol, pv, *, risk_frac, ambiguity="coin", costs=True):
    spec = m.SPECS[symbol]
    d, entry, stop = sig["side"], sig["entry"], sig["stop"]
    stop_d = abs(entry - stop)
    lpl = stop_d / spec["pip"] * pv + (v2.COMM_RT if costs else 4.0)
    lots = max(0.0, math.floor((m.ACCOUNT_BALANCE * risk_frac / lpl) / m.VOLUME_STEP) * m.VOLUME_STEP)
    if lots < m.VOLUME_MIN:
        return None
    target = sig["target"]

    bbar_end = sig["sig_ts"]
    fwd = [b for b in day_bars if bbar_end <= b.ts < end_utc]
    if not fwd:
        return None

    if sig["entry_style"] == "limit":
        fill_i = None
        for i, b in enumerate(fwd):
            if (d == "long" and b.low <= entry) or (d == "short" and b.high >= entry):
                fill_i = i
                break
        if fill_i is None:
            return None
    else:
        fill_i = 0                                          # filled at signal close

    exit_px, reason = entry, "session_end"
    exit_ts = fwd[-1].ts + timedelta(minutes=5)
    ambiguous = False
    for b in fwd[fill_i:]:
        if d == "long":
            hit_t = target is not None and b.high >= target
            hit_s = b.low <= stop
        else:
            hit_t = target is not None and b.low <= target
            hit_s = b.high >= stop
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
    else:
        exit_px, reason = fwd[-1].close, "session_end"

    gpips = ((exit_px - entry) if d == "long" else (entry - exit_px)) / spec["pip"]
    spread_cash = ((v2.SPREAD_STD[symbol] * v2.RAW_SCALE) / spec["pip"]) * pv * lots if costs else 0.0
    comm = v2.COMM_RT * lots if costs else 4.0 * lots
    net = gpips * pv * lots - comm - spread_cash
    risk_c = stop_d / spec["pip"] * pv * lots + comm + spread_cash
    return dict(symbol=symbol, pnl=net, r=net / risk_c if risk_c > 0 else 0.0,
                reason=reason, ambiguous=ambiguous, cost=comm + spread_cash,
                exit_ts=exit_ts)


def run_family(cache, family, dparams, universe, *, risk_frac=0.01,
               ambiguity="coin", costs=True, max_per_day=2):
    lp, np_ = universe
    sessions = [(0, s) for s in lp] + [(1, s) for s in np_]
    all_dates = sorted({d for sym in cache for d in cache[sym][0] if d.weekday() < 5})
    balance = m.ACCOUNT_BALANCE
    total_floor = balance * m.TOTAL_FLOOR_PCT
    trades, equity = [], [(all_dates[0], balance)]
    halted = qual = 0
    p1, days_to_p1, tdays = False, None, 0
    det_fn, _ = DETECTORS[family]

    for d in all_dates:
        if halted:
            break
        tdays += 1
        day_start = balance
        daily_floor = day_start * (1.0 - m.DAILY_LOSS_LIMIT + m.SAFETY_BUFFER)
        day_pnl = 0.0
        traded = 0
        cands = []
        prev_days = [dd for dd in all_dates if dd < d]
        for prio, sym in sessions:
            if sym not in cache or d not in cache[sym][0]:
                continue
            by_date_sym, atr_map = cache[sym]
            day_bars = by_date_sym[d]
            atr = 0.0
            if family in ("F1", "F4"):         # prev-day ATR: no same-day lookahead
                for pd in reversed(prev_days[-5:]):
                    if atr_map.get(pd, 0) > 0:
                        atr = atr_map[pd]
                        break
            else:
                atr = atr_map.get(d, 0.0)
            sigs = det_fn(day_bars, atr, sym, **dparams) if atr > 0 else []
            end_utc = (m.lw_utc(d, 6, 30) if family == "F1" else m.lw_utc(d, 11))
            for sig in sigs:
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
            t = sim(sig, day_bars, end_utc, sym, sig["pv"], risk_frac=risk_frac,
                    ambiguity=ambiguity, costs=costs)
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
    return dict(family=family, params=dparams, n=n,
                wr=wins / n if n else 0.0,
                pf=gw / gl if gl > 0 else float("inf"),
                avg_r=(sum(t["r"] for t in trades) / n) if n else 0.0,
                total=tc, monthly=tc * 21.0 / max(tdays, 1),
                dd=mdd / peak * 100 if peak > 0 else 0.0,
                amb=(sum(1 for t in trades if t["ambiguous"]) / n) if n else 0.0,
                p1=p1, p1_days=days_to_p1, halted=halted, qual=qual,
                risk=risk_frac, trades=trades)


def show(r, label=""):
    p1 = f"{r['p1_days']}d" if r["p1"] else ("HALT" if r["halted"] else "NO")
    mo_pct = r["monthly"] / m.ACCOUNT_BALANCE * 100
    print(f"  {label}{r['family']} {str(r['params']):<42} {r['n']:>4} "
          f"WR={r['wr']*100:>4.1f}% PF={r['pf']:>4.2f} AvgR={r['avg_r']:>5.2f} "
          f"amb={r['amb']*100:>3.0f}% DD={r['dd']:>4.1f}% "
          f"mth={mo_pct:>5.2f}% P1={p1:>6}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--confirm", action="store_true")
    args = ap.parse_args()
    print("=" * 108)
    print("FAST-TRACK LAB — honest framework (bounds, raw costs, one slot) — 2-year gate")
    print("=" * 108)
    cache = v2.load_cache(DATA_2Y)

    universes = {"core3": (CORE3, []), "quiet5": (QUIET5, []),
                 "lon11": (LON11, [])}
    results = []
    for fam, (fn, grid) in DETECTORS.items():
        keys = list(grid)
        for combo in _param_grid(grid):
            dp = dict(zip(keys, combo))
            unis = list(universes.keys()) if fam != "F1" else ["quiet5", "core3"]
            for uni_name in unis:
                r = run_family(cache, fam, dp, universes[uni_name], risk_frac=0.01)
                r["uni"] = uni_name
                results.append(r)
    results.sort(key=lambda r: (r["p1_days"] if r["p1_days"] else 9999,
                                -(r["monthly"] / m.ACCOUNT_BALANCE * 100)))
    print(f"\n{'Unis.':<7} {'Family/params':<56} {'N':>4} WR    PF   AvgR  amb  DD   mth%  P1")
    print("  " + "-" * 104)
    for r in results:
        show(r, f"[{r['uni']:<6}] ")
    ok = [r for r in results if r["p1"]]
    print(f"\n  {len(ok)}/{len(results)} runs passed Phase 1 within the 2-year window at 1% risk")
    best3 = ok[:3]
    if best3:
        print("\n=== Bounds check for top 3 (coin vs pessimistic; opt shown too) ===")
        for r in best3:
            for amb in ("target", "coin", "stop"):
                rb = run_family(cache, r["family"], r["params"], universes[r["uni"]],
                                risk_frac=0.01, ambiguity=amb)
                show(rb, f"[{r['uni']:<6}] amb={amb:<5} ")
    if args.confirm and ok:
        print("\n=== 4-YEAR CONFIRMATION of top 3 ===")
        cache4 = v2.load_cache(DATA_4Y)
        for r in best3:
            for amb in ("coin", "stop"):
                rb = run_family(cache4, r["family"], r["params"], universes[r["uni"]],
                                risk_frac=0.01, ambiguity=amb)
                show(rb, f"4y[{r['uni']:<6}] amb={amb:<5} ")


def _param_grid(grid):
    keys = list(grid)
    out = [[]]
    for k in keys:
        out = [row + [v] for row in out for v in grid[k]]
    return [tuple(row) for row in out]


if __name__ == "__main__":
    main()
