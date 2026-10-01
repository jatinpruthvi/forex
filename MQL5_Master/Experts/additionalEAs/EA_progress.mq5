//+------------------------------------------------------------------+
//| EA_progress.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| progress.md - the frozen TRIAD-R Sleeve A contract
//| Source document : docs/strategy/progress.md
//| Tracker entry   : #27  |  Magic: 3113
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CProgressFrozenContract class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "progress.md - the frozen TRIAD-R Sleeve A contract"
#property description "Source: docs/strategy/progress.md"

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
input ulong           InpMagicNumber      = 3113; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpSweepAtrMin         = 0.05;  // Frozen: minimum sweep depth (ATR)
input double InpSweepAtrMax         = 0.50;  // Frozen: maximum sweep depth (ATR)
input int    InpReclaimBars         = 3;     // Frozen: reclaim window (M5 bars)
input double InpReclaimWickMin      = 0.60;  // Frozen: reclaim wick ratio
input double InpDisplacementBodyMin = 0.60;  // Frozen: displacement body ratio
input double InpStopBufferAtr       = 0.10;  // Frozen: stop buffer beyond the sweep
input double InpStopAtrMin          = 0.60;  // Frozen: minimum stop distance
input double InpStopAtrMax          = 1.50;  // Frozen: maximum stop distance
input double InpMaxCostToR          = 0.10;  // Frozen: all-in cost ceiling in R
input double InpProfileRiskPct      = 0.40;  // Profile A: 0.40% / +1.50R
input double InpProfileTargetR      = 1.50;  // Profile A target
input int    InpTimeStopMinutes     = 45;    // Frozen: time stop
input string InpBuildId             = "TRIAD_R_HS_2.1.6_20260905"; // Frozen build record

//+------------------------------------------------------------------+
//| Strategy: progress.md - the frozen TRIAD-R Sleeve A contract
//+------------------------------------------------------------------+
class CProgressFrozenContract : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "TRIAD_R_FROZEN";
      cfg.sourceDoc             = "docs/strategy/progress.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpProfileRiskPct;         // profile A
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.maxCostR              = InpMaxCostToR;             // frozen cost gate
      cfg.commissionPerLotRT    = 7.00;
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
      cfg.timeStopMinutes       = InpTimeStopMinutes;        // frozen 45 minutes
      cfg.breakEvenAtR          = 1.0;
      cfg.partial1AtR           = 0.0;                       // V2 removed partial closing
      cfg.useHwmThrottle        = true;
      cfg.hwmTier1Dd            = 2.0;  cfg.hwmTier1Mult = 0.50;
      cfg.hwmTier2Dd            = 5.0;  cfg.hwmTier2Mult = 0.0;  cfg.hwmHaltDd = 5.0;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- the frozen contract runs Sleeve A on EURUSD London (active),
      //--- with GBPUSD London and USDJPY New York kept as validated candidates.
      SSweepParams p;
      p.Reset();
      p.rangeFromMin   = 0;
      p.rangeToMin     = 7 * 60;
      p.sessionFromMin = 7 * 60;
      p.sessionToMin   = 11 * 60;
      p.sweepMinAtr    = InpSweepAtrMin;
      p.sweepMaxAtr    = InpSweepAtrMax;
      p.reclaimWindowBars = InpReclaimBars;
      p.wickRatio      = InpReclaimWickMin;
      p.bodyRatio      = InpDisplacementBodyMin;
      p.stopBufferAtr  = InpStopBufferAtr;
      p.minStopAtr     = InpStopAtrMin;
      p.maxStopAtr     = InpStopAtrMax;
      p.entryRetrace   = 0.50;
      p.targetR        = InpProfileTargetR;

      if(ctx.symbol == "USDJPY")
      {
         p.rangeFromMin   = 7 * 60;
         p.rangeToMin     = 13 * 60;
         p.sessionFromMin = 13 * 60 + 30;
         p.sessionToMin   = 16 * 60;
      }
      if(ctx.clockMinutes < p.sessionFromMin || ctx.clockMinutes >= p.sessionToMin) return false;

      if(!SigSweepReclaim(ctx, p, plan)) return false;
      plan.reason = StringFormat("%s %s", InpBuildId, plan.reason);
      return true;
   }

   void OnInitStrategy()
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("frozen contract build %s - do not change constants without a full revalidation", InpBuildId));
      EA_Log(EA_LOG_EVENTS, "gold, indices, continuation and Asian fade stay disabled in this contract");
   }
};

CProgressFrozenContract g_ProgressFrozenContract;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_ProgressFrozenContract);
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
