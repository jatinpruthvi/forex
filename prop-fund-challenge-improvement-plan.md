# TRIAD-R Prop Fund Challenge Improvement Plan

**Canonical strategy:** `THE5ERS-CHALLENGE-STRATEGY-V2.md` (revision 2.1)
**EA source:** `MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5` (build 2.1.5)
**Challenge target:** The5ers $2,500 New High Stakes — Phase 1 (+10%) + Phase 2 (+5%)
**Status:** Plan — pending user review and approval before implementation

---

## Top-Level Overview

The project is a well-specified, fail-closed MQL5 Expert Advisor that implements a single-sleeve
M5 session sweep/reclaim strategy (TRIAD-R, Sleeve A) designed specifically for The5ers $2,500
New High Stakes two-phase challenge. The architecture is strong: tiered risk governors, a
stateful daily machine, mandatory pre-signal gates, anti-overfit selection framework, and a
comprehensive Python validation pipeline.

**Current status: research implementation — NO-GO for live trading.** Every safety gate defaults
to `false`/`LOCKED`. The key blocker is not strategy design (which is sound) but rather the
absence of completed validation evidence:

1. No tick-quality backtesting data has been fed through the Python pipeline.
2. The MQL5 source has not been compiled in MetaEditor.
3. No forward-demo fills exist.
4. Several EA sub-systems have been corrected through five code-review passes but still carry
   open residual risks identified in `TRIAD_R_HS-CODE-REVIEW.md`.

The improvement plan is organized into **seven sequential sub-tasks** covering the full path from
the current research state to a challenge-ready, evidence-backed release. Each sub-task is
designed to be self-contained, reviewable, and consistent with the lexicographic optimization
priority: zero compliance failures → highest joint two-phase pass probability → lowest 95th-
percentile drawdown → shortest median duration as tie-breaker.

---

## Sub-Task 1 — MetaEditor Compilation and Static Verification

**Status:** `[ ] pending`

### Intent

Establish an executable, compiler-verified EA binary as the mandatory foundation for everything
that follows. No test, drill, or backtest result is meaningful against uncompiled source.

### Expected Outcomes

- `TRIAD_R_HS_2.1.5_20260904.ex5` compiles in MetaEditor with zero errors and no suppressed
  warnings.
- Compiler output, EX5 SHA-256, source SHA-256, MT5 terminal build number, and MetaEditor
  version are archived in a release record file.
- All 48 Python contract tests (`python3 -m unittest discover -s tests -v`) pass against the
  same source.
- `InpCompilationGatePassed` set to `true` in the release configuration only; all other gates
  remain `false` in the committed source.

### Todo List

1. Install the target MT5 terminal build on the development machine (or VPS).
2. Open `MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5` in MetaEditor for that build.
3. Compile; resolve every error and investigate every warning:
   - Verify all `HistoryOrderGet*`/`ORDER_TIME_DONE` enums are present in this build.
   - Verify `CTrade` ticket overloads match the expected signatures.
   - Verify `iATR`/`CopyBuffer` index conventions.
   - Verify `ENUM_DEAL_TYPE`, `ENUM_ORDER_TYPE`, and `ENUM_ORDER_STATE` are correct.
   - Verify fill/expiry mode enum values.
4. Record SHA-256 of source and EX5, terminal build, MetaEditor version.
5. Run `python3 -m unittest discover -s tests -v` and confirm all 48 tests pass.
6. Create `validation/release-2.1.5-compilation.md` capturing all evidence.
7. Update `InpCompilationGatePassed = true` in the release configuration record (not in source
   defaults).

### Relevant Context

- Source: `MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5` lines 1–140 (inputs, enums).
- Code review residual risk #1: verify MQL API overloads on actual terminal build.
- Code review residual risk #2: `HistoryOrderGet*` and `CTrade` ticket overloads.
- Python tests: `tests/test_source_contract.py` (48 tests covering all default gates).

