# ICT / SMC coverage — what the repository really implements

*2026-10-05.  Derived from the source (which function each EA calls), not from EA names.
Nothing here has been compiled or run in a Strategy Tester — that gap is unchanged and
is the first thing to close on the Windows machine.*

## Short answer

* **SMC — yes.**  The Master Triad's engine **E1** is a dedicated SMC engine (liquidity
  sweep → M15 CHoCH → order block with a mitigation check → a two-leg limit entry).
  In the 65-EA family, **5 EAs trade an order-block retest, 2 trade a fair-value-gap
  retest, 3 use fractal swing structure, and 50 build on a liquidity sweep** (53 of 65
  counting three hand-written sweep variants).
* **ICT — partially, as building blocks; no EA is an explicit ICT model.**  The pieces
  are here — the Asian-range liquidity raid at the London open (ICT's "Judas swing"),
  displacement, fair-value gaps, order blocks, an SMT-style divergence check, session
  windows — but nothing composes them into the canonical ICT entry (daily bias → kill
  zone → liquidity sweep → market-structure shift with displacement → FVG/OB entry at
  OTE / in discount → target the opposite liquidity).  Several ICT staples do not exist
  at all (see *What is not implemented*).

## Where it lives

| ICT / SMC concept | Implementation | Used by |
|---|---|---|
| Liquidity sweep → reclaim → displacement (raid of the Asian / London / NY range) | `SigSweepReclaim` — `MQL5_Master/Include/EASignals.mqh:431` | **50 EAs** — magics 2003, 2004, 2008, 2010, 2011, 2014, 2016, 2018–2020, 2023–2031, 2033–2048, 3103–3117 |
| …hand-written variants of the same pattern | `TriadPlan` (3101), `SweepReversal` (2013), a 4-hour-extreme sweep with volume-delta (2032) | 3 EAs |
| "Judas swing" (fade the false break of the Asian extreme at the London open) | `SigSweepReclaim` with a 07:00–09:00 London window, 50 % retrace entry — `EA_studyarena_round4_contestant_c.mq5:94` (`R4C-JUDAS`) | 2011 (one EA) |
| Order block + retest | `SigOrderBlockRetest` — `EASignals.mqh:1396` (last opposing candle before a displacement; entry on the retest) | 2001 R1B, 2002 R1C, 2005 R2C, 2006 R3A, 2012 R4C2 |
| Fair-value gap (imbalance) retest | `SigFvgRetest` — `EASignals.mqh:1482` | 2007 R3B, 2010 R4B2 |
| Swing structure / swing sweeps | `SigFractals` — `EASignals.mqh:1583` | 2005, 2008, 2017 |
| Market-structure shift (CHoCH) | `CE1SMCCore::DetectM15CHoCH` — `E1_SMC_Core.mqh:389` (first M15 close beyond the post-sweep swing); a 3-bar "CHoCH" in R2C | Triad E1, 2005 |
| Order block with mitigation check, entry at the OB edge **and** its 50 % ("mean threshold") | `E1_SMC_Core.mqh:389-` + `ExecutionManager.mqh:65` (`SendDualBracketLimit`, two limits at 50/50 risk) | Triad E1 |
| SMT divergence | `E1_SMC_Core.mqh:134-` — an RSI(14) **proxy** on the dollar index, *inert* when the broker has no DXY symbol (logged) | Triad E1 |
| Session / kill-zone timing | London-clock entry windows on every sweep EA (07:00–10:30 London, NY 13:30–16:00); E1 uses raw server hours 08–18 | all of the above |
| FVG as a **sizing** boost only | `GeminiV4_FVG_Score` — `MQL5/Experts/GEMINI_V4_QUANT.mqh:134` (H4 FVG multiplier) | the older `*_V4` research EAs (`FIVE_M5_EXHAUST_V4`, `GOLD_SWING_V4`, `TRIAD_GOD_COMBO_V4`), not the 65 |

The 13 files in `additionalEAs/` that are *not* among the 65 (`EA_max_roi_out_of_box_strategy`,
`EA_master_combination_strategy`, …) mention kill zones, FVG and "50 % OB equilibrium", but they
are print-only skeletons with no entry logic (`signalTriggered = false; // Example trigger`) —
they are **not** ICT strategies.

## What is not implemented

No EA has: **break-of-structure** (continuation) tracking · **premium / discount** (equilibrium)
filter · **OTE** (62–79 % retracement) entries · **breaker** or **mitigation blocks** as entry
models · the **Silver Bullet** window (10:00–11:00 New York) or kill zones expressed in New York
time · an explicit **Power-of-3 / AMD** model beyond the Asian-range raid · **inversion FVGs** ·
**equal-highs / equal-lows** liquidity pools (the liquidity used is the Asian/session range and
fractal swings) · a **previous-day high/low daily-bias** model (prior-day extremes appear only as a
score term in R10KIMI 2033 and R5A2 2047) · a real SMT comparison of swing extremes between two
instruments.  "SMC"/"ICT" in a name is not evidence: `R2C_SMC_PILLARS`' CHoCH is a three-candle
pattern, `R1C_SMC_CONFLUENCE` counts *order block + break-retest + EMA cascade*.

## How faithful the SMC implementation was — and what this pass fixed

Reading the ICT/SMC paths line by line found defects that change what they trade
(`docs/EA_TOP25_BUGS_2.md` has the full list with evidence):

* **E1's liquidity-sweep precondition read the time axis backwards.**  `CopyRates` fills a plain
  array *oldest-first*, so the "prior liquidity" `r[50..59]` was the **newest** ten bars; a
  textbook sweep-and-reclaim could be rejected and a breakdown that simply continued accepted.
  (This was my own request-21 fix; it is re-done in chronological terms and the test that pinned
  the wrong rule is replaced.)
* **R2C, R3A and R3B could never go short** — `tradeBothWays = (bias > 0)` switched the bearish
  branch off exactly when the bias was bearish.  They are now genuinely two-sided.
* **`SigOrderBlockRetest` had no block-failure test**: a block that price had traded *through*
  still fired a long on the way back.  It now requires that no closed bar has closed beyond the
  block's far side.
* **`SigBreakRetest` was a breakout chaser**: break and "retest" were judged on the same candle, so
  any breakout candle that opened inside the range "retested".  The retest is now a *later* bar.
* **R4D** put its stop at the range edge — *inside* the sweep wick — while its own document says
  "beyond the sweep extreme".
* **E1 consumed a sweep before the order existed**, so one rejected placement (spread blip, stop
  level) burned the setup for good; **its partial / break-even flag** had the same shape.
* The 13 pullback EAs, R5B, R10FABLE, R8B, R4B and the portfolio host **did not compile** (see the
  top-25 list).

## Judgment calls left open (not bugs, but they decide behaviour)

1. **Order-block freshness.**  E1 only trades an *unmitigated* block (the SMC rule); the library's
   `SigOrderBlockRetest` re-fires on every revisit while the block is alive.  A `requireFresh`
   option is a small change — it is a strategy decision (fewer, higher-quality entries), so it was
   not made silently.
2. **`SigFvgRetest.maxRetrace`** is named "max" but behaves as a *minimum* depth (price must be at
   least 25 % into the gap at the default 0.75).  Documented in the struct; behaviour kept because
   two EAs were written against it.
3. **E1's session filter and grading bonus use raw server hours** (08–18, "London 08–12"): right
   for a GMT+2/+3 broker only.  `InpBrokerOffset` exists for news; the engine does not use it.
4. **SMT is a proxy** (RSI of the dollar index), not a swing-extreme comparison, and it is skipped
   — with a warning — on brokers without a DXY symbol.

## If you want an explicit ICT model

The primitives are reusable, so a real ICT EA would be a composition rather than a rewrite.  A
sensible first version: *daily bias from the previous day's high/low and a higher-timeframe
close → trade only inside the London and New York kill zones (New York time, DST-aware) → require a
liquidity sweep of the session range or of equal highs/lows → require a market-structure shift
with displacement → enter at the FVG / order block, in discount (long) or premium (short), with
an OTE limit → stop beyond the swept extreme → target the opposite liquidity pool.*  That is a new
EA (or a new engine in the portfolio host) and a strategy decision — say which parts you want and
it can be built on the same checked-in primitives, with the same guards and tests.
