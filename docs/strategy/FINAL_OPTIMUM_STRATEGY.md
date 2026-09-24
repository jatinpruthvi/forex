# FINAL OPTIMUM STRATEGY — Per-Pair 5-Pair Triad Stack + Gold Donchian

**Status:** Certified champion (2026-09-13) · **Objective:** maximum returns (PnL/CAGR), The5ers rules binding
**Backtest result:** **+$3,811.34 over 4 years** (2022-09 → 2026-09) on a $2,500 account — final equity **$6,311.34** (CAGR 26.1%, PF 2.25, max DD 4.5%)
**Reproduce:** `python tools/order_selector.py --confirm --pairfit --compound --risk 0.0175`

Everything in this document is implemented in this repository and every number was
re-verified by re-running the engine on the day the document was written. The
document describes the strategy exactly as the code executes it — constants below
were read from the source, not from memory.

---

## 1. Account framework (The5ers-style challenge, binding)

| Rule | Value |
|---|---|
| Starting balance | **$2,500** |
| Positions | **one** account-wide position at any time |
| Trades per day | max **2** (across both legs, all symbols) |
| Daily loss limit | trading stops for the day when balance ≤ day-start × (1 − 0.05 + 0.005) — i.e. a **4.5%** realized day loss (0.5% safety buffer before the 5% hard limit) |
| Total floor | **$2,250** (−10% from base) — permanent halt |
| Phase 1 target | **$2,750** sustained + 3 qualifying days (day PnL ≥ $12.50) |
| Broker model | raw account: **55% of standard spread + $7/lot round turn** (all costs inside every trade) |

Drawdown is a *reference metric only* — the optimization objective is maximum
returns, and the rules above are the hard constraints.

## 2. Data & time base

- **M5 OHLC history** (The5ers FSB dumps): 4y window `validation/HistoryData/`
  (2022-09-11 → 2026-09-11) and 2y gate window `validation/HistoryData/2-years-data/`.
  11 pairs; 6-column CSV (ts, open, high, low, close, volume). Volume is non-zero
  only inside the 2y window (the champion does not use volume).
- **All session times are London wall clock** (`Europe/London`, DST-aware);
  days are bucketed by London date. Weekends: no triad (FX); gold trades 24/5.
- **ATR (triad leg):** rolling **14×M15 range**. M15 bars are formed from 3
  consecutive M5 bars; only bars *before 07:00 London* on each day feed the
  accumulator (which carries across days), so day-d's ATR uses exclusively data
  available before the entry window opens — no look-ahead.
- **ATR (gold leg):** simple average of the last **14 daily (high − low)** bars
  ending yesterday.

## 3. Leg A — Triad sweep/reclaim/displacement (intraday)

### 3.1 Universe & per-pair configuration

Five pairs, each running the single logic variant it was best at on the 2y gate
(confirmed on 4y). All pairs share the base geometry; the table lists overrides
(`tools/order_selector.py`, `PAIRFIT_ASSIGN`):

| Pair | Target | Stop buffer | Sweep min | Signal cutoff | Session end | Time stop |
|---|---|---|---|---|---|---|
| **AUDUSD** | **2.5R** | 0.10 ATR | 0.02 ATR | — | 11:00 | 90 min |
| **EURJPY** | 1.5R | **0.05 ATR** | 0.02 ATR | — | **13:30** | **120 min** |
| **GBPJPY** | 1.5R | 0.10 ATR | **0.01 ATR** | — | 11:00 | 90 min |
| **USDJPY** | 1.5R | 0.10 ATR | 0.02 ATR | — | **13:30** | 90 min |
| **XAUUSD** | 1.5R | **0.05 ATR** | 0.02 ATR | **10:00** (no-late) | **13:30** | 90 min |

- **Sweep min** = minimum sweep depth in ATR units (relaxed-geometry default
  0.02; GBPJPY 0.01).
- **Signal cutoff** (no-late): triad signals accepted only in London hours
  07:00–10:00 (the 11:00–13:30 buckets were negative over 4y).
- **Session end**: flat-by time — any open trade is closed at market at the last
  M5 bar of the session; an unfilled limit order expires.
- Base geometry (relaxed champion): `SWEEP_ATR_MIN 0.02`, `RECLAIM_WICK_MIN 0.45`,
  `DISPLACEMENT_BODY_MIN 0.50`, sweep max `0.50 ATR`, stop band
  `0.60–1.50 ATR`, broker min-stop 2 pips.

### 3.2 Session windows

- **Reference range (Asian):** M5 bars in **[00:00, 07:00)** London — its high/low
  is the liquidity pool (needs ≥ 12 bars).
