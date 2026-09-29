# 🛡️ RUIN-PROOFING & SURVIVAL BUDGET — deterministic gates only

**Date:** 28 Sept 2026
**Question:** can this strategy blow up account capital, and how do we *prove* it can't?
**Companions:** `roi-lever-scorecard.md` (ROI ranking), `recommendations-and-next-steps.md`
(execution queue), `master-combination-strategy.md` (operating manual).

---

## 0. Skill selection

**Selected: `delivery-gate`** from `E:\Jatin-Project\cad\cadEngine\.agents\skills`
(read-only — that repo is unmodified; every file read still timestamps `06:44:39`).

Re-ranked the library with the new keyword (*survival / blow-up / gate*):

| # | Skill | Why it matches | Verdict |
|---|---|---|---|
| **1** | **`delivery-gate`** | *"Stop hook that blocks… until quality checks pass"*; *"deterministic checks… **No AI inference**"*; *"the same pattern as CI pipeline gates — automated, deterministic checks that verify machine-readable facts **rather than trusting self-reported status**"* | **SELECTED** |
| 2 | `operator-approval-loop` | Hard-gates irreversible actions; *"drafts without a deadline stay hard-gated forever"* | Complementary — the "never auto-approve a risk increase" principle only |
| 3 | `verification-before-completion` | Don't claim done without checking | Subset of delivery-gate |
| 4 | `benchmark-methodology` | Scores candidates (used last pass for the ROI ranking) | Already applied |

**Why it transfers.** A trading strategy is only as safe as its *tested* kill-switches.
Delivery-gate's doctrine maps one-to-one onto ruin-proofing:

| `delivery-gate` concept | Ruin-proofing translation |
|---|---|
| Deterministic check, no AI inference | Limits must be **arithmetic**, not judgement: `realized ≤ −2.2%`, `heat ≤ 2%` |
| Machine-readable facts, not self-reported status | *"The breaker is probably fine"* is not evidence — a **forced-drill log** is |
| **Block** vs **Warning** thresholds | Hard blocks (breach → flat) vs warnings (E₅₀ band → halve) |
| Rationalization detection (`"skip tests for now"`) | Detecting risk-control rationalization: *"skip the drill, it passed last week"* |
| Disk < 15 GB → **block** | Heat > cap, or a drill that failed → **no entries this week** |

`benchmark-methodology` still governs *ranking the ROI levers*; `delivery-gate` governs
*whether we are allowed to say the system is safe*.

---

## 1. The survival budget — worst case at every timescale

