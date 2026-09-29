# Tri-Pillar Review

## Bottom line

**Its structure is right; its numbers are wrong; and it's mostly rediscovering what's already in `master-combination-strategy.md` — but with two of our audited decisions quietly reversed and our entire validation protocol deleted.**

It's a good *narrative* summary and a poor *specification*. Take the framing, reject the parameters.

---

## 1. The "Tri-Pillar" already exists — it's our E1/E2/E4

| Tri-Pillar | Our engine (already specced) | Status |
|---|---|---|
| Pillar 1: Momentum & Trend (Asymmetric SMC) | **E1 SMC core** — "H4 bias → sweep → CHoCH → OB", 1.0R + 4-stage ladder | ✅ identical |
| Pillar 2: Liquidity Reversal / Swing Failure | **E2 Asian-range raid** (07–10 server, sweep & retract) | ✅ identical |
| Pillar 3: Market Neutral / Relative Strength | **E4 Dispersion rank book** (8 majors, daily, 0.25%/leg) | ✅ identical |
| "Correlation Heat Cap ≤1.5%/currency" | Deterministic Cluster Firewalls + netting (2.5/2.0/1.0, net USD 1.5% funded) | ⚠️ coarser subset |
| "E50 kill-switch" | Rolling E₅₀ throttle — but with **0.35R/0.15R warning bands** | ⚠️ downgraded |
| "0.5% × 5 funded accounts" | D2 Track A (0.5%) / Track B (0.4–0.5%) + D6 stagger | ⚠️ see flaw #3 |

Pillar 3 isn't even out-of-the-box — it's copy-pasted from `studyarena-round5-contestant-a.md:78`, verbatim: *"Long the 2 strongest majors, short the 2 weakest, sized to zero net USD exposure, rebalanced daily… 1.5–2.5%/month gross expectancy… monthly σ ~4–5%."*

And its own conclusion — *"ask what it's uncorrelated to, not how many R it promises; if it correlates above 0.5 with something you already run, it's not a lever, it's leverage"* — is the exact principle the new document then violates.

---

## 2. What's genuinely good (adopt)

- **The correlated-levers critique is correct and well-argued.** "Adding Session Breakout and ORB is taking the same trade twice" is the right diagnosis. We already acted on it (4 engines, 6–9 hard cap, pairwise corr <0.5 gate).
- **Prop horizontal scaling is the right business model.** Agreed with our D2 — it's the single highest-value insight in both documents.
- **Pillar 2's role framing** ("it earns when Pillar 1 is being chopped up") is the correct *intent* for a second return family.
- **Limit orders, raw ECN, majors-only, gold-off-M15** — all correct, all already in D1/D8.
- **Prop Firm Scaling table** (safe risk on OPM vs suicidal risk on $5k) is a fair restatement of D2.

---

## 3. What's wrong — ranked by damage

### 🔴 A. The 0.7R stop reverses an audited kill. This is the most concrete error.

Our corpus tested 0.7R and rejected it with numbers:

> **`strategy-recommendation.md:275`** — *"The tighter 0.7R stop converts too many winners into breakeven scratches, destroying the expectancy math. The corrected 3-bucket model shows **E drops from 0.52R to 0.084R**. Use 1.0R stop."*
>
> **`studyarena-round4-contestant-b:29`** — *"That's the difference between 19.5%/month and 2.5%/month, from one missing bucket. **The tighter 0.7R stop is the culprit** — it converts winners into BE-scratches faster than it saves you on losers."*

The mechanism: at 0.7R the trade hits T1, stop moves to +0.3R, then dies — **~30–35% of all trades**, returning ~+0.4R instead of the +4.18R the simplified formula assumes. The document has re-derived the *original* three-bucket arithmetic error our Round 4 corrected.

Also note a definitional problem: **R is defined by the stop distance.** A "0.7R stop" is self-referential nonsense — you can only mean either (a) a *tighter* stop in pips (which trips the D8 cost gate: stops <25 pips cost 5–14% of R), or (b) risking 0.7% instead of 1.0%. Neither is what's written.

