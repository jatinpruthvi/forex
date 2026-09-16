# Broker cost budget and minimum balance

Companion to `findings_phase2_speed.md`. Produced by
`validation/speed_lab/broker_cost_and_balance.py` (stdlib only, ~14 s).

All figures are the frozen M5 long-only 4×ATR exhaustion fade, TRAIN-selected 8-pair universe
(`EURGBP, AUDUSD, NZDUSD, USDCAD, USDCHF, EURJPY, GBPJPY, XAUUSD`), held-out TEST period
2024-09-11 → 2026-09-11, 1,198 signals, next-bar-open fills, pessimistic intrabar exits,
0.50% risk, degenerate-stop guard on.

---

## 0. Jurisdiction blocks this for an Indian resident — read first

This was prepared for a user in Ahmedabad, India, and the answer is constrained by law before
it is constrained by spreads.

Under **FEMA 1999**, a person resident in India may deal in foreign exchange only through an
RBI-authorised person, and may trade currency derivatives only on a recognised Indian exchange
(NSE / BSE / MSE) via a SEBI-registered broker. OTC spot forex and CFDs on non-INR pairs
through an offshore broker are not permitted. The **Liberalised Remittance Scheme expressly
prohibits** remitting funds abroad for margin trading or forex speculation.

**Every instrument this strategy trades is affected.** None of the 8 pairs is an INR pair, and
none is among the contracts available on Indian exchanges — USDINR, EURINR, GBPINR, JPYINR
futures and options, plus EURUSD, GBPUSD and USDJPY cross-currency futures. The strategy
additionally requires continuous 24×5 M5 spot bars spanning the daily rollover, which
exchange-traded currency futures do not provide (fixed session hours, contract expiry, rolls).

The **RBI Alert List** (95 entities, updated 19 November 2025) names, among others: IC Markets,
Pepperstone, Fusion Markets, Tickmill, FP Markets, Exness, XM, IG Markets, Admiral, Think
Markets, BlackBull, Vantage, VT Markets, HF Markets/HotForex — that is, **every broker modelled
in §3 below** — and also lists **MetaTrader 4 and MetaTrader 5 themselves**, plus the prop firms
FTMO, FundedNext and Smart Prop Trader. RBI states the list is not exhaustive, so absence from
it is not authorisation.

Reported penalties under FEMA s.13: up to **three times the amount involved** or ₹2 lakh
(whichever is higher), **₹5,000 per day** for a continuing violation, and up to **5 years
imprisonment** for a serious or wilful violation under s.13(1C). Funds in unauthorised offshore
accounts may be attached.

The broker comparison in §3 is therefore provided as **cost analysis** — the spread budget and
the rollover finding are real properties of the strategy and are needed to interpret any
backtest — and **not as a recommendation to open an account**. It should not be acted on by a
person resident in India. Confirm your own residency status and take advice from a professional
qualified in Indian exchange-control law. If your residency is not Indian, §1–§4 apply as
written.

---

## 1. Spread budget — what a broker must offer

The validated cost model charges round-turn spread = 0.55 × the standard spread (a raw/ECN
account) plus $7.00 per lot commission, inside every trade. Costs below are expressed as a
fraction of 1R. "Break-even" is the widest round-turn quote at which the pair still has
positive expectancy on TEST.

| pair | std (pips) | raw (pips) | median stop | cost/1R | E_gross | E_net | break-even | headroom | n |
|---|---|---|---|---|---|---|---|---|---|
| EURGBP | 1.40 | 0.77 | 4.0 pips | 32.3% | +1.146R | **+0.823R** | 4.14 pips | 5.4× | 178 |
| AUDUSD | 1.20 | 0.66 | 6.3 | 23.3% | +0.658R | +0.426R | 3.15 | 4.8× | 186 |
| NZDUSD | 1.60 | 0.88 | 5.8 | 29.8% | +0.605R | +0.307R | 2.51 | **2.9×** | 187 |
| USDCAD | 1.80 | 0.99 | 8.5 | 22.8% | +0.828R | +0.600R | 5.47 | 5.5× | 109 |
| USDCHF | 1.40 | 0.77 | 6.3 | 26.1% | +1.155R | **+0.894R** | 5.86 | 7.6× | 200 |
| EURJPY | 1.60 | 0.88 | 16.0 | 13.9% | +0.491R | +0.352R | 5.99 | 6.8× | 123 |
| GBPJPY | 2.00 | 1.10 | 19.5 | 15.2% | +0.870R | +0.717R | 12.64 | 11.5× | 128 |
| XAUUSD | 2.80 | 1.54 | 93.0 | 3.2% | **−0.187R** | **−0.219R** | *none* | *n/a* | 87 |
| **all 8** | | | | **22.8%** | **+0.765R** | **+0.537R** | | | 1,198 |

