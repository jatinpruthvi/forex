# SSRN forex EAs — three strategies ported from working papers

Three new Expert Advisors, one per paper. **No existing file in this repo was
modified to add them.** Everything lives in new folders:

```
MQL5/Include/SSRN/                     5 new headers (shared numerics + signals)
MQL5/Experts/SSRN_COINTEGRATION/       EA 1
MQL5/Experts/SSRN_MOMENTUM/            EA 2
MQL5/Experts/SSRN_G10_ML/              EA 3
ssrn-ml/                               the offline trainer for EA 3
```

All three compile clean — **0 errors, 0 warnings** — under the MetaEditor64 that
ships with Fusion Markets MetaTrader 5. That is a real check, not a claim of
intent; your repo's own README notes that none of the other EAs have been through
a compiler on this machine.

---

## What each one is

| EA | Paper | Approach | Horizon |
| --- | --- | --- | --- |
| `SSRN_COINTEGRATION` | Lemishko, Landi & Caicedo-Llano, [SSRN 4771108](https://ssrn.com/abstract=4771108) | Engle-Granger–gated pairs trading | daily |
| `SSRN_MOMENTUM` | Rohrbach, Suremann & Osterrieder, [SSRN 2949379](https://ssrn.com/abstract=2949379) | Baz/Rohrbach EMA-mixture trend following | daily |
| `SSRN_G10_ML` | Agrawal, [SSRN 3693753](https://ssrn.com/abstract=3693753) | Feature pipeline + your own logistic model | H4 |

### EA 1 — `SSRN_COINTEGRATION`

Scans **every unordered pair** among its seven symbols (21 pairs, the paper's
universe). Each test window it screens every pair with Engle-Granger, testing
**both OLS orientations** and keeping whichever has the more negative residual
ADF statistic — the paper's key detail, since the EG residual depends on which
series is the regressand. Pairs that fail the screen sit flat, which is the
paper's entire contribution.

Trades the spread z-score: long when `z < -entry`, short when `z > +entry`,
exit when `|z| < exit`, plus a bar time stop. Default windows are the paper's
257 train / 21 test.

**Requires a hedging account.** Two opposing positions on one symbol exist at
once by design. It refuses to start on netting.

*Departure from the paper:* the paper measures PnL as `signal(t-2) × (z(t) −
z(t-1))` on an unlevered synthetic book. This EA instead opens two real legs at
equal notional and lets the broker mark them, so costs you see are real spread
and swap rather than a stylised 2 bp.

### EA 2 — `SSRN_MOMENTUM`

The most literal port, because the paper gives exact maths:

```
x_k = EMA(P, n_short) - EMA(P, n_long)          n_short = 8,16,32
y_k = x_k / sd_moving(63)(P)                     n_long  = 24,48,96
z_k = y_k / sd_moving(252)(y_k)
u_k = z_k * exp(-z_k^2/4) / (sqrt(2)*exp(-1/2))   -> bounded in [-1, 1]
Signal = mean(u_k)
```

The response-function denominator is `sqrt(2)*exp(-1/2)` ≈ 0.857764, **not** the
0.89 used by Baz et al. The paper derives the true extrema of
`v(z) = z·exp(−z²/4)` at `z = ±sqrt(2)`, where `v = 0.857764`, and divides by
that so the signal lands exactly in `[-1, 1]`.

*One trap worth recording:* `pdftotext` renders the paper's root sign as byte
`0xC7`, so `sqrt(2)·e^(−1/2)` extracts as plain `2 e-1/2`. Taking that literally
caps the signal at 0.7071 and silently shrinks every position. Cross-checked
against the paper's other figure — Baz's `0.89` denominator gives 0.9638,
matching the paper's stated "±0.96" — which confirms the formula and isolates
the constant as the only mangling.

The 313-bar warm-up is enforced; it will not trade before it has enough history.

Time-series mode only. The paper's cross-sectional variant needs one clock over
several currencies, which a single-chart EA cannot do honestly — and the paper
found time-series beats cross-sectional anyway.

**Read this before trading it.** The paper's own conclusion: *"there is no
momentum in G10 currencies anymore. Therefore, the strategy is not useful
anymore."* G10 returned 2.45% p.a. at Sharpe 0.53; emerging markets held 2.48%
at 0.59. Costs are not modelled in the paper either. Consider an EM cross.

### EA 3 — `SSRN_G10_ML`

**Ships inert, deliberately.** The paper publishes its indicator list and its
result (27% p.a., Sharpe 1.60) but not the fractional-differencing parameter
`d`, not the rule mapping a class label to a position, and not one trained
weight. There is nothing to port.

So the EA implements the paper's feature engineering faithfully — EMA(3/7),
Bollinger(20,2), CCI **with close replacing typical price** (their stated
modification), stochastic(14), Williams %R(14), Ichimoku, RSI(14), lags,
autocorrelations, calendar dummies, and the interest-rate differential — and
scores it with weights loaded from a CSV you produce.

If the CSV is missing, or its feature order does not match the EA exactly, it
refuses to trade and says why. It will never fall back to a guess.

---

## Training and deploying EA 3's model

This repo already carries four years of M5 bars per pair under
`validation/HistoryData` (see `scripts/history-data/README.md` for how they were
fetched from Dukascopy and HistData). `m5_to_h4.py` turns those into the H4 file
the trainer wants, bucketed on the standard UTC 00/04/08/12/16/20 grid.

```bash
# 0. build a python env with pandas + scikit-learn
python -m venv ssrn-ml/.venv && ssrn-ml/.venv/Scripts/pip install pandas scikit-learn

# 1. M5 -> H4. No download needed; the data is already in the repo.
ssrn-ml/.venv/Scripts/python ssrn-ml/m5_to_h4.py \
    --m5 validation/HistoryData/eurusd-m5-2022-09-11_2026-09-11.csv \
    --out ssrn-ml/eurusd_h4.csv

# 2. train. --horizon 18 is the paper's 3-day vertical barrier on H4.
ssrn-ml/.venv/Scripts/python ssrn-ml/train_model.py \
    --csv ssrn-ml/eurusd_h4.csv --horizon 18 --out ssrn_g10_model.csv

# 3. copy it where MT5 looks for it - see the tester note below
cp ssrn_g10_model.csv "<terminal>/MQL5/Files/"
cp ssrn_g10_model.csv "$APPDATA/MetaQuotes/Terminal/Common/Files/"

# 4. attach SSRN_G10_ML to a chart; the Experts log must say "model armed"
```

> **The Strategy Tester cannot read `MQL5\Files`.** Tester agents run in their
> own sandbox and *wipe* its `MQL5\Files` at startup, so a model placed only
> there yields `NOT ARMED - cannot open ...` on every backtest even though the
> file is plainly present. `SSRN_Model.mqh` now falls back to the **common**
> Files folder (`%APPDATA%\MetaQuotes\Terminal\Common\Files`), which the
> terminal and every tester agent share. Copy the model to both locations: the
> terminal folder for live trading, the common folder for backtesting.

The script mirrors `SSRN_Features.mqh` bar for bar. **Feature order is the
contract** — change the order in either place and the EA rejects the model,
which is exactly what you want rather than scoring against a shuffled vector.

It prints train and test accuracy. Accuracy is not profitability. Expect to
backtest before believing anything.

### Three things the labelling does that you should know

The paper's §3.2.2.3 fixes the horizontal barriers at ±70% of mean daily
volatility and the vertical barrier at 3 days; a vertical hit is labelled "the
sign of the return, **or 0**". Three consequences on real H4 data:

* **The `flat` class is genuinely rare.** Four years of EURUSD produced 41 flat
  bars against ~6,250 directional ones. The trainer therefore keeps label 0 as
  a real class (it used to be conflated with "unlabelled" and dropped), and the
  export anchors whichever classes a fit actually saw so that the missing one
  gets a bias of −1e6 and can never win the softmax.
* **A two-class fit is exported correctly, not as a fake three-class model.**
  sklearn fits a *binary* model when only two labels appear — `coef_` then has
  one row, not two. Exporting that as three rows silently produced the wrong
  matrix. Verified now: the exported file reproduces sklearn's
  `predict_proba` to ~2.5e-9 and agrees on the argmax of every holdout row.
* **On this data the model is short-biased**, and confidence is modest: in the
  25% holdout, 76% of bars clear the EA's `InpMinConf = 0.55`, of which ~85%
  are shorts, max confidence 0.82. That is a property of the data and the
  labels, not a signal worth trusting.

---

## Deploying all three

1. Copy the EA folders into `<terminal>/MQL5/Experts/` and the `SSRN` header
   folder into `<terminal>/MQL5/Include/SSRN/`.
2. Compile in MetaEditor (all three should be clean).
3. EA 1 needs a hedging account and D1 history for all seven symbols.
4. Attach, then check the Experts log — each EA prints what it is doing and why
   it might be disarmed.

## Honest limitations

* **The backtest that exists is NOT out-of-sample for EA 3 — treat its
  number as meaningless as an expectation.** Both EAs have now been run in the
  real MT5 Strategy Tester on EURUSD, 2023-01-01 → 2026-10-07, 1-min OHLC,
  10,000 USD at 1:100:

  | EA | Result | Position entries |
  | --- | --- | --- |
  | `SSRN_MOMENTUM` | **9,791.97** (−2.08%) | 7 |
  | `SSRN_G10_ML` | **11,329.16** (+13.29%) | 477 |

  The ML EA's +13.29% is **not** evidence of skill: the model was trained on
  EURUSD H4 bars spanning 2022-09 → 2026-09, which covers the backtest window
  almost entirely. The model has already seen this data. An honest estimate has
  to come from walking forward — train on a window, test strictly after it —
  which this pipeline does not do yet. The 54.6% holdout accuracy printed at
  training time is the more defensible number, and it is thin.

  `SSRN_MOMENTUM`'s −2.08% is the more representative of the two, and it is a
  small sample: the 800-bar warm-up ate the first two years of the window, so
  only 7 positions were opened, from 2025-02 onward.

  Both runs were clean — no rejected orders, no runtime errors, and the
  diagnostic logging confirmed exactly why the EAs stayed flat while warming
  up rather than looking broken.
* **EA 3 is an interpretation of its paper, not a reproduction.** The published
  27% / Sharpe 1.60 cannot be reproduced from what the paper discloses.
* **The cointegration EA needs real leverage to matter.** The paper's unlevered
  book runs at 0.89% volatility and needs **11.21× leverage** to reach a 10%
  vol target, at which its max drawdown is **−43.8%**. The paper's headline
  Sharpe ratios are scale-invariant; your account is not.
* Both the momentum and ML papers model **no transaction costs**, so their
  published returns are overstated. Only the cointegration paper tests costs,
  at 2–5 bp.
