"""
Multi-pair parameter grid search — EURUSD London, GBPUSD London, USDJPY New York.

For each pair/session combination, tests a coarse grid of:
  SWEEP_ATR_MAX  : how deep the sweep can go before the reclaim window expires
  RECLAIM_WICK_MIN : minimum wick ratio on the reclaim bar

Reports signal count, signal rate, and breakdown of rejection reasons
so we can pick the best relaxed-but-principled parameter values.

Usage:
    python tools/multi_pair_grid_search.py
"""
from __future__ import annotations

import csv
import sys
from collections import defaultdict
from datetime import date, datetime, timedelta
from pathlib import Path

# ---------------------------------------------------------------------------
# Frozen geometry (only SWEEP_ATR_MAX and RECLAIM_WICK_MIN are varied)
# ---------------------------------------------------------------------------
SWEEP_ATR_MIN      = 0.05
DISP_BODY_MIN      = 0.60
STOP_BUFF_ATR      = 0.10
STOP_ATR_MIN       = 0.60
STOP_ATR_MAX       = 1.50
SERVER_UTC_OFFSET  = 3   # Eightcap UTC+3

# Grid to search
SWEEP_MAX_CANDIDATES = [0.50, 0.60, 0.75, 1.00, 1.25]
WICK_MIN_CANDIDATES  = [0.60, 0.50, 0.45, 0.40]

# ---------------------------------------------------------------------------
# Instrument specs
# ---------------------------------------------------------------------------
INSTRUMENTS = {
    "EURUSD": {"tick_size": 0.00001, "tick_value": 10.0,  "contract": 100_000},
    "GBPUSD": {"tick_size": 0.00001, "tick_value": 10.0,  "contract": 100_000},
    "USDJPY": {"tick_size": 0.001,   "tick_value":  9.09, "contract": 100_000},
}

# ---------------------------------------------------------------------------
# Session definitions
# Sessions: (ref_start_london_h, ref_end_london_h,
#             entry_start_london_h, entry_end_london_h,
#             uses_ny_dst)   [all as Europe/London wall hours]
# For USDJPY NY:
#   ref   = 07:00-13:00 Europe/London
#   entry = 08:30-11:00 America/New_York  -> expressed relative to London wall
# ---------------------------------------------------------------------------
SESSIONS = {
    "EURUSD_LONDON": {
        "symbol": "EURUSD",
        "ref_start_lw":   0,   # 00:00 London wall
        "ref_end_lw":     7,   # 07:00 London wall
        "entry_start_lw": 7,   # 07:00 London wall
        "entry_end_lw":   11,  # 11:00 London wall
        "ny_entry": False,
    },
    "GBPUSD_LONDON": {
        "symbol": "GBPUSD",
        "ref_start_lw":   0,
        "ref_end_lw":     7,
        "entry_start_lw": 7,
        "entry_end_lw":   11,
        "ny_entry": False,
    },
    "USDJPY_NEWYORK": {
        "symbol": "USDJPY",
        "ref_start_lw":   7,   # 07:00 London wall
        "ref_end_lw":     13,  # 13:00 London wall
        "entry_start_lw": None,  # computed from NY DST below
        "entry_end_lw":   None,
        "ny_entry": True,
        # NY entry: 08:30-11:00 America/New_York
        "ny_entry_start_h": 8,
        "ny_entry_start_m": 30,
        "ny_entry_end_h":   11,
        "ny_entry_end_m":   0,
    },
}

# ---------------------------------------------------------------------------
# DST helpers
# ---------------------------------------------------------------------------

def _last_sunday(year: int, month: int) -> date:
    if month == 12:
        nxt = date(year + 1, 1, 1)
    else:
        nxt = date(year, month + 1, 1)
    last = nxt - timedelta(days=1)
    return last - timedelta(days=(last.weekday() + 1) % 7)


def london_offset(d: date) -> int:
    """London UTC offset: +1 (BST Apr-Oct) or 0 (GMT)."""
    yr = d.year
    if _last_sunday(yr, 3) <= d < _last_sunday(yr, 10):
        return 1
    return 0


