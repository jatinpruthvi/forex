#!/usr/bin/env python3
"""Compare EAs from a Strategy Tester sweep: correlation, redundancy, portfolio fit.

Run the sweep first (see README.md), then:

    python3 validation/mt5_harness/compare_results.py --reports "<terminal data>/Reports/EA_Harness"
    python3 validation/mt5_harness/compare_results.py --results "<terminal data>/Common/Files/EA_TestReports"

Two data levels, auto-detected:

* **HTML tester reports** (``--reports``) - full per-deal detail: daily PnL series,
  pairwise correlation, redundancy pairs, combined portfolio equity/DD/Sharpe and
  a leave-one-out table ("what does dropping this EA do to the book?").
  Best: generate them with ``gen_tester_configs.py`` (it writes ``Report=``).
* **Result CSVs** (``--results``, written by ``EA_TestReport()``) - aggregate-only
  fallback: ranking table, shared-symbol overlap and a duplicate-strategy warning
  when two EAs on the same symbol have near-identical statistics.

``--selftest`` verifies the maths against synthetic reports (no MT5 needed).
"""

from __future__ import annotations

import argparse
import csv
import html
import json
import math
import re
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DEFAULT_OUT = REPO / "validation" / "mt5_harness" / "out"

DATE_RE = re.compile(r"^(\d{4})\.(\d{2})\.(\d{2})")
TAG_RE = re.compile(r"<[^>]+>")
ROW_RE = re.compile(r"<tr[^>]*>(.*?)</tr>", re.S | re.I)
CELL_RE = re.compile(r"<t[dh][^>]*>(.*?)</t[dh]>", re.S | re.I)
XROW_RE = re.compile(r"<row[^>]*>(.*?)</row>", re.S | re.I)
XCELL_RE = re.compile(r"<cell[^>]*>(.*?)</cell>", re.S | re.I)
NUM_RE = re.compile(r"-?\d[\d\s]*(?:\.\d+)?")


# --------------------------------------------------------------------------
# parsing
# --------------------------------------------------------------------------
def _clean(cell: str) -> str:
    cell = re.sub(r"<br\s*/?>", " ", cell, flags=re.I)
    cell = TAG_RE.sub("", cell)
    cell = html.unescape(cell)
    return re.sub(r"\s+", " ", cell).replace("\xa0", " ").strip()


def _to_float(text: str) -> float | None:
    m = NUM_RE.search(text.replace(" ", "") if text.count(" ") > 1 else text)
    if not m:
        return None
    try:
        return float(m.group(0).replace(" ", ""))
    except ValueError:
        return None


def parse_report(path: Path) -> dict:
    """Return {'deals': [(date, symbol, net)], 'stats': {...}, 'name': ...}."""
    raw = path.read_text(encoding="utf-8", errors="replace")
    deals: list[tuple[str, str, float]] = []

    raw_rows = ([(r, CELL_RE) for r in ROW_RE.findall(raw)] +
                [(r, XCELL_RE) for r in XROW_RE.findall(raw)])
    for row, cell_re in raw_rows:
        cells = [_clean(c) for c in cell_re.findall(row)]
        if len(cells) < 12:
            continue
        m = DATE_RE.match(cells[0])
        if not m:
            continue
        symbol = cells[2]
        if not re.fullmatch(r"[A-Za-z0-9._#]+", symbol or ""):
            continue
        # Time | Deal | Symbol | Type | Direction | Volume | Price | Order |
        # Commission | Swap | Profit | Balance | Comment
        parts = [_to_float(cells[i]) for i in (8, 9, 10)]
        if parts[2] is None:
            continue
        net = (parts[0] or 0.0) + (parts[1] or 0.0) + parts[2]
        deals.append((cells[0], symbol, net))

    stats: dict[str, float] = {}
    for row, cell_re in raw_rows:
        cells = [_clean(c) for c in cell_re.findall(row)]
        if len(cells) == 2:
            label = cells[0].rstrip(":").strip().lower()
            value = _to_float(cells[1])
            if value is not None:
                stats.setdefault(label, value)

    return {"deals": deals, "stats": stats, "name": path.stem}


