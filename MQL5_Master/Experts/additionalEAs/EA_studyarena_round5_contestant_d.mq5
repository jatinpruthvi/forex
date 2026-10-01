//+------------------------------------------------------------------+
//| EA_studyarena_round5_contestant_d.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 5D - 3-shift portfolio with an un-blow-up-able equal-lot grid
//| Source document : docs/research/study_arena/studyarena-round5-contestant-d.md
//| Tracker entry   : #52  |  Magic: 2019
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound5D class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 5D - 3-shift portfolio with an un-blow-up-able equal-lot grid"
#property description "Source: docs/research/study_arena/studyarena-round5-contestant-d.md"

#include "..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURGBP,AUDNZD,EURUSD,GBPUSD,XAUUSD,USDCAD";      // Comma separated universe
input double          InpRiskPct          = 1.5;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 0;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 20;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 6;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2019; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpGridSpacingDailyAtr = 0.30;  // 3 levels spaced by 30% of daily ATR
input int    InpGridMaxLegs       = 3;     // Exactly three equal legs
input double InpRunnerPartialPct  = 75.0;  // Close 75% at 1R
input int    InpGridFlatMin       = 6 * 60 + 30;  // Flat by 06:30 UK, no matter what

//+------------------------------------------------------------------+
//| Strategy: Round 5D - 3-shift portfolio with an un-blow-up-able equal-lot grid
//+------------------------------------------------------------------+
class CRound5D : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R5D_THREE_SHIFT";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round5-contestant-d.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M15;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = InpGridMaxLegs;
      cfg.minSecondsBetweenTrades = 60;
      cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 22;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = InpRunnerPartialPct;
      cfg.breakEvenAtR          = 1.00;
      cfg.trailAtR              = 1.00;  cfg.trailDistanceR = 1.50;
      cfg.timeStopMinutes       = 0;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- Shift 1: Asian session grid (EURGBP / AUDNZD, ADX < 20, three equal legs)
      if(ctx.clockMinutes < InpGridFlatMin && IsQuietCross(ctx.symbol))
      {
         if(ctx.adx14 >= 20.0) return false;
         if(!EqualLegPlan(ctx, plan)) return false;
         plan.reason = "R5D-ASIAGRID " + plan.reason;
         return true;
      }

      //--- Shift 2: London liquidity sweep (EURUSD / GBPUSD)
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
         plan.reason = "R5D-LONDONSWEEP " + plan.reason;
         return true;
      }

      //--- Shift 3: NY pullback into the 15m 20-EMA (XAUUSD / USDCAD)
      if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 16 * 60 &&
         (StringFind(ctx.symbol, "XAU") >= 0 || StringFind(ctx.symbol, "USDCAD") >= 0))
      {
         if(!SigEmaPullback(ctx, NyParams(), plan)) return false;
         plan.reason = "R5D-NYPULLBACK " + plan.reason;
         return true;
      }
      return false;
   }

   SEmaPullbackParams NyParams()
   {
      SEmaPullbackParams ep;
      ep.Reset();
      ep.emaPeriod = 20; ep.maxDistanceAtr = 1.20;
      ep.requireTrend = true; ep.targetR = 2.0;
      return ep;
   }

   bool IsQuietCross(const string sym)
   {
      return (StringFind(sym, "EURGBP") >= 0 || StringFind(sym, "AUDNZD") >= 0);
   }

   //--- equal-size legs (0.01, 0.01, 0.01 - never increase the multiplier)
   bool EqualLegPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      int legs = EA_CountPositions(ctx.symbol, true);
      if(legs >= InpGridMaxLegs) return false;
      double spacing = InpGridSpacingDailyAtr * ctx.atrD1;
      if(spacing <= 0.0) return false;
      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 30, r) < 20) return false;
      double hi = r[0].high, lo = r[0].low;
      for(int i = 1; i < 20; i++) { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }
      double mid = 0.5 * (hi + lo);
      int dir = (ctx.mid < mid) ? +1 : -1;
      if(legs > 0)
      {
         double last = GridLastEntry(ctx.symbol);
         if(last == 0.0) return false;
         double adverse = (dir > 0) ? (last - ctx.mid) : (ctx.mid - last);
         if(adverse < spacing) return false;
      }
      double avg = GridAverageEntry(ctx.symbol, ctx.mid);
      plan.Reset();
      plan.dir      = dir;
      plan.entry    = (dir > 0) ? ctx.ask : ctx.bid;
      plan.riskDist = spacing;
      plan.stop     = (dir > 0) ? avg - 3.0 * spacing : avg + 3.0 * spacing;
      plan.target   = (dir > 0) ? avg + spacing : avg - spacing;
      plan.score    = 45.0;
      plan.isLimit  = true;
      plan.expiry   = TimeTradeServer() + (datetime)(30 * 60);
      plan.reason   = StringFormat("equal leg %d", legs + 1);
      return true;
   }

   double GridLastEntry(const string sym)
   {
      datetime newest = 0; double entry = 0.0;
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

   double GridAverageEntry(const string sym, const double candidate)
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

   //--- forced flat by 06:30 UK - London volume destroys grids
   void Manage(SEAContext &ctx)
   {
      if(!IsQuietCross(ctx.symbol)) return;
      if(EA_CountPositions(ctx.symbol, true) == 0) return;
      if(ctx.clockMinutes >= InpGridFlatMin) g_eaExec.CloseAll("06:30 grid flat");
   }
};

CRound5D g_Round5D;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round5D);
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
