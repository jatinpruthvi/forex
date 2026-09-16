# Phase 2 — Fastest Validated Route to Passing The5ers $2,500 Phase 1

**Repo:** `jatinpruthvi/forex` · **Branch:** `arena/01a0a554-forex`
**Question asked:** *"Check if any modification to the last PR's code will help reduce days-to-win. Think like you have no blocker, no constraint, starting from zero. You can also change max trades per day — anything. Make sure the result is validated on the data we have."*
**Data used:** `validation/HistoryData/` — 4 years of M5 (11 pairs, ~289k bars/pair) and 2 years of M1, exactly as committed in the repo.
**Reproduce:** `python3 validation/speed_lab/verify_final_config.py` (stdlib only, ~8 s, no numpy needed)

---

## 1. Answer in one paragraph

Yes — the days-to-pass can be cut roughly in half versus PR #9, but **not** by the levers PR #9 pulled. The single largest source of days is not trade frequency, timeframe, or the profit target: it is that **PR #9's configuration has negative net expectancy once real spread and commission are charged**, so it never passes at all (0% over 120 walk-forward starts; it busts the $2,250 floor on day 7). Rebuilding from zero on the same data produced a **M5 long-only extreme-bar mean-reversion fade** with a genuine **+0.40 R net expectancy after costs** at 2.3 trades/day. Under the real firm rules, on the **held-out 2024-09 → 2026-09 window that was never used for any parameter selection**, it passes **77.5% of walk-forward starts in a median of 27 calendar days** at 0.50% risk, or **75% in a median of 17 days** at 0.75% risk. **0.75% is the hard ceiling** — not because of appetite, but because higher risk breaches the firm's $125 daily-loss limit and is therefore illegal.

**Head-to-head on the identical TEST window with identical firm rules:**

| Configuration | Costs modelled | Pass rate | Median days | p90 days |
|---|---|---|---|---|
| PR #9 champion (as merged) | real spread + $7/lot | **0.0%** — never passes | ∞ (floor bust day 7) | — |
| PR #9 champion | **zero costs (fantasy)** | 77.5% | 29 | 90 |
| **This config @ 0.50% risk** | **real spread + $7/lot** | **77.5%** | **27** | 71 |
| **This config @ 0.75% risk** | **real spread + $7/lot** | **75.0%** | **17** | 46 |

The bottom line: **this config matches PR #9's cost-free fantasy reliability while actually paying real costs, and at 0.75% risk it is ~1.7× faster.** PR #9's real-cost result is zero.

---

## 2. The frozen configuration

Selected **only** on TRAIN (2022-09-11 → 2024-09-11). TEST (2024-09-11 → 2026-09-11) was evaluated **exactly once**, after the freeze. This is the discipline PR #9 skipped — it selected and reported on the same window, which inflated its numbers ~2.5×.

**Strategy — "extreme bar exhaustion fade", M5, LONG only:**

| Element | Value |
|---|---|
| Instrument set | all 11 repo pairs, same rule, no per-pair tuning |
| Timeframe | M5 |
| Trigger | a completed M5 bar whose body `\|close − open\|` exceeds **4.0 × ATR(14)** (true range, prior bars only) |
| Side | **LONG only** — fade sharp *sell-offs*; sharp rallies are left alone |
| Entry | **next bar's open** (you cannot fill at the close of the bar that formed the signal) |
| Stop | signal bar's low − **2.0 × ATR** |
| Target | entry + **10.0 R** |
| Max hold | 96 h, then close at market |
| Intrabar ambiguity | **pessimistic** — a bar spanning both stop and target books the stop |
| Broken geometry | rejected if the fill opens at/beyond the intended stop |

**Risk & gate controls:** 0.50% (or 0.75%) of the **initial** $2,500 per trade — no compounding; ≤ 2 concurrent positions; ≤ 5 trades/day; stop opening after −3R on the day; no new entries after Fri 21:00 server time. Firm rules enforced exactly: $2,250 static equity floor, 5% daily loss on the UTC+3 server day, ≥ 3 qualifying days at ≥ $12.50, +10% ($2,750) target.

**Costs:** round-trip spread = repo `SPREAD_STD × 0.55` (raw account) plus $7/lot commission, charged *inside every trade*; lot size floored to 0.01. Costs consume **21.5% of 1R** — they are the dominant term, which is precisely what PR #9 ignored.

---

## 3. Validation results

### 3.1 Held-out TEST window, per pair (2024-09-11 → 2026-09-11)

