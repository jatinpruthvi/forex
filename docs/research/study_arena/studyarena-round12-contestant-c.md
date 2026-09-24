# StudyArena

**Question:** now suggest me final trading strategy.

**Answered by** Contestant C · Round 12 · 31 Aug 2026

---

# Final Strategy: **SR-10 Survival Algo**

The objective is **not to force 10–15% every month**. It is to preserve an account for ten years while giving it the opportunity to earn 10–15% in strong months.

With an 8% drawdown ceiling, a realistic long-term expectation is approximately **4–8% per month**, with occasional 10–15% months. Sustaining 10–15% every month would require either unusually high expectancy, excessive risk, or both.

---

## 1. Core strategy

Trade an **M5 liquidity sweep, reclaim and displacement** at the London and New York opens.

Do not use:

- M1 scalping
- Martingale or grid recovery
- Averaging into losses
- Correlated “house-money” stacking
- More risk after a loss
- Multiple copied accounts as supposed drawdown reduction

Copying one trade to three accounts produces the same percentage drawdown on every account. It diversifies broker risk, not market risk.

---

# 2. Instruments and sessions

## London module

**Trading window:** 07:00–10:30 Europe/London time.

**Reference range:** 00:00–06:59 Europe/London.

Trade:

- EURUSD
- GBPUSD

EURUSD and GBPUSD belong to one USD-Europe correlation cluster. The robot may enter only the higher-quality signal if both trigger in the same direction.

## New York module

**Trading window:** 08:30–11:30 America/New_York time.

**Reference range:** 00:00–08:29 America/New_York.

Trade:

- EURUSD
- USDJPY
- XAUUSD

The robot must use timezone libraries so daylight-saving changes are handled automatically.

## Frequency limits

- Maximum one trade per instrument per session
- Maximum three completed trades per day
- Maximum two simultaneous positions
- Maximum aggregate open risk: **0.70%**
- No new entry after the designated session window

This should initially generate approximately **25–50 qualifying trades per month**, depending on filters.

---

# 3. Market-regime filter

A trade is allowed only if all these conditions pass.

## Volatility condition

Calculate the current daily \(ATR(14)\) percentile against the previous 252 trading days.

Trade only when it is between the **20th and 85th percentiles**.

- Below 20th percentile: insufficient movement
- Above 85th percentile: unstable spreads and abnormal event risk

## Reference-range condition

Compare today’s reference range with the median equivalent range from the previous 60 trading days.

Trade only when:

\[
0.60 \times \text{Median Range}
\leq
\text{Current Range}
\leq
1.40 \times \text{Median Range}
\]

## Higher-timeframe direction

For a long trade:

- Last closed H1 candle is above H1 EMA(50)
- EMA(50) is higher than it was five H1 candles earlier

For a short trade:

- Last closed H1 candle is below H1 EMA(50)
- EMA(50) is lower than it was five H1 candles earlier

This means:

- Sweep below the range → long only when H1 is bullish
- Sweep above the range → short only when H1 is bearish

The strategy buys a temporary liquidity event in the direction of the broader trend.

---

# 4. Exact entry conditions

## Long setup

### Step 1: Liquidity sweep

An M5 candle must trade below the reference-range low.

The sweep depth must satisfy:

\[
0.05 \times ATR_{M15}(14)
\leq
\text{Sweep Depth}
\leq
0.50 \times ATR_{M15}(14)
\]

A very small breach is noise. A very deep breach is more likely to be a genuine breakout.

### Step 2: Reclaim

The same candle or one of the next two M5 candles must close back above the reference-range low.

The reclaim candle must have:

- Lower wick at least 50% of its full range
- Close in the upper 40% of its range

### Step 3: Displacement

Within the next two M5 candles, a bullish displacement candle must appear.

It must:

- Close above the reclaim candle’s midpoint
- Have a bullish body at least 60% of its full range
- Have a body at least \(1.2\) times the median M5 body of the previous 20 candles

### Step 4: Entry

Place a buy-limit order at the 50% retracement of the displacement candle’s body:

\[
Entry = BodyLow + 0.50(BodyHigh-BodyLow)
\]

Cancel the order if:

- It remains unfilled for three M5 candles
- Price reaches \(+1R\) before filling it
- The session entry window closes
- A news blackout begins

## Short setup

Apply the exact inverse:

1. Price sweeps above the reference high.
2. It closes back below that high.
3. Reclaim candle has an upper wick of at least 50%.
4. Bearish displacement follows.
5. Sell limit is placed at the displacement body’s midpoint.

---

# 5. Stop-loss rules

For a long:

\[
SL = SweepLow - Buffer
\]

For a short:

\[
SL = SweepHigh + Buffer
\]

Use:

