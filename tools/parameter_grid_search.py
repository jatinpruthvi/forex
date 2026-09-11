"""
Parameter grid search — throwaway spike script.

Tests coarse combinations of SWEEP_ATR_MAX and RECLAIM_WICK_MIN on the
existing 196-day tick data to measure how signal rate changes.

Usage:
    python tools/parameter_grid_search.py
"""
import csv
import math
from collections import defaultdict
from datetime import date, datetime, timedelta
from pathlib import Path

# ---------------------------------------------------------------------------
TICK_FILE = Path("validation/HistoryData/EURUSD.i_202406190501_202609102250.csv")
SERVER_UTC_OFFSET = 3
SWEEP_ATR_MIN     = 0.05
STOP_BUFF_ATR     = 0.10
STOP_ATR_MIN      = 0.60
STOP_ATR_MAX      = 1.50
DISP_BODY_MIN     = 0.60
# ---------------------------------------------------------------------------


def _last_sunday(year: int, month: int) -> date:
    if month == 12:
        nxt = date(year + 1, 1, 1)
    else:
        nxt = date(year, month + 1, 1)
    last = nxt - timedelta(days=1)
    return last - timedelta(days=(last.weekday() + 1) % 7)


def london_utc_offset(d: date) -> int:
    yr = d.year
    if _last_sunday(yr, 3) <= d < _last_sunday(yr, 10):
        return 1
    return 0


