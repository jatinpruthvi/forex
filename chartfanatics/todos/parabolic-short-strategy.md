# 30. Parabolic Short Strategy

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `parabolic-short-strategy` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/parabolic-short-strategy.pdf) (9.5 MB) |
| **Origin** | [chartfanatics.com/strategies/parabolic-short-strategy](https://www.chartfanatics.com/strategies/parabolic-short-strategy) · [source PDF on Google Drive](https://drive.google.com/file/d/1DxbLt_pDx8ScLnPKgWysTW9vdhKNZ78A/view?usp=sharing) |
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
- **Verdict:** Implemented as a full EA - the playbook is explicit that it has **three core components and "if any of these are missing, the setup is not valid"**, so the EA gates on all three and then implements the graded entries and the risk mechanics. **Filter 1 - size**: a small-cap needs ~200% from its last base, a mid-cap ~100%, a large-cap ~50%, measured "from the most recent base, not the absolute bottom ... the last time price touched the 20-day moving average before the strong move began" (`ParabolicContext`, cap-tier input). **Filter 2 - structure**: the move must show acceleration ("candles become large, and the slope becomes steep", gaps between sessions) and must not be a controlled drift with deep pullbacks ("these pullbacks release pressure"). **Filter 3 - the exhaustion day**: price below VWAP and unable to reclaim it, lower highs then lower lows, and the top must be today or yesterday ("if nothing happens within two days, the setup should be ignored"). Entries are the playbook's own three grades, selectable: the structure break (earlier, more risk), the structure break with the VWAP loss at the same time (stronger), and the best - the failed reclaim of VWAP. Stop at "the high of the day or the most recent lower high"; partial profits then the stop to break-even; and **the risk-free add** - a second short when price returns to VWAP and fails again, allowed only when the banked partial profit actually covers the add's risk (the playbook's "earlier profits cover the loss" made arithmetic, read from the position's own deal history). Targets are sized off the expected move ("10 to 20 percent" / "20 to 40 percent"), the trade is closed before the bell, and a strong VWAP reclaim invalidates the setup. Volume records and round numbers only raise the score - the playbook marks them optional.
- **Instruments:** `AAPL,MSFT,NVDA` - the playbook trades **stocks** (default cap tier = large cap); the universe input is the user's own list
- **Timeframe / session:** M5 signals on D1 context; the US day-trading session 14:30-21:00 London (09:30-16:00 ET), flat before the bell - "the trade should be closed before the end of the day"
- **EA file / magic:** [`EA_CF_ParabolicShort.mq5`](../mql5-eas/EA_CF_ParabolicShort.mq5) / `3233` (static-checked)
- **Priority:** P1 - the exhaustion-short sibling of the First Red Day card
- **Blocked by:** _nothing_
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: the overview, what a parabolic exhaustion move is, the three core components (size of the
  move, structure of the move, the exhaustion day), the additional strengthening signs (volume records,
  psychological round numbers), the types of stocks and their expected drops, entry execution, managing
  risk, timing the trade, the risk-free add, the expected move, and the SMCI example (short at the VWAP
  rejection, stop at the high of the day, ~23-24% single-day drop).
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_ParabolicShort.mq5` (34 rules pinned).
- `[interpretation]`: every number the discretionary document does not state is an input and labelled -
  the 20-day-MA touch tolerance, the accelerating-leg / base windows, the acceleration multiple (1.5x),
  the pullback cap (1/3 of the leg span), the swing wing and minimum swing size, the "at the same time"
  window for the structure + VWAP entry, the rejection lookback and tolerances, the strong-reclaim buffer,
  the stop buffer and the stop-width sanity cap, the share of the expected move used for the target, the
  target R cap, the minimum RR, and the add's cover multiple.
- Design notes: the add is implemented through the engine's plan path (`maxOpenPositions = 2` and
  `AllowMultipleOnSymbol`) but is gated inside the strategy on a *protected* live leg (stop at or beyond
  break-even) and on banked partial profit covering the add's own risk; a fresh entry is impossible while
  any position is open, so the extra position slot can never average down. The exhaustion-day VWAP is the
  RTH session VWAP weighted by bar volume (tick volume where the broker publishes none), and "the high of
  the day" is the session's own high, both anchored to the 14:30 London open.
- Disclosed, not faked: single-stock selection by catalyst and the trader's discretionary read of
  "how the move feels" stay human; the cap-tier matrix is the playbook's own (small/mid/large), and a
  user running the EA on an index can override the required move percentage.
<!-- /edit:notes -->
