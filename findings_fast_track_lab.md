# Fast-Track Lab — Round 1 Findings (2026-09-12)

**Tool:** `tools/fast_track_lab.py` (new file — writes its own findings per the
standing rule adopted from `.qoder/better-harness` finding
`optimizer-overwrites-findings-doc`).
**Goal:** Phase 1 (+10%) ≤ 3 months ⇒ ≈ +3.3%/month at PF ≳ 1.3 **after raw
costs**, max DD ≤ 8%, risk ≤ 1.5–2% (floor math).
**Gate:** 2-year FSB dataset (Jan 2024 – Sep 2026), honesty layer identical to
sessions 7–9 (ambiguity bounds, re-touch/market fills as appropriate, raw-account
costs inside every trade, per-day pip values, one account-wide slot, governors).

---

## Round 1: four new strategy families — ALL ELIMINATED

| Family | Concept | Best 2y result (1% risk) | Verdict |
|---|---|---|---|
| F1 Quiet-session range fade | Fade 2–2.5 SD band touches 00:00–06:30 London on quiet FX | PF 0.45–0.69, all halt | ❌ no edge after costs (stops 1.5–4 pips → cost share 20–40% again) |
| F2 Failed-breakout reversal | ORB break, close back inside within 3–5 bars → fade it | PF 0.30–0.59, all halt (20–44 trades) | ❌ negative in every universe/param |
| F3 Breakout rider (diagnostic) | Validated ORB entry, stop only, ride to session end | **WR 0.0% over 77 trades**, PF 0.88, DD 24.7% | ❌ **and diagnostic: London breakouts have ZERO follow-through** — the old ORB "3R wins" were pure target-path artifacts |
| F4 Trend pullback (Sleeve-B concept) | EMA20/50 trend, enter on pullback touch, 1.5–3R, 0.5–1 ATR stops | PF 0.18–0.86, all halt | ❌ negative in every universe/param |

Notes: F2 had an implementation sign bug in round 1 (stop distance inverted in
both branches → 0 trades); fixed and re-run — still negative, so the elimination
stands on the corrected code. F3's bounds are trivially identical (no target);
its 0% win rate is the cleanest possible proof that the M5-data momentum edge
doesn't exist in these instruments/sessions.

## Combined with sessions 5–9, the empirical map of this dataset is now:

| Family tested (honest accounting) | Survives? |
|---|---|
| ORB tight-stop (11 & 3 pair universes, 60–72 param combos) | ❌ (mid bound busts w/ costs; optimistic-only survives) |
| ORB wide-stop (ambiguity-engineered) | ❌ (ambiguity falls, edge falls faster) |
| Quiet-session mean reversion (F1) | ❌ |
| Failed-breakout reversal (F2) | ❌ |
| Breakout riding without target (F3) | ❌ (0% follow-through) |
| Trend pullback (F4) | ❌ |
| **TRIAD sweep/reclaim (canonical + relaxed, core-3, London)** | ✅ **PF 1.6–2.7 after costs, 0% ambiguity — the ONLY survivor** |

## Conclusion for the 3-month objective

On this repository's data (FX/XAU M5 OHLC, 2022–2026) and within the floor-math
risk ceiling, **no strategy family tested achieves +10% in 3 months with honest
accounting.** The only validated edge produces ~+0.5R/month (Phase 1 ≈ 2 years).
This is a property of the market data and the challenge's own drawdown floor —
not of parameter tuning.

## What could change this answer (in order of information value)

1. **Tick / 1-minute data** (Eightcap export) — the only way to (a) certify the
   TRIAD fills, (b) search intrabar-dependent and higher-frequency patterns that
   M5 OHLC provably cannot measure (13.5% of tight-stop trades were path-
   dependent), (c) validate more sessions/instruments cheaply.
2. **More instruments** (indices/GER40/US30/crypto per the founder's Sleeve-B
   note) — need data exports before any testing.
3. **Stacking validated sources** — if TRIAD is joined by even one more
   +0.4R/month source, Phase 1 halves. This is the honest frequency lever.
4. **Not an option:** risk > 2% — turns "slow pass" into "probable bust"
   (5-loss streak ≥ floor). Refused on math, not preference.

*Round 2 awaits tick data / additional instruments. Track A (TRIAD) remains the
validated challenge vehicle.*
