# The5ers $2,500 New High Stakes — End-to-End Pre-Code Checklist

Completeness review date: 2026-09-03
Canonical strategy: `THE5ERS-CHALLENGE-STRATEGY-V2.md`
Detailed rule audit: `THE5ERS-CHALLENGE-V2-REVALIDATION.md`

## Status legend

- **LOCKED** — rule/design is clear and must be implemented exactly.
- **TEST** — candidate is defined, but data must select or reject it.
- **RUNTIME** — must be read/verified from the actual MT5 account or dashboard.
- **EXTERNAL** — requires the purchased agreement or written The5ers confirmation.
- **NO-GO** — live trading cannot proceed while unresolved.

This checklist covers the complete lifecycle from checkout through both evaluation phases, initial funding, first payout, and scale transition. No trading code has been started.

## Strategy revalidation outcome — Revision 2.1

The core M5 sweep/reclaim strategy remains the best first-challenge candidate, but the latest rule/lifecycle findings justified five simplifications:

1. Risk and reward are now tested as four paired profiles: 0.40%/+1.5R, 0.35%/+1.75R, 0.30%/+2R, and 0.25%/+2.5R.
2. Partial closing is removed entirely from the initial implementation.
3. Profit-level-based risk changes near phase targets are removed.
4. The former 25% risk tier is removed; only one documented half-risk drawdown tier remains.
5. Any first net-positive exit locks the day; a second trade is possible only after a zero/net-loss result and only when its full stressed loss fits every limit.

These changes preserve the entry edge while reducing bulk-trading ambiguity, lot-size inconsistency, server actions, profitable-day manipulation risk, and near-target complexity. They do not assert that any candidate profile is profitable; the offline holdout selects or rejects it.

---

## Stage 0 — Identify the exact product

| Item | Required action | Status |
|---|---|---|
| Product name | Agreement must say `$2,500 New High Stakes` | **RUNTIME / NO-GO if different** |
| Price | Current live High Stakes page shows $19; verify checkout | **RUNTIME** |
| Phase targets | 10% Phase 1 and 5% Phase 2 | **LOCKED** |
| Evaluation daily loss | 5% of higher prior rollover balance/equity | **LOCKED for High Stakes** |
| Overall loss | Static 10% below phase initial balance | **LOCKED** |
| Profitable days | Three per evaluation phase, each 0.5% of initial balance | **LOCKED** |
| Time | Unlimited, subject to inactivity | **LOCKED** |
| Inactivity | 30 consecutive evaluation days from registration | **LOCKED** |
| Product collision | Do not apply the separate Summer 2-Step $100K rules (3% daily, funded 50% consistency, different payout terms) | **LOCKED / NO-GO on ambiguity** |
| Agreement snapshot | Save PDF/screenshots/version and purchase timestamp | **RUNTIME** |
| Account ownership | User's own identity, KYC, payment, email, and access only | **EXTERNAL / RUNTIME** |
| Jurisdiction | Confirm eligibility at checkout/KYC; do not infer solely from a generic public list | **EXTERNAL** |

**Missing item found in this review:** The site currently has a distinct Summer “2-Step” product whose rules conflict with High Stakes. Product selection can no longer be inferred from “2-Step”; the exact High Stakes agreement is a mandatory profile key.

---

## Stage 1 — Pre-code strategy freeze

| Item | Required action | Status |
|---|---|---|
| Trading module | Sleeve A M5 sweep/reclaim only | **LOCKED** |
| Candidate combinations | EURUSD London, GBPUSD London, USDJPY New York | **TEST** |
| Disabled modules | Gold, indices, continuation, Asian fade, grid, martingale, averaging | **LOCKED** |
| Order concurrency | One working entry or one open position account-wide | **LOCKED** |
| Exit concurrency | No separate target tickets | **LOCKED** |
| Copier | None | **LOCKED** |
| Direction | Exact mirrored long/short logic; no forced alternation | **LOCKED** |
| Runtime optimization | Disabled | **LOCKED** |
| Source ownership | User retains complete source and build record | **LOCKED** |
| Parameter dimensions | Range band, ATR band, time stop, categorical exit policy only | **LOCKED for research design** |
| Paired profile A | 0.40% risk with +1.50R target | **TEST baseline** |
| Paired profile B | 0.35% risk with +1.75R target | **TEST** |
| Paired profile C | 0.30% risk with +2.00R target | **TEST** |
| Paired profile D | 0.25% risk with +2.50R target | **TEST** |
| Partial closes | Removed from initial implementation | **LOCKED** |
| Breakeven policy | Move visible stop to entry after M5 +1R close versus no move | **TEST** |
| Candidate time exit | 30/45/60/90 minutes or session-only | **TEST** |

