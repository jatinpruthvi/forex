# The M5 exhaustion fade is a rollover spread artefact (2026-09-30)

The user named the brokers: **The5ers High Stakes** for the funded account and **Fusion Markets (Zero)** for individual trading. This round re-costs the M5 fade with their commissions and then looks at when the trades happen.
Code: `tools/broker_cost_lab.py` (`python tools/broker_cost_lab.py` and `... rollover`; 4 tests). Data: Dukascopy 10-year set (fingerprint `2133f59930b9`) and the repo's tracked FSB set.

## 1. Broker costs (public pages, 2026)

| | Commission (round turn, per standard lot) | Spread |
|---|---|---|
| The5ers High Stakes | **$4.00** on Forex and Gold | raw; average not published as a table |
| Fusion Markets Zero | **$4.50** on Forex and Metals | EURUSD ~0.02-0.11 pips, 8-pair basket ~0.36 pips, gold ~$0.12 |
| (repo model used so far) | $7.00 | 0.55 x a "standard" spread (EURUSD 0.55 pip) |

Also relevant for The5ers High Stakes: news trading is not allowed within 2 minutes of high-impact releases, at least 3 profitable days (>= 0.5% of the initial balance), 5% daily loss, 10% max drawdown, and swap-free accounts are available on request. Fusion Markets Classic (no commission, ~0.9 pip EURUSD) is costlier for this kind of trading.
I assumed typical raw spreads per pair (`TYPICAL_RAW` in the lab: EURUSD 0.1 pip ... GBPJPY 1.0, gold 1.5 pips) and scaled them x1 / x2 / x3, because signals fire in volatile moments. These spreads are my assumption, not published data.

## 2. Re-costed M5 fade (same signals, strict bound)

| Broker, spread multiple | 2016-22 (clean) net / PF / 90% lb / gates passed | 2022-26 (tuned) net / PF |
|---|---|---|
| The5ers, x1 | +0.095R / 1.10 / +0.020 / O1 O5 O6 O9 | +0.424R / 1.46 |
| The5ers, x2 (pre-declared primary) | +0.026R / 1.02 / -0.049 / O1 O9 | +0.360R / 1.37 |
| The5ers, x3 | -0.043R / 0.96 / -0.118 / O1 | +0.296R / 1.29 |
| Fusion Zero, x1 / x2 | +0.089R / +0.020R | +0.418R / +0.355R |

Cheaper execution helps, but on the clean window the fade still fails O2, O3, O4 and O7, and it is not positive at x3. Both-phase pass in 90 days stays at 17-25% (0.5% or 1% risk).
The clean window went from +0.012R (repo costs) to +0.095R at best. That is not enough. But the bigger finding is in section 3.

## 3. Where the profit comes from

The fade's signal bars cluster at one time of day. In the clean window, 823 of 4,150 signals (20%) start between 16:55 and 18:10 New York time, the daily **17:00 NY rollover**, when quoted spreads blow out for minutes (20:55 UTC in summer, 21:55 UTC in winter are the two biggest buckets). In the repo's own tracked data 511 of the 1,667 verifier-window signals sit on the single 17:00-17:05 NY bar.

| Data and window | All signals | Rollover window only | Everything else |
|---|---|---|---|
| Dukascopy 2016-22 (clean), repo costs | n=4150, net **+0.012R** | n=823, gross +0.811, net **+0.541R** | n=3327, gross +0.086, net **-0.118R** |
| Dukascopy 2022-26 | n=3283, **+0.348R** | n=1281, gross +1.276, net **+1.010R** | n=2002, gross +0.081, net **-0.076R** |
| Tracked FSB 2022-26 | n=3284, +0.348R | n=1274, net +1.005R | n=2010, net -0.069R |
| Tracked FSB 2024-26 (the repo verifier's window, repo rule) | n=1667, **+0.375R** | n=701, net **+1.033R** | n=966, net **-0.103R** |

With The5ers costs and typical spreads, everything outside the rollover window is **negative in both eras** (x1: -0.039R and -0.013R; x2: -0.103R and -0.060R).

Why this is an artefact and not an edge. At the rollover, dealers widen the bid/ask spread for a few minutes. On bid-price bars the widening looks like a violent down bar, and the price then snaps back as spreads normalise. The fade buys the "spike" at the bid-side bar open and is paid when the quote normalises. A real long order fills at the ask, which at that moment sits about a whole widened spread above that bid, so the modelled entry is better than any real fill by roughly the profit being harvested. The 5-pip stops and +10R targets make the phantom profit look huge (a 1R move is only a few pips, a normal rollover spread is 10-30 pips on retail feeds).
The same pattern appears in two independent data sources (Dukascopy, FSB) and in every window, which fits a structural quote effect and not noise. I have not seen tick quotes, so the widening itself is inferred from the time-of-day concentration, from the immediate reversal and from the fact that nothing else in the strategy has an edge. That is strong circumstantial evidence, not proof.
The The5ers 2-minute news rule is a second problem (about 25% of signal bars also sit on common US-release slots such as 12:30 and 13:30 UTC), which I have not quantified because there is no calendar data.

## 4. Consequences and corrections

- **The repo's documented fade results (`findings_phase2_speed.md`: +0.3985R, n=1684, "validated") are dominated by this artefact.** Removing the rollover window turns +0.375R into -0.103R on the repo's own verifier window.
- **Correction of my earlier statement** in `findings_best_strategy_oos.md` section 5, where the placebo showed "real gross information in the exhaustion trigger about +0.27R above random". That gross information is the rollover window. Outside it, gross is +0.08R, below any cost. The placebo was not evidence of a usable edge. The same applies to the "fade geometry" reading in `findings_edge_search.md` section 4.
- The cost-sensitivity results (`findings_edge_search.md` section 9: "would become a modest edge if costs were half") no longer support any optimism. They priced a phantom.
- I have not checked the champion's TRIAD and gold legs for rollover dependence. Their failure on 2016-22 (PF 0.82) does not depend on it.
- Verdict for the fade under The5ers and Fusion Markets costs: **NOT VALIDATED, and the apparent profit is a rollover quote artefact.**

## 5. Ledger

| # | Step | Outcome |
|---|---|---|
| 1 | Looked up the two brokers' commissions | The5ers $4, Fusion Zero $4.50 |
| 2 | Re-cost the fade at x1 / x2 / x3 spread | still fails on the clean window |
| 3 | Time-of-day split (an unplanned diagnostic after seeing the clustering in a histogram) | rollover window holds all of the profit |
| 4 | Checked the split on Dukascopy 2016-22, Dukascopy 2022-26, tracked FSB 2022-26 and 2024-26 | same pattern everywhere |
| 5 | Sandbox `/tmp` and the local git state were reset again; re-synced to the pushed commit | no file changes |

The rollover window (16:55-18:10 NY) was fixed from the histogram and from the known daily rollover time, not tuned on P&L. It is a diagnostic, so no trials were added and no gate was re-run on it.
Known unrelated baseline failure: `tests/test_source_contract.py::test_canonical_and_runtime_files_exist`.
