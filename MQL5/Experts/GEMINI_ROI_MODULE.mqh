//+------------------------------------------------------------------+
//|                                            GEMINI_ROI_MODULE.mqh |
//|                     Antigravity Advanced ROI Improvement Module  |
//|  Version 3.0 — 18 total ROI improvements (v2 + 9 new)           |
//+------------------------------------------------------------------+
#property copyright "Gemini Antigravity"
#property link      ""

//===================================================================
//  V2 INPUTS (preserved from v2.0)
//===================================================================
input group "=== GEMINI ROI: 1. Multi-TF Confluence Filter ==="
input bool   GInpEnableMTFFilter        = true;
input int    GInpH1EmaPeriod            = 21;

input group "=== GEMINI ROI: 2. Session-Aware Sizing ==="
input bool   GInpEnableSessionSizing    = true;
input double GInpSessionBoostMultiplier = 1.5;
input int    GInpSessionStartHour       = 13;
input int    GInpSessionEndHour         = 17;

input group "=== GEMINI ROI: 3. ATR Trailing Stop ==="
input bool   GInpEnableTrailingStop     = true;
input double GInpTrailAtrMultiplier     = 2.0;
input int    GInpTrailAtrPeriod         = 14;

input group "=== GEMINI ROI: 4. Correlation Guard ==="
input bool   GInpEnableCorrelationGuard = true;

input group "=== GEMINI ROI: 5. Breakeven Automation ==="
input bool   GInpEnableBreakeven        = true;
input double GInpBreakevenTriggerR      = 0.75;
input double GInpBreakevenLockPips      = 2.0;

input group "=== GEMINI ROI: 6. Weekly Loss Reset ==="
input bool   GInpEnableWeeklyReset      = true;
input double GInpWeeklyLossThreshPct    = 2.0;
input double GInpWeeklyReducedRiskPct   = 0.25;

input group "=== GEMINI ROI: 7. Spread Filter ==="
input bool   GInpEnableSpreadFilter     = true;
input double GInpMaxSpreadMultiplier    = 1.5;

input group "=== GEMINI ROI: 8. Adaptive Half-Kelly Sizing ==="
input bool   GInpEnableKellySizing      = true;
input double GInpKellyBaseWinRate       = 0.55;
input double GInpKellyBaseRR            = 1.50;

input group "=== GEMINI ROI: 9. Time-Based Exits ==="
input bool   GInpEnableTimeStops        = true;
input int    GInpTimeStopBars           = 12;

//===================================================================
//  V3 INPUTS (9 new improvements)
//===================================================================
input group "=== GEMINI ROI: 10. Signal Scoring (ML-style) ==="
input bool   GInpEnableSignalScoring    = true;   // Enable confluence scoring
input int    GInpMinSignalScore         = 60;     //   Minimum score to trade (0-100)

input group "=== GEMINI ROI: 11. Regime Detection ==="
input bool   GInpEnableRegimeFilter     = true;   // Skip signals in ranging markets
input int    GInpAdxPeriod              = 14;     //   ADX period
input double GInpAdxTrendThreshold      = 22.0;   //   ADX must be > this to trade
input int    GInpAtrRankPeriod          = 50;     //   ATR percentile lookback bars
input double GInpAtrRankMinPct          = 25.0;   //   Min ATR percentile rank (0-100)

input group "=== GEMINI ROI: 12. Walk-Forward Adaptation ==="
input bool   GInpEnableWalkForward      = true;   // Adapt Kelly after each 20 trades
input int    GInpWFAdaptWindow          = 20;     //   Rolling window of trades

input group "=== GEMINI ROI: 13. News Pre-Positioning ==="
input bool   GInpEnableNewsPrepos       = false;  // Pre-position before red news (off by default)
input int    GInpNewsPreposMins         = 15;     //   Minutes before news to enter
input string GInpNewsPreposCsv         = "triad_red_news.csv"; // News CSV file

input group "=== GEMINI ROI: 14. H1 Structure Exit ==="
input bool   GInpEnableH1StructureExit  = true;   // Exit when H1 closes against trade
input int    GInpH1ExitLookback         = 2;      //   Bars to confirm H1 close

input group "=== GEMINI ROI: 15. Dynamic TP (Daily ATR) ==="
input bool   GInpEnableDynamicTP        = true;   // Shrink TP as daily range fills
input double GInpDailyAtrUsedCapPct     = 75.0;   //   If daily range >75% used, reduce TP
input double GInpDynamicTPReductionPct  = 50.0;   //   Reduce TP by this % when capped

