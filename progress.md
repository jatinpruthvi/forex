# TRIAD-R High Stakes — Project Progress Log

**Purpose:** This file is a complete, AI-readable handoff document. If work stops, the next AI model can read this file and resume without re-analysing the whole codebase from scratch.

---

## 1. Project Goal

Pass the **The5ers $2,500 New High Stakes** prop-fund challenge using a fully automated MQL5 Expert Advisor called **TRIAD-R High Stakes (TRIAD_R_HS)**.

### Challenge rules (The5ers New High Stakes $2,500)
| Rule | Value |
|---|---|
| Starting balance | $2,500 |
| Phase 1 profit target | +10% → reach $2,750 |
| Phase 2 profit target | +5% → reach $2,625 (of phase 2 start) |
| Daily loss limit | 5% of current balance |
| Overall drawdown floor | 10% of starting balance (account cannot drop below $2,250) |
| Qualifying days required | Minimum 3 days per phase with at least $12.50 net profit each |
| Inactivity limit | 30 calendar days without any trade |
| Time limit | Unlimited |

---

## 2. Strategy Summary (TRIAD-R Sleeve A)

**Name:** TRIAD-R — three-instrument sweep/reclaim strategy
**Active sleeve:** Sleeve A only — EURUSD London session
**Signal logic (M5 bars, frozen V2.1 geometry):**
1. Build an **Asian reference range** (London 00:00–07:00 wall time = server 02:00–09:00 or 03:00–10:00 depending on DST)
2. In the **entry window** (London 07:00–11:00 wall = server 09:00–13:00 BST or 10:00–14:00 GMT):
   - Detect a **sweep**: any M5 bar low/high that breaches the range by 0.05–0.50 × ATR(M15, 14-period)
   - Detect a **reclaim**: within the next 3 bars (including sweep bar), a close that returns inside the range, with wick ratio ≥ 0.60 in the sweep direction
   - Detect a **displacement**: the bar immediately after the reclaim — body ratio ≥ 0.60, close beyond the reclaim bar midpoint, in the direction of the sweep
3. Place a **buy/sell limit order** at 50% retrace of the displacement body
4. Stop = sweep extreme ± 0.10 × ATR; stop distance must be 0.60–1.50 × ATR
5. Target = 1.50R (Profile A, 0.40% risk per trade)
6. Time stop = 45 minutes (Profile A default)
7. All trades cut at London session end (11:00 wall time)

**Risk profile (Profile A):**
- Risk per trade: 0.40% of current balance
- Target: 1.50R
- Time stop: 45 minutes
- Drawdown throttle: risk halved at 2% drawdown; halt at 5%

---

## 3. Repository Structure

```
forex/
├── MQL5/
│   ├── Experts/
│   │   ├── TRIAD_R_HS/
│   │   │   ├── TRIAD_R_HS.mq5          ← MAIN EA SOURCE (currently build 2.1.6)
│   │   │   └── README.md
│   │   └── TRIAD_SCREEN/
│   │       ├── TRIAD_SCREEN.mq5         ← Screening/demo tool (unchanged)
│   │       └── README.md
│   └── Files/
│       └── triad_red_news.csv.example   ← News calendar template
│
├── tools/
│   ├── aggressive_optimizer.py          ← ACTIVE — multi-pair M5 optimizer (11 pairs, 60 combos, 3 bugs fixed)
│   ├── strategy_optimizer.py            ← SUPERSEDED — older tick-based optimizer (requires tick CSVs, not present)
│   ├── tick_signal_builder.py           ← Tick CSV → observed_events.csv
│   ├── strategy_orb.py                  ← ORB backtest v1 (tick data, 3 pairs)
│   ├── replay_export.py                 ← observed_events.csv → replay_rows.csv
│   ├── triad_validation.py              ← replay_rows.csv → champion_report.json
│   ├── triad_ablation.py                ← ablation study runner
│   └── __init__.py
│
├── tests/
│   ├── test_source_contract.py          ← MODIFIED (+3 new tests for 3 improvements)
│   ├── test_validation.py               ← unchanged
│   ├── test_reference.py                ← unchanged
│   ├── test_screen_ea_contract.py       ← unchanged
│   ├── test_extended_validation.py      ← unchanged
│   ├── test_bugfix_regressions.py       ← unchanged
│   ├── test_ablation_scaffold.py        ← unchanged
│   └── triad_reference.py               ← unchanged
│
├── validation/
│   ├── triad_v2_1_registry.json         ← FROZEN — 160 configs, DO NOT MODIFY
│   ├── triad_v2_2_ablation_registry.json← ablation registry
│   ├── HistoryData/                     ← 11 M5 OHLCV files (Jan 2024–Sep 2026, ~9.5 MB each)
│   │   ├── eurusd-m5-fsb.csv
│   │   ├── gbpusd-m5-fsb.csv
│   │   ├── eurgbp-m5-fsb.csv
│   │   ├── gbpjpy-m5-fsb.csv
│   │   ├── eurjpy-m5-fsb.csv
│   │   ├── audusd-m5-fsb.csv
│   │   ├── nzdusd-m5-fsb.csv
│   │   ├── usdcad-m5-fsb.csv
│   │   ├── usdchf-m5-fsb.csv
│   │   ├── usdjpy-m5-fsb.csv
│   │   └── xauusd-m5-fsb.csv
│   ├── EURUSD_London_observed_events.csv ← OUTPUT of tick_signal_builder.py (6 signals)
│   ├── triad_replay_rows.csv             ← OUTPUT of replay_export.py build
│   └── champion_selection_report.json    ← OUTPUT of triad_validation.py validate
│
├── findings_aggressive_optimizer.md     ← Session 4 optimizer results (CURRENT)
├── findings_orb_strategy.md             ← ORB v1 results (session 3)
├── signal-rate-research-findings.md     ← Grid search on sweep/reclaim signal rate
├── THE5ERS-CHALLENGE-STRATEGY-V2.md     ← MASTER SPEC — canonical strategy document
├── TRIAD_R_HS-CODE-REVIEW.md            ← Fifth-pass static code review
├── prop-fund-challenge-improvement-plan.md ← Master improvement plan
├── strategy-improvements-plan.md        ← Plan for 3 EA code improvements (all done)
├── progress.md                          ← THIS FILE
└── [many studyarena-*.md files]         ← Unrelated competition files, ignore
```

