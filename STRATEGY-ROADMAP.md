# Strategy Roadmap — Two Tracks (2026-09-12)

**User objective update:** the challenge has no official time limit, but capital is
deployed and profit is required. **New requirement: Phase 1 (+10%) in ≤ 3 months**
(≈ +3.3%/month ≈ +0.16%/trading day). Everything found so far is preserved below;
new fast-track work happens in **new files only** so the long-term track is never lost.

---

## Track A — LONG-TERM (validated, preserved, not fast enough for 3 months)

**TRIAD sweep/reclaim — relaxed core-3** (`tools/triad_honest.py`, findings §7):

- GBPJPY + EURJPY + XAUUSD, London only, Asian-range sweep → reclaim → displacement,
  limit at 50% retrace, stop 0.6–1.5×ATR-M15, T=1.5R, 90-min time stop, session flat.
- Relaxed geometry: sweep ≥0.02 ATR, wick ≥0.45, body ≥0.50.
- Risk 1.5%/trade. **0% intrabar ambiguity** (all bounds identical), costs 5–8% of risk.
- 4-year honest result: 94 trades, **PF 1.60**, DD 7.8%, all pairs positive,
  rising 2024–26. **Phase 1 in ~723 trading days (~2 years).**
- Verdict: real edge, structurally bug-proof, **too slow for the 3-month goal**.
  Kept as the long-term compounding track (and as Phase 2/funded-account strategy
  where patience is fine).

## Track B — FAST-TRACK (new, goal: Phase 1 ≤ 3 months)

### The math the new strategy must beat
- +10% in ~63 trading days with a **−10% total floor** (The5ers) and −5% daily limit.
- Floor math caps sane risk at **1.5–2.0%/trade** (a 5-loss streak must stay < 10%).
- Therefore the strategy needs ≈ **+5…7R net per quarter** — i.e. combination of
  frequency × expectancy, e.g. ~1 trade/day × AvgR ≥ +0.11, or ~2/day × AvgR ≥ +0.06,
  at PF ≳ 1.3 **after raw-account costs**, with max DD ≤ 8%.

### What was already ruled out (sessions 5–9, all documented in
`findings_live_friction_audit.md` + `progress.md`)
- Old ORB champion ($359/mo): **the profit was the bugs** (adverse-selection fills,
  optimistic intrabar resolution, zero costs). Honest: +$24/mo or busts.
- ORB with wide stops: ambiguity falls but edge dies faster (tight stop WAS the edge).
- More pairs / NY window: dilute. XAUUSD is the only strong ORB instrument.
- News blackout, one-position compliance: modeled in every result below.

### New families in the lab (`tools/fast_track_lab.py` — new file, honest framework)
- **F1 Quiet-session range fade** (founder's TRIAD-SURVIVE Sleeve C idea): fade
  2-SD band touches back to the mean in 00:00–06:30 London on low-vol crosses
  (EURGBP, AUDUSD, NZDUSD, USDCHF, EURUSD). Market-fill at band-touch close,
  stop = extreme ± 0.5 ATR, target = band mean, hard flat 06:30.
- **F2 Failed-breakout reversal**: ORB level breaks, then closes back inside →
  trade against the failure, stop beyond the break extreme, target 1.0–1.5R.
  Mirrors the one real momentum structure that survived auditing.
- **F3 Breakout rider** (diagnostic): ORB entry + stop, NO target — exit at session
  end only. Measures how much edge is in "riding" vs the (path-dependent) 3R target.

Every family runs through the same honesty layer: re-touch/market fills as
appropriate, opt/coin/pess ambiguity bounds, raw-account costs inside each trade,
per-day pip values, ONE account-wide slot, 2 trades/day, daily/floor governors.

### Ranking rule for Track B
Fastest honest Phase 1 on the 2-year gate (Jan 2024–Sep 2026); any survivor is
then confirmed on the 4-year set. **A family that only passes on the optimistic
intrabar bound does not count** (that lesson is the whole session-6–8 audit).

### Relationship to the `.qoder` documentation (reviewed 2026-09-12)
- `repowiki/` — generated repo wiki (compliance, EA internals, validation,
  backtesting docs). Accurate for the **pre-audit** repo state; its performance
  claims (ORB champion $331–359/mo) are **superseded** by sessions 5–9 of this
  roadmap and `findings_live_friction_audit.md`. Compliance/EA/validation
  sections remain the reference for Track A engineering (TRIAD_R_HS gates,
  news calendar contract, frozen registries).
- `better-harness/findings.json` (2026-09-11) — 7 independent findings that
  foreshadowed this audit: champion artifacts disagreeing, wrong data window in
  findings, optimizer regressions unverified by tests, optimizer overwriting
  the findings doc. **All subsequently confirmed and fixed** (sessions 5–7:
  dynamic data window, 14 optimizer regression tests, supersession history
  preserved in git). Standing rule adopted: new strategy tools write their own
  findings files (never overwrite another tool's doc).

*Round 1 results (2026-09-12): see `findings_fast_track_lab.md` — **all four
families eliminated** (F1 PF≤0.69, F2 PF≤0.59, F3 0%-WR diagnostic proving no
London breakout follow-through, F4 PF≤0.86). Combined with sessions 5–9, TRIAD
sweep/reclaim is the ONLY edge on this dataset that survives honest accounting.
The 3-month Phase-1 goal is not achievable from this M5 data at floor-safe risk;
the honest paths forward are tick-data validation and additional validated
signal sources (findings_fast_track_lab.md §What-could-change-this-answer).*

---

## PERSONAL-ACCOUNT TRACK (added 2026-09-12, later same day)

User reframed the goal: personal (non-challenge) account, max 10% DD, wants
40–50%/yr; asked about scalping and other classes. Findings:
`findings_swing_and_portfolio.md` (tool: `tools/swing_lab.py`).

- **Scalping:** untestable on bid-only M5 data (needs ticks + live spreads);
  cost math against it by construction. Deferred to tick-data phase.
- **Swing/trend validated on GOLD only** (Donchian N=55 k=2.5, PF 3.76,
  AvgR +0.89R, 19 trades, regime-dependent); FX trend-following dead (PF<1).
- **Two-leg validated portfolio:** TRIAD core3 (1.5%) + Gold swing (3%) →
  **~21%/yr expected at 10.3% maxDD** (2024–25 tail years +28/+51% are
  gold-trend-inflated; plan on the CAGR).
- **40–50%/yr at ≤10% DD: not reachable today.** Frontier is ~21% at 10% DD.
  Reachable with ~2–3 more validated uncorrelated legs (tick data, indices,
  more crosses) — returns scale ~N, DD scales ~√N. That is the roadmap.
