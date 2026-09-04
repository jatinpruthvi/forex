# TRIAD-R High Stakes EA (revision 2.1)

This directory contains the **research implementation** of the canonical strategy in [`THE5ERS-CHALLENGE-STRATEGY-V2.md`](../../../THE5ERS-CHALLENGE-STRATEGY-V2.md). The reviewed source identifies itself as build `TRIAD_R_HS_2.1.4_20260903`.

> **Status: not compile-verified, not backtested, and not approved for challenge or funded trading.**
>
> `InpEnableOrderSubmission` defaults to `false`. Every release-gate attestation also defaults to `false` and the release ID defaults to `LOCKED`.

## Files

- `TRIAD_R_HS.mq5` — fail-closed Expert Advisor source.
- `../../Files/triad_red_news.csv.example` — format example only. Its dates are deliberately finite and will become stale; it is never an operational calendar.
- `../../../tests/` — Python reference and static contract tests. These do not replace an MQL5 compile or MT5 Strategy Tester run.

## Safe installation for research

1. In MT5, use **File → Open Data Folder**.
2. Copy `TRIAD_R_HS.mq5` to `MQL5/Experts/TRIAD_R_HS/`.
3. Create `MQL5/Files/triad_red_news.csv` from an independently verified high-impact calendar export. Do **not** merely rename the example.
4. Compile in MetaEditor with the broker's current MT5 build. Save the complete compiler output and the resulting source/build checksum in the validation record.
5. Restart or refresh MT5's Navigator, attach the EA to one chart, and leave `InpEnableOrderSubmission=false`.
6. Confirm that all three configured symbols are present in Market Watch and that their base/profit currencies map to EUR/USD, GBP/USD, and USD/JPY as expected.
7. Review the Experts log and `MQL5/Files/TRIAD_R_HS_<login>_DRY_<config-hash>.csv`. Any `ERROR`, `HALT`, stale calendar, insufficient history, property mismatch, or offset mismatch is a failed run—not a warning to bypass.

The EA is timer-driven and scans its configured symbols from one chart. Do not attach multiple live-order instances to the same account. Execution mode also acquires a terminal-global owner/heartbeat lock and fails closed on a concurrent instance. A stale instance that resumes after a newer claimant has acquired the lease is locally fenced: it cannot send cleanup or entry requests and cannot overwrite the new owner's journal on deinitialization. Terminal globals coordinate only processes in the same MT5 data environment; never run or trade the credential from a second terminal, VPS, copier, API, phone, or manual session. Intentionally removing/reconfiguring/recompiling an initialized live EA while it has exposure latches and attempts to flatten; a terminal shutdown instead relies on the broker-visible exits and persisted plan so the exact release can reconcile on restart.

## News CSV contract

The runtime filename is `triad_red_news.csv` unless `InpNewsCsvFile` is changed. It uses comma-separated fields:

```text
utc_time,currency,impact,title
2026.09.07 12:30,USD,RED,Example title without an unquoted comma
2026.09.08 23:59,ALL,COVERAGE,Operator verified through this UTC time
```

Rules:

- `utc_time` is UTC in `YYYY.MM.DD HH:MM` form—not broker time, London time, New York time, or the computer's local time.
- Event `currency` must be a three-letter uppercase currency code. The loader normalizes case.
- Event `impact` must be `RED` or `HIGH`; other non-metadata rows are ignored.
- Every operational file must contain an explicit `ALL,COVERAGE` row whose timestamp is the UTC instant through which the operator has verified the calendar is complete. A far-future event is not treated as proof that intervening events are present.
- Keep titles free of unquoted commas.
- Include **all** relevant red/high events for EUR, GBP, USD, and JPY, including CPI, NFP, FOMC/central-bank rate decisions, and other configured high-impact events.
- Declared coverage must extend at least `InpRequiredNewsCoverageHours` beyond current UTC. The default is 24 hours. Missing, malformed, or stale required coverage disables new entries; a calendar that becomes stale while the EA remains attached also fails closed at runtime and forces managed exposure flat. Zero event rows are allowed only when the explicit coverage declaration truthfully confirms there are no relevant events in that interval.
- Refresh the file before declared coverage expires. The EA reloads it at each confirmed server rollover; reattaching also reloads it. Runtime coverage is checked on every relevant entry/order/position decision rather than trusted indefinitely from initialization.
- Independently reconcile event times, omissions, and daylight-saving changes before advancing the coverage declaration. The CSV is an operational input and requires human review.

`#property tester_file` packages the default filename for Strategy Tester agents. Ensure the current calendar file exists in the terminal's `MQL5/Files` directory before a test.

## Runtime configuration

### Locked by default

These controls prevent an accidental transition from research to execution:

- `InpEnableOrderSubmission=false`
- `InpValidationReleaseId="LOCKED"`
- `InpStatisticalGatePassed=false`
- `InpStressGatePassed=false`
- `InpOperationalGatePassed=false`
- `InpExternalRulesGatePassed=false`
- `InpAccountSpecificGatePassed=false`
- `InpForwardDemoGatePassed=false`
- `InpCompilationGatePassed=false`
- `InpExplicitUserApproval=false`
- `InpEURUSDLondonGatePassed=false`
- `InpGBPUSDLondonGatePassed=false`
- `InpUSDJPYNewYorkGatePassed=false`

