#!/usr/bin/env python3
"""
Train the logistic model that SSRN_G10_ML.mq5 loads at runtime.

Source paper: Dhruv Agrawal, "Short-Term Trading Strategy on G10
Currencies", SSRN 3693753.

WHY THIS EXISTS
---------------
The paper reports 27% p.a. at a Sharpe of 1.60 but publishes none of the
things needed to reproduce it: the fractional-differencing parameter d,
the rule mapping a class label to a position, or a single trained
weight. There is nothing to embed in an EA.

So the EA implements the paper's FEATURE ENGINEERING faithfully and
scores it with weights you produce here. This script mirrors
MQL5/Include/SSRN/SSRN_Features.mqh bar-for-bar. Feature order is the
contract: the EA refuses any model whose feature names do not match,
exactly, in order.

Anything you get out of this is an INTERPRETATION of the paper, not the
paper's strategy. Do not expect 27%.

USAGE
-----
  python train_model.py --csv EURUSD_H4.csv --out ssrn_g10_model.csv

CSV columns (header row required, names case-insensitive):
  date,open,high,low,close
where date parses with pandas (e.g. 2020-06-22 12:00 or 2020.06.22).

Then copy --out into <terminal>/MQL5/Files/ and attach SSRN_G10_ML.

Requires: pandas, numpy, scikit-learn.
"""

from __future__ import annotations

import argparse
import sys
from datetime import datetime

import numpy as np
import pandas as pd

try:
    from sklearn.linear_model import LogisticRegression
    from sklearn.preprocessing import StandardScaler
except ImportError:  # pragma: no cover
    sys.exit("This script needs scikit-learn:  pip install scikit-learn")

# ---------------------------------------------------------------------------
# The contract. Must match SSRN_Features.mqh SSRN_FeatureNames() exactly,
# in this exact order. The EA validates this and refuses on any mismatch.
# ---------------------------------------------------------------------------
FEATURE_NAMES = [
    "ema_fast3", "ema_slow7", "ema_side",
    "bb_mid20", "bb_upper", "bb_lower", "bb_sd", "bb_side",
    "cci14",
    "stoch_k14", "stoch_d14", "stoch_side",
    "willr14", "willr_side",
    "ichimoku_tenkan9", "ichimoku_kijun26", "ichimoku_senkou_a",
    "ichimoku_senkou_b52", "ichimoku_chikou", "ichimoku_side",
    "rsi14", "rsi_side",
    "close_t1", "close_t2", "close_t12",
    "autocorr_lag1", "autocorr_lag2", "autocorr_lag4", "autocorr_lag6",
    "ret1_lag1", "ret1_lag2", "ret1_lag12",
    "ret_period_lag1", "ret_period_lag2", "ret_period_lag12",
    "ir_differential",
    "dow_mon", "dow_tue", "dow_wed", "dow_thu", "dow_fri", "dow_sun",
    "month_jan", "month_feb", "month_mar", "month_apr", "month_may", "month_jun",
    "month_jul", "month_aug", "month_sep", "month_oct", "month_nov", "month_dec",
    "eom",
]

AC_WINDOW = 100      # autocorrelation lookback, bars
MIN_BARS = 130       # the EA's SSRN_FEAT_MIN_BARS
CLASSES = ("short", "flat", "long")   # index 0, 1, 2 - the EA's contract


# --- rolling primitives, each mirroring its MQL5 counterpart ---------------

def _ema_local(close: np.ndarray, end: int, n: int) -> float:
    """Seeded with the SMA of the last n values, then recursed. Matches
    SSRN_F_EMA: the seed lives at end-n+1 and only that short window is
    used, so this is a local, not an expanding, EMA."""
    if end < n - 1:
        return 0.0
    window = close[end - n + 1: end + 1]
    seed = float(window.mean())
    e = seed
    for v in window[1:]:
        e = (1.0 / n) * v + (1.0 - 1.0 / n) * e
    return e


