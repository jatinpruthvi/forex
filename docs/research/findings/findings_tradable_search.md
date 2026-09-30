# Third bounded search: tradable-only strategies with The5ers costs built in (2026-09-30)

Follows `findings_rollover_artifact.md`. The user asked for one more pre-registered search with a rollover blackout and The5ers costs as the standard.

> Sections 1-3 are the pre-registration, committed **before any P&L of any config below was computed**. Results are appended as section 4+.

## 1. Standing rules for every config (new since the rollover finding)

- **Costs**: The5ers High Stakes $4.00 round turn per lot + typical raw spread x2 (pre-declared primary; `tools/broker_cost_lab.py`). The "spread x1.5 stress" gate uses x3 of typical. Typical raw spreads are my assumption (see the rollover file).
- **Rollover blackout**: no entry bar between 16:55 and 18:10 New York time. No entry in the first hour after a weekend gap (the first-print artefact of round 2).
- **Flat before the rollover**: the intraday families (ORB, H1MR, CM) exit before 16:45 New York. The multi-day family (H4T) cannot avoid rollovers; blackout bars get their range widened by their own range when a stop is tested (a pessimistic proxy for spread spikes).
- Strict gap-aware stops, ties to the stop. Data: Dukascopy 10-year M5 (fingerprint `2133f59930b9`).
- Not modelled: swap (The5ers offers swap-free accounts on request), news blackouts (no calendar data; The5ers prohibits trading within 2 minutes of high-impact news).

## 2. Search space: 28 configs, the whole budget of this round

| Family | Rule | Configs |
|---|---|---|
| **ORB** London-open breakout | Asian range = high/low of 00:00-07:00 London. The first M5 close beyond the range between 07:00 and 10:00 gives the signal. `follow` trades the break; `fade` trades against it. Entry next open. Stop = S x range. Target = T x stop distance. Exit 16:00 London at the latest. Skip a range under 4 pips. One trade per pair per day. | mode {follow, fade} x S {0.5, 1.0} x T {1, 2} = 8 |
| **H4T** 4-hour trend | H4 bars on UTC boundaries. Enter when the close exceeds the highest high (below the lowest low) of the previous N bars; chandelier trail and initial stop k x ATR14(H4); max 60 bars; one position per pair; long and short. | N {20, 40, 80} x k {2, 3} = 6 |
| **H1MR** hourly mean reversion | H1 z-score of the close against its 20-bar mean. z <= -zt goes long, z >= zt short, entered at the next open, only between 60 and 1200 minutes after 18:10 New York. Target = the 20-bar mean at signal time, stop = S x ATR14(H1), exit by 16:30 New York or after 12 hours. | zt {2.0, 2.5} x S {2, 3} = 4 |
| **CM** conditional momentum | London windows A 00-07, B 07-12, C 12-16, D 16-20. If window X's move is at least half its recent average absolute move, trade the following window Y in X's direction (`cont`) or against it (`rev`). Stop = 2 x the recent average absolute Y move. Exit at Y's end. | (A,B) (A,C) (B,C) (B,D) (C,D) x {cont, rev} = 10 |

All are pooled across the 11 pairs. Cumulative trials across rounds after this one: 168 + 28 = **196**.
Why these: London-open breakouts, hourly mean reversion and intraday momentum are the standard intraday ideas the repo has not tested cleanly (its ORB result was bug-driven, see `findings_live_friction_audit.md`). H4 trend is the faster cousin of the daily trend that failed.

## 3. Procedure and gates (FIXED)

**TRAIN** 2016-09-11 to 2020-09-11. **VALID** 2020-09-11 to 2022-09-11. **TEST** 2022-09-11 to 2026-09-11, finalists only, once (lock file). Windows by entry time.

1. **TRAIN candidate**: n >= 300 (ORB, CM) / 150 (H1MR) / 100 (H4T); net expectancy > 0; day-block bootstrap **95%** one-sided lower bound > 0 (28 trials); PF >= 1.10; at least 3 of 4 Sep-Sep years positive.
2. **VALID**: n >= 60, net expectancy > 0, PF >= 1.05, and net expectancy still > 0 with the entry delayed 15 minutes (the executability gate learned in round 2). At most 3 finalists, ranked by the TRAIN lower bound.
3. **TEST** (all must pass): T1 n >= 150; T2 net expectancy >= +0.05R and 95% lower bound > 0; T3 PF >= 1.15; T4 positive at spread x1.5 of the primary AND with an extra 0.05R per trade; T5 >= 3 of 4 years positive; T6 top pair <= 40% of net R and positive without it; T7 tracked FSB set: entry overlap >= 85% and net expectancy > 0; T8 net expectancy > 0 with the entry delayed 15 minutes.
   Informational: both-phase 90-day pass rate at 0.5% and 1% risk against the zero-edge null.

