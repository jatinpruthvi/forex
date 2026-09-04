# TRIAD-R The5ers Challenge Strategy V2

Specification date: 2026-09-03
Revision: 2.1, revalidated against the complete High Stakes lifecycle
Status: improved build-and-validation specification; **not approved for live trading until Section 13 passes**

This is the canonical improved specification for the $2,500 New High Stakes evaluation. It incorporates the rule audit, profitable-day clarification, small-account lot constraints, and challenge-level optimization design. It supersedes earlier challenge implementation choices where they conflict.

---

## 1. Objective

Maximize the probability of completing both phases before the internal 5% strategy shutdown, while:

- Reaching +10% ($250) in Phase 1.
- Reaching +5% ($125) in Phase 2.
- Producing any three qualifying days per phase under the official formula.
- Never approaching the firm's 5% daily or 10% overall termination levels as operating targets.
- Producing zero prohibited-practice, news, account-state, or order-state violations.

Optimization priority is lexicographic:

1. Zero compliance failures.
2. Highest joint two-phase pass probability.
3. Lowest 95th-percentile drawdown.
4. Shortest median duration only as a final tie-breaker.

Monthly ROI and fastest completion are not optimization objectives.

---

## 2. Immutable The5ers profile

These settings cannot be optimized or waived:

- One working entry order **or** one open position account-wide.
- No simultaneous positions, separate target tickets, copier, or coordinated account execution.
- No grid, martingale, averaging, hedge, recovery trade, HFT, tick scalping, arbitrage, emulator, or stealth stop.
- Broker-visible stop attached to every entry.
- No new entry or working entry order within 30 minutes of relevant red-folder news.
- No market chase after an expired limit.
- Maximum two completed sequential trades per server day.
- Volume always rounded down; never increase size to satisfy the profitable-day threshold.
- Long and short rules are exact mirrors; no forced direction alternation.
- Runtime optimization and automatic parameter mutation are disabled.
- The trader owns and retains the complete EA source code and build record.
- Trade-server actions are rate-limited: no per-tick order modification, at most one revalidated retry after a transient rejection, and a default cap of 20 non-emergency trade requests per server day. Reaching the cap blocks new entries and halts the strategy; it must never suppress a necessary pending-order cancellation or emergency close.
- The same selected base-risk process remains in force through Phase 1, Phase 2, and the initial funded period.

Any future exception requires current written approval from The5ers for the exact behavior. The 20 non-emergency-request cap is an intentionally conservative engineering default, not a published The5ers number; validation may lower it but may not remove rate limiting or safety-operation priority.

---

## 3. Enabled strategy and universe

Only Sleeve A, M5 session sweep/reclaim, may trade.

Candidate instrument/session combinations:

| Combination | Reference range | Candidate entry window |
|---|---|---|
| EURUSD London | 00:00-07:00 Europe/London | 07:00-11:00 Europe/London |
| GBPUSD London | 00:00-07:00 Europe/London | 07:00-11:00 Europe/London |
| USDJPY New York | 07:00-13:00 Europe/London | 08:30-11:00 America/New_York |

An instrument/session combination is enabled in production only if it passes Section 13 independently. A profitable pooled portfolio cannot conceal a losing combination.

XAUUSD, GBPJPY, indices, continuation, and Asian mean reversion remain disabled for the first evaluation and first funded payout.

London definitions use the `Europe/London` civil-time zone and the New York entry window uses `America/New_York`; both must be converted independently to MT5 server timestamps. This avoids the temporary one-hour error during the weeks when US and UK daylight-saving changes do not coincide. Firm daily snapshots and profitable-day grouping use confirmed MT5 server rollover. These are separate clocks.

---

## 4. Mandatory pre-signal gates

Every gate must pass. There is no 7/8 override.

