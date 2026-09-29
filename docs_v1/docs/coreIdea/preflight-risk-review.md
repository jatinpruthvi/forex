# ✈️ PRE-FLIGHT RISK REVIEW — strategy before it touches money

**Date:** 28 Sept 2026
**Method source:** `prediction-market-risk-review` from
`E:\Jatin-Project\Broker\Implementation\opencode\Architech\.agents\skills`
(read-only — that repo is unmodified).
**Companions:** `roi-lever-scorecard.md` (ranking) · `ruin-proofing-survival-budget.md`
(anti-blow-up) · `master-combination-strategy.md` (manual).

### Why this skill, third time

Two prior passes already scored the levers (`benchmark-methodology`) and proved the
kill-switches (`delivery-gate`). What remained unreviewed was the **workflow boundary**
this skill is written for: *"Review… trading-agent workflows for compliance, safety,
data-quality, privacy, and execution risk. **Use before any workflow** handles venue
auth, portfolio data, API keys, or trade planning."*

It is the only skill in that library that reviews a **trading workflow end-to-end**,
and it produced findings the other two could not see — including the single largest
payout risk in the entire corpus.

---

## 1. Scope reviewed

| Gate | What was checked |
|---|---|
| **Advice boundary** | whether the corpus is informational vs decisional; where human judgement stays |
| **Venue & regulatory boundary** | prop-firm ToS dimensions: EA rules, consistency/payout rules, account limits, weekend/news/hold rules, copy-trading, scaling plans |
| **Data quality** | timebase, session windows, proxy fidelity, spread-at-fill, stale prices, news calendar |
| **Security** | credential handling, scopes, circuit breakers, dry runs, human approval |
| **Privacy** | portfolio/financial data handled by the system |
| **Execution risk** | (covered by `ruin-proofing-survival-budget.md` — reviewed there, cross-referenced, not re-litigated) |

Method: every gate was searched against the full 27-document corpus, not against memory.

---

## 2. Findings — pass / warn / fail

### 🔴 FAIL → BLOCK

| ID | Gate | Finding | Evidence |
|---|---|---|---|
| **P1** | Venue | **Consistency / max-day-gain rule is nowhere in the corpus.** Many firms require best single day ≤ 30–50% of total profit at payout. A normal `+3%` day against a `−2.2%` breaker can **void a payout the strategy already earned** | `consistency rule` / `max day` / `best day … total profit` → **0 hits in 27 files** |
| **P2** | Data | **Killzones have no declared timebase.** E2 and MFP are specified as *"07:00–10:00 **server time**"* — but server time differs per broker, and **DST shifts it by an hour twice a year**. Switch brokers or cross a DST boundary and the killzone silently drifts | only 3 hits for `server time`; **0** for `GMT offset` / `DST` / `daylight` |
| **P3** | Data | **DXY / USOIL proxy fidelity is never validated.** The Safe-Hybrid SMT gate reads a broker-native proxy; nothing checks it tracks the real instrument. A low-fidelity proxy makes the gate **noise, or actively wrong** | only 2 hits, both "deploy/pull the proxy" — **no validation step** |
| **P4** | Advice | **Manual overrides are not logged, and would silently invalidate MFP-001.** The corpus aspires to *"zero human discretion"* but has no rule that an override is an event — a pre-registered experiment with unlogged interventions is uninterpretable | `override` → 4 hits, none defining a log |

### 🟡 WARN

| ID | Gate | Finding |
|---|---|---|
| P5 | Venue | EA/automation permission, news ban, min-hold and scaling-plan terms **vary per firm** — ACM says *"Read the ToS, not the landing page"* but there is no pre-purchase matrix with an **unknown → block** rule |
| P6 | Data | Cost audit must record spread **at fill**, not at quote — otherwise the `c ≤ 5% of R` gate is measured on the wrong number |
| P7 | Data | News calendar **source and timezone undefined**, yet P1/P2 and the Tier-1 flat rule all depend on it |
| P8 | Data | No stale-price guard: all time-based rules assume a live feed |
| P9 | Security | Credentials live on the VPS; the EA must never write keys/passwords to logs or reports |
| P10 | Security | Logging and execution should use **separate scopes** — the Shadow ML logger needs read-only |

### 🟢 PASS

| ID | Gate | Finding |
|---|---|---|
| P11 | Security | Circuit breakers, spend limits, dry runs and human approval **before** any execution already exist (Stage 0: no entries until Gate 0 passes both conditions) |
| P12 | Venue | Copy-trade flag / multi-account rules already handled (unique magic + 60–120s entry offset, D6 stagger) |
| P13 | Venue | Weekend-hold variance now handled — flat satisfies every variant |
| P14 | Privacy | No third-party user portfolio data; operation is self-directed. Data retained is our own trade log, needed for the ledger |
| P15 | Advice | Size/entry recommendations are informational and gated behind Stage 1's `net R ≥ 0` test |

---

## 3. Blocked actions (until §4 is implemented)

1. **Buying any evaluation** whose consistency / max-day-gain rule is unknown → **P1**
2. **Going live with killzones in raw server time** → **P2**
3. **Enabling the DXY SMT gate** on an unvalidated proxy → **P3**
4. **Starting MFP-001** while manual overrides can happen unlogged → **P4**
5. Any further execution-capable coding — per this skill's contract that requires
   **a separate implementation plan and explicit user approval**

---

## 4. Required mitigations

### M1 — Firm Capability Matrix (fixes P1, P5) · Layer 3, largest single-item EV in the corpus

A pre-purchase checklist. **Every row must be `known AND compatible` — `unknown` blocks the purchase.**

