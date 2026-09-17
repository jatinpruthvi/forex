#!/usr/bin/env python3
"""
test_ea_server_offset.py — round-5 audit: broker server UTC-offset detection.

WHY THIS EXISTS
---------------
CheckServerOffset() measures the broker's server clock against real UTC and warns when it
does not match the offset the strategy was validated at:

    const long detected = (long)TimeCurrent() - (long)TimeGMT();

The validated backtest assumes UTC+3 (InpExpectedServerUtcOffsetHours). Every day boundary,
the Friday-late entry block, the daily-loss breaker window and the rollover analysis in
findings_broker_and_balance.md are keyed to that clock — 43.8% of this strategy's entries
fall in the server 21:00-00:59 rollover window, so an offset error moves a large slice of
the trade stream into a different session.

Before round 5 the seconds were converted to hours with

    const double hours = (double)((detected + 1800) / 3600);

which reads like round-to-nearest but is not. Both operands are integers, so MQL5 performs
INTEGER division, and C-style integer division truncates TOWARD ZERO rather than flooring.
Adding 1800 before a truncation rounds correctly for positive values and wrongly for
negative ones. Measured:

      server offset    true hours    EA reported
             UTC-1          -1            0        WRONG
             UTC-2          -2           -1        WRONG
             UTC-4          -4           -3        WRONG
             UTC-5          -5           -4        WRONG

Every broker west of UTC came out an hour high. That does not corrupt order flow
(ServerDayKey uses TimeCurrent directly), but it corrupts the one diagnostic the operator
relies on when porting the EA to a new broker: it can emit a bogus WARN against a correct
offset, or stay silent against a real one — and a silent offset mismatch is exactly the
class of failure that shifts the session filter without any visible symptom.

The fix is MathFloor on a floating-point quotient, which rounds half up for both signs.

Faithful port, not a reimplementation: if CheckServerOffset() changes, this must too.
Standard library only, per the repo convention.

Usage:  python3 validation/speed_lab/test_ea_server_offset.py
"""
from __future__ import annotations

import math
import sys

FAILURES: list[str] = []


def check(cond: bool, label: str) -> None:
    print(f"  {'PASS' if cond else 'FAIL'}  {label}")
    if not cond:
        FAILURES.append(label)


def hours_patched(detected_seconds: int) -> int:
    """MQL5: MathFloor(((double)detected + 1800.0) / 3600.0)"""
    return int(math.floor((float(detected_seconds) + 1800.0) / 3600.0))


def hours_old(detected_seconds: int) -> int:
    """MQL5 pre-fix: (double)((detected + 1800) / 3600) — INTEGER division, truncates to 0."""
    q = (detected_seconds + 1800) / 3600
    return int(q) if q >= 0 else -int(-q)          # C truncation toward zero


def hours_naive_div(detected_seconds: int) -> int:
    """The other wrong answer: plain float division with no rounding at all."""
    return int(detected_seconds / 3600.0)          # Python int() also truncates toward zero


# Real broker server offsets that matter to this EA. Positive = east of UTC (the validated
# case and most MT5 servers); negative = west of UTC (a minority, incl. some US-hosted
# servers); zero = a fixed-UTC server such as Exness, which the findings doc flags as a
# 3-hour day-boundary shift from the validated UTC+3.
CASES = [
    # (label, detected seconds, expected hours)
    ("UTC+3  validated assumption (IC Markets/Pepperstone summer)", 3 * 3600, 3),
    ("UTC+2  IC Markets/Pepperstone winter",                        2 * 3600, 2),
    ("UTC+3  Dukascopy",                                            3 * 3600, 3),
    ("UTC+2  Dukascopy hedging winter",                             2 * 3600, 2),
    ("UTC+0  fixed year-round (Exness) — day boundaries shift 3h",          0, 0),
    ("UTC+10 Sydney-hosted server",                                10 * 3600, 10),
    ("UTC-1  one hour west",                                       -1 * 3600, -1),
    ("UTC-2  two hours west",                                      -2 * 3600, -2),
    ("UTC-3 ",                                                     -3 * 3600, -3),
    ("UTC-4  US Eastern server, DST",                              -4 * 3600, -4),
    ("UTC-5  US Eastern server, standard time",                    -5 * 3600, -5),
    ("UTC-8  US Pacific server",                                   -8 * 3600, -8),
]

# Half-hour and 45-minute servers exist (UTC+5:30 India, UTC+5:45 Nepal, UTC+9:30 Adelaide).
# Round-to-nearest must send them somewhere deterministic; assert it is the nearer hour.
# -5:30 is an EXACT tie (-5.5 h). MathFloor(x + 0.5) rounds half UP, i.e. toward +infinity,
# so it resolves to -5, not -6. That is a legitimate deterministic tie-break and is asserted
# as such; what must never happen is a tie resolving differently for two equal inputs.
FRACTIONAL = [
    ("UTC+5:30 -> +5.50 rounds half up to +6", 5 * 3600 + 1800, 6),
    ("UTC+5:29 -> +5.483 rounds to +5", 5 * 3600 + 29 * 60, 5),
    ("UTC-5:30 -> -5.50 is an exact tie, half-up gives -5", -(5 * 3600 + 1800), -5),
    ("UTC-5:29 -> -5.483 rounds to -5", -(5 * 3600 + 29 * 60), -5),
    ("UTC-5:31 -> -5.517 rounds to -6", -(5 * 3600 + 31 * 60), -6),
    ("UTC+5:45 -> +5.75 rounds to +6", 5 * 3600 + 45 * 60, 6),
]


