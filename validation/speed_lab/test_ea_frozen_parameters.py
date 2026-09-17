#!/usr/bin/env python3
"""
test_ea_frozen_parameters.py — round-7 audit: the EA must not trade a retuned strategy
while still claiming to be the validated release.

WHY THIS EXISTS
---------------
`InpValidationReleaseId` is a string the operator types. Before round 7 nothing anywhere
compared the frozen strategy parameters against the values the expectancy was measured at.
So a buyer of this EA could set:

    InpBodyAtrMultiple 4.0 -> 3.0      (far more signals, a different strategy entirely)
    InpTimeframe       M5  -> M15      (different bars, different ATR window, different fills)
    InpRiskPercent     0.50 -> 5.0     (10x the risk every published drawdown figure assumed)

and `OnInit` would still print `release=M5_EXHAUST_2026_09` and `order submission ENABLED`,
because `Authorised()` only compares two strings the same operator supplied. Every number
published for this EA — +0.704R, ~+15%/month, 8.3% max drawdown, the $2,000 balance floor —
is conditional on those values. This is the same failure class as the repo's own PR #9, which
overstated itself by 2.5x by reporting numbers its configuration did not produce.

`CheckFrozenParameters()` now runs in `OnInit` and splits inputs into two tiers:
  HARD — strategy-defining. Any drift halts the EA (and flattens, since a halted EA stops
         managing positions). InpRiskPercent ABOVE 0.50 is hard for the same reason: the
         drawdown, margin and balance-floor figures all scale with it.
  SOFT — account/broker/universe settings that legitimately vary. These warn and name the
         consequence. InpCommissionPerLotRT MUST be soft, because setting it to 4.50 for
         Fusion Markets Zero is required and must never halt the EA.

That last point is the one that could easily have been gotten backwards, so it is asserted
explicitly in section 4: the recommended Fusion configuration must produce ZERO hard drift.

Faithful port, not a reimplementation. Standard library only, per the repo convention.

Usage:  python3 validation/speed_lab/test_ea_frozen_parameters.py
"""
from __future__ import annotations

import sys

FAILURES: list[str] = []
PERIOD_M5 = 5


def check(cond: bool, label: str) -> None:
    print(f"  {'PASS' if cond else 'FAIL'}  {label}")
    if not cond:
        FAILURES.append(label)


# ---------------------------------------------------------------- the port

DEFAULTS = dict(
    InpBodyAtrMultiple=4.0, InpAtrPeriod=14, InpStopAtrMultiple=2.0,
    InpMinStopAtrMultiple=1.0, InpTargetR=10.0, InpMaxHoldHours=96,
    InpTimeframe=PERIOD_M5, InpRiskPercent=0.50, InpCommissionPerLotRT=7.0,
    InpUseAllEleven=False, InpMaxConcurrent=99, InpMaxTradesPerDay=99,
    InpRiskOnInitialBase=True, InpBlockFridayLate=True, InpFridayCutoffHour=21,
    InpSizingBaseOverride=0.0,
)


def same_d(a: float, b: float) -> bool:
    """MQL5 SameD(): MathAbs(a-b) <= 1e-9"""
    return abs(a - b) <= 1e-9


