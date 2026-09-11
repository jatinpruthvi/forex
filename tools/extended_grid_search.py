"""
Extended parameter grid search — adds RECLAIM_BARS (3, 4, 5) as a third dimension.

Covers:
  SWEEP_ATR_MAX   : [0.50, 0.75, 1.00, 1.25]
  RECLAIM_WICK_MIN: [0.60, 0.50, 0.45, 0.40]
  RECLAIM_BARS    : [3, 4, 5]

Pairs: EURUSD London, GBPUSD London, USDJPY New York

Usage:
    python tools/extended_grid_search.py
"""
from __future__ import annotations

import csv
from collections import defaultdict
from datetime import date, datetime, timedelta
from pathlib import Path

# ---------------------------------------------------------------------------
# Frozen geometry (only varied params listed)
# ---------------------------------------------------------------------------
SWEEP_ATR_MIN      = 0.05
DISP_BODY_MIN      = 0.60
STOP_BUFF_ATR      = 0.10
STOP_ATR_MIN       = 0.60
STOP_ATR_MAX       = 1.50
SERVER_UTC_OFFSET  = 3

SWEEP_MAX_CANDIDATES  = [0.50, 0.75, 1.00, 1.25]
WICK_MIN_CANDIDATES   = [0.60, 0.50, 0.45, 0.40]
RECLAIM_BARS_CANDIDATES = [3, 4, 5]

# ---------------------------------------------------------------------------
# Session definitions
# ---------------------------------------------------------------------------
SESSIONS = {
    "EURUSD_LONDON": {
        "symbol": "EURUSD",
        "ref_start_lw": 0, "ref_end_lw": 7,
        "entry_start_lw": 7, "entry_end_lw": 11,
        "ny_entry": False,
    },
    "GBPUSD_LONDON": {
        "symbol": "GBPUSD",
        "ref_start_lw": 0, "ref_end_lw": 7,
        "entry_start_lw": 7, "entry_end_lw": 11,
        "ny_entry": False,
    },
    "USDJPY_NEWYORK": {
        "symbol": "USDJPY",
        "ref_start_lw": 7, "ref_end_lw": 13,
        "ny_entry": True,
        "ny_entry_start_h": 8, "ny_entry_start_m": 30,
        "ny_entry_end_h": 11,  "ny_entry_end_m": 0,
    },
}

TICK_FILES = {
    "EURUSD": Path("validation/HistoryData/EURUSD.i_202406190501_202609102250.csv"),
    "GBPUSD": Path("validation/HistoryData/GBPUSD.i_202406190501_202609110308.csv"),
    "USDJPY": Path("validation/HistoryData/USDJPY.i_202406190501_202609110308.csv"),
}

# ---------------------------------------------------------------------------
# DST helpers
# ---------------------------------------------------------------------------

def _last_sunday(year: int, month: int) -> date:
    nxt = date(year + 1, 1, 1) if month == 12 else date(year, month + 1, 1)
    last = nxt - timedelta(days=1)
    return last - timedelta(days=(last.weekday() + 1) % 7)


def london_offset(d: date) -> int:
    yr = d.year
    return 1 if _last_sunday(yr, 3) <= d < _last_sunday(yr, 10) else 0


def ny_offset(d: date) -> int:
    yr = d.year
    first_sun_mar = date(yr, 3, 1) + timedelta(days=(6 - date(yr, 3, 1).weekday()) % 7)
    edt_start = first_sun_mar + timedelta(weeks=1)
    edt_end = date(yr, 11, 1) + timedelta(days=(6 - date(yr, 11, 1).weekday()) % 7)
    return -4 if edt_start <= d < edt_end else -5


def lw_to_srv(yr, mo, da, h, m=0) -> datetime:
    wall_utc = datetime(yr, mo, da, h, m) - timedelta(hours=london_offset(date(yr, mo, da)))
    return wall_utc + timedelta(hours=SERVER_UTC_OFFSET)


def ny_to_srv(yr, mo, da, h, m=0) -> datetime:
    wall_utc = datetime(yr, mo, da, h, m) - timedelta(hours=ny_offset(date(yr, mo, da)))
    return wall_utc + timedelta(hours=SERVER_UTC_OFFSET)


# ---------------------------------------------------------------------------
# Bar building
# ---------------------------------------------------------------------------

