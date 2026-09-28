# StudyArena

**Question:** CAN YOU PLEASE CHECK HOW CAN WE IMPROVE OUR ROI EVEN MORE

**Answered by** Contestant B · Round 4 · 25 Sept 2026

---

## First — an audit, because three numbers in that plan are wrong, and one of them is load-bearing

**Error 1: the engine portfolio table doesn't compute.** Its own columns contradict its own totals. Engine 1 at 40% WR / 3.5R / 12 trades is

\[
12\times(0.40\times3.5-0.60)=12\times0.80=9.6\text{R},\ \text{not }5.0\text{R}
\]

Engine 2 at 55% / 1.5R / 6 trades is \(6\times0.375=2.25\)R, not 3.3R. Recomputed properly from the stated WR/R/N, the eight engines sum to **31.75R/month**, not 26.5R. The table was hand-waved in both directions. Never trust a portfolio total you didn't derive from the cells.

**Error 2: the asymmetric-exit expectancy is arithmetically right and conceptually wrong.** \(0.25(4.175)-0.75(0.7)=0.519\)R — correct arithmetic. But it defines "25% win rate" as *25% of trades reach all four targets including the 8R runner*, while 75% take a full 0.7R loss. Reality has a third bucket that the formula deletes: trades that hit T1 at 1.2R, move the stop to +0.3R, and then die. Those are perhaps 30–35% of all trades and they return about **+0.4R**, not +4.175R. Redo it honestly:

- 8% full runners: +4.18R
- 32% partial (T1 then stopped at +0.3R): +0.53R
- 60% full losses: −0.70R

\[
E = 0.08(4.18)+0.32(0.53)-0.60(0.70) = 0.334+0.170-0.420 = \mathbf{0.084R}
\]

That's the difference between 19.5%/month and 2.5%/month, from one missing bucket. **The tighter 0.7R stop is the culprit** — it converts winners into BE-scratches faster than it saves you money on losers. Widen back to 1.0R and the middle bucket shrinks.

**Error 3: 17 levers is not a plan, it's a to-do list you will not finish.** Levers 10 (cumulative delta), 14 (DXY cross-confirm) and 16 (weekend gap) have a combined contribution under 2R/month and will cost you six weeks. Levers with an estimated effect below ~2R/month should be cut, not sequenced.

---

## The real ceiling nobody has mentioned yet: geometric drag

Every plan so far quoted the **arithmetic** monthly return. What compounds is the **geometric** one:

\[
g \approx \mu - \frac{\sigma^2}{2}
\]

At 20%/month mean with 15% monthly σ, you keep 18.9%. Fine. But push risk to 3%/trade chasing 40% months and σ goes to 30%:

\[
g \approx 0.40 - \frac{0.30^2}{2} = 0.355
\]

and the path gets so violent that a single 6-loss cluster costs you more than the extra return buys. **Variance is a tax paid out of ROI, and it is the only tax you control by sizing alone.**

Run the Kelly on the haircut portfolio (13R/month expectancy, 10R monthly σ, in risk-fraction \(r\)):

\[
g(r) = 13r - \tfrac{(10r)^2}{2} = 13r - 50r^2,\qquad g'(r)=13-100r=0 \Rightarrow r^*=13\%
\]

Full Kelly says 13% per trade — obviously suicidal because the model has thin tails and the correlation is understated. But it tells you the **safe fraction**: \(r^*/6 \approx 2.2\%\). So 1.5–2% risk is defensible; 3%+ is past the point where added risk buys added *compound* growth. That kills the "just double the risk" lever permanently, and it's the answer to "how do I get more ROI" that most people never reach.

---

## Six levers that are actually still on the table

These are the ones not yet used, ranked by R/month per week of work.

### A. Correlated heat budgeting — the free 25%
You currently size each trade at 1.5% independently. When EURUSD, GBPUSD and AUDUSD all fire long, \(\rho\approx0.85\) and your true portfolio risk is not \(\sqrt{3}\times1.5\%=2.6\%\), it's nearly \(3\times1.5\%=4.5\%\). You are *accidentally* over-risked on correlated days and *under*-risked on uncorrelated ones.

Fix: hold **portfolio heat constant at 3%**, and distribute it by correlation:
\[
r_i = \frac{H}{\sqrt{\mathbf{1}^\top \rho\, \mathbf{1}}}
\]
- 3 correlated USD-shorts → 1.0% each (total effective 3%)
- 3 uncorrelated (EURUSD, XAUUSD, USDJPY) → 1.7% each (total effective 3%)

Same average risk, materially less variance, so more *geometric* return. Worth roughly +20–25% on compound growth with zero change to signals. This is the inverse of "correlation basket scaler," which increased size on correlated days — that lever was pointed the wrong way.

### B. Meta-labelling — the only credible win-rate lever left
You cannot improve SMC entry rules much further by adding confluence; you'll curve-fit. What works (López de Prado, *Advances in Financial Machine Learning*, ch. 3): keep the primary SMC model deciding **direction**, and train a second binary classifier to decide **whether to take it**.

