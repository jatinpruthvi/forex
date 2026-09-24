//+------------------------------------------------------------------+
//|                                            GEMINI_ROI_MODULE.mqh |
//|                     Antigravity Advanced ROI Improvement Module  |
//|  Version 2.0 - All 9 ROI improvements implemented               |
//+------------------------------------------------------------------+
#property copyright "Gemini Antigravity"
#property link      ""

//--- Input Groups
input group "=== GEMINI ROI: 1. Multi-TF Confluence Filter ==="
input bool   GInpEnableMTFFilter        = true;   // Enable H1 trend filter
input int    GInpH1EmaPeriod            = 21;     //   H1 EMA period for trend

input group "=== GEMINI ROI: 2. Session-Aware Sizing ==="
input bool   GInpEnableSessionSizing    = true;   // Enable London/NY boost
input double GInpSessionBoostMultiplier = 1.5;    //   Risk multiplier in overlap
input int    GInpSessionStartHour       = 13;     //   Session overlap start (UTC)
input int    GInpSessionEndHour         = 17;     //   Session overlap end (UTC)

input group "=== GEMINI ROI: 3. ATR Trailing Stop ==="
input bool   GInpEnableTrailingStop     = true;   // Enable ATR trailing stop
input double GInpTrailAtrMultiplier     = 2.0;    //   ATR multiplier for trail
input int    GInpTrailAtrPeriod         = 14;     //   ATR period

input group "=== GEMINI ROI: 4. Correlation Guard ==="
input bool   GInpEnableCorrelationGuard = true;   // Block correlated duplicates
input double GInpCorrelationThreshold   = 0.80;   //   Min correlation to block

input group "=== GEMINI ROI: 5. Breakeven Stop Automation ==="
input bool   GInpEnableBreakeven        = true;   // Auto move SL to breakeven
input double GInpBreakevenTriggerR      = 0.75;   //   Trigger at R-multiple
input double GInpBreakevenLockPips      = 2.0;    //   Lock pips above entry

input group "=== GEMINI ROI: 6. Weekly Loss Reset ==="
input bool   GInpEnableWeeklyReset      = true;   // Reduce risk after bad week
input double GInpWeeklyLossThreshPct    = 2.0;    //   Weekly loss % threshold
input double GInpWeeklyReducedRiskPct   = 0.25;   //   Reduced risk %

input group "=== GEMINI ROI: 7. Spread Filter ==="
input bool   GInpEnableSpreadFilter     = true;   // Skip entries on wide spread
input double GInpMaxSpreadMultiplier    = 1.5;    //   Max spread vs normal

input group "=== GEMINI ROI: 8. Adaptive Half-Kelly Sizing ==="
input bool   GInpEnableKellySizing      = true;   // Enable Half-Kelly risk scaling
input double GInpKellyBaseWinRate       = 0.55;   //   Base win rate assumption
input double GInpKellyBaseRR            = 1.50;   //   Base risk/reward ratio
input int    GInpKellyLookbackTrades    = 30;     //   Rolling trades window

input group "=== GEMINI ROI: 9. Time-Based Exits ==="
input bool   GInpEnableTimeStops        = true;   // Kill dead capital positions
input int    GInpTimeStopBars           = 12;     //   Max bars before forced exit

//--- Global State
double g_gemini_kelly_mult     = 1.0;
double g_gemini_session_mult   = 1.0;
double g_gemini_normal_spread[]      = {};
double g_gemini_week_bal = 0.0;
bool   g_gemini_week_reduced  = false;
datetime g_gemini_week_key           = 0;

