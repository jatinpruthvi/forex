# Expert Advisor (EA) Implementation Tracker

**Repository:** `jatinpruthvi/forex`  
**Master Directory:** `MQL5_Master/`  
**Last Updated:** 2026-10-01  
**Status Overview:**
- **Total EAs Tracked:** 79
- **Finished & Fully Compiled (0 Errors):** 14
- **Pending Implementation (Scaffolds / Templates):** 65

---

## 1. Finished & Compiled EAs (Ready for Testing)

All finished EAs have been compiled directly with MetaEditor 64 into `.ex5` binaries with 0 errors and 0 warnings. Each utilizes an isolated `InpMagicNumber` and is protected by institutional risk frameworks.

| # | EA File Name | Associated Document | Magic Number | Key Logic / Architectural Edge Implemented | Binary (`.ex5`) |
|---|---|---|---|---|---|
| **1** | `Master_Triad_V1.mq5` | `THE-ULTIMATE-COMBINED-STRATEGY.md` | `777112` (Dynamic Input) | **Full Production Triad:** SMC Core (M15 sweeps, CHoCH, OBs), H4 EMA trend bias, DXY SMT divergence, Risk Governor (4.5% daily DD, Friday EET 22:45 close), Execution Manager (Dual-Bracket, 45m dead money exit, +1.5R partials), News Manager (live ForexFactory feed). | `Master_Triad_V1.ex5` |
| **2** | `EA_adaptive_capital_matrix.mq5` | `adaptive-capital-matrix.md` | `1000` | **Asynchronous JSON Bridge:** Reads `acm_weights.json` from `Common/Files` hourly via timer thread. Dynamically scales risk per engine & master Kelly multiplier. Failsafe auto-degrades to 0.33 equal weight / 0.6x risk on stale file (>24h). | `EA_adaptive_capital_matrix.ex5` |
| **3** | `EA_apex_eigen_matrix.mq5` | `apex-eigen-matrix.md` | `1001` | **First-Hitting-Time Optimal Control:** Replaces flat sizing with 4 dynamic account distance zones: Zone 0 Defense (0.25% risk), Zone 1 Neutral (0.50%), Zone 2 Convex Acceleration (1.20%), and Zone 3 Target Lock (throttles to <=0.20% near pass target). | `EA_apex_eigen_matrix.ex5` |
| **4** | `EA_asymmetric_alpha_matrix.mq5` | `asymmetric-alpha-matrix.md` | `1002` | **Convex Payoff Pyramiding & Hard Day Guard:** Halts trading at `-2.2%` daily loss. Continuously monitors open trades; at `+2.0R`, locks Stop Loss to `+1.0R` (risk-free) and unlocks secondary positions funded entirely by market money. | `EA_asymmetric_alpha_matrix.ex5` |
| **5** | `EA_master_combination_strategy.mq5` | `master-combination-strategy.md` | `1003` | **Deterministic USD Netting & Dual-Bracket:** Enforces `Net USD Cap <= 1.5%` portfolio-wide across open positions. Executes 50/50 Dual-Bracket (Front edge + 50% OB equilibrium limit) and auto-cancels pending equilibrium if front reaches +1.0R. | `EA_master_combination_strategy.ex5` |
| **6** | `EA_max_roi_out_of_box_strategy.mq5` | `max-roi-out-of-box-strategy.md` | `1004` | **Prop Firm Exam Protocol:** Blocks XAUUSD, blocks Friday trades, enforces London (07-10) and NY (13-16) Killzones only, caps positions at 2. Features "8% in 20 days" schedule: throttles risk to 0.40% at +4% equity and 0.25% at +6% equity. | `EA_max_roi_out_of_box_strategy.ex5` |
| **7** | `EA_micro_live_falsification_protocol.mq5` | `micro-live-falsification-protocol.md` | `1005` | **Shadow Mode Evidence Ledger:** Zero-capital verification mode. Intercepts all trade signals and writes theoretical entries to `MFP_Evidence_Ledger.csv` without placing broker orders until statistical edge is proven. | `EA_micro_live_falsification_protocol.ex5` |
| **8** | `EA_omega_alpha_factory.mq5` | `omega-alpha-factory.md` | `1006` | **Multi-Account Barrier Staggering:** Implements `InpFarmGroupId` (1 to 5) across account farms. Staggers risk profiles (Vanguard 1.0x, Stagger 0.8x, Aggressive 1.2x, Delayed 0.5x, Reserve 0.25x) to prevent simultaneous correlated ruin. | `EA_omega_alpha_factory.ex5` |
| **9** | `EA_preflight_risk_review.mq5` | `preflight-risk-review.md` | `1007` | **Payout Protection & Stale Feed Guard:** Halts daily trading if floating gains touch `+4.0%` to prevent violating prop-firm consistency/max-day rules. Rejects orders if quote ticks are older than 60 seconds (feed latency guard). | `EA_preflight_risk_review.ex5` |
| **10** | `EA_recommendations_and_next_steps.mq5` | `recommendations-and-next-steps.md` | `1008` | **Heat Redistribution & Grade Sizing:** Implements `r_i = H / sqrt(1 + rho)` to allocate headroom to uncorrelated setups. Differentiates Personal accounts (ratchets A-grade setups up to 1.25%) vs Funded accounts (strictly filters C-grades). | `EA_recommendations_and_next_steps.ex5` |
| **11** | `EA_ruin_proofing_survival_budget.mq5` | `ruin-proofing-survival-budget.md` | `1010` | **Deterministic Delivery Gates:** Zero AI inference pre-trade gates. Strictly validates live spread against `InpMaxSpreadPoints` and halts execution if `ACCOUNT_MARGIN_LEVEL` falls below a 250% safety floor. | `EA_ruin_proofing_survival_budget.ex5` |
| **12** | `EA_sovereign_adversarial_matrix.mq5` | `sovereign-adversarial-matrix.md` | `1012` | **Counterparty / B-Book Evasion:** Enforces a minimum hold time of 180 seconds to avoid broker latency-arbitrage flags. Injects randomized execution jitter (up to 1500 ms) to disguise multi-account copy clustering. | `EA_sovereign_adversarial_matrix.ex5` |
| **13** | `EA_strategy_recommendation.mq5` | `strategy-recommendation.md` | `1013` | **Timeframe Cascade Engine:** Enforces multi-timeframe structural consensus. Confirms D1 200 EMA trend and H4 50 EMA structure alignment before permitting M15/M1 execution. Blocks all trades during mixed higher-timeframe chop. | `EA_strategy_recommendation.ex5` |
| **14** | `EA_studyarena_round1_contestant_a.mq5` | `studyarena-round1-contestant-a.md` | `1014` | **20% ROI Math Enforcer:** Validates the exact arithmetic necessary for 20%/month. Calculates real-time pip distance and strictly blocks any setup where the Risk-to-Reward ratio is below `1:3.0`. | `EA_studyarena_round1_contestant_a.ex5` |

