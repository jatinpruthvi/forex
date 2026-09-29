# 📊 ROI LEVER SCORECARD — ranked by R/month per week of work

**Purpose:** decide which levers actually buy the most ROI per unit of effort,
capital and survival-risk — and say what is deferred and why.
**Companion:** `master-combination-strategy.md` (the operating manual; this file
ranks the levers that feed it).
**Date:** 28 Sept 2026

**Method source:** `benchmark-methodology` from
`E:\Jatin-Project\cad\cadEngine\.agents\skills` (read-only; that repo untouched).
Its rules were adapted from *scoring competitors* to *scoring strategy levers*:
same dimensions for every candidate, explicit 1–5 anchors, an evidence source for
every score, and no false composite average.

---

## 0. Why this skill

"Improve the strategy for best ROI" is not a brainstorm — it is a **scoring
problem**: many candidate levers, one evidence base, one ordering. The skill's
bias controls are precisely what our corpus is for:

> *"A score without evidence is an opinion, not a benchmark."*
> *"Downgrade credibility for self-reported claims with no corroboration."*
> *"No single composite score — report dimension scores and the tension plot separately."*

That last rule is exactly why the Tri-Pillar proposal failed review: it asserted
one blended claim ("20%+ ROI, completely uncorrelated") instead of showing dimensions.

---

## 1. The strategic tension (both poles scored, **never averaged**)

| Pole | Meaning |
|---|---|
| **A. Return** | How much ROI does this lever add if it works? |
| **B. Ruin-avoidance** | Does it protect or threaten prop-firm survival and payouts? |

The gap between the poles **is** the finding. High-Return + low-Ruin-avoidance is
*leverage*, not a lever — the exact trap D8 was written to catch.

---

## 2. Dimensions and weights (sum = 100%)

| # | Dimension | Weight | What a 5 means |
|---|---|---|---|
| 1 | **Expected ROI contribution** | 25% | ≥ +3R/mo or ≥ +3%/mo, from an audited cell |
| 2 | **Evidence strength** | 20% | arithmetic or cost-table backed; reproducible |
| 3 | **Implementation burden** (inverted) | 15% | ≤ 2 days of work, no new dependency |
| 4 | **Capital / cash cost** (inverted) | 10% | ~$0 — no fees, no data, no subscriptions |
| 5 | **Time-to-impact** (inverted) | 15% | pays inside week 1 |
| 6 | **Failure blast radius** (inverted) | 15% | if wrong, cheap and fully reversible |

**Inverted** = a 5 is *good* (low burden / low cost / fast / safe).

### Rubric anchors (calibrated for this set)

- **ROI:** 5 = ≥3R/mo independently derivable · 4 = 1–3R/mo · 3 = <1R/mo but real ·
  2 = compounding only · 1 = unquantified.
- **Evidence:** 5 = arithmetic from a cost table/formula · 4 = backtested with a
  stated audit trail · 3 = plausible, partially measured · 2 = asserted, no sample ·
  1 = marketing claim.
- **Blast radius:** 5 = bounded, costs $0 · 4 = bounded to one eval fee · 3 = one
  account · 2 = correlated whole-farm failure · 1 = can void all payouts.

---

## 3. The scorecard

`ROI` = only the number our own corpus supports. **R4B** = `studyarena-round4-contestant-b (1).md`,
**R2B** = `studyarena-round2-contestant-b.md`, **ACM** = `adaptive-capital-matrix.md`,
**R5A** = `studyarena-round5-contestant-a.md`.

