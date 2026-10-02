//+------------------------------------------------------------------+
//| EA_studyarena_round7_contestant_b.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 7B - three sleeves, equity-curve throttle and a 2.5x-ATR runner trail
//| Source document : docs/research/study_arena/studyarena-round7-contestant-b.md
//| Tracker entry   : #56  |  Magic: 2023
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound7B class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 7B - three sleeves, equity-curve throttle and a 2.5x-ATR runner trail"
#property description "Source: docs/research/study_arena/studyarena-round7-contestant-b.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,XAUUSD,USDJPY,EURGBP,AUDNZD,GER40";      // Comma separated universe
input int             InpMaxTradesPerDay  = 6;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2023; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpSleeveARisk       = 1.50;  // A: London sweep + runner
input double InpSleeveBRisk       = 1.00;  // B: NY continuation
input double InpSleeveCRisk       = 0.50;  // C: gated Asian grid
input double InpMaxOpenHeatPct    = 2.50;  // Max open heat across sleeves
input double InpRunnerTrailAtr    = 2.50;  // Trail 25% by 2.5 x ATR
input int    InpRollingTrades     = 10;    // Equity-curve throttle window

//+------------------------------------------------------------------+
//| Strategy: Round 7B - three sleeves, equity-curve throttle and a 2.5x-ATR runner trail
//+------------------------------------------------------------------+
class CRound7B : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R7B_SLEEVES_THROTTLE";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round7-contestant-b.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpSleeveARisk;
      cfg.signalTimeframe       = PERIOD_M15;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 3;
      cfg.minSecondsBetweenTrades = 120;
      cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 22;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 75.0;   // 75% off at 1R
      cfg.breakEvenAtR          = 1.00;
      cfg.trailAtR              = 1.00;  cfg.trailDistanceR = InpRunnerTrailAtr;
      cfg.timeStopMinutes       = 0;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      if(OpenHeatExceeded(ctx)) return false;

      //--- Sleeve A: London sweep + runner
      if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 10 * 60 + 30 &&
         (StringFind(ctx.symbol, "EURUSD") >= 0 || StringFind(ctx.symbol, "GBPUSD") >= 0 ||
          StringFind(ctx.symbol, "XAU") >= 0))
      {
         SSweepParams p;
         p.Reset();
         p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
         p.sessionFromMin = 7 * 60; p.sessionToMin = 10 * 60 + 30;
         p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
         p.reclaimWindowBars = 3; p.wickRatio = 0.55; p.bodyRatio = 0.55;
         p.stopBufferAtr = 0.10; p.minStopAtr = 0.50; p.maxStopAtr = 1.50;
         p.entryRetrace = 0.50; p.targetR = 3.0;
         if(!SigSweepReclaim(ctx, p, plan)) return false;
         m_sleeve = 1;
         plan.reason = "R7B-LONDONRUNNER " + plan.reason;
         return true;
      }

      //--- Sleeve B: NY continuation (XAUUSD, USDJPY)
      if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 16 * 60 &&
         (StringFind(ctx.symbol, "XAU") >= 0 || StringFind(ctx.symbol, "USDJPY") >= 0))
      {
         if(!SigEmaPullback(ctx, NyParams(), plan)) return false;
         m_sleeve = 2;
         plan.reason = "R7B-NYCONT " + plan.reason;
         return true;
      }

      //--- Sleeve C: gated Asian grid
      if(ctx.clockMinutes < 7 * 60 &&
         (StringFind(ctx.symbol, "EURGBP") >= 0 || StringFind(ctx.symbol, "AUDNZD") >= 0))
      {
         if(ctx.adxH1 >= 16.0) return false;                     // doc: ADX(14) < 16 gate (E lineage: H1)
         SRangeFadeParams rf;
         rf.Reset();
         rf.bbPeriod = 20; rf.bbDeviation = 2.0;
         rf.rsiOversold = 5.0; rf.rsiOverbought = 95.0;
         rf.wickRatio = 0.50; rf.stopBufferAtr = 0.20;
         rf.targetR = 0.80; rf.requireRangeRegime = false;       // regime ADX is the H1 gate above
         if(!SigRangeFade(ctx, rf, plan)) return false;
         m_sleeve = 3;
         plan.reason = "R7B-ASIAGRID " + plan.reason;
         return true;
      }
      return false;
   }

   //--- doc sleeve C: flat by 07:00 UK - London volume destroys grids
   void Manage(SEAContext &ctx)
   {
      if(ctx.clockMinutes < 7 * 60) return;
      if(StringFind(ctx.symbol, "EURGBP") < 0 && StringFind(ctx.symbol, "AUDNZD") < 0) return;
      for(int t = g_eaTrackCount - 1; t >= 0; t--)
      {
         if(g_eaTrack[t].symbol != ctx.symbol) continue;
         if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;
         g_eaExec.Close(g_eaTrack[t].ticket, "grid flat 07:00");
      }
   }

   int m_sleeve;

   SEmaPullbackParams NyParams()
   {
      SEmaPullbackParams ep;
      ep.Reset();
      ep.emaPeriod = 20; ep.maxDistanceAtr = 1.20;
      ep.requireTrend = true; ep.targetR = 2.0;
      return ep;
   }

   double SleeveRisk()
   {
      if(m_sleeve == 1) return InpSleeveARisk;
      if(m_sleeve == 2) return InpSleeveBRisk;
      if(m_sleeve == 3) return InpSleeveCRisk;
      return 0.0;
   }

   //--- sleeve risk allocation, plus the equity-curve throttle (rolling 10 trades)
   double LotsMultiplier(SEAContext &ctx)
   {
      double risk = SleeveRisk();
      if(RollingPlNegative()) risk *= 0.50;              // throttle: halve all risk
      if(ctx.riskPct <= 0.0) return 0.0;
      return MathMax(0.0, risk / ctx.riskPct);
   }

   bool RollingPlNegative()
   {
      if(!HistorySelect(TimeCurrent() - 30 * 24 * 3600, TimeCurrent())) return false;
      double pl = 0.0;
      int n = 0;
      for(int i = HistoryDealsTotal() - 1; i >= 0 && n < InpRollingTrades; i--)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagicNumber) continue;
         if(HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
         pl += HistoryDealGetDouble(t, DEAL_PROFIT) +
               HistoryDealGetDouble(t, DEAL_SWAP) +
               HistoryDealGetDouble(t, DEAL_COMMISSION);
         n++;
      }
      return (n >= InpRollingTrades && pl < 0.0);
   }

   //--- max open heat across the sleeves (2.5% of equity)
   bool OpenHeatExceeded(SEAContext &ctx)
   {
      if(ctx.equity <= 0.0) return false;
      return (EA_OpenRiskPct() > InpMaxOpenHeatPct);
   }
};

CRound7B g_Round7B;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round7B);
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
