# JJ Simon's 1-Minute Fair Pricing Strategy — Specification

Source: Chart Fanatics video "STEAL The 1-Minute Strategy That Made Him $1.8M+ (Works Every Session)"
Glimpse summary: https://glimpse.wozart.com/v/4ajvjwex
Status: research / codification. No live order submission from this spec until a pass-rate backtest over ≥50 simulated evals is produced (see §11).

This document translates JJ Simon's mechanical fair-pricing-theory approach for NASDAQ futures prop-firm trading into a specification that can be tested, backtested, and — only after validation — implemented as an EA or manual checklist. It targets M1 NQ (NAS100 / NASDAQ futures). Adaptation to forex indices (GER40, US30, NAS100 CFDs) is left to §12.

---

## 1. Core premise (Fair Pricing Theory)

Markets spend most of their time at a "fair price" — a transient equilibrium set by the recent consolidation (session open, pre-news level, post-news consolidation). External events (session opens, scheduled news, unscheduled shocks) displace price **away** from that fair level. The initial displacement candle is mechanically unfair; price reverts toward fair price with a measurable edge.

- We do not predict direction from indicators. We identify **fair price** and **unfair displacement**, then trade the reversion.
- The strategy is **mechanical**: exactly three entry patterns, static risk-to-reward, fixed session windows, fixed stop rule. Discretion is allowed only when deciding whether fair price has moved (§5.3).
- The edge is realised across **many accounts / many trades**, not on any single account (§8, §10).

---

## 2. Instrument, timeframe, broker data

| Item | Value |
|---|---|
| Primary instrument | **NQ** (NASDAQ 100 E-mini futures, CME Sept/Dec/Mar/Jun cycle) |
| CFD proxy (if no futures feed) | NAS100 / US100 micro lot, 0.01 min lot, tick size known at runtime |
| Timeframe | **M1** (1-minute candles) |
| Sessions | New York open 9:30–11:00 EST, New York PM open 14:00–15:30 EST, Asia open (see §4) |
| Do-not-trade window | 11:00–14:00 EST (dead zone — volume collapses) and after 15:30 EST (liquidity drop) |
| Data requirement | Tick-accurate M1 OHLC with real volume; bid/ask spread log for cost model |
| Timezone | All hard windows specified in **US/Eastern** (EST/EDT must be resolved at runtime — NYSE calendar) |

---

## 3. Defining fair price

Fair price is the last consolidation level before an unfair displacement. There are exactly three fair-price anchors, in priority order:

1. **Session-open price** — the close of the 9:30 EST candle for NY AM, the 14:00 EST candle for NY PM, the Asia open candle for the Asia session. This is the default anchor for the first ~30 minutes of the session.
2. **Pre-news consolidation** — the tight range (≤ 5 candles) immediately before a scheduled (red-folder) news release. For CPI / PPI / NFP / FOMC at 8:30 EST, the pre-news price is fair; the first candle after release is unfair.
3. **Post-unexpected-news consolidation** — after an unscheduled shock (tweet, Fed chair unscheduled remarks, geopolitical), the first consolidation zone that forms (3–6 overlapping candles) becomes the new fair price. **Do not revert to pre-news** in this case — fair price has moved.

When none of the three anchors is present (mid-session, no news, consolidation has broken), there is no fair-price reference: **do not trade**.

---

## 4. Trading windows (kill zones)

Only trade the first 90 minutes of high-volume sessions. All times US/Eastern.

| Window | Open | Close | Notes |
|---|---|---|---|
| New York AM | 09:30 | 11:00 | Primary window. Session-open reversions + 8:30 news reversions. |
| Dead zone | 11:00 | 14:00 | No trades. Volume flat; edge disappears. |
| New York PM | 14:00 | 15:30 | Secondary window. Re-open reversions. |
| Asia open | 20:00 (or local Sydney/Tokyo open per broker) | +90 min | Optional, lower edge; same mechanical rules apply. |
| London open | 08:00 (07:00 if DST) | 09:30 | Optional overlaps with NY pre-news; treated as Asia-close drift, not a primary window. |

