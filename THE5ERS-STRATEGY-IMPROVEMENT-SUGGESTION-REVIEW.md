# Validated Review — "Improving the forex strategy" (submitted suggestion)

Review date: 2026-09-09
Reviewer method: repository-evidence check only. No MT5/MetaEditor, no broker terminal, and no tick/news data exist in this workspace, so nothing here was compiled, backtested, or replayed. Every claim below was checked against the committed source, specification, registry, and validation tooling; all 65 local Python tests pass (`python3 -m unittest discover -s tests -v`).

Purpose: decide whether the submitted suggestion is safe to adopt as the next work plan, correct anything it gets wrong, and identify what it misses. **No strategy rule, EA input contract, or frozen registry was changed to produce this review.** That follows from the suggestion's own (correct) priority-1 premise: freeze before changing.

---

## 0. Bottom line

**Adopt the suggestion as the sequencing plan, with four corrections and three additions.**

The suggestion is unusually well aligned with what this repository already demands of itself:

- It correctly identifies that **no trading-performance evidence exists** in the repo (no replay, no OOS fills, no compiler report, no forward-demo record) and treats that as an evidence gap rather than proof of failure. The repo's own documents say the same thing in multiple places.
- It correctly identifies the **current scope as Sleeve A / M5 session sweep-reclaim on EURUSD-London, GBPUSD-London, USDJPY-New York**, and correctly separates the older three-regime portfolio audit (which is explicitly a *design* audit, not evidence) from the current canonical strategy.
- Its proposed gate order (baseline replay → ablations → challenge-level simulation → forward demo → deployment) matches Section 13 of `THE5ERS-CHALLENGE-STRATEGY-V2.md` and the mandatory release-blocker list in `TRIAD_R_HS-CODE-REVIEW.md`.
- Its research hypotheses are framed as testable questions with "what would justify a change" criteria, and it does **not** propose changing live rules — which is exactly right while the frozen candidate set is unreviewed.

The corrections and additions that matter:

1. **"The current executable strategy" is imprecise.** The three combinations are *candidates*; every per-combination release gate and every global release gate defaults to `false` (`TRIAD_R_HS.mq5` lines 53–63, 102–104), and the EA README states it is **not compile-verified, not backtested, and not approved**. Also, "Sleeve A" in the older audit is not the same rule set as V2 (audit Sleeve A has H1 context, 40/30/30 partial exits, and includes XAUUSD-New York; V2 removes partial closing, has no H1 context, and excludes XAUUSD). "Sleeve A only" is right at the family level, wrong at the rule level.
2. **"Freeze current data" — there is no data to freeze.** The repo contains no tick files, no historical news calendar (only a finite `.example` CSV), and no replay or report outputs. Data must be acquired, provenance-versioned, and excluded from git (the existing `.gitignore` already expects `validation/*.csv` off-repo).
3. **"Run its existing validation process" is not yet possible end-to-end.** The committed Python tool is a *consumer* of a replay export; no committed code **produces** that export. The EA in tester mode writes an event journal with different columns (`server_time,level,event,detail,balance,equity,requests`), not the registry schema (`config_id, split, server_day, sequence, ... fill_fraction, net_r, risk_cash_full, ...`). `tests/` only synthesize rows. Until a replay exporter (or an agreed external producer) exists, steps 1–2 of the suggestion cannot be executed.
4. **The submitted metric list partly exceeds what the current validator reports, and partly omits what it never implemented.** See Section 3 for the exact list. This matters because "run the existing release gates" is stronger than the tool currently supports.
5. **Add the three things the suggestion misses:** (a) the replay-exporter gap above; (b) declared Section 13 gates that the validator does not implement (median drawdown, year/regime persistence, joint-probability confidence bounds, firm 10% floor, stress phase simulation); (c) the account-wide router (§12 priority/cost-R/sequence selection) is **not applied before aggregate gates or phase simulation** — the validator has the daily lock and two-trade cap, but no priority/cost router and no per-day mutual-exclusion of colliding signals.

---

## 1. Confirmed claims (with evidence)

