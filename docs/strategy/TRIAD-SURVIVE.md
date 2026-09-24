# TRIAD-SURVIVE

Locked final strategy for an MT5 Expert Advisor.

One robot. Three regime sleeves. Shared risk governor.

This document is the build spec. Hand it to the developer. Nothing else is needed.

---

## THE HONEST TARGET

10-15% every month, 8-9% maximum drawdown, and 5-10 year account life cannot all be guaranteed together.

Path drawdown for one edge over about 1,000 trades is approximately 15R. At 0.50% risk that is already 7.5% — the entire drawdown budget on a single sleeve.

Honest operating band:

- Average month: 9-12%
- Strong month: 13-15%
- Weak month: -3% to -5%, expect 1-2 per year
- Shutdown: 6% from closed-equity high
- Design cap: 8%. One percent reserved for gaps and operational risk
- 5-year survival: plausible if profits are withdrawn and sleeves are replaced
- 10-year survival: approximately 35-45% even if every rule below is followed

Do not compound the full account. Fix a capital base. Withdraw 70% of profit above that base every month.

---

## 1. ARCHITECTURE

Returns add linearly. Risk adds closer to the square root when sleeves are genuinely decorrelated. That is the only honest path near 10% inside an 8% drawdown budget.

| Sleeve | Market regime | Session (Europe/London) | Instruments | Edge |
|---|---|---|---|---|
| A | Normal volatility | London 07:00-11:00, NY 13:30-16:00 | EURUSD, GBPUSD, USDJPY, XAUUSD | Liquidity sweep and reclaim at session opens |
| B | Trending / high volatility | London 07:00-15:30, NY 13:30-19:30 | XAUUSD, GBPJPY. GER40 and US30 only if the broker lists them and they pass the six gates | Breakout that holds, entered on first pullback |
| C | Dead / low volatility | 00:00-06:30, hard flat 06:30 | AUDNZD, EURGBP, EURCHF | Fade 2-standard-deviation Bollinger touches back to the mean. Single entry. No grid |

Sleeve A profits when volatility is normal. Sleeve B profits when volatility is expanding — the days Sleeve A gets chopped. Sleeve C profits when volatility is dead and the other two have no setups.

Correlation enforcement: measure daily P&L correlation between sleeves on a rolling 60-day window. If any two sleeves drift above 0.50, halve the smaller one. Target correlation is 0.30 or below.

EURUSD and GBPUSD in the same direction count as one position.

| Limit | Value |
|---|---|
| Max concurrent open positions | 4 total across all sleeves |
| Max concurrent per sleeve | 2 |
| Max total open risk at any moment | 1.0% |
| Max risk per correlated group | 0.24% |

Correlation groups (one position at a time):

- USD group: EURUSD, GBPUSD, AUDUSD
- JPY group: USDJPY, GBPJPY, EURJPY
- Commodity group: AUDUSD, USDCAD, XAUUSD during major US events
- European cross group: EURGBP, EURCHF

---

## 2. SLEEVE A: SESSION-OPEN SWEEP AND RECLAIM

Primary edge. Highest trade count.

### 2.1 Windows

| Session | Window (Europe/London) | Instruments | Reference range |
|---|---|---|---|
| London | 07:00-11:00 | EURUSD, GBPUSD, XAUUSD | Asian session 00:00-07:00 high and low |
| New York | 13:30-16:00 | XAUUSD, USDJPY | London session 07:00-13:00 high and low |

Hard exclusions:

- No entries 21:30-23:30 London (thin liquidity, spread blowouts)
- Flat every Friday 20:00 London
- No entries within 30 minutes before or after red-folder news (CPI, NFP, FOMC, rate decisions)
- Hard flatten all positions 15 minutes before and 10 minutes after CPI, NFP, FOMC

### 2.2 Eight-point score

Fire only at 7/8. No override.

