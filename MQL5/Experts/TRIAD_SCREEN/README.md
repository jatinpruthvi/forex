# TRIAD_SCREEN — multi-symbol demo screening EA with on-chart dashboard

**Status: research/screening tool. Not compile-verified, not backtested, not approved
for challenge or funded trading.** It must be compiled in MetaEditor on your MT5
build (zero errors, review every warning) before use — nothing in this repository
compiles MQL5.

This is a **separate** implementation. The frozen canonical EA
(`TRIAD_R_HS/TRIAD_R_HS.mq5`), the V2.1 registry, and the V2.2 ablation registry
are **not modified** by this tool.

## What it does

Each MT5 **demo account** runs **one symbol + one session-window combination**
(`InpSymbol` + `InpWindow`), matching your chosen layout: one combo per account.

For that combo it:

- ports the frozen V2.1 entry rules (session range, M5 sweep/reclaim/displacement
  geometry, ATR/range percentile gates, spread gate, all-in §6 volume, visible
  SL/TP, time stop / breakeven / session-end exits);
- tracks a The5ers-style **funding-challenge rule set** (editable): phase target
  (+10%/+5%), qualifying days (≥ $12.50), daily loss boundary (5%), overall floor
  (10% / $2,250), inactivity (30 days);
- draws a **simple on-chart dashboard** showing, for that account:
  `STATUS: ACTIVE / PASSED / FAILED_* / TARGET_REACHED_DAYS_PENDING / HALTED:*`,
  phase progress, qualifying days, daily/overall floor distances, today's
  signals/candidates/fills/rejects, net-R ledger, and the exact **setting
  fingerprint** (`ConfigHash`) so you know which EA settings each account ran;
- writes three small CSVs per combo+login into `MQL5/Files/` for later review:
  `TSC_<prefix>_J_<login>_<combo>.csv` (event journal),
  `TSC_<prefix>_S_<login>_<combo>.csv` (persisted day/challenge state),
  `TSC_<prefix>_D_<login>_<combo>.csv` (per-day summary),
  `TSC_<prefix>_P_<login>_<combo>.csv` (planned cash risk per position),
  `TSC_<prefix>_T_<login>_<combo>.csv` (closed-trade R ledger).

## Why it exists

The frozen V2.1 scope is only EURUSD-London, GBPUSD-London, USDJPY-New York.
`TRIAD_SCREEN` lets you test the wider eligible universe — all seven majors (and
EURJPY/GBPJPY) in **both** London and New York windows — on separate demo
accounts, one combo each, and compare in one glance which combos produce
signals/fills and whether each demo account would pass or fail the configured
challenge rules.

## Supported symbols / windows

Any of: `EURUSD, GBPUSD, USDCHF, AUDUSD, USDCAD, NZDUSD, USDJPY, EURJPY, GBPJPY`
combined with `TSC_WINDOW_LONDON` or `TSC_WINDOW_NEW_YORK` (18 combos). The EA
fails closed at init for any other symbol.

Session windows are ported verbatim from the canonical EA:

| Window | Reference range (local) | Entry window (local) |
|---|---|---|
| London | 00:00–07:00 | 07:00–11:00 |
| New York | previous London day 07:00–13:00 | 08:30–11:00 |

## Quick start

1. Create a demo account (broker of choice) for each combo you want to test.
2. Compile `TRIAD_SCREEN.mq5` in MetaEditor (zero errors).
3. Open a chart for the combo's symbol, attach the EA, set:
   - `InpSymbol` = the combo symbol;
   - `InpWindow` = `TSC_WINDOW_LONDON` or `TSC_WINDOW_NEW_YORK`;
   - `InpComboLabel` = optional short label (defaults to `SYMBOL_LON` / `SYMBOL_NY`);
   - `InpChallengePhase`, `InpPhaseInitialBalance` = your challenge phase config;
   - the challenge-rule inputs (`InpPhase1TargetPercent`, `InpQualifyingDayPercent`,
     `InpDailyLossPercent`, `InpOverallLossPercent`, `InpMinQualifyingDays`,
     `InpInactivityDays`, …) to match the account's actual agreement — the
     defaults are the The5ers $2,500 New High Stakes preset from
     `THE5ERS-2.5K-CHALLENGE-PLAN.md` (Phase 1 +10% = $250, Phase 2 +5% = $125,
     3 days × $12.50, 5% daily, 10% = $2,250 floor, 30-day inactivity);
   - `InpEnableOrderSubmission = true` **only on demo accounts** (leave false to
     run a *dry* dashboard: signals/candidates are counted, no order is sent).
4. Keep `MQL5/Files/triad_red_news.csv` current (same schema as the canonical EA:
   `utc_time,currency,impact,title` plus the `ALL,COVERAGE` row, UTC, RED/HIGH
   impact). If you do not want the news blackout in this screen, set
   `InpRequireNewsCalendar=false` — the dashboard will show `Calendar: DISABLED`.

## Reading the dashboard

