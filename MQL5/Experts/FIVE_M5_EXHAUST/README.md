# FIVE_M5_EXHAUST — M5 long-only extreme-bar exhaustion fade

Reference implementation of the frozen configuration validated in
[`findings_phase2_speed.md`](../../../findings_phase2_speed.md).

> **SHIPS DISABLED.** `InpEnableOrderSubmission` defaults to `false` and all eight gate
> flags default to `false`, following the convention set by `TRIAD_R_HS`. Until you set
> them, the EA logs signals and manages nothing. It has been validated on historical data
> only — **it has never been forward-tested or traded.**

## The rule (frozen — do not retune)

On each newly opened M5 bar, look at the bar that just closed:

1. Compute `ATR` = **simple mean of true range over the 14 bars strictly before it**.
2. Trigger if `|close − open| > 4.0 × ATR`.
3. **Long only** — act only if `close < open` (fade sharp sell-offs).
4. Enter at market on the open of the new bar.
5. Stop = signal bar's `low − 2.0 × ATR`. Reject if the fill is already at/beyond the stop.
6. Target = `entry + 10.0 × (entry − stop)`.
7. Close at market after 96 hours if neither level was hit.

**Do not replace the hand-rolled ATR with `iATR()`.** MT5's built-in ATR uses Wilder/RMA
smoothing; the backtest used a simple mean. Swapping it changes every signal and invalidates
all validated numbers.

The window is the 14 bars **strictly before** the signal bar (live: shifts 2-15), and each
true range needs the close *preceding* its own bar - so the oldest term reads shift 16.
Getting that index wrong understates one of the 14 terms to a bare high-low range; measured
against the backtest it flips **8 trigger decisions in 124,000 bars (0.006%)**. Negligible in
practice, but it was fixed so the EA reproduces the validated numbers exactly.

## Universe

Default: the **8 pairs selected on TRAIN only** (`EURGBP, AUDUSD, NZDUSD, USDCAD, USDCHF,
EURJPY, GBPJPY, XAUUSD`). Held-out TEST, personal-account sizing, every signal taken:

| Universe | Mean /mo | **Median /mo** | Worst mo | Max DD |
|---|---|---|---|---|
| All 11 pairs | +13.05% | +9.51% | −14.83% | 16.2% |
| **TRAIN-selected 8 (default)** | **+13.63%** | **+10.87%** | **−11.11%** | **10.9%** |

The 8-pair set is better out-of-sample on *every* metric — higher mean, higher median,
smaller worst month, and a third less drawdown — and it drops the two worst swap-paying
lines (EURUSD, GBPUSD). `InpUseAllEleven=true` reverts to all 11.

Prop-challenge settings are in Part A of the findings file (0.50% risk → 77.5% pass / median
27 days; 0.75% → 75% / 17 days; **never above 0.75%**, which breaches the $125 daily-loss rule).
Set `InpProfitTarget=2750`, `InpEquityFloor=2250`, `InpDailyLossLimitPct=5`,
`InpQualifyingDays=3`, `InpSizingBaseOverride=2500` and cap `InpMaxConcurrent=2`,
`InpMaxTradesPerDay=5` for that mode.

## Margin — read this before enabling

Worst case, all positions open at once at 0.50% risk on a $2,500 account
(1.46 lots total, ~$158k notional):

| Leverage | Margin required | % of equity | Verdict |
|---|---|---|---|
| 1:30 | $5,262 | 210% | **IMPOSSIBLE** — margin call |
| 1:50 | $3,157 | 126% | **IMPOSSIBLE** — margin call |
| 1:100 | $1,579 | 63% | tight |
| 1:200 | $789 | 32% | feasible |
| 1:500 | $316 | 13% | feasible |

Realised concurrency in the 4-year backtest is much lower — **mean 3.11 positions**,
≤4 open 77% of the time, **max 14** (positions held up to 233 h overlap later signals).
The EA refuses an entry when required margin exceeds 90% of free margin, but on 1:30 or 1:50
leverage it will skip most signals and you will not reproduce the validated numbers.
**You need 1:100 or better; 1:200 is comfortable.**