def check_frozen(p: dict, initial_balance: float = 2000.0) -> tuple[str, str]:
    """Port of CheckFrozenParameters(). Returns (hard_drift, soft_drift)."""
    hard, soft = "", ""

    if not same_d(p["InpBodyAtrMultiple"], 4.0):
        hard += f"InpBodyAtrMultiple={p['InpBodyAtrMultiple']:.2f} (validated 4.00); "
    if p["InpAtrPeriod"] != 14:
        hard += f"InpAtrPeriod={p['InpAtrPeriod']} (validated 14); "
    if not same_d(p["InpStopAtrMultiple"], 2.0):
        hard += f"InpStopAtrMultiple={p['InpStopAtrMultiple']:.2f} (validated 2.00); "
    if not same_d(p["InpMinStopAtrMultiple"], 1.0):
        hard += f"InpMinStopAtrMultiple={p['InpMinStopAtrMultiple']:.2f} (validated 1.00); "
    if not same_d(p["InpTargetR"], 10.0):
        hard += f"InpTargetR={p['InpTargetR']:.2f} (validated 10.00); "
    if p["InpMaxHoldHours"] != 96:
        hard += f"InpMaxHoldHours={p['InpMaxHoldHours']} (validated 96); "
    if p["InpTimeframe"] != PERIOD_M5:
        hard += f"InpTimeframe={p['InpTimeframe']} (validated PERIOD_M5={PERIOD_M5}); "
    if not same_d(p["InpRiskPercent"], 0.50):
        if p["InpRiskPercent"] > 0.50:
            hard += f"InpRiskPercent={p['InpRiskPercent']:.2f}% EXCEEDS the validated 0.50%; "
        else:
            soft += (f"InpRiskPercent={p['InpRiskPercent']:.2f}% is below the validated 0.50% "
                     "- safer, but expect proportionally lower return, and the lot-granularity "
                     "floor RISES (a smaller risk budget reaches 0.01 lots at a higher balance); ")

    if not same_d(p["InpCommissionPerLotRT"], 7.0):
        soft += f"InpCommissionPerLotRT={p['InpCommissionPerLotRT']:.2f} differs from 7.00; "
    if p["InpUseAllEleven"]:
        soft += "InpUseAllEleven=true; "
    if p["InpMaxConcurrent"] != 99:
        soft += (f"InpMaxConcurrent={p['InpMaxConcurrent']} is a prop-firm cap; the "
                 "personal-account figures (~+15%/month) assume 99 = take every signal, and "
                 "capping it roughly halves realised return; ")
    if p["InpMaxTradesPerDay"] != 99:
        soft += (f"InpMaxTradesPerDay={p['InpMaxTradesPerDay']} is a prop-firm cap; the "
                 "personal-account figures assume 99; ")
    if not p["InpRiskOnInitialBase"]:
        soft += "InpRiskOnInitialBase=false compounds; "
    if not p["InpBlockFridayLate"]:
        soft += "InpBlockFridayLate=false; "
    if p["InpFridayCutoffHour"] != 21:
        soft += f"InpFridayCutoffHour={p['InpFridayCutoffHour']} differs from 21; "
    if (p["InpSizingBaseOverride"] > 0.0 and initial_balance > 0.0
            and p["InpSizingBaseOverride"] > initial_balance * 1.001):
        soft += (f"InpSizingBaseOverride={p['InpSizingBaseOverride']:.2f} EXCEEDS the actual "
                 f"initial balance {initial_balance:.2f}; ")
    return hard, soft


def with_(**kw) -> dict:
    d = dict(DEFAULTS)
    d.update(kw)
    return d


# ---------------------------------------------------------------- tests

