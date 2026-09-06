# TRIAD-R High Stakes EA — code review

- **Review date:** 2026-09-03
- **Reviewed build:** `TRIAD_R_HS_2.1.4_20260903`
- **Canonical behavior:** `THE5ERS-CHALLENGE-STRATEGY-V2.md`, revision 2.1
- **Source:** `MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5`
- **Reviewed source SHA-256:** `367c38a18eac487255192f9713825fffd944778a058784a9ec937f76374f1f60`
- **Review type:** fifth static/logic pass; no MetaEditor or MT5 runtime was available

> **Historical review notice:** this document covers build 2.1.4 and the SHA-256 shown above. The repository now contains build `TRIAD_R_HS_2.1.5_20260904`, which adds a signed emergency-halt latch. The new build is not covered by the 2.1.4 review and remains subject to fresh static review, MetaEditor compilation, and MT5 runtime validation.

## Verdict

The fifth pass found and corrected additional initialization, lease-fencing, persistence, offline-rollover, calendar-coverage, collision-ranking, volume-grid, timing, cleanup-lifecycle, and governor-state defects. The implementation is materially safer and more faithful to revision 2.1 than build 2.1.3.

This is **not** a bug-free, compile-ready, backtested, challenge-ready, or live-ready claim. The MQL5 source has not been compiled in MetaEditor and has not run in MT5. Local Python and lexical checks cannot validate MQL overloads/enums, broker events, terminal-global crash semantics, indicator buffers, comments/magic propagation, fills, commissions, or timed cleanup under real infrastructure. No challenge, funded, or other live account should execute this build. Status remains **NO-GO**; order submission, the release ID, and every release attestation remain locked by default.

## Fifth-pass material findings and corrections

### 1. Initialization could report success after initial session-state persistence halted

`RefreshSession()` can latch a halt when a required consumed-session write fails. `OnInit()` previously continued to log initialization and could return `INIT_SUCCEEDED`. Initialization now checks the halt immediately after all initial session refreshes, attempts authorized strategy-exposure cleanup while it still owns the live lock, releases the lock, and returns `INIT_FAILED`.

### 2. State-load failure could strand old strategy exposure

A persisted halt, incomplete state, config mismatch, or migration lock could make state loading fail before startup exposure management ran. Live initialization now validates the account, acquires the account-level lock before runtime/state initialization, and attempts cleanup of only same-magic strategy exposure if runtime or state reconciliation fails. A duplicate instance fails before this path and therefore cannot perform competing cleanup.

### 3. The instance lease had claimant/release races and did not fully fence a resumed stale instance

The prior claimant published owner before heartbeat, allowing another starter to observe a fresh owner with an old beat and steal it. Release could also zero the heartbeat after a new owner had already acquired the token. Claimants now publish heartbeat before the owner CAS, and release clears only the conditionally owned token. Ownership is rechecked before activation, every live request path, timer work, ticks, and trade-transaction journaling.

A stale instance that resumes after lease takeover is locally fenced: it cannot submit, delete, close, modify, or rewrite account state during deinitialization. Runtime journal health checks detect a persisted halt/migration latch or state-signature change. The lock remains terminal-local; a second MT5 installation/VPS cannot be detected and is operationally prohibited.

### 4. Offline exposure that crossed rollover could disappear before restart and evade the incident path

If a broker stop/target closed a position while MT5 was offline after rollover, no current exposure remained for the old check to find. The EA now reconstructs same-magic pending-order lifetimes and strategy position entry/exit lifetimes from history. A pending entry or position spanning different server-day keys is treated as rollover exposure.

The exact firm equity snapshot at an unobserved boundary cannot be reconstructed from deals. Any found or reconstructed rollover exposure now sets a separately persisted migration latch, suppresses the profitable-day estimate, cleans current strategy exposure where authorized, and cannot be cleared with the ordinary halt-reset input.

### 5. External cashflow and unauthorized history were repeatedly detectable but not intrinsically non-resettable

A user could attempt the ordinary halt-reset workflow even though an old high-water/daily/weekly basis was no longer trustworthy; the incident would normally be rediscovered only after another attach. A signed `Rebase` migration latch is now persisted immediately for external cashflow, unauthorized order/deal history, and rollover-exposure incidents. Current code refuses to load such state for ordinary reset. Continuation requires a separately reviewed migration/rebaseline release.

The history audit now also scans completed pending-order history. A manual/foreign pending order placed and cancelled while the EA was offline no longer escapes merely because it generated no deal. Fresh-state authorization also rejects any historical order, including a cancelled unfilled order.

### 6. News coverage was incorrectly inferred from the timestamp of the latest event