| # | Filter | Pass condition |
|---|---|---|
| 1 | Range quality | Range width = 35-75% of its 20-day median width for that instrument |
| 2 | Higher-timeframe bias | Price on correct side of H1 50-EMA, EMA slope agrees with trade direction |
| 3 | Sweep | Price trades beyond the range extreme by 0.05-0.50 x ATR(M15, 14), then closes back inside within 3 M5 candles |
| 4 | Rejection | Sweep candle wick at least 60% of its total range |
| 5 | Displacement | Next M5 candle after reclaim has body at least 60% of its total range and closes beyond the prior candle midpoint |
| 6 | Spread gate | Live spread at most 1.5x the 20-day average spread for that symbol |
| 7 | Cost gate | Stop distance at least 10x round-trip cost |
| 8 | Clean book | No red-folder news within 30 minutes, no correlated position already open |

Scoring:

- 8/8: full tier risk (0.24%)
- 7/8: half tier risk (0.12%)
- 6 or below: no trade

Tick volume is not a hard gate. MetaTrader tick volume is broker-local. It may be used as an optional soft score point only. The strategy must still fire without it.

A breach deeper than 0.50 x ATR(M15, 14) is treated as a genuine breakout, not a liquidity grab. Skip.

### 2.3 Entry order

- Place a limit order at the 50% retracement of the displacement candle body
- Cancel if unfilled after 3 M5 candles (15 minutes)
- Cancel if price reaches +1R before the limit fills
- Cancel if the session entry window closes
- Cancel if a news blackout begins
- Never chase with a market order

### 2.4 Stop loss

- Long: sweep low minus 0.10 x ATR(M15, 14)
- Short: sweep high plus 0.10 x ATR(M15, 14)
- Reject the trade if stop distance is below 0.60 x ATR(M15) or above 1.50 x ATR(M15)

### 2.5 Exit ladder

All exits are mechanical. No discretion.

| Trigger | Action |
|---|---|
| +1R reached, confirmed by M5 candle close (not wick) | EURUSD, GBPUSD, USDJPY: close 40%, move stop to breakeven. XAUUSD only: close 60%, move stop to breakeven |
| +2R reached | EURUSD, GBPUSD, USDJPY: close 30%. XAUUSD only: close 20% |
| Runner | EURUSD, GBPUSD, USDJPY remaining 30%: trail at High minus 2.5 x ATR(H1, 14), recalculated hourly. XAUUSD remaining 20%: trail behind H4 swing points |
| 45 minutes elapsed without reaching +1R | Close at market |
| Session close | Flat all positions unless runner is at least +2R with stop already at breakeven |
| Friday 20:00 London | Flat everything |

The 45-minute time stop is the single most valuable rule in this strategy. Sweeps displace immediately. If price is still hovering near entry after 45 minutes, the thesis is dead.

### 2.6 Position sizing

Position size = (Account Equity x Risk Fraction) / (Stop Distance in pips x Pip Value)

Risk fraction is 0.24% at full tier, 0.12% at half tier, then adjusted by the drawdown throttle in Section 5.

---

## 3. SLEEVE B: VOLATILITY-EXPANSION CONTINUATION

This sleeve is designed to profit on the trending days where Sleeve A gets chopped.

If GER40 or US30 do not exist on the account, or fail the cost gate, Sleeve B is XAUUSD and GBPJPY only. Do not invent substitutes.

### 3.1 Windows

| Session | Window (Europe/London) | Instruments |
|---|---|---|
| London | 07:00-15:30 | XAUUSD, GBPJPY, GER40 if listed |
| New York | 13:30-19:30 | XAUUSD, GBPJPY, US30 if listed |

### 3.2 Entry (all must pass)

1. Daily ATR is in the 60th to 90th percentile of its 20-day range
2. An M15 candle closes beyond the 4-hour range high (longs) or low (shorts) with a body at least 70% of its total range
3. Tick volume at least 1.3x the 20-candle average. If broker volume is unusable, drop this point and require 4/4 on the remaining filters
4. Price pulls back to the breakout level within the next 6 M15 candles
5. Enter on a limit order at the breakout level
6. Stop loss: 1.20 x ATR(M15, 14) beyond the breakout candle extreme

### 3.3 Exit

| Trigger | Action |
|---|---|
| +1.5R | Close 50%, move stop to breakeven |
| Remaining 50% | Chandelier trail: highest high since entry minus 3.0 x ATR(H1, 14), recalculated hourly |
| No time stop | This sleeve is supposed to be slow |
| Session close | Flat unless position is at least +2R with stop at breakeven |
| Friday 20:00 London | Flat everything |

### 3.4 Scoring