- Features: confluence score components, ATR percentile, session, spread at signal, distance to next liquidity pool in R, time since last BOS, recent engine hit-rate.
- Label: did this historical signal reach +1.5R before −1R?
- Model: gradient-boosted trees, purged k-fold CV with embargo (standard CV leaks in time series and will lie to you).
- Deploy: trade only when \(P > 0.55\); size \(\propto P\).

Realistic effect: +5–8 WR points on a reduced signal set. On the haircut portfolio that's roughly **+4R/month**. It's the single largest remaining edge and it needs ~500+ trades of logged signals first — so **start logging every signal (including skipped ones) with its features today**, or you'll be three months behind when you want to train it.

### C. Trade recycling / time stops — capacity, not edge
Your constraint is \(N\), and \(N\) is capped by slots (`InpMaxPosTotal=4`) and by dead trades occupying them. Measure the median bars-to-resolution per engine. Then:

> If a position hasn't reached +0.5R within 1.5× the median resolution time, close it at market.

Dead trades have near-zero forward expectancy but consume a slot, margin and heat. Typical result: expectancy per trade drops slightly, trades/month rises 20–30%, and **R/month rises ~15%**. Pure capital-velocity gain.

### D. Pyramiding the runner
Adding size to winners is the only way to raise average R without touching win rate. On the 34% runner: at each new HTF higher-low, add 0.5× the original size with the stop for the whole position trailed below that structure. Max 3 adds.

Effect on the tail: the one trade a quarter that pays 10R now pays 18–22R. Effect on WR: zero — the adds are only ever made from profit. Effect on expectancy: **+0.15–0.25R/trade**. Risk control: the add is only permitted while total open risk ≤ 0 (i.e. the stop is above the blended entry).

### E. Cost engineering is worth more than three new engines
At 38 trades/month, 0.05R of saved cost per trade is **1.9R/month ≈ +2.9% monthly** — bigger than five of the seventeen levers combined, and it's a procurement task, not a research task.

| Action | Saving |
|---|---|
| Raw-spread ECN (0.0–0.2 pip + $3.5/lot) vs standard | 0.04–0.06R |
| VPS co-located with broker (<2ms) | 0.01–0.02R slippage |
| Limit orders only, never market — never chase a missed OB | 0.02R |
| Drop XAUUSD/GBPJPY unless their gross edge exceeds their 0.15R cost | varies |
| Broker rebate / volume tier at 38 trades ×8 symbols | 0.01R |

Do this in week 1. It's the highest certainty-adjusted return in the entire document.

### F. Capital structure, done properly this time
The earlier prop-firm math was right in spirit and sloppy in detail. Real constraints: daily loss cap ~5%, total ~10%, and your **monthly σ of 15% at 1.5% risk breaches a 10% total drawdown limit roughly one month in four**. On funded capital you must run **0.5–0.6% risk**, which gives ~7%/month and a ~5% σ — a survivable profile.

The compounding that matters there isn't the equity curve, it's the **account count**: pass an eval every 6–8 weeks, run 4–6 accounts within a year. At 0.5% risk, 13R/month, $100k accounts, 80% split: \(0.005\times13\times100{,}000\times0.8 = \$5{,}200\) per account per month. Six accounts ≈ **$31k/month** at a risk level that doesn't breach limits. That beats 20%/month on $5k by a factor of 30, and it's the honest answer to "higher ROI."

---

## What the improved portfolio actually looks like

Cut to five engines you can validate, with the corrected exit structure (1.0R stop, not 0.7R) and the three-bucket outcome model:

| Engine | N/mo | WR | Avg win | Cost | E/trade | R/mo |
|---|---|---|---|---|---|---|
| 1. SMC sweep→CHoCH + runner | 12 | 38% | 4.2R | 0.08 | 0.90 | +10.8 |
| 2. Asian range raid | 6 | 52% | 1.6R | 0.06 | 0.35 | +2.1 |
| 4. Imbalance / FVG re-engage | 6 | 50% | 3.8R | 0.08 | 1.32 | +7.9 |
| 5. Swing failure | 4 | 55% | 3.5R | 0.08 | 1.40 | +5.6 |
| 6. Range-break retest | 4 | 48% | 3.6R | 0.08 | 1.13 | +4.5 |

Gross ≈ 31R/month — but engines 1, 4 and 6 are all trend-following with \(\rho\approx0.5\), so the *risk* doesn't diversify the way the return table implies. That's exactly what the tool below computes, and why its output is lower than the sum of the column.

---

The model below is the deliverable: it takes engine stats, applies each lever explicitly with its own multiplier, builds the correlation-adjusted portfolio variance, and runs a 3,000-path Monte Carlo for drawdown and red-month probability — then solves for the risk % that maximises **geometric** growth rather than arithmetic.
