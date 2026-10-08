//+------------------------------------------------------------------+
//|                                    EA_CF_UniqueHighRr.mq5        |
//|                                  Copyright 2026, Master Strategy  |
//|                                                                   |
//| ChartFanatics: Unique High RR (TG Capital Playbook)                |
//| "Unique High RR" - Apr 2025, Futures / Forex                      |
//| Card    : chartfanatics/todos/unique-high-rr.md            (#45)  |
//| Source  : chartfanatics/pdf/unique-high-rr.pdf                    |
//| Magic   : 3245                                                    |
//|                                                                   |
//| "capture high risk-to-reward trades by trading only during the     |
//|  London session, when momentum and volatility tend to align.  It   |
//|  follows a clear, structured model that uses stacked EMAs, fair    |
//|  value gaps (FVGs), and time-based entry conditions"               |
//|                                                                   |
//|   S1  THE CLOCK: "Only trades between 3:00 AM and 6:30 AM New      |
//|       York time ... Entries must occur inside this window"; the    |
//|       FVG itself "Must occur between 2:30 and 4:00 AM".            |
//|   S2  THE FRAME: "30-minute chart is the only chart used to find   |
//|       the entry.  The daily chart is used for overall bias and to  |
//|       target take-profit levels".  5 / 9 / 13 (or 15) / 21 EMAs    |
//|       "must be clearly stacked in the direction of the trade.  If  |
//|       they are crossing or tangled, the setup is invalid"; the     |
//|       daily 200 EMA: "Above 200 EMA -> only take longs.  Below 200 |
//|       EMA -> only take shorts."                                    |
//|   S3  THE TRIDENT PATTERN: "Look for a 3-candle FVG to form on the |
//|       30M chart"; "Identify the 50% Level (Consequent              |
//|       Encroachment) - mark the midpoint of the FVG"; "A small-     |
//|       bodied doji candle must form next.  The candle must wick     |
//|       into the FVG 50% zone"; "The candle after the doji must      |
//|       close below the doji high.  If it closes above the doji      |
//|       high, the trade is invalid."  Entry: "on that confirmation   |
//|       candle or place a limit at the FVG 50% if you're early".     |
//|   S4  THE STOP: "Below the low of the candle that forms FVG";      |
//|       "On Gold, a hard stop isn't used ... Using a closing candle  |
//|       filter prevents getting stopped out prematurely."            |
//|   S5  TARGET & MANAGEMENT: "The daily chart is used ... to target  |
//|       take-profit levels"; "ride the trend for as long as it       |
//|       remains intact.  Consider closing the trade if: the EMAs     |
//|       begin to reverse direction ... a significant bearish         |
//|       candlestick appears that invalidates the current structure." |
//|   S6  BOOKKEEPING: "PNL Fluctuations: Price may go +10R and pull   |
//|       back to +5R before running again" - no partials, no break-   |
//|       even, no R trail: the document's own exits are the exits.    |
//|                                                                   |
//| `[interpretation]`: the doji body threshold, the resting 50%       |
//| order's life, the stop buffer, the stop-width cap, the gold        |
//| disaster stop that keeps risk bounded where the document removes   |
//| the hard stop, the daily swing width and lookback used to pick the |
//| take-profit level, the minimum target distance, the far fallback   |
//| target, the "significant" candle body size, the structure swing    |
//| the invalidation rule breaks, the "clean" gap that only raises the |
//| score, the daily attempt cap and the open-position cap.            |
//|                                                                   |
//| Disclosed, not faked: the "Bull Trading Candle Strength" indicator |
//| is a proprietary four-state candle classifier (green / blue =      |
//| strong / mild bullish, red / black = strong / mild bearish).  The  |
//| EA has no such feed and never pretends to read it: the document    |
//| says it "helps confirm momentum on the daily chart", it is not a   |
//| stated gate, and the two momentum reads the document DOES state as |
//| rules - the daily 200 EMA bias and the stacked 5/9/13/21 EMAs -    |
//| are implemented.  The document's windows are New York wall time;   |
//| the engine's clocks are London and server only, so the EA converts |
//| server -> UTC -> New York with the US DST rule (2nd Sunday March   |
//| 02:00 -> 1st Sunday November 02:00), which is exact all year.      |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics Unique High RR - the Trident Pattern: a 30M three-candle FVG, a doji wick into the FVG 50% (consequent encroachment), a confirmation close, stacked 5/9/13/21 EMAs, the daily 200-EMA bias, entries only in the 03:00-06:30 New York kill zone"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade     = "EURUSD,GBPUSD,USDJPY,NZDUSD,USDCAD,XAUUSD";  // "Valid Pairs"
input ulong             InpMagicNumber        = 3245;             // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct            = 0.50;             // Risk per trade (% of equity)
input int               InpStage              = 5;                // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input double            InpMaxSpreadPoints    = 40.0;             // Spread gate in points (0 = off)
input double            InpDailyLossPct       = 2.00;             // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset    = 2;                // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel           = EA_LOG_EVENTS;    // Log verbosity
input double            InpCommissionPerLotRT = 0.0;              // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.15;             // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;             // Write the engine evidence ledger CSV

