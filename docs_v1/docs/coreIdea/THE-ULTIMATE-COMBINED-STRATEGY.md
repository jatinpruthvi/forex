# 🏆 THE ULTIMATE COMBINED STRATEGY — Synthesis of All 8 Architectures

**Date:** 29 Sept 2026
**Purpose:** The single best strategy from ALL documents in `docs/coreIdea/` — the consensus of D1–D8, AAM, ACM, AEM, OAF, SAM, MFP, Preflight, Ruin-Proofing, ROI Scorecard, Recommendations, and Tri-Pillar Review. Every decision carries its source.
**Rule:** Evidence-first. Numbers from audited corpus, never from untested projections. Layers 2+3 (65% of ROI) built before Layer 1.

---

## 📋 Source Documents & What Each Contributes

| Doc | Contribution to This Strategy |
|---|---|
| **D1 Strategy Recommendation** | 5-round consensus: 1.0R stop, staged exit ladder, A/B/C grading, cluster budgets, E₅₀ throttle, 8-symbol portfolio |
| **D2 Max-ROI Out-of-Box** | 3-Track Factory (Eval/Funded/Personal Barbell), anti-breach circuit breakers, dead-money exit, dispersion book |
| **D3 AAM** | DXY SMT divergence gate, 3-state regime router |
| **D4 ACM** | Layer hierarchy (15/30/35/20), bandit (deferred), procurement alpha, promo-window evals, yield-diff + COT gates, payout ladder |
| **D5 AEM** | 4-zone barrier sizing for Track A, double-barrier optimal control, PCA stat-arb (deferred) |
| **D6 OAF** | Account stagger, genetic breeder (deferred), PPO (deferred), cross-asset lattice (deferred) |
| **D7 SAM** | Execution hygiene, limit-order-only, ≥180s holds, payout-first withdrawal, firm solvency scoring |
| **D8 MFP** | Cost-reality audit, pre-registration, micro-live lab, evidence ledger, sample-size gates |
| **Master Combination** | v1.1 Safe-Hybrid: Dual-Bracket Entry, Daily HMM, Shadow ML, Native Macro Feeds, Cluster Firewalls |
| **Ruin-Proofing** | 16 failure modes, 5 gap fixes, deterministic go-live gate, survival budget |
| **Preflight** | Firm Capability Matrix, timebase normalization, proxy fidelity gate, override log |
| **ROI Scorecard** | 15 levers ranked, layer hierarchy, tension plot |
| **Recommendations** | 6 do-now $0 levers, Risk Governor spec |
| **Tri-Pillar Review** | HMM as regime allocator, rejection of 0.7R/3% heat/copier |

---

## 🔑 The Core Innovation: HMM-Regime-Allocated 3-Book System

This is the single most important concept that emerges from the synthesis. Instead of running all engines simultaneously and *hoping* they're uncorrelated, the **Daily HMM becomes the state machine that explicitly allocates capital**:

```
                     ┌─────────────────────────────────┐
                     │  DAILY HMM (23:55 GMT)           │
                     │  Classifies market into 3 states │
                     └──────┬──────────┬──────────┬─────┘
                            │          │          │
                    ┌───────┘    ┌──────┘  ┌──────┘
                    ▼            ▼          ▼
             ┌──────────┐ ┌──────────┐ ┌──────────┐
             │ TRENDING │ │ MEAN-    │ │ SHOCK    │
             │          │ │ REVERTING│ │ (HIGH VOL)│
             └────┬─────┘ └────┬─────┘ └────┬─────┘
                  │            │            │
    ┌─────────────┼────────────┼────────────┼─���───────────┐
    │             │            │            │             │
    ▼             ▼            ▼            ▼             ▼
┌───────┐   ┌───────┐    ┌───────┐    ┌───────┐     ┌───────┐
│ BOOK  │   │ BOOK  │    │ BOOK  │    │ BOOK  │     │ BOOK  │
│ A     │   │ B     │    │ C1    │    │ C2    │     │ E4    │
│ EVAL  │   │FUNDED │    │PERSONAL   │PERSONAL│     │DISPERSION
│ 0.5%  │   │0.4-0.5%│   │BASE 0.75%│SNIPER │     │0.25%/leg
└───────┘   └───────┘    │ 80% of   │ 20% of │     └───────┘
                         │ personal │ personal│
                         └─────┬─────┘────┬────┘
                               │          │
                               ▼          ▼
                    ┌─────────────────────────┐
                    │   E1 SMC Core (M15)     │
                    │   E2 Asian Raid (07-10) │
                    │   E3 FVG Re-Engage      │
                    └─────────────────────────┘
```

---

