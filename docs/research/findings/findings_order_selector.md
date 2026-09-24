# Combo Lab — Best-Order Selection Under One Slot (2026-09-12)

**Tool:** `tools/order_selector.py` (new file, research layer only — frozen registries and MQL5 EAs untouched).
**Question:** user asked for a strategy combination where, when multiple order candidates exist, the system selects the best risk-reward / best order. Two validated legs (TRIAD sweep/reclaim intraday core3 + Gold Donchian swing N=55 k=2.5) share ONE account-wide position slot. The previously published two-leg portfolio compounded the legs' equity curves independently (slot double-counted on collision days) — this lab re-derives the combination under the shared slot and ranks selection policies.

## Policies
- **P0 chrono** — first candidate whose slot is free (status quo).
- **P_PRO production** — P0 + the frozen EA cost gate (InpMaxCostToR=0.10, cost vs target).
- **P1 bar(θ)** — first candidate with composite score ≥ θ.
- **P2 patience(θ)** — after the first signal, wait 30 min (capped at session end); take the best-scoring candidate seen in the window (score ≥ θ) if it would still fill; else fall back to P1 for the day.
- **P3 bar+upg(θ)** — P1 + upgrade-only: never take a candidate weaker than one already passed today.
- **P4 legbar(θ_g)** — the cross-leg selector: triad candidates take on first-available (P0 semantics); the GOLD entry at the open is gated on its own walk-forward score ≥ θ_g.
- **O1 oracle** — DIAGNOSTIC loose upper bound: hindsight pick of the best realized PnL among fillable candidates today (gold multi-day opportunity cost ignored). Not live-tradable.

## Score (walk-forward, no look-ahead)
`score = max(E[R],0) * conviction * 1/(1+costR) * diversity` — E[R] = expanding mean of the leg's completed net R (min 5 trades, else research prior {'triad': 0.1, 'gold': 0.3}); conviction ∈ [0.5,1.5] from pattern strength; costR = (spread+commission)/initial-risk; diversity 0.85 for a same-day second JPY trade.

Gold-leg equivalence vs swing_lab: PASS (identical trade R) — ref 12 trades PF 6.71 meanR +1.480 | this 12 trades meanR +1.480

## 2-year FSB gate (Jan 2024 → Sep 2026)