| # | Lever | Layer | ROI contribution (source) | Evid | Burden | Cost | Speed | Blast |
|---|---|---|---|---|---|---|---|---|
| L1 | **Cost engineering** — raw ECN, limit-only, VPS <2ms, ≥25 pips, drop gold | 3 | +0.05R × 38 = **+1.9R/mo ≈ +2.9%/mo** (R4B §E) | 5 | 5 | 5 | 5 | 5 |
| L2 | **Procurement** — promo-window evals, firm-rule fit, EV-per-eval | 3 | **−60–90% fees; +15–25pp pass rate** (ACM) | 5 | 4 | 5 | 5 | 5 |
| L3 | **Correlated heat budgeting** — cap → redistribute by ρ | 2 | **+20–25% compound**, zero signal change (R4B §A) | 4 | 4 | 5 | 4 | 5 |
| L4 | **Dead-money time exit** — recycle occupied slots | 2 | trades/mo +20–30%, **R/mo +15%** (R4B §C) | 4 | 5 | 5 | 5 | 5 |
| L5 | **Setup grading** — 0–10 → A/B/C/skip | 1 | WR 40→45% = **×1.5 expectancy; +40–70%/mo** (R2B §3) | 4 | 4 | 5 | 5 | 4 |
| L6 | **Skipped-signal logging** — log C-grades too | 2 | $0 now, **unlocks +4R/mo at 500 signals** (R4B §B) | 5 | 5 | 5 | 5 | 5 |
| L7 | **6th funded account** | 3 | **+$5.2k/mo** → up to ~$31k total (R4B §F) | 4 | 2 | 3 | 2 | 4 |
| L8 | **Personal risk ratchet** 0.75% → 1.25%, gated | 2 | **+67%** on all personal R | 4 | 5 | 5 | 3 | 3 |
| L9 | **Runner / exit ladder** | 1 | fixed 3R → ladder = **×1.7 on R** (R2B §1) | 4 | 4 | 5 | 5 | 4 |
| L10 | **Pyramiding C2b** (personal only) | 2 | **+0.15–0.25R/trade** (R4B §D) | 3 | 3 | 5 | 4 | 3 |
| L11 | **E4 dispersion sleeve** | 4 | **+1.5–2.5%/slice** (R5A/ACM) | 3 | 2 | 4 | 2 | 4 |
| L12 | **Grade-tier sizing on personal** A(8+) 2.5% | 2 | +40–70% on that sleeve (R2B §3) | 3 | 4 | 5 | 4 | 2 |
| L13 | **Meta-labeling** P > 0.55 gate | 1 | **+5–8 WR pts ≈ +4R/mo** (R4B §B) | 2 | 1 | 3 | 1 | 4 |
| L14 | **Bandit allocation** | 2 | +15–35% risk-adjusted (ACM) | 2 | 2 | 4 | 2 | 4 |
| L15 | **Daily HMM regime gate** | 1 | unquantified — cuts chop losses | 1 | 3 | 4 | 3 | 4 |

**No composite score is published**, per the skill's rules. The ordering unit is the
corpus's own native one — **R/month per week of work** (R4B's framing):

```
RANK BY R/MONTH PER WEEK OF WORK
 1  L1  cost engineering    week 1, highest certainty in the whole corpus
 2  L2  procurement         arithmetic certainty, no market risk
 3  L3  heat budgeting      "the free 25%", zero signal change
 4  L4  dead-money exit     already coded; only the median must be measured
 5  L5  grading             already coded; acts as a filter before it sizes
 6  L6  skipped-signal log  costs nothing, pays +4R/mo a quarter later
 --  --- below the line: gated on EVIDENCE, not on enthusiasm ---
 7  L7  6th account         GATE 2 consecutive evals passed
 8  L8  personal ratchet    GATE E1 >=30 live trades with E > 0.25R
 9  L9  runner ladder       IN PLACE (D1)
10  L10 pyramiding          IN PLACE (personal C2 only)
11  L11 dispersion          GATE 60 days of logged paper book
12  L12 grade-tier sizing   GATE personal sleeve only, wrapper still caps
13  L13 meta-labeling       GATE 500 logged signals incl. skipped
14  L14 bandit              GATE 2 engines x 30 trades
15  L15 HMM gate            LOG-ONLY 30 days, then SIZE (never on/off)
```

---

## 4. Tension plot (both poles, reported separately)

