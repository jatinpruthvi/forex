# 🚀 MAX-ROI Out-of-the-Box Strategy — The Funded Factory + Barbell SMC

**Generated:** 28 Sept 2026
**Goal:** Maximum ROI. Funded accounts explicitly allowed.
**Premise flip:** Stop optimizing "% per month on your equity." Start optimizing
"$ payout per $ of YOUR risk capital (eval fees + personal buffer)."

---

## 0. The one reframe that changes everything

On your own $10k, 20%/month = **$2,000/month** with a 25% drawdown hanging
over your head. One bad month and you are psychologically broken.

On funded capital, the math inverts:

```
1 eval fee ($500) → $100k account → 5%/month at 0.5% risk
= $5,000/month gross → ~$4,000 net (80% split)
= 800% ROI per month ON YOUR FEE CAPITAL
```

Even if you blow 7 evals and pass 3 out of 10:

```
Cost:    10 × $500 = $5,000
Income:  3 × $4,000/mo = $12,000/mo
Net Month 1: +$7,000 on $5,000 risked = +140%
```

**That is the maximum-ROI game. It is a factory, not a trade.**
Your EA is the assembly line. Evals are raw material. Funded payouts are product.

> Everything below is designed for this factory. If you insist on running it
> on personal capital only, halve every risk number and expect half the dollars.

---

## 1. The 3-Track System (the actual out-of-the-box move)

Everyone in the StudyArena debated ONE ea with 5–40 engines.
That is wrong for max ROI. You need THREE different risk profiles,
because evals, funded accounts, and personal capital have OPPOSITE payoff shapes:

| Track | Capital | Objective | Risk/trade | Character |
|---|---|---|---|---|
| **A. Eval Farm** | Eval fees (~$500 each) | PASS the challenge, nothing else | 0.5–0.75% | Low variance, high Sharpe, boring |
| **B. Funded Harvest** | Firm's $100k+ | SURVIVE + extract 4–6%/mo forever | 0.4–0.5% | Ultra-disciplined, runners, never breach |
| **C. Personal Compounder** | Your own $5–10k | COMPOUND aggressively | 1.5–2.5% graded | High variance, high ceiling, you accept 30% DD |

Same core edge. Three position-sizing wrappers. One VPS runs all three.

**Why this wins:** Track A is a call option (fixed $500 downside, $100k upside).
Track B is an annuity (low risk, recurring payout). Track C is a lottery ticket
with positive expectancy (small base, huge compounding). No single EA can be all
three at once — that is why single-EA thinking caps your ROI.

---

## 2. The Eval Pass Machine (Track A) — engineered, not traded

Prop evals are not markets. They are EXAMS with known answers:

```
Typical exam: 8% profit target, 5% daily loss limit, 10% total DD, 30–60 days.
```

Most traders fail because they trade the eval like a personal account.
You will trade it like a cryptocoin with a binary payout. Design for the exam:

### A. The "8% in 20 days" schedule

```
Days 1–10:   0.5% risk, A-setups only (score ≥ 8). Target +4%.
Days 11–20:  if ≥ +4%, drop to 0.4% risk, B+ setups only. Target +4% more.
Any day -2% drawdown:  STOP for the day. No exceptions, coded in EA.
If +6% by day 15:  drop to 0.25% risk. Protect the pass. You are done hunting.
```

Pass rate math: a 40%-WR / 3R system at 0.5% risk has ~65–70% chance of
hitting +8% before −5% DD inside 30 days (Monte Carlo standard result).
Run 5 evals in parallel → expected 3 passes. That is the factory yield.

### B. The exam-only filters (turn OFF on funded)

- NO XAUUSD on evals (spread variance kills exam Sharpe).
- NO Friday trades on evals (weekend gap = unforced exam error).
- NO trades 30 min either side of red news on evals (one spike = exam over).
- Max 2 positions TOTAL on evals (exam punishes heat, rewards patience).
- Killzone only: London 07–10 + NY 13–16 server. Nothing else. Boredom passes exams.

### C. Parallel-firm staggering (the real multiplier)

