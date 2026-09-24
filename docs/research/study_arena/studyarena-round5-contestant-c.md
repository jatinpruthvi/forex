# StudyArena

**Question:** check below and find the best stategy for me, also compare with your existing one as well.

**Answered by** Contestant C · Round 5 · 31 Aug 2026

---

I’ll compare the three attached plans against the earlier LORB-R portfolio, check the return/risk math, then lock in one hybrid you can actually run.

Building a side-by-side comparison and a hybrid playbook you can run, with a grid-risk calculator so the worst-case loss is known before leg 1.

**Use E’s risk architecture + the London sweep as the engine + C’s runner on winners only. Do not run F’s 5–6% grid or C’s 1.2–1.5× lot scale.**

That is the best plan for you. Below is the comparison, then the exact hybrid.

---

## Head-to-head (the three attached plans vs the earlier LORB-R)

| | **F** | **E** | **C** | **Earlier LORB-R** |
|---|---|---|---|---|
| Honesty about 25% | Adds 13+5+6 = 24% as if it were a floor | Shows 18.95% base, 25% as a *strong* month | Treats 25% as routine via “runners” | 6–8% from strategy, 25% from prop capital |
| Core edge | 3 sleeves, good idea | London sweep is the business | Judas swing + NY pullback | Same London sweep/retest |
| Correlation control | Weak (EURUSD in A *and* C) | **Best** — 1% per USD/JPY/commodity group | None | One position per USD block |
| Grid | 8 legs, **5–6% basket**, ADX&lt;20 | **3 equal legs, 0.5% basket, ADX&lt;16** | 3 legs **with 1.0 / 1.2 / 1.5×** | 6–8 equal legs, 6% basket |
| Grid death | Known, but 6% × 2 stops = −12% month | Known and *small* | Claims $200 cap, but lot scaling still grows pain | Known, too large |
| Session map | Strong | Strong + pair-specific “do not use when” | Decent, adds US30 you don’t need | Strong |
| Out-of-box | Prop stack, ATR regime switch, spread arb | Prove each pair with 100-trade gate | 75% off at 1R, 25% 4H trail | Prop stack |
| What would blow you | Grid sleeve at 6% | Almost nothing if you follow the 8% monthly stop | The 1.5× third leg + holding grid into London | 1.5% × 2 correlated pairs |

**Verdict in one line:** F has the best *portfolio idea*, E has the only *survivable numbers*, C has one useful *trade-management* trick. The earlier LORB-R was the right setup and the wrong grid size.

Math that decides it:

- Need: \(1.25^{1/21}-1 = 1.07\%\) net per trading day, or \(1.25^{12} = +1355\%\)/year.
- E’s formula is the real requirement: \(N \times f \times E\). At 45 trades, 1% risk, 0.55R → 24.75%. That 0.55R is *not* a beginner number.
- E’s realistic book: \(9.0+6.0+2.7+1.25 = 18.95\%\). Treat **~12–19%** as a good month. 25% is a *hot* month, not a KPI you force with leverage.
- F’s grid EV gate \(p < 4.8\%\) is a good design constraint, but a 6% basket still fails the “two bad nights and you’re done” test.
- \(0.55^9 \approx 0.46\%\) per sequence — a 9-loss streak *will* show up this year. At 1% you lose 9%. At F/LORB 1.5–6% you don’t get a year.

---

## The hybrid you should actually run

**Capital split (same account, not three accounts):**

| Sleeve | Weight | Session (UK) | Pairs | Risk | Role |
|---|---|---|---|---|---|
| **1. London sweep + retest** | 70% of activity | 07:00–10:30 | EURUSD, GBPUSD only | 1.0% per trade | Makes the month |
| **2. NY continuation** | 20% | 13:30–16:00 | USDJPY or XAUUSD, **one** | 1.0% | Extra 4–6% when London already printed |
| **3. Capped grid** | 10% | 00:00–07:00, flat by 07:00 | EURGBP *or* AUDNZD, never both | **0.5% basket** | Side income, never the 25% engine |

