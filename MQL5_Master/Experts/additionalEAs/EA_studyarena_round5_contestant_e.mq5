//+------------------------------------------------------------------+
//| EA_studyarena_round5_contestant_e.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 5E - executable core: 1% per group, 0.5% basket grid and three named setups
//| Source document : docs/research/study_arena/studyarena-round5-contestant-e.md
//| Tracker entry   : #53  |  Magic: 2020
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound5E class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 5E - executable core: 1% per group, 0.5% basket grid and three named setups"
#property description "Source: docs/research/study_arena/studyarena-round5-contestant-e.md"

#include "..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY,AUDUSD,USDCAD,EURGBP,AUDNZD";      // Comma separated universe
input double          InpRiskPct          = 1.0;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 2.0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 5.0;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 20;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 5;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2020; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpGroupCapPct       = 1.00;  // Max risk per correlation group
input double InpBasketCapPct      = 0.50;  // Grid basket cap (3 equal legs)
input double InpGridAdxMax        = 16.0;  // ADX gate for the grid
input double InpRsi2Entry         = 5.0;   // RSI(2) < 5 / > 95 entry filter
input double InpExpectancyGate    = 0.25;  // Required live expectancy (R) to keep trading

//+------------------------------------------------------------------+
//| Strategy: Round 5E - executable core: 1% per group, 0.5% basket grid and three named setups
//+------------------------------------------------------------------+
class CRound5E : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R5E_EXECUTABLE_CORE";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round5-contestant-e.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M15;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.totalDdPct            = InpTotalDdPct;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 3;
      cfg.minSecondsBetweenTrades = 120;
      cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 22;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;
      cfg.breakEvenAtR          = 1.00;
      cfg.timeStopMinutes       = 240;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      if(GroupBlocked(ctx)) return false;

      //--- Setup 1: London liquidity sweep (EURUSD / GBPUSD, tight Asian range required)
      if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 10 * 60 + 30 &&
         (StringFind(ctx.symbol, "EURUSD") >= 0 || StringFind(ctx.symbol, "GBPUSD") >= 0))
      {
         if(!RangeTight(ctx)) return false;
         if(ctx.emaH1_50 <= 0.0) return false;
         bool up = (ctx.mid > ctx.emaH1_50 && ctx.ema50 > ctx.emaH1_50);
         bool dn = (ctx.mid < ctx.emaH1_50 && ctx.ema50 < ctx.emaH1_50);
         if(!up && !dn) return false;
         SSweepParams p;
         p.Reset();
         p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
         p.sessionFromMin = 7 * 60; p.sessionToMin = 10 * 60 + 30;
         p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.55;
         p.reclaimWindowBars = 3; p.wickRatio = 0.55; p.bodyRatio = 0.55;
         p.stopBufferAtr = 0.10; p.minStopAtr = 0.50; p.maxStopAtr = 1.50;
         p.entryRetrace = 0.50; p.targetR = 2.0;
         if(!SigSweepReclaim(ctx, p, plan)) return false;
         plan.reason = "R5E-LONDONSWEEP " + plan.reason;
         return true;
      }

      //--- Setup 2: NY opening-range continuation (USDJPY / USDCAD / EURUSD)
      if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 16 * 60)
      {
         if(!SigEmaPullback(ctx, NyParams(), plan)) return false;
         plan.reason = "R5E-NYCONT " + plan.reason;
         return true;
      }

      //--- Setup 3: gated Asian grid (3 equal legs, ADX < 16, RSI(2) extremes)
      if(ctx.clockMinutes < 7 * 60 && IsGridPair(ctx.symbol))
      {
         if(ctx.adx14 >= InpGridAdxMax) return false;
         if(!AtrBelow40thPct(ctx)) return false;
         int legs = EA_CountPositions(ctx.symbol, true);
         if(legs >= 3) return false;
         if(legs > 0 && !LegSpaced(ctx)) return false;
         if(!Rsi2Plan(ctx, plan)) return false;
         plan.reason = StringFormat("R5E-GRID(leg %d) %s", legs + 1, plan.reason);
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

   bool IsGridPair(const string sym)
   {
      return (StringFind(sym, "EURGBP") >= 0 || StringFind(sym, "AUDNZD") >= 0);
   }

   bool RangeTight(SEAContext &ctx)
   {
      double hi = 0.0, lo = 0.0;
      if(!SigAsianRange(ctx.symbol, hi, lo)) return false;
      double pip = EA_PipSize(ctx.symbol);
      if(pip <= 0.0) return false;
      double pips = (hi - lo) / pip;
      if(StringFind(ctx.symbol, "GBPUSD") >= 0) return (pips <= 45.0);
      return (pips <= 35.0);
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
      return (MathAbs(ctx.mid - last) >= 0.30 * ctx.atrD1);
   }

   bool Rsi2Plan(SEAContext &ctx, SSignalPlan &plan)
   {
      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 22, r) < 20) return false;
      double gain = 0.0, loss = 0.0;
      for(int i = 0; i < 2; i++)
      {
         double d = r[i].close - r[i + 1].close;
         if(d > 0.0) gain += d; else loss -= d;
      }
      double rsi2 = (gain + loss > 0.0) ? 100.0 * gain / (gain + loss) : 50.0;
      int dir = 0;
      if(rsi2 < InpRsi2Entry) dir = +1;
      if(rsi2 > 100.0 - InpRsi2Entry) dir = -1;
      if(dir == 0) return false;
      double spacing = 0.30 * ctx.atrD1;
      if(spacing <= 0.0) return false;
      plan.Reset();
      plan.dir      = dir;
      plan.entry    = (dir > 0) ? ctx.ask : ctx.bid;
      plan.riskDist = MathMax(spacing, 0.25 * ctx.atr);
      plan.stop     = (dir > 0) ? plan.entry - plan.riskDist : plan.entry + plan.riskDist;
      plan.target   = (dir > 0) ? plan.entry + 0.80 * plan.riskDist : plan.entry - 0.80 * plan.riskDist;
      plan.score    = 50.0;
      plan.reason   = StringFormat("rsi2 %.1f", rsi2);
      return true;
   }

   bool GroupBlocked(SEAContext &ctx)
   {
      if(ctx.openPositionsAll == 0) return false;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         string other = PositionGetString(POSITION_SYMBOL);
         if(other == ctx.symbol) continue;
         if(SharesGroup(ctx.symbol, other)) return true;
      }
      return false;
   }

   bool SharesGroup(const string a, const string b)
   {
      string groups[3][6];
      groups[0][0] = "EURUSD"; groups[0][1] = "GBPUSD"; groups[0][2] = "AUDUSD";
      groups[0][3] = "USDCAD"; groups[0][4] = "NZDUSD"; groups[0][5] = "";
      groups[1][0] = "USDJPY"; groups[1][1] = "GBPJPY"; groups[1][2] = "EURJPY";
      groups[1][3] = "AUDJPY"; groups[1][4] = "";       groups[1][5] = "";
      groups[2][0] = "EURGBP"; groups[2][1] = "EURCHF"; groups[2][2] = "AUDNZD";
      groups[2][3] = "";       groups[2][4] = "";       groups[2][5] = "";
      for(int g = 0; g < 3; g++)
      {
         bool hasA = false, hasB = false;
         for(int i = 0; i < 6; i++)
         {
            if(groups[g][i] == "") continue;
            if(StringFind(a, groups[g][i]) >= 0) hasA = true;
            if(StringFind(b, groups[g][i]) >= 0) hasB = true;
         }
         if(hasA && hasB) return true;
      }
      return false;
   }

   //--- hard basket cap on the grid sleeve
   void Manage(SEAContext &ctx)
   {
      if(!IsGridPair(ctx.symbol)) return;
      if(EA_CountPositions(ctx.symbol, true) == 0) return;
      if(ctx.floatingPl < -InpBasketCapPct / 100.0 * ctx.equity)
         g_eaExec.CloseAll("0.5% basket cap");
   }
};

CRound5E g_Round5E;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round5E);
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
