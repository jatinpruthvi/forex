SIXTH = r'''
## Sixth pass — 2026-10-02 (sixth in-depth request)

The fifth pass swept documents for *missing* rules. This pass swept for
**code that exists but does nothing**, and for **exit semantics** - the one
family the earlier passes had only spot-checked (they fixed three sites:
`round8_contestant_b`, `round7_contestant_d`, `round10_claude_fable_5`). New
detectors: dead EA-local helpers, inputs referenced only inside comments,
`ctx.index` guards, track-table mutation inside forward loops, clock/offset
wiring, outer-vs-inner session consistency, sleeve-accounting tags, and - the
one that paid - **every documented "X % at +NR" ladder and every documented
break-even qualifier**, compared with the rendered `cfg.partialN*` /
`cfg.breakEven*` configuration.

| # | Severity | Where | Defect | Fix |
|---|---|---|---|---|
| 52 | **Medium (wrong instruments in two sleeves)** | `round4_contestant_b` | The document assigns instruments per sleeve and per session. The EA gated the Tokyo grid but the London-open, London-mid and NY sleeves accepted **any** universe member, so e.g. a USDCHF could take the London sweep or the VWAP fade, and the pair the document assigns to the VWAP fade (USDCAD) could take the NY continuation. A helper with exactly the documented sleeve-1 list (`IsLondonPair(value)`) existed but was **never called**. | `IsLondonPair` is now the London-open gate (GBPUSD, EURUSD, XAUUSD) and a new `IsNySleevePair` gates the 13:30-16:00 branch (XAUUSD, USDJPY). GBPJPY and USDCAD are deliberately excluded with comments: their documented triggers (momentum break with no retest wait; the WTI-divergence fade) are not implemented, so the pairs are left out instead of being traded with the wrong trigger. |
| 53 | **Low (dead code)** | `round12_contestant_b` | `RangeBetween(value)` was defined and never called. Unlike 7c/8a there is no range-quality rule anywhere in this document, so it was leftover code - and dead code that *looks* like a rule is a traceability trap. | Removed. |
| 54 | **Low (declared lever never wired)** | `round4_contestant_c__1_` | The class documents "Lever 3: end-of-month liquidity harvest bias" and implements `EndOfMonthWindow()` (last day / first two days of the month) - which nothing ever called. This file has no source document in the repository, so its own comments are the specification of record. | Wired as a **rank bonus** (`+5` score inside the month-end window), not a veto, matching "bias". |
| 55 | **High (document's session x symbol matrix not implemented)** | `round10_claude_opus_5` | The document's matrix is 00:00-03:00 AUDNZD/EURGBP/AUDUSD, 07:00-10:30 EURUSD/GBPUSD/XAUUSD/GER40, 13:30-16:00 XAUUSD/USDJPY/US100, plus "max 2 entries per session, max 3 concurrent, max 1.5 % open risk". The EA ran one 07:00-16:00 sweep window for every instrument - the Asian sleeve did not exist at all (session started at 07:00), GER40/US100 were missing from the universe, and none of the three caps was enforced. | Session starts at 00:00; the three windows and their instruments are enforced branch by branch; `EA_CountPositions`, a new `SessionEntries` (deal-history count) and `EA_OpenRiskPct` implement the caps; universe gains GER40 and US100. |
| 56 | **Medium (universe, windows and group cap) with a self-correction** | `round10_qwen3_8` | (a) **The fifth pass added `AUDUSD` to this EA by mistake** - the document never mentions AUDUSD (that is the round-10 *Kimi* document). (b) The document's secondary stack lists DAX (London) and US30/NAS100 (New York); the EA's London secondary matched only `"GER"` and the NY secondary was unreachable with the shipped universe. (c) Documented windows are London 07:00-16:30 and NY 13:30-20:30; the EA cut London at 12:00 and ran NY to 21:00. (d) "Max 2 concurrent positions per currency group" was not enforced. | AUDUSD removed; DAX/US30/NAS100 added and matched in `SessionTier` (including the `GER` alias); windows aligned; `CurrencyGroupCount` implements the currency-group cap with a correct base/quote test and a single index-exposure group. |
| 57 | **Medium (dead sleeve)** | `round11_contestant_f` | The fifth pass gave the EA sleeve-B symbol gates, but the universe still did not contain DAX/US30 - and `IsSleeveBSymbol` returned true only for XAUUSD, so two of the sleeve's three documented instruments could never trade. | Universe gains DAX and US30; the gate accepts XAUUSD, DAX or US30 (the engine skips any symbol the broker does not list). |
| 58 | **Medium (documented cost rule missing)** | `round11_contestant_a` | "Reject the trade when: Spread plus estimated commission and slippage exceeds 0.10R." Nothing in the EA measured cost, although the engine has exactly this gate (`commissionPerLotRT` + `maxCostR`, added in the third/fourth-pass work). | New inputs `InpCommissionPerLotRT` (7.0) and `InpMaxCostR` (0.10) wired to the engine gate. *Slippage is not part of the ex-ante estimate* (the document's own number is a backtest-cost rule); disclosed below. |
| 59 | **High (exit matrix of a scalping document)** | `round10_gemini_3_1_pro` | Document: "**Take Profit 1:** At +1.5R, sell **60 %** of the position and move the Stop Loss to Breakeven + 0.2 pips" and "**The Time Stop:** If the position is **not at +1R** within exactly **12 minutes**, the algo closes the trade at market. No exceptions." The EA paid 50 % at +1R, moved BE at +1R, and used a flat 10-minute stop - i.e. it banked earlier than the document and force-closed runners the document says to keep. | `partial1AtR = 1.50 / 60 %`, `breakEvenAtR = 1.50`, `timeStopMinutes = 12` plus the pass-5 `timeStopUnlessR = 1.0` (skip the stop at/above +1R). The "+0.2 pips" commission offset and the Parabolic-SAR runner trail are disclosed below. |
| 60 | **Medium (ladder)** | `round8_contestant_d` | Document: 40 % at +1R, 30 % at +2R, 30 % on the trail. The EA paid 50 % at +1R and never had a +2R rung, so half the position rode a trail the document intends for a third. | `40 % / 30 % at +1R / +2R`. |
| 61 | **Medium (ladder)** | `round12_contestant_b` | Document: TP1 (+1R) close **50 %**, TP2 (+2R) close 30 %. The EA paid 40 % at +1R - a tenth of the position stayed exposed for the whole first leg. | `partial1Pct = 50.0`. |
| 62 | **Medium (missing rung)** | `round12_contestant_c` | Document: +1R close 50 %, **+2R close 30 %**. The +2R rung did not exist; 50 % of every position ran on the trail instead of booking the second target. | Added `partial2AtR = 2.00 / 30 %`. |
| 63 | **High (across 13 EAs: break-even on a wick instead of a close)** | 13 EAs | The fifth pass fixed this semantics for `round8_contestant_b` and `round7_contestant_d`; the same detector - applied to every document - shows **thirteen more EAs** whose documents explicitly qualify the break-even move with a completed bar ("BE stop only after M5 close beyond +1R", "only on an M5 close past +1R", "Move to breakeven only after an M15 candle closes beyond 1R", "only after an M1 candle closes beyond +1R", "not a wick") while the engine moved the stop on a **touch**. A wick to +1R followed by a reversal is a full loss in the code and a scratch in the document. The confirmations even name *different* timeframes than the signal timeframe in three cases. | Engine: new `SEASettings.beConfirmTf` (PERIOD_CURRENT = the EA's signal timeframe) selects the bar series for the confirmation; `EATrade` uses it. Specs: `breakEvenOnBarClose = true` on `round10_claude_opus_5`, `round10_kimi_k3`, `round10_qwen3_8`, `round11_contestant_a`, `round11_contestant_f`, `round12_claude_fable_5`, `round12_contestant_a`, `round12_contestant_c`, `round12_contestant_f`, `round12_qwen3_8`, `round4_contestant_d`, `round8_contestant_a`, `round8_contestant_d`; `beConfirmTf` overridden to M5 (opus), M1 (r11a) and M15 (r8d) where the document names those. |
| 64 | **Medium (break-even one bar late)** | `THE5ERS_CHALLENGE_STRATEGY_V2` | The manual BE block is correctly close-based, but read `m[1].close` from a series fetched as `EA_Rates(..., start = 1, ...)`, where index 0 is the last *completed* bar. The check therefore looked at the second-to-last close, so the BE move lagged one M5 bar behind the document's "completed M5 close beyond +1R". | `m[0].close`. |
| 65 | **High (the +1R rung of the flagship EA was a wick trigger)** | `EA_TRIAD_SURVIVE` | The document's sleeve-A table says "+1R reached, **confirmed by M5 candle close (not wick)** | close 40 % (60 % XAUUSD), move stop to breakeven". `Manage()` triggered both the partial and the BE on `rMult >= 1.0`, i.e. on a touch. | A completed-M5-close R multiple (`rClose`) now gates the +1R rung; the +2R rung stays on touch because the document does not qualify it. |

Verification of the sixth pass: `gen_additional_eas.py` regenerates all 65 and
`--check` reports "OK - 65 generated EAs match the specs"; `check_mql5_source.py`
reports **0 findings** on the 65 (92 on the whole tree, all pre-existing legacy
structure); `scripts/dev/arity_check.py` reports 0 arity and 0 undefined-name
findings over 87 files; brace balance 0; the stdlib suite passes 187 tests. The
dead-helper detector reports **0** remaining dead EA-local helpers, the
comment-only-input detector **0**, the clock-wiring detector 0 of 65 unwired,
and the BE-qualifier regression check reports the only remaining "touch-based
where the document qualifies a close" candidate as a false positive (an
entry-side sentence in `round5_contestant_f`).

**Documented deviations and limitations from this pass (not bugs).**

* **Index instruments are now shipped, not withheld.** GER40/US100 (opus),
  DAX/US30/NAS100 (qwen), DAX/US30 (r11_f sleeve B) are in the universes; the
  engine's `EA_ParseSymbols` **skips and logs** any configured symbol the broker
  does not offer, so these sleeves are live exactly where the broker lists the
  index and inert where it does not. This supersedes the fifth pass's "index
  sleeves are not shipped" limitation (kept visible in the pass-5 table).
* **Per-sleeve exit ladders still cannot be expressed by the engine.**
  `EA_TRIAD_SURVIVE`'s sleeve B (XAUUSD/GBPJPY) is documented with its own
  ladder (50 % at +1.5R, remainder on a chandelier) while sleeve A's ladder
  (40/30, 60/20 on gold) is the one `Manage()` implements; sleeve identity is in
  the position comment (`SURVIVE-S2`) but `cfg.partialN*` is per-EA state, so
  sleeve B runs the sleeve-A ladder. `round5_contestant_e` (per-pair ladders),
  `round5_contestant_b` (asymmetric-runner variant), `round5_contestant_b_2048`
  (75 % at 1.5R, a deliberate variant of its sibling row), `round5_contestant_f`
  (grid sleeve only) and `round11_contestant_f` (sleeve B trigger substitution)
  remain as disclosed in the fifth pass; `round10_qwen3_8` and
  `round12_qwen3_8` documents specify 40/30 in their own tables but 50 % in
  their "stack" section - the EA follows the tables, and the inconsistency is
  the document's.
* `round10_gemini_3_1_pro`'s runner is documented as trailing "using a tight M1
  Parabolic SAR (0.02/0.2)". No Parabolic-SAR handle exists in the engine's
  indicator registry, so the runner keeps the R-distance trail
  (`trailAtR = 1.5`, 0.5R) - a stated stand-in, not the documented indicator.
  Its "+0.2 pips" break-even offset is likewise not expressible: `beOffsetR` is
  in R multiples, so the stop lands exactly at entry.
* `round11_contestant_a`'s cost gate counts spread + commission (the engine's
  `EA_CostInR`) but not slippage: slippage is not knowable before the fill. The
  document's own sentence is a backtest-cost rule; the live gate is the
  conservative half of it.
* `round4_contestant_d`'s break-even level is "a 5-minute close beyond the next
  structure level" - encoded as `breakEvenAtR = 2.0` with the M5 close
  confirmation (#63). The document does not quantify the structure level.
'''

