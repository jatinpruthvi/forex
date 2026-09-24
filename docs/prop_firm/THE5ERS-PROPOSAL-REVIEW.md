# Review of the Proposed The5ers $2,500 EA Decisions

Review date: 2026-09-03

## Scope and rule hierarchy

This document checks the material decisions in the pasted proposal against The5ers' current public rules and the repository's strategy audit. It is a design review, not legal or profitability assurance. The agreement and dashboard rules attached to the purchased account control if they differ from a public FAQ.

The improved canonical implementation and validation specification is `THE5ERS-CHALLENGE-STRATEGY-V2.md`; it supersedes implementation details in this review wherever they differ.

The most important newer source is The5ers' **Prohibited Trading Practices** FAQ, updated July 28, 2026. Its specific wording is more restrictive than some older/general EA guidance: it defines bulk trading as multiple trades open simultaneously, prohibits coordinated/copy trading with other traders or accounts, and prohibits artificially spreading one idea's profit across days.

Status labels:

- **KEEP** — sound as proposed.
- **MODIFY** — sound idea, but implementation must change.
- **REJECT** — unsafe, mathematically wrong, or contrary to the current published rule.
- **VERIFY** — cannot be treated as fixed until checked in checkout, MT5, the dashboard, or written support.

---

## 1. Direct answer: the three profitable days

Each evaluation phase requires **at least three qualifying profitable days**. They are **not required to be the first three trading days** and **do not need to be consecutive**.

For a $2,500 phase account:

`0.5% × $2,500 = $12.50`

The published calculation is:

`min(midnight balance, midnight equity) - previous-day balance >= $12.50`

Consequences:

- A +$12.50-or-more day qualifies.
- A positive day below $12.50 is allowed, but does not count.
- A losing or flat day is allowed and does not reset the count.
- Unrealized profit does not add to the calculation because the lower of midnight balance and equity is used.
- An open floating loss at midnight can reduce an otherwise qualifying result.
- The count starts again for Phase 2 because it is a separate phase.
- Stay flat at server rollover and confirm the dashboard count rather than relying only on an EA estimate.

Example:

| Trading day | Published-formula result | Qualifies? | Running count |
|---|---:|---|---:|
| 1 | +$15 | Yes | 1 |
| 2 | -$8 | No | 1 |
| 3 | +$10 | No | 1 |
| 4 | +$13 | Yes | 2 |
| 5 | +$20 | Yes | 3 |

The profitable-day rule must not be gamed. Do not hold opposing/correlated positions or close parts of the same idea on different dates to manufacture the count.

---

## 2. Decision-by-decision verdict

