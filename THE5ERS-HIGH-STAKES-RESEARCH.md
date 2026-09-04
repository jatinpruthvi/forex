# The5ers High Stakes — Program and TRIAD Compatibility Research

Research date: 2026-09-03

Primary page: https://the5ers.com/high-stakes/

This document summarizes the public rules. The purchase agreement and the rules displayed in the trader's dashboard at purchase time control. The5ers states that asset specifications can change, so the EA must read live MT5 symbol properties rather than rely on values copied into this document.

---

## 1. Program summary

High Stakes is a two-step evaluation followed by a funded stage.

| Rule | New High Stakes | Classic High Stakes | Funded stage |
|---|---:|---:|---:|
| Phase 1 target | 10% | 8% | — |
| Phase 2 target | 5% | 5% | — |
| Scaling target | — | — | 10% per level |
| Minimum profitable days | 3 per phase | 3 per phase | 3 for scaling |
| Maximum daily loss | 5% | 5% | 5% |
| Maximum total loss | 10% of initial balance | 10% of initial balance | 10% of level's initial balance |
| Trading period | Unlimited | Unlimited | Unlimited |
| Starting profit split | — | — | 80% to trader |
| Maximum profit split | — | — | Up to 100% |
| Maximum scale | — | — | $500,000 |

Published starting account sizes are $2,500, $5,000, $10,000, $25,000, $50,000, and $100,000. The live High Stakes page currently displays a starting New-plan price of $19 for $2,500. Prices vary by size, variant, and promotion, so the checkout selector should be treated as the current price source. An official refund example lists a $545 cost for a $100,000 account.

Do not confuse this product with The5ers' separate 2026 **Summer 2-Step** $100,000 offer. Its current public page uses 3% daily loss, a $250 payout minimum/cap structure, and a funded 50% consistency rule, while the current High Stakes pages specify 5% daily loss and the High Stakes terms documented here. Product name and the purchased agreement must be verified and persisted; a rule profile may never be selected merely because both products are described as “2-Step.”

### Which variant is better for TRIAD?

- **Classic:** The 8% Phase 1 target is easier and better aligned with TRIAD's current conditional return arithmetic of about 7.9% per month. It normally costs more.
- **New:** The 10% Phase 1 target is harder but the displayed entry prices are lower.
- Because there is no evaluation time limit, the safer decision is normally Classic if the extra fee is acceptable. Do not increase trade risk merely to pass New faster.

---

## 2. Profitable-day rule

A profitable day requires at least 0.5% of the initial account balance in closed-day profit.

The published formula is:

`Minimum(midnight balance, midnight equity) - previous-day balance`

For a $100,000 account, a qualifying day therefore requires at least $500. For the $2,500 account, it requires at least **$12.50**.

The three days can occur anywhere in each phase; they do not have to be the first three trading days or consecutive. A smaller positive day is permitted but does not count, and a losing day does not reset the count.

This matters for a low-risk EA. At 0.24% risk per trade, 0.5% is approximately 2.08R before interaction with other trades. The EA should track qualifying days but must not increase risk, force trades, or spread one idea across dates to create them. Unlimited evaluation time removes the need to rush.

---

## 3. Drawdown rules

### Overall loss

The maximum loss is an absolute/static floor at 10% below the initial balance for that account level.

Example for $100,000:

- Initial balance: $100,000
- Overall termination floor: $90,000 equity

Profits retained in the account increase the dollar cushion above this static floor. Payouts reduce account balance and therefore reduce part of that cushion.

### Daily loss

At 00:00 server time, The5ers takes the higher of the account balance or equity. The daily loss allowance is 5% of that value.

`Daily snapshot = max(previous rollover balance, previous rollover equity)`

`Daily termination floor = 95% × daily snapshot`

The active termination level is effectively the more restrictive of the overall and daily floors.

Example published by The5ers:

- Equity at rollover: $110,000
- New daily loss amount: $5,500
- Daily termination floor: $104,500

This creates an important overnight-runner risk. If a trade has large floating profit at rollover, that high equity becomes the next day's daily reference. A retracement can terminate the account even while it remains well above the original $100,000 balance.

### Recommended internal limits

The firm's 5%/10% limits are termination boundaries, not trading targets. TRIAD should retain much tighter internal limits:

- Internal daily stop: 0.75-1.0%
- Internal weekly stop: 2.0-2.5%
- Strategy shutdown/review: 5.5-6.0%
- Normal maximum open risk: 0.72%
- Absolute technical open-risk cap: 1.0%
- Reserve at least 1% for slippage, gaps, and operational errors

---

## 4. News rule

Holding an existing position through high-impact news is allowed. Opening a new position, including an entry pending order, is prohibited from two minutes before until two minutes after relevant high-impact news.

The5ers uses the Forex Factory red-folder calendar and server time. A prohibited opening is a soft breach:

- Profit from the affected trade is removed and does not count toward the target.
- Loss remains the trader's loss.
- Existing stop-loss or take-profit orders may execute during the window.

TRIAD's existing 30-minute blackout is stricter and should remain. The EA must also:

- Cancel unfilled entry pending orders before the blackout.
- Prevent order retries that could open inside the prohibited window.
- Use server-time conversion and a clock-skew safety margin.
- Apply USD restrictions to XAUUSD and US indices.

---

## 5. EA and automation policy

EAs are allowed, but The5ers prohibits an EA that:

- Copies another person's signals
- Performs tick scalping
- Performs high-frequency trading
- Performs latency arbitrage
- Performs reverse arbitrage
- Performs hedge arbitrage
- Uses emulators

The July 28, 2026 prohibited-practices page additionally prohibits or flags:

- **Bulk trading**, broadly defined as multiple trades open simultaneously
- Trade coordination or copy trading with other traders **or accounts**
- Consistently one-sided bets disconnected from changing market conditions
- Artificially distributing one trade idea across days to manufacture profitable days
- Excessive server requests from opening, modifying, or cancelling orders
- Substantially inconsistent position sizing between evaluation and funded stages
- Concentrated correlated exposure and gambling-style leverage

The stop-loss must be visible in the trading platform; stealth stops are prohibited. The trader must own the EA source code.

### TRIAD compatibility

TRIAD's M5/M15 architecture is much more compatible than the repository's rejected M1/tick-scalping proposals:

- M5/M15 decisions rather than millisecond or tick scalping
- Broker-visible stop-loss on every order
- No latency/arbitrage logic
- No emulator
- Source code owned by the trader
- Moderate holding times and explicit session logic

For The5ers, the default compliance interpretation must be **one working entry or one open position account-wide**. Full multi-position TRIAD and trade copying must remain disabled unless The5ers gives written approval for the exact configuration. The latest specific prohibited-practices wording should take priority over older/general articles that may appear more permissive.

---

## 6. Platform, assets, and holding rules

The High Stakes page currently specifies:

- Platform: MT5 Hedge
- Leverage: 1:100
- Assets: FX, metals, indices, oil, and crypto
- Overnight and weekend holding: allowed
- Index weekend holding: allowed, but high swap can apply

The asset-specification page publishes the following general FX details:

- Contract size: 100,000
- Minimum lot: 0.01
- Lot step: 0.01
- Commission: $4 per standard lot round trip

The5ers tells traders to verify current details in MT5 because specifications can change.

### TRIAD recommendation

Permission to hold is not a reason to hold. For the 8-9% drawdown objective:

- Keep the Friday-flat rule.
- Close ordinary positions before rollover.
- Do not carry an open-profit runner through the daily snapshot unless its retracement-to-floor risk is explicitly calculated.
- Avoid weekend index and oil exposure.
- Read `SYMBOL_TRADE_TICK_VALUE`, contract size, volume step, stop level, and session hours directly from MT5.

---

## 7. Payouts and fee refund

Payouts are available only after reaching the funded stage and generating at least $150 after the profit split.

Published policy:

- The first request is available after 14 funded days; later requests are bi-weekly from the last approved withdrawal.
- A scale-up resets the 14-day payout timer.
- All open trades must be closed before requesting a payout.
- Methods include Rise, bank transfer, cryptocurrency, and non-withdrawable Hub Credit.
- Crypto withdrawals are currently capped at $1,500 per transaction.
- The account must have generated at least $150 **after the profit split** for an eligible High Stakes payout.

The challenge fee is not simply returned in cash immediately:

1. Pass Phase 1: 10% of the initial fee becomes non-withdrawable Hub Credit.
2. Pass Phase 2: another 20% becomes non-withdrawable Hub Credit.
3. Funded stage: 70% is added to funded-account equity and can be withdrawn with the first eligible payout.

