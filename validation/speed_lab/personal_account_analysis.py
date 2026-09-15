#!/usr/bin/env python3
"""
personal_account_analysis.py — the same edge, but sized for a LIVE PERSONAL account.

A funded/prop account and a personal account are different optimisation problems:

  prop account   maximise P(reach +10% before hitting a 5% daily loss or the
                 $2,250 static floor) within a time limit
                 -> risk is capped at 0.75%/trade BY THE FIRM'S RULES

  personal acct  maximise long-run compounded growth subject to a drawdown you
                 can personally tolerate; no daily-loss limit, no floor, no clock
                 -> risk is capped only by variance and ruin mathematics

So the question "can this make ~10%/month on my own account?" cannot be answered
with the prop numbers. This script re-runs the FROZEN strategy (same signals,
same exits, same costs) with the firm gates removed, and reports the monthly
return distribution, drawdown profile, and - critically - the two cost/behaviour
terms the prop analysis could afford to ignore but a multi-year personal account
cannot: OVERNIGHT SWAP and the hold-time distribution that drives it.

Usage:  python3 validation/speed_lab/personal_account_analysis.py
"""
from __future__ import annotations

import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import verify_final_config as V   # noqa: E402  (frozen signal/exit/cost model)

MS_DAY = 86_400_000
TRAIN_END = V.TRAIN_END


