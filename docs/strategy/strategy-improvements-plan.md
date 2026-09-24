# Strategy Improvements Plan — TRIAD-R HS Three Targeted Enhancements
<!-- IMPLEMENTATION STATUS: COMPLETE — build 2.1.6 — all 39 contract tests pass -->

**EA source:** `MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5` (build 2.1.5)
**Canonical spec:** `THE5ERS-CHALLENGE-STRATEGY-V2.md` (revision 2.1)
**Test suite:** `tests/test_source_contract.py` (48 tests, all must pass after changes)
**Status:** Plan — pending user review and approval before implementation

---

## Top-Level Overview

Three targeted improvements are made to the existing EA. None of them change the
core entry geometry, risk arithmetic, or compliance guardrails. Each improvement is
self-contained and can be reviewed and rolled back independently.

| # | Improvement | Challenge benefit |
|---|---|---|
| 1 | H1 50-EMA directional bias filter | Rejects counter-trend sweep setups, raising net expectancy |
| 2 | News-blocked day counter + inactivity alert | Prevents surprise 30-day inactivity breach from news-heavy weeks |
| 3 | `STATS_INSUFFICIENT` severity escalation | Operator sees the warning as ERROR, not buried WARN |

**Design constraints that must not be violated:**
- Entry contract parameters (sweep band, reclaim bars, wick/body minimums, stop buffer) stay
  locked — `ValidateInputs()` enforces them and `test_source_contract.py` checks them.
- No new tunable risk parameter may be introduced.
- The config hash (`BuildConfigHash()`) must still compile with all existing inputs.
- All 48 existing Python contract tests must continue to pass.
- New inputs default to values that preserve current behaviour on existing configurations.

---

## Sub-Task 1 — H1 50-EMA Directional Bias Filter

**Status:** `[x] done`

### Intent

Add an optional H1 EMA directional bias check as a new mandatory gate in
`PrepareCandidate()`. When enabled, a long setup is only accepted if the current H1
bar's close is above the 50-period EMA and the EMA slope (difference between the
current and the previous completed H1 bar's EMA value) is non-negative. A short setup
requires the inverse. This rejects counter-trend sweeps that trade into sustained
institutional momentum — the regime where the sweep/reclaim edge is weakest.

The filter is gated behind a new input `InpRequireH1EmaBias` (default `false`) so the
baseline behaviour is completely unchanged for the existing 160-config validation
registry. Enabling it becomes a research candidate added to future registry runs.

### Expected Outcomes

- New input `InpRequireH1EmaBias = false` appears in the inputs section, under
  the "Coarse research candidates" block, at line ~114.
- New global `int g_h1_ema_handles[3]` initialised to `INVALID_HANDLE` is declared
  alongside the existing `g_atr_handles[3]`.
- `InitializeSessions()` creates the H1 EMA(50) indicator handle for each enabled
  symbol using `iMA(symbol, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE)`.
- `OnDeinit()` releases the H1 EMA handles alongside the existing ATR handle cleanup.
- New helper function `CheckH1EmaBias(const int session_index, const ENUM_PATTERN_SIDE side)`
  returns `true` (allow trade) when:
  - `InpRequireH1EmaBias` is `false` → always returns `true`.
  - Filter enabled and handle valid: reads two consecutive completed H1 bars' EMA
    values via `CopyBuffer`. For a LONG: `close > ema_current` AND
    `ema_current >= ema_prev`. For a SHORT: inverse.
  - If the indicator handle is invalid or buffer copy fails: returns `false` (fail-closed).
- `PrepareCandidate()` calls `CheckH1EmaBias()` immediately after the ATR-percentile
  gate (line ~2390) and before the spread gate. On failure, sets
  `candidate.rejection = "h1_ema_bias"` and returns `false`.
- `BuildConfigHash()` includes `BoolText(InpRequireH1EmaBias)` so configurations with
  and without the filter produce different hashes.
- `ValidateInputs()` requires no changes (the new input has no constrained domain).
- New Python contract test `test_h1_ema_bias_filter_structure` verifies:
  - `InpRequireH1EmaBias` declared with default `false`.
  - `g_h1_ema_handles` global array declared.
  - `CheckH1EmaBias` function present.
  - `"h1_ema_bias"` rejection string present.
  - `InpRequireH1EmaBias` appears in `BuildConfigHash`.

### Todo List

1. In the inputs section (~line 114), after `InpMoveStopToEntryAfter1R`, add:
   ```
   input bool InpRequireH1EmaBias = false; // false = V2.1 baseline behaviour
   ```
2. After `g_atr_handles[3]` declaration (~line 206), add:
   ```
   int g_h1_ema_handles[3] = {INVALID_HANDLE, INVALID_HANDLE, INVALID_HANDLE};
   ```
