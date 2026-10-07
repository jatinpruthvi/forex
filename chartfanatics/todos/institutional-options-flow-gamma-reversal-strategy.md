# 14. Institutional Options Flow & Gamma Reversal Strategy

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `institutional-options-flow-gamma-reversal-strategy` |
| **Type** | video-only (Glimpse summary) |
| **Source** | [Glimpse summary](../glimpse/35cyqDz-ej8.md) · [summary PDF](../glimpse-pdf/35cyqDz-ej8.pdf) · [YouTube](https://www.youtube.com/watch?v=35cyqDz-ej8) (@chart-fanatics) |
| **Origin** | [chartfanatics.com/strategies/institutional-options-flow-gamma-reversal-strategy](https://www.chartfanatics.com/strategies/institutional-options-flow-gamma-reversal-strategy) · [Glimpse](https://glimpse.wozart.com/v/8agbp538) |
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
- **Verdict:** Partially robotic, implemented with the honest split. The edge is options positioning: dealer gamma at big strikes makes those levels price magnets. That data (90-day OI, the volatility surface) lives on an options platform - the video names Guestbot - and no MetaTrader EA can read it, so the levels are inputs the trader fills in (the video's own action item). Everything the document states mechanically is implemented: reversal entries at a wall (tap + reclaim + rejection wick, confirmed by above-average volume as the order-flow proxy), the 30-50 tick stop and next-gamma-level target, the dollar-risk sizing ("$150-200"), the 1-2 setups/day cap, the first-two-hours window with a flat at its end, the OPEX / triple-witching / spiration calendar gates, and the "2 days off after a stop loss" rule enforced from the EA's own deal history.
- **Instruments:** NQ / ES / SPX (source). EA: `InpSymbolsToTrade`
- **Timeframe / session:** M1 reversals inside the first two hours (9:30-11:30 ET = 14:30-16:30 London)
- **EA file / magic:** [`EA_CF_GammaReversal.mq5`](../mql5-eas/EA_CF_GammaReversal.mq5) / `3218` (static-checked)
- **Priority:** P2 - the level data needs a human, the discipline does not
- **Blocked by:** _nothing_ (levels must be set from the platform before use; never compiled - MetaEditor run owed)
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Video sections used: why options flow matters now (zero-DTE, dealer hedging); how market makers move the
  market (delta hedging, gamma acceleration); the volatility surface; gamma walls and call walls; how to
  trade gamma levels (maximum gamma levels, trade reversals with tight stops); frequency and sizing
  (1-2 setups/day, 30-50 ticks risk / 300-400 ticks target, 2-3 contracts with partials, 75% win rate);
  convexity levels as secondary confirmation ("trade positive convexity to positive convexity"); the
  first two hours matter most (9:30-11:30 ET, charm after lunch); avoid OPEX / triple witching; the
  discipline rules (stop losses are emotional triggers, 1:8 R:R, take 2 days off after a stop loss).
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_GammaReversal.mq5` (22 rules pinned).
- `[interpretation]`: wall/target levels are inputs (platform data); "spiration" read verbatim as 30
  days before a monthly OPEX; approach/reclaim/volume tolerances are inputs because the video gives
  none; flat at the window end reflects "avoid trading late in the day".
<!-- /edit:notes -->
