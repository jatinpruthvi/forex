# 02. 80/20 Nasdaq Strategy

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `80-20-nasdaq-strategy` |
| **Type** | video-only (Glimpse summary) |
| **Source** | [Glimpse summary](../glimpse/jsUTbjwpFVk.md) · [summary PDF](../glimpse-pdf/jsUTbjwpFVk.pdf) · [YouTube](https://www.youtube.com/watch?v=jsUTbjwpFVk) (@Okala8020) |
| **Origin** | [chartfanatics.com/strategies/80-20-nasdaq-strategy](https://www.chartfanatics.com/strategies/80-20-nasdaq-strategy) · [Glimpse](https://glimpse.wozart.com/v/2lfzrtk8) |
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
- **Verdict:** Tradable, implemented. NASDAQ mean reversion at price levels ending in 80/20, entered through three structures (fork long / H-pattern short / cross-section retest), with repair candles as magnet targets. Fixed 10-point stop, 15-point TP1 (half off), break-even, runners.
  `[interpretation]`: the video's 200-second chart is not a MetaTrader timeframe (M3 is the closest, M10 structure is exact); the fork's "targeting the previous low" is ambiguous for a long, so the document's own fixed stop/target are used; cross-sections are direction-neutral in the source, so the retest side plus the 80/20 confluence decides.
- **Instruments:** NASDAQ (playbook). EA: US100 (`InpSymbolsToTrade`) - the strategy is level-based, so other index CFDs work if their 80/20 endings mean the same thing
- **Timeframe / session:** Playbook: 10-minute structure + 200-second entries, New York open 09:30 ET, lunch 11:00-13:00 ET avoided. EA: M10 structure, M3 entries, London 14:30-16:00 and 18:00-20:00 (= 09:30-11:00 and 13:00-15:00 ET)
- **EA file / magic:** [`EA_CF_8020NasdaqStrategy.mq5`](../mql5-eas/EA_CF_8020NasdaqStrategy.mq5) / `3208` (static-checked)
- **Priority:** P1 - first level-anchored model in the family (no indicator dependence at all)
- **Blocked by:** _nothing_ (never compiled: MetaEditor run owed, see the Windows stage in [`../LOOP.md`](../LOOP.md))
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
_Nothing yet._
<!-- /edit:notes -->
