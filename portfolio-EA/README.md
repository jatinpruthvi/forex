# portfolio-EA — all 65 engines on one chart + a separate tracker

Two EAs, both plain MQL5, one boundary:

| EA | File | Chart | Job | Trading |
| --- | --- | --- | --- | --- |
| **AllEnginesEA** | `build/AllEnginesEA.mq5` | 1 chart | runs **all 65 engines**: registry, per-engine state switch, on/off switches, identity tags | yes |
| **PortfolioEA** | `src/PortfolioEA.mq5` | any chart, or a second chart | **tracks per-engine performance** and writes the report you use to decide what to switch off | **never** (read-only) |

### What you compile

1. `build/AllEnginesEA.mq5` — **one file**. All 65 strategies are inside it; it
   needs nothing from this folder next to it, only the shared engine header that
   the 65 delivered EAs already use:
   `<data>\MQL5\Include\EACommon.mqh`.
2. `src/PortfolioEA.mq5` — **one file**, self-contained, needs no header at all.

### How it is driven

MT5 delivers `OnTick` only for the **chart's** symbol. The EA therefore does not
depend on that alone: it processes the book from a **1-second timer** as well
(`OnTimer` → the same `PortProcess()`), so an engine keeps working while the
chart symbol is closed (weekend, holiday, index out of session). Engines that
have exposure are processed on every pass; the rest wake on a new bar of their
own signal timeframe. Attach it to a liquid, always-on symbol (EURUSD is the
natural choice) so the tick path stays fast.

### Python is build-time only

Nothing in either EA is Python. `gen_portfolio_ea.py` is the *assembly* tool that
copies the 65 delivered strategies into the EA file (so nobody retypes 12 000
lines by hand), and `verify_portfolio.py` is the checker. You never need Python to
compile, install or run the EAs — and MT5 never runs Python.

MT5 allows one EA per chart, so AllEnginesEA is the only way to get a genuinely
single-chart book; PortfolioEA is the dashboard, deliberately kept out of the
trading program.

