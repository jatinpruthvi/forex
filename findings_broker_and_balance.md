# Broker cost budget and minimum balance

Companion to `findings_phase2_speed.md`. Produced by
`validation/speed_lab/broker_cost_and_balance.py` (stdlib only, ~14 s).

All figures are the frozen M5 long-only 4×ATR exhaustion fade, TRAIN-selected 8-pair universe
(`EURGBP, AUDUSD, NZDUSD, USDCAD, USDCHF, EURJPY, GBPJPY, XAUUSD`), held-out TEST period
2024-09-11 → 2026-09-11, 1,198 signals, next-bar-open fills, pessimistic intrabar exits,
0.50% risk, degenerate-stop guard on.

---

## 0. Scope: intended end users are outside India

The author is resident in India but intends to **sell this EA to non-Indian users**, so
jurisdiction is not treated as a blocker here and the analysis below is written for a buyer
resident outside India.

It is recorded once, for completeness, because it does constrain the author personally: under
FEMA 1999 a person resident in India may deal in forex only through an RBI-authorised person and
may trade currency derivatives only on a recognised Indian exchange (NSE/BSE/MSE) via a
SEBI-registered broker; none of the 8 pairs is available there, and the Liberalised Remittance
Scheme cannot fund offshore margin trading. The RBI Alert List (95 entities, 19 Nov 2025) names
every tightly-priced broker modelled in §3 and also MetaTrader 4 and 5 themselves. **This affects
the author running the EA on their own account. It does not affect a buyer in a jurisdiction where
leveraged OTC forex is permitted** — which is the intended market, and which is what §1–§4 address.

Anyone deploying this should confirm the position in *their own* jurisdiction and the leverage
cap their broker's entity offers, because §2(b) shows the configuration needs ≥1:200.

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
| FXCC ECN XL (myfxbook live) | **$0.00** | +0.633R | +14.79% | 9.7% | +370% |

With rollover widening applied to UTC 21:00–22:59 entries. **The multiplier is an assumption,
not a measurement** — published data implies ~12× on EURUSD, so it is swept:

| broker | ×2 | ×4 | ×8 | ×12 |
|---|---|---|---|---|
| backtest assumption (flat) | +0.537R | +0.537R | +0.537R | +0.537R |
| IC Markets Raw | +0.574R | +0.516R | +0.400R | +0.284R |
| Fusion Markets Zero | **+0.608R** | **+0.550R** | **+0.434R** | **+0.317R** |
| Pepperstone Razor | +0.571R | +0.511R | +0.393R | +0.275R |
| Tickmill Pro | +0.577R | +0.492R | +0.321R | +0.150R |
| FXCC ECN XL (myfxbook live) | +0.558R | +0.407R | +0.107R | **−0.193R** |

Mean %/month under the same sweep: Fusion +14.24% → +7.66%; Tickmill +13.54% → +3.62%;
**FXCC +13.12% → −4.35%** — the only broker in the group that goes negative.

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

### FXCC checked directly, and what myfxbook does and does not settle

FXCC (fxcc.com) and the myfxbook spread comparison were both checked as asked. FXCC's live
per-pair quotes come from **myfxbook's own FXCC feed** (broker id 5191), sampled from real
accounts — not from FXCC's marketing:

| pair | FXCC live | break-even ceiling (§1) | headroom |
|---|---|---|---|
| EURGBP | 0.9 | 4.14 pips | 4.6× |
| AUDUSD | 0.6 | 3.15 pips | 5.3× |
| NZDUSD | 0.7 | 2.51 pips | 3.6× |
| USDCAD | 0.5 | 5.47 pips | 11× |
| USDCHF | 0.5 | 5.86 pips | 12× |
| EURJPY | 1.3 | 5.99 pips | 4.6× |
| GBPJPY | 1.3 | 12.64 pips | 9.7× |
| XAUUSD | 16¢ = 1.6 pips | none — negative edge | n/a |

Every FX pair clears its ceiling with room to spare, and the account terms are genuinely good
for an EA: **$0 commission, no minimum deposit, 1:1000 max leverage, no requotes, EAs and
custom scripts explicitly allowed, free VPS, swap-free accounts, stop-out 50%**. It passes
every requirement in §3 except one, and the one it fails is the one that matters most here.