---

## Sub-Task 2 — Tick-Quality Backtest Data Acquisition and Replay Export

**Status:** `[ ] pending`

### Intent

Produce the tick/bid-ask replay data required to feed the frozen 160-config validation
registry. Without this, the statistical gate, champion selection, and all probability
estimates remain unknowable. This is the most critical gap between current state and
a challenge-ready system.

### Expected Outcomes

- Bid/ask tick-quality data obtained for EURUSD, GBPUSD, USDJPY covering 2019-01-01 through
  the latest available period from a The5ers-compatible data source (MT5 Strategy Tester
  real-tick history, Dukascopy, or equivalent).
- Historical Forex Factory red-folder news calendar obtained in UTC and converted to the
  `triad_red_news.csv` schema.
- Europe/London and America/New_York DST boundary mapping confirmed for the full data window.
- MT5 Strategy Tester run with `TRIAD_R_HS.mq5` in real-tick mode producing a signal-event
  CSV in the schema declared by `tools/replay_export.py` (fields: `server_day`, `sequence`,
  `event_id`, `combination`, `direction`, reference/sweep/reclaim/displacement OHLC,
  `atr_m15`, fill flags, exit path, MFE/MAE, actual spread, commission).
- `tools/replay_export.py build` successfully processes the event CSV against the frozen
  registry and produces a `replay_rows.csv` containing:
  - At least one row per config/combo/day for both WALK_FORWARD (2019–2024) and
    HOLDOUT (2025–2026) windows.
  - No-candidate rows for days with no valid signal.
  - Actual rounded lot sizes and cash outcomes, not nominal percentages.

### Todo List

1. Source tick data: MT5 Strategy Tester real-tick history for EURUSD, GBPUSD, USDJPY,
   minimum 2019-01-01, covering spreads and commissions matching The5ers broker conditions.
2. Build or obtain historical Forex Factory calendar (red-folder only) in UTC from 2019
   through current date. Verify completeness independently.
3. Convert calendar to `triad_red_news.csv` schema with explicit `ALL,COVERAGE` row.
4. Configure `TRIAD_R_HS.mq5` in MT5 Strategy Tester:
   - Real-tick mode (not OHLC or 1-minute bars).
   - Set `InpResetTesterStateOnInit = true`, `InpUseEstimatedDaysInTester = true`.
   - Attach news CSV via `#property tester_file "triad_red_news.csv"`.
   - Enable verbose logging (`InpVerboseLog = true`).
   - Run across full 2019–2026 window for all three instruments.
5. Export signal-event CSV from tester logs conforming to `replay_export.py` observed-event
   schema.
6. Run `python3 tools/replay_export.py selftest --tmpdir /tmp/` to confirm producer is
   functional.
7. Run `python3 tools/replay_export.py build` with the event CSV and frozen registry.
8. Inspect output for:
   - At least 100 fills per combination in WALK_FORWARD.
   - No-candidate day completeness (every server day present).
   - Lot rounding behaves correctly (no lots above volume_max, no zero lots logged as fills).
9. Archive `replay_rows.csv` with data provenance metadata.

### Relevant Context

- Registry: `validation/triad_v2_1_registry.json` (frozen 160-config matrix, DO NOT modify).
- Replay producer: `tools/replay_export.py` — read schema section for exact field list.
- Split boundaries: WALK_FORWARD 2019-01-01 → 2024-12-31; HOLDOUT 2025-01-01 → 2026-08-31.
- Code review residual risk #9: tick-exact MFE/MAE and execution-cost records required.
- Optimization doc: `THE5ERS-CHALLENGE-OPTIMIZATION.md` section 2 (small-account lot problem).

---

## Sub-Task 3 — Walk-Forward Champion Selection

**Status:** `[ ] pending`

### Intent

Select ONE champion configuration from the frozen 160-config matrix using WALK_FORWARD data
only, applying the anti-overfit process specified in Section 13 of the canonical strategy.
This sub-task must complete before the holdout window is opened.

