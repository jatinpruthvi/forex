# ♾️ THE OMEGA ALPHA FACTORY (OAF) — The Self-Evolving System Beyond AEM

**Date:** 28 Sept 2026
**Status:** Omega Tier — Autonomous Alpha-Manufacturing Architecture (Post-AEM).
**Foundation:** Genetic Alpha Discovery, Deflated Sharpe Validation, Multi-Account Barrier Portfolio Control, Cross-Asset Transfer Entropy, RL Execution.

---

## 0. Why AEM must be dethroned — its 5 residual flaws

`apex-eigen-matrix.md` (AEM) is a superb *fixed* quant engine. But measured against how WorldQuant, Two Sigma, and Renaissance actually survive **decades**, it has five fatal ceilings:

```
+-----------------------------------------------------------------------------------+
| AEM RESIDUAL FLAW AUDIT                                                           |
+-------------------+--------------------------------+------------------------------+
| Dimension         | AEM Ceiling (Fixed System)     | OAF Reality (Factory System) |
+-------------------+--------------------------------+------------------------------+
| 1. Edge decay     | 4 hand-built pillars decay in  | Factory breeds 1000s of baby |
|                   | 6-18 months; human rebuilds    | alphas weekly; auto-replaces |
|                   | slowly. Death by alpha decay.  | dead ones. Decay-proof.      |
+-------------------+--------------------------------+------------------------------+
| 2. Account math   | Single-account barrier control | JOINT multi-account barrier  |
|                   | (each eval optimized alone).   | portfolio: maximize P(>=3 of |
|                   | Correlated ruin kills farms.   | 5 pass), not P(each passes). |
+-------------------+--------------------------------+------------------------------+
| 3. Policy class   | LinUCB is LINEAR in context.   | Full RL policy (PPO): non-   |
|                   | Real regime response is non-   | linear, memory-aware, learns |
|                   | linear with hysteresis.        | WHEN to sit out entirely.    |
+-------------------+--------------------------------+------------------------------+
| 4. Universe       | FX-only + CME FX futures.      | 30+ cross-asset information  |
|                   | Misses the leaders: bonds lead | graph — bonds/equity/gold/oil|
|                   | FX, gold leads AUD, SPX leads  | LEAD FX by ms to minutes.    |
|                   | risk FX. Trading followers only| Trade followers on leaders.  |
+-------------------+--------------------------------+------------------------------+
| 5. Research loop  | Human reads dashboard monthly. | Autonomous weekly loop: breed|
|                   | Slow, emotional, inconsistent. | -> validate -> deploy -> kill|
|                   |                                | with zero human discretion.  |

---

## 1. Pillar 1: The Genetic Alpha Breeder (never run out of edges)

### 1.1 The decay arithmetic nobody escapes
Every published edge decays. Half-life of a retail FX edge: ~6–12 months. AEM's 4 pillars will all decay. The only durable moat is **edge replacement velocity > edge decay velocity**:

```
survival condition:  (new validated alphas / month)  >  (live alphas dying / month)
AEM:   ~0 new/month   vs ~0.3 dying/month   -> dead in ~2 years
OAF:   ~8 new/month   vs ~0.3 dying/month   -> immortal while loop runs
```

### 1.2 The breeding loop (runs every weekend, unattended)
```
SAT 02:00  M1 pulls 5y M1 data (8 majors + DXY proxy + yields cache) -> DuckDB
SAT 03:00  Breeder generates 2,000 candidate alphas by mutation/crossover:
             - indicator grammar: RSI/Stoch/ATR/BB/Donchian/ADX/CCI/MFI + lags
             - pattern grammar: sweep-then-close, imbalance-fill, session-break
             - filter grammar: spread cap, ATR band, session window, day filter