1. The instrument/session combination is enabled by the locked configuration.
2. No working entry or open position exists anywhere on the account.
3. Current reference-range width lies within the selected historical percentile band calculated from the prior 60 completed comparable sessions only.
4. ATR(M15,14) lies within the selected historical percentile band calculated from the prior 60 completed comparable session opens only.
5. Current spread is no more than 1.5 times its median for the same symbol and minute-of-session over the prior 60 completed comparable sessions.
6. Estimated all-in round-trip cost is no more than 0.10R.
7. No Forex Factory red-folder event for either currency is due within 30 minutes; USD restrictions apply to every USD pair, and an unavailable/unmapped calendar fails closed.
8. Quote age, bar state, symbol properties, and calendar state are valid.
9. Measured execution health is inside the tested latency/slippage bounds.
10. Stop and target prices satisfy live MT5 stop/freeze levels.
11. The rounded volume does not exceed the active risk tier.
12. The planned target fits inside the reference range: for a long, `reference_high - planned_entry >= target_distance`; for a short, `planned_entry - reference_low >= target_distance`.
13. Projected stressed loss remains above all internal and firm safety floors.

The operational red-news feed must carry an explicit operator-verified UTC coverage-through declaration. The timestamp of the latest event is not evidence that intervening events are complete. Runtime calendar coverage must remain current and fail closed. Exact entry, news, session, Friday, and rollover boundaries are approached with a small fixed early execution lead frozen in the validated release; the lead may make controls earlier but never later.

Initial range-band test candidate: 30th-80th percentile. Challenger: 35th-75th percentile. Initial ATR-band test candidate: 20th-80th percentile. Challenger: 25th-75th percentile. Final bands are selected offline only.

---

## 5. Entry sequence

For a long; invert every price comparison for a short:

1. Price trades below the reference low by 0.05-0.50 × ATR(M15,14).
2. An M5 candle closes back inside the reference range within three completed M5 candles.
3. The reclaim candle's lower wick is at least 60% of its total range.
4. The next completed M5 displacement candle has a body at least 60% of its range and closes above the prior candle midpoint.
5. Place one limit order at the 50% retracement of the displacement candle body.
6. Attach the calculated broker-visible stop and target in the initial order request.
7. Cancel the order after three completed M5 bars, at the session cutoff, before the news buffer, or if price reaches the theoretical +1R level without filling.
8. Never replace a cancelled/expired order with a market order.

A breach deeper than 0.50 ATR, no reclaim, late reclaim, weak displacement, or insufficient target room is `NO_TRADE`. An accepted breakout may be logged for continuation research but cannot send an order.

Only one signal event per symbol/session may produce an order. Repeated sweeps of the same reference level do not reset the event.

---

## 6. Stop and cash-risk calculation

For a long:

`stop_price = sweep_low - 0.10 × ATR(M15,14)`

For a short:

`stop_price = sweep_high + 0.10 × ATR(M15,14)`

Reject if entry-to-stop distance is outside 0.60-1.50 × ATR(M15,14).

Define cash risk using live symbol economics:

`all_in_loss(lots) = abs(OrderCalcProfit(entry, stop, lots)) + commission + slippage_reserve`

`risk_budget = phase_initial_balance × active_risk_fraction`

Select the largest valid volume-step value for which:

`all_in_loss(lots) <= risk_budget`

Additional rules:

- Read tick size, tick value, contract size, volume minimum/maximum/step, stops level, and currency conversion from MT5.
- Never assume $10/pip.
- Never round volume up.
- Skip if minimum volume exceeds the risk budget.
- Use the persisted phase initial balance, not changing equity, as the normal sizing base.
- Only the single predeclared drawdown tier may reduce risk; profit level, phase, day count, and recent results cannot change it.

---

## 7. Exit engine

Only one position may exist. The live configuration contains exactly one frozen exit model.

### Champion baseline to test

- Use paired Profile A from Section 8: 0.40% maximum risk with a fixed +1.5R target.
- Solve the take-profit price using `OrderCalcProfit` so estimated **net** target profit equals the profile's target R after expected commission and the configured take-profit slippage allowance.
- Define `+1R confirmed` as a completed M5 candle close at or beyond the calculated +1R price; a tick/wick touch does not qualify.
- If +1R has not been confirmed within 45 minutes from confirmed fill, close at market.
- Compare moving the broker-visible stop to entry after +1R confirmation against leaving the original stop unchanged. Entry price is not called risk-free because commission, gaps, and slippage remain.
- Close at the session hard stop.
- Close before the rollover and weekend buffers.

