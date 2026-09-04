# TRIAD-R Challenge Strategy V2 — Point-by-Point Revalidation

Revalidation date: 2026-09-03
Scope: The5ers $2,500 New High Stakes, strategy V2, and pre-coding readiness
Canonical strategy reviewed: `THE5ERS-CHALLENGE-STRATEGY-V2.md`

A later lifecycle-completeness pass is recorded in `THE5ERS-END-TO-END-PRECODE-CHECKLIST.md`. It adds product-disambiguation, phase-transition, funded, payout, scaling, duplicate-position, and missing-stop checks; use that checklist as the final pre-code/pre-live gate.

## Final revalidation verdict

The V2 architecture is internally coherent and substantially safer than the original proposal. No fundamental strategy replacement is recommended before building the research/backtest implementation.

However, two different meanings of “validated” must remain separate:

1. **Rule/design revalidation:** completed in this document against current public The5ers pages.
2. **Statistical edge validation:** not possible before a reproducible implementation and data replay exist.

Therefore:

- **GO, after user approval, for coding an offline backtest/compliance harness.**
- **NO-GO for challenge activation or production trading** until the Section 13 gates in V2 pass.
- No coding was started during this revalidation.

Several strategy values remain deliberately labeled test candidates rather than facts: the four paired risk/target profiles, time stop, range/ATR bands, breakeven behavior, and which instrument/session combinations survive.

---

## 1. Official-rule recheck

All pages below were fetched again on 2026-09-03.

| Rule point | Current public information | V2 treatment | Verdict |
|---|---|---|---|
| Product | Live selector shows $2,500 New High Stakes at $19 | Designed for this product; checkout/agreement must still be saved before purchase | **Confirmed now; verify at checkout** |
| Structure | Two-step evaluation | Separate Phase 1 and Phase 2 state | **Confirmed** |
| Phase 1 target | New High Stakes requires 10% = $250 | Locks only at $2,750 plus day condition | **Confirmed** |
| Phase 2 target | 5% = $125 | Locks only at $2,625 plus day condition | **Confirmed** |
| Minimum days | At least three profitable days per phase | Separate three-day counter per phase | **Confirmed** |
| “First/consecutive” days | Current rules say “at least 3”; they do not say first or consecutive | Any three qualifying days; no reset after a losing/small-positive day | **Confirmed interpretation** |
| Qualifying amount | 0.5% of initial balance = $12.50 | Uses phase initial balance × 0.005 | **Confirmed** |
| Qualifying formula | `min(midnight balance, midnight equity) - previous-day balance` | Exact same formula; dashboard remains authoritative | **Confirmed** |
| Overall loss | 10% absolute from initial balance = $250; floor $2,250 | Static floor from persisted phase initial balance | **Confirmed** |
| Daily loss | 5% from higher prior rollover balance/equity | Computes `max(balance,equity) × 0.95` floor | **Confirmed** |
| Daily boundary | General page currently says 00:00 UTC+3; detailed pages say server time | Uses observed MT5 server boundary and fails closed on disagreement | **Confirmed with runtime verification** |
| Time limit | Unlimited evaluation time | Optimizes pass probability, not speed | **Confirmed** |
| Inactivity | 30 days evaluation from registration; 60 funded | Warn day 20, escalate day 25, no fake trade | **Confirmed** |
| News opening restriction | No new market/entry-pending order from two minutes before through two minutes after related red-folder news | Uses a stricter 30-minute buffer and cancels pending entries | **Confirmed; conservative** |
| Existing trades at news | Holding is allowed; preset SL/TP can execute | V2 voluntarily flattens 15 minutes before relevant configured red events | **Allowed conservative design** |
| Overnight/weekend | Holding is allowed | V2 voluntarily stays flat | **Allowed conservative design** |
| EA use | Allowed if it avoids prohibited EA practices | V2 avoids tick scalping, HFT, arbitrage, emulators, and copying | **Confirmed** |
| Stop loss | Must be visible on platform | Stop is attached in initial request | **Confirmed** |
| Source code | Trader must own it | Source/build ownership and records required | **Confirmed** |
| Bulk trading | Current prohibited-practices page defines it as multiple trades open simultaneously | Global mutex permits one working entry or one open position only | **Confirmed conservative response** |
| Copy/coordination | Prohibited with other traders or accounts | No copier or coordinated execution | **Confirmed** |
| Artificial day distribution | Prohibits splitting/hedging one idea across dates to inflate day count | No cross-day partial, hedge, or day-counter-driven exit | **Confirmed** |
| One-sided bets | Consistently taking one direction regardless of conditions is prohibited | Mirrored long/short rules; logs directional evidence; never forces alternation | **Confirmed design response** |
| Excess requests | Excess EA order/pending modification traffic is prohibited | No per-tick modifications, one revalidated retry, default cap 20 trade requests/day | **Confirmed response; cap is internal** |
| Size consistency | Substantially inconsistent size across activity/stages is prohibited | Same base process across stages; documented throttles only; raw lots vary with stops | **Mostly aligned; written clarification recommended for 25% throttle** |
| Overexposure/gambling | Concentrated or disproportionate risk is prohibited | Maximum 0.40%, one exposure, no event gamble, strict news/drawdown controls | **Confirmed response** |
| Platform | MT5 Hedge, 1:100 | MT5 implementation with one-position restriction | **Confirmed** |
| FX volume | 0.01 minimum and 0.01 step; live MT5 specifications control | Exact step/minimum and `OrderCalcProfit`; always round down | **Confirmed** |
| FX commission | Public page currently lists $4/lot round trip | Included as live/configured cost; MT5 specification overrides stale web values | **Confirmed** |

