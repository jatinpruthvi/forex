# 05. Auction Market Strategy

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `auction-market-strategy` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/auction-market-strategy.pdf) (5.6 MB) |
| **Origin** | [chartfanatics.com/strategies/auction-market-strategy](https://www.chartfanatics.com/strategies/auction-market-strategy) · [source PDF on Google Drive](https://drive.google.com/file/d/11SMHgZFCSHQLQXd5-Qx586mYRkX8bNLB/view?usp=sharing) |
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
- **Verdict:** Tradable, implemented. Two complementary setups selected by the market state: a trend model (continuation out of balance: impulse leg -> LVN -> aggression -> stop beyond the print -> previous balance POC) and a mean-reversion model (failed auction outside value -> reclaim -> pullback into the reclaim leg's LVN -> POC).
- **Instruments:** Futures (playbook: NASDAQ, ES). EA: US100 / US500 / GER40 (`InpSymbolsToTrade`)
- **Timeframe / session:** Playbook: order-flow scalping; trend model in the New York session, mean reversion in London (avoiding the London open). EA: M5 signal, London 14:30-19:00 for the trend model and 08:00-11:30 for the reversion model
- **EA file / magic:** [`EA_CF_AuctionMarket.mq5](../mql5-eas/EA_CF_AuctionMarket.mq5) / `3210` (static-checked)
- **Priority:** P2 - the two-model split is a good A/B for the tester (each side switchable)
- **Blocked by:** _nothing_ (never compiled: MetaEditor run owed, see the Windows stage in [`../LOOP.md`](../LOOP.md))
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
_Nothing yet._
<!-- /edit:notes -->
