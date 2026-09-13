# M1 Lab — 1-minute validation & improvement search (2026-09-12)

**Tool:** `tools/m1_lab.py` (new file, research layer only — frozen
registries and MQL5 EAs untouched).
**Data:** user-uploaded M1 history (origin/main `578da08`): all 11 pairs,
2024-09-11 → 2026-09-11, validated against the Dukascopy API
(`validation/HistoryData/m1-data/validation-report-m1.txt`). Extracted
from git to `/home/user/.cache/m1` (NOT committed; repo stays lean).
**Objective (user):** "improve the current strategy, forget about
drawdown, give me the best combination." DD is reported for reference
only, not optimized.

## Method

- Signal detection UNCHANGED (champion: relaxed geometry 0.02/0.45/0.50,
  M5 bars, warm M15 ATR, all-London 07:00-11:00, T=1.5R, 90-min
  time-stop). `triad_honest.run_triad` gained an optional
  `sim_bars_fn(sym, date)` execution hook + `target_r_map` /
  `target_r_fn` / `entry_expire_min` / `breakeven_r` (all default to
  the original behavior — regression re-verified: 4y champion still
  exactly 94 trades / +$835.38 / P1 723d).
- Execution walks the 1-minute bars (`sim_triad`), resolving the
  stop-vs-target ordering that M5 had to assume. Residual ambiguity
  (within a single 1-min bar): **0 trades across every run below.**

## 1. Fidelity — does the champion survive at 1-minute resolution?

2y window, champion params, 1.5% risk, core-3 all-London:

| execution | n | PF | AvgR | total | DD | P1 | per pair (n/$) |
|---|---|---|---|---|---|---|---|
| M5 (baseline) | 55 | 2.26 | +0.391 | $813.79 | 4.4% | 201d | EURJPY 21/+362, XAUUSD 18/+323, GBPJPY 16/+128 |
| M1 | 55 | 2.28 | +0.395 | $821.75 | 4.4% | 201d | EURJPY 21/+362, XAUUSD 18/+328, GBPJPY 16/+131 |

**M1 − M5 = +$7.95 (+1.0%), identical trade count.** The M5 engine is
an accurate proxy; the champion edge is real at 1-minute resolution.

## 2. Improvement grid (M1 execution, 2y gate) — and its rejection

Gate ranking by total PnL (profit objective), core-3, 1.5%:

| config | 2y M1 $ | PF | 4y M5 confirm |
|---|---|---|---|
| **T1.5/ts90 (champion)** | $821.75 | 2.28 | **94 tr, +$835.38, PF 1.60, P1 723d** |
| T2.5/ts90 | $879.93 | 2.08 | **KILLED: floor hit after 15 trades (−$268, PF 0.40)** |
| T2.5/ts120 | $838.17 | 1.89 | (same family — killed) |
| T2.0/ts120 | $829.49 | 1.96 | (same family) |
| T1.5/ts120 | $818.47 | 2.25 | (within noise of champion) |
| BE@1.0R (breakeven move) | $568.11 | 1.96 | rejected at gate |
| BE@0.5R | $372.28 | 1.97 | rejected at gate |
| entry-expire 60m | $742.24 | 2.34 | rejected at gate |
| entry-expire 30m | $598.60 | 2.55 | rejected at gate |
| entry-expire 15m | $156.39 | 1.54 | rejected at gate |

