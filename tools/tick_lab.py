#!/usr/bin/env python3
"""Real bid/ask minute data (histdata tick quotes reduced to 1-minute bars by scripts/research-data/fetch_ticks.py) used to
  (1) measure the actual spread around the 17:00 New York rollover and the Sunday open, and
  (2) re-execute the exhaustion fade's signals with real ask entries and bid exits (limit/stop on the correct side).
Pre-registered in docs/research/findings/findings_tick_rollover.md (committed before any P&L here was computed).
  python tools/tick_lab.py report
Data: RESEARCH_INPUTS/ticks/<pair>-<yyyy>-<mm>-1min.csv.gz. The `min` column is epoch SECONDS of the feed's clock (UTC-5 in winter, UTC-4 in summer,
switching on the European DST dates; verified day by day against the Dukascopy M5 bid closes, see `feed_to_utc_ms`).
"""
from __future__ import annotations

import glob
import os
import sys
from pathlib import Path
from zoneinfo import ZoneInfo

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "validation" / "speed_lab"))
from tools import exhaustion_oos_lab as X  # noqa: E402
from tools import broker_cost_lab as B  # noqa: E402
import verify_final_config as V  # noqa: E402

RI = Path(os.environ.get("RESEARCH_INPUTS", "/tmp/ri/forex-data-research-inputs")) / "ticks"
NYZ = ZoneInfo("America/New_York")
MIN = 60_000
PAIRS = ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD"]
COMM = 4.0                                  # The5ers round turn per lot


def feed_to_utc_ms(sec: np.ndarray) -> np.ndarray:
    """Feed stamps (epoch seconds of the feed's own clock) -> UTC epoch ms.
    Measured on 12 months of EURUSD against the Dukascopy M5 closes (100 % match on every day): the clock is UTC-5 in winter and UTC-4 in summer,
    and it switches on the EUROPEAN daylight-saving dates (2025-10-26 and 2026-03-29), NOT the US dates. So: utc = stamp + 5 h, minus 1 h when London is on summer time."""
    utc5 = pd.to_datetime(sec, unit="s").tz_localize("UTC") + pd.Timedelta(hours=5)
    summer = utc5.tz_convert("Europe/London").map(lambda t: t.dst().total_seconds() > 0).to_numpy()
    utc = utc5 - pd.to_timedelta(summer.astype(int), unit="h")
    return utc.tz_localize(None).astype("datetime64[ms]").astype("int64")


def load_minutes(sym: str, root: Path = RI) -> dict:
    files = sorted(glob.glob(str(root / f"{sym.lower()}-*-1min.csv.gz")))
    if not files:
        raise FileNotFoundError(sym)
    df = pd.concat([pd.read_csv(f) for f in files], ignore_index=True)
    df = df.copy()
    df["ts"] = feed_to_utc_ms(df["min"].to_numpy().astype(np.int64))
    df = df.sort_values("ts").drop_duplicates("ts")
    return {k: df[k].to_numpy() for k in ("ts", "bid_o", "bid_h", "bid_l", "bid_c", "ask_o", "ask_h", "ask_l", "ask_c", "spr_mean", "spr_max", "spr_min")}


def ny_minute_of_day(ts_ms: np.ndarray) -> np.ndarray:
    t = pd.to_datetime(ts_ms, unit="ms", utc=True).tz_convert(NYZ)
    return (t.hour * 60 + t.minute).to_numpy()


# ------------------------------------------------------------------ execution on real quotes
def execute_long(m: dict, t_entry_ms: int, stop: float, target: float, hold_min: int, delay_min: int = 0):
    """Market buy at the ASK open of the entry minute (+delay). Protective stop and limit target are SELL orders, so they trigger on the BID:
    stop when bid low <= stop (filled at the stop, or at the bid open if the minute gaps through it), target when bid high >= target.
    Stop ties beat the target. Returns (entry_ask, exit_bid, exit_ts, kind) or None when the minute is missing."""
    ts = m["ts"]
    i0 = int(np.searchsorted(ts, t_entry_ms + delay_min * MIN, "left"))
    if i0 >= len(ts) or ts[i0] - (t_entry_ms + delay_min * MIN) > 10 * MIN:
        return None
    entry = float(m["ask_o"][i0])
    j_end = int(np.searchsorted(ts, ts[i0] + hold_min * MIN, "right"))
    lo, hi = m["bid_l"][i0:j_end], m["bid_h"][i0:j_end]
    s = np.flatnonzero(lo <= stop); t = np.flatnonzero(hi >= target)
    js = int(s[0]) if len(s) else 10 ** 9
    jt = int(t[0]) if len(t) else 10 ** 9
    if js <= jt and js < 10 ** 9:
        j = i0 + js
        fill = stop if js == 0 else min(stop, float(m["bid_o"][j]))
        return entry, fill, int(ts[j]), "stop"
    if jt < 10 ** 9:
        j = i0 + jt
        return entry, target, int(ts[j]), "target"
    j = j_end - 1
    return entry, float(m["bid_c"][j]), int(ts[j]), "time"


