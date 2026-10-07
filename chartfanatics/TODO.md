# ChartFanatics — Strategy Work Board

**47 strategies** archived in this folder (32 with a published PDF, 15 video-only
with a Glimpse summary). Every strategy has a work card in [`todos/`](todos/) covering the same
8 stages, from "read the source" to "demo / forward".

**Cards:** ✅ 0 done · 🟡 23 in progress ·
⬜ 24 not started

**EAs built:** 23/47 — see [`mql5-eas/`](mql5-eas/) (magic block 3201-3247)

**Loop:** 22 awaiting human · 25 planned — see [`LOOP.md`](LOOP.md)

**Stages ticked:** 115/376 (31%)
`▰▰▰▰▰▰▰▰▰▰▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱`

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

| # | Strategy | Status | Progress | Source | EA | Card |
|---|---|---|---|---|---|---|
| 01 | 5 Stage Trading Framework | 🟡 wip | `▰▰▰▰▰▱▱▱` 5/8 | [PDF](pdf/5-stage-trading-framework.pdf) 7.0 MB | [`Stage_Guardrails.mq5`](mql5-eas/EA_CF_Stage_Guardrails.mq5) mag 3207 (monitor) | [`5-stage-trading-framework.md`](todos/5-stage-trading-framework.md) |
| 04 | AMD Model | 🟡 wip | `▰▰▰▰▰▱▱▱` 5/8 | [PDF](pdf/amd-model.pdf) 25.8 MB | [`AMD_Model.mq5`](mql5-eas/EA_CF_AMD_Model.mq5) mag 3201 | [`amd-model.md`](todos/amd-model.md) |
| 05 | Auction Market Strategy | 🟡 wip | `▰▰▰▰▰▱▱▱` 5/8 | [PDF](pdf/auction-market-strategy.pdf) 5.6 MB | [`AuctionMarket.mq5`](mql5-eas/EA_CF_AuctionMarket.mq5) mag 3210 | [`auction-market-strategy.md`](todos/auction-market-strategy.md) |
| 06 | Auction Market Theory Strategy | 🟡 wip | `▰▰▰▰▰▱▱▱` 5/8 | [PDF](pdf/auction-market-theory-strategy.pdf) 12.4 MB | [`AuctionMarketTheory.mq5`](mql5-eas/EA_CF_AuctionMarketTheory.mq5) mag 3211 | [`auction-market-theory-strategy.md`](todos/auction-market-theory-strategy.md) |
| 07 | Break & Retest | 🟡 wip | `▰▰▰▰▰▱▱▱` 5/8 | [PDF](pdf/break-retest.pdf) 20.9 MB | [`Break_Retest.mq5`](mql5-eas/EA_CF_Break_Retest.mq5) mag 3205 | [`break-retest.md`](todos/break-retest.md) |
| 08 | Episodic Pivot Strategy | 🟡 wip | `▰▰▰▰▰▱▱▱` 5/8 | [PDF](pdf/episodic-pivot-strategy.pdf) 26.4 MB | [`EpisodicPivot.mq5`](mql5-eas/EA_CF_EpisodicPivot.mq5) mag 3212 | [`episodic-pivot-strategy.md`](todos/episodic-pivot-strategy.md) |
| 10 | First Red Day | 🟡 wip | `▰▰▰▰▰▱▱▱` 5/8 | [PDF](pdf/first-red-day.pdf) 29.8 MB | [`FirstRedDay.mq5`](mql5-eas/EA_CF_FirstRedDay.mq5) mag 3214 | [`first-red-day.md`](todos/first-red-day.md) |
| 11 | First Red Day Strategy | 🟡 wip | `▰▰▰▰▰▱▱▱` 5/8 | [PDF](pdf/first-red-day-strategy.pdf) 4.3 MB | [`FirstRedDayPro.mq5`](mql5-eas/EA_CF_FirstRedDayPro.mq5) mag 3215 | [`first-red-day-strategy.md`](todos/first-red-day-strategy.md) |
| 12 | Full Psychology MasterClass | 🟡 wip | `▰▰▰▰▰▱▱▱` 5/8 | [PDF](pdf/full-psychology-masterclass.pdf) 38.3 MB | [`PsychGuardrails.mq5`](mql5-eas/EA_CF_PsychGuardrails.mq5) mag 3216 (monitor) | [`full-psychology-masterclass.md`](todos/full-psychology-masterclass.md) |
| 13 | Futures Trading Strategy | 🟡 wip | `▰▰▰▰▰▱▱▱` 5/8 | [PDF](pdf/futures-trading-strategy.pdf) 5.3 MB | [`FuturesStrategy.mq5`](mql5-eas/EA_CF_FuturesStrategy.mq5) mag 3217 | [`futures-trading-strategy.md`](todos/futures-trading-strategy.md) |
| 16 | Intraday Liquidity & Volatility Model | 🟡 wip | `▰▰▰▰▰▱▱▱` 5/8 | [PDF](pdf/intraday-liquidity-volatility-model.pdf) 2.9 MB | [`Intraday_Liquidity.mq5`](mql5-eas/EA_CF_Intraday_Liquidity.mq5) mag 3206 | [`intraday-liquidity-volatility-model.md`](todos/intraday-liquidity-volatility-model.md) |
| 18 | Liquidity Strategy | 🟡 wip | `▰▰▰▰▰▱▱▱` 5/8 | [PDF](pdf/liquidity-strategy.pdf) 37.7 MB | [`LiquidityStrategy.mq5`](mql5-eas/EA_CF_LiquidityStrategy.mq5) mag 3221 | [`liquidity-strategy.md`](todos/liquidity-strategy.md) |
| 19 | Low Volume Node | 🟡 wip | `▰▰▰▰▰▱▱▱` 5/8 | [PDF](pdf/low-volume-node.pdf) 3.9 MB | [`LowVolumeNode.mq5`](mql5-eas/EA_CF_LowVolumeNode.mq5) mag 3222 | [`low-volume-node.md`](todos/low-volume-node.md) |
| 20 | Market Auction theory | 🟡 wip | `▰▰▰▰▰▱▱▱` 5/8 | [PDF](pdf/market-auction-theory.pdf) 2.1 MB | [`MarketAuctionTheory.mq5`](mql5-eas/EA_CF_MarketAuctionTheory.mq5) mag 3223 | [`market-auction-theory.md`](todos/market-auction-theory.md) |
| 21 | Market DNA Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/market-dna-strategy.pdf) 30.9 MB | _—_ | [`market-dna-strategy.md`](todos/market-dna-strategy.md) |
| 22 | Mean Reversion Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/mean-reversion-strategy.pdf) 10.1 MB | _—_ | [`mean-reversion-strategy.md`](todos/mean-reversion-strategy.md) |
| 23 | Measured Move Trend Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/measured-move-trend-strategy.pdf) 9.5 MB | _—_ | [`measured-move-trend-strategy.md`](todos/measured-move-trend-strategy.md) |
| 27 | Options Trading Masterclass | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/options-trading-masterclass.pdf) 3.5 MB | _—_ | [`options-trading-masterclass.md`](todos/options-trading-masterclass.md) |
| 29 | OrderFlow Trading Masterclass | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/orderflow-trading-masterclass.pdf) 16.9 MB | _—_ | [`orderflow-trading-masterclass.md`](todos/orderflow-trading-masterclass.md) |
| 30 | Parabolic Short Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/parabolic-short-strategy.pdf) 9.5 MB | _—_ | [`parabolic-short-strategy.md`](todos/parabolic-short-strategy.md) |
| 31 | PO3, OTE + ADR | 🟡 wip | `▰▰▰▰▰▱▱▱` 5/8 | [PDF](pdf/po3-ote-adr.pdf) 32.8 MB | [`PO3_OTE_ADR.mq5`](mql5-eas/EA_CF_PO3_OTE_ADR.mq5) mag 3204 | [`po3-ote-adr.md`](todos/po3-ote-adr.md) |
| 34 | Real Simple Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/real-simple-strategy.pdf) 34.0 MB | _—_ | [`real-simple-strategy.md`](todos/real-simple-strategy.md) |
| 35 | Shorting Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/shorting-strategy.pdf) 31.4 MB | _—_ | [`shorting-strategy.md`](todos/shorting-strategy.md) |
| 37 | SMT Divergence+PO3 | 🟡 wip | `▰▰▰▰▰▱▱▱` 5/8 | [PDF](pdf/smt-divergence-po3.pdf) 4.1 MB | [`SMT_PO3.mq5`](mql5-eas/EA_CF_SMT_PO3.mq5) mag 3203 | [`smt-divergence-po3.md`](todos/smt-divergence-po3.md) |
| 39 | Structure + OTE | 🟡 wip | `▰▰▰▰▰▱▱▱` 5/8 | [PDF](pdf/structure-ote.pdf) 6.9 MB | [`Structure_OTE.mq5`](mql5-eas/EA_CF_Structure_OTE.mq5) mag 3202 | [`structure-ote.md`](todos/structure-ote.md) |
| 40 | Support and Resistance | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/support-and-resistance.pdf) 7.7 MB | _—_ | [`support-and-resistance.md`](todos/support-and-resistance.md) |
| 41 | The Vix Futures Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/the-vix-futures-strategy.pdf) 3.6 MB | _—_ | [`the-vix-futures-strategy.md`](todos/the-vix-futures-strategy.md) |
| 43 | Trendline Break Pocket Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/trendline-break-pocket-strategy.pdf) 33.0 MB | _—_ | [`trendline-break-pocket-strategy.md`](todos/trendline-break-pocket-strategy.md) |
| 44 | Trendline Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/trendline-strategy.pdf) 8.7 MB | _—_ | [`trendline-strategy.md`](todos/trendline-strategy.md) |
| 45 | Unique High RR | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/unique-high-rr.pdf) 9.9 MB | _—_ | [`unique-high-rr.md`](todos/unique-high-rr.md) |
| 46 | Universal Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/universal-strategy.pdf) 3.3 MB | _—_ | [`universal-strategy.md`](todos/universal-strategy.md) |
| 47 | Volume Profile Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [PDF](pdf/volume-profile-strategy.pdf) 34.7 MB | _—_ | [`volume-profile-strategy.md`](todos/volume-profile-strategy.md) |

