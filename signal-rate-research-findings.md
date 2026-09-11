# Signal Rate Research Findings

**Date:** Session 4  
**Purpose:** Determine whether parameter relaxation can raise signal frequency enough to make the TRIAD-R strategy viable for the The5ers $2,500 New High Stakes challenge within a reasonable timeframe.  
**Data:** Eightcap tick data — EURUSD (452 MB, 196 days), GBPUSD (600 MB, 206 days), USDJPY (244 MB, 61 days) — all covering approximately 2024-06-19 to 2025-03-21.  
**Scripts:** `tools/parameter_grid_search.py`, `tools/multi_pair_grid_search.py`, `tools/extended_grid_search.py`

---

## 1. The Core Problem

The challenge requires +10% profit in Phase 1 = +$250 at $2,500 balance.  
Profile A (0.40% risk × 1.50R) yields approximately **$15 net per winning trade**.  
Wins needed for Phase 1: **~17 wins**.  
At a realistic 50% win rate: **~34 signals needed** just for Phase 1.

The original frozen geometry (SWEEP_ATR_MAX=0.50, RECLAIM_BARS=3, RECLAIM_WICK_MIN=0.60) produced **6 signals from 196 EURUSD days** — a 3.1% signal rate.  
At that rate, ~34 signals requires **~1,100 trading days = ~4.4 years**.  
That is not viable for a challenge with an unlimited but practically finite time window.

---

## 2. Parameters Tested

Three dimensions were varied in a full grid search:

| Parameter | Baseline | Candidates tested |
|---|---|---|
| `SWEEP_ATR_MAX` | 0.50 | 0.50, 0.75, 1.00, 1.25 |
| `RECLAIM_WICK_MIN` | 0.60 | 0.60, 0.50, 0.45, 0.40 |
| `RECLAIM_BARS` | 3 | 3, 4, 5 |

All other geometry frozen: `SWEEP_ATR_MIN=0.05`, `DISP_BODY_MIN=0.60`, `STOP_BUFF=0.10`, `STOP_ATR_MIN=0.60`, `STOP_ATR_MAX=1.50`.

---

## 3. Key Findings by Pair

### 3.1 EURUSD London (196 days)

| Parameter set | Signals | Rate |
|---|---|---|
| Baseline (SM=0.50, WM=0.60, RB=3) | 6 | 3.1% |
| SM=0.75, WM=0.50, RB=3 | 8 | 4.1% |
| SM=0.75, WM=0.45, RB=3 | 8 | 4.1% |
| SM=1.25, WM=0.40, RB=5 | 8 | 4.1% |

**Finding:** EURUSD signal count plateaus at **8 regardless** of how aggressively parameters are relaxed beyond SM=0.75. Increasing RECLAIM_BARS from 3 to 5 gives **zero additional signals** on EURUSD. The `too_deep` count barely changes with more reclaim bars (119 → 120) — meaning the price that was "too deep" during bar 4/5 was already too deep by bar 3. The bottleneck is not reclaim time, it's sweep depth.

### 3.2 GBPUSD London (206 days)

| Parameter set | Signals | Rate |
|---|---|---|
| Baseline (SM=0.50, WM=0.60, RB=3) | 0 | 0.0% |
| SM=0.50, WM=0.45, RB=3 | 3 | 1.5% |
| SM=0.75, WM=0.45, RB=3–5 | 3 | 1.5% |
| SM=1.25, WM=0.40, RB=5 | 3 | 1.5% |

**Finding:** GBPUSD also plateaus hard at **3 signals**. Zero signals with the original WICK_MIN=0.60 — the wick quality of GBPUSD reclaim bars is structurally weaker than EURUSD. Relaxing WICK_MIN below 0.45 adds no more signals. RECLAIM_BARS extension has zero effect.

### 3.3 USDJPY New York (61 days only — data issue)

| Parameter set | Signals | Rate |
|---|---|---|
| Any combination | 1 | 1.6% |

**Finding:** The USDJPY file covers only 61 trading days vs 196–206 for the other pairs. This is likely because the USDJPY NY session entry window (08:30–11:00 NY = ~13:30–16:00 server) falls **outside** the main tick coverage window for these files. Only 61 valid NY-session days were found. With 1 signal from 61 days, USDJPY is essentially uninformative and cannot be relied upon.

**Action required:** USDJPY data either needs a longer file or the session boundary calculation needs verification against actual tick timestamps.

---

## 4. Combined Portfolio Results

Best achievable with all 3 pairs combined:

| Rank | RB | SWEEP_MAX | WICK_MIN | Total Signals | Annualised | ETA (weeks) |
|---|---|---|---|---|---|---|
| 1 | 3 | 0.75 | 0.45 | 12 | ~15/yr | 111 wks |
| 2 | 3 | 0.75 | 0.40 | 12 | ~15/yr | 111 wks |
| 3 | 3 | 1.00 | 0.45 | 12 | ~15/yr | 111 wks |
| — | — | — | — | — | — | — |
| **Baseline** | 3 | 0.50 | 0.60 | 7 | ~9/yr | 190 wks |

**Improvement from relaxation: 7 → 12 signals (+71%), but ETA still 111 weeks (2+ years).**

---