---

## 2. Pending EAs (Scaffolds / Templates Awaiting Logic Conversion)

These 65 EAs currently exist as isolated boilerplate templates in `MQL5_Master/Experts/additionalEAs/`. Each already possesses an assigned unique `InpMagicNumber` and is ready for specific strategy logic insertion.

### A. Core Strategy & Prop Firm Challenge Documents (`docs/strategy/`, `docs/prop_firm/`)

| # | EA File Name | Source Document | Assigned Magic | Status |
|---|---|---|---|---|
| 15 | `EA_FINAL_OPTIMUM_STRATEGY.mq5` | `docs/strategy/FINAL_OPTIMUM_STRATEGY.md` | `1000` | PENDING |
| 16 | `EA_THE5ERS_CHALLENGE_STRATEGY_V2.mq5` | `docs/strategy/THE5ERS_CHALLENGE_STRATEGY_V2.md` | `1001` | PENDING |
| 17 | `EA_THE5ERS_CHALLENGE_OPTIMIZATION.mq5` | `docs/prop_firm/THE5ERS_CHALLENGE_OPTIMIZATION.md` | `1002` | PENDING |
| 18 | `EA_THE5ERS_2_5K_CHALLENGE_PLAN.mq5` | `docs/prop_firm/THE5ERS_2_5K_CHALLENGE_PLAN.md` | `1003` | PENDING |
| 19 | `EA_THE5ERS_CHALLENGE_V2_REVALIDATION.mq5` | `docs/prop_firm/THE5ERS_CHALLENGE_V2_REVALIDATION.md` | `1004` | PENDING |
| 20 | `EA_THE5ERS_END_TO_END_PRECODE_CHECKLIST.mq5` | `docs/prop_firm/THE5ERS_END_TO_END_PRECODE_CHECKLIST.md` | `1005` | PENDING |
| 21 | `EA_THE5ERS_HIGH_STAKES_RESEARCH.mq5` | `docs/prop_firm/THE5ERS_HIGH_STAKES_RESEARCH.md` | `1006` | PENDING |
| 22 | `EA_THE5ERS_PROPOSAL_REVIEW.mq5` | `docs/prop_firm/THE5ERS_PROPOSAL_REVIEW.md` | `1007` | PENDING |
| 23 | `EA_THE5ERS_STRATEGY_IMPROVEMENT_SUGGESTION_REVIEW.mq5` | `docs/prop_firm/THE5ERS_STRATEGY_IMPROVEMENT_SUGGESTION_REVIEW.md` | `1008` | PENDING |
| 24 | `EA_TRIAD_R_HS_CODE_REVIEW.mq5` | `docs/prop_firm/TRIAD_R_HS_CODE_REVIEW.md` | `1009` | PENDING |
| 25 | `EA_TRIAD_SURVIVE.mq5` | `docs/prop_firm/TRIAD_SURVIVE.md` | `1010` | PENDING |
| 26 | `EA_Pr10_Roi_Improvements.mq5` | `docs/strategy/Pr10_Roi_Improvements.md` | `1011` | PENDING |
| 27 | `EA_progress.mq5` | `docs/strategy/progress.md` | `1012` | PENDING |
| 28 | `EA_prop_fund_challenge_improvement_plan.mq5` | `docs/strategy/prop_fund_challenge_improvement_plan.md` | `1013` | PENDING |
| 29 | `EA_strategy_improvements_plan.mq5` | `docs/strategy/strategy_improvements_plan.md` | `1014` | PENDING |
| 30 | `EA_STRATEGY_PORTFOLIO_AUDIT.mq5` | `docs/strategy/STRATEGY_PORTFOLIO_AUDIT.md` | `1015` | PENDING |
| 31 | `EA_STRATEGY_ROADMAP.mq5` | `docs/strategy/STRATEGY_ROADMAP.md` | `1016` | PENDING |

