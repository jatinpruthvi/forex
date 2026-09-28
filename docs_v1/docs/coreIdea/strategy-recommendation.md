# 📊 Complete Strategy Analysis & Recommendation — StudyArena (All 5 Rounds)

**Generated:** 27 Sept 2026  
**Based on:** 13 StudyArena `.md` files across 5 rounds (3 contestants each)  
**Goal:** Forex EA using Smart Money Concepts targeting 20% ROI/month

---

## 🧠 Overview of the Discussion Arc

| Round | Question Asked | Key Insight Gained |
|---|---|---|
| Round 1 | Build SMC EA for 20% ROI | Math says you need ~25 setups/month; multi-symbol is mandatory |
| Round 2 | Focus on strategy, not code | You need a **portfolio of engines**, not one EA |
| Round 3 | How to improve ROI further | Pyramiding, cost reduction, tiered Kelly sizing, TF cascade |
| Round 4 | How to improve ROI even more | Audit of math errors, geometric drag, execution quality, prop capital |
| Round 5 | Even more levers (40+ total) | More levers ≠ more ROI if they're correlated; risk budgeting is the real multiplier |

---

## 🏆 Best Strategy — Synthesized Master Plan

> **Winner blend: Contestant B (Round 2) + Contestant A (Round 3) + Contestant B (Round 4) + Contestant A (Round 5)**  
> These contestants showed the most mathematical rigor, corrected each other's errors, and converged on the most honest and actionable architecture.

---

## 🔢 Step 1: Fix the Arithmetic First

> *(Contestant B, Round 2 — the most underrated insight)*

The whole 20%/month target decomposes into 4 levers:

```
Monthly % = N (setups) × E (expectancy in R) × r (risk %)
```

| Lever | Cheap Move | Effect |
|---|---|---|
| **N setups** | 1 pair → 8 pairs | ×6–8 more trades |
| **W win rate** | 40% → 45% via grading | ×1.5 |
| **R avg win** | Fixed TP → runner to HTF pool | ×1.7 |
| **r risk %** | 1% → 1.5–2% (properly sized) | ×1.5–2× |
| **C costs** | Retail spread → Raw ECN | +0.1R/trade saved |

> **Key truth: Entry signal quality is the hardest lever. Setup count, sizing, and exits are the fastest ROI levers.**

---

## 🏗️ Step 2: The Engine Portfolio (5 Uncorrelated Engines — Not 40)

> Contestant A Round 5 proved adding correlated engines = more risk, not more ROI.  
> Keep engines that are **genuinely uncorrelated** (correlation < 0.5).

| # | Engine | Edge Harvested | Fires When | Target R/mo |
|---|---|---|---|---|
| **1** | SMC Core: HTF Bias → Sweep → CHoCH → OB/FVG | Institutional flow confirmation | London/NY overlap, trending | **+8–10R** |
| **2** | Asian-Range Liquidity Raid | Stop clusters above/below 00:00–06:00 range swept at London open | 07:00–10:00 server time daily | **+3–5R** |
| **3** | Imbalance / FVG Re-Engagement | Impulse → pullback into gap → re-engage | Any trending day | **+5–7R** |
| **4** | Swing Failure (Failed Breakout) | Retail stops swept, price re-enters range | When breakout candles close back inside | **+3–4R** |
| **5** | Mean Reversion at HTF Extremes | Price at weekly OB / 2.5σ from VWAP | Range-bound periods where Engine 1 is silent | **+3–4R** |

**Combined realistic target (live, haircut): 22–30R/month → 15–20% at 1.5% risk**

---

## 🧩 Step 3: The SMC Core Logic (Engine 1) — Best Parameters

> Based on Contestant A's EA in Round 1 (most complete implementation), with Round 3 refinements.

```
Symbols:        EURUSD, GBPUSD, USDJPY, AUDUSD, USDCAD, XAUUSD, GBPJPY, EURJPY
Entry TF:       M15 (ideal balance of signal frequency vs. spread cost)
HTF Bias:       H4 (3 TF steps up)
Fractal:        2 bars each side
Sweep Lookback: 12 bars
Risk %:         1.5% (A-grade), 1.0% (B-grade), 0.5% (C-grade)
RR:             3.0 (minimum)
Partial Exit:   50% at 1.5R → move SL to breakeven
Trail:          ATR × 2 after BE
Daily Stop:     4% daily loss cap
Max DD:         25% equity hard stop
Session:        06:00–20:00 server (London + NY focus)
Max Pos/Sym:    1
Max Pos Total:  4
```

