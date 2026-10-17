#!/usr/bin/env python3
"""Fourth bounded search: macro / positioning signals that need data beyond M5 bars (carry from policy rates, CFTC positioning).
Pre-registered in docs/research/findings/findings_macro_search.md (committed before any P&L was computed).
Inputs: the `data/research-inputs` branch (FRED CSVs, CFTC COT zips) extracted to RESEARCH_INPUTS (default /tmp/ri/forex-data-research-inputs).
  python tools/macro_lab.py train | valid | test --confirm
"""
from __future__ import annotations

import argparse
import csv
import io
import json
import os
import sys
import zipfile
from datetime import date, datetime, timezone
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "validation" / "speed_lab"))
from tools import tradable_search_lab as T  # noqa: E402
from tools import docs_v1_lab as L  # noqa: E402
from tools import family_search_lab as F  # noqa: E402
from tools import challenge_sim as C  # noqa: E402

OUT = Path("/tmp/macro_out")
OUT.mkdir(exist_ok=True)
RI = Path(os.environ.get("RESEARCH_INPUTS", "/tmp/ri/forex-data-research-inputs")) / "macro"
ms, SPLITS = T.ms, F.SPLITS
DAY = 86_400_000
MARKUP = 0.005                      # annual swap mark-up charged on notional, both directions (pre-declared)
STOP_ATR = 3.0

CONFIGS: dict[str, dict] = {}
for th in (0.0, 1.0):
    for mode in ("sign", "xs", "signtr"):
        CONFIGS[f"CARRY_{mode}_th{th:g}"] = dict(fam="CARRY", mode=mode, th=th)
for who in ("lev", "am"):
    for mode in ("contra", "follow"):
        for hi in (80, 90):
            CONFIGS[f"COT_{who}_{mode}_{hi}"] = dict(fam="COT", who=who, mode=mode, hi=hi)

# currency -> (pair, +1 if the currency is the BASE of the pair else -1)
CCY = {"EUR": ("EURUSD", 1), "GBP": ("GBPUSD", 1), "AUD": ("AUDUSD", 1), "NZD": ("NZDUSD", 1),
       "CAD": ("USDCAD", -1), "CHF": ("USDCHF", -1), "JPY": ("USDJPY", -1)}
COT_CONTRACT = {"EURO FX": "EUR", "BRITISH POUND": "GBP", "JAPANESE YEN": "JPY", "CANADIAN DOLLAR": "CAD", "AUSTRALIAN DOLLAR": "AUD",
                "NZ DOLLAR": "NZD", "SWISS FRANC": "CHF",
                "BRITISH POUND STERLING": "GBP", "NEW ZEALAND DOLLAR": "NZD"}       # CFTC renamed two contracts in 2020-21
FRED_MONTHLY = {"GBP": "IRSTCI01GBM156N", "JPY": "IRSTCI01JPM156N", "AUD": "IRSTCI01AUM156N", "NZD": "IRSTCI01NZM156N",
                "CAD": "IRSTCI01CAM156N", "CHF": "IRSTCI01CHM156N"}
FRED_DAILY = {"USD": "DFF", "EUR": "ECBDFR"}


# ---------------------------------------------------------------- rates
def read_fred(sid: str, root: Path = RI) -> tuple[np.ndarray, np.ndarray]:
    """(obs date ms, value) skipping missing ('.')."""
    xs, ys = [], []
    with (root / f"fred_{sid}.csv").open() as f:
        for row in list(csv.reader(f))[1:]:
            if len(row) < 2 or row[1] in (".", ""):
                continue
            xs.append(ms(row[0])); ys.append(float(row[1]))
    return np.array(xs, dtype=np.int64), np.array(ys)