### Offline challengers

Compare the four paired risk/target profiles in Section 8 without changing the entry event set. For each profile, compare:

- Broker-visible stop moved to entry only after a completed M5 close beyond +1R.
- Original stop left unchanged.
- Time stops of 30, 45, 60, and 90 minutes, plus session-only.

The selected champion freezes one paired risk/target profile, one time-stop rule, and one breakeven policy. **Partial closing is removed from the initial challenge implementation entirely.** This keeps one entry, one position, one final close, and removes the remaining same-day partial/bulk-trading interpretation question.

### Forced-flat rules

- Flat at least 15 minutes before confirmed MT5 server rollover.
- Flat at least 15 minutes before relevant CPI, NFP, FOMC, central-bank rate decisions, and any other configured red event during the position's expected holding window.
- No re-entry until 30 minutes after the event.
- Flat by Friday 20:00 Europe/London or earlier if the symbol closes earlier.

Permission to hold through news, rollover, or weekends is not used in this challenge profile.

---

## 8. Risk engine

### Offline paired risk/target candidates

Risk and target are tested as paired profiles so lower-risk candidates still have a normal full-target outcome near 0.6% before lot rounding and costs:

| Profile | Maximum risk | $2,500 cash ceiling | Fixed target | Nominal risk × target |
|---|---:|---:|---:|---:|
| A baseline | 0.40% | $10.00 | +1.50R | 0.600% |
| B | 0.35% | $8.75 | +1.75R | 0.613% |
| C | 0.30% | $7.50 | +2.00R | 0.600% |
| D | 0.25% | $6.25 | +2.50R | 0.625% |

These nominal values do not prove that a rounded live winner qualifies as a $12.50 day. Every profile is replayed with actual volume rounding and costs. No candidate above 0.40% is permitted. The winning profile is selected only after freezing the out-of-sample event series and is then used unchanged in Phase 1, Phase 2, and the initial funded period.

### Drawdown throttle

The strategy high-water mark is the highest balance observed while the account is flat. Current strategy drawdown is measured from that high-water mark to current equity, so open losses count. It is checked continuously for emergency protection and before every new order. A new calendar month never resets it, and an open position is never resized because its tier changed after entry.

| Drawdown | Active fraction of selected profile risk | Action |
|---:|---:|---|
| 0-2% | 100% | Normal |
| 2-5% | 50% | Reduced risk using the same entry/target-R policy |
| 5% or more | 0% | Cancel entries, attempt to close open risk immediately while executable, halt, reconcile, and require formal revalidation |

The 5% value remains the absolute internal emergency boundary and operational reserve limit. Removing the former 25% tier avoids minimum-lot distortion and the largest stage-consistency ambiguity while retaining a defined half-risk recovery path.

### Loss governors

- Internal daily stop: -1.0% = $25 at inception, measured from the flat server-day starting balance and including closed/floating P&L and costs.
- Internal weekly stop: -2.0% = $50 at inception, measured from the flat balance at the first server rollover of the trading week and including closed/floating P&L and costs.
- The second trade is permitted only if its stressed full-stop outcome would remain above the daily, weekly, strategy, and firm safety floors.
- Two full losses: stop for the day even if the -1% limit has not been reached.
- No risk increase after a loss, win, profitable week, or target approach.

The single 50% drawdown reduction is predeclared, applied identically in evaluation and funded operation, and logged. If the purchased agreement or written support rejects this ordinary risk-reduction tier, the fallback is no new trade at 2% drawdown—not continuation at larger risk.

---

## 9. Daily operating state machine

`DAY_READY -> FIRST_TRADE -> {NET_POSITIVE: DAY_LOCKED, NET_NONPOSITIVE: SECOND_ELIGIBLE_IF_SAFE} -> SECOND_TRADE -> DAY_LOCKED`

Rules:

