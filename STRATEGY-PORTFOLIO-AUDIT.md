# Independent Strategy and Portfolio Audit

## Objective

Evaluate every strategy proposed in this repository and identify the best single strategy or portfolio for:

- 10-15% monthly account return
- 8-9% maximum drawdown
- At least 5 years of account survival, preferably 10 years

This is a design audit, not evidence that any strategy is profitable. The repository contains strategy proposals but no source code, tick data, fill records, backtest reports, walk-forward results, or Monte Carlo output. Every return, drawdown, win-rate, trade-count, and survival figure in the source documents is therefore an assumption until independently reproduced.

---

## 1. Executive verdict

### Best architecture

The strongest design in the repository is the three-regime architecture in `TRIAD-SURVIVE.md`, derived mainly from Round 11 Contestant F and the more conservative parts of Rounds 7, 8, 10, and 12:

1. **M5 session-open sweep and reclaim** for false breakouts in normal volatility.
2. **M15 volatility-expansion continuation** for genuine breakouts in trending/high-volatility conditions.
3. **Single-entry Asian mean reversion** for quiet conditions, with no grid or averaging.

The important edge is not merely having three entry systems. It is that the systems attempt to make money in different regimes and can be separated in time. The portfolio should route a session event either to reversal or continuation; it should not let the two modules fight each other.

### Target verdict

No document proves that 10-15% can be earned every month while keeping the entire 5-10-year path below 8-9% drawdown. That combination cannot be promised.

The best defensible planning bands are:

| Outcome | Defensible target before validation |
|---|---:|
| Ordinary long-run month | 6-10% |
| Strong month | 10-15% |
| Weak/loss month | 0% to -5% |
| Strategy shutdown | 5.5-6% from the closed-equity high |
| Design ceiling | 8%, leaving about 1% for gaps and operational failures |

A 10-12% long-run average might be possible only if live-quality out-of-sample evidence confirms both unusually high trade count and net expectancy. A 15% monthly floor is incompatible with the drawdown and survival requirements.

### Best practical recommendation

Use a revised form of TRIAD, called **TRIAD-R: Regime-Routed Portfolio**, described in Section 6. Do not raise risk to manufacture the target. If the validated portfolio produces only 6-9%, accept that result or increase external capital; do not force 10-15% by increasing leverage.

---

## 2. The target mathematics

The basic relationship is:

`Monthly return ≈ filled trades × net expectancy in R × average risk per trade`

At the `TRIAD-SURVIVE.md` full-tier risk of 0.24%:

| Filled trades/month | Net expectancy needed for 8% | 10% | 12% | 15% |
|---:|---:|---:|---:|---:|
| 100 | 0.333R | 0.417R | 0.500R | 0.625R |
| 150 | 0.222R | 0.278R | 0.333R | 0.417R |
| 170 | 0.196R | 0.245R | 0.294R | 0.368R |
| 200 | 0.167R | 0.208R | 0.250R | 0.312R |
| 250 | 0.133R | 0.167R | 0.200R | 0.250R |

If half-tier signals and drawdown throttling reduce effective average risk to 0.20%, then 170 monthly trades require approximately 0.294R net expectancy just to reach 10% and 0.441R to reach 15%.

### Internal check of the current final specification

The central assumptions in `TRIAD-SURVIVE.md` imply:

| Sleeve | Trades | Net EV | Risk | Expected contribution |
|---|---:|---:|---:|---:|
| A: sweep/reclaim | 70 | 0.25R | 0.24% | 4.20% |
| B: continuation | 40 | 0.22R | 0.24% | 2.11% |
| C: mean reversion | 60 | 0.11R | 0.24% | 1.58% |
| **Total** | **170** | **0.194R weighted** | — | **7.90%** |

Therefore, the current document's own central arithmetic supports approximately **7.9% before throttle drag and missed trades**, not a 9-12% ordinary month. Exceptional runners can create 10-15% months, but they cannot be counted twice if they are already included in average winner/expectancy assumptions.

