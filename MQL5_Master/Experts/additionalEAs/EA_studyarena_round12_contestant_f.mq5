//+------------------------------------------------------------------+
//| EA_studyarena_round12_contestant_f.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 12F - SOS-SWEEP veteran: five gates, one-position correlation rule, 1.2% heat cap
//| Source document : docs/research/study_arena/studyarena-round12-contestant-f.md
//| Tracker entry   : #78  |  Magic: 2045
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound12F class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 12F - SOS-SWEEP veteran: five gates, one-position correlation rule, 1.2% heat cap"
#property description "Source: docs/research/study_arena/studyarena-round12-contestant-f.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "AUDNZD,EURGBP,EURUSD,GBPUSD,XAUUSD,USDJPY";      // Comma separated universe
input double          InpRiskPct          = 0.60;   // Base risk per trade (% of equity)
input int             InpMaxTradesPerDay  = 6;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2045; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input int    InpMinScore           = 7;     // Score >= 7/8 to fire
input double InpMaxOpenRiskPct    = 1.20;  // Max total open risk
input int    InpMaxOpenPositions  = 4;     // Max four open positions
input double InpWickRatio         = 0.60;  // Sweep wick >= 60% of the candle

//+------------------------------------------------------------------+
//| Strategy: Round 12F - SOS-SWEEP veteran: five gates, one-position correlation rule, 1.2% heat cap
//+------------------------------------------------------------------+
class CRound12F : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R12F_SOS_SWEEP_VET";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round12-contestant-f.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = InpMaxOpenPositions;
      cfg.minSecondsBetweenTrades = 300;
      cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 20;  cfg.sessionEndMin   = 30;
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
      if(EA_OpenRiskPct() > InpMaxOpenRiskPct) return false;
      if(EA_CountPositions("", false) >= InpMaxOpenPositions) return false;
      if(CorrelatedPositionOpen(ctx)) return false;

      int fromMin, toMin, sessFrom, sessTo;
      if(!SessionMap(ctx, fromMin, toMin, sessFrom, sessTo)) return false;

      double hi = 0.0, lo = 0.0;
      if(!RangeBetween(ctx.symbol, fromMin, toMin, hi, lo)) return false;
      double median = MedianRange(ctx.symbol);
      if(median <= 0.0) return false;
      double ratio = (hi - lo) / median;
      if(ratio < 0.35 || ratio > 0.75) return false;

      SSweepParams p;
      p.Reset();
      p.rangeFromMin = fromMin; p.rangeToMin = toMin;
      p.sessionFromMin = sessFrom; p.sessionToMin = sessTo;
      p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
      p.reclaimWindowBars = 3;
      p.wickRatio = InpWickRatio; p.bodyRatio = 0.60;
      p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
      p.entryRetrace = 0.50; p.targetR = 2.0;
      if(!SigSweepReclaim(ctx, p, plan)) return false;
      if(!BiasAgrees(ctx, plan.dir)) return false;

      int score = ScoreGate(ctx, plan);
      if(score < InpMinScore) return false;
      plan.score  = score * 12.5;
      plan.reason = StringFormat("R12F-SOSSOSWEEP(%d/8) %s", score, plan.reason);
      return true;
   }

   bool SessionMap(SEAContext &ctx, int &fromMin, int &toMin, int &sessFrom, int &sessTo)
   {
      if(ctx.clockMinutes < 6 * 60 + 30 && (StringFind(ctx.symbol, "AUDNZD") >= 0 ||
                                            StringFind(ctx.symbol, "EURGBP") >= 0))
      { fromMin = 21 * 60; toMin = 24 * 60; sessFrom = 0; sessTo = 6 * 60 + 30; return true; }
      if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 16 * 60 + 30 &&
         (StringFind(ctx.symbol, "EURUSD") >= 0 || StringFind(ctx.symbol, "GBPUSD") >= 0 ||
          StringFind(ctx.symbol, "XAU") >= 0))
      { fromMin = 0; toMin = 7 * 60; sessFrom = 7 * 60; sessTo = 16 * 60 + 30; return true; }
      if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 20 * 60 + 30 &&
         (StringFind(ctx.symbol, "XAU") >= 0 || StringFind(ctx.symbol, "USDJPY") >= 0))
      { fromMin = 7 * 60; toMin = 13 * 60; sessFrom = 13 * 60 + 30; sessTo = 20 * 60 + 30; return true; }
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
      return (dir > 0) ? (ctx.mid > ctx.emaH1_50) : (ctx.mid < ctx.emaH1_50);
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

   int ScoreGate(SEAContext &ctx, SSignalPlan &plan)
   {
      int score = 4;
      if(ctx.adx14 >= 16.0 && ctx.adx14 <= 40.0) score++;
      double costR = (plan.riskDist > 0.0) ? (ctx.spreadPoints * ctx.point) / plan.riskDist : 1.0;
      if(costR <= 0.10) score++;
      if(ctx.atrD1 > 0.0 && ctx.atr > 0.35 * ctx.atrD1) score++;
      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M5, 1, 22, r) >= 21)
      {
         double vsum = 0.0;
         for(int i = 1; i <= 20; i++) vsum += (double)r[i].tick_volume;
         if(vsum > 0.0 && r[0].tick_volume >= 1.2 * (vsum / 20.0)) score++;
      }
      return MathMin(score, 8);
   }
};

CRound12F g_Round12F;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round12F);
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