def ny_offset(d: date) -> int:
    """New York UTC offset: -4 (EDT Mar-Nov) or -5 (EST)."""
    yr = d.year
    # US DST: 2nd Sunday March -> 1st Sunday November
    # 2nd Sunday March
    first_sun_mar = date(yr, 3, 1) + timedelta(days=(6 - date(yr, 3, 1).weekday()) % 7)
    edt_start = first_sun_mar + timedelta(weeks=1)
    # 1st Sunday November
    edt_end = date(yr, 11, 1) + timedelta(days=(6 - date(yr, 11, 1).weekday()) % 7)
    if edt_start <= d < edt_end:
        return -4
    return -5


def london_wall_to_server(yr: int, mo: int, da: int, h: int, m: int = 0) -> datetime:
    """Convert London civil wall time to server (UTC+3)."""
    wall_utc = datetime(yr, mo, da, h, m) - timedelta(hours=london_offset(date(yr, mo, da)))
    return wall_utc + timedelta(hours=SERVER_UTC_OFFSET)


def ny_wall_to_server(yr: int, mo: int, da: int, h: int, m: int = 0) -> datetime:
    """Convert NY civil wall time to server (UTC+3)."""
    wall_utc = datetime(yr, mo, da, h, m) - timedelta(hours=ny_offset(date(yr, mo, da)))
    return wall_utc + timedelta(hours=SERVER_UTC_OFFSET)


# ---------------------------------------------------------------------------
# Bar building helpers
# ---------------------------------------------------------------------------