### B. Study Arena AI Contestant Documents (`docs/research/study_arena/` & `docs_v1/docs/coreIdea/`)

| # | EA File Name | Source Document | Assigned Magic | Status |
|---|---|---|---|---|
| 32 | `EA_studyarena_round1_contestant_b.mq5` | `studyarena-round1-contestant-b.md` | `2001` | PENDING |
| 33 | `EA_studyarena_round1_contestant_c.mq5` | `studyarena-round1-contestant-c.md` | `2002` | PENDING |
| 34 | `EA_studyarena_round2_contestant_a.mq5` | `studyarena-round2-contestant-a.md` | `2003` | PENDING |
| 35 | `EA_studyarena_round2_contestant_b.mq5` | `studyarena-round2-contestant-b.md` | `2004` | PENDING |
| 36 | `EA_studyarena_round2_contestant_c.mq5` | `studyarena-round2-contestant-c.md` | `2005` | PENDING |
| 37 | `EA_studyarena_round3_contestant_a__1_.mq5` | `studyarena-round3-contestant-a.md` | `2006` | PENDING |
| 38 | `EA_studyarena_round3_contestant_b__1_.mq5` | `studyarena-round3-contestant-b.md` | `2007` | PENDING |
| 39 | `EA_studyarena_round4_contestant_a__1_.mq5` | `studyarena-round4-contestant-a.md` | `2008` | PENDING |
| 40 | `EA_studyarena_round4_contestant_b.mq5` | `studyarena-round4-contestant-b.md` | `2009` | PENDING |
| 41 | `EA_studyarena_round4_contestant_b__1_.mq5` | `studyarena-round4-contestant-b (1).md` | `2010` | PENDING |
| 42 | `EA_studyarena_round4_contestant_c.mq5` | `studyarena-round4-contestant-c.md` | `2011` | PENDING |
| 43 | `EA_studyarena_round4_contestant_c__1_.mq5` | `studyarena-round4-contestant-c (1).md` | `2012` | PENDING |
| 44 | `EA_studyarena_round4_contestant_d.mq5` | `studyarena-round4-contestant-d.md` | `2013` | PENDING |
| 45 | `EA_studyarena_round4_contestant_e.mq5` | `studyarena-round4-contestant-e.md` | `2014` | PENDING |
| 46 | `EA_studyarena_round4_contestant_f.mq5` | `studyarena-round4-contestant-f.md` | `2015` | PENDING |
| 47 | `EA_studyarena_round5_contestant_a.mq5` | `studyarena-round5-contestant-a.md` | `2016` | PENDING |
| 48 | `EA_studyarena_round5_contestant_a_2047.mq5` | `studyarena-round5-contestant-a.md` | `2047` | PENDING |
| 49 | `EA_studyarena_round5_contestant_b.mq5` | `studyarena-round5-contestant-b.md` | `2017` | PENDING |
| 50 | `EA_studyarena_round5_contestant_b_2048.mq5` | `studyarena-round5-contestant-b.md` | `2048` | PENDING |
| 51 | `EA_studyarena_round5_contestant_c.mq5` | `studyarena-round5-contestant-c.md` | `2018` | PENDING |
| 52 | `EA_studyarena_round5_contestant_d.mq5` | `studyarena-round5-contestant-d.md` | `2019` | PENDING |
| 53 | `EA_studyarena_round5_contestant_e.mq5` | `studyarena-round5-contestant-e.md` | `2020` | PENDING |
| 54 | `EA_studyarena_round5_contestant_f.mq5` | `studyarena-round5-contestant-f.md` | `2021` | PENDING |
| 55 | `EA_studyarena_round7_contestant_a.mq5` | `studyarena-round7-contestant-a.md` | `2022` | PENDING |
| 56 | `EA_studyarena_round7_contestant_b.mq5` | `studyarena-round7-contestant-b.md` | `2023` | PENDING |
| 57 | `EA_studyarena_round7_contestant_c.mq5` | `studyarena-round7-contestant-c.md` | `2024` | PENDING |
| 58 | `EA_studyarena_round7_contestant_d.mq5` | `studyarena-round7-contestant-d.md` | `2025` | PENDING |
| 59 | `EA_studyarena_round8_contestant_a.mq5` | `studyarena-round8-contestant-a.md` | `2026` | PENDING |
| 60 | `EA_studyarena_round8_contestant_b.mq5` | `studyarena-round8-contestant-b.md` | `2027` | PENDING |
| 61 | `EA_studyarena_round8_contestant_c.mq5` | `studyarena-round8-contestant-c.md` | `2028` | PENDING |
| 62 | `EA_studyarena_round8_contestant_d.mq5` | `studyarena-round8-contestant-d.md` | `2029` | PENDING |
| 63 | `EA_studyarena_round10_claude_fable_5_high_reasoning.mq5` | `studyarena-round10-claude-fable-5-high-reasoning.md` | `2030` | PENDING |
| 64 | `EA_studyarena_round10_claude_opus_5_high_reasoning.mq5` | `studyarena-round10-claude-opus-5-high-reasoning.md` | `2031` | PENDING |
| 65 | `EA_studyarena_round10_gemini_3_1_pro_preview_high_reasoning.mq5` | `studyarena-round10-gemini-3-1-pro-preview-high-reasoning.md` | `2032` | PENDING |
| 66 | `EA_studyarena_round10_kimi_k3_high_reasoning.mq5` | `studyarena-round10-kimi-k3-high-reasoning.md` | `2033` | PENDING |
| 67 | `EA_studyarena_round10_qwen3_8_2_4t_a95b_high_reasoning.mq5` | `studyarena-round10-qwen3-8-2-4t-a95b-high-reasoning.md` | `2034` | PENDING |
| 68 | `EA_studyarena_round11_contestant_a.mq5` | `studyarena-round11-contestant-a.md` | `2035` | PENDING |
| 69 | `EA_studyarena_round11_contestant_b.mq5` | `studyarena-round11-contestant-b.md` | `2036` | PENDING |
| 70 | `EA_studyarena_round11_contestant_c.mq5` | `studyarena-round11-contestant-c.md` | `2037` | PENDING |
| 71 | `EA_studyarena_round11_contestant_d.mq5` | `studyarena-round11-contestant-d.md` | `2038` | PENDING |
| 72 | `EA_studyarena_round11_contestant_e.mq5` | `studyarena-round11-contestant-e.md` | `2039` | PENDING |
| 73 | `EA_studyarena_round11_contestant_f.mq5` | `studyarena-round11-contestant-f.md` | `2040` | PENDING |
| 74 | `EA_studyarena_round12_claude_fable_5_high_reasoning.mq5` | `studyarena-round12-claude-fable-5-high-reasoning.md` | `2041` | PENDING |
| 75 | `EA_studyarena_round12_contestant_a.mq5` | `studyarena-round12-contestant-a.md` | `2042` | PENDING |
| 76 | `EA_studyarena_round12_contestant_b.mq5` | `studyarena-round12-contestant-b.md` | `2043` | PENDING |
| 77 | `EA_studyarena_round12_contestant_c.mq5` | `studyarena-round12-contestant-c.md` | `2044` | PENDING |
| 78 | `EA_studyarena_round12_contestant_f.mq5` | `studyarena-round12-contestant-f.md` | `2045` | PENDING |
| 79 | `EA_studyarena_round12_qwen3_8_2_4t_a95b_high_reasoning.mq5` | `studyarena-round12-qwen3-8-2-4t-a95b-high-reasoning.md` | `2046` | PENDING |

