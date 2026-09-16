#!/usr/bin/env python3
"""
selftest_ea_dump.py — self-test for EA_SIGNAL_DUMP.mq5 + compare_ea_dump.py.

You cannot run MetaTrader here, so this generates a SYNTHETIC dump from the repo's own M5
data in exactly the column format EA_SIGNAL_DUMP.mq5 writes, then runs compare_ea_dump.py
against it. That validates the whole verification chain end to end:

  * Layer 1 (self-consistency) must PASS - proving the formulas the EA implements are
    internally coherent and that the comparator checks them correctly.
  * Layer 2 must report 100% OHLC agreement and ZERO divergences - because the synthetic
    dump is built from the same data, so this is the "same feed" branch, the strict one.
  * The bug-removal evidence must be non-trivial: atr_wilder must differ from atr_simple,
    daykey_bug must differ from daykey_correct, friday_bug must differ and specifically
    MISS the real 21:00-23:59 pre-close window, and degenerate stops must be flagged.

If any of those is vacuous, the comparator would pass on a broken EA, which is exactly the
failure mode that let the double-offset bug through the first time.

Usage:  python3 validation/speed_lab/selftest_ea_dump.py
"""
from __future__ import annotations

import csv
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE))
import verify_final_config as V                     # noqa: E402
from ea_emulator import digits_of                   # noqa: E402

OUT = HERE / "selftest_dump.csv"
OFFSET_H = 3
OFFSET_S = OFFSET_H * 3600
K, SA, TR, NEED, MINSA = 4.0, 2.0, 10.0, 14, 1.0
RISK, BASE, COMM = 0.50, 2500.0, 7.0
FRI_CUT = 21

HEADER = ["symbol", "digits", "shift", "signal_time_server", "entry_time_server", "utc_time",
          "server_offset_hours", "open", "high", "low", "close", "atr_simple", "atr_wilder",
          "atr_ratio_wilder_over_simple", "body", "body_over_atr", "trigger", "long_only",
          "signal_fires", "pip", "tick_size", "tick_value", "volume_step", "volume_min",
          "volume_max", "entry_next_open", "stop_raw", "stop_norm", "dist", "dist_pips",
          "dist_over_atr", "reject_broken_geom", "reject_degenerate_stop", "target", "lots",
          "loss_per_lot", "daykey_correct", "daykey_bug", "friday_correct", "friday_bug"]


def real_digits(closes, sample=2000):
    """Decimals actually carried by the data - what SYMBOL_DIGITS would report."""
    d = 0
    for x in closes[:sample]:
        s = repr(float(x))
        if "." in s:
            d = max(d, len(s.split(".")[1].rstrip("0")) if s.split(".")[1].rstrip("0") else 0)
    return d


def wilder_atr(h, l, c, period=14):
    """MT5 iATR: true-range RMA (Wilder smoothing). Deliberately NOT what the EA uses."""
    n = len(c)
    tr = [0.0] * n
    for i in range(n):
        pc = c[i - 1] if i else c[0]
        tr[i] = max(h[i] - l[i], abs(h[i] - pc), abs(l[i] - pc))
    out = [None] * n
    if n < period:
        return out
    seed = sum(tr[1:period + 1]) / period
    out[period] = seed
    prev = seed
    for i in range(period + 1, n):
        prev = (prev * (period - 1) + tr[i]) / period
        out[i] = prev
    return out


def srv(t_ms, extra=0):
    return datetime.fromtimestamp(t_ms / 1000 + OFFSET_S + extra, tz=timezone.utc)


