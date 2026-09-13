"""
S/R + Price-Action + Volume Lab — new strategy families (2026-09-13)
=====================================================================
User request: "try different strategy like support and resistance, price
action, volume — check how can increase our ROI."

Three genuinely different logic families, all on the SAME honest engine
(M5 bars, re-touch limit fills, coin ambiguity, raw costs, per-day pip
values, one slot, T=1.5R / 90-min / 11:00 session end unless noted):

S/R family (multi-day liquidity — the triad detector generalized to
    N-day references, plus a breakout-AND-RETEST variant):
      S1  3-day high/low sweep + reclaim  (detect geometry, ref = 3d H/L)
      S2  5-day high/low sweep + reclaim  (weekly)
      S3  10-day high/low sweep + reclaim
      S4  5-day H/L breakout & retest     (break the level, enter the
          retest of the broken level — NOT a rider; London ORB riders
          have ZERO follow-through, findings_fast_track_lab.md F3)

Price-action family (candle-structure setups, no prior-range sweep):
      PA1 inside-bar breakout   (break of the mother bar, stop opposite)
      PA2 pin-bar rejection     (wick sweeps the Asian edge >=0.02 ATR,
                                 wick >= 0.60, close back inside)
      PA3 engulfing bar         (body engulfs the prior opposite body,
                                 range >= 0.3 ATR)
      PA4 outside-bar follow    (range expands both sides, body >= 0.50,
                                 range >= 0.5 ATR, enter in close dir)

Volume family (tick volume — DATA CONSTRAINT: volume exists in the files
    only from 2024-01-10, i.e. exactly the 2y gate window. 4y
    CONFIRMATION IS IMPOSSIBLE for these; they are reported as
    "2y-only, unconfirmed" and are NOT certifiable into the stack with
    this dataset):
      V1  volume-spike displacement (vol >= 3x 20-bar avg, body >= 0.60
          ratio, body >= 0.3 ATR, enter in spike direction)
      V2  POC retrace (volume-weighted 07:00-09:00 price = POC; trend
          away from POC by >= 0.1 ATR by 09:00; enter the retrace to
          POC in trend direction, stop 0.65 ATR beyond POC)
      V3  low-volume new-extreme exhaustion (new window extreme on
          vol <= 0.5x 20-bar avg -> fade)

Protocol (same as the per-pair fit, findings_m1_lab.md §9): selection on
the 2y gate only (n>=15, PF>=1.2, total>0, max $ per pair); confirmation
on the 4y window for the S/R and PA families (volume family: none
possible — reported as-is). Portfolio test: confirmed signals added to
the frozen per-pair 5-pair stack under the one slot vs $3,811.34.

Usage
-----
  python tools/sr_pa_lab.py --stage1    # 2y matrix 11 pairs x 11 variants
  python tools/sr_pa_lab.py --stage2    # 4y confirm + portfolio ablation
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import sys
import time
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, os.path.abspath("."))
import tools.aggressive_optimizer as m      # noqa: E402
import tools.optimizer_v2 as v2             # noqa: E402
import tools.triad_honest as th             # noqa: E402
import tools.order_selector as osel         # noqa: E402

DATA_DIR4 = v2.DATA_4Y
DATA_DIR2 = v2.DATA_2Y
ALL11 = ["AUDUSD", "EURGBP", "EURJPY", "EURUSD", "GBPJPY", "GBPUSD",
         "NZDUSD", "USDCAD", "USDCHF", "USDJPY", "XAUUSD"]
RISK = 0.015
T, TS = 1.5, 90
MATRIX_JSON = Path("/tmp/srpa_matrix.json")
SM = th.tsb.SWEEP_ATR_MIN          # 0.02 relaxed
BUF = th.tsb.STOP_BUFFER_ATR       # 0.10


# ---------------------------------------------------------------------------
# Reference levels & volume maps
# ---------------------------------------------------------------------------
def n_day_levels(cache, sym, n):
    """{date: (high, low)} of the previous n bar-days (any bars that day)."""
    by_date = cache[sym][0]
    ds = sorted(by_date)
    pos = {d: i for i, d in enumerate(ds)}
    out = {}
    for d in ds:
        i = pos[d]
        if i < n:
            continue
        seg = ds[i - n:i]
        h, l = None, None
        for dd in seg:
            for b in by_date[dd]:
                h = b.high if h is None or b.high > h else h
                l = b.low if l is None or b.low < l else l
        out[d] = (h, l)
    return out


def load_vol(data_dir, syms):
    """{sym: {date: [(ts, vol), ...]}} for London 00:00-11:05 bars only
    (everything the volume detectors need)."""
    out = {}
    for sym in syms:
        files = list(data_dir.glob(f"{sym.lower()}-m5-*.csv"))
        if not files:
            out[sym] = {}
            continue
        path = max(files, key=lambda p: p.stat().st_size)
        by_date: dict = defaultdict(list)
        with open(path, newline="") as f:
            rdr = csv.reader(f)
            next(rdr)
            for row in rdr:
                if len(row) < 6:
                    continue
                try:
                    ts = int(row[0]) // 1000
                    v = int(row[5])
                except ValueError:
                    continue
                dt = datetime.fromtimestamp(ts, tz=timezone.utc)
                ldn = m.to_london_date(dt)
                # keep 00:00-11:05 London wall time (same wall clock
                # m.lw_utc uses); keys are INT seconds (Bar.ts.timestamp())
                ws = m.lw_utc(ldn, 0).timestamp()
                we = m.lw_utc(ldn, 11, 5).timestamp()
                if ws <= ts < we:
                    by_date[ldn].append((ts, v))
        out[sym] = {d: sorted(rs) for d, rs in by_date.items()}
    return out


# ---------------------------------------------------------------------------
# Detectors. Signature: fn(day_bars, ref_s, ref_e, ent_s, ent_e, atr, sym)
# -> signal dict (compatible with th.sim_triad) or None.
# All: London window (ref = Asian 00:00-07:00, entry window 07:00-end),
# limit at the signal price, one signal per day.
# ---------------------------------------------------------------------------
def _base_sig(side, entry, stop, ts, bar_ts, extreme, body_ratio, wick_ratio,
              sweep_atr):
    return dict(side=side, entry=entry, stop=stop, sig_ts=ts,
                extreme=extreme, body_ratio=body_ratio,
                wick_ratio=wick_ratio, sweep_atr=sweep_atr)


def _band_ok(entry, stop, atr):
    d = abs(entry - stop)
    return 0.40 * atr <= d <= 1.50 * atr


def make_sweep_reclaim(refs):
    """S1-S3: N-day H/L sweep + reclaim + displacement — the certified
    triad geometry (th.detect) with the reference overridden to N-day
    high/low."""
    orig = th.detect

    def det(day_bars, ref_s, ref_e, ent_s, ent_e, atr, sym,
            disp_max=2, ref_override=None, stop_buffer=None,
            sweep_min=None):
        rl = refs.get(m.to_london_date(day_bars[0].ts))
        if rl is None or atr <= 0:
            return None
        return orig(day_bars, ref_s, ref_e, ent_s, ent_e, atr, sym,
                    disp_max=disp_max, ref_override=rl)
    return det


def make_breakout_retest(refs):
    """S4: close breaks the 5-day level, then a retest of the broken
    level -> limit at the level, stop beyond the retest extreme.
    First break event in the window wins; band 0.4-1.5 ATR."""
    def det(day_bars, ref_s, ref_e, ent_s, ent_e, atr, sym, **kw):
        rl = refs.get(m.to_london_date(day_bars[0].ts))
        if rl is None or atr <= 0:
            return None
        ref_h, ref_l = rl
        win = [b for b in day_bars if ent_s <= b.ts < ent_e]
        if len(win) < 3:
            return None
        break_i, side = -1, None
        for i, b in enumerate(win):
            if b.close > ref_h:
                break_i, side = i, "long"
                break
            if b.close < ref_l:
                break_i, side = i, "short"
                break
        if break_i < 0:
            return None
        level = ref_h if side == "long" else ref_l
        extreme = win[break_i].low if side == "long" else win[break_i].high
        rec_i = -1
        for j in range(break_i + 1, min(len(win), break_i + 13)):
            b = win[j]
            if side == "long" and b.low <= level:
                extreme = min(extreme, b.low)
                rec_i = j
                break
            if side == "short" and b.high >= level:
                extreme = max(extreme, b.high)
                rec_i = j
                break
        if rec_i < 0:
            return None
        stop = extreme - 0.05 * atr if side == "long" else extreme + 0.05 * atr
        if not _band_ok(level, stop, atr):
            return None
        return _base_sig(side, level, stop,
                         win[rec_i].ts + _five(), win[rec_i].ts, extreme,
                         0.6, 0.6,
                         ((ref_l - extreme) / atr if side == "long"
                          else (extreme - ref_h) / atr))
    return det


def _five():
    from datetime import timedelta
    return timedelta(minutes=5)


def make_inside_bar():
    """PA1: inside bar (mother range >= 0.5 ATR), then close breaks the
    mother -> limit at the mother extreme, stop at the other side."""
    def det(day_bars, ref_s, ref_e, ent_s, ent_e, atr, sym, **kw):
        if atr <= 0:
            return None
        win = [b for b in day_bars if ent_s <= b.ts < ent_e]
        for i in range(1, len(win) - 1):
            mo, ib = win[i - 1], win[i]
            if mo.high - mo.low < 0.5 * atr:
                continue
            if not (ib.high < mo.high and ib.low > mo.low):
                continue
            j = i + 1
            b = win[j]
            if b.close > mo.high:
                side, entry, stop = "long", mo.high, mo.low
            elif b.close < mo.low:
                side, entry, stop = "short", mo.low, mo.high
            else:
                continue
            if not _band_ok(entry, stop, atr):
                continue
            return _base_sig(side, entry, stop,
                             b.ts + _five(), b.ts,
                             mo.low if side == "long" else mo.high,
                             th.body_ratio(b), th.wick_ratio(b, side), 0.2)
        return None
    return det


def make_pin_bar():
    """PA2: pin bar sweeps the Asian edge by >= SM ATR, wick >= 0.60,
    close back inside the range -> enter the rejection at the pin
    midpoint, stop beyond the wick extreme."""
    def det(day_bars, ref_s, ref_e, ent_s, ent_e, atr, sym, **kw):
        if atr <= 0:
            return None
        pre = [b for b in day_bars if ref_s <= b.ts < ref_e]
        if len(pre) < 12:
            return None
        ref_h = max(b.high for b in pre)
        ref_l = min(b.low for b in pre)
        win = [b for b in day_bars if ent_s <= b.ts < ent_e]
        for b in win:
            if (b.low < ref_l - SM * atr
                    and ref_l < b.close < ref_h
                    and th.wick_ratio(b, "long") >= 0.60):
                entry = (b.open + b.close) / 2.0
                stop = b.low - 0.05 * atr
                if _band_ok(entry, stop, atr):
                    return _base_sig("long", entry, stop, b.ts + _five(),
                                     b.ts, b.low, th.body_ratio(b),
                                     th.wick_ratio(b, "long"),
                                     (ref_l - b.low) / atr)
            if (b.high > ref_h + SM * atr
                    and ref_l < b.close < ref_h
                    and th.wick_ratio(b, "short") >= 0.60):
                entry = (b.open + b.close) / 2.0
                stop = b.high + 0.05 * atr
                if _band_ok(entry, stop, atr):
                    return _base_sig("short", entry, stop, b.ts + _five(),
                                     b.ts, b.high, th.body_ratio(b),
                                     th.wick_ratio(b, "short"),
                                     (b.high - ref_h) / atr)
        return None
    return det


def make_engulfing():
    """PA3: bar body engulfs the previous opposite-direction body
    (range >= 0.3 ATR) -> limit at the engulfing midpoint, stop beyond
    the engulfing low/high."""
    def det(day_bars, ref_s, ref_e, ent_s, ent_e, atr, sym, **kw):
        if atr <= 0:
            return None
        win = [b for b in day_bars if ent_s <= b.ts < ent_e]
        for i in range(1, len(win)):
            p, b = win[i - 1], win[i]
            if b.high - b.low < 0.3 * atr:
                continue
            if p.close < p.open and b.close > b.open \
                    and b.close >= p.open and b.open <= p.close:
                entry = (b.open + b.close) / 2.0
                stop = b.low - 0.05 * atr
                if _band_ok(entry, stop, atr):
                    return _base_sig("long", entry, stop, b.ts + _five(),
                                     b.ts, b.low, th.body_ratio(b),
                                     th.wick_ratio(b, "long"), 0.2)
            if p.close > p.open and b.close < b.open \
                    and b.close <= p.open and b.open >= p.close:
                entry = (b.open + b.close) / 2.0
                stop = b.high + 0.05 * atr
                if _band_ok(entry, stop, atr):
                    return _base_sig("short", entry, stop, b.ts + _five(),
                                     b.ts, b.high, th.body_ratio(b),
                                     th.wick_ratio(b, "short"), 0.2)
        return None
    return det


def make_outside_bar():
    """PA4: outside bar (expands the prior bar both sides), range >= 0.5
    ATR, body ratio >= 0.50 -> enter in the close direction at the
    midpoint, stop beyond the opposite extreme."""
    def det(day_bars, ref_s, ref_e, ent_s, ent_e, atr, sym, **kw):
        if atr <= 0:
            return None
        win = [b for b in day_bars if ent_s <= b.ts < ent_e]
        for i in range(1, len(win)):
            p, b = win[i - 1], win[i]
            if not (b.high > p.high and b.low < p.low):
                continue
            if b.high - b.low < 0.5 * atr \
                    or th.body_ratio(b) < 0.50:
                continue
            if b.close > b.open:
                entry = (b.open + b.close) / 2.0
                stop = b.low - 0.05 * atr
                if _band_ok(entry, stop, atr):
                    return _base_sig("long", entry, stop, b.ts + _five(),
                                     b.ts, b.low, th.body_ratio(b),
                                     th.wick_ratio(b, "long"), 0.2)
            elif b.close < b.open:
                entry = (b.open + b.close) / 2.0
                stop = b.high + 0.05 * atr
                if _band_ok(entry, stop, atr):
                    return _base_sig("short", entry, stop, b.ts + _five(),
                                     b.ts, b.high, th.body_ratio(b),
                                     th.wick_ratio(b, "short"), 0.2)
        return None
    return det


def _vol_avg20(day_vols, ts_int):
    """Mean volume of up to the 20 bars strictly before ts_int (ints)."""
    n = 0
    s = 0.0
    for t, v in day_vols:
        if t >= ts_int:
            break
        s += v
        n += 1
        if n >= 20:
            break
    if n < 10:
        return None
    return s / n


def make_vol_spike(volmap):
    """V1: bar volume >= 3x the 20-bar average, body ratio >= 0.60,
    body >= 0.3 ATR -> enter the spike direction at the midpoint, stop
    beyond the opposite extreme. 2y-only (volume starts 2024-01-10)."""
    def det(day_bars, ref_s, ref_e, ent_s, ent_e, atr, sym, **kw):
        if atr <= 0:
            return None
        d = m.to_london_date(day_bars[0].ts)
        day_vols = volmap.get(sym, {}).get(d)
        if not day_vols:
            return None
        win = [b for b in day_bars if ent_s <= b.ts < ent_e]
        vmap = dict(day_vols)
        for b in win:
            ts_i = int(b.ts.timestamp())
            av = _vol_avg20(day_vols, ts_i)
            if av is None:
                continue
            bv = vmap.get(ts_i, 0)
            if bv < 3 * av:
                continue
            body = abs(b.close - b.open)
            rng = b.high - b.low
            if rng <= 0 or th.body_ratio(b) < 0.60 or body < 0.3 * atr:
                continue
            if b.close > b.open:
                entry = (b.open + b.close) / 2.0
                stop = b.low - 0.05 * atr
                if _band_ok(entry, stop, atr):
                    return _base_sig("long", entry, stop, b.ts + _five(),
                                     b.ts, b.low, th.body_ratio(b),
                                     th.wick_ratio(b, "long"),
                                     bv / max(av, 1))
            else:
                entry = (b.open + b.close) / 2.0
                stop = b.high + 0.05 * atr
                if _band_ok(entry, stop, atr):
                    return _base_sig("short", entry, stop, b.ts + _five(),
                                     b.ts, b.high, th.body_ratio(b),
                                     th.wick_ratio(b, "short"),
                                     bv / max(av, 1))
        return None
    return det


def make_poc_retrace(volmap):
    """V2: POC = volume-weighted 07:00-09:00 London price. By 09:00 the
    close must be >= 0.1 ATR away from POC (trend dir). Enter the first
    retrace to within 0.05 ATR of POC in the trend direction (limit at
    POC), stop 0.65 ATR beyond POC. 2y-only."""
    def det(day_bars, ref_s, ref_e, ent_s, ent_e, atr, sym, **kw):
        if atr <= 0:
            return None
        d = m.to_london_date(day_bars[0].ts)
        day_vols = volmap.get(sym, {}).get(d)
        if not day_vols:
            return None
        vmap = dict(day_vols)
        w0 = m.lw_utc(d, 7).timestamp()
        w1 = m.lw_utc(d, 9).timestamp()
        num = den = 0.0
        for b in day_bars:
            tsi = int(b.ts.timestamp())
            if w0 <= tsi < w1:
                v = vmap.get(tsi, 0)
                if v > 0:
                    num += ((b.open + b.high + b.low + b.close) / 4.0) * v
                    den += v
        if den <= 0:
            return None
        poc = num / den
        close9 = None
        for b in day_bars:
            if int(b.ts.timestamp()) < w1:
                close9 = b.close
            else:
                break
        if close9 is None:
            return None
        if poc - close9 >= 0.1 * atr:
            side = "long"
        elif close9 - poc >= 0.1 * atr:
            side = "short"
        else:
            return None
        win = [b for b in day_bars if ent_s <= b.ts < ent_e]
        for b in win:
            if int(b.ts.timestamp()) < w1:
                continue
            if side == "long" and b.low <= poc + 0.05 * atr:
                stop = poc - 0.65 * atr
                return _base_sig("long", poc, stop, b.ts + _five(), b.ts,
                                 b.low, 0.6, 0.6, 0.2)
            if side == "short" and b.high >= poc - 0.05 * atr:
                stop = poc + 0.65 * atr
                return _base_sig("short", poc, stop, b.ts + _five(), b.ts,
                                 b.high, 0.6, 0.6, 0.2)
        return None
    return det


def make_vol_divergence(volmap):
    """V3: new window extreme (low/high since window start) printed on
    volume <= 0.5x the 20-bar average -> exhaustion, fade the extreme.
    Enter at the bar midpoint, stop beyond the extreme. 2y-only."""
    def det(day_bars, ref_s, ref_e, ent_s, ent_e, atr, sym, **kw):
        if atr <= 0:
            return None
        d = m.to_london_date(day_bars[0].ts)
        day_vols = volmap.get(sym, {}).get(d)
        if not day_vols:
            return None
        vmap = dict(day_vols)
        win = [b for b in day_bars if ent_s <= b.ts < ent_e]
        hh, ll = None, None
        for b in win:
            ts_i = int(b.ts.timestamp())
            av = _vol_avg20(day_vols, ts_i)
            bv = vmap.get(ts_i, 0)
            if av is not None and bv <= 0.5 * av:
                if hh is not None and b.low < ll \
                        and th.body_ratio(b) >= 0.30:
                    entry = (b.open + b.close) / 2.0
                    stop = b.low - 0.05 * atr
                    if _band_ok(entry, stop, atr):
                        return _base_sig("long", entry, stop,
                                         b.ts + _five(), b.ts, b.low,
                                         th.body_ratio(b),
                                         th.wick_ratio(b, "long"), 0.2)
                if hh is not None and b.high > hh \
                        and th.body_ratio(b) >= 0.30:
                    entry = (b.open + b.close) / 2.0
                    stop = b.high + 0.05 * atr
                    if _band_ok(entry, stop, atr):
                        return _base_sig("short", entry, stop,
                                         b.ts + _five(), b.ts, b.high,
                                         th.body_ratio(b),
                                         th.wick_ratio(b, "short"), 0.2)
            hh = b.high if hh is None or b.high > hh else hh
            ll = b.low if ll is None or b.low < ll else ll
        return None
    return det


# ---------------------------------------------------------------------------
# Variant registry
# ---------------------------------------------------------------------------
# variant: (label, family, make_fn(ctx) -> detector)
def _mk_s1(ctx):  return make_sweep_reclaim(ctx["sym_ref"]["3"])
def _mk_s2(ctx):  return make_sweep_reclaim(ctx["sym_ref"]["5"])
def _mk_s3(ctx):  return make_sweep_reclaim(ctx["sym_ref"]["10"])
def _mk_s4(ctx):  return make_breakout_retest(ctx["sym_ref"]["5"])
def _mk_pa1(ctx): return make_inside_bar()
def _mk_pa2(ctx): return make_pin_bar()
def _mk_pa3(ctx): return make_engulfing()
def _mk_pa4(ctx): return make_outside_bar()
def _mk_v1(ctx):  return make_vol_spike(ctx["volmap"])
def _mk_v2(ctx):  return make_poc_retrace(ctx["volmap"])
def _mk_v3(ctx):  return make_vol_divergence(ctx["volmap"])

VARIANTS = {
    "S1":  ("3d sweep-reclaim", "sr", _mk_s1),
    "S2":  ("5d sweep-reclaim", "sr", _mk_s2),
    "S3":  ("10d sweep-reclaim", "sr", _mk_s3),
    "S4":  ("5d breakout-retest", "sr", _mk_s4),
    "PA1": ("inside-bar break", "pa", _mk_pa1),
    "PA2": ("pin-bar rejection", "pa", _mk_pa2),
    "PA3": ("engulfing", "pa", _mk_pa3),
    "PA4": ("outside-bar follow", "pa", _mk_pa4),
    "V1":  ("vol-spike displacement", "vol", _mk_v1),
    "V2":  ("POC retrace", "vol", _mk_v2),
    "V3":  ("low-vol exhaustion", "vol", _mk_v3),
}
VOL_ONLY = {"V1", "V2", "V3"}


def build_ctx(cache, volmap):
    """Per-symbol reference levels (for the sweep family)."""
    out = {}
    for sym in ALL11:
        if sym not in cache:
            continue
        out[sym] = dict(
            sym_ref={"3": n_day_levels(cache, sym, 3),
                     "5": n_day_levels(cache, sym, 5),
                     "10": n_day_levels(cache, sym, 10)},
            volmap=volmap)
    return out


def run_variant(cache, sym, vk, ctx):
    label, fam, mk = VARIANTS[vk]
    det = mk(ctx[sym])
    orig = th.detect
    th.detect = det
    try:
        return th.run_triad(cache, T, TS, ([sym], []), risk_frac=RISK)
    finally:
        th.detect = orig


def restrict_m5(cache, d0, d1):
    out = {}
    for sym, (by_date, atr_map) in cache.items():
        out[sym] = ({d: bars for d, bars in by_date.items() if d0 <= d <= d1},
                    {d: a for d, a in atr_map.items() if d0 <= d <= d1})
    return out


# ---------------------------------------------------------------------------
# Stage 1: 2y gate matrix
# ---------------------------------------------------------------------------
def stage1():
    osel.set_geometry(False)
    th.tsb.STOP_BUFFER_ATR = BUF
    # 2y gate = the 2y data file's own window (same gate as the certified
    # stack; its ATR map is warmed over the same window)
    rc = v2.load_cache(DATA_DIR2)
    d2 = sorted(rc["EURUSD"][0])
    d0, d1 = d2[0], d2[-1]
    print(f"STAGE 1 — 2y gate {d0} -> {d1}, standalone 11 pairs x "
          f"{len(VARIANTS)} variants, {RISK*100:.2f}%")
    t0 = time.time()
    volmap = load_vol(DATA_DIR2, ALL11)
    nv = sum(len(r) for sym in ALL11 for r in volmap[sym].values())
    print(f"  volume loaded: {nv} window-bars "
          f"({time.time()-t0:.0f}s)")
    ctx = build_ctx(rc, volmap)
    out = {}
    for sym in ALL11:
        out[sym] = {}
        for vk in VARIANTS:
            r = run_variant(rc, sym, vk, ctx)
            out[sym][vk] = dict(n=r["n"], pf=r["pf"], total=r["total"],
                                avg_r=r["avg_r"], dd=r["dd"])
            print(f"  {sym:<8} {vk:<4} n={r['n']:>3} PF={r['pf']:5.2f} "
                  f"${r['total']:>9.2f}", flush=True)
    # core-3 aggregate screen (family viability at a glance)
    print("\ncore-3 aggregate (champion geometry base, standalone per pair "
          "summed for reference only — selection is per-pair):")
    MATRIX_JSON.write_text(json.dumps(out))
    print(f"\nwrote {MATRIX_JSON}")
    return out


# ---------------------------------------------------------------------------
# Stage 2: 4y confirmation + portfolio ablation
# ---------------------------------------------------------------------------
def stage2():
    import json
    mat = json.loads(MATRIX_JSON.read_text())
    osel.set_geometry(False)
    th.tsb.STOP_BUFFER_ATR = BUF
    cache4 = v2.load_cache(DATA_DIR4)
    volmap4 = load_vol(DATA_DIR4, ALL11)
    ctx4 = build_ctx(cache4, volmap4)

    def qualifies(x):
        return x["n"] >= 15 and x["total"] > 0 \
            and (x["pf"] >= 1.2 or x["pf"] == float("inf"))

    picks = {}
    for sym in ALL11:
        cands = {k: x for k, x in mat[sym].items() if qualifies(x)}
        if cands:
            picks[sym] = max(cands, key=lambda k: cands[k]["total"])
    print("2y picks (n>=15, PF>=1.2, total>0, max $):")
    for sym in ALL11:
        vk = picks.get(sym)
        if vk:
            x = mat[sym][vk]
            print(f"  {sym:<8} {vk:<4} {VARIANTS[vk][0]:<22} "
                  f"2y n={x['n']} ${x['total']:+.0f}")
        else:
            print(f"  {sym:<8} — no qualifier")

    print("\n4y confirmation (S/R + PA families only; volume family has NO "
          "4y data — 2y-only status):")
    confirmed = {}
    for sym, vk in picks.items():
        x2 = mat[sym][vk]
        if vk in VOL_ONLY:
            print(f"  {sym:<8} {vk:<4} 2y-only (no 4y volume data) "
                  f"${x2['total']:+.0f} n={x2['n']} — UNCONFIRMED")
            continue
        r = run_variant(cache4, sym, vk, ctx4)
        ok = r["total"] > 0
        confirmed[sym] = (vk, r, ok)
        print(f"  {sym:<8} {vk:<4} {VARIANTS[vk][0]:<22} "
              f"2y ${x2['total']:+.0f} -> 4y n={r['n']} PF={r['pf']:.2f} "
              f"${r['total']:+.0f} {'CONFIRM' if ok else 'REJECT'}",
              flush=True)

    # portfolio ablation: per-pair 5-pair stack (frozen) + confirmed extras
    print("\nPortfolio ablation (one slot, P0, 1.75/3.0, compound):")
    osel.PAIR_CFG = {s: dict(c) for s, c in osel.PAIRFIT_ASSIGN.items()}
    osel.TRIA_UNIVERSE = [(1, s, 0) for s in osel.PAIRFIT_ASSIGN]
    osel.TR_SIG_HOURS = None
    osel.RISK_TRIAD = 0.0175
    osel.COMPOUND = True
    osel.EXTRA_DETECTORS.clear()
    r0 = osel.run_combo(cache4, "P0", theta=0.0)
    print(f"  F0 per-pair 5-pair stack: ${r0['total']:.2f} "
          f"(expect $3,811.34) CAGR={r0['cagr']:.1f}% P1={r0['p1_days']}d")

    ok_extras = [(sym, vk, r) for sym, (vk, r, ok) in confirmed.items()
                 if ok]
    if ok_extras:
        # attach the confirmed detectors as extras (closures over ctx4)
        for sym, vk, r in ok_extras:
            mk = VARIANTS[vk][2]
            det = mk(ctx4[sym])

            def make_bound(det, only_sym):
                def fn(day_bars, ref_s, ref_e, ent_s, ent_e, atr, sym2):
                    if sym2 != only_sym:
                        return None
                    return det(day_bars, ref_s, ref_e, ent_s, ent_e, atr,
                               sym2)
                return fn
            osel.EXTRA_DETECTORS.append((vk, make_bound(det, sym)))
        r1 = osel.run_combo(cache4, "P0", theta=0.0)
        print(f"  F1 + {len(ok_extras)} confirmed S/R-PA extras: "
              f"${r1['total']:.2f} CAGR={r1['cagr']:.1f}% P1="
              f"{r1['p1_days']}d | vs F0 "
              f"${r1['total'] - r0['total']:+.2f}")
        pp = defaultdict(lambda: [0, 0.0])
        for t in r1["trades"]:
            if "entry_date" not in t:
                pp[t["symbol"]][0] += 1
                pp[t["symbol"]][1] += t["pnl"]
        print("   per-pair (F1): " + "  ".join(
            f"{s}:{v[0]}/{v[1]:+.0f}" for s, v in sorted(pp.items())))
    else:
        print("  no confirmed extras — F1 skipped")
    osel.EXTRA_DETECTORS.clear()
    return picks, confirmed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stage1", action="store_true")
    ap.add_argument("--stage2", action="store_true")
    args = ap.parse_args()
    if not (args.stage1 or args.stage2):
        ap.print_help()
        return
    if args.stage1:
        stage1()
    if args.stage2:
        stage2()


if __name__ == "__main__":
    main()