## 🏗️ THE COMPLETE SYSTEM

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ THE ULTIMATE COMBINED SYSTEM (v2.0 — HMM-Regime-Allocated 3-Book Factory)   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  [D8 VALIDATION OS — runs beneath everything, BEFORE any entry]             │
│   ├─ Cost-Reality Audit (c/R ≤ 5% mandatory hurdle) — D8 §3                │
│   ├─ Pre-registration & unalterable Evidence Ledger — D8 §2                 │
│   ├─ Override Log (M4) — timestamp·reason·R, unlogged override = invalid   │
│   └─ Shadow ML Logger: 20-feature snapshot on EVERY signal incl. skipped   │
│                                                                             │
│  [M5 RISK GOVERNOR — coded FIRST, before any entry logic]                  │
│   ├─ Anti-breach: -2.2% realized daily → CLOSE ALL, disable 24h            │
│   ├─ Trailing DD: ≥4% peak-to-trough → 48h freeze                          │
│   ├─ Cluster Firewalls: Trend≤2.5%, Reversal≤2.0%, Dispersion≤1.0%         │
│   ├─ Net single-currency: ≤3% personal / ≤1.5% funded                      │
│   ├─ Heat REDISTRIBUTION: r_i = H_rem / √(1ᵀρ1) — +20-25% compound         │
│   ├─ Rolling E₅₀: <0.35R→halve, <0→halt EA                                │
│   ├─ PRE-TRADE ASSERTIONS: lot>cap·heat>cap·net-ccy>cap·margin<floor→REFUSE│
│   ├─ BROKER-SIDE SL: every fill carries hard SL at broker                  │
│   └─ Weekly kill-switch drill (demo: force -2.2%→assert flat+disabled)    │
│                                                                             │
│  [M2/M3 DATA INTEGRITY LAYER]                                               │
│   ├─ Timebase in UTC; convert via server_utc_offset; unknown→NO ENTRIES    │
│   ├─ Proxy fidelity: 30D corr(broker_DXY, 8-major composite)≥0.95→enable   │
│   │  else gate NEUTRAL                                                      │
│   ├─ Spread at fill (M6) — not at quote                                    │
│   └─ News calendar + timezone declared                                     │
│                                                                             │
│  [DAILY HMM REGIME CLASSIFIER — the state machine that allocates]          │
│   Runs at 23:55 GMT across DXY + 8 majors. Outputs regime state flag       │
│   that determines which engines get full/half/zero allocation.             │
│   Shadow-log for 30 days first; then drives SIZING (never on/off switch).  │
│                                                                             │
│  [NATIVE MACRO FEEDS]                                                       │
│   ├─ DXY SMT divergence gate (MT5 native proxy) — §M3 validated            │
│   ├─ USOIL CAD lead-lag confirmation                                       │
│   └─ Yield-differential bias gate (5-day change of US2Y-DE2Y etc.)         │
│                                                                             │
│  [SIGNAL LAYER — 4 Engines × 2 Return Families]                            │
│                                                                             │
│   FAMILY 1: DIRECTIONAL (E1, E2, E3) — HMM-allocated per regime            │
│   ────────────��────────────────────────────────────                        │
│   E1: SMC Core (H4 bias→sweep→M15 CHoCH→OB/FVG)                           │
│       + DXY SMT validity gate                                              │
│       0–10 grading → A(8+)/B(5-7)/C(3-4)/skip(<3)                         │
│       Entry TF: M15 · HTF Bias: H4                                         │
│                                                                             │
│   E2: Asian-Range Liquidity Raid (07:00-10:00 UTC)                         │
│       Asian H/L mapped, sweep + retract + CHoCH back inside                │
│       + DXY SMT validity gate                                              │
│                                                                             │
│   E3: FVG Imbalance Re-Engagement                                          │
│       Impulse >2.0×ATR₁₄ → map 3-candle FVG → 50% equilibrium limit       │
│       + volume-confirm (tick vol >1.8× 20-period avg)                      │
│                                                                             │
│   FAMILY 2: CROSS-SECTIONAL (E4) — runs UNCONDITIONALLY in all regimes    │
│   ───��─────────────────────────────────────────────                        │
│   E4: Dispersion Rank Book (8 majors, daily rebalance at NY close)         │
│       20-day momentum + 60-day carry → score → long top 2, short bottom 2  │
│       Zero net USD exposure · 0.25%/leg · hold 1-5 days                    │
│       Stop: rank flip or 5-day timeout                                     │
│       This is the CHOP MONTH INSURANCE — fires when E1-E3 are flat/losing │
│                                                                             │
│  [EXECUTION & EXIT LAYER — D1 Corrected Ladder + Dual-Bracket Entry]       │
│   ├─ Dual-Limit Entry: 50% risk @ OB front edge, 50% @ 50% equilibrium    │
│   │  Cancel Limit 2 if Limit 1 reaches +1.0R                              │
│   ├─ 1.0R hard stop (≥25 pips effective on M15) — NOT 0.7R!               │
│   ├─ Staged Exit: 25%@1.5R(move SL to BE+0.3R)→25%@3R→25%@pool→runner    │
│   ├─ Dead-money time exit: age>1.5×median AND <+0.5R→close at market       │
│   ├─ Execution hygiene: RESTING LIMITS ONLY, VPS<5ms, holds≥180s          │
│   └─ Killzones only: London 07-10 UTC, NY 13-16 UTC                       │
│                                                                             │
│  [3-TRACK CAPITAL WRAPPERS — D2 Factory Structure]                         │
│                                                                             │
│   TRACK A: EVAL FARM (0.5% base risk)                                      │
│   ├─ 4-Zone Barrier Sizing (D5 adapted): 0.5%→0.35%@+4%→0.20%@+6%→0.10%@+7%│
│   ├─ Exam-only filters: no gold, no Friday, no news ±30min, max 2 pos     │
│   ├─ Killzone only — boredom passes exams                                 │
│   ├─ Target: +8% pass, nothing else                                       │
│   └─ Buy only at promo-priced firms with known+compatible rule matrix      │
│                                                                             │
│   TRACK B: FUNDED HARVEST (0.4-0.5% base risk)                             │
│   ├─ E1 + E2 ONLY (disable E3 on funded)                                  │
│   ├─ Target: 4-6%/mo then STOP — overtrading = donating it back           │
│   ├─ Heat cap: 2% total · currency cap: 1.5%                              │
│   └─ Weekly payout discipline: withdraw on schedule, always                │
│                                                                             │
│   TRACK C: PERSONAL BARBELL                                                │
│   ├─ C1 "Rent Money" (80%): 0.75% risk, E1+E2, killzone-only             │
│   │  Target: 6-8%/mo, <12% DD                                             │
│   ├─ C2 "Rocket Fuel" (20%): 2.5% sniper (C2a) + 1.5% pyramid (C2b)      │
│   │  C2a: London killzone sniper, 07-10 UTC, A-grade only, max 1 pos      │
│   │  C2b: HTF pyramid driver, risk-free-add gate only                     │
│   │  Hard rules: max 3% heat, no Friday 15:00, 2-consec-loss→48h pause   │
│   │  Monthly C2 stop: -8% → C2 off for rest of month                      │
│   └─ Personal risk ratchet: 0.75% → 1.00% → 1.25%, gated on E1≥30 trades  │
│      with E>0.25R and E₅₀>0.35R. Hard ceiling 2.2% (Kelly r*/6).         │
│      NEVER applies to eval/funded — their wrappers stay fixed.             │
│                                                                             │
│  [STRUCTURE & PROCUREMENT LAYER — D4 + D6 + D7]                            │
│   ├─ Firm Capability Matrix (M1): 12 rules, EVERY row known+compatible    │
│   │  or DO NOT BUY — consistency rule is the single biggest payout risk   │
│   ├─ Promo-window eval buying only: 60-90% discounts → EV jumps $425+    │
│   ├─ Account staggering (D6): never push all evals aggressively at once   │
│   │  Different engine mixes per account, different firms                 │
│   ├─ Payout ladder (D4): 2 fast-payout + 2 slow-payout high-split + 1     │
│   │  scaling-focused; REINVEST 25%→evals, 25%→buffer, 50%→compounder     │
│   ├─ Firm solvency score (D7): payout latency, rule volatility, spreads   │
│   └─ Payout-first withdrawal: extract immediately on qualification        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 🧠 HMM Regime Allocation Logic — The Core Innovation

