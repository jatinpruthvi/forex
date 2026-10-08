# 32. Price Action Strategy

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `price-action-strategy` |
| **Type** | video-only (Glimpse summary) |
| **Source** | [Glimpse summary](../glimpse/70UtrLU6RAg.md) · [summary PDF](../glimpse-pdf/70UtrLU6RAg.pdf) · [YouTube](https://www.youtube.com/watch?v=70UtrLU6RAg) (@GalaTrades) |
| **Origin** | [chartfanatics.com/strategies/price-action-strategy](https://www.chartfanatics.com/strategies/price-action-strategy) · [Glimpse](https://glimpse.wozart.com/v/tcku5v5a) |
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
- **Verdict:** Implemented as a full EA - the video-derived playbook is a routine, but its mechanical spine is stated plainly and the EA implements exactly that. **Trend** (R1): "tracking successive highs and lows" on H1 - higher highs with higher lows is an uptrend, lower highs with lower lows is a downtrend, and a mixed structure means no trade (direction decides calls or puts, so the EA is long-only in uptrends and short-only in downtrends). **Levels** (R2): H1 pivoting points taken at their **candle open prices, not the wicks**, as the document explicitly requires. **Confidence** (R3): 5/5 for a level pivoted at three or more times, 3/5 for a single-pivot opening price, 2.5/5 once price has closed decisively through it - and the score sizes the trade (R4: full / half / quarter risk through the engine's `LotsMultiplier`). **Entries** (R5-R9): the three candle patterns on M5, trend-aligned - **break and retest** (a 5-minute close through the level, then the retest with a small wick and the body back on the break side), **bounce** (2-3 candles whose bodies hold above a support while wicks probe below) and **rejection** (bodies below a resistance while wicks push up), each with the document's own stop (just under the retest wick / the lowest wick / the highest wick) and, for the rejection, the target at the next lower level. **Risk** (R10-R18): two attempts per setup counted from the day's own deals at that level, 50% trimmed at 2R with the stop shifted above entry, a second trim at 3R, then the stop trailed candle by candle; a 2R target (1.5R floor) instead of home runs; 2-3 trades per day; one-and-done after a winner (the engine's `dayLockFirstWin`); and entries only in the first hour after the open with the first five minutes skipped.
- **Instruments:** `US100,US500` - the document trades options on TSLA/SPY/QQQ and futures ES/NQ; the symbol list is the user's universe, as in the other cards
- **Timeframe / session:** M5 entries on H1 levels; US day-trading session, entries only from 14:35 to 15:35 London (09:35-10:35 ET, "executes for only 1 hour daily"), flat before the cash close - no overnight holds
- **EA file / magic:** [`EA_CF_PriceAction.mq5`](../mql5-eas/EA_CF_PriceAction.mq5) / `3234` (static-checked)
- **Priority:** P1 - the video-only half of the queue
- **Blocked by:** _nothing_
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: core framework (trend via highs and lows, hourly levels at open prices with confidence
  scores, 2-5 minute execution), the three candle patterns (break and retest, bounce, rejection), position
  management (risk acceptance, the two-entry maximum, scaling out and stop shifting, the 2R target),
  pre-market preparation (the 10-name watchlist, confidence sizing, the 2-4 trade limit), the live Tesla
  example, the trade-review mistakes, the journaling template and star ratings, and the psychology and
  discipline sections (hide the P&L, FOMO, one-and-done, the one-hour day, the mistakes to avoid).
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_PriceAction.mq5` (36 rules pinned).
- `[interpretation]`: the document is discretionary, so every number it does not state is an input and
  labelled - the pivot wing, the level cluster tolerance, the strong-touch count, the invalidation
  distance, the level cap, the mid/low confidence sizes, how many candles the bounce and rejection count,
  the probe and entry distances, the retest tolerance and lookback, the stop buffer, the break-even
  offset above entry, the second trim, the trail buffer, the volume skew cut, and the exact one-hour
  window boundaries.
- Design notes: positions are sized by the *level's* confidence through `LotsMultiplier(ctx)`, keyed by
  the symbol's context index (the engine sizes the plan with the winning symbol's context, so the score
  always belongs to the level that was actually traded); the two-entry rule is counted from the day's
  deal history at that level's price, so it survives a restart; a winning exit locks the day
  (`dayLockFirstWin`), which is how "never re-enter the same setup on the same day" is enforced for
  winners, while a stop-out earns the single retry the two-entry rule allows. `SigFractals` is bound to
  the signal timeframe and returns wick prices, so the H1 open-price scan is local to this EA - noted in
  the header.
- Disclosed, not faked: the pre-market 10-name plan, the economic-calendar check, hiding the P&L
  display and the journaling (star ratings and the rules checklist) are human steps and stay human; the
  engine ledger records the setup type and R outcome the journal needs. "Optional orderflow (bookmap)"
  has no MT5 signal, so the confirmation is a labelled body-volume skew and is off by default, matching
  the document's "optional".
<!-- /edit:notes -->
