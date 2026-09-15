import csv
from pathlib import Path
from datetime import datetime, timezone

ACCOUNT_BALANCE = 2500.0

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

def test_holy_grail_portfolio(file_paths, target_r=1.0, risk_pct=0.005, stop_atr=2.0, threshold=2.5, max_trades_per_day=5):
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

if __name__ == "__main__":
    DATA_DIR = Path("validation/HistoryData/m1-data/")
    files = [f for f in list(DATA_DIR.glob("*.csv")) if "eurusd" in f.name]

    print("Testing true portfolio timeline to pass Phase 1 (M1 Unified Chronological Timeline)...")

    # We test the top 3 best configurations from our sweep
    configs = [
        {"target_r": 1.0, "risk_pct": 0.005, "stop_atr": 1.5, "threshold": 2.5},
        {"target_r": 1.5, "risk_pct": 0.005, "stop_atr": 1.5, "threshold": 2.5},
        {"target_r": 1.0, "risk_pct": 0.005, "stop_atr": 2.0, "threshold": 2.5},
    ]

    for c in configs:
        res = test_holy_grail_portfolio(files, target_r=c['target_r'], risk_pct=c['risk_pct'],
                                        stop_atr=c['stop_atr'], threshold=c['threshold'], max_trades_per_day=5)

        print(f"\nConfiguration: Target R: {c['target_r']}, Stop ATR: {c['stop_atr']}, Threshold: {c['threshold']}")
        print(f"Results for EURUSD Only (Risk: 0.5% per trade, Max 5 trades/day):")
        print(f"  Total Trades: {res['trades']}")
        print(f"  Win Rate: {res['wr']*100:.1f}%")
        print(f"  Maximum Account Drawdown: {res['dd']*100:.2f}%")
        print(f"  Total PnL Generated: ${res['pnl']:.2f}")
        print(f"  ** Days to pass Phase 1 (+10%): {res['days']} days! **")
