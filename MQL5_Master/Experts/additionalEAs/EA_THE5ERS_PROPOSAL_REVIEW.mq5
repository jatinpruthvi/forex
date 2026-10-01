//+------------------------------------------------------------------+
//| EA_THE5ERS_PROPOSAL_REVIEW.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| The5ers proposal review - corrected profitable-day and cash-risk rules
//| Source document : docs/prop_firm/THE5ERS-PROPOSAL-REVIEW.md
//| Tracker entry   : #22  |  Magic: 3108
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CProposalReview class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "The5ers proposal review - corrected profitable-day and cash-risk rules"
#property description "Source: docs/prop_firm/THE5ERS-PROPOSAL-REVIEW.md"

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
input ulong           InpMagicNumber      = 3108; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
enum ENUM_REVIEW_PHASE
{
   REVIEW_PHASE_1 = 0,  // Phase 1 (10% / $250)
   REVIEW_PHASE_2 = 1,  // Phase 2 (5% / $125, fresh counter)
   REVIEW_FUNDED  = 2   // Funded (same process, capital preservation)
};
input ENUM_REVIEW_PHASE InpReviewPhase      = REVIEW_PHASE_1;  // Current phase
input double InpPhaseInitialBalance         = 2500.0;  // Phase initial balance
input double InpPlannedRiskCash             = 10.00;   // Planned $ risk per trade (review #8)
input double InpQualifyingDayCash           = 12.50;   // 0.5% qualifying-day amount
input bool   InpVerifyProductName           = false;   // VERIFY item: confirm at checkout
input int    InpRolloverHourServer          = 0;       // Server rollover hour
input int    InpFlatBeforeRolloverMin       = 15;      // Stay flat into rollover

//+------------------------------------------------------------------+
//| Strategy: The5ers proposal review - corrected profitable-day and cash-risk rules
//+------------------------------------------------------------------+
class CProposalReview : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "PROPOSAL_REVIEW";
      cfg.sourceDoc             = "docs/prop_firm/THE5ERS-PROPOSAL-REVIEW.md";
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
      cfg.profitTargetPct       = (InpReviewPhase == REVIEW_PHASE_2) ? 5.0 : InpProfitTargetPct;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;                       // single position account-wide
      cfg.minSecondsBetweenTrades = 60;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.pendingExpiryMinutes  = 15;
      cfg.timeStopMinutes       = 45;
      cfg.breakEvenAtR          = 1.0;
      cfg.partial1AtR           = 0.0;                     // no partial closes
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      if(InpVerifyProductName) return false;    // VERIFY item stays fail-closed until confirmed

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
      plan.reason = StringFormat("REVIEW-SLEEVE-A %s %s", ctx.symbol, plan.reason);
      return true;
   }

   //--- MODIFY #8: $10 planned cash risk per challenge trade
   double LotsMultiplier(SEAContext &ctx)
   {
      double planned = ctx.equity * (ctx.riskPct / 100.0);
      if(InpPlannedRiskCash > 0.0 && planned > InpPlannedRiskCash)
         return InpPlannedRiskCash / planned;
      return 1.0;
   }

   //--- corrected profitable-day rules: non-qualifying days never reset the count,
   //--- Phase 2 starts a fresh counter, and the EA stays flat into rollover.
   void Manage(SEAContext &ctx)
   {
      //--- flat X minutes before the server rollover
      MqlDateTime sdt;
      TimeToStruct(TimeTradeServer(), sdt);
      int secsToRollover = 86400 - (sdt.hour * 3600 + sdt.min * 60 + sdt.sec);
      if(secsToRollover <= InpFlatBeforeRolloverMin * 60)
      {
         if(ctx.openPositions > 0 || EA_CountPendings("") > 0)
            EA_FlattenAll("flat into rollover");
      }

      //--- qualifying-day accounting (any three days per phase, never reset downward)
      static datetime lastDay = 0;
      MqlDateTime dt;
      TimeToStruct(ctx.nowClock, dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      datetime day = StructToTime(dt);
      if(lastDay != 0 && day != lastDay)
      {
         double dayPl = ctx.dayRealizedPl;
         if(dayPl >= InpQualifyingDayCash)
         {
            string key = "EA_" + IntegerToString((long)InpMagicNumber) + "_QualDays_P" +
                         IntegerToString((int)InpReviewPhase);
            int n = GlobalVariableCheck(key) ? (int)GlobalVariableGet(key) : 0;
            GlobalVariableSet(key, (double)(n + 1));
            EA_Log(EA_LOG_EVENTS, StringFormat("qualifying day %d/3 banked (P/L %.2f, phase %s)",
                   n + 1, dayPl, EnumToString(InpReviewPhase)));
         }
         else
         {
            EA_Log(EA_LOG_EVENTS, StringFormat("day did not qualify (%.2f < %.2f) - counter unchanged",
                   dayPl, InpQualifyingDayCash));
         }
      }
      lastDay = day;
   }
};

CProposalReview g_ProposalReview;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_ProposalReview);
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