### Expected Outcomes

- `tools/triad_validation.py validate` runs against `replay_rows.csv` using WALK_FORWARD
  rows only and produces `validation/champion_selection_report.json`.
- Each enabled instrument/session combination passes its per-combination gates independently:
  - ≥100 out-of-sample fills.
  - Positive net expectancy.
  - Profit factor ≥1.15.
  - No single year/regime responsible for >35% of profit.
  - Passes ≥65% of rolling walk-forward windows.
- Portfolio gates pass:
  - Net expectancy ≥0.20R.
  - Profit factor ≥1.30.
  - Positive at 1.5× spread, 2× slippage.
  - ≥10,000 day/week block-bootstrap paths.
  - Phase 1 pass probability ≥70%.
  - Phase 2 pass probability ≥85%.
  - Joint two-phase pass probability ≥60%.
  - ≥99% probability of three qualifying days by target.
  - P99 max drawdown ≤6%; no path touches 10% floor.
  - Zero simulated rule/state violations.
  - No historical 30-day inactivity failure.
- ONE champion config is selected and frozen before the holdout window is opened.
- Frozen champion config ID, combination priorities, and selection rationale are written to
  `validation/champion-selection-record.md`.

### Todo List

1. Run `python3 tools/triad_validation.py validate` using only WALK_FORWARD split rows.
2. Check per-combination gate results for EURUSD_LONDON, GBPUSD_LONDON, USDJPY_NEW_YORK.
   Disable any combination that fails independently (a winning portfolio cannot conceal a
   losing combination per Section 3 of the strategy spec).
3. Identify configuration plateau: prefer broad performance regions, not sharp peaks.
4. Run ablation study for entry complexity using `tools/triad_ablation.py` against
   `validation/triad_v2_2_ablation_registry.json` to determine whether full V2.1 entry
   complexity is justified or can be simplified.
5. Derive and freeze combination priorities using the predeclared walk-forward training-
   expectancy rule (descending training expectancy, subject to independent gates).
6. Select ONE champion configuration from the non-holdout data.
7. Record champion config ID, risk profile (A/B/C/D), time-stop, range/ATR bands, breakeven
   policy, and combination priorities in `validation/champion-selection-record.md`.
8. Commit the selection record BEFORE running the holdout evaluation.

### Relevant Context

- Validator: `tools/triad_validation.py` — `validate` command.
- Registry: `validation/triad_v2_1_registry.json`.
- Ablation registry: `validation/triad_v2_2_ablation_registry.json`.
- Strategy Section 13: anti-overfit process (frozen event definition, rolling walk-forward,
  coarse candidates only, champion locked before holdout).
- Strategy Section 12: collision ranking requires frozen combination priorities from
  training data before OOS evaluation.

---

## Sub-Task 4 — Holdout Evaluation and Statistical Gate

**Status:** `[ ] pending`

### Intent

Evaluate the frozen champion configuration against the held-out 2025–2026 data to confirm
the edge is not an artefact of the training window. This sub-task may only start after
Sub-Task 3 is complete and the champion is locked.

### Expected Outcomes

- `tools/triad_validation.py validate` runs against the HOLDOUT split using the locked
  champion configuration only.
- Holdout passes the same portfolio gates as the walk-forward (with the HOLDOUT minimum:
  ≥300 aggregate fills across all enabled combinations).
- A second independent Monte Carlo run on holdout data produces phase-pass probabilities
  within the predefined confidence bounds relative to walk-forward results.
- Gap/slippage stress test: P99 overshoot beyond 5% shutdown ≤1%; no path touches 10% floor.
- Zero simulated rule-state violations in holdout replay.
- `validation/holdout-evaluation-report.json` produced and archived.
- `InpStatisticalGatePassed = true` attestation is formally granted.
- `InpStressGatePassed = true` attestation is formally granted.