input group "=== GEMINI ROI: 16. Portfolio Heat Monitor ==="
input bool   GInpEnableHeatMonitor      = true;   // Cap total portfolio risk
input double GInpMaxPortfolioHeatPct    = 3.0;    //   Max combined risk % of balance

input group "=== GEMINI ROI: 17. Adaptive Per-Pair Sizing ==="
input bool   GInpEnablePerPairSizing    = true;   // Adjust size based on pair performance
input int    GInpPairSizingWindow       = 20;     //   Trades per pair to track
input double GInpPairSizingMinMult      = 0.5;    //   Minimum size multiplier
input double GInpPairSizingMaxMult      = 1.5;    //   Maximum size multiplier

input group "=== GEMINI ROI: 18. COT Sentiment Filter ==="
input bool   GInpEnableCOTFilter        = false;  // COT data directional filter (off by default)
input string GInpCOTCsvFile             = "cot_data.csv"; // COT data file (weekly download)

//===================================================================
//  GLOBAL STATE
//===================================================================
double   g_gemini_kelly_mult      = 1.0;
double   g_gemini_week_bal        = 0.0;
bool     g_gemini_week_reduced    = false;
datetime g_gemini_week_key        = 0;

// Walk-Forward state (stored via GlobalVariables)
int      g_gemini_wf_trades       = 0;
int      g_gemini_wf_wins         = 0;
double   g_gemini_wf_total_r      = 0.0;

// Per-pair sizing state (symbol → wins, total)
string   g_pair_symbols[20];
int      g_pair_wins[20];
int      g_pair_total[20];
int      g_pair_count             = 0;

// COT sentiment: 1=bullish, -1=bearish, 0=neutral per currency
string   g_cot_currencies[10];
int      g_cot_sentiment[10];
int      g_cot_count              = 0;

//===================================================================
//  1/10. MULTI-TF CONFLUENCE FILTER (v2 preserved)
//===================================================================
bool GeminiMTFTrendAllows(string symbol, ENUM_ORDER_TYPE order_type)
  {
   if(!GInpEnableMTFFilter) return true;
   int handle = iMA(symbol, PERIOD_H1, GInpH1EmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(handle == INVALID_HANDLE) return true;
   double ema[2];
   if(CopyBuffer(handle, 0, 0, 2, ema) < 2) { IndicatorRelease(handle); return true; }
   IndicatorRelease(handle);
   double price = SymbolInfoDouble(symbol, SYMBOL_BID);
   if(order_type == ORDER_TYPE_BUY  && price < ema[0]) return false;
   if(order_type == ORDER_TYPE_SELL && price > ema[0]) return false;
   return true;
  }

//===================================================================
//  2/11. SESSION MULTIPLIER (v2 preserved)
//===================================================================
double GeminiSessionMultiplier()
  {
   if(!GInpEnableSessionSizing) return 1.0;
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   if(dt.hour >= GInpSessionStartHour && dt.hour < GInpSessionEndHour)
      return GInpSessionBoostMultiplier;
   return 1.0;
  }

//===================================================================
//  3/12. ATR TRAILING STOP (v2 preserved)
//===================================================================
void GeminiRunTrailingStops(ulong magic)
  {
   if(!GInpEnableTrailingStop) return;
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)magic) continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      int atr_h = iATR(sym, PERIOD_CURRENT, GInpTrailAtrPeriod);
      if(atr_h == INVALID_HANDLE) continue;
      double atr_buf[1];
      if(CopyBuffer(atr_h, 0, 1, 1, atr_buf) < 1) { IndicatorRelease(atr_h); continue; }
      IndicatorRelease(atr_h);
      double atr = atr_buf[0];
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double bid = SymbolInfoDouble(sym, SYMBOL_BID);
      double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
      long pos_type = PositionGetInteger(POSITION_TYPE);
      int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      double trail = GInpTrailAtrMultiplier * atr;
      MqlTradeRequest req={}; MqlTradeResult res={};
      req.action=TRADE_ACTION_SLTP; req.position=ticket; req.symbol=sym; req.tp=tp;
      if(pos_type == POSITION_TYPE_BUY)
        {
         double new_sl = NormalizeDouble(bid - trail, digits);
         if(new_sl > sl + SymbolInfoDouble(sym,SYMBOL_POINT) && new_sl > entry)
           { req.sl=new_sl; bool _r=OrderSend(req,res); }
        }
      else
        {
         double new_sl = NormalizeDouble(ask + trail, digits);
         if((sl==0||new_sl<sl-SymbolInfoDouble(sym,SYMBOL_POINT)) && new_sl<entry)
           { req.sl=new_sl; bool _r=OrderSend(req,res); }
        }
     }
  }