def load_reports(folder: Path) -> dict[str, dict]:
    out: dict[str, dict] = {}
    for p in sorted(folder.glob("*")):
        if p.suffix.lower() not in (".html", ".htm", ".xml", ".txt") or not p.is_file():
            continue
        rep = parse_report(p)
        if rep["deals"] or rep["stats"]:
            out[rep["name"]] = rep
    return out


def read_csv_results(folder: Path) -> list[dict]:
    rows = []
    for p in sorted(folder.glob("*.csv")):
        with p.open(encoding="utf-8", errors="replace") as fh:
            for row in csv.DictReader(fh):
                row["_file"] = p.name
                rows.append(row)
    return rows


# --------------------------------------------------------------------------
# maths
# --------------------------------------------------------------------------
def daily_series(deals: list[tuple[str, str, float]]) -> dict[str, float]:
    out: dict[str, float] = defaultdict(float)
    for ts, _sym, net in deals:
        out[ts[:10]] += net
    return dict(out)


def pearson(a: list[float], b: list[float]) -> float:
    n = len(a)
    if n < 3:
        return float("nan")
    ma, mb = sum(a) / n, sum(b) / n
    va = sum((x - ma) ** 2 for x in a)
    vb = sum((y - mb) ** 2 for y in b)
    if va <= 0 or vb <= 0:
        return float("nan")
    cov = sum((x - ma) * (y - mb) for x, y in zip(a, b))
    return cov / math.sqrt(va * vb)


def max_drawdown(series: list[float]) -> float:
    peak = 0.0
    worst = 0.0
    run = 0.0
    for x in series:
        run += x
        peak = max(peak, run)
        worst = min(worst, run - peak)
    return abs(worst)


def streak_metrics(daily: dict[str, float]) -> dict:
    days = sorted(daily)
    vals = [daily[d] for d in days]
    n = len(vals)
    if n == 0:
        return {"days": 0, "net": 0.0, "vol": 0.0, "sharpe": 0.0, "maxdd": 0.0, "win_days": 0}
    mean = sum(vals) / n
    var = sum((v - mean) ** 2 for v in vals) / n
    vol = math.sqrt(var)
    total = sum(vals)
    # compounding Sharpe on the combined series happens at portfolio level
    sharpe = (mean / vol * math.sqrt(252)) if vol > 0 else 0.0
    return {"days": n, "net": total, "vol": vol, "sharpe": sharpe,
            "maxdd": max_drawdown(vals), "win_days": sum(1 for v in vals if v > 0)}


def align(pair_dates: list[str], series: dict[str, dict[str, float]]) -> tuple[list[float], list[float]]:
    a, b = [], []
    for d in pair_dates:
        a.append(series[0].get(d, 0.0))
        b.append(series[1].get(d, 0.0))
    return a, b