This replaces the flawed "run everything and hope it's uncorrelated" approach with explicit, rule-based allocation:

```
┌─────────────────────────────────────────────────────────────────────────┐
│ HMM STATE → ENGINE ALLOCATION MAP                                       │
├────────────┬──────────┬──────────┬──────────┬──────────┬────────────────┤
│ HMM State  │   E1     │   E2     │   E3     │   E4     │ Notes          │
│            │SMC Core  │Asian Raid│FVG Re-Eng│Dispersion│                │
├────────────┼──────────┼──────────┼──────────┼──────────┼────────────────┤
│ TRENDING   │ 100%     │  30%     │ 100%     │ 100%     │ E2=fade=bad    │
│ (25% of    │          │          │          │          │ in trend       │
│  time)     │          │          │          │          │                │
├────────────┼──────────┼──────────┼──────────┼──────────┼────────────────┤
│ MEAN-      │  30%     │ 100%     │  30%     │ 100%     │ E1/E3 bleed    │
│ REVERTING  │          │          │          │          │ in chop;       │
│ (65% of    │          │          │          │          │ E2=raid thrives│
│  time)     │          │          │          │          │                │
├────────────┼──────────┼──────────┼──────────┼──────────┼────────────────┤
│ SHOCK      │  0%      │  0%      │  0%      │ 100%     │ FLAT all       │
│ (10% of    │          │          │          │          │ directional;   │
│  time)     │          │          │          │          │ keep E4 only   │
└────────────┴──────────┴──────────┴──────────┴──────────┴────────────────┘
```

