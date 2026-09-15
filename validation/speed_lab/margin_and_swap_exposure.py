#!/usr/bin/env python3
"""
margin_and_swap_exposure.py — resolve the two open items from findings_phase2_speed.md B.6

Both were flagged as "check with your broker". Partly they can be settled from the repo's own
data instead:

  1. MARGIN / LEVERAGE  - is holding all 11 pairs at once actually possible on a $2,500
     account? Computed from real lot sizes (0.50% risk, actual median stop distance per
     pair) and real notional (base-currency contract size x the last close in the data),
     across the leverage tiers retail brokers actually offer.

  2. SWAP EXPOSURE MAP  - swap cannot be computed without a broker table, but WHERE it
     lands can. This reports, per pair: nights held per trade, share of total net R, and
     the sign of carry a LONG position would have paid or earned over 2022-2026 from the
     policy-rate differential. That turns "unknown" into "concentrated here, and you can
     price exactly these lines".

Carry signs are the standard short-rate differential for a LONG position
(long pays when the quote currency's rate exceeds the base currency's):
  2022-2024   USD rates rose far above EUR/GBP/AUD/NZD/CHF -> longs on the USD-short
              pairs PAID; USDJPY / GBPJPY / EURJPY longs EARNED (huge JPY differential)
  2024-2026   ECB/RBA/RBNZ cut ahead of or with the Fed, BoJ hiked -> the JPY carry
              compressed sharply and USD-short carry became mild or positive
So the sign is period-dependent for most pairs and only the JPY crosses are unambiguous.

Usage:  python3 validation/speed_lab/margin_and_swap_exposure.py
"""
from __future__ import annotations

import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import verify_final_config as V   # noqa: E402

ACCOUNT = V.ACCOUNT
CONTRACT_FX = 100_000.0
CONTRACT_XAU = 100.0

# base currency of each instrument, and where to get its USD price
BASE = {
    "EURUSD": ("EUR", "EURUSD"), "GBPUSD": ("GBP", "GBPUSD"),
    "EURGBP": ("EUR", "EURUSD"), "AUDUSD": ("AUD", "AUDUSD"),
    "NZDUSD": ("NZD", "NZDUSD"), "USDCAD": ("USD", None),
    "USDCHF": ("USD", None),     "USDJPY": ("USD", None),
    "EURJPY": ("EUR", "EURUSD"), "GBPJPY": ("GBP", "GBPUSD"),
    "XAUUSD": ("XAU", "XAUUSD"),
}

# long-position carry sign by regime (see module docstring)
CARRY = {
    "EURUSD": ("pays", "mild/neutral"), "GBPUSD": ("pays", "mild/neutral"),
    "EURGBP": ("pays", "earns"),        "AUDUSD": ("earns", "neutral"),
    "NZDUSD": ("earns", "neutral"),     "USDCAD": ("earns", "neutral"),
    "USDCHF": ("earns", "earns"),       "USDJPY": ("earns++", "compressed"),
    "EURJPY": ("earns++", "compressed"),"GBPJPY": ("earns++", "compressed"),
    "XAUUSD": ("pays", "pays"),
}


def last_close(sym):
    ts, o, h, l, c = V.load(sym)
    return c[-1], ts[-1]


def lots_for(sym, stop_pips, risk_pct):
    rc = ACCOUNT * risk_pct
    loss_per_lot = stop_pips * V.SPECS[sym][1] + V.COMM_RT
    if loss_per_lot <= 0:
        return 0.0
    return int((rc / loss_per_lot) / V.VOL_STEP) * V.VOL_STEP