The broker keeps **22.8% of 1R** on the validated quotes; costs consume **30% of the gross
edge**. That is the entire margin of safety, which is why spread is not a rounding error here.

**NZDUSD has the least headroom (2.9×)** and is the pair to check first on any broker.

### XAUUSD has no break-even spread

Gold's gross expectancy on TEST is **negative** (−0.187R) before any cost, so no spread makes it
work. It was selected on TRAIN, where it made **+0.319R** over 76 trades, and decayed on TEST
(87 trades). Only 3.2% of 1R goes to cost because its stops are ~93 pips — spread is *not* its
problem, the edge is.

Per-pair TRAIN vs TEST, for context. Dropping gold **on TEST evidence alone** would be fitting
to the held-out set — the exact error that made this repo's own PR #9 overstate itself by 2.5× —
so this is recorded as information, not applied as a retune:

| pair | TRAIN E_net | TEST E_net | verdict |
|---|---|---|---|
| EURGBP | +1.792R | +0.823R | decayed |
| AUDUSD | +0.076R | +0.426R | held up |
| NZDUSD | +0.552R | +0.307R | decayed |
| USDCAD | +0.070R | +0.600R | held up |
| USDCHF | +0.288R | +0.894R | held up |
| EURJPY | +0.171R | +0.352R | held up |
| GBPJPY | +0.319R | +0.717R | held up |
| XAUUSD | +0.319R | **−0.219R** | **negative on TEST** |

### Raw/ECN beats a standard account

Because stops are wide, 1R is large in dollars, so a flat commission is a smaller slice of it
than the spread. Raw wins on **6 of 8** pairs. The two exceptions (EURJPY +0.0136R, GBPJPY
+0.0080R favouring standard) are marginal and both have low pip value, which makes the fixed
$7 relatively larger.

---

## 2. Minimum initial balance — three different floors

### (a) Lot granularity — the binding one

`lots = floor(risk / loss_per_lot / 0.01) × 0.01`, and the EA **skips** the trade below 0.01
lots. With risk = balance × 0.50%, a trade is takeable only when
`balance ≥ 0.01 × loss_per_lot / 0.005 = 2 × loss_per_lot`.

| pair | median $/lot | p95 $/lot | max $/lot | min balance (worst) |
|---|---|---|---|---|
| EURGBP | 58 | 170 | 280 | 560 |
| AUDUSD | 70 | 203 | 423 | 846 |
| NZDUSD | 65 | 180 | 327 | 654 |
| USDCAD | 90 | 279 | 592 | 1,184 |
| USDCHF | 69 | 194 | 386 | 772 |
| EURJPY | 105 | 356 | 782 | 1,565 |
| GBPJPY | 108 | 341 | 719 | 1,437 |
| XAUUSD | 937 | 2,777 | **8,051** | **16,101** |

- **$1,565** covers the worst trade on the 7 FX pairs.
- **$16,101** covers the worst trade including XAUUSD — gold alone raises the floor **10×**,
  because a gold stop is ~93 pips on a 100 oz contract where each pip is worth $10.
- **$5,553** covers 95% of trades on every pair.

Skipped trades are **not random** — they are the wide-stop ones. A small account therefore does
not run the validated strategy, it runs a biased subset of it. In practice that bias is
favourable at present (the skipped trades are disproportionately gold, which is losing), but it
is an accident of granularity, not a designed filter, and should not be relied on.

Measured effect across balances (full replay, EA gates):

| balance | signals skipped | mean %/mo | median | worst month | maxDD | total |
|---|---|---|---|---|---|---|
| $250 | 29.3% | +11.75% | +10.39% | −9.61% | 10.6% | +294% |
| $500 | 11.2% | +13.23% | +9.70% | −11.08% | 8.1% | +331% |
| $1,000 | 6.3% | +12.75% | +9.70% | −11.11% | 9.2% | +319% |
| $2,500 | 2.4% | +12.60% | +10.04% | −11.11% | 11.7% | +315% |
| $5,000 | 0.5% | +12.25% | +10.04% | −11.61% | 11.9% | +306% |
| $10,000 | 0.1% | +12.42% | +10.04% | −12.12% | 11.9% | +311% |

