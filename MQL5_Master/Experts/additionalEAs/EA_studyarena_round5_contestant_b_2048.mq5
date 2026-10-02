//+------------------------------------------------------------------+
//| EA_studyarena_round5_contestant_b_2048.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 5B-2048 - Contestant E's executable core: 3 equal legs, 0.5% basket, RSI(2) entry
//| Source document : docs/research/study_arena/studyarena-round5-contestant-b.md
//| Tracker entry   : #50  |  Magic: 2048
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound5B2 class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 5B-2048 - Contestant E's executable core: 3 equal legs, 0.5% basket, RSI(2) entry"
#property description "Source: docs/research/study_arena/studyarena-round5-contestant-b.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURGBP,AUDNZD,EURUSD,GBPUSD,USDJPY";      // Comma separated universe
input double          InpRiskPct          = 1.0;   // Base risk per trade (% of equity)
input double          InpDailyLossPct     = 2.0;   // Halt for the day at -x% (0 = off)
input int             InpMaxTradesPerDay  = 6;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2048; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpBasketCapPct      = 0.50;  // Hard basket cap (E's 0.5%)
input double InpLegSpacingAtr     = 0.30;  // 3 legs spaced by 30% of daily ATR
input double InpRsi2Level         = 5.0;   // RSI(2) < 5 (long) / > 95 (short)
input double InpBbSigma           = 2.00;  // 2-sigma Bollinger entry band
input double InpGridAdxMax        = 16.0;  // ADX(14) < 16 gate
input double InpTrendOverrideKill = 1.00;  // Kill the grid if H1 EMA50 slope exceeds

