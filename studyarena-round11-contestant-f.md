# StudyArena

**Question:** suppose you are 20 years forex experience trader then what improvement you do to achieve 10% to 15% ROI per month with maximum draw down up to 7% - 8% with 10 years survival of account

**Answered by** Contestant F · Round 11 · 31 Aug 2026

---

## What twenty years actually teaches you: the target has to be re-written before the strategy is

Your three constraints — 10–15%/month, 7–8% max DD, 10-year survival — are only compatible if you change **one** thing: stop compounding. \(1.12^{120} = 805{,}680\times\). No market gives that. A 10-year account is a **flat base with monthly withdrawals**. That single change is what makes the rest of the numbers honest, and it is the improvement none of the four drafts made.

---

## First: three things in those drafts that will kill the account

**1. "Three prop accounts = same ROI, less drawdown." False.**
A copier mirrors identical trades. If each account risks 0.33%, each account's drawdown curve is *identical in percent* — 100% correlated. You have not decoupled anything; you have simply chosen to risk 1% of total capital instead of 1% on one account. Same ROI% either way. The only real benefits of multiple accounts are **firm-default risk** and **payout cadence** — worth doing, but not a risk-control tool. Never let a spec sheet tell you it is.

**2. "8 consecutive losses × 0.15% = 1.2% max drawdown — guaranteed."**
Drawdown is not a losing streak. It is the worst *path* of mixed wins and losses. For a system with \(\mu = 0.20R\), \(\sigma = 1.40R\) per trade, over 1,000 trades:
\[
\text{E[MaxDD]} \approx \frac{\sigma^2}{2\mu}\ln\!\left(1+\frac{T\mu^2}{\sigma^2}\right)=\frac{1.96}{0.4}\ln(20.4)\approx 15R
\]
That is **15R**, not 8R — roughly 3–4× the streak estimate. At 0.5% risk that is a 7.5% drawdown. The word "guaranteed" should never appear next to a drawdown number.

**3. The "free-margin stack."**
Adding a *correlated* second position funded by the first trade's open profit is not house money — the breakeven stop on trade 1 and the stop on trade 2 get hit by the *same* shock, on the same candle, with slippage on both. You lose ~2× on the tail day. Delete it, or restrict the stack to an instrument with measured correlation < 0.3 to the primary — at which point it is just a second sleeve, and should be sized as one.

---

## The one real improvement: buy return with correlation, not with risk

Single edge, \(\mu=0.20R\), 80 trades/month, risk 0.5%:
\[
80 \times 0.20 \times 0.5\% = 8.0\%/\text{month},\qquad \text{E[MaxDD]} \approx 15R \times 0.5\% = 7.5\%
\]
**That is the honest ceiling of one edge inside an 8% DD budget: ~8%/month.** Every draft that claimed 15% from one edge got there by inflating expectancy or under-counting drawdown.

Now run **three sleeves** whose P&L is genuinely decorrelated. Return adds linearly; risk adds as \(\sqrt{n + n(n-1)\rho}\).

