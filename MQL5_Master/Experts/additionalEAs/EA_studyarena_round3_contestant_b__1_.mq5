//+------------------------------------------------------------------+
//| EA_studyarena_round3_contestant_b__1_.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 3B - 17 levers: imbalance entries, MTF stacking, graded ladder exits
//| Source document : docs_v1/docs/coreIdea/studyarena-round3-contestant-b (1).md
//| Tracker entry   : #38  |  Magic: 2007
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound3B class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 3B - 17 levers: imbalance entries, MTF stacking, graded ladder exits"
#property description "Source: docs_v1/docs/coreIdea/studyarena-round3-contestant-b (1).md"

#include "..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,XAUUSD";      // Comma separated universe
input double          InpRiskPct          = 1.0;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 0;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 20;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 5;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2007; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpStopFactor        = 0.70;  // Hard stop: 0.7R of the structural swing
input double InpTarget1R          = 1.20;  // Target 1: +1.2R (25%)
input double InpTarget2R          = 2.50;  // Target 2: +2.5R (25%)
input double InpRunnerTrailR      = 1.00;  // Runner trail in R behind the H4 swing
input double InpGradedMaxRiskPct  = 2.50;  // Score 10/10 -> 2.5% risk
input double InpGradedMinRiskPct  = 1.00;  // Score 6/10 -> 1.0% risk

//+------------------------------------------------------------------+
//| Strategy: Round 3B - 17 levers: imbalance entries, MTF stacking, graded ladder exits
//+------------------------------------------------------------------+
class CRound3B : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R3B_SEVENTEEN_LEVERS";
      cfg.sourceDoc             = "docs_v1/docs/coreIdea/studyarena-round3-contestant-b (1).md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpGradedMinRiskPct;
      cfg.signalTimeframe       = PERIOD_M15;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      //--- the document's exit ladder: 25% at 1.2R, 25% at 2.5R, runner trails the H4 swing
      cfg.partial1AtR           = InpTarget1R;  cfg.partial1Pct = 25.0;
      cfg.partial2AtR           = InpTarget2R;  cfg.partial2Pct = 25.0;
      cfg.breakEvenAtR          = 1.2;
      cfg.trailAtR              = 2.5;  cfg.trailDistanceR = InpRunnerTrailR;
      cfg.timeStopMinutes       = 0;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- Lever 2: multi-timeframe confirmation stacking (D1 direction, H4 momentum, M15 timing)
      int dirBias = 0;
      if(ctx.emaD1_200 > 0.0)
         dirBias = (ctx.mid > ctx.emaD1_200) ? +1 : -1;
      if(dirBias == 0) return false;
      //--- H4 momentum: ADX > 25 and ATR expanding
      if(ctx.adx14 < 25.0) return false;
      if(ctx.atrD1 <= 0.0 || ctx.atr <= 0.0) return false;

      //--- Lever 3: the imbalance (FVG) trade - SMC's highest-R edge
      SFvgParams f;
      f.Reset();
      f.impulseBody = 0.60; f.minGapAtr = 0.10;
      f.stopBufferAtr = 0.15; f.targetR = 6.0;      // runner targets 6-8R
      f.maxRetrace = 0.75;
      f.tradeBothWays = (dirBias > 0);
      if(!SigFvgRetest(ctx, f, plan)) return false;
      if(plan.dir != dirBias) return false;

      //--- Lever 1: the 0.7R hard stop (tighter than the structural swing)
      double structural = plan.riskDist;
      double stop = InpStopFactor * structural;
      if(stop <= 0.0) return false;
      plan.riskDist = stop;
      plan.stop     = (plan.dir > 0) ? plan.entry - stop : plan.entry + stop;
      plan.target   = (plan.dir > 0) ? plan.entry + InpTarget2R * stop
                                     : plan.entry - InpTarget2R * stop;

      //--- Lever 4: graded conviction sizing
      m_grade = Grade(ctx, plan.dir);
      plan.score = m_grade * 10.0;
      plan.reason = StringFormat("R3B-IMBALANCE(grade %.0f/10) %s", m_grade, plan.reason);
      return true;
   }

   double m_grade;

   double Grade(SEAContext &ctx, const int dir)
   {
      double grade = 5.0;
      if(ctx.emaD1_200 > 0.0 && ((dir > 0 && ctx.mid > ctx.emaD1_200) || (dir < 0 && ctx.mid < ctx.emaD1_200)))
         grade += 1.5;
      if(ctx.adx14 > 25.0) grade += 1.0;
      if(ctx.emaH1_50 > 0.0 && ((dir > 0 && ctx.mid > ctx.emaH1_50) || (dir < 0 && ctx.mid < ctx.emaH1_50)))
         grade += 1.0;
      if(ctx.atrD1 > 0.0 && ctx.atr > 0.3 * ctx.atrD1) grade += 0.75;
      if((dir > 0 && ctx.rsi14 > 45.0 && ctx.rsi14 < 75.0) ||
         (dir < 0 && ctx.rsi14 < 55.0 && ctx.rsi14 > 25.0)) grade += 0.75;
      return MathMin(grade, 10.0);
   }

   //--- graded conviction sizing: 10/10 -> 2.5%, 6/10 -> 1.0%, below -> no trade
   double LotsMultiplier(SEAContext &ctx)
   {
      if(m_grade < 6.0) return 0.0;
      double span = (InpGradedMaxRiskPct - InpGradedMinRiskPct) / 4.0;   // 6..10
      double target = InpGradedMinRiskPct + (m_grade - 6.0) * span;
      if(ctx.riskPct <= 0.0) return 0.0;
      return MathMax(0.0, MathMin(target / ctx.riskPct, InpGradedMaxRiskPct / MathMax(0.01, ctx.riskPct)));
   }
};

CRound3B g_Round3B;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round3B);
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
