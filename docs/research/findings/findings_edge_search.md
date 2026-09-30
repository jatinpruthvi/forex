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

---

# Results (appended 2026-09-29; sections 1-3 were committed before any P&L)

## 4. Verdict: NOT VALIDATED. TEST (2022-2026) was not opened.

116 of 116 trials on TRAIN (2016-09-11 to 2020-09-11), net of costs, strict bound:

| Family | Configs | Mean net exp | Mean gross | Mean cost | Best net exp | Candidates |
|---|---|---|---|---|---|---|
| SESS session drift | 88 | -0.046R | +0.003R | 0.049R | +0.008R (GBPUSD 12-16 long) | 0 |
| FADE geometry, long only | 12 | -0.044R | +0.145R | 0.190R | +0.002R | 0 |
| FADE geometry, long + short | 12 | -0.102R | +0.080R | 0.181R | -0.056R | 0 |
| GAP weekend fade | 4 | +0.159R | n/a | n/a | +0.220R | **4** |

- **Session drift**: gross expectancy averages zero. Only 2 of 88 cells have positive net expectancy and both are below +0.01R. No intraday time-of-day drift on these instruments survives costs on 2016-2020.
- **Fade geometry**: gross edge +0.15R is again about the size of the cost (0.19R) whatever the stop or target. Short-fading up-spikes is worse than long-fading down-spikes, so the edge is one-sided. Re-choosing the geometry does not fix the fade.
- **Weekend-gap fade** passed the pre-registered TRAIN and VALID rules (n=1011, +0.22R, PF 1.68, lower bound +0.08 to +0.15, all four years positive; VALID +0.375R, PF 2.36), which made three finalists (g=0.10/s=1, g=0.25/s=1, g=0.10/s=2, essentially the same trades).

## 5. The weekend-gap edge is an execution artefact (checked on 2016-2022 only, before touching TEST)

The rule enters at the open of the first M5 bar after the weekend hole and fades the gap back to Friday's close. Diagnostics on 2016-2022 (TRAIN + VALID, g=0.10, s=1.0):

| Entry | n | net exp | PF |
|---|---|---|---|
| first-bar open (pre-registered rule) | 1441 | +0.266R | 1.81 |
| +5 min | 1408 | +0.115R | 1.32 |
| +10 min | 1384 | +0.020R | 1.05 |
| +15 min | 1373 | +0.019R | 1.05 |
| +30 min | 1340 | -0.018R | 0.95 |
| +60 min | 1221 | -0.074R | 0.82 |

| Spread at the weekend open | net exp | PF |
|---|---|---|
| x1 (repo model) | +0.266R | 1.81 |
| x3 | +0.154R | 1.42 |
| x5 | +0.041R | 1.10 |
| x10 | -0.241R | 0.52 |

The gross edge (+0.38R) is the first minutes of the week, when a thin market prints a first tick away from the fair price and then reverts. It is gone 10 minutes later. A retail account cannot fill at the exact first-bar open, and spreads at the Sunday reopen are commonly many times normal for the first minutes. So this is a measurement of the data's first print and not a tradable edge. The other two finalists behave the same way: at +15 min they give +0.026R (g=0.25/s=1) and +0.003R (g=0.10/s=2).

**Addendum (committed with this section, added after the TRAIN/VALID look and before any TEST look; it can only tighten the gates):** T8, a finalist must keep net expectancy >= +0.03R on 2016-2022 with entry delayed 15 minutes; T9, net expectancy > 0 with the spread at x5 on the entry. All three finalists fail T8 (+0.019R, +0.026R, +0.003R). Therefore **NOT VALIDATED without opening TEST**, which stays sealed for any future, properly executable version of this idea (it would need tick or M1 data at the Sunday open and real Sunday spreads, which this repo does not have). The gates T1-T7 alone would not have caught it. That is a hole in the original pre-registration, now closed for later rounds: any strategy with entries at a session or week boundary needs a delayed-entry gate.

Code note: `gap_trades` gained `delay` and `spread_mult` arguments after the pre-registration commit. Defaults reproduce the registered rule, and the 4 tests still pass.

## 6. What would a strategy have to look like to pass both phases in 90 days?

`tools/challenge_sim.py` on synthetic trade streams (1:1 payoff, costs already inside, independent trades, up to 3 slots, the same rules as section 1; 40 simulated 400-day histories per cell):