### Rule sources

- https://the5ers.com/high-stakes/
- https://the5ers.com/faqs/what-are-the-general-rules-for-the-high-stakes-program/
- https://the5ers.com/faqs/how-do-you-define-a-profitable-day-in-the-high-stakes-program/
- https://the5ers.com/faqs/what-is-the-drawdown-rule-for-high-stakes/
- https://the5ers.com/faqs/is-news-trading-allowed-in-the-high-stakes-program2024/
- https://the5ers.com/faqs/can-i-use-an-ea-expert-advisor-can-i-set-a-stealth-mode-stop-loss/
- https://the5ers.com/faqs/prohibited-trading-practices/
- https://the5ers.com/asset-specifications/

---

## 2. V2 objective and architecture

| V2 point | Revalidation | Status |
|---|---|---|
| Optimize joint two-phase success | Correct objective for the user's challenge | **Approved** |
| Compliance before return | Correct because a rule failure overrides expectancy | **Approved** |
| Drawdown before speed | Correct because evaluation time is unlimited | **Approved** |
| Sleeve A only initially | Reduces implementation, regime-routing, and rule complexity | **Approved design; edge requires data** |
| One EA supervisor | Necessary for the account-wide order mutex and shared floors | **Approved** |
| No additional indicator/sleeve | Correct before core edge is reproduced | **Approved** |
| No production claim | Required; current mathematical probabilities are conditional models | **Approved** |

The strategy is a solid blueprint rather than a proven edge. Additional complexity is not an appropriate pre-test “improvement.”

---

## 3. Instruments, sessions, and clocks

| V2 point | Revalidation | Status |
|---|---|---|
| EURUSD London candidate | Liquid, low-cost candidate suitable for a small account | **Approved for testing** |
| GBPUSD London candidate | Suitable but must pass independently after its higher spread/slippage | **Approved for testing** |
| USDJPY New York candidate | Adds a later sequential opportunity; still has USD factor exposure but never overlaps | **Approved for testing** |
| XAUUSD excluded | Correct because 0.01 lot, spread, and slippage can make $10 risk inaccurate | **Approved** |
| London range 00:00-07:00 | Mechanically defined, common session reference; profitability unproven | **Test required** |
| London entry 07:00-11:00 | Exact and DST-aware | **Test required** |
| New York entry | Corrected from fixed London time to 08:30-11:00 `America/New_York` | **Corrected and approved for testing** |
| London/NY DST mismatch | V2 now converts each civil time zone independently | **Corrected** |
| Firm rollover | Uses live server boundary, not session/local computer time | **Approved** |
| One combination hiding another | Prevented by minimum independent gates | **Approved** |

The New York timezone correction was material: a fixed 13:30 London start is wrong during the weeks when US and UK daylight-saving transitions differ.

---

## 4. Mandatory gates

