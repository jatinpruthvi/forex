//+------------------------------------------------------------------+
//|                                    EA_CF_TrendlineStrategy.mq5    |
//|                                  Copyright 2026, Master Strategy  |
//|                                                                   |
//| ChartFanatics: Trendline Strategy (Tori Trade)                     |
//| "Tori Trade's Playbook" - Apr 2025, Futures / Crypto / Forex       |
//| Card    : chartfanatics/todos/trendline-strategy.md         (#41)  |
//| Source  : chartfanatics/pdf/trendline-strategy.pdf                 |
//| Magic   : 3244                                                    |
//|                                                                   |
//| "This method relies on two key concepts - the Action Line and the  |
//|  Safety Line to guide entries, exits, and trailing stops."         |
//|                                                                   |
//|   S1  THE FRAME: "This strategy works best on the 4-hour          |
//|       timeframe ... A top-down look at bigger timeframes, like the |
//|       daily or weekly, helps confirm the main trend direction."    |
//|   S2  THE LINES: the Action Line is where you enter (the trendline |
//|       price touches - bounce - or the trendline price must break   |
//|       through - break); the Safety Line is where you exit if the   |
//|       trade fails ("for bounce setups, the action line and safety  |
//|       line are the same"; for breaks "a new opposing trendline is  |
//|       drawn as the safety line").                                  |
//|   S3  TRENDLINE BOUNCE: "the trendline must have at least two or   |
//|       three clear touchpoints before entry", "at least one week of |
//|       price data from the first touchpoint to the intended entry", |
//|       "enter when the price reaches or tests the trendline", the   |
//|       line itself is the stop - "if the price closes through the   |
//|       line, the position is closed immediately" - and "the stop    |
//|       can be trailed along the trendline as the price creates new  |
//|       valid swing points".  "Stops should not be placed exactly at |
//|       the entry ... enough room so normal price wicks don't stop   |
//|       you out too early."                                          |
//|   S4  TRENDLINE BREAK: "the action line must have two clear        |
//|       touchpoints before the break" (2T) or "three or more" (3T),  |
//|       "about one week of price data between the first touchpoint   |
//|       and the break", entry "when the price breaks the action line |
//|       and there is a clear safety line to protect the trade" ("if  |
//|       there is no safety line when the break happens, wait until   |
//|       price forms a clear high or low to draw one"), and "the      |
//|       break must happen close to the safety line so the risk stays |
//|       tight.  If it's too far, skip the trade."                    |
//|   S5  INVALIDATION: "If the price moves back and closes beyond the |
//|       safety line, the trade is invalid and must be closed."        |
//|   S6  BOOKKEEPING: "Track all 2 touchpoint breaks separately from  |
//|       3 touchpoints breaks" - the two score differently and both    |
//|       are named in the ledger.                                     |
//|                                                                   |
//| `[interpretation]`: the pivot width, the line tolerance and the    |
//| touch-test tolerance, the minimum touch span (a week is stated;     |
//| days are the unit), the break buffer, the entry-freshness window    |
//| around the break, the stop buffer behind the line, the stop-width   |
//| cap, the maximum safety-line risk percentage ("close to the safety  |
//| line" made numeric), the daily alignment period and the far TP      |
//| placeholder are inputs and labelled.                                |
//|                                                                   |
//| Disclosed, not faked: "manually drawn trendlines" are drawn here    |
//| by rule - the line through the two most recent same-side swings,    |
//| extended forward - because an EA cannot read a hand-drawn object;   |
//| the document's "frequent false breaks" caveat is handled by the     |
//| touchpoint gate (more touchpoints = more reliable) and by the       |
//| close-through requirement, which ignores pure wick breaks.          |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics Trendline Strategy - the Action Line and the Safety Line: trendline bounces and 2T/3T trendline breaks with a line-trailed stop"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade     = "XAUUSD,XAGUSD";   // Universe (the playbook likes metals/commodities that respect lines)
input ulong             InpMagicNumber        = 3244;             // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct            = 0.50;             // Risk per trade (% of equity)
input int               InpStage              = 5;                // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input double            InpMaxSpreadPoints    = 40.0;             // Spread gate in points (0 = off)
input double            InpDailyLossPct       = 2.00;             // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset    = 2;                // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel           = EA_LOG_EVENTS;    // Log verbosity
input double            InpCommissionPerLotRT = 0.0;              // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.15;             // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;             // Write the engine evidence ledger CSV

