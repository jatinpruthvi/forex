//+------------------------------------------------------------------+
//| EA_studyarena_round5_contestant_f.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 5F - stat-arb gates: ADX, band-width rank, channel check and 8-level ladder
//| Source document : docs/research/study_arena/studyarena-round5-contestant-f.md
//| Tracker entry   : #54  |  Magic: 2021
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound5F class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 5F - stat-arb gates: ADX, band-width rank, channel check and 8-level ladder"
#property description "Source: docs/research/study_arena/studyarena-round5-contestant-f.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURCHF,EURGBP,AUDNZD,EURUSD,GBPUSD,XAUUSD,USDJPY,USDCAD";      // Comma separated universe
input double          InpRiskPct          = 1.0;   // Base risk per trade (% of equity)
input int             InpMaxTradesPerDay  = 10;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2021; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input int    InpGridLevels        = 8;     // Max 8 equal-size levels
input double InpGridSpacingAtr    = 0.60;  // Spacing = 0.6 x H1 ATR
input double InpMaxSpreadPipsEur   = 1.00;  // Sleeve-1 spread cap, EURUSD (doc: < 1.0 pips)
input double InpMaxSpreadPipsGbp   = 1.50;  // Sleeve-1 spread cap, GBPUSD (doc: < 1.5 pips)

//+------------------------------------------------------------------+
//| Strategy: Round 5F - stat-arb gates: ADX, band-width rank, channel check and 8-level ladder
//+------------------------------------------------------------------+
class CRound5F : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R5F_STATARB_GATES";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round5-contestant-f.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M15;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = InpGridLevels;
      cfg.minSecondsBetweenTrades = 60;
      cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 22;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.timeStopMinutes       = 0;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- grid sleeve: only under the full gate stack, and only in the Asian window
      //--- merged doc gate: spread < 1.0 pips on EURUSD, < 1.5 on GBPUSD; other
      //--- pairs in the universe fall back to the looser cap
      double maxSpreadPips = InpMaxSpreadPipsGbp;
      if(StringFind(ctx.symbol, "EURUSD") >= 0)      maxSpreadPips = InpMaxSpreadPipsEur;
      if(EA_SpreadPips(ctx.symbol) > maxSpreadPips)
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.2f pips > %.2f - skip (doc sleeve-1 gate)", ctx.symbol, EA_SpreadPips(ctx.symbol), maxSpreadPips), true);
         return false;
      }

      if(ctx.clockMinutes < 7 * 60 && IsGridPair(ctx.symbol))
      {
         if(!GateStack(ctx)) return false;
         if(!LadderPlan(ctx, plan)) return false;
         plan.reason = "R5F-GRID " + plan.reason;
         return true;
      }

      //--- trend sleeve: London break+retest (no grid near this)
      if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 10 * 60)
      {
         SBreakRetestParams br;
         br.Reset();
         br.rangeFromMin = 0; br.rangeToMin = 7 * 60;
         br.entryFromMin = 7 * 60; br.entryToMin = 10 * 60;
         br.minRangeAtr = 0.25; br.targetR = 2.0;
         if(!SigBreakRetest(ctx, br, plan)) return false;
         plan.reason = "R5F-LONDONBREAK " + plan.reason;
         return true;
      }

      //--- NY momentum sleeve
      if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 16 * 60)
      {
         if(!SigEmaPullback(ctx, NyParams(), plan)) return false;
         plan.reason = "R5F-NYMOMENTUM " + plan.reason;
         return true;
      }
      return false;
   }

   SEmaPullbackParams NyParams()
   {
      SEmaPullbackParams ep;
      ep.Reset();
      ep.emaPeriod = 20; ep.maxDistanceAtr = 1.50;
      ep.requireTrend = true; ep.targetR = 1.50;
      return ep;
   }

   bool IsGridPair(const string sym)
   {
      return (StringFind(sym, "EURCHF") >= 0 || StringFind(sym, "EURGBP") >= 0 ||
              StringFind(sym, "AUDNZD") >= 0);
   }

   //--- 8-filter gate stack (ADX on H1+H4, band-width rank, channel, news via engine)
   bool GateStack(SEAContext &ctx)
   {
      if(ctx.adxH1 >= 20.0) return false;                     // doc: ADX(14) < 20 on 1H
      if(ctx.adxH4 >= 20.0) return false;                     // doc: ... and on 4H
      if(!BandWidthBottom(ctx)) return false;
      double hi = 0.0, lo = 0.0;
      if(!ChannelBounds(ctx, 50, hi, lo)) return false;
      if(ctx.mid > hi || ctx.mid < lo) return false;
      return true;
   }

   bool BandWidthBottom(SEAContext &ctx)
   {
      if(ctx.atrD1 <= 0.0) return false;
      double av[];
      if(EA_BufN(g_eaInd[ctx.index].hAtrD1, 0, 1, 60, av) < 30) return true;
      double s[];
      ArrayResize(s, ArraySize(av));
      ArrayCopy(s, av);
      ArraySort(s);
      int idx = (int)MathRound(0.25 * (ArraySize(s) - 1));
      return (ctx.atrD1 <= s[idx]);
   }

   bool ChannelBounds(SEAContext &ctx, const int bars, double &hi, double &lo)
   {
      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M15, 1, bars, r) < bars) return false;
      hi = r[0].high; lo = r[0].low;
      for(int i = 1; i < bars; i++) { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }
      return true;
   }

   //--- equal-size ladder, max 8 levels, net +1 spacing target
   bool LadderPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      int legs = EA_CountPositions(ctx.symbol, true);
      if(legs >= InpGridLevels) return false;
      double hi = 0.0, lo = 0.0;
      if(!ChannelBounds(ctx, 50, hi, lo)) return false;
      double mid = 0.5 * (hi + lo);
      int dir = (ctx.mid < mid) ? +1 : -1;
      double spacing = InpGridSpacingAtr * ctx.atr;
      if(spacing <= 0.0) return false;
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
      plan.stop     = (dir > 0) ? avg - 8.0 * spacing : avg + 8.0 * spacing;
      plan.target   = (dir > 0) ? avg + spacing : avg - spacing;
      plan.score    = 45.0;
      plan.isLimit  = true;
      plan.expiry   = TimeTradeServer() + (datetime)(30 * 60);
      plan.reason   = StringFormat("level %d", legs + 1);
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

   //--- kill tripwire: 1 ATR beyond the channel disables the grid for 24h
   void Manage(SEAContext &ctx)
   {
      if(!IsGridPair(ctx.symbol)) return;
      if(EA_CountPositions(ctx.symbol, true) == 0) return;
      double hi = 0.0, lo = 0.0;
      if(!ChannelBounds(ctx, 50, hi, lo)) return;
      if(ctx.atr > 0.0 && (ctx.mid > hi + ctx.atr || ctx.mid < lo - ctx.atr))
         g_eaExec.CloseAll("grid kill tripwire");
      if(ctx.clockMinutes >= 7 * 60) g_eaExec.CloseAll("pre-London flat");
   }
};

CRound5F g_Round5F;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round5F);
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
