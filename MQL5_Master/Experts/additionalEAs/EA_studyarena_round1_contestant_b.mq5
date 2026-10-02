//+------------------------------------------------------------------+
//| EA_studyarena_round1_contestant_b.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 1B - SMC order-block EA with break/retest confirmation
//| Source document : docs_v1/docs/coreIdea/studyarena-round1-contestant-b.md
//| Tracker entry   : #32  |  Magic: 2001
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound1B class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 1B - SMC order-block EA with break/retest confirmation"
#property description "Source: docs_v1/docs/coreIdea/studyarena-round1-contestant-b.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,XAUUSD";      // Comma separated universe
input double          InpProfitTargetPct  = 20;   // Stop opening at +x% (0 = off)
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2001; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpRiskPercentStart  = 1.00;  // RiskPercent (0.5-1.0% suggested)
input double InpAtrSlMultiplier   = 1.80;  // ATRMultiplier (1.5-2.0)
input double InpRrRatio           = 2.50;  // RR_Ratio (1:2 .. 1:3)
input int    InpMaxSpreadPips     = 30;    // Spread filter (pips)
input int    InpMaxTradesDay      = 4;     // MaxTradesPerDay (3-5)
input int    InpObLookbackBars    = 12;    // Order-block search window

//+------------------------------------------------------------------+
//| Strategy: Round 1B - SMC order-block EA with break/retest confirmation
//+------------------------------------------------------------------+
class CRound1B : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R1B_SMC_ORDER_BLOCK";
      cfg.sourceDoc             = "docs_v1/docs/coreIdea/studyarena-round1-contestant-b.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPercentStart;
      cfg.signalTimeframe       = PERIOD_M15;               // SMC works best M15-H1
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.profitTargetPct       = InpProfitTargetPct;       // auto-stop once +20% is reached
      cfg.maxTradesPerDay       = InpMaxTradesDay;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 900;                    // cooldown between SMC setups
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.timeStopMinutes       = 240;
      cfg.breakEvenAtR          = 1.0;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- spread filter: 30 pips in the document's terms
      double spreadPips = (ctx.pip > 0.0) ? ctx.spreadPoints * ctx.point / ctx.pip : 0.0;
      if(spreadPips > InpMaxSpreadPips) return false;

      //--- 1) order-block retest, 2) break/retest continuation
      SOrderBlockParams ob;
      ob.Reset();
      ob.lookbackBars     = InpObLookbackBars;
      ob.displacementBody = 0.55;
      ob.touchTolAtr      = 0.20;
      ob.stopBufferAtr    = 0.10;
      ob.targetR          = InpRrRatio;
      ob.requireHtfBias   = true;
      if(SigOrderBlockRetest(ctx, ob, plan))
      {
         //--- ATR stop override (document's ATRMultiplier)
         double stopDist = InpAtrSlMultiplier * ctx.atr;
         if(stopDist > 0.0 && MathAbs(plan.entry - plan.stop) < stopDist)
         {
            plan.stop = (plan.dir > 0) ? plan.entry - stopDist : plan.entry + stopDist;
            plan.riskDist = stopDist;
            plan.target = (plan.dir > 0) ? plan.entry + InpRrRatio * stopDist
                                         : plan.entry - InpRrRatio * stopDist;
         }
         plan.reason = "R1B-OB " + plan.reason;
         return true;
      }
      SBreakRetestParams br;
      br.Reset();
      br.rangeFromMin = 0; br.rangeToMin = 7 * 60;
      br.entryFromMin = 7 * 60; br.entryToMin = 16 * 60;
      br.minRangeAtr = 0.20; br.targetR = InpRrRatio;
      if(!SigBreakRetest(ctx, br, plan)) return false;
      plan.reason = "R1B-BREAKRETEST " + plan.reason;
      return true;
   }
};

CRound1B g_Round1B;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round1B);
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