| Policy | n | WR | PF | AvgR | Total | CAGR | DD | P1 | legs (n/$) |
|---|---|---|---|---|---|---|---|---|---|
| P0 | 49 | 67.3% | 3.70 | +0.63 | $1831 | 21.5% | 2.8% | 116d | triad:37/+499 gold:12/+1332 |
| P_PRO | 32 | 68.8% | 4.49 | +0.82 | $1637 | 19.5% | 2.5% | 116d | triad:20/+305 gold:12/+1332 |
| P1/t0.05 | 17 | 64.7% | 4.72 | +1.01 | $1311 | 16.1% | 4.0% | 116d | triad:5/-21 gold:12/+1332 |
| P1/t0.1 | 21 | 61.9% | 4.46 | +0.87 | $1358 | 16.6% | 2.4% | 116d | triad:9/+26 gold:12/+1332 |
| P1/t0.15 | 12 | 75.0% | 6.71 | +1.48 | $1332 | 16.3% | 2.4% | 338d | gold:12/+1332 |
| P1/t0.2 | 12 | 75.0% | 6.71 | +1.48 | $1332 | 16.3% | 2.4% | 338d | gold:12/+1332 |
| P1/t0.3 | 12 | 75.0% | 6.71 | +1.48 | $1332 | 16.3% | 2.4% | 338d | gold:12/+1332 |
| P1/t0.5 | 0 | 0.0% | inf | +0.00 | $0 | 0.0% | 0.0% | NO |  |
| P2/t0.05 | 17 | 64.7% | 4.72 | +1.01 | $1311 | 16.1% | 4.0% | 116d | triad:5/-21 gold:12/+1332 |
| P2/t0.1 | 21 | 61.9% | 4.46 | +0.87 | $1358 | 16.6% | 2.4% | 116d | triad:9/+26 gold:12/+1332 |
| P2/t0.15 | 12 | 75.0% | 6.71 | +1.48 | $1332 | 16.3% | 2.4% | 338d | gold:12/+1332 |
| P2/t0.2 | 12 | 75.0% | 6.71 | +1.48 | $1332 | 16.3% | 2.4% | 338d | gold:12/+1332 |
| P2/t0.3 | 12 | 75.0% | 6.71 | +1.48 | $1332 | 16.3% | 2.4% | 338d | gold:12/+1332 |
| P2/t0.5 | 0 | 0.0% | inf | +0.00 | $0 | 0.0% | 0.0% | NO |  |
| P3/t0.05 | 17 | 64.7% | 4.72 | +1.01 | $1311 | 16.1% | 4.0% | 116d | triad:5/-21 gold:12/+1332 |
| P3/t0.1 | 21 | 61.9% | 4.46 | +0.87 | $1358 | 16.6% | 2.4% | 116d | triad:9/+26 gold:12/+1332 |
| P3/t0.15 | 12 | 75.0% | 6.71 | +1.48 | $1332 | 16.3% | 2.4% | 338d | gold:12/+1332 |
| P3/t0.2 | 12 | 75.0% | 6.71 | +1.48 | $1332 | 16.3% | 2.4% | 338d | gold:12/+1332 |
| P3/t0.3 | 12 | 75.0% | 6.71 | +1.48 | $1332 | 16.3% | 2.4% | 338d | gold:12/+1332 |
| P3/t0.5 | 0 | 0.0% | inf | +0.00 | $0 | 0.0% | 0.0% | NO |  |
| P4/t0.05 | 49 | 67.3% | 3.70 | +0.63 | $1831 | 21.5% | 2.8% | 116d | triad:37/+499 gold:12/+1332 |
| P4/t0.1 | 49 | 67.3% | 3.70 | +0.63 | $1831 | 21.5% | 2.8% | 116d | triad:37/+499 gold:12/+1332 |
| P4/t0.15 | 49 | 67.3% | 3.70 | +0.63 | $1831 | 21.5% | 2.8% | 116d | triad:37/+499 gold:12/+1332 |
| P4/t0.2 | 49 | 67.3% | 3.70 | +0.63 | $1831 | 21.5% | 2.8% | 116d | triad:37/+499 gold:12/+1332 |
| P4/t0.3 | 49 | 67.3% | 3.70 | +0.63 | $1831 | 21.5% | 2.8% | 116d | triad:37/+499 gold:12/+1332 |
| P4/t0.5 | 67 | 64.2% | 2.13 | +0.36 | $921 | 11.8% | 4.3% | 330d | triad:67/+921 |
| O1 | 39 | 100.0% | inf | +1.31 | $2733 | 29.9% | 0.0% | 116d | triad:31/+1181 gold:8/+1552 |

## 4-year confirmation (2022-09 → 2026-09)

_Primary: gate-calibrated policy vs P0 (status quo) and the oracle. Parameters were chosen on the 2-year gate — this run only confirms, it does not re-select._

| Policy | n | WR | PF | AvgR | Total | CAGR | DD | P1 | legs (n/$) |
|---|---|---|---|---|---|---|---|---|---|
| P0 | 73 | 63.0% | 2.58 | +0.44 | $1869 | 15.0% | 5.5% | 422d | triad:54/+602 gold:19/+1267 |
| O1 | 53 | 100.0% | inf | +1.20 | $3301 | 23.4% | 0.0% | 152d | triad:42/+1588 gold:11/+1713 |

### 4-year full policy family (descriptive, same gate-calibrated θ grid)

