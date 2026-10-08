//+------------------------------------------------------------------+
//|                                     EA_CF_LiquidityStrategy.mq5  |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Marco Trade's Liquidity Playbook (PDF, Apr 2025)                  |
//| Card    : chartfanatics/todos/liquidity-strategy.md  (#18)         |
//| Source  : chartfanatics/pdf/liquidity-strategy.pdf                 |
//| Magic   : 3221                                                     |
//|                                                                    |
//| THE MODEL: price seeks liquidity; retail traders get trapped at     |
//| key highs and lows.  Do not enter before the level is run - wait    |
//| for the market to take the liquidity, trap the breakout crowd, and  |
//| then trade the reversal.                                            |
//|                                                                    |
//|   (1) identify a high/low that was RESPECTED and caused price to    |
//|       move away - that is where the resting liquidity sits;         |
//|   (2) wait for price to return and trade THROUGH that level (run    |
//|       stops / trigger breakout entries);                            |
//|   (3) the trap is confirmed when price rejects back inside the      |
//|       level (the playbook's own 5-minute breakdown);                |
//|   (4) SELL above the swept high, BUY below the swept low - market   |
//|       execution once the level is taken and the trap is confirmed;  |
//|   (5) stop-loss always covers the last high/low that was taken;     |
//|   (6) target the opposing resting liquidity - the playbook's example |
//|       targets the equal lows marked on the 30-minute chart.         |
//|                                                                    |
//| The document's management rules are enforced in Manage():           |
//|   * partials only AT actual liquidity targets, never at arbitrary    |
//|     R-multiples;                                                     |
//|   * no break-even stop unless a partial has been taken;               |
//|   * the stop moves only after price has moved in our favour and       |
//|     formed a higher low (long) / lower high (short);                  |
//|   * runners are left to reach meaningful liquidity areas.             |
//|                                                                    |
//| `[interpretation]`: the playbook is a method, not a parameter list,   |
//| so the numbers it never states are fixed here and labelled - the      |
//| fractal strength and depth of the context scan (30-minute chart, per  |
//| the breakdown), the move-away distance that qualifies a level as      |
//| respected (an ATR multiple), the equal-highs/lows clustering          |
//| tolerance, the trap freshness window, the entry zone around the swept |
//| level (the doc's "sell above the high, never below" plus its          |
//| "entered right after the rejection"), the stop buffer, the 1R floor   |
//| that keeps a trade from aiming at a nearer pool than its own stop,    |
//| the NY-open session window the doc only gives as an example, and the  |
//| 50% partial size.  The document states no position-sizing rule, so    |
//| the engine risk percent applies.                                     |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "Marco Trade liquidity playbook - sweep the respected level, trade the trap back inside, target the opposing liquidity"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade   = "US100,US500";     // the playbook is asset-agnostic (futures/forex/crypto)
input ulong             InpMagicNumber      = 3221;              // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct          = 0.50;              // Risk per trade (% of equity) - the doc states no sizing rule
input int               InpStage             = 5;                // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input int               InpServerGmtOffset  = 2;                 // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;     // Log verbosity
input double            InpCommissionPerLotRT = 0.0;             // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.12;            // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;            // Write the engine evidence ledger CSV
//--- the context chart (the breakdown reads levels on the 30-minute chart)
input ENUM_TIMEFRAMES   InpContextTf        = PERIOD_M30;        // "the focus was on the 30-minute chart"
input int               InpContextBars      = 90;                // 30-minute bars scanned for levels (about 5 sessions)
input int               InpFractalBars      = 2;                 // swing strength that makes a level
input int               InpAwayBars         = 8;                 // bars allowed for the move-away measurement
input double            InpAwayAtr          = 1.0;               // a level must move price this far (context ATR) to hold liquidity
input double            InpEqualTolAtr      = 0.25;              // equal highs/lows cluster tolerance (context ATR)
//--- the trap
input int               InpLookbackM5       = 96;                // execution bars checked that the level was intact before the run
input int               InpTrapBars         = 6;                 // the trap must be this fresh (M5 bars since the run)
input double            InpBreachTolAtr     = 0.05;              // how far through the level counts as taken (execution ATR)
input double            InpMaxChaseAtr      = 0.35;              // entry must stay this close to the swept level (never chase)
input double            InpStopBufferAtr    = 0.10;              // stop buffer beyond the level that was taken
//--- targets / management
input double            InpMinTargetR       = 1.0;               // trade floor: the nearest pool must be this far away ([interpretation])
input double            InpClusterReach     = 1.6;               // prefer an equal-highs/lows cluster within this multiple of a nearer single level
input int               InpPartialPct       = 50;                // partial size at the first liquidity target ([interpretation])
input bool              InpMoveStopAfterPartial = true;          // "no break-even stops unless partials have been taken"
input int               InpStructureBars    = 24;                // M5 bars searched for the higher low / lower high
//--- session
input int               InpSessionStartHour = 14;                // New York open window, London clock ([interpretation]: doc says "e.g.")
input int               InpSessionStartMin  = 30;                // 14:30 London = 09:30 ET
input int               InpSessionEndHour   = 17;                // 17:00 London = 12:00 ET
input int               InpSessionEndMin    = 0;
input int               InpMaxTradesPerDay  = 2;                 // [interpretation]: the doc sets no daily cap