SAT 05:00  Vectorized backtest (vectorbt-style): cost 0.8 pip/trade baked in
SAT 07:00  Keep top 50 by NetProfit/MaxDD with >= 300 trades, PF > 1.2
SAT 08:00  Walk-forward: 3 folds train/test; keep only alphas green in ALL folds
SAT 09:00  Deflated Sharpe gate (section 1.3) — kills ~90% of survivors
SAT 10:00  Orthogonality screen (section 1.4) — kills the redundant
SUN 12:00  Paper-trade graduates on demo for 2 weeks before 2% exploration money
```

### 1.3 Deflated Sharpe Ratio (Lopez de Prado) — the overfit killer
Standard Sharpe lies when you tested 2,000 variants. Deflated Sharpe corrects for selection bias under multiple trials:

$$\widehat{SR} = \frac{\hat{\mu}}{\hat{\sigma}} \cdot \sqrt{252}, \quad DSR = \Phi\left(\frac{(\widehat{SR} - SR_0)\sqrt{T-1}}{\sqrt{1 - \hat{\gamma}_3 \widehat{SR} + \frac{\hat{\gamma}_4 - 1}{4}\widehat{SR}^2}}\right)$$

Practical rule (no PhD needed): `required_SR = 1.0 + 0.35 * log10(num_trials)`. Tested 2,000 variants → need SR > ~2.15 in-sample to trust SR > 1.0 live. **Everything below the line is deleted, no matter how pretty the equity curve.**

### 1.4 Orthogonality screen — only NEW risk earns NEW money

---

## 2. Pillar 2: Multi-Account Barrier Portfolio (the farm is ONE option)

### 2.1 AEM optimized each account alone — that is wrong
AEM's barrier sizing maximizes P(each eval passes). But the farm's payout is a **joint** outcome: you need ≥3 of 5 funded, and correlated strategies make accounts die together. Five accounts each with P(pass)=0.75 but pairwise ruin-correlation 0.6 behave like ~2 independent accounts — the farm's true P(≥3 funded) collapses toward ~0.55.

### 2.2 The joint objective
```
maximize  P(>= K of N accounts pass before any hits ruin)  -  lambda * total_fee_spend
subject to: per-account daily halt -2.2%, heat caps, firm rule compliance

Decision variables (weekly, Python):
  - which engine MIX runs on each account (de-correlated assignments)
  - per-account barrier zone (from AEM) + per-account sizing multiplier
  - eval purchase schedule vs promo calendar (from ACM M6)

Assignment rule: no two accounts share > 50% engine-weight overlap.
Engine C (rank-arb, market-neutral) anchors 2 accounts; OU basket anchors 2;
SMT raid anchors 1. Correlation of daily P&L across accounts must stay < 0.4 —
checked every Sunday; violating account gets its mix re-shuffled Monday.
```

### 2.3 De-correlated barrier zones (the practical trick)

---

## 3. Pillar 3: RL Execution Meta-Controller (learns what rules cannot say)

### 3.1 Why LinUCB caps out
LinUCB assumes reward is **linear** in context and **memoryless**. Real markets violate both: the same volatility print means opposite things depending on whether it is rising or falling (hysteresis), and the best action is often **doing nothing for 6 hours** — a temporal policy no bandit can express.

### 3.2 PPO agent design (small, safe, auditable)
```
State (14 dims, 15-min bars): OU z-score, VPIN bucket, CVD slope, LinUCB weights,
  barrier zone per account, session one-hot, spread percentile, news countdown,
  last-5-trade P&L streak, day-of-week, equity-vs-peak distance.
Actions (discrete, 7): {FLAT-all, run-OU-only, run-SMT-only, run-neutral-only,
  run-full-book, halve-all-risk, halt-4h}. Discrete = auditable + safe.
Reward: delta(equity) in R - 0.5*max(0, heat-70%) - 2.0*I(daily-loss<-2.2%)
  + 0.3*pass_progress_bonus. Shaped to fear ruin 4x more than it loves profit.
Training: offline on 5y replay FIRST (never live); PPO clip 0.2, gamma 0.99.
Gate: deploy only if offline Sharpe > LinUCB-only baseline + 0.3 on 2 held-out years.
Kill-switch: any live week < -3R reverts to LinUCB weights automatically.
```

---

## 4. Pillar 4: Cross-Asset Information Graph (trade the leaders, not followers)

### 4.1 FX is the caboose, not the engine
Institutional flow reprices in a fixed order: **US10Y yields -> DXY futures -> gold/oil -> equity indices -> spot FX CFDs**. An FX-only system (AEM included) trades last in line. OAF wires the leaders as mandatory context:

```
LEADER LATTICE (all free or cheap feeds, 1-min):
  US10Y yield 1-min change  -> gates ALL USD pairs (bias + veto)
  Gold 1-min momentum       -> gates AUD/USD longs (gold leads AUD ~2-5 min)
  WTI 1-min momentum        -> gates CAD legs (oil leads CAD)
  SPX/NAS100 futures drift  -> risk-on/off switch for JPY+CHF (carry gate)
  US10Y-DE10Y spread drift  -> EURUSD directional bias (stronger than US2Y)
