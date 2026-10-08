# Fourth bounded search: macro and positioning signals (carry, CFTC) (2026-09-30)

Follows `findings_tradable_search.md`. That round ended with 196 trials, no strategy validating, and the statement that only *new information* (not more price-bar rules) could change the answer. This round brings two kinds of new information that the sandbox could not reach directly and that I therefore fetched with a GitHub Actions workflow (`.github/workflows/fetch-research-data.yml`, published to the `data/research-inputs` branch):

- **Policy rates** (FRED): USD fed funds (daily), ECB deposit rate (daily), OECD call-money rates for GBP, JPY, AUD, NZD, CAD, CHF (monthly).
- **Positioning** (CFTC Commitments of Traders): financial-futures (TFF) history 2015-2026 for seven currency futures.

> Sections 1-3 are the pre-registration, committed **before any P&L of any config below was computed** (only trade *counts* were looked at while debugging: CARRY_sign_th0 782, CARRY_xs_th1 192, CARRY_signtr_th0 402, COT_lev_contra_80 1400 over the whole 10 years). Results are appended as section 4+.

## 1. Standing rules

- Universe: EURUSD GBPUSD AUDUSD NZDUSD USDCAD USDCHF USDJPY (the seven USD crosses whose currency has a rate and a CFTC future). Gold has no carry and the gold COT series uses different participant classes; it is excluded from this round.
- Costs: same as the third search (The5ers $4 round turn + typical raw spread x2). Execution: every entry and exit is on an allowed bar (outside 16:55-18:10 New York and the first hour after a weekend gap); the stop is tested with the rollover-widened ranges of `walk(..., widen_blackout=True)`; strict gap-aware stops.
- **Carry is credited only on the currency side held**, at the rate differential `i_ccy - i_USD` known at decision time, **less a 0.5 %/yr swap mark-up on notional** (my assumption for a retail broker; both directions are charged). The5ers offers swap-free accounts, on which carry is *not* earned; so the report also shows **ex-carry** expectancy (what a swap-free account would see). The gates use carry-credited R (the most favourable reading).
- Rates are lagged for publication: daily series 1 day; monthly OECD series usable only from 62 days after the month start, and treated as **missing** (not forward-filled) 75 days after that. Consequence: CHF carry is unavailable after ~2024-09, NZD after ~2025-05, and any pair without a fresh rate is skipped.
- Stop = 3 x ATR20 of daily bars (completed days only); position size is 1R at that stop. A trade is held until the next monthly rebalance (CARRY) or until Friday 15:00 London (COT).
- A continuing carry position is booked as a close and a re-open each month (conservative: it pays the spread again).

## 2. Search space: 14 configs, the whole budget of this round

| Family | Rule | Configs |
|---|---|---|
| **CARRY** monthly | At the first completed trading day of each calendar month, `carry = i_ccy - i_USD`. `sign`: long the currency if carry >= th, short if carry <= -th. `xs`: cross-sectional, long the two highest-carry currencies and short the two lowest (needs >= 5 currencies with fresh rates), each only if beyond th. `signtr`: `sign`, taken only when the price is on the same side of its 100-day SMA as the trade (carry AND trend agree). th in {0, 1 percentage point}. Entry first allowed bar after the decision day closes; exit at the next month's entry time. | 3 x 2 = 6 |
| **COT** weekly positioning | Net position / open interest of leveraged funds (`lev`) or asset managers (`am`), ranked as a percentile over the trailing 156 weeks (needs >= 104). `contra`: short the currency when the percentile >= hi, long when <= 100-hi. `follow`: the opposite. hi in {80, 90}. The report is as-of Tuesday and published Friday 15:30 New York; the trade starts the following Monday from 01:00 London and is closed the next Friday at 15:00 London. | 2 x 2 x 2 = 8 |

Cumulative trials across rounds after this one: 196 + 14 = **210**.

Why these: carry and positioning are the two classic sources of FX return that do not come from price bars, and they are the only ones the free data allows. Both are **low frequency** (about 7 x 12 = 84 carry trades a year; COT about 100 to 300 a year), so this round is also a test of whether such strategies are even *measurable* inside the gate chain, and they cannot complete two challenge phases in 90 days by themselves; they are included because the standing goal says to look for any real edge first.

