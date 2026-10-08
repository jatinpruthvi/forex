//+------------------------------------------------------------------+
//|                                            EA_CF_AuctionMarket.mq5|
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| ChartFanatics playbook: Auction Market (Fabio Valentini)         |
//| Card    : chartfanatics/todos/auction-market-strategy.md  (#05)   |
//| Source  : chartfanatics/pdf/auction-market-strategy.pdf           |
//| Magic   : 3210                                                   |
//|                                                                  |
//| "Market State -> Location -> Aggression.  When these three        |
//|  align, you have a trade.  If even one is missing, you stay flat."|
//|                                                                  |
//| Two complementary setups, selected by the market state:           |
//|                                                                  |
//|  TREND MODEL (out of balance, seeking new value)                  |
//|    1. State  : displacement away from prior value, momentum       |
//|    2. Location: the impulse leg's LOW-VOLUME NODES (LVNs)         |
//|    3. Trigger : aggression in the trend direction at the LVN      |
//|    4. Risk    : stop just beyond the aggressive print (+ buffer), |
//|                 early break-even, 0.25-0.5% risk per trade        |
//|    5. Target  : the previous balance POC, full exit               |
//|    Works best in the New York session; the London open is avoided.|
//|                                                                  |
//|  MEAN REVERSION MODEL (failed auction outside value -> back in)   |
//|    1. State  : market in balance (previous day's profile is the   |
//|                 balance reference)                                |
//|    2. Watch for a push out of balance that FAILS                  |
//|    3. Wait for a reclaim inside balance, then the pullback into   |
//|       the reclaim leg's LVN ("do not take the first move back")   |
//|    4. Risk    : stop beyond the aggressive print, never widened   |
//|    5. Target  : the balance POC, full exit                        |
//|    Works best in the London session / compressed conditions.      |
//|                                                                  |
//| "No aggression = no trade": every entry needs an aggressive body  |
//| AND above-average volume (the EA's proxy for the big prints the   |
//| playbook reads in a footprint chart - the engine has no order-    |
//| flow feed).  `[interpretation]` marks this and the other proxies  |
//| listed in mql5-eas/README.md.                                     |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics Auction Market - balance/imbalance, volume-profile LVNs, aggression confirmation"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade   = "US100,US500,GER40";  // Futures per the playbook (NASDAQ, ES)
input ulong             InpMagicNumber      = 3210;                 // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct          = 0.40;                 // "keep risk small, 0.25% to 0.5% of the account per trade"
input int               InpStage             = 5;                   // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input double            InpMaxSpreadPoints  = 3.0;                  // Spread gate in points (0 = off)
input double            InpDailyLossPct     = 1.50;                 // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset  = 2;                    // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;        // Log verbosity
input double            InpCommissionPerLotRT = 0.0;                // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.12;               // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;               // Write the engine evidence ledger CSV
//--- market state (step 1)
input double InpImbalanceAtr   = 1.00;  // Distance from the prior POC (in ATR) that counts as "out of balance"
input double InpMinAdx         = 20.0;  // ... plus momentum: ADX(14) floor for the out-of-balance state
//--- location (step 2): the volume profile
input int    InpProfileBins    = 40;    // Price bins in the tick-volume profile
input double InpValueAreaPct   = 0.70;  // Value area share (70% is the standard AMT convention - [interpretation])
//--- aggression (step 3)
input double InpAggressionBody = 0.50;  // Body ratio the trigger candle must show in the trade direction
input double InpAggressionVol  = 1.20;  // Trigger volume vs its own 20-bar average ("big prints")
//--- risk (step 4) and target (step 5)
input double InpStopBufferAtr  = 0.10;  // Beyond the aggressive print, plus 2 ticks (see StopFor)
input int    InpStopBufferTicks= 2;     // "add a 1-2 tick buffer before the obvious swing high/low"
input double InpMinStopAtr     = 0.15;  // Reject stops tighter than this
input double InpMinRR          = 1.00;  // [interpretation] POC target must at least cover risk
//--- windows (London clock; New York = London - 5 in winter)
input bool   InpTradeTrend     = true;  // Trend model switched on
input bool   InpTradeRevert    = true;  // Mean-reversion model switched on
input int    InpNyFromMin      = 870;   // 14:30 London = 09:30 ET - the trend model's session
input int    InpNyToMin        = 1140;  // 19:00 London = 14:00 ET
input int    InpLdnFromMin     = 480;   // 08:00 London - the mean-reversion model's session
input int    InpLdnToMin       = 690;   // 11:30 London
input int    InpLegBars        = 24;    // Impulse / reclaim leg length
input int    InpFailLookback   = 12;    // Bars a failed auction may have printed in

