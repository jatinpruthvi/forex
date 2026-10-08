# docs_v1 strategy extraction and validation (2026-09-29)

Loop: `.agents/skills/loop-engineering` with profile `projects/forex-strategy-validation.md`.
Baseline commit: `17b0ba5`. Data: tracked 4-year M5 set, 11 pairs, preflight PASS (set fingerprint `7d2636bc01e9`).
Baseline tests: 200 passed, 1 known failure (`test_canonical_and_runtime_files_exist`, doc moved to `docs/prop_firm/`).

> **Status of this file:** Sections 1-4 are the **pre-registration**. They were written and committed
> **before any simulator code existed or ran**. Sections 5+ (results) are appended afterwards.
> Nothing in sections 1-4 may be edited once results exist; supersede by appending instead.

---

## 1. Goal

Read every strategy in `docs_v1/`, extract what can be tested on 4 years of M5 OHLC for 11 pairs, test it
honestly, and report the best strategy that survives - or report that none does. "Best" means best on
held-out data under the pessimistic bound with costs, not best in-sample.

## 2. What `docs_v1` contains (extraction)

28 markdown files, ~390 KB, no code except one MQL5 EA listing (StudyArena round 1, contestant A).
`master-combination-strategy.md` is the self-declared definitive manual; every performance figure in the
corpus is stated as UNTESTED or is an unrun projection (its own Evidence Ledger says so).

| ID | Engine (source) | Testable on M5 OHLC? | How it is tested here |
|---|---|---|---|
| E1 | SMC core: H4 bias -> sweep of swing -> M15 CHoCH -> OB/FVG zone, limit at 50% (round1-A EA source; strategy-recommendation.md) | Yes | Signals on M15, fills and exits scanned on M5 |
| E2 | Asian-range liquidity raid, 07:00-10:00 (max-roi, strategy-recommendation.md) | Yes | Same machinery as E1 with the Asian H/L as the swept level. The repo already tested a tuned M5 variant (TRIAD); this is the docs' M15-CHoCH form |
| E3 | Imbalance / FVG re-engagement: impulse > 2.0 ATR14, 3-candle FVG, limit at 50% (AAM Engine B) | Yes, **without** the tick-volume > 1.8x gate (volume is 0 before 2024-01-24) | Volume gate tested as an ablation on 2024+ only |
| E4 | Dispersion rank book: 8 majors, long strongest 2 / short weakest 2, hold 1-5 days, exit on rank flip (max-roi Multiplier 3) | Partly. **60-day carry needs swap data we do not have -> dropped**, momentum only | Currency strength solved from the 10 available pairs; trades limited to the pairs we have |
| E5 | Cross-currency relative momentum (AAM Engine C): 24h z-score rank, 24h hold | Yes | Same rank engine, 24h horizon |
| X1 | Exit ladder: 1.0R stop; 25% at 1.5R (SL -> +0.3R), 25% at 3R (SL -> +1.0R), 25% at first opposing pool, 25% runner | Yes | Position manager on M5, pessimistic within-bar ordering |
| X2 | Round-1 EA exit: RR 3, 50% at 1.5R -> BE, ATR x2 trail | Yes | Comparator to X1 |
| F1 | DXY SMT divergence gate (non-confirmation) | Partly. No DXY feed -> **synthetic DXY** from EURUSD/USDJPY/GBPUSD/USDCAD/USDCHF (no SEK), USD pairs only | One filter trial |
| F2 | Regime router (ATR + ADX) / daily HMM | Partly | Simple ATR-ratio + ADX router, one filter trial. HMM not implemented (no evidence a trial is worth its budget) |
| F3 | Dead-money exit (age > 1.5x median and < +0.5R) | Yes | Exit option |

**Not testable here, stated so nobody reads silence as a pass:** tick-volume confirmation before 2024,
swap/carry, broker DXY/USOIL feeds, spread-at-fill, slippage, ML meta-labeling, procurement/prop-firm
economics, multi-account factory, payout mechanics. These are business or live-data claims.

**Doc claims to test** (from `strategy-recommendation.md`, `master-combination-strategy.md`, MFP):
C1 realistic expectancy 0.60R at 40% win rate; C2 each engine E > 0.25R out of sample;
C3 pairwise engine monthly-return correlation < 0.5; C4 round-trip cost <= 5% of R with stops >= 25 pips;
C5 "gold on M15 is a cost leak"; C6 the 1.0R stop beats 0.7R (not re-tested - docs rejected it).

## 3. Fixed rules for every run (R1-R12 from the profile, made concrete)

- **Data:** tracked 4-year set `validation/HistoryData/*-m5-2022-09-11_2026-09-11.csv`. Never modified.
- **Windows:** TRAIN 2022-09-11 -> 2024-09-11. TEST 2024-09-11 -> 2026-09-11.
  FORWARD 2026-09-13 -> 2026-09-29 from the CI snapshot, run separately (never spliced), smoke test only.
