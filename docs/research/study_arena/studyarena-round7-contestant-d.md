# StudyArena

**Question:** can you please think out of the box and suggest best strategy which reliable for trading and have 15% ROI per month.

**Answered by** Contestant D · Round 7 · 31 Aug 2026

---

## Straight answer

A strategy cannot reliably produce **15% every month with low drawdown**.

\[
(1.15)^{12}-1=435\% \text{ annual return}
\]

To average 15% with 30 trades per month:

\[
\text{Monthly return}\approx
\text{trades}\times\text{risk}\times\text{expectancy}
\]

At \(0.75\%\) risk per trade:

\[
30\times0.75\%\times0.67R=15.1\%
\]

A verified \(0.67R\) expectancy over 30 monthly trades is exceptionally difficult. A more defensible target is:

- **Normal month:** \(+4\%\) to \(+8\%\)
- **Strong trend month:** \(+10\%\) to \(+15\%\)
- **Losing month:** \(-3\%\) to \(-6\%\)
- **Long-run objective:** approximately \(5\%\)–\(8\%\) monthly before costs

The best approach is therefore not a grid or a fixed monthly promise. It is a **regime-switched, session-based strategy with asymmetric exits**.

# Recommended strategy: Regime-Switched Session Portfolio

Use three instruments:

- EURUSD
- GBPUSD
- XAUUSD

But treat EURUSD and GBPUSD as **one correlated position**. Trade whichever provides the cleaner setup—not both.

## Strategy 1: London Compression Breakout

This is the primary return engine.

### Session

Use London local time so daylight-saving changes are handled automatically:

- Build overnight range: **00:00–06:59**
- Entries permitted: **07:00–10:00**
- No new London trades after 10:00

### Market-condition filter

Trade only if all five conditions pass:

1. Overnight range is between \(35\%\) and \(75\%\) of its 20-day median daily range.
2. H1 ADX(14) is between 18 and 35.
3. Price is above H1 200-EMA for a long or below it for a short.
4. H1 20-EMA slope agrees with the direction.
5. No high-impact GBP, EUR or USD announcement within 15 minutes before or after entry.

Skip the setup when the Asian range is extremely narrow. Tiny ranges frequently produce manipulation in both directions rather than clean expansion.

### Long entry

1. Price trades below the overnight low.
2. An M5 candle closes back inside the overnight range.
3. Within the next six M5 candles, price breaks the most recent M5 lower high.
4. The breakout candle’s body must be at least \(60\%\) of its total range.
5. Enter on the first retracement to \(50\%\) of that displacement candle.
6. Cancel the order if it is not filled within three M5 candles.

Reverse every condition for a short.

### Stop

Place the stop:

- Below the sweep low for a long;
- Above the sweep high for a short;
- Add a buffer of \(0.1\times\text{M15 ATR}(14)\).

Reject the trade if the stop is:

- Less than \(0.6\times\) M15 ATR; or
- More than \(1.5\times\) M15 ATR.

That prevents artificially tight stops and oversized stops.

### Exit

Do not close 75% at 1R. That often destroys the value of the runner.

Use:

- Close \(40\%\) at \(+1R\).
- Close \(30\%\) at \(+2R\).
- Trail the remaining \(30\%\).
- Move the stop to breakeven only after price closes beyond \(+1R\), not merely after touching it.
- Trail behind the last confirmed M15 swing, with a minimum distance of \(1.5\times\) M15 ATR.
- Close the runner by 16:30 London time unless the trade has reached \(+2R\).

If every target is reached before the runner trails out at \(4R\):

\[
0.40(1R)+0.30(2R)+0.30(4R)=2.2R
\]

This asymmetric payoff is what creates occasional 10–15% months without raising initial risk.

---

# Strategy 2: New York Continuation

This is permitted only when London has established a genuine trend.

### Session

- Entry window: **08:30–10:30 New York time**
- Maximum one NY trade daily

### Conditions

All must pass:

1. London moved at least \(0.6\times\) the 20-day daily ATR.
2. London did not already move more than \(1.3\times\) daily ATR.
3. H1 structure contains higher highs and higher lows for a long, or the reverse for a short.
4. Price retraces into the M15 20-EMA or London breakout level.
5. The retracement is no deeper than \(61.8\%\) of the London impulse.
6. EURUSD and DXY—or USDJPY and US 10-year yields—are not sending contradictory signals.

### Entry

Enter after an M5 rejection followed by a close beyond the rejection candle.

### Exit

- Close \(50\%\) at \(1R\).
- Close \(25\%\) at \(2R\).
- Trail \(25\%\) behind M15 swings.
- Close everything by 15:30 New York time.

Do not take the NY trade if the London position is still open unless the combined initial risk remains below the portfolio limit.

---

# Strategy 3: Asian mean reversion—but no grid

The safest grid improvement is to **remove the grid**.

A grid earns many small profits and occasionally realizes a disproportionately large loss. Filters reduce that risk but cannot eliminate regime breaks, central-bank surprises, gaps or failed correlations.

Instead, use one defined-risk mean-reversion entry.

### Instruments

- AUDNZD
- EURGBP

Trade only one at a time.

### Conditions

1. H1 ADX(14) \(<16\).
2. H4 ADX is not rising.
3. H4 20-EMA slope over the previous eight candles is less than \(0.20\times\) H4 ATR.
4. Price remains inside the previous five-day range.
5. Price touches the outer 2.2-standard-deviation Bollinger Band.
6. RSI(2) is below 5 for a long or above 95 for a short.
7. No relevant high-impact announcement during the holding window.
8. Entry occurs between 22:00 and 04:00 London time.

### Entry and exit

- Enter after M15 closes back inside the Bollinger Band.
- Stop \(0.8\times\) H1 ATR beyond the extreme.
- Target the H1 20-period mean.
- Require at least \(1.5R\) reward.
- Close by 06:30 London time.
- Never add to the position.

This gives the potential mean-reversion edge without unlimited averaging.

# Pair-selection score

Do not trade every signal. Score each candidate from 0 to 8:

| Condition | Point |
|---|---:|
| Daily/H1 direction agrees | 1 |
| Valid volatility regime | 1 |
| Clean liquidity sweep | 1 |
| Strong displacement candle | 1 |
| Retest occurs within three candles | 1 |
| Reward to structural target \(\ge2R\) | 1 |
| No correlated exposure | 1 |
| No nearby high-impact news | 1 |

Rules:

- **0–6:** no trade
- **7:** risk \(0.50\%\)
- **8:** risk \(0.75\%\)
- Never exceed \(0.75\%\) initial risk because of confidence or a winning streak.

This selection mechanism is more useful than adding another indicator.

# Portfolio risk model

## Base risk

- Normal setup: \(0.50\%\)
- Perfect 8/8 setup: \(0.75\%\)
- Mean-reversion trade: \(0.25\%\)
- Maximum total open risk: \(1.00\%\)
- Maximum daily realized loss: \(1.50\%\)
- Maximum weekly loss: \(3.0\%\)
- Maximum monthly drawdown: \(6.0\%\)

At the limit, stop trading until the next period:

- Daily limit: stop until the next trading day.
- Weekly limit: stop until the next Monday.
- Monthly limit: stop live trading and investigate the strategy.

## Adaptive risk reduction

Use drawdown—not a short 10-trade moving average—to change size:

| Drawdown from equity high | Risk multiplier |
|---|---:|
| \(0\%\)–\(2\%\) | \(1.00\) |
| \(2\%\)–\(4\%\) | \(0.50\) |
| \(4\%\)–\(6\%\) | \(0.25\) |
| More than \(6\%\) | Stop |

Return to full size only after:

1. Twenty additional demo or minimum-size trades;
2. Their rolling expectancy is positive;
3. The strategy produces a new 20-trade equity high.

An equity-curve filter does **not mathematically guarantee** that drawdown will be cut in half. It must be tested like any other rule.

## Correlation limits

