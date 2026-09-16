# FIVE_M5_EXHAUST — M5 long-only extreme-bar exhaustion fade

Reference implementation of the frozen configuration validated in
[`findings_phase2_speed.md`](../../../findings_phase2_speed.md).

> **SHIPS DISABLED.** `InpEnableOrderSubmission` defaults to `false` and all eight gate
> flags default to `false`, following the convention set by `TRIAD_R_HS`. Until you set
> them, the EA logs signals and manages nothing. It has been validated on historical data
> only — **it has never been forward-tested or traded.**

> **INTENDED MARKET.** This EA is written for buyers resident **outside India**, where leveraged
> OTC forex is permitted. The author is resident in India and will not be running it on their own
> account there: FEMA 1999 restricts residents to RBI-authorised persons and recognised Indian
> exchanges, none of the eight instruments is available on them, the LRS cannot fund offshore
> margin trading, and the RBI Alert List (95 entities, 19 Nov 2025) names both the tightly-priced
> brokers below and MetaTrader 4/5 themselves. Anyone deploying this must confirm the position in
> **their own** jurisdiction, and note that §Broker requirements needs leverage ≥1:200, which
> tier-1 regulated entities often do not offer.

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

**Updated by measurement** — [`findings_broker_and_balance.md`](../../../findings_broker_and_balance.md)
§2(b) replays the actual TEST trade stream instead of assuming a position count. The 8-pair
stream reaches **9 concurrent positions** and 13 trades in a day at peak, and margin usage is
almost independent of balance because lots scale with it. Peak margin as a share of equity is
**~82% at 1:100, ~41% at 1:200, ~16% at 1:500, and ~274% at 1:30** — so at the EU/UK retail
leverage cap this configuration cannot be run as validated at any balance, and at 1:100 a
margin call arrives before the EA's own −3R daily breaker does. Leverage, not account size, is
the constraint.

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

## Broker requirements

Derived in [`findings_broker_and_balance.md`](../../../findings_broker_and_balance.md). These are
requirements of *this strategy*, not general advice — most come from where it trades and how wide
its stops are.

| Requirement | Why | What happens if not met |
|---|---|---|
| **Hedging** account mode | 13.8% of signals stack on a symbol already open, up to 3 deep | Netting merges them and overwrites SL/TP. The EA now skips instead, costing ~13% of signals: ~+10.4%/mo and 11.9% DD rather than +12.6% and 11.7% |
| **Raw / ECN** pricing, fixed commission | Raw beat a standard spread-marked account on 6 of 8 pairs, because wide stops make 1R large in dollars so a flat commission is a smaller slice of it than the spread | Higher cost per trade |
| **Tight spread at the rollover**, not in London | **43.8% of entries land in server 20:00–00:59 and 30.7% in the single hour UTC 21:00.** Published tests put EURUSD at 0.1 pips in London but 1.2 avg / 3.1 max across the rollover | Headline spreads describe the ~42% of trades that don't enter at the roll. At 8–12× rollover widening, expectancy falls from ~+0.64R to ~+0.15–0.43R |
| **Leverage ≥ 1:200**, ideally 1:500 | Peak margin is ~82% of equity at 1:100, ~41% at 1:200, ~16% at 1:500, ~274% at 1:30 | At 1:100 a margin call arrives before the EA's own −3R breaker. At the 1:30 EU/UK retail cap the configuration cannot be run at any balance |
| **Server time UTC+2/+3**, aligned to the NY 17:00 close | The validation assumed a fixed +3 h. `CheckServerOffset()` measures and warns | A UTC+0 server shifts every server-day boundary by 3 h, so the daily breaker, qualifying days and Friday cutoff no longer match the validated windows. Re-validate before use |
| **Market execution, no requotes, no news freeze, no minimum hold time** | Entries happen on a bar whose body exceeded 4×ATR — i.e. *during* a volatility spike, often at the roll | A broker-side news freeze or requote policy deletes the entry the strategy depends on |
| XAUUSD at 2 **or** 3 digits | Brokers differ; the repo data carries 3 | Handled — the EA reads `SYMBOL_DIGITS` and never infers it |
| Low **long** swap | Long-only, 0.772 nights per trade, 25.3% of trades cross ≥1 night | Swap is a persistent one-way drag the cost model does not charge; 0.10R/night costs ~1.3 points of monthly return |

### `InpCommissionPerLotRT` must be set to your broker's actual commission

This input is **not** cosmetic. It is added to the stop distance inside `LossPerLot()`, so it
divides every position size. Leaving it at the `7.0` default when the broker charges something
else moves realised risk away from the `0.50%` mandate:

