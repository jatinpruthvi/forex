# The5ers $2,500 New High Stakes Challenge Plan

Plan date: 2026-09-03
Status: historical operational summary; **do not use as the coding source of truth**

This plan is designed to maximize the probability of passing, not the speed of passing. No strategy can guarantee a win. The repository currently contains no verified backtest or live-fill record, so the plan must pass the validation gate in Section 12 before it is treated as ready.

The canonical improved build-and-validation specification is now `THE5ERS-CHALLENGE-STRATEGY-V2.md`. It supersedes implementation details in this summary wherever they conflict.

---

## 1. Challenge objective and boundaries

The $19 offer is the $2,500 **New High Stakes** two-step evaluation.

| Item | Phase 1 | Phase 2 |
|---|---:|---:|
| Starting balance | $2,500 | New phase account, normally $2,500 |
| Profit target | 10% = **$250** | 5% = **$125** |
| Target balance | **$2,750** | **$2,625** |
| Minimum profitable days | 3 non-necessarily-consecutive qualifying days | 3 non-necessarily-consecutive qualifying days |
| Minimum profit per qualifying day | 0.5% = **$12.50** | 0.5% = **$12.50** |
| Firm daily loss boundary | 5% of daily snapshot | Same |
| Firm overall loss boundary | 10% = **$250** | Same |
| Firm static termination floor | **$2,250 equity** | Normally $2,250 for a $2,500 phase account |
| Time limit | Unlimited | Unlimited |
| Evaluation inactivity limit | 30 consecutive days | 30 consecutive days |

The three days can occur anywhere in the phase; they do **not** have to be the first three trading days or consecutive. A smaller positive day is allowed but does not count. The exact published test is:

`min(midnight balance, midnight equity) - previous-day balance >= $12.50`

An open floating profit does not add to the count, while an open floating loss can reduce a day's result. Staying flat at rollover is the safest operational policy.

The objective is not to earn 10% every month. The only objectives are to reach each fixed target, accumulate three qualifying days as a natural result of valid trades, and never touch a rule boundary. Do not manufacture qualifying days by altering exits or spreading one trade idea across dates.

---

## 2. Recommended strategy profile

Use **TRIAD-R Challenge Profile**, a simplified session-event router.

### Active module

Use only **M5 sweep/reclaim reversal** for the first evaluation and through the first funded payout. It trades false session breakouts with a defined stop and short holding period.

The continuation route remains a shadow-mode research candidate. It is not enabled during the first challenge.

### Disabled for the first challenge

- Volatility continuation, Asian grid, and Asian mean reversion
- XAUUSD, GER40, US30, and GBPJPY until their minimum-lot risk and execution are independently validated
- M1/tick scalping, volume-delta scalping, carry, crypto funding, and free-margin stacking

### Initial instruments

- London: scan EURUSD and GBPUSD; trade only the better signal, never both.
- New York: scan USDJPY only when no earlier position or pending entry remains.
- Maximum two completed **sequential** trades per day.
- Maximum one working pending entry or one open position account-wide—never simultaneous positions.

The one-position rule follows The5ers' July 2026 prohibited-practices wording, which broadly defines multiple simultaneously open trades as bulk trading. The smaller universe lowers trade count but reduces correlated losses, rule errors, and lot-sizing mistakes. The evaluation has unlimited time, so quality is more important than frequency.

---

## 3. Entry router

All safety and execution gates are mandatory. A score must never make news, cost, stop geometry, or correlation optional.

### Shared hard gates

- Correct session and reference range.
- Current spread no more than 1.5 times the tested spread for that symbol/minute.
- Estimated round-trip cost no more than 0.10R.
- No Forex Factory red-folder event for either currency within 30 minutes.
- Cancel all entry pending orders before a news blackout.
- MT5 data is fresh and execution latency is within the tested bound.
- No correlated position is open.
- Proposed stop can be represented safely with the 0.01 lot step.

### Route A: sweep/reclaim reversal

For a long; reverse for a short:

1. Build the session reference high and low.
2. Range width must be within the validated percentile/median band.
3. Price sweeps below the range by 0.05-0.50 × M15 ATR.
4. An M5 candle closes back inside within three M5 candles.
5. Reclaim wick is at least 60% of the candle range.
6. Next M5 displacement candle has a body at least 60% of its range and closes beyond the prior midpoint.
7. Place a limit at the 50% retracement of the displacement body.
8. Cancel after three M5 candles, at session end, on news blackout, or if price reaches +1R without filling.
9. Stop below the sweep plus 0.10 × M15 ATR.
10. Reject if stop distance is outside 0.60-1.50 × M15 ATR.

### Accepted-breakout handling

If the range break does not reclaim, Sleeve A records the event as `GENUINE_BREAKOUT` and does not trade it. A continuation candidate may be logged in shadow mode for later research, but it cannot send an order during the first challenge.

---

## 4. Risk per trade

### Default evaluation risk

Risk **0.40% of the initial balance per trade**:

`$2,500 × 0.004 = $10 maximum planned loss`

This is deliberately below 0.50%. It allows meaningful progress while preserving room for slippage and losing clusters.

### Position-size formula

Do not assume $10/pip for every symbol. In MT5, use `OrderCalcProfit` or the symbol's live tick value.

`loss_per_lot = stop-loss cash loss + commission + slippage reserve`

`raw_lots = $10 / loss_per_lot`

`final_lots = round down to the 0.01 volume step`

Never round up beyond the $10 risk budget.

### Approximate EURUSD examples

Assuming approximately $10/pip per standard lot before commission:

| Stop | Raw size for $10 | Safe rounded size | Approx. price risk |
|---:|---:|---:|---:|
| 10 pips | 0.10 | 0.09-0.10 after costs | $9-$10 |
| 15 pips | 0.066 | 0.06 | $9 |
| 20 pips | 0.05 | 0.04-0.05 after costs | $8-$10 |
| 25 pips | 0.04 | 0.03-0.04 after costs | $7.50-$10 |
| 30 pips | 0.033 | 0.03 | $9 |
| 40 pips | 0.025 | 0.02 | $8 |

Actual MT5 tick value, commission, account currency conversion, and slippage reserve control the final lot.

---

## 5. Small-account exit logic

The canonical 40/30/30 ladder is often impossible with a 0.01 lot step. For example, a 0.03-lot position cannot be divided accurately into 40%, 30%, and 30%.

Use one MT5 position only. Do not create separate entry tickets because The5ers' current prohibited-practices page broadly treats simultaneous positions as bulk trading.

### First-challenge baseline

- Use one fixed target at a validated +1.5R.
- Do not increase lot size merely to make partial closes possible.
- Never carry partial closures across different days to manufacture profitable-day counts.

A one-position, same-day partial-close model may be compared in testing, but it must outperform the fixed-target model after commission, slippage, missed limits, and 0.01-lot rounding before it can replace the baseline.

### Time exits

- Close the reversal if +1R is not reached within the validated 30-60 minute plateau; 45 minutes is only an initial test candidate, not a live constant until validated.
- Close by the session hard stop.
- Flat before The5ers server rollover.
- Flat every Friday.

---

## 6. Daily operating rules

### Loss side

- First full loss: continue only if a second completely independent valid setup appears.
- Second full loss: approximately -0.8%; stop for the day.
- Internal daily stop: **-1.0% including floating P&L and costs**.
- Internal weekly stop: **-2.0% including floating P&L and costs**.
- Never take a third trade after two full losses.
- No recovery trade and no larger position after a loss.

### Profit side and qualifying-day handling

A qualifying day requires $12.50. At the $10 risk ceiling, a complete 1.5R winner is at most approximately $15 or 0.6% before any costs not already included in sizing. Actual profit can be lower after 0.01-lot rounding and costs, so the EA must calculate rather than assume whether the day qualifies.

- As a standing policy in evaluation and funded operation, one full planned winner ends trading for the day.
- Do not change a valid target, defer a close, add a trade, or split one idea across dates merely to create qualifying days.
- If an otherwise normal trading day finishes above $12.50, remain flat through server midnight so an open loss cannot reduce the published calculation.
- Confirm the profitable-day count in the dashboard before assuming it qualified.
- A day at +$12.49 or any smaller positive amount is not a breach; it simply does not count.

