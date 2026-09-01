# StudyArena

**Question:** suppose you are 20 years forex experience trader then what improvement you do to achieve 10% to 15% ROI per month with maximum draw down up to 7% - 8% with 10 years survival of account

**Answered by** Contestant A · Round 11 · 31 Aug 2026

---

## First, correct the target

A professional would **not promise** 10–15% every month with only 7–8% maximum drawdown for ten years.

\[
1.10^{120}\approx 92{,}709
\]

At 10% monthly compounding, \( \$10{,}000 \) theoretically becomes about \( \$927\text{ million} \) in ten years. That illustrates how aggressive and statistically unlikely the target is.

A survivable objective is:

- **Average:** 4–8% per month  
- **Strong months:** 10–15%
- **Weak months:** 0–3%
- **Occasional losing month:** \(-2\%\) to \(-5\%\)
- **Strategy shutdown level:** 6%
- **Absolute design limit:** 8%, although gaps and execution failures mean it cannot be guaranteed

Also, copying the same trade onto two accounts does **not** turn an 8% ROI into 16% ROI. Each account still earns 8%; only the dollar profit doubles because the capital doubles.

# Final Strategy: Adaptive Session Sweep-Reclaim

This remains **one strategy**, but uses an M5 market structure with M1 execution. I would not use pure M1 signals because spread, slippage, feed differences and noise usually destroy their apparent backtest edge.

## 1. Markets and trading windows

Trade only:

- EURUSD
- GBPUSD
- USDJPY
- XAUUSD

Trading windows:

- London: first 120 minutes after the London open
- New York: first 120 minutes after the New York open
- One trade per instrument per session
- Maximum three completed trades per session
- No Asian-session trading unless independent testing proves it profitable

The robot must use `Europe/London` and `America/New_York` time zones so daylight-saving changes are handled automatically.

## 2. Reference liquidity range

For London, use the high and low formed from 00:00 until the London open.

For New York, use the high and low formed from the London open until the New York open.

A range is eligible only when its width is between the **30th and 80th percentile** of the previous 60 comparable sessions. Percentiles are more robust than using an arbitrary percentage of a 20-day median.

Skip the session if:

- The range is exceptionally narrow or wide.
- Current spread is more than twice its 20-session median.
- A high-impact scheduled announcement is imminent.
- The instrument has already moved more than 80% of its 20-day daily ATR before the setup.

## 3. Direction and regime filter

### Long setup

A sweep below the range may be traded only when:

- H1 EMA(50) slope over the previous five completed candles is non-negative.
- Price is not more than \(0.75\times\text{ATR}_{H1}\) below the EMA.
- H1 ADX(14) is below 30, or the H1 trend is upward.

Reverse these conditions for shorts.

This avoids fading an exceptionally strong trend while still permitting ordinary session-open reversals.

## 4. Sweep definition

For a long:

1. Price trades below the reference low by:

\[
0.10\text{ to }0.35\times\text{ATR}_{M5}(14)
\]

2. Price reclaims the reference low within three completed M1 candles.
3. The reclaim candle closes in its upper 40%.
4. The reclaim candle’s range is at least the 60th percentile of the previous 30 M1 candles.
5. Price then breaks the most recent confirmed M1 lower high.

Reverse the rules for a short.

This replaces fixed requirements such as “one pip beyond the level,” which are inappropriate across different instruments and volatility regimes.

### Optional institutional-data confirmation

If genuine centralized futures data is available, use:

- 6E for EURUSD
- 6B for GBPUSD
- 6J for USDJPY
- GC for gold

Require futures volume or delta reversal during the reclaim. Do **not** describe ordinary broker tick volume as genuine global FX volume delta; spot FX is decentralized.

The strategy must remain profitable without this filter before it is added.

## 5. Entry and stop

After confirmation:

- Place a limit order between the 38% and 62% retracement of the displacement candle.
- Cancel the order after five M1 candles.
- Do not chase with a market order.

For a long:

\[
SL=\text{sweep low}-\max\left(2\times\text{spread},\;0.08\times\text{ATR}_{M5}\right)
\]

Reverse for a short.

Reject the trade when:

- Stop distance is below \(0.30\times\text{ATR}_{M5}\).
- Stop distance exceeds \(1.00\times\text{ATR}_{M5}\).
- Spread plus estimated commission and slippage exceeds \(0.10R\).
- The next meaningful liquidity target provides less than \(2R\) of available space.

Position size:

\[
\text{Position size}
=
\frac{\text{equity}\times\text{risk fraction}}
{\text{stop distance}\times\text{value per point}}
\]

## 6. Exit model

Use one fixed exit model rather than “house-money stacking.”

1. Close 50% at \(+1R\).
2. Move the remaining stop to entry only after an M1 candle closes beyond \(+1R\).
3. Close the remaining 50% at \(+2.5R\), or trail behind confirmed M5 swing points after price reaches \(+1.5R\).
4. If maximum favorable excursion is below \(+0.35R\) after 12 minutes, close at market.
5. Hard-close after 30 minutes if \(+1R\) has not been reached.
6. Close all positions before the relevant session ends.