If no finalist passes, the verdict is NOT VALIDATED. Nothing is called live-ready either way.

Code: `tools/tradable_search_lab.py`. Tests: `tests/test_tradable_search_lab.py` (blackout in summer and winter, weekend-gap block, stop/gap/target, widened-blackout stop, ORB directions and signal-before-entry, truncation invariance on real data for ORB, CM, H1MR and H4T).

---

# Results (appended 2026-09-30; sections 1-3 were committed before any P&L)

## 4. Verdict: NOT VALIDATED. No TRAIN candidate in any of the 28 configs; TEST (2022-2026) was not opened.

TRAIN 2016-09-11 to 2020-09-11, The5ers costs at x2 typical spread, rollover blackout on, strict bound, all 11 pairs pooled:

| Family | Configs | n per config | Mean gross | Mean cost | Mean net | Positive configs |
|---|---|---|---|---|---|---|
| ORB London-open breakout | 8 | 9,082 | +0.002R | 0.092R | **-0.089R** | 0 / 8 |
| H4T 4-hour trend | 6 | 987-2,498 | +0.004R | 0.021R | **-0.017R** | 0 / 6 |
| H1MR hourly mean reversion | 4 | 7,589-15,088 | -0.005R | 0.046R | **-0.051R** | 0 / 4 |
| CM conditional momentum | 10 | 6,242-6,584 | +0.005R | 0.042R | **-0.037R** | 0 / 10 |

- **All 28 configs are negative net, and every gross expectancy is within ±0.03R of zero.** The best single config is H4T N20 k3.0 at -0.001R (lower bound -0.052). The worst are the tight-stop ORB variants, where cost is 0.12R per trade.
- Breakout and fade of the Asian range are equally flat (gross +0.002R vs +0.004R), so there is no directional information either way. The same holds for continuation vs reversal in CM.
- The sample sizes are large (thousands of trades per config), so the zeros are tight: a true gross edge of even +0.05R would show up.
- `valid` printed "TRAIN candidates: NONE" and `test --confirm` refused with "no finalists: nothing to test".

## 5. Cumulative record across all rounds

| Round | Trials | Outcome |
|---|---|---|
| docs_v1 (every strategy in `docs_v1/`) | 38 | none survives TRAIN |
| Champion and M5 fade on 2016-2022 | 2 | both fail; the fade's profit is the rollover artefact |
| Daily families (trend, pullback, cross-sectional) | 12 | no TRAIN candidate |
| Session drift, weekend gap, fade geometry | 116 | only the first-print artefact |
| **Tradable-only (this round)** | **28** | **nothing** |
| **Total** | **196** | **no strategy validates** |

Every "edge" that ever looked real in this repo's data turned out to be a quote-formation artefact (first print of the week, 17:00 NY rollover). Once those are excluded, gross expectancy across 10 years, 11 pairs and 5 strategy families is indistinguishable from zero, and costs make the net negative. That is what an efficient market at these frequencies looks like, and it is the prior the pre-registrations started from.

## 6. What this means for "Phase 1 + Phase 2 inside three months"

From `findings_edge_search.md` section 6, a strategy needs about +0.10R net per trade at three independent trades a day (or +0.20R at one a day) to pass both phases in 90 days about 70% of the time. Nothing found comes close to a positive net. With these data and this search the honest expectation of a systematic challenge pass is the zero-edge lottery rate (roughly 7-25%, rising with risk and falling with the daily-loss buffer), which is not a strategy.

What could still change the answer, none of it available here: tick data with real quotes (to price entries and the spread at news and rollover), order-flow or positioning data, swap/carry and macro data, an economic calendar, or live fills. Until one of those exists, further searches on M5 bars are data-mining with a low prior.

## 7. Ledger

| # | Step | Outcome |
|---|---|---|
| 1 | Wrote lab and 7 tests; all pass, including truncation invariance on real data | ok |
| 2 | Pre-registered 28 configs (`e7d3f65`), then ran TRAIN | 0 candidates |
| 3 | VALID, TEST | no candidates, no finalists, TEST unopened |
| 4 | Sandbox `/tmp` and local git state were reset again; re-synced to the pushed branch | no file changes |

Known unrelated baseline failure: `tests/test_source_contract.py::test_canonical_and_runtime_files_exist`.
