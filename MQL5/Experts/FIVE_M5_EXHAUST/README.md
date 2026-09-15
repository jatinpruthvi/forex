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

## Known limits of this implementation

- Single-symbol chart attachment is not required; the EA iterates its symbol list from
  `OnTick` on whatever chart it is attached to.
- `ScanClosedDeals()` attributes realised P&L to the current server day for the −3R breaker.
  After a restart mid-day the breaker resets — acceptable, but it is a reset, not a restore.
- The 96 h timeout is enforced by polling in `ManageTimeouts()`; the EA must stay online.
- No news filter. None was validated; adding one is untested upside, not a known improvement.
- Lot size is floored to the broker's volume step, so on a very small account the realised
  risk per trade is *lower* than `InpRiskPercent` — the backtest models the same floor.