---

## 4. Key Configuration Values (Frozen EA Contract)

These values are locked in the EA and must not be changed without re-running the full validation pipeline.

| Parameter | Value | Location in EA |
|---|---|---|
| `InpSweepAtrMin` | 0.05 | line ~122 |
| `InpSweepAtrMax` | 0.50 | line ~123 |
| `InpReclaimBars` | 3 | line ~124 |
| `InpReclaimWickMin` | 0.60 | line ~125 |
| `InpDisplacementBodyMin` | 0.60 | line ~126 |
| `InpStopBufferAtr` | 0.10 | line ~128 |
| `InpStopAtrMin` | 0.60 | line ~129 |
| `InpStopAtrMax` | 1.50 | line ~130 |
| `InpMaxCostToR` | 0.10 | line ~131 |
| `InpProfile` | A (0.40%, 1.50R) | line ~107 |
| `InpTimeStopMinutes` | 45 | line ~113 |
| `EA_BUILD_ID` | `TRIAD_R_HS_2.1.6_20260905` | line ~209 |

---

## 5. Completed Work

### 5.1 Three Code Improvements to EA (Session 3 — All Done)

#### Sub-Task 1: H1 50-EMA Directional Bias Filter
- **What it does:** Optional filter (`InpRequireH1EmaBias`, default `false`) that rejects counter-trend setups.
- **Status:** ✅ Implemented and tested
- **Test:** `tests/test_source_contract.py::test_h1_ema_bias_filter_structure`

#### Sub-Task 2: News-Blocked Day Inactivity Counter
- **What it does:** Counts consecutive days where a signal was blocked by news AND no trade completed. Logs `ERROR NEWS_BLOCK_INACTIVITY_RISK` when count hits `InpNewsBlockInactivityThreshold` (default 3).
- **Status:** ✅ Implemented and tested
- **Test:** `tests/test_source_contract.py::test_news_block_day_counter_structure`

#### Sub-Task 3: STATS_INSUFFICIENT Log Level WARN → ERROR
- **What it does:** Changed the `STATS_INSUFFICIENT` log event from `WARN` to `ERROR`.
- **Status:** ✅ Implemented and tested
- **Test:** `tests/test_source_contract.py::test_stats_insufficient_is_error_level`

#### Build ID Bump
- `EA_BUILD_ID = "TRIAD_R_HS_2.1.6_20260905"` (line 209)

### 5.2 Test Suite Status

```bash
python -m pytest tests/ -v
```

- **171 total tests — 171 pass, 0 fail** (tzdata installed, EA committed at `cfb7f45`)

### 5.3 Validation Pipeline (Session 3 — Limited by Data)

Full pipeline runs end-to-end. Blocked by insufficient tick data volume:
- Only 196 trading days of tick data → 6 signals
- Minimum gate requires ≥300 aggregate fills
- Status: `NO_CHAMPION_SELECTION_GATES` (expected — not a bug)

### 5.4 Multi-Pair Optimizer — Session 4 (COMPLETED)

#### What was built
`tools/aggressive_optimizer.py` — a standalone Python backtester that:
- Loads all 11 M5 pairs from `validation/HistoryData/`
- Runs 3 strategies × 4 target-R values × 3 ORB window sizes × 3 ATR stop fractions = **60 combinations**
- Simulates bar-level exit scanning (high/low touch = exit at exact price)
- Uses **fixed $2,500 lot sizing** (no compounding) matching challenge risk model
- Max 2 trades per day across all pairs
- DST-correct London and NY session windows
- Writes `findings_aggressive_optimizer.md` automatically

#### Bug diagnosed and fixed (Session 4)
**Bug:** Max drawdown was reported as 83–86% across all combinations, causing the leaderboard to show "no viable combos".

**Root cause:** The drawdown formula compared the global all-time equity peak against the global all-time trough, regardless of sequence:
```python
# WRONG (old):
mins = min(v for _, v in equity)          # all-time low = starting balance
mdd  = (peak_balance - mins) / peak_balance * 100  # = total return, not drawdown
```
Since the strategy is monotonically profitable, `mins` = start balance ($2,500) and `peak_balance` = end balance (~$15k), giving `(15k-2.5k)/15k = 83%` — which is the total return framed as a fake "drawdown", not an actual account drop.

