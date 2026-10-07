# 38. Stage Analysis Strategy

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `stage-analysis-strategy` |
| **Type** | video-only (Glimpse summary) |
| **Source** | [Glimpse summary](../glimpse/VDK200OHNSo.md) · [summary PDF](../glimpse-pdf/VDK200OHNSo.pdf) · [YouTube](https://www.youtube.com/watch?v=VDK200OHNSo) (@chart-fanatics) |
| **Origin** | [chartfanatics.com/strategies/stage-analysis-strategy](https://www.chartfanatics.com/strategies/stage-analysis-strategy) · [Glimpse](https://glimpse.wozart.com/v/upkpddh6) |
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
- **Verdict:** Implemented as a trading EA - the framework is fully mechanical once the stack is written down ("this visual alignment is the fastest way to gauge market structure"), and the document states its entry, exit and stop rules outright. The **10/20/30/40 simple-moving-average stack** is the stage reader: bullishly stacked with price "surfing above all moving averages" = **Stage 2 (buy/hold)**; bearishly stacked with price "trading below the 10, 30, and 40" = **Stage 4 (avoid / short)**; a **converged** stack splits into **Stage 1 basing** (price near the range lows, after a decline) or **Stage 3 topping** (near the highs) - and both take **no risk**, which is Livermore's "forget the first and last eighth" turned into a gate. Entries are the document's own words: "Wait for price to close above all four moving averages (10, 20, 30, 40) with the 10 above the 20 and 30. Volume should confirm. On the daily chart, look for a pullback to the 10/20 MA for a lower-risk entry" - both the transition close and the preferred pullback are coded, plus **the first multi-month base** after a big Stage 2 move ("this is Ted's favorite setup") breaking out for the next leg. The **Stage 3 exit** is "when price fails to make new highs, MAs flatten and converge ... it is time to scale out" - the EA scales out on exactly that read and closes the rest on the completed close that loses the 30-period MA ("do not wait for Stage 4 crash"). The other half of the middle 68% is the **Stage 4 failed-rally short** into the 10 MA. The advanced **Stage 4 mean reversion** back to the 30/40 MAs ships **off by default**, exactly as the document frames it ("this is a mean reversion trade, not a Stage 2 entry").
- **Instruments:** `AAPL,MSFT,NVDA` default - the framework is "universal ... stocks, crypto, commodities, bonds, and currencies", and the stack timeframe is an input so each market can be read on its own bars; the document's own sector-ETF market-health screen stays a human review (disclosed)
- **Timeframe / session:** D1 stack by default (the document's 10/20/30/40-week stack scaled to the "swing traders use daily" instruction; weekly and hourly are one input away - "works on weekly, daily, hourly, and even 5-minute charts"), M5 execution inside the US session; Stage 2 is "buy/HOLD", so positions ride the stage rather than the bell and there is no end-of-session flattening
- **EA file / magic:** [`EA_CF_StageAnalysisStrategy.mq5`](../mql5-eas/EA_CF_StageAnalysisStrategy.mq5) / `3239` (static-checked)
- **Priority:** P1 - the queue's cycle-framework card
- **Blocked by:** _nothing_
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: the four stages (downtrend, basing, uptrend, topping), how to identify each stage (the
  moving-average stack, rate of change / slope, price structure), universal application across asset
  classes (ARKK, Bitcoin, gold, silver, Treasury futures, DXY, cocoa/coffee/OJ), the real-world nuances
  (failed breakouts and fake transitions - Moderna, the Stage 4 mean reversion trade, catalyst-driven
  transitions), the first multi-month base setup (REE), the fractal nature across timeframes, why the
  framework works (timeless cycles, forget the first and last eighth, drawdown protection, probability
  instead of prediction), practical implementation (screening and monitoring, Stage 2 entry signals,
  Stage 3 exit signals, layering conviction) and the key stocks analysed (NVDA, TSLA, ANF, MRNA, RGTI,
  REE, uranium).
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_StageAnalysisStrategy.mq5` (41 rules pinned).
- `[interpretation]`: the "45-degree" steepness, the "flatten and converge" percentage, the
  volume-confirmation multiple, the pullback tolerance, the base window and tightness, the "big Stage 2
  move" threshold, the fail-high window, the extreme-distance percentage for the mean reversion, the far
  TP placeholder and every stop buffer are inputs and labelled - the document draws them by eye.
- Design notes: the stage read is one function (`ReadStage`) shared by the entry logic and by `Manage`,
  so the entry and the Stage 3 exit can never disagree about which stage the market is in. The
  converged-stack split (Stage 1 vs Stage 3) uses the position of price inside its lookback range,
  because "this mirrors Stage 1 but at the top" is a location statement; the two are also the two
  no-risk states, so a mislabel cannot create a trade. Entries in a converged zone happen only through
  the transition closes (above the whole stack / above the base), never inside the chop.
- Disclosed, not faked: the narrative/catalyst layer ("price + story + catalyst"), the sector-ETF
  market-health screen ("if most stocks are in Stage 3/4, be cautious") and the visual chart reps stay
  with the human; the EA trades the stage mechanics alone, which is what the document says the mechanics
  are for ("this is not prediction; it is probabilistic thinking"). The failed Stage 2 breakout handling
  is the engine's stop plus a retry budget rather than a bespoke "try again" loop, mirroring Moderna's
  three attempts.
<!-- /edit:notes -->