---

## 🚪 Step 4: The Asymmetric Exit Ladder (Corrected)

> *(Contestant B, Round 4)*  
> Round 3 proposed a 0.7R stop. Round 4 Contestant B correctly audited this and showed it creates too many breakeven scratches. Use **1.0R stop** with staged exits.

```
Hard Stop:   1.0R
Target 1:    1.5R → Close 25%, move SL to +0.3R (secured profit)
Target 2:    3.0R → Close 25%, move SL to +1.0R
Target 3:    First opposing liquidity pool → Close 25%
Runner:      Trail behind HTF swing lows/highs until structure breaks → 6–10R
```

**Expectancy with honest 3-bucket model (Contestant B, Round 4):**

```
8%  full runners:                           +8.0R avg
32% partial (hit T1, stopped at +0.3R):    +0.4R avg
60% full losses:                           -1.0R

E = 0.08(8) + 0.32(0.4) - 0.60(1.0)
  = 0.64 + 0.13 - 0.60
  = +0.17R/trade × 25 trades = ~4R/month base
  + runners elevate this to 10–12R/month
```


---

## 📊 Step 5: Setup Grading System

> *(Contestant B, Round 2 — most actionable)*

**Score each signal 0–10 before entering:**

| Confluence Factor | Points |
|---|---|
| HTF (H4/D1) bias aligned | +2 |
| Swept a significant liquidity pool (Asian H/L, PDH/PDL, equal highs/lows) | +2 |
| CHoCH with displacement candle (>1.5× ATR body) | +2 |
| Entry zone is unmitigated + has FVG inside it | +1 |
| Clean liquidity target ≥3R away, no opposing OB in path | +2 |
| Killzone timing (London 07–10, NY 13–16 server) | +1 |
| **Penalties:** News within 30 min, spread >1.5× normal, Friday after 15:00 | −3 each |

**Risk Tier Assignment:**

| Grade | Score | Risk % |
|---|---|---|
| A | 8–10 | 2.0–2.5% |
| B | 5–7 | 1.0–1.5% |
| C | 3–4 | 0.5% |
| Skip | < 3 | 0% — do not trade |

---

## 🛡️ Step 6: Risk Architecture — The Missing Piece

