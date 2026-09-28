# 🧪 THE MICRO-LIVE FALSIFICATION PROTOCOL (MFP)
### Proof Before Capital — The Genuinely Better Idea Beyond SAM

**Date:** 28 Sept 2026
**Status:** Tier-8 document. This is the LAST architecture file. After this, the only work that increases ROI is measurement.
**Supersedes as "next best action":** `sovereign-adversarial-matrix.md` (SAM).

---

## 0. Why this is better than SAM (and the honest disclosure)

### 0.1 The uncomfortable arithmetic of documents 1–7
```
Documents produced:        7 architectures, ~130 KB of design
Verified edges among them: 0
Real dollars produced:     0
Marginal ROI of doc #8 in the same style: ~0 (or negative — it delays testing)
```

Every previous escalation was *design*. Design has no payoff until it is
either **verified** or **falsified** in the real world. The bottleneck to your
ROI is not architectural elegance — it is **evidence per edge**.

### 0.2 Mandatory disclosure: which numbers were real, which were illustrative
To keep this honest, every quantitative claim in docs 1–7 must be labeled:

| Claim | Source doc | True status |
|---|---|---|
| Signal quality is the smallest ROI contributor (15/30/35/20 layer split) | ACM | **Modelling judgment**, not measured. Treat as a hypothesis to test. |
| Bandit allocation adds +15–35% risk-adjusted return | ACM | **Literature-derived prior** (online learning / ensemble studies). Not measured on YOUR book. |
| Firm rule-fit adds +15–25pp pass rate | ACM | **Plausible estimate** from mechanism reasoning. Not measured. |
| 1/5-Kelly sizing beats tiered sizing | ACM | **Derived from theory** assuming calibrated probabilities. Depends on p-calibration quality. |
| PCA residual stationarity, OU half-life, Kalman hedge | AEM | **Standard, well-documented mathematics.** The math is sound; the *magnitude of live profit* is unmeasured. |
| Pass rate 74.6%, ruin 1.8%, "100,000 Monte Carlo paths" | AEM | **Illustrative simulation flavor.** NOT a conducted experiment. Do not quote these as results. |
| $28k–$42k / $30k–$48k monthly projections | AEM / OAF | **Assumption chains**, not forecasts. |
| "+365% realized payout efficiency", "$15,540/cycle" | SAM | **Illustrative arithmetic on assumed P(payout) values.** P(payout)=0.96 is an assumption, not a measurement. |
| Genetic breeder + Deflated Sharpe gate | OAF | **Method is real and standard** (López de Prado). Throughput of profitable alphas on retail data is unproven. |
| Dealer plugin slippage injection, lateness flags | SAM | **Mechanism is real industry knowledge**; exact magnitudes vary by firm and are unmeasured by us. |

**The rule from here forward:** a claim is either *Verified* (measured on our own
fills), *Falsified*, or *Untested*. Nothing enters live risk while Untested.

### 0.3 What the better idea actually is
> **Buy evidence at the cheapest possible price, then buy funded accounts only
> for distributions already proven.**
>
> A $300–600 prop evaluation is the most expensive way in existence to learn
> whether an edge exists. A **$0-fee micro-live account** measuring the same
> edge costs a few dozen dollars in spread — a 10–50× cheaper evidence channel,
> with zero ToS constraints on strategy type.

That is the Micro-Live Proof Lab, and it is genuinely better than SAM, not
because it is more sophisticated, but because it converts Untested into
Verified at the lowest cost while SAM only rearranged assumptions.

---

## 1. The Micro-Live Proof Lab (the core of the better idea)

### 1.1 Cost of evidence, by channel
```
CHANNEL                          COST PER EDGE TESTED        CONSTRAINTS
------------------------------------------------------------------------------
Prop evaluation (1 account)      $300 - $600  per attempt    ToS limits, time
                                                                            limits, rules
Prop evaluation (5 accounts)     $1,500 - $3,000             same, times five
Backtest only (untrusted)        ~$0                          Overfit risk; no
                                                             slippage truth
------------------------------------------------------------------------------
MICRO-LIVE ACCOUNT (this doc)    $50 - $150 of spread,       None that matter:
                                 once, reused for unlimited  any strategy, any
                                 edge tests                   hold time, any size
------------------------------------------------------------------------------
```
One funded-evaluation dollar buys ~4 micro-live trades of proof. A single $500
eval = ~3,700 micro trades of real fill data. **The micro account is the
cheapest truth machine in retail trading.**

