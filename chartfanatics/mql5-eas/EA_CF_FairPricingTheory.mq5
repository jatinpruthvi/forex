//+------------------------------------------------------------------+
//|                                  EA_CF_FairPricingTheory.mq5     |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| ChartFanatics: "STEAL The 1-Minute Strategy That Made Him $1.8M+" |
//|                  (JJ Simon, Fair Pricing Theory)                  |
//| Card    : chartfanatics/todos/fair-pricing-theory-strategy.md     |
//|           (#09)                                                  |
//| Source  : chartfanatics/glimpse/-kGVL93XfyE.md (video, no PDF)    |
//| Magic   : 3213                                                   |
//|                                                                  |
//| "Fair pricing theory focuses only on external factors - news and  |
//|  session opens - that create initial UNFAIR price moves, then     |
//|  trades reversions back to the fair price."                       |
//|                                                                  |
//| Pure price action on the 1-minute chart, with three signals:      |
//|   1. DISPLACEMENT - a candle whose body is larger than the        |
//|      previous one and which closes beyond the previous wick.      |
//|      The open's displacement is traded as continuation.           |
//|   2. BREAK OF STRUCTURE - a wick lower (higher) than the two      |
//|      adjacent candles, then broken: continuation in that direction.|
//|   3. REVERSION - after an unfair displacement away from the fair  |
//|      price (previous close / session open), trade the snap-back   |
//|      to it once the push stops extending.                         |
//|                                                                  |
//| Money management is the part the source is emphatic about:        |
//|   * STATIC risk-to-reward: 1:1 or 1:1.5 for evaluations, 1:4+ for |
//|     funded accounts (InpRewardRatio), never a structure-chasing TP;|
//|   * "optimize take profit FIRST, stop loss second": the TP is the  |
//|     distance to fair price; the stop is its static reciprocal      |
//|     (TP / ratio), i.e. mathematically paired, not structural;      |
//|   * the THREE-LOSS RULE ends the session - three consecutive       |
//|     reversion losses mean the market is trending and fair price    |
//|     has moved;                                                   |
//|   * trade only the first 90 minutes of the session opens:          |
//|     NY 09:30-11:00 ET, the Asia open, and NY PM 14:00-15:30 ET -   |
//|     the dead zone between 11:00 and 14:00 is skipped.              |
//|                                                                  |
//| `[interpretation]`: scheduled news reversions (the A+ setup) need  |
//| an economic calendar the engine cannot read tick-for-tick, so the  |
//| session-open reversion stands in for the same mechanic - an unfair  |
//| displacement away from fair price snapping back to it.  See        |
//| mql5-eas/README.md.                                               |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics Fair Pricing Theory - 1-minute displacement, BOS and session-open reversions with static R:R"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade   = "US100";              // NASDAQ futures per the source
input ulong             InpMagicNumber      = 3213;                 // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct          = 0.50;                 // Risk per trade (% of equity)
input int               InpStage             = 5;                   // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input double            InpMaxSpreadPoints  = 3.0;                  // Spread gate in points (0 = off)
input double            InpDailyLossPct     = 1.50;                 // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset  = 2;                    // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;        // Log verbosity
input double            InpCommissionPerLotRT = 0.0;                // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.12;               // Cost gate: (spread + commission) <= xR (1-minute ATR is small)
input bool              InpLedger             = true;               // Write the engine evidence ledger CSV
//--- the static ratio ("1:1 or 1:1.5 for evaluations; 1:4 or higher for funded accounts")
input double InpRewardRatio   = 1.50;   // TP : SL ratio; the stop is the reciprocal of the TP
input double InpMinTpAtr      = 0.60;   // TP-first: skip when fair price is closer than this (no room to pay)
input double InpMaxTpAtr      = 6.00;   // ... and when it is absurdly far (fair price has moved)
//--- the three signals
input bool   InpUseDisplacement = true; // Signal 1: displacement candle continuation
input bool   InpUseBreakOfStructure = true; // Signal 2: wick swing broken -> continuation
input bool   InpUseReversion    = true; // Signal 3: unfair displacement -> reversion to fair price
input double InpBodyMult        = 1.10; // "body larger than previous": ratio of body sizes
input double InpUnfairAtr       = 0.80; // Displacement away from fair price that counts as unfair
input int    InpReversionBars   = 3;    // Bars the unfair push must stop extending before the reversion entry
//--- the three 90-minute session windows (London clock; ET = London - 5 in winter)
input int    InpNyAmFromMin     = 870;  // 14:30 London = 09:30 ET
input int    InpNyAmToMin       = 960;  // 16:00 London = 11:00 ET
input int    InpAsiaFromMin     = 60;   // 01:00 London (the Asia open)
input int    InpAsiaToMin       = 150;  // 02:30 London
input int    InpNyPmFromMin     = 1140; // 19:00 London = 14:00 ET
input int    InpNyPmToMin       = 1230; // 20:30 London = 15:30 ET
input bool   InpUseAsia         = true; // the source lists the Asia open as one of the three windows

