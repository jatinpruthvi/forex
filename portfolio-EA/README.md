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

The trading program **draws nothing and writes nothing** at run time. The only
file it touches is the optional news calendar, read by the six engines that gate
on it (deploy step 4), plus the Strategy Tester's per-engine report row — both are
delivered engine behaviour that the standalone EAs have too, not dashboard logic.

```
portfolio-EA/
├── build/AllEnginesEA.mq5   COMPILE THIS - one EA, all 65 strategies inside it
├── src/PortfolioEA.mq5      COMPILE THIS - the tracker EA (standalone)
│
├── PLAN.md                  the design + the decisions taken (read this first)
├── gen_portfolio_ea.py      build tool: delivered 65 EAs -> the one EA file
├── verify_portfolio.py      1 775 static checks (freshness, hashes, policy, tags,
│                              identifier hygiene, capacity, shared-engine state)
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

Precedence: whitelist → `InpRun_<magic>` → blacklist.

**A switch stops new entries, never the management of open trades.** A
switched-off engine is still initialised and keeps running its exits — break-even,
partials, trail, time stop, session flats, halt flatten — for the positions it
already holds; only `PortEntryGate` refuses new ones. That is what makes "run the
demo, then switch off what did not work" safe: you never orphan a live position by
unticking a box. (The EA must be reloaded for input changes, and it will say
`N open for new entries, M switched off` in the Experts log at startup.)

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
your demo window. The folder for the report is created automatically. Without
`engines.csv` the tracker still works — it just shows
magic numbers instead of engine names.

## Build and deploy

On Windows/MT5:

0. use a **hedging** account. The program checks `ACCOUNT_MARGIN_MODE` at init and
   refuses to start on a netting account: netting merges two engines' positions on
   one symbol into a single ticket, so magic identity and per-engine P/L would be
   lost. On netting, run the individual EAs one chart at a time instead;
1. engine headers already in `<data>\MQL5\Include\` (the 65 EAs need them too);
2. copy **`build/AllEnginesEA.mq5`** into `<data>\MQL5\Experts\` and compile it
   (nothing else has to go with it);
3. copy `build/engines.csv` into `<data>\MQL5\Files\PortfolioEA\`;
4. attach `AllEnginesEA` to **one** chart (Algo Trading ON) — demo first.
   **Six engines fail closed on news.** 3102, 3104, 3105, 3106, 3107 and 3109 ship
   the red-folder gate with `newsFailClosed`, so without
   `MQL5\Files\the5ers_red_news.csv` they log `FAIL CLOSED` and take **no new
   entries** (the tracker shows them `TOO_FEW` forever). The calendar is one event
   per row — `date,time,currency,impact`, e.g. `2026.10.02,13:30,USD,HIGH`; times
   are UTC, impact ≥ 2 or `HIGH` counts, and `currency` is matched against the
   engine's symbol list (`ALL` = every symbol). Each event blocks a 30-minute
   window (default) around it. Install the file, or switch those six off;
5. compile + attach `src/PortfolioEA.mq5` on another chart to watch per-engine
   results.

Only if you change a strategy or the host do you need the build tools again:

```bash
python3 portfolio-EA/gen_portfolio_ea.py        # rewrite the compiled EA file
python3 portfolio-EA/verify_portfolio.py        # 1 775 checks
```

If you hand-edit `build/AllEnginesEA.mq5`, keep the edited copy somewhere else
first: re-running the generator overwrites it. Hand edits belong in the delivered
EA (for logic) or in `gen_portfolio_ea.py` (for the host).

## Known limits of a 65-engine program

* **`EA_MAX_SYMBOLS` is 8 per engine.** Four delivered universes list 9-10 symbols
  (magics 3111, 2031, 2034, 2040); the tail is never traded by the delivered EA
  either. The engine now logs the names it drops, and `verify_portfolio.py`
  lists the four. Widening the cap or trimming the universes changes delivered
  behaviour, so it is left to the owner (say the word and I will do either).
* **Indicator memory.** One program shares the terminal's indicator cache, so the
  book resolves to ~476 indicator instances (34 symbol x timeframe pairs x 14
  handles), not 65 x 8 x 14. Expect a slower first init on a fresh terminal and a
  few hundred MB of history/buffers — keep "Max bars in chart" moderate.
* **Market statistics are pooled.** Spread, fill-slippage and R-outcome rings are
  keyed by symbol and shared by all engines (they measure the market/broker, not
  a strategy). Two engines gate on them (`EA_SymbolSlippageOk`); for those, the
  gate sees the whole book's fills on the symbol.
* **Per-day request budget, deal cursor and trade spacing** are per engine and now
  survive restarts within the same trading day (`EA_<magic>_ReqToday`,
  `EA_<magic>_LastOutDeal`, `EA_<magic>_LastTrade`). 53 engines set
  `minSecondsBetweenTrades`, so a shared stamp would have dropped their signals.
* **The account is one account.** 24 engines run daily-loss/drawdown limits and
  8 run weekly/monthly ones; those percentages are measured on the **shared
  account equity**, so a book-level drawdown trips every one of them at once
  (it is a stricter, book-wide brake than the single-EA backtests show). The halt
  also clears with the clock day — the rollover is now performed by the engine's
  `Init()` as well as `OnTick()`, exactly once per day, so a running terminal no
  longer keeps an engine halted forever.
* **Margin and free funds are shared.** 65 engines on one account compete for the
  same margin, and the book caps (`InpMaxBookPositions`, `InpMaxBookPerSymbol`,
  `InpBookRiskPct`) are the only aggregate limits; fund the demo account for the
  whole book, not for one engine.
* **Six engines need the red-folder calendar** (see the deploy step): fail-closed
  by design in the delivered EAs.
* **The `switch` column of `performance.csv` is the input name to untick**
  (`InpRun_<magic>`), not the live switch state — the trader is deliberately
  single-file and publishes nothing, so the tracker cannot read inputs.

## Fidelity — exact and not exact

| Area | Status |
| --- | --- |
| Strategy logic | **exact** — class bodies copied verbatim; only identifiers are prefixed |
| Config, symbols, timeframe, risk, magic | **exact** delivered defaults (`InpRiskScale` is a deliberate multiplier) |
| Position management (partials, BE, trails, session/news gates) | **exact** — same engine functions |
| Risk anchors (day/week/month, HWM, halts) | **exact** — magic-keyed GlobalVariables; the day anchor is frozen once per clock day and the rollover runs exactly once, from `Init()` or `OnTick()` |
| Governor state across the 65 engines | **exact** — `Init()` re-derives every member from that engine's magic-scoped state, so no halt, day lock or spacing stamp leaks to the next engine |
| Order policy | host override described above; `2006` keeps the delivered ladder |
| Spread/slippage/outcome rings | **shared on purpose** — symbol/market statistics, not engine state |
| Per-day request counter | **exact** — persisted per magic (`EA_<magic>_ReqToday` + day stamp) |
| Deal cursor, trade spacing | **exact** — persisted per magic (`EA_<magic>_LastOutDeal`, `EA_<magic>_LastTrade`) |
| Account-wide % limits (daily/weekly/monthly DD, HWM, profit target) | **book-wide** — measured on the shared account equity; identical to the single-EA case only when the book runs alone on its account |

## Status

* `gen_portfolio_ea.py` — **run**: 65 engines inlined into the single EA file,
  860 inputs as constants, 65 tag wrappers, registry + engines.csv + policy
  override + book caps. Enum types of the 6 engines that declare them are
  prefixed like every other per-engine identifier (defect #67).
* `verify_portfolio.py` — **1 775/1 775 checks pass** (freshness, originals by
  hash, switches, tags/wrappers, policy override, registry/engines.csv
  completeness, **one-file EA: every strategy inlined verbatim**, **identifier
  hygiene**: every emitted type exists, no top-level name twice, every
  `cfg.magic` resolves to its registry magic, **no dashboard or file I/O in the
  trader**, **no trading API in the tracker**, **the shared risk governor
  re-derives every member per engine**, **hedging-only guard**, repo checkers
  clean).
* **Not verified: MQL5 compilation** — no MetaEditor on Linux. Compile
  `AllEnginesEA.mq5` and `PortfolioEA.mq5` on Windows; anything the compiler
  reports is fixed in `gen_portfolio_ea.py` or `src/`, never in `build/`.
* Deep-review findings are listed in `docs/EA_BUG_AUDIT.md`: **eighth pass**
  (#67-#70: a prefixed enum type that was never declared, the halt-latch, the
  tracker's entry costs, magic 3117's duplicated symbol) and **ninth pass**
  (#71-#77: switched-off engines orphaning open trades, the silent 8-symbol
  truncation, per-position cost carry, the request budget and loss cursor leaking
  between engines, the 16-slot market-statistics table, and the report folder),
  **tenth pass** (#78-#84: the daily floor ratcheting to the intraday equity peak,
  the clock-day rollover being swallowed in the host, a halt/day-lock/spacing-stamp
  leaking from one engine to the next, the missing netting-account guard, and a
  news log that said "inert" while the engine was blocked).
  The tracker's parse/accounting/verdict contract is mirrored by
  `tests/test_portfolio_tracker.py` (16 tests).