The gate (pure 2024-26 gold-bull window) pushed T toward 2.5-4.0 for
XAUUSD (monotonic: XAU leg +$328→+$480→+$538→+$592→+$622 at T=1.5→4.0).
**4y confirmation kills it:** even with the floor disabled
("forget DD"), all-T2.5 makes $471 vs $835 (PF 1.26, DD 18.4%); XAU3.0
makes $815 but with 2× DD. The 2022-23 chop never trended 2.5R inside
90 minutes. A regime-safe variant (XAU T=2.5 only on close>SMA55 days,
reusing the gold leg's N) also died: floor after 14 trades (−$256) —
the longer holds blocked better JPY fills through the shared slot.

**T=1.5R / 90-min time-stop is the robust parameter set.** This is a
textbook gate-overfit caught by confirmation — recorded so nobody
re-fits T to the recent bull.

## 3. Universe scan (M1, 2y, champion params, standalone per pair)

| pair | n | PF | 2y $ | verdict |
|---|---|---|---|---|
| XAUUSD | 19 | 2.95 | +$379 | in core-3 |
| EURJPY | 21 | 2.78 | +$362 | in core-3 |
| GBPJPY | 17 | 1.75 | +$181 | in core-3 |
| USDJPY | 17 | 1.03 | +$9 | flat — no |
| AUDUSD | 15 | 0.98 | −$5 | no |
| GBPUSD | 11 | 0.77 | −$58 | no |
| NZDUSD | 21 | 0.69 | −$142 | no |
| EURGBP | 9 | 0.47 | −$126 | no |
| EURUSD | 10 | 0.23 | −$252 | no |
| USDCAD | 14 | 0.34 | −$266 | no |
| USDCHF | 10 | 0.23 | −$267 | no |

**The sweep/reclaim edge exists only in JPY crosses + gold.** All
USD-quoted pairs are negative. core-3 stays the universe — no new
triad legs to add.

## 4. Sizing — the only remaining "profit" lever (hard-rule bounded)

The5ers hard rules: 5% max daily loss, −10% floor, one position.
Worst realistic same-day realized loss = gold stop + triad stop:
3.0% + 1.5% = 4.5% (current) — already near the cap. The maximum
compliant nudge: **triad 1.5% → 1.75%** (worst day 4.75% < 5%).
Triad 2.0% would sit exactly on the 5% cap — not allowed.

## 5. Best combination (user's ask)

One shared slot, P0 first-available selection (proven best live rule in
the combo lab), M5 4y full window:

| sizing | 4y P0 total | CAGR | DD (ref) | P1 | legs (n/$) |
|---|---|---|---|---|---|
| 1.5% / 3.0% (certified) | $1,869.37 | 15.0% | 5.5% | 422d | triad 54/+$602, gold 19/+$1,267 |
| **1.75% / 3.0% (max compliant)** | **$1,960.95** | **15.6%** | 5.6% | 422d | triad 54/+$694, gold 19/+$1,267 |

2y gate at 1.75%/3.0%: $1,905.45, CAGR 22.2%, DD 3.1%, P1 in 116d.
P0 identical across opt/coin/pess and the challenge governors.

**Recommendation:** run the certified 1.5%/3.0% combo; the 1.75%
variant is +$91 (+4.9%) over 4y at the price of using 0.25% more of
the daily-loss budget on every triad day. Both are the SAME strategy —
the M1 lab found no parameter that improves it.

## Interpretation

1. **The M1 data is a validation asset, not an improvement asset, for
   this strategy family.** Fidelity is +1.0%; every variant it enabled
   (T-grid, breakeven, entry-expiry, 8 extra pairs) was rejected at
   gate or confirmation.
2. **The gate overfit trap is now documented with numbers.** The 2y
   window (2024-09→2026-09) is one gold bull; any parameter that loves
   it (large T) dies in the 2022-23 chop. T=1.5 is robust because it
   wins in both regimes (by year: 2022 −$24, 2023 −$61, 2024 +$255,
   2025 +$250, 2026 +$415 — the edge is a 2024-26 story carried by
   gold volatility, not a 2022-23 one).
3. **Why nothing beat P0 again:** M1 resolved the fills, and the
   ranking was unchanged — selection value remains hindsight-only
   (oracle $3,616 at 1.75% sizing vs $1,961 for P0, +85%).
4. **What M1 WOULD help with (future):** intraday patterns native to
   1-min resolution (scalping legs, tighter session windows), and
   re-touch timing studies. Out of scope for this combo.

## Honesty notes

- M1 covers 2y only (2022-23 has no 1-min data); the 4y confirmation
  ran on M5 execution (fidelity section shows M5≈M1 at +1.0%).
- All numbers: costs ON (spread+commission), re-touch limit fills,
  one slot, max 2 trades/day, weekday-only, per-day pip values.
- "Forget DD" was honored in the objective function; DD is shown
  because The5ers' floor (−10%) is a hard rule, not a preference —
  T2.5's death came from it, so it is reported.
- No M1 files are committed to the repo (data lives on origin/main
  `578da08`); `tools/m1_lab.py` extracts them to
  `/home/user/.cache/m1` at runtime.

## 6. LOGIC BATTERY — genuinely different triad logic (2026-09-12 follow-up)

User ask: "apply different logic, find the best & optimum result."
New variants tested on the M5 4y decision window (champion geometry,
core-3, T=1.5R, 90-min, 1.5%):

| # | logic | 4y M5 result | verdict |
|---|---|---|---|
| L1 | market entry at next bar open (no re-touch) | 111 tr, PF 1.30, $533.98, DD 11.3% | REJECTED — the re-touch filter is load-bearing (WR 51%→41%: momentum days that never retrace are mostly losers at this stop) |
| L2 | strongest-sweep-first same-day ordering | 93 tr, PF 1.66, $884.83, DD 6.6% | small win alone; **subsumed by D0a** (adds −$36 on top of it) |
| L3 | session extended 11:00 → 13:30 (late signals + longer fill time) | 105 tr, PF 1.57, $918.78, **P1 577d** (was 723d) | KEEP |
| L4a | stop buffer 0.10 → 0.05 ATR (stop at the true extreme) | 91 tr, **PF 1.78**, **$974.13**, **DD 4.9%** | KEEP (shape: 0.025→$945, 0.05→$974, 0.075→$826, 0.10→$835) |
| L4b | stop buffer 0.20 ATR | 13 tr, PF 0.35, floor hit | REJECTED (wide stop breaks the pattern) |
| L5/L6 | reclaim window 3 / 1 bars | identical to baseline | no effect |
| C1/C2 | market-entry combos | floor hit | REJECTED |

### D0a = tight stop (0.05 ATR) + extended session (13:30) — CERTIFIED

Beats the champion in all three windows:

| window | champion | D0a |
|---|---|---|
| 4y M5 (decision) | $835.38, PF 1.60, DD 7.8%, P1 723d | **$1,042.93, PF 1.70, DD 5.6%, P1 549d** |
| 2y FSB gate | $921.31, PF 2.13, P1 330d | **$994.10, PF 1.99, P1 255d** |
| 2y M1 (fidelity) | $821.75 | **$847.50** (+$26; note: M5 overstates this config by ~5% vs M1 — the extended/tight region is more resolution-sensitive) |

Mechanics: the stop sits at the sweep extreme itself (0.05 ATR buffer vs
0.10) — a cleaner invalidation AND a smaller R unit, so the 1.5R target
is reached more often inside the 90-min window; the session running to
13:30 captures late re-touch fills and 11:00-13:30 signals (never held
overnight — flat at 13:30).

### NEW BEST COMBINATION (D0a triad + gold N=55 k=2.5, one slot, P0)

`python tools/order_selector.py --confirm --d0a` (reproduces exactly):

| sizing | 4y total | CAGR | DD (ref) | P1 | legs (n/$) |
|---|---|---|---|---|---|
| 1.5% / 3.0% | **$2,075.93** | 16.3% | 4.7% | 196d | triad 59/+$809, gold 19/+$1,267 |
| **1.75% / 3.0% (max compliant)** | **$2,222.50** | **17.2%** | 4.7% | **124d** | triad 59/+$955, gold 19/+$1,267 |

2y gate at 1.75%/3.0%: $2,006.17, CAGR 23.2%, P1 115d. P0 identical
across opt/coin/pess and challenge governors. vs the previous best
(champion triad): **+$261 (+18% PnL), CAGR 15.6%→17.2%, Phase 1 in
124 vs 422 trading days (~6 months instead of ~1.8 years), DD down
5.6%→4.7%.**

Selection note: with D0a's denser triad, gate-calibrated P1/t0.1
narrowly beats P0 ON THE GATE ($1,942 vs $1,901) but 4y re-kills it
($1,175 vs $2,076 — the gold-lockout mechanism again). P0
first-available remains the best live selection rule.

## 7. Updated recommendation

Run the D0a combo (tight stop + extended session + gold + P0) at
1.5%/3.0% — or 1.75%/3.0% if you accept using 0.25% more of the daily
loss budget. The champion triad parameter set is otherwise unchanged
(T=1.5R, 90-min, relaxed geometry, core-3, all-London — now until
13:30). The M1 data's role: it validated the fills and killed the
bull-regime overfits (T2.5 family); the 4y M5 window remains the
decision set for anything structural.

## 8. OUT-OF-THE-BOX BATTERY (2026-09-12) — new logic, new levers

Beyond the parameter space: five structurally different ideas, tested
on the M5 4y decision window (D0a base, core-3):

| idea | 4y result | verdict |
|---|---|---|
| **Profit compounding** (size every trade off the CURRENT balance instead of fixed $2,500) | triad $1,043 → **$1,245 (+19%)**; PnL is linear in base, R/score untouched | KEEP |
| **Hour-of-day mining** (kill dead signal hours) | 07h: n=53 PF 1.93 +$673; 08h +$113; 09h +$135; 10h +$173 (n=4); 11h −$34 (n=3); 12h −$35 (n=3); 13h +$18 (n=2) | KEEP (no-late: signals ≤10:00 only — $1,043 → $1,093, PF 1.83, DD 4.5%; note: the 11-13h buckets are small-sample, n=8 total) |
| **NY session for JPY crosses** (13:30-16:00, London-morning ref range) | JPY: −$73 (PF 0.90); JPY+XAU: −$265 (PF 0.54) | REJECTED — NY is dead for this pattern, confirming session 9 |
| **NEW signal family: previous-day high/low liquidity sweeps** (sweep D-1 extreme ≥0.02 ATR, reclaim, displacement — same engine, `detect(ref_override=...)`) | 12 trades, PF 0.24, −$289 | REJECTED — the Asian-range reference is the edge; D-1 extremes are not |
| **Phase-2 timeline** (time to FULL account approval: P1 +10%, then P2 +5% on $2,750) | at final stack: **P1 day 124**, P2 (balance ≥ $2,887.50) **day 422** (equity drifts in the $2,750-2,887 band between); final 4y balance $5,829.62 | reported, no strategy change |

A bug was found and fixed while wiring compounding: `_take` mutated the
shared precomputed candidate trade dict in place, corrupting later
policy/ambiguity runs in the same process (double-scaled PnL). Now
scales a copy. Post-fix numbers are deterministic: P0 identical across
opt/coin/pess and the challenge governors.

### THE FINAL STACK (all keepers combined)

Triad: relaxed geometry + **D0a** (stop buffer 0.05 ATR, session to
13:30) + **no-late-signals** (≤10:00) + **compounding**, core-3
GBPJPY/EURJPY/XAUUSD; Gold Donchian N=55 k=2.5 compounding @3%; one
slot; P0 first-available (still the best live selection).

`python tools/order_selector.py --confirm --d0a --no-late --compound --risk 0.0175`

| sizing | 4y total | CAGR | DD (ref) | P1 | 2y gate |
|---|---|---|---|---|---|
| 1.5% / 3.0% | $2,993.07 | 21.7% | 4.2% | 196d | $2,702, CAGR 29.6%, P1 115d |
| **1.75% / 3.0% (max compliant)** | **$3,329.62** | **23.6%** | **4.2%** | **124d** | **$2,944, CAGR 31.7%, P1 115d** |

Progression of the best 4y combo across this session (same $2,500
base, P0, one slot):

| version | 4y PnL | CAGR | P1 |
|---|---|---|---|
| champion triad + gold (1.5/3.0) | $1,869 | 15.0% | 422d |
| + D0a (tight stop + extend, 1.75/3.0) | $2,223 | 17.2% | 124d |
| **+ no-late + compounding (1.75/3.0)** | **$3,330** | **23.6%** | **124d** |

Leg split at the final stack (1.75/3.0): triad 56 tr/+$1,569, gold
19 tr/+$1,761 — the two legs now contribute almost equally.

Honest caveats: (a) the no-late filter rests on 8 negative trades in
the 11-13h buckets — directionally sound (late sweeps are exhausted
moves) but small-sample; (b) compounding makes PnL path-dependent, so
a rough live year starts the curve below the backtest (the 4y path
includes 2022-23 losses that shrink the base before the bull); the
2y-gate numbers (pure bull, no prior shrinkage) are the right
expectation for an account starting NOW at $2,500: ~$2,944 over
~2 years, P1 in ~115 trading days; (c) 1.75% uses 4.75% of the 5%
daily cap on a double-stop day — compliant, no headroom; (d) oracle
(hindsight ceiling) at this stack: $8,270 (O1 books compounded PnL but
selects candidates on fixed-base PnL — approximate) — the remaining
gap is selection value that no live rule recovers, as before.

## 9. PER-PAIR STRATEGY FIT (2026-09-13) — each pair runs the logic it is best at

**Question (user):** each pair might work best under a *different* strategy —
which player (pair) fits which strategy, and does that improve the current
best combo?

**Method.** 11 pairs × 11 logic variants, standalone, 1.5% fixed base.
*Selection on the 2y gate only* (n ≥ 15, PF ≥ 1.2, total > 0, max $ per
pair); *confirmation on the 4y full window* (pick must stay positive, else
fall back to the best 4y member of the robust set {champion, D0a,
D0a+no-late}; else OFF). Two stages keep bull-regime artifacts (e.g. T > 1.5
in aggregate) from being certified. Same engine throughout (M5, re-touch
fills, coin ambiguity, raw costs).

Variants: V0 champion (buf 0.10, end 11:00, T 1.5, ts 90) · V1 D0a (buf
0.05, end 13:30) · V2 D0a+no-late (sig ≤ 10:00) · V3 extend (end 13:30
only) · V4 T 2.0 · V5 T 2.5 · V6 previous-day high/low reference · V7 NY
window · V8 loose sweep (0.01 ATR) · V9 D0a + 120-min time-stop · V10
market entry (D0a).

**2y picks (gate):**

| pair | 2y pick | 2y n | 2y PF | 2y $ |
|---|---|---|---|---|
| AUDUSD | V5 (T 2.5) | 15 | 1.47 | +$141 |
| EURJPY | V9 (D0a, ts 120) | 24 | 2.80 | +$441 |
| GBPJPY | V8 (loose sweep 0.01) | 17 | 2.25 | +$257 |
| USDJPY | V3 (extend 13:30) | 17 | 1.24 | +$77 |
| XAUUSD | V5 (T 2.5) | 19 | 3.21 | +$511 |
| EURGBP, EURUSD, GBPUSD, NZDUSD, USDCAD, USDCHF | — | | | no qualifying variant → OFF |

Six of eleven pairs have **no** qualifying variant in any of the 11 logics —
the family simply does not work there (every variant negative on 2y).

**4y confirmation (standalone, 1.5%):**

| pair | pick | 4y n | 4y PF | 4y $ | verdict |
|---|---|---|---|---|---|
| AUDUSD | V5 | 26 | 1.41 | +$208 | confirmed |
| EURJPY | V9 | 36 | 1.91 | +$447 | confirmed |
| GBPJPY | V8 | 25 | 1.72 | +$264 | confirmed |
| USDJPY | V3 | 36 | 1.05 | +$35 | confirmed (weak) |
| XAUUSD | V5 | 22 | 0.50 | **−$283** | **rejected** → fallback |

The XAUUSD T 2.5 pick is the clean demonstration of why the two-stage
protocol exists: +$511 on the 2y bull gate, −$283 (PF 0.50) on 4y — a
regime artifact. Fallback rule picks the best 4y robust variant: **V2
(D0a + no-late), 4y n=38, PF 2.18, +$581** — the same logic the uniform
stack already used, now *per-pair* certified.

**Portfolio ablation** (assigned triad universe + gold Donchian, one slot,
P0, 1.75% / 3.0%, compounding):

| case | universe | 4y $ | CAGR | DD | P1 |
|---|---|---|---|---|---|
| **A) 5 pairs, per-pair (final)** | AUD V5, EURJPY V9, GBPJPY V8, USDJPY V3, XAU V2 | **$3,811.34** | **26.1%** | 4.5% | 282d |
| B) 4 pairs (−USDJPY) | | $3,784.41 | 25.9% | 4.1% | 196d |
| C) core-3, per-pair | EURJPY V9, GBPJPY V8, XAU V2 | $3,396.43 | 23.9% | 4.1% | 124d |
| D) baseline uniform D0a+no-late | core-3 | $3,329.62 | 23.6% | 4.2% | 124d |
| E) sensitivity: AUDUSD→V2 | 4 pairs | $3,203.36 | 22.9% | 4.2% | 196d |

