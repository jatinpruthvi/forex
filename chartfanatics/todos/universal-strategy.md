# 46. Universal Strategy

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `universal-strategy` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/universal-strategy.pdf) (3.3 MB) |
| **Origin** | [chartfanatics.com/strategies/universal-strategy](https://www.chartfanatics.com/strategies/universal-strategy) · [source PDF on Google Drive](https://drive.google.com/file/d/1eqoOhINITFnc3PwHWGGQ5l6QvRajSRlE/view?usp=sharing) |
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
- **Verdict:** Implemented as a trading EA - the document is a narrative framework, but every part of the narrative is a mechanical test, and the EA requires all of them.  **S1 the liquidity catalyst** is one of the document's own events detected on price: "a sweep of equal highs/lows" (two equal levels, then a wick through them that closes back on-side - the same shape as "a sharp rejection from a significant level"), "a break of a major support/resistance zone" (a level respected at least twice, then closed through decisively), and "a break of a well-respected trendline" (the line through the two most recent same-side swings, the worked S&P 500 example's own catalyst: a falling resistance broken upward for longs, a rising support broken downward for shorts).  **S2 displacement** must then be real: "a decisive move away from that area" measured in ATR, "a noticeable shift in price behavior" as a displacement candle body, and "a break in the prior swing structure" - because "without meaningful displacement, there is no evidence that the market intends to move".  **S3 the retracement** is the entry and the EA enforces the document's hardest rule - "Entries Are Taken Only on the Retracement ... you do not enter during the first impulsive move" - by running the engine's limit-only mode: every story is a resting order at the proximal edge of a confluence zone, and if the zone is never reached "the market did not fulfill your criteria" and the order simply expires.  The zone is built from the document's own confluence list - the level, "a fair value gap", "an order block", "a moving average used as dynamic support/resistance" (the worked example's 21 EMA), "a previous swing level", "higher-timeframe alignment" and, at sweeps, "divergence" (the RSI refusing to confirm the new extreme) - and because "no trade is taken based on a single signal", at least `InpMinConfluence` factors must line up; the count feeds the score.  A story already worked once is never re-armed - "missing a trade is not a mistake".  **Invalidation** is structural, as demanded: the stop sits beyond the zone and the catalyst's own extremity with "no arbitrary breathing room", a stop that would be wider than the cap is refused ("no wide stops out of fear"), and when a completed close returns through the level the trade closes at once - "if that level breaks, the trade is invalid, and you exit without hesitation".  **Targets** are the next liquidity pool ("markets move from one liquidity zone to the next"), and management is deliberately empty: no partials, no break-even, no trail, because the document's rule is "manage the trade according to the story, not emotion" and it explicitly warns about "the desire to protect profits prematurely".
- **Instruments:** `US500,US100` default - the document's worked example is the S&P 500 and the playbook "applies to any market (stocks, futures, crypto, forex)", so the universe is an input
- **Timeframe / session:** H4 default - the document is timeframe-agnostic ("any timeframe, and any trading style"), so the signal frame is an input; no session window is stated, so the clock stays open
- **EA file / magic:** [`EA_CF_UniversalStrategy.mq5`](../mql5-eas/EA_CF_UniversalStrategy.mq5) / `3246` (static-checked)
- **Priority:** P1 - the queue's story-framework card
- **Blocked by:** _nothing_
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: the playbook overview (the three core components and the "no catalyst, no trade" rule), the
  catalyst page (sweeps, level breaks, trendline breaks, structure shifts, sharp rejections), the
  displacement page ("a strong reaction must follow the catalyst"), the rules pages (no catalyst = no
  trade; entries only on the retracement; invalidation clear and objective; missing a trade is not a
  mistake; technical and/or fundamental confluence; manage the trade according to the story), the
  swing/day-trading pros and cons pages (human context, disclosed), and the S&P 500 trendline
  break-and-retest breakdown (context, catalyst, reaction, entry at the retest where the 21 EMA
  aligned, invalidation on a reclaim, targets at prior internal lows).
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_UniversalStrategy.mq5` (41 rules).
- Disclosed, not faked: the confluence list ends with "macro conditions, seasonality, or significant
  news" - a backtest has no working economic calendar and no seasonality feed, so the EA counts the
  technical confluences the document lists and says so; the fundamental context the document's
  pros/cons pages describe is, by its own words, a human judgement.
- `[interpretation]` inputs, all labelled in the source: the signal timeframe, the equal-level and
  zone-cluster tolerances, the level touch and break tolerances, the trendline swing width and
  tolerance, the displacement distance and candle thresholds, the confluence minimum, the zone's life,
  the stop buffer and its width cap, the invalidation close count, the target swing width, the minimum
  target distance, the far fallback target, the higher-timeframe MA period, the catalyst lookback and
  freshness window, and the attempt / open-position caps.
<!-- /edit:notes -->
