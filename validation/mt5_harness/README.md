# MT5 Strategy Tester harness — validating the 65 implemented EAs

**The problem:** MetaTrader 5 attaches **exactly one EA per chart**, so validating
65 EAs by opening 65 charts and attaching 65 robots is not practical (and 65
charts of M1/M5 noise is unreadable anyway).

**This harness:** the Strategy Tester runs an EA **with no chart at all**, and it
can be driven from the command line, one config file per EA. Each run writes a
machine-readable result row, so a full 65-EA sweep ends with one table — no
charts, no clicking.

```
                    ┌─ gen_tester_configs.py ──► out/configs/<EA>.ini  (65 files)
 EA specs ──────────┤                            out/sets/<EA>.set
 (gen_additional_    │                            out/run_all.ps1 | run_all.bat
  eas.py)            │                            out/manifest.json
                    └─ out/symbols_preflight.txt ──► MQL5_Master/Scripts/UniversePreflight.mq5

 Windows:  run_all.ps1  ──►  terminal64.exe /config:<EA>.ini   (65 sequential runs)
                                    │
                                    ▼
              Common\Files\EA_TestReports\<strategy>_<magic>.csv   (written by EA_TestReport)
                                    │
                       parse_results.py ──► out/portfolio_summary.md + .csv
```

## 1. Generate the configs (this machine)

```bash
python3 validation/mt5_harness/gen_tester_configs.py \
    --terminal "C:/Program Files/Fusion Markets MetaTrader 5/terminal64.exe" \
    --from 2025.01.01 --to 2026.09.30 \
    --model 1          # 1 = 1-minute OHLC (fast sweep); use 4 = real ticks for finalists
```

It reads `scripts/gen_additional_eas.py` directly, so the configs cannot drift
from the compiled EAs. Per EA it picks the most liquid symbol of that EA's own
universe (overridable in `SYMBOL_OVERRIDES`) and the EA's documented timeframe.
One EA (`EA_studyarena_round7_contestant_a`) is DAX-only — edit its `Symbol=`
line to whatever alias your broker uses (the preflight script tells you which).

## 2. Preflight the broker's symbols (MT5, one click)

Before any of that, build the news calendar (Stage 0b): six engines fail closed,
so without `MQL5\Files\the5ers_red_news.csv` their tester rows show zero trades.
Compile and run **`MQL5_Master/Scripts/ExportRedNews.mq5`** — it writes that file
from the terminal's own economic calendar. (`validation/mt5_harness/files/`
holds a hand-fill template for brokers without a calendar feed.)

After the `EA_MAX_SYMBOLS` 8 → 10 change, four engines trade 9–10 symbols, so the
one-symbol default sweep no longer covers them: run
`gen_tester_configs.py --symbols wide` (adds exactly the six runs the old cap
truncated) or `--symbols all` (one run per EA × symbol).  Multi-symbol runs keep
separate result rows (the report file name carries the test symbol) and
`parse_results.py` lists one row per (EA, symbol).

Compile and run **`MQL5_Master/Scripts/UniversePreflight.mq5`** once. It reports
every symbol the 65 EAs need, whether your broker offers it, its spread and
contract size, and which index aliases exist (GER40 / DE40 / DAX / …). The
engine **skips and logs** a symbol the broker does not list, so a `MISSING`
entry means "that sleeve is inert here", not "the EA fails".

## 3. Run the sweep (Windows)

```powershell
cd <repo>\validation\mt5_harness\out
.\run_all.ps1          # 65 sequential tester runs; ~10-60 s each at model=1
```

Notes
* The terminal must be **logged in at least once** and have the symbols in
  Market Watch; the first run of a symbol downloads history.
* `ShutdownTerminal=1` makes each run exit and return control to the script.
* If a run produces no CSV, the EA failed to compile, threw, or never
  deinitialised — the parser lists those separately (that is the compile check).

## 4. Summarise (this machine)

```bash
# copy %APPDATA%\MetaQuotes\Terminal\Common\Files\EA_TestReports here, or
python3 validation/mt5_harness/parse_results.py --dir "<path to EA_TestReports>"
```

Produces `out/portfolio_summary.md` (worst first) and `.csv`, with
**PASS / WARN / FAIL** per EA and a list of EAs that produced no row at all.
Thresholds: FAIL = 0/&lt;20 trades or net ≤ 0 or DD ≥ 20 %; WARN = &lt;40 trades,
PF &lt; 1.10, DD ≥ 10 %, expectancy ≤ 0. All overridable:

```bash
python3 validation/mt5_harness/parse_results.py --min-trades 30 --min-pf 1.2 --max-dd 15
```

## 5. Compare the EAs (which are additive, which are duplicates)

```bash
# full comparison, from the tester reports the sweep already wrote:
python3 validation/mt5_harness/compare_results.py \
    --reports "<terminal data folder>\Reports\EA_Harness"

# aggregate-only fallback, if you only kept the result rows:
python3 validation/mt5_harness/compare_results.py --results "<...>\Common\Files\EA_TestReports"
```

`compare_results.py` produces `out/comparison.md` plus three CSVs:

* **Pairwise correlation** of daily PnL (over each pair's common span, missing day =
  no trade = 0; `--min-overlap` controls how many days are required, default 20).
* **Redundancy list** — pairs correlated above `--corr` (default 0.60) that also
  trade the same symbol: these duplicate risk instead of diversifying it. The
  higher-net member is proposed as the keeper.
* **Combined portfolio** — equal-weight and vol-scaled (each EA scaled to the
  median daily volatility) with net, max drawdown and Sharpe, plus per-EA
  "correlation to the book".
* **Leave-one-out** — the book's net/DD/Sharpe with each EA removed, so you can
  see which EAs actually earn their slot.

Verify the maths any time (no MT5 needed): `compare_results.py --selftest`.

## 6. Running the EAs for real — one attach, not 65

Validation is chart-free (above). *Running* them is the part where MT5's
one-EA-per-chart rule bites, so the same folder also generates a launcher:

```bash
# 1. in MT5: attach any EA to a chart (Algo Trading ON)
#    -> right-click -> Template -> Save Template -> "EA_Launch_Base"
# 2. stamp 65 templates from that one file (names + inputs rewritten):
python3 validation/mt5_harness/gen_launcher.py \
    --base-tpl "<data>\MQL5\Profiles\Templates\EA_Launch_Base.tpl" \
    --groups 1
# 3. copy validation/mt5_harness/out/launch/*  ->  <data>\MQL5\Files\EA_Launch\
```

Then attach **`MQL5_Master/Scripts/PortfolioLauncher.mq5`** to one chart
(Algo Trading ON, "Allow Algo Trading" ticked) and press OK:

| Mode | Effect |
| --- | --- |
| START | opens one chart per EA and attaches it from its template; skips EAs that are already running, so it is safe to re-run; skips entries switched off in the plan |
| STOP | closes every chart that is running one of these EAs |
| DRYRUN | reports what it would do, changes nothing |

**Switching an EA off after demo testing:** `launch_plan.csv` column 2 is
`enabled` — set it to `0` for that EA and run START again (delete its chart, or
use STOP first). Column 7 is its magic, the same magic the strategy uses as a
standalone EA and the same one as `InpRun_<magic>` in the
[one-chart portfolio EA](../../portfolio-EA/README.md), so one decision applies
to both routes. `launch_status.csv` records `DISABLED_IN_PLAN` for skipped rows.

Everything is logged to `MQL5\Files\EA_Launch\launch_status.csv` and the
Experts tab. `--groups N` splits the plan into N groups so you can spread the
load over N terminals (`InpGroup=<n>` each). MT5 gives every EA its own thread,
so a single terminal handles 65 EAs fine (chart limit is 200); groups are for
memory/UI/stability, not for CPU.

Permission note (MT5 rule, not ours): an EA attached via `ChartApplyTemplate`
can only trade if the **calling** program has trade permission. That is why
START refuses to run with Algo Trading off — it would give you 65 charts of
mute EAs.

## What the sweep does and does not prove

* It **does** prove each EA compiles, initialises, takes trades under its gates,
  and what its single-symbol performance/DD is over the period.
* One tester run tests **one symbol**. EAs whose document spans several symbols
  (e.g. `EA_TRIAD_SURVIVE`, `round10_opus`, `round11_contestant_f`) are only
  fully validated when the same EA is re-run on each key symbol — add extra
  configs with a different `Symbol=` (the manifest lists each EA's universe).
* Non-chart symbols in a multi-symbol EA are evaluated from their own history
  with less tick precision than the tested symbol. For finalists, re-run with
  `--model 4` (every tick based on real ticks).

See `docs/EA_VALIDATION_PLAYBOOK.md` for the full plan (sweep → real-ticks
finalists → forward demo) and for the one-chart *portfolio EA* option.
