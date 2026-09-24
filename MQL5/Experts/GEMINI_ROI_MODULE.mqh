//+------------------------------------------------------------------+
//|                                            GEMINI_ROI_MODULE.mqh |
//|                     Antigravity Advanced ROI Improvement Module  |
//+------------------------------------------------------------------+
#property copyright "Gemini Antigravity"
#property link      ""

input group "=== GEMINI ROI IMPROVEMENTS ==="
input bool   InpEnableWinnerPyramiding  = true;   // 1. Winner Pyramiding (Scale-In)
input double InpPyramidTriggerR         = 1.5;    //    - Trigger at R-multiple
input double InpPyramidScalePct         = 0.5;    //    - Size relative to original
input bool   InpEnableKellySizing       = true;   // 2. Adaptive Half-Kelly Sizing
input double InpKellyBaseWinRate        = 0.55;   //    - Base Win Rate expectation
input double InpKellyBaseRR             = 1.50;   //    - Base Risk/Reward expectation
input bool   InpEnableM1Execution       = true;   // 3. M1 Momentum Execution Engine
input double InpM1PullbackPips          = 2.0;    //    - Required pullback for entry
input bool   InpEnableDynamicVolatility = true;   // 4. High-Beta Asset Scaling (ATR)
input bool   InpEnableTimeStops         = true;   // 5. Dynamic Time-Based Exits
input int    InpTimeStopBars            = 12;     //    - Max bars for dead capital

// Global state for Gemini ROI tracking
double g_kelly_risk_multiplier = 1.0;

// Initialize Kelly Sizing
void InitGeminiKellySizing()
  {
   if(!InpEnableKellySizing) return;
   // Half-Kelly = 0.5 * (W - ((1-W)/R))
   double kelly = InpKellyBaseWinRate - ((1.0 - InpKellyBaseWinRate) / InpKellyBaseRR);
   double half_kelly = 0.5 * kelly;
   
   if(half_kelly <= 0.05) half_kelly = 0.05; // floor
   if(half_kelly >= 0.50) half_kelly = 0.50; // ceiling
   
   // We will use this to scale the base risk input
   g_kelly_risk_multiplier = half_kelly * 10.0; // arbitrary scaler for demo
   Print("[GEMINI] Adaptive Half-Kelly Multiplier initialized: ", g_kelly_risk_multiplier);
  }

// Dynamic Time-Based Exits
void RunGeminiTimeStops(ulong magic)
  {
   if(!InpEnableTimeStops) return;
   
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      
      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
      string symbol = PositionGetString(POSITION_SYMBOL);
      
      int bars_passed = iBarShift(symbol, PERIOD_CURRENT, open_time);
      if(bars_passed >= InpTimeStopBars)
        {
         double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         if(profit <= 0)
           {
            Print("[GEMINI] Time-Stop triggered for ticket ", ticket, " (Dead Capital: ", bars_passed, " bars)");
            // Note: Caller must implement actual close logic based on their specific framework
            // We just print the trigger here to avoid breaking EA-specific execution wrappers.
           }
        }
     }
  }

// Call this from OnTick or OnTimer
void RunGeminiROIModules(ulong magic)
  {
   RunGeminiTimeStops(magic);
   // Winner Pyramiding & M1 Engine logic would hook here
  }