**Fix applied:** True sequential peak-to-trough drawdown:
```python
# CORRECT (new):
_running_peak = ACCOUNT_BALANCE
_max_dd_abs   = 0.0
for _, _v in equity:
    _running_peak = max(_running_peak, _v)
    _max_dd_abs   = max(_max_dd_abs, _running_peak - _v)
mdd = _max_dd_abs / _running_peak * 100
```

**Fix location:** [`tools/aggressive_optimizer.py`](tools/aggressive_optimizer.py) lines 443–449.

#### Clean results after fix

**All 20 leaderboard entries pass Phase 1. Every viable combo is `orb_atr` with `ATR_stop=0.25`.**

Top 3 configurations:

| # | Strategy | Target R | ORB bars | ATR stop | Win% | Avg R | Max DD | Phase 1 |
|---|---|---|---|---|---|---|---|---|
| 1 | `orb_atr` | 3.0R | 8 (40 min) | 0.25×ATR | 59.1% | 1.294 | 0.3% | **10 days** |
| 2 | `orb_atr` | 2.5R | 8 (40 min) | 0.25×ATR | 65.6% | 1.225 | 0.3% | **10 days** |
| 3 | `orb_atr` | 2.0R | 8 (40 min) | 0.25×ATR | 72.3% | 1.101 | 0.2% | **10 days** |

**Best config detail (TR=3.0, RB=8, ATR_stop=0.25):**
- 1,424 signals over 738 trading days (~2.5 years)
- Profit factor: 4.22 | Monthly P&L: $465 | Final balance: $18,858
- Top contributing pairs: GBPJPY ($5,639), XAUUSD ($5,537), EURJPY ($4,960)
- Real max drawdown: **0.3%** (the strategy only ever moves up)

Full results in [`findings_aggressive_optimizer.md`](findings_aggressive_optimizer.md).

---

## 6. Data Files

### M5 OHLCV Files (11 pairs — primary data for optimizer)
| File | Bars | Days | Coverage |
|---|---|---|---|
| `validation/HistoryData/eurusd-m5-fsb.csv` | 200,000 | 837 | Jan 2024 – Sep 2026 |
| `validation/HistoryData/gbpusd-m5-fsb.csv` | 200,000 | 838 | Jan 2024 – Sep 2026 |
| `validation/HistoryData/eurgbp-m5-fsb.csv` | 200,000 | 837 | Jan 2024 – Sep 2026 |
| `validation/HistoryData/gbpjpy-m5-fsb.csv` | 200,000 | 838 | Jan 2024 – Sep 2026 |
| `validation/HistoryData/eurjpy-m5-fsb.csv` | 200,000 | 838 | Jan 2024 – Sep 2026 |
| `validation/HistoryData/audusd-m5-fsb.csv` | 200,000 | 838 | Jan 2024 – Sep 2026 |
| `validation/HistoryData/nzdusd-m5-fsb.csv` | 200,000 | 837 | Jan 2024 – Sep 2026 |
| `validation/HistoryData/usdcad-m5-fsb.csv` | 200,000 | 838 | Jan 2024 – Sep 2026 |
| `validation/HistoryData/usdchf-m5-fsb.csv` | 200,000 | 838 | Jan 2024 – Sep 2026 |
| `validation/HistoryData/usdjpy-m5-fsb.csv` | 200,000 | 837 | Jan 2024 – Sep 2026 |
| `validation/HistoryData/xauusd-m5-fsb.csv` | 200,000 | 879 | Jan 2024 – Sep 2026 |

**Format:** `timestamp_ms_utc, open, high, low, close, volume` (no header in data rows, header row present)

### M5 File Instrument Specs
| Symbol | pip | tick_value ($/lot/pip) | tick_size | Notes |
|---|---|---|---|---|
| EURUSD | 0.0001 | $10.00 | 0.00001 | Standard USD quote |
| GBPUSD | 0.0001 | $10.00 | 0.00001 | Standard USD quote |
| EURGBP | 0.0001 | $10.00 | 0.00001 | Cross — GBP quoted, TV approx |
| AUDUSD | 0.0001 | $10.00 | 0.00001 | Standard USD quote |
| NZDUSD | 0.0001 | $10.00 | 0.00001 | Standard USD quote |
| USDCAD | 0.0001 | $10.00 | 0.00001 | USD base — TV approx |
| USDCHF | 0.0001 | $10.00 | 0.00001 | USD base — TV approx |
| USDJPY | 0.01 | $9.09 | 0.001 | JPY quote |
| EURJPY | 0.01 | $9.09 | 0.001 | JPY quote |
| GBPJPY | 0.01 | $9.09 | 0.001 | JPY quote |
| XAUUSD | 0.10 | $1.00 | 0.01 | Gold: 1 standard lot = 100 oz |

### Tick Data File (original sweep/reclaim pipeline)
```
validation/HistoryData/EURUSD.i_202406190501_202609102250.csv
```
- **Coverage:** 2024-06-19 to 2025-03-21 = 196 trading days
- **Format:** tab-delimited `<DATE> <TIME> <BID> <ASK> <LAST> <VOLUME> <FLAGS>`
- **Result:** 6 signals / 196 days = 3.1% signal rate (too low for validation pipeline)

---

## 7. Critical Blocker: Insufficient Tick Data (Sweep/Reclaim Pipeline)

