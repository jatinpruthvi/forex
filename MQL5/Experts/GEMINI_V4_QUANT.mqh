//+------------------------------------------------------------------+
//|                                           GEMINI_V4_QUANT.mqh    |
//|                 Antigravity Institutional V4 Quant Module        |
//+------------------------------------------------------------------+
#property copyright "Gemini Antigravity"
#property link      ""

//=== V4: 1. Trading the Equity Curve ===
input group "=== GEMINI V4: 1. Equity Curve Evasion ==="
input bool   QInpEnableEquityCurve      = true;
input int    QInpEquityCurvePeriod      = 10;   // Rolling window of trades
input double QInpDrawdownPenaltyMult    = 0.2;  // Size multiplier when below EQ curve MA

//=== V4: 2. Cross-Asset Macro Gating (DXY) ===
input group "=== GEMINI V4: 2. Macro Dollar Guard ==="
input bool   QInpEnableMacroGuard       = true;
input string QInpDxySymbol              = "DXY"; // Adjust to broker's dollar index ticker
input int    QInpMacroEmaPeriod         = 20;

//=== V4: 3. Smart Money Concepts (H4 FVG) ===
input group "=== GEMINI V4: 3. Fair Value Gaps ==="
input bool   QInpEnableFVG              = true;
input double QInpFVGBoostMult           = 1.5;  // Multiplier if entering in a H4 FVG

//+------------------------------------------------------------------+
//| 1. Trading the Equity Curve (Drawdown Evasion)                   |
//+------------------------------------------------------------------+
double GeminiV4_EquityCurveSizing(ulong magic)
  {
   if(!QInpEnableEquityCurve) return 1.0;
   
   HistorySelect(0, TimeCurrent());
   int total = HistoryDealsTotal();
   
   double history_pl[];
   ArrayResize(history_pl, QInpEquityCurvePeriod);
   ArrayInitialize(history_pl, 0.0);
   
   int count = 0;
   double cumulative_eq = 0.0;
   
   // Traverse history backwards to get the last N trades for this magic number
   for(int i = total - 1; i >= 0 && count < QInpEquityCurvePeriod; i--)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      
      long deal_magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
      long deal_entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      
      // Only count exits for this EA
      if(deal_magic == magic && (deal_entry == DEAL_ENTRY_OUT || deal_entry == DEAL_ENTRY_INOUT))
        {
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         double comm   = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         double swap   = HistoryDealGetDouble(ticket, DEAL_SWAP);
         
         double net = profit + comm + swap;
         history_pl[QInpEquityCurvePeriod - 1 - count] = net;
         count++;
        }
     }
     
   if(count < QInpEquityCurvePeriod) return 1.0; // Not enough data yet
   
   // Calculate Equity Curve MA vs Current Equity Peak
   double current_eq = 0;
   double sum_eq = 0;
   double eq_curve[];
   ArrayResize(eq_curve, count);
   
   for(int i = 0; i < count; i++)
     {
      current_eq += history_pl[i];
      eq_curve[i] = current_eq;
      sum_eq += current_eq;
     }
     
   double eq_ma = sum_eq / count;
   
   if(current_eq < eq_ma)
     {
      Print("[GEMINI V4] System in Drawdown (Current EQ: ",current_eq," < MA: ",eq_ma,"). Slashing risk to ",QInpDrawdownPenaltyMult,"x");
      return QInpDrawdownPenaltyMult;
     }
     
   Print("[GEMINI V4] System in Sync (Current EQ: ",current_eq," >= MA: ",eq_ma,"). Full risk authorized.");
   return 1.0;
  }

//+------------------------------------------------------------------+
//| 2. Cross-Asset Macro Gating (DXY Momentum)                       |
//+------------------------------------------------------------------+
bool GeminiV4_MacroGuard(string symbol, ENUM_ORDER_TYPE type)
  {
   if(!QInpEnableMacroGuard) return true;
   if(QInpDxySymbol == "" || !SymbolSelect(QInpDxySymbol, true)) return true; // Broker doesn't have it
   
   // We only care about USD paired assets (e.g. EURUSD, GBPUSD, XAUUSD)
   bool is_usd_base = (StringSubstr(symbol, 0, 3) == "USD");
   bool is_usd_quote = (StringSubstr(symbol, 3, 3) == "USD");
   if(!is_usd_base && !is_usd_quote) return true; // Not a USD pair
   
   // Check DXY Trend (Price vs EMA20)
   double close[1];
   if(CopyClose(QInpDxySymbol, PERIOD_D1, 0, 1, close) < 1) return true;
   
   int ema_h = iMA(QInpDxySymbol, PERIOD_D1, QInpMacroEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   double ema[1];
   if(ema_h == INVALID_HANDLE || CopyBuffer(ema_h, 0, 0, 1, ema) < 1) return true;
   IndicatorRelease(ema_h);
   
   bool dollar_bullish = (close[0] > ema[0]);
   bool dollar_bearish = (close[0] < ema[0]);
   
   // If trading EURUSD (USD quote), Buy means shorting USD.
   if(is_usd_quote && type == ORDER_TYPE_BUY && dollar_bullish)
     {
      Print("[GEMINI V4] MACRO BLOCK: Trying to Buy ",symbol," but DXY is Bullish.");
      return false;
     }
   if(is_usd_quote && type == ORDER_TYPE_SELL && dollar_bearish)
     {
      Print("[GEMINI V4] MACRO BLOCK: Trying to Sell ",symbol," but DXY is Bearish.");
      return false;
     }
     
   return true;
  }

//+------------------------------------------------------------------+
//| 3. Smart Money Concepts: H4 FVG Multiplier                       |
//+------------------------------------------------------------------+
double GeminiV4_FVG_Score(string symbol, ENUM_ORDER_TYPE type)
  {
   if(!QInpEnableFVG) return 1.0;
   
   MqlRates h4[];
   ArraySetAsSeries(h4, true);
   if(CopyRates(symbol, PERIOD_H4, 1, 20, h4) < 20) return 1.0; // Need recent bars
   
   double current_price = SymbolInfoDouble(symbol, SYMBOL_BID);
   
   for(int i = 2; i < 18; i++) // Scan for 3-bar FVG patterns
     {
      // Bullish FVG: Bar(i+1) is large green, Bar(i+2) High < Bar(i) Low
      if(h4[i+2].high < h4[i].low && h4[i+1].close > h4[i+1].open)
        {
         double fvg_top = h4[i].low;
         double fvg_bot = h4[i+2].high;
         
         if(type == ORDER_TYPE_BUY && current_price <= fvg_top && current_price >= fvg_bot)
           {
            Print("[GEMINI V4] SMC BOOST: Buying inside H4 Bullish FVG [",fvg_bot," - ",fvg_top,"]");
            return QInpFVGBoostMult;
           }
        }
        
      // Bearish FVG: Bar(i+2) Low > Bar(i) High
      if(h4[i+2].low > h4[i].high && h4[i+1].close < h4[i+1].open)
        {
         double fvg_top = h4[i+2].low;
         double fvg_bot = h4[i].high;
         
         if(type == ORDER_TYPE_SELL && current_price <= fvg_top && current_price >= fvg_bot)
           {
            Print("[GEMINI V4] SMC BOOST: Selling inside H4 Bearish FVG [",fvg_bot," - ",fvg_top,"]");
            return QInpFVGBoostMult;
           }
        }
     }
     
   return 1.0;
  }