def _sma(s: np.ndarray, end: int, n: int) -> float:
    return float(s[end - n + 1: end + 1].mean()) if end >= n - 1 else 0.0


def _highest(s: np.ndarray, end: int, n: int) -> float:
    return float(s[end - n + 1: end + 1].max()) if end >= n - 1 else 0.0


def _lowest(s: np.ndarray, end: int, n: int) -> float:
    return float(s[end - n + 1: end + 1].min()) if end >= n - 1 else 0.0


def _rsi(c: np.ndarray, end: int, n: int) -> float:
    if end < n:
        return 50.0
    ch = np.diff(c[end - n: end + 1])
    up = ch[ch > 0].sum()
    dn = -ch[ch < 0].sum()
    if dn <= 0.0:
        return 100.0
    rs = (up / n) / (dn / n)
    return 100.0 - 100.0 / (1.0 + rs)


def _autocorr(c: np.ndarray, end: int, lag: int, window: int) -> float:
    if lag < 1 or end < window + lag:
        return 0.0
    base = end - window - lag + 1
    idx = np.arange(window)
    a = base + idx
    b = a - lag
    if b.min() < 1:
        return 0.0
    r1 = np.log(c[a] / c[a - 1])
    r2 = np.log(c[b] / c[b - 1])
    if r1.std() <= 0 or r2.std() <= 0:
        return 0.0
    return float(np.corrcoef(r1, r2)[0, 1])


# --- the feature row, mirroring SSRN_BuildFeatures -------------------------

def build_row(o, h, l, c, end, ts, ir_diff=0.0):
    close = c[end]
    f = np.zeros(len(FEATURE_NAMES), dtype=float)

    ema3 = _ema_local(c, end, 3)
    ema7 = _ema_local(c, end, 7)
    f[0], f[1] = ema3, ema7
    f[2] = 1.0 if ema3 > ema7 else (-1.0 if ema3 < ema7 else 0.0)

    mid20 = _sma(c, end, 20)
    if end >= 19:
        seg = c[end - 19: end + 1]
        sd20 = float(seg.std(ddof=1))
    else:
        sd20 = 0.0
    f[3], f[6] = mid20, sd20
    f[4] = mid20 + 2.0 * sd20
    f[5] = mid20 - 2.0 * sd20
    f[7] = (close - mid20) / sd20 if sd20 > 0 else 0.0

    # CCI(14) with the paper's modification: close replaces typical price
    sma14 = _sma(c, end, 14)
    seg = c[end - 13: end + 1]
    md14 = float(np.abs(seg - sma14).mean())
    f[8] = (close - sma14) / (0.015 * md14) if md14 > 0 else 0.0

    hi14, lo14 = _highest(h, end, 14), _lowest(l, end, 14)
    k = 100.0 * (close - lo14) / (hi14 - lo14) if hi14 > lo14 else 50.0
    f[9] = k
    ks = [k]
    for back in (1, 2):
        e = end - back
        if e >= 14:
            hp = _highest(h, e, 14)
            lp = _lowest(l, e, 14)
            ks.append(100.0 * (c[e] - lp) / (hp - lp) if hp > lp else 50.0)
        else:
            ks.append(50.0)
    d = sum(ks) / 3.0
    f[10], f[11] = d, k - d

    wr = -100.0 * (hi14 - close) / (hi14 - lo14) if hi14 > lo14 else -50.0
    f[12] = wr
    f[13] = (wr + 50.0) / 50.0

    tenkan = (_highest(h, end, 9) + _lowest(l, end, 9)) / 2.0
    kijun = (_highest(h, end, 26) + _lowest(l, end, 26)) / 2.0
    senka = (_highest(h, end, 52) + _lowest(l, end, 52)) / 2.0
    sena = (tenkan + kijun) / 2.0
    f[14], f[15], f[16], f[17], f[18] = tenkan, kijun, sena, senka, c[end - 26]
    f[19] = 1.0 if close > sena else (-1.0 if close < sena else 0.0)

    rsi = _rsi(c, end, 14)
    f[20] = rsi
    f[21] = (rsi - 50.0) / 50.0

    f[22], f[23], f[24] = c[end - 1], c[end - 2], c[end - 12]

    f[25] = _autocorr(c, end, 1, AC_WINDOW)
    f[26] = _autocorr(c, end, 2, AC_WINDOW)
    f[27] = _autocorr(c, end, 4, AC_WINDOW)
    f[28] = _autocorr(c, end, 6, AC_WINDOW)

    f[29] = c[end] / c[end - 1] - 1.0 if c[end - 1] > 0 else 0.0
    f[30] = c[end - 1] / c[end - 2] - 1.0 if c[end - 2] > 0 else 0.0
    f[31] = c[end - 11] / c[end - 12] - 1.0 if c[end - 12] > 0 else 0.0

    f[32] = c[end - 1] / c[end - 2] - 1.0 if c[end - 2] > 0 else 0.0
    f[33] = c[end - 1] / c[end - 3] - 1.0 if c[end - 3] > 0 else 0.0
    f[34] = c[end - 1] / c[end - 13] - 1.0 if c[end - 13] > 0 else 0.0

    f[35] = ir_diff

    dow = ts.weekday() + 1          # 0=Sun .. 6=Sat in MQL5
    if dow == 7:
        dow = 0
    f[36] = 1.0 if dow == 1 else 0.0
    f[37] = 1.0 if dow == 2 else 0.0
    f[38] = 1.0 if dow == 3 else 0.0
    f[39] = 1.0 if dow == 4 else 0.0
    f[40] = 1.0 if dow == 5 else 0.0
    f[41] = 1.0 if dow == 0 else 0.0

    mo = ts.month
    for m in range(1, 13):
        f[41 + m] = 1.0 if mo == m else 0.0

    f[54] = 1.0 if (ts + pd.Timedelta(days=1)).month != mo else 0.0

    return f# --- the paper's triple-barrier labelling -------------------------------