**The problem is structural, not a bad quote.** FXCC's cost is 100% spread and 0% commission.
A commission is a *fixed* cost — it does not widen at the rollover. A spread is *variable*, and
it does. So FXCC has no fixed-cost ballast at all, and 43.8% of this strategy's entries land in
the rollover window. That is why it is second-best at peak hours (+0.633R, essentially tied with
Fusion's +0.638R) and **worst of all six once the rollover is priced**: +0.107R at 8× widening
and −0.193R at 12×, the only negative figure in the table. Fusion, with $4.50 of fixed
commission, is still +0.317R at 12×.

The second problem is which entity offers the leverage. FXCC runs two:

| entity | regulator | leverage | segregated funds | usable here? |
|---|---|---|---|---|
| FX Central Clearing Ltd (Cyprus) | CySEC, licence 121/10; ICF to €20,000 | 1:30 retail | **Yes** | **No** — §2(b) measures 1:30 at 260–275% margin, a stop-out |
| Central Clearing Ltd (Comoros) | MISA (Mwali), licence BFX2024085 | up to 1:1000 | **No**, per FXEmpire's entity table | Yes on margin, but this is the weak-regulator, unsegregated one |

So the entity that can actually carry this strategy's margin is the one that does not segregate
client funds, and the entity that does segregate is capped at leverage the strategy cannot use.
That trade-off is not unique to FXCC — it is the general shape of offshore forex — but it should
be chosen deliberately rather than discovered later. The 100% deposit bonus (up to $2,000) is a
further reason for caution when the EA is sold on: bonuses typically carry traded-volume and
withdrawal conditions that a buyer would inherit without expecting them.

**On myfxbook's comparison page specifically:** it is region-filtered, and the default view here
listed FOREX.com, tastyfx and Oanda. Two limits make it the wrong tool for *this* decision:

1. **The spread table excludes commission**, so a $0-commission spread-only account and a
   $7-commission raw account are not comparable in it. There is a separate Commissions toggle.
2. Against our break-even ceilings those three are fine on paper (FOREX.com EURGBP 0.2, NZDUSD
   0.9; tastyfx 0.9/1.8) except **Oanda's NZDUSD at 2.4 against a 2.51 ceiling — 1.05× headroom,
   i.e. NZDUSD is a zero-edge pair there**. But all three are retail/US-oriented at 1:30–1:50
   leverage, and §2(b) measures 1:50 at 156–165% margin: **a stop-out before the strategy's own
   risk limit**. None of them can run this EA regardless of how good the spreads look.

The useful thing myfxbook provided is FXCC's live per-pair feed above. It cannot settle the
question that actually decides the broker — the 21:00–22:00 UTC rollover spread — because a
single snapshot is not a session-weighted average. That still needs `EA_SIGNAL_DUMP.mq5` on a
demo account.

**Broker spreads/commissions above are from published independent measurements (compareforexbrokers
2026 raw-account testing; lowspreadbroker 30-day live tests, 2026; myfxbook's live FXCC quote
feed, 2026) and several cells are interpolated from the same broker's other pairs rather than
directly published. They move constantly and are not a quote.**

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

## 5. Minimum balance at 1:500 leverage — the direct answer

At 1:500 the margin floor stops binding: measured on the actual TEST stream, peak margin is ~16%
of equity and nearly independent of balance, because lots scale with balance. So the minimum is
set entirely by **lot granularity** — the EA skips a trade when `floor(risk/loss_per_lot/0.01)×0.01
< 0.01`, i.e. when `balance < 2 × loss_per_lot`.

Realised risk per trade, which is the fidelity measure that matters (target 0.500%):

| balance | 8 pairs: skipped | 8 pairs: realised risk | 7 FX pairs: skipped | 7 FX: realised risk |
|---|---|---|---|---|
| $500 | 11.2% | 0.422% | 4.5% | 0.422% |
| $1,000 | 6.3% | 0.452% | **0.5%** | 0.453% |
| **$1,565** | 4.0% | 0.468% | **0.0%** | **0.470%** |
| $2,000 | 3.3% | 0.472% | 0.0% | 0.475% |
| $2,500 | 2.4% | 0.476% | 0.0% | 0.481% |
| $5,000 | 0.5% | 0.485% | 0.0% | 0.491% |
| $16,101 | 0.1% | 0.494% | 0.0% | 0.497% |
| $25,000 | 0.0% | 0.496% | 0.0% | 0.498% |

No trade that *is* taken ever risks under half the target — sub-0.01-lot signals are skipped
outright rather than under-sized. So granularity shows up as skipped trades, not as quiet
under-risking.

### The single number

> ## $2,000
> Seven FX pairs (XAUUSD excluded), 1:500 leverage, `InpRiskPercent = 0.50`.

That is the answer. The reasoning in one line each:

- **Below $1,565 the EA starts silently dropping signals**, because a trade is only takeable
  when `balance ≥ 2 × loss_per_lot` and the worst trade in the 7-pair stream costs $782/lot
  (EURJPY). $1,565 is that arithmetic floor: 0.0% of signals skipped, realised risk 0.470%.
- **$1,565 is a knife-edge, not a recommendation.** It is set by one outlier trade, with zero
  buffer. At $2,000 nothing is skipped either (realised risk 0.475%) and there is 28% of
  headroom above the floor, so a slightly wider stop than the historical worst still fits.
- **Above $2,000 you buy almost nothing.** $2,500 moves realised risk from 0.475% to 0.481% and
  monthly return by well under a point. The granularity floor is satisfied; the rest is
  preference. (Every headline figure in this repo is quoted at $2,500 purely because that is the
  prop-challenge account size the config was selected on — not because $2,500 trades better.)
- **Leverage, not balance, is the margin constraint.** At 1:500 peak margin is ~16% of equity at
  *every* balance from $500 to $16,000 (§2b), so margin never binds here. At 1:50 it is 156–165%
  and the broker stops you out first — which is why 1:500 is a requirement, not a preference.
- **Do not add gold to get a bigger number.** XAUUSD raises the floor 10× to $16,101, to trade a
  pair whose held-out TEST expectancy is **negative** (−0.187R gross, −0.219R net). Set
  `InpSymbols` to the seven FX pairs instead; that is both cheaper and better.

If a single alternative is wanted for a more conservative buyer: **$2,500**, which is the exact
balance the +12.60%/mo and 11.7% maxDD figures were measured at.

**One input must be changed with the broker.** `InpCommissionPerLotRT` defaults to `7.0` and is
*inside* the lot-size calculation, not just reporting. On a $0-commission broker such as FXCC,
leaving it at 7.0 under-sizes every position by 6.5–12.1%, so realised risk lands at 0.439–0.468%
instead of 0.500%. Set it to the broker's actual round-turn commission: Fusion $4.50, Tickmill
$4.00, IC Markets / Pepperstone $7.00, FXCC $0.00. The mirror error is the dangerous one — a
broker charging *more* than the input over-sizes past the risk mandate. Round 5 of the audit made
the EA print this value in its first log line and warn if it is negative.

At 1:500 there is no margin constraint at any of these balances, and no broker's minimum deposit
is binding either (FXCC $0, Fusion ~$0, Pepperstone $0–200, Tickmill $100, IC Markets $200). The
only remaining check is **whether the entity you register under actually offers 1:500** — ASIC,
FCA and CySEC retail entities are capped at 1:30–1:50, far below what §2(b) needs, so leverage and
tier-1 regulation are traded against each other and must be chosen deliberately. §3's FXCC entity
table is the clearest example: the regulated entity cannot carry the margin, and the entity that
can is the weak-regulator one.

---

## 6. Which broker

Ranked against the requirements in §3 and the EA README's broker table, on the modelled numbers
rather than on marketing.

**First choice — Fusion Markets, Zero account.** Lowest commission in the group ($4.50 round turn)
and the best measured spreads on four of this universe's eight pairs (AUDUSD 0.09, USDCAD 0.23,
NZDUSD 0.30, USDCHF 0.41). It won **every** rollover scenario in §3: +0.638R at peak quotes,
+0.434R at 8× widening, +0.317R at 12×. ASIC-regulated. Caveat: a smaller firm than IC Markets,
and its leverage depends on which entity you register under.

