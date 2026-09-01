# StudyArena

**Question:** please improve below strategy and give me only one strategy which help me to achieve 15% ROI per month with less than 10% max DD.

**Answered by** Contestant D · Round 8 · 31 Aug 2026

---

## One strategy: London Sweep–Reclaim with an asymmetric runner

This is the strongest single setup in the uploaded suggestions. Remove the grid, DAX gap fade, NY sleeve, carry trades, rebates, and “free-roll” sizing. They add unverified assumptions or correlated risk.

A reliable **15% return on the trading account every month with maximum drawdown below 10% is not a credible target**:

\[
(1.15)^{12}-1=435\%
\]

With 20 trades monthly at \(0.50\%\) risk, the expectancy required is:

\[
E=\frac{15\%}{20\times0.50\%}=1.50R
\]

Sustaining \(1.50R\) per trade after costs is unrealistic. Use this strategy to target **3–6% on the account**, with occasional 10–15% trend months. If you need 15% ROI on your own committed cash, use a larger funded allocation after validation.

# Exact trading rules

### Markets

- EURUSD and GBPUSD only.
- Evaluate both, but take **only one trade per day**.
- If both qualify, select the one with the larger reward to the next H1 structural level.
- Maximum five attempts weekly; no second entry after a loss.

### Times

Use London local time, automatically adjusting for daylight saving:

- Overnight range: **00:00–06:59**
- Entries: **07:00–10:00**
- No new position after 10:00
- Close by 16:30 unless the runner has already reached \(+2R\)
- Absolute closing time: 20:00

## 1. Regime filter

Trade only when every condition passes:

1. Calculate:

\[
\text{Compression ratio}
=
\frac{\text{overnight high}-\text{overnight low}}
{\text{20-day average daily range}}
\]

Require:

\[
0.25\leq\text{compression ratio}\leq0.55
\]

2. H1 ADX(14) must be between 18 and 35.
3. For a long:
   - Price above H1 200-EMA;
   - H1 20-EMA higher than it was five candles ago.
4. Reverse those conditions for a short.
5. No relevant high-impact EUR, GBP, or USD announcement from 30 minutes before entry until 30 minutes afterward.
6. Skip Friday. Trade Monday–Thursday.
7. Skip if the spread exceeds twice its median spread for that time of day.

The normalized compression ratio replaces fixed 35- or 45-pip limits, which become unreliable when volatility changes.

## 2. Long entry

1. Price trades below the overnight low.
2. The sweep must not exceed \(0.30\times\text{M15 ATR}(14)\). A deeper move is more likely a genuine breakout.
3. An M5 candle closes back inside the overnight range within three candles.
4. Within the next six M5 candles, price closes above the latest confirmed M5 lower high.
5. The displacement candle must have:
   - Body at least 60% of its total range;
   - Close in its upper 25%.
6. Place a limit order at the 50% retracement of that candle.
7. Cancel if the order is not filled within three M5 candles.

Reverse all conditions for a short.

## 3. Stop and position size

For a long, place the stop:

\[
\text{sweep low}-0.10\times\text{M15 ATR}
\]

Reject the setup if the total stop distance is outside:

\[
0.60\times\text{M15 ATR}
\leq \text{stop}
\leq
1.40\times\text{M15 ATR}
\]

Risk a fixed **0.50% of current equity**, not a fixed lot size.

\[
\text{Cash risk}=\text{equity}\times0.005
\]

\[
\text{Lots}
=
\frac{\text{cash risk}}
{\text{stop in pips}\times\text{pip value per lot}}
\]

Example:

\[
\text{Equity}=\$10{,}000,\qquad \text{risk}=\$50
\]

\[
\text{Stop}=20\text{ pips},\qquad
\text{pip value}=\$10
\]

\[
\text{Lots}=\frac{50}{20\times10}=0.25
\]

**Result: trade \(0.25\) standard lots.**

## 4. Exit designed for ROI and drawdown

Use one consistent exit ladder:

- Close 40% at \(+1R\).
- Close 30% at \(+2R\).
- Trail the remaining 30%.
- Do not move to breakeven merely because price touches \(1R\).
- Move to breakeven only after an M15 candle closes beyond \(1R\).
- After \(2R\), trail below the latest confirmed M15 swing low for longs or swing high for shorts.
- The trailing stop must remain at least \(1.5\times\text{M15 ATR}\) from current price.
- Close the runner at 20:00 London time.

