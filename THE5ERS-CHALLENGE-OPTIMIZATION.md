# Optimizing TRIAD-R to Pass the $2,500 The5ers Challenge

Optimization review date: 2026-09-03

## Executive conclusion

The challenge profile has now been consolidated into `THE5ERS-CHALLENGE-STRATEGY-V2.md`, the canonical improved build-and-validation specification. It is **simpler and more pass-oriented**, but it cannot yet be called statistically optimized. The repository has no reproducible tick backtest, fill history, trade-day series, or MT5 symbol export. Therefore, changing thresholds now based on intuition would be curve-fitting without data.

The correct objective is not maximum monthly return or fastest completion. It is:

> Maximize the probability of completing Phase 1 and Phase 2, including three qualifying days in each phase, before the personal 5% strategy shutdown, with zero rule violations.

The current **0.40% risk ceiling and +1.5R fixed-target baseline should remain test candidates, not unquestioned constants**. Lower risk generally improves survival because evaluation time is unlimited, but the $2,500 account's 0.01-lot step and $12.50 profitable-day threshold mean that risk and exits must be optimized using actual MT5 cash outcomes—not percentages alone.

---

## 1. What should be optimized first

### Priority 1: eliminate non-market failure

A strategy with positive expectancy can still fail through a rule or implementation error. Before tuning entries:

- One working pending entry or one open position account-wide.
- No account copier or coordinated execution.
- Broker-visible stop attached with the entry.
- Confirmed server-rollover state machine.
- Thirty-minute relevant-news gate with pending-order cancellation and retry suppression.
- Persisted account/phase/initial-balance identity.
- Exact 0.01-lot rounding down.
- Rate-limited order requests and restart reconciliation.
- Fail closed when calendar, quote, account identity, or state is uncertain.

These changes improve challenge survival without requiring a stronger trading edge.

### Priority 2: optimize the complete challenge outcome

Do not choose a variant using win rate, profit factor, monthly return, or Phase 1 speed alone. Replay the complete account path and measure:

1. Phase 1 pass probability before 5% strategy drawdown.
2. Probability that three qualifying days are already present when the 10% target is reached.
3. Phase 2 pass probability and three-day completion on a fresh $2,500 phase account.
4. Joint probability of passing both phases.
5. Median and 90th-percentile calendar duration.
6. 95th-percentile maximum drawdown.
7. Longest calendar gap between valid trades for the 30-day inactivity risk.
8. Frequency of minimum-lot skips and winner amounts below $12.50.
9. Rule-engine and server-request errors; acceptable count is zero.

### Priority 3: improve net expectancy before increasing risk

The best improvements are likely to come from rejecting poor trades:

- Compare each instrument/session independently after costs.
- Retain only combinations with positive out-of-sample expectancy and stable results across years/regimes.
- Select only one when EURUSD and GBPUSD signal together.
- Keep XAUUSD and indices disabled until minimum-lot and stressed-execution tests pass.
- Treat accepted breakouts as no-trades; continuation remains shadow-only.
- Keep spread, cost, news, stale-data, stop-geometry, and one-position checks as mandatory gates.

A quality score may rank two otherwise valid candidates. It must not rescue a failed hard gate or increase risk until score buckets demonstrate monotonic out-of-sample expectancy.

---

## 2. Small-account optimization problem

### Nominal risk is not actual cash risk

At a 0.40% ceiling, the maximum planned loss is $10. The rounded position may risk materially less:

- A raw 0.066 lot becomes 0.06 lot.
- A raw 0.025 lot becomes 0.02 lot.
- Commission, tick value, conversion, and stop distance alter both stop and target cash values.

Consequently, `0.40% × 1.5R = 0.60%` does **not** prove every full winner will add at least $12.50 after volume rounding and costs.

The simulator must use:

- Historical entry, stop, and target prices.
- MT5-equivalent `OrderCalcProfit` economics.
- Volume minimum and step.
- Commission, spread, swap if applicable, and slippage.
- Realized day grouping using server rollover.
- The exact profitable-day formula.

### Exit models to compare

Test these as mutually exclusive complete models:

| Model | Exit | Reason to test |
|---|---|---|
| A | One fixed +1.5R target | Simplest baseline; fewest server actions |
| B | One fixed +1.75R target | May allow more rounded-down winners to exceed $12.50, but likely lowers hit rate |
| C | One fixed +2.0R target | Lower-risk settings can still create qualifying days, but holding time and win rate may deteriorate |
| D | One fixed +2.5R target | Paired only with the 0.25% profile; likely safest cash risk but most demanding target |

Partial closing was considered and then removed from V2.1. The initial implementation uses one entry, one position, and one final close, eliminating the remaining partial-close interpretation and extra server actions.

Do not select the target that creates the most qualifying days in-sample. Select a broad, stable fixed-target region that maximizes joint out-of-sample pass probability after all costs.

### Time-stop models to compare

Replay 30, 45, 60, and 90 minutes, plus session-only exit. Use the first stable plateau, not the single best backtest point. If 45 minutes wins only at exactly 45, it is overfit.

