"""
External ORB+M1 strategy — review of the /home/ubuntu/forex suggestion
(2026-09-13)
=======================================================================
Spec under test (verbatim from the suggestion):
  Instruments/sessions: GBPJPY London, EURJPY London, XAUUSD New York.
  1. 6-candle M5 opening range (first 6 M5 bars of the session).
  2. Breakout only when the breakout candle has body >= 35% of its range
     and close aligned with the breakout direction.
  3. M1 confirmation: preceding 12-minute M1 slope positive (long) /
     negative (short).
  4. Stop distance >= 10 pips.
  5. 0.50 ATR stop.  6. 1.5R target.
  7. One account-wide position.  8. Max 2 trades/day.
  9. Spread+commission costs.  10. Daily/total floor governors.

Assumptions (theirs unspecified; documented for the audit):
  * Session start: London 07:00, NY 13:30 London wall (repo WINDOWS[1]).
  * "First M5 close beyond the opening range" is THE breakout candle;
    if it fails the body/close/M1 filters, no trade that day.
  * Entry: MARKET at the open of the bar after the breakout candle
    (signal known at its close).
  * 0.5 ATR stop measured from the entry fill, ATR = the repo's daily
    warm M15 ATR (same map the certified stack uses).
  * No time-stop specified -> flat at session end (11:00 / 16:00 London).
  * M1 data exists only 2024-09-11 -> 2026-09-11 (git 578da08); earlier
    dates produce no signal (reported, not approximated).
  * Their capped-compounding sizing (min(0.4% equity, $12.50)) is a
    ~0.4%-risk product — reported as a sizing sensitivity only; the
    combination test uses the certified stack's 1.75% sizing.

Tests (same honesty engine + one-slot combo loop):
  A. standalone 2y (real M1): coin + stop-first, 1.5% fixed base
  B. standalone 4y (M1 only from 2024-09): coin + stop-first (descriptive)
  C. COMBINATION with the certified per-pair 5-pair stack + gold:
     2y gate (real M1) -> 4y confirmation (external active only in the
     M1 window), coin + stop-first, vs $3,289.33 / $3,811.34.

Usage:  python tools/external_orb.py --run
"""
from __future__ import annotations

import argparse
import csv
import os
import sys
import time
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, os.path.abspath("."))
import tools.aggressive_optimizer as m      # noqa: E402
import tools.optimizer_v2 as v2             # noqa: E402
import tools.order_selector as osel         # noqa: E402
import tools.sr_pa_lab as L                 # noqa: E402

M1_DIR = Path("/home/user/.cache/m1/validation/HistoryData/m1-data")
SESSIONS = {"GBPJPY": (7, 0, 11, 0), "EURJPY": (7, 0, 11, 0),
            "XAUUSD": (13, 30, 16, 0)}
SYMS = list(SESSIONS)
FIVE = timedelta(minutes=5)
_NO_TS = 99996            # minutes — effectively no time-stop (their spec)


def load_m1(sym):
    """{london_date: [Bar]} for the session window (M1, ts in seconds)."""
    sh, _, eh, em = SESSIONS[sym]
    path = next(M1_DIR.glob(f"{sym.lower()}-m1-*.csv"))
    by_date: dict = defaultdict(list)
    with open(path, newline="") as f:
        rdr = csv.reader(f)
        next(rdr)
        for row in rdr:
            try:
                ts = int(row[0]) // 1000
            except ValueError:
                continue
            dt = datetime.fromtimestamp(ts, tz=timezone.utc)
            d = m.to_london_date(dt)
            ws = m.lw_utc(d, sh - 1, 30).timestamp()
            we = m.lw_utc(d, eh, em).timestamp()
            if ws <= ts < we:
                by_date[d].append(m.Bar(
                    datetime.fromtimestamp(ts, tz=timezone.utc),
                    float(row[1]), float(row[2]), float(row[3]),
                    float(row[4])))
    out = {d: rs for d, rs in by_date.items()}
    return out


def make_detector(m1):
    def det(day_bars, ref_s, ref_e, ent_s, ent_e, atr, sym, **kw):
        if sym not in SESSIONS or atr <= 0:
            return None
        d = m.to_london_date(day_bars[0].ts)
        m1d = m1.get(sym, {}).get(d)
        if not m1d:
            return None                      # no M1 for this date
        sh, sm_, eh, em = SESSIONS[sym]
        s_start = m.lw_utc(d, sh, sm_)
        s_end = m.lw_utc(d, eh, em)
        win = [b for b in day_bars if s_start <= b.ts < s_end]
        if len(win) < 7:
            return None
        or_h = max(b.high for b in win[:6])
        or_l = min(b.low for b in win[:6])
        for b in win[6:]:
            side = None
            if b.close > or_h:
                side = "long"
            elif b.close < or_l:
                side = "short"
            if side is None:
                continue
            # ---- THE breakout candle: filters must all pass ----
            rng = b.high - b.low
            if rng <= 0:
                return None
            body = abs(b.close - b.open)
            if body / rng < 0.35:
                return None
            if (side == "long" and b.close <= b.open) or \
               (side == "short" and b.close >= b.open):
                return None
            lo_t = b.ts - timedelta(minutes=12)
            pre = [x for x in m1d if lo_t <= x.ts < b.ts]
            if len(pre) < 10:
                return None
            slope = pre[-1].close - pre[0].close
            if side == "long" and slope <= 0:
                return None
            if side == "short" and slope >= 0:
                return None
            entry = b.close                   # market fill next bar open
            stop = entry - 0.5 * atr if side == "long" \
                else entry + 0.5 * atr
            spec = m.SPECS[sym]
            if abs(entry - stop) / spec["pip"] < 10:
                return None
            return dict(side=side, entry=entry, stop=stop,
                        sig_ts=b.ts + FIVE,
                        extreme=b.low if side == "long" else b.high,
                        body_ratio=body / rng, wick_ratio=0.5,
                        sweep_atr=0.2,
                        end_utc=s_end,        # own session end (NY XAU)
                        ts=_NO_TS,            # no time-stop (their spec)
                        mode="market")        # break-and-enter, next open
        return None
    return det