Minimum 4/5 to trade.

| # | Filter | Pass condition |
|---|---|---|
| 1 | ATR percentile | Daily ATR in 60th-90th percentile of 20-day range |
| 2 | Breakout body | Body at least 70% of candle range |
| 3 | Volume | Tick volume at least 1.3x average, or omitted if unusable |
| 4 | Spread | At most 1.5x average |
| 5 | Clean book | No red-folder news within 30 minutes, no correlated position open |

Score 5/5: 0.24%. Score 4/5: 0.12%. Below 4: no trade.

---

## 4. SLEEVE C: ASIAN MEAN REVERSION

Low-beta ballast. One defined-risk fade. Never a grid.

### 4.1 Window

00:00-06:30 Europe/London on AUDNZD, EURGBP, EURCHF only.

Hard flat 06:30. One instrument at a time. Never add to a position.

### 4.2 Entry (all must pass)

1. H1 ADX(14) below 16
2. Price touches the upper or lower 2.0-standard-deviation Bollinger Band (20-period)
3. Touch candle wick at least 50% of its range
4. RSI(14) on M15 above 70 (shorts) or below 30 (longs)
5. Enter on a limit order at the Bollinger Band level
6. Stop loss: 1.0 x ATR(M15, 14) beyond the touch candle extreme
7. Target: the 20-period moving average (middle Bollinger Band)

### 4.3 Exit

| Trigger | Action |
|---|---|
| Price reaches 20-period MA | Close 100% at market |
| 06:30 London | Hard flat everything |
| Stop hit | Close at market |
| Friday 20:00 London | Flat everything |

No partial exits. No trailing. No averaging.

### 4.4 Scoring

Minimum 4/5 to trade.

| # | Filter | Pass condition |
|---|---|---|
| 1 | Regime | H1 ADX(14) below 16 |
| 2 | Bollinger touch | Price touches 2.0 sigma band |
| 3 | Rejection wick | Touch candle wick at least 50% of range |
| 4 | RSI extreme | M15 RSI above 70 or below 30 |
| 5 | Spread | At most 1.5x average |

Score 5/5: 0.24%. Score 4/5: 0.12%. Below 4: no trade.

---

## 5. RISK ENGINE

This section determines whether the account survives. The entry signal makes the money. The risk engine keeps the account alive long enough to collect it.

### 5.1 Per-trade risk

- Base risk: 0.24% per trade at full tier (8/8 or 5/5)
- Half tier: 0.12% per trade (7/8 or 4/5)
- Never raise risk after profits
- No free-roll
- No free-margin stack
- No martingale
- No grid
- No averaging into losers

### 5.2 Drawdown throttle

Drawdown is measured from the highest closed-equity value. Checked before every new order. Floating drawdown must not resize live positions.

| Drawdown from equity high | Risk per trade |
|---|---|
| 0-2% | 0.24% (full tier) |
| 2-4% | 0.12% (half tier) |
| 4-6% | 0.06% (quarter tier) |
| Above 6% | Shutdown. No new trades until next month. Mandatory review |

### 5.3 Hard kill switches

| Trigger | Action |
|---|---|
| Daily loss reaches -1.0% | Stop trading for the rest of the day |
| Weekly loss reaches -2.5% | Stop trading for the rest of the week |
| Monthly drawdown reaches -6% | Stop trading until next month. Mandatory review |
| 5 consecutive losses on the same instrument and session | Disable that instrument-session combination for 24 hours |
| Rolling 60-trade expectancy of any sleeve drops below 0.08R | That sleeve auto-pauses. Does not resume until a human re-enables it |
| Live expectancy falls below 50% of backtest after 100 live trades | Full re-validation |
| Live slippage on last 20 fills exceeds 0.25R average | Halt that symbol |
| Spread spike exceeds 2x the 60-minute average | Skip entry, or flatten if already in a trade |
| Latency exceeds 400ms or quote gap exceeds 3 seconds | Flatten everything and halt |
| Market data stale (no tick for 10+ seconds) | Flatten everything and halt |

---

## 6. RETURN MODEL

Budget net expectancy after costs. Do not plan with gross backtest numbers.

### Sleeve A