No parameter in the TEST category may be represented as optimized before the replay/holdout results exist.

---

## Stage 2 — Account initialization

Before enabling even research/demo order execution:

| Item | Required action | Status |
|---|---|---|
| Account number/server | Match authorized record | **RUNTIME / fail closed** |
| Product/phase | Match High Stakes profile and current phase | **RUNTIME / fail closed** |
| Initial balance | Verify and persist $2,500 for each evaluation phase | **RUNTIME / fail closed** |
| Build/config hash | Match the locked champion | **RUNTIME / fail closed** |
| Symbol names/suffixes | Discover from MT5; do not assume | **RUNTIME** |
| Tick/contract values | Read and unit-test with `OrderCalcProfit` | **RUNTIME** |
| Volume min/step | Verify 0.01/0.01 or use live value | **RUNTIME** |
| Stop/freeze levels | Read live | **RUNTIME** |
| Commission/swap | Read/confirm live | **RUNTIME** |
| Trading sessions | Read live and compare with strategy windows | **RUNTIME** |
| Server rollover | Observe/verify against account terms; current public High Stakes wording uses 00:00 UTC+3/server time | **RUNTIME / fail closed** |
| Local/session time zones | `Europe/London` and `America/New_York` converted independently | **LOCKED** |
| Calendar | Forex Factory-compatible relevant red events loaded and mapped | **RUNTIME / fail closed** |
| Existing state | Reconcile positions, orders, balance, equity, history, and day/week counters | **RUNTIME / fail closed** |

---

## Stage 3 — Start-of-day and rollover

| Item | Required action | Status |
|---|---|---|
| Rollover snapshot | Persist balance and equity at confirmed server boundary | **LOCKED** |
| Firm daily floor | `max(rollover balance, rollover equity) × 0.95` | **LOCKED** |
| Firm static floor | `phase initial balance × 0.90 = $2,250` | **LOCKED** |
| Active floor | More restrictive/higher floor | **LOCKED** |
| Internal reserve | Greater of 0.5% initial or 2× configured gap/slippage reserve | **TEST stress component** |
| Previous-day balance | Persist for profitable-day formula | **LOCKED** |
| Daily internal start | Flat server-day starting balance | **LOCKED** |
| Weekly start | Flat balance at first server rollover of trading week | **LOCKED** |
| Daily state reset | Only after rollover plus successful reconciliation | **LOCKED** |
| News/calendar refresh | Must succeed before entries | **LOCKED / fail closed** |
| Floating position at rollover | Profile requires none; unexpected exposure triggers halt | **LOCKED** |

The EA must not use the PC clock, Ahmedabad time, a fixed EET assumption, or London time for firm rollover.

---

## Stage 4 — Before every signal/order

All conditions are mandatory:

| Item | Pass condition | Status |
|---|---|---|
| Session | Correct civil-time session after DST conversion | **LOCKED; historical performance TEST** |
| Range sample | Uses prior 60 completed comparable sessions only | **LOCKED** |
| Range band | Selected champion band | **TEST** |
| ATR sample | Uses prior 60 completed comparable session opens only | **LOCKED** |
| ATR band | Selected champion band | **TEST** |
| Spread | ≤1.5× same-symbol/session-minute historical median | **LOCKED threshold candidate** |
| Cost | Estimated all-in round trip ≤0.10R | **LOCKED** |
| News | No red event for either currency within 30 minutes | **LOCKED** |
| Calendar failure | No trade | **LOCKED** |
| Data/latency | Fresh and inside measured bounds | **TEST bounds / fail closed** |
| Account mutex | No working entry and no open position | **LOCKED** |
| Target room | Target fits before opposite reference-range extreme | **LOCKED definition; value TEST** |
| Stop geometry | 0.60-1.50 M15 ATR | **TEST** |
| Volume | Rounded down and inside current risk tier | **LOCKED** |
| Safety projection | Full stressed loss fits daily, weekly, strategy, firm, and reserve floors | **LOCKED** |
| Direction evidence | Signal arises from mirrored rule, not account-history balancing | **LOCKED** |

A failed gate means `NO_TRADE`; there is no score override.

---

## Stage 5 — Entry event

For long; short is the exact inverse:

1. Sweep below range by 0.05-0.50 M15 ATR — **LOCKED definition / TEST edge**.
2. M5 close back inside within three bars — **LOCKED definition / TEST edge**.
3. Reclaim lower wick at least 60% — **LOCKED definition / TEST edge**.
4. Next M5 displacement body at least 60% and close above prior midpoint — **LOCKED definition / TEST edge**.
5. One limit at 50% displacement-body retracement — **LOCKED definition / TEST edge**.
6. Visible stop and target included with initial request — **LOCKED**.
7. Expire after three M5 bars/session/news or theoretical +1R without fill — **LOCKED**.
8. Never chase at market — **LOCKED**.
9. Accepted/deep breakout is no-trade — **LOCKED**.
10. One order attempt per event; one revalidated retry only after a transient technical rejection — **LOCKED**.

---

## Stage 6 — Position sizing and order safety

| Item | Required behavior | Status |
|---|---|---|
| Risk base | Phase initial balance, not current equity | **LOCKED** |
| Stop cash loss | `abs(OrderCalcProfit(entry, stop, lots))` | **LOCKED** |
| Cost reserve | Commission plus calibrated stop slippage | **TEST calibration** |
| Lot choice | Largest valid step whose all-in loss does not exceed budget | **LOCKED** |
| Minimum lot unsafe | Skip | **LOCKED** |
| Target cash | Solve price for selected net R after expected commission/TP slippage | **LOCKED method / TEST policy** |
| Nominal day assumption | Never assume 0.40% × 1.5R automatically equals a qualifying day | **LOCKED** |
| Missing visible stop | One immediate correction attempt; if unsuccessful, close and halt | **LOCKED** |
| Partial/unexpected fills | Reconcile; any multiple-position state triggers flatten/halt | **LOCKED** |
| Request count | Cap 20 non-emergency requests/day; safety closes/cancels remain permitted | **LOCKED internal limit** |

---

## Stage 7 — Open-position management

| Item | Required behavior | Status |
|---|---|---|
| One position | Account-wide invariant | **LOCKED** |
| +1R event | Completed M5 close, not tick/wick | **LOCKED** |
| Breakeven | Use only if selected in frozen exit policy | **TEST** |
| Partial close | Not implemented in the initial challenge EA | **LOCKED** |
| Time stop | Selected frozen policy | **TEST** |
| Session stop | Flat | **LOCKED** |
| Rollover | Flat at least 15 minutes before | **LOCKED conservative** |
| Relevant red news | Flat at least 15 minutes before configured event | **LOCKED conservative** |
| Re-entry after news | Not until 30 minutes after | **LOCKED** |
| Weekend | Flat by Friday 20:00 Europe/London or earlier symbol close | **LOCKED** |
| Equity monitoring | Floating losses count toward every internal/firm guard | **LOCKED** |
| 5% strategy DD | Attempt immediate close, cancel entries, halt/reconcile | **LOCKED; overshoot cannot be guaranteed** |

---

## Stage 8 — Daily and weekly process

| Item | Required behavior | Status |
|---|---|---|
| First net-positive exit | Locks day even if profit is below $12.50; day counter is not consulted | **LOCKED** |
| First zero/net-loss exit | One second independent setup only if projected stop remains safe | **LOCKED** |
| Second completed trade | Always locks day | **LOCKED** |
| Third trade | Never | **LOCKED** |
| Recovery trade/size | Never | **LOCKED** |
| Direction alternation | Never forced | **LOCKED** |
| Qualifying-day chase | Never | **LOCKED** |
| Daily internal stop | -1% = $25 at inception | **LOCKED** |
| Weekly internal stop | -2% = $50 at inception | **LOCKED** |
| Day end | Flat, reconcile, calculate formula, compare dashboard | **LOCKED** |

---

## Stage 9 — Profitable-day accounting

| Item | Required behavior | Status |
|---|---|---|
| Threshold | $12.50 | **LOCKED** |
| Formula | `min(midnight balance, midnight equity) - previous-day balance` | **LOCKED** |
| Required count | Any three in Phase 1; new count of any three in Phase 2 | **LOCKED** |
| Consecutive/first | Not required by current High Stakes wording | **LOCKED interpretation** |
| Positive <$12.50 | Allowed, not counted | **LOCKED** |
| Loss/flat day | Does not reset count | **LOCKED** |
| EA versus dashboard | Dashboard authoritative | **LOCKED** |
| Cross-date partial/hedge | Prohibited | **LOCKED** |
| Strategy changes for count | Prohibited by profile | **LOCKED** |
| Simulation requirement | ≥99% day-completion probability by target | **TEST** |

