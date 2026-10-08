# Structural ROI on real price paths: a no-edge trader through a full The5ers-style challenge (2026-09-30)

Follows `findings_challenge_ev.md`, which used a coin-flip model and found a positive expected value per challenge attempt for a **zero-edge** trader in 2-step challenges with a static 10 % max loss (+0.7x to +1.5x the fee). The user asked for that idea to be validated. A coin flip is not a market: real paths have gaps, spread, time exits and fat tails. This round re-runs the idea on the 10-year Dukascopy M5 data.

> Sections 1-3 were committed **before any challenge result was computed**. What I had seen: only the zero-edge diagnostic of the trade pool (section 3, mean R before costs is about 0 for random direction and time, as intended).

## 1. The trader (rule-based, deliberately no edge)

- Each trading day: pick one of EURUSD, GBPUSD, USDJPY, AUDUSD, XAUUSD at random, a **random direction**, and a random entry bar between 08:00 and 16:00 London (03:00-11:00 New York), never in the rollover blackout or the first hour after a weekend gap, and never within about +-4 minutes of 08:30, 10:00 or 14:00 New York (news times, widened).
- Stop = 0.5 x daily ATR20 (completed days only). Target = R x stop (R in {1, 2}). If neither is hit, flat at 20:00 London (before the rollover). Strict gap-aware stops, ties to the stop.
- Costs per trade: The5ers $4 round turn + spread (`B.cost_R`). Spread multiple on my raw `TYPICAL_RAW`: x2 (pre-declared primary) or x6 (stress, about the retail-feed spreads measured in `findings_tick_rollover.md`).
- Per day, N_CAND=8 random candidate bars per pair and both directions are pre-resolved on real prices (same walk code as the other labs); a simulated path draws one of that day's candidates at random. Directions are random, so the pool has no edge by construction; a test checks that the mean R before costs is within 0.06.

## 2. The challenge rules simulated (The5ers High Stakes "New", as read from public pages in 2026-09; verify before relying)

Phase 1 +10 %, Phase 2 +5 %, 5 % daily loss terminates, 10 % static max loss terminates, **3 profitable days each >= +0.5 % per phase**, no time limit (cap 700 trading days per path). Then funded: stop trading once +5 % is reached, wait >= 14 days, withdraw; the trader receives **80 %** of the gain; repeat up to 5 payouts or until the account is blown. EV per attempt = mean total payout - fee. Fee scenarios 0.3 %, 0.6 % (primary), 1.0 % of the account size (public pages disagree; the smallest High Stakes accounts list $19-22, a $100k one about $545-850).

Paths start on a random historical day; TRAIN starts 2016-10-01..2021-09-01, CONFIRM starts 2021-09-01..2024-09-01 (paths run on forward from there, so the data through 2026 is used).

## 3. Search space and decision rules (FIXED)

8 configs: risk per trade {2.5 %, 4 %} x R {1, 2} x cost multiple {2, 6}. Zero-edge diagnostic of the pool: R=1 mean -0.0012R, R=2 +0.0024R (n=205,280 each): **no edge before costs**, as intended.

- On TRAIN starts choose the best config **at the declared cost (x2)** by EV. Only that config goes to CONFIRM (lock file, one look), run at both x2 and x6.
- **The structural-ROI claim is validated only if**, on CONFIRM, at x2: EV >= +0.5x a 0.6 % fee with the 90 % interval (mean +- 1.645 se) above zero, AND at x6: EV > 0.
- Otherwise the claim is **rejected** and the real-path result replaces the coin-flip number. Either way it is reported.
- Caveats written before the run: the rules model omits firm discretion (gambling/consistency clauses), payout reliability, and the $150 minimum payout and ~3.5 % withdrawal fee reported by some sources; a positive result is still not proof a firm would pay.
- Tests: `tests/test_challenge_real_lab.py` (rule mechanics on synthetic paths, zero-edge pool on real data).

# Results

*(appended 2026-09-30; sections 1-3 above were committed first)*

## 4. Round 1 result: the idea survives real price paths, at a risk size the firm does not allow

TRAIN starts 2016-10..2021-09 (3,000 paths per config; all paths finished, none "open"):