### Todo List

1. Confirm champion selection record is committed and no changes have been made since.
2. Run `python3 tools/triad_validation.py validate` with HOLDOUT split rows for the champion
   config ID only.
3. Verify ≥300 aggregate fills across enabled combinations.
4. Check phase pass probabilities include confidence bounds (Wilson-score intervals):
   - Phase 1: lower confidence bound ≥70%.
   - Phase 2: lower confidence bound ≥85%.
   - Joint: lower confidence bound ≥60%.
5. Verify ≥99% qualifying-day probability with confidence bound.
6. Run stress scenario: model at 1.5× spread, 2× slippage, 10% missed limit fills.
7. Verify no historical 30-day inactivity gap in holdout replay.
8. Document results in `validation/holdout-evaluation-report.json`.
9. Formally complete and sign `InpStatisticalGatePassed` and `InpStressGatePassed`
   attestation records in release document.

### Relevant Context

- Selection record: `validation/champion-selection-record.md` (produced in Sub-Task 3).
- Holdout window: 2025-01-01 → 2026-08-31.
- Strategy Section 13 portfolio gates (all must pass on holdout).
- Code review residual risk #8: tick-quality evidence per combination with confidence bounds.

---

## Sub-Task 5 — EA Operational Drills and Residual Code-Review Fixes

**Status:** `[ ] pending`

### Intent

Address all 13 residual risks identified in `TRIAD_R_HS-CODE-REVIEW.md` through MT5 runtime
harness testing, and confirm the EA's operational resilience before forward-demo trading.
This sub-task runs concurrently with Sub-Tasks 2–4 for time efficiency but must complete
before Sub-Task 6.

### Expected Outcomes

- All 13 code-review residual risks are explicitly resolved or documented as accepted:
  1. Compile verification (done in Sub-Task 1).
  2. Every used MQL API/enum verified on target terminal build.
  3. MT5 harnesses for: first-event M5 sequences, M15 indexing, both DST mismatch
     periods, quote refresh/ranking, all exact news/session/rollover boundaries, volume
     grids/limits, day/week governor reset.
  4. Restart/offline history drills for pending/position rollover reconstruction,
     order-only foreign-history detection, state-signature rejection, ordinary halt reset,
     and non-resettable migration-latch behavior.
  5. Fault-injection for: unavailable terminal-global writes, stale calendar, malformed
     coverage declarations, duplicate claimant races, stale-owner resumption,
     account/server switching, request timeout/late acknowledgement, partial fill, missing
     stop, incomplete delete/close, disconnect, and failed cleanup retry.
  6. Broker propagation check: comments, magic numbers, SL/TP deal/order reasons,
     commissions/fees/swaps, fill prices, volume lattice/limit, stop/freeze levels,
     expiration, and limit fill behavior.
  7. Calendar declaration verification against independently verified UTC source.
  8. Forward-demo tick MFE/MAE records (done in Sub-Task 6).
  9-13: All other listed residual risks.
- `InpOperationalGatePassed = true` attestation is formally granted.
- `InpExternalRulesGatePassed = true` attestation is formally granted.
- Zero errors or unresolved behaviors across all drills.

### Todo List

1. Build a deterministic MT5 harness (strategy tester scripts) to exercise each residual
   risk scenario listed above.
2. Run first-event M5 sequence: confirm no repeated-sweep reset, no consumed-session race.
3. Run M15 ATR indexing: verify buffer copy direction (0 = current) and history depth.
4. Run DST mismatch period: 2024-03-10 (US spring forward) and 2024-03-31 (UK spring forward)
   — confirm the independent Europe/London vs. America/New_York conversion prevents the
   temporary one-hour error.
5. Simulate rollover while offline: confirm history reconstruction correctly identifies
   pending-order/position spans across server-day boundaries.
6. Fault-inject stale news calendar: confirm `InpRequireNewsCalendar = true` blocks entries
   and logs `NEWS_CALENDAR_STALE`.