## Video-only — no published PDF (15)

| # | Strategy | Status | Progress | Source | EA | Card |
|---|---|---|---|---|---|---|
| 02 | 80/20 Nasdaq Strategy | 🟡 wip | `▰▰▰▰▰▱▱▱` 5/8 | [video](https://www.youtube.com/watch?v=jsUTbjwpFVk) · [summary](glimpse/jsUTbjwpFVk.md) | [`8020NasdaqStrategy.mq5`](mql5-eas/EA_CF_8020NasdaqStrategy.mq5) mag 3208 | [`80-20-nasdaq-strategy.md`](todos/80-20-nasdaq-strategy.md) |
| 03 | Algorithmic Strategy | 🟡 wip | `▰▰▰▰▰▱▱▱` 5/8 | [video](https://www.youtube.com/watch?v=TyHTEtArsS4) · [summary](glimpse/TyHTEtArsS4.md) | [`AlgoPortfolioMonitor.mq5`](mql5-eas/EA_CF_AlgoPortfolioMonitor.mq5) mag 3209 (monitor) | [`algorithmic-strategy.md`](todos/algorithmic-strategy.md) |
| 09 | Fair Pricing Theory Strategy | 🟡 wip | `▰▰▰▰▰▱▱▱` 5/8 | [video](https://www.youtube.com/watch?v=KHEQ5g55dQ4) · [summary](glimpse/KHEQ5g55dQ4.md) | [`FairPricingTheory.mq5`](mql5-eas/EA_CF_FairPricingTheory.mq5) mag 3213 | [`fair-pricing-theory-strategy.md`](todos/fair-pricing-theory-strategy.md) |
| 14 | Institutional Options Flow & Gamma Reversal Strategy | 🟡 wip | `▰▰▰▰▰▱▱▱` 5/8 | [video](https://www.youtube.com/watch?v=35cyqDz-ej8) · [summary](glimpse/35cyqDz-ej8.md) | [`GammaReversal.mq5`](mql5-eas/EA_CF_GammaReversal.mq5) mag 3218 | [`institutional-options-flow-gamma-reversal-strategy.md`](todos/institutional-options-flow-gamma-reversal-strategy.md) |
| 15 | Institutional Strategy Development Framework | 🟡 wip | `▰▰▰▰▰▱▱▱` 5/8 | [video](https://www.youtube.com/watch?v=yW6c0K8uGvw) · [summary](glimpse/yW6c0K8uGvw.md) | [`InstFramework.mq5`](mql5-eas/EA_CF_InstFramework.mq5) mag 3219 | [`institutional-strategy-development-framework.md`](todos/institutional-strategy-development-framework.md) |
| 17 | Liquidity Inversion Model | 🟡 wip | `▰▰▰▰▰▱▱▱` 5/8 | [video](https://www.youtube.com/watch?v=UIGZtoGGPH4) · [summary](glimpse/UIGZtoGGPH4.md) | [`LiquidityInversion.mq5`](mql5-eas/EA_CF_LiquidityInversion.mq5) mag 3220 | [`liquidity-inversion-model.md`](todos/liquidity-inversion-model.md) |
| 24 | Momentum Model Performance Development | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [video](https://www.youtube.com/watch?v=WDdvnd9vLbM) · [summary](glimpse/WDdvnd9vLbM.md) | _—_ | [`momentum-model-performance-development.md`](todos/momentum-model-performance-development.md) |
| 25 | Nasdaq ICT and Order Flow Scalping Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [video](https://www.youtube.com/watch?v=KkTTCKr-3Ew) · [summary](glimpse/KkTTCKr-3Ew.md) | _—_ | [`nasdaq-ict-and-order-flow-scalping-strategy.md`](todos/nasdaq-ict-and-order-flow-scalping-strategy.md) |
| 26 | NQ Liquidity Sweep & Reversal Scalping Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [video](https://www.youtube.com/watch?v=-kGVL93XfyE) · [summary](glimpse/-kGVL93XfyE.md) | _—_ | [`nq-liquidity-sweep-reversal-scalping-strategy.md`](todos/nq-liquidity-sweep-reversal-scalping-strategy.md) |
| 28 | Order Flow Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [video](https://www.youtube.com/watch?v=hvyf6frvCcA) · [summary](glimpse/hvyf6frvCcA.md) | _—_ | [`order-flow-strategy.md`](todos/order-flow-strategy.md) |
| 32 | Price Action Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [video](https://www.youtube.com/watch?v=70UtrLU6RAg) · [summary](glimpse/70UtrLU6RAg.md) | _—_ | [`price-action-strategy.md`](todos/price-action-strategy.md) |
| 33 | Price Cycle Continuation & Failed Base Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [video](https://www.youtube.com/watch?v=0_NSmOWVbpA) · [summary](glimpse/0_NSmOWVbpA.md) | _—_ | [`price-cycle-continuation-failed-base-strategy.md`](todos/price-cycle-continuation-failed-base-strategy.md) |
| 36 | Small-Cap Short Statistics | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [video](https://www.youtube.com/watch?v=52ZsDmFHqyY) · [summary](glimpse/52ZsDmFHqyY.md) | _—_ | [`small-cap-short-statistics.md`](todos/small-cap-short-statistics.md) |
| 38 | Stage Analysis Strategy | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [video](https://www.youtube.com/watch?v=VDK200OHNSo) · [summary](glimpse/VDK200OHNSo.md) | _—_ | [`stage-analysis-strategy.md`](todos/stage-analysis-strategy.md) |
| 42 | Trading First Principles Framework | ⬜ todo | `▱▱▱▱▱▱▱▱` 0/8 | [video](https://www.youtube.com/watch?v=_wpg45NdMkM) · [summary](glimpse/_wpg45NdMkM.md) | _—_ | [`trading-first-principles-framework.md`](todos/trading-first-principles-framework.md) |

---

*Sources: [chartfanatics.com/strategies](https://www.chartfanatics.com/strategies). Video-only strategies
summarised via [Glimpse](https://glimpse.wozart.com) — see [`README.md`](README.md) for provenance and
[`glimpse.py`](glimpse.py) / [`make_pdfs.py`](make_pdfs.py) to regenerate.*