//+------------------------------------------------------------------+
struct SVolProfile
{
   double poc, val, vah;
   bool   ok;
};

//+------------------------------------------------------------------+
class CCfAuctionMarket : public CEAStrategy
{
public:
   void OnInitStrategy()
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("5-stage policy: stage %d active (risk %.3f%%, %d trades/day max)",
             InpStage, g_eaCfg.riskPct, g_eaCfg.maxTradesPerDay), true);
      EA_Log(EA_LOG_EVENTS, "auction market armed: state -> LVN -> aggression; no aggression = no trade", true);
   }

   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_AUCTION_MARKET";
      cfg.sourceDoc             = "chartfanatics/pdf/auction-market-strategy.pdf (card #05)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;      // [interpretation] order-flow scalping implies sub-minute data;
                                                  // M5 is the lowest timeframe with a meaningful profile from bars
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = 3.0;
      cfg.totalDdPct            = 8.0;
      cfg.maxTradesPerDay       = 4;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 180;
      cfg.sessionStartHour      = 8;   cfg.sessionStartMin  = 0;    // covers both model windows
      cfg.sessionEndHour        = 19;  cfg.sessionEndMin    = 0;
      cfg.noTradeAfterHour      = 19;  cfg.noTradeAfterMin  = 0;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 17;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = false;   // "don't place blind limit orders" - enter on the aggression bar
      //--- "if CVD shows strong pressure, move the stop to break-even early": without an order-flow feed the
      //--- engine's 1R break-even stands in, and the trail keeps the strong trend day variant alive.
      cfg.breakEvenAtR          = 1.0;
      cfg.trailAtR              = 1.5;  cfg.trailDistanceR = 0.75;
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_auction_market_ledger.csv";
      cfg.newsFilter            = false;
      cfg.logLevel              = InpLogLevel;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession || ctx.atr <= 0.0) return false;

      //--- step 1: market state against the PREVIOUS day's balance (the profile reference the
      //--- playbook names for the mean-reversion model)
      SVolProfile prev;
      if(!BuildProfile(ctx.symbol, 1, 288, prev)) return false;      // ~1 day of M5 bars
      bool outOfBalance = (MathAbs(ctx.mid - prev.poc) > InpImbalanceAtr * ctx.atr) &&
                          (ctx.adx14 >= InpMinAdx);
      bool inNy    = EA_InWindow(ctx.nowClock, InpNyFromMin / 60, InpNyFromMin % 60,
                                                InpNyToMin / 60,   InpNyToMin % 60);
      bool inLdn   = EA_InWindow(ctx.nowClock, InpLdnFromMin / 60, InpLdnFromMin % 60,
                                                InpLdnToMin / 60,   InpLdnToMin % 60);

      //--- step 2-3: the setups.  State chooses the model, exactly like the playbook's split.
      if(InpTradeTrend && outOfBalance && inNy && TrendModel(ctx, prev, plan)) return true;
      if(InpTradeRevert && !outOfBalance && inLdn && MeanReversionModel(ctx, prev, plan)) return true;
      return false;
   }

