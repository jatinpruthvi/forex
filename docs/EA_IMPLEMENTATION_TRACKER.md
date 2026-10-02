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

## 5. Verification Performed (2026-10-01, extended 2026-10-02, sixth audit pass)

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
* **Validation tooling (2026-10-02)** - MT5 allows one EA per chart, so the 65 EAs are validated headlessly instead: `validation/mt5_harness/gen_tester_configs.py` generates one Strategy Tester config and `.set` per EA (read straight from the generator, so configs cannot drift), `run_all.ps1`/`run_all.bat` drive `terminal64.exe /config:` for all 65, every run writes one machine-readable row via the new tester-only `EA_TestReport()` (`EACommon.mqh`; no effect live), and `validation/mt5_harness/parse_results.py` produces a PASS/WARN/FAIL portfolio table plus the list of EAs that produced no row at all (i.e. compile failures). `MQL5_Master/Scripts/UniversePreflight.mq5` reports which of the EAs' symbols the broker actually offers and which index alias it uses, because the engine skips-and-logs unavailable symbols and an inert sleeve otherwise looks like "the EA does not trade". See `docs/EA_VALIDATION_PLAYBOOK.md`.
* **Documented approximations (disclosed)** - `EA_studyarena_round12_contestant_c` turns its document's "20th-85th ATR percentile band" into an ATR-vs-median ratio of 0.6-1.6 and says so in a code comment. The four EAs whose documents name a spread-versus-history gate that the first pass had served with a round-local sample ring (`EA_studyarena_round8_contestant_d` and `EA_studyarena_round12_contestant_a`: "median for that time of day"; `EA_studyarena_round5_contestant_a_2047`: "1.5x that pair's normal spread for the same time"; `EA_TRIAD_SURVIVE`: "at most 1.5x the 20-day average spread") now query the engine baseline `EA_SpreadBaseline(sym, 30)` / `(sym, 720)` first and fall back to the local ring only while the engine has no evidence yet, so the statistic matches the documents (live-learned 20-day per-minute-of-day average, 30-minute or whole-day window).