The sweep/reclaim validation pipeline needs ≥300 aggregate fills to select a champion. With 6 signals from 196 days, it needs ~100 times more data.

**What is needed:** EURUSD tick data from Eightcap (or any MT5 broker) going back to at least 2022, ideally 2019. Same tab-delimited format. See §9 for pipeline run commands.

**Important:** This blocker only affects the original TRIAD-R sweep/reclaim EA validation. The new ORB optimizer (`aggressive_optimizer.py`) does not use tick data — it runs entirely on the M5 OHLCV files already present.

---

## 8. Validation Pipeline Architecture (Sweep/Reclaim)

```
tick CSV
  ↓
tools/tick_signal_builder.py
  ↓
validation/EURUSD_London_observed_events.csv   (42-column schema, one row per signal)
  ↓
tools/replay_export.py build
  --event-file <observed_events>
  --configs validation/triad_v2_1_registry.json
  --selection-split YYYY.MM.DD YYYY.MM.DD
  --holdout-split   YYYY.MM.DD YYYY.MM.DD
  --output validation/triad_replay_rows.csv
  ↓
validation/triad_replay_rows.csv
  ↓
tools/triad_validation.py validate
  --registry validation/triad_v2_1_registry.json
  --input validation/triad_replay_rows.csv
  --output validation/champion_selection_report.json
  ↓
validation/champion_selection_report.json   (champion config or NO_CHAMPION_SELECTION_GATES)
```

### Minimum Gates for Champion Selection
| Gate | Threshold |
|---|---|
| `minimum_combination_fills` | 100 fills per instrument/session combination |
| `minimum_aggregate_fills` | 300 total fills across all combinations |
| `minimum_combination_profit_factor` | 1.15 |
| `minimum_aggregate_profit_factor` | 1.30 |
| `minimum_aggregate_expectancy_r` | 0.20R per trade |
| `minimum_phase1_pass_probability` | 0.70 (70%) |
| `minimum_phase2_pass_probability` | 0.85 (85%) |
| `minimum_joint_pass_probability` | 0.60 (60%) |
| `maximum_p99_drawdown_fraction` | 0.06 (6%) |

---

## 9. Pipeline Commands (Full Run)

### Run aggressive optimizer (M5 data — no tick data needed)
```bash
python tools/aggressive_optimizer.py
# Runs in ~3 minutes, writes findings_aggressive_optimizer.md
```

### Run tick signal builder
```bash
python tools/tick_signal_builder.py \
    --tick-file validation/HistoryData/EURUSD.i_202406190501_202609102250.csv \
    --output validation/EURUSD_London_observed_events.csv \
    --combination EURUSD_LONDON
```

### Run replay export
```bash
python tools/replay_export.py build \
    --event-file validation/EURUSD_London_observed_events.csv \
    --configs validation/triad_v2_1_registry.json \
    --selection-split 2024.06.19 2025.01.31 \
    --holdout-split 2025.02.01 2025.03.21 \
    --output validation/triad_replay_rows.csv
```

### Run validation
```bash
python tools/triad_validation.py validate \
    --registry validation/triad_v2_1_registry.json \
    --input validation/triad_replay_rows.csv \
    --output validation/champion_selection_report.json
```

### Run tests
```bash
pip install pytest tzdata   # one-time setup
python -m pytest tests/ -v
# Expected: 171 pass, 0 fail
```

---

## 10. MetaEditor Compilation (Pending)

The EA source at `MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5` (build 2.1.6) has NOT yet been compiled in MetaEditor.

**MetaEditor path:** `C:\Program Files\Eightcap Global MT5 Terminal\MetaEditor64.exe`

**Steps:**
1. Open MetaEditor
2. Open `TRIAD_R_HS.mq5`
3. Compile (F7) — must produce zero errors, zero warnings
4. Compute SHA-256 of compiled `.ex5` file and record it
5. Set `InpCompilationGatePassed = true` when deploying

---

## 11. Remaining Tasks (In Priority Order)

| # | Task | Status | Notes |
|---|---|---|---|
| 1 | Commit EA changes to git | ✅ DONE | commit `cfb7f45` |
| 2 | All 171 tests pass | ✅ DONE | 0 failures |
| 3 | Multi-pair optimizer bug fix | ✅ DONE | max_dd formula fixed (session 4) |
| 4 | Clean leaderboard | ✅ DONE | Top 20 combos all pass Phase 1 in 10–14 days |
| 5 | Compile EA in MetaEditor | ⬜ PENDING | Needs user to run MetaEditor |
| 6 | Obtain more EURUSD tick data (ideally 2019–present) | ⬜ PENDING | For sweep/reclaim pipeline only |
| 7 | Re-run sweep/reclaim pipeline with more data | ⬜ PENDING | Depends on #6 |
| 8 | Forward-demo the best ORB config on MT5 demo | ⬜ PENDING | `orb_atr` T=3.0R RB=8bars ATR=0.25 |
| 9 | Champion selection report passes all gates | ⬜ PENDING | Depends on #7 |
| 10 | Implement winning ORB config in EA or new EA | ⬜ PENDING | Depends on #8 result |
| 11 | Set `InpEURUSDLondonGatePassed = true` and start challenge | ⬜ PENDING | Depends on all above |

---

## 12. Session History