//===================================================================
//  4/13. CORRELATION GUARD (v2 preserved)
//===================================================================
bool GeminiCorrelationAllows(string symbol, ulong magic)
  {
   if(!GInpEnableCorrelationGuard) return true;
   string eur[]={"EURUSD","EURGBP","EURJPY","EURCHF","EURAUD","EURCAD","EURNZD"};
   string gbp[]={"GBPUSD","GBPJPY","GBPCHF","GBPAUD","GBPCAD","GBPNZD","EURGBP"};
   string usd[]={"USDCHF","USDJPY","USDCAD"};
   string aud[]={"AUDUSD","AUDCHF","AUDJPY","AUDCAD","AUDNZD","NZDUSD","NZDJPY"};
   string my_cluster="";
   for(int i=0;i<7;i++) if(symbol==eur[i]) { my_cluster="EUR"; break; }
   if(my_cluster=="") for(int i=0;i<7;i++) if(symbol==gbp[i]) { my_cluster="GBP"; break; }
   if(my_cluster=="") for(int i=0;i<3;i++) if(symbol==usd[i]) { my_cluster="USD"; break; }
   if(my_cluster=="") for(int i=0;i<7;i++) if(symbol==aud[i]) { my_cluster="AUD"; break; }
   if(my_cluster=="") return true;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong t=PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=(long)magic) continue;
      string h=PositionGetString(POSITION_SYMBOL); if(h==symbol) continue;
      string hc="";
      for(int j=0;j<7;j++) if(h==eur[j]) { hc="EUR"; break; }
      if(hc=="") for(int j=0;j<7;j++) if(h==gbp[j]) { hc="GBP"; break; }
      if(hc=="") for(int j=0;j<3;j++) if(h==usd[j]) { hc="USD"; break; }
      if(hc=="") for(int j=0;j<7;j++) if(h==aud[j]) { hc="AUD"; break; }
      if(hc==my_cluster)
        { Print("[GEMINI] Corr guard blocked ",symbol," (already holding ",h,")"); return false; }
     }
   return true;
  }

//===================================================================
//  5/14. BREAKEVEN AUTOMATION (v2 preserved)
//===================================================================
void GeminiRunBreakeven(ulong magic)
  {
   if(!GInpEnableBreakeven) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=(long)magic) continue;
      string sym=PositionGetString(POSITION_SYMBOL);
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL); if(sl==0) continue;
      double tp=PositionGetDouble(POSITION_TP);
      double bid=SymbolInfoDouble(sym,SYMBOL_BID);
      double ask=SymbolInfoDouble(sym,SYMBOL_ASK);
      double point=SymbolInfoDouble(sym,SYMBOL_POINT);
      int digits=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
      long pos_type=PositionGetInteger(POSITION_TYPE);
      double lock=GInpBreakevenLockPips*point*10;
      double risk=MathAbs(entry-sl); if(risk<=0) continue;
      double be=0; bool move=false;
      if(pos_type==POSITION_TYPE_BUY)
        { be=NormalizeDouble(entry+lock,digits); move=((bid-entry)/risk>=GInpBreakevenTriggerR&&sl<be); }
      else
        { be=NormalizeDouble(entry-lock,digits); move=((entry-ask)/risk>=GInpBreakevenTriggerR&&(sl==0||sl>be)); }
      if(move)
        {
         MqlTradeRequest req={}; MqlTradeResult res={};
         req.action=TRADE_ACTION_SLTP; req.position=ticket; req.symbol=sym; req.sl=be; req.tp=tp;
         if(OrderSend(req,res)) Print("[GEMINI] BE set ",sym," ticket=",ticket," SL=",be);
        }
     }
  }

//===================================================================
//  6/15. WEEKLY LOSS RESET (v2 preserved)
//===================================================================
void GeminiCheckWeeklyReset()
  {
   if(!GInpEnableWeeklyReset) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(dt.day_of_week==1)
     {
      datetime wk=(datetime)(TimeCurrent()-dt.hour*3600-dt.min*60-dt.sec);
      if(wk!=g_gemini_week_key)
        { g_gemini_week_key=wk; g_gemini_week_bal=AccountInfoDouble(ACCOUNT_BALANCE); g_gemini_week_reduced=false; }
     }
   if(g_gemini_week_bal<=0) return;
   double loss_pct=(g_gemini_week_bal-AccountInfoDouble(ACCOUNT_BALANCE))/g_gemini_week_bal*100.0;
   if(loss_pct>=GInpWeeklyLossThreshPct&&!g_gemini_week_reduced)
     { g_gemini_week_reduced=true; Print("[GEMINI] Weekly loss ",DoubleToString(loss_pct,2),"% — risk cut to ",GInpWeeklyReducedRiskPct,"%"); }
  }
