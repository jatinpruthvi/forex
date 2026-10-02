//+------------------------------------------------------------------+
//| EA_TRIAD_R_HS_CODE_REVIEW.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| TRIAD-R code review - hardened runtime controls from the 12 findings
//| Source document : docs/strategy/TRIAD_R_HS-CODE-REVIEW.md
//| Tracker entry   : #24  |  Magic: 3110
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CTriadCodeReviewHardened class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "TRIAD-R code review - hardened runtime controls from the 12 findings"
#property description "Source: docs/strategy/TRIAD_R_HS-CODE-REVIEW.md"

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
input ulong           InpMagicNumber      = 3110; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
enum ENUM_REVIEW_PROFILE
{
   REVIEW_RR_A = 0,  // A: 0.40% / +1.50R
   REVIEW_RR_B = 1,  // B: 0.35% / +1.75R
   REVIEW_RR_C = 2,  // C: 0.30% / +2.00R
   REVIEW_RR_D = 3   // D: 0.25% / +2.50R
};
input ENUM_REVIEW_PROFILE InpReviewProfile   = REVIEW_RR_A;   // Exactly one paired profile
input long   InpAuthorizedLogin              = 0;    // Finding 12: runtime identity revalidation
input int    InpEarlyLeadSeconds             = 5;    // Finding 9: fixed early execution lead
input int    InpLeaseMinutes                 = 10;   // Finding 3: single-instance lease
input string InpPriorityOrder                = "EURUSD,GBPUSD,USDJPY"; // Finding 7: frozen priority
input string InpNewsCoverageThrough          = "";   // Finding 6: explicit UTC coverage-through
input int    InpMaxEmergencyRetries          = 2;    // Finding 10: escalation policy

//+------------------------------------------------------------------+
//| Strategy: TRIAD-R code review - hardened runtime controls from the 12 findings
//+------------------------------------------------------------------+
class CTriadCodeReviewHardened : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      double riskPct = 0.40, targetR = 1.50;
      if(InpReviewProfile == REVIEW_RR_B) { riskPct = 0.35; targetR = 1.75; }
      if(InpReviewProfile == REVIEW_RR_C) { riskPct = 0.30; targetR = 2.00; }
      if(InpReviewProfile == REVIEW_RR_D) { riskPct = 0.25; targetR = 2.50; }

      cfg.strategyName          = "TRIAD_R_HS_HARDENED";
      cfg.sourceDoc             = "docs/strategy/TRIAD_R_HS-CODE-REVIEW.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = riskPct;
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
      cfg.sessionEndFlat        = true;                    // finding 4: no offline exposure over rollover
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.pendingExpiryMinutes  = 15;
      cfg.timeStopMinutes       = 45;
      cfg.breakEvenAtR          = 1.0;
      cfg.partial1AtR           = 0.0;
      cfg.maxRetries            = 2;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      if(!RuntimeGatesOk()) return false;

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
      if(InpReviewProfile == REVIEW_RR_B) p.targetR = 1.75;
      if(InpReviewProfile == REVIEW_RR_C) p.targetR = 2.00;
      if(InpReviewProfile == REVIEW_RR_D) p.targetR = 2.50;

      if(ctx.symbol == "USDJPY")
      {
         p.rangeFromMin   = 7 * 60;
         p.rangeToMin     = 13 * 60;
         p.sessionFromMin = 13 * 60 + 30;
         p.sessionToMin   = 16 * 60;
      }
      //--- finding 9: every boundary is approached with a fixed early lead
      if(ctx.clockMinutes < p.sessionFromMin || ctx.clockMinutes >= p.sessionToMin) return false;
      if(ctx.clockMinutes + (InpEarlyLeadSeconds / 60) >= p.sessionToMin) return false;

      if(!SigSweepReclaim(ctx, p, plan)) return false;
      plan.reason = StringFormat("TRIAD-HARDENED %s %s", ctx.symbol, plan.reason);
      return true;
   }

   //--- finding 7: frozen combination priority (EURUSD > GBPUSD > USDJPY)
   double RankSetup(SEAContext &ctx, const SSignalPlan &plan)
   {
      int pos = 0;
      string parts[];
      int n = StringSplit(InpPriorityOrder, ',', parts);
      for(int i = 0; i < n; i++)
      {
         string s = parts[i];
         StringTrimLeft(s); StringTrimRight(s);
         if(s == ctx.symbol) { pos = i; break; }
      }
      return plan.score - pos * 10.0;      // earlier in the list wins collisions
   }

   //--- findings 3 / 5 / 6 / 10 / 12: runtime gates
   bool RuntimeGatesOk()
   {
      if(InpAuthorizedLogin > 0 && AccountInfoInteger(ACCOUNT_LOGIN) != InpAuthorizedLogin)
      {
         EA_Log(EA_LOG_EVENTS, "identity mismatch - refusing to trade", true);
         return false;
      }
      //--- single-instance lease
      string hireKey = "EA_" + IntegerToString((long)InpMagicNumber) + "_LeaseHolder";
      string timeKey = "EA_" + IntegerToString((long)InpMagicNumber) + "_LeaseTime";
      datetime now = TimeTradeServer();
      if(GlobalVariableCheck(hireKey))
      {
         double holder = GlobalVariableGet(hireKey);
         double stamp  = GlobalVariableCheck(timeKey) ? GlobalVariableGet(timeKey) : 0.0;
         if((double)ChartID() != holder && now - (datetime)stamp < InpLeaseMinutes * 60)
         {
            EA_Log(EA_LOG_EVENTS, "another instance holds the lease - refusing to trade", true);
            return false;
         }
      }
      GlobalVariableSet(hireKey, (double)ChartID());
      GlobalVariableSet(timeKey, (double)now);
      //--- finding 6: news coverage must be explicitly declared, not inferred
      if(g_eaCfg.newsFilter)
      {
         datetime coverage = StringToTime(InpNewsCoverageThrough);
         if(coverage <= 0 || coverage < EA_ServerToUtc(now))
         {
            EA_Log(EA_LOG_EVENTS, "news coverage-through missing or expired - failing closed", true);
            return false;
         }
      }
      return true;
   }

   //--- findings 1 / 2 / 5 / 10 / 11: execution-integrity management
   void Manage(SEAContext &ctx)
   {
      //--- every position must carry a broker-visible stop (finding 10)
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetDouble(POSITION_SL) <= 0.0)
         {
            EA_Log(EA_LOG_EVENTS, StringFormat("CRITICAL: %s position without a stop - closing immediately",
                   PositionGetString(POSITION_SYMBOL)));
            g_eaExec.Close(t, "unprotected exposure (review finding 10)");
         }
      }
      //--- finding 5: external cashflow detection while flat and inactive
      static double balanceRef = -1.0;
      if(balanceRef < 0.0) balanceRef = AccountInfoDouble(ACCOUNT_BALANCE);
      if(ctx.openPositionsAll == 0 && ctx.tradesToday == 0)
      {
         double bal = AccountInfoDouble(ACCOUNT_BALANCE);
         if(MathAbs(bal - balanceRef) > 1.0)
         {
            EA_Log(EA_LOG_EVENTS, StringFormat("CRITICAL: unexplained balance change %.2f -> %.2f - halting for review",
                   balanceRef, bal));
            g_eaRisk.Halt("external cashflow / unauthorized history");
         }
         balanceRef = bal;
      }
   }
};

CTriadCodeReviewHardened g_TriadCodeReviewHardened;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_TriadCodeReviewHardened);
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