_BARS: dict = {}


def _bars(sym: str) -> dict:
    if sym not in _BARS:
        _BARS[sym] = X.load(sym, X.files("ci")[sym])
    return _BARS[sym]


def reprice(signals: list[dict], mins: dict[str, dict], delay_min: int = 0) -> list[dict]:
    """Re-execute the modelled fade signals on real quotes. R is measured in the MODEL's 1R (dist) so it is comparable with R_strict."""
    out = []
    for t in signals:
        m = mins.get(t["sym"])
        if m is None:
            continue
        pip, pv, _ = V.SPECS[t["sym"]]
        # model geometry: entry = bid open of bar i+1, stop = model stop, target = entry + 10R
        d = _bars(t["sym"])
        i1 = int(np.searchsorted(d["ts"], t["t_fill"]))
        entry_model = float(d["o"][i1]); stop = entry_model - t["dist"]; target = entry_model + X.TARGET_R * t["dist"]
        r = execute_long(m, t["t_fill"], stop, target, 96 * 60, delay_min)
        if r is None:
            continue
        e, x, tx, kind = r
        comm_R = COMM / (t["stop_pips"] * pv)
        spread_entry = e - float(m["bid_o"][int(np.searchsorted(m["ts"], t["t_fill"] + delay_min * MIN))])
        out.append(dict(t, R_tick=(x - e) / t["dist"], R_tick_net=(x - e) / t["dist"] - comm_R, comm_R=comm_R, kind=kind,
                        spread_entry_pips=spread_entry / pip, R_model=t["R_strict"]))
    return out


def spread_profile(mins: dict[str, dict]) -> pd.DataFrame:
    rows = []
    for sym, m in mins.items():
        pip = V.SPECS[sym][0]
        nym = ny_minute_of_day(m["ts"])
        sp = m["spr_mean"] / pip
        gap = np.r_[False, np.diff(m["ts"]) >= 36 * 3_600_000 * 1.0]
        first_after_gap = np.zeros(len(sp), bool)
        for g in np.flatnonzero(gap):
            first_after_gap[g:g + 5] = True
        def q(mask):
            return float(np.median(sp[mask])) if mask.any() else float("nan")
        rows.append(dict(sym=sym, typical_raw_assumed=B.TYPICAL_RAW.get(sym, np.nan),
                         median_all=q(np.ones(len(sp), bool)), london_NY02_05=q((nym >= 120) & (nym < 300)),
                         ny_1300_1500=q((nym >= 780) & (nym < 900)), pre_1600_1650=q((nym >= 960) & (nym < 1010)),
                         rollover_1700_1705=q((nym >= 1020) & (nym < 1025)), rollover_1655_1810=q((nym >= 1015) & (nym <= 1090)),
                         mean_rollover_1655_1810=float(np.mean(sp[(nym >= 1015) & (nym <= 1090)])),
                         max_p99_rollover=float(np.percentile(m["spr_max"][(nym >= 1015) & (nym <= 1090)] / pip, 99)),
                         first5min_after_weekend=q(first_after_gap)))
    return pd.DataFrame(rows).set_index("sym")


def report():
    mins = {s: load_minutes(s) for s in PAIRS}
    print("Spread profile, pips (median of the per-minute mean spread), real quotes Sep-2025 .. Aug-2026:")
    pd.set_option("display.width", 250)
    print(spread_profile(mins).round(2).T.to_string())
    lo, hi = X.ms("2025-09-03"), X.ms("2026-08-28")
    sig = [t for t in X.all_signals("ci") if t["sym"] in mins and lo <= t["t_fill"] < hi]
    import tools.broker_cost_lab as BL
    sig = BL.recost(sig, COMM, 2.0)                       # The5ers $4 + typical raw spread x2 = the pre-declared model cost
    roll = [t for t in sig if BL.in_rollover(t)]
    rest = [t for t in sig if not BL.in_rollover(t)]
    print(f"\nFade signals on the four pairs in the tick window: {len(sig)} (rollover {len(roll)}, other {len(rest)})")
    for lbl, rows in (("rollover 16:55-18:10 NY", roll), ("everything else", rest)):
        for delay in (0, 1, 5):
            rp = reprice(rows, mins, delay)
            if not rp:
                continue
            g = np.array([r["R_model"] for r in rp]); k = np.array([r["R_tick"] for r in rp]); kn = np.array([r["R_tick_net"] for r in rp])
            mc = np.array([r["cost"] for r in rp])
            print(f"  {lbl:24s} delay {delay} min: n={len(rp):3d} model gross {g.mean():+.3f} (model net at repo cost {(g - mc).mean():+.3f}) | "
                  f"real-quote gross {k.mean():+.3f}, net of $4 commission {kn.mean():+.3f} | mean entry spread {np.mean([r['spread_entry_pips'] for r in rp]):.2f} pips")


if __name__ == "__main__":
    report()