After 15:30 EST: close any open orders; do not enter new trades. Liquidity drops and slippage erases the edge.

---

## 5. Three mechanical entry signals

All entries are reversion-to-fair-price trades. Each must have (a) a clear fair-price anchor, and (b) a qualifying unfair displacement. Continuation trades are allowed only at the session open (first 5–10 minutes) before reversion becomes the dominant bias — see §5.4.

### 5.1 Displacement candle (DC)

Best for evaluation accounts — faster turnover, lower per-trade win rate but faster pass-rate accumulation.

Qualifications:
- Candle body size (|close − open|) > 1.5× the median body size of the prior 10 candles.
- Candle closes beyond its own wick in the direction of displacement (i.e. bullish displacement closes at/near the high; bearish at/near the low) — in JJ's framing "closes below the wick" means the closing price leaves no meaningful wick on the displacement side, confirming commitment.
- Displacement direction is **away** from fair price (e.g. fair price above, displacement is down → wait for buy setup; fair price below, displacement is up → wait for sell setup).
- Entry: **market order at the close of the next candle** if price does not immediately return to fair price. Alternative conservative entry: limit at 50% of the displacement candle.

### 5.2 Break of structure (BoS)

Best for funded accounts — higher win rate, more selective.

Qualifications:
- A swing wick (high or low) prints that is more extreme than its **two adjacent candles on each side** (a local 5-bar extreme).
- Price later closes back through that wick level **in the direction of fair price** (e.g. after a downward displacement, a local low wick forms; a close above that wick confirms the reversion structure has broken).
- Entry: market on the close that breaks the structure, or stop-entry just beyond the wick level.

### 5.3 News reversion (NR) — the A+ setup

Highest win rate. Only for **expected/scheduled** (red-folder) news.

Qualifications:
- Scheduled event at a known time (CPI, PPI, NFP, FOMC decision, retail sales, etc. — see §6).
- In the 6–12 hours before release, price trades within a range; that range's midpoint/close is fair.
- The first 1-minute candle (or first 2–3 candles) after the release creates a sharp move away from the pre-news range. That initial move is **unfair** (outcomes almost always land close to forecast).
- Entry: market in the direction of fair price as soon as the first news candle closes and the displacement is measurable.
- Target: pre-news consolidation level (fair price).
- Stop: beyond the wick of the news candle (reciprocal of TP in points — §7).

**Unexpected news (tweets, unscheduled Fed comments, geopolitics):** Do NOT revert to pre-news. After the initial move, let a consolidation form (3–6 overlapping candles). That consolidation becomes the new fair price; trade slight drift/continuation away from it or reverts back to it — never back to the old level.

### 5.4 Session-open continuation (optional first-leg)

At exactly 9:30 EST, overnight orders create an initial impulse. That impulse is not immediately unfair — for the first 5–10 minutes a continuation trade in the direction of the opening drive is acceptable (one trade only). After 9:40 EST, bias flips to reversion back toward the 9:30 open price. The continuation leg is optional and should be disabled for the first 50-eval backtest (§11) to isolate the reversion edge.

---

## 6. News calendar rules

- Maintain a list of expected (red-folder) events for the current week, pulled from Forex Factory / Econoday. Events that move NQ: CPI, PPI, Core PCE, NFP, FOMC rate decision + press conference, retail sales, ISM, GDP, initial jobless claims (minor), Fed chair scheduled speeches.
- **30-minute blackout** around an event where no new entry is placed (except the news-reversion entry itself on the first post-release close). Pending entries not related to the news are cancelled before release.
- If the outcome is a massive miss (>2σ from forecast — JJ does not give a hard threshold; in testing we can use >1.5× the recent ATR move on release), treat it as if unexpected and wait for a new fair-price consolidation rather than reverting.

---

## 7. Risk management (static RR, prop-firm optimized)

Prop firms reward **fixed** risk and fixed targets that respect account rules. Discretionary targets (trailing stops, "runners", partial closes based on structure) are **not used** here. That is the opposite of how live discretionary trading works.

### 7.1 Risk-to-reward by account type

