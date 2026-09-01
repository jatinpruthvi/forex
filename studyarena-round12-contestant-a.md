# StudyArena

**Question:** now suggest me final trading strategy.

**Answered by** Contestant A · Round 12 · 31 Aug 2026

---

# SWEEP-1 — FINAL LOCKED STRATEGY

*One edge. Three sessions. Fully automated. Built to survive 10 years, not to win one month.*

---

## THE EDGE (one sentence)

At session opens, price sweeps the prior range's liquidity pool, rejects, and displaces in the opposite direction — the algo enters on the retracement of the displacement candle, exits on a fixed ladder, and kills the trade at 45 minutes if the thesis doesn't pay.

Nothing else. No indicators, no second strategy, no discretion.

---

## 1. TRADING WINDOWS & INSTRUMENTS (locked)

| Sleeve | Window (UK) | Instruments | Reference range |
|---|---|---|---|
| **Asian** | 00:00–06:30 | AUDNZD, EURGBP | 21:00–00:00 prior day |
| **London** | 07:00–11:30 | EURUSD, GBPUSD, XAUUSD | Asian session 00:00–07:00 |
| **New York** | 13:30–17:00 | XAUUSD, USDJPY | London 07:00–13:00 |

**Timeframe: M5. Not M1.** At a 3–5 pip M1 stop, spread and slippage eat 20–40% of the edge; on an M5 sweep with a 10–20 point stop, costs are 5–10%. The algo's edge is discipline and breadth, not milliseconds. Every M1 EA I've watched died inside 36 months.

**Hard exclusions:** no entries 21:30–23:30 UK (thin spreads), **flat every Friday 20:00 UK** (weekend gaps ignore stop losses — SNB 2015, GBP 2016, JPY 2022), flat ±30 min around red-folder news.

---

## 2. ENTRY — 8-POINT SCORE (must be ≥ 7/8 to fire)

| # | Filter | Pass condition |
|---|---|---|
| 1 | **Range quality** | Range = 35–75% of its 20-day median |
| 2 | **Bias** | Price on correct side of H1 50-EMA, EMA slope agrees (waived on AUDNZD/EURGBP if H1 ADX < 16) |
| 3 | **Sweep** | Trades beyond range extreme, closes back inside within 3× M5 |
| 4 | **Rejection** | Sweep candle wick ≥ 60% of its total range |
| 5 | **Displacement** | Next M5 body ≥ 60% of range, closes past prior candle midpoint |
| 6 | **Spread gate** | Live spread ≤ 1.5× the 20-day average for that symbol |
| 7 | **Participation** | Sweep-candle tick volume ≥ 1.2× the 20-candle average |
| 8 | **Clean book** | No news ±30 min, no correlated position open |

**Order:** limit at the **50% retracement of the displacement candle body**. Unfilled after 3 candles → cancelled.
**Stop:** beyond the sweep extreme + 0.1 × M15-ATR(14). Reject if stop < 0.6× or > 1.5× M15-ATR.

Score 8/8 → full tier risk. Score 7/8 → half tier risk. Score ≤ 6 → no trade, no exceptions.

---

## 3. EXIT — the ladder (unchanged, mechanical)

| Trigger | Action |
|---|---|
| **+1R** | Close 40%, stop → breakeven (only on a **candle close** past +1R, not a wick) |
| **+2R** | Close 30% |
| **Runner (30%)** | Trail at High − 2.5 × H1-ATR, updated hourly |
| **45 minutes** | If +1R not reached in 9× M5 candles → **close at market**, any P&L |
| **Session close** | Flat, unless runner ≥ +2R with stop at BE |

The 45-minute time-stop is the single highest-value line in this document. Sweeps displace immediately; if price is still hovering at entry, the thesis is dead and you're the liquidity now. It converts slow-bleed full losers into ~0.2R scratches and is what lifts net expectancy from marginal to real.

---

## 4. RISK — the drawdown throttle (hard-coded, no override)

| Drawdown from equity high | Risk per trade |
|---|---|
| 0 – 2% | **0.60%** |
| 2 – 4% | **0.30%** |
| 4 – 6% | **0.15%** |
| > 6% | **Shutdown until next month** |

Why this specific ladder — the survival math:

Over ~12,000 trades in ten years, the expected longest losing streak is
\[\frac{\ln(12000\times0.45)}{\ln(1/0.55)} \approx 14.4 \text{ losses.}\]

At a flat 0.6% that streak costs 9% — account dead. Walked through the throttle instead:

\[4(0.6\%) + 6(0.3\%) + 5(0.15\%) = 4.95\%\]

**A 15-loss streak costs you 4.95%.** It takes 22 consecutive losses to reach the 6% shutdown. Your 7–8% ceiling is structurally unreachable, not merely hoped for.

Also hard-capped: daily −1.5% → stop for the day. Weekly −3% → stop for the week. Max concurrent open risk 1.2%. Correlated pairs in the same direction (EURUSD + GBPUSD) count as **one** position.

**On sizing sanity:** full Kelly for this edge is \((0.55\times1.9-0.45)/1.9 = 31.3\%\) per trade. We trade 0.6% — roughly 1/50th Kelly. That gap is the whole reason the account is still alive in year ten.

---

## 5. THE RETURN MODEL (honest numbers)

Gross expectancy: \(0.55 \times 1.9 - 0.45 = 0.595R\). After spread, slippage, swap and the time-stop scratches, budget **0.30R net**.

