//+------------------------------------------------------------------+
//| EA_FINAL_OPTIMUM_STRATEGY.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Final Optimum - per-pair Triad stack (5 pairs) + 55-day gold Donchian
//| Source document : docs/strategy/FINAL_OPTIMUM_STRATEGY.md
//| Tracker entry   : #15  |  Magic: 3101
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CFinalOptimum class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Final Optimum - per-pair Triad stack (5 pairs) + 55-day gold Donchian"
#property description "Source: docs/strategy/FINAL_OPTIMUM_STRATEGY.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "XAUUSD,AUDUSD,EURJPY,GBPJPY,USDJPY";      // Comma separated universe
input double          InpRiskPct          = 1.75;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 25;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 4.5;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 10;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 10;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 2;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 3101; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpGoldRiskPct       = 3.00;  // Gold Donchian leg: 3% of current balance
input int    InpDonchianDays      = 55;    // Channel: 55 D1 bars ending the day before yesterday
input double InpGoldStopAtr       = 2.50;  // Gold stop and chandelier k (2.5 x ATR14)
input double InpGoldAtrPeriod     = 14;    // Gold ATR: 14 daily (high - low) bars
input int    InpGoldEntryWindowMin= 60;    // Gold fills inside the first hour of the London day
input bool   InpTradeGold         = true;  // Enable the XAUUSD Donchian leg
input int    InpMaxTradesPerDayX  = 2;     // Max two trades/day across both legs
input double InpQualifyingDayCash = 12.50; // 0.5% of $2,500: phase qualifying day

