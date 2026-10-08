# 35. Shorting Strategy

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `shorting-strategy` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/shorting-strategy.pdf) (31.4 MB) |
| **Origin** | [chartfanatics.com/strategies/shorting-strategy](https://www.chartfanatics.com/strategies/shorting-strategy) · [source PDF on Google Drive](https://drive.google.com/file/d/1tKaL0zxHK8M5RZsTRZvZSLdgGNEjZwEe/view?usp=sharing) |
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
- **Verdict:** Implemented as a full EA - the playbook is unusually explicit about its systematic spine, and all of it is coded. **Selection**: the document's quantitative gate that survives in an EA is the gap itself - "Focus on stocks with large percentage gaps. Smaller moves (around 20-40%) are avoided" - so the minimum gap is a labelled input defaulted above that band; market cap (<$100-200M) and institutional ownership (<40%) are not observable in MetaTrader, so the universe carries that filter (disclosed). **Gap-up fade (ADF behavior)**: entered only **after the open**, with the **10:00 a.m. behavior check** as the confirmation - trading below the open price with **volume decreasing** - and entries taken **into pops or bounces** and never at the exact low of a flush. **Backside parabolic short (the primary edge)**: a large run-up has already happened, topping signs (upper wicks, a failed push) and fading volume are required, and the entry comes on a bounce during the fade - "do not short the first sign of weakness". **Multi-halt exhaustion**: halts are not observable in MetaTrader, so the document's own fallback - "the overall extension is historically extreme" - is the gate (disclosed). **Risk**: "pre-market highs are not used as stops" - stops are a **fixed percentage**, deliberately wide ("the goal is staying in the trade, not tight precision"), sizing is conservative, the live rule **above the open -> reduce risk or exit** closes a failing short, and the **30-minute validation** rides the engine's time stop with an R escape hatch ("if the trade is working after ~30 minutes, holding makes sense"). **Recycling**: partials into the sharp drops plus a re-entry budget so bounces into prior support can be re-shorted ("repeat within a defined range"). New risk stops after midday ("after ~12:00 p.m., edge decreases").
- **Instruments:** `AAPL,MSFT,NVDA` default - the playbook trades **small-cap gappers**, so the universe input should be the user's own gapper list
- **Timeframe / session:** M5 intraday behaviour reads; entries from the open until midday (18:00 London / 12:00 ET), flat at the US close
- **EA file / magic:** [`EA_CF_ShortingStrategy.mq5`](../mql5-eas/EA_CF_ShortingStrategy.mq5) / `3237` (static-checked)
- **Priority:** P1 - the short-side day-trading card
- **Blocked by:** _nothing_
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
- Sections used: the playbook overview, the stock selection criteria (market cap, institutional ownership,
  gap strength), the three core setups (gap-up short with fade validation, backside parabolic short,
  multi-halt exhaustion short), the risk-management rules (stop logic, fixed percentage wide stops, the
  trade-off, outlier risk), the trade-management rules (the 10:00 a.m. behaviour rule, the 30-minute
  validation, ongoing context checks, the recycling framework and its benefits), the time-of-day rules,
  the pros and cons, and the CRCL trade breakdown (the backside short, the partial into the prior-day
  close level, the recycling loop on the bounce into resistance).
- Sync table: `tests/test_chartfanatics_sync.py` -> `EA_CF_ShortingStrategy.mq5` (36 rules pinned).
- `[interpretation]`: the document deliberately quantifies almost nothing, so the fixed stop percentage
  (15%), the volume-decline fraction, the flush clearance, the bounce definition, the topping thresholds
  (upper-wick share, the failed-push read), the parabolic run minimum, the extreme-extension proxy for
  halt exhaustion, the attempts budget and the 30-40% target centre are inputs and labelled.
- Design notes: the 30-minute validation is the engine's time stop with `timeStopUnlessR`, so a trade
  that is already working (>= 0.25R) is kept, exactly as the document describes; the recycling loop is
  the partial at 1R plus the day's attempts budget (the engine cannot add to an open position, so a
  recycle is a fresh plan on the next bounce, which is also what the document does in practice); the
  above-the-open reduce-risk rule is evaluated live after the behaviour check and closes any open short,
  applying to every setup since all three are fade shorts that require the below-open context.
- Disclosed, not faked: market cap and institutional ownership filters (not in MetaTrader - the universe
  and the gap gate stand in), the ongoing context checks (manipulation reads, sympathy moves, small-cap
  breadth), hard-to-borrow fees and locate costs, and the discretionary "reassess" judgement stay human.
<!-- /edit:notes -->
