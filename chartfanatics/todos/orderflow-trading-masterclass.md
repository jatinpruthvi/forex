# 29. OrderFlow Trading Masterclass

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `orderflow-trading-masterclass` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/orderflow-trading-masterclass.pdf) (16.9 MB) |
| **Origin** | [chartfanatics.com/strategies/orderflow-trading-masterclass](https://www.chartfanatics.com/strategies/orderflow-trading-masterclass) · [source PDF on Google Drive](https://drive.google.com/file/d/1L-Kl266O9N5D3f7FZoQm6CoATANtGyOr/view?usp=sharing) |
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
- **Verdict:** Implemented as a full EA - the document is mechanizable and hands over two worked setups. Its closing framework is the EA's three gates: **Context** (a real push must exist: an impulse move or an aggressive volume bar - `ImpulseContext`), **Location** (a documented level: previous day high/low, the session extreme, a value-area edge / POC from the tick-volume profile, or a level the session has already **tested and held several times** - `CollectLevels` / `TouchCount`, the honest proxy for the document's DOM/heatmap "liquidity wall"), and **Confirmation** (`AbsorptionAt`: heavy volume, no progress beyond the level, a rejection wick, the **delta-divergence proxy** - the aggressive side keeps leaning in while price stalls - and the newer bar that flips control; plus the reclaim for the stop run). The two setups: the **stop run and reclaim** (a flush through the level, entry on the reclaim close, "a stop just below the low of the flush") and the **absorption fade** at a level that held ("aggressive buyers trapped into resistance while passive sellers absorb and take over"). The target is the rotation to the session's far extreme with a minimum R floor. DOM, heatmap and footprint charts do not exist in MT5, so aggression is body-directional tick volume and the wall is a repeatedly-tested level - all labelled; the document states no stop size, target rule, sizing ladder or session window, so those are exposed as inputs.
- **Instruments:** `US100,US500` ("Futures" per the playbook)
- **Timeframe / session:** M5; the regular session 14:30-20:30 London (09:30-15:30 ET) - the case studies' own context, labelled
- **EA file / magic:** [`EA_CF_OrderflowTradingMasterclass.mq5`](../mql5-eas/EA_CF_OrderflowTradingMasterclass.mq5) / `3232` (static-checked)
- **Priority:** P1 - the second order-flow card of the queue
- **Blocked by:** _nothing_
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: understanding order flow (limit vs market orders, why price moves, what candles represent,
  why support and resistance form), the three core signals (absorption, liquidity walls, stop runs), reading
  delta and the volume profile (delta divergence included), the tools (DOM, heatmap, footprint chart), both
  case studies (absorption short at resistance around the 111-contract wall at 5710 with 70-80 contract
  lifts; the stop run and reclaim long below the previous day's low, entry ~5844 with the stop below the
  flush low, and the level that had held four or five times), and the closing Context / Location /
  Confirmation framework.
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_OrderflowTradingMasterclass.mq5`
  (20 rules pinned).
- `[interpretation]`: the push size (0.80 ATR) and its volume multiple (1.30x), the touch tolerance
  (0.15 ATR), the minimum touches (2) and the strong-touch count (4 - the case study's own "four or five
  times"), the absorption volume multiple (2.0x), the allowed progress beyond the level (0.25 ATR), the
  rejection-wick share (0.35), the test window (3 bars), the delta bars (12) and the lean cut (0.10), the
  flush minimum (0.15 ATR), the reclaim window (3 bars), the stop buffers, the minimum R (1.50), the
  value-area split (70%) and the session window are engineering numbers the document does not state - all
  exposed as inputs and labelled in the source.
- Disclosed, not faked: the DOM, heatmap and footprint chart (resting limit orders, order-book depth,
  bid-vs-ask executed volume) have no MT5 signal; "liquidity wall" is therefore read as a repeatedly
  tested level plus a high-volume profile node, and "delta" as body-directional tick volume. The
  document's platform/tool setup and the trader's discretionary reading of "how quickly liquidity is
  taken or replenished" stay human.
- Design note: the engine's partial / break-even / trail are off because the document states no
  management rules - the plan's target is the exit, as the case studies trade; the stop is always
  structural (beyond the flush or test extreme) and the level list is deduplicated and capped so a noisy
  session cannot flood the scan.
<!-- /edit:notes -->