If the runner reaches \(4R\), the result is:

\[
0.40(1R)+0.30(2R)+0.30(4R)
\]

\[
=0.40R+0.60R+1.20R
\]

\[
=2.20R
\]

At \(0.50\%\) initial risk:

\[
2.20R\times0.50\%=1.10\%
\]

**Result: one successful \(4R\) sequence earns approximately \(1.10\%\).**

# Drawdown governor

Use drawdown from the equity high—not winning streaks or monthly profit—to size risk:

| Current drawdown | Risk per trade |
|---:|---:|
| \(0\%\)–\(2\%\) | \(0.50\%\) |
| \(2\%\)–\(4\%\) | \(0.25\%\) |
| \(4\%\)–\(6\%\) | \(0.125\%\) |
| \(6\%\) or more | Stop live trading |

Additional limits:

- Daily loss limit: \(1.0\%\)
- Weekly loss limit: \(2.0\%\)
- Monthly loss limit: \(6.0\%\)
- Never increase risk after profits.
- Never average down.
- Never remove or widen a stop.
- Resume full risk only after the account recovers to within 1% of its equity high and the latest 20 trades have positive expectancy.

These limits cannot guarantee drawdown below 10% because gaps and slippage exist, but they are designed to stop ordinary strategy drawdown around 6%.

# Realistic return model

Suppose there are 20 trades monthly with:

- Win rate: 48%;
- Average winner: \(1.8R\);
- Average loser: \(1R\).

\[
E=(0.48\times1.8)-(0.52\times1)
\]

\[
E=0.864-0.52
\]

\[
E=0.344R
\]

At \(0.50\%\) risk:

\[
20\times0.344R\times0.50\%=3.44\%
\]

With several large runners, a strong month could produce 8–15%. The defensible expectation is:

| Metric | Target |
|---|---:|
| Long-run monthly account return | 3–6% |
| Strong month | 8–15% |
| Strategy stop level | 6% drawdown |
| Desired profit factor after costs | \(>1.40\) |
| Desired expectancy | \(>0.30R\) |

## How to target 15% ROI without forcing the account to make 15%

Apply the same single strategy to a sufficiently large external allocation. Let:

- \(K\) = your ring-fenced personal capital;
- \(A\) = funded allocation;
- \(r\) = monthly account return;
- \(s\) = your payout percentage;
- \(C\) = monthlyized fees and costs.

Then:

\[
\text{Personal ROI}
=
\frac{A rs-C}{K}
\]

Example:

\[
K=\$10{,}000,\quad A=\$60{,}000,\quad r=4\%,\quad s=80\%,\quad C=\$300
\]

\[
\text{Net income}
=
60{,}000\times0.04\times0.80-300
\]

\[
=\$1{,}920-\$300
\]

\[
=\$1{,}620
\]

\[
\text{Personal ROI}
=
\frac{1{,}620}{10{,}000}=16.2\%
\]

This targets more than 15% on committed personal cash while requiring only 4% from the trading account. It still will not deliver exactly 15% every month; assess it over a rolling 6–12-month period and include failed challenges, denied payouts, and fees.

# Validation before live trading

1. Backtest at least **300 trades**, including spread, commission, and realistic slippage.
2. Keep the final 100 trades completely out of sample.
3. Do not optimize separately for every pair or year.
4. Run at least 10,000 block-bootstrap simulations preserving winning and losing clusters.
5. Use the strategy only if:
   - Out-of-sample expectancy \(>0.30R\);
   - Profit factor \(>1.40\);
   - At least 45% of rolling 20-trade windows are profitable;
   - Simulated 95th-percentile maximum drawdown is below 10%;
   - No single quarter creates more than 40% of total profit.

**Final configuration:** one London sweep–reclaim trade per day, one pair only, \(0.50\%\) base risk, 40/30/30 asymmetric exit, drawdown throttling, and a 6% live-trading stop. This is the best balance of reliability, return potential, and sub-10% drawdown; pursue the 15% target through capital allocation rather than excessive trade risk.
