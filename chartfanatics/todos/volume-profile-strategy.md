# 47. Volume Profile Strategy

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `volume-profile-strategy` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/volume-profile-strategy.pdf) (34.7 MB) |
| **Origin** | [chartfanatics.com/strategies/volume-profile-strategy](https://www.chartfanatics.com/strategies/volume-profile-strategy) · [source PDF on Google Drive](https://drive.google.com/file/d/1HOLZzGKv-nRqTIXZorrdh5zdDHFBxGEY/view?usp=sharing) |
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
- **Verdict:** Implemented as a trading EA - the document is a discretionary-looking playbook, but it names its own confluences, so the EA requires all three of them on the same candle: "Price is touching a volume profile edge (transition from HVA to LVA or vice versa)", "The location aligns with a key contextual level (ONH/ONL/PDH/PDL)" and "A high volume signal candle forms with a visible wick rejecting the area and closing in the trade direction".  **The profiles** are built from tick volume spread evenly across each bar's range - MT5 publishes tick volume, not exchange volume, which is stated in the header and is also the document's own reason for its universe ("Requires Volume Data: Not viable in decentralized markets like spot forex"), so the default symbols are the index proxies of the worked NQ example.  A session profile, a visible-range profile and a higher-timeframe (daily) profile all feed the HVAs (`InpHvnFactor` x average), the LVAs (`InpLvaFactor` x average) and the **shelves** where one becomes the other, and "higher timeframes (Weekly, Daily) are used to identify long-term value areas and edges" is honoured by testing the level against each profile's own nearest edges.  **The four key daily levels** are exactly the document's: prior day high/low off the last completed daily bar and the overnight high/low off the server window between `InpOnStartHour` and `InpOnEndHour` (the window is allowed to cross midnight, as it does on every real broker clock).  **The signal candle** is tested on the last closed bar only (`signalOnNewBarOnly`, because "always wait for the signal candle to close.  Do not front-run it; even the last few minutes of a candle can change everything"), and it must sweep a level intrabar and close back on-side - the worked example's own shape, "trades above PDH intrabar (sweep), closes back below PDH" - while printing volume at `InpVolFactor` x the 20-bar average, carrying a rejection wick of `InpWickFrac` of its range and a real body.  **The weekly bias** is the document's reversal candle - "if the Weekly chart closes with a high volume bottom-wick reversal candle at a volume edge, then the bias is long" - and when it exists it is a hard filter ("All intraday setups should then favour long trades"), with the daily range structure available as an optional softer gate.  **Both named setups** are coded: the **Previous Day POC Retest** ("after a breakout or trend day, the price often returns to the prior day's POC before resuming the trend ... look for a signal candle at the prior day's POC and target a new high/low") and the **Volatility-Based Retest Entry** ("if the signal candle has a long wick -> expect a 50-80% wick retrace before continuation ... set a limit order in that retrace zone"), which rests at `InpRetraceFrac` of the wick and expires after `InpLimitBars` bars through the engine's limit mode.  **Stops** sit "just beyond the signal candle's wick or beyond the edge of the high value node" (whichever is further, plus `InpStopBufferAtr`), **targets** are "the next shelf - edge-to-edge targeting" via `NextShelf`, or the prior-day extreme for the POC setup, with `InpTargetR` as the fallback and `InpMinTargetR` as the floor.  **"Avoid entries in the middle"** is enforced structurally: every non-POC level must sit at a volume edge, and a stop wider than `InpMaxStopPct` is refused as a sign the edge is not an edge.
- **Instruments:** `US100,US500` default - the worked example is NQ futures and the method needs centralized volume data, so the universe is an input
- **Timeframe / session:** H1 default - "execution timeframes: 4H and 1H are the main chart timeframes used for identifying signal candles and taking trades", so the signal frame is an input; the overnight window's clock hours are inputs because the document names the level but not its hour
- **EA file / magic:** [`EA_CF_VolumeProfileStrategy.mq5`](../mql5-eas/EA_CF_VolumeProfileStrategy.mq5) / `3247` (static-checked)
- **Priority:** P1 - the queue's volume-profile card
- **Blocked by:** _nothing_
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
**Source read end to end** (8 pages / 7,192 characters, 2026-10-07): the volume-profile playbook - HVAs are "sticky" and LVAs "price tends to move quickly through", the four key daily levels, the three-element setup, the weekly bias, the two named setups, the entry/stop/target recipe, the volatility-based retrace and the mid-zone warning, the document's own worked NQ example on 1H (PDH sweep, ONL target) and its pros/cons - including the volume-data requirement that limits the universe.

**Sync:** 41 rules in `tests/test_chartfanatics_sync.py` map each stated rule and number to the exact code line that implements it (the file is the source of truth; every pattern is matched against the real source, including the disclosed tick-volume proxy and the quoted universe caveat).  Nothing in the document is silently dropped; the rules the EA deliberately does not mechanize are below.

**Implemented:** the four key daily levels (PDH/PDL from the completed daily bar, ONH/ONL from the configurable overnight window); session, visible-range and higher-timeframe profiles with HVA/LVA thresholds and shelf detection; the three-element setup (volume edge + key level + high-volume wick candle that sweeps and closes back on-side); the weekly reversal-candle bias as a hard side filter; the prior-day POC retest after a breakout/trend day; the 50-80% wick retrace limit; edge-to-edge shelf targets; structural stops beyond the signal wick or the high-value edge; the mid-zone refusal; engine stage policy.

**Disclosed, not faked:** MT5 publishes tick volume, not exchange volume, so the profile is a tick-volume proxy spread across each bar's range - stated in the header.  The document's own caveat ("Required Data: Volume ... Not viable in decentralized markets like spot forex") is quoted in the header and is exactly why the default universe is the index proxies of its worked example rather than a pair.  The order-flow tools the playbook mentions in passing (cumulative delta, absorption images) are not derivable from MT5 and are not simulated.

**`[interpretation]` (choices the document leaves open):** the signal timeframe; the bucket counts (session/visible/HVN-vs-LVA); the HVA and LVA multiples of the average bucket volume; the edge tolerance; the overnight window's clock hours; the wick fraction and minimum body; the volume multiple and its lookback; the retrace fraction and the "long wick" threshold; the trend-day body threshold; the stop buffer and the max-stop cap; the minimum target distance and the target R fallback; the limit's life in bars.  All are inputs with the document's own numbers where it gives one (50-80% retrace -> `InpRetraceFrac` 50 in, 80 out).

**Not mechanized (stated plainly):** the document's visual "does the level look respected" judgement is reduced to the mechanical sweep-and-close shape; "estimated visually, not with Fib tools" is honoured by using the wick fraction rather than any fib level; there is no economic-calendar or order-flow filter because MT5 exposes neither.
<!-- /edit:notes -->
