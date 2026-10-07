//+------------------------------------------------------------------+
//|                                       EA_CF_GammaReversal.mq5    |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| ChartFanatics / Freddy Siento: "STEAL This INSANE 1-Minute Market |
//| Maker Trading Strategy (75% Win Rate)"                             |
//| Card    : chartfanatics/todos/                                     |
//|           institutional-options-flow-gamma-reversal-strategy.md    |
//|           (#14)                                                    |
//| Source  : chartfanatics/glimpse/35cyqDz-ej8.md                     |
//| Magic   : 3218                                                     |
//|                                                                    |
//| WHAT THE DOC SAYS AND WHAT AN EA CAN KNOW                         |
//|                                                                    |
//| The edge is options positioning: dealers hedge zero-DTE inventory  |
//| through futures, so the biggest gamma (open-interest) strikes are   |
//| price magnets where the hedging pressure runs out and price          |
//| reverses.  "Identify the maximum put gamma and call gamma levels     |
//| using 90-day open interest" - that data lives on an options          |
//| platform (the video names Guestbot), NOT in MetaTrader.              |
//|                                                                    |
//| So the levels are INPUTS the trader reads off the platform - the     |
//| video's own action item - and the EA mechanizes everything the       |
//| document does state mechanically:                                    |
//|                                                                    |
//|   * reversal entries AT a wall: price taps the level and the M1 bar  |
//|     closes back off it with a rejection wick, confirmed by above-    |
//|     average volume (the doc's "combine gamma levels with order flow  |
//|     or footprint analysis to confirm" - the engine's available       |
//|     proxy);                                                          |
//|   * "Set stop losses at 30-50 ticks" -> the stop sits InpStopTicks    |
//|     beyond the wall;                                                  |
//|   * "target the next gamma level" -> the next level from the          |
//|     InpGammaLevels list, else the doc's 300-400 tick band;            |
//|   * "use 2-3 contracts to allow partial profit-taking while keeping    |
//|     one contract running" -> the engine's partial + trailing runner;   |
//|   * "Risk 30-50 ticks ($150-200)" -> dollar risk converted to the     |
//|     engine's percent sizing at init;                                  |
//|   * "Trade only the first two hours after market open (9:30-11:30     |
//|     ET) ... avoid trading late in the day" -> the session window and  |
//|     a flat-at-window-end rule;                                        |
//|   * "Avoid OPEX (third Friday), triple witching (Mar/Jun/Sep/Dec)     |
//|     and spiration days (30 days before OPEX)" -> calendar gates the   |
//|     EA computes itself;                                               |
//|   * "Take 2 days off after a stop loss" -> the EA refuses new         |
//|     entries for that many days after its own last losing close.       |
//|                                                                    |
//| `[interpretation]`: "spiration" is not a standard term - it is read   |
//| verbatim as a day 30 calendar days before a monthly OPEX; the         |
//| approach/reclaim tolerances in ticks and the volume-confirmation      |
//| multiple are inputs because the video gives no numbers; the flat at   |
//| the window end reflects "avoid trading late in the day" (charm        |
//| dominates after lunch).                                               |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics gamma reversal - wall reversal entries in the first two hours, OPEX/witching/spiration aware"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade   = "US100,US500";        // NQ / ES / SPX (source); broker naming applies
input ulong             InpMagicNumber      = 3218;                 // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskUsd          = 200.0;                // "Risk 30-50 ticks ($150-200)" per trade (0 = use InpRiskPctFallback)
input double            InpRiskPctFallback  = 0.50;                 // Used only when InpRiskUsd is 0
input int               InpStage             = 5;                   // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input int               InpServerGmtOffset  = 2;                    // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;        // Log verbosity
input double            InpCommissionPerLotRT = 0.0;                // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.10;               // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;               // Write the engine evidence ledger CSV
//--- the levels (read off the options platform, the video's own action item)
input double InpPutWall        = 0.0;   // Maximum PUT gamma level (put wall; 0 = not traded today)
input double InpCallWall       = 0.0;   // Maximum CALL gamma level (call wall; 0 = not traded today)
input string InpGammaLevels    = "";    // Next gamma / positive-convexity levels, comma separated (targets)
//--- the document's numbers
input int    InpStopTicks      = 40;    // "stop losses at 30-50 ticks" beyond the wall
input int    InpTargetTicks    = 350;   // "300-400 ticks" when no next level is listed
input int    InpApproachTicks  = 25;    // `[interpretation]` how close to the wall counts as "at the level"
input int    InpReclaimTicks   = 5;     // `[interpretation]` close back beyond the wall by this many ticks
input double InpWickRatio      = 0.30;  // rejection wick the entry bar must show (engine EA_WickRatio)
input double InpVolMult        = 1.20;  // order-flow confirmation: bar volume >= x the M1 average
input int    InpVolLookback    = 20;    // the average is taken over this many M1 bars
//--- the document's rules
input int    InpWindowStartHour   = 14; // "first two hours after market open (9:30-11:30 ET)" in London clock
input int    InpWindowStartMin    = 30;
input int    InpWindowEndHour     = 16; // 11:30 ET
input int    InpWindowEndMin      = 30;
input int    InpMaxTradesPerDay   = 2;  // "1-2 high-probability setups per day"
input bool   InpSkipOpex          = true;  // "Avoid OPEX and Triple Witching Days"
input bool   InpSkipSpiration     = true;  // "spiration days (30 days before OPEX)"
input int    InpDaysOffAfterLoss  = 2;     // "Take 2 days off after a stop loss"
input double InpPartial1AtR       = 2.0;   // `[interpretation]` scale-out level for the 3-contract structure
input bool   InpFlatAtWindowEnd   = true;  // "avoid trading late in the day" - intraday reversals do not run into charm

