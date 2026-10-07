# Expert Advisor (EA) Implementation Tracker

**Repository:** `jatinpruthvi/forex`  
**Master Directory:** `MQL5_Master/`  
**Last Updated:** 2026-10-01  
**Status Overview:**
- **Total EAs Tracked:** 79
- **Finished & Fully Compiled (0 Errors):** 14 (§1)
- **Implemented on 2026-10-01 (logic complete, pending Windows compile):** 65 (§2)
- **Pending Implementation (Scaffolds / Templates):** 0

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

## 2. Implemented EAs (2026-10-01 pass)

The 65 former scaffolds in `MQL5_Master/Experts/additionalEAs/` now carry the strategy logic of their source documents. Every EA is authored by `scripts/gen_additional_eas.py` (spec -> `.mq5`), uses the shared `EACommon.mqh` engine (`CEAStrategy`), passes `scripts/check_mql5_source.py`, and keeps a unique magic. The 17 §2A EAs keep the tracker's filenames, but their magic numbers were reassigned to `3101`-`3117` because rows 15-31 collided with the §1 `1000`-`1016` range; the 48 §2B Study Arena EAs use their originally assigned `2001`-`2048` values. Final `.ex5` compilation still happens on Windows (see §4).

### A. Core Strategy & Prop Firm Challenge Documents (`docs/strategy/`, `docs/prop_firm/`)

| # | EA File Name | Source Document | Assigned Magic | Status |
|---|---|---|---|---|
| 15 | `EA_FINAL_OPTIMUM_STRATEGY.mq5` | `docs/strategy/FINAL_OPTIMUM_STRATEGY.md` | `3101` | **IMPLEMENTED** (2026-10-01) |
| 16 | `EA_THE5ERS_CHALLENGE_STRATEGY_V2.mq5` | `docs/prop_firm/THE5ERS-CHALLENGE-STRATEGY-V2.md` | `3102` | **IMPLEMENTED** (2026-10-01) |
| 17 | `EA_THE5ERS_CHALLENGE_OPTIMIZATION.mq5` | `docs/prop_firm/THE5ERS-CHALLENGE-OPTIMIZATION.md` | `3103` | **IMPLEMENTED** (2026-10-01) |
| 18 | `EA_THE5ERS_2_5K_CHALLENGE_PLAN.mq5` | `docs/prop_firm/THE5ERS-2.5K-CHALLENGE-PLAN.md` | `3104` | **IMPLEMENTED** (2026-10-01) |
| 19 | `EA_THE5ERS_CHALLENGE_V2_REVALIDATION.mq5` | `docs/prop_firm/THE5ERS-CHALLENGE-V2-REVALIDATION.md` | `3105` | **IMPLEMENTED** (2026-10-01) |
| 20 | `EA_THE5ERS_END_TO_END_PRECODE_CHECKLIST.mq5` | `docs/prop_firm/THE5ERS-END-TO-END-PRECODE-CHECKLIST.md` | `3106` | **IMPLEMENTED** (2026-10-01) |
| 21 | `EA_THE5ERS_HIGH_STAKES_RESEARCH.mq5` | `docs/prop_firm/THE5ERS-HIGH-STAKES-RESEARCH.md` | `3107` | **IMPLEMENTED** (2026-10-01) |
| 22 | `EA_THE5ERS_PROPOSAL_REVIEW.mq5` | `docs/prop_firm/THE5ERS-PROPOSAL-REVIEW.md` | `3108` | **IMPLEMENTED** (2026-10-01) |
| 23 | `EA_THE5ERS_STRATEGY_IMPROVEMENT_SUGGESTION_REVIEW.mq5` | `docs/prop_firm/THE5ERS-STRATEGY-IMPROVEMENT-SUGGESTION-REVIEW.md` | `3109` | **IMPLEMENTED** (2026-10-01) |
| 24 | `EA_TRIAD_R_HS_CODE_REVIEW.mq5` | `docs/strategy/TRIAD_R_HS-CODE-REVIEW.md` | `3110` | **IMPLEMENTED** (2026-10-01) |
| 25 | `EA_TRIAD_SURVIVE.mq5` | `docs/strategy/TRIAD-SURVIVE.md` | `3111` | **IMPLEMENTED** (2026-10-01) |
| 26 | `EA_Pr10_Roi_Improvements.mq5` | `docs/strategy/Pr10 Roi Improvements.md` | `3112` | **IMPLEMENTED** (2026-10-01) |
| 27 | `EA_progress.mq5` | `docs/strategy/progress.md` | `3113` | **IMPLEMENTED** (2026-10-01) |
| 28 | `EA_prop_fund_challenge_improvement_plan.mq5` | `docs/prop_firm/prop-fund-challenge-improvement-plan.md` | `3114` | **IMPLEMENTED** (2026-10-01) |
| 29 | `EA_strategy_improvements_plan.mq5` | `docs/strategy/strategy-improvements-plan.md` | `3115` | **IMPLEMENTED** (2026-10-01) |
| 30 | `EA_STRATEGY_PORTFOLIO_AUDIT.mq5` | `docs/strategy/STRATEGY-PORTFOLIO-AUDIT.md` | `3116` | **IMPLEMENTED** (2026-10-01) |
| 31 | `EA_STRATEGY_ROADMAP.mq5` | `docs/strategy/STRATEGY-ROADMAP.md` | `3117` | **IMPLEMENTED** (2026-10-01) |

### B. Study Arena AI Contestant Documents (`docs/research/study_arena/` & `docs_v1/docs/coreIdea/`)

