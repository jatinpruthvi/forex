# portfolio-EA — PLAN (for approval, before building)

**Status: decisions taken and implemented** (2026-10-03) - the user confirmed the intent:
*a new EA holding all 65 engines, plus a separate PortfolioEA tracker*.  The four
questions below were skipped, so the plan's recommended defaults were applied:
1) magic 2006 keeps its delivered ladder (`InpKeepDeliveredPolicy = "2006"`);
2) comment tags `P<magic>|` inside the generated trader only;
3) the trader writes no runtime files (identity ships as static `engines.csv`);
4) risk/book guards exist but default to faithful (`InpRiskScale = 1.0`, caps 0 =
off) - set them for the demo phase as you prefer.
Names per the clarification: trader = `AllEnginesEA.mq5`, tracker = `PortfolioEA.mq5`.
See README.md for the implemented state and `verify_portfolio.py` (723 checks) for the
evidence.  Items below are kept as the original design record.

---

**Original proposal text follows.** Everything
below is grounded in the delivered code, verified by reading it (facts and line
references are given). Approve/adjust the four decisions at the end and the build
follows.

**Scope of this plan**

| | |
| --- | --- |
| Goal | Run the 65 engines **on one chart** for a **demo phase first**, with each engine uniquely identifiable, individually switchable, and each engine following the *one-order-per-symbol / many-symbols* rule |
| Out of scope | Any dashboard / performance tracking inside this EA — that becomes a **separate EA** (same repo, later) |
| Constraint | 65 delivered EAs and the engine includes stay **unmodified**; all work happens in generated files under `portfolio-EA/` |

---

## 1. Two EAs, one boundary

| Program | Runs on | Job | Writes |
| --- | --- | --- | --- |
| `PortfolioEA` (this folder) | 1 chart | execute the engines, hold the on/off switches, keep identity | nothing at runtime (see §6) |
| `EngineDashboard` (future, separate) | its own chart or none | read account history per magic → per-engine P/L, DD, win rate, trades/day; decide what to switch off | its own report files |

They cooperate through **one static identity file** (§2.3) and the **magic number**.
No runtime coupling, no shared state — so the dashboard can be added, removed or
restarted without touching the trading program.

---

## 2. Identity: how each engine is recognised

### 2.1 Magic number — primary key (already unique, already built)

Every engine keeps its delivered magic (3101…3193). Verified in the engine:
**every** position/order/history query filters `POSITION_MAGIC == g_eaCfg.magic`
(`EA_CountPositions`, `EATrade.mqh:112/168/182/202…`). So:

* the terminal's trade history is already grouped per engine by magic;
* one engine can never count, close or manage another engine's trades;
* the future dashboard only needs the magic to attribute every deal.

### 2.2 Order comment — secondary key (proposed addition)

Fact: the order comment is `plan.reason` (`EACommon.mqh:449` → `OpenMarket/OpenLimit`
→ `CTrade`), and **MT5 caps comments at 31 characters**; the server may rewrite the
last characters when a position closes (MT5 help: max 31, ~6 reserved). So identity
must go at the **front** of the comment, never the end.

Proposal: a generated **tag wrapper** per engine (new code, in the generated
header only — the delivered classes stay untouched):

```cpp
class P3101_Tagged : public P3101_CFinalOptimum {
public:
   virtual bool BuildPlan(SEAContext &ctx, SSignalPlan &plan) override {
      if(!P3101_CFinalOptimum::BuildPlan(ctx, plan)) return false;
      if(plan.dir != 0) plan.reason = "P3101|" + plan.reason;   // 6 chars, survives truncation
      return true;
   }
};
```

Effect: every order, every log line and every ledger note starts with `P3101|`,
so the comment alone identifies the engine even without looking up the magic.
Cost: 6 of 31 characters; the rest of the strategy's own description survives.

### 2.3 Static identity file

Generated from the specs and shipped to `MQL5\Files\PortfolioEA\engines.csv`:

```
magic,tag,ea,strategy,symbols,timeframe,risk_pct,switch_input,source_doc
3101,P3101|,EA_FINAL_OPTIMUM_STRATEGY,FINAL_OPTIMUM,XAUUSD;AUDUSD;EURJPY;GBPJPY;USDJPY,M5,1.75,InpRun_3101,docs/strategy/FINAL_OPTIMUM_STRATEGY.md
…
```