//--- one resting liquidity level from the context chart
struct SCfLiqLevel
{
   double level;      // the pool's price (the cluster extreme)
   datetime time;     // when the swing formed
   int    side;       // +1 buyside (a high above), -1 sellside (a low below)
   int    touches;    // >= 2 -> the playbook's equal highs / equal lows
};

//+------------------------------------------------------------------+
class CCfLiquidityTrap : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_LIQUIDITY_STRATEGY";
      cfg.sourceDoc             = "chartfanatics/pdf/liquidity-strategy.pdf (card #18)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;          // the breakdown's execution chart
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = 3.0;
      cfg.dailyLossPct          = 1.50;
      cfg.weeklyLossPct         = 3.0;
      cfg.totalDdPct            = 8.0;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 120;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = false;              // "use market execution once the high/low is taken"
      cfg.newsFilter            = false;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_liquidity_strategy_ledger.csv";
      cfg.logLevel              = InpLogLevel;
      //--- "have a specific session window (e.g. New York Open)"; setups outside it are ignored
      cfg.sessionStartHour = InpSessionStartHour;  cfg.sessionStartMin = InpSessionStartMin;
      cfg.sessionEndHour   = InpSessionEndHour;    cfg.sessionEndMin   = InpSessionEndMin;
      cfg.noTradeAfterHour = InpSessionEndHour;    cfg.noTradeAfterMin = InpSessionEndMin;
      //--- the engine's own R-based management is switched OFF: the playbook manages by liquidity
      cfg.partial1AtR      = 0.0;                     // "don't take partials at arbitrary R-multiples"
      cfg.breakEvenAtR     = 0.0;                     // "no break-even stops unless partials have been taken"
      cfg.trailAtR         = 0.0;                     // the stop follows structure, not an R grid
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   void OnInitStrategy()
   {
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "liquidity trap armed: levels from %s (fractal %d, move-away %.2f ATR), NY-open window %02d:%02d-%02d:%02d London, partial %d%% at the first pool",
             EnumToString(InpContextTf), InpFractalBars, InpAwayAtr,
             InpSessionStartHour, InpSessionStartMin, InpSessionEndHour, InpSessionEndMin,
             InpPartialPct), true);
   }

   //-------------------------------------------------------------------
   // The trap: a respected level is taken and price rejects back inside
   //-------------------------------------------------------------------
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession || ctx.atr <= 0.0) return false;          // "ignore price action outside your session"

      SCfLiqLevel levels[];
      int count = LiquidityLevels(ctx.symbol, levels);
      if(count <= 0) return false;    // "don't trade unless liquidity is built" / "no trade" after a big move

      for(int i = 0; i < count; i++)
      {
         int    side = levels[i].side;
         int    runBar = 0;
         double runExtreme = 0.0;
         if(!TrapConfirmed(ctx, levels[i].level, side, runBar, runExtreme)) continue;

         int    dir   = -side;                                   // the level was taken -> trade the reversal
         double entry = (dir > 0) ? ctx.ask : ctx.bid;
         //--- "sell above the high, never below" and "entered right after the rejection, once the price
         //--- moved back below the high": price is back inside the level, but the entry may not chase it.
         if(dir < 0 && (ctx.mid > levels[i].level || ctx.mid < levels[i].level - InpMaxChaseAtr * ctx.atr)) continue;
         if(dir > 0 && (ctx.mid < levels[i].level || ctx.mid > levels[i].level + InpMaxChaseAtr * ctx.atr)) continue;

         double stop = (dir > 0) ? runExtreme - InpStopBufferAtr * ctx.atr
                                 : runExtreme + InpStopBufferAtr * ctx.atr;
         double risk = (dir > 0) ? entry - stop : stop - entry;
         if(risk <= 0.0) continue;

         double firstPool = PoolTarget(ctx, dir, entry, levels, count, risk, false);
         if(firstPool <= 0.0) continue;                          // nothing resting ahead -> no trade
         double runTarget = PoolTarget(ctx, dir, entry, levels, count, risk, true);
         if(runTarget <= 0.0) runTarget = firstPool;

         double rr = MathAbs(runTarget - entry) / risk;
         plan.dir       = dir;
         plan.entry     = entry;
         plan.stop      = stop;
         plan.target    = runTarget;
         plan.riskDist  = risk;
         plan.barsAgo   = 1;
         plan.sweepBarsAgo = runBar;
         plan.score     = (levels[i].touches >= 2) ? 76.0 : 72.0;
         plan.isLimit   = false;
         plan.reason    = StringFormat("liquidity trap: %s %.2f was run and rejected, stop over the taken %s, first pool %.2f, runner target %.2f (%.2fR)",
                                       (side > 0) ? "buyside high" : "sellside low", levels[i].level,
                                       (side > 0) ? "high" : "low", firstPool, runTarget, rr);
         return true;
      }
      return false;
   }

   //-------------------------------------------------------------------
   // Playbook management: partials at liquidity, structure-based stop
   //-------------------------------------------------------------------
   void Manage(SEAContext &ctx)
   {
      if(ctx.atr <= 0.0) return;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong ticket = PositionGetTicket(p);
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;

         int idx = EA_TrackIndex(ticket);          // engine tracking: entry, initial risk, partial state
         if(idx < 0) continue;
         int    dir   = g_eaTrack[idx].dir;
         double entry = g_eaTrack[idx].entry;
         double risk  = g_eaTrack[idx].riskDist;
         double sl    = PositionGetDouble(POSITION_SL);
         if(risk <= 0.0) continue;

         //--- partial only when an actual liquidity target is reached
         if(!g_eaTrack[idx].p1Done)
         {
            SCfLiqLevel levels[];
            int count = LiquidityLevels(ctx.symbol, levels);
            double firstPool = PoolTarget(ctx, dir, entry, levels, count, risk, false);
            if(firstPool > 0.0 && TargetReached(ctx, dir, firstPool))
            {
               if(g_eaExec.ClosePartial(ticket, InpPartialPct))
               {
                  g_eaTrack[idx].p1Done = true;
                  EA_Log(EA_LOG_EVENTS, StringFormat(
                         "%d%% taken at the liquidity target %.2f - the runner keeps its structure stop",
                         InpPartialPct, firstPool), true);
               }
               else if(!g_eaExec.CanPartial(ticket, InpPartialPct))
                  g_eaTrack[idx].p1Done = true;     // volume cannot be split - carry on with the full position
            }
         }

         //--- "only move your stop after price moves in your favour and forms a higher low / lower high"
         //--- and "no break-even stops unless partials have been taken"
         if(InpMoveStopAfterPartial && !g_eaTrack[idx].p1Done) continue;
         double structure = StructureStop(ctx.symbol, dir);
         if(structure <= 0.0) continue;
         double newSl = (dir > 0) ? structure - InpStopBufferAtr * ctx.atr
                                  : structure + InpStopBufferAtr * ctx.atr;
         bool improves = (dir > 0) ? (newSl > sl) : (newSl < sl);
         if(!improves) continue;                        // the stop only ever ratchets in our favour
         //--- "no break-even stops unless partials have been taken"
         if(!g_eaTrack[idx].p1Done)
         {
            if(dir > 0 && newSl >= entry) continue;
            if(dir < 0 && newSl <= entry) continue;
         }
         if(dir > 0 && newSl >= ctx.bid) continue;      // never park the stop inside the market
         if(dir < 0 && newSl <= ctx.ask) continue;
         if(g_eaExec.Modify(ticket, newSl, PositionGetDouble(POSITION_TP)))
            EA_Log(EA_LOG_EVENTS, StringFormat("stop follows the new %s to %.2f",
                   (dir > 0) ? "higher low" : "lower high", newSl), true);
      }
   }