TRACKER_BULLET = (
"* **Deep bug audit, sixth pass (2026-10-02)** - this pass went after **code that exists but does nothing** and the "
"**exit semantics** the earlier passes had only spot-checked: **14 defect classes fixed across 20 EAs plus one "
"shared-engine addition** (#52-#65 in `docs/EA_BUG_AUDIT.md` \"Sixth pass\"). Headlines: `round4_contestant_b`'s "
"London and NY sleeves accepted any universe member (the documented sleeve-1 helper existed and was never called); "
"`round10_claude_opus_5` never implemented the document's session x symbol matrix (the Asian sleeve did not exist, "
"GER40/US100 were missing and none of the three exposure caps was enforced); **thirteen EAs moved the stop to "
"break-even on a wick while their documents require a completed bar close** (fixed with a new "
"`SEASettings.beConfirmTf`, which also lets the confirmation run on the timeframe the document names - M5/M1/M15); "
"`EA_TRIAD_SURVIVE`'s +1R rung (partial + BE) was a wick trigger, `round10_gemini_3_1_pro` banked at +1R instead of "
"its +1.5R/60 % matrix and force-closed runners its document says to keep (flat 10-minute stop -> 12-minute "
"conditional stop), `round8_contestant_d`/`round12_contestant_b`/`round12_contestant_c` paid the wrong ladder "
"percentages or lacked a rung, `round11_contestant_a`'s documented 0.10R cost gate was missing, "
"`THE5ERS_CHALLENGE_STRATEGY_V2`'s manual break-even read one bar late, and two dead helpers "
"(`RangeBetween`, `EndOfMonthWindow`) were removed/wired respectively. **One self-correction:** the fifth pass had "
"added `AUDUSD` to `round10_qwen3_8`, whose document never mentions it - removed. All 65 EAs regenerated; "
"`--check` 65/65, checker 0 on the 65, arity 0/0 over 87 files, braces 0, 187 tests pass.\n"
"* **Sixth-pass note on index instruments** - GER40/US100/DAX/US30/NAS100 are now shipped as universes instead of "
"being withheld: the engine's symbol parser skips (and logs) any configured symbol the broker does not list, so "
"those sleeves trade where the index exists and stay inert where it does not.\n"
)

