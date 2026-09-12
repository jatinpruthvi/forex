"""Deep validation of 4-year results — sanity check lots, P&L, drawdown, per-pair stats."""
import sys, os
sys.path.insert(0, os.path.abspath('.'))
import tools.aggressive_optimizer as m
from collections import defaultdict
import statistics

print("=" * 65)
print("4-Year Data Deep Validation")
print("=" * 65)

# Load 4-year data
print("\nLoading data...")
cache = {}
for sym in m.SPECS:
    bars = m.load_pair(sym)
    if bars:
        by_date, atr_map = m.preprocess(bars)
        cache[sym] = (by_date, atr_map)
        print(f"  {sym:<8} {len(bars):>7} bars  {len(by_date):>5} days  "
              f"({list(by_date.keys())[0]} to {list(by_date.keys())[-1]})")

# Best config from grid run: orb_atr T=3.0R RB=8bars ATR=0.25
# (highest monthly P&L: $358.78, Phase1 in 12 days)
print("\n" + "=" * 65)
print("Running best config: orb_atr T=3.0R RB=8bars ATR=0.25")
r = m.run_backtest(cache, 'orb_atr', 3.0, 8, 0.25)

print(f"\n  Signals:     {r['signals']} ({r['wins']}W / {r['losses']}L / {r['time_exits']}T)")
print(f"  Win rate:    {r['win_rate']*100:.1f}%")
print(f"  Avg R:       {r['avg_r']:.3f}")
print(f"  Profit fac:  {r['profit_factor']:.2f}")
print(f"  Max DD:      {r['max_dd_pct']:.2f}%")
print(f"  Total P&L:   ${r['total_cash']:.2f} over {r['trading_days']} days")
print(f"  Monthly est: ${r['monthly_pnl']:.2f}")
print(f"  Final bal:   ${r['final_balance']:.2f}")
print(f"  Phase 1:     {'PASSED in ' + str(r['days_to_p1']) + ' trading days' if r['phase1_done'] else 'NOT COMPLETED'}")
print(f"  Qual days:   {r['qual_days']}")

# Per-trade P&L sanity check
wins = [t for t in r['all_trades'] if t.exit_reason == "target"]
losses = [t for t in r['all_trades'] if t.exit_reason == "stop"]
times = [t for t in r['all_trades'] if t.exit_reason == "time"]
print(f"\n  Avg winning trade: ${sum(t.pnl_cash for t in wins)/len(wins):.2f}  (expected ~+$26 before comm adj)")
print(f"  Avg losing trade:  ${sum(t.pnl_cash for t in losses)/len(losses):.2f}  (expected ~-$10)")
print(f"  Avg time exit:     ${sum(t.pnl_cash for t in times)/len(times):.2f}" if times else "  No time exits")

# Per-pair breakdown
print(f"\n  Per-pair (sorted by P&L):")
print(f"  {'Pair':<8} {'N':>5} {'WR%':>6} {'Lots':>6} {'Total$':>10} {'Avg$/tr':>9} {'AvgR':>7}")
print("  " + "-" * 58)
for sym, pp in sorted(r['per_pair'].items(), key=lambda x: x[1]['pnl'], reverse=True):
    if pp['n'] == 0: continue
    wr = pp['w'] / pp['n'] * 100
    avg_cash = pp['pnl'] / pp['n']
    avg_r = pp['r'] / pp['n']
    sym_trades = [t for t in r['all_trades'] if t.pair == sym]
    avg_lots = sum(t.lots for t in sym_trades) / len(sym_trades) if sym_trades else 0
    print(f"  {sym:<8} {pp['n']:>5} {wr:>6.1f} {avg_lots:>6.2f} {pp['pnl']:>10.2f} {avg_cash:>9.2f} {avg_r:>7.3f}")

# Lot sizing spot check — 3 sample trades per top pair
print(f"\n  Sample trades (first 3 from top pairs, lot size check):")
print(f"  {'Pair':<8} {'Dir':>6} {'Entry':>8} {'Stop':>8} {'stop_d':>8} {'Lots':>6} {'PnL$':>8} {'Reason'}")
print("  " + "-" * 65)
shown = defaultdict(int)
for t in r['all_trades']:
    if shown[t.pair] >= 3: continue
    if t.pair not in ['GBPJPY', 'EURJPY', 'XAUUSD', 'EURUSD']: continue
    stop_d = abs(t.entry - t.stop)
    print(f"  {t.pair:<8} {t.direction:>6} {t.entry:>8.4f} {t.stop:>8.4f} {stop_d:>8.5f} {t.lots:>6.2f} {t.pnl_cash:>8.2f}  {t.exit_reason}")
    shown[t.pair] += 1

# Year-by-year performance
print(f"\n  Year-by-year equity:")
equity = r['equity']
by_year = defaultdict(list)
for d, v in equity:
    by_year[d.year].append(v)
for yr in sorted(by_year):
    start = by_year[yr][0]
    end = by_year[yr][-1]
    gain = end - start
    sign = '+' if gain >= 0 else ''
    print(f"    {yr}: ${start:>8.0f} -> ${end:>8.0f}  ({sign}{gain:.0f})")

# Max intra-year DD check
print(f"\n  Max intra-year drawdown:")
for yr in sorted(by_year):
    pts = by_year[yr]
    peak = pts[0]
    worst_dd = 0.0
    for v in pts:
        peak = max(peak, v)
        worst_dd = max(worst_dd, (peak - v) / peak * 100)
    print(f"    {yr}: max DD = {worst_dd:.2f}%")

# Run second-best config for comparison
print(f"\n{'='*65}")
print("Running #5 (highest AvgR): orb_atr T=3.0R RB=8bars ATR=0.25 — same, confirm")
print("Running true #5 (orb_atr T=3.0R RB=8 ATs=0.25) already shown.")
print("Showing orb_atr T=2.5R RB=8 ATs=0.25 for comparison:")
r2 = m.run_backtest(cache, 'orb_atr', 2.5, 8, 0.25)
print(f"  Signals={r2['signals']} WR={r2['win_rate']*100:.1f}% AvgR={r2['avg_r']:.3f} "
      f"DD={r2['max_dd_pct']:.2f}% Mth=${r2['monthly_pnl']:.2f} P1={'YES in '+str(r2['days_to_p1'])+'d' if r2['phase1_done'] else 'NO'}")
