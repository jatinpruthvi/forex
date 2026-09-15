#!/usr/bin/env python3
"""
verify_final_config.py — stdlib-only reproduction of the recommended Phase-1 config.

The research sweep (sweep1..sweep8) used numpy for speed. The repo's convention is
standard library only, so this script re-derives the FINAL frozen configuration
from the raw CSVs with no third-party imports, and reproduces:

  * the per-pair net expectancy table on the held-out TEST window
  * the walk-forward days-to-pass distribution under the real The5ers gates

FROZEN CONFIG (selected on TRAIN 2022-09-11..2024-09-11 only, never on TEST):
  instrument   11 pairs, validation/HistoryData/*-m5-2022-09-11_2026-09-11.csv
  timeframe    M5
  signal       "extreme bar exhaustion fade": a completed M5 bar whose body
               |close-open| exceeds 4.0 x ATR(14, true range) of the PRIOR bars
  side         LONG ONLY - only fade sharp sell-offs. (The short side of the same
               fade was negative in BOTH the TRAIN and the TEST half.)
  entry        NEXT bar's open (you cannot fill at the close of the bar that
               formed the signal)
  stop         signal bar's low - 2.0 x ATR
  target       entry + 10.0 x (entry - stop)
  max hold     96 h, then close at market
  ambiguity    pessimistic - a bar spanning both stop and target books the stop
  costs        round-trip spread = SPREAD_STD x 0.55 (raw account) and $7/lot
               commission, charged inside every trade; lots floored to 0.01
  risk         0.50% of the initial $2,500 per trade (fixed base, no compounding)
  gates        $2,250 equity floor, 5% daily loss on the SERVER day (UTC+3),
               >= 3 qualifying days at >= $12.50, +10% target,
               <= 2 concurrent positions, <= 5 trades/day, stop for the day
               after -3R

Usage:  python3 validation/speed_lab/verify_final_config.py
"""
from __future__ import annotations

import csv
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "validation/HistoryData"

# ---- repo-canonical instrument + cost model (tools/optimizer_v2.py) ----
SPECS = {
    "EURUSD": (0.0001, 10.00, 0.00010), "GBPUSD": (0.0001, 10.00, 0.00014),
    "EURGBP": (0.0001, 12.70, 0.00014), "AUDUSD": (0.0001, 10.00, 0.00012),
    "NZDUSD": (0.0001, 10.00, 0.00016), "USDCAD": (0.0001, 9.80, 0.00018),
    "USDCHF": (0.0001, 9.80, 0.00014),  "USDJPY": (0.01, 6.76, 0.014),
    "EURJPY": (0.01, 6.13, 0.016),      "GBPJPY": (0.01, 5.18, 0.020),
    "XAUUSD": (0.10, 10.00, 0.28),
}
RAW_SCALE, COMM_RT, VOL_STEP, VOL_MIN = 0.55, 7.0, 0.01, 0.01

ACCOUNT, FLOOR, TARGET = 2500.0, 2250.0, 2750.0
DAILY_LOSS, QUAL_DAY, QUAL_N = 0.05, 12.50, 3
SRV_MS, MS_DAY = 3 * 3600 * 1000, 86_400_000

# ---- frozen strategy parameters ----
K, STOP_ATR, TARGET_R, HOLD_H = 4.0, 2.0, 10.0, 96
TRAIN_END = 1726012800000            # 2024-09-11T00:00:00Z


@dataclass
class T:
    sym: str
    ets: int
    xts: int
    R: float          # gross R
    cost_R: float
    stop_pips: float


def load(sym):
    p = DATA / f"{sym.lower()}-m5-2022-09-11_2026-09-11.csv"
    ts, o, h, l, c = [], [], [], [], []
    with open(p, newline="") as f:
        rdr = csv.reader(f)
        next(rdr)
        for row in rdr:
            if len(row) < 5:
                continue
            ts.append(int(row[0])); o.append(float(row[1])); h.append(float(row[2]))
            l.append(float(row[3])); c.append(float(row[4]))
    order = sorted(range(len(ts)), key=lambda i: ts[i])
    return ([x[i] for i in order] for x in (ts, o, h, l, c))


def atr_prior(h, l, c, period=14):
    n = len(c)
    tr = [0.0] * n
    for i in range(n):
        pc = c[i - 1] if i else c[0]
        tr[i] = max(h[i] - l[i], abs(h[i] - pc), abs(l[i] - pc))
    out = [None] * n
    run = 0.0
    for i in range(n):
        run += tr[i]
        if i >= period:
            run -= tr[i - period]
        if i >= period and i + 1 < n:
            out[i + 1] = run / period
    return out


