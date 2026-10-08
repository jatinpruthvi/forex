# 10. First Red Day

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `first-red-day` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/first-red-day.pdf) (29.8 MB) |
| **Origin** | [chartfanatics.com/strategies/first-red-day](https://www.chartfanatics.com/strategies/first-red-day) · [source PDF on Google Drive](https://drive.google.com/file/d/18PPp_AwpnMfnJLgnxzRT4GfaRj3Qfv6n/view?usp=sharing) |
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
- **Verdict:** Tradable, implemented. Short-only: a 3+ day green run (each day higher, ideally stronger, total move >= 25%) ends, the previous day's close is the red-to-green line, and the entry is the first close below that line - both documented paths (gap-up fade, gap-down bounce failure) - with the stop just above the line (a reclaim cuts it) and portions covered into the weakness with a runner kept.
- **Instruments:** Stocks / Options (source). EA: `InpSymbolsToTrade` (the run's quality is the selection filter)
- **Timeframe / session:** Playbook: multi-day run on the daily; entry intraday on the first red day. EA: D1 run detection, M5 trigger, US cash session
- **EA file / magic:** [`EA_CF_FirstRedDay.mq5](../mql5-eas/EA_CF_FirstRedDay.mq5) / `3214` (static-checked)
- **Priority:** P2 - crisp rule set, short side diversifies the book
- **Blocked by:** _nothing_ (never compiled: MetaEditor run owed, see the Windows stage in [`../LOOP.md`](../LOOP.md))
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
_Nothing yet._
<!-- /edit:notes -->