- **Entry window:** **[07:00, session end)**. The pattern must complete inside it.

### 3.3 Pattern definition (long; short is exact mirror)

The detector (`tools/triad_honest.py:detect`) emits **at most one signal per
pair per day**:

1. **Sweep** — the first M5 bar in the entry window whose low closes the pool:
   `low < ref_low − 0.02 × ATR` (sweep min), and which does *not* simultaneously
   sweep the other side (two-sided sweep → the day is consumed, no trade).
   Record `extreme = lowest low`. If the sweep exceeds `0.50 × ATR` depth → abort.
2. **Reclaim** — in the sweep bar itself or the **next 2 bars** (`disp_max = 2`),
   a bar that:
   - closes **back inside** the reference range (`ref_low < close < ref_high`),
   - makes a new extreme low (extreme updated; if the updated sweep then exceeds
     0.50 ATR → abort),
   - does not sweep the opposite side,
   - has a **close-side wick ≥ 45% of the bar's range** (the sellers' wick that
     rejected the move back inside).
3. **Displacement** — the bar **immediately after** the reclaim must be a
   **bullish candle with body ≥ 50% of its range, closing above the reclaim bar's
   midpoint**. This is the follow-through bar that licenses the trade.
4. **Signal** at the displacement bar's close (+5 min).

### 3.4 Entry, stop, target, exits

- **Entry: BUY LIMIT at `(displacement.open + displacement.close) / 2`** — the
  midpoint of the displacement bar (≈ 50% of the move). **Re-touch fill:** the
  order rests and fills when price trades through the limit price; if it never
  re-touchs by the session end, the signal is **dropped** (no fill, no trade).
- **Stop:** `extreme − buffer × ATR` (buffer 0.10 ATR default / 0.05 ATR for
  EURJPY & XAUUSD). The stop distance must fall in the **0.60–1.50 ATR band**
  (outside → signal rejected) and be ≥ 2 pips.
- **Target:** `1.5 × R` (AUDUSD `2.5 × R`), where R = |entry − stop|.
- **Time stop:** 90 min after the signal (EURJPY 120 min).
- **Session end:** flat by 11:00 (base) / 13:30 (EURJPY, USDJPY, XAUUSD).
- **Cost gate (EA rule `InpMaxCostToR = 0.10`):** a candidate is rejected if
  (spread + commission) > 10% of the target R in cash terms.

### 3.5 Trade economics (per $1 of risk)

Position size is set so that **initial risk = risk fraction × current balance**,
where initial risk = stop distance + one round turn of costs. Triad risk fraction
= **1.75% of current balance (compounding)** — the maximum compliant with the
5% daily cap while the gold leg runs 3%.

## 4. Leg B — Gold Donchian swing (XAUUSD, daily)

The uncorrelated second leg (multi-day). Semantics of `tools/swing_lab.py`,
ported live as `GoldLeg` in `tools/order_selector.py` (bit-identical standalone).

- **Channel:** N = **55 daily bars** — the highest high / lowest low of the 55
  days **ending the day before yesterday** (the breakout day and today are
  excluded — classic Donchian, live-tradable).
- **Signal, decided at the OPEN of day d using only data through d−1's close:**
  - yesterday's close **above** the 55-day high → **long at the open** (market),
  - yesterday's close **below** the 55-day low → **short at the open** (market).
- **Initial stop:** `entry ∓ 2.5 × ATR14` (same k as the breakout).
- **Management (chandelier), checked on every daily close including weekends:**
  - `extreme` = best close since entry; `trail = extreme ∓ 2.5 × ATR14`;
  - exit triggered when `close < max(stop0, trail)` (long) **or** when price
    closes back outside the opposite channel side.
  - **Exit fills at the next day's open** (close-based trigger, open-based fill —
    no intra-day stop chasing).
- **Risk:** **3% of current balance** per trade (compounding).
- **Warmup:** no signals until 55+14 daily bars of history exist.
- Weekend bar-days are **included** in the daily series (gold trades 24/5);
  excluding them would shift the channel windows and break the validated edge.

## 5. Portfolio mechanics (the one-slot layer)

This is where the value lives: two legs, **one position slot**, one shared
balance.

1. **Gold acts first, at the open.** If a gold entry/exit is decided at day d's
   open, it executes at the open (exit of the previous position first, then a
   possible new entry).
2. **While a gold position is open, the triad leg does not trade** — the gold
   swing holds the slot for its whole (multi-day) life. Triad candidates that
   day are skipped entirely.
3. **Selection policy P0 (chrono, first-available):** when the slot is free, the
   earliest candidate in time takes it. No scoring, no waiting, no upgrading.
   (The full policy family — P_PRO cost-gate, P1 score-bar, P2 patience, P3
   upgrade-only, P4 cross-leg gating, and the O1 hindsight oracle — was tested;
   **P0 is the live winner**, oracle is a diagnostic ceiling only.)
