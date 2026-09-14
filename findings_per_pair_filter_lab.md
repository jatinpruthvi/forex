# Per-Pair Filter and Interaction Lab — Research Only

This report audits whether the global TRIAD filters from `filter_training_lab.py` should really be applied to every pair. No MQL5 or production EA file was changed.

**Protocol:** pair-fitted TRIAD, Gold Donchian N=55/k=2.5, one shared slot, P0 first-available selection, compounding at 1.75% TRIAD / 3.0% Gold, raw costs, re-touch fills, and stop-first selection. The two-year gate is selected first; the four-year window only confirms. Personal-account 15% DD ceiling is measured, not targeted.

## Pair-level standalone results

Each row is one pair with Gold and all other TRIAD symbols disabled. This distinguishes a real pair edge from a one-slot portfolio interaction.

| Pair | New filter | Gate trades | Gate PnL | Gate CAGR | 4y trades | 4y PnL | 4y CAGR |
|---|---|---:|---:|---:|---:|---:|---:|
| AUDUSD | none | 19 | $84 | 1.2% | 26 | $237 | 2.3% |
| AUDUSD | session <=10:00 | 19 | $84 | 1.2% | 26 | $237 | 2.3% |
| AUDUSD | quality >=1.05 | 19 | $84 | 1.2% | 26 | $237 | 2.3% |
| AUDUSD | both | 19 | $84 | 1.2% | 26 | $237 | 2.3% |
| EURJPY | none | 25 | $633 | 8.3% | 36 | $563 | 5.2% |
| EURJPY | session <=10:00 | 23 | $627 | 8.2% | 34 | $558 | 5.2% |
| EURJPY | quality >=1.05 | 25 | $633 | 8.3% | 36 | $563 | 5.2% |
| EURJPY | both | 23 | $627 | 8.2% | 34 | $558 | 5.2% |
| GBPJPY | none | 20 | $369 | 5.0% | 25 | $317 | 3.0% |
| GBPJPY | session <=10:00 | 20 | $369 | 5.0% | 25 | $317 | 3.0% |
| GBPJPY | quality >=1.05 | 19 | $314 | 4.3% | 24 | $263 | 2.5% |
| GBPJPY | both | 19 | $314 | 4.3% | 24 | $263 | 2.5% |
| USDJPY | none | 23 | $193 | 2.7% | 36 | $31 | 0.3% |
| USDJPY | session <=10:00 | 23 | $193 | 2.7% | 34 | $71 | 0.7% |
| USDJPY | quality >=1.05 | 22 | $243 | 3.3% | 33 | $36 | 0.4% |
| USDJPY | both | 22 | $243 | 3.3% | 31 | $77 | 0.8% |
| XAUUSD | none | 29 | $452 | 6.1% | 38 | $756 | 6.8% |
| XAUUSD | session <=10:00 | 29 | $452 | 6.1% | 38 | $756 | 6.8% |
| XAUUSD | quality >=1.05 | 27 | $452 | 6.1% | 36 | $756 | 6.8% |
| XAUUSD | both | 27 | $452 | 6.1% | 36 | $756 | 6.8% |

## One-slot portfolio ablation

A filter is applied to only the named pair while all other pair logic and Gold remain unchanged.