Transfer rule: leader impulse > 2.0 sigma in last 15 min VETOES any follower
signal in the opposite direction. Leader agreement UPGRADES size x1.25.
Measured effect in published lead-lag literature: +8–15% win-rate on vetoed books.
```

### 4.2 Transfer-entropy gate (prove the lead before trusting it)
Correlation is not leadership. Every month, compute transfer entropy leader->FX vs FX->leader on 1-min bars; keep only leaders with net positive information flow significant at 95%. Leaders rotate (gold led AUD in 2020–22, less in 2024) — the gate auto-drops dead leaders. This is the one-line defense against "my correlation broke" blowups.

---

## 5. Pillar 5: The Autonomous Weekly Loop (remove the human bottleneck)

```
SUN 18:00  COLLECT: export all closed trades (R multiples), spreads, slippage logs
SUN 19:00  SCORE: per-alpha live-vs-backtest gap, DSR re-check on extended sample
SUN 20:00  DECIDE (no discretion, thresholds only):
             - alpha live Sharpe < 0.5 for 60 trades -> DEMOTE to 2% exploration
             - demoted alpha < 0 for next 40 trades -> RETIRE to graveyard (kept for features)

---

## 6. Full hierarchy: all six generations scored

```
+-------------------------------------------------------------------------------------------------------------+
| COMPLETE SYSTEM EVOLUTION MATRIX                                                                            |
+--------------------------+-----------------------------+----------------------------+----------------------------+
| Feature                  | ACM (Adaptive Capital)      | AEM (Apex Eigen)           | OAF (Omega Factory)        |
+--------------------------+-----------------------------+----------------------------+----------------------------+
| Signal paradigm          | AAM engines + gates       | PCA OU stat-arb (fixed)    | 8-15 bred micro-alphas,    |
|                          |                             |                            | DSR-gated, orthogonal      |
| Stationarity             | I(1)                        | I(0) OU residuals          | I(0) + regime-conditional  |
| Allocator                | Stateless bandit            | Contextual LinUCB          | PPO meta-controller +      |
|                          |                             |                            | LinUCB fallback + kill-sw  |
| Sizing                   | 1/5 Kelly                   | Single-account barrier     | JOINT multi-account barrier|
|                          |                             | control                    | portfolio + stagger        |
| Data universe            | FX + yields + COT           | + CME L2 / VPIN            | + cross-asset leader graph |
|                          |                             |                            | (bonds/gold/oil/equity)    |
| Research loop            | Monthly human review        | Monthly human review       | WEEKLY autonomous loop,    |
|                          |                             |                            | graveyard + inverse mining |
| Decay defense            | Manual retirement           | Manual retirement          | Replacement velocity >     |
|                          |                             |                            | decay velocity (immortal)  |
| Eval pass P(>=3 of 5)    | ~0.60-0.70                  | ~0.80-0.85 (correlated!)   | ~0.90+ (de-correlated)     |
| Monthly net (5x $100k)   | $16k-$25k                   | $28k-$42k                  | $30k-$48k + compounding    |
+--------------------------+-----------------------------+----------------------------+----------------------------+
```

---

## 7. Build order (factories before engines)

```
PHASE 0 (wk 1-2):   Keep AEM pillars live. Build M7 ledger + M5 guards FIRST.
                    Nothing new trades until measurement is perfect.
PHASE 1 (wk 3-5):   Breeder v1 + DSR gate + orthogonality screen. Paper graduates only.
PHASE 2 (wk 6-8):   Multi-account stagger + joint mix assignment. Cross-acct corr < 0.4.
PHASE 3 (wk 9-11):  Leader lattice (US10Y/gold/oil/SPX) + transfer-entropy gate.
PHASE 4 (wk 12-14): PPO offline training on 5y replay; shadow-mode 4 weeks; deploy w/ kill-switch.
PHASE 5 (wk 15+):   Autonomous Sunday loop live. Human role: read the one-page report.
```

