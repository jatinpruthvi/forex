//+------------------------------------------------------------------+
//| EA_studyarena_round4_contestant_d.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 4D - regime router: trend, range and expansion portfolios with exact ladders
//| Source document : docs/research/study_arena/studyarena-round4-contestant-d.md
//| Tracker entry   : #44  |  Magic: 2013
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound4D class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 4D - regime router: trend, range and expansion portfolios with exact ladders"
#property description "Source: docs/research/study_arena/studyarena-round4-contestant-d.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY,EURJPY,AUDUSD,AUDJPY,EURGBP";      // Comma separated universe
input double          InpRiskPct          = 1.0;   // Base risk per trade (% of equity)
input int             InpMaxTradesPerDay  = 5;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2013; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpTrendAdx          = 22.0;  // Trend regime: H1 ADX above
input double InpRangeAdx          = 18.0;  // Range regime: H1 ADX below
input double InpMaxStopAtrH1      = 0.35;  // Skip if the sweep stop > 0.35 x H1 ATR
input int    InpTokyoFromMin      = 9 * 60;   // Tokyo opening range start (local)
input int    InpTokyoToMin        = 10 * 60;  // Tokyo opening range end
input int    InpNyFromMin         = 8 * 60 + 35;   // NY continuation start
input int    InpNyToMin           = 11 * 60;       // NY continuation end

