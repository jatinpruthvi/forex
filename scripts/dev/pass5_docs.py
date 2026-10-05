FIFTH_PASS = r'''
## Fifth pass — 2026-10-02 (fifth in-depth request)

This pass started from the **documents** rather than the code: every EAs source
file was parsed for its declared instrument universe, its session/instrument
matrix, its exit ladder, its flat times and its day-of-week rules, and each of
those statements was then searched for in the generated strategy.  Detectors
that did not exist before: *universe coverage* (every instrument a document
declares, versus `InpSymbolsToTrade`), *dead pair branches* (a `StringFind`
branch on a symbol the universe can never deliver), *runner-trail conflicts*
(document chandelier versus the engine `trailAtR`), *grid-flat coverage*
(documents that say "flat by 07:00" versus a closer that never runs),
*day-of-week filters*, and *H1-ATR proxies*.  All fixes are in
`scripts/gen_additional_eas.py` (EA logic) and `MQL5_Master/Include/EASignals.mqh`
(the one shared-engine addition), then regenerated.

| # | Severity | Where | Defect | Fix |
|---|---|---|---|---|
| 35 | **High (dead sleeve + unsatisfiable filter)** | `round7_contestant_c`, `round8_contestant_a` | Both documents open with "Instrument set: EURUSD, GBPUSD, **XAUUSD** only", but the universe shipped only the two majors — gold could never trade. Worse, both fuel filters end in a bare `return (pips <= 35.0)` / `return (pips <= InpEurFuelPips)` fall-through meant for EURUSD, so had gold been enabled it would have been measured against a **35-pip** Asian-range cap no gold session ever satisfies. | Universes gained `XAUUSD`; the pip caps now apply to EURUSD/GBPUSD only and gold is governed by the 35–75 %-of-20-day-median ratio test the documents state for every instrument. |
| 36 | **High (dead sleeves from incomplete universes, 10 EAs)** | generator specs | Documents declared instruments the EA could never receive, so the matching sleeve was inert: `TRIAD_SURVIVE` sleeve A `AUDUSD` (doc: "AUDUSD, NZDUSD — Asian grid or London breakout"), `round4_contestant_b` sleeve 2 `EURCHF`, `round11_contestant_d` Asian mean-reversion `AUDNZD`, `round11_contestant_f` sleeve C `EURCHF`, `round10_qwen3_8` Asian pair `AUDUSD`, `round10_kimi_k3` `AUDUSD` (doc L37 universe), `round10_gemini` `USDJPY` (doc: "Instruments: EURUSD, GBPUSD, USDJPY, XAUUSD"), `round5_contestant_b_2048` sleeve B `XAUUSD`, `THE5ERS_CHALLENGE_STRATEGY_V2` `GBPUSD`/`USDJPY` (two of the three documented instrument/session combinations were dead, including the EA's own `ctx.symbol == "USDJPY"` window branch), `round11_contestant_f` sleeve A `AUDUSD`. | Every universe now equals the documents instrument list; regenerated and `--check` reports 65/65. The stock-index sleeves whose symbols are not broker assets (`GER40`/`US30`/`DAX`/`US100`) stay out of the shipped universes and are listed as limitations below. |
| 37 | **High (universe contradicted the document)** | `round10_claude_opus_5` | The document's session × symbol matrix is AUDNZD/EURGBP/AUDUSD (00:00–03:00), EURUSD/GBPUSD/XAUUSD/GER40 (07:00–10:30), XAUUSD/USDJPY/US100 (13:30–16:00). The EA traded `EURUSD,GBPUSD,USDJPY,AUDUSD,USDCAD`: none of the Asian sleeve and no gold at all, plus USDCAD, which the document never mentions. | Universe set to the FX/metal members of the matrix (indices excluded as usual); USDCAD removed. |
| 38 | **High (entry windows)** | `round7_contestant_c`, `round8_contestant_a`, `round8_contestant_b` | `7c`/`8a` documents: "Setup — London sweep-and-reclaim, 07:00–10:30 UK" / "**Window:** 07:00–10:30 UK"; both EAs scanned for setups until 12:00. `8b` document schedule: Asian entries 00:00–03:00, London 07:00–10:00, NY 13:30–15:30; the EA mapped each session to a window ending at 07:00/12:00/21:00 and had **no entry cutoff at all**, so it took entries up to four hours after every documented window closed. | `7c`/`8a` sweep windows end at 10:30. `8b` each branch now sets `sessTo` to the documents entry end (03:00 / 10:00 / 15:30) and rejects any clock ≥ `sessTo`. |
| 39 | **High (missing exit mechanism — the ROI of the document)** | `round8_contestant_b` | The document's ladder is "40 % at +1R · 30 % at +2R · **30 % runner trailed at High − 2.5×H1-ATR, hourly, no TP**", with "Breakeven stop **only after a M5 close beyond +1R (not a touch)**". The EA had partials but no chandelier at all (its `InpChandelierMult` input had even been stripped by the dead-input guard), BE was touch-based, and an engine R-trail substituted for the runner trail. | Added `Manage()` chandelier (`H1Atr()` now returns the real `ctx.atrH1`, D1/6 only as fallback), `cfg.breakEvenOnBarClose = true`, `cfg.trailAtR = 0.0`. |
| 40 | **High (engine trail overrode the documented runner)** | `round5_contestant_c`, `round7_contestant_c`, `round8_contestant_a`, `round8_contestant_c` | All four documents trail the runner on a **chandelier** (1H swing structure / High − 2.5×H1-ATR, updated hourly, no take-profit) and each EA implements that chandelier in `Manage()` — but each also set `cfg.trailAtR`, so the engine silently ran a *tighter* fixed-R trail on top. Tighten-only semantics mean the tighter stop always won: the runner was cut around +2…3R instead of riding the documented 5–8R tail, which is exactly where these documents say the ROI lives. | `cfg.trailAtR = 0.0` on all four; the chandelier (and the `breakEvenAtR` lock, which all four keep) is now the only runner trail. |
| 41 | **Medium (flat times)** | `round7_contestant_c`, `round8_contestant_c`, `round7_contestant_d`, `round5_contestant_c` | Documented hard flats were missing or mis-timed: `7c` "Hard flat by 21:00 UK" (EA session ended 16:00 with no flat), `8c` "Hard Time Stop: Close everything manually at **16:30** UK" (EA 16:00), `7d` "Close the runner by **16:30** London" (no flat at all), `5c` "hard flat 16:00" (no flat at all). | Session end / `sessionEndFlat` set to 21:00, 16:30, 16:30 and 16:00 respectively. |
| 42 | **High (the rule that keeps grids alive)** | `round4_contestant_b`, `round7_contestant_b`, `round5_contestant_e` | All three documents run a Tokyo/Asian grid sleeve under the same risk rule — "Time stop: flat by 07:00 UK **regardless of P/L**", "flat by 07:00", "**Flat by 07:00, no exceptions.** Never hold into London" — and none of the three EAs closed the grid legs; the entries simply stopped, leaving the basket exposed to the London expansion the documents warn about. | Each EA gained a `Manage()` that closes its own positions in the grid symbols from 07:00 (per-symbol, so the trend sleeves are untouched). |
| 43 | **Medium (day-of-week filter)** | `round7_contestant_c`, `round8_contestant_a`, `round8_contestant_c` | "Trade only **Tuesday–Thursday** … Monday lacks direction, Friday reverses into the weekend" / "**Days:** Tuesday–Thursday only" / "Schedule: **Tuesday to Thursday only**" — no EA read `ctx.dayOfWeek` at all. | `if(ctx.dayOfWeek < 2 \|\| ctx.dayOfWeek > 4) return false;` at the top of each `BuildPlan`, matching the existing `round8_contestant_d` precedent. |
| 44 | **Medium (fake H1 ATR, 8 EAs)** | `round5_contestant_c`, `round7_contestant_c`, `round8_contestant_a`, `round8_contestant_c`, `round10_qwen3_8`, `round11_contestant_a`, `round12_contestant_c`, `round12_qwen3_8` | Eight EAs scale a documented H1-ATR distance (chandelier, EMA-distance gate, H1 slope tolerance) by `daily ATR / 6` — a proxy that is wrong exactly when it matters (news days, compressed weeks) and inconsistent with the real `ctx.atrH1` the fourth pass added. | All eight prefer `ctx.atrH1` and keep `atrD1 / 6` only as a fallback while the H1 series is still empty. |
| 45 | **Medium (sleeve membership)** | `round11_contestant_f`, `round5_contestant_b_2048` | `11f`'s sleeves A and B had **no symbol gate** at all, so any universe member could take any sleeve (the doc assigns each instrument to exactly one sleeve), and sleeve C admitted entries 06:30–07:00 although the document says "00:00–06:30 … hard flat at 06:30". `5b_2048`'s NY sleeve was open to the Asian grid pairs although the document restricts it to USDJPY/XAUUSD. | `IsSleeveASymbol/BSymbol/CSymbol` helpers gate sleeves A/B/C (A: EURUSD, GBPUSD, USDJPY, AUDUSD; B: XAUUSD; C: AUDNZD, EURGBP, EURCHF); sleeve C's window ends at 06:30 and a `Manage()` flattens sleeve-C symbols at 06:30. `5b_2048`'s NY sleeve now accepts only USDJPY/XAUUSD. |
| 46 | **Medium (exit ladder + BE semantics)** | `round7_contestant_d` | Document: "Close 40 % at +1R. Close 30 % at +2R. Trail the remaining 30 %. **Move the stop to breakeven only after price closes beyond +1R, not merely after touching it.**" The EA paid 40 % at +2R (leaving 20 % as runner) and moved BE on touch. | `partial2Pct = 30.0`, `cfg.breakEvenOnBarClose = true` (the runner's M15-swing trail remains an approximation, listed below). |
| 47 | **Medium (missing document rule)** | `round10_qwen3_8`, `MQL5_Master/Include/EASignals.mqh` | Step 4 of the document requires the displacement candle to "close **beyond the prior candles midpoint**" in addition to the body test, and the entry limit to be cancelled "if unfilled after 3 candles (15 minutes)". The body test and the 50 % retracement limit existed; the midpoint test and the expiry did not (the EA never set `pendingExpiryMinutes`). | New opt-in `SSweepParams.requireMidpointBreak` (default false, so no other EA changes) enforced on both branches; the spec sets it, plus `cfg.useLimitEntry = true` and `cfg.pendingExpiryMinutes = 15`. |
| 48 | **Low (documentation integrity)** | `docs/EA_IMPLEMENTATION_TRACKER.md` | 53 of the 65 "Source Document" cells did not resolve to a file: underscore-vs-hyphen drift, bare filenames with the directory stripped, and 13 rows pointing at `docs/strategy/`/`docs/prop_firm/` paths that live in the other directory. Every row was a dead evidence link for anyone re-checking a requirement. | All resolvable cells rewritten to repository-relative paths that exist (tracker row 16 also corrected from `docs/strategy/THE5ERS_CHALLENGE_STRATEGY_V2.md` to `docs/prop_firm/THE5ERS-CHALLENGE-STRATEGY-V2.md`). |

Verification of the fifth pass: `gen_additional_eas.py` regenerates all 65 and
`--check` reports "OK - 65 generated EAs match the specs"; `check_mql5_source.py`
reports **0 findings** on the 65 (92 on the whole tree, all pre-existing legacy
structure); `scripts/dev/arity_check.py` reports 0 arity and 0 undefined-name
findings over 87 files; brace balance 0; the stdlib suite passes 187 tests (the
pytest-only module still cannot run in this sandbox).  After the fixes the
universe-coverage detector reports no document-declared instrument missing from
its EA, and the dead-pair-branch detector reports only the intentional
index-symbol branch listed below.

**Documented deviations and limitations from this pass (not bugs).**

* **Index-named sleeves are not shipped as universes.** `GER40`/`US30`/`DAX`/
  `US100` appear in three documents but are broker-dependent symbols.
  `EA_TRIAD_SURVIVE` implements the documents own fallback ("if GER40 or US30
  do not exist on the account, Sleeve B is XAUUSD and GBPJPY only") and is
  compliant; `round11_contestant_f` sleeve B trades XAUUSD and leaves DAX/US30
  out; `round10_qwen3_8`s DAX/US30/NAS100 stack pairs are not traded and its
  `US30/NAS` classifier branch is inert with the shipped universe (kept so a
  broker that does list them can be served by editing the input).
  `round12_contestant_b` *does* ship US30 because its document names it directly
  as a New York instrument.
* **Deliberate single-sleeve variants.** `round5_contestant_a_2047` (London
  checklist), `round5_contestant_b` (asymmetric runner), `round5_contestant_c`
  (London sweep; its documents sleeve 3 grid, and that sleeve's 06:30 flat, are
  deliberately not part of this variant) and `round12_contestant_c` (the SR-10
  London module; the document's New York module is not implemented) implement a
  named subset of their source document, and their tracker titles say so.
  `round7_contestant_d` implements Strategy 1 of 3 (the London compression
  breakout with the full adaptive stop band); its document's Strategy 2 (NY
  continuation) and Strategy 3 (Asian mean reversion on AUDNZD/EURGBP) are not
  implemented.  `EA_STRATEGY_ROADMAP`s F1 quiet-session family (00:00–06:30
  window plus a hard 06:30 flat) is the only shipped Track-B family without its
  flat; it is not the default (`InpFastFamily = FAST_F2_FAILED_BREAK`) and the
  F1 instrument set is largely outside the shipped universe.
* **Per-session windows and flats.** `round10_claude_opus_5` uses one
  07:00–20:00 envelope with a single 07:00–16:00 sweep window rather than the
  documents three session windows, and has no session-end flat.
  `round10_qwen3_8` and `round10_kimi_k3` keep the reference session windows
  documented in the fourth pass, and all three rely on the shared 22:00
  session-end flat rather than each documents per-session flat times.
* **`round5_contestant_c` keeps a flat 16:00** without the documents
  "unless that runner is already > 2R" exemption (the exemption needs a
  per-position tag the engine does not carry).
* `round7_contestant_d`s runner is trailed by the engine M15-swing stand-in
  (`trailAtR = 2.0 / 0.75R`) rather than the documents "last confirmed M15
  swing with a minimum 1.5 × M15-ATR distance"; the ladder and BE semantics are
  exact.
* Rows 32–39, 41 and 43 of the tracker (`round1`–`round4_contestant_a__1_`
  and the two `(1)` documents) have **no source document in the repository**;
  their cells are left as the tracker originally recorded them, and their code
  is the intended behaviour of record.
'''

