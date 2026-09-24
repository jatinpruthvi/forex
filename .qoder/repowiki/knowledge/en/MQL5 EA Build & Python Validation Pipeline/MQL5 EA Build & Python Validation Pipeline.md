---
kind: build_system
name: MQL5 EA Build & Python Validation Pipeline
category: build_system
scope:
    - '**'
source_files:
    - MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5
    - MQL5/Experts/TRIAD_R_HS/README.md
    - tests/test_source_contract.py
    - tests/test_reference.py
    - tests/triad_reference.py
    - tools/triad_validation.py
    - tools/replay_export.py
    - tools/triad_ablation.py
    - validation/triad_v2_1_registry.json
    - validation/triad_v2_2_ablation_registry.json
    - MQL5/Files/triad_red_news.csv.example
---

## What system/approach is used

This repository has no traditional build system (no Makefile, Dockerfile, CI pipeline, or packaging script). The "build" consists of two parallel tracks:

1. **MQL5 compilation** — the production Expert Advisor `MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5` and its screen variant are compiled manually in MetaEditor against the broker's MT5 build. Versioning is embedded as a string literal `EA_BUILD_ID = "TRIAD_R_HS_2.1.6_20260905"` inside the source; there is no automated version bump.
2. **Python validation/backtest pipeline** — a pure-Python, standard-library-only research harness (`tools/triad_validation.py`, `tools/replay_export.py`, `tools/triad_ablation.py`, plus ablation/aggressive optimizer variants) that consumes frozen registries under `validation/` and historical tick data under `validation/HistoryData/`. It produces registry-conformant replay CSVs and JSON reports. There is no `requirements.txt`, `pyproject.toml`, or virtualenv script; the tooling assumes a system `python3` with only stdlib modules.

The project also ships a `.gitignore` that excludes MetaEditor build output, confirming MQL5 artifacts are intentionally not committed.

## Key files and packages

- `MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5` — compiled MQL5 EA source (the only artifact produced by the build).
- `MQL5/Experts/TRIAD_SCREEN/TRIAD_SCREEN.mq5` — demo/screen EA, built separately.
- `tests/test_source_contract.py` — static contract tests that grep the compiled EA source for required tokens, default gate values, forbidden API calls, and structural invariants. This is the closest thing to a continuous integration check in the repo.
- `tests/test_reference.py` — unit tests over the pure-Python reference implementation in `tests/triad_reference.py` (risk math, daily state, session bounds, halt-latch signatures).
- `tests/test_screen_ea_contract.py`, `tests/test_validation.py`, `tests/test_ablation_scaffold.py`, `tests/test_bugfix_regressions.py`, `tests/test_extended_validation.py` — additional contract and regression suites.
- `tools/triad_validation.py`, `tools/replay_export.py`, `tools/triad_ablation.py`, `tools/strategy_optimizer.py`, `tools/aggressive_optimizer.py`, `tools/multi_pair_grid_search.py`, `tools/parameter_grid_search.py`, `tools/tick_signal_builder.py`, `tools/extended_grid_search.py`, `tools/_validate_4yr.py` — offline research tools invoked via `python3 tools/<script>.py`.
- `validation/triad_v2_1_registry.json`, `validation/triad_v2_2_ablation_registry.json` — frozen configuration matrices (SHA-256 covered); any mutation breaks the validator.
- `validation/HistoryData/` — committed M5 CSV tick/bar datasets used by the replay pipeline.
- `MQL5/Files/triad_red_news.csv.example` — schema example for the runtime news calendar consumed by the EA.
- `MQL5/Experts/TRIAD_R_HS/README.md` — documents the full compile-and-validate sequence, including the required `python3 -m unittest discover -s tests -v` step before any MetaEditor compile.

## Architecture and conventions

- **Frozen registries drive reproducibility.** Both the V2.1 selection matrix and the preregistered ablation round are stored as JSON files whose SHA-256 commit covers every threshold, split date, fill policy, and decision rule. Changing any payload invalidates the hash and the tool rejects it. This replaces a dependency manifest: the "version" of the research is the registry file itself.
- **Tests assert the MQL5 source as a contract.** Rather than compiling the EA during CI, `tests/test_source_contract.py` reads `TRIAD_R_HS.mq5` and asserts the presence/absence of specific tokens (e.g., all release gates default to `false`, `InpEnableOrderSubmission=false`, `InpValidationReleaseId="LOCKED"`, forbidden order APIs like `OrderSend`/`.Buy(`/`.Sell(`, exactly four paired profiles with max risk ≤ 0.4%, visible stop/target on pending orders, etc.). This enforces safety defaults without an MQL5 compiler.
- **Build ID is manual and human-tracked.** The README states the current build is `TRIAD_R_HS_2.1.5_20260904`; the test expects `EA_BUILD_ID = "TRIAD_R_HS_2.1.6_20260905"`. The README explicitly says newer builds require a fresh review and compile/runtime validation before use.
- **No automated packaging or deployment.** Installation is documented as copying `TRIAD_R_HS.mq5` into `MQL5/Experts/TRIAD_R_HS/` on the MT5 terminal's data folder and compiling in MetaEditor. There is no installer, container, or CI job.
- **Research runs are CLI scripts, not services.** Every tool exposes a `schema` subcommand to print its row contract, then `build` and `validate` subcommands driven by command-line flags. No process manager or daemon is involved.

## Conventions and constraints

- **All release gates default closed.** The source must declare `InpEnableOrderSubmission=false`, `InpValidationReleaseId="LOCKED"`, and every combination-specific gate (`InpEURUSDLondonGatePassed`, `InpGBPUSDLondonGatePassed`, `InpUSDJPYNewYorkGatePassed`) as `false`; the test suite enforces this statically.
- **Forbidden order APIs are banned.** The source may not contain `PositionClosePartial`, `ORDER_TYPE_CLOSE_BY`, `.Buy(`, `.Sell(`, `OrderSend(`, or `OrderSendAsync(`; pending orders must be submitted via `g_trade.BuyLimit`/`g_trade.SellLimit` with explicit stop and target.
- **News CSV schema is enforced.** The example header must be `utc_time,currency,impact,title`, rows must have exactly four fields, timestamps match `YYYY.MM.DD HH:MM`, currency is three uppercase letters, impact is `RED` or `HIGH`, and at least one `ALL,COVERAGE` row must exist.
- **Versioning is source-inlined.** The build identifier lives as a string literal in the MQL5 source; there is no external version file or tag-based release automation.
- **Testing entry point is documented but not scripted.** The README prescribes `python3 -m unittest discover -s tests -v`; no `Makefile`, `tox.ini`, or `pytest` config exists to enforce it.
- **No CI, Docker, or packaging artifacts were found.** There is no `.github`, `.gitlab-ci`, `Jenkinsfile`, `Dockerfile`, `docker-compose.yml`, `setup.py`, `pyproject.toml`, `requirements.txt`, `Makefile`, or shell build script anywhere in the repository.