Treat these as single risk clusters:

- EURUSD and GBPUSD
- GBPUSD and GBPJPY
- USDJPY and XAUUSD when both express the same USD/rate view
- AUDNZD and simultaneous AUD or NZD positions

If two positions are driven by the same factor, their **combined** risk cannot exceed \(0.75\%\).

# Correct position-size calculation

First calculate cash risk:

\[
\text{Cash risk}
=
\text{equity}\times\text{risk percentage}
\]

Then:

\[
\text{Position size}
=
\frac{\text{cash risk}}
{\text{stop distance in pips}\times\text{pip value per lot}}
\]

Example:

- Equity: \(\$10{,}000\)
- Risk: \(0.50\%\)
- Cash risk: \(\$50\)
- Stop: 20 pips
- EURUSD pip value: approximately \(\$10\) per standard lot

\[
\text{Lots}
=
\frac{50}{20\times10}
=
0.25
\]

Result: **0.25 standard lots**.

ATR helps determine an appropriate stop distance. It does not replace the actual structural invalidation point.

# Return expectations

Suppose the strategy takes 25 trades per month with:

- Win rate: \(48\%\)
- Average winner: \(1.8R\)
- Average loser: \(1R\)

Expected value:

\[
E=(0.48\times1.8)-(0.52\times1)
\]

\[
E=0.864-0.52=0.344R
\]

At \(0.60\%\) average risk:

\[
25\times0.344\times0.60\%=5.16\%
\]

A strong trend month with several \(3R\)–\(5R\) runners might reach 10–15%. But making 15% the mandatory target would encourage overtrading and excessive risk.

A sound operating target is:

| Metric | Target |
|---|---:|
| Average monthly return | \(5\%\)–\(8\%\) |
| Strong-month return | \(10\%\)–\(15\%\) |
| Maximum monthly drawdown | \(6\%\) |
| Profit factor | \(>1.35\) after costs |
| Expectancy | \(>0.25R\) |
| Minimum trades before live use | 200 |
| Out-of-sample trades | At least 60 |

# The genuinely “out-of-the-box” improvement

Optimize **return on your own committed capital**, not the trading account’s percentage return.

The safest version is:

1. Prove the strategy on demo and minimum size.
2. Keep personal trading risk small.
3. If using external funded capital, assess its actual rules, payout history, trailing drawdown, prohibited strategies and counterparty risk.
4. Target \(3\%\)–\(6\%\) on the larger external account rather than forcing 15% on your own account.

For example, a verified \(5\%\) return on a larger capital allocation can produce more cash than 15% on a small account, while requiring substantially less risk. However, a challenge fee should not be treated as the only capital at risk; failed challenges, payout denial and provider failure must be included in ROI calculations.

# Changes I would make to the previous proposal

1. **Remove the multi-leg grid.** Replace it with one defined-risk mean-reversion trade.
2. **Remove the automatic “free-roll” risk increase.** A profit cushion does not improve the next trade’s probability.
3. **Do not promise 25% or 15%.** Let exceptional trends create exceptional months.
4. **Use a 30% runner, not only 25%,** with partial exits at 1R and 2R.
5. **Use drawdown tiers**, but validate them independently.
6. **Trade only one correlated FX setup per session.**
7. **Measure results in \(R\), not pips or win rate.**
8. **Separate each strategy’s statistics.** Disable a sleeve if its rolling 40-trade expectancy drops below zero.

## Final recommendation

The most reliable configuration is:

- **Primary engine:** London compression/sweep breakout;
- **Secondary engine:** NY trend continuation;
- **Diversifier:** single-entry Asian mean reversion;
- **No grid, no martingale, no averaging down;**
- **\(0.50\%\) standard risk and \(0.75\%\) maximum risk;**
- **30% runner for occasional outsized gains;**
- **6% hard monthly drawdown limit.**

This structure can reasonably pursue a **5–8% long-run monthly average with occasional 15% months**. A claim of reliable 15% every month would require either unusually strong verified expectancy or drawdown high enough to threaten the account.