//--- S1: the New York clock
input int               InpKzStartHourNy      = 3;                // "Only trades between 3:00 AM and 6:30 AM New York time"
input int               InpKzStartMinNy       = 0;
input int               InpKzEndHourNy        = 6;
input int               InpKzEndMinNy         = 30;
input int               InpFvgStartHourNy     = 2;                // "Must occur between 2:30 and 4:00 AM"
input int               InpFvgStartMinNy      = 30;
input int               InpFvgEndHourNy       = 4;
input int               InpFvgEndMinNy        = 0;

//--- S2: the trend frame
input bool              InpRequireStack       = true;             // "These EMAs must be clearly stacked ... If they are crossing or tangled, the setup is invalid"
input int               InpEmaFast            = 5;                // "5 EMA"
input int               InpEmaMid1            = 9;                // "9 EMA"
input int               InpEmaMid2            = 13;               // "13 (or 15) EMA"
input int               InpEmaSlow            = 21;               // "21 EMA"
input double            InpStackMinGapAtr     = 0.00;             // [interpretation] an optional minimum separation so "clearly" has a number (0 = plain order)
input int               InpEmaBiasPeriod      = 200;              // "200 EMA: for trend bias"
input bool              InpUseEmaBias         = true;             // "Above 200 EMA -> only take longs.  Below 200 EMA -> only take shorts"

//--- S3: the Trident pattern
input double            InpDojiBodyMaxPct     = 34.0;             // [interpretation] "a small-bodied doji candle" - body <= x% of the candle range
input double            InpCleanGapAtr        = 0.50;             // [interpretation] "a clean 3-candle FVG" - a gap this wide only raises the score
input bool              InpUseLimitAtMid      = true;             // "place a limit at the FVG 50% if you're early" (off = enter on the confirmation candle)
input int               InpLimitMinutes       = 240;              // [interpretation] the resting 50% order's life, capped by the kill zone

//--- S4: the stop
input double            InpStopBufferAtr      = 0.10;             // "Below the low of the candle that forms FVG" - just below, with a wick cushion
input double            InpMaxStopPct         = 3.00;             // [interpretation] reject stops wider than x% of price
input bool              InpGoldCloseStop      = true;             // "On Gold, a hard stop isn't used ... a closing candle filter prevents getting stopped out prematurely"
input double            InpGoldDisasterAtr    = 2.00;             // [interpretation] the far hard stop that still bounds gold risk

//--- S5: the target and the two management rules
input bool              InpDailyStructureTp   = true;             // "The daily chart is used ... to target take-profit levels"
input int               InpDailySwingSide     = 2;                // [interpretation] the daily swing width used to place a target
input int               InpDailyLookback      = 60;               // [interpretation] the daily window searched for the target
input double            InpMinTargetR         = 3.0;              // [interpretation] only a daily level at least this far away is used
input double            InpTargetR            = 10.0;             // [interpretation] far fallback target (the document's own +10R language)
input bool              InpExitOnStackFlip    = true;             // "The EMAs begin to reverse direction, signaling a potential shift in trend"
input bool              InpExitOnBigCandle    = true;             // "A significant bearish candlestick appears that invalidates the current structure"
input double            InpInvalidBodyAtr     = 1.00;             // [interpretation] "significant" - the candle body in 30M ATR
input int               InpSwingSide          = 2;                // [interpretation] the structure swing the invalidating candle breaks

//--- S6: bookkeeping
input int               InpMaxTradesPerDay    = 2;                // [interpretation] "quality over quantity" - a small daily attempt budget
input int               InpMaxOpenPositions   = 2;                // [interpretation] "maximize reward through trend continuation" - keep the stack small
input int               InpMinSecondsBetween  = 1800;             // [interpretation] one attempt per 30-minute bar at most