Increasing risk from 0.24% to about 0.30% would scale 7.9% toward 10%, but it would also scale an assumed 6-8% drawdown toward roughly 7.5-10%. Raising risk enough to target 15% would make the drawdown objective implausible. Risk is not the solution.

---

## 3. Strategy-family evaluation

### Ranking key

- **A:** suitable for the live portfolio after independent validation
- **B:** useful research candidate or optional filter
- **C:** reject as a live return engine for this objective

| Strategy family | Grade | Return potential | Drawdown/tail profile | Diversification value | Verdict |
|---|---|---|---|---|---|
| M5 session-open sweep and reclaim | **A** | Medium-high if the edge survives costs | Defined loss; vulnerable on true breakout days | Core normal-volatility sleeve | Best primary engine |
| M15 volatility-expansion continuation | **A** | Medium with positively skewed trends | False breakouts and event gaps; defined loss | Strongest complement to sweep reversal | Best second sleeve |
| Single-entry Asian mean reversion | **A-** | Low-medium | Clean defined risk, but low EV and occasional range breaks | Good time/regime separation | Use small; no grid |
| London compression breakout | **B+** | Medium | Similar to continuation; can overlap it | Useful entry variant | Fold into Sleeve B, not a fourth sleeve |
| New York continuation | **B+** | Medium | Correlated with London trend and USD factors | Different clock, not always different risk | Use inside Sleeve B after separate validation |
| Tokyo opening-range breakout | **B** | Low-medium | False-breakout risk in thin liquidity | Some session diversification | Incubate only |
| DAX/GER40 cash-open gap fade | **B** | Unproved; likely low frequency | Gap can continue; CFD open/close definition and fills matter | Structurally different, but overlaps London hours | Shadow candidate, not live core |
| H4/weekly trend following | **B+** | Low frequency, convex payoff | Many small losses; overnight gap risk | Potential macro-regime diversifier | Better research candidate than another intraday fade |
| Intermarket filters: DXY, yields, oil | **B** | May improve selection | Data synchronization and causal overfit risk | Filter only, not a return sleeve | Add only if incremental OOS value is proven |
| Capped equal-size grid | **C+** | Many small wins | Negative skew; slippage and regime breaks concentrate loss | Time-separated, but tail cost remains | Single-entry fade is superior |
| Increasing-size grid/martingale | **C** | Attractive until failure | Account-ending negative convexity | None | Ban |
| M1/tick-acceleration sweep scalping | **C** | Backtests may look high | Spread/slippage dominate 3-5 pip stops | Same edge as M5, not diversification | Reject for initial build |
| Spot-FX volume-delta strategy | **C** without futures data | Unproved | Broker tick data is not centralized order flow | None | Do not use as a hard gate |
| EURUSD/GBPUSD statistical-arbitrage spread | **C+/B-** | Potentially useful if professionally modeled | Cointegration breaks; the spread is not bounded | Could diversify direction, not regime failure | Separate research project only |
| Carry trades such as AUDJPY/MXNJPY | **C** | Slow positive carry | Devaluation, intervention, weekend and gap tails | Poor fit for an 8% box | Reject as core |
| Crypto delta-neutral funding capture | **C** | Yield varies | Exchange, basis, liquidation, custody and funding reversal risk | Different market but new tail risks | Keep outside this FX mandate |
| Monday/weekend gap fade | **C+/B-** | Very low frequency | Wide open spreads and jump risk | Some timing diversification | Insufficient as a meaningful sleeve |
| Free-margin/correlated stack | **C** | Can boost good months | Both trades can fail on the same shock; not house money | Increases, rather than reduces, tail concentration | Ban |
| Asymmetric runner on an existing trade | **A-** | Adds positive skew without a new entry | Breakeven is not gap-risk-free | Improves payoff, not diversification | Keep, but count it in expectancy once |
| Prop-account copying | Capital tool only where expressly permitted | More dollars, not more return percentage | Same market drawdown on every copied account | Diversifies firm failure only | Current The5ers rules prohibit coordinated/copy trading between accounts; disable there |
| Fixed capital base and withdrawals | **A** survival tool | Does not create trading edge | Reduces capital exposed to future failure | Essential for multi-year economic survival | Keep |

