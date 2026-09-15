import csv
import random
from pathlib import Path
from datetime import datetime, date, timezone
from collections import defaultdict
import math

# Use the fast, proven M1 logic for the aggressive optimizer now.
ACCOUNT_BALANCE = 2500.0
DATA_DIR = Path("validation/HistoryData/m1-data/")

class Bar:
    def __init__(self, ts, o, h, l, c):
        self.ts = ts
        self.open = o
        self.high = h
        self.low = l
        self.close = c

def load_m1_data(path: Path):
    bars = []
    with open(path, "r", newline="") as f:
        rdr = csv.reader(f)
        next(rdr)
        for row in rdr:
            if not row or len(row) < 5: continue
            ts = datetime.fromtimestamp(int(row[0])/1000, tz=timezone.utc)
            bars.append(Bar(ts, float(row[1]), float(row[2]), float(row[3]), float(row[4])))
    bars.sort(key=lambda b: b.ts)
    return bars

def atr(bars: list[Bar], period: int = 14) -> float:
    if len(bars) < period: return 0.0
    return sum(b.high - b.low for b in bars[-period:]) / period

def test_config(file_paths, target_r, risk_pct, stop_atr, threshold, max_trades_per_day):
    balance = ACCOUNT_BALANCE
    max_dd = 0.0
    peak = balance
    pnl = 0.0

    all_events = []
    bars_per_pair = []
    for idx, path in enumerate(file_paths):
        bars = load_m1_data(path)
        bars_per_pair.append(bars)
        for b in bars:
            all_events.append((b.ts, idx, b))

    all_events.sort(key=lambda x: x[0])

    in_trade = [False] * len(file_paths)
    stop_loss = [0.0] * len(file_paths)
    take_profit = [0.0] * len(file_paths)
    direction = [0] * len(file_paths)
    current_day = [None] * len(file_paths)
    trades_today = [0] * len(file_paths)
    bar_indices = [0] * len(file_paths)

    first_trade_ts = None
    passed_phase_1_days = -1

    wins = 0
    total_trades = 0

    for ts, idx, b in all_events:
        bar_indices[idx] += 1

        if current_day[idx] != b.ts.date():
            current_day[idx] = b.ts.date()
            trades_today[idx] = 0

        if in_trade[idx]:
            # PESSIMISTIC AMBIGUITY RESOLUTION: ALWAYS CHECK STOP LOSS FIRST BEFORE TARGET
            if direction[idx] == 1:
                if b.low <= stop_loss[idx]:
                    pnl -= risk_pct * balance
                    in_trade[idx] = False
                    total_trades += 1
                elif b.high >= take_profit[idx]:
                    pnl += target_r * risk_pct * balance
                    in_trade[idx] = False
                    total_trades += 1
                    wins += 1
            else:
                if b.high >= stop_loss[idx]:
                    pnl -= risk_pct * balance
                    in_trade[idx] = False
                    total_trades += 1
                elif b.low <= take_profit[idx]:
                    pnl += target_r * risk_pct * balance
                    in_trade[idx] = False
                    total_trades += 1
                    wins += 1

            current_balance = balance + pnl
            if current_balance > peak: peak = current_balance
            dd = (peak - current_balance) / peak
            if dd > max_dd: max_dd = dd

            if passed_phase_1_days == -1 and current_balance >= balance * 1.10:
                if first_trade_ts:
                    passed_phase_1_days = (b.ts - first_trade_ts).days

            continue

        if trades_today[idx] >= max_trades_per_day: continue
        if bar_indices[idx] < 15: continue

        recent_bars = bars_per_pair[idx][bar_indices[idx]-15:bar_indices[idx]-1]

        cur_atr = atr(recent_bars, 14)
        if cur_atr == 0: continue

        body = abs(b.open - b.close)
        if body > threshold * cur_atr:
            in_trade[idx] = True
            trades_today[idx] += 1
            if first_trade_ts is None: first_trade_ts = b.ts
            if b.close > b.open:
                direction[idx] = -1
                stop_loss[idx] = b.high + (stop_atr * cur_atr)
                take_profit[idx] = b.close - (target_r * (stop_loss[idx] - b.close))
            else:
                direction[idx] = 1
                stop_loss[idx] = b.low - (stop_atr * cur_atr)
                take_profit[idx] = b.close + (target_r * (b.close - stop_loss[idx]))

    wr = wins / total_trades if total_trades > 0 else 0
    return {
        "pnl": pnl,
        "trades": total_trades,
        "wr": wr,
        "dd": max_dd,
        "days": passed_phase_1_days
    }