//--- S1: the frame
input int               InpPivotSide          = 2;                // [interpretation] Bars each side of a swing point
input int               InpScanBars           = 200;              // [interpretation] The trendline search window
input bool              InpRequireDailyAlign  = false;            // "a top-down look ... helps confirm the main trend direction"
input int               InpDailyMaPeriod      = 50;               // [interpretation] The daily trend reference

//--- the lines
input double            InpLineTolPct         = 0.25;             // [interpretation] How close counts as touching the line
input int               InpMinTouchpoints     = 2;                // "at least two or three clear touchpoints before entry"
input int               InpMinTouchSpanDays   = 7;                // "at least one week of price data from the first touchpoint"

//--- S3: the bounce setup
input bool              InpUseBounce          = true;             // "The bounce setup aims to enter when the price touches and respects an existing trendline"
input double            InpTouchTestPct       = 0.15;             // [interpretation] How close to the line counts as "reaches or tests"
input double            InpStopBufferAtr      = 0.50;             // "enough room so normal price wicks don't stop you out too early"
input double            InpMaxStopPct         = 4.00;             // [interpretation] Reject stops wider than x% of price
input bool              InpTrailAlongLine     = true;             // "The stop can be trailed along the trendline"

//--- S4: the break setup
input bool              InpUseBreak           = true;             // "enter when the price breaks through an established trendline"
input double            InpBreakClosePct      = 0.05;             // [interpretation] A close beyond the line by x% = the break
input int               InpBreakFreshBars     = 6;                // [interpretation] "wait until price forms a clear high or low to draw one"
input double            InpMaxLineRiskPct     = 1.50;             // "the break must happen close to the safety line ... if it's too far, skip"

//--- management
input bool              InpUseLineExit        = true;             // "if the price closes through the line, the position is closed immediately"
input double            InpTargetR            = 8.0;              // [interpretation] Far TP placeholder - the safety line is the exit
input int               InpMaxTradesPerDay    = 3;                // Setups are rare - few attempts

//+------------------------------------------------------------------+
struct SLine
{
   datetime t0, t1;      // the two anchor points in time/price space
   double   p0, p1;
   int      dir;         // +1 = a rising support line, -1 = a falling resistance line
   int      touches;     // "two or three clear touchpoints"
   int      newestIdx;   // the bar index of the newest anchor
   int      oldestIdx;   // ... and of the oldest (the first touchpoint)
};