The three combination gates enforce Section 13 independently: every enabled symbol/session must pass its own out-of-sample fill-count, expectancy, profit-factor, and regime checks. The booleans are operator attestations, not evidence. They may be changed only after the corresponding Section 13 evidence exists, current purchased-account rules have been checked, MetaEditor compiles with zero errors, forward demo gates pass, and the user explicitly approves that exact release. Use a traceable release ID tied to the archived configuration, source checksum, compiler output, datasets, and reports. The EA cannot independently prove those external facts.

`InpEURUSDLondonPriority`, `InpGBPUSDLondonPriority`, and `InpUSDJPYNewYorkPriority` are validation-frozen collision priorities from 1 (highest) through 3 (lowest). Ties are allowed and then resolve by lower cost/R, earlier completed signal, and stable session index. These values are included in the configuration hash and must come from the approved walk-forward/OOS selection; they are not runtime discretion.

### Account handshake for any eventual approved release

Before execution mode can initialize:

- `InpAuthorizedLogin` must exactly equal the MT5 account login.
- `InpExpectedAccountServer` must exactly equal `AccountInfoString(ACCOUNT_SERVER)`.
- Account currency must remain USD and account leverage must exactly match the verified 1:100 profile.
- The account must be MT5 hedging mode and permit EA trading.
- The observed trade-server offset must match UTC+3 within the fixed five-second runtime tolerance.
- `InpRequiredProductCode` must remain `HS_NEW_2500`.
- Phase 1 and Phase 2 require a $2,500 phase initial balance. Funded/scaled credentials require an explicitly reconciled funded initial balance and fresh phase journal.

The product code and gate inputs are declarations; the EA cannot query The5ers' dashboard or contract. Exact product identity, phase, targets, profitable-day count, payout state, scale state, and current agreement remain human/account-specific checks. If MT5 switches away from the authorized login/server, the EA latches its old journal but deliberately sends no cleanup request to the newly selected account. The old account must be restored, manually flattened if exposure remains, and reconciled before the ordinary flat-only halt-reset handshake; its broker-visible SL/TP remains the only protection while it is not the active terminal context.

### One-time state authorization

Live state is separated from dry-run state.

1. On a brand-new, verified credential with no trading history, no exposure, and balance/equity exactly equal to the configured phase initial balance, set `InpAuthorizeFreshPhaseState=true` for one initialization.
2. The EA creates the persisted journal and intentionally returns initialization failure.
3. Return the input to `false` and reattach. Do not delete terminal global variables to bypass a mismatch.

Internal daily and weekly governors are calendar locks: they force managed exposure flat and prevent entries, then reset only through the confirmed day/week rollover logic. They do not consume the ordinary emergency-halt reset.

A resettable persisted emergency halt is also deliberate:

1. Confirm the log does **not** report `PERSISTED_STATE_MIGRATION_LOCK`, then resolve the incident and complete formal reconciliation/revalidation.
2. With the account flat, set `InpAuthorizeHaltReset=true` for one initialization.
3. The EA clears the latch and intentionally returns initialization failure.
4. Return the input to `false` and reattach.

External cashflow, unauthorized trading history, and any exposure found or reconstructed across rollover set a separate persistent migration latch. The ordinary halt-reset input cannot clear it because the old accounting basis or exact rollover equity is no longer trustworthy. Those incidents require a separately reviewed state-migration/rebaseline release; deleting terminal globals is not a migration procedure.

Never leave either one-time authorization set to `true`.

### Payout, phase, and scale locks

`InpLifecycleLock` defaults to `LIFECYCLE_ACTIVE`. Before a payout request, phase handoff, or scale handoff, select the corresponding lock and reattach the EA. Execution mode cancels its pending order, closes its own position, latches the journal, and refuses new trades. The EA never submits a payout, infers a new phase, or reinitializes scaled credentials by itself.

After the dashboard operation is complete, archive logs/state and reconcile the balance, account login/server, phase, phase initial balance, target, day count, payout/scale timer, and current agreement. A new credential requires a new fresh-phase handshake. If a requested payout is cancelled and no account balance operation occurred, resuming the same credential still requires formal review plus the one-time persisted-halt reset.

A deposit, withdrawal, credit, charge, bonus, or correction after the state baseline is treated as an external cashflow and latches the EA. **Do not use the ordinary halt reset after a payout changed account balance.** This release intentionally has no automatic post-payout high-water/floor migration. Post-payout continuation requires the Section 14 review and a separately approved rebaseline/migration release. Return `InpLifecycleLock` to `LIFECYCLE_ACTIVE` only when that process authorizes it.

### Candidate versus fixed inputs

The only intended offline comparisons are:

- one of four paired risk/target profiles A–D;
- range band 30–80 or 35–75 percentile;
- ATR band 20–80 or 25–75 percentile;
- time stop 30, 45, 60, 90 minutes, or session-only (`0`);
- confirmed-1R stop-to-entry on or off;
- enabled-combination collision priorities from 1–3, derived by the predeclared training/walk-forward ranking rule and frozen before OOS evaluation (not tuned as another free dimension).

