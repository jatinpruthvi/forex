"""
Swing/Trend-Following Lab (2026-09-12)
======================================
Track B extension: the one strategy class NOT yet tested — multi-day
trend-following (CTA-style Donchian/chandelier) on the instruments with the
biggest historical trends. Daily bars aggregated from the M5 dataset.

System: close breaks N-day high/low -> enter next day at the daily open in the
breakout direction; chandelier exit = extreme-close-since-entry -/+ k*ATR(d,14),
evaluated on daily closes, exit next day open; opposite breakout also exits.
Risk % normalized on the k*ATR initial stop. Costs: entry spread + $7/lot RT
(swing stops are wide => cost share is small; charged anyway).

Scalping is NOT testable on this data (bid-only M5, volume=0 on the 4y files;
scalping results are decided by tick-level spread/slippage). See findings.

Usage: python tools/swing_lab.py
"""
from __future__ import annotations

import hashlib
import math
import os
import sys
from collections import defaultdict
from datetime import timedelta

sys.path.insert(0, os.path.abspath("."))
import tools.aggressive_optimizer as m       # noqa: E402
import tools.optimizer_v2 as v2              # noqa: E402

RAW_SCALE, COMM_RT = 0.55, 7.0


def _coin(key: str) -> bool:
    return int(hashlib.md5(key.encode()).hexdigest(), 16) % 2 == 0


def daily_bars(cache_day_bars):
    """Aggregate a symbol's M5 day-bars into daily OHLC keyed by UTC date."""
    out: dict = {}
    for d, bars in cache_day_bars.items():
        out[d] = dict(open=bars[0].open, high=max(b.high for b in bars),
                      low=min(b.low for b in bars), close=bars[-1].close,
                      n=len(bars))
    return out


def atr14(dailies_list, i, n=14):
    win = dailies_list[max(0, i - n):i]
    if len(win) < 5:
        return 0.0
    return sum(t[1]["high"] - t[1]["low"] for t in win) / len(win)


def run_donchian(cache, symbols, n_chan=20, k_atr=3.0, risk_frac=0.02,
                 costs=True, allow_short=True):
    # aggregate each symbol once
    agg = {s: daily_bars(cache[s][0]) for s in symbols if s in cache}
    dates = sorted({d for s in agg for d in agg[s]})
    dates = [d for d in dates if d.weekday() < 5]

    balance = 1.0
    peak = 1.0
    mdd = 0.0
    trades = []
    yearly_eq: dict = {}

    for s in agg:
        dl = list(agg[s].items())            # [(date, ohlc)] in order
        idx = {d: i for i, (d, _) in enumerate(dl)}
        pos = None                            # dict(side, entry, stop0, extreme, lots_eq)
        pend = None                           # pending entry signal
        for i in range(n_chan + 1, len(dl)):
            d, bar = dl[i]
            if pos is None and pend is not None:
                # enter at today's open
                entry = bar["open"]
                side = pend
                atr = atr14(dl, i)
                if atr <= 0:
                    pend = None
                    continue
                stop0 = entry - k_atr * atr if side == "long" else entry + k_atr * atr
                pos = dict(side=side, entry=entry, stop0=stop0, atr=atr,
                           extreme=entry, entry_date=d)
                pend = None
            # check exit on prior close already done at previous loop end
            if pos is None:
                # breakout check using today's close
                hi_n = max(dl[j][1]["high"] for j in range(i - n_chan, i))
                lo_n = min(dl[j][1]["low"] for j in range(i - n_chan, i))
                if bar["close"] > hi_n:
                    pend = "long"
                elif allow_short and bar["close"] < lo_n:
                    pend = "short"
                continue
            # manage position: update chandelier with today's close
            side = pos["side"]
            pos["extreme"] = max(pos["extreme"], bar["close"]) if side == "long" \
                else min(pos["extreme"], bar["close"])
            trail = pos["extreme"] - k_atr * pos["atr"] if side == "long" \
                else pos["extreme"] + k_atr * pos["atr"]
            stop_hit = (side == "long" and bar["close"] < max(pos["stop0"], trail)) or \
                       (side == "short" and bar["close"] > min(pos["stop0"], trail))
            # opposite breakout also exits
            hi_n = max(dl[j][1]["high"] for j in range(i - n_chan, i))
            lo_n = min(dl[j][1]["low"] for j in range(i - n_chan, i))
            opp = (side == "long" and bar["close"] < lo_n) or \
                  (side == "short" and bar["close"] > hi_n)
            if stop_hit or opp:
                spec = m.SPECS[s]
                pv = m.day_pv(s, d, cache)
                exit_px = dl[i + 1][1]["open"] if i + 1 < len(dl) else bar["close"]
                entry = pos["entry"]
                stop_d = k_atr * pos["atr"]
                gpips = ((exit_px - entry) if side == "long" else (entry - exit_px)) / spec["pip"]
                spread_cash = ((v2.SPREAD_STD[s] * RAW_SCALE) / spec["pip"]) * pv if costs else 0.0
                comm = COMM_RT if costs else 4.0
                net_r = (gpips * pv - comm - spread_cash) / (stop_d / spec["pip"] * pv + comm + spread_cash)
                balance *= (1.0 + risk_frac * net_r)
                peak = max(peak, balance)
                mdd = max(mdd, (peak - balance) / peak)
                trades.append(dict(sym=s, side=side, r=net_r, date=d))
                pos = None
        yearly_eq[s] = balance  # unused per-year below; global curve only

    n = len(trades)
    wr = sum(1 for t in trades if t["r"] > 0) / n if n else 0.0
    gw = sum(t["r"] for t in trades if t["r"] > 0)
    gl = -sum(t["r"] for t in trades if t["r"] <= 0)
    span_years = (dates[-1] - dates[0]).days / 365.25
    cagr = (balance ** (1 / span_years) - 1) * 100 if span_years > 0.5 and balance > 0 else 0.0
    by_year = defaultdict(lambda: 1.0)
    prev_eq = defaultdict(lambda: 1.0)
    eq = 1.0
    ys = sorted({t["date"].year for t in trades})
    yr_mult = defaultdict(lambda: 1.0)
    # recompute equity per year for yearly returns
    eq = 1.0
    yearly_ret = {}
    for y in ys:
        start = eq
        for t in [t for t in trades if t["date"].year == y]:
            eq *= (1.0 + risk_frac * t["r"])
        yearly_ret[y] = (eq / start - 1) * 100
    return dict(n=n, wr=wr, pf=(gw / gl if gl > 0 else float("inf")),
                avg_r=(sum(t["r"] for t in trades) / n) if n else 0.0,
                cagr=cagr, dd=mdd * 100, final=balance,
                yearly=yearly_ret, trades=trades,
                span=span_years, params=(n_chan, k_atr, risk_frac))


