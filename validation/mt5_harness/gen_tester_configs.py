#!/usr/bin/env python3
"""Generate MetaTrader 5 Strategy Tester configs for all 65 implemented EAs.

Why this exists
---------------
MT5 attaches exactly ONE Expert Advisor per chart, so "65 charts + 65 robots"
is not a validation method.  The Strategy Tester runs an EA with no chart at
all, and it can be driven from the command line, one config file per EA:

    terminal64.exe /config:<this folder>\\configs\\<EA>.ini

Each run writes a machine-readable result row (see `EA_TestReport()` in
MQL5_Master/Include/EACommon.mqh) which `parse_results.py` turns into the
portfolio table.

The EA metadata is read straight from `scripts/gen_additional_eas.py` (the
generator is the single source of truth for names, magics, universes and
timeframes), so these configs can never drift from the compiled EAs.

Outputs (all under --out, default validation/mt5_harness/out/)
    configs/<EA>.ini        one [Tester] config per EA
    sets/<EA>.set           the EA's inputs, for manual runs / optimization
    run_all.ps1, run_all.bat  sequential sweep driver
    manifest.json           per-EA metadata used by parse_results.py
    symbols_preflight.txt   union of every symbol the 65 EAs need

Usage
    python3 validation/mt5_harness/gen_tester_configs.py \
        --terminal "C:/Program Files/Fusion Markets MetaTrader 5/terminal64.exe" \
        --from 2025.01.01 --to 2026.09.30

Nothing is downloaded or executed here; this only writes files.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
GEN = REPO / "scripts" / "gen_additional_eas.py"

# prefer the most liquid, best-history symbol of each universe for the sweep
PREFERENCE = ["EURUSD", "GBPUSD", "XAUUSD", "USDJPY", "AUDNZD", "EURGBP", "GBPJPY", "AUDUSD", "EURCHF"]

# per-EA overrides (primary test symbol) for EAs whose first documented sleeve
# is not the one the preference list would pick
SYMBOL_OVERRIDES = {
    "EA_studyarena_round5_contestant_e": "GBPUSD",   # doc's per-pair matrix is GBPUSD-first
    "EA_studyarena_round5_contestant_f": "EURGBP",   # Asian grid sleeve
    "EA_studyarena_round11_contestant_f": "XAUUSD",  # sleeve B is the second sleeve
    "EA_studyarena_round10_claude_opus_5_high_reasoning": "EURUSD",
    "EA_TRIAD_SURVIVE": "EURUSD",
}

TF_MAP = {
    "PERIOD_M1": "M1", "PERIOD_M5": "M5", "PERIOD_M15": "M15",
    "PERIOD_M30": "M30", "PERIOD_H1": "H1", "PERIOD_H4": "H4", "PERIOD_D1": "D1",
}

INPUT_RE = re.compile(r"^\s*input\s+\S+\s+(\w+)\s*=\s*([^;]+);", re.M)


def load_generator():
    spec = importlib.util.spec_from_file_location("gen_additional_eas", GEN)
    mod = importlib.util.module_from_spec(spec)
    # dataclasses resolve cls.__module__ through sys.modules, so register first
    sys.modules["gen_additional_eas"] = mod
    spec.loader.exec_module(mod)          # guarded by __main__, no side effects
    return mod


def timeframe_of(ea) -> str:
    m = re.search(r"cfg\.signalTimeframe\s*=\s*(PERIOD_\w+)", ea.configure)
    return TF_MAP.get(m.group(1), "M5") if m else "M5"


def symbols_of(ea) -> list[str]:
    return [s.strip() for s in ea.common.get("symbols", "EURUSD").split(",") if s.strip()]


# the cap that used to silently truncate four universes (defect #72, raised to
# 10 in the eleventh-pass follow-up): "--symbols wide" sweeps exactly the
# symbols that cap used to drop, so those engines get faithful coverage again
OLD_SYMBOL_CAP = 8


def sweep_symbols(ea, mode: str) -> list[str]:
    """Symbols one EA must be swept on.

    primary - just the representative symbol (the original 65-run sweep)
    wide    - primary + every universe symbol beyond the old 8-symbol cap
              (the coverage the cap change restored: magics 2031/3111 get one
              extra run, 2034/2040 get two)
    all     - every symbol of the universe, primary first
    """
    syms = symbols_of(ea)
    prim = primary_symbol(ea)
    if mode == "all":
        rest = [s for s in syms if s != prim]
        return [prim] + rest
    if mode == "wide":
        return [prim] + [s for s in syms[OLD_SYMBOL_CAP:] if s != prim]
    return [prim]


def primary_symbol(ea) -> str:
    if ea.name in SYMBOL_OVERRIDES:
        return SYMBOL_OVERRIDES[ea.name]
    syms = symbols_of(ea)
    for p in PREFERENCE:
        if p in syms:
            return p
    return syms[0]


def input_defaults(ea) -> list[tuple[str, str]]:
    """Inputs as exposed by the rendered EA (post dead-config guard)."""
    out = []
    for name, raw in INPUT_RE.findall(ea.render()):
        value = re.sub(r"//.*$", "", raw).strip()
        if value.startswith('"') and value.endswith('"'):
            value = value[1:-1]
        out.append((name, value))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--terminal", default=r"C:\Program Files\MetaTrader 5\terminal64.exe",
                    help="path to terminal64.exe (used in run_all scripts)")
    ap.add_argument("--out", default=str(REPO / "validation" / "mt5_harness" / "out"))
    ap.add_argument("--symbols", choices=("primary", "wide", "all"), default="primary",
                    help="primary = one run per EA (default); wide = also sweep the symbols the "
                         "old 8-symbol cap used to truncate (the four wide universes); "
                         "all = one run per (EA, universe symbol)")
    ap.add_argument("--from", dest="date_from", default="2025.01.01", help="tester FromDate (YYYY.MM.DD)")
    ap.add_argument("--to", dest="date_to", default="2026.09.30", help="tester ToDate (YYYY.MM.DD)")
    ap.add_argument("--deposit", default="10000")
    ap.add_argument("--leverage", default="1:100")
    ap.add_argument("--model", default="1",
                    help="0 every tick, 1 1-min OHLC (fast sweep), 2 open prices, 4 real ticks (finalists)")
    ap.add_argument("--report-dir", default="Reports\\EA_Harness",
                    help="tester report folder, relative to the terminal data folder "
                         "(per MetaQuotes docs) or an absolute path")
    ap.add_argument("--use-set", action="store_true",
                    help="also pass ExpertParameters=<set file> (needs a recent terminal build)")
    ap.add_argument("--only", default="", help="comma-separated EA name substrings to include")
    args = ap.parse_args()

    gen = load_generator()
    eas = list(gen.EAS)
    if args.only:
        wanted = [w.strip() for w in args.only.split(",") if w.strip()]
        eas = [e for e in eas if any(w in e.name for w in wanted)]

    out = Path(args.out)
    (out / "configs").mkdir(parents=True, exist_ok=True)
    (out / "sets").mkdir(parents=True, exist_ok=True)
    (out / "reports").mkdir(parents=True, exist_ok=True)

    magics: dict[int, str] = {}
    manifest = []
    universe: set[str] = set()

    for ea in eas:
        if ea.magic in magics:
            print(f"DUPLICATE MAGIC {ea.magic}: {ea.name} and {magics[ea.magic]}", file=sys.stderr)
            return 2
        magics[ea.magic] = ea.name

        tf = timeframe_of(ea)
        universe.update(symbols_of(ea))
        runs = sweep_symbols(ea, args.symbols)
        sym = runs[0]

        for rsym in runs:
            # the primary run keeps the historical names (<EA>.ini/.set); extra
            # symbol runs get __<SYMBOL> so every result file stays distinct
            stem = ea.name if rsym == sym else f"{ea.name}__{rsym}"
            ini = [
                "[Tester]",
                f"Expert={ea.name}",
                f"Symbol={rsym}",
                f"Period={tf}",
                f"Model={args.model}",
                f"FromDate={args.date_from}",
                f"ToDate={args.date_to}",
                "Optimization=0",
                "Visual=0",
                f"Deposit={args.deposit}",
                "Currency=USD",
                f"Leverage={args.leverage}",
                "ReplaceReport=1",
                f"Report={args.report_dir}\\{stem}",
                "ShutdownTerminal=1",
            ]
            if args.use_set:
                ini.append(f"ExpertParameters={(out / 'sets' / (stem + '.set')).as_posix()}")
            (out / "configs" / f"{stem}.ini").write_text("\n".join(ini) + "\n", encoding="utf-8")

            set_lines = [f"; {ea.title}", f"; source: {ea.doc}", ";",
                         f"; test: {rsym} {tf}  {args.date_from}..{args.date_to}  model={args.model}", ";"]
            set_lines += [f"{n}={v}" for n, v in input_defaults(ea)]
            (out / "sets" / f"{stem}.set").write_text("\n".join(set_lines) + "\n", encoding="utf-8")

        index_only = not (set(symbols_of(ea)) & {
            "EURUSD", "GBPUSD", "USDJPY", "XAUUSD", "AUDUSD", "USDCAD", "USDCHF",
            "NZDUSD", "EURGBP", "EURJPY", "GBPJPY", "AUDNZD", "EURCHF", "AUDCAD"})
        manifest.append({
            "name": ea.name, "magic": ea.magic, "title": ea.title, "doc": ea.doc,
            "symbols": symbols_of(ea), "test_symbol": sym, "timeframe": tf,
            "risk_pct": ea.common.get("risk", ""), "index_only": index_only,
            "sweep_symbols": runs,
        })

    ps1 = ["# Sequential 65-EA Strategy Tester sweep (generated - do not hand-edit).",
           f'$terminal = "{args.terminal}"',
           '$here = Split-Path -Parent $MyInvocation.MyCommand.Path',
           '$configs = Get-ChildItem -Path (Join-Path $here "configs") -Filter *.ini | Sort-Object Name',
           '$n = 0; $failed = 0',
           'foreach ($c in $configs) {',
           '  $n++',
           '  Write-Host ("[{0}/{1}] {2}" -f $n, $configs.Count, $c.BaseName)',
           '  & $terminal /config:"$($c.FullName)" | Out-Null',
           '  if ($LASTEXITCODE -ne 0) { $failed++; Write-Host "   exit code $LASTEXITCODE" }',
           '}',
           'Write-Host ""',
           'Write-Host ("done: {0} configs, {1} non-zero exits" -f $configs.Count, $failed)',
           'Write-Host "result rows: %APPDATA%\\MetaQuotes\\Terminal\\Common\\Files\\EA_TestReports"',
           'Write-Host "full reports: %APPDATA%\\MetaQuotes\\Terminal\\<instance>\\' + str(args.report_dir).replace('\\', '\\') + ' (for compare_results.py)"',
           'Write-Host "next:    python3 validation/mt5_harness/parse_results.py"']
    (out / "run_all.ps1").write_text("\n".join(ps1) + "\n", encoding="utf-8")

    bat = ["@echo off",
           "REM Sequential 65-EA Strategy Tester sweep (generated - do not hand-edit).",
           f'set TERMINAL={args.terminal}',
           'set HERE=%~dp0',
           'for %%f in ("%HERE%configs\\*.ini") do (',
           '   echo [running] %%~nf',
           '   "%TERMINAL%" /config:"%%~ff"',
           ')',
           'echo done. results: %APPDATA%\\MetaQuotes\\Terminal\\Common\\Files\\EA_TestReports']
    (out / "run_all.bat").write_text("\r\n".join(bat) + "\r\n", encoding="utf-8")

    run_count = sum(len(m["sweep_symbols"]) for m in manifest)
    multi = [m for m in manifest if len(m["sweep_symbols"]) > 1]
    (out / "manifest.json").write_text(json.dumps({
        "generated_from": str(GEN.relative_to(REPO)),
        "date_from": args.date_from, "date_to": args.date_to,
        "model": args.model, "deposit": args.deposit, "leverage": args.leverage,
        "sweep_mode": args.symbols, "count": len(manifest), "run_count": run_count,
        "eas": manifest,
    }, indent=2) + "\n", encoding="utf-8")

    pre = sorted(universe)
    (out / "symbols_preflight.txt").write_text(
        "# every symbol the 65 EAs need (union)\n# feed this to MQL5_Master/Scripts/UniversePreflight.mq5\n"
        + "\n".join(pre) + "\n", encoding="utf-8")

    print(f"OK - {len(manifest)} EAs, {run_count} tester config(s) written to {out} "
          f"(sweep mode: {args.symbols})")
    if multi:
        print(f"     multi-symbol runs ({len(multi)} engine(s)):")
        for m in multi:
            print(f"        {m['name']}: {', '.join(m['sweep_symbols'])}")
    if args.symbols == "primary":
        print("     NOTE: after the EA_MAX_SYMBOLS 8 -> 10 change, the four wide universes "
              "(2031/2034/3111/2040 in the portfolio) are only fully covered with "
              "--symbols wide (or all).")
    print(f"     primary symbols used: {sorted({m['test_symbol'] for m in manifest})}")
    index_only = [m["name"] for m in manifest if m["index_only"]]
    if index_only:
        print("     INDEX-ONLY universes (edit the Symbol= line to your broker's alias):")
        for n in index_only:
            print(f"        {n}")
    print(f"     universes need {len(pre)} distinct symbols (see symbols_preflight.txt)")
    print(f"     tester reports -> <terminal data folder>\\{args.report_dir}\\<EA> (feeds compare_results.py)")
    print(f"     next: run {out / 'run_all.ps1'} on the Windows machine")
    return 0


if __name__ == "__main__":
    sys.exit(main())
