//+------------------------------------------------------------------+
//| EA_studyarena_round4_contestant_c.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 4C - 24-hour matrix: Asian grid, London Judas swing, NY pullback
//| Source document : docs/research/study_arena/studyarena-round4-contestant-c.md
//| Tracker entry   : #42  |  Magic: 2011
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound4C class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 4C - 24-hour matrix: Asian grid, London Judas swing, NY pullback"
#property description "Source: docs/research/study_arena/studyarena-round4-contestant-c.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "AUDNZD,EURGBP,EURUSD,GBPUSD,XAUUSD,USDCAD";      // Comma separated universe
input double          InpRiskPct          = 1.5;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 0;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 20;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 8;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2011; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpGridLeg1Lots      = 0.05;  // Asian grid: leg 1 volume
input int    InpGridSpacingPips    = 15;    // Asian grid: spacing between legs (pips)
input double InpGridLeg3Mult       = 1.40;  // Leg 3 multiplier (1.4x, capped ladder)
input int    InpGridTakePips       = 10;    // TP above the average entry (pips)
input int    InpGridStopPips       = 60;    // Hard stop below leg 1 (pips) - ~$200 cap
input double InpJudasTargetR       = 2.00;  // London Judas swing target
input double InpNyPullbackEma      = 20;    // NY pullback: 15m EMA
input double InpNyFibRetrace       = 0.50;  // NY pullback: 50% of the London move