| # | EA File Name | Source Document | Assigned Magic | Status |
|---|---|---|---|---|
| 32 | `EA_studyarena_round1_contestant_b.mq5` | `studyarena-round1-contestant-b.md` | `2001` | **IMPLEMENTED** (2026-10-01) |
| 33 | `EA_studyarena_round1_contestant_c.mq5` | `studyarena-round1-contestant-c.md` | `2002` | **IMPLEMENTED** (2026-10-01) |
| 34 | `EA_studyarena_round2_contestant_a.mq5` | `studyarena-round2-contestant-a.md` | `2003` | **IMPLEMENTED** (2026-10-01) |
| 35 | `EA_studyarena_round2_contestant_b.mq5` | `studyarena-round2-contestant-b.md` | `2004` | **IMPLEMENTED** (2026-10-01) |
| 36 | `EA_studyarena_round2_contestant_c.mq5` | `studyarena-round2-contestant-c.md` | `2005` | **IMPLEMENTED** (2026-10-01) |
| 37 | `EA_studyarena_round3_contestant_a__1_.mq5` | `studyarena-round3-contestant-a.md` | `2006` | **IMPLEMENTED** (2026-10-01) |
| 38 | `EA_studyarena_round3_contestant_b__1_.mq5` | `studyarena-round3-contestant-b.md` | `2007` | **IMPLEMENTED** (2026-10-01) |
| 39 | `EA_studyarena_round4_contestant_a__1_.mq5` | `studyarena-round4-contestant-a.md` | `2008` | **IMPLEMENTED** (2026-10-01) |
| 40 | `EA_studyarena_round4_contestant_b.mq5` | `docs/research/study_arena/studyarena-round4-contestant-b.md` | `2009` | **IMPLEMENTED** (2026-10-01) |
| 41 | `EA_studyarena_round4_contestant_b__1_.mq5` | `studyarena-round4-contestant-b (1).md` | `2010` | **IMPLEMENTED** (2026-10-01) |
| 42 | `EA_studyarena_round4_contestant_c.mq5` | `docs/research/study_arena/studyarena-round4-contestant-c.md` | `2011` | **IMPLEMENTED** (2026-10-01) |
| 43 | `EA_studyarena_round4_contestant_c__1_.mq5` | `studyarena-round4-contestant-c (1).md` | `2012` | **IMPLEMENTED** (2026-10-01) |
| 44 | `EA_studyarena_round4_contestant_d.mq5` | `docs/research/study_arena/studyarena-round4-contestant-d.md` | `2013` | **IMPLEMENTED** (2026-10-01) |
| 45 | `EA_studyarena_round4_contestant_e.mq5` | `docs/research/study_arena/studyarena-round4-contestant-e.md` | `2014` | **IMPLEMENTED** (2026-10-01) |
| 46 | `EA_studyarena_round4_contestant_f.mq5` | `docs/research/study_arena/studyarena-round4-contestant-f.md` | `2015` | **IMPLEMENTED** (2026-10-01) |
| 47 | `EA_studyarena_round5_contestant_a.mq5` | `docs/research/study_arena/studyarena-round5-contestant-a.md` | `2016` | **IMPLEMENTED** (2026-10-01) |
| 48 | `EA_studyarena_round5_contestant_a_2047.mq5` | `docs/research/study_arena/studyarena-round5-contestant-a.md` | `2047` | **IMPLEMENTED** (2026-10-01) |
| 49 | `EA_studyarena_round5_contestant_b.mq5` | `docs/research/study_arena/studyarena-round5-contestant-b.md` | `2017` | **IMPLEMENTED** (2026-10-01) |
| 50 | `EA_studyarena_round5_contestant_b_2048.mq5` | `docs/research/study_arena/studyarena-round5-contestant-b.md` | `2048` | **IMPLEMENTED** (2026-10-01) |
| 51 | `EA_studyarena_round5_contestant_c.mq5` | `docs/research/study_arena/studyarena-round5-contestant-c.md` | `2018` | **IMPLEMENTED** (2026-10-01) |
| 52 | `EA_studyarena_round5_contestant_d.mq5` | `docs/research/study_arena/studyarena-round5-contestant-d.md` | `2019` | **IMPLEMENTED** (2026-10-01) |
| 53 | `EA_studyarena_round5_contestant_e.mq5` | `docs/research/study_arena/studyarena-round5-contestant-e.md` | `2020` | **IMPLEMENTED** (2026-10-01) |
| 54 | `EA_studyarena_round5_contestant_f.mq5` | `docs/research/study_arena/studyarena-round5-contestant-f.md` | `2021` | **IMPLEMENTED** (2026-10-01) |
| 55 | `EA_studyarena_round7_contestant_a.mq5` | `docs/research/study_arena/studyarena-round7-contestant-a.md` | `2022` | **IMPLEMENTED** (2026-10-01) |
| 56 | `EA_studyarena_round7_contestant_b.mq5` | `docs/research/study_arena/studyarena-round7-contestant-b.md` | `2023` | **IMPLEMENTED** (2026-10-01) |
| 57 | `EA_studyarena_round7_contestant_c.mq5` | `docs/research/study_arena/studyarena-round7-contestant-c.md` | `2024` | **IMPLEMENTED** (2026-10-01) |
| 58 | `EA_studyarena_round7_contestant_d.mq5` | `docs/research/study_arena/studyarena-round7-contestant-d.md` | `2025` | **IMPLEMENTED** (2026-10-01) |
| 59 | `EA_studyarena_round8_contestant_a.mq5` | `docs/research/study_arena/studyarena-round8-contestant-a.md` | `2026` | **IMPLEMENTED** (2026-10-01) |
| 60 | `EA_studyarena_round8_contestant_b.mq5` | `docs/research/study_arena/studyarena-round8-contestant-b.md` | `2027` | **IMPLEMENTED** (2026-10-01) |
| 61 | `EA_studyarena_round8_contestant_c.mq5` | `docs/research/study_arena/studyarena-round8-contestant-c.md` | `2028` | **IMPLEMENTED** (2026-10-01) |
| 62 | `EA_studyarena_round8_contestant_d.mq5` | `docs/research/study_arena/studyarena-round8-contestant-d.md` | `2029` | **IMPLEMENTED** (2026-10-01) |
| 63 | `EA_studyarena_round10_claude_fable_5_high_reasoning.mq5` | `docs/research/study_arena/studyarena-round10-claude-fable-5-high-reasoning.md` | `2030` | **IMPLEMENTED** (2026-10-01) |
| 64 | `EA_studyarena_round10_claude_opus_5_high_reasoning.mq5` | `docs/research/study_arena/studyarena-round10-claude-opus-5-high-reasoning.md` | `2031` | **IMPLEMENTED** (2026-10-01) |
| 65 | `EA_studyarena_round10_gemini_3_1_pro_preview_high_reasoning.mq5` | `docs/research/study_arena/studyarena-round10-gemini-3-1-pro-preview-high-reasoning.md` | `2032` | **IMPLEMENTED** (2026-10-01) |
| 66 | `EA_studyarena_round10_kimi_k3_high_reasoning.mq5` | `docs/research/study_arena/studyarena-round10-kimi-k3-high-reasoning.md` | `2033` | **IMPLEMENTED** (2026-10-01) |
| 67 | `EA_studyarena_round10_qwen3_8_2_4t_a95b_high_reasoning.mq5` | `docs/research/study_arena/studyarena-round10-qwen3-8-2-4t-a95b-high-reasoning.md` | `2034` | **IMPLEMENTED** (2026-10-01) |
| 68 | `EA_studyarena_round11_contestant_a.mq5` | `docs/research/study_arena/studyarena-round11-contestant-a.md` | `2035` | **IMPLEMENTED** (2026-10-01) |
| 69 | `EA_studyarena_round11_contestant_b.mq5` | `docs/research/study_arena/studyarena-round11-contestant-b.md` | `2036` | **IMPLEMENTED** (2026-10-01) |
| 70 | `EA_studyarena_round11_contestant_c.mq5` | `docs/research/study_arena/studyarena-round11-contestant-c.md` | `2037` | **IMPLEMENTED** (2026-10-01) |
| 71 | `EA_studyarena_round11_contestant_d.mq5` | `docs/research/study_arena/studyarena-round11-contestant-d.md` | `2038` | **IMPLEMENTED** (2026-10-01) |
| 72 | `EA_studyarena_round11_contestant_e.mq5` | `docs/research/study_arena/studyarena-round11-contestant-e.md` | `2039` | **IMPLEMENTED** (2026-10-01) |
| 73 | `EA_studyarena_round11_contestant_f.mq5` | `docs/research/study_arena/studyarena-round11-contestant-f.md` | `2040` | **IMPLEMENTED** (2026-10-01) |
| 74 | `EA_studyarena_round12_claude_fable_5_high_reasoning.mq5` | `docs/research/study_arena/studyarena-round12-claude-fable-5-high-reasoning.md` | `2041` | **IMPLEMENTED** (2026-10-01) |
| 75 | `EA_studyarena_round12_contestant_a.mq5` | `docs/research/study_arena/studyarena-round12-contestant-a.md` | `2042` | **IMPLEMENTED** (2026-10-01) |
| 76 | `EA_studyarena_round12_contestant_b.mq5` | `docs/research/study_arena/studyarena-round12-contestant-b.md` | `2043` | **IMPLEMENTED** (2026-10-01) |
| 77 | `EA_studyarena_round12_contestant_c.mq5` | `docs/research/study_arena/studyarena-round12-contestant-c.md` | `2044` | **IMPLEMENTED** (2026-10-01) |
| 78 | `EA_studyarena_round12_contestant_f.mq5` | `docs/research/study_arena/studyarena-round12-contestant-f.md` | `2045` | **IMPLEMENTED** (2026-10-01) |
| 79 | `EA_studyarena_round12_qwen3_8_2_4t_a95b_high_reasoning.mq5` | `docs/research/study_arena/studyarena-round12-qwen3-8-2-4t-a95b-high-reasoning.md` | `2046` | **IMPLEMENTED** (2026-10-01) |

### Implementation notes (one line per EA)

Every entry below is generated from `scripts/gen_additional_eas.py`; rerun the script to reproduce the files byte-for-byte.

