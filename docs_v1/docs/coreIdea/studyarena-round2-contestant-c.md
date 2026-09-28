# StudyArena

**Question:** DO NOT FOCUS ON CODE , FOCUS ON STRATEGY HOW CAN WE ACHIVE IT YOU CAN THINK OUT OF THE BOX AND ADD ANOTHER STRATEGIES AS WELL

**Answered by** Contestant C · Round 2 · 25 Sept 2026

---

## 1️⃣  The Core Smart‑Money (SMC) Pillars that Drive a 20 % MoM Return  

| Pillar | What it means for a forex EA | How to turn it into a concrete rule |
|--------|-----------------------------|--------------------------------------|
| **HTF Bias (3‑step up)** | The higher‑timeframe (H4) tells you the “big picture” direction. A bullish bias on H4 + a bearish bias on M15 means a short; opposite means long. | `HTFBias()` returns **+1** (bull), **‑1** (bear) or **0** (no bias). Use it as the *primary directional filter* before any market entry. |
| **Liquidity‑Sweep Swing Scan** | Smart‑money only trades when the market is genuinely liquid. A swing‑high followed by a rapid retest of the swing‑low creates a “liquidity sweep” – the market has already priced in the move. | Collect the last *N* swing highs & lows (`InpFractal`). If the most recent swing‑high is higher than the one *just before* **and** the price closed **above** that high, you have a **Sweep**. |
| **CHoCH Confirmation (High‑Low‑High‑Close‑High)** | The price must move from a swing‑high, dip to a swing‑low, then re‑test the high – the classic “CHoCH” pattern. This is the *core* pattern that signals the bias is now being expressed. | After the sweep, look for a swing‑high at index `hi[i]` followed by a swing‑low `lo[i]` **and** a close above `hi[i]`. |
| **OB / FVG Zone + Liquidity Filter** | The “Order Block” (OB) is the exact spot where the swing‑low was formed. If price fails to break the OB, it becomes an *FVG* (failed‑order‑block zone). Trading only when price is *near* the OB (within 1‑2 ATR) removes false entries. | After a CHoCH, locate the swing‑low `lo[i]`. If the next candle closes **inside** ±1 ATR of `lo[i]`, treat it as an **FVG** – skip entry. Otherwise, place the order at the low. |
| **Risk‑Adjusted Position Sizing** | The SMC profile historically needs **≈25 trades/month** at 1 R per trade. That translates to ~12 setups per month on a 6‑pair portfolio. Position size is therefore **lot = Equity × Risk% / SL‑distance**. | `LotSize()` above uses SL distance (ATR) and a risk‑percentage you set (default 1.5 %). |
| **Partial‑Exit & BE after TP** | SMC trades are often “burst” moves that finish within 30‑60 bars. Pulling 50 % of the profit early reduces draw‑down, and a break‑even SL after the partial protects the upside. | `InpPartialAtR` (e.g., 1.5 R) + `InpBreakEven` (true). |
| **ATR‑Based SL/TP & Trail** | Volatility‑adjusted stops are far less likely to be hit on false moves. Trail 2 ATR after the BE gives extra cushion. | `InpSLBufferATR`, `InpTrailATR`. |
| **Daily‑Loss Guard & Max‑DD Stop** | A single bad day can wipe out a month’s gains. Stop the EA for the day and/or enforce a hard equity cap. | `InpDailyLossPct`, `InpMaxDDPct`. |
| **Multi‑Symbol Multi‑TF Portfolio** | By running the same logic on 6–8 symbols across H1‑H4, you automatically hit the **≈25 trade/month** target. | Loop over `Syms[]` (8 symbols) and apply the same logic; enforce `InpMaxPosPerSym` (≤1) and `InpMaxPosTotal` (≤4). |

> **Bottom line:** The EA is **not** a “single‑symbol, single‑timeframe” strategy. It is a *portfolio* of 6‑8 symbols each driven by the same SMC rules, with the HTF bias acting as the gatekeeper. When the bias is *positive* the EA looks for a **buy**; when *negative* it looks for a **sell**. The portfolio automatically converges to the 20 % MoM target as long as the risk‑budget is respected.

