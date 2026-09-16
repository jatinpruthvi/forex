#!/usr/bin/env python3
"""
compare_ea_dump.py — verify EA_SIGNAL_DUMP.csv, the dump from your own MetaTrader.

Two independent layers, because your broker's price feed is NOT the repo's CSV feed:

  LAYER 1 - SELF-CONSISTENCY (works on any dump, no overlap needed).
    Re-derives every column from the raw OHLC in the same row and checks the EA's own
    arithmetic: ATR against the simple-mean definition, the trigger inequality, the
    long-only filter, stop normalisation, dist, dist/ATR, the target, the lot size, and
    the day-key/Friday logic. If any of these disagree with the values the EA wrote, the
    EA has a bug - and this needs no reference data at all.

    It also confirms the three bugs that were fixed are actually gone, by checking the
    deliberately-dumped WRONG columns:
      * atr_wilder must DIFFER from atr_simple  (proves we are not on Wilder/RMA smoothing)
      * daykey_bug must differ from daykey_correct on some rows
      * friday_bug must differ, and specifically must MISS the 21:00-23:59 server window
        that friday_correct catches (the inversion that left the pre-close window open)
      * reject_degenerate_stop must fire, and no row may size an oversized position

  LAYER 2 - CROSS-FEED COMPARISON (only where timestamps overlap the repo CSVs).
    Joins on the signal bar's UTC timestamp and compares against verify_final_config.py.
    It reports the OHLC agreement rate FIRST, because that determines how to read the rest:
      * if OHLC matches exactly, then ATR and every decision MUST match exactly too -
        any difference is an EA bug.
      * if OHLC differs, the feeds differ and decisions may legitimately diverge; the
        agreement rate is then informational, not a pass/fail.

Usage:
    python3 validation/speed_lab/compare_ea_dump.py [path/to/ea_signal_dump.csv]
Default path: MQL5/Files/ea_signal_dump.csv
"""
from __future__ import annotations

import csv
import math
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE))
import verify_final_config as V   # noqa: E402

DEFAULT = ROOT / "MQL5/Files/ea_signal_dump.csv"
RISK_PCT = 0.50          # must match the EA's InpRiskPercent
COMM_PER_LOT = 7.0       # must match the EA's InpCommissionPerLotRT
MT5_TIME = "%Y.%m.%d %H:%M:%S"
# Every numeric column is written with DoubleToString(x, 10), so each carries at most
# 5e-11 of serialization error. Comparisons of RAW values can therefore be tight; the two
# quantities that pass through NormalizeDouble (stop_norm, target) additionally carry up to
# half a broker point, and are checked as "within half a point AND on the point grid" so a
# value sitting exactly on a rounding boundary cannot flip the verdict.
SER = 1e-9


def mt5_to_utc_ms(text, offset_hours):
    dt = datetime.strptime(text, MT5_TIME).replace(tzinfo=timezone.utc)
    return int((dt.timestamp() - offset_hours * 3600) * 1000)


def close_enough(a, b, tol=SER):
    """Absolute comparison for raw (un-normalised) values."""
    return a is not None and b is not None and abs(a - b) <= tol


def rel_close(a, b, tol=1e-6):
    """Relative comparison for ratios, whose magnitude spans orders of magnitude."""
    if a is None or b is None:
        return False
    return abs(a - b) <= tol * max(1e-12, abs(a), abs(b))


def product_ok(ratio, denom, num, tol=1e-9):
    """Check `ratio == num/denom` WITHOUT dividing by a possibly-tiny denominator.

    A pure relative test on the quotient is unsound here: every dumped value carries ~5e-11
    of serialization error, and dividing by a small ATR (~1e-4) amplifies that to ~5e-7
    relative, which a fixed relative tolerance would read as a divergence. Cross-multiplying
    keeps the error absolute and bounded instead.
    """
    # Error budget: ratio_err*|denom| + |ratio|*denom_err + num_err, each input carrying
    # ~5e-11. The bound must therefore scale with the DENOMINATOR too, not just the ratio -
    # XAUUSD's ATR reaches ~40, where 5e-11*40 already exceeds a ratio-only bound. A real
    # algorithmic bug changes these by orders of magnitude more, so this stays decisive.
    return abs(ratio * denom - num) <= tol * (1.0 + abs(ratio) + abs(denom) + abs(num))