//+------------------------------------------------------------------+
//| Strategy: Round 4D - regime router: trend, range and expansion portfolios with exact ladders
//+------------------------------------------------------------------+
class CRound4D : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R4D_REGIME_ROUTER";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round4-contestant-d.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;              // the document's entry precision
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 600;
      cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 22;  cfg.sessionEndMin   = 0;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      //--- document ladder: 50% at 1R, 25% at 2R, trail the last 25% behind M15 structure
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;
      cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 25.0;
      cfg.breakEvenAtR          = 2.00;
      cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 0.75;
      cfg.timeStopMinutes       = 240;
      cfg.useLimitEntry         = true;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      int regime = Regime(ctx);
      if(regime == 0) return false;                       // unclear/transition: no trade

      //--- Strategy A: London liquidity-sweep reversal (European majors)
      if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 10 * 60 + 30 && IsMajors(ctx.symbol))
      {
         if(regime != 1 && regime != 2) return false;
         if(AsiaRangeTooWide(ctx)) return false;
         if(!SweepReversal(ctx, plan)) return false;
         if(plan.riskDist > InpMaxStopAtrH1 * ctx.atr * 4.0) return false;   // 0.35 x H1 ATR
         plan.reason = "R4D-LONDONSWEEP " + plan.reason;
         return true;
      }

      //--- Strategy B: Tokyo opening-range breakout (yen + commodity currencies)
      if(ctx.clockMinutes >= InpTokyoFromMin && ctx.clockMinutes < InpTokyoToMin && IsTokyoPair(ctx.symbol))
      {
         if(regime != 3) return false;
         if(!SigAsianBreakout(ctx, 0.10, 0.20, 2.0, plan)) return false;
         plan.reason = "R4D-TOKYOORB " + plan.reason;
         return true;
      }

      //--- Strategy C: New York continuation of the London move
      if(ctx.clockMinutes >= InpNyFromMin && ctx.clockMinutes < InpNyToMin)
      {
         if(regime != 1) return false;
         if(!LondonDirectional(ctx)) return false;
         if(!SigEmaPullback(ctx, NypParams(), plan)) return false;
         plan.reason = "R4D-NYCONTINUATION " + plan.reason;
         return true;
      }
      return false;
   }

   SEmaPullbackParams NypParams()
   {
      SEmaPullbackParams ep;
      ep.Reset();
      ep.emaPeriod = 20; ep.maxDistanceAtr = 1.20;
      ep.requireTrend = true; ep.targetR = 2.0;
      return ep;
   }

   //--- 1 trend, 2 range, 3 expansion, 0 unclear
   int Regime(SEAContext &ctx)
   {
      bool h4Trend = false;
      if(ctx.emaH1_50 > 0.0 && ctx.emaH1_200 > 0.0)
         h4Trend = (ctx.emaH1_50 > ctx.emaH1_200 && ctx.mid > ctx.emaH1_50) ||
                   (ctx.emaH1_50 < ctx.emaH1_200 && ctx.mid < ctx.emaH1_50);
      if(ctx.adxH1 > InpTrendAdx && h4Trend) return 1;
      if(ctx.adxH1 < InpRangeAdx && !h4Trend) return 2;
      if(ctx.atr > 0.0 && ctx.atrD1 > 0.0 && ctx.atr > 0.5 * ctx.atrD1 &&
         ctx.inSession && ctx.adxH1 > InpRangeAdx) return 3;
      return 0;
   }

   bool IsMajors(const string sym)
   {
      return (StringFind(sym, "EURUSD") >= 0 || StringFind(sym, "GBPUSD") >= 0);
   }

   bool IsTokyoPair(const string sym)
   {
      return (StringFind(sym, "JPY") >= 0 || StringFind(sym, "AUD") >= 0);
   }

   bool AsiaRangeTooWide(SEAContext &ctx)
   {
      double hi = 0.0, lo = 0.0;
      if(!SigAsianRange(ctx.symbol, hi, lo)) return true;
      return ((hi - lo) > 0.8 * ctx.atr * 4.0);
   }

   //--- document's exact London sweep-reversal sequence
   bool SweepReversal(SEAContext &ctx, SSignalPlan &plan)
   {
      double hi = 0.0, lo = 0.0;
      if(!SigAsianRange(ctx.symbol, hi, lo)) return false;
      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M5, 1, 6, r) < 5) return false;
      //--- long: swept the Asian low, M5 closed back inside, then broke the lower high
      bool sweptLow  = (r[3].low < lo && r[2].close > lo);
      bool brokeHigh = false;
      for(int i = 0; i < 3; i++)
      {
         double body = MathAbs(r[i].close - r[i].open);
         double range = r[i].high - r[i].low;
         if(range <= 0.0) continue;
         if(r[i].close > r[i + 1].high && body >= 0.60 * range) { brokeHigh = true; break; }
      }
      if(sweptLow && brokeHigh) return BullPlan(ctx, plan, lo);
      bool sweptHigh = (r[3].high > hi && r[2].close < hi);
      bool brokeLow  = false;
      for(int i = 0; i < 3; i++)
      {
         double body = MathAbs(r[i].close - r[i].open);
         double range = r[i].high - r[i].low;
         if(range <= 0.0) continue;
         if(r[i].close < r[i + 1].low && body >= 0.60 * range) { brokeLow = true; break; }
      }
      if(sweptHigh && brokeLow) return BearPlan(ctx, plan, hi);
      return false;
   }

   bool BullPlan(SEAContext &ctx, SSignalPlan &plan, const double sweepLow)
   {
      double stop = sweepLow - 0.10 * ctx.atr;
      if(ctx.mid - stop <= 0.0) return false;
      plan.Reset();
      plan.dir      = +1;
      plan.entry    = ctx.ask;
      plan.riskDist = ctx.ask - stop;
      plan.stop     = stop;
      plan.target   = plan.entry + 2.0 * plan.riskDist;
      plan.score    = 65.0;
      return true;
   }

   bool BearPlan(SEAContext &ctx, SSignalPlan &plan, const double sweepHigh)
   {
      double stop = sweepHigh + 0.10 * ctx.atr;
      if(stop - ctx.bid <= 0.0) return false;
      plan.Reset();
      plan.dir      = -1;
      plan.entry    = ctx.bid;
      plan.riskDist = stop - ctx.bid;
      plan.stop     = stop;
      plan.target   = plan.entry - 2.0 * plan.riskDist;
      plan.score    = 65.0;
      return true;
   }

   bool LondonDirectional(SEAContext &ctx)
   {
      MqlRates h1[];
      if(EA_Rates(ctx.symbol, PERIOD_H1, 1, 4, h1) < 3) return false;
      double move = h1[0].close - h1[2].open;
      return (MathAbs(move) > 0.25 * ctx.atr * 4.0);
   }
};

CRound4D g_Round4D;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round4D);
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
