# 13. Futures Trading Strategy

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `futures-trading-strategy` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/futures-trading-strategy.pdf) (5.3 MB) |
| **Origin** | [chartfanatics.com/strategies/futures-trading-strategy](https://www.chartfanatics.com/strategies/futures-trading-strategy) · [source PDF on Google Drive](https://drive.google.com/file/d/1xIXCbPLXJCvbrqNFcj1esgXaDaEpTEz5/view?usp=sharing) |
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
- **Verdict:** Tradable, implemented - and the rare playbook whose first rule is *not* a setup. The EA answers the document's one question on the daily chart first (Bollinger 20/3s bandwidth: contract = consolidation, expand = expansion, contract after a band peak = mean reversion) and only then executes: consolidation = two-way at the range edges (M30 execution), expansion = one direction only on a confirmed breakout of the prior box, mean reversion = the doc's explicit rule (daily close beyond the 30% line of the band-peak leg, target the 50% line, live until a daily close back through the line, smaller size counter-trend, hands in pocket once 50% is hit). Stops are structural (daily swing high/low) with the doc's own answer - "use options" - standing in as a skip when the stop is unrealistically wide; targets are the "unfinished business" band peak and week extremes; exits use the doc's tools (8/21/34 exit context, anchored VWAP, 1-5 trading day hold).
- **Instruments:** Index futures (S&P / Nasdaq / Russell; source). EA: `InpSymbolsToTrade`
- **Timeframe / session:** D1 environment, M30 execution (the doc names 60-min / 30-min), US cash session, 1-5 trading day hold
- **EA file / magic:** [`EA_CF_FuturesStrategy.mq5`](../mql5-eas/EA_CF_FuturesStrategy.mq5) / `3217` (static-checked)
- **Priority:** P2 - the environment filter other setups can inherit
- **Blocked by:** _nothing_ (never compiled: MetaEditor run owed, see the Windows stage in [`../LOOP.md`](../LOOP.md))
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Rule refs: p.2 overview + "daily process (non-negotiable)"; p.3 tools (Bollinger 20/3s, Beacon, MAs,
  optional RSI does not generate entries, anchored VWAP); p.4 consolidation; p.5 expansion + targets
  ("unfinished business") + options vehicle; p.6-7 mean reversion posture; p.8 the 30/50/70 levels
  and the bearish rule; p.9 execution rules; p.10 stops/risk ("risk in dollars", options when the
  stop is too wide); p.11 management & exits (8/21/34, anchored VWAP); p.12 pros/cons ("sometimes the
  correct trade is no trade"); p.13-14 bearish-expansion trade breakdown.
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_FuturesStrategy.mq5` (26 rules pinned).
- `[interpretation]`: Beacon anchor/leg (the tool is proprietary and described in words only);
  contracting/expanding = ratio vs the 20-day average bandwidth; anchored-VWAP anchor and its
  deviation bands (the 1R partial stands in); MA exit context reading.
<!-- /edit:notes -->