### 1.2 The real cost table at micro size (make this explicit, not hand-waved)
Pip value on EURUSD: 0.01 lots = **$0.10/pip**; 0.10 lots = $1.00/pip.

```
LOT   STOP(pp)  RISK/TRADE  ROUND-TRIP COST*   COST AS % OF R   VERDICT
------------------------------------------------------------------------------
0.01    10       $1.00        $0.10-$0.14        10-14%        Unusable (why scalping dies)
0.01    20       $2.00        $0.10-$0.14         5-7%         Marginal proof only
0.01   100      $10.00        $0.10-$0.14         1.0-1.4%     EXCELLENT
0.10    20      $20.00        $1.00-$1.40         5-7%         Marginal
0.10   100     $100.00        $1.00-$1.40         1.0-1.4%     EXCELLENT
------------------------------------------------------------------------------
* spread 0.8-1.0 pip + ECN commission ~$3.5/lot round turn, at typical retail ECN
```
**Law discovered for free by this table:** any edge with a stop below ~25 pips
must clear a 5–14% cost-of-R hurdle before it earns anything. This single fact
falsifies most "scalping" designs in the entire 7-document set — at zero cost.

### 1.3 Statistical power: how many trades before you may believe anything
To detect an edge of mean $\mu_R$ with standard deviation $\sigma_R \approx 1.0R$:
$$n \geq \left(\frac{z_{1-\alpha/2} + z_{1-\beta}}{\mu_R}\right)^2 = \left(\frac{1.96 + 0.84}{\mu_R}\right)^2 = \left(\frac{2.8}{\mu_R}\right)^2$$

```
EXPECTED EDGE (R/trade)   TRADES NEEDED (80% power, 95% conf)   AT 5 TRADES/DAY
------------------------------------------------------------------------------
0.05R                     3,136                                 ~2.5 years   (dead on arrival)
0.10R                       784                                 ~7 months    (slow)
0.15R                       348                                 ~3.5 months  (workable)
0.25R                       125                                 ~5 weeks     (good)
0.40R                        49                                 ~2 weeks     (excellent)
------------------------------------------------------------------------------
```
**Pre-registration consequence:** never evaluate a strategy on fewer than the
trades its expected edge requires. Evaluating a 0.15R edge on 40 trades is not
"early feedback" — it is pure noise worship, and it is the #1 reason traders
churn strategies and never accumulate evidence.


---

## 2. Pre-Registration (the single highest-ROI habit in quant research)

Fill this sheet and date it **before** writing code or looking at results.
Changing it after seeing data is p-hacking and the evidence is void.

```
+-----------------------------------------------------------------------------+
| EDGE PRE-REGISTRATION FORM                                                  |
+-----------------------------------------------------------------------------+
| 1. Hypothesis ID:            MFP-001                                        |
| 2. One-sentence claim:       "After a London-session liquidity sweep of a   |
|                              prior-day low on EURUSD, price closes back      |
|                              above the low within 3 bars >= 55% of the time |
|                              and RR=2.0 yields net >= +0.15R/trade."        |
| 3. Universe:                 EURUSD, GBPUSD (M15 entry, H1 context)         |
| 4. Session window:           07:00-11:00 server time only                   |
| 5. Cost model (mandatory):   spread 1.0 pip + commission, applied per trade |
| 6. Expected edge (pre-data): mu_R = 0.15, sigma_R = 1.0                     |
| 7. Required sample:          n = 350 trades (from power table)              |
| 8. Primary metric:           Net R per trade (cost-adjusted), 95% CI        |
| 9. Kill criteria (pre-agreed):                                              |
|      - Net R <= 0.00 after 350 trades              -> FALSIFIED, archive   |
|      - Max DD > 12R at any point                   -> FALSIFIED, stop now  |
|      - Net R < 0.08R after 350 trades              -> NOT ECONOMIC, stop   |
| 10. Scale criteria (pre-agreed):                                            |
|      - Net R >= 0.15R with lower CI > 0.05R        -> PROMOTE to eval stage |
| 11. Expiry date:            30 days from start. No extensions without a     |
|                             new hypothesis ID.                              |
| 12. Data log location:      experiments/MFP-001/trades.csv (every fill)      |
+-----------------------------------------------------------------------------+
```