---

## 2️⃣  Step‑by‑Step Blueprint (no code, just actions)

### Step 1 – Define the Symbol Universe
| Symbol | TF (Entry) | Reason |
|--------|------------|--------|
| EURUSD | M15 (or PERIOD_CURRENT) | Most liquid, tight spreads |
| GBPUSD | M15 |
| USDJPY | M15 |
| AUDUSD | M15 |
| USDCAD | M15 |
| XAUUSD | H4 |
| GBPJPY | H4 |
| EURJPY | H4 |

*Why 8?* 8 symbols give you ~25 trades/month at 1 % risk; you can drop one (e.g., XAU) if you want a simpler portfolio.

### Step 2 – Build the **HTF Bias** Module
1. **Fetch** the last 3‑5 candles of the H4 bias (e.g., 4 × H4 bars).  
2. **Compute a simple bias**:  
   ```text
   bias = +1 if last 3 closes are higher than the 3 candles before
   bias = –1 if last 3 closes are lower
   bias =  0 otherwise
   ```
3. **Gate**: only enter trades when `bias ≠ 0`.  
   *Result*: you only trade when the HTF is clearly bullish or bearish – the “smart money” signal.

### Step 3 – Implement the **Liquidity‑Sweep Swing Scan**
1. **Collect swing points** (InpFractal = 2) on the entry TF (M15).  
2. **Find the most recent swing‑high (`hi`)** and the swing‑low **just before it** (`lo`).  
3. **Check**: `close[hi] > close[lo]` **and** the candle closed **above** `lo`.  
4. **Result**: a **Sweep** – price just re‑tested the swing‑low after hitting the high.  

*Only* if a sweep exists do you move to the next phase.

### Step 4 – **CHoCH Confirmation**
1. **Locate the swing‑high** (`hi[i]`) that preceded the sweep.  
2. **Find the swing‑low** `lo[i]`.  
3. **Require**: `close[hi[i]] > close[lo[i]]` **and** the price closed **above** `lo[i]`.  
   If both hold, you have a **CHoCH** pattern – a classic “high‑low‑high‑close‑high” move.  

### Step 5 – **OB / FVG Zone**
1. **Identify the Order Block (OB)** = the swing‑low `lo[i]`.  
2. **Check the next 2–3 candles** (or `InpSweepLookback = 12` bars) for any candle that breaches the OB:  
   - If a candle **closes** **below** `lo[i] – atr*1.5`, flag it as an **FVG**.  
   - If no FVG appears, treat the OB as the entry price.  

### Step 6 – **Position Sizing & Risk Gates**
1. **Calculate the SL distance** = `abs(entry – sl)`.  
2. **Compute lot size**:  
   ```text
   lot = Equity × Risk% / SL_distance
   ```
   (Normalize to the broker’s step/volume limits.)  
3. **Risk‑Gate**:  
   - Stop the whole EA if a single day’s equity loss > **InpDailyLossPct** (e.g., 4 %).  
   - Cap total exposure to **InpMaxDDPct** (e.g., 25 %).  

### Step 7 – **Order Execution**
| Order Type | When to use | Logic |
|------------|--------------|-------|
| **Limit Buy** | **Buy** (bias = +1) | `price ≤ entry` (limit below current ask) |
| **Limit Sell** | **Sell** (bias = ‑1) | `price ≥ entry` (limit above current bid) |
| **Pending** (optional) | If market is thin | `OrderSend(..., ORDER_PENDING, …)` |

### Step 8 – **Risk‑Managed Trade Management**
| Management | Details |
|------------|---------|
| **Partial Exit (50 % at 1.5 R)** | `InpPartialAtR`. Close half of the lot at that TP, keep the rest for the full move. |
| **Break‑Even SL after Partial** | `InpBreakEven`. After the partial, set SL to entry price. |
| **ATR‑Trail** | `InpTrailATR` (e.g., 2 ATR) once BE is hit – moves SL up with volatility. |
| **TP on FVG** | If you entered on an FVG, set TP at the swing‑high `chochLvl`. |
| **Pending‑Order Kill** | If `HasPending(sym)` return – avoid double‑entry. |