//+------------------------------------------------------------------+
class CCfGammaReversal : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_GAMMA_REVERSAL";
      cfg.sourceDoc             = "chartfanatics/glimpse/35cyqDz-ej8.md (card #14)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      //--- "Risk 30-50 ticks ($150-200)" - the fixed dollar risk becomes the engine's percent
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double riskPct = InpRiskPctFallback;
      if(InpRiskUsd > 0.0 && equity > 0.0) riskPct = InpRiskUsd / equity * 100.0;
      cfg.riskPct               = MathMin(riskPct, 2.0);             // hard safety clamp
      cfg.signalTimeframe       = PERIOD_M1;                        // the video's 1-minute chart
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = 3.0;
      cfg.dailyLossPct          = 1.50;
      cfg.weeklyLossPct         = 3.0;
      cfg.totalDdPct            = 8.0;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 60;
      //--- "first two hours after market open (9:30-11:30 ET)" = 14:30-16:30 London in the cash session
      cfg.sessionStartHour      = InpWindowStartHour;  cfg.sessionStartMin = InpWindowStartMin;
      cfg.sessionEndHour        = InpWindowEndHour;    cfg.sessionEndMin   = InpWindowEndMin;
      cfg.noTradeAfterHour      = InpWindowEndHour;    cfg.noTradeAfterMin = MathMax(0, InpWindowEndMin - 10);
      cfg.fridayFlat            = false;                            // OPEX/witching days are handled by the calendar gate
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = false;
      cfg.breakEvenAtR          = 1.0;
      cfg.partial1AtR           = InpPartial1AtR;  cfg.partial1Pct = 50.0;
      cfg.trailAtR              = 3.0;                              // the runner "keeps one contract running to capture larger moves"
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_gamma_ledger.csv";
      cfg.newsFilter            = false;
      cfg.logLevel              = InpLogLevel;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   void OnInitStrategy()
   {
      m_levelCount = 0;
      ParseLevels();
      m_lockDay      = 0;
      m_lockLogged   = false;
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "gamma reversal armed: put wall %.2f, call wall %.2f, %d target levels; stop %d ticks, target %d ticks (next level preferred)",
             InpPutWall, InpCallWall, m_levelCount, InpStopTicks, InpTargetTicks), true);
      EA_Log(EA_LOG_EVENTS, "levels come from the options platform (the video's action item); the EA trades reversals at them", true);
   }

   //--- the document's own calendar and discipline rules are admissibility gates
   bool AllowTrading(SEAContext &ctx)
   {
      if(InpSkipOpex && (IsOpexDate(ctx.nowClock) || IsWitchingDate(ctx.nowClock)))
      {
         LogOnce(ctx.nowClock, "OPEX / triple-witching day - the document says skip: hedging is chaotic");
         return false;
      }
      if(InpSkipSpiration && IsSpirationDate(ctx.nowClock))
      {
         LogOnce(ctx.nowClock, "spiration day (30 days before OPEX) - the document says skip");
         return false;
      }
      if(PostLossLockActive(ctx.nowClock))
      {
         LogOnce(ctx.nowClock, StringFormat("%d days off after a stop loss - the document's cortisol rule", InpDaysOffAfterLoss));
         return false;
      }
      return true;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession) return false;
      if(InpPutWall <= 0.0 && InpCallWall <= 0.0) return false;
      double tick = SymbolInfoDouble(ctx.symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tick <= 0.0) return false;

      MqlRates m[];
      if(EA_Rates(ctx.symbol, g_eaIndTf, 0, 3, m) < 2) return false;
      double avgVol = AverageVolume(ctx.symbol);

      //--- put wall = the long reversal (price rejected at the wall and closes back above it)
      if(InpPutWall > 0.0 && WallsPlanOk(ctx, m[1], +1, InpPutWall, tick, avgVol, plan)) return true;
      //--- call wall = the short reversal
      if(InpCallWall > 0.0 && WallsPlanOk(ctx, m[1], -1, InpCallWall, tick, avgVol, plan)) return true;
      return false;
   }

   //--- "avoid trading late in the day": the reversals are intraday, charm takes over after lunch
   void Manage(SEAContext &ctx)
   {
      if(!InpFlatAtWindowEnd) return;
      if(ctx.clockMinutes < InpWindowEndHour * 60 + InpWindowEndMin) return;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;
         if(g_eaExec.Close(ticket, "window over - charm phase starts"))
            EA_Log(EA_LOG_EVENTS, "first two hours over: position closed (avoid trading late in the day)", true);
      }
   }