import re

A = "docs/EA_BUG_AUDIT.md"
s = open(A, encoding="utf-8").read()
before = len(s)
anchor = "## Verification after the fixes"
assert s.count(anchor) == 1
s = s.replace(anchor, SIXTH.strip("\n") + "\n\n" + anchor)

rows = (
"| Dead EA-local helpers (function defined, never called) | 3 found; all resolved (`IsLondonPair` wired, `RangeBetween` removed, `EndOfMonthWindow` wired); 0 remaining |\n"
"| Inputs referenced only inside comments (rendered EA) | 0 |\n"
"| `ctx.index` / `g_eaInd[ctx.index]` uses without a guard in the function | 14 raw hits, all guarded upstream: a context is only built when `ind.valid` (EA_BuildContext) |\n"
"| Track-table mutation inside a forward `g_eaTrack` loop | 0 real - the engine's only remover (`EA_SyncTracks`) iterates backwards and the executor's `Close()` is asynchronous; the detector's one hit was `EA_TrackIndex`, a forward search |\n"
"| `cfg.clock` / `serverWinterGmtOffset` wiring | 65/65 wired |\n"
"| Outer session envelope vs inner sleeve windows | 2 raw hits, both verified non-entry (FINAL_OPTIMUM's deliberate 24h window; round8_d's 16:30/20:00 close-outs inside a 07:00-10:00 entry window) |\n"
"| Sleeve-accounting tags vs what the executor writes | clean - `EA_ExecutePlan` passes `plan.reason` as the position comment, so the `R11F-A/B/C` and `SURVIVE-S1/2/3` tags are present exactly |\n"
"| Documented partial ladders vs `cfg.partialN*` (both \"X % at +NR\" and \"at +NR, sell X %\" phrasings) | 4 real mismatches fixed (#59-#62); the rest verified as pro-poetry, rejected alternatives, or disclosed variants |\n"
"| Documented break-even qualifiers (\"only after a close/beyond a candle\") vs `cfg.breakEven*` | 13 further EAs were touch-based (#63); after the fixes the only remaining candidate is a false positive (an entry sentence) |\n"
)
anchor2 = "| Tracker source-document links resolve to a file |"
assert s.count(anchor2) == 1
s = s.replace(anchor2, rows + anchor2)

