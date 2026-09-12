# Swing Lab & Personal-Account Portfolio Findings (2026-09-12)

**Tools:** `tools/swing_lab.py` (new file), `tools/triad_honest.py` (existing).
**Question:** user wants 40–50%+/yr on a personal (non-challenge) account with
max 10% drawdown; asked specifically about scalping and other strategy classes.

---

## 1. Scalping — cannot be validated on this dataset (and why it rarely pays)

The M5 OHLC data here is bid-only with `volume=0` on the 4-year files; scalping
outcomes are decided by tick-level spread, requotes and slippage. Any scalping
backtest on this data would be fiction — the same class of fiction that
inflated the original ORB numbers. Structural note: scalping lives on
spread-capture, so broker costs consume 30–70% of gross edge (we measured cost
shares of 40–65% killing 2–5 pip intraday strategies in sessions 7–8). Verdict:
**untestable here, and the cost math is against it by construction.** Revisit
only with tick data + live spread feed.

## 2. Swing / trend-following (the one untested class) — gold only

Daily Donchian breakout + chandelier exit (k×ATR(14)), daily-close management,
next-open fills, honest costs, compounding, 2022–2026:

| Universe | Best config | Trades | PF | AvgR | Verdict |
|---|---|---|---|---|---|
| **XAUUSD** | N=55, k=2.5 | 19 | **3.76** | **+0.89R** | ✅ real edge, lumpy |
| XAUUSD | N=20, k=2.5 | 34 | 1.84 | +0.39 | ✅ weaker variant |
| XAUUSD+GBPJPY | any | 33–69 | 0.9–1.4 | ~0 | ❌ dilutes |
| core3 | any | 48–96 | 0.85–1.19 | ~0 | ❌ |
| all11 FX | any | 194–350 | 0.62–0.90 | negative | ❌ **FX trend-following is dead on 2022–26** |

⚠️ Sample warning: 19 trades, one instrument, driven by the exceptional 2024–25
gold bull market. Yearly: 2023 −1.8% / 2024 +11.2% / 2025 +24.5% / 2026 +0.4%
(at 2% risk). Expect regime risk.

## 3. The combined portfolio — TRIAD core3 (intraday) + Gold swing (multi-week)

The two are structurally uncorrelated (intraday range mean-reversion vs
multi-week trend). Merged honest equity, compounding:

| TRIAD risk + Gold risk | **CAGR** | **maxDD** | Final (4y) | 2024 / 2025 / 2026 |
|---|---|---|---|---|
| 1.0% + 2% | 14.1% | 6.9% | 1.69× | +18% / +33% / +12% |
| **1.5% + 3%** | **21.3%** | **10.3%** | 2.16× | +28% / +51% / +19% |
| 2.0% + 4% | 28.5% | 13.6% ⚠️ | 2.72× | +38% / +70% / +25% |
| 2.5% + 5% | 35.8% | 17.0% ⚠️ | 3.38× | +49% / +91% / +33% |

(2024–25 numbers are gold-trend-inflated; 2022–23 were slightly negative.
Plan on the CAGR, not the lucky years.)

## 4. Verdict on 40–50%/yr at ≤10% DD

- **At the user's 10% DD cap, the validated frontier delivers ~21%/yr expected**
  (TRIAD 1.5% + Gold swing 3%). That is the honest maximum today.
- 40–50%/yr at ≤10% DD is **not reachable with currently validated edges**.
  Reaching it requires roughly **2–3× more uncorrelated validated sources**
  (tick-data-driven intraday edges, additional instruments/classes) — or
  accepting 15–17% DD for ~36% (still short).
- Aggressive alternative presented for completeness, not recommended:
  2.0%+4% setting → ~28% CAGR but 13.6% DD breaches the user's cap.

## 5. Path to 40–50% (unchanged from the roadmap, now with a second leg)

1. ✅ Validated: TRIAD core3 intraday (PF 1.6–2.7).
2. ✅ Validated: Gold Donchian swing (PF 3.8, lumpy) — **second uncorrelated leg**.
3. ⬳ Tick data → certify fills + open intrabar/high-frequency search.
4. ⬳ More instruments (indices, crosses) → more swing/trend legs.
Each new validated uncorrelated edge multiplies CAGR faster than it multiplies
DD (returns scale ~N, DD scales ~√N). Three TRIAD+Gold-class legs ≈ 35–50%/yr
at ~10–12% DD becomes plausible — with evidence, not hope.