| Config (risk, R, cost mult) | P(Phase 1) | P(both) | P(first payout) | mean payout | EV per attempt | x 0.6 % fee |
|---|---|---|---|---|---|---|
| 2.5 %, 1, x2 | 0.38 | 0.21 | 0.12 | 1.29 % | +0.69 % | +1.1 |
| 2.5 %, 1, x6 | 0.24 | 0.10 | 0.04 | 0.38 % | -0.22 % | -0.4 |
| 2.5 %, 2, x2 | 0.40 | 0.22 | 0.12 | 1.29 % | +0.69 % | +1.2 |
| 2.5 %, 2, x6 | 0.31 | 0.14 | 0.06 | 0.62 % | +0.02 % | 0.0 |
| 4 %, 1, x2 | 0.43 | 0.23 | 0.14 | 1.76 % | +1.16 % | +1.9 |
| 4 %, 1, x6 | 0.33 | 0.16 | 0.08 | 0.80 % | +0.20 % | +0.3 |
| **4 %, 2, x2** | 0.44 | 0.24 | 0.14 | 1.81 % | **+1.21 %** | **+2.0** |
| 4 %, 2, x6 | 0.35 | 0.15 | 0.08 | 0.89 % | +0.29 % | +0.5 |

Best at the declared cost: `r4_R2_m2`. **CONFIRM (starts 2021-09..2024-09, 6,000 paths, one look):** at x2 P(both) 0.23, first payout 0.13, EV +1.03 % of the account = **+1.7x** a 0.6 % fee (se 0.07 %); at x6 P(both) 0.18, EV +0.47 % = **+0.8x**. By the section-3 rule the **claim is validated on the model** (x2 >= +0.5x with the 90 % interval above zero, x6 > 0). Fee sensitivity at x2: 0.3 % fee +4.4x, 0.6 % +1.7x, 1.0 % +0.6x; at x6: +2.6x, +0.8x, +0.1x.

Limits of this reading: paths from nearby start days overlap, so the standard errors are too small (the honest uncertainty is larger); the EV is essentially all in the payouts (P of a first payout is 13 %); and the model assumed rules that turned out to be too permissive, see section 5.

## 5. The rules check (web, 2026-09) invalidates the 4 % risk size

Reading The5ers' published rules after round 1 (sources: propfirmmatch rules page, tradetanto, the5ers FAQ pages, tradersunion, dealpropfirm, quantvps; some are third-party and they disagree in places):
- **High Stakes prohibits** "allocating a substantial or majority portion of the allowable daily loss or available margin to a single trade idea" (risk-management rule), plus one-sided betting, martingale, and "position sizing inconsistency". The Bootcamp caps any position at 2 % risk. 4 % risk is 80 % of a 5 % daily limit: not allowed. Even 2.5 % is 50 %.
- **Payout cap per request on bigger High Stakes accounts**: $3,000 on $50K, $4,000 on $100K (minimum P&L for payout $300 and $500 respectively); minimum withdrawal $150; withdrawal fee 2-3.5 %.
- **Fee refund is partial**, not cash at once: 10 % and 20 % of the fee become non-withdrawable Hub Credits after Phases 1 and 2; about 70 % of the fee can be added to funded equity and withdrawn with the first payout (quantvps/traderssecondbrain read of the policy); other sources say "full refund". I counted **no refund** (conservative).
- Some pages give 4 % daily / 8 % static loss for the "New" route; others 5 % / 10 %. News: no new order within 2 minutes of high-impact news (my random entries avoid +-4 minutes of 08:30, 10:00, 14:00 New York).
- Entry fees: $22 for $2.5K, $39 for $5K, $78 for $10K, $165 for $20K-$25K, $329 for $60K, $545 for $100K (0.55 %-0.9 % of the account).

## 6. Round 2 (PRE-REGISTERED, committed before any round-2 result): compliance-constrained

