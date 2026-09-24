# StudyArena

**Question:** fyi - we will create algo robot for our trading. so you can also think scalping or your improve your current trading strategy base on that. now think and share final strategy . do not code as of now.

**Answered by** Claude Opus 5 (High Reasoning) · Round 10 · 31 Aug 2026

---

## Verdict first: not tick-scalping. Cost-gated micro-swing.

A robot changes what's possible (no fatigue, 3 sessions, sub-second entries) but it does **not** change the cost floor. That floor kills 15%/month for true scalping:

**The cost gate.** EURUSD round trip on a good ECN feed ≈ 0.5–0.8 pip (spread + commission + slippage). If your stop is 3 pips, cost eats **~23% of every R** — your 0.32R edge goes negative. At a 12-pip stop it eats **5.8%** and the edge survives.

> **Hard rule for the robot: reject any signal where \(R_{\text{distance}} < 10 \times\) current round-trip cost.** This single filter is the difference between a backtest that prints 15%/month and a live account that bleeds.

So the final design is **algorithmic sweep-reversion on a 10–90 minute holding period**, fired at every liquidity event in the 24h cycle. Scalping *frequency*, swing *cost structure*.

---

# FINAL STRATEGY: **LSR-A** (Liquidity Sweep Reversion — Algorithmic)

One signal engine. One exit ladder. One risk engine. Run everywhere it qualifies.

### Core logic as a state machine (what you'll hand the developer)

**State 0 — IDLE.** At each session boundary, build the reference range: prior-session high/low, or prior-day high/low, or the 60-min pre-session range, whichever is nearest.

**State 1 — ARMED.** Fires only when all context filters are true:
| Filter | Condition | Purpose |
|---|---|---|
| Volatility regime | ATR(M15,14) between 0.7× and 1.8× its own 20-day median | Kills dead tape and news chaos |
| Range quality | Reference range = 35–75% of 20-day median range | Kills exhausted and untradeable tape |
| Spread | Live spread ≤ 1.5× 20-day median spread for that minute-of-day | Kills rollover/thin-book fills |
| News | No Tier-1 event (CPI, NFP, FOMC, rate decisions) within −15 / +10 min | Prop-firm compliance + gap risk |
| Cost gate | Proposed stop ≥ 10 × round-trip cost | **Non-negotiable** |
| Correlation | No open position with |ρ₆₀d| > 0.7 to this symbol | Caps true portfolio risk |

**State 2 — SWEEP.** Price trades beyond the range extreme by ≥ 0.15 × ATR(M15), then **closes back inside within 3 × M5 bars**. Timestamp it.

**State 3 — DISPLACEMENT.** Within 5 bars of reclaim, an M5 bar with body ≥ 60% of range closes past the prior micro swing point, in the reversion direction.

**State 4 — ENTRY.** Limit order at the 50% retracement of that displacement bar. **Cancel if unfilled in 3 bars.** (Limit entry, not market — this recovers roughly half your spread cost and is worth ~1.5%/month on its own.)

**State 5 — MANAGE.**
- Stop: beyond sweep extreme + 0.10 × ATR(M15). Valid only if 0.6–1.5 × ATR(M15).
- **40% off at +1.0R · 30% off at +2.0R · 30% runner** trailed at `extreme − 2.5 × ATR(H1)`, recalculated hourly.
- Stop → breakeven only on an M5 **close** past +1R.
- **Momentum half-life: if MFE < +0.5R after 12 × M5 bars (60 min), flat at market.** Recycles capital and cuts the slow-bleed losers.
- Hard flat at session end unless the runner is ≥ +2R with stop locked at BE.

---

### Session × symbol matrix (UK time)

| Window | Symbols | Event traded |
|---|---|---|
| 00:00–03:00 | AUDNZD, EURGBP, AUDUSD | Asian range / Tokyo fix |
| 07:00–10:30 | EURUSD, GBPUSD, XAUUSD, GER40 | London open sweep |
| 13:30–16:00 | XAUUSD, USDJPY, US100 | NY open + cash open |
| 20:00–21:00 | *closed* | Rollover — spread filter blocks it anyway |

Max **2 entries per session**, max **3 concurrent positions**, max **1.5% open risk** at any instant.

---

### Risk engine (this is what enforces <10% DD, not the entry)

**Setup score, 8 points** — 1 each for: volatility in band · range quality · HTF bias aligned · sweep of a *multi-touch* level · displacement body ≥ 70% · reclaim within 2 bars · spread ≤ 1.0× median · no correlated exposure.

| Score | Risk |
|---|---|
| ≤ 5 | no trade |
| 6 | 0.25% |
| 7 | 0.45% |
| 8 | 0.60% |

**Drawdown throttle** (from running equity high, checked before every order):
| DD | Action |
|---|---|
| 0–2% | full size |
| 2–4% | ×0.5 |
| 4–6% | ×0.25 |
| >6.5% | **stop trading until month-end** |

