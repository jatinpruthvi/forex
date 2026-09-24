# Strategy Filter and Walk-Forward Lab — Research Only

This lab tests causal filters around the current pair-fitted P0 TRIAD + Gold stack. It does not change MQL5 or production EA logic.

**Account model:** $2,500 personal-account baseline, 1.75% TRIAD risk and 3.0% Gold risk, compounding, one shared slot, maximum two trades per day. The 15% drawdown ceiling is measured; no The5ers floor or challenge-specific daily governor is applied.

**Causal rule:** every filter uses only data available at the signal decision. The two-year window is the selection gate and the four-year window is confirmation; the four-year run never selects a new filter.

**Training scenario:** the walk-forward filter keeps an expanding per-instrument shadow ledger. It can use a candidate only after at least 12 prior closed shadow outcomes exist and their mean net R is non-negative. Unfilled candidates are not treated as losses.

## Scenarios

- `triad_session_10`: reject TRIAD signals after 10:00 London.
- `triad_quality_105`: require the existing causal conviction score to be at least 1.05.
- `triad_session_quality`: apply both TRIAD filters.
- `triad_prior_trend_align`: negative-control trend alignment.
- `triad_cost_to_target_20`: reject candidates whose cost is above 20% of target R.
- `gold_long_only`: allow only long Gold breakouts.
- `gold_long_ema20_55`: allow long Gold only when the previous close is above EMA20 and EMA20 is above EMA55, all computed from prior daily closes.
- `walkforward_symbol`: expanding per-symbol training gate.

## Two-year gate

| Scenario | Trades | PnL | CAGR | Max DD |
|---|---:|---:|---:|---:|
| baseline | 72 | $3289 | 34.6% | 4.5% |
| triad_session_10 | 71 | $3400 | 35.6% | 4.5% |
| triad_quality_105 | 69 | $3397 | 35.5% | 4.5% |
| triad_session_quality | 68 | $3509 | 36.4% | 4.5% |
| triad_prior_trend_align | 50 | $2177 | 24.8% | 7.1% |
| triad_cost_to_target_20 | 68 | $2711 | 29.7% | 6.7% |
| gold_long_only | 73 | $3590 | 37.1% | 3.8% |
| gold_long_ema20_55 | 79 | $3668 | 37.7% | 3.7% |
| session_quality_plus_gold_long | 69 | $3822 | 38.9% | 3.8% |
| session_quality_plus_gold_ema | 75 | $3902 | 39.5% | 3.7% |
| walkforward_symbol | 70 | $3026 | 32.4% | 4.5% |
| walkforward_plus_static | 66 | $3236 | 34.2% | 4.5% |

## Four-year confirmation

Parameters were chosen on the two-year gate. This table only confirms the same scenarios on the unchanged four-year data.

| Scenario | Trades | PnL | CAGR | Max DD |
|---|---:|---:|---:|---:|
| baseline | 109 | $3811 | 26.1% | 4.5% |
| triad_session_10 | 106 | $4034 | 27.1% | 4.5% |
| triad_quality_105 | 106 | $3929 | 26.6% | 4.5% |
| triad_session_quality | 103 | $4155 | 27.7% | 4.5% |
| triad_prior_trend_align | 72 | $2615 | 19.6% | 7.1% |
| triad_cost_to_target_20 | 102 | $3093 | 22.3% | 6.7% |
| gold_long_only | 110 | $4396 | 28.9% | 3.8% |
| gold_long_ema20_55 | 116 | $4505 | 29.4% | 3.7% |
| session_quality_plus_gold_long | 104 | $4771 | 30.6% | 3.8% |
| session_quality_plus_gold_ema | 110 | $4886 | 31.1% | 3.7% |
| walkforward_symbol | 104 | $3460 | 24.3% | 4.5% |
| walkforward_plus_static | 99 | $3664 | 25.3% | 4.5% |

## Gate training year vs holdout years

The two-year gate begins in 2024. This diagnostic reports the same path's 2024 PnL versus 2025–2026 PnL; it is not used to re-select after looking at the four-year confirmation.

| Scenario | 2024 PnL | 2025–2026 PnL |
|---|---:|---:|
| baseline | $499 | $2790 |
| triad_session_10 | $499 | $2901 |
| triad_quality_105 | $499 | $2898 |
| triad_session_quality | $499 | $3010 |
| triad_prior_trend_align | $622 | $1556 |
| triad_cost_to_target_20 | $400 | $2311 |
| gold_long_only | $499 | $3092 |
| gold_long_ema20_55 | $499 | $3169 |
| session_quality_plus_gold_long | $499 | $3323 |
| session_quality_plus_gold_ema | $499 | $3403 |
| walkforward_symbol | $499 | $2527 |
| walkforward_plus_static | $499 | $2737 |

## Ten-thousand-path order stress

The realized mixed-leg trade stream is randomly reordered; dates and daily stops are ignored so this isolates sequence risk. It does not recreate alternate candidate selection paths.

| Scenario | Paths >15% DD | Median DD | 95th DD | 99th DD |
|---|---:|---:|---:|---:|
| session_quality_plus_gold_ema | 0.22% | 6.8% | 10.9% | 13.2% |
| baseline | 0.89% | 7.8% | 12.4% | 14.9% |

## Ambiguity validation of the selected gate policy

Selected gate policy: **session_quality_plus_gold_ema**.

| Model | Trades | PnL | CAGR | Max DD |
|---|---:|---:|---:|---:|
| target | 110 | $4886 | 31.1% | 3.7% |
| coin | 110 | $4886 | 31.1% | 3.7% |
| stop | 110 | $4886 | 31.1% | 3.7% |

## Verdict

The best tested two-year gate policy was **session_quality_plus_gold_ema**.

A filter is not accepted merely because it increases the historical return. It must remain positive on the unchanged four-year confirmation and leave useful sequence-risk margin under the 15% ceiling.

The walk-forward expectancy filter did not provide a reliable improvement: learning from recent outcomes can lock the system out immediately before a regime change. The prior-day TRIAD trend and strict cost filters also reduced the result.

The strongest transparent candidate was the combination of the 10:00 London cutoff, conviction >= 1.05, and Gold's causal long-plus-EMA20-above-EMA55 regime gate. It is a research challenger, not certified for live deployment: the Gold sample is only a small number of multi-day trades and is heavily exposed to the 2024–2026 bullish Gold regime.

The next validation required before deployment is tick-level and forward/demo testing, including real spread, slippage, lot rounding, gaps, and a genuinely unseen future regime.

## Reproduction

```bash
python tools/filter_training_lab.py --confirm
```
