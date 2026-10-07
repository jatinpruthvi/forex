# 16. Intraday Liquidity & Volatility Model

| | |
|---|---|
| **Status** | 🟡 WIP — 5/8 stages |
| **Slug** | `intraday-liquidity-volatility-model` |
| **Type** | published PDF |
| **Source** | [PDF](../pdf/intraday-liquidity-volatility-model.pdf) (2.9 MB) |
| **Origin** | [chartfanatics.com/strategies/intraday-liquidity-volatility-model](https://www.chartfanatics.com/strategies/intraday-liquidity-volatility-model) · [source PDF on Google Drive](https://drive.google.com/file/d/1nKDbrdtHSO4Dv0Jfye7QctgWF6NSXsJ6/view?usp=sharing) |
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
- **Verdict:** Tradable, implemented. Daily bias + session liquidity raid during the NY window, entered on FVG / MSS / breaker confirmation, targeting the opposite session's liquidity.
  `[interpretation]`: "if the trade slows near midday, consider exiting" becomes the engine time stop (90 min unless the trade is already at 1R).
- **Instruments:** Futures / Forex (playbook). EA: US100 / US500 / GER40 / XAUUSD (`InpSymbolsToTrade`)
- **Timeframe / session:** Playbook: daily bias, 15m / 5m confirmation, 9:30-11:30 ET. EA: M5 signal, London 14:30-16:30 = NY 09:30-11:30, raid lookback 12 bars
- **EA file / magic:** [`EA_CF_Intraday_Liquidity.mq5](../mql5-eas/EA_CF_Intraday_Liquidity.mq5) / `3206` (static-checked)
- **Priority:** P2 - the raid detector is reusable; swing variant (HTF alignment) is not implemented
- **Blocked by:** _nothing_
<!-- /edit:tracking -->

## Notes

<!-- edit:notes -->
### EA implemented 2026-10-07
- **Source read:** `pdf/intraday-liquidity-volatility-model.pdf` (7 pp, JadeCap) - daily bias + a failed NY-session raid of session liquidity, FVG/MSS confirmation, target the opposite session liquidity.
- **EA:** [`mql5-eas/EA_CF_Intraday_Liquidity.mq5`](../mql5-eas/EA_CF_Intraday_Liquidity.mq5), magic `3206`, M5.
- **Encoded:** daily bias gate (D1 200-EMA with a band); a marked-level raid that FAILS to continue (custom detector over previous day high/low, Asian high/low and London high/low); 09:30-11:30 New York window; `SigFvgRetest` entry (sweep-reclaim MSS fallback); stop forced beyond the sweep extreme; target = opposite Asian session liquidity when >= 1.5R.
- **Gaps:** the playbook's "second entry" (a re-test of the same FVG after price dips) is largely covered by the FVG retest window but is not tracked as a distinct second setup; London range inclusion is an input (default on).
   - Entry/confirmation come from `SigFvgRetest` and `SigSweepReclaim` (MSS), levels from `SigRangeForDay`/`SigAsianRange`. `SigSessionFade` is deliberately not used: it only fades within 3 hours of a range closing (02:00-05:00 ET), while this model trades 09:30-11:30 ET.
- **Status:** passes `scripts/check_mql5_source.py` (0 findings); **not yet compiled**.
<!-- /edit:notes -->
