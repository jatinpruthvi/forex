# Running FIVE_M5_EXHAUST on a personal live account

**The question:** can this make roughly 10% a month on my own money?

**The answer:** yes on held-out data — **+15.0% a month modelled, with an 8.3% maximum
drawdown** — and the honest caveats are bigger than the number. Roughly **a quarter of
months are negative** (24% on the 25-month TEST window at fixed sizing, 28.6% across the
full four-year frontier), the worst month in the TEST window is **−10.0%**, the longest
losing streak is **three consecutive months**, and every one of those figures comes from a
backtest whose cost model is an *assumption about spreads* rather than a record of your
fills. Read "What would make this fail" before you read anything else.

**One warning about the numbers in this document.** Several configurations are in
circulation across this repository's analyses, and they differ by roughly 2× — 8 pairs
versus 7, commission 7.0 versus 4.50, $2,500 versus $2,000, prop caps on versus off. Every
table below states which one it is. **Do not compare a row from one configuration against a
row from another.**

This document is the personal-account counterpart to `findings_broker_and_balance.md`
(broker choice and minimum balance) and `MQL5/Experts/FIVE_M5_EXHAUST/README.md` (the EA
itself). It exists because **a prop account and a personal account are different
optimisation problems**, and the prop numbers do not transfer.

---

## 1. Why the prop-firm numbers cannot answer this