//+------------------------------------------------------------------+
class CCfTrendline : public CEAStrategy
{
public:
   void OnInitStrategy()
   {
      m_planSafety = false;
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "Trendline Strategy armed: %s on %s; bounce %s (min %d touchpoints), break %s (2T and 3T tracked separately), stop trailed along the safety line %s",
             InpSymbolsToTrade, EnumToString(PERIOD_H4), InpUseBounce ? "on" : "off", InpMinTouchpoints,
             InpUseBreak ? "on" : "off", InpTrailAlongLine ? "on" : "off"), true);
   }

   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_TRENDLINE";
      cfg.sourceDoc             = "chartfanatics/pdf/trendline-strategy.pdf (card #41)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_H4;       // "This strategy works best on the 4-hour timeframe"
      cfg.clock                 = EA_CLOCK_SERVER; // futures / crypto / FX run around the clock
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = 4.0;
      cfg.totalDdPct            = 10.0;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 2;
      cfg.minSecondsBetweenTrades = 3600;
      cfg.sessionStartHour      = 0;
      cfg.sessionStartMin       = 0;
      cfg.sessionEndHour        = 23;
      cfg.sessionEndMin         = 59;
      cfg.sessionEndFlat        = false;           // swing trading: the line is the exit, not the clock
      cfg.fridayFlat            = false;
      cfg.signalOnNewBarOnly    = true;            // one decision per completed 4-hour bar
      cfg.useLimitEntry         = false;
      //--- the document's exits are the safety line and its trail - nothing else
      cfg.breakEvenAtR          = 0.0;
      cfg.trailAtR              = 0.0;
      cfg.partial1AtR           = 0.0;
      cfg.partial2AtR           = 0.0;
      cfg.timeStopMinutes       = 0;
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_trendline_ledger.csv";
      cfg.logLevel              = InpLogLevel;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   //+----------------------------------------------------------------+
   //| The two setups of the playbook, on drawn-by-rule trendlines.    |
   //+----------------------------------------------------------------+
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      m_planSafety = false;
      if(ctx.atr <= 0.0 || !ctx.inSession) return false;

      MqlRates d[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, InpScanBars + 10, d);
      if(got < 60) return false;

      PruneState();                                   // once per signal bar is enough

      bool dailyUp = DailyTrendUp(ctx.symbol);

      double best = -1.0;
      SSignalPlan p;

      if(InpUseBounce)
      {
         p.Reset();
         if(PlanBounce(ctx, d, got, +1, dailyUp, p) && p.score > best) { plan = p; best = p.score; }
         p.Reset();
         if(PlanBounce(ctx, d, got, -1, dailyUp, p) && p.score > best) { plan = p; best = p.score; }
      }
      if(InpUseBreak)
      {
         p.Reset();
         if(PlanBreak(ctx, d, got, +1, dailyUp, p) && p.score > best) { plan = p; best = p.score; }
         p.Reset();
         if(PlanBreak(ctx, d, got, -1, dailyUp, p) && p.score > best) { plan = p; best = p.score; }
      }
      if(plan.dir != 0 && m_planSafety) PendingSafetyStore(ctx.symbol);
      return (plan.dir != 0);
   }

   //+----------------------------------------------------------------+
   //| S5 + the trailing rule: "if the price moves back and closes     |
   //| beyond the safety line, the trade is invalid and must be        |
   //| closed"; "move the stop manually as the new structure forms".   |
   //+----------------------------------------------------------------+
   void Manage(SEAContext &ctx)
   {
      if(PositionsTotal() == 0) return;
      MqlRates d[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, 6, d);
      if(got < 3) return;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != (long)g_eaCfg.magic) continue;

         SLine L;
         if(!SafetyLoad(t, L))
         {
            datetime stamp = (datetime)GlobalVariableGet(K(ctx.symbol, "_PTT"));
            datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
            if(HasPendingSafety(ctx.symbol) && PendingSafetyLoad(ctx.symbol, L) &&
               opened + (datetime)(4 * 3600) >= stamp && opened <= stamp + (datetime)(4 * 3600))
            {
               SafetySave(t, L);                      // the fill belongs to the plan: tag it
               PendingSafetyClear(ctx.symbol);
            }
            else continue;                            // no line recorded: the stop/target protect it
         }
         bool isLong = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

         //--- S5: the completed close back beyond the safety line invalidates the trade
         if(InpUseLineExit)
         {
            double line = LineAt(L, d[1].time);
            bool invalid = isLong ? (d[1].close < line) : (d[1].close > line);
            if(invalid)
            {
               if(g_eaExec.Close(t, "the completed close crossed the safety line - invalid"))
                  EA_Log(EA_LOG_EVENTS, "Trendline Strategy: position closed - price closed beyond the safety line", true);
               continue;
            }
         }

         //--- the line trail: the stop follows the safety line as the structure advances
         if(InpTrailAlongLine)
         {
            double line = LineAt(L, TimeTradeServer());
            double newSl = isLong ? line - InpStopBufferAtr * ctx.atr : line + InpStopBufferAtr * ctx.atr;
            if(newSl <= 0.0) continue;
            if(isLong && newSl >= ctx.bid) continue;      // never push a stop through the market
            if(!isLong && newSl <= ctx.ask) continue;
            double curSl = PositionGetDouble(POSITION_SL);
            double curTp = PositionGetDouble(POSITION_TP);
            bool better = (curSl == 0.0) || (isLong ? (newSl > curSl) : (newSl < curSl));
            if(better && g_eaExec.Modify(t, newSl, curTp))
               EA_Log(EA_LOG_EVENTS, StringFormat("Trendline Strategy: stop trailed along the safety line to %.5f", newSl), true);
         }
      }
   }

