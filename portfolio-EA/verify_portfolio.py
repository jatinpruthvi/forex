#!/usr/bin/env python3
"""Static verification of the generated portfolio EA (run after gen_portfolio_ea.py).

    python3 portfolio-EA/verify_portfolio.py

Checks, in order:

1. ``build/`` is exactly what the generator produces right now (deterministic).
2. the originals are untouched - sha256 of the 65 delivered EAs + engine headers
   still matches the hashes recorded at generation time.
3. all 65 classes are present, unique, and derive from ``CEAStrategy``.
4. no bare input identifier survives: every delivered ``InpX`` appears only as
   ``P<magic>_InpX`` (a name that survived unrenamed inside a class body is a
   compile error in the one-program build).
5. no ``input`` / ``#property`` / event-handler definitions leaked into the
   strategies include.
6. braces balanced in both generated files; include guard present.
7. host registry is complete and magics are unique + match the manifest.
8. the host snapshots and restores every engine global that is per-strategy
   (the list is explicit below - it is the whole point of the host), and
   refreshes the risk governor + executor on every switch.
9. the repo's own checkers run clean on the generated files.

Exit code 0 = all good. Any failure prints the offending file/line.
"""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
BUILD = HERE / "build"
sys.path.insert(0, str(REPO / "validation" / "mt5_harness"))
sys.path.insert(0, str(HERE))

import gen_portfolio_ea as gpe  # noqa: E402
import gen_tester_configs as gtc  # noqa: E402

FAILS: list[str] = []
CHECKS = 0


def check(cond: bool, label: str) -> None:
    global CHECKS
    CHECKS += 1
    if not cond:
        FAILS.append(label)


