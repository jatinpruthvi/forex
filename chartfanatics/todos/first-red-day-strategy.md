# 11. First Red Day Strategy

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `first-red-day-strategy` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/first-red-day-strategy.pdf) (4.3 MB) |
| **Origin** | [chartfanatics.com/strategies/first-red-day-strategy](https://www.chartfanatics.com/strategies/first-red-day-strategy) · [source PDF on Google Drive](https://drive.google.com/file/d/1DAIyyF03kubJ0TjXTzf4Uzk0SXLzNyfk/view?usp=sharing) |
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
- **Verdict:** Tradable, implemented. Short-only FRD with the playbook's non-negotiable minimum criteria hard-gated: 2-3+ consecutive green days with no red inside the run, 80-100%+ extension, expanding volume, expanding range. The previous day's close is the trigger; all three documented entry methods are implemented and selectable (pre-red stall, standard crack below the prior close, lower-high after a failed bounce), with the source's own risk level per method (ATH of the run / today's HOD / bounce high). The overextended gap-down rule (never short already down 10%+) and the 3-5 attempts cap are enforced; VWAP is the primary magnet target with the "larger assets 2-3%" fallback; exits scale out into weakness and can trail the 15-minute high.
- **Instruments:** Stocks / Options (source: small-cap euphoric runners). EA: `InpSymbolsToTrade` (the run quality is the selection filter)
- **Timeframe / session:** Playbook: daily run, intraday short. EA: D1 run detection, M5 trigger, 15-min trail, US cash session
- **EA file / magic:** [`EA_CF_FirstRedDayPro.mq5](../mql5-eas/EA_CF_FirstRedDayPro.mq5) / `3215` (static-checked)
- **Priority:** P2 - the fuller FRD spec (superset of card #10's variant)
- **Blocked by:** _nothing_ (never compiled: MetaEditor run owed, see the Windows stage in [`../LOOP.md`](../LOOP.md))
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Rule refs: p.1-2 minimum criteria + why multiple green days matter; p.2 previous day's close as the
  psychological trigger; p.3 the three entry methods; p.4 exits (VWAP magnet, scale out, 15-min trail);
  p.5 overextended gap-down variation; p.6 maximum-attempts rule and risk management (primary stop =
  ATH of the run); p.7-8 BYND A+ trade breakdown (1,400% extension example).
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_FirstRedDayPro.mq5` (20 rules pinned).
- `[interpretation]`: VWAP from session M5 bars (tick volume proxy); "2-3%" fallback for larger
  assets where VWAP gives no >= 1R magnet; single-stock catalyst selection is the user's universe.
<!-- /edit:notes -->