def bar_key(dt: datetime, period: int) -> datetime:
    t = dt.hour * 60 + dt.minute
    f = t // period * period
    return dt.replace(hour=f // 60, minute=f % 60, second=0, microsecond=0)


def build_bars(ticks, period):
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
    return [bm[k] for k in sorted(bm)]  # [time, open, high, low, close]


def compute_atr14(bars, before: datetime) -> float:
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
# Signal detector (parameterised)
# ---------------------------------------------------------------------------

def count_signals_for_day(
    ask_bars_m5, mid_bars_m15,
    ref_ticks_mid,
    ent_start: datetime, ent_end: datetime,
    sweep_max: float, wick_min: float,
) -> tuple[int, str]:
    """
    Returns (1, '') if signal found, (0, reason) if not.
    """
    if not ref_ticks_mid:
        return 0, "no_ref"
    ref_high = max(p for _, p in ref_ticks_mid)
    ref_low  = min(p for _, p in ref_ticks_mid)

    atr = compute_atr14(mid_bars_m15, ent_start)
    if atr <= 0:
        return 0, "zero_atr"

    window = [b for b in ask_bars_m5 if ent_start <= b[0] < ent_end]
    if not window:
        return 0, "no_window"

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
            return 0, "ambiguous"
        si, side = i, ("long" if ls else "short")
        sx = b[3] if side == "long" else b[2]
        break
    if si < 0:
        return 0, "no_sweep"

    # Reclaim within 3 bars
    last_r = min(len(window) - 1, si + 2)
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
        ok = (dc[4] > dc[1] and body_ratio(dc) >= DISP_BODY_MIN
              and dc[4] > (rc[2] + rc[3]) / 2)
    else:
        ok = (dc[4] < dc[1] and body_ratio(dc) >= DISP_BODY_MIN
              and dc[4] < (rc[2] + rc[3]) / 2)
    if not ok:
        return 0, "displace_fail"

    entry = (dc[1] + dc[4]) / 2
    raw_stop = sx - STOP_BUFF_ATR * atr if side == "long" else sx + STOP_BUFF_ATR * atr
    dist = abs(entry - raw_stop)
    if dist / atr < STOP_ATR_MIN or dist / atr > STOP_ATR_MAX:
        return 0, "stop_band"

    return 1, ""


# ---------------------------------------------------------------------------
# Load one tick file
# ---------------------------------------------------------------------------

def load_tick_file(path: Path) -> tuple[dict, dict]:
    """Returns (ask_day, mid_day) dicts keyed by 'YYYY.MM.DD' string."""
    ask_day: dict = defaultdict(list)
    mid_day: dict = defaultdict(list)
    total = 0
    print(f"  Loading {path.name} ({path.stat().st_size / 1e6:.0f} MB) ...", end="", flush=True)
    with open(path, "r", newline="") as f:
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
                dt = datetime.strptime(
                    row[0].strip() + " " + row[1].strip()[:8], "%Y.%m.%d %H:%M:%S"
                )
            except ValueError:
                continue
            day_key = row[0].strip()
            if has_ask:
                ask_day[day_key].append((dt, float(as_)))
            if has_bid and has_ask:
                mid_day[day_key].append((dt, (float(bs) + float(as_)) / 2))
            total += 1
    print(f" {total:,} ticks, {len(ask_day)} days")
    return dict(ask_day), dict(mid_day)


# ---------------------------------------------------------------------------
# Run grid search for one session
# ---------------------------------------------------------------------------

def run_grid(session_name: str, ask_day: dict, mid_day: dict) -> list[dict]:
    sess = SESSIONS[session_name]
    results = []

    # Pre-build bars per day (expensive — do once outside the grid)
    day_data = {}  # day_key -> (ask_m5, mid_m15, ref_ticks)
    for day_key in sorted(ask_day.keys()):
        aticks = ask_day.get(day_key, [])
        mticks = mid_day.get(day_key, [])
        if not aticks or not mticks:
            continue
        y, mo, d = (int(x) for x in day_key.split("."))
        dobj = date(y, mo, d)

        if sess["ny_entry"]:
            ref_start_srv = london_wall_to_server(y, mo, d, sess["ref_start_lw"])
            ref_end_srv   = london_wall_to_server(y, mo, d, sess["ref_end_lw"])
            ent_start_srv = ny_wall_to_server(y, mo, d,
                                              sess["ny_entry_start_h"],
                                              sess["ny_entry_start_m"])
            ent_end_srv   = ny_wall_to_server(y, mo, d,
                                              sess["ny_entry_end_h"],
                                              sess["ny_entry_end_m"])
        else:
            ref_start_srv = london_wall_to_server(y, mo, d, sess["ref_start_lw"])
            ref_end_srv   = london_wall_to_server(y, mo, d, sess["ref_end_lw"])
            ent_start_srv = london_wall_to_server(y, mo, d, sess["entry_start_lw"])
            ent_end_srv   = london_wall_to_server(y, mo, d, sess["entry_end_lw"])

        ref_ticks = [(dt, p) for dt, p in mticks if ref_start_srv <= dt < ref_end_srv]
        ask_m5    = build_bars([(dt, p) for dt, p in aticks], 5)
        mid_m15   = build_bars([(dt, p) for dt, p in mticks], 15)
        day_data[day_key] = (ask_m5, mid_m15, ref_ticks, ent_start_srv, ent_end_srv)

    total_days = len(day_data)

    for sweep_max in SWEEP_MAX_CANDIDATES:
        for wick_min in WICK_MIN_CANDIDATES:
            signals = 0
            reasons: dict = defaultdict(int)

            for day_key, (ask_m5, mid_m15, ref_ticks, es, ee) in day_data.items():
                found, reason = count_signals_for_day(
                    ask_m5, mid_m15, ref_ticks, es, ee, sweep_max, wick_min
                )
                if found:
                    signals += 1
                else:
                    reasons[reason] += 1

            results.append({
                "session":     session_name,
                "sweep_max":   sweep_max,
                "wick_min":    wick_min,
                "days":        total_days,
                "signals":     signals,
                "rate_pct":    signals / total_days * 100 if total_days > 0 else 0.0,
                "too_deep":    reasons.get("too_deep", 0),
                "weak_wick":   reasons.get("weak_wick", 0),
                "no_sweep":    reasons.get("no_sweep", 0),
                "displace":    reasons.get("displace_fail", 0),
            })
    return results


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

TICK_FILES = {
    "EURUSD": Path("validation/HistoryData/EURUSD.i_202406190501_202609102250.csv"),
    "GBPUSD": Path("validation/HistoryData/GBPUSD.i_202406190501_202609110308.csv"),
    "USDJPY": Path("validation/HistoryData/USDJPY.i_202406190501_202609110308.csv"),
}


def main():
    print("=" * 70)
    print("Multi-pair parameter grid search")
    print("=" * 70)

    all_results: list[dict] = []

    for session_name, sess in SESSIONS.items():
        sym = sess["symbol"]
        tick_file = TICK_FILES.get(sym)
        if tick_file is None or not tick_file.exists():
            print(f"\n[SKIP] {session_name}: file not found")
            continue
        print(f"\n--- {session_name} ---")
        ask_day, mid_day = load_tick_file(tick_file)
        results = run_grid(session_name, ask_day, mid_day)
        all_results.extend(results)

    # Print results per session
    for session_name in SESSIONS:
        sess_results = [r for r in all_results if r["session"] == session_name]
        if not sess_results:
            continue
        print(f"\n{'='*70}")
        print(f"Results: {session_name}")
        print(f"{'='*70}")
        hdr = (f"{'SWEEP_MAX':<12}{'WICK_MIN':<10}{'Days':<7}"
               f"{'Signals':<10}{'Rate%':<8}{'too_deep':<11}{'weak_wick':<11}{'no_sweep':<10}")
        print(hdr)
        print("-" * len(hdr))
        for r in sess_results:
            marker = " <-- baseline" if r["sweep_max"] == 0.50 and r["wick_min"] == 0.60 else ""
            print(
                f"{r['sweep_max']:<12.2f}{r['wick_min']:<10.2f}{r['days']:<7}"
                f"{r['signals']:<10}{r['rate_pct']:<8.1f}"
                f"{r['too_deep']:<11}{r['weak_wick']:<11}{r['no_sweep']:<10}{marker}"
            )

    # Combined portfolio view: sum signals across all 3 sessions per param combo
    print(f"\n{'='*70}")
    print("COMBINED PORTFOLIO (EURUSD_LONDON + GBPUSD_LONDON + USDJPY_NEWYORK)")
    print("Note: on same calendar day, at most 1 trade allowed — combined = opportunity set")
    print(f"{'='*70}")
    combos: dict = {}
    for r in all_results:
        k = (r["sweep_max"], r["wick_min"])
        if k not in combos:
            combos[k] = {"signals": 0, "days_set": set()}
        combos[k]["signals"] += r["signals"]

    # Use EURUSD day count as proxy for calendar days
    eu_days = next((r["days"] for r in all_results
                    if r["session"] == "EURUSD_LONDON" and r["sweep_max"] == 0.50
                    and r["wick_min"] == 0.60), 196)

    hdr2 = f"{'SWEEP_MAX':<12}{'WICK_MIN':<10}{'Total Signals':<16}{'Per 196 days':<16}{'Annualised*':<14}"
    print(hdr2)
    print("-" * len(hdr2))
    for (sm, wm), d in sorted(combos.items()):
        s = d["signals"]
        ann = s / eu_days * 252  # ~252 trading days/year
        marker = " <-- baseline" if sm == 0.50 and wm == 0.60 else ""
        print(f"{sm:<12.2f}{wm:<10.2f}{s:<16}{s:<16}{ann:<14.0f}{marker}")

    print("\n* Annualised assumes same signal rate holds across a full trading year (252 days)")
    print("\n--- Challenge context ---")
    print("Phase 1 needs +10% = +$250.  Profile A: 0.40% risk x 1.50R = ~$15 net per win.")
    print("Wins needed for Phase 1: ~17.  At 50% win rate: need ~34 signals.")
    print()
    # Find recommended combo
    best = max(combos.items(), key=lambda x: x[1]["signals"])
    bsm, bwm = best[0]
    bsigs = best[1]["signals"]
    print(f"Best combined: SWEEP_MAX={bsm}, WICK_MIN={bwm} -> {bsigs} signals / {eu_days} days")
    ann_best = bsigs / eu_days * 252
    days_for_34 = 34 / (bsigs / eu_days)
    print(f"  Annualised: ~{ann_best:.0f} signals/year")
    print(f"  Days to accumulate 34 signals: ~{days_for_34:.0f} ({days_for_34/5:.0f} trading weeks)")


if __name__ == "__main__":
    main()