| Suggestion claim | Verdict | Repository evidence |
|---|---|---|
| No historical replay results, OOS fills, compiler report, or forward-demo record in the reviewed files | **Confirmed** | `find` returns zero `.csv`/`.log`/report files; only `validation/triad_v2_1_registry.json` is tracked. `.gitignore` excludes `validation/*.csv` and `*_report.json` and `*.ex5`. EA README: "not compile-verified, not backtested, and not approved". Code-review doc: "These checks inspect text and independent arithmetic only. They do not compile or execute MQL5." |
| This is an evidence gap, not proof the strategy fails | **Confirmed / fair** | `THE5ERS-CHALLENGE-OPTIMIZATION.md` (executive conclusion) and the audit ("This is a design audit, not evidence that any strategy is profitable... every ... figure ... is an assumption until independently reproduced") say exactly this. |
| Current scope = Sleeve A only, M5 session sweep/reclaim, on EURUSD-London, GBPUSD-London, USDJPY-New York | **Confirmed (scope), imprecise (status)** | `THE5ERS-CHALLENGE-STRATEGY-V2.md` §3 (line 56 ff.) and EA session table (`LON_EURUSD`, `LON_GBPUSD`, `NY_USDJPY`, lines 3859–3875). But every combination is gated off: `Inp*GatePassed=false` (lines 102–104) with a hard init rejection at 3515–3517. |
| Three-regime portfolio belongs to an older design audit; its return targets and survival aspirations are not demonstrated | **Confirmed** | `STRATEGY-PORTFOLIO-AUDIT.md` objective/design disclaimer; Sleeves B/C (continuation, Asian MR) are explicitly disabled in V2 §3. Bonus: the audit itself says it is not evidence. |
| Entry combines sweep depth, three-bar reclaim, wick geometry, displacement, 50% retracement limit | **Confirmed** | V2 §5; EA inputs `InpSweepAtrMin=0.05`, `InpSweepAtrMax=0.50`, `InpReclaimWickMin=0.60`, `InpDisplacementBodyMin=0.60`, `InpReclaimBars=3`, entry = midpoint of displacement body (lines 117–126, 2329). |
| 160-candidate registry is frozen and must be kept frozen | **Confirmed** | `validation/triad_v2_1_registry.json`: exactly 160 unique `config_id`s; SHA-256 over matrix/schema/etc.; validator rejects mutations; test `test_registry_hash_detects_any_candidate_mutation` passes. |
| One-position limit + first-net-positive daily lock mean per-combination results cannot simply be added | **Confirmed** | V2 §2/§9 (line 231: any first-trade net profit locks the day even below $12.50), §12 one-order system; validator `simulate_phase` enforces `completed>=2` and `completed==1 and day_net>0 → break` (line 681). **But see Section 3.3 for the router gap.** |
| $2,500 account, 0.25–0.40% risk ⇒ $6.25–$10 planned risk per trade | **Confirmed** | Registry `risk_fraction` 0.0025–0.0040; V2 §8 table (D $6.25, A $10.00). |
| Entry filters may improve selection or remove good trades; treat as hypotheses | **Confirmed / correctly hedged** | Nothing in the repo contradicts it; V2 §13 also treats entry parameters as test candidates, and the optimization doc warns against pre-data tuning. |
| Keep selection separate from untouched final holdout; do not reuse holdout as fresh evidence | **Confirmed** | Registry `selection_split=WALK_FORWARD`, `holdout_split=HOLDOUT`; validator rejects HOLDOUT rows during selection; `test_holdout_outcomes_cannot_change_selected_champion` passes. |
| If release gates fail, reject rather than tune the same holdout | **Confirmed** | V2 §13: "A failed gate results in rejection or lower risk—not looser loss limits." |
| Expansion (continuation, Asian MR, more symbols/indicators) only after independent evidence | **Confirmed** | V2 §3 disables them; audit §6.5 hard gates; optimization doc Priority 3. |
| Small-positive day can end a day without meeting the profitable-day threshold | **Confirmed** | V2 §9 rule 2 + §10 threshold $12.50; the validator's day counter increments only on `day_net >= qualifying_cash`, so the lock is real but unflagged (Section 3.2). |
| Do not force extra trades to manufacture qualifying days | **Confirmed** | V2 §9 rule 8 and §10 controls already prohibit day-counter-driven entries. |
| Any alternative to the daily lock requires checking the applicable account agreement first | **Confirmed** | `THE5ERS-CHALLENGE-V2-REVALIDATION.md` §16 lists written support clarification as required before live activation. |

---

## 2. Corrections and precision needed

1. **"Prove the edge" should be "estimate the edge within stated uncertainty."** No replay can prove challenge passage; V2 itself states no drawdown guarantee exists under gaps/outages/rejected closes. The suggestion's own wording ("Any numerical pass probability must come from actual data and stated simulation assumptions") is the right standard — keep that as the framing so "prove" never becomes a deployment claim.
2. **"Current executable strategy" → "current candidate strategy (frozen, unapproved)."** All release gates are `false`; nothing is executable for the challenge today. The suggestion actually says the correct thing later ("keep every combination disabled until its existing release gates pass") — just make the opening statement match.
3. **"Freeze the current code, data, and 160-candidate registry" — the data clause is empty.** Recommend: freeze code + registry now; acquire and version data next, recording vendor/broker, date range (V2 §13: 2019 → latest), tick quality, DST conversion assumptions, and source hashes in the release record; keep the data outside git.
4. **Ablation "current setup" must be defined against the frozen EA build, not the prose.** The proposal is build `TRIAD_R_HS_2.1.5_20260904`; the existing code review covers 2.1.4 and explicitly says 2.1.5 needs a fresh review, compile, and runtime validation. Also, the entry-geometry inputs are contract-locked in the EA (`Initialize` rejects any value other than 0.05/0.50/0.60/3, lines 3468–3474), so ablations **cannot be done via EA inputs** — they need a separate research reference/replay implementation. `tests/triad_reference.py` is explicitly "not a backtest" and only covers arithmetic, so it is not that implementation yet.
5. **The "first executable quote after confirmation" variant conflicts with live rule §2/§5.8 (no market chase / no replacing an expired limit with a market order).** That is fine for a research-only variant, but the variant must state: (a) whether it is a market order or a limit at the touch; (b) the fill model (spread + slippage); (c) how the 0.10R cost gate and the 0.60–1.50×ATR stop-distance gate are handled, because changing the entry point changes *both* R and stop distance — otherwise an ablation result is confounded by the cost and geometry gates rather than measuring the entry rule.
6. **Hold the fixed-difference principle in the ablations.** The simple reclaim alternative must define: the same sweep band (0.05–0.50 ATR), the same reclaim window (3 completed M5 bars), the same wick rule or the explicit removal of it, the same stop rule (`sweep_high/low ± 0.10 ATR`), the same target/time-stop, and the same lot/cost engine. One change per variant, exactly as the suggestion intends — the registry's CSV schema already supports this (per-variant rows with `config_id`, `combination`, `candidate`, fill fields).
7. **Timing of the ablation round.** V2 §13 step 1 requires the event/entry definition to be frozen *before* development. Therefore the ablation round must be registered as a **new evaluation plan with a new matrix and new data splits**, and if any ablation is adopted, the *entire* Section 13 pipeline must re-run on fresh windows — not spliced into the frozen selection. The suggestion says the second half of this but not the first; state it explicitly so the two processes never share evidence.
8. **§3's "minimum lot sizes force skips" is probably the wrong failure mode for these majors.** With a 0.01 minimum/step and ATR-scaled stops (typically ~10–30 pips), the expected effect is not a skip but **actual realized risk far below the $6.25–$10 budget** (e.g., 0.01 lots × ~20-pip stop ≈ $2). That changes cash outcomes and the $12.50 qualifying-day math, which is precisely why the repo's optimization doc already lists "frequency of minimum-lot skips and winner amounts below $12.50" as a required metric (Priority 2, item 8) and why V2 §8 says nominal profile values "do not prove that a rounded live winner qualifies." The suggestion should measure both directions: skip rate *and* budget-underuse rate, plus per-symbol tick-value reality (never assume $10/pip — the EA already reads tick value/contract size and the code-review checklist flags broker reconciliation).
9. **§1's "run the existing validation process" — be explicit about which parts need the user's Windows MT5.** Compile, MetaEditor harnesses, real-tick Strategy Tester, and forward demo cannot run in this workspace. The repo's own required sequence (EA README) and the 13-item release-blocker list (`TRIAD_R_HS-CODE-REVIEW.md` lines 123–139) should be adopted wholesale by the implementation order rather than paraphrased into five steps; the suggestion currently compresses "fault-injection drills, broker order/deal reconciliation, calendar verification, tick-exact MFE/MAE, single-terminal demonstration, purchased-agreement verification" into "test lifecycle failures."
10. **"Without changing the definitive holdout" — the split dates are currently not predeclared anywhere in the registry.** The registry names splits (`WALK_FORWARD`, `HOLDOUT`) but not the calendar cut. The replay producer must predeclare the cut (and arguably record it in the registry version) before any data is generated, otherwise the holdout boundary is decided after seeing data — the exact failure mode V2 §13 forbids.