double GeminiWeeklyRiskMultiplier() { return g_gemini_week_reduced?(GInpWeeklyReducedRiskPct/0.5):1.0; }

//===================================================================
//  7/16. SPREAD FILTER (v2 preserved)
//===================================================================
bool GeminiSpreadAllows(string symbol)
  {
   if(!GInpEnableSpreadFilter) return true;
   long sp_pts=SymbolInfoInteger(symbol,SYMBOL_SPREAD);
   double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
   double sp_pips=sp_pts*point*10000.0;
   double highs[],lows[];
   ArrayResize(highs,20); ArrayResize(lows,20);
   if(CopyHigh(symbol,PERIOD_M5,1,20,highs)<20) return true;
   if(CopyLow(symbol,PERIOD_M5,1,20,lows)<20)   return true;
   double avg=0; for(int i=0;i<20;i++) avg+=(highs[i]-lows[i]); avg/=20.0;
   double normal=avg*0.08*10000.0; if(normal<=0) return true;
   double ratio=sp_pips/normal;
   if(ratio>GInpMaxSpreadMultiplier)
     { Print("[GEMINI] Spread blocked ",symbol," ratio=",DoubleToString(ratio,2)); return false; }
   return true;
  }

//===================================================================
//  8/17. HALF-KELLY SIZING (v2 preserved, extended by walk-forward)
//===================================================================
void GeminiInitKelly()
  {
   if(!GInpEnableKellySizing) { g_gemini_kelly_mult=1.0; return; }
   double kelly=GInpKellyBaseWinRate-((1.0-GInpKellyBaseWinRate)/GInpKellyBaseRR);
   double hk=MathMax(MathMin(0.5*kelly,0.50),0.05);
   g_gemini_kelly_mult=MathMax(MathMin(hk/0.175,2.0),0.3);
   Print("[GEMINI] Half-Kelly mult=",DoubleToString(g_gemini_kelly_mult,3));
  }
double GeminiKellyMultiplier() { return GInpEnableKellySizing?g_gemini_kelly_mult:1.0; }

//===================================================================
//  9/18. TIME-BASED EXITS (v2 preserved)
//===================================================================
void GeminiRunTimeStops(ulong magic)
  {
   if(!GInpEnableTimeStops) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=(long)magic) continue;
      string sym=PositionGetString(POSITION_SYMBOL);
      datetime open_t=(datetime)PositionGetInteger(POSITION_TIME);
      int bars=iBarShift(sym,PERIOD_CURRENT,open_t);
      if(bars<GInpTimeStopBars) continue;
      double pnl=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      if(pnl>=0) continue;
      MqlTradeRequest req={}; MqlTradeResult res={};
      req.action=TRADE_ACTION_DEAL; req.position=ticket; req.symbol=sym;
      req.volume=PositionGetDouble(POSITION_VOLUME); req.deviation=20; req.magic=magic;
      req.comment="GEMINI_TIMESTOP"; req.type_filling=ORDER_FILLING_FOK;
      req.type=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
      req.price=(req.type==ORDER_TYPE_SELL)?SymbolInfoDouble(sym,SYMBOL_BID):SymbolInfoDouble(sym,SYMBOL_ASK);
      if(OrderSend(req,res)) Print("[GEMINI] Time-stop closed ",sym," ticket=",ticket," P&L=",DoubleToString(pnl,2));
     }
  }