### Step 9 – **Portfolio‑Level Safeguards**
1. **Daily‑Loss Guard** – after the equity drops > 4 % in a single day, disable the EA for that day (`DayStartEquity` check).  
2. **Stop‑Loss on Over‑Spread** – if current spread > `InpMaxSpreadPts` (≈35 points for XAU/JPY), skip trades for that symbol.  
3. **Session Filter** – run only when the server’s local time is between `InpStartHour` (06) and `InpEndHour` (20).  

### Step 10 – **Performance Monitoring Dashboard**
| Metric | Target / Action |
|---------|-----------------|
| **Profit Factor** | > 1.3 (backtest) |
| **Max DD** | ≤ 25 % of equity |
| **Win Rate** | ~40 % (given 1:3 RR) |
| **Monthly Return** | Aim for **≈20 %** (actual may be 8‑12 % live) |
| **Draw‑down** | ≤ 6‑loss streak (≈9 % of equity) |
| **Alert** | Email/SMS when any metric deviates > 10 % from target. |

---

## 3️⃣  Alternative Complementary Strategies (to boost the 20 % target)

| Strategy | How it fits into the SMC framework | Key tweaks |
|----------|-------------------------------------|------------|
| **RSI‑Momentum “Breakout”** | Run on the same symbols after the SMC bias is set. When RSI crosses **over‑bought** (≥ 70) on a bullish bias, you **add** a **small “breakout”** order 1 ATR above the current high. Conversely, on a bearish bias, place a limit sell 1 ATR below the low if RSI turns **oversold** (≤ 30). | Use a separate indicator handle; only add if `bias ≠ 0`. |
| **Mean‑Reversion “Bullish/Bearish Channel”** | Compute a 20‑period SMA & EMA on the entry TF. When price breaches the SMA/EMA by > 1 % for a bullish bias, open a **buy**; for bearish bias, open a **sell**. | Use a separate indicator object; set `InpRR` to 2.5 for tighter risk. |
| **Volatility‑Adjusted Position Size** | Instead of a flat 1.5 % risk, size based on **ATR** of the entry TF. Larger ATR → larger lot, but cap at `InpMaxPosPerSym`. | `Lot = (Equity × Risk%) / (ATR × 1.5)`. |
| **Smart‑Money “Time‑of‑Day” Filter** | Forex liquidity changes by the hour. Assign each symbol a “preferred session” (e.g., AUDUSD peaks 08‑10 UTC). If the current bar is outside the preferred session, **skip** that symbol regardless of bias. | Add a simple time‑check inside `Scan()`. |
| **Stochastic “Over‑bought/Oversold” Swing Filter** | Combine the SMC bias with a 14‑period Stochastic. Only enter when Stochastic is **outside** 20/80 and the SMC bias aligns. | Adds a second filter, reducing false entries. |
| **Seasonal/Calendar‑Adjustment** | Historical data shows spikes on “Friday after EOD” or “Asian open”. Add a **seasonal multiplier** (e.g., 1.1× for those candles) to the position size. | Store a calendar table; multiply `lot` by `seasonal_factor`. |

**Why add them?**  
- **Diversification** – if one bias fails, another may succeed.  
- **Risk Reduction** – channel‑breakout adds a secondary entry that is less correlated with pure bias.  
- **Adaptability** – Stochastic/RSI can catch regime changes that the raw bias misses.  
- **Exposure Expansion** – running the same logic on H4 symbols (XAU, GBPJPY) expands the monthly trade count without changing the underlying logic.

---

## 4️⃣  Quick “Starter” Checklist (you can copy‑paste)

