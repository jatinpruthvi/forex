//+------------------------------------------------------------------+
//| EA_THE5ERS_CHALLENGE_V2_REVALIDATION.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| The5ers V2 revalidation - Sleeve A plus the compliance harness
//| Source document : docs/prop_firm/THE5ERS-CHALLENGE-V2-REVALIDATION.md
//| Tracker entry   : #19  |  Magic: 3105
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CChallengeV2Revalidation class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "The5ers V2 revalidation - Sleeve A plus the compliance harness"
#property description "Source: docs/prop_firm/THE5ERS-CHALLENGE-V2-REVALIDATION.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY";      // Comma separated universe
input double          InpRiskPct          = 0.4;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 3.0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 5.0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 10;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 10;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 2;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 3105; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpPhaseInitialBalance = 2500.0; // Persisted phase initial balance
input double InpQualifyingDayPct     = 0.005;  // 0.5% of phase initial balance = $12.50
input double InpDailyBoundaryPct     = 0.05;   // Firm boundary: max(balance,equity) x 0.95
input int    InpInactivityWarnDays   = 20;     // Warn at day 20 without a trade
input int    InpInactivityEscalateDays = 25;   // Escalate at day 25 (never fake a trade)
input double InpMaxCostR             = 0.10;   // Cost gate in R
input string InpNewsFile           = "the5ers_red_news.csv"; // Red-folder calendar (MQL5/Files)
input int    InpNewsBeforeMin      = 30;    // Mandatory 30-minute pre-event buffer
input int    InpNewsAfterMin       = 30;    // Mandatory 30-minute post-event buffer
input int    InpMaxRequestsPerDay  = 20;    // Non-emergency trade-request cap
input int    InpRetryCount         = 1;     // One revalidated retry after a transient reject
input double InpQualifyingDayCash   = 12.50;  // 0.5% of $2,500: qualifying-day amount
input int    InpQualifyingDayCount  = 3;      // Qualifying days required per phase
input double InpCommissionPerLotRT   = 7.00;   // Round-turn commission per lot
input double InpTargetR              = 1.50;   // Sleeve A target
input int    InpTimeStopMinutes      = 45;     // Sleeve A time stop

//+------------------------------------------------------------------+
//| Strategy: The5ers V2 revalidation - Sleeve A plus the compliance harness
//+------------------------------------------------------------------+
class CChallengeV2Revalidation : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "THE5ERS_V2_REVALIDATION";
      cfg.sourceDoc             = "docs/prop_firm/THE5ERS-CHALLENGE-V2-REVALIDATION.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;
      cfg.newsFilter            = true;
      cfg.maxRequestsPerDay     = InpMaxRequestsPerDay;
      cfg.newsFile              = InpNewsFile;
      cfg.newsBeforeMin         = InpNewsBeforeMin;
      cfg.newsAfterMin          = InpNewsAfterMin;
      cfg.newsFailClosed        = true;                     // calendar unavailable = no new entries
      cfg.qualifyingDayAmount   = InpQualifyingDayCash;
      cfg.qualifyingDaysTarget  = InpQualifyingDayCount;
      cfg.dailyLossPct          = InpDailyLossPct;         // firm boundary (fail closed)
      cfg.totalDdPct            = InpTotalDdPct;           // static floor from persisted base
      cfg.profitTargetPct       = InpProfitTargetPct;      // 10% Phase 1 / 5% Phase 2
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;                    // flat before rollover/weekend
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.pendingExpiryMinutes  = 15;
      cfg.timeStopMinutes       = InpTimeStopMinutes;
      cfg.breakEvenAtR          = 1.0;                     // BE after +1R...
      cfg.breakEvenOnBarClose   = true;                    // ...confirmed by a completed M5 close
      cfg.partial1AtR           = 0.0;                     // no partials in the frozen contract
      cfg.useHwmThrottle        = true;
      cfg.hwmTier1Dd            = 2.0;  cfg.hwmTier1Mult = 0.50;
      cfg.hwmTier2Dd            = 5.0;  cfg.hwmTier2Mult = 0.0;  cfg.hwmHaltDd = 5.0;
      //--- LOCKED: phase-initial balance is the sizing base; one working entry account-wide
      cfg.riskBaseInitialBalance = true;  cfg.riskInitialBalance = InpPhaseInitialBalance;
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
      p.targetR        = InpTargetR;

      if(ctx.symbol == "USDJPY")
      {
         p.rangeFromMin   = 7 * 60;
         p.rangeToMin     = 13 * 60;
         p.sessionFromMin = 13 * 60 + 30;
         p.sessionToMin   = 16 * 60;
      }
      if(ctx.clockMinutes < p.sessionFromMin || ctx.clockMinutes >= p.sessionToMin) return false;

      //--- revalidation gate: daily boundary max(balance,equity) x 0.95
      if(DailyBoundaryBreached(ctx)) return false;

      if(!SigSweepReclaim(ctx, p, plan)) return false;
      plan.reason = StringFormat("V2-REVALIDATED %s %s", ctx.symbol, plan.reason);
      return true;
   }

   //--- firm daily boundary: max(prior rollover balance, equity) x (1 - 5%)
   bool DailyBoundaryBreached(SEAContext &ctx)
   {
      double base = MathMax(ctx.dayStartEquity, AccountInfoDouble(ACCOUNT_BALANCE));
      if(base <= 0.0) return false;
      double floorLevel = base * (1.0 - InpDailyBoundaryPct);
      if(ctx.equity <= floorLevel)
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("daily boundary breached (equity %.2f <= %.2f)", ctx.equity, floorLevel), true);
         return true;
      }
      return false;
   }

   //--- qualifying-day + inactivity harness (evidence only, never fake a trade)
   void Manage(SEAContext &ctx)
   {
      static datetime lastDay = 0;
      MqlDateTime dt;
      TimeToStruct(ctx.nowClock, dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      datetime day = StructToTime(dt);
      if(lastDay != 0 && day != lastDay)
         EA_Log(EA_LOG_EVENTS, StringFormat("rollover: %d qualifying day(s) banked by the engine (no duplicate counter)",
                ctx.qualifyingDays));
      lastDay = day;

      //--- inactivity watchdog: warn day 20, escalate day 25
      string tkey = "EA_" + IntegerToString((long)InpMagicNumber) + "_LastTrade";
      if(!GlobalVariableCheck(tkey)) GlobalVariableSet(tkey, (double)ctx.nowServer);
      datetime lastTrade = (datetime)GlobalVariableGet(tkey);
      int idleDays = (int)((ctx.nowServer - lastTrade) / 86400);
      if(idleDays >= InpInactivityEscalateDays)
         EA_Log(EA_LOG_EVENTS, StringFormat("INACTIVITY ESCALATION: %d days without a trade - operator action required", idleDays), true);
      else if(idleDays >= InpInactivityWarnDays)
         EA_Log(EA_LOG_EVENTS, StringFormat("inactivity warning: %d days without a trade", idleDays), true);
   }
};

CChallengeV2Revalidation g_ChallengeV2Revalidation;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_ChallengeV2Revalidation);
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