### Session 1–2 (Pre-history)
- Repository scaffolded, TRIAD_R_HS EA core written, validation pipeline infrastructure built.

### Session 3 (EA improvements + tick data pipeline)
- **EA build 2.1.6**: H1 EMA filter, news streak counter, STATS_INSUFFICIENT→ERROR. Committed `cfb7f45`.
- **171 tests pass**.
- **`tick_signal_builder.py`** built and run: 6 signals from 196 days of tick data.
- Sweep/reclaim signal rate confirmed at ~3% — not a bug, by design.
- Pipeline blocked: needs ≥300 fills, only has 6.

### Session 4 — Part 1 (Multi-pair optimizer + first bug fix)
- **`aggressive_optimizer.py`** built: 11 pairs, M5 data, 60 combos, 3 strategies.
- **Bug A fixed**: `max_dd_pct` computed `(peak−start)/peak × 100` = total return mislabelled as drawdown. Fixed with sequential peak-to-trough equity scan.
- First clean run: leaderboard showed Phase 1 in 10 days, 0.3% DD. **BUT** pip-value bug and same-symbol bug not yet found at that point.
- All 11 M5 history files committed to `validation/HistoryData/`.

### Session 4 — Part 2 (Full code audit + 2 more bug fixes) — CURRENT

Systematic line-by-line audit of every function found two more critical bugs:

**Bug B — Pip value formula 10× wrong for all FX pairs:**
- `pv = tv * (pip/ts)` where `tv` was already the pip value → multiplied by `pip/ts = 10` a second time.
- EURUSD: formula gave $100/pip/lot, actual = $10. All FX lots were 10× undersized.
- XAUUSD was accidentally correct (its `tv=1.0` truly was a tick value, not pip value).
- Effect: gold dominated results artificially; FX pairs barely registered.
- Fix: replaced `tv/ts/pip` three-field spec with single `pv` field (USD/pip/lot), calibrated to 2024–2026 rates.

**Bug C — Same symbol consumed both daily slots:**
- XAUUSD (and EURUSD, GBPUSD) appeared in both `LONDON_PAIRS` and `NY_PAIRS`.
- Both daily trade slots could go to the same symbol every day — no diversification.
- Fix: `traded_syms` set enforces max 1 trade per symbol per day.

**Revalidated results after all 3 fixes:**
- Best config: `orb_atr` T=3.0R RB=8bars ATR=0.25 → Phase 1 in **15 trading days**, max DD **0.4%**, monthly P&L ~**$332**
- Avg winning trade: +$23, avg losing trade: −$10 (correct for $10 risk budget)
- Top pairs: GBPJPY ($4,509), EURJPY ($4,032), XAUUSD ($2,996)
- `strategy_optimizer.py` (older tick-based tool, superseded) committed for history.

---

## 13. Files Created or Modified by This Session (Session 4)

### Files Created (new)
| File | Purpose |
|---|---|
| `tools/aggressive_optimizer.py` | Multi-pair M5 optimizer — 60 combos, 11 pairs, 3 bugs fixed, final results |
| `tools/strategy_optimizer.py` | Older tick-based optimizer — superseded, committed for history |
| `findings_aggressive_optimizer.md` | Full findings with all 3 bug writeups and revalidated results |
| `validation/HistoryData/eurusd-m5-fsb.csv` | 200K M5 bars EURUSD (Jan 2024–Sep 2026) |
| `validation/HistoryData/gbpusd-m5-fsb.csv` | same for GBPUSD |
| `validation/HistoryData/eurgbp-m5-fsb.csv` | same for EURGBP |
| `validation/HistoryData/gbpjpy-m5-fsb.csv` | same for GBPJPY |
| `validation/HistoryData/eurjpy-m5-fsb.csv` | same for EURJPY |
| `validation/HistoryData/audusd-m5-fsb.csv` | same for AUDUSD |
| `validation/HistoryData/nzdusd-m5-fsb.csv` | same for NZDUSD |
| `validation/HistoryData/usdcad-m5-fsb.csv` | same for USDCAD |
| `validation/HistoryData/usdchf-m5-fsb.csv` | same for USDCHF |
| `validation/HistoryData/usdjpy-m5-fsb.csv` | same for USDJPY |
| `validation/HistoryData/xauusd-m5-fsb.csv` | same for XAUUSD |

### Files Modified
| File | What Changed |
|---|---|
| `tools/aggressive_optimizer.py` | Bug A: max_dd sequential scan; Bug B: pip value formula → single `pv` field; Bug C: 1-trade-per-symbol-per-day guard |
| `findings_aggressive_optimizer.md` | Full bug writeup + revalidated results after all 3 fixes |
| `progress.md` | This file — updated with session 4 full audit |

---

## 14. Key Architectural Rules (Do Not Break)

1. **Frozen entry geometry:** Never change `SWEEP_ATR_MIN`, `SWEEP_ATR_MAX`, `RECLAIM_WICK_MIN`, `DISPLACEMENT_BODY_MIN`, `STOP_BUFFER_ATR`, `STOP_ATR_MIN`, `STOP_ATR_MAX`. These are in the registry. Any change invalidates all prior validation work.

2. **Frozen registry:** `validation/triad_v2_1_registry.json` must never be modified. It was committed before any data was seen.

3. **One signal per session:** The EA and signal builder both enforce "first qualifying event per session only". Later same-day sweeps on the same combination are discarded.

