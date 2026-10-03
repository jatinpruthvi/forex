//+------------------------------------------------------------------+
//| EA_studyarena_round4_contestant_f.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 4F - three sleeves: London break+retest, filtered Asian grid, NY momentum
//| Source document : docs/research/study_arena/studyarena-round4-contestant-f.md
//| Tracker entry   : #46  |  Magic: 2015
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound4F class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 4F - three sleeves: London break+retest, filtered Asian grid, NY momentum"
#property description "Source: docs/research/study_arena/studyarena-round4-contestant-f.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "GBPUSD,EURUSD,GBPJPY,EURCHF,EURGBP,AUDNZD,USDJPY,XAUUSD";      // Comma separated universe
input double          InpDailyLossPct     = 5.0;   // Halt for the day at -x% (0 = off)
input int             InpMaxTradesPerDay  = 8;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2015; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpSleeveARisk       = 1.20;  // A: London break+retest risk
input int    InpGridMaxLevels     = 8;     // Grid: max 8 levels
input double InpGridSpacingAtr    = 0.60;  // Spacing = 0.6 x H1 ATR
input double InpGridBasketCapPct  = 5.00;  // Hard basket stop (5-6% of account)
input int    InpGridCloseMin      = 7 * 60 - 0;  // Close every basket before 07:00