# --------------------------------------------------------------------------
# analysis
# --------------------------------------------------------------------------
def analyse(reports: dict[str, dict], manifest: dict, min_overlap: int,
            corr_threshold: float) -> dict:
    daily = {name: daily_series(rep["deals"]) for name, rep in reports.items()}
    names = sorted(daily, key=lambda n: -streak_metrics(daily[n])["net"])
    per_ea = {n: streak_metrics(daily[n]) for n in names}

    # pairwise correlation over each pair's common span (missing day = no trade = 0)
    corr: dict[tuple[str, str], float] = {}
    overlap: dict[tuple[str, str], int] = {}
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            da, db = daily[a], daily[b]
            if not da or not db:
                continue
            lo = max(min(da), min(db))
            hi = min(max(da), max(db))
            span = sorted({d for d in list(da) + list(db) if lo <= d <= hi})
            if len(span) < min_overlap:
                continue
            va, vb = align(span, ({0: da, 1: db}))
            c = pearson(va, vb)
            if not math.isnan(c):
                corr[(a, b)] = c
                overlap[(a, b)] = len(span)

    # universe overlap from the sweep manifest (when available)
    universes = {m.get("name", ""): set(m.get("symbols", [])) for m in manifest.get("eas", [])}
    primary = {m.get("name", ""): m.get("test_symbol", "") for m in manifest.get("eas", [])}

    def shared(a: str, b: str) -> list[str]:
        return sorted(universes.get(a, set()) & universes.get(b, set()))

    redundant = []
    for (a, b), c in sorted(corr.items(), key=lambda kv: -kv[1]):
        if c < corr_threshold:
            continue
        shared_syms = shared(a, b)
        primary_same = primary.get(a, "") != "" and primary.get(a) == primary.get(b)
        if shared_syms or primary_same:
            keep, drop = (a, b) if per_ea[a]["net"] >= per_ea[b]["net"] else (b, a)
            redundant.append({
                "keep": keep, "drop": drop, "corr": c, "overlap_days": overlap[(a, b)],
                "shared_symbols": ",".join(shared_syms) or primary.get(a, ""),
                "keep_net": per_ea[keep]["net"], "drop_net": per_ea[drop]["net"],
                "keep_sharpe": per_ea[keep]["sharpe"], "drop_sharpe": per_ea[drop]["sharpe"],
            })

    # combined portfolio: equal weight (raw PnL) and vol-scaled (each EA to the
    # median daily vol, so one loud EA cannot dominate the book)
    all_days = sorted({d for s in daily.values() for d in s})
    vols = [per_ea[n]["vol"] for n in names if per_ea[n]["vol"] > 0]
    target_vol = sorted(vols)[len(vols) // 2] if vols else 0.0

    def combined(exclude: str | None = None) -> tuple[list[float], dict]:
        eq_series, vs_series = [], []
        for d in all_days:
            eq_series.append(sum(daily[n].get(d, 0.0) for n in names if n != exclude))
            vs_series.append(sum(
                daily[n].get(d, 0.0) * (target_vol / per_ea[n]["vol"] if per_ea[n]["vol"] > 0 else 1.0)
                for n in names if n != exclude))
        stats = {"equal": streak_metrics(dict(zip(all_days, eq_series))),
                 "vol_scaled": streak_metrics(dict(zip(all_days, vs_series)))}
        return eq_series, stats

    _, port = combined()
    loo = []
    for n in names:
        _, st = combined(exclude=n)
        loo.append({
            "excluded": n, "net": st["equal"]["net"], "maxdd": st["equal"]["maxdd"],
            "sharpe": st["equal"]["sharpe"],
            "net_delta": st["equal"]["net"] - port["equal"]["net"],
            "sharpe_delta": st["equal"]["sharpe"] - port["equal"]["sharpe"],
        })

    corr_to_book = {}
    for n in names:
        others = [m for m in names if m != n]
        span = sorted({d for d in daily[n]})
        if len(span) >= min_overlap and others:
            book = [sum(daily[m].get(d, 0.0) for m in others) for d in span]
            c = pearson([daily[n].get(d, 0.0) for d in span], book)
            if not math.isnan(c):
                corr_to_book[n] = c

    return {"names": names, "per_ea": per_ea, "corr": corr, "overlap": overlap,
            "redundant": redundant, "portfolio": port, "loo": loo,
            "corr_to_book": corr_to_book, "daily": daily,
            "target_vol": target_vol}


# --------------------------------------------------------------------------
# reporting
# --------------------------------------------------------------------------
def write_reports(res: dict, out_dir: Path, manifest: dict, corr_threshold: float) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    sym_of = {m.get("name", ""): m.get("test_symbol", "") for m in manifest.get("eas", [])}

    md = ["# EA comparison (from a Strategy Tester sweep)", ""]
    md += [f"Reports analysed: **{len(res['names'])}** · correlation threshold: {corr_threshold:.2f} "
           f"· vol target: {res['target_vol']:.2f}/day", ""]

    p = res["portfolio"]
    md += ["## Combined portfolio", "",
           "| view | net | max DD | Sharpe | win days | days |",
           "| --- | ---: | ---: | ---: | ---: | ---: |",
           f"| equal weight | {p['equal']['net']:,.2f} | {p['equal']['maxdd']:,.2f} | "
           f"{p['equal']['sharpe']:.2f} | {p['equal']['win_days']} | {p['equal']['days']} |",
           f"| vol-scaled | {p['vol_scaled']['net']:,.2f} | {p['vol_scaled']['maxdd']:,.2f} | "
           f"{p['vol_scaled']['sharpe']:.2f} | {p['vol_scaled']['win_days']} | {p['vol_scaled']['days']} |",
           ""]

    md += ["## Per-EA", "",
           "| EA | symbol | net | days | max DD | Sharpe | corr to book |",
           "| --- | --- | ---: | ---: | ---: | ---: | ---: |"]
    for n in res["names"]:
        s = res["per_ea"][n]
        c = res["corr_to_book"].get(n)
        md.append(f"| {n} | {sym_of.get(n, '')} | {s['net']:,.2f} | {s['days']} | "
                  f"{s['maxdd']:,.2f} | {s['sharpe']:.2f} | {'-' if c is None else f'{c:.2f}'} |")

    md += ["", "## Redundant pairs (high correlation + shared symbol)", ""]
    if res["redundant"]:
        md += ["| keep | drop | corr | overlap days | shared symbols | keep net / drop net |",
               "| --- | --- | ---: | ---: | --- | --- |"]
        for r in res["redundant"]:
            md.append(f"| {r['keep']} | {r['drop']} | {r['corr']:.2f} | {r['overlap_days']} | "
                      f"{r['shared_symbols']} | {r['keep_net']:,.2f} / {r['drop_net']:,.2f} |")
        md += ["", "Correlated EAs on the same symbol duplicate risk rather than diversifying it: "
                   "run the keeper at full size and either drop the other or halve both."]
    else:
        md.append("None above the threshold - the set is diversified on this sample.")

    md += ["", "## Leave-one-out (equal-weight book)", "",
           "Negative net delta = the EA is additive; positive = the book is better without it.",
           "", "| excluded | book net | delta net | book max DD | delta Sharpe |",
           "| --- | ---: | ---: | ---: | ---: |"]
    for row in sorted(res["loo"], key=lambda r: r["net_delta"], reverse=True):
        md.append(f"| {row['excluded']} | {row['net']:,.2f} | {row['net_delta']:+,.2f} | "
                  f"{row['maxdd']:,.2f} | {row['sharpe_delta']:+.2f} |")

    (out_dir / "comparison.md").write_text("\n".join(md) + "\n", encoding="utf-8")

    with (out_dir / "comparison_corr.csv").open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["ea_a", "ea_b", "corr", "overlap_days", "shared_symbols"])
        for (a, b), c in sorted(res["corr"].items(), key=lambda kv: -kv[1]):
            w.writerow([a, b, f"{c:.4f}", res["overlap"][(a, b)], ""])

    with (out_dir / "redundancy.csv").open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["keep", "drop", "corr", "overlap_days",
                                           "shared_symbols", "keep_net", "drop_net",
                                           "keep_sharpe", "drop_sharpe"])
        w.writeheader()
        w.writerows(res["redundant"])

    with (out_dir / "leave_one_out.csv").open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["excluded", "net", "maxdd", "sharpe",
                                           "net_delta", "sharpe_delta"])
        w.writeheader()
        for row in res["loo"]:
            w.writerow({k: (f"{v:.4f}" if isinstance(v, float) else v) for k, v in row.items()})


