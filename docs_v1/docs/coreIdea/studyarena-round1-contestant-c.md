# StudyArena

**Question:** I want to create forex EA using Smart Money Concepts which have 20% ROI per month.

FYI - 
it  CAN  be run on multiple symbol AND ALL ACCEPTED TIMEFRAME

**Answered by** Contestant C · Round 1 · 25 Sept 2026

---

Breakdown for a SMC-based EA targeting 20% monthly ROI

Assumptions you must define explicitly
- Account size: $X → target monthly profit = 0.2X
- Leverage: L:1 (risk control per trade)
- Risk per trade: R% of account equity (e.g., 1–2%)
- Max open trades (concurrent): N
- Symbols: list (EURUSD, GBPUSD, USDJPY, etc.)
- Timeframes: list (M15, H1, H4, D1)

Key SMC logic to code
1) Liquidity pools (Order Blocks, FVGs, SMAs 200/50, horizontal S/R)
2) Break & Re-test confirmation (price closes outside pool then re-tests and rejects)
3) Stop-hunt filter (avoid trades right after a spike close)
4) Confluence: 2/3+ SMC signals across chosen timeframes
5) Dynamic SL/TP: at least 1× ATR(14) away; TP at nearest liquidity pool or risk:reward ≥ 2:1

Risk management blueprint
- Position size per trade:  
  \[
  \text{Units} = \frac{R\% \cdot \text{Equity}}{\text{ATR}_{14} \cdot \text{pips\_to\_SL} \cdot \text{contract\_size\_multiplier}}
  \]
  Example (round lot):  
  - Equity = $10 000, R = 1%, ATR(14) = 20 pips, SL = 20 pips  
  - Usd/lot for EURUSD ≈ $10 per 1 pip → contract multiplier = 0.0001 × 100 000 = 10  
  \[
  \text{Units} = \frac{0.01 \times 10 000}{20 \times 10} = 0.05 \text{ lots}
  \]
- Only trade if total notional exposure ≤ 30–50% of equity.
- Auto-close if monthly PnL reaches +20% or −5% (hard stop).

Trade filter (pseudo-MQL5 logic you can copy)
- On new bar of chosen timeframe T:
  - Identify last Order Block or strong S/R zone within last 10 bars.
  - Check higher timeframe (T*2) trend bias.
  - Wait for price to break zone, then re-test and form rejection wick (pin bar/candle close beyond wick).
  - Only enter if ATR volatility is not spiking (e.g., ATR(14) not > 1.5× avg ATR of last 30 bars).
  - SL: just beyond zone or 1.5× ATR; TP: nearest liquidity cluster or ≥ 2:1 RR.
  - Skip if last trade within X minutes on same symbol (cooldown).

Multi-symbol scheduling (avoids overtrading)
- Run 1 trade per symbol; stagger entries by symbol hash modulo 3 (e.g., EURUSD → minute % 3 = 0 → enter 00:00, 01:20, 02:40 UTC).
- Only enter if open trades < N and total risk ≤ limit.

Performance target math
- To hit 20% monthly with 1.5% risk/trade and ~50% win rate:
  \[
  \text{Required RR} = \frac{\ln(1.2)}{\ln\left(1 + w \cdot RR - w - l \cdot RR\right)} \text{ (approx. solve)} \quad \text{or use rule-of-thumb} \\
  \text{Effective RR} \gtrsim 2:1 \text{ with } w \gtrsim 55\%
  \]
  If you run ≈10–12 trades/month per symbol with 55% win rate and 2:1 RR → expected monthly return ≈ 20–25%.

Minimum viable code skeleton (Python/MQL5-style structure)
- OnTick:
  - For each symbol/timeframe pair in your list:
    a. Detect SMC zone (OB/FVG/S/R).
    b. Confirm break + re-test + trend bias.
    c. Compute SL/TP.
    d. If no open trade on symbol and total risk OK → place order.
    e. Manage SL/TP, trail if desired.
- Metrics logger: record entry/exit, PnL, RR, win/loss, drawdown per symbol.

Backtesting checklist before live
- Out-of-sample split (e.g., 2019–2021 train, 2022–2024 test).
- Walk-forward optimization of SL/TP multipliers and ATR thresholds.
- Validate for slippage ≥ 2 pips and spread cost per trade.
- Stress-test in low-liquidity sessions (Asian close).
- Ensure calendar-event filters (NFP/BoJ/CAD) are disabled or penalized.

Execution constraints
- Broker must allow multi-symbol, multi-timeframe strategy and variable lot sizing.
- Enable tick-by-tick accounting (not just daily equity).
- Daily drawdown limit: −3% → reduce lot size by 50% for next trade.

What to send me next
- Your broker type + trading platform (MT4/MT5/TradingView/Python).
- Exact list of symbols and timeframes.
- Your starting capital and risk per trade.
I will return a ready-to-import EA code template and the exact risk/lot calculations for your specs.