//+------------------------------------------------------------------+
//| Strategy: Round 4F - three sleeves: London break+retest, filtered Asian grid, NY momentum
//+------------------------------------------------------------------+
class CRound4F : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R4F_THREE_SLEEVES";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round4-contestant-f.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpSleeveARisk;
      cfg.signalTimeframe       = PERIOD_M15;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = InpGridMaxLevels;      // grid legs are the widest sleeve
      cfg.minSecondsBetweenTrades = 120;
      cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 22;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.partial1AtR           = 2.00;  cfg.partial1Pct = 100.0;   // sleeve A/B bank at target
      cfg.breakEvenAtR          = 1.00;
      cfg.timeStopMinutes       = 240;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- Sleeve B: Asian filtered grid (00:00-07:00 UK, grid-only pairs)
      if(ctx.clockMinutes < InpGridCloseMin)
      {
         if(!IsGridOnlyPair(ctx.symbol)) return false;
         if(!GridRegimeOk(ctx)) return false;
         if(!FadeBandPlan(ctx, plan)) return false;
         plan.reason = "R4F-GRID " + plan.reason;
         return true;
      }

      //--- Sleeve A: London range break + retest (07:00-10:00)
      if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 10 * 60)
      {
         if(IsGridOnlyPair(ctx.symbol)) return false;
         SBreakRetestParams br;
         br.Reset();
         br.rangeFromMin = 0; br.rangeToMin = 7 * 60;
         br.entryFromMin = 7 * 60; br.entryToMin = 10 * 60;
         br.minRangeAtr = 0.25; br.targetR = 2.0;
         if(!SigBreakRetest(ctx, br, plan)) return false;
         plan.reason = "R4F-LONDONBREAK " + plan.reason;
         return true;
      }

      //--- Sleeve C: NY momentum continuation (13:30-16:00)
      if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 16 * 60)
      {
         if(IsGridOnlyPair(ctx.symbol)) return false;
         if(!SigEmaPullback(ctx, MomentumParams(), plan)) return false;
         plan.reason = "R4F-NYMOMENTUM " + plan.reason;
         return true;
      }
      return false;
   }

   SEmaPullbackParams MomentumParams()
   {
      SEmaPullbackParams ep;
      ep.Reset();
      ep.emaPeriod = 20; ep.maxDistanceAtr = 1.50;
      ep.requireTrend = true; ep.targetR = 1.50;
      return ep;
   }

   bool ChannelBounds(SEAContext &ctx, const int bars, double &hi, double &lo)
   {
      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M15, 1, bars, r) < bars) return false;
      hi = r[0].high; lo = r[0].low;
      for(int i = 1; i < bars; i++) { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }
      return true;
   }

   bool IsGridOnlyPair(const string sym)
   {
      return (StringFind(sym, "EURCHF") >= 0 || StringFind(sym, "EURGBP") >= 0 ||
              StringFind(sym, "AUDNZD") >= 0);
   }

   //--- the document's 11-point grid checklist (ADX, channel, bands, news handled by engine)
   bool GridRegimeOk(SEAContext &ctx)
   {
      if(ctx.adxH1 >= 20.0) return false;                    // doc: ADX(14) < 20 on 1H
      if(ctx.adxH4 >= 20.0) return false;                    // doc: ... and on 4H
      double hi = 0.0, lo = 0.0;
      if(!SigAsianRange(ctx.symbol, hi, lo)) return false;
      if(hi <= lo) return false;
      //--- price must have stayed inside the channel for 12+ hours
      double chHi = 0.0, chLo = 0.0;
      if(!ChannelBounds(ctx, 48, chHi, chLo)) return false;
      if(chHi <= chLo) return false;
      if(ctx.mid > chHi || ctx.mid < chLo) return false;
      //--- kill tripwire: 1 ATR beyond the channel -> no new legs
      if(ctx.atrH1 > 0.0 && (ctx.mid > chHi + ctx.atrH1 || ctx.mid < chLo - ctx.atrH1)) return false;   // doc tripwire: 1 x 1H ATR
      return true;
   }

   //--- equal-size ladder: add only after price moved 0.6 x ATR against the basket
   bool FadeBandPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      int legs = EA_CountPositions(ctx.symbol, true);
      if(legs >= InpGridMaxLevels) return false;
      double chHi = 0.0, chLo = 0.0;
      if(!ChannelBounds(ctx, 48, chHi, chLo)) return false;
      double mid = 0.5 * (chHi + chLo);
      int dir = (ctx.mid < mid) ? +1 : -1;
      if(legs > 0)
      {
         double last = GridLastEntry(ctx.symbol);
         if(last == 0.0) return false;
         double adverse = (dir > 0) ? (last - ctx.mid) : (ctx.mid - last);
         if(adverse < InpGridSpacingAtr * ctx.atrH1) return false;      // doc: spacing = 0.6 x 1H ATR
      }
      double avg = GridAverageEntry(ctx.symbol, ctx.mid);
      double spacing = InpGridSpacingAtr * ctx.atrH1;                    // doc: spacing = 0.6 x 1H ATR
      plan.Reset();
      plan.dir      = dir;
      plan.entry    = (dir > 0) ? ctx.ask : ctx.bid;
      plan.riskDist = spacing;
      plan.stop     = (dir > 0) ? avg - 8.0 * spacing : avg + 8.0 * spacing;   // full-ladder cap
      plan.target   = (dir > 0) ? avg + 1.0 * spacing : avg - 1.0 * spacing;   // net +1 spacing
      plan.score    = 45.0;
      plan.isLimit  = true;
      plan.expiry   = TimeTradeServer() + (datetime)(30 * 60);
      plan.reason   = StringFormat("level %d channel %.5f-%.5f", legs + 1, chLo, chHi);
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

   //--- flat every basket before London wakes up, and cap the ladder at 5-6% of equity
   void Manage(SEAContext &ctx)
   {
      if(!IsGridOnlyPair(ctx.symbol)) return;
      int legs = EA_CountPositions(ctx.symbol, true);
      if(legs == 0) return;
      double floating = ctx.floatingPl;
      if(floating < -InpGridBasketCapPct / 100.0 * ctx.equity)
      {
         g_eaExec.CloseAll("grid basket cap");
         return;
      }
      if(ctx.clockMinutes >= InpGridCloseMin)
         g_eaExec.CloseAll("pre-London flat");
   }
};

CRound4F g_Round4F;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round4F);
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
