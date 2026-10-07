# 27. Options Trading Masterclass

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `options-trading-masterclass` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/options-trading-masterclass.pdf) (3.5 MB) |
| **Origin** | [chartfanatics.com/strategies/options-trading-masterclass](https://www.chartfanatics.com/strategies/options-trading-masterclass) · [source PDF on Google Drive](https://drive.google.com/file/d/1cEFqPT1m7IR_EYf81Wiwf73PRf7B7wX5/view?usp=sharing) |
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
- **Verdict:** Implemented as a **monitor** (never trades). The document is a ten-page fundamentals masterclass - what an option is (strike, expiration, premium), calls vs puts, ITM/ATM/OTM, intrinsic vs extrinsic value, time decay, implied volatility and the volatility crush, the Greeks (delta / theta / vega / gamma), liquidity (volume and open interest) and position sizing - and it states **no entry rule, no exit rule, no stop and no target**; an MT5 EA cannot read an option chain either. So the five operational lessons are audited against the account instead: **premium = maximum risk** (each live position's money at risk, `EA_LossPerLotAllIn` x volume, against a per-position budget; a no-stop position is flagged as having no defined premium), **theta = time decay** (holding time from the entry deal to the exit deal, against the trader's own style horizon), **liquidity = fills** (the engine's slippage ring and the scope's spreads against budgets), **vega = the volatility-crush analogue** (entries taken while the day's range is expanded against its own median; a CFD has no IV feed, so the analogy is labelled), and **sizing = concentration** (the day's peak deployed risk against the cap). The output is the trader's study sheet: one CSV row per tenet per day, a five-tenets PASS/FLAG card and a live risk registry snapshot.
- **Instruments:** the account's own scope (`InpSymbolsToTrade`, default the family's `US100,US500`); `InpMagicFilter` 0 = every magic on that scope
- **Timeframe / session:** M15 report tick for the once-a-day writer; no session gate (an audit runs after the day closes)
- **EA file / magic:** [`EA_CF_OptionsTradingMasterclass.mq5`](../mql5-eas/EA_CF_OptionsTradingMasterclass.mq5) / `3230` (static-checked)
- **Priority:** P1 - v1 follow-ups depend on knowing whether trades followed the playbook
- **Blocked by:** _nothing_
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: what an option is (the premium example), the three core parts (expiration / strike /
  premium), buyers and sellers (the premium caps the buyer's risk), calls and puts, exercising vs trading
  the premium, ITM / ATM / OTM, intrinsic vs extrinsic value, why time matters (theta), implied volatility
  (the earnings spike and the volatility crush), the Greeks, liquidity (volume and open interest), position
  sizing and risk ("sizing to zero" vs stop-losses), and the final takeaways.
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_OptionsTradingMasterclass.mq5`
  (17 rules pinned).
- `[interpretation]`: every threshold is an engineering number the document does not state - the
  per-position premium budget (1% of equity), the deployment cap (3%), the day / swing style horizons
  (8 h / 120 h), the slip budget (0.10R), the spread budget (5 points), the volatility-expansion flag
  (1.50x) and its 20-day median window - all exposed as inputs and labelled in the source.
- Disclosed, not faked: delta / gamma / theta / vega and open interest are option-chain quantities with no
  CFD feed, so they are not implemented and no fake Greek is printed; the monitor reports only the honest
  analogues (money risk, time carried, fills, realised expansion). The option-specific mechanics themselves
  (strike selection, expiration choice, premium pricing, rollovers) cannot be traded as a CFD instrument
  and are out of EA scope; the document's worked examples are educational, not signals.
- Design note: the monitor never trades (`BuildPlan` returns false) and prices its risk through the
  engine's own money helper (`EA_LossPerLot`, which prefers the loss tick value), so the premium analogy is
  audited in the account's currency; the theta read runs `HistorySelectByPosition` per position closed in
  the audited day, so a cross-day hold gets its true entry time. The day's counters are per position
  (flagged once), never per tick, and the live registry retires closed tickets at the rollover.
<!-- /edit:notes -->