| Broker / account | Round turn | Set `InpCommissionPerLotRT` to |
|---|---|---|
| FXCC ECN XL ("ZERO") | $0.00 | `0.0` |
| Tickmill Pro | $4.00 | `4.0` |
| Fusion Markets Zero | $4.50 | `4.5` |
| IC Markets Raw Spread | $7.00 | `7.0` (the default — this is what the backtest assumed) |
| Pepperstone Razor | $7.00 | `7.0` |

Setting it too **high** under-sizes: on a $0-commission broker the `7.0` default makes every
position 6.5–12.1% too small, so realised risk lands at **0.439–0.468% instead of 0.500%**.
Setting it too **low** over-sizes past the risk mandate, which is the dangerous direction — and a
negative value would understate the loss per lot badly enough to warrant the `[WARN]` the EA now
emits at init.

Note the strategic consequence, derived in §3 and §6 of the findings doc: **a fixed commission is
the part of your cost that cannot widen at the rollover**, and 43.8% of these entries land there.
That is why a $0-commission spread-only account (FXCC) looks best at peak hours and finishes worst
once rollover widening is priced, and why Fusion's $4.50 of fixed commission wins every scenario.

### Worked example — Fusion Markets Zero

Everything below is measured in `validation/speed_lab/fusion_markets_defaults.py`, on the held-out
TEST trade list, not read off the broker's site.

**Open the account as:** the **VFSC (Vanuatu) or FSA (Seychelles) entity**, **Zero** account,
**USD** base currency, **hedging** mode (Fusion supports it, so no signals are forgone), and
**not** the Islamic/swap-free variant. The ASIC retail entity caps leverage at 1:30, where this
stream's peak margin measures 260–275% of equity — the broker stops you out before the EA's own
−3R breaker ever acts. Classic instead of Zero roughly doubles the cost per round turn (~$9 vs
~$4.75). Swap-free trades a 1.4-pip spread markup for no swap, and the markup only pays if long
swap exceeds **~0.25R per night** — far above realistic levels on these pairs.

**Three inputs must change from their shipped defaults:**

| Input | Shipped | Set to | Why |
|---|---|---|---|
| `InpCommissionPerLotRT` | `7.0` | **`4.50`** | Fusion Zero is $2.25/side. This input is inside `LossPerLot()`, so leaving it at 7.0 **under-sizes 55.2% of trades** at $2,000 (mean position 0.158 vs 0.168 lots, −6.2%), costing **+14.33%/mo instead of +15.01%** with a slightly deeper drawdown (8.8% vs 8.3%) |
| `InpSymbols` | 8 pairs incl. `XAUUSD` | **drop `XAUUSD`** | Gold's held-out expectancy is negative (−0.219R) and it raises the lot-granularity floor 10× to $16,101 |
| `InpValidationReleaseId` | `"LOCKED"` | **`"M5_EXHAUST_2026_09"`** | `Authorised()` requires it to equal `InpRequiredReleaseId`. As shipped, **no order is ever submitted** |

Everything else stays at its default. In particular **leave `InpExpectedServerUtcOffsetHours` at
`3`** even though Fusion will spend about four months a year on GMT+2 — it is the validated
assumption, and the input is informational. Expect a `[WARN]` from roughly November to March; that
is the detector working, not a fault.

**What the seasonal clock actually costs.** Fusion's server is New York aligned and observes DST,
so it is GMT+3 in US summer and GMT+2 in winter. Measured across offsets +4…0 on the 7-pair TEST
stream: **expectancy is identical (+0.704R) at every offset**, because signals and exits are keyed
to UTC. Only the server-day grouping moves — monthly return stays within about a point
(+14.11% to +15.64%) and max drawdown between 6.7% and 10.8%.

The one figure that moves materially is the **rollover count: 890 nights at GMT+3 versus 1,141 at
GMT+2, +28.2%.** The reason is subtle and worth knowing: 30.7% of entries occur at UTC 21:00, and
with a +3 server the day boundary sits exactly on that hour, so those trades begin a fresh server
day and cross no rollover at all. Move the boundary an hour later and they cross one. **The
validated +3 assumption is therefore flattering on swap**, and Fusion is on the unflattering clock
for part of the year. That makes reading Fusion's actual long-swap table for all seven symbols —
the `InpSwapCostGatePassed` condition — more important than usual, not less.

**Two practical notes.** Fusion's free VPS requires 20 lots/month; at $2,000 this strategy trades
roughly 2–3 lots/month, so **budget for a paid VPS** — the EA must run 24/5 or the 96 h timeout and
the daily breaker both stop working. And Fusion does not accept US residents, which matters if the
EA is sold abroad.

**Balance: $2,000** on the seven FX pairs at 1:500 — see
[`findings_broker_and_balance.md`](../../../findings_broker_and_balance.md) §5. Peak margin is ~16%
of equity, so margin is not the constraint; lot granularity is.