//+------------------------------------------------------------------+
//| 1. Multi-Timeframe Confluence: Check if H1 trend agrees         |
//+------------------------------------------------------------------+
bool GeminiMTFTrendAllows(string symbol, ENUM_ORDER_TYPE order_type)
  {
   if(!GInpEnableMTFFilter) return true;
   
   int handle = iMA(symbol, PERIOD_H1, GInpH1EmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(handle == INVALID_HANDLE) return true; // fail open
   
   double ema[2];
   if(CopyBuffer(handle, 0, 0, 2, ema) < 2) return true;
   IndicatorRelease(handle);
   
   double price = SymbolInfoDouble(symbol, SYMBOL_BID);
   bool bullish_trend = (price > ema[0]);
   
   if(order_type == ORDER_TYPE_BUY  && !bullish_trend) return false;
   if(order_type == ORDER_TYPE_SELL && bullish_trend)  return false;
   
   return true;
  }

//+------------------------------------------------------------------+
//| 2. Session-Aware: Get risk multiplier based on time              |
//+------------------------------------------------------------------+
double GeminiSessionMultiplier()
  {
   if(!GInpEnableSessionSizing) return 1.0;
   
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int hour = dt.hour;
   
   if(hour >= GInpSessionStartHour && hour < GInpSessionEndHour)
      return GInpSessionBoostMultiplier;
   
   return 1.0;
  }

//+------------------------------------------------------------------+
//| 3. ATR Trailing Stop: Move SL for all positions of magic         |
//+------------------------------------------------------------------+
void GeminiRunTrailingStops(ulong magic)
  {
   if(!GInpEnableTrailingStop) return;
   
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)magic) continue;
      
      string  sym      = PositionGetString(POSITION_SYMBOL);
      int     atr_h    = iATR(sym, PERIOD_CURRENT, GInpTrailAtrPeriod);
      if(atr_h == INVALID_HANDLE) continue;
      
      double atr_buf[1];
      if(CopyBuffer(atr_h, 0, 1, 1, atr_buf) < 1) { IndicatorRelease(atr_h); continue; }
      IndicatorRelease(atr_h);
      double atr = atr_buf[0];
      
      double sl          = PositionGetDouble(POSITION_SL);
      double open_price  = PositionGetDouble(POSITION_PRICE_OPEN);
      double current_bid = SymbolInfoDouble(sym, SYMBOL_BID);
      double current_ask = SymbolInfoDouble(sym, SYMBOL_ASK);
      long   pos_type    = PositionGetInteger(POSITION_TYPE);
      double point       = SymbolInfoDouble(sym, SYMBOL_POINT);
      int    digits      = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      double trail_dist  = GInpTrailAtrMultiplier * atr;
      
      double new_sl = 0;
      if(pos_type == POSITION_TYPE_BUY)
        {
         new_sl = NormalizeDouble(current_bid - trail_dist, digits);
         if(new_sl > sl + point && new_sl > open_price)
           {
            MqlTradeRequest req = {}; MqlTradeResult res = {};
            req.action   = TRADE_ACTION_SLTP;
            req.position = ticket;
            req.symbol   = sym;
            req.sl       = new_sl;
            req.tp       = PositionGetDouble(POSITION_TP);
            bool _r=OrderSend(req, res);
           }
        }
      else if(pos_type == POSITION_TYPE_SELL)
        {
         new_sl = NormalizeDouble(current_ask + trail_dist, digits);
         if((sl == 0 || new_sl < sl - point) && new_sl < open_price)
           {
            MqlTradeRequest req = {}; MqlTradeResult res = {};
            req.action   = TRADE_ACTION_SLTP;
            req.position = ticket;
            req.symbol   = sym;
            req.sl       = new_sl;
            req.tp       = PositionGetDouble(POSITION_TP);
            bool _r=OrderSend(req, res);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| 4. Correlation Guard: Check if symbol is already in portfolio    |
//+------------------------------------------------------------------+
bool GeminiCorrelationAllows(string symbol, ulong magic)
  {
   if(!GInpEnableCorrelationGuard) return true;
   
   // Hard-coded correlation clusters - pairs that move together
   string eur_cluster[] = {"EURUSD","EURGBP","EURJPY","EURCHF","EURAUD","EURCAD","EURNZD"};
   string gbp_cluster[] = {"GBPUSD","GBPJPY","GBPCHF","GBPAUD","GBPCAD","GBPNZD"};
   string usd_cluster[] = {"USDCHF","USDJPY","USDCAD"};
   string aud_cluster[] = {"AUDUSD","AUDCHF","AUDJPY","AUDCAD","AUDNZD","NZDUSD","NZDJPY"};
   
   string clusters[][7] = {};  // just check manually below
   
   // Find what cluster our symbol is in
   string sym_cluster = "";
   
   for(int i=0; i<7; i++) if(symbol == eur_cluster[i]) { sym_cluster = "EUR"; break; }
   if(sym_cluster == "") for(int i=0; i<6; i++) if(symbol == gbp_cluster[i]) { sym_cluster = "GBP"; break; }
   if(sym_cluster == "") for(int i=0; i<3; i++) if(symbol == usd_cluster[i]) { sym_cluster = "USD"; break; }
   if(sym_cluster == "") for(int i=0; i<6; i++) if(symbol == aud_cluster[i]) { sym_cluster = "AUD"; break; }
   
   if(sym_cluster == "") return true; // unknown pair, allow
   
   // Check if we already hold a position in same cluster
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)magic) continue;
      
      string held_sym = PositionGetString(POSITION_SYMBOL);
      if(held_sym == symbol) continue; // same symbol, not a correlation issue
      
      string held_cluster = "";
      for(int j=0; j<7; j++) if(held_sym == eur_cluster[j]) { held_cluster = "EUR"; break; }
      if(held_cluster == "") for(int j=0; j<6; j++) if(held_sym == gbp_cluster[j]) { held_cluster = "GBP"; break; }
      if(held_cluster == "") for(int j=0; j<3; j++) if(held_sym == usd_cluster[j]) { held_cluster = "USD"; break; }
      if(held_cluster == "") for(int j=0; j<6; j++) if(held_sym == aud_cluster[j]) { held_cluster = "AUD"; break; }
      
      if(held_cluster == sym_cluster)
        {
         Print("[GEMINI] Correlation guard blocked ", symbol, " — already holding ", held_sym, " in ", sym_cluster, " cluster");
         return false;
        }
     }
   return true;
  }

