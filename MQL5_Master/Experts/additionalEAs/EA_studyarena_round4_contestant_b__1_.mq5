//+------------------------------------------------------------------+
//| EA_studyarena_round4_contestant_b__1_.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 4B(1) - imbalance engine with correlated heat, meta-labeling and recycling
//| Source document : docs_v1/docs/coreIdea/studyarena-round4-contestant-b (1).md
//| Tracker entry   : #41  |  Magic: 2010
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound4B2 class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 4B(1) - imbalance engine with correlated heat, meta-labeling and recycling"
#property description "Source: docs_v1/docs/coreIdea/studyarena-round4-contestant-b (1).md"

#include "..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY,XAUUSD,AUDNZD";      // Comma separated universe
input double          InpRiskPct          = 0.7;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 6.0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 0;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 20;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 4;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2010; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpCostR              = 0.08;  // Expected round-trip cost per trade (R)
input double InpMetaGateProb       = 0.55;  // Meta-label gate: only trade when P > 0.55
input double InpCorrelatedHeatPct  = 1.00;  // Correlated USD/JPY block heat cap
input int    InpRecycleMinutes     = 90;    // Trade recycling: flat after 90 min
input double InpRunnerReachR       = 4.20;  // Avg win of the sweep->CHoCH runner engine

//+------------------------------------------------------------------+
//| Strategy: Round 4B(1) - imbalance engine with correlated heat, meta-labeling and recycling
//+------------------------------------------------------------------+
class CRound4B2 : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R4B2_IMBALANCE_ENGINE";
      cfg.sourceDoc             = "docs_v1/docs/coreIdea/studyarena-round4-contestant-b (1).md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M15;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;      // cost engineering: raw-spread ECN only
      cfg.maxCostR              = InpCostR;                // reject trades whose cost eats the edge
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 2;
      cfg.minSecondsBetweenTrades = 600;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 20;  cfg.sessionEndMin   = 0;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.timeStopMinutes       = InpRecycleMinutes;       // Lever C: trade recycling / capacity
      cfg.partial1AtR           = 1.50;  cfg.partial1Pct = 35.0;
      cfg.breakEvenAtR          = 1.50;
      cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 1.00;
      cfg.useLimitEntry         = true;                    // never chase a missed OB
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- Engine 4/6: imbalance (FVG) re-engage - the best expectancy/trade (1.32R)
      SFvgParams f;
      f.Reset();
      f.impulseBody = 0.55; f.minGapAtr = 0.08; f.stopBufferAtr = 0.15;
      f.targetR = 3.80; f.maxRetrace = 0.80;
      if(SigFvgRetest(ctx, f, plan))
      {
         if(MetaLabelPass(ctx, plan)) { plan.reason = "R4B2-FVG " + plan.reason; return true; }
      }

      //--- Engine 1: SMC sweep -> CHoCH with runner potential (avg win 4.2R)
      SSweepParams p;
      p.Reset();
      p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
      p.sessionFromMin = 7 * 60; p.sessionToMin = 16 * 60;
      p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.50;
      p.reclaimWindowBars = 3; p.wickRatio = 0.60; p.bodyRatio = 0.60;
      p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
      p.entryRetrace = 0.50; p.targetR = InpRunnerReachR;
      if(!SigSweepReclaim(ctx, p, plan)) return false;
      if(!MetaLabelPass(ctx, plan)) return false;
      plan.reason = "R4B2-SWEEP-CHOCH " + plan.reason;
      return true;
   }

   //--- Lever E/B: cost gate + meta-label probability proxy
   bool MetaLabelPass(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- observed cost in R must stay below the engine's budget
      if(plan.riskDist <= 0.0) return false;
      double costR = (ctx.spreadPoints * ctx.point) / plan.riskDist;
      if(costR > InpCostR) return false;
      //--- meta-label features: HTF agreement, volatility percentile, clean regime
      double prob = 0.50;
      if(ctx.emaH1_50 > 0.0 && ((plan.dir > 0 && ctx.mid > ctx.emaH1_50) ||
                                (plan.dir < 0 && ctx.mid < ctx.emaH1_50))) prob += 0.06;
      if(ctx.emaD1_200 > 0.0 && ((plan.dir > 0 && ctx.mid > ctx.emaD1_200) ||
                                 (plan.dir < 0 && ctx.mid < ctx.emaD1_200))) prob += 0.05;
      if(ctx.atrD1 > 0.0 && ctx.atr < ctx.atrD1 * 0.6) prob += 0.03;   // ATR percentile gate
      if(ctx.adx14 >= 18.0 && ctx.adx14 <= 45.0) prob += 0.03;
      //--- size proportional to the probability edge (Lever B)
      m_metaScore = prob;
      plan.score  = prob * 100.0;
      return (prob > InpMetaGateProb);
   }

   double m_metaScore;

   //--- Lever B: size proportional to P when the model leans in
   double LotsMultiplier(SEAContext &ctx)
   {
      if(m_metaScore <= InpMetaGateProb) return 0.0;
      return MathMin(1.5, m_metaScore / InpMetaGateProb);   // 1.0x .. 1.5x, never martingale
   }
};

CRound4B2 g_Round4B2;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round4B2);
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
