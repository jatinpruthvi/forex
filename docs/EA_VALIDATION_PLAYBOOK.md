# EA Validation Playbook — how to validate all 65 implemented EAs

**Short answer:** don't open 65 charts. MT5 allows **one EA per chart**, and
65 charts of M1/M5 noise is neither readable nor automatable. Validation belongs
in the **Strategy Tester**, which runs an EA headlessly and can be scripted — one
config file per EA, 65 sequential runs, one result table. Forward/demo running
comes **after** the survivors are known, and even then there are better options
than 65 charts.

Everything described here is implemented in
[`validation/mt5_harness/`](../validation/mt5_harness/README.md) plus
`MQL5_Master/Scripts/UniversePreflight.mq5`.

---

## Stage 0 — compile everything (5 minutes)

**This is the first thing to run on Windows**, and the one verification the
repository's static audit **cannot** do on Linux (see `docs/EA_BUG_AUDIT.md` →
Known limitations): nothing in the delivery has ever been through the MQL5
compiler. Treat any error as a stop and send the log.

One command compiles all 67 programs — the 65 delivered EAs, `AllEnginesEA` and
`PortfolioEA` — and prints a per-file error/warning line plus a total:

```powershell
# after copying the EA into <data>\MQL5\Experts\ (see portfolio-EA/README.md)
.\validation\mt5_harness\compile_all.ps1 -Mql5 "C:\Users\you\AppData\Roaming\MetaQuotes\Terminal\<ID>\MQL5"
```

Exit code 0 = every file compiled (`/log` written by MetaEditor); exit 1 = at
least one error, with the first errors printed; exit 2 = the files are not in
that `MQL5` folder yet. `metaeditor64.exe` is auto-detected under
`C:\Program Files` / `%LOCALAPPDATA%\Programs`, or pass `-MetaEditor`.

The safety net for a missed compile is the sweep below: an EA that fails to
compile produces **no result row**, and the summary lists the EAs with no row.

Multi-line messages in the delivery are written as explicit `"a " + "b"`
concatenation, never as two adjacent literals: adjacency is the one MQL5
construct the Linux side could not verify, so the verifier now bans it outright
(0 occurrences in the host, the tracker and all five headers).

## Stage 0b — build the news calendar (once)

Six delivered engines (3102, 3104, 3105, 3106, 3107, 3109) ship the red-folder
gate **fail-closed**: without a calendar source they take no new entries at all —
in the tester that shows up as a FAIL row with zero trades, which looks like a
broken strategy rather than a missing file.  **Live** they now read MT5's own
economic calendar (`InpNewsCalendar` in the portfolio EA), but the **Strategy
Tester has no calendar data** (the API returns 0 / error 4014 there), so a sweep
still needs the file.  Build it before Stage 1:

```powershell
# copy the exporter into the terminal, then (MetaEditor) compile it and run it:
copy MQL5_Master\Scripts\ExportRedNews.mq5 "<data>\MQL5\Scripts\"
& $me /compile:"<data>\MQL5\Scripts\ExportRedNews.mq5" /log
# then drag ExportRedNews onto any chart once - it writes
#   <data>\MQL5\Files\the5ers_red_news.csv  from the terminal's own calendar
```

It only reads the economic calendar and writes that one file (never trades).  The
format is the engine's: `date,time,currency,impact` (`2026.10.02,13:30,USD,HIGH`,
UTC, `HIGH` or a number ≥ 2, currency matched against the engine's symbol list,
`ALL` for every symbol).

The file starts with a `#timezone=server` marker because MT5 calendar times are
**server time** (not UTC); the engine follows the marker, and a hand-written file
without it keeps the delivered UTC meaning.  Do not mix the two.

**Cover your tester window, not just "now".**  The sweep below runs a fixed range
(the generated configs default to `2025.01.01 .. 2026.09.30`).  Set the script's
`InpFromDate`/`InpToDate` to those same dates (leave them empty to fall back to
the relative `InpDaysBack`/`InpDaysForward` window).  A calendar exported "from
now" would leave the fail-closed engines blind to every historical event in the
sweep — they would block entries they should not see.  Re-run the export whenever
you extend the tester window.  No calendar at your broker?  The runner-up is the
hand-fill template `validation\mt5_harness\files\the5ers_red_news.csv.template`;
the fallback is to untick those six engines.

The Strategy Tester reads the same `MQL5\Files`, so one export serves both the
sweep and the live/demo charts.

## Stage 1 — headless sweep of all 65 (the answer to "how do I even run 65?")

