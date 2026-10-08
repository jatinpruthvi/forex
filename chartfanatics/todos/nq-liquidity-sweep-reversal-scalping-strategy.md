# 26. NQ Liquidity Sweep & Reversal Scalping Strategy

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `nq-liquidity-sweep-reversal-scalping-strategy` |
| **Type** | video-only (Glimpse summary) |
| **Source** | [Glimpse summary](../glimpse/-kGVL93XfyE.md) · [summary PDF](../glimpse-pdf/-kGVL93XfyE.pdf) · [YouTube](https://www.youtube.com/watch?v=-kGVL93XfyE) (@chart-fanatics) |
| **Origin** | [chartfanatics.com/strategies/nq-liquidity-sweep-reversal-scalping-strategy](https://www.chartfanatics.com/strategies/nq-liquidity-sweep-reversal-scalping-strategy) · [Glimpse](https://glimpse.wozart.com/v/kmwhgkoo) |
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
- **Verdict:** Implemented as an EA. The document is a kill-zone scalping model and the code keeps its order:
  **window** - the London kill zone 02:00-05:00 EST ("she avoids pre-2am setups despite temptation") plus the
  New-York open 09:30-09:50 EST ("New York trades end within 10-15 minutes"), both gated on the document's own
  fixed EST clock (UTC-5, never DST-shifted); **liquidity** - a sweep of the Asia range (`SigAsianRange`) or of
  a recent swing extreme, with tolerance ("identifying where price has swept liquidity (Asia high/low, swing
  highs/lows)"); **entry** - the inverted fair value gap: a counter-directional gap is closed fully through by a
  *fresh* trigger candle ("A bearish FVG forms when price gaps down without filling the gap. When a bullish candle
  closes above it, it becomes an inverted FVG - a valid entry"; the conservative variant the document names, and
  a stale inversion is rejected); **stop** - the session caps the document states (London 20-25, New York 30-40
  index points), because "If I had to use a larger stop loss to enter, that means that is not the entry point";
  **target** - the closest higher-timeframe liquidity pool the document marks (Asia high/low, daily FVG edges,
  1-hour FVG edges, the RTH gap quarters built from the 16:00 EST close and the 09:30 EST open - "she targets
  the 75 percent level" - and the midnight opening price) with the 1:2 minimum floor, so a 1:3/1:4 pool extends
  the target; **size** - a confluence count (Asia sweep, daily-FVG sweep, 1-hour-FVG fill, an equal-highs/lows
  run, displacement) drives `LotsMultiplier()`: A+ = full risk, B/C = 0.40x ("A+ setups ... 5 contracts ... B/C
  setups: 2 contracts"); **management** - 1R partial + break-even, a half-close when price reaches the opposing
  1-hour FVG ("if price enters it during a trade, she closes at least half the position") and a trail behind the
  newest minor swing once a minor sweep prints ("she trails her stop to a tighter level - sometimes to
  break-even"). The daily loss limit is dollar-based, as the document insists: $3,000 on a $160,000 account =
  1.875%.
- **Instruments:** `US100` (the document's NQ on a CFD feed)
- **Timeframe / session:** M1 entries ("Candice enters on 1-minute charts"); the 15/30-second monitoring is not a
  MetaTrader timeframe, so "speed and displacement" is read from M1 bar internals (body share of range, range
  against ATR, tick volume) - labelled. Windows: London kill zone 02:00-05:00 EST and/or New York 09:30-09:50 EST
  (`InpSessions`)
- **EA file / magic:** [`EA_CF_NqLiquiditySweepReversalScalpingStrategy.mq5`](../mql5-eas/EA_CF_NqLiquiditySweepReversalScalpingStrategy.mq5) / `3229` (static-checked)
- **Priority:** P1 - the family's kill-zone scalper: tight stops, pooled targets, confluence-sized risk
- **Blocked by:** _nothing_
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: the ICT foundation (algorithms target liquidity at swing highs/lows; AMD across sessions), the
  London kill zone (02:00-05:00 EST, no pre-2am setups - discipline against overtrading), 1-minute entries with
  15/30-second monitoring, the three pillars (HTF analysis with daily candles and 1-hour FVGs, premium/discount
  and liquidity pools with the equal-highs/lows run, the FVG / inverted-FVG entry with aggressive vs conservative
  variants), the fixed per-session stop caps, the 1:2 minimum with targets adjusted to the closest HTF pool, the
  proactive trail after a minor sweep, the 5-vs-2 contract sizing by confluence, the dollar-based daily loss
  limit, the first-target exits ("close at the first target, not the whole move"), the New-York RTH-gap quarters
  and the seconds mattering at the open, and the psychology sections (personality-driven rules, lifestyle
  alignment, three exit templates back-tested, mental capital above monetary capital).
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_NqLiquiditySweepReversalScalpingStrategy.mq5`
  (26 rules pinned).
- `[interpretation]`: 15/30-second monitoring is not a MetaTrader timeframe (M1 internals stand in); the
  document's "points" are NQ index points (1 index point = 1 price unit - the family's 80/20 convention -
  exposed as `InpIndexPointSize`); the sweep tolerance, gap floors, freshness windows, equal-run tolerance and
  count, the A+ confluence threshold, the daily loss percentage ($3,000/$160,000 = 1.875%) and the RTH scan
  depth are engineering numbers.
- Disclosed, not faked: scale-ins on additional FVGs (the engine holds one position per symbol), the "outage
  gap" reference from the fourth trade example, copy trading across 20 Apex accounts (a prop-firm feature), and
  the personality / lifestyle / back-test-templates / mental-capital action items, which are human decisions.
- Audit: the first draft scanned the inverted-gap zone only *newer* than the sweep bar and accepted any closed
  bar beyond the gap; both were caught in self-review and fixed (the gap may form on the way into the sweep, and
  the inversion must be fresh - the previous closed bar still on the far side). A placeholder body in the
  daily-FVG confluence check was replaced with the real geometry before the checker run.
<!-- /edit:notes -->