//+------------------------------------------------------------------+
//| The 5 / 9 / 13 / 21 stack plus the daily 200 EMA, one set per     |
//| symbol (created on first use, released in OnDeinitStrategy).      |
//+------------------------------------------------------------------+
struct SEmaSet
{
   string sym;
   int    hFast;
   int    hMid1;
   int    hMid2;
   int    hSlow;
   int    hBias;
};

//+------------------------------------------------------------------+
class CCfUniqueHighRr : public CEAStrategy
{
public:
   void OnInitStrategy()
   {
      m_emaCount        = 0;
      m_planSetup       = 0;
      m_planCloseStop   = 0.0;
      m_planHasClose    = false;
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "Unique High RR armed: Trident Pattern on %s; kill zone %02d:%02d-%02d:%02d New York, FVG window %02d:%02d-%02d:%02d NY, EMA stack %d/%d/%d/%d + %d bias, limit at the FVG 50%% %s",
             InpSymbolsToTrade, InpKzStartHourNy, InpKzStartMinNy, InpKzEndHourNy, InpKzEndMinNy,
             InpFvgStartHourNy, InpFvgStartMinNy, InpFvgEndHourNy, InpFvgEndMinNy,
             InpEmaFast, InpEmaMid1, InpEmaMid2, InpEmaSlow, InpEmaBiasPeriod,
             InpUseLimitAtMid ? "on" : "off"), true);
   }

   void OnDeinitStrategy()
   {
      for(int i = 0; i < m_emaCount; i++)
      {
         if(m_ema[i].hFast != INVALID_HANDLE) IndicatorRelease(m_ema[i].hFast);
         if(m_ema[i].hMid1 != INVALID_HANDLE) IndicatorRelease(m_ema[i].hMid1);
         if(m_ema[i].hMid2 != INVALID_HANDLE) IndicatorRelease(m_ema[i].hMid2);
         if(m_ema[i].hSlow != INVALID_HANDLE) IndicatorRelease(m_ema[i].hSlow);
         if(m_ema[i].hBias != INVALID_HANDLE) IndicatorRelease(m_ema[i].hBias);
         m_ema[i].hFast = INVALID_HANDLE; m_ema[i].hMid1 = INVALID_HANDLE;
         m_ema[i].hMid2 = INVALID_HANDLE; m_ema[i].hSlow = INVALID_HANDLE;
         m_ema[i].hBias = INVALID_HANDLE;
      }
      m_emaCount = 0;
   }

   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_UNIQUE_HIGH_RR";
      cfg.sourceDoc             = "chartfanatics/pdf/unique-high-rr.pdf (card #45)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M30;      // "30-minute chart is the only chart used to find the entry"
      cfg.clock                 = EA_CLOCK_SERVER;  // the New York windows are converted explicitly, DST-proof
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
      cfg.sessionEndFlat        = false;           // the exit is the document's trend-integrity read, not the clock
      cfg.fridayFlat            = false;
      cfg.signalOnNewBarOnly    = true;            // one decision per completed 30-minute bar
      cfg.useLimitEntry         = false;
      //--- the document's exits are the stop, the daily target and the two trend-integrity
      //--- rules; "price may go +10R and pull back to +5R before running again" - so no
      //--- partials, no break-even and no R trail are layered on top
      cfg.breakEvenAtR          = 0.0;
      cfg.trailAtR              = 0.0;
      cfg.partial1AtR           = 0.0;
      cfg.partial2AtR           = 0.0;
      cfg.timeStopMinutes       = 0;
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_unique_high_rr_ledger.csv";
      cfg.logLevel              = InpLogLevel;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   //+----------------------------------------------------------------+
   //| The edge: FVG -> doji wick into the 50% -> confirmation close.  |
   //+----------------------------------------------------------------+
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      m_planHasClose = false;
      m_planCloseStop = 0.0;
      if(ctx.atr <= 0.0 || !ctx.inSession) return false;

      PruneState();                                   // once per signal bar is enough

      //--- "Entries must occur inside this window" (New York wall time)
      int nowNy = NyMinutesOfDay(TimeTradeServer());
      if(!InWindow(nowNy, InpKzStartHourNy, InpKzStartMinNy, InpKzEndHourNy, InpKzEndMinNy)) return false;

      MqlRates d[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, 12, d);
      if(got < 8) return false;

      double best = -1.0;
      SSignalPlan p;
      for(int dir = +1; dir >= -1; dir -= 2)
      {
         if(SetupBusy(SetupIndex(dir))) continue;
         p.Reset();
         int setup = 0; double closeStop = 0.0; bool hasClose = false;
         if(PlanTrident(ctx, d, got, dir, p, setup, closeStop, hasClose) && p.score > best)
         {
            plan = p; best = p.score;
            m_planSetup = setup; m_planCloseStop = closeStop; m_planHasClose = hasClose;
         }
      }
      if(plan.dir != 0)
      {
         PendingStore(ctx.symbol, m_planSetup, m_planCloseStop);
         EA_Log(EA_LOG_EVENTS, StringFormat("%s: Trident Pattern armed - %s", ctx.symbol, plan.reason), true);
      }
      return (plan.dir != 0);
   }

   //+----------------------------------------------------------------+
   //| S5: the document's own exits - "ride the trend for as long as   |
   //| it remains intact" - plus the gold closing-candle filter.       |
   //+----------------------------------------------------------------+
   void Manage(SEAContext &ctx)
   {
      if(PositionsTotal() == 0) return;
      MqlRates m[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, 6, m);
      if(got < 5) return;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != (long)g_eaCfg.magic) continue;

         bool isLong = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

         //--- a fill adopts the pending setup tag and the gold close-stop level
         if(!TagExists(t, "_S") && PendingFresh(ctx.symbol))
         {
            datetime stamp  = (datetime)GlobalVariableGet(K(ctx.symbol, "_PST"));
            datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
            if(opened + (datetime)3600 >= stamp && opened <= stamp + (datetime)3600)
            {
               GlobalVariableSet(T(t, "_S"), GlobalVariableGet(K(ctx.symbol, "_PS")));
               if(GlobalVariableCheck(K(ctx.symbol, "_PCS")))
                  GlobalVariableSet(T(t, "_CS"), GlobalVariableGet(K(ctx.symbol, "_PCS")));
               PendingClear(ctx.symbol);
            }
         }

         //--- S5a: "the EMAs begin to reverse direction, signaling a potential shift in trend"
         if(InpExitOnStackFlip && !StackOrdered(ctx.symbol, isLong ? +1 : -1, ctx.atr))
         {
            if(g_eaExec.Close(t, "the EMAs are no longer stacked with the trade - potential shift in trend"))
               EA_Log(EA_LOG_EVENTS, "Unique High RR: position closed - the EMA stack flipped", true);
            continue;
         }

         //--- S5b: "a significant bearish candlestick appears that invalidates the current structure"
         if(InpExitOnBigCandle && InvalidCandle(m, got, isLong, ctx.atr))
         {
            if(g_eaExec.Close(t, "a significant opposing candle invalidated the structure"))
               EA_Log(EA_LOG_EVENTS, "Unique High RR: position closed - the structure candle printed against the trade", true);
            continue;
         }

         //--- S4: "on Gold ... a closing candle filter prevents getting stopped out prematurely"
         double lvl = CloseStopLevel(t);
         if(lvl > 0.0 && (isLong ? (m[1].close < lvl) : (m[1].close > lvl)))
         {
            if(g_eaExec.Close(t, "the completed close crossed the FVG stop level - the gold closing-candle filter"))
               EA_Log(EA_LOG_EVENTS, "Unique High RR: position closed - the closing candle crossed the FVG stop level", true);
         }
      }
   }

