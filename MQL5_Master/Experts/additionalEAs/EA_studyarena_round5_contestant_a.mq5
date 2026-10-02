//+------------------------------------------------------------------+
//| EA_studyarena_round5_contestant_a.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 5A - 60/25/15 portfolio: London sweep, NY continuation, capped reversion basket
//| Source document : docs/research/study_arena/studyarena-round5-contestant-a.md
//| Tracker entry   : #47  |  Magic: 2016
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound5A class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 5A - 60/25/15 portfolio: London sweep, NY continuation, capped reversion basket"
#property description "Source: docs/research/study_arena/studyarena-round5-contestant-a.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY,USDCAD,XAUUSD,EURGBP,AUDNZD";      // Comma separated universe
input int             InpMaxTradesPerDay  = 6;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2016; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpSweepRiskBudget    = 60.0;  // Risk budget allocation to London sweep (%)
input double InpNyRiskBudget       = 25.0;  // Risk budget allocation to NY continuation
input double InpBasketRiskBudget   = 15.0;  // Risk budget allocation to capped reversion
input double InpBaseRiskPct        = 1.00;  // Base risk unit before the allocation split

//+------------------------------------------------------------------+
//| Strategy: Round 5A - 60/25/15 portfolio: London sweep, NY continuation, capped reversion basket
//+------------------------------------------------------------------+
class CRound5A : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R5A_PORTFOLIO_60_25_15";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round5-contestant-a.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpBaseRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 2;
      cfg.minSecondsBetweenTrades = 600;
      cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 22;  cfg.sessionEndMin   = 0;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;
      cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 40.0;
      cfg.breakEvenAtR          = 1.00;
      cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 0.75;
      cfg.timeStopMinutes       = 300;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      m_sleeve = 0;
      if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 10 * 60 + 30 &&
         (StringFind(ctx.symbol, "EURUSD") >= 0 || StringFind(ctx.symbol, "GBPUSD") >= 0))
      {
         if(!SweepGatesPass(ctx)) return false;
         SSweepParams p;
         p.Reset();
         p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
         p.sessionFromMin = 7 * 60; p.sessionToMin = 10 * 60 + 30;
         p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
         p.reclaimWindowBars = 3; p.wickRatio = 0.55; p.bodyRatio = 0.55;
         p.stopBufferAtr = 0.10; p.minStopAtr = 0.50; p.maxStopAtr = 1.50;
         p.entryRetrace = 0.50; p.targetR = 2.0;
         if(!SigSweepReclaim(ctx, p, plan)) return false;
         m_sleeve = 1;
         plan.reason = "R5A-SWEEP " + plan.reason;
         return true;
      }

      if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 16 * 60)
      {
         if(!SigEmaPullback(ctx, PullbackParams(), plan)) return false;
         m_sleeve = 2;
         plan.reason = "R5A-NYCONT " + plan.reason;
         return true;
      }

      if(ctx.clockMinutes < 7 * 60 && (StringFind(ctx.symbol, "EURGBP") >= 0 ||
                                       StringFind(ctx.symbol, "AUDNZD") >= 0))
      {
         if(ctx.adx14 >= 16.0) return false;
         SRangeFadeParams rf;
         rf.Reset();
         rf.bbPeriod = 20; rf.bbDeviation = 2.0;
         rf.rsiOversold = 5.0; rf.rsiOverbought = 95.0;
         rf.wickRatio = 0.50; rf.stopBufferAtr = 0.20;
         rf.targetR = 0.80; rf.requireRangeRegime = true; rf.maxAdx = 16.0;
         if(!SigRangeFade(ctx, rf, plan)) return false;
         m_sleeve = 3;
         plan.reason = "R5A-BASKET " + plan.reason;
         return true;
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

   //--- regime gate checklist: percentile band, H1 trend, ADR cap, spread normalization
   bool SweepGatesPass(SEAContext &ctx)
   {
      double hi = 0.0, lo = 0.0;
      if(!SigAsianRange(ctx.symbol, hi, lo)) return false;
      double pct = AsiaRangePercentile(ctx.symbol, hi - lo);
      if(pct < 20.0 || pct > 65.0) return false;
      if(ctx.emaH1_50 <= 0.0) return false;
      bool up = (ctx.mid > ctx.emaH1_50 && ctx.ema50 > ctx.emaH1_50);
      bool dn = (ctx.mid < ctx.emaH1_50 && ctx.ema50 < ctx.emaH1_50);
      if(!up && !dn) return false;
      //--- travelled more than 70% of the 20-day ADR today?
      double adr = ctx.atrD1 * 4.0;
      if(adr > 0.0)
      {
         double dayRange = DayRange(ctx.symbol);
         if(dayRange > 0.70 * adr) return false;
      }
      return true;
   }

   double DayRange(const string sym)
   {
      MqlRates d[];
      if(EA_Rates(sym, PERIOD_D1, 0, 1, d) < 1) return 0.0;
      return d[0].high - d[0].low;
   }

   //--- percentile of today's Asian range among the last 60 sessions
   double AsiaRangePercentile(const string sym, const double todayRange)
   {
      MqlRates d[];
      if(EA_Rates(sym, PERIOD_D1, 1, 60, d) < 30) return 50.0;
      int below = 0, n = 0;
      for(int i = 0; i < 60; i++)
      {
         double r = d[i].high - d[i].low;
         if(r <= 0.0) continue;
         n++;
         if (todayRange >= r) below++;
      }
      return (n > 0) ? 100.0 * below / (double)n : 50.0;
   }

   //--- scale risk by the sleeve's budget allocation
   double LotsMultiplier(SEAContext &ctx)
   {
      double budget = (m_sleeve == 1) ? InpSweepRiskBudget
                    : (m_sleeve == 2) ? InpNyRiskBudget
                    : (m_sleeve == 3) ? InpBasketRiskBudget : 0.0;
      if(budget <= 0.0 || ctx.riskPct <= 0.0) return 0.0;
      return MathMax(0.0, (InpBaseRiskPct * budget / 100.0) / ctx.riskPct);
   }
};

CRound5A g_Round5A;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round5A);
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
