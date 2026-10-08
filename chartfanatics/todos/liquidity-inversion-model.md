# 17. Liquidity Inversion Model

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `liquidity-inversion-model` |
| **Type** | video-only (Glimpse summary) |
| **Source** | [Glimpse summary](../glimpse/UIGZtoGGPH4.md) · [summary PDF](../glimpse-pdf/UIGZtoGGPH4.pdf) · [YouTube](https://www.youtube.com/watch?v=UIGZtoGGPH4) (@chart-fanatics) |
| **Origin** | [chartfanatics.com/strategies/liquidity-inversion-model](https://www.chartfanatics.com/strategies/liquidity-inversion-model) · [Glimpse](https://glimpse.wozart.com/v/gb8wwmls) |
| **Board** | [`chartfanatics/TODO.md`](../TODO.md) |
| **Updated** | 2026-10-07 |

> Work this card top to bottom; **tick a box in place and it survives regeneration**
> (`python3 gen_todos.py`), so the checkboxes are the source of truth for status.
> Anything between the `edit:` markers is never overwritten by the generator.

## Stages

- [x] **1. Read source** — PDF / summary reviewed end to end; note page or section refs in Notes <!-- id:read -->
- [x] **2. Extract rules** — Entry, exit, stop, targets, timeframe, session, instruments - in writing <!-- id:extract -->
- [x] **3. Mechanizable?** — Verdict: EA candidate | discretionary checklist | drop (say why) <!-- id:verdict -->
- [x] **4. Write spec** — Unambiguous spec: exact conditions, no 'price reacts' phrasing <!-- id:spec -->
- [ ] **5. Backtest** — Run through validation/mt5_harness; record symbol, period, PF, DD, trades <!-- id:backtest -->
- [x] **6. Implement EA** — New .mq5 with its own magic, or adapt an existing engine; cross-check docs/ICT_SMC_COVERAGE.md <!-- id:ea -->
- [ ] **7. Validate** — Strategy Tester gates + scripts/check_mql5_source.py pass <!-- id:validate -->
- [ ] **8. Demo / forward** — Forward phase per docs/EA_VALIDATION_PLAYBOOK.md, then live decision <!-- id:demo -->

## Tracking

<!-- edit:tracking -->
- **Verdict:** Implemented as a strategy - the video's whole stack is stated mechanically enough to code, and every reading of it is labelled `[interpretation]` in the source. The EA runs the two models the document separates: **day** (daily wick sweeps the prior **weekly** extreme and closes back inside - **monthly** liquidity is checked first because the doc calls it the more significant sweep - the reaction leaves a **4-hour fair value gap**, that gap's **inversion** on the 4H (a displacement close through it plus a retest that holds the new side) is the bias confirmation, then a counter-trend **15-minute gap** is inverted on the **5-minute** as a *market* execution) and **swing** (entries only off the hourly/4-hour gap, "never the 15-minute or lower", H4-structure stop, no break-even/trail so whipsaws are ignored, unfilled daily/weekly gaps marked as extra partials). Stops beyond the 15-minute high/low (mirrored for both sides) with an ATR buffer "wide enough to breathe", targets at prior sellside/buyside liquidity (previous day's extreme, the 9:30 NY-open level, HTF gaps) behind a **1.5R floor** ("typically yields a 1.5:1 to 2:1"), **trim 50% at 1R + break-even + runner trail**, **half size in high-volatility regimes** ("same dollar risk"), and the day model only trades **after the 10:00 ET open**. The document's discipline rules are enforced: **two consecutive losses stop the day** (a win resets the count and allows the third attempt) - tracked in class state because the engine's `dayLockAfterLosses` counts *today's* losers, not consecutive ones - and the optional **VIX** gate (elevated volatility raises setup probability) since the symbol is broker-dependent. Not codeable on MT5 spot and disclosed: the **options-leap** workflow (macro monthly/weekly FVG + order-block zones) and the **prop-firm payout** framing; they are described on the card, not silently dropped.
- **Instruments:** NQ/ES (the demo trades NQ) - `InpSymbolsToTrade` (default `US100,US500`); the model is index-futures shaped
- **Timeframe / session:** M5 execution for the day model (H4/M15 context), H1 for the swing layer; NY session from 10:00 ET, London-clock window 15:00-21:00
- **EA file / magic:** [`EA_CF_LiquidityInversion.mq5`](../mql5-eas/EA_CF_LiquidityInversion.mq5) / `3220` (static-checked)
- **Priority:** P1 - the flagship ICT multi-timeframe reversal stack of the library
- **Blocked by:** _nothing_ for the day/swing models; options-leap workflow + prop-firm payout rules are not implementable on MT5 spot (documented)
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: the daily/weekly sweep premise and why institutional liquidity matters more than
  session highs/lows; monthly > weekly > daily significance; the 4H reaction gap and its inversion as
  the highest-probability confirmation; the 15m retracement gap inverted on the 1m/5m as the entry;
  market execution vs limit orders and the missed-runner problem; stop above the 15m high "to breathe";
  target prior sellside liquidity (previous session low, 9:30 open low); 1.5:1-2:1 framing; 50% trim at
  the first target, break-even, runners; two-consecutive-loss day stop with a third attempt after a
  win; "10 a.m. start - before that price action is too choppy"; volatility-based sizing; the 65% win
  rate over a 1k-2k trade dataset; the swing-gap add-on layer (H1/H4 entries, multiple gap partials);
  VIX-elevation probability note; the options-leap macro workflow; the prop-firm payout framing.
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_LiquidityInversion.mq5` (35 rules pinned).
- `[interpretation]`: the rejection tolerance is a fraction of the gap height (the video gives no
  number); "inversion" is read as break-through close + retest that holds the new side (the doc's own
  words); the sweep window is a 3-day default; the engine's `dayLockAfterLosses` counts today's losers,
  so the consecutive rule is tracked in class state (a win resets it); the VIX gate is off by default
  because the symbol is broker-dependent.
- Axis options-leap / prop-firm sections are disclosed on the card as non-codeable; the swing layer is
  implemented with `InpModel = CF_LI_SWING` (H1 gap inversion, H4 stop, unfilled daily gaps as targets,
  no break-even/trail).
- Card number note: the loop dispatches this build as its 16th; the board card is **#17** (card #16 is
  `intraday-liquidity-volatility-model`), so manifest/card/README carry #17.
<!-- /edit:notes -->