| Lever | **A. Return** | **B. Ruin-avoidance** | Quadrant |
|---|---|---|---|
| L1 cost engineering | 5 | 5 | **high/high — free ROI** |
| L2 procurement | 4 | 5 | high/high |
| L3 heat budgeting | 4 | 5 | high/high |
| L4 dead-money exit | 3 | 5 | high/high |
| L5 grading (as filter) | 4 | 5 | high/high |
| L6 skipped-signal log | 1 | 5 | low/high — **pure option value** |
| L7 6th account | 5 | 3 | high return / medium ruin |
| L8 personal ratchet | 5 | 3 | high return / gated |
| L12 grade-tier sizing | 5 | 2 | **the danger quadrant** |
| L11 dispersion | 3 | 4 | mid/mid, negative skew |
| L13 meta-labeling | 5 | 4 | high/high, but late |
| L15 HMM gate | 3 | 3 | unmeasured — **log only first** |

**The reading:** everything in the *high/high* quadrant costs **$0 and adds no blowup
risk** — that is the real "best ROI" answer, and it is all Layer 2/3 work. The
high-return / low-survival quadrant (L8, L12) is where the 40%-month trap lives.

---

## 5. The ROI layer hierarchy — why the ordering looks like this

ACM's audited attribution, *"the honest hierarchy of what actually creates maximum ROI"*:

```
LAYER 1  Signal alpha       (better entries)              ~15% of final ROI
LAYER 2  Allocation alpha   (which engine, what size)     ~30% of final ROI
LAYER 3  Structural alpha   (evals, firms, fees, cost)    ~35% of final ROI
LAYER 4  Income alpha       (uncorrelated sleeves)        ~20% of final ROI
```

**Finding:** Layers 2 + 3 = **65% of final ROI**, yet the master build order spends
Stages 1–3 building Layer 1 (15%). Layers 2–4 are already *present* in the master
strategy — what is genuinely missing is **two mechanisms and one telemetry hook**:

| Missing piece | Layer | Cost of not adding it |
|---|---|---|
| Heat **redistribution**, not just heat **capping** | 2 | we only ever *cut* size, never return it to uncorrelated trades — leaving ~20–25% compound growth on the table |
| Log **skipped** signals, not just taken ones | 2 | meta-labeling starts ~3 months late ≈ 12R foregone |
| A **risk ratchet** with an evidence gate | 2 | personal sleeve stays at 0.75% forever even after the edge is proven |
| **Per-layer ROI telemetry** in the Evidence Ledger | 2/3 | nobody can see which layer is actually carrying the month |

---

## 6. Evidence boundaries (per `research-ops` output discipline)

- **Sourced facts:** every ROI cell in §3 cites a file; the layer percentages are
  ACM's own stated attribution, not mine.
- **User-supplied context:** none in this pass.
- **Inference:** the claim that Layers 2+3 dominate *our* outcome — well-motivated by
  ACM's attribution but **not yet measured on our own ledger**. Treat as inference.
- **Recommendation:** implement L1/L2/L3/L6 now; gate L7/L8/L12/L13 behind the
  stated triggers. **Monitor candidate:** per-layer ROI attribution should become a
  standing monthly row in the Evidence Ledger rather than a one-off analysis.

---

## 7. Bias controls applied

- **No composite score.** Columns are reported individually; the rank uses the
  corpus's own R/mo-per-week unit, not an average.
- **Asserted vs proven.** L13/L14/L15 are scored 1–2 on evidence precisely because
  they have no live sample — not because they are bad ideas.
- **Aesthetic/flashiness bias.** The "out-of-the-box" pillars (L11, L15) are *not*
  scored up for being novel; L1's unglamorous procurement work scores highest
  because it is arithmetic.
- **Calibrate across the set.** A "5" on evidence means the same thing for L1 and
  L2 (both arithmetic) as it does for L11 (3: partially measured) — re-read
  side-by-side before trusting the ordering.

## Anti-patterns deliberately avoided

- Ranking by ROI alone (that is how blowups get ranked #1).
- Presenting one blended "expected ROI" figure with no dimension breakdown.
- Scoring a lever without a source file.
- Treating a deferred lever (L7–L15) as a rejected one — each carries a trigger.


