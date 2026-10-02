//+------------------------------------------------------------------+
//| EA_studyarena_round12_qwen3_8_2_4t_a95b_high_reasoning.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 12 Qwen - SWEEP-1 definitive with session flat times and overlap discipline
//| Source document : docs/research/study_arena/studyarena-round12-qwen3-8-2-4t-a95b-high-reasoning.md
//| Tracker entry   : #79  |  Magic: 2046
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound12Qwen class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 12 Qwen - SWEEP-1 definitive with session flat times and overlap discipline"
#property description "Source: docs/research/study_arena/studyarena-round12-qwen3-8-2-4t-a95b-high-reasoning.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "AUDNZD,EURGBP,EURUSD,GBPUSD,XAUUSD,USDJPY,GBPJPY";      // Comma separated universe
input double          InpRiskPct          = 0.60;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 0;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 20;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 8;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2046; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input int    InpAsiaMaxConcurrent  = 2;     // Session concurrency caps
input int    InpLondonMaxConcurrent = 3;
input int    InpNyMaxConcurrent     = 2;
input int    InpMaxTotalOpen        = 4;     // Max four open positions overall
input int    InpMaxSessionTrades    = 3;     // Completed trades per session

//+------------------------------------------------------------------+
//| Strategy: Round 12 Qwen - SWEEP-1 definitive with session flat times and overlap discipline
//+------------------------------------------------------------------+
class CRound12Qwen : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R12QWEN_SWEEP1_DEFINITIVE";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round12-qwen3-8-2-4t-a95b-high-reasoning.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = InpMaxTotalOpen;
      cfg.minSecondsBetweenTrades = 300;
      cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 20;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;
      cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 30.0;
      cfg.breakEvenAtR          = 1.00;
      cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 1.00;
      cfg.useLimitEntry         = true;
      cfg.pendingExpiryMinutes  = 15;
      cfg.timeStopMinutes       = 240;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      int fromMin, toMin, sessFrom, sessTo, maxConcurrent;
      if(!SessionMap(ctx, fromMin, toMin, sessFrom, sessTo, maxConcurrent)) return false;
      if(ConcurrentForSession(sessFrom) >= maxConcurrent) return false;
      if(TradesThisSession(sessFrom) >= InpMaxSessionTrades) return false;
      if(CorrelatedPositionOpen(ctx)) return false;

      double hi = 0.0, lo = 0.0;
      if(!RangeBetween(ctx.symbol, fromMin, toMin, hi, lo)) return false;
      double median = MedianRange(ctx.symbol);
      if(median <= 0.0) return false;
      double ratio = (hi - lo) / median;
      if(ratio < 0.35 || ratio > 0.75) return false;               // manipulation bait vs spent fuel

      SSweepParams p;
      p.Reset();
      p.rangeFromMin = fromMin; p.rangeToMin = toMin;
      p.sessionFromMin = sessFrom; p.sessionToMin = sessTo;
      p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
      p.reclaimWindowBars = 3;
      p.wickRatio = 0.60; p.bodyRatio = 0.60;
      p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
      p.entryRetrace = 0.50; p.targetR = 2.0;
      if(!SigSweepReclaim(ctx, p, plan)) return false;
      if(!BiasAgrees(ctx, plan.dir)) return false;
      plan.reason = StringFormat("R12QWEN-%sSWEEP1 %s",
                                  sessFrom == 7 * 60 ? "LONDON" : (sessFrom >= 13 * 60 + 30 ? "NY" : "ASIA"),
                                  plan.reason);
      return true;
   }

   bool SessionMap(SEAContext &ctx, int &fromMin, int &toMin, int &sessFrom, int &sessTo, int &maxConcurrent)
   {
      //--- Asia flat 06:00, London flat 16:00, NY flat 20:00; overlap 13:30-16:00 is NY-only
      if(ctx.clockMinutes < 6 * 60 && (StringFind(ctx.symbol, "AUDNZD") >= 0 ||
                                       StringFind(ctx.symbol, "EURGBP") >= 0))
      { fromMin = 20 * 60; toMin = 24 * 60; sessFrom = 0; sessTo = 6 * 60; maxConcurrent = InpAsiaMaxConcurrent; return true; }
      if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 13 * 60 + 30 &&
         (StringFind(ctx.symbol, "EURUSD") >= 0 || StringFind(ctx.symbol, "GBPUSD") >= 0 ||
          StringFind(ctx.symbol, "XAU") >= 0 || StringFind(ctx.symbol, "GBPJPY") >= 0))
      { fromMin = 0; toMin = 7 * 60; sessFrom = 7 * 60; sessTo = 16 * 60; maxConcurrent = InpLondonMaxConcurrent; return true; }
      if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 20 * 60 &&
         (StringFind(ctx.symbol, "XAU") >= 0 || StringFind(ctx.symbol, "USDJPY") >= 0))
      { fromMin = 7 * 60; toMin = 13 * 60; sessFrom = 13 * 60 + 30; sessTo = 20 * 60; maxConcurrent = InpNyMaxConcurrent; return true; }
      return false;
   }

   double MedianRange(const string sym)
   {
      MqlRates d[];
      if(EA_Rates(sym, PERIOD_D1, 1, 20, d) < 10) return 0.0;
      double s[];
      ArrayResize(s, 20);
      for(int i = 0; i < 20; i++) s[i] = d[i].high - d[i].low;
      ArraySort(s);
      return s[10];
   }

   bool RangeBetween(const string sym, const int fromMin, const int toMin, double &hi, double &lo)
   {
      MqlRates r[];
      if(EA_Rates(sym, PERIOD_M15, 1, 400, r) < 30) return false;
      bool wrap = (fromMin > toMin);
      int i = 0;
      for(; i < 400; i++)
      {
         MqlDateTime t;
         TimeToStruct(r[i].time, t);
         int m = t.hour * 60 + t.min;
         bool inWin = wrap ? (m >= fromMin || m < toMin) : (m >= fromMin && m < toMin);
         if(inWin) break;
      }
      if(i >= 400) return false;
      hi = 0.0; lo = 0.0;
      bool found = false;
      for(; i < 400; i++)
      {
         MqlDateTime t;
         TimeToStruct(r[i].time, t);
         int m = t.hour * 60 + t.min;
         bool inWin = wrap ? (m >= fromMin || m < toMin) : (m >= fromMin && m < toMin);
         if(!inWin) break;
         if(!found) { hi = r[i].high; lo = r[i].low; found = true; }
         else { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }
      }
      return found;
   }

   bool BiasAgrees(SEAContext &ctx, const int dir)
   {
      bool asianPair = (StringFind(ctx.symbol, "AUDNZD") >= 0 || StringFind(ctx.symbol, "EURGBP") >= 0);
      if(asianPair && ctx.adx14 < 16.0) return true;
      if(ctx.emaH1_50 <= 0.0) return false;
      double h1Atr = (ctx.atrD1 > 0.0) ? ctx.atrD1 / 6.0 : 0.0;
      if(h1Atr <= 0.0) return false;
      //--- slope measured over the last five H1 candles (approx: 5 x 1/6 of the daily ATR)
      double slope = ctx.emaH1_50 - ctx.emaH1_200;
      if(dir > 0) return (ctx.mid > ctx.emaH1_50 && slope >= -0.05 * h1Atr);
      return (ctx.mid < ctx.emaH1_50 && slope <= 0.05 * h1Atr);
   }

   bool CorrelatedPositionOpen(SEAContext &ctx)
   {
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         string other = PositionGetString(POSITION_SYMBOL);
         if(other == ctx.symbol) continue;
         bool usdA = (StringFind(ctx.symbol, "USD") >= 0);
         bool usdB = (StringFind(other, "USD") >= 0);
         if(usdA && usdB) return true;
      }
      return false;
   }

   int ConcurrentForSession(const int sessFrom)
   {
      int n = 0;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(sessFrom == 0 && !IsAsianSymbol(PositionGetString(POSITION_SYMBOL))) continue;
         n++;
      }
      return n;
   }

   bool IsAsianSymbol(const string sym)
   {
      return (StringFind(sym, "AUDNZD") >= 0 || StringFind(sym, "EURGBP") >= 0);
   }

   int TradesThisSession(const int sessFrom)
   {
      if(!HistorySelect(TimeCurrent() - 3 * 24 * 3600, TimeCurrent())) return 0;
      MqlDateTime dt;
      TimeToStruct(TimeTradeServer(), dt);
      int nowMin = dt.hour * 60 + dt.min;
      int elapsed = nowMin - sessFrom;
      if(elapsed < 0) elapsed += 24 * 60;
      datetime from = TimeTradeServer() - (datetime)(elapsed * 60);
      int n = 0;
      for(int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagicNumber) continue;
         if(HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
         if((datetime)HistoryDealGetInteger(t, DEAL_TIME) < from) continue;
         n++;
      }
      return n;
   }
};

CRound12Qwen g_Round12Qwen;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round12Qwen);
}

void OnTick()
{
   EA_Tick();
}

void OnDeinit(const int reason)
{
   EA_Deinit(reason);
}
//+------------------------------------------------------------------+