| Gate | Revalidation | Status |
|---|---|---|
| Combination enabled by locked config | Prevents unvalidated symbols from trading | **Approved** |
| Account-wide order/position mutex | Enforces conservative bulk-trading interpretation | **Approved** |
| Range percentile | More robust than raw pip or short median threshold | **Candidate bands require data** |
| ATR percentile | Rejects dead and extreme conditions | **Candidate bands require data** |
| Spread by symbol/minute/session | Correct comparison; prior 60 completed sessions prevents lookahead | **Approved design; threshold test required** |
| Cost ≤0.10R | Sensible cost ceiling and mandatory | **Approved design** |
| Both-currency news mapping | Required for every FX pair | **Approved** |
| Calendar unavailable = fail closed | Correct | **Approved** |
| Quote/bar/symbol freshness | Required | **Approved; exact latency thresholds require measurement** |
| MT5 stop/freeze levels | Required to avoid rejects | **Approved** |
| Rounded volume ≤ risk | Correct | **Approved** |
| Target room | Now exactly defined using the opposite reference-range extreme | **Corrected; incremental value requires data** |
| Stressed floor projection | Correct defense against firm limits | **Approved** |

No score can waive one of these gates. A score may rank already-valid signals only.

---

## 5. Entry sequence

| Entry point | Revalidation | Status |
|---|---|---|
| Sweep 0.05-0.50 M15 ATR | Scale-normalized and mechanically defined | **Fixed test definition; edge unproven** |
| Reclaim within three closed M5 bars | Exact, prevents late discretionary entries | **Approved for testing** |
| Reclaim wick ≥60% | Exact | **Test required** |
| Next M5 displacement body ≥60% | Exact | **Test required** |
| Close beyond prior midpoint | Exact | **Test required** |
| Limit at 50% body retracement | Avoids chasing and defines price | **Approved for testing** |
| Stop/target attached initially | Correct rule/execution defense | **Approved** |
| Expire after three M5 bars | Exact | **Test required** |
| Cancel at news/session/+1R without fill | Correct stale-order defense | **Approved design** |
| No market chase | Reduces slippage and strategy drift | **Approved** |
| Deep/accepted breakout = no trade | Prevents Sleeve A from fading its known failure regime | **Approved** |
| One event/order attempt | Prevents repeated request loops and overtrading | **Approved** |
| Mirrored short logic | Addresses directional neutrality | **Approved** |

No entry rule is internally contradictory. Wick, displacement, limit, and expiry values remain hypotheses until replayed.

---

## 6. Stop, lot, and cash-risk logic

| Point | Revalidation | Status |
|---|---|---|
| Stop beyond sweep ±0.10 ATR | Structural and volatility-normalized | **Test required** |
| Stop range 0.60-1.50 ATR | Rejects tiny cost-dominated and oversized stops | **Test required** |
| `OrderCalcProfit` | Correct MT5 method for symbol/account currency economics | **Approved** |
| Include commission | Required | **Approved** |
| Include stop slippage reserve | Required | **Approved; reserve calibrated from data** |
| Use phase initial balance | Stable, consistent sizing base | **Approved** |
| Round volume down | Required to respect budget | **Approved** |
| Skip unsafe minimum lot | Correct; never raise size for profitable days | **Approved** |
| No raw-lot consistency rule | Correct because stop distance and tick value vary | **Approved** |
| Target solved as net R | Corrected versus assuming gross price R | **Approved** |

The key remaining risk is broker-specific cash arithmetic. It is testable and must be unit-tested before any signal logic is trusted.

---

## 7. Exit engine

| Point | Revalidation | Status |
|---|---|---|
| One position only | Compliant conservative design | **Approved** |
| +1.5R baseline | Positive asymmetry; not proven optimal | **Candidate** |
| +1R confirmation | Now defined as completed M5 close, not wick/tick | **Corrected** |
| 45-minute baseline | Mechanically defined; not proven | **Candidate** |
| +1.75R/+2R challengers | Appropriate coarse alternatives | **Approved for offline comparison** |
| Breakeven move | Now explicitly compared with no-BE; not assumed risk-free | **Corrected** |
| Partial closing | Removed entirely from the initial challenge implementation | **Improved/approved** |
| Session flat | Correct for short-horizon thesis | **Approved design** |
| Red-news flat | Stricter than official rule | **Approved conservative design** |
| Rollover flat | Reduces daily-floor and day-formula risk | **Approved** |
| Friday flat | Reduces gap risk | **Approved** |

