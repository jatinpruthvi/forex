# 04. AMD Model

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `amd-model` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/amd-model.pdf) (25.8 MB) |
| **Origin** | [chartfanatics.com/strategies/amd-model](https://www.chartfanatics.com/strategies/amd-model) · [source PDF on Google Drive](https://drive.google.com/file/d/15W9VMBk3v1yDTQcKrmyePoRAUJMNLqkb/view?usp=sharing) |
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
- **Verdict:** Tradable, implemented. Accumulation range -> manipulation sweep -> confirmed displacement, entering the retrace into the imbalance. EA takes the distribution leg only, in the two macro windows the playbook names.
  `[interpretation]`: related-market alignment = same side of each symbol's PD midpoint; target = opposite side of the accumulation range (the worked example) else the nearest clean swing.
- **Instruments:** Futures (playbook). EA: US100 / US500 / GER40 (`InpSymbolsToTrade`)
- **Timeframe / session:** Playbook: 1H / 4H / Daily for the draw on liquidity, 1m / 5m / 15m for displacement and entries; New York session after the news. EA: M5 signal, NY windows 14:50-15:10 and 15:50-16:10 London, max 2 trades/day
- **EA file / magic:** [`EA_CF_AMD_Model.mq5](../mql5-eas/EA_CF_AMD_Model.mq5) / `3201` (static-checked)
- **Priority:** P1 - the two-trade day lock and the news-day concept are the cleanest risk rules in the set
- **Blocked by:** _nothing_
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
### EA implemented 2026-10-07
- **Source read:** `pdf/amd-model.pdf` (8 pp, Tanja Trades) - accumulation / manipulation / distribution, entry only on the retrace into the imbalance.
- **EA:** [`mql5-eas/EA_CF_AMD_Model.mq5`](../mql5-eas/EA_CF_AMD_Model.mq5), magic `3201`, M5.
- **Encoded:** accumulation window 00:00-14:30 London; sweep -> reclaim -> displacement via `SigSweepReclaim`; retracement limit entry; macro windows 09:50-10:10 / 10:50-11:10 ET enforced; 2 trades/day; two-loss day lock; D1+H1 cascade gate ("if the higher timeframe is unclear, do not force a setup").
- **Gaps:** the "high probability day" news filter (CPI/NFP/FOMC days) is a calendar decision and is OFF - the playbook trades the *post-news* move, so blocking news windows would veto its best setups. Scale-down on pre-news days is not implemented.
   - Uses `EA_InWindow` for both macro windows (engine helper, midnight-crossing safe) and `SigEmaCascade` for the HTF clarity gate; the engine cost gate (`maxCostR`) and evidence ledger are on.
- **Status:** passes `scripts/check_mql5_source.py` (0 findings); **not yet compiled** - run `validation/mt5_harness/compile_all.ps1`, then a tester sweep.
<!-- /edit:notes -->