---

## 3. Risk optimization

Risk does not create edge. Choose it only after producing a fixed out-of-sample trade/day sequence.

V2.1 tests risk and target as paired profiles:

- 0.40% with +1.50R
- 0.35% with +1.75R
- 0.30% with +2.00R
- 0.25% with +2.50R

Do not test above 0.40% for the first challenge. For each profile, apply exact volume rounding and the same single predeclared drawdown reduction. Profit-level-based target throttles are no longer used.

### Illustrative sensitivity—not a forecast

A simple 30,000-path IID experiment was run only to illustrate the risk trade-off. Assumptions were a +1.5R winner, -1R loser, fixed risk, +10% target, 5% trailing personal shutdown, at most 2,000 trades, no target throttle, no daily grouping, and no profitable-day condition.

| Net win probability | Net EV | Risk | Simulated pass before 5% shutdown | Median trades among passes |
|---:|---:|---:|---:|---:|
| 45% | 0.125R | 0.25% | 79.8% | 247 |
| 45% | 0.125R | 0.35% | 65.9% | 151 |
| 45% | 0.125R | 0.40% | 59.9% | 121 |
| 48% | 0.200R | 0.25% | 95.6% | 180 |
| 48% | 0.200R | 0.35% | 87.0% | 121 |
| 48% | 0.200R | 0.40% | 81.8% | 101 |
| 50% | 0.250R | 0.25% | 98.6% | 149 |
| 50% | 0.250R | 0.35% | 93.5% | 102 |
| 50% | 0.250R | 0.40% | 90.7% | 87 |

Seed: 20260903. These figures are not strategy evidence. IID outcomes understate changing regimes, clustered losses, execution errors, and autocorrelation. The lesson is only that **lower risk can materially increase pass probability when time is unlimited**, while edge quality matters more than speed.

### Conditional two-phase estimate at the 0.40% baseline

A separate 100,000-path run used the same simplified fixed-risk assumptions and simulated the +10% and +5% phases independently. Joint probability is the product of the two simulated phase rates:

| Net win rate | Net EV | Phase 1 | Phase 2 | Simplified joint pass probability |
|---:|---:|---:|---:|---:|
| 42% | 0.050R | 31.0% | 56.1% | 17.4% |
| 45% | 0.125R | 59.7% | 78.3% | 46.7% |
| 48% | 0.200R | 81.8% | 90.9% | 74.4% |
| 50% | 0.250R | 90.4% | 95.4% | 86.3% |
| 52% | 0.300R | 95.1% | 97.6% | 92.8% |

This table shows why no unconditional percentage is honest. If the challenge profile really delivers the proposed 0.20-0.25R net expectancy, the simplified mathematical range is approximately 74-86%. If it delivers only 0.125R, the same risk plan falls to about 47%. The model omits lot granularity, non-qualifying winners, costs beyond the assumed net outcome, loss clustering, missed trades, changing regimes, operational failures, and the exact throttles. It therefore must not be presented as a real-world forecast.

The real block-bootstrap result must decide between 0.25-0.40%. The selected risk must also produce three qualifying days with high probability under actual lot rounding. This is why 0.25% cannot automatically replace 0.40% despite its better toy survival result.

---

## 4. Optimized daily process

Use one policy throughout both phases and the initial funded period; do not switch behavior merely because the profitable-day counter changes.

1. Take the first fully valid setup at the configured risk tier.
2. If it reaches its full normal target, end trading for the day under the standing daily profit governor.
3. If it loses, allow one further independent setup only if every gate passes.
4. After two full losses, stop for the day.
5. Never take a third trade, recovery trade, larger trade, forced opposite trade, or maintenance trade.
6. Stay flat through server rollover.
7. Calculate the day's qualifying status with the official formula and reconcile it against the dashboard.

A first-trade full winner may qualify. A loss followed by a winner may finish positive but below $12.50; that is acceptable. Do not take another trade solely to push it above the threshold.

---

## 5. Instrument/session selection

Candidate combinations:

- EURUSD London sweep/reclaim.
- GBPUSD London sweep/reclaim.
- USDJPY New York sweep/reclaim.

Optimization rules:

- Report expectancy, profit factor, maximum adverse excursion, slippage, qualifying-day contribution, and longest no-trade gap separately for each combination.
- Do not allow a profitable combination to conceal an unprofitable one in pooled results.
- Require stable performance in multiple volatility and trend regimes.
- If EURUSD and GBPUSD signal together, rank only after every hard gate passes and place at most one entry.
- A New York trade may occur only after the London trade/order is completely closed/cancelled.
- Remove a combination if it adds trade count but lowers joint challenge pass probability.

XAUUSD may only enter a later comparison after its 0.01-lot stop risk, spread, and stressed slippage are shown to be suitable for $2,500.

---

## 6. Parameters that must not be freely optimized

To avoid curve-fitting, keep these as compliance/structural constants:

