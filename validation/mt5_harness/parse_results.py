#!/usr/bin/env python3
"""Turn the Strategy Tester result rows into a 65-EA validation table.

Reads the CSVs written by `EA_TestReport()` (EACommon.mqh) during a sweep:

    Common\\Files\\EA_TestReports\\<strategy>_<magic>.csv

and produces, next to the harness:

    out/portfolio_summary.csv    one row per EA, machine-readable
    out/portfolio_summary.md     the same table for reading, worst first

Verdict rules (all overridable on the command line)
    FAIL  no result file (compile/crash/no OnDeinit) | trades < 20 | net profit <= 0 | DD >= 20%
    WARN  trades < 40 | profit factor < 1.10 | DD >= 10% | expectancy <= 0
    PASS  everything else

Usage
    python3 validation/mt5_harness/parse_results.py
    python3 validation/mt5_harness/parse_results.py --dir /path/to/EA_TestReports
    python3 validation/mt5_harness/parse_results.py --dir validation/mt5_harness/results
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
HARNESS = REPO / "validation" / "mt5_harness"


def default_dir() -> Path | None:
    """Repo drop-folder first, then the real Windows common folder."""
    local = HARNESS / "results"
    if local.is_dir() and any(local.glob("*.csv")):
        return local
    appdata = os.environ.get("APPDATA")
    if appdata:
        p = Path(appdata) / "MetaQuotes" / "Terminal" / "Common" / "Files" / "EA_TestReports"
        if p.is_dir():
            return p
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dir", default="", help="folder holding the EA_TestReports CSVs")
    ap.add_argument("--manifest", default="", help="manifest.json written by gen_tester_configs.py")
    ap.add_argument("--min-trades", type=int, default=20)
    ap.add_argument("--warn-trades", type=int, default=40)
    ap.add_argument("--min-pf", type=float, default=1.10)
    ap.add_argument("--max-dd", type=float, default=20.0, help="FAIL at or above this equity DD %%")
    ap.add_argument("--warn-dd", type=float, default=10.0)
    args = ap.parse_args()

    src = Path(args.dir) if args.dir else default_dir()
    if src is None or not src.is_dir():
        print("no result folder found.\n"
              "  run the sweep first, then either copy the folder\n"
              "  %APPDATA%\\MetaQuotes\\Terminal\\Common\\Files\\EA_TestReports\n"
              f"  to {HARNESS / 'results'} or pass --dir <path>", file=sys.stderr)
        return 2

    manifest_path = Path(args.manifest) if args.manifest else (HARNESS / "out" / "manifest.json")
    manifest = {}
    by_magic = {}
    if manifest_path.is_file():
        data = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest = {e["name"]: e for e in data["eas"]}
        by_magic = {str(e["magic"]): e["name"] for e in data["eas"]}
        expected = list(manifest)
    else:
        expected = []

    def resolve(rec):
        """Row -> EA name. `expert` is the compiled file name (join key);
        `strategy` is only the label inside SEASettings."""
        if rec.get("expert") in manifest:
            return rec["expert"]
        if str(rec.get("magic", "")) in by_magic:
            return by_magic[str(rec["magic"])]
        return rec.get("expert") or rec.get("strategy", "")

    rows, unknown = [], []
    for f in sorted(src.glob("*.csv")):
        with f.open(newline="", encoding="utf-8", errors="replace") as fh:
            for rec in csv.DictReader(fh):
                rec["_file"] = f.name
                rec["_ea"] = resolve(rec)
                if manifest and rec["_ea"] not in manifest:
                    unknown.append(rec["_ea"])
                rows.append(rec)

    def num(rec, key):
        try:
            return float(rec.get(key, "") or 0)
        except ValueError:
            return 0.0

    def verdict(rec):
        trades = int(num(rec, "trades"))
        pf = num(rec, "profit_factor")
        dd = num(rec, "equity_dd_pct")
        profit = num(rec, "net_profit")
        exp = num(rec, "expected_payoff")
        if trades < args.min_trades or profit <= 0 or dd >= args.max_dd:
            return "FAIL"
        if trades < args.warn_trades or pf < args.min_pf or dd >= args.warn_dd or exp <= 0:
            return "WARN"
        return "PASS"

    # one row per EA (a re-run overwrites; keep the newest by end_time)
    best: dict[str, dict] = {}
    for rec in rows:
        key = rec["_ea"]
        prev = best.get(key)
        if prev is None or rec.get("end_time", "") >= prev.get("end_time", ""):
            best[key] = rec

    table = []
    for key, rec in best.items():
        meta = manifest.get(key, {})
        table.append({
            "expert_key": key,
            "strategy": rec.get("strategy", key),
            "ea_file": meta.get("name", key),
            "magic": rec.get("magic", meta.get("magic", "")),
            "expert": rec.get("expert", meta.get("name", "")),
            "test_symbol": rec.get("test_symbol", meta.get("test_symbol", "")),
            "timeframe": rec.get("timeframe", meta.get("timeframe", "")),
            "universe": rec.get("symbols", ""),
            "risk_pct": rec.get("risk_pct", ""),
            "trades": int(num(rec, "trades")),
            "win": int(num(rec, "profit_trades")),
            "loss": int(num(rec, "loss_trades")),
            "net_profit": round(num(rec, "net_profit"), 2),
            "pf": round(num(rec, "profit_factor"), 3),
            "expectancy": round(num(rec, "expected_payoff"), 3),
            "equity_dd_pct": round(num(rec, "equity_dd_pct"), 2),
            "recovery": round(num(rec, "recovery_factor"), 3),
            "sharpe": round(num(rec, "sharpe"), 3),
            "verdict": verdict(rec),
        })

    missing = [n for n in expected if n not in best]
    order = {"FAIL": 0, "WARN": 1, "PASS": 2}
    table.sort(key=lambda r: (order[r["verdict"]], r["net_profit"]))
    table = [{"#": i + 1, **r} for i, r in enumerate(table)]

    out = HARNESS / "out"
    out.mkdir(parents=True, exist_ok=True)
    cols = list(table[0].keys()) if table else ["#"]
    with (out / "portfolio_summary.csv").open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        w.writerows(table)

    counts = {v: sum(1 for r in table if r["verdict"] == v) for v in ("PASS", "WARN", "FAIL")}
    md = ["# 65-EA validation summary", "",
          f"Source folder: `{src}`",
          f"EAs with a result row: **{len(table)}** of {len(expected) or '?'} "
          f"| PASS {counts['PASS']} · WARN {counts['WARN']} · FAIL {counts['FAIL']}",
          f"Missing results (no row at all): **{len(missing)}**", ""]
    if missing:
        md += ["EAs that produced no result (compile failure, crash, or never deinitialised):", ""]
        md += [f"* `{m}`" for m in missing] + [""]
    if unknown:
        md += [f"* rows for EAs not in the manifest: {', '.join(sorted(set(unknown)))}", ""]
    md += ["| # | verdict | EA | strategy label | test sym | TF | trades | win/loss | net | PF | expectancy | "
           "eq DD % | recovery | Sharpe |", "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in table:
        md.append("| {#} | {verdict} | `{ea_file}` | {strategy} | {test_symbol} | {timeframe} | {trades} | "
                  "{win}/{loss} | {net_profit} | {pf} | {expectancy} | {equity_dd_pct} | "
                  "{recovery} | {sharpe} |".format(**r))
    md += ["", "Generated by `validation/mt5_harness/parse_results.py`. "
               "Reminder: one tester run tests **one symbol**; EAs whose document spans several "
               "symbols are only fully validated when the same EA is re-run on each key symbol."]
    (out / "portfolio_summary.md").write_text("\n".join(md) + "\n", encoding="utf-8")

    print(f"read {len(rows)} result row(s) from {src}")
    print(f"  PASS {counts['PASS']} | WARN {counts['WARN']} | FAIL {counts['FAIL']} | missing {len(missing)}")
    if missing:
        print("  no result row:", ", ".join(missing[:10]) + (" ..." if len(missing) > 10 else ""))
    print(f"  wrote {out / 'portfolio_summary.csv'}")
    print(f"  wrote {out / 'portfolio_summary.md'}")
    return 0 if not missing else 1


if __name__ == "__main__":
    sys.exit(main())