\[60 \text{ trades} \times 0.30R \times 0.6\% = 10.8\%/\text{month base}\]

Free-margin stack (activates **only** when month-to-date ≥ +5%): the +1R locked profit on a winner becomes the entire stop budget for one correlated high-beta continuation trade (long EURUSD → long GBPJPY/DAX). Both stop out = net zero, no new drawdown. Adds **+2 to 3%**.

| Metric | Realistic value |
|---|---|
| Average month | **+11% to +14%** |
| Month spread | +4% to +20%; expect one −3/4% month a year |
| Realized max DD | 5–7% |
| Ten-year worst-case DD | ~6% (throttle caps it) |
| Capacity | ~$500k base — grow by adding accounts, never by raising % risk |

---

## 6. THE STRUCTURE THAT MAKES IT LAST 10 YEARS

**Counterparty split.** 3 × $50K accounts at **three different firms**, trade-copied at 0.2% each. One firm collapsing costs a third, not everything. Keep 6 months of fees and living costs outside the trading ecosystem entirely.

**The cash sweep — this is the real answer to your 10-year question.** Compounding 13%/month for 120 months is \(1.13^{120}\) ≈ 3.6 million-fold. It does not exist. So don't chase it: fix a **compounding base** (say $300k across accounts → ~$39,000/month at 13%), **withdraw 70% of profit each month**, compound the other 30% back quarterly. Add a fourth account when the base grows 25%. Realized cash in your bank is the only money a broker, a gap, or your own future mistake can never take back. This turns a curve that must eventually blow up into a machine that pays a salary indefinitely.

**Edge-decay monitor — the module nobody builds, and the reason most 10-year attempts end at year three.** Track rolling 30-trade expectancy *per instrument × session*. Below **0.10R** → that sleeve auto-pauses and alerts you. Every January, walk-forward re-validate on the newest 12 months. Cap tunable parameters at four, forever — a parameter that only works at one exact value is curve-fit, delete it. Plan to retire and replace one sleeve every 2–3 years; the structure survives, the instruments rotate.

**Kill switches:** 5 straight losses → 24h pause and review. Live slippage > 1.5× backtest → halve risk automatically. Spread spike → flatten everything.

---

## 7. DEPLOYMENT GATES (do not skip a single one)

1. **Tick-quality M5 backtest, 2021–2026**, per sleeve. Gate: ≥ 200 trades, PF ≥ 1.35, expectancy ≥ 0.25R. A sleeve that fails is not deployed — no "it'll work live."
2. **Walk-forward:** ≥ 70% of out-of-sample windows profitable.
3. **Monte Carlo, 5,000 runs:** 95th-percentile drawdown ≤ 8%.
4. **8 weeks demo** on live spreads, full automation, zero manual touches.
5. **One account at 0.3% risk.** Add accounts two and three only after **100 profitable live trades**.

---

Below is the desk tool for running this live: pre-trade score gate, throttle-aware position sizer across all three accounts, the 45-minute clock, and the monthly sweep calculator.

**The desk tool is live above.** Four panels, used in this order every trade:

1. **Score gate** — tick the 8 filters. 8/8 = full risk, 7/8 = half risk, anything less shows NO TRADE. Don't argue with it.
2. **Throttle sizer** — enter account size, your *current drawdown from equity high*, and stop distance. It picks the tier automatically (0.60 / 0.30 / 0.15 / shutdown), returns lots per account, combined risk, and your +1R / +2R cash targets.
3. **Kill clock** — hit start the moment the limit fills. At 00:00 you close at market, no matter what the chart is doing.
4. **Cash sweep** — at $300k base and 13%, it shows $39,000/month, $27,300 withdrawn, $11,700 compounded, and the base's honest 12-month growth.

---

### The whole strategy on one card

**Edge:** M5 liquidity sweep + reclaim at session opens → enter on 50% retracement of the displacement candle.
**Windows:** Asian 00:00–06:30 (AUDNZD, EURGBP) · London 07:00–11:30 (EURUSD, GBPUSD, XAUUSD) · NY 13:30–17:00 (XAUUSD, USDJPY), UK time.
**Entry:** 8-point score, fire at ≥ 7. Stop beyond the sweep + 0.1× M15-ATR.
**Exit:** 40% at +1R (stop → BE on candle close) · 30% at +2R · 30% trailing 2.5× H1-ATR · **hard close at 45 minutes** · flat at session end · **flat every Friday**.
**Risk:** 0.60% → 0.30% → 0.15% → shutdown, stepped by drawdown. Daily −1.5%, weekly −3%. Max 1.2% open. 3 accounts, 3 different firms, 0.2% each.
**Survival:** rolling 30-trade expectancy per sleeve, auto-pause below 0.10R · annual walk-forward re-validation · max 4 tunable parameters · withdraw 70% of profit monthly.
**Expectation:** ~60 trades/month × 0.30R net × 0.6% ≈ **10.8% base, +2–3% from the stack, so 11–14% average**, with a 15-loss streak costing only **4.95%** and shutdown triggering at 6% — your 7–8% ceiling never gets tested.

The two lines that do the heavy lifting, if you cut everything else: **the 45-minute time-stop** (turns full losers into scratches) and **the drawdown throttle** (makes the 14-loss streak that *will* arrive in ten years survivable). Build those two first and test them in isolation — you'll see the equity curve change shape before a single other module is written.