## Swap — the largest unquantified cost

The backtest charges spread and commission but **not overnight swap**. Mean exposure is
**0.771 rollovers per trade**; 25.4% of trades cross ≥1 night, 15.8% cross ≥2.

| Swap (R / rollover) | E_net per trade | Mean /mo @0.50% |
|---|---|---|
| 0.00 (as backtested) | +0.377R | +7.79% |
| 0.10 | +0.300R | +6.51% |
| 0.20 | +0.223R | +5.26% |

The direction is **not uniformly negative** and the default universe is favourable: the pairs
carrying 85% of the profit (EURGBP, USDCHF, NZDUSD, GBPJPY) mostly **earned** carry over
2022–2026, while the two clear swap *payers* (EURUSD, GBPUSD) are exactly the pairs the
TRAIN selection drops. Realistic drag is likely small — but **pull your broker's swap table
for all 8 symbols and set `InpSwapCostGatePassed` only after you have.** The JPY crosses'
carry tailwind compressed sharply after 2024 as the BoJ hiked, so do not assume the past
benefit repeats.

## Gate checklist

Set each flag to `true` only when the condition is genuinely met:

| Input | Condition |
|---|---|
| `InpBacktestGatePassed` | You have read Parts A and B of `findings_phase2_speed.md`, including §5 caveats |
| `InpOutOfSampleGatePassed` | You understand the headline came from a window never used for selection, and that 2 implementations disagreed in the tail (77.5% vs 92.5% pass) |
| `InpSwapCostGatePassed` | Broker swap table checked for every configured symbol |
| `InpMarginGatePassed` | Leverage is 1:100 or better; worst-case margin fits |
| `InpForwardDemoGatePassed` | Demo run through **at least one full losing streak** — 32% of months lose money, worst observed month −14.8%, longest losing streak 3 months |
| `InpExplicitUserApproval` | You accept a 16–23% peak-relative drawdown with no external floor to stop you |
| `InpValidationReleaseId` | Must equal `InpRequiredReleaseId` |
| `InpEnableOrderSubmission` | Set **last** |

## Reproducing the validation

```
python3 validation/speed_lab/verify_final_config.py        # Part A: prop challenge  (~8 s)
python3 validation/speed_lab/personal_account_analysis.py  # Part B: personal account (~9 s)
python3 validation/speed_lab/margin_and_swap_exposure.py   # Part C: margin + swap map
```

All three are standard-library only, per the repo's no-dependency convention. numpy is used
only by the exploratory `sweep*.py` files and is not required for any shipped artifact.

## Verification — what was actually checked

This EA cannot be compiled here (no MetaEditor in the validation environment), so it was
verified two ways instead.

### 1. Logic equivalence, proven by emulation

`validation/speed_lab/ea_emulator.py` re-implements the EA's decision path **independently** —
transcribed from the `.mq5` line by line, in the EA's own order — and compares it against
`verify_final_config.py`, which produced the validated numbers. It parses the EA's inputs
straight out of the source file, so the test cannot silently drift from the EA.

| Check | Result |
|---|---|
| ATR window (`SimpleAtrBefore` vs `atr_prior`) | **IDENTICAL** — 477,430 bars compared, 0 mismatches, max relative difference 0.000e+00 |
| Signals + geometry (trigger, long-only filter, stop, target, broken-geometry rejection) | **IDENTICAL** — 3,317 vs 3,317 trades, all 11 pairs matching exactly, stop distances differing by 0.0 |
| Gate semantics (server-day key, Friday 21:00 block) | **IDENTICAL** — 15,643 timestamps, 0 mismatches |
| Ships disabled | **PASS** — master switch and all six sign-off gates default to `false` |

So the EA trades *the same strategy that was validated*. It also confirms the MQL5↔Python
day-of-week mapping is right (MQL5 `day_of_week==5` and Python `weekday()==4` are both Friday).

