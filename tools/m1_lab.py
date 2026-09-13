"""
M1 Lab — M1-resolution execution for the champion triad leg (2026-09-12)
========================================================================
User-uploaded M1 history (origin/main 578da08): all 11 pairs,
2024-09-11 -> 2026-09-11, validated against the Dukascopy API
(validation/HistoryData/m1-data/validation-report-m1.txt). Extracted
from git to /home/user/.cache/m1 (NOT committed; repo stays lean).

Method
------
* SIGNAL DETECTION UNCHANGED: champion relaxed geometry (sweep 0.02 ATR,
  wick 0.45, body 0.50), M5 bars, warm M15 ATR from the 4-year files,
  all-London session (07:00-11:00 London), T=1.5R, 90-min time-stop.
* EXECUTION: sim_triad walks 1-minute bars instead of 5-minute bars.
  This (a) resolves most of the stop-vs-target ordering ambiguity the
  M5 engine had to coin-flip, and (b) makes entry-expiry and
  breakeven-move variants testable at real resolution.

Objective (per user 2026-09-12): maximize profit — drawdown is
reported for reference only, not optimized.

Modes
-----
--fidelity : champion params, 2y window: M5 execution vs M1 execution
--grid     : T x time-stop + breakeven + entry-expiry (M1, 2y, core3)
--universe : champion params, per pair standalone (M1, 2y, all 11)
--confirm  : given configs on the M5 4y full window (M5 execution)
--combo    : best triad config + approved pairs + gold, one slot P0,
             M5 4y (delegates to tools/order_selector.py)
"""
from __future__ import annotations

import argparse
import csv
import os
import sys
import time
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

_LDN = ZoneInfo("Europe/London")

sys.path.insert(0, os.path.abspath("."))
import tools.aggressive_optimizer as m          # noqa: E402
import tools.optimizer_v2 as v2                 # noqa: E402
import tools.triad_honest as th                 # noqa: E402
import tools.order_selector as osel             # noqa: E402

M1_DIR = Path("/home/user/.cache/m1/validation/HistoryData/m1-data")
WIN0 = m.to_london_date(datetime(2024, 9, 11, tzinfo=timezone.utc))
WIN1 = m.to_london_date(datetime(2026, 9, 11, 1, 0, tzinfo=timezone.utc))
CORE3 = ["GBPJPY", "EURJPY", "XAUUSD"]
ALL11 = ["AUDUSD", "EURGBP", "EURJPY", "EURUSD", "GBPJPY", "GBPUSD",
         "NZDUSD", "USDCAD", "USDCHF", "USDJPY", "XAUUSD"]
T, TS, RISK = 1.5, 90, 0.015     # champion: 1.5R target, 90-min, 1.5%

_M1_CACHE: dict[tuple, dict] = {}


def load_m1(sym: str, keep_e=(11, 5)) -> dict:
    """{london_date: [Bar]} for the 06:30-keep_e London window — the bars
    the sim needs (signal fires >= 07:00; default session ends 11:00,
    pass keep_e=(13,35) for the extended-session variant). Parsed once
    per process."""
    key = (sym, keep_e)
    if key in _M1_CACHE:
        return _M1_CACHE[key]
    path = next(M1_DIR.glob(f"{sym.lower()}-m1-*.csv"))
    t0 = time.time()
    raw: dict = defaultdict(list)
    with open(path, newline="") as f:
        rdr = csv.reader(f)
        next(rdr)
        for row in rdr:
            ts = int(row[0]) // 1000
            raw[m.to_london_date(datetime.fromtimestamp(ts,
                                                         tz=timezone.utc))
                ].append((ts, row[1], row[2], row[3], row[4]))
    by_date: dict = {}
    for d, rs in raw.items():
        ws = m.lw_utc(d, 6, 30).timestamp()      # bar ts are in SECONDS
        we = m.lw_utc(d, 11, 5).timestamp()
        keep = sorted(r for r in rs if ws <= r[0] < we)
        if keep:
            by_date[d] = [m.Bar(datetime.fromtimestamp(r[0],
                                                       tz=timezone.utc),
                                float(r[1]), float(r[2]),
                                float(r[3]), float(r[4])) for r in keep]
    print(f"  loaded M1 {sym}: {len(by_date)} days "
          f"({time.time() - t0:.1f}s)", flush=True)
    _M1_CACHE[sym] = by_date
    return by_date


