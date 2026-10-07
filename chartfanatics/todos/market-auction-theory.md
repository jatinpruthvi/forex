# 20. Market Auction theory

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `market-auction-theory` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/market-auction-theory.pdf) (2.1 MB) |
| **Origin** | [chartfanatics.com/strategies/market-auction-theory](https://www.chartfanatics.com/strategies/market-auction-theory) · [source PDF on Google Drive](https://drive.google.com/file/d/1nF6o7icjvre7ArUyOoKA0URCs9w5p2-z/view?usp=sharing) |
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
- **Verdict:** Implemented as a strategy. It is a clean top-down model and the EA carries every stated rule: the **daily bias** comes from the previous day's candle (a strong body, plus the **45-degree trend** as an ATR-normalised slope) and the daily **21/50 MAs**; the **5-minute must mirror it** (price on the same side of both MAs, the MAs stacked) - the document's "if the daily and 5-minute trades are not aligned, skip the trade". The **auction zone** is the post-open congestion (the breakdown's own "clean consolidation area after the open"), refused when the structure is "messy" (a cap on the zone width), and the EA requires price to have **left the zone in the trend direction** before it returns ("broke down from this zone, confirming trend continuation"). The setup is the **rejection candle** - it trades into the zone and closes back out of it - entered immediately after the candle closes, with the **stop just beyond that candle's high/low** and the document's **minimum 2:1** target. The **first hour** is the default window (the doc's "focus on the first hour"; the "unless conditions clearly align" extension is an input, off by default), the **gap context** must agree with the bias (the breakdown's gap down), and the doc's "conflicting news headlines" is handled by the engine's calendar gate.
- **Instruments:** stocks (the example is SPY); the doc extends the same principles to indices and crypto - `InpSymbolsToTrade` (default `US500,US100`)
- **Timeframe / session:** D1 bias, M5 execution; first hour after the New York open (`14:30-15:30` London by default), 2 trades/day (first and second retest)
- **EA file / magic:** [`EA_CF_MarketAuctionTheory.mq5`](../mql5-eas/EA_CF_MarketAuctionTheory.mq5) / `3223` (static-checked)
- **Priority:** P1 - the second of the library's two auction models, and the more rule-based one
- **Blocked by:** _nothing_
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: overview (the market as a daily auction; value area from the previous day; top-down D1 bias +
  5m execution; trades only when both align; the key setup = return to the auction zone and reject in the trend
  direction, first hour); timeframes; trend alignment via MAs used "only to confirm"; directional bias from the
  previous day's candle; the auction zone (congestion / value area); open and gap context (gapping up/down,
  inside/outside the prior range); the 45-degree daily trend and "wait for alignment"; entry after the rejection
  candle closes; stop beyond the setup candle; the 2:1 minimum; no-trade conditions (misaligned, messy structure,
  unclear sentiment/news, no retest); time of day (first hour, avoid middle/late); pros/cons; the breakdown
  (downtrend below the 21 EMA, gap down, post-open consolidation, break down, return to the zone, rejection
  candle closing below, entry, stop above the candle, 2:1 target, the second retest).
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_MarketAuctionTheory.mq5` (28 rules pinned).
- `[interpretation]`: the formation window and zone-width cap, the "strongly" body threshold, the 45-degree slope
  threshold, the stop tick buffer, the second-entry allowance, the extended window (off by default) and the
  calendar gate as the "conflicting news" stand-in. The doc says the numbers are examples.
- Engine reuse: `SigRangeForDay` (the auction zone), `cfg.newsFilter`, the M5 EMA set from the context, engine risk
  sizing and the 1R scale-out. The daily 21/50 EMA pair is computed locally because the engine carries only the
  daily 200 (documented).
<!-- /edit:notes -->