//+------------------------------------------------------------------+
//| Strategy: Final Optimum - per-pair Triad stack (5 pairs) + 55-day gold Donchian
//+------------------------------------------------------------------+
class CFinalOptimum : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName         = "FINAL_OPTIMUM";
      cfg.sourceDoc            = "docs/strategy/FINAL_OPTIMUM_STRATEGY.md";
      cfg.symbols              = InpSymbolsToTrade;
      cfg.magic                = InpMagicNumber;
      cfg.riskPct              = 1.75;                 // triad risk fraction (% of current balance)
      cfg.riskBaseBalance      = true;                 // risk fraction x current balance (doc 3.5)
      cfg.signalTimeframe      = PERIOD_M5;
      cfg.clock                = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset= InpServerGmtOffset;
      cfg.serverFollowsEuDst   = true;
      cfg.maxSpreadPoints      = InpMaxSpreadPoints;
      cfg.commissionPerLotRT   = 7.00;                 // $7/lot round turn (doc 6)
      cfg.maxCostR             = 0.10;                 // (spread + commission) <= 10% of R
      cfg.dailyLossPct         = InpDailyLossPct;      // 4.5% internal buffer under the 5% rule
      cfg.totalDdPct           = InpTotalDdPct;        // $2,250 permanent floor
      cfg.profitTargetPct      = InpProfitTargetPct;   // $2,750 phase-1 target
      cfg.maxTradesPerDay      = InpMaxTradesPerDayX;  // max two trades/day across both legs
      cfg.maxOpenPositions     = 1;                    // one shared slot; the gold leg holds it
      cfg.sessionStartHour     = 0;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour       = 0;   cfg.sessionEndMin   = 0;   // 24h: gold is a multi-day swing
      cfg.sessionEndFlat       = false;                // per-leg flat enforced in Manage()
      cfg.fridayFlat           = false;                // gold holds through the weekend (doc 4)
      cfg.signalOnNewBarOnly   = true;
      cfg.useLimitEntry        = true;
      cfg.pendingExpiryMinutes = 60;                   // dropped if never re-touched
      cfg.breakEvenAtR         = 0.0;                  // no BE rule in the champion
      cfg.timeStopMinutes      = 0;                    // per-pair time stop lives in Manage()
      cfg.minSecondsBetweenTrades = 120;
      cfg.qualifyingDayAmount  = InpQualifyingDayCash; // any three 0.5% days per phase
      cfg.qualifyingDaysTarget = 3;
      cfg.logLevel             = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- Leg B first: gold acts first at the open and holds the only slot (doc 5)
      if(ctx.symbol == "XAUUSD" && InpTradeGold)
      {
         if(GoldLegPlan(ctx, plan)) { plan.reason = "GOLD " + plan.reason; return true; }
      }
      return TriadPlan(ctx, plan);
   }

   //--- per-pair overrides (doc 3.1)
   int    PairSessionEnd(const string sym)
   {
      if(sym == "EURJPY" || sym == "USDJPY" || sym == "XAUUSD") return 13 * 60 + 30;
      return 11 * 60;
   }
   double PairSweepMinAtr(const string sym)  { return (sym == "GBPJPY") ? 0.01 : 0.02; }
   double PairStopBufferAtr(const string sym)
   {
      if(sym == "EURJPY" || sym == "XAUUSD") return 0.05;
      return 0.10;
   }
   double PairTargetR(const string sym)      { return (sym == "AUDUSD") ? 2.5 : 1.5; }

   //--- Leg A: the doc 3.3 pattern (sweep, reclaim, displacement), one signal
   //--- per pair per day, BUY/SELL LIMIT at the displacement body midpoint
   bool TriadPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      if(ctx.atr <= 0.0) return false;
      int sessionEnd = PairSessionEnd(ctx.symbol);
      if(ctx.clockMinutes < 7 * 60 || ctx.clockMinutes >= sessionEnd) return false;
      if(ctx.symbol == "XAUUSD" && ctx.clockMinutes > 10 * 60) return false;   // no-late cutoff

      //--- reference range: M5 bars [00:00, 07:00) London, at least 12 bars
      double rHi = 0.0, rLo = 0.0;
      int    rangeBars = 0;
      if(!SigRangeForDay(ctx.symbol, PERIOD_M5, 0, 7 * 60, 0, rHi, rLo, rangeBars)) return false;
      if(rHi <= rLo || rangeBars < 12) return false;

      int lookback = (ctx.clockMinutes - 7 * 60) / 5 + 4;
      if(lookback > 300) lookback = 300;
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, PERIOD_M5, 1, lookback, r);
      if(got < 4) return false;

      double sweepMin = PairSweepMinAtr(ctx.symbol) * ctx.atr;
      double sweepMax = 0.50 * ctx.atr;

      for(int k = got - 1; k >= 3; k--)                    // oldest session bar first
      {
         MqlRates sw = r[k];
         bool sweptLow  = (sw.low  < rLo - sweepMin);
         bool sweptHigh = (sw.high > rHi + sweepMin);
         if(sweptLow && sweptHigh) return false;           // two-sided sweep consumes the day
         bool isLong = sweptLow;
         if(!isLong && !sweptHigh) continue;

         double extreme = isLong ? sw.low : sw.high;
         if(MathAbs(extreme - (isLong ? rLo : rHi)) > sweepMax) return false;   // abort day

         for(int c = 0; c <= 2; c++)                        // reclaim within the next two bars
         {
            int ri = k - c;
            if(ri < 1) continue;
            MqlRates re = r[ri];
            if(isLong)
            {
               if(re.high > rHi + sweepMin) return false;              // opposite sweep: day consumed
               if(re.low < extreme) extreme = re.low;                  // new extreme low
               if(MathAbs(extreme - rLo) > sweepMax) return false;
               if(!(re.close > rLo && re.close < rHi)) continue;       // close back inside
               if(EA_WickRatio(re, +1) < 0.45) continue;               // sellers' wick
            }
            else
            {
               if(re.low < rLo - sweepMin) return false;
               if(re.high > extreme) extreme = re.high;
               if(MathAbs(extreme - rHi) > sweepMax) return false;
               if(!(re.close > rLo && re.close < rHi)) continue;
               if(EA_WickRatio(re, -1) < 0.45) continue;
            }

            int di = ri - 1;                                // displacement: bar right after reclaim
            if(di < 1) continue;
            MqlRates disp = r[di];
            double body = EA_BodyRatio(disp);
            if(body < 0.50) continue;
            if(isLong  && !(disp.close > disp.open && disp.close > (re.open + re.close) / 2.0)) continue;
            if(!isLong && !(disp.close < disp.open && disp.close < (re.open + re.close) / 2.0)) continue;

            double entry = (disp.open + disp.close) / 2.0;
            double stop  = isLong ? extreme - PairStopBufferAtr(ctx.symbol) * ctx.atr
                                  : extreme + PairStopBufferAtr(ctx.symbol) * ctx.atr;
            double risk  = isLong ? entry - stop : stop - entry;
            if(risk <= 0.0) continue;
            if(risk < 0.60 * ctx.atr || risk > 1.50 * ctx.atr) return false;   // 0.60-1.50 ATR band
            if(risk < 2.0 * EA_PipSize(ctx.symbol)) return false;              // at least 2 pips

            int digits = (int)SymbolInfoInteger(ctx.symbol, SYMBOL_DIGITS);
            plan.Reset();
            plan.dir      = isLong ? +1 : -1;
            plan.entry    = NormalizeDouble(entry, digits);
            plan.stop     = stop;
            plan.riskDist = risk;
            plan.target   = isLong ? entry + PairTargetR(ctx.symbol) * risk
                                   : entry - PairTargetR(ctx.symbol) * risk;
            plan.score    = 70.0;
            plan.isLimit  = true;                           // BUY/SELL LIMIT at the body midpoint
            plan.expiry   = TimeTradeServer() + (datetime)(g_eaCfg.pendingExpiryMinutes * 60);
            plan.reason   = StringFormat("TRIAD-%s sweep %.2f ATR, disp body %.2f", ctx.symbol,
                                         MathAbs(extreme - (isLong ? rLo : rHi)) / ctx.atr, body);
            return true;
         }
      }
      return false;
   }

   //--- Leg B: gold Donchian swing (doc 4): 55 days ending the day before
   //--- yesterday, signal on yesterday's close beyond the channel, fill at the
   //--- open window, stop and chandelier = 2.5 x ATR14, no fixed target
   bool GoldLegPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      if(ctx.clockMinutes > InpGoldEntryWindowMin) return false;
      MqlRates r[];
      int need = InpDonchianDays + (int)InpGoldAtrPeriod + 1;
      if(EA_Rates(ctx.symbol, PERIOD_D1, 1, need, r) < need) return false;
      double atr14 = GoldAtr(r);
      if(atr14 <= 0.0) return false;

      double h = -1e18, l = 1e18;
      for(int i = 1; i <= InpDonchianDays; i++)                     // channel = d-1 .. d-55
      {
         if(r[i].high > h) h = r[i].high;
         if(r[i].low  < l) l = r[i].low;
      }
      int dir = 0;
      if(r[0].close > h)      dir = +1;                             // yesterday's close broke out
      else if(r[0].close < l) dir = -1;
      if(dir == 0) return false;

      double entry = (dir > 0) ? ctx.ask : ctx.bid;
      double stop  = (dir > 0) ? entry - InpGoldStopAtr * atr14 : entry + InpGoldStopAtr * atr14;
      double risk  = MathAbs(entry - stop);
      if(risk <= 0.0) return false;
      plan.Reset();
      plan.dir      = dir;
      plan.entry    = entry;
      plan.stop     = stop;
      plan.riskDist = risk;
      plan.target   = 0.0;                                          // chandelier: no fixed target
      plan.score    = 80.0;
      plan.reason   = StringFormat("GOLD-DONCHIAN(%d) close %.2f vs %s %.2f", InpDonchianDays,
                                   r[0].close, dir > 0 ? "high" : "low", dir > 0 ? h : l);
      return true;
   }

   //--- ATR14 = mean of the last 14 daily (high - low) bars ending yesterday
   double GoldAtr(MqlRates &r[])
   {
      int n = (int)InpGoldAtrPeriod;
      if(ArraySize(r) < n) return 0.0;
      double sum = 0.0;
      for(int i = 0; i < n; i++) sum += (r[i].high - r[i].low);
      return (n > 0) ? sum / n : 0.0;
   }

   //--- per-pair time stop and flat-by for the intraday leg
   void Manage(SEAContext &ctx)
   {
      if(ctx.symbol == "XAUUSD") { GoldManage(ctx); return; }
      for(int t = g_eaTrackCount - 1; t >= 0; t--)
      {
         if(g_eaTrack[t].symbol != ctx.symbol) continue;
         if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;

         datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
         double limitMin = (ctx.symbol == "EURJPY") ? 120.0 : 90.0;
         int    minutesOpen = (int)((TimeTradeServer() - opened) / 60);
         if(minutesOpen >= limitMin)
         {
            g_eaExec.Close(g_eaTrack[t].ticket, "per-pair time stop");
            continue;
         }
         if(ctx.clockMinutes >= PairSessionEnd(ctx.symbol))
         {
            g_eaExec.CancelPending(ctx.symbol, "session end - drop unfilled");
            g_eaExec.Close(g_eaTrack[t].ticket, "flat by pair session end");
         }
      }
   }

   //--- gold: opposite-channel exit plus the 2.5 x ATR chandelier, evaluated on
   //--- completed daily closes (no intra-day stop chasing, doc 4)
   void GoldManage(SEAContext &ctx)
   {
      MqlRates r[];
      int need = InpDonchianDays + (int)InpGoldAtrPeriod + 2;
      if(EA_Rates(ctx.symbol, PERIOD_D1, 1, need, r) < need) return;
      double atr14 = GoldAtr(r);
      if(atr14 <= 0.0) return;

      double h = -1e18, l = 1e18;
      for(int i = 1; i <= InpDonchianDays; i++)
      {
         if(r[i].high > h) h = r[i].high;
         if(r[i].low  < l) l = r[i].low;
      }

      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong tk = PositionGetTicket(p);
         if(tk == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;

         bool   isBuy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         double sl     = PositionGetDouble(POSITION_SL);
         datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
         bool   exitCh = isBuy ? (r[1].close < l) : (r[1].close > h);

         double extreme = PositionGetDouble(POSITION_PRICE_OPEN);
         for(int i = 0; i < ArraySize(r); i++)
         {
            if(r[i].time < opened) break;
            extreme = isBuy ? MathMax(extreme, r[i].close) : MathMin(extreme, r[i].close);
         }
         double trail = isBuy ? extreme - InpGoldStopAtr * atr14 : extreme + InpGoldStopAtr * atr14;
         if(exitCh) { g_eaExec.Close(tk, "gold opposite-channel exit"); continue; }
         if((isBuy && trail > sl) || (!isBuy && (sl <= 0.0 || trail < sl)))
            g_eaExec.Modify(tk, NormalizeDouble(trail, (int)SymbolInfoInteger(ctx.symbol, SYMBOL_DIGITS)), 0.0);
      }
   }
};

CFinalOptimum g_FinalOptimum;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_FinalOptimum);
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