def main() -> int:
    print("=" * 100)
    print("ROUND-5 AUDIT — CheckServerOffset() broker UTC-offset rounding")
    print("=" * 100)

    print("\n1. WHOLE-HOUR SERVER OFFSETS, EAST AND WEST OF UTC")
    print(f"     {'case':<58} {'true':>5} {'old':>5} {'new':>5}")
    old_wrong = new_wrong = 0
    for label, secs, expect in CASES:
        o, n = hours_old(secs), hours_patched(secs)
        flag = "" if n == expect else "   <-- NEW WRONG"
        if o != expect:
            old_wrong += 1
        if n != expect:
            new_wrong += 1
        print(f"     {label:<58} {expect:>+5} {o:>+5} {n:>+5}{flag}")
    print(f"\n     pre-fix wrong: {old_wrong}/{len(CASES)}    patched wrong: {new_wrong}/{len(CASES)}")
    check(new_wrong == 0, f"patched rounding is correct for every whole-hour offset ({new_wrong} wrong)")
    check(old_wrong > 0, f"the pre-fix integer division was genuinely wrong ({old_wrong} offsets) — "
                         f"the test is not asserting against a strawman")

    print("\n2. THE FAILURE IS SIGN-SPECIFIC (truncation toward zero, not a general off-by-one)")
    neg = [(l, s, e) for l, s, e in CASES if e < 0]
    pos = [(l, s, e) for l, s, e in CASES if e > 0]
    neg_old_wrong = sum(1 for _, s, e in neg if hours_old(s) != e)
    pos_old_wrong = sum(1 for _, s, e in pos if hours_old(s) != e)
    print(f"     negative offsets mis-reported pre-fix: {neg_old_wrong}/{len(neg)}")
    print(f"     positive offsets mis-reported pre-fix: {pos_old_wrong}/{len(pos)}")
    check(neg_old_wrong == len(neg), "EVERY offset west of UTC was mis-reported pre-fix")
    check(pos_old_wrong == 0, "offsets east of UTC were already correct (so the bug was invisible "
                              "on the common MT5 servers, and only bites on a port)")

    print("\n3. FRACTIONAL-HOUR SERVERS: NEAREST HOUR, WITH A DETERMINISTIC TIE-BREAK")
    bad = 0
    for label, secs, expect in FRACTIONAL:
        n = hours_patched(secs)
        ok = n == expect
        bad += not ok
        print(f"     {label:<40} detected={secs:>7}s -> {n:>+3}   {'OK' if ok else 'WRONG'}")
    check(bad == 0, f"all {len(FRACTIONAL)} fractional cases round to the nearer hour ({bad} wrong)")

    print("\n4. THE WARN THRESHOLD USES THE SAME VALUE")
    # CheckServerOffset compares (int)hours != InpExpectedServerUtcOffsetHours. With the
    # validated expectation of +3, confirm which real servers do and do not warn.
    EXPECTED = 3
    # Derived from the case table, NOT hardcoded: WARN must fire on every offset that is not
    # the validated UTC+3. Hardcoding the set is how this test first failed — it listed four
    # labels and silently exempted UTC+10 and all the negative ones, which is precisely the
    # bug the round-5 fix exists to catch.
    warn_wrong = 0
    n_warn = 0
    for label, secs, expect in CASES:
        warned = hours_patched(secs) != EXPECTED
        want = expect != EXPECTED
        n_warn += warned
        if warned != want:
            warn_wrong += 1
            print(f"     MISMATCH {label}: warned={warned} expected={want}")
    print(f"     {n_warn}/{len(CASES)} servers warn; only UTC+3 stays silent")
    check(warn_wrong == 0, f"WARN fires exactly on the offsets that differ from UTC+3 "
                           f"({warn_wrong} mismatches)")
    check(n_warn == sum(1 for _, _, e in CASES if e != EXPECTED),
          "no offset west of UTC is silently exempted from the warning")

    print("\n5. MUTATION CONTROL — are these assertions load-bearing?")
    mutants = {
        "pre-fix integer division": hours_old,
        "no rounding at all": hours_naive_div,
        "floor without the +1800": lambda s: int(math.floor(float(s) / 3600.0)),
        "ceil instead of floor": lambda s: int(math.ceil((float(s) + 1800.0) / 3600.0)),
    }
    caught = 0
    for name, fn in mutants.items():
        wrong = sum(1 for _, s, e in CASES + FRACTIONAL if fn(s) != e)
        hit = wrong > 0
        caught += hit
        print(f"     {name:<28} detected: {hit}   ({wrong} of {len(CASES)+len(FRACTIONAL)} cases wrong)")
    check(caught == len(mutants), f"all {len(mutants)} mutants caught ({caught}/{len(mutants)}) — "
                                  f"the assertions distinguish correct from plausible rounding")

    print("\n6. TESTER SHORT-CIRCUIT IS UNCHANGED")
    print("     CheckServerOffset() returns early under MQL_TESTER/MQL_VISUAL_MODE because there")
    print("     TimeGMT() == TimeCurrent(), so `detected` is always 0 and the EA would print a")
    print("     spurious UTC+0 and warn against the configured UTC+3 on every backtest.")
    check(hours_patched(0) == 0, "detected == 0 (the tester case) yields UTC+0, which is why the "
                                 "early return is required rather than optional")

    print("\n" + "=" * 100)
    if FAILURES:
        print(f"FAILED — {len(FAILURES)} check(s):")
        for f in FAILURES:
            print(f"   - {f}")
        return 1
    print("ALL CHECKS PASSED")
    print("  Every whole-hour and fractional server offset, east and west of UTC, is now reported")
    print("  correctly; pre-fix, 100% of offsets west of UTC were an hour high.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