---

## 3. Directory Structure

```
forex/
├── MQL5_Master/
│   ├── Experts/
│   │   ├── Master_Triad_V1.mq5         # Production Master Engine (Compiled)
│   │   ├── Master_Triad_V1.ex5         # Production Binary
│   │   └── additionalEAs/              # 13 Finished EAs + 65 Pending Strategy EAs
│   │       ├── EA_*.mq5
│   │       └── EA_*.ex5                # Compiled binaries for finished EAs
│   └── Include/
│       ├── E1_SMC_Core.mqh             # SMC sweep + CHoCH + OB engine
│       ├── ExecutionManager.mqh        # Dual-bracket + staged exits + time stops
│       ├── NewsManager.mqh             # Live XML news ingestion + blackout
│       └── RiskGovernor.mqh            # Breakers + prop-firm capital governor
└── docs/
    └── EA_IMPLEMENTATION_TRACKER.md    # This file
```

---

## 4. How to Test & Deploy

1. **Production Full Strategy:** Launch MetaTrader 5 and select `Master_Triad_V1` in the Strategy Tester. It runs all symbols concurrently with the fully integrated risk and execution engine.
2. **Specialized Module EAs:** To backtest or forward-test individual architectural breakthroughs (e.g. `EA_apex_eigen_matrix` or `EA_max_roi_out_of_box_strategy`), select that specific EA in the Strategy Tester.
3. **Compiling Pending EAs:** Once a pending EA's `OnTick()` execution logic is coded, compile it using MetaEditor 64:
   ```powershell
   & "C:\Program Files\Fusion Markets MetaTrader 5\metaeditor64.exe" /compile:"E:\Jatin-Project\Forex\forex\MQL5_Master\Experts\additionalEAs\EA_name.mq5" /log
   ```
