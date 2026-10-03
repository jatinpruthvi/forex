//+------------------------------------------------------------------+
//| EA_THE5ERS_HIGH_STAKES_RESEARCH.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| The5ers High Stakes research - internal limit ladder + news jurisdiction
//| Source document : docs/prop_firm/THE5ERS-HIGH-STAKES-RESEARCH.md
//| Tracker entry   : #21  |  Magic: 3107
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CHighStakesResearch class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "The5ers High Stakes research - internal limit ladder + news jurisdiction"
#property description "Source: docs/prop_firm/THE5ERS-HIGH-STAKES-RESEARCH.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY";      // Comma separated universe
input double          InpRiskPct          = 0.4;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 3.0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 1.0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 10;   // Permanent floor from start balance (0 = off)
input int             InpMaxTradesPerDay  = 2;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 3107; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
enum ENUM_HIGH_STAKES_VARIANT
{
   HS_NEW_10PCT     = 0,  // New High Stakes: 10% Phase 1
   HS_CLASSIC_8PCT  = 1   // Classic High Stakes: 8% Phase 1
};
input ENUM_HIGH_STAKES_VARIANT InpVariant = HS_NEW_10PCT; // Program variant
input double InpWeeklyStopPct     = 2.50;  // Internal weekly stop (2.0-2.5%)
input double InpShutdownPct       = 5.50;  // Strategy shutdown/review (5.5-6.0%)
input double InpMaxOpenRiskPct    = 0.72;  // Normal maximum open risk
input double InpAbsOpenRiskCapPct = 1.00;  // Absolute technical open-risk cap
input bool   InpNewsGate          = true;  // Red-folder news blackout
input int    InpNewsBeforeMin     = 30;    // Cancel/protect before the event
input int    InpNewsAfterMin      = 30;    // No retries after the event
input double InpAccountSize       = 2500.0; // Account size for the $150 payout gate
input double InpQualifyingDayCash   = 12.50;  // 0.5% of $2,500: qualifying-day amount
input int    InpQualifyingDayCount  = 3;      // Qualifying days required per phase

//+------------------------------------------------------------------+
//| Strategy: The5ers High Stakes research - internal limit ladder + news jurisdiction
//+------------------------------------------------------------------+
class CHighStakesResearch : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "HIGH_STAKES_RESEARCH";
      cfg.sourceDoc             = "docs/prop_firm/THE5ERS-HIGH-STAKES-RESEARCH.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = MathMin(InpRiskPct, InpMaxOpenRiskPct);   // 0.72% normal cap
      cfg.signalTimeframe       = PERIOD_M15;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.serverOffsetAuto      = true;                       // live offset, never hard-coded
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;            // internal 0.75-1.0%
      cfg.weeklyLossPct         = InpWeeklyStopPct;           // internal 2.0-2.5%
      cfg.totalDdPct            = InpTotalDdPct;              // 10% firm floor
      cfg.profitTargetPct       = (InpVariant == HS_CLASSIC_8PCT) ? 8.0 : 10.0;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;                          // bulk trading is prohibited
      cfg.minSecondsBetweenTrades = 300;                      // no tick-scalping profile
      cfg.useHwmThrottle        = true;
      cfg.hwmTier1Dd            = 2.0;  cfg.hwmTier1Mult = 0.50;
      cfg.hwmTier2Dd            = InpShutdownPct;  cfg.hwmTier2Mult = 0.0;
      cfg.hwmHaltDd             = InpShutdownPct;             // shutdown/review boundary
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 21;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.pendingExpiryMinutes  = 15;
      cfg.newsFilter            = InpNewsGate;                // fail closed when enabled
      cfg.newsFile              = "the5ers_red_news.csv";
      cfg.newsBeforeMin         = InpNewsBeforeMin;
      cfg.newsAfterMin          = InpNewsAfterMin;
      cfg.newsFailClosed        = true;                       // bad calendar = no new entries
      cfg.qualifyingDayAmount   = InpQualifyingDayCash;
      cfg.qualifyingDaysTarget  = InpQualifyingDayCount;
      cfg.timeStopMinutes       = 45;
      cfg.breakEvenAtR          = 1.0;
      cfg.breakEvenOnBarClose   = true;                    // only a completed bar confirms +1R
      //--- LOCKED: phase-initial balance is the sizing base; one working entry account-wide
      cfg.riskBaseInitialBalance = true;  cfg.riskInitialBalance = InpAccountSize;
      cfg.oneEntryAccountWide    = true;   // no second entry while one is working or open
      cfg.flattenOnHalt          = true;   // governor halt = cancel entries + close
      cfg.newsFlatBeforeMin      = 15.0;   // flat 15 min before a relevant red event

      cfg.dayAnchorServer        = true;   // firm rollover on the SERVER day, never the clock day
      cfg.dayLockFirstWin        = true;   // any first net-positive exit locks the day

      cfg.dayLockAfterTrades     = 2;      // two completed sequential trades end the day


      cfg.maxRetries           = 1;                        // one revalidated retry only
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- Sleeve A sweep/reclaim on M15 ATR geometry
      SSweepParams p;
      p.Reset();
      p.rangeFromMin   = 0;
      p.rangeToMin     = 7 * 60;
      p.sessionFromMin = 7 * 60;
      p.sessionToMin   = 16 * 60;
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
      plan.reason = StringFormat("HS-RESEARCH %s %s", ctx.symbol, plan.reason);
      return true;
   }

   //--- Section 4 (news): cancel unfilled entries before the blackout and
   //--- suppress retries inside it; Section 3: enforce the absolute open-risk cap.
   void Manage(SEAContext &ctx)
   {
      if(ctx.newsBlocked)
      {
         g_eaExec.CancelPending(ctx.symbol, "news blackout");
         return;
      }
      double openRisk = EA_OpenRiskPct();
      if(openRisk > InpAbsOpenRiskCapPct)
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("open risk %.2f%% above absolute cap %.2f%% - flattening",
                openRisk, InpAbsOpenRiskCapPct), true);
         EA_FlattenAll("absolute open-risk cap");
      }
   }
};

CHighStakesResearch g_HighStakesResearch;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_HighStakesResearch);
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