- **No look-ahead:** M15/H4/D1 bars from M5 buckets, only completed higher-timeframe bars are visible; fractals
  need 2 later bars; entries are limit orders placed after the signal bar closes and must be **re-touched**.
- **Timebase:** session windows in `Europe/London` wall clock (DST-aware). Killzones 07:00-10:00 and 13:00-16:00.
  Asian range 00:00-06:00 London. The docs say "server time" without an offset; this is my declared assumption.
- **Costs:** raw account, 55% of standard spread + $7/lot round turn, inside every trade
  (`validation/speed_lab/engine.py` model). Zero-cost numbers are diagnostics only.
- **Ambiguity:** same-bar stop/target ordering reported at three bounds (pessimistic, coin, optimistic). **Pessimistic is the gate.**
- **Account configs (R9):** **C-prop** = $2,500, 0.50% risk, max 4 concurrent, 1 per symbol, halt at -2.2% day (docs),
  equity floor $2,250, firm daily limit 5%. **C-slot1** = same but one account-wide slot (repo prop rule), reported as sensitivity.
  Never compare rows across configs.
- **Pairs:** all 11 as the base universe. XAUUSD and JPY crosses are excluded by the docs' unified parameter sheet
  for E1; they are reported as an ablation so the docs' exclusion is tested rather than assumed.

## 4. Acceptance criteria, gates and budget (FIXED - do not loosen)

### Trial budget
- **N_max = 60** configurations evaluated on TRAIN in total, counted in the ledger.
- Stage A (docs-as-written, no tuning): E1-X1, E1-X2, E2-X1, E3-X1, E4-mom20, E5-z24 = **6 configs**.
- Stage B (TRAIN-only tuning, at most 44 configs): dimensions allowed and nothing else - stop buffer {0.25, 0.5} ATR,
  entry {50% zone, zone front edge}, exit {X1, X2, single RR 2/3}, H4 bias {on, off}, filters {none, F1, F2},
  pair set {docs 5-8, all 11}, dead-money {on, off}.
- Stage C (combination of survivors): at most 6 configs.
- Extending N_max after seeing TEST needs the user's approval.

### Selection rule (fixed now)
A config is a **candidate** only if on TRAIN it has >= 120 trades, pessimistic net PF >= 1.15, pessimistic net expectancy > 0,
and is positive in both TRAIN halves (2022-09..2023-09, 2023-09..2024-09). At most **3 candidates** get a TEST look, one look each.
Candidates are ranked **by TRAIN score only** (pessimistic net expectancy x sqrt(trades)). TEST never influences which candidate is chosen.
An engine with no candidate is **NOT VALIDATED (fails on TRAIN)** and its TEST window is never opened.

### Gates on TEST (all must pass for VALIDATED; pessimistic bound, costs in)
| # | Gate |
|---|---|
| T1 | >= 150 trades. Fewer -> INCONCLUSIVE (cannot identify the edge) |
| T2 | Net expectancy >= +0.10R per trade AND day-block bootstrap (10,000 resamples) 90% lower bound > 0 |
| T3 | Profit factor >= 1.20 |
| T4 | Still net positive with spreads x1.5 |
| T5 | >= 3 of the 4 TEST half-years net positive |
| T6 | C-prop at 0.50% risk: no floor breach, no day above the 5% firm limit, max drawdown <= 8% |
| T7 | Not one pair: top pair <= 50% of net R, and expectancy stays > 0 with the top pair removed |
| T8 | No unexplained suspicion trigger (R10): DD < 1%, PF > 3, sign flip between bounds, profit from never-retouched fills |
| T9 | Coin-flip bound expectancy >= pessimistic (sanity) and > 0; result reported at all three bounds |

FORWARD window: reported only. Fewer than ~40 trades, so it cannot gate anything.

### Verdict vocabulary
VALIDATED (on history) | NOT VALIDATED | INCONCLUSIVE. `DONE + NOT VALIDATED` is an acceptable outcome; parameters will not be iterated to change it.

### Human-judged items
Whether these gates are the right ones for the user's goal (I chose them; the user did not specify gates). Flagged in the report.

### Deliverables
`tools/docs_v1_lab.py` (engine + runner), `tests/test_docs_v1_lab.py` (regression tests for the engine),
this findings file (results and ledger appended). If a candidate is VALIDATED: a frozen spec plus an independent
stdlib re-run of its trades.

---

## 4a. Amendment 1 (2026-09-29) - written BEFORE any TRAIN performance number was viewed