If both targets are reached, the gross result is:

\[
0.50(1R)+0.50(2.5R)=1.75R
\]

The 12- and 30-minute exits are hypotheses, not proven advantages. Backtest them against 10, 20, 30 and 45 minutes and select a **stable parameter region**, not merely the best individual result.

## 7. Portfolio risk engine

### Initial live risk

- Base risk: **0.20% per trade**
- Increase to 0.25% only after 200 live trades meet validation criteria
- Maximum total simultaneous open risk: 0.40%
- Maximum risk within one correlated cluster: 0.25%

Treat these as correlated:

- EURUSD and GBPUSD
- USDJPY and dollar-driven EURUSD exposure
- Gold and broad short-USD positions during major US events

### Drawdown throttle

Drawdown is measured from the highest closed-equity value:

| Drawdown | Risk per trade |
|---|---:|
| \(0\%-2\%\) | 0.20–0.25% |
| \(2\%-3.5\%\) | 0.12% |
| \(3.5\%-5\%\) | 0.06% |
| \(5\%-6\%\) | No new trades; investigation |
| Above 6% | Strategy disabled and revalidated |

Additional limits:

- Daily closed and open loss: \(-0.75\%\)
- Weekly loss: \(-1.75\%\)
- Five losses on the same instrument/session combination: disable that combination
- Rolling 50-trade expectancy below zero: disable new trading
- Live trading costs above 1.5 times the tested level: disable the affected instrument

Do not automatically restart at the beginning of a new month. A regime problem does not disappear because the calendar changed.

## 8. Return mathematics

Assume the verified live results are:

- 100 trades per month
- 48% winning trades
- Average winner \(=1.55R\), after partial exits
- Average loss \(=0.85R\), because time stops reduce some losses

Then:

\[
E=(0.48\times1.55R)-(0.52\times0.85R)
\]

\[
E=0.744R-0.442R=0.302R
\]

At 0.25% risk:

\[
100\times0.302R\times0.25\%=7.55\%
\]

To target 10% using the same performance:

\[
r=\frac{10\%}{100\times0.302}=0.331\%
\]

For 15%:

\[
r=\frac{15\%}{100\times0.302}=0.497\%
\]

Risking approximately 0.50% per trade may produce 15% mathematically, but it is unlikely to remain compatible with a 7–8% ten-year drawdown limit. Therefore, **risk must be determined by drawdown testing, not by the desired ROI**.

## 9. Ten-year survival validation

Before live deployment:

### Data

- Use tick data covering at least 2016–2026.
- Include variable spreads, commissions, swaps and slippage.
- Include Brexit, COVID, the 2022 rate shock and high-volatility news periods.
- Use bid and ask prices, not midpoint candles.

### Walk-forward testing

- Train: 24 months
- Validate: next 6 months
- Roll forward by 6 months
- Keep the final 18 months completely untouched as a final test

An instrument/session combination survives only if:

- Out-of-sample profit factor \(\geq1.25\)
- Post-cost expectancy \(\geq0.15R\)
- At least 70% of out-of-sample windows are profitable
- No single year generates more than 35% of total profit
- Results remain profitable when parameters move by \(\pm20\%\)

### Stress testing

Run at least 10,000 block-bootstrap simulations that preserve losing-trade clustering. Stress each simulation with:

- Spreads multiplied by 1.5
- Slippage multiplied by 2
- 10% of profitable limit entries missed
- Occasional stop fills worse by \(0.25R\)
- Random platform interruptions

Set risk so the **99th-percentile simulated drawdown is at most 6%**. The remaining 2% is an operational safety reserve. If the risk required to make 10% monthly violates that test, reduce the return target—not the safety standard.

## 10. Operational survival rules

The robot also needs:

- Broker-side emergency stop-losses
- A separate watchdog process
- Automatic position reconciliation with the broker
- Trading disabled when market data becomes stale
- Flattening after rejected or inconsistent orders
- Primary and backup VPS in the broker’s region
- Daily database and configuration backups
- Alerts for spread, latency, rejected orders and equity limits
- No martingale, grid, averaging down or correlated “free-margin” stacks

Withdraw at least 50% of profits above the account’s risk-capital high-water mark each quarter. Do not continually compound at the maximum risk rate for ten years.

## Final professional target

I would build and validate this strategy for:

- **4–8% average monthly return**
- **10–15% during favorable months**
- **5–6% automated shutdown drawdown**
- **7–8% emergency design ceiling**
- **0.20–0.25% normal risk per trade**

Only raise risk if ten-year tick testing, walk-forward results, live execution and 99th-percentile simulations all support it. That is the realistic improvement required for account survival; claiming a guaranteed 10–15% every month would undermine the entire risk objective.