Before funding, verify on the **account type you will actually use**: hedging vs netting, the
symbol names (the EA resolves suffixes, but confirm the `[INIT]` lines), the measured server
offset, the commission actually charged, and the leverage offered by the entity you register under
— these differ between a broker's ASIC, FCA, CySEC and offshore entities.

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
python3 validation/speed_lab/broker_cost_and_balance.py    # spread budget + min balance (~14 s)
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

Round 4 (found while answering "which broker, and what minimum balance"):

| Bug | Impact |
|---|---|
| **Netting accounts were never detected** | On `ACCOUNT_MARGIN_MODE_RETAIL_NETTING` a second `Buy()` on a symbol does **not** open a second position — it merges into the open one at a volume-weighted average price and **overwrites its SL and TP**. The first trade's 2×ATR stop and +10R target would be silently destroyed and replaced by the second trade's levels, and the merged volume would carry risk as though each leg had been sized independently. **13.8% of TEST signals (165 of 1,198) enter while the same symbol is already open, and up to 3 stack on one symbol**, so this is not a corner case — and the entire validation assumes independent positions, i.e. hedging behaviour. Now detected in `OnInit`, with a per-symbol skip via `PositionOpenOn()`. A netting account forgoes ~13% of signals and lands at roughly **+10.4%/month with an 11.9% max drawdown instead of +12.6% and 11.7%**; use a hedging account to get the validated figures |
| **Broker symbol suffixes silently shrank the universe** | `InpSymbols` holds canonical names, but brokers call the same instrument `EURGBP.m`, `EURGBPm`, `EURGBP.pro`, `EURGBP-ECN` or `EURGBP.micro` depending on firm *and account type*. `SymbolSelect()` fails, one warning scrolls past, and the EA then trades a subset — or nothing — while looking healthy. Added `ResolveSymbol()`/`SuffixPlausible()`, which accepts punctuation-delimited suffixes at any length and alphanumeric ones only when short and lower-case, so `USD` can never resolve onto `USDCAD`. Unresolvable symbols now log an `[ERROR]`, are blanked so they cannot reach `EvaluateSymbol`, and if *none* resolve the EA halts; a partial resolution warns that results will not match the published figures. Tested by `test_ea_symbol_resolution.py` (transliterated logic + mutation control) |
| `ProcessOnce()` ran a full deal-history scan on **every tick** | `RecomputeDayState()` does `HistorySelect()` plus a loop over every deal in the server day. `OnTick` can fire hundreds of times a second on an active symbol and `OnTimer` adds one more, so that is hundreds of full history scans a second — enough to starve the bar-open evaluation the `InpMaxEntryLagSeconds` guard depends on. `TimeCurrent()` has one-second granularity, so gating on it throttles to one scan per second, and a dirty flag set on every fill forces an immediate rescan so the −3R breaker never lags |
| "Gates not satisfied" never said *which* gate | Useless to whoever is deploying it — and a buyer on a non-USD account would see only "DISABLED", with no hint that `InpExpectedAccountCurrency` was the blocker. Added `FirstClosedGate()`, reported both at init and on every dry-run signal |

Checked and **cleared** in the same round (no change needed): the 96 h timeout is a wall-clock
test in the EA but a 1,152-*bar* count in the backtest, which diverge across weekends — measured
on TEST, only **10 of 1,198 trades** close a different bar and the worst gap is **6 minutes**.

Round 5 (found while checking FXCC and myfxbook as the candidate broker):

| Bug | Impact |
|---|---|
| **The volume sent to the broker carried a 1-ULP float residue** | `NormaliseLots()` ended with `MathFloor(lots/step)*step` and returned it directly. `0.01` has no exact binary64 representation, so `n*step` is frequently not the number it prints as — 35 steps is `0.35000000000000003`. A broker that validates volume against `SYMBOL_VOLUME_STEP` by exact comparison rejects that with `TRADE_RETCODE_INVALID_VOLUME` (10014) or `INVALID_VOLUME_STEP`. Measured on the real validated trade list, the share of sized volumes affected is **3 of 1,111 at $1,565, 15 at $2,000, and 25 at $2,500 (2.3%)** — about one live signal in 43 at the reference balance. **No backtest can catch this**, because no backtest round-trips a volume through a broker's server. Prices were already normalised; the volume was the one thing that wasn't. Now rounded to the step's own decimal count, with a guard so the clean-up can never authorise *more* volume than the floor did. The decimal count is derived by scaling, **not** `-log10(step)` — log10 gives `0.25` one decimal, which would round `0.25` **up** to `0.3`, a 20% over-size |
| **`CheckServerOffset()` mis-reported every server west of UTC by one hour** | `(double)((detected+1800)/3600)` looks like round-to-nearest, but both operands are integers so MQL5 performs **integer division, which truncates toward zero**. Adding 1800 before a truncation rounds correctly for positive values and wrongly for negative ones: UTC−1 reported as 0, −2 as −1, −5 as −4. Order flow was never corrupted (`ServerDayKey` uses `TimeCurrent` directly), but the *diagnostic* was — it could raise a bogus WARN against a correct offset or stay silent against a real one, and a silent offset mismatch is exactly how a session filter drifts with no visible symptom. Invisible on the GMT+2/+3 MT5 servers everyone tests on, which is why four earlier rounds missed it. Now `MathFloor(((double)detected+1800.0)/3600.0)` |
| **Suspected — and refuted: do not "fix" the lot floor with a tolerance** | `MathFloor(raw/step)` can drop a whole step when the quotient lands a ULP below an integer, and the obvious remedy is `MathFloor(q+1e-9)`. Measured against exact rational arithmetic across all 3,290 trades × 3 balances, the shipped plain floor disagrees with true intent **zero** times, while that tolerance **over-sizes 7 trades at $2,000 and 2 at $2,500**. The reason: `stop_pips` derives from price differences, so `loss_per_lot` is not a round number even when it prints like one (11.80 pips on AUDUSD gives `125.00000000000699`, not `125`). A quotient of `9.99999999999944` is therefore **not** float noise around 10 — it faithfully reports a stop a whisker wider than the round number, so 9 steps *is* the authorised size. Recording this so it is not "fixed" later: the tolerance is the bug |

