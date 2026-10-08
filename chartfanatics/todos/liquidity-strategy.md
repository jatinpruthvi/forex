# 18. Liquidity Strategy

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `liquidity-strategy` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/liquidity-strategy.pdf) (37.7 MB) |
| **Origin** | [chartfanatics.com/strategies/liquidity-strategy](https://www.chartfanatics.com/strategies/liquidity-strategy) · [source PDF on Google Drive](https://drive.google.com/file/d/1gzE7bquOUDAxHktAs5KpBvfZuwrWdRyW/view?usp=sharing) |
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
- **Verdict:** Implemented as a strategy. The playbook is a complete method - the EA maps the respected liquidity levels on the **30-minute chart** (the document's own context chart: a fractal swing only qualifies once it has **moved price away** by an ATR multiple and **nothing has closed through it since** - a wick is a sweep, a close means the liquidity is already spent), merges **equal highs / equal lows** into one pool ("multiple lows sitting at the same level") and then waits for the trap: the level must have been **intact inside the lookback**, get **run** (the first breach, fresh), and price must **reject back inside** on the 5-minute chart - exactly the document's breakdown. The entry is a **market order at the level** ("market execution once the high/low is taken and the trap is confirmed"), honouring both "sell above the high, never below" and "entered right after the rejection", with the **stop covering the high/low that was just taken**. Targets are the **opposing resting pools** and the playbook's example - the equal-lows cluster - wins over a nearer single level; a **1R trade floor** keeps a trade from aiming nearer than its own stop, and when no pool is resting ahead there is **no trade** ("don't trade unless liquidity is built"). Management follows the document literally: the engine's R grid is switched off, **partials are taken only at liquidity targets**, the **stop never reaches break-even until a partial is taken**, it only ratchets after a **higher low / lower high** forms, and the **runner is aimed at the furthest pool**. The session is the document's own example (**New York open**); price action outside it is ignored.
- **Instruments:** the playbook says "fits any asset" (futures / forex / crypto); the breakdown is index-futures shaped - `InpSymbolsToTrade` (default `US100,US500`)
- **Timeframe / session:** M30 level chart, M5 execution; NY-open window `14:30-17:00` London (`09:30-12:00` ET), configurable
- **EA file / magic:** [`EA_CF_LiquidityStrategy.mq5`](../mql5-eas/EA_CF_LiquidityStrategy.mq5) / `3221` (static-checked)
- **Priority:** P1 - the family's cleanest "sweep and reverse" model, fully mechanical
- **Blocked by:** _nothing_ (the doc states no sizing rule, so the engine risk percent applies - disclosed)
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: playbook overview (price seeks liquidity; retail gets trapped; "buy below lows, sell above
  highs" only after structure has been respected and moved away); directional bias from resting liquidity;
  "don't trade unless liquidity is built"; the no-trade case after a big move; sell/buy setup rules 1-6
  (identify the respected level, wait for the run, confirmation/trap, execute at the level, stop over the
  taken level, target the opposing liquidity); execution notes (after the liquidity is taken, market
  execution, never refine entries); management (stop only after a higher low/lower high, no break-even
  without partials, partials only at liquidity, let trades run); the session-window rule; the pros/cons
  (patience, missed moves, "not every high/low has liquidity"); the trade breakdown (30m equal lows as the
  target, pre-NY swing high, the 5m run and rejection, the entry after the rejection, stop over the swing
  high, target the equal lows).
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_LiquidityStrategy.mq5` (36 rules pinned).
- `[interpretation]`: fractal strength, the ATR move-away distance, the equal-highs/lows cluster tolerance,
  trap freshness, the entry chase cap around the swept level, the stop buffer, the 1R trade floor, the 50%
  partial, and the NY-open window (the doc gives it as an example: "e.g. New York Open"). The document
  states no position-sizing rule.
- Engine reuse: `EA_TrackIndex`/`g_eaTrack` for entry, initial risk and partial state; `g_eaExec.ClosePartial`
  and `g_eaExec.Modify` for the doc's management; `EA_ApplyStagePolicy` for card #01. The engine's
  `partial1AtR`/`breakEvenAtR`/`trailAtR` are set to 0 because the playbook manages by liquidity, not by R.
- The playbook's "fractal - works on all timeframes" is honoured by exposure: `InpContextTf` (levels) and
  `cfg.signalTimeframe` (execution) are the two knobs.
<!-- /edit:notes -->