def main() -> int:
    print("=" * 100)
    print("ROUND-7 AUDIT — CheckFrozenParameters(): retuned inputs must not trade as validated")
    print("=" * 100)

    print("\n1. THE SHIPPED DEFAULTS MUST NOT HALT (no false positive)")
    hard, soft = check_frozen(DEFAULTS)
    print(f"     hard='{hard or '(none)'}'   soft='{soft or '(none)'}'")
    check(hard == "", "as-shipped defaults produce zero hard drift — the EA still starts")
    check(soft == "", "as-shipped defaults produce zero soft drift — no spurious warnings")

    print("\n2. EVERY HARD PARAMETER IS ACTUALLY CAUGHT")
    mutations = [
        ("InpBodyAtrMultiple", 3.0, "trigger loosened — many more signals"),
        ("InpBodyAtrMultiple", 5.0, "trigger tightened — far fewer signals"),
        ("InpAtrPeriod", 7, "ATR window halved"),
        ("InpAtrPeriod", 14, "unchanged (control)"),
        ("InpStopAtrMultiple", 1.0, "stop halved — 1R is half as wide"),
        ("InpStopAtrMultiple", 3.0, "stop widened"),
        ("InpMinStopAtrMultiple", 0.0, "degenerate-stop guard DISABLED — sizes unprotected"),
        ("InpTargetR", 9.0, "target changed"),
        ("InpTargetR", 2.0, "target cut to 2R — a different strategy"),
        ("InpMaxHoldHours", 24, "timeout cut"),
        ("InpMaxHoldHours", 0, "timeout disabled"),
        ("InpTimeframe", 15, "M15 instead of M5"),
        ("InpTimeframe", 1, "M1 instead of M5"),
        ("InpRiskPercent", 5.0, "10x the validated risk"),
        ("InpRiskPercent", 1.0, "2x the validated risk"),
    ]
    missed = []
    for name, val, why in mutations:
        h, _ = check_frozen(with_(**{name: val}))
        expect_hard = not (name == "InpAtrPeriod" and val == 14)
        got = h != ""
        flag = "OK" if got == expect_hard else "MISSED"
        if got != expect_hard:
            missed.append((name, val))
        print(f"     {name:<24} = {val!s:<6} hard={str(got):<5} {flag:<7} {why}")
    check(not missed, f"every strategy-defining drift halts the EA ({len(missed)} missed)")

    print("\n3. InpMinStopAtrMultiple=0 DISABLES THE DEGENERATE-STOP GUARD — must be hard")
    # That guard exists because a near-zero stop sizes an enormous unprotected position
    # (dist==0 -> 1.78 lots on $2,500 with cost_R > 1). Turning it off is not a preference.
    h, _ = check_frozen(with_(InpMinStopAtrMultiple=0.0))
    check(h != "", "disabling the degenerate-stop guard halts, it does not merely warn")

    print("\n4. THE RECOMMENDED FUSION CONFIGURATION MUST NOT HALT  (the easy thing to get wrong)")
    # Round 6 requires InpCommissionPerLotRT = 4.50 for Fusion Zero and dropping XAUUSD.
    # If commission drift were classified HARD, following the broker advice would brick the EA.
    fusion = with_(InpCommissionPerLotRT=4.50)
    h, s = check_frozen(fusion)
    print(f"     Fusion (comm=4.50): hard='{h or '(none)'}'")
    print(f"                         soft='{s[:70]}...'")
    check(h == "", "commission 4.50 (Fusion Zero) is SOFT — the EA still trades")
    check("InpCommissionPerLotRT" in s, "and it warns, naming the broker values, so it is visible")
    for comm in (0.0, 4.0, 4.5, 7.0, 10.0):
        h2, _ = check_frozen(with_(InpCommissionPerLotRT=comm))
        if h2:
            FAILURES.append(f"commission {comm} incorrectly classified HARD")
    check(all(check_frozen(with_(InpCommissionPerLotRT=c))[0] == ""
              for c in (0.0, 4.0, 4.5, 7.0, 10.0)),
          "no commission value from $0 (FXCC) to $10 halts the EA — broker choice is never blocked")

    print("\n5. RISK PERCENT IS ASYMMETRIC: above 0.50 hard, below 0.50 soft")
    h_hi, _ = check_frozen(with_(InpRiskPercent=0.75))
    _, s_lo = check_frozen(with_(InpRiskPercent=0.25))
    h_lo, _ = check_frozen(with_(InpRiskPercent=0.25))
    _, s_hi = check_frozen(with_(InpRiskPercent=0.75))
    print(f"     0.75%: hard={'yes' if h_hi else 'no'} soft={'yes' if s_hi else 'no'}")
    print(f"     0.25%: hard={'yes' if h_lo else 'no'} soft={'yes' if s_lo else 'no'}")
    check(h_hi != "" and s_hi == "", "risk ABOVE the validated 0.50% halts — published drawdown, "
                                     "margin and balance floor all scale with it")
    check(h_lo == "" and s_lo != "", "risk BELOW 0.50% only warns — a deliberate safer choice is "
                                     "legitimate and must not be blocked")
    check("lot-granularity floor" in s_lo, "the low-risk warning names the real consequence: the "
                                           "$2,000 floor RISES as risk % falls")

    print("\n6. SOFT SETTINGS WARN WITHOUT HALTING")
    softs = [("InpUseAllEleven", True), ("InpMaxConcurrent", 2), ("InpMaxTradesPerDay", 5),
             ("InpRiskOnInitialBase", False), ("InpBlockFridayLate", False),
             ("InpFridayCutoffHour", 20)]
    bad = []
    for name, val in softs:
        h, s = check_frozen(with_(**{name: val}))
        if h or not s:
            bad.append((name, val, bool(h), bool(s)))
        print(f"     {name:<24} = {val!s:<6} hard={'yes' if h else 'no '} soft={'yes' if s else 'no '}")
    check(not bad, f"prop-firm caps and account choices warn but never halt ({bad})")

    print("\n7. THE PROP-FIRM CAPS ARE NAMED AS WHAT THEY COST")
    _, s = check_frozen(with_(InpMaxConcurrent=2, InpMaxTradesPerDay=5))
    check("halves realised return" in s,
          "the concurrency warning states that capping roughly halves return — the exact error "
          "made in an earlier draft of this analysis, which quoted +6.80%/mo as if it were the "
          "personal-account figure")

    print("\n8. SIZING-BASE OVERRIDE ABOVE THE REAL BALANCE IS AN OVER-RISK")
    h, s = check_frozen(with_(InpSizingBaseOverride=2500.0), initial_balance=2000.0)
    print(f"     override=2500 on a $2,000 account: hard={'yes' if h else 'no'} soft={'yes' if s else 'no'}")
    check(s != "" and "EXCEEDS" in s, "sizing on $2,500 while holding $2,000 is flagged as a 25% over-risk")
    _, s2 = check_frozen(with_(InpSizingBaseOverride=2000.0), initial_balance=2000.0)
    check("EXCEEDS" not in s2, "an override EQUAL to the balance is not flagged")
    _, s3 = check_frozen(with_(InpSizingBaseOverride=0.0), initial_balance=2000.0)
    check("EXCEEDS" not in s3, "the default override of 0 (use initial balance) is not flagged")

    print("\n9. MULTIPLE DRIFTS ARE ALL REPORTED, NOT JUST THE FIRST")
    h, _ = check_frozen(with_(InpBodyAtrMultiple=3.0, InpAtrPeriod=7, InpTargetR=2.0,
                              InpTimeframe=15))
    n = h.count(";")
    print(f"     4 simultaneous hard drifts -> {n} reported")
    check(n == 4, f"all four are named so the operator can fix them in one pass (got {n})")

    print("\n10. MUTATION CONTROL — would a weaker check pass these tests?")
    def mutant_release_id_only(p, initial_balance=2000.0):
        """What the EA effectively did before round 7: trust the typed release id."""
        return "", ""

    def mutant_warn_only(p, initial_balance=2000.0):
        """A check that classifies everything SOFT — never halts."""
        h, s = check_frozen(p, initial_balance)
        return "", h + s

    def mutant_no_risk_asymmetry(p, initial_balance=2000.0):
        """Risk % treated as soft in BOTH directions — lets 5.0% through."""
        h, s = check_frozen(p, initial_balance)
        if "InpRiskPercent" in h:
            h = h.replace([x for x in h.split("; ") if "InpRiskPercent" in x][0] + "; ", "")
            s += "InpRiskPercent drift; "
        return h, s

    caught = 0
    for name, fn in (("release-id only (pre-round-7)", mutant_release_id_only),
                     ("warn-only, never halts", mutant_warn_only),
                     ("no risk asymmetry", mutant_no_risk_asymmetry)):
        # a weaker variant must fail at least one property asserted above
        broke = (fn(with_(InpBodyAtrMultiple=3.0))[0] == ""            # does not halt a retune
                 or fn(with_(InpRiskPercent=5.0))[0] == ""             # does not halt 10x risk
                 or fn(with_(InpCommissionPerLotRT=4.5))[0] != "")     # or wrongly halts Fusion
        caught += broke
        print(f"     {name:<30} detected: {broke}")
    check(caught == 3, f"all 3 weaker variants are caught ({caught}/3) — the tiering is load-bearing")

    print("\n" + "=" * 100)
    if FAILURES:
        print(f"FAILED — {len(FAILURES)} check(s):")
        for f in FAILURES:
            print(f"   - {f}")
        return 1
    print("ALL CHECKS PASSED")
    print("  Shipped defaults start clean; every strategy-defining retune halts; the recommended")
    print("  Fusion configuration (commission 4.50) warns but still trades; risk above 0.50% halts")
    print("  while risk below it only warns.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
