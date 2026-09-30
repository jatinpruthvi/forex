# Real bid/ask quotes: is the fade's rollover profit tradable? (2026-09-30)

Follows `findings_rollover_artifact.md`, which showed that the exhaustion fade's profit sits almost entirely in signals on the 17:00 New York rollover bars and gave a circumstantial explanation (a crash-and-rebound on *bid* bars when the spread blows out, so a modelled entry at the bar's bid open beats any real ask fill). It had no quotes to test that. This round fetched them: histdata.com tick quotes (bid and ask) for EURUSD, GBPUSD, USDJPY and AUDUSD, Sep 2025 to Aug 2026, reduced to 1-minute bid/ask bars by `scripts/research-data/fetch_ticks.py` on a GitHub runner (`data/research-inputs` branch, `ticks/`).

> Sections 1-2 were committed **before any fade P&L on quotes was computed**. What I had seen before writing them: the minute counts, and the feed-clock calibration (section 1). Results are appended below as section 3+.

## 1. Data facts established before the test (calibration only, no P&L)

- The feed's `min` stamps are epoch *seconds* (my fetch script's unit comment was wrong: it assumed ms; pandas 3 gives microsecond datetimes). The loader accounts for it.
- **Feed clock**: matched day by day against the Dukascopy M5 bid closes (EURUSD, 12 months). Every day matches 100 % under UTC = stamp + 5 h in winter and + 4 h in summer, with the switch on **2025-10-26 and 2026-03-29, the European DST dates**, not the US ones. So the clock is not New York local time with US DST, contrary to my earlier assumption from the M1 files; around the 3 weeks in spring and 1 week in autumn where the US and Europe differ, it is a fixed offset from UTC. Everything below converts to true New York time from UTC.
- The quotes agree with Dukascopy's bid closes exactly, so these are the same underlying bid series the 10-year set uses. The ask side is what is new.

## 2. Questions, method and decision rules (FIXED)

**Q1 - real spread profile.** Median per-minute mean spread in pips by New York clock window (02:00-05:00, 13:00-15:00, 16:00-16:50, 17:00-17:05, 16:55-18:10) and in the first 5 minutes after a weekend gap, per pair, compared with my `TYPICAL_RAW` assumption (x2 is the pre-declared primary cost). Descriptive; no threshold.

**Q2 - re-execution of the fade on real quotes.** Take every signal of the frozen long-only exhaustion fade on these four pairs whose entry falls in 2025-09-03 .. 2026-08-28 (same signal code, `tools/exhaustion_oos_lab.py`; stops and targets keep the model's prices, 1R = the model's distance). Execute: market buy at the **ask** open of the entry minute; stop and limit target are sell orders and trigger on the **bid** (stop fills at the stop or the bid open if gapped; ties go to the stop); time exit after 96 h at the bid close. Subtract the $4 round-turn commission in R. Split into rollover signals (signal bar 16:55-18:10 NY) and all others. Also run entries delayed by 1 and 5 minutes (a retail platform cannot fill at the first tick of a spread blow-out).

Decision rule, fixed now:
- The rollover profit is **tradable** only if, at the 1-minute delay, the rollover group's real-quote expectancy net of commission is > +0.25R with at least 40 trades and the same sign at the 5-minute delay. Otherwise it is an artefact of bid-only bars.
- The "everything else" group is reported as the out-of-sample (different year, different pairs mix, real quotes) read of the clean fade; the clean-window expectancy was -0.08R to -0.12R at model cost; real quotes either confirm or move it, and I report the number whichever way.
- The sample is 12 months and four pairs: small. A positive result would be a reason to collect more, not a validation; nothing here opens TEST.

## 3. Procedure notes

- `tools/tick_lab.py report` prints everything. Tests: `tests/test_tick_lab.py` (ask-in/bid-out mechanics, target on bid not ask, gap fill, tie to stop, delayed entry, European-DST clock, and on real data that the feed clock matches Dukascopy M5 closes).
- Caveat stated up front: histdata's ask is a retail-feed ask, not The5ers' or Fusion's; it is the best real quote I can get, and real brokers' raw-spread accounts can differ in either direction.

# Results