| # | Rule | Why it matters |
|---|---|---|
| 1 | **Consistency / max-day-gain rule** | a `+3%` day can void a payout the strategy already earned |
| 2 | Daily loss limit % | sets heat: use **40% of it, never more** |
| 3 | Total DD: static / trailing / EOD | determines our freeze level |
| 4 | Max positions · max lot | |
| 5 | Min hold time | interacts with our ≥180s hygiene |
| 6 | EA / automation permitted | *"read the ToS, not the landing page"* |
| 7 | News trading permitted? (± min) | before E2 is enabled |
| 8 | Weekend holds permitted? | flat now satisfies every variant |
| 9 | Multi-account / copy-trading limits | unique magic + 60–120s offset |
| 10 | Scaling plan terms | |
| 11 | Payout split, frequency, delay | never cluster firms with the same payout delay |
| 12 | Allowed instruments · prohibited strategies · jurisdiction | |

> **ROI logic:** one voided payout = **−100% of that account's expected value**
> ($4–6k/mo gross). No signal improvement in the corpus comes close to that EV.

### M2 — Timebase normalization (fixes P2) · protects E1 + E2 = 11–15R/mo

```
DECLARE EVERY WINDOW IN UTC, never in "server time"
  London killzone   07:00-10:00 UTC
  NY killzone       13:00-16:00 UTC
  Daily HMM         23:55 UTC
  Tier-1 blackout   calendar time, stated in UTC

AT CONNECT: read broker's server_utc_offset, assert it is known
  -> convert UTC windows to server time for the day
  -> re-derive on DST change (2 fixed dates) and on ANY broker change
FAIL-SAFE: unknown offset -> no entries
```

Today the corpus says *"07:00-10:00 server time"* with **0** mentions of offset or DST —
so the same EA on two brokers trades two different strategies, and drifts an hour twice
a year without ever raising an error.

### M3 — Proxy fidelity gate (fixes P3) · zero external APIs required

Before the SMT gate is allowed to be **on**, validate it against data we already hold:

```
composite_USD = basket of the 8 majors we already quote
over the last 30 daily bars:
    pearson(broker_DXY, composite_USD) >= 0.95   -> PASS
    mean |log-ratio drift|             <= 0.3%/day -> PASS
BOTH must hold -> enable SMT gate
EITHER fails  -> SMT gate stays NEUTRAL (not biased), log the failure
```

Fail-safe direction matters: an unvalidated proxy must make the gate **neutral**, never
"assume USD is fine." **Bad data is worse than no data** — a WR lever fed noise subtracts
expectancy instead of adding it.

### M4 — Override log (fixes P4) · protects the $0 cost of MFP-001

Every manual intervention (skip, early close, resize, cancel) is appended with
`timestamp · reason · resulting R`. Rules:

- **An unlogged override invalidates MFP-001 for the affected trades.**
- Trades touched by a *logged* override are tagged and reported **both** with and without.

A pre-registration with unrecorded human judgement is not evidence — it is a story.

### M5 — Credential hygiene & scope separation (P9, P10)

- No keys, passwords or tokens in EA logs, reports or git — VPS credentials only.
- **Shadow ML logger runs read-only;** execution permissions are a separate, minimal path.
- Payout portal: 2FA, no credential reuse with the trading login.

### M6 — Spread **at fill** (P6)

The cost audit records the spread *at the moment of the fill*, not the quote at decision
time — otherwise the `c ≤ 5% of R` gate is measured on a number the market never gave us.

---

## 5. ROI impact — this is not compliance overhead

| Finding | What it protects | Layer |
|---|---|---|
| P1 consistency rule | a whole account's payout EV ($4–6k/mo gross) | **3** |
| P2 timebase drift | **E1 + E2 = 11–15R/mo**, the entire signal edge | **1** |
| P3 proxy fidelity | the DXY SMT gate — a win-rate lever | **1** |
| P4 override log | the **$0** cost of running MFP-001 correctly | **2** |
| P5–P10 | procurement + execution quality | **3** |

All four FAILs are **Layer 2 / Layer 3 — 65% of final ROI** and cost ≈$0. Same shape as
every earlier finding: the expensive-looking work (another engine) is the small prize,
the unglamorous checklist is the large one.

> **The most valuable line in this review is P1.** A strategy can be perfectly sized,
> perfectly drilled and perfectly correlated — and still hand 100% of a payout back over
> a rule nobody read.

---

## 6. Safe next step

Per this skill's contract, *execution-capable work requires a separate implementation
plan and explicit user approval.* So:

1. **This week, paperwork only:** build the Firm Capability Matrix (M1) for the two
   candidate firms — a spreadsheet, no code, and it already blocks a bad purchase.
2. **Stage 0 code, two items added:** timebase connector + proxy fidelity check (M2, M3)
   alongside the already-planned Risk Governor.
3. **Then** Gate 0 runs — now three deterministic conditions:
   `c ≤ 5% of R` **AND** kill-switch drill PASS **AND** capability matrix complete.
4. **M2–M6 should be issued as a separate implementation plan for explicit approval**,
   not folded silently into Stage 0.

### Evidence boundaries

- **Sourced facts:** every *"0 hits"* claim was produced by regex search across all 27
  corpus documents — P1–P4 were verified **absent**, not assumed absent.
- **User-supplied context:** none.
- **Inference:** that a consistency rule would void our payouts — plausible and common,
  but it depends on the chosen firm's actual terms, which is exactly what M1 blocks on.
- **Recommendation:** adopt M1–M6; hold all blocked actions until they exist.


