# 34. Real Simple Strategy

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `real-simple-strategy` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/real-simple-strategy.pdf) (34.0 MB) |
| **Origin** | [chartfanatics.com/strategies/real-simple-strategy](https://www.chartfanatics.com/strategies/real-simple-strategy) · [source PDF on Google Drive](https://drive.google.com/file/d/1Zn2_fyB531a0XS7MNhs6ZSK5FW3I-Z61/view?usp=sharing) |
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
- **Verdict:** Implemented as a full EA - the document is explicit that it trades "5 to 6 repeatable price action setups ... anchored around earnings gaps, high volume closes, and breakout patterns", and **all six are implemented**, each with the document's own entry and stop. **EP** (episodic pivot): a gap up on "volume ... multiple times the normal daily average" -> entry on the **ORB above the high of the first five-minute bar**, stop at the low of day. **Delayed HVC**: the gap day's closing price becomes the level -> "enter as price breaks back through that close on any day afterward", stop at the low of the day the entry triggers. **Flat base**: a multiple-week tight range with the 10/20 MAs converged and ranges shrinking -> above the prior day's high, with the document's own stop rule (a very tight candle -> the previous day's low; a wide candle -> the low of the breakout day). **U&R**: the quick undercut of a prior low then the reclaim -> "enter when price reclaims the prior low", stop at "the new swing low formed during the undercut". **MA U&R**: a close below a significant moving average (the 10, 20 or 50-day) then the reclaim through it (increased volume scored) -> stop at the low of the reclaim day. **High tight flag**: a 50%+ advance, a 2-5 week tight flag on contracting volume -> the break of the flag's upper boundary, stop at the low of the breakout day. Every trade must pass the document's alignment principle - "trades are only taken when the broader market and the stock's sector or group support the trade's direction" - mechanized as the market proxy holding its own 20-day EMA plus relative strength versus that market. Daily chart for the setup, M5 for execution, risk in the stated 0.5-1% band, and management exactly as written: trims into strength after several strong days, the 10/20-day EMA trail, and an exit on a high-volume close below the 20-day EMA.
- **Instruments:** `AAPL,MSFT,NVDA` (stocks, swing trading, per the playbook); the market proxy is `InpMarketSymbol` (default `US100`)
- **Timeframe / session:** D1 setups with M5 execution, entries in the US RTH window (14:30-21:00 London); positions held for days on the trailing stop
- **EA file / magic:** [`EA_CF_RealSimpleStrategy.mq5`](../mql5-eas/EA_CF_RealSimpleStrategy.mq5) / `3236` (static-checked)
- **Priority:** P1 - the richest swing card of the queue (six setups)
- **Blocked by:** _nothing_
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: the playbook overview, the key principles (daily first / intraday entry, institutional
  footprints, market and group alignment, defined risk, patience and progressive exposure), the six core
  setups (EP, delayed HVC, flat base breakout, undercut and rally, MA undercut and rally, high tight
  flag), the execution process (identify, define entry and stop, adjust position size, react don't
  predict, monitor price and volume, manage the trade), the pros and cons, and the NVDA trade breakdown.
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_RealSimpleStrategy.mq5` (41 rules pinned).
- `[interpretation]`: the document is a discretionary swing playbook, so every number it does not state
  is an input and labelled - the gap minimum and volume multiple, how fresh an EP gap stays valid, the
  HVC freshness and consolidation window, the base window and height, the MA convergence, the prior-trend
  requirement, the prior-low window, the reclaim distance and volume multiple, the flag run window,
  advance threshold, flag length and height, the "near highs" band and the volume-contraction fraction,
  the strong-day trim count, the stop buffers, the max-stop sanity cap and the far TP placeholder (the
  EMA trail is the real exit).
- Design notes: the "strong days" trim and the EMA trail are day-count / MA based, so they are
  hand-rolled in `Manage()` with per-ticket one-shot globals (the engine's risk-key pattern); the
  engine's own break-even and trailing stay off because the document states the EMA trail instead. The
  ORB reference is the first M5 bar of the RTH session, so the EA reads the same bar the playbook
  watches; the low-of-day stops use the session low so far. Progressive exposure (scaling in as trades
  work) is a human discipline - the engine opens one risk-sized position per setup - and sector / group
  strength is unobservable in an EA, so relative strength versus the market proxy stands in for both the
  "strong group" and "relative strength vs. the market" criteria (disclosed in the header). "The upper
  half of the tight range" is ambiguous; the EA takes the unambiguous boundary - the flag high.
- Disclosed, not faked: the pre-market scanning of groups and sectors, the Tradezella journaling and the
  discretionary read of "institutional footprints" stay human; the ledger records entry, stop and the R
  outcome the journal needs.
<!-- /edit:notes -->