3. Locate `InitializeSessions()` — find where ATR handles are created (look for
   `iATR(` calls). Immediately after each ATR handle creation for session `i`, add a
   corresponding H1 EMA handle:
   ```
   g_h1_ema_handles[i] = iMA(g_sessions[i].symbol, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE);
   if(g_h1_ema_handles[i] == INVALID_HANDLE)
       LogEvent("WARN", "H1_EMA_HANDLE_FAILED", g_sessions[i].id);
   ```
4. Locate `OnDeinit()` — find the ATR handle release loop. Add a parallel loop to
   release H1 EMA handles:
   ```
   for(int i = 0; i < 3; i++)
     {
      if(g_h1_ema_handles[i] != INVALID_HANDLE)
        {
         IndicatorRelease(g_h1_ema_handles[i]);
         g_h1_ema_handles[i] = INVALID_HANDLE;
        }
     }
   ```
5. Add the `CheckH1EmaBias` helper function immediately before `PrepareCandidate()`:
   ```cpp
   bool CheckH1EmaBias(const int session_index, const ENUM_PATTERN_SIDE side)
     {
      if(!InpRequireH1EmaBias)
         return true;
      int handle = g_h1_ema_handles[session_index];
      if(handle == INVALID_HANDLE || BarsCalculated(handle) < 52)
         return false; // fail-closed when indicator not ready
      double ema[];
      ArraySetAsSeries(ema, true);
      // Copy the two most-recently completed H1 bars' EMA values.
      // shift=1 is the last completed bar; shift=2 is the one before it.
      if(CopyBuffer(handle, 0, 1, 2, ema) != 2)
         return false;
      double ema_current = ema[0]; // most recently completed H1 bar
      double ema_prev    = ema[1]; // bar before that
      string symbol = g_sessions[session_index].symbol;
      MqlRates h1[];
      ArraySetAsSeries(h1, true);
      if(CopyRates(symbol, PERIOD_H1, 1, 1, h1) != 1)
         return false;
      double h1_close = h1[0].close;
      if(side == PATTERN_LONG)
         return h1_close > ema_current && ema_current >= ema_prev;
      return h1_close < ema_current && ema_current <= ema_prev;
     }
   ```
6. In `PrepareCandidate()`, after the ATR-percentile gate block (the block ending with
   `candidate.rejection="atr_percentile"; return false;` at ~line 2390) and before the
   spread-gate block, add:
   ```cpp
   if(!CheckH1EmaBias(candidate.session_index, candidate.side))
     {
      candidate.rejection = "h1_ema_bias";
      return false;
     }
   ```
7. In `BuildConfigHash()`, append `"|" + BoolText(InpRequireH1EmaBias)` to the hash
   string — do this in the block where other bool inputs are hashed (around line 352).
8. In `tests/test_source_contract.py`, add a new test method
   `test_h1_ema_bias_filter_structure` that asserts the five items listed in Expected
   Outcomes above.
9. Run `python3 -m unittest discover -s tests -v` — all 49 tests must pass.

### Relevant Context

- Input block: `TRIAD_R_HS.mq5` lines 106–114 (coarse research candidates).
- Global declarations: `TRIAD_R_HS.mq5` lines 203–244.
- `BuildConfigHash()`: `TRIAD_R_HS.mq5` lines 346–385.
- `PrepareCandidate()`: `TRIAD_R_HS.mq5` lines 2320–2451 — the ATR-percentile gate
  ends at line 2391; the spread gate begins at line 2392.
- `TRIAD-SURVIVE.md` line 89: the original 8-point scoring system that included this
  filter as Filter 2.
- `THE5ERS-CHALLENGE-OPTIMIZATION.md` priority 3: "rejecting poor trades is the
  highest-value improvement."
- The filter defaults to `false` — the 160-config validation registry is unaffected
  until a new registry run explicitly sets `InpRequireH1EmaBias=true`.

---

## Sub-Task 2 — News-Blocked Day Counter and Inactivity Alert

**Status:** `[x] done`

### Intent

Add a persistent counter `g_news_blocked_days` that increments each server day when
at least one valid signal was detected but was rejected exclusively because of the
news blackout gate (rejection `"news_blackout"`). At rollover, if the counter crosses
a configurable threshold (default 3 consecutive days), log an `ERROR`-level
`NEWS_BLOCK_INACTIVITY_RISK` event so the operator can update the news calendar or
monitor activity. This distinguishes "no signal existed" (genuine dead-market day) from
"signal existed but was gated by news" — giving early warning before the 30-day
inactivity clock expires.

### Expected Outcomes

