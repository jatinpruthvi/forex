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
    host_p = BUILD / "AllEnginesEA.mq5"
    manifest_p = BUILD / "portfolio_manifest.json"
    check(all(p.exists() for p in (strategies_p, host_p, manifest_p)),
          "build/ missing - run gen_portfolio_ea.py first")
    if FAILS:
        return report()

    strategies = strategies_p.read_text(encoding="utf-8")
    host = host_p.read_text(encoding="utf-8")
    reg_md = (BUILD / "STRATEGY_REGISTRY.md").read_text(encoding="utf-8")
    reg_csv = (BUILD / "strategy_registry.csv").read_text(encoding="utf-8")
    manifest = json.loads(manifest_p.read_text(encoding="utf-8"))
    specs = list(gtc.load_generator().EAS)

    # 1 - deterministic / up to date -------------------------------------------------
    fresh, fresh_host, fresh_manifest = gpe.render(gpe.engine_enum_values(), specs)
    fresh_md, fresh_csv = gpe.registry_docs(fresh_manifest)
    check(fresh == strategies, "PortfolioStrategies.mqh differs from a fresh generation")
    check(fresh_host == host, "AllEnginesEA.mq5 differs from a fresh generation")
    check(fresh_md == reg_md, "STRATEGY_REGISTRY.md differs from a fresh generation")
    check(fresh_csv == reg_csv, "strategy_registry.csv differs from a fresh generation")
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
    for name, text in (("PortfolioStrategies.mqh", strategies), ("AllEnginesEA.mq5", host)):
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

    # 9 - per-strategy switches and the magic registry (post-demo enable/disable) -----
    entries = manifest["entries"]
    switches = re.findall(r"^input bool (InpRun_(\d+)) = true;", host, re.M)
    check(len(switches) == 65, f"expected 65 per-strategy switches, found {len(switches)}")
    check(len({m for _, m in switches}) == len(switches), "duplicate switch magics")
    check([int(m) for _, m in switches] == [e["magic"] for e in entries],
          "switch order/magics do not match the manifest")
    check(all(e["enable_input"] == f"InpRun_{e['magic']}" for e in entries),
          "manifest enable_input does not match InpRun_<magic>")
    for e in entries:
        check(f"g_portEnableReq[{e['index']}]  = InpRun_{e['magic']};" in host,
              f"registry index {e['index']} does not read InpRun_{e['magic']}")
    check("if(!g_portEnableReq[i]) return false;" in host,
          "PortAllowed must honour the per-engine switch")

    # registry documents must carry every magic exactly once
    check(len(re.findall(r"^\| \d+ \| `P\d+\|` \| `InpRun_", reg_md, re.M)) == 65,
          "STRATEGY_REGISTRY.md does not list 65 strategies")
    for e in entries:
        check(f"| {e['magic']} | `{e['tag']}` | `InpRun_{e['magic']}` | {e['expert']} |" in reg_md,
              f"STRATEGY_REGISTRY.md missing magic {e['magic']}")
    csv_rows = [r for r in reg_csv.strip().splitlines() if r and not r.startswith("magic,")]
    check(len(csv_rows) == 65, f"strategy_registry.csv has {len(csv_rows)} rows, expected 65")
    check(len({r.split(",")[0] for r in csv_rows}) == 65, "registry CSV has duplicate magics")

    # identity file for the tracker EA -------------------------------------------
    engines_p = BUILD / "engines.csv"
    check(engines_p.exists(), "engines.csv missing (the tracker EA needs it)")
    engines = engines_p.read_text(encoding="utf-8")
    e_rows = [r for r in engines.strip().splitlines() if r and not r.startswith("magic,")]
    check(len(e_rows) == 65, f"engines.csv has {len(e_rows)} rows, expected 65")
    check(len({r.split(",")[0] for r in e_rows}) == 65, "engines.csv has duplicate magics")
    for e in entries:
        check(f"{e['magic']},{e['tag']},{e['expert']}" in engines,
              f"engines.csv missing magic {e['magic']}")
    check(engines.startswith("magic,tag,ea,strategy,symbols,timeframe,risk_pct,switch,"),
          "engines.csv header changed - the tracker parses it")

    # comment identity: one wrapper per engine, tag front-loaded, gate applied -----
    for e in entries:
        check(f"class {e['wrapper']} : public {e['class']}" in strategies,
              f"wrapper {e['wrapper']} missing")
        check(f'plan.reason = "{e["tag"]}" + plan.reason;' in strategies,
              f"wrapper {e['wrapper']} does not tag the comment")
        check(f"if(!{e['class']}::BuildPlan(ctx, plan)) return false;" in strategies,
              f"wrapper {e['wrapper']} does not call the delivered BuildPlan")
        check(f"g_portStrategy[{e['index']}]   = new {e['wrapper']}();" in host,
              f"registry index {e['index']} does not use the wrapper")
    check("if(!PortEntryGate(ctx.symbol)) return false;" in strategies,
          "wrappers do not apply the book-level entry gate")
    check("bool   PortEntryGate(const string sym);" in host and
          "bool PortEntryGate(const string sym)" in host,
          "PortEntryGate must be declared before the include and defined after")

    # order policy: one per symbol (engine-enforced), cap raised to symbol count --
    check("g_eaCfg.maxOpenPositions    = (int)MathMax(1, cap);" in host,
          "per-engine cap override missing")
    check("g_eaCfg.oneEntryAccountWide = false;" in host,
          "oneEntryAccountWide override missing (multi-symbol needs it off)")
    check('input string InpKeepDeliveredPolicy = "2006"' in host,
          "delivered-policy exception list missing (2006 is the ladder)")
    # one order per symbol, many symbols: the engine enforces it for strategies
    # that do not override AllowMultipleOnSymbol(); the host enforces it for the
    # one that does (2006), unless the engine is in the delivered-policy list
    check("int PortCountEngineSymbol(const long magic, const string sym)" in host,
          "per-engine per-symbol hold counter missing")
    check("if(!PortKeepDelivered(magic) && PortCountEngineSymbol(magic, sym) > 0)" in host,
          "host does not enforce one-order-per-symbol for the stacking engine")
    check("if(PortKeepDelivered(magic)) return true;" not in host,
          "the delivered-policy exemption must not bypass the book caps")
    check("MathMax(1, ctx.openPositions" not in host and
          "g_eaStrategy.AllowMultipleOnSymbol" not in host,
          "the trader must not re-implement the per-symbol rule (the engine has it)")
    check("if(!PortKeepDelivered(g_portMagic[i]))" in host,
          "policy override is not gated by the exception list")

    # dashboard boundary: the trader draws and writes nothing ---------------------
    for forbidden in ("ObjectCreate", "OBJ_LABEL", "OnChartEvent", "Comment(",
                      "ChartRedraw", "ChartSetString", "FileOpen", "FileWrite",
                      "FileDelete", "FileMove", "ObjectsTotal", "ObjectSetString",
                      "StringFormat(\"PORTFOLIO"):
        check(forbidden not in host, f"dashboard/file logic leaked into the trader: {forbidden}")
    check('input group "Per-strategy switches' in host, "switch group heading missing")
    check("EventSetTimer(1);" in host and "void OnTimer()" in host and
          "EventKillTimer();" in host,
          "the chart-symbol tick stream must be backed by the 1s execution timer")
    check("void PortProcess()" in host and host.count("PortProcess();") == 2,
          "OnTick and OnTimer must both call PortProcess()")
    check("g_portState[i].cfg.signalOnNewBarOnly && !PortNewBar(i)" in host,
          "engines that want every-tick signals must not be new-bar gated")
    for e in entries:
        syms = list(e["symbols"])
        check(len(syms) == len(set(syms)),
              f"magic {e['magic']} lists a symbol twice: {syms}")

    # 11 - the EA is ONE file: the strategies are inside it, not a sibling include --
    check('#include "PortfolioStrategies.mqh"' not in host,
          "AllEnginesEA.mq5 still #includes the strategies file")
    check(strategies in host, "the strategy text is not inlined verbatim into the EA")
    bslash = chr(92)
    check(host.count("//=== BEGIN inlined PortfolioStrategies.mqh") == 1 and
          host.count("//=== END inlined PortfolioStrategies.mqh") == 1,
          "inlined strategy block markers missing")
    quoted = re.findall(r'^\s*#include\s+"([^"]+)"', host, re.M)
    check(quoted == [".." + bslash + ".." + bslash + "Include" + bslash + "EACommon.mqh"],
          f"the EA must need only the shared engine header, found: {quoted}")
    check(len(re.findall(r"class P\d+_Port\s*:\s*public\s", host)) == 65,
          "the EA does not carry all 65 strategy wrappers")

    # 10 - tracker EA (PortfolioEA.mq5 in src/): read-only, by magic ------------------
    tracker_p = HERE / "src" / "PortfolioEA.mq5"
    check(tracker_p.exists(), "tracker EA missing: src/PortfolioEA.mq5")
    if tracker_p.exists():
        tracker = tracker_p.read_text(encoding="utf-8")
        code_only = "\n".join(l.split("//")[0] for l in tracker.splitlines())
        for forbidden in ("OrderSend", "OrderSendAsync", "PositionClose", "PositionOpen",
                          "PositionModify", "PositionClosePartial", "OrderModify",
                          "OrderDelete", "CTrade", "trade.Buy", "trade.Sell",
                          "PositionSelect(", "SetExpertMagicNumber"):
            check(forbidden not in code_only,
                  f"tracker must never trade - found {forbidden}")
        check(tracker.count("{") == tracker.count("}"),
              f"brace mismatch in the tracker ({tracker.count('{')} vs {tracker.count('}')})")
        check("EventSetTimer(" in tracker and "void OnTimer()" in tracker and
              "EventKillTimer()" in tracker, "tracker timer wiring incomplete")
        bslash = chr(92)
        check(f'InpIdentityFile = "PortfolioEA{bslash * 2}engines.csv"' in tracker,
              "tracker must read the generated engines.csv")
        check(f'InpReportFile   = "PortfolioEA{bslash * 2}performance.csv"' in tracker,
              "tracker report path changed")
        check("FileOpen(InpReportFile, FILE_WRITE | FILE_CSV | FILE_ANSI, ',')" in tracker,
              "tracker does not write the CSV report")
        for verdict in ("DROP", "REVIEW", "TOO_FEW", "KEEP"):
            check(f'"{verdict}"' in tracker, f"tracker verdict {verdict} missing")
        check("InpRun_" in tracker, "tracker should name the switch (InpRun_<magic>)")
        check("InpRegistryOnly" in tracker, "tracker registry filter missing")
        check("ObjectsTotal(0)" in tracker and "ObjectDelete(0, name)" in tracker,
              "tracker must clean its panel objects on deinit")
        check('g_panelPrefix' in tracker and "PFX_" in tracker, "panel prefix missing")
        # accounting: entry-side costs belong to the round turn (many brokers
        # charge commission on the entry deal), and cost-only deal types must
        # still land in net
        check("isTrade && entry == DEAL_ENTRY_IN" in tracker and
              "g_rows[i].pending += money;" in tracker,
              "tracker drops entry-side commission/swap")
        check("double pl = money + g_rows[i].pending;" in tracker,
              "closed-trade P/L does not include the entry-side costs")
        check("DEAL_ENTRY_OUT_BY" in tracker and "DEAL_ENTRY_INOUT" in tracker,
              "partial/out-by closes are not counted as closed trades")
        check("DEAL_TYPE_BUY" in tracker and "DEAL_TYPE_SELL" in tracker,
              "deal-type filter missing (charge/commission deals must not count as trades)")
        # verdict order: not enough trades is TOO_FEW, never KEEP/DROP
        i_too = tracker.index('g_rows[i].verdict = "TOO_FEW";')
        i_drop = tracker.index('g_rows[i].verdict = "DROP";')
        check(i_too < i_drop, "TOO_FEW must be decided before DROP")
        check('g_rows[i].closed == 0' in tracker, "zero-trade engine is not reported as TOO_FEW")
        check("ArrayResize(g_rows, g_count + 1) != g_count + 1" in tracker,
              "tracker ignores a failed row allocation")
        check("bool haveHistory = HistorySelect(" in tracker,
              "history failure must not wipe the report")
        check("string CsvText(string s)" in tracker and tracker.count("CsvText(") >= 5,
              "CSV text fields must be sanitised (a comma would shift columns)")
        # the identity file the tracker expects must be the one we generate
        check("tag" in engines.splitlines()[0] and "switch" in engines.splitlines()[0],
              "engines.csv header does not match what the tracker parses")

    # 12 - identifier hygiene: what an MQL5 compile rejects -------------------------
    # (a) every `const <type> <name>` must name a type that exists: built-in,
    #     engine enum, or an enum declared in this very file (defect #67 was a
    #     prefixed enum type that was never declared under that name)
    builtin = {"void", "bool", "int", "uint", "long", "ulong", "short", "ushort",
               "char", "uchar", "double", "float", "string", "datetime", "color"}
    declared_enums = re.findall(r"^enum\s+(\w+)", strategies, re.M)
    engine_enums = set()
    for hdr in sorted(gpe.INCLUDE_DIR.glob("*.mqh")):
        engine_enums.update(re.findall(r"^\s*enum\s+(\w+)", hdr.read_text(encoding="utf-8"), re.M))
    check(len(declared_enums) == len(set(declared_enums)),
          "duplicate enum type name in the combined EA")
    check(not (set(declared_enums) & engine_enums),
          f"enum type name clashes with the engine: {sorted(set(declared_enums) & engine_enums)}")
    for m in re.finditer(r"^const\s+([\w:]+)\s+(\w+)\s*=", strategies, re.M):
        tname = m.group(1)
        check(tname in builtin or tname.startswith("ENUM_") or tname in declared_enums,
              f"const {m.group(2)} declares unknown type {tname}")
    # (b) one program namespace: no top-level name may be declared twice
    names = []
    names += re.findall(r"^(?:#define|class|enum|struct)\s+(\w+)", strategies, re.M)
    names += re.findall(r"^const\s+[\w:]+\s+(\w+)\s*=", strategies, re.M)
    names += [m.group(2) for m in
              re.finditer(r"^(?!const\b)(?:static\s+)?(?:void|bool|int|uint|long|ulong|short|"
                          r"ushort|char|uchar|double|float|string|datetime|color|ENUM_\w+|[A-Z]\w*)"
                          r"\s+(\w+)\s*[\[(]", strategies, re.M)]
    dupes = sorted({n for n in names if names.count(n) > 1})
    check(not dupes, f"top-level identifier(s) declared twice in the EA: {dupes[:8]}")
    # (c) every engine's class must configure the magic the registry/tag uses
    parts = re.split(r"//={66}\n//\| from (\S+)\s+\|\s+magic (\d+)\n", strategies)
    for i in range(1, len(parts) - 2, 3):
        blk_name, magic, body = parts[i], int(parts[i + 1]), parts[i + 2]
        consts = dict(re.findall(r"^const\s+[\w:]+\s+(\w+)\s*=\s*(.+?);\s*$", body, re.M))
        mm = re.search(r"cfg\.magic\s*=\s*(\w+)\s*;", body)
        resolved = consts.get(mm.group(1), mm.group(1)) if mm else None
        check(resolved is not None and resolved.strip().isdigit() and int(resolved) == magic,
              f"{blk_name}: cfg.magic does not resolve to the registry magic {magic}")

    # 11 - repo checkers --------------------------------------------------------------
    arity_targets = [str(REPO / "MQL5_Master" / "Include" / h)
                     for h in ("EACore.mqh", "EASignals.mqh", "EASpread.mqh",
                               "EATrade.mqh", "EACommon.mqh")]
    arity_targets += [str(BUILD / "AllEnginesEA.mq5"),
                      str(HERE / "src" / "PortfolioEA.mq5")]
    runs = (([ "python3", "scripts/check_mql5_source.py",
               "portfolio-EA/build/AllEnginesEA.mq5",
               "portfolio-EA/src/PortfolioEA.mq5"], "0 finding(s)"),
            (["python3", "scripts/dev/arity_check.py"] + arity_targets,
             "0 arity finding(s), 0 undefined-name finding(s)"))
    for cmd, expect in runs:
        r = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True)
        tail = (r.stdout + r.stderr).strip().splitlines()
        summary = tail[-1] if tail else "(no output)"
        check(r.returncode == 0, f"{' '.join(cmd[:2])} failed: {summary}")
        check(expect in r.stdout, f"{' '.join(cmd[:2])}: expected '{expect}' in output, got: {summary}")

    return report()


def report() -> int:
    if FAILS:
        print(f"FAILED {len(FAILS)} of {CHECKS} checks:")
        for f in FAILS:
            print("  -", f)
        return 1
    print(f"OK - {CHECKS} checks passed")
    consts = len(re.findall(r"^const ", (BUILD / "PortfolioStrategies.mqh")
                            .read_text(encoding="utf-8"), re.M))
    print("     build/ is current | originals untouched (sha256) | 65 classes, %d inputs" % consts)
    print("     registry complete | state coverage complete | repo checkers clean")
    print("     per-strategy switches + tags + registry/docs/engines.csv verified")
    print("     trader boundary (no dashboard/files) + tracker read-only checks verified")
    print("     NOT verified here: MQL5 compilation (needs MetaEditor on Windows)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