---

## 3. Repository gaps the suggestion should carry (it does not currently say these)

### 3.1 No replay exporter exists (biggest blocker for the plan's step 2)

- The validator schema (registry `csv_fields`, tool `schema`) needs per-config, per-combination, **per-day** rows including no-candidate days, conservative fill fields, and full/half-tier cash outcomes.
- The EA's only file writer is the event journal (`LogEvent`, fields `server_time,level,event,detail,balance,equity,requests`, lines 296–302). None of the schema fields (`config_id`, `limit_touched`, `fill_fraction`, `net_r`, `risk_cash_full`, …) appear in the EA source.
- `tests/` build rows synthetically; `tools/triad_validation.py` consumes but does not generate them.
- Consequence: "run its existing validation process using broker-relevant bid/ask tick data" has no working producer. The plan needs a first work item: **build and contract-test the replay exporter** (from MT5 real-tick tester history and/or external tick data), with explicit no-lookahead rules, DST/server-day mapping, and news-calendar application. Until then, no replay CSV can exist.

### 3.2 The validator does not implement every declared Section 13 gate (or the suggestion's own metrics)

Current `phase_simulation_report` / `metric_report` emit: fills, expectancy R, profit factor, wins/losses/scratches, per-combination R stats, rule-violation and operational-error counts, touch-without-trade-through, partial-fill observations, p95/p99 max drawdown, median joint completion days, and point-estimate phase probabilities. Checked against V2 §13 and the suggestion:

| Required by V2 §13 / suggestion | Tool status |
|---|---|
| Net expectancy, trade count, fill uncertainty, results by symbol/session | **Implemented** (R-based; uncertainty via block bootstrap CI) |
| Median, 95th, 99th percentile max drawdown | **Median (p50) missing** (only p95/p99 reported) |
| Time in drawdown | **Missing** (suggestion asks for it; added value, no conflict) |
| Formal fill rate (fills ÷ eligible signals) | **Partially served**: touch-without-trade-through and partial-fill counts exist; no per-combination fill-rate ratio or eligible-signal denominator |
| Joint two-phase pass probability "reported with confidence bounds" | **Point estimate only** (fixed seed per config; no binomial/interval around the probability) |
| "No single year/regime responsible for the entire profit" | **Not implemented**; WALK_FORWARD rows are pooled, not reported fold-by-fold; no per-year/per-regime persistence check |
| "No simulated path touches the firm's 10% overall floor"; stress overshoot ≤1% | **Not implemented** (only internal p99≤6% check; paths stop at 5% shutdown and firm floor is not tracked) |
| Positive expectancy at 1.5× spread / 2× slippage | **Implemented as R gate**; stressed *phase* simulation not run |
| No historical 30-day inactivity failure | **Implemented** (`inactivity` outcome) |
| Zero simulated rule violations / operational errors | **Implemented** |
| $12.50 qualifying-day cash math per combination | **Implemented in simulation**, but per-combination *cash* metrics are not part of the per-combination report (R only) |
| Frequency of locked small-positive days (0 < day_net < $12.50) — suggestion §5 | **Missing** from reports (logic exists in `simulate_phase` line 681) |
| Volume-rounding skip / underuse frequency — suggestion §3 | **Data available in CSV** (`risk_cash_full/half`, `net_cash_full/half`) but **not aggregated in reports** |

