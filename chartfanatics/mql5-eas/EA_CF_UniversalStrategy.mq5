//+------------------------------------------------------------------+
//|                                  EA_CF_UniversalStrategy.mq5      |
//|                                  Copyright 2026, Master Strategy  |
//|                                                                   |
//| ChartFanatics: Universal Strategy (Travelling Traders' Playbook)   |
//| "Universal Strategy" - Apr 2025, Stocks / Futures / Forex / Crypto |
//| Card    : chartfanatics/todos/universal-strategy.md         (#43)  |
//| Source  : chartfanatics/pdf/universal-strategy.pdf                 |
//| Magic   : 3246                                                    |
//|                                                                   |
//| "A trade is valid only when there is a clear and logical story     |
//|  behind it.  This story begins with liquidity, is confirmed by     |
//|  market behavior, and is executed only after price pulls back into |
//|  a high-quality area."                                             |
//|                                                                   |
//| The story has three components, and the EA requires all three:     |
//|   S1  THE LIQUIDITY CATALYST - "something meaningful happens": a   |
//|       sweep of equal highs/lows, a break of a major support/       |
//|       resistance zone, a break of a well-respected trendline, or a |
//|       market structure shift.  "No Liquidity Catalyst, No Trade".  |
//|   S2  DISPLACEMENT - "the market reacts with strength": a decisive |
//|       move away from the level, with "a noticeable shift in price  |
//|       behavior" and "a break in the prior swing structure".        |
//|       "Without meaningful displacement, there is no evidence that  |
//|       the market intends to move."                                 |
//|   S3  THE RETRACEMENT INTO A LOGICAL AREA - the entry: "Entries    |
//|       Are Taken Only on the Retracement ... You do not enter        |
//|       during the first impulsive move away from liquidity."  The   |
//|       zone is built from the document's own list - the broken      |
//|       support/resistance level, a fair value gap, an order block,  |
//|       a moving average used as dynamic support/resistance, a       |
//|       previous swing level, a trendline retest - and "no trade is  |
//|       taken based on a single signal": at least `InpMinConfluence` |
//|       of those factors must line up in the zone.                   |
//|                                                                   |
//|   S4  INVALIDATION: "the stop must sit beyond the level that       |
//|       proves the narrative wrong ... no wide stops out of fear, no |
//|       arbitrary breathing room.  Stops are always defined by price |
//|       structure, nothing else" - and when that level breaks, "the  |
//|       trade is invalid, and you exit without hesitation".          |
//|   S5  TARGETS: "liquidity pools, prior highs or lows, imbalance    |
//|       fills ... Markets move from one liquidity zone to the next" - |
//|       the nearest prior swing in the trade's direction.            |
//|   S6  PATIENCE: "If the retracement zone is never reached, the     |
//|       market did not fulfill your criteria ... Missing a Trade Is  |
//|       Not a Mistake" - the resting order expires and the EA waits  |
//|       for the next story.  "Manage the Trade According to the      |
//|       Story, Not Emotion" - no partials, no break-even, no trail,  |
//|       no "desire to protect profits prematurely".                  |
//|                                                                   |
//| The worked example the document prints (S&P 500 trendline break    |
//| and retest: break - follow-through that lost the most recent       |
//| higher low - retrace into the broken trendline where "the 21 EMA   |
//| aligned with the retest" - invalidation on a reclaim of the        |
//| trendline, targets at prior internal lows) is exactly the shape    |
//| this EA trades, with the trendline break as one of the catalysts.  |
//|                                                                   |
//| `[interpretation]`: the signal timeframe (the document is          |
//| timeframe-agnostic), the equal-level and zone-cluster tolerances,  |
//| the displacement thresholds, the confluence minimum, the zone's    |
//| life, the stop buffer and its width cap, the swing width used for  |
//| the target, the minimum target distance, the far fallback target,  |
//| the invalidation close count, the higher-timeframe MA period, the  |
//| catalyst freshness window and the attempt / open-position caps.    |
//|                                                                   |
//| Disclosed, not faked: the confluence list ends with "macro         |
//| conditions, seasonality, or significant news".  A backtest has no  |
//| working economic calendar, so the EA counts the technical          |
//| confluences the document lists and says out loud that the          |
//| fundamental one is not simulated.  Fundamental context is also     |
//| what the document's pros/cons pages call a human decision.         |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics Universal Strategy - the three-part story: a liquidity catalyst (sweep, level break, trendline break, structure shift), displacement that breaks the prior swing structure, and a retracement into a confluence zone entered only by a resting order"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade     = "US500,US100";    // The document's worked example is the S&P 500; "applies to any market"
input ulong             InpMagicNumber        = 3246;             // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct            = 0.50;             // Risk per trade (% of equity)
input int               InpStage              = 5;                // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input double            InpMaxSpreadPoints    = 40.0;             // Spread gate in points (0 = off)
input double            InpDailyLossPct       = 2.00;             // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset    = 2;                // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel           = EA_LOG_EVENTS;    // Log verbosity
input double            InpCommissionPerLotRT = 0.0;              // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.15;             // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;             // Write the engine evidence ledger CSV