| # | Proposed decision | Verdict | Corrected decision and reason |
|---:|---|---|---|
| 1 | Treat the $19 product as the $2,500 New High Stakes plan | **VERIFY** | The live page currently shows that offer, but promotions and checkout terms can change. Confirm product name, price, targets, and account agreement immediately before payment. |
| 2 | Use the New plan's 10% Phase 1 and 5% Phase 2 targets | **KEEP** | These are the currently published New High Stakes targets: $250 and $125 on $2,500. |
| 3 | The first three profitable days must each be 0.5% | **REJECT** | Any three days in each phase may qualify; they need not be first or consecutive. A smaller positive day simply does not count. |
| 4 | A qualifying day is +$12.50 on $2,500 | **KEEP, with formula** | It qualifies only under `min(midnight balance, midnight equity) - previous-day balance`. Do not count floating profit. |
| 5 | Separate Challenge and Funded operating modes | **KEEP, with limits** | Separate target/reporting states are useful, but compliance and strategy behavior must remain consistent. Do not make the funded mode a materially different or larger/smaller betting system. |
| 6 | Use Sleeve A sweep/reclaim only for the first challenge | **KEEP** | This is the simplest repository strategy with defined risk. Keep continuation in shadow mode until separately validated. |
| 7 | Turn on several sleeves in the funded stage immediately | **REJECT for initial rollout** | First prove one sleeve through both phases and one payout. Additional sleeves must pass their own out-of-sample and live gates and still obey the one-position rule. |
| 8 | Risk 0.40% per challenge trade | **MODIFY/conditional** | $10 planned risk is reasonable only as a ceiling after exact small-account tests. Use the same normal risk logic through the first funded payout; drawdown and target throttles may reduce it. Do not increase risk to finish a target. |
| 9 | Use 0.30% funded risk by mode | **MODIFY** | A lower funded risk is prudent in isolation, but a mode-triggered size change can conflict with the new consistency wording. Prefer one documented baseline risk process across stages, with only predeclared drawdown/profit-protection reductions. Seek written clarification before a material stage-based change. |
| 10 | Permit two funded positions if both stops are at breakeven | **REJECT** | The current FAQ broadly defines multiple simultaneously open trades as bulk trading. Breakeven is also not risk-free under gaps, slippage, commission, or rejected closes. Use one open position account-wide. |
| 11 | Enter using two tickets so each has a different target | **REJECT** | That creates simultaneous trades. Use one MT5 position and, if validated, same-day partial closes; the simplest first-challenge baseline is one fixed target. |
| 12 | Keep a basket/open-risk cap | **KEEP, but subordinate** | A cap remains good defense, but the current The5ers default is stricter: one working entry or one open position account-wide. |
| 13 | Treat EURUSD and GBPUSD as correlated USD exposure | **KEEP** | Scan both but select only one live signal. With sequential-only trading, factor exposure cannot overlap. |
| 14 | Exclude USDJPY to remove USD concentration | **REJECT reasoning** | EURUSD, GBPUSD, and XAUUSD are also USD-sensitive. Instrument names do not remove factor correlation. USDJPY can be a separately validated, sequential New York candidate. |
| 15 | Use XAUUSD initially | **REJECT for the $2,500 first pass** | Gold's 0.01 minimum, tick value, spread, and slippage can make small risk imprecise. Keep it disabled until its exact MT5 specifications and stressed fills pass validation. |
| 16 | Restrict the latest five trades from being in the same direction | **REJECT** | Never manufacture an opposite trade or block a valid trade solely to make history look balanced. The strategy must support valid longs and shorts symmetrically and respond to conditions, not enforce cosmetic alternation. |
| 17 | Keep lot size within ±50% of the recent median | **REJECT as primary consistency test** | Raw lots legitimately vary with stop distance and tick value. Monitor planned risk percentage, stop geometry, and aggregate factor exposure instead. Flag unexplained risk changes, not normal ATR sizing. |
| 18 | Allow a setup at 7/8 because the total score passes | **MODIFY** | News, session, spread, cost, data freshness, stop geometry, one-position, and compliance checks are mandatory. A score may rank candidates only after every hard gate passes; initially, do not use score-based sizing. |
| 19 | Apply a 30-minute red-folder news buffer | **KEEP** | It is intentionally stricter than the firm's ±2-minute entry restriction. Cancel working entry orders before the buffer and prevent retries inside it. Map restrictions to both currencies and to USD-sensitive instruments. |
| 20 | Hold existing positions through news because the firm permits it | **MODIFY** | Permission is not a risk recommendation. The first challenge should normally be flat into CPI, NFP, FOMC, and rate decisions under the documented policy. Existing SL/TP behavior must still be broker-side. |
| 21 | Flatten before midnight/rollover | **KEEP** | This avoids raising the next daily-loss snapshot with floating profit and avoids an open loss reducing a profitable-day calculation. Use confirmed MT5 server rollover, not a hard-coded EET hour. |
| 22 | Hard-code EET for resets | **REJECT** | Broker/server offsets and daylight-saving behavior can change. Detect and confirm server rollover using server timestamps and persisted daily snapshots. |
| 23 | Identify mode by comparing `AccountBalance()` with $2,500 at every start | **REJECT** | Profit or loss changes current balance. Persist account ID, plan, phase, initial balance, and configuration checksum once; load and validate them on restart and fail closed on mismatch. |
| 24 | Use fail-closed controls for unknown mode, stale data, bad calendar, or state mismatch | **KEEP** | No new order should be possible when compliance state is uncertain. Existing positions should follow a separately tested emergency policy. |
| 25 | Add visible broker-side stop loss and require source ownership | **KEEP** | Both are explicit public EA requirements. A virtual/stealth stop is not acceptable. |
| 26 | Ban grids, martingale, averaging, HFT, tick scalping, arbitrage, emulators, and rollover-feed exploitation | **KEEP** | These either violate current policy or conflict with the drawdown/survival objective. |
| 27 | Copy identical trades to additional The5ers accounts after passing | **REJECT by default** | The newer FAQ explicitly prohibits trade coordination or copy trading with other traders or accounts. Do not deploy a copier unless The5ers gives a specific written exception for the exact topology. |
| 28 | Split one winner or its partial closures across dates to obtain three profitable days | **REJECT** | The new prohibited-practices wording specifically addresses artificial multi-day profit distribution. Same-day partials may be used only as ordinary tested exit logic. |
| 29 | Stop immediately after exactly $13.75 solely to bank a qualifying day | **MODIFY** | A standing daily profit governor can be legitimate, but do not create a challenge-only daily target designed to manufacture counts. Use the same normal trade/day policy and let qualifying days occur naturally. |
| 30 | Maximum two challenge trades per day | **KEEP** | They must be sequential, with no overlap or working second order. Stop after two full losses and when the internal daily loss governor triggers. |
| 31 | Use a -1.0% internal daily stop | **KEEP** | On $2,500 this is **$25**, not $125. Include closed P&L, floating P&L, costs, and projected slippage. |
| 32 | Use the firm's 10% total loss as the strategy stop | **REJECT** | That is a termination boundary. Stop and revalidate at 5% strategy drawdown, leaving roughly $125 above the $2,250 firm floor at inception. |
| 33 | Guarantee drawdown cannot exceed a configured cap | **REJECT wording** | Stops reduce risk but cannot guarantee a cap through gaps, stale prices, outages, rejected closes, or slippage. Reserve must exist below every hard boundary. |
| 34 | Alert before inactivity expiry | **KEEP** | Current public limits are 30 consecutive days for evaluation and 60 for funded. Never place a low-quality or fake trade merely to reset inactivity. |
| 35 | Validate with tick data, costs, walk-forward/holdout, stress, bootstrap, and forward demo before activation | **KEEP** | The repository has no reproducible trading results. No return, drawdown, pass-probability, or survival claim is established yet. |

