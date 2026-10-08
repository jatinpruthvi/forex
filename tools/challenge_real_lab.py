#!/usr/bin/env python3
"""Structural-EV test on REAL price paths: a rule-based, no-edge "bracket" trader (random direction, random liquid-hour entry, one trade a day)
runs a full The5ers-High-Stakes-style challenge (Phase 1 +10 %, Phase 2 +5 %, 5 % daily loss, 10 % static max loss, 3 profitable days >= 0.5 % per phase)
and then funded payout rounds, starting on many historical days. Pre-registered in docs/research/findings/findings_challenge_real.md.
  python tools/challenge_real_lab.py train | confirm --confirm
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "validation" / "speed_lab"))
from tools import tradable_search_lab as T  # noqa: E402
from tools import family_search_lab as F  # noqa: E402
from tools import broker_cost_lab as B  # noqa: E402

OUT = Path("/tmp/challenge_real_out")
OUT.mkdir(exist_ok=True)
ms = T.ms
SYMS = ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "XAUUSD"]
COMM = 4.0
N_CAND = 8                                   # random candidate entry bars per (pair, day), both directions
DAY_LON = 1440
ENTRY_WIN = (480, 960)                       # London clock 08:00-16:00 (New York 03:00-11:00)
EXIT_MIN = 1200                              # flat by London 20:00
STOP_ATR = 0.5                               # stop = 0.5 x daily ATR20
NEWS_NY = [(508, 515), (598, 605), (838, 845)]   # 08:28-08:35, 09:58-10:05, 13:58-14:05 New York (+-2 min of typical releases, widened)
RULES = dict(t1=0.10, t2=0.05, daily=0.05, floor=0.10, min_days=3, day_profit=0.005, fund_w=0.05, split=0.80, rounds=5, pay_gap_days=14, cap_days=700)
RULES2 = dict(RULES, cap_days=1500, withdraw_fee=0.035)      # round 2: compliance-constrained (see findings_challenge_real.md section 6)

CONFIGS = {}
CONFIGS2 = {}
for risk in (0.01, 0.015, 0.02):
    for R in (1.0, 2.0):
        for m in (2.0, 6.0):
            CONFIGS2[f"c_r{risk*100:g}_R{R:g}_m{m:g}"] = dict(risk=risk, R=R, mult=m)
for risk in (0.025, 0.04):
    for R in (1.0, 2.0):
        for m in (2.0, 6.0):
            CONFIGS[f"r{risk*100:g}_R{R:g}_m{m:g}"] = dict(risk=risk, R=R, mult=m)


class World:
    """Pre-resolved random candidate trades on real data, per (sym, london day)."""
    def __init__(self, R: float, seed: int = 7):
        rng = np.random.default_rng(seed)
        self.R = R
        self.tab: dict[int, list] = {}           # day -> list of trade tuples (R_strict, stop_pips, sym, sign_ok)
        pairs = T.pairs("ci")
        for sym in SYMS:
            P = pairs[sym]
            dd = F.daily(P.d)
            days = np.unique(P.dayL)
            days = days[((days + 3) % 7) < 5]
            a = np.searchsorted(P.keyL, days * DAY_LON + ENTRY_WIN[0], "left")
            b = np.searchsorted(P.keyL, days * DAY_LON + ENTRY_WIN[1], "left")
            x = np.searchsorted(P.keyL, days * DAY_LON + EXIT_MIN, "left")
            news = np.zeros(len(P.nym), bool)
            for lo, hi in NEWS_NY:
                news |= (P.nym >= lo) & (P.nym < hi)
            ok = P.allowed & ~news
            for k, day in enumerate(days):
                ia_, ib_, ix = int(a[k]), int(b[k]), int(x[k])
                if ib_ - ia_ < 60 or ix >= len(P.d["o"]) - 1 or ix <= ib_ + 12:
                    continue
                cand = np.flatnonzero(ok[ia_:ib_]) + ia_
                if len(cand) < 10:
                    continue
                pick = rng.choice(cand, size=min(N_CAND, len(cand)), replace=False)
                ja = int(np.searchsorted(dd["je"], ia_, "right")) - 1
                if ja < 0 or not np.isfinite(dd["atr"][ja]):
                    continue
                dist = STOP_ATR * float(dd["atr"][ja])
                for i0 in pick:
                    for dirn in (1, -1):
                        entry = float(P.d["o"][i0])
                        tgt = entry + dirn * R * dist
                        r_s, _, _ = T.walk(P, int(i0), dirn, dist, ix, tgt_price=tgt)
                        self.tab.setdefault(int(day), []).append((float(r_s), dist / P.pip, sym))
        self.days = np.array(sorted(self.tab))
        self.ts_day = {d: d for d in self.days}


def trade_net(row, mult):
    r, sp, sym = row
    return r - B.cost_R(sym, sp, COMM, mult)


def run_path(world: World, start_idx: int, cfg: dict, rng: np.random.Generator, rules=RULES):
    """Returns dict(stage reached, payouts list in fraction of account, days used). Steps through real trading days from start_idx."""
    risk, mult = cfg["risk"], cfg["mult"]
    days = world.days
    i = start_idx
    res = dict(p1=False, p2=False, payouts=[], end="open", days=0)
    stage, eq, prof_days, last_pay_day = 1, 0.0, 0, None
    target = rules["t1"]
    n_days = 0
    while i < len(days) and n_days < rules["cap_days"]:
        day = int(days[i]); rows = world.tab[day]
        if stage == 3 and eq >= rules["fund_w"]:                 # target reached: stop risking it, wait for the payout window
            n_days += 1; i += 1
            if day - last_pay_day >= rules["pay_gap_days"]:
                res["payouts"].append(rules["split"] * eq * (1 - rules.get("withdraw_fee", 0.0)))
                eq, last_pay_day = 0.0, day
                if len(res["payouts"]) >= rules["rounds"]:
                    res["end"] = "max_rounds"; break
            continue
        row = rows[int(rng.integers(len(rows)))]
        pnl = risk * trade_net(row, mult)
        n_days += 1; i += 1
        if pnl <= -rules["daily"]:
            res["end"] = f"daily_breach_stage{stage}"; break
        eq += pnl
        if pnl >= rules["day_profit"]:
            prof_days += 1
        if eq <= -rules["floor"]:
            res["end"] = f"blown_stage{stage}"; break
        if stage in (1, 2):
            if eq >= target and prof_days >= rules["min_days"]:
                res["p1" if stage == 1 else "p2"] = True
                if stage == 1:
                    stage, eq, prof_days, target = 2, 0.0, 0, rules["t2"]
                else:
                    stage, eq, prof_days, last_pay_day = 3, 0.0, 0, day
        else:
            pass                                               # payout handled at the top of the loop once the target is reached
    res["days"] = n_days
    return res


def evaluate(world: World, cfg: dict, lo: str, hi: str, n_paths: int = 3000, seed: int = 3, fee: float = 0.006, rules=RULES):
    rng = np.random.default_rng(seed)
    idx = np.flatnonzero((world.days >= ms(lo) // 86_400_000) & (world.days < ms(hi) // 86_400_000))
    out = []
    for _ in range(n_paths):
        out.append(run_path(world, int(rng.choice(idx)), cfg, rng, rules))
    p1 = np.mean([o["p1"] for o in out]); p2 = np.mean([o["p2"] for o in out])
    pay = np.array([sum(o["payouts"]) for o in out])
    unfinished = np.mean([o["end"] == "open" for o in out])
    first = np.mean([len(o["payouts"]) > 0 for o in out])
    ev = pay.mean() - fee
    se = pay.std() / np.sqrt(len(pay))
    return dict(p1=float(p1), both=float(p2), first_payout=float(first), ev_pct=float(ev * 100), ev_x_fee=float(ev / fee), se_pct=float(se * 100),
                mean_payout_pct=float(pay.mean() * 100), unfinished=float(unfinished), mean_days=float(np.mean([o["days"] for o in out])))


_W: dict = {}


def world(R):
    if R not in _W:
        _W[R] = World(R)
    return _W[R]


def diag():
    """Is the trader really at zero edge? Mean strict R of the pre-resolved random trades (before costs), win rate, by R."""
    for R in (1.0, 2.0):
        w = world(R)
        r = np.array([t[0] for v in w.tab.values() for t in v])
        print(f"R={R:g}: n={len(r)} mean R gross={r.mean():+.4f} (expect about {(1/(R+1))*R-(1-1/(R+1)):+.3f} = 0 by construction less time exits) win%={100*(r>0.99*R).mean():.1f} stop%={100*(r<=-0.99).mean():.1f}")


def cmd_train():
    diag()
    res = {}
    for name, cfg in CONFIGS.items():
        res[name] = evaluate(world(cfg["R"]), cfg, "2016-10-01", "2021-09-01")
        r = res[name]
        print(f"{name:16s} P1={r['p1']:.2f} both={r['both']:.2f} first payout={r['first_payout']:.2f} meanpay={r['mean_payout_pct']:.2f}% EV={r['ev_pct']:+.2f}% ({r['ev_x_fee']:+.1f}x fee, se {r['se_pct']:.2f}%) unfinished={r['unfinished']:.2f} days={r['mean_days']:.0f}", flush=True)
    json.dump(res, (OUT / "train.json").open("w"))
    best = max(res, key=lambda k: res[k]["ev_pct"] if CONFIGS[k]["mult"] == 2.0 else -9)
    json.dump(best, (OUT / "best.json").open("w"))
    print("best at declared cost (m=2) on TRAIN starts:", best)


def cmd_confirm(confirm):
    lock = OUT / "confirm.lock"
    if not confirm or lock.exists():
        sys.exit("refusing: CONFIRM is one look (needs --confirm; lock exists=%s)" % lock.exists())
    best = json.load((OUT / "best.json").open())
    lock.write_text(best)
    base = CONFIGS[best]
    for m in (2.0, 6.0):
        cfg = dict(base, mult=m)
        r = evaluate(world(cfg["R"]), cfg, "2021-09-01", "2024-09-01", n_paths=6000, seed=11)
        print(f"{best} at cost x{m:g} on CONFIRM starts 2021-09..2024-09: P1={r['p1']:.2f} both={r['both']:.2f} first payout={r['first_payout']:.2f} "
              f"EV={r['ev_pct']:+.2f}% of account ({r['ev_x_fee']:+.1f}x a 0.6% fee, se {r['se_pct']:.2f}%) unfinished={r['unfinished']:.2f}")
        for fee in (0.003, 0.006, 0.01):
            print(f"   fee {fee*100:.1f}%: EV {(r['mean_payout_pct']/100 - fee)*100:+.2f}% = {(r['mean_payout_pct']/100 - fee)/fee:+.1f}x fee")


def cmd_train2():
    res = {}
    for name, cfg in CONFIGS2.items():
        res[name] = evaluate(world(cfg["R"]), cfg, "2016-10-01", "2021-09-01", fee=0.008, rules=RULES2)
        r = res[name]
        print(f"{name:16s} P1={r['p1']:.2f} both={r['both']:.2f} first payout={r['first_payout']:.2f} meanpay={r['mean_payout_pct']:.2f}% EV={r['ev_pct']:+.2f}% ({r['ev_x_fee']:+.1f}x fee, se {r['se_pct']:.2f}%) unfinished={r['unfinished']:.2f} days={r['mean_days']:.0f}", flush=True)
    json.dump(res, (OUT / "train2.json").open("w"))
    best = max(res, key=lambda k: res[k]["ev_pct"] if CONFIGS2[k]["mult"] == 2.0 else -9)
    json.dump(best, (OUT / "best2.json").open("w"))
    print("best at declared cost (m=2) on TRAIN starts:", best)


def cmd_confirm2(confirm):
    lock = OUT / "confirm2.lock"
    if not confirm or lock.exists():
        sys.exit("refusing: CONFIRM2 is one look (needs --confirm; lock exists=%s)" % lock.exists())
    best = json.load((OUT / "best2.json").open())
    lock.write_text(best)
    base = CONFIGS2[best]
    for label, rules in (("daily 5% / max 10%", RULES2), ("daily 4% / max 8% (stricter)", dict(RULES2, daily=0.04, floor=0.08))):
        for m in (2.0, 6.0):
            cfg = dict(base, mult=m)
            r = evaluate(world(cfg["R"]), cfg, "2021-09-01", "2024-09-01", n_paths=6000, seed=11, fee=0.008, rules=rules)
            print(f"{best} [{label}] cost x{m:g}: P1={r['p1']:.2f} both={r['both']:.2f} first payout={r['first_payout']:.2f} mean payout={r['mean_payout_pct']:.2f}% "
                  f"EV={r['ev_pct']:+.2f}% ({r['ev_x_fee']:+.1f}x a 0.8% fee, se {r['se_pct']:.2f}%) unfinished={r['unfinished']:.2f} days={r['mean_days']:.0f}")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("train"); sub.add_parser("diag"); sub.add_parser("train2")
    c = sub.add_parser("confirm"); c.add_argument("--confirm", action="store_true")
    c2 = sub.add_parser("confirm2"); c2.add_argument("--confirm", action="store_true")
    a = ap.parse_args()
    {"train": cmd_train, "diag": diag, "train2": cmd_train2}.get(a.cmd, lambda: cmd_confirm2(a.confirm) if a.cmd == "confirm2" else cmd_confirm(a.confirm))()


if __name__ == "__main__":
    main()