- One open/working exposure.
- Thirty-minute red-news buffer.
- Cost no more than 0.10R.
- No market chase after an expired limit.
- Visible stop on entry.
- Volume always rounded down.
- No grid, martingale, averaging, hedge, copier, HFT, or arbitrage.
- Maximum two sequential trades per day.
- Daily stop no looser than 1%.
- Personal strategy shutdown no looser than 5%.

Limit optimization to the four dimensions locked in V2.1:

1. Range-quality percentile band.
2. ATR-regime percentile band.
3. Time stop.
4. Categorical execution profile: paired risk/target plus breakeven behavior.

The sweep, wick, displacement, and all compliance definitions remain fixed. They may be subjected to sensitivity checks, but not tuned digit by digit. Prefer a broad performance plateau over the highest point.

---

## 7. Completion and drawdown protection

V2.1 removes profit-level-based position-size ratchets. They created additional size inconsistency and could make a late $12.50 day impossible after volume rounding.

### Both evaluation phases

- Profit level does not change position risk.
- Only a fully valid setup may trade near the target.
- Phase 1 locks at or above $2,750 plus three dashboard-confirmed days.
- Phase 2 locks at or above $2,625 plus three dashboard-confirmed days.
- Target without confirmed days enters `TARGET_PENDING_DAYS` and requires reconciliation/review.

Drawdown response is simplified:

- 0-2%: selected paired-profile risk.
- 2-5%: one predeclared 50% reduction using the same target-R policy.
- 5%: emergency exposure-close boundary and formal shutdown.

Never reset strategy drawdown because a calendar month changed.

---

## 8. Required optimization experiment

### Data

- Tick-quality or broker-quality bid/ask data covering 2019 through the most recent available period.
- Correct Europe/London daylight-saving sessions.
- Historical red-folder calendar.
- The5ers-like commission and variable spread.
- Separate broker-stress scenario with 1.5× spread and 2× slippage.

### Process

1. Freeze the entry definition before viewing final holdout results.
2. Develop only on the training period.
3. Use rolling walk-forward windows and a final untouched holdout.
4. Store every candidate entry once, then replay risk/exit variants on the same event set.
5. Group results into actual server trading days.
6. Use block bootstrap by day/week to preserve loss clusters and simultaneous market regimes.
7. Simulate Phase 1 followed by a fresh Phase 2, including target throttles, volume rounding, three-day counts, inactivity, news, and all stops.
8. Rank by joint pass probability, then drawdown, then duration—never duration first.

### Suggested go/no-go gates

- At least 300 out-of-sample filled trades across enabled combinations.
- Net expectancy at least 0.20R after normal costs.
- Profit factor at least 1.30.
- Positive expectancy under the stressed-cost scenario.
- At least 70% simulated Phase 1 passes before the personal 5% shutdown.
- Joint two-phase pass probability reported explicitly; no minimum can be trusted until confidence intervals and sample stability are visible.
- At least 95% probability of having three qualifying days by each phase target under calendar/day-level replay.
- 95th-percentile drawdown below 5% over the expected challenge path.
- No 30-day inactivity failure in historical replay; alert logic still required because the future can differ.
- 30-50 forward-demo trades with zero compliance, restart, order-state, or sizing errors.

---

## 9. Recommended next version to test

Do not deploy this as proven; use it as the locked baseline against which alternatives are compared:

- Sleeve A M5 sweep/reclaim only.
- EURUSD/GBPUSD London and USDJPY New York, each retained only if separately valid.
- One working entry or open position account-wide.
- All entry and safety conditions mandatory; no 7/8 waiver.
- One limit entry, visible stop, no chase.
- Four paired risk/target profiles from 0.40%/+1.5R through 0.25%/+2.5R.
- No partial closing.
- Breakeven-after-confirmed-+1R versus no-breakeven candidate.
- 30/45/60/90-minute and session-only time-stop candidates.
- Maximum two sequential trades/day; any first net-positive exit or the second completed trade ends the day.
- Daily -1%, weekly -2%; 50% risk after 2% strategy DD; 5% emergency shutdown.
- No profit-level-based position-size changes.
- Flat before rollover, high-impact news, and weekends.

The winner is the complete variant with the highest robust **joint two-phase pass probability**, not the highest return or shortest lucky run.

---

## 10. Practical purchase sequence

1. Do not buy/activate the challenge while the EA and validation are unfinished; evaluation inactivity starts after activation.
2. Obtain/download the exact current agreement and confirm the checkout still represents $2,500 New High Stakes for $19.
3. Resolve any material rule ambiguity with written The5ers support, especially one-position interpretation and stage-size consistency.
4. Complete historical optimization without the final holdout.
5. Lock parameters and run the untouched holdout.
6. Complete forward demo and failure/restart drills.
7. Only then activate one challenge.
8. Do not change strategy parameters during either phase.
9. After passing, keep the same behavior through the first funded payout; do not add sleeves or accounts immediately.

This process is slower than guessing a high-return configuration, but unlimited evaluation time means patience is part of the edge.
