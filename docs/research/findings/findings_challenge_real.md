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