The production EA will contain one frozen champion exit policy. It will not switch exits based on recent P&L or profitable-day count.

---

## 8. Risk and drawdown

### Arithmetic check

| Base risk | Cash risk | Phase 1 target | Phase 2 target | Personal 5% DD in R | Two full losses |
|---:|---:|---:|---:|---:|---:|
| 0.25% | $6.25 | 40R | 20R | 20R | -0.50% |
| 0.30% | $7.50 | 33.33R | 16.67R | 16.67R | -0.60% |
| 0.35% | $8.75 | 28.57R | 14.29R | 14.29R | -0.70% |
| 0.40% | $10.00 | 25R | 12.5R | 12.5R | -0.80% |

All arithmetic is correct.

| Risk point | Revalidation | Status |
|---|---|---|
| Maximum candidate 0.40% | Keeps two ordinary stops below 1% internal daily limit | **Approved ceiling** |
| Lower-risk candidates | Appropriate because time is unlimited | **Approved for testing** |
| Select after freezing trades | Prevents risk from contaminating edge selection | **Approved** |
| High-water mark at flat balance | Stable reference | **Approved** |
| Current drawdown uses current equity | Open loss now counted | **Corrected** |
| No monthly reset | Required for genuine path control | **Approved** |
| Drawdown tiers | Full risk below 2%, one predeclared 50% reduction from 2-5%, then emergency shutdown | **Improved; former 25% tier removed** |
| Daily -1% | $25 internal limit versus $125 firm allowance | **Approved** |
| Weekly -2% | $50 internal limit | **Approved** |
| 5% shutdown | Leaves about $125 initial cushion before firm overall floor | **Approved** |
| Gap guarantee | No guarantee is made; stress and reserve are required | **Approved** |

---

## 9. Daily process

| Point | Revalidation | Status |
|---|---|---|
| Any first net-positive exit locks day | Protects earned profit under a standing rule and does not inspect day count | **Improved/approved** |
| First zero/net-loss exit may allow second | Preserves opportunity without permitting a third trade | **Corrected** |
| Projected second stop must fit all limits | Prevents a second trade from violating daily/weekly/firm guard | **Corrected** |
| Second result always locks day | Exact maximum of two sequential trades | **Approved** |
| No day-counter inspection | Prevents manufacturing $12.50 | **Approved** |
| No forced opposite trade | Correct response to one-sided-bet rule | **Approved** |
| No recovery sizing | Required | **Approved** |
| Server rollover reset only after reconciliation | Correct | **Approved** |

A second independent setup after a loss is allowed because it is part of the same standing process; it cannot be taken merely to recover the first trade.

---

## 10. Profitable-day logic

| Point | Revalidation | Status |
|---|---|---|
| Threshold $12.50 | Correct | **Confirmed** |
| Exact midnight formula | Correct | **Confirmed** |
| Any three, not first/consecutive | Correct under current wording | **Confirmed** |
| Smaller positive day | Allowed but not counted | **Confirmed** |
| Open loss can reduce day | Correct consequence of minimum balance/equity | **Confirmed** |
| Dashboard authoritative | Necessary | **Approved** |
| No special volume/exit/trade | Required by prohibited-practice rule | **Approved** |
| No cross-day partial | Required | **Approved** |
| Separate Phase 2 counter | Correct | **Confirmed** |
| Target requires days too | V2 now locks only when both are confirmed | **Corrected** |
| Target reached before days | New `TARGET_PENDING_DAYS` fail-safe remains flat and requires review | **Corrected** |
| Probability gate | Raised from 95% to 99% in day-level replay | **Improved** |

Nominal `0.40% × 1.5R = 0.60%` remains insufficient proof because volume rounding and costs change actual dollars. V2 handles this correctly.

---

## 11. Firm-floor and target guards