7. Fault-inject missing COVERAGE row: confirm fails closed.
8. Simulate duplicate EA instance: confirm claimant-heartbeat-before-owner CAS race is safe.
9. Simulate account/server context switch: confirm frozen identity rejects the new context.
10. Simulate partial fill (less than full lot): confirm EA detects and halts for review.
11. Simulate missing stop-loss after fill: confirm one-attempt repair, then close + halt.
12. Run request-cap drill: reach 20 non-emergency requests and confirm new entries block
    while emergency cancellation/close still passes.
13. Document every drill result in `validation/operational-drills-record.md`.
14. Formally complete `InpOperationalGatePassed` and `InpExternalRulesGatePassed`
    attestation records.

### Relevant Context

- Code review: `TRIAD_R_HS-CODE-REVIEW.md` — residual risks #1 through #13.
- End-to-end checklist: `THE5ERS-END-TO-END-PRECODE-CHECKLIST.md` — Stages 0–3.
- EA source: focus on `OnInit()`, `OnTimer()`, `ManageExposure()`, rollover logic,
  instance-lock logic, and news calendar loader.

---

## Sub-Task 6 — Forward-Demo Validation on Live Infrastructure

**Status:** `[ ] pending`

### Intent

Obtain 30–50 real broker fills on the exact infrastructure (broker, symbols, server, VPS)
that will be used in the challenge, confirming that live economics and EA behavior match the
validated backtested model within predefined confidence bounds.

### Expected Outcomes

- 30–50 filled trades on a demo account matching The5ers broker (or as close as available)
  using the EXACT same compiled EX5, configuration, and news calendar as planned for the
  challenge.
- Zero manual interventions during the demo run.
- Zero account-state, calendar, size, duplicate-order, restart, or stop-attachment errors.
- Live spread, commission, slippage, and fill prices recorded for every trade.
- Live demo expectancy lies within the predefined confidence bounds from the holdout
  evaluation.
- `InpForwardDemoGatePassed = true` attestation is formally granted.
- `InpAccountSpecificGatePassed = true` attestation is formally granted.

### Todo List

1. Open a demo account at the intended broker on the exact MT5 server.
2. Copy `TRIAD_R_HS.mq5` compiled EX5 to the demo terminal's `Experts/` folder.
3. Prepare a current `triad_red_news.csv` with a valid COVERAGE row extending ≥24 hours
   ahead; update it at every UTC day boundary during the demo run.
4. Configure the EA with champion parameters (from Sub-Task 3), but keep
   `InpEnableOrderSubmission = false` for a dry run first:
   - Confirm all 13 mandatory gates produce expected signals and rejections.
   - Verify signal log matches expectations from the harness drills.
5. Re-enable `InpEnableOrderSubmission = true` for the live demo run.
6. Monitor every fill: record entry, stop, target prices; actual fill vs. limit; spread at
   fill; commission charged; exit price; slippage; MFE/MAE.
7. Check every exit: confirm time-stop, session-stop, and target exits all work correctly.
8. Verify qualifying-day arithmetic after each winning day.
9. Simulate a planned restart (MT5 restart while flat): confirm state persistence loads
   correctly and the day counter is intact.
10. At ≥30 fills, compute live expectancy and compare to holdout confidence bounds.
11. Document all fills, errors (expected: zero), and cost comparisons in
    `validation/forward-demo-record.md`.
12. Formally complete `InpForwardDemoGatePassed` and `InpAccountSpecificGatePassed`
    attestation records.

### Relevant Context

- EA README: `MQL5/Experts/TRIAD_R_HS/README.md` — Validation Sequence section.
- Forward gate requirements: Strategy Section 13, Forward Gate (30–50 fills, zero errors).
- Screening tool: `MQL5/Experts/TRIAD_SCREEN/TRIAD_SCREEN.mq5` can be used in parallel on
  a second demo account to monitor dashboard state without interfering with the canonical EA.

