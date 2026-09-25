//+------------------------------------------------------------------+
//|                                          GEMINI_ALPHA_MODULE.mqh |
//|                     Antigravity Advanced Core Strategy Filters   |
//|  Version 1.0 (V2 Alpha Phase)                                    |
//+------------------------------------------------------------------+
#property copyright "Gemini Antigravity"
#property link      ""

//=== ALPHA: 1. Tick Volume Capitulation (For M5 Mean Reversion) ===
input group "=== GEMINI ALPHA: 1. Volume Capitulation (FIVE_M5) ==="
input bool   AInpEnableVolCapitulation  = true;
input double AInpMinTickVolMultiplier   = 2.5; // Tick volume must be 2.5x average
input int    AInpVolAvgPeriod           = 20;  // Moving average period for volume

//=== ALPHA: 2. Volatility Squeeze (For Daily Trend) ===
input group "=== GEMINI ALPHA: 2. Volatility Squeeze (GOLD_SWING) ==="
input bool   AInpEnableVolSqueeze       = true;
input int    AInpSqueezeFastATR         = 14;  // Fast ATR period
input int    AInpSqueezeSlowATR         = 50;  // Slow ATR period
input double AInpSqueezeRatioMax        = 1.0; // Fast/Slow ratio must be <= 1.0

//=== ALPHA: 3. Anchored VWAP (For Intraday Breakout) ===
input group "=== GEMINI ALPHA: 3. Anchored VWAP (TRIAD) ==="
input bool   AInpEnableAnchoredVWAP     = true;

//+------------------------------------------------------------------+
//| 1. Check Volume Capitulation (FIVE_M5_EXHAUST)                   |
//+------------------------------------------------------------------+
bool GeminiAlpha_VolumeCapitulation(string symbol)
  {
   if(!AInpEnableVolCapitulation) return true;
   
   long ticks[];
   ArrayResize(ticks, AInpVolAvgPeriod + 1);
   if(CopyTickVolume(symbol, PERIOD_CURRENT, 1, AInpVolAvgPeriod + 1, ticks) < AInpVolAvgPeriod + 1)
      return true; // fail open
      
   double avg = 0;
   for(int i = 0; i < AInpVolAvgPeriod; i++) avg += (double)ticks[i];
   avg /= (double)AInpVolAvgPeriod;
   
   double current_vol = (double)ticks[AInpVolAvgPeriod];
   
   if(avg > 0 && (current_vol / avg) >= AInpMinTickVolMultiplier)
     {
      Print("[GEMINI ALPHA] Vol Capitulation SUCCESS on ",symbol,": Vol=",current_vol," (",DoubleToString(current_vol/avg,1),"x avg)");
      return true;
     }
     
   Print("[GEMINI ALPHA] Vol Capitulation REJECT on ",symbol,": Vol=",current_vol," (",DoubleToString(current_vol/avg,1),"x avg, need ",AInpMinTickVolMultiplier,")");
   return false;
  }

//+------------------------------------------------------------------+
//| 2. Check Volatility Squeeze (GOLD_SWING)                         |
//+------------------------------------------------------------------+
bool GeminiAlpha_VolatilitySqueeze(string symbol)
  {
   if(!AInpEnableVolSqueeze) return true;
   
   int fast_h = iATR(symbol, PERIOD_CURRENT, AInpSqueezeFastATR);
   int slow_h = iATR(symbol, PERIOD_CURRENT, AInpSqueezeSlowATR);
   if(fast_h == INVALID_HANDLE || slow_h == INVALID_HANDLE) return true;
   
   double f[1], s[1];
   if(CopyBuffer(fast_h, 0, 0, 1, f) < 1 || CopyBuffer(slow_h, 0, 0, 1, s) < 1)
     { IndicatorRelease(fast_h); IndicatorRelease(slow_h); return true; }
     
   IndicatorRelease(fast_h); IndicatorRelease(slow_h);
   
   double ratio = f[0] / s[0];
   if(ratio <= AInpSqueezeRatioMax)
     {
      Print("[GEMINI ALPHA] Vol Squeeze SUCCESS on ",symbol,": Ratio=",DoubleToString(ratio,2));
      return true;
     }
     
   Print("[GEMINI ALPHA] Vol Squeeze REJECT on ",symbol,": Ratio=",DoubleToString(ratio,2)," (Need <=",AInpSqueezeRatioMax,")");
   return false;
  }

//+------------------------------------------------------------------+
//| 3. Check Session-Anchored VWAP (TRIAD)                           |
//+------------------------------------------------------------------+
bool GeminiAlpha_AnchoredVWAP(string symbol, ENUM_ORDER_TYPE order_type, datetime session_start)
  {
   if(!AInpEnableAnchoredVWAP) return true;
   
   // Approximate VWAP since session start using M5 bars
   int bars = iBarShift(symbol, PERIOD_M5, session_start);
   if(bars <= 0 || bars > 288) return true; // fallback if invalid or spanning days
   
   MqlRates rates[];
   if(CopyRates(symbol, PERIOD_M5, 0, bars, rates) < bars) return true;
   
   double cum_vol = 0;
   double cum_pv  = 0;
   
   for(int i = 0; i < bars; i++)
     {
      double typ_price = (rates[i].high + rates[i].low + rates[i].close) / 3.0;
      double vol = (double)rates[i].tick_volume;
      cum_vol += vol;
      cum_pv  += (typ_price * vol);
     }
     
   if(cum_vol <= 0) return true;
   double vwap = cum_pv / cum_vol;
   double price = SymbolInfoDouble(symbol, SYMBOL_BID);
   
   bool is_bullish = (price > vwap);
   
   if(order_type == ORDER_TYPE_BUY  && !is_bullish) 
     {
      Print("[GEMINI ALPHA] VWAP REJECT BUY on ",symbol," (Price ",price," < VWAP ",vwap,")");
      return false;
     }
   if(order_type == ORDER_TYPE_SELL && is_bullish)
     {
      Print("[GEMINI ALPHA] VWAP REJECT SELL on ",symbol," (Price ",price," > VWAP ",vwap,")");
      return false;
     }
     
   Print("[GEMINI ALPHA] VWAP SUCCESS on ",symbol," for ",EnumToString(order_type));
   return true;
  }