### (b) Margin — decided by leverage, not by balance

Measured on the actual trade stream, not a synthetic worst case. The 8-pair stream reaches
**9 concurrent positions** and **13 trades in a day** at peak (time-weighted: 0 open 9.3%,
1 open 23.5%, 2 open 25.5%, 3 open 18.7%, 4 open 11.9%, 5+ open 11.1%).

Peak margin as a share of equity:

| balance | 1:30 | 1:50 | 1:100 | 1:200 | 1:500 |
|---|---|---|---|---|---|
| $500 | 260% | 156% | 78% | 39% | 16% |
| $2,500 | 274% | 164% | 82% | 41% | 16% |
| $10,000 | 275% | 165% | 83% | 41% | 17% |

Margin usage is **almost independent of balance** because lots scale with it — so leverage, not
account size, decides this row. At **1:100 the peak is ~82%**, meaning a margin call arrives
before the strategy's own −3R daily breaker does. 1:200 is tight-but-workable, 1:500 is
comfortable. At the **1:30 EU/UK retail cap it is ~274% and cannot be run as validated** at all.

### (c) Drawdown tolerance

Fixed sizing on TEST: maxDD ~12%, worst month ~−11%, ~24% of months negative. Compounded:
maxDD ~23%.

---

## 3. Real broker quotes — and why rollover spread is the number that matters

### 44% of entries land in the rollover window

Entries by UTC hour on held-out TEST:

```
21:00   368 entries (30.7%)   <-- daily rollover, the single largest hour
22:00   161 entries (13.4%)
12:00    83 entries  (6.9%)
20:00    83 entries  (6.9%)
all other hours: 503 entries (42.0%)
```

**43.8% of entries fall in the server 20:00–00:59 rollover/close window.** Published 30-day
broker tests measure EURUSD at **0.1 pips** in London but **1.2 pips average and 3.1 max**
across the 21:00–22:00 rollover, with 0% of time at zero. A broker's headline number describes
the session carrying only ~42% of these trades. This is the same daily-roll/weekend-close
window where the degenerate-stop bug was concentrated.

### Modelled against published raw-account quotes

Peak-hour quotes only (the flattering view):

| broker | commission RT | E_net | mean %/mo | maxDD | total |
|---|---|---|---|---|---|
| backtest assumption (flat) | $7.00 | +0.537R | +12.60% | 11.7% | +315% |
| IC Markets Raw | $7.00 | +0.603R | +14.16% | 10.2% | +354% |
| Fusion Markets Zero | $4.50 | **+0.638R** | **+14.93%** | 9.6% | +373% |
| Pepperstone Razor | $7.00 | +0.600R | +14.15% | 10.2% | +354% |
| Tickmill Pro | $4.00 | +0.620R | +14.54% | 9.9% | +363% |

With rollover widening applied to UTC 21:00–22:59 entries. **The multiplier is an assumption,
not a measurement** — published data implies ~12× on EURUSD, so it is swept:

| broker | ×2 | ×4 | ×8 | ×12 |
|---|---|---|---|---|
| backtest assumption (flat) | +0.537R | +0.537R | +0.537R | +0.537R |
| IC Markets Raw | +0.574R | +0.516R | +0.400R | +0.284R |
| Fusion Markets Zero | **+0.608R** | **+0.550R** | **+0.434R** | **+0.317R** |
| Pepperstone Razor | +0.571R | +0.511R | +0.393R | +0.275R |
| Tickmill Pro | +0.577R | +0.492R | +0.321R | **+0.150R** |

Mean %/month under the same sweep: Fusion +14.24% → +7.66%; Tickmill +13.54% → **+3.62%**.

### What this says

- On peak-hour quotes alone every real raw account beats the backtest assumption, because the
  model charged 0.55× standard spread on all pairs while real raw quotes are 2–7× tighter on
  most of this universe.
- That advantage **shrinks or reverses once the rollover is priced**. At a realistic 8–12×
  widening, expectancy is materially *below* the published backtest figure, not above it.
- **Commission is the second-order choice.** $4.00 vs $7.00 round turn moves expectancy less
  than a 2× change in rollover spread does. Tickmill's industry-lowest commission does not
  save it from being worst at 12× widening, because its peak quotes on EURGBP/GBPJPY/XAUUSD are
  the widest of the four.
- The decisive number is each broker's **21:00–22:00 UTC spread on EURGBP, NZDUSD and XAUUSD**
  — not its homepage headline. `MQL5/Scripts/EA_SIGNAL_DUMP.mq5` on a demo account for two
  weeks measures it directly; the CSV carries the entry timestamp on every row, so the rollover
  subset can be isolated and its realised spread compared against the London-session subset.