---

## 3. Corrected final first-challenge strategy

### 3.1 Strategy identity

Use **TRIAD-R Challenge Profile, Sleeve A only**:

- False session-break sweep followed by M5 reclaim and displacement.
- Long and short rules are exact mirrors.
- No continuation trade when a breakout is accepted; log it in shadow mode only.
- No grid, averaging, martingale, hedge, recovery trade, or correlated second trade.

### 3.2 Instruments and sessions

- London window: scan EURUSD and GBPUSD against the 00:00-07:00 Europe/London range; select at most one.
- New York window: scan USDJPY against the 07:00-13:00 Europe/London range only if no position or working entry remains.
- Candidate entry windows: London 07:00-11:00 and New York 13:30-16:00 Europe/London, converted to MT5 server timestamps with tested daylight-saving handling.
- Maximum two completed sequential trades per day.
- Maximum one working pending entry **or** one open position account-wide.
- XAUUSD, indices, GBPJPY, and every additional sleeve remain disabled.

Server rollover time and strategy session time are different concepts. Daily rule snapshots use confirmed MT5 server rollover. London session definitions use a tested Europe/London conversion.

### 3.3 Mandatory setup gates

Every gate must pass; there is no 7/8 safety override:

1. Range width is within a prevalidated distribution band for that instrument/session.
2. M15 ATR regime is in its prevalidated band.
3. Current spread is no more than 1.5 times the tested minute-of-day reference.
4. Estimated round-trip cost is no more than 0.10R.
5. No relevant Forex Factory red-folder event within 30 minutes.
6. Market data is fresh and latency/slippage state is acceptable.
7. No working order or open position exists account-wide.
8. Stop distance and 0.01 lot-step sizing fit the current risk tier without rounding up.

### 3.4 Entry sequence

For a long; invert every price comparison for a short:

1. Price trades below the reference low by 0.05-0.50 × ATR(M15,14).
2. An M5 candle closes back inside the range within three M5 candles.
3. Reclaim candle wick is at least 60% of its full range.
4. The next M5 displacement candle has a body at least 60% of its range and closes beyond the prior candle midpoint.
5. Place one limit entry at 50% of the displacement body.
6. Attach a visible broker-side stop below the sweep low minus 0.10 × M15 ATR.
7. Reject if entry-to-stop distance is outside 0.60-1.50 × M15 ATR.
8. Cancel the limit after three M5 bars, at the session cutoff, at the news buffer, or if price reaches the theoretical +1R level without filling.
9. Never replace an expired limit with a market chase.

### 3.5 Exit model

Use one position and choose one exit model before validation. The preferred first-challenge baseline is deliberately simple:

- Fixed take-profit at +1.5R.
- Close at market if +1R has not been reached within a validated 30-60-minute time-stop band; 45 minutes is a test candidate, not an assumed truth.
- Hard flat at session end, before server rollover, and before the weekend.
- Never carry partial exposure into another date to influence profitable-day counts.

A one-position, same-day partial-close alternative may be tested, but it must beat the fixed-target model after costs and lot rounding before it replaces the baseline.

### 3.6 Risk and loss controls

- Base planned risk ceiling: 0.40% of phase initial balance = $10.
- Calculate loss with `OrderCalcProfit`/live symbol properties plus commission and a slippage reserve.
- Round volume down to the 0.01 step; skip if minimum volume exceeds the current risk budget.
- One full loss: a second trade is allowed only if it is independently valid.
- Two full losses: stop for the day.
- Internal daily loss stop: 1.0% = $25, inclusive of all P&L and costs.
- Internal weekly stop: 2.0% = $50 from the weekly starting reference.
- Drawdown from highest closed-equity reference: 0-2% at normal tier; 2-3.5% at half tier; 3.5-5% at minimum lot-safe tier; 5% shutdown and investigation.
- Risk may only decrease under documented drawdown/target protection. Never increase risk after wins, losses, or near a target.