Every row must fit inside the **tighter** of (our own limit) and (the firm's limit).
Funded firm limits assumed: **5% daily / 10% total** (D4 firm-rule matrix).

| Timescale | Control | Worst case (funded) | Firm limit | Headroom |
|---|---|---|---|---|
| Single trade | 1.0R hard stop, ≥25 pips effective | −0.5% | — | — |
| Open heat | heat cap **2%** | −2% nominal | 5% daily | 2.5× |
| Intraday bleed | **−2.2% realized → close-all, disable 24h** | −2.2% | 5% daily | 2.3× |
| Multi-day bleed | **4% trailing DD → 48h freeze** | −4% | 10% total | 2.5× |
| Edge decay | E₅₀ <0.15R halve · <0 halt | risk → 0 | — | ∞ |
| Correlated cluster | netting ≤1.5%/currency + redistribution | ≈2% | 5% daily | 2.5× |
| **News event** | **flat before Tier-1 news** *(new — §3)* | **0** | 5% | ∞ |
| **Weekend** | **flat before weekend** *(new — §3)* | **0** | — | ∞ |
| **EA / VPS failure** | **broker-side hard SL on every fill** *(new — §3)* | ≈−2% (stops execute at broker) | 5% | 2.5× |
| **Lot-sizing bug** | **pre-trade max-lot assertion** *(new — §3)* | order refused | — | ∞ |

### The three numbers that justify the risk level

**1. Worst expected losing streak** (longest-run formula `k = ln(N)/ln(1/p)`, N=300
trades/yr, our audited p(win) = 0.40):

```
k = ln(300) / ln(1/0.40) = 5.70 / 0.916 ≈ 6.2  →  plan for a 6–7 loss streak
```

| Risk/trade | Drawdown from that streak | Verdict |
|---|---|---|
| **0.5% (funded)** | **≈ 3.1%** | under the 4% freeze — the expected worst streak **never even trips it** |
| 1.5% | ≈ 9.3% | blows through the 4% freeze and sits at 93% of the firm's 10% total limit |

> **This is the arithmetic reason 1.5% is banned on funded capital** — not caution.
> The same streak that is a non-event at 0.5% is a near-breach at 1.5%.

**2. Monthly breach probability** (using R4B's own variance model: monthly σ ≈ 15% at
1.5% risk, ≈ 5% at 0.5% risk):

| Risk | 10% total limit as σ | Approx. monthly probability of hitting it |
|---|---|---|
| 1.5% | 10/15 = **0.67σ** | **≈ 25%** — matches R4B's *"one month in four"* |
| **0.5%** | 10/5 = **2.0σ** | **≈ 2–3%** |

*Derived from R4B's stated model under a normal approximation — **inference, not a
measured result.** Flagged in the Evidence Ledger as such.*

**3. Distance from the geometric ceiling.** Full Kelly on our model gives `r* = 13%`;
R4B's safe fraction is `r*/6 ≈ 2.2%`. At **0.5% we run 23% of the ceiling**; the
personal ratchet to 1.25% still sits at **57%**. There is no sizing-based blow-up path
inside those bounds — **blow-up risk comes from gaps, clustering and control failure,
not from the risk-per-trade number.**

---

## 2. Blow-up matrix — every way the account dies

"Covered" means a control exists **and is deterministic**. "GAP" means the failure was
identified but a control was never adopted.

| # | Failure mode | Control | Worst case (funded) | Verdict |
|---|---|---|---|---|
| F1 | Normal losing day | −2.2% realized → close-all, disable 24h | −2.2% | ✅ covered |
| F2 | Multi-day chop bleed | 4% trailing DD → 48h freeze | −4% | ✅ covered |
| F3 | Edge decays / model dies | E₅₀ <0.15R halve, <0 halt | risk → 0 | ✅ covered (slow — see F11) |
| F4 | Correlated cluster stops together | heat 2% + netting ≤1.5%/currency + redistribution | ≈ −2% | ✅ covered |
| F5 | **Tier-1 news gaps through the stop** | *none — our rule is entry-only* | **−2…−4% instant → breach spiral** | ❌ **GAP** |
| F6 | **Weekend gap on a held position** | *none on funded/personal (evals only)* | unbounded by design | ❌ **GAP** |
| F7 | **VPS/EA dies — breaker never fires** | *none — no broker-side invariant* | whatever the market does | ❌ **GAP** |
| F8 | **Lot-sizing bug puts 10× size on** | *none — no pre-trade assertion* | 10× intended risk | ❌ **GAP** |
| F9 | **The breaker itself is broken** | *none — backtested, never drill-tested live* | undetected → no ceiling | ❌ **GAP** |
| F10 | Correlation spikes to ~1.0 in a crash | netting ≤1.5%/currency | ≈1.5% × gap | ✅ covered (residual gap risk) |
| F11 | E₅₀ lag (50 trades ≈ 6 weeks) | daily breaker + DD freeze cover meanwhile | bounded by F1/F2 | ✅ acceptable |
| F12 | Consecutive-loss streak | daily breaker (intra-day) + DD freeze (multi-day) + E₅₀ (edge) | ≈3.1% | ✅ **checked — see below** |
| F13 | Revenge / tilt after a failed eval | −2% daily + 48h pause + A-setups-only (D2) | bounded | ✅ covered |
| F14 | Whole funded farm dies the same day | D6 stagger — never push all accounts, mixed engine sets | compartmentalized | ✅ covered |
| F15 | Firm or broker fails to pay | D7 solvency score + payout-first withdrawal | fees only | ✅ covered |
| F16 | ToS flag (copy-trading / identical fills) | unique magic + 60–120s entry offset per account (D2) | payout denied | ✅ covered (in D2) |

### One lever deliberately **not** added

A consecutive-loss streak brake (*"3 losses → halve, 5 → halt"*) looks prudent and is
**redundant**. Losses already stop out at ≤0.5% each, and the three timescales are
covered independently — daily breaker (same day), 4% DD freeze (same week), E₅₀ (same
edge). Worse, at 40% WR three losses in a row happens **21.6%** of the time, so a brake
there taxes expectancy without touching a real blow-up vector. *Rejected as complexity.*

---

## 3. The five gaps and their fixes

### Why F5 is mandatory, not optional — the gap-equivalence math

```
funded heat cap                        = 2.0%
worst plausible gap/slippage multiple  ≈ 2.5× nominal stop distance
2.0% × 2.5                             = 5.0%
firm daily loss limit                  = 5.0%   ->  headroom = 0
```

**A news-day gap on a full-heat correlated cluster lands exactly on the firm's daily
limit** — before any breaker can act, because the breaker only fires on *realized* loss
and a gap realizes instantly. D2 already names this failure:

> `News spike on funded | Instant −2–4%, breach spiral | Spread-guard skip + 30-min news blackout + −2.5% daily hard close`

We adopted the entry blackout. We never adopted the **hold** rule. Closed:

| Gap | Fix | Cost |
|---|---|---|
| **F5 News hold** | **Close all open positions ≥15 min before any Tier-1 release**; no entries ±30 min. Heat = 0 through the event ⇒ gap loss = 0 | none — the news spike is a breach vector, not a measured edge |
| **F6 Weekend flat** | **No positions carried over the weekend on eval/funded.** Firm weekend-hold rules differ (D4) — flat satisfies every variant | forgives the gap-fill lever, already rejected by R4B as <2R/month |
| **F7 Broker-side stops** | **Every fill must carry a hard SL order at the broker.** The EA's −2.2% breaker is *defense in depth*, never the only line. EA/VPS death then caps loss at the stop, not at ∞ | none |
| **F8 Pre-trade assertions** | Refuse the order if: lot > symbol cap · projected heat > cluster cap · projected net currency > cap · margin level would fall below floor. **All four are arithmetic, no judgement** | none |
| **F9 Kill-switch drill** | **Every Sunday, in demo:** force a −2.2% condition and assert `positions → flat` + `EA disabled 24h`. Log PASS/FAIL. A FAIL is a **BLOCK** on going live that week | ~30 min/week |

F5 and F6 both work by driving **heat to 0**, not by trying to size for a gap — sizing
for an unbounded gap is impossible; refusing to be present is not.

---

## 4. Deterministic go-live gate (`delivery-gate` structure)

**BLOCK** — no entries until resolved. Machine-verifiable only, no inference.

| ID | Block when |
|---|---|
| B1 | Forced breaker drill **FAILED**, or is >7 days old |
| B2 | Any of the four pre-trade assertions (F8) not implemented |
| B3 | An open position exists within ±15 min of a Tier-1 release |
| B4 | An open position exists at weekend close on an eval/funded account |
| B5 | Any open position has no broker-side SL attached |
| B6 | Cost audit `c > 5%` of R |
| B7 | `E₅₀ < 0` — EA is halted |
| B8 | Projected heat > cap, or projected net currency > cap |

**WARN** — keep trading, reduce risk.

| ID | Warn when | Action |
|---|---|---|
| W1 | `E₅₀ ∈ (0.15, 0.35]` | halve risk |
| W2 | 4% trailing DD freeze active | no new entries for 48h |
| W3 | spread > 1.5× normal | skip that setup |
| W4 | drill passed but not this week | schedule it |

**Rationalization detector** — warn-only, exactly as `delivery-gate` specifies (regex
false-positives must never block):
`"skip the drill"` · `"it worked last time"` · `"the breaker is fine"` ·
`"just this once"` · `"news won't matter"` · `"temporary override"`

---

## 5. Where ROI and safety agree

The instinct is that safety costs return. Here it does not:

- **Funded accounts are capped by the firm, not by Kelly.** At 0.5% we use **23%** of
  the 2.2% geometric ceiling — the binding constraint is the firm's 5%/10%, not the math.
  ⇒ **Raise ROI on funded accounts by increasing account COUNT (Layer 3), never size.**
- **Personal accounts have no firm ceiling.** That is where the ratchet belongs:
  0.75% → 1.25%, hard-capped at 2.2% (57% of ceiling).
  ⇒ **size lives on your own money; count lives on theirs.**
- **The five new controls cost ≈0 expectancy** and remove the only paths that actually
  reach a breach. They are Layer-3 work: cheap, structural, high certainty.

> **Rule: never buy ROI with tail risk. The 5% month you skip is worth less than the
> account that survives to compound.**

---

## 6. Honest limits of this analysis

- The monthly-breach table in §1 is **inference** from R4B's variance model under a
  normal approximation — **not a measured result**. The streak figure assumes all losses
  at full risk with no intervening wins (deliberately pessimistic).
- Worst gap multiple `2.5×` is an **assumption**, flagged in the Evidence Ledger. Replace
  it with observed gap slippage from the 100-fill cost audit (Stage 0).
- "Covered" in §2 means a control is **specified**, not **implemented or drilled**. B1
  exists precisely because specification ≠ evidence.
- Nothing here replaces the D8 protocol. An unregistered, untested strategy is not safe
  regardless of how many gates it documents.


