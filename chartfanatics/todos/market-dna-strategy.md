# 21. Market DNA Strategy

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `market-dna-strategy` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/market-dna-strategy.pdf) (30.9 MB) |
| **Origin** | [chartfanatics.com/strategies/market-dna-strategy](https://www.chartfanatics.com/strategies/market-dna-strategy) · [source PDF on Google Drive](https://drive.google.com/file/d/1EkMOI5gtVuYQJ0VLbUauixuL5DW4lqqI/view?usp=sharing) |
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
- **Verdict:** Implemented as a strategy, with its order-flow core disclosed as a proxy. The document's **DNA points** are zones that previously created huge directional moves ("20-30% swings, or areas where momentum exploded") and are treated as **ranges, not lines** - the EA finds them as H1 bases that produced a >= 2.5 ATR displacement, keeps them as zones, and drops any level that has since been **closed through** ("never let a trade run past the DNA zone once invalidated"). The **setup** is the document's "aggression overwhelms absorption": a displacement bar (strong body, above-average participation) that tests the zone and **closes out of it** - the passive wall failing - entered **as close as possible to the level** (no chasing), with the **stop just beyond the zone** and a cap that enforces "risk is reduced ... by minimizing stop distance". Targets honour the **3:1 minimum**, partials are taken into the first reaction, the **remainder rides until aggression flips** (an opposing displacement close), and the stop **trails behind newly formed structure**. Market selection follows the doc: a **relative-volume catalyst** requirement ("news or earnings push participants into the market"), a **flat/range-bound session gate**, and the **instrument rule** - stocks and futures only, forex deliberately not traded (the EA logs this). **Disclosed and labelled:** tape/Level II cannot be read by an MT5 EA, so aggression/absorption are bar-and-tick-volume proxies (the same family of proxies as the library's other order-flow cards); the catalyst is relative volume, optionally combined with the engine's calendar gate.
- **Instruments:** large-cap stocks and futures (NQ/ES) - `InpSymbolsToTrade` (default `US100,US500`); forex deliberately excluded per the doc
- **Timeframe / session:** H1 DNA structure, M5 execution; US cash session (`14:30-21:00` London), 2 trades/day cap
- **EA file / magic:** [`EA_CF_MarketDna.mq5`](../mql5-eas/EA_CF_MarketDna.mq5) / `3224` (static-checked)
- **Priority:** P1 - the family's flagship tape-reading model, and the one with the tightest risk framing
- **Blocked by:** _nothing_; true tape/Level II reads are not possible in MT5 (documented proxy)
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: overview (buyers/sellers move price; tape, Level II and liquidity zones; stocks/options/futures,
  not forex); instrument selection (large caps with catalysts; NQ/ES; avoid forex); DNA points (zones of prior
  huge moves, momentum explosions, ranges not lines); aggressive vs passive players (walls absorbing flow,
  aggression overwhelming absorption); catalyst confirmation (earnings/news -> aggression -> absorption at a
  level -> explosive move); tight risk windows (enter where control flips; stop just beyond the zone);
  market-selection rules (high-volume stocks in catalysts, futures in macro sessions, no flat/range-bound
  trades); long/short entry rules; exit rules (partials into the first reaction, the remainder until
  aggression flips, trail stops behind new aggressive zones); risk management (3:1 minimum, most 4-5:1,
  never past an invalidated zone, risk reduced by a minimal stop distance); pros/cons; the breakdown
  (NVDA earnings, prior demand zone, repeated lifting of offers, entry at the zone, stop below the zone,
  partials at intraday reactions).
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_MarketDna.mq5` (28 rules pinned).
- `[interpretation]`: the DNA timeframe and move multiple, the zone width cap, the body/volume thresholds for
  aggression, the chase cap, the stop buffer and the tight-risk cap, the fractal trail, the catalyst multiple,
  the flat-session threshold and the daily trade cap. Tape/Level II is not readable by an EA.
- Engine reuse: `EA_BodyRatio`, `SigRangeForDay`, `cfg.newsFilter`, `EA_TrackIndex`/`g_eaTrack`, `g_eaExec.Close`
  and `Modify`, `cfg.partial1AtR`, `EA_ApplyStagePolicy`.
<!-- /edit:notes -->