1. Take only a fully valid signal.
2. Any first-trade net profit locks the day in all evaluation and funded modes, even when it is below $12.50 and does not qualify. This protects earned profit without consulting the day counter.
3. After a zero or net-loss first exit, one second independently valid setup may trade only if its stressed stop outcome remains inside every daily, weekly, strategy, and firm limit.
4. A time exit is classified using final net cash P&L; partial closing does not exist in this profile.
5. The second completed trade always locks the day regardless of outcome.
6. Daily/weekly/drawdown governors can lock earlier.
7. Locking cancels every working entry and prevents retries.
8. The state resets only after a confirmed server rollover and successful reconciliation.

The second-trade decision does not inspect the profitable-day counter or the dollars still needed to reach $12.50. Do not take another trade solely to cross $12.50, recover a loss, alternate direction, or prevent inactivity.

---

## 10. Profitable-day engine

For each phase:

`qualification_threshold = phase_initial_balance × 0.005 = $12.50`

At confirmed rollover:

`day_result = min(midnight_balance, midnight_equity) - previous_day_balance`

`qualifies = day_result >= $12.50`

Controls:

- Store the predicted net target cash before entry and actual net cash after exit.
- Do not assume 0.40% × 1.5R qualifies; volume rounding and costs can reduce it.
- Do not alter volume, target, exit date, or trade count based on the day counter.
- Do not distribute one idea or its partial exits across dates.
- Smaller positive days are valid but do not count.
- Losing days do not reset the count.
- The EA count is an estimate; the dashboard is authoritative.
- Phase 2 starts a new three-day counter.
- A phase is complete only when both the balance target and dashboard-confirmed three-day condition are satisfied.
- If the balance target is reached before the dashboard confirms three days, enter `TARGET_PENDING_DAYS`: remain flat, alert, reconcile the formula/dashboard, and require human review before the unchanged strategy may resume. The EA must not invent a special trade, size, target, or exit for this state.

The offline optimizer must reject configurations with less than 99% probability of having three qualifying days by each target in calendar/day-level replay. This higher gate makes `TARGET_PENDING_DAYS` an exceptional reconciliation state rather than a normal operating path.

---

## 11. Firm-rule and target protection

Persist on first authorized initialization:

- Account number and server.
- Program/profile and phase.
- Phase initial balance.
- Selected base risk and exit configuration.
- Configuration/build checksum.
- Prior rollover balance/equity and day counters.

Fail closed on any mismatch. Never infer phase from current `AccountBalance()`. External cashflow, unauthorized order/deal history, or exposure found/reconstructed across rollover makes the old accounting basis non-resettable by an ordinary halt clear; continuation requires a separately reviewed state migration/rebaseline release.

At rollover:

`firm_daily_floor = max(rollover_balance, rollover_equity) × 0.95`

`firm_overall_floor = phase_initial_balance × 0.90`

`active_firm_floor = max(firm_daily_floor, firm_overall_floor)`

The current public general-rules page describes rollover as 00:00 UTC+3, while the drawdown/news pages call it server time. The implementation must use and verify the live MT5 server boundary, log its UTC offset, and fail closed if the observed boundary/configuration disagrees with the account documentation.

No order may be sent if stressed projected loss can cross `active_firm_floor + firm_floor_reserve`, where the conservative default reserve is the greater of 0.5% of phase initial balance or twice the configured one-trade gap/slippage reserve. This reserve is internal, not an official The5ers rule.

### Phase 1 completion guard

- Profit level does not change position risk; only the drawdown tier can reduce it. This preserves stage-to-stage and near-target sizing consistency.
- Every new trade must remain fully valid and fit all floors even when the account is close to target.
- At or above $2,750 **and** with three dashboard-confirmed qualifying days: close/cancel and lock phase.
- If the balance target is reached without the confirmed day condition, enter `TARGET_PENDING_DAYS`.

### Phase 2 completion guard

- Use the same selected profile and drawdown policy as Phase 1; the smaller target never permits higher risk.
- At or above $2,625 **and** with three dashboard-confirmed qualifying days: close/cancel and lock phase.
- If the balance target is reached without the confirmed day condition, enter `TARGET_PENDING_DAYS`.

The former +8%/+9.5% and +3.5%/+4.5% profit-based size reductions are removed. They were unverified, created additional lot-size variation, and could make a late qualifying day mathematically impossible on the small account.

---

## 12. Signal collision and ranking