def bar_key(dt: datetime, period: int) -> datetime:
    t = dt.hour * 60 + dt.minute
    f = t // period * period
    return dt.replace(hour=f // 60, minute=f % 60, second=0, microsecond=0)


def build_bars(ticks, period):
    bm = {}
    for dt, price in ticks:
        k = bar_key(dt, period)
        if k not in bm:
            bm[k] = [k, price, price, price, price]
        else:
            b = bm[k]
            if price > b[2]: b[2] = price
            if price < b[3]: b[3] = price
            b[4] = price
    return [bm[k] for k in sorted(bm)]  # [time, open, high, low, close]


def compute_atr14(bars, before):
    comp = [b for b in bars if b[0] < before]
    if len(comp) < 14:
        return 0.0
    return sum(b[2] - b[3] for b in comp[-14:]) / 14.0


def lower_wick(b):
    t = b[2] - b[3]
    return 0.0 if t <= 0 else (min(b[1], b[4]) - b[3]) / t


def upper_wick(b):
    t = b[2] - b[3]
    return 0.0 if t <= 0 else (b[2] - max(b[1], b[4])) / t


def body_ratio(b):
    t = b[2] - b[3]
    return 0.0 if t <= 0 else abs(b[4] - b[1]) / t


def count_signals(ask_day, mid_day, sweep_max, wick_min):
    signals = 0
    total_days = 0
    reasons = defaultdict(int)

    for day_key in sorted(ask_day.keys()):
        aticks = ask_day[day_key]
        mticks = mid_day[day_key]
        if not aticks or not mticks:
            continue
        y, mo, d = (int(x) for x in day_key.split("."))
        dobj = date(y, mo, d)
        lo = london_utc_offset(dobj)
        # Session boundaries in server time (UTC+3)
        ref_start = datetime(y, mo, d, SERVER_UTC_OFFSET - lo, 0)
        ref_end   = datetime(y, mo, d, 7 + SERVER_UTC_OFFSET - lo, 0)
        ent_start = ref_end
        ent_end   = datetime(y, mo, d, 11 + SERVER_UTC_OFFSET - lo, 0)

        ref_ticks = [(dt, p) for dt, p in mticks if ref_start <= dt < ref_end]
        if not ref_ticks:
            continue
        ref_high = max(p for _, p in ref_ticks)
        ref_low  = min(p for _, p in ref_ticks)

        m5   = build_bars([(dt, p) for dt, p in aticks], 5)
        m15m = build_bars([(dt, p) for dt, p in mticks], 15)
        atr  = compute_atr14(m15m, ent_start)
        if atr <= 0:
            continue

        window = [b for b in m5 if ent_start <= b[0] < ent_end]
        if not window:
            continue
        total_days += 1

        # Find first sweep
        si, side, sx = -1, None, 0.0
        for i, b in enumerate(window):
            ld = (ref_low - b[3]) / atr
            sd = (b[2] - ref_high) / atr
            ls = ld >= SWEEP_ATR_MIN
            ss = sd >= SWEEP_ATR_MIN
            if not ls and not ss:
                continue
            if ls and ss:
                reasons["ambiguous"] += 1
                break
            si, side = i, ("long" if ls else "short")
            sx = b[3] if side == "long" else b[2]
            break
        if si < 0:
            reasons["no_sweep"] += 1
            continue

        # Reclaim in 3 bars
        last_r = min(len(window) - 1, si + 2)
        ri, fail = -1, None
        for i in range(si, last_r + 1):
            b = window[i]
            if side == "long":
                sx = min(sx, b[3])
                if (ref_low - sx) / atr > sweep_max:
                    fail = "too_deep"
                    break
                if b[4] > ref_low and b[4] < ref_high:
                    if lower_wick(b) < wick_min:
                        fail = "weak_wick"
                        break
                    ri = i
                    break
            else:
                sx = max(sx, b[2])
                if (sx - ref_high) / atr > sweep_max:
                    fail = "too_deep"
                    break
                if b[4] < ref_high and b[4] > ref_low:
                    if upper_wick(b) < wick_min:
                        fail = "weak_wick"
                        break
                    ri = i
                    break
        if ri < 0:
            reasons[fail or "no_reclaim"] += 1
            continue

        if ri + 1 >= len(window):
            reasons["no_displace"] += 1
            continue
        rc, dc = window[ri], window[ri + 1]

        if side == "long":
            ok = (dc[4] > dc[1] and body_ratio(dc) >= DISP_BODY_MIN
                  and dc[4] > (rc[2] + rc[3]) / 2)
        else:
            ok = (dc[4] < dc[1] and body_ratio(dc) >= DISP_BODY_MIN
                  and dc[4] < (rc[2] + rc[3]) / 2)
        if not ok:
            reasons["displace_fail"] += 1
            continue

        entry = (dc[1] + dc[4]) / 2
        raw_stop = sx - STOP_BUFF_ATR * atr if side == "long" else sx + STOP_BUFF_ATR * atr
        if abs(entry - raw_stop) / atr < STOP_ATR_MIN or abs(entry - raw_stop) / atr > STOP_ATR_MAX:
            reasons["stop_band"] += 1
            continue

        signals += 1

    return total_days, signals, dict(reasons)


def main():
    print(f"Loading: {TICK_FILE}")
    ask_day: dict = defaultdict(list)
    mid_day: dict = defaultdict(list)

    with open(TICK_FILE, "r", newline="") as f:
        rdr = csv.reader(f, delimiter="\t")
        next(rdr)
        for row in rdr:
            if len(row) < 4:
                continue
            bs, as_ = row[2].strip(), row[3].strip()
            has_bid, has_ask = bs != "", as_ != ""
            if not has_bid and not has_ask:
                continue
            try:
                dt = datetime.strptime(row[0].strip() + " " + row[1].strip()[:8],
                                       "%Y.%m.%d %H:%M:%S")
            except ValueError:
                continue
            day_key = row[0].strip()
            if has_ask:
                ask_day[day_key].append((dt, float(as_)))
            if has_bid and has_ask:
                mid_day[day_key].append((dt, (float(bs) + float(as_)) / 2))

    print(f"Loaded {sum(len(v) for v in ask_day.values()):,} ask ticks across {len(ask_day)} days\n")

    sweep_candidates = [0.50, 0.60, 0.75, 1.00]
    wick_candidates  = [0.60, 0.50, 0.45, 0.40]

    header = f"{'SWEEP_MAX':<12}{'WICK_MIN':<10}{'Days':<7}{'Signals':<10}{'Rate%':<8}{'too_deep':<11}{'weak_wick':<11}"
    print(header)
    print("-" * len(header))

    for sweep_max in sweep_candidates:
        for wick_min in wick_candidates:
            days, sigs, reasons = count_signals(ask_day, mid_day, sweep_max, wick_min)
            rate = sigs / days * 100 if days > 0 else 0.0
            td = reasons.get("too_deep", 0)
            ww = reasons.get("weak_wick", 0)
            marker = " <-- CURRENT" if sweep_max == 0.50 and wick_min == 0.60 else ""
            print(f"{sweep_max:<12.2f}{wick_min:<10.2f}{days:<7}{sigs:<10}{rate:<8.1f}{td:<11}{ww:<11}{marker}")
        print()


if __name__ == "__main__":
    main()