---

## Stage 10 — Drawdown and completion guards

| State | Action | Status |
|---|---|---|
| Strategy DD 0-2% | Selected paired profile risk | **TEST selected profile** |
| Strategy DD 2-5% | 50% of selected risk; same entry and target-R policy | **TEST + document consistency** |
| Strategy DD reaches 5% | Emergency exposure close/cancel and shutdown | **LOCKED** |
| Near Phase 1 target | No profit-based size change; only fully valid setups | **LOCKED** |
| Near Phase 2 target | Same policy; smaller target never permits larger risk | **LOCKED** |
| Target plus days complete | Lock phase | **LOCKED** |
| Target reached without days | `TARGET_PENDING_DAYS`; flat and review | **LOCKED** |
| Calendar month | Does not reset strategy drawdown | **LOCKED** |

The former 25% tier and all profit-based risk reductions are removed. This reduces minimum-lot distortion and stage/near-target size inconsistency. The one remaining 50% drawdown reduction is predeclared and used identically in every stage; if account terms reject it, the fallback is no new trade at 2% drawdown.

---

## Stage 11 — Phase target and transition

### Phase 1

- Require balance at or above $2,750 **and** three dashboard-confirmed qualifying days — **LOCKED**.
- Cancel/close and lock; do not continue after completion — **LOCKED**.
- If balance reaches target before day count, enter `TARGET_PENDING_DAYS`, stay flat, reconcile, and require review — **LOCKED**.

### Phase 1 → Phase 2

- Wait for actual new credentials/account — **RUNTIME**.
- Verify product, phase, account number, server, $2,500 initial balance, symbols, and rules — **RUNTIME / fail closed**.
- New daily/static floors and new three-day counter — **LOCKED**.
- Same champion parameters and source version — **LOCKED**.
- No order before clean initialization — **LOCKED**.

### Phase 2

- Require balance at or above $2,625 and three dashboard-confirmed days — **LOCKED**.
- Use the same strategy/daily/risk process — **LOCKED**.
- No assumption that the smaller target permits higher risk — **LOCKED**.

**Missing items found in this review:** explicit new-account handshakes, independent Phase 2 floors/counters, and a no-order transition lock are now in V2.

---

## Stage 12 — Funded transition

| Item | Required behavior | Status |
|---|---|---|
| New credentials/state | Treat funded as a new account/configuration event | **LOCKED** |
| Initial balance/floors | Read and persist; never reuse Phase 2 state | **RUNTIME** |
| Rules/specifications | Re-read funded agreement, symbols, leverage, and payout terms | **RUNTIME / fail closed** |
| Strategy | Same champion through first payout | **LOCKED** |
| Risk process | Same paired profile and one documented 50% drawdown tier | **LOCKED / confirm half-risk tier or halt at 2%** |
| One-position rule | Continues | **LOCKED** |
| Inactivity | Current general rule says 60 funded days | **LOCKED; dashboard verify** |
| Scaling days | Current High Stakes page shows three qualifying days for scaling | **RUNTIME tracker; no manufacturing** |
| Scaling target | 10% at each funded level | **LOCKED current public rule** |
| Expansion | No new sleeve/account/copier before 100 funded trades and first payout review | **LOCKED internal policy** |

No separate public 50% funded consistency rule was found for the $2,500 High Stakes product. The current 50% page belongs to the separate Summer $100,000 2-Step offer. The purchased High Stakes agreement remains controlling.

---

## Stage 13 — Payout and scale lifecycle

| Item | Required behavior | Status |
|---|---|---|
| Evaluation payout | None | **LOCKED** |
| First funded request | At least 14 funded days | **LOCKED current FAQ / dashboard verify** |
| Later requests | Every two weeks from last approved withdrawal | **LOCKED current FAQ** |
| Minimum | $150 after profit split under current High Stakes FAQ | **LOCKED current FAQ / dashboard verify** |
| $2,500 at 80% split | $187.50 gross distributable profit = 7.5% to reach $150 before processing fees | **Arithmetic confirmed** |
| Open trades | Must all be closed before request | **LOCKED** |
| Payout action | Human only; EA enters `PAYOUT_REQUEST_LOCK` and reconciles | **LOCKED** |
| Processing | Current methods generally charge 3.5%; bank may add fees | **RUNTIME** |
| Refund | Current High Stakes-specific FAQ says 70% external-fee portion with first eligible payout; promotion-specific pages can differ | **EXTERNAL/account terms control** |
| Scale target | 10%, trades closed | **LOCKED** |
| Scale transition | New initial balance/floors/specs; clean reinitialization | **LOCKED** |
| Payout timer after scale | Current withdrawal FAQ says 14-day timer resets | **LOCKED current FAQ** |
| In-flight state | No payout/scale change while order/position exists | **LOCKED** |