\[
Buffer = \max(0.10 \times ATR_{M15}(14),\ 1.5 \times CurrentSpread)
\]

Reject the trade unless the stop distance is between:

\[
0.50 \times ATR_{M15}(14)
\quad\text{and}\quad
1.50 \times ATR_{M15}(14)
\]

Never widen the stop after entry.

---

# 6. Execution-cost filter

Estimated round-trip cost must include:

- Current spread
- Commission
- Expected entry slippage
- Expected exit slippage

Reject a setup when:

\[
\frac{\text{Estimated Round-Trip Cost}}
{\text{Stop Distance}}
> 0.10
\]

Therefore, trading costs may consume no more than **10% of one unit of risk**.

Also reject the trade if:

- Current spread exceeds twice the median spread for that instrument and time of day
- Price feed is stale
- Bid/ask update latency is abnormal
- Order execution latency exceeds the tested limit
- Broker and independent reference prices materially disagree

---

# 7. Position management

Use three exit components.

| Level | Action |
|---|---|
| \(+1R\) | Close 50% |
| \(+2R\) | Close 30% |
| Runner | Hold remaining 20% |

After an M5 candle closes beyond \(+1R\):

- Move the remaining stop to entry plus estimated costs
- Do not move to breakeven merely because a wick touches \(+1R\)

## Runner exit

Trail the final 20% behind the most recent confirmed M15 swing:

- Long: below the latest confirmed M15 swing low
- Short: above the latest confirmed M15 swing high
- Add a \(0.10 \times ATR_{M15}\) buffer

A swing requires two completed candles on each side, so the algorithm cannot use future information.

## Time stop

Measure maximum favorable excursion after entry.

- If the trade has not reached \(+0.5R\) within six M5 candles, close it.
- Otherwise, if it has not reached \(+1R\) within twelve M5 candles, close it.
- Exit all remaining positions at the session’s hard close unless the runner has already reached \(+2R\).

Session hard closes:

- London module: 12:00 Europe/London
- New York module: 15:30 America/New_York

The exact six- and twelve-candle limits must survive out-of-sample testing. They should not be assumed profitable without evidence.

---

# 8. Risk per trade

## Starting risk

Use **0.25% per trade** during initial live deployment.

After at least 100 live trades, risk may increase to **0.35%** only if:

- Net profit factor is at least 1.30
- Net expectancy is at least \(0.20R\)
- Live execution costs are no more than 20% worse than backtest assumptions
- Drawdown is below 3%
- No material implementation errors occurred

Position size:

\[
\text{Position Size}
=
\frac{\text{Account Equity}\times\text{Risk Percentage}}
{\text{Stop Distance}\times\text{Value Per Point}}
\]

Calculate size using the actual stop distance and instrument contract specification.

## No setup scoring

Do not use “7/8 means 0.5% and 8/8 means 0.75%.” That approach increases risk based on an assumed relationship between a score and future profitability.

Every mandatory condition must pass. Every accepted trade receives the same current risk allocation.

---

# 9. Drawdown control

Measure drawdown from the highest closed daily equity.

| Drawdown | Risk per trade |
|---:|---:|
| \(0\%–2\%\) | 0.35% |
| \(2\%–3.5\%\) | 0.25% |
| \(3.5\%–5\%\) | 0.15% |
| \(5\%–6\%\) | 0.10% |
| Above 6% | Stop new trading |

Starting deployment remains at 0.25%, regardless of the table.

## Loss limits

- Three losing trades: stop for the day
- Daily closed loss of 1.0%: stop for the day
- Weekly closed loss of 2.0%: stop until the next week
- Monthly closed loss of 4.0%: stop until formal review
- Drawdown above 6%: disable live entries and investigate
- Never automatically restart after a drawdown shutdown

The extra space between the 6% shutdown and the 8% maximum is reserved for:

- Slippage
- Price gaps
- Currency conversion
- Open-position fluctuations
- Broker errors

A stop loss cannot guarantee an 8% maximum because markets can gap through stops.

---

# 10. News and tail-risk protection

No new entries:

- 30 minutes before high-impact scheduled news
- Until 15 minutes after ordinary high-impact releases
- Until 30 minutes after FOMC, ECB, BoE and BoJ rate decisions
- Until spreads and prices return to normal

For a currency pair, apply restrictions when either currency has affected news.

For gold, apply all major USD restrictions.

Remain flat during:

- NFP
- US CPI
- Central-bank rate decisions
- Fed chair press conferences
- Unexpected market closures
- Broker maintenance
- The final two hours before the weekly FX close

Do not hold positions over weekends.

---

# 11. Correlation management

Use these initial risk clusters:

1. EURUSD and GBPUSD
2. USDJPY
3. XAUUSD

If EURUSD and GBPUSD give simultaneous same-USD-direction signals:

- Rank them using the lower cost-to-stop ratio
- Select only one
- Do not trade both at full risk

Total simultaneous risk across all positions cannot exceed 0.70%.

Correlation should also be recalculated from rolling 60-day H1 returns. Instruments with absolute correlation above 0.70 belong temporarily to the same risk cluster.

---

# 12. Edge-decay controls

Monitor each instrument-session combination separately, for example:

- EURUSD–London
- GBPUSD–London
- EURUSD–New York
- USDJPY–New York
- XAUUSD–New York

Pause an individual sleeve if any condition occurs:

- Rolling 40-trade net expectancy falls below \(0R\)
- Rolling 40-trade profit factor falls below 1.0
- Actual costs exceed modeled costs by more than 25%
- Entry slippage exceeds the 95th percentile assumption repeatedly
- Live trade distribution differs materially from historical testing

Review rather than immediately optimizing parameters. Changing parameters after every weak period causes curve-fitting.

---

# 13. Validation before live deployment

## Data requirements

Test at least January 2012 through the latest available 2026 data using:

- Bid and ask tick data
- Variable historical spreads
- Commission
- Conservative slippage
- Swap when applicable
- Real session and daylight-saving times
- Historical news timestamps
- No future-looking swing calculations

The test period should include:

- 2015 SNB shock
- 2016 Brexit
- 2020 COVID volatility
- 2022 inflation and rate shocks
- Low- and high-volatility regimes

## Walk-forward process

Use rolling windows such as:

- 24 months development
- Next 6 months untouched out-of-sample
- Roll forward by 6 months
- Combine all out-of-sample results

Do not optimize primarily on total return. Prefer broad parameter stability.

## Minimum acceptance gates

Deploy a sleeve only if its combined out-of-sample results show:

- At least 300 trades
- Net profit factor at least 1.30
- Net expectancy at least \(0.20R\)
- At least 65% of out-of-sample windows profitable
- No single year generating more than 35% of total profit
- Profitable results after costs are increased by 25%
- Similar performance across neighboring parameter values

Then perform at least 10,000 block-bootstrap Monte Carlo simulations. Select final risk so the simulated ten-year drawdown satisfies:

\[
99^{th}\text{-percentile drawdown} \leq 8\%
\]

If 0.35% risk fails that test, lower the risk. Do not change the test to justify the desired return.

---

# 14. Deployment plan

## Stage 1: Shadow mode

- Run live without sending orders for four weeks
- Compare robot signals with manually reconstructed signals
- Verify timestamps, spreads, news handling and position sizing

## Stage 2: Minimum live size

- Trade 0.10% risk for 30 trades
- Confirm real fills and order-management behavior

## Stage 3: Normal initial risk

- Increase to 0.25% for the next 70 trades
- No scaling before completing 100 live trades

## Stage 4: Validated risk

Increase to 0.35% only when all live-performance conditions pass.

Do not add another broker or account until the first implementation has at least 100 error-free live trades.

---

# 15. Return expectations and required mathematics

Suppose the strategy produces:

- 40 trades per month
- Net expectancy of \(0.25R\)
- Risk of 0.35% per trade

Then:

\[
40 \times 0.25R \times 0.35\% = 3.5\%
\]

At an exceptional net expectancy of \(0.40R\):

\[
40 \times 0.40R \times 0.35\% = 5.6\%
\]

To make 10% with 40 trades and \(0.25R\) expectancy, required risk is:

\[
\text{Risk}
=
\frac{10\%}{40\times0.25}
=
1\%
\]

Risking 1% per trade is inconsistent with a robust 7–8% maximum-drawdown target over ten years.

Therefore, the safe route toward higher returns is:

1. Prove this strategy first.
2. Add genuinely independent, separately validated strategies.
3. Allocate a shared risk budget across them.
4. Do not simply increase leverage or copy correlated trades.

---

# Final operating specification

- **Setup:** M5 sweep, reclaim and displacement
- **Markets:** EURUSD, GBPUSD, USDJPY and XAUUSD
- **Sessions:** London and New York only
- **Initial risk:** 0.25%
- **Maximum validated risk:** 0.35%
- **Maximum total open risk:** 0.70%
- **Daily stop:** 1.0% or three losses
- **Weekly stop:** 2.0%
- **Monthly stop:** 4.0%
- **Strategy shutdown:** 6% drawdown
- **Absolute design ceiling:** 8%, not guaranteed against gaps
- **No martingale, grid, averaging down or correlated stacking**
- **Expected sustainable return:** approximately 4–8% monthly if the tested edge is real
- **Possible strong month:** 10–15%
- **Priority:** ten-year survival over forcing a monthly target

This is the version I would develop: one simple edge, conservative risk, realistic execution modeling, automatic shutdowns and continuous edge-decay monitoring.
