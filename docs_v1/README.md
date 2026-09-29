# Forex Quantitative Architecture & Strategy Roadmap: Index & Synthesis

This repository contains the complete quantitative research, algorithmic design, capital architecture, and falsification roadmap developed across the 5 Study Arena rounds and 6 advanced architecture blueprints.

---

## 📚 Complete Document Library (`docs/coreIdea/`)

### 1. Foundational Strategy & Arena Rounds
- **`strategy-recommendation.md`**: Master synthesis of the 5-round Study Arena. Defines Engine 1 (SMC Core), 1.0R stop loss, asymmetric exit ladder (1.5R/3R/runner), 0–10 setup grading, cluster risk budgeting, and the rolling $E_{50}$ edge decay monitor.
- **`max-roi-out-of-box-strategy.md`**: 3-Track Capital Allocation Factory (Track A: Eval Farming, Track B: Funded Harvesting, Track C: Personal Barbell C1/C2), anti-breach circuit breakers, and time-boxed capital velocity exits.
- **`studyarena-round1-*.md` to `studyarena-round5-*.md`**: Raw transcripts, debates, and peer audits between Contestants A, B, and C across all 5 evaluation rounds.

### 2. Advanced Architectural Blueprints
- **`asymmetric-alpha-matrix.md` (AAM)**: High-expectancy setups, DXY SMT divergence, 3-state volatility regime routing, and convex position compounding.
- **`adaptive-capital-matrix.md` (ACM)**: Multi-armed bandit dynamic allocation, 1/5th fractional Kelly sizing, eval promo arbitrage economics, and weekly macro/yield differential filters.
- **`apex-eigen-matrix.md` (AEM)**: PCA eigen-portfolio stat-arb, Ornstein-Uhlenbeck cointegration, continuous-time double-barrier first-hitting-time optimal sizing, and CME L2 order-flow proxies.
- **`omega-alpha-factory.md` (OAF)**: Genetic alpha breeding, Deflated Sharpe Ratio (DSR) selection gating, PPO meta-controller, and cross-asset lead-lag graph networks.
- **`sovereign-adversarial-matrix.md` (SAM)**: Execution hygiene, anti-adverse broker routing, latency jittering, payout-first equity retention, and Avellaneda-Stoikov inventory control.

### 3. Falsification Protocol & Operating Consensus
- **`micro-live-falsification-protocol.md` (MFP)**: The empirical "Operating System." Reality audit of all 12 theoretical claims, cost-as-%-of-R friction formulas, pre-registration protocol, and statistical sample-size hurdles.
- **`master-combination-strategy.md`**: **The definitive operating manual (v1.1 Safe-Hybrid).** Cross-evaluates all 8 blueprints with explicit **ADOPT**, **LATER**, and **DROP** decisions, and incorporates all 5 quantitative frontiers (Dual-Bracket limits, Daily HMM, Shadow ML, Native Macro feeds, and Cluster Risk Firewalls) in a robust, prop-compliant framework.
- **`roi-lever-scorecard.md`**: **The ROI ranking artifact.** Scores 15 candidate levers on 6 weighted dimensions with evidence-anchored 1–5 rubrics and a Return-vs-Ruin tension plot, ordered by *R/month per week of work*. Records ACM's 4-layer ROI hierarchy (Signal 15% / Allocation 30% / Structural 35% / Income 20%) and the four upgrades it produced.
- **`recommendations-and-next-steps.md`**: **The execution queue.** The 6 do-now $0 levers with their first actions, the gated levers with triggers, the 5 externally-proposed claims rejected with reasons (0.7R stop, 3% heat, trade copier, "uncorrelated pillars", $25k base case), and the full Risk Governor specification with acceptance tests.
- **`tri-pillar-review.md`**: **External proposal review.** Line-by-line verdict on the third-party "Tri-Pillar Prop-Scaler" — mapping it to our existing E1/E2/E4, what it got right, and its 6 defects ranked by damage.
- **`ruin-proofing-survival-budget.md`**: **The anti-blow-up document.** 16 failure modes with their controls, 5 real gaps found and fixed (news hold, weekend flat, broker-side stops, pre-trade assertions, kill-switch drill), the survival-budget arithmetic (worst streak ≈ 3.1% at 0.5% risk vs 9.3% at 1.5%), and a deterministic BLOCK/WARN go-live gate.
- **`preflight-risk-review.md`**: **Workflow boundary review** (5 gates: advice, venue/regulatory, data quality, security, privacy). 4 verified-absent FAILs — firm consistency rule, killzone timebase/DST, DXY proxy fidelity, override logging — plus 6 WARNs, the blocked-actions list, and mitigations M1–M6.