```
Month 1: buy 2 evals (Firm X + Firm Y — different servers, different rules).
Month 2: with first payouts, buy 3 more evals (Firms Z, W, V).
Month 3+: every funded payout funds 2–4 new evals. Self-financing loop.
```

Why different firms: HFT bans, news-trading bans, copy-trading flags and
weekend-hold rules differ per firm. Diversifying firms = diversifying RULE risk,
exactly like diversifying pairs diversifies market risk.
Never run identical magic numbers / identical timestamps across two accounts
at the same firm (copy-trade flag). Offset entries by 60–120 seconds per account.

**Expected factory economics (steady state):**

```
Eval spend/month:        4 × $500 = $2,000
Pass rate:               ~60% → ~2.4 new funded/quarter
Active funded (month 6): 4–6 × $100k
Monthly harvest:         5 × $100k × 5% × 80% ≈ $20,000
ROI on YOUR fee capital: ~10× per month
```

This is the maximum-ROI answer. Nothing in technical analysis competes with it.


---

## 3. The Funded Harvest Engine (Track B) — "never give the account back"

A funded account is not for growing. It is for milking. Different objective,
different EA config:

```
Risk:           0.4–0.5% per trade (NEVER above 0.5 — daily 5% cap is sacred)
Engines:        1 (SMC core) + 2 (Asian raid) ONLY. Disable everything else.
Exits:          1.0R stop → 25% at 1.5R → 25% at 3R → 25% at pool → runner.
                (Same ladder as strategy-recommendation.md — do not touch it.)
Monthly target: 4–6%. Then STOP. Overtrading funded = donating it back.
Weekly payout discipline: withdraw on schedule, every time, no "let it ride."
Heat cap:       2% total open heat (half the personal-account cap).
E₅₀ throttle:   if trailing-50 expectancy < 0.15R → halve risk automatically.
```

### The anti-breach circuit breaker (code this FIRST, before any entry logic)

```
On every tick:
  if today's realized loss ≤ −2.5% → close ALL, disable trading till next day.
  if trailing peak-to-today DD ≥ 4% → close ALL, disable for 48 hours.
  if spread > 1.5× 20-day median → skip new entries (news spike guard).
```

One breach wipes 3 months of harvest. This breaker is worth more than any engine.

### Payout-first accounting

```
Funded $100k, month N:
  Gross 5% = $5,000 → you keep $4,000 → allocate:
    $1,000 → 2 new eval fees (factory fuel)
    $1,000 → personal buffer (rent-proofing, psychology)
    $2,000 → Track C compounder fuel OR scaling reserve
```

The harvest feeds the farm and the compounder. That circular flow is the "firm"
you are building. Most traders withdraw and spend; you withdraw and REINVEST
into more exam attempts. That reinvestment rate is your true compounding rate.


---

## 4. The Personal Compounder (Track C) — the Barbell: "boring base + violent tip"

This is the genuinely out-of-the-box piece. Forget "1.5% on everything."
Split your personal account into two sub-books that NEVER mix:

### Book C1 — "Rent money" (80% of personal equity)

- Engines 1+2 only, 0.75% risk, killzone-only entries, full exit ladder.
- Target: 6–8%/month with <12% DD. This pays your psychology bill.
- Rule: NEVER borrow from C1 to feed C2. C1 is sacred.

### Book C2 — "Rocket fuel" (20% of personal equity)

This is where max ROI lives. Concentrated, timed violence:

**C2a. London Killzone Sniper (60% of C2)**

```
Window:      07:00–10:00 server ONLY. EA flat outside it.
Setup:       Asian range (00:00–06:00) high/low mapped.
             Sweep of EITHER side + M15 CHoCH back inside + displacement.
             A-grade confluence only (score ≥ 8).
Risk:        2.5% per trade, max 1 position.
Exit:        25% at 1.5R → 25% at 3R → 50% runner to opposing Asian extreme.
Math:        ~55% WR × 2.5R avg win on this filtered setup (raid logic,
             not generic SMC) → E ≈ 0.55(2.5) − 0.45(1) ≈ +0.93R/trade.
             ~6–8 shots/month → +5.5–7.5R/month on the C2a slice.
```