//+------------------------------------------------------------------+
class CCfFairPricingTheory : public CEAStrategy
{
public:
   void OnInitStrategy()
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("5-stage policy: stage %d active (risk %.3f%%, %d trades/day max)",
             InpStage, g_eaCfg.riskPct, g_eaCfg.maxTradesPerDay), true);
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "fair pricing armed: static 1:%.2f (TP first, stop = TP/ratio), three-loss rule, 90-minute session windows",
             InpRewardRatio), true);
   }

   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_FAIR_PRICING_THEORY";
      cfg.sourceDoc             = "chartfanatics/glimpse/-kGVL93XfyE.md (card #09)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M1;      // the source is explicit: the 1-minute chart
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = 3.0;
      cfg.totalDdPct            = 8.0;
      cfg.maxTradesPerDay       = 0;      // no trade cap in the source - the windows and the 3-loss rule pace it
      cfg.dayLockAfterLosses    = 3;      // "if three consecutive reversion trades lose in a session, stop trading"
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 60;
      cfg.sessionStartHour      = 1;   cfg.sessionStartMin = 0;     // spans the three windows
      cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;
      cfg.noTradeAfterHour      = 21;  cfg.noTradeAfterMin = 0;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 21;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = false;    // all three signals are "mechanical" bar-close entries
      cfg.breakEvenAtR          = 0.0;      // the source is static: pairing SL to TP, no break-even talk
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_fair_pricing_ledger.csv";
      cfg.newsFilter            = false;    // the news-reversion reading is documented as an interpretation
      cfg.logLevel              = InpLogLevel;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession || ctx.atr <= 0.0) return false;
      if(!InSessionWindow(ctx)) return false;

      //--- fair price: the previous day's close (the level the source anchors the news and open
      //--- reversions to).  The session-open reversion adds the session's own opening print.
      double fair = PreviousDayClose(ctx.symbol);
      if(fair <= 0.0) return false;

      //--- signal order is the source's: the two continuation structures first, then the reversion
      if(InpUseReversion && Reversion(ctx, fair, plan)) return true;
      if(InpUseDisplacement && Displacement(ctx, plan)) return true;
      if(InpUseBreakOfStructure && BreakOfStructure(ctx, plan)) return true;
      return false;
   }