# --------------------------------------------------------------------------
def replay_personal(trades, risk_pct, mode="initial", max_conc=2, cap_day=5,
                    breaker=3.0, swap_R_per_night=0.0):
    """Event replay with NO firm gates: no equity floor, no daily-loss limit,
    no profit target, no qualifying-day requirement. Only the trader's own
    risk controls remain (concurrency, trades/day, -3R daily breaker).

    mode="initial"  -> fixed fractional on the starting balance (no compounding)
    mode="equity"   -> fixed fractional on current equity (compounding)
    swap_R_per_night-> extra cost, in R, per overnight rollover a position holds
    """
    ev = []
    for t in trades:
        ev.append((t.ets, 0, t))
        ev.append((t.xts, 1, t))
    ev.sort(key=lambda x: (x[0], x[1], x[2].sym))

    A0 = V.ACCOUNT
    bal, peak, mdd = A0, A0, 0.0
    mdd_start = 0
    worst_dd, worst_dd_at = 0.0, 0
    day_key, day_pnl, today, locked = -1, 0.0, 0, False
    openp, open_risk, open_nights = {}, 0.0, {}
    months = {}          # 'YYYY-MM' -> net P&L in dollars
    start_month = None

    for ets, kind, t in ev:
        dt = datetime.fromtimestamp((ets + V.SRV_MS) / 1000, tz=timezone.utc)
        mk = dt.strftime("%Y-%m")
        if start_month is None:
            start_month = mk
        dk = (ets + V.SRV_MS) // MS_DAY
        if dk != day_key:
            day_key, day_pnl, today, locked = dk, 0.0, 0, False

        if kind == 1:
            if id(t) not in openp:
                continue
            rc = openp.pop(id(t))
            open_risk -= rc
            nights = open_nights.pop(id(t), 0)
            net = (t.R - t.cost_R - swap_R_per_night * nights) * rc
            bal += net
            day_pnl += net
            months[mk] = months.get(mk, 0.0) + net
            peak = max(peak, bal)
            dd = (peak - bal) / peak
            if dd > worst_dd:
                worst_dd, worst_dd_at = dd, ets
            mdd = max(mdd, dd)
        else:
            if locked or today >= cap_day or len(openp) >= max_conc:
                continue
            if t.xts <= ets:
                continue
            if dt.weekday() == 4 and dt.hour >= 21:      # market close, no new risk
                locked = True
                continue
            base = A0 if mode == "initial" else bal
            rc = base * risk_pct
            loss_per_lot = t.stop_pips * V.SPECS[t.sym][1] + V.COMM_RT
            if loss_per_lot <= 0:
                continue
            lots = int((rc / loss_per_lot) / V.VOL_STEP) * V.VOL_STEP
            if lots < V.VOL_MIN:
                continue
            if day_pnl <= -(breaker * rc):
                locked = True
                continue
            today += 1
            openp[id(t)] = rc
            open_risk += rc
            # overnight rollovers crossed between entry and exit (server days)
            open_nights[id(t)] = max(0, ((t.xts + V.SRV_MS) // MS_DAY)
                                     - ((t.ets + V.SRV_MS) // MS_DAY))

    return dict(final=bal, total_ret=(bal - A0) / A0, mdd=worst_dd,
                months=months, start_month=start_month,
                n_trades=len(open_nights) + 0)


def month_stats(res, A0=V.ACCOUNT):
    ms = res["months"]
    keys = sorted(ms)
    rets = [ms[k] / A0 for k in keys]           # % of the INITIAL account
    return keys, rets


def pct(x, s):
    if not s:
        return 0.0
    s = sorted(s)
    i = int(x * (len(s) - 1))
    return s[i]


def main():
    print("=" * 116)
    print("PERSONAL LIVE ACCOUNT — frozen M5 long-only fade, firm gates REMOVED")
    print("no equity floor | no 5% daily-loss limit | no +10% target | no clock")
    print("kept: <=2 concurrent, <=5 trades/day, -3R daily breaker, no entries after Fri 21:00 server")
    print("=" * 116)

    all_tr, train_tr, test_tr = [], [], []
    for sym in V.SPECS:
        tr = V.build(sym)
        all_tr += tr
        train_tr += [t for t in tr if t.ets < TRAIN_END]
        test_tr += [t for t in tr if t.ets >= TRAIN_END]
    for L in (all_tr, train_tr, test_tr):
        L.sort(key=lambda t: (t.ets, t.sym))

    # ---------------- hold-time / overnight exposure ----------------
    nights = [max(0, ((t.xts + V.SRV_MS) // MS_DAY) - ((t.ets + V.SRV_MS) // MS_DAY))
              for t in all_tr]
    hold_h = [(t.xts - t.ets) / 3_600_000 for t in all_tr]
    n = len(nights)
    print(f"\n--- OVERNIGHT EXPOSURE (drives swap cost, which the prop model omitted) ---")
    print(f"  trades (4y, all pairs)      : {n}")
    print(f"  hold time  median / mean    : {pct(0.5,hold_h):.1f} h / {sum(hold_h)/n:.1f} h")
    print(f"  hold time  p90 / max        : {pct(0.9,hold_h):.1f} h / {max(hold_h):.1f} h")
    print(f"  nights crossed  mean        : {sum(nights)/n:.3f} per trade")
    print(f"  trades crossing >=1 night   : {sum(1 for x in nights if x>=1)/n*100:.1f}%")
    print(f"  trades crossing >=2 nights  : {sum(1 for x in nights if x>=2)/n*100:.1f}%")
    print(f"  -> at risk r%, swap drag per night = {sum(nights)/n:.3f} x r% of account per trade")

    # ---------------- risk frontier for a personal account ----------------
    print("\n" + "=" * 116)
    print("RISK FRONTIER — 4 YEARS OF DATA (TRAIN 2022-09..2024-09 + TEST 2024-09..2026-09), FIXED sizing")
    print("=" * 116)
    hdr = (f"{'risk%':>7}{'4y total':>10}{'/month':>9}{'medMo%':>8}{'worstMo%':>10}"
           f"{'bestMo%':>9}{'loseMo%':>9}{'maxDD%':>8}")
    print(hdr)
    print("-" * 116)
    rows = {}
    for r in (0.0025, 0.0036, 0.005, 0.0075, 0.01, 0.015, 0.02):
        res = replay_personal(all_tr, r, mode="initial")
        keys, rets = month_stats(res)
        nmo = len(rets)
        per_mo = sum(rets) / nmo if nmo else 0
        lose = sum(1 for x in rets if x < 0) / nmo * 100 if nmo else 0
        rows[r] = (res, keys, rets)
        print(f"{r*100:>7.2f}{res['total_ret']*100:>9.1f}%{per_mo*100:>8.2f}%"
              f"{pct(0.5,rets)*100:>7.2f}%{min(rets)*100:>9.2f}%{max(rets)*100:>8.2f}%"
              f"{lose:>8.1f}%{res['mdd']*100:>7.1f}%")

    # ---------------- the 10%/month question, per window ----------------
    print("\n" + "=" * 116)
    print("THE ~10%/MONTH QUESTION — does the edge deliver it, and in which half of the data?")
    print("=" * 116)
    print(f"{'window':<12}{'months':>8}{'risk%':>8}{'mean/mo':>10}{'median/mo':>11}"
          f"{'worst/mo':>10}{'losing mo':>11}{'maxDD':>8}{'>=10%?':>9}")
    print("-" * 116)
    for label, trs in (("TRAIN", train_tr), ("TEST", test_tr), ("ALL 4y", all_tr)):
        for r in (0.0036, 0.005, 0.0075):
            res = replay_personal(trs, r, mode="initial")
            keys, rets = month_stats(res)
            if not rets:
                continue
            nmo = len(rets)
            mean = sum(rets) / nmo
            med = pct(0.5, rets)
            hit = sum(1 for x in rets if x >= 0.10) / nmo * 100
            lose = sum(1 for x in rets if x < 0) / nmo * 100
            print(f"{label:<12}{nmo:>8}{r*100:>8.2f}{mean*100:>9.2f}%{med*100:>10.2f}%"
                  f"{min(rets)*100:>9.2f}%{lose:>10.1f}%{res['mdd']*100:>7.1f}%{hit:>8.1f}%")
        print("-" * 116)

    # ---------------- swap sensitivity ----------------
    print("\n" + "=" * 116)
    print("SWAP SENSITIVITY — the cost the 27-day prop run could ignore but a multi-year account cannot")
    print("swap charged in R per overnight rollover, applied to every position held across a server midnight")
    print("=" * 116)
    print(f"{'swap R/night':>13}{'E_net R/trade':>15}{'4y total @0.5%':>16}{'/month @0.5%':>14}{'maxDD':>8}")
    print("-" * 116)
    base_en = sum(t.R - t.cost_R for t in all_tr) / len(all_tr)
    mean_nights = sum(nights) / n
    for sw in (0.0, 0.02, 0.05, 0.10, 0.20, 0.30):
        res = replay_personal(all_tr, 0.005, mode="initial", swap_R_per_night=sw)
        keys, rets = month_stats(res)
        nmo = len(rets) or 1
        en = base_en - sw * mean_nights
        print(f"{sw:>13.2f}{en:>15.4f}{res['total_ret']*100:>15.1f}%"
              f"{sum(rets)/nmo*100:>13.2f}%{res['mdd']*100:>7.1f}%")

    # ---------------- compounding ----------------
    print("\n" + "=" * 116)
    print("FIXED vs COMPOUNDED sizing over 4 years (no swap, 0.50% and 0.75% risk)")
    print("=" * 116)
    for r in (0.005, 0.0075):
        f = replay_personal(all_tr, r, mode="initial")
        c = replay_personal(all_tr, r, mode="equity")
        print(f"  risk {r*100:.2f}%   fixed: {f['total_ret']*100:>+8.1f}%  maxDD {f['mdd']*100:>5.1f}%"
              f"   |   compounded: {c['total_ret']*100:>+9.1f}%  maxDD {c['mdd']*100:>5.1f}%")
    print("\n  compounding multiplies both the return and the drawdown; the maxDD above is")
    peak_note = "  peak-relative, so it is the fraction of your high-water mark you must sit through."

    # ---------------- monthly detail at the 10%/month setting ----------------
    print("\n" + "=" * 116)
    print("MONTH-BY-MONTH at 0.50% risk, fixed sizing, 4 years (% of initial account)")
    print("=" * 116)
    res, keys, rets = rows[0.005]
    for i in range(0, len(keys), 6):
        chunk = list(zip(keys[i:i + 6], rets[i:i + 6]))
        print("   " + "   ".join(f"{k}:{v*100:+6.1f}%" for k, v in chunk))
    cum, worst_run, run = 0.0, 0, 0
    for v in rets:
        if v < 0:
            run += 1
            worst_run = max(worst_run, run)
        else:
            run = 0
    print(f"\n  longest losing streak : {worst_run} consecutive months")
    print(f"  months in the sample  : {len(rets)}")
    print(peak_note)


if __name__ == "__main__":
    main()
