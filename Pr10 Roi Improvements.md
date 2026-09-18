# PR #10 — Comprehensive ROI Improvement Master Plan

Based on an exhaustive deep-dive audit of all validation sweeps (`sweep1` through `sweep8`), Python lab findings (`findings_*_lab.md`), the Study Arena proposals, and the challenge strategy docs, we have identified massive ROI potential that was either left in the Python research phase, missed during parameter sweeping, or disabled in the final EA.

The current `FIVE_M5_EXHAUST.mq5` / `TRIAD_R_HS.mq5` EA produces a validated **~15%/month** baseline (at 0.50% risk), but this can be pushed significantly higher.

Here is the exhaustive, data-backed plan to maximize ROI, ranked by implementation effort and impact.

---

## 1. Immediate Configuration Tweaks (Zero Coding Required)

These improvements simply require changing the inputs in your MT5 terminal. 

*   **Drop XAUUSD from the Intraday M5 Triad**: Gold is structurally a trend-following instrument. In the M5 reversal fade, XAUUSD is a drag with a **-0.219R net expectancy** on the held-out TEST window. Dropping it raises the 4-year CAGR from 26.1% to 34.6% and drops the minimum balance requirement from $16,101 to $1,565.
*   **Fix the Commission Cost Variable**: Ensure `InpCommissionPerLotRT` is set exactly to your broker's cost (e.g., **4.50** for Fusion Zero). Leaving it at the 7.0 default silently undersizes 55% of trades by 6%, bleeding ROI.
*   **Enable the H1 EMA Bias Filter**: The EA already contains `InpRequireH1EmaBias`. Set it to `true`. Python labs confirm that trading strictly in the direction of the H1 EMA50 avoids low-probability counter-trend sweeps and significantly improves the win rate.

---

## 2. High-Impact Logic Ports (Proven in Python, Missing in MQL5)

The Python research (`findings_filter_training_lab.md` and `findings_m1_lab.md`) found several highly profitable filters that were **never ported to the MQL5 EA**. Implementing these in the EA is your highest-value development work.

> [!TIP]
> **The "God Combo" (Session + Quality + Gold EMA)**
> Applying these filters in the Python validation increased 4-year PnL by **+28% (CAGR 26.1% → 31.1%)** while dropping drawdown from 4.5% to **3.7%**.

*   **Pair-Specific Cutoffs**:
    *   *EURJPY*: Hard cutoff at `10:00` session time.
    *   *USDJPY*: Require conviction quality `≥1.05`.
*   **The "D0a" Variant Upgrades**:
    *   Tighten the stop buffer to **0.05 ATR** (down from 0.10 ATR).
    *   Extend the valid session window to **13:30**. 
    *   *Impact*: +$207 PnL on a single pair, drops Phase 1 ETA by ~60%.
*   **Compounding Sizing (Equity-based)**: The EA currently defaults to fixed fractional sizing on the initial balance. Changing to size off current equity adds **+$875** to the 4-year final stack (though it slightly increases sequence risk, it is ideal for personal accounts).

---

## 3. The Big Missing Piece: XAUUSD Donchian Swing Leg

While XAUUSD fails as an intraday M5 fade, it is incredibly profitable as a multi-day swing trade. The `findings_swing_and_portfolio.md` and `FINAL_OPTIMUM_STRATEGY.md` files reveal a **Gold Donchian Swing** strategy that is completely missing from the MQL5 EA.

*   **The Edge**: Daily Donchian breakout (N=55) with a Chandelier exit (2.5x ATR trail). 
*   **The Impact**: Over the 4-year test, this single setup contributed **+$1,807 (47% of the total portfolio PnL)** from only **19 trades**. 
*   **Action**: Build a separate `GOLD_SWING.mq5` EA. Combining the intraday FX Triad with this Gold swing leg is the mathematically proven path to crossing **20-30% CAGR** at ≤10% drawdown. 

---

## 4. Untapped Research Opportunities (Sweep Blind Spots)

The 8-stage "Speed Lab" validation sweeps missed a few critical parameter spaces. Exploring these could unlock massive hidden ROI.

> [!WARNING]
> **Rollover Session Exclusion (The "Spread Killer")**
> 43.8% of all entries land in the **20:00–00:59 UTC** rollover window. During this time, spreads widen 3x to 8x. Because the strategy uses wide stops, this silently eats your edge. **Implement a hard session filter that blocks entries between 21:00 and 22:00 UTC.**

*   **ATR Period Optimization**: The entire sweep architecture hardcoded the ATR period to `14`. Sweeping shorter periods (`7` or `10`) would make the sweep/reclaim threshold much more reactive to sudden volatility spikes, potentially catching higher-quality exhaustion bars.
*   **Re-sweep SA=1.0 (Stop ATR)**: In Sweep 6 (the first "honest" fill sweep), the `SA=1.0` and `SA=1.5` bands were partially skipped or filtered too early. A tighter stop (if it survives spread costs) drastically improves Risk:Reward.
*   **Signal Rate Regime Check**: The strategy currently generates a very low signal rate (~3.1%). You must acquire 2019-2023 tick data to verify if this is a structural flaw or just a side-effect of the heavily trending 2024-2025 gold bull market.

---

## 5. Officially Dead Ends (Do Not Waste Time Building)

The study arenas definitively killed several concepts. Do not attempt to code or trade these:

*   **M1 Scalping / ORB (Opening Range Breakout)**: A tight 2-5 pip stop results in spread/commission eating **40-65% of the 1R risk**. At real costs, the PR #9 M1 strategy busts a $2,250 floor in 7 days.
*   **Winner Pyramiding / Grid Additions**: Scaling into winning trades (adding at 0.5R or 0.75R) universally underperformed the single-entry baseline. The edge is in the initial reversal sweep, not the continuation. 
*   **Fibonacci Progression Sizing**: While it improves mean return, it increases 99th-percentile sequence drawdown to 18%, which guarantees a failure on a prop firm evaluation (-10% hard stop). Stick to fixed fractional risk.
*   **Free-Margin Stacking (House Money)**: Opening correlated pairs (e.g., long EURUSD, long GBPJPY) once the first hits breakeven is a trap. A single macroeconomic shock will gap both trades, bypassing the breakeven stops and doubling your drawdown.