# supersede the pass-5 index limitation, in place
import re as _re
bullet = _re.compile(r"\* \*\*Index-named sleeves are not shipped as universes\.\*\*.*?(?=\n\* \*\*Deliberate single-sleeve variants)", _re.S)
assert len(bullet.findall(s)) == 1
s = bullet.sub(
    "* **Index-named sleeves are not shipped as universes (SUPERSEDED by the sixth "
    "pass, which ships them - the engine skips and logs any configured symbol the "
    "broker does not list, so those sleeves trade where the index is offered and stay "
    "inert where it is not).** This bullet is kept for the record of what the fifth "
    "pass decided.", s)
open(A, "w", encoding="utf-8").write(s)

T = "docs/EA_IMPLEMENTATION_TRACKER.md"
t = open(T, encoding="utf-8").read()
t = t.replace("## 5. Verification Performed (2026-10-01, extended 2026-10-02, fifth audit pass)",
              "## 5. Verification Performed (2026-10-01, extended 2026-10-02, sixth audit pass)")
anchor3 = "* **Documented limitations from the fifth pass (deliberate, not bugs)**"
assert t.count(anchor3) == 1
t = t.replace(anchor3, TRACKER_BULLET + anchor3)
open(T, "w", encoding="utf-8").write(t)
print("audit updated: +%d bytes; tracker: +%d bytes" % (len(s) - before, len(t)))
