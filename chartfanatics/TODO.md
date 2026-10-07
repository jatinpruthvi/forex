# ChartFanatics — Strategy Work Board

**47 strategies** archived in this folder (32 with a published PDF, 15 video-only
with a Glimpse summary). Every strategy has a work card in [`todos/`](todos/) covering the same
8 stages, from "read the source" to "demo / forward".

**Cards:** ✅ 0 done · 🟡 0 in progress ·
⬜ 47 not started

**Stages ticked:** 0/376 (0%)
`▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱`

*Regenerated 2026-10-07 by [`gen_todos.py`](gen_todos.py). Checkbox state lives in each card
and is never lost on regeneration; edit through the cards, not this board.*

---

## How to work a card

1. Open `todos/<slug>.md`, read the source PDF / summary, fill the **Tracking** block with the verdict.
2. Tick stage boxes as you go — a card with any box ticked becomes 🟡, all 8 becomes ✅.
3. Re-run `python3 gen_todos.py` after ticking to refresh this board (it preserves every edit).
4. When a strategy is dropped, leave the verdict in Tracking and say why — that is as useful as an EA.

Reference material for the later stages: [`docs/EA_VALIDATION_PLAYBOOK.md`](../docs/EA_VALIDATION_PLAYBOOK.md)
(compile → calendar → tester sweep → forward), [`docs/ICT_SMC_COVERAGE.md`](../docs/ICT_SMC_COVERAGE.md)
(which primitives already exist and which are genuinely missing),
[`docs/EA_IMPLEMENTATION_TRACKER.md`](../docs/EA_IMPLEMENTATION_TRACKER.md) (magic-number allocation; anything
built here must take a free magic outside 1000-1016 / 2001-2048 / 3101-3117).

## Kickoff shortlist

<!-- edit:shortlist -->
Ordered by how cheaply they can be tested against code that already exists in
`MQL5_Master/Include/EASignals.mqh` (sweep / order-block / FVG / fractal primitives) — no new
infrastructure needed to get a first verdict:

| Order | Strategy | Why first |
|---|---|---|
| 1 | [AMD Model](todos/amd-model.md) | Explicit accumulation-manipulation-distribution model; maps to the existing session-range sweep |
| 2 | [Structure + OTE](todos/structure-ote.md) | Structure break + 62-79% retrace; OTE is listed in docs/ICT_SMC_COVERAGE.md as *not implemented* — a real gap |
| 3 | [SMT Divergence + PO3](todos/smt-divergence-po3.md) | Repo has an RSI-proxy SMT that goes inert without DXY; this gives a real spec |
| 4 | [PO3, OTE + ADR](todos/po3-ote-adr.md) | Same primitives plus an ADR filter to reuse for the daily gate |
| 5 | [Break & Retest](todos/break-retest.md) | Simplest possible rule set; fast falsification |
| 6 | [Intraday Liquidity & Volatility Model](todos/intraday-liquidity-volatility-model.md) | Session/volatility window logic reusable across every engine |

<!-- /edit:shortlist -->

---

## Published PDFs (32)