//--- the frame
input ENUM_TIMEFRAMES   InpSignalTf           = PERIOD_H4;        // [interpretation] the document is timeframe-agnostic; H4 is the middle ground
input int               InpSwingSide          = 2;                // [interpretation] Bars each side of a swing point
input int               InpCatalystLookback   = 60;               // [interpretation] Bars searched for the liquidity catalyst
input int               InpMaxBarsSinceCat    = 20;               // [interpretation] "the story" is stale after this many bars
input int               InpHtfMaPeriod        = 50;               // [interpretation] The higher-timeframe reference for alignment

//--- S1: the liquidity catalyst
input double            InpEqualTolPct        = 0.05;             // [interpretation] How equal "equal highs/lows" are
input int               InpMinLevelTouches    = 2;                // "a break of a major support/resistance zone" - a level respected twice or more
input double            InpLevelTolPct        = 0.10;             // [interpretation] How close counts as touching that level
input double            InpBreakClosePct      = 0.05;             // [interpretation] A close beyond the level by x% = the break
input int               InpLineSwingSide      = 2;                // [interpretation] The trendline's swing width
input double            InpLineTolPct         = 0.25;             // [interpretation] How close to the line counts as respected

//--- S2: displacement
input double            InpDisplaceAtr        = 1.50;             // "After the catalyst, you want to see a decisive move away" - in ATR
input double            InpDisplaceBodyAtr    = 1.00;             // "A noticeable shift in price behavior" - one candle body this big in ATR

//--- S3: the retracement zone and its confluence
input int               InpMinConfluence      = 2;                // "No trade is taken based on a single signal" - the level itself plus at least one more
input double            InpZoneClusterPct     = 0.50;             // [interpretation] How close the confluence factors must sit to the level
input int               InpZoneLifeBars       = 12;               // "If the retracement zone is never reached ... move on" - the order's life
input int               InpEma21Period        = 21;               // "A moving average used as dynamic support/resistance" (the worked example uses the 21 EMA)
input int               InpDivRsiPeriod       = 14;               // "Divergence" - the RSI the sweep is compared against

//--- S4: invalidation
input double            InpStopBufferAtr      = 0.05;             // "No arbitrary breathing room" - a minimal structural buffer only
input double            InpMaxStopPct         = 2.50;             // [interpretation] Reject stops wider than x% of price
input int               InpInvalidateCloses   = 1;                // "If that level breaks, the trade is invalid" - completed closes beyond the zone

//--- S5 / S6: targets and bookkeeping
input int               InpTargetSwingSide    = 2;                // [interpretation] The swing width used to find the next liquidity pool
input double            InpMinTargetR         = 2.00;             // [interpretation] Only a pool at least this far away is used
input double            InpTargetR            = 4.00;             // [interpretation] Far fallback target
input int               InpMaxTradesPerDay    = 2;                // [interpretation] "Less Temptation to Overtrade"
input int               InpMaxOpenPositions   = 2;                // [interpretation] One story per symbol, a small portfolio cap
input int               InpMinSecondsBetween  = 3600;             // [interpretation] One attempt per signal bar at most

//+------------------------------------------------------------------+
struct SCatalyst
{
   int      kind;        // 1 = sweep of equal levels, 2 = level break, 3 = trendline break
   int      idx;         // the bar index of the catalyst
   datetime time;        // the catalyst's bar time (the story ledger's key)
   int      prevIdx;     // the older equal level of a sweep (the divergence check)
   double   level;       // the level the story is built on
   double   extreme;     // the catalyst's own extremity (the narrative's last defence)
};