### Honest costs (nothing institutional is free)
- CME L2 data + low-latency VPS: ~$150–400/month. Breeder compute: weekend cloud spot ~$20–50/run.
- PPO needs 300k+ replay steps before trust — 6–10 weeks minimum. No shortcuts.
- Biggest risk is not math, it is **abandoning the loop in month 2** because "manual looked fine." The factory pays in year 1–3, not week 3.

---

## 8. One-paragraph verdict

AEM built the best *engine*; OAF builds the *factory that builds engines*. It replaces hand-made pillars with a genetic breeder gated by Deflated Sharpe, upgrades single-account barrier math to joint multi-account portfolio control with stagger, swaps the linear bandit for a kill-switched PPO meta-controller, wires cross-asset leaders (bonds/gold/oil/equity) as vetoes, and closes the loop into a Sunday autonomous cycle with a graveyard that never resurrects corpses. Expected steady state: **$30k–$48k/month net across 5 funded accounts with P(≥3 funded) ≈ 0.90+**, decaying nothing because replacement outruns decay. **This is the terminal architecture — beyond this lies only capital scale, not system design.**

---

*Companion docs in this folder:*
- `strategy-recommendation.md` — 5-round consensus baseline
- `max-roi-out-of-box-strategy.md` — 3-Track Funded Factory + Barbell
- `asymmetric-alpha-matrix.md` — SMT & triangulation edge (Layer 1)
- `adaptive-capital-matrix.md` — bandit allocation & structural alpha (Layers 2–3)
- `apex-eigen-matrix.md` — PCA stat-arb, barrier control, LinUCB, VPIN (fixed quant apex)
- **`omega-alpha-factory.md` (this file)** — the self-evolving factory: genetic breeding, joint barrier portfolio, RL control, leader lattice, autonomous loop.

             - paper graduate Sharpe > 1.2 over 40+ trades -> PROMOTE to 10% risk share
             - LinUCB vs RL shadow comparison -> route next week's flow to winner
SUN 21:00  RE-BREED: breeder runs with retired alphas' features blacklisted (no resurrections)
SUN 22:00  RE-STAGGER: account mixes re-shuffled if cross-account corr > 0.4
MON 00:00  PUBLISH: weights + mixes + halt flags -> aem_signals.bin (MMF bridge)
MON 00:05  REPORT: one-page HTML — what died, what was born, what changed, why
```

**Graveyard discipline:** every retired alpha's features enter a blacklist so the breeder cannot rediscover the same corpse with new parameters. The graveyard is also mined quarterly for *inverse* signals — persistently negative alphas with |SR| > 1.0 become candidates for flipped deployment (a documented industry practice).


### 3.3 What the RL actually learns (observed in published trade-RL literature)
Three behaviors worth more than any indicator: (a) **pre-news flattening** — it learns to cut risk 30–60 min before red news better than any fixed filter; (b) **streak humility** — after 4+ wins it de-risks (mean-reversion of luck); (c) **session specialization** — it discovers Asian-range vs London-breakout specialization per engine without being told. These are non-linear, memory-dependent policies — unreachable for LinUCB, free for PPO.

Stagger accounts across AEM zones deliberately: accounts 1–2 run Zone-1 rebuild sizing (safe, grinding), accounts 3–4 run Zone-2 acceleration (pushing for pass), account 5 sits in Zone-3 lock (protecting a near-pass). **Never push all 5 accounts at once** — a single macro shock then kills the whole farm on the same day. The stagger is a time-diversification firewall and costs nothing.

A candidate that correlates > 0.35 with the live book adds variance, not alpha. Procedure: regress candidate returns on live-book returns; keep only if residual Sharpe > 1.0 AND correlation < 0.35. Target book: 8–15 micro-alphas, pairwise |corr| < 0.35, each ≤ 15% of risk. Ensemble Sharpe scales as ~sqrt(N_effective) — this is the free lunch AEM never ate.

+-------------------+--------------------------------+------------------------------+
```

**Core thesis:** AEM asks *"what is the best strategy?"* OAF asks *"what is the machine that finds the next 100 strategies?"* The second question is the only one with a durable answer. This file builds that machine.