Net effect: the plan must include a **validator completion workstream** (report-only extensions plus the missing declared gates) **before** calling the baseline "existing release gates passed." These are tooling changes, not strategy changes; they do not touch the frozen registry and remain compatible with its hash.

### 3.3 The account-wide router is under-modeled in aggregate gates and phase simulation

- The validator pools rows from independently-eligible combinations and computes aggregate gates over **all** fills (`portfolio_rows` → `metric_report`), then feeds trades to `simulate_phase` sorted by `(sequence, event_id)`.
- `simulate_phase` does enforce the two-trade daily cap and the first-net-positive day lock — good.
- It does **not** apply §12 collision routing: frozen combination priority (1–3), then lower all-in cost/R, then first completed signal. `priority` appears nowhere in `tools/triad_validation.py`, and the registry's selection rule does not mention routing.
- Consequence: when EURUSD and GBPUSD both signal on the same London day (both windows overlap 07:00–11:00), both fills enter aggregate statistics even though reality would route one; the ≥300-fill gate can be satisfied by trades that the live one-position rule would discard; and the phase simulation can take a "second trade" that the router would never have created. This is exactly the "standalone results cannot simply be added together" problem the suggestion raises — it is **stronger than the suggestion states**: the current tool mostly *does* add them together in the aggregate gates, then applies only the day-lock/cap inside the phase simulation.
- Required fix (tooling, not strategy): apply the frozen priority/cost-R router to per-day routed events *before* aggregate gates and phase simulation, and report both routed and un-routed diagnostics.

### 3.4 Miscellaneous but material

- **Build 2.1.5 needs fresh static review + compile + harness** — the only code review on file covers build 2.1.4 (its header says so). "Compile and test" must not be interpreted as "the 2.1.4 findings are resolved."
- **Data provenance/versioning is not part of the frozen registry** — no data range, vendor, or tick-quality fields. The release record must carry them; otherwise the "frozen data" in step 1 is unverifiable.
- **Calendar/account verification is human work**: runtime news coverage is an operator declaration (README news-CSV contract), and product/phase/agreement checks cannot be queried by the EA. The suggestion's §1 "verify account-specific rules and broker economics" should be expanded with the revalidation §16 items (exact server rollover, one-position interpretation, 50% drawdown-reduction acceptability) rather than left as an implementation detail.

---

## 4. Section-by-section verdict

| Suggestion section | Verdict | Notes |
|---|---|---|
| Assessment | **Sound** | Evidence-gap framing matches the repo. |
| 1. Baseline before changes | **Adopt, with additions** | Correct and highest priority; must be preceded by building the replay exporter (3.1) and completed by extending the validator (3.2, 3.3). |
| 2. Entry complexity ablation | **Adopt as separate, preregistered round** | Correct hypothesis framing; needs exact variant definitions against the frozen build (2.4–2.7), a new matrix/splits, and cost-gate de-confounding. |
| 3. Missed fills / small-account sizing | **Adopt** | Right concerns; add budget-underuse rate, per-symbol tick value, per-combination cash metrics; the tool needs report extensions. |
| 4. Edge vs challenge risk | **Adopt** | Aligns with §13; add joint-probability CIs and per-combination cash reporting; the "common-risk-level" comparison is a reasonable pre-registered study, not a change to the frozen selection. |
| 5. Opportunity cost of daily lock | **Adopt (measurement only)** | Premise verified; the lock is already simulated; alternative must wait for the written support clarification (revalidation §16). |
| 6. Expand only after evidence | **Adopt** | Matches V2 §3; no new sleeve/indicator now. |
| Implementation order | **Adopt with merge** | Map the five steps onto the EA README's 8-step sequence + the 13 release blockers; insert "build replay exporter" and "extend validator/router modeling" as step 0/2; mark which steps require the user's Windows MT5 + broker data + purchased account. |

---

## 5. Recommended next actions (no strategy changes)

**P0 — evidence pipeline (default branch work, do first):**
1. Register (in the repo) the replay-export contract + exactly how MT5 real-tick tester output or external tick data maps to the registry schema; build the exporter and a round-trip/coverage test. Predeclare the WALK_FORWARD/HOLDOUT calendar cut before generating anything.
2. Extend `tools/triad_validation.py` (report-only + gate) to implement all declared §13 items currently missing: median max drawdown, time-in-drawdown, formal fill rate, joint-probability confidence bounds, per-year/regime persistence, firm 10%-floor and stress-overshoot checks, stressed phase runs, per-combination cash metrics, min-lot skip/underuse and locked-small-positive-day counts.
3. Apply the §12 router (frozen priorities → cost/R → first signal) before aggregate gates and phase simulation; keep un-routed diagnostics for audit.
4. Acquire and provenance-version broker tick data (2019→latest, per §13) and an independently verified red-folder calendar; keep out of git; record hashes in the release record.