**Strong alternative — IC Markets, Raw Spread.** Its **$7 round-turn commission is exactly what
the backtest assumed**, so it reproduces the validated cost model with no adjustment — worth a lot
when you are selling an EA against published numbers. Best measured spreads on the two pairs where
this strategy is most concentrated (EURGBP 0.27, EURJPY 0.30). Server GMT+2 winter / GMT+3 summer,
aligned to the NY 17:00 close, which matches the validation's +3 assumption half the year. Largest
firm in the group, MT5, hedging, own VPS, $200 minimum.

**Pepperstone Razor** — choose it if FCA regulation matters for your buyer's jurisdiction. Best
EURGBP (0.20–0.30) and USDCHF (0.39) in the group, but the worst EURJPY (1.1–1.2), and GMT+2/+3.

**Dukascopy** — worth a look specifically for buyer confidence: a Swiss bank, MT5, GMT+2/+3
NY-aligned, hedging explicitly allowed, EAs allowed, stop-out ≤50%, 21 account currencies. Its
pricing is less competitive than the three above, so it trades cost for counterparty strength.

**Not recommended despite the best-looking terms — FXCC.** Checked directly as asked (§3). The
account terms are the most EA-friendly in the group: $0 commission, no minimum deposit, up to
1:1000, no requotes, EAs explicitly allowed, free VPS, swap-free accounts, and every FX pair
clears its break-even ceiling by 3.6–12×. At peak hours it is second-best of six (+0.633R,
+14.79%/mo), a hair behind Fusion. It still loses, for two reasons:

1. **It has no fixed-cost ballast.** With $0 commission, 100% of its cost is spread, and spread
   is what widens at the rollover where 43.8% of these entries land. It is the *worst* of the six
   once that is priced — +0.107R at 8× and **−0.193R at 12×, the only negative in the table**
   (−4.35%/mo). A broker whose entire cost is variable is the wrong shape for a strategy that
   trades the rollover.
2. **Leverage and fund segregation sit in different entities.** The CySEC entity segregates funds
   and carries ICF cover to €20,000 but is capped at 1:30, which §2(b) measures as a stop-out.
   The MISA (Comoros) entity offers 1:1000 but, per FXEmpire's entity comparison, does not
   segregate. The 100% deposit bonus adds traded-volume/withdrawal conditions a buyer would
   inherit unexpectedly.

**Avoid for this universe — Tickmill**, despite the industry's lowest commission ($4 Pro, $2 VIP
above $50k). Its spreads on EURGBP (0.40), GBPJPY (1.00) and XAUUSD (1.50) are the widest of the
group, and §3 shows commission is second-order here: Tickmill's cheap commission does not stop it
being **worst-but-one at 12× rollover widening (+0.150R)**.

**The lesson from Tickmill and FXCC is the same one, and it is the rule to buy on:** for this
strategy a broker's cost must be judged by *what happens to it at 21:00 UTC*, not by its headline.
Commission is fixed and survives the rollover; spread is variable and does not. So the ranking is
set by measured rollover spread, with commission acting as the part of the cost that cannot widen
— which is why Fusion ($4.50 fixed, tightest spreads on four pairs) wins every scenario and why
the two cheapest-looking options on paper, FXCC ($0 commission) and Tickmill ($4), finish last.

**Avoid — Exness**, despite excellent quotes, because its server is **fixed GMT+0 year-round**.
That shifts every server-day boundary 3 hours from the +3 the validation assumed, so the daily
breaker, qualifying-day windows and Friday cutoff no longer correspond to what was measured. The
EA's own day boundaries stay internally correct — `CheckServerOffset()` warns — but the published
figures would need re-validating on that clock first.

**The decisive step before funding, whatever you pick:** run `EA_SIGNAL_DUMP.mq5` on a **demo**
account for two weeks with `InpBarsToDump=120000`, then `compare_ea_dump.py`. The CSV carries the
entry timestamp on every row, so you can isolate the UTC 21:00–22:59 subset and compare its
realised spread against the London-session subset on *your* account type. That replaces the 8×
rollover assumption — the single largest uncertainty in this cost model, worth roughly 5 points of
monthly return — with a measurement. It also surfaces the four silent cross-broker failures at
once: symbol suffix, server offset, netting mode, and minimum stop distance.

---

## Bugs found in this analysis while building it

Five were in this analysis itself, each caught by reconciliation rather than by review:

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
   vary by hour, corrupting the reference row and every percentage derived from it.