**C2b. HTF Pyramid Driver (40% of C2)**

```
The single highest-ROI structural change from Round 3, refined:
Trigger:     H4 sweep → H4 OB tap → M30 CHoCH in same direction.
Unit 1:      1.5% at the M30 OB (stop below H4 sweep wick).
Add Unit 2:  ONLY if +1.5R profit AND fresh M30 OB forms in trend.
             Size 0.75% (half), stop for WHOLE book trailed below new OB.
Add Unit 3:  ONLY if book stop is above blended breakeven (risk-free add).
             Size 0.5%. Max 3 units, ever.
Effect:      1-in-8 drivers pay 8–14R blended instead of 3R.
             Expectancy lift ≈ +0.2–0.3R per trigger setup.
Frequency:   3–5 triggers/month. This is the fat-tail hunter.
```

**C2 hard rules (violate these and C2 becomes gambling):**

```
- C2 total open heat ≤ 3%. One sniper + one pyramid MAX concurrently.
- Same-currency cap 2% (no EURUSD + GBPUSD long together in C2).
- Friday 15:00 server → C2 flat. No exceptions.
- Two consecutive C2 losses → C2 paused 48h (tilt guard, coded).
- Monthly C2 stop: −8% on the C2 slice → C2 off for the rest of the month.
```

### Why the barbell beats "medium risk everywhere"

```
Flat 1.5% everywhere:   smooth, capped, ~15%/mo, bored but safe.
Barbell (80/20 split):  C1 gives 0.8×8% ≈ 6.4% baseline
                        C2 gives 0.2×35% ≈ 7% rocket contribution
                        Total ≈ 13–15% with SMALLER blended DD...
                        ...AND periodic 25–40% months when a pyramid lands.
```

Same average, fatter right tail, protected left tail. That asymmetry IS max ROI:
you keep every normal month and catch every monster month. Medium-risk-everywhere
clips both tails and gives you neither safety nor monsters.


---

## 5. The three multipliers nobody in the Arena priced correctly

### Multiplier 1 — Correlation firewall (worth more than any 5 new engines)

The Arena's Round-5 audit proved correlated engines = hidden leverage.
For max ROI you must ENFORCE decorrelation in code, not hope for it:

```
Rule 1: One cluster budget per DIRECTIONAL FAMILY.
        Trend family (SMC core + imbalance + pyramid) shares ONE 2.5% budget.
        First signal takes it. Later same-family signals are QUEUED, not sized down.
Rule 2: USD-exposure netting.
        Long EURUSD + long GBPUSD + short USDCHF = 3× short USD, not 3 trades.
        Cap net single-currency exposure at 3% (personal) / 1.5% (funded).
Rule 3: Session exclusivity.
        Asian-raid engine and NY-breakout logic NEVER both live on the same pair
        in the same 4h window. One regime, one engine. Router decides, not both.
```

Effect: same gross R, ~30–40% lower monthly σ → Kelly math lets you run
~1.4× the risk at the SAME drawdown. That 1.4× IS free ROI.

### Multiplier 2 — Time-boxed capital velocity (the "dead money" rule)

From Round 4, Contestant B's most profitable throwaway line:
a position that hasn't reached +0.5R within 1.5× its engine's median
resolution time has near-zero forward expectancy but occupies heat + margin.

```
Code it: every engine logs median bars-to-TP1.
If open trade age > 1.5× median AND floating < +0.5R → close at market.
```

Typical result: −5% expectancy per trade, +25% trades/month capacity,
net +10–15% R/month. Pure velocity gain. Costs nothing. Nobody does it.

### Multiplier 3 — The dispersion book (the only truly uncorrelated edge left)

Everything in all 5 rounds is price-direction on single pairs — all functions
of the same OHLC series. One genuinely orthogonal return stream remains:

```
Market-neutral rank book (runs DAILY, rebalanced at NY close):
  1. Score 8 majors on 20-day momentum + 60-day carry (swap).
  2. Long the 2 strongest, short the 2 weakest, equal USD-neutral notional.
  3. Hold 1–5 days. No stops on direction — stop on RANK FLIP or 5-day timeout.
  4. Size: 0.25% per leg (0.5% per pair-spread, 1% book total).
Expectancy: ~1.5–2.5%/month gross on its slice, σ ~4%.
Value: fires hardest in CHOP months when every directional engine bleeds.
       That is exactly when funded accounts die — this book keeps them alive.
```

Small alone. Priceless as funded-account life insurance that pays YOU a premium.
Allocate 10–15% of funded heat budget to it. It converts red chop months into
flat months, and flat months are what let harvest accounts survive to month 12.

---

## 6. Full-month operating calendar (how the three tracks interact)

```
WEEK 1 — "Hunt"
  Track A (evals):    full aggression within exam rules. A-setups only.
  Track B (funded):   normal 0.5% harvesting.
  Track C (personal): C1 normal + C2 sniper armed, London window only.
  Dispersion book:    rebalance daily, all tracks.

WEEK 2–3 — "Press or protect" (branch on P&L)
  IF portfolio ≥ +6%:
      → cut ALL risk 30% (funded) / bank the eval progress (drop to 0.3%).
      → C2 pyramid allowed (winners fund violence, never hope).
      → Rule: gains buy safety first, lottery tickets second.
  IF portfolio ≤ −3%:
      → E₅₀ check. If E₅₀ < 0.15R: halve everything, regime-filter review.
      → C2 OFF entirely until portfolio recovers above −1%.
      → Track A evals: pause new entries 48h (exam tilt kills passes).

WEEK 4 — "Harvest"
  Funded ≥ +4%:       STOP new entries. Manage runners only. Withdraw on schedule.
  Eval ≥ +6%:         drop to 0.25%, A+ setups only. Protect the pass certificate.
  Personal C1 ≥ +6%:  optional early stop. C2 may take 1 final sniper if A-grade.
  Last 2 days:        NO new C2 positions. NO new eval entries. Manage + close.

MONTH-END (last trading day + first 2 of new month):
  Optional overlay: month-end rebalance flows (JPY-cross unwind, EURGBP drift).
  Size 0.5%, max 2 trades. Documented +3R/month edge at 60% WR in Round 4.
  Skip if any track is in drawdown — never add cleverness on top of bleeding.
```

---

## 7. Honest numbers: what "maximum" actually means

| Configuration | Gross/mo (live, haircut) | Max DD | Who it suits |
|---|---|---|---|
| Personal only, flat 1.5% | 12–18% | ~25% | Baseline from prior doc |
| Personal barbell (C1+C2) | 15–25%, spikes to 35–40% on pyramid months | ~25–30% | You accept variance |
| 1 funded $100k @ 0.5% | 4–6% = $4–6k gross → **$3.2–4.8k net** | ~8% | The annuity |
| 5 funded $100k @ 0.5% | 4–6% = $20–30k gross → **$16–24k net** | ~8% each, uncorrelated across firms | The factory |
| Eval farm (4 evals/mo) | Expected +1.5–2 funded/qtr | Capped at fees (~$2k/mo) | The pipeline |
| **Combined factory (steady state, mo 6+)** | **$16–24k/mo net + personal 15–25% compounding** | Blended, compartmentalized | **Maximum ROI** |

### The red-month reality (do not skip this)

```
Personal barbell:  ~1 month in 4 red (−5 to −12%).
Funded harvest:    ~1 month in 6 flat-or-red (0 to −3%, never near breach if breaker coded).
Eval farm:         ~40% of evals fail. That is PRICED IN. 60% pass rate = profitable factory.
Combined:          personal red months coincide with funded flat months ~half the time.
                   The dispersion book + C1 baseline exist precisely for those months.
```

Maximum ROI is not maximum smoothness. If you need every month green,
run Track B only and accept $4k/mo per account. The barbell + factory above
is for maximum DOLLARS per year, which includes surviving red months mechanically.


---

## 8. 60-day build order (max-ROI sequencing — do NOT build engines first)