## 3. Procedure and gates (FIXED, identical to the third search except where noted)

**TRAIN** 2016-09-11 to 2020-09-11. **VALID** 2020-09-11 to 2022-09-11. **TEST** 2022-09-11 to 2026-09-11, finalists only, once (lock file, `tools/macro_lab.py`).

- TRAIN candidate: n >= 100 (lower than before because these families trade rarely), net expectancy > 0, 5th-percentile day-block bootstrap lower bound > 0, PF >= 1.10, at least 3 of the 4 TRAIN years positive.
- VALID eligibility: n >= 40, expectancy > 0, PF >= 1.05, and the same with entries delayed 15 minutes. At most the top 3 by TRAIN lower bound go to TEST.
- TEST gates T1-T8 unchanged (n >= 150, exp >= +0.05R and lb > 0, PF >= 1.15, x1.5 spread and +0.05R slippage still positive, >= 3 of 4 years positive, no single pair > 40 % share, the tracked FSB 2022-26 set reproduces >= 85 % of trades with positive expectancy, 15-minute delay still positive). A validated result would additionally need a separate assessment of whether so few trades can pass a 90-day challenge.
- **Not modelled, stated up front:** actual broker swap rates (the OECD short rate is a proxy; retail swaps differ and change daily), news restrictions, CHF and NZD after their rate series go stale.
- Tests: `tests/test_macro_lab.py` (rate lag and staleness, causal percentile, carry-side sign, COT timing after publication, truncation invariance of all three carry modes on real data).

# Results

*(appended 2026-09-30; sections 1-3 above were committed first as `d025d6e`)*

## 4. Verdict: NOT VALIDATED. No TRAIN candidate in any of the 14 configs; TEST (2022-2026) was not opened.

`python tools/macro_lab.py train` (18 s), then `valid` ("TRAIN candidates: NONE", "FINALISTS: NONE"), then `test --confirm` refused with "no finalists: nothing to test".

**TRAIN 2016-09-11 to 2020-09-11** (R per trade, 1R = 3 x daily ATR, The5ers costs; "carry/trade" is the carry accrual net of the 0.5 % mark-up already inside exp; "ex-carry" is what a swap-free account would see):

| Config | n | exp | PF | gross | carry/trade | ex-carry | lb5 | TRAIN years |
|---|---|---|---|---|---|---|---|---|
| CARRY_sign_th0 | 329 | -0.003 | 0.99 | +0.003 | +0.025 | -0.028 | -0.102 | -0.27 +0.11 +0.18 -0.05 |
| CARRY_xs_th0 | 145 | -0.061 | 0.86 | -0.055 | +0.040 | -0.101 | -0.190 | -0.23 +0.15 +0.09 -0.15 |
| CARRY_signtr_th0 | 164 | -0.014 | 0.96 | -0.008 | +0.028 | -0.042 | -0.157 | -0.25 +0.09 +0.01 -0.08 |
| CARRY_sign_th1 | 141 | -0.056 | 0.86 | -0.050 | +0.057 | -0.113 | -0.201 | -0.44 +0.15 +0.09 -0.28 |
| CARRY_xs_th1 | 88 | -0.110 | 0.73 | -0.104 | +0.065 | -0.175 | -0.285 | -0.49 +0.18 +0.09 -0.27 |
| CARRY_signtr_th1 | 71 | -0.076 | 0.79 | -0.071 | +0.065 | -0.141 | -0.257 | -0.87 +0.09 -0.03 -0.42 |
| COT_lev_contra_80 | 474 | +0.017 | 1.09 | +0.023 | -0.003 | +0.020 | -0.027 | +0.01 +0.04 +0.04 -0.04 |
| COT_lev_contra_90 | 245 | +0.023 | 1.12 | +0.028 | -0.003 | +0.025 | -0.038 | -0.08 +0.08 +0.14 -0.03 |
| COT_lev_follow_80 | 474 | -0.029 | 0.86 | -0.024 | -0.003 | -0.026 | -0.077 | -0.03 -0.06 -0.06 +0.06 |
| COT_lev_follow_90 | 245 | -0.030 | 0.86 | -0.025 | -0.003 | -0.027 | -0.091 | +0.06 -0.10 -0.16 +0.07 |
| COT_am_contra_80 | 749 | +0.014 | 1.07 | +0.019 | -0.003 | +0.017 | -0.016 | +0.04 0.00 +0.05 -0.02 |
| COT_am_contra_90 | 519 | +0.014 | 1.07 | +0.019 | -0.003 | +0.017 | -0.023 | +0.01 +0.01 +0.06 -0.01 |
| COT_am_follow_80 | 749 | -0.030 | 0.86 | -0.024 | -0.003 | -0.027 | -0.059 | -0.08 -0.01 -0.07 +0.01 |
| COT_am_follow_90 | 519 | -0.035 | 0.84 | -0.029 | -0.003 | -0.032 | -0.070 | -0.05 -0.03 -0.08 0.00 |