## 5. The Central Conclusion

**RECLAIM_BARS extension (3→5) has zero effect.** The hypothesis was that many `too_deep` rejections were sweeps that eventually reclaimed within 4–5 bars. The data disproves this: the `too_deep` counter barely changes from RB=3 to RB=5 (119 → 120 on EURUSD). Once a sweep goes deeper than SWEEP_ATR_MAX during any bar in the reclaim window, it stays rejected regardless of how many additional bars are allowed. The sweep depth and wick quality are the binding constraints — not the reclaim time window.

**Parameter relaxation alone cannot solve the signal frequency problem.** The maximum achievable is ~12 signals per 9 months from 3 pairs combined. This requires ~2 years to accumulate enough signals for Phase 1, making the challenge impractical.

---

## 6. Root Cause Analysis

### Why signal rate is structurally low

The rejection breakdown reveals the true problem:

| Rejection reason | Days (EURUSD) | % of all days |
|---|---|---|
| `too_deep` — sweep >0.50 ATR before reclaim | 119 | 60.7% |
| `weak_wick` — reclaim bar wick ratio <0.60 | 51 | 26.0% |
| `no_sweep` — no range breach at all | 8 | 4.1% |
| Other (displacement, stop band) | 11 | 5.6% |
| **Signal found** | **6** | **3.1%** |

The `too_deep` rejection is the dominant failure mode. On 61% of days, price sweeps the Asian range but keeps going — it doesn't form a quick, clean reversal. This is the **normal London open behaviour**: most sessions are continuation moves or large sweeps that extend well before recovering. The clean 3-bar sweep-reclaim is genuinely rare.

### What this means

The strategy is designed for a specific, high-quality setup that only appears on ~3–4% of trading days **in this 9-month data window**. Whether this is representative of long-term market behaviour or reflects a particular regime (2024 mid – 2025 early was characterised by strong trend moves) is unknown without more data.

---

## 7. Options Going Forward

### Option A — Accept low frequency, use longer timeframe (RECOMMENDED FIRST STEP)

Get historical data from 2015–2019 onwards. The sweep/reclaim rate may be significantly higher in other market regimes (e.g., range-bound 2019–2021 or the 2022 high-volatility period). If the rate is 8–10% in normal regimes, the strategy becomes viable. **This is the only way to know if the strategy is structurally sound without changing the entry logic.**

**What's needed:** EURUSD M1 OHLC from 2015 onwards (~10MB file from MT5 History Center). The signal builder can be rewritten to consume M1 OHLC instead of ticks — much faster processing.

### Option B — Redesign entry: relax `too_deep` by tracking sweep depth differently

Instead of rejecting when the sweep exceeds SWEEP_ATR_MAX at any point during the reclaim window, only reject if the sweep exceeds SWEEP_ATR_MAX **at the close of the sweep bar** (not the running extreme during reclaim bars). This preserves the intent (reject huge breakouts) while allowing deeper intrabar wicks that quickly recover. This is a fundamentally different geometric interpretation.

**Estimated impact:** Could potentially unlock 20–30% of `too_deep` rejections.

### Option C — Different session or different setup type

Add a second setup type alongside the sweep/reclaim: e.g., a **range-breakout pullback** (price breaks range by >0.5 ATR, pulls back to the range boundary, then re-breaks). This is a different class of setup but uses the same infrastructure (Asian range, ATR, M5 bars). Higher frequency but lower quality than a clean sweep/reclaim.

### Option D — Accept the current signal rate, focus on challenge feasibility

The challenge has no time limit. If the win rate is genuinely above 50% and expectancy is positive, the strategy will eventually pass. The question is patience. With 12 signals/9 months and ~50% WR, Phase 1 could take 2–3 years. This is viable only if you are willing to wait.

---

## 8. Recommended Next Action

**Before any code changes, get 5+ years of EURUSD M1 OHLC data from MT5 History Center (File → Export, M1 timeframe, 2015–present). The file will be ~10–15 MB.**

Run the signal builder on that data. If the signal rate on 2015–2024 data is significantly higher (≥8%), the strategy is viable and the path forward is clear. If the rate is still ~3–4% across 5+ years, the strategy needs a fundamental geometry change (Option B or C above).

This is the lowest-risk, highest-information next step.

---

## 9. Parameter Recommendation (Pending More Data)

If proceeding with the current 9-month data window, the best-justified parameters are:

| Parameter | Current (frozen) | Recommended relaxed value | Justification |
|---|---|---|---|
| `SWEEP_ATR_MAX` | 0.50 | **0.75** | Modest relaxation; EURUSD gains 2 signals. Beyond 0.75 adds nothing. |
| `RECLAIM_WICK_MIN` | 0.60 | **0.45** | Unlocks 3 GBPUSD signals; EURUSD gains 1. Below 0.45 adds nothing. |
| `RECLAIM_BARS` | 3 | **3** (unchanged) | Extension to 4 or 5 adds zero signals — confirmed by grid search. |

**With these values:** 12 combined signals / 9 months across 3 pairs.  
**Caveat:** These values are selected on the only data we have. They carry overfitting risk.

---

*Last updated: Session 4. Grid search complete. Recommendation: get longer historical data before committing to parameter changes.*