def restrict_m5(cache: dict) -> dict:
    """Same M5 cache limited to the M1 window (ATR map stays warm)."""
    out = {}
    for sym, (by_date, atr_map) in cache.items():
        out[sym] = ({d: bars for d, bars in by_date.items()
                     if WIN0 <= d <= WIN1},
                    {d: a for d, a in atr_map.items() if WIN0 <= d <= WIN1})
    return out


def fmt(r, label):
    pp = " ".join(f"{k}:{v[0]}/{v[1]:+.0f}" for k, v in r["per_pair"].items())
    return (f"{label:<34} n={r['n']:>3} WR={r['wr']*100:5.1f}% "
            f"PF={r['pf']:5.2f} AvgR={r['avg_r']:+.3f} | "
            f"${r['total']:>8.2f} DD={r['dd']:4.1f}% amb={r['amb']*100:4.1f}% "
            f"P1={'Y' if r['p1'] else 'n'}{'' if r['p1_days'] is None else str(r['p1_days'])}d"
            f" | {pp}")


def m1_bars(core3):
    def fn(sym, d):
        return load_m1(sym).get(d)   # lazy; cached per process
    return fn


# ---------------------------------------------------------------------------
def run_fidelity():
    print("=== FIDELITY: champion (relaxed, all-London, T=1.5, ts=90, "
          f"1.5%) 2y {WIN0} -> {WIN1} ===")
    osel.set_geometry(False)
    cache = v2.load_cache(osel.DATA_4Y)
    rc = restrict_m5(cache)
    uni = (CORE3, [])
    r5 = th.run_triad(rc, T, TS, uni, risk_frac=RISK)
    for s in CORE3:
        load_m1(s)
    r1 = th.run_triad(rc, T, TS, uni, risk_frac=RISK, sim_bars_fn=m1_bars(CORE3))
    print(fmt(r5, "M5 execution (baseline)"))
    print(fmt(r1, "M1 execution"))
    d = r1["total"] - r5["total"]
    print(f"\nM1 - M5 = ${d:+.2f}  ({d / max(abs(r5['total']), 1) * 100:+.1f}% of M5 total)")
    amb5 = sum(1 for t in r5["trades"] if t["ambiguous"])
    amb1 = sum(1 for t in r1["trades"] if t["ambiguous"])
    print(f"ambiguous stop/target bars: M5={amb5} of {r5['n']}  "
          f"M1={amb1} of {r1['n']}")
    return r5, r1


def run_grid():
    print(f"\n=== GRID (M1 execution, 2y, core3, 1.5%) ===")
    osel.set_geometry(False)
    cache = restrict_m5(v2.load_cache(osel.DATA_4Y))
    uni = (CORE3, [])
    rows = []
    for t in (1.0, 1.5, 2.0, 2.5):
        for ts in (60, 90, 120, 180):
            r = th.run_triad(cache, t, ts, uni, risk_frac=RISK,
                             sim_bars_fn=m1_bars(CORE3))
            rows.append((f"T{t}/ts{ts}", r))
            print(fmt(r, f"T={t} ts={ts}"), flush=True)
    for be in (0.5, 1.0):
        r = th.run_triad(cache, T, TS, uni, risk_frac=RISK,
                         sim_bars_fn=m1_bars(CORE3), breakeven_r=be)
        rows.append((f"BE{be}", r))
        print(fmt(r, f"T=1.5 ts=90 BE@{be}R"), flush=True)
    for ex in (15, 30, 60):
        r = th.run_triad(cache, T, TS, uni, risk_frac=RISK,
                         sim_bars_fn=m1_bars(CORE3), entry_expire_min=ex)
        rows.append((f"EX{ex}", r))
        print(fmt(r, f"T=1.5 ts=90 expire{ex}m"), flush=True)
    rows.sort(key=lambda x: -x[1]["total"])
    print("\nRanking by 2y M1 total PnL (profit objective):")
    for name, r in rows:
        print(f"  {name:<12} ${r['total']:>9.2f}  n={r['n']:>3} "
              f"PF={r['pf']:5.2f} AvgR={r['avg_r']:+.3f} DD={r['dd']:4.1f}%")