| Policy | n | WR | PF | AvgR | Total | CAGR | DD | P1 | legs (n/$) |
|---|---|---|---|---|---|---|---|---|---|
| P0 | 73 | 63.0% | 2.58 | +0.44 | $1869 | 15.0% | 5.5% | 422d | triad:54/+602 gold:19/+1267 |
| P_PRO | 42 | 61.9% | 3.00 | +0.59 | $1542 | 12.8% | 6.5% | 422d | gold:19/+1267 triad:23/+275 |
| P1/t0.05 | 12 | 41.7% | 0.78 | -0.11 | $-77 | -0.8% | 9.9% | NO | triad:7/-25 gold:5/-51 |
| P1/t0.1 | 87 | 63.2% | 1.88 | +0.32 | $1053 | 9.2% | 5.7% | 194d | triad:82/+1105 gold:5/-51 |
| P1/t0.15 | 5 | 40.0% | 0.71 | -0.14 | $-51 | -0.5% | 6.9% | NO | gold:5/-51 |
| P1/t0.2 | 5 | 40.0% | 0.71 | -0.14 | $-51 | -0.5% | 6.9% | NO | gold:5/-51 |
| P1/t0.3 | 5 | 40.0% | 0.71 | -0.14 | $-51 | -0.5% | 6.9% | NO | gold:5/-51 |
| P1/t0.5 | 0 | 0.0% | inf | +0.00 | $0 | 0.0% | 0.0% | NO |  |
| P2/t0.05 | 10 | 40.0% | 0.73 | -0.14 | $-83 | -0.8% | 8.5% | NO | triad:5/-32 gold:5/-51 |
| P2/t0.1 | 78 | 61.5% | 1.75 | +0.28 | $838 | 7.5% | 5.6% | 559d | triad:73/+890 gold:5/-51 |
| P2/t0.15 | 5 | 40.0% | 0.71 | -0.14 | $-51 | -0.5% | 6.9% | NO | gold:5/-51 |
| P2/t0.2 | 5 | 40.0% | 0.71 | -0.14 | $-51 | -0.5% | 6.9% | NO | gold:5/-51 |
| P2/t0.3 | 5 | 40.0% | 0.71 | -0.14 | $-51 | -0.5% | 6.9% | NO | gold:5/-51 |
| P2/t0.5 | 0 | 0.0% | inf | +0.00 | $0 | 0.0% | 0.0% | NO |  |
| P3/t0.05 | 12 | 41.7% | 0.78 | -0.11 | $-77 | -0.8% | 9.9% | NO | triad:7/-25 gold:5/-51 |
| P3/t0.1 | 87 | 63.2% | 1.88 | +0.32 | $1053 | 9.2% | 5.7% | 194d | triad:82/+1105 gold:5/-51 |
| P3/t0.15 | 5 | 40.0% | 0.71 | -0.14 | $-51 | -0.5% | 6.9% | NO | gold:5/-51 |
| P3/t0.2 | 5 | 40.0% | 0.71 | -0.14 | $-51 | -0.5% | 6.9% | NO | gold:5/-51 |
| P3/t0.3 | 5 | 40.0% | 0.71 | -0.14 | $-51 | -0.5% | 6.9% | NO | gold:5/-51 |
| P3/t0.5 | 0 | 0.0% | inf | +0.00 | $0 | 0.0% | 0.0% | NO |  |
| P4/t0.05 | 90 | 61.1% | 1.71 | +0.28 | $929 | 8.2% | 5.9% | 559d | triad:85/+980 gold:5/-51 |
| P4/t0.1 | 90 | 61.1% | 1.71 | +0.28 | $929 | 8.2% | 5.9% | 559d | triad:85/+980 gold:5/-51 |
| P4/t0.15 | 90 | 61.1% | 1.71 | +0.28 | $929 | 8.2% | 5.9% | 559d | triad:85/+980 gold:5/-51 |
| P4/t0.2 | 90 | 61.1% | 1.71 | +0.28 | $929 | 8.2% | 5.9% | 559d | triad:85/+980 gold:5/-51 |
| P4/t0.3 | 90 | 61.1% | 1.71 | +0.28 | $929 | 8.2% | 5.9% | 559d | triad:85/+980 gold:5/-51 |
| P4/t0.5 | 94 | 59.6% | 1.60 | +0.23 | $835 | 7.5% | 7.8% | 723d | triad:94/+835 |
| O1 | 53 | 100.0% | inf | +1.20 | $3301 | 23.4% | 0.0% | 152d | triad:42/+1588 gold:11/+1713 |