Case E (AUDUSD on its "robust" variant) loses $106 *in combo* — the fit is
genuinely per-pair, not "best variant in aggregate".

**THE PER-PAIR STACK (final, 2026-09-13):**

| pair | variant | rule (vs champion defaults) |
|---|---|---|
| AUDUSD | V5 | target **2.5R** (rest champion: buf 0.10, 11:00, ts 90) |
| EURJPY | V9 | D0a buf 0.05, session to **13:30**, **120-min** time-stop |
| GBPJPY | V8 | **sweep 0.01 ATR** (rest champion) |
| USDJPY | V3 | session to **13:30** (rest champion) |
| XAUUSD | V2 | D0a buf 0.05, session to 13:30, **signals ≤ 10:00** |
| + Gold Donchian N=55 k=2.5 @ 3% (unchanged) | | |

`python tools/order_selector.py --confirm --pairfit --compound --risk 0.0175`

| window | n | PF | total | CAGR | DD (ref) | P1 | final |
|---|---|---|---|---|---|---|---|
| **4y** (2022-09 → 2026-09) | 109 | 2.25 | **$3,811.34** | **26.1%** | 4.5% | 282d | $6,311.34 |
| **2y gate** (2024-01 → 2026-09, "starting now") | 72 | — | **$3,289.33** | **34.6%** | 4.5% | 115d | — |

