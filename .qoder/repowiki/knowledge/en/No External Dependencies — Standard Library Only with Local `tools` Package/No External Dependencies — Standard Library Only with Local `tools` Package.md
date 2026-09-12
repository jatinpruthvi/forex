---
kind: dependency_management
name: No External Dependencies — Standard Library Only with Local `tools` Package
category: dependency_management
scope:
    - '**'
source_files:
    - tools/__init__.py
    - tools/triad_validation.py
    - tools/strategy_orb.py
    - tests/test_ablation_scaffold.py
    - tests/test_bugfix_regressions.py
    - validation/triad_v2_1_registry.json
    - validation/triad_v2_2_ablation_registry.json
---

## What system/approach is used

This repository does **not** use any third-party Python dependency management system. There is no `requirements.txt`, `pyproject.toml`, `setup.py`, `Pipfile`, `poetry.lock`, `conda.yml`, or `venv/` directory committed to the repo. All Python scripts in `tools/` and `tests/` import exclusively from the Python standard library (`csv`, `json`, `math`, `random`, `statistics`, `dataclasses`, `datetime`, `pathlib`, `unittest`, `argparse`, `hashlib`, `collections`, `typing`) and one local sibling package, `tools`. The MQL5 expert advisors under `MQL5/Experts/` are compiled by MetaTrader 5 and carry their own platform-level dependencies, but they do not reference Python packages.

The project's design intentionally keeps the backtest/validation pipeline free of external libraries so it can run on any machine with a CPython interpreter and the Eightcap tick CSV data, without requiring `pip install` or environment setup.

## Key files and packages

- `tools/__init__.py` — declares the repository-local `tools` package; its docstring reads *"Repository-local offline research and validation tools."* Tests import it via `from tools import replay_export as re`, `from tools import triad_ablation as abl`, and `from tools.triad_validation import ValidationError, validate_replay_coverage`.
- `tools/triad_validation.py` — the central validation/backtesting module; uses only stdlib modules and references frozen registries under `validation/` (`triad_v2_1_registry.json`, `triad_v2_2_ablation_registry.json`).
- `tools/strategy_orb.py` — standalone ORB backtester; explicitly states *"No imports from existing strategy or signal-builder files"* and imports only stdlib.
- `tests/test_ablation_scaffold.py`, `tests/test_bugfix_regressions.py`, `tests/test_validation.py`, etc. — unittest suite that depends only on stdlib + the local `tools` package.
- `validation/*.json` — frozen registry artifacts (configuration manifests) rather than package lockfiles; they pin strategy parameters, not Python packages.

## Architecture and conventions

1. **Single flat package for tooling.** All research scripts live under `tools/` and are imported directly by tests using relative package paths (`from tools import ...`). There is no subpackage hierarchy beyond the flat layout.
2. **No virtual environments committed.** The `.gitignore` does not list `venv/`, `__pycache__/` is ignored, and no lockfile exists — each developer installs nothing and runs scripts directly against the system or user Python installation.
3. **Data-driven configuration instead of package pins.** Versioning and reproducibility are achieved through frozen JSON registries (`validation/triad_v2_1_registry.json`, `validation/triad_v2_2_ablation_registry.json`) and committed historical tick CSVs under `validation/HistoryData/`, not through package version locks.
4. **MQL5 EAs are separate from Python tooling.** The production EA (`TRIAD_R_HS.mq5`) and screening EA (`TRIAD_SCREEN.mq5`) are compiled by MT5 and have no Python dependency surface; the Python side only consumes their exported event CSVs.

## Conventions and constraints

- **Constraint: no third-party Python packages.** Every Python file observed imports only from the Python standard library. No `pip`, `conda`, or other package manager invocation appears anywhere in the repo.
- **Convention: treat `tools/` as an installable package despite lacking `setup.py`.** Tests import it as `import tools`, relying on the repo root being on `sys.path` when invoked from the workspace directory.
- **Convention: freeze strategy logic in registries, not in code versions.** The `SCHEMA_VERSION = "TRIAD_VALIDATION_V1"` and `REGISTRY_VERSION = "TRIAD_R_V2_1_160"` constants in `triad_validation.py` document which schema and registry version a report was produced against, serving as the reproducible artifact in place of a package lockfile.
- **Constraint: self-contained scripts.** `strategy_orb.py`'s header explicitly states it has *"No imports from existing strategy or signal-builder files"*, reinforcing the convention that each tool should be runnable independently without shared state beyond the stdlib.