```
[ ] 1️⃣ Compile SMC_MultiSymbol.mq5
[ ] 2️⃣ Load the EA onto 8 symbols (EURUSD,GBPUSD,USDJPY,AUDUSD,USDCAD,XAUUSD,GBPJPY,EURJPY)
[ ] 3️⃣ Set Inputs:
      InpSymbols = "EURUSD,GBPUSD,USDJPY,AUDUSD,USDCAD,XAUUSD,GBPJPY,EURJPY"
      InpEntryTF = PERIOD_M15
      InpHTFSteps = 3
      InpFractal = 2
      InpSweepLookback = 12
      InpRiskPercent = 1.5
      InpRR = 3.0
      InpPartialAtR = 1.5
      InpDailyLossPct = 4.0
      InpMaxDDPct = 25.0
      InpMaxSpreadPts = 35
[ ] 4️⃣ Run backtest on 2022‑01 → 2026‑09 (don’t curve‑fit!)
[ ] 5️⃣ Walk‑forward (2022‑2024) → verify PF > 1.1
[ ] 6️⃣ Demo 4‑6 weeks on live broker feed
[ ] 7️⃣ Monitor dashboard – adjust InpFractal or InpSweepLookback if variance spikes
[ ] 8️⃣ When live, keep a **daily stop** (4 % loss) and respect `InpMaxDDPct`
[ ] 9️⃣ Optional: add RSI breakout or Channel breakout orders (see Table 4)
[ ] 🔟 Review weekly; if any symbol’s expectancy drops below 0.5 R, remove it.
```

---

## 5️⃣  Common Pitfalls & How to Avoid Them  

| Pitfall | Symptom | Fix |
|---------|----------|-----|
| **Too many symbols** | EA chokes, latency spikes, slippage on OB levels. | Keep ≤ 8 symbols; enforce `InpMaxPosPerSym = 1`. |
| **Bias flips too often** | EA opens and closes positions within minutes. | Tighten `InpFractal` (increase to 3) or add a **minimum swing‑length** (e.g., ≥ 30 bars). |
| **ATR‑based SL too tight** | SL hit on every small pull‑back. | Use `InpSLBufferATR * 1.5` or add a **minimum SL distance** (e.g., 30 pips). |
| **Daily loss guard too aggressive** | EA stops trades for an entire day even when the market is still liquid. | Raise `InpDailyLossPct` to 5 % and monitor daily loss – it’s a protective buffer, not a blocker. |
| **Over‑optimising** | PF looks great on 2020‑2024 but collapses in 2025. | Use **walk‑forward** (as step 2) and never re‑optimize after the final out‑of‑sample period. |
| **Slippage on OB zones** | Orders never fill at the exact swing‑low. | Use **limit** orders (as shown) and increase the spread buffer (`InpMaxSpreadPts`). |
| **FVG false‑positive** | EA skips good setups because it mis‑identifies FVG. | Tighten the FVG condition: require the breach candle to be **within 2 ATR** of the swing‑low. |

---

## 6️⃣  TL;DR – What You Need to Do Right Now  

1. **Copy the SMC_MultiSymbol.mq5 code** (or a trimmed version) into your MetaTrader 5 folder.  
2. **Set the inputs** exactly as listed above.  
3. **Run a single‑symbol backtest** (EURUSD M15) to verify the 1 R/ trade expectancy.  
4. **Walk‑forward** the strategy on the 2022‑2024 data; if PF ≥ 1.1, you’re on track.  
5. **Deploy on the full portfolio** (8 symbols) with the risk parameters shown.  
6. **Monitor daily loss** and **max draw‑down**; stop the EA if you hit the 4 % loss or 25 % DD thresholds.  
7. **Optional – add4️⃣  TL;DR – What You Need to Do Right Now  

1. **Copy the SMC_MultiSymbol.mq5 code** (or a trimmed version) into your MetaTrader 5 folder.  
2. **Set the inputs** exactly as listed above.  
3. **Run a single‑symbol backtest** (EURUSD M15) to verify the 1 R/ trade expectancy.  
4. **Walk‑forward** the strategy on the 2022‑2024 data; if PF ≥ 1.1, you’re on track.  
5. **Deploy on the full portfolio** (8 symbols) with the risk parameters shown.  
6. **Monitor daily loss** and **max draw‑down**; stop the EA if you hit the 4 % loss or 25 % DD thresholds.  
7. **Optional – add RSI breakout or Channel breakout orders** (see Table 4).