private:
   //--- the three windows the source names, and nothing outside them
   bool InSessionWindow(const SEAContext &ctx)
   {
      if(EA_InWindow(ctx.nowClock, InpNyAmFromMin / 60, InpNyAmFromMin % 60,
                                     InpNyAmToMin / 60, InpNyAmToMin % 60)) return true;
      if(EA_InWindow(ctx.nowClock, InpNyPmFromMin / 60, InpNyPmFromMin % 60,
                                     InpNyPmToMin / 60, InpNyPmToMin % 60)) return true;
      if(InpUseAsia)
         return EA_InWindow(ctx.nowClock, InpAsiaFromMin / 60, InpAsiaFromMin % 60,
                                        InpAsiaToMin / 60, InpAsiaToMin % 60);
      return false;
   }

   double PreviousDayClose(const string sym)
   {
      MqlRates d[];
      if(EA_Rates(sym, PERIOD_D1, 0, 3, d) < 2) return 0.0;
      return d[1].close;
   }

   //--- TP first, stop second: the take profit is the distance to fair price (a real destination);
   //--- the stop is its static reciprocal.  Both directions are anchored on fair price, which is
   //--- what makes the ratio "essentially random but mathematically paired" - exactly as stated.
   bool BuildStaticPlan(SEAContext &ctx, const int dir, const double fair, SSignalPlan &plan)
   {
      double entry = (dir > 0) ? ctx.ask : ctx.bid;
      if(entry <= 0.0) return false;

      //--- "the take profit is set based on account rules and available points to fair price":
      //--- `fair` is whatever destination the signal calls fair (the day close for signals 1 and 3,
      //--- the measured structure for signal 2), and these bands keep it tradable.
      double tpDist = (dir > 0) ? (fair - entry) : (entry - fair);
      if(tpDist < InpMinTpAtr * ctx.atr) return false;
      if(tpDist > InpMaxTpAtr * ctx.atr) return false;

      double stopDist = tpDist / InpRewardRatio;
      if(stopDist <= 0.0) return false;

      plan.dir      = dir;
      plan.entry    = entry;
      plan.stop     = (dir > 0) ? entry - stopDist : entry + stopDist;
      plan.target   = (dir > 0) ? entry + tpDist   : entry - tpDist;
      plan.riskDist = stopDist;
      plan.barsAgo  = 1;
      plan.isLimit  = false;
      return true;
   }

   //--- SIGNAL 1: displacement candle - body larger than the previous bar's body, closing beyond
   //--- the previous bar's wick.  Traded as continuation in the displacement's direction.
   bool Displacement(SEAContext &ctx, SSignalPlan &plan)
   {
      MqlRates r[];
      if(EA_Rates(ctx.symbol, g_eaIndTf, 0, 6, r) < 4) return false;
      double bodyNow  = MathAbs(r[1].close - r[1].open);
      double bodyPrev = MathAbs(r[2].close - r[2].open);
      if(bodyPrev <= 0.0 || bodyNow < InpBodyMult * bodyPrev) return false;

      int dir = (r[1].close > r[1].open) ? +1 : -1;
      bool closesBeyondWick = (dir > 0) ? (r[1].close > r[2].high) : (r[1].close < r[2].low);
      if(!closesBeyondWick) return false;

      double fair = PreviousDayClose(ctx.symbol);
      if(fair <= 0.0) return false;
      if(!BuildStaticPlan(ctx, dir, fair, plan)) return false;
      plan.score  = 60.0;
      plan.reason = StringFormat("displacement candle (body %.2fx previous) continuation", bodyNow / bodyPrev);
      return true;
   }

   //--- SIGNAL 2: break of structure - a wick beyond both adjacent candles, then broken.  The fair
   //--- price for the static TP is the pre-break extreme extended by the same leg (the structure's
   //--- own measured distance), which is the "available points" the source says to size the TP on.
   bool BreakOfStructure(SEAContext &ctx, SSignalPlan &plan)
   {
      MqlRates r[];
      if(EA_Rates(ctx.symbol, g_eaIndTf, 0, 12, r) < 10) return false;

      for(int dir = +1; dir >= -1; dir -= 2)
      {
         //--- find the most recent wick swing: a bar whose wick exceeds BOTH neighbours
         double swing = 0.0;
         int    swingIdx = -1;
         for(int i = 3; i <= 9; i++)
         {
            bool isSwing = (dir > 0) ? (r[i].low < r[i - 1].low && r[i].low < r[i + 1].low)
                                     : (r[i].high > r[i - 1].high && r[i].high > r[i + 1].high);
            if(isSwing) { swing = (dir > 0) ? r[i].low : r[i].high; swingIdx = i; break; }
         }
         if(swingIdx < 0) continue;

         //--- ... and it must have been BROKEN by a close beyond it, after the swing printed
         double legExtreme = (dir > 0) ? r[swingIdx].low : r[swingIdx].high;
         bool broken = false;
         double furthest = legExtreme;
         for(int i = swingIdx - 1; i >= 1; i--)
         {
            if(dir > 0 && r[i].close < legExtreme) { broken = true; furthest = MathMin(furthest, r[i].low); }
            if(dir < 0 && r[i].close > legExtreme) { broken = true; furthest = MathMax(furthest, r[i].high); }
         }
         if(!broken) continue;

         //--- the structural destination: the broken leg repeated from the break point
         double entry = (dir > 0) ? ctx.ask : ctx.bid;
         double structTp = (dir > 0) ? entry + MathAbs(entry - furthest) : entry - MathAbs(furthest - entry);
         if(!BuildStaticPlan(ctx, dir, structTp, plan)) continue;
         plan.score  = 60.0;
         plan.reason = StringFormat("break of structure: wick %.2f broken, continuation", legExtreme);
         return true;
      }
      return false;
   }

   //--- SIGNAL 3: reversion to fair price.  An unfair displacement away from fair price that stops
   //--- extending is the snap-back trade ("reversions back to that fair price").  For the static
   //--- ratio the TP is the distance back to fair price itself - a real destination.
   bool Reversion(SEAContext &ctx, const double fair, SSignalPlan &plan)
   {
      MqlRates r[];
      if(EA_Rates(ctx.symbol, g_eaIndTf, 0, InpReversionBars + 6, r) < InpReversionBars + 3) return false;

      //--- the unfair push: price stretched away from fair by at least InpUnfairAtr during the
      //--- lookback, and the last InpReversionBars bars stopped making new extremes
      for(int dir = +1; dir >= -1; dir -= 2)         // dir = the snap-back direction
      {
         double stretch = (dir > 0) ? (fair - ctx.mid) : (ctx.mid - fair);
         if(stretch < InpUnfairAtr * ctx.atr) continue;         // not unfair enough to revert

         //--- exhaustion: the last bars must not keep extending away from fair price
         bool stillExtending = false;
         double lastExtreme = (dir > 0) ? r[InpReversionBars].low : r[InpReversionBars].high;
         for(int i = 1; i < InpReversionBars; i++)
         {
            if(dir > 0 && r[i].low < lastExtreme) { stillExtending = true; break; }
            if(dir < 0 && r[i].high > lastExtreme) { stillExtending = true; break; }
         }
         if(stillExtending) continue;

         //--- the reversal bar closes back in the snap-back direction
         if(dir > 0 && !(r[1].close > r[1].open)) continue;
         if(dir < 0 && !(r[1].close < r[1].open)) continue;

         if(!BuildStaticPlan(ctx, dir, fair, plan)) continue;
         plan.score  = 64.0;
         plan.reason = StringFormat("unfair displacement %.2f from fair price %.2f - reversion",
                                    MathAbs(ctx.mid - fair), fair);
         return true;
      }
      return false;
   }
};

CCfFairPricingTheory g_cfFairPricingTheory;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfFairPricingTheory);
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
