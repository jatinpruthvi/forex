# 39. Structure + OTE

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `structure-ote` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/structure-ote.pdf) (6.9 MB) |
| **Origin** | [chartfanatics.com/strategies/structure-ote](https://www.chartfanatics.com/strategies/structure-ote) · [source PDF on Google Drive](https://drive.google.com/file/d/1nKM7slvicm-EULEhYto_QTQbEdz6BFvO/view?usp=sharing) |
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
- **Verdict:** Tradable, implemented. HTF dealing range -> break of structure -> retrace into the zone that caused the move (order block, breaker fallback) with the ORIGINAL trend, entered inside the OTE band of that leg.
  `[interpretation]`: the playbook names OTE but prints no fib numbers, so the band is the standard 62-79%.
- **Instruments:** Futures / Crypto / Forex (playbook). EA: US100 / US500 / GER40 (`InpSymbolsToTrade`)
- **Timeframe / session:** Playbook: top-down, HTF bias then execution on H1 or M15. EA: H4 dealing range, M15 signal (`InpLtfTimeframe`)
- **EA file / magic:** [`EA_CF_Structure_OTE.mq5](../mql5-eas/EA_CF_Structure_OTE.mq5) / `3202` (static-checked)
- **Priority:** P1 - first premium/discount + OTE implementation in the repo, reusable by later cards
- **Blocked by:** _nothing_
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
### EA implemented 2026-10-07
- **Source read:** `pdf/structure-ote.pdf` (10 pp, Trader Mayne) - HTF break of structure -> POI (OB/breaker) -> LTF confirmation, min 2R.
- **EA:** [`mql5-eas/EA_CF_Structure_OTE.mq5`](../mql5-eas/EA_CF_Structure_OTE.mq5), magic `3202`, M15 execution on an H4 range.
- **Encoded:** D1+H1 cascade bias; dealing range over 120 H4 bars with a premium/discount gate; OTE band 62-79% of the active leg; `SigOrderBlockRetest` POI entry (direction-locked) with a sweep-reclaim breaker fallback; target = next external liquidity when it delivers >= 2R.
- **Note:** `docs/ICT_SMC_COVERAGE.md` records premium/discount and OTE as not implemented anywhere in this repo - this EA is the first implementation.
- **Gaps:** the breaker fallback inherits `SigSweepReclaim`'s bullish-first evaluation order, so a fresh bearish breaker can be masked by an older bullish sequence (the OB path is direction-locked, the fallback merely fires less often).
   - Swing structure now comes from the engine's 3-bar fractal rule (`SigFractals` for the breaker's engineered-liquidity check; the same rule applied to HTF bars for the dealing range), and the swept extreme must sit on a swing unless `InpRequireEngineeredLiquidity=false`.
- **Status:** passes `scripts/check_mql5_source.py` (0 findings); **not yet compiled**.
<!-- /edit:notes -->
