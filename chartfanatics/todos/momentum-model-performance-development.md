# 24. Momentum Model Performance Development

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `momentum-model-performance-development` |
| **Type** | video-only (Glimpse summary) |
| **Source** | [Glimpse summary](../glimpse/WDdvnd9vLbM.md) · [summary PDF](../glimpse-pdf/WDdvnd9vLbM.pdf) · [YouTube](https://www.youtube.com/watch?v=WDdvnd9vLbM) (@chart-fanatics) |
| **Origin** | [chartfanatics.com/strategies/momentum-model-performance-development](https://www.chartfanatics.com/strategies/momentum-model-performance-development) · [Glimpse](https://glimpse.wozart.com/v/q67mk1ke) |
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
- **Verdict:** Implemented as a **process monitor** (never trades). The document is an eight-minute masterclass on how to DEVELOP a trader - identify mistakes, diagnose with five whys, implement one solution, stack small wins - so there is no entry rule to mechanize; instead the four elements are run against the account: a **daily report card** built from deal history (the mistakes the document names are detected mechanically: a loss beyond the planned risk is "didn't respect the stop", a small winner cut inside 20 minutes is "sold too early", a small winner held for hours is "held too long", plus a revenge entry after a loss - labelled as the fourth slot from the same discipline vocabulary - and risk above the grade's allocation band), a **five-whys prompt** written weekly for the most recurring mistake, the **one-goal-at-a-time** focus lock (stop-loss first - "risk management is the foundation"), **trade grading** A+/A/B/C with the document's 80/15/5 allocation bands audited against the risk actually taken, the **one-playbook** gate (more than one magic traded in a week is flagged), and the **small-wins** weekly row (rule-following trades, win/loss days, and the share of profit carried by a single trade - "not one big breakthrough moment"). Grading uses the engine's own R definition: the executing EA's planned risk is snapshotted into a registry while the position is live, because the engine deletes its risk key when the position closes; a trade whose risk was never captured is reported as **ungraded**, never guessed.
- **Instruments:** the account's own scope (`InpSymbolsToTrade`, default the family's `US100,US500`); `InpMagicFilter` 0 = every magic on that scope
- **Timeframe / session:** M15 context tick for the once-a-day / once-a-week writers; no session gate (a review runs after the day/week closes)
- **EA file / magic:** [`EA_CF_MomentumModelPerformanceDevelopment.mq5`](../mql5-eas/EA_CF_MomentumModelPerformanceDevelopment.mq5) / `3227` (static-checked)
- **Priority:** P1 - the process half of the family: it is what turns the other cards' mistakes into data
- **Blocked by:** _nothing_
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: the friction cycle and perfectionism (the report card is data collection, not
  self-criticism), the four-element momentum model (identify - diagnose - solution - friction/small wins),
  one goal at a time ("research shows working on two goals simultaneously means you'll fail at both";
  risk management is the foundation), the trade-grading system (A+/A/B/C with 80/15/5% of the daily stop),
  playbook development (master one before adding others; ~4 developing / 18-25 experienced), the P&L-curve
  reality and the "click moment" myth (compounded small wins), the 9-EMA trade example (the exit rule and
  "not working vs not working yet"), the 10-year horizon and pods, market-shift adaptation, and the AI /
  five-whys action items.
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_MomentumModelPerformanceDevelopment.mq5`
  (35 rules pinned).
- `[interpretation]`: the grade thresholds (A+ >= 2R, A >= 1R, B > 0, C <= 0 or flagged), the A allocation
  band (40% - the document gives A+, B and C only), the A+/B/C bands' tolerance, the early-exit / held-too-long
  / oversized thresholds, the 30-minute revenge window (the fourth report-card slot) and the holding-time
  proxy for "held too long" are engineering numbers, exposed as inputs and labelled in the source. Pods, the
  10-year horizon, "study the new market" and the qualitative grade of a setup have no platform signal and are
  disclosed, not faked.
- Design note: the R multiple is the engine's own planned risk (`EA_LossPerLot x volume`), snapshotted by a
  registry while the position is live, because the executor deletes its risk key when the position closes. A
  position the monitor never saw live (or one with no stop and no persisted key, or an unpriceable symbol) is
  reported in the `ungraded` column - the monitor never invents an R.
- Self-review fixes: the registry is keyed by the position IDENTIFIER (what history reports as
  `DEAL_POSITION_ID`) while the engine's persisted key is read by its own ticket; the win/loss-day count moved
  from a report-file re-read to the trades themselves; the worst stop violation now logs symbol/direction/prices;
  the unused-price fields and the scan throttle were reworked (per-symbol).
- Engine reuse: `EA_LossPerLot`, `EA_Log`, `EA_Tick`, the engine symbol list, `EA_ApplyStagePolicy`.
<!-- /edit:notes -->