| Account type | RR ratio | Why |
|---|---|---|
| Evaluation (phase 1 / phase 2) | **1:1 to 1:1.5** | Fastest path to profit target; win rate dominates; pass rate is the metric. |
| Funded with consistency rule (e.g. ≤50% biggest-day rule, min-days rule) | **1:1 to 1:2** | Need steady wins; 1:4 creates drawdown oscillation and takes 3–6 months to accrue RR. |
| Funded without consistency rule | **1:3 to 1:6** | Let winners run; expect lower win rate but higher EV per trade. |

### 7.2 Optimize take profit FIRST; stop loss is the reciprocal

- Set TP at fair price (§3) OR at the static RR distance, whichever comes first.
- Compute points to fair price: `pts_to_fair = abs(entry - fair_price) / point_value`.
- SL points = `pts_to_fair / RR` (so SL is the mathematical reciprocal — JJ calls this "essentially random" because it isn't placed at structure, but it must pair to TP for EV to hold).
- Never move SL to break-even early on static-RR accounts — it breaks the RR symmetry the pass-rate math assumes. Break-even moves are permitted only after 50% of TP is reached on consistency accounts (as a variance reducer, to be tested).

### 7.3 Contract sizing (keep dollar risk constant)

- Determine dollar risk allowed per trade: `risk_usd = account_risk_pct × account_balance` (typically 0.5%–1.0% for evals; see §8).
- Points available to fair price may be smaller or larger than the RR-implied distance. Adjust contracts so dollar risk stays at `risk_usd`:
  - If 76 points available but TP needs only 38, halve the contracts (1 contract → 5 micros on NQ micros).
  - If 50 points to TP and you need $6,000 profit target on the account, raise contracts until `contracts × point_value × pts_to_TP = required_profit_per_trade`.
- Never exceed 1 micro lot per $100 of account on NQ micros without validating against broker margin rules.

### 7.4 Three-loss rule (session kill switch)

If **three consecutive reversion trades** in a single session end in a loss, stop trading reversions for that session. The market is trending and fair price has moved; further reversions will violate the bias.

- A continuation trade taken under §5.4 does not count toward the three.
- If the three losses occur before 10:00 EST, the session is over.
- You may resume at the NY PM session (14:00) with a fresh fair-price anchor (the PM open). Treat it as a new session (counter resets).

### 7.5 Daily / firm-level hard boundaries

- Always stay inside the prop firm's daily loss and overall drawdown.
- Maximum of one open position per account; because trades are layered across accounts (§8), within a single account there is never more than one working order.

---

## 8. Account management and layering

JJ manages 45+ accounts simultaneously by treating each account as an independent binomial trial of the same bias.

### 8.1 One trade per account per setup

Each entry signal (DC, BoS, NR) is taken on **a separate account**. If the same bias produces three DC entries in sequence as price moves toward fair price, each DC goes on a fresh evaluation/funded account. This:
- Spreads risk (one bad fill doesn't kill one large account).
- Maximises the number of "bias realisations" per session (30+ trades per session is normal).
- Allows different RR profiles per account type (DC on evals at 1:1.5; BoS on funded at 1:3).

### 8.2 Signal → account-type mapping

| Signal | Use on | RR | Rationale |
|---|---|---|---|
| Displacement candle | Evaluations | 1:1 – 1:1.5 | Faster, lower win rate, but more setups — good for passing many evals quickly. |
| Break of structure | Funded accounts | 1:3+ (or 1:1–1:2 under consistency) | Higher win rate, more selective; preserves funded capital. |
| News reversion | Both (A+ on funded) | 1:2 – 1:4 (TP = pre-news fair price, which may be many points away) | Highest win rate; ideal for growing funded balances. |

### 8.3 Scaling ladder (from JJ's trajectory)

1. Start with **one evaluation**, pass it.
2. Take the first payout.
3. Reinvest payout into **5 funded accounts**.
4. When EV per funded account is positive (§10), scale to 20–50 accounts (JJ peaked at 45+).
5. When prop firms move accounts live, **keep SIM balance below the live account size** so EV doesn't invert.
6. Prefer newer firms with better payout policies; rotate away from firms that tighten rules.

---

## 9. Expected vs unexpected news (decision table)

| Scenario | Initial move | Fair price after event | Trade |
|---|---|---|---|
| Scheduled (CPI, NFP, FOMC) near forecast | Unfair, overshoots | Pre-news level unchanged | Reversion to pre-news |
| Scheduled, large miss (>1.5× ATR surprise) | Trend day | Wait for new consolidation (3–6 bars) | Reversion to new consolidation (not pre-news) |
| Unscheduled (tweet, surprise Fed comment) | Impulse + drift | New consolidation post-move | Continuation (slight drift) or reversion to new consolidation |
| Geopolitical / circuit-breaker type | Chaotic | Unknown | Do not trade for the session |

---

## 10. Pass-rate math (the numbers that matter)

Prop firms are designed such that a live-equity-curve backtest will lie. The correct metric is **pass rate across many simulated accounts**.

### 10.1 Backtest methodology

1. Simulate **≥50 evaluation accounts** (JJ recommends 50+; 10 at a minimum for rough signal).
2. Apply the SAME static RR on every trade for a given account type.
3. Enforce the exact firm rules (trailing drawdown from peak balance, daily loss limit, consistency/max-day rule, minimum trading days).
4. Record pass/fail for each simulated eval.
5. Pass rate = `passed / total`.

### 10.2 Cost per funded account

```
cost_per_funded = eval_price / pass_rate
```

Example: eval costs $100, pass rate 25% → $400 per funded account.

### 10.3 Expected value test

```
ev_per_funded = expected_payout_per_funded_account × payout_rate
scale if and only if ev_per_funded > cost_per_funded
```

Example: funded account expected payout $2,000, payout rate (probability you actually get paid before being restricted/closed) 30% → $600 EV; cost $400 → profitable.

### 10.4 Risk of ruin on a single eval

At 30% pass rate and 30% payout rate, the probability of getting paid on one eval is 0.30 × 0.30 = **9%** (a 91% chance of nothing). Do not judge the strategy on 3 evals. Variance with small samples will kill you; that does not mean the strategy failed. The edge only appears across many evals because EV is positive: lose $900 on 9 evals, win $2,000+ on 1 payout.

---

## 11. Validation gates before live use

The repository's standing rule (fail-closed) applies. Before any live order is placed from this spec, all of the following must be satisfied:

- [ ] M1 historical data for NQ (or chosen proxy) covering ≥6 months, including at least 6 CPI / NFP releases and 2 FOMC meetings.
- [ ] Pass-rate simulator (Python) built per §10.1 with configurable firm rules (trailing DD, daily loss, consistency).
- [ ] ≥50-eval backtest showing a pass rate ≥25% for evaluations at 1:1.5 RR, with EV > cost.
- [ ] Per-trade log includes: signal type, fair-price anchor used, RR, points to TP, points to SL, session, news flag, outcome.
- [ ] Three-loss rule tested: confirm that sessions with 3 consecutive losses do indeed have negative EV when continued.
- [ ] News-reversion win rate measured separately; must be the highest of the three signal types (as JJ claims).
- [ ] Dead-zone trades (11:00–14:00 EST) measured and confirmed to have EV ≤ 0.
- [ ] Spread and slippage model included (use ≥1.5× average spread per minute as hard gate, per §3 of existing THE5ERS plan).
- [ ] Contract-sizing math back-tested to confirm dollar risk stays within account_risk_pct on every trade.
- [ ] Manual walk-forward of at least 10 live-session replays (trading the replay bar-by-bar) before any EA is allowed to place demo orders.

---

## 12. Open questions / adaptation notes

These are points where JJ's description is qualitative and we must pick concrete parameters for coding. They are to be resolved by the backtest in §11, not by argument.

1. **Displacement threshold.** "Body larger than previous, closes below the wick" — codify as body > 1.5× median 10-candle body AND (for bearish DC) close ≤ low + 10% of body range; threshold value (1.3× / 1.5× / 2.0×) to be sweep-tested.
2. **BoS lookback.** "Wick lower than two adjacent candles" — test 2-bar vs 3-bar (5-bar vs 7-bar) swing definition.
3. **News consolidation definition.** "3–6 overlapping candles" — define overlap as ≥70% body overlap; exact count to be sweep-tested.
4. **Session open continuation leg** (§5.4): confirm whether including it raises or lowers pass rate for evaluations; default off for first backtest.
5. **Forex proxy adaptation.** JJ trades NQ futures. If adapting to forex indices (GER40, US30, NAS100 CFD), re-test fair-price anchors — forex session opens (Frankfurt/London/Tokyo) may behave differently from NY 9:30.
6. **Asia session.** JJ mentions Asia open as a tradeable window but focuses most examples on NY. Measure EV separately; expect lower edge due to lower volume.
7. **Unexpected-news classification.** Need a hard rule for "large miss" vs "near forecast" to route between expected-NR and treat-as-unexpected paths. Start with 1.5× the 12-hour ATR as the threshold on the first news candle.
8. **Break-even move** (§7.2): test whether a break-even move after 50% TP reached improves pass rate on consistency accounts (it reduces the worst case but breaks pure static-RR symmetry).

---

## 13. Notable quotes (from source)

> "If you can follow a bias on prop firms, you're going to make a ton of money." — JJ Simon

> "Optimize for your take profit first. The stop loss is going to be essentially random." — JJ Simon

> "There is going to exist a statistically optimal risk and take profit for every single trade you take." — JJ Simon

---

## 14. Immediate action items (from the video)

- [ ] Build or extend the Python simulator to model prop-firm evals (trailing DD, daily loss, consistency) and ingest M1 OHLCV.
- [ ] Implement signal detection for DC, BoS, NR as pure functions that can be unit-tested on labelled candles.
- [ ] Acquire 6+ months of NQ M1 data (or NAS100 CFD) including news-event timestamps.
- [ ] Run the first 50-eval backtest with ONLY news reversions at 1:1.5 RR, no continuations, three-loss rule enforced. Record pass rate.
- [ ] Add displacement candles, then break of structure; measure each signal's contribution to pass rate independently before combining.
- [ ] Cost the funded account at the resulting pass rate (§10.2) and refuse to fund live accounts until EV > cost is established with a margin of safety.

---

## 15. Relationship to existing TRIAD-R / THE5ERS strategy stack

This repository already contains a session-event router (TRIAD-R) and an SMC sweep/CHoCH engine (E1). JJ's strategy is a **complementary** model, not a replacement. Differences and overlaps to be aware of when porting:

| Concern | TRIAD-R / E1 (current) | JJ Simon 1-min fair pricing |
|---|---|---|
| Timeframe | M5 / M15 primary | M1 only |
| Instrument | EURUSD, GBPUSD, XAUUSD, indices | NQ futures (single-instrument focus) |
| Edge model | SMC liquidity sweep → CHoCH → OB/FVG retest | Fair-price reversion after displacement/BoS/news |
| Session windows | London + NY kill zones | NY AM 90 min + NY PM 90 min only |
| RR model | Mixed (sweep entries use 1.5–2R; dual bracket limit in E1) | Strictly static, optimized per account type |
| Take-profit placement | Structure-based (opposite liquidity / FVG) | At fair price, mathematically paired with SL |
| Backtest metric | Equity curve | Pass rate across many simulated accounts |
| Account scaling | Single-account focused | Massive multi-account layering (45+ accounts) |
| News handling | Hard blackout (no trade) | Expected news = A+ trade; unexpected = wait for new consolidation |
| Kill switch | None formalised | Three consecutive losses = session over |

Integrating JJ's ideas into the existing stack should happen **only after** the pass-rate simulator validates the model in isolation. Concretely:
- The **three-loss rule** and **dead-zone enforcement** are directly portable as risk gates on every EA.
- The **static-RR-by-account-type** matrix is a better fit for THE5ERS challenge profiles than the existing 1.5R fixed value (which was chosen heuristically).
- **News reversions** as a positive-expected setup (instead of a hard blackout) warrant a separate research branch; E1 currently treats all news as "do not trade".
- **Pass-rate simulation** is the main methodological upgrade — current backtests look at equity curves of a single account, which JJ's math says is the wrong metric for prop-firm profitability.
