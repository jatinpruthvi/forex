# Strategy Tester & Optimization — Methodology and Automation

Scope: HOW to test and optimize correctly. Tester **traps** live in `pitfalls.md §4`; the `OnTester` template in `pitfalls.md §5` — cross-reference, do not duplicate.

## Contents
1. Modeling modes — selection matrix
2. Validity requirements for a backtest
3. TesterStatistics — full constant table
4. Metric thresholds
5. Walk-forward analysis (native MT5)
6. Optimization workflow
7. Frames — inter-pass data collection (Monte Carlo base)
8. Multi-currency testing
9. Tester automation via CLI (agentic workflow)

---

## 1. Modeling modes — selection matrix

| Mode | Speed | Fidelity | Use for |
|---|---|---|---|
| Every tick based on real ticks | slowest | broker-recorded ticks | final validation; scalpers; XAUUSD/news-sensitive logic |
| Every tick | slow | generated ticks | final validation when real ticks unavailable |
| 1-minute OHLC | medium | 4 ticks per M1 bar | default for bar-close strategies |
| Open prices only | fast | bar opens only | mass optimization of strictly new-bar EAs ONLY |
| Math calculations | instant | no market | pure computation / OnTester research |

Workflow rule: optimize on the cheapest mode the strategy's logic tolerates, validate every surviving parameter set on "Every tick based on real ticks". An EA with any intra-bar dependence (trailing per tick, breakeven, partial closes on price levels) is NOT eligible for "Open prices only" (pitfalls.md §4).

## 2. Validity requirements for a backtest

- ≥ 1,000 trades (target 2,000+) — below that, expectancy confidence intervals are too wide to act on.
- ≥ 2 full market regimes (trend + range; ideally bull + bear + range) — multiple years.
- Real spread or realistically raised fixed spread; add commission and average slippage in tester settings for netting with the live broker.
- Same server/symbol specs as the live account (tick size, stops level, sessions) — test on the broker's own data when possible.
- History quality ≥ 99% for tick modes; check the tester journal for "mismatched charts" errors.

## 3. TesterStatistics — full constant table

| Constant | Meaning |
|---|---|
| STAT_PROFIT | net profit |
| STAT_GROSS_PROFIT / STAT_GROSS_LOSS | gross sides |
| STAT_TRADES | total trades |
| STAT_PROFIT_TRADES / STAT_LOSS_TRADES | winners / losers |
| STAT_PROFIT_FACTOR | gross profit / gross loss |
| STAT_EXPECTED_PAYOFF | net profit / trades |
| STAT_SHARPE_RATIO | Sharpe |
| STAT_RECOVERY_FACTOR | net profit / max DD |
| STAT_EQUITY_DD / STAT_EQUITY_DD_PERCENT / STAT_EQUITY_DD_RELATIVE | equity drawdowns (money / % / relative %) |
| STAT_BALANCE_DD / STAT_BALANCE_DD_PERCENT | balance drawdowns |
| STAT_MAX_PROFITTRADE / STAT_MAX_LOSSTRADE | largest single trades |
| STAT_CONPROFITMAX / STAT_CONLOSSMAX | max consecutive profit / loss |
| STAT_SHORT_TRADES / STAT_LONG_TRADES | direction counts |
| STAT_WIN_SHORT_TRADES / STAT_WIN_LONG_TRADES | direction winners |
| STAT_INITIAL_DEPOSIT / STAT_WITHDRAWAL | cash flows |
| STAT_MIN_MARGINLEVEL | worst margin level |

## 4. Metric thresholds

| Metric | Acceptable | Strong |
|---|---|---|
| Profit factor | > 1.5 | > 2.0 |
| Sharpe | > 1.0 | > 2.0 |
| Recovery factor | > 3.0 | > 5.0 |
| Max relative DD | < 20% | < 10% |
| Expected payoff | > spread+commission cost per trade | — |

Reject in OnTester before scoring: `STAT_TRADES < 100`, `STAT_EQUITY_DD_RELATIVE > 25`, `STAT_PROFIT_FACTOR < 1.3` (template: pitfalls.md §5). For funded/prop targets, tighten DD to the firm's daily/total limits minus buffer (trading.md §12).

## 5. Walk-forward analysis (native MT5)