4. **Max 2 trades/day** across both legs; a symbol is traded at most once per day.
5. **Sizing is deterministic per candidate** (risk fraction × current balance),
   so every candidate's realized PnL is fixed before selection — selection
   cannot look ahead.

## 6. Cost & fill honesty layer (applies to every trade, every run)

- **Costs:** round-trip spread = 55% of standard-account spread, charged in
  price units: AUDUSD 0.00012 · USDJPY 0.014 · EURJPY 0.016 · GBPJPY 0.020 ·
  XAUUSD 0.28 — plus **$7/lot round turn** commission. Pip values per lot:
  AUDUSD 10.00 · USDJPY 6.76 · EURJPY 6.13 · GBPJPY 5.18 · XAUUSD 10.00.
- **Fill model:** limit orders fill on re-touch; market orders fill at the next
  bar's open. Unfilled = trade dropped.
- **Intra-bar ambiguity:** M5 OHLC cannot resolve the order in which stop and
  target are touched inside one bar. Every certified number is therefore run
  under **two models — coin (random 50/50) and stop-first (pessimistic)** —
  and the champion is **bit-identical under both** (and under the optimistic
  target-first). Certification requires identical results; any future addition
  must clear the **pessimistic floor** (stop-first, governors on) before it is
  accepted.
- All backtests run with the **challenge governors on** (5% daily stop, $2,250
  halt) — the reported numbers are what the account actually does.

## 7. Performance (verified 2026-09-13 by re-run)

### 7.1 Headline

| Window | PnL | Trades | Win rate | PF | CAGR | Max DD | Phase 1 | Final equity |
|---|---|---|---|---|---|---|---|---|
| **4y** (2022-09 → 2026-09) | **+$3,811.34** | 109 | 62.4% | 2.25 | 26.1% | 4.5% | day 282 | **$6,311.34** |
| **2y gate** (2024-09 → 2026-09) | **+$3,289.33** | 72 | — | 2.62 | 34.6% | 4.5% | day 115 | $5,789.33 |

- PnL is **bit-identical under coin and stop-first ambiguity** (certification).
- Worst day: **−$237.51** (3.80% of day-start equity) — inside the 4.5% daily
  stop with buffer; no halt triggered in 4y.
- Oracle (hindsight best-selection) ceiling: $13,967.21 (4y) / $7,866.09 (2y) —
  the distance between P0 and O1 is the cost of not knowing the future; P0 was
  chosen deliberately over any policy that needs re-selection.

### 7.2 By year (4y, partial calendar years at both ends)

| 2022-09→12 | 2023 | 2024 | 2025 | 2026-01→09 |
|---|---|---|---|---|
| −$23 | +$171 | +$615 | +$2,313 | +$734 |

2022-23 was flat-to-slightly-red — the regime the per-pair fit absorbed rather
than over-fit; the bulk of the 4y PnL arrives in 2025-26, so the 2y gate
($3,289.33, 86% of the 4y total) is the more representative forward figure.

### 7.3 By leg (4y)

| Leg | Trades | PnL | Notes |
|---|---|---|---|
| **Triad (5 pairs)** | 90 | **+$2,004** | below |
| **Gold Donchian** | 19 | **+$1,807** | ~47% of total PnL from 17% of trades |

### 7.4 By pair (triad leg, 4y)

| Pair | PnL |
|---|---|
| XAUUSD | +$843 |
| EURJPY | +$696 |
| AUDUSD | +$258 |
| GBPJPY | +$247 |
| USDJPY | **−$40** (ballast) |

## 8. Certification protocol (how this was selected — and stays selected)

1. **2y gate selects, 4y confirms.** Every candidate change (parameter, pair,
   filter, leg) must first pass on the 2y window; the 4y window then *confirms
   only* — no re-selection on 4y (bull-regime artifacts die in confirmation).
2. **Both ambiguity models, governors on**, bit-identical PnL required.
3. **Pessimistic-floor criterion (standing rule, adopted 2026-09-13):** any
   future leg or filter must clear the $2,250 floor under stop-first +
   governors before certification.
4. **Objective:** maximum returns; DD referenced, not optimized.

### Rejected and kept rejected (audit trail)