When more than one candidate occurs before an order is placed:

1. Discard every candidate that fails any mandatory gate.
2. Use the locked instrument/session priority learned only from training/walk-forward data.
3. If priorities tie, select the lower all-in cost/R candidate.
4. If still tied, select the first completed valid signal.
5. Log every rejected candidate and collision reason.

Ranking never changes risk and never allows more than one order. EURUSD and GBPUSD cannot both trade from the same London event. Combination priorities are derived once by a predeclared training/walk-forward rule (for example, descending training expectancy subject to the independent gates), not optimized as an additional free parameter; exact ties may remain equal. The frozen priority values and derivation evidence are included in the release record before OOS evaluation.

---

## 13. Validation and offline selection

### Data and replay

- Bid/ask tick-quality or broker-quality data from 2019 through the latest available period.
- Europe/London DST and MT5 server-day mapping.
- Historical red-folder calendar.
- The5ers-like commission, variable spread, slippage, missed limits, stop gaps, and volume rounding.
- Day/week block bootstrap preserving loss clusters.

### Anti-overfit process

1. Freeze the event/entry definition, including the 0.05-0.50 ATR sweep band.
2. Develop only on training windows.
3. Use rolling walk-forward tests.
4. Select at most four parameter dimensions: range band, ATR band, time stop, and categorical execution profile (paired risk/target plus breakeven behavior).
5. Use only the coarse candidates declared in this specification; no digit-by-digit tuning.
6. Prefer broad performance plateaus.
7. Lock one champion configuration before opening the untouched final holdout.
8. Never choose using the final holdout.

### Per-combination gates

Each enabled instrument/session requires:

- At least 100 out-of-sample fills; at least 300 in aggregate.
- Positive net expectancy.
- Profit factor at least 1.15 independently.
- No single year/regime responsible for the entire profit.

Portfolio gates:

- Net expectancy at least 0.20R.
- Profit factor at least 1.30.
- Positive expectancy at 1.5× spread and 2× slippage.
- At least 10,000 calendar-aware day/week block-bootstrap paths.
- Phase 1 pass probability at least 70% before the personal 5% shutdown.
- Phase 2 pass probability at least 85%.
- Joint two-phase pass probability at least 60%, reported with confidence bounds.
- At least 99% probability of three qualifying days by each target.
- Report median, 95th-, and 99th-percentile maximum drawdown on all paths; do not claim a meaningful sub-5% percentile merely because the simulator stops paths at 5%.
- Under the predefined gap/slippage stress, 99th-percentile overshoot beyond the 5% shutdown is no more than 1%, and no simulated path touches the firm's 10% overall floor.
- No historical 30-day inactivity failure in replay; future inactivity alerts still required.
- Zero simulated rule-state violations.

### Forward gate

- 30-50 forward-demo fills on the intended infrastructure.
- Zero manual interventions.
- Zero account-state, calendar, size, duplicate-order, restart, or stop-attachment errors.
- Live-demo expectancy and cost remain inside predefined confidence bounds.

A failed gate results in rejection or lower risk—not looser loss limits.

---

## 14. Product, phase-transition, funded, and production lifecycle

### Before challenge activation

- Confirm that checkout and the saved agreement explicitly identify **$2,500 New High Stakes** with 10%/5% targets, 5% daily loss, 10% overall loss, and three qualifying days per evaluation phase.
- Do not confuse High Stakes with the separate 2026 Summer 2-Step $100,000 product, whose current public page describes a 3% daily limit, $250 payout minimum, payout cap, and a funded consistency rule. If the purchased agreement shows those terms, this profile is incompatible and must fail closed pending a separate configuration.
- Complete identity/jurisdiction/KYC requirements using only the account owner's details; never share or resell account access.
- Save the agreement, purchase timestamp, account/profile identifiers, and applicable FAQ snapshot.
- Save the selected parameters, source version, compiler version, and checksum.
- Disable runtime optimizer and external command paths that can alter strategy behavior.
- Perform disconnect, restart, stale-quote, rejected-order, partial-fill, duplicate-position, missing-stop, calendar-failure, and rollover drills.
- Activate only one challenge after the EA is ready; do not consume the 30-day inactivity window during development.