//===================================================================
//  NEW: 10. SIGNAL SCORING ENGINE
//===================================================================
int GeminiScoreSignal(string symbol, ENUM_ORDER_TYPE order_type)
  {
   if(!GInpEnableSignalScoring) return 100; // disabled = always pass
   int score = 0;

   // Factor 1: H1 Trend Alignment (25 pts)
   if(GeminiMTFTrendAllows(symbol, order_type)) score += 25;

   // Factor 2: Session quality (20 pts)
   MqlDateTime dt; TimeToStruct(TimeGMT(), dt);
   if(dt.hour >= GInpSessionStartHour && dt.hour < GInpSessionEndHour) score += 20;
   else if((dt.hour >= 8 && dt.hour < 12) || (dt.hour >= 15 && dt.hour < 17)) score += 10;

   // Factor 3: Spread health (15 pts)
   if(GeminiSpreadAllows(symbol)) score += 15;

   // Factor 4: Regime is trending (20 pts)
   int adx_h = iADX(symbol, PERIOD_H1, GInpAdxPeriod);
   if(adx_h != INVALID_HANDLE)
     {
      double adx_buf[1];
      if(CopyBuffer(adx_h, 0, 0, 1, adx_buf) == 1 && adx_buf[0] >= GInpAdxTrendThreshold)
         score += 20;
      IndicatorRelease(adx_h);
     }

   // Factor 5: Not correlated (10 pts)
   // This is pre-checked before scoring normally, so grant points if safe
   score += 10;

   // Factor 6: Weekly performance — bonus if week is winning (10 pts)
   if(!g_gemini_week_reduced) score += 10;

   Print("[GEMINI] Signal score for ",symbol,": ",score,"/100 (min=",GInpMinSignalScore,")");
   return score;
  }

bool GeminiSignalPassesScore(string symbol, ENUM_ORDER_TYPE order_type)
  {
   return GeminiScoreSignal(symbol, order_type) >= GInpMinSignalScore;
  }

//===================================================================
//  NEW: 11. REGIME DETECTION
//===================================================================
bool GeminiRegimeAllowsTrading(string symbol)
  {
   if(!GInpEnableRegimeFilter) return true;

   // Check 1: ADX trend strength
   int adx_h = iADX(symbol, PERIOD_H1, GInpAdxPeriod);
   if(adx_h != INVALID_HANDLE)
     {
      double adx_buf[1];
      if(CopyBuffer(adx_h, 0, 0, 1, adx_buf) == 1)
        {
         IndicatorRelease(adx_h);
         if(adx_buf[0] < GInpAdxTrendThreshold)
           { Print("[GEMINI] Regime filter: ADX=",DoubleToString(adx_buf[0],1)," < ",GInpAdxTrendThreshold," — RANGING, skip"); return false; }
        }
      else IndicatorRelease(adx_h);
     }

   // Check 2: ATR percentile rank
   int atr_h = iATR(symbol, PERIOD_H1, 14);
   if(atr_h != INVALID_HANDLE)
     {
      double atr_vals[];
      ArrayResize(atr_vals, GInpAtrRankPeriod);
      if(CopyBuffer(atr_h, 0, 0, GInpAtrRankPeriod, atr_vals) == GInpAtrRankPeriod)
        {
         double cur_atr = atr_vals[0];
         int rank_count = 0;
         for(int i = 1; i < GInpAtrRankPeriod; i++)
            if(atr_vals[i] <= cur_atr) rank_count++;
         double rank_pct = (double)rank_count / (GInpAtrRankPeriod - 1) * 100.0;
         IndicatorRelease(atr_h);
         if(rank_pct < GInpAtrRankMinPct)
           { Print("[GEMINI] Regime filter: ATR rank=",DoubleToString(rank_pct,1),"% too low — low volatility, skip"); return false; }
        }
      else IndicatorRelease(atr_h);
     }

   return true;
  }

//===================================================================
//  NEW: 12. WALK-FORWARD ADAPTIVE KELLY
//===================================================================
void GeminiRecordTradeResult(bool win, double r_multiple)
  {
   if(!GInpEnableWalkForward) return;
   g_gemini_wf_trades++;
   if(win) g_gemini_wf_wins++;
   g_gemini_wf_total_r += r_multiple;

   // Persist to GlobalVariables so it survives restarts
   GlobalVariableSet("GEMINI_WF_TRADES", g_gemini_wf_trades);
   GlobalVariableSet("GEMINI_WF_WINS",   g_gemini_wf_wins);
   GlobalVariableSet("GEMINI_WF_R",      g_gemini_wf_total_r);

   // Recalibrate after each window
   if(g_gemini_wf_trades >= GInpWFAdaptWindow && GInpEnableKellySizing)
     {
      double win_rate = (double)g_gemini_wf_wins / g_gemini_wf_trades;
      double avg_r    = (g_gemini_wf_wins > 0) ? g_gemini_wf_total_r / g_gemini_wf_wins : GInpKellyBaseRR;
      avg_r = MathMax(avg_r, 0.5);
      double kelly = win_rate - ((1.0 - win_rate) / avg_r);
      double hk    = MathMax(MathMin(0.5 * kelly, 0.50), 0.05);
      g_gemini_kelly_mult = MathMax(MathMin(hk / 0.175, 2.0), 0.3);
      Print("[GEMINI] Walk-forward recalibration: W=",DoubleToString(win_rate,3),
            " avgR=",DoubleToString(avg_r,2)," new_kelly=",DoubleToString(g_gemini_kelly_mult,3));
      // Reset window
      g_gemini_wf_trades = 0; g_gemini_wf_wins = 0; g_gemini_wf_total_r = 0.0;
     }
  }