**Why this beats every architecture file:** it makes self-deception impossible.
Kill criteria decided in cold blood at 09:00 beat emotional decisions made at
-6R on a Thursday night. This is the mechanism institutions call "research
governance", and it costs nothing.

---

## 3. The Cost-Reality Audit (one day of work, run it first)

Before testing any of the 7 documents' ideas, measure your actual broker
reality. Fill this table from 100 real demo/live fills — not from marketing pages.

```
+-----------------------------------------------------------------------------+
| COST REALITY AUDIT  (paste real numbers)                                    |
+-----------------------------------------------------------------------------+
| Pair      Exp. spread  Obs. spread  Avg slip (entry)  Avg slip (exit)  Swap |
| EURUSD       0.8 p        ?            ?                 ?              ?   |
| GBPUSD       1.2 p        ?            ?                 ?              ?   |
| USDJPY       0.9 p        ?            ?                 ?              ?   |
+-----------------------------------------------------------------------------+
| Derived:                                                                    |
|   real_cost_per_trade_pips = exp_spread + slip_in + slip_out + commission   |
|   cost_as_%_of_R(stop=100p) = real_cost / 100 * 100                         |
|   breakeven_winrate(RR=2)   = (1 + c) / (1 + RR)   where c = cost/R fraction|
+-----------------------------------------------------------------------------+
```
Worked example, using realistic retail numbers:
```
cost = 1.0 pip spread + 0.3 pip entry slip + 0.4 pip exit slip = 1.7 pips
stop = 100 pips  ->  c = 1.7% of R
breakeven win rate at RR 2.0 = (1 + 0.017) / 3.0 = 33.9%
```
Then re-run the same formula for a 20-pip stop: `c = 8.5%`, breakeven win rate
at RR 2.0 becomes **36.2%**. Three percentage points of win rate vanish into
cost purely from a tighter stop. **This audit alone tells you which of the 7
documents' engines are even economically possible** — and it takes one day,
zero dollars, and zero code.

Gates for proceeding:
```
If c <= 2% of R   -> proceed with confidence; cost is not your problem.
If 2% < c <= 5%   -> proceed, but expected edge must clear mu_R > 0.12R.
If c > 5% of R    -> STOP. Change stop size, pair, or broker before anything else.
```


---

## 4. Minimum Viable Edge ranking (what to test first, from all 7 docs)

Every idea across all 7 architectures, ranked by **(evidence strength ×
implementability) ÷ (data + cost burden)**:

```
+---------------------------------------------------------------------------------------+
| PRIORITY QUEUE — WHAT TO TEST, IN ORDER                                               |
+-----+---------------------------+----------+---------+---------+----------------------+
| Rnk | Idea (source doc)         | Evidence | Impl.   | Burden  | Testable in          |
+-----+---------------------------+----------+---------+---------+----------------------+
|  1  | Cost-reality audit (MFP)  | Certainty| Trivial | ~0      | 1 day, no code       |
|  2  | Execution hygiene (SAM*)  | High     | Trivial | ~0      | Immediately          |
|  3  | Barrier sizing overlay    | Strong   | Easy    | Low     | Needs pass/DD rules  |
|     | (AEM) — pure risk overlay | (math)   |         |         | + 100 evals of data  |
|  4  | Promo procurement + rule- | Medium   | Manual  | Low     | 1 week (calendar)    |
|     | fit firm choice (ACM)     |          |         |         |                      |
|  5  | Session sweep reversion   | Medium   | Easy    | Low     | 3-4 months (350 tr)  |
|     | (baseline consensus)      |          |         |         |                      |
|  6  | SMT divergence raid (AAM) | Medium   | Medium  | Medium  | 3-4 months           |
|  7  | OU residual reversion     | Strong   | Hard    | High    | 4-6 months (multi-   |
|     | (AEM) — needs PCA+Kalman  | (math)   |         |         | leg execution cost)  |
|  8  | Bandit allocation (ACM)   | Strong   | Medium  | Needs 2+| Only AFTER 2 engines |
|     |                           |          |         | engines | are independently +  |
|  9  | Joint multi-acct stagger  | Weak-Med | Medium  | 5 accts | After 1st payouts    |
|     | (OAF)                     |          |         |         |                      |
| 10  | Genetic breeder + DSR     | Strong   | Hard    | Compute | Month 4+              |
|     | (OAF)                     |          |         |         |                      |
| 11  | Avellaneda-Stoikov MM     | Strong   | Very    | Capital | Only with real       |
|     | (SAM) — personal book     | (math)   | Hard    | + infra | personal capital     |
+-----+---------------------------+----------+---------+---------+----------------------+
*SAM "camouflage" is re-scoped in section 7 as legitimate execution hygiene.
```