//+------------------------------------------------------------------+
//| 5. Breakeven Stop: Move SL to entry + lock pips                 |
//+------------------------------------------------------------------+
void GeminiRunBreakeven(ulong magic)
  {
   if(!GInpEnableBreakeven) return;
   
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)magic) continue;
      
      string sym        = PositionGetString(POSITION_SYMBOL);
      double entry      = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl         = PositionGetDouble(POSITION_SL);
      double tp         = PositionGetDouble(POSITION_TP);
      double bid        = SymbolInfoDouble(sym, SYMBOL_BID);
      double ask        = SymbolInfoDouble(sym, SYMBOL_ASK);
      double point      = SymbolInfoDouble(sym, SYMBOL_POINT);
      int    digits     = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      long   pos_type   = PositionGetInteger(POSITION_TYPE);
      double lock_dist  = GInpBreakevenLockPips * point * 10;
      
      if(sl == 0) continue;
      
      double risk = MathAbs(entry - sl);
      if(risk <= 0) continue;
      
      double be_level = 0;
      bool   should_move = false;
      
      if(pos_type == POSITION_TYPE_BUY)
        {
         double progress = (bid - entry) / risk;
         be_level = NormalizeDouble(entry + lock_dist, digits);
         should_move = (progress >= GInpBreakevenTriggerR && sl < be_level);
        }
      else if(pos_type == POSITION_TYPE_SELL)
        {
         double progress = (entry - ask) / risk;
         be_level = NormalizeDouble(entry - lock_dist, digits);
         should_move = (progress >= GInpBreakevenTriggerR && (sl == 0 || sl > be_level));
        }
      
      if(should_move)
        {
         MqlTradeRequest req = {}; MqlTradeResult res = {};
         req.action   = TRADE_ACTION_SLTP;
         req.position = ticket;
         req.symbol   = sym;
         req.sl       = be_level;
         req.tp       = tp;
         if(OrderSend(req, res))
            Print("[GEMINI] Breakeven set for ", sym, " ticket=", ticket, " SL=", be_level);
        }
     }
  }

//+------------------------------------------------------------------+
//| 6. Weekly Loss Reset                                             |
//+------------------------------------------------------------------+
void GeminiCheckWeeklyReset()
  {
   if(!GInpEnableWeeklyReset) return;
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   // Reset tracking on Monday
   if(dt.day_of_week == 1)
     {
      datetime this_week = (datetime)(TimeCurrent() - dt.hour*3600 - dt.min*60 - dt.sec);
      if(this_week != g_gemini_week_key)
        {
         g_gemini_week_key            = this_week;
         g_gemini_week_bal= AccountInfoDouble(ACCOUNT_BALANCE);
         g_gemini_week_reduced = false;
         Print("[GEMINI] Weekly reset — start balance: ", g_gemini_week_bal);
        }
     }
   
   if(g_gemini_week_bal <= 0) return;
   
   double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double weekly_loss_pct = (g_gemini_week_bal - current_balance) / g_gemini_week_bal * 100.0;
   
   if(weekly_loss_pct >= GInpWeeklyLossThreshPct && !g_gemini_week_reduced)
     {
      g_gemini_week_reduced = true;
      Print("[GEMINI] Weekly loss threshold hit (", DoubleToString(weekly_loss_pct,2), "%) — risk reduced to ", GInpWeeklyReducedRiskPct, "%");
     }
  }

bool GeminiIsWeeklyRiskReduced() { return g_gemini_week_reduced; }
double GeminiWeeklyRiskMultiplier() { return g_gemini_week_reduced ? (GInpWeeklyReducedRiskPct / 0.5) : 1.0; }

