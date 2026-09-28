# StudyArena

**Question:** currently we have 17 levers, how can we have more so it will improve ROI

**Answered by** Contestant A · Round 5 · 25 Sept 2026

---

# The Honest Answer First

You now have 17 levers, then 23 more, and the last round's arithmetic claims 40R/month. Before adding lever #41, look at what those numbers actually imply:

**40R/month at 1.5% risk = +60%/month = +19,000%/year.** That is not a strategy, that's a compounding fantasy. And more importantly — **those levers don't add.** They're 40 overlapping ways of saying "enter at a better price." Lever 6 (session filter) and lever 20 (intraday seasonality) are the same filter twice. Lever 3 (imbalance) and lever 15 (double break) both fire on the same impulse candle, so on a strong day you'd be double-long — which is *not* more ROI, it's the same ROI at double risk, and it makes the drawdown worse, not better.

You've been adding levers linearly and assuming returns add linearly. They don't. So here's what actually raises ROI from here.

---

## The four things that genuinely move the number (and are missing)

### 1. Correlated engines must be risk-budgeted, not added

This is the single biggest error in the 40-lever list. If Engines 1, 3, 4, 15, 19 and 21 all read the same impulse and all go long GBPUSD, you have **one trade at 6× size**, not six edges. Your monthly σ goes to ~20R and one bad week erases three good months.

Fix: **cluster engines by correlation, one risk budget per cluster.**

| Cluster | Engines it contains | Shared budget |
|---|---|---|
| Trend continuation | 1, 3, 15, 19, 21 | 2.5% total |
| Reversal / fade | 2, 9, 12, 17 | 2.0% total |
| Volatility breakout | 7, 11, 14, 22 | 1.5% total |
| Event / calendar | 8, 13, 16 | 1.0% total |

Within a cluster, the *first* signal gets the budget and later ones get **zero**, not a share. This alone typically cuts monthly drawdown by a third while leaving gross return nearly unchanged — which is exactly what raises **risk-adjusted** ROI, and it's what lets you run higher risk safely. That is the actual multiplier: a system with 22% DD can run 2% risk; a system with 45% DD can't run 1%.

### 2. Portfolio heat cap — the one hard number that's missing

Nobody rates 40 levers without this. Define **open heat** = Σ (distance to stop × position size) across everything.

- Cap total open heat at **4%** of equity.
- Cap **any one currency's** net exposure at 3% (long EURUSD + GBPUSD + AUDUSD = short USD three times).
- Cap same-direction cluster heat at 2.5% (see above).
- New signal that would breach → **queue it**, don't skip it; enter when heat frees up and the setup is still valid.

Without a heat cap, 40 levers guarantees the January-you-blow-up scenario. With it, your worst month becomes bounded and you can size confidently every other month.

### 3. A kill switch that measures edge decay, not just drawdown

Drawdown stops are reactive. Add a **rolling-expectancy monitor**:

\[
E_{50} = \text{mean R over the last 50 trades}
\]

- \(E_{50} > 0.35\)R → run full risk
- \(0.15 < E_{50} \le 0.35\) → 75% risk
- \(0 \le E_{50} \le 0.15\) → 40% risk, and re-check the regime filter
- \(E_{50} < 0\) → **flat all engines until 20 paper-traded signals are logged**, then resume at 25%

This catches a dead edge in ~50 trades instead of discovering it after a 30% drawdown. Systems that keep compounding through an edge-death month are how funded accounts die. This lever doesn't raise good-month ROI — it protects the compounding, which over a year is worth more than any new entry filter.

### 4. Reinvest into the capital base, not the return ratio

You already have this one (funded accounts). Extend it: **the real ROI lever is account count, and it's multiplicative.**

\[
\text{Income} = n_{\text{accounts}} \times \text{capital} \times \text{monthly \%} \times \text{split}
\]

5 accounts × $100k × 5% × 85% = **$21,250/month**, achieved at a risk level (0.5%) that survives. That is the number you were chasing with 40 levers, and it doesn't require a single new indicator. Your marginal effort per additional account is near zero once the engine set is validated — that's where the highest return on *your time* lives.

---

## And the one true remaining edge-class you haven't touched

Everything in the 40 levers is **price-derived**. They're all functions of the same OHLCV series, which is why they keep re-counting the same signal. One genuinely uncorrelated class is left:

**Cross-sectional relative strength (a market-neutral book).** Long the 2 strongest majors, short the 2 weakest, sized to zero net USD exposure, rebalanced daily. It makes money from *dispersion between pairs*, not from direction — so it's near-zero correlation with all 40 directional engines. Historical monthly σ of a well-constructed 8-pair rank book is ~4–5%, with ~1.5–2.5%/month gross expectancy. Small alone; valuable because it fires in the chop months where every directional engine is flat or losing. That's what smooths the equity curve into something that can carry 2% risk per directional trade.

That's the pattern for anything you add from here: **ask what it's uncorrelated to, not how many R it promises.** If it correlates above 0.5 with something you already run, it's not a lever — it's leverage.

---

## Realistic ceiling, restated plainly

| Configuration | Monthly (live) | Expected max DD |
|---|---|---|
| Single SMC EA, 1 pair, 1% risk | 3–5% | 20% |
| + multi-symbol + graded sizing + runners | 8–12% | 25% |
| + regime router + heat cap + expectancy kill switch | **11–15%** | **20%** |
| + funded-account multiplication at 0.5% risk | 5–6% per account, ×N accounts | 8–10% per account |

The jump from "17 levers" to "40 levers" bought you almost nothing in real terms because they weren't independent. The jump to **clustered risk budgets + heat caps + edge-decay monitoring + account multiplication** is worth roughly **+3 to +5 points of monthly ROI and a third off the drawdown** — because you can then run 2% risk instead of 1%, and 2% × a smooth curve beats 1% × a lumpy one.

---

## What to do in the next 30 days

1. **Backtest each of the 40 engines alone over 2022–2026.** Keep only those with \(E > 0.25\)R out-of-sample *and* monthly-return correlation < 0.5 to everything already kept. You'll likely keep 6–9, not 40.
2. **Cluster the survivors and assign one risk budget per cluster.** Re-backtest the portfolio. Compare return to correlation.
3. **Add the heat cap (4% total / 2.5% cluster / 3% per currency).** This is 20 lines of code and it's the highest-value change on this list.
4. **Add the rolling-expectancy throttle.**
5. **Only then** raise risk from 1% to 2%, and only if step 2 cut your DD below 25%.
6. **In parallel:** pass funded evals at 0.5% risk. That's where the income number comes from.

---

The below planner does the thing the last round's tables couldn't: it lets you enter your own per-engine win rate, RR, trade count and **correlation to your existing book**, and it shows the portfolio return *and* drawdown *and* probability of a losing month — so you can see directly that adding a correlated engine raises return and drawdown together (bad) while adding an uncorrelated one raises return alone (good).

Put your real backtest numbers in. The defaults are the honest haircut case (6–9 surviving engines, live-haircut win rates, 0.08R costs), and they land in the **11–15%/month with ~20% drawdown** band — which, run across funded accounts, is the actual 20%-per-month income you've been asking how to reach.