---

## 4. Why the three selected sleeves fit together

### Sleeve A: false-breakout reversal

The sweep/reclaim is the repository's most consistently specified idea. It has:

- A structural invalidation point beyond the sweep.
- Liquid session windows.
- A cost-aware limit entry.
- A short time-to-thesis that supports a mechanical time stop.
- Positive-skew potential through a runner.

Its main failure regime is a genuine one-way breakout. That is why it cannot be the only edge.

### Sleeve B: accepted-breakout continuation

Continuation is the logical opposite response to the same liquidity event. It performs when:

- Volatility is expanding.
- A breakout closes strongly outside the range.
- The level holds on a pullback.

This is the best diversifier in the repository because it is intended to profit in the regime that damages Sleeve A. It should not fire simultaneously with Sleeve A on the same event.

### Sleeve C: quiet-session single-entry fade

A defined-risk Bollinger/mean-reversion entry on AUDNZD or EURGBP gives time separation from London and New York. It is cleaner than a grid because:

- Maximum loss is known from one position.
- There is no path-dependent accumulation of exposure.
- A regime break causes one stop, not a loaded basket.
- It is easier to test and monitor for decay.

Initially exclude EURCHF. Low historical volatility does not remove central-bank repricing and gap risk, and earlier repository audits correctly identified the 2015-style tail as unsuitable for a mean-reversion basket.

---

## 5. Findings from every repository document

### Round 4

| File | Main contribution | Audit decision |
|---|---|---|
| `studyarena-round4-contestant-b.md` | Session separation and three-sleeve thinking | Keep time separation; reject 6% grid basket. File is truncated. |
| `studyarena-round4-contestant-c.md` | Session map and asymmetric runner | Keep runner concept; grid sizing is incorrect and increasing size is unsafe. |
| `studyarena-round4-contestant-d.md` | Regime classifier, correlation groups, testing discipline | One of the strongest early documents. Keep architecture; replace grid with one fade. |
| `studyarena-round4-contestant-e.md` | Detailed sweep, continuation, and defined-risk grid | Keep directional mechanics and risk groups; do not deploy its grid by default. |
| `studyarena-round4-contestant-f.md` | Portfolio framing and capital structure | Keep regime portfolio concept; reject 5-6% grid, “bounded” stat-arb, and “free” carry claims. |

### Round 5

| File | Main contribution | Audit decision |
|---|---|---|
| `studyarena-round5-contestant-a.md` | Strong critique of prior math and adaptive percentiles | Keep. Its cautious return analysis is more credible than aggressive syntheses. |
| `studyarena-round5-contestant-b.md` | E/F/C hybrid | Too aggressive at 1-1.5% risk; runner and architecture are useful. |
| `studyarena-round5-contestant-c.md` | Conservative hybrid and cleaned runner | Useful direction, but file ends mid-calculation. |
| `studyarena-round5-contestant-d.md` | Short three-shift summary | Reject 1.5% risk and “un-blow-up-able” wording. |
| `studyarena-round5-contestant-e.md` | Best arithmetic audit of the early proposals | Keep its correction of grid math and risk claims. |
| `studyarena-round5-contestant-f.md` | Strong synthesis | Keep small basket critique and correlation logic; ultimately prefer no grid. |

### Round 7