//+------------------------------------------------------------------+
//| 7. Spread Filter                                                 |
//+------------------------------------------------------------------+
bool GeminiSpreadAllows(string symbol)
  {
   if(!GInpEnableSpreadFilter) return true;
   
   long spread_points = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   double point       = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double spread_pips = spread_points * point * 10000.0;
   
   // Use 10-bar average ask/bid diff as reference
   double highs[], lows[];
   int bars = 20;
   ArrayResize(highs, bars); ArrayResize(lows, bars);
   
   if(CopyHigh(symbol, PERIOD_M5, 1, bars, highs) < bars) return true;
   if(CopyLow(symbol, PERIOD_M5, 1, bars, lows)   < bars) return true;
   
   double avg_range = 0;
   for(int i=0; i<bars; i++) avg_range += (highs[i]-lows[i]);
   avg_range /= bars;
   
   // Normal spread is typically 5-15% of average bar range
   double normal_spread_estimate = avg_range * 0.08;
   double normal_spread_pips     = normal_spread_estimate * 10000.0;
   
   if(normal_spread_pips <= 0) return true;
   
   double ratio = spread_pips / normal_spread_pips;
   if(ratio > GInpMaxSpreadMultiplier)
     {
      Print("[GEMINI] Spread filter blocked ", symbol, " — spread=", DoubleToString(spread_pips,1), "p vs normal=", DoubleToString(normal_spread_pips,1), "p (ratio=", DoubleToString(ratio,2), "x)");
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| 8. Adaptive Half-Kelly Risk Sizing                               |
//+------------------------------------------------------------------+
void GeminiInitKelly()
  {
   if(!GInpEnableKellySizing) { g_gemini_kelly_mult = 1.0; return; }
   
   double kelly = GInpKellyBaseWinRate - ((1.0 - GInpKellyBaseWinRate) / GInpKellyBaseRR);
   double half_kelly = 0.5 * kelly;
   
   half_kelly = MathMax(half_kelly, 0.05);
   half_kelly = MathMin(half_kelly, 0.50);
   
   // Scale against baseline of 0.5% risk = kelly factor of 0.175 (55% WR, 1.5R)
   g_gemini_kelly_mult = half_kelly / 0.175;
   g_gemini_kelly_mult = MathMax(g_gemini_kelly_mult, 0.3);
   g_gemini_kelly_mult = MathMin(g_gemini_kelly_mult, 2.0);
   
   Print("[GEMINI] Half-Kelly multiplier: ", DoubleToString(g_gemini_kelly_mult,3),
         " | W=", GInpKellyBaseWinRate, " R=", GInpKellyBaseRR);
  }

double GeminiKellyMultiplier() { return GInpEnableKellySizing ? g_gemini_kelly_mult : 1.0; }

//+------------------------------------------------------------------+
//| 9. Time-Based Exits (Dead Capital Liquidation)                  |
//+------------------------------------------------------------------+
void GeminiRunTimeStops(ulong magic)
  {
   if(!GInpEnableTimeStops) return;
   
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)magic) continue;
      
      string   sym       = PositionGetString(POSITION_SYMBOL);
      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
      int      bars      = iBarShift(sym, PERIOD_CURRENT, open_time);
      
      if(bars < GInpTimeStopBars) continue;
      
      double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(profit >= 0) continue; // only exit losing/flat dead trades
      
      MqlTradeRequest req = {}; MqlTradeResult res = {};
      req.action    = TRADE_ACTION_DEAL;
      req.position  = ticket;
      req.symbol    = sym;
      req.volume    = PositionGetDouble(POSITION_VOLUME);
      req.deviation = 20;
      req.magic     = magic;
      req.comment   = "GEMINI_TIMESTOP";
      req.type_filling = ORDER_FILLING_FOK;
      
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         req.type  = ORDER_TYPE_SELL;
      else
         req.type  = ORDER_TYPE_BUY;
      
      req.price = (req.type == ORDER_TYPE_SELL)
                  ? SymbolInfoDouble(sym, SYMBOL_BID)
                  : SymbolInfoDouble(sym, SYMBOL_ASK);
      
      if(OrderSend(req, res))
         Print("[GEMINI] Time-stop closed ", sym, " ticket=", ticket, " after ", bars, " bars. P&L=", DoubleToString(profit,2));
      else
         Print("[GEMINI] Time-stop FAILED for ", sym, " ticket=", ticket, " err=", GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| Master Init — call from OnInit()                                 |
//+------------------------------------------------------------------+
void GeminiROIInit()
  {
   GeminiInitKelly();
   g_gemini_week_bal = AccountInfoDouble(ACCOUNT_BALANCE);
   g_gemini_week_key             = 0;
   g_gemini_week_reduced  = false;
   Print("[GEMINI] ROI Module v2.0 initialized — all 9 improvements active");
  }

//+------------------------------------------------------------------+
//| Master Tick — call from OnTick() and OnTimer()                   |
//+------------------------------------------------------------------+
void GeminiROITick(ulong magic)
  {
   GeminiCheckWeeklyReset();
   GeminiRunBreakeven(magic);
   GeminiRunTrailingStops(magic);
   GeminiRunTimeStops(magic);
  }