```
W1: [======= IS =======][ OOS ]
W2:    [======= IS =======][ OOS ]
W3:       [======= IS =======][ OOS ]
```
1. Strategy Tester → Settings → **Forward** = 1/4 (or 1/3): MT5 splits the date range, optimizes on IS, replays best passes on OOS automatically.
2. Accept a parameter set only if OOS performance ≥ 50–80% of IS (walk-forward efficiency `WFE = OOS return / IS return`).
3. Manual rolling WFA (stronger): repeat with the window slid forward (e.g., 12-month IS / 3-month OOS, step 3 months); a strategy must survive most windows, not one.
4. A big IS/OOS gap = overfit — reduce optimized parameter count (every added parameter is a curve-fitting axis), widen parameter steps, or discard.

## 6. Optimization workflow

1. Freeze structure first — never optimize while still editing logic.
2. Optimize ≤ 3–4 parameters at a time; coarse steps first (genetic), refine winners with narrow ranges (slow complete).
3. Optimization criterion: custom OnTester score (pitfalls.md §5) beats built-in "Balance max" — balance-max selects lottery outliers.
4. Select from a **plateau** of neighboring good results, never the single best cell; a sharp isolated peak is noise. Inspect the 2-parameter optimization graph for contiguous green regions.
5. Validate the chosen set: Every-tick-real run + forward period + (if available) second broker's data.
6. Re-optimization cadence: only at fixed calendar intervals decided in advance — re-optimizing after every losing week is curve-fitting in slow motion.

## 7. Frames — inter-pass data collection (Monte Carlo base)

Frames pass per-pass data from agents to the terminal during optimization:

```mql5
// EA side — end of each pass
double OnTester()
{
   double score = /* ... */;
   double payload[]; /* fill: per-trade returns, DD path, etc. */
   FrameAdd("stats", 1, score, payload);
   return score;
}
// Terminal side (same EA, runs only in the terminal during optimization)
void OnTesterPass()
{
   ulong pass; string name; long id; double val; double data[];
   while(FrameNext(pass, name, id, val, data)) { /* aggregate */ }
}
void OnTesterDeinit() { /* final report/file across all passes */ }
```

Monte Carlo without external tools: collect per-trade returns via frames, then reshuffle trade order / resample with replacement N thousand times in OnTesterDeinit; report the DD distribution (95th percentile DD, risk of ruin at the chosen risk-per-trade). A strategy whose 95th-percentile shuffled DD breaches the account's kill-switch level fails, regardless of the pretty original equity curve.

## 8. Multi-currency testing

- The MT5 tester natively feeds all symbols an EA subscribes to (`SymbolSelect`, handles on other symbols) — one pass tests a whole portfolio EA (architecture: advanced.md §7).
- Tick sync across symbols is simulated; OnTick fires for the chart symbol only — poll others via handles/CopyRates, or use OnTimer logic identical to live.
- Verify margin interplay: simultaneous positions on correlated symbols (XAUUSD+XAGUSD) can breach margin in test exactly as live — check STAT_MIN_MARGINLEVEL.

## 9. Tester automation via CLI (agentic workflow)

Headless backtests for Claude Code / scripted loops — no GUI interaction:

```ini
; tester.ini
[Tester]
Expert=MyEA\DTC_Lite            ; path under MQL5\Experts, no extension
Symbol=XAUUSD
Period=M5
Model=4                          ; 0=every tick,1=1m OHLC,2=open only,3=math,4=real ticks
FromDate=2024.01.01
ToDate=2026.06.01
Deposit=10000
Leverage=1:100
Optimization=0                   ; 0=off,1=slow complete,2=genetic,3=all symbols
Report=reports\dtc_report        ; html/htm output
ShutdownTerminal=1               ; exit when done — mandatory for scripting
ExpertParameters=MyEA.set        ; optional .set file with inputs
```
```
terminal64.exe /config:C:\path\tester.ini
```
- Compile first via `metaeditor64.exe /compile:"MQL5\Experts\MyEA\DTC_Lite.mq5" /log` — the log file (UTF-16LE, read per pitfalls.md §10) contains errors/warnings; a scripted loop is: compile → parse log → fix → recompile → run tester → parse report.
- The HTML report is parseable (deals table + summary stats); for machine-readable output prefer writing a CSV from OnTester/OnDeinit into `MQL5\Files` and reading that.
- Multiple configs = sequential runs; parallelism comes from optimization agents, not multiple terminals on one data folder.