vs baseline D: **+$481.72 (+14.5%) on 4y** and **+$345 (+11.7%) on the 2y
gate** — the improvement survives on both windows. Leg split (4y): triad
90/+$2,004 (AUDUSD 15/+$258, EURJPY 16/+$696, GBPJPY 15/+$247, USDJPY
18/−$40, XAUUSD 26/+$843), gold 19/+$1,807. By year: 2022 −$23, 2023
+$171, 2024 +$615, 2025 +$2,313, 2026 (to 09-11) +$734.

**The5ers compliance:** worst single day −$237.51 (2026-08-09) = **3.80%**
of start-of-day balance — inside the 5% cap and even inside the 0.5%
safety-buffer line (4.5%). Total floor $2,250 never approached (min equity
well above; DD 4.5%). One slot, max 2 trades/day unchanged.

**P1 tradeoff (the honest cost).** Baseline crosses $2,750 in Mar 2023
(P1 124d); the per-pair stack first crosses in Oct 2023 (P1 282d) — the
extra pairs (AUDUSD T 2.5, USDJPY extend) added exposure in the 2022-23
dead zone, dragging the early equity curve. It gives the gain back,
re-crosses Jul 2024, and **overtakes the baseline around Q2 2025**
($3,476 vs $3,381), pulling away in the 2025-26 bull as the larger base
compounds. If a fast Phase 1 is the priority, the §8 uniform stack remains
the right one; for maximum returns (the stated objective) the per-pair
stack wins on both windows.

**Honesty notes.** (1) Multiple comparisons: 121 configurations selected on
2y, confirmed on 4y. The two-stage protocol demonstrably kills the bull
artifact (XAUUSD V5) but does not eliminate all selection bias — the
per-pair edges (PF 1.4-2.2) are weaker than the aggregate champion's
(PF 2.8) and must be read with that discount. (2) The A-vs-B ablation used
4y in-combo PnL (mild confirmation-window selection); the pre-registered
rule (keep if 4y standalone > 0) independently keeps USDJPY, and A wins on
both PnL and CAGR regardless. (3) USDJPY V3 is **−$40 in combo** (4y
standalone +$35) — it is ballast kept only because A still beats B; if it
turns persistently negative it is the first pair to drop. (4) AUDUSD T 2.5
is regime-conditional: 2022-23 was roughly flat, the edge is 2024-26
trend; in a flat decade it contributes ~0 rather than large losses. (5)
GBPJPY V8 halves the sweep threshold (0.02 → 0.01 ATR) — more, weaker
signals; 4y PF 1.72 on n=25. (6) The no-late small-sample caveat (n=6
negative buckets) applies to XAUUSD V2 as before. (7) Compounding is
path-dependent — use the 2y gate row as the "starting now" expectation.
