# 45. Unique High RR

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `unique-high-rr` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/unique-high-rr.pdf) (9.9 MB) |
| **Origin** | [chartfanatics.com/strategies/unique-high-rr](https://www.chartfanatics.com/strategies/unique-high-rr) · [source PDF on Google Drive](https://drive.google.com/file/d/1uSN2T9caD_6i2UWuVVQviiNBqO1a44kr/view?usp=sharing) |
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
- **Verdict:** Implemented as a trading EA - the document is built around one named entry formation, the **Trident Pattern**, so every stated condition is a gate in the document's own order.  **The clock first:** "Only trades between 3:00 AM and 6:30 AM New York time ... Entries must occur inside this window", and the three-candle FVG itself "must occur between 2:30 and 4:00 AM" ("ignore FVGs outside the kill zone").  New York wall time is not an engine clock, so the EA converts server -> UTC -> New York with the US DST rule and says so in the header - the windows are then exact all year.  **The pattern:** a three-candle fair value gap on the 30-minute chart, its 50% level (consequent encroachment) marked; "a small-bodied doji candle must form next" whose range contains that 50% ("the candle must wick into the FVG 50% zone"); and the confirmation candle's close relative to the doji's extreme - "the candle after the doji must close below the doji high.  If it closes above the doji high, the trade is invalid".  **The entry** is offered both ways the document allows: at market "on that confirmation candle", or as "a limit at the FVG 50% if you're early" - and the resting order's life is capped by the kill zone's end so an entry can never fill outside the window the document insists on.  **The frame:** the 5 / 9 / 13 / 21 EMAs "must be clearly stacked in the direction of the trade.  If they are crossing or tangled, the setup is invalid" (the optional minimum separation is a labelled `[interpretation]` with 0 = the plain ordering the document states), and the daily 200 EMA gives the side: "above 200 EMA -> only take longs.  Below 200 EMA -> only take shorts."  **The stop** is "below the low of the candle that forms FVG" with a wick cushion, and the document's gold exception is coded literally: "On Gold, a hard stop isn't used ... using a closing candle filter prevents getting stopped out prematurely" - on gold the hard stop moves out of wick range (a labelled disaster distance that still bounds the risk) and a completed close beyond the structural level is the exit.  **The target** comes from the daily chart ("the daily chart is used for overall bias and to target take-profit levels"): the nearest daily swing beyond a minimum distance, with the document's own +10R language as the far fallback.  **Management** implements the two stated rules and nothing else - "the EMAs begin to reverse direction, signaling a potential shift in trend" and "a significant bearish candlestick appears that invalidates the current structure" - and because the document warns "price may go +10R and pull back to +5R before running again", there are no partials, no break-even and no R trail.
- **Instruments:** `EURUSD,GBPUSD,USDJPY,NZDUSD,USDCAD,XAUUSD` default - the document's own "Valid Pairs" list; the model "is directional and can be applied to both longs and shorts", and the universe stays an input
- **Timeframe / session:** 30-minute entries, daily-frame bias and targets, entries only in the 03:00-06:30 New York kill zone (the FVG window 02:30-04:00 New York)
- **EA file / magic:** [`EA_CF_UniqueHighRr.mq5`](../mql5-eas/EA_CF_UniqueHighRr.mq5) / `3245` (static-checked)
- **Priority:** P1 - the queue's London-kill-zone pattern card
- **Blocked by:** _nothing_
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: the playbook overview (the London-session window and the momentum/volatility logic), the
  playbook criteria page (kill zone 03:00-06:30 New York, the 30-minute entry chart, the daily chart for
  bias and targets, the 5/9/13(or 15)/21 EMAs and their "clearly stacked" rule, the 200 EMA bias, the Bull
  Trading Candle Strength indicator), the Trident Pattern page (the 3-candle FVG and its 02:30-04:00
  window, the 50% consequent encroachment, the doji and its wick, the confirmation candle rule, both
  entry forms, the stop below the FVG candle's low and the gold exception), the take-profit/management
  page (ride the trend, the EMA reversal and significant-candle exits, the valid pairs), the pros/cons
  page (the patience requirement, the window, the +10R-to-+5R fluctuation, the psychology), and the
  worked USDJPY breakdown.
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_UniqueHighRr.mq5` (50 rules).
- Disclosed, not faked: the "Bull Trading Candle Strength" indicator is a proprietary four-state candle
  classifier (green/blue = strong/mild bullish, red/black = strong/mild bearish).  MetaTrader has no such
  feed, the EA never pretends to read it, and the document only says it "helps confirm momentum on the
  daily chart" - it is not a stated gate.  The two momentum reads the document DOES state as rules (the
  EMA stack and the 200 EMA bias) are implemented.
- `[interpretation]` inputs, all labelled in the source: the doji body threshold, the stop buffer and the
  stop-width cap, the gold disaster distance, the daily swing width / lookback / minimum target distance,
  the far fallback target, the "significant" candle body in ATR, the structure swing the invalidation rule
  breaks, the "clean" gap that only raises the score, the resting 50% order's life, the daily attempt cap
  and the open-position cap.
<!-- /edit:notes -->
