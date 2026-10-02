//+------------------------------------------------------------------+
//| EA_studyarena_round10_kimi_k3_high_reasoning.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 10 Kimi - SWEEP-1 multi-session engine with a score gate and drawdown throttle
//| Source document : docs/research/study_arena/studyarena-round10-kimi-k3-high-reasoning.md
//| Tracker entry   : #66  |  Magic: 2033
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound10Kimi class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 10 Kimi - SWEEP-1 multi-session engine with a score gate and drawdown throttle"
#property description "Source: docs/research/study_arena/studyarena-round10-kimi-k3-high-reasoning.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY,AUDUSD,XAUUSD,GBPJPY,AUDNZD,EURGBP";      // Comma separated universe
input double          InpDailyLossPct     = 3.0;   // Halt for the day at -x% (0 = off)
input int             InpMaxTradesPerDay  = 8;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2033; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpBaseRiskPct       = 0.60;  // SWEEP-1 risk per trade
input int    InpMinScore           = 7;     // Only trade setups scoring >= 7/10
input double InpThrottleAfterPct   = 3.00;  // Halve risk after a -3% drawdown
input double InpSweepMinPierceAtr  = 0.15;  // Wick must exceed the range by 0.15 x M15 ATR

//+------------------------------------------------------------------+
//| Strategy: Round 10 Kimi - SWEEP-1 multi-session engine with a score gate and drawdown throttle
//+------------------------------------------------------------------+
class CRound10Kimi : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R10KIMI_SWEEP1";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round10-kimi-k3-high-reasoning.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpBaseRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 2;
      cfg.minSecondsBetweenTrades = 120;
      cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 22;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;
      cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 30.0;
      cfg.breakEvenAtR          = 1.00;
      cfg.breakEvenOnBarClose   = true;    // doc: BE only after a completed bar close
      cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 1.00;
      cfg.timeStopMinutes       = 180;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- session range selection: Asian / London / New York
      int fromMin = 21 * 60, toMin = 24 * 60, sessFrom = 0, sessTo = 7 * 60;
      if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 13 * 60 + 30)
      { fromMin = 0; toMin = 7 * 60; sessFrom = 7 * 60; sessTo = 12 * 60; }
      else if(ctx.clockMinutes >= 13 * 60 + 30)
      { fromMin = 7 * 60; toMin = 13 * 60; sessFrom = 13 * 60 + 30; sessTo = 21 * 60; }

      //--- doc universe: the Asian mean-reversion sleeve trades AUDNZD/EURGBP only,
      //--- and only while H1 ADX(14) < 16 (the "no trend" regime)
      if(ctx.clockMinutes < 7 * 60 && (!IsAsianMrPair(ctx.symbol) || ctx.adxH1 >= 16.0)) return false;

      SSweepParams p;
      p.Reset();
      p.rangeFromMin = fromMin; p.rangeToMin = toMin;
      p.sessionFromMin = sessFrom; p.sessionToMin = sessTo;
      p.sweepMinAtr = InpSweepMinPierceAtr; p.sweepMaxAtr = 0.60;
      p.reclaimWindowBars = 3;
      p.wickRatio = 0.60; p.bodyRatio = 0.60;
      p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
      p.entryRetrace = 0.50; p.targetR = 2.0;
      if(!SigSweepReclaim(ctx, p, plan)) return false;

      int score = ScoreSetup(ctx, plan);
      if(score < InpMinScore) return false;
      plan.score  = score * 10.0;
      plan.reason = StringFormat("R10KIMI-SWEEP1(%d/10) %s", score, plan.reason);
      return true;
   }

   bool IsAsianMrPair(const string sym)
   {
      return (StringFind(sym, "AUDNZD") >= 0 || StringFind(sym, "EURGBP") >= 0);
   }

   int ScoreSetup(SEAContext &ctx, SSignalPlan &plan)
   {
      int score = 5;
      if(ctx.emaH1_50 > 0.0 && ((plan.dir > 0 && ctx.mid > ctx.emaH1_50) ||
                                (plan.dir < 0 && ctx.mid < ctx.emaH1_50))) score++;
      if(ctx.adx14 >= 18.0 && ctx.adx14 <= 35.0) score++;
      MqlRates d[];
      if(EA_Rates(ctx.symbol, PERIOD_D1, 1, 1, d) >= 1)
      {
         double tol = 0.25 * ctx.atr * 4.0;
         if(MathAbs(ctx.mid - d[0].high) < tol || MathAbs(ctx.mid - d[0].low) < tol) score++;
      }
      if(ctx.atrD1 > 0.0 && ctx.atr > 0.4 * ctx.atrD1) score++;
      double costR = (plan.riskDist > 0.0) ? (ctx.spreadPoints * ctx.point) / plan.riskDist : 1.0;
      if(costR <= 0.10) score++;
      return MathMin(score, 10);
   }

   //--- drawdown throttle: halve risk after a -3% equity drawdown
   double LotsMultiplier(SEAContext &ctx)
   {
      if(ctx.riskPct <= 0.0) return 0.0;
      double risk = InpBaseRiskPct;
      double equity = ctx.equity;
      double hwm = GlobalVariableGet("R10KIMI_HWM");
      if(hwm <= 0.0 || equity > hwm) { GlobalVariableSet("R10KIMI_HWM", MathMax(equity, hwm)); return 1.0; }
      if(hwm > 0.0 && equity < hwm * (1.0 - InpThrottleAfterPct / 100.0)) risk *= 0.50;
      return MathMax(0.0, risk / ctx.riskPct);
   }
};

CRound10Kimi g_Round10Kimi;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round10Kimi);
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
