# Bounded search over three new strategy families, 2016-2026 Dukascopy M5 (2026-09-29)

Loop: `.agents/skills/loop-engineering`, profile `projects/forex-strategy-validation.md`. Follows `findings_best_strategy_oos.md`
(the two existing candidates did not validate). The user asked to continue by searching a new family under pre-registration.

> Sections 1-3 are the pre-registration, committed **before any P&L of any config below was computed**. Only trade counts of two
> configs on EURUSD (a code sanity print) were seen. Results are appended as section 4+. Do not edit above them.

## 1. Question and honest priors

Can a strategy with a much lower cost-to-risk ratio than the M5 fade (whose cost was ~0.22R per trade against a gross edge of ~0.23R)
show a net edge that survives a chronological train / validation / test procedure? Daily-horizon strategies have stops of 40-150 pips,
so the repo cost model gives about 0.02-0.06R per trade. Prior: most classic daily FX rules are roughly zero after costs over 2016-2026.
`NOT VALIDATED` is the expected outcome, and a normal, good one.

Things I already know, disclosed (they can bias my design, not the selection):
- Gold Donchian N=55, k=2.5 was positive in 2016-22 (28 trades) and 2022-26 (19 trades). F1 below is a broader cousin of it. It is on XAUUSD too.
- The M5 fade's trigger had gross information in both windows. Not used here.
- I have looked at 2022-2026 P&L only for those two things, never for any family below.

## 2. The whole trial budget: 12 configs (no more; no config is added or changed after a look)

Daily bars on the NY-17:00 clock built from M5 (stub days under 100 bars are merged into the previous day). Signal at a completed daily close;
entry at the first M5 open of the next NY day; stops checked on M5 bars, gap-aware (a long stop fills at min(stop, bar open)); repo rule (-1R) is the
optimistic bound. One position per pair. ATR = 20-day mean true range. Costs: repo model in R (`SPECS x 0.55` + $7/lot round turn). **Swap/carry is not modelled** (no data), so T4 adds 0.10R per trade as a swap/slippage haircut.

| Family | Rule | Grid (4 configs) |
|---|---|---|
| **F1 trend breakout** (long+short, all 11 pairs incl. XAUUSD) | Enter when the close exceeds the highest high (below the lowest low) of the previous N days. Stop and chandelier trail = k x ATR from the best close. Max hold 250 days. | N in {20, 55} x k in {3.0, 4.5} |
| **F2 trend pullback** (long+short, 11 pairs) | Long when close > SMA100 and the close is the lowest close of the last L days (short mirrors). Fixed stop S x ATR. Exit at the first close beyond the prior day's high (low for shorts), or after 10 days. | L in {3, 5} x S in {2.0, 3.0} |
| **F3 weekly cross-sectional** (10 FX pairs, no gold) | Each Friday close, rank pairs by the 20- or 60-day return divided by (ATR/close). "mom": long the top 3, short the bottom 3. "rev": the reverse. Stop 3 x ATR. Exit at the next Friday close. | lb in {20, 60} x {mom, rev} |

## 3. Procedure and gates (FIXED)

Windows by entry time. **TRAIN** 2016-09-11 to 2020-09-11. **VALID** 2020-09-11 to 2022-09-11. **TEST** 2022-09-11 to 2026-09-11, one look per finalist, guarded by a lock file (`/tmp/fam_out/test.lock`). FWD 2026-09-13 onward is smoke only.

1. **TRAIN**: run all 12 configs. A config is a *candidate* if n >= 100, net expectancy >= +0.05R, PF >= 1.15 and at least 3 of the 4 Sep-Sep years are positive. Per family the candidate with the highest `exp x sqrt(n)` is picked. Nothing else is looked at to choose it.
2. **VALID**: each pick is run once. It becomes a *finalist* if n >= 40, net expectancy > 0 and PF >= 1.10. Nothing is re-picked.
3. **TEST** (finalists only; at most 3, so the interval is 95% one-sided, a Bonferroni for 3), strict pessimistic bound, all must pass:

| # | Gate |
|---|---|
| T1 | n >= 150 |
| T2 | Net expectancy >= +0.10R AND day-block bootstrap (10,000 resamples, seed 20260929) 95% lower bound > 0 |
| T3 | PF >= 1.20 |
| T4 | Expectancy > 0 at spread x1.5 AND with an extra 0.10R per trade |
| T5 | >= 3 of 4 Sep-Sep years positive |
| T6 | Top pair <= 40% of net R and expectancy positive without it |
| T7 | Cross-source: on the tracked FSB set, entry overlap >= 85% and net expectancy > 0 |

"Best" = the validated finalist with the highest T2 lower bound. If no finalist passes, the answer is that no family validates. Nothing is called live-ready either way.
The account-level walk-forward (prop-challenge pass rate) is a separate sizing question and is not a gate here.

Code: `tools/family_search_lab.py` (tests: `tests/test_family_search_lab.py`: stop/gap mechanics, entry on the next day, cost scale, truncation invariance for no look-ahead).
Data: `/tmp/ci/forex-data-m5-history/*-m5-2016-09-11_2026-09-29.csv`, preflight PASS, fingerprint `2133f59930b9`.

