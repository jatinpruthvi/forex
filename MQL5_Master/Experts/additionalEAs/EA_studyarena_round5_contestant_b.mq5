//+------------------------------------------------------------------+
//| EA_studyarena_round5_contestant_b.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 5B - asymmetric runner: 25% at 1.2R, break-even +0.3R, trail the 8R tail
//| Source document : docs/research/study_arena/studyarena-round5-contestant-b.md
//| Tracker entry   : #49  |  Magic: 2017
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound5B class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 5B - asymmetric runner: 25% at 1.2R, break-even +0.3R, trail the 8R tail"
#property description "Source: docs/research/study_arena/studyarena-round5-contestant-b.md"

#include "..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY,XAUUSD";      // Comma separated universe
input double          InpRiskPct          = 1.5;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 0;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 20;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 4;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2017; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpStopFactor        = 0.70;  // 0.7R hard stop on the structural swing
input double InpT1R               = 1.20;  // T1: close 25% at 1.2R
input double InpT2R               = 2.50;  // T2: close 25% at 2.5R
input double InpRunnerTargetR     = 8.00;  // Runner: liquidity pool target (up to 8R)
input double InpLiquidityLookback = 60;    // Bars scanned for the liquidity pool
input double InpMtfLayerR         = 0.15;  // MTF conviction layer add-on

//+------------------------------------------------------------------+
//| Strategy: Round 5B - asymmetric runner: 25% at 1.2R, break-even +0.3R, trail the 8R tail
//+------------------------------------------------------------------+
class CRound5B : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R5B_ASYMMETRIC_RUNNER";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round5-contestant-b.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M15;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 900;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.partial1AtR           = InpT1R;  cfg.partial1Pct = 25.0;
      cfg.partial2AtR           = InpT2R;  cfg.partial2Pct = 25.0;
      cfg.breakEvenAtR          = 1.20;    // then BE + 0.3R
      cfg.beOffsetR             = 0.30;
      cfg.trailAtR              = 1.20;  cfg.trailDistanceR = 1.00;
      cfg.timeStopMinutes       = 0;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- entry engine: fractal sweep + CHoCH, the only idea all three contestants ranked
      double highs[], lows[];
      int    hiIdx[], loIdx[];
      if(SigFractals(ctx.symbol, 6, highs, lows, hiIdx, loIdx) < 2) return false;
      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 6, r) < 5) return false;
      if(ctx.emaH1_50 <= 0.0) return false;
      bool biasUp = (ctx.mid > ctx.emaH1_50);

      bool long  = biasUp  && ArraySize(lows)  >= 2 && lows[0] < lows[1] && r[0].close > lows[0];
      bool short = !biasUp && ArraySize(highs) >= 2 && highs[0] > highs[1] && r[0].close < highs[0];
      if(!long && !short) return false;

      int dir = long ? +1 : -1;
      double structural = long ? (lows[0] - 0.10 * ctx.atr) : (highs[0] + 0.10 * ctx.atr);
      double stopDist = MathAbs(ctx.mid - structural);
      if(stopDist <= 0.0) return false;
      double tight = InpStopFactor * stopDist;

      plan.Reset();
      plan.dir      = dir;
      plan.entry    = (dir > 0) ? ctx.ask : ctx.bid;
      plan.riskDist = tight;
      plan.stop     = (dir > 0) ? plan.entry - tight : plan.entry + tight;
      plan.target   = LiquidityTarget(ctx, dir, plan.entry, tight);
      plan.score    = 70.0 + MtfLayers(ctx, dir);
      plan.reason   = StringFormat("R5B-RUNNER(stop %.2fR, target %.1fR)", InpStopFactor,
                                   (plan.target - plan.entry) / tight * (dir > 0 ? 1 : -1));
      return true;
   }

   //--- runner target: the next liquidity pool, capped at 8R
   double LiquidityTarget(SEAContext &ctx, const int dir, const double entry, const double stopDist)
   {
      MqlRates r[];
      int n = (int)InpLiquidityLookback;
      if(EA_Rates(ctx.symbol, PERIOD_M15, 1, n, r) < 10) return entry + dir * InpRunnerTargetR * stopDist;
      double best = 0.0;
      for(int i = 0; i < n; i++)
      {
         if(dir > 0 && r[i].high > entry)
         {
            if(best == 0.0 || r[i].high < best) best = r[i].high;     // nearest pool above
         }
         if(dir < 0 && r[i].low < entry)
         {
            if(best == 0.0 || r[i].low > best) best = r[i].low;       // nearest pool below
         }
      }
      if(best == 0.0) return entry + dir * InpRunnerTargetR * stopDist;
      double poolR = MathAbs(best - entry) / stopDist;
      if(poolR < 2.0 || poolR > InpRunnerTargetR)
         return entry + dir * InpRunnerTargetR * stopDist;
      return best;
   }

   //--- MTF conviction layers: +0.10/+0.15/+0.20R of expected edge
   double MtfLayers(SEAContext &ctx, const int dir)
   {
      double layers = 0.0;
      if(ctx.emaD1_200 > 0.0 && ((dir > 0 && ctx.mid > ctx.emaD1_200) ||
                                 (dir < 0 && ctx.mid < ctx.emaD1_200))) layers += 10.0;
      if(ctx.adx14 > 20.0 && ctx.adx14 < 45.0) layers += 15.0;
      if(ctx.atrD1 > 0.0 && ctx.atr > 0.4 * ctx.atrD1) layers += 20.0;
      return layers;
   }
};

CRound5B g_Round5B;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round5B);
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