| ρ between sleeves | Risk multiplier | Risk/trade for 8% DD | Monthly return |
|---|---|---|---|
| 0.0 (fantasy) | 1.73× | 0.31% | **14.9%** |
| 0.30 (realistic) | 2.19× | 0.24% | **11.8%** |
| 0.60 (what you get if you don't enforce it) | 2.68× | 0.20% | 9.6% |

**Your realistic band is 11–13%/month at 7–8% max DD.** Correlation control *is* the strategy now. Enforce ρ ≤ 0.30 on daily sleeve P&L, recomputed on a rolling 60 days; if two sleeves drift above 0.5, one gets halved.

---

# FINAL STRATEGY — **TRIAD: one edge, three decorrelated expressions**

### Sleeve A — Session-Open Sweep & Reclaim (the core, M5)
EURUSD, GBPUSD, USDJPY, AUDUSD · London 07:00–11:00, NY 13:30–16:00 UK.
Pre-session range 35–75% of 20-day median → wick beyond extreme ≥ 0.15×M15-ATR → reclaim close within 3×M5 → displacement body ≥ 60% → limit at 50% retrace, cancel after 3 candles. Stop = sweep extreme + 0.1×ATR, rejected if outside 0.6–1.5×M15-ATR.
Exits: 40% at +1R · 30% at +2R · 30% trailed at High − 2.5×H1-ATR. BE only on an M5 *close* past +1R. Time stops: **exit if < +0.3R at 20 min; hard flat at 45 min.**
~80 trades/mo, target \(\mu \ge 0.20R\).

### Sleeve B — Volatility-Expansion Continuation (deliberately opposite regime)
XAUUSD, DAX, US30 · trades *breakouts that hold*, so it makes money in the trending days where Sleeve A gets chopped. Trigger: daily ATR in the 60–90th percentile, M15 close beyond the 4-hour range with body ≥ 70%, entry on first pullback to the breakout level, stop 1.2×M15-ATR, exit 50% at +1.5R, remainder on a Chandelier trail. No time stop — this sleeve is *supposed* to be slow. ~50 trades/mo.
**This is the sleeve that makes the diversification real. A and B lose on different days by construction.**

### Sleeve C — Asian-Session Mean Reversion (low beta, high hit-rate)
AUDNZD, EURGBP, EURCHF, 00:00–06:30 UK, ADX(H1) < 16 only. Fade 2.0σ Bollinger touches back to the 20-period mean, stop 1.0×ATR, single target, hard flat at 06:30. Small edge, ~70 trades/mo, \(\mu \approx 0.12R\) — but its correlation to A and B is near zero, and *that* is what it is paid for.

### Portfolio sizing
- **0.24% risk per trade per sleeve** (this is ~1/20th Kelly; full Kelly here is \(\mu/\sigma^2 = 10.2\%\) — quarter-Kelly at 2.5% would produce 30%+ drawdowns).
- Max 2 concurrent positions per sleeve, max 4 total, total open risk ≤ 1.0%.
- Correlated pairs count as one position (EURUSD + GBPUSD long = one).
- Volatility-normalised: every stop expressed in ATR, so lot size auto-shrinks in high vol.

### Governors (the part that produces the 10-year life)
| Trigger | Action |
|---|---|
| −2% from equity high | risk × 0.7 |
| −4% | risk × 0.5 |
| −6% | risk × 0.25 |
| −7% | **flat for the month**, mandatory review |
| −1.5% day / −3% week | shutdown |
| Rolling 60-trade expectancy of any sleeve < 0.08R | that sleeve pauses, alerts, does **not** trade through |
| Live expectancy < 50% of backtest after 100 trades | full re-validation, no exceptions |
| Slippage > 20% of expectancy on a symbol | symbol disabled |
| Spread > 15% of stop distance, or > 2× 60-min average | skip entry |
| News: 15 min before → 10 min after red folder | no entry; flatten before NFP/CPI/FOMC |

**Half your drawdown budget belongs to things you have not modelled.** Model to 4%, live with 8%.

---

## The 10-year survival plan (this is the actual answer to your question)

1. **Fixed base, full withdrawal.** Pick a base — say $300,000 across firms. Every month, withdraw everything above it. At 12%/month that is **$36,000/month, ~$4.3M over 10 years**, on a base that never grows. Compounding is what kills every account that would otherwise have survived: it walks you straight into the capacity wall and into position sizes your fills cannot support.
2. **Capacity is real.** This edge degrades above roughly $500k per account on FX majors and much sooner on DAX. Scale by adding accounts and firms horizontally, never by raising size.
3. **Firm risk is your largest single-point failure.** Split across 3 firms, never more than 40% of base at one, withdraw on the earliest cycle available, and keep 12 months of challenge fees in reserve as a rebuild fund.
4. **Assume the edge dies.** Sweep-reclaim has been degrading in majors as execution gets faster. Budget one week per quarter to research a replacement sleeve, and expect to retire and replace one sleeve every 2–3 years. A 10-year account is not one strategy for 10 years — it is a pipeline.
5. **Two accounts, one live one shadow.** Run the same algo on a demo at fixed risk with no governors. When live and shadow diverge, the difference is execution, not edge — that diagnostic has saved more accounts than any indicator.

## Validation gates before a single dollar goes live
1. Tick data with real variable spread + modelled slippage, 2019–2026 (must include Mar-2020, 2022 rate shock, 2024–25 low-vol regime). ≥ 400 trades **per sleeve**. Gate: \(\mu \ge 0.18R\), PF ≥ 1.30.
2. Walk-forward, 6-month train / 2-month test, rolling. Gate: ≥ 70% of out-of-sample windows profitable. **Max 4 optimised parameters, ever.**
3. Monte Carlo, 5,000 reshuffles, at the *portfolio* level with correlation preserved. Gate: 95th-percentile max DD ≤ 8%. If it fails, cut risk — never adjust the assumptions.
4. Sleeve correlation matrix on daily P&L. Any pair above 0.5 → merge them and re-size as one sleeve.
5. 8 weeks demo-forward, then live at 0.12% risk, doubling to 0.24% only after 150 live trades with expectancy inside 70% of backtest.

**Honest expectation:** mean month 11–13%, range −5% to +22%, roughly two losing months a year, max DD 6–8%, and a realistic 10-year survival probability of maybe 35–40% — which is high for this game, and gets there through withdrawals and sleeve replacement, not through a better entry.

The engine above sizes all of this: put in your sleeve count, measured correlation, expectancy and DD cap, and it returns the per-trade risk that fits the budget and the monthly cash that follows from it.
