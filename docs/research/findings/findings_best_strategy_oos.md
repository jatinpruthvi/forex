# Best strategy with validation: out-of-sample test on 2016-09 -> 2022-09 (2026-09-29)

Loop: `.agents/skills/loop-engineering`, profile `projects/forex-strategy-validation.md`.
Follows `findings_docs_v1_validation.md` (none of the docs_v1 engines validated). This file asks the next question:
**which strategy the repo already contains survives a test on data that was never used to choose it?**

> Sections 1-3 are the pre-registration. They are committed **before any trade of any candidate has been computed on the new window**.
> Results are appended in section 4+. Nothing above the results may be edited afterwards; supersede by appending.

## 1. What is new, and why it matters

The CI snapshot on branch `data/m5-history` (run 36573645289, generated 2026-09-29 13:22Z, Dukascopy source) now reaches back to **2016-09-11**,
not 2022-09-11. Every selection, sweep and "held-out TEST" in this repo used 2022-09-11 -> 2026-09-11 (`FINAL_OPTIMUM_STRATEGY.md`,
`findings_phase2_speed.md`, sweeps 2-8 all read the 4-year set). So **2016-09-11 -> 2022-09-11 (six years, incl. Brexit tail, 2018 vol spike,
COVID crash, 2022 dollar surge) has never influenced any choice.** It is the first genuinely untouched window in this repo.

**Why the existing "validated" claims are not enough** (facts read from the repo, not opinions):
- `findings_phase2_speed.md` says the frozen exhaustion-fade config was "selected on TRAIN only". `validation/speed_lab/sweep3.py` states it
  *ranks on the held-out TEST half only*, and `sweep4.py` refines the grid on the TEST half. So TEST is contaminated for that config, and
  hundreds of (pair x timeframe x family x threshold x stop x target) cells were scored. The claim cannot be taken at face value.
- The certified champion (`FINAL_OPTIMUM_STRATEGY.md`, TRIAD per-pair fit + Gold Donchian) was fitted on the 2-year gate that sits inside the 4-year set, with 109 trades in four years.
- Reproduction (R11) done today: `python3 tools/order_selector.py --confirm --pairfit --compound --risk 0.0175` reproduces the documented
  109 trades / PF 2.25 / +$3,811.34 / DD 4.5% exactly. `python3 validation/speed_lab/verify_final_config.py` prints **n=1673, E_net +0.3755R, +628R** on TEST,
  while `findings_phase2_speed.md` documents n=1684, +0.3985R, +671R. **The documented headline does not reproduce to the stated precision**
  (the document was not refreshed after the degenerate-stop guard was added; per-pair rows differ by 1-5 trades). Finding, not fixed here.

## 2. Candidates (frozen now; each gets exactly ONE look at the 2016-2022 window)

| ID | Candidate | Frozen spec (source) | Why it is on the list |
|---|---|---|---|
| C1 | **Extreme-bar exhaustion fade** (M5, long only) | `verify_final_config.py`: body > 4.0 x ATR14(prior bars), down bar; entry next open; stop = bar low - 2 ATR; target +10R; 96 h hold; reject stop < 1 ATR; 11 pairs; costs = `SPREAD_STD x 0.55` + $7/lot | Highest claimed expectancy; most trades (1,673 in 2y), so the only candidate that can reach a decisive sample |
| C2 | **Champion stack** (TRIAD per-pair fit + Gold Donchian N=55, k=2.5, one slot, compounding 1.75%/3%) | `docs/strategy/FINAL_OPTIMUM_STRATEGY.md`, run through the unmodified `tools/order_selector.py` on the new window | The repo's certified champion; ~25 trades per year, so likely under-powered |

No other strategy is added, no parameter of either candidate is changed, and neither is tuned. Search budget: **0 configurations** (2 frozen candidates, 1 look each).
If a candidate cannot be run unchanged on the new window it is reported as BLOCKED, not adapted.

Not candidates: anything from docs_v1 (failed TRAIN, see companion file); the 3-month "fast track" families (eliminated in `findings_fast_track_lab.md`); M1 scalps (eliminated, `findings_phase2_speed.md`).

## 3. Windows, data rules, gates (FIXED - do not loosen)

**Data.** CI snapshot `*-m5-2016-09-11_2026-09-29.csv` (Dukascopy). Different source than the tracked FSB set, so it is used **only as its own experiment, never spliced** (profile rule).
Preflight before any run (structure only, no P&L). Raw data is used unmodified in the primary result. The CI validation report already shows verdict FAIL for every pair for
84 weekend-timestamped bars and one JPY spot-check deviation of 0.003; I will list what preflight finds and run the sensitivities below, not silently repair anything.