def run_universe():
    print(f"\n=== UNIVERSE SCAN (M1 execution, 2y, champion T=1.5 ts=90, "
          "standalone per pair) ===")
    osel.set_geometry(False)
    cache = restrict_m5(v2.load_cache(osel.DATA_4Y))
    rows = []
    for sym in ALL11:
        load_m1(sym)
        r = th.run_triad(cache, T, TS, ([sym], []), risk_frac=RISK,
                         sim_bars_fn=m1_bars([sym]))
        rows.append((sym, r))
        print(fmt(r, sym), flush=True)
    print("\nCandidates for the combo (need n>=20 AND PF>=1.2 AND total>0):")
    for sym, r in rows:
        ok = r["n"] >= 20 and (r["pf"] >= 1.2 if r["pf"] != float("inf") else True) \
            and r["total"] > 0
        print(f"  {sym:<8} n={r['n']:>3} PF={r['pf']:5.2f} "
              f"${r['total']:>9.2f} AvgR={r['avg_r']:+.3f} "
              f"{'APPROVE' if ok else '-'}")


def run_confirm():
    print(f"\n=== CONFIRM on M5 4y full window (M5 execution, lower "
          "fidelity, champion geometry) ===")
    osel.set_geometry(False)
    cache = v2.load_cache(osel.DATA_4Y)
    uni = (CORE3, [])
    r = th.run_triad(cache, T, TS, uni, risk_frac=RISK)
    print(fmt(r, "champion T1.5/ts90"))
    for t in (1.0, 2.0):
        r = th.run_triad(cache, t, TS, uni, risk_frac=RISK)
        print(fmt(r, f"T{t}/ts90"))
    for ts in (60, 120):
        r = th.run_triad(cache, T, ts, uni, risk_frac=RISK)
        print(fmt(r, f"T1.5/ts{ts}"))


def run_logic():
    """Different-logic battery, decided on the M5 4y window (honest
    confirmation), with M1 2y used for entry-resolution fidelity.
    All variants: champion geometry, core-3, T=1.5R, 90-min, 1.5%."""
    osel.set_geometry(False)
    cache = v2.load_cache(osel.DATA_4Y)
    uni = (CORE3, [])
    base_kw = dict(risk_frac=RISK)

    def one(label, **kw):
        r = th.run_triad(cache, T, TS, uni, **base_kw, **kw)
        print(fmt(r, label), flush=True)
        return r

    print("\n=== LOGIC BATTERY — M5 4y full window (decision set) ===")
    one("baseline (limit/time/11:00)")
    one("L1 market-entry nextbar", entry_mode="market")
    one("L2 strongest-sweep-first", order="sweep")
    one("L3 session-extend 13:30", session_end=(13, 30))
    one("L5 reclaim-window 3 (disp3)", disp_max=3)
    one("L6 reclaim-window 1 (disp1)", disp_max=1)
    # stop buffer variants (patched module constant, restored after)
    orig_buf = th.tsb.STOP_BUFFER_ATR
    try:
        th.tsb.STOP_BUFFER_ATR = 0.05
        one("L4a stop-buffer 0.05ATR")
        th.tsb.STOP_BUFFER_ATR = 0.20
        one("L4b stop-buffer 0.20ATR")
    finally:
        th.tsb.STOP_BUFFER_ATR = orig_buf
    # combo of the two promising non-overlapping ideas
    one("C1 market + strongest-sweep", entry_mode="market", order="sweep")
    one("C2 market + extend 13:30", entry_mode="market", session_end=(13, 30))

    # M1 2y fidelity for the entry-resolution-sensitive variants
    print("\n=== LOGIC (entry variants) — M1 2y fidelity check ===")
    rc = restrict_m5(cache)
    fn = m1_bars(CORE3)
    r5 = th.run_triad(rc, T, TS, uni, **base_kw)
    r1 = th.run_triad(rc, T, TS, uni, **base_kw, sim_bars_fn=fn)
    print(fmt(r5, "M5 baseline"))
    print(fmt(r1, "M1 baseline"))
    r5m = th.run_triad(rc, T, TS, uni, **base_kw, entry_mode="market")
    r1m = th.run_triad(rc, T, TS, uni, **base_kw, sim_bars_fn=fn,
                       entry_mode="market")
    print(fmt(r5m, "M5 market-entry"))
    print(fmt(r1m, "M1 market-entry"))
    d = r1m["total"] - r1["total"]
    print(f"\nM1 market-entry vs M1 baseline = ${d:+.2f}")