> *(Contestant A, Round 5 — #1 most overlooked aspect across all rounds)*  
> Without this, 40 levers blow up your account.

### A. Cluster Risk Budgeting

```
Trend Continuation (Engines 1, 3):    2.5% MAX total heat
Reversal / Fade (Engines 4, 5):       2.0% MAX total heat
Session Breakout (Engine 2):          1.5% MAX total heat
```

> First signal in a cluster gets the full budget; subsequent signals in the same cluster = **0** until a slot frees up.

### B. Portfolio Heat Cap

```
Total open heat (Σ distance-to-stop × lot):   ≤ 4% equity
Any single currency net exposure:              ≤ 3% equity
Same-direction cluster:                        ≤ 2.5% equity
```

> New signal that would breach → **queue it**, don't skip it. Enter when heat frees up and setup is still valid.

### C. Dynamic Volatility Sizing

> *(Contestant A, Round 2)*

```
ATR high  → lower lot size (avoid stops hit on normal noise)
ATR low   → larger lot size (maximize breakout potential)

Lot = Base lot × (ATR_20_avg / ATR_20_current)
```

### D. Rolling Edge Decay Monitor

> *(Contestant A, Round 5 — most advanced protection lever)*

```
E₅₀ = mean R over last 50 trades

E₅₀ > 0.35R          →  100% risk (full operation)
0.15R < E₅₀ ≤ 0.35R  →   75% risk
0.00R ≤ E₅₀ ≤ 0.15R  →   40% risk + re-check regime filter
E₅₀ < 0               →  FLAT all engines until 20 paper signals
                           validate edge, then resume at 25% risk
```

---

## 🔧 Step 7: Execution Quality

> **Every contestant agreed — most underappreciated lever.**  
> At 25 trades/month, 0.1R of slippage per trade = 2.5R = **12.5% of your entire monthly target**.

| Action | Saving per Trade |
|---|---|
| Raw ECN spread account (0.0–0.2 pip + $3.5/lot commission) | 0.04–0.06R |
| VPS co-located with broker (< 5ms latency) | 0.01–0.02R |
| **Limit orders ONLY** — never chase a missed OB at market | 0.02R |
| Move XAUUSD to H4/H1 entry (M15 gold spread kills expectancy) | 0.07–0.15R saved |
| Avoid trading Friday after 15:00 server | Protects gains |
| No trades within 30 min of high-impact news (NFP, CPI, Fed) | Avoids gaps |

---

## 💰 Step 8: Capital Structure — The True "20%/month" Answer

> *(Contestant B, Round 3 — confirmed by Contestant A, Round 5)*  
> The real path to $20k+/month is **5–7% on multiple $100k funded accounts**, not 20% on your own $10k.

```
5 funded accounts × $100k × 5% monthly × 85% split = $21,250/month
Risk per account: 0.5% (survives prop firm daily 5% loss limits)
Your effort: SAME EA — SAME VPS — ZERO additional research
```

**Prop Firm Progression Path:**

| Stage | Action |
|---|---|
| Weeks 1–8 | Validate engines on demo (real broker feed) |
| Week 9–10 | Pass first $50k eval at 0.5% risk (8% target, 5% max DD) |
| Week 11+ | Run funded at 0.5% risk |
| Every 6–8 weeks | Pass new eval → scale to 2–4–6 accounts |


---

## 📅 Step 9: The 90-Day Build Order

> *(Most agreed upon across all 5 rounds)*

| Week | Action | Expected Impact |
|---|---|---|
| 1–2 | Setup raw ECN account + VPS. Implement 5-engine EA with A/B/C grading. Backtest EURUSD M15 (2022–2026) | Baseline validation |
| 3–4 | Replace fixed TP with asymmetric exit ladder (1.5R partial → runner). Re-backtest. | +0.4–0.7R/trade avg |
| 5–6 | Add regime router (ATR + ADX filter) + heat cap + clustering. Re-backtest portfolio. | Cuts DD by ~30% |
| 7–8 | Add Engine 2 (Asian Range Raid) — lowest correlation, easiest to validate. Check portfolio correlation < 0.5. | +3–5R/month |
| 9–10 | Add rolling E₅₀ edge-decay monitor. Full stress test (1-in-12 losing streak scenario). | Prevents blow-ups |
| 11–12 | Demo on live broker feed (4 weeks, ~100 trades). Live vs backtest comparison. | Real feed validation |
| 13+ | Apply to funded account(s) at 0.5% risk. Scale accounts over time. | Income multiplication |

---

## 📉 Realistic Expectations Table

> *(Contestant B, Round 2 — Honest Haircut)*

| Scenario | Win Rate | Expectancy | R/Month | ROI @ 1.5% | Verdict |
|---|---|---|---|---|---|
| Backtest (perfect execution) | 45% | 0.80R | 25R | +37.5% | Fantasy ceiling |
| **Realistic live target** | **40%** | **0.60R** | **15R** | **+22.5%** | ✅ Achievable |
| Typical live result (first 3 months) | 35% | 0.40R | 10R | +15% | Expected early on |
| Poor execution / high spread | 30% | 0.20R | 5R | +7.5% | Still profitable |
| Break-even floor | 25% | 0.00R | 0R | 0% | Absolute floor |

---

## 🔴 Critical Warnings From All Rounds

### ⚠️ Warning 1: Correlated Engines ≠ Diversification
> *(Contestant A, Round 5)*  
> If 5 engines all read the same impulse candle and all go long the same pair, you have **1 trade at 5× size**, not 5 independent edges. Your monthly σ goes to ~20R and one bad week erases three good months.

### ⚠️ Warning 2: The 0.7R Tight Stop is a Trap
> *(Contestant B, Round 4)*  
> The tighter 0.7R stop converts too many winners into breakeven scratches, destroying the expectancy math. The corrected 3-bucket model shows E drops from 0.52R to 0.084R. **Use 1.0R stop.**

### ⚠️ Warning 3: "40 Levers" is Marketing, Not Math
> *(Contestant A, Round 5)*  
> Many levers are the same signal described differently (e.g., Lever 6 "session filter" and Lever 20 "intraday seasonality" are the same). Keep only **6–9 engines** that each show `E > 0.25R` out-of-sample AND monthly-return correlation < 0.5 to each other.

### ⚠️ Warning 4: Geometric Drag is Real
> *(Contestant B, Round 4)*  
> Chasing 40%/month with 3% risk produces **lower geometric returns** than 20%/month at 1.5% risk:
> ```
> g ≈ μ − σ²/2
> At 40%/month mean with 30% σ → g ≈ 0.40 − 0.045 = 35.5%  (but path is violent)
> At 20%/month mean with 15% σ → g ≈ 0.20 − 0.011 = 18.9%  (much smoother)
> ```
> Optimal safe risk fraction per Kelly ≈ **2.2%** per trade. Beyond that, variance erodes compound growth.

### ⚠️ Warning 5: XAUUSD on M15 is a Cost Leak
> *(Contestant A, Round 3)*  
> Spread of 25–35 points against a 20-point stop = **0.15R cost per trade**. Move gold to H4/H1 entry or drop it entirely unless its gross edge compensates. At 25 trades/month, this alone is −3.75R = −5.6% of your target.


---

## ✅ Final Recommendation: Build This in Priority Order

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PHASE 1 — Foundation (Week 1–4)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Multi-symbol SMC EA (Engine 1 only, 8 pairs)
✅ M15 entry with H4 bias (3 TF steps up)
✅ A/B/C grading + tiered risk (2.5% / 1.5% / 0.5%)
✅ Asymmetric exit ladder (1.0R stop → staged TPs → runner)
✅ Raw ECN account + VPS (<5ms) + limit orders ONLY

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PHASE 2 — Risk Architecture (Week 5–8)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Portfolio heat cap (4% total / 2.5% cluster / 3% per currency)
✅ Cluster risk budgeting (one budget per correlated group)
✅ Volatility-adjusted lot sizing (ATR₂₀ ratio)
✅ Regime router (ADX + ATR regime detection)
✅ Daily loss cap (4%) + Max DD hard stop (25%)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PHASE 3 — Engine Diversification (Week 9–12)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Engine 2: Asian Range Raid (lowest correlation, easiest to validate)
✅ Engine 3: Imbalance/FVG Re-Engagement
✅ E₅₀ rolling expectancy kill switch
✅ Full portfolio stress test (flash crash, 1-in-12 streak scenarios)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PHASE 4 — Income Scaling (Month 3+)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Funded account eval at 0.5% risk (pass first $50k eval)
✅ Scale to 4–6 funded accounts over 6–9 months
✅ Engine 4 (Swing Failure) + Engine 5 (Mean Reversion)
   — ONLY added after Engines 1–3 each validate standalone
✅ Target: 5 accounts × $100k × 5%/mo × 85% split = ~$21k/month
```

---

## 📌 Quick Reference: Top 10 Levers by ROI Impact

| Priority | Lever | ROI Lift (Live) | Effort |
|---|---|---|---|
| 1 | **Raw ECN account + limit orders only** | +2–4%/month (pure saved cost) | Low — procurement task |
| 2 | **A/B/C grading + tiered risk** | +3–5%/month | Low — code change |
| 3 | **Asymmetric exit ladder (staged TPs + runner)** | +4–6%/month | Medium |
| 4 | **8-symbol portfolio (vs 1 pair)** | ×6 setup count | Low — config change |
| 5 | **Portfolio heat cap + cluster budgeting** | Halves DD → allows 2× risk | Medium |
| 6 | **Regime router (ADX + ATR)** | +2–3%/month by cutting bad trades | Medium |
| 7 | **E₅₀ edge-decay kill switch** | Protects compounding (most valuable over 12 months) | Medium |
| 8 | **Engine 2: Asian Range Raid** | +3–5R/month, near-zero correlation | Medium |
| 9 | **VPS co-location (<5ms)** | +0.5–1%/month slippage saved | Low |
| 10 | **Funded prop account multiplication** | Dollar income ×5–10 | Low (same EA) |

---

## 🎯 Bottom Line

The strategy that wins isn't the one with the most indicators. It's the one with:

1. **5–6 uncorrelated engines** (not 40 overlapping ones)
2. **Mathematically correct exits** (1.0R stop, staged TPs, HTF runners)
3. **Disciplined risk clustering** (heat caps, one budget per correlated group)
4. **Flawless execution** (raw ECN, VPS, limit orders only)
5. **Eventual scaling via funded prop accounts** (5 × $100k at 0.5% risk)

Run that consistently and the realistic outcome is **15–20%/month on your own capital with a ~25% peak drawdown**, or **$20k–25k/month of income** across 5 funded accounts — which is the real "20% ROI" goal you were chasing from the start.

---

*This document synthesizes findings from 13 StudyArena markdown files across 5 rounds. The strategy presented is the converged consensus of the most mathematically rigorous and practically honest analysis across all contestants and rounds.*

