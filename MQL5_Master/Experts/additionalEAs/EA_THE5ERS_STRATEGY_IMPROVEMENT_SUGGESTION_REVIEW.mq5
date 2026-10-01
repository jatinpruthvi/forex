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
input ulong           InpMagicNumber      = 3109; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input bool InpGateDataProvenanceOK   = false;  // Global gate: data acquired + versioned
input bool InpGateReplayExportOK     = false;  // Global gate: replay exporter produces the registry rows
input bool InpGateDeclaredGatesSigned = false; // Global gate: Section 13 gates declared
input bool InpGateEurusdLondon       = false;  // Per-combination gate: EURUSD London
input bool InpGateGbpsdLondon        = false;  // Per-combination gate: GBPUSD London
input bool InpGateUsdjpyNewYork      = false;  // Per-combination gate: USDJPY New York
input bool InpAcknowledgeNotApproved = false;  // Reviewer: README = not compile-verified/backtested/approved

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
      cfg.pendingExpiryMinutes  = 15;
      cfg.timeStopMinutes       = 45;
      cfg.breakEvenAtR          = 1.0;
      cfg.partial1AtR           = 0.0;                     // V2 removed partial closing
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