- **15.** `EA_FINAL_OPTIMUM_STRATEGY.mq5` (magic `3101`) - Final Optimum - per-pair Triad stack + gold Donchian
- **16.** `EA_THE5ERS_CHALLENGE_STRATEGY_V2.mq5` (magic `3102`) - The5ers Challenge V2 - M1 momentum reversion + daily state machine
- **17.** `EA_THE5ERS_CHALLENGE_OPTIMIZATION.mq5` (magic `3103`) - The5ers optimization - non-market-failure elimination + Route A router
- **18.** `EA_THE5ERS_2_5K_CHALLENGE_PLAN.mq5` (magic `3104`) - The5ers $2,500 challenge plan - Route A with spread-median and cost gates
- **19.** `EA_THE5ERS_CHALLENGE_V2_REVALIDATION.mq5` (magic `3105`) - The5ers V2 revalidation - Sleeve A plus the compliance harness
- **20.** `EA_THE5ERS_END_TO_END_PRECODE_CHECKLIST.mq5` (magic `3106`) - The5ers pre-code checklist - staged compliance gates + paired profiles
- **21.** `EA_THE5ERS_HIGH_STAKES_RESEARCH.mq5` (magic `3107`) - The5ers High Stakes research - internal limit ladder + news jurisdiction
- **22.** `EA_THE5ERS_PROPOSAL_REVIEW.mq5` (magic `3108`) - The5ers proposal review - corrected profitable-day and cash-risk rules
- **23.** `EA_THE5ERS_STRATEGY_IMPROVEMENT_SUGGESTION_REVIEW.mq5` (magic `3109`) - Suggestion review - fail-closed release gates over canonical V2 Sleeve A
- **24.** `EA_TRIAD_R_HS_CODE_REVIEW.mq5` (magic `3110`) - TRIAD-R code review - hardened runtime controls from the 12 findings
- **25.** `EA_TRIAD_SURVIVE.mq5` (magic `3111`) - TRIAD-SURVIVE - three-sleeve portfolio with scored entries and risk caps
- **26.** `EA_Pr10_Roi_Improvements.mq5` (magic `3112`) - PR10 ROI improvements - cost-honest M5 fade + gold Donchian(55)
- **27.** `EA_progress.mq5` (magic `3113`) - progress.md - the frozen TRIAD-R Sleeve A contract
- **28.** `EA_prop_fund_challenge_improvement_plan.mq5` (magic `3114`) - Prop-fund improvement plan - evidence gates before any live risk
- **29.** `EA_strategy_improvements_plan.mq5` (magic `3115`) - Strategy improvements plan - H1 bias filter, news-day counter, stats gate
- **30.** `EA_STRATEGY_PORTFOLIO_AUDIT.mq5` (magic `3116`) - Portfolio audit - three-sleeve session router with per-sleeve R telemetry
- **31.** `EA_STRATEGY_ROADMAP.mq5` (magic `3117`) - Strategy roadmap - Track A preservation, Track B fast-track families
- **32.** `EA_studyarena_round1_contestant_b.mq5` (magic `2001`) - Round 1B - SMC order-block EA with break/retest confirmation
- **33.** `EA_studyarena_round1_contestant_c.mq5` (magic `2002`) - Round 1C - multi-timeframe SMC confluence with exposure cap
- **34.** `EA_studyarena_round2_contestant_a.mq5` (magic `2003`) - Round 2A - liquidity-hunting with correlation ripple and z-score reversion
- **35.** `EA_studyarena_round2_contestant_b.mq5` (magic `2004`) - Round 2B - portfolio of five return engines with graded conviction sizing
- **36.** `EA_studyarena_round2_contestant_c.mq5` (magic `2005`) - Round 2C - SMC pillars: HTF bias, fractal sweep, CHoCH and OB zone
- **37.** `EA_studyarena_round3_contestant_a__1_.mq5` (magic `2006`) - Round 3A - three-timeframe cascade with pyramided units and Kelly sizing
- **38.** `EA_studyarena_round3_contestant_b__1_.mq5` (magic `2007`) - Round 3B - 17 levers: imbalance entries, MTF stacking, graded ladder exits
- **39.** `EA_studyarena_round4_contestant_a__1_.mq5` (magic `2008`) - Round 4A(1) - leverage layer: liquidity sniper, gamma scalp and asymmetric exit
- **40.** `EA_studyarena_round4_contestant_b.mq5` (magic `2009`) - Round 4B - session map portfolio with grid, sweep, pullback and VWAP engines
- **41.** `EA_studyarena_round4_contestant_b__1_.mq5` (magic `2010`) - Round 4B(1) - imbalance engine with correlated heat, meta-labeling and recycling
- **42.** `EA_studyarena_round4_contestant_c.mq5` (magic `2011`) - Round 4C - 24-hour matrix: Asian grid, London Judas swing, NY pullback
- **43.** `EA_studyarena_round4_contestant_c__1_.mq5` (magic `2012`) - Round 4C(1) - 23 levers: regime parameter sets, streaks, EOM harvest, CVD and OB scoring
- **44.** `EA_studyarena_round4_contestant_d.mq5` (magic `2013`) - Round 4D - regime router: trend, range and expansion portfolios with exact ladders
- **45.** `EA_studyarena_round4_contestant_e.mq5` (magic `2014`) - Round 4E - pair/session map with correlation groups and exact entry steps
- **46.** `EA_studyarena_round4_contestant_f.mq5` (magic `2015`) - Round 4F - three sleeves: London break+retest, filtered Asian grid, NY momentum
- **47.** `EA_studyarena_round5_contestant_a.mq5` (magic `2016`) - Round 5A - 60/25/15 portfolio: London sweep, NY continuation, capped reversion basket
- **48.** `EA_studyarena_round5_contestant_a_2047.mq5` (magic `2047`) - Round 5A-2047 - percentile-gated London sweep with the full checklist and 40/40/20 ladder
- **49.** `EA_studyarena_round5_contestant_b.mq5` (magic `2017`) - Round 5B - asymmetric runner: 25% at 1.2R, break-even +0.3R, trail the 8R tail
- **50.** `EA_studyarena_round5_contestant_b_2048.mq5` (magic `2048`) - Round 5B-2048 - Contestant E's executable core: 3 equal legs, 0.5% basket, RSI(2) entry
- **51.** `EA_studyarena_round5_contestant_c.mq5` (magic `2018`) - Round 5C - honest-math London sweep with chandelier trail and fuel filter
- **52.** `EA_studyarena_round5_contestant_d.mq5` (magic `2019`) - Round 5D - 3-shift portfolio with an un-blow-up-able equal-lot grid
- **53.** `EA_studyarena_round5_contestant_e.mq5` (magic `2020`) - Round 5E - executable core: 1% per group, 0.5% basket grid and three named setups
- **54.** `EA_studyarena_round5_contestant_f.mq5` (magic `2021`) - Round 5F - stat-arb gates: ADX, band-width rank, channel check and 8-level ladder
- **55.** `EA_studyarena_round7_contestant_a.mq5` (magic `2022`) - Round 7A - GER40 cash open gap fade: 20-80 point filter, 1.5x stop, exact gap fill
- **56.** `EA_studyarena_round7_contestant_b.mq5` (magic `2023`) - Round 7B - three sleeves, equity-curve throttle and a 2.5x-ATR runner trail
- **57.** `EA_studyarena_round7_contestant_c.mq5` (magic `2024`) - Round 7C - 5% single strategy: 1.5x M15 ATR stop with an hourly chandelier runner
- **58.** `EA_studyarena_round7_contestant_d.mq5` (magic `2025`) - Round 7D - regime-switched compression breakout with adaptive stops
- **59.** `EA_studyarena_round8_contestant_a.mq5` (magic `2026`) - Round 8A - London sweep-and-reclaim on borrowed capital with a 6% monthly stop
- **60.** `EA_studyarena_round8_contestant_b.mq5` (magic `2027`) - Round 8B - SOS-3 session-open sweep and reclaim with an A+ free-roll booster
- **61.** `EA_studyarena_round8_contestant_c.mq5` (magic `2028`) - Round 8C - immediate close-entry reclaim with a 50/20/30 ladder and 3-loss de-risk
- **62.** `EA_studyarena_round8_contestant_d.mq5` (magic `2029`) - Round 8D - one trade per day, five attempts a week, strict spread and slope filters
- **63.** `EA_studyarena_round10_claude_fable_5_high_reasoning.mq5` (magic `2030`) - Round 10 Fable - M1 session-open sweep scalper with a ruthless 30-minute exit
- **64.** `EA_studyarena_round10_claude_opus_5_high_reasoning.mq5` (magic `2031`) - Round 10 Opus - LSR-A cost-gated micro-swing state machine with correlation cap
- **65.** `EA_studyarena_round10_gemini_3_1_pro_preview_high_reasoning.mq5` (magic `2032`) - Round 10 Gemini - M1 delta-sweep scalper with volume divergence and tick acceleration
- **66.** `EA_studyarena_round10_kimi_k3_high_reasoning.mq5` (magic `2033`) - Round 10 Kimi - SWEEP-1 multi-session engine with a score gate and drawdown throttle
- **67.** `EA_studyarena_round10_qwen3_8_2_4t_a95b_high_reasoning.mq5` (magic `2034`) - Round 10 Qwen - SOS-3 stacker: three sessions, 45-minute kill switch, multi-account sizing
- **68.** `EA_studyarena_round11_contestant_a.mq5` (magic `2035`) - Round 11A - adaptive session sweep-reclaim with session caps and cost governors
- **69.** `EA_studyarena_round11_contestant_b.mq5` (magic `2036`) - Round 11B - cost-of-business governor with virtual stops and hard-stop camouflage
- **70.** `EA_studyarena_round11_contestant_c.mq5` (magic `2037`) - Round 11C - decade-honest risk throttle: halve at -3%, quarter at -5%, month over at -5.5%
- **71.** `EA_studyarena_round11_contestant_d.mq5` (magic `2038`) - Round 11D - veteran spec: 0.4-0.5% cap, -2% throttle steps and three decorrelated sleeves
- **72.** `EA_studyarena_round11_contestant_e.mq5` (magic `2039`) - Round 11E - SWEEP-1 veteran: score gate, DD-tier risk ladder and Friday flat
- **73.** `EA_studyarena_round11_contestant_f.mq5` (magic `2040`) - Round 11F - TRIAD: one edge, three decorrelated expressions at 0.24% per sleeve
- **74.** `EA_studyarena_round12_claude_fable_5_high_reasoning.mq5` (magic `2041`) - Round 12 Fable - SWEEP-1 the 10-year machine with six entry gates and flow checks
- **75.** `EA_studyarena_round12_contestant_a.mq5` (magic `2042`) - Round 12A - SWEEP-1 final locked with the 8-point score gate (>= 7/8)
- **76.** `EA_studyarena_round12_contestant_b.mq5` (magic `2043`) - Round 12B - three-tier DD throttle on top of the programmatic M5 sweep-reclaim
- **77.** `EA_studyarena_round12_contestant_c.mq5` (magic `2044`) - Round 12C - SR-10 survival: ban list, volatility percentile band and 0.70% open-risk cap
- **78.** `EA_studyarena_round12_contestant_f.mq5` (magic `2045`) - Round 12F - SOS-SWEEP veteran: five gates, one-position correlation rule, 1.2% heat cap
- **79.** `EA_studyarena_round12_qwen3_8_2_4t_a95b_high_reasoning.mq5` (magic `2046`) - Round 12 Qwen - SWEEP-1 definitive with session flat times and overlap discipline

---

## 3. Directory Structure

```
forex/
├── MQL5_Master/
│   ├── Experts/
│   │   ├── Master_Triad_V1.mq5         # Production Master Engine (Compiled)
│   │   ├── Master_Triad_V1.ex5         # Production Binary
│   │   └── additionalEAs/              # 14 Finished EAs (§1) + 65 implemented strategy EAs (§2)
│   │       ├── EA_*.mq5
│   │       └── EA_*.ex5                # Compiled binaries for finished EAs
│   └── Include/
│       ├── E1_SMC_Core.mqh             # SMC sweep + CHoCH + OB engine
│       ├── ExecutionManager.mqh        # Dual-bracket + staged exits + time stops
│       ├── NewsManager.mqh             # Live XML news ingestion + blackout
│       └── RiskGovernor.mqh            # Breakers + prop-firm capital governor
├── chartfanatics/                      # ChartFanatics playbook archive + work tracker
│   ├── TODO.md                         # 47-strategy board (status/progress)
│   ├── todos/                          # one card per strategy (stages + tracking + notes)
│   ├── pdf/ · glimpse/ · glimpse-pdf/  # sources
│   └── mql5-eas/                       # EAs built from the playbooks (§6), magic block 3201-3247
└── docs/
    └── EA_IMPLEMENTATION_TRACKER.md    # This file
```

---

## 4. How to Test & Deploy

1. **Production Full Strategy:** Launch MetaTrader 5 and select `Master_Triad_V1` in the Strategy Tester. It runs all symbols concurrently with the fully integrated risk and execution engine.
2. **Specialized Module EAs:** To backtest or forward-test individual architectural breakthroughs (e.g. `EA_apex_eigen_matrix` or `EA_max_roi_out_of_box_strategy`), select that specific EA in the Strategy Tester.
3. **Validating the 65 implemented EAs (no charts needed):** MT5 allows one EA per chart, so validation runs headlessly in the Strategy Tester through a generated harness: `python3 validation/mt5_harness/gen_tester_configs.py` writes one `[Tester]` config per EA (+ `.set`, `run_all.ps1`), `run_all.ps1` drives `terminal64.exe /config:<EA>.ini` for all 65, every EA dumps one machine-readable result row (`EA_TestReport()` in `EACommon.mqh`, tester-only), and `python3 validation/mt5_harness/parse_results.py` produces a PASS/WARN/FAIL table plus the list of EAs that produced no row (compile failures). Run `MQL5_Master/Scripts/UniversePreflight.mq5` once first to see which of the EAs' symbols the broker actually offers. Full plan: `docs/EA_VALIDATION_PLAYBOOK.md`, harness details: `validation/mt5_harness/README.md`.
4. **Compiling the implemented EAs:** Compile each `.mq5` with MetaEditor 64 (batch-compile the whole `additionalEAs/` folder):
   ```powershell
   & "C:\Program Files\Fusion Markets MetaTrader 5\metaeditor64.exe" /compile:"E:\Jatin-Project\Forex\forex\MQL5_Master\Experts\additionalEAs\EA_name.mq5" /log
   ```