- `STATUS: PASSED` — balance ≥ phase target AND qualifying days ≥ minimum.
- `STATUS: TARGET_REACHED_DAYS_PENDING` — target reached, day count still short.
- `STATUS: FAILED_OVERALL_FLOOR` — equity ≤ 90% of phase initial balance.
- `STATUS: FAILED_DAILY_FLOOR` — equity ≤ daily snapshot × (1 − daily loss %).
- `STATUS: FAILED_INACTIVITY` — no own-magic closed trade for `InpInactivityDays`.
- `STATUS: ACTIVE` — within rules.
- `DRY RUN (orders disabled)` marker — the status is still computed from real
  account equity so you can watch a combo without risking orders.
- `ConfigHash` — a fingerprint of every input that changes behavior; record it
  with each account so you can attribute results to settings, not guesses.
- `Ledger: net_r` — realized net R from closed trades, using the planned cash
  risk recorded at fill time (accurate for trades opened while this EA ran;
  positions adopted after an EA restart have no recorded risk and are excluded).

## Halt and reset behavior

- `STATUS: HALTED:*` is a **per-run latch** inside this screen EA (config failure,
  state-file mismatch, …). A **restart is the documented recovery** — a halted
  state saved to the state CSV is *not* restored on the next init, so re-attach
  the EA after fixing the cause and it resumes from the persisted account state.
- The **non-emergency request cap** (`InpMaxNonEmergencyRequestsDay`) never halts
  the screen EA: reaching it only blocks further non-emergency requests for the
  day (logged `REQUEST_CAP_REACHED`) so the dashboard keeps running.
  **Emergency cleanup is never gated by that cap** — protective deletes/closes
  (missing SL/TP, news, rollover, floor breach, phase completion) are only
  per-ticket throttled (10 s), exactly like the canonical EA.
- `InpAllowPhaseReset = true` only takes effect when the existing state file does
  **not** match the combo/`InpChallengePhase` (e.g. after re-pointing an account
  to a different combo or phase): it deletes that combo's state CSV and starts a
  fresh day/challenge ledger. It cannot be used to retroactively pass — the
  challenge status machine still derives everything from account equity.

## Safety semantics (canonical parity)

- **Same rules gate both entries and exposure.** If a risk guard fails (daily/
  overall floor, internal stops, strategy drawdown shutdown, phase complete)
  `ManageExposure` cancels own pending orders **and closes own positions** —
  exactly like the canonical EA. A floor breach never lets an open position ride.
- **Foreign/manual exposure** is detected; own-magic exposure is cleaned and the
  event is logged (`FOREIGN_EXPOSURE`). Foreign objects are left untouched but
  block new entries for the day (`manual_or_foreign_deal_detected`).
- **One exposure invariant**: at most one own pending order *or* one own
  position; a violation is repaired by cancel/close (`EXPOSURE_INVARIANT_VIOLATED`).
- **Mid-session attach** (`InpSkipFreshMidSessionStart = true`, canonical default)
  consumes the session instead of reconstructing a stale event, and the range is
  only trusted once it is fully closed (`now >= range_end` — the canonical rule;
  this is what makes the New York window work, since its London reference range
  closes before its entry window opens).
- **High water is updated only while flat** (canonical `UpdateHighWater` gate), so
  an open position cannot distort the drawdown basis.
- **Detach cleanup**: on an intentional detach with order submission enabled and
  exposure present, pending orders are cancelled and positions closed
  (`DEINIT_EXPOSURE_CLEANUP`); terminal shutdown keeps visible broker exits.
- **Closed-trade ledger is crash-safe**: a processed-position id set (loaded from
  `T.csv`) plus plan-row-first removal make double accounting impossible, and
  partial closes on still-open positions are not counted as completed trades.

## Important caveats (read before drawing conclusions)

- **No edge evidence.** Signals and fills on demo accounts prove mechanics only.
  The canonical Section-13 pipeline (fresh splits, real tick export, frozen
  registry, preregistered ablations) is the only path to an edge claim.
- **This is not the canonical EA.** It drops production safety machinery
  (instance locks, journal signatures, lifecycle locks). Do **not** attach it to
  a live/funded account; use it only to screen demo accounts.
- **Rule numbers are your responsibility.** The presets mirror the plan document
  in this repo, but the live agreement governs; verify every number (base for
  Phase 2, payout/scale locks, inactivity) against the account.
- **Broker specifics matter.** Prices are normalized to `SYMBOL_TRADE_TICK_SIZE`
  (not `SYMBOL_POINT`), and session bounds are derived from UK/US DST rules
  against `InpExpectedServerUtcOffsetHours` — set that offset to the broker's
  actual server offset; the EA warns on account-currency/balance mismatch at init.
- **Phase 2 base** is the same $2,500 phase-initial input here; if your actual
  Phase-2 account base differs, set `InpPhaseInitialBalance` for that account.
- **News CSV** must be operator-verified; a stale calendar blocks entries
  (fail-closed, same as canonical).