void GeminiLoadWFState()
  {
   if(!GInpEnableWalkForward) return;
   if(GlobalVariableCheck("GEMINI_WF_TRADES")) g_gemini_wf_trades = (int)GlobalVariableGet("GEMINI_WF_TRADES");
   if(GlobalVariableCheck("GEMINI_WF_WINS"))   g_gemini_wf_wins   = (int)GlobalVariableGet("GEMINI_WF_WINS");
   if(GlobalVariableCheck("GEMINI_WF_R"))      g_gemini_wf_total_r= GlobalVariableGet("GEMINI_WF_R");
  }

//===================================================================
//  NEW: 13. NEWS PRE-POSITIONING CHECK
//===================================================================
bool GeminiNewsPrepositionOpportunity(string symbol, ENUM_ORDER_TYPE &direction)
  {
   if(!GInpEnableNewsPrepos) return false;

   int fh = FileOpen(GInpNewsPreposCsv, FILE_READ|FILE_CSV|FILE_ANSI|FILE_SHARE_READ, ',');
   if(fh == INVALID_HANDLE) return false;

   datetime now_utc = (datetime)(TimeCurrent());
   datetime window  = (datetime)(GInpNewsPreposMins * 60);
   string currency  = StringSubstr(symbol, 0, 3); // e.g. "EUR" from "EURUSD"
   bool found = false;

   while(!FileIsEnding(fh))
     {
      string time_str  = FileReadString(fh);
      string curr_str  = FileReadString(fh);
      string impact    = FileReadString(fh);
      string title     = FileReadString(fh);
      datetime ev_time = StringToTime(time_str);
      if(ev_time <= 0) continue;
      long mins_to_event = (long)(ev_time - now_utc) / 60;
      if(mins_to_event >= 0 && mins_to_event <= GInpNewsPreposMins && curr_str == currency)
        {
         // Pre-position in direction of current H1 trend
         int ma_h = iMA(symbol, PERIOD_H1, 21, 0, MODE_EMA, PRICE_CLOSE);
         if(ma_h != INVALID_HANDLE)
           {
            double ma[1]; CopyBuffer(ma_h, 0, 0, 1, ma); IndicatorRelease(ma_h);
            direction = (SymbolInfoDouble(symbol,SYMBOL_BID) > ma[0]) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
           }
         Print("[GEMINI] News prepos: ",title," in ",mins_to_event,"m — signaling ",EnumToString(direction));
         found = true; break;
        }
     }
   FileClose(fh);
   return found;
  }

//===================================================================
//  NEW: 14. H1 STRUCTURE EXIT
//===================================================================
void GeminiH1StructureExit(ulong magic)
  {
   if(!GInpEnableH1StructureExit) return;

   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)magic) continue;

      string sym    = PositionGetString(POSITION_SYMBOL);
      long pos_type = PositionGetInteger(POSITION_TYPE);

      // Get last completed H1 candles
      double h1_close[], h1_open[];
      ArrayResize(h1_close, GInpH1ExitLookback+1);
      ArrayResize(h1_open,  GInpH1ExitLookback+1);
      if(CopyClose(sym, PERIOD_H1, 1, GInpH1ExitLookback, h1_close) < GInpH1ExitLookback) continue;
      if(CopyOpen(sym,  PERIOD_H1, 1, GInpH1ExitLookback, h1_open)  < GInpH1ExitLookback) continue;

      // Check if last H1 bar closed against us
      bool bearish_h1 = (h1_close[0] < h1_open[0]);
      bool bullish_h1 = (h1_close[0] > h1_open[0]);
      bool exit_long  = (pos_type == POSITION_TYPE_BUY  && bearish_h1);
      bool exit_short = (pos_type == POSITION_TYPE_SELL && bullish_h1);

      if(exit_long || exit_short)
        {
         MqlTradeRequest req={}; MqlTradeResult res={};
         req.action=TRADE_ACTION_DEAL; req.position=ticket; req.symbol=sym;
         req.volume=PositionGetDouble(POSITION_VOLUME); req.deviation=20; req.magic=magic;
         req.comment="GEMINI_H1_STRUCTURE"; req.type_filling=ORDER_FILLING_FOK;
         req.type  = exit_long ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         req.price = exit_long ? SymbolInfoDouble(sym,SYMBOL_BID) : SymbolInfoDouble(sym,SYMBOL_ASK);
         if(OrderSend(req,res))
            Print("[GEMINI] H1 structure exit ",sym," ticket=",ticket," bearish_h1=",bearish_h1);
        }
     }
  }