def aggregate_compare(rows: list[dict], out_dir: Path) -> None:
    """Fallback when only EA_TestReport CSVs exist (no per-deal data)."""
    out_dir.mkdir(parents=True, exist_ok=True)
    def num(r, *keys, default=0.0):
        for k in keys:
            for kk, vv in r.items():
                if kk and kk.strip().lower() == k:
                    try:
                        return float(str(vv).replace(",", ""))
                    except ValueError:
                        pass
        return default

    md = ["# EA comparison (aggregate only)", "",
          "No per-deal HTML reports were found, so correlation/portfolio maths is not "
          "possible. Re-run the sweep with `Report=` (the default in "
          "`gen_tester_configs.py`) for the full comparison.", "",
          "| EA | net | PF | trades | expectancy | DD % |", "| --- | ---: | ---: | ---: | ---: | ---: |"]
    seen: dict[str, dict] = {}
    for r in rows:
        name = r.get("expert") or r.get("strategy") or Path(str(r.get("_file", ""))).stem
        seen[name] = r
    for name, r in sorted(seen.items(), key=lambda kv: -num(kv[1], "net profit", "net_profit")):
        md.append(f"| {name} | {num(r, 'net profit', 'net_profit'):,.2f} | "
                  f"{num(r, 'profit factor', 'profit_factor'):.2f} | "
                  f"{num(r, 'total trades', 'trades'):.0f} | "
                  f"{num(r, 'expected payoff', 'expectancy'):,.2f} | "
                  f"{num(r, 'equity dd %', 'equity dd relative'):.2f} |")
    (out_dir / "comparison.md").write_text("\n".join(md) + "\n", encoding="utf-8")


