//+------------------------------------------------------------------+
//| EA_THE5ERS_STRATEGY_IMPROVEMENT_SUGGESTION_REVIEW.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Suggestion review - fail-closed release gates over canonical V2 Sleeve A
//| Source document : docs/prop_firm/THE5ERS-STRATEGY-IMPROVEMENT-SUGGESTION-REVIEW.md
//| Tracker entry   : #23  |  Magic: 3109
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CSuggestionReview class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Suggestion review - fail-closed release gates over canonical V2 Sleeve A"
#property description "Source: docs/prop_firm/THE5ERS-STRATEGY-IMPROVEMENT-SUGGESTION-REVIEW.md"

#include "..\..\Include\EACommon.mqh"

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
input ulong           InpMagicNumber      = 3109; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpPhaseInitialBalance = 2500.0; // Persisted phase initial balance (LOCKED sizing base)
input bool InpGateDataProvenanceOK   = false;  // Global gate: data acquired + versioned
input bool InpGateReplayExportOK     = false;  // Global gate: replay exporter produces the registry rows
input bool InpGateDeclaredGatesSigned = false; // Global gate: Section 13 gates declared
input bool InpGateEurusdLondon       = false;  // Per-combination gate: EURUSD London
input bool InpGateGbpsdLondon        = false;  // Per-combination gate: GBPUSD London
input bool InpGateUsdjpyNewYork      = false;  // Per-combination gate: USDJPY New York
input bool InpAcknowledgeNotApproved = false;  // Reviewer: README = not compile-verified/backtested/approved
input string InpNewsFile             = "the5ers_red_news.csv"; // Red-folder calendar (MQL5/Files)
input double InpQualifyingDayCash   = 12.50;  // 0.5% of $2,500: qualifying-day amount
input int    InpQualifyingDayCount  = 3;      // Qualifying days required per phase

//+------------------------------------------------------------------+
//| Strategy: Suggestion review - fail-closed release gates over canonical V2 Sleeve A
//+------------------------------------------------------------------+
class CSuggestionReview : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "SUGGESTION_REVIEW_GATES";
      cfg.sourceDoc             = "docs/prop_firm/THE5ERS-STRATEGY-IMPROVEMENT-SUGGESTION-REVIEW.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.maxCostR              = 0.10;                       // round-trip cost ceiling (section 13)
      cfg.maxRequestsPerDay     = 20;                         // excess-request safeguard
      cfg.newsFilter            = true;
      cfg.newsFile              = InpNewsFile;
      cfg.newsFailClosed        = true;                       // bad calendar = no new entries
      cfg.qualifyingDayAmount   = InpQualifyingDayCash;
      cfg.qualifyingDaysTarget  = InpQualifyingDayCount;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
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
      cfg.useLimitEntry         = true;                       // frozen V2 entry is a limit at the 50% retracement
      cfg.pendingExpiryMinutes  = 15;
      cfg.timeStopMinutes       = 45;
      cfg.breakEvenAtR          = 0.0;                     // frozen controls: no breakeven move
      cfg.partial1AtR           = 0.0;                     // V2 removed partial closing
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
      //--- fail-closed release gates: nothing trades until every gate is enabled
      if(!InpGateDataProvenanceOK || !InpGateReplayExportOK || !InpGateDeclaredGatesSigned) return false;
      bool comboEnabled = false;
      if(ctx.symbol == "EURUSD") comboEnabled = InpGateEurusdLondon;
      if(ctx.symbol == "GBPUSD") comboEnabled = InpGateGbpsdLondon;
      if(ctx.symbol == "USDJPY") comboEnabled = InpGateUsdjpyNewYork;
      if(!comboEnabled) return false;

      //--- canonical V2 Sleeve A (no H1 context, no partials, XAUUSD excluded)
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
      plan.reason = StringFormat("V2-CANONICAL %s %s", ctx.symbol, plan.reason);
      return true;
   }

   //--- the reviewer's checklist is printed once at init so the operator sees
   //--- exactly which release gate is still open
   void OnInitStrategy()
   {
      EA_Log(EA_LOG_EVENTS, "release gates (all must be true before trading):");
      EA_Log(EA_LOG_EVENTS, StringFormat("  data provenance........ %s", InpGateDataProvenanceOK ? "PASS" : "OPEN"));
      EA_Log(EA_LOG_EVENTS, StringFormat("  replay exporter........ %s", InpGateReplayExportOK ? "PASS" : "OPEN"));
      EA_Log(EA_LOG_EVENTS, StringFormat("  declared gates......... %s", InpGateDeclaredGatesSigned ? "PASS" : "OPEN"));
      EA_Log(EA_LOG_EVENTS, StringFormat("  EURUSD London.......... %s", InpGateEurusdLondon ? "PASS" : "OPEN"));
      EA_Log(EA_LOG_EVENTS, StringFormat("  GBPUSD London.......... %s", InpGateGbpsdLondon ? "PASS" : "OPEN"));
      EA_Log(EA_LOG_EVENTS, StringFormat("  USDJPY New York........ %s", InpGateUsdjpyNewYork ? "PASS" : "OPEN"));
      if(!InpAcknowledgeNotApproved)
         EA_Log(EA_LOG_EVENTS, "NOTE: this build is not approved for live trading until the gates above pass");
   }
};

CSuggestionReview g_SuggestionReview;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_SuggestionReview);
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
