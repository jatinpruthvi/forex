# 37. SMT Divergence+PO3

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `smt-divergence-po3` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/smt-divergence-po3.pdf) (4.1 MB) |
| **Origin** | [chartfanatics.com/strategies/smt-divergence-po3](https://www.chartfanatics.com/strategies/smt-divergence-po3) · [source PDF on Google Drive](https://drive.google.com/file/d/15DBqFgBptjodeabXGpZtOSzXaYqJlp6y/view?usp=sharing) |
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
- **Verdict:** Tradable, implemented. PD high/low manipulation, SMT divergence against the twin index, entry on the reclaim, target the 50% level of the range.
  `[interpretation]`: the doc's "11:00 candle flips bearish -> break-even" becomes the engine's 1R BE; the 50% target is used only when it sits ahead of the entry.
- **Instruments:** Futures / Crypto (playbook). EA: US100 vs US500 (`InpSmtSymbol`), `InpSmtFailClosed` refuses to trade when the twin is unavailable
- **Timeframe / session:** Playbook: Daily -> 4H -> 1H -> intraday entry; manipulation typically ~10:00 ET. EA: M5 entries, H1 50% target, NY window 14:30-18:00 London
- **EA file / magic:** [`EA_CF_SMT_PO3.mq5](../mql5-eas/EA_CF_SMT_PO3.mq5) / `3203` (static-checked)
- **Priority:** P1 - the only cross-symbol implementation in the family; needs both symbols on the broker
- **Blocked by:** _nothing_
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
### EA implemented 2026-10-07
- **Source read:** `pdf/smt-divergence-po3.pdf` (11 pp, Trader Kane) - daily 50% level + PO3 + NQ/ES SMT divergence at ~10:00 ET, base hit to the 50% level.
- **EA:** [`mql5-eas/EA_CF_SMT_PO3.mq5`](../mql5-eas/EA_CF_SMT_PO3.mq5), magic `3203`, M5.
- **Encoded:** previous day's range and its 50% level; premium/discount gate; Asian accumulation -> NY-session sweep via `SigSweepReclaim`; direct symbol-vs-symbol SMT divergence (`InpSmtSymbol`, default `US500` for a `US100` leg) instead of the engine's RSI-on-DXY proxy, which is inert without DXY; target = the 50% level with a 1.5R floor.
- **Gaps:** the pair symbol must exist at the broker. Without it the SMT gate fails OPEN by default (loud log); set `InpSmtFailClosed=true` to refuse entries instead. The "11:00 candle flips bearish" break-even rule is approximated by the engine's 1R break-even.
   - Sessions come from the engine's session window machinery; the direct NQ-vs-ES comparison remains local because the engine's own SMT check is an RSI-on-DXY proxy that goes inert without DXY.
- **Status:** passes `scripts/check_mql5_source.py` (0 findings); **not yet compiled**.
<!-- /edit:notes -->
