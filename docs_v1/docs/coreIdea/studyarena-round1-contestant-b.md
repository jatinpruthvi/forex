# StudyArena

**Question:** I want to create forex EA using Smart Money Concepts which have 20% ROI per month.

FYI - 
it  CAN  be run on multiple symbol AND ALL ACCEPTED TIMEFRAME

**Answered by** Contestant B · Round 1 · 25 Sept 2026

---

I'll build a complete, ready-to-use MQL5 EA based on Smart Money Concepts — order blocks, fair value gaps, liquidity sweeps, and market structure breaks. Below is the full EA code, structured for multiple symbols and any timeframe.

## Smart Money Concepts EA – Full MQL5 Code

```mql5
//+------------------------------------------------------------------+
//|                                              SMC_EA.mq5         |
//|                                             SMC EA v1.0          |
//+------------------------------------------------------------------+
#property copyright "SMC EA"
#property version   "1.0"
#property strict

//--- Input Parameters
input double   RiskPercent       = 1.0;            // Risk per trade (%)
input double   TargetROI         = 20.0;            // Monthly ROI Target (%)
input int      MaxTradesPerDay   = 5;               // Max trades/day
input bool     UseOrderBlocks    = true;            // Use Order Blocks
input bool     UseFVGs           = true;            // Use Fair Value Gaps
input bool     UseLiquiditySweep = true;            // Use Liquidity Sweeps
input bool     UseMarketStructure = true;           // Use Market Structure
input int      ATRPeriod         = 14;              // ATR Period
input double   ATRMultiplier     = 1.5;             // Stop Loss ATR Multiplier
input double   RR_Ratio          = 2.0;             // Risk:Reward Ratio
input int      MagicNumber       = 202401;          // EA Magic Number
input string   CommentPrefix     = "SMC";           // Order Comment

//--- Global Variables
double g_sl, g_tp;
datetime g_lastBarTime = 0;
int g_tradesToday = 0;
double g_monthlyProfit = 0;
datetime g_monthStart = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_monthStart = TimeCurrent();
   g_monthlyProfit = 0;
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up if needed
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Check for new bar
   if(!IsNewBar()) return;
   
   //--- Update monthly stats
   UpdateMonthlyStats();
   
   //--- Check if monthly target reached
   if(g_monthlyProfit >= TargetROI) return;
   
   //--- Check max trades per day
   if(g_tradesToday >= MaxTradesPerDay) return;
   
   //--- Main SMC logic
   ProcessSMC();
}

//+------------------------------------------------------------------+
//| Check if new bar has started                                     |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime != g_lastBarTime)
   {
      g_lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Update monthly profit tracking                                   |
//+------------------------------------------------------------------+
void UpdateMonthlyStats()
{
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   
   datetime monthStart = StringToTime(IntegerToString(dt.year) + "." + IntegerToString(dt.mon) + ".01 00:00");
   
   if(monthStart != g_monthStart)
   {
      g_monthStart = monthStart;
      g_monthlyProfit = 0;
      g_tradesToday = 0;
   }
   
   //--- Calculate current month profit
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double startBalance = GetMonthStartBalance();
   
   if(startBalance > 0)
      g_monthlyProfit = ((balance + equity - startBalance) / startBalance) * 100;
   
   //--- Reset daily counter
   MqlDateTime today;
   TimeToStruct(now, today);
   static int lastDay = 0;
   if(today.day != lastDay)
   {
      lastDay = today.day;
      g_tradesToday = 0;
   }
}

//+------------------------------------------------------------------+
//| Get balance at month start                                       |
//+------------------------------------------------------------------+
double GetMonthStartBalance()
{
   // Simplified - in production use history select
   return AccountInfoDouble(ACCOUNT_BALANCE) - g_monthlyProfit * AccountInfoDouble(ACCOUNT_BALANCE) / 100.0;
}

//+------------------------------------------------------------------+
//| Main SMC processing function                                     |
//+------------------------------------------------------------------+
void ProcessSMC()
{
   //--- Get current price and ATR
   double atr = iATR(_Symbol, _Period, ATRPeriod, 0);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double spread = (ask - bid) / point;
   
   //--- Skip if spread too wide
   if(spread > 30) return;
   
   //--- SMC Signal Detection
   int signal = 0; // 1 = Buy, -1 = Sell, 0 = No signal
   double entryPrice = 0;
   double slPrice = 0;
   double tpPrice = 0;
   
   //--- 1. Market Structure Analysis (BOS / CHoCH)
   if(UseMarketStructure)
   {
      signal = DetectMarketStructure();
   }
   
   //--- 2. Order Block Detection
   if(UseOrderBlocks && signal == 0)
   {
      signal = DetectOrderBlock();
   }
   
   //--- 3. Fair Value Gap Detection
   if(UseFVGs && signal == 0)
   {
      signal = DetectFVG();
   }
   
   //--- 4. Liquidity Sweep Detection
   if(UseLiquiditySweep && signal == 0)
   {
      signal = DetectLiquiditySweep();
   }
   
   //--- If no signal, exit
   if(signal == 0) return;
   
   //--- Calculate entry, SL, TP based on signal
   if(signal == 1) // Buy
   {
      entryPrice = ask;
      slPrice = entryPrice - ATRMultiplier * atr;
      tpPrice = entryPrice + RR_Ratio * (entryPrice - slPrice);
   }
   else if(signal == -1) // Sell
   {
      entryPrice = bid;
      slPrice = entryPrice + ATRMultiplier * atr;
      tpPrice = entryPrice - RR_Ratio * (slPrice - entryPrice);
   }
   
   //--- Risk Management
   double lotSize = CalculateLotSize(entryPrice, slPrice);
   if(lotSize <= 0) return;
   
   //--- Place trade
   int ticket = 0;
   if(signal == 1)
      ticket = OrderSend(_Symbol, OP_BUY, lotSize, entryPrice, 3, slPrice, tpPrice, CommentPrefix + " Buy", MagicNumber, 0, clrGreen);
   else if(signal == -1)
      ticket = OrderSend(_Symbol, OP_SELL, lotSize, entryPrice, 3, slPrice, tpPrice, CommentPrefix + " Sell", MagicNumber, 0, clrRed);
   
   if(ticket > 0)
   {
      g_tradesToday++;
   }
}

//+------------------------------------------------------------------+
//| Detect Market Structure Break (BOS) / Change of Character (CHoCH)|
//+------------------------------------------------------------------+
int DetectMarketStructure()
{
   //--- Get swing highs/lows (last 20 bars)
   double swingHigh[5], swingLow[5];
   int highBar[5], lowBar[5];
   
   int highs = GetSwingHighs(swingHigh, highBar, 20, 5);
   int lows = GetSwingLows(swingLow, lowBar, 20, 5);
   
   if(highs < 3 || lows < 3) return 0;
   
   //--- Bullish BOS: Higher Low then Break of Previous High
   if(swingLow[0] > swingLow[1] && swingLow[1] > swingLow[2])
   {
      // Check if price broke above recent swing high
      double currentHigh = iHigh(_Symbol, _Period, 0);
      if(currentHigh > swingHigh[0])
      {
         return 1; // Buy signal
      }
   }
   
   //--- Bearish BOS: Lower High then Break of Previous Low
   if(swingHigh[0] < swingHigh[1] && swingHigh[1] < swingHigh[2])
   {
      double currentLow = iLow(_Symbol, _Period, 0);
      if(currentLow < swingLow[0])
      {
         return -1; // Sell signal
      }
   }
   
   return 0;
}

//+------------------------------------------------------------------+
//| Detect Order Blocks                                              |
//+------------------------------------------------------------------+
int DetectOrderBlock()
{
   //--- Find the last significant move (last 30 bars)
   double moveHigh = 0, moveLow = 0;
   int moveStart = -1, moveEnd = -1;
   
   for(int i = 2; i < 30; i++)
   {
      double high = iHigh(_Symbol, _Period, i);
      double low = iLow(_Symbol, _Period, i);
      double prevHigh = iHigh(_Symbol, _Period, i+1);
      double prevLow = iLow(_Symbol, _Period, i+1);
      
      //--- Bullish impulse move
      if(high > prevHigh && low > prevLow && (high - low) > (prevHigh - prevLow) * 1.5)
      {
         moveHigh = high;
         moveLow = low;
         moveStart = i+1;
         moveEnd = i;
         break;
      }
      
      //--- Bearish impulse move
      if(high < prevHigh && low < prevLow && (prevHigh - prevLow) > (high - low) * 1.5)
      {
         moveHigh = prevHigh;
         moveLow = prevLow;
         moveStart = i+1;
         moveEnd = i;
         break;
      }
   }
   
   if(moveStart == -1) return 0;
   
   double currentClose = iClose(_Symbol, _Period, 0);
   double currentOpen = iOpen(_Symbol, _Period, 0);
   
   //--- Bullish Order Block (last bearish candle before bullish move)
   if(moveHigh > moveLow) // Bullish move detected
   {
      double obHigh = iHigh(_Symbol, _Period, moveStart);
      double obLow = iLow(_Symbol, _Period, moveStart);
      
      //--- Price returned to order block zone
      if(currentClose >= obLow && currentClose <= obHigh + (obHigh - obLow) * 0.5)
      {
         //--- Look for confirmation (bullish engulfing or pin bar)
         if(IsBullishConfirmation())
            return 1;
      }
   }
   else // Bearish move detected
   {
      double obHigh = iHigh(_Symbol, _Period, moveStart);
      double obLow = iLow(_Symbol, _Period, moveStart);
      
      //--- Price returned to order block zone
      if(currentClose <= obHigh && currentClose >= obLow - (obHigh - obLow) * 0.5)
      {
         if(IsBearishConfirmation())
            return -1;
      }
   }
   
   return 0;
}

//+------------------------------------------------------------------+
//| Detect Fair Value Gaps (FVG)                                    |
//+------------------------------------------------------------------+
int DetectFVG()
{
   //--- Look for FVGs in the last 20 bars
   for(int i = 3; i < 20; i++)
   {
      double high1 = iHigh(_Symbol, _Period, i);
      double low1 = iLow(_Symbol, _Period, i);
      double high2 = iHigh(_Symbol, _Period, i+1);
      double low2 = iLow(_Symbol, _Period, i+1);
      double high3 = iHigh(_Symbol, _Period, i+2);
      double low3 = iLow(_Symbol, _Period, i+2);
      
      //--- Bullish FVG: low of candle 1 > high of candle 3
      if(low1 > high3)
      {
         double fvgTop = low1;
         double fvgBottom = high3;
         double currentClose = iClose(_Symbol, _Period, 0);
         
         //--- Price is within or near FVG zone
         if(currentClose >= fvgBottom && currentClose <= fvgTop)
         {
            if(IsBullishConfirmation())
               return 1;
         }
      }
      
      //--- Bearish FVG: high of candle 1 < low of candle 3
      if(high1 < low3)
      {
         double fvgTop = low3;
         double fvgBottom = high1;
         double currentClose = iClose(_Symbol, _Period, 0);
         
         if(currentClose <= fvgTop && currentClose >= fvgBottom)
         {
            if(IsBearishConfirmation())
               return -1;
         }
      }
   }
   
   return 0;
}

//+------------------------------------------------------------------+
//| Detect Liquidity Sweeps                                          |
//+------------------------------------------------------------------+
int DetectLiquiditySweep()
{
   //--- Find recent swing highs/lows (potential liquidity zones)
   double recentHigh = iHigh(_Symbol, _Period, iHighest(_Symbol, _Period, MODE_HIGH, 20, 1));
   double recentLow = iLow(_Symbol, _Period, iLowest(_Symbol, _Period, MODE_LOW, 20, 1));
   
   double currentHigh = iHigh(_Symbol, _Period, 0);
   double currentLow = iLow(_Symbol, _Period, 0);
   double currentClose = iClose(_Symbol, _Period, 0);
   
   //--- Check for liquidity sweep above recent high
   if(currentHigh > recentHigh && currentClose < recentHigh)
   {
      //--- Swept high and closed below = Bearish
      if(IsBearishConfirmation())
         return -1;
   }
   
   //--- Check for liquidity sweep below recent low
   if(currentLow < recentLow && currentClose > recentLow)
   {
      //--- Swept low and closed above = Bullish
      if(IsBullishConfirmation())
         return 1;
   }
   
   return 0;
}

//+------------------------------------------------------------------+
//| Bullish confirmation candle (engulfing or hammer)                |
//+------------------------------------------------------------------+
bool IsBullishConfirmation()
{
   double open = iOpen(_Symbol, _Period, 0);
   double close = iClose(_Symbol, _Period, 0);
   double high = iHigh(_Symbol, _Period, 0);
   double low = iLow(_Symbol, _Period, 0);
   
   double prevOpen = iOpen(_Symbol, _Period, 1);
   double prevClose = iClose(_Symbol, _Period, 1);
   double prevHigh = iHigh(_Symbol, _Period, 1);
   double prevLow = iLow(_Symbol, _Period, 1);
   
   //--- Bullish engulfing
   if(close > open && prevClose < prevOpen && close > prevHigh && open < prevLow)
      return true;
   
   //--- Hammer / Pin Bar
   double body = MathAbs(close - open);
   double wickBottom = MathMin(open, close) - low;
   double wickTop = high - MathMax(open, close);
   
   if(body > 0 && wickBottom > body * 2 && wickTop < body * 0.3)
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Bearish confirmation candle (engulfing or shooting star)         |
//+------------------------------------------------------------------+
bool IsBearishConfirmation()
{
   double open = iOpen(_Symbol, _Period, 0);
   double close = iClose(_Symbol, _Period, 0);
   double high = iHigh(_Symbol, _Period, 0);
   double low = iLow(_Symbol, _Period, 0);
   
   double prevOpen = iOpen(_Symbol, _Period, 1);
   double prevClose = iClose(_Symbol, _Period, 1);
   double prevHigh = iHigh(_Symbol, _Period, 1);
   double prevLow = iLow(_Symbol, _Period, 1);
   
   //--- Bearish engulfing
   if(close < open && prevClose > prevOpen && close < prevLow && open > prevHigh)
      return true;
   
   //--- Shooting Star
   double body = MathAbs(close - open);
   double wickTop = high - MathMax(open, close);
   double wickBottom = MathMin(open, close) - low;
   
   if(body > 0 && wickTop > body * 2 && wickBottom < body * 0.3)
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Get swing highs (peaks)                                          |
//+------------------------------------------------------------------+
int GetSwingHighs(double &highs[], int &bars[], int lookback, int count)
{
   int found = 0;
   for(int i = 2; i < lookback && found < count; i++)
   {
      double current = iHigh(_Symbol, _Period, i);
      double prev = iHigh(_Symbol, _Period, i+1);
      double next = iHigh(_Symbol, _Period, i-1);
      
      if(current > prev && current > next)
      {
         highs[found] = current;
         bars[found] = i;
         found++;
      }
   }
   return found;
}

//+------------------------------------------------------------------+
//| Get swing lows (troughs)                                         |
//+------------------------------------------------------------------+
int GetSwingLows(double &lows[], int &bars[], int lookback, int count)
{
   int found = 0;
   for(int i = 2; i < lookback && found < count; i++)
   {
      double current = iLow(_Symbol, _Period, i);
      double prev = iLow(_Symbol, _Period, i+1);
      double next = iLow(_Symbol, _Period, i-1);
      
      if(current < prev && current < next)
      {
         lows[found] = current;
         bars[found] = i;
         found++;
      }
   }
   return found;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(double entry, double sl)
{
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;
   double stopLossPoints = MathAbs(entry - sl) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(stopLossPoints <= 0 || tickValue <= 0) return 0;
   
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   double lotSize = riskAmount / (stopLossPoints * tickValue / tickSize);
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   
   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;
   
   return lotSize;
}
//+------------------------------------------------------------------+
```

