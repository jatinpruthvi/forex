# 06. Auction Market Theory Strategy

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `auction-market-theory-strategy` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/auction-market-theory-strategy.pdf) (12.4 MB) |
| **Origin** | [chartfanatics.com/strategies/auction-market-theory-strategy](https://www.chartfanatics.com/strategies/auction-market-theory-strategy) · [source PDF on Google Drive](https://drive.google.com/file/d/1bZmiYn2Sga8l9gRqrY1tFZZQbOLI1VtV/view?usp=sharing) |
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
- **Verdict:** Tradable, implemented. Around a tick-volume value area: failed auction at VAL/VAH -> reversal to POC (setups 1-2), accepted breakout of the opening range -> continuation (setup 3), and the playbook's own order-flow exit (strong opposing body back through value, once the trade works) implemented as a custom Manage().
- **Instruments:** Futures (playbook). EA: US100 / US500 / GER40 (`InpSymbolsToTrade`)
- **Timeframe / session:** Playbook: day trading around value; NY opening range for the breakout layer. EA: M5 signal, London 14:25-20:00 (NY 09:25-15:00), entries until 15:00 ET
- **EA file / magic:** [`EA_CF_AuctionMarketTheory.mq5](../mql5-eas/EA_CF_AuctionMarketTheory.mq5) / `3211` (static-checked)
- **Priority:** P1 - the acceptance test (body vs wick) is the most transferable idea in the auction-market pair
- **Blocked by:** _nothing_ (never compiled: MetaEditor run owed, see the Windows stage in [`../LOOP.md`](../LOOP.md))
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
_Nothing yet._
<!-- /edit:notes -->
