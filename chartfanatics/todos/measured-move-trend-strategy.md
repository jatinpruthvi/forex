# 23. Measured Move Trend Strategy

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `measured-move-trend-strategy` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/measured-move-trend-strategy.pdf) (9.5 MB) |
| **Origin** | [chartfanatics.com/strategies/measured-move-trend-strategy](https://www.chartfanatics.com/strategies/measured-move-trend-strategy) · [source PDF on Google Drive](https://drive.google.com/file/d/1EAymw6X15xRcltAly6fyPfrx8SyJBHnw/view?usp=sharing) |
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
- **Verdict:** Implemented as a strategy. The "Little RZY" structure is mechanical once the trendline is defined, and the EA follows the document's own order: **trend first** (fractal swings must show lower highs and lower lows - or the mirror), then the **initial move and pullback** (the structure needs a proper span, not a vertical collapse), then the **trendline** across the two newest pullback anchors, then the **measurement** (the line's height above the structure's extreme, projected from that extreme exactly as the document says). The entry waits for the pullback to **reach the trendline and reject it back with the trend** - never during the impulse. The stop sits **beyond the trendline / recent swing extreme** with a buffer ("avoid placing stops too tight"), and because the document asks for a **confirmed close beyond the trendline** to invalidate, that close is an exit in `Manage()` rather than a hope. Targets are the **measured move** with the full move allowed to play out (no arbitrary partials). The document's context rules are enforced: **Bollinger** stretch ranks structures (downtrend structures near the upper band, uptrend structures near the lower band) and can be a hard gate; **structure count** (the fourth or fifth is exhausted) and **shrinking structures** (the trend may be ending) both block entries; and the **higher-timeframe direction** is checked before the structure counts (the doc's "identify direction on higher timeframes, execute on lower").
- **Instruments:** stocks / futures / crypto (the document's list) - `InpSymbolsToTrade` (default `US100,US500`)
- **Timeframe / session:** H4 structure (the doc's higher-timeframe preference); swing trading, so no session gate
- **EA file / magic:** [`EA_CF_MeasuredMove.mq5`](../mql5-eas/EA_CF_MeasuredMove.mq5) / `3226` (static-checked)
- **Priority:** P1 - the family's cleanest measured-move projection, and the only one that projects from structure
- **Blocked by:** _nothing_
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: overview (repeating measured patterns; retracement distance reused for the continuation;
  Bollinger context; most effective on higher timeframes); the Little RZY definition (impulse, bounce,
  trendline across the pullback highs, the lowest low, the measured distance projected from it, each structure
  its own trendline); the ten strategy rules (trend first; wait for the move and pullback; draw the trendline;
  measure the move; entry on the rejection/continuation; stop above the line or the swing high with the
  confirmed-close invalidation; the measured-move target and letting it play out; Bollinger context - early
  structures near the opposite band are stronger; first/second structures strongest, fourth/fifth exhausted,
  shrinking structures a warning; invalid conditions); timeframe considerations; bottoms ("anticipate reversals
  rather than react"); key takeaways; the trade breakdown (steps 1-7).
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_MeasuredMove.mq5` (26 rules pinned).
- `[interpretation]`: the fractal swing strength, the structure span limits, the trigger freshness, the
  trendline-touch tolerance, the stop buffer, the 1.5R floor, the structure-count limit, the shrinking ratio
  and the 2-sigma Bollinger setting (the doc says "the standard setting" implicitly via "middle/outer bands").
  The mechanical trendline (the line through the two newest anchors) replaces the by-eye line.
- Self-review fixes: the long-side trend sign, the pullback anchors for longs, a placeholder block and a dead
  helper were removed before handing the card to the judge.
- Engine reuse: the engine context (ATR), `g_eaExec.Close` for the invalidation exit, `cfg.maxCostR`, the
  evidence ledger, `EA_ApplyStagePolicy`. Bollinger is computed locally because the engine carries EMAs only.
<!-- /edit:notes -->
