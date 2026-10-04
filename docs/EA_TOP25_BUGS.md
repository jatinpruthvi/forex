# Top 25 — highest-priority defects and gaps

_2026-10-04. Owner request: "find top 25 high priority bugs in our development"._

**How this list was produced.** Full-file reads of the one live path the twelve
earlier passes never audited (`Master_Triad_V1.mq5` + `RiskGovernor.mqh` +
`ExecutionManager.mqh` + `NewsManager.mqh` + `E1_SMC_Core.mqh` — that is the
second EA in the repo, unrelated to the 65-engine delivery), the launcher and
preflight scripts, the harness tooling, the tracker, the generated host, plus
the automated detectors (checker / arity / verifier) and the official MQL5
documentation for the clock and calendar semantics. Every item carries its
evidence as `file:line`.

**Types.** `DEFECT` = a verified code defect. `RISK` = an unverified assumption
that would be a defect if it holds (no compiler/tester here). `GAP` = a
verification gap (no evidence either way). `LIMIT` = a documented limitation that
still matters for decisions.

**Priority.** `P0` = corrupts the results of the run we are about to make.
`P1` = wrong money/risk behaviour or a silent failure. `P2` = wrong behaviour in
a narrower window. `P3` = hygiene.

## Status (fix pass of 2026-10-04)

**Fixed at the source, guarded and tested:** #1, #2, #3 (previous pass) and
**#4–#22** in this pass:

| # | what changed |
|---|---|
| 4 | pending orders judged by `order.OrderType()`, not the stale position object |
| 5 | `DetectLiquiditySweep()` implemented (takeout + reclaim on the same M15 window/indexing as the CHoCH) — **entries are now strictly rarer; re-validate on the tester** |
| 6 | heat / currency exposure count only this magic's positions and orders |
| 7 | Triad news gate **fails closed** when the calendar is unusable; impact compared case-insensitively on both load paths; the 2030 coverage sentinel no longer loads as a blocking event |
| 8 | rows whose timestamp does not parse are rejected and counted; an all-bad or empty file fails the load |
| 9 | state keys namespaced `MasterTriad_<account>_<magic>_<field>`; day key is the full server date; the pre-upgrade values are adopted once, then the legacy keys are deleted |
| 10 | daily breaker = rest of the server day; trailing breaker = a real 48 h freeze the day boundary does not lift |
| 11 | bearish structure search mirrors the bullish one |
| 12 | attempt cooldown keys on M15 (the setup timeframe), not the chart's |
| 13 | SMT gate passed as a constructor parameter; the inert case (no DXY symbol) is logged; the dead `m_hDxySmt` handle removed |
| 14 | `GetDailyRealizedPnL()` uses the server-day boundary and filters by magic |
| 15 | the daily-range vintage pair is stated truthfully in the code |
| 16 | `compile_all.ps1` matches the log case-insensitively and requires evidence the compiler ran |
| 17 | the synthesised-template risk is loud in stdout and in `READ_ME_FIRST.txt` |
| 18 | equal `end_time` ties broken by file mtime |
| 19 | `gen_launcher.py` writes `symbols.txt`; `UniversePreflight.mq5` reads it and warns when it falls back to the builtin list |
| 20 | `#property strict` removed from the four Triad files |
| 21 | the resolved server offset is logged once, implausible values are an error |
| 22 | tracker limits documented (closed-only verdicts; entry-commission edge) |

**Also closed this pass:** the calendar-upkeep finding from the audit (the news module used to load once per chart and never refresh) - see `docs/EA_BUG_AUDIT.md`, "Calendar upkeep".

**Still owner/Windows-side (nothing to fix in code):** #23 compile,
#24 tester sweep, #25 demo run.