def _trailing_mean(x, window):
    """Trailing `window`-element mean; NaN while there are fewer than that.
    Pure numpy: pandas aligns on the index when you subtract two slices of a
    DatetimeIndex-indexed Series, which silently produced an all-NaN volatility
    series (and therefore zero labels) on pandas 3.x. No alignment, no bug."""
    x = np.asarray(x, dtype=float)
    out = np.full(len(x), np.nan)
    if len(x) >= window:
        cs = np.concatenate(([0.0], np.cumsum(x)))
        out[window - 1:] = (cs[window:] - cs[:-window]) / window
    return out


def _fill_edges(a):
    """Back-fill the leading warm-up and forward-fill the tail of a series
    whose interior can only be NaN if the window itself was."""
    a = np.asarray(a, dtype=float)
    good = np.flatnonzero(~np.isnan(a))
    if good.size == 0:
        return np.zeros_like(a)
    out = a.copy()
    out[:good[0]] = a[good[0]]
    out[good[-1] + 1:] = a[good[-1]]
    if np.isnan(out).any():
        out = pd.Series(out).bfill().ffill().to_numpy()
    return out


NO_LABEL = -99         # sentinel: this bar was never labelled, as opposed to
                        # being labelled 0, which is the paper's 'flat' class


def triple_barrier_labels(c, horizon_bars=14, vol_frac=0.70, bars_per_day=6,
                          flat_frac=0.15):
    """Upper/lower barriers at +/- vol_frac of mean daily volatility, plus a
    vertical barrier. First barrier touched wins: +1, -1; if neither is
    touched, the vertical barrier decides by the sign of the forward return.
    If that return is inside flat_frac of the barrier the move is treated as
    noise and labelled 0. Without that dead-band the third class is
    unreachable - a forward return is exactly 0 essentially never - and the
    EA's short/flat/long contract degenerates to two classes.

    The paper uses 3 calendar days on 2-hourly bars; pass the bar
    equivalent for your own timeframe (14 on H4 is a workable stand-in).

    `c` must be a 1-D array of closes, oldest to newest."""
    c = np.asarray(c, dtype=float)
    n = len(c)
    labels = np.full(n, NO_LABEL, dtype=int)
    logc = np.log(c)

    # daily volatility approximated over a 24-bar day for H4
    day_ret = np.abs(logc[bars_per_day:] - logc[:-bars_per_day])
    vol = np.zeros(n)
    vol[bars_per_day:] = _fill_edges(_trailing_mean(day_ret, 100))

    for t in range(MIN_BARS, n - horizon_bars):
        v = vol[t]
        if v <= 0:
            continue
        barrier = v * vol_frac
        up, dn = logc[t] + barrier, logc[t] - barrier
        label = 0
        for k in range(1, horizon_bars + 1):
            p = logc[t + k]
            if p >= up:
                label = 1
                break
            if p <= dn:
                label = -1
                break
        else:
            fut = logc[t + horizon_bars] - logc[t]
            if abs(fut) < barrier * flat_frac:
                label = 0
            else:
                label = 1 if fut > 0 else -1
        labels[t] = label
    return labels


