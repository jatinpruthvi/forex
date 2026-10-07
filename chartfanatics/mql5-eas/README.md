# ChartFanatics EAs

Expert Advisors built from the ChartFanatics playbooks archived in this folder. One `.mq5` per
strategy, each wired into the repository's shared engine (`MQL5_Master/Include/EACommon.mqh`), each
with its own magic number, and each traceable back to its work card in
[`../todos/`](../todos/).

**Status: static-checked and doc-synced, not yet compiled.** `python3 scripts/check_mql5_source.py
chartfanatics/mql5-eas/*.mq5` reports 0 findings (contract: `CEAStrategy` subclass, unique magic,
engine delegation, no MQL4 contamination, declared identifiers, **duplicate declarations**,
balanced blocks), and `tests/test_chartfanatics_sync.py` fails the build if any playbook rule stops
matching the code that implements it (see *Rule -> code sync* below). Nothing here has been through
MetaEditor yet — that is Stage 0 of
[`docs/EA_VALIDATION_PLAYBOOK.md`](../../docs/EA_VALIDATION_PLAYBOOK.md) and the first thing to run
on the Windows machine.

## Wave 1

| Card | Strategy | EA | Magic | TF | Reads from the engine |
|---|---|---|---|---|---|
| [#01](../todos/5-stage-trading-framework.md) | 5 Stage Trading Framework | `EA_CF_Stage_Guardrails.mq5` | 3207 | — | **Monitor, never trades.** Card #01 is a trader-development framework with no entry/exit rules, so this EA mechanizes what the document does contain: it sweeps the account's own deal history (every magic) on the stage's thresholds and journals/flags breaches — daily loss cut-off, trade-count cap, entry within N minutes of a losing close ("revenge trade"), an entry above N× the day's average size ("sizing up too fast"), and a losing streak past the stage's pause. Writes `MQL5/Files/cf_stage_journal.csv` |
| [#04](../todos/amd-model.md) | AMD Model | `EA_CF_AMD_Model.mq5` | 3201 | M5 | `SigSweepReclaim` + `SigEmaCascade`, playbook macro windows (09:50–10:10 / 10:50–11:10 ET), 2 trades/day, two-loss day lock |
| [#39](../todos/structure-ote.md) | Structure + OTE | `EA_CF_Structure_OTE.mq5` | 3202 | M15 | `SigOrderBlockRetest` (POI) + breaker fallback, **first premium/discount + OTE (62–79%) implementation in the repo** |
| [#37](../todos/smt-divergence-po3.md) | SMT Divergence + PO3 | `EA_CF_SMT_PO3.mq5` | 3203 | M5 | `SigSweepReclaim` + direct symbol-vs-symbol SMT divergence (NQ vs ES) and the 50%-level target |
| [#31](../todos/po3-ote-adr.md) | PO3, OTE + ADR | `EA_CF_PO3_OTE_ADR.mq5` | 3204 | M15 | PD-array proximity, daily bias, ADR budget, **fib-anchored OTE limit** (stop 1.0 fib, target 0.0 fib → fixed R by geometry) |
| [#07](../todos/break-retest.md) | Break & Retest | `EA_CF_Break_Retest.mq5` | 3205 | M5 | `SigBreakRetest` + rejection-wick confirmation + no-trade-zone gate |
| [#16](../todos/intraday-liquidity-volatility-model.md) | Intraday Liquidity & Volatility | `EA_CF_Intraday_Liquidity.mq5` | 3206 | M5 | failed-raid detector over PDH/PDL, Asian and London extremes + `SigFvgRetest` (MSS fallback), NY window |

## Wave 2

| Card | Strategy | EA | Magic | TF | Reads from the engine |
|---|---|---|---|---|---|
| [#02](../todos/80-20-nasdaq-strategy.md) | 80/20 Nasdaq | `EA_CF_8020NasdaqStrategy.mq5` | 3208 | M3 (structure M10) | NASDAQ mean reversion at price levels ending in 80/20 (`EA_Rates` + candle maths, no indicator at all): fork long, H-pattern short, cross-section retest, repair-candle magnet targets; fixed 10-point stop / 15-point TP1 (half off, break-even, runners); NY-open window with the lunch hour excluded; **no daily trade cap** (the source trades conditionally) |
| [#03](../todos/algorithmic-strategy.md) | Algorithmic Strategy | `EA_CF_AlgoPortfolioMonitor.mq5` | 3209 | - | **Monitor, never trades.** The video is a process document (build + rank + monitor algorithms), so the EA applies its ranking filters to the account's own deal history per magic: profit factor, return/DD, trades per month, average loss band, implied allocation 5-25%, drawdown past 20-25%, expectancy. One row per algorithm per scan in `MQL5/Files/cf_algo_ranking.csv` |
| [#05](../todos/auction-market-strategy.md) | Auction Market | `EA_CF_AuctionMarket.mq5` | 3210 | M5 | Market state -> LVN (tick-volume profile) -> aggression. Trend model: impulse-leg LVN pullback, stop beyond the print, previous-balance POC/extension. Mean-reversion model: failed auction outside value -> reclaim -> reclaim-leg LVN -> POC. Risk 0.40% (the playbook's 0.25-0.5% band) |
| [#06](../todos/auction-market-theory-strategy.md) | Auction Market Theory | `EA_CF_AuctionMarketTheory.mq5` | 3211 | M5 | Value area from a tick-volume profile: failed auctions at VAL/VAH -> rotation to POC, accepted opening-range breakouts (body, not wick), and a custom `Manage()` that exits when the opposing side closes back through value while the trade is in profit - the playbook's own order-flow exit |
| [#09](../todos/fair-pricing-theory-strategy.md) | Fair Pricing Theory | `EA_CF_FairPricingTheory.mq5` | 3213 | M1 | Displacement-candle continuation, break-of-structure continuation, and reversions of unfair displacements back to fair price (previous close / session open). Static R:R with **TP first, stop = TP/ratio** (1:1.5 evaluation default, 1:4 via input for funded), three-loss session rule, and only the three 90-minute session windows |
| [#08](../todos/episodic-pivot-strategy.md) | Episodic Pivot | `EA_CF_EpisodicPivot.mq5` | 3212 | M5 | Neglect + catalyst-footprint + repricing: day-1 opening-range break (stop below the OR low), EP 9M (real share volume where published), delayed reaction long (post-catalyst range breakout) and short (negative-catalyst bounce failure); custom Manage() trails under the daily lows |
| [#10](../todos/first-red-day.md) | First Red Day | `EA_CF_FirstRedDay.mq5` | 3214 | M5 | Short-only: 3+ day green run, entry on the first close below the previous day's close (gap-up fade or gap-down bounce failure), stop just above the line, partials into the weakness, runner kept |
| [#11](../todos/first-red-day-strategy.md) | First Red Day Strategy | `EA_CF_FirstRedDayPro.mq5` | 3215 | M5 | The fuller FRD spec: non-negotiable minimum criteria (no red day, 80-100%+ extension, expanding volume/range) then three selectable entry methods - pre-red stall, standard crack below the prior close, failed lower high - each risking the level the playbook names; never shorts an overextended gap down (-10%+); VWAP magnet target with the 2-3% fallback, scale-out plus optional 15-min-high trail via a custom `Manage()` |
| [#12](../todos/full-psychology-masterclass.md) | Psychology MasterClass | `EA_CF_PsychGuardrails.mq5` | 3216 | M15 | **Monitor, never trades.** Replays the account's own day (every magic) through the progressive-shutdown ladder - caution at 1 loss, the doc's 15-minute break at 2, session over if the break is broken or on the 3rd loss - with the emotional-carryover shift after a red day and mechanical proxies for the zone-map signs (revenge re-entry, size escalation, entry bursts, off-window trades); journals pre/during/post to `cf_psych_journal.csv` |
| [#13](../todos/futures-trading-strategy.md) | Futures Trading Strategy | `EA_CF_FuturesStrategy.mq5` | 3217 | M30 | **Environment first.** Daily Bollinger 20/3s bandwidth classifies consolidation / expansion / mean reversion, then: two-way edge trades at the range edges, one-directional expansion breakouts with the "unfinished business" band-peak and week-level targets, and the doc's 30%-line daily trigger to the 50% line (smaller size counter-trend, hands in pocket after 50%); structural daily-swing stops (skip when unrealistically wide - the doc's "use options" rule), 8/21/34 + anchored-VWAP exits, 1-5 day hold |
| [#14](../todos/institutional-options-flow-gamma-reversal-strategy.md) | Institutional Options Flow & Gamma Reversal | `EA_CF_GammaReversal.mq5` | 3218 | M1 | Wall reversals: price taps the put/call wall the trader reads off the options platform (the video's own action item) and the M1 bar rejects with an above-average-volume confirmation; stop 40 ticks beyond the wall, target the next listed gamma level; dollar-risk sizing ($150-200), 1-2 setups/day, flat when the first-two-hours window closes, OPEX/triple-witching/spiration calendar gates and the doc's "2 days off after a stop loss" enforced in `AllowTrading()` |
| [#15](../todos/institutional-strategy-development-framework.md) | Institutional Strategy Development Framework | `EA_CF_InstFramework.mq5` | 3219 | M1 | The pipeline, carried into code: three of the document's strategies as modes - ORB (long-only break of the 9:30-10:00 range, stop at the range low, 1:1/1:2 target, 3:30 p.m. time exit), VWOP momentum (1-minute close above/below the volume-weighted price, exit on the cross, open or prior-close anchor), overnight gap premium (long 4 p.m., exit 9:30 a.m.) - plus volatility targeting to a constant dollar risk, the validated-drawdown pause, and an account-wide monthly review that names underperformers. **PEAD is disclosed as data-blocked** (no earnings feed in MT5) |
| [#17](../todos/liquidity-inversion-model.md) | Liquidity Inversion Model | `EA_CF_LiquidityInversion.mq5` | 3220 | M5 | ICT multi-timeframe reversal, day and swing in one EA: a daily wick sweeps the prior weekly (preferred: monthly) extreme and closes back inside, the reaction leaves a 4-hour fair value gap, that gap's **inversion** (displacement close plus a retest that holds the new side) is the confirmation, then a 15m counter-trend gap is inverted on the 5m as the market-execution entry (swings enter off H1/H4 only). Stop beyond the 15m high/low with an ATR buffer (H4 structure for swings), target prior sellside/buyside liquidity (previous day, the 9:30 NY open, unfilled HTF gaps) at a >= 1.5R floor, trim 50% at 1R + break-even + runner trail (swings skip the micro-management), half size in high-volatility regimes, trade only after the 10:00 ET open, and the doc's two-consecutive-loss day stop tracked in class state (the engine's day lock counts today's losers, not the streak) |

`[interpretation]` for card #02 (the source is a video summary, not a rule sheet):

* the **200-second entry chart is not a MetaTrader timeframe** — M3 (180 s) is the closest and is a
  visible input; the 10-minute structure timeframe is exact;
* the fork's **"targeting the previous low"** reads oddly for a long, so the fixed 10-point stop and
  15-point first target the same document states are used, and the fork low stays the structural
  reference;
* **cross-sections are direction-neutral** in the source ("depending on market structure"), so the
  retest side (from above → long, from below → short) plus the 80/20 confluence decides;
* **position size**: the source sizes up by feel; the EA keeps constant *point* risk via the engine's
  percent sizing, which is the mechanical equivalent of "static in points".

Magic block **3201–3247** is reserved for this family (one per card). `manifest.json` is the
machine-readable source of truth and is read by [`../gen_todos.py`](../gen_todos.py) to fill each
card's Tracking block.

### Engine utilities these EAs lean on

Nothing here re-implements what `MQL5_Master/Include/` already provides:

| Engine utility | Used for | Where |
|---|---|---|
| `SigSweepReclaim` | range sweep → reclaim → displacement → retrace entry | AMD, SMT+PO3, Structure+OTE (breaker) |
| `SigOrderBlockRetest` | POI entry with a direction lock (`onlyDir`) | Structure+OTE |
| `SigFvgRetest` | imbalance retest entry | Intraday Liquidity |
| `SigBreakRetest` | accepted break + later retest bar | Break & Retest |
| `SigEmaCascade` | D1/H1/HTF bias and clarity gates | AMD, Structure+OTE |
| `SigRangeForDay` / `SigPrevSessionRange` / `SigAsianRange` | session windows and previous-day levels | all six |
| `SigFractals` | swing structure: engineered liquidity (Structure+OTE) and the manipulation anchor (PO3) | Structure+OTE, PO3 |
| `SigTwoBarReversal` | pin + engulf confirmation ("rejection / engulfing") | Break & Retest |
| `EA_InWindow` | every session/macro window (midnight-crossing safe, London clock) | AMD, PO3, SMT+PO3 |
| `EA_WickRatio` / `EA_BodyRatio` / `EA_Rates` / `EA_Buf` | candle and series maths | all six |
| `cfg.maxCostR` + `EA_CostInR` | all-in cost gate: reject a setup when (spread + commission) > xR | all six |
| `cfg.ledgerEnabled` / `ledgerFile` | engine evidence ledger, one CSV row per open / partial / close | all six |
| `RiskGovernor` (`dailyLossPct`, `maxTradesPerDay`, `dayLockAfterLosses`, HWM tiers) | the playbooks' daily discipline rules | all six |
| `EA_ApplyStagePolicy` (engine helper, **added for card #01**) | per-stage risk posture from the 5-Stage framework: stage 1 quarter risk + 1 trade/day + day locked after the first win, stage 2 half risk, stage 3 three-quarter risk + 24h streak pause, stage 4 HWM throttle + 12h streak pause, **stage 5 = no-op**. Tightens only, never raises a cap, inert with static lots | all six playbook EAs via `InpStage` (default 5 = off); the guardrail EA reads the same table |

Deliberately **not** used: `SigSessionFade` (EASignals 14) fades a quiet range only in the three
hours *after* that range closes — the 02:00–05:00 ET window — while the Intraday Liquidity model
trades 09:30–11:30 ET; `EA_BasketShouldAddLeg`/`EA_BasketManage` implement *adverse* grid legs, not
the playbooks' "scale in only once the first entry is at break-even", which stays unimplemented.

## Rule -> code sync

Each playbook was read end to end and every stated number/rule was mapped to the line that
implements it. `tests/test_chartfanatics_sync.py` holds that mapping as a table of
`(regex, rule-quoted-from-the-pdf)` pairs — one per rule — and asserts all of them against the
sources, so a changed threshold or a dropped gate fails the test suite instead of silently
drifting away from the document. The same file asserts that every deliberate deviation stays
labelled `[interpretation]` in the EA.

Documented deviations (the playbook is silent or self-contradictory — the code follows the
unambiguous geometry and says so):

| EA | Playbook text | What the code does |
|---|---|---|
| `EA_CF_PO3_OTE_ADR` | R table printed on p.4 ("62 % = ~2.38R, 70.5 % = ~3.75R, 50 % = ~1.63R") contradicts the fib geometry on the same page | R is **derived** (`tpR = entryFib / (stopFib - entryFib)`), which yields 1.63R / 2.39R / 3.76R for 0.62 / 0.705 / 0.79 — the table's labels are shifted one row; the discrepancy is noted in the source. Stop levels 1.0 (default) and 0.90 (tighter option) are both inputs |
| `EA_CF_PO3_OTE_ADR` | "ADR" appears only in the document title — the body states no ADR rule | The daily-range budget gate is marked `[interpretation]` (ADR ~ daily ATR) and is an input |
| `EA_CF_Structure_OTE` | names OTE but prints no fib numbers | 62–79 % band, labelled `[interpretation]` |
| `EA_CF_SMT_PO3` | "the 11:00 candle flips bearish -> break-even" | engine 1R break-even; the target (50 % of the range) is used only when it sits ahead of the entry |
| `EA_CF_AMD_Model` | "high probability day" (CPI/NFP/FOMC) | calendar data is tester-incomplete, so the news gate is off |
| `EA_CF_AMD_Model` | "make sure related markets (e.g., NASDAQ and S&P) are aligned" — no threshold given | `InpCorrelationSymbol` (default `US500`): both markets must sit on the same side of their own previous-day midpoint |
| `EA_CF_Intraday_Liquidity` | "if the trade slows near midday, consider exiting" | engine time stop, 90 minutes unless the trade is already at 1R |

### Bugs found by this audit (all fixed)

| Where | Bug | Fix |
|---|---|---|
| `EA_CF_SMT_PO3` | two `OnInitStrategy()` bodies from the stage-policy wiring — a hard compile error | merged into one; `check_mql5_source.py` now also flags duplicate class members (signature = name + param types, overloads stay legal) |
| `EA_CF_PO3_OTE_ADR` | fractal anchor could sit at index `got`, so the displacement loop read `r[manipIdx]` **out of bounds** (MQL5 aborts the run) | anchor clamped to the fetched series; loop bounded by `i + 1 < got` |
| `EA_CF_PO3_OTE_ADR` | displacement only had to beat the previous bar's extreme, not close "past the key level" | the close must also clear the raided PD array (`pdh` / `pdl`) |
| `EA_CF_PO3_OTE_ADR` | R targets hardcoded 1.70 / 2.39 (did not follow the inputs at all) | derived from geometry; `InpStopFibLevel` added; `InpMinRR` 2.00 -> 1.50 so the doc's own 0.62 entry (1.63R) can qualify |
| `EA_CF_PO3_OTE_ADR` | a resting OTE limit was returned even when the market had already run through it | refuses when `ask <= entry` (short) / `bid >= entry` (long) |
| `EA_CF_PO3_OTE_ADR` | `NearKeyLevel()` had two identical branches (both read `pdh`) | side-specific, per the playbook's raid example |
| `EA_CF_SMT_PO3` | the twin's bars were compared by index without checking they were the *same* bars | `a[i].time != b[i].time` -> unavailable (fail-closed default, warn once) |
| `EA_CF_Intraday_Liquidity` | the raid detector returned the *first* level hit, so an older raid masked a fresher one | returns the most recent raid (`bestBar`) |
| `EA_CF_Break_Retest` | the two-bar reversal confirmation was used for retests that did not close on the last bar, but the engine detector only reads the last closed bar | gated on `barsAgo == 1` |
| `EA_CF_Structure_OTE` | "engineered liquidity" could be a swing created *after* the sweep | requires the swing index to be older than the sweep bar |
| `EA_CF_AMD_Model` | "related markets aligned" and "there must be a clear target" were stated in the playbook but not implemented | correlation gate added; the worked example's target (opposite side of the accumulation range, then the nearest clean swing) now overrides the R target when it is far enough |
| `EA_CF_Break_Retest` | the playbook's TP1 ("the prior high / prior low") was implemented as a flat R target | nearest swing extreme ahead of the entry sets TP1, R stays the fallback |
| `EA_CF_Intraday_Liquidity` | the playbook lists four confirmations (FVG, MSS, Turtle Soup, breaker block); only two were implemented | breaker-block path added via `SigOrderBlockRetest`; Turtle Soup *is* the failed raid the detector already requires |

## Deploy

Each EA includes `..\..\Include\EACommon.mqh`, so the folder has to sit at
`MQL5\Experts\chartfanatics\`:

```powershell
# copy the family into the terminal
$dst = "C:\Users\you\AppData\Roaming\MetaQuotes\Terminal\<ID>\MQL5\Experts\chartfanatics"
New-Item -ItemType Directory -Force $dst | Out-Null
Copy-Item chartfanatics\mql5-eas\*.mq5 $dst

# the shared headers must be in MQL5\Include\ (the 65 EAs need them too)
Copy-Item MQL5_Master\Include\*.mqh "C:\Users\you\AppData\Roaming\MetaQuotes\Terminal\<ID>\MQL5\Include\"
```

Then compile everything, including this family, with the harness:

```powershell
.\validation\mt5_harness\compile_all.ps1 -Mql5 "C:\Users\you\AppData\Roaming\MetaQuotes\Terminal\<ID>\MQL5"
```

`compile_all.ps1` picks up `Experts\chartfanatics\*.mq5` automatically; an EA that fails to compile
produces no result row in the tester sweep that follows.

## Known gaps (do not paper over these)

* **Never compiled.** Static checks are not a compiler.
* **Symbol universes are broker-dependent.** The defaults assume the names this repository already
  uses elsewhere (`US100`, `US500`, `GER40`); other brokers call NQ `NAS100`/`USTEC`. The engine
  logs and skips symbols the broker does not offer — check the Experts log after first run.
* **SMT needs its twin.** `EA_CF_SMT_PO3` compares `InpSymbolsToTrade` with `InpSmtSymbol`
  (default `US500` for a `US100` leg). Without that symbol the divergence gate fails open by
  default and logs loudly; `InpSmtFailClosed=true` refuses to trade instead.
* **News-day quality is not encoded.** The AMD playbook's "high probability day" filter is a
  calendar decision (CPI/NFP/FOMC days) and the repo's calendar is tester-incomplete; the news
  filter is therefore off.
* **Scale-in rules are off.** The PO3/AMD models scale only once the first entry is at break-even;
  the engine holds one position per symbol, so those additions are not implemented.

Next waves: cards with no EA yet are listed on [`../TODO.md`](../TODO.md) — a card gets an EA entry
here once its source rules are read and mapped, never before.
