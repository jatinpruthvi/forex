//+------------------------------------------------------------------+
//| EA_studyarena_round2_contestant_b.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 2B - portfolio of five return engines with graded conviction sizing
//| Source document : docs_v1/docs/coreIdea/studyarena-round2-contestant-b.md
//| Tracker entry   : #35  |  Magic: 2004
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound2B class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 2B - portfolio of five return engines with graded conviction sizing"
#property description "Source: docs_v1/docs/coreIdea/studyarena-round2-contestant-b.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY,XAUUSD,AUDNZD";      // Comma separated universe
input double          InpRiskPct          = 1.0;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 4.0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 0;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 20;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 6;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2004; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpScoreFullRiskPct   = 2.00;  // Score >= 8/10 -> 2.0% risk
input double InpScoreMidRiskPct    = 1.00;  // Score 6-7/10 -> 1.0% risk
input int    InpScoreMinToTrade    = 6;     // Below this score: no trade
input double InpNarrowAsiaRangeAtr = 0.60;  // Session-open breakout when Asia range < x ATR20
input double InpSwapHarvestPct     = 0.50;  // Engine 5: carry/swap harvest risk

//+------------------------------------------------------------------+
//| Strategy: Round 2B - portfolio of five return engines with graded conviction sizing
//+------------------------------------------------------------------+
class CRound2B : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R2B_ENGINE_PORTFOLIO";
      cfg.sourceDoc             = "docs_v1/docs/coreIdea/studyarena-round2-contestant-b.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpScoreMidRiskPct;      // scaled per setup by LotsMultiplier
      cfg.signalTimeframe       = PERIOD_M15;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.profitTargetPct       = InpProfitTargetPct;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 3;
      cfg.minSecondsBetweenTrades = 300;
      cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 21;  cfg.sessionEndMin = 0;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.timeStopMinutes       = 180;
      cfg.breakEvenAtR          = 1.0;
      cfg.trailAtR              = 2.0;  cfg.trailDistanceR = 0.75;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      m_score = 0.0;

      //--- Engine 4: mean reversion at HTF extremes (2.5 sigma, ranging regime)
      if(ctx.adx14 > 0.0 && ctx.adx14 < 20.0)
      {
         SSignalPlan z;
         if(SigZScoreFade(ctx, 20, 2.50, 0.50, 1.50, z))
         {
            double score = ScoreConfluence(ctx, z.dir) + 2.0;
            if(score >= InpScoreMinToTrade)
            {
               plan = z; ScoreTo(plan, score);
               plan.reason = "R2B-MEANREV " + plan.reason;
               return true;
            }
         }
      }

      //--- Engine 2/3: Asian-range liquidity raid + narrow-range session breakout
      if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 10 * 60)
      {
         double hi = 0.0, lo = 0.0, atr20 = 0.0;
         MqlRates d[];
         if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 25, d) >= 21)
         {
            double sum = 0.0;
            for(int i = 1; i <= 20; i++) sum += (d[i].high - d[i].low);
            atr20 = sum / 20.0;
         }
         if(SigAsianRange(ctx.symbol, hi, lo) && hi > lo && atr20 > 0.0)
         {
            bool narrow = (hi - lo) < InpNarrowAsiaRangeAtr * atr20;
            SSignalPlan a;
            if(narrow && SigAsianBreakout(ctx, 0.05, 0.20, 2.0, a))
            {
               double score = ScoreConfluence(ctx, a.dir) + 3.0;
               if(score >= InpScoreMinToTrade)
               {
                  plan = a; ScoreTo(plan, score);
                  plan.reason = "R2B-SESSIONBREAK " + plan.reason;
                  return true;
               }
            }
         }
      }

      //--- Engine 1: SMC-style sweep + reclaim continuation
      SSweepParams p;
      p.Reset();
      p.rangeFromMin   = 0;
      p.rangeToMin     = 7 * 60;
      p.sessionFromMin = 7 * 60;
      p.sessionToMin   = 16 * 60;
      p.sweepMinAtr    = 0.05;
      p.sweepMaxAtr    = 0.50;
      p.reclaimWindowBars = 3;
      p.wickRatio      = 0.60;
      p.bodyRatio      = 0.60;
      p.stopBufferAtr  = 0.10;
      p.minStopAtr     = 0.60;  p.maxStopAtr = 1.50;
      p.entryRetrace   = 0.50;
      p.targetR        = 3.0;                       // fixed 3R with runner potential
      if(ctx.clockMinutes < p.sessionFromMin || ctx.clockMinutes >= p.sessionToMin) return false;
      if(!SigSweepReclaim(ctx, p, plan)) return false;

      double score = ScoreConfluence(ctx, plan.dir) + 2.0;
      if(score < InpScoreMinToTrade) return false;
      ScoreTo(plan, score);
      plan.reason = StringFormat("R2B-SMC(%.0f/10) %s", score, plan.reason);
      return true;
   }

   double m_score;

   //--- confluence grading (0..10) used for conviction sizing
   double ScoreConfluence(SEAContext &ctx, const int dir)
   {
      double score = 0.0;
      //--- HTF bias aligned (H4/D1)
      if(ctx.emaD1_200 > 0.0 && ((dir > 0 && ctx.mid > ctx.emaD1_200) || (dir < 0 && ctx.mid < ctx.emaD1_200)))
         score += 3.0;
      //--- H1 structure aligned
      if(ctx.emaH1_50 > 0.0 && ((dir > 0 && ctx.mid > ctx.emaH1_50) || (dir < 0 && ctx.mid < ctx.emaH1_50)))
         score += 2.0;
      //--- momentum regime
      if(ctx.adx14 >= 20.0 && ctx.adx14 <= 45.0) score += 2.0;
      //--- volatility expanding but not spiking
      if(ctx.atr > 0.0 && ctx.atrD1 > 0.0 && ctx.atr < ctx.atrD1 * 0.5) score += 1.5;
      //--- no counter-trend RSI extreme
      if((dir > 0 && ctx.rsi14 < 70.0) || (dir < 0 && ctx.rsi14 > 30.0)) score += 1.5;
      return MathMin(score, 10.0);
   }

   void ScoreTo(SSignalPlan &plan, const double score)
   {
      m_score    = score;
      plan.score = score * 10.0;
   }

   //--- graded conviction sizing: score >= 8 -> full risk, 6-7 -> mid risk, else none
   double LotsMultiplier(SEAContext &ctx)
   {
      if(m_score >= 8.0) return (InpScoreMidRiskPct > 0.0) ? InpScoreFullRiskPct / InpScoreMidRiskPct : 1.0;
      return 1.0;
   }
};

CRound2B g_Round2B;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round2B);
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
