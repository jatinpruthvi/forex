# Second bounded search: session drift, weekend-gap fade, fade geometry (2026-09-29)

Loop: `.agents/skills/loop-engineering`. The user's goal for this round: a strategy that validates AND can complete Phase 1 (+10%) and
Phase 2 (+5%) within three months, thinking beyond the repo's documents. Earlier rounds (`findings_docs_v1_validation.md`,
`findings_best_strategy_oos.md`, `findings_family_search.md`) found nothing that validates.

> Sections 1-3 are the pre-registration, committed **before any P&L of any config below was computed**. Results are appended as section 4+.

## 1. What the challenge actually needs (measured, not assumed)

`tools/challenge_sim.py` (tested) runs the two-phase challenge from every weekly start date, all inside 90 calendar days: +10%, reset, +5%, static -10% floor, 4.5% daily-loss buffer.
Applied to the M5 fade, whose 2022-26 profit is the best number in the repo, with a zero-edge null (same trades, mean gross edge removed, costs kept):

| window | slots | risk | both phases in 90 d | Phase 1 only | null both phases |
|---|---|---|---|---|---|
| 2022-26 (in-sample) | 1 | 0.5% | 40% | 62% | 14% |
| 2022-26 (in-sample) | 1 | 1.0% | 35% | 54% | 12% |
| 2016-22 (out of sample) | 1 | 0.5% | 21% | 44% | 13% |
| 2016-22 (out of sample) | 3 | 0.5% | 27% | 45% | 17% |

So even the best in-sample edge in the repo completes both phases in 90 days about 40% of the time, and a strategy with no edge does so 10-17% of the time. A pass rate is mostly variance, not evidence of edge.
Consequence for this round: **first find a net edge that survives out of sample, then size it.** The pass rate is reported for every finalist next to its null, but the gates below are edge gates.

## 2. Search space: 116 configs (the whole budget of this round; nothing is added after a look)

Data: Dukascopy 10-year M5 set, preflight PASS, fingerprint `2133f59930b9`. Costs: repo model (spread x0.55 + $7/lot), in R. Strict gap-aware stops, ties to the stop.

| Family | Hypothesis (why it might be real) | Configs |
|---|---|---|
| **SESS** session drift | Intraday FX seasonality documented in the literature (currency depreciation vs USD in its home trading hours, London/NY flow asymmetries); gold's overnight drift. One trade per instrument per weekday: enter at a London-clock time, exit at another; stop = 2 x the average absolute move of that window over the prior 20 days (an R unit that scales with the window's volatility). Windows (London wall clock): A 00-07, B 07-12, C 12-16, D 16-21. | 11 instruments x 4 windows x {long, short} = **88** |
| **GAP** weekend gap fade | Weekend gaps partly refill (liquidity returns at the open). Fade a gap of >= g x ATR(D1) (and >= 3 pips) at the first bar after the weekend; target = prior close; stop = s x gap beyond entry; time exit after 24 h. | g in {0.10, 0.25} x s in {1, 2} = **4** |
| **FADE** fade geometry | The exhaustion fade had positive gross edge before and after 2022 but cost ate it before 2022. Re-choose its geometry on 2016-2022 only, and test the mirror (short fade of up-spikes). Trigger: body > K x ATR14 (prior bars); entry next open; stop = bar extreme -/+ S x ATR; target T x R; 96 h hold; min stop 1 ATR. | K in {3,4,5} x S in {2,3} x T in {5,10} x {long-only, both} = **24** |

Known design bias, disclosed: I know the fade family worked in 2022-26 and the gold Donchian was positive in both windows, so those directions were chosen with that knowledge. Their geometry and parameters are chosen on 2016-2022 only.

## 3. Procedure and gates (FIXED)

Windows by entry time. **TRAIN** 2016-09-11 to 2020-09-11. **VALID** 2020-09-11 to 2022-09-11. **TEST** 2022-09-11 to 2026-09-11, finalists only, once (lock file). FWD from 2026-09-13 is smoke.

1. **TRAIN candidate**: n >= 600 (SESS) / 100 (GAP) / 150 (FADE), net expectancy > 0, day-block bootstrap **97.5%** one-sided lower bound > 0 (a stricter bound than before because of the 116 trials), PF >= 1.10, at least 3 of the 4 Sep-Sep years positive.
2. **VALID**: n >= 250 (SESS) / 60 (others), net expectancy > 0 and PF >= 1.05. Survivors are ranked by TRAIN lower bound; **at most 3 finalists**.
3. **TEST** (all must pass; strict bound): T1 n >= 150; T2 expectancy >= +0.03R and 95% lower bound > 0; T3 PF >= 1.10; T4 positive at spread x1.5 and with an extra 0.03R per trade; T5 >= 3 of 4 years positive; T6 top pair <= 40% of net R and positive without it; T7 the tracked FSB set gives >= 85% entry overlap and a positive expectancy.
   (Lower expectancy bars than round 1 because these strategies have small R units and low cost. Pass rate is informational, printed against the zero-edge null at 0.5/1.0/1.5% risk with 2 slots.)

Also reported for the record: cumulative trials across all rounds (docs_v1 38 + earlier candidates 2 + family search 12 + this round 116 = **168**).
If no finalist passes, the verdict is NOT VALIDATED and nothing is called live-ready.

Code: `tools/edge_search_lab.py`, `tools/challenge_sim.py`; tests `tests/test_edge_search_lab.py`, `tests/test_challenge_sim.py` (stop/gap/target mechanics, mirror, window entry time, phase/floor/daily-limit logic).