**Trigger (geometry only, no P&L seen):** while smoke-testing the E1 detector on EURUSD TRAIN (2022-09-11 -> 2024-09-11):
1,496 raw setups, 1,404 with a placeable limit; **median stop 4.9 pips, 90th percentile 8.9 pips, only 0.1% >= 25 pips**;
median M15 ATR(14) = 5.7 pips. The docs' "stop distance >= 25 pips effective on M15" (unified parameter sheet) therefore contradicts
the docs' own M15 order-block entries. Run as written, E1 places almost no orders; run with the natural stop, round-trip cost is a
large share of R (checked in the results section, claim C4).

**Consequence:** Stage A keeps the docs-as-written configs (25-pip floor on) and reports what they do. Two dimensions are ADDED to
the Stage B menu so the docs' intent (stops wide enough that cost <= 5% of R) can be tested at all:

- `sig_tf` in {M15, H1} - signal timeframe (H4 bias stays H4)
- `min_stop_pips` in {25, 0}

Everything else in section 4 is unchanged: N_max = 60 in total, candidate rule, 3 candidates, one TEST look each, all gates T1-T9.
Stage B is NOT a full factorial; the exact config list is fixed in the ledger before it is run.

---

## 4b. Amendment 2 (2026-09-29) - implementation decisions, written BEFORE the first Stage A run

The lab (`tools/docs_v1_lab.py`) and its tests (`tests/test_docs_v1_lab.py`, all passing) exist. No Stage A/B config has been run
through the runner yet. Before that, four things learned while testing the simulator are pinned here. **One of them corrects the
pre-registration text** (item 2); none of them can be tuned against results later.

1. **Stage B menu clarification (a restriction, not an extension).** The section-4 menu lists exits {X1, X2, RR2, RR3}, bias, stop buffer, entry,
   filters, pair set, dead-money (+ `sig_tf`, `min_stop_pips` from Amendment 1). None of these applies to the rank engines E4/E5, so
   **E4/E5 get Stage A only** (their lookback, K, hold and stop are not tuned). Because the menu has no dimension for it, the E1-only exit
   ladders "E2 as written" / "E3 as written" (X_E2, X_E3, present as code) are **not used**; E2 and E3 use X1 in Stage A exactly as section 4 says.
2. **The pessimistic / optimistic labels are two tie-break conventions, not nested bounds.** Testing showed a real trade where the
   "optimistic" convention (bank 1.5R on the fill bar, then the +0.3R ratchet stops the rest) ends *below* the "pessimistic" one (no target on
   the fill bar, runs on to 3.5R). A ladder that banks and ratchets is not monotone in the tie-break. So the **reported pessimistic result is the per-trade
   minimum of the two conventions and the optimistic result is the per-trade maximum**. It is a bound over two conventions, not over every intrabar path.
   The coin bound is the midpoint of the two (the exact expectation for a fair coin on a single ambiguity, approximate otherwise). The trade
   *set* and timing come from the pessimistic-convention run. Gate T9 is evaluated with these definitions.
3. **Simplifications that make the filters weaker than the docs' wording (disclosed, fixed):** F2 is the ATR-ratio shock skip only (signal-TF ATR(14) /
   its own 20-day mean > 1.8 -> skip); **no ADX**, no HMM. F3 dead-money threshold = 1.5 x the median hold (M5 bars) of the dead-money-free twin's
   TRAIN trades (the docs say "median time to TP1"), applied when age > threshold and the leg is below +0.5R; the threshold is measured on TRAIN and reused on TEST.
   F1 uses the closes-based synthetic DXY (M15 clock, 24-bar extreme). The account simulation marks realised balance only (open floating loss is not marked).
   Rank books are flat over the weekend: no entries on the Friday decision, exit at the Friday 17:00 New York close.
4. **Test-window lock.** `run --window test` refuses to run unless `DOCS_V1_TEST_OK=1`, the config is a TRAIN candidate, and the total number of
   TEST looks (persisted in `docs/research/findings/docs_v1_test_looks.json`) stays at most 3, one per config.

### Ledger (all configs fixed here; N counts every config evaluated on TRAIN)

Before this ledger, four smoke runs on TRAIN (EURUSD only, geometry/plumbing check) showed some performance numbers: E1 M15 natural stop
(= B01 on one pair), E1 H1 natural stop (= B03 on one pair), E4 default (= A5), E5 default (= A6). They are not extra trials (each config is re-run in full
below and counted once) but they were partly seen before being registered, and that is stated here.

Stage A = 6, Stage B = 32, so far **38 of N_max = 60**. Stage C (combinations of survivors) <= 6 more, leaving >= 16 unspent.