| Point | Revalidation | Status |
|---|---|---|
| Persist account/phase/initial balance | Prevents restart/mode errors | **Approved** |
| Configuration checksum | Prevents silent phase changes | **Approved** |
| Daily floor formula | Matches current FAQ | **Confirmed** |
| Static overall floor | Matches current FAQ | **Confirmed** |
| Active floor is stricter floor | Correct | **Approved** |
| Server-time mismatch | Now fails closed and logs UTC offset | **Corrected** |
| Internal floor reserve | Greater of 0.5% initial or 2× configured gap/slippage reserve | **Approved conservative default; calibrate stress component** |
| Phase 1 completion guard | No profit-based size changes; lock only after target plus days | **Improved/approved** |
| Phase 2 completion guard | Same profile as Phase 1; smaller target never increases risk | **Improved/approved** |
| Both target and days required | Explicit | **Corrected** |
| Most restrictive throttle wins | Correct | **Approved** |

The target thresholds are design candidates, not official requirements. They survive only if they improve untouched out-of-sample pass probability.

---

## 12. Collision, request, and operational controls

| Point | Revalidation | Status |
|---|---|---|
| Discard invalid candidates first | Correct | **Approved** |
| Locked instrument priority | Prevents live adaptation | **Approved; learned from training only** |
| Lower cost/R tie break | Sensible deterministic rule | **Approved** |
| First valid completion final tie | Deterministic | **Approved** |
| One order after collision | Required | **Approved** |
| One retry maximum | Prevents request loops | **Improved** |
| No per-tick stop/order modification | Prevents excessive requests | **Improved** |
| 20 non-emergency requests/day cap | Far above expected normal use but far below abusive traffic; it blocks new entries but never suppresses a safety cancellation/close | **Approved internal safeguard; not a firm-published threshold** |
| Restart reconciliation | Required before new risk | **Approved** |
| Direction concentration log | Provides evidence of condition-driven trades without forced alternation | **Improved** |
| Inactivity alerts day 20/25 | Correct and non-trading | **Improved** |

---

## 13. Validation design

| Point | Revalidation | Status |
|---|---|---|
| Bid/ask tick-quality data | Required for limit fills and costs | **Approved** |
| 2019-latest period | Covers multiple regimes, including 2020 and 2022 | **Approved minimum history** |
| Historical news mapping | Required for realistic accepted events | **Approved** |
| Walk-forward plus untouched holdout | Correct anti-overfit structure | **Approved** |
| Maximum four parameter dimensions | Range, ATR, time, and categorical paired risk/target-plus-BE profile | **Corrected** |
| Sweep band fixed | Avoids a fifth tunable dimension | **Approved** |
| Coarse candidates only | Correct | **Approved** |
| 100 OOS fills per combination | Reasonable minimum, not a guarantee | **Approved gate** |
| 300 aggregate OOS fills | Reasonable minimum | **Approved gate** |
| Net EV ≥0.20R | Matches the conditional probability case used in planning | **Approved gate** |
| PF ≥1.30 aggregate | Reasonable cost-aware gate | **Approved** |
| Stress remains positive | Required | **Approved** |
| Day/week block bootstrap | Better than IID shuffle for clustered losses | **Approved** |
| Phase 1 ≥70%, Phase 2 ≥85% | Appropriate minimum design gates | **Approved** |
| Joint ≥60% | Mathematically consistent with phase gates | **Approved minimum** |
| Three-day probability ≥99% | Reduces target-without-days tail | **Improved** |
| Drawdown percentile | Circular “below 5 because paths stop at 5” claim removed | **Corrected** |
| Stop overshoot | 99th-percentile overshoot capped at 1%; no simulated firm-floor touch | **Improved gate** |
| Inactivity replay | Correct | **Approved** |
| Forward demo 30-50 trades | Minimum operational gate; more is better | **Approved** |
| Zero implementation errors | Required | **Approved** |

Statistical gates cannot be confirmed in this pre-coding review. They are the tests the research implementation must perform.

---

## 14. Conditional probability math

For a simple +1.5R/-1R binary model:

`EV = 1.5p - (1-p) = 2.5p - 1`

Break-even win rate is 40%.

Previously reproduced 100,000-path fixed-0.40% illustrative results were:

| Net win rate | Net EV | Phase 1 | Phase 2 | Simplified joint |
|---:|---:|---:|---:|---:|
| 42% | 0.05R | 31.0% | 56.1% | 17.4% |
| 45% | 0.125R | 59.7% | 78.3% | 46.7% |
| 48% | 0.20R | 81.8% | 90.9% | 74.4% |
| 50% | 0.25R | 90.4% | 95.4% | 86.3% |
| 52% | 0.30R | 95.1% | 97.6% | 92.8% |