# ---------------------------------------------------------------------------
# Out-of-the-box battery (2026-09-12): compounding sizing, hour-of-day
# mining, NY-session JPY, and a NEW signal family (previous-day high/low
# liquidity sweeps) — all on the M5 4y decision window, D0a logic base.
# ---------------------------------------------------------------------------
D0A_BUF, D0A_END = 0.05, (13, 30)

# ---------------------------------------------------------------------------
# Per-pair strategy fit: which logic variant each pair should run.
# Selection on the 2y window (gate), confirmation on the 4y full window —
# bull-regime artifacts (e.g. T2.5) die in confirmation and fall back to
# the robust set {V0, V1, V2}.
# ---------------------------------------------------------------------------
VARIANTS = {
    "V0": dict(label="champion"),
    "V1": dict(label="D0a", end=(13, 30), buf=0.05),
    "V2": dict(label="D0a+nolate", end=(13, 30), buf=0.05,
               sig_hours={7, 8, 9, 10}),
    "V3": dict(label="extend", end=(13, 30)),
    "V4": dict(label="T2.0", T=2.0),
    "V5": dict(label="T2.5", T=2.5),
    "V6": dict(label="prevday", end=(13, 30), buf=0.05, prevday=True),
    "V7": dict(label="NY", ny=True),
    "V8": dict(label="loose-sweep", sweep=0.01),
    "V9": dict(label="ts120", end=(13, 30), buf=0.05, ts=120),
    "V10": dict(label="market", end=(13, 30), buf=0.05, mode="market"),
}
# variant -> order_selector PAIR_CFG mapping
VAR_CFG = {
    "V0": {}, "V1": {"buf": 0.05, "end": (13, 30)},
    "V2": {"buf": 0.05, "end": (13, 30), "no_late": True},
    "V3": {"end": (13, 30)}, "V4": {"T": 2.0}, "V5": {"T": 2.5},
    "V6": {"buf": 0.05, "end": (13, 30), "prevday": True},
    "V7": {"win": 1}, "V8": {"sweep": 0.01},
    "V9": {"buf": 0.05, "end": (13, 30), "ts": 120},
    "V10": {"buf": 0.05, "end": (13, 30), "mode": "market"},
}
ROBUST = ("V0", "V1", "V2")
PAIRFIT_JSON = Path("/tmp/pairfit_matrix.json")


