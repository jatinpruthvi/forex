# 💡 RECOMMENDATIONS & NEXT STEPS

**Date:** 28 Sept 2026
**Status:** saved for execution — nothing here is implemented until Stage 0 gates it.
**Why this file exists:** the ROI review and the external "Tri-Pillar" proposal review
were both delivered in conversation. This file persists the conclusions so they are
not re-litigated. Companion artifacts: `roi-lever-scorecard.md` (the ranking),
`master-combination-strategy.md` (the operating manual).

**Method:** `benchmark-methodology` skill from
`E:\Jatin-Project\cad\cadEngine\.agents\skills` (read-only — that repo was not modified).

---

## A. Already applied to the master strategy

| # | Change | Section |
|---|---|---|
| 1 | **Heat redistribution** `r_i = H / √(1ᵀρ1)` — give headroom back to uncorrelated trades (+20–25% compound) | §2 diagram, §3, §4 Stage 0 |
| 2 | Shadow ML logger records **every signal incl. declined/C-grade** (unlocks meta-labeling ~3 months earlier) | §2 diagram, §3, §4 Stage 0 |
| 3 | **Personal risk ratchet** 0.75% → 1.25%, hard ceiling 2.2%, gated | §1 LATER, §3 |
| 4 | **Per-layer ROI telemetry** (L1/L2/L3/L4) in the Evidence Ledger | §1b, §4 Stage 0 |
| 5 | **Grade-tier sizing** on personal only; eval/funded keep grade-as-filter | §3 |
| 6 | **6th funded account** upside row with its gate | §5 |
| 7 | New **§1b layer hierarchy** + standing ordering rule | §1b |

---

## B. Do-now queue — top 6 levers, all $0, all add zero blowup risk

Ranked by *R/month per week of work*. Layers 2+3 carry **~65%** of final ROI.

| # | Lever | Expected effect | First action |
|---|---|---|---|
| 1 | **Cost engineering** | +0.05R × 38 = **+1.9R/mo ≈ +2.9%/mo** | Raw ECN + VPS <2ms + limit-only + ≥25 pips + drop gold on M15 |
| 2 | **Procurement** | **−60–90% fees; +15–25pp pass rate** | EV-per-eval table + promo calendar + prefer static/EOD-DD firms |
| 3 | **Heat budgeting** | **+20–25% compound**, zero signal change | Code the redistribution into the Risk Governor (spec in §E) |
| 4 | **Dead-money exit** | trades/mo +20–30%, **R/mo +15%** | Measure median bars-to-resolution per engine, then tune 1.5× |
| 5 | **Setup grading** | WR 40→45% = **×1.5 expectancy** | Already coded as a filter; keep as filter on eval/funded |
| 6 | **Skipped-signal logging** | $0 now, **+4R/mo at ~500 signals** | Add the `taken=false` path to the Shadow ML logger CSV |

**Standing ordering rule:** a week on Layer 3 ≈ **2.3×** the same week on Layer 1
(35% vs 15%, ACM attribution — *inference, not yet measured on our ledger*).
Only drop to Layer 1 when Layers 2 and 3 have no open gate.

---

## C. Gated — do NOT build yet (each has a trigger)

| Lever | Trigger |
|---|---|
| 6th funded account | 2 consecutive evals passed, then only inside a promo window |
| Personal risk ratchet → 1.25% | E1 ≥30 live trades with `E > 0.25R` **and** `E₅₀ > 0.35R` |
| Grade-tier sizing on personal | personal sleeve only, wrapper still caps |
| Meta-labeling / 1-5-Kelly | ~500 logged signals **including skipped ones** |
| Bandit allocation | ≥2 engines live, ≥30 trades each |
| E4 dispersion live | 60 days of logged paper book (must clear the D8 cost gate) |
| Daily HMM sizing | log-only for 30 days, then **size** — never on/off |
| 6th+ levers (PCA/OU, breeder, VPIN) | per `master-combination-strategy.md` §1 LATER table |

---

## D. Rejected on review — do not re-propose these

Full detail: **`tri-pillar-review.md`** (the complete review of the external proposal).
This section is the durable summary.

Five claims from the external `final_strategy_validation.md` ("Tri-Pillar Prop-Scaler")
were tested against our own audited corpus. Recording the rejection with its original
reason so a later tool cannot quietly reinstate them.

