#!/usr/bin/env python3
"""
Turn the repository's downloaded M5 history into the H4 OHLC file that
train_model.py wants.

The repo already carries four years of M5 bars per pair under
validation/HistoryData (see scripts/history-data/README.md for how they
were fetched). Those are epoch-millisecond UTC; this buckets them into
4-hour bars aligned to 00/04/08/12/16/20 UTC, which is the standard
forex H4 grid.

USAGE
  python m5_to_h4.py --m5 ../validation/HistoryData/eurusd-m5-*.csv \\
                     --out eurusd_h4.csv

Input header must be:  timestamp,open,high,low,close,volume
Output header is:      date,open,high,low,close
"""

from __future__ import annotations

import argparse
import glob
import sys
from datetime import datetime, timezone

BUCKET_MS = 4 * 60 * 60 * 1000


def read_m5(paths):
    rows = []
    for path in paths:
        with open(path, "r", encoding="utf-8") as fh:
            header = fh.readline().strip().split(",")
            want = ["timestamp", "open", "high", "low", "close"]
            if [c.strip().lower() for c in header][:5] != want:
                sys.exit("%s: unexpected header %s" % (path, header))
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                p = line.split(",")
                try:
                    ts = int(p[0])
                    o, h, l, c = float(p[1]), float(p[2]), float(p[3]), float(p[4])
                except ValueError:
                    continue          # a truncated trailing line is normal
                rows.append((ts, o, h, l, c))
    if not rows:
        sys.exit("No rows read from: %s" % paths)
    rows.sort(key=lambda r: r[0])
    return rows


def to_h4(rows):
    """Bucket into UTC 4-hour bars: key -> [open, high, low, close, count]."""
    bars = {}
    for ts, o, h, l, c in rows:
        key = ts - (ts % BUCKET_MS)
        b = bars.get(key)
        if b is None:
            bars[key] = [o, h, l, c, 1]
        else:
            b[1] = max(b[1], h)
            b[2] = min(b[2], l)
            b[3] = c
            b[4] += 1
    return bars


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--m5", required=True, nargs="+", help="M5 CSV path(s); globs are expanded")
    ap.add_argument("--out", default="eurusd_h4.csv", help="H4 CSV to write")
    ap.add_argument("--min-m5", type=int, default=1,
                    help="drop H4 bars built from fewer than this many M5 bars "
                         "(filters the session-opening partial bar; default 1)")
    args = ap.parse_args()

    paths = []
    for pattern in args.m5:
        hit = glob.glob(pattern)
        paths.extend(hit if hit else [pattern])

    rows = read_m5(paths)
    bars = to_h4(rows)

    out = []
    for key in sorted(bars):
        o, h, l, c, n = bars[key]
        if n < args.min_m5:
            continue
        stamp = datetime.fromtimestamp(key / 1000.0, tz=timezone.utc)
        out.append((stamp.strftime("%Y-%m-%d %H:%M:%S"), o, h, l, c))

    with open(args.out, "w", encoding="utf-8", newline="") as fh:
        fh.write("date,open,high,low,close\n")
        for row in out:
            fh.write("%s,%.5f,%.5f,%.5f,%.5f\n" % row)

    # --- what the next step needs to know ---------------------------------
    span = (datetime.strptime(out[-1][0], "%Y-%m-%d %H:%M:%S") -
            datetime.strptime(out[0][0], "%Y-%m-%d %H:%M:%S"))
    print("  files read      : %d (%d M5 rows)" % (len(paths), len(rows)))
    print("  H4 bars written : %d" % len(out))
    print("  first bar       : %s" % out[0][0])
    print("  last bar        : %s" % out[-1][0])
    print("  span            : %.2f years" % (span.days / 365.25))
    print()
    print("  train_model.py needs >= 500 usable samples after its %d-bar" % 130)
    print("  warm-up; %d bars clears that comfortably." % len(out))
    print()
    print("Wrote %s" % args.out)


if __name__ == "__main__":
    main()