### 🔴 B. The trade copier across 5 accounts is the biggest operational flaw

Three separate failures:

1. **It creates zero diversification.** Five accounts running identical copied trades = **one bet at 5× size**, not five. That's precisely our Round-1 warning: *"If 5 engines all go long the same pair, you have 1 trade at 5× size."* The document claims horizontal scaling as its "ROI secret" while silently concentrating the exact risk its Correlation Heat Cap is meant to prevent.
2. **It violates ToS.** Nearly every prop firm restricts same-owner multi-account networks and copy trading. One flag can void all five payouts at once — the D7 counterparty risk we specifically designed for.
3. **Our D6 stagger exists for exactly this:** never push all accounts at once, *alternate engine mixes across accounts*. The document deletes the mechanism that makes horizontal scaling survivable.

### 🟠 C. "3 mutually exclusive, completely uncorrelated pillars" is an assertion, not a measurement

- **"Mutually exclusive" is false as written.** Pillar 1 trades London/NY (07–16); Pillar 2 trades Asian (07–10 server). They overlap, on the same symbols, with *opposite* exposure — that's exposure-offset, not mutual exclusion. Legitimate, but a different claim with different consequences.
- **Pillar 1 and Pillar 3 are both momentum factors.** Cross-sectional currency strength ranking *is* a momentum factor; so is a trend-following SMC system. Calling them "completely uncorrelated" because one "ignores charts" is category error — instruments don't determine factors.
- **Pillar 2 is a fade system**, i.e. negative-skew short-volatility behavior. It doesn't reliably "make money when Pillar 1 is chopped up"; it reliably loses on breakout days and gains on range days — and the whole thing is regime-dependent.
- **We already solved this the right way:** corr <0.5 *measured from logged trades* before anything is trusted. The document wants to *declare* independence where we *test* it.

### 🟠 D. It deleted the operating system (D8)

Nothing in the Tri-Pillar spec includes: the **cost-reality audit** (c ≤ 5% of R), **pre-registration**, **sample-size gates**, or the **stage gates** that let an engine fail cheaply.

This matters most for **Pillar 3**: it holds 4 legs across 8 majors with a *daily* rebalance. That's ~4 spreads + commission per day per book. Our D8 cost math is exactly the thing that tells you whether a "smooth 1.5–2.5%/month" survives turnover. It also has no drop-out rule for when the book stops working.

Also missing: D7 hygiene rules (≥180s holds, no Friday, news ±30min, natural sizing) — which are what keep a prop payout intact, and the dead-money time exit.

### 🟡 E. The ROI arithmetic is correct but has no probability attached

`5% × $500k = $25k` — the arithmetic checks out, but as *expectancy* it's fiction because it omits:

| Missing term | Effect |
|---|---|
| ~60% eval pass rate | ~40% of attempts never reach funded |
| Eval fees | D2 caps these at ≤2% of net worth — EV drag |
| Our honest funded number | **$16–24k/month net** across 5 accounts (4–6% = $4–6k/acct gross, $3.2–4.8k net) |
| "1 month in 4 red" | Not in the document at all |
| Time to 5 simultaneous funded | Months, not day 1 |

And **"0.5% risk easily survives a 5% daily limit"** is wrong under clustering: the proposal's own 3% total heat cap equals **60% of a 5%-daily-limit firm's budget in one move**. Our rule is stricter — funded heat **2%**, −2.2% hard breaker, and ACM's *"use 40% of the daily loss limit, never more"* (40% × 5% = 2%). **Their 3% heat cap exceeds both.**

### 🟡 F. Smaller spec gaps