---

## Sub-Task 7 — Release Attestation, Challenge Activation, and Monitoring Protocol

**Status:** `[ ] pending`

### Intent

Complete all final attestations, unlock the EA for challenge use, activate the Phase 1
challenge account, and establish the daily monitoring protocol to ensure compliance and
operational integrity throughout the evaluation.

### Expected Outcomes

- All nine safety gates explicitly set to `true` with documented evidence attached:
  `InpStatisticalGatePassed`, `InpStressGatePassed`, `InpOperationalGatePassed`,
  `InpExternalRulesGatePassed`, `InpAccountSpecificGatePassed`, `InpForwardDemoGatePassed`,
  `InpCompilationGatePassed`, `InpExplicitUserApproval`, and `InpEnableOrderSubmission`.
- `InpValidationReleaseId` set to a unique non-LOCKED release identifier.
- Challenge account purchased with confirmed product: **$2,500 New High Stakes** (not the
  2026 Summer 2-Step). Agreement snapshot saved.
- Fresh phase initialization handshake completed successfully.
- Daily monitoring checklist in place and followed without exception.
- Zero rule violations during Phase 1 and Phase 2.

### Todo List

1. Confirm every sub-task above is marked complete and all evidence files exist.
2. Purchase The5ers $2,500 New High Stakes challenge — save receipt and agreement. Verify
   the product shows: 10%/5% targets, 5% daily loss, 10% overall loss, three qualifying days.
3. Complete KYC with account owner's details only.
4. Create `validation/release-record.md` attaching all evidence and signing each gate.
5. Set `InpValidationReleaseId = "TRIAD_R_HS_V2_1_RELEASE_001"` (or similar unique ID).
6. Set all gate inputs to `true` in the release configuration file.
7. Set `InpAuthorizedLogin` to the new challenge account login number.
8. Set `InpExpectedAccountServer` to the exact The5ers MT5 server name.
9. Set `InpPhaseInitialBalance = 2500.0` and `InpPhase = TRIAD_PHASE_1`.
10. First-run initialization: set `InpAuthorizeFreshPhaseState = true`, attach EA, wait for
    `INIT_FAILED` (expected), then set `InpAuthorizeFreshPhaseState = false` and reattach.
11. Confirm EA initializes successfully and logs `INIT_OK`.
12. Verify MT5 account shows zero positions, zero pending orders.
13. Update `triad_red_news.csv` with current calendar + valid COVERAGE row.
14. Begin daily monitoring protocol:
    - Each day: reconcile MT5 balance/equity with The5ers dashboard.
    - Each day: record every signal/no-signal, fill, exit, reason, MFE/MAE.
    - Each day: verify qualifying-day count matches dashboard.
    - At 20 inactive calendar days: log alert; at 25: escalate to human review.
    - Each Friday: confirm flat by 20:00 London.
    - Each rollover: confirm state persists correctly after MT5 overnight.
15. For Phase 1 → Phase 2 transition:
    - Wait for dashboard confirmation of ≥3 qualifying days AND balance ≥$2,750.
    - Set `InpLifecycleLock = LIFECYCLE_PHASE_TRANSITION`.
    - Archive Phase 1 logs and state.
    - Open Phase 2 account, verify credentials.
    - Update `InpAuthorizedLogin`, `InpPhase = TRIAD_PHASE_2`, fresh `InpPhaseInitialBalance`.
    - Repeat initialization handshake.
16. For Phase 2 → Funded transition: same procedure with `InpPhase = TRIAD_FUNDED`.

### Relevant Context

- End-to-end checklist: `THE5ERS-END-TO-END-PRECODE-CHECKLIST.md` — Stages 4–7.
- EA README: `MQL5/Experts/TRIAD_R_HS/README.md` — Installation and Runtime sections.
- Strategy Section 14: full lifecycle procedure (challenge activation through payout).
- Product disambiguation: High Stakes ($2,500, 10%/5%, no consistency rule) vs. Summer
  2-Step ($100K, 3% daily, payout cap, funded consistency rule). Failure to distinguish
  these makes the entire configuration incompatible.