**Why this beats everything else in the corpus:**
1. **Non-overlap by construction** — not by statistical hope
2. **Misclassification survivable** — it's *sizing* (30-100%), not on/off
3. **E4 runs unconditionally** — its job is chop-month insurance
4. **Correlation matrix measured automatically** — not asserted

**Caveat (from MFP + Tri-Pillar):** HMM shadows for 30 days before driving size. Never let an unvalidated regime classifier veto trades.

---

## 📊 The 4 Engines: When Each Fires & How They Interact

```
ENGINE PROFILES
┌──────┬──────────────────┬──────────┬────────┬──────────┬───────────────┐
│ Eng  │ Edge Type        │  WR est │ RR avg │ R/mo est │ Best Regime   │
├──────┼──────────────────┼──────────┼────────┼──────────┼───────────────┤
│ E1   │ SMC Core         │   40%   │  3.0   │ +8-10R   │ Trending      │
│ E2   │ Asian Raid       │   50%   │  2.2   │ +3-5R    │ Mean-Reverting│
│ E3   │ FVG Re-Engagement│   42%   │  2.8   │ +5-7R    │ Trending      │
│ E4   │ Dispersion Book  │   55%   │  1.5   │+1.5-2.5% │ ALL regimes   │
└──────┴──────────────────┴──────────┴────────┴──────────┴───────────────┘

CORRELATION STRUCTURE (measured from logged trades, never assumed)
┌──────┬──────┬──────┬──────┬──────┐
│      │  E1  │  E2  │  E3  │  E4  │
├──────┼──────┼──────┼──────┼──────┤
│  E1  │ 1.00 │ 0.30 │ 0.45 │ 0.05 │
│  E2  │ 0.30 │ 1.00 │ 0.35 │ 0.10 │
│  E3  │ 0.45 │ 0.35 │ 1.00 │ 0.08 │
│  E4  │ 0.05 │ 0.10 │ 0.08 │ 1.00 │
└──────┴──────┴──────┴──────┴──────┘
E4 is the ONLY genuinely uncorrelated stream — runs unconditionally.

SETUP GRADING SYSTEM (D1 consensus, used as FILTER on eval/funded,
SIZING on personal):
  8-10 pts (A): +2 HTF bias +2 sweep +2 CHoCH +1 FVG +2 clean target +1 killzone
  5-7 pts (B): standard conditions
  3-4 pts (C): minimal confluence
  <3 pts: SKIP — do not trade
  Penalties: -3 each for news±30min, spread>1.5×norm, Friday>15:00
```

---

## 🛡️ EXECUTION & EXIT ARCHITECTURE — The Corrected Ladder

```
DUAL-BRACKET LIMIT ENTRY (Safe-Hybrid from Master Combination):
  Limit 1: 50% risk @ OB/FVG front edge
  Limit 2: 50% risk @ 50% equilibrium point
  Cancel Limit 2 IMMEDIATELY if Limit 1 reaches +1.0R (capture more runner)

This beats: single market order (slippage), 5-slice micro-limits (HFT flags)

STOP LOSS: 1.0R HARD STOP — NEVER 0.7R (Tri-Pillar Review §3A)
  Why: 0.7R converts winners→BE scratches, E drops 0.52R→0.084R
  Minimum stop distance: 25 pips on M15 (below this = cost>5-14% of R)
  Every fill carries broker-side hard SL (Ruin-Proofing F7 fix)

STAGED EXIT LADDER:
  TP1 (1.5R): Close 25%, move SL to +0.3R (secured profit) — 32% of trades
  TP2 (3.0R): Close 25%, move SL to +1.0R (risk-free) — 15% of trades
  TP3 (Pool): Close 25% at first opposing liquidity pool — 8% of trades
  Runner: Trail behind HTF swing structure until broken → 6-10R — 8% of trades

EXPECTANCY (3-bucket corrected model — R4B audited):
  E = 0.08(8.0) + 0.32(0.4) + 0.60(-1.0) = 0.64 + 0.13 - 0.60 = +0.17R/trade
  With runners elevating: ~0.40-0.60R/trade on good engines
  25 trades/month × 0.60R = 15R/month at 1.5% = +22.5%/mo

DEAD-MONEY TIME EXIT (D2 Multiplier 2):
  If trade age > 1.5× engine's median resolution time AND <+0.5R → close
  Effect: trades/mo +20-30%, R/mo +15% — costs $0
```

---

## 📦 THE 3-TRACK CAPITAL FACTORY — How Edge Becomes Dollars

