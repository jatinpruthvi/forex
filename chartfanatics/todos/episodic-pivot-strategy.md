# 08. Episodic Pivot Strategy

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `episodic-pivot-strategy` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/episodic-pivot-strategy.pdf) (26.4 MB) |
| **Origin** | [chartfanatics.com/strategies/episodic-pivot-strategy](https://www.chartfanatics.com/strategies/episodic-pivot-strategy) · [source PDF on Google Drive](https://drive.google.com/file/d/1Ez_YFt3U4KyrIZmcxrPfvnNj_4tsI-63/view?usp=sharing) |
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
- **Verdict:** Tradable, implemented (3 mechanical setups). A neglected instrument + a catalyst's footprint (outsized gap/move on abnormal volume) + the repricing entry: day-1 opening-range break with strength (stop below the OR low), EP 9M (>= 9M shares far above normal volume with a clear intraday trend), and delayed reaction both ways (post-catalyst tight-range breakout; negative-catalyst bounce failure). Management is the trade breakdown's own: break-even once the trade works, then the stop trails under the daily lows, exiting when the trend breaks.
- **Instruments:** Stocks (source). EA: any broker instrument in `InpSymbolsToTrade` - the symbol list IS the catalyst universe (documented)
- **Timeframe / session:** Playbook: catalyst day + day-1 entries near the open; swings of 10-20+ days. EA: M5 signals, D1 catalyst/neglect/trail, US cash session entries
- **EA file / magic:** [`EA_CF_EpisodicPivot.mq5](../mql5-eas/EA_CF_EpisodicPivot.mq5) / `3212` (static-checked)
- **Priority:** P2 - the daily-low trail is the distinctive piece; needs the broker's volume data to be meaningful
- **Blocked by:** _nothing_ (never compiled: MetaEditor run owed, see the Windows stage in [`../LOOP.md`](../LOOP.md))
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
_Nothing yet._
<!-- /edit:notes -->
