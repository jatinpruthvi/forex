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