| Config | Engine | Definition (unlisted fields are `Cfg` defaults: risk 0.5%, London killzones 07-10 & 13-16 (E2: 07-10), docs pair sheet EURUSD/GBPUSD/USDJPY/AUDUSD/USDCAD unless `pairs=11`) |
|---|---|---|
| A1_E1_X1 | E1 | tf=15 exit=X1 entry=dual min_stop=25 bias=on buf=0.25 pairs=5 F1=False F2=False dead=False |
| A2_E1_X2 | E1 | tf=15 exit=X2 entry=mid min_stop=25 bias=on buf=0.25 pairs=5 F1=False F2=False dead=False |
| A3_E2_X1 | E2 | tf=15 exit=X1 entry=dual min_stop=25 bias=on buf=0.25 pairs=5 F1=False F2=False dead=False |
| A4_E3_X1 | E3 | tf=15 exit=X1 entry=mid min_stop=25 bias=on buf=0.25 pairs=5 F1=False F2=False dead=False |
| A5_E4_mom20 | E4 | lookback=20 z24=False K=4 hold=5d flip_exit=True stop=2.0xATR(D1) |
| A6_E5_z24 | E5 | lookback=20 z24=True K=4 hold=1d flip_exit=False stop=2.0xATR(D1) |
| B01_E1_m15_X1 | E1 | tf=15 exit=X1 entry=dual min_stop=0 bias=on buf=0.25 pairs=5 F1=False F2=False dead=False |
| B02_E1_m15_X2mid | E1 | tf=15 exit=X2 entry=mid min_stop=0 bias=on buf=0.25 pairs=5 F1=False F2=False dead=False |
| B03_E1_h1_X1 | E1 | tf=60 exit=X1 entry=dual min_stop=0 bias=on buf=0.25 pairs=5 F1=False F2=False dead=False |
| B04_E1_h1_X2mid | E1 | tf=60 exit=X2 entry=mid min_stop=0 bias=on buf=0.25 pairs=5 F1=False F2=False dead=False |
| B05_E1_h1_RR2mid | E1 | tf=60 exit=RR2 entry=mid min_stop=0 bias=on buf=0.25 pairs=5 F1=False F2=False dead=False |
| B06_E1_h1_RR3mid | E1 | tf=60 exit=RR3 entry=mid min_stop=0 bias=on buf=0.25 pairs=5 F1=False F2=False dead=False |
| B07_E1_h1_X1_min25 | E1 | tf=60 exit=X1 entry=dual min_stop=25 bias=on buf=0.25 pairs=5 F1=False F2=False dead=False |
| B08_E1_h1_X1_front | E1 | tf=60 exit=X1 entry=front min_stop=0 bias=on buf=0.25 pairs=5 F1=False F2=False dead=False |
| B09_E1_h1_X1_biasoff | E1 | tf=60 exit=X1 entry=dual min_stop=0 bias=off buf=0.25 pairs=5 F1=False F2=False dead=False |
| B10_E1_h1_X1_buf05 | E1 | tf=60 exit=X1 entry=dual min_stop=0 bias=on buf=0.5 pairs=5 F1=False F2=False dead=False |
| B11_E1_h1_X1_all11 | E1 | tf=60 exit=X1 entry=dual min_stop=0 bias=on buf=0.25 pairs=11 F1=False F2=False dead=False |
| B12_E1_h1_X1_F1 | E1 | tf=60 exit=X1 entry=dual min_stop=0 bias=on buf=0.25 pairs=5 F1=True F2=False dead=False |
| B13_E1_h1_X1_F2 | E1 | tf=60 exit=X1 entry=dual min_stop=0 bias=on buf=0.25 pairs=5 F1=False F2=True dead=False |
| B14_E1_h1_X1_dead | E1 | tf=60 exit=X1 entry=dual min_stop=0 bias=on buf=0.25 pairs=5 F1=False F2=False dead=True |
| B15_E2_m15_X1 | E2 | tf=15 exit=X1 entry=dual min_stop=0 bias=on buf=0.25 pairs=5 F1=False F2=False dead=False |
| B16_E2_m15_X2mid | E2 | tf=15 exit=X2 entry=mid min_stop=0 bias=on buf=0.25 pairs=5 F1=False F2=False dead=False |
| B17_E2_m15_RR2mid | E2 | tf=15 exit=RR2 entry=mid min_stop=0 bias=on buf=0.25 pairs=5 F1=False F2=False dead=False |
| B18_E2_m15_X1_min25 | E2 | tf=15 exit=X1 entry=dual min_stop=25 bias=on buf=0.25 pairs=5 F1=False F2=False dead=False |
| B19_E2_m15_X1_buf05 | E2 | tf=15 exit=X1 entry=dual min_stop=0 bias=on buf=0.5 pairs=5 F1=False F2=False dead=False |
| B20_E2_m15_X1_all11 | E2 | tf=15 exit=X1 entry=dual min_stop=0 bias=on buf=0.25 pairs=11 F1=False F2=False dead=False |
| B21_E2_m15_X1_F1 | E2 | tf=15 exit=X1 entry=dual min_stop=0 bias=on buf=0.25 pairs=5 F1=True F2=False dead=False |
| B22_E2_h1_X1 | E2 | tf=60 exit=X1 entry=dual min_stop=0 bias=on buf=0.25 pairs=5 F1=False F2=False dead=False |
| B23_E2_m15_X1_front | E2 | tf=15 exit=X1 entry=front min_stop=0 bias=on buf=0.25 pairs=5 F1=False F2=False dead=False |
| B24_E3_m15_X1 | E3 | tf=15 exit=X1 entry=mid min_stop=0 bias=on buf=0.25 pairs=5 F1=False F2=False dead=False |
| B25_E3_h1_X1 | E3 | tf=60 exit=X1 entry=mid min_stop=0 bias=on buf=0.25 pairs=5 F1=False F2=False dead=False |
| B26_E3_m15_X2 | E3 | tf=15 exit=X2 entry=mid min_stop=0 bias=on buf=0.25 pairs=5 F1=False F2=False dead=False |
| B27_E3_m15_RR2 | E3 | tf=15 exit=RR2 entry=mid min_stop=0 bias=on buf=0.25 pairs=5 F1=False F2=False dead=False |
| B28_E3_m15_X1_biasoff | E3 | tf=15 exit=X1 entry=mid min_stop=0 bias=off buf=0.25 pairs=5 F1=False F2=False dead=False |
| B29_E3_m15_X1_all11 | E3 | tf=15 exit=X1 entry=mid min_stop=0 bias=on buf=0.25 pairs=11 F1=False F2=False dead=False |
| B30_E3_m15_X1_F2 | E3 | tf=15 exit=X1 entry=mid min_stop=0 bias=on buf=0.25 pairs=5 F1=False F2=True dead=False |
| B31_E3_m15_X1_min25 | E3 | tf=15 exit=X1 entry=mid min_stop=25 bias=on buf=0.25 pairs=5 F1=False F2=False dead=False |
| B32_E3_m15_X1_front | E3 | tf=15 exit=X1 entry=front min_stop=0 bias=on buf=0.25 pairs=5 F1=False F2=False dead=False |

