# 44. Trendline Strategy

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `trendline-strategy` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/trendline-strategy.pdf) (8.7 MB) |
| **Origin** | [chartfanatics.com/strategies/trendline-strategy](https://www.chartfanatics.com/strategies/trendline-strategy) · [source PDF on Google Drive](https://drive.google.com/file/d/1vy9pacuUc8YUqvtzzcVBIh1CA08xF6xM/view?usp=sharing) |
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
- **Verdict:** Implemented as a trading EA - the document is a two-setup trendline playbook built on one idea: every trade has an **Action Line** (where you enter) and a **Safety Line** (where you are wrong), and for a bounce they are the same line. An EA cannot read hand-drawn objects, so the lines are **drawn by rule** and disclosed as such: through the two most recent same-side swings (higher lows for support, lower highs for resistance), extended forward, with every older pivot inside tolerance counting towards the document's "at least two or three clear touchpoints before entry", plus the hard gate "at least one week of price data from the first touchpoint". **The bounce** (S3) enters when the last completed bar tests the line ("enter when the price reaches or tests the trendline") and closes back on-side, and the line itself is the stop - "instead of exiting at the line automatically, use a close below it" - buffered by the stated reason "stops should not be placed exactly at the entry ... give it enough room so normal price wicks don't stop you out too early". **The break** (S4) trades a completed close through the opposing action line within a freshness window (the repeatable form of "wait until price forms a clear high or low to draw one"), protected by the newest line on the trade's side as the Safety Line, and skipped when that line sits further away than the document's "the break must happen close to the safety line ... if it's too far, skip the trade" allows. The 2-touchpoint and 3-touchpoint breaks are **tracked separately** as the document demands (3T scores higher and is named in the ledger reason), and the 3T reading is the document's own "more touchpoints show the line is well respected and make the break more reliable". **Exits are the document's, not the engine's:** a completed close back through the safety line closes the trade at once ("the trade is invalid and must be closed") and the stop **trails along the line** as new swings extend it ("the stop can be trailed along the trendline as the price creates new valid swing points") - so the engine's R-based trailing and break-even are switched off on purpose. The 4-hour frame ("this strategy works best on the 4-hour timeframe"), the metals/commodities universe and the optional daily top-down confirmation are inputs.
- **Instruments:** `XAUUSD,XAGUSD` default - "certain commodities or metals with strong trending behavior are suitable"; the playbook also names futures and crypto, so the list is an input
- **Timeframe / session:** H4 signal bars on the server clock (futures/crypto/FX run around the clock; the session gate stays open), one decision per completed 4-hour bar
- **EA file / magic:** [`EA_CF_TrendlineStrategy.mq5`](../mql5-eas/EA_CF_TrendlineStrategy.mq5) / `3244` (static-checked)
- **Priority:** P1 - the queue's second trendline-structure card, and the one that names the action/safety-line pairing explicitly
- **Blocked by:** _nothing_
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: the introduction (the Action Line / Safety Line concept and the 4-hour frame), the
  top-down daily/weekly confirmation, the two setups (trendline bounce and trendline break with 2T/3T
  touchpoint counts), the rules for drawing trendlines and the "one week of price data" requirement,
  entries (touch-and-respect for bounces, close-through for breaks), the safety-line definition ("for
  bounce setups, the action line and safety line are the same"; a new opposing trendline for breaks),
  the "break must happen close to the safety line" risk rule, the stop rules (the line itself, plus
  buffer room), the invalidation rule ("if the price moves back and closes beyond the safety line, the
  trade is invalid and must be closed"), the trailing rule, the timeframe rule, the instrument notes,
  the pros/cons, and all three worked examples.
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_TrendlineStrategy.mq5` (45 rules).
- Disclosed, not faked: hand-drawn trendlines do not exist for an EA, so the line geometry is derived
  by rule and the document's "frequent false breaks" warning is answered by the gate the document
  itself gives - touchpoints plus a close-through (a wick alone is not a break).  The document states no
  target for either setup, so the far 8R TP is a labelled `[interpretation]` placeholder that exists
  only to satisfy the engine's order model; the safety line remains the exit.
- `[interpretation]` inputs, all labelled in the source: the pivot width, the line tolerance, the
  touch-test tolerance, the break-close buffer, the freshness window after the break, the stop buffer,
  the stop-width cap, the maximum safety-line risk percentage, the daily reference period and the far
  TP placeholder.
<!-- /edit:notes -->