# --- output in the EA's exact format -------------------------------------

def write_model(path, clf, scaler, n_classes):
    """Fold the scaler into the weights so the EA can score raw features:

        s_c = sum_i coef_[c,i] * (x_i - mean_i)/scale_i + intercept_[c]
            = sum_i W[c,i] * x_i + B[c]

    Two traps this has to avoid, both of which produce a file that parses
    fine and scores garbage:

    * scales must be indexed on the FEATURE axis, scales[None, :]. Using
      scales[:, None] broadcasts (n_classes, n_features) against
      (n_features, 1) into (n_features, n_features) and silently exports a
      matrix of the wrong shape.

    * the paper's labels are {-1, 0, +1} but its 0 - the vertical-barrier
      'sign of the return, or 0' case - is rare, so a fit can legitimately
      see only two of the three classes. sklearn then fits a binary model
      whose coef_ has ONE row modelling log(P(b)/P(a)), not two. Exporting
      that as three rows is wrong. Here the observed pair is anchored so
      that the softmax reproduces P(a) and P(b) exactly, and the missing
      class is given a bias of -1e6 so it can never win the argmax.
    """
    classes = [int(x) for x in clf.classes_]
    inv = 1.0 / scaler.scale_                            # (n_features,)
    n_feat = len(FEATURE_NAMES)
    W = np.zeros((n_classes, n_feat))
    B = np.full(n_classes, -1.0e6)                       # missing class: never argmax

    if len(classes) == n_classes:
        W = clf.coef_ * inv[None, :]                     # (n_classes, n_features)
        B = clf.intercept_ - (W * scaler.mean_[None, :]).sum(axis=1)
    elif len(classes) == 2:
        a, b = classes
        w = clf.coef_[0] * inv
        bias = clf.intercept_[0] - (w * scaler.mean_).sum()
        W[b], B[b] = w, bias                             # log(P(b)/P(a)) = w.x + bias
        W[a], B[a] = 0.0, 0.0                            # anchor the loser at 0
    else:
        raise SystemExit("The fit saw only class(es) %s - there is nothing to "
                         "learn. Give it more history." % classes)

    with open(path, "w", encoding="utf-8") as fh:
        fh.write("SSRN_ML_MODEL_V1\n")
        fh.write("# generated by ssrn-ml/train_model.py on %s\n" % datetime.now().isoformat(timespec="seconds"))
        fh.write("# class order: 0=short, 1=flat, 2=long\n")
        fh.write("# classes seen in training: %s\n" % ",".join(CLASSES[i] for i in classes))
        for name in FEATURE_NAMES:
            fh.write("feature=%s\n" % name)
        fh.write("bias=" + ",".join("%.10g" % B[i] for i in range(n_classes)) + "\n")
        for i in range(n_feat):
            fh.write("w=" + ",".join("%.10g" % W[c, i] for c in range(n_classes)) + "\n")
    return W, B


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--csv", required=True, help="OHLC export: date,open,high,low,close")
    ap.add_argument("--out", default="ssrn_g10_model.csv", help="model file to copy into MQL5\\Files\\")
    ap.add_argument("--ir", type=float, default=0.0, help="static interest differential (%%)")
    ap.add_argument("--horizon", type=int, default=14, help="vertical barrier, bars")
    ap.add_argument("--flat-frac", type=float, default=0.15,
                    help="forward returns smaller than this fraction of the barrier "
                         "are labelled 'flat' (default 0.15)")
    ap.add_argument("--C", type=float, default=1.0, help="inverse regularisation strength")
    args = ap.parse_args()

    df = pd.read_csv(args.csv)
    df.columns = [str(c).strip().lower() for c in df.columns]
    for col in ("date", "open", "high", "low", "close"):
        if col not in df.columns:
            sys.exit("CSV is missing the '%s' column. Found: %s" % (col, list(df.columns)))
    df["date"] = pd.to_datetime(df["date"])
    df = df.sort_values("date").reset_index(drop=True)

    o = df["open"].values.astype(float)
    h = df["high"].values.astype(float)
    l = df["low"].values.astype(float)
    c = df["close"].values.astype(float)

    labels = triple_barrier_labels(c, horizon_bars=args.horizon,
                                   flat_frac=args.flat_frac)

    rows, ys, idxs = [], [], []
    for t in range(MIN_BARS, len(df) - args.horizon):
        if labels[t] == NO_LABEL:      # not 0: 0 is a real 'flat' label
            continue
        rows.append(build_row(o, h, l, c, t, df["date"].iloc[t], args.ir))
        ys.append(labels[t])
        idxs.append(t)

    X = np.array(rows)
    y = np.array(ys)
    if len(y) < 500:
        sys.exit("Only %d usable samples - need at least 500. Give it more history." % len(y))

    # map {-1,0,1} -> {0=short, 1=flat, 2=long}
    ymap = {-1: 0, 0: 1, 1: 2}
    y3 = np.array([ymap[v] for v in y])
    present = np.unique(y3)
    n_classes = 3

    split = int(len(y3) * 0.75)
    Xtr, Xte = X[:split], X[split:]
    ytr, yte = y3[:split], y3[split:]

    scaler = StandardScaler().fit(Xtr)
    # multinomial is lbfgs' default for multiclass; the explicit
    # multi_class="multinomial" was removed from sklearn in 1.9
    clf = LogisticRegression(max_iter=4000, C=args.C)
    clf.fit(scaler.transform(Xtr), ytr)

    acc_tr = clf.score(scaler.transform(Xtr), ytr)
    acc_te = clf.score(scaler.transform(Xte), yte)

    W, B = write_model(args.out, clf, scaler, n_classes)

    print()
    print("  samples          : %d  (train %d / test %d)" % (len(y3), len(Xtr), len(Xte)))
    print("  classes present  : %s" % ", ".join(CLASSES[i] for i in present))
    print("  train accuracy   : %.4f" % acc_tr)
    print("  test accuracy    : %.4f" % acc_te)
    print("  features         : %d" % len(FEATURE_NAMES))
    print()
    print("Wrote %s" % args.out)
    print()
    print("  accuracy is NOT profitability. The paper reported 27%% p.a. and a")
    print("  Sharpe of 1.60; this pipeline cannot reproduce that, because the")
    print("  paper never published the weights, the differencing parameter, or")
    print("  the label-to-position rule. Treat this as an interpretation.")
    print()
    print("Next: copy %s into <terminal>\\MQL5\\Files\\, then attach" % args.out)
    print("SSRN_G10_ML to a chart and check the Experts log for 'model armed'.")


if __name__ == "__main__":
    main()