def build(sym):
    """All LONG-only signals for one pair, exits resolved pessimistically."""
    ts, o, h, l, c = load(sym)
    pip, pv, sprd = SPECS[sym]
    atr = atr_prior(h, l, c, 14)
    n = len(c)
    hold = max(8, HOLD_H * 60 // 5)
    spread_pips = sprd * RAW_SCALE / pip
    out = []
    for i in range(15, n - 1):
        a = atr[i]
        if not a or a <= 0:
            continue
        if abs(c[i] - o[i]) <= K * a:
            continue
        if c[i] > o[i]:                      # long-only: fade sharp SELL-OFFS
            continue
        if i + 1 >= n:
            continue
        entry = o[i + 1]                     # honest fill: next bar open
        stop = l[i] - STOP_ATR * a
        dist = entry - stop
        if dist <= 0:
            continue
        target = entry + TARGET_R * dist
        stop_pips = dist / pip
        cost = (spread_pips * pv + COMM_RT) / (stop_pips * pv + COMM_RT)
        R, xts = None, ts[min(i + hold, n - 1)]
        for j in range(i + 1, min(i + hold, n) + 1):   # scan starts on the ENTRY bar
            if j >= n:
                break
            hit_s = l[j] <= stop
            hit_t = h[j] >= target
            if hit_s:                        # pessimistic: stop wins ties
                R, xts = -1.0, ts[j]; break
            if hit_t:
                R, xts = TARGET_R, ts[j]; break
        if R is None:                        # timeout -> close at market
            j = min(i + hold, n - 1)
            R, xts = (c[j] - entry) / dist, ts[j]
        out.append(T(sym, ts[i], xts, R, cost, stop_pips))
    return out


def replay(trades, risk_pct, max_conc=2, cap_day=5, breaker=3.0, start=0, n_starts=40,
           flat_weekend=True):
    A = ACCOUNT
    span = trades[-1].ets - trades[0].ets
    starts = [trades[0].ets + int(i * span / max(n_starts - 1, 1)) for i in range(n_starts)]
    results = []
    for st in starts:
        ev = []
        for t in trades:
            if t.ets < st:
                continue
            ev.append((t.ets, 0, t)); ev.append((t.xts, 1, t))
        ev.sort(key=lambda x: (x[0], x[1]))
        bal, peak, mdd = A, A, 0.0
        qual, day_key, day_start, day_pnl = 0, -1, A, 0.0
        worst_day, today, locked = 0.0, 0, False
        openp, open_risk, first, pass_ts = {}, 0.0, 0, 0
        reason = "not reached"
        for ets, kind, t in ev:
            dk = (ets + SRV_MS) // MS_DAY
            if dk != day_key:
                if day_key != -1:
                    if day_pnl >= QUAL_DAY:
                        qual += 1
                    worst_day = min(worst_day, day_pnl)
                day_key, day_start, day_pnl, today, locked = dk, bal, 0.0, 0, False
            rc = A * risk_pct
            if kind == 1:
                if id(t) not in openp:
                    continue
                open_risk -= openp.pop(id(t))
                net = (t.R - t.cost_R) * rc
                bal += net; day_pnl += net
                peak = max(peak, bal); mdd = max(mdd, (peak - bal) / peak)
                if bal <= FLOOR:
                    reason = "equity floor"; break
                if day_pnl <= -(day_start * DAILY_LOSS):
                    reason = "daily loss limit"; break
                if bal >= TARGET and qual >= QUAL_N:
                    reason = ""; pass_ts = ets; break
            else:
                if locked or today >= cap_day or len(openp) >= max_conc:
                    continue
                if t.xts <= ets:                              # zero-length, skip
                    continue
                if flat_weekend:                              # no entries after Fri 21:00 server
                    dt = datetime.fromtimestamp((ets + SRV_MS) / 1000, tz=timezone.utc)
                    if dt.weekday() == 4 and dt.hour >= 21:
                        locked = True
                        continue
                loss_per_lot = t.stop_pips * SPECS[t.sym][1] + COMM_RT
                if loss_per_lot <= 0:
                    continue
                lots = int((rc / loss_per_lot) / VOL_STEP) * VOL_STEP
                if lots < VOL_MIN:
                    continue
                if bal - open_risk - rc <= FLOOR:
                    continue
                if day_pnl - open_risk <= -(day_start * DAILY_LOSS) * 0.90:
                    locked = True; continue
                if day_pnl <= -(breaker * rc):
                    locked = True; continue
                if first == 0:
                    first = ets
                today += 1
                openp[id(t)] = rc; open_risk += rc
        if day_key != -1 and day_pnl >= QUAL_DAY:
            qual += 1
        results.append(dict(passed=bool(pass_ts), days=(pass_ts - first) // MS_DAY if pass_ts else -1,
                            mdd=mdd, worst_day=worst_day, qual=qual, reason=reason,
                            end=bal))
    npass = sum(1 for r in results if r["passed"])
    days = sorted(r["days"] for r in results if r["passed"])
    med = days[len(days) // 2] if days else -1
    p90 = days[int(0.9 * (len(days) - 1))] if days else -1
    p25 = days[int(0.25 * (len(days) - 1))] if days else -1
    return dict(n=len(results), n_pass=npass, pass_rate=npass / len(results),
                med_days=med, p25=p25, p90=p90,
                worst=max(days) if days else -1, best=min(days) if days else -1,
                max_dd=max(r["mdd"] for r in results),
                worst_day=min(r["worst_day"] for r in results),
                floor_busts=sum(1 for r in results if r["reason"] == "equity floor"),
                daily_busts=sum(1 for r in results if r["reason"] == "daily loss limit"))


def main():
    print("=" * 112)
    print("FROZEN CONFIG — M5 long-only extreme-bar fade, k=4.0, stop 2.0xATR, target +10R, hold 96h")
    print("next-bar-open fill | raw-account spread + $7/lot | pessimistic intrabar | 11 pairs")
    print("=" * 112)
    all_tr = []
    print(f"\n{'sym':<8}{'n(TEST)':>9}{'stopP':>8}{'cost%':>8}{'WR%':>7}{'E_net':>9}{'totalR':>9}")
    print("-" * 112)
    tot = 0.0
    n_all = 0
    for sym in SPECS:
        tr = build(sym)
        te = [t for t in tr if t.ets >= TRAIN_END]
        all_tr += te
        if not te:
            continue
        n = len(te)
        en = sum(t.R - t.cost_R for t in te) / n
        cost = sum(t.cost_R for t in te) / n
        stop = sum(t.stop_pips for t in te) / n
        wr = sum(1 for t in te if t.R - t.cost_R > 0) / n
        tot += en * n
        n_all += n
        print(f"{sym:<8}{n:>9}{stop:>8.2f}{cost*100:>8.1f}{wr*100:>7.1f}{en:>+9.4f}{en*n:>+9.0f}")
    print("-" * 112)
    print(f"{'AGGREGATE':<8}{n_all:>9}{'':>8}{sum(t.cost_R for t in all_tr)/len(all_tr)*100:>8.1f}"
          f"{'':>7}{tot/n_all:>+9.4f}{tot:>+9.0f}")
    print(f"\n  trades/day = {n_all/730:.2f}   R/day = {tot/730:+.3f}   "
          f"net expectancy = {tot/n_all:+.4f}R per trade")

    all_tr.sort(key=lambda t: (t.ets, t.sym))   # deterministic tie-break, matches build_trades()
    print("\n" + "=" * 112)
    print("WALK-FORWARD, HELD-OUT TEST WINDOW 2024-09-11 .. 2026-09-11 (40 rolling start dates)")
    print("=" * 112)
    print(f"{'risk%':>7}{'pass%':>8}{'medD':>6}{'p25':>5}{'p90':>5}{'best':>6}{'worst':>7}"
          f"{'maxDD%':>8}{'worstDay$':>11}{'dayLimit':>10}{'floorBust':>11}")
    print("-" * 112)
    for r in (0.0025, 0.005, 0.0075, 0.01):
        w = replay(all_tr, r)
        ok = "OK" if w["worst_day"] >= -(ACCOUNT * DAILY_LOSS) else "BREACH"
        print(f"{r*100:>7.2f}{w['pass_rate']*100:>8.1f}{w['med_days']:>6}{w['p25']:>5}"
              f"{w['p90']:>5}{w['best']:>6}{w['worst']:>7}{w['max_dd']*100:>8.1f}"
              f"{w['worst_day']:>11.0f}{ok:>10}{w['floor_busts']:>11}")
    print("\n  firm daily-loss boundary = 5% of $2,500 = $125.00;  equity floor = $2,250")
    print("  risk above ~0.75% breaches the daily-loss boundary and is therefore illegal.")


if __name__ == "__main__":
    main()