//+------------------------------------------------------------------+
class CCfUniversalStrategy : public CEAStrategy
{
public:
   void OnInitStrategy()
   {
      m_emaCount = 0;
      m_rsiCount = 0;
      m_zoneLevel = 0.0;
      m_zoneHas = false;
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "Universal Strategy armed: story = liquidity catalyst -> displacement -> retracement; signal %s, confluence >= %d factors, zone +/- %.2f%%, order life %d bars, invalidation on %d completed close(s) beyond the zone",
             EnumToString(g_eaIndTf), InpMinConfluence, InpZoneClusterPct, InpZoneLifeBars, InpInvalidateCloses), true);
   }

   void OnDeinitStrategy()
   {
      for(int i = 0; i < m_emaCount; i++)
      {
         if(m_ema[i].hEma21 != INVALID_HANDLE) IndicatorRelease(m_ema[i].hEma21);
         if(m_ema[i].hHtf   != INVALID_HANDLE) IndicatorRelease(m_ema[i].hHtf);
         m_ema[i].hEma21 = INVALID_HANDLE;
         m_ema[i].hHtf   = INVALID_HANDLE;
      }
      m_emaCount = 0;
      for(int i = 0; i < m_rsiCount; i++)
         if(m_rsi[i].h != INVALID_HANDLE) { IndicatorRelease(m_rsi[i].h); m_rsi[i].h = INVALID_HANDLE; }
      m_rsiCount = 0;
   }

   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_UNIVERSAL";
      cfg.sourceDoc             = "chartfanatics/pdf/universal-strategy.pdf (card #43)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = InpSignalTf;      // "applies to any market ... any timeframe"
      cfg.clock                 = EA_CLOCK_SERVER;  // the document names no session window
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = 4.0;
      cfg.totalDdPct            = 10.0;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = InpMaxOpenPositions;
      cfg.minSecondsBetweenTrades = InpMinSecondsBetween;
      cfg.sessionStartHour      = 0;
      cfg.sessionStartMin       = 0;
      cfg.sessionEndHour        = 23;
      cfg.sessionEndMin         = 59;
      cfg.sessionEndFlat        = false;           // "Manage the Trade According to the Story, Not Emotion"
      cfg.fridayFlat            = false;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = true;            // "Entries Are Taken Only on the Retracement" - never a market chase
      //--- "the desire to protect profits prematurely" is what the document warns against
      cfg.breakEvenAtR          = 0.0;
      cfg.trailAtR              = 0.0;
      cfg.partial1AtR           = 0.0;
      cfg.partial2AtR           = 0.0;
      cfg.timeStopMinutes       = 0;
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_universal_strategy_ledger.csv";
      cfg.logLevel              = InpLogLevel;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   //+----------------------------------------------------------------+
   //| S1 -> S2 -> S3: find the freshest story and price its entry     |
   //+----------------------------------------------------------------+
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      m_zoneHas = false;
      m_zoneLevel = 0.0;
      if(ctx.atr <= 0.0 || !ctx.inSession) return false;

      PruneState();

      MqlRates d[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, InpCatalystLookback + 20, d);
      if(got < 40) return false;

      double best = -1.0;
      SSignalPlan p;
      for(int dir = +1; dir >= -1; dir -= 2)
      {
         p.Reset();
         double zone = 0.0;
         if(!PlanStory(ctx, d, got, dir, p, zone)) continue;
         if(p.score > best) { plan = p; best = p.score; m_zoneLevel = zone; m_zoneHas = true; }
      }
      if(plan.dir != 0 && m_zoneHas)
      {
         PendingStore(ctx.symbol, plan.dir, m_zoneLevel);
         EA_Log(EA_LOG_EVENTS, StringFormat("%s: story complete - %s", ctx.symbol, plan.reason), true);
      }
      return (plan.dir != 0);
   }

   //+----------------------------------------------------------------+
   //| S4/S6: the narrative's own exit - "if that level breaks, the    |
   //| trade is invalid, and you exit without hesitation"              |
   //+----------------------------------------------------------------+
   void Manage(SEAContext &ctx)
   {
      if(PositionsTotal() == 0) return;
      MqlRates m[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, 6, m);
      if(got < 4) return;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != (long)g_eaCfg.magic) continue;

         bool isLong = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

         if(!TagExists(t, "_Z") && PendingFresh(ctx.symbol))
         {
            datetime stamp  = (datetime)GlobalVariableGet(K(ctx.symbol, "_PST"));
            datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
            if(opened + (datetime)3600 >= stamp && opened <= stamp + (datetime)3600)
            {
               GlobalVariableSet(T(t, "_Z"), GlobalVariableGet(K(ctx.symbol, "_PL")));
               GlobalVariableSet(T(t, "_D"), GlobalVariableGet(K(ctx.symbol, "_PD")));
               PendingClear(ctx.symbol);
            }
         }
         if(!TagExists(t, "_Z")) continue;
         double zone = GlobalVariableGet(T(t, "_Z"));
         if(zone <= 0.0) continue;

         //--- "the trade is invalid, and you exit without hesitation": completed closes
         //--- beyond the zone the story was built on
         int need = (int)MathMax(1, InpInvalidateCloses);
         int beyond = 0;
         for(int k = 1; k <= need && k < got; k++)
         {
            if(isLong ? (m[k].close < zone) : (m[k].close > zone)) beyond++;
            else break;
         }
         if(beyond >= need)
         {
            if(g_eaExec.Close(t, "the story is invalid - the level it was built on no longer holds"))
               EA_Log(EA_LOG_EVENTS, "Universal Strategy: position closed - the narrative's invalidation level broke", true);
         }
      }
   }