Answering "is there still a bug?" then produced a fourth audit round on the EA itself. Four more
defects, two of them serious:

6. **Netting accounts were never detected** (serious). A second `Buy()` on a netting account
   merges into the open position and **overwrites its SL/TP**, destroying the first trade's stop.
   13.8% of TEST signals stack on a symbol already open. Fixed by detecting
   `ACCOUNT_MARGIN_MODE` and skipping same-symbol entries; cost of running on netting quantified.
7. **Broker symbol suffixes silently shrank the universe** (serious for an EA being sold).
   `SymbolSelect()` fails on `EURGBP.m`, one warning scrolls past, and the EA trades a subset
   while looking healthy. Fixed with `ResolveSymbol()`/`SuffixPlausible()`, tested by
   `validation/speed_lab/test_ea_symbol_resolution.py` including mutation control — the
   permissive variant is shown to mis-resolve `USD` onto `USDCAD`, proving the rule is
   load-bearing.
8. **`ProcessOnce()` ran a full deal-history scan on every tick** — hundreds of `HistorySelect()`
   calls a second, enough to starve the bar-open evaluation the entry-lag guard depends on.
   Throttled to one scan per second with a dirty flag forcing an immediate rescan after a fill.
9. **"Gates not satisfied" never said which gate** — useless to a buyer whose account is not USD.
   Added `FirstClosedGate()`.

Checked and cleared, no change needed: the 96 h timeout is wall-clock in the EA but a 1,152-*bar*
count in the backtest, which diverge across weekends. Measured on TEST, only 10 of 1,198 trades
close a different bar and the worst gap is 6 minutes.

After all four fixes the equivalence proof still holds: `ea_emulator.py` reports ATR, signals and
gates **IDENTICAL** (3,290 = 3,290), and `selftest_ea_dump.py` passes with all four verbatim
function copies still identical to the EA's and 9/9 mutations caught.

### Round 5 — from the FXCC/myfxbook broker check (3 more; 1 fixed, 1 fixed, 1 refuted)

Asked again whether any bug remained. Three findings, of which the third is the interesting one
because the audit *disproved* a fix that looked obviously correct.

| # | where | what | severity | outcome |
|---|---|---|---|---|
| 23 | `NormaliseLots()` | The volume sent to `trade.Buy()` was `MathFloor(lots/step)*step` with no normalisation. `0.01` has no exact binary64 representation, so `n*step` carries a 1-ULP residue — 35 steps is `0.35000000000000003`, not `0.35`. A broker validating volume against `SYMBOL_VOLUME_STEP` by exact comparison rejects that with `TRADE_RETCODE_INVALID_VOLUME` (10014). Measured on the real validated trade list: **3 of 1,111 volumes at $1,565, 15 at $2,000, 25 at $2,500 (2.3%)** — roughly one live signal in 43 at the reference balance. No backtest can catch it, because no backtest round-trips a volume through a server. | **High, live-only** | **Fixed** — rounds to the step's own decimal count, with an explicit guard that the clean-up can never authorise more volume than the floor did |
| 24 | `CheckServerOffset()` | `(double)((detected+1800)/3600)` reads as round-to-nearest but both operands are integers, so MQL5 does integer division, which **truncates toward zero**. Correct east of UTC, wrong west of it: −1h reported as 0, −2h as −1, −5h as −4 — **every** negative offset an hour high. Does not corrupt order flow (`ServerDayKey` uses `TimeCurrent` directly) but corrupts the one diagnostic relied on when porting to a new broker: it can raise a bogus WARN or suppress a real one, and a silent offset mismatch shifts the session filter with no visible symptom. Invisible on the common GMT+2/+3 MT5 servers, which is why four earlier rounds missed it. | Medium | **Fixed** — `MathFloor(((double)detected+1800.0)/3600.0)` |
| 25 | `NormaliseLots()` floor | Suspected that `MathFloor(raw/step)` loses a whole step when the quotient lands a ULP below an integer, and that the fix is a tolerance (`MathFloor(q+1e-9)`). **The suspicion was right about the mechanism and wrong about the remedy.** Against exact rational arithmetic over all 3,290 trades × 3 balances, the shipped plain floor disagrees with true intent **zero** times, while the tolerance **over-sizes 7 trades at $2,000 and 2 at $2,500**. Cause: `stop_pips` comes from price differences, so `loss_per_lot` is not a round number even when it prints like one (11.80 pips on AUDUSD gives `125.00000000000699`). A quotient of `9.99999999999944` is therefore not float noise around 10 — it correctly reports a stop a whisker wider than the round number, so 9 steps *is* the authorised size. | Would have been **high** (over-sizing breaches the 0.50% mandate) | **Refuted — no change made.** The floor is left byte-identical to the validated replay; the trap is recorded so it is not "fixed" later |

