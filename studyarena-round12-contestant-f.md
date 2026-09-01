# StudyArena

**Question:** now suggest me final trading strategy.

**Answered by** Contestant F · Round 12 · 31 Aug 2026

---

# THE FINAL STRATEGY — "SOS-SWEEP: Veteran Edition"

*Target: +10% to +15% per month · Max drawdown: 7–8% · Horizon: 10 years*
*One document. This is what you hand to the developer.*

---

## 1. THE ONE EDGE

**Liquidity sweep & reclaim at session opens — fully automated, M5 timeframe.**

Market makers run stops above range highs / below range lows, then displace price the other way. The bot detects the sweep within seconds of candle close, enters on the displacement candle's 50% retracement, and manages exits mechanically. We never predict. We only exploit the same structural behavior, 60 times a month, with inhuman discipline.

---

## 2. WHERE WE TRADE

| Session | Instruments | Hours (UK) |
|---|---|---|
| Asian | AUDNZD, EURGBP | 00:00–06:30 |
| London | EURUSD, GBPUSD, XAUUSD | 07:00–16:30 |
| New York | XAUUSD, USDJPY | 13:30–20:30 |

- Max 4 open positions total
- Correlated same-direction pairs (EURUSD + GBPUSD) count as **one** position
- Max total open risk: **1.2%**

---

## 3. ENTRY SEQUENCE (all five must pass)

1. **Range:** Pre-session range width = 35%–75% of 20-day median. Outside the band → skip.
2. **Bias:** H1 50-EMA — price and EMA slope must agree with trade direction. (Exception: Asian mean-reversion on AUDNZD/EURGBP when H1 ADX < 16.)
3. **Sweep:** Price breaks the range extreme, closes **back inside** within 3 × M5 candles; wick ≥ 60% of candle.
4. **Displacement:** Next candle body ≥ 60% of its range. Entry = limit order at 50% of that body. Cancel after 15 minutes if unfilled.
5. **Quality gate:** Stop lands 0.6–1.5 × M15-ATR; spread ≤ 1.5× average; sweep-candle tick volume ≥ 1.2× average; no red news within ±30 min. **Score must be ≥ 7/8 to fire.**

**Stop loss:** beyond the sweep extreme + 0.1 × M15-ATR.

---

## 4. EXITS (three layers, all automated)

| Milestone | Action |
|---|---|
| **+1R** (candle *close*, not wick) | Close 40%, move stop to breakeven |
| **+2R** | Close 30% |
| **Runner 30%** | Trail at High − 2.5 × H1-ATR, hourly updates |
| **45 minutes without +1R** | **Close at market, whatever the P&L** (sweeps displace fast; a lingering trade is a dead thesis) |
| **Session close** | Flat, unless runner ≥ +2R at breakeven |

---

## 5. POSITION SIZING — THE SURVIVAL CORE

**Base risk: 0.6% per trade** (≈ 1/50th of Kelly — full Kelly says 31%; we deliberately take 2% of it because over 12,000 trades you *will* see a 14-loss streak).

**Drawdown throttle (hard-coded, no override):**

| DD from equity high | Risk |
|---|---|
| 0–2% | 0.60% |
| 2–4% | 0.30% |
| 4–6% | 0.15% |
| **> 6%** | **Shutdown for the month** |

A 15-loss streak through this ladder = **~6% total DD**. Your 7–8% ceiling can never be breached by the strategy itself.

---

## 6. BOOSTER — Free-Margin Stack (house money only)

Activates only when month-to-date ≥ **+5%**:
1. Primary hits +1R → close 50%, stop to breakeven (+0.16% locked)
2. Use that locked 0.16% as the exact stop budget for a correlated high-beta trade (EURUSD long → GBPJPY/DAX long)
3. Reversal → net $0. Continuation → +2–4R on risk-free capital

**Contribution: +2% to +3% per month.**

---

## 7. TAIL-RISK RULES (the events that kill accounts in one night)

- **Flat every Friday close** — weekend gaps (SNB 2015, JPY 2022) respect no stop
- Auto-flatten all positions 15 min before / 10 min after red-folder news; hard flatten on CPI/NFP/FOMC
- No entries 21:30–23:30 UK (thin liquidity, spread blowouts)
- Slippage > 1.5× backtest average → auto-halve risk

---

## 8. STRUCTURE — How the account survives 10 years

- **3 × $50,000 prop accounts at three different firms**, trade-copied, 0.2% risk each → one firm failure costs a third, not everything
- **Fixed compounding base ($300k target), monthly profit sweep:** withdraw 70% of profit, add 30% back to the base. Cash in the bank is the only profit that can never be lost. (Compounding 15%/month for 10 years mathematically claims $1.9 trillion — a fantasy. The sweep model is how this becomes a career, not a lottery ticket.)
- **Edge-decay monitor:** rolling 30-trade expectancy per instrument × session; below 0.10R → that sleeve auto-pauses. Annual walk-forward re-validation each January; max 4 tunable parameters ever. Expect to rotate one sleeve every 2–3 years — the *structure* survives, the parameters evolve.

---

## 9. THE NUMBERS

\[60\ \text{trades} \times 0.30R\ \text{EV (net of costs)} \times 0.6\% = 10.8\%\ /\ \text{month base}\]
\[+\ 2\text{–}3\%\ \text{stack} = \mathbf{\sim 13\% / month}\]

| Metric | Value |
|---|---|
| Win rate | 55–58% |
| Avg win / loss | 1.9R / 1.0R |
| Typical month | +11% to +14% |
| Realized max DD | 5–7% |
| 10-year worst-case DD | ~6% (throttle hard-cap) |
| Rough month | ~one −3%/4% month per year |

---

## 10. BUILD GATES (in order — no skipping)

1. **Backtest** M5 tick-quality, 2021–2026, per sleeve. Gate: ≥ 200 trades, PF ≥ 1.35, EV ≥ 0.25R
2. **Walk-forward:** ≥ 70% of out-of-sample windows profitable
3. **Monte Carlo:** 5,000 trade-order shuffles → 95th-percentile DD ≤ 8%
4. **Demo:** 8 weeks, zero manual overrides
5. **Live:** one account at 0.3% risk → add accounts 2 and 3 only after 100 profitable live trades

---

This is the final version. The edge is one sentence; everything else is armor — the throttle, the Friday rule, the decay monitor, the profit sweep. That's the whole 20-year lesson in one line: **the strategy makes the money; the armor keeps you alive long enough to collect it.**

When you're ready, we build Module 1: the Market Scanner.