**Sweep mode matters after `EA_MAX_SYMBOLS` went 8 → 10.**  The default sweep runs
one symbol per EA (65 configs, unchanged).  Four engines now trade 9–10 symbols,
so their faithful coverage is the wide sweep:

```bash
python3 validation/mt5_harness/gen_tester_configs.py --symbols wide   # 71 configs: +6 runs
python3 validation/mt5_harness/gen_tester_configs.py --symbols all    # one run per (EA, symbol)
```

`wide` adds exactly the symbols the old cap used to truncate (magics
2031/2034/3111/2040 in the portfolio = the four engines above; `verify_portfolio.py`
proves the coverage on every run).  Each multi-symbol run writes its own result row
— the tester report file now carries the test symbol in its name
(`<strategy>_<magic>_<symbol>.csv`) — and `parse_results.py` reports one row per
**(EA, symbol)** instead of collapsing them into one.

```bash
python3 validation/mt5_harness/gen_tester_configs.py \
    --terminal "C:/Program Files/Fusion Markets MetaTrader 5/terminal64.exe" \
    --from 2025.01.01 --to 2026.09.30 --model 1
```

then on Windows:

```powershell
cd <repo>\validation\mt5_harness\out ; .\run_all.ps1
```

Each run is `terminal64.exe /config:out\configs\<EA>.ini` — Strategy Tester,
**no chart**, `ShutdownTerminal=1`. Every EA writes one row to
`Common\Files\EA_TestReports\<strategy>_<magic>.csv` (the dump is built into the
engine: `EA_TestReport()` in `EACommon.mqh`, tester-only, no effect live).

Summarise on any machine:

```bash
python3 validation/mt5_harness/parse_results.py
open validation/mt5_harness/out/portfolio_summary.md
```

Result: a 65-row table — trades, win/loss, net, PF, expectancy, equity DD %,
recovery factor, Sharpe — with **PASS/WARN/FAIL** verdicts, worst first, plus a
separate list of EAs that produced **no row** (compile failure / crash / no
deinit). That last list is the compile check, automated.

**Before the sweep, run the preflight once** (drag
`MQL5_Master/Scripts/UniversePreflight.mq5` onto any chart): it tells you which
of the EAs' symbols your broker actually offers and which index alias it uses.
A symbol the broker lacks is skipped-and-logged by the engine — that sleeve will
simply be inert, which otherwise looks like "the EA doesn't trade".

## Stage 2 — real ticks for the survivors

Re-run only the PASS/WARN EAs with `--model 4` (every tick based on real ticks)
and, for multi-symbol EAs, once per key symbol:

```bash
python3 validation/mt5_harness/gen_tester_configs.py --model 4 \
    --only EA_TRIAD_SURVIVE,EA_studyarena_round11_contestant_f
```