**Missing items found in this review:** payout flat/reconciliation lock, first-14-day timing, after-split interpretation, phase-to-funded reset, scaling day tracker, and scale reinitialization are now covered.

---

## Stage 14 — Failure and recovery paths

| Failure | Required response | Status |
|---|---|---|
| Unknown account/profile/phase | No new orders | **LOCKED** |
| Configuration hash mismatch | No new orders | **LOCKED** |
| Stale quote/bar | No new orders; existing broker stop remains | **LOCKED** |
| Calendar missing/stale | No new orders | **LOCKED** |
| Server rollover mismatch | No new orders; reconcile | **LOCKED** |
| Order rejected | One delayed, fully revalidated retry maximum | **LOCKED** |
| Visible stop missing | One correction; otherwise close/halt | **LOCKED** |
| Duplicate/multiple positions | Cancel entries, flatten as safely executable, halt | **LOCKED** |
| Partial fill | Reconcile actual risk/position count immediately | **LOCKED** |
| Request cap reached | Block entries; never block safety cancel/close | **LOCKED** |
| Daily/weekly/strategy floor | Cancel entries and lock relevant period | **LOCKED** |
| Firm-floor danger | No new order; emergency exposure reduction | **LOCKED** |
| EA/VPS restart | Reconstruct from broker state before action | **LOCKED** |
| Manual trade detected | Halt and require reconciliation | **LOCKED** |
| Gap/slippage overrun | Log actual, halt, do not claim guaranteed cap | **LOCKED** |

---

## Stage 15 — Statistical and operational acceptance

Live challenge remains **NO-GO** until all pass:

- At least 100 OOS fills per enabled combination and 300 total.
- Every enabled combination positive with PF ≥1.15.
- Aggregate net EV ≥0.20R and PF ≥1.30.
- Positive at 1.5× spread and 2× slippage.
- Rolling walk-forward plus untouched holdout.
- Four parameter dimensions maximum; coarse declared candidates only.
- At least 10,000 calendar-aware day/week block-bootstrap paths.
- Phase 1 pass ≥70% before personal 5% stop.
- Phase 2 pass ≥85%.
- Joint pass ≥60% with confidence bounds.
- Three qualifying days by each target ≥99%.
- Shutdown overshoot stress within V2 gate and no simulated firm-floor breach.
- No historical 30-day inactivity failure.
- 30-50 forward-demo fills.
- Zero state, calendar, duplicate-order, missing-stop, sizing, restart, or compliance errors.

These cannot be prevalidated without the research implementation. Coding the harness creates the evidence; it does not presume the answer.

---

## Stage 16 — External questions that remain

The public High Stakes rules are sufficiently clear for a conservative research implementation, but retain written answers before live activation where possible:

1. Does the profile—one working entry while flat, followed by at most one open market position account-wide—satisfy the July 2026 bulk-trading interpretation?
2. Is one predeclared 50% risk reduction after 2% strategy drawdown acceptable under the size-consistency wording? If not, the profile will halt instead of reducing size.
3. Does the purchased $2,500 New High Stakes agreement use 00:00 UTC+3 continuously, or should only the observed MT5 server midnight control?
4. Confirm funded payout minimum, fee refund timing, and scaling-day treatment shown in the dashboard for this exact purchase.

Partial closing is no longer an open question because it has been removed from the initial implementation. Suggested support wording should identify the product, account size, one-order/one-position topology, and exact fixed risk policy; avoid asking a vague “Are EAs allowed?” question.

---

## Final completeness verdict

After this lifecycle review, no additional public-rule category was found missing from the strategy profile. Newly discovered product-collision, phase-transition, payout, scale, duplicate-position, missing-stop, and account-identity paths have been added.

The remaining unknowns are correctly isolated as:

- Purchased agreement/dashboard values.
- Written interpretations of broad public wording.
- Live MT5 symbol/server properties.
- Statistical edge and parameter selection.

The next permissible engineering step is an offline research/backtest and compliance harness. Live order activation remains disabled until every RUNTIME, EXTERNAL, and TEST gate required for production is resolved.
