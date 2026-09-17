# Review — PR #9 "Optimize strategy risk limits" (merged 2026-09-15)

**Reviewer verdict: DO NOT DEPLOY. The strategy in this PR will not pass the challenge.
It fails on transaction costs alone, and the merge also broke 13 tools and 1 test module.**

Reviewed commit: `2713001` (merge of `optimize-strategy-risk-limits-5950591650535969703`)
Base commit: `003df25` (PR #8)
Files changed: 5 · +411 / −911

| File | Change |
|---|---|
| `tools/m1_holy_grail.py` | **new** — 156-line M1 backtester |
| `tools/aggressive_optimizer.py` | **rewritten** — 939 → 257 lines; the cost-aware M5 engine was deleted |
| `tools/findings_m1_discovery.md` | **new** — claims "Phase 1 in ~20 trading days" |
| `THE5ERS-2.5K-CHALLENGE-PLAN.md` | risk 2.00% → 0.50%, active module → M1 Momentum Reversion |
| `THE5ERS-CHALLENGE-STRATEGY-V2.md` | entry/stop/risk sections rewritten for M1 momentum fade |

Reproduction harness: [`validation/pr9_audit/`](validation/pr9_audit/) — `python3 validation/pr9_audit/run_all.py`

---

## 1. The published numbers do reproduce — the problem is what they assume

I rebuilt `tools/m1_holy_grail.py` as an exactly-equivalent trade-list engine and
confirmed it reproduces every published figure bit-for-bit, so nothing below is a
modelling artefact on my side:

| Config | Trades | WR | Max DD | Days to +10% | `findings_m1_discovery.md` | Match |
|---|---:|---:|---:|---:|---|:--:|
| T=1.0R, stop 1.5×ATR | 2976 | 51.7% | 15.29% | 19 | 2976 / 51.7% / 15.29% / 19d | ✅ |
| **T=1.5R, stop 1.5×ATR** (champion) | 2962 | 42.7% | 12.62% | 20 | 2962 / 42.7% / 12.62% / 20d | ✅ |
| T=1.0R, stop 2.0×ATR | 2963 | 52.1% | 12.11% | 27 | 2963 / 52.1% / 12.11% / 27d | ✅ |

**But the engine models no transaction costs at all.** P&L is hard-coded:

```python
pnl -= risk_pct * balance          # loss  = exactly -0.5%
pnl += target_r * risk_pct * balance   # win = exactly +target_r x 0.5%
```

There is no spread, no commission, no slippage, no lot sizing, and no 0.01 lot step.

---

## 2. FATAL — the stops are too tight to clear their own costs

Measured over all 9,460 raw EURUSD M1 triggers in the shipped test data:

| Metric | Value |
|---|---:|
| ATR(M1,14) median | 0.74 pips |
| **Stop distance — median** | **1.11 pips** |
| Stop distance — p5 / p25 / p75 / p95 | 0.31 / 0.67 / 1.88 / 3.62 pips |
| Stops under 1.0 pip | 44.1% |
| Stops under 2.0 pips | 77.8% |
| **Round-trip cost as % of 1R — median** | **68%** |
| Round-trip cost as % of 1R — p90 | 111% |
| Trades where cost ≥ 50% of 1R | 73.3% |
| Trades where cost ≥ 100% of 1R (guaranteed loss even if the target is hit) | 17.4% |

Cost model is the repo's own, from `tools/optimizer_v2.py`:
`SPREAD_STD["EURUSD"]=0.00010 × RAW_SCALE=0.55` → 0.55 pip round-trip, `COMM_RT=$7/lot`,
0.01 lot step, $12.50 risk.

### Break-even sweep (EURUSD, champion config, commission $0)

| Round-trip spread | Net P&L | $2,250 floor | Phase 1 |
|---:|---:|---|:--:|
| 0.00 pip | +$256.25 | no | **PASS** |
| 0.03 pip | +$267.97 | no | **PASS** |
| **0.05 pip** | **−$253.03** | **BUST 2024-11-15** | **NO** |
| 0.10 pip | −$258.58 | BUST 2024-11-05 | NO |
| 0.55 pip (realistic raw) | −$254.89 | BUST 2024-09-19 | NO |

**The strategy survives only below a ~0.05 pip round-trip spread with zero commission.
Real EURUSD is ~0.55 pip raw / ~1.0 pip standard — 11× to 20× past break-even.**

With the repo's canonical costs the champion loses **−1.0259R per trade, profit factor 0.26**.
It reaches the firm's $2,250 termination floor on **2024-09-18, seven calendar days in,
after 31 trades**, with 0 qualifying days.

### This is a known, previously-documented failure mode being reintroduced

`findings_live_friction_audit.md` §3 already concluded, for the M5 engine:

> "the 0.25×ATR stops are **2–4.5 pips**; round-trip cost is **$4–6.5 per trade ≈ 40–65%
> of the $10 risk unit**. The edge cannot clear its own microstructure fees."

PR #9's stops are **2–4× tighter** than the configuration that audit already ruled fatal.
The root cause is that the PR deleted the min-stop-distance gate from
`THE5ERS-CHALLENGE-STRATEGY-V2.md` §6 — the line `Reject if entry-to-stop distance is
outside 0.60-1.50 × ATR(M15,14)` was removed and nothing replaced it.

### Reinstating a min-stop filter destroys the signal rate

Cost as a fraction of 1R is `(spread_pips × $10 + $7) / (stop_pips × $10 + $7)`, so:

| Required cost ≤ | Minimum stop needed | Trades surviving that filter | Trades/day |
|---|---:|---:|---:|
| 20% of 1R | 5.5 pips | 104 / 2,962 (3.5%) | 0.18 |
| 10% of 1R | **11.8 pips** | **17 / 2,962 (0.6%)** | **0.03** |

At a stop wide enough for costs to stop dominating, the strategy fires about **once every
three weeks** instead of the 5×/day the plan now assumes. The fix is therefore structural,
not parametric — there is no M1 momentum-reversion configuration on this data that is both
cost-viable and fast enough to matter.

---

## 3. FATAL — the merged optimizer busts the account on day one

`tools/aggressive_optimizer.py` was rewritten to run **10 pairs through one shared `pnl`
pool**, while `THE5ERS-2.5K-CHALLENGE-PLAN.md` §2 now advertises "EURUSD / Max 5 trades
per day". The code and the doc disagree. Measured on the shipped M1 data:

| Metric (10-pair portfolio, **zero costs**) | Value |
|---|---:|
| Total trades over 2 years | 29,354 |
| **Max simultaneous open positions** | **9** → 4.5% aggregate risk |
| Trades per calendar day (median = max) | **50** |
| Max drawdown | **39.07%** |
| Balance first ≤ $2,250 (firm termination) | **2024-09-11 03:33 UTC — day one** |

Replaying the PR's full 24-config grid under its own semantics:

| | Count |
|---|---:|
| Configs breaching the $2,250 firm floor (zero costs) | **20 / 24** |
| Configs whose worst single day exceeds the 5% daily-loss boundary ($125) | **23 / 24** |
| Configs admitted by the PR's own leaderboard filter (`dd ≤ 9%`) | 1 / 24 |
| …of those, ones that are actually challenge-legal | **0 / 24** |

The single "admitted" config (T=1.0R, risk 0.2%, stop 2.0×ATR, thresh 2.0) has a worst
day of **−$160**, breaching the $125 daily-loss boundary. So `python tools/aggressive_optimizer.py`
produces either an empty leaderboard or an illegal one.

These directly violate `THE5ERS-2.5K-CHALLENGE-PLAN.md` §2:
*"Maximum one working pending entry or one open position account-wide — never simultaneous
positions"* and *"Maximum two completed sequential trades per day"*. The plan cites
The5ers' July 2026 prohibited-practices wording on bulk trading — 9 concurrent positions
and 50 trades/day is squarely in that risk zone.

---

## 4. "20 days" is the luckiest window in two years

The PR reports one run starting at the first bar of the dataset. Walk-forward over 120
rolling start dates, champion config, Phase 1 = +10% **and** ≥3 qualifying days:

| | Zero-cost (PR's assumption) | With real costs |
|---|---:|---:|
| Phase 1 passed | 93 / 120 = **77.5%** | 0 / 120 = **0.0%** |
| Busted the $2,250 floor | 27 / 120 = **22.5%** | 120 / 120 = **100%** |
| Days-to-pass — median | **29** | — |
| Days-to-pass — p90 / max | 90 / 166 | — |
| Qualifying days at pass — median / min | 9 / 4 | — |

Even in the frictionless fantasy the honest median is **29 days, not 20**, the p90 is 90
days, and **roughly one attempt in 4.5 loses the account**. The configuration was also
selected by sweeping the entire 2-year set and keeping the fastest — pure in-sample
selection with no held-out split.

---

## 5. Regression — the merge broke 13 tools and 1 test module

`tools/aggressive_optimizer.py` was the repo's shared constants/utilities module.
Deleting `LONDON_PAIRS`, `NY_PAIRS`, `SPECS`, `calc_lots`, `to_london_date`,
`COMMISSION_PER_LOT`, `VOLUME_MIN` etc. broke every downstream importer.

All 27 tools imported cleanly at base `003df25`. After the merge, **13 fail**:

```
tools/_validate_4yr.py            AttributeError: no attribute 'SPECS'
tools/bounded_grid_lab.py         AttributeError: no attribute 'LONDON_PAIRS'
tools/external_orb.py             AttributeError: no attribute 'LONDON_PAIRS'
tools/fast_track_lab.py           AttributeError: no attribute 'LONDON_PAIRS'
tools/fibonacci_martingale_lab.py AttributeError: no attribute 'LONDON_PAIRS'
tools/filter_training_lab.py      AttributeError: no attribute 'LONDON_PAIRS'
tools/m1_lab.py                   AttributeError: no attribute 'LONDON_PAIRS'
tools/order_selector.py           AttributeError: no attribute 'LONDON_PAIRS'
tools/per_pair_filter_lab.py      AttributeError: no attribute 'LONDON_PAIRS'
tools/smart_fibonacci_lab.py      AttributeError: no attribute 'LONDON_PAIRS'
tools/sr_pa_lab.py                AttributeError: no attribute 'LONDON_PAIRS'
tools/triad_honest.py             AttributeError: no attribute 'LONDON_PAIRS'
tools/winner_pyramid_lab.py       AttributeError: no attribute 'LONDON_PAIRS'
```

Test suite, base vs merged (run with `PYTHONPATH=<repo root>`):

| Test module | At `003df25` | At `2713001` |
|---|---|---|
| `tests/test_order_selector.py` | **OK (16 tests)** | **FAIL — import error via `tools/triad_honest.py`** |
| test_ablation_scaffold | OK (27) | OK (27) |
| test_bugfix_regressions | OK (24) | OK (24) |
| test_extended_validation | OK (23) | OK (23) |
| test_screen_ea_contract | OK (29) | OK (29) |
| test_source_contract | OK (39) | OK (39) |
| test_validation | OK (13) | OK (13) |

PR #9 added **zero tests** for the 413 lines of new/rewritten backtester it introduced.

---

## 6. The MQL5 EA was not updated — spec and implementation now contradict

`THE5ERS-CHALLENGE-STRATEGY-V2.md` is declared the canonical build spec, and the PR
rewrote its §5 entry sequence, §6 stop formula and §8 risk profiles for M1 momentum
reversion. But `MQL5/Experts/TRIAD_R_HS/TRIAD_R_HS.mq5` is untouched and still reads:

```mql5
#property description "TRIAD-R High Stakes: one-position M5 sweep/reclaim research EA"
input double InpSweepAtrMin = 0.05;   input int    InpReclaimBars = 3;
CopyRates(symbol, PERIOD_M5, ...)     iBarShift(symbol, PERIOD_M15, ...)
```

Worse, `tests/test_source_contract.py` still passes while now enforcing the **opposite**
of the canonical doc:

| Contract test assertion | Canonical doc after PR #9 |
|---|---|
| `assertLessEqual(max(risk_literals), 0.004)` — max risk 0.40% | 0.50% (§4, §8) |
| profiles `0.0040/1.50`, `0.0035/1.75`, `0.0030/2.00`, `0.0025/2.50` | `0.0050/1.00`, `0.0050/1.50`, `0.0030/1.50`, `0.0025/2.00` (§8) |
| `self.assertIn("count>=2", source)` — two-trade daily lock | "Max 5 trades per day" (§2 of the plan) |

The suite is green only because the contract tests read the `.mq5` and never cross-check
the doc sections the PR changed. That is a false pass.

---

## 7. Documentation defects introduced or left behind

**Direct self-contradictions in `THE5ERS-2.5K-CHALLENGE-PLAN.md` §2** — the PR changed the
"Active module" line without touching the rest of the same section:

- Line 45 now says *use M1 Momentum Reversion*; line 53 still lists **"M1/tick scalping"**
  under **"Disabled for the first challenge"**.
- Line 45 says *Max 5 trades per day*; lines 62–63 still say *"Maximum two completed
  sequential trades per day"* and *"Maximum one … open position account-wide"*.

**Stale numbers the PR did not update:**

| Location | Text | Problem |
|---|---|---|
| Plan §11 table | `0.15R/trade → ~167 / ~84 trades` | Table is still built for 25R / 12.5R. The PR's own new text says Phase 1 = 20R, Phase 2 = 10R → should be ~133 / ~67 |
| Plan §6 line 177 | *"At the $10 risk ceiling, a complete 1.5R winner is at most approximately $15"* | Risk ceiling is now $12.50 |
| V2 §7 line 156 | *"If **+1R** has not been confirmed within 45 minutes"* | Target is now +1.5R |
| V2 §7 line 165 | *"after a completed **M5** close beyond +1R"* | Strategy is now M1 |
| V2 §8 line 186 | *"a normal full-target outcome near **0.6%**"* | New profiles give 0.45–0.75% |
| V2 §8 table | *"A baseline (**Old M5**) | 0.50% | +1.00R"* | The old M5 baseline was 2.00% / +2.50R. Relabelling it destroys the comparison the row exists to make |
| `findings_aggressive_optimizer.md` | *"11 pairs **M5** OHLCV … 60 combinations … Max 2 trades per day"* | Stale — the tool that generates it was rewritten to M1/10 pairs/24 combos. Never regenerated |

**Terminology:** `passed_phase_1_days = (b.ts - first_trade_ts).days` is **calendar** days.
`findings_m1_discovery.md` says "20 calendar days" but the plan says "~20 **trading** days
(~3-4 weeks)". 20 calendar days from 2024-09-11 is ~14 trading days. The two documents
cannot both be right.

---

## 8. Code-quality defects in `tools/m1_holy_grail.py`

| # | Issue | Impact |
|---|---|---|
| 1 | No cost model, no lot sizing, no 0.01 lot step | Fatal — see §2 |
| 2 | §6's min-stop-distance rejection deleted | Fatal — root cause of §2 |
| 3 | **R is mis-stated.** Stop is placed beyond the extreme bar's *wick* but entry is the bar's *close*, so the true R = `(close − low) + 1.5×ATR`, not `1.5×ATR`. The docs advertise "Stop 1.5 ATR" | Real risk per trade is larger than documented; the +1.5R target is measured off a different base than the stop |
| 4 | `atr()` averages `high − low`, not true range | Understates ATR across the 100 weekend gaps in the data |
| 5 | No max-hold / time stop, no session hard stop, no flat-before-rollover | Positions are held across weekends and news; V2 §7 requires all three |
| 6 | Exits booked at the exact stop/target price | 2.9% of losers open beyond the stop (extra ~0.09 pip median = ~8% of 1R); entry filled at trigger close though the next open differs by 0.10 pip median, 7.60 pip max |
| 7 | No daily-loss limit, no DD throttle, no news blackout, no spread filter | Plan §3 "Shared hard gates" — all mandatory, all absent |
| 8 | `balance` is never updated; `risk_pct * balance` is constant | Risk is fixed to the *initial* balance forever — not the documented "% of current balance" |
| 9 | Day bucketing on **UTC** calendar date | The5ers/Eightcap server is UTC+3 (`tick_signal_builder.SERVER_UTC_OFFSET`). Changes the daily cap boundary and the qualifying-day snapshot |
| 10 | Qualifying days are never counted | Phase 1 needs ≥3 days at ≥$12.50. (It happens to reach 6–7 zero-cost, but the tool cannot tell you) |
| 11 | `test_holy_grail_portfolio` shares one `pnl` across all pairs with per-pair risk | Silent 9-way risk aggregation — see §3 |
| 12 | `main()` re-parses all 10 CSVs inside each of 24 grid configs | ~9 min of pure CSV re-parsing plus a 7.4M-element sort per config |
| 13 | Dead placeholder left in the code path | `tools/m1_holy_grail.py` has none, but the sibling copy in `aggressive_optimizer.py` duplicates the whole 130-line engine instead of importing it — two copies to keep in sync |

---

## 9. Scorecard against the repo's own go/no-go gate

`THE5ERS-2.5K-CHALLENGE-PLAN.md` §12: *"Do not call the challenge plan ready until the
exact challenge profile passes"* all 12 items. The PR's champion:

| # | Gate | Actual | Verdict |
|---:|---|---|:--:|
| 1 | ≥300 **out-of-sample** trades | 0 — config chosen by sweeping the full 2y set | **FAIL** |
| 2 | Net expectancy ≥ 0.20R after spread + $4/lot | +0.0685R zero-cost → **−1.0259R** with costs | **FAIL** |
| 3 | Net profit factor ≥ 1.30 | 1.12 zero-cost → **0.26** with costs | **FAIL** |
| 4 | Profitable at spread ×1.5, slippage ×2 | busts at 0.05 pip spread with $0 commission | **FAIL** |
| 5 | 0.01-lot rounding, MT5 cash P&L, server-day grouping, published profitable-day formula | none implemented | **FAIL** |
| 6 | Historical news blackout + server-time/DST | none implemented | **FAIL** |
| 7 | ≥10,000 day/week block-bootstrap sims | none run | **FAIL** |
| 8 | Phase 1 then fresh Phase 2, joint pass probability | Phase 2 never simulated | **FAIL** |
| 9 | ≥70% Phase 1 pass probability before the −5% stop | 0% with costs; 77.5% zero-cost with 22.5% floor busts | **FAIL** |
| 10 | 95th-percentile max DD < 5% | 12.62% single-pair; 39.07% portfolio | **FAIL** |
| 11 | Compare 0.50%/+1.0R vs 0.25%/+1.5R with actual lot rounding | no lot rounding anywhere | **FAIL** |
| 12 | 30–50 forward-demo trades, zero implementation errors | none recorded | **FAIL** |

**Gates passed: 0 / 12.**

---

## 10. Recommendation

1. **Revert the strategy decision.** Restore the pre-PR `tools/aggressive_optimizer.py`
   (`git show 003df25:tools/aggressive_optimizer.py`) to un-break the 13 tools and
   `tests/test_order_selector.py`. Keep `tools/m1_holy_grail.py` only as a research
   artefact, clearly marked as cost-blind.
2. **Do not fund this.** The champion config busts the $2,250 floor in 7 calendar days
   under the repo's own cost constants. Break-even requires a sub-0.05-pip round-trip
   spread that does not exist on EURUSD.
3. **If M1 momentum reversion is worth pursuing**, the fix is structural, not parametric.
   Reinstating a min-stop distance wide enough for costs to stop dominating (≥ 11.8 pips
   for cost ≤ 10% of 1R) leaves **17 trades in 2 years** — roughly one every three weeks,
   versus the 5/day the plan now assumes. On this dataset there is no M1 configuration
   that is both cost-viable and fast. Re-run the §12 gate end-to-end before touching the
   plan docs again.
4. **Correct the docs.** Either the M1 module or the "M1/tick scalping disabled",
   "max two trades per day" and "one position account-wide" rules must go. Regenerate
   `findings_aggressive_optimizer.md`. Fix the §11 trade-count table and the stale
   +1R/M5/0.6%/$10 references listed in §7.
5. **Close the spec↔code gap.** Either implement the M1 strategy in `TRIAD_R_HS.mq5` and
   update `tests/test_source_contract.py` (max-risk 0.40% → 0.50%, two-trade lock →
   whatever is decided), or leave the canonical doc on the M5 sweep/reclaim design the EA
   actually implements. Right now the contract tests pass while asserting the opposite of
   the canonical spec.
6. **Add a cost-awareness guard test** so a future backtester that books P&L as a flat
   `±risk_pct` with no spread/commission term cannot be merged as "validated" again.