(Each extra config is just a copy with a different `Symbol=`; the manifest lists
every EA's universe.)

## Stage 2b — compare the EAs against each other

A sweep tells you which EAs work. It does **not** tell you which ones belong in one
book: three EAs on the same symbol with the same session produce the same risk
three times. `validation/mt5_harness/compare_results.py` answers that from the
tester reports the sweep already writes:

* pairwise **daily-PnL correlation** and a **redundancy list** (correlated pairs on
  a shared symbol — keep the better one, or halve both);
* **combined portfolio** net / max DD / Sharpe, equal-weight and vol-scaled;
* **leave-one-out** table: what the book looks like without each EA.

```bash
python3 validation/mt5_harness/compare_results.py --reports "<data>\Reports\EA_Harness"
```

## Stage 3 — forward/demo deployment without attaching 65 EAs

Attaching 65 EAs by hand is the pain this stage removes. Two ways, in order of
effort:

### A. One attach, all 65 running — the launcher (built, in this repo)

`MQL5_Master/Scripts/PortfolioLauncher.mq5` + templates generated by
`validation/mt5_harness/gen_launcher.py`:

```bash
# once, in MT5: attach any EA to a chart -> right-click -> Template -> Save
# Template -> "EA_Launch_Base"  (so the permissions in the file come from YOUR
# terminal, not from a guess)
python3 validation/mt5_harness/gen_launcher.py \
    --base-tpl "<data>\MQL5\Profiles\Templates\EA_Launch_Base.tpl" --groups 1
# copy validation/mt5_harness/out/launch/*  ->  <data>\MQL5\Files\EA_Launch\
```

Then **attach `PortfolioLauncher` once** (Algo Trading ON, "Allow Algo
Trading" ticked) and press OK:

* **START** opens one chart per EA and attaches it from its template with the
  EA's inputs already set. Re-running is safe — EAs already running are skipped.
* **STOP** closes every chart running one of these EAs.
* **DRYRUN** reports only.
* Results: `MQL5\Files\EA_Launch\launch_status.csv` + the Experts tab.
* `--groups N` splits the plan so you can spread the load over N terminals
  (`InpGroup=<n>` in each) — useful for memory/UI/stability and to isolate a
  crashing terminal, not for CPU: **MT5 already gives every EA its own thread**
  (chart limit is 200), so one terminal runs 65 EAs comfortably.

Honest limit: this still ends up with 65 charts inside the terminal (MT5's rule,
not a choice) — what it removes is 65 *manual* attaches, and it makes the set
reproducible. Charts are minimised automatically and need no attention.

### B. One chart for the whole book — portfolio EA (built in `portfolio-EA/`)

The engine was written for this: strategies are classes (`CEAStrategy` with
virtual `Configure` / `BuildPlan` / `Manage` / `AllowTrading` / `RankSetup` /
`LotsMultiplier`), and every position, order and history query filters by
`g_eaCfg.magic` — so strategies are already isolated from each other by magic,
and the base class even has a "portfolio hook" (`RankSetup`, collision ranking).

What is missing is the *host*: the engine holds one active strategy
(`g_eaStrategy`) and one config (`g_eaCfg`), plus per-run state
(`g_eaLastSignalBar`, `g_eaTrack`, `g_eaRisk`, indicator handles, spread rings).
A portfolio host therefore needs:

1. a container of N strategies × N settings, with a **context switch** per tick
   (`g_eaCfg`/`g_eaStrategy` set before each strategy's manage/plan/execute
   cycle);
2. per-strategy instances of the stateful singletons (tracks, risk governor,
   new-bar marker, indicator/spread caches) — most already key off
   `g_eaCfg.magic`, so this is mostly mechanical;
3. generator support to emit **one** combined `.mq5` (all 65 classes in one file,
   `OnTick` looping) — the generator already emits all 65 as source, so this is
   a template change, not new strategy code;
4. a full re-run of the six-pass audit on the modified engine.

**Status: implemented as new files in [`portfolio-EA/`](../portfolio-EA/README.md)** — `AllEnginesEA.mq5` runs all 65 engines on one chart, `PortfolioEA.mq5` is the separate read-only tracker that reports per-engine net/DD/win-rate and the `InpRun_<magic>` switch to flip —
the 65 delivered EAs and the engine are read-only inputs (hashed and re-verified);
the folder holds the generator, the verifier (207 checks) and the generated host.
Not compiled yet (no MetaEditor here), so compile it before trusting it live.

Payoff: one chart, one attach, **one tester run for the whole book**, and true
portfolio-level caps across sleeves (several source documents assume
portfolio-level correlation/risk caps that individual EAs cannot enforce across
each other). Cost: a real engine project, not a script — worth doing if these
EAs are going to run together in size.

## Interpreting results honestly

* **0 trades** → not a bug by itself: the EA's gates (session, ADX, spread,
  news, day-of-week) blocked everything in that period. Check the tester journal
  for the EA's skip logs, and re-run on its documented primary session/symbol.
* **< 30 trades** → statistically meaningless; extend the period.
* **Good PF but huge DD** → position sizing, not signal quality; check
  `stats`/`riskPct` and the DD throttle of that EA's document.
* **All 65 positive** → do Stage 2 before believing any of it (model 1 is a
  fast approximation).
* Result rows are per **single run**; the summary keeps the newest row per EA,
  so you can re-run freely.
* **Global variables in the tester are emulated and per-agent**, not the
  terminal's (MQL5 documentation and forum consensus): a backtest can never
  disturb the anchors a live/demo terminal holds, and the emulated store dies with
  the agent. The engine's keys are magic-scoped (`EA_<magic>_...`) and each of the
  65 runs uses its own magic, so the sweep cannot cross-contaminate. If you repeat
  the *same* EA over the *same* start date, restart the terminal/agent first if you
  want a byte-identical repeat (the emulated day stamp could otherwise carry that
  day's request counter into the second run).

## Why this is better than charts

1. **No chart limit** — the tester needs none; you can sweep all 65 unattended.
2. **Machine-readable** — the verdict table is generated, not eyeballed.
3. **Reproducible** — the same `.ini` + `.set` reproduce a run exactly.
4. **Compile check included** — missing rows are failures, not oversights.
5. **Honest** — one symbol per run is stated, not hidden; Stage 2 covers the rest.