private:
   double   m_levels[128];       // parsed gamma / convexity target levels
   int      m_levelCount;
   datetime m_lockDay;
   bool     m_lockLogged;

   //-------------------------------------------------------------------
   // The wall reverse: tap the level, reject, confirm with volume
   //-------------------------------------------------------------------
   bool WallsPlanOk(SEAContext &ctx, const MqlRates &bar, const int dir, const double wall,
                    const double tick, const double avgVol, SSignalPlan &plan)
   {
      double tol     = InpApproachTicks * tick;
      double reclaim = InpReclaimTicks * tick;

      //--- price must come TO the level ("wait for the level, enter"): the bar reached it (a deeper
      //--- spike through the wall that still closes back is the classic reversal, not a failure)
      bool tapped = (dir > 0) ? (bar.low <= wall + tol) : (bar.high >= wall - tol);
      if(!tapped) return false;

      //--- the reversal: the bar closes back off the wall with a rejection wick
      bool reclaimed = (dir > 0) ? (bar.close > wall + reclaim) : (bar.close < wall - reclaim);
      if(!reclaimed) return false;
      if(EA_WickRatio(bar, dir) < InpWickRatio) return false;         // engine wick geometry (reuse)
      if(avgVol > 0.0 && (double)bar.tick_volume < InpVolMult * avgVol) return false;   // order-flow proxy

      double entry = (dir > 0) ? ctx.ask : ctx.bid;
      //--- "Set stop losses at 30-50 ticks" - beyond the wall
      double stop  = (dir > 0) ? wall - InpStopTicks * tick : wall + InpStopTicks * tick;
      double risk  = (dir > 0) ? entry - stop : stop - entry;
      if(risk <= 0.0) return false;

      //--- "target the next gamma level" - the nearest listed level beyond the risk distance
      double target = NextLevel(entry, dir, risk, tick);
      if(target <= 0.0)
         target = (dir > 0) ? entry + InpTargetTicks * tick : entry - InpTargetTicks * tick;
      if(dir > 0 && target <= entry + risk) return false;              // never a sub-1R destination
      if(dir < 0 && target >= entry - risk) return false;

      plan.dir = dir; plan.entry = entry; plan.stop = stop; plan.target = target;
      plan.riskDist = risk; plan.barsAgo = 1; plan.score = 75.0; plan.isLimit = false;
      plan.reason = StringFormat("%s wall reversal at %.2f (vol x%.2f)",
                                 dir > 0 ? "put" : "call", wall, (avgVol > 0.0) ? bar.tick_volume / avgVol : 0.0);
      return true;
   }

   //--- the next listed gamma / positive-convexity level in the trade's direction
   double NextLevel(const double entry, const int dir, const double risk, const double tick)
   {
      double best = 0.0;
      for(int i = 0; i < m_levelCount; i++)
      {
         double lvl = m_levels[i];
         if(dir > 0)
         {
            if(lvl <= entry + risk + 2.0 * tick) continue;             // must clear the risk distance
            if(best == 0.0 || lvl < best) best = lvl;                  // the NEAREST next level
         }
         else
         {
            if(lvl >= entry - risk - 2.0 * tick) continue;
            if(best == 0.0 || lvl > best) best = lvl;
         }
      }
      return best;
   }

   double AverageVolume(const string sym)
   {
      MqlRates m[];
      int got = EA_Rates(sym, g_eaIndTf, 0, InpVolLookback + 1, m);
      if(got < 3) return 0.0;
      double sum = 0.0;
      for(int i = 1; i < got; i++) sum += (double)m[i].tick_volume;    // completed bars only
      return sum / (got - 1);
   }

   void ParseLevels()
   {
      m_levelCount = 0;
      string parts[];
      if(StringLen(InpGammaLevels) <= 0) return;
      int n = StringSplit(InpGammaLevels, ',', parts);
      for(int i = 0; i < n && m_levelCount < 128; i++)
      {
         string v = parts[i];
         StringTrimLeft(v); StringTrimRight(v);
         if(StringLen(v) <= 0) continue;
         double lvl = StringToDouble(v);
         if(lvl > 0.0) m_levels[m_levelCount++] = lvl;
      }
   }

   //-------------------------------------------------------------------
   // "Take 2 days off after a stop loss" - this EA's own deal history
   //-------------------------------------------------------------------
   bool PostLossLockActive(const datetime now)
   {
      if(InpDaysOffAfterLoss <= 0) return false;
      datetime from = now - (datetime)((InpDaysOffAfterLoss + 3) * 86400);
      if(!HistorySelect(from, now + 60)) return false;
      datetime lastLoss = 0;
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagicNumber) continue;
         long kind = HistoryDealGetInteger(t, DEAL_ENTRY);
         if(kind != DEAL_ENTRY_OUT && kind != DEAL_ENTRY_OUT_BY && kind != DEAL_ENTRY_INOUT) continue;
         double p = HistoryDealGetDouble(t, DEAL_PROFIT) +
                    HistoryDealGetDouble(t, DEAL_SWAP) +
                    HistoryDealGetDouble(t, DEAL_COMMISSION);
         if(p >= 0.0) continue;
         datetime when = (datetime)HistoryDealGetInteger(t, DEAL_TIME);
         if(when > lastLoss) lastLoss = when;
      }
      if(lastLoss <= 0) return false;
      return (now - lastLoss) < (datetime)(InpDaysOffAfterLoss * 86400);
   }

   //-------------------------------------------------------------------
   // Calendar gates: OPEX (third Friday), triple witching, spiration
   //-------------------------------------------------------------------
   datetime ThirdFriday(const int year, const int month)
   {
      MqlDateTime dt;
      dt.year = year; dt.mon = month; dt.day = 1;
      dt.hour = 0; dt.min = 0; dt.sec = 0; dt.day_of_week = 0; dt.day_of_year = 0;
      datetime first = StructToTime(dt);
      MqlDateTime f;
      if(!TimeToStruct(first, f)) return 0;
      int offset = (5 - f.day_of_week + 7) % 7;      // 5 = Friday in MQL5 (0 = Sunday)
      return first + (datetime)(offset + 14) * 86400;
   }

   bool IsOpexDate(const datetime clockTime)
   {
      MqlDateTime dt;
      if(!TimeToStruct(clockTime, dt)) return false;
      datetime third = ThirdFriday(dt.year, dt.mon);
      if(third <= 0) return false;
      datetime dayStart = clockTime - (datetime)(dt.hour * 3600 + dt.min * 60 + dt.sec);
      return (dayStart == third);
   }

   bool IsWitchingDate(const datetime clockTime)
   {
      MqlDateTime dt;
      if(!TimeToStruct(clockTime, dt)) return false;
      if(dt.mon != 3 && dt.mon != 6 && dt.mon != 9 && dt.mon != 12) return false;
      return IsOpexDate(clockTime);
   }

   //--- `[interpretation]`: the document's "spiration days (30 days before OPEX)", read verbatim
   bool IsSpirationDate(const datetime clockTime)
   {
      MqlDateTime dt;
      if(!TimeToStruct(clockTime, dt)) return false;
      datetime dayStart = clockTime - (datetime)(dt.hour * 3600 + dt.min * 60 + dt.sec);
      datetime plus30   = dayStart + (datetime)(30 * 86400);
      MqlDateTime p;
      if(!TimeToStruct(plus30, p)) return false;
      datetime third = ThirdFriday(p.year, p.mon);
      return (third > 0 && plus30 == third);
   }

   void LogOnce(const datetime now, const string why)
   {
      MqlDateTime dt, ld;
      if(!TimeToStruct(now, dt)) return;
      if(m_lockLogged && m_lockDay > 0 && TimeToStruct(m_lockDay, ld) &&
         ld.year == dt.year && ld.mon == dt.mon && ld.day == dt.day)
         return;                                    // one line per rule per day, never per tick
      m_lockDay = now;
      m_lockLogged = true;
      EA_Log(EA_LOG_EVENTS, "gamma reversal stands aside: " + why, true);
   }
};

CCfGammaReversal g_cfGammaReversal;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfGammaReversal);
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
