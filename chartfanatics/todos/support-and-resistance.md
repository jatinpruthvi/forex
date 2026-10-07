# 40. Support and Resistance

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `support-and-resistance` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/support-and-resistance.pdf) (7.7 MB) |
| **Origin** | [chartfanatics.com/strategies/support-and-resistance](https://www.chartfanatics.com/strategies/support-and-resistance) · [source PDF on Google Drive](https://drive.google.com/file/d/1WF8Mdee6ziWKZD4U7rZNcLWgqM97j0H3/view?usp=sharing) |
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
- **Verdict:** Implemented as a trading EA - the playbook is mechanical once its three pillars are written down ("the strategy thrives on the convergence of: price reaching a key level, catalyst providing the volatility needed to trigger a large move, confirmation before entry"). **Levels**: swing highs and lows ("past market highs, lows, and reactions on daily/weekly charts") are collected from **both the daily and the weekly series**, clustered within a tolerance, scored by the number of reactions, gated on being **major** ("major support/resistance levels" - tested at least `InpMinTouches` times or weekly-confirmed), and flagged when they sit on a **round psychological number** ("round psychological numbers like 5000, 6000, or 7000 on SPX tend to act as strong magnets"). The working level book is written to `cf_support_resistance_levels.csv` as evidence. **Catalyst**: "Only take trades when the technical level and fundamental catalyst align. Avoid trading key levels without a strong catalyst" is a hard gate. The document names FOMC, CPI/NFP, earnings and geopolitical events; FOMC/CPI/NFP are exactly the terminal calendar's red-folder events, so the EA reads the engine's news cache (calendar live, CSV in the tester), and because **earnings dates are not in the calendar** a **volatility-footprint proxy** (a news-sized bar within the last few sessions) is the tester-safe source - both disclosed. The engine's own blackout keeps entries out of the print itself. **Confirmation**: "A strong bounce or rejection from the level" (the completed day reaches the level and closes back beyond it), "Multi-day hold or reclaim of the level" (completed closes beyond it), Example 1's own context ("price formed two higher weekly lows following the initial test of 5000") required on a support bounce, and Example 2's word-for-word entry ("long calls were taken once the price reclaimed and stabilized above 5700") coded as the reclaim-and-hold continuation. **Sizing**: "Sizing for Zero" verbatim - "size your total trade to $1,000 - fully acceptable loss if the trade goes to zero" becomes a tiny risk with the document's own **20% wide stop** as the accepted complete loss, **no break-even and no trailing** because that is what "allows you to hold through volatility" and "avoids premature exits", and scale-outs at **5R and 10R** ("target massive R multiples (5x, 10x+)").
- **Instruments:** `US500,US100` default - the playbook is SPX options (weekly/monthly contracts); MetaTrader has no options chain, so the EA trades the underlying index/CFD and expresses the contract horizon as the time stop - **disclosed, not faked**
- **Timeframe / session:** levels from D1 and W1 bars (the document's "weekly and daily charts"), execution on the M5 signal frame inside the US cash session; positions are held for weeks (no session flat, no Friday flat) - the thesis is the level, not the day
- **EA file / magic:** [`EA_CF_SupportAndResistance.mq5`](../mql5-eas/EA_CF_SupportAndResistance.mq5) / `3240` (static-checked)
- **Priority:** P1 - the queue's level/catalyst card
- **Blocked by:** _nothing_
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: the playbook overview (higher-timeframe levels, event-driven confirmation, the
  anti-overtrading stance, the mindset foundation), the playbook rules (options style, identifying key
  levels, round numbers as magnets, the convergence rule with the FOMC / CPI / NFP / earnings /
  geopolitical catalyst list, confirmation before entry, Sizing for Zero with the $5,000 -> $1,000
  example), the pros and cons (80% win rate when technicals and news align, only a few ideal setups per
  year, execution pressure), and both trade breakdowns (the May 2024 SPX long from 5000 with two higher
  weekly lows and the 5150-5160 entry; the November 2024 post-election breakout above 5700 with the
  reclaim-and-stabilise entry).
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_SupportAndResistance.mq5` (39 rules pinned).
- `[interpretation]`: the pivot width, the clustering and approach tolerances, the round-number step
  (the document's examples are multiples of 500), the touch / bounce tolerances, the hold bars, the
  catalyst lookback window and the volatility-proxy multiple, the time-stop horizon for the monthly
  contract, the level cooldown and the symmetric short when a support is lost are inputs and labelled.
- Design notes: the level book is rebuilt from the daily and weekly series every time a plan is
  evaluated, and the same book is dumped to CSV once a day, so the human can audit which levels the EA
  worked with (the document tells the trader to identify them by eye; the CSV is that identification,
  in writing). A traded level then goes on a cooldown so the same magnet is not re-entered day after
  day - the document's "patience is critical" as a rule. The engine's news subsystem supplies the
  catalyst window *and* the blackout, so the EA never opens into a print and never opens without one;
  the proxy mode exists only so the whole thing is testable in the Strategy Tester, where the calendar
  API has no data.
- Disclosed, not faked: options premium/delta mechanics, position-greek sizing and the "weekly or
  monthly contract" selection are out of scope for MetaTrader - the EA trades the underlying and uses
  the time stop as the contract horizon; the terminal calendar has no earnings dates, so earnings
  catalysts are covered by the volatility proxy; the "clear shift in sentiment post-catalyst" is read
  as the level's own reaction (the observable half of that sentence).
<!-- /edit:notes -->
