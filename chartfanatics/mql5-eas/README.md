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
| [#26](../todos/structure-ote.md) | Structure + OTE | `EA_CF_Structure_OTE.mq5` | 3202 | M15 | `SigOrderBlockRetest` (POI) + breaker fallback, **first premium/discount + OTE (62–79%) implementation in the repo** |
| [#23](../todos/smt-divergence-po3.md) | SMT Divergence + PO3 | `EA_CF_SMT_PO3.mq5` | 3203 | M5 | `SigSweepReclaim` + direct symbol-vs-symbol SMT divergence (NQ vs ES) and the 50%-level target |
| [#22](../todos/po3-ote-adr.md) | PO3, OTE + ADR | `EA_CF_PO3_OTE_ADR.mq5` | 3204 | M15 | PD-array proximity, daily bias, ADR budget, **fib-anchored OTE limit** (stop 1.0 fib, target 0.0 fib → fixed R by geometry) |
| [#07](../todos/break-retest.md) | Break & Retest | `EA_CF_Break_Retest.mq5` | 3205 | M5 | `SigBreakRetest` + rejection-wick confirmation + no-trade-zone gate |
| [#12](../todos/intraday-liquidity-volatility-model.md) | Intraday Liquidity & Volatility | `EA_CF_Intraday_Liquidity.mq5` | 3206 | M5 | failed-raid detector over PDH/PDL, Asian and London extremes + `SigFvgRetest` (MSS fallback), NY window |

## Wave 2

| Card | Strategy | EA | Magic | TF | Reads from the engine |
|---|---|---|---|---|---|
| [#02](../todos/80-20-nasdaq-strategy.md) | 80/20 Nasdaq | `EA_CF_8020NasdaqStrategy.mq5` | 3208 | M3 (structure M10) | NASDAQ mean reversion at price levels ending in 80/20 (`EA_Rates` + candle maths, no indicator at all): fork long, H-pattern short, cross-section retest, repair-candle magnet targets; fixed 10-point stop / 15-point TP1 (half off, break-even, runners); NY-open window with the lunch hour excluded; **no daily trade cap** (the source trades conditionally) |

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