---

## 5. Results (2026-09-29) - appended after the runs; sections 1-4b unchanged

**Verdict: NOT VALIDATED for every `docs_v1` engine (E1, E2, E3, E4, E5). No config became a candidate on TRAIN, so the TEST window was never opened
(0 TEST looks; `docs_v1_test_looks.json` was never written). Stage C had no survivors to combine and was not run. Trials used: 38 of N_max = 60.**
Nothing in this report supports the docs' projected 52-58% win rate, PF 2.1-2.45 or 24-35 R/month.

All numbers below are TRAIN (2022-09-11 -> 2024-09-11), net of cost, pessimistic bound (per-trade minimum of the two tie-break conventions, see 4b.2),
C-prop sizing not applied to these statistics (R units per trade). Full table also in `docs_v1_train_results.csv`.

### 5.1 Stage A and B on TRAIN (all 38 configs)

| Config | n | WR | net exp (pess) R | PF | gross exp R | cost R | median stop pips | net exp (opt) R | net @1.5x spread | halves (pess) | candidate |
|---|---|---|---|---|---|---|---|---|---|---|---|
| A1_E1_X1 | 20 | 60% | +0.274 | 1.85 | +0.303 | 0.029 | 49.5 | +0.274 | +0.267 | +0.23, +0.70 | no |
| A2_E1_X2 | 12 | 58% | +0.487 | 2.12 | +0.531 | 0.044 | 32.4 | +0.487 | +0.476 | +0.49, n/a | no |
| A3_E2_X1 | 0 | - | - | - | - | - | - | - | - | - | no (no orders placed) |
| A4_E3_X1 | 67 | 36% | -0.174 | 0.74 | -0.127 | 0.047 | 31.3 | -0.150 | -0.185 | -0.49, +0.29 | no |
| A5_E4_mom20 | 432 | 50% | -0.007 | 0.97 | +0.002 | 0.009 | 181.5 | -0.007 | -0.009 | +0.02, -0.04 | no |
| A6_E5_z24 | 1468 | 49% | -0.006 | 0.95 | +0.004 | 0.010 | 153.4 | -0.006 | -0.008 | -0.02, +0.00 | no |
| B01_E1_m15_X1 | 1110 | 35% | -0.346 | 0.50 | -0.163 | 0.183 | 7.6 | -0.135 | -0.392 | -0.31, -0.38 | no |
| B02_E1_m15_X2mid | 968 | 33% | -0.477 | 0.44 | -0.210 | 0.267 | 5.4 | -0.031 | -0.544 | -0.42, -0.53 | no |
| B03_E1_h1_X1 | 282 | 32% | -0.334 | 0.51 | -0.222 | 0.112 | 12.6 | -0.170 | -0.362 | -0.22, -0.44 | no |
| B04_E1_h1_X2mid | 246 | 33% | -0.419 | 0.47 | -0.258 | 0.162 | 8.9 | -0.109 | -0.460 | -0.36, -0.48 | no |
| B05_E1_h1_RR2mid | 246 | 26% | -0.399 | 0.54 | -0.237 | 0.162 | 8.9 | -0.143 | -0.440 | -0.39, -0.41 | no |
| B06_E1_h1_RR3mid | 244 | 20% | -0.364 | 0.61 | -0.202 | 0.162 | 8.8 | -0.151 | -0.406 | -0.37, -0.36 | no |
| B07_E1_h1_X1_min25 | 18 | 28% | -0.235 | 0.62 | -0.201 | 0.035 | 40.5 | -0.192 | -0.244 | -0.22, -0.37 | no |
| B08_E1_h1_X1_front | 263 | 32% | -0.292 | 0.62 | -0.187 | 0.104 | 14.7 | -0.174 | -0.318 | -0.22, -0.37 | no |
| B09_E1_h1_X1_biasoff | 964 | 37% | -0.214 | 0.65 | -0.102 | 0.112 | 12.3 | -0.097 | -0.242 | -0.22, -0.21 | no |
| B10_E1_h1_X1_buf05 | 278 | 33% | -0.246 | 0.63 | -0.156 | 0.091 | 15.4 | -0.141 | -0.269 | -0.16, -0.33 | no |
| B11_E1_h1_X1_all11 | 654 | 35% | -0.289 | 0.55 | -0.173 | 0.116 | 14.1 | -0.140 | -0.320 | -0.24, -0.34 | no |
| B12_E1_h1_X1_F1 | 260 | 32% | -0.332 | 0.51 | -0.221 | 0.111 | 12.6 | -0.169 | -0.360 | -0.25, -0.41 | no |
| B13_E1_h1_X1_F2 | 282 | 32% | -0.334 | 0.51 | -0.222 | 0.112 | 12.6 | -0.170 | -0.362 | -0.22, -0.44 | no |
| B14_E1_h1_X1_dead | 286 | 36% | -0.321 | 0.47 | -0.210 | 0.111 | 12.6 | -0.157 | -0.349 | -0.24, -0.40 | no |
| B15_E2_m15_X1 | 444 | 40% | -0.232 | 0.63 | -0.070 | 0.162 | 7.9 | -0.146 | -0.272 | -0.18, -0.28 | no |
| B16_E2_m15_X2mid | 321 | 36% | -0.401 | 0.52 | -0.148 | 0.253 | 5.3 | -0.210 | -0.463 | -0.25, -0.55 | no |
| B17_E2_m15_RR2mid | 325 | 31% | -0.352 | 0.61 | -0.100 | 0.252 | 5.3 | -0.287 | -0.414 | -0.24, -0.47 | no |
| B18_E2_m15_X1_min25 | 0 | - | - | - | - | - | - | - | - | - | no (no orders placed) |
| B19_E2_m15_X1_buf05 | 438 | 39% | -0.224 | 0.63 | -0.090 | 0.135 | 9.5 | -0.169 | -0.258 | -0.18, -0.27 | no |
| B20_E2_m15_X1_all11 | 985 | 39% | -0.241 | 0.61 | -0.069 | 0.173 | 8.0 | -0.146 | -0.286 | -0.21, -0.27 | no |
| B21_E2_m15_X1_F1 | 417 | 39% | -0.265 | 0.59 | -0.102 | 0.163 | 7.9 | -0.172 | -0.306 | -0.20, -0.34 | no |
| B22_E2_h1_X1 | 60 | 47% | +0.007 | 1.01 | +0.112 | 0.106 | 12.8 | +0.064 | -0.020 | +0.05, -0.04 | no |
| B23_E2_m15_X1_front | 415 | 39% | -0.204 | 0.72 | -0.047 | 0.157 | 9.4 | -0.134 | -0.243 | -0.19, -0.22 | no |
| B24_E3_m15_X1 | 641 | 36% | -0.263 | 0.65 | -0.117 | 0.146 | 10.7 | -0.189 | -0.300 | -0.23, -0.29 | no |
| B25_E3_h1_X1 | 162 | 35% | -0.306 | 0.57 | -0.233 | 0.074 | 19.5 | -0.229 | -0.325 | -0.26, -0.34 | no |
| B26_E3_m15_X2 | 670 | 37% | -0.251 | 0.66 | -0.105 | 0.146 | 10.8 | -0.178 | -0.288 | -0.24, -0.26 | no |
| B27_E3_m15_RR2 | 671 | 31% | -0.210 | 0.74 | -0.064 | 0.145 | 10.7 | -0.183 | -0.246 | -0.17, -0.24 | no |
| B28_E3_m15_X1_biasoff | 1697 | 39% | -0.155 | 0.78 | -0.014 | 0.141 | 11.0 | -0.095 | -0.191 | -0.14, -0.17 | no |
| B29_E3_m15_X1_all11 | 1425 | 37% | -0.251 | 0.66 | -0.104 | 0.147 | 11.9 | -0.197 | -0.289 | -0.18, -0.31 | no |
| B30_E3_m15_X1_F2 | 641 | 36% | -0.263 | 0.65 | -0.117 | 0.146 | 10.7 | -0.189 | -0.300 | -0.23, -0.29 | no |
| B31_E3_m15_X1_min25 | 67 | 36% | -0.174 | 0.74 | -0.127 | 0.047 | 31.3 | -0.150 | -0.185 | -0.49, +0.29 | no |
| B32_E3_m15_X1_front | 708 | 38% | -0.182 | 0.74 | -0.066 | 0.116 | 14.2 | -0.147 | -0.211 | -0.20, -0.17 | no |

