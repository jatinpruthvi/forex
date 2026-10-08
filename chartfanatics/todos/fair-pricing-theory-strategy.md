# 09. Fair Pricing Theory Strategy

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `fair-pricing-theory-strategy` |
| **Type** | video-only (Glimpse summary) |
| **Source** | [Glimpse summary](../glimpse/KHEQ5g55dQ4.md) · [summary PDF](../glimpse-pdf/KHEQ5g55dQ4.pdf) · [YouTube](https://www.youtube.com/watch?v=KHEQ5g55dQ4) (@itsjjsimon) |
| **Origin** | [chartfanatics.com/strategies/fair-pricing-theory-strategy](https://www.chartfanatics.com/strategies/fair-pricing-theory-strategy) · [Glimpse](https://glimpse.wozart.com/v/b3tn99g9) |
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
- **Verdict:** Tradable, implemented. Pure 1-minute price action around a fair price (previous day's close / session open): displacement-candle continuation, break-of-structure continuation, and reversions of unfair displacements back to fair price. The source's money management is the core: TP first (distance to fair price), stop = static reciprocal (the 1:1/1:1.5 evaluation ratio or 1:4 funded), three-loss rule ends the session, and only the first 90 minutes of the NY AM, Asia and NY PM opens are traded.
- **Instruments:** NASDAQ futures (source). EA: US100 (`InpSymbolsToTrade`)
- **Timeframe / session:** Playbook: 1-minute chart; NY 09:30-11:00 ET, Asia open, NY PM 14:00-15:30 ET; 11:00-14:00 dead zone skipped. EA: M1 signal, London 14:30-16:00 / 01:00-02:30 / 19:00-20:30
- **EA file / magic:** [`EA_CF_FairPricingTheory.mq5](../mql5-eas/EA_CF_FairPricingTheory.mq5) / `3213` (static-checked)
- **Priority:** P1 - the static-R:R + TP-first construction is the prop-firm pattern the repository's other EAs do not yet use
- **Blocked by:** _nothing_ (never compiled: MetaEditor run owed, see the Windows stage in [`../LOOP.md`](../LOOP.md))
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
_Nothing yet._
<!-- /edit:notes -->