def _standalone(cache, m1, amb, risk):
    osel.EXTRA_DETECTORS.clear()
    det = make_detector(m1)
    osel.EXTRA_DETECTORS.append(("ext-orb",
                                 lambda *a, **k: det(*a, **k)))
    osel.TRIA_UNIVERSE = [(1, s, 0) for s in SYMS]
    osel.PAIR_CFG = {s: {"sweep": 99.0} for s in SYMS}   # primary off
    osel.RISK_TRIAD = risk
    osel.COMPOUND = False
    osel.TR_SIG_HOURS = None
    r = osel.run_combo(cache, "P0", theta=0.0, ambiguity=amb,
                       challenge=True, gold_off=True)
    osel.EXTRA_DETECTORS.clear()
    return r


def _combo(cache, m1, amb, with_ext, risk):
    osel.PAIR_CFG = {s: dict(c) for s, c in osel.PAIRFIT_ASSIGN.items()}
    osel.TRIA_UNIVERSE = [(1, s, 0) for s in osel.PAIRFIT_ASSIGN]
    osel.TR_SIG_HOURS = None
    osel.RISK_TRIAD = risk
    osel.COMPOUND = True
    osel.EXTRA_DETECTORS.clear()
    if with_ext:
        det = make_detector(m1)
        osel.EXTRA_DETECTORS.append(
            ("ext-orb", lambda *a, **k: det(*a, **k)))
    r = osel.run_combo(cache, "P0", theta=0.0, ambiguity=amb,
                       challenge=True)
    osel.EXTRA_DETECTORS.clear()
    return r


def show(r, label):
    p1 = f"{r['p1_days']}d" if r["p1"] else ("HALT" if r["halted"] else "NO")
    legs = " ".join(f"{k}:{v[0]}/{v[1]:+.0f}"
                    for k, v in r["per_leg"].items())
    print(f"  {label:<34} n={r['n']:>3} PF={r['pf']:5.2f} "
          f"${r['total']:>8.2f} CAGR={r['cagr']:>5.1f}% DD={r['dd']:>5.1f}% "
          f"P1={p1:>5} | {legs}", flush=True)


def run():
    import tools.triad_honest as th
    osel.set_geometry(False)
    th.tsb_STOP = None
    th.tsb.STOP_BUFFER_ATR = L.BUF
    print("loading M1 (3 symbols)...")
    t0 = time.time()
    m1 = {s: load_m1(s) for s in SYMS}
    for s in SYMS:
        ds = sorted(m1[s])
        print(f"  M1 {s}: {len(ds)} days {ds[0]} -> {ds[-1]}")
    print(f"({time.time() - t0:.0f}s)\n")

    c2 = v2.load_cache(v2.DATA_2Y)
    c4 = v2.load_cache(v2.DATA_4Y)

    print("=== A) EXTERNAL STRATEGY STANDALONE, 2y (real M1), 1.5% fixed ===")
    show(_standalone(c2, m1, "coin", 0.015), "A1 2y coin")
    show(_standalone(c2, m1, "stop", 0.015), "A2 2y stop-first")

    print("\n=== B) STANDALONE 4y (M1 only from 2024-09; earlier = no sig) ===")
    show(_standalone(c4, m1, "coin", 0.015), "B1 4y coin")
    show(_standalone(c4, m1, "stop", 0.015), "B2 4y stop-first")

    print("\n=== B3) sizing sensitivity: their capped-compounding ~= 0.4% ===")
    show(_standalone(c2, m1, "coin", 0.004), "B3 2y coin @0.4%")
    show(_standalone(c2, m1, "stop", 0.004), "B4 2y stop @0.4%")

    print("\n=== C) COMBINATION with certified per-pair stack (1.75/3.0, "
          "compound, gold) ===")
    show(_combo(c2, m1, "coin", False, 0.0175), "C1 2y base (expect 3289.33)")
    show(_combo(c2, m1, "coin", True, 0.0175), "C2 2y base + external")
    show(_combo(c2, m1, "stop", True, 0.0175), "C3 2y base + ext stop-first")
    show(_combo(c4, m1, "coin", False, 0.0175), "C4 4y base (expect 3811.34)")
    show(_combo(c4, m1, "coin", True, 0.0175), "C5 4y base + external")
    show(_combo(c4, m1, "stop", True, 0.0175), "C6 4y base + ext stop-first")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", action="store_true")
    args = ap.parse_args()
    if not args.run:
        ap.print_help()
        return
    run()


if __name__ == "__main__":
    main()