**Decision: test only #1–#5 in the next 90 days.** Ranks 6–11 are real but
premature; running them first is the classic failure of building infrastructure
before proving one edge.

---

## 5. The 30-Day Reality Sprint (with hard go/no-go gates)

```
WEEK 1 — MEASUREMENT (no strategy decisions allowed)
  Day 1-2  Cost Reality Audit completed. Real numbers, not web pages.
  Day 3-4  Open micro-live account ($50-$200). Set 0.01-0.10 lots.
  Day 5-7  Manual 20 trades of ANY simple setup. Purpose: learn real fills,
           tick behavior, spread behavior at each session. Log everything.
  GATE 1: c <= 5% of R? If not — change stops/pairs/broker. Do not continue.

WEEK 2 — PRE-REGISTRATION + INSTRUMENTATION
  Day 8-9   Write pre-registration MFP-001 (section 2 template).
  Day 10-14 Build the minimal test harness: signal log + trade log + cost
            fields + R calculation. NO optimisation, NO parameter sweeps.
  GATE 2: Can you reproduce, from the log alone, the exact cost and R of any
          historical trade? If no, fix logging before trading more.

WEEK 3-4 — THE TEST (hands off the parameters)
  Run MFP-001 exactly as registered. Do not change rules mid-test.
  Parallel (zero extra cost): start MFP-002 in a second magic number so two
  hypotheses gather evidence simultaneously.
  GATE 3 (day 30): net R per trade with 95% CI.
     - CI entirely below 0          -> FALSIFIED. Archive. Next hypothesis.
     - CI straddles 0, n < required -> INCONCLUSIVE. Extend by the registered n.
     - CI entirely above 0.05R      -> PROMOTE toward eval deployment stage.

MONTH 2-3 — only if promoted
  Take the ONE promoted edge and apply the AEM barrier overlay (rank #3).
  Buy exactly ONE evaluation at a rule-fit firm inside a promo window.
  Compare live live-filled results against micro-lab results (track the gap —
  this gap is the single most valuable number you will ever measure).
```

**Falsification is a win, not a loss.** Every falsified hypothesis costs ~$100
in spread and permanently removes a losing branch. Seven falsifications cost
less than two prop evaluation fees and save years of compounded losses.


---

## 6. The Evidence Ledger (living document — status of every claim we made)

This table is the honest scoreboard of all 7 previous documents. Update monthly.
Nothing may enter live risk while marked *Untested*.

```
+---------------------------------------------------------------------------------------+
| EVIDENCE LEDGER                                                                        |
+-----+------------------------------------------+---------+-------------+---------------+
| ID  | Claim                                    | Status  | Measured by | Verdict       |
+-----+------------------------------------------+---------+-------------+---------------+
| E-01| Real cost per trade c <= 2% of R         | UNTESTED| MFP Audit   | -             |
| E-02| Sweep reversal >= 55% win @ RR2          | UNTESTED| MFP-001     | -             |
| E-03| SMT divergence beats plain sweep         | UNTESTED| MFP-003     | -             |
| E-04| OU residual (PCA) net Sharpe > 1.0       | UNTESTED| MFP-004     | -             |
| E-05| Barrier overlay raises pass rate         | UNTESTED| MFP-005     | -             |
| E-06| Bandit > equal weight over 6 months      | UNTESTED| MFP-006     | -             |
| E-07| Rule-fit firm raises pass rate           | UNTESTED| MFP-007     | -             |
| E-08| Promo timed purchase lowers cost basis   | VERIFIED| Ledger      | true if real discount |
| E-09| Resting limit orders reduce negative slip| UNTESTED| Cost audit  | -             |
| E-10| Micro-lab R mirrors live funded R        | UNTESTED| MFP-008     | -             |
| E-11| Dealer slippage injection magnitude      | UNTESTED| Cost audit  | -             |
| E-12| Genetic breeder yields live Sharpe>1.2   | UNTESTED| Month 4+    | -             |
+-----+------------------------------------------+---------+-------------+---------------+
*E-05 requires many evaluations historically; measure via simulated barrier rules on
 micro-lab equity curves, then confirm on 2-3 real evals. Accept the small sample.
```