Also hardened in round 5: `InpCommissionPerLotRT` sits *inside* `LossPerLot()` and therefore sizes
every position, but nothing surfaced it — see the table below for why that matters when you change
broker. The EA now prints it in its first `[INIT]` line beside the sizing base, and warns if it is
negative. Tests: `test_ea_lot_normalisation.py` and `test_ea_server_offset.py`, both with mutation
control (3 and 4 mutants caught respectively).

Round 6 (found while setting the defaults for a specific broker, Fusion Markets Zero):

| Bug | Impact |
|---|---|
| **`FillingModeFor()` preferred FOK over IOC — and nothing retried a rejection** | The function tested `SYMBOL_FILLING_FOK` first, the pattern copied around MQL5 forums. That is wrong twice over here. **(1) Rejection:** `TRADE_RETCODE_INVALID_FILL` (10030, "unsupported filling type") is almost always a FOK request to a market-execution server. `SYMBOL_FILLING_MODE` describes the *symbol*; the account's execution mode can be stricter, so the advertised bitmask is not a guarantee — Fusion is NDD/market execution, where IOC is the norm. The EA logged the error and **lost the signal**. **(2) Economics:** FOK fills the whole volume at once or dies. This EA enters on a bar whose body exceeded 4×ATR — during a volatility spike — and 43.8% of entries land in the rollover, where depth is thinnest. FOK converts thin depth into a lost trade, diverging from a backtest that assumes every signal fills. IOC takes what is available and cancels the rest, so a partial fill is *smaller than sized* and under-risks — the safe direction, and `DONE_PARTIAL` is now reported with a `[WARN]`. IOC is now preferred, and any 10030 steps down the list (IOC → FOK → RETURN) instead of giving up |
| **`Authorised()` gated the *close* path, so a halt could announce a flatten it never performed** | Both `ManageTimeouts()` and `FlattenOwnPositions()` did `Print("[TIMEOUT]…"/"[FLATTEN]…")` and then `if(Authorised()) trade.PositionClose(tk)`. The gate exists to stop the EA *taking* new risk; blocking a close is backwards, because closing **reduces** risk. Reachable the obvious way: an operator sets `InpEnableOrderSubmission=false` to "pause" the EA, which forces a reinit, and from then on the 96 h timeout stops firing and `Halt()` latches `g_halted` while flattening nothing — positions left permanently unmanaged, with a log that says they were closed. They kept their broker SL/TP, so they were not naked, but a silently-failing halt is exactly what this EA's gate convention exists to prevent. Closes now go through `CloseOwnPosition()`, which is **never** gated, reports a failed close as an `[ERROR]` demanding manual intervention, and `FlattenOwnPositions()` prints the true tally — `N closed, M FAILED` — rather than implying success. Dry-run from a clean start is unaffected: nothing was opened, so there is nothing to close |

Checked and **cleared** in round 6 (no change needed): the filling mode *is* re-resolved per symbol
immediately before each `Buy()` (the `OnInit` call from `_Symbol` is only an initial default, so a
chart symbol differing from the traded symbols is not a problem); `RecomputeDayState()` includes
`DEAL_SWAP` **and** `DEAL_COMMISSION` in realised R, so the −3R breaker sees true net R; the
`ProcessOnce()` throttle gates only the history rescan, not `ManageTimeouts()`, so a frozen
`TimeCurrent()` over a weekend cannot starve the 96 h timeout; and the broker minimum stop distance
is checked for **both** the stop and the target before entry.

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