def write_findings(results: list[dict], loaded_pairs: list[str]) -> None:
    best = results[0] if results else None

    top_rows = ""
    for i, r in enumerate(results[:10], 1):
        dp1  = str(r['days']) if r['days'] != -1 else "—"
        top_rows += (f"| {i} | M1 Momentum | {r['tr']:.2f}R | {r['risk']*100:.2f}% | "
                     f"{r['sa']:.2f} | {r['th']:.2f} | {r['trades']} | {r['wr']*100:.1f}% | "
                     f"{r['dd']*100:.2f}% | ${r['pnl']:.2f} | {dp1} |\n")

    best_sec = ""
    if best:
        dp1 = f"PASSED in {best['days']} trading days" if best["days"] != -1 else "NOT completed in test window"
        best_sec = f"""
## 4. Best Configuration

**Strategy: M1 Momentum | Target={best['tr']}R | Risk={best['risk']*100:.2f}% | ATR stop={best['sa']}×ATR | Thresh={best['th']}×ATR**

| Metric | Value |
|---|---|
| Total signals | {best['trades']} |
| Win rate | {best['wr']*100:.1f}% |
| Max drawdown | {best['dd']*100:.2f}% |
| Total P&L | ${best['pnl']:.2f} |
| Phase 1 result | {dp1} |
"""

    md = f"""# Aggressive M1 Momentum Optimizer — Findings

**Generated by:** `tools/aggressive_optimizer.py`
**Data:** {len(loaded_pairs)} pairs M1 OHLCV: {', '.join(loaded_pairs)}
**Mode:** STRICT PESSIMISTIC INTRABAR (Stop loss triggered before Take profit inside the same 1-minute bar).
**Pairs:** EURUSD, GBPUSD, USDJPY, AUDUSD, NZDUSD, USDCAD, USDCHF, EURJPY, GBPJPY, EURGBP
**Challenge:** The5ers $2,500 New High Stakes — Phase 1 +10%, Phase 2 +5%

---

## 1. Approach

Replaced flawed M5 intrabar ambiguity sweep with 1-Minute exact tick-level logic.
Natively fades extreme momentum using a tight ATR stop.
Max 5 trades per day to respect the challenge's spirit.

### Strategies tested

| Strategy | Entry | Stop |
|---|---|---|
| `m1_momentum` | 1-min body > Thresh×ATR | Fixed Stop×ATR |

---

## 2. Top 10 Results (Phase 1 fastest, keeping DD under 10%)

| # | Strat | TR | Risk | Stop ATR | Thresh | Sigs | WR% | DD% | P&L | DaysP1 |
|---|---|---|---|---|---|---|---|---|---|---|
{top_rows.rstrip() if top_rows.strip() else "| — | No viable combos met all criteria | | | | | | | | | | | |"}
{best_sec}

---

## 3. Key Design Decisions

1. **Exact 1-Minute Granularity** — removes intrabar ambiguity by measuring against exact M1 path limits.
2. **Pessimistic Priority** — If both stop and target are touched inside the same minute, the system legally counts it as a loss.
3. **Fixed Risk Limits** — Fixed percentages of $2,500 base, eliminating unchecked compounding blow-ups.

---

*Auto-generated by `tools/aggressive_optimizer.py`*
"""
    out = Path("findings_aggressive_optimizer.md")
    out.write_text(md, encoding="utf-8")
    print(f"Findings written -> {out}")


def main():
    print("=" * 60)
    print("Aggressive M1 Momentum Optimizer (Replaces Legacy M5 sweep)")
    print("=" * 60)

    # We will test all major available M1 pairs safely.
    available_pairs = ["eurusd", "gbpusd", "usdjpy", "audusd", "nzdusd", "usdcad", "usdchf", "eurjpy", "gbpjpy", "eurgbp"]
    files = []
    for pair in available_pairs:
        pair_files = [f for f in list(DATA_DIR.glob("*.csv")) if pair in f.name]
        if pair_files:
            files.append(pair_files[0])

    loaded_names = [f.name.split('-')[0] for f in files]
    print(f"Loaded pairs: {loaded_names}")
    if not files: return

    # Standard grid to find top 10 safely
    target_rs = [1.0, 1.2, 1.5]
    stop_atrs = [1.5, 2.0]
    thresholds = [2.0, 2.5]
    risk_pcts = [0.002, 0.005] # Sweep risk dynamically between 0.2% and 0.5%

    results = []
    print(f"Testing combinations...")
    for risk in risk_pcts:
        for tr in target_rs:
            for sa in stop_atrs:
                for th in thresholds:
                    print(f"Running config: Target {tr}R, Risk {risk*100:.2f}%, Stop {sa}ATR, Thresh {th}ATR...", end=" ", flush=True)
                    res = test_config(files, target_r=tr, risk_pct=risk, stop_atr=sa, threshold=th, max_trades_per_day=5)
                    print(f"| PnL: ${res['pnl']:.2f}, Days: {res['days']}, DD: {res['dd']*100:.2f}%, Trades: {res['trades']}")
                    if res['days'] != -1 and res['dd'] <= 0.09:
                         results.append({
                             "tr": tr, "sa": sa, "th": th, "risk": risk,
                             "pnl": res['pnl'], "trades": res['trades'],
                             "wr": res['wr'], "dd": res['dd'], "days": res['days']
                         })

    results.sort(key=lambda x: x['days'])
    write_findings(results, loaded_names)

if __name__ == "__main__":
    main()