- Trades per month: approximately 60-80
- Budget net expectancy: 0.22-0.30R
- Monthly contribution at 70 trades x 0.25R x 0.24%: approximately 4.2%

### Sleeve B

- Trades per month: approximately 30-50
- Budget net expectancy: 0.20-0.25R
- Monthly contribution at 40 trades x 0.22R x 0.24%: approximately 2.1%

### Sleeve C

- Trades per month: approximately 50-70
- Budget net expectancy: 0.10-0.12R
- Monthly contribution at 60 trades x 0.11R x 0.24%: approximately 1.6%

### Portfolio

- Base: approximately 8%
- Throttle drag and missed limits: 7-10% typical
- Gold runners in trend months: 11-14%

If live Sleeve B is not negatively timed versus Sleeve A, kill Sleeve B. Accept 6-9%. Do not raise risk to fake the missing 3%.

---

## 7. EA IMPLEMENTATION RULES

The strategy is built as one MetaTrader 5 Expert Advisor. Not three EAs on three charts.

### 7.1 Process layout

- One OnTick supervisor owns score, size, throttle, correlation, session clock, and flatten
- Sleeves A, B, and C are modules called by that supervisor
- Magic numbers per sleeve, shared risk object so modules cannot double-book
- Prop-firm flags live in config only: consistency cap, news-trade ban, max lot, hedging ban, EA-allowed check

### 7.2 State machine

IDLE -> RANGE_OK -> SWEEP -> RECLAIM -> DISPLACE -> LIMIT_WORKING -> MANAGE -> FLAT

Never skip LIMIT_WORKING with a market chase.

### 7.3 Non-negotiable execution

- Broker-side stop-loss and take-profit on every order, not only in EA memory
- Separate watchdog process or companion EA that flattens if the main EA is gone, quotes are stale, or latency blows out
- All session clocks use Europe/London, not broker server time. Handle daylight saving automatically
- News calendar is a local file reloaded daily. Do not HTTP-call a calendar from OnTick
- Flatten 15 minutes before CPI, NFP, FOMC and 10 minutes after
- Partial close only on M5 close through +1R, not a wick
- Freeze at most 4 tunable parameters per sleeve. No in-EA optimizer
- Log every fill: score breakdown, spread at entry, latency, requested versus filled price, MFE, MAE, exit reason

### 7.4 Banned in code

- M1 scalping
- Grid or martingale
- Averaging into losses
- Free-margin stack / correlated second position funded by open profit
- Virtual stop with a wider broker stop
- Hedging both sides or opposite challenge accounts
- Raising risk after a winning week
- Treating copied accounts as lower percentage drawdown
- In-EA weekly re-optimization

---

## 8. TEN-YEAR SURVIVAL

### 8.1 Capital

- Fix a compounding base (example: 150,000 across accounts)
- Every month, withdraw 70% of all profit above the base
- Compound the remaining 30% back into the base quarterly
- Three firms. Never more than 40% of total capital at any one firm
- Copier is default insurance, not extra ROI
- Keep 12 months of challenge fees in reserve as a rebuild fund

### 8.2 Edge decay

- Track rolling 30-trade expectancy per instrument per session, for every sleeve
- If any instrument-session combination drops below 0.10R expectancy: auto-pause
- Every January: full walk-forward re-validation on the most recent 12 months
- Maximum 4 tunable parameters per sleeve, ever
- Plan to retire and replace one sleeve every 2-3 years
- The new sleeve starts at Gate 1. It does not inherit live size

### 8.3 Shadow account

Run the same algorithm on a demo account at fixed risk with no governors. When live and shadow diverge, the difference is execution, not edge.

### 8.4 Infrastructure

- VPS in the broker region, ping below 5ms
- Primary and backup VPS
- Tick-level backtesting only, with real variable spread
- Broker-side emergency stops
- Automatic position reconciliation with the broker every 60 seconds
- Daily database and configuration backups
- Alerts for spread spikes, latency, rejected orders, equity limits

---

## 9. DEPLOYMENT GATES

The robot does not go live until it clears all six gates, in order.

### Gate 1: In-sample backtest

Tick-quality M5 data with real variable spread, 2019-2026. Must include March 2020, 2022 rate shock, and 2024-2025 low-vol regime. Per sleeve, per instrument. Minimum 200 trades per sleeve.

