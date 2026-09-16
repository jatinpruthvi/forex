#!/usr/bin/env python3
"""
test_ea_lot_normalisation.py — round-5 audit: volume normalisation in NormaliseLots().

WHY THIS EXISTS
---------------
The EA ends every entry with `trade.Buy(lots, ...)`. Before round 5, `lots` came straight
out of

    lots = MathFloor(lots/step)*step;

`n*step` is a binary64 multiply and 0.01 has no exact binary representation, so the value
carries a 1-ULP residue: 35 steps becomes 0.35000000000000003, not 0.35. A broker that
validates volume against SYMBOL_VOLUME_STEP with an exact comparison rejects that with
TRADE_RETCODE_INVALID_VOLUME (10014) or INVALID_VOLUME_STEP — the signal dies live while
every backtest still passes, because no backtest round-trips a volume through a server.

Measured on the REAL validated trade list (7 FX pairs, held-out TEST, n=1,111), the share
of sized volumes carrying the residue is:

      $1,565 ->   3 trades  (0.3%)
      $2,000 ->  15 trades  (1.4%)
      $2,500 ->  25 trades  (2.3%)   <- the balance every headline number is validated at

So this is not cosmetic: at the reference balance, roughly one live signal in 43 could be
rejected outright by a strict broker.

The fix rounds the floored volume to the step's own decimal count. This test proves it does
what it claims and not what would be dangerous:

  1. the residue is gone on the real trade list, at the real balances;
  2. it NEVER authorises more volume than the plain floor did — over-sizing would breach
     the 0.50% risk mandate silently, which is the one outcome that matters;
  3. the intended decimal size is unchanged, so the validated expectancy, the $1,565
     granularity floor and the EA<->backtest identity all still hold;
  4. the decimal count comes from scaling, not -log10(step), because log10 mis-handles
     non-decimal steps: 0.25 -> 1 decimal, which would round 0.25 UP to 0.3 (a 20% over-size).

A TEMPTING 'FIX' THAT IS ACTUALLY A BUG is refuted in sections 8-9. MathFloor(raw/step) looks
vulnerable to dropping a whole step when the quotient lands a ULP below an integer, and the
obvious remedy is a tolerance (MathFloor(q + 1e-9)). Measured against exact rational
arithmetic on all 3,290 trades at $1,565 / $2,000 / $2,500, the shipped plain floor disagrees
with the true intent ZERO times, while the tolerance OVER-sizes 7 trades at $2,000 and 2 at
$2,500. The reason: `stop_pips` comes from price differences, so loss_per_lot is not a round
number even when it prints like one (11.80 pips on AUDUSD gives 125.00000000000699). A
quotient of 9.99999999999944 is therefore not float noise around 10 — it correctly reports
that the stop is a whisker wider than the round number, so 9 steps IS the authorised size. The
floor is left byte-identical to the validated replay; only the residue is cleaned.

This is a faithful port of the MQL5 function, not a reimplementation: if NormaliseLots()
changes, this port must change with it. Standard library only, per the repo convention.

Usage:  python3 validation/speed_lab/test_ea_lot_normalisation.py
"""
from __future__ import annotations

import math
import sys
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

FAILURES: list[str] = []


def check(cond: bool, label: str) -> None:
    print(f"  {'PASS' if cond else 'FAIL'}  {label}")
    if not cond:
        FAILURES.append(label)


# ---------------------------------------------------------------- the port

def decimals_for_step(step: float) -> int:
    """Decimals needed to print `step` exactly. Mirrors the MQL5 scaling loop."""
    vd, s = 0, step
    while vd < 8 and abs(s - math.floor(s + 0.5)) > 1e-12:
        s *= 10.0
        vd += 1
    return vd


def normalise_double(v: float, vd: int) -> float:
    """MQL5 NormalizeDouble(v, vd): round half away from zero to vd decimals."""
    return float(Decimal(repr(v)).quantize(Decimal(1).scaleb(-vd), rounding=ROUND_HALF_UP))


