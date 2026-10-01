# Project profile: forex - strategy validation on history data

Repo: `jatinpruthvi/forex`. MT5 Expert Advisors (MQL5) plus a Python research and validation stack that
tests strategies on M5 history for The5ers-style prop-firm challenges.
Facts below were checked against the repo on 2026-09-29 (baseline commit `5b3d349`). Re-check
anything marked **(verify)** before relying on it.

## 1. What the loop is for

**In scope**
- Validate, re-validate, or falsify a strategy or configuration on the repo's history data.
- Change the Python simulator, labs, or tests, when a validation needs it.
- Reproduce a documented result and explain any mismatch.
- Refresh or audit history data (integrity, provenance, forward window).

**Out of scope without approval** (see section 8)
- Declaring a strategy "live-ready", "profitable", or "passes the challenge".
  The loop reports evidence; a human decides whether to trade.
- Editing the EA to change frozen parameters, flipping any `Inp*GatePassed` input, compiling or deploying.
- Replacing or overwriting tracked history data, or mixing data from different sources in one run.

## 2. Read first (DISCOVER)

| Order | File | Why |
|---|---|---|
| 1 | `docs/strategy/progress.md` | Handoff log, frozen EA contract, pipeline commands |
| 2 | `docs/strategy/STRATEGY-ROADMAP.md` | Track A (long-term) vs Track B (fast-track) and the ranking rule |
| 3 | `docs/strategy/FINAL_OPTIMUM_STRATEGY.md` | Current certified champion and its reproduce command |
| 4 | `docs/research/findings/findings_live_friction_audit.md` | The four simulator bugs that once inflated results |
| 5 | The findings file for the lab you touch (`docs/research/findings/findings_<lab>.md`) | Prior results, do not repeat them |
| 6 | `docs/PERSONAL_LIVE_ACCOUNT.md` (only for personal-account questions) | Prop and personal are different problems |

Documents disagree with each other (configurations differ by pair count, commission, caps). Before
comparing any two numbers, confirm both came from the **same configuration** (section 5, rule R9).

## 3. Commands

Python 3.11. The system Python refuses `pip install` (PEP 668), so use a venv outside the repo:

```bash
python3 -m venv /tmp/venv && /tmp/venv/bin/pip install pytest tzdata numpy
```

| Purpose | Command | Notes |
|---|---|---|
| Baseline tests | `/tmp/venv/bin/python -m pytest tests validation/speed_lab -q -p no:cacheprovider` | ~15 s. **Baseline: 200 passed, 1 failed** |
| Data preflight | `python3 .agents/skills/loop-engineering/scripts/preflight_data.py` | stdlib; exit 1 on any integrity failure |
| Reproduce stdlib config | `python3 validation/speed_lab/verify_final_config.py` | ~8 s, prints TEST-window per-pair expectancy and walk-forward table |
| Reproduce champion | `python tools/order_selector.py --confirm --pairfit --compound --risk 0.0175` | Per `FINAL_OPTIMUM_STRATEGY.md`; **(verify)** runtime before scheduling it |
| Sweep/reclaim pipeline | `tools/tick_signal_builder.py` -> `tools/replay_export.py build` -> `tools/triad_validation.py validate` | Exact flags in `docs/strategy/progress.md` section 9 |

**Known baseline failure (not yours to fix silently):**
`tests/test_source_contract.py::SourceContractTests::test_canonical_and_runtime_files_exist` - it looks for
`THE5ERS-CHALLENGE-STRATEGY-V2.md` at the repo root, but the file now lives in `docs/prop_firm/`. Report it
in every REPORT; fix only if the user asks.

Conventions: research sweeps may use numpy; the **final** reproduction of any chosen config must be
**stdlib-only** (the `verify_final_config.py` pattern). Generated CSV/JSON reports stay out of Git
(`.gitignore` covers `validation/*.csv`, `validation/*_report.json`, dumps).

## 4. Data

| Set | Path | Coverage | Source | Volume |
|---|---|---|---|---|
| 4-year M5 (tracked) | `validation/HistoryData/<pair>-m5-2022-09-11_2026-09-11.csv` | 2022-09-11 .. 2026-09-11 | The5ers FSB dumps | 0 in older segment |
| 2-year M5 gate (tracked) | `validation/HistoryData/2-years-data/<pair>-m5-fsb.csv` | Jan 2024 .. Sep 2026 | FSB dumps | non-zero |
| 2-year M1 (tracked) | `validation/HistoryData/m1-data/` | 2024-09-11 .. 2026-09-11 | | |
| CI snapshot | branch `data/m5-history` (`*.csv.gz`) | 2022-09-11 .. latest run | ForexSB mirror (recent ~200k bars) + histdata.com (older gap), built by `.github/workflows/download-history-data.yml` | 0 in the older segment |