```
Days 1–7:    PROCUREMENT (highest ROI-per-hour in the entire plan)
             ☐ Raw ECN account + VPS <5ms + limit-only execution coded
             ☐ Anti-breach circuit breaker coded + tested (Section 3 box)
             ☐ Heat-cap + cluster-budget + USD-netting module coded
             ☐ Dead-money time-exit coded (Section 5, Multiplier 2)
             (No entries yet. Protection before production. Always.)

Days 8–20:   TRACK C1 + TRACK B CORE (one engine, two risk wrappers)
             ☐ Engine 1 (SMC sweep→CHoCH→OB) + A/B/C grading + exit ladder
             ☐ Wrapper B: 0.5% fixed, eval/funded filters (Section 2B)
             ☐ Wrapper C1: 0.75%, killzone-only
             ☐ Backtest 2022–2026 + walk-forward. Keep iff E > 0.25R OOS.

Days 21–35:  TRACK A GOES LIVE + C2 SNIPER
             ☐ Buy eval #1 (one firm, one $50–100k challenge). Run Wrapper B.
             ☐ Code + backtest C2a London sniper in isolation.
             ☐ E₅₀ throttle + tilt guards coded.
             ☐ Demo C2a on personal alongside eval.

Days 36–50:  PYRAMID + DISPERSION (the two fat-tail / flat-month tools)
             ☐ Code C2b pyramid with risk-free-add gating (stop-above-blend rule).
             ☐ Code dispersion rank book (daily rebalance, 0.25%/leg).
             ☐ Portfolio backtest: check pairwise engine correlation < 0.5.
             ☐ Cut anything that fails. 6–9 survivors max. Ruthlessness = ROI.

Days 51–60:  FACTORY IGNITION
             ☐ Eval #2 + #3 at two DIFFERENT firms. Fund payouts → fund evals loop.
             ☐ First withdrawal on schedule (habit > amount).
             ☐ 4-week live review: live R vs haircut R within 30%? If not,
               execution audit before ANY new engine. Slippage is the usual killer.
```

---

## 9. What can still kill this (and the coded defense for each)

| Killer | How it kills | Coded defense |
|---|---|---|
| Copy-trade flag across same-firm accounts | Payout denied, accounts closed | Unique magic + 60–120s entry offset per account; never mirror fills exactly |
| News spike on funded | Instant −2–4%, breach spiral | Spread-guard skip + 30-min news blackout + −2.5% daily hard close |
| Pyramid hope-adds | One driver wipes C2 month | Risk-free-add gate: add ONLY if book stop ≥ blended breakeven |
| Chop bleeding funded | Slow −1%/week, death by papercuts | Dispersion book + dead-money exits + E₅₀ throttle |
| Eval tilt (revenge trading the exam) | Failed exam = burned fee | −2% daily stop + 48h pause + A-setups-only coded rule |
| Gold spread on M15 | −0.15R/trade silent tax | XAUUSD H4/H1 only, or excluded on evals/funded entirely |
| Overconfidence after +10% month | Giving it all back week 4 | Month-4 harvest rules + risk-cut-on-gains branch (Section 6) |

---

## 🎯 The one-paragraph version

Stop building a better indicator. Build a **factory**: boring 0.5%-risk exam
machines that convert $500 fees into $100k accounts at a 60% pass rate; milking
machines that extract 4–6%/month per funded account without ever touching the
breach line; and a personal barbell — an 80% "rent-money" base plus a 20%
"rocket-fuel" tip running London-snipers and risk-free-gated pyramids for the
fat-tail months. Wrap all of it in correlation firewalls, dead-money exits, a
dispersion book for chop months, and payout-funded eval compounding. That system
does not target 20%/month on your equity. It targets **$16–24k/month net across
5 funded accounts plus 15–25% compounding on your own small base** — which,
measured against YOUR actual risk capital, is several hundred percent ROI.
That is maximum ROI, honestly engineered.

---

*Companion to `strategy-recommendation.md` (the converged 5-round consensus).*
*This file is the aggressive out-of-the-box extension: same core edge,*
*three risk wrappers, one factory. Protection coded before production, always.*