- **Pillar 3 has no USD-exclusion branch.** "Rank 8 majors, buy top 2, sell bottom 2, net-zero USD" breaks the moment USD *is* one of the top-2 (it can't be traded away). Example given (long GBPJPY) sidesteps it. Unspecified rule = undefined behavior in code.
- **Pillar 2's implied expectancy is 1.2R/trade** (0.55×3 − 0.45×1) with **zero** audit trail — 2× our entire audited baseline of 0.60R and 4× the E>0.25R OOS gate. A spec that opens by assuming 1.2R has not been cost-audited.
- **Pillar 2's 55% WR vs 3R target is internally suspicious**: at fixed 3R, target-hit probability usually *falls* as target distance rises; 55% at 3R is the kind of number that comes from assuming, not logging.
- **E₅₀ trigger is downgraded** to a single `E50 < 0 → 25%`. Ours is a two-band throttle (0.35R warning → half, <0 → halt) — it reacts *before* zero.
- **The 4-engine plan was already a 3-pillar plan.** E3 (FVG re-engagement) sits at 0.3–0.5 correlation to E1 — near our own gate. Folding E3 into E1 later, not launching it separately, would cut validation burden from 4×30 trades to 3×30.

---

## 4. My better suggestion

Take their architecture, restore our numbers, and fix the one thing they got conceptually wrong: **don't *assume* independence — *construct* it.**

### Better idea: make the Daily HMM the state machine that *alternates* the pillars

Instead of running Pillar 1 and Pillar 2 simultaneously and hoping for low correlation, use our **Daily Rollover HMM (23:55 GMT)** as an explicit regime allocator:

```
HMM = Trending       → size E1 at 100%, E2 at 30%   (reversals are suicide in trend)
HMM = Mean-Reverting → size E2 at 100%, E1 at 30%   (trend engine bleeds here)
HMM = Shock          → flat all directional, keep E4 only
```

This buys three things the Gemini version can't:

1. **Non-overlap by construction**, not by statistical hope — the claim becomes *architecturally true* rather than an untested assertion.
2. **E4 runs unconditionally in all states** — which is the actual justification for it being the "uncorrelated pillar."
3. **Misclassification is survivable** because it's *sizing*, not an on/off switch — a wrong state costs you 70% of size, not 100% of the edge.

Caveat: the HMM itself needs validation before you trust it — log its state for **30 days alongside realized returns** (costs nothing, Stage 0) before letting it drive sizing. Same shadow-first pattern we're already using for ML.

### The corrected spec

| Parameter | Gemini doc | **Use instead** | Why |
|---|---|---|---|
| Stop | 0.7R | **1.0R, ≥25 pips effective** | Round-4 audit: 0.7R → E falls 0.52R→0.084R |
| Pillars | 3, uncorrelated | **3 books, *measured* corr <0.5, HMM-allocated** | Independence is a hypothesis, not a setting |
| Heat cap | 3% total | **4% personal / 2% funded**, cluster 2.5/2.0/1.0 | 3% > 40% of a 5% daily limit |
| Kill switch | `E50 < 0` → 25% | **two-band: <0.35R halve, <0 halt** | Acts earlier |
| Pillar 3 live | day 1 | **60-day logged paper book → then 0.25%/leg** | 4 legs × daily turnover must clear D8 cost gate; ACM warns such sleeves underperform 2+ years |
| Scale | copier ×5 accounts | **staggered, *mixed* engine sets per account (D6)** | ToS safety + real diversification |
| ROI | $25k/mo | **$16–24k/mo net** + 10–25% personal, 1 mo in 4 red | Audit-trailed |
| Missing | — | **D8 pre-registration + cost audit + stage gates** | The system that makes claims falsifiable |
| Missing | — | **D7 hygiene** (≥180s, no gold, no Friday, news ±30) | Protects payouts |

### Order of work (unchanged, and *not* "pick a pillar to code")

```
Stage 0:  cost audit (100 fills) → Risk Governor (−2.2%, cluster caps)
          → Daily HMM state script → Shadow ML logger
Stage 1:  E1 only, micro-live, pre-registered  [GATE: net R ≥ 0]
Stage 2:  E2 + barrier sizing → eval #1 in a promo window
Stage 3:  E4 paper book 60 days, then live at 0.25%/leg
Stage 4:  mixed-engine account expansion (D6), payout ladder
```