---

## Key Risks and Mitigations

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Tick data unavailable or of poor quality | Medium | High — invalidates entire backtest | Use MT5 real-tick Strategy Tester history for same-broker data; cross-check with Dukascopy |
| No combination passes per-combination gates independently | Medium | High — must disable that combo | Expected: USDJPY NY may be weaker; disable if it fails; EURUSD London most robust |
| Lot rounding makes qualifying-day threshold unreachable on $2,500 | Low-Medium | Medium — slows Phase 1 | Profile D (0.25%, 2.5R) may solve this; replay confirms which profiles qualify |
| News calendar gap causes blocked trading day | Medium | Low-Medium | Maintain calendar with 48-hour lead; COVERAGE row enforced by EA |
| MQL5 DST bug during non-coincident US/UK transition weeks | Low | High — wrong session window | Explicitly tested in drill #4; independent civil-time conversion in EA |
| MT5 terminal restart during live trade | Low | Low (state persists) | Drill tested in Sub-Task 5 and 6 |
| The5ers rule change between plan and execution | Low | High | Re-read agreement at checkout; fail closed if rule mismatch detected |

---

## Implementation Order and Dependencies

```
Sub-Task 1 (Compile)
       |
       +---> Sub-Task 2 (Tick Data + Replay) ---> Sub-Task 3 (Walk-Forward Selection)
       |                                                   |
       +---> Sub-Task 5 (Drills, runs concurrently)        |
                                                   Sub-Task 4 (Holdout Eval)
                                                           |
                                                   Sub-Task 6 (Forward Demo)
                                                           |
                                                   Sub-Task 7 (Release + Challenge)
```

Sub-Tasks 1 and 5 can begin immediately. Sub-Task 2 requires tick data sourcing.
Sub-Tasks 3 and 4 are strictly sequential (champion locked before holdout opens).
Sub-Task 6 requires Sub-Tasks 1–5 complete. Sub-Task 7 requires Sub-Task 6 complete.

---

## Validation Metrics to Track Throughout

| Metric | Target | Minimum Acceptable |
|---|---|---|
| Net expectancy (portfolio) | ≥0.30R | ≥0.20R |
| Profit factor (portfolio) | ≥1.50 | ≥1.30 |
| Phase 1 pass probability | ≥80% | ≥70% |
| Phase 2 pass probability | ≥90% | ≥85% |
| Joint two-phase pass probability | ≥70% | ≥60% |
| P95 maximum drawdown | ≤5% | ≤6% |
| P99 maximum drawdown | ≤6% | ≤8% |
| Qualifying-day probability | ≥99.5% | ≥99% |
| Fill count per combination (OOS) | ≥150 | ≥100 |
| Forward-demo fills | ≥50 | ≥30 |
| Rule violations | 0 | 0 (hard floor) |

---

## What is NOT Being Changed

The following design decisions are intentionally left unchanged because they are:
(a) already well-specified in the canonical strategy, or
(b) changes would require re-validation from scratch:

- Entry geometry (sweep 0.05–0.50 ATR, 3-bar reclaim, 60% wick, 60% displacement body).
- Stop calculation (sweep extreme ± 0.10 ATR, 0.60–1.50 ATR gate).
- Risk profiles (A/B/C/D — selected by validation, not assumed).
- Daily state machine (first-net-positive locks, two-trade max, governor precedence).
- Drawdown throttle (2% → 50% risk; 5% → halt; no other tiers).
- Compliance guardrails (no grid, no averaging, no partial closes, visible stop mandatory).
- News and rollover flat rules.
- Anti-overfit selection process (frozen registry, rolling walk-forward, coarse candidates).