Pairs (11): EURUSD GBPUSD EURGBP AUDUSD NZDUSD USDCAD USDCHF USDJPY EURJPY GBPJPY XAUUSD.
CSV: `timestamp_ms_utc,open,high,low,close,volume` with a header row.

**Getting the CI snapshot in the agent sandbox.** Azure blob storage (where `gh run download` and artifact
zips live) is unreachable there. Git hosts work:

```bash
curl -L https://codeload.github.com/jatinpruthvi/forex/tar.gz/refs/heads/data/m5-history | tar -xz -C /tmp
gunzip /tmp/forex-data-m5-history/*.csv.gz        # keep it in /tmp, never in the repo
```

**Measured 2026-09-29 (CI snapshot run 36570042374 vs tracked 4-year set):** the sources agree on
~99.99% of overlapping bars (12-20 differing bars per pair; largest deviations EURUSD 0.00023, USDJPY 0.094,
XAUUSD 2.37; AUDUSD 0.0034 is the largest FX-major outlier). The CI set adds ~3.3k bars per pair after the
tracked set ends (2026-09-13 21:00 .. 2026-09-29 11:55 UTC, about 16 trading days).

Consequences:
- The CI tail (2026-09-13 onward) is the only **never-seen forward window**. Use it as a final
  out-of-sample check, and say plainly it is ~16 trading days (a few dozen trades at most) - a smoke test, not proof.
- Never overwrite tracked CSVs with CI CSVs, and never splice sources inside one run. A different
  source is a different experiment.
- Volume is 0 in the older segment of **both** sets (it turns on around 2024; `preflight_data.py` prints the date).
  A strategy that reads volume cannot be validated on the full 4 years.

## 5. Validation rules (the VERIFY layer)

These come from bugs and inflated results already found in this repo. Each rule names its evidence.

| # | Rule | Evidence in repo |
|---|---|---|
| R1 | **Preflight the data** before any run: strictly increasing timestamps, on the 5-minute grid, no duplicates, valid OHLC, expected coverage. Record which set and hash. | `scripts/preflight_data.py` |
| R2 | **No look-ahead.** Signal uses only completed bars. Entry is the *next* bar's open, or a limit that must be **re-touched** after the signal. ATR and range inputs come strictly from data before the entry window. | Bug B2: 11.5% of signals never re-touched the limit level yet carried 26.7% of P&L. |
| R3 | **Same-bar stop/target ambiguity: report all three bounds** - pessimistic (books the stop), coin-flip, optimistic. **The pessimistic bound is the gate.** A result that only passes optimistically is NOT a pass. | Bug B1; old 60-combo grid: nothing survives the pessimistic bound; `STRATEGY-ROADMAP.md` ranking rule. |
| R4 | **Costs inside every trade**: raw account = 55% of standard spread + $7/lot round turn; per-day pip value from that day's real prices; lots floored to 0.01. Zero-cost runs are diagnostics only. | `validation/speed_lab/engine.py`; findings: ORB "champion" profit was the bugs. |
| R5 | **One account-wide slot** unless the profile of the specific ruleset says otherwise, with the daily-loss and floor governors active. | Bug B3: overlapping positions on 249/1045 days. |
| R6 | **Time handling**: session windows in `Europe/London` wall clock (DST-aware), days bucketed by London date; the firm's daily loss uses the **server** day, UTC+3 (`SERVER_OFF_H` in the engine). Get London offsets from `zoneinfo`; never hard-code them. | `FINAL_OPTIMUM_STRATEGY.md` section 2; `validation/speed_lab/test_ea_server_offset.py`. |
| R7 | **Split discipline**: select on TRAIN `2022-09-11 -> 2024-09-11` only. TEST `2024-09-11 -> 2026-09-11` is looked at **once per frozen candidate**. Any window already used for ranking (the 2-year gate overlaps TEST) counts as burned for that purpose. | `verify_final_config.py` header; `STRATEGY-ROADMAP.md`. |
| R8 | **Multiple testing**: count every configuration tried and report N next to the winner. Write the trial budget at SCOPE; extending it after seeing TEST results needs approval. `validation/triad_v2_1_registry.json` (160 configs) is frozen. | Registry marked FROZEN in `progress.md`. |
| R9 | **One configuration per comparison**: state pair set, commission, capital, caps, risk, window. Never compare rows from different configurations. | `docs/PERSONAL_LIVE_ACCOUNT.md` warning: configs differ by ~2x. |
| R10 | **Suspicion triggers** - a result meeting any of these is a bug until disproved: max drawdown < 1% or equity that only rises; PF > 3 after costs; win rate or sign flips between ambiguity bounds; profit concentrated in one pair or one quarter; P&L from trades whose limit never re-touched; result vanishes when costs +25%. | Old "0.3% max DD" was a formula bug; ORB champion was bug-driven. |
| R11 | **Reproduce before you extend**: re-run the documented command for the baseline result and confirm the number to the stated precision before building on it. If it does not reproduce, that is finding #1. | `legacy=True` reproduces old numbers to the cent ($17,853.56 / 1812 trades). |
| R12 | **Engine changes need a regression test** and the full test run. Keep a `legacy`/toggle path so the delta is attributable. | `tests/test_optimizer_fill_logic.py` (14 tests). |