def normalise_lots(lots: float, step: float, vmin: float, vmax: float) -> float:
    """Port of the PATCHED MQL5 NormaliseLots()."""
    if step <= 0.0:
        return 0.0
    floored = math.floor(lots / step) * step        # authorised volume, residue and all
    clean = normalise_double(floored, decimals_for_step(step))
    if clean > floored + 1e-10:                     # never authorise more than the floor did
        clean = floored
    if clean < vmin:
        return 0.0
    if clean > vmax:
        return vmax
    return clean


def normalise_lots_old(lots: float, step: float, vmin: float, vmax: float) -> float:
    """The pre-round-5 function, kept as the regression baseline."""
    if step <= 0.0:
        return 0.0
    lots = math.floor(lots / step) * step
    if lots < vmin:
        return 0.0
    if lots > vmax:
        return vmax
    return lots


def correctly_rounded_decimal(v: float, vd: int) -> float:
    """The double the broker means: `v` snapped to exactly vd decimals."""
    return normalise_double(v, vd)


# ---------------------------------------------------------------- real trade list

UNI7 = ["EURGBP", "AUDUSD", "NZDUSD", "USDCAD", "USDCHF", "EURJPY", "GBPJPY"]


def real_volumes():
    """Every (balance, sym, raw_lots) the EA would actually size, on the validated TEST set."""
    import verify_final_config as V
    all_tr = {s: V.build(s) for s in V.SPECS}
    test = [t for s in UNI7 for t in all_tr[s] if t.ets >= V.TRAIN_END]
    test.sort(key=lambda t: t.ets)
    out = []
    for bal in (1565.0, 2000.0, 2500.0):
        rc = bal * 0.005
        for t in test:
            lpl = t.stop_pips * V.SPECS[t.sym][1] + V.COMM_RT
            if lpl <= 0.0:
                continue
            out.append((bal, t.sym, rc / lpl))
    return out, len(test)


# ---------------------------------------------------------------- tests