private:
   //--- aggression proxy: a body in `dir` plus above-average volume.  The playbook reads big
   //--- prints / footprint imbalance; the engine has bars only, so volume-vs-average stands in.
   bool AggressiveBar(const SEAContext &ctx, const int dir, const double bodyMin)
   {
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, 24, r);
      if(got < 21) return false;
      if(EA_BodyRatio(r[1]) < bodyMin) return false;
      if(dir > 0 && !(r[1].close > r[1].open)) return false;
      if(dir < 0 && !(r[1].close < r[1].open)) return false;
      double avg = 0.0;
      for(int i = 2; i <= 21; i++) avg += (double)r[i].tick_volume;
      avg /= 20.0;
      if(avg <= 0.0) return false;
      return ((double)r[1].tick_volume >= InpAggressionVol * avg);
   }

   //--- the stop the playbook describes: just beyond the aggressive print, 1-2 ticks before the
   //--- obvious swing extreme so slippage does not clip it.
   double StopFor(const SEAContext &ctx, const int dir, const double printExtreme)
   {
      double tick = SymbolInfoDouble(ctx.symbol, SYMBOL_TRADE_TICK_SIZE);
      double buffer = MathMax((double)InpStopBufferTicks * tick, InpStopBufferAtr * ctx.atr);
      return (dir > 0) ? printExtreme - buffer : printExtreme + buffer;
   }

   //--- TREND MODEL: the impulse leg's LVN is the location; aggression at it is the trigger.
   bool TrendModel(SEAContext &ctx, const SVolProfile &prev, SSignalPlan &plan)
   {
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, InpLegBars + 4, r);
      if(got < InpLegBars + 1) return false;

      for(int dir = +1; dir >= -1; dir -= 2)
      {
         //--- the impulse: price displaced in `dir` from the prior POC
         if(dir > 0 && !(ctx.mid > prev.poc)) continue;
         if(dir < 0 && !(ctx.mid < prev.poc)) continue;

         //--- leg extreme, and the LVN between the current price and that extreme
         double extreme = (dir > 0) ? r[1].high : r[1].low;
         for(int i = 1; i <= InpLegBars && i < got; i++)
            extreme = (dir > 0) ? MathMax(extreme, r[i].high) : MathMin(extreme, r[i].low);

         double lvn = 0.0;
         if(!LowestVolumeNode(ctx.symbol, 1, InpLegBars, ctx.mid, extreme, lvn)) continue;

         //--- price must have pulled BACK into the node (no chase)
         double tol = 0.30 * ctx.atr;
         if(dir > 0 && !(r[1].low <= lvn + tol)) continue;
         if(dir < 0 && !(r[1].high >= lvn - tol)) continue;

         //--- aggression in the trend direction
         if(!AggressiveBar(ctx, dir, InpAggressionBody)) continue;

         double entry = (dir > 0) ? ctx.ask : ctx.bid;
         //--- the aggressive print's extreme: the trigger bar with its own 3-bar swing
         double print = (dir > 0) ? MathMin(r[1].low, MathMin(r[2].low, r[3].low))
                                  : MathMax(r[1].high, MathMax(r[2].high, r[3].high));
         double stop  = StopFor(ctx, dir, print);
         double risk  = MathAbs(entry - stop);
         if(risk < InpMinStopAtr * ctx.atr) return false;

         //--- "Target the previous balance POC": the mean-reversion model returns TO the POC; in the
         //--- trend model price has already left it, so the EA projects one value-area width beyond
         //--- it (the new balance area) and keeps an R-based fallback.  `[interpretation]`
         double width = MathAbs(prev.poc - prev.val);
         double target = (dir > 0) ? prev.poc + width : prev.poc - width;
         if(dir > 0 && target <= entry) target = entry + 2.0 * risk;
         if(dir < 0 && target >= entry) target = entry - 2.0 * risk;
         if(MathAbs(target - entry) < InpMinRR * risk) return false;

         plan.dir = dir; plan.entry = entry; plan.stop = stop; plan.target = target;
         plan.riskDist = risk; plan.barsAgo = 1; plan.score = 68.0; plan.isLimit = false;
         plan.reason = StringFormat("trend model: LVN %.2f inside the impulse leg (POC %.2f)", lvn, prev.poc);
         return true;
      }
      return false;
   }

   //--- MEAN REVERSION MODEL: failed auction outside value, reclaim, then the pullback into the
   //--- reclaim leg's LVN with aggression toward the snap-back.
   bool MeanReversionModel(SEAContext &ctx, const SVolProfile &prev, SSignalPlan &plan)
   {
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, InpFailLookback + 6, r);
      if(got < InpFailLookback + 2) return false;

      for(int dir = +1; dir >= -1; dir -= 2)      // dir = the snap-back direction
      {
         double edge = (dir > 0) ? prev.val : prev.vah;      // the value edge that was broken
         //--- the failed auction: a bar beyond the edge that closed back inside value
         int failIdx = -1;
         for(int i = 2; i <= InpFailLookback && i < got; i++)
         {
            bool beyond = (dir > 0) ? (r[i].low < edge) : (r[i].high > edge);
            bool backIn = (dir > 0) ? (r[i].close > edge) : (r[i].close < edge);
            if(beyond && backIn) { failIdx = i; break; }
         }
         if(failIdx < 2) continue;

         //--- "do not take the first move back": the reclaim must be an EARLIER bar, and the last
         //--- closed bar is the pullback - otherwise the trader would be entering the reclaim itself
         if(failIdx <= 2) continue;

         //--- the reclaim leg (failed auction -> now) and its LVN
         double extreme = (dir > 0) ? r[1].low : r[1].high;
         for(int i = 1; i <= failIdx && i < got; i++)
            extreme = (dir > 0) ? MathMin(extreme, r[i].low) : MathMax(extreme, r[i].high);
         double legStart = (dir > 0) ? r[failIdx].low : r[failIdx].high;
         double lvn = 0.0;
         if(!LowestVolumeNode(ctx.symbol, 1, failIdx, ctx.mid, legStart, lvn)) continue;

         //--- pullback INTO the LVN on the last closed bar
         double tol = 0.30 * ctx.atr;
         if(dir > 0 && !(r[1].low <= lvn + tol)) continue;
         if(dir < 0 && !(r[1].high >= lvn - tol)) continue;

         //--- aggression toward the snap-back (big buys after a failed downside break, ...)
         if(!AggressiveBar(ctx, dir, InpAggressionBody)) continue;

         double entry = (dir > 0) ? ctx.ask : ctx.bid;
         double print = (dir > 0) ? MathMin(r[1].low, extreme) : MathMax(r[1].high, extreme);
         double stop  = StopFor(ctx, dir, print);
         double risk  = MathAbs(entry - stop);
         if(risk < InpMinStopAtr * ctx.atr) return false;

         //--- "Target the balance POC.  Close the full position there."
         double target = prev.poc;
         if(dir > 0 && target <= entry) return false;
         if(dir < 0 && target >= entry) return false;
         if(MathAbs(target - entry) < InpMinRR * risk) return false;

         plan.dir = dir; plan.entry = entry; plan.stop = stop; plan.target = target;
         plan.riskDist = risk; plan.barsAgo = 1; plan.score = 70.0; plan.isLimit = false;
         plan.reason = StringFormat("mean reversion: failed auction at %.2f, reclaim leg LVN %.2f -> POC %.2f",
                                    edge, lvn, prev.poc);
         return true;
      }
      return false;
   }

   //--- tick-volume profile over bars [fromBar..toBar] of the signal timeframe.
   //--- `[interpretation]`: the playbook applies a real volume profile; the engine has bar tick
   //--- volume only, so that is what is bucketed here.
   bool BuildProfile(const string sym, const int fromBar, const int toBar, SVolProfile &out)
   {
      out.ok = false; out.poc = 0.0; out.val = 0.0; out.vah = 0.0;
      MqlRates r[];
      int got = EA_Rates(sym, g_eaIndTf, 0, toBar + 2, r);
      if(got < toBar + 1 || InpProfileBins < 8) return false;

      double hi = -DBL_MAX, lo = DBL_MAX;
      for(int i = fromBar; i <= toBar && i < got; i++)
      { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }
      if(hi <= lo) return false;

      int    nb = InpProfileBins;
      double binVol[]; ArrayResize(binVol, nb); ArrayInitialize(binVol, 0.0);
      double size = (hi - lo) / nb;
      for(int i = fromBar; i <= toBar && i < got; i++)
      {
         int b1 = (int)MathFloor((r[i].low - lo) / size);
         int b2 = (int)MathFloor((r[i].high - lo) / size);
         b1 = (int)MathMax(0, MathMin(nb - 1, b1));
         b2 = (int)MathMax(0, MathMin(nb - 1, b2));
         double v = (double)r[i].tick_volume;
         int span = b2 - b1 + 1;
         for(int b = b1; b <= b2; b++) binVol[b] += v / (double)span;
      }

      int pocBin = 0;
      double total = 0.0;
      for(int b = 0; b < nb; b++)
      {
         total += binVol[b];
         if(binVol[b] > binVol[pocBin]) pocBin = b;
      }
      if(total <= 0.0) return false;

      //--- value area: expand from the POC into the larger neighbour until 70% is covered
      int loBin = pocBin, hiBin = pocBin;
      double covered = binVol[pocBin];
      while(covered < InpValueAreaPct * total && (loBin > 0 || hiBin < nb - 1))
      {
         double below = (loBin > 0) ? binVol[loBin - 1] : -1.0;
         double above = (hiBin < nb - 1) ? binVol[hiBin + 1] : -1.0;
         if(above >= below) { hiBin++; covered += binVol[hiBin]; }
         else               { loBin--; covered += binVol[loBin]; }
      }

      out.poc = lo + (pocBin + 0.5) * size;
      out.val = lo + loBin * size;
      out.vah = lo + (hiBin + 1) * size;
      out.ok  = true;
      return true;
   }

   //--- the lowest-volume bin strictly between two prices, i.e. the node the playbook marks as the
   //--- reaction point inside the leg.  Returns its centre.
   bool LowestVolumeNode(const string sym, const int fromBar, const int toBar,
                         const double priceA, const double priceB, double &node)
   {
      if(InpProfileBins < 8) return false;
      MqlRates r[];
      int got = EA_Rates(sym, g_eaIndTf, 0, toBar + 2, r);
      if(got < toBar + 1) return false;
      double hi = -DBL_MAX, lo = DBL_MAX;
      for(int i = fromBar; i <= toBar && i < got; i++)
      { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }
      if(hi <= lo) return false;

      double zlo = MathMin(priceA, priceB), zhi = MathMax(priceA, priceB);
      zlo = MathMax(zlo, lo); zhi = MathMin(zhi, hi);
      if(zhi <= zlo) return false;

      int nb = InpProfileBins;
      double size = (hi - lo) / nb;
      double binVol[]; ArrayResize(binVol, nb); ArrayInitialize(binVol, 0.0);
      for(int i = fromBar; i <= toBar && i < got; i++)
      {
         int b1 = (int)MathMax(0, MathMin(nb - 1, (int)MathFloor((r[i].low - lo) / size)));
         int b2 = (int)MathMax(0, MathMin(nb - 1, (int)MathFloor((r[i].high - lo) / size)));
         double v = (double)r[i].tick_volume;
         int span = b2 - b1 + 1;
         for(int b = b1; b <= b2; b++) binVol[b] += v / (double)span;
      }

      int best = -1;
      for(int b = 0; b < nb; b++)
      {
         double centre = lo + (b + 0.5) * size;
         if(centre < zlo || centre > zhi) continue;
         if(best < 0 || binVol[b] < binVol[best]) best = b;
      }
      if(best < 0) return false;
      node = lo + (best + 0.5) * size;
      return true;
   }
};

CCfAuctionMarket g_cfAuctionMarket;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfAuctionMarket);
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