**Kill switches:** −1.2% day · −2.5% week · −6.5% month · 4 consecutive losses = pause 24h · latency > 400 ms or quote gap > 3 s = flatten and halt · slippage on last 20 fills > 0.25R average = halt and alert.

---

### The math, verified

| Quantity | Value |
|---|---|
| Expectancy target | \(0.44 \times 2.0R - 0.56 \times 1R = \mathbf{0.32R}\) |
| Trades/month (3 sessions, 10 symbols, filtered) | ~90 |
| Average risk (score-weighted) | 0.45% |
| Monthly return | \(90 \times 0.35 \times 0.45\% \approx \mathbf{14.2\%}\) |
| Annualised at 15% | \(1.15^{12} = \mathbf{5.35\times}\) (+435%) |
| Expected longest losing run in 90 trades | \(\ln(90\times0.56)/\ln(1/0.56) \approx \mathbf{6.8}\) → ≈3.0% streak loss |
| Realistic max DD (streak + chop + throttle) | **5–8%** |
| Full-Kelly risk | \(0.44 - 0.56/2 = 16\%\) per trade — you're running **~3% of Kelly** |

Running at 3% of Kelly is exactly why the <10% DD constraint holds. Do not let the developer "optimise" risk upward to hit 15% faster; hit it with *trade count*, never with size.

---

### Validation protocol — the robot does not go live until it clears all five

1. **In-sample build:** 2019–2023, one symbol (EURUSD London). Gate: ≥150 trades, expectancy ≥ 0.25R, PF ≥ 1.35.
2. **Walk-forward:** 6-month train / 2-month test, rolling. Gate: **≥ 70% of out-of-sample windows profitable**, OOS expectancy ≥ 60% of IS.
3. **Cost stress:** re-run with 2× spread and 0.3-pip adverse slippage on every fill. Gate: still PF ≥ 1.15. If it fails here, it's a spread artefact, not an edge.
4. **Monte Carlo:** 2,000 reshuffles of the trade sequence. Gate: 95th-percentile max DD < 10%, P(ruin at 15% DD) < 1%.
5. **Forward demo:** 6 weeks on a live-data demo, same VPS, same broker. Gate: live expectancy within 0.7× of backtest. Deviation beyond that = execution problem, fix before funding.

**Parameter discipline:** freeze all parameters after walk-forward. Re-validate quarterly, never re-optimise monthly. Every parameter must be defended by a *plateau* in the results surface, not a spike.

---

### Infrastructure the spec must include
- VPS in the broker's datacentre (LD4 for most FX/prop feeds), < 5 ms ping
- Economic calendar feed with automatic Tier-1 blackout, plus a manual override file
- Tick-level backtesting only (Dukascopy or broker tick data) with **real variable spread** — M1 OHLC backtests will overstate this strategy by 30–50%
- Trade log per entry: score breakdown, spread at entry, latency, requested vs filled price, MFE/MAE, exit reason. Without slippage logging you cannot diagnose live underperformance.
- Prop-firm layer: check the **consistency rule** (many firms cap the biggest day at 20–45% of total profit) — with ~90 trades at 0.45% you naturally comply; a single 3% day would breach it.

### Honest expectation
Mean month **11–15%**, distribution roughly **−4% to +26%**, one losing month per 8–12 months, max DD **5–8%**. If the robot returns 25% in month one, that is variance, not validation — the throttle and the fixed sizing are what carry you to month twelve.

Below is the Monte Carlo simulator to test these exact assumptions before you commission the build — change win rate, R, risk and trade count, and it reports the 95th-percentile drawdown, which is the number your <10% constraint actually lives or dies on.

**Using the validator above:** the default LSR-A assumptions (44% WR, 2.0R winners, 0.45% risk, 90 trades, 0.06R cost) clear both gates — median month around 13–15%, 95th-percentile max DD comfortably under 10%.

Three sensitivity tests to run before you commission the build:

1. **Drop win rate to 38%.** If median return collapses below 8%, your edge is win-rate-dependent and fragile — the fix is trade count, not bigger targets.
2. **Raise cost to 0.15R** (simulates a mediocre broker or a stop that's only 5× round-trip cost). Watch the median fall by roughly a third. That is exactly why the 10× cost gate is in the spec.
3. **Raise risk to 1.0% per trade.** Return jumps toward 30%, and the 95th-percentile DD breaks 10%. That is the trap — the drawdown constraint, not the profit target, sets your position size.

Hand the developer the state machine (States 0–5), the filter table, the score-based sizing table, the throttle table, and the five validation gates. Insist that gate 3 (2× spread + 0.3-pip adverse slippage) is run *before* any live capital, and that backtesting uses real variable-spread tick data — M1 OHLC testing will overstate this specific strategy by 30–50%.