| Candidate | Result | Where |
|---|---|---|
| NY window for triad | rejected: "few signals, dilutes" | session 9 |
| M1 execution improvements | negative vs M5 fills | `findings_m1_lab.md` |
| S/R + price-action + volume families (11 variants, 121 cells, ~1,558 trades) | **0/121 qualify**, every family total negative | `findings_m1_lab.md` §10 |
| S/R-proximity filter on the stack | 2y −$1,792.26 | §10 |
| External PA/S/R/volume lab (separate checkout) | volume-zero claim disproved; their pessimistic-floor failure is a disqualifier our stack does not have; spread-widening proxy 2y −$99.16 | §11 |
| **External ORB + M1-slope strategy** | standalone PF 0.83–0.88, halts floor; **combination −$489.90 (2y) / −$535.09 (4y)**, DD 4.5→9.3 | §12 |
| Selection policies P_PRO/P1/P2/P3/P4 | all ≤ P0 | `findings_order_selector.md` |
| Sizing above 1.75%/3% | violates 5% daily cap | The5ers rules |

## 9. Caveats (read before trading this live)

1. **Multiple-comparison discount:** per-pair edges run PF ≈ 1.4–2.2, weaker
   than the aggregate 2.25. Five pairs × several variants were examined on the
   gate; treat the aggregate as the honest number and expect live decay.
2. **USDJPY is −$40 ballast** — kept because its signals share the slot with
   the profitable JPY cluster and cutting it changed nothing on 4y. If it goes
   persistently negative live, **cut USDJPY first**; it is the designated
   sacrificial pair.
3. **AUDUSD 2.5R is regime-conditional** — flat in 2022-23, positive after.
   It is the most likely pair to misbehave in a repeat of the 2022-23 regime.
4. **P1 speed trade:** the per-pair stack reaches Phase 1 ($2,750) in 282d on
   4y — slower than the uniform all-pairs base geometry — in exchange for far
   higher total ROI. If the live account needs Phase 1 *faster*, the uniform
   stack is the fallback, not the per-pair fit.
5. **M5 OHLC resolution:** same-bar stop/target order is genuinely
   unknowable from this data; the pessimistic model is the honest bound, and
   the champion is identical under both bounds, but live fills are a third
   regime. Expect slippage on the gold leg's open-based fills around
   news (FOMD, NFP).
6. **Volume data exists only in the 2y window** — any future volume-based
   addition can only be gate-tested, not 4y-confirmed.
7. **Data source:** single broker's FSB history. No multi-broker or tick
   validation; the next uncorrelated ROI lever is tick data or more
   instruments, not more filters on this data.
8. **Gold leg has no MQL5 EA in this repo** — it is backtest-certified
   (`swing_lab` semantics, bit-identical port). Either implement the EA
   (open-based Donchian + chandelier, weekend-aware) or execute it manually
   at the daily open. The triad leg has live EAs: `MQL5/Experts/TRIAD_R_HS`
   and `TRIAD_SCREEN`.

## 10. Reproduction

```bash
# full champion run (2y gate + 4y confirmation, P0, pairfit, compounding,
# 1.75% triad risk, 3% gold, challenge governors on):
python tools/order_selector.py --confirm --pairfit --compound --risk 0.0175

# test suite (201 tests + 4 subtests):
PYTHONPATH=. pytest -q

# standalone external-ORB reference battery (the rejected leg):
python tools/external_orb.py --run
```

**File map**

| File | Role |
|---|---|
| `tools/order_selector.py` | one-slot combo engine, `PAIRFIT_ASSIGN`, `GoldLeg`, governors, P0–O1 policies |
| `tools/triad_honest.py` | pattern detector + honest fill/exit sim (`detect`, `sim_triad`) |
| `tools/tick_signal_builder.py` | frozen geometry constants (relaxed vs canonical) |
| `tools/optimizer_v2.py` | data loader (M5 cache + 14-M15 ATR map), cost model (spreads/commission) |
| `tools/swing_lab.py` | gold Donchian reference implementation (equivalence-checked) |
| `tools/aggressive_optimizer.py` | account constants ($2,500, 5% day, $2,250 floor), specs, London time utils |
| `tools/sr_pa_lab.py` | rejected S/R/PA/volume battery (kept for audit) |
| `tools/external_orb.py` | rejected external ORB+M1 strategy (kept for audit) |
| `findings_m1_lab.md` | full research log: §9 per-pair fit, §10 S/R/PA/vol, §11 external review, §12 external ORB |
| `findings_order_selector.md` | selection-policy lab (why P0) |
| `MQL5/Experts/TRIAD_R_HS`, `TRIAD_SCREEN` | triad-leg live EAs |

**Change history:** champion = commit `b28b9c3` on
`arena/01a095f3-forex` (this document's parent history: `c283cfc` combo/M1/
per-pair fit → `7ec9df2` S/R/PA/vol rejection → `3aa8dd0` external review →
`b28b9c3` external ORB rejection).