def _run_variant(cache, sym, v, prev_hl=None):
    """Standalone single-pair run of variant v (champion geometry base)."""
    buf = v.get("buf", 0.10)
    sweep = v.get("sweep")
    orig_buf, orig_sweep = th.tsb.STOP_BUFFER_ATR, th.tsb.SWEEP_ATR_MIN
    orig_detect = th.detect
    th.tsb.STOP_BUFFER_ATR = buf
    if sweep is not None:
        th.tsb.SWEEP_ATR_MIN = sweep
    if v.get("prevday") and prev_hl is not None:
        from tools.triad_honest import detect as _orig

        def _pd(day_bars, ref_s, ref_e, ent_s, ent_e, atr, sym2,
                disp_max=2, ref_override=None, stop_buffer=None,
                sweep_min=None):
            phl = prev_hl.get(m.to_london_date(day_bars[0].ts))
            if phl is None:
                return None
            return _orig(day_bars, ref_s, ref_e, ent_s, ent_e, atr, sym2,
                         disp_max=disp_max, ref_override=phl,
                         stop_buffer=stop_buffer, sweep_min=sweep_min)
        th.detect = _pd
    try:
        uni = ([], [sym]) if v.get("ny") else ([sym], [])
        return th.run_triad(
            cache, v.get("T", T), v.get("ts", TS), uni, risk_frac=RISK,
            session_end=v.get("end", (11, 0)), sig_hours=v.get("sig_hours"),
            entry_mode=v.get("mode", "limit"))
    finally:
        th.tsb.STOP_BUFFER_ATR = orig_buf
        th.tsb.SWEEP_ATR_MIN = orig_sweep
        th.detect = orig_detect


def pair_matrix_stage1():
    """2y gate: every pair x every variant, standalone, 1.5%."""
    import json
    osel.set_geometry(False)
    cache4 = v2.load_cache(osel.DATA_4Y)
    rc = restrict_m5(cache4)
    out = {}
    for sym in ALL11:
        by_date = cache4[sym][0]
        ds = sorted(by_date)
        prev_hl = {}
        for i, d in enumerate(ds):
            if i > 0:
                bars = by_date[ds[i - 1]]
                prev_hl[d] = (max(b.high for b in bars),
                              min(b.low for b in bars))
        out[sym] = {}
        for vk, v in VARIANTS.items():
            r = _run_variant(rc, sym, v, prev_hl)
            out[sym][vk] = dict(n=r["n"], pf=r["pf"], total=r["total"],
                                avg_r=r["avg_r"], dd=r["dd"])
            print(f"  {sym:<8} {vk} {v['label']:<12} n={r['n']:>3} "
                  f"PF={r['pf']:5.2f} ${r['total']:>9.2f}", flush=True)
    PAIRFIT_JSON.write_text(json.dumps(out))
    print(f"\nwrote {PAIRFIT_JSON}")
    return out


