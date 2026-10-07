# 01. 5 Stage Trading Framework

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `5-stage-trading-framework` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/5-stage-trading-framework.pdf) (7.0 MB) |
| **Origin** | [chartfanatics.com/strategies/5-stage-trading-framework](https://www.chartfanatics.com/strategies/5-stage-trading-framework) · [source PDF on Google Drive](https://drive.google.com/file/d/1WKP6UQDCKdrhr79hEXW6pp8C2tiGIp6H/view?usp=sharing) |
| **Board** | [`chartfanatics/TODO.md`](../TODO.md) |
| **Updated** | 2026-10-07 |

> Work this card top to bottom; **tick a box in place and it survives regeneration**
> (`python3 gen_todos.py`), so the checkboxes are the source of truth for status.
> Anything between the `edit:` markers is never overwritten by the generator.

## Stages

- [x] **1. Read source** — PDF / summary reviewed end to end; note page or section refs in Notes <!-- id:read -->
- [x] **2. Extract rules** — Entry, exit, stop, targets, timeframe, session, instruments - in writing <!-- id:extract -->
- [x] **3. Mechanizable?** — Verdict: EA candidate | discretionary checklist | drop (say why) <!-- id:verdict -->
- [x] **4. Write spec** — Unambiguous spec: exact conditions, no 'price reacts' phrasing <!-- id:spec -->
- [ ] **5. Backtest** — Run through validation/mt5_harness; record symbol, period, PF, DD, trades <!-- id:backtest -->
- [x] **6. Implement EA** — New .mq5 with its own magic, or adapt an existing engine; cross-check docs/ICT_SMC_COVERAGE.md <!-- id:ea -->
- [ ] **7. Validate** — Strategy Tester gates + scripts/check_mql5_source.py pass <!-- id:validate -->
- [ ] **8. Demo / forward** — Forward phase per docs/EA_VALIDATION_PLAYBOOK.md, then live decision <!-- id:demo -->

## Tracking

<!-- edit:tracking -->
- **Verdict:** **NOT a signal strategy.** Trader-development framework (stages, mindset, process) - it
  contains no entry, exit, stop, target, instrument or timeframe rule. The mechanizable content is its
  risk-discipline policy, implemented as an engine helper + a process-monitor EA. No entry EA exists and
  none should: building one would mean inventing rules the document never states.
- **Instruments:** n/a (account-wide monitor; no instrument logic)
- **Timeframe / session:** n/a (one account-wide sweep per minute, server-day rollover)
- **EA file / magic:** [`EA_CF_Stage_Guardrails.mq5](../mql5-eas/EA_CF_Stage_Guardrails.mq5) / `3207` (static-checked)
- **Priority:** P2 (policy applies to every EA; the monitor is a process tool)
- **Blocked by:** nothing. Not compiled (no MetaEditor here); nothing to backtest in a non-trading EA.
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
### Framework read 2026-10-07 - verdict: development framework, not a strategy
Read end to end (8 pp, Umar Ashraf). The five stages (Novice / Developing / Intermediate / Advanced /
Pro) describe what a trader does and how they think. Verified absence of trade rules: no entry, exit,
stop, target, instrument, timeframe or session appears anywhere in the document. The only numbers are
stage durations (2-4 weeks, 4-6 weeks combined) - development time, not market logic.

### What was implemented instead (the mechanizable content)
- **Engine helper `EA_ApplyStagePolicy(cfg, stage)`** in `MQL5_Master/Include/EACore.mqh` - the per-stage
  risk posture, quoted line by line from the document and marked `[interpretation]` where the document
  states a principle but no number:
  stage 1 "keep the risk extremely low" -> quarter risk (ceiling 0.25%), 1 trade/day, day locked after the
  first win; stage 2 "still not supposed to be sizing up yet" -> half risk (ceiling 0.50%), 2 trades/day;
  stage 3 "narrow your focus to only 1-2 main setups" -> three-quarter risk, 3 trades/day, 3-loss streak
  pauses 24h; stage 4 "size up gradually, but only on your best setups" + the traps "sizing up too fast"
  and "revenge trade after a loss" -> full risk, 2-loss streak pauses 12h, high-water-mark throttle on;
  stage 5 "trade your proven setups at full size" -> **a true no-op** (the strategy's own settings).
  It only ever tightens, and never touches static-lot sizing.
- **EA `mql5-eas/EA_CF_Stage_Guardrails.mq5`** (magic `3207`) - the account-wide mirror. It never opens,
  sizes or closes a position (`AllowTrading()` and `BuildPlan()` both refuse by design). Every minute it
  sweeps the account's own deal history - every magic, not just its own - and holds the trader to the
  stage's rules, flagging each breach once per day and writing the journal the document demands
  ("journaling is not optional"): `MQL5/Files/cf_stage_journal.csv`, one SUMMARY row per day
  (rollover/deinit) plus one BREACH row per breach type.
  | Document line | Machine check |
  |---|---|
  | "cut-off rules" | daily loss beyond the cut-off % vs the day-start balance |
  | "Narrow your focus to only 1-2 main setups" | entries today vs the stage's trade cap |
  | stage-4 trap "revenge trade after a loss" | an entry within N minutes of a losing close |
  | "Sizing up too fast" | an entry above N x the day's earlier average size |
  | "Breaking rules after a few losing trades" | a losing streak beyond the stage's pause threshold |
- **The six playbook EAs** now each take `InpStage` (default 5 = policy off, so nothing changes unless a
  stage is chosen) and call `EA_ApplyStagePolicy()` at the end of `Configure()`, logging the active
  posture at init. The stage table therefore lives in exactly one place.
- **Not mechanized, on purpose:** the stage descriptions themselves are self-assessment ("ask yourself
  honestly: what stage am I actually in?"). Nothing in the code guesses that for you.

### Stage status
Stages 1-4 and 6 complete. Stage 5 (backtest) and 7-8 (tester gates / forward) are **not applicable to
a non-trading monitor** and are left unticked rather than quietly claimed; the EA's only runtime
artefact is the journal CSV, which is verifiable the first day it runs.
<!-- /edit:notes -->