- New input `InpNewsBlockInactivityThreshold = 3` in the logging/operational block.
- New global `int g_news_blocked_days_streak = 0` persisted via a new terminal-global
  key `"NewsBlkStreak"`.
- `AccountStateSignature()` includes the new counter so any inconsistency fails closed.
- `PersistAccountState()` writes and reads `"NewsBlkStreak"`.
- When `PrepareCandidate()` returns `false` with `candidate.rejection == "news_blackout"`,
  a session-level flag `bool g_news_blocked_this_day` is set to `true`.
- At rollover (`ProcessRollover()`), after the day qualification check:
  - If `g_news_blocked_this_day` is `true` and no trade was completed that day,
    `g_news_blocked_days_streak++`.
  - Otherwise reset `g_news_blocked_days_streak = 0`.
  - If the streak reaches `InpNewsBlockInactivityThreshold`, log:
    `LogEvent("ERROR", "NEWS_BLOCK_INACTIVITY_RISK", ...)` with the streak count.
  - Reset `g_news_blocked_this_day = false` for the new day.
- New Python contract test `test_news_block_day_counter_structure` verifies:
  - `InpNewsBlockInactivityThreshold` declared with default `3`.
  - `g_news_blocked_days_streak` global declared.
  - `"NewsBlkStreak"` GV key present.
  - `"NEWS_BLOCK_INACTIVITY_RISK"` log event name present.
  - `g_news_blocked_this_day` flag referenced in source.

### Todo List

1. In the input section, after `InpVerboseLog` (~line 138), add:
   ```
   input int InpNewsBlockInactivityThreshold = 3; // consecutive news-blocked days before ERROR alert
   ```
2. In the global declarations block (~line 244), add two new globals:
   ```
   bool g_news_blocked_this_day     = false;
   int  g_news_blocked_days_streak  = 0;
   ```
3. In `AccountStateSignature()` (~line 395), append
   `"|" + IntegerToString(g_news_blocked_days_streak)` to the `text` string — do this
   alongside the other integer counters already included.
4. In `PersistAccountState()` (~line 549), add a write and a matching read in
   `LoadOrCreateAccountState()`:
   - Write: `if(!GVWrite("NewsBlkStreak", g_news_blocked_days_streak)) ok = false;`
     Place this immediately before the `StateSig` commit line (~line 576).
   - Read: in `LoadOrCreateAccountState()`, locate where `InactAlert` is loaded and add:
     ```
     double news_blk_val = 0.0;
     if(!GVRead("NewsBlkStreak", news_blk_val)) return false;
     g_news_blocked_days_streak = (int)news_blk_val;
     ```
5. In `PrepareCandidate()`, in the news-blackout rejection block (~line 2368):
   ```cpp
   if(IsRelevantNewsWindow(s.ccy1, s.ccy2, TimeTradeServer(), InpNewsBlockMinutes))
     {
      candidate.rejection = "news_blackout";
      g_news_blocked_this_day = true;   // <-- add this line
      return false;
     }
   ```
6. In `ProcessRollover()`, after the qualifying-day estimation block (~line 3396,
   after the `g_estimated_profitable_days` update) and before `g_server_day_key = key`,
   add:
   ```cpp
   // News-block inactivity tracking: count consecutive days where a signal
   // existed but was exclusively gated by the news blackout with no trade completing.
   int day_trade_count = 0;
   double dummy1 = 0.0, dummy2 = 0.0; bool dummy3 = false;
   RebuildDailyClosedTrades(day_trade_count, dummy1, dummy2, dummy3);
   if(g_news_blocked_this_day && day_trade_count == 0)
     {
      g_news_blocked_days_streak++;
      if(g_news_blocked_days_streak >= InpNewsBlockInactivityThreshold)
         LogEvent("ERROR", "NEWS_BLOCK_INACTIVITY_RISK",
                  StringFormat("streak=%d days; calendar coverage may cause inactivity breach",
                               g_news_blocked_days_streak));
     }
   else
      g_news_blocked_days_streak = 0;
   g_news_blocked_this_day = false;
   ```
7. In `tests/test_source_contract.py`, add `test_news_block_day_counter_structure`
   asserting the five items in Expected Outcomes.
8. Run `python3 -m unittest discover -s tests -v` — all 50 tests must pass.

### Relevant Context

- `PrepareCandidate()` news gate: `TRIAD_R_HS.mq5` lines 2368–2372.
- `PersistAccountState()`: `TRIAD_R_HS.mq5` lines 549–581.
- `AccountStateSignature()`: `TRIAD_R_HS.mq5` lines 395–409.
- `ProcessRollover()`: `TRIAD_R_HS.mq5` lines 3308–3420 — the qualifying-day
  estimation block ends around line 3396; `g_server_day_key = key` is at line 3398.