**Broker spreads/commissions above are from published independent measurements (compareforexbrokers
2026 raw-account testing; lowspreadbroker 30-day live tests, 2026) and several cells are
interpolated from the same broker's other pairs rather than directly published. They move
constantly and are not a quote.**

---

## 4. What "% per month" means — and a correction to an earlier figure

Two sizing modes give very different headlines from the same trades.

| mode | mean/mo | median | worst | maxDD | final | total |
|---|---|---|---|---|---|---|
| fixed (0.50% of starting balance) | +12.60% | +10.04% | −11.11% | 11.7% | $10,378 | +315% |
| compounded (0.50% of current equity) | +13.28% | +8.60% | −11.89% | 22.6% | $41,978 | +1579% |

Compounded geometric rate: **+11.94%/month on current equity** over 25 months.

**A ~10%/month target is inside what this strategy demonstrated on held-out data** — but only
under compounding, and the price of compounding is that the drawdown roughly doubles (22.6% vs
11.7%), because positions are largest exactly when the account is at its peak. On fixed sizing
the honest rate is ~12.6% of the *starting* balance per month, and it does not grow.

### Correction: two configs are in circulation and they differ by ~2×

`personal_account_analysis.py` publishes **TEST 0.50% = +6.26%/month**, which uses the
prop-firm caps (≤2 concurrent, ≤5 trades/day) in `replay_personal`'s defaults. The EA's shipped
inputs are `InpMaxConcurrent = 99` and `InpMaxTradesPerDay = 99` — *take every signal* — which
gives **+12.60%/month**. Both are correct for their configuration; the caps are firm
protection, not edge protection.

An early version of this analysis inherited `replay_personal`'s 2/5 defaults and under-reported
the EA's own behaviour by half. It now pins `EA_CONC = 99`, `EA_DAY = 99`, `EA_BREAKER = 3.0`
to the EA's inputs explicitly, with a comment explaining why the defaults must not be used.

Both figures are **gross of swap**, which the cost model does not charge.
`personal_account_analysis.py` measures 0.772 nights per trade and shows 0.10R/night costing
about 1.3 points of monthly return — second-order, but a broker's swap table decides it, and
for a long-only book it is a persistent one-way drag that varies by pair.

---

## Bugs found in this analysis while building it

Each was caught by reconciliation, not by review:

1. **`month_stats(res, A0=V.ACCOUNT)` binds its default at import time.** Python evaluates
   default arguments once, so every balance row was silently divided by $2,500 and `mean %/mo`
   stopped reconciling with `total` (it showed +25.90%/month against a +162% total). Fixed by
   passing `A0` explicitly at every call site.
2. **Margin notional used the quoted price instead of the base currency's USD price.** For
   GBPJPY the quote is JPY per GBP, so notional was overstated ~200× and the table reported
   5397% margin usage. Fixed by reusing `margin_and_swap_exposure.BASE`.
3. **Margin sized for 2 concurrent positions.** That is the prop-firm cap, not the EA's; the
   real peak is 9. The whole floor-2 table was replaced with a replay that tracks margin on the
   actual trade stream.
4. **`replay_personal`'s prop caps were inherited as the EA's behaviour**, halving reported
   returns. See the correction in §4.
5. **Rollover widening was applied to the flat backtest model**, which by definition does not
   vary by hour, corrupting the reference row and every "vs assumed" percentage derived from it.

---

## Sources

- RBI Alert List, 95 entities, updated 19 November 2025 (PTI / RBI; reproduced by Upstox,
  Outlook Money, Economic Times, Gulf News).
- FEMA 1999 s.13 penalties; LRS prohibition on margin trading and forex speculation
  (RBI Master Directions; taxguru.in, m4markets, incredmoney, tradebrains, pippenguin, 2026).
- Raw-account spread measurements: compareforexbrokers.com "Which Broker Has the Tightest
  Spread" (March 2026 methodology, August 2026 results) and per-broker spread/fee reviews
  (2026); lowspreadbroker.com 30-day live tests of IC Markets and Fusion Markets (2026),
  including the session-by-session EURUSD table showing 1.2 pips average / 3.1 max across the
  21:00–22:00 rollover.
- Commission structures: Fusion Markets $4.50 RT, Tickmill Pro $4.00 RT, IC Markets / FP
  Markets / Exness $7.00 RT per lot.