| Pair | New filter | Gate trades | Gate PnL | Gate CAGR | 4y trades | 4y PnL | 4y CAGR | 4y DD |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| AUDUSD | none | 72 | $3289 | 34.6% | 109 | $3811 | 26.1% | 4.5% |
| AUDUSD | session <=10:00 | 72 | $3289 | 34.6% | 109 | $3811 | 26.1% | 4.5% |
| AUDUSD | quality >=1.05 | 72 | $3289 | 34.6% | 109 | $3811 | 26.1% | 4.5% |
| AUDUSD | both | 72 | $3289 | 34.6% | 109 | $3811 | 26.1% | 4.5% |
| EURJPY | none | 72 | $3289 | 34.6% | 109 | $3811 | 26.1% | 4.5% |
| EURJPY | session <=10:00 | 71 | $3400 | 35.6% | 108 | $3932 | 26.6% | 4.5% |
| EURJPY | quality >=1.05 | 72 | $3289 | 34.6% | 109 | $3811 | 26.1% | 4.5% |
| EURJPY | both | 71 | $3400 | 35.6% | 108 | $3932 | 26.6% | 4.5% |
| GBPJPY | none | 72 | $3289 | 34.6% | 109 | $3811 | 26.1% | 4.5% |
| GBPJPY | session <=10:00 | 72 | $3289 | 34.6% | 109 | $3811 | 26.1% | 4.5% |
| GBPJPY | quality >=1.05 | 72 | $3289 | 34.6% | 109 | $3811 | 26.1% | 4.5% |
| GBPJPY | both | 72 | $3289 | 34.6% | 109 | $3811 | 26.1% | 4.5% |
| USDJPY | none | 72 | $3289 | 34.6% | 109 | $3811 | 26.1% | 4.5% |
| USDJPY | session <=10:00 | 72 | $3289 | 34.6% | 107 | $3912 | 26.5% | 4.5% |
| USDJPY | quality >=1.05 | 71 | $3397 | 35.5% | 108 | $3928 | 26.6% | 4.5% |
| USDJPY | both | 71 | $3397 | 35.5% | 106 | $4031 | 27.1% | 4.5% |
| XAUUSD | none | 72 | $3289 | 34.6% | 109 | $3811 | 26.1% | 4.5% |
| XAUUSD | session <=10:00 | 72 | $3289 | 34.6% | 109 | $3811 | 26.1% | 4.5% |
| XAUUSD | quality >=1.05 | 70 | $3289 | 34.6% | 107 | $3811 | 26.1% | 4.5% |
| XAUUSD | both | 70 | $3289 | 34.6% | 107 | $3811 | 26.1% | 4.5% |
| baseline | all | 72 | $3289 | 34.6% | 109 | $3811 | 26.1% | 4.5% |
| EURJPY session only | all | 71 | $3400 | 35.6% | 108 | $3932 | 26.6% | 4.5% |
| USDJPY quality only | all | 71 | $3397 | 35.5% | 108 | $3928 | 26.6% | 4.5% |
| targeted EUR + USD | all | 70 | $3509 | 36.4% | 107 | $4051 | 27.2% | 4.5% |
| global TRIAD filters | all | 68 | $3509 | 36.4% | 103 | $4155 | 27.7% | 4.5% |
| targeted EUR + USD + Gold EMA | long_ema20_55 | 77 | $3902 | 39.5% | 114 | $4771 | 30.6% | 3.7% |
| global TRIAD + Gold EMA | long_ema20_55 | 75 | $3902 | 39.5% | 110 | $4886 | 31.1% | 3.7% |

## Interacting-pair gate grid with Gold regime filter

The gate showed that EURJPY and USDJPY are the only pairs where the new TRIAD filters changed the selected portfolio path materially. This 4x4 grid tests their interaction while holding Gold to the causal long + EMA20 > EMA55 regime filter.

| EURJPY mode | USDJPY mode | Gate PnL | 4y PnL | 4y CAGR | 4y DD |
|---|---|---:|---:|---:|---:|
| none | none | $3668 | $4505 | 29.4% | 3.7% |
| none | session <=10:00 | $3668 | $4616 | 29.9% | 3.7% |
| none | quality >=1.05 | $3782 | $4635 | 30.0% | 3.7% |
| none | both | $3782 | $4748 | 30.5% | 3.7% |
| session <=10:00 | none | $3785 | $4638 | 30.0% | 3.7% |
| session <=10:00 | session <=10:00 | $3785 | $4752 | 30.5% | 3.7% |
| session <=10:00 | quality >=1.05 | $3902 | $4771 | 30.6% | 3.7% |
| session <=10:00 | both | $3902 | $4886 | 31.1% | 3.7% |
| quality >=1.05 | none | $3668 | $4505 | 29.4% | 3.7% |
| quality >=1.05 | session <=10:00 | $3668 | $4616 | 29.9% | 3.7% |
| quality >=1.05 | quality >=1.05 | $3782 | $4635 | 30.0% | 3.7% |
| quality >=1.05 | both | $3782 | $4748 | 30.5% | 3.7% |
| both | none | $3785 | $4638 | 30.0% | 3.7% |
| both | session <=10:00 | $3785 | $4752 | 30.5% | 3.7% |
| both | quality >=1.05 | $3902 | $4771 | 30.6% | 3.7% |
| both | both | $3902 | $4886 | 31.1% | 3.7% |

