# portfolio-EA — all 65 engines on one chart + a separate tracker

Two EAs, one boundary:

| EA | File | Chart | Job | Trading |
| --- | --- | --- | --- | --- |
| **AllEnginesEA** | `build/AllEnginesEA.mq5` (generated) | 1 chart | runs **all 65 engines** in one program: registry, per-engine state switch, on/off switches, identity tags | yes |
| **PortfolioEA** | `src/PortfolioEA.mq5` (hand-written) | any chart, or a second chart | **tracks per-engine performance** and writes the report you use to decide what to switch off | **never** (read-only) |

MT5 allows one EA per chart, so AllEnginesEA is the only way to get a genuinely
single-chart book; PortfolioEA is the dashboard, deliberately kept out of the
trading program.

```
portfolio-EA/
├── gen_portfolio_ea.py      reads the 65 delivered EAs + engine (READ-ONLY) -> build/
├── verify_portfolio.py      723 static checks (freshness, hashes, policy, tags, boundary)
├── PLAN.md                  the design + the decisions taken (read this first)
├── src/
│   └── PortfolioEA.mq5      the tracker EA (independent, no engine include)
├── README.md
└── build/                   GENERATED - do not hand-edit
    ├── AllEnginesEA.mq5              the trading host (one attach)
    ├── PortfolioStrategies.mqh       65 strategy classes + 65 tag wrappers
    ├── engines.csv                   magic -> tag -> engine -> switch  (for the tracker)
    ├── STRATEGY_REGISTRY.md          the same table, human-readable
    ├── strategy_registry.csv         and machine-readable
    ├── portfolio_manifest.json
    └── originals.sha256              hashes of every original file read
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

That rule is **already the engine's behaviour** (`EA_SelectPlan`):

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

Engines listed in `InpKeepDeliveredPolicy` (**default `"2006"`** — the intentional
one-symbol ladder) keep their delivered policy. Per-engine caps can be capped
lower with `InpMaxPerEngine`.

Book-level guards (off by default; raise the risk scale and switch them on as you
prefer): `InpMaxBookPositions`, `InpMaxBookPerSymbol`, `InpBookRiskPct`. Context:
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

* net closed P/L, trades, wins/losses, win %, **max closed drawdown per engine**;
* open positions and floating P/L per engine;
* a **verdict** you can act on: `DROP` (≥ `InpMinTrades` and net negative),
  `REVIEW` (expectancy ≤ 0 or DD ≥ `InpReviewDdPct`), `TOO_FEW`, `KEEP`;
* writes `MQL5\Files\PortfolioEA\performance.csv` (includes the `switch` column —
  the exact input name to untick), and draws an optional on-chart panel sorted by
  net.

Install: copy `build/engines.csv` **and** the whole `build/` folder into
`<data>\MQL5\Files\PortfolioEA\` (for the launcher/templates), put
`src/PortfolioEA.mq5` in `<data>\MQL5\Experts\` (or any subfolder), compile, and
attach it to a chart with `InpDaysBack` set to your demo window.

## Build and deploy

```bash
python3 portfolio-EA/gen_portfolio_ea.py        # write build/
python3 portfolio-EA/verify_portfolio.py        # 723 checks
```

On Windows/MT5:

1. engine headers already in `<data>\MQL5\Include\` (the 65 EAs need them too);
2. copy `build/AllEnginesEA.mq5` **and** `build/PortfolioStrategies.mqh` into
   `<data>\MQL5\Experts\portfolio\` and compile `AllEnginesEA.mq5`;
3. copy the rest of `build/` (`engines.csv`, registry files) into
   `<data>\MQL5\Files\PortfolioEA\`;
4. attach `AllEnginesEA` to **one** chart (Algo Trading ON) — demo first;
5. compile + attach `PortfolioEA.mq5` on another chart to watch per-engine results.

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

* `gen_portfolio_ea.py` — **run**: 65 engines, 860 inputs as constants, 65 tag
  wrappers, registry + engines.csv + policy override + book caps.
* `verify_portfolio.py` — **723/723 checks pass** (freshness, originals by hash,
  switches, tags/wrappers, policy override, registry/engines.csv completeness,
  **no dashboard or file I/O in the trader**, **no trading API in the tracker**,
  repo checkers clean).
* **Not verified: MQL5 compilation** — no MetaEditor on Linux. Compile
  `AllEnginesEA.mq5` and `PortfolioEA.mq5` on Windows; anything the compiler
  reports is fixed in `gen_portfolio_ea.py` or `src/`, never in `build/`.
