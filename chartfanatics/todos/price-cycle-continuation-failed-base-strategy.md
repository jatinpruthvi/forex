# 33. Price Cycle Continuation & Failed Base Strategy

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `price-cycle-continuation-failed-base-strategy` |
| **Type** | video-only (Glimpse summary) |
| **Source** | [Glimpse summary](../glimpse/0_NSmOWVbpA.md) · [summary PDF](../glimpse-pdf/0_NSmOWVbpA.pdf) · [YouTube](https://www.youtube.com/watch?v=0_NSmOWVbpA) (@chart-fanatics) |
| **Origin** | [chartfanatics.com/strategies/price-cycle-continuation-failed-base-strategy](https://www.chartfanatics.com/strategies/price-cycle-continuation-failed-base-strategy) · [Glimpse](https://glimpse.wozart.com/v/0umqvnju) |
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
- **Verdict:** Implemented as a full EA with **both cycles** of the playbook. **Long - the bullish continuation**: an established uptrend (the 50-day EMA rising, price over the 200-day EMA) plus a base that is "tight" on **receding volume** ("receding volume during consolidation signals low supply"); entry either **buying on strength** - a close above the horizontal consolidation level with **large volume** ("large volume on the wedge pop confirms demand"), stop at "the low of the current or prior day" - or **buying on weakness** - the pullback into the 10 or 20-day EMA, which the document prefers for its "much tighter risk-reward". The selection filters are the document's own: **$50M average daily dollar volume, more than 3% ADR, relative strength versus the market** (a proxy symbol, US100 by default). The scaling is the document's own too: **1/3 off at 2x the ADR, another 1/3 at 8-10x ATR extension from the 50-day EMA, and the final 1/3 trailed on the 10 or 20-day EMA, exiting on violation** - hand-rolled in `Manage()` because the rules are price/volatility based, with per-ticket one-shot flags persisted as global variables. **Short - the failed base**: a base whose breakout attempt failed, the **20-day EMA violated on larger volume than recent bars**, then the recovery **wedge on minimal volume** stalling at a lower high - short "the turn lower" with the stop just above the **high of day**, gated on the **broader market declining**. Covers are the document's: **half on the undercut and rally**, the rest when price **reclaims the 10-day EMA**; re-entries capped at **3 attempts per ticker** counted from the day's own sell-side deals. **Timing**: "Daily chart is used for setup identification and context, while 5-minute chart is used for precise entry timing" - the EA reads D1 context and executes on M5; positions are held for days (no flatten at the bell).
- **Instruments:** `AAPL,MSFT,NVDA` (stocks, per the playbook's selection criteria); the market proxy is `InpMarketSymbol` (default `US100`, the QQQ analogue)
- **Timeframe / session:** M5 execution on D1 context; entries timed in the US RTH window (14:30-21:00 London), positions held across days
- **EA file / magic:** [`EA_CF_PriceCycleContinuationFailedBaseStrategy.mq5`](../mql5-eas/EA_CF_PriceCycleContinuationFailedBaseStrategy.mq5) / `3235` (static-checked)
- **Priority:** P1 - the only card with a documented short-side cycle as well as the long
- **Blocked by:** _nothing_
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: the championship track record and risk-reward philosophy, the long setup (price cycle
  foundation, buying on strength, buying on weakness, stock selection, scaling out, the two timeframes),
  the short setup (failed base, the 20-day EMA invalidation, the wedge and the entry, market
  confirmation, the undercut-and-rally covers, aggressive profit taking), the chart examples (AFRM,
  PLTR, CORE), simplicity vs analysis paralysis, win rate vs risk-reward, execution and psychology
  (historical study, market context, re-entry discipline, reaction vs anticipation), and the advanced
  concepts (relative strength, volume as supply/demand, base duration, ATR-based scaling, the 5-minute
  entry timing).
- Sync table: `tests/test_chartfanatics_sync.py` ->
  `EA_CF_PriceCycleContinuationFailedBaseStrategy.mq5` (39 rules pinned).
- `[interpretation]`: the document states its headline numbers (50M ADV, 3% ADR, 2x ADR, 8-10x ATR, the
  1/3s, the 20 and 10 EMAs, 3 attempts) and leaves the rest to the trader - the base window and its
  tightness, the pullback tolerance, the volume ratios (breakout, invalidation, minimal recovery), the
  relative-strength threshold, the stop buffers and the max-stop sanity cap, the wedge lookback, the
  prior-low window, the recovery lookback, and the far take-profit placeholders (the scaling and covers
  are the real exits). All are inputs and labelled.
- Design notes: the two long exits (2x ADR profit, 8-10x ATR extension) are price/volatility based, so
  they are hand-rolled in `Manage()` rather than the engine's R-based partials, with one-shot flags
  stored as globals keyed by ticket (the engine's own risk keys follow this pattern); the EMA trail and
  the short covers are likewise the document's rules, not engine defaults, and the engine's break-even /
  trailing stay off because the document states no such rule. The dollar-volume filter needs share
  volume - brokers publishing none fall back to tick volume, disclosed in the header.
- Disclosed, not faked: training the eyes on year-by-year winners, the AI/fundamental research, the
  "30% anticipation" cycle opinion, and the single-monitor discipline are human steps. The QQQ read is a
  proxy symbol the user can point anywhere.
<!-- /edit:notes -->