## Portfolio combinations

These combinations were compared on the two-year gate before the unchanged four-year confirmation.

| Combination | Gate trades | Gate PnL | Gate CAGR | 4y trades | 4y PnL | 4y CAGR | 4y DD |
|---|---:|---:|---:|---:|---:|---:|---:|
| baseline | 72 | $3289 | 34.6% | 109 | $3811 | 26.1% | 4.5% |
| EURJPY session only | 71 | $3400 | 35.6% | 108 | $3932 | 26.6% | 4.5% |
| USDJPY quality only | 71 | $3397 | 35.5% | 108 | $3928 | 26.6% | 4.5% |
| targeted EUR + USD | 70 | $3509 | 36.4% | 107 | $4051 | 27.2% | 4.5% |
| global TRIAD filters | 68 | $3509 | 36.4% | 103 | $4155 | 27.7% | 4.5% |
| targeted EUR + USD + Gold EMA | 77 | $3902 | 39.5% | 114 | $4771 | 30.6% | 3.7% |
| global TRIAD + Gold EMA | 75 | $3902 | 39.5% | 110 | $4886 | 31.1% | 3.7% |

## Ten-thousand-path order stress

The realized mixed-leg stream is shuffled; dates and daily stops are ignored. This tests sequence risk, not alternate candidate paths.

| Combination | Paths >15% DD | Median DD | 95th DD | 99th DD |
|---|---:|---:|---:|---:|
| baseline | 0.89% | 7.8% | 12.4% | 14.9% |
| targeted EUR + USD + Gold EMA | 0.34% | 7.0% | 11.2% | 13.5% |
| global TRIAD + Gold EMA | 0.22% | 6.8% | 10.9% | 13.2% |

## Verdict

The earlier per-pair strategy fit was tested independently; this new filter was initially global, so the pair audit was necessary.

Pair-level findings:

1. **AUDUSD:** neither new filter changed the executed result. Keep the existing AUDUSD target/logic; do not add a filter based on this sample.
2. **EURJPY:** the 10:00 London cutoff improves the one-slot portfolio because it changes which candidate gets the shared slot, although its standalone PnL is approximately flat/slightly lower. Treat it as a portfolio interaction, not proof of a stronger EURJPY edge.
3. **GBPJPY:** the quality filter removes profitable trades in the standalone test. Leave GBPJPY unfiltered by this new rule.
4. **USDJPY:** quality >=1.05 is the clearest pair-specific improvement and also reduces its confirmation drawdown modestly. It remains a weak/ballast pair, so monitor it closely.
5. **XAUUSD TRIAD:** the quality filter changes trade count but not the executed PnL in this portfolio. The meaningful Gold improvement comes from the separate Donchian directional/regime filter, not from adding another TRIAD quality gate to XAUUSD.

The parsimonious pair-specific challenger is therefore:

```text
EURJPY: session cutoff <= 10:00 London
USDJPY: conviction >= 1.05
AUDUSD: unchanged
GBPJPY: unchanged
XAUUSD TRIAD: unchanged by the new filter
Gold: long only when previous close > EMA20 > EMA55
```

On the two-year gate this targeted configuration reaches the same approximately $3,902 PnL as the global filter. Its four-year confirmation is approximately $4,771, 30.6% CAGR, and 3.7% DD. The global filter reaches approximately $4,886 on the same confirmation, but that extra 4-year gain is not allowed to decide the gate selection and therefore should be treated as a secondary descriptive result rather than proof that every pair needs the rule.

No pair filter is approved for live deployment yet. The Gold regime filter still has a small trade sample and is exposed to the recent Gold bull market. Forward/demo evidence and tick-level execution validation remain required.

## Reproduction

```bash
python tools/per_pair_filter_lab.py
```
