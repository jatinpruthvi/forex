# PR #10 — Corrected ROI Improvement Master Plan

Based on a detailed code review and provenance check of the repository's validation sweeps (sweep1 through sweep8), Python lab findings, and the PR #10 audit documentation, here is the corrected and verified plan to understand and maximize the ROI of the FIVE_M5_EXHAUST.mq5 EA.

> **Note on Provenance**: A previous version of this document incorrectly mixed findings from the TRIAD_R_HS (M1 ORB) strategy with the FIVE_M5_EXHAUST strategy, and included claims unsupported by the repository data. This document has been strictly verified against the actual main branch data.

---

## 1. Verified Configuration Optimizations (Zero Coding Required)

The following tweaks strictly align with the FIVE_M5_EXHAUST frozen configuration and the repository's backtest results.

*   **Drop XAUUSD from the Intraday M5 Fade**: Gold is structurally a trend-following instrument. In the M5 reversal fade, XAUUSD is a drag with a **-0.219R net expectancy** on the held-out TEST window. Removing it from InpSymbols is the mathematically correct choice to preserve your edge. *(Source: findings_broker_and_balance.md)*
*   **Fix the Commission Cost Variable**: Ensure InpCommissionPerLotRT is set exactly to your broker's cost (e.g., **4.50** for Fusion Zero). Leaving it at the 7.0 default on a cheaper broker will force the EA to size your lots too small, leaving money on the table.
*   **Stick to Fixed Fractional Sizing**: Do **not** use compounding sizing for prop firm challenges. The repository's own indings_phase2_speed.md explicitly warns: *"Do not plan around the compounded column."* Compounding yielded 11.94%/month vs 12.60%/month fixed, while suffering **22.6% max drawdown vs 11.7%**. Fixed risk is superior here.

---

## 2. Broker Selection vs. Rollover Exclusion

**Do NOT arbitrarily block the 21:00 UTC rollover hour.** 
Approximately 30.7% of all entries for this strategy occur precisely at UTC 21:00 (the Daily close). While spreads widen significantly during this rollover window, the repository's *validated* answer to this is **broker selection**, not entry exclusion. 
Blocking the 21:00-22:00 window deletes roughly a third of the strategy's volume with zero evidence that the remainder keeps its edge. 

*   **Action**: Use a raw-spread broker with tight overnight conditions (like Fusion Markets Zero or Tickmill VIP) rather than modifying the EA's time filters.

---

## 3. The Gold Donchian Swing Portfolio Addition

While XAUUSD fails as an intraday M5 fade, the FINAL_OPTIMUM_STRATEGY.md file notes an incredibly profitable swing trade portfolio addition.

*   **The Edge**: Daily Donchian breakout (N=55) with a Chandelier exit (2.5x ATR trail). 
*   **The Impact**: Over a 4-year test, this single setup contributed **+,807 (47% of the total portfolio PnL)**.
*   **The Caveat**: This was achieved in only **19 trades**, driven heavily by the exceptional 2024-2025 Gold bull market. *(findings_swing_and_portfolio.md)*
*   **Action**: Building a separate GOLD_SWING.mq5 EA to run alongside the M5 Exhaustion EA is a viable way to capture macro trends, but be aware of the small sample size before relying on it for consistent monthly returns.

---

## 4. Officially Dead Ends (Do Not Waste Time Building)

The PR #9 review and the study arenas definitively killed several concepts. Do not attempt to code or trade these:

*   **M1 Scalping / ORB (Opening Range Breakout)**: A tight 2-5 pip stop results in spread/commission eating the entire edge. At real costs, the PR #9 M1 champion flips from +0.068R to **-1.0259R**, busting a ,250 prop floor with a 100% failure rate. Tightening stops to 0.05 ATR is mathematically impossible to execute in live markets.
*   **Winner Pyramiding / Grid Additions**: Scaling into winning trades universally underperformed the single-entry baseline. The edge is in the initial reversal sweep, not the continuation. 
*   **Fibonacci Progression Sizing**: While it improves mean return, it increases 99th-percentile sequence drawdown to 18%, which guarantees a failure on a prop firm evaluation (-10% hard stop).
*   **Free-Margin Stacking (House Money)**: Opening correlated pairs once the first hits breakeven is a trap. A single macroeconomic shock will gap both trades, bypassing the breakeven stops and doubling your drawdown.