### Challenge constants (verify against the ruleset in use; never edit to help a result)
The5ers $2,500 High Stakes as modeled here: start $2,500, floor $2,250 (-10%), daily loss 5% of balance
(sims stop at 4.5% for a buffer), Phase 1 target +10% ($2,750) with >= 3 qualifying days at >= $12.50,
Phase 2 +5%, 30-day inactivity limit. Position and trade caps differ between documents (one slot in
`FINAL_OPTIMUM_STRATEGY.md`; <= 2 concurrent and <= 5/day in `verify_final_config.py`) - name which one you used (R9).

### Default acceptance gates for the sweep/reclaim EA (from `docs/strategy/progress.md` section 8)
>= 100 fills per combination, >= 300 aggregate; combination PF >= 1.15, aggregate PF >= 1.30; expectancy >= 0.20R;
Phase 1 pass probability >= 0.70, Phase 2 >= 0.85, joint >= 0.60; p99 drawdown <= 6%.
For any other strategy family, **the human sets the gates at SCOPE**; the loop cannot invent them after the fact.

## 6. Verdict vocabulary

Terminal status (`DONE/PARTIAL/BLOCKED`) says whether the **procedure** finished. The **strategy verdict** is separate:

| Verdict | Requires |
|---|---|
| **VALIDATED (on history)** | All human-set gates pass on TEST under the pessimistic bound with costs, R1-R12 clean, N reported. Still not live evidence. |
| **NOT VALIDATED** | A gate fails, or it survives only optimistic bounds. |
| **INCONCLUSIVE** | The data cannot identify the answer (e.g. too few fills, ambiguity bounds straddle break-even). Say what data would settle it (tick or M1 data is the repo's standing answer). |

`DONE` + `NOT VALIDATED` is a normal, good outcome. Do not iterate parameters to convert it.

## 7. Where things go

| Item | Location |
|---|---|
| Plans | `docs/superpowers/plans/YYYY-MM-DD-<slug>.md` |
| Results and audits | `docs/research/findings/findings_<lab>.md` (one per lab) |
| Ledger | Bottom section of the findings file for the run, from `templates/loop-ledger.md` |
| Cross-session handoff | Append a dated entry to `docs/strategy/progress.md` |
| Lab code | `tools/` (research) or `validation/speed_lab/` (verification) |
| Scratch / large outputs | `/tmp` (data extracts, caches such as `/tmp/speedlab_cache`) |

## 8. Approval required (ask, then wait)

- Modify: `validation/triad_v2_1_registry.json`, `validation/triad_v2_2_ablation_registry.json`,
  EA frozen parameters in `MQL5/Experts/**` (`InpSweepAtrMin`, `InpProfile`, `EA_BUILD_ID`, ...),
  cost constants (`SPREAD_STD`, `RAW_SCALE`, `COMM_RT`), challenge constants, or acceptance gates.
- Overwrite, delete, or re-source any file in `validation/HistoryData/`; commit any dataset or CSV to Git.
- Widen the trial budget or re-open a TEST window after a look.
- Add a step that pushes to a branch, or dispatch a workflow that publishes data.
- Any statement that recommends live or demo trading, or sets `Inp*GatePassed = true`.
- Deleting or rewriting existing findings docs (append and supersede instead, as the roadmap does).

## 9. Git

- Work on the session branch the harness gave you; never switch or create branches; never touch `main`.
- The `data/m5-history` branch is owned by the CI workflow (force-pushed each run). Read it; do not push to it.
- Small commits, message states the validation effect ("fix: ..." or "research: ..."). Do not commit
  generated data. Skills `INDEX.md` here is generated by a script that is **not** in this repo, so do not
  hand-edit it.
- Do not rewrite or delete history. Do not stage unrelated dirty files.
