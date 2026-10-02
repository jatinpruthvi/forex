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

Compile the folder once (MetaEditor 64 CLI) and treat any error as a stop:

```powershell
$me = "C:\Program Files\Fusion Markets MetaTrader 5\metaeditor64.exe"
Get-ChildItem "<repo>\MQL5_Master\Experts\additionalEAs\*.mq5" | ForEach-Object {
    & $me /compile:"$($_.FullName)" /log
}
Get-ChildItem "<repo>\MQL5_Master\Experts\additionalEAs\*.log" |
    Select-String -Pattern ": error" -List   # must print nothing
```

This is the one verification the repository's static audit **cannot** do on
Linux (see `docs/EA_BUG_AUDIT.md` → Known limitations). The sweep below re-checks
it indirectly: an EA that fails to compile produces **no result row**.

## Stage 1 — headless sweep of all 65 (the answer to "how do I even run 65?")

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

## Stage 3 — forward/demo deployment (only for the EAs that passed)

This is where the "65 charts" question really bites, and where the options are:

| Option | What it gives | Cost |
|---|---|---|
| **A. Multi-terminal** (5–10 portable MT5 instances, ~10–15 charts each, unique magics already assigned) | works today, keeps every EA in its own chart/process | manual chart management; RAM/CPU grows with instances; portfolio risk is *not* aggregated |
| **B. Template launcher** (script opens N charts in one terminal and applies per-EA `.tpl` templates that carry the EA + inputs) | one terminal, all 65 running, charts can be tiled/hidden | MT5 template format must be verified per build; still 65 charts internally; still no portfolio risk aggregation |
| **C. Portfolio EA** (one EA on ONE chart hosting many strategies, each with its own magic/risk/sleeves) | one chart, one tester run for the whole book, true portfolio-level risk caps, per-sleeve attribution | a real engine refactor: all engine state is global today (`g_eaCfg`, `g_eaInd`, `g_eaTrack`, `g_eaExec`, `g_eaRisk`), so it must become per-strategy objects — engine + generator template work, then a re-run of the full audit |

Option **A** is the zero-code route for a first demo. Option **C** is the right
destination if you intend to run many of these strategies together — several
source documents actually *assume* portfolio-level correlation/risk caps, which
individual EAs cannot enforce across each other.

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

## Why this is better than charts

1. **No chart limit** — the tester needs none; you can sweep all 65 unattended.
2. **Machine-readable** — the verdict table is generated, not eyeballed.
3. **Reproducible** — the same `.ini` + `.set` reproduce a run exactly.
4. **Compile check included** — missing rows are failures, not oversights.
5. **Honest** — one symbol per run is stated, not hidden; Stage 2 covers the rest.