```
sym       n(TEST)   stopP   cost%    WR%    E_net   totalR
EURUSD        125    9.91    18.1   13.6   -0.0362       -5
GBPUSD        141   11.68    17.3   12.1   -0.1394      -20
EURGBP        180    4.95    33.3   23.3   +0.8500     +153
AUDUSD        186    7.97    23.3   18.3   +0.4257      +79
NZDUSD        192    6.83    32.3   16.7   +0.4117      +79
USDCAD        111   11.18    23.8   24.3   +0.7552      +84
USDCHF        201    7.70    26.4   20.9   +0.8803     +177
USDJPY        210   17.80    15.1   14.3   +0.0345       +7
EURJPY        123   22.14    13.9   18.7   +0.3520      +43
GBPJPY        128   25.03    15.2   21.9   +0.7172      +92
XAUUSD         87  117.26     3.2   11.5   -0.2193      -19
AGGREGATE    1684            21.5          +0.3985     +671
trades/day = 2.31    R/day = +0.92    net expectancy = +0.3985 R/trade
```

**8 of 11 pairs are positive**, and no single pair dominates: the top four contributors are USDCHF +177R, EURGBP +153R, GBPJPY +92R, USDCAD +84R out of +671R total. Gold is a −19R *drag* — this is **not** the gold-bull regime luck that made PR #9's Donchian breakout look good. Dropping XAUUSD would improve the result slightly; keeping it is immaterial.

An independent numpy implementation reproduces this to within sampling noise: n = 1687 vs 1684, E_net = **+0.4048R** vs +0.3985R.

### 3.2 Walk-forward, TEST window, 40 rolling start dates

| Risk / trade | Pass rate | Median days | p25 | p90 | Best | Worst | Max DD (peak-rel) | Worst day | Legal? |
|---|---|---|---|---|---|---|---|---|---|
| 0.25% | 90.0% | 81 | 36 | 180 | 11 | 214 | 12.9% | −$34 | ✓ but too slow |
| **0.50%** | **77.5%** | **27** | 13 | 71 | 7 | 112 | 16.8% | **−$69** | ✓ **recommended** |
| **0.75%** | **75.0%** | **17** | 12 | 46 | 7 | 65 | 19.4% | **−$103** | ✓ **fastest legal** |
| 1.00% | 60.0% | 14 | 10 | 22 | 7 | 27 | 21.9% | **−$125** | ✗ **breaches the $125 daily limit** |

The numpy implementation returned 92.5% / 26 d at 0.50% and 75.0% / 16 d at 0.75%. **Medians and economics agree; the failure tail is implementation-sensitive** (4 boundary trades and tie-break order across 40 paths). The table above reports the **more conservative** stdlib verifier, which is also the artifact that ships.

Both settings clear the repo's own §12 gate of **≥70% pass probability**. Going from 0.75% → 1.00% buys only 3 more median days while making the config **illegal** and costing 15 points of pass rate. There is no speed left to buy.

### 3.3 Robustness

