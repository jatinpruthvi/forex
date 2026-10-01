//+------------------------------------------------------------------+
//| EA_prop_fund_challenge_improvement_plan.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Prop-fund improvement plan - evidence gates before any live risk
//| Source document : docs/prop_firm/prop-fund-challenge-improvement-plan.md
//| Tracker entry   : #28  |  Magic: 3114
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CPropFundImprovementPlan class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Prop-fund improvement plan - evidence gates before any live risk"
#property description "Source: docs/prop_firm/prop-fund-challenge-improvement-plan.md"

#include "..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY";      // Comma separated universe
input double          InpRiskPct          = 0.4;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 3.0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 1.0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 10;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 10;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 2;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 3114; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input bool   InpCompilationGatePassed = false;  // Sub-task 1: MetaEditor 0-error evidence
input bool   InpTickDataGatePassed    = false;  // Sub-task 2: tick-quality replay data
input bool   InpForwardDemoGatePassed = false;  // Sub-task 3: forward-demo fill evidence
input bool   InpStatisticalGatePassed = false;  // Sub-task 4: statistical acceptance
input string InpEvidenceRecord        = "";     // Path/SHA record of the release evidence
input double InpCommissionPerLotRT    = 7.00;   // Cost model used by the pipeline

//+------------------------------------------------------------------+
//| Strategy: Prop-fund improvement plan - evidence gates before any live risk
//+------------------------------------------------------------------+
class CPropFundImprovementPlan : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "PROPFUND_IMPROVEMENT_PLAN";
      cfg.sourceDoc             = "docs/prop_firm/prop-fund-challenge-improvement-plan.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = 0.10;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = 2.0;
      cfg.totalDdPct            = InpTotalDdPct;
      cfg.profitTargetPct       = InpProfitTargetPct;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.pendingExpiryMinutes  = 15;
      cfg.timeStopMinutes       = 45;
      cfg.breakEvenAtR          = 1.0;
      cfg.partial1AtR           = 0.0;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- every release gate defaults to false: the EA is inert until the plan's
      //--- evidence exists (compilation, tick replay, forward demo, statistics)
      if(!InpCompilationGatePassed) return false;
      if(!InpTickDataGatePassed)    return false;
      if(!InpForwardDemoGatePassed) return false;
      if(!InpStatisticalGatePassed) return false;

      SSweepParams p;
      p.Reset();
      p.rangeFromMin   = 0;
      p.rangeToMin     = 7 * 60;
      p.sessionFromMin = 7 * 60;
      p.sessionToMin   = 11 * 60;
      p.sweepMinAtr    = 0.05;
      p.sweepMaxAtr    = 0.50;
      p.reclaimWindowBars = 3;
      p.wickRatio      = 0.60;
      p.bodyRatio      = 0.60;
      p.stopBufferAtr  = 0.10;
      p.minStopAtr     = 0.60;  p.maxStopAtr = 1.50;
      p.entryRetrace   = 0.50;
      p.targetR        = 1.50;
      if(ctx.symbol == "USDJPY")
      {
         p.rangeFromMin   = 7 * 60;
         p.rangeToMin     = 13 * 60;
         p.sessionFromMin = 13 * 60 + 30;
         p.sessionToMin   = 16 * 60;
      }
      if(ctx.clockMinutes < p.sessionFromMin || ctx.clockMinutes >= p.sessionToMin) return false;
      if(!SigSweepReclaim(ctx, p, plan)) return false;
      plan.reason = StringFormat("PLAN-GATED %s %s", ctx.symbol, plan.reason);
      return true;
   }

   void OnInitStrategy()
   {
      EA_Log(EA_LOG_EVENTS, "release evidence checklist:");
      EA_Log(EA_LOG_EVENTS, StringFormat("  compilation gate ....... %s", InpCompilationGatePassed ? "PASS" : "OPEN"));
      EA_Log(EA_LOG_EVENTS, StringFormat("  tick-data gate ......... %s", InpTickDataGatePassed ? "PASS" : "OPEN"));
      EA_Log(EA_LOG_EVENTS, StringFormat("  forward-demo gate ...... %s", InpForwardDemoGatePassed ? "PASS" : "OPEN"));
      EA_Log(EA_LOG_EVENTS, StringFormat("  statistical gate ....... %s", InpStatisticalGatePassed ? "PASS" : "OPEN"));
      if(StringLen(InpEvidenceRecord) > 0) EA_Log(EA_LOG_EVENTS, "evidence record: " + InpEvidenceRecord);
      else EA_Log(EA_LOG_EVENTS, "no evidence record attached - trading stays disabled");
   }
};

CPropFundImprovementPlan g_PropFundImprovementPlan;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_PropFundImprovementPlan);
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