| | funded / prop account | personal account |
|---|---|---|
| objective | reach +10% before a 5% daily loss or the static floor | long-run compounded growth, subject to a drawdown you can tolerate |
| clock | 27 days minimum, phase limits | none |
| risk cap | 0.75%/trade **imposed by the firm's rules** | only by variance and ruin mathematics |
| concurrent positions | capped (2 in the firm's rule set) | uncapped — the EA ships at 99 |
| trades per day | capped (5) | uncapped — the EA ships at 99 |
| swap | irrelevant over 27 days | **material over years** |

Two of those rows are worth more than the rest combined.

**Removing the caps roughly doubles the monthly rate.** The EA's shipped gates are
`InpMaxConcurrent=99` and `InpMaxTradesPerDay=99` — take every signal. The prop replay
caps them at 2 and 5. `validation/speed_lab/personal_account_analysis.py` still defaults
to the *prop* caps (a bug recorded as #4 in `findings_broker_and_balance.md`), so **its
raw output understates a personal account by about half**. Its risk frontier is reproduced
below with that caveat attached, because the *shape* of the frontier is still the useful
part. The corrected personal-account figures come from `broker_cost_and_balance.py` and
`fusion_markets_defaults.py`, which run the shipped gates.

**Swap is a real cost over years and a rounding error over 27 days.** The strategy holds
a median of 3.5 hours but a mean of 21.0 hours, because the 96-hour timeout lets losers
run: **0.772 rollovers per trade**, 25.3% of trades cross at least one night, 15.7% cross
two or more.

---

## 2. The headline configuration

Everything below is the **held-out TEST window, 2024-09-11 → 2026-09-11 (25 months)**,
which the strategy was never tuned on. TRAIN is 2022-09-11 → 2024-09-11.

| parameter | value |
|---|---|
| strategy | M5 long-only exhaustion fade: body > 4×ATR(14), enter next bar open |
| stop | 2×ATR, floored at 1×ATR by `InpMinStopAtrMultiple` |
| target | +10R |
| timeout | 96 hours |
| universe | **7 FX pairs** — EURGBP, AUDUSD, NZDUSD, USDCAD, USDCHF, EURJPY, GBPJPY |
| risk | 0.50% of the **initial** balance, fixed sizing |
| gates | every signal (99/99), −3R daily breaker, no entries after Fri 21:00 server |
| balance | $2,000 |
| broker | Fusion Markets **Zero**, `InpCommissionPerLotRT = 4.50` |
| server | UTC+3 |

**Result: 1,111 trades, E_net +0.704R per trade, +15.01%/month, worst month −10.01%,
maximum drawdown 8.3%, total +375% over 25 months.**

Cost per trade is `spread × pip_value + commission`, with spread modelled at **0.55× the
pair's standard deviation**. The cost model measured on the *eight-pair* universe at the
shipped 7.00 commission is: round-turn cost **22.8% of 1R**, gross expectancy **+0.765R**,
net **+0.537R**. That is a different universe and a different commission input from the
headline row above, so **+0.765R and +0.704R are not a gross/net pair** — costs consume
about 30% of the gross edge either way, which is the whole margin of safety, and it is why
a wide-spread broker is not a rounding error here. See §8 for the spread sensitivity.

### Why seven pairs and not eight

`InpSymbols` ships with eight symbols including **XAUUSD**. Drop it:

* Gold's held-out TEST expectancy is **−0.219R** — it loses money out of sample.
* It has **no break-even spread**. Its cost is dominated by a wide quote, and no realistic
  spread leaves it positive.
* It raises the minimum balance **tenfold**, from $1,565 to $16,101, because one gold trade
  needs a much larger risk budget to reach the 0.01-lot floor (§4).

### Why `InpCommissionPerLotRT` must be set, not left alone

This input is **not a reporting field**. `LossPerLot()` returns
`stop_distance × pip_value + commission`, and `lots = risk_cash / LossPerLot()`. So an
overstated commission **understates the lot size on every single trade**. Leaving it at
the shipped 7.0 on a broker that charges 4.50:

| | E_net | %/month | worst month | maxDD |
|---|---|---|---|---|
| left at the 7.00 default | +0.672R | +14.33% | −10.34% | 8.8% |
| set correctly to 4.50 | +0.704R | **+15.01%** | −10.01% | **8.3%** |

**613 of 1,111 trades (55.2%) are sized too small** at $2,000, mean position 0.1580 lots
instead of 0.1684 (−6.2%). It costs about 0.7 points of monthly return and half a point of
drawdown — and it is invisible, because nothing looks broken.

---

## 3. Fixed or compounded sizing

| mode | input | meaning |
|---|---|---|
| **fixed** (shipped) | `InpRiskOnInitialBase=true` | risk 0.50% of the **starting** balance, forever. Linear growth in dollars |
| **compounded** | `InpRiskOnInitialBase=false` | risk 0.50% of the **live** balance. Geometric growth; drawdown measured against the high-water mark |

These two rows are **not measured on the headline configuration**, because the fixed-vs-
compounded comparison in `broker_cost_and_balance.py` was run before the seven-pair and
4.50-commission decisions were made. They are stated with their own configuration attached
so they are not confused with §2:

> **25 months of held-out TEST, shipped gates (every signal, −3R daily breaker), 0.50%
> risk, 8-pair universe including XAUUSD, commission 7.00, $2,500 balance:**
>
> | mode | mean/mo | median | worst mo | maxDD | final | total |
> |---|---|---|---|---|---|---|
> | fixed | +12.60% | +10.04% | −11.11% | 11.7% | $10,378 | +315% |
> | compounded | +13.28% arithmetic / **+11.94% geometric on current equity** | +8.60% | −11.89% | **22.6%** | $41,978 | +1579% |
>
> 24% of months negative on fixed sizing, 28% on compounded.

The headline seven-pair / 4.50-commission / $2,000 configuration (§2) was measured on
**fixed** sizing only: **+15.01%/month, 8.3% maxDD**.

Over the full four years at 0.50% risk (prop caps, 8-pair universe): fixed **+367%** with a
10.9% max drawdown; compounded **+2,807%** with a **27.8%** one.

Three traps here:

* **Do not average the fixed-mode monthly percentages and call it a growth rate.** On fixed
  sizing the monthly figure is a return on the *initial* balance, so as the account grows it
  becomes a progressively smaller return on current equity — $2,500 → $10,378 over 25 months
  is +315% total, which is about **5.9%/month compounded**, not 12.6%. Quoting the fixed
  column as a growth rate overstates you badly.
* **The compounded geometric rate is *lower* than the fixed arithmetic rate** (11.94% vs
  12.60%) even though the final balance is four times higher. That is variance drag, and it
  is why the drawdown nearly doubles — positions are largest exactly when the account is at
  its peak.
* **A ~10%/month target is reachable on held-out data under both modes**, but under fixed
  sizing it is 10% *of the starting balance*, which decays as a rate on current equity. If
  you want a durable 10%/month *growth rate*, that is compounded sizing, and the price is a
  drawdown around 22–28% instead of 8–12%.

Start on fixed sizing. It is what every published figure in this document was measured on,
and the EA now warns if you change it (§7).

---

## 4. Minimum balance: three floors, only one of which binds

### (a) Lot granularity — the binding constraint

The EA computes `lots = floor(risk_cash / loss_per_lot / step) × step` and **skips the
trade entirely below 0.01 lots**. So a trade is takeable only when

```
balance ≥ step × loss_per_lot / risk_pct  =  0.01 × loss_per_lot / 0.005  =  2 × loss_per_lot
```

The worst trade in the TEST window on the seven FX pairs costs **$782 per lot**, giving a
knife-edge floor of **$1,565**. Below that the EA silently forgoes the most expensive —
and therefore widest-stopped — signals, so realised risk drifts under 0.50% and results
stop matching anything published.

**Recommended: $2,000.** That is 28% above the knife-edge, skips **0.0%** of signals, and
delivers a realised risk of **0.475%** (the 0.01-lot step cannot express 0.50% exactly).
Including XAUUSD raises the floor to **$16,101** — one more reason to drop gold.

### (b) Margin — decided by leverage, not by balance

Margin use is **nearly independent of balance**, because lot size scales with balance. The
stream reaches 9 concurrent positions, which at **1:500 peaks around 16% of balance** and
at 1:100 around **82%** — a margin call arrives long before the strategy's own drawdown
does. This is why leverage matters more than deposit size: **1:500 is a requirement, not
a preference.**

### (c) Drawdown tolerance

* **Headline config** (7 FX pairs, commission 4.50, $2,000, fixed sizing, 25-month TEST):
  max drawdown **8.3%**, worst month **−10.0%**.
* **8-pair config** (commission 7.0, $2,500, TEST, shipped gates): **11.7%** maxDD fixed,
  **22.6%** compounded; **24%** of months negative fixed, **28%** compounded.
* **Four-year frontier** (prop caps): **28.6%** of months negative at every risk level,
  longest losing streak **3 consecutive months**.

If a 10% drawdown would make you intervene manually, this strategy is not sized for you at
0.50% — and manual intervention is exactly what the frozen-parameter check in §7 is there
to catch. Plan for **three bad months in a row** as a normal event, not a signal that
something has broken.

---

## 5. The risk frontier

From `personal_account_analysis.py` over **all four years** (49 months). **These rows still
carry the prop-firm caps** (≤2 concurrent, ≤5 trades/day), so treat them as the *shape* of
the frontier, not as achievable rates — the shipped gates roughly double the monthly
column (§1). The relative cost of each risk level is unaffected.

| risk % | 4y total | /month | median mo | worst mo | best mo | losing mo | maxDD |
|---|---|---|---|---|---|---|---|
| 0.25 | 183.8% | 3.75% | 2.70% | −4.31% | 16.30% | 28.6% | 6.8% |
| 0.36 | 266.1% | 5.43% | 3.92% | −6.21% | 23.48% | 28.6% | 8.0% |
| **0.50** | **367.1%** | **7.49%** | **5.40%** | **−8.62%** | **32.61%** | **28.6%** | **10.9%** |
| 0.75 | 547.6% | 11.18% | 8.10% | −12.93% | 48.91% | 28.6% | 16.4% |
| 1.00 | 727.1% | 14.84% | 10.80% | −17.25% | 65.22% | 28.6% | 21.8% |
| 1.50 | 1098.8% | 22.43% | 16.21% | −25.87% | 97.83% | 28.6% | 32.7% |
| 2.00 | 1463.1% | 29.86% | 21.61% | −34.49% | 130.43% | 28.6% | 43.7% |

Note the column that does not move: **28.6% of months are negative at every risk level.**
Raising risk scales the wins and the losses together; it does not improve the hit rate.
There is no risk setting at which this strategy stops having bad months.

**0.50% is the validated setting and the EA now refuses to initialise above it** (§7).

---

## 6. Swap: the cost the prop run could ignore

Swap charged in R per rollover, applied to every position held across a server midnight
(fixed sizing, 0.50%, prop caps — again, shape not level):

| swap R/night | E_net R/trade | 4y total | /month | maxDD |
|---|---|---|---|---|
| 0.00 | 0.3573 | 367.1% | 7.49% | 10.9% |
| 0.02 | 0.3418 | 355.9% | 7.26% | 11.1% |
| 0.05 | 0.3187 | 340.2% | 6.94% | 11.6% |
| 0.10 | 0.2801 | 304.9% | 6.22% | 12.6% |
| 0.20 | 0.2029 | 244.5% | 4.99% | 13.7% |
| 0.30 | 0.1258 | 182.6% | 3.73% | 17.2% |

At 0.10R a night — a realistic long swap on these pairs — swap costs roughly **1.3 points
of monthly return**.

The same sweep on the **headline configuration** (7 FX pairs, commission 4.50, $2,000,
fixed sizing, TEST) — run on Fusion's **winter GMT+2 clock**, which is the conservative
case because it crosses 28% more rollovers than the validated +3 assumption:

| account | commission RT | swap/night | E_net | %/mo | maxDD |
|---|---|---|---|---|---|
| Zero, no swap charged | $4.50 | 0.00R | +0.704R | +15.64% | 6.7% |
| Zero | $4.50 | 0.05R | +0.704R | +14.72% | 6.9% |
| Zero | $4.50 | 0.10R | +0.704R | +13.78% | 7.2% |
| Zero | $4.50 | 0.20R | +0.704R | +12.07% | 8.4% |
| Zero | $4.50 | 0.30R | +0.704R | +9.76% | 11.3% |
| **Swap-Free (+1.4p markup)** | $4.50 | 0.00R | **+0.467R** | **+10.89%** | **9.4%** |

**The two tables above account for swap differently, and that is a reporting difference, not
a disagreement about the strategy.** `personal_account_analysis.py` folds swap into each
trade's realised R, so E_net falls as swap rises. `fusion_markets_defaults.py` reports E_net
*excluding* swap and lets the charge show up in the monthly and drawdown columns instead.
Read each table against its own convention; do not compare E_net across them.

**Do not take the swap-free account.** Fusion's Islamic/swap-free variant replaces swap
with a spread markup quoted from **1.4 pips**, and that markup costs **0.237R of expectancy
per trade** (+0.704R → +0.467R) — more than four nights of realistic swap. The markup only
pays if long swap exceeds about **0.25R per night**, far beyond realistic long swap on these
pairs. Take Zero. `InpSwapCostGatePassed` still requires you to read Fusion's actual swap
table for all seven symbols before enabling: the script models the cost, it does not quote it.

### The server clock, and why it is not a performance variable

Fusion's server is New York aligned and observes DST: **GMT+3 in summer, GMT+2 in winter**.
The EA ships assuming a fixed **+3**. Measured across UTC+0 to UTC+4:

| server | trades | E_net | %/mo | worst mo | maxDD | total | rollovers | nights/trade |
|---|---|---|---|---|---|---|---|---|
| UTC+3 | 1,111 | +0.704R | +15.01% | −10.01% | 8.3% | +375% | 890 | 0.801 |
| UTC+2 | 1,111 | +0.704R | +15.64% | −10.01% | 6.7% | +391% | 1,141 | 1.027 |
| UTC+1 | 1,111 | +0.704R | +14.11% | −10.01% | 8.7% | +353% | 1,245 | 1.121 |
| UTC+0 | 1,111 | +0.704R | +14.34% | −10.54% | 8.6% | +359% | 1,249 | 1.124 |
| UTC+4 | 1,111 | +0.704R | +15.59% | −10.54% | 10.8% | +390% | 844 | 0.760 |

**E_net is +0.704R at every offset** — the signal and exit logic is offset-invariant. What
moves is the server-day boundary, which drives the Friday block and the −3R breaker, and
therefore how many nights positions are held across: **890 rollovers at +3 versus 1,141 at
+2 (+28.2%)**, i.e. 0.801 versus 1.027 nights per trade. In other words **the +3 assumption
flatters the swap line** — at +2 you pay swap on roughly four more months a year on this
clock. Leave `InpExpectedServerUtcOffsetHours=3` and expect an informational `[WARN]` from
November to March when Fusion drops to +2; the warning is correct and does not mean anything
is broken.

---

## 7. What the EA verifies for you, and what it cannot

Seven audits found **28 bugs; 27 fixed, 1 refuted and deliberately left alone**. Full list
in `findings_broker_and_balance.md`. The ones that bear on a personal account:

* **Frozen parameters are now actually checked** (bug #28, round 7). `InpValidationReleaseId`
  used to be a string compared against a string, so typing it in made `OnInit` print
  *"release ID matches the validated configuration"* — a claim about a **label**, not about
  the numbers in force. `CheckFrozenParameters()` now runs in `OnInit` and **halts** if the
  trigger, ATR period, stop multiples, target R, hold hours or timeframe have been retuned,
  or if `InpRiskPercent` is **above 0.50%**. It **warns** — naming the consequence — on risk
  below 0.50%, a commission input that no longer matches your broker, universe changes,
  position/trade caps, compounding, Friday-filter changes, and a sizing-base override larger
  than your actual balance. Every figure in this document is conditional on those values.
* **Netting accounts are detected and refused.** On a netting account a second `Buy()` on a
  symbol merges into the open position and **overwrites its SL and TP**, destroying the
  first trade's stop and target. 13.8% of TEST signals stack on an already-open symbol.
  **You need a hedging account** — Fusion Markets supports hedging, so this is satisfied.
* **Broker symbol suffixes resolve, or the EA halts.** `EURGBP.m`, `EURGBPm`, `EURGBP.pro`,
  `EURGBP-ECN` are all handled; `USD` can never resolve onto `USDCAD`. If none resolve the
  EA halts rather than trading a subset while looking healthy.
* **Volumes are normalised to the broker's step's own decimal count**, so a 1-ULP float
  residue (0.35 stored as 0.35000000000000003) cannot produce
  `TRADE_RETCODE_INVALID_VOLUME` on roughly 1 signal in 43.
* **Order submission defaults to `false`.** The EA runs a dry run until you set
  `InpEnableOrderSubmission=true` explicitly, and every gate is a separate boolean that also
  defaults to false. `InpAuthorizedLogin` should be set to your own login.
* **Closing is never gated.** A halt always flattens and reports the true tally
  (`N closed, M FAILED`); it cannot announce a flatten it did not perform.

What the EA **cannot** verify: that your broker's live spread matches the model, that your
fills happen at the next bar's open, or that the edge persists out of sample. For the first
two there is an on-broker verification chain — `MQL5/Scripts/EA_SIGNAL_DUMP.mq5` dumps the
signals your broker's own feed produces, and `validation/speed_lab/compare_ea_dump.py`
compares them against the repo's backtest, with `selftest_ea_dump.py` proving the comparator
can fail (9/9 deliberate mutations caught).

---

## 8. What would make this fail

In rough order of likelihood:

1. **The spread assumption is too optimistic.** Costs are modelled at 0.55× standard
   deviation plus commission. Round-turn cost is **22.8% of 1R** and gross expectancy is
   only +0.765R, so the strategy is cost-sensitive: the break-even ceilings on TEST are
   **EURGBP 4.14, NZDUSD 2.51, USDCAD 5.47, EURJPY 5.99, GBPJPY 12.64 pips**. If your
   live average exceeds those, that pair has no edge. **Measure them with the dump script
   before you size up.** Measured sensitivity, on the 8-pair / 7.00-commission config, as a
   multiplier on every pair's validated raw spread:

   | × validated spread | E_net | vs base | mean %/mo | median %/mo | worst mo | maxDD |
   |---|---|---|---|---|---|---|
   | 0.50× | +0.5976 | +11% | +14.04% | +13.20% | −10.44% | 10.3% |
   | 0.75× | +0.5673 | +6% | +13.23% | +10.76% | −10.78% | 11.2% |
   | **1.00×** | **+0.5370** | **—** | **+12.60%** | **+10.04%** | **−11.11%** | **11.7%** |
   | 1.25× | +0.5068 | −6% | +12.00% | +9.33% | −11.44% | 12.6% |
   | 1.50× | +0.4765 | −11% | +11.34% | +8.62% | −11.78% | 13.6% |
   | 2.00× | +0.4159 | −23% | +10.21% | +7.19% | −12.44% | 15.7% |
   | 3.00× | +0.2948 | −45% | +7.53% | +4.62% | −13.78% | 17.9% |
   | 5.00× | +0.0526 | −90% | +2.30% | −0.32% | −17.65% | 37.0% |

   The edge degrades gradually rather than falling off a cliff, which is reassuring — but
   **doubling your spreads costs 23% of the expectancy**, and NZDUSD has only **2.9×**
   headroom before it turns unprofitable at all.
2. **43.8% of entries land in the UTC 21:00–00:59 rollover/close window**, and **30.7% in
   the single hour UTC 21:00**, where spreads widen to roughly 3× the session average on
   some pairs. This is where the model is weakest, and it is not a corner case. It is also
   why the server clock matters for swap (§6): with a +3 server the day boundary sits exactly
   on that hour, so those trades start a fresh server day and cross no rollover at all.
3. **Regime change.** The TEST window is one 25-month sample. Expectancy is +0.704R per
   trade across 1,111 trades; a persistent drop to +0.3R halves your monthly rate without
   anything looking broken.
4. **Balance too small.** Under $1,565 the EA starts skipping the widest-stopped signals,
   realised risk falls under 0.50%, and results stop matching this document.
5. **A VPS that is not actually 24/5.** The 96-hour timeout and the −3R daily breaker both
   depend on the EA running continuously. Fusion's free VPS needs 20 lots/month; at $2,000
   this strategy trades roughly 2–3 lots/month, so **you must pay for a VPS**.
6. **Manual intervention.** Disabling order submission to "pause" the EA used to leave
   positions unmanaged (bug #27). It does not now, but overriding the frozen parameters
   will halt it — deliberately.
7. **MQL5 compilation is unverified.** There is no MetaEditor in this environment. The EA
   has been checked by brace/paren balance, by a faithful Python port of every function, and
   by an emulator that reproduces **3,290 = 3,290 trades IDENTICAL** to the backtest — but
   **compile it in MetaEditor before you trust it.**

---

## 9. Deployment checklist

1. Open a **Fusion Markets Zero** account in **USD**, on the **VFSC (Vanuatu, 40256) or FSA
   (Seychelles)** entity — **not** the ASIC retail entity, which is 1:30 and will stop you
   out at the margin peak. **Not** the swap-free variant.
2. Deposit **$2,000**. Confirm **hedging** is enabled and leverage is **1:500**.
3. Rent a **paid VPS**; install MT5; attach the EA to any chart (it drives its own symbols
   via a 1-second timer, so the chart symbol does not matter).
4. Set exactly three inputs: `InpCommissionPerLotRT = 4.50`, `InpSymbols` **without
   XAUUSD**, `InpValidationReleaseId = "M5_EXHAUST_2026_09"`. Leave
   `InpExpectedAccountCurrency = "USD"`, `InpExpectedServerUtcOffsetHours = 3`,
   `InpMaxConcurrent = 99`, `InpSizingBaseOverride = 0.0`.
5. Set `InpAuthorizedLogin` to your login. Leave `InpEnableOrderSubmission = false`.
6. Run `EA_SIGNAL_DUMP.mq5` in the **live terminal** (not the Strategy Tester, where
   `TimeGMT() == TimeCurrent()` by design) with `InpBarsToDump = 120000`, and diff it
   against the repo with `compare_ea_dump.py`.
7. Watch the dry run for at least a week. Confirm the `[INIT]` line reports no frozen-parameter
   drift, that all seven symbols resolved, and that the first closed gate is what you expect.
8. Only then set `InpEnableOrderSubmission = true`.

---

## 10. A note on where you are resident

This document assumes the account holder is **not resident in India**. For an Indian
resident, trading leveraged FX through an offshore broker is a different question from the
one asked here — the RBI's Alert List and FEMA s.13 apply to the *person*, not to the EA,
and no setting in this repository changes that. It is not a technical blocker and it is not
a reason the strategy would underperform; it is a matter for the account holder and their
own adviser. Details and sources are in `findings_broker_and_balance.md`.

---

## Reproducing every number here

All tools are stdlib-only Python 3 (numpy is used for research but nothing shipped depends
on it).

| script | what it produces |
|---|---|
| `validation/speed_lab/personal_account_analysis.py` | risk frontier, hold-time and rollover distribution, swap sensitivity, month-by-month table (**prop caps still on by default** — see §1) |
| `validation/speed_lab/broker_cost_and_balance.py` | minimum-balance floors, margin by leverage, fixed vs compounded on TEST at shipped gates, per-broker cost comparison |
| `validation/speed_lab/fusion_markets_defaults.py` | every EA input checked against Fusion Zero; commission, server-offset and swap-free sensitivity |
| `validation/speed_lab/margin_and_swap_exposure.py` | margin peak and swap exposure by concurrency |
| `validation/speed_lab/verify_final_config.py` | the frozen signal/exit/cost model every other script imports |
| `validation/speed_lab/ea_emulator.py` | equivalence proof: emulator vs backtest, **3,290 = 3,290 IDENTICAL** |
| `validation/speed_lab/selftest_ea_dump.py` | synthesises an `EA_SIGNAL_DUMP` file and requires the comparator to pass on it and **fail** on 9 corrupted variants |
| `validation/speed_lab/test_ea_frozen_parameters.py` | the round-7 frozen-parameter check: 18 assertions, 3 mutants caught |
| `validation/speed_lab/test_ea_lot_normalisation.py` | volume rounding: 16 assertions, 3 mutants caught |
| `validation/speed_lab/test_ea_symbol_resolution.py` | broker suffixes: 39 assertions |
| `validation/speed_lab/test_ea_server_offset.py` | offset rounding, both hemispheres: 4 mutants caught |

Data: `validation/HistoryData/` — M5 four years for 11 pairs plus M1 two years.
TRAIN 2022-09-11 → 2024-09-11, TEST 2024-09-11 → 2026-09-11.

**Nothing here is investment advice, and past backtest performance does not indicate future
results. The +15.01%/month is a modelled figure from 25 months of held-out data under a
specific cost assumption — not a forecast, and not a promise.**
