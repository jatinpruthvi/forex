---
kind: error_handling
name: 'Error Handling in TRIAD-R: Custom Validation Exceptions and Fail-Closed MQL5 Logging'
category: error_handling
scope:
    - '**'
source_files:
    - tools/triad_validation.py
    - tests/test_bugfix_regressions.py
    - tests/test_ablation_scaffold.py
    - tests/test_extended_validation.py
    - tests/test_validation.py
    - tests/triad_reference.py
    - MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5
    - MQL5/Experts/TRIAD_SCREEN/TRIAD_SCREEN.mq5
---

## Overview

The repository implements two distinct error-handling strategies, one for the Python validation/backtest toolchain and one for the live MQL5 Expert Advisor (EA). The Python side uses a dedicated `ValidationError` exception type to enforce frozen registries, replay CSV schemas, and simulation invariants. The MQL5 side avoids exceptions entirely and instead logs structured audit events via a `LogEvent` helper, persists halts through fail-closed global variables, and treats I/O failures as logged warnings that disable further logging rather than crashing.

## Python Toolchain: `ValidationError` as the Central Error Type

- **Custom exception**: `tools/triad_validation.py` defines `class ValidationError(ValueError)` (line 227) with the docstring "Raised when a frozen registry or replay export is invalid." All downstream validation functions raise this single typed exception rather than raw `ValueError`/`IOError`, so callers can catch exactly the domain-level failure.
- **Where it is raised**:
  - Registry loading: missing file (`OSError` wrapped), JSON decode errors, missing `registry_sha256`, hash mismatch, and registry payload drift all raise `ValidationError` (lines 318–330).
  - Replay CSV parsing: field-type coercion helpers `_strict_bool`, `_finite_float`, `_nonnegative_float` wrap `ValueError` into `ValidationError` with line-number context (lines 334–357); unknown `config_id`, invalid `split`/`combination`, negative integers, duplicate rows, empty CSVs, and activated candidates with zero risk cash all raise `ValidationError` (lines 385–436).
  - Coverage checks: missing configuration/combination exports or inconsistent calendar-day coverage across combinations raise `ValidationError` (lines 448–472).
  - Phase simulation: an empty day list passed to `_moving_block_days` raises `ValidationError` (line 958).
  - Priority parsing: invalid tokens, unknown combinations, non-integer values, and out-of-range priorities raise `ValidationError` (lines 781–792).
- **Propagation pattern**: low-level parsers convert generic `ValueError`/`KeyError`/`TypeError` into `ValidationError(...)` using `from exc` chaining, preserving the original traceback while elevating to the domain layer. Callers (e.g., CLI entry points) are expected to catch `ValidationError` and surface it to the user/report.
- **Test coverage**: tests import and assert on `ValidationError` directly — e.g., `tests/test_ablation_scaffold.py`, `tests/test_bugfix_regressions.py` (`LoaderErrorHandlingTests`), `tests/test_extended_validation.py`, `tests/test_validation.py` — confirming that malformed inputs consistently produce this exception type.
- **Other Python errors**: The reference implementation in `tests/triad_reference.py` raises plain `ValueError` for invalid halt values (lines 49, 51), which tests assert against separately; this is a different module from the validator and intentionally uses the built-in type.

## MQL5 EA: Structured Audit Logging and Fail-Closed Halting

The live EA (`MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5`) has no try/catch or exception mechanism. Errors are handled by:

- **Structured audit log**: A `LogEvent(level, event_name, detail)` helper (lines 300–327) writes every event to a CSV file with columns `server_time, level, event, detail, balance, equity, requests`. Levels include `INFO`, `ERROR`, and `HALT`. On file open/write failure, it prints `[ERROR] AUDIT_LOG_OPEN_FAILED` / `AUDIT_LOG_WRITE_FAILED` with `GetLastError()` and sets a `g_log_failure` flag so subsequent calls stop retrying the dead file handle. This is a graceful degradation, not a crash.
- **Halt system**: `Halt(reason)` (lines 329–350) records a strategy halt by persisting three global variables — `Halt`, `HaltReason`, and `HaltSig` — via `WriteHaltLatch`. The latch signature combines config hash, runtime identity, phase, halt value, and reason hash so tampering cannot silently clear a halt. If writing fails, the config sentinel is deleted to force a fresh-state handshake on next start (fail-closed behavior, lines 341–347).
- **Runtime integrity checks**: `BuildConfigHash()`, `RuntimeIdentityHash()`, and `AccountStateSignature()` compute hashes of EA inputs, account identity, and full trading state; mismatches between runs cause the EA to refuse to proceed, treating configuration drift as a fatal condition.
- **Server time offset tolerance**: Instead of raising an error, server GMT offset drift is measured as `offset_error` and compared against `SERVER_OFFSET_TOLERANCE_SECONDS`; only if the drift exceeds the tolerance does the code treat it as a problem (lines 1722–1735, 3662–3664).
- **News-driven recovery**: Positions are explicitly closed via `ClosePosition(ticket, "post_news_recovery_flat", true)` after news blocks (line 3153) and similarly in the screen EA (line 2595), treating news events as recoverable operational conditions rather than errors.
- **No panics/recover**: MQL5 code never uses `throw`, `catch`, `panic`, or `recover`. Errors are represented as return codes, boolean flags, and logged events.

## Conventions and Constraints

1. **Python validation layer**: All schema/registry violations must be raised as `ValidationError` (not bare `ValueError`). Tests enforce this contract by asserting `assertRaises(ValidationError)` on malformed inputs.
2. **Exception chaining**: When wrapping lower-level parse errors, use `raise ... from exc` to preserve tracebacks (observed in `load_registry`, `load_replay_rows`, and field coercers).
3. **Line-number context**: Every `ValidationError` raised during CSV parsing includes the offending line number, enabling precise diagnostics for replay exporters.
4. **Fail-closed persistence**: In MQL5, any persistent state change (halt latch, config sentinel) is accompanied by a checksum/signature; partial writes leave stale data that causes the next run to fail closed rather than silently proceeding.
5. **Audit-first logging**: All operational anomalies go through `LogEvent` with a fixed `level`/`event_name`/`detail` triple, producing machine-readable CSV output suitable for post-mortem analysis.
6. **No silent ignores**: File I/O failures in the logger do not swallow the error; they print an `[ERROR]` message and set a flag to avoid repeated failed attempts.
7. **Domain-specific tolerances**: Timezone/server-offset drift is tolerated within a bounded threshold rather than treated as a hard error, reflecting the distinction between transient environment drift and genuine misconfiguration.