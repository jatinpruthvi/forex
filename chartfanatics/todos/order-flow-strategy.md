# 28. Order Flow Strategy

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `order-flow-strategy` |
| **Type** | video-only (Glimpse summary) |
| **Source** | [Glimpse summary](../glimpse/hvyf6frvCcA.md) · [summary PDF](../glimpse-pdf/hvyf6frvCcA.pdf) · [YouTube](https://www.youtube.com/watch?v=hvyf6frvCcA) (@chart-fanatics) |
| **Origin** | [chartfanatics.com/strategies/order-flow-strategy](https://www.chartfanatics.com/strategies/order-flow-strategy) · [Glimpse](https://glimpse.wozart.com/v/2lit20z2) |
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
- **Verdict:** Implemented as a full EA. The system is the four criteria built into two models. **Criteria**: (1) market-generated levels - the previous day high/low, the overnight range (21:00-09:29 ET = 02:00-14:29 London, via the engine's `SigRangeForDay`) and the 30-minute opening range; (2) the volume profile - a 70% value area and low volume nodes found as thin bins of a tick-volume profile; (3) big trades - bars far above the window median that touch the level (the document's 75-lot / 200-lot feed is not readable, so this is a labelled proxy); (4) delta - body-directional volume with absorption read as a heavy bar that tests the level and closes back on the defended side (also labelled). **Model one (range)**: trade the value-area edges when the range holds no node inside - tight stop, small size, 1R partial into the midpoint, the opposite edge as the final target, stop to break-even after the first target ("never let a winner go red"). **Model two (trend)**: the **trap fade** sells a wick through a generated level that closes back inside (where the breakout traders are stuck), and an **accepted value break** trades pullbacks into low volume nodes toward the next generated level or a measured extension. At least **two of four** criteria are required, three or more makes the **A+** size (`LotsMultiplier`), and the document's own gates are encoded: first 1-3 hours post-open only, max 3 trades a day, never the middle of a range, never against an un-pulled-back momentum burst, and a three-bar lower-highs exit on the trend model. The document's "averaging up" add-on cannot exist while the engine holds one position per symbol (the confirmation banks the partial instead) - disclosed.
- **Instruments:** `US100,US500` (the NQ / ES analogues)
- **Timeframe / session:** M2 (NQ's 2-minute frame; ES runs 3-minute charts - one signal timeframe per EA, disclosed); entries only 14:30-17:30 London = 09:30-12:30 ET
- **EA file / magic:** [`EA_CF_OrderFlowStrategy.mq5`](../mql5-eas/EA_CF_OrderFlowStrategy.mq5) / `3231` (static-checked)
- **Priority:** P1 - the core order-flow card of the queue
- **Blocked by:** _nothing_
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: the four criteria (market-generated levels, volume profile / value areas and low volume
  nodes, the big trades indicator, the delta profile and absorption / trapped orders), both models
  (range-bound edge trading, trending pullbacks and selling into breakout highs), the minimum-criteria
  rule (two of four, 3-4 = A+), risk management (aggressive entry = smaller size, never let a winner go
  red, the 3-4R / 2R / 1.5-2R ladders), the discipline rules (first 1-3 hours, 2-3 trades a day, never
  against momentum, accept the daily risk up front, execution speed), the platform notes (tick data, the
  2-minute NQ and 3-minute ES frames, the DOM) and the common mistakes (averaging down vs up, trading the
  middle, chasing breakouts, overcomplicating, ICT without order flow).
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_OrderFlowStrategy.mq5` (24 rules pinned).
- `[interpretation]`: the big-trade multiple (2.5x the median), the 12-bar search, the thin-bin cut (35%
  of the mean), the delta-lean cut (0.20), the absorption volume multiple (1.8x) and defended-half split
  (50%), the level tolerance (0.20 ATR), the edge band (25% of the value area), the value-area bar window
  (420 M2 bars with a developing-day preference), the chase / pullback tolerances, the stop buffers, the
  B/C size share (0.50) and the three-bar structure exit are engineering numbers the document does not
  state - all exposed as inputs and labelled in the source.
- Disclosed, not faked: the real order feed (75 lots NQ / 200 ES), the delta profile and the DOM speed
  read have no MT5 signal; the proxies are labelled and the psychology / platform-setup sections are human
  decisions. The add-on after confirmation ("averaging up") is an engine limit (one position per symbol).
- Design note: the value area is expanded out of the POC until 70% of the profile's tick volume is covered
  (the standard algorithm, and the document's own 70%); low volume nodes are contiguous runs of thin bins
  between the broken value edge and the price, which is where the trend model's pullback entry lives; the
  trap fade needs the wick to close back inside the level, so an accepted break is never faded.
<!-- /edit:notes -->