Also hardened in round 5, not a bug but a live-fidelity risk: `InpCommissionPerLotRT` is *inside*
`LossPerLot()` and therefore sizes every position, yet nothing surfaced it. On a $0-commission
broker the `7.0` default under-sizes all positions 6.5–12.1% (realised risk 0.439–0.468% instead
of 0.500%); on a broker charging more it over-sizes past the mandate. The EA now prints the value
in its first `[INIT]` line next to the sizing base and warns if it is negative.

Two new tests, both with mutation control so the assertions are provably load-bearing:
`test_ea_lot_normalisation.py` (9 sections; 3 mutants caught) and `test_ea_server_offset.py`
(6 sections; 4 mutants caught, including "no rounding at all" and "ceil instead of floor"). Both
caught bugs in themselves on first run — a hardcoded `should_warn` set that silently exempted
every negative offset, and a tie-break expectation for UTC−5:30 that assumed round-half-away
from zero where `MathFloor(x+0.5)` rounds half up — which is the reason they are committed.

After round 5 the equivalence proof still holds: `ea_emulator.py` reports ATR, signals and gates
**IDENTICAL**, `selftest_ea_dump.py` passes 9/9 mutations, and its layer-0 drift check caught the
`NormaliseLots` copy in `EA_SIGNAL_DUMP.mq5` going stale the moment the EA was patched — the copy
was then updated and the check re-passed.

**Cumulative: 25 bugs across five audits** (round 1 static, round 2 by emulation, round 3 by
re-reading against MQL5 time semantics, round 4 from the broker/balance question, round 5 from
the FXCC/myfxbook check). 24 fixed, 1 refuted and deliberately left alone. Compilation remains
unverified — there is no MetaEditor in this environment.

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
- FXCC: fxcc.com homepage and account terms (ECN XL / "ZERO": $0 commission, spreads from 0.0,
  up to 1:1000, no minimum deposit, no requotes, EAs and custom scripts allowed, free VPS,
  segregated client funds, 100% deposit bonus to $2,000); **live per-pair quotes from myfxbook's
  FXCC feed, broker id 5191** (`myfxbook.com/forex-broker-quotes/fxcc/5191`); FXEmpire's FXCC
  entity comparison (FX Central Clearing Ltd, CySEC 121/10, 1:30, segregated, ICF €20,000 vs
  Central Clearing Ltd, MISA Comoros BFX2024085, 1:1000, **not** segregated; margin call 100%,
  stop-out 50%, min volume 0.01, swap-free available; ECN XL live spreads EURUSD 0.0, GBPJPY
  1.5–1.9, XAUUSD 17–18¢ vs 33¢ industry average); FXScouts and daytrading.com FXCC reviews
  (EURUSD average 0.60 pips; EURGBP 0.3–0.6; gold 12–20¢).
- `myfxbook.com/forex-broker-spreads` live comparison table, retrieved 2026 — region-filtered;
  visible rows FOREX.com-Live 536 (EURGBP 0.2, NZDUSD 0.9, USDCAD 0.5, EURJPY 0.9, GBPJPY 1.7),
  tastyfx (0.9 / 1.8 / 1.3 / 2.1 / 2.5) and Oanda (1.1 / 2.4 / 1.9 / 2.6 / 3.0). Spread only —
  the page's Commissions toggle is separate, so the table is not comparable across account models.
- MQL5 `TimeCurrent()` / `TimeGMT()` semantics, and C-style integer division truncating toward
  zero (the round-5 bug 24 mechanism); IEEE-754 binary64 representation of `0.01` and the ULP
  residue in `n*step` (bug 23), measured in `test_ea_lot_normalisation.py`.
