# 31. PO3, OTE + ADR

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `po3-ote-adr` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/po3-ote-adr.pdf) (32.8 MB) |
| **Origin** | [chartfanatics.com/strategies/po3-ote-adr](https://www.chartfanatics.com/strategies/po3-ote-adr) · [source PDF on Google Drive](https://drive.google.com/file/d/1gk5jmT9BvTCFGwu3AoSdddBwnNxa2aws/view?usp=sharing) |
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
- **Verdict:** Tradable, implemented. Daily bias -> PD-array raid in one of the three sessions -> strong-body displacement past the level -> fib-anchored OTE limit with the stop at the 1.0 fib and TP at the 0.0 fib (R derived from the geometry: 1.63 / 2.39 / 3.76R for the 0.62 / 0.705 / 0.79 entries).
  `[interpretation]`: the doc's printed R table contradicts its own fib geometry (labels shifted one row) - the geometry wins and the discrepancy is noted in the source. "ADR" appears only in the title, so the daily-range budget gate is an interpretation.
- **Instruments:** Forex (playbook). EA: XAUUSD / US100 / US500 / EURUSD (`InpSymbolsToTrade`)
- **Timeframe / session:** Playbook: Daily + 4H bias, 15m / 30m confirmation, 5m refinement, never 1m; London open / NY open / London close. EA: M15 signal, all three session blocks, D1-200EMA bias, resting limit
- **EA file / magic:** [`EA_CF_PO3_OTE_ADR.mq5](../mql5-eas/EA_CF_PO3_OTE_ADR.mq5) / `3204` (static-checked)
- **Priority:** P1 - the tightest geometry in the family; also the card where the doc needed the most interpretation
- **Blocked by:** _nothing_
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
### EA implemented 2026-10-07
- **Source read:** `pdf/po3-ote-adr.pdf` (9 pp, NBB Trader) - Market Maker Model with fib-anchored OTE entries and a fixed R by geometry.
- **EA:** [`mql5-eas/EA_CF_PO3_OTE_ADR.mq5`](../mql5-eas/EA_CF_PO3_OTE_ADR.mq5), magic `3204`, M15.
- **Encoded:** daily bias (D1 200-EMA with a band, "never trade both ways"); proximity to a PD array (previous day high/low); the three documented sessions (London open / NY open / London close); a raid + body-candle displacement; a resting LIMIT at the 0.62-0.705 retracement with the stop at the 1.0 fib and take-profit at the 0.0 fib (0.62 -> 1.63R, 0.705 -> 2.39R, 0.79 -> 3.76R); break-even at 1.70R (the 0.20 fib from a 0.705 entry); ADR budget gate.
- **Gaps:** ADR is approximated by daily ATR (`ctx.atrD1`). The scale-in rule ("only when the first entry is at break-even or better") is not implemented - the engine holds one position per symbol.
   - The manipulation extreme (the 1.0 fib) is anchored to a confirmed swing point via `SigFractals`, with the raw bar extreme as fallback; the three sessions use `EA_InWindow`.
- **Status:** passes `scripts/check_mql5_source.py` (0 findings); **not yet compiled**.
<!-- /edit:notes -->