This table remains mathematically consistent but is **not a forecast**. It excludes actual lot steps, daily grouping, missed limits, changing win probability under alternate targets, correlated losses, target/drawdown throttles, news gaps, execution failures, and exact day qualification. V2 correctly requires a calendar-aware block bootstrap instead.

The provisional 60-70% planning estimate remains reasonable only if net expectancy is near 0.20R and operational errors are near zero. It must be withdrawn if the actual replay fails the stated gates.

---

## 15. Corrections made during this second revalidation

The V2 specification was amended before coding to:

1. Use `America/New_York` for the New York window instead of assuming a fixed London offset.
2. Define range/ATR/spread lookbacks using prior completed comparable sessions only.
3. Define the target-room gate exactly using the opposite reference-range extreme.
4. Add explicit both-currency Forex Factory news mapping and calendar fail-closed behavior.
5. Define +1R confirmation as an M5 close rather than a wick/tick.
6. Add breakeven versus no-breakeven as an offline exit-policy comparison.
7. Measure internal drawdown against current equity so floating losses count.
8. Define daily and weekly starting references.
9. Require projected second-trade loss to fit every safety floor.
10. Clarify daily state behavior after non-target exits.
11. Add `TARGET_PENDING_DAYS` when target and dashboard day count disagree.
12. Raise the profitable-day completion simulation gate from 95% to 99%.
13. Reconcile public UTC+3 wording with live MT5 server-boundary verification.
14. Define an internal firm-floor reserve.
15. Correct the anti-overfit plan to four coherent parameter dimensions.
16. Remove the circular drawdown percentile gate and replace it with explicit shutdown-overshoot stress.
17. Add source ownership, order-request rate limiting, directional evidence logs, and exact inactivity alert thresholds.
18. Pair each risk candidate with a fixed reward target near a nominal 0.6% full-winner outcome.
19. Remove partial closing entirely from the initial challenge implementation.
20. Remove the 25% risk tier; retain one half-risk recovery tier from 2% drawdown until the 5% emergency shutdown.
21. Remove profit-level-based position-size changes near phase targets.
22. Add exact product disambiguation, phase transitions, funded initialization, payout/scale locks, duplicate-position recovery, and missing-stop recovery.

---

## 16. Remaining external/data-dependent items

These are not specification contradictions, but they cannot be truthfully cleared before implementation or account access:

### Must be obtained from live MT5/account documentation

- Exact symbol names and suffixes.
- Tick value behavior and currency conversion.
- Stop/freeze levels and session hours.
- Actual commission and swap.
- Actual server UTC offset/rollover behavior.
- Account agreement version at purchase.

### Written support clarification recommended before live activation

1. Confirm that the intended one-order/one-position account-wide profile satisfies the current broad bulk-trading wording.
2. Confirm that one predeclared 50% risk reduction after 2% strategy drawdown is acceptable under the size-consistency wording; otherwise the profile halts at 2% rather than resizing.
3. Confirm the exact server rollover and funded payout/scaling terms for the purchased $2,500 High Stakes account.

Partial closing and profit-based size reductions have been removed, so they no longer need support interpretation.

### Requires the research implementation and data

- Which instrument/session combinations survive.
- Selected range and ATR bands.
- Selected paired risk/target profile, time stop, and breakeven policy.
- Actual Phase 1, Phase 2, joint, day-count, drawdown, and inactivity probabilities.

---

## 17. Pre-coding conclusion

The specification is now sufficiently precise to build the **research/backtest and compliance framework** without inventing behavior during coding. The implementation must not hard-code candidate values as proven; it must reproduce all declared candidates offline and produce the evidence required for champion selection.

Production/live mode remains locked until:

- Official account-specific details are entered and verified.
- Recommended support clarifications are retained where material.
- One champion configuration passes every statistical and operational gate.
- The user explicitly approves moving from research results to live-challenge configuration.

No strategy can guarantee passage, and no drawdown cap can be guaranteed through gaps, outages, or rejected closes. V2 now states and tests those limitations rather than hiding them.