**Hard limits (steal these from E, do not loosen):**
- Max open risk **1.5%**. USD group (EURUSD+GBPUSD) = **one 1%**.
- Daily −2%. Weekly −5%. Monthly −8% → stop, demo the rest of the month.
- After 2 losses: half size. After 3 losses same day: done.
- No CPI / NFP / FOMC / BoE / ECB / BoJ. No grid Friday into the weekend.

---

### Sleeve 1 — this is your “best strategy” (merge LORB-R with E)

Trade **only** EURUSD and GBPUSD, London, and only if **all** are true:

1. Asian range 00:00–07:00 UK: EURUSD 15–35 pips, GBPUSD 20–45 pips. Wider = no trade (no compression).
2. H1 in the trade direction: price vs 50-EMA, 20-EMA sloping with it.
3. Spread normal (EURUSD &lt; 1.0, GBPUSD &lt; 1.5).
4. No high-impact news in 45 minutes.

**Long (mirror for short):**
- Sweep **below** Asian low, 5m close back inside within 3 candles.
- Then 5m close above the last lower high / Asian high.
- Enter **on the retest**, not the spike.
- Stop: below the sweep low, min 12 pips EURUSD / 15 GBPUSD.
- **C’s runner, cleaned up:** close **50% at 1R**, stop to breakeven. Close **25% at 2R** or previous-day high/low. Trail the last **25%** on 1H swing structure, hard flat 16:00 unless that runner is already &gt; 2R — then trail 4H swings. That last 25% is the only “out of the box” you need. Do **not** leave 25% with no stop.

Worked example, $10,000, 1% = $100, 20-pip stop → $5/pip. Half at 1R, quarter at 2R, quarter trails: a normal winner ≈ **1.5R = $150**. Two A-setups like that in a week is +3% without touching a grid.

Skip ~40% of signals that fight the daily 20-EMA / DXY. That filter is what lifts expectancy toward 0.35R+.

**GBPJPY:** do not put it in sleeve 1. Too fast for a retest. If you add it later, half size, 1.5×ATR stop, no grid, London only.

---

### Sleeve 2 — NY, only as a continuation

08:35–11:00 NY (13:35–16:00 UK). Conditions from E, keep them:

- London already did ≥ 0.6× ADR in one direction.
- Pullback into 5m 20-EMA or VWAP, rejection candle, enter the break of that candle.
- Stop under the pullback. Target 2R. **No new direction after 15:30 NY.**
- USDJPY when yields/Fed agree. XAUUSD if London gold already chose a side. USDCAD only if oil does **not** fight the USD call.

If London was chop: **sleeve 2 is off.** That one rule stops most NY give-back.

---

### Sleeve 3 — the only grid that should exist

F said “gate the regime.” E said “0.5% and three equal lots.” **Both. C’s 1.2×/1.5× is still a martingale. Don’t.**

**On at 00:00 UK, forced flat 07:00 UK, one pair, one direction, one basket.**

All of these must pass or there is no grid:

1. H1 ADX(14) **&lt; 16** (E’s bar, not F’s 20).
2. H1 ATR below 40th percentile of last 60 days.
3. H4 20-EMA change over 10 bars &lt; 0.25 ATR (flat).
4. Price inside yesterday’s high–low.
5. No high-impact news 12h for either currency.
6. Spread &lt; 15% of first spacing.
7. Pair ∈ {EURGBP, AUDNZD} only.

**Structure** (E’s 3-level, equal size):

Let \(A =\) M15 ATR(14).

- Leg 1 at price, leg 2 at \(0.30A\), leg 3 at \(0.60A\), **hard basket stop at \(1.20A\)** from leg 1.
- Lots: **0.01 / 0.01 / 0.01** (or whatever equal size makes full-stop = 0.5% of account).
- TP: close **entire** basket at average entry \(+ 0.35A\).
- Start a long grid only after M15 touches 2σ lower BB **and** RSI(2) &lt; 5 **and** a close back inside the band. Not “price went down.”

**Kill immediately** (cancel unfilled, close filled): M15 close outside the H1 range with a large body; H1 ADX &gt; 20; spread doubles; news surprise.

**$10,000 example:** 0.5% = $50. \(A = 10\) pips. Stop 12 pips from leg 1. If all three fill, pip-units to