The 70% applies only to the portion originally paid with external funds, not the portion paid with Hub Credit. A separate promotion-specific Summer Boost FAQ currently describes payment at the third payout; it must not be applied to High Stakes without the purchased agreement/dashboard confirming it. The current High Stakes-specific payout FAQ says the first eligible payout.

Example published for a $545 fee:

- Phase 1 Hub Credit: $54.50
- Phase 2 Hub Credit: $109.00
- Funded-account refundable amount: $381.50

The current payout-method FAQ reports a 3.5% processing commission for Rise, cryptocurrency, and bank transfer, while Hub Credit has no commission but is non-withdrawable. Verify the exact fee in the dashboard before relying on net-income calculations.

---

## 8. Scaling plan

At the funded stage, every 10% account milestone can advance the account to the next level. Open trades must be closed before advancement.

The current page shows incremental scaling toward $500,000. For the $100,000 route, the published levels are:

`$100K → $125K → $150K → $175K → $200K → $250K → $300K → $350K → $400K → $450K → $500K`

Published split progression:

- 80% at lower levels through $150K
- 85% at $175K and $200K
- 90% at $250K and $300K
- 100% at $350K and above

Published fixed payout:

- $4,000 monthly once account balance reaches $350,000
- $10,000 monthly once account balance reaches $500,000

These fixed amounts are credited to the trading account and can be withdrawn on the next payout cycle.

---

## 9. Account-count rules

The current public account-limit FAQ distinguishes Classic and New.

### Classic

Up to four active High Stakes accounts, subject to size slots:

- One $2.5K
- One $5K
- One of $10K or $25K
- One of $50K or $100K

### New

- Up to three $2.5K accounts
- Up to three $5K accounts
- Up to three $10K accounts
- One $25K
- One of $50K or $100K

Cross-variant restrictions apply to larger sizes. In particular, only one $50K-or-$100K slot can be held across Classic and New combined. Account rules can change and must be confirmed before purchasing a multi-account plan.

Multiple accounts carrying identical exposure would multiply dollar exposure and counterparty concentration, not reduce percentage market drawdown; three accounts at 8% each do not create a 24% return on any account. More importantly, the current prohibited-practices FAQ bans trade coordination or copy trading between accounts, so the account-count allowance must not be interpreted as copier permission.

---

## 10. Inactivity

The current general-rules FAQ states:

- Evaluation account expiration after 30 consecutive days without activity
- Funded account expiration after 60 consecutive days without activity

The EA should send an inactivity alert well before these thresholds. It should not place a fake or low-quality trade merely to keep an account active.

---

## 11. Fit with the repository's return objective

### Evaluation timing under conditional TRIAD assumptions

`TRIAD-SURVIVE.md` currently implies about 7.9% monthly before further drag:

- Classic Phase 1 at 8%: approximately one strong/ordinary month
- New Phase 1 at 10%: approximately 1.3 months at the assumed average
- Phase 2 at 5%: approximately 0.6-1 month

This is only arithmetic using unverified assumptions, not a pass forecast. The unlimited time means the correct response to a slow month is patience, not increased risk.

### Funded cash examples at the initial 80% split

Before payout-method fees and taxes:

| Account size | Gross return | Gross profit | 80% trader share |
|---:|---:|---:|---:|
| $100,000 | 6% | $6,000 | $4,800 |
| $100,000 | 8% | $8,000 | $6,400 |
| $100,000 | 10% | $10,000 | $8,000 |
| $100,000 | 15% | $15,000 | $12,000 |

The profit split means a 10% account return is 8% of notional account size paid to the trader before withdrawal charges and taxes. It remains a 10% trading return, not an 80% personal-capital guarantee.

---

## 12. Required EA changes for High Stakes

Add a dedicated `THE5ERS_HIGH_STAKES` compliance profile with the following modules.

### Rule-state engine

Track separately:

- Account-level initial balance
- Static overall floor: `initial_balance × 0.90`
- Prior rollover balance and equity
- Daily floor: `max(rollover_balance, rollover_equity) × 0.95`
- Internal strategy limits
- Active safety floor: the most restrictive floor plus a configurable safety reserve

### Rollover protection

- Query MT5 server time; do not hard-code London or broker offsets.
- Block new risk before rollover.
- Warn or flatten if floating profit would create a dangerous next-day snapshot.
- Reset daily counters only after a confirmed server rollover.

### News compliance

- Use Forex Factory-compatible red-folder timestamps or a verified mapped calendar.
- Cancel pending entries before the restricted window.
- Block retries/requotes from opening inside the window.
- Log every calendar decision for dispute/audit purposes.