---

## 🧭 The Master Synthesis Summary

### 1. The Core Decision Hierarchy
```
                                 [ D8: Falsification Protocol ]
                            (Cost Audits, Pre-registration, Gates)
                                              │
                      ┌───────────────────────┴───────────────────────┐
                      ▼                                               ▼
          [ Capital Architecture ]                               [ Signal Core ]
         (D2: 3-Track Allocation)                             (D1: SMC + D3: SMT)
         - Track A: Eval Farm (0.5% risk)                     - E1: SMC Core (H4/M15)
         - Track B: Funded Harvest (0.4–0.5%)                 - E2: Asian Raid (07–10 GMT)
         - Track C: Personal Barbell (C1/C2)                  - E3: FVG Re-engagement
                      │                                       - E4: Dispersion Rank Book
                      │                                               │
                      └───────────────────────┬───────────────────────┘
                                              ▼
                                    [ Execution & Defense ]
                                 (D1: Staged Exits + D7: Hygiene)
                                 - 1.0R Hard SL, 25% at 1.5R/3R/Pool
                                 - Dead-Money Time Exits
                                 - Daily Loss Cap: -2.2% Hard Close
```

### 2. Verdict by Component
- **Adopt Immediately (v1.1 Safe-Hybrid)**:
  - Engines 1–4 (SMC, Asian Sweep, FVG re-engagement, Cross-major dispersion).
  - 1.0R hard stop with 4-stage exit ladder (+0.3R secured at 1.5R TP1).
  - **Dual-Bracket Limit Order Entry** (50% front / 50% equilibrium) to defeat slippage without triggering prop HFT spam flags.
  - **Daily Rollover HMM (23:55 GMT)** market regime classification.
  - **Shadow Mode ML Meta-Labeling** (logs features & predictions without interfering until 100 audited live trades).
  - **Native MT5 Macro Feeds** (DXY index and USOIL CFD proxies).
  - 3-Track capital allocation (Eval / Funded / Personal Barbell) with 4-zone barrier sizing.
  - Anti-breach circuit breakers (-2.2% daily halt, 4% equity DD freeze).
  - Pre-registered falsification ledger and cost-to-risk friction hurdle ($c \le 5\%$ of $R$).
- **Deferred to Defined Milestones (v2)**:
  - Active ML trade vetoing (requires $\ge 100$ live audited fills from Shadow Mode with AUC $> 0.65$).
  - Multi-armed bandit allocation (requires $\ge 2$ engines with $\ge 30$ live trades).
  - 1/5-Kelly meta-sizing (requires $\ge 300$ logged live executions).
  - PCA/OU stat-arb & Genetic alpha breeder (activates if live edge decay $E_{50} < 0$).
- **Dropped**:
  - Overfitted backtest projections (50%+ win-rate claims pruned to audited 40% base).
  - Micro-scalping with stops $< 25$ pips ($> 5\text{--}14\%$ friction leakage).
  - Counterparty evasion hacks (Poisson jittering) risking payout forfeiture.
  - Fragile external 3rd-party bond APIs and unstable real-time matrix inversions.

---

## 🛠️ Implementation Queue
1. **Cost-Reality Audit**: Log 100 fills on target broker to verify spread/commission friction on $R$.
2. **Circuit Breakers**: Implement `-2.2%` daily equity halt and max portfolio heat cap (`4%` personal, `2%` funded) before any entry logic.
3. **Daily HMM Script**: Deploy the 23:55 GMT Python classifier script to output regime state flags.
4. **Shadow ML Logger**: Attach the 20-feature snapshot recorder to the execution module.
5. **Engine 1 Validation**: Pre-register experiment `MFP-001` on micro-live feed with Dual-Bracket limits.
