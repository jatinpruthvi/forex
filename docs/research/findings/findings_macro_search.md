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
