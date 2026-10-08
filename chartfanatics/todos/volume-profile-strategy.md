# 47. Volume Profile Strategy

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `volume-profile-strategy` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/volume-profile-strategy.pdf) (34.7 MB) |
| **Origin** | [chartfanatics.com/strategies/volume-profile-strategy](https://www.chartfanatics.com/strategies/volume-profile-strategy) · [source PDF on Google Drive](https://drive.google.com/file/d/1HOLZzGKv-nRqTIXZorrdh5zdDHFBxGEY/view?usp=sharing) |
| **Board** | [`chartfanatics/TODO.md`](../TODO.md) |
| **Updated** | 2026-10-08 |

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
- **Verdict:** EA candidate. The standard four-level setup requires all three stated confluences on one closed signal candle: a profile edge, a contextual level, and a high-volume rejection wick closing in the trade direction. The distinct **Previous Day POC Retest** is treated as a named setup exception: after a prior breakout/trend day, the POC substitutes for the four daily context levels and need not independently coincide with an HVA/LVA edge. It still requires the high-volume rejection/sweep candle. That exception is disclosed because the playbook's named POC setup could otherwise conflict with its generic edge / mid-zone rules.
- **Instruments:** `US100,US500` default - the worked example is NQ futures and the method needs centralized volume data; tick-volume proxy disclosed, so no spot-FX default
- **Timeframe / session:** H1 default (4H also supported); overnight level window is configurable server time and is measured from closed M1 bars in `[start,end)`
- **EA file / magic:** [`EA_CF_VolumeProfileStrategy.mq5`](../mql5-eas/EA_CF_VolumeProfileStrategy.mq5) / `3247` (static-checked; MT5 compile/test still owed)
- **Priority:** P1 - the queue's volume-profile card
- **Blocked by:** Windows MT5 compile/Strategy Tester and human signoff
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
**Source read end to end** (8 pages; 2026-10-08): the volume-profile playbook - HVAs are "sticky" and LVAs "price tends to move quickly through", the four key daily levels, the three-element standard setup, weekly bias, both named setups, entry/stop/target recipe, volatility-based retest, mid-zone warning, worked NQ 1H example (PDH sweep, ONL target), pros/cons, and the centralized-volume requirement.

**Sync:** 53 rule-to-code checks in `tests/test_chartfanatics_sync.py` cover the stated rules, numbers and disclosed interpretations; each regex was checked against the updated EA. `tests/test_volume_profile_strategy.py` adds 12 focused logic regressions. The order-flow tools mentioned in passing (cumulative delta and absorption images) cannot be derived from MT5 and are not simulated.

**Implemented:** the standard three-part setup at one of ONH/ONL/PDH/PDL; session, visible-range and daily higher-timeframe profiles with both HVA/LVA boundary orientations; overnight levels from completed M1 bars on a half-open server-clock window; PDH/PDL from the last completed D1 bar; weekly reversal bias checked against the preceding `InpBiasWeeks` weekly profile/volume baseline; prior completed broker-D1 POC after a breakout/trend day; actual rejection-wick 50-80% retrace limit with finite expiry; structural stop beyond the signal wick or adverse-side HVN edge; next-shelf targets; and mid-zone refusal on the standard setup. The POC branch is the specifically disclosed named-setup exception to the generic edge requirement.

**Disclosed, not faked:** MT5 publishes tick volume, not exchange volume, so profiles distribute tick volume across each bar's price range. The PDF itself says the method is "not viable in decentralized markets like spot forex"; the EA quotes this and defaults to the index proxies of the worked NQ example. No centralized futures volume, cumulative delta, or absorption feed is fabricated.

**`[interpretation]`:** H1 default (4H supported); profile buckets/lookbacks and HVA/LVA thresholds; server overnight hours; edge tolerance; volume and wick thresholds; the stricter sweep-and-close shape applied to the worked example's generic key-level rejection; wick retrace measured from the candle body edge into the actual rejection wick (`InpRetraceFrac` 0.50-0.80); breakout/trend-day threshold for POC; stop buffer/cap; minimum target R, fallback target and trade caps. The POC branch substitutes the named prior-day POC for the generic contextual-level/edge confluences after a trend day; this is called out because the PDF's generic mid-zone rule and specific POC setup leave their precedence implicit.

**Independent bug audit (2026-10-08):** fixed the undersized/calendar-based POC history window (now anchored to the prior completed D1 bar, including weekend gaps); ONH/ONL using signal-frame bars and including the end-boundary bar (now closed M1 bars, `[start,end)`, so H4 works); inclusive-maximum profile bucket out-of-bounds / lookup errors; missing LVA→HVA edge orientation; HVN stop lookup on the favorable side and wrong edge; first-hit selection that let a swept non-edge level mask a later valid edge; retrace price measured through candle body instead of within the wick; weekly bias checked against an intraday profile instead of its own prior-W1 profile; optional uninitialized HTF profile; invalid zero lookback inputs; and stale, never-read terminal-global pending-slot writes. Also refuse a retrace order if its stop invalidation is already crossed. Each fix has a regression fence.

**Validation limits:** static checker and source tests can validate structure and deterministic logic, but MetaEditor and Strategy Tester are Windows-only and were not run here; backtest and forward/demo stages remain outstanding. The POC exception and sweep filter are explicit decisions, not claims that the PDF was unambiguous.
<!-- /edit:notes -->