**Windows.**
- **OOS-A: signal bar in [2016-09-11, 2022-09-11)** - the gate window. Exits may run past the end (up to 96 h) so no trade is truncated.
- **REP: [2022-09-11, 2026-09-11)** on the CI/Dukascopy source - cross-source replication of the tracked-set result; a data-artefact check, not a gate for edge.
- **FWD: 2026-09-13 -> end of snapshot** - smoke only (~16 trading days).

**Execution model for the gate (strict, my own numpy implementation; not the repo's).** The repo verifier books every stop at exactly -1R, even when the entry bar or a later bar
gaps through it. The gate uses gap-aware stops: a stop fills at `min(stop, bar open)` (long), and the same ties go to the stop. The **repo's exact rule** is computed alongside for reproduction
(must match `verify_final_config.py` on the tracked set to the trade count, otherwise my implementation is wrong and I fix it before any OOS-A number is looked at).

**Gates for C1 on OOS-A (all must pass = VALIDATED out-of-sample):**

| # | Gate |
|---|---|
| O1 | >= 300 trades (fewer -> INCONCLUSIVE) |
| O2 | Net expectancy >= +0.10R per trade AND day-block bootstrap (10,000 resamples, seed 20260929) 90% lower bound > 0 |
| O3 | Profit factor >= 1.20 |
| O4 | Net expectancy still > 0 with (a) spreads x1.5 AND (b) +0.10R slippage per trade |
| O5 | >= 4 of the 6 Sep-Sep years net positive |
| O6 | Top pair <= 40% of net R and expectancy > 0 without it; no single UTC day > 15% of net R |
| O7 | Walk-forward (40 rolling starts, repo's firm-rule replay from `verify_final_config.py`, 0.50% risk): pass rate >= 70% (the repo's own gate) and no daily-loss-limit breach |
| O8 | REP: (pair, signal-bar) overlap between the Dukascopy and FSB signal sets >= 85% and Dukascopy-source strict expectancy > 0 |
| O9 | No unexplained R10 trigger: PF > 3, DD < 1%, sign flip between bounds, profit from never-touched fills. Coin bound (midpoint of strict and repo-rule R) > 0 |

**Gates for C2:** O1 becomes >= 100 trades; O2-O5 apply to the net R per trade of the stack (TRIAD + Gold trades pooled); O6 pair rule applied to the TRIAD legs;
O7 and O8 are replaced by "reproduces on the tracked window (109 trades)" (done, above) and the unmodified tool running on the new data. If the tool cannot run unchanged on the new
data, C2 is BLOCKED.

**"Best" rule.** If both candidates are VALIDATED, the better one is the one with the higher 90% lower bound of expectancy x trades per year. If exactly one is, it is the answer.
If neither is, the answer is "no strategy in this repo validates out-of-sample", and I say so.

**Diagnostics (reported, not gates):** time-shift placebo (same geometry at random bars); M1 replay of the 2024-09 -> 2026-09 signals for fill-path realism; break-even spread multiple;
per-year and per-pair tables; a glitch screen (signal bars whose range is > 25 ATR, dropped as a sensitivity only).

**Human-judged, not self-approved:** whether a 17% win-rate / 10R-target system is acceptable to run (behavioural), whether spreads in the minutes after a 4-ATR bar are covered by the cost model
(cannot be tested on bar data), whether the firm's drawdown rule is static. Flagged in the report.

**Budget.** Repairs: 3 per criterion. TEST-style looks: 1 per candidate. Trials: 0 new configs.

---

# Results (appended 2026-09-29; sections 1-3 above were frozen before any of this was run)

## 4. Verdict: NOT VALIDATED. No strategy in this repo validates out of sample.

| Candidate | 2016-09 -> 2022-09 (one look, never tuned on) | Verdict |
|---|---|---|
| C1 exhaustion fade (`tools/exhaustion_oos_lab.py`, code frozen at `c80eb41`) | n=4150, strict net **+0.012R**, PF 1.011, 90% bootstrap lower bound **-0.063R**; O2-O7 fail | NOT VALIDATED |
| C2 champion stack (TRIAD pairfit + Gold Donchian, `order_selector.py --confirm --pairfit --compound --risk 0.0175`, unchanged) | 127 trades, WR 38.6%, PF **0.82**, AvgR **-0.14**, -$652 on $10k, DD **36.1%** | NOT VALIDATED |

Nothing here is live-ready, and nothing should be described as validated.

## 5. C1 exhaustion fade

Reproduction first: the independent numpy engine reproduces the repo's verifier trade for trade on the tracked 2024-26 data (1673 trades, 0 mismatches, 11 pairs). The first attempt was off by one trade. Stops sit exactly on the price grid, and a 4e-17 float difference in ATR flipped a touch/no-touch tie. The fix was to copy the repo's sliding add/subtract ATR order. The result is fragile to this kind of noise (+/-1-2 trades per pair), which is itself worth knowing.

OOS-A, Dukascopy, gap-aware strict stops (the gate):
- n=4150; 9.8% reach +10R, 3613 stop out, 129 time out.
- Gross +0.230R, mean cost 0.217R, **net +0.012R**, PF 1.011, coin-flip-stop variant +0.017R, repo -1R rule +0.021R.
- Spread multiples x1.0 / 1.5 / 2.0 / 3.0: +0.012 / -0.043 / -0.099 / -0.210.
- Sep-Sep years: +0.122, -0.031, -0.055, -0.159, +0.166, +0.063 (3 of 6 positive; 4 required).
- Per pair (n, exp): EURUSD 360 -0.33; GBPUSD 426 +0.22; EURGBP 337 +0.07; AUDUSD 382 -0.05; NZDUSD 423 -0.07; USDCAD 332 +0.32; USDCHF 512 +0.07; USDJPY 450 -0.04; EURJPY 288 -0.15; GBPJPY 308 +0.03; XAUUSD 332 +0.04.
- Bad-tick screen (range <= 25 ATR): n=4125, +0.005R. The result is not a glitch artifact.
- Walk-forward (challenge-style, 0.25 / 0.50 / 0.75% risk): pass 37.5 / 37.5 / 35.0%; 8 floor busts and 18% max DD at 0.50%.
- Gates: O1 pass; **O2, O3, O4, O5, O6, O7 fail**; O9 pass.

Replication window 2022-09 -> 2026-09 (contaminated: the config was tuned there; a mechanics check only, not a gate):
- Dukascopy: n=3283, +0.348R, PF 1.35, 90% lower bound +0.258. Tracked FSB data: n=3284, +0.348R.
- **O8: 98.2% signal overlap** between the two sources. The 2022-26 edge is not a data-source artifact.
- Years +0.138, +0.437, +0.288, +0.440. EURGBP alone is 44% of net R. The walk-forward pass rate at 0.50% risk is 82.5%.

Placebo (`run --window placebo`; same long geometry, the real signals' stop/ATR ratios, +10R target, entries at random bars, same count per pair):

| window | random bars gross / net | real signals gross | target rate random / real |
|---|---|---|---|
| 2016-09 -> 2022-09 | -0.042R / -0.209R | +0.230R | 6.6% / 9.8% |
| 2022-09 -> 2026-09 | -0.005R / -0.154R | +0.548R | 6.1% / 11.8% |

Reading: the exhaustion trigger carries real gross information in both windows, about +0.27R above random entries before 2022 and +0.55R after. Before 2022 that is roughly the size of the 0.22R round-trip cost, so the net is about zero. The 2022-26 profit is a bigger version of the same effect and does not persist earlier. It is regime- or sample-specific, or the tuned parameters were overfit to it. This data cannot separate those two explanations.

Forward window (2026-09-13 to the data end, `run --window fwd`): n=52, net +0.015R, lower bound -0.46R. It is too small to conclude anything, and all gates fail on n. It is neither support nor refutation.

Stale-documentation discrepancy: `docs/research/findings/findings_phase2_speed.md` documents n=1684 / +0.3985R for the fade. The repo verifier gives n=1673 / +0.3755R (the doc predates the degenerate-stop guard). The doc also says the config was "selected on TRAIN only", but `sweep3.py` and `sweep4.py` ranked and refined on the TEST window. 2022-26 was therefore never held out for this strategy. Only 2016-2022 was clean, and there the edge is absent.

## 6. C2 champion stack

`order_selector.py` was run unchanged, from a temp tree holding 2016-09-11 -> 2022-09-11 Dukascopy slices in the paths it hard-codes. The P0 line is the champion policy. Only `--no-doc` was added, so it does not overwrite tracked findings.

| | 2022-09 -> 2026-09 tracked FSB (the documented result) | 2022-09 -> 2026-09 Dukascopy slice | **2016-09 -> 2022-09 Dukascopy (OOS-A)** |
|---|---|---|---|
| Trades | 109 | 109 | **127** |
| WR / PF / AvgR | 62.4% / 2.25 / +0.39 | 62.4% / 2.24 / +0.40 | **38.6% / 0.82 / -0.14** |
| P&L, CAGR, DD | +$3,811, 26.1%, 4.5% | +$3,817, 26.1%, 4.6% | **-$653, -4.9%, 36.1%** |
| TRIAD leg | 90 / +$2,004 | 90 / +$1,980 | **99 / -$1,214** |
| Gold Donchian leg | 19 / +$1,807 | 19 / +$1,837 | 28 / +$561 |

- The middle column is a cross-source check, like O8 for C1. The Dukascopy data reproduces the documented result almost exactly, so the OOS failure is not a data-source artifact.
- The gold leg still reproduces the swing_lab reference trade for trade (28 trades, meanR +0.336).
- The 2022-26 result was fitted (pairfit assignment, TRIAD thresholds, and the Gold N/k, all chosen on the 2y gate). It is an in-sample number.
- Gates (n >= 100 with O2-O5): O1 pass on n=127; O2 fails (AvgR -0.14R); O3 fails (PF 0.82); O4 and O5 are moot. The stack's profit came from the TRIAD leg on the fitted window, and the TRIAD leg lost money in 2016-22.

## 7. Exploratory only: Gold Donchian (N=55, k=2.5) standalone

This was **not** pre-registered as a candidate. It is one leg of C2, picked after seeing that leg positive out of sample, so it carries a selection effect. Keep it as a hypothesis for a future pre-registered test, and don't treat it as a finding. The parameters are the frozen ones and were not refit.

| window | n | mean R | PF | WR | 90% bootstrap lower bound (trade-level) |
|---|---|---|---|---|---|
| 2016-09 -> 2022-09 | 28 | +0.336 | 1.78 | 46% | -0.012 |
| 2022-09 -> 2026-09 (in-sample) | 19 | +0.890 | 3.77 | 63% | +0.150 |
| pooled | 47 | +0.560 | n/a | n/a | +0.195 (the pooled figure includes in-sample data) |

Fewer than 100 trades over 10 years (about 5 a year). The clean OOS sample has a lower bound that touches zero. The largest trade is 39% of pooled R. This is a slow, low-frequency trend filter on one instrument in a decade when gold trended. It does not meet the pre-registered n or lower-bound requirements, so **it is INCONCLUSIVE**. Only new forward data can settle it, and at about 5 trades a year that takes years.

## 8. Conclusions

1. Neither candidate clears the pre-registered out-of-sample gates. The honest answer to "best strategy with validation" is that none validates.
2. The strongest positive evidence found is a gross edge in the exhaustion trigger (+0.27R over random entries in 2016-22), and a small positive gold trend leg. Neither is tradable net of cost at the sizes tested.
3. The documented 2022-26 performance figures (26% CAGR, 62% WR, +0.37R/trade) are in-sample numbers and don't carry over to 2016-22.
4. Data caveat: the OOS window is Dukascopy data rather than the FSB feed. Cross-source checks (C1 O8 98.2% overlap; C2 109 trades, PF 2.24 vs 2.25) show the two feeds agree on 2022-26. The costs model is the repo's fixed spread schedule, applied identically to all windows.
5. Not tested: M1 intra-bar replay (M5 OHLC cannot resolve stop/target order inside a bar on the tightest stops), swap/carry, and DXY/oil/tick-volume gates.

## 9. Ledger

| # | Step | Outcome |
|---|---|---|
| 1 | Reproduce champion on tracked 2022-26 data | exact match |
| 2 | Reproduce fade with independent engine | first FAIL (1674 vs 1673, float tie); fixed; PASS, 0 mismatches |
| 3 | C1 OOS-A, one look | NOT VALIDATED |
| 4 | C1 REP mechanics check (contaminated window) | 98.2% overlap, edge replicates in-sample |
| 5 | C2 OOS-A, one look (first attempt crashed on setup: import path, wrong interpreter, no data consumed) | NOT VALIDATED |
| 6 | C2 cross-source check on 2022-26 Dukascopy | matches documented result |
| 7 | C1 placebo, C1 FWD, exploratory gold Donchian stats | see sections 5 and 7 |

Trials with a P&L look on OOS-A: 2 (C1, C2). Extra looks, disclosed: the REP runs (in-sample), the placebo and FWD runs, and the exploratory gold stats (diagnostics, no parameter changes).

Known baseline failure, unrelated and not fixed: `tests/test_source_contract.py::SourceContractTests::test_canonical_and_runtime_files_exist` (the file it wants moved to `docs/prop_firm/`).

Reproduce: `tools/exhaustion_oos_lab.py {repro | run --window oos|rep|fwd|placebo}` (needs the 10-year Dukascopy set from the `data/m5-history` branch); C2 via `PYTHONPATH=<repo> python tools/order_selector.py --confirm --pairfit --compound --risk 0.0175 --no-doc` from a directory holding the sliced CSVs.