def pair_matrix_stage2():
    """4y confirmation of each pair's 2y pick + portfolio combo."""
    import json
    mat = json.loads(PAIRFIT_JSON.read_text())
    osel.set_geometry(False)
    cache4 = v2.load_cache(osel.DATA_4Y)
    # prevday maps (4y) for confirmation runs
    prev_hls = {}
    for sym in ALL11:
        by_date = cache4[sym][0]
        ds = sorted(by_date)
        pm = {}
        for i, d in enumerate(ds):
            if i > 0:
                bars = by_date[ds[i - 1]]
                pm[d] = (max(b.high for b in bars), min(b.low for b in bars))
        prev_hls[sym] = pm

    def qualifies(x):
        return x["n"] >= 15 and x["total"] > 0 and \
            (x["pf"] >= 1.2 or x["pf"] == float("inf"))

    assignments, report = {}, []
    for sym in ALL11:
        m2 = mat[sym]
        cands = {k: x for k, x in m2.items() if qualifies(x)}
        pick = max(cands, key=lambda k: cands[k]["total"]) if cands else None
        final = None
        if pick is not None:
            r = _run_variant(cache4, sym, VARIANTS[pick], prev_hls[sym])
            if r["total"] > 0:
                final = (pick, r)
            else:  # bull artifact: fall back to robust set on 4y
                for k in ROBUST:
                    rr = _run_variant(cache4, sym, VARIANTS[k],
                                      prev_hls[sym])
                    if final is None or rr["total"] > final[1]["total"]:
                        final = (k, rr)
                if final is None or final[1]["total"] <= 0:
                    final = None
        if final is not None:
            k, r = final
            assignments[sym] = k
            report.append((sym, k, m2.get(k, {}), r))
        else:
            report.append((sym, "OFF", m2, None))
    print("\n=== PER-PAIR ASSIGNMENTS (2y pick -> 4y confirmed) ===")
    for sym, k, x2, r4 in report:
        x2s = (f"2y: n={x2.get('n')} ${x2.get('total', 0):+.0f}"
               if k in VARIANTS else "no 2y qualifier")
        r4s = (f"4y: n={r4['n']} PF={r4['pf']:.2f} ${r4['total']:+.0f}"
               if r4 is not None else "—")
        print(f"  {sym:<8} -> {k:<4} {VARIANTS.get(k, {}).get('label', 'off'):<12} "
              f"{x2s} | {r4s}", flush=True)

    # portfolio combo: assigned pairs (+ their cfgs) + gold, one slot P0
    if not assignments:
        print("no pairs assigned — nothing to combo")
        return
    osel.PAIR_CFG = {s: dict(VAR_CFG[k]) for s, k in assignments.items()}
    osel.TRIA_UNIVERSE = [(1, s, 0) for s in assignments]
    osel.TR_SIG_HOURS = None
    osel.RISK_TRIAD = 0.0175
    osel.COMPOUND = True
    th.tsb.STOP_BUFFER_ATR = 0.10     # per-pair cfg carries its own buf
    r = osel.run_combo(cache4, "P0", theta=0.0)
    tl = r["per_leg"].get("triad", [0, 0.0])
    gl = r["per_leg"].get("gold", [0, 0.0])
    print(f"\nPORTFOLIO COMBO (per-pair strategies + gold, P0, 1.75/3.0, "
          f"compound): n={r['n']} ${r['total']:.2f} CAGR={r['cagr']:.1f}% "
          f"DD={r['dd']:.1f}% P1={r['p1_days']}d | triad {tl[0]}/"
          f"{tl[1]:+.0f} gold {gl[0]}/{gl[1]:+.0f}")
    print(f"vs current best combo (uniform D0a+no-late+compound): $3,329.62")


def _d0a():
    osel.set_geometry(False)
    th.tsb.STOP_BUFFER_ATR = D0A_BUF


def run_box():
    print("=== OUT-OF-THE-BOX BATTERY — M5 4y, D0a base (buf 0.05, "
          "ext 13:30), core-3, 1.5% ===")
    _d0a()
    cache = v2.load_cache(osel.DATA_4Y)
    uni = (CORE3, [])
    base = dict(risk_frac=RISK, session_end=D0A_END)
    d0a = th.run_triad(cache, T, TS, uni, **base)
    print(fmt(d0a, "D0a (fixed-base)"))

    # 1) profit compounding (size off current equity)
    comp = th.run_triad(cache, T, TS, uni, **base, compound=True)
    print(fmt(comp, "D0a COMPOUNDED"))

    # 2) hour-of-day mining: bucket D0a trades by London signal hour
    from collections import defaultdict as _dd
    hb = _dd(lambda: [0, 0.0, 0.0, 0.0])
    for t in d0a["trades"]:
        h = t["sig_ts"].astimezone(_LDN).hour
        hb[h][0] += 1
        hb[h][1] += t["pnl"]
        if t["pnl"] > 0:
            hb[h][2] += t["pnl"]
        else:
            hb[h][3] += t["pnl"]
    print("\nhour-of-day buckets (D0a 4y):")
    for h in sorted(hb):
        n, tot, gw, gl = hb[h]
        pf = gw / abs(gl) if gl < 0 else float("inf")
        print(f"  {h:02d}:00  n={n:>3}  PF={pf:5.2f}  ${tot:>+8.2f}")
    neg_hours = {h for h, v in hb.items() if v[0] >= 5 and v[1] < 0}
    session_hours = {7, 8, 9, 10, 11, 12, 13}   # D0A 07:00-13:30 window
    if neg_hours:
        keep = session_hours - neg_hours
        r = th.run_triad(cache, T, TS, uni, **base, sig_hours=keep)
        print(fmt(r, f"D0a skip-hours {sorted(neg_hours)}"))
    # late signals (11:00-13:00) are negative in aggregate (n=6) but each
    # hour alone is under the n>=5 bar: test dropping them explicitly
    # while KEEPING the extended fill window (fills may still rest to 13:30)
    r = th.run_triad(cache, T, TS, uni, **base, sig_hours={7, 8, 9, 10})
    print(fmt(r, "D0a no-late-signals (sig<=10, fill to 13:30)"))

    # 3) NY session (13:30-16:00) for the JPY crosses — never tested
    r = th.run_triad(cache, T, TS, ([], ["GBPJPY", "EURJPY"]), **base)
    print(fmt(r, "NY-session JPY (D0a buf)"))
    r = th.run_triad(cache, T, TS, ([], ["GBPJPY", "EURJPY", "XAUUSD"]),
                     **base)
    print(fmt(r, "NY-session JPY+XAU (D0a buf)"))

    # 4) NEW signal family: previous-day high/low liquidity sweep
    _prevday_leg(cache)
    th.tsb.STOP_BUFFER_ATR = 0.10


