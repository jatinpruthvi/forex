# portfolio-EA — the whole book on **one chart**

MT5 attaches exactly one EA per chart. The launcher
(`validation/mt5_harness/gen_launcher.py` + `MQL5_Master/Scripts/PortfolioLauncher.mq5`)
removes the *manual* work but still ends up with 65 charts. This folder is the
other answer: **one program, one chart, all 65 strategies**, generated as new
files from the delivered EAs.

## Nothing original is touched

* The 65 delivered EAs are **read only** — `build/originals.sha256` records the
  hash of every file this generator reads, and `verify_portfolio.py` re-checks
  them, so any accidental edit to an original is detected.
* `MQL5_Master/Include/*.mqh` (the engine) is **read only** too, and is included
  unchanged.
* Everything produced lives in `portfolio-EA/`.

```
portfolio-EA/
├── gen_portfolio_ea.py      reads the 65 EAs + the engine, writes build/
├── verify_portfolio.py      207 static checks (deterministic, hashes, coverage)
├── README.md                this file
└── build/                   GENERATED - do not hand-edit
    ├── PortfolioEA.mq5               the host (registry + state switch + scheduler)
    ├── PortfolioStrategies.mqh       65 strategy classes, one namespace
    ├── portfolio_manifest.json       index / class / magic / tf / symbols per strategy
    └── originals.sha256              hashes of every original file read
```

## How it works

1. **Registry** — one `new P<magic>_<Class>()` per delivered EA; magics are the
   delivered ones, unchanged (so results, tracking and the tester reports stay
   comparable with the standalone EAs).
2. **State switch** — the engine keeps its state in globals (`g_eaCfg`,
   `g_eaSymbols`, `g_eaInd`, `g_eaTrack`, `g_eaStatSym`, the news cache…). The
   host snapshots all of it per strategy, loads it before that strategy's tick
   and saves it afterwards. `formula` — see `PortLoadState` / `PortSaveState`.
3. **Risk + executor** — their state is private, but both persist it to
   magic-scoped GlobalVariables and reload it in `Init()`, so a switch calls the
   same path a terminal restart uses (`g_eaRisk.Init(); g_eaExec.Init();`).
4. **Scheduler** — per tick, a strategy is only processed when it has exposure
   (open position/pending with its magic) or one of its symbols has a new bar.
   Without that, 65 strategies × up to 8 symbols would rebuild contexts on every
   tick for nothing.
5. **Result rows** — `EA_Deinit` per strategy calls the tester-only
   `EA_TestReport()`, so one portfolio backtest still produces **one row per
   strategy** for `parse_results.py` / `compare_results.py` (65 rows, 65 EAs).

## Build and deploy

```bash
python3 portfolio-EA/gen_portfolio_ea.py        # write build/
python3 portfolio-EA/verify_portfolio.py        # 207 static checks
```

Then on the Windows/MT5 machine:

1. The engine headers must already be in `<data>\MQL5\Include\` (the 65 EAs need
   them there too, so this is normally already true).
2. Copy `portfolio-EA/build/PortfolioEA.mq5` **and** `PortfolioStrategies.mqh`
   into `<data>\MQL5\Experts\portfolio\`.
3. Compile `PortfolioEA.mq5` in MetaEditor (F7).
4. Attach it to **one** chart, Algo Trading ON.

Inputs: `InpRiskScale` (multiplies every strategy's delivered `riskPct`),
`InpOnlyMagics` (run a subset, e.g. `2035,2027`), `InpQuietInit`, `InpSummary`.
Per-strategy parameters are the delivered defaults, baked in as
`P<magic>_…` constants — a single program cannot expose 860 inputs. To change
one, edit the constant in `build/PortfolioStrategies.mqh` (regenerating later
overwrites it) or keep running that strategy standalone.

## Fidelity — what is exact and what is not

| Area | Status |
| --- | --- |
| Strategy logic | **exact** — class bodies copied verbatim; only identifiers are prefixed |
| Config, symbols, timeframe, risk, magic | **exact** (delivered defaults; `InpRiskScale` is a deliberate multiplier) |
| Positions, partials, break-even, trailing, session/news gates | **exact** — same engine functions, same magic |
| Risk anchors (day/week/month floors, HWM, qualifying days, halts, loss-streak pause) | **exact** — GlobalVariables are keyed by magic and reloaded on switch |
| Indicator handles | **exact** — one set per strategy per symbol; identical parameters share the terminal's global indicator cache |
| Spread/slippage/outcome rings | **shared, on purpose** — they are symbol/market statistics, not strategy state (keyed by symbol) |
| Per-day request counter (`m_requestsToday`) | **resets on each switch** — only 4 EAs set `maxRequestsPerDay`, so their caps effectively stop binding. Fixable with the accessor below |
| Deal cursor (`m_lastOutDeal`) | resets on switch; **inert here** — 0 of 65 EAs enable `lossStreakPause`, the only consumer |
| News cache | snapshotted per strategy, capped at `PORT_NEWS_MAX` (512 events per strategy); longer calendars truncate (logged) |

The two "resets" are memory-only counters in the risk governor. The clean fix is
a 3-line accessor on the governor (snapshot/restore) — deliberately **not**
added, because that would mean editing the engine. If you want it, say so and it
becomes an opt-in overlay file plus one `#include` line.

## Status

* `gen_portfolio_ea.py` — **run**: 65 strategies, 860 inputs converted to
  constants, 0 enum collisions, registry and state coverage verified.
* `verify_portfolio.py` — **207/207 checks pass** (fresh-generation equality,
  originals unchanged by hash, no bare input identifiers, brace balance,
  registry/manifest agreement, complete save/restore coverage, repo checkers
  clean on the generated files).
* **Not verified: MQL5 compilation.** There is no MetaEditor on the Linux
  machine this was built on. Compile step 3 above is the real test; if the
  compiler complains, send the messages — the fix belongs in
  `gen_portfolio_ea.py` (the generator), never in `build/`.

Related: `MQL5_Master/Scripts/PortfolioLauncher.mq5` (65 charts, one attach),
`validation/mt5_harness/README.md` (validation *without* any charts),
`docs/EA_VALIDATION_PLAYBOOK.md` (the whole plan).