```
TRACK A: EVAL FARM
───────────────────────────────────────────────────────────────────────────
  Purpose: Convert $500 fees into $100k funded accounts at ~60% pass rate
  Risk/trade: 0.5% base → 4-Zone Barrier Sizing (D5 adapted):
    Zone 0 (<-2.5% DD):     0.25% risk — survival mode
    Zone 1 (-2.5% to +3%):  0.50% risk — standard
    Zone 2 (+3% to +7%):    0.75% risk — push for pass
    Zone 3 (>+7%):          0.10% risk — protect the pass
  Engines: E1 + E2 only (E3 too correlated, E4 too small for exam)
  Filters: No gold, no Friday, no news±30min, killzone only, max 2 pos
  Pass target: +8% in 20-30 days

TRACK B: FUNDED HARVEST
───────────────────────────────────────────────────────────────────────────
  Purpose: Extract 4-6%/month forever without breach
  Risk/trade: 0.4-0.5% FIXED — NEVER above 0.5% (Ruin-Proofing §1)
  Engines: E1 + E2 only — disable E3 on funded
  Heat cap: 2% total · currency cap: 1.5%
  Monthly target: 4-6% THEN STOP
  Weekly payout: withdraw on schedule — no exceptions
  Economics: $100k × 5% × 80% split = $4,000/mo per account net

TRACK C: PERSONAL BARBELL (80/20 Split)
───────────────────────────────────────────────────────────────────────────
  C1 — "RENT MONEY" (80% of personal equity):
    Risk: 0.75%, capped at 2.2% geometric ceiling
    Engines: E1 + E2, killzone-only, full exit ladder
    Target: 6-8%/mo with <12% DD
    NEVER borrow from C1 to feed C2 — C1 is sacred

  C2 — "ROCKET FUEL" (20% of personal equity):
    C2a London Sniper (60% of C2):
      Window: 07:00-10:00 UTC only
      Setup: Asian range sweep + M15 CHoCH back inside, A-grade (≥8) only
      Risk: 2.5%, max 1 position
    C2b HTF Pyramid Driver (40% of C2):
      H4 sweep→OB tap→M30 CHoCH. Add only with risk-free-add gate
      Max 3 units, ever
      1-in-8 drivers pay 8-14R blended

    C2 HARD RULES:
      - Total C2 heat ≤ 3%
      - Same-currency cap 2%
      - Friday 15:00 → C2 flat
      - 2 consecutive losses → C2 paused 48h
      - Monthly C2 stop: -8% → C2 off for month
      - NEVER apply C2 sizing to eval/funded accounts

  PERSONAL RISK RATCHET (gated — Recommendations §C):
    Gate: E1 ≥30 live trades with E>0.25R AND E₅₀>0.35R
    C1 0.75% → 1.00% → 1.25% (hard ceiling 2.2%)
    Eval/funded NEVER ratchet — their wrappers stay fixed
```

---

## 🧮 HONEST PLANNING NUMBERS (All D8-Audited, No Fantasy)

| Track | Risk/trade | Monthly Return | Max DD | Status |
|---|---|---|---|---|
| **Personal C1** (80%) | 0.75% | 6-8% | <12% | D1-consistent |
| **Personal C2** (20%) | 2.5% sniper | −8% to +20% slice | slice-capped −8%/mo | Outcome variable |
| **Personal total** | mixed | **10-18%** (~1mo in 4 red) | ~25% | Honest sum |
| **Track A eval** | 0.5% (barrier) | pass target +8%, ~60% pass rate | exam-capped | Hypothesis |
| **Track B funded** | 0.4-0.5% | **$3.2-4.8k/mo net per $100k** | ~8%, −2.2% breaker | D1/D2 consensus |
| **5 funded accounts** | 0.5% | **$16-24k/mo net** (month 6+) | compartmentalized | The factory goal |
| **6th account (upside)** | 0.5% | up to **~$31k/mo** (gated) | compartmentalized | Gate: 2 evals passed |
| **E4 dispersion** | 0.25%/leg | +1.5-2.5%/slice | ~4% slice | Insurance > return |
| **Eval spend** | ≤2% net worth | capped loss = fees | — | Fees = only true downside |

**WR expectancy table (D1 honest haircut, D8 audited):**
 | Scenario | WR | Expectancy | R/mo | ROI @ 1.5% |
 |---|---|---|---|---|
 | Backtest ceiling | 45% | 0.80R | 25R | +37.5% |
 | **Realistic live** | **40%** | **0.60R** | **15R** | **+22.5%** |
 | First 3 months | 35% | 0.40R | 10R | +15% |
 | Poor execution | 30% | 0.20R | 5R | +7.5% |
 | Break-even floor | 25% | 0.00R | 0R | 0% |

**Geometric drag warning (D1 Warning 4):** 40%/mo at 3% risk → `g ≈ 35.5%` but violent.
20%/mo at 1.5% risk → `g ≈ 18.9%` and much smoother. The smooth path produces more
wealth by month 12. Optimal Kelly safe fraction: `r*/6 ≈ 2.2%` — hard ceiling.

---

## 🔧 THE 4 QUANT ADVANCEMENTS (De-Risked Safe Hybrids)

From the Master Combination — these 4 enhancements are INCLUDED but SAFE:

### 1. Dual-Bracket Limit Entry (instead of 5-slice micro-limits)
- 50% at FVG front edge, 50% at 50% equilibrium
- Cancel Limit 2 if Limit 1 hits +1.0R
- Zero HFT spam flags, captures runners

### 2. Daily Rollover HMM State Flag (instead of tick-by-tick real-time)
- Python script runs at 23:55 GMT, once per day
- Classifies: Trending / Mean-Reverting / High-Vol Shock
- Drives engine allocation next session
- Zero execution latency, zero API crash risk

### 3. Shadow Mode ML Meta-Labeling (instead of live veto Day 1)
- Logs 20-feature snapshot + XGBoost prediction on EVERY signal
- INCLUDES skipped/C-grade signals (vote for later meta-labeling unlock)
- Unlocks active vetoing only after 100 live audited broker fills
- Meta-labeling needs ~500 signals; logging skips today = +4R/mo available ~3 months earlier

### 4. Deterministic Cluster Firewalls + USD Netting (instead of dynamic HRP)
- Trend ≤2.5%, Reversal ≤2.0%, Dispersion ≤1.0%
- Net USD cap ≤1.5% funded
- Heat REDISTRIBUTION: `r_i = H_rem / √(1ᵀρ1)` — give unused headroom to uncorrelated trades
- Captures 90% of HRP math with zero matrix instability
- **+20-25% compound growth with zero signal change** (ROI Scorecard §5)

---

## 🚫 DEFERRED (Gated — Do Not Build Yet)

| Component | Source | Gate/Trigger |
|---|---|---|
| Bandit allocation | D4/ACM | ≥2 engines live, ≥30 trades each, unequal decay |
| Meta-labeling → 1/5-Kelly | D4/ACM | ≥500 logged trades with feature columns |
| Rebate layer | D4/ACM | After 1st funded payout; only where ToS permits |
| PCA/OU stat-arb engine | D5/AEM | After dispersion book proves profitable 60+ days |
| Double-barrier zone sizing | D5/AEM | Before buying eval #2 |
| CME L2 / VPIN feed | D5/AEM | Only if cost audit shows slippage >3% of R |
| LinUCB contextual allocator | D5/AEM | When bandit shows regime-lag problems |
| Genetic alpha breeder + DSR | D6/OAF | Month 4+: only if 3+ engines verified AND edge decay |
| PPO meta-controller | D6/OAF | Never before breeder (no data); offline kill-switch required |
| Cross-asset leader lattice | D6/OAF | After MFP-00x confirms yield-diff gate value |
| Avellaneda-Stoikov MM | D7/SAM | Personal capital >$50k + dedicated liquidity data |
| 6th funded account | D2 | 2 consecutive evals passed, then promo window only |
| Grade-tier sizing (A=2.5%) | D1 | Personal sleeve only; wrapper still caps |
| News hold (gap capture) | R4B | Rejected — <2R/month, breaches risk |

---

## 💣 THE 5 FAILURE MODES EVERY OTHER STRATEGY IGNORES (Fixed Here)

These 5 controls cost ≈$0 and remove the only paths that actually reach a breach:

| Gap | Fix | Cost |
|---|---|---|
| **F5 News gap** | Close all ≥15min before Tier-1. Heat=0 through event ⇒ gap loss=0 | $0 |
| **F6 Weekend gap** | No positions carried over weekend on eval/funded. Flat=all variants | $0 |
| **F7 EA/VPS death** | Every fill carries broker-side hard SL. EA death caps loss at stop, not ∞ | $0 |
| **F8 Lot-sizing bug** | 4 pre-trade assertions: lot>cap·heat>cap·net-ccy>cap·margin<floor→REFUSE | $0 |
| **F9 Breaker failure** | Weekly forced drill in demo: force -2.2%→assert flat+disabled. FAIL=BLOCK | 30min/week |

**The arithmetic reason 1.5% is banned on funded (Ruin-Proofing §1):**
```
Worst expected streak (40% WR, 300 trades/yr): k = ln(300)/ln(1/0.40) ≈ 6.2
At 0.5% risk: DD ≈ 3.1% — under 4% freeze, never even trips it
At 1.5% risk: DD ≈ 9.3% — 93% of firm's 10% total limit, near-breach
```

---

## 🔥 DETERMINISTIC GO-LIVE GATE (Machine-Verifiable, No Inference)

**BLOCK** — no entries until resolved:
- B1: Breaker drill FAILED or >7 days old
- B2: Any pre-trade assertion not implemented
- B3: Open position within ±15min of Tier-1 news
- B4: Open position at weekend close on eval/funded
- B5: Any open position has no broker-side SL
- B6: Cost audit `c > 5%` of R
- B7: E₅₀ < 0 — EA halted
- B8: Projected heat > cap or projected net currency > cap

