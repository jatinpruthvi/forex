# 07. Break & Retest

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `break-retest` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/break-retest.pdf) (20.9 MB) |
| **Origin** | [chartfanatics.com/strategies/break-retest](https://www.chartfanatics.com/strategies/break-retest) · [source PDF on Google Drive](https://drive.google.com/file/d/1vsC6ZUlx2rOiqHdKtukgyiEAGxjp2mQ1/view?usp=sharing) |
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
- **Verdict:** _TBD_
- **Instruments:** _TBD_
- **Timeframe / session:** _TBD_
- **EA file / magic:** [`EA_CF_Break_Retest.mq5](../mql5-eas/EA_CF_Break_Retest.mq5) / `3205` (static-checked)
- **Priority:** _TBD_ (P1 = do next, P2 = queued, P3 = nice-to-have)
- **Blocked by:** _nothing_
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
### EA implemented 2026-10-07
- **Source read:** `pdf/break-retest.pdf` (7 pp, Vincent Desiano) - break the level, never trade the break; trade the retest inside the battle zone.
- **EA:** [`mql5-eas/EA_CF_Break_Retest.mq5`](../mql5-eas/EA_CF_Break_Retest.mq5), magic `3205`, M5.
- **Encoded:** premarket range (00:00-14:30 London) with a clean break + buffer and a LATER retest bar that holds (`SigBreakRetest`); rejection-wick confirmation on the retest bar; stop beyond the retest structure; TP1 partial 50% at 1R with runners trailed.
- **Gaps (approximation):** the No Trade Zone is implemented as the previous day's high-to-low band, while the playbook describes it as "between the previous day's high and the premarket low" - the narrower BIS-style band would need a premarket-specific low rather than a PDH/PDL pair.
   - The playbook's "rejection / engulfing" confirmation is the engine's own pin+engulf detector (`SigTwoBarReversal`) alongside the wick test, not a second hand-rolled candle matcher.
- **Status:** passes `scripts/check_mql5_source.py` (0 findings); **not yet compiled**.
<!-- /edit:notes -->