### EA-policy compliance

- M5/M15 only for the initial production strategy.
- Visible broker-side stop-loss.
- No tick-scalping, HFT, arbitrage, emulator, or stealth stop.
- Maximum one working entry or open position account-wide by default.
- No copier or coordinated multi-account execution without written approval.
- Do not split one idea across rollover to manufacture profitable days.
- Rate-limit order sends/modifications and log every request.
- Keep risk percentage consistent; do not police consistency using raw lot size alone because ATR-based stops legitimately change lots.
- Maintain source-code ownership and version records.
- Record requested versus filled price to demonstrate ordinary strategy execution.

### Profitable-day and scaling tracker

- Calculate the exact 0.5% profitable-day formula.
- Count qualifying days independently for each phase/account.
- Never alter trade risk to manufacture a qualifying day.
- Pause and reconcile all positions before requesting a scale-up.

### Payout/scale reconciliation

- Treat every new funded or scaled account as a new configuration event.
- Re-read balance, static floor, symbol specifications, and trading permissions.
- Do not reuse stale drawdown values after payout or scaling.

---

## 13. Overall assessment

High Stakes is structurally compatible with a conservative M5/M15 TRIAD EA:

### Positive fit

- MT5 Hedge supports the intended EA architecture.
- EAs are allowed when source-owned and non-HFT.
- Static 10% overall loss is compatible with TRIAD's intended 5.5-6% shutdown.
- The 5% daily limit is comfortably above TRIAD's proposed 0.75-1.0% internal daily stop.
- The existing 30-minute news blackout is stricter than the firm's two-minute opening restriction.
- Unlimited evaluation time removes pressure to overtrade.
- 80% initial split and scaling to $500K can improve cash income without increasing trade risk.

### Main risks

- Daily drawdown uses the higher of balance/equity at rollover, making overnight floating-profit runners dangerous.
- A rule violation can terminate the account or remove profits while retaining losses.
- EA definitions such as HFT/tick scalping and copier arrangements must be respected precisely.
- Fees, payout charges, firm rules, symbol specifications, and counterparty availability can change.
- Prop-account scaling changes dollar returns, not the underlying strategy's percentage expectancy or drawdown.

### Recommendation

Use Classic High Stakes for the lower 8% first-phase target if its current fee is acceptable; for the user's specific $19/$2,500 objective, use the New-plan challenge without increasing risk to offset its 10% target. Start with one small evaluation solely to verify EA compliance, symbol specifications, spreads, slippage, daily-floor calculations, news handling, and payout workflow. Do not mirror trades between accounts. Do not expand to another account until at least 100 error-free live trades and one successful payout have confirmed the full operating chain; before doing so, obtain written clarification for the exact multi-account use of the strategy.

---

## Official sources

- High Stakes program: https://the5ers.com/high-stakes/
- General High Stakes rules: https://the5ers.com/faqs/what-are-the-general-rules-for-the-high-stakes-program/
- Drawdown calculation: https://the5ers.com/faqs/what-is-the-drawdown-rule-for-high-stakes/
- Profitable-day definition: https://the5ers.com/faqs/how-do-you-define-a-profitable-day-in-the-high-stakes-program/
- News restrictions: https://the5ers.com/faqs/is-news-trading-allowed-in-the-high-stakes-program2024/
- EA rules: https://the5ers.com/faqs/can-i-use-an-ea-expert-advisor-can-i-set-a-stealth-mode-stop-loss/
- Prohibited trading practices: https://the5ers.com/faqs/prohibited-trading-practices/
- Payout/refund policy: https://the5ers.com/faqs/payout-policy-and-hub-credit-in-the-high-stakes-program/
- Growth: https://the5ers.com/faqs/how-does-growth-work-in-the-high-stakes-program/
- Fixed payouts: https://the5ers.com/faqs/how-does-scaling-monthly-fixed-payout-work/
- Account limits: https://the5ers.com/faqs/how-many-high-stakes-accounts-can-i-have/
- Overnight/weekend positions: https://the5ers.com/faqs/do-i-have-to-close-my-positions-overnight/
- Asset specifications: https://the5ers.com/asset-specifications/
- General withdrawal lifecycle: https://the5ers.com/faqs/withdrawals-everything-you-need-to-know/
- Separate Summer Plan (do not confuse with High Stakes): https://the5ers.com/summer-plan/