| File | Main contribution | Audit decision |
|---|---|---|
| `studyarena-round7-contestant-a.md` | DAX cash-open gap fade and prop-capital framing | Incubate DAX only; the 70% fill claim is unsupported and text is duplicated. |
| `studyarena-round7-contestant-b.md` | Multiple “ballast” sleeves | Too many heterogeneous risks. Reject crypto funding and free-roll risk increases. |
| `studyarena-round7-contestant-c.md` | Simpler London sweep and structural ROI | Keep simple core; rebates and carry are not a trading edge and add incentives/tails. |
| `studyarena-round7-contestant-d.md` | Conservative sweep, continuation, and single Asian fade | One of the best precursors to final TRIAD. Strong risk and no-grid decision. |

### Round 8

| File | Main contribution | Audit decision |
|---|---|---|
| `studyarena-round8-contestant-a.md` | Detailed single London strategy and external-capital structure | Strong mechanics. Copied accounts increase dollars, not account ROI; payout assumptions are unproved. |
| `studyarena-round8-contestant-b.md` | One sweep edge over three sessions | Useful unification, but free-roll and losing-streak drawdown logic understate path DD. |
| `studyarena-round8-contestant-c.md` | Simplified London sweep | Too simplistic; halving after three losses cannot guarantee sub-10% DD. |
| `studyarena-round8-contestant-d.md` | Conservative single-strategy specification | One of the strongest single-edge documents; realistic 3-6% base expectation. |

### Round 10

| File | Main contribution | Audit decision |
|---|---|---|
| `studyarena-round10-claude-fable-5-high-reasoning.md` | M1 automation and time stop | Keep automation/time-stop idea; reject M1 cost assumptions. |
| `studyarena-round10-claude-opus-5-high-reasoning.md` | Cost gate and explicit state machine | Best Round 10 document. Keep 10x cost gate, limit expiry, logging, and validation. |
| `studyarena-round10-gemini-3-1-pro-preview-high-reasoning.md` | M1 delta/tick scalper | Reject: decentralized spot volume, fixed tiny stops, copied-account ROI error, and false DD guarantee. Text is duplicated. |
| `studyarena-round10-kimi-k3-high-reasoning.md` | Automated scanner and edge monitor | Keep modules; 0.6% risk and streak-only DD estimate are too aggressive. |
| `studyarena-round10-qwen3-8-2-4t-a95b-high-reasoning.md` | Full EA module architecture | Keep structure; reject 0.75% risk, free-margin stack, and combined-risk copy-account framing. |

### Round 11

| File | Main contribution | Audit decision |
|---|---|---|
| `studyarena-round11-contestant-a.md` | Conservative risk, cost realism, 10-year stress process | Strongest conservative single-engine audit. Return target is realistic. |
| `studyarena-round11-contestant-b.md` | Cost/ATR ratio, regime filter, fixed base | Keep cost and regime ideas; reject virtual stops with a broker stop three times wider. |
| `studyarena-round11-contestant-c.md` | Withdrawals and edge-decay monitoring | Keep survival process; 0.8% combined risk and >95% survival claim are unproved. |
| `studyarena-round11-contestant-d.md` | Three decorrelated regime sleeves | Strong conceptual pivot that leads to TRIAD. Keep; validate all correlation claims. |
| `studyarena-round11-contestant-e.md` | M5 choice, tail controls, decay monitoring | Keep these; Kelly calculation/risk label and free-margin stack are unreliable. |
| `studyarena-round11-contestant-f.md` | Path-drawdown correction and three-sleeve TRIAD | Strongest mathematical synthesis in the repository and primary basis for the recommendation. |

### Round 12

| File | Main contribution | Audit decision |
|---|---|---|
| `studyarena-round12-claude-fable-5-high-reasoning.md` | Compact final SWEEP-1 | Good mechanics; 0.6% risk and free-margin stack conflict with 10-year DD objective. |
| `studyarena-round12-contestant-a.md` | Detailed locked SWEEP-1 | Good operational detail; return and “structurally unreachable DD” claims are too certain. |
| `studyarena-round12-contestant-b.md` | Compact EA blueprint | Copying 0.2% across three accounts does not create 0.6% return on one account; return assumptions remain unproved. |
| `studyarena-round12-contestant-c.md` | SR-10 conservative final strategy | Strongest pure-survival proposal; realistically targets 4-8%, not 10-15%. |
| `studyarena-round12-contestant-f.md` | Veteran sweep specification | Useful summary, but repeats the rejected 0.6% risk/free-stack assumptions. |
| `studyarena-round12-qwen3-8-2-4t-a95b-high-reasoning.md` | Most detailed module breakdown | Good implementation map; risk tables conflict internally and free-stack logic is unsafe. |