- The5ers inactivity rule: 30 consecutive calendar days → account closed.
- `CheckInactivity()`: `TRIAD_R_HS.mq5` lines 1502–1528 — existing alert at 20/25
  days; this new counter is complementary and fires earlier on news-pattern clusters.

---

## Sub-Task 3 — Escalate `STATS_INSUFFICIENT` from WARN to ERROR

**Status:** `[x] done`

### Intent

`ComparableStatistics()` currently logs `STATS_INSUFFICIENT` at `WARN` level when
fewer than 60 comparable sessions are found in history. Because the function
immediately returns `false` → `NO_TRADE`, this is operationally equivalent to an
error: the EA will silently skip every signal until the broker loads enough historical
bars. Upgrading to `ERROR` level makes it appear prominently in the operator's MT5
Experts tab and in the audit CSV, enabling rapid diagnosis when the issue is systematic
(e.g., insufficient history depth on a newly attached terminal).

This is a one-line change and carries no logic risk.

### Expected Outcomes

- In `ComparableStatistics()` (~line 1193), `"WARN"` is replaced with `"ERROR"` for
  the `"STATS_INSUFFICIENT"` log event.
- No other code changes in this function.
- New Python contract test `test_stats_insufficient_is_error_level` verifies the
  `ERROR` level is used for the `STATS_INSUFFICIENT` event name.
- All 51 tests pass.

### Todo List

1. In `ComparableStatistics()` at line 1193, change:
   ```cpp
   LogEvent("WARN","STATS_INSUFFICIENT", ...);
   ```
   to:
   ```cpp
   LogEvent("ERROR","STATS_INSUFFICIENT", ...);
   ```
2. In `tests/test_source_contract.py`, add `test_stats_insufficient_is_error_level`:
   ```python
   def test_stats_insufficient_is_error_level(self) -> None:
       # STATS_INSUFFICIENT causes a NO_TRADE with no way to recover in the same
       # session; it must appear as ERROR so the operator sees it immediately.
       self.assertIn('"ERROR","STATS_INSUFFICIENT"', self.source)
       self.assertNotIn('"WARN","STATS_INSUFFICIENT"', self.source)
   ```
3. Run `python3 -m unittest discover -s tests -v` — all 51 tests must pass.

### Relevant Context

- `ComparableStatistics()`: `TRIAD_R_HS.mq5` lines 1140–1200, specifically line 1193.
- Existing pattern: `LogEvent("ERROR", ...)` is already used throughout the EA for
  conditions that block trading and require operator attention
  (e.g., `NEWS_FILE_OPEN`, `NEWS_ROW_INVALID`, `SYMBOL_SELECT`).

---

## Execution Order and Dependencies

```
Sub-Task 3 (one-line change, zero risk)
       |
Sub-Task 1 (new indicator + gate — most complex)
       |
Sub-Task 2 (new persisted counter — touches PersistAccountState)
       |
Final: run full test suite (must show 51 tests pass)
```

Sub-Task 3 can be done first as a warm-up because it is a single-character change
and its contract test is trivial to write. Sub-Task 1 is the most structural change
and should be reviewed in isolation. Sub-Task 2 is last because it touches
`PersistAccountState()` and `AccountStateSignature()`, which are the most sensitive
state-management functions — these must be changed carefully and verified to match.

---

## What Is Not Changed

| Component | Reason |
|---|---|
| Entry contract (sweep/reclaim/displacement parameters) | Frozen by `ValidateInputs()` and registry |
| Stop formula | Frozen by `ValidateInputs()` |
| Risk profiles A/B/C/D | Frozen by `ValidateInputs()` and contract tests |
| Drawdown throttle (2%/5%) | Frozen by `ValidateInputs()` and contract tests |
| Daily state machine | No change — daily lock/second-trade logic untouched |
| Compliance guardrails (no grid, no partial close, visible stop) | No change |
| News flat/block windows | Values unchanged; only a day-streak counter is added |
| 160-config registry | Unchanged — new filter defaults to `false` |
| EA build ID string | Updated in Sub-Task 1 to `TRIAD_R_HS_2.1.6_YYYYMMDD` to
  reflect the code change. The `test_canonical_and_runtime_files_exist` test
  must be updated to match the new build ID. |

---

## Build ID Update

When Sub-Task 1 is implemented, update the build ID constant at line 199:
```cpp
const string EA_BUILD_ID = "TRIAD_R_HS_2.1.6_<date>";
```
And update the corresponding assertion in `tests/test_source_contract.py`:
```python
self.assertIn('EA_BUILD_ID = "TRIAD_R_HS_2.1.6_<date>"', self.source)
```
Use today's date in `YYYYMMDD` format.