def _prevday_leg(cache):
    """Liquidity-sweep leg: London sweep (>=0.02 ATR) of the PREVIOUS
    trading day's high/low, reclaim into the day's range, displacement.
    Same engine (detect geometry + sim_triad + run_triad slot loop) via a
    patched detector. Standalone per pair + core-3 combined, 4y, 1.5%."""
    from tools.triad_honest import detect as _orig_detect
    prev_hl = {}   # sym -> {date: (prev_h, prev_l)}
    for sym in CORE3:
        by_date = cache[sym][0]
        ds = sorted(by_date)
        pm = {}
        for i, d in enumerate(ds):
            if i > 0:
                bars = by_date[ds[i - 1]]
                pm[d] = (max(b.high for b in bars), min(b.low for b in bars))
        prev_hl[sym] = pm

    def detect_pd(day_bars, ref_s, ref_e, ent_s, ent_e, atr, sym,
                  disp_max=2):
        phl = prev_hl.get(sym, {}).get(m.to_london_date(day_bars[0].ts))
        if phl is None or atr <= 0:
            return None
        ref_h, ref_l = phl
        return _orig_detect(day_bars, ref_s, ref_e, ent_s, ent_e, atr, sym,
                            disp_max=disp_max, ref_override=(ref_h, ref_l))
    th.detect = detect_pd
    try:
        base = dict(risk_frac=RISK, session_end=D0A_END)
        r = th.run_triad(cache, T, TS, (CORE3, []), **base)
        pp = " ".join(f"{k}:{v[0]}/{v[1]:+.0f}" for k, v in r["per_pair"].items())
        print(f"\nPREVDAY-SWEEP leg (4y, D0a buf): n={r['n']:>3} "
              f"PF={r['pf']:5.2f} AvgR={r['avg_r']:+.3f} ${r['total']:>8.2f} "
              f"DD={r['dd']:4.1f}% | {pp}")
    finally:
        th.detect = _orig_detect


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fidelity", action="store_true")
    ap.add_argument("--grid", action="store_true")
    ap.add_argument("--universe", action="store_true")
    ap.add_argument("--confirm", action="store_true")
    ap.add_argument("--logic", action="store_true")
    ap.add_argument("--box", action="store_true")
    ap.add_argument("--pairfit", type=int, choices=[1, 2], default=None,
                    help="per-pair strategy fit: 1=2y matrix (writes "
                         "/tmp/pairfit_matrix.json), 2=4y confirm + "
                         "portfolio combo")
    args = ap.parse_args()
    if not any([args.fidelity, args.grid, args.universe, args.confirm,
                args.logic, args.box, args.pairfit is not None]):
        ap.print_help()
        return
    if args.fidelity:
        run_fidelity()
    if args.grid:
        run_grid()
    if args.universe:
        run_universe()
    if args.confirm:
        run_confirm()
    if args.logic:
        run_logic()
    if args.box:
        run_box()
    if args.pairfit == 1:
        pair_matrix_stage1()
    if args.pairfit == 2:
        pair_matrix_stage2()


if __name__ == "__main__":
    main()