**WARN** — reduce risk:
- W1: E₅₀ ∈ (0.15, 0.35] → halve risk
- W2: 4% trailing DD freeze active → no new entries 48h
- W3: Spread >
- W3: Spread > 1.5× normal → skip that setup
- W4: Drill passed but not this week → schedule it

**Rationalization detector (delivery-gate pattern):**
`"skip the drill"` · `"it worked last time"` · `"the breaker is fine"` ·
`"just this once"` · `"news won't matter"` · `"temporary override"`

---

## ✅ FIRM CAPABILITY MATRIX (M1 — Single Largest EV in Corpus)

A voided payout = **−100%** of that account's EV ($4-6k/mo gross). No signal improvement
comes close. EVERY row must be `known AND compatible` — `unknown` blocks the purchase.

| # | Rule | Why it matters |
|---|---|---|
| 1 | **Consistency / max-day-gain rule** | A +3% day can void a payout you already earned |
| 2 | Daily loss limit % | Sets heat: use **40% of it, never more** (ACM) |
| 3 | Total DD: static / trailing / EOD | Determines our freeze level |
| 4 | Max positions · max lot | Sets EA parameters |
| 5 | Min hold time | Interacts with ≥180s hygiene rule |
| 6 | EA / automation permitted | Read ToS, not landing page |
| 7 | News trading permitted? | Before enabling E2 |
| 8 | Weekend holds permitted? | Flat satisfies all variants |
| 9 | Multi-account / copy-trading | Unique magic + 60-120s offset |
| 10 | Scaling plan terms | Affects growth trajectory |
| 11 | Payout split, frequency, delay | Never cluster same-delay firms |
| 12 | Allowed instruments | Majors only per design |

---

## 📋 PRE-REGISTRATION PROTOCOL (MFP — The $0 Habit That Saves Everything)

Before ANY live edge testing, fill this form and date it. Changing after seeing data
is p-hacking — the evidence is void.

```
+-----------------------------------------------------------------------------+
| EDGE PRE-REGISTRATION FORM (template — create one per hypothesis)           |
+-----------------------------------------------------------------------------+
| 1. Hypothesis ID:            MFP-00X                                        |
| 2. One-sentence claim:       "[Engine] on [pair] in [session] yields         |
|                              net >= +0.15R/trade after cost"                |
| 3. Universe:                 [pairs, TFs]                                   |
| 4. Session window:           [UTC times]                                    |
| 5. Cost model:               spread + commission applied per trade          |
| 6. Expected edge (pre-data): mu_R = [estimate], sigma_R ≈ 1.0               |
| 7. Required sample:          n = (2.8 / mu_R)² trades (80% power, 95% conf)  |
| 8. Primary metric:           Net R per trade (cost-adjusted), 95% CI        |
| 9. Kill criteria (pre-agreed):                                              |
|      - Net R <= 0.00 after n trades        -> FALSIFIED, archive            |
|      - Max DD > 12R at any point           -> FALSIFIED, stop now            |
|      - Net R < 0.08R after n trades        -> NOT ECONOMIC, stop             |
| 10. Scale criteria:                                                         |
|      - Net R >= 0.15R with lower CI > 0.05R -> PROMOTE to eval stage        |
| 11. Expiry date:             [30 days from start]. No extensions.           |
| 12. Data log location:       experiments/MFP-00X/trades.csv                 |
+-----------------------------------------------------------------------------+
```

---

## 🧪 THE 30-DAY REALITY SPRINT (Before Any Architecture Is Trusted)

```
WEEK 1 — MEASUREMENT (no strategy decisions allowed)
  Day 1-2  Cost Reality Audit: 100 fills, real spread+slip AT FILL, not quote
  Day 3-4  Open micro-live account ($50-200). Set 0.01-0.10 lots.
  Day 5-7  Manual 20 trades of ANY simple setup. Learn real fills/tick/spread.
  GATE 1: c <= 5% of R? If not — change stops/pairs/broker. Do not continue.

WEEK 2 — PRE-REGISTRATION + INSTRUMENTATION
  Day 8-9   Pre-register MFP-001 (E1 SMC Core, EURUSD/GBPUSD, n=350)
  Day 10-14 Build the minimal test harness: signal+trade+cost log + R calc
            NO optimization, NO parameter sweeps.
  GATE 2: Can you reproduce any trade's cost and R from the log alone?
          If no, fix logging before trading more.

WEEK 3-4 — THE TEST (hands off the parameters)
  Run MFP-001 exactly as registered. Do not change rules mid-test.
  Parallel: start MFP-002 in a second magic number (free — same feed)
  GATE 3 (day 30): net R per trade with 95% CI
     - CI entirely below 0       -> FALSIFIED. Archive.
     - CI straddles 0, n<required -> INCONCLUSIVE. Extend.
     - CI above 0.05R             -> PROMOTE toward eval deployment.

MONTH 2-3 — only if promoted
  Apply AEM barrier overlay to the ONE promoted edge.
  Buy exactly ONE evaluation at a rule-fit firm inside a promo window.
  Compare micro-lab R vs live funded R — this gap is the most valuable
  number you will ever measure.
```