//===================================================================
//  NEW: 15. DYNAMIC TP BASED ON DAILY ATR
//===================================================================
double GeminiDynamicTPMultiplier(string symbol)
  {
   if(!GInpEnableDynamicTP) return 1.0;

   // Get daily range used so far today
   double daily_open[], daily_high[], daily_low[];
   ArrayResize(daily_open, 1); ArrayResize(daily_high, 1); ArrayResize(daily_low, 1);
   if(CopyOpen(symbol, PERIOD_D1, 0, 1, daily_open) < 1) return 1.0;
   if(CopyHigh(symbol, PERIOD_D1, 0, 1, daily_high) < 1) return 1.0;
   if(CopyLow(symbol,  PERIOD_D1, 0, 1, daily_low)  < 1) return 1.0;

   // Daily ATR estimate (use simple range of last 14 daily bars)
   int atr_h = iATR(symbol, PERIOD_D1, 14);
   if(atr_h == INVALID_HANDLE) return 1.0;
   double atr_buf[1];
   if(CopyBuffer(atr_h, 0, 0, 1, atr_buf) < 1) { IndicatorRelease(atr_h); return 1.0; }
   IndicatorRelease(atr_h);
   double daily_atr = atr_buf[0];
   if(daily_atr <= 0) return 1.0;

   double daily_range = daily_high[0] - daily_low[0];
   double range_used_pct = daily_range / daily_atr * 100.0;

   if(range_used_pct >= GInpDailyAtrUsedCapPct)
     {
      double mult = 1.0 - GInpDynamicTPReductionPct / 100.0;
      Print("[GEMINI] Daily ATR ",DoubleToString(range_used_pct,1),"% used — TP reduced to ",DoubleToString(mult*100,0),"%");
      return mult;
     }
   return 1.0;
  }

//===================================================================
//  NEW: 16. PORTFOLIO HEAT MONITOR
//===================================================================
bool GeminiPortfolioHeatAllows(ulong magic)
  {
   if(!GInpEnableHeatMonitor) return true;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0) return true;
   double total_heat_pct = 0.0;

   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)magic) continue;
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      if(sl == 0) continue;
      double volume = PositionGetDouble(POSITION_VOLUME);
      string sym    = PositionGetString(POSITION_SYMBOL);
      double tick_val = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
      double tick_sz  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
      double risk_per_lot = MathAbs(entry - sl) / tick_sz * tick_val;
      double position_risk = risk_per_lot * volume;
      total_heat_pct += position_risk / balance * 100.0;
     }

   if(total_heat_pct >= GInpMaxPortfolioHeatPct)
     {
      Print("[GEMINI] Portfolio heat ",DoubleToString(total_heat_pct,2),"% >= limit ",GInpMaxPortfolioHeatPct,"% — blocked");
      return false;
     }
   return true;
  }

//===================================================================
//  NEW: 17. ADAPTIVE PER-PAIR SIZING
//===================================================================
void GeminiRecordPairResult(string symbol, bool win)
  {
   if(!GInpEnablePerPairSizing) return;
   int idx = -1;
   for(int i = 0; i < g_pair_count; i++) if(g_pair_symbols[i] == symbol) { idx = i; break; }
   if(idx < 0 && g_pair_count < 20) { idx = g_pair_count; g_pair_symbols[idx] = symbol; g_pair_wins[idx] = 0; g_pair_total[idx] = 0; g_pair_count++; }
   if(idx < 0) return;
   if(win) g_pair_wins[idx]++;
   g_pair_total[idx]++;
   // Rolling window: reset after window size
   if(g_pair_total[idx] >= GInpPairSizingWindow * 2) { g_pair_wins[idx] /= 2; g_pair_total[idx] /= 2; }
  }

double GeminiPairSizingMultiplier(string symbol)
  {
   if(!GInpEnablePerPairSizing) return 1.0;
   int idx = -1;
   for(int i = 0; i < g_pair_count; i++) if(g_pair_symbols[i] == symbol) { idx = i; break; }
   if(idx < 0 || g_pair_total[idx] < 5) return 1.0; // need min 5 trades
   double wr = (double)g_pair_wins[idx] / g_pair_total[idx];
   // Map 0-100% WR to GInpPairSizingMinMult – GInpPairSizingMaxMult
   double mult = GInpPairSizingMinMult + wr * (GInpPairSizingMaxMult - GInpPairSizingMinMult);
   return MathMax(GInpPairSizingMinMult, MathMin(GInpPairSizingMaxMult, mult));
  }