def bar_key(dt: datetime, period: int) -> datetime:
    t = dt.hour * 60 + dt.minute
    f = t // period * period
    return dt.replace(hour=f // 60, minute=f % 60, second=0, microsecond=0)


def build_bars(ticks, period: int) -> list:
    bm: dict = {}
    for dt, price in ticks:
        k = bar_key(dt, period)
        if k not in bm:
            bm[k] = [k, price, price, price, price]
        else:
            b = bm[k]
            if price > b[2]: b[2] = price
            if price < b[3]: b[3] = price
            b[4] = price
    return [bm[k] for k in sorted(bm)]


def atr14(bars, before: datetime) -> float:
    comp = [b for b in bars if b[0] < before]
    if len(comp) < 14:
        return 0.0
    return sum(b[2] - b[3] for b in comp[-14:]) / 14.0


def lower_wick(b) -> float:
    t = b[2] - b[3]
    return 0.0 if t <= 0 else (min(b[1], b[4]) - b[3]) / t


def upper_wick(b) -> float:
    t = b[2] - b[3]
    return 0.0 if t <= 0 else (b[2] - max(b[1], b[4])) / t


def body_ratio(b) -> float:
    t = b[2] - b[3]
    return 0.0 if t <= 0 else abs(b[4] - b[1]) / t


# ---------------------------------------------------------------------------
# Signal detector — parameterised on sweep_max, wick_min, reclaim_bars
# ---------------------------------------------------------------------------

def detect(ask_m5, mid_m15, ref_ticks, ent_start, ent_end,
           sweep_max, wick_min, reclaim_bars) -> tuple[int, str]:
    if not ref_ticks:
        return 0, "no_ref"
    ref_high = max(p for _, p in ref_ticks)
    ref_low  = min(p for _, p in ref_ticks)

    atr = atr14(mid_m15, ent_start)
    if atr <= 0:
        return 0, "zero_atr"

    window = [b for b in ask_m5 if ent_start <= b[0] < ent_end]
    if not window:
        return 0, "no_window"

    # Find first sweep
    si, side, sx = -1, None, 0.0
    for i, b in enumerate(window):
        ld = (ref_low - b[3]) / atr
        sd = (b[2] - ref_high) / atr
        ls, ss = ld >= SWEEP_ATR_MIN, sd >= SWEEP_ATR_MIN
        if not ls and not ss:
            continue
        if ls and ss:
            return 0, "ambiguous"
        si, side = i, ("long" if ls else "short")
        sx = b[3] if side == "long" else b[2]
        break
    if si < 0:
        return 0, "no_sweep"

    # Reclaim within reclaim_bars bars (inclusive of sweep bar)
    last_r = min(len(window) - 1, si + reclaim_bars - 1)
    ri, fail = -1, None
    for i in range(si, last_r + 1):
        b = window[i]
        if side == "long":
            sx = min(sx, b[3])
            if (ref_low - sx) / atr > sweep_max:
                fail = "too_deep"; break
            if b[4] > ref_low and b[4] < ref_high:
                if lower_wick(b) < wick_min:
                    fail = "weak_wick"; break
                ri = i; break
        else:
            sx = max(sx, b[2])
            if (sx - ref_high) / atr > sweep_max:
                fail = "too_deep"; break
            if b[4] < ref_high and b[4] > ref_low:
                if upper_wick(b) < wick_min:
                    fail = "weak_wick"; break
                ri = i; break
    if ri < 0:
        return 0, fail or "no_reclaim"

    if ri + 1 >= len(window):
        return 0, "no_displace"

    rc, dc = window[ri], window[ri + 1]
    if side == "long":
        ok = dc[4] > dc[1] and body_ratio(dc) >= DISP_BODY_MIN and dc[4] > (rc[2] + rc[3]) / 2
    else:
        ok = dc[4] < dc[1] and body_ratio(dc) >= DISP_BODY_MIN and dc[4] < (rc[2] + rc[3]) / 2
    if not ok:
        return 0, "displace_fail"

    dist = abs((dc[1] + dc[4]) / 2 - (sx - STOP_BUFF_ATR * atr if side == "long"
                                        else sx + STOP_BUFF_ATR * atr))
    if dist / atr < STOP_ATR_MIN or dist / atr > STOP_ATR_MAX:
        return 0, "stop_band"

    return 1, ""


# ---------------------------------------------------------------------------
# Load tick file
# ---------------------------------------------------------------------------

def load_ticks(path: Path) -> tuple[dict, dict]:
    ask_day: dict = defaultdict(list)
    mid_day: dict = defaultdict(list)
    print(f"  Loading {path.name} ({path.stat().st_size / 1e6:.0f} MB)...", end="", flush=True)
    with open(path, "r", newline="") as f:
        rdr = csv.reader(f, delimiter="\t")
        next(rdr)
        for row in rdr:
            if len(row) < 4:
                continue
            bs, as_ = row[2].strip(), row[3].strip()
            hb, ha = bs != "", as_ != ""
            if not hb and not ha:
                continue
            try:
                dt = datetime.strptime(row[0].strip() + " " + row[1].strip()[:8],
                                       "%Y.%m.%d %H:%M:%S")
            except ValueError:
                continue
            dk = row[0].strip()
            if ha:
                ask_day[dk].append((dt, float(as_)))
            if hb and ha:
                mid_day[dk].append((dt, (float(bs) + float(as_)) / 2))
    print(f" {len(ask_day)} days")
    return dict(ask_day), dict(mid_day)


# ---------------------------------------------------------------------------
# Pre-build per-day bars (once, outside the grid loop)
# ---------------------------------------------------------------------------

def prebuild(session_name: str, ask_day: dict, mid_day: dict) -> dict:
    sess = SESSIONS[session_name]
    day_data = {}
    for dk in sorted(ask_day):
        at = ask_day.get(dk, [])
        mt = mid_day.get(dk, [])
        if not at or not mt:
            continue
        y, mo, d = (int(x) for x in dk.split("."))
        if sess["ny_entry"]:
            rs = lw_to_srv(y, mo, d, sess["ref_start_lw"])
            re = lw_to_srv(y, mo, d, sess["ref_end_lw"])
            es = ny_to_srv(y, mo, d, sess["ny_entry_start_h"], sess["ny_entry_start_m"])
            ee = ny_to_srv(y, mo, d, sess["ny_entry_end_h"],   sess["ny_entry_end_m"])
        else:
            rs = lw_to_srv(y, mo, d, sess["ref_start_lw"])
            re = lw_to_srv(y, mo, d, sess["ref_end_lw"])
            es = lw_to_srv(y, mo, d, sess["entry_start_lw"])
            ee = lw_to_srv(y, mo, d, sess["entry_end_lw"])

        ref_ticks = [(dt, p) for dt, p in mt if rs <= dt < re]
        ask_m5    = build_bars([(dt, p) for dt, p in at], 5)
        mid_m15   = build_bars([(dt, p) for dt, p in mt], 15)
        day_data[dk] = (ask_m5, mid_m15, ref_ticks, es, ee)
    return day_data


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 72)
    print("Extended grid search: SWEEP_MAX x WICK_MIN x RECLAIM_BARS")
    print("=" * 72)

    # Load all tick files
    loaded: dict[str, tuple[dict, dict]] = {}
    for sym, path in TICK_FILES.items():
        if path.exists():
            loaded[sym] = load_ticks(path)
        else:
            print(f"  [SKIP] {sym}: file not found")

    # Per-session grid
    all_results: list[dict] = []

    for sname, sess in SESSIONS.items():
        sym = sess["symbol"]
        if sym not in loaded:
            continue
        print(f"\nProcessing {sname}...")
        ask_day, mid_day = loaded[sym]
        day_data = prebuild(sname, ask_day, mid_day)
        total_days = len(day_data)

        for rb in RECLAIM_BARS_CANDIDATES:
            for sm in SWEEP_MAX_CANDIDATES:
                for wm in WICK_MIN_CANDIDATES:
                    sigs = 0
                    reasons: dict = defaultdict(int)
                    for dk, (am5, mm15, rt, es, ee) in day_data.items():
                        found, reason = detect(am5, mm15, rt, es, ee, sm, wm, rb)
                        if found:
                            sigs += 1
                        else:
                            reasons[reason] += 1
                    all_results.append({
                        "session":     sname,
                        "reclaim_bars": rb,
                        "sweep_max":   sm,
                        "wick_min":    wm,
                        "days":        total_days,
                        "signals":     sigs,
                        "rate_pct":    sigs / total_days * 100 if total_days > 0 else 0.0,
                        "too_deep":    reasons.get("too_deep", 0),
                        "weak_wick":   reasons.get("weak_wick", 0),
                        "no_sweep":    reasons.get("no_sweep", 0),
                        "displace":    reasons.get("displace_fail", 0),
                        "stop_band":   reasons.get("stop_band", 0),
                    })

    # ---- Print per-session tables ----
    for sname in SESSIONS:
        rows = [r for r in all_results if r["session"] == sname]
        if not rows:
            continue
        print(f"\n{'='*72}")
        print(f"Results: {sname}  ({rows[0]['days']} days)")
        print(f"{'='*72}")
        hdr = (f"{'RB':<5}{'SWEEP_MAX':<12}{'WICK_MIN':<10}"
               f"{'Signals':<10}{'Rate%':<8}{'too_deep':<11}{'weak_wick':<10}")
        print(hdr)
        print("-" * len(hdr))
        prev_rb = None
        for r in rows:
            if r["reclaim_bars"] != prev_rb:
                if prev_rb is not None:
                    print()
                prev_rb = r["reclaim_bars"]
            baseline = r["sweep_max"] == 0.50 and r["wick_min"] == 0.60 and r["reclaim_bars"] == 3
            marker = " <-- baseline" if baseline else ""
            print(
                f"{r['reclaim_bars']:<5}{r['sweep_max']:<12.2f}{r['wick_min']:<10.2f}"
                f"{r['signals']:<10}{r['rate_pct']:<8.1f}"
                f"{r['too_deep']:<11}{r['weak_wick']:<10}{marker}"
            )

    # ---- Combined portfolio view ----
    print(f"\n{'='*72}")
    print("COMBINED PORTFOLIO (all 3 sessions summed)")
    print(f"{'='*72}")

    combos: dict = {}
    for r in all_results:
        k = (r["reclaim_bars"], r["sweep_max"], r["wick_min"])
        combos.setdefault(k, 0)
        combos[k] += r["signals"]

    # Reference: EURUSD day count for annualisation
    eu_days = next((r["days"] for r in all_results
                    if r["session"] == "EURUSD_LONDON"
                    and r["reclaim_bars"] == 3 and r["sweep_max"] == 0.50
                    and r["wick_min"] == 0.60), 196)

    hdr2 = (f"{'RB':<5}{'SWEEP_MAX':<12}{'WICK_MIN':<10}"
            f"{'Total Sigs':<13}{'Ann.~':<10}{'Challenge ETA*':<18}")
    print(hdr2)
    print("-" * len(hdr2))

    prev_rb = None
    for (rb, sm, wm), total in sorted(combos.items()):
        if rb != prev_rb:
            if prev_rb is not None:
                print()
            prev_rb = rb
        ann = total / eu_days * 252
        # wins needed ~17 (Phase1), at assumed 50% WR need ~34 signals
        eta_days = (34 / (total / eu_days)) if total > 0 else 99999
        eta_wks  = eta_days / 5
        baseline = rb == 3 and sm == 0.50 and wm == 0.60
        marker = " <-- baseline" if baseline else ""
        print(
            f"{rb:<5}{sm:<12.2f}{wm:<10.2f}"
            f"{total:<13}{ann:<10.0f}{eta_wks:<18.0f}{marker}"
        )

    print("\n* Challenge ETA = trading weeks to accumulate ~34 signals (17 wins at 50% WR needed for Phase 1)")

    # ---- Top 10 combinations ----
    print(f"\n{'='*72}")
    print("TOP 10 combinations by total signals (all 3 sessions combined)")
    print(f"{'='*72}")
    top10 = sorted(combos.items(), key=lambda x: x[1], reverse=True)[:10]
    print(f"{'Rank':<6}{'RB':<5}{'SWEEP_MAX':<12}{'WICK_MIN':<10}"
          f"{'Total Sigs':<13}{'Ann.~':<10}{'ETA (weeks)':<14}")
    print("-" * 60)
    for rank, ((rb, sm, wm), total) in enumerate(top10, 1):
        ann = total / eu_days * 252
        eta_wks = (34 / (total / eu_days)) / 5 if total > 0 else 99999
        print(f"{rank:<6}{rb:<5}{sm:<12.2f}{wm:<10.2f}{total:<13}{ann:<10.0f}{eta_wks:<14.0f}")

    # ---- Per-pair breakdown for the single best combo ----
    best_k, best_total = top10[0]
    best_rb, best_sm, best_wm = best_k
    print(f"\n--- Per-pair breakdown for best combo: RB={best_rb}, SWEEP_MAX={best_sm}, WICK_MIN={best_wm} ---")
    for r in all_results:
        if r["reclaim_bars"] == best_rb and r["sweep_max"] == best_sm and r["wick_min"] == best_wm:
            print(f"  {r['session']:<22} {r['signals']:>3} signals / {r['days']} days  ({r['rate_pct']:.1f}%)")


if __name__ == "__main__":
    main()