def build(symbols, max_rows_per_symbol):
    rows = []
    for sym in symbols:
        ts, o, h, l, c = V.load(sym)
        atrp = V.atr_prior(h, l, c, NEED)
        wild = wilder_atr(h, l, c, NEED)
        _pip_spec, pv, _ = V.SPECS[sym]
        # decimals actually present in the repo CSV - digits_of(pip) is only an approximation
        # and is WRONG for XAUUSD (pip 0.10 implies 2, the data carries 3). Read the real
        # precision from the file so the synthetic dump matches what a broker would report.
        dig = real_digits(c)
        # pip exactly the way the MQL5 script derives it: from the broker's digit count,
        # NOT from the repo's SPECS table (they disagree for XAUUSD - worth surfacing).
        pip = 10.0 ** (-dig) * 10.0
        tick_size, tick_value = pip, pv
        vol_step, vol_min, vol_max = 0.01, 0.01, 100.0
        n = len(c)
        start = max(NEED + 2, n - max_rows_per_symbol)
        for i in range(start, n - 1):
            a = atrp[i]
            w = wild[i]
            if not a or a <= 0:
                continue
            body = abs(c[i] - o[i])
            trig = body > K * a
            longo = c[i] < o[i]
            fires = trig and longo
            entry = o[i + 1]
            stop_raw = l[i] - SA * a
            stop_norm = round(stop_raw, dig)
            dist = entry - stop_norm
            rej_g = dist <= 0.0
            rej_d = (not rej_g) and dist < MINSA * a
            target = round(entry + TR * dist, dig)
            lpl = (dist / pip) * pv + COMM
            if rej_g or rej_d or lpl <= 0:
                lots = 0.0
            else:
                lots = int((BASE * RISK / 100.0 / lpl) / 0.01) * 0.01
                if lots < 0.01:
                    lots = 0.0
            s_now = srv(ts[i + 1])
            s_bug = srv(ts[i + 1], OFFSET_S)
            rows.append({
                "symbol": sym, "digits": dig, "shift": n - 1 - i,
                "signal_time_server": srv(ts[i]).strftime("%Y.%m.%d %H:%M:%S"),
                "entry_time_server": s_now.strftime("%Y.%m.%d %H:%M:%S"),
                "utc_time": datetime.fromtimestamp(ts[i + 1] / 1000, tz=timezone.utc)
                              .strftime("%Y.%m.%d %H:%M:%S"),
                "server_offset_hours": OFFSET_H,
                "open": f"{o[i]:.10f}", "high": f"{h[i]:.10f}",
                "low": f"{l[i]:.10f}", "close": f"{c[i]:.10f}",
                "atr_simple": f"{a:.10f}", "atr_wilder": f"{(w or 0.0):.10f}",
                "atr_ratio_wilder_over_simple": f"{(w / a if w else 0.0):.10f}",
                "body": f"{body:.10f}", "body_over_atr": f"{body / a:.10f}",
                "trigger": int(trig), "long_only": int(longo), "signal_fires": int(fires),
                "pip": f"{pip:.10f}", "tick_size": f"{tick_size:.10f}",
                "tick_value": f"{tick_value:.10f}", "volume_step": f"{vol_step:.10f}",
                "volume_min": f"{vol_min:.10f}", "volume_max": f"{vol_max:.10f}",
                "entry_next_open": f"{entry:.10f}",
                "stop_raw": f"{stop_raw:.10f}", "stop_norm": f"{stop_norm:.10f}",
                "dist": f"{dist:.10f}", "dist_pips": f"{dist / pip:.10f}",
                "dist_over_atr": f"{dist / a:.10f}",
                "reject_broken_geom": int(rej_g), "reject_degenerate_stop": int(rej_d),
                "target": f"{target:.10f}", "lots": f"{lots:.10f}",
                "loss_per_lot": f"{lpl:.10f}",
                "daykey_correct": int(s_now.timestamp() // 86400),
                "daykey_bug": int(s_bug.timestamp() // 86400),
                "friday_correct": int(s_now.weekday() == 4 and s_now.hour >= FRI_CUT),
                "friday_bug": int(s_bug.weekday() == 4 and s_bug.hour >= FRI_CUT),
            })
    return rows


def extract_fn(src, sig):
    """Pull one whole function body out of an MQL5 source file by brace matching."""
    i = src.index(sig)
    j = src.index("{", i)
    d = 0
    for k in range(j, len(src)):
        if src[k] == "{":
            d += 1
        elif src[k] == "}":
            d -= 1
            if d == 0:
                return src[i:k + 1]
    raise AssertionError("unbalanced braces after " + sig)


def strip_noise(code):
    """Compare MQL5 semantically: comments and whitespace carry no behaviour."""
    code = re.sub(r"//[^\n]*", "", code)
    return re.sub(r"\s+", " ", code).strip()


def layer0_verbatim():
    """The dump claims to copy the EA's functions VERBATIM. Verify that mechanically -
    a copy that has silently drifted makes every comparison below meaningless."""
    ea = (ROOT / "MQL5/Experts/FIVE_M5_EXHAUST/FIVE_M5_EXHAUST.mq5").read_text()
    du = (ROOT / "MQL5/Scripts/EA_SIGNAL_DUMP.mq5").read_text()
    drift = []
    for sig in ["bool SimpleAtrBefore(", "double LossPerLot(",
                "double NormaliseLots(", "int ServerDayKey("]:
        if strip_noise(extract_fn(ea, sig)) != strip_noise(extract_fn(du, sig)):
            drift.append(sig)
    return drift


def main():
    syms = ["EURGBP", "USDCHF", "NZDUSD", "XAUUSD", "USDJPY"]
    print("=" * 100)
    print("SELF-TEST: synthetic EA_SIGNAL_DUMP -> compare_ea_dump.py")
    print("=" * 100)

    print("\nLAYER 0 - the dump's function copies must still BE the EA's")
    drift = layer0_verbatim()
    for sig in ["bool SimpleAtrBefore(", "double LossPerLot(",
                "double NormaliseLots(", "int ServerDayKey("]:
        print(f"  [{'IDENTICAL' if sig not in drift else '*** DRIFTED ***':>17}]  {sig}")
    assert not drift, f"EA_SIGNAL_DUMP.mq5 has drifted from the EA: {drift}"
    print("  -> all four copies are semantically identical to FIVE_M5_EXHAUST.mq5")
    rows = build(syms, 40_000)
    with open(OUT, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=HEADER)
        w.writeheader()
        w.writerows(rows)
    print(f"\nwrote {len(rows):,} rows for {syms} -> {OUT.relative_to(ROOT)}")

    # non-vacuity of the bug evidence, computed here so we can assert on it
    wd = sum(1 for r in rows if abs(float(r["atr_wilder"]) / float(r["atr_simple"]) - 1) > 1e-9)
    dk = sum(1 for r in rows if r["daykey_correct"] != r["daykey_bug"])
    fb = sum(1 for r in rows if r["friday_correct"] != r["friday_bug"])
    missed = sum(1 for r in rows if r["friday_correct"] == 1 and r["friday_bug"] == 0)
    spur = sum(1 for r in rows if r["friday_correct"] == 0 and r["friday_bug"] == 1)
    degen = sum(1 for r in rows if r["reject_degenerate_stop"] == 1)
    geom = sum(1 for r in rows if r["reject_broken_geom"] == 1)
    print("\nexpected non-vacuity in the synthetic dump:")
    print(f"  atr_wilder != atr_simple      : {wd:,} rows  {'OK' if wd else '*** VACUOUS ***'}")
    print(f"  daykey_correct != daykey_bug  : {dk:,} rows  {'OK' if dk else '*** VACUOUS ***'}")
    print(f"  friday differs                : {fb:,} rows  (missed {missed:,}, spurious {spur:,})")
    print(f"  degenerate-stop rejections    : {degen:,}")
    print(f"  broken-geometry rejections    : {geom:,}")
    assert wd and dk and fb and missed, "the bug evidence is vacuous - the test would pass on a broken EA"
    print("  -> all four bug-evidence signals are non-vacuous")

    print("\n" + "-" * 100)
    print("running compare_ea_dump.py against it")
    print("-" * 100)
    r = subprocess.run([sys.executable, str(HERE / "compare_ea_dump.py"), str(OUT)],
                       capture_output=True, text=True)
    print(r.stdout)
    if r.stderr.strip():
        print("STDERR:", r.stderr[-2000:])
    clean_ok = (r.returncode == 0 and "ALL SELF-CONSISTENCY CHECKS PASS" in r.stdout
                and "EXACTLY" in r.stdout and "*** " not in r.stdout)

    # ---------------------------------------------------------------- MUTATION CONTROL
    # A comparator that cannot fail is worse than no comparator: the first EA audit passed a
    # gate test that was vacuous and let a real double-offset bug through. So corrupt the dump
    # in the exact ways a buggy EA would, and require the comparator to catch every one.
    print("\n" + "-" * 100)
    print("MUTATION CONTROL: the comparator must FAIL on a deliberately broken dump")
    print("-" * 100)
    import copy

    def mutate(rows, fn):
        out = copy.deepcopy(rows)
        for r in out:
            fn(r)
        return out

    MUTATIONS = [
        ("ATR swapped to Wilder smoothing",
         lambda r: r.update(atr_simple=r["atr_wilder"])),
        ("trigger threshold 4x -> 3x ATR",
         lambda r: r.update(trigger=int(float(r["body"]) > 3.0 * float(r["atr_simple"])))),
        ("stop uses 1x ATR instead of 2x",
         lambda r: r.update(stop_raw=f"{float(r['low']) - float(r['atr_simple']):.10f}")),
        ("stop normalised to the wrong digit count",
         lambda r: r.update(stop_norm=f"{round(float(r['stop_raw']), max(0, int(r['digits']) - 1)):.10f}")),
        ("target uses +9R instead of +10R",
         lambda r: r.update(target=f"{round(float(r['entry_next_open']) + 9.0 * float(r['dist']), int(r['digits'])):.10f}")),
        ("lot size doubled",
         lambda r: r.update(lots=f"{float(r['lots']) * 2:.10f}") if float(r["lots"]) > 0 else None),
        # rows still hold native ints here (the CSV round-trip is what turns them into
        # strings), so compare numerically - a string comparison silently never fires.
        ("degenerate-stop guard disabled",
         lambda r: r.update(reject_degenerate_stop=0) if int(r["reject_degenerate_stop"]) == 1 else None),
        ("Friday block reverts to the pre-fix double-offset bug",
         lambda r: r.update(friday_correct=r["friday_bug"])),
        ("day key reverts to the pre-fix double-offset bug",
         lambda r: r.update(daykey_correct=r["daykey_bug"])),
    ]
    caught = 0
    inert = []
    for name, fn in MUTATIONS:
        m = mutate(rows, fn)
        changed = sum(1 for a, b in zip(rows, m) if a != b)
        if changed == 0:
            inert.append(name)
        with open(OUT, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=HEADER); w.writeheader(); w.writerows(m)
        rr = subprocess.run([sys.executable, str(HERE / "compare_ea_dump.py"), str(OUT)],
                            capture_output=True, text=True)
        bad = ("*** SELF-CONSISTENCY FAILURES ***" in rr.stdout or rr.returncode != 0
               or "EXACTLY" not in rr.stdout)
        caught += bad
        print(f"  [{'CAUGHT' if bad else 'MISSED ***'}]  {name}   ({changed:,} rows altered)")

    # restore the clean dump
    with open(OUT, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=HEADER); w.writeheader(); w.writerows(rows)

    print(f"\n  mutations caught: {caught}/{len(MUTATIONS)}")
    if inert:
        print(f"  *** INERT MUTATIONS (never altered a row, so they prove nothing): {inert}")
    ok = clean_ok and caught == len(MUTATIONS) and not inert
    print("=" * 100)
    print(f"SELF-TEST {'PASS' if ok else 'FAIL'}")
    print("=" * 100)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
