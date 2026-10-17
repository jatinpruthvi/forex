#!/usr/bin/env python3
"""Third bounded search: only trades a retail account could plausibly take, with the user's broker costs built in.
Pre-registered in docs/research/findings/findings_tradable_search.md (committed before any P&L was computed).

Standing rules for every config here (lesson of findings_rollover_artifact.md):
  * no entry bar inside the rollover blackout (16:55-18:10 New York) and none in the first hour after a weekend gap;
  * intraday families are flat before 16:45 New York; the multi-day family treats blackout bars with a widened range (stop test pessimistic);
  * costs: The5ers High Stakes $4 round-turn per lot + TYPICAL_RAW spread x2 (pre-declared primary); "x1.5 stress" = x3 of typical.
  python tools/tradable_search_lab.py train | valid | test --confirm
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

import numpy as np
from numpy.lib.stride_tricks import sliding_window_view as swv

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "validation" / "speed_lab"))
from tools import exhaustion_oos_lab as X  # noqa: E402
from tools import docs_v1_lab as L  # noqa: E402
from tools import family_search_lab as F  # noqa: E402
from tools import broker_cost_lab as B  # noqa: E402
from tools import challenge_sim as C  # noqa: E402
import verify_final_config as V  # noqa: E402

OUT = Path("/tmp/tradable_out")
OUT.mkdir(exist_ok=True)
ms = X.ms
SPLITS = F.SPLITS
COMM, MULT = 4.0, 2.0
NY = ZoneInfo("America/New_York")
WINDOWS = {"A": (0, 420), "B": (420, 720), "C": (720, 960), "D": (960, 1200)}     # London clock minutes: 00-07, 07-12, 12-16, 16-20
CM_PAIRS = [("A", "B"), ("A", "C"), ("B", "C"), ("B", "D"), ("C", "D")]

CONFIGS: dict[str, dict] = {}
for mode in ("follow", "fade"):
    for S in (0.5, 1.0):
        for T in (1.0, 2.0):
            CONFIGS[f"ORB_{mode}_S{S}_T{T}"] = dict(fam="ORB", mode=mode, S=S, T=T)
for N in (20, 40, 80):
    for k in (2.0, 3.0):
        CONFIGS[f"H4T_N{N}_k{k}"] = dict(fam="H4T", N=N, k=k)
for zt in (2.0, 2.5):
    for S in (2.0, 3.0):
        CONFIGS[f"H1MR_z{zt}_S{S}"] = dict(fam="H1MR", z=zt, S=S)
for x, y in CM_PAIRS:
    for mode in ("cont", "rev"):
        CONFIGS[f"CM_{x}to{y}_{mode}"] = dict(fam="CM", x=x, y=y, mode=mode)


# ---------------------------------------------------------------- pair data
class Pair:
    def __init__(self, sym: str, path: Path):
        self._setup(sym, X.load(sym, path))

    def _setup(self, sym: str, d: dict):
        self.sym = sym
        self.d = d
        ts = d["ts"]
        hours = ts // 3_600_000
        uh, inv = np.unique(hours, return_inverse=True)
        off = np.array([int(datetime.fromtimestamp(int(h) * 3600, tz=timezone.utc).astimezone(NY).utcoffset().total_seconds() * 1000) for h in uh])
        loc = ts + off[inv]
        self.nym = ((loc // 60_000) % 1440).astype(np.int64)                      # New York minute of day
        # session minute: minutes since 18:10 NY (the end of the rollover blackout); 0..1439
        self.smin = (self.nym - 1090) % 1440
        self.minL, self.dayL = L.london_parts(ts)
        self.keyL = self.dayL * 1440 + self.minL
        ok = ~((self.nym >= 1015) & (self.nym <= 1090))
        gi = np.flatnonzero(np.diff(ts) >= 36 * 3_600_000) + 1
        for g in gi:
            ok[g:g + 12] = False
        self.allowed = ok                                                          # entry bar permitted
        self.blackout = ~((self.nym < 1015) | (self.nym > 1090))
        self.pip, self.pv, _ = V.SPECS[sym]
        self.dd_cache = {}


def mk(P: Pair, dirn, entry, dist, r_strict, r_opt, i0, ix, isig):
    ts = P.d["ts"]
    sp = dist / P.pip
    return dict(sym=P.sym, dir=dirn, R_pess=float(r_strict), R_opt=float(r_opt),
                cost=B.cost_R(P.sym, sp, COMM, MULT), cost15=B.cost_R(P.sym, sp, COMM, MULT * 1.5),
                cost2=B.cost_R(P.sym, sp, COMM, MULT * 2.0), cost3=B.cost_R(P.sym, sp, COMM, MULT * 3.0),
                t_fill=int(ts[i0]), t_exit=int(ts[ix]), t_sig=int(ts[isig]), stop_pips=sp)


def walk(P: Pair, i0: int, dirn: int, dist: float, i_end: int, tgt_price: float | None = None, widen_blackout=False):
    """Enter at the open of bar i0. Bars i0..i_end-1 are scanned; time exit at the open of bar i_end. Stop ties beat the target.
    Returns (R_strict, R_repo, exit_index)."""
    d = P.d
    entry = float(d["o"][i0])
    stop = entry - dirn * dist
    lo, hi = d["l"][i0:i_end], d["h"][i0:i_end]
    if widen_blackout:
        rng = hi - lo
        bo = P.blackout[i0:i_end]
        lo = np.where(bo, lo - rng, lo)
        hi = np.where(bo, hi + rng, hi)
    sh = np.flatnonzero(lo <= stop if dirn > 0 else hi >= stop)
    th = np.flatnonzero(hi >= tgt_price if dirn > 0 else lo <= tgt_price) if tgt_price is not None else []
    js = int(sh[0]) if len(sh) else 10 ** 9
    jt = int(th[0]) if len(th) else 10 ** 9
    if js <= jt and js < 10 ** 9:
        j = i0 + js
        fill = stop if js == 0 else (min(stop, d["o"][j]) if dirn > 0 else max(stop, d["o"][j]))
        return (fill - entry) * dirn / dist, -1.0, j
    if jt < 10 ** 9:
        r = abs(tgt_price - entry) / dist
        return r, r, i0 + jt
    r = (d["o"][i_end] - entry) * dirn / dist
    return r, r, i_end


# ---------------------------------------------------------------- families
def window_index(P: Pair, days, m0, m1):
    e = np.searchsorted(P.keyL, days * 1440 + m0, "left")
    x = np.searchsorted(P.keyL, days * 1440 + m1, "left")
    return e, x


def run_ORB(P: Pair, mode, S, T, delay=0):
    d = P.d
    days = np.unique(P.dayL)
    days = days[((days + 3) % 7) < 5]
    a0, a1 = window_index(P, days, 0, 420)
    _, x1 = window_index(P, days, 0, 600)
    _, te = window_index(P, days, 0, 960)
    out = []
    for k in range(len(days)):
        i0_, i1_, xe, t_end = int(a0[k]), int(a1[k]), int(x1[k]), int(te[k])
        if i1_ - i0_ < 60 or t_end >= len(d["c"]) - 1 or xe <= i1_ + 1 or t_end < xe + 24:
            continue
        H, Lw = d["h"][i0_:i1_].max(), d["l"][i0_:i1_].min()
        width = H - Lw
        if width < 4 * P.pip:
            continue
        c = d["c"][i1_:xe]
        br = np.flatnonzero((c > H) | (c < Lw))
        if not len(br):
            continue
        j = i1_ + int(br[0])
        bdir = 1 if d["c"][j] > H else -1
        dirn = bdir if mode == "follow" else -bdir
        i0 = j + 1 + delay
        if i0 >= t_end - 12 or not P.allowed[i0]:
            continue
        dist = S * width
        entry = float(d["o"][i0])
        tgt = entry + dirn * T * dist
        r, ro, ix = walk(P, i0, dirn, dist, t_end, tgt)
        out.append(mk(P, dirn, entry, dist, r, ro, i0, ix, j))
    return out


def h_bars(P: Pair, hours: int):
    key = P.d["ts"] // (hours * 3_600_000)
    st = np.flatnonzero(np.r_[True, key[1:] != key[:-1]])
    en = np.r_[st[1:], len(key)]
    d = P.d
    n = en - st
    keep = n >= max(1, int(hours * 12 * 0.5))
    st, en = st[keep], en[keep]
    o, h, l, c = d["o"][st], np.maximum.reduceat(d["h"], st), np.minimum.reduceat(d["l"], st), d["c"][en - 1]
    # np.maximum.reduceat over st segments runs to the next kept start, so merged stubs stay inside the previous bar
    en = np.r_[st[1:], len(d["c"])]
    c = d["c"][en - 1]
    pc = np.r_[c[0], c[:-1]]
    tr = np.maximum(h - l, np.maximum(np.abs(h - pc), np.abs(l - pc)))
    cs = np.cumsum(np.r_[0.0, tr])
    atr = np.full(len(c), np.nan); atr[13:] = (cs[14:] - cs[:-14]) / 14
    return dict(js=st, je=en, o=o, h=h, l=l, c=c, atr=atr)


def run_H4T(P: Pair, N, k, delay=0):
    hb = h_bars(P, 4)
    c, h, l, atr = hb["c"], hb["h"], hb["l"], hb["atr"]
    n = len(c)
    hi = np.full(n, np.nan); lo = np.full(n, np.nan)
    hi[N:] = swv(h, N)[:n - N].max(1); lo[N:] = swv(l, N)[:n - N].min(1)
    d = P.d
    out, i = [], max(N, 14)
    while i < n - 2:
        if not np.isfinite(atr[i]) or not np.isfinite(hi[i]):
            i += 1; continue
        dirn = 1 if c[i] > hi[i] else (-1 if c[i] < lo[i] else 0)
        i0 = int(hb["je"][i]) + delay
        if not dirn or i0 >= len(d["o"]) - 1 or not P.allowed[i0 - delay] or (hb["js"][i + 1] if i + 1 < n else 0) != hb["je"][i]:
            i += 1; continue                 # need a contiguous next H4 bar (no weekend hole) and an allowed entry bar
        entry = float(d["o"][i0]); dist = k * atr[i]
        stop = entry - dirn * dist; best = entry
        done = False
        for kk in range(i + 1, min(i + 61, n)):
            a, b = int(hb["js"][kk]), int(hb["je"][kk])
            a = max(a, i0)
            if b <= a:
                continue
            lo_, hi_ = d["l"][a:b], d["h"][a:b]
            bo = P.blackout[a:b]
            rng = hi_ - lo_
            lo_ = np.where(bo, lo_ - rng, lo_); hi_ = np.where(bo, hi_ + rng, hi_)
            hit = np.flatnonzero(lo_ <= stop if dirn > 0 else hi_ >= stop)
            if len(hit):
                j = a + int(hit[0])
                fill = stop if j == i0 else (min(stop, d["o"][j]) if dirn > 0 else max(stop, d["o"][j]))
                out.append(mk(P, dirn, entry, dist, (fill - entry) * dirn / dist, -1.0, i0, j, int(hb["je"][i]) - 1)); i = kk; done = True; break
            best = max(best, c[kk]) if dirn > 0 else min(best, c[kk])
            new = best - dirn * k * atr[i]
            stop = max(stop, new) if dirn > 0 else min(stop, new)
        if not done:
            kk = min(i + 60, n - 1)
            jx = min(int(hb["je"][kk]), len(d["o"]) - 1)
            r = (d["o"][jx] - entry) * dirn / dist
            out.append(mk(P, dirn, entry, dist, r, r, i0, jx, int(hb["je"][i]) - 1)); i = kk
        i += 1
    return out


def run_H1MR(P: Pair, zt, S, delay=0):
    hb = h_bars(P, 1)
    c, atr = hb["c"], hb["atr"]
    n = len(c)
    cs = np.cumsum(np.r_[0.0, c]); cs2 = np.cumsum(np.r_[0.0, c * c])
    sma = np.full(n, np.nan); sd = np.full(n, np.nan)
    sma[19:] = (cs[20:] - cs[:-20]) / 20
    var = (cs2[20:] - cs2[:-20]) / 20 - sma[19:] ** 2
    sd[19:] = np.sqrt(np.maximum(var, 0))
    d = P.d
    smin, ts = P.smin, d["ts"]
    out, i = [], 20
    while i < n - 2:
        if not (np.isfinite(atr[i]) and np.isfinite(sd[i]) and sd[i] > 0):
            i += 1; continue
        z = (c[i] - sma[i]) / sd[i]
        dirn = 1 if z <= -zt else (-1 if z >= zt else 0)
        i0 = int(hb["je"][i]) + delay
        if not dirn or i0 >= len(d["o"]) - 13 or not P.allowed[i0 - delay]:
            i += 1; continue
        sm = int(smin[i0])
        if sm < 60 or sm > 1200 or (hb["js"][i + 1] != hb["je"][i]):
            i += 1; continue
        # deadline: the last bar at or before 16:30 New York (session minute 1340) of this session, and at most 12 hours
        ahead = smin[i0:i0 + 12 * 12 + 1]
        cut = np.flatnonzero(ahead >= 1340)
        i_end = i0 + (int(cut[0]) if len(cut) else 12 * 12)
        i_end = min(i_end, i0 + 144, len(d["o"]) - 1)
        if i_end <= i0 + 3:
            i += 1; continue
        entry = float(d["o"][i0]); dist = S * atr[i]
        tgt = float(sma[i])
        if (tgt - entry) * dirn <= 0:
            i += 1; continue
        r, ro, ix = walk(P, i0, dirn, dist, i_end, tgt)
        out.append(mk(P, dirn, entry, dist, r, ro, i0, ix, int(hb["je"][i]) - 1))
        # one position per pair: continue after the exit bar
        i = int(np.searchsorted(hb["je"], ix, "left")) + 1
    return out


def run_CM(P: Pair, x, y, mode, delay=0):
    d = P.d
    days = np.unique(P.dayL)
    days = days[((days + 3) % 7) < 5]
    xs, xe = window_index(P, days, *WINDOWS[x])
    ys, ye = window_index(P, days, *WINDOWS[y])
    ok = (xs < len(d["o"])) & (xe < len(d["o"])) & (ys < len(d["o"])) & (ye < len(d["o"])) & (xe > xs + 12) & (ye > ys + 12) & (ys >= xe)
    ok &= (P.keyL[np.minimum(xs, len(d["o"]) - 1)] - (days * 1440 + WINDOWS[x][0]) <= 10)
    ok &= (P.keyL[np.minimum(ys, len(d["o"]) - 1)] - (days * 1440 + WINDOWS[y][0]) <= 10)
    ok &= (P.keyL[np.minimum(ye, len(d["o"]) - 1)] - (days * 1440 + WINDOWS[y][1]) <= 10)
    rx = np.where(ok, d["o"][np.minimum(xe, len(d["o"]) - 1)] - d["o"][np.minimum(xs, len(d["o"]) - 1)], np.nan)
    wy = np.where(ok, np.abs(d["o"][np.minimum(ye, len(d["o"]) - 1)] - d["o"][np.minimum(ys, len(d["o"]) - 1)]), np.nan)
    out = []
    for k in range(25, len(days)):
        if not ok[k]:
            continue
        pr_x = np.abs(rx[k - 20:k]); pr_y = wy[k - 20:k]
        if np.isnan(pr_x).any() or np.isnan(pr_y).any():
            continue
        Wx, Wy = pr_x.mean(), pr_y.mean()
        if Wy <= 0 or abs(rx[k]) < 0.5 * Wx:
            continue
        s = 1 if rx[k] > 0 else -1
        dirn = s if mode == "cont" else -s
        i0 = int(ys[k]) + delay
        if not P.allowed[i0 - delay] or i0 >= int(ye[k]) - 6:
            continue
        dist = 2.0 * Wy
        entry = float(d["o"][i0])
        r, ro, ix = walk(P, i0, dirn, dist, int(ye[k]), None)
        out.append(mk(P, dirn, entry, dist, r, ro, i0, ix, int(xe[k]) - 1))
    return out


# ---------------------------------------------------------------- driver
_PAIRS: dict = {}
_TR: dict = {}


def pairs(kind="ci"):
    if kind not in _PAIRS:
        _PAIRS[kind] = {s: Pair(s, p) for s, p in X.files(kind).items()}
    return _PAIRS[kind]


def trades_for(name, kind="ci", delay=0):
    k = (name, kind, delay)
    if k in _TR:
        return _TR[k]
    c = CONFIGS[name]
    tr = []
    for P in pairs(kind).values():
        if c["fam"] == "ORB":
            tr += run_ORB(P, c["mode"], c["S"], c["T"], delay)
        elif c["fam"] == "H4T":
            tr += run_H4T(P, c["N"], c["k"], delay)
        elif c["fam"] == "H1MR":
            tr += run_H1MR(P, c["z"], c["S"], delay)
        else:
            tr += run_CM(P, c["x"], c["y"], c["mode"], delay)
    tr.sort(key=lambda t: (t["t_fill"], t["sym"]))
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
    return st


def fmt(name, st):
    if not st.get("n"):
        return f"{name:26s} n=0"
    return (f"{name:26s} n={st['n']:5d} exp={st['exp']:+.3f} PF={st['pf']:.2f} gross={st['exp_gross']:+.3f} cost={st['cost_mean_R']:.3f} "
            f"lb={st['lb']:+.3f} yrs={[round(h, 2) for h in st['halves']]}")


def is_candidate(name, st):
    need = 100 if CONFIGS[name]["fam"] == "H4T" else (150 if CONFIGS[name]["fam"] == "H1MR" else 300)
    ys = [h for h in st.get("halves", []) if h == h]
    return st.get("n", 0) >= need and st["exp"] > 0 and st["lb"] > 0 and st["pf"] >= 1.10 and sum(h > 0 for h in ys) >= 3


def cmd_train():
    res = {}
    for name in CONFIGS:
        res[name] = stats_for(trades_for(name), "train")
        print(fmt(name, res[name]), "CANDIDATE" if res[name].get("n") and is_candidate(name, res[name]) else "", flush=True)
    json.dump(res, (OUT / "train.json").open("w"), default=float)
    print(f"TRIALS: {len(CONFIGS)}")
    for fam in ("ORB", "H4T", "H1MR", "CM"):
        v = [s for n, s in res.items() if CONFIGS[n]["fam"] == fam and s.get("n")]
        print(f"{fam}: {len(v)} configs, mean gross {np.mean([s['exp_gross'] for s in v]):+.4f}, mean cost {np.mean([s['cost_mean_R'] for s in v]):.3f}, "
              f"mean net {np.mean([s['exp'] for s in v]):+.4f}, positive {sum(s['exp'] > 0 for s in v)}/{len(v)}")
    print("candidates:", [n for n, s in res.items() if s.get("n") and is_candidate(n, s)])


def cmd_valid():
    train = json.load((OUT / "train.json").open())
    cands = [n for n, s in train.items() if s.get("n") and is_candidate(n, s)]
    print("TRAIN candidates:", cands or "NONE")
    ok = []
    for n in cands:
        st = stats_for(trades_for(n), "valid")
        dl = stats_for(trades_for(n, delay=3), "valid")
        good = st.get("n", 0) >= 60 and st["exp"] > 0 and st["pf"] >= 1.05 and dl.get("n", 0) and dl["exp"] > 0
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
    lab = [dict(t_fill=t["t_fill"], t_exit=t["t_exit"], R=t["R_pess"], cost=t["cost"]) for t in tr]
    chal = {}
    for r in (0.005, 0.01):
        a = C.pass_rates(lab, ms(SPLITS["test"][0]), ms(SPLITS["test"][1]), r, max_conc=2)
        z = C.pass_rates(C.zero_edge([t for t in lab if ms(SPLITS["test"][0]) <= t["t_fill"] < ms(SPLITS["test"][1])]), ms(SPLITS["test"][0]), ms(SPLITS["test"][1]), r, max_conc=2)
        chal[str(r)] = dict(real=a, null=z)
    return dict(name=name, stats=st, gates={k: [bool(v[0]), v[1]] for k, v in g.items()}, passed=all(v[0] for v in g.values()), challenge=chal)


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
        for rk, v in r["challenge"].items():
            print(f"   challenge risk {rk}: both phases in 90d {v['real']['pass_rate']:.2f} (zero-edge null {v['null']['pass_rate']:.2f})")
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