### 3.7 Target protection

Phase 1:

- 0% to +8%: normal tier subject to drawdown controls.
- +8% to +9.5%: half tier.
- Above +9.5%: minimum lot-safe tier or wait.
- At $2,750 and all conditions confirmed: cancel/close and stop.

Phase 2:

- 0% to +3.5%: normal tier.
- +3.5% to +4.5%: half tier.
- Above +4.5%: minimum lot-safe tier or wait.
- At $2,625 and all conditions confirmed: cancel/close and stop.

Do not alter normal exits to generate a $12.50 day. Let valid trades create the three days naturally and verify them in the dashboard.

---

## 4. Corrected EA compliance specification

The future EA should contain these independent modules:

1. **Persisted account identity** — account number, broker/server, product, phase, initial balance, configured risk, and build/config checksum.
2. **Rollover state machine** — detects confirmed server-day transitions; stores rollover balance/equity and computes the current firm daily floor.
3. **Firm floor guard** — static floor `phase_initial_balance × 0.90`; daily floor `max(rollover balance, rollover equity) × 0.95`; blocks orders whose stressed projected loss could cross the safety reserve.
4. **Profitable-day tracker** — implements the exact published formula, stores estimates by date, and treats the dashboard as the final count.
5. **One-exposure mutex** — prevents another pending or market entry while any working entry/open position exists.
6. **News gate** — local/verified calendar, currency mapping, 30-minute buffer, pending cancellation, and retry suppression.
7. **Sizing engine** — sizes by planned risk percentage and actual tick economics; never by assumed pip value or raw-lot median.
8. **Execution limiter** — rate-limits sends/modifications/cancellations and logs requested price, fill, spread, latency, rejection, and retry.
9. **Direction-neutral signal engine** — mirrored long/short logic; no hard-coded one-way betting and no forced alternation.
10. **Fail-closed watchdog** — blocks new risk on unknown state, stale quote, calendar failure, identity mismatch, or reconciliation mismatch.
11. **Audit journal** — signal gates, reason for no-trade, risk in dollars/percent, MFE/MAE, exit reason, daily formula estimate, and all rule-state changes.
12. **Inactivity alert** — alerts well before 30/60 days but never sends a synthetic maintenance trade.

No copier module should be built for this The5ers profile.

---

## 5. Go/no-go before coding and activation

The plan is settled enough to define what should be tested, but the trading constants are not proven. Before paying for or activating the EA profile:

1. Reconfirm all account rules in checkout/dashboard and save the applicable agreement.
2. Ask The5ers support in writing if any interpretation remains material, especially the broad one-open-trade wording and stage-to-stage sizing consistency.
3. Backtest the exact one-position, fixed-target, small-account profile with variable spread, commission, slippage, missed limits, 0.01 lot rounding, news, and DST/server-rollover logic.
4. Require at least 300 out-of-sample trades across enabled instrument/session combinations, net expectancy at least 0.20R, and net profit factor at least 1.30.
5. Re-run with 1.5× spread and 2× slippage; the strategy must remain profitable.
6. Use at least 10,000 block-bootstrap paths preserving loss clusters. Target at least 70% Phase 1 pass probability before the personal -5% shutdown and 95th-percentile drawdown below 5% over the expected evaluation duration.
7. Complete 30-50 forward-demo trades with zero rule-engine, sizing, calendar, restart, or order-state errors.
8. If the gates fail, do not compensate with more risk. Change or reject the strategy.

No 10-15% monthly result or 5-10-year survival probability can be claimed from the repository today. The first objective is a compliant, testable pass process—not a promised return.

---

## Official sources

- High Stakes program: https://the5ers.com/high-stakes/
- General rules: https://the5ers.com/faqs/what-are-the-general-rules-for-the-high-stakes-program/
- Profitable-day definition: https://the5ers.com/faqs/how-do-you-define-a-profitable-day-in-the-high-stakes-program/
- Drawdown rule: https://the5ers.com/faqs/what-is-the-drawdown-rule-for-high-stakes/
- Prohibited trading practices: https://the5ers.com/faqs/prohibited-trading-practices/
- News rule: https://the5ers.com/faqs/is-news-trading-allowed-in-the-high-stakes-program2024/
- EA/stop-loss rule: https://the5ers.com/faqs/can-i-use-an-ea-expert-advisor-can-i-set-a-stealth-mode-stop-loss/
- Asset specifications: https://the5ers.com/asset-specifications/
