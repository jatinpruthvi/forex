# 42. Trading First Principles Framework

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `trading-first-principles-framework` |
| **Type** | video-only (Glimpse summary) |
| **Source** | [Glimpse summary](../glimpse/_wpg45NdMkM.md) · [summary PDF](../glimpse-pdf/_wpg45NdMkM.pdf) · [YouTube](https://www.youtube.com/watch?v=_wpg45NdMkM) (@chart-fanatics) |
| **Origin** | [chartfanatics.com/strategies/trading-first-principles-framework](https://www.chartfanatics.com/strategies/trading-first-principles-framework) · [Glimpse](https://glimpse.wozart.com/v/xhvdp2u1) |
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
- **Verdict:** Implemented as a trading EA carrying the document's own three strategies as the portfolio it tells you to build ("Advanced traders should combine 3+ strategies across different asset classes and timeframes"). **All three are stated mechanically, so all three are coded**: (A) *short-term momentum* - "measure volatility expansion - when price moves further than average - and enter", exit "after 2-5 days or when momentum disappears", daily bars; (B) *mean reversion* - "measure how far price deviates from a moving average (e.g., 5-day MA). When deviation exceeds normal range (e.g., 6-7% vs. 2% average), enter expecting reversion", exit "after 1-4 days or when price returns to mean"; (C) *trend following* - "identify strong support/resistance (e.g., 100-day or 200-day high). Enter on breakout; exit when price closes below a trailing moving average (e.g., 10-day MA)", with the document's "strongest edge when breaking all-time highs" bonus. **The portfolio rules are wired, not just mentioned**: three equal risk shares with one slot per approach; the monthly **rebalance** ("rebalance monthly or quarterly to lock in gains") is the percentage-of-equity reset at every entry - "forces you to buy low and sell high" - with the rebalance dates logged; the quarterly **edge-decay review** ("document your edge decay hypothesis ... schedule quarterly research reviews") is a logged date and a per-signal CSV carrying the cost in R; the **fee warning** ("fees can consume 50% or more of gross returns") is the engine's cost gate plus that log; "avoid shorting large-cap stocks" is the long-only list; "avoid overcrowded battlefields" and "holding time matters more than timeframe" are the daily-bar-only design.
- **Instruments:** `BTCUSD,ETHUSD` default - the document's matrix says crypto is "the least efficient, most volatile market ... all approaches, all timeframes", i.e. the best retail opportunity; the matrix is expressed through the universe input
- **Timeframe / session:** D1 signals, one decision per completed day, multi-day holds; no session flattening (the holds are the strategy)
- **EA file / magic:** [`EA_CF_TradingFirstPrinciplesFramework.mq5`](../mql5-eas/EA_CF_TradingFirstPrinciplesFramework.mq5) / `3242` (static-checked)
- **Priority:** P1 - the queue's framework/portfolio card
- **Blocked by:** _nothing_
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: the foundation (Dunning-Kruger, trading as pure capitalism, the compounding cost of fees),
  the playground (Sharpe ratio as the institutional metric, the liquidity/volatility trade-off, the
  timeframe/Sharpe relationship, expectancy growing with timeframe, avoiding overcrowded battlefields),
  edge decay (why all edges decay, the timeframe decay rate, continuous research), the three core
  approaches (breakouts / mean reversion / trend following, with the document's own examples and numbers),
  the asset-class strategy matrix (stocks, commodities, forex, crypto), trend following as the most robust
  approach, portfolio trading and rebalancing (the diversification-vs-portfolio example, rebalancing
  frequency, non-correlated strategies), the practical takeaways (maximize edge / minimize competition,
  holding time vs timeframe, tools are descriptive, start with trend following, scale through portfolio
  not leverage) and the action items.
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_TradingFirstPrinciplesFramework.mq5`
  (38 rules pinned).
- `[interpretation]`: the range normalisation behind "moves further than average" (its ATR-style window),
  the average-deviation window behind the "2% average", the breakout and stop buffers, the stop-width
  cap, the trend stop's ATR multiple (the document exits on the MA, not a stop), the all-time-high
  lookback, the rebalance and review periods and the far take-profit placeholder are inputs and labelled.
- Design notes: the three approaches are one EA with three slots and one shared risk share each - the
  "portfolio" the document describes, expressible inside an MQL5 EA without pretending to be a fund
  accounting system. The approach tag travels on a global variable from the plan to the filled ticket, so
  each position is managed by its own documented exit (the 2-5 day / momentum-gone rule, the 1-4 day /
  back-to-mean rule, the 10-day MA rule). Percentage-of-equity sizing is the mechanical rebalancing: every
  entry is sized off current equity at the base share, which is exactly "resetting to original allocation".
- Disclosed, not faked: the EA cannot detect an asset class, so the matrix rules ("avoid shorting large-cap
  stocks", "forex: trend and mean reversion only") are inputs and the universe, not secret heuristics; the
  Sharpe-ratio optimisation and the correlation maths of the document's portfolio example are process
  advice for the human, and the EA contributes the evidence (the per-signal CSV) rather than a fake
  optimisation.
<!-- /edit:notes -->