After three profitable days have been confirmed, do not alter the standing daily policy or overtrade simply because the minimum-day condition is complete.

---

## 7. Drawdown throttle

Drawdown is measured from the highest closed balance/equity reference, while the firm floor is tracked independently.

| Strategy drawdown | New-trade risk | Action |
|---:|---:|---|
| 0-2% | 0.40% = $10 | Normal |
| 2-3.5% | 0.20% = $5 | Half risk |
| 3.5-5% | 0.10% = $2.50, subject to lot granularity | Recovery/diagnostic only |
| 5% or more | 0 | Stop and revalidate |

Personal shutdown at 5% means stopping around $2,375, leaving approximately $125 before the firm's $2,250 termination floor. That reserve belongs to slippage and mistakes; it is not recovery-trade capital.

If 0.10% cannot be represented safely because the minimum lot risks more than $2.50, do not trade that symbol.

---

## 8. Profit protection by phase

### Phase 1

| Closed phase return | Risk/action |
|---:|---|
| 0% to +8% | Normal 0.40%, subject to DD throttle |
| +8% to +9.5% | Reduce to 0.20% |
| +9.5% or more | 0.10% only if lot-safe; otherwise wait for the cleanest setup |
| Target reached | Close/cancel everything and stop immediately |

Milestones:

- +5% balance: $2,625
- +8% balance: $2,700
- +9.5% balance: $2,737.50
- Target: $2,750

### Phase 2

Use the same process. Because the target is only 5%:

| Closed phase return | Risk/action |
|---:|---|
| 0% to +3.5% | Normal 0.40%, subject to DD throttle |
| +3.5% to +4.5% | Reduce to 0.20% |
| +4.5% or more | Minimum lot-safe risk |
| Target reached | Close/cancel everything and stop immediately |

Do not treat Phase 2 as easier and raise risk. Many traders fail after Phase 1 because they rush the smaller second target.

---

## 9. Firm-rule guard

The EA needs a rule engine independent of the trading strategy. On first authorized initialization, persist the account number, program/profile, phase, initial balance, and configuration checksum. On every later initialization, load that record and fail closed on a mismatch. Do not infer the phase by repeatedly comparing current `AccountBalance()` with $2,500 because ordinary profit or loss changes that value.

At each confirmed server rollover:

`daily_snapshot = max(rollover_balance, rollover_equity)`

`firm_daily_floor = daily_snapshot × 0.95`

`firm_overall_floor = phase_initial_balance × 0.90`

`active_firm_floor = max(firm_daily_floor, firm_overall_floor)`

The EA must also enforce a configurable safety floor above `active_firm_floor`. It must block orders if projected stop loss, open risk, commission, and slippage could cross that safety floor.

Never use London, Indian, or local computer time for the firm reset. Query MT5 server time.

---

## 10. News and EA compliance

- No new entry within 30 minutes of red-folder news, even though the firm restriction is two minutes.
- Cancel entry pending orders before the blackout.
- Pre-set SL/TP may remain, but do not modify by opening/reversing positions during the prohibited window.
- Visible broker-side stop on every position.
- No stealth stop.
- No M1 tick scalping or HFT.
- No latency, hedge, or reverse arbitrage.
- No external signal copying, account-to-account copying, or coordinated execution.
- Rate-limit order actions; no repeated cancel/modify/request bursts.
- Keep planned risk percentage consistent across evaluation and funded stages; raw lots may vary with stop distance and tick value.
- Support valid long and short signals symmetrically, but never force an opposite-direction trade merely to alter account history.
- Trader must own the EA source code.
- Any exception to the one-position/no-copy defaults requires specific written approval for the exact topology before use.

---

## 11. Expected path—not a promise

At 0.40% risk, Phase 1 requires 25 net R and Phase 2 requires 12.5 net R.

