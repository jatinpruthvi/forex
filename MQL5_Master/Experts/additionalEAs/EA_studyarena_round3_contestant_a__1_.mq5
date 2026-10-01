//+------------------------------------------------------------------+
//| EA_studyarena_round3_contestant_a__1_.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 3A - three-timeframe cascade with pyramided units and Kelly sizing
//| Source document : docs_v1/docs/coreIdea/studyarena-round3-contestant-a (1).md
//| Tracker entry   : #37  |  Magic: 2006
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound3A class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 3A - three-timeframe cascade with pyramided units and Kelly sizing"
#property description "Source: docs_v1/docs/coreIdea/studyarena-round3-contestant-a (1).md"

#include "..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY,GBPJPY";      // Comma separated universe
input double          InpRiskPct          = 1.0;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 0;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 20;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 6;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2006; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input int    InpPyramidUnits       = 3;     // Unit 1 entry + up to 2 refinements
input double InpPyramidStepR       = 1.00;  // Add when price advances xR beyond the last entry
input double InpKellyWinRate       = 0.45;  // Trailing win rate for fractional Kelly
input double InpKellyPayoffR       = 3.00;  // Trailing average win in R
input double InpKellyFraction      = 0.125; // 1/k fraction (k=8)
input double InpKellyCapPct        = 2.00;  // Hard per-trade cap

//+------------------------------------------------------------------+
//| Strategy: Round 3A - three-timeframe cascade with pyramided units and Kelly sizing
//+------------------------------------------------------------------+
class CRound3A : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R3A_TF_CASCADE";
      cfg.sourceDoc             = "docs_v1/docs/coreIdea/studyarena-round3-contestant-a (1).md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;             // scaled by the Kelly multiplier
      cfg.signalTimeframe       = PERIOD_M5;              // M5 precision entries
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = InpPyramidUnits;        // unit stacking is deliberate here
      cfg.minSecondsBetweenTrades = 120;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 20;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.pendingExpiryMinutes  = 15;
      cfg.timeStopMinutes       = 90;
      cfg.breakEvenAtR          = 1.0;
      cfg.trailAtR              = 1.5;  cfg.trailDistanceR = 0.5;
      cfg.useLimitEntry         = true;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      if(!PyramidStepSatisfied(ctx)) return false;

      //--- Engine A/B direction: H4-equivalent H1 bias, then M5 precision entry
      if(ctx.emaH1_200 <= 0.0 || ctx.ema50 <= 0.0) return false;
      int bias = (ctx.mid > ctx.emaH1_200) ? +1 : -1;
      if(bias > 0 && ctx.ema50 < ctx.emaH1_200) return false;
      if(bias < 0 && ctx.ema50 > ctx.emaH1_200) return false;

      //--- Engine C: M5 order-block precision entry, limit-only (cost per section 2)
      SOrderBlockParams ob;
      ob.Reset();
      ob.lookbackBars = 10; ob.displacementBody = 0.50;
      ob.touchTolAtr = 0.20; ob.stopBufferAtr = 0.10;
      ob.targetR = 1.50;                 // M5 engine target
      ob.requireHtfBias = true;
      ob.tradeBothWays = (bias > 0);
      if(!SigOrderBlockRetest(ctx, ob, plan)) return false;
      if(plan.dir != bias) return false;

      //--- limit-only resting entry at the block edge
      plan.entry   = (plan.dir > 0) ? MathMin(plan.entry, ctx.ask) : MathMax(plan.entry, ctx.bid);
      plan.isLimit = true;
      plan.expiry  = TimeTradeServer() + (datetime)(g_eaCfg.pendingExpiryMinutes * 60);
      plan.reason  = StringFormat("R3A-CASCADE(unit %d) %s", EA_CountPositions(ctx.symbol, true) + 1, plan.reason);
      return true;
   }

   bool AllowMultipleOnSymbol() { return true; }

   //--- each additional unit needs price to have advanced 1R past the last entry
   bool PyramidStepSatisfied(SEAContext &ctx)
   {
      int open = EA_CountPositions(ctx.symbol, true);
      if(open == 0) return true;
      if(open >= InpPyramidUnits) return false;
      //--- find the best (most advanced) entry on this symbol
      double bestEntry = 0.0;
      int    dir       = 0;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;
         bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         dir = isBuy ? +1 : -1;
         double e = PositionGetDouble(POSITION_PRICE_OPEN);
         if(bestEntry == 0.0 || (dir > 0 && e > bestEntry) || (dir < 0 && e < bestEntry)) bestEntry = e;
      }
      int ti = -1;
      for(int i = 0; i < g_eaTrackCount; i++) if(g_eaTrack[i].symbol == ctx.symbol) ti = i;
      double risk = (ti >= 0) ? g_eaTrack[ti].riskDist : 1.5 * ctx.atr;
      if(risk <= 0.0) return false;
      double px = ctx.mid;
      double advance = (dir > 0) ? (px - bestEntry) : (bestEntry - px);
      return (advance >= InpPyramidStepR * risk);
   }

   //--- fractional Kelly sizing on trailing statistics, hard-capped
   double LotsMultiplier(SEAContext &ctx)
   {
      double kelly = (InpKellyWinRate - (1.0 - InpKellyWinRate) / MathMax(0.1, InpKellyPayoffR)) * InpKellyFraction;
      if(kelly <= 0.0) return 0.0;
      double riskPct = MathMin(ctx.riskPct * (kelly / MathMax(0.0001, InpRiskPct)), InpKellyCapPct);
      return (ctx.riskPct > 0.0) ? MathMax(0.0, riskPct / ctx.riskPct) : 0.0;
   }
};

CRound3A g_Round3A;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round3A);
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
