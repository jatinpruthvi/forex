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

*(appended 2026-09-30)*

## 4. Q1 result: the rollover spread is huge and the real spreads are wider than my assumptions

Median per-minute mean spread, pips, real quotes Sep 2025 to Aug 2026 (`tools/tick_lab.py report`):

| Window (NY clock) | EURUSD | GBPUSD | USDJPY | AUDUSD |
|---|---|---|---|---|
| my `TYPICAL_RAW` assumption (x1) | 0.10 | 0.30 | 0.30 | 0.30 |
| all minutes (median) | 0.31 | 0.67 | 0.42 | 0.90 |
| 02:00-05:00 | 0.29 | 0.63 | 0.40 | 0.89 |
| 13:00-15:00 | 0.28 | 0.64 | 0.37 | 0.89 |
| 16:00-16:50 | 0.35 | 0.75 | 0.49 | 0.95 |
| **17:00-17:05** | **4.30** | **8.52** | **8.09** | **5.63** |
| 16:55-18:10 (median) | 2.30 | 5.32 | 3.99 | 3.10 |
| 16:55-18:10 (mean) | 2.69 | 6.01 | 4.99 | 3.62 |
| 16:55-18:10, 99th pct of the minute's widest spread | 9.7 | 22.7 | 22.4 | 14.2 |
| first 5 minutes after the weekend gap | 5.24 | 12.95 | 9.20 | 7.15 |

- The same table explains the weekend "first print" artefact of the second search (`findings_edge_search.md`: +0.27R at delay 0, gone by 10-15 minutes): a 5 to 13 pip spread in the first five minutes after the open makes an order at that print untradable.
- The rollover spread is **10 to 30 times** the normal spread and the weekend-open spread about 15 to 30 times, which is the mechanism the artefact finding guessed at, now observed.
- **Caveat on the cost assumptions:** this feed's ordinary spread (EURUSD 0.3, GBPUSD 0.7, USDJPY 0.4, AUDUSD 0.9) is 2 to 3 times my `TYPICAL_RAW`. That is a retail-quote feed (spread includes a markup); a raw-spread account with a separate commission, which is what The5ers and Fusion Zero offer, would be tighter, so the raw numbers are not wrong, but nothing here verifies them. If the real accounts look more like this feed than like raw, every cost in the earlier rounds was too low and the verdicts only get worse.

## 5. Q2 result: the rollover profit is an artefact. On real quotes it is a large loss.

The fade's signals on these four pairs in the window: 315 (123 on the rollover, 192 elsewhere). Expectancy in R (1R = the model's stop distance), entry delayed by the stated minutes:

| Group | Model gross (bid bars) | Model net (repo cost x2 + $4) | Real quotes, net of $4 | n |
|---|---|---|---|---|
| Rollover, delay 0 | +0.808 | +0.619 | **-1.885** | 123 |
| Rollover, delay 1 min | +0.808 | +0.619 | **-1.763** | 123 |
| Rollover, delay 5 min | +0.808 | +0.619 | **-1.467** | 123 |
| Everything else, delay 0 | +0.328 | +0.221 | +0.066 | 192 |
| Everything else, delay 1 min | +0.328 | +0.221 | +0.048 | 192 |
| Everything else, delay 5 min | +0.277 | +0.170 | +0.036 | 191 |

- **Decision rule (section 2): not tradable.** The rollover group's real-quote net is deeply negative at every delay; the +0.25R threshold is missed by two R.
- Why: the rollover signals have a **median stop distance of 5.4 pips and a median entry spread of 8.7 pips**. A long filled at the ask is already below its own stop on the bid (101 of 123 stopped out, 19 hit the target, 3 timed out; 17 % winners). The model books the bid-bar rebound as profit that no ask-side order could ever capture. 90 % bootstrap interval of the delay-1 mean: -2.35R to -1.16R.
- **Everything else** (delay 1, post-hoc description of the same run, not a new trial): n=192, mean +0.048R, day-block bootstrap 5-95 %: -0.32R to +0.47R; 157 stops, 14 targets, 21 time exits; per pair GBPUSD +0.12 (36), USDJPY +0.11 (95), EURUSD +0.02 (28), AUDUSD -0.20 (33). The model's own net for the same trades is +0.221R; the gap, 0.17R, is the real entry/exit spread beyond my x2 assumption (the mean entry spread is 0.7 pips, about 0.09R of the stop). Twelve months of four pairs cannot tell +0.05R from zero or from -0.3R. It is also inside the period that earlier rounds treated as contaminated (2022-26) and it is the most recent year, so it is not evidence that the clean 2016-22 result (-0.12R) was wrong.

## 6. What this changes

1. **The fade cannot be rescued by trading only its rollover signals**, which was the last reading under which its headline numbers (PF 1.35, +0.35R) could have been real. It is an artefact of modelling on bid bars, now shown with quotes rather than argued.
2. Every earlier round's blackout of 16:55-18:10 NY (and the first hour after the weekend open) is justified by measurement: no stop-and-target system can work when the spread is 4 to 13 pips.
3. **A practical rule for live or demo trading:** do not place orders, and keep stops away from, 16:55-18:10 New York. Stops sitting in the book can be hit by the spread alone at 17:00 (the quoted bid does not move, but many platforms trigger shorts' stops on the ask).
4. Cost assumptions remain the largest unverified input; a demo account at The5ers or Fusion with the platform's own spread log (see the forward-test protocol) is the only way to fix them.

## 7. Ledger

Files: `tools/tick_lab.py`, `tests/test_tick_lab.py`, `scripts/research-data/fetch_ticks.py`. Not a search (no config was tuned or ranked), so the trial count stays at 210 (this round's 14 were the macro configs).
