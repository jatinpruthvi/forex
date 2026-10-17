# NQ Real-Data Backtest Result (JJ Simon 1-min fair pricing — v1)

**Run date:** 2026-10-07
**Data:** `validation/HistoryData/nq-m1-data/NQ_1min_20260120_20260415.csv`
(axb0306/cme-futures-ohlc, E-mini Nasdaq-100 NQ, TopstepX feed, UTC timestamps)
**Range:** 2026-01-20 → 2026-04-15 (≈ 74 trading days, 83,919 M1 bars)
**Simulator:** `validation/jj_sim/simulator.py`
**Sweep:** `validation/jj_sim/sweep_nq.py` (24 configs × 20 accounts = 480 account-trials)
**Results CSV:** `validation/jj_sim/nq_sweep_results.csv`

---

## Bottom line

**The v1 fully-mechanical implementation of JJ's strategy is NOT profitable on
real NQ M1 data under the test conditions.**

The cleanest signal (displacement candles, DC) comes within 1–2 percentage
points of its breakeven win rate, but every configuration shows a win rate at
or below what its RR requires to break even, before spread, slippage,
commissions, or payout risk. Adding those real-world costs makes every config
lose money.

This is exactly why §11 of the strategy spec requires backtesting before an
EA is ever written: the gross synthetic pass rate (68%) collapsed to 0–25%
on real data.

---

## Top-of-table results (eval_1to1_5 settings, no cost model)

Run with `eval_1to1_5` preset: $2,500 account, 10% target, 10% trailing
drawdown, 5% daily loss, 0.75% risk/trade, RR=1.5:

| Metric | EURUSD M1 (wrong instrument) | NQ M1 (real JJ instrument) |
|---|---:|---:|
| Bars | 744,766 (2 years) | 83,919 (≈3 months) |
| Signals fired | 39,960 | 1,248 |
| Trades taken | 3,839 | 1,099 |
| Win rate | 38.7% | **28.9%** |
| Breakeven win rate (at RR 1:1.5) | 40.0% | 40.0% |
| Pass rate (50 accts) | 26% | **0%** (31/50 still active, 19 failed) |
| EV per $1 eval (gross) | +$0.56 | **−$1.00** |
| Dominant failure mode | drawdown | drawdown (19/19) |

EURUSD (wrong instrument) looked +EV by accident; NQ (the right instrument)
does not.

---

## Parameter sweep — best and worst configs

(Sorted by EV per $1 eval; positive = profitable on eval-cost math.)

| Signals | RR | Risk/trade | Trades | Win rate | Breakeven WR | Δ WR | Pass rate | Gross EV/$ |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| DC only | 3.0 | 1.0% | 501 | 23.6% | 25.0% | −1.4% | 25% (5/20) | **+$0.50** |
| DC only | 1.5 | 1.0% | 613 | 38.5% | 40.0% | −1.5% | 20% (4/20) | +$0.20 |
| DC only | 2.0 | 1.0% | 572 | 31.6% | 33.3% | −1.7% | 20% (4/20) | +$0.20 |
| BoS only | 3.0 | 1.0% | 385 | 19.0% | 25.0% | −6.0% | 20% (4/20) | +$0.20 |
| BoS only | 2.0 | 1.0% | 495 | 26.5% | 33.3% | −6.8% | 10% (2/20) | −$0.40 |
| DC+BoS | 1.5 | 1.0% | 618 | 29.9% | 40.0% | −10.1% | 0% | −$1.00 |
| DC+BoS | 2.0 | 0.5% | 789 | 22.4% | 33.3% | −10.9% | 0% | −$1.00 |

Key observations:

1. **DC is close to breakeven** — only 1–2 percentage points below required
   win rate across all RRs. That's within the noise floor of what spread and
   slippage could erase, but also within the range a more tuned entry could
   plausibly recover.
2. **BoS in its v1 form is a losing signal on NQ** — win rate sits 6–11
   points below breakeven for every RR. The detector fires ~3× more often
   than DC (2,888 vs 512 signals over the same period), which is a red flag
   that the swing-lookback (2 bars on each side = 5-bar swing) is too loose
   and is picking up noise rather than real structure breaks.
3. **Combining DC + BoS makes things worse, not better** — the loose BoS
   bleeds so much that it drags DC down with it. JJ's stated logic uses BoS
   on funded accounts specifically because it is *more* selective, not less;
   our v1 detector implements the opposite.
4. **Higher risk (1% vs 0.5%) shows higher pass rate** because accounts
   either hit the 10% target faster or blow up faster; this is variance, not
   edge, and is consistent with JJ's warning that lower RR + smaller risk
   is more stable for consistency accounts.
5. **No config shows a statistically significant positive edge.** Even the
   "+$0.50" top result is 5/20 passes — at 20 accounts that's well within
   binomial noise for a strategy at breakeven.

---

## What is still missing (and could change the answer)

These are the items JJ's strategy relies on that v1 of the simulator does
**not** yet model, and each of them is a plausible source of the missing
edge:

| Missing piece | Why it matters | Effort to add |
|---|---|---|
| **News reversion (NR) setups with real calendar** | JJ calls NR his A+ setup with the highest win rate. It is *disabled in effect* because no news events CSV was fed in. CPI/NFP/FOMC sessions over 3 months might be 8–12 events — small count but high win rate can dominate the expectancy. | Build a news CSV from FRED/Econoday for Jan–Apr 2026 and re-run (~20 min work + manual event list). |
| **Spread / slippage / commission model** | Works *against* the strategy. Will reduce EV for every config that is currently near breakeven. Required for an honest "go/no-go" call. | ~30 lines in the simulator. |
| **Tighter BoS detector** | Current `swing_lookback=2` produces noise. JJ's BoS requires the wick to be more extreme than *two adjacent candles on each side* and then price to *close* through it; we may be entering too early. | Sweep `swing_lookback` 2–4, add "close must be 0.25× ATR beyond the pivot" filter. |
| **Distance-from-fair-price filter** | We currently take any displacement/BoS regardless of how far price has stretched from fair. JJ implies the move must be "unfair" (large) not just any deviation. Adding a min-points-from-fair gate will cut low-edge trades. | Add `min_points_frac_of_atr` parameter and sweep. |
| **Session-open continuation (SOC)** | Optional first-5-min continuation trade. Spec says default off but JJ mentions it. | Enable and re-test. |
| **Contract sizing with real NQ multiplier** | Currently dollars-per-point is computed from risk_dollars / sl_pts (instrument-agnostic). NQ futures are $20/point, micro NQ $2/point; setting `point_value_per_dollar=$20` would make sizing match reality (but doesn't change pass rate since risk % is already enforced as a fraction of balance). | Trivial; does not change pass rate. |
| **Post-news big-miss threshold** | Currently 3× ATR routes to unexpected-new mode. Needs to be validated against actual CPI/NFP releases. | Tune against news events. |
| **More than 3 months of data** | 74 trading days × 3 session windows is a decent sample but JJ built his stats over 18 months. Will matter especially for NR (which fires ~1×/week at most). | Download a longer history (MNQ/NQ from the same repo goes back further at tick/daily; M1 only starts 2026-01-20). |
| **Discretion / fair-price adjustment** | JJ explicitly says discretion is needed to know when fair price has moved. A fully mechanical model will never match his 25% pass rate if that discretion is doing real work. The three-loss rule is our automation of this — it may be insufficient. | Hard to automate; this is the "art" part JJ says takes months. |

---

## Per-preset result on NQ (DC+BoS enabled, default risk, no news)

For reference, running the same settings across the 5 preset account types
on the same NQ file:

| Preset | RR | Risk | Win rate | Breakeven WR | Pass rate | Verdict |
|---|---:|---:|---:|---:|---:|---|
| eval_1to1 | 1.0 | 1.0% | 40.4% | 50.0% | 5% | NOT PROFITABLE |
| eval_1to1_5 | 1.5 | 0.75% | 28.9% | 40.0% | **0%** | NOT PROFITABLE |
| funded_consistency | 1.5 | 0.5% | 28.3% | 40.0% | 0% | N/A (funded) |
| funded_noconsistency | 4.0 | 0.5% | 17.8% | 20.0% | 0% | N/A (funded) |
| the5ers_2500 | 1.5 | 0.5% | 27.8% | 40.0% | 0% | NOT PROFITABLE |

---

## Honest conclusion

What this simulator actually shows right now is:

1. **The code works correctly** — the mechanics of fair-price tracking,
   session windows, three-loss kill switch, static RR sizing, multi-account
   layering, and prop-firm rule enforcement all run without errors across
   84k real NQ bars.
2. **The EURUSD test that showed +56% ROI was a false positive** — it was
   the wrong instrument, and the result does not carry over to NQ.
3. **On NQ (the right instrument) v1 is breakeven-at-best on DC, and
   clearly negative on BoS and DC+BoS.**
4. **JJ's claimed A+ setup (news reversions) is not yet tested** because we
   have no news calendar for the period. This is the single highest-value
   next step. NR setups are few per month but JJ claims they win "almost
   100%", so even 10 events with a 70% win rate at 1:1.5 could swing EV
   positive on their own.
5. **Until news-reversion results are in AND a cost model is added AND BoS
   is tightened, there is no basis to claim profitability** and therefore
   no basis to write an MQL5 EA for live/demo use. The spec's §11 fail-closed
   gate should remain locked.

---

## Recommended next actions (priority order)

1. **Build the news calendar CSV** for 2026-01-20 → 2026-04-15 (CPI, PPI,
   NFP, FOMC, retail sales, ISM, core PCE, GDP, Fed chair speeches). 10
   minutes of manual work from any economic calendar.
2. **Add spread/slippage model** — NQ typical spread is 0.25 pts (1 tick) in
   NY session, slippage ~0–0.25 pts on market orders. Deduct from every
   entry.
3. **Re-run the sweep** with NR enabled and costs on. If NR wins ≥65% at
   1:1.5 and the combined DC+NR+BoS pass rate crosses ~30% after costs, the
   strategy crosses the "proceed to tuning" threshold.
4. **Tighten BoS** — sweep `swing_lookback` in {2,3,4} and add a min-ATR
   break-size filter. If BoS win rate doesn't rise to at least 1 point
   above breakeven, drop it from the model (JJ uses BoS only on funded
   accounts for a reason).
5. **Add a min-distance-from-fair filter** (e.g. displacement must be
   ≥0.5× ATR(12) away from fair price) to suppress marginal DC trades.
6. **If still not profitable after steps 1–5**, be honest that the edge
   likely depends on (a) the multi-account layer that's hard to simulate
   without real fills, (b) trader discretion JJ uses to shift fair price,
   or (c) market conditions in 2023–2024 that don't persist in Q1 2026.