Both EAs read it; it is written once by the generator (not by the EA), so it is
data, not runtime state. `portfolio-EA/build/STRATEGY_REGISTRY.md` keeps the
human-readable version.

---

## 3. Order policy per engine

### 3.1 The rule you asked for — half of it already exists

Verified in `EA_SelectPlan` (`EACommon.mqh:351-356`):

```cpp
if(!g_eaStrategy.AllowMultipleOnSymbol())
{
   if(ctx.openPositions > 0) continue;                 // already positioned on THIS symbol
   if(g_eaExec.HasPending(ctx.symbol, +1) || …) continue;   // or an order is already working
}
```

`ctx.openPositions` is per **engine × symbol** (magic-filtered). So *"one order if
that symbol is already placed"* is **already the behaviour of 64 of the 65
engines** — no change needed, only verification.

The one exception is by design: **magic 2006 (`round3_contestant_a__1_`)** returns
`AllowMultipleOnSymbol() == true` (it is a ladder). Forcing one-per-symbol on it
would change the strategy, so the plan treats it as an explicit, documented
exception unless you decide otherwise (decision 1).

### 3.2 The other half — multi-symbol needs a cap override

The blocker for *"multiple orders when the symbol is different"* is the per-engine
cap, checked account-wide **for that engine** (`EATrade.mqh:778`):

```cpp
if(ctx.openPositionsAll >= (int)MathMax(1, g_eaCfg.maxOpenPositions)) return false;
```

Delivered state, verified across the 65:

| Delivered setting | Engines | Consequence today |
| --- | ---: | --- |
| `maxOpenPositions = 1` (or unset → 1) | 46 | the engine can hold **one** position max across its whole universe |
| `maxOpenPositions = 2–3` | 19 | still below the symbol count (e.g. cap 2 with 9 symbols) |
| `oneEntryAccountWide = true` (8 × THE5ERS) | 8 | one entry account-wide **for that engine** — no second symbol either |
| `AllowMultipleOnSymbol() = true` | 1 (magic 2006) | ladder on one symbol, intentional |

Proposal (host-side config override, applied right after `EA_Init` per strategy,
exactly like the existing `riskPct` scaling — **no engine or EA edits**):

```
g_eaCfg.maxOpenPositions  = symbol_count            // unless InpMaxPerEngine > 0
g_eaCfg.oneEntryAccountWide = false                 // allow one position per symbol
```

with `InpOnePerSymbol = true` (documents/guards the one-position-per-symbol rule
you asked for) and `InpKeepDeliveredPolicy = "2006"` (list of engines whose
delivered policy is preserved, ladder by default).

Result after the override:

* each engine may hold up to **one position per symbol**, on as many different
  symbols as it has in its universe;
* an engine never blocks another engine (verified: all counters filter by magic);
* engines that keep the "one entry account-wide" idea can be listed in
  `InpKeepDeliveredPolicy` if you ever want that for a specific engine.

### 3.3 Book-level limits (new, recommended)

Because the same table also shows the risk concentration:

* delivered `riskPct` **sums to 51.5 % of equity** across the 65 engines;
* **EURUSD appears in 63 engines**, GBPUSD in 62, USDJPY in 49, XAUUSD in 41;
* 19 distinct symbols in total.

So "all engines on" can mean 63 simultaneous EURUSD positions if every engine's
conditions fire. Proposed guards (risk management, not a dashboard):

| Input | Default | Meaning |
| --- | --- | --- |
| `InpRiskScale` | 0.25 | multiplies every engine's delivered risk while on demo |
| `InpBookRiskPct` | 6.0 | refuse new entries when aggregate open risk exceeds this % of equity |
| `InpMaxBookPositions` | 12 | total positions across all engines |
| `InpMaxBookPerSymbol` | 3 | how many engines may hold the same symbol concurrently |
| `InpMaxPerEngine` | 0 | 0 = the engine's own symbol count |

All five can be raised to "off" values for the final configuration; the point is
that the demo phase starts safe by default.

---

## 4. Demo-first lifecycle

1. **Compile + attach once** (one chart, Algo Trading ON).
2. **Demo phase**: `InpRiskScale = 0.25`, book caps on, all `InpRun_<magic>` ticked.
3. **Measure** with the separate dashboard EA (per-magic P/L, DD, trade counts).
4. **Switch off** losers: untick `InpRun_<magic>` (or use `InpDisableMagics = "2036,2039"`).
   No recompile, no re-attach. Options persist with the chart — save the chart as a
   template (`PortfolioEA_demo_YYMMDD`) so each decision set is reproducible.
