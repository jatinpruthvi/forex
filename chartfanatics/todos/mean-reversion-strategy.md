# 22. Mean Reversion Strategy

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `mean-reversion-strategy` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/mean-reversion-strategy.pdf) (10.1 MB) |
| **Origin** | [chartfanatics.com/strategies/mean-reversion-strategy](https://www.chartfanatics.com/strategies/mean-reversion-strategy) · [source PDF on Google Drive](https://drive.google.com/file/d/1xQizDu1gKelJOsExAN9UPlwqpi9uO4Jv/view?usp=sharing) |
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
- **Verdict:** Implemented as a strategy. The EA starts from the document's own premise - mean reversion needs an **abnormal** move - and checks the **daily context first** (today's expansion against the 20-day normal range, a volume spike, and the displacement measured in daily ATRs), then the **intraday speed** (the playbook's "one of the most important factors"): the displacement must travel far in a short window with **consecutive bars in one direction**, or print a single **panic candle** (the doc's rare extremely-fast case). The entry is always the **right side of the move** ("trading the right side of the reversal"): the **break of the prior bar's high** after a down-leg (the prior bar's low after an up-leg), as in the OCLR example. The **stop** sits below the capitulation low / above the capitulation high, the risk must stay clearly defined (a cap), and the **target is the 20-period mean** - the doc's equilibrium reference, the centre of the Bollinger Bands - with realistic R fallbacks because "the first bounce often retraces part of the move". Management **trails the stop below prior bar lows** (above prior bar highs for shorts), setup **quality drives size** (the more of the doc's favourable variables, the larger; fewer than three, no trade - "lower quality setups may be traded smaller or avoided entirely"), **shorts are sized smaller** (the document's structural asymmetry) and **panic entries are sized smaller** ("the risk is less clearly defined"). The doc's "news vs fundamental change" caution cannot be decided by an EA - it is disclosed and the engine's calendar gate is an optional input.
- **Instruments:** stocks (the examples are OCLR and similar large-caps) - `InpSymbolsToTrade` (default `AAPL,MSFT,NVDA`; set your own universe)
- **Timeframe / session:** D1 context + M5 execution; US cash session (`14:30-21:00` London), 2 trades/day cap
- **EA file / magic:** [`EA_CF_MeanReversion.mq5`](../mql5-eas/EA_CF_MeanReversion.mq5) / `3225` (static-checked)
- **Priority:** P1 - the family's only capitulation/reversal model with explicit quality-based sizing
- **Blocked by:** _nothing_; "news vs fundamental" cannot be classified by an EA (disclosed)
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: overview (efficiency, dislocations, trading the reversion after capitulation); expected value
  (win rate x reward - loss probability x risk); the conditions (size, speed, news vs fundamental change,
  consecutive bars/days, forced buying/selling, sentiment extreme, stability and market structure, quantifiable
  vs non-quantifiable assets, long/short structural asymmetry); the ideal setup (calm asset, sudden extreme move:
  acceleration, large candles, high volume, far from MAs); volume and capitulation (daily + intraday charts);
  entry concept (right side of the move; break of the prior bar high/low; extreme panic reversal; trend structure
  shift); stop placement (capitulation low, reversal structure failure, broken higher lows); profit target (the
  20-period MA / Bollinger centre; realism); trade management (trail below prior bar lows / above prior highs);
  finding opportunities (Bollinger extremes, multi-day runs, expansions, volume); evaluating trade quality
  (favourable variables, size scaling); common mistakes (buying early, unrealistic targets, slow trends, ignoring
  context); the OCLR example (three phases, volatility expansion, entry on the break, stop at the capitulation
  low, target near the 20-MA, prior-bar trail).
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_MeanReversion.mq5` (26 rules pinned).
- `[interpretation]`: the expansion/volume/displacement multiples, the speed window and travel, the streak
  length, the panic-candle size, the risk cap, the execution timeframe and the daily trade cap. The doc gives
  no parameter values.
- Bug found in self-review: the down-leg travel was signed backwards (a down-leg must measure a POSITIVE
  distance); fixed, and the panic-candle path was dead code until the second qualification path was added.
- Engine reuse: the context EMA (the 20-period mean), `EA_BodyRatio`-style bar facts, `g_eaExec.Modify` for the
  trail, `cfg.partial1AtR`, `cfg.newsFilter` (optional), `EA_ApplyStagePolicy`.
<!-- /edit:notes -->