---

## 5. Verification Performed (2026-10-01, extended 2026-10-02, seventh pass 2026-10-03)

* **Static contract validation** - `python3 scripts/check_mql5_source.py MQL5_Master/Experts/additionalEAs/<file>.mq5` on all 65 new EAs: **0 findings** (no MQL4 patterns, event handlers delegate to the engine, no bare `return;` in typed functions, no per-tick alerts, risk checks present).
* **Whole-tree scan** - 92 findings remain in the repository, all of them pre-existing: the 12 untracked legacy helper EAs, `EA_studyarena_round1_contestant_a.mq5` (§1, finished), `Master_Triad_V1.mq5` and the three legacy `#property strict` includes (`E1_SMC_Core.mqh`, `ExecutionManager.mqh`, `NewsManager.mqh`). None of the 65 implemented EAs contributes a finding.
* **Generation reproducibility** - every implemented `.mq5` is emitted by `python3 scripts/gen_additional_eas.py`; the generator holds all 65 specs (inputs, `Configure`, `BuildPlan`, `Manage`, helper methods) and must be edited instead of the rendered files.
* **Shared engine** - all 65 EAs inherit `CEAStrategy` from `MQL5_Master/Include/EACommon.mqh` (settings/clock/session engine, `EACore` + `EASignals` + `EATrade` risk governor, news filter and execution manager). Detectors used include sweep/reclaim, break-retest, range fade, EMA pullback, ORB, Donchian, FVG retest, order-block retest, z-score fade and fractal structure.
* **Deep bug audit (2026-10-02)** - full static audit of the engine and the 65 generated EAs plus a review of the entry/sizing/exit/rollover paths: **15 defects found and fixed** (unresolvable `#include` path in all 65, four input declarations swallowed by a comment, a duplicate input, an unknown `cfg.beOffsetR` field, a wrong-arity `SpreadGuard` call, a missing minimum-lot risk guard, floating P&L leaking into `ctx.dayRealizedPl`, double-counted qualifying days, London-clock day anchors for the server-day firm rollover, a request cap that halted/flattened instead of blocking, restart-unsafe `riskDist`, swallowed partial-close failures, MQL4 `Symbol()` in four legacy EAs, and the engine/generator/checker not being tracked in git). See `docs/EA_BUG_AUDIT.md` for the evidence table. **Re-audited in depth the same day (second request): 3 further defects fixed** - a shared-engine rate-array indexing convention error that made 11 signal functions evaluate their trigger bar one bar late in every generated EA, an unsatisfiable liquidity-sweep comparison that left `EA_studyarena_round10_gemini_3_1_pro_preview_high_reasoning` unable to trade at all, and 237 declared-but-inert `input`s across 60 EAs (dead config). Five automated candidate reports were dismissed with reasons rather than "fixed".
* **Deep bug audit, third pass (2026-10-02)** - six further defects fixed at the source of truth (partial-close percentages re-based on the entry volume plus a sub-min remainder guard, break-even-on-bar-close reading a stale bar, `EA_FindPosition` newest-by-time, the `SigPrevSessionRange` compile-arity error, per-leg loss counting, `DEAL_ENTRY_INOUT` entries). See `docs/EA_BUG_AUDIT.md` "Third pass".
* **Deep bug audit, fourth pass (2026-10-02)** - **ten further defects fixed**, nine of them in the shared engine and one dead parameter, plus a fidelity sweep of every ADX/ATR gate against the timeframe its source document quotes: marketable-limit entries could never fill in 12 of the 13 `useLimitEntry` EAs (#25), `SigRangeForDay` starved multi-day lookbacks (#26), `EA_TRIAD_SURVIVE` scored every sleeve against the Asian window (#27), the pre-trade risk gate could re-open risk on a breached weekly/monthly floor after the day rollover (#28), `SigSweepReclaim` silently dropped every retracement setup whose level was already offered (#29), weekly/monthly risk anchors were not restart-safe (#30), 20 ADX/ATR gates in 15 EAs read the signal timeframe while their documents quote H1/H4/daily (#31), three EAs missed explicit document rules (bias + sweep-volume gates, the Asian-sleeve universe, the daily-ATR risk halving) (#32), `plan.expiry` (a timestamp) was passed to the executor's minutes parameter (#33), and one unused filter parameter (#34). Engine additions: `ctx.adxH1`, `ctx.adxH4`, `ctx.atrH1`, `SSignalPlan.sweepBarsAgo`, `EA_BookFill()`. All 65 EAs regenerated; see `docs/EA_BUG_AUDIT.md` "Fourth pass".
* **Deep bug audit, fifth pass (2026-10-02)** - the pass walked **every source document** and checked its declared instrument universe, session/instrument matrix, exit ladder, flat times and day-of-week rules against the generated strategy: **17 further defect classes fixed across 22 EAs plus two shared-engine additions** (#35-#51 in `docs/EA_BUG_AUDIT.md` "Fifth pass"). The headline fixes: nine EAs shipped universes that could never deliver an instrument their document declares (gold missing from the two London-sweep EAs - whose fuel filter would then have rejected every gold setup with the EURUSD 35-pip cap - `AUDUSD`/`EURCHF`/`AUDNZD` dead sleeves, the The5ers EA running one of its three documented instrument/session combinations, `round10_claude_opus_5` trading USDCAD instead of its document's Asian and gold sleeves); `round8_contestant_b` was missing the chandelier runner that its document calls the ROI and took entries up to four hours after every documented session window closed, and it had none of the document's three risk rules (one position per currency group, max 2 trades/session, max 1.5% open risk); four EAs let the engine's fixed-R trail truncate the documented chandelier tail; four documented hard flats (21:00/16:30/16:00) were missing and three Asian-grid EAs never closed their baskets at the 07:00 flat their documents call the rule that keeps grids alive; three EAs ignored their "Tuesday-Thursday only" rule; eight EAs scaled H1-ATR distances off a `daily ATR / 6` proxy instead of the real `ctx.atrH1`; `round10_qwen3_8`s Step 4 midpoint confirmation and 3-candle limit expiry are now implemented through a new opt-in `SSweepParams.requireMidpointBreak`; the round-10 Fable EA's "30-minute exit only while below +1R" was being enforced unconditionally (a runner at +3R was force-closed) and its +2.5R ladder rung was missing, now a new opt-in `SEASettings.timeStopUnlessR` plus the 40 % rung; `round5_contestant_c`'s 25 % at +2R rung restored; and `round8_contestant_c`'s "never both pairs on the same day" rule was not enforced; the `round8_contestant_c` "never both pairs on the same day" rule was not enforced; and 53 of the 65 tracker source-document links did not resolve to a file (now corrected). All 65 EAs regenerated; `--check` reports 65/65, the checker reports 0 findings on the 65, arity 0/0 over 87 files, braces 0, 187 tests pass.
* **Deep bug audit, sixth pass (2026-10-02)** - this pass went after **code that exists but does nothing** and the **exit semantics** the earlier passes had only spot-checked: **14 defect classes fixed across 20 EAs plus one shared-engine addition** (#52-#65 in `docs/EA_BUG_AUDIT.md` "Sixth pass"). Headlines: `round4_contestant_b`'s London and NY sleeves accepted any universe member (the documented sleeve-1 helper existed and was never called); `round10_claude_opus_5` never implemented the document's session x symbol matrix (the Asian sleeve did not exist, GER40/US100 were missing and none of the three exposure caps was enforced); **thirteen EAs moved the stop to break-even on a wick while their documents require a completed bar close** (fixed with a new `SEASettings.beConfirmTf`, which also lets the confirmation run on the timeframe the document names - M5/M1/M15); `EA_TRIAD_SURVIVE`'s +1R rung (partial + BE) was a wick trigger, `round10_gemini_3_1_pro` banked at +1R instead of its +1.5R/60 % matrix and force-closed runners its document says to keep (flat 10-minute stop -> 12-minute conditional stop), `round8_contestant_d`/`round12_contestant_b`/`round12_contestant_c` paid the wrong ladder percentages or lacked a rung, `round11_contestant_a`'s documented 0.10R cost gate was missing, `THE5ERS_CHALLENGE_STRATEGY_V2`'s manual break-even read one bar late, and two dead helpers (`RangeBetween`, `EndOfMonthWindow`) were removed/wired respectively. **One self-correction:** the fifth pass had added `AUDUSD` to `round10_qwen3_8`, whose document never mentions it - removed. All 65 EAs regenerated; `--check` 65/65, checker 0 on the 65, arity 0/0 over 87 files, braces 0, 187 tests pass.
* **Sixth-pass note on index instruments** - GER40/US100/DAX/US30/NAS100 are now shipped as universes instead of being withheld: the engine's symbol parser skips (and logs) any configured symbol the broker does not list, so those sleeves trade where the index exists and stay inert where it does not.
* **Documented limitations from the fifth pass (deliberate, not bugs)** - (a) index-named sleeves (`GER40`, `US30`, `DAX`, `US100`) are not shipped as universes because they are broker-dependent symbols; `EA_TRIAD_SURVIVE` implements its document's own XAUUSD+GBPJPY fallback, `round11_contestant_f` sleeve B trades XAUUSD only, and `round12_contestant_b` does ship `US30` because its document names it directly. (b) `round11_contestant_f`'s sleeve B is a stated trigger substitution: the document's volatility-expansion trigger (daily ATR 60-90th percentile + M15 close beyond the rolling 4-hour range + body >= 70% + first-pullback entry + 1.2 x M15-ATR stop) is shipped as an EMA-20 pullback on XAUUSD, and the sleeve runs on the EA-wide partial ladder and time stop because the engine's exits are per-EA, not per-sleeve; sleeve A and sleeve C follow their documents. (c) Four EAs are deliberate single-sleeve variants of larger documents and their titles say so: `round5_contestant_a_2047` (London checklist), `round5_contestant_b` (asymmetric runner), `round5_contestant_c` (London sweep; the document's grid sleeve is not part of the variant), `round12_contestant_c` (SR-10 London module; the New York module is not implemented); `round7_contestant_d` implements Strategy 1 of 3 (its NY continuation and AUDNZD/EURGBP Asian mean-reversion strategies are not implemented); `EA_STRATEGY_ROADMAP`'s F1 quiet-session family is the only shipped Track-B family without its 06:30 flat (it is not the default family and its instrument set is largely outside the universe). (d) `round10_claude_opus_5` keeps one 07:00-20:00 envelope with a single 07:00-16:00 sweep window instead of its document's three session windows and has no session-end flat, and `round10_qwen3_8`/`round10_kimi_k3` use the shared 22:00 session-end flat rather than their documents' per-session flat times. (e) `round5_contestant_c` keeps a flat 16:00 without the document's "> 2R runner" exemption, and `round7_contestant_d`'s runner uses the engine M15-swing stand-in trail rather than the document's exact M15-swing + 1.5 x ATR distance. (f) `round5_contestant_e` ships one GBPUSD-shaped exit ladder for its whole universe (its document gives a per-pair exit), `round5_contestant_b` implements the asymmetric-runner variant rather than the document's 75 %-at-TP1 booster, `round5_contestant_f` implements the document's filtered-grid sleeve only, and the `round7_contestant_c` document's own summary (60 % at 1R) disagrees with its detailed section (50 % at 1R) - the EA follows the detailed section. (g) Tracker rows 32-39, 41 and 43 (the round-1/2/3 documents and the two "(1)" documents) have no source document in the repository; their code is the behaviour of record.
* **New regression checks** - `scripts/check_mql5_source.py` now also verifies include resolution, unknown `SEASettings` fields, duplicate inputs, declarations glued onto comments and MQL4 `Symbol()`. Whole-tree result after the fixes: **92 findings**, all pre-existing structure of the 13 legacy non-engine EAs; the 65 implemented EAs remain at **0 findings**. The generator additionally refuses to emit an `input` that no strategy code reads (`DEAD INPUT` guard in `scripts/gen_additional_eas.py`).
* **Not yet done in this environment** - MetaEditor compilation and Strategy Tester execution require Windows (see §4); the Linux sandbox cannot run `metaeditor64.exe`.
* **Spread / slippage rules implemented (2026-10-02, third pass on owner request)** - the nine document rules that the second audit pass had disclosed as open gaps are now implemented, in the engine and in the ten affected EAs. New engine module `MQL5_Master/Include/EASpread.mqh` (included by `EACommon.mqh`) keeps three pieces of live telemetry per symbol:
  * **spread history** - one sample per minute per symbol plus a per-minute-of-day baseline that is an exponential average with a 20-day time constant (one sample per slot per day), i.e. the documents' "20-day average spread", learned live. Query: `EA_SpreadBaseline(sym, windowMin)`; also `EA_SpreadMedianRecent(sym, n)` ("2x the 60-min average") and `EA_SpreadPips(sym)`.
  * **fill-vs-signal slippage** - measured at every market entry (expected signal price vs actual fill, in R) and written to the log, which is what the round-11 document asks for ("log fill-vs-signal on every trade").
  * **closed-trade outcomes in R** - recorded when a tracked ticket leaves the book, so a strategy can compare slippage with expectancy (`EA_ExpectancyR`, `EA_SlipMedianR`, `EA_SymbolSlippageOk`).
  Wired rules: **#36** over-spread symbol skip (`InpMaxSpreadPts`, doc's ~35 points for XAU/JPY); **#49/#50** spread < 15 % of the leg spacing (`InpMaxSpreadSpacingPct`); **#53** same for the 0.30 x D1-ATR grid; **#54** sleeve-1 pip caps (`InpMaxSpreadPipsEur` 1.0 / `InpMaxSpreadPipsGbp` 1.5); **#65** "< 0.8 pips" gate (`InpMaxSpreadPips`); **#67** spread <= 1.5 x the symbol's own time-of-day baseline; **#70** spread gate via the existing 0.1R all-in cost budget plus slippage-vs-expectancy symbol disable (`InpMaxSlipPctOfExp`); **#73** spread <= 2 x its 60-min median, spread <= 15 % of the stop distance (`CostOk`) and the same slippage disable; **#79** spread <= 1.5 x the time-of-day baseline.
  Boundaries, stated rather than hidden: every new gate **fails open** while its baseline is too thin to be evidence (fewer than 8 samples, or fewer than 2 days for a minute-of-day slot), because blocking all entries at startup would be worse than a missing baseline; telemetry is in-memory only, so a restart re-learns it; limit-order fills and the one hedge add-on in `EA_studyarena_round4_contestant_a__1_` are not slippage-measured (market entries are); and the "20-day average" is a live-learned per-minute-of-day average with a 20-day decay, not a broker-side 20-day statistic.
* **Seventh pass (2026-10-03)** - one defect found by the new validation tooling and fixed at
  the source of truth: `EA_studyarena_round8_contestant_b.mq5` line 31 began with a control byte
  (0x01, a leaked `\1` in the generator template) that MetaEditor cannot parse - see
  `docs/EA_BUG_AUDIT.md` defect #66. `scripts/check_mql5_source.py` now also fails on control
  characters (and resolves includes for files outside `MQL5_Master/`). All 65 EAs regenerated;
  generated-65 still 0 findings, legacy baseline unchanged at 92.
* **One-chart portfolio EA (new, `portfolio-EA/`)** - `gen_portfolio_ea.py` generates a host that
  runs all 65 strategies in a single chart/program: registry + per-strategy engine-state
  snapshot/restore + exposure/new-bar scheduler, with the delivered EAs and the engine includes
  left untouched (hashes recorded in `build/originals.sha256` and re-verified).
  `verify_portfolio.py` = 357 static checks, all green.  Per-strategy tracking/enables:
  the delivered magic is the key everywhere (terminal history, tester reports, comparison
  harness); `build/STRATEGY_REGISTRY.md` + `strategy_registry.csv` list magic -> switch ->
  strategy; the EA exposes one `InpRun_<magic>` checkbox per strategy (plus
  `InpDisableMagics`/`InpOnlyMagics`) so a strategy can be disabled after demo testing with
  no recompile, and the live `MQL5\Files\PortfolioEA\roster.csv` maps magic -> strategy with
  positions and floating P/L.  The 65-chart launcher has the same switch: `enabled` column in
  `launch_plan.csv`.  Two-EA layout per the user's clarification (2026-10-03): the trader is
  `AllEnginesEA.mq5` (65 engines, one chart, tags `P<magic>|`, policy override
  one-per-symbol/many-symbols, `InpKeepDeliveredPolicy="2006"`) and the dashboard is the
  separate read-only `portfolio-EA/src/PortfolioEA.mq5` tracker (per-engine net/DD/win%/verdict
  -> `MQL5\Files\PortfolioEA\performance.csv` + panel).  The trader contains no dashboard or
  file I/O at all; the 65 strategies are inlined into `build/AllEnginesEA.mq5`, so the EA is
  one file to compile; `verify_portfolio.py` (1 816 checks) enforces both boundaries, the
  single-file property and identifier hygiene (defects #67-#70 of the eighth deep pass:
  a prefixed enum type that was never declared, a halt-flatten latch shared by the 65 engines,
  entry-side commission missing from the tracker's net, and a duplicated symbol in magic 3117 -
  all fixed; the host also gained a 1-second execution timer and enforces one order per symbol).
  The tracker contract is mirrored by `tests/test_portfolio_tracker.py`.
  Ninth deep pass (2026-10-03): a switched-off engine now keeps managing its open trades
  (only new entries stop), the 8-symbol truncation is logged instead of silent (and has since
  been resolved by raising the cap - see the eleventh-pass follow-up below), cost carry is
  per position, the request budget / loss cursor are magic-scoped GlobalVariables, the market
  statistics table covers the book's 19 symbols, and the tracker creates its report folder.
  Tenth deep pass (2026-10-03) followed the shared engine object the 65 engines run through:
  the risk governor's `Init()` now re-derives every member from that engine's magic-scoped
  state (a stale halt/day lock/trade-spacing stamp used to leak to the next engine - 53 engines
  set `minSecondsBetweenTrades`), the daily anchor is frozen per clock day and the rollover
  (banked qualifying days, halt release) runs exactly once from `Init()` or `OnTick()`, and the
  host refuses to start on a netting account (identity is by magic). Six fail-closed news
  engines and the account-wide (% limits measure the shared equity) semantics are documented.
  Eleventh deep pass (2026-10-03) followed the shared DATA: the market-statistics
  symbol -> slot map is now one program-wide table (per-engine copies had every engine
  reusing the same ring slots, so a symbol's spread/slippage baseline could be built
  from another symbol's samples), a failed `EA_IndCreate` and an engine that fails init
  no longer leak indicator handles, the news-cache cap is 2 048 events and says so when
  it bites, and `InpMaxBookPerSymbol` is labelled for what it counts (positions). The
  verifier enumerates every engine global and fails unless it is snapshotted per engine
  or on the explicit program-wide list.
  Eleventh-pass follow-up (2026-10-03, owner decisions implemented): `EA_MAX_SYMBOLS`
  raised 8 -> 10 so the four widest delivered universes (2034/2040 list 10, 2031/3111
  list 9) trade in full instead of being silently cut to 8 - their results differ from
  any earlier backtest by design, and the verifier now fails if a universe outgrows the
  cap.  The six fail-closed news engines get `MQL5_Master\Scripts\ExportRedNews.mq5`,
  which writes `MQL5\Files\the5ers_red_news.csv` from the terminal's own economic
  calendar in the engine's format (plus a hand-fill template and a Stage 0b in the
  playbook); `compile_all.ps1` compiles it too.  Follow-through: the headless sweep gained `--symbols wide|all` (the four widened universes are swept on every symbol the old cap truncated, the tester report file name carries the test symbol, and `parse_results.py` reports one row per EA+symbol), and the exporter gained `InpFromDate`/`InpToDate` so the calendar can cover the tester's fixed date range.
  News path review (2026-10-04): the exporter wrote MT5 calendar values - server time - into a CSV the gate reads as UTC, shifting every news window by the broker GMT offset (defect #90; the file now declares its frame with a `#timezone=server` marker the loader honours, and marker-less files keep the delivered UTC meaning), and `NewsManager.mqh` shifted ForexFactory times by a fixed EST-calibrated offset, one hour off all summer (defect #91; the shift is now derived from the terminal clocks and the US DST rule for the event's own date, with the input as fallback).  The engine also gained a live calendar source (`newsUseCalendar`, host input `InpNewsCalendar`) that falls back to the CSV in the Strategy Tester - the calendar API has no data there - so the fail-closed engines trade live without a file and still need one for backtests.
  Not compiled here (no MetaEditor on
  Linux) - compilation is the first step on the Windows machine.
* **Top-25 priority sweep (2026-10-04)** - the first audit of the repo's *second* live EA (`Master_Triad_V1` + `RiskGovernor` + `ExecutionManager` + `NewsManager` + `E1_SMC_Core`), the launcher/preflight scripts and the clock semantics: three P0-class defects fixed at the source (the tester's auto server offset always reading 0 - engine 3107's backtests shifted by the broker offset; the launcher's substring expert matching skipping one EA of four delivered name pairs; the news frame left set on the calendar fallback) and 22 further findings ranked with evidence and fixes in `docs/EA_TOP25_BUGS.md`.  The two dominant residual risks remain the never-run compile (`compile_all.ps1`) and the never-run tester sweep.
* **Top-25 fix pass (2026-10-04)** - all code-side findings of the priority sweep are fixed at the source with 32 new verifier checks (1 846 -> 1 878) and 16 new tests: the Triad risk governor (order-type risk test, magic-filtered heat/exposure, account+magic state keys, split daily/trailing freezes, server-day PnL), the Triad strategies (a real liquidity-sweep precondition, mirrored structure search, M15 cooldown, an SMT gate that is a parameter and says when it is inert), the Triad news module (fail-closed gate, case-insensitive impact, validated timestamps) and the harness tools (compile-log detection, mtime tie-break, generated preflight symbol list, synth-template warning). Behaviour changes are disclosed in `docs/EA_TOP25_BUGS.md`; compilation and the tester sweep remain the two Windows-side steps.
* **Validation tooling (2026-10-02)** - MT5 allows one EA per chart, so the 65 EAs are validated headlessly instead: `validation/mt5_harness/gen_tester_configs.py` generates one Strategy Tester config and `.set` per EA (read straight from the generator, so configs cannot drift), `run_all.ps1`/`run_all.bat` drive `terminal64.exe /config:` for all 65, every run writes one machine-readable row via the new tester-only `EA_TestReport()` (`EACommon.mqh`; no effect live), and `validation/mt5_harness/parse_results.py` produces a PASS/WARN/FAIL portfolio table plus the list of EAs that produced no row at all (i.e. compile failures). `MQL5_Master/Scripts/UniversePreflight.mq5` reports which of the EAs' symbols the broker actually offers and which index alias it uses, because the engine skips-and-logs unavailable symbols and an inert sleeve otherwise looks like "the EA does not trade". See `docs/EA_VALIDATION_PLAYBOOK.md`. For running the set for real, `MQL5_Master/Scripts/PortfolioLauncher.mq5` + `validation/mt5_harness/gen_launcher.py` reduce "65 manual attaches" to one: the generator stamps a per-EA template (EA + inputs) from a single template saved by the user, and the script opens every chart, attaches each EA, skips what is already running, and writes `MQL5\Files\EA_Launch\launch_status.csv` (START / STOP / DRYRUN, optional group split across terminals).
* **Documented approximations (disclosed)** - `EA_studyarena_round12_contestant_c` turns its document's "20th-85th ATR percentile band" into an ATR-vs-median ratio of 0.6-1.6 and says so in a code comment. The four EAs whose documents name a spread-versus-history gate that the first pass had served with a round-local sample ring (`EA_studyarena_round8_contestant_d` and `EA_studyarena_round12_contestant_a`: "median for that time of day"; `EA_studyarena_round5_contestant_a_2047`: "1.5x that pair's normal spread for the same time"; `EA_TRIAD_SURVIVE`: "at most 1.5x the 20-day average spread") now query the engine baseline `EA_SpreadBaseline(sym, 30)` / `(sym, 720)` first and fall back to the local ring only while the engine has no evidence yet, so the statistic matches the documents (live-learned 20-day per-minute-of-day average, 30-minute or whole-day window).


---

## 6. ChartFanatics playbook family (2026-10-07)

EAs built from the ChartFanatics playbooks archived in `chartfanatics/`. Source of truth is
**`chartfanatics/mql5-eas/`** (one `.mq5` per strategy), deployed to `MQL5\Experts\chartfanatics\`
so their `..\..\Include\EACommon.mqh` resolves; `validation/mt5_harness/compile_all.ps1` compiles
that folder alongside `additionalEAs/`. `chartfanatics/mql5-eas/manifest.json` is the machine-readable
card -> EA -> magic map, and `chartfanatics/gen_todos.py` writes the EA/magic into each work card.

**Magic block 3201-3247 is reserved for this family** (one per card, 47 cards). Wave 1 uses 3201-3206:

| # | EA File Name | Source Playbook | Magic | TF | Notes |
|---|---|---|---|---|---|
| 1 | `EA_CF_AMD_Model.mq5` | `chartfanatics/pdf/amd-model.pdf` (card #04) | `3201` | M5 | Distribution-leg entry off the manipulation sweep; NY macro windows 09:50-10:10 / 10:50-11:10 ET; 2 trades/day, two-loss day lock; related-market alignment gate; target = opposite side of the accumulation range, else the nearest clean swing |
| 2 | `EA_CF_Structure_OTE.mq5` | `chartfanatics/pdf/structure-ote.pdf` (card #39) | `3202` | M15 | HTF break -> POI -> LTF breaker; first premium/discount + OTE (62-79%) implementation in the repo; 2R floor |
| 3 | `EA_CF_SMT_PO3.mq5` | `chartfanatics/pdf/smt-divergence-po3.pdf` (card #37) | `3203` | M5 | Direct symbol-vs-symbol SMT divergence (NQ vs ES) with the previous day's 50% level as the target |
| 4 | `EA_CF_PO3_OTE_ADR.mq5` | `chartfanatics/pdf/po3-ote-adr.pdf` (card #31) | `3204` | M15 | PD-array raid + displacement (close must clear the PD array), fib-anchored OTE limit from `InpOteFib`, stop at `InpStopFibLevel` (1.00 default / 0.90 tighter), TP at the 0.0 fib with R **derived** from the geometry, ADR budget gate (`[interpretation]`) |
| 5 | `EA_CF_Break_Retest.mq5` | `chartfanatics/pdf/break-retest.pdf` (card #07) | `3205` | M5 | Battle-zone retest with rejection wick; previous-day no-trade-zone gate; TP1 = nearest swing extreme ahead (R fallback), 50% partial, runners kept |
| 6 | `EA_CF_Intraday_Liquidity.mq5` | `chartfanatics/pdf/intraday-liquidity-volatility-model.pdf` (card #16) | `3206` | M5 | Failed-raid fade of PDH/PDL, Asian and London extremes, most-recent raid wins; FVG / MSS / breaker-block entries; NY 09:30-11:30 window; 90-minute time stop |
| 7 | `EA_CF_Stage_Guardrails.mq5` | `chartfanatics/pdf/5-stage-trading-framework.pdf` (card #01) | `3207` | - | **Monitor, never trades.** Card #01 is a trader-development framework (no entry/exit rules), so the EA mechanizes its checkable content: account-wide deal sweep against the stage's thresholds (loss cut-off, trade cap, revenge entry, size jump, loss streak) and a journal CSV ("journaling is not optional") |
| 8 | `EA_CF_8020NasdaqStrategy.mq5` | `chartfanatics/glimpse/jsUTbjwpFVk.md` (card #02) | `3208` | M3 | NASDAQ 80/20 mean reversion: fork / H-pattern / cross-section, repair-candle magnets, fixed 10-pt stop, 15-pt TP1 (half off, BE, runners), NY-open window, no daily cap (`[interpretation]` notes in the family README) |
| 9 | `EA_CF_AlgoPortfolioMonitor.mq5` | `chartfanatics/glimpse/TyHTEtArsS4.md` (card #03) | `3209` | - | **Monitor, never trades.** Process document (build/rank/monitor algos), so the EA ranks the account's live algorithms per magic against the document's filters: PF 1.5+, return/DD 4:1, 2+ trades/month, avg loss <= 0.5%, implied allocation 5-25%, drawdown band, expectancy; journal `cf_algo_ranking.csv` |
| 10 | `EA_CF_AuctionMarket.mq5` | `chartfanatics/pdf/auction-market-strategy.pdf` (card #05) | `3210` | M5 | Two setups selected by market state: trend model (impulse-leg LVN -> aggression -> previous-balance POC) and mean-reversion model (failed auction outside value -> reclaim -> LVN -> POC); tick-volume profile proxy; risk 0.25-0.5% band |
| 11 | `EA_CF_AuctionMarketTheory.mq5` | `chartfanatics/pdf/auction-market-theory-strategy.pdf` (card #06) | `3211` | M5 | Failed auctions at VAL/VAH -> POC rotation; accepted opening-range breakouts (body vs wick); custom Manage() flow exit on opposing pressure; value area from the tick-volume profile |
| 12 | `EA_CF_FairPricingTheory.mq5` | `chartfanatics/glimpse/-kGVL93XfyE.md` (card #09) | `3213` | M1 | 1-minute fair-pricing: displacement, break of structure, session-open reversions; static TP-first R:R (stop = TP/ratio), three-loss session lock, NY AM / Asia / NY PM 90-minute windows |
| 13 | `EA_CF_EpisodicPivot.mq5` | `chartfanatics/pdf/episodic-pivot-strategy.pdf` (card #08) | `3212` | M5 | Neglect + catalyst + repricing: day-1 OR break, EP 9M, delayed-reaction long/short; daily-low trail via custom Manage() |
| 14 | `EA_CF_FirstRedDay.mq5` | `chartfanatics/pdf/first-red-day.pdf` (card #10) | `3214` | M5 | Short the first close below the previous day's close after a 3+ day run; stop above the line; partials into the weakness |
| 15 | `EA_CF_FirstRedDayPro.mq5` | `chartfanatics/pdf/first-red-day-strategy.pdf` (card #11) | `3215` | M5 | Fuller FRD: minimum criteria (no red day, 80-100%+ extension, expanding volume/range), three entry methods, overextended-gap-down veto, VWAP magnet + 2-3% fallback, M15-high trail |
| 16 | `EA_CF_PsychGuardrails.mq5` | `chartfanatics/pdf/full-psychology-masterclass.pdf` (card #12) | `3216` | M15 | **Monitor, never trades.** Shutdown ladder (caution/cooldown/breach/session over), carryover shift, zone-map proxies, pre/during/post session journal |
| 17 | `EA_CF_FuturesStrategy.mq5` | `chartfanatics/pdf/futures-trading-strategy.pdf` (card #13) | `3217` | M30 | Environment first (D1 Bollinger bandwidth): consolidation edge trades, one-directional expansion breakouts with unfinished-business/week targets, 30%/50% mean-reversion trigger; structural daily-swing stops, counter-trend half size, 8/21/34 + anchored-VWAP exits, 1-5 trading day hold |
| 18 | `EA_CF_GammaReversal.mq5` | `chartfanatics/glimpse/35cyqDz-ej8.md` (card #14) | `3218` | M1 | Put/call wall reversal entries (levels are platform-data inputs); tick stops/targets, dollar-risk sizing, OPEX/witching/spiration gates, 2-day post-loss lock, flat at the window end |
| 19 | `EA_CF_InstFramework.mq5` | `chartfanatics/glimpse/yW6c0K8uGvw.md` (card #15) | `3219` | M1 | ORB / VWOP / overnight-gap modes with volatility targeting (constant dollar risk), validated-drawdown pause, monthly per-magic review; PEAD disclosed data-blocked |
| 20 | `EA_CF_LiquidityInversion.mq5` | `chartfanatics/glimpse/UIGZtoGGPH4.md` (card #17) | `3220` | M5 | Daily/weekly sweep -> 4H gap inversion -> 15m gap inverted on the 5m (swings: H1/H4 only); stop beyond the 15m extreme, prior-liquidity targets with a 1.5R floor, 50% trim + BE + runner trail, high-volatility half size, 10:00 ET start, two-consecutive-loss day stop |
| 21 | `EA_CF_LiquidityStrategy.mq5` | `chartfanatics/pdf/liquidity-strategy.pdf` (card #18) | `3221` | M5 | Liquidity-trap model: respected 30m levels (move-away + unconsumed), first-breach trap with the rejection back inside on M5, market entry at the level, stop over the taken high/low, opposing pools as targets (equal lows preferred, 1R floor), partials only at liquidity, structure-ratcheted stop, NY-open window |
| 22 | `EA_CF_LowVolumeNode.mq5` | `chartfanatics/pdf/low-volume-node.pdf` (card #19) | `3222` | M5 | Base + impulse zone map, tick-volume LVN bins, revisit absorption confirmation (wick, close-back-inside, no close-through, participation), tight stop + stop cap, session/prior-day/next-LVN targets with a 2R floor, 1R scale-out, premise exit on a close through the node |
| 23 | `EA_CF_MarketAuctionTheory.mq5` | `chartfanatics/pdf/market-auction-theory.pdf` (card #20) | `3223` | M5 | Prior-day bias (body + 45-degree slope + daily 21/50), 5m mirror alignment, post-open auction zone with a congestion cap, breakout-left-the-zone requirement, rejection-candle entry, stop beyond the candle, 2:1 target, first-hour window, calendar gate |
| 24 | `EA_CF_MarketDna.mq5` | `chartfanatics/pdf/market-dna-strategy.pdf` (card #21) | `3224` | M5 | DNA zones (H1 base + exploded move, ranges, consumed test), aggression-over-absorption confirmation proxy, entry at the level, stop beyond the zone with a tight-risk cap, 3:1 target, partial at the first reaction, aggression-flip runner exit, fractal trail, relative-volume catalyst gate, flat-session gate |
| 25 | `EA_CF_MeanReversion.mq5` | `chartfanatics/pdf/mean-reversion-strategy.pdf` (card #22) | `3225` | M5 | Abnormal-day gate (expansion/volume/ATR), fast displacement with a streak or a panic candle, right-side reversal break entry, capitulation-extreme stop with a risk cap, 20-period-mean target, prior-bar trail, quality-scaled sizing, smaller shorts |
| 26 | `EA_CF_MeasuredMove.mq5` | `chartfanatics/pdf/measured-move-trend-strategy.pdf` (card #23) | `3226` | H4 | Little RZY structures from fractal swings, trendline through the pullback anchors, measured move projected from the structure extreme as the target, rejection entry, structure stop with a buffer, Bollinger stretch ranking, structure-count + shrinking gates, trendline-invalidation exit |
| 27 | `EA_CF_MomentumModelPerformanceDevelopment.mq5` | `chartfanatics/glimpse/WDdvnd9vLbM.md` (card #24) | `3227` | M15 | Process monitor (never trades): daily report card from deal history (stop violation, early exit, held too long, revenge entry, oversized risk against the grade band), five-whys prompt for the week's top mistake, one-goal-at-a-time focus lock (stop-loss first), A+/A/B/C grading with the doc's 80/15/5 allocation-band audit, one-playbook weekly gate, small-wins row with the single-trade share; R from a live registry snapshot, ungraded when the risk was never captured |
| 28 | `EA_CF_NasdaqIctAndOrderFlowScalpingStrategy.mq5` | `chartfanatics/glimpse/KkTTCKr-3Ew.md` (card #25) | `3228` | M1 | Three-step ICT + orderflow scalping: H4 macro trend (higher highs/lows) + D1 EMA200 + a fair-value pullback band, H1 secondary-structure weakness (lower highs, close below the prior high, volume), then IFBG / change-of-character / break-and-retest on M1 confirmed by a session-POC / VWAP / aggression / absorption proxy for bookmap, tight-stop cap in M1 ATR, liquidity-pool targets with a 1.5R floor, 1R partial + trailing stop, orderflow-flip and sketchy-condition exits |
| 29 | `EA_CF_NqLiquiditySweepReversalScalpingStrategy.mq5` | `chartfanatics/glimpse/-kGVL93XfyE.md` (card #26) | `3229` | M1 | Candice BL's kill-zone scalper: EST windows (London 02:00-05:00, New York 09:30-09:50) on a fixed UTC-5 clock, liquidity sweeps (Asia range via SigAsianRange, swing extremes) into an inverted-FVG entry that must be a fresh full close through the gap, session stop caps in index points (25 London / 40 New York), HTF liquidity-pool targets (Asia range, daily/1H FVG edges, RTH gap quarters, midnight open) with a 2R floor, confluence-count sizing (A+ full / B/C 0.40x), 1R partial + break-even, opposing-1H-FVG half-close and minor-sweep trail, dollar-based daily loss limit |
| 30 | `EA_CF_OptionsTradingMasterclass.mq5` | `chartfanatics/pdf/options-trading-masterclass.pdf` (card #27) | `3230` | M15 | Monitor (never trades) auditing the playbook's five operational lessons: premium as maximum risk (money at risk via EA_LossPerLotAllIn vs a per-position budget; a no-stop position flagged as having no defined premium), time decay (entry-to-exit deal holds vs the day/swing style horizon), liquidity as fills (EA_SlipMedianR + the scope's spread baseline vs budgets), the volatility-crush analogue (day range vs its own median at entry), and sizing (peak deployed risk cap); daily tenet CSV + five-tenets PASS/FLAG card + live registry snapshot; Greeks and open interest disclosed as not implemented, never faked |
| 31 | `EA_CF_OrderFlowStrategy.mq5` | `chartfanatics/glimpse/hvyf6frvCcA.md` (card #28) | `3231` | M2 | Four criteria into two models: generated levels (D1 previous high/low, overnight 02:00-14:29 London, 30-minute ORB) + 70% tick-volume value area / LVN thin bins + big-trade volume-spike proxy + delta / absorption body-volume proxy; range model fades the value edges with a tight stop and midpoint-first partials, the trap fade sells failed breaks of generated levels, the trend model buys pullbacks into LVNs after an accepted break toward the next level or a measured extension; 2-of-4 minimum (3+ = A+ size), first 1-3 hours only, max 3 trades/day, never the middle, never against un-pulled-back momentum, lower-highs structure exit |
| 32 | `EA_CF_OrderflowTradingMasterclass.mq5` | `chartfanatics/pdf/orderflow-trading-masterclass.pdf` (card #29) | `3232` | M5 | Context / Location / Confirmation framework trading the two worked case studies: absorption at a level (heavy volume, no progress, rejection wick, delta-divergence proxy, control flip) and the stop run + reclaim (a flush through the level, entry on the reclaim, stop just below the flush low); levels are the previous day high/low, session extreme, value-area edges / POC and repeated-touch levels (TouchCount); target is the rotation to the session's far extreme with a minimum R floor; DOM / heatmap / footprint proxied by volume and geometry, labelled |
| 33 | `EA_CF_ParabolicShort.mq5` | `chartfanatics/pdf/parabolic-short-strategy.pdf` (card #30) | `3233` | M5 | Three core components as one gate: the move from the last 20-day-MA base must clear the cap tier (200/100/50), the leg must accelerate (range expansion or session gaps, shallow pullbacks), and the exhaustion day must be within two days of the top; exhaustion reads below VWAP with no reclaim, lower highs and lower lows from real pivots; three graded entries (structure break, structure + VWAP loss, failed VWAP reclaim); stop at the high of the day or the most recent lower high; partial then break-even; the risk-free add is gated on the banked partial covering the add risk; expected-move target with the already-moved skip; session-end flat and a strong-VWAP-reclaim exit |
| 34 | `EA_CF_PriceAction.mq5` | `chartfanatics/glimpse/70UtrLU6RAg.md` (card #31) | `3234` | M5 | H1 trend from successive pivot highs/lows; H1 levels at the pivot candle OPEN with confidence scores (5/5, 3/5, 2.5/5) driving position size; three M5 patterns (break and retest, bounce, rejection) with the optional M2 alignment; stops at the pattern wick; 2R target (1.5R floor) capped by the next level; 50% trim at 2R with the stop shifted above entry, a second trim at 3R and the candle-by-candle trail; two attempts per setup from the day deal history; 2-3 trades a day; one-and-done after a win; one-hour execution window after the open |
| 35 | `EA_CF_PriceCycleContinuationFailedBaseStrategy.mq5` | `chartfanatics/glimpse/0_NSmOWVbpA.md` (card #32) | `3235` | M5 | Both cycles: the bullish continuation (rising 50 EMA / above the 200 EMA, tight base on receding volume, breakout with volume or the 10/20-EMA pullback, selection by $50M ADV / 3% ADR / relative strength) with the 1/3 at 2x ADR, 1/3 at 8-10x ATR from the 50-day EMA and the final third trailed on the 10/20-day EMA; and the failed base (20-EMA violation on volume, minimal-volume wedge to a lower high, the turn lower with the stop above the high of day, market confirmation) with the undercut-and-rally and EMA10-reclaim covers and the 3-attempt cap |
| 36 | `EA_CF_RealSimpleStrategy.mq5` | `chartfanatics/pdf/real-simple-strategy.pdf` (card #33) | `3236` | M5 | Six setups with documented entries/stops: EP (first-five-minute ORB, stop at the low of day), delayed HVC (reclaim of the gap-day close), flat base (prior-day-high break with the tight/wide candle stop rule), U&R (reclaim of the prior low, stop at the undercut swing low), MA U&R (reclaim of the 10/20/50-day MA, stop at the reclaim-day low) and the high tight flag (break of the flag high, stop at the breakout-day low); market + relative-strength alignment gate; trims after strong days, the 10/20-day EMA trail and the high-volume below-20-EMA exit |
| 37 | `EA_CF_ShortingStrategy.mq5` | `chartfanatics/pdf/shorting-strategy.pdf` (card #34) | `3237` | M5 | Gap gate (20-40% avoided), entries after the open, the 10:00 a.m. behavior check (below the open, volume declining), bounce entries off the flush low, the backside parabolic read (run-up, upper-wick topping, fading volume), the halt-exhaustion proxy (extreme extension), fixed wide percentage stops, the 30-minute validation via the engine time stop, partials into sharp drops with a re-entry budget for recycling, midday cutoff and the above-the-open reduce-risk exit |
| 38 | `EA_CF_SmallCapShortStatistics.mq5` | `chartfanatics/glimpse/52ZsDmFHqyY.md` (card #35) | `3238` | M5 | Gap up short (100%+ gap, 1-2h consolidation, partial breakdown entry and the 3-5% add, stop above consolidation, 26% fade target); bounce short (old resistance with a 150M+ dollar block, the trapped-to-intraday ratio 2:1+ with 10:1 exceptional driving size, Type 1/2 fade targets); first red day (3+ green days, increasing volume, 300%+ range, the 1/4 scout and the 3/4 add on the volume drop); the setup-statistics CSV with the win-rate bands |
| 39 | `EA_CF_StageAnalysisStrategy.mq5` | `chartfanatics/glimpse/VDK200OHNSo.md` (card #36) | `3239` | D1 stack / M5 | The 10/20/30/40 SMA stack as the four stages (Stage 2 = bullish stack + price above, Stage 4 = bearish + below, converged = 1/3 by range position, mixed = no risk); the Stage 2 entries (close above all four MAs with 10 > 20 and 30, volume confirm, pullback into the 10/20, the first multi-month base after a big move); the Stage 3 scale-out (fails to make new highs while the stack converges) and the 30-MA close exit; the optional Stage 4 mean reversion |
| 40 | `EA_CF_SupportAndResistance.mq5` | `chartfanatics/pdf/support-and-resistance.pdf` (card #37) | `3240` | D1/W1 levels, M5 | Higher-timeframe levels (daily + weekly pivots clustered and weighted, major-level gate, round-number magnets); the catalyst gate (engine red-folder news reader live / volatility proxy in the tester) with the engine blackout; confirmations (bounce or rejection, multi-day hold or reclaim, two higher weekly lows, reclaim-and-stabilise); Sizing for Zero (tiny risk, 20% wide stop, no BE/trail, 5R and 10R scale-outs, monthly horizon as the time stop) |
| 41 | `EA_CF_VixFuturesStrategy.mq5` | `chartfanatics/pdf/the-vix-futures-strategy.pdf` (card #38) | `3241` | M15 | Previous-day levels confirmed (or faked) by the VIX: the confirmed break (VIX at/above its prior-day high, both indices through their lows, the VIX head-start score) and the snap-back squeeze long, both mirrors; the VIX floor reversal (double bottom at the contract-low proxy while the index fails at all-time highs) with the Friday-weakness bonus; the 1% chase veto and the natural-floor caution; mode B long the VIX with the 6:1 R target |

* **Stage policy (card #01)** - `EA_ApplyStagePolicy(cfg, stage)` in `EACore.mqh` is the single stage
  table derived from the 5-Stage framework (quoted per stage, `[interpretation]` marked where the
  document gives no number); the six playbook EAs opt in through `InpStage` (default 5 = no-op) and the
  guardrail EA reads the same helper, so the table cannot drift. Tests in
  `tests/test_chartfanatics_family.py` pin the family contract (unique magics in the block, manifest vs
  files, checker-clean, the monitor never trading, stage 5 a true no-op).
* **Doc sync + bug audit (2026-10-07)** - every playbook was re-read and each stated rule pinned to the
  line implementing it in `tests/test_chartfanatics_sync.py` (rule -> code table, one test per rule;
  deliberate deviations must stay labelled `[interpretation]`). The same pass fixed the findings in
  `chartfanatics/mql5-eas/README.md` ("Rule -> code sync"): a duplicate `OnInitStrategy()` that would
  not compile (SMT+PO3), an out-of-bounds rates read and a hardcoded R table (PO3/OTE+ADR), an
  unguarded twin-bar comparison (SMT), a first-hit-wins raid detector (Intraday), a misread two-bar
  confirmation (Break & Retest), liquidity that could be "swept" before it existed (Structure+OTE),
  and the three rules the playbooks stated but the EAs did not implement (AMD correlation + clear
  target, Break & Retest TP1, Intraday breaker block + midday time stop).
* **Engine reuse** - the family is deliberately thin: signals come from `EASignals.mqh`
  (`SigSweepReclaim`, `SigOrderBlockRetest`, `SigFvgRetest`, `SigBreakRetest`, `SigEmaCascade`,
  `SigFractals`, `SigTwoBarReversal`, `SigRangeForDay`/`SigAsianRange`), windows from `EA_InWindow`,
  discipline from the `RiskGovernor` config, and cost/evidence from the engine's `maxCostR` gate and
  per-EA evidence ledger (`cfg.ledgerEnabled`). Only two detectors are local, both documented:
  `SmtDivergence()` (the engine's own SMT is an RSI-on-DXY proxy that is inert without DXY) and
  `LiquidityRaid()` (`SigSessionFade` only fades in the three hours after a range closes, i.e. the
  02:00-05:00 ET window, while the model trades 09:30-11:30 ET).
* **Static contract validation** - `python3 scripts/check_mql5_source.py chartfanatics/mql5-eas/*.mq5`:
  **6 files, 6 EAs, 0 findings** (CEAStrategy-derived, unique magic, engine delegation, declared
  identifiers, balanced blocks, no MQL4 patterns).
* **Never compiled.** No MetaEditor on Linux - Stage 0 of `docs/EA_VALIDATION_PLAYBOOK.md` is the
  first thing to run on the Windows machine, and `compile_all.ps1` now includes this folder.
* **Disclosed approximations** (also on each card): the AMD "high probability day" news filter is a
  calendar decision and stays off; the PO3/AMD scale-in rules are not implemented because the engine
  holds one position per symbol; `EA_CF_PO3_OTE_ADR` uses daily ATR as the ADR proxy; the
  Structure+OTE breaker fallback inherits `SigSweepReclaim`'s bullish-first evaluation order (the
  order-block path supports `onlyDir` directly); index universes (`US100`/`US500`/`GER40`) are
  broker-dependent and skipped-with-a-log when absent.