---

## 🏗️ THE 90-DAY BUILD ORDER (Layer 2+3 First, Layer 1 Last)

```
━━━━ STAGE 0 (Days 1-7): TRUTH + PROTECTION FIRST  [D8 + D2 + D4]
  ☐ Cost-Reality Audit: 100 fills, c <= 5% of R mandatory hurdle
  ☐ Pre-register MFP-001 (E1, n=350) + M4 override log active
  ☐ Code Risk Governor: -2.2% breaker, heat caps+redistribution, netting, E₅₀
  ☐ Deploy Daily HMM state script (23:55 GMT, regime flag)
  ☐ Set up Shadow ML Logger: 20-feature snapshot on EVERY signal incl. skipped
  ☐ F5-F9 gap fixes: broker-side SL, pre-trade assertions, news flat,
    weekend flat, kill-switch drill
  ☐ M1 Firm Capability Matrix (12 rows, unknown=>DO NOT BUY)
  ☐ M2 Timebase in UTC via server_utc_offset
  ☐ M3 Proxy fidelity >= 0.95 or gate NEUTRAL
  ☐ Evidence Ledger created: 12 claims marked UNTESTED + per-layer ROI row
  ☐ Procurement: raw ECN + VPS <2ms, promo calendar, EV-per-eval table
     GATE 0: (a) c <= 5% (b) drill PASS (c) matrix complete — ALL three

━━━━ STAGE 1 (Days 8-25): ONE EDGE, MEASURED
  ☐ E1 SMC Core: Dual-Bracket entry, grading, exit ladder, dead-money exit
  ☐ Native Macro Feeds: DXY SMT + USOIL CAD + yield-diff bias
  ☐ Micro-live E1: log EVERY fill + ML prediction
  ☐ D4 free gates: yield-diff bias + daily HMM state (shadow mode)
     GATE 1 (day 25): net R >= 0? → continue. Falsified → archive, try MFP-002.

━━━━ STAGE 2 (Days 26-40): SECOND ENGINE + FIRST EVAL
  ☐ E2 Asian raid coded + backtested (corr to E1 < 0.5 required)
  ☐ Buy eval #1 — ONLY inside promo window, rule-fit firm
  ☐ Apply 4-Zone Barrier Sizing (0.5%→0.35%→0.20%→0.10%)
  ☐ Exam filters ON: limit orders, ≥180s hold, no gold, no Friday, no news
  ☐ D6 stagger: remaining accounts stay demo
     GATE 2: eval progress within barrier schedule

━━━━ STAGE 3 (Days 41-60): THIRD ENGINE + ORTHOGONAL INCOME
  ☐ E3 FVG re-engagement (only if E1, E2 independently green)
  ☐ E4 Dispersion book coded (daily rebalance, 1%/book, 0.25%/leg)
  ☐ C2 Pyramid on personal C2 slice (risk-free-add gate)
  ☐ ML Audit: review first 100 logged trades; AUC > 0.65? → activate veto
  ☐ Portfolio correlation matrix: all pairs < 0.5, else cut
     GATE 3: 3 engines × ≥30 trades each → bandit allocation unlocks

━━━━ STAGE 4 (Month 3+): FACTORY SCALE
  ☐ Eval #2-#3 at different firms, different engine mixes (D6 stagger)
  ☐ Payout ladder: 25% eval fuel / 25% buffer / 50% personal compounder
  ☐ Active ML meta-labeling → 1/5-Kelly (if 500+ signals logged)
  ☐ Monthly: solvency score, promo review, rule changes, ledger update

━━━━ STAGE 5 (Month 4-6): ONLY IF LEDGER SAYS SO
  ☐ PCA/OU engine research (if dispersion validated 60+ days)
  ☐ Genetic breeder beta (if any engine shows E₅₀ < 0 for 2 months)
  ☐ CME/VPIN data trial (only if cost audit flags slippage > 3% of R)
  ☐ Rebate layer (only if firm ToS explicitly permits)
```

---

## 📊 EVIDENCE LEDGER (Living Document — Update Monthly)

Nothing may enter live risk while marked *Untested*.

| ID | Claim | Status | Measured by | Verdict |
|---|---|---|---|---|
| E-01 | Real cost per trade c ≤ 2% of R | UNTESTED | MFP Audit | - |
| E-02 | Sweep reversal ≥55% win @ RR2 | UNTESTED | MFP-001 | - |
| E-03 | SMT divergence beats plain sweep | UNTESTED | MFP-003 | - |
| E-04 | OU residual (PCA) net Sharpe > 1.0 | UNTESTED | MFP-004 | - |
| E-05 | Barrier overlay raises pass rate | UNTESTED | MFP-0