One far-future event did not prove that intervening red events were complete; conversely, a legitimately event-free interval could look stale. Operational news files must now include an explicit `ALL,COVERAGE` row declaring the UTC instant through which the operator verified completeness. Runtime coverage is based only on that declaration. Missing, malformed, or stale coverage fails closed; the event list may be empty only when the declaration truthfully covers an event-free interval. The example, README, and static checks were updated.

### 7. Collision ranking did not implement the canonical frozen combination priority

Build 2.1.3 assigned all combinations equal priority and ranked only by cost/R and signal time. Build 2.1.4 adds per-combination priorities from 1–3, includes them in the configuration hash, validates their range, and applies priority before cost/R and completion time. Ties remain permitted. The priority values must be derived by the predeclared training/walk-forward rule and frozen before OOS evaluation, not tuned as another free dimension.

Candidate preparation can load enough history for an earlier quote snapshot to age before all symbols are ranked. Every surviving candidate now refreshes its quote-derived spread, cost/R, marketability, and broker-distance gates immediately before cross-symbol ranking. The selected candidate is still fully revalidated before submission.

### 8. Volume rounding assumed the broker's lot lattice was anchored at zero

Rounding `raw/step` can create an invalid value if `SYMBOL_VOLUME_MIN` is not itself a zero-anchored step multiple. Volume is now rounded down on the lattice `minimum + n × step`, normalized using both minimum and step precision, bounded by `SYMBOL_VOLUME_MAX`, and additionally capped by a positive `SYMBOL_VOLUME_LIMIT`. Minimum-lot over-risk remains a no-trade result. Independent Python reference arithmetic now covers a non-zero-offset grid.

### 9. Exact time cutoffs and server-offset tolerance left avoidable timing slack

A one-second timer and accepted synchronous request can execute just after an exact 30/15-minute, session, Friday, or rollover boundary. Entry and forced-cleanup controls now use a fixed ten-second early lead; limit expiry itself remains at three completed M5 bars and is not shortened. The accepted UTC+3 skew was tightened from 60 seconds to five seconds so fixed civil/news conversion cannot begin materially early under a tolerated offset error. Server-day regression now latches instead of migrating state backward.

The lead and tolerance remain assumptions to validate on the actual terminal/VPS; they cannot guarantee timing through stalls, disconnects, or broker outages.

### 10. Emergency request failures and incomplete accepted outcomes were under-escalated

Failed emergency deletes/closes now latch for review. A vanished order/position race is treated as successful cleanup, while an accepted response that leaves the ticket active/open is classified as incomplete and latched. Close filling-mode setup is checked. An accepted submission is synchronously passed through exposure/plan/visible-exit reconciliation rather than waiting a full timer interval.

### 11. Internal daily and weekly governors incorrectly consumed a permanent halt reset

The canonical daily and weekly limits are calendar locks, not permanent incident latches. Build 2.1.3 halted persistently on every global-guard failure. The new policy still cancels pending orders and flattens managed exposure at the internal daily/weekly boundary, but it keeps those two reasons temporary so they reset only through the confirmed day/week rollover state machine. Cleanup failure remains a persistent halt. Firm-floor, 5% strategy-drawdown, identity, audit, lifecycle, target, and migration failures remain persistent.

### 12. Rollover could run before runtime identity/journal revalidation

Timer processing now verifies current lock ownership, frozen account identity/config sentinel, server-offset/account properties, persisted halt/migration values, and the signed runtime journal before external-history checks or rollover migration. This prevents a changed server clock/account state or concurrently modified journal from becoming a new daily/weekly baseline.

## Controls reconfirmed across all passes

- `InpEnableOrderSubmission=false`; release ID is `LOCKED`; global, account, compilation, forward, user, and per-combination attestations default false.
- Live initialization requires exact login/server, USD currency, 1:100 leverage, hedging mode, permissions, product declaration, UTC+3 check, release gates, and a clean one-time phase-state handshake.
- Dry mode cannot send, modify, delete, or close orders. Tester execution requires explicit tester-only enabling.
- There are exactly four paired profiles: 0.40%/+1.50R, 0.35%/+1.75R, 0.30%/+2.00R, and 0.25%/+2.50R.
- The only drawdown reduction is 50% at 2%; the strategy cleans up and persistently halts at 5%.
- Cash sizing uses `OrderCalcProfit`, commission, configured stop slippage, actual symbol volume properties, and downward volume rounding.
- Stops and targets are broker-visible in the initial pending request; target cash is solved net of commission and configured target slippage.
- The first sweep event is reconstructed from the effective signal-window start and cannot reset after a deep, ambiguous, late, weak, stale, or repeated event.
- Civil London/New York DST conversion is independent; NY bars before completion of its London reference range are excluded.
- Pending orders are cancelled on expiry, cutoff, stale quote, news blackout, theoretical +1R without fill, trade-mode downgrade, or plan mismatch. There is no market chase.
- Position management enforces plan identity, non-worse limit fill, exact volume, visible exits, post-fill completed-M5 +1R confirmation, optional bounded breakeven, time/session/news/rollover/Friday stops, and account-wide one-position topology.
- Missing visible stop has one immediate protective repair path; failed repair closes and halts.
- Daily history reconstructs complete position IDs and net cash: first net-positive trade locks the day; a zero/loss permits at most one independently safe second trade.
- Firm daily/overall floors, reserve, internal day/week limits, high-water drawdown, target/day-count, payout, phase-transition, and scale-transition controls remain present.
- External cashflow and unauthorized post-baseline order/deal history cannot migrate into new risk baselines.
- Audit-log open/seek/write failures fail closed while emergency safety requests remain permitted where the account and lease are authorized.
- No grid, martingale, averaging, hedge, copier, partial close, raw `OrderSend`, market-entry `Buy`/`Sell`, runtime optimizer, or automatic parameter mutation path was found.