| # | Rejected claim | Reason | Source |
|---|---|---|---|
| 1 | **0.7R stop** for Pillar 1 | Converts winners into breakeven scratches — the corrected 3-bucket model drops expectancy **0.52R → 0.084R**. Round-4 audited and killed | `strategy-recommendation.md:275`, `master-combination-strategy.md` §3 |
| 2 | **3% total heat cap** on a 5%-daily-limit firm | = **60%** of the firm's daily budget in one move; our rule is ≤40% of the daily limit → funded heat is **2%**, breaker −2.2% | ACM §"daily loss limit"; master §3 |
| 3 | **Trade copier across 5 funded accounts** | Five accounts on identical trades = **one bet at 5× size**, not diversification; also a same-owner/copy-trading **ToS** risk that can void all payouts. Replaced by D6 stagger with *mixed* engine sets per account | D6 stagger rule; D7 counterparty defense |
| 4 | **"3 mutually exclusive, completely uncorrelated pillars"** | An assertion, not a measurement. Pillar 1 and Pillar 3 are **both momentum factors**; Pillar 1 and 2 overlap in session and symbol with *opposite* exposure. Independence must be **measured**: pairwise corr < 0.5 from logged trades, then allocated by the Daily HMM | R5A: *"if it correlates above 0.5… it's not a lever, it's leverage"* |
| 5 | **$25k/month as the base case** | The arithmetic is right but the probability is missing: ~60% pass rate, fees, 1-in-4 red months. Base case is **$16–24k/mo** on 5 accounts; **~$31k** is the gated upside on a 6th | D2 Track B; R4B §F |

**Also noted:** Pillar 2's spec implies **1.2R/trade** (0.55×3 − 0.45×1) with no audit
trail — 2× our entire audited 0.60R baseline and ~5× the `E > 0.25R` out-of-sample gate.
A spec that opens by assuming 1.2R has not been cost-audited.

**What the proposal got right** (already in our plan): the correlated-levers critique,
prop horizontal scaling as the business model, limit orders + raw ECN + majors-only,
and Pillar 2's intent as a second return family. Its *framing* (3 pillars) is a good
narrative layer over E1/E2/E4 — useful for explanation, not for parameters.

---

## E. Next step — Risk Governor specification (Stage 0, item 3)

The only top-6 lever that needs **code** rather than paperwork. Must exist and pass
tests **before any entry logic is written**.

### Order of checks (fire top-down; each can veto the rest)

```
1. BREAKERS (hard, non-negotiable)
   realized daily loss <= -2.2%  -> CLOSE ALL, disable EA 24h
   peak-to-trough DD   >=  4%    -> freeze 48h
2. HEAT BUDGET  H = 4% (personal) | 2% (funded)
3. CLUSTER CAPS (hard ceilings, redistribution may never exceed them)
   trend <= 2.5%   reversal <= 2.0%   dispersion <= 1.0%
4. NET SINGLE CURRENCY  <= 3% personal | 1.5% funded
5. REDISTRIBUTION (operates only on headroom left by steps 2-4)
   denom = sqrt(n + n*(n-1)*rho_bar)          # = sqrt(1^T rho 1)
   r_each = H_remaining / denom
```

### Worked examples (these are the acceptance tests)

| Scenario | Budget | Correlated? | Per-trade size |
|---|---|---|---|
| 3 same-direction USD legs, personal | H = 3% | yes, ρ̄ ≈ 0.85 → treat as fully correlated | **1.0%** each (total effective 3%) |
| 3 uncorrelated legs, personal | H = 3% | no | **1.7%** each (3/√3) |
| 3 same-direction USD legs, funded | H = 2% | yes | **0.67%** each |
| 3 uncorrelated legs, funded | H = 2% | no | **1.15%** each (2/√3) |

### Constraints

- **Size is computed at order placement only** — never resize mid-trade (protects the
  ≥180s hold-time hygiene rule and avoids phantom order traffic).
- **Phase 1 uses two static ρ̄ buckets** (same-direction USD legs vs everything else),
  not a rolling matrix. Upgrading to measured ρ requires ≥30 trades per engine pair.
  *Static buckets = assumption, flagged in the Evidence Ledger.*
- Cluster caps stay **ceilings**; redistribution only reallocates *unused* headroom.
  The phrase "cap is a floor" in §3 means "the budget should be used up," not "the cap
  may be exceeded."
- Breakers always fire first — redistribution must never be able to spend into a halt.

### Acceptance tests

1. Breaker test: simulated −2.2% day → flat, EA disabled, and it fires **before** any sizing logic.
2. Cap test: redistribution proposes more than a cluster cap → clamped to the cap.
3. Correlation test: the four worked examples above reproduce exactly.
4. Currency test: EURUSD + GBPUSD + AUDUSD longs → net USD exposure ≤ 1.5% funded.
5. Idempotence: re-running the governor with no new fills changes nothing.

---

## F. Evidence boundaries

- **Sourced facts:** every ROI cell in §B cites a corpus file; layer percentages are
  ACM's stated attribution; the four worked examples are R4B's arithmetic.
- **User-supplied context:** the external `final_strategy_validation.md` was reviewed;
  its content is treated as *asserted*, not evidenced.
- **Inference:** that Layers 2+3 dominate *our* outcome, and the "~2.3× per week" rule —
  well-motivated, **not yet measured on our own ledger**.
- **Recommendation:** execute §B in order; hold §C behind its triggers; code §E before
  any entry logic.
- **Monitor candidate:** per-layer ROI attribution should become a standing monthly row
  in the Evidence Ledger rather than a one-off analysis.