| Verified net expectancy | Expected trades for Phase 1 | Expected trades for Phase 2 |
|---:|---:|---:|
| 0.15R/trade | ~167 | ~84 |
| 0.20R/trade | ~125 | ~63 |
| 0.25R/trade | ~100 | ~50 |
| 0.30R/trade | ~84 | ~42 |
| 0.35R/trade | ~72 | ~36 |

This simple expectation calculation does not include variance, throttling, missed limits, minimum-day pauses, or profit-protection sizing. Actual passing time can be much longer, and the challenge can still fail.

At 20 qualified trades per month, Phase 1 may take several months. That is acceptable because the evaluation has unlimited time. Speed is not an edge.

---

## 12. Go/no-go validation before purchase or activation

Do not call the challenge plan ready until the exact challenge profile passes:

1. At least 300 out-of-sample trades across the selected instrument/session combinations, with each combination reported separately.
2. Net expectancy after The5ers-like spread and $4/lot FX commission of at least 0.20R.
3. Net profit factor of at least 1.30.
4. Profitable results with spread multiplied by 1.5 and slippage multiplied by 2.
5. Exact 0.01-lot rounding, MT5 cash P&L, small-account exits, server-day grouping, and the published profitable-day formula.
6. Historical news blackout and server-time/DST handling.
7. At least 10,000 day/week block-bootstrap simulations preserving losing clusters.
8. Simulate Phase 1 followed by a fresh Phase 2; rank variants by joint two-phase pass probability, not speed or monthly return.
9. Target at least 70% Phase 1 pass probability before the **personal -5% stop** and at least 95% probability that three qualifying days exist by each phase target.
10. The 95th-percentile maximum drawdown remains below 5% over the expected evaluation duration.
11. Compare the 0.40%/+1.5R baseline with 0.25-0.35% risk and +1.75R/+2R exits using actual lot rounding; do not assume a nominal full winner qualifies.
12. At least 30-50 forward-demo trades with zero implementation errors.

If 0.40% fails the drawdown/pass-probability tests, reduce risk. If lower risk makes the three-day condition unreliable because of lot granularity, compare robust exit variants rather than increasing lots. Do not widen the personal stop or use the firm's full 10% loss allowance. The full experiment is specified in `THE5ERS-CHALLENGE-OPTIMIZATION.md`.

---

## 13. Execution checklist

### Before the phase

- Confirm account is New High Stakes $2,500.
- Persist and verify the account/mode/phase identity, phase initial balance, and firm floors.
- Confirm server rollover time from MT5.
- Verify EURUSD, GBPUSD, and USDJPY contract/tick values and commission.
- Verify EA source ownership and permitted behavior.
- Load and verify the red-folder calendar.
- Test emergency close, rejected order, reconnect, and restart recovery.

### Before every order

- Correct phase and session?
- Hard signal gates all pass?
- News clear for 30 minutes?
- Spread and total cost acceptable?
- No correlated position?
- Lot rounded down and total planned loss no more than current tier?
- Visible SL attached?
- Firm and personal safety floors safe after projected loss?
- Daily trade/loss limit not reached?

### After every trading day

- Flat before rollover.
- Reconcile MT5 and dashboard balance/equity.
- Record P&L in dollars, percent, and R.
- Record MFE, MAE, spread, slippage, and exit reason.
- Confirm whether the day counted as a profitable day.
- Do not modify parameters during the phase.

---

## 14. Final passing plan

1. Validate the exact small-account strategy first.
2. Buy only one $19 challenge.
3. Trade $10 maximum planned risk per accepted setup.
4. Take at most two sequential trades and two losses per day, with only one working/open exposure account-wide.
5. Let the three $12.50 qualifying days arise from normal valid trades; do not engineer them by changing exits or distributing profit across dates.
6. Reduce risk near the target instead of trying to finish in one trade.
7. Stop the strategy at 5% drawdown, well before the firm's 10% floor.
8. Remain flat over news blackouts, rollover, and weekends.
9. Pass Phase 2 with the same discipline as Phase 1.
10. Do not buy or copy to another account until this one has passed and the funded workflow has been tested.

The $19 fee is small, but the challenge should still be treated as a controlled examination. The winning advantage is unlimited time plus strict loss control—not aggressive leverage.