## Automated evidence in this environment

From the repository root:

```bash
python3 -m unittest discover -s tests -v
python3 -m py_compile tests/triad_reference.py tests/test_reference.py tests/test_source_contract.py
```

Fifth-pass suite result: **48 tests passed**. The suite includes independent profile, drawdown, firm-floor, non-zero-offset volume-grid, daily-state, phase-target, and UK/US DST arithmetic plus static source-contract checks for the fifth-pass corrections.

Additional checks passed for:

- balanced delimiters outside strings/comments;
- duplicate and obvious-unused helper detection;
- **131 unique referenced MQL functions**;
- tabs, NUL bytes, and trailing whitespace;
- prohibited direct trade APIs/behaviors;
- unresolved work markers;
- terminal-global worst-case name lengths;
- synchronized source/build identifiers outside this review;
- Python byte-compilation.

These checks inspect text and independent arithmetic only. They do not compile or execute MQL5.

## Residual risks and mandatory release blockers

1. **Compile the exact 2.1.4 source** in the current target MetaEditor/MT5 build with zero errors; investigate every warning and archive compiler output, EX5 hash, source hash, terminal build, and configuration.
2. Verify every used MQL API/enum on that build, especially `HistoryOrderGet*`/`ORDER_TIME_DONE`, `CTrade` ticket overloads, fill/expiry modes, `iATR`/`CopyBuffer`, terminal-global conditionals, timer registration, and deal/order properties.
3. Run deterministic MT5 harnesses for first-event M5 sequences, M15 indexing, both DST mismatch periods, quote refresh/ranking, all exact news/session/rollover boundaries, volume grids/limits, and day/week governor reset behavior.
4. Run restart/offline history drills proving pending and position rollover reconstruction, order-only foreign-history detection, state-signature rejection, ordinary halt reset, and non-resettable migration-latch behavior.
5. Fault-inject unavailable/partial terminal-global writes, stale calendar, malformed/missing coverage declarations, duplicate claimant races, stale-owner resumption, account/server switching, request timeout/late acknowledgement, partial fill, missing stop, incomplete delete/close, disconnect, and failed cleanup retry.
6. Reconcile broker propagation of order/position comments, magic numbers, SL/TP deal/order reasons, commissions/fees/swaps, fill prices, volume lattice/limit, stop/freeze levels, expiration, and adverse/favourable limit behavior.
7. Confirm the explicit calendar declaration against an independently verified complete UTC high-impact source. The declaration is an operator assertion, not proof that no event is missing.
8. Produce tick-quality 2019–latest training/walk-forward/OOS evidence per combination and portfolio, including every Section 13 fill-count, expectancy, profit-factor, stress, bootstrap, pass-probability, drawdown, inactivity, and zero-violation gate. Freeze priorities by the predeclared rule before final OOS.
9. Generate tick-exact MFE/MAE and execution-cost records in tester/post-processing; one-second runtime logs are not a substitute.
10. Complete 30–50 forward-demo fills on the exact broker symbols/server/infrastructure with zero operational errors and confidence-bound reconciliation.
11. Verify the purchased agreement/dashboard, exact product, account credentials, phase, targets, profitable-day formula/count, rollover, leverage, prohibited-practice interpretation, payout, and scaling terms.
12. Demonstrate the operational single-terminal rule. Terminal globals cannot coordinate another terminal, VPS, phone, API, copier, or manual session.
13. Keep execution and every release gate closed until all evidence is attached to one frozen release and the user explicitly approves it.

A migration implementation is deliberately absent from this build. Any existing live state carrying `PERSISTED_STATE_MIGRATION_LOCK` requires a separately reviewed release; deleting terminal globals is not an acceptable migration.

No software can guarantee firm floors under gaps, slippage, rejected emergency requests, stale data, terminal failure, network loss, or broker outage. Visible stops, the internal 5% shutdown, reserves, and early control lead reduce risk; they do not create a hard drawdown guarantee or prove a trading edge.