No config has n >= 120 **and** PF >= 1.15 **and** positive expectancy **and** two positive halves. Highlights:

- **Best pessimistic net PF among configs with >= 100 trades: 0.97** (A5, the E4 rank book). Best net expectancy with >= 100 trades: -0.006R (E5) and -0.007R (E4), i.e. a coin flip that pays its costs.
- **Even the optimistic tie-break convention gives no positive net expectancy for any config with >= 100 trades** (best: E5 -0.006R, E4 -0.007R, E1-M15-X2mid -0.031R). So the failure is not an artefact of the pessimistic rule.
- The only positive rows are A1 (n = 20), A2 (n = 12) and B22 (n = 60, +0.007R). They fail the >= 120 trades rule; A1/A2 are what the docs' own 25-pip stop floor lets through: **20 and 12 orders in two years across five pairs**. Docs-as-written E1 cannot produce 15-35 R/month; it produces about one trade a month.
- A3 / B18 (E2 with the 25-pip floor) place **zero** orders.
- Stage B never moved anything toward the gates: the 32 variants (timeframe, exit ladder, entry, bias, buffer, F1/F2/F3, pair set) range from -0.15R to -0.48R net (excluding B22, n = 60 at +0.007R, and the three 25-pip-floor variants with < 70 orders). F1 (synthetic DXY), F2 (ATR shock) and F3 (dead money) changed E1-H1 by less than 0.02R.