# --------------------------------------------------------------------------
# selftest
# --------------------------------------------------------------------------
def _synthetic_report(name: str, deals: list[tuple[str, str, float]]) -> str:
    rows = []
    for ts, sym, net in deals:
        rows.append(
            "<tr><td>" + ts + "</td><td>1</td><td>" + sym + "</td><td>buy</td><td>in</td>"
            "<td>0.10</td><td>1.10000</td><td>1</td><td>-0.70</td><td>0.00</td>"
            f"<td>{net + 0.70:.2f}</td><td>10000.00</td><td></td></tr>")
    return ("<html><body><table>"
            + "<tr><td>Total Net Profit:</td><td>" + f"{sum(n for _, _, n in deals):.2f}" + "</td></tr>"
            + "<tr><td>Profit Factor:</td><td>1.30</td></tr>"
            + "<tr><td>Total Trades:</td><td>" + str(len(deals)) + "</td></tr>"
            + "</table><table>" + "".join(rows) + "</table></body></html>")


def selftest() -> int:
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        d = Path(td) / "reports"
        d.mkdir()
        # A and B trade identically (corr 1.0, shared symbol EURUSD)
        base = [(f"2025.0{i}.{j:02d} 10:00:00", "EURUSD", 10.0 if (i + j) % 2 else -8.0)
                for i in (1, 2, 3, 4, 5, 6) for j in (1, 2, 3, 4, 5, 6, 7, 8, 9, 10)]
        (d / "EA_A.html").write_text(_synthetic_report("EA_A", base), encoding="utf-8")
        (d / "EA_B.html").write_text(_synthetic_report("EA_B", base), encoding="utf-8")
        # C independent on another symbol
        c = [(f"2025.0{i}.{(j % 9) + 1:02d} 11:00:00", "GBPUSD", (-5.0 if j % 3 else 6.0))
             for i in (1, 2, 3, 4, 5, 6) for j in (1, 2, 3, 4, 5, 6, 7, 8, 9)]
        (d / "EA_C.html").write_text(_synthetic_report("EA_C", c), encoding="utf-8")
        # D consistently losing
        dd = [(f"2025.0{i}.{j:02d} 12:00:00", "XAUUSD", -30.0)
              for i in (1, 2, 3, 4) for j in (1, 5, 9, 13, 17, 21, 25, 28)]
        (d / "EA_D.html").write_text(_synthetic_report("EA_D", dd), encoding="utf-8")

        reports = load_reports(d)
        assert len(reports) == 4, reports.keys()
        # real manifest schema (see gen_tester_configs.py)
        manifest = {"eas": [{"name": "EA_A", "test_symbol": "EURUSD", "symbols": ["EURUSD"]},
                            {"name": "EA_B", "test_symbol": "EURUSD", "symbols": ["EURUSD"]},
                            {"name": "EA_C", "test_symbol": "GBPUSD", "symbols": ["GBPUSD"]},
                            {"name": "EA_D", "test_symbol": "XAUUSD", "symbols": ["XAUUSD"]}]}
        res = analyse(reports, manifest, min_overlap=10, corr_threshold=0.6)

        cab = res["corr"].get(("EA_A", "EA_B"))
        assert cab is not None and abs(cab - 1.0) < 1e-9, f"A/B corr={cab}"
        pairs = {(r["keep"], r["drop"]) for r in res["redundant"]}
        assert ("EA_A", "EA_B") in pairs, pairs
        # dropping the losing EA must improve the book
        loo = {r["excluded"]: r for r in res["loo"]}
        assert loo["EA_D"]["net_delta"] > 0, loo["EA_D"]
        assert loo["EA_A"]["net_delta"] < 0, loo["EA_A"]
        # diversification bound: the book's DD can never exceed the sum of the
        # members' DDs, and dropping the consistent loser must lower it
        total_dd = sum(res["per_ea"][n]["maxdd"] for n in res["names"])
        assert res["portfolio"]["equal"]["maxdd"] <= total_dd + 1e-9, (res["portfolio"], total_dd)
        assert loo["EA_D"]["maxdd"] < res["portfolio"]["equal"]["maxdd"], loo["EA_D"]
        write_reports(res, Path(td) / "out", manifest, 0.6)
        for f in ("comparison.md", "comparison_corr.csv", "redundancy.csv", "leave_one_out.csv"):
            assert (Path(td) / "out" / f).exists(), f
        print("selftest OK - parsing, correlation (A/B == 1.000), redundancy detection,")
        print("             leave-one-out direction and all four outputs verified")
    return 0


