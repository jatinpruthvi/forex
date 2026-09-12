---
kind: configuration_system
name: Frozen JSON Registry + Immutable ConfigSpec Dataclasses for Strategy Configuration
category: configuration_system
scope:
    - '**'
source_files:
    - tools/replay_export.py
    - tools/triad_validation.py
    - tools/triad_ablation.py
    - validation/triad_v2_1_registry.json
    - validation/triad_v2_2_ablation_registry.json
    - tests/test_ablation_scaffold.py
    - tests/test_validation.py
    - tests/test_screen_ea_contract.py
---

## What system/approach is used

The project does **not** use a conventional application configuration framework (no `.env`, no YAML/TOML loaders, no `os.environ`-based settings). Instead it implements a **frozen registry pattern**: strategy parameters are declared in Python code, serialized to committed JSON files under `validation/`, and then loaded at runtime by the validation/ablation tooling. The registries act as both configuration manifests and immutable audit artifacts — every change requires re-running the `preregister` command, which rebuilds the payload and recomputes a `registry_sha256` hash that is enforced on load.

Configuration values flow through two layers:
1. **Frozen registries** (`triad_v2_1_registry.json`, `triad_v2_2_ablation_registry.json`) — canonical, versioned, SHA-256–protected JSON documents describing the full parameter space or ablation variant set.
2. **Python dataclass wrappers** (`ConfigSpec`, `EntrySpec`, `CandidateConfig`, `FillPolicy`, `ValidationThresholds`, `SimulationSettings`, `AblationRun`, `AblationSettings`) — frozen `@dataclass(frozen=True)` objects parsed from the registries, providing type-safe access with no mutable state.

There is no runtime config loading from environment variables, CLI flags override registries only via explicit `--registry` / `--output` paths passed to `tools/triad_validation.py` and `tools/triad_ablation.py` subcommands.

## Key files and packages

- `tools/replay_export.py` — defines `ConfigSpec` (config_id, profile, risk_fraction, target_r, time_stop_minutes, move_stop_to_entry_after_confirmed_1r) and `EntrySpec` (sweep_atr_min/max, reclaim_wick_min, displacement_body_min, require_midpoint, entry_mode); provides `load_config_specs(registry)` to materialize configs from a validated registry; contains observed-event schema and export helpers.
- `tools/triad_validation.py` — builds and validates the V2.1 160-config matrix via `build_registry()` / `write_registry()` / `load_registry()`, enforces `registry_sha256` integrity, enumerates `RANGE_BANDS`, `ATR_BANDS`, `TIME_STOPS`, `PROFILES`, `BREAKEVEN_POLICIES`, and loads replay CSV rows against the frozen field list `CSV_FIELDS`.
- `tools/triad_ablation.py` — mirrors the same pattern for the ablation round: `build_runs()` declares variants, `build_registry()` serializes fixed controls + decision rules + splits, `load_registry()` verifies hash and exact equality with the in-memory declaration, and `guard_split_args()` / `guard_row_days()` enforce preregistered WALK_FORWARD/HOLDOUT cuts.
- `validation/triad_v2_1_registry.json` — the committed 160-configuration manifest referenced by tests and tools; each entry carries `config_id`, `profile`, `risk_fraction`, `target_r`, `time_stop_minutes`, `move_stop_to_entry_after_confirmed_1r`, plus range/ATR percentile bands.
- `validation/triad_v2_2_ablation_registry.json` — the committed ablation manifest declaring baseline + five single-change variants, their `entry_spec`, fixed controls, evaluation rules, and split windows.
- `tests/test_ablation_scaffold.py`, `tests/test_validation.py`, `tests/test_screen_ea_contract.py` — reference the committed registries via `ROOT / "validation" / triad_v2_x_registry.json` and drive replay/ablation runs against them.

## Architecture and conventions

### Registry lifecycle
1. **Declaration phase**: `python3 tools/<tool>.py preregister --output <path>` calls `build_registry()` (or `build_runs()` + `build_registry()`), writes a deterministic JSON file with `schema_version`, `registry_version`, `canonical_strategy`, `fill_policy`, thresholds/simulation settings, and a computed `registry_sha256` over the payload (excluding the hash itself).
2. **Commit phase**: the resulting JSON is checked into `validation/` and becomes the ground truth.
3. **Consumption phase**: `load_registry(path)` reads the file, recomputes the hash, rejects any mismatch, and additionally asserts equality with the in-memory `build_registry()` output so the source code and committed file stay in lockstep.
4. **Runtime consumption**: `load_config_specs()` / `load_runs()` / `load_replay_rows()` parse the registry into frozen dataclasses and reject unknown fields, out-of-range values, duplicate keys, and missing coverage.

### Configuration shape
- **V2.1 selection configs** are a Cartesian product of four axes: range percentile band × ATR percentile band × time stop (30/45/60/90/0) × profile (A/B/C/D with fixed risk_fraction/target_r pairs) × breakeven policy (BE0/BE1), yielding exactly 160 unique `config_id`s generated by `_config_id(range_band, atr_band, time_stop, profile, breakeven)`.
- **Ablation configs** are single-variant entries where each `AblationRun` changes exactly one element of `EntrySpec` (displacement removal, quote entry, wick filter, body threshold, midpoint filter) while holding profile/risk/target/time-stop/breakeven constant at Profile A, 45 minutes, no breakeven.
- **Fill policy and simulation thresholds** are embedded in the registry payload (`fill_policy`, `thresholds`, `simulation`, `decision`) rather than read from disk separately, ensuring the entire experimental protocol is self-contained in one document.

### Validation and enforcement
- All registries carry a `registry_sha256` computed via `_payload_hash()` using canonical JSON (`sort_keys=True`, compact separators, ASCII-only). Loading fails if the stored hash differs from the recomputed one.
- Replay CSV inputs are validated against a hard-coded `CSV_FIELDS` tuple; header mismatches trigger `ValidationError` directing users to run `schema`.
- Split dates are frozen in the ablation registry under `splits.WALK_FORWARD` / `splits.HOLDOUT`; `guard_split_args()` rejects any CLI invocation whose `--selection-split` / `--holdout-split` differs from the preregistered values.
- Coverage checks (`validate_replay_coverage`) require every combination/config/day declared in the registry to be present in both WALK_FORWARD and HOLDOUT splits, even when there is no candidate trade.
- `write_registry(..., overwrite=False)` refuses to overwrite existing registries without `--force`, preventing accidental drift.

### Conventions and constraints
- No environment-variable-based configuration exists anywhere in the codebase; all runtime behavior is driven by CLI arguments pointing at committed registries and CSV inputs.
- Configuration objects are immutable: every dataclass is decorated with `@dataclass(frozen=True)`, so once loaded they cannot be mutated at runtime.
- New configurations must go through the registry generation pipeline (`build_registry` / `build_runs` → `write_registry`); ad-hoc dictionaries bypassing these functions are rejected by the loader's strict schema checks.
- The MQL5 EAs in `MQL5/Experts/` are intentionally decoupled from this Python configuration system — the registries describe the *offline* validation contract; live EA parameters are separate inputs not managed by these tools.
- The `config_id` naming convention encodes the configuration axes (e.g. `R30_80-A20_80-T30-PA-BE0`) and is treated as an immutable identifier across exports, reports, and audits.