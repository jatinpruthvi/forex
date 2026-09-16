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
| All 11 pairs | +12.20% | +9.51% | −14.83% | 16.2% |
| **TRAIN-selected 8 (default)** | **+12.74%** | **+10.34%** | **−11.11%** | **11.3%** |

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
python3 validation/speed_lab/ea_emulator.py                # EA == backtest, on repo data
python3 validation/speed_lab/selftest_ea_dump.py           # tests the broker-dump chain (~3 min)
python3 validation/speed_lab/compare_ea_dump.py            # YOUR broker's dump (run it in MT5 first)
```

All of these are standard-library only, per the repo's no-dependency convention. numpy is used
only by the exploratory `sweep*.py` files and is not required for any shipped artifact.
`selftest_ea_dump.py` needs no MetaTrader — it synthesises a dump from the repo's own data — and
writes a ~70 MB `selftest_dump.csv` that is gitignored and safe to delete.

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

### The server clock — read this, it is the subtlest thing in the file

MQL5's `TimeCurrent()` returns **broker server time**, and bar times (`SERIES_LASTBAR_DATE`),
deal times (`DEAL_TIME`) and position times (`POSITION_TIME`) are all on that *same* clock.
So **no code in this EA converts time**. `InpExpectedServerUtcOffsetHours` is informational
only — it is never added to anything.

The backtest works the other way round: the repo's CSVs are **UTC** (verified — the market
closes Fri 20:55/21:55 UTC and reopens Sun 21:00/22:00 UTC, with zero Saturday bars), so it
*adds* +3 h to reach the server day. Both end up on the same server-day boundaries, which is
what `ea_emulator.py` now proves.

`CheckServerOffset()` measures the real offset at init (`TimeCurrent() - TimeGMT()`) and warns
if your broker is not UTC+3. The EA still keeps correct day boundaries either way, but a
different offset means the backtested daily-loss and qualifying-day windows are not directly
comparable — re-validate before prop use. Skipped in the Strategy Tester, where
`TimeGMT() == TimeCurrent()` by design.

**A side benefit:** because the EA follows the broker's clock natively, it stays correct if
your broker shifts UTC+2 ↔ UTC+3 seasonally. The backtest used a fixed +3 h for all four
years, so its server-day assignment is approximate during any UTC+2 period.

### 2. Static audit

Balanced braces/parens, 23 functions all defined, 37 inputs all declared and referenced, no
undeclared globals, no stray `};`, and every external call resolving to either an MQL5 builtin
or a documented `CTrade` method from `<Trade/Trade.mqh>`.

### 3. On your own broker — `EA_SIGNAL_DUMP.mq5`

Emulation proves the EA's *logic* matches the backtest, but it does so on the repo's CSV data.
It cannot tell you what your broker's feed does. `MQL5/Scripts/EA_SIGNAL_DUMP.mq5` closes that
gap: it is a **read-only script** (places no orders, modifies nothing) that dumps, for every M5
bar of *your* broker's history, exactly what the EA would compute — ATR, trigger, stop/target
geometry, lot size, server-day key and Friday flag.

It carries **verbatim copies** of the EA's `SimpleAtrBefore()`, `LossPerLot()`,
`NormaliseLots()` and `ServerDayKey()`. `selftest_ea_dump.py` mechanically diffs those copies
against the EA and fails on drift, so the script cannot silently diverge from what it claims to
verify.

It also dumps three deliberately **wrong** values next to the correct ones, so the bugs this EA
had are visible as data rather than as prose:

| Column | The bug it represents |
|---|---|
| `atr_wilder` | MT5's built-in `iATR()` (Wilder/RMA). Must differ from `atr_simple` on essentially every bar — measured ratio spans **0.51× to 4.41×** |
| `daykey_bug` | Server-day key with the UTC offset added to a value that is *already* server time |
| `friday_bug` | The same double-offset in the Friday test, which **inverted** the block: fired 18:00–20:59 and missed the 21:00–23:59 pre-close window |

Workflow:

```
MetaTrader  ->  run EA_SIGNAL_DUMP.mq5 (any chart)  ->  MQL5/Files/ea_signal_dump.csv
repo        ->  python3 validation/speed_lab/compare_ea_dump.py
```

`compare_ea_dump.py` has two independent layers, because your broker's bars are not the repo's:

* **Layer 1 — self-consistency.** Re-derives every column from the raw OHLC in the same row.
  Needs *no* overlap with the repo data at all, so it works on any dump, any broker, any period.
  Also confirms the three bug-evidence columns above are non-trivial and that no row sizes an
  oversized position.
* **Layer 2 — cross-feed.** Joins on the signal bar's UTC timestamp and compares against
  `verify_final_config.py`. It reports the OHLC agreement rate **first**, because that
  determines how to read the rest: where the bars are identical, ATR and every decision must
  match exactly, and any difference is an EA bug. Where the bars differ, the feeds differ and
  divergence is expected, not a failure.

It also prints your broker's `pip` / `tick_value` / `volume_step` next to the repo's
assumptions. A difference there is **not a bug** — it means realised lot sizes and P/L will
scale differently from the backtest, which is worth knowing before you size a position.

Two practical notes:

* Set `InpBarsToDump` large enough to overlap the repo data, which ends **2026-09-11**. The
  default 20000 M5 bars is only ~10 weeks; use **120000** for roughly a year. The comparator
  says so explicitly if it finds zero overlap rather than reporting a vacuous pass.
* Run it in a **live terminal**, not the Strategy Tester. In the tester `TimeGMT() ==
  TimeCurrent()` by design, so the real broker offset cannot be measured and the configured
  `InpServerUtcOffsetHours` is used instead.

`selftest_ea_dump.py` tests the whole chain without MetaTrader: it synthesises a dump from the
repo's own data in exactly the MQL5 output format, then requires Layers 1 and 2 to pass **and**
requires the comparator to *fail* on nine deliberately corrupted dumps (Wilder ATR swapped in,
trigger at 3× instead of 4×, 1× stop, wrong digit count, +9R target, doubled lots, guard
disabled, and both double-offset bugs restored). All nine are caught. A comparator that cannot
fail is worse than no comparator — that is precisely how the double-offset bug survived the
first audit.

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

Round 3 (found by re-reading against the MQL5 time semantics, then re-verifying):

| Bug | Impact |
|---|---|
| **The UTC offset was added to `TimeCurrent()`, which is *already* server time** | Every day boundary landed at 21:00 server instead of 00:00 — so the −3R breaker reset at the wrong hour and qualifying days were counted over 21:00→21:00 windows, which is not how the firm counts them. Worse, the Friday block was **exactly inverted**: shifting by +3 h made it fire on Fri 18:00–20:59 server and then *miss* Fri 21:00–23:59 entirely, because the shifted time rolls into Saturday (`day_of_week` 6). It blocked a harmless window and left the pre-close window — where a position gets carried into the weekend gap — wide open. Measured by mutation test: the buggy version disagrees with the backtest on **12.2% of server-day keys and 4.9% of Friday decisions** |
| **No minimum stop distance — a degenerate stop sized an enormous unprotected position** | `dist = (next_open − signal_low) + 2×ATR`, so a gap down through the signal bar's low shrinks it. In 4 years of data it reaches **exactly 0**, and since `lots = risk / (dist × pip_value + commission)`, `dist = 0` sizes to **1.78 lots on a $2,500 account with no stop protection at all**. 25 more signals have stops under 1×ATR (up to 1.16 lots on a 0.4-pip stop). They cluster at 20:55–22:00 — the daily roll and weekend close, where the next-bar open is a stale wide-spread print. Fixed with `InpMinStopAtrMultiple` (default 1.0) on **both** the EA and the backtest |
| Sizing used the raw stop while the order sent the normalised one | Dollars at risk differed slightly from `InpRiskPercent`. The stop is now normalised *before* sizing |
| Friday cutoff hour was hard-coded | Now `InpFridayCutoffHour` (default 21, matching the validation) |

**On the degenerate-stop guard, note the direction:** adding it *lowered* backtested expectancy
(TEST E_net +0.399R → **+0.376R**), because those trades were **winners** in the backtest — a
0.4-pip stop puts the +10R target only 4 pips away, so it hits often. They are still removed,
because the backtest assumes the stop executes exactly at its price, and **a 0.4-pip stop
cannot be executed**: one pip of slippage is a 3.5R loss. This is the same error class as the
close-bar-fill problem found in Phase 2 — a backtest flattering trades that cannot exist live.
Accepting a slightly lower number here is the honest choice.

### Still not verified — read before trusting it

**Compilation is unverified.** A static audit is not a compiler. **Your broker's feed is
unverified** — everything in this repo was validated on the repo's CSV data, not your broker's.
Before enabling anything:

1. Open in MetaEditor, press **F7**. Fix every warning, not just errors.
2. Run `MQL5/Scripts/EA_SIGNAL_DUMP.mq5` in a **live terminal** with `InpBarsToDump=120000`,
   then `python3 validation/speed_lab/compare_ea_dump.py`. **Layer 1 must PASS** — that is the
   EA's arithmetic checked against itself on your broker's own bars, and it needs no data
   overlap. Where Layer 2 finds identical OHLC, ATR and every decision must match exactly too.
   Read the broker contract-terms table: if `tick_value` differs from the repo's, your realised
   P/L per lot differs from every number quoted here.
3. Strategy Tester, M5, *"Every tick based on real ticks"*, 2024-09 → 2026-09, 0.50% risk,
   all 8 symbols available in Market Watch.
4. It must reproduce the validated shape: **median ≈ +10.3%/month, max DD ≈ 11%, roughly 32%
   losing months.** If it does not, something differs — most likely the ATR window, a symbol's
   tick value, or your broker's spread. Do not open any gate until it matches.
5. Then work through the gate checklist.

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