### During each evaluation phase

- No parameter changes.
- Reconcile MT5 and the dashboard daily.
- Record every signal/no-signal, fill, MFE, MAE, cost, slippage, exit, and day calculation.
- Record long/short counts and the market-condition evidence for each direction. Direction concentration creates a review alert but never forces an opposite trade.
- Warn at 20 inactive days and escalate at 25; never place a maintenance trade.
- If the platform ever shows more than one open position because of a partial fill, reconciliation fault, manual action, or any other cause, cancel all entry orders, reduce to zero exposure as safely as executable, and halt for review.
- If a filled position lacks its intended visible stop, attempt one immediate protective correction; if that fails, close the position and halt.

### Phase 1 to Phase 2

- Keep Phase 1 locked after both target and day conditions are dashboard-confirmed.
- Do not assume credentials, timing, initial balance, or counters for Phase 2.
- On receipt of the Phase 2 account, require a human-authorized transition that verifies account number, server, product, $2,500 initial balance, symbol specifications, and rule set.
- Create a new static overall floor, daily-rollover state, three-day counter, and phase journal.
- Preserve the exact champion strategy/configuration; do not optimize between phases.
- No order may be sent until the new account has completed a clean initialization/reconciliation cycle.

### Phase 2 to funded

- Lock Phase 2 after both target and day conditions are dashboard-confirmed.
- Treat funded credentials as another new-account transition; never reuse evaluation floor/counter state.
- Re-read the funded initial balance, symbol specifications, leverage, permissions, payout terms, and current agreement.
- Keep the same source version, entry logic, normal risk process, one-position rule, and daily state machine through the first payout.
- Funded scaling has its own 10% target and the live High Stakes page currently shows three profitable days for scaling; track these separately but do not manufacture them.

### Payout and scaling controls

- The current High Stakes payout FAQ permits the first request after at least 14 funded days and at least $150 **after the profit split**; dashboard/account terms remain authoritative.
- At an 80% split, a $150 payout requires at least $187.50 distributable gross profit, equal to 7.5% of $2,500 before withdrawal processing charges.
- Enter `PAYOUT_REQUEST_LOCK` before a request: cancel pending entries, close all open trades, reconcile balance/dashboard, and require human confirmation. The EA never submits a payout.
- The current High Stakes-specific FAQ says 70% of an externally paid evaluation fee is eligible with the first qualifying payout; conflicting promotion-specific refund pages must not override the account's own terms.
- A scale-up also requires all trades closed. After scaling, treat the result as a new configuration event: verify the new level initial balance/floors/specifications, reset the relevant 14-day payout timer, and require clean initialization before trading.
- A payout or scale event must never silently change risk, floors, or counters while an order/position exists.

### After the first funded payout

- Do not add a copier, account, sleeve, gold, index, or simultaneous exposure.
- Review only after at least 100 error-free funded trades and one completed payout.

---

## 15. What V2 improves

Compared with the earlier challenge plan, V2:

- Replaces optional scoring with mandatory gates.
- Adds a target-room gate.
- Separates strategy-session time from server-rollover time.
- Defines cash risk and net target using actual MT5 economics.
- Tests four paired risk/target profiles instead of optimizing risk and reward independently.
- Treats time stop and breakeven behavior as test candidates rather than proven constants.
- Selects the complete profile using two-phase probability and actual qualifying days.
- Tests every instrument/session separately.
- Adds exact collision handling and one-event protection.
- Uses one immutable daily policy before and after the three-day condition.
- Removes same-position partial closes from the initial implementation.
- Removes profit-based sizing changes and the minimum-lot-distorting 25% tier.
- Retains only one predeclared 50% drawdown reduction; otherwise the profile halts rather than changing size repeatedly.
- Adds anti-overfit selection, confidence-aware validation, configuration freeze, failure drills, and full phase/payout lifecycle handling.
- Keeps the live system simple: one strategy, one order, one position, and one final close.

No extra indicator or additional position was added because the highest-value improvements are execution integrity, lower variance, exact small-account arithmetic, and honest selection—not more complexity.
