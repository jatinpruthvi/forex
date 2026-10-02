//+------------------------------------------------------------------+
//| EA_studyarena_round11_contestant_f.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 11F - TRIAD: one edge, three decorrelated expressions at 0.24% per sleeve
//| Source document : docs/research/study_arena/studyarena-round11-contestant-f.md
//| Tracker entry   : #73  |  Magic: 2040
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound11F class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 11F - TRIAD: one edge, three decorrelated expressions at 0.24% per sleeve"
#property description "Source: docs/research/study_arena/studyarena-round11-contestant-f.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY,XAUUSD,EURGBP,AUDNZD";      // Comma separated universe
input int             InpMaxTradesPerDay  = 6;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2040; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpPerSleeveRiskPct  = 0.24;  // ~1/20th Kelly per sleeve
input double InpMaxOpenRiskPct    = 1.00;  // Total open risk ceiling
input int    InpMaxPerSleeve      = 2;     // Max concurrent positions per sleeve
input int    InpMaxTotal          = 4;     // Max concurrent positions overall
input double InpSpreadAvgX        = 2.00;  // Skip entry when spread > this x its 60-min median
input double InpMaxSpreadStopPct  = 15.0;  // Skip entry when spread > this % of the stop distance
input double InpMaxSlipPctOfExp   = 20.0;  // Disable a symbol whose slippage eats this % of expectancy

//+------------------------------------------------------------------+
//| Strategy: Round 11F - TRIAD: one edge, three decorrelated expressions at 0.24% per sleeve
//+------------------------------------------------------------------+
class CRound11F : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R11F_TRIAD_SLEEVES";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round11-contestant-f.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpPerSleeveRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = InpMaxTotal;
      cfg.minSecondsBetweenTrades = 300;
      cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;
      cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 30.0;
      cfg.breakEvenAtR          = 1.00;
      cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 1.00;
      cfg.timeStopMinutes       = 240;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      if(EA_OpenRiskPct() > InpMaxOpenRiskPct) return false;
      //--- survival table: spread vs its own 60-min baseline, and slippage vs expectancy
      double spRef = EA_SpreadMedianRecent(ctx.symbol, 60);
      if(spRef > 0.0 && ctx.spreadPoints > InpSpreadAvgX * spRef)
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.1f pts > %.1fx its 60-min median %.1f - skip",
                ctx.symbol, ctx.spreadPoints, InpSpreadAvgX, spRef), true);
         return false;
      }
      if(!EA_SymbolSlippageOk(ctx.symbol, InpMaxSlipPctOfExp))
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("%s disabled: slippage eats > %.0f%% of expectancy",
                ctx.symbol, InpMaxSlipPctOfExp), true);
         return false;
      }
      if(TotalOpen() >= InpMaxTotal) return false;

      //--- Sleeve A: session-open sweep & reclaim (the core, M5)
      if(TotalForSleeve(1) < InpMaxPerSleeve)
      {
         SSweepParams p;
         p.Reset();
         p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
         p.sessionFromMin = 7 * 60; p.sessionToMin = 16 * 60;
         p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
         p.reclaimWindowBars = 3;
         p.wickRatio = 0.60; p.bodyRatio = 0.60;
         p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
         p.entryRetrace = 0.50; p.targetR = 2.0;
         if(SigSweepReclaim(ctx, p, plan))
         { m_sleeve = 1; plan.reason = "R11F-A-SWEEP " + plan.reason; return CostOk(ctx, plan); }
      }

      //--- Sleeve B: volatility-expansion continuation (deliberately opposite regime)
      if(TotalForSleeve(2) < InpMaxPerSleeve && ctx.adx14 > 25.0)
      {
         if(SigEmaPullback(ctx, PullbackParams(), plan))
         { m_sleeve = 2; plan.reason = "R11F-B-EXPANSION " + plan.reason; return CostOk(ctx, plan); }
      }

      //--- Sleeve C: Asian-session mean reversion (low beta, high hit-rate)
      if(TotalForSleeve(3) < InpMaxPerSleeve && ctx.clockMinutes < 7 * 60 &&
         (StringFind(ctx.symbol, "EURGBP") >= 0 || StringFind(ctx.symbol, "AUDNZD") >= 0))
      {
         SRangeFadeParams rf;
         rf.Reset();
         rf.bbPeriod = 20; rf.bbDeviation = 2.0;
         rf.rsiOversold = 5.0; rf.rsiOverbought = 95.0;
         rf.wickRatio = 0.50; rf.stopBufferAtr = 0.20;
         rf.targetR = 0.80; rf.requireRangeRegime = true; rf.maxAdx = 16.0;
         if(SigRangeFade(ctx, rf, plan))
         { m_sleeve = 3; plan.reason = "R11F-C-ASIANMR " + plan.reason; return CostOk(ctx, plan); }
      }
      return false;
   }

   int m_sleeve;

   SEmaPullbackParams PullbackParams()
   {
      SEmaPullbackParams ep;
      ep.Reset();
      ep.emaPeriod = 20; ep.maxDistanceAtr = 1.20;
      ep.requireTrend = true; ep.targetR = 2.0;
      return ep;
   }

   int TotalOpen()
   {
      return EA_CountPositions("", false);
   }

   //--- sleeve identity from the position comment prefix written at entry
   int TotalForSleeve(const int sleeve)
   {
      string tag = (sleeve == 1) ? "R11F-A" : (sleeve == 2) ? "R11F-B" : "R11F-C";
      int n = 0;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(StringFind(PositionGetString(POSITION_COMMENT), tag) >= 0) n++;
      }
      return n;
   }
   //--- doc: spread > 15% of the stop distance voids the entry
   bool CostOk(SEAContext &ctx, SSignalPlan &p)
   {
      if(p.riskDist <= 0.0) return false;
      bool ok = (ctx.spreadPoints * ctx.point <= InpMaxSpreadStopPct / 100.0 * p.riskDist);
      if(!ok)
         EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.1f pts > %.0f%% of the %.5f stop - entry void",
                ctx.symbol, ctx.spreadPoints, InpMaxSpreadStopPct, p.riskDist), true);
      return ok;
   }
};

CRound11F g_Round11F;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round11F);
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
