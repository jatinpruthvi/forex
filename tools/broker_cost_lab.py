#!/usr/bin/env python3
"""Re-cost the M5 exhaustion fade with the user's real brokers (The5ers High Stakes, Fusion Markets Zero).

The price path and the signals are unchanged (tools/exhaustion_oos_lab.py, frozen); only the cost per trade changes.
Commission (public pages, checked 2026-09-29): The5ers $4.00 round turn per lot on Forex and Gold; Fusion Markets Zero $4.50 round turn per lot.
Spreads are NOT published as a table: TYPICAL_RAW below are my assumptions for average raw spreads (pips; gold in pips of 0.10 = $0.01),
consistent with the published EURUSD 0.02-0.11, 8-pair basket average 0.36 and gold ~$0.12-0.15. Signals fire on volatility spikes, when spreads widen,
so a spread multiple is applied to the typical value. Pre-declared primary: x2.

  python tools/broker_cost_lab.py            # both windows, both brokers, spread multiples x1 / x2 / x3
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "validation" / "speed_lab"))
from tools import exhaustion_oos_lab as X  # noqa: E402
from tools import docs_v1_lab as L  # noqa: E402
from tools import challenge_sim as C  # noqa: E402
import verify_final_config as V  # noqa: E402

TYPICAL_RAW = {"EURUSD": 0.1, "GBPUSD": 0.3, "EURGBP": 0.5, "AUDUSD": 0.3, "NZDUSD": 0.6, "USDCAD": 0.5, "USDCHF": 0.5,
               "USDJPY": 0.3, "EURJPY": 0.7, "GBPJPY": 1.0, "XAUUSD": 1.5}
BROKERS = {"The5ers High Stakes": 4.00, "Fusion Markets Zero": 4.50}


def cost_R(sym: str, stop_pips: float, comm: float, mult: float) -> float:
    pip, pv, _ = V.SPECS[sym]
    return (TYPICAL_RAW[sym] * mult * pv + comm) / (stop_pips * pv + comm)


def recost(sig: list[dict], comm: float, mult: float) -> list[dict]:
    out = []
    for t in sig:
        d = dict(t)
        d["cost"] = cost_R(t["sym"], t["stop_pips"], comm, mult)
        d["cost15"] = cost_R(t["sym"], t["stop_pips"], comm, mult * 1.5)
        d["cost2"] = cost_R(t["sym"], t["stop_pips"], comm, mult * 2.0)
        d["cost3"] = cost_R(t["sym"], t["stop_pips"], comm, mult * 3.0)
        out.append(d)
    return out


def ny_minute(ts_ms: int) -> int:
    from datetime import datetime, timezone
    from zoneinfo import ZoneInfo
    d = datetime.fromtimestamp(ts_ms / 1000, tz=timezone.utc).astimezone(ZoneInfo("America/New_York"))
    return d.hour * 60 + d.minute


def in_rollover(t: dict) -> bool:
    """Signal bar starts between 16:55 and 18:10 New York time: the 17:00 NY daily rollover, when quoted spreads blow out."""
    return 16 * 60 + 55 <= ny_minute(t["t_sig"]) <= 18 * 60 + 10


def rollover_report() -> None:
    """Split the fade by rollover window vs the rest, on the clean 2016-22 window (Dukascopy), the tuned 2022-26 window (Dukascopy and tracked FSB),
    and the repo verifier's own 2024-26 window (tracked FSB, repo rule and repo costs)."""
    def line(lbl, rows, repo=False):
        if not rows:
            return
        g = np.array([t["R_repo" if repo else "R_strict"] for t in rows]); c = np.array([t["cost"] for t in rows])
        print(f"  {lbl:42s} n={len(rows):5d} gross={g.mean():+.3f} cost={c.mean():.3f} net={(g - c).mean():+.3f}")
    for kind, lo, hi, repo, title in (("ci", "2016-09-11", "2022-09-11", False, "Dukascopy 2016-22 (clean), repo costs, strict"),
                                      ("ci", "2022-09-11", "2026-09-11", False, "Dukascopy 2022-26 (tuned), repo costs, strict"),
                                      ("tracked", "2022-09-11", "2026-09-11", False, "tracked FSB 2022-26, repo costs, strict"),
                                      ("tracked", "2024-09-11", "2026-09-11", True, "tracked FSB 2024-26 (verifier window), repo rule + costs")):
        sig = [t for t in X.all_signals(kind) if X.ms(lo) <= t["t_sig"] < X.ms(hi)]
        print(title)
        line("all signals", sig, repo)
        line("rollover window 16:55-18:10 NY", [t for t in sig if in_rollover(t)], repo)
        line("everything else", [t for t in sig if not in_rollover(t)], repo)
    print("Everything else, The5ers $4 + typical raw spread, strict, 2016-22 / 2022-26 (Dukascopy):")
    sig = X.all_signals("ci")
    ex = [t for t in sig if not in_rollover(t)]
    for mult in (1.0, 2.0, 3.0):
        rs = recost(ex, 4.0, mult)
        out = []
        for lo, hi in (("2016-09-11", "2022-09-11"), ("2022-09-11", "2026-09-11")):
            w = [t for t in rs if X.ms(lo) <= t["t_sig"] < X.ms(hi)]
            out.append(f"n={len(w)} net={np.mean([t['R_strict'] - t['cost'] for t in w]):+.3f}")
        print(f"  spread x{mult:.0f}: " + " | ".join(out))


if __name__ == "__main__" and len(sys.argv) > 1 and sys.argv[1] == "rollover":
    rollover_report()
elif __name__ == "__main__":
    sig = X.all_signals("ci")
    windows = {"2016-22 (clean OOS)": ("2016-09-11", "2022-09-11", X.YEARS_OOS), "2022-26 (tuned)": ("2022-09-11", "2026-09-11", X.YEARS_REP)}
    for bname, comm in BROKERS.items():
        for wl, (lo, hi, edges) in windows.items():
            for mult in (1.0, 2.0, 3.0):
                rs = recost(sig, comm, mult)
                ev = X.evaluate(rs, X.ms(lo), X.ms(hi), edges, wl, boot=3000)
                st = ev["stats"]
                tr = [dict(t_fill=t["t_fill"], t_exit=t["t_exit"], R=t["R_strict"], cost=t["cost"]) for t in rs if X.ms(lo) <= t["t_fill"] < X.ms(hi)]
                p = [C.pass_rates(tr, X.ms(lo), X.ms(hi), r, max_conc=1)["pass_rate"] for r in (0.005, 0.01)]
                g = ev["gates"]
                print(f"{bname:20s} {wl:20s} spread x{mult:.0f}: n={st['n']} cost={st['cost_mean_R']:.3f}R net={st['exp']:+.3f} PF={st['pf']:.2f} lb90={st['lb90']:+.3f} "
                      f"yrs+={sum(1 for h in st['halves'] if h == h and h > 0)}/{len(st['halves'])} "
                      f"gates {''.join(k[1] if v[0] else '-' for k, v in g.items())} | 90d both-phase pass 0.5%/1%: {p[0]:.2f}/{p[1]:.2f}", flush=True)
