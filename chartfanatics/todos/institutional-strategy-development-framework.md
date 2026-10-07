# 15. Institutional Strategy Development Framework

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `institutional-strategy-development-framework` |
| **Type** | video-only (Glimpse summary) |
| **Source** | [Glimpse summary](../glimpse/yW6c0K8uGvw.md) · [summary PDF](../glimpse-pdf/yW6c0K8uGvw.pdf) · [YouTube](https://www.youtube.com/watch?v=yW6c0K8uGvw) (@chart-fanatics) |
| **Origin** | [chartfanatics.com/strategies/institutional-strategy-development-framework](https://www.chartfanatics.com/strategies/institutional-strategy-development-framework) · [Glimpse](https://glimpse.wozart.com/v/onfkdxi8) |
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
- **Verdict:** Implemented as a strategy set plus the framework's own machinery. The document is a pipeline (research -> exact rules -> code -> validate -> automate) with four example strategies; three are codeable and run as modes - ORB (long-only break of the 9:30-10:00 range, stop at the range low, 1:1/1:2 target, 3:30 p.m. time exit), VWOP momentum (1-minute close above/below the volume-weighted price, exit on the cross, both anchors the doc says to test), overnight gap premium (long at 4 p.m., exit 9:30 a.m., optional combined ORB filter). PEAD (Strategy 3) is **not implemented and disclosed as data-blocked**: it needs actual-vs-estimate earnings and an earnings calendar, which no MT5 EA can read. The framework rules themselves are implemented: volatility targeting (constant dollar risk via `LotsMultiplier`), the validated-drawdown pause ("red flag to pause the strategy"), and an account-wide monthly review CSV that names underperformers. The 80/20 split and Monte Carlo steps are research-time work (validation harness), carried into live trading as that pause threshold.
- **Instruments:** QQQ / ES / NQ / crude / single stocks (source). EA: `InpSymbolsToTrade`
- **Timeframe / session:** M1 execution; per-mode windows (US cash session for ORB/VWOP, the 4 p.m.-9:30 a.m. wrap for overnight)
- **EA file / magic:** [`EA_CF_InstFramework.mq5`](../mql5-eas/EA_CF_InstFramework.mq5) / `3219` (static-checked)
- **Priority:** P2 - the pipeline itself, and the only card whose deliverable includes its own review process
- **Blocked by:** _nothing_ for ORB/VWOP/overnight; **PEAD blocked by data** (earnings estimates + calendar; documented)
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: retail vs institutional; the five-step pipeline; the three essential components; 80/20
  in-sample/out-of-sample; Monte Carlo reshuffle; Monte Carlo bootstrap (10k-20k paths); validation
  metrics during live trading (the pause rule); SSRN sourcing; "extract the why"; Strategy 1 ORB
  (finding, why, entry/exit/sizing, long-only evidence); Strategy 2 VWOP; Strategy 3 PEAD (60-day
  drift, 1-2% sizing, why the short side is weaker); Strategy 4 overnight gap premium (90% of index
  returns, overnight risk premium, NQ 2015+); encoding iteratively; running 3-4 uncorrelated
  strategies; monthly review; volatility targeting ($10,000/1 contract vs 10 contracts example).
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_InstFramework.mq5` (27 rules pinned).
- `[interpretation]`: ORB target 1:1 vs 1:2 -> input; overnight entry tolerance; the ORB filter for
  the combined variation; the month-window drawdown definition; Friday-overnight skip (weekend risk
  the doc never asks for).
- Checker fix: this card's `else if(...)` chain exposed a false positive in the duplicate-member rule
  (control flow read as a member declaration); fixed in `scripts/check_mql5_source.py` with a
  regression in `tests/test_compile_class_guards.py`.
<!-- /edit:notes -->