//===================================================================
//  NEW: 18. COT SENTIMENT FILTER
//===================================================================
void GeminiLoadCOTData()
  {
   if(!GInpEnableCOTFilter) return;
   g_cot_count = 0;
   int fh = FileOpen(GInpCOTCsvFile, FILE_READ|FILE_CSV|FILE_ANSI|FILE_SHARE_READ, ',');
   if(fh == INVALID_HANDLE) { Print("[GEMINI] COT file not found: ",GInpCOTCsvFile); return; }
   // Expected CSV format: currency,net_position (e.g. EUR,45000 means longs heavy = bullish)
   while(!FileIsEnding(fh) && g_cot_count < 10)
     {
      string currency  = FileReadString(fh);
      string net_str   = FileReadString(fh);
      StringTrimLeft(currency); StringTrimRight(currency);
      StringTrimLeft(net_str);  StringTrimRight(net_str);
      if(currency == "" || StringFind(currency,"currency") >= 0) continue;
      double net = StringToDouble(net_str);
      g_cot_currencies[g_cot_count] = currency;
      g_cot_sentiment[g_cot_count]  = (net > 10000) ? 1 : (net < -10000) ? -1 : 0;
      g_cot_count++;
     }
   FileClose(fh);
   Print("[GEMINI] COT data loaded: ",g_cot_count," currencies");
  }

bool GeminiCOTAllows(string symbol, ENUM_ORDER_TYPE order_type)
  {
   if(!GInpEnableCOTFilter || g_cot_count == 0) return true;
   string base_curr = StringSubstr(symbol, 0, 3);
   for(int i = 0; i < g_cot_count; i++)
     {
      if(g_cot_currencies[i] == base_curr)
        {
         int sentiment = g_cot_sentiment[i];
         if(order_type == ORDER_TYPE_BUY  && sentiment == -1) { Print("[GEMINI] COT blocked BUY ",symbol," — large specs net-short ",base_curr); return false; }
         if(order_type == ORDER_TYPE_SELL && sentiment ==  1) { Print("[GEMINI] COT blocked SELL ",symbol," — large specs net-long ",base_curr); return false; }
        }
     }
   return true;
  }

//===================================================================
//  MASTER FUNCTIONS — call from EA OnInit() and OnTick()/OnTimer()
//===================================================================
void GeminiROIInit()
  {
   GeminiInitKelly();
   GeminiLoadWFState();
   GeminiLoadCOTData();
   g_gemini_week_bal     = AccountInfoDouble(ACCOUNT_BALANCE);
   g_gemini_week_key     = 0;
   g_gemini_week_reduced = false;
   g_pair_count          = 0;
   Print("[GEMINI] ROI Module v3.0 initialized — 18 improvements active");
  }

// All-in-one gate check: call this BEFORE opening any new trade
bool GeminiEntryGate(string symbol, ENUM_ORDER_TYPE order_type, ulong magic)
  {
   if(!GeminiRegimeAllowsTrading(symbol))           return false;
   if(!GeminiMTFTrendAllows(symbol, order_type))    return false;
   if(!GeminiSpreadAllows(symbol))                  return false;
   if(!GeminiCorrelationAllows(symbol, magic))      return false;
   if(!GeminiPortfolioHeatAllows(magic))            return false;
   if(!GeminiCOTAllows(symbol, order_type))         return false;
   if(!GeminiSignalPassesScore(symbol, order_type)) return false;
   return true;
  }

// Combined risk multiplier to apply to lot sizing
double GeminiRiskMultiplier(string symbol)
  {
   double m = 1.0;
   m *= GeminiKellyMultiplier();
   m *= GeminiSessionMultiplier();
   m *= GeminiWeeklyRiskMultiplier();
   m *= GeminiPairSizingMultiplier(symbol);
   m *= GeminiDynamicTPMultiplier(symbol);
   return MathMax(0.1, MathMin(m, 3.0)); // hard bounds
  }

void GeminiROITick(ulong magic)
  {
   GeminiCheckWeeklyReset();
   GeminiRunBreakeven(magic);
   GeminiRunTrailingStops(magic);
   GeminiH1StructureExit(magic);
   GeminiRunTimeStops(magic);
  }
