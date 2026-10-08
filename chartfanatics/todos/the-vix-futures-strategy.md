# 41. The Vix Futures Strategy

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `the-vix-futures-strategy` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/the-vix-futures-strategy.pdf) (3.6 MB) |
| **Origin** | [chartfanatics.com/strategies/the-vix-futures-strategy](https://www.chartfanatics.com/strategies/the-vix-futures-strategy) · [source PDF on Google Drive](https://drive.google.com/file/d/1oNnrljkDrdx7YzTbz6hQHM4Kq527ApDb/view?usp=sharing) |
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
- **Verdict:** Implemented as a trading EA - the playbook is a confirmation layer with mechanical rules, not a discretionary read. Everything is on one frame ("needs matching timeframes across ES, NQ, and VIX"), read against the previous day's levels. **The core rule**: "When ES breaks below the previous day's low (PDL), the VIX should normally be rising and sitting at or above its previous day's high ... the move down has higher odds of continuing", plus the document's own strength filter "if both ES and NQ break their lows and the VIX is strong, the downside usually has real power" and the head start ("sometimes the VIX reaches its previous day's high before ES or NQ breaks their previous day's lows"). **The trap rule**: "If ES breaks below the PDL, but the VIX is not doing its part ... the breakdown has a good chance of failing. ES often snaps back above the level, trapping shorts ... one of the simplest ways to avoid shorting a fake breakdown" - the EA takes the snap-back long instead, with the document's relative-strength note ("NQ holds above its own low or makes a higher low") scored in. Both **mirrors** are coded because the document frames the framework as previous-day highs *or* lows. **The cautions are gates, not footnotes**: the **1% rule** ("if ES is up 1% or more and the VIX is also up 1% or more ... moves into resistance are more likely to fail"; and the down mirror) vetoes chasing, and the **natural-floor** warning ("at all-time highs ... a rising VIX doesn't always mean ES is about to break down. Context from ES levels is needed") refuses the confirmed breakdown short while the index is at its own highs. **The worked example** - "VIX forms a double bottom at contract lows" (16.8) while "ES was struggling to break through its all-time high area" - is the highest-scoring setup, and **mode B** reproduces the document's actual trade ("long VIX futures ... delivered a 6:1 R outcome") when the broker offers a VIX instrument. "Must avoid taking the same trade on multiple instruments" is enforced: one index leg at a time, never ES and NQ on the same signal.
- **Instruments:** `US500` default (the document's ES) with `US100` as the confirming NQ leg; VIX read from `InpVixSymbol` (`VIX` by default) - mode B trades the VIX instrument itself
- **Timeframe / session:** M15 on all three reads, previous-day levels from D1; entries inside the US cash session (14:30-21:00 London), flat at the bell because the previous-day edge is an intraday thesis; mode B keeps its position (the document's VIX trade was a swing)
- **EA file / magic:** [`EA_CF_VixFuturesStrategy.mq5`](../mql5-eas/EA_CF_VixFuturesStrategy.mq5) / `3241` (static-checked)
- **Priority:** P1 - the queue's volatility-regime card
- **Blocked by:** _nothing_ (mode B needs a broker VIX instrument, logged when absent)
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: the playbook overview (what the VIX tells you about the S&P, ES/NQ symmetry, the
  confirmation layer, the trap avoidance), the foundation (what the VIX measures - put demand, the 90%
  algorithmic share and the sell/buy programs, the hiker-with-a-backpack analogy, "weak VIX -> easier for
  ES to go up / strong VIX -> harder"), previous-day levels with the VIX (both confirmation directions,
  ES+NQ both breaking, the noisy single-instrument break), the VIX head start, VIX support/resistance
  pairing, the 1% rule, the natural floor at major highs, the pros and cons (matching timeframes, false
  signals at all-time highs, "must avoid taking the same trade on multiple instruments"), and the full
  trade breakdown (the 16.8 contract-low double bottom, ES failing at all-time highs, the Friday-selling
  pattern, the 6:1 R outcome).
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_VixFuturesStrategy.mq5` (43 rules pinned).
- `[interpretation]`: the break / reclaim buffers, the stop buffer and the stop-width cap (which doubles
  as the anti-chase guard), the VIX confirmation tolerance, the floor proximity, the double-bottom window
  and tolerance, the "all-time" lookback and distance, the failed-breakout window, the Friday-weakness
  window and count, the 1% threshold source (`InpOnePct`) and the R targets are inputs and labelled.
  The document's 1% rule is quoted as a threshold and is kept as an input.
- Design notes: the three reads (traded index, confirming index, VIX) are loaded by the same two
  functions, so a change to the previous-day frame can never drift between the instruments; the VIX
  high/low comparisons are made on today's session bars as well as the live price because the document
  asks about the *path* ("making a lower high instead of a higher high"). The level book of card #37 is
  not reused here on purpose: this playbook is about previous-day extremes and VIX agreement, not about
  pivots.
- Disclosed, not faked: "contract low" is a futures notion (each contract has its own life); the EA
  proxies it with the VIX's own multi-month extreme low and says so. The VIX symbol is an input because
  brokers differ, and when it is missing the EA produces no signals and logs why (fail-safe, never
  fail-silent). The Friday-selling context is a score bonus, not a gate, because the document calls it
  "helpful context". Mode B's 1% exemption is deliberate and disclosed: the VIX long is the other side of
  the very divergence the rule describes.
<!-- /edit:notes -->
