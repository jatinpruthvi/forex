#!/usr/bin/env python3
"""
test_ea_symbol_resolution.py — test FIVE_M5_EXHAUST's ResolveSymbol()/SuffixPlausible().

MQL5 cannot be compiled here, so the two functions are transliterated line-for-line into
Python and tested against the symbol lists real brokers actually publish. The point is to
catch the failure mode that is invisible in the terminal: an EA that silently trades a
SUBSET of its universe because the broker calls EURGBP "EURGBP.m" on this account type.

Includes mutation control. A matcher that accepts everything passes the positive cases and
is worthless, so the permissive variant must be shown to produce the false match it would
produce in production - resolving the canonical base "USD" onto "USDCAD".

Usage:  python3 validation/speed_lab/test_ea_symbol_resolution.py
"""
from __future__ import annotations

import sys

# ---------------------------------------------------------------- transliteration
# MQL5 StringGetCharacter(s, i) returns the UTF-16 code unit; Python ord() on a BMP
# character is the same value, which is all these ASCII suffixes need.


def suffix_plausible(suf: str, permissive: bool = False) -> bool:
    n = len(suf)
    if n == 0:
        return True                      # exact match
    if suf[0] in ".-_":
        return True                      # punctuation-delimited: unambiguous at any length
    if permissive:                       # mutation: no case and no length rule
        return True
    if n > 4:
        return False
    return all("a" <= ch <= "z" for ch in suf)


def resolve_symbol(base: str, universe, selected=(), permissive: bool = False):
    """Returns (resolved_name, n_matches) or (None, 0) - mirrors the MQL5 control flow."""
    if base == "":
        return None, 0
    blen = len(base)
    best, best_selected, matches = None, False, 0
    for nm in universe:
        if len(nm) < blen:
            continue
        if nm[:blen] != base:
            continue
        suf = nm[blen:]
        if not suffix_plausible(suf, permissive):
            continue
        matches += 1
        if suf == "":                    # exact name always wins outright
            return base, matches
        sel = nm in selected
        if best is None or (sel and not best_selected):
            best, best_selected = nm, sel
    return best, matches


# ---------------------------------------------------------------- cases
UNIVERSE = [
    # a typical MT5 broker offering several account types at once
    "EURUSD", "EURUSD.m", "EURUSD.pro", "EURUSDm", "EURUSD-ECN", "EURUSD_raw",
    "EURGBP", "EURGBP.m", "EURGBP.pro",
    "AUDUSD", "AUDUSD.a", "AUDUSDm",
    "NZDUSD", "NZDUSD.micro",
    "USDCAD", "USDCAD.m", "USDCHF", "USDCHF.m", "USDJPY", "USDJPY.m",
    "EURJPY", "EURJPY.ecn", "GBPJPY", "GBPJPY.pro",
    "XAUUSD", "XAUUSD.m", "XAUUSD2",
    "USDCADx", "EURGBPxxxxxx", "AUDUSDm1",     # must NOT be treated as suffixes
]
CANON = ["EURGBP", "AUDUSD", "NZDUSD", "USDCAD", "USDCHF", "EURJPY", "GBPJPY", "XAUUSD"]


def main() -> int:
    print("=" * 96)
    print("EA SYMBOL-RESOLUTION TEST - transliterated ResolveSymbol()/SuffixPlausible()")
    print("=" * 96)
    fails = []

    def check(name, ok, detail=""):
        print(f"  [{'PASS' if ok else 'FAIL'}]  {name}{('  ' + detail) if detail else ''}")
        if not ok:
            fails.append(name)

    print("\n1. Every pair in the EA's default universe resolves on a multi-suffix broker")
    for base in CANON:
        got, n = resolve_symbol(base, UNIVERSE)
        check(f"{base:<7} -> exact match preferred", got == base, f"got {got!r} from {n} candidates")

    print("\n2. Exact-match-only universes (no suffix) still resolve")
    plain = ["EURGBP", "AUDUSD", "NZDUSD", "USDCAD", "USDCHF", "EURJPY", "GBPJPY", "XAUUSD"]
    for base in CANON:
        got, _ = resolve_symbol(base, plain)
        check(f"{base:<7} resolves", got == base, f"got {got!r}")

    print("\n3. Suffix-only universes resolve, preferring one already in Market Watch")
    only_suffix = ["EURGBP.m", "EURGBP.pro", "EURGBP-ECN"]
    got, n = resolve_symbol("EURGBP", only_suffix)
    check("picks a suffixed variant when no exact name exists", got in only_suffix, f"got {got!r} of {n}")
    got2, _ = resolve_symbol("EURGBP", only_suffix, selected={"EURGBP.pro"})
    check("prefers the variant already selected in Market Watch", got2 == "EURGBP.pro", f"got {got2!r}")

    print("\n4. A missing instrument is reported as missing, never silently substituted")
    got, n = resolve_symbol("GBPCHF", UNIVERSE)
    check("GBPCHF (not offered) -> None", got is None, f"got {got!r}")
    got, n = resolve_symbol("", UNIVERSE)
    check("empty base -> None", got is None, f"got {got!r}")

    print("\n5. Conservative matching must NOT cross instruments")
    got, n = resolve_symbol("USD", UNIVERSE)
    check("base 'USD' does not resolve onto USDCAD/USDCHF/USDJPY", got is None,
          f"got {got!r} from {n} candidates")
    got, n = resolve_symbol("XAUUSD", ["XAUUSD2"])
    check("digit suffix 'XAUUSD2' rejected (uppercase/digit rule)", got is None, f"got {got!r}")
    got, n = resolve_symbol("EURGBP", ["EURGBPxxxxxx"])
    check("6-char lower-case suffix 'EURGBPxxxxxx' rejected", got is None, f"got {got!r}")
    got, n = resolve_symbol("AUDUSD", ["AUDUSDm1"])
    check("alphanumeric suffix containing a digit rejected", got is None, f"got {got!r}")

    print("\n6. Real suffix conventions seen at brokers are all accepted")
    for suf in ("", ".m", "m", ".pro", "-ECN", "_raw", ".ecn", ".a",
                ".micro", ".rawx", "-RAWT", ".standard"):
        base, nm = "AUDUSD", "AUDUSD" + suf
        got, _ = resolve_symbol(base, [nm])
        check(f"suffix {suf!r:<8} on {base} -> {nm}", got == nm, f"got {got!r}")

    # ------------------------------------------------------------ mutation control
    print("\n7. MUTATION CONTROL - the conservative rule must be load-bearing")
    got_p, n_p = resolve_symbol("USD", UNIVERSE, permissive=True)
    caught = got_p is not None
    check("permissive variant DOES mis-resolve 'USD' (proves the rule has power)",
          caught, f"permissive gave {got_p!r} from {n_p} candidates")
    got_p2, _ = resolve_symbol("EURGBP", ["EURGBPxxxxxx"], permissive=True)
    check("permissive variant DOES accept an over-long alphanumeric suffix",
          got_p2 == "EURGBPxxxxxx", f"permissive gave {got_p2!r}")
    if not caught:
        print("      -> the length/case rule changed nothing; this test would pass on a broken matcher")

    print("\n" + "=" * 96)
    if fails:
        print(f"FAIL - {len(fails)} case(s): {fails}")
        return 1
    print("PASS - all cases, and the conservative suffix rule is demonstrably load-bearing")
    print("=" * 96)
    print("\nNote: this tests the TRANSLITERATED logic. It cannot prove the MQL5 compiles, and")
    print("SymbolsTotal(false)/SymbolName(i,false) behaviour must be confirmed in a terminal.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