private:
   //-------------------------------------------------------------------
   // Resting liquidity levels on the context chart
   //-------------------------------------------------------------------
   int LiquidityLevels(const string sym, SCfLiqLevel &levels[])
   {
      ArrayResize(levels, 0);
      MqlRates r[];
      int got = EA_Rates(sym, InpContextTf, 0, InpContextBars + InpFractalBars + InpAwayBars + 4, r);
      if(got < InpFractalBars * 2 + InpAwayBars + 6) return 0;
      double atrCtx = ContextAtr(sym);
      if(atrCtx <= 0.0) return 0;

      int count = 0;
      for(int k = InpFractalBars + 1; k <= got - InpAwayBars - 2; k++)
      {
         bool isHigh = true, isLow = true;
         for(int j = 1; j <= InpFractalBars; j++)
         {
            if(r[k + j].high >= r[k].high || r[k - j].high >= r[k].high) isHigh = false;
            if(r[k + j].low  <= r[k].low  || r[k - j].low  <= r[k].low ) isLow  = false;
         }
         if(isHigh && LevelValid(r, k, +1, atrCtx))
            count = MergeLevel(levels, count, r[k].high, r[k].time, +1, atrCtx);
         if(isLow && LevelValid(r, k, -1, atrCtx))
            count = MergeLevel(levels, count, r[k].low, r[k].time, -1, atrCtx);
      }
      return count;
   }

   //--- The level is RESPECTED and STILL RESTING:
   //---   (a) after it formed, price moved away by InpAwayAtr context ATR, and
   //---   (b) nothing has CLOSED beyond it since (a close through means the level was consumed;
   //---       the sweep itself only wicks through and closes back inside - that is the trap).
   bool LevelValid(const MqlRates &r[], const int k, const int side, const double atrCtx)
   {
      double extreme = (side > 0) ? DBL_MAX : -DBL_MAX;
      for(int i = k - 1; i >= 1 && i >= k - InpAwayBars; i--)
      {
         if(side > 0) extreme = MathMin(extreme, r[i].low);
         else         extreme = MathMax(extreme, r[i].high);
      }
      if(side > 0 && extreme == DBL_MAX) return false;
      if(side < 0 && extreme == -DBL_MAX) return false;
      double level = (side > 0) ? r[k].high : r[k].low;
      double away  = (side > 0) ? (level - extreme) : (extreme - level);
      if(away < InpAwayAtr * atrCtx) return false;

      for(int i = 1; i < k; i++)                          // newer than the fractal
      {
         if(side > 0 && r[i].close > level) return false;  // buyside liquidity already consumed
         if(side < 0 && r[i].close < level) return false;  // sellside liquidity already consumed
      }
      return true;
   }

   //--- equal highs / equal lows are ONE pool in the playbook: merge near levels, keep the extreme
   int MergeLevel(SCfLiqLevel &levels[], const int count, const double level, const datetime when,
                  const int side, const double atrCtx)
   {
      for(int i = 0; i < count; i++)
      {
         if(levels[i].side != side) continue;
         if(MathAbs(levels[i].level - level) > InpEqualTolAtr * atrCtx) continue;
         levels[i].touches++;
         if(side > 0) levels[i].level = MathMax(levels[i].level, level);
         else         levels[i].level = MathMin(levels[i].level, level);
         return count;
      }
      ArrayResize(levels, count + 1);
      levels[count].level   = level;
      levels[count].time    = when;
      levels[count].side    = side;
      levels[count].touches = 1;
      return count + 1;
   }

   double ContextAtr(const string sym)
   {
      MqlRates r[];
      int got = EA_Rates(sym, InpContextTf, 0, 20, r);
      if(got < 5) return 0.0;
      double sum = 0.0;
      int n = 0;
      for(int i = 1; i <= 14 && i < got - 1; i++)
      {
         double tr = MathMax(r[i].high - r[i].low,
                             MathMax(MathAbs(r[i].high - r[i + 1].close),
                                     MathAbs(r[i].low  - r[i + 1].close)));
         sum += tr; n++;
      }
      return (n > 0) ? sum / n : 0.0;
   }

   //-------------------------------------------------------------------
   // The trap: the level is intact, then taken, then rejected back inside
   //-------------------------------------------------------------------
   bool TrapConfirmed(const SEAContext &ctx, const double level, const int side, int &runBar, double &runExtreme)
   {
      runBar = 0; runExtreme = 0.0;
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, PERIOD_M5, 0, InpLookbackM5 + 2, r);
      if(got < 24) return false;
      double tol = InpBreachTolAtr * ctx.atr;

      //--- the newest bar that traded through the level
      int run = -1;
      for(int i = 1; i < got - 1; i++)
      {
         bool through = (side > 0) ? (r[i].high > level + tol) : (r[i].low < level - tol);
         if(through) { run = i; break; }
      }
      if(run < 0) return false;
      if(run > InpTrapBars) return false;                 // stale: "the entry came right after the trap was confirmed"

      //--- "there was no trade before the level was run": the level was intact inside the lookback
      for(int i = run + 1; i < got; i++)
      {
         bool through = (side > 0) ? (r[i].high > level + tol) : (r[i].low < level - tol);
         if(through) return false;
      }

      //--- the run's extreme - "always cover the last high/low with your stop"
      runExtreme = (side > 0) ? r[run].high : r[run].low;
      for(int i = 1; i <= run; i++)
         runExtreme = (side > 0) ? MathMax(runExtreme, r[i].high) : MathMin(runExtreme, r[i].low);

      //--- the rejection: the newest completed bar closed back inside the level
      bool rejected = (side > 0) ? (r[1].close < level) : (r[1].close > level);
      if(!rejected) return false;
      runBar = run;
      return true;
   }

   //-------------------------------------------------------------------
   // Targets: the opposing resting liquidity
   //-------------------------------------------------------------------
   //--- first=false -> the NEAREST pool ahead (the trade floor and the partial trigger)
   //--- first=true  -> the FURTHEST pool ahead (the runner objective, "let trades run")
   double PoolTarget(const SEAContext &ctx, const int dir, const double entry,
                     const SCfLiqLevel &levels[], const int count, const double risk, const bool furthest)
   {
      int    want = (dir > 0) ? +1 : -1;      // pools on the side the trade is heading
      double best = 0.0;
      int    bestTouches = 0;
      double floorDist = InpMinTargetR * risk;
      for(int i = 0; i < count; i++)
      {
         if(levels[i].side != want) continue;
         double lvl = levels[i].level;
         double dist = (dir > 0) ? (lvl - entry) : (entry - lvl);
         if(dist < floorDist) continue;                       // the doc: a pool closer than the stop is no objective
         if(best == 0.0) { best = lvl; bestTouches = levels[i].touches; continue; }
         double bestDist = MathAbs(best - entry);
         bool better;
         if(furthest) better = (dist > bestDist);
         else         better = (dist < bestDist);
         //--- the playbook's own target example is the EQUAL lows cluster: prefer a cluster
         //--- when it is within reach of the nearer single level
         if(!furthest && levels[i].touches >= 2 && bestTouches < 2 && dist <= bestDist * InpClusterReach)
            better = true;
         if(better) { best = lvl; bestTouches = levels[i].touches; }
      }
      return best;
   }

   bool TargetReached(const SEAContext &ctx, const int dir, const double target)
   {
      if(target <= 0.0) return false;
      return (dir > 0) ? (ctx.ask >= target) : (ctx.bid <= target);
   }

   //-------------------------------------------------------------------
   // Structure trail: the newest higher low (long) / lower high (short)
   //-------------------------------------------------------------------
   double StructureStop(const string sym, const int dir)
   {
      MqlRates r[];
      int got = EA_Rates(sym, PERIOD_M5, 0, InpStructureBars + 2, r);
      if(got < 6) return 0.0;
      double first = 0.0, second = 0.0;
      for(int k = 2; k <= got - 2; k++)
      {
         bool isFractal = (dir > 0) ? (r[k].low < r[k - 1].low && r[k].low < r[k + 1].low)
                                    : (r[k].high > r[k - 1].high && r[k].high > r[k + 1].high);
         if(!isFractal) continue;
         double lvl = (dir > 0) ? r[k].low : r[k].high;
         if(first == 0.0) first = lvl;
         else { second = lvl; break; }
      }
      if(first == 0.0 || second == 0.0) return 0.0;
      //--- only a NEW higher low (long) / lower high (short) justifies moving the stop
      bool improved = (dir > 0) ? (first > second) : (first < second);
      return improved ? first : 0.0;
   }
};

CCfLiquidityTrap g_cfLiquidityTrap;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfLiquidityTrap);
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