```
portfolio-EA/
├── build/AllEnginesEA.mq5   COMPILE THIS - one EA, all 65 strategies inside it
├── src/PortfolioEA.mq5      COMPILE THIS - the tracker EA (standalone)
│
├── PLAN.md                  the design + the decisions taken (read this first)
├── gen_portfolio_ea.py      build tool: delivered 65 EAs -> the one EA file
├── verify_portfolio.py      1 739 static checks (freshness, hashes, policy, tags,
│                              identifier hygiene, both boundaries)
├── README.md
└── build/                   GENERATED - do not hand-edit
    ├── AllEnginesEA.mq5              the EA (the strategies are inlined)
    ├── PortfolioStrategies.mqh        review copy of those 65 classes + wrappers
    ├── engines.csv                   magic -> tag -> engine -> switch  (for the tracker)
    ├── STRATEGY_REGISTRY.md          the same table, human-readable
    ├── strategy_registry.csv         and machine-readable
    ├── portfolio_manifest.json       per-engine manifest used by the checks
    └── originals.sha256              hashes of every original file read
```
```

## Nothing original is touched

The 65 delivered EAs and `MQL5_Master/Include/*.mqh` are **read-only inputs**.
`build/originals.sha256` records their hashes and `verify_portfolio.py` re-checks
them, so any accidental edit to an original fails verification.

## Identity: magic + comment tag

* **Magic is the primary key.** Every engine keeps its delivered magic (3101…3193),
  and the engine filters every position/order/history query by it — including
  `openPositionsAll`, which is **per engine**, not account-wide (verified in
  `EA_CountPositions`). One engine can never touch another's trades.
* **Comment tag** is the visible secondary key. Each engine is wrapped by a
  generated class that prefixes the order comment with `P<magic>|`
  (front-loaded because MT5 caps comments at 31 characters and the server may
  rewrite the tail):

  ```cpp
  //--- portfolio wrapper for EA_FINAL_OPTIMUM_STRATEGY (magic 3101, tag P3101|)
  class P3101_Port : public P3101_CFinalOptimum
  {
  public:
     virtual bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
     {
        if(!PortEntryGate(ctx.symbol)) return false;            // book caps (host)
        if(!P3101_CFinalOptimum::BuildPlan(ctx, plan)) return false;
        if(plan.dir != 0) plan.reason = "P3101|" + plan.reason; // identity, front-loaded
        return true;
     }
  };
  ```

* `build/engines.csv` is the static map (magic, tag, engine, strategy, symbols,
  timeframe, risk, switch, order policy, source doc). Copy it to
  `MQL5\Files\PortfolioEA\engines.csv` — the tracker reads it; without it the
  tracker still works but shows magics instead of engine names.

## Order policy: one position per symbol, many symbols

**Two mechanisms enforce it.** Every delivered engine except one carries the rule
in `EA_SelectPlan`:

```cpp
if(!g_eaStrategy.AllowMultipleOnSymbol())
{
   if(ctx.openPositions > 0) continue;                 // already positioned on THIS symbol
   if(g_eaExec.HasPending(ctx.symbol, +1) || …) continue;   // or a working order
}
```

`ctx.openPositions` counts only that engine's positions on that symbol. So an
engine may hold one position on each of its symbols and never doubles up on one.

What *did* need fixing is the per-engine cap, which would have limited engines to
a single position book-wide: 46 of the 65 deliver `maxOpenPositions = 1` and 8
(THE5ERS family) set `oneEntryAccountWide = true`. The host therefore applies,
per engine right after init (config-level only — no engine or EA code changed):

```
maxOpenPositions    = its symbol count   (or InpMaxPerEngine if > 0)
oneEntryAccountWide = false
```

The one exception is magic **2006** (`R3A_TF_CASCADE`), the only strategy that
overrides `AllowMultipleOnSymbol()`. For it (and for any engine you add to
`InpKeepDeliveredPolicy`) the host applies the rule itself: `PortEntryGate`
refuses a new entry while that engine already has a **position or a resting
order** on the symbol — so one order per symbol holds for the whole book. Remove
`2006` from the list to keep its delivered stacking ladder instead.

Per-engine caps can be lowered with `InpMaxPerEngine`.

Book-level guards (off by default; raise the risk scale and switch them on as you
prefer): `InpMaxBookPositions`, `InpMaxBookPerSymbol`, `InpBookRiskPct`. They
apply to **every** engine, including the one keeping its delivered policy. Context:
delivered risk sums to **51.5 % of equity** across the engines and EURUSD appears
in **63 of 65** universes, so an unguarded "all on" demo can put 60+ positions on
one symbol. For a demo phase that is meant to be *measured*, start with
`InpRiskScale` below 1 and only the caps you are comfortable with — the tracker
records what each engine did either way.

## Switches (after demo testing)

| Control | Where | Effect |
| --- | --- | --- |
| `InpRun_<magic>` | inputs, group *"Per-strategy switches"* | untick one engine — no recompile, no re-attach |
| `InpDisableMagics` | portfolio inputs | blacklist, e.g. `"2036,2039"` |
| `InpOnlyMagics` | portfolio inputs | whitelist, e.g. `"3101,3102"` (subset testing) |
| `InpRiskScale` | portfolio inputs | scales **every** engine's delivered risk at once |

Precedence: whitelist → `InpRun_<magic>` → blacklist. Disabled engines are logged
at startup with the reason, and their open positions are still managed (the engine
keeps managing exposure regardless of the switch — that is the delivered design).

## The tracker EA (`src/PortfolioEA.mq5`)

Read-only by construction (no `CTrade`, no order functions, verified by
`verify_portfolio.py`). Runs on a timer, groups the account's history by magic:

* net closed P/L — the **whole round turn**: entry-side commission/swap is
  carried to the closing deal, so net, the win/loss split and the drawdown curve
  agree (defect #69); trades, wins/losses, win %, **max closed drawdown**;
* open positions and floating P/L per engine;
* a **verdict** you can act on, decided in this order: `TOO_FEW` (fewer than
  `InpMinTrades` closed trades — a zero-trade engine is never `KEEP`; a big
  closed drawdown still flags `REVIEW`), `DROP` (enough trades and net
  negative), `REVIEW` (expectancy ≤ 0 or DD ≥ `InpReviewDdPct`), `KEEP`;
* writes `MQL5\Files\PortfolioEA\performance.csv` (includes the `switch` column —
  the exact input name to untick), and draws an optional on-chart panel sorted by
  net.

Install: copy `build/engines.csv` to `<data>\MQL5\Files\PortfolioEA\engines.csv`
(it is the magic -> name map), put `src/PortfolioEA.mq5` in `<data>\MQL5\Experts\`
(or any subfolder), compile, and attach it to a chart with `InpDaysBack` set to
your demo window. Without `engines.csv` the tracker still works — it just shows
magic numbers instead of engine names.

## Build and deploy

On Windows/MT5:

1. engine headers already in `<data>\MQL5\Include\` (the 65 EAs need them too);
2. copy **`build/AllEnginesEA.mq5`** into `<data>\MQL5\Experts\` and compile it
   (nothing else has to go with it);
3. copy `build/engines.csv` into `<data>\MQL5\Files\PortfolioEA\`;
4. attach `AllEnginesEA` to **one** chart (Algo Trading ON) — demo first;
5. compile + attach `src/PortfolioEA.mq5` on another chart to watch per-engine
   results.

Only if you change a strategy or the host do you need the build tools again:

```bash
python3 portfolio-EA/gen_portfolio_ea.py        # rewrite the compiled EA file
python3 portfolio-EA/verify_portfolio.py        # 1 739 checks
```

If you hand-edit `build/AllEnginesEA.mq5`, keep the edited copy somewhere else
first: re-running the generator overwrites it. Hand edits belong in the delivered
EA (for logic) or in `gen_portfolio_ea.py` (for the host).

## Fidelity — exact and not exact

| Area | Status |
| --- | --- |
| Strategy logic | **exact** — class bodies copied verbatim; only identifiers are prefixed |
| Config, symbols, timeframe, risk, magic | **exact** delivered defaults (`InpRiskScale` is a deliberate multiplier) |
| Position management (partials, BE, trails, session/news gates) | **exact** — same engine functions |
| Risk anchors (day/week/month, HWM, halts) | **exact** — GlobalVariables are magic-keyed and reloaded per switch |
| Order policy | host override described above; `2006` keeps the delivered ladder |
| Spread/slippage/outcome rings | **shared on purpose** — symbol/market statistics, not engine state |
| Per-day request counter | resets on switch (only 4 engines set `maxRequestsPerDay`) — documented gap |
| Deal cursor | resets on switch; **inert** — 0 of 65 enable `lossStreakPause` |

## Status

* `gen_portfolio_ea.py` — **run**: 65 engines inlined into the single EA file,
  860 inputs as constants, 65 tag wrappers, registry + engines.csv + policy
  override + book caps. Enum types of the 6 engines that declare them are
  prefixed like every other per-engine identifier (defect #67).
* `verify_portfolio.py` — **1 739/1 739 checks pass** (freshness, originals by
  hash, switches, tags/wrappers, policy override, registry/engines.csv
  completeness, **one-file EA: every strategy inlined verbatim**, **identifier
  hygiene**: every emitted type exists, no top-level name twice, every
  `cfg.magic` resolves to its registry magic, **no dashboard or file I/O in the
  trader**, **no trading API in the tracker**, repo checkers clean).
* **Not verified: MQL5 compilation** — no MetaEditor on Linux. Compile
  `AllEnginesEA.mq5` and `PortfolioEA.mq5` on Windows; anything the compiler
  reports is fixed in `gen_portfolio_ea.py` or `src/`, never in `build/`.
* Deep-review findings of this round (defects #67–#70, engine halt latch, host
  timer / per-symbol rule / caps, tracker accounting) are listed in
  `docs/EA_BUG_AUDIT.md`, "Eighth pass"; the tracker's parse/accounting/verdict
  contract is mirrored by `tests/test_portfolio_tracker.py` (15 tests).