def rate_at(dates: np.ndarray, vals: np.ndarray, t: int, lag_days: int, fresh_days: int) -> float:
    """Latest observation usable at time t: obs date + lag <= t; NaN when the newest usable observation is older than fresh_days
    after it became usable (stale series, e.g. a series the provider stopped updating)."""
    avail = dates + lag_days * DAY
    k = np.searchsorted(avail, t, side="right") - 1
    if k < 0 or t - avail[k] > fresh_days * DAY:
        return float("nan")
    return float(vals[k])


class Rates:
    """Short rate per currency as known at a time, with publication lags: daily series 1 day; monthly OECD series usable from 62 days
    after the month start and for at most 75 more days (so a dead series turns NaN instead of being forward-filled for years)."""
    def __init__(self, root: Path = RI):
        self.s = {}
        for c, sid in FRED_DAILY.items():
            self.s[c] = (*read_fred(sid, root), 1, 7)
        for c, sid in FRED_MONTHLY.items():
            self.s[c] = (*read_fred(sid, root), 62, 75)

    def at(self, ccy: str, t: int) -> float:
        d, v, lag, fresh = self.s[ccy]
        return rate_at(d, v, t, lag, fresh)


# ---------------------------------------------------------------- CARRY
def _month(key: int) -> tuple[int, int]:
    dt = date.fromordinal(719163 + int(key) + 1)       # the date the NY trading day ENDS on
    return dt.year, dt.month


def first_allowed(P: T.Pair, i: int) -> int | None:
    n = len(P.allowed)
    while i < n - 1 and not P.allowed[i]:
        i += 1
    return i if i < n - 1 else None


def make_trade(P: T.Pair, dirn: int, i0: int, dist: float, i_end: int, ccy_side: int, carry_pct: float, isig: int):
    """One position held to i_end. R includes the carry accrual (credited to the currency side) less the swap mark-up."""
    r_s, r_o, j = T.walk(P, i0, dirn, dist, i_end, widen_blackout=True)
    entry = float(P.d["o"][i0])
    days = (int(P.d["ts"][j]) - int(P.d["ts"][i0])) / DAY
    acc = (ccy_side * carry_pct / 100.0 * days / 365.0 * entry) / dist
    mk_ = (MARKUP * days / 365.0 * entry) / dist
    t = T.mk(P, dirn, entry, dist, r_s + acc - mk_, r_o + acc - mk_, i0, j, isig)
    t["acc_R"] = float(acc - mk_)
    t["acc_gross_R"] = float(acc)
    t["side"], t["carry"] = int(ccy_side), float(carry_pct)
    return t


def run_CARRY(mode: str, th: float, rates: Rates | None = None, pairs: dict | None = None, delay: int = 0):
    rates = rates or Rates()
    pairs = pairs or {c: T.pairs("ci")[p] for c, (p, _) in CCY.items()}
    dd = {c: F.daily(P.d) for c, P in pairs.items()}
    base = next(iter(dd.values()))
    # rebalance decisions: the first completed NY day of each calendar month (by its end date), common to all pairs
    months = [_month(k) for k in base["key"]]
    reb = [i for i in range(1, len(months)) if months[i] != months[i - 1]]
    out = []
    for a, b in zip(reb[:-1], reb[1:]):
        keya, keyb = int(base["key"][a]), int(base["key"][b])
        sig = {}
        for c, P in pairs.items():
            D = dd[c]
            ia = int(np.searchsorted(D["key"], keya)); ib = int(np.searchsorted(D["key"], keyb))
            if ia >= len(D["key"]) or D["key"][ia] != keya or ib >= len(D["key"]) or not np.isfinite(D["atr"][ia]):
                continue
            t_dec = int(P.d["ts"][D["je"][ia] - 1])
            ri, ru = rates.at(c, t_dec), rates.at("USD", t_dec)
            if not (np.isfinite(ri) and np.isfinite(ru)):
                continue
            sig[c] = (ri - ru, ia, ib)
        if not sig:
            continue
        side = {c: 0 for c in sig}
        if mode == "xs":
            if len(sig) >= 5:
                order = sorted(sig, key=lambda c: sig[c][0])
                for c in order[-2:]:
                    side[c] = 1 if sig[c][0] >= th else 0
                for c in order[:2]:
                    side[c] = -1 if sig[c][0] <= -th else 0
        else:
            for c, (cr, ia, ib) in sig.items():
                side[c] = 0 if abs(cr) < th or cr == 0 else int(np.sign(cr))
        for c, s in side.items():
            if not s:
                continue
            P, D = pairs[c], dd[c]
            cr, ia, ib = sig[c]
            dirn = s * CCY[c][1]
            if mode == "signtr":
                tr = np.sign(D["c"][ia] - D["sma100"][ia]) if np.isfinite(D["sma100"][ia]) else 0
                if tr != dirn:
                    continue
            i0 = first_allowed(P, int(D["je"][ia]) + delay)
            ix = first_allowed(P, int(D["je"][ib]))
            if i0 is None or ix is None or ix <= i0 + 12:
                continue
            out.append(make_trade(P, dirn, i0, STOP_ATR * float(D["atr"][ia]), ix, s, cr, int(D["je"][ia]) - 1))
    out.sort(key=lambda t: (t["t_fill"], t["sym"]))
    return out