### Final synthesis documents

| File | Main contribution | Audit decision |
|---|---|---|
| `bolt-TRIAD-SWEEP` | Corrects risk to 0.24% and combines three regimes | Strongest pre-final synthesis, but stated trade counts/EV still require proof. |
| `bolt-TRIAD-SWEEP-2` | Repository-wide comparison and runner/capital discussion | Useful rationale; numerical rankings are not backed by stored tests. |
| `TRIAD-SURVIVE.md` | Locked MT5 build specification | Best current source of truth, with the corrections in this audit recommended before coding. |

---

## 6. Recommended portfolio: TRIAD-R

### 6.1 Shared session-event router

Use one supervisor for each reference-range event:

1. Build the session reference range.
2. Apply hard data, news, spread, cost, correlation, and volatility gates.
3. Route the event:
   - **Sweep of 0.05-0.50 M15 ATR followed by reclaim within three M5 closes:** Sleeve A reversal candidate.
   - **Strong M15 close outside the range, no reclaim, expanding volatility, then a successful pullback:** Sleeve B continuation candidate.
   - **Neither:** no trade.
4. Sleeve A and Sleeve B may not trade opposite interpretations of the same symbol/session event.

This makes the core portfolio logically complete: fade a rejected breakout, follow an accepted breakout, and do nothing when evidence is ambiguous.

### 6.2 Sleeve A: session-open sweep/reclaim

Start with:

- EURUSD and GBPUSD at London; select only one same-USD-direction signal.
- USDJPY and XAUUSD at New York only after separate validation.
- M5 signal, M15 ATR normalization, H1 context.
- Limit at 50% of displacement body; cancel after three M5 bars.
- Stop beyond sweep plus 0.10 M15 ATR; valid distance 0.60-1.50 ATR.
- 40% at +1R, 30% at +2R, 30% ATR/structure runner.
- Breakeven only after an M5 close beyond +1R.
- Test a 30-60 minute time-stop plateau; use 45 minutes only if it is stable out of sample.

### 6.3 Sleeve B: volatility continuation

Start with:

- XAUUSD and GBPJPY.
- Add GER40/US30 only as separately tested CFD strategies with broker-specific contract, session, spread, and gap data.
- Daily volatility in a validated expansion band.
- M15 close beyond a four-hour range, body at least 70%, followed by pullback to the breakout level.
- Stop based on M15 ATR.
- 50% at +1.5R and 50% on an H1 Chandelier/structure trail.
- No forced 45-minute stop; this sleeve is intentionally slower.

### 6.4 Sleeve C: Asian defined-risk fade

Start with:

- AUDNZD and EURGBP only.
- H1 ADX below a validated low-volatility threshold.
- Two-standard-deviation Bollinger touch, rejection, and M15 RSI extreme.
- One limit entry, one ATR stop, target at the mean.
- One instrument at a time.
- Hard flat at 06:30 Europe/London.
- No grid, no second leg, no averaging, and initially no EURCHF.

### 6.5 Hard gates versus scoring

Do not let a score make a failed safety condition optional.

The following must always pass:

- Correct session and timezone
- Valid volatility/range regime
- Exact signal sequence
- Stop geometry
- Estimated round-trip cost no greater than 0.10R
- Spread within tested range
- No prohibited news exposure
- No stale data or abnormal latency
- No correlated risk conflict