**P1 — first real evidence:**
5. Fresh static review + MetaEditor compile of build 2.1.5 (user's terminal), archive compiler output/EX5 hash; deterministic MT5 harnesses; fault-injection drills per the 13 release blockers.
6. Produce the replay export, run `tools/triad_validation.py validate`, and record the full champion-or-rejection result. No combination is enabled and no profile is chosen until this report exists and the per-combination gates pass.

**P2 — ablation round (only after P1):**
7. Preregister a new matrix (registry v2.2-style research addendum) with the exact ablation variants (simpler reclaim; first-executable-quote-with-costs; single wick/body restriction removed per variant), new splits, and the fixed-difference controls. If a variant wins, re-run the whole P1 pipeline on fresh windows before anything is adopted. **Status: the preregistration scaffold is implemented now (Appendix D); the round itself remains data-gated and cannot run until P1's evidence pipeline produces a real observed-event export.**

**P3 — challenge-rules and execution evidence:**
8. Written support clarifications (one-position interpretation, 50% drawdown tier, exact rollover), purchased-agreement verification, 30–50 forward-demo fills on the exact broker/server, and reconciliation vs. the model (fills, commissions, swaps, stops, request counts, dashboard days).

**P4 — deployment decision:**
9. Only with P1–P3 complete and all gates green: freeze the champion release, obtain explicit user approval, and enable the exact combination gates.

**Explicit non-actions while P0–P2 are pending:** no change to entry/exit/risk rules; no change to the 160-candidate registry; no addition of sleeves, symbols, indicators, continuation, or Asian mean reversion; no rounding volume up; no relaxing of any gate to make a candidate pass; no use of the final holdout for tuning.

---

## Appendix A — Evidence index (checked in this review)

- `THE5ERS-CHALLENGE-STRATEGY-V2.md` — §3 (line 56: Sleeve A only; lines 58–68: candidate combos + disabled scope); §5 entry; §8 profiles (lines 193–196: $10.00/$6.25); §9 rule 2 (line 231: any net profit locks day); §10 (lines 247–253: $12.50 formula); §13 (lines 328–380: data, anti-overfit, gates, failure policy).
- `MQL5/Experts/TRIAD_R_HS/README.md` — status warning; 8-step required validation sequence; input-gate defaults; news CSV contract; tooling description.
- `MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5` (build 2.1.5) — lines 53–63 release gates false; 96–104 session enables true / per-combination gates false; 117–131 entry-geometry + contract values; 296–302 journal writer only; 2067–2091 displacement check; 2219–2229 volume grid anchored at `SYMBOL_VOLUME_MIN`; 2329 entry at displacement midpoint; 3468–3474 contract-locked inputs; 3515–3517 combination-gate rejection; 3859–3875 session table.
- `validation/triad_v2_1_registry.json` — 160 configs; `fill_policy` (trade-through requirement, 10% stress miss); `selection_split`/`holdout_split`; `simulation` (2,000 selection paths / 10,000 holdout paths, block 5 days, 30-day inactivity, targets); `thresholds` (100/300 fills, 0.20R, PF 1.15/1.30, pass probs, 99% qualifying-days, p99 DD 6%); registry SHA-256.
- `tools/triad_validation.py` — `metric_report` keys (494–536); `simulate_phase` day lock/cap (657–725, line 681); `phase_simulation_report` keys (741–803); `phase_gates_pass` (806–840); `select_champion` (907–1040, holdout rejection, frozen-before-holdout, adjusted CI); no `priority`/router application anywhere; no per-year/regime check; no time-in-drawdown/median-DD/firm-floor checks.
- `tests/` — 65 tests pass; `tests/triad_reference.py` is arithmetic-reference only ("not a backtest"); synthetic-row generation only.
- `STRATEGY-PORTFOLIO-AUDIT.md` — design-audit disclaimer (lines 13–16); Sleeves A/B/C (6.2–6.4); 5–10 year survival design (Section 8); audit Sleeve A ≠ V2 (partial exits 40/30/30, H1 context, XAUUSD candidate).
- `THE5ERS-CHALLENGE-OPTIMIZATION.md` — executive conclusion (no reproducible tick backtest); Priority 2 metric list (incl. min-lot skips and sub-$12.50 winners); Priority 3 (combinations independent, one-of-EURUSD/GBPUSD selection).
- `THE5ERS-CHALLENGE-V2-REVALIDATION.md` — §16 external/data-dependent items; required written support clarifications.
- `TRIAD_R_HS-CODE-REVIEW.md` — covers build 2.1.4 only; 2.1.5 needs fresh review; 13 mandatory release blockers (lines 123–139); static-check disclaimer.

## Appendix B — Commands run

```bash
git status                                   # clean, branch arena/01a08488-forex
find . -type f (csv/log/report enumeration)  # no replay/report artifacts
python3 -m unittest discover -s tests -v     # 88/88 pass after P0 implementation; 115/115 after P2 scaffold
grep -n config_id|limit_touched|... mq5     # replay schema absent from EA source
python3 tools/replay_export.py selftest      # synthetic round trip OK
python3 tools/triad_validation.py validate   # end-to-end smoke OK (NO_CHAMPION on synthetic data, as expected)
python3 tools/triad_ablation.py schema       # ablation row contract = v2.1 CSV schema + variant IDs
python3 tools/triad_ablation.py preregister --output validation/triad_v2_2_ablation_registry.json
python3 tools/triad_ablation.py build ...    # synthetic CLI smoke (50,400 rows) -> OK
python3 tools/triad_ablation.py validate ... # synthetic CLI smoke -> NO_CHANGE_SUPPORTED / VARIANT_SUPPORTED (synthetic only)
```

## Appendix C — P0 implementation status (added after the review was accepted)

The P0 plan items 1–3 from Section 5 are now implemented in the repository, **without changing the frozen registry, the EA source, or any strategy rule** (`validation/triad_v2_1_registry.json` hash and the 160-config matrix are unchanged; `git status` shows only new/edited tooling, tests, this file, and the EA README).

| P0 item | Status | Where |
|---|---|---|
| Replay exporter contract + round-trip test | Done | `tools/replay_export.py` (`schema`, `build`, `selftest`); split cut must be predeclared and is enforced; same-session repeat signals never become orders; per-config entry/stop/cost/lot/target/time-stop/breakeven arithmetic mirrors the frozen EA contract |
| Validator extension: gates/metrics currently missing | Done (report-only + gates) | `tools/triad_validation.py`: median max drawdown, time-in-drawdown, candidate/activated/fill-rate metrics, per-combination cash metrics, small-positive vs qualifying ($12.50) wins, rounded-lot budget underuse, calendar-year robustness, joint-probability Wilson confidence bounds, draw-outcome categories |
| Section-13 firm floor + stress overshoot | Done | `firm_floor_check()` (1000 block-bootstrap paths, 10% overall floor, p99 overshoot ≤ 1% beyond the 5% shutdown); combined into `sec13_verdict()` |
| Section-12 router before aggregate gates/phase simulation | Done | `route_daily_rows()` with `--combination-priorities` CLI; default priorities 1/1/1 (EA default); tie-break cost/R → sequence → session index; demoted rows keep coverage and audit trail |
| Broker tick data + MT5 replay job (P0 item 4) | Not done — requires user's MT5/data | The exporter consumes an observed-event CSV produced by that job; it explicitly does not reconstruct fills from raw ticks |

New tests: `tests/test_extended_validation.py` (23 new cases) — router, metric extensions, phase/floor extensions, exporter contract and round trip. Full suite: **88 tests, all passing.**

End-to-end smoke (synthetic, 451,680 rows; mechanics only, no edge evidence): `replay_export.py build` → `triad_validation.py validate` produced `CHAMPION_FROZEN_BEFORE_HOLDOUT`, froze all three combinations, routed with priorities 1/2/3, passed every holdout point and phase gate, reported a Wilson joint-probability interval (1.0; lower 0.9996 for 10,000 paths), confirmed no firm-floor breach and stress-overshoot compliance — and correctly **failed only `year_robustness`** because the synthetic holdout spanned a single calendar year. That single failure is the gate working as intended (multi-year real data is required to pass it), not a tooling defect.

**Important honest caveat:** the exporter's `selftest` and the new tests use synthetic fixtures. No real tick data, historical news calendar, or broker symbol economics are in the workspace, so **no trading-performance evidence has been produced** — the evidence gap identified by the review remains exactly where it was. The pipeline that will fill it now exists and is contract-tested.

Repository files changed by the implementation (not by the review itself): `tools/replay_export.py` (new), `tools/triad_validation.py` (extended), `tests/test_extended_validation.py` (new), `MQL5/Experts/TRIAD_R_HS/README.md` (tooling documentation).

## Appendix D — P2 ablation scaffold status (added after P0, still data-gated)

The ablation round from plan item 7 is now **preregistered and mechanically wired**, but it is **not evidence**. Everything below is contract and mechanics: the variants, splits, fill policy, thresholds, and decision rules were frozen in `validation/triad_v2_2_ablation_registry.json` **before any real data was generated**, and every acceptance rule is machine-enforced by `tools/triad_ablation.py`. The frozen V2.1 registry, the EA source, and the strategy rules are unchanged (V2.1 registry hash still `d802c2a5…`).

### What was built

| Piece | Where | Notes |
|---|---|---|
| Shared entry/exit/sizing core | `tools/replay_export.py` — `EntrySpec`, `resolve_entry()`, `resolve_prices()`, `resolve_exit()`, `resolve_lots()`, `_row_from_resolved()` | The frozen V2.1 derive path now calls the same core with `BASELINE_ENTRY_SPEC`. Contract test proves the default variant produces **byte-equivalent rows** to the previous implementation (minus the variant config ID). |
| Preregistered ablation registry | `validation/triad_v2_2_ablation_registry.json` — SHA-256 `1fc30a72692e486fb1e55199aa84286ee5964bec428589bd689f4f7ce73ace2c` (revised during the bug review while still data-gated) | 6 runs, declared splits 2019-01-01→2024-12-31 (WALK_FORWARD) and 2025-01-01→2026-08-31 (HOLDOUT), fixed controls (Profile A, 0.40% risk, +1.5R, 45-min time stop, no breakeven move, 30–80/20–80 bands, $2,500 account), fill policy, thresholds, and decision rules R1–R5. Any edit to the payload breaks the hash and is rejected. |
| Ablation rows | Can be built from the same observed-event CSV contract as P0 (`tools/triad_ablation.py build`) | Same CSV schema, same fill policy, same "one signal per session" rule; each row is labelled with its variant ID. The build command **rejects any split that differs from the preregistered declaration**. |
| Paired evaluator | `tools/triad_ablation.py validate` | R1 per-variant gates (fills, per-combination expectancy, profit factor ≥ 1.15, calendar-year robustness, 1.5× spread / 2× slippage stress), then R2 superiority (familywise-adjusted block-bootstrap lower bound > +0.05R), R5 simpler-tie (simpler variants only: ≥ 1.2× opportunity, adjusted lower bound > −0.05R, mean ≥ −0.05R), R3 holdout confirmation (≥ 300 fills on each side, variant expectancy ≥ 0 and ≥ baseline − 0.05R), R4 conflict rule. Emits a full JSON audit report. |

### The registered variants

| Variant | Question | Change vs. baseline | Simpler? |
|---|---|---|---|
| ABL-V0-BASELINE | — | none (frozen V2.1 entry: sweep → reclaim 60% wick → displacement 60% body + midpoint → limit at 50% of displacement body) | — |
| ABL-V1-SIMPLER-RECLAIM | Q1 does displacement confirmation help? | displacement module removed; entry at 50% of the reclaim body | yes |
| ABL-V2-QUOTE-ENTRY | Q2 does the 50% retracement limit help? | entry at the first executable quote after displacement close (cost and stop band evaluated after that quote; documented confound) | no |
| ABL-V3-NO-RECLAIM-WICK | Q3 are geometry filters useful? | reclaim-bar 60% wick filter removed | yes |
| ABL-V4-BODY-40 | Q3 are geometry filters useful? | displacement body threshold 0.60 → 0.40 | no |
| ABL-V5-NO-MIDPOINT | Q3 are geometry filters useful? | reclaim-midpoint direction filter removed | no |

One change per variant; no stacking (R4); no live/EA parameter change may result from this round (a follow-up round must re-register with the best variant as the new baseline and test combinations, on fresh evidence).

### Verification status

- Full suite at time of writing: **129 tests, all passing** (88 from P0 + 27 ablation scaffold + 14 bug-review regressions; see Appendix E for the review details and the small registry revision they caused). Superseded by Appendix F (139/139 after the round-2 pass).
- New tests cover registry hash/tamper rejection, split re-registration enforcement, byte-equivalence of the baseline spec, each variant's entry behavior (including the acceptance cases the frozen rules reject and vice versa), builder coverage/round trip, the R1/R2/R5 decision logic, paired day-level differencing and bootstrap determinism, and two end-to-end CLI scenarios: a flat synthetic market that correctly returns **NO_CHANGE_SUPPORTED**, and a synthetic market where only the simpler-reclaim variant can act, which correctly returns **VARIANT_SUPPORTED** with holdout confirmation.
- No test asserts any performance claim about any variant; the end-to-end cases above are mechanics-only wiring proofs on synthetic fixtures.

### What remains before the round can run

1. P1 evidence: fresh static review + MetaEditor compile of build 2.1.5, deterministic MT5 harnesses, fault-injection drills, and the real observed-event export (broker tick data 2019→latest per §13).
2. Real-data execution of `triad_ablation.py build` (same event CSV as P0) and `triad_ablation.py validate`.
3. Only then can the predeclared R1–R5 rules produce a decision; **no strategy, registry, or EA change may be derived from the two synthetic end-to-end runs.**

Repository files changed by this scaffold: `tools/replay_export.py` (refactored to the shared event core — default-variant output unchanged), `tools/triad_ablation.py` (new), `validation/triad_v2_2_ablation_registry.json` (new, preregistered), `tests/test_ablation_scaffold.py` (new), this review (Appendices B/D).

## Appendix E — Code bug review (performed on fbab6eb, fixed and re-committed)

The P0/P2 tooling was re-reviewed line-by-line plus with targeted adversarial tests. **Confirmed and fixed:**

1. **Breakeven cash mismatch (real economics bug).** For the confirmed-1R breakeven policy, the exporter priced `net_r` at the entry (capped, net of costs — e.g. `−0.074R`) but priced `net_cash_full` from the raw path exit price (e.g. `+$2.30`). The EA actually moves the stop to entry, so the effective fill is entry. Fixed in `resolve_exit` (it now returns the *effective* fill price, entry on a breakeven cap) and `_row_from_resolved` prices cash from it; regression test proves `net_cash_full / risk_cash_full ≈ net_r` and `net_cash_full < 0`. The default (no-breakeven) path and the ablation round (fixed controls, no breakeven move) are byte-identical to before; only breakeven-fixed configurations changed, and they changed to match the EA model.
   - **Ordering flaw in the same code path.** The cap also ignored *when* the +1R confirmation happened: a stop touched at minute 10 was capped by a "confirmation" at minute 15. `resolve_exit` now applies the cap only when the confirmation strictly precedes the exit (stop-touch minute or time-stop horizon); raw stop outcomes stand otherwise — regression-tested both directions. `session_end` has no explicit event time and keeps the documented cap-if-confirmed behavior.
2. **`decide()` crashed on empty paired data** (`float(None)`); now returns `not_adopted` with an explicit reason — regression-tested.
3. **R3 confirmation had no minimum evidence floor**, so a variant could be "confirmed" on a handful of fresh-window fills. Preregistered `minimum_holdout_fills = 300` per side (mirrors the frozen Section-13 aggregate floor), enforced in `evaluate()` and recorded in the report — re-registered while still data-gated (new hash `1fc30a72…`).
4. **Observed-event loader raised a raw `ValueError`** (traceback instead of fail-closed `ValidationError`) for a non-integer `trade_through_ticks`; now caught — regression-tested.
5. **Stop-on-wrong-side not explicitly rejected.** Geometrically unreachable after the sweep/band gates in practice, but the exporter now fails closed on an inverted entry/stop pair (`stop_on_wrong_side`) — regression-tested.
6. **Volume lattice could return a value below `SYMBOL_VOLUME_MIN`** in a sub-EPS boundary case (it was always rejected downstream, but the arithmetic was wrong); count is now clamped at zero.
7. **Stale/misleading preregistration text**: module docstring R5/R3 no longer matched the implemented rules; a dead `opportunity_floor_fraction` setting was frozen into the registry without being used. Docstring corrected and the dead field removed from the registry (re-hashed).
8. `schema` output had a stray quote artifact; cleaned.

**Checked and found sound (no change):** registry hash mutability protection; split-guard build/validate; row-day guard; coverage validation; router ranking/demotion; paired differencing; block-bootstrap mechanics and Bonferroni tails; phase simulator day-lock/weekly-stop/inactivity logic; firm-floor path; Wilson intervals; loader dedupe/positive-value checks; CLI error paths.

**Known limitations (documented, not fixed):** the replay-row dedupe key does not include `combination` (event IDs must be unique per config/split/day across combinations — the exporter's own IDs are); V2's "first executable quote" is modeled as the displacement close (documented confound in the registry); the frozen net-cash conventions are only guaranteed consistent for non-breakeven configs after fix 1; no real data has been touched, so none of this is edge evidence.

Test suite at round-1 close: **129/129 passing** (115 before this review + 14 new regression tests in `tests/test_bugfix_regressions.py`). Round 2 added 10 more regression tests and 2 expectation updates; current total **139/139** (see Appendix F).

## Appendix F — Bug review round 2 (deeper adversarial pass, on 144789d)

A second line-by-line plus adversarial-property pass was run after round 1. **Confirmed and fixed:**

1. **Stressed cash totals contradicted the stressed expectancy (real metrics bug).** Under `stressed=True`, `metric_report` reported the *stressed* net-R expectancy (e.g. 1.430851 vs the normal 1.468085) but the *normal-scenario* cash totals (`net_cash_total_full` still 13.8000, `all_in_cost_r_mean` still 0.074469) — so the cash and R columns of one report told different stories. Fixed: `_augment_metric_report` sums `trade.cash_result(...)` (which embeds the fill-policy stress cost) for the full/half cash totals, means, the qualifying-cash small/qualifying counts, and `all_in_cost_r_mean` now includes `trade.extra_cost_r`. Normal scenario is unchanged (stress costs are zero there).
2. **Volume sizing breached V2 §6's all-in ceiling.** `resolve_lots` sized on the broker-visible stop risk alone; concrete counterexample: a 0.004 profile on $2,500 ($10.00 risk budget) sized 0.17 lots = $9.69 pure stop risk but **$10.03 all-in** (stop risk + commission + one-side stop slippage) — above the declared ceiling. Fixed: the lattice is solved against the all-in per-lot loss (`per_lot_risk + commission + one-side slippage`), floored at `SYMBOL_VOLUME_MIN`, fail-closed stepped down to the largest compliant lattice value, and returns `(0.0, 0.0)` (row marked `minimum_volume_exceeds_risk_budget`) when even the minimum volume breaches the budget. The same example now sizes 0.16 lots → $9.46 all-in. The returned `risk_cash_full` stays the broker-visible stop risk (frozen CSV schema).
3. **`exit_reason="breakeven"` was misread as time-stop/session-end.** A row whose upstream replay recorded a breakeven exit produced a phantom **+3.70R** "target-like" fill because the reason fell through to the time-stop branch. Fixed: `resolve_exit` has an explicit breakeven branch (effective fill at entry, `effective_reason="breakeven"`, net R = −(spread_r + slippage_r + commission_r), negative net cash), the breakeven-cap logic excludes it (no double application), and the loader now requires `breakeven_hit_minutes` for breakeven exits so the branch can never be ambiguous. Defense in depth: `resolve_exit` now raises `ValidationError` for `exit_reason="cancel"` even when called directly.
4. **Cancelled orders with contradictory fill fields could count as fills.** `exit_reason="cancel"` rows that upstream marked `limit_touched=true`/`fill_fraction=1` reported a +3.70R/$34.80 trade. Fixed: `_row_from_resolved` short-circuits cancel rows through a new `_cancelled()` helper that zeroes fill, risk, cost, and MAE columns and sets `limit_touched=False`, so `apply_fill_policy` always returns `None`.
5. **Unsupported time-stop horizons raised a raw `KeyError`.** A configuration with a horizon outside {30, 45, 60, 90} (loader only validates the 30–90 range loosely) crashed with a traceback; now an explicit fail-closed `ValidationError`.
6. **Budget-utilization metric measured the wrong denominator after fix 2.** `executed_risk_fraction_*` compared broker-visible stop risk against the §6 budget, understating utilization now that volume is sized all-in. It is reconstructed from the R components (`1 + commission_r + slippage_r/2` — `slippage_r` is two-sided, so half is the one-side stop slip; identical to `resolve_lots`' per-lot all-in) and regression-tested.

**Checked and found sound (no change):** re-audited the §6 lattice arithmetic against the EA's `CashLossForVolume`/volume-grid model; the breakeven/cancel/unknown-horizon branch ordering; stress-cost propagation through `AllInCostR` means vs `_all_in_cost_r`; the R-convention divergence (exporter R = per-lot net ÷ broker-visible stop risk with spread charged inside the net, versus the live EA solving take-profit against all-in cash risk) — kept as a documented, frozen-CSV-convention divergence, not silently changed.

**New regression coverage (10 tests, `tests/test_bugfix_regressions.py` + 2 expectation updates):** all-in ceiling counterexample and minimum-volume failure; stressed-vs-normal cash consistency; breakeven honored at entry; breakeven loader timestamp requirement; cancel never counts as a fill; `resolve_exit` refuses cancelled orders; unknown horizon raises `ValidationError`; 120-sample randomized invariant sweep across 40 configs × 4 profiles (row invariants, §6 all-in ceiling per activated row, CSV round trip, fill-policy consistency); bootstrap adjusted-interval containment. The ablation V5 expectation and the utilization-metric test were updated for the corrected §6 semantics.

Test suite: **139/139 passing** across P0 + ablation scaffold + both review rounds. `tools/replay_export.py selftest` OK (84 rows, 6 fills, 8 candidates, synthetic only).

**Registries untouched this round:** v2.1 `d802c2a5…` (160 configs) and v2.2 `1fc30a72…` (6 runs) — unchanged from round 1; no real data touched; no strategy rule, EA input, or frozen registry modified.