# ---------------------------------------------------------------- COT
def read_cot(root: Path = RI) -> dict[str, dict]:
    """{ccy or 'XAU': {date ordinal (Tuesday as-of): (oi, lev_net, am_net)}} from the TFF (currencies) and disaggregated (gold) files."""
    res: dict[str, dict] = {}
    for zp in sorted(root.glob("cot_fut_fin_txt_*.zip")):
        with zipfile.ZipFile(zp) as z:
            for row in csv.DictReader(io.TextIOWrapper(z.open(z.namelist()[0]), encoding="latin-1")):
                nm = row["Market_and_Exchange_Names"].split(" - ")[0].strip()
                if nm not in COT_CONTRACT:
                    continue
                d = date.fromisoformat(row["Report_Date_as_YYYY-MM-DD"]).toordinal()
                oi = float(row["Open_Interest_All"])
                lev = (float(row["Lev_Money_Positions_Long_All"]) - float(row["Lev_Money_Positions_Short_All"])) / oi
                am = (float(row["Asset_Mgr_Positions_Long_All"]) - float(row["Asset_Mgr_Positions_Short_All"])) / oi
                res.setdefault(COT_CONTRACT[nm], {})[d] = (oi, lev, am)
    return res


def pct_rank(x: np.ndarray, win: int = 156, minobs: int = 104) -> np.ndarray:
    """Percentile (0..100) of x[i] within x[i-win+1..i] (inclusive); NaN until minobs observations."""
    out = np.full(len(x), np.nan)
    for i in range(minobs - 1, len(x)):
        w = x[max(0, i - win + 1):i + 1]
        out[i] = 100.0 * (w <= x[i]).sum() / len(w)
    return out


def run_COT(who: str, mode: str, hi: int, cot: dict | None = None, pairs: dict | None = None, delay: int = 0):
    cot = cot or read_cot()
    pairs = pairs or {c: T.pairs("ci")[p] for c, (p, _) in CCY.items()}
    col = 1 if who == "lev" else 2
    out = []
    for c, series in cot.items():
        if c not in pairs:
            continue
        P = pairs[c]; D = F.daily(P.d)
        dates = np.array(sorted(series)); x = np.array([series[d][col] for d in dates])
        pr = pct_rank(x)
        for d, p in zip(dates, pr):
            if not np.isfinite(p):
                continue
            s = 0
            if p >= hi:
                s = -1 if mode == "contra" else 1        # crowded long currency: fade it / ride it
            elif p <= 100 - hi:
                s = 1 if mode == "contra" else -1
            if not s:
                continue
            # as-of Tuesday d is published Friday d+3 after 15:30 NY; trade the following Monday (London date d+6) from 01:00 London
            mon = d + 6 - 719163
            i0 = first_allowed(P, int(np.searchsorted(P.keyL, mon * 1440 + 60, "left")) + delay)
            ix = int(np.searchsorted(P.keyL, (mon + 4) * 1440 + 900, "left"))
            if i0 is None or ix >= len(P.d["o"]) - 1 or ix <= i0 + 12 or abs(int(P.dayL[i0]) - mon) > 1:
                continue
            ia = int(np.searchsorted(D["je"], i0, "right")) - 1
            if ia < 0 or not np.isfinite(D["atr"][ia]):
                continue
            out.append(make_trade(P, s * CCY[c][1], i0, STOP_ATR * float(D["atr"][ia]), ix, 0, 0.0, i0 - 1) | {"ccy": c, "asof": int(d)})
    out.sort(key=lambda t: (t["t_fill"], t["sym"]))
    return out