| # | Strategy | Status | Progress | Source | Card |
|---|---|---|---|---|---|
| 01 | 5 Stage Trading Framework | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/5-stage-trading-framework.pdf) 7.0 MB | [`5-stage-trading-framework.md`](todos/5-stage-trading-framework.md) |
| 04 | AMD Model | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/amd-model.pdf) 25.8 MB | [`amd-model.md`](todos/amd-model.md) |
| 05 | Auction Market Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/auction-market-strategy.pdf) 5.6 MB | [`auction-market-strategy.md`](todos/auction-market-strategy.md) |
| 06 | Auction Market Theory Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/auction-market-theory-strategy.pdf) 12.4 MB | [`auction-market-theory-strategy.md`](todos/auction-market-theory-strategy.md) |
| 07 | Break & Retest | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/break-retest.pdf) 20.9 MB | [`break-retest.md`](todos/break-retest.md) |
| 08 | Episodic Pivot Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/episodic-pivot-strategy.pdf) 26.4 MB | [`episodic-pivot-strategy.md`](todos/episodic-pivot-strategy.md) |
| 10 | First Red Day | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/first-red-day.pdf) 29.8 MB | [`first-red-day.md`](todos/first-red-day.md) |
| 11 | First Red Day Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/first-red-day-strategy.pdf) 4.3 MB | [`first-red-day-strategy.md`](todos/first-red-day-strategy.md) |
| 12 | Full Psychology MasterClass | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/full-psychology-masterclass.pdf) 38.3 MB | [`full-psychology-masterclass.md`](todos/full-psychology-masterclass.md) |
| 13 | Futures Trading Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/futures-trading-strategy.pdf) 5.3 MB | [`futures-trading-strategy.md`](todos/futures-trading-strategy.md) |
| 16 | Intraday Liquidity & Volatility Model | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/intraday-liquidity-volatility-model.pdf) 2.9 MB | [`intraday-liquidity-volatility-model.md`](todos/intraday-liquidity-volatility-model.md) |
| 18 | Liquidity Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/liquidity-strategy.pdf) 37.7 MB | [`liquidity-strategy.md`](todos/liquidity-strategy.md) |
| 19 | Low Volume Node | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/low-volume-node.pdf) 3.9 MB | [`low-volume-node.md`](todos/low-volume-node.md) |
| 20 | Market Auction theory | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/market-auction-theory.pdf) 2.1 MB | [`market-auction-theory.md`](todos/market-auction-theory.md) |
| 21 | Market DNA Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/market-dna-strategy.pdf) 30.9 MB | [`market-dna-strategy.md`](todos/market-dna-strategy.md) |
| 22 | Mean Reversion Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/mean-reversion-strategy.pdf) 10.1 MB | [`mean-reversion-strategy.md`](todos/mean-reversion-strategy.md) |
| 23 | Measured Move Trend Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/measured-move-trend-strategy.pdf) 9.5 MB | [`measured-move-trend-strategy.md`](todos/measured-move-trend-strategy.md) |
| 27 | Options Trading Masterclass | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/options-trading-masterclass.pdf) 3.5 MB | [`options-trading-masterclass.md`](todos/options-trading-masterclass.md) |
| 29 | OrderFlow Trading Masterclass | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/orderflow-trading-masterclass.pdf) 16.9 MB | [`orderflow-trading-masterclass.md`](todos/orderflow-trading-masterclass.md) |
| 30 | Parabolic Short Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/parabolic-short-strategy.pdf) 9.5 MB | [`parabolic-short-strategy.md`](todos/parabolic-short-strategy.md) |
| 31 | PO3, OTE + ADR | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/po3-ote-adr.pdf) 32.8 MB | [`po3-ote-adr.md`](todos/po3-ote-adr.md) |
| 34 | Real Simple Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/real-simple-strategy.pdf) 34.0 MB | [`real-simple-strategy.md`](todos/real-simple-strategy.md) |
| 35 | Shorting Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/shorting-strategy.pdf) 31.4 MB | [`shorting-strategy.md`](todos/shorting-strategy.md) |
| 37 | SMT Divergence+PO3 | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/smt-divergence-po3.pdf) 4.1 MB | [`smt-divergence-po3.md`](todos/smt-divergence-po3.md) |
| 39 | Structure + OTE | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/structure-ote.pdf) 6.9 MB | [`structure-ote.md`](todos/structure-ote.md) |
| 40 | Support and Resistance | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/support-and-resistance.pdf) 7.7 MB | [`support-and-resistance.md`](todos/support-and-resistance.md) |
| 41 | The Vix Futures Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/the-vix-futures-strategy.pdf) 3.6 MB | [`the-vix-futures-strategy.md`](todos/the-vix-futures-strategy.md) |
| 43 | Trendline Break Pocket Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/trendline-break-pocket-strategy.pdf) 33.0 MB | [`trendline-break-pocket-strategy.md`](todos/trendline-break-pocket-strategy.md) |
| 44 | Trendline Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/trendline-strategy.pdf) 8.7 MB | [`trendline-strategy.md`](todos/trendline-strategy.md) |
| 45 | Unique High RR | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/unique-high-rr.pdf) 9.9 MB | [`unique-high-rr.md`](todos/unique-high-rr.md) |
| 46 | Universal Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/universal-strategy.pdf) 3.3 MB | [`universal-strategy.md`](todos/universal-strategy.md) |
| 47 | Volume Profile Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/volume-profile-strategy.pdf) 34.7 MB | [`volume-profile-strategy.md`](todos/volume-profile-strategy.md) |

## Video-only — no published PDF (15)