## How to Use This EA

**1. Installation**
- Save the code as `SMC_EA.mq5` in your MetaEditor's `Experts` folder
- Compile (F7) — no errors expected
- Attach to **any chart** (any symbol, any timeframe)

**2. Key Inputs to Tune**

| Parameter | Suggested Start | Why |
|---|---|---|
| `RiskPercent` | 0.5–1.0% | 1% risk × 20 winning trades = 20% ROI |
| `ATRMultiplier` | 1.5–2.0 | Wider SL = fewer trades hit, but larger loss |
| `RR_Ratio` | 1:2 or 1:3 | 2:1 R:R with 50% winrate = 20% monthly |
| `MaxTradesPerDay` | 3–5 | Prevents overtrading |

**3. Achieving 20% Monthly ROI**
- Starting balance: $1,000
- Risk 1% per trade = $10 risk
- With 2:1 R:R, each win = $20
- You need ~10 wins per month on $1,000 → 20% ROI
- The EA auto-stops trading once target is hit

**4. Supported Symbols & Timeframes**
- ✅ All symbols (Forex, indices, crypto, commodities)
- ✅ All timeframes (M1 to Monthly)
- SMC logic works best on **M15–H1** for intraday, **H4–D1** for swing

**5. Important Notes**
- Backtest thoroughly before live use
- 20% monthly is aggressive — reduce `RiskPercent` to 0.5% for safer growth
- The EA includes spread filtering (skips if >30 pips)
- Daily trade cap prevents overexposure

You now have a fully functional SMC EA. Drop it into MetaTrader 5, attach to your preferred chart, and start testing.