//+------------------------------------------------------------------+
//| Strategy: Round 5B-2048 - Contestant E's executable core: 3 equal legs, 0.5% basket, RSI(2) entry
//+------------------------------------------------------------------+
class CRound5B2 : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R5B2_E_CORE";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round5-contestant-b.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M15;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 3;                       // exactly three equal legs
      cfg.minSecondsBetweenTrades = 60;
      cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 22;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.partial1AtR           = 1.50;  cfg.partial1Pct = 75.0;   // 75% off at 1.5R
      cfg.breakEvenAtR          = 1.50;
      cfg.trailAtR              = 1.50;  cfg.trailDistanceR = 1.50;
      cfg.timeStopMinutes       = 0;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- grid sleeve: quiet crosses only, in the Asian session
      if(ctx.clockMinutes < 7 * 60 && IsQuietPair(ctx.symbol))
      {
         if(ctx.adx14 >= InpGridAdxMax) return false;       // E's ADX < 16 gate
         if(!AtrBelow40thPct(ctx)) return false;            // ATR 40th percentile gate
         if(TrendOverride(ctx)) return false;               // trend-override kill
         int legs = EA_CountPositions(ctx.symbol, true);
         if(legs >= 3) return false;
         if(legs > 0 && !LegSpaced(ctx)) return false;
         if(!Rsi2BollingerPlan(ctx, plan)) return false;
         plan.reason = StringFormat("R5B2-GRID(leg %d) %s", legs + 1, plan.reason);
         return true;
      }

      //--- trend sleeve: London sweep (E's business core) for the majors
      if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 10 * 60 + 30 &&
         (StringFind(ctx.symbol, "EURUSD") >= 0 || StringFind(ctx.symbol, "GBPUSD") >= 0))
      {
         SSweepParams p;
         p.Reset();
         p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
         p.sessionFromMin = 7 * 60; p.sessionToMin = 10 * 60 + 30;
         p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
         p.reclaimWindowBars = 3; p.wickRatio = 0.55; p.bodyRatio = 0.55;
         p.stopBufferAtr = 0.10; p.minStopAtr = 0.50; p.maxStopAtr = 1.50;
         p.entryRetrace = 0.50; p.targetR = 2.0;
         if(!SigSweepReclaim(ctx, p, plan)) return false;
         plan.reason = "R5B2-LONDONSWEEP " + plan.reason;
         return true;
      }

      //--- NY pullback sleeve
      if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 16 * 60)
      {
         if(!SigEmaPullback(ctx, PullbackParams(), plan)) return false;
         plan.reason = "R5B2-NYPULLBACK " + plan.reason;
         return true;
      }
      return false;
   }

   SEmaPullbackParams PullbackParams()
   {
      SEmaPullbackParams ep;
      ep.Reset();
      ep.emaPeriod = 20; ep.maxDistanceAtr = 1.20;
      ep.requireTrend = true; ep.targetR = 2.0;
      return ep;
   }

   bool IsQuietPair(const string sym)
   {
      return (StringFind(sym, "EURGBP") >= 0 || StringFind(sym, "AUDNZD") >= 0);
   }

   bool AtrBelow40thPct(SEAContext &ctx)
   {
      double av[];
      if(EA_BufN(g_eaInd[ctx.index].hAtrD1, 0, 1, 60, av) < 30) return true;
      double s[];
      ArrayResize(s, ArraySize(av));
      ArrayCopy(s, av);
      ArraySort(s);
      double p40 = s[(int)MathRound(0.40 * (ArraySize(s) - 1))];
      return (p40 <= 0.0 || ctx.atrD1 <= p40);
   }

   bool TrendOverride(SEAContext &ctx)
   {
      if(ctx.emaH1_50 <= 0.0 || ctx.emaH1_200 <= 0.0) return false;
      double slope = ctx.emaH1_50 - ctx.emaH1_200;
      if(ctx.atr <= 0.0) return false;
      return (MathAbs(slope) > InpTrendOverrideKill * ctx.atr);
   }

   bool LegSpaced(SEAContext &ctx)
   {
      double last = 0.0; datetime newest = 0;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;
         if(PositionGetInteger(POSITION_TIME) >= newest)
         { newest = PositionGetInteger(POSITION_TIME); last = PositionGetDouble(POSITION_PRICE_OPEN); }
      }
      if(last == 0.0) return true;
      return (MathAbs(ctx.mid - last) >= InpLegSpacingAtr * ctx.atrD1);
   }

   //--- E's entry trio: RSI(2) extreme + 2-sigma Bollinger band + flat ADX
   bool Rsi2BollingerPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 30, r) < 22) return false;
      //--- RSI(2) computed inline
      double gain = 0.0, loss = 0.0;
      for(int i = 0; i < 2; i++)
      {
         double d = r[i].close - r[i + 1].close;
         if(d > 0.0) gain += d; else loss -= d;
      }
      double rsi2 = 100.0;
      if(gain + loss > 0.0) rsi2 = 100.0 * gain / (gain + loss);
      //--- 2-sigma band
      double sum = 0.0;
      for(int i = 0; i < 20; i++) sum += r[i].close;
      double mean = sum / 20.0;
      double var = 0.0;
      for(int i = 0; i < 20; i++) var += (r[i].close - mean) * (r[i].close - mean);
      double sd = MathSqrt(var / 20.0);

      int dir = 0;
      if(rsi2 < InpRsi2Level && r[0].close < mean - InpBbSigma * sd) dir = +1;
      if(rsi2 > 100.0 - InpRsi2Level && r[0].close > mean + InpBbSigma * sd) dir = -1;
      if(dir == 0) return false;

      double spacing = InpLegSpacingAtr * ctx.atrD1;
      if(spacing <= 0.0) return false;
      plan.Reset();
      plan.dir      = dir;
      plan.entry    = (dir > 0) ? ctx.ask : ctx.bid;
      plan.riskDist = MathMax(spacing, 0.30 * ctx.atr);
      plan.stop     = (dir > 0) ? plan.entry - plan.riskDist : plan.entry + plan.riskDist;
      plan.target   = mean;                                // exit at the band mean
      plan.score    = 50.0;
      plan.reason   = StringFormat("rsi2 %.1f band %.5f", rsi2, mean);
      return true;
   }

   //--- equal legs, hard 0.5% basket cap, flat if the market turns trending
   void Manage(SEAContext &ctx)
   {
      if(!IsQuietPair(ctx.symbol)) return;
      int legs = EA_CountPositions(ctx.symbol, true);
      if(legs == 0) return;
      if(ctx.floatingPl < -InpBasketCapPct / 100.0 * ctx.equity)
      {
         g_eaExec.CloseAll("0.5% basket cap");
         return;
      }
      if(TrendOverride(ctx)) g_eaExec.CloseAll("trend override kill");
      if(ctx.clockMinutes >= 7 * 60) g_eaExec.CloseAll("Asian session flat");
   }
};

CRound5B2 g_Round5B2;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round5B2);
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