def show(label, r):
    print(f"  {label:<44} {r['n']:>4} WR={r['wr']*100:>4.1f}% PF={r['pf']:>5.2f} "
          f"AvgR={r['avg_r']:>5.2f} CAGR={r['cagr']:>6.1f}% DD={r['dd']:>4.1f}% "
          f"| yearly: " + " ".join(f"{y}:{v:>6.1f}%" for y, v in sorted(r['yearly'].items())))


def main():
    print("=" * 112)
    print("SWING / TREND-FOLLOWING LAB — daily Donchian+chandelier, honest costs, compounding (2022-2026)")
    print("=" * 112)
    cache = v2.load_cache(v2.DATA_4Y)
    universes = {
        "gold": ["XAUUSD"],
        "gold+gbpjpy": ["XAUUSD", "GBPJPY"],
        "core3": ["XAUUSD", "GBPJPY", "EURJPY"],
        "all11": list(m.SPECS),
    }
    results = []
    for uni_name, syms in universes.items():
        for n_chan in (20, 55):
            for k in (2.5, 3.5):
                r = run_donchian(cache, syms, n_chan, k, risk_frac=0.02)
                r["uni"] = uni_name
                results.append(r)
                show(f"[{uni_name:<11}] N={n_chan:<3} k={k}", r)
    ok = [r for r in results if r["dd"] <= 10.5 and r["cagr"] > 0]
    ok.sort(key=lambda r: -r["cagr"])
    if ok:
        print("\n=== Best DD<=10% config — risk calibration ===")
        b = ok[0]
        print(f"  winner: [{b['uni']}] N={b['params'][0]} k={b['params'][1]}")
        for rf in (0.01, 0.02, 0.03, 0.04, 0.05):
            rr = run_donchian(cache, universes[b["uni"]], b["params"][0], b["params"][1], risk_frac=rf)
            show(f"risk={rf*100:.0f}%", rr)
    else:
        print("\n  No config with CAGR>0 and DD<=10.5%.")


if __name__ == "__main__":
    main()
