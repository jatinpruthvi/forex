//+------------------------------------------------------------------+
//|                                                   GOLD_SWING.mq5 |
//|                             Daily Donchian N=55 Swing Portfolio  |
//+------------------------------------------------------------------+
#property copyright "Jatin"
#property link      ""

#include "../GEMINI_ROI_MODULE.mqh"
#include "../GEMINI_ALPHA_MODULE.mqh"

// --- Inputs ---
input group "=== Strategy Parameters ==="
input int    InpDonchianPeriod = 55;      // 55-Day Donchian Breakout
input double InpChandelierAtrMult = 2.5;  // 2.5x ATR Trailing Stop
input int    InpAtrPeriod = 14;           // ATR calculation period
input double InpRiskPercent = 1.0;        // 1.0% fixed risk per trade
input long   InpMagic = 55555;            // EA Magic Number

int handle_atr;
int handle_highest;
int handle_lowest;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   GeminiROIInit();

   if(Symbol() != "XAUUSD") 
     {
      Print("This EA is designed exclusively for XAUUSD (Gold).");
     }

   handle_atr = iATR(Symbol(), PERIOD_D1, InpAtrPeriod);
   handle_highest = iHighest(Symbol(), PERIOD_D1, MODE_HIGH, InpDonchianPeriod, 1);
   handle_lowest = iLowest(Symbol(), PERIOD_D1, MODE_LOW, InpDonchianPeriod, 1);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   GeminiROITick(InpMagic);

   // NOTE: This is a structural scaffold for the Gold Swing strategy.
   // Wait for a new Daily bar close
   static datetime last_bar = 0;
   datetime current_bar = iTime(Symbol(), PERIOD_D1, 0);
   if(current_bar == last_bar) return;
   last_bar = current_bar;

   // 1. Read Donchian Channel
   double highest_high = 0; // Retrieve from handle_highest
   double lowest_low = 0;   // Retrieve from handle_lowest
   
   // 2. Read ATR for Chandelier Exit
   double atr_val[1];
   CopyBuffer(handle_atr, 0, 1, 1, atr_val);

      // 3. Breakout Logic & V2 Volatility Squeeze Filter
   if(!GeminiAlpha_VolatilitySqueeze(Symbol())) return;
   
   double hh[1], ll[1];
   if(CopyBuffer(handle_highest, 0, 1, 1, hh) < 1) return;
   if(CopyBuffer(handle_lowest, 0, 1, 1, ll) < 1) return;
   
   double close_px = iClose(Symbol(), PERIOD_D1, 1);
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   
   bool is_long_breakout = (close_px > hh[0]);
   bool is_short_breakout = (close_px < ll[0]);
   
   if(!is_long_breakout && !is_short_breakout) return;
   
   // 4. Execution Guard (ROI V1 modules)
   ENUM_ORDER_TYPE type = is_long_breakout ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!GeminiEntryGate(Symbol(), type, InpMagic)) return;
   
   double sl = 0;
   if(is_long_breakout) sl = bid - (atr_val[0] * InpChandelierAtrMult);
   if(is_short_breakout) sl = ask + (atr_val[0] * InpChandelierAtrMult);
   
   // We will execute a 0.01 lot for the scaffold
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action = TRADE_ACTION_DEAL;
   req.symbol = Symbol();
   req.volume = 0.01;
   req.type = type;
   req.price = is_long_breakout ? ask : bid;
   req.sl = sl;
   req.deviation = 20;
   req.magic = InpMagic;
   
   OrderSend(req, res);
  }
//+------------------------------------------------------------------+




