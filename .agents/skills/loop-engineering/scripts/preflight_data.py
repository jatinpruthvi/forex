#!/usr/bin/env python3
"""
preflight_data.py - integrity and provenance check for M5 history CSVs (stdlib only).

Used by the forex-strategy-validation profile, rule R1. Run it BEFORE any validation, and record the
printed set fingerprint in the loop ledger so a result can be tied to the exact data behind it.

Checks per file (any failure -> exit code 1):
  * header is  timestamp,open,high,low,close,volume
  * every row parses; timestamps strictly increasing (no duplicates, no reordering)
  * timestamps sit on the 5-minute grid (ts_ms % 300000 == 0)
  * OHLC valid: low <= open,close <= high and all prices > 0
  * coverage: first/last bar, plus optional --expect-start / --expect-end (UTC dates)
  * reports bar count, largest gap, the date volume first becomes non-zero (volume is 0 in the older
    segment of BOTH the tracked and the CI sets, so it is not a provenance signal), and a short sha256

Optional comparison of two data sets (never splice them - this only reports):
  --compare DIR   overlap agreement vs another directory, plus bars that exist only in DIR after this
                  set's last bar (the "forward window", e.g. the CI snapshot tail after 2026-09-11)

Examples
  python3 preflight_data.py
  python3 preflight_data.py --dir validation/HistoryData --expect-start 2022-09-11 --expect-end 2026-09-11
  python3 preflight_data.py --compare /tmp/forex-data-m5-history
"""
from __future__ import annotations

import argparse
import hashlib
import sys
from datetime import datetime, timezone
from pathlib import Path

GRID_MS = 300_000
HEADER = "timestamp,open,high,low,close,volume"
DEFAULT_PATTERN = "*-m5-2022-09-11_2026-09-11.csv"


def find_root() -> Path:
    here = Path(__file__).resolve()
    for p in [here, *here.parents]:
        if (p / "validation" / "HistoryData").is_dir():
            return p
    return Path.cwd()


def fmt(ts_ms: int) -> str:
    return datetime.fromtimestamp(ts_ms / 1000, tz=timezone.utc).strftime("%Y-%m-%d %H:%M")


def parse_date(s: str) -> int:
    return int(datetime.strptime(s, "%Y-%m-%d").replace(tzinfo=timezone.utc).timestamp() * 1000)


def load_bars(path: Path) -> dict:
    """timestamp -> (o, h, l, c, v). Tolerates gz-decompressed CSVs only; header required."""
    bars = {}
    with path.open("r", encoding="utf-8") as fh:
        head = fh.readline().strip().lower()
        if head != HEADER:
            raise ValueError(f"unexpected header: {head!r}")
        for line in fh:
            line = line.strip()
            if not line:
                continue
            f = line.split(",")
            bars[int(f[0])] = (float(f[1]), float(f[2]), float(f[3]), float(f[4]), float(f[5]))
    return bars


def check_file(path: Path) -> dict:
    res = {"file": path.name, "problems": []}
    digest = hashlib.sha256()
    prev = None
    n = dups = unordered = off_grid = bad_ohlc = 0
    vol_from = None
    first = last = None
    max_gap = 0
    max_gap_at = None
    with path.open("rb") as raw:
        for chunk in iter(lambda: raw.read(1 << 20), b""):
            digest.update(chunk)
    with path.open("r", encoding="utf-8") as fh:
        head = fh.readline().strip().lower()
        if head != HEADER:
            res["problems"].append(f"unexpected header {head!r}")
            return res
        for lineno, line in enumerate(fh, start=2):
            line = line.strip()
            if not line:
                continue
            try:
                f = line.split(",")
                ts = int(f[0])
                o, h, l, c, v = (float(x) for x in f[1:6])
            except (ValueError, IndexError):
                res["problems"].append(f"parse error at line {lineno}")
                if len(res["problems"]) > 5:
                    break
                continue
            n += 1
            if ts % GRID_MS:
                off_grid += 1
            if prev is not None:
                if ts == prev:
                    dups += 1
                elif ts < prev:
                    unordered += 1
                else:
                    gap = ts - prev
                    if gap > max_gap:
                        max_gap, max_gap_at = gap, prev
            if min(o, h, l, c) <= 0 or h < max(o, c, l) or l > min(o, c, h):
                bad_ohlc += 1
            if v and vol_from is None:
                vol_from = ts
            if first is None:
                first = ts
            last = ts
            prev = ts
    res.update(
        bars=n, first=first, last=last, max_gap_min=max_gap // 60_000, max_gap_at=max_gap_at,
        vol_from=vol_from, sha=digest.hexdigest()[:12],
    )
    if n == 0:
        res["problems"].append("no data rows")
    for name, cnt in (("duplicate timestamps", dups), ("out-of-order rows", unordered),
                      ("off-grid timestamps", off_grid), ("invalid OHLC bars", bad_ohlc)):
        if cnt:
            res["problems"].append(f"{cnt} {name}")
    return res