5. **Promote** the survivors: raise `InpRiskScale`, relax the book caps, attach on
   live. Same switches, same magics, same engine code.

Audit trail without a dashboard: the Experts log prints one line per engine at
start (`ready … magic … symbols … risk`) and one line per disabled engine with the
reason (`switch=off`, whitelist, blacklist).

---

## 5. What this changes in the current prototype

| Piece | Action |
| --- | --- |
| `InpRun_<magic>` switches, whitelist/blacklist | **keep** (built, verified) |
| Registry documents (MD/CSV) | **keep**, add `tag` + `switch_input` columns; add `engines.csv` for `MQL5\Files` |
| Per-engine cap + `oneEntryAccountWide` override | **add** (§3.2) |
| Comment tag wrappers | **add** (§2.2) |
| Book risk / position caps | **add** (§3.3) |
| `roster.csv` runtime writer (positions + floating P/L) | **remove** — that is performance tracking; it belongs to the dashboard EA (§6) |
| One-per-symbol rule | **verify** in tests rather than re-implement (engine already does it) |

---

## 6. The boundary: no dashboard logic here

`PortfolioEA` will contain **no**: panel/objects, `OnChartEvent`, chart labels,
`Comment()`, statistics aggregation, equity/DD computation, per-engine P/L, or
report files. Runtime output is limited to `Print()` lines (init, switches,
rejections) — logging is not a dashboard.

Removed by this plan: the `roster.csv` writer (it carried positions + floating
P/L). The identity map moves to the static `engines.csv`, which is exactly what
the future `EngineDashboard` needs to attribute history — grouped by magic,
labelled with `tag`/`strategy` from the same file.

---

## 7. Verification plan (all runnable here, no MT5)

Extend `verify_portfolio.py` (currently 357 checks) with:

1. every engine's effective policy in the build = one-per-symbol, cap ≥ symbol
   count, except the engines listed in `InpKeepDeliveredPolicy`;
2. tag wrappers exist for all 65, tags are unique, ≤ 9 chars, front-loaded;
3. `engines.csv` covers all 65 magics exactly once and matches the registry;
4. **no-dashboard guard**: build must not contain `ObjectCreate`, `OnChartEvent`,
   `Comment(`, `ChartSetString`, or any position/P&L aggregation outside the
   engine's own functions;
5. no runtime `FileOpen` for writing except the engine's own ledger (disabled by
   default) — i.e. PortfolioEA writes nothing;
6. the existing checks (originals untouched by hash, 65 classes, switches,
   registry completeness, brace balance, repo checkers).

Plus a **policy simulation test** (new, pure Python): a mini model of
`EA_SelectPlan` + the cap check, fed synthetic signals, asserting:
engine holds max 1 per symbol, holds ≥ 2 symbols when signals differ, book caps
hold, and switching an engine off stops new entries while its open positions are
still managed (the engine manages existing positions regardless of the switch —
that is the delivered behaviour and stays).

---

## 8. Milestones

| # | Step | Output |
| --- | --- | --- |
| M1 | Approve this plan (4 decisions below) | — |
| M2 | Generator changes: overrides, tag wrappers, book caps, `engines.csv`, remove roster | regenerated `build/` |
| M3 | Verification: new checks + policy simulation | `verify_portfolio.py` green |
| M4 | You compile on Windows, run the **demo phase** | per-engine demo results |
| M5 | `EngineDashboard` (separate EA, its own folder) | per-engine performance report |
| M6 | Flip the switches, go live | final engine set |

---

## 9. Decisions needed

1. **Ladder exception** — magic 2006 is intentionally multi-leg on one symbol.
   Keep its delivered behaviour (recommended) / force one-per-symbol / exclude it
   from the demo set?
2. **Comment tags** — add the `P<magic>|` prefix inside PortfolioEA only
   (recommended), also generate tagged copies of the 65 for the chart-per-EA
   route, or magic-only?
3. **Runtime files** — none; static identity CSV only (recommended), or write the
   identity map at init (no P/L)?
4. **Demo risk defaults** — the proposal in §3.3 (`0.25×`, 6 % book risk, 12
   positions, 3 per symbol), or start with everything at delivered risk and no
   book caps?
