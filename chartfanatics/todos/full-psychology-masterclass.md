# 12. Full Psychology MasterClass

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `full-psychology-masterclass` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/full-psychology-masterclass.pdf) (38.3 MB) |
| **Origin** | [chartfanatics.com/strategies/full-psychology-masterclass](https://www.chartfanatics.com/strategies/full-psychology-masterclass) · [source PDF on Google Drive](https://drive.google.com/file/d/1hMBMScO06VtFBvHNLGNwoEHkm21eyz3Z/view?usp=sharing) |
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
- **Verdict:** Not a strategy - a psychology/process document (Jared Tendler). No entry, exit, stop, target, instrument or timeframe rule exists in it, so it becomes a process monitor, not an invented strategy. The EA replays the account's own day (every magic) through the masterclass's mental model: the progressive-shutdown ladder (1 loss -> caution "reduce activity", 2 -> the doc's 15-minute break, a trade inside the break -> "your session is over", 3 -> session over on emotional EV), the emotional-carryover shift after a red day, and mechanical proxies for the zone map's early-warning signs (revenge re-entry, size escalation, entry bursts, off-window entries). It writes the journal the doc calls "mental maintenance": pre-session check-in, a during note per warning with the 4-step reset protocol, and the post-session review with the day's own moments and the if-then plan slot (`cf_psych_journal.csv`).
- **Instruments:** n/a (monitors every magic on the account)
- **Timeframe / session:** EA: M15 scan loop, one replay per minute; US cash session window (London 14:25-21:00) as the reference "session"
- **EA file / magic:** [`EA_CF_PsychGuardrails.mq5`](../mql5-eas/EA_CF_PsychGuardrails.mq5) / `3216` (static-checked)
- **Priority:** P2 - the mental-risk half of the risk model
- **Blocked by:** _nothing_ (never compiled: MetaEditor run owed, see the Windows stage in [`../LOOP.md`](../LOOP.md))
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: the emotion-performance curve and the 60%-vs-100% idea (the ladder's graded steps);
  progressive shutdown; how emotional carryover affects the next day; working memory ("your desk
  shrinks"); the power of journaling / mental cool-down; the zone map's triggers, thoughts, physical
  clues and perception shifts; discipline problems are emotional problems; emotional EV ("sometimes
  the smartest trade is no trade at all"); how to reset mid-session (the 4-step protocol + "if you
  break your own limit, your session is over"); the before/during/after check-in structure; key
  takeaways ("journal daily to release built-up emotion").
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_PsychGuardrails.mq5` (21 rules pinned).
- `[interpretation]`: the doc is subjective, so loss counts stand in for "emotion rising" and the
  zone-map signs get event proxies; every threshold is an input and the day replay is deterministic.
<!-- /edit:notes -->
