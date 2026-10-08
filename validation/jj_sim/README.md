# JJ Simon 1-Minute Fair-Pricing — Pass-Rate Simulator

Implements the mechanical prop-firm strategy described in
`docs/strategy/JJ-SIMON-1MIN-FAIR-PRICING-STRATEGY.md`.

## Why this exists

JJ Simon's key insight is that **prop-firm strategies cannot be evaluated on a
single-account equity curve** because trailing drawdowns, consistency rules, and
"move to live" transitions break the assumptions live-trading backtests rely on.
The only metric that matters is **pass rate across many simulated evaluations**.

This simulator:

1. Replays M1 OHLCV bars chronologically.
2. Tracks fair price (session open / pre-news / post-unexpected consolidation).
3. Detects three mechanical signals — displacement candle (DC), break of
   structure (BoS), news reversion (NR).
4. Runs **N virtual accounts in parallel** through the same bar series with the
   firm rules (profit target, trailing drawdown, daily loss, consistency,
   minimum profitable days) enforced.
5. Layers trades: each signal goes to a fresh account (one per setup per
   session), mimicking JJ's 45+ account layering approach.
6. Reports pass rate, cost per funded account, EV per funded account, per-signal
   win rates, and failure reasons.

## Quick start

Run a smoke test on a synthetic NQ-like series (no real data required):

```bash
python3 validation/jj_sim/simulator.py --synthetic 500 --accounts 50 --config eval_1to1_5
```

Run across all preset firm configurations and dump JSON:

```bash
python3 validation/jj_sim/simulator.py \
    --synthetic 500 --accounts 50 --config all \
    --json-out validation/jj_sim/last_run.json
```

Run on real M1 CSV data (columns: `timestamp,open,high,low,close,volume` with
timestamps in milliseconds UTC, matching the existing
`validation/HistoryData/m1-data/*.csv` format):

```bash
python3 validation/jj_sim/simulator.py \
    --data path/to/NQ-m1.csv --news path/to/news.csv \
    --accounts 50 --config eval_1to1_5
```

Run on the existing EURUSD M1 data in this repo (note: JJ trades NQ futures,
not EURUSD — expect no edge here; this just demonstrates the loader):

```bash
python3 validation/jj_sim/simulator.py \
    --data validation/HistoryData/m1-data/eurusd-m1-2024-09-11_2026-09-11.csv \
    --accounts 50 --config eval_1to1_5
```

## Tests

```bash
python3 validation/tests/test_jj_sim.py
```

Covers:

* NY session window classification (DST-aware)
* Displacement candle detection (bullish/bearish/wrong-direction/tight-market)
* Break of structure detection
* Firm rule enforcement (drawdown breach, profit target)
* Three-consecutive-loss session kill switch
* End-to-end simulation on synthetic data (all accounts resolve)
* Dead-zone produces no trades
* All presets run without error
* M1 CSV loader (monotonic timestamps)

## Configuration presets (`FirmRules.presets()`)

| Preset | Start bal | Target | Overall DD | Daily | Trailing DD | Consistency | RR | Risk/trade |
|---|---:|---:|---:|---:|---|---|---:|---:|
| `eval_1to1` | $2,500 | 8% | 8% | 4% | no | no | 1.0 | 1.0% |
| `eval_1to1_5` | $2,500 | 10% | 10% | 5% | yes | no | 1.5 | 0.75% |
| `funded_consistency` | $25,000 | 10% | 6% | 3% | yes | yes | 1.5 | 0.5% |
| `funded_noconsistency` | $25,000 | 10% | 6% | 3% | yes | no | 4.0 | 0.5% |
| `the5ers_2500` | $2,500 | 10% | 10% | 5% | yes | 3-day × 0.5% | 1.5 | 0.5% |

You can add new presets by extending `FirmRules.presets()` in `simulator.py`.

## Signals

* **DC (displacement candle)** — body > 1.5× median(10) body; close within 10%
  of body of the wick extreme in the displacement direction; displacement is
  AWAY from fair price. Fast, lower win-rate — used for evaluations.
* **BoS (break of structure)** — a local 5-bar swing wick prints and price
  closes back through it in the fair-price direction. Higher win rate — used
  for funded accounts.
* **NR (news reversion)** — on the first close after a scheduled (red-folder)
  event, fade the initial impulse back to the pre-news consolidation.
  A+ setup. If the post-news candle is > 3× ATR(12) the event is treated as
  unexpected and we wait for a new consolidation to form.
* **SOC (session-open continuation)** — optional first-5-minutes continuation
  at 9:30. Off by default.

## News CSV format

```
timestamp_iso,kind,big_move_mult
2024-10-10 08:31:00-04:00,expected,1.5
2024-10-15 10:00:00-04:00,unexpected,1.5
```

`kind` is `expected` (scheduled red-folder; revert to pre-news) or `unexpected`
(unscheduled shock; new consolidation becomes fair price).

## What to do next

Per §11/§14 of the strategy spec:

1. **Acquire NQ M1 data** — 6+ months including CPI/NFP/FOMC events. The
   `scripts/history-data/dukascopy-node/` tools in this repo can download M1
   data from Dukascopy; wire them up for NAS100 / NQ proxy.
2. **Run a baseline backtest** with NR only (no DC, no BoS, no SOC) at RR 1.5
   on evals. Record pass rate.
3. **Add DC**, then **add BoS**; measure each signal's independent contribution
   to pass rate before combining.
4. **Sweep thresholds** (DC body_mult 1.3–2.0; BoS swing_lookback 2–3; NR
   big_move_mult 1.5–3.0) to find maxima.
5. **Validate contract sizing** with the actual NQ point multiplier ($5/point
   for micro NQ, $20/point for full NQ).
6. **Only then** consider porting the winning parameter set into an MQL5 EA,
   starting with demo / fail-closed mode.

## Output metrics

* `pass_rate` — fraction of simulated accounts that hit the profit target
  without breaching a rule.
* `cost_per_funded` — `eval_price / pass_rate`. Tells you how many eval dollars
  you burn per funded account on average.
* `ev_per_funded` — `expected_payout_per_funded × payout_rate`.
* `ev_per_eval_dollar` — profit per $1 spent on evals; positive ⇒ strategy is
  +EV at scale.
* `per_signal_stats` — per-signal-type trade count & win rate.
* `failure reasons` — histogram of which rule (daily loss, drawdown, …) killed
  failed accounts. Tells you which gate to tune.

## Caveats

* The synthetic data generator builds in a 58% reversion probability by
  construction, so pass rates on synthetic data are a smoke test only. Real
  NQ data may (and likely will) give lower pass rates.
* BoS detection is still relatively loose in v1 — trades on synthetic are
  dominated by BoS (which is what JJ says: higher win rate, more setups).
  Sweep `swing_lookback` and add a "distance from fair price" filter if it
  over-trades on real data.
* No spread/slippage model yet — the next step. JJ's edge depends on fills
  near the signal close; add a configurable spread gate per minute (as in
  THE5ERS plan §3 shared hard gates) before using results to size accounts.
* No trade cost/commission model. Add `commission_per_contract` and deduct
  from P&L before judging rules.
