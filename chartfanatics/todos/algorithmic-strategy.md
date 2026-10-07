# 03. Algorithmic Strategy

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `algorithmic-strategy` |
| **Type** | video-only (Glimpse summary) |
| **Source** | [Glimpse summary](../glimpse/TyHTEtArsS4.md) · [summary PDF](../glimpse-pdf/TyHTEtArsS4.pdf) · [YouTube](https://www.youtube.com/watch?v=TyHTEtArsS4) (@chart-fanatics) |
| **Origin** | [chartfanatics.com/strategies/algorithmic-strategy](https://www.chartfanatics.com/strategies/algorithmic-strategy) · [Glimpse](https://glimpse.wozart.com/v/ypeas563) |
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
- **Verdict:** **NOT a signal strategy.** The video teaches how to build and operate a portfolio of algorithms (rule complexity budget, robustness filters, position sizing, continuous monitoring). There is no entry/exit/stop/target to implement, so no entry rule is invented; the card delivers a **portfolio monitor EA** that applies the document's own ranking filters to live deal history (profit factor >= 1.5, return/DD >= 4:1, >= 2 trades/month, average loss <= 0.5%, implied allocation inside 5-25%, drawdown past 20-25% flagged, expectancy from win rate and reward:risk).
  `[interpretation]`: Sharpe / UPI are not computable from deal history alone, so the return/DD ratio the same page quotes is reported instead. The robustness checks the video teaches live in the repo pipeline, not in the EA: in-/out-of-sample splits + multi-market sweeps = `validation/mt5_harness`, parameter sensitivity = the ablation scaffold, Monte Carlo reshuffle = not implemented (noted as a gap).
- **Instruments:** n/a (portfolio-wide monitor; the document's subject is the portfolio, not one market)
- **Timeframe / session:** n/a (re-scans the account's deal history every 240 minutes; 90-day window by default)
- **EA file / magic:** [`EA_CF_AlgoPortfolioMonitor.mq5`](../mql5-eas/EA_CF_AlgoPortfolioMonitor.mq5) / `3209` (monitor, never trades; static-checked)
- **Priority:** P2 - the ranking journal is useful the moment several EAs trade a live account
- **Blocked by:** _nothing_ (never compiled: MetaEditor run owed, see the Windows stage in [`../LOOP.md`](../LOOP.md))
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
_Nothing yet._
<!-- /edit:notes -->