| # | Strategy | Status | Progress | Source | Card |
|---|---|---|---|---|---|
| 02 | 80/20 Nasdaq Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [video](https://www.youtube.com/watch?v=jsUTbjwpFVk) · [summary](glimpse/jsUTbjwpFVk.md) | [`80-20-nasdaq-strategy.md`](todos/80-20-nasdaq-strategy.md) |
| 03 | Algorithmic Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [video](https://www.youtube.com/watch?v=TyHTEtArsS4) · [summary](glimpse/TyHTEtArsS4.md) | [`algorithmic-strategy.md`](todos/algorithmic-strategy.md) |
| 09 | Fair Pricing Theory Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [video](https://www.youtube.com/watch?v=KHEQ5g55dQ4) · [summary](glimpse/KHEQ5g55dQ4.md) | [`fair-pricing-theory-strategy.md`](todos/fair-pricing-theory-strategy.md) |
| 14 | Institutional Options Flow & Gamma Reversal Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [video](https://www.youtube.com/watch?v=35cyqDz-ej8) · [summary](glimpse/35cyqDz-ej8.md) | [`institutional-options-flow-gamma-reversal-strategy.md`](todos/institutional-options-flow-gamma-reversal-strategy.md) |
| 15 | Institutional Strategy Development Framework | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [video](https://www.youtube.com/watch?v=yW6c0K8uGvw) · [summary](glimpse/yW6c0K8uGvw.md) | [`institutional-strategy-development-framework.md`](todos/institutional-strategy-development-framework.md) |
| 17 | Liquidity Inversion Model | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [video](https://www.youtube.com/watch?v=UIGZtoGGPH4) · [summary](glimpse/UIGZtoGGPH4.md) | [`liquidity-inversion-model.md`](todos/liquidity-inversion-model.md) |
| 24 | Momentum Model Performance Development | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [video](https://www.youtube.com/watch?v=WDdvnd9vLbM) · [summary](glimpse/WDdvnd9vLbM.md) | [`momentum-model-performance-development.md`](todos/momentum-model-performance-development.md) |
| 25 | Nasdaq ICT and Order Flow Scalping Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [video](https://www.youtube.com/watch?v=KkTTCKr-3Ew) · [summary](glimpse/KkTTCKr-3Ew.md) | [`nasdaq-ict-and-order-flow-scalping-strategy.md`](todos/nasdaq-ict-and-order-flow-scalping-strategy.md) |
| 26 | NQ Liquidity Sweep & Reversal Scalping Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [video](https://www.youtube.com/watch?v=-kGVL93XfyE) · [summary](glimpse/-kGVL93XfyE.md) | [`nq-liquidity-sweep-reversal-scalping-strategy.md`](todos/nq-liquidity-sweep-reversal-scalping-strategy.md) |
| 28 | Order Flow Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [video](https://www.youtube.com/watch?v=hvyf6frvCcA) · [summary](glimpse/hvyf6frvCcA.md) | [`order-flow-strategy.md`](todos/order-flow-strategy.md) |
| 32 | Price Action Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [video](https://www.youtube.com/watch?v=70UtrLU6RAg) · [summary](glimpse/70UtrLU6RAg.md) | [`price-action-strategy.md`](todos/price-action-strategy.md) |
| 33 | Price Cycle Continuation & Failed Base Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [video](https://www.youtube.com/watch?v=0_NSmOWVbpA) · [summary](glimpse/0_NSmOWVbpA.md) | [`price-cycle-continuation-failed-base-strategy.md`](todos/price-cycle-continuation-failed-base-strategy.md) |
| 36 | Small-Cap Short Statistics | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [video](https://www.youtube.com/watch?v=52ZsDmFHqyY) · [summary](glimpse/52ZsDmFHqyY.md) | [`small-cap-short-statistics.md`](todos/small-cap-short-statistics.md) |
| 38 | Stage Analysis Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [video](https://www.youtube.com/watch?v=VDK200OHNSo) · [summary](glimpse/VDK200OHNSo.md) | [`stage-analysis-strategy.md`](todos/stage-analysis-strategy.md) |
| 42 | Trading First Principles Framework | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [video](https://www.youtube.com/watch?v=_wpg45NdMkM) · [summary](glimpse/_wpg45NdMkM.md) | [`trading-first-principles-framework.md`](todos/trading-first-principles-framework.md) |

---

*Sources: [chartfanatics.com/strategies](https://www.chartfanatics.com/strategies). Video-only strategies
summarised via [Glimpse](https://glimpse.wozart.com) — see [`README.md`](README.md) for provenance and
[`glimpse.py`](glimpse.py) / [`make_pdfs.py`](make_pdfs.py) to regenerate.*