Changes (all fixed now): risk per trade {1.0 %, 1.5 %, 2.0 %} (2 % is 40 % of a 5 % daily limit and equals the Bootcamp cap; I treat 2 % as the highest defensible and recommend less), R {1, 2}, cost multiple {2, 6} = 12 configs; payouts net of a **3.5 %** withdrawal fee; fee primary **0.8 %** of the account ($39 on $5K); the day cap raised to 1,500 trading days; no fee refund counted; same TRAIN and CONFIRM start windows and the same decision rule (confirm at x2 >= +0.5x the fee with the 90 % interval above zero, and x6 > 0). Additional fixed sensitivity on CONFIRM only: daily 4 % / max loss 8 % (the stricter rule reported by some pages). Payout caps do not bind on accounts of $25K or smaller and are ignored; the result is stated per unit of account size.

# Round 2 results

*(appended 2026-09-30; section 6 was committed before any of this was run)*

## 7. Round 2 result: NOT VALIDATED. With the firm's risk limit respected, the structural play is cost-fragile and roughly zero-EV.

**TRAIN starts 2016-10..2021-09** (12 configs, fee 0.8 %, payouts net of 3.5 % withdrawal fee; all paths finished):

| Risk | R | x2 cost: P(both) | x2 EV (x fee) | x6 cost: P(both) | x6 EV (x fee) |
|---|---|---|---|---|---|
| 1.0 % | 1 | 0.12 | -0.33 % (-0.4) | 0.02 | -0.78 % (-1.0) |
| 1.0 % | 2 | 0.15 | -0.10 % (-0.1) | 0.05 | -0.70 % (-0.9) |
| 1.5 % | 1 | 0.16 | -0.16 % (-0.2) | 0.06 | -0.63 % (-0.8) |
| 1.5 % | 2 | 0.20 | +0.22 % (+0.3) | 0.10 | -0.46 % (-0.6) |
| 2.0 % | 1 | 0.21 | +0.37 % (+0.5) | 0.09 | -0.52 % (-0.6) |
| **2.0 %** | **2** | 0.22 | **+0.44 % (+0.5)** | 0.12 | -0.26 % (-0.3) |

Best at the declared cost: `c_r2_R2_m2` (2 % risk, R = 2). **CONFIRM (starts 2021-09..2024-09, 6,000 paths, one look):**

| Rule set | Cost | P(Phase 1) | P(both) | P(first payout) | EV per attempt | x 0.8 % fee |
|---|---|---|---|---|---|---|
| daily 5 % / max 10 % | x2 | 0.42 | 0.24 | 0.14 | +0.61 % (se 0.05) | **+0.8** |
| daily 5 % / max 10 % | x6 | 0.30 | 0.14 | 0.07 | -0.19 % | **-0.2** |
| daily 4 % / max 8 % | x2 | 0.36 | 0.19 | 0.10 | +0.14 % | +0.2 |
| daily 4 % / max 8 % | x6 | 0.27 | 0.12 | 0.05 | -0.33 % | -0.4 |

- Decision rule: x2 passes (+0.8x >= +0.5x, interval above zero) but **x6 fails** (EV < 0). So the claim is **not validated**. The no-edge structural play is only positive if all-in costs are about my x2 (EURUSD about 0.6 pip all-in incl. commission) or lower, and turns negative if costs triple; under the stricter 4 %/8 % rules it is about zero even at x2.
- Risk below about 1.5 % per trade loses money at any cost (too slow: many days, costs bleed, few reach the targets); the coin-flip model of `findings_challenge_ev.md` badly overstated the low-risk end because real trades mostly end at the time exit near zero R, not at +-R.
- The 4 % / R=2 result of round 1 (+1.7x, then +0.8x at x6) is what the model gives at a size the firm prohibits; it should not be acted on.
- Honest limits: overlapping start days make the standard errors optimistic; firm discretion, payout caps above $25K and payout delays are not modelled; the cost multiple is an assumption that a demo-account spread log would resolve; roughly 86 % of attempts still end without a payout.

## 8. Ledger

Files: `tools/challenge_real_lab.py` (`train`, `confirm`, `train2`, `confirm2`; CONFIRM locks used), `tests/test_challenge_real_lab.py`, `tools/challenge_ev.py` (coin-flip model, now known to be optimistic). Not a market-edge search, so the trial count of 210 stands; this is 8 + 12 = 20 configs of a structural test, with their own pre-registration and lock files.