def main() -> int:
    print("=" * 100)
    print("ROUND-5 AUDIT — NormaliseLots() volume normalisation")
    print("=" * 100)

    STEP, VMIN, VMAX = 0.01, 0.01, 1e9
    VD = decimals_for_step(STEP)

    vols, n_test = real_volumes()
    print(f"\n  validated TEST trades, 7 FX pairs: {n_test:,}   "
          f"balances probed: $1,565 / $2,000 / $2,500")

    print("\n1. THE RESIDUE IS REAL ON THE ACTUAL TRADE LIST")
    per_bal = {}
    for bal in (1565.0, 2000.0, 2500.0):
        rows = [(s, raw) for b, s, raw in vols if b == bal]
        sized = [(s, normalise_lots_old(raw, STEP, VMIN, VMAX)) for s, raw in rows]
        sized = [(s, v) for s, v in sized if v >= VMIN]
        bad = [(s, v) for s, v in sized if v != correctly_rounded_decimal(v, VD)]
        per_bal[bal] = (len(bad), len(sized))
        ex = "  ".join(f"{s}:{v!r}" for s, v in bad[:2])
        print(f"     ${bal:>7,.0f}  {len(bad):>4} of {len(sized):>5,} sized volumes carry a residue "
              f"({len(bad)/max(1,len(sized))*100:>4.1f}%)   {ex}")
    total_bad = sum(b for b, _ in per_bal.values())
    check(total_bad > 0, f"pre-fix, {total_bad} real volumes carry a 1-ULP residue "
                         f"(broker-rejectable on a strict step validator)")

    print("\n2. THE FIX REMOVES IT")
    still = 0
    for bal, sym, raw in vols:
        v = normalise_lots(raw, STEP, VMIN, VMAX)
        if v >= VMIN and v != correctly_rounded_decimal(v, VD):
            still += 1
    print(f"     residues after patch: {still}")
    check(still == 0, f"every real volume now equals the correctly-rounded decimal ({still} left)")

    print("\n3. IT NEVER AUTHORISES MORE VOLUME THAN THE FLOOR DID  (the dangerous direction)")
    over = [(bal, sym, normalise_lots_old(raw, STEP, VMIN, VMAX),
             normalise_lots(raw, STEP, VMIN, VMAX))
            for bal, sym, raw in vols
            if normalise_lots(raw, STEP, VMIN, VMAX)
            > normalise_lots_old(raw, STEP, VMIN, VMAX) + 1e-12]
    # and over the whole synthetic range too
    over += [(0, f"n={n}", 0.0, 0.0) for n in range(1, 20001)
             if normalise_lots(n * STEP, STEP, VMIN, VMAX)
             > normalise_lots_old(n * STEP, STEP, VMIN, VMAX) + 1e-12]
    print(f"     over-sized cases: {len(over)}  (real trade list + n=1..20000)")
    check(len(over) == 0, f"no volume is rounded UP into a step the risk budget did not authorise "
                          f"({len(over)} violations)")

    print("\n4. INTENDED SIZE IS UNCHANGED — the EA<->backtest identity survives")
    changed = [(bal, sym, normalise_lots_old(raw, STEP, VMIN, VMAX),
                normalise_lots(raw, STEP, VMIN, VMAX))
               for bal, sym, raw in vols
               if round(normalise_lots_old(raw, STEP, VMIN, VMAX), VD)
               != round(normalise_lots(raw, STEP, VMIN, VMAX), VD)]
    print(f"     real trades whose intended decimal size changed: {len(changed)} of {len(vols):,}")
    check(len(changed) == 0, f"lot SIZE is unchanged on every real trade ({len(changed)} changed) — "
                             f"validated expectancy and the $1,565 floor still hold")

    print("\n5. STEP-DECIMAL COUNT: scaling beats -log10(step)")
    for step in (0.01, 0.1, 1.0, 0.5, 0.25, 0.125, 0.001):
        sc, lg = decimals_for_step(step), max(0, math.ceil(-math.log10(step)))
        print(f"     step={step:<7} scaling->{sc}   -log10->{lg}"
              f"   {'agree' if sc == lg else 'DIVERGE — log10 would corrupt this step'}")
    check(decimals_for_step(0.25) == 2, "0.25 step needs 2 decimals (log10 says 1)")
    check(decimals_for_step(0.125) == 3, "0.125 step needs 3 decimals (log10 says 1)")
    q25 = [normalise_lots(n * 0.25, 0.25, 0.25, VMAX) for n in range(1, 9)]
    exp25 = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    print(f"     0.25 step, n=1..8 -> {q25}")
    check(q25 == exp25, "0.25 step reproduces every multiple exactly (no 0.25 -> 0.3 over-size)")

    print("\n6. BOUNDARY GUARDS")
    check(normalise_lots(500.0, STEP, VMIN, 100.0) == 100.0, "clamped down to SYMBOL_VOLUME_MAX")
    check(normalise_lots(0.004, STEP, VMIN, VMAX) == 0.0, "below SYMBOL_VOLUME_MIN -> 0.0 (trade skipped)")
    check(normalise_lots(1.0, 0.0, VMIN, VMAX) == 0.0, "step <= 0 -> 0.0 (no divide by zero)")
    check(normalise_lots(1.0, -0.01, VMIN, VMAX) == 0.0, "negative step -> 0.0")

    print("\n7. MUTATION CONTROL — are these assertions load-bearing?")
    def mutant_log10(lots, step, vmin, vmax):
        if step <= 0.0:
            return 0.0
        return normalise_double(math.floor(lots / step) * step,
                                max(0, math.ceil(-math.log10(step))))

    def mutant_coarse(lots, step, vmin, vmax):
        if step <= 0.0:
            return 0.0
        return normalise_double(math.floor(lots / step) * step, 1)   # 2dp volumes at 1dp

    mutants = (("log10 decimals", mutant_log10), ("1-decimal rounding", mutant_coarse),
               ("unpatched", normalise_lots_old))
    caught = 0
    for name, fn in mutants:
        residue = any(v >= VMIN and v != correctly_rounded_decimal(v, VD)
                      for _, _, raw in vols for v in (fn(raw, STEP, VMIN, VMAX),))
        oversize = any(fn(n * 0.25, 0.25, 0.25, VMAX) > n * 0.25 + 1e-12 for n in range(1, 9))
        hit = residue or oversize
        caught += hit
        print(f"     {name:<20} detected: {hit}   (residue={residue}, over-size={oversize})")
    check(caught == 3, f"all 3 mutants caught ({caught}/3) — assertions are load-bearing")

    print("\n8. THE 'OBVIOUS FIX' IS A TRAP — a floor tolerance would OVER-size real trades")
    # MathFloor(raw/step) looks vulnerable: when raw is a hair below an exact multiple, the
    # quotient lands a ULP under the integer and the floor drops a whole step. The tempting
    # fix is a tolerance, MathFloor(q + 1e-9). Section 1 of the docstring's history is that
    # this was tried and measured. It is WRONG, and this asserts why.
    #
    # `stop_pips` is derived from price differences, so loss_per_lot is not a round number
    # even when it prints like one (11.80 pips on AUDUSD gives 125.00000000000699, not 125).
    # A quotient of 9.99999999999944 is therefore NOT float noise around 10 - it faithfully
    # reports that the true stop is a whisker wider than the round number, so 9 steps is the
    # correct, authorised size. A tolerance reads that as noise and grants a 10th step.
    from decimal import getcontext
    getcontext().prec = 60
    import verify_final_config as V
    all_tr = {s: V.build(s) for s in V.SPECS}
    every = [t for s in V.SPECS for t in all_tr[s]]

    def tolerant(raw: float) -> int:
        q = raw / STEP
        return math.floor(q + 1e-9 * max(1.0, abs(q)))

    print(f"     {'balance':>9} {'trades':>7} {'plain wrong':>12} {'tolerant wrong':>15}")
    worst_plain = worst_tol = 0
    for bal in (1565.0, 2000.0, 2500.0):
        rc = bal * 0.005
        d_rc = Decimal(repr(rc))
        pw = tw = 0
        for t in every:
            pv = V.SPECS[t.sym][1]
            lpl_x = Decimal(repr(t.stop_pips)) * Decimal(repr(pv)) + Decimal(repr(V.COMM_RT))
            lpl_f = t.stop_pips * pv + V.COMM_RT
            if lpl_x <= 0 or lpl_f <= 0:
                continue
            n_exact = int((d_rc / lpl_x) / Decimal(str(STEP)))    # exact rational intent
            if math.floor((rc / lpl_f) / STEP) != n_exact:
                pw += 1
            if tolerant(rc / lpl_f) != n_exact:
                tw += 1
        worst_plain, worst_tol = max(worst_plain, pw), max(worst_tol, tw)
        print(f"     {bal:>8,.0f}$ {len(every):>7,} {pw:>12} {tw:>15}")
    check(worst_plain == 0, f"the shipped plain floor matches exact rational intent on every real "
                            f"trade at every balance ({worst_plain} disagreements)")
    check(worst_tol > 0, f"a floor tolerance over-sizes {worst_tol} real trades — the 'fix' is the bug")

    print("\n9. THE ARTIFICIAL CASE THAT DOES LOSE A STEP (and why the EA never reaches it)")
    rt = [n for n in range(1, 20001) if math.floor((n * STEP) / STEP) != n]
    print(f"     n*0.01 fed straight back through floor(x/0.01): {len(rt)} of 20000 lose a step")
    print("     e.g. n=29 -> 0.29/0.01 = 28.999999999999996 -> 28")
    print("     Unreachable in the EA: lots is risk_cash/loss_per_lot, a quotient of two")
    print("     unrelated floats, never a pre-existing multiple of step. Measured above: 0")
    print("     disagreements across 3,290 real trades x 3 balances. Left as-is on purpose.")
    check(len(rt) > 0, "the round-trip step-loss is real, so the decision to leave it is informed")

    print("\n" + "=" * 100)
    if FAILURES:
        print(f"FAILED — {len(FAILURES)} check(s):")
        for f in FAILURES:
            print(f"   - {f}")
        return 1
    print("ALL CHECKS PASSED")
    print(f"  {total_bad} broker-rejectable volumes eliminated across $1,565/$2,000/$2,500;")
    print("  0 over-sized; 0 intended sizes changed, so the validated numbers stand.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