Re-run it any time with `python3 validation/speed_lab/ea_emulator.py` (~30 s).

### 2. Static audit

Balanced braces/parens, 23 functions all defined, 37 inputs all declared and referenced, no
undeclared globals, no stray `};`, and every external call resolving to either an MQL5 builtin
or a documented `CTrade` method from `<Trade/Trade.mqh>`.

### Bugs this process found and fixed

Round 1 (static audit):

| Bug | Impact |
|---|---|
| `SimpleAtrBefore()` read the prior close for the oldest window bar from `shift+need`, which *is* that bar | Its true range degenerated to a bare high-low range. Flipped **8 trigger decisions in 124k bars (0.006%)** — small, but it broke exact reproduction. Fixed to `shift+need+1`; bar-count guard was also off by one |
| Called `trade.SetTypeFillingBySymbol()`, which does not exist in `CTrade` | **Would not have compiled.** Replaced with a per-symbol mode from `SYMBOL_FILLING_MODE` |
| No broker `SYMBOL_TRADE_STOPS_LEVEL` check | Orders would be rejected. Now skips rather than widening the stop (widening would change risk per trade) |
| `Halt()` left positions open | Now flattens its own positions via `InpCloseAllOnHalt` |
| Mid-day restart reset the −3R breaker | Now rebuilt from deal history |

Round 2 (found while writing the emulator):

| Bug | Impact |
|---|---|
| **`ScanClosedDeals()` used a 1-second-granularity watermark and *added* deals to a running total** | Many ticks share one second, so the same closed deals were re-selected and re-added **on every tick**. `g_day_net_r` inflated until the −3R breaker tripped spuriously and **locked out all trading**. Also mis-attributed deals closed across midnight to the wrong day. Replaced with an idempotent `RecomputeDayState()` that recounts from the server-day window |
| **`OnTick()` only fires for the chart symbol** | With 8–11 symbols watched from one chart, a pair whose bar opened while the chart symbol was quiet would be evaluated late or never — breaking the next-bar-open fill the validation depends on. Added a 1-second `EventSetTimer` driving the same `ProcessOnce()` |
| Bar was marked processed *before* `CopyRates`/ATR succeeded | One failed history sync permanently discarded that bar's signal. Now committed only after the data is in hand, and retried otherwise |
| No entry-freshness guard | The EA could enter minutes after the bar opened, so the trade would not match the backtested fill distribution. Added `InpMaxEntryLagSeconds` (default 30 s) |
| Prop-mode target was not latched, and ignored `InpQualifyingDays` | `g_day_locked` clears at every server midnight, so the EA would resume trading the next day on an already-passed account; and it flattened before the qualifying days were earned, which would forfeit them. Now latched in `g_target_reached` and gated on both conditions |
| `g_day_trades` had two sources of truth and could regress | A fill increments it, then the history recount could overwrite it with a *lower* number before the deal synced, letting `InpMaxTradesPerDay` be exceeded. Now takes the max within a server day |
| Transient tick-value / margin-calc failures called `Halt()` | A momentary glitch would flatten the whole book and disable the EA until restart. Now they skip the entry and log |
| `day_key*86400` computed in `int` | ~1.73e9, overflowing int32 in 2038. Now cast to `long` |
| `SizingBase()` honoured `InpSizingBaseOverride` even in compounding mode | Silently disabled compounding. Now applies only in fixed-fractional mode |
| `Buy()`'s boolean return was trusted alone | It can be true for a request merely accepted. Now confirms `TRADE_RETCODE_DONE`/`DONE_PARTIAL`/`PLACED` |

### Still not verified — read before trusting it

**Compilation is unverified.** A static audit is not a compiler. Before enabling anything:

1. Open in MetaEditor, press **F7**. Fix every warning, not just errors.
2. Strategy Tester, M5, *"Every tick based on real ticks"*, 2024-09 → 2026-09, 0.50% risk,
   all 8 symbols available in Market Watch.