def median(x):
    if not x:
        return 0.0
    s = sorted(x)
    n = len(s)
    return s[n // 2] if n % 2 else 0.5 * (s[n // 2 - 1] + s[n // 2])


_CACHE = {}


def trades_of(sym):
    if sym not in _CACHE:
        _CACHE[sym] = V.build(sym)
    return _CACHE[sym]


def main():
    print("=" * 118)
    print("MARGIN & SWAP-EXPOSURE ANALYSIS — frozen config, all 11 pairs, 4 years of repo data")
    print("=" * 118)

    px = {s: last_close(s)[0] for s in V.SPECS}
    stats = {}
    for sym in V.SPECS:
        tr = trades_of(sym)
        if not tr:
            continue
        nights = [max(0, ((t.xts + V.SRV_MS) // V.MS_DAY) - ((t.ets + V.SRV_MS) // V.MS_DAY))
                  for t in tr]
        netR = [t.R - t.cost_R for t in tr]
        stats[sym] = dict(n=len(tr), stop=median([t.stop_pips for t in tr]),
                          nights=sum(nights) / len(nights),
                          pct_night=sum(1 for x in nights if x >= 1) / len(nights) * 100,
                          netR=sum(netR))
    tot_R = sum(s["netR"] for s in stats.values())
    tot_nights = sum(s["nights"] * s["n"] for s in stats.values())

    # ---------------- per-pair map ----------------
    print("\n--- PER-PAIR: where the edge and the overnight exposure actually sit (4 years) ---")
    print(f"{'sym':<8}{'trades':>8}{'medStopP':>10}{'nights/tr':>11}{'>=1 night':>11}"
          f"{'net R':>9}{'% of R':>8}  {'carry 22-24':<12}{'carry 24-26':<12}")
    print("-" * 118)
    for sym in sorted(stats, key=lambda s: -stats[s]["netR"]):
        s = stats[sym]
        c = CARRY[sym]
        print(f"{sym:<8}{s['n']:>8}{s['stop']:>10.2f}{s['nights']:>11.3f}{s['pct_night']:>10.1f}%"
              f"{s['netR']:>+9.0f}{s['netR']/tot_R*100:>7.1f}%  {c[0]:<12}{c[1]:<12}")
    print("-" * 118)
    print(f"{'TOTAL':<8}{sum(s['n'] for s in stats.values()):>8}{'':>10}"
          f"{tot_nights/sum(s['n'] for s in stats.values()):>11.3f}{'':>11}{tot_R:>+9.0f}{100.0:>7.1f}%")

    # ---------------- margin ----------------
    print("\n" + "=" * 118)
    print("MARGIN FEASIBILITY — all 11 positions open at once, 0.50% risk on $2,500")
    print("lot size = floor(risk_cash / (stop_pips x pip_value + $7 commission) / 0.01) x 0.01")
    print("=" * 118)
    print(f"{'sym':<8}{'medStopP':>10}{'lots':>8}{'base':>6}{'px(USD)':>10}"
          f"{'notional$':>12}{'1:30':>9}{'1:50':>9}{'1:100':>9}{'1:200':>9}{'1:500':>9}")
    print("-" * 118)
    lots = {}
    marg = {lev: 0.0 for lev in (30, 50, 100, 200, 500)}
    tot_notional = 0.0
    for sym in V.SPECS:
        if sym not in stats:
            continue
        L = lots_for(sym, stats[sym]["stop"], 0.005)
        lots[sym] = L
        ccy, ref = BASE[sym]
        usd_px = 1.0 if ref is None else px[ref]
        contract = CONTRACT_XAU if sym == "XAUUSD" else CONTRACT_FX
        notional = L * contract * usd_px
        tot_notional += notional
        row = []
        for lev in (30, 50, 100, 200, 500):
            m = notional / lev
            marg[lev] += m
            row.append(m)
        print(f"{sym:<8}{stats[sym]['stop']:>10.2f}{L:>8.2f}{ccy:>6}{usd_px:>10.4f}"
              f"{notional:>12,.0f}" + "".join(f"{x:>9,.0f}" for x in row))
    print("-" * 118)
    print(f"{'TOTAL':<8}{'':>10}{sum(lots.values()):>8.2f}{'':>6}{'':>10}{tot_notional:>12,.0f}"
          + "".join(f"{marg[l]:>9,.0f}" for l in (30, 50, 100, 200, 500)))
    print(f"\n  account equity = ${ACCOUNT:,.0f}")
    for lev in (30, 50, 100, 200, 500):
        used = marg[lev] / ACCOUNT * 100
        verdict = ("FEASIBLE" if used <= 60 else
                   "TIGHT" if used <= 100 else "IMPOSSIBLE (margin call)")
        free = ACCOUNT - marg[lev]
        print(f"   1:{lev:<4} margin required ${marg[lev]:>8,.0f}  = {used:>6.1f}% of equity   "
              f"free ${free:>8,.0f}   {verdict}")

    print("\n  NOTE: margin is reserved while the position is open, and this table assumes the")
    print("  WORST case of all 11 pairs signalling simultaneously. In the backtest the realised")
    print("  mean concurrency is far lower - see below.")

    # ---------------- realised concurrency ----------------
    print("\n" + "=" * 118)
    print("REALISED CONCURRENCY — how many positions are actually open at once (4 years)")
    print("=" * 118)
    ev = []
    for sym in V.SPECS:
        for t in trades_of(sym):
            ev.append((t.ets, 1)); ev.append((t.xts, -1))
    ev.sort()
    cur = 0
    dist = {}
    for _, d in ev:
        cur += d
        dist[cur] = dist.get(cur, 0) + 1
    tot = sum(dist.values())
    cdf = 0
    shown = set()
    for k in sorted(dist):
        cdf += dist[k] / tot
        if k <= 6 or k in (8, 10, 11) or cdf > 0.995:
            if k not in shown:
                print(f"   {k:>2} open : {dist[k]/tot*100:>6.2f}% of the time   (cumulative {cdf*100:>6.2f}%)")
                shown.add(k)
    print(f"   max observed concurrent positions : {max(dist)}")
    mean_conc = sum(k * v for k, v in dist.items()) / tot
    print(f"   mean concurrency                  : {mean_conc:.2f}")
    print(f"\n  -> sizing margin for {max(dist)} positions, not 11, is what the backtest actually needed.")


if __name__ == "__main__":
    main()
