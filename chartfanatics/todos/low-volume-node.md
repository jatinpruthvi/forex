# 19. Low Volume Node

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `low-volume-node` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/low-volume-node.pdf) (3.9 MB) |
| **Origin** | [chartfanatics.com/strategies/low-volume-node](https://www.chartfanatics.com/strategies/low-volume-node) · [source PDF on Google Drive](https://drive.google.com/file/d/1f7Ku7vhsDKGzhxq6dvyuAg9mIWoPDgDY/view?usp=sharing) |
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
- **Verdict:** Implemented as a strategy. The playbook's sequence is fully mechanical except its order-flow confirmation, which is disclosed. The EA finds the **level of interest** as the document defines it - a **consolidation** (a tight base) followed by an **impulsive move away** that confirms strong participants - then profiles the base+leg with **tick-volume bins** and keeps the **thin bins** as the **LVN zone** ("an LVN doesn't have to be a single exact price - it can be treated as a zone"), on the impulse side of the base (demand nodes above the base, supply nodes below). Entry waits for the **revisit** and the document's **defense**: nothing closes through the node, the newest bar wicks into it and closes back inside ("each time the price broke a low, it was quickly bought back"), on **above-average participation**. The stop is **tight, just beyond the node / revisit extreme** (hard cap: setups needing more are skipped - the doc's "tight stop" framing), sizing is the stop-distance-based risk the playbook asks for ("keep dollar risk the same"), the entry is taken **at the node** (never after a run away), and the target comes from the document's own list - **high/low of day**, **another supply/demand level** (read as the prior day's extreme), **another LVN** - behind a 2R floor ("aim for a high reward-to-risk setup"), with a **1R scale-out** and the runner left for the objective. A premise exit closes the trade when a bar closes through the node. **Disclosed:** the playbook confirms with heatmaps, footprint charts and delta - no MT5 EA can read those, so the defense is a bar/tick-volume **proxy**, labelled `[interpretation]` in the source.
- **Instruments:** index futures (the example is ES at 5563); playbook says day trading / scalping - `InpSymbolsToTrade` (default `US500,US100`)
- **Timeframe / session:** M5 execution; New York session `14:30-21:00` London (`09:30-16:00` ET), configurable
- **EA file / magic:** [`EA_CF_LowVolumeNode.mq5`](../mql5-eas/EA_CF_LowVolumeNode.mq5) / `3222` (static-checked)
- **Priority:** P1 - a clean mechanical read of an order-flow playbook
- **Blocked by:** _nothing_; heatmap/footprint confirmation is not codeable (documented proxy)
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: overview (impulsive moves through low volume; later revisits so institutions reload/defend;
  LVN forms after a reaction from a supply/demand/support/resistance level; confirmation tools); criteria
  (identify the level - consolidation then impulse; wait for the pullback; identify the LVN with volume-by-price
  and treat it as a zone; wait for the revisit; look for confirmation - heatmaps/footprint/delta; enter long off
  demand or short off supply; stop just above/below the LVN or recent low/high; size from the stop distance;
  targets - high/low of day, another supply/demand zone, another LVN, S/R; scale out or take full profits);
  risk management (define dollar risk first, size by stop, accept losses); pros/cons; the trade breakdown
  (demand zone, two LVNs at 5563 / 5550s, the pullback into 5563, passive buyers holding, absorption, sellers
  trapped, entry 5561, tight stop below the zone, target the high of day).
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_LowVolumeNode.mq5` (27 rules pinned).
- `[interpretation]`: the base/impulse windows, the thin-bin fraction (50% of the average bin), the revisit
  window, the participation multiple, the stop buffer and cap, the 2R floor, the daily trade cap and the
  entry chase tolerance. The document states no parameter values.
- Engine reuse: `SigRangeForDay` (session extreme), the engine risk sizing (`cfg.riskPct`), `cfg.partial1AtR`
  scale-out, `g_eaExec.Close` premise exit, `EA_ApplyStagePolicy`. The volume profile is built locally from
  tick volume - the same proxy the library's volume-profile EAs (#05/#06) use.
<!-- /edit:notes -->