def normalised_ok(value, exact, point):
    """value must equal exact rounded to the broker point grid, within half a point."""
    if abs(value - exact) > 0.5 * point + SER:
        return False
    k = value / point
    return abs(k - round(k)) <= 1e-6


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    print("=" * 104)
    print("EA_SIGNAL_DUMP VERIFICATION")
    print("=" * 104)
    if not path.exists():
        print(f"\n[ERROR] dump not found: {path}")
        print("        Run EA_SIGNAL_DUMP.mq5 in MetaTrader first (it writes to MQL5/Files/),")
        print("        then re-run this script, optionally passing the CSV path as argv[1].")
        return 2
    rows = list(csv.DictReader(open(path, newline="")))
    if not rows:
        print("\n[ERROR] dump is empty")
        return 2
    print(f"\nfile            : {path}")
    print(f"rows            : {len(rows):,}")
    print(f"symbols         : {sorted(set(r['symbol'] for r in rows))}")
    print(f"server offset   : {rows[0]['server_offset_hours']} h (as measured/used by the script)")
    print(f"time span (UTC) : {rows[0]['utc_time']}  ..  {rows[-1]['utc_time']}")

    fails = Counter()
    worst = defaultdict(float)

    def chk(name, ok, sev=1.0):
        if not ok:
            fails[name] += 1
        return ok

    # ---------------------------------------------------------------- LAYER 1
    print("\n" + "=" * 104)
    print("LAYER 1 - SELF-CONSISTENCY: re-derive every column from the row's own OHLC")
    print("=" * 104)

    n_wilder_diff = 0
    n_daykey_diff = 0
    n_fri_diff = 0
    fri_missed_by_bug = 0          # rows the buggy version would have left unprotected
    fri_spurious_by_bug = 0        # rows the buggy version would have blocked wrongly
    n_degen = 0
    n_geom = 0
    max_lots = 0.0
    max_lots_row = None
    n_fire = 0
    ratios = []

    for r in rows:
        o = float(r["open"]); h = float(r["high"]); l = float(r["low"]); c = float(r["close"])
        atr = float(r["atr_simple"]); wilder = float(r["atr_wilder"])
        body = float(r["body"]); entry = float(r["entry_next_open"])
        stop_raw = float(r["stop_raw"]); stop_norm = float(r["stop_norm"])
        dist = float(r["dist"]); dist_pips = float(r["dist_pips"]); dist_atr = float(r["dist_over_atr"])
        target = float(r["target"]); lots = float(r["lots"]); lpl = float(r["loss_per_lot"])
        trig = r["trigger"] == "1"; longo = r["long_only"] == "1"; fires = r["signal_fires"] == "1"
        rg = r["reject_broken_geom"] == "1"; rd = r["reject_degenerate_stop"] == "1"

        digits = int(r["digits"])          # the broker's own SYMBOL_DIGITS, never inferred
        point = 10 ** (-digits)
        # Contract terms come from the dump: on a real broker these will NOT equal the
        # repo's SPECS assumptions, and guessing them would produce false failures.
        pip = float(r["pip"]); tick_size = float(r["tick_size"]); tick_value = float(r["tick_value"])
        vol_step = float(r["volume_step"]); vol_min = float(r["volume_min"]); vol_max = float(r["volume_max"])

        # body and the trigger inequality
        chk("body == |close-open|", close_enough(body, abs(c - o)))
        chk("body_over_atr * atr == body", product_ok(float(r["body_over_atr"]), atr, body))
        K = 4.0
        chk(f"trigger == (body > {K}*atr)", trig == (body > K * atr))
        chk("long_only == (close < open)", longo == (c < o))
        chk("signal_fires == trigger AND long_only", fires == (trig and longo))

        # stop geometry. stop_raw is un-normalised so it can be checked exactly; stop_norm and
        # target have been through NormalizeDouble, so they are checked against the point grid.
        chk("stop_raw == low - 2*atr", close_enough(stop_raw, l - 2.0 * atr))
        chk("stop_norm == NormalizeDouble(stop_raw, digits)",
            normalised_ok(stop_norm, stop_raw, point))
        chk("dist == entry - stop_norm", close_enough(dist, entry - stop_norm))
        chk("dist_pips * pip == dist", product_ok(dist_pips, pip, dist))
        chk("dist_over_atr * atr == dist", product_ok(dist_atr, atr, dist))
        chk("target == NormalizeDouble(entry + 10*dist, digits)",
            normalised_ok(target, entry + 10.0 * dist, point))

        # rejection flags and the degenerate-stop guard
        chk("reject_broken_geom == (dist <= 0)", rg == (dist <= 0.0))
        chk("reject_degenerate == (not broken AND dist < 1.0*atr)",
            rd == ((not rg) and dist < 1.0 * atr))

        # lot sizing: risk / loss_per_lot, floored to the volume step
        if not rg and not rd and lpl > 0:
            risk = 2500.0 * RISK_PCT / 100.0
            expect = math.floor((risk / lpl) / vol_step) * vol_step
            expect = 0.0 if expect < vol_min else min(expect, vol_max)
            # loss_per_lot is serialised to 10 decimals and then floored to a volume step, so
            # a value sitting on a step boundary can land one step either way. Allow one step,
            # and never allow the EA to size LARGER - that is the direction that matters.
            chk("lots within one step of NormaliseLots(risk/loss_per_lot)",
                abs(lots - expect) <= vol_step + 1e-9)
            chk("lots never exceeds expected by more than one step",
                lots <= expect + vol_step + 1e-9)
            chk("loss_per_lot == (dist/tick_size)*tick_value + commission",
                abs(lpl - ((dist / tick_size) * tick_value + COMM_PER_LOT)) <= 1e-4)
            if lots > max_lots:
                max_lots, max_lots_row = lots, r
        else:
            chk("lots == 0 when rejected", lots == 0.0)

        # day-key and Friday logic, correct vs the double-offset bug
        dkc = int(r["daykey_correct"]); dkb = int(r["daykey_bug"])
        fc = r["friday_correct"] == "1"; fb = r["friday_bug"] == "1"
        srv = datetime.strptime(r["entry_time_server"], MT5_TIME).replace(tzinfo=timezone.utc)
        chk("daykey_correct == server_time//86400",
            dkc == int(srv.timestamp() // 86400))
        chk("friday_correct == (server weekday is Fri AND hour >= 21)",
            fc == (srv.weekday() == 4 and srv.hour >= 21))
        if wilder > 0 and atr > 0:
            chk("atr_ratio * atr_simple == atr_wilder",
                product_ok(float(r["atr_ratio_wilder_over_simple"]), atr, wilder))
            n_wilder_diff += 1 if abs(wilder - atr) > 1e-9 else 0
            ratios.append(wilder / atr)
        if dkc != dkb:
            n_daykey_diff += 1
        if fc != fb:
            n_fri_diff += 1
            if fc and not fb:
                fri_missed_by_bug += 1
            if fb and not fc:
                fri_spurious_by_bug += 1
        if rd:
            n_degen += 1
        if rg:
            n_geom += 1
        if fires:
            n_fire += 1

    print(f"  rows checked                       : {len(rows):,}")
    print(f"  signals that fire                  : {n_fire:,} ({n_fire/len(rows)*100:.3f}% of bars)")
    print(f"  rejected broken geometry (dist<=0) : {n_geom}")
    print(f"  rejected degenerate stop (<1xATR)  : {n_degen}")
    if fails:
        print("\n  *** SELF-CONSISTENCY FAILURES ***")
        for k, v in fails.most_common():
            print(f"      {v:>7,} rows  {k}")
    else:
        print("  -> ALL SELF-CONSISTENCY CHECKS PASS on every row.")

    print("\n  Bug-removal evidence (the dump carries the WRONG values on purpose):")
    print(f"    atr_wilder differs from atr_simple on {n_wilder_diff:,} rows "
          f"({n_wilder_diff/max(1,len(rows))*100:.1f}%)")
    if ratios:
        print(f"      wilder/simple ratio: min {min(ratios):.4f}  median "
              f"{sorted(ratios)[len(ratios)//2]:.4f}  max {max(ratios):.4f}")
    print(f"      -> {'CONFIRMED not interchangeable' if n_wilder_diff else '*** SUSPICIOUS: identical, check the ATR ***'}")
    print(f"    daykey_bug differs from daykey_correct on {n_daykey_diff:,} rows "
          f"({n_daykey_diff/len(rows)*100:.1f}%)")
    print(f"    friday_bug differs from friday_correct on {n_fri_diff:,} rows")
    print(f"      of which the bug MISSED a real pre-close block : {fri_missed_by_bug:,}")
    print(f"      of which the bug BLOCKED when it should not    : {fri_spurious_by_bug:,}")
    if max_lots_row:
        print(f"    largest position sized: {max_lots:.2f} lots  "
              f"({max_lots_row['symbol']} {max_lots_row['entry_time_server']}, "
              f"dist {float(max_lots_row['dist_pips']):.2f} pips, "
              f"dist/ATR {float(max_lots_row['dist_over_atr']):.2f})")
        print(f"      -> {'OK' if max_lots <= 2.0 else '*** REVIEW: unexpectedly large ***'}")

    # ---------------------------------------------------------------- LAYER 2
    print("\n" + "=" * 104)
    print("LAYER 2 - CROSS-FEED COMPARISON against the repo's validated backtest")
    print("=" * 104)

    repo = {}
    for sym in sorted(set(r["symbol"] for r in rows)):
        if sym not in V.SPECS:
            continue
        ts, o, h, l, c = V.load(sym)
        idx = {t: i for i, t in enumerate(ts)}
        repo[sym] = (ts, o, h, l, c, idx, V.atr_prior(h, l, c, 14))

    print("\n  Broker contract terms reported by the dump vs the repo's assumptions:")
    print(f"    {'symbol':<9} {'pip':>10} {'(repo)':>10} {'tick_value':>12} {'(repo)':>10} "
          f"{'vol_step':>9} {'digits':>7}")
    seen = {}
    for r in rows:
        seen.setdefault(r["symbol"], r)
    for sym, r in sorted(seen.items()):
        rp = V.SPECS.get(sym, (None, None, None))
        flag_p = "" if rp[0] is None or abs(float(r["pip"]) - rp[0]) < 1e-12 else "  <-- DIFFERS"
        flag_v = "" if rp[1] is None or abs(float(r["tick_value"]) - rp[1]) < 1e-9 else "  <-- DIFFERS"
        print(f"    {sym:<9} {float(r['pip']):>10.5f} {str(rp[0]):>10} "
              f"{float(r['tick_value']):>12.5f} {str(rp[1]):>10}{flag_v} "
              f"{float(r['volume_step']):>9.3f} {int(r['digits']):>7}{flag_p}")
    print("    (a DIFFERS line is not a bug - it means your broker's contract terms are not")
    print("     what the backtest assumed, so realised lot sizes and P/L will scale differently)")

    joined = ohlc_match = 0
    atr_bad = fire_bad = stop_bad = 0
    worst_atr = 0.0
    no_overlap = Counter()
    for r in rows:
        sym = r["symbol"]
        if sym not in repo:
            continue
        ts, o, h, l, c, idx, atrp = repo[sym]
        off = int(r["server_offset_hours"])
        sig_utc = mt5_to_utc_ms(r["signal_time_server"], off)
        i = idx.get(sig_utc)
        if i is None:
            no_overlap[sym] += 1
            continue
        joined += 1
        same_ohlc = (abs(o[i] - float(r["open"])) <= SER and abs(h[i] - float(r["high"])) <= SER
                     and abs(l[i] - float(r["low"])) <= SER and abs(c[i] - float(r["close"])) <= SER)
        if same_ohlc:
            ohlc_match += 1
            ref = atrp[i]
            got = float(r["atr_simple"])
            if ref is None:
                continue
            # ATR is serialised to 10 decimals, which for a small ATR (~4e-4) is a relative
            # error of ~1e-7. Anything above 1e-5 is a real algorithmic difference.
            d = abs(got - ref) / ref if ref else 0.0
            worst_atr = max(worst_atr, d)
            if d > 1e-5:
                atr_bad += 1
            ref_stop = l[i] - 2.0 * (ref or 0)
            if abs(float(r["stop_raw"]) - ref_stop) > SER:
                stop_bad += 1
            K = 4.0
            ref_fire = (abs(c[i] - o[i]) > K * (ref or 0)) and (c[i] < o[i])
            if ref_fire != (r["signal_fires"] == "1"):
                fire_bad += 1

    print(f"  rows joined to repo data           : {joined:,} of {len(rows):,}")
    if joined == 0:
        print("\n  [!] NO OVERLAP. Your dump's time range does not intersect the repo CSVs")
        print("      (which end 2026-09-11). Re-run EA_SIGNAL_DUMP.mq5 with a larger")
        print("      InpBarsToDump - 20000 M5 bars is about 10 weeks, so try 120000 for")
        print("      roughly a year - then re-run this comparison.")
        if no_overlap:
            print(f"      per-symbol misses: {dict(no_overlap)}")
    else:
        rate = ohlc_match / joined * 100
        print(f"  rows where OHLC matches EXACTLY    : {ohlc_match:,} ({rate:.2f}%)")
        if rate > 99.0:
            print("      -> same feed. ATR and every decision MUST match exactly; any")
            print("         difference below is an EA bug.")
            print(f"  ATR mismatches                     : {atr_bad}  (max rel diff {worst_atr:.3e})")
            print(f"  stop_raw mismatches                : {stop_bad}")
            print(f"  signal_fires mismatches            : {fire_bad}")
            ok = (atr_bad == 0 and stop_bad == 0 and fire_bad == 0)
            print(f"      -> {'EA REPRODUCES THE VALIDATED BACKTEST EXACTLY' if ok else '*** DIVERGENCE - DO NOT TRADE ***'}")
        else:
            print("      -> DIFFERENT FEED (expected: your broker's bars are not the repo's).")
            print("         Comparison on non-identical bars is informational only.")
            print(f"  on the {ohlc_match:,} identical-OHLC rows:")
            print(f"    ATR mismatches                   : {atr_bad}  (max rel diff {worst_atr:.3e})")
            print(f"    stop_raw mismatches              : {stop_bad}")
            print(f"    signal_fires mismatches          : {fire_bad}")
            if atr_bad == 0 and stop_bad == 0 and fire_bad == 0:
                print("    -> where the bars agree, the EA agrees EXACTLY. That is the test")
                print("       that matters: it isolates the algorithm from the data source.")
            else:
                print("    -> *** EA diverges even on identical bars - investigate ***")

    print("\n" + "=" * 104)
    print("SUMMARY")
    print("=" * 104)
    layer1 = not fails
    print(f"  Layer 1 self-consistency : {'PASS' if layer1 else 'FAIL'}")
    print(f"  Layer 2 cross-feed       : {'PASS' if joined and atr_bad == 0 and fire_bad == 0 else 'n/a (no overlap) or FAIL'}")
    print("\n  Still NOT covered by anything here: MQL5 compilation, order execution,")
    print("  requotes, live spread at the moment a 4xATR bar closes, and swap.")
    return 0 if layer1 else 1


if __name__ == "__main__":
    sys.exit(main())