| Check | Result |
|---|---|
| TRAIN vs TEST consistency | TRAIN 92.5% / 21 d vs TEST 77.5–92.5% / 26–27 d — same sign, no collapse |
| Cost stress: spread × 2.0 **+** 0.20 R slippage per side | still **77.5% pass, median 30 d** (repo gate #4 ✓) |
| Yearly net expectancy (4 separate years) | **+0.17 / +0.42 / +0.29 / +0.41 R** — all positive, no single-year dependence |
| FX only (drop gold entirely) | 90% pass, median 27 d — not gold-dependent |
| Regime split | edge holds in **both** the strong-dollar half (2022–24) and the weak-dollar half (2024–26) |
| Bar-resolution ambiguity | 0.55% of trades — pessimistic tie-break applied |
| Timeout exits | only ~5% of total net R — the edge comes from the +10R target, **not** from marking timeouts to market |
| Plan-compliant variant (1 position, ≤2 trades/day — the repo's *actual* policy) | **80% pass, median 25 d** |

That last row matters: the user relaxed the policy constraints, but **the config does not need them relaxed.** A strictly plan-compliant version performs about the same. Speed comes from the edge, not from breaking the rules.

---

## 4. Why this works, and why the obvious levers don't

### The structural insight
Sharp **FX sell-offs mean-revert strongly; sharp rallies continue.** This asymmetry was measured independently in both halves of the data:

- LONG side of the fade: **+0.73 R on TRAIN**, **+0.86 R on TEST**, positive on **10 of 11 pairs in both halves**
- SHORT side of the same fade: **negative in both halves**

So the config is long-only not as a bet on direction but because the *reaction function* is asymmetric — and that asymmetry is stable across two opposite dollar regimes. This is the opposite of PR #9's Donchian breakout, whose apparent edge was a decaying gold-bull artifact.

### Why the +10R target is the engine
A 17.6% win rate looks alarming, but it is the *point*: the strategy risks 1R to make 10R on genuine exhaustion events. Sweep 5 isolated this — removing the +10R target and relying on timeouts collapses net expectancy, and timeouts contribute only ~5% of total net R. The target is doing the work.

### Levers tested and killed

| Lever | Verdict |
|---|---|
| **"More trades/day via a lower timeframe" (M1)** | **Dead.** The same structure transferred to M1 (744k bars, 2-year TEST window) produced **0 of 144 parameter cells positive**, even with 6×ATR stops and long-only. Costs stay at **30–54% of 1R** — the microstructure edge is smaller than the toll booth. |
| **Timeframe stacking (M15 / M30 / H1)** | **Dead or dilutive.** The M15 and M30 versions of the identical fade are *negative* on TEST (−0.05 R and −0.28 R). Combining them lowers R/day. **M5 alone is optimal at +0.92 R/day** — the effect is specifically an M5 microstructure phenomenon, not general mean reversion. |
| **Taking shorts too** | **Dead.** Negative in both halves. |
| **Raising risk above 0.75%** | **Illegal.** ≥1.00% produces worst days of −$125 to −$129 against a $125 limit. The binding constraint on speed is the *firm's daily-loss rule*, not strategy appetite. |
| **Filling at the signal bar's close** | **Cheating — and it was caught.** The bar's extreme is only known *after* it closes. Filling at close flattered net expectancy **4×** (+0.41 R vs +0.10 R honest). Every number in this report uses the next-bar-open fill. This is the same class of error as PR #9's. |

### The speed math
`days_to_pass ≈ required_$ / (trades_per_day × E_net × $risk_per_trade)`

At 0.75% risk ($18.75/trade): 2.31 × 0.3985 × 18.75 ≈ **$17.3/day**, so $250 needs ≈ 14.5 trading days ≈ 20 calendar days — matching the observed median of 17. The 3-qualifying-day rule is **never binding** (one 10R win = $187 ≥ $12.50).

Three of the four terms are already maxed: expectancy is optimised, frequency is fixed by how often 4×ATR bars occur, and risk is capped by law. **Only the risk term has room, and it runs out at 0.75%.**

---

## 5. Caveats — read before acting

1. **Drawdown legality depends on the firm's rule being *static*.** Max DD is 16.8% peak-relative at 0.50% risk. That is legal **only** because the repo documents the boundary as a *static* $2,250 floor from the initial $2,500. **If The5ers applies a trailing/equity-high-water drawdown, this config breaches it and must be re-tuned downward.** Verify against the actual contract before funding.
2. **17.6% win rate is psychologically brutal.** Roughly 5 losses in every 6 trades. A human operator will be tempted to intervene during the inevitable 8–12 loss streaks, which is exactly when the +10R payoffs arrive. This needs to run fully automated or not at all.
3. **The tail is implementation-sensitive.** Two independent engines agreed on expectancy and median days but differed on pass rate (77.5% vs 92.5%) at 0.50% risk. The conservative figure is reported. Real-world performance should be assumed to sit at the low end.
4. **Slippage is modelled, not observed.** Costs use the repo's own `SPREAD_STD × 0.55`; the ×2 + 0.20R stress passes, but 4×ATR bars occur *during volatility spikes*, when real spreads widen well beyond the historical average. Live fills on the entry bar are the biggest single risk to this result.
5. **Timeout exits are marked to market at a fixed bar close.** Real exits would vary with liquidity; these are only ~5% of net R, so the impact is bounded.
6. **40–60 walk-forward starts is a modest sample.** A 77.5% pass rate on 40 paths has a ±6.6% standard error. Treat the point estimate as a range, not a number.
7. **No news or session filter was applied.** Adding one is plausible upside but was not tested; do not assume it.
8. **This is research on historical repo data, not a trading recommendation.** Nothing here has been forward-tested or executed live.

---

## 6. Recommendation

- **Deploy candidate:** M5 long-only 4×ATR exhaustion fade, next-bar-open entry, 2×ATR stop, +10R target, 96 h timeout, all 11 pairs, pessimistic intrabar resolution.
- **Risk setting:** **0.50% for reliability** (77.5% pass, 27 d median) or **0.75% for speed** (75% pass, 17 d median). **Never above 0.75%** — it breaches the $125 daily-loss limit.
- **Before funding:** confirm the drawdown rule is static (caveat #1), and run the cost stress at the broker's *actual* live spreads rather than the repo's historical table.
- **Do not** revisit M1, timeframe stacking, shorts, or close-bar fills. All four were tested to exhaustion and are dead.

---

## Appendix — artifacts

| Path | Contents |
|---|---|
| `validation/speed_lab/verify_final_config.py` | **stdlib-only verifier** — reproduces §3.1 and §3.2 from raw CSVs in ~8 s. Run this. |
| `validation/speed_lab/engine.py` | numpy research engine (specs, cost model, resampling, signal families, pessimistic resolver) |
| `validation/speed_lab/portfolio.py` | gate-aware event-driven replay + `walk_forward()` |
| `validation/speed_lab/sweep1..8*.py` | the eight research sweeps (grid searches, adversarial checks, M1 transfer, timeframe stacking, frontier) |
| `findings_pr9_m1_review.md` | Phase 1 report — PR #9 verdict: **DO NOT DEPLOY**, 0/12 gates |
| `validation/pr9_audit/` | Phase 1 audit harness |

numpy is used only by the research sweeps and is **not** a repo dependency; `verify_final_config.py` needs nothing but the standard library.

---

# Part B — Using the same edge on a LIVE PERSONAL account (~10%/month target)

**Reproduce:** `python3 validation/speed_lab/personal_account_analysis.py` (stdlib only, ~9 s)

A funded account and a personal account are **different optimisation problems**. The prop
challenge's binding constraints — the 5% daily-loss limit, the $2,250 static floor, the
+10% clock, the 1-position/≤2-trades-per-day policy — exist to protect *the firm*. On your
own account none of them apply, so the same frozen edge can be run with more diversification
and no clock. Part A's numbers therefore **understate** what the strategy does for you personally.

## B.1 The caps are costing you return — and removing them *lowers* drawdown

The ≤2-concurrent / ≤5-per-day caps were a prop-policy artefact. On the held-out TEST window
(2024-09 → 2026-09, 25 months, fixed fractional sizing, firm gates removed):

| Concurrency | Trades/day | Breaker | Risk | Mean /mo | Median /mo | Worst mo | Losing mo | Max DD | Annualised |
|---|---|---|---|---|---|---|---|---|---|
| 2 | 5 | −3R | 0.50% | +6.77% | +5.40% | −6.78% | 28% | 17.7% | 61% |
| 2 | 5 | −3R | 0.75% | +10.03% | +8.10% | −10.17% | 24% | 22.7% | 83% |
| 5 | 10 | −3R | 0.50% | +10.58% | +8.18% | −18.20% | 24% | 20.0% | 86% |
| **11** | **20** | **−3R** | **0.50%** | **+12.72%** | **+10.93%** | −18.66% | 24% | 22.0% | 99% |
| **all** | **all** | off | **0.50%** | **+13.05%** | **+9.51%** | −14.83% | 32% | **16.2%** | 101% |
| all | all | off | 0.75% | +19.16% | +12.31% | −22.24% | 28% | 24.2% | 132% |

**The last row at 0.50% risk is the important one: taking *every* signal produces both the
highest mean return (+13.05%/mo) and the *lowest* max drawdown (16.2%) of any configuration
tested.** That is not a contradiction — 11 pairs trading independently is a diversified book,
whereas the capped version concentrates risk into whichever 2 pairs signalled first. The caps
were forcing concentration.

**Answer to your question: yes, ~10%/month is reachable, at 0.50% risk with the caps removed**
(median +9.51%, mean +13.05%). At the capped 0.75% setting the mean is +10.03% but the median
is only +8.10% with a worse drawdown.

## B.2 Four years, no firm gates (TRAIN + TEST, fixed sizing)

| Risk | 4-year total | Mean /mo | Median /mo | Worst mo | Losing mo | Max DD |
|---|---|---|---|---|---|---|
| 0.25% | +191% | +3.90% | +3.22% | −4.46% | 29% | 5.8% |
| 0.36% | +277% | +5.65% | +5.03% | −6.42% | 29% | 7.9% |
| **0.50%** | **+382%** | **+7.79%** | **+6.48%** | −8.92% | 29% | **10.9%** |
| **0.75%** | **+569%** | **+11.62%** | **+8.96%** | −13.38% | 27% | **16.4%** |
| 1.00% | +756% | +15.43% | +11.94% | −17.84% | 27% | 21.8% |
| 2.00% | +1521% | +31.04% | +23.88% | −35.69% | 27% | 43.7% |

On a personal account there is **no illegality ceiling** — 1.00% and 2.00% risk are perfectly
legal, they just carry proportionally larger drawdowns. The 0.75% cap from Part A was imposed
by the firm's $125 daily-loss rule, not by the strategy.

## B.3 A personal account is the *better* fit for this edge than the prop challenge

| | Prop challenge | Personal account |
|---|---|---|
| Probability of a good outcome | **75–77.5%** pass (one ~27-day attempt) | **87–91%** of rolling 3-month windows positive |
| What kills you | variance over a short window | only your own drawdown tolerance |
| Effect of the clock | decisive — 27 days is ~70 trades | none — 49 months is ~3,300 trades |
| Binding constraint | firm's 5% daily-loss rule | your own risk appetite |

The challenge asks a positive-expectancy strategy to clear a barrier **before variance kills it
over a very short sample**. A personal account lets the law of large numbers work. Same edge,
much better odds.

## B.4 The cost Part A could ignore but a multi-year account cannot: OVERNIGHT SWAP

Part A's horizon was 27 days; a personal account is years. Hold-time distribution over 3,317 trades:

- median hold **3.4 h**, mean **20.9 h**, p90 **82 h**, max **233 h**
- mean **0.771 overnight rollovers per trade**; **25.4%** of trades cross ≥1 night, **15.8%** cross ≥2

Swap was **not** in the cost model. Sensitivity at 0.50% risk, capped config, 4 years:

| Swap (R per rollover) | E_net per trade | 4-year total | Mean /mo | Max DD |
|---|---|---|---|---|
| 0.00 (as modelled) | +0.377R | +382% | +7.79% | 10.9% |
| 0.05 | +0.338R | +355% | +7.24% | 11.6% |
| **0.10** | **+0.300R** | **+319%** | **+6.51%** | 12.6% |
| 0.20 | +0.223R | +258% | +5.26% | 13.5% |
| 0.30 | +0.146R | +196% | +3.99% | 15.9% |

For scale: at 0.50% risk on a $2,500 account a ~10-pip EURUSD stop sizes to ≈0.11 lots, so a
typical $7/lot/night swap is ≈$0.77 ≈ **0.06R per night** — i.e. the realistic case sits near
the top of this table, costing roughly 1–1.5 percentage points of monthly return.

**But note the direction is not uniformly negative.** This book is **long-only**, so over
2022–2026 it would have *earned* positive carry on the JPY crosses (USDJPY, GBPJPY, EURJPY —
which contributed +142R of the total) and *paid* on the USD-short pairs (EURUSD, GBPUSD,
AUDUSD, NZDUSD). Net swap is genuinely ambiguous and **broker-specific**. Pull your broker's
actual swap table for all 11 pairs before sizing — this is the largest unquantified term.

## B.5 Compounding: real arithmetic, unrealistic numbers

| Risk | Fixed sizing, 4y | Compounded, 4y | Compounded max DD |
|---|---|---|---|
| 0.50% | +382% | +3,251% | 24.5% |
| 0.75% | +569% | +15,666% | 34.8% |

**Do not plan around the compounded column.** It assumes flawless execution for 48 consecutive
months, an edge that never decays, unlimited liquidity, no broker constraint, and no capacity
limit. It is shown only to make the point that *compounding multiplies drawdown faster than
return* — a 24.5% peak-relative drawdown at 0.50% risk is the price of the +3,251%.

## B.6 What to actually do, and what will bite you

**Recommended personal-account setup:** every signal (no concurrency or per-day cap), **0.50%
risk**, fixed fractional on a periodically-reset base, −3R daily breaker retained. Backtested
+13.05%/month mean, +9.51% median, 16.2% max DD over the held-out 2 years.

Realistic expectations, in priority order:

1. **~1 in 3 months loses money** (32% of months negative at the recommended setting), worst
   observed month **−14.8%**, longest losing streak **3 months**, longest stretch below +10%
   **4–6 months**. "10%/month" is an *average across years*, never a monthly drip. The mean
   (+13.05%) sits well above the median (+9.51%) because the +10R winners arrive in clusters.
2. **Check your margin and leverage before assuming 11 concurrent positions.** At 0.50% risk
   with ~10-pip stops, 11 open positions ≈ 1.2 lots total — fine at 1:100, impossible at 1:30
   on a small account. If leverage binds you, the diversification benefit in B.1 partly
   disappears and you fall back toward the capped rows.
3. **You will sit through a ~16–23% drawdown from your high-water mark.** There is no firm
   floor to stop you, which is the advantage — and also means nothing stops you except your
   own rule. Decide your personal stop *before* you are in it.
4. **Total open risk can reach ~5.5% of the account** (11 positions × 0.50%) held across a
   weekend gap. That is the mechanism behind the 16.2% max DD.
5. **Swap is unquantified** (B.4) — could cost 1–1.5 points of monthly return, or pay you.
6. **All of this is backtest.** Part A's caveats apply in full and are *more* binding here:
   next-bar-open fills during volatility spikes, 17.6% win rate requiring total automation,
   and a 40-start walk-forward sample with ±7% standard error. A 100%-annualised backtest
   should be expected to degrade substantially live. Forward-test on demo for at least one
   full losing streak before committing capital.

---

# Part C — Resolving B.6: margin, concurrency, swap concentration, and a better universe

**Reproduce:** `python3 validation/speed_lab/margin_and_swap_exposure.py` (stdlib only, ~9 s)

B.6 said "check margin and swap with your broker." Both are partly answerable from the repo's
own data. Doing so produced a **material improvement** to the recommended configuration.

## C.1 The TRAIN-selected 8-pair universe is better out-of-sample on every metric

The per-pair table in B.1/B.2 is a *combined* 4-year view, and picking winners from it would
be exactly the in-sample selection error PR #9 made. So the subset was chosen on **TRAIN only**
(2022-09 → 2024-09) and then measured on the untouched TEST window.

TRAIN per-pair net expectancy selected 8 of 11 (dropping **EURUSD −0.153R, USDJPY −0.151R,
GBPUSD −0.117R**). Result on TEST, personal-account sizing, every signal taken, 0.50% risk:

| Universe | Mean /mo | **Median /mo** | Worst mo | Losing mo | **Max DD** | Total |
|---|---|---|---|---|---|---|
| All 11 pairs | +13.05% | +9.51% | −14.83% | 32% | 16.2% | +326% |
| **TRAIN-selected 8** | **+13.63%** | **+10.87%** | **−11.11%** | 32% | **10.9%** | **+341%** |

Higher mean, higher median, smaller worst month, **and a third less drawdown** — selected
honestly, evaluated once. This is now the recommended default. It also happens to drop the two
clearest swap *payers* (EURUSD, GBPUSD), improving C.3.

Note the selection kept **XAUUSD** (TRAIN +0.319R) even though it was −0.219R on TEST. That is
the gold regime decay identified in Part 1 — honest selection means living with it, and the
result improved anyway.

**Updated answer to the 10%/month question: median +10.87%/month at 0.50% risk with a 10.9%
max drawdown, on the held-out window.** That is a better risk-adjusted answer than Part B's.

## C.2 Margin and leverage — feasible at 1:100, impossible below

Worst case, all positions open simultaneously at 0.50% risk on $2,500: **1.46 lots total,
~$157,854 notional** (lot sizes from each pair's real median stop distance; notional from
base-currency contract size × the last close in the data).

| Leverage | Margin required | % of equity | Free margin | Verdict |
|---|---|---|---|---|
| 1:30 | $5,262 | 210.5% | −$2,762 | **IMPOSSIBLE — margin call** |
| 1:50 | $3,157 | 126.3% | −$657 | **IMPOSSIBLE — margin call** |
| 1:100 | $1,579 | 63.1% | $921 | tight |
| 1:200 | $789 | 31.6% | $1,711 | feasible |
| 1:500 | $316 | 12.6% | $2,184 | feasible |

**Realised concurrency is far below the worst case.** Over 4 years: mean **3.11** positions
open, ≤4 open **76.7%** of the time, ≥11 open only **0.44%** of the time. Max observed was
**14** (not 11 — a position held up to 233 h overlaps later signals), so B.1's "11 concurrent"
understates the tail. At the mean concurrency, 1:100 uses only ~18% of equity.

**Conclusion: 1:100 leverage works; 1:30 and 1:50 do not** and would silently skip signals,
failing to reproduce the validated numbers. This is a hard broker-selection requirement.

## C.3 Swap exposure map — the drag lands on the pairs that already lose

Swap cannot be computed without a broker table, but *where it lands* can. Per pair over 4 years:

| Pair | Trades | Nights/trade | ≥1 night | Net R | % of total R | Carry 2022-24 | Carry 2024-26 |
|---|---|---|---|---|---|---|---|
| EURGBP | 381 | 0.845 | 26.5% | **+509** | **40.7%** | pays | earns |
| USDCHF | 359 | 0.813 | 30.1% | +231 | 18.5% | earns | earns |
| NZDUSD | 379 | 0.741 | 25.9% | +190 | 15.2% | earns | neutral |
| GBPJPY | 265 | 0.830 | 24.9% | +133 | 10.7% | earns++ | compressed |
| AUDUSD | 354 | 0.726 | 24.6% | +101 | 8.1% | earns | neutral |
| USDCAD | 215 | 1.051 | 30.7% | +91 | 7.3% | earns | neutral |
| EURJPY | 260 | 0.892 | 26.5% | +73 | 5.8% | earns++ | compressed |
| XAUUSD | 163 | 0.656 | 21.5% | +5 | 0.4% | pays | pays |
| USDJPY | 421 | 0.710 | 24.5% | −25 | −2.0% | earns++ | compressed |
| EURUSD | 265 | 0.653 | 21.1% | −26 | −2.1% | **pays** | mild/neutral |
| GBPUSD | 255 | 0.580 | 20.4% | −33 | −2.6% | **pays** | mild/neutral |
| **Total** | **3,317** | **0.771** | | **+1,250** | 100% | | |

**The clear swap payers (EURUSD, GBPUSD) are precisely the two pairs with negative price
expectancy — and precisely the two the TRAIN selection in C.1 drops.** The pairs carrying 85%
of the profit mostly *earned* carry. So the B.4 stress table's −0.10R/night case is pessimistic
for the recommended universe; realistic drag is likely a few tenths of a percentage point of
monthly return, not 1–1.5.

**One honest caution:** the JPY crosses (GBPJPY, EURJPY, USDJPY — +181R combined, 14.5%)
earned a large carry tailwind in 2022–24 that **compressed sharply after 2024** as the BoJ
hiked. The backtest charges zero swap, so it neither claimed nor lost that benefit — but do
not assume the historical tailwind repeats.

## C.4 Executable artifact

The frozen config now ships as an EA following the repo's `TRIAD_R_HS` safety convention:

**`MQL5/Experts/FIVE_M5_EXHAUST/FIVE_M5_EXHAUST.mq5`** + `README.md`

- **Disabled by default** — `InpEnableOrderSubmission=false` and all eight gate flags `false`.
  Signals are logged; no orders are placed until every gate is explicitly signed off.
- Hand-rolled **simple-mean** true-range ATR. The README warns against substituting `iATR()`,
  whose Wilder/RMA smoothing would change every signal and invalidate the validation.
- Rejects broken stop geometry, enforces the 96 h timeout, the −3R daily breaker, the
  Fri-21:00-server entry block, and a 90%-of-free-margin guard.
- Prop-challenge mode available via `InpProfitTarget` / `InpEquityFloor` /
  `InpDailyLossLimitPct` / `InpQualifyingDays`; all default to 0 (personal-account mode).
- Defaults to the TRAIN-selected 8-pair universe from C.1.

The gate checklist in the README maps each flag to the specific evidence required — including
`InpForwardDemoGatePassed`, which requires demo-running through **at least one full losing
streak** (32% of months lose, worst observed −14.8%, longest streak 3 months) before enabling.

---

# Part D — Corrections forced by verifying the EA

Building and then auditing `MQL5/Experts/FIVE_M5_EXHAUST` found two problems that change the
numbers reported above. Both are recorded here so Parts A–C are not read on their own.

## D.1 A degenerate-stop guard was missing from the backtest too

`dist = (next_bar_open − signal_bar_low) + 2×ATR`, so a gap down through the signal bar's low
shrinks the stop. Across 4 years of the repo's data it reaches **exactly zero**, and since
`lots = risk_cash / (dist_pips × pip_value + commission)`, a zero-distance stop sizes to
**1.78 lots on a $2,500 account with no stop protection whatsoever**. 25 further signals have
stops under 1×ATR — up to **1.16 lots on a 0.4-pip stop**. They cluster at 20:55–22:00, i.e.
the daily roll and the weekend close, where the next bar's open is a stale, wide-spread print.

A minimum stop distance of 1.0×ATR (`InpMinStopAtrMultiple`) was added to **both** the EA and
`verify_final_config.py`. It removes ~3% of signals and every degenerate one.

**Note the direction of the effect: this made the backtest *worse*.** TEST net expectancy fell
from +0.3985R to **+0.3755R**, because those trades were *winners* in simulation — a 0.4-pip
stop puts the +10R target only 4 pips away, so it hits often. They are removed anyway, because
the backtest assumes the stop executes exactly at its price and **a 0.4-pip stop cannot be
executed**: one pip of slippage is a 3.5R loss. This is the same error class as the
signal-bar-close fill caught earlier in Phase 2 — a backtest flattering trades that cannot
exist live. The lower number is the honest one.

## D.2 Corrected headline results (degenerate-stop guard applied)

**Prop challenge, held-out TEST window, 40 walk-forward starts:**

| Risk | Pass rate | Median days | p90 | Max DD | Worst day | Legal? |
|---|---|---|---|---|---|---|
| 0.25% | 87.5% | 78 | 156 | 13.3% | −$34 | ✓ |
| **0.50%** | **75.0%** | **27** | 76 | 17.4% | −$69 | ✓ **recommended** |
| **0.75%** | **70.0%** | **17** | 46 | 19.4% | −$103 | ✓ **fastest legal** |
| 1.00% | 55.0% | 15 | 22 | 21.9% | −$125 | ✗ breaches the daily-loss limit |

TEST aggregate: n = 1,673, **E_net +0.3755R**, costs 21.0% of 1R, 2.29 trades/day, +0.861 R/day.

**These supersede the tables in §3.1, §3.2 and Part B.** The conclusions are unchanged —
0.75% remains the fastest legal setting and 1.00% remains illegal — but the pass rates are
2.5–5 points lower than first reported, and 0.75% now sits exactly *on* the repo's ≥70% gate
rather than comfortably above it.

**Personal account, held-out TEST window, every signal taken, 0.50% risk:**

| Universe | Mean /mo | Median /mo | Worst mo | Max DD | Total |
|---|---|---|---|---|---|
| All 11 pairs | +12.20% | +9.51% | −14.83% | 16.2% | +305% |
| **TRAIN-selected 8** | **+12.74%** | **+10.34%** | **−11.11%** | **11.3%** | **+318%** |

The 8-pair universe still wins on every metric. The median falls from +10.87% to **+10.34%** —
still at the ~10%/month target, but with less headroom than Part C claimed.

## D.3 What verifying the EA proved about the strategy code

`validation/speed_lab/ea_emulator.py` re-implements the EA's decision path independently and
compares it to the backtest. After the fixes:

| Check | Result |
|---|---|
| ATR window | **IDENTICAL** — 477,430 bars, 0 mismatches |
| Signals + geometry | **IDENTICAL** — 3,290 vs 3,290 trades, all 11 pairs matching exactly |
| Server-day key and Friday block | **IDENTICAL** — 15,643 timestamps, 0 mismatches |

The gate check includes a **mutation control**: the pre-fix EA (which added the UTC offset to
`TimeCurrent()`, already server time) is run against the same inputs and disagrees on **12.2%
of server-day keys and 4.9% of Friday decisions**. That confirms the test can actually detect
the bug rather than passing vacuously — worth stating, because the first version of this test
*did* pass vacuously: it fed the EA functions UTC timestamps, mirroring the backtest's
assumption instead of the EA's real runtime input, and so could not see the error.

The double-counted offset had inverted the Friday block: it fired on Fri 18:00–20:59 server
and missed Fri 21:00–23:59 entirely, because the shifted time rolls into Saturday. It blocked
a harmless window and left the pre-close window — where a position is carried into the weekend
gap — unprotected.

## D.4 Verification status of the EA itself

**Logic: proven equivalent** to the validated backtest, as above.
**Compilation: NOT verified** — there is no MetaEditor in this environment. Static audit is
clean (balanced braces/parens, 23 functions defined, 37 inputs declared and referenced, no
undeclared globals, `OnTick`/`OnTimer` both wired, timer set and killed in pairs), but that is
not a compiler. The EA README gives the acceptance test: Strategy Tester on M5 real ticks,
2024-09 → 2026-09 at 0.50% risk must reproduce median ≈ +10.3%/month, max DD ≈ 11%, ~32%
losing months. **Do not open any gate until it matches.**