- **CARRY: 0 of 6 positive** (mean net -0.053R). In 2016-20 the high-yielders lost as much in price as they paid in carry: the accrual is real (+0.025 to +0.065R per monthly trade) but the price leg is -0.05R to -0.10R. The worst TRAIN year for every mode is the first one (Sep 2016 - Sep 2017) and Sep 2019 - Sep 2020 (the COVID risk-off). A 4-year window is a short time for a carry factor, whose known failure mode is exactly such crashes; TRAIN being negative is not a finding about carry in general, only that this rule had no edge in this sample.
- **COT: contrarian is weakly positive, follow is its mirror image** (contra configs +0.014 to +0.023R net, every follow config negative by about the same amount). The contrarian sign is consistent across both participant groups and both thresholds (these four are one idea seen four times, not four independent results), but the size is +0.02R and the lower bounds are all negative (-0.016 to -0.038R). At +0.02R per trade and about 100 trades a year it could not be told apart from zero even after 10 years, and is a fifth of the +0.10R the challenge needs at 3 trades a day.
- Gross edge of every COT config is within +-0.03R, the same noise band as every price-bar family so far.
- **Power note (why low-frequency families cannot be judged here):** 6 CARRY trades a month across seven pairs are heavily correlated (all are USD legs). The day-block bootstrap lower bounds of -0.10R to -0.29R show the width: detecting a +0.05R edge would need an order of magnitude more independent trades than 4 years provide.

## 5. Cumulative record: 210 trials, none validates

| Round | Trials |
|---|---|
| docs_v1 strategies | 38 |
| champion and fade OOS | 2 |
| daily families | 12 |
| session / gap / fade geometry | 116 (only a first-print artefact) |
| tradable-only price-bar families | 28 |
| **macro and positioning (this round)** | **14** |
| **Total** | **210** |

## 6. What this round settles, and what it does not

- Carry and CFTC positioning, implemented on the data now available, give no edge that clears even the TRAIN gate, and the only positive pattern (contrarian COT, +0.02R) is about a tenth of what a two-phase challenge needs.
- Not settled: a proper carry test needs broker swap rates (the OECD rate is a proxy), CHF and NZD rates that run to 2026 (the OECD series stopped in 2024), and a longer history than 10 years of FX price data (the 2008-2015 carry crash and rebound are outside the window). The CFTC history reaches back to 2006 and the FRED rates to 2010, so a longer price series (histdata M1 to 2000) would be the next data to fetch if anyone wants to pursue it. I have not, because any such test would be about a *monthly* strategy whose trade count cannot complete a 90-day challenge whatever its edge.

## 7. Ledger

Files: `tools/macro_lab.py`, `tests/test_macro_lab.py`, `scripts/research-data/fetch_macro.py` and the `.github/workflows/fetch-research-data.yml` workflow (data branch `data/research-inputs`, `macro/`). Pre-registration commit `d025d6e`. The FRED gold series `GOLDPMGBD228NLBM` no longer exists (download failed, unused).
