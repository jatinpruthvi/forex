# 36. Small-Cap Short Statistics

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `small-cap-short-statistics` |
| **Type** | video-only (Glimpse summary) |
| **Source** | [Glimpse summary](../glimpse/52ZsDmFHqyY.md) · [summary PDF](../glimpse-pdf/52ZsDmFHqyY.pdf) · [YouTube](https://www.youtube.com/watch?v=52ZsDmFHqyY) (@chart-fanatics) |
| **Origin** | [chartfanatics.com/strategies/small-cap-short-statistics](https://www.chartfanatics.com/strategies/small-cap-short-statistics) · [Glimpse](https://glimpse.wozart.com/v/qqsih81n) |
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
- **Verdict:** Implemented as a trading EA carrying the document's statistics - the three strategies all have observable mechanical rules, so they are coded as rules with the document's own numbers, and the statistics database the video keeps insisting every trader must build ("Create a spreadsheet to track market cap, float, volume, sector, and outcomes for every setup you encounter") is written to CSV with the win-rate band of every logged setup. **Gap up short**: "Gap must be above 100%", a 1-2 hour consolidation, then "enter partial position on first breakdown" - the EA takes the partial at the breakdown and the **full add when momentum cracks 3-5% below consolidation**, with the stop above the consolidation high and the target at the **26% average fade** from the intraday high (the 20-35% band). **Bounce short**: the old resistance from 1+ year ago must carry a **dollar block of 150M+** ("volume traded at resistance x price"), the **trapped-to-intraday ratio** gates the trade (2:1 strong, 10:1 exceptional, which drives the size) and the entry is the rejection of the old level; the type picks the fade target - **Type 1 (gapping straight to the level) fades 75%**, Type 2 fades 50% - and exits are gradual, giving supply back. **First red day**: 3+ consecutive green days with increasing volume and 300%+ range (1000%+ for the two-day variant), a **1/4 scout** on the final green day, and the **3/4 add** on the first red day when the volume drops (pre-market volume is not observable, so the drop is read from the day's volume pace against yesterday - labelled) - stop above consolidation. Sizing follows the document's conviction model: the ratio and the setup's own win-rate band decide the risk weight.
- **Instruments:** `AAPL,MSFT,NVDA` default - the playbook trades **small caps** ($1-100M cap, $1-50M float, price > $3, no biotech/energy/Chinese names), none of which MetaTrader exposes, so the universe input carries that selection (disclosed in the header and notes)
- **Timeframe / session:** M5 execution; entries from the open with no new risk after midday ET (the volume concentrates 9:30-11:30 AM), flat at the US close
- **EA file / magic:** [`EA_CF_SmallCapShortStatistics.mq5`](../mql5-eas/EA_CF_SmallCapShortStatistics.mq5) / `3238` (static-checked)
- **Priority:** P1 - the queue's statistics card
- **Blocked by:** _nothing_
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: the trading journey and philosophy, the universal criteria (market cap and float ranges,
  the $3 minimum price, the sectors to avoid, the pre-market volume estimation), all three strategies
  (gap up short: criteria, statistics, entry/exit, float-based sizing; bounce short: psychology, the
  dollar block calculation, the volume ratio, the Type 1 / Type 2 fades, sizing limits, entry/exit; first
  red day: setup requirements, predicting the top, statistics, the entry strategy, risk management, why
  it is the primary wealth-building setup), the real trade examples (GME, Beyond Meat, Bird, Silver) and
  the key insights (statistics drive sizing, psychology + mechanics, large accounts need gradual exits,
  ten years of hand-tracked data, avoid crowded tickers).
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_SmallCapShortStatistics.mq5` (39 rules pinned).
- `[interpretation]`: the consolidation tightness, the breakdown and rejection buffers, the add band, the
  fade centres (the document gives bands), the old-resistance scan window, the Type 1 proximity, the
  volume-pace estimate for the first-red-day drop, the sanity cap on stop width and the state machine
  that turns the 1/4 and 3/4 entries into two engine plans are inputs and labelled.
- Design notes: the staged entries (partial + full add, 1/4 + 3/4) use the engine's second position slot
  with the per-symbol risk weight through `LotsMultiplier`, mirroring the document's own vocabulary of
  entering in pieces; the ratio and setup determine conviction and therefore size, as the document's
  "statistics drive sizing" insight demands. Exits are the engine's 1R partial ("exit gradually on the
  way down, not all at once, to allow supply back into market") plus the fade targets.
- Disclosed, not faked: market cap, float and its buckets, the sector exclusions, pre-market volume and
  the 10%-of-float / 1%-of-daily-volume caps are not observable in MetaTrader; the universe carries the
  stock selection and the EA enforces the observable substitutes. The hand-tracked database is replaced
  by the CSV, which logs every signal with its metrics and the documented win-rate band.
<!-- /edit:notes -->
