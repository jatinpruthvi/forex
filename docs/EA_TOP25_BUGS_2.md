# Top 25 — second sweep (2026-10-05): the strategy classes, line by line

The first top-25 (`docs/EA_TOP25_BUGS.md`) looked at the shared engine, the Triad and the
tooling; it is closed (#1–#22 fixed, #23–#25 need Windows).  This sweep read what that one
skimmed: **the 65 strategy classes** (all 2 477 lines of `BuildPlan` and all 5 061 lines of
helpers), the signal library, and the Triad's execution layer.

It found that **16 of the 65 EAs — and the one-program portfolio EA that inlines them — could not
compile**, and a further layer of defects that fail silently.  47 of the 65 EAs change behaviour or
compile status as a result (32 with changed text, the rest through a shared primitive).

Priority: **P0** = the EA / portfolio does not build · **P1** = it builds but trades wrongly, never
trades, or leaves risk unmanaged · **P2** = wrong timing / robustness.  Line numbers are the code *as
delivered* (commit `dfd12c7`); every item is **FIXED** at the source of truth (generator or shared
header), guarded and tested — see *Verification*.

| # | Pri | Area | Finding | As delivered | Effect | Fix |
|---|---|---|---|---|---|---|
| 1 | P0 | compile | **R5B** (2017) names two variables `long` and `short` — MQL5 reserved words (MQL5 reference, *Reserved Words*) | `…round5_contestant_b.mq5:80-85` · generator `:5483` | EA — and the portfolio build — do not compile | `goLong` / `goShort` |
| 2 | P0 | compile | **R10FABLE** (2030) reads `EA_MAX_SYM`; the constant is `EA_MAX_SYMBOLS` | `…round10_claude_fable…mq5:92` | does not compile | corrected |
| 3 | P0 | compile | **R8B** (2027) reads `InpAplusScore`, declared nowhere; its booster also ignored the document's "once the month is ≥ +5 %" rule | `…round8_contestant_b.mq5:182` | does not compile; if it had, *every* A+ setup would have risked 1.25 % | input declared (95 = every optional filter met), `InpFreeRollMonthPct`, `MonthStartEquity()`, booster gated on the month |
| 4 | P0 | compile | **R4B** (2009) reads `ctx.adxD1`; `SEAContext` has no such field (the daily-ADX handle existed, unused) | `…round4_contestant_b.mq5:75` | does not compile | field added, reset, filled |
| 5 | P0 | compile | **13 EAs** assign `ep.emaPeriod`, `ep.maxDistanceAtr`, `ep.requireTrend` (14 sites) — members `SEmaPullbackParams` never had (not in git history either): 2009 2011 2013 2014 2015 2016 2019 2020 2021 2023 2038 2040 2048 | e.g. `…round11_contestant_d.mq5:106-107` | none of the 13 compiles | the three are real knobs (EMA 20/50/200 · tolerance in ATR · trend flag) honoured by `SigEmaPullback`; no EA text changed |
| 6 | P0 | compile | the **portfolio host** reads `InpSummary`, declared nowhere | `gen_portfolio_ea.py:733` | `AllEnginesEA.mq5` does not compile | input declared |
| 7 | P1 | strategy | **R2C 2005, R3A 2006, R3B 2007 can never go short** — `tradeBothWays = (bias > 0)` switches the bearish branch off exactly when the bias is bearish, then `plan.dir != bias → false` | `…round2_contestant_c.mq5:116` · `…round3_contestant_a__1_.mq5:86` · `…round3_contestant_b__1_.mq5:84` | three "two-sided" EAs were long-only | one-sided `onlyDir` on the OB and FVG detectors |
| 8 | P1 | SMC | **E1's sweep precondition reads time backwards** (my request-21 fix): `CopyRates` fills a plain array *oldest-first*, so the "prior liquidity" `r[50..59]` was the **newest** ten bars | `E1_SMC_Core.mqh:308` | a textbook sweep-and-reclaim could be rejected, a continuing breakdown accepted | re-done: prior = the 10 bars *before* the sweep candle (70 bars fetched) |
| 9 | P1 | strategy | **R5A 2016 / R5A2 2047**: "percentile of today's Asian range among the last 60 sessions" was computed against 60 full-**day** ranges | `…round5_contestant_a.mq5:153` · `…_a_2047.mq5:138` | an Asian range is a fraction of a day: percentile ≈ 0, so the `[20, 65]` band rejects almost every day (R5A2 effectively never trades) | `SigAsiaRangePercentile` over past Asian sessions (one H1 fetch) |
| 10 | P1 | strategy | **R7A 2022**: stop = `1.5 * gapAbs * ctx.point` — `gapAbs` is already a price | `…round7_contestant_a.mq5:77` | on a 2-digit index the stop is 100× too close, and sizing takes a 100× position for it | `1.5 * gapAbs` |
| 11 | P1 | strategy | **R7A**: cash open and prior close compared on the **server** clock; "prior close" was the day's *last* bar; a hard-coded 300-bar loop; target already behind the entry | `:91`, `:108` | wrong gap (the overnight move; the cash open taken one broker-offset early); an out-of-range read stops the EA (and every engine in the portfolio) | UK clock, the 16:30 bar, loop bounded by the copy, target checked |
| 12 | P1 | risk | **RiskGovernor flatten is fire-and-forget**: return codes ignored, the freeze flag set regardless, the freeze branches just `return` — and `OnTimer` returns before maintenance while frozen.  The Friday 21:00 close is one-shot too | `RiskGovernor.mqh:319` · `:198` · `Master_Triad_V1.mq5:162` | one rejected close leaves a position unmanaged for the whole freeze / weekend (and the object's `CTrade` never set a fill mode) | verified, fill mode per symbol, retried every 5 s until flat; freeze log once per 15 min (was once per second) |
| 13 | P1 | execution | **E1 consumes the sweep before the order is sent** (and persists that in a GV) | `E1_SMC_Core.mqh:228`, `:237` | a spread blip or stop-level rejection burns the setup for good | consumed only when placed; three failures abandon it; the low-grade skip logs once per candle |
| 14 | P1 | strategy | **3110**'s "external cashflow" check compares the balance with a reference refreshed only while flat with zero trades today | `…TRIAD_R_HS_CODE_REVIEW.mq5:196` | the realised P/L of any trading day halts the EA the next morning — it trades about every other day | looks for balance-type deals (balance / credit / charge / correction) |
| 15 | P1 | strategy | **R11E / R12B** "shutdown / halt for the month" uses an all-time high-water mark in a fixed GV | `…round11_contestant_e.mq5:142` · `…round12_contestant_b.mq5:126` | after a drawdown from the peak of ≥ 6 % (R11E) / 8 % (R12B) there are no trades, so equity can never regain the peak ⇒ locked out for good while still above the start balance (the engine's separate permanent floor from the *start* balance is untouched) | the HWM key carries the server month |
| 16 | P1 | risk | **five EAs share fixed HWM names** (`R10KIMI_HWM`, `R11C_`, `R11D_`, `R11E_`, `R12B_`) — across every account, never reset | same | a prop-account reset or demo→live inherits the old peak and throttles / stops | `EA_HwmKey(tag, monthly)` = account + magic (+ month) |
| 17 | P1 | strategy | **gold swing (3101)**: the opposite-channel exit tests `r[1].close`, a bar that is *inside* the channel `r[1..55]` | `…FINAL_OPTIMUM_STRATEGY.mq5:299` | the documented exit can never fire (only the chandelier remains) | tests `r[0]`, the entry's own geometry |
| 18 | P1 | strategy | **TRIAD_SURVIVE sleeve B**: one fixed reference window (bars 3–18) for every breakout candidate | `…TRIAD_SURVIVE.mq5:331` | candidates 3–6 sit inside the range they must close beyond; only the last two bars can ever break out | a 16-bar reference range per candidate |
| 19 | P1 | execution | **staged exits** flag the partial / break-even as done whether or not the broker accepted them | `ExecutionManager.mqh:361` | one requote at +1.5R = neither the partial nor the BE stop, for good | the two steps are independent and retried |
| 20 | P1 | strategy | **R4D** passes the Asian-range edge to its stop builder, not the sweep wick | `…round4_contestant_d.mq5:166` | the stop sits inside the wick price already visited (the document: "beyond the sweep extreme") | `r[3].low` / `r[3].high` |
| 21 | P1 | SMC | **`SigOrderBlockRetest` has no block-failure test** | `EASignals.mqh:1262` | a block price has traded *through* still fires a long on the way back (5 EAs) | no closed bar since the displacement may close beyond the block's far side |
| 22 | P1 | SMC | **`SigBreakRetest` judges break and retest on the same candle** — a breakout candle that opened inside the range always "retests" | `EASignals.mqh:857` | a breakout chaser, not a retest strategy (7 EAs: 2001 2002 2009 2015 2021 3116 3117) | the retest must be a *later* closed bar that holds the level |
| 23 | P2 | indexing | **one bar late**: fetch from bar 1 with logic written for bar 0 — 3102, 3104 (M1 reversion), 3101 `TriadPlan`, 3111 sleeve C; R8D judged the wrong candle | `…THE5ERS_CHALLENGE_STRATEGY_V2.mq5:119` · `…2_5K…:139` · `…FINAL_OPTIMUM…:123` · `…TRIAD_SURVIVE.mq5:411` | every signal (and a resting limit) arrives one candle late | fetch from bar 0; R8D uses `plan.barsAgo` |
| 24 | P2 | robustness | **reads past what `CopyRates` returned**: `MedianRange` ×8 sized and read 20 after checking 10; R7A, R5A/R5A2, `ObQualityScore`, `SniperSetup`, `LiquidityTarget` | `…round8_contestant_b.mq5:124` … | an out-of-range read stops the EA — in the portfolio build, every engine | bounded by the returned count / guards raised |
| 25 | P2 | time | **server vs London clock**: `RangeBetween` ×6 compared bar minutes with London windows; `TradesThisSession` (R11A, R12QWEN) and `TradedThisSession` (R12C) subtracted a London session start from a server time | `…round8_contestant_b.mq5:136` · `…round11_contestant_a.mq5:162` · `…qwen…:218` · `…round12_contestant_c.mq5:131` | range-quality filters measured the wrong hours; one session's closed trades counted against the next's limit | `EA_BarClockTime` / `EA_ClockToServer` |

## Also fixed in the same files

R12A's scoreboard credited sweep + rejection + displacement with 2 points (max 7/8, so "≥ 7" demanded
perfection) — now 3 · R12A / R12F / R12FABLE measured the last closed bar's volume instead of the
*sweep candle's* (new `SigSweepVolumeRatio`) · R4C2 shaped plans with the previous symbol's regime ·
R4A's delta-hedge scalper needs a hedging account (a netting account would net the hedge against the
runner) · ExecutionManager: the half-lot floor lost a step on 14 of 399 lot sizes (IEEE: `0.29 / 0.01
= 28.999999999999996`), a 0.02-lot "25 %" partial was 50 %, an empty `ManageH1Bailout()` stub that
read like a protective exit, a duplicated default argument, a "4 hours" comment on a 45-minute rule.

## Reviewed and deliberately not changed (next tier)

SOS / ORB score asymmetry (bearish gets a flat +5; ranking only) · R1C can trade an order-block
plan that disagrees with the confluence it counted · FVG `maxRetrace` is a minimum depth (documented,
behaviour kept) · E1's SMT gate and H1 filter fail open when their data is not ready · E1's session
window is raw server hours · `GetEquityCurveThrottleMultiplier()` still returns 1.0 · R3A's "limit-only
entry at the block edge" rests at the ask · R10GEMINI's stop is 1 point, its comment says 1 pip ·
`SigDonchian` triggers intraday on the live price.

## Verification

| | Result |
|---|---|
| Static rules added | reserved-word identifiers · undeclared project identifiers · struct members (scope-aware) · duplicate declarations · undeclared variables — against the *delivered* EAs they report **51 findings**; against the fixed tree **0**, across the 65 EAs, headers, Triad, scripts, tracker and the generated portfolio build |
| `verify_portfolio.py` | **OK — 1 940** (was 1 906; +2 for R8B's inputs, +32 guards) |
| Tests | **332** (was 250): `test_compile_class_guards` 18 · `test_ict_smc_fixes` 35 · `test_risk_flow_fixes` 30; the old `SweepTests`, which pinned the *wrong* sweep rule, are replaced |
| Measured control | with the six Stage-B/C source files reverted: **22 of 1 940** checks and **20** tests fail |
| Behavioural proof | each rule is mirrored in Python and pinned against the defect it replaces (the mirror of the delivered rule must give the wrong answer on the fixture) |

**Not verified (cannot be here):** a MetaEditor compile and a Strategy Tester run.  The static rules
narrow the compile risk — they found 16 broken EAs that six earlier passes had not — but they are not
a compiler; run `validation/mt5_harness/compile_all.ps1` first.  Items 7, 9, 10, 14, 17, 18 and 22
**change what the EAs trade** (more shorts, far more sweep entries for R5A2, tighter or wider
stops, real retests); the earlier backtest numbers for these EAs — where any existed — describe code
that either did not compile or behaved differently.