| trades / day | net expectancy (R) | 0.5% risk | 1.0% | 1.5% | 2.0% |
|---|---|---|---|---|---|
| 1 | 0.00 (no edge) | 0% | 7% | 16% | 25% |
| 1 | +0.10 | 0% | 22% | 34% | 46% |
| 1 | +0.20 | 2% | 46% | 68% | 70% |
| 3 | 0.00 (no edge) | 4% | 23% | 10% | 20% |
| 3 | +0.10 | 25% | 70% | 31% | 43% |
| 3 | +0.20 | 84% | 93% | 52% | 64% |

- To reach about 70% probability of both phases in three months, a strategy needs roughly **+0.10R net per trade at 3 independent trades a day, or +0.20R at 1 trade a day**, sustained out of sample.
- The best out-of-sample net expectancy found across 168 trials is +0.012R (the fade, 2016-2022). That is one to two orders of magnitude short.
- Zero-edge strategies pass 7-25% of the time at high risk. A pass rate in that range is not evidence of an edge, and pushing risk up to buy it is gambling with the challenge fee, not a validated strategy. I do not recommend it and did not test anything built on it.

## 7. Cumulative record

| Round | Trials | Outcome |
|---|---|---|
| docs_v1 (all strategies in `docs_v1/`) | 38 | none survives TRAIN |
| Champion and fade on 2016-2022 | 2 | both fail out of sample |
| Daily families (trend, pullback, cross-sectional) | 12 | no TRAIN candidate |
| This round (session, gap, fade geometry) | 116 | only a data-first-print artefact |
| **Total** | **168** | **no strategy validates** |

## 8. Ledger

| # | Step | Outcome |
|---|---|---|
| 1 | Open PR #14 for rounds 1-3 | done |
| 2 | Wrote `challenge_sim.py` (6 tests). Applied it to the fade and a zero-edge null | fade completes both phases in 90 d: 40% in-sample, 21-27% out of sample; null 10-17% |
| 3 | Pre-registered 116 configs (`35d3cfb`), then ran TRAIN | 4 GAP candidates, all others none |
| 4 | VALID | 3 finalists (all GAP) |
| 5 | Executability diagnostics on 2016-2022 (delayed entry, spread stress, per-pair, hold time) | artefact; T8 added; verdict NOT VALIDATED |
| 6 | TEST | not opened |
| 7 | Sandbox `/tmp` was wiped twice between turns: the earlier local commits were lost and re-created from the surviving files. Data re-downloaded, fingerprint `2133f59930b9` verified | - |

Known unrelated baseline failure: `tests/test_source_contract.py::test_canonical_and_runtime_files_exist`.

## 9. Follow-up: how much does the M5 fade depend on the cost model? (diagnostic, not a gate)

Net result if every trade's cost were scaled by a multiple (gross R unchanged; strict bound; both-phase pass rate in 90 days from weekly starts, one slot; `tools/challenge_sim.py`). The repo's own cost model is x1.0.

| Window | cost x | net exp | PF | 90% lower bound | both-phase pass at 0.5% / 1% risk |
|---|---|---|---|---|---|
| 2016-22 (clean) | 1.0 | +0.012R | 1.01 | -0.063 | 21% / 19% |
| 2016-22 (clean) | 0.75 | +0.067R | 1.07 | -0.008 | 22% / 22% |
| 2016-22 (clean) | 0.5 | +0.121R | 1.12 | +0.046 | 26% / 29% |
| 2016-22 (clean) | 0.25 | +0.175R | 1.19 | +0.100 | 30% / 33% |
| 2022-26 (tuned) | 1.0 | +0.348R | 1.35 | +0.259 | 40% / 35% |
| 2022-26 (tuned) | 0.5 | +0.448R | 1.49 | +0.358 | 46% / 38% |

- Break-even cost multiple on the clean window is 1.06 (gross +0.230R against 0.217R cost). The fade only clears the O2 gate (+0.10R, lower bound > 0) if real costs are about half the repo model or less, which I cannot check without the user's real broker terms. It clears O3 (PF >= 1.20) only at about a quarter of the model.
- Even at half cost, the clean-window both-phase pass rate is 26-29%, far from 70%. The limit is trade volume under the one-slot rule and the 4.5% daily-loss buffer, not only the edge.
- Reading: a real broker with much cheaper execution would turn the M5 fade from a zero into a modest edge. That is a hypothesis about costs, not a validation. The way to test it is a live or demo forward run that records real fills on the exact signals, which needs a human decision.
- Sandbox note: `/tmp` and the local git state were reset again between turns; the local branch was re-synced to the pushed commit `37bf990` (`git reset` mixed, no file changes).