//+------------------------------------------------------------------+
//| Strategy: Round 4C - 24-hour matrix: Asian grid, London Judas swing, NY pullback
//+------------------------------------------------------------------+
class CRound4C : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R4C_24H_MATRIX";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round4-contestant-c.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M15;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 3;                       // grid legs 1-3
      cfg.minSecondsBetweenTrades = 0;
      cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 23;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.timeStopMinutes       = 0;
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 75.0;   // 75% off at 1R
      cfg.breakEvenAtR          = 1.00;
      cfg.trailAtR              = 1.00;  cfg.trailDistanceR = 1.50;
      cfg.useLimitEntry         = true;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- Asian shift (23:00-06:30 London): mean-reversion grid on crosses only
      if(ctx.clockMinutes < 6 * 60 + 30)
      {
         if(!IsGridPair(ctx.symbol)) return false;
         if(ctx.adx14 >= 20.0) return false;
         if(!GridLegPlan(ctx, plan)) return false;
         plan.reason = "R4C-ASIANGRID " + plan.reason;
         return true;
      }

      //--- London Judas swing (07:00-08:00 GMT): fade the fakeout of the Asian extreme
      if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 9 * 60)
      {
         SSweepParams p;
         p.Reset();
         p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
         p.sessionFromMin = 7 * 60; p.sessionToMin = 9 * 60;
         p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
         p.reclaimWindowBars = 3; p.wickRatio = 0.50; p.bodyRatio = 0.50;
         p.stopBufferAtr = 0.10; p.minStopAtr = 0.50; p.maxStopAtr = 1.50;
         p.entryRetrace = 0.50; p.targetR = InpJudasTargetR;
         if(!SigSweepReclaim(ctx, p, plan)) return false;
         plan.reason = "R4C-JUDAS " + plan.reason;
         return true;
      }

      //--- NY shift (13:00-16:00 London): pullback into the 15m 20-EMA of the London move
      if(ctx.clockMinutes >= 13 * 60 && ctx.clockMinutes < 16 * 60)
      {
         if(IsGridPair(ctx.symbol)) return false;            // never grid in NY
         if(!Londontrend(ctx)) return false;
         int bias = LondonBias(ctx);
         SEmaPullbackParams ep;
         ep.Reset();
         ep.emaPeriod = (int)InpNyPullbackEma;
         ep.maxDistanceAtr = 1.50; ep.requireTrend = true; ep.targetR = 2.0;
         if(!SigEmaPullback(ctx, ep, plan)) return false;
         if(plan.dir != bias) return false;
         plan.reason = StringFormat("R4C-NYFIB(%.0f%%) %s", InpNyFibRetrace * 100.0, plan.reason);
         return true;
      }
      return false;
   }

   bool IsGridPair(const string sym)
   {
      return (StringFind(sym, "AUDNZD") >= 0 || StringFind(sym, "EURGBP") >= 0);
   }

   //--- grid ladder: same-direction legs spaced by a fixed pip distance, 1.4x on leg 3
   bool GridLegPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      double pip = EA_PipSize(ctx.symbol);
      if(pip <= 0.0) return false;
      //--- bias from where price sits inside the 50-bar channel
      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 55, r) < 51) return false;
      double hi = r[1].high, lo = r[1].low;
      for(int i = 1; i <= 50; i++) { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }
      double mid = 0.5 * (hi + lo);
      int dir = (ctx.mid < mid) ? +1 : -1;                  // fade back to the channel mean

      int legs = EA_CountPositions(ctx.symbol, true);
      double entry = ctx.mid;
      if(legs > 0)
      {
         //--- only add when price has travelled one spacing against the basket
         double lastEntry = LastEntry(ctx.symbol);
         if(lastEntry == 0.0) return false;
         double adverse = (dir > 0) ? (lastEntry - ctx.mid) : (ctx.mid - lastEntry);
         if(adverse < InpGridSpacingPips * pip) return false;
      }
      double spacing = InpGridSpacingPips * pip;
      //--- target 10 pips above the running average entry
      double avgEntry = RunningAverageEntry(ctx.symbol, entry);
      plan.Reset();
      plan.dir      = dir;
      plan.entry    = (dir > 0) ? MathMin(entry, ctx.ask) : MathMax(entry, ctx.bid);
      plan.isLimit  = true;
      plan.expiry   = TimeTradeServer() + (datetime)(15 * 60);
      plan.riskDist = InpGridStopPips * pip;
      plan.stop     = (dir > 0) ? avgEntry - InpGridStopPips * pip : avgEntry + InpGridStopPips * pip;
      plan.target   = (dir > 0) ? avgEntry + InpGridTakePips * pip : avgEntry - InpGridTakePips * pip;
      plan.score    = 40.0;
      plan.reason   = StringFormat("grid leg %d spacing %.0fpips", legs + 1, InpGridSpacingPips);
      return true;
   }

   double LastEntry(const string sym)
   {
      datetime newest = 0;
      double   entry  = 0.0;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != sym) continue;
         if(PositionGetInteger(POSITION_TIME) >= newest)
         { newest = PositionGetInteger(POSITION_TIME); entry = PositionGetDouble(POSITION_PRICE_OPEN); }
      }
      return entry;
   }

   double RunningAverageEntry(const string sym, const double candidate)
   {
      double sum = 0.0; int n = 0;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != sym) continue;
         sum += PositionGetDouble(POSITION_PRICE_OPEN);
         n++;
      }
      return (n > 0) ? (sum + candidate) / (double)(n + 1) : candidate;
   }

   int LondonBias(SEAContext &ctx)
   {
      return (ctx.ema50 > 0.0 && ctx.mid > ctx.ema50) ? +1
           : (ctx.ema50 > 0.0 && ctx.mid < ctx.ema50) ? -1 : 0;
   }

   bool Londontrend(SEAContext &ctx)
   {
      return (ctx.atr > 0.0 && MathAbs(ctx.mid - ctx.ema50) > 0.15 * ctx.atr);
   }

   //--- leg 3 is 1.4x, legs are otherwise flat (never martingale beyond that)
   double LotsMultiplier(SEAContext &ctx)
   {
      int legs = EA_CountPositions(ctx.symbol, true);
      if(legs == 2) return InpGridLeg3Mult;
      return 1.0;
   }
};

CRound4C g_Round4C;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round4C);
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
