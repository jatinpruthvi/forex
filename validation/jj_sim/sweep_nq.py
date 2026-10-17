"""Parameter sweep across JJ-strategy settings on real NQ M1 data.

Runs many combinations of signals-on/off and RR ratios, printing a table of
pass rate, win rate, and EV per eval dollar. This is the first real-market
answer to "is it profitable".

Usage:
    python3 validation/jj_sim/sweep_nq.py
"""
from __future__ import annotations

import copy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

import pandas as pd  # noqa: E402

from validation.jj_sim.simulator import (  # noqa: E402
    FirmRules,
    detect_bos,
    detect_displacement,
    load_m1_csv,
    simulate,
)

DATA = "validation/HistoryData/nq-m1-data/NQ_1min_20260120_20260415.csv"

N_ACCOUNTS = 20
# Sweep RR values relevant to JJ's framework:
RRS = [1.0, 1.5, 2.0, 3.0]
# Sweep risk per trade:
RISKS = [0.005, 0.01]
# Signal permutations (start with individual signals, then all-combined):
SIGNAL_SETS = [
    {"DC": True,  "BoS": False, "NR": False, "SOC": False},
    {"DC": False, "BoS": True,  "NR": False, "SOC": False},
    {"DC": True,  "BoS": True,  "NR": False, "SOC": False},
]


def main():
    bars = load_m1_csv(DATA)
    print(f"Loaded {len(bars):,} bars from {DATA}")
    first = pd.Timestamp(bars["ts_dt"][0]).tz_convert("US/Eastern")
    last = pd.Timestamp(bars["ts_dt"][-1]).tz_convert("US/Eastern")
    print(f"Range (ET): {first} -> {last}\n")

    rows = []
    for sigs in SIGNAL_SETS:
        sig_label = "+".join(k for k, v in sigs.items() if v)
        for rr in RRS:
            for risk in RISKS:
                rules = copy.deepcopy(FirmRules.presets()["eval_1to1_5"])
                rules.name = f"nq_{sig_label}_rr{rr}_risk{risk}"
                rules.rr = rr
                rules.risk_per_trade_pct = risk
                # Make target+drawdown slightly looser for NQ (larger daily range):
                rules.profit_target_pct = 0.10
                rules.overall_drawdown_pct = 0.10
                rules.daily_loss_pct = 0.05
                rules.trailing_drawdown = True
                res = simulate(
                    bars=bars, rules=rules, n_accounts=N_ACCOUNTS,
                    news_events=[], signals_enabled=sigs,
                )
                total_closed = sum(a.wins + a.losses for a in res.accounts)
                wins = sum(a.wins for a in res.accounts)
                wr = wins / total_closed if total_closed else 0
                rows.append({
                    "signals": sig_label,
                    "rr": rr,
                    "risk_pct": risk,
                    "signals_fired": res.signals_fired,
                    "trades": res.trades_taken,
                    "win_rate": wr,
                    "pass_rate": res.pass_rate,
                    "cost_per_funded": res.cost_per_funded if res.pass_rate > 0 else float("inf"),
                    "ev_per_eval_dollar": res.ev_per_eval_dollar,
                    "breakeven_wr": 1.0 / (1.0 + rr),
                    "wr_minus_be": wr - 1.0 / (1.0 + rr),
                    "active": sum(1 for a in res.accounts if a.status == "active"),
                    "failed": sum(1 for a in res.accounts if a.status == "failed"),
                    "passed": sum(1 for a in res.accounts if a.status == "passed"),
                })

    df = pd.DataFrame(rows)
    pd.set_option("display.width", 200)
    pd.set_option("display.max_columns", 20)
    pd.set_option("display.float_format", lambda x: f"{x:.3f}")
    print(df.to_string(index=False))

    # Find best by EV per eval dollar
    print("\n--- Top 5 by EV per $ eval (gross of costs/spread) ---")
    print(df.sort_values("ev_per_eval_dollar", ascending=False).head(5).to_string(index=False))
    print("\n--- Top 5 by raw win-rate-above-breakeven (most positive edge) ---")
    print(df.sort_values("wr_minus_be", ascending=False).head(5).to_string(index=False))

    out = "validation/jj_sim/nq_sweep_results.csv"
    df.to_csv(out, index=False)
    print(f"\nWrote {out}")


if __name__ == "__main__":
    main()