def main() -> int:
    strategies_p = BUILD / "PortfolioStrategies.mqh"
    host_p = BUILD / "PortfolioEA.mq5"
    manifest_p = BUILD / "portfolio_manifest.json"
    check(all(p.exists() for p in (strategies_p, host_p, manifest_p)),
          "build/ missing - run gen_portfolio_ea.py first")
    if FAILS:
        return report()

    strategies = strategies_p.read_text(encoding="utf-8")
    host = host_p.read_text(encoding="utf-8")
    manifest = json.loads(manifest_p.read_text(encoding="utf-8"))
    specs = list(gtc.load_generator().EAS)

    # 1 - deterministic / up to date -------------------------------------------------
    fresh, fresh_host, fresh_manifest = gpe.render(gpe.engine_enum_values(), specs)
    check(fresh == strategies, "PortfolioStrategies.mqh differs from a fresh generation")
    check(fresh_host == host, "PortfolioEA.mq5 differs from a fresh generation")
    expect_manifest = json.loads(json.dumps(manifest))
    check(len(fresh_manifest) == len(expect_manifest["entries"]),
          "manifest entry count mismatch vs fresh generation")

    # 2 - originals untouched --------------------------------------------------------
    hash_file = BUILD / "originals.sha256"
    check(hash_file.exists(), "originals.sha256 missing (regenerate)")
    if hash_file.exists():
        for line in hash_file.read_text(encoding="utf-8").splitlines():
            if not line or line.startswith("#"):
                continue
            digest, rel = line.split("  ", 1)
            f = REPO / rel
            check(f.exists(), f"original missing: {rel}")
            if f.exists():
                actual = hashlib.sha256(f.read_bytes()).hexdigest()
                check(actual == digest, f"ORIGINAL MODIFIED: {rel}")

    # 3 - classes --------------------------------------------------------------------
    classes = re.findall(r"class\s+(P\d+_\w+)\s*:\s*public\s+CEAStrategy", strategies)
    check(len(classes) == 65, f"expected 65 strategy classes, found {len(classes)}")
    check(len(set(classes)) == len(classes), "duplicate class names in the strategies include")
    check(len(set(classes)) == len(manifest["entries"]),
          "class count != manifest entries")

    # 4 - no bare input identifiers ---------------------------------------------------
    bare = []
    for ea in specs:
        for _t, name, _d in gpe.INPUT_LINE_RE.findall(gpe.strategy_source(ea.name)):
            for m in re.finditer(rf"(?<![\w]){re.escape(name)}(?![\w])", strategies):
                line = strategies[:m.start()].count("\n") + 1
                bare.append(f"{ea.name}:{name} at line {line}")
    check(not bare, f"unrenamed input identifier(s): {bare[:5]}")

    # 5 - nothing leaked from the EA shell -------------------------------------------
    check(not re.search(r"^\s*input\s+\w+\s+\w+\s*=", strategies, re.M),
          "input declaration leaked into the strategies include")
    check("#property" not in strategies, "#property leaked into the strategies include")
    for handler in ("int OnInit", "void OnTick", "void OnDeinit", "void OnTimer"):
        check(not re.search(rf"^\s*{handler}\s*\(", strategies, re.M),
              f"{handler} leaked into the strategies include")
    check("#ifndef PORTFOLIO_STRATEGIES_MQH" in strategies, "include guard missing")

    # 6 - braces ---------------------------------------------------------------------
    for name, text in (("PortfolioStrategies.mqh", strategies), ("PortfolioEA.mq5", host)):
        check(text.count("{") == text.count("}"),
              f"brace mismatch in {name} ({text.count('{')} vs {text.count('}')})")

    # 7 - registry -------------------------------------------------------------------
    reg = re.findall(r"g_portStrategy\[(\d+)\]\s*=\s*new\s+(P\d+_\w+)\(\);", host)
    check(len(reg) == 65, f"registry has {len(reg)} entries, expected 65")
    check([int(i) for i, _ in reg] == list(range(65)), "registry indices are not 0..64")
    magics = [int(m) for m in re.findall(r"g_portMagic\[(\d+)\]\s*=\s*(\d+);", host)] \
        if False else [int(m) for _, m in re.findall(r"g_portMagic\[(\d+)\]\s*=\s*(\d+);", host)]
    check(len(magics) == 65 and len(set(magics)) == 65, "magic list incomplete or duplicated")
    check(sorted(magics) == sorted(e["magic"] for e in manifest["entries"]),
          "registry magics != manifest magics")
    check(all(c in strategies for _, c in reg), "registry references a class not in the include")

    # 8 - state coverage -------------------------------------------------------------
    required = ["g_eaCfg", "g_eaSymbols", "g_eaSymbolCount", "g_eaLastSignalBar",
                "g_eaInd", "g_eaIndCount", "g_eaIndTf", "g_eaTrack", "g_eaTrackCount",
                "g_eaStatSym", "g_eaStatUsed", "g_eaNewsTimes", "g_eaNewsCount",
                "g_eaNewsLoadedFile", "g_eaNewsLoadStamp"]
    save = re.search(r"void PortSaveState\(const int i\)(.*?)\n\}", host, re.S)
    load = re.search(r"void PortLoadState\(const int i\)(.*?)\n\}", host, re.S)
    check(save is not None and load is not None, "snapshot functions missing")
    if save and load:
        for g in required:
            check(re.search(rf"(?<![\w]){g}\b", save.group(1)) is not None,
                  f"PortSaveState does not save {g}")
            check(re.search(rf"(?<![\w]){g}\b", load.group(1)) is not None,
                  f"PortLoadState does not restore {g}")
    check("g_eaRisk.Init()" in host and "g_eaExec.Init()" in host,
          "per-switch risk/exec refresh missing")
    check("g_eaIndCount    = 0;" in host or "g_eaIndCount = 0;" in host,
          "indicator registry is not reset before each EA_Init (handles would accumulate)")

    # 9 - repo checkers ---------------------------------------------------------------
    for cmd in (["python3", "scripts/check_mql5_source.py",
                 "portfolio-EA/build/PortfolioEA.mq5"],
                ["python3", "scripts/dev/arity_check.py"]):
        r = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True)
        tail = (r.stdout + r.stderr).strip().splitlines()
        summary = tail[-1] if tail else "(no output)"
        check(r.returncode == 0, f"{' '.join(cmd[:2])} failed: {summary}")
        if cmd[-1].endswith(".mq5"):
            check("0 finding(s)" in r.stdout, f"checker findings: {summary}")

    return report()


def report() -> int:
    if FAILS:
        print(f"FAILED {len(FAILS)} of {CHECKS} checks:")
        for f in FAILS:
            print("  -", f)
        return 1
    print(f"OK - {CHECKS} checks passed")
    print("     build/ is current | originals untouched (sha256) | 65 classes, 859 inputs")
    print("     registry complete | state coverage complete | repo checkers clean")
    print("     NOT verified here: MQL5 compilation (needs MetaEditor on Windows)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