### 5.2 Null calibration (random entries through the same execution model, TRAIN, 5 pairs, diagnostic only, not a trial)

Random direction, random bar inside the killzones, limit a fixed ATR distance under the close, same exit ladder, same costs, ~3,000 trades each:

| Config shape | Real: gross exp (pess) | Null: gross exp (pess) | Real: net (pess) | Null: net (pess) | Null net (opt) |
|---|---|---|---|---|---|
| B01 E1 M15 X1 | -0.163 | -0.166 | -0.346 | -0.424 | -0.209 |
| B03 E1 H1 X1 | -0.222 | -0.050 | -0.334 | -0.204 | -0.107 |
| B05 E1 H1 RR2 | -0.237 | -0.008 | -0.399 | -0.222 | -0.089 |
| B15 E2 M15 X1 | -0.070 | -0.159 | -0.232 | -0.447 | -0.273 |
| B24 E3 M15 X1 | -0.117 | -0.266 | -0.263 | -0.618 | -0.222 |

Read this carefully: the null's stops are not matched to the real setups (nulls have smaller stops, hence larger cost), so the net columns are not comparable and
this is **not** a significance test. The gross columns are the fairer comparison. On gross expectancy the E1 signal is **no better than random entries** (equal on M15, worse on H1),
E2 and E3 are 0.09R and 0.15R better than random entries but still negative before costs. Two things follow: (a) nothing here shows the SMC signals carry information the
random entry lacks, and (b) the simulator is not biased into a large fixed negative: at H1 the null brackets zero (pess -0.05 gross, opt about +0.05), on M15 it leans negative
(limit-fill adverse selection plus gap fills), which is a real feature of resting limit orders, not a proof of a bug. The tie-break spread itself (0.2-0.45R between conventions at
5-8 pip stops) shows that **M5 OHLC cannot resolve strategies with M15-scale stops**; conclusions about M15 configs rest on the tie-break rule, and only the rank books (stops 100-250 pips) are insensitive to it.

### 5.3 The docs' own claims