To obtain simulated trades in MT5 Strategy Tester, use a USD $2,500 initial deposit and set `InpEnableOrderSubmission=true` inside the tester. The external live-release attestations are bypassed only when `MQL_TESTER` is true; account orders remain locked outside the tester. With the input left `false`, the EA only logs dry-run candidates and will not send, modify, delete, or close any order—including orders already on the account.

`InpResetTesterStateOnInit=true` gives each Strategy Tester run a clean journal for deterministic batch/optimization passes. Set it to `false` only for explicit tester restart/persistence drills. It never resets live state.

Entry geometry, 60-session lookbacks, spread/cost gates, the one-second maximum synchronous order-request latency, news/rollover buffers, drawdown tiers, and internal risk limits are revision 2.1 contract controls. Initialization rejects values outside the supported contract or values that weaken a safety default. Time-based entry/cleanup checks apply a fixed ten-second early safety lead so timer cadence and an accepted request within the one-second ceiling do not intentionally cross an exact cutoff. The final latency threshold must also be inside the empirically tested execution envelope; the runtime check does not replace forward execution validation.

Build 2.1.4 retains the prior canonical `iATR(M15,14)`, first-event reconstruction, DST-overlap exclusion, visible-exit, bounded-breakeven, and same-tick request protections. This pass also fails initialization after any initial session-state halt; acquires and verifies the live lease before state reconciliation; fences stale instances from requests and journal writes; detects runtime journal changes; reconstructs pending/position exposure across an offline rollover; and makes cashflow, unauthorized-history, or rollover-exposure incidents non-resettable without a separately reviewed migration. News coverage now requires an explicit operator-verified `ALL,COVERAGE` declaration instead of inferring completeness from a far-future event. Collision ranking uses frozen per-combination priorities and freshly revalidated quote costs. Volume rounding uses the symbol minimum-anchored step grid and directional volume limit. A ten-second early control lead and five-second server-offset tolerance protect exact cutoffs, while emergency delete/close failures and incomplete outcomes latch for review. Accepted submissions are reconciled immediately rather than waiting one timer interval.

Symbol names may be changed for broker suffixes (for example, `EURUSD.a`), but the EA validates each symbol's actual base and profit currencies.

## Persistence and logs

Live and dry modes use separate terminal-global prefixes and separate CSV logs. Persisted state includes configuration/build hash, the initialization-time account identity hash, phase initial balance, rollover state, daily floor, weekly reference, high-water balance, estimated qualifying days, request count, external-cashflow history baseline, state creation time, halt/migration latches, and the active order/position plan. The frozen identity prevents an MT5 account switch during deinitialization from rewriting the prior account's journal. A last-written state signature rejects partial or internally mixed terminal-global updates after interruption. Missing, invalid, inconsistent, or unwritable safety state fails closed. Detected deposits, withdrawals, unauthorized trading, and related account operations are not allowed to migrate into daily, weekly, or high-water baselines; they require the separately approved rebaseline process.

The dashboard remains authoritative for profitable days. Set `InpDashboardConfirmedDays` from a verified dashboard only; never use that input to manufacture a trade. Phase target arrival with fewer than three confirmed days enters a flat, latched `TARGET_PENDING_DAYS` state.

Execution logs include each completed M5 no-event decision, valid/rejected candidates, planned cash risk, predicted net target, order retcodes, entry slippage observations, exit-deal and reconstructed position-net cash values, rollover estimates, calendar status, direction-concentration review alerts, and inactivity alerts. Preserve logs with tester and forward evidence. Tick-derived MFE/MAE remains a tester/post-processing requirement; the one-second multi-symbol timer is not represented as tick-exact excursion data.

## Required validation sequence

A local Python pass is only the first check:

```bash
python3 -m unittest discover -s tests -v
```

Then complete, in order:

1. MetaEditor compile on the target MT5 build with zero errors; investigate every warning.
2. Deterministic unit/harness checks for civil-time conversion, DST mismatch weeks, entry/exit state, floor math, volume rounding, restart state, and news boundaries.
3. Real-tick Strategy Tester runs per symbol/session and paired profile using frozen assumptions.
4. Out-of-sample, walk-forward, multiple-testing, spread/slippage stress, bootstrap/Monte Carlo, data-quality, and qualifying-day gates from canonical Section 13.
5. Operational drills: disconnect, stale quote, rejected/uncertain order, partial fill, duplicate exposure, missing stop, calendar failure, rollover, external cashflow at rollover, MT5 account/server switch, Friday closure, restart, deinitialization, and persisted halt.
6. Current external-rule and purchased-account verification, including written clarification for any material ambiguity.
7. Forward-demo validation on the exact broker symbols/server and reconciliation of fills, commissions, swaps, stops, targets, request counts, and dashboard days.
8. Explicit approval of the frozen source/configuration release.

Until all steps pass, keep order submission disabled. A successful Python test, compile, backtest, or Monte Carlo run alone does not establish an edge and does not authorize challenge use.
