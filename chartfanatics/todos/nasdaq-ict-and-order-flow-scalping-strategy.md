# 25. Nasdaq ICT and Order Flow Scalping Strategy

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `nasdaq-ict-and-order-flow-scalping-strategy` |
| **Type** | video-only (Glimpse summary) |
| **Source** | [Glimpse summary](../glimpse/KkTTCKr-3Ew.md) · [summary PDF](../glimpse-pdf/KkTTCKr-3Ew.pdf) · [YouTube](https://www.youtube.com/watch?v=KkTTCKr-3Ew) (@chart-fanatics) |
| **Origin** | [chartfanatics.com/strategies/nasdaq-ict-and-order-flow-scalping-strategy](https://www.chartfanatics.com/strategies/nasdaq-ict-and-order-flow-scalping-strategy) · [Glimpse](https://glimpse.wozart.com/v/9mezeyor) |
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
- **Verdict:** Implemented as an EA - a hard-gated one. The document is a **three-step system** and the code runs the
  three steps in order, quoting the source: **step 1** H4 macro structure (higher highs + higher lows, or the mirror)
  with the engine's D1 EMA200 on the same side and price pulled back into fair value (a 25-90% band of the newest leg -
  still at the extreme means wait, deeper means a reversal, not a pullback); **step 2** the H1 secondary structure must
  show the document's own weakness - lower highs, a close below the previous high, and sell-side volume beating the buy
  side before a short (mirrored for longs); **step 3** one of the three entry models on M1 - **IFBG** (liquidity taken
  above a high, a fair value gap, then a close with volume below the gap), **change of character** (the document's
  preferred model: sweep -> break with volume -> a retest that cannot reclaim the level) or **break & retest**
  (continuation; only when the macro bias agrees) - each accepted only after the orderflow layer confirms the
  direction. Bookmap's heatmap / volume dots / spoof detection cannot be read from an EA: the orderflow layer is the
  tick-volume proxy the document itself names (session POC, VWAP, body-direction aggression, the absorption read "if
  buyers can't push price above a level despite high buy volume, sellers are absorbing those buys"), and "watch for
  spoofing" stays a human task - disclosed, not faked. **"The entry model is only a trigger, not confirmation"**: a
  setup missing any layer is skipped, exactly as the action items demand.
- **Instruments:** `US100` (the document's NASDAQ; a CME NQ proxy on a CFD broker)
- **Timeframe / session:** M1 execution ("30-second or 1-minute charts ... allows tight stops") with the H4 macro and H1
  secondary reads; default window **Asia 00:00-08:00 London** ("tends to have clearer structure and less manipulation"),
  with New York 14:30-20:00 London alongside it - a CFD broker's US100 may be closed or untradeably wide in Asia while
  the doc trades CME NQ
- **EA file / magic:** [`EA_CF_NasdaqIctAndOrderFlowScalpingStrategy.mq5`](../mql5-eas/EA_CF_NasdaqIctAndOrderFlowScalpingStrategy.mq5) / `3228` (static-checked)
- **Priority:** P1 - the family's only pure ICT + order-flow model, and the strictest gate stack
- **Blocked by:** _nothing_
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: the three-step system (macro context - secondary structure - entry model + orderflow), the three entry
  models (IFBG, change of character, break and retest), "entry model is not confirmation" / confluence over single
  signals, the bookmap layer (heatmap, volume dots, order book), POC and VWAP ("when they lose control - POC flips,
  VWAP breaks"), buyer/seller aggression and absorption, spoofing (a human watch, not faked), why Asia suits NASDAQ,
  why lower timeframes matter (tight stops), the three live examples (liquidity target, profit before resistance,
  trailed stop), "close at break-even or skip" on sketchy conditions, "no mechanical strategies" (models are triggers),
  and the action items (skip any setup missing a layer).
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_NasdaqIctAndOrderFlowScalpingStrategy.mq5` (26 rules pinned).
- `[interpretation]`: bookmap is a tick-volume proxy (session POC from M1 bins, VWAP anchored to the clock-day open,
  body-direction aggression); the fractal strengths, sweep tolerance, gap floors, freshness windows, aggression ratio,
  POC bin count, the sketchy thresholds (volume pace, range floor, POC dominance, opening burst), the stop cap, the
  target floor, the partial and the flip confirmation are engineering numbers the document does not state.
- Design notes: the flow cache rebuilds once per closed M1 bar (Manage runs on every tick); the "sketchy" gates are
  session-scoped on purpose - a window that reached back into the previous (much busier) New York session would read
  every quiet Asia bar as "low volume" and block the document's own preferred window; the tight-stop cap is what makes
  the M1 execution faithful (a setup needing more than 1x M1 ATR is skipped rather than traded with a huge stop).
- Audit: the first draft read the sketchy volume pace across the whole scanned window (cross-session contamination -
  fixed by session-scoped stats) and rebuilt the 360-bar profile several times per tick (fixed by the per-bar cache);
  both were caught in the self-review before the checker/judge run.
<!-- /edit:notes -->