A quality score may rank two otherwise valid signals. It should change position size only after out-of-sample evidence proves that score buckets have monotonically different expectancy. A 7/8 trade must never be allowed merely because the missing point is the news or cost gate.

---

## 7. Risk architecture for 5-10 years

### Initial and validated risk

| Stage | Risk per accepted trade |
|---|---:|
| Shadow/demo | No capital risk |
| First 50 live trades | 0.10-0.12% |
| Next 100-150 error-free trades | 0.15-0.20% |
| Fully validated ceiling | **0.24%** |

The 0.24% value is a ceiling, not a starting entitlement. Final allocation should equalize measured sleeve risk rather than blindly assign identical risk to every signal.

### Portfolio limits

- Normal maximum aggregate open risk: **0.72%**.
- Absolute technical cap: 1.0%, including pending orders that can fill together.
- One position per correlated currency/factor group.
- Maximum two open trades in the same session.
- Include floating P&L and gap/slippage reserve in all loss limits.

### Drawdown throttle

| Drawdown from highest closed equity | Action |
|---|---|
| 0-2% | Validated risk |
| 2-4% | Half risk |
| 4-5.5% | Quarter risk |
| 5.5% or more | No new entries; formal investigation |
| 8% | Emergency design boundary, not an ordinary stop |

Do not automatically restore full risk because a new month begins. Restore it only after execution is healthy, rolling expectancy is positive, and the equity/strategy recovery rule has been met.

Suggested hard limits:

- Daily loss: 0.75-1.0%
- Weekly loss: 2.0-2.5%
- Strategy shutdown: 5.5-6.0%
- Operational reserve: at least 1% below the 8-9% maximum

No stop can guarantee the maximum during a market gap, broker outage, bad tick, rejected close, or extreme slippage.

---

## 8. Five-year and ten-year survival design

### Five years

Five-year survival is plausible only if:

- Risk remains at or below the validated ceiling.
- No grid, martingale, correlated stack, or virtual-stop widening is introduced.
- All costs and fills are monitored live.
- Profits are regularly removed from the trading venue.
- Underperforming instrument-session combinations are paused.

### Ten years

A single fixed parameter set is not a credible ten-year strategy. Ten-year survival requires a research and replacement process:

1. Track expectancy, profit factor, slippage, MAE/MFE, and trade frequency per instrument/session/sleeve.
2. Use a shadow account with fixed risk and no equity throttle to separate edge decay from risk-governor effects.
3. Run annual full walk-forward revalidation and quarterly health checks.
4. Maintain one challenger strategy in shadow mode.
5. Expect to replace or materially revise a sleeve every 2-3 years.
6. Split broker/prop-firm counterparty exposure and reconcile positions independently.
7. Use a fixed capital base and withdraw 50-70% of profits rather than compound indefinitely.

Profit withdrawal protects accumulated wealth. It does not improve the percentage drawdown of the trading strategy itself.

---

## 9. Validation required before choosing the final return target

### Historical test

- Prefer bid/ask tick data from at least 2012-2026 where reliable data exists.
- Include SNB 2015, Brexit 2016, COVID 2020, 2022 rate shocks, and low-volatility periods.
- Use real session clocks and historical daylight-saving transitions.
- Include spread, commission, swap, rejected/missed limits, and conservative slippage.
- Use historical news timestamps without look-ahead.
- Test every instrument-session combination separately before combining it.

### Minimum sleeve gates

- At least 300 combined out-of-sample trades per sleeve; 500 is preferable for the higher-frequency sleeves.
- Net out-of-sample profit factor at least 1.30.
- Net expectancy at least 0.18R for A/B and at least 0.10R for C.
- At least 65-70% of walk-forward windows profitable.
- OOS expectancy at least 60% of in-sample.
- No single year or instrument responsible for more than 35% of portfolio profit.
- Neighboring parameter values remain profitable.

### Cost and failure stress

The combined portfolio must remain profitable with:

- 2x spread
- 2x modeled slippage
- At least 10% of profitable limit entries missed
- Stop fills occasionally 0.25R worse
- Random quote gaps and platform outages
- Sleeve correlation stressed toward 1 during crisis windows
- Broker-specific CFD gaps for indices and gold

### Survival simulation

Use at least 10,000 block-bootstrap or regime-preserving simulations. Simple random trade shuffling is insufficient because it destroys losing clusters and cross-sleeve correlation.

Set final risk so:

- 99th-percentile simulated 5-year maximum drawdown is no more than 8%.
- 99th-percentile simulated 10-year maximum drawdown is no more than 8%, if ten-year survival is the requirement.
- Probability of breaching the actual account/firm limit remains below the chosen tolerance after gap and execution stress.

If the risk required to reach 10% monthly fails the drawdown gate, reduce the return target. Never weaken the simulation to justify the return.

---

## 10. Out-of-the-box improvements worth pursuing

### A. Champion/challenger sleeve pipeline

Do not add every plausible edge to the live account. Keep TRIAD-R as the champion and run one challenger in shadow mode. The best initial challengers are:

1. Slow H4/weekly trend following, because it may provide crisis convexity.
2. GER40 cash-open gap fade, if broker-specific open/close and fill data support it.
3. Tokyo opening-range breakout, independently from London/NY results.

A challenger replaces a decayed sleeve; it does not automatically become a fourth live risk source.

### B. Volatility-targeted sleeve budgets

Allocate risk from measured sleeve volatility and drawdown contribution, not equal nominal risk per trade. A frequent low-EV sleeve can consume more risk budget than a less frequent high-EV sleeve even when every trade risks 0.24%.

### C. Correlation stress, not only correlation measurement

A rolling 60-day correlation estimate is noisy and may fail in crises. In addition to live estimates, calculate portfolio limits under correlation equal to 1. The account must still avoid catastrophic loss when diversification temporarily disappears.

### D. Separate account ROI from personal-capital ROI

If the real objective is cash income, a larger external allocation can generate more dollars from a safer 4-8% account strategy. This changes return on personal fees/capital, but it does not turn copied 8% account returns into 16% account returns. Include failed challenges, denied payouts, rule changes, and firm failure in the economics.

### E. Execution alpha before signal complexity

The most credible improvement may come from reducing friction rather than adding indicators:

- Broker-specific spread curves by minute of day
- Fill probability model for limit entries
- Slippage and partial-close monitoring
- VPS failover and broker reconciliation
- Per-symbol cost-to-stop ratio

Saving 0.03-0.05R per trade across a high-frequency portfolio can matter more than another fragile signal filter.

---

## 11. Final recommendation

Build and validate **TRIAD-R**, with:

- M5 sweep/reclaim as the primary normal-volatility engine.
- M15 accepted-breakout continuation as the opposite-regime engine.
- Small, single-entry Asian mean reversion as the time-separated ballast.
- One shared router so reversal and continuation cannot conflict.
- 0.24% maximum validated trade risk, reached only through phased deployment.
- 5.5-6% strategy shutdown and at least 1% operational reserve.
- No grid, martingale, M1 delta scalping, free-margin stack, virtual-stop widening, carry, or crypto funding inside the portfolio.
- A fixed capital base, regular withdrawals, counterparty diversification, a shadow account, and a permanent replacement-sleeve research pipeline.

### Honest expected outcome

Until actual tests exist, plan for **6-10% ordinary months and 10-15% strong months**. Promote 10% to a long-run base expectation only if live-quality OOS results demonstrate either:

- Approximately 170 filled trades/month at at least 0.245R net expectancy and near-full 0.24% average risk, or
- Approximately 200 filled trades/month at at least 0.208R net expectancy and 0.24% average risk,

while the portfolio still passes the 99th-percentile 5/10-year drawdown test.

If those conditions are not met, the correct response is a lower return target or more external capital—not more risk.