---

# Results (appended 2026-09-29)

## 4. Verdict: NOT VALIDATED. No family produced a TRAIN candidate. VALID and TEST were never opened for any of them.

12 of 12 trials used. Costs are tiny at this horizon (0.005-0.011R per trade), so the failure is in the gross edge, not in friction.
TRAIN 2016-09-11 to 2020-09-11, strict pessimistic bound, repo cost model, `lb90` = day-block bootstrap 90% lower bound:

| Config | n | net exp (R) | PF | gross | lb90 | Sep-Sep years | ×1.5 spread | median hold |
|---|---|---|---|---|---|---|---|---|
| F1 N20 k3.0 | 282 | +0.013 | 1.03 | +0.020 | -0.077 | -0.15, +0.09, -0.11, +0.35 | +0.011 | 33 d |
| F1 N20 k4.5 | 170 | -0.003 | 0.99 | +0.001 | -0.110 | -0.21, -0.01, -0.16, +0.48 | -0.004 | 62 d |
| F1 N55 k3.0 | 193 | -0.074 | 0.83 | -0.067 | -0.173 | -0.20, -0.00, -0.25, +0.14 | -0.076 | 25 d |
| F1 N55 k4.5 | 139 | -0.039 | 0.90 | -0.034 | -0.154 | -0.24, -0.03, -0.19, +0.25 | -0.040 | 56 d |
| F2 L3 S2.0 | 1331 | -0.025 | 0.90 | -0.014 | -0.050 | -0.04, +0.02, -0.06, -0.02 | -0.027 | 5 d |
| F2 L3 S3.0 | 1259 | -0.020 | 0.89 | -0.013 | -0.039 | -0.05, +0.01, -0.04, -0.02 | -0.022 | 5 d |
| F2 L5 S2.0 | 920 | -0.017 | 0.93 | -0.007 | -0.047 | -0.04, +0.03, -0.06, -0.01 | -0.020 | 5 d |
| F2 L5 S3.0 | 884 | -0.013 | 0.93 | -0.006 | -0.037 | -0.04, +0.02, -0.03, -0.01 | -0.015 | 6 d |
| F3 mom lb20 | 1200 | -0.006 | 0.97 | +0.001 | -0.031 | 0.00, +0.02, -0.03, -0.01 | -0.008 | 7 d |
| F3 rev lb20 | 1200 | -0.008 | 0.96 | -0.000 | -0.033 | -0.01, -0.04, +0.02, +0.01 | -0.009 | 7 d |
| F3 mom lb60 | 1152 | -0.031 | 0.85 | -0.024 | -0.060 | -0.02, +0.01, -0.11, -0.01 | -0.033 | 7 d |
| F3 rev lb60 | 1152 | +0.022 | 1.12 | +0.029 | -0.006 | +0.02, -0.04, +0.09, +0.01 | +0.020 | 7 d |

- Candidate rule (n >= 100, exp >= +0.05R, PF >= 1.15, >= 3 of 4 years positive): **no config qualifies.** The best expectancy is +0.022R (F3 reversal, 60-day) with a lower bound below zero, and F1 N20 k3.0 (+0.013R) is driven by one year.
- `valid` printed `TRAIN picks: NONE`, `FINALISTS: NONE`. `test --confirm` refused with "no finalists: nothing to test". **TEST (2022-2026) was not opened**, so it is unspent.
- Gross expectancy is within ±0.03R of zero for almost every config. There is no daily-horizon signal here that costs are hiding. The trend family (F1) is the only one with a plausible positive tail, in the last TRAIN year (Sep 2019 to Sep 2020, the COVID crash), which is one episode.

## 5. What this does and does not show

- It shows that simple, textbook daily trend, pullback and cross-sectional rules on these 11 pairs have no detectable net edge over 2016-2020 under this cost model. It does not show that no edge exists anywhere: 12 configs is a small search, and swap/carry and macro data are not modelled.
- Together with `findings_best_strategy_oos.md`: the M5 fade's edge is a cost problem (gross +0.23R against 0.22R cost pre-2022), and the daily families have no gross edge. Nothing found so far turns a positive gross into a positive net at a scale that clears the gates.
- The one open thread is the Gold Donchian leg (28 + 19 trades, positive in both windows, too few trades to validate). A daily gold trend rule (F1 includes XAUUSD) did not stand out on TRAIN pooled across 11 pairs, so I would not expand this into a gold search without a fresh pre-registration.

## 6. Ledger

| # | Step | Outcome |
|---|---|---|
| 1 | Sandbox `/tmp` was wiped between turns; rebuilt venv, re-downloaded the 10-year set | preflight PASS, fingerprint `2133f59930b9` (same data as before) |
| 2 | Wrote lab and 7 tests (mechanics, no look-ahead by truncation); first truncation test failed only on a sample-size threshold (too few trades before the 2019 cut) and was fixed to cut at 2022 | 7 pass |
| 3 | Pre-registration committed (`e837e3e`) before running | - |
| 4 | TRAIN: 12 configs | no candidates |
| 5 | VALID / TEST | not run, no finalists |

Known unrelated baseline failure: `tests/test_source_contract.py::test_canonical_and_runtime_files_exist`.