4. **New inputs must default to V2.1 baseline:** Any new EA input must default to the old behaviour (e.g., `InpRequireH1EmaBias = false` preserves the baseline).

5. **All 39 contract tests must pass:** Run `python -m pytest tests/test_source_contract.py -v` before any EA change is considered done.

6. **Holdout data is never seen during champion selection:** The `--selection-split` and `--holdout-split` date ranges must be declared before generating the replay rows. The holdout is only evaluated after a champion is already selected from walk-forward data.

7. **Optimizer uses fixed $2,500 base:** Never switch to compounding during the challenge window — the $2,250 drawdown floor makes compounding blow-up risk too high.

---

## 15. Understanding the Signal Rate (Sweep/Reclaim)

The low signal rate (3%) is **correct and expected** for this setup. Why each category rejects days:

- **`too_deep` (60.7%):** Sweep extends beyond 0.50 ATR during the 3-bar reclaim window. Hard filter by design — rejects exhaustion moves. Not a bug.
- **`weak_wick` (26.0%):** Reclaim bar does not have a strong lower/upper wick. Ensures genuine rejection of the sweep.
- **`no_sweep` (4.1%):** Price never breaks the Asian reference range. Normal on low-volatility days.
- **`displace_wrong_dir` / `displace_weak_body` (4.6%):** The bar after the reclaim doesn't confirm continuation.

Net effect: ~3% of London sessions produce a qualifying sweep/reclaim. Fine for live challenge (only 3 qualifying days needed per phase), but needs many years of data for the statistical validation pipeline.

---

## 16. Instrument Specs — Why They Matter

The lot sizing formula in the optimizer:
```python
pv  = spec["tv"] * (spec["pip"] / spec["ts"])   # pip value per standard lot in USD
sp  = stop_dist / spec["pip"]                    # stop distance in pips
lpl = sp * pv + commission                        # $ loss per lot at stop
lots = ($10 risk) / lpl                          # lots to risk exactly $10
```

For XAUUSD: `pv = 1.0 × (0.10/0.01) = $10/lot/pip`. Gold ATR on M5 ≈ $0.9, M15 ATR ≈ $2.7, stop = 0.25×ATR ≈ $0.67 = 6.7 pips → lpl ≈ $71 → lots = 10/71 = 0.14 lots. Actual dollar risk ≈ $9.40. Correct.

For JPY pairs: `pv = 9.09 × (0.01/0.001) = $90.9/lot/pip`. GBPJPY M5 ATR ≈ 0.075, M15 ≈ 0.225, stop ≈ 0.056 = 5.6 pips → lpl ≈ $515 → lots = 10/515 = 0.02 lots. Correct.

---

## 17. Next AI Model: Where to Start

If you are the next AI model reading this file, here is the priority list:

### Immediate (no user input needed)
1. Run `python tools/aggressive_optimizer.py` — takes ~3 min, produces clean leaderboard.
2. Run `python -m pytest tests/ -v` — all 171 should pass.

### Requires user input
3. **Ask user**: "Please compile `TRIAD_R_HS.mq5` in MetaEditor (`C:\Program Files\Eightcap Global MT5 Terminal\MetaEditor64.exe`). Press F7, confirm zero errors and zero warnings."
4. **Ask user**: "Please load the best ORB config on MT5 demo and run it for 2 weeks: `orb_atr`, Target=3.0R, ORB=8 bars (40 min), ATR stop=0.25×ATR, pairs: GBPJPY + XAUUSD + EURJPY (London session 07:00–11:00)."
5. **Optionally ask user**: "If you want to validate the sweep/reclaim EA, please provide EURUSD tick data from Eightcap going back to 2019. Format: tab-delimited, columns `<DATE> <TIME> <BID> <ASK> <LAST> <VOLUME> <FLAGS>`."

### After demo results
6. Evaluate forward demo P&L vs backtest expectations.
7. If demo confirms edge → proceed to live challenge with `InpEURUSDLondonGatePassed = true`.

---

## 18. Test Suite Quick Reference

```bash
# Run all tests
python -m pytest tests/ -v

# Run only EA contract tests (quickest sanity check)
python -m pytest tests/test_source_contract.py -v

# Run only validation pipeline tests
python -m pytest tests/test_validation.py tests/test_extended_validation.py -v

# Expected result: 171 pass, 0 fail
```

---

## 19. Python Environment Requirements

```bash
pip install pytest tzdata
# No other non-standard libraries needed
# All tools use only: csv, json, math, datetime, pathlib, argparse, dataclasses, statistics, collections
```

Python version: 3.13 (tested and passing)

---

## 20. Session 5 — 4-Year Data Re-Test (2026-09-12)

Re-ran the full backtest over the **complete 4-year M5 dataset** (11 pairs, `2022-09-11 → 2026-09-11`, ~288K bars/pair, **3,168,720 bars total**). `load_pair` automatically prefers the longer `*-m5-2022-09-11_2026-09-11.csv` files over the 2-year `*-fsb.csv` files.

### Reproducibility result

The regenerated `findings_aggressive_optimizer.md` was **byte-identical to the previously committed version** — the session-4 results were already produced on the 4-year data; only the header text was stale (hardcoded "Jan 2024 – Sep 2026, ~2.5 years, 200K bars/pair").