private:
   SLine m_planSafetyLine;      // the safety line of the plan being assembled
   bool  m_planSafety;

   //+----------------------------------------------------------------+
   //| Line arithmetic                                                 |
   //+----------------------------------------------------------------+
   double LineAt(const SLine &L, const datetime t)
   {
      long span = (long)L.t1 - (long)L.t0;
      if(span == 0) return L.p1;
      return L.p0 + (L.p1 - L.p0) * (double)((long)t - (long)L.t0) / (double)span;
   }

   //--- the pivot book: the same-side swings with their bar indexes, newest first
   int PivotLows(const MqlRates &d[], const int got, double &price[], int &idx[])
   {
      int n = 0;
      int side = (int)MathMax(1, InpPivotSide);
      for(int i = side + 1; i + side < got - 1 && n < 12; i++)
      {
         bool pl = true;
         for(int k = 1; k <= side; k++)
            if(d[i].low >= d[i - k].low || d[i].low >= d[i + k].low) pl = false;
         if(pl) { price[n] = d[i].low; idx[n] = i; n++; }
      }
      return n;
   }
   int PivotHighs(const MqlRates &d[], const int got, double &price[], int &idx[])
   {
      int n = 0;
      int side = (int)MathMax(1, InpPivotSide);
      for(int i = side + 1; i + side < got - 1 && n < 12; i++)
      {
         bool ph = true;
         for(int k = 1; k <= side; k++)
            if(d[i].high <= d[i - k].high || d[i].high <= d[i + k].high) ph = false;
         if(ph) { price[n] = d[i].high; idx[n] = i; n++; }
      }
      return n;
   }

   //--- a trendline is drawn through the two most recent same-side swings; the two
   //--- anchors are the first two touchpoints and every later touch on the extended
   //--- line counts towards the document's "two or three clear touchpoints"
   bool BuildLine(const MqlRates &d[], const int got, const int dir, SLine &L)
   {
      double px[12]; int ix[12];
      int n = (dir > 0) ? PivotLows(d, got, px, ix) : PivotHighs(d, got, px, ix);
      if(n < 2) return false;

      //--- a rising support line needs higher lows, a falling resistance line lower highs
      if(dir > 0 && !(px[0] > px[1])) return false;
      if(dir < 0 && !(px[0] < px[1])) return false;

      L.t0 = d[ix[0]].time; L.p0 = px[0];
      L.t1 = d[ix[1]].time; L.p1 = px[1];
      L.dir = dir;
      L.newestIdx = ix[0];
      L.oldestIdx = ix[1];
      L.touches = 2;

      double tol = InpLineTolPct / 100.0;
      for(int k = 2; k < n; k++)                        // older pivots: were they on the line?
      {
         double line = LineAt(L, d[ix[k]].time);
         if(MathAbs(px[k] - line) / line <= tol) L.touches++;
      }
      //--- "there must be at least one week of price data from the first touchpoint"
      if(d[L.oldestIdx].time > TimeTradeServer() - (datetime)((long)InpMinTouchSpanDays * 86400)) return false;
      return true;
   }

   //--- "a top-down look ... helps confirm the main trend direction"
   bool DailyTrendUp(const string sym)
   {
      double sum = 0.0;
      int n = (int)MathMax(5, InpDailyMaPeriod);
      MqlRates d[];
      int got = EA_Rates(sym, PERIOD_D1, 0, n + 2, d);
      if(got < n) return false;
      for(int i = 0; i < n; i++) sum += d[i].close;
      return (d[0].close > sum / n);
   }

   //+----------------------------------------------------------------+
   //| S3: the bounce - "enter when the price reaches or tests the     |
   //| trendline", the line itself is the safety line.                 |
   //+----------------------------------------------------------------+
   bool PlanBounce(const SEAContext &ctx, const MqlRates &d[], const int got, const int dir,
                   const bool dailyUp, SSignalPlan &p)
   {
      if(InpRequireDailyAlign && (dailyUp != (dir > 0))) return false;   // the top-down look, optional
      SLine L;
      if(!BuildLine(d, got, dir, L)) return false;
      if(L.touches < InpMinTouchpoints) return false;

      //--- the completed bar tested the line and closed back on the right side
      double lineNow = LineAt(L, d[1].time);
      if(lineNow <= 0.0) return false;
      double tol = InpTouchTestPct / 100.0;
      bool tested = (dir > 0) ? (d[1].low <= lineNow * (1.0 + tol) && d[1].close > lineNow)
                              : (d[1].high >= lineNow * (1.0 - tol) && d[1].close < lineNow);
      if(!tested) return false;

      double entry = (dir > 0) ? ctx.ask : ctx.bid;
      double stop  = (dir > 0) ? lineNow - InpStopBufferAtr * ctx.atr
                               : lineNow + InpStopBufferAtr * ctx.atr;
      if(!StopOk(entry, stop)) return false;
      double risk = MathAbs(entry - stop);

      p.dir = dir;
      p.entry = entry;
      p.stop = stop;
      p.target = (dir > 0) ? entry + InpTargetR * risk : entry - InpTargetR * risk;
      p.riskDist = risk;
      p.barsAgo = 1;
      p.isLimit = false;
      p.score = 86.0;                                   // "the bounce setup generally carries the lowest risk"
      if(dailyUp == (dir > 0)) p.score += 3.0;          // the top-down look agrees
      m_planSafetyLine = L;                             // bounce: action line = safety line
      m_planSafety = true;
      p.reason = StringFormat("trendline bounce %s: %d touchpoints, the line at %.5f acts as action and safety line%s",
                              (dir > 0 ? "LONG off support" : "SHORT at resistance"), L.touches, lineNow,
                              (dailyUp == (dir > 0) ? " (daily trend agrees)" : ""));
      return (p.target > 0.0);
   }

   //+----------------------------------------------------------------+
   //| S4: the break - the action line breaks, an opposing line is the |
   //| safety line, and "the break must happen close to the safety      |
   //| line so the risk stays tight".                                  |
   //+----------------------------------------------------------------+
   bool PlanBreak(const SEAContext &ctx, const MqlRates &d[], const int got, const int dir,
                  const bool dailyUp, SSignalPlan &p)
   {
      if(InpRequireDailyAlign && (dailyUp != (dir > 0))) return false;   // the top-down look, optional
      //--- the action line opposes the trade: a falling line broken upward, and vice versa
      SLine action;
      if(!BuildLine(d, got, -dir, action)) return false;
      if(action.touches < InpMinTouchpoints) return false;

      //--- the freshest completed bar that closed beyond the action line after a bar
      //--- that did not: the bar that started the current excursion through the line
      double brk = InpBreakClosePct / 100.0;
      int breakIdx = 0;
      for(int i = 1; i <= action.newestIdx; i++)
      {
         double line = LineAt(action, d[i].time);
         bool through = (dir > 0) ? (d[i].close > line * (1.0 + brk)) : (d[i].close < line * (1.0 - brk));
         if(!through) continue;
         bool before = false;
         if(i + 1 <= action.newestIdx)
         {
            double pl = LineAt(action, d[i + 1].time);
            before = (dir > 0) ? (d[i + 1].close > pl * (1.0 + brk)) : (d[i + 1].close < pl * (1.0 - brk));
         }
         if(!before) { breakIdx = i; break; }
      }
      if(breakIdx == 0) return false;
      if(breakIdx > InpBreakFreshBars) return false;    // "wait until price forms a clear high or low to draw one"

      //--- the safety line: "a new opposing trendline is drawn as the safety line" -
      //--- the EA uses the latest opposing line it can see (formed before or after the
      //--- break), and the risk gate below is what keeps the setup tight
      SLine safety;
      if(!BuildLine(d, got, dir, safety)) return false;  // a line in the trade's direction

      double entry = (dir > 0) ? ctx.ask : ctx.bid;
      double safetyNow = LineAt(safety, d[1].time);
      if(safetyNow <= 0.0) return false;
      double risk = MathAbs(entry - safetyNow);
      if(risk <= 0.0) return false;
      if(risk > entry * InpMaxLineRiskPct / 100.0) return false;   // "if it's too far, skip the trade"
      //--- the safety line must sit behind the trade (below a long, above a short)
      if(dir > 0 && !(safetyNow < entry)) return false;
      if(dir < 0 && !(safetyNow > entry)) return false;

      double buffered = (dir > 0) ? safetyNow - InpStopBufferAtr * ctx.atr
                                  : safetyNow + InpStopBufferAtr * ctx.atr;
      if(!StopOk(entry, buffered)) return false;

      p.dir = dir;
      p.entry = entry;
      p.stop = buffered;
      p.target = (dir > 0) ? entry + InpTargetR * risk : entry - InpTargetR * risk;
      p.riskDist = MathAbs(entry - buffered);
      p.barsAgo = 1;
      p.isLimit = false;
      //--- "Track all 2 touchpoint breaks separately from 3 touchpoints breaks"
      p.score = (action.touches >= 3) ? 88.0 : 84.0;
      if(dailyUp == (dir > 0)) p.score += 3.0;
      m_planSafetyLine = safety;
      m_planSafety = true;
      p.reason = StringFormat("trendline break %s: %d touchpoints broken%s, safety line at %.5f (risk %.2f%%)",
                              (dir > 0 ? "LONG" : "SHORT"), action.touches,
                              (action.touches >= 3 ? " (3T break)" : " (2T break)"), safetyNow,
                              risk / entry * 100.0);
      return (p.target > 0.0);
   }

   bool StopOk(const double entry, const double stop)
   {
      if(stop <= 0.0) return false;
      double risk = MathAbs(entry - stop);
      if(risk <= 0.0) return false;
      return (risk <= entry * InpMaxStopPct / 100.0);
   }

   //+----------------------------------------------------------------+
   //| Safety-line storage: four numbers per ticket plus a pending slot |
   //| keyed by symbol (the ticket exists only after the fill).         |
   //+----------------------------------------------------------------+
   string K(const string sym, const string tag) { return "CFTL_" + IntegerToString((long)g_eaCfg.magic) + "_" + sym + tag; }
   string T(const ulong ticket, const string tag) { return "CFTL_" + IntegerToString((long)g_eaCfg.magic) + "_" + IntegerToString((long)ticket) + tag; }

   void SafetySave(const ulong ticket, const SLine &L)
   {
      GlobalVariableSet(T(ticket, "_T0"), (double)(long)L.t0);
      GlobalVariableSet(T(ticket, "_P0"), L.p0);
      GlobalVariableSet(T(ticket, "_T1"), (double)(long)L.t1);
      GlobalVariableSet(T(ticket, "_P1"), L.p1);
   }
   bool SafetyLoad(const ulong ticket, SLine &L)
   {
      string k = T(ticket, "_T0");
      if(!GlobalVariableCheck(k)) return false;
      L.t0 = (datetime)GlobalVariableGet(k);
      L.p0 = GlobalVariableGet(T(ticket, "_P0"));
      L.t1 = (datetime)GlobalVariableGet(T(ticket, "_T1"));
      L.p1 = GlobalVariableGet(T(ticket, "_P1"));
      L.dir = 0; L.touches = 0; L.newestIdx = 0; L.oldestIdx = 0;
      return (L.t1 != L.t0 && L.p0 > 0.0);
   }
   void PendingSafetyStore(const string sym)
   {
      GlobalVariableSet(K(sym, "_PTT"), (double)(long)TimeTradeServer());
      GlobalVariableSet(K(sym, "_PT0"), (double)(long)m_planSafetyLine.t0);
      GlobalVariableSet(K(sym, "_PP0"), m_planSafetyLine.p0);
      GlobalVariableSet(K(sym, "_PT1"), (double)(long)m_planSafetyLine.t1);
      GlobalVariableSet(K(sym, "_PP1"), m_planSafetyLine.p1);
   }
   bool HasPendingSafety(const string sym)
   {
      if(!GlobalVariableCheck(K(sym, "_PT0"))) return false;
      datetime stamp = (datetime)GlobalVariableGet(K(sym, "_PTT"));
      return (TimeTradeServer() - stamp <= (datetime)(2 * 4 * 3600));   // two 4-hour bars, no stale tags
   }
   bool PendingSafetyLoad(const string sym, SLine &L)
   {
      if(!HasPendingSafety(sym)) return false;
      L.t0 = (datetime)GlobalVariableGet(K(sym, "_PT0"));
      L.p0 = GlobalVariableGet(K(sym, "_PP0"));
      L.t1 = (datetime)GlobalVariableGet(K(sym, "_PT1"));
      L.p1 = GlobalVariableGet(K(sym, "_PP1"));
      L.dir = 0; L.touches = 0; L.newestIdx = 0; L.oldestIdx = 0;
      return true;
   }
   void PendingSafetyClear(const string sym)
   {
      GlobalVariableDel(K(sym, "_PT0"));
      GlobalVariableDel(K(sym, "_PP0"));
      GlobalVariableDel(K(sym, "_PT1"));
      GlobalVariableDel(K(sym, "_PP1"));
      GlobalVariableDel(K(sym, "_PTT"));
   }

   //--- housekeeping (once per signal bar): forget the lines of closed tickets and
   //--- expire a pending slot the engine never turned into a fill
   void PruneState()
   {
      string prefix = "CFTL_" + IntegerToString((long)g_eaCfg.magic) + "_";
      int plen = StringLen(prefix);
      for(int g = GlobalVariablesTotal() - 1; g >= 0; g--)
      {
         string name = GlobalVariableName(g);
         if(StringFind(name, prefix) != 0) continue;
         int sep = StringFind(name, "_", plen);
         if(sep < 0) continue;
         string id  = StringSubstr(name, plen, sep - plen);
         string tag = StringSubstr(name, sep + 1);
         if(tag == "PT0" || tag == "PP0" || tag == "PT1" || tag == "PP1" || tag == "PTT")
         {
            if(tag != "PTT" && GlobalVariableCheck(K(id, "_PTT")) &&
               TimeTradeServer() - (datetime)GlobalVariableGet(K(id, "_PTT")) > (datetime)(2 * 4 * 3600))
               PendingSafetyClear(id);
            else if(tag == "PTT" && !GlobalVariableCheck(K(id, "_PT0")))
               GlobalVariableDel(name);
            continue;
         }
         if(tag != "T0" && tag != "T1" && tag != "P0" && tag != "P1") continue;
         ulong ticket = (ulong)StringToInteger(id);
         if(ticket == 0) continue;
         if(!PositionSelectByTicket(ticket)) GlobalVariableDel(name);
      }
   }
};

CCfTrendline g_cfTrendline;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfTrendline);
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