Gate: expectancy at least 0.18R, profit factor at least 1.30. A sleeve that fails is not deployed.

### Gate 2: Walk-forward

6-month train, 2-month test, rolling.

Gate: at least 70% of out-of-sample windows profitable. Out-of-sample expectancy at least 60% of in-sample. Maximum 4 optimized parameters per sleeve.

### Gate 3: Cost stress test

Re-run with 2x spread and 0.3-pip adverse slippage on every fill. 10% of profitable limit entries missed. Occasional stop fills worse by 0.25R.

Gate: still profit factor at least 1.15.

### Gate 4: Monte Carlo

5,000 trade-order reshuffles at the portfolio level with correlation preserved between sleeves. Stress with spreads multiplied by 1.5 and slippage multiplied by 2.

Gate: 95th-percentile maximum drawdown at most 8%. If it fails, cut risk. Never adjust the assumptions to make it pass.

### Gate 5: Forward demo

8 weeks on a live-data demo account. Same VPS, same broker. Full automation, zero manual touches.

Gate: live expectancy within 0.7x of backtest expectancy.

### Gate 6: Phased live rollout

- Start with one account at 0.12% risk
- Double to 0.24% only after live expectancy is confirmed within 70% of backtest
- Add the second firm only after 150 profitable live trades
- Add the third firm only after another 150 profitable live trades

---

## 10. WHAT WAS REJECTED AND WHY

| Idea | Why it is out |
|---|---|
| 10-15% every single month as a floor | Incompatible with 8% drawdown over a decade |
| M1 3-5 pip scalping | Round-trip cost eats 16-40% of every R |
| Martingale or increasing grid | Tail death |
| 5-6% Asian grid | Hidden blow-up budget |
| Free-margin stack | Same shock stops both legs. Tail day is about 2x, not zero |
| Copier as extra ROI or lower percent DD | Percent drawdown is identical across copied accounts |
| Crypto funding, MXNJPY carry, IB rebates as core | Custody, devaluation, counterparty. Not an 8% FX box |
| Virtual SL with 3x broker stop | Gap realizes 3R |
| In-EA optimizer | Curve-fit |
| Compounding 15% monthly | 1.15^120 is fantasy. Cash extraction is the 10-year plan |
| DAX cash-open gap fade as a live sleeve | Unproven fill rate, overlaps A/B hours. Incubate only, through Gate 1, as a replacement candidate — never as a fourth live sleeve |

---

## 11. ONE-CARD SUMMARY

Architecture: three decorrelated sleeves. Session-open sweep, volatility-expansion continuation, Asian mean reversion.

Sleeve A: M5 liquidity sweep and reclaim at London and NY opens. EURUSD, GBPUSD, USDJPY, XAUUSD. 8-point score, fire at 7+. Limit at 50% retracement of displacement. Stop beyond sweep plus 0.10 x ATR. Exit 40/30/30 except XAUUSD 60/20/20. 45-minute hard time stop.

Sleeve B: M15 volatility-expansion breakout that holds. XAUUSD, GBPJPY, indices only if listed. Daily ATR in 60th-90th percentile. Enter on pullback. Stop 1.2 x ATR. Exit 50% at +1.5R, remainder on Chandelier trail.

Sleeve C: Asian mean reversion. AUDNZD, EURGBP, EURCHF. ADX below 16, fade 2-sigma Bollinger to mean. Single target. Hard flat at 06:30 London. No grid.

Risk: 0.24% per trade at full tier. Throttle 0.24 then 0.12 then 0.06 then shutdown at 6%. Daily -1.0%, weekly -2.5%. Max 1.0% open risk.

EA: one MT5 process, three modules, shared risk brain, broker-side stops, Europe/London clocks, local news file, watchdog flatten.

Survival: 3 firms. Withdraw 70% of profit monthly. Rolling expectancy monitor. Annual walk-forward. Max 4 parameters per sleeve. Replace one sleeve every 2-3 years. Shadow account always running.

Expectation: 9-12% average month, 13-15% strong month, one or two -3 to -5% months per year. Max drawdown 6-8%. 10-year survival probability 35-45%.

The two rules that do the heavy lifting: the 45-minute time stop, and the drawdown throttle. Build those two first and test them in isolation before anything else.