| Claim | Result on TRAIN |
|---|---|
| C1 realistic expectancy 0.60R at 40% WR | **Not reproduced.** No config with >= 100 trades has positive net expectancy (best -0.006R). Highest WR among E1/E2/E3 configs with >= 100 trades is 40% (E2) at -0.23R |
| C2 each engine > +0.25R out of sample | **Fails.** Not tested out of sample (never earned a TEST look); in sample no engine exceeds 0R with adequate n |
| C3 pairwise engine monthly correlation < 0.5 | **Not evaluated** - moot, since no engine has an edge to combine |
| C4 round-trip cost <= 5% of R with stops >= 25 pips | **True but vacuous.** Configs forced to >= 25 pip stops pay 2.9-4.7% of R. But only 0.1% (EURUSD M15) to 1.5% (H1) of the docs' own OB setups have such stops. At the natural stop the cost is 11% of R (E1 H1), 18% (E1 M15), 16% (E2) and 15% (E3); the pessimistic gross expectancy is already negative before cost |
| C5 gold on M15 is a cost leak | **Not supported.** XAUUSD has the *lowest* cost share of the 11 pairs in the model (0.05-0.11R vs 0.09-0.26R); its net expectancy is negative but among the least negative (-0.02R E1-H1, -0.17R E2, -0.11R E3). Nothing is positive, so this is not evidence for trading it either |
| C6 1.0R stop beats 0.7R | Not re-tested (docs rejected it) |
| Docs' pair exclusion (no XAU / JPY crosses for E1) | **Neither vindicated nor refuted:** GBPJPY (-0.015R) and XAUUSD (-0.023R) are the least negative pairs in the E1-H1 all-11 run, on 49 and 72 trades; all 11 are negative |

### 5.4 FORWARD smoke (2026-09-13 -> 2026-09-29, CI snapshot `/tmp/m5data`, reported only, never spliced)

The whole ledger was run through the same code on the newer CI snapshot to prove the pipeline runs end to end on it (it does: all 38 configs, all 11 pairs). Trade counts are
1-40 for the E1/E2/E3 configs and 12 / 36 for E4 / E5, so **nothing can be concluded and no gate applies**. For the record: the E1-M15 family is negative again (B01 -0.53R on 20 trades),
E5 is +0.10R on 36 trades (lower 90% bound +0.02R, but 62% of its R from one pair) and E4 +0.05R on 12. These do not change the verdict; a 16-day window
cannot promote a config that failed TRAIN.

### 5.5 Trial accounting

38 configs evaluated on TRAIN (6 + 32), 0 in Stage C, 0 TEST looks, 0 configs dropped or re-run after seeing results, no parameter changed after a run. Candidate selection, Stage C and TEST unlocking were all resolved mechanically by the pre-registered rules (and the TEST lock in the runner). Runner and CLI: `python tools/docs_v1_lab.py run --config all --window train`.

### 5.6 What this does and does not show

**Shows:** with these implementations of the docs' rules, on this data, with these costs, none of the five engines has a positive net expectancy with a usable trade count.
The docs' 25-pip stop floor is incompatible with their own M15 entries. A random-entry null with the same execution model is as good as the E1 signal on gross expectancy.

**Does not show:** that no discretionary or differently-specified SMC trading works. The detectors are my reading of loosely specified rules (sweep of one of the newest 6 fractal swings, CHoCH within 11 bars,
newest opposing candle as the order block, 2-bar fractals); other readings were not tried and the budget was spent on the menu the pre-registration allowed. Untestable here and left untested: the tick-volume gate
(volume is zero before 2024-01-25), real DXY / SMT, ADX, HMM regime, carry (E4's 60-day carry leg was dropped), spread-at-fill, slippage, execution latency, the prop-firm and procurement claims.
M5 bars cannot order events inside a bar, which matters for the M15 configs (see 5.2). A tick or M1 replay of the same configs would tighten that, and only makes sense for a config that first shows a gross edge; none does.
Whether these gates suit your goal is your call (see section 4, human-judged items).

### 5.7 Known limits of the lab

- Limit-order entries use the touch model (fill at the limit price on a touch; a fill bar cannot prove a target in the pessimistic convention). Real fills can be worse (no queue, no slippage modelled) or better.
- Portfolio limits are applied after the fact on per-symbol trade lists (approximate); account results are realised-balance only.
- The bootstrap resamples trading days with the ratio estimator, seed `20260929`; TRAIN used 2,000 resamples (informational only, no gate depends on it).
- F1's synthetic DXY omits SEK and uses closes on an M15 clock; F2 has no ADX.
- Baseline test suite: 226 tests with the lab's 25 added: 225 pass, 1 fails, the same pre-existing failure as before (`test_canonical_and_runtime_files_exist`, the doc moved to `docs/prop_firm/`); not touched.