# ---------------------------------------------------------------- driver (same gate chain as the tradable search)
_TR: dict = {}


def trades_for(name: str, kind: str = "ci", delay: int = 0):
    k = (name, kind, delay)
    if k in _TR:
        return _TR[k]
    c = CONFIGS[name]
    pairs = {cc: T.pairs(kind)[p] for cc, (p, _) in CCY.items()}
    tr = run_CARRY(c["mode"], c["th"], pairs=pairs, delay=delay) if c["fam"] == "CARRY" else run_COT(c["who"], c["mode"], c["hi"], pairs=pairs, delay=delay)
    _TR[k] = tr
    return tr


def stats_for(tr, split, B_=3000, q=5.0):
    w = F.window(tr, split)
    if not w:
        return dict(n=0)
    st = L.stats(w, SPLITS[split][2], B=200)
    st["lb"] = L.bootstrap_lb(w, B=B_, q=q)
    x = L.net_R(w)
    st["exp_slip"] = float((x - 0.05).mean())
    st["acc_mean"] = float(np.mean([t.get("acc_R", 0.0) for t in w]))
    st["exp_no_carry"] = float(st["exp"] - st["acc_mean"])
    return st


def fmt(name, st):
    if not st.get("n"):
        return f"{name:24s} n=0"
    return (f"{name:24s} n={st['n']:4d} exp={st['exp']:+.3f} PF={st['pf']:.2f} gross={st['exp_gross']:+.3f} cost={st['cost_mean_R']:.3f} "
            f"carry/trade={st['acc_mean']:+.3f} ex-carry={st['exp_no_carry']:+.3f} lb={st['lb']:+.3f} yrs={[round(h, 2) for h in st['halves']]}")


def is_candidate(name, st):
    ys = [h for h in st.get("halves", []) if h == h]
    return st.get("n", 0) >= 100 and st["exp"] > 0 and st["lb"] > 0 and st["pf"] >= 1.10 and sum(h > 0 for h in ys) >= 3


def cmd_train():
    res = {}
    for name in CONFIGS:
        res[name] = stats_for(trades_for(name), "train")
        print(fmt(name, res[name]), "CANDIDATE" if res[name].get("n") and is_candidate(name, res[name]) else "", flush=True)
    json.dump(res, (OUT / "train.json").open("w"), default=float)
    print(f"TRIALS: {len(CONFIGS)}")
    for fam in ("CARRY", "COT"):
        v = [s for n, s in res.items() if CONFIGS[n]["fam"] == fam and s.get("n")]
        print(f"{fam}: {len(v)} configs, mean gross {np.mean([s['exp_gross'] for s in v]):+.4f}, mean net {np.mean([s['exp'] for s in v]):+.4f}, positive {sum(s['exp'] > 0 for s in v)}/{len(v)}")
    print("candidates:", [n for n, s in res.items() if s.get("n") and is_candidate(n, s)])