def compare_dirs(base: Path, other: Path, pattern: str) -> None:
    print("\n== Comparison (report only; sets are never merged) ==")
    print(f"base : {base}\nother: {other}")
    print(f"{'pair':<8}{'common':>9}{'diff_bars':>10}{'max_abs_diff':>14}{'only_base':>10}{'only_other':>11}"
          f"{'forward_bars':>13}  forward_window")
    for bf in sorted(base.glob(pattern)):
        pair = bf.name.split("-")[0]
        cands = sorted(other.glob(f"{pair}-m5-*.csv"))
        if not cands:
            print(f"{pair:<8} (no counterpart in other)")
            continue
        a, b = load_bars(bf), load_bars(cands[0])
        common = a.keys() & b.keys()
        diff = 0
        mx = 0.0
        for k in common:
            d = max(abs(x - y) for x, y in zip(a[k][:4], b[k][:4]))
            if d > 1e-9:
                diff += 1
                mx = max(mx, d)
        last = max(a)
        fwd = sorted(k for k in b if k > last)
        window = f"{fmt(fwd[0])} .. {fmt(fwd[-1])}" if fwd else "-"
        print(f"{pair:<8}{len(common):>9}{diff:>10}{mx:>14.6g}{len(a.keys() - b.keys()):>10}"
              f"{len(b.keys() - a.keys()):>11}{len(fwd):>13}  {window}")
    print("Note: volume is ignored in the comparison. A forward window this short is a smoke test, not proof.")


def main() -> int:
    root = find_root()
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dir", type=Path, default=root / "validation" / "HistoryData")
    ap.add_argument("--pattern", default=DEFAULT_PATTERN)
    ap.add_argument("--expect-start", help="YYYY-MM-DD (UTC): first bar must be within 3 days after this")
    ap.add_argument("--expect-end", help="YYYY-MM-DD (UTC): last bar must be within 3 days before/after this or later")
    ap.add_argument("--min-pairs", type=int, default=11, help="fail if fewer matching files are found (default 11)")
    ap.add_argument("--compare", type=Path, help="directory with another data set to compare against")
    args = ap.parse_args()

    files = sorted(args.dir.glob(args.pattern))
    print(f"Directory: {args.dir}\nPattern  : {args.pattern}\nFiles    : {len(files)}\n")
    if len(files) < args.min_pairs:
        print(f"FAIL: expected at least {args.min_pairs} files, found {len(files)}")
        return 1

    hdr = f"{'pair':<8}{'bars':>8}  {'first (UTC)':<17}{'last (UTC)':<17}{'maxgap_min':>11}  {'volume from':<12}sha256[:12]  status"
    print(hdr)
    failed = 0
    fingerprint = hashlib.sha256()
    for f in files:
        r = check_file(f)
        pair = f.name.split("-")[0]
        problems = list(r["problems"])
        if not problems:
            if args.expect_start and r["first"] > parse_date(args.expect_start) + 3 * 86_400_000:
                problems.append(f"starts {fmt(r['first'])}, later than expected {args.expect_start}")
            if args.expect_end and r["last"] < parse_date(args.expect_end) - 3 * 86_400_000:
                problems.append(f"ends {fmt(r['last'])}, earlier than expected {args.expect_end}")
        if "bars" in r and r.get("first") is not None:
            print(f"{pair:<8}{r['bars']:>8}  {fmt(r['first']):<17}{fmt(r['last']):<17}"
                  f"{r['max_gap_min']:>11}  {(fmt(r['vol_from'])[:10] if r['vol_from'] else 'never'):<12}{r['sha']:<12} "
                  f"{'FAIL: ' + '; '.join(problems) if problems else 'ok'}")
            fingerprint.update(r["sha"].encode())
        else:
            print(f"{pair:<8} FAIL: {'; '.join(problems)}")
        failed += bool(problems)

    print(f"\nSet fingerprint (record in ledger): {fingerprint.hexdigest()[:12]}")
    print("Volume is 0 before roughly 2024 in both known sets; do not use it as a signal input on older data.")
    if args.compare:
        compare_dirs(args.dir, args.compare, args.pattern)
    print(f"\nRESULT: {'FAIL (' + str(failed) + ' file(s) with problems)' if failed else 'PASS'}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