## Verdict

Best live policy on 4y: **P0** (θ=0) — CAGR 15.0% at DD 5.5%, 73 trades, PF 2.58.
Best *selection* policy on 4y: **P1** (θ=0.1) — CAGR 9.2% at DD 5.7%, PF 1.88. Vs P0 (chrono): 48 days traded differently, net PnL delta $-816 (31 added / 17 removed).
Oracle (O1, loose upper bound) CAGR 23.4% ($3301) — +1432 vs P0's $1869. The oracle knows the future; treat it as the ceiling on selection value, not a target.

## Interpretation

1. **First-available (P0) is the best live selection rule on both the gate and 4y.** No risk-reward score policy beats it. This is the honest negative result of the lab.
2. **The one-slot cost of the combination is real and was previously hidden.** The published two-leg figure (CAGR ~21.3%, findings_swing_and_portfolio.md) compounded the legs' curves independently. Under the shared slot the honest number is **15.0% CAGR / 5.5% maxDD / Phase 1 in ~422 trading days** (the independent-curve figure never modeled the slot). Gold's multi-month holds block the triad leg: triad makes $+602 on 54 trades inside the combo vs +$835 on 94 standalone over 4y (session 9 champion) — gold occupying the slot cuts the triad PnL by a quarter and blocks roughly 40 entries.
3. **Why score-based selection loses — the negative-E lockout.** P1-P3 gate on each leg's walk-forward expectancy. In 2022-23 both legs' expanding mean R goes negative (their weak years); `max(E,0)` then scores every candidate 0 and the policy stops trading — permanently, because a leg's expectancy can only recover by trading it. P4 isolates the mechanism: it frees the triad leg (always first-available) and gates only gold — result $929 vs P0's $1,869, because the gated gold never re-enters after 2023 and misses the 2024-26 gold bull that produced most of the value. A self-updating gate on its own history locks a system out of the regime turn.
4. **Where the hindsight value actually lives (oracle decomposition).** Oracle gold: 11 entries for $+1,713 vs P0's 19 for $+1,267 (skipping losing entries); oracle triad: 42 for $+1,588 vs P0's 54 for $+602 (taking only the winning days). Both are hindsight decisions — the gold entry decision itself is made at the open when ONLY gold is known, and taking the high-static-expectancy leg (+0.89R vs +0.17R per unit risk) is the correct live call.
5. **P_PRO observation (research layer only).** The frozen EA's InpMaxCostToR=0.10 gate rejects a third of the triad candidates on this universe (P_PRO triad: 23 trades, $+275 vs P0's 54, $+602). The production EA is frozen and runs a different symbol set (EURUSD/GBPUSD/USDJPY) — this is recorded as a tuning observation, not a change request.
6. **Follow-ups (not certified):** a price-based regime gate for gold (e.g. entry only in an uptrend) would not self-lock-out, but it cannot be gate-calibrated (the 2y gate is one long bull) and must not be counted on 4y alone. The primary path to the 40-50% target remains more validated uncorrelated legs (tick data, more instruments), per STRATEGY-ROADMAP.md.

## Honesty notes
re-touch limit fills, coin ambiguity (bounds printed in the run output — P0 is identical across opt/coin/pess, 0% ambiguous fills in the combo), raw-account costs, per-day pip values, max 2 trades/day, fixed-base sizing (1.5% triad / 3% gold on $2,500). Gold exits are daily-close based (no intrabar ambiguity); triad fills are the only path-dependent piece. Gold trades weekends (the daily series includes weekend bar-days, exactly as in swing_lab).