def cmd_valid():
    train = json.load((OUT / "train.json").open())
    cands = [n for n, s in train.items() if s.get("n") and is_candidate(n, s)]
    print("TRAIN candidates:", cands or "NONE")
    ok = []
    for n in cands:
        st = stats_for(trades_for(n), "valid")
        dl = stats_for(trades_for(n, delay=3), "valid")
        good = st.get("n", 0) >= 40 and st["exp"] > 0 and st["pf"] >= 1.05 and dl.get("n", 0) and dl["exp"] > 0
        print(fmt(n, st), f"| delay15min exp={dl.get('exp', float('nan')):+.3f}", "-> ELIGIBLE" if good else "-> dropped")
        if good:
            ok.append(n)
    ok.sort(key=lambda n: -train[n]["lb"])
    fin = ok[:3]
    json.dump(fin, (OUT / "finalists.json").open("w"))
    print("FINALISTS:", fin or "NONE")


def gates(name):
    tr, fs, dl = trades_for(name), trades_for(name, "tracked"), trades_for(name, delay=3)
    st = stats_for(tr, "test", B_=10_000, q=5.0)
    w, fw = F.window(tr, "test"), F.window(fs, "test")
    kw = {(t["sym"], t["t_fill"], t["dir"]) for t in w}; kf = {(t["sym"], t["t_fill"], t["dir"]) for t in fw}
    ov = len(kw & kf) / max(len(kw), len(kf), 1)
    fexp = float(L.net_R(fw).mean()) if fw else float("nan")
    dw = F.window(dl, "test"); dexp = float(L.net_R(dw).mean()) if dw else float("nan")
    ys = [h for h in st["halves"] if h == h]
    g = {"T1": (st["n"] >= 150, f"n={st['n']}"),
         "T2": (st["exp"] >= 0.05 and st["lb"] > 0, f"exp={st['exp']:+.4f} lb95={st['lb']:+.4f}"),
         "T3": (st["pf"] >= 1.15, f"pf={st['pf']:.3f}"),
         "T4": (st["exp_x15"] > 0 and st["exp_slip"] > 0, f"x1.5={st['exp_x15']:+.4f} +0.05R={st['exp_slip']:+.4f}"),
         "T5": (sum(h > 0 for h in ys) >= 3, f"years={[round(h, 3) for h in ys]}"),
         "T6": (st["top_share"] <= 0.40 and st["exp_ex_top"] > 0, f"top {st['top_pair']} {st['top_share']:.0%} ex-top {st['exp_ex_top']:+.4f}"),
         "T7": (ov >= 0.85 and fexp > 0, f"FSB overlap {ov:.1%} FSB exp {fexp:+.4f} (n={len(fw)})"),
         "T8": (dexp > 0, f"entry delayed 15 min: exp={dexp:+.4f} (n={len(dw)})")}
    return dict(name=name, stats=st, gates={k: [bool(v[0]), v[1]] for k, v in g.items()}, passed=all(v[0] for v in g.values()))


def cmd_test(confirm):
    lock = OUT / "test.lock"
    if not confirm or lock.exists():
        sys.exit("refusing: TEST is one look (needs --confirm; lock exists=%s)" % lock.exists())
    fin = json.load((OUT / "finalists.json").open())
    if not fin:
        sys.exit("no finalists: nothing to test")
    lock.write_text(json.dumps(fin))
    res = {}
    for n in fin:
        r = gates(n); res[n] = r
        print("\n" + fmt(n, r["stats"]))
        for k, (ok, m) in r["gates"].items():
            print(f"   {k}: {'PASS' if ok else 'FAIL'}  {m}")
        print("   =>", "ALL GATES PASS" if r["passed"] else "NOT VALIDATED")
    json.dump(res, (OUT / "test.json").open("w"), default=float, indent=1)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("train"); sub.add_parser("valid")
    t = sub.add_parser("test"); t.add_argument("--confirm", action="store_true")
    a = ap.parse_args()
    {"train": cmd_train, "valid": cmd_valid}.get(a.cmd, lambda: cmd_test(a.confirm))()


if __name__ == "__main__":
    main()
