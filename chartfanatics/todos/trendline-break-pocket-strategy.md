# 43. Trendline Break Pocket Strategy

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `trendline-break-pocket-strategy` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/trendline-break-pocket-strategy.pdf) (33.0 MB) |
| **Origin** | [chartfanatics.com/strategies/trendline-break-pocket-strategy](https://www.chartfanatics.com/strategies/trendline-break-pocket-strategy) · [source PDF on Google Drive](https://drive.google.com/file/d/1H_BcKIlQjatySwLPRZu1m9TGAVMz2byW/view?usp=sharing) |
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
- **Verdict:** Implemented as a trading EA - this is the most explicit playbook of the queue ("You only take a trade when all of the following are true"), and every condition is coded as a gate in the document's own order. The market condition read is the pocket itself: "price hits the key level -> trendline is broken -> last swing is broken (momentum shift)" and "only then does the market qualify". **The level** is a Frequency & Proximity zone: pivots cluster into zones, zones need "multiple highs rejecting a similar price area" (the minimum two clean hits), a recent test ("if the recent price has tagged and respected it -> strong, active zone"), and a low break-count - "mid-range areas that have been broken through repeatedly are largely ignored". **The trendline** is drawn through the two most recent same-side swings, which is the repeatable version of "the most recent swing that created the last higher high or lower low" and of "if price steepens ... use the more recent one"; the break is a completed close through the line, and - exactly as stated - "breaking the trendline does not trigger a trade", it only opens the pocket. **The momentum shift** is the break of the last higher low (uptrend) / last lower high (downtrend) *after* the trendline break: "No swing break = no trade ... this removes 90% of the fake trendline breaks". **The overshoot rule** counts distinct pierces beyond the zone: one is allowed ("a deeper wick or push"), a second voids the setup. **Both entries** are implemented - the core pullback into the 21 EMA as a resting limit order placed *at* the EMA (the engine's limit path honours the order's expiry), and the consolidation breakout requiring at least two highs and two lows on the correct side of the broken structure. **The 2R model** is literal: the target is the extreme formed after the momentum shift and the stop is half the distance to it, so the base model's 2:1 is exact; the clean-air rule scans the entry-to-target corridor for blocking zones and skips the trade when the path is not clear; MACD divergence is scored (and can be made a gate). **Management is deliberately absent** - "for standard 2R setups: no micromanagement, no trailing, no early exits" - so the engine trades only the target and the stop.
- **Instruments:** `EURUSD,GBPUSD,USDJPY` default - the playbook is Forex swing; "works on any market with clean structure" means the universe is an input
- **Timeframe / session:** daily trigger (the document's default) with the weekly context carried by the pivot width; FX runs around the clock so the session gate stays open and positions ride to the 2R target
- **EA file / magic:** [`EA_CF_TrendlineBreakPocketStrategy.mq5`](../mql5-eas/EA_CF_TrendlineBreakPocketStrategy.mq5) / `3243` (static-checked)
- **Priority:** P1 - the queue's trendline-structure card
- **Blocked by:** _nothing_
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: the playbook overview (the three market conditions and why only the pocket is traded),
  "What You Trade" (the four conditions, the 2R base model, the ~58% win rate), the Frequency & Proximity
  method (frequency, proximity, key levels vs proceed-with-caution levels), the market-conditions
  framework, the playbook rules (the overshoot rule, the momentum-shift confirmation, the two entry rules,
  how to draw the trendline, the trendline-is-not-an-entry note, the stop/target rules, the clean-air
  requirement, the optional filters, both entry types, the timeframe rules, MACD divergence, retail
  sentiment, and the no-micromanagement management rule), why the pocket works, the pros and cons and
  both worked examples.
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_TrendlineBreakPocketStrategy.mq5`
  (41 rules pinned).
- `[interpretation]`: the pivot width behind "the most recent swing", the zone cluster tolerance and the
  touch / break / overshoot windows, the level-proximity percentage, the pocket window, the trendline
  close-through buffer, the consolidation tolerance, bar count and "not a leg" bound, the stop-width
  sanity cap, the clean-air window and the limit order's life are inputs and labelled.
- Design notes: the trendline is the two-point line through the most recent same-side swings, evaluated
  at each bar by index - the document's "consistent, repeatable way to draw them" expressed as
  arithmetic, with the price-steepens rule falling out of using the newest swings. The zone book is
  rebuilt from the daily series on every decision, so frequency and proximity are measured, not drawn.
  The engine's limit path already handles the case where the market is at/past the EMA price (it enters
  at market rather than resting a dead order), which is what "the EMA is touched" means in practice.
- Disclosed, not faked: retail sentiment requires a positioning feed MetaTrader does not provide, so the
  document's sentiment condition is left to the human and not simulated; the weekly analysis frame is
  carried by the pivot width on the daily series rather than a second chart the EA cannot read
  consistently; the "optional filters for extending targets beyond 2R" are not invented - the base model
  ships as stated.
<!-- /edit:notes -->