private:
   SEmaSet  m_ema[8];
   int      m_emaCount;
   int      m_planSetup;
   double   m_planCloseStop;
   bool     m_planHasClose;

   //+----------------------------------------------------------------+
   //| The New York clock: the engine knows London and server only, so |
   //| the document's windows are converted server -> UTC -> NY with   |
   //| the US DST rule (2nd Sunday March 02:00 - 1st Sunday Nov 02:00).|
   //+----------------------------------------------------------------+
   bool InDstWindow(const datetime nyLocal)
   {
      MqlDateTime dt;
      if(!TimeToStruct(nyLocal, dt)) return false;
      datetime start = NthSunday(dt.year, 3, 2, 2);   // 2nd Sunday of March, 02:00
      datetime end   = NthSunday(dt.year, 11, 1, 2);  // 1st Sunday of November, 02:00
      return (nyLocal >= start && nyLocal < end);
   }
   datetime NthSunday(const int year, const int month, const int nth, const int hour)
   {
      MqlDateTime m;
      m.year = year; m.mon = month; m.day = 1; m.hour = hour; m.min = 0; m.sec = 0;
      datetime d1 = StructToTime(m);
      MqlDateTime t;
      TimeToStruct(d1, t);
      int firstSunday = 1 + ((7 - t.day_of_week) % 7);
      m.day = firstSunday + (nth - 1) * 7;
      return StructToTime(m);
   }
   bool NyDst(const datetime utc)
   {
      //--- two-step settle, the same trick the engine uses for EU DST
      if(InDstWindow(utc - (datetime)(5 * 3600))) return true;
      return InDstWindow(utc - (datetime)(4 * 3600));
   }
   datetime NyStamp(const datetime serverTime)
   {
      datetime utc = EA_ServerToUtc(serverTime);
      return utc - (datetime)((NyDst(utc) ? 4 : 5) * 3600);
   }
   datetime ServerFromNy(const datetime nyStamp)
   {
      datetime utc = nyStamp + (datetime)(5 * 3600);
      if(NyDst(utc)) utc = nyStamp + (datetime)(4 * 3600);
      return utc + (datetime)EA_ServerGmtOffsetSeconds();
   }
   int NyMinutesOfDay(const datetime serverTime) { return EA_MinutesOfDay(NyStamp(serverTime)); }
   bool InWindow(const int nowMin, const int fromH, const int fromM, const int toH, const int toM)
   {
      if(fromH < 0 || toH < 0) return false;
      int from = fromH * 60 + fromM;
      int to   = toH * 60 + toM;
      if(from == to) return true;
      if(from < to)  return (nowMin >= from && nowMin < to);
      return (nowMin >= from || nowMin < to);
   }
   //--- the kill zone's end today, in server time (the resting limit never outlives it)
   datetime KzEndServer()
   {
      datetime nyNow = NyStamp(TimeTradeServer());
      MqlDateTime d;
      TimeToStruct(nyNow, d);
      d.hour = InpKzEndHourNy; d.min = InpKzEndMinNy; d.sec = 0;
      return ServerFromNy(StructToTime(d));
   }

   //+----------------------------------------------------------------+
   //| Indicator handles: 5 / 9 / 13 / 21 on the signal frame, 200 on  |
   //| the daily frame, one cached set per symbol                      |
   //+----------------------------------------------------------------+
   bool EmaSet(const string sym, SEmaSet &s)
   {
      for(int i = 0; i < m_emaCount; i++)
         if(m_ema[i].sym == sym) { s = m_ema[i]; return (s.hFast != INVALID_HANDLE); }
      if(m_emaCount >= 8) return false;
      SEmaSet n;
      n.sym   = sym;
      n.hFast = iMA(sym, g_eaIndTf, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
      n.hMid1 = iMA(sym, g_eaIndTf, InpEmaMid1, 0, MODE_EMA, PRICE_CLOSE);
      n.hMid2 = iMA(sym, g_eaIndTf, InpEmaMid2, 0, MODE_EMA, PRICE_CLOSE);
      n.hSlow = iMA(sym, g_eaIndTf, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
      n.hBias = iMA(sym, PERIOD_D1,     InpEmaBiasPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(n.hFast == INVALID_HANDLE || n.hMid1 == INVALID_HANDLE || n.hMid2 == INVALID_HANDLE ||
         n.hSlow == INVALID_HANDLE || n.hBias == INVALID_HANDLE)
      {
         EA_Log(EA_LOG_ERRORS, StringFormat("EMA handles failed for %s (err %d)", sym, GetLastError()), true);
         if(n.hFast != INVALID_HANDLE) IndicatorRelease(n.hFast);
         if(n.hMid1 != INVALID_HANDLE) IndicatorRelease(n.hMid1);
         if(n.hMid2 != INVALID_HANDLE) IndicatorRelease(n.hMid2);
         if(n.hSlow != INVALID_HANDLE) IndicatorRelease(n.hSlow);
         if(n.hBias != INVALID_HANDLE) IndicatorRelease(n.hBias);
         return false;
      }
      m_ema[m_emaCount] = n;
      m_emaCount++;
      s = n;
      return true;
   }
   double EmaVal(const int handle, const int shift)
   {
      double v;
      if(!EA_Buf(handle, 0, shift, v)) return 0.0;
      return v;
   }

   //--- "These EMAs must be clearly stacked in the direction of the trade"
   bool StackOrdered(const string sym, const int dir, const double atr)
   {
      SEmaSet s;
      if(!EmaSet(sym, s)) return false;
      double f = EmaVal(s.hFast, 1), m1 = EmaVal(s.hMid1, 1), m2 = EmaVal(s.hMid2, 1), sl = EmaVal(s.hSlow, 1);
      if(f <= 0.0 || m1 <= 0.0 || m2 <= 0.0 || sl <= 0.0) return false;
      double gap = InpStackMinGapAtr * atr;    // [interpretation] 0 = plain order, the document's own reading
      if(dir > 0) return (f > m1 + gap && m1 > m2 + gap && m2 > sl + gap);
      return (f < m1 - gap && m1 < m2 - gap && m2 < sl - gap);
   }

   //--- "Above 200 EMA -> only take longs.  Below 200 EMA -> only take shorts."
   int BiasDir(const string sym)
   {
      SEmaSet s;
      if(!EmaSet(sym, s)) return 0;
      double ema = EmaVal(s.hBias, 1);
      if(ema <= 0.0) return 0;
      MqlRates d[];
      int got = EA_Rates(sym, PERIOD_D1, 1, 1, d);      // the last completed daily close
      if(got < 1) return 0;
      if(d[0].close > ema) return +1;
      if(d[0].close < ema) return -1;
      return 0;
   }

   //+----------------------------------------------------------------+
   //| S3: the Trident Pattern                                         |
   //|   d[5] d[4] d[3] = the three FVG candles (d[3] completes it)    |
   //|   d[2] = the doji, d[1] = the confirmation candle               |
   //+----------------------------------------------------------------+
   bool PlanTrident(const SEAContext &ctx, const MqlRates &d[], const int got, const int dir, SSignalPlan &p,
                    int &setupOut, double &closeStopOut, bool &hasCloseOut)
   {
      if(got < 8) return false;

      //--- the frame: the stack and the daily bias must agree with the trade
      if(InpRequireStack && !StackOrdered(ctx.symbol, dir, ctx.atr)) return false;
      if(InpUseEmaBias)
      {
         int bias = BiasDir(ctx.symbol);
         if(bias != 0 && bias != dir) return false;
      }

      //--- the 3-candle FVG; "ignore FVGs outside the kill zone"
      int fvgNy = NyMinutesOfDay(d[3].time);
      if(!InWindow(fvgNy, InpFvgStartHourNy, InpFvgStartMinNy, InpFvgEndHourNy, InpFvgEndMinNy)) return false;

      double gapLow = 0.0, gapHigh = 0.0;
      if(dir > 0)
      {
         if(!(d[3].low > d[5].high)) return false;      // bullish FVG: candle 3's low above candle 1's high
         gapLow = d[5].high; gapHigh = d[3].low;
      }
      else
      {
         if(!(d[3].high < d[5].low)) return false;      // bearish FVG: candle 3's high below candle 1's low
         gapLow = d[3].high; gapHigh = d[5].low;
      }
      double mid = (gapLow + gapHigh) / 2.0;            // "the 50% Level (Consequent Encroachment)"
      if(mid <= 0.0 || !(gapHigh > gapLow)) return false;

      //--- "A small-bodied doji candle must form next.  The candle must wick into the FVG 50% zone"
      double rng = d[2].high - d[2].low;
      if(rng <= 0.0) return false;
      double body = MathAbs(d[2].close - d[2].open);
      if(body > rng * InpDojiBodyMaxPct / 100.0) return false;
      if(!(d[2].low <= mid && d[2].high >= mid)) return false;

      //--- "The candle after the doji must close below the doji high ... otherwise the trade is invalid"
      if(dir > 0) { if(!(d[1].close < d[2].high)) return false; }
      else        { if(!(d[1].close > d[2].low))  return false; }

      //--- S4: "below the low of the candle that forms FVG", buffered against the wick
      double structural = (dir > 0) ? MathMin(d[3].low, d[4].low) - InpStopBufferAtr * ctx.atr
                                    : MathMax(d[3].high, d[4].high) + InpStopBufferAtr * ctx.atr;
      if(structural <= 0.0) return false;

      //--- the entry: "on that confirmation candle or place a limit at the FVG 50%"
      bool canRest = (InpUseLimitAtMid && (KzEndServer() - TimeTradeServer() > (datetime)120));
      double entry = canRest ? mid : ((dir > 0) ? ctx.ask : ctx.bid);

      //--- the stop that goes on the order; on gold the hard stop is moved out of wick
      //--- range and a completed close beyond the structural level does the exit instead
      bool closeStop = (InpGoldCloseStop && StringFind(ctx.symbol, "XAU") >= 0);
      double hardStop = structural;
      if(closeStop)
         hardStop = (dir > 0) ? structural - InpGoldDisasterAtr * ctx.atr
                              : structural + InpGoldDisasterAtr * ctx.atr;
      if(dir > 0 && !(hardStop < entry)) return false;
      if(dir < 0 && !(hardStop > entry)) return false;
      if(!StopOk(entry, hardStop)) return false;
      double risk = MathAbs(entry - hardStop);
      if(risk <= 0.0) return false;

      double tgt = DailyTarget(ctx.symbol, dir, entry, risk);
      if(tgt <= 0.0) return false;
      if(dir > 0 && !(tgt > entry)) return false;       // the target rides with the trade
      if(dir < 0 && !(tgt < entry)) return false;

      p.dir      = dir;
      p.entry    = entry;
      p.stop     = hardStop;
      p.target   = tgt;
      p.riskDist = risk;
      p.barsAgo  = 1;
      p.isLimit  = canRest;
      if(canRest)
      {
         datetime exp = TimeTradeServer() + (datetime)(InpLimitMinutes * 60);
         datetime kz  = KzEndServer();
         p.expiry = (exp < kz) ? exp : kz;              // the order never outlives the kill zone
      }
      //--- the document's own quality words: a "clean" gap and the resting 50% order rank higher
      p.score = 85.0;
      if((gapHigh - gapLow) >= InpCleanGapAtr * ctx.atr) p.score += 3.0;
      if(canRest) p.score += 3.0;

      setupOut     = SetupIndex(dir);
      closeStopOut = closeStop ? structural : 0.0;
      hasCloseOut  = closeStop;
      p.reason = StringFormat("Trident %s: 3-candle FVG %.5f-%.5f (mid %.5f, inside the 02:30-04:00 NY window), doji wick into the 50%%, confirmation close; %s entry, stop %.5f%s",
                              (dir > 0 ? "LONG" : "SHORT"), gapLow, gapHigh, mid,
                              (canRest ? "limit at the FVG 50%" : "market on the confirmation candle"),
                              hardStop, (closeStop ? " (gold closing-candle filter)" : ""));
      return true;
   }

   //--- the setup index of a direction (both directions of one pattern family are
   //--- the same approach, so a second position of the same family is refused)
   int SetupIndex(const int dir) { return (dir > 0) ? 1 : 2; }

   bool StopOk(const double entry, const double stop)
   {
      if(stop <= 0.0) return false;
      double risk = MathAbs(entry - stop);
      if(risk <= 0.0) return false;
      return (risk <= entry * InpMaxStopPct / 100.0);
   }

   //+----------------------------------------------------------------+
   //| "The daily chart is used ... to target take-profit levels": the |
   //| nearest daily swing beyond the minimum distance, else the far   |
   //| fallback the document's own +10R language suggests              |
   //+----------------------------------------------------------------+
   double DailyTarget(const string sym, const int dir, const double entry, const double risk)
   {
      if(!InpDailyStructureTp)
         return (dir > 0) ? entry + InpTargetR * risk : entry - InpTargetR * risk;
      MqlRates d[];
      int want = (int)MathMax(10, InpDailyLookback + InpDailySwingSide + 2);
      int got = EA_Rates(sym, PERIOD_D1, 0, want, d);
      if(got >= InpDailySwingSide + 5)
      {
         int last = (int)MathMin(InpDailyLookback, got - 1 - InpDailySwingSide);
         double best = 0.0;
         for(int i = 1 + InpDailySwingSide; i <= last; i++)
         {
            bool hi = true, lo = true;
            for(int k = 1; k <= InpDailySwingSide; k++)
            {
               if(!(d[i].high > d[i - k].high && d[i].high > d[i + k].high)) hi = false;
               if(!(d[i].low  < d[i - k].low  && d[i].low  < d[i + k].low )) lo = false;
            }
            if(dir > 0 && hi && d[i].high > entry + InpMinTargetR * risk)
            {
               if(best == 0.0 || d[i].high < best) best = d[i].high;   // the nearest level above
            }
            if(dir < 0 && lo && d[i].low < entry - InpMinTargetR * risk)
            {
               if(best == 0.0 || d[i].low > best) best = d[i].low;     // the nearest level below
            }
         }
         if(best > 0.0) return best;
      }
      return (dir > 0) ? entry + InpTargetR * risk : entry - InpTargetR * risk;
   }

   //+----------------------------------------------------------------+
   //| S5b: "a significant bearish candlestick appears that            |
   //| invalidates the current structure" - a body against the trade   |
   //| that closes beyond the structure swing                          |
   //+----------------------------------------------------------------+
   bool InvalidCandle(const MqlRates &m[], const int got, const bool isLong, const double atr)
   {
      if(got < InpSwingSide + 3) return false;
      double body = MathAbs(m[1].close - m[1].open);
      if(body < InpInvalidBodyAtr * atr) return false;      // [interpretation] "significant" in 30M ATR
      bool against = isLong ? (m[1].close < m[1].open) : (m[1].close > m[1].open);
      if(!against) return false;
      //--- the structure swing: the extreme of the bars before the signal bar
      double swing = isLong ? m[2].low : m[2].high;
      for(int i = 2; i <= InpSwingSide + 1 && i < got; i++)
         swing = isLong ? MathMin(swing, m[i].low) : MathMax(swing, m[i].high);
      bool beyond = isLong ? (m[1].close < swing) : (m[1].close > swing);
      return (against && beyond);
   }

   //+----------------------------------------------------------------+
   //| One live position per approach: read the per-ticket setup tag    |
   //+----------------------------------------------------------------+
   bool SetupBusy(const int setup)
   {
      if(setup <= 0) return false;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != (long)g_eaCfg.magic) continue;
         if(!TagExists(t, "_S")) continue;
         if((int)GlobalVariableGet(T(t, "_S")) == setup) return true;
      }
      return false;
   }
   double CloseStopLevel(const ulong ticket)
   {
      if(!TagExists(ticket, "_CS")) return 0.0;
      return GlobalVariableGet(T(ticket, "_CS"));
   }

   //+----------------------------------------------------------------+
   //| The pending slot (setup + gold close-stop level), written when  |
   //| a plan is produced and adopted by the fill that follows         |
   //+----------------------------------------------------------------+
   string K(const string sym, const string tag) { return "CFUHR_" + IntegerToString((long)g_eaCfg.magic) + "_" + sym + tag; }
   string T(const ulong ticket, const string tag) { return "CFUHR_" + IntegerToString((long)g_eaCfg.magic) + "_" + IntegerToString((long)ticket) + tag; }
   bool TagExists(const ulong ticket, const string tag) { return GlobalVariableCheck(T(ticket, tag)); }

   void PendingStore(const string sym, const int setup, const double closeStop)
   {
      GlobalVariableSet(K(sym, "_PST"), (double)(long)TimeTradeServer());
      GlobalVariableSet(K(sym, "_PS"), (double)setup);
      if(closeStop > 0.0) GlobalVariableSet(K(sym, "_PCS"), closeStop);
      else if(GlobalVariableCheck(K(sym, "_PCS"))) GlobalVariableDel(K(sym, "_PCS"));
   }
   bool PendingFresh(const string sym)
   {
      if(!GlobalVariableCheck(K(sym, "_PST"))) return false;
      datetime stamp = (datetime)GlobalVariableGet(K(sym, "_PST"));
      return (TimeTradeServer() - stamp <= (datetime)3600);      // the fill follows the plan within the hour
   }
   void PendingClear(const string sym)
   {
      GlobalVariableDel(K(sym, "_PST"));
      GlobalVariableDel(K(sym, "_PS"));
      GlobalVariableDel(K(sym, "_PCS"));
   }

   //--- housekeeping (once per signal bar): pending slots expire on their own and
   //--- the tags of closed tickets are forgotten
   void PruneState()
   {
      string prefix = "CFUHR_" + IntegerToString((long)g_eaCfg.magic) + "_";
      int plen = StringLen(prefix);
      for(int g = GlobalVariablesTotal() - 1; g >= 0; g--)
      {
         string name = GlobalVariableName(g);
         if(StringFind(name, prefix) != 0) continue;
         int sep = StringFind(name, "_", plen);
         if(sep < 0) continue;
         string id  = StringSubstr(name, plen, sep - plen);
         string tag = StringSubstr(name, sep + 1);
         if(tag == "PST" || tag == "PS" || tag == "PCS")
         {
            if(tag != "PST" && GlobalVariableCheck(K(id, "_PST")) &&
               TimeTradeServer() - (datetime)GlobalVariableGet(K(id, "_PST")) > (datetime)3600)
               PendingClear(id);
            else if(tag == "PST" && !GlobalVariableCheck(K(id, "_PS")))
               GlobalVariableDel(name);
            continue;
         }
         if(tag != "S" && tag != "CS") continue;
         ulong ticket = (ulong)StringToInteger(id);
         if(ticket == 0) continue;
         if(!PositionSelectByTicket(ticket)) GlobalVariableDel(name);
      }
   }
};

CCfUniqueHighRr g_cfUniqueHighRr;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfUniqueHighRr);
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