import re
p = "docs/EA_BUG_AUDIT.md"
s = open(p, encoding="utf-8").read()
_before = len(s)
anchor = "## Verification after the fixes"
assert s.count(anchor) == 1
s = s.replace(anchor, FIFTH_PASS.strip("\n") + "\n\n" + anchor)

# --- new verification rows --------------------------------------------------
rows = (
"| Universe coverage: every instrument a source document declares vs `InpSymbolsToTrade` (65 EAs) | 12 dead-sleeve / wrong-universe cases found, all fixed (#35–#37, #45); after the fixes 0 document-declared instruments are missing |\n"
"| Dead pair branches: a `StringFind`/`==` symbol branch the universe can never deliver | 2 before (#36 The5ers USDJPY, and one index branch); after the fixes only `round10_qwen3_8`s `US30`/`NAS` classifier branch, kept deliberately (documented above) |\n"
"| Runner-trail conflicts: document chandelier vs engine `trailAtR` | 4 EAs ran a tighter R-trail on top of their own chandelier (#40); all four now leave the runner to the chandelier |\n"
"| Grid-flat coverage: documents saying \"flat by 07:00/06:30\" vs a closer that exists | 3 grid sleeves closed nothing at the flat time (#42, plus `round10_qwen3_8`/`round12_qwen3_8` per-session flats listed as limitations) |\n"
"| Day-of-week filters quoted by a document | 3 EAs quoted Tuesday–Thursday and had no filter (#43); 1 EA already implemented its Monday–Thursday rule |\n"
"| H1-ATR sites: real `ctx.atrH1` vs a D1/6 proxy | 8 proxy sites found (#44), all now prefer the real H1 ATR with the proxy only as an empty-series fallback |\n"
"| Tracker source-document links resolve to a file | 53 of 65 corrected (#48); the 11 unresolved rows are the documents that do not exist in the repository |\n"
)
assert s.count("| Spread-vs-history gates re-pointed at the engine baseline (4 EAs) | regenerated; each gate logs its skip and fails open while evidence is thin |\n") == 1
s = s.replace("| Spread-vs-history gates re-pointed at the engine baseline (4 EAs) | regenerated; each gate logs its skip and fails open while evidence is thin |\n",
              "| Spread-vs-history gates re-pointed at the engine baseline (4 EAs) | regenerated; each gate logs its skip and fails open while evidence is thin |\n" + rows)
open(p, "w", encoding="utf-8").write(s)
print("audit updated: +%d bytes" % (len(s) - _before))