# --------------------------------------------------------------------------
def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--reports", default="", help="folder with tester HTML reports")
    ap.add_argument("--results", default="", help="folder with EA_TestReport CSVs")
    ap.add_argument("--manifest", default=str(REPO / "validation" / "mt5_harness" / "out" / "manifest.json"))
    ap.add_argument("--out", default=str(DEFAULT_OUT))
    ap.add_argument("--min-overlap", type=int, default=20,
                    help="minimum common trading days before a pair is correlated (default 20)")
    ap.add_argument("--corr", type=float, default=0.60, help="redundancy correlation threshold")
    ap.add_argument("--selftest", action="store_true", help="verify the maths on synthetic data")
    args = ap.parse_args()

    if args.selftest:
        return selftest()

    manifest = {}
    mpath = Path(args.manifest)
    if mpath.exists():
        manifest = json.loads(mpath.read_text(encoding="utf-8"))

    if args.reports and Path(args.reports).is_dir():
        reports = load_reports(Path(args.reports))
        if not reports:
            print(f"no tester reports found in {args.reports}", file=sys.stderr)
            return 2
        res = analyse(reports, manifest, args.min_overlap, args.corr)
        write_reports(res, Path(args.out), manifest, args.corr)
        print(f"compared {len(res['names'])} EA reports -> {Path(args.out) / 'comparison.md'}")
        print(f"  redundant pairs: {len(res['redundant'])} | "
              f"book net (equal weight): {res['portfolio']['equal']['net']:,.2f} | "
              f"book max DD: {res['portfolio']['equal']['maxdd']:,.2f}")
        return 0

    if args.results and Path(args.results).is_dir():
        rows = read_csv_results(Path(args.results))
        if not rows:
            print(f"no result CSVs in {args.results}", file=sys.stderr)
            return 2
        aggregate_compare(rows, Path(args.out))
        print(f"aggregate comparison of {len(rows)} rows -> {Path(args.out) / 'comparison.md'}")
        print("NOTE: no per-deal data - re-run the sweep with Report= for correlation maths.")
        return 0

    print("give --reports <tester report folder> or --results <EA_TestReports folder> "
          "(or --selftest)", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