3. It must reproduce the validated shape: **median ≈ +10.9%/month, max DD ≈ 11%, roughly 32%
   losing months.** If it does not, something differs — most likely the ATR window, a symbol's
   tick value, or your broker's spread. Do not open any gate until it matches.
4. Then work through the gate checklist.

Two intentional differences from the backtest, neither a bug:

- **Exits.** The EA sets real SL/TP and the broker resolves them tick-by-tick; the backtest
  resolves on bar OHLC and books the *stop* when a bar spans both levels. Live results should
  therefore be slightly **better** than backtested, not worse.
- **Entry price.** The EA fills at `tick.ask`; the backtest uses the next bar's open.
  `InpMaxEntryLagSeconds` exists to keep these close. Note the EA sizes from the *actual*
  ask-based stop distance, so dollar risk stays at `InpRiskPercent` regardless of spread.
## Execution guards

The EA refuses an entry rather than distorting the risk model the validation assumed:

| Guard | Behaviour |
|---|---|
| **Entry freshness** | Skips if the bar opened more than `InpMaxEntryLagSeconds` (default 30 s) ago — a late fill would not match the backtested next-bar-open distribution |
| Broker **stops level** | Skips if `entry - SL` or `TP - entry` is inside `SYMBOL_TRADE_STOPS_LEVEL`. It does **not** widen the stop, because widening changes risk per trade |
| **Margin** | Skips if required margin exceeds 90% of free margin |
| **Broken geometry** | Skips if the fill is already at/beyond the intended stop |
| **Lot floor** | Skips if the computed size rounds below `SYMBOL_VOLUME_MIN` |
| **Tradability** | Skips unless `SYMBOL_TRADE_MODE` is full/long-only and algo trading is permitted at EA, account and terminal level |
| **Filling mode** | Chosen per symbol from `SYMBOL_FILLING_MODE` (FOK, else IOC, else RETURN) |
| **Retcode** | Confirms `TRADE_RETCODE_DONE`/`DONE_PARTIAL`/`PLACED`; a `Buy()` that merely returned true is not counted as a fill |

Transient failures (unavailable tick value, failed `OrderCalcMargin`) **skip the entry and
log** — they do not halt. `Halt()` is reserved for rule breaches, and flattens the EA's own
positions when `InpCloseAllOnHalt=true` (default) so a halt never leaves orphaned risk.

`RecomputeDayState()` recounts today's realised R and trade count from deal history on every
pass. It is idempotent by design, and the trade counter takes the max of the history count and
the in-session count so it can never regress within a server day.

## Known limits of this implementation

- **Attach to any one chart.** The EA iterates its symbol list from `ProcessOnce()`, driven by
  both `OnTick` and a 1-second `OnTimer`. The timer matters: `OnTick` alone fires only for the
  chart symbol, so without it a quiet pair's signals would be evaluated late or never.
- **Strategy Tester caveat.** In the tester, `OnTimer` runs on simulated time and multi-symbol
  data must be present in Market Watch. Test with *"Every tick based on real ticks"* and all 8
  symbols downloaded, or the tester will not reproduce the validated distribution.
- `RecomputeDayState()` rebuilds realised R and the trade count from deal history, so the −3R
  breaker survives a restart. But `g_day_start_equity` is set to the equity *at init*, not the
  true start-of-server-day equity, so after a mid-day restart the prop-mode
  `InpDailyLossLimitPct` baseline is wrong until the next server midnight. **For prop-challenge
  use, avoid restarting mid-day.**
- The 96 h timeout is enforced by polling in `ManageTimeouts()`; the EA must stay online. SL/TP
  are real broker-side orders, so those protect the position even if the EA disconnects.
- No news filter. None was validated; adding one is untested upside, not a known improvement.
- Lot size is floored to the broker's volume step, so on a very small account the realised risk
  per trade is *lower* than `InpRiskPercent`. The backtest models the same floor.
- `g_qualifying_days` is tracked and displayed but only consulted before standing down at the
  prop target. The EA does not itself verify that the firm has credited those days — check the
  firm's dashboard, not this counter.