**Fix:** `write_findings()` in `tools/aggressive_optimizer.py` now receives the actually-loaded data range and bar counts and writes them dynamically. Header now reads: `Data: 11 pairs M5 OHLCV, 2022-09-11 – 2026-09-11 (~4.0 years, ~288K bars/pair, 3,168,720 bars total)`.

### Grid re-run (60 combos, 4-year data) — confirmed

Top by (fastest Phase 1, then monthly P&L): `orb_atr` **T=3.0R RB=6 bars ATR=0.25** — Phase 1 in 8 trading days, $331.38/mo, PF 3.20, DD 0.5%.
Best monthly P&L (leaderboard #5): `orb_atr` **T=3.0R RB=8 bars ATR=0.25** — $358.78/mo, highest AvgR (1.006).

### Deep validation (`tools/_validate_4yr.py`) — champion `orb_atr` T=3.0R RB=8 ATR=0.25

| Metric | Value |
|---|---|
| Signals | 1,812 (1,090W / 719L / 3T) |
| Win rate | 60.2% |
| Avg R / Profit factor | 1.006 / 3.55 |
| Max drawdown | 0.38% |
| Total P&L | $17,853.56 over 1,045 trading days |
| Est. monthly P&L | $358.78 |
| Final balance | $20,353.56 (from $2,500) |
| Phase 1 | PASSED in 12 trading days |
| Qualifying days | 602 |

**Year-by-year (positive in every year):**
| Year | Equity | P&L | Max intra-year DD |
|---|---|---|---|
| 2022 (Sep–Dec) | $2,500 → $4,210 | +$1,710 | 0.94% |
| 2023 | $4,191 → $8,961 | +$4,771 | 0.91% |
| 2024 | $8,961 → $13,960 | +$4,998 | 0.42% |
| 2025 | $13,960 → $18,405 | +$4,445 | 0.39% |
| 2026 (Jan–Sep) | $18,405 → $20,354 | +$1,949 | 0.38% |

**Trade-economics sanity:** avg losing trade −$9.75 (≈ the $10 intended risk), avg winning trade +$22.78 (≈ 3R minus commission), avg time exit +$11.12. Lot sizing spot-checks correct for JPY pairs and XAUUSD.

**Known concentration:** GBPJPY + EURJPY + XAUUSD produce ~96% of total P&L ($17,124 of $17,854). The six other pairs contribute <$1,100 combined over 4 years. Treat the edge as a 3-instrument strategy (GBPJPY, EURJPY, XAUUSD) with optional extras, not an 11-pair system.

All 171 tests pass after the `write_findings` change.

---

## 21. Session 6 — Champion-Path Logic Audit + Live-Friction Analysis (2026-09-12)

Line-by-line audit of the challenge-winning code path (`orb_atr` T=3.0R RB=8 ATR=0.25 in `tools/aggressive_optimizer.py`) plus a quantified live-friction study (`tools/audit_champion_live.py`, new tool).

### Logic bugs found (champion path)
1. **Same-bar target/stop ambiguity awarded to the WIN** (`simulate()` checks target before stop). 84/1812 trades (4.6%) ambiguous; pessimistic resolution = −15% P&L, PF 3.55 → 2.94.
2. **Limit fills assumed without re-touch check.** 11.5% of signals never re-touch the orb level; those carry **26.7% of total P&L (364/369 winners)** — adverse selection. Market-chasing the close instead **destroys the strategy** (WR 60%→17.5%, negative). Edge = limit at the range boundary; live must accept missed runners.
3. **One-position rule violated by backtest:** 249/1045 days book overlapping holds (The5ers allows one position account-wide).
4. **Pip values frozen at 2024–26 mids:** 2022 risk oversized +17% (GBPJPY), +13% (EURJPY) — dollar-risk drift, R-stats unaffected.
5. **No news blackout modeled** (compliance rule + spike slippage).
6. Minor: M15-ATR grouping across session gaps; monthly normalization counts zero-trade days; day-end-only equity sampling.

Verified correct: DST helpers, session windows, loader, ATR, orb geometry filters, lot math (avg loss −$9.75 ≈ $10 risk), fixed-base sizing, 2/day + 1/symbol caps, daily/total floors with safety buffer, qualifying-day + Phase-1 logic, session-end flat, deterministic ordering.

### Live vs backtest (4-year data, champion RB=8)

| Scenario | PF | Mth$ | Phase 1 |
|---|---|---|---|
| Backtest as coded | 3.55 | $359 | 12d |
| Raw acct (55% spread + $7/lot) | 2.13 | $219 | 14d |
| + ambiguity coin-flip | 1.76 | $165 | 17d |
| **Honest live estimate (stacked + missed fills + overlap/news)** | **~1.6–2.0** | **~$135–180** | **~35–55 trading days** |
| Pessimistic | 1.5 | ~$95–130 | ~2–3 months |

Per-pair under raw-account friction: EURJPY $3.8K · GBPJPY $3.5K · XAUUSD $3.3K over 4y; **all other 8 pairs <$350 combined → trade the 3 core pairs only.**

### Decisions
- Fix `simulate()` (re-touch requirement + pessimistic ambiguity mode), per-day pip values, news blackout, one-position semantics (Section 4 of `findings_live_friction_audit.md`).
- Demo gate: EURJPY+GBPJPY+XAUUSD, limit entries, raw spread; go-live needs demo ≥ ~$140/month run-rate.
- The5ers has no time limit → even pessimistic estimate passes; risk is execution quality + news compliance, not edge sign.

---

## 22. Session 7 — Fill-Semantics Bugs FIXED in Code; Strategy De-Certified Pending Tick Data (2026-09-12)

Follow-up to session 6: the four champion-path bugs were **fixed in `tools/aggressive_optimizer.py`** and everything re-run.

### Fixes (all guarded by `legacy=True` reproducing old numbers to the cent)
1. **Limit re-touch fills** (`require_touch=True` default): unfilled signals → no trade; exit scan starts at the fill bar.
2. **Ambiguity knob** (`stop_first`): True=pessimistic / False=optimistic / None=deterministic 50/50 coin (new grid default).
3. **One account-wide order/position slot**: chronological scheduling, cancel/replace, unfilled limit blocks its session slot.
4. **Per-day pip values** (`day_pv`): JPY/USDCAD/USDCHF from own-day close (USDCAD old constant $9.80 was wrong, true $7.41@1.35); EURGBP via same-day GBPUSD.
New tool version `tools/audit_champion_live.py` (rewritten on the fixed model) + 14 regression tests in `tests/test_optimizer_fill_logic.py` → **185/185 pass**.

### Results after the fix (4-year data, zero backtest costs)
- 11-pair old champion (T=3.0 RB=8): optimistic +$7.0K (PF 1.74) / **coin +$3.9K (PF 1.37, $78/mo)** / pessimistic **BUSTS the $2,250 floor**.
- Grid re-ranked: new best = 3-core **T=2.5R RB=6**: optimistic +$11.0K (PF 2.66, $220/mo) / coin +$5.5K (PF 1.66, $112/mo) / pessimistic BUST. Under pessimistic bound **no grid combo survives**.
- **13.5% of filled trades resolve on ambiguous bars** (fill bar spans stop and target) — expectancy is not identifiable from M5.

### With realistic costs (raw account: 55% spread + $7/lot; stops are 2–4.5 pips → cost = 40–65% of the $10 risk unit)
- Best survivor: 3-core T=2.5 RB=6 **optimistic bound**: +$5.2K (PF 1.57, $104/mo); +slippage still +$3.6K.
- **Coin-flip mid bound + costs: BUSTS in every universe/config.** 11-pair + costs: breakeven at the optimistic bound.

### Decision
- **The config is NOT certifiable from M5 data and must not go live/demo on this evidence.** Next mandatory step: tick/1-minute validation of the fill/ambiguity windows (`tools/tick_signal_builder.py` exists; request Eightcap tick data 2019+).
- If tick data confirms the optimistic path → 3-core only, raw account, T=2.5 RB=6, PF ~1.5.
- Redesign lever if it confirms coin/pessimistic: wider stops (≥0.5–1.0×ATR), re-optimize on the fixed simulator only.
---

## 23. Session 8 — 2-Year Gate: "Is the edge the bug?" Answer: Mostly Yes (2026-09-12)

Built `tools/optimizer_v2.py` (cost-aware: raw spread + $7/lot charged per trade inside the backtest; ambiguity-aware: coin-bound ranking + per-config ambiguity %; min-stop-pips filter; ATR-stop grid widened to 1.0×). Gate per user: validate on the 2-year FSB dataset first; only proceed to 4-year if promising.

### Data accuracy
2-year FSB files and 4-year files are **100% identical** on all overlapping 2024–26 bars (1,200 sampled, max diff 0.00000). Data inputs are clean.

### 2-year gate results (costs ON, coin bound)
- **60/72 combos negative; 59 halted at the $2,250 floor.**
- Best: `T=2.0R RB=8 ATs=0.25 minStop=6` → **+$24/mo (PF 1.29), Phase 1 in 405 trading days**; zero-cost coin = $45/mo; pessimistic+costs busts.
- **XAUUSD = 103% of champion P&L**; other 10 pairs net negative. Gold-only ≈ same result.
- Wider stops cut ambiguity exactly as engineered (15% → 1–8%) **but kill the edge** (ATs≥0.75 → negative). The tight stop WAS the edge.

### Verdict (per user gate): NOT PROMISING — 4-year run not warranted
Answer to "what if the bug is our strategy": to first order it was — the old $220–360/mo was adverse-selection fills + optimistic intrabar resolution + zero costs. Honest mid bound: $24/mo, ~19 months to Phase 1, sign still hostage to 13–16% path-dependent trades.

### Next steps (agreed priority)
1. Tick/1-minute data validation (only way to certify tight-stop M5 strategies; `tick_signal_builder.py` ready — need Eightcap tick export from user).
2. If tick confirms coin/pessimistic → pivot to TRIAD sweep/reclaim geometry (stops 0.6–1.5×ATR-M15 = 10–40 pips → cost share 2–5%, near-zero M5 ambiguity — structurally immune to this failure mode).
3. XAUUSD is the only keeper from the ORB family.

---

*Last updated: end of session 8 (2-year gate) (fill-semantics fixes + de-certification pending tick data). Session 6 found the 4 bugs; session 7 fixed them, re-ran everything, and showed the honest expectancy band is [bust, +$104/mo after costs] with the mid bound negative. 185 tests pass. Next: tick/1-min data validation before any MetaEditor compile/demo step.*
