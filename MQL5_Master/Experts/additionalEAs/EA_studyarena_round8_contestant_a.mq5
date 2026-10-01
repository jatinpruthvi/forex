//+------------------------------------------------------------------+
//| EA_studyarena_round8_contestant_a.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 8A - London sweep-and-reclaim on borrowed capital with a 6% monthly stop
//| Source document : docs/research/study_arena/studyarena-round8-contestant-a.md
//| Tracker entry   : #59  |  Magic: 2026
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound8A class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 8A - London sweep-and-reclaim on borrowed capital with a 6% monthly stop"
#property description "Source: docs/research/study_arena/studyarena-round8-contestant-a.md"

#include "..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD";      // Comma separated universe
input double          InpRiskPct          = 0.75;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 6.0;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 20;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 2;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2026; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpRangeLowPct       = 35.0;  // Asian range floor (% of 20-day median)
input double InpRangeHighPct      = 75.0;  // Asian range ceiling
input double InpAdxLow            = 18.0;  // H1 ADX band
input double InpAdxHigh           = 35.0;  // H1 ADX ceiling
input double InpChandelierMult    = 2.50;  // Runner trail: high - 2.5 x H1 ATR
input int    InpFlatMin           = 21 * 60;  // Flat by 21:00 UK

//+------------------------------------------------------------------+
//| Strategy: Round 8A - London sweep-and-reclaim on borrowed capital with a 6% monthly stop
//+------------------------------------------------------------------+
class CRound8A : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R8A_LONDON_RECLAIM";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round8-contestant-a.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;              // 0.75%
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.totalDdPct            = InpTotalDdPct;           // own-account hard monthly stop
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 900;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;
      cfg.breakEvenAtR          = 1.00;
      cfg.trailAtR              = 1.00;  cfg.trailDistanceR = 1.00;
      cfg.timeStopMinutes       = 0;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      if(!RangeQualifies(ctx)) return false;
      if(ctx.adx14 < InpAdxLow || ctx.adx14 > InpAdxHigh) return false;
      if(!H1BiasAgrees(ctx)) return false;

      SSweepParams p;
      p.Reset();
      p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
      p.sessionFromMin = 7 * 60; p.sessionToMin = 12 * 60;
      p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
      p.reclaimWindowBars = 3;
      p.wickRatio = 0.60; p.bodyRatio = 0.60;
      p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
      p.entryRetrace = 0.50; p.targetR = 3.0;
      if(!SigSweepReclaim(ctx, p, plan)) return false;
      plan.reason = "R8A-SWEEPRECLAIM " + plan.reason;
      return true;
   }

   bool RangeQualifies(SEAContext &ctx)
   {
      double hi = 0.0, lo = 0.0;
      if(!SigAsianRange(ctx.symbol, hi, lo)) return false;
      double median = MedianRange(ctx.symbol);
      if(median <= 0.0) return false;
      double ratio = (hi - lo) / median;
      if(ratio < InpRangeLowPct / 100.0 || ratio > InpRangeHighPct / 100.0) return false;
      double pip = EA_PipSize(ctx.symbol);
      if(pip <= 0.0) return false;
      double pips = (hi - lo) / pip;
      if(StringFind(ctx.symbol, "GBPUSD") >= 0) return (pips <= 45.0);
      return (pips <= 35.0);                             // fuel already burned above this
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

   bool H1BiasAgrees(SEAContext &ctx)
   {
      if(ctx.emaH1_50 <= 0.0) return false;
      bool up = (ctx.mid > ctx.emaH1_50 && ctx.ema50 > ctx.emaH1_50);
      bool dn = (ctx.mid < ctx.emaH1_50 && ctx.ema50 < ctx.emaH1_50);
      return (up || dn);
   }

   //--- mechanical chandelier trail on the remaining half, no take-profit
   void Manage(SEAContext &ctx)
   {
      for(int t = 0; t < g_eaTrackCount; t++)
      {
         if(g_eaTrack[t].symbol != ctx.symbol) continue;
         if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double cur   = PositionGetDouble(POSITION_PRICE_CURRENT);
         double risk  = g_eaTrack[t].riskDist;
         if(risk <= 0.0) continue;
         double rMult = (g_eaTrack[t].dir > 0) ? (cur - entry) / risk : (entry - cur) / risk;
         if(rMult < 1.0) continue;
         double h1Atr = H1Atr(ctx);
         if(h1Atr <= 0.0) continue;
         MqlRates r[];
         if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 20, r) < 5) continue;
         double hh = r[0].high, ll = r[0].low;
         for(int i = 1; i < 20; i++) { hh = MathMax(hh, r[i].high); ll = MathMin(ll, r[i].low); }
         double newSl = (g_eaTrack[t].dir > 0) ? hh - InpChandelierMult * h1Atr
                                               : ll + InpChandelierMult * h1Atr;
         double oldSl = PositionGetDouble(POSITION_SL);
         if(g_eaTrack[t].dir > 0 && newSl > oldSl) g_eaExec.Modify(g_eaTrack[t].ticket, newSl, 0.0);
         if(g_eaTrack[t].dir < 0 && (oldSl == 0.0 || newSl < oldSl))
            g_eaExec.Modify(g_eaTrack[t].ticket, newSl, 0.0);
      }
   }

   double H1Atr(SEAContext &ctx)
   {
      double av[];
      if(EA_BufN(g_eaInd[ctx.index].hAtrD1, 0, 1, 20, av) < 5) return 0.0;
      return (av[0] > 0.0) ? av[0] / 6.0 : 0.0;
   }
};

CRound8A g_Round8A;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round8A);
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