**Behaviour changes to be aware of** (all disclosed, none silent): the sweep
precondition (#5) makes entries rarer; the trailing-DD freeze now really lasts
48 h (#10); the news gate can block instead of trading blind (#7); the SMT switch
can now log that it is inert (#13).

## The list

| # | P | Type | Area | Finding | Evidence | Impact | Action |
|---|---|---|---|---|---|---|---|
| 1 | P0 | DEFECT **[FIXED]** | engine clock | `EA_ServerGmtOffsetHours()` auto path reads `TimeTradeServer() − TimeGMT()`; MT5 documents that **in the tester `TimeGMT()` always equals the simulated `TimeTradeServer()`**, so the difference is always 0 → the engine believes "server == UTC" | `MQL5_Master/Include/EACore.mqh:405-411`, `:427-429`; engine 3107 sets `serverOffsetAuto=true` (`EA_THE5ERS_HIGH_STAKES_RESEARCH.mq5:66`, generator `scripts/gen_additional_eas.py:1501`) | In every backtest of magic 3107 the news window, session windows and the London day anchor shift by the broker offset (2–3 h), i.e. defect #90's failure mode delivered inside the engine | guard the auto path with `!MQLInfoInteger(MQL_TESTER)` and fall back to the configured winter/EU-DST rule — **done** |
| 2 | P0 | DEFECT **[FIXED]** | launcher | expert names matched by substring in both directions; **four delivered names are prefixes of another delivered EA** and both members of each pair are in `launch_plan.csv`: `round4_contestant_b` / `..._b__1_`, `round4_contestant_c` / `..._c__1_`, `round5_contestant_a` / `..._a_2047`, `round5_contestant_b` / `..._b_2048` | `MQL5_Master/Scripts/PortfolioLauncher.mq5:127-155` (`ExpertInPlan`, `FindRunningChart`), plan evidence: 65 rows, both names in each pair | One EA of each pair is skipped as "already running"; `STOP` closes the wrong chart; the attach check can pass for the wrong EA | exact match on a normalised key (path + `.ex5` stripped) — **done** |
| 3 | P0 | DEFECT **[FIXED]** | news gate | a calendar load that returned *nothing* left its server-time frame set, so a fallback **UTC** CSV was read in the server frame (regression from the 2026-10-04 news work) | `MQL5_Master/Include/EACore.mqh:600-635` | live runs with `InpNewsCalendar=true` on a broker whose calendar is empty fall back to the CSV and shift every window by the broker offset | reset the frame at the start of the CSV path; the marker may set it again — **done** |
| 4 | P1 | DEFECT | risk governor | pending-order risk-free test uses **`m_position`** (the position object, stale from the previous loop) instead of the order's own type/price | `MQL5_Master/Include/RiskGovernor.mqh:387-388` | pending limits are classified as risk-free when an unrelated position happens to be a winner → the 1.5 % net-currency cap under-counts and the book can be over-exposed | test `order.OrderType()` / `order.PriceOpen()` |
| 5 | P1 | DEFECT | strategy core | `DetectLiquiditySweep()` is a **stub that returns `true` unconditionally** — the documented entry precondition ("liquidity sweep") never runs | `MQL5_Master/Include/E1_SMC_Core.mqh:269-271` | entries fire on CHoCH alone; results cannot match the document; the audit category "code that does nothing" | implement the sweep rule or delete it and re-document the entry |
| 6 | P1 | DEFECT | risk governor | `GetTotalPortfolioHeat()` / `GetNetCurrencyExposure()` loop **all** positions and orders with no magic filter, while `CloseAllPositions()` does filter by magic | `RiskGovernor.mqh:266, 302, 331, 370` vs `:236` | a manual position or another EA's trade counts as this EA's heat/exposure; one stop-less position adds a synthetic **100 % heat** and silently blocks all trading | filter by `DEAL/POSITION_MAGIC == m_magic` (keep the deliberate stop-less=∞ rule per position) |
| 7 | P1 | DEFECT | news (Triad) | `IsNewsBlockActive()` returns `false` when the event list is empty (**fails OPEN**), and the parser keeps only the exact string `"High"` (**case-sensitive**) | `NewsManager.mqh:258`, `:190` | a feed/CSV that writes `HIGH`/`high`, or an empty parse, silently disables the news filter while the EA keeps trading — the 65-engine family is fail-closed for exactly this reason | fail closed (or at least log loudly) and compare case-insensitively + accept a numeric importance |
| 8 | P1 | DEFECT | news (Triad) | date/time mapping is unvalidated: any unexpected feed format makes `StringToTime()` return 0, and the event lands at 1970 + offset | `NewsManager.mqh:198`, `:304`, `:258` (past events never block) | a changed feed format silently turns news protection off (no error, no log) | validate the parse (year/month/day sanity, non-zero result) and log the count of dropped rows |
| 9 | P1 | DEFECT | risk governor | state GVs (`MasterTriad_PeakEquity`, `_LastDay`, `_InitialBalance`, `_BreakerTime`) are keyed by a **fixed name**: not per account, not per magic; the day key compares `day_of_year` only | `RiskGovernor.mqh:58-87`, `:75` | switching account (or a prop-firm account reset) inherits the old peak → the −4 % trailing breaker can trip on the first tick; a restart exactly one year later on the same day-of-year is treated as "same day" and keeps a year-old daily anchor | namespace the keys with account+magic and compare the full date |
| 10 | P1 | DEFECT | risk governor | the "freezing 24h" / "48h" message is contradicted by the day-rollover reset, which clears `m_breakerResetTime` at the next server midnight | `RiskGovernor.mqh:115-120` vs `:137`, `:154` | a breaker tripped at 23:50 is lifted ten minutes later; behaviour is only "sticky" because the DD check re-trips on the next evaluation | either keep the breaker until its timestamp or fix the message and document the day-boundary semantics |
| 11 | P2 | DEFECT | strategy core | mirror-image sweep detection is asymmetric: the bullish path takes the **global max high** after the sweep, the bearish path takes the **first fractal swing low** | `E1_SMC_Core.mqh:305-315` vs `:380` | identical setups grade differently by direction; long setups can be graded against a far-away swing | use the same rule both ways (immediate fractal, or the same max/min test) |
| 12 | P2 | DEFECT | strategy core | the attempt cooldown keys on `SeriesInfoInteger(symbol, PERIOD_CURRENT, …)` — the **chart's** timeframe | `E1_SMC_Core.mqh:160` | attaching the same EA to an M1 vs an H1 chart changes trade frequency (1-minute vs 1-hour cooldown); the strategy's own clock is M15 | use the setup timeframe (`PERIOD_M15`) |
| 13 | P2 | DEFECT | strategy core | the SMT gate is silently inert when neither `"US Dollar Index"` nor `"DXY"` exists at the broker (most brokers); `m_hDxySmt` is declared but never initialised or used | `E1_SMC_Core.mqh:25`, `:118-135`, `:73-74` | `InpUseDxySmtGate=true` does nothing, with no log — a silent no-op input | log "SMT gate unavailable (no DXY symbol)" once, or fail the init when the gate is requested |
| 14 | P2 | DEFECT | risk governor | `GetDailyRealizedPnL()` computes the day start as `TimeCurrent() % 86400` (epoch mod → **UTC** midnight, not broker midnight) and sums all magics | `RiskGovernor.mqh:212-221` | unused today, but silently wrong the day someone wires it into the breaker | compute from `TimeToStruct`/server midnight and filter by magic |
| 15 | P2 | DEFECT | execution | `GetDailyRange()` comment says "index 1 (yesterday's completed range)" while the call copies index 0 — **today's unfinished bar**; `GetDailyATR()` really does use index 1 | `ExecutionManager.mqh:442-447` vs `:429-437` | the ATR-exhaustion TP shrink mixes vintages (yesterday's ATR against today's partial range); intent is unreadable | make comment and code agree and state the intended vintage |
| 16 | P2 | RISK | compile gate | `compile_all.ps1` decides success by counting `": information: result"` in the MetaEditor log — an **unverified string** (casing/wording of the CLI log is not checked anywhere) | `validation/mt5_harness/compile_all.ps1:102` | a clean compile could be reported as 65 failures (or a real error missed) on the first Windows run, wasting the run | match case-insensitively on "result"/"errors", or parse the last line of the log; verify on the first real compile |
| 17 | P2 | RISK | launcher | the synthesised `.tpl` (hand-built `flags=343`, `period=…`) is a guess unless `--base-tpl` is used | `validation/mt5_harness/gen_launcher.py:126-146` | if MT5 rejects the format, no EA is attached (`ChartApplyTemplate` false → reported, so not silent) | use a saved template (`--base-tpl`) for the first real launch; keep synth as fallback |
| 18 | P2 | DEFECT | harness | on equal `end_time` the parser keeps the **alphabetically later file**, not the newer run | `validation/mt5_harness/parse_results.py:125` | a stale result can win a tie during repeated sweeps | include the file mtime in the tie-break |
| 19 | P2 | DEFECT | preflight | the preflight symbol list is a hardcoded snapshot of the union of universes | `MQL5_Master/Scripts/UniversePreflight.mq5:25` | a future universe change silently makes the preflight stale (a missing symbol then looks "not traded") | generate the list from the same source as the configs |
| 20 | P3 | DEFECT | hygiene | `#property strict` (MQL4-only directive) in the Triad set | `Master_Triad_V1.mq5:8`, `RiskGovernor.mqh:5-6`, `ExecutionManager.mqh:7`, `E1_SMC_Core.mqh:7` | ignored property/warning noise; the repo checker already flags it | remove |
| 21 | P3 | RISK | engine clock | engine 3107 is the only EA that reads the live auto offset, whose correctness now depends on the VPS PC timezone (`TimeGMT()` is derived from it) | `EA_THE5ERS_HIGH_STAKES_RESEARCH.mq5:66` + `EACore.mqh:408` | a mis-set VPS timezone shifts its sessions/news by hours, live, with no symptom | log the resolved offset at init and sanity-check it (|offset| ≤ 14 h) |
| 22 | P3 | LIMIT | tracker | a position opened before `InpDaysBack` loses its entry-side commission from the round turn (net understated); the verdict is closed-only by design (floating P&L not counted) | `portfolio-EA/src/PortfolioEA.mq5:219-243`, `:318` | long-carry trades look slightly worse; documented, but worth stating in the panel footer | note it in the README/verdict rules |
| 23 | P0 | GAP | everything | **47 000 lines of MQL5 have never been compiled.** The last two passes alone found five compile-blocking adjacent string literals, and two of the items above would only show up in a backtest | `validation/mt5_harness/compile_all.ps1` (never run); repo-wide adjacency scan is the only stand-in | any of the open defects above can be masked by a compile error; nothing here is proven to build | run `compile_all.ps1` first on Windows — it is the single highest-value next action |
| 24 | P1 | GAP | validation | no Strategy Tester sweep has ever run: no PASS/WARN/FAIL table, the six fail-closed news engines need the Stage 0b calendar file, and the four widened universes' older backtests are invalidated (owner decision) | `docs/EA_VALIDATION_PLAYBOOK.md` Stage 0b/1; `--symbols wide` | all performance decisions (KEEP/REVIEW/DROP, demo switches) are currently blind | Stage 0b calendar for the tester window, then `--symbols wide`, then `parse_results.py` |
| 25 | P1 | GAP | demo | no demo run with the tracker: the live switches, tracker verdicts/panel and the new live-calendar source are unverified live; 65 engines in one thread (476 indicator handles, 1 s timer) have never been timed | `portfolio-EA/src/PortfolioEA.mq5`, `portfolio-EA/README.md` deploy steps | the switch semantics and the dashboard are the operator's only feedback | demo run on one account, tracker attached, after the compile |

## Fixed in the first pass (with verification)

Three of the four P0-class items were fixed **at the source**, each with a
permanent verifier guard and a regression test:

* **#1 tester auto-offset** — both helpers now refuse the auto path in the tester
  (`EACore.mqh:405-411`, `:427-429`) and use the configured winter/EU-DST rule,
  which is the only usable one there because the modelled `TimeCurrent()` *is*
  the broker clock.
* **#2 launcher expert matching** — `ExpertKey()` normalises path and
  `.ex5`/`.mq5` and all three call sites compare exactly
  (`PortfolioLauncher.mq5`).
* **#3 news fallback frame** — the CSV path restarts the frame, so a calendar
  that keeps nothing cannot leave its server frame set for a UTC file
  (`EACore.mqh`, in `EA_LoadNewsCache`).

New tests pin all three: `tests/test_harness_scripts.py` (launcher pairs +
offset policy) and `tests/test_news_timeframes.py` (fallback frame).

Battery after the fixes: `verify_portfolio.py` **OK - 1 846 checks** (with the
new guards), repo checker **0** on the 65 delivered EAs (92 known legacy
findings), arity **0/0**, `gen_portfolio_ea.py --check` OK-65, `unittest discover
tests` **222 tests run** (1 documented pytest-loader artifact for the missing
`pytest` module). **Nothing was compiled** (no MetaEditor on Linux) — item #23 stands.

## What I could not verify

* Whether the code compiles at all (#23) — no MetaEditor in this environment.
* MetaEditor's exact log wording (#16) and whether MT5 accepts the synthesised
  templates (#17) — both need one Windows run.
* The live calendar source's behaviour against a real broker feed (documented
  fallback exists and is tested in mirror form only).
* Whether the Triad path (#4–#15) matches its strategy documents in behaviour —
  only the code was reviewed; there is no Triad test harness like the 65-engine
  one.

## Recommended order

1. **Windows: `compile_all.ps1`** (#23) — everything else is downstream.
2. **Risk-governor fixes #4 and #6** before any live/demo money (they are the
   only items that can *increase* risk silently).
3. **Stage 0b calendar + `--symbols wide` sweep** (#24) — the number that drives
   the KEEP/REVIEW/DROP decisions.
4. **News hardening #7/#8** (fail-open) — same class as the fixed #3.
5. **Demo run with the tracker** (#25), then the remaining P2/P3 items.
