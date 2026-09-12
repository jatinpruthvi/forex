---
kind: logging_system
name: MQL5 Structured Audit Logging with Python print-based Tooling
category: logging_system
scope:
    - '**'
source_files:
    - MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5
    - MQL5/Experts/TRIAD_SCREEN/TRIAD_SCREEN.mq5
    - tools/strategy_optimizer.py
    - tools/_validate_4yr.py
---

## What system/approach is used

The repository has two distinct logging mechanisms, one for the live MQL5 Expert Advisors and one for the Python research/backtest tooling.

- **MQL5 (live EA)**: A custom structured audit logger built on `Print()` plus persistent CSV file writes. There is no external logging framework; all output goes through a single `LogEvent(level, event_name, detail)` helper that formats messages as `[LEVEL] EVENT | detail` and appends them to an on-disk CSV audit log.
- **Python tools**: No structured logging library (`logging`, `loguru`, `structlog`) is imported anywhere in the codebase. All tooling uses plain `print()` calls for progress, results, and diagnostics.

## Key files and packages

- `MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5` — production EA; defines the entire logging subsystem under the `// ---- Logging ---` input section and the `Utility and logging` block.
- `MQL5/Experts/TRIAD_SCREEN/TRIAD_SCREEN.mq5` — demo screening EA; declares its own journal headers (`TSC_JOURNAL_HEADER`, `TSC_SUMMARY_HEADER`) but does not reuse the production logger.
- `tools/*.py` (e.g. `strategy_optimizer.py`, `_validate_4yr.py`) — Python scripts that rely exclusively on `print()` for console output.

## Architecture and conventions

### MQL5 structured audit log

1. **Inputs control verbosity**
   - `InpVerboseLog` (bool) gates whether non-error events are emitted to the terminal via `Print()`.
   - `InpLogFilePrefix` (string) is used to derive the path of the CSV audit log file stored on disk.

2. **Single entry point: `LogEvent(level, event_name, detail)`**
   - Formats every message as `[LEVEL] EVENT_NAME | detail`.
   - Always emits to the terminal when `InpVerboseLog` is true or the level is `ERROR` or `HALT`.
   - Always attempts to append a row to the CSV audit file regardless of verbosity.

3. **CSV schema (fixed header written once per file)**
   - Columns: `server_time`, `level`, `event`, `detail`, `balance`, `equity`, `requests`.
   - The first write opens the file with `FILE_CSV|FILE_ANSI|FILE_SHARE_READ`; if the file is empty it writes the header row before appending data.
   - Each row carries the server timestamp, the event level, the event name, the free-form detail string, current account balance/equity, and a monotonic request counter (`g_request_count`).

4. **Error handling around I/O**
   - If opening the file fails, `LogEvent` prints `[ERROR] AUDIT_LOG_OPEN_FAILED | <path> error=<code>` and sets a global `g_log_failure` flag so the same failure is not reprinted repeatedly.
   - If writing fails, it prints `[ERROR] AUDIT_LOG_WRITE_FAILED | <path> error=<code>` and marks `g_log_failure=true`.

5. **Halt / fail-closed semantics**
   - `Halt(reason)` logs a `HALT`-level event and persists a halt latch via `WriteHaltLatch(1.0, hash(reason))`. On failure it deletes the configuration sentinel (`GlobalVariableDel(GVName("Cfg"))`) so the next live start fails the fresh-state handshake rather than silently resuming — this is enforced by the code path itself.

6. **Event taxonomy observed across the EA**
   - Levels: `ERROR`, `WARN`, `HALT` (and informational messages gated by `InpVerboseLog`).
   - Event names follow a `DOMAIN_SUBEVENT` convention: `INSTANCE_LOCK_STORAGE_FAILED`, `DUPLICATE_LIVE_INSTANCE`, `INSTANCE_LOCK_RACE`, `STALE_INSTANCE_LOCK_RECOVERED`, `STRATEGY_HALTED`, `STATE_PERSIST_FAILED`, `REBASELINE_FLAG_PERSIST_FAILED`, `NEWS_FILE_OPEN`, `NEWS_COVERAGE_ROW_INVALID`, etc.
   - Every event includes a human-readable `detail` field carrying contextual values (account login, owner chart ID, reason strings).

7. **Separate on-chart dashboard**
   - `TRIAD_SCREEN.mq5` defines its own journal headers (`TSC_JOURNAL_HEADER = "server_time;level;event;detail;balance;equity"`) and summary headers, indicating a parallel but independent logging stream for the demo screener.

### Python tooling logging

- Scripts such as `tools/strategy_optimizer.py` and `tools/_validate_4yr.py` use `print()` directly for:
  - Progress indicators (e.g. `print(f"  {path.name} ({path.stat().st_size/1e6:.0f} MB)...", end="", flush=True)`).
  - Section separators using repeated `=` characters.
  - Tabular result tables printed to stdout.
- There is no centralized logger, no log levels, no file sinks, and no structured fields in the Python side.

## Conventions and constraints

- **Every significant runtime decision in the production EA goes through `LogEvent`**, never a bare `Print()`, ensuring consistent formatting and guaranteed CSV persistence.
- **Verbosity is user-controlled at runtime** via the `InpVerboseLog` input; only `ERROR` and `HALT` events bypass the verbosity gate.
- **Audit log integrity is self-healing**: failed open/write operations are recorded as `AUDIT_LOG_OPEN_FAILED` / `AUDIT_LOG_WRITE_FAILED` errors and the logger stops retrying until the underlying issue is resolved, preventing log spam.
- **Halt state is persisted and fail-closed**: halting the strategy also removes the configuration sentinel on persistence failure, enforcing a manual reset before resuming.
- **Event naming follows a domain-prefixed convention** (e.g. `INSTANCE_LOCK_*`, `STATE_*`, `NEWS_*`) making it possible to filter and alert on specific categories from the CSV.
- **Python scripts have no logging policy** — they are ad-hoc research utilities where `print()` output is sufficient; there is no expectation to migrate them to a structured logger.