private:
   struct SEmaPair
   {
      string sym;
      int    hEma21;
      int    hHtf;
   };
   struct SRsiSlot
   {
      string sym;
      int    h;
   };
   SEmaPair m_ema[8];
   int      m_emaCount;
   SRsiSlot m_rsi[8];
   int      m_rsiCount;
   double   m_zoneLevel;
   bool     m_zoneHas;

   //+----------------------------------------------------------------+
   //| Indicator handles                                               |
   //+----------------------------------------------------------------+
   bool EmaPair(const string sym, SEmaPair &out)
   {
      for(int i = 0; i < m_emaCount; i++)
         if(m_ema[i].sym == sym) { out = m_ema[i]; return (out.hEma21 != INVALID_HANDLE && out.hHtf != INVALID_HANDLE); }
      if(m_emaCount >= 8) return false;
      SEmaPair n;
      n.sym    = sym;
      n.hEma21 = iMA(sym, g_eaIndTf, InpEma21Period, 0, MODE_EMA, PRICE_CLOSE);
      n.hHtf   = iMA(sym, PERIOD_D1,  InpHtfMaPeriod,  0, MODE_EMA, PRICE_CLOSE);
      if(n.hEma21 == INVALID_HANDLE || n.hHtf == INVALID_HANDLE)
      {
         EA_Log(EA_LOG_ERRORS, StringFormat("EMA handles failed for %s (err %d)", sym, GetLastError()), true);
         if(n.hEma21 != INVALID_HANDLE) IndicatorRelease(n.hEma21);
         if(n.hHtf   != INVALID_HANDLE) IndicatorRelease(n.hHtf);
         return false;
      }
      m_ema[m_emaCount] = n;
      m_emaCount++;
      out = n;
      return true;
   }
   int RsiHandle(const string sym)
   {
      for(int i = 0; i < m_rsiCount; i++)
         if(m_rsi[i].sym == sym) return m_rsi[i].h;
      if(m_rsiCount >= 8) return INVALID_HANDLE;
      SRsiSlot n;
      n.sym = sym;
      n.h   = iRSI(sym, g_eaIndTf, InpDivRsiPeriod, PRICE_CLOSE);
      if(n.h == INVALID_HANDLE) return INVALID_HANDLE;
      m_rsi[m_rsiCount] = n;
      m_rsiCount++;
      return n.h;
   }
   double EmaVal(const int handle, const int shift)
   {
      double v;
      if(!EA_Buf(handle, 0, shift, v)) return 0.0;
      return v;
   }

   int PivotLows(const MqlRates &d[], const int got, const int side, double &px[], int &ix[])
   {
      int n = 0;
      for(int i = side + 1; i + side < got - 1 && n < 16; i++)
      {
         bool pl = true;
         for(int k = 1; k <= side; k++)
            if(d[i].low >= d[i - k].low || d[i].low >= d[i + k].low) pl = false;
         if(pl) { px[n] = d[i].low; ix[n] = i; n++; }
      }
      return n;
   }
   int PivotHighs(const MqlRates &d[], const int got, const int side, double &px[], int &ix[])
   {
      int n = 0;
      for(int i = side + 1; i + side < got - 1 && n < 16; i++)
      {
         bool ph = true;
         for(int k = 1; k <= side; k++)
            if(d[i].high <= d[i - k].high || d[i].high <= d[i + k].high) ph = false;
         if(ph) { px[n] = d[i].high; ix[n] = i; n++; }
      }
      return n;
   }

   //+----------------------------------------------------------------+
   //| S1: the three catalyst detectors of the document's list         |
   //+----------------------------------------------------------------+
   //--- the newest pivot extreme before bar `before`, used by the displacement check
   double PriorSwing(const MqlRates &d[], const int got, const int before, const int side, const int dir)
   {
      double px[16]; int ix[16];
      int n = (dir > 0) ? PivotHighs(d, got, side, px, ix) : PivotLows(d, got, side, px, ix);
      for(int i = 0; i < n; i++)
         if(ix[i] > before) return px[i];              // pivots are collected oldest -> newest
      return 0.0;
   }

   //--- "a sweep of equal highs/lows": two or more equal levels, then a wick through
   //--- them in the SAME direction the trade will take, closed back on-side (the
   //--- rejection is the evidence the interaction mattered)
   bool CatalystSweep(const MqlRates &d[], const int got, const int dir, SCatalyst &c)
   {
      double px[16]; int ix[16];
      int n = (dir > 0) ? PivotLows(d, got, InpSwingSide, px, ix) : PivotHighs(d, got, InpSwingSide, px, ix);
      if(n < 2) return false;
      double tol = InpEqualTolPct / 100.0;
      //--- find the newest pair of equal levels (px is newest first)
      double level = 0.0;
      int    newest = 0, prevIdx = 0;
      for(int i = 0; i + 1 < n; i++)
      {
         if(MathAbs(px[i] - px[i + 1]) / px[i + 1] <= tol)
         {
            level = (px[i] + px[i + 1]) / 2.0;
            newest = ix[i];
            prevIdx = ix[i + 1];
            break;
         }
      }
      if(level <= 0.0) return false;
      int older = prevIdx;
      //--- the sweep bar: a wick beyond the level, closed back on the trade's side
      for(int i = 1; i <= newest && i <= InpMaxBarsSinceCat; i++)
      {
         bool swept = (dir > 0) ? (d[i].low < level && d[i].close > level)
                                : (d[i].high > level && d[i].close < level);
         if(swept)
         {
            c.kind    = 1;
            c.idx     = i;
            c.time    = d[i].time;
            c.prevIdx = older;
            c.level   = level;
            c.extreme = (dir > 0) ? d[i].low : d[i].high;
            return true;
         }
      }
      return false;
   }

   //--- "a break of a major support/resistance zone": a level respected at least
   //--- `InpMinLevelTouches` times, then closed through decisively
   bool CatalystLevelBreak(const MqlRates &d[], const int got, const int dir, SCatalyst &c)
   {
      double px[16]; int ix[16];
      int n = (dir > 0) ? PivotHighs(d, got, InpSwingSide, px, ix) : PivotLows(d, got, InpSwingSide, px, ix);
      if(n < InpMinLevelTouches) return false;
      double tol = InpLevelTolPct / 100.0;
      for(int i = 0; i < n; i++)                          // newest pivot first
      {
         double level = px[i];
         int touches = 1;
         for(int k = i + 1; k < n; k++)
            if(MathAbs(px[k] - level) / level <= tol) touches++;
         if(touches < InpMinLevelTouches) continue;
         int firstIdx = ix[i];
         for(int j = 1; j < firstIdx && j <= InpMaxBarsSinceCat; j++)
         {
            double need = InpBreakClosePct / 100.0;
            bool broke = (dir > 0) ? (d[j].close > level * (1.0 + need))
                                   : (d[j].close < level * (1.0 - need));
            if(broke)
            {
               c.kind    = 2;
               c.idx     = j;
               c.time    = d[j].time;
               c.prevIdx = 0;
               c.level   = level;
               c.extreme = (dir > 0) ? d[j].low : d[j].high;
               return true;
            }
         }
      }
      return false;
   }

   //--- "a break of a well-respected trendline": the line through the two most recent
   //--- same-side swings, broken by a completed close
   bool CatalystLineBreak(const MqlRates &d[], const int got, const int dir, SCatalyst &c)
   {
      double px[16]; int ix[16];
      int n = (dir > 0) ? PivotHighs(d, got, InpLineSwingSide, px, ix) : PivotLows(d, got, InpLineSwingSide, px, ix);
      if(n < 2) return false;
      if(dir > 0 && !(px[0] < px[1])) return false;        // a falling resistance line, broken upward
      if(dir < 0 && !(px[0] > px[1])) return false;        // a rising support line, broken downward (the worked example)
      double p0 = px[0], p1 = px[1];
      long   t0 = (long)d[ix[0]].time, t1 = (long)d[ix[1]].time;
      if(t1 == t0) return false;
      double tol = InpLineTolPct / 100.0;
      int touches = 2;
      for(int k = 2; k < n; k++)
      {
         double line = p0 + (p1 - p0) * (double)((long)d[ix[k]].time - t0) / (double)(t1 - t0);
         if(line > 0.0 && MathAbs(px[k] - line) / line <= tol) touches++;
      }
      if(touches < 2) return false;
      for(int j = 1; j <= ix[0] && j <= InpMaxBarsSinceCat; j++)
      {
         double line = p0 + (p1 - p0) * (double)((long)d[j].time - t0) / (double)(t1 - t0);
         if(line <= 0.0) continue;
         double need = InpBreakClosePct / 100.0;
         bool broke = (dir > 0) ? (d[j].close > line * (1.0 + need)) : (d[j].close < line * (1.0 - need));
         if(broke)
         {
            c.kind    = 3;
            c.idx     = j;
            c.time    = d[j].time;
            c.prevIdx = 0;
            c.level   = line;
            c.extreme = (dir > 0) ? d[j].low : d[j].high;
            return true;
         }
      }
      return false;
   }

   //+----------------------------------------------------------------+
   //| S2: "without meaningful displacement, there is no evidence"     |
   //+----------------------------------------------------------------+
   bool DisplacementOk(const SEAContext &ctx, const MqlRates &d[], const int got, const SCatalyst &c, const int dir)
   {
      if(c.idx <= 1) return false;

      //--- the leg after the catalyst: "a decisive move away from that area"
      double best = 0.0;
      double body = 0.0;
      for(int i = c.idx - 1; i >= 1 && i < got; i--)
      {
         double move = (dir > 0) ? (d[i].high - c.level) : (c.level - d[i].low);
         if(move > best) best = move;
         double b = (dir > 0) ? (d[i].close - d[i].open) : (d[i].open - d[i].close);
         if(b > body) body = b;
      }
      if(best < InpDisplaceAtr * ctx.atr) return false;     // "a decisive move"
      if(body < InpDisplaceBodyAtr * ctx.atr) return false; // "a noticeable shift in price behavior"

      //--- "a break in the prior swing structure"
      double prior = PriorSwing(d, got, c.idx, InpSwingSide, dir);
      if(prior <= 0.0) return false;
      if(dir > 0 && !(best > prior - c.level)) return false;   // "a break in the prior swing structure"
      if(dir < 0 && !(best > c.level - prior)) return false;
      return true;
   }

   //+----------------------------------------------------------------+
   //| S3: the confluence zone and its factor count                    |
   //+----------------------------------------------------------------+
   int ConfluenceCount(const SEAContext &ctx, const MqlRates &d[], const int got, const SCatalyst &c,
                       const int dir, const double level, const double cluster, double &zoneLow, double &zoneHigh)
   {
      zoneLow  = level - cluster;
      zoneHigh = level + cluster;
      int count = 1;                                        // the catalyst level itself

      //--- "a fair value gap": a three-candle gap inside the displacement leg (bars
      //--- 1..c.idx-1) that overlaps the zone
      for(int k = c.idx - 1; k >= 3 && dir > 0; k--)
      {
         if(!(d[k - 2].high <= d[k].low)) continue;         // a bullish gap inside the leg
         if(d[k - 2].high <= zoneHigh && d[k].low >= zoneLow) { count++; break; }
      }
      for(int k = c.idx - 1; k >= 3 && dir < 0; k--)
      {
         if(!(d[k - 2].low >= d[k].high)) continue;         // a bearish gap inside the leg
         if(d[k - 2].low >= zoneLow && d[k].high <= zoneHigh) { count++; break; }
      }

      //--- "an order block": the last opposing candle before the leg, inside the zone
      for(int k = c.idx; k <= c.idx + 6 && k < got; k++)
      {
         bool opposing = (dir > 0) ? (d[k].close < d[k].open) : (d[k].close > d[k].open);
         if(!opposing) continue;
         double mid = (d[k].high + d[k].low) / 2.0;
         if(mid >= zoneLow && mid <= zoneHigh) count++;
         break;
      }

      //--- "a moving average used as dynamic support/resistance" (the worked example's 21 EMA)
      SEmaPair es;
      if(EmaPair(ctx.symbol, es))
      {
         double ema = EmaVal(es.hEma21, 1);
         if(ema > 0.0 && ema >= zoneLow && ema <= zoneHigh) count++;
         //--- "higher-timeframe alignment"
         double htf = EmaVal(es.hHtf, 1);
         MqlRates dd[];
         int dg = EA_Rates(ctx.symbol, PERIOD_D1, 1, 1, dd);
         if(htf > 0.0 && dg >= 1)
         {
            if(dir > 0 && dd[0].close > htf) count++;
            if(dir < 0 && dd[0].close < htf) count++;
         }
      }

      //--- "a previous swing level"
      double px[16]; int ix[16];
      int n = (dir > 0) ? PivotLows(d, got, InpSwingSide, px, ix) : PivotHighs(d, got, InpSwingSide, px, ix);
      for(int i = 0; i < n; i++)
         if(px[i] >= zoneLow && px[i] <= zoneHigh) { count++; break; }

      //--- "divergence": at a sweep, price took the older equal level out but the RSI did not confirm it
      if(c.kind == 1 && c.prevIdx >= 1 && c.prevIdx <= c.idx)
      {
         int h = RsiHandle(ctx.symbol);
         double rs[];
         if(h != INVALID_HANDLE && EA_BufN(h, 0, 1, c.idx, rs) == c.idx)
         {
            double nowRsi = rs[c.idx - 1];
            double oldRsi = rs[c.prevIdx - 1];
            if(dir > 0 && d[c.idx].low < d[c.prevIdx].low && nowRsi > oldRsi) count++;
            if(dir < 0 && d[c.idx].high > d[c.prevIdx].high && nowRsi < oldRsi) count++;
         }
      }
      return count;
   }

   //+----------------------------------------------------------------+
   //| The story, end to end                                           |
   //+----------------------------------------------------------------+
   bool PlanStory(const SEAContext &ctx, const MqlRates &d[], const int got, const int dir,
                  SSignalPlan &p, double &zoneOut)
   {
      //--- S1: the freshest of the three catalysts wins
      SCatalyst c; c.kind = 0; c.idx = 0; c.time = 0; c.prevIdx = 0; c.level = 0.0; c.extreme = 0.0;
      SCatalyst cand;
      if(CatalystSweep(d, got, dir, cand) && (c.kind == 0 || cand.idx < c.idx)) c = cand;
      if(CatalystLevelBreak(d, got, dir, cand) && (c.kind == 0 || cand.idx < c.idx)) c = cand;
      if(CatalystLineBreak(d, got, dir, cand) && (c.kind == 0 || cand.idx < c.idx)) c = cand;
      if(c.kind == 0 || c.level <= 0.0) return false;

      //--- the story is current: no re-arming on a story already traded
      if(ArmedSeen(ctx.symbol, dir, c.time)) return false;

      //--- S2
      if(!DisplacementOk(ctx, d, got, c, dir)) return false;

      //--- S3
      double cluster = InpZoneClusterPct / 100.0 * c.level;
      double zoneLow = 0.0, zoneHigh = 0.0;
      int confluence = ConfluenceCount(ctx, d, got, c, dir, c.level, cluster, zoneLow, zoneHigh);
      if(confluence < InpMinConfluence) return false;

      //--- the entry: the proximal edge of the zone - "entries are taken only on the retracement"
      double entry = (dir > 0) ? zoneHigh : zoneLow;
      if(entry <= 0.0) return false;
      if(dir > 0 && entry >= ctx.ask) entry = ctx.ask;      // already inside the zone: take it now
      if(dir < 0 && entry <= ctx.bid) entry = ctx.bid;

      //--- S4: "beyond the level that proves the narrative wrong", buffered minimally
      double far = (dir > 0) ? MathMin(zoneLow, c.extreme) : MathMax(zoneHigh, c.extreme);
      double stop = (dir > 0) ? far - InpStopBufferAtr * ctx.atr : far + InpStopBufferAtr * ctx.atr;
      if(stop <= 0.0) return false;
      if(dir > 0 && !(stop < entry)) return false;
      if(dir < 0 && !(stop > entry)) return false;
      double risk = MathAbs(entry - stop);
      if(risk <= 0.0) return false;
      if(risk > entry * InpMaxStopPct / 100.0) return false;

      //--- S5: "markets move from one liquidity zone to the next"
      double tgt = TargetPool(d, got, dir, entry, risk);
      if(tgt <= 0.0) return false;
      if(dir > 0 && !(tgt > entry)) return false;
      if(dir < 0 && !(tgt < entry)) return false;

      p.dir      = dir;
      p.entry    = entry;
      p.stop     = stop;
      p.target   = tgt;
      p.riskDist = risk;
      p.barsAgo  = c.idx;
      p.isLimit  = true;
      p.expiry   = TimeTradeServer() + (datetime)(InpZoneLifeBars * PeriodSeconds(g_eaIndTf));
      //--- "when several elements point in the same direction, the trade idea becomes valid"
      p.score = 80.0 + 3.0 * (double)confluence;
      p.reason = StringFormat("story %s: %s at %.5f (bar %d), displacement %.2f ATR, retracement zone %.5f-%.5f with %d confluences, stop %.5f, pool target %.5f",
                              (dir > 0 ? "LONG" : "SHORT"),
                              (c.kind == 1 ? "sweep of equal levels" : (c.kind == 2 ? "level break" : "trendline break")),
                              c.level, c.idx, InpDisplaceAtr, zoneLow, zoneHigh, confluence, stop, tgt);
      zoneOut = c.level;
      ArmedStore(ctx.symbol, dir, c.time);
      return true;
   }

   //--- the next liquidity pool: the nearest prior swing beyond the minimum distance
   double TargetPool(const MqlRates &d[], const int got, const int dir, const double entry, const double risk)
   {
      double px[16]; int ix[16];
      int n = (dir > 0) ? PivotHighs(d, got, InpTargetSwingSide, px, ix) : PivotLows(d, got, InpTargetSwingSide, px, ix);
      double best = 0.0;
      for(int i = 0; i < n; i++)
      {
         if(dir > 0 && px[i] > entry + InpMinTargetR * risk)
         {
            if(best == 0.0 || px[i] < best) best = px[i];
         }
         if(dir < 0 && px[i] < entry - InpMinTargetR * risk)
         {
            if(best == 0.0 || px[i] > best) best = px[i];
         }
      }
      if(best > 0.0) return best;
      return (dir > 0) ? entry + InpTargetR * risk : entry - InpTargetR * risk;
   }

   //+----------------------------------------------------------------+
   //| State: the zone a fill adopts, the pending slot, the memory of  |
   //| a story already traded, and the housekeeping                     |
   //+----------------------------------------------------------------+
   string K(const string sym, const string tag) { return "CFUNI_" + IntegerToString((long)g_eaCfg.magic) + "_" + sym + tag; }
   string T(const ulong ticket, const string tag) { return "CFUNI_" + IntegerToString((long)g_eaCfg.magic) + "_" + IntegerToString((long)ticket) + tag; }
   bool TagExists(const ulong ticket, const string tag) { return GlobalVariableCheck(T(ticket, tag)); }

   void PendingStore(const string sym, const int dir, const double level)
   {
      GlobalVariableSet(K(sym, "_PST"), (double)(long)TimeTradeServer());
      GlobalVariableSet(K(sym, "_PL"), level);
      GlobalVariableSet(K(sym, "_PD"), (double)dir);
   }
   bool PendingFresh(const string sym)
   {
      if(!GlobalVariableCheck(K(sym, "_PST"))) return false;
      datetime stamp = (datetime)GlobalVariableGet(K(sym, "_PST"));
      return (TimeTradeServer() - stamp <= (datetime)3600);
   }
   void PendingClear(const string sym)
   {
      GlobalVariableDel(K(sym, "_PST"));
      GlobalVariableDel(K(sym, "_PL"));
      GlobalVariableDel(K(sym, "_PD"));
   }

   //--- the story ledger: a catalyst already armed once is not armed twice
   bool ArmedSeen(const string sym, const int dir, const datetime stamp)
   {
      string tag = (dir > 0) ? "_AL" : "_AS";
      if(!GlobalVariableCheck(K(sym, tag))) return false;
      return ((datetime)GlobalVariableGet(K(sym, tag)) == stamp);
   }
   void ArmedStore(const string sym, const int dir, const datetime stamp)
   {
      string tag = (dir > 0) ? "_AL" : "_AS";
      GlobalVariableSet(K(sym, tag), (double)(long)stamp);
      GlobalVariableSet(K(sym, (dir > 0) ? "_ALT" : "_AST"), (double)(long)TimeTradeServer());
   }

   void PruneState()
   {
      string prefix = "CFUNI_" + IntegerToString((long)g_eaCfg.magic) + "_";
      int plen = StringLen(prefix);
      for(int g = GlobalVariablesTotal() - 1; g >= 0; g--)
      {
         string name = GlobalVariableName(g);
         if(StringFind(name, prefix) != 0) continue;
         int sep = StringFind(name, "_", plen);
         if(sep < 0) continue;
         string id  = StringSubstr(name, plen, sep - plen);
         string tag = StringSubstr(name, sep + 1);
         if(tag == "PST" || tag == "PL" || tag == "PD")
         {
            if(tag != "PST" && GlobalVariableCheck(K(id, "_PST")) &&
               TimeTradeServer() - (datetime)GlobalVariableGet(K(id, "_PST")) > (datetime)3600)
               PendingClear(id);
            else if(tag == "PST" && !GlobalVariableCheck(K(id, "_PL")))
               GlobalVariableDel(name);
            continue;
         }
         if(tag == "AL" || tag == "AS")
         {
            string stampKey = K(id, (tag == "AL") ? "_ALT" : "_AST");
            if(GlobalVariableCheck(stampKey) &&
               TimeTradeServer() - (datetime)GlobalVariableGet(stampKey) > (datetime)(3 * 86400))
            {
               GlobalVariableDel(stampKey);
               GlobalVariableDel(name);
            }
            continue;
         }
         if(tag == "ALT" || tag == "AST")
         {
            if(!GlobalVariableCheck(K(id, (tag == "ALT") ? "_AL" : "_AS"))) GlobalVariableDel(name);
            continue;
         }
         if(tag != "Z" && tag != "D") continue;
         ulong ticket = (ulong)StringToInteger(id);
         if(ticket == 0) continue;
         if(!PositionSelectByTicket(ticket)) GlobalVariableDel(name);
      }
   }
};

CCfUniversalStrategy g_cfUniversalStrategy;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfUniversalStrategy);
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