---

## 7. Honest limits & compliance (non-negotiable)

```
WHAT THIS PROTOCOL EXPLICITLY EXCLUDES (and why — it is the same reason):
  x Latency snagging / sub-second arbitrage against the broker's price feed.
      -> Almost all prop ToS prohibit it. Unenforceable claims pay $0.
  x Copying positions across accounts to create cross-account hedges.
      -> Reads as abuse/clustering; payouts get voided. Zero realized ROI.
  x Deliberate evasion of surveillance or breach of firm rules by design.
      -> Business model becomes non-defensible; single rule change = -100%.
  x Anything requiring >2x real slippage numbers you have not measured.

WHAT SAM's "CAMOUFLAGE" LEGITIMATELY MEANS, re-scoped:
  + Use limit orders where the strategy allows (better fills, universally fine).
  + Avoid pathological micro-scalping that no firm tolerates (it also dies on
    cost: see the cost-as-%-of-R table — 10-14% of R).
  + Vary position sizing naturally (standard risk management practice).
  + Hold times consistent with a normal human trading style.
  These are simply "good trading hygiene". No evasion, no edge stolen from a
  counterparty, nothing that risks a void payout.

GOVERNANCE THAT PROTECTS YOU (and is legitimate everywhere):
  + One firm's rules read in full, in writing, before purchasing that firm's eval.
  + Withdraw eligible payouts promptly; keep balances at firms you trust least.
  + Never fund an eval with money you need; max fee spend < 2% of net worth.
  + If a firm retroactively changes rules, stop buying and exit that firm.
```

**Why this section increases rather than decreases ROI:** a payout that cannot
be legally claimed is worth exactly zero, and a firm that terminates an account
for abuse takes the fee *and* the profit. Defensible operations are the only
ones that compound. No strategy is so clever that a voided payout makes it profitable.


---

## 8. Final verdict and the end of the design phase

```
+---------------------------------------------------------------------------------------+
| THE COMPLETE 8-DOCUMENT SET — AND WHERE THE VALUE ACTUALLY LIVES                      |
+---------------------------------------------------------------------------------------+
| Doc | File                              | Tier      | Real contribution               |
+-----+-----------------------------------+-----------+---------------------------------+
|  1  | strategy-recommendation.md        | Baseline  | Consensus signal library        |
|  2  | max-roi-out-of-box-strategy.md    | Structure | Funded-factory economics        |
|  3  | asymmetric-alpha-matrix.md        | Layer 1   | Intermarket signal upgrade      |
|  4  | adaptive-capital-matrix.md        | Layer 2-3 | Allocation + procurement        |
|  5  | apex-eigen-matrix.md              | Quant     | PCA/OU math + barrier control   |
|  6  | omega-alpha-factory.md            | Durability| Breeder + decay-proof loop      |
|  7  | sovereign-adversarial-matrix.md   | Realism   | Counterparty & payout reality   |
|  8  | micro-live-falsification-proto... | TRUTH     | Converts 1-7 into money or out  |
+-----+-----------------------------------+-----------+---------------------------------+
```

**The answer to "do you have a better idea?" is now final:** yes — and it is
not another architecture. Better than SAM is the protocol that forces every one
of the 7 architectures to prove itself at the cheapest possible price before a
single evaluation fee or live-risk dollar is committed. Architecture generation
is finished. From here, the only thing that changes your results is:

```
1. The Cost Reality Audit         (1 day,   $0)
2. Pre-registration MFP-001       (2 days,  $0)
3. Micro-live evidence            (30 days, ~$50-150 in spread)
4. Kill or promote, mechanically  (1 hour,  $0)
5. Only then: one promo-priced evaluation at a rule-fit firm
```

Everything else — LinUCB, PPO, VPIN, genetic breeding, market-making — stays in
the file cabinet until step 4 says PROMOTE. That discipline, not any indicator,
is where the remaining 10x of ROI actually lives.

*End of the design phase. The next document in this folder should be a
`trades.csv` with real fills in it, not another architecture.*

