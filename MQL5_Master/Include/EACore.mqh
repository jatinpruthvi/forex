//+------------------------------------------------------------------+
//|                                                       EACore.mqh |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Shared runtime core for every EA under MQL5_Master/Experts/      |
//| additionalEAs. Provides:                                         |
//|   * London-wall-clock session engine (broker-offset + EU DST)    |
//|   * symbol / price / volume normalisation helpers                |
//|   * fail-closed pre-trade gates (spread, stops level, margin)    |
//|   * a news blackout reader (CSV, optional)                       |
//|   * rate-limited logging and a per-EA evidence ledger            |
//|                                                                  |
//| No trading decisions live here; see EASignals.mqh and            |
//| EATrade.mqh. Every function guards its own inputs - the whole    |
//| library is designed to fail closed rather than throw.            |
//+------------------------------------------------------------------+
#ifndef EA_CORE_MQH
#define EA_CORE_MQH

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//+------------------------------------------------------------------+
//| Build / identity                                                 |
//+------------------------------------------------------------------+
#define EA_CORE_BUILD_ID      "MQL5_Master_EA_CORE_1.0.0_20261001"
//--- 10 = the widest delivered universe (magics 2034/2040 list 10, 2031/3111
//--- list 9).  It was 8 until the owner's decision on the eleventh-pass
//--- finding #72, which truncated those four engines to their first 8
//--- symbols.  10 keeps every delivered EA trading exactly its documented
//--- book; EA_ParseSymbols still logs (never silently drops) anything a
//--- future universe lists beyond it, and the verifier fails if a
//--- delivered universe is wider than this macro.
#define EA_MAX_SYMBOLS        10
#define EA_MAX_POSITIONS      64
#define EA_MAX_PARTIALS       4

//+------------------------------------------------------------------+
//| Logging levels                                                   |
//+------------------------------------------------------------------+
enum ENUM_EA_LOG_LEVEL
{
   EA_LOG_ERRORS = 0,   // Errors only
   EA_LOG_EVENTS = 1,   // Errors + state changes (default)
   EA_LOG_VERBOSE= 2    // Everything (tester/debug)
};

//+------------------------------------------------------------------+
//| Reference timeframe for the session clock                        |
//+------------------------------------------------------------------+
enum ENUM_EA_CLOCK
{
   EA_CLOCK_LONDON = 0, // Europe/London wall clock (DST aware)
   EA_CLOCK_SERVER = 1  // Broker server clock
};

//+------------------------------------------------------------------+
//| Global settings filled by each EA in OnInit() before EA_Init().   |
//| Every field has a safe default: an EA that sets nothing trades    |
//| nothing (magic 0 / no symbols) rather than trading blindly.       |
//+------------------------------------------------------------------+
struct SEASettings
{
   //--- identity
   ulong                magic;                 // unique magic number
   string               strategyName;          // human readable
   string               sourceDoc;             // tracker source document
   //--- universe
   string               symbols;               // comma separated list
   bool                 requireSupportedList;  // fail init if symbol not in list
   //--- risk
   double               riskPct;               // base risk per trade (% of equity/balance)
   bool                 riskBaseBalance;       // size on balance instead of equity
   double               qualifyingDayAmount;   // cash: a day counts when the closed-day delta reaches this
   int                  qualifyingDaysTarget;  // required qualifying days per phase (0 = off)
   double               maxSpreadPoints;       // 0 = disabled
   double               dailyLossPct;          // halt day at -x%  (0 = disabled)
   double               weeklyLossPct;         // halt week at -x% (0 = disabled)
   bool                 flattenOnHalt;        // close positions and cancel entries when halted
   bool                 oneEntryAccountWide;  // one working entry/open position across the EA
   bool                 riskBaseInitialBalance; // size off a fixed phase-initial balance
   double               riskInitialBalance;   // the fixed phase-initial balance (0 = off)
   double               newsFlatBeforeMin;    // flatten this many minutes before a red event
   bool                 dayAnchorServer;      // firm rollover uses the broker SERVER day, not the clock day
   bool                 dayLockFirstWin;      // lock the day after a net-positive first exit
   int                  dayLockAfterTrades;   // lock the day after N completed trades (0 = off)
   int                  dayLockAfterLosses;   // lock the day after N losing completed trades (0 = off)
   double               monthlyLossPct;        // halt month at -x% (0 = disabled)
   int                  lossStreakPause;      // consecutive losses that trigger a pause (0 = off)
   int                  lossStreakPauseHours; // pause length in hours
   double               commissionPerLotRT;    // broker round-turn commission per lot
   double               maxCostR;              // reject if all-in cost > xR (0 = off)
   int                  maxRequestsPerDay;     // trade-request rate limit (0 = off)
   double               totalDdPct;            // permanent floor from start balance
   double               profitTargetPct;       // stop opening at +x% (0 = disabled)
   double               softTargetPct;         // reduce risk beyond this (0=disabled)
   double               softTargetRiskMult;
   int                  maxTradesPerDay;       // 0 = unlimited
   int                  maxOpenPositions;      // per EA (magic), 0 = 1
   int                  minSecondsBetweenTrades;
   //--- equity throttle
   bool                 useHwmThrottle;        // scale risk on drawdown from HWM
   double               hwmTier1Dd;            // default 2.0
   double               hwmTier1Mult;          // default 0.50
   double               hwmTier2Dd;            // default 4.0
   double               hwmTier2Mult;          // default 0.25
   double               hwmHaltDd;             // default 6.0
   //--- time
   ENUM_EA_CLOCK        clock;
   int                  serverWinterGmtOffset; // server clock minus GMT in winter
   bool                 serverOffsetAuto;      // read the live server-GMT offset instead
   bool                 serverFollowsEuDst;    // +1h in EU summer time
   int                  noTradeAfterHour;      // London hour, -1 disabled
   int                  noTradeAfterMin;
   bool                 fridayFlat;            // flatten before weekend
   int                  fridayFlatHour;        // London hour
   int                  fridayFlatMin;
   bool                 sessionEndFlat;
   int                  sessionEndHour;
   int                  sessionEndMin;
   int                  sessionStartHour;
   int                  sessionStartMin;
   //--- execution
   bool                 signalOnNewBarOnly;
   ENUM_TIMEFRAMES      signalTimeframe;
   bool                 useLimitEntry;         // strategy decides per signal
   int                  pendingExpiryMinutes;
   int                  deviationPoints;
   int                  maxRetries;
   //--- exits (engine level, applied in addition to strategy Manage())
   bool                 breakEvenOnBarClose;     // require a completed bar beyond +1R
   ENUM_TIMEFRAMES      beConfirmTf;            // bar used for that confirmation (PERIOD_CURRENT = signal TF)
   double               breakEvenAtR;          // 0 = disabled
   double               beOffsetR;             // stop lands at BE + xR instead of exactly entry
   double               partial1AtR;           // 0 = disabled
   double               partial1Pct;
   double               partial2AtR;
   double               partial2Pct;
   double               trailAtR;              // trail after this R (0 = disabled)
   double               trailDistanceR;        // trail distance in R units
   int                  timeStopMinutes;       // 0 = disabled
   double               timeStopUnlessR;      // 0 = unconditional; else skip the time stop at/above this R
   //--- safety
   bool                 newsFilter;
   bool                 newsFailClosed;        // no usable calendar -> refuse new entries
   bool                 newsUseCalendar;       // prefer the terminal's economic calendar (live)
   string               newsFile;              // MQL5/Files/<name>.csv
   int                  newsBeforeMin;
   int                  newsAfterMin;
   bool                 marginCheck;
   double               marginFreeFloorPct;    // e.g. 25.0 = keep 25% free
   bool                 ledgerEnabled;
   string               ledgerFile;            // MQL5/Files/<name>.csv
   ENUM_EA_LOG_LEVEL    logLevel;
   //--- constructor-equivalent defaults
   void Reset()
   {
      magic                  = 0;
      strategyName           = "EA";
      sourceDoc              = "";
      symbols                = "";
      requireSupportedList   = false;
      riskPct                = 0.5;
      riskBaseBalance        = false;
      qualifyingDayAmount    = 0.0;
      qualifyingDaysTarget   = 0;
      maxSpreadPoints        = 0.0;
      dailyLossPct           = 0.0;
      weeklyLossPct          = 0.0;
      flattenOnHalt          = false;
      oneEntryAccountWide    = false;
      riskBaseInitialBalance = false;
      riskInitialBalance     = 0.0;
      newsFlatBeforeMin      = 0.0;
      dayAnchorServer        = false;
      dayLockFirstWin        = false;
      dayLockAfterTrades     = 0;
      dayLockAfterLosses     = 0;
      monthlyLossPct         = 0.0;
      lossStreakPause        = 0;
      lossStreakPauseHours   = 24;
      commissionPerLotRT     = 0.0;
      maxCostR               = 0.0;
      maxRequestsPerDay      = 0;
      totalDdPct             = 0.0;
      profitTargetPct        = 0.0;
      softTargetPct          = 0.0;
      softTargetRiskMult     = 0.5;
      maxTradesPerDay        = 0;
      maxOpenPositions       = 1;
      minSecondsBetweenTrades= 60;
      useHwmThrottle         = false;
      hwmTier1Dd             = 2.0;  hwmTier1Mult = 0.50;
      hwmTier2Dd             = 4.0;  hwmTier2Mult = 0.25;
      hwmHaltDd              = 6.0;
      clock                  = EA_CLOCK_LONDON;
      serverWinterGmtOffset  = 2;
      serverOffsetAuto       = false;
      serverFollowsEuDst     = true;
      noTradeAfterHour       = -1;   noTradeAfterMin = 0;
      fridayFlat             = false;
      fridayFlatHour         = 21;   fridayFlatMin = 0;
      sessionEndFlat         = false;
      sessionEndHour         = -1;   sessionEndMin = 0;
      sessionStartHour       = 0;    sessionStartMin = 0;
      signalOnNewBarOnly     = true;
      signalTimeframe        = PERIOD_M5;
      useLimitEntry          = false;
      pendingExpiryMinutes   = 15;
      deviationPoints        = 20;
      maxRetries             = 3;
      breakEvenOnBarClose    = false;
      beConfirmTf            = PERIOD_CURRENT;
      breakEvenAtR           = 0.0;
      beOffsetR              = 0.0;
      partial1AtR            = 0.0;  partial1Pct = 50.0;
      partial2AtR            = 0.0;  partial2Pct = 30.0;
      trailAtR               = 0.0;  trailDistanceR = 0.5;
      timeStopMinutes        = 0;
      timeStopUnlessR        = 0.0;
      newsFilter             = false;
      newsFailClosed         = false;
      newsUseCalendar        = false;
      newsFile               = "";
      newsBeforeMin          = 30;
      newsAfterMin           = 30;
      marginCheck            = true;
      marginFreeFloorPct     = 0.0;
      ledgerEnabled          = false;
      ledgerFile             = "";
      logLevel               = EA_LOG_EVENTS;
   }
};

//--- the single global configuration used by the engine
SEASettings g_eaCfg;

//+------------------------------------------------------------------+
//| Small helpers                                                    |
//+------------------------------------------------------------------+
double EA_Point(const string sym)
{
   double p = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(p <= 0.0) p = 0.00001;
   return p;
}

int EA_Digits(const string sym)
{
   int d = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   if(d < 0 || d > 8) d = 5;
   return d;
}

//--- 1 pip = 10 points on 3/5-digit quotes, else 1 point
double EA_PipSize(const string sym)
{
   int d = EA_Digits(sym);
   double p = EA_Point(sym);
   if(d == 3 || d == 5) return p * 10.0;
   return p;
}

double EA_SpreadPoints(const string sym)
{
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double p   = EA_Point(sym);
   if(ask <= 0.0 || bid <= 0.0 || p <= 0.0) return 1e12; // fail closed
   return (ask - bid) / p;
}

bool EA_SymbolReady(const string sym)
{
   if(sym == "") return false;
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0) return false;
   if((int)SymbolInfoInteger(sym, SYMBOL_TRADE_MODE) == (int)SYMBOL_TRADE_MODE_DISABLED) return false;
   MqlTick t;
   if(!SymbolInfoTick(sym, t)) return false;
   // stale feed guard: reject quotes older than 60s in live trading
   if(!MQLInfoInteger(MQL_TESTER) && TimeTradeServer() - t.time > 60) return false;
   return true;
}

double EA_NormalizePrice(const string sym, double price)
{
   double tick = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0) tick = EA_Point(sym);
   if(tick <= 0.0) return price;
   return MathRound(price / tick) * tick;
}

double EA_NormalizeVolume(const string sym, double vol)
{
   double minV = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxV = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(step <= 0.0 || minV <= 0.0) return 0.0;
   vol = MathFloor(vol / step + 1e-9) * step;
   vol = MathMin(MathMax(vol, minV), maxV);
   // normalise floating point lattice (0.30000000000000004 -> 0.30)
   int    d    = 3;
   double s    = step;
   while(s < 1.0 && d < 8) { s *= 10.0; d++; }
   if(s >= 1.0) vol = MathRound(vol * MathPow(10, d - 1)) / MathPow(10, d - 1);
   return vol;
}

double EA_MinStopDistance(const string sym)
{
   double p    = EA_Point(sym);
   long   stop = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
   long   frz  = SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL);
   double d    = (double)MathMax(stop, frz) * p;
   double spread = EA_SpreadPoints(sym) * p;
   if(spread > 1e11) spread = 0.0;
   return MathMax(d, spread * 2.0);
}

//--- money risked if 1 lot is stopped `slDistance` away
double EA_LossPerLot(const string sym, double slDistance)
{
   double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0.0) tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0 || slDistance <= 0.0) return 0.0;
   return (slDistance / tickSize) * tickValue;
}

//--- all-in money lost per lot when stopped: price risk + commission
double EA_LossPerLotAllIn(const string sym, double slDistance, double commissionPerLotRT)
{
   return EA_LossPerLot(sym, slDistance) + MathMax(0.0, commissionPerLotRT);
}

//--- round-trip cash cost per lot (spread + commission)
double EA_CostPerLot(const string sym, double commissionPerLotRT)
{
   double spread = EA_SpreadPoints(sym);
   if(spread > 1e11) return 0.0;
   double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0) return MathMax(0.0, commissionPerLotRT);
   double spreadCash = (spread * EA_Point(sym) / tickSize) * tickValue;
   return spreadCash + MathMax(0.0, commissionPerLotRT);
}

//--- all-in cost expressed in R units for a given stop distance
double EA_CostInR(const string sym, double slDistance, double commissionPerLotRT)
{
   double loss = EA_LossPerLot(sym, slDistance);
   if(loss <= 0.0) return 1e9;
   return EA_CostPerLot(sym, commissionPerLotRT) / loss;
}

double EA_LotsForRisk(const string sym, double riskMoney, double slDistance)
{
   double lossPerLot = EA_LossPerLot(sym, slDistance);
   if(lossPerLot <= 0.0 || riskMoney <= 0.0) return 0.0;
   return EA_NormalizeVolume(sym, riskMoney / lossPerLot);
}

//+------------------------------------------------------------------+
//| London wall-clock engine                                         |
//|                                                                  |
//| The broker server clock is the only trustworthy clock in the     |
//| terminal. We convert it to UTC using the configured winter GMT   |
//| offset (+1h when the broker follows EU DST) and then to the      |
//| Europe/London wall clock using the EU DST rule:                  |
//|   summer time = last Sunday of March 01:00 UTC                   |
//|                 .. last Sunday of October 01:00 UTC              |
//+------------------------------------------------------------------+
bool EA_IsEuDst(const datetime utc)
{
   MqlDateTime dt;
   if(!TimeToStruct(utc, dt)) return false;
   int year = dt.year;

   //--- last Sunday of March
   MqlDateTime mar;
   mar.year = year; mar.mon = 3; mar.day = 31; mar.hour = 0; mar.min = 0; mar.sec = 0;
   datetime m31 = StructToTime(mar);
   MqlDateTime tmp;
   TimeToStruct(m31, tmp);
   int marchLastSun = 31 - tmp.day_of_week;      // 0=Sunday
   mar.day = marchLastSun; mar.hour = 1;
   datetime dstStart = StructToTime(mar);

   //--- last Sunday of October
   MqlDateTime oct;
   oct.year = year; oct.mon = 10; oct.day = 31; oct.hour = 0; oct.min = 0; oct.sec = 0;
   datetime o31 = StructToTime(oct);
   TimeToStruct(o31, tmp);
   int octLastSun = 31 - tmp.day_of_week;
   oct.day = octLastSun; oct.hour = 1;
   datetime dstEnd = StructToTime(oct);

   return (utc >= dstStart && utc < dstEnd);
}

//--- server clock offset from GMT (hours), DST aware
int EA_ServerGmtOffsetHours()
{
   //--- the doc rule: query MT5 server time, never hard-code the offset
   if(g_eaCfg.serverOffsetAuto)
   {
      long diff = (long)TimeTradeServer() - (long)TimeGMT();
      return (int)MathRound((double)diff / 3600.0);
   }
   int winter = g_eaCfg.serverWinterGmtOffset;
   if(!g_eaCfg.serverFollowsEuDst) return winter;
   // first approximation: assume winter offset, then refine once
   datetime approxUtc = TimeTradeServer() - (datetime)(winter * 3600);
   if(EA_IsEuDst(approxUtc)) return winter + 1;
   datetime approxUtc2 = TimeTradeServer() - (datetime)((winter + 1) * 3600);
   if(EA_IsEuDst(approxUtc2)) return winter + 1;
   return winter;
}

datetime EA_ServerToUtc(const datetime serverTime)
{
   return serverTime - (datetime)(EA_ServerGmtOffsetHours() * 3600);
}

datetime EA_UtcToLondon(const datetime utcTime)
{
   return utcTime + (datetime)(EA_IsEuDst(utcTime) ? 3600 : 0);
}

datetime EA_LondonNow()
{
   return EA_UtcToLondon(EA_ServerToUtc(TimeTradeServer()));
}

//--- current EA clock (London or server), per configuration
datetime EA_ClockNow()
{
   if(g_eaCfg.clock == EA_CLOCK_SERVER) return TimeTradeServer();
   return EA_LondonNow();
}

//--- convert a wall-clock time on the EA clock to broker server time
datetime EA_ClockToServer(const datetime clockTime)
{
   if(g_eaCfg.clock == EA_CLOCK_SERVER) return clockTime;
   // clockTime is London wall time -> subtract London offset -> UTC -> add server offset
   datetime asUtc = clockTime - (datetime)(EA_IsEuDst(clockTime) ? 3600 : 0);
   return asUtc + (datetime)(EA_ServerGmtOffsetHours() * 3600);
}

//--- minutes since midnight on a datetime
int EA_MinutesOfDay(const datetime t)
{
   MqlDateTime dt;
   if(!TimeToStruct(t, dt)) return 0;
   return dt.hour * 60 + dt.min;
}

//--- true when wall-clock time lies inside [from,to) - overnight windows supported
bool EA_InWindow(const datetime nowClock, const int fromHour, const int fromMin,
                 const int toHour, const int toMin)
{
   if(fromHour < 0 || toHour < 0) return false;
   int now  = EA_MinutesOfDay(nowClock);
   int from = fromHour * 60 + fromMin;
   int to   = toHour * 60 + toMin;
   if(from == to) return true;                       // all day
   if(from < to)  return (now >= from && now < to);
   return (now >= from || now < to);                 // crosses midnight
}

//--- convenience: is `now` a weekday (Mon..Fri) on the configured clock
bool EA_IsWeekday(const datetime t)
{
   MqlDateTime dt;
   if(!TimeToStruct(t, dt)) return false;
   return (dt.day_of_week >= 1 && dt.day_of_week <= 5);
}

//--- seconds until the next London midnight (used by daily throttles)
int EA_SecondsToNextDay(const datetime clockNow)
{
   MqlDateTime dt;
   if(!TimeToStruct(clockNow, dt)) return 0;
   int secs = dt.hour * 3600 + dt.min * 60 + dt.sec;
   return 86400 - secs;
}

//+------------------------------------------------------------------+
//| Logging (rate-limited)                                           |
//+------------------------------------------------------------------+
string g_eaLastLogKey  = "";
datetime g_eaLastLogTime = 0;

string EA_PrettyMagic(const ulong m)
{
   return IntegerToString((long)m);
}

void EA_Log(const int level, const string msg, const bool throttleSeconds = false)
{
   if(level > (int)g_eaCfg.logLevel) return;
   if(MQLInfoInteger(MQL_OPTIMIZATION) && level > EA_LOG_ERRORS) return;
   if(throttleSeconds)
   {
      if(g_eaLastLogKey == msg && TimeTradeServer() - g_eaLastLogTime < 60) return;
      g_eaLastLogKey  = msg;
      g_eaLastLogTime = TimeTradeServer();
   }
   PrintFormat("[%s|%s] %s", g_eaCfg.strategyName, EA_PrettyMagic(g_eaCfg.magic), msg);
}

//+------------------------------------------------------------------+
//| News blackout - CSV file and/or the terminal's economic calendar |
//|                                                                  |
//| Two sources, in one cache (the gate reads g_eaNewsTimes only):    |
//|  1. the terminal's own calendar (cfg.newsUseCalendar, live only - |
//|     the Strategy Tester has no calendar data, so backtests use   |
//|     the file), and                                             |
//|  2. a CSV in MQL5/Files:  date,time,currency,impact              |
//|     e.g. 2026.10.02,13:30,USD,HIGH  (impact >= 2 or "HIGH")     |
//|                                                                  |
//| TIME FRAME: by contract the CSV times are UTC (the gate converts |
//| "now" with EA_ServerToUtc).  Times taken from the terminal        |
//| calendar are SERVER time (that is the calendar API's own         |
//| convention), so a CSV produced by MQL5_Master\Scripts\           |
//| ExportRedNews.mq5 declares its frame with a first-row marker:     |
//|     #timezone=server,,,                                          |
//| (the three empty fields keep the 4-field row structure the       |
//| parser relies on).  A file without the marker is UTC, exactly as  |
//| the delivered engines always read it.                            |
//+------------------------------------------------------------------+
datetime g_eaNewsTimes[];
int      g_eaNewsCount = 0;
string   g_eaNewsLoadedFile = "";
datetime g_eaNewsLoadStamp = 0;
bool     g_eaNewsServerFrame = false;   // times are broker server time, not UTC

//--- how far around "now" the live calendar is queried
#define EA_NEWS_CAL_PAST_DAYS    2
#define EA_NEWS_CAL_FUTURE_DAYS 30

//--- "now" expressed in the frame the loaded times use
datetime EA_NewsNowRef()
{
   return g_eaNewsServerFrame ? TimeTradeServer() : EA_ServerToUtc(TimeTradeServer());
}

//--- load high-impact events for this engine's symbols from the terminal's own
//--- economic calendar.  Returns false when there is nothing to load - which is
//--- also ALWAYS the case inside the Strategy Tester (the calendar API has no
//--- data there, returns 0/error 4014), so the caller falls back to the CSV.
bool EA_LoadCalendarNews()
{
   if(MQLInfoInteger(MQL_TESTER)) return false;

   datetime now = TimeTradeServer();
   datetime from = now - (datetime)((long)EA_NEWS_CAL_PAST_DAYS * 86400);
   datetime to   = now + (datetime)((long)EA_NEWS_CAL_FUTURE_DAYS * 86400);

   MqlCalendarValue values[];
   ResetLastError();
   int n = CalendarValueHistory(values, from, to, NULL, NULL);
   if(n <= 0)
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("economic calendar: no events for %s..%s (count %d, err %d)",
             TimeToString(from, TIME_DATE), TimeToString(to, TIME_DATE), n, GetLastError()));
      return false;
   }

   int kept = 0;
   for(int i = 0; i < n; i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev)) continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH) continue;   // red-folder rule

      string cc = "ALL";
      MqlCalendarCountry country;
      if(CalendarCountryById(ev.country_id, country) && StringLen(country.currency) > 0)
         cc = country.currency;
      if(cc != "" && cc != "ALL" && StringFind(g_eaCfg.symbols, cc) < 0) continue;

      ArrayResize(g_eaNewsTimes, kept + 1, 32);
      g_eaNewsTimes[kept] = values[i].time;                     // server time
      kept++;
   }
   g_eaNewsCount      = kept;
   g_eaNewsServerFrame = true;                                  // calendar times are server time
   EA_Log(EA_LOG_EVENTS, StringFormat("economic calendar: %d high-impact event(s) kept for %s",
          kept, g_eaCfg.symbols));
   return (kept > 0);
}

void EA_LoadNewsCache()
{
   if(!g_eaCfg.newsFilter) return;
   if(g_eaCfg.newsFile == "" && !g_eaCfg.newsUseCalendar) return;

   //--- the cache key is what actually supplies the events, so switching source
   //--- (or no CSV at all) still reloads on the hourly stamp and never per tick
   string sourceKey = (g_eaCfg.newsUseCalendar && !MQLInfoInteger(MQL_TESTER))
                      ? "<terminal calendar>" : g_eaCfg.newsFile;
   if(g_eaNewsLoadedFile == sourceKey && TimeTradeServer() - g_eaNewsLoadStamp < 3600) return;

   g_eaNewsLoadedFile  = sourceKey;
   g_eaNewsLoadStamp   = TimeTradeServer();
   g_eaNewsCount       = 0;
   g_eaNewsServerFrame = false;
   ArrayResize(g_eaNewsTimes, 0);

   //--- 1. the terminal's own calendar first (live only - see EA_LoadCalendarNews)
   if(g_eaCfg.newsUseCalendar)
   {
      if(MQLInfoInteger(MQL_TESTER))
         EA_Log(EA_LOG_EVENTS, "news: the terminal calendar is unavailable in the Strategy Tester - " +
                "using the CSV file");
      else if(EA_LoadCalendarNews())
         return;                       // calendar supplied the events
      else
         EA_Log(EA_LOG_EVENTS, "news: no calendar events - falling back to the CSV file");
   }

   //--- 2. the CSV (also the tester path, and the delivered default)
   if(g_eaCfg.newsFile == "")
   {
      if(g_eaCfg.newsFailClosed)
         EA_Log(EA_LOG_ERRORS, "news: no calendar events and no CSV file configured - " +
                "FAIL CLOSED: no new entries until one of them is available");
      return;
   }

   int fh = FileOpen(g_eaCfg.newsFile, FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(fh == INVALID_HANDLE)
   {
      //--- the message has to state the CONSEQUENCE: with newsFailClosed a
      //--- missing calendar stops every new entry (EA_NewsBlocked returns true),
      //--- and calling that "inert" would send the user hunting for a strategy
      //--- bug instead of copying the file (docs/EA_BUG_AUDIT.md, tenth pass)
      if(g_eaCfg.newsFailClosed)
         EA_Log(EA_LOG_ERRORS, StringFormat("news file '%s' not found (error %d) - FAIL CLOSED: " +
                "no new entries until the calendar is in MQL5\\Files",
                g_eaCfg.newsFile, GetLastError()));   // once per engine per hour (load cache)
      else
         EA_Log(EA_LOG_EVENTS, StringFormat("news file '%s' not found - news filter inert",
                g_eaCfg.newsFile));
      return;
   }
   while(!FileIsEnding(fh))
   {
      string d  = FileReadString(fh);
      string t  = FileReadString(fh);
      string cc = FileReadString(fh);
      string im = FileReadString(fh);
      //--- frame marker written by ExportRedNews.mq5: "#timezone=server,,,"
      //--- (three empty fields so the 4-field row structure stays aligned)
      if(StringFind(d, "#timezone") == 0)
      {
         if(StringFind(d, "server") > 0) g_eaNewsServerFrame = true;
         continue;
      }
      if(d == "" || t == "") continue;
      if(StringFind(im, "HIGH") < 0 && StringFind(im, "High") < 0 && StringToInteger(im) < 2) continue;
      if(cc != "" && cc != "ALL" && StringFind(g_eaCfg.symbols, cc) < 0) continue;
      string stamp = d + " " + t;
      datetime nt  = StringToTime(stamp);
      if(nt > 0) { ArrayResize(g_eaNewsTimes, g_eaNewsCount + 1, 32); g_eaNewsTimes[g_eaNewsCount] = nt; g_eaNewsCount++; }
   }
   FileClose(fh);
   EA_Log(EA_LOG_EVENTS, StringFormat("news cache loaded: %d blocking events", g_eaNewsCount));
}

//--- minutes until the next blocking red event (-1 when none is pending)
int EA_NewsMinutesToNext()
{
   if(!g_eaCfg.newsFilter) return -1;
   EA_LoadNewsCache();
   if(g_eaNewsCount == 0) return -1;
   datetime nowRef = EA_NewsNowRef();       // same frame as the loaded times
   long best = -1;
   for(int i = 0; i < g_eaNewsCount; i++)
   {
      long secs = (long)g_eaNewsTimes[i] - (long)nowRef;
      if(secs < 0) continue;
      if(best < 0 || secs < best) best = secs;
   }
   if(best < 0) return -1;
   return (int)MathFloor((double)best / 60.0);
}

bool EA_NewsBlocked()
{
   if(!g_eaCfg.newsFilter) return false;
   EA_LoadNewsCache();
   if(g_eaNewsCount == 0) return g_eaCfg.newsFailClosed;   // fail closed without a calendar
   datetime nowRef = EA_NewsNowRef();       // same frame as the loaded times
   for(int i = 0; i < g_eaNewsCount; i++)
   {
      datetime t = g_eaNewsTimes[i];
      if(nowRef >= t - (datetime)(g_eaCfg.newsBeforeMin * 60) &&
         nowRef <= t + (datetime)(g_eaCfg.newsAfterMin * 60))
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Evidence ledger (one CSV row per execution decision)             |
//+------------------------------------------------------------------+
void EA_Ledger(const string action, const string sym, const double price,
               const double sl, const double tp, const double lots,
               const string note)
{
   if(!g_eaCfg.ledgerEnabled || g_eaCfg.ledgerFile == "") return;
   if(MQLInfoInteger(MQL_OPTIMIZATION)) return;
   int fh = FileOpen(g_eaCfg.ledgerFile, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(fh == INVALID_HANDLE) return;
   FileSeek(fh, 0, SEEK_END);
   if(FileTell(fh) == 0)
      FileWrite(fh, "utc_time", "ea", "magic", "action", "symbol", "price", "sl", "tp", "lots", "equity", "note");
   FileWrite(fh,
             TimeToString(EA_ServerToUtc(TimeTradeServer()), TIME_DATE | TIME_SECONDS),
             g_eaCfg.strategyName,
             IntegerToString((long)g_eaCfg.magic),
             action, sym,
             DoubleToString(price, EA_Digits(sym)),
             DoubleToString(sl, EA_Digits(sym)),
             DoubleToString(tp, EA_Digits(sym)),
             DoubleToString(lots, 2),
             DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2),
             note);
   FileClose(fh);
}

//+------------------------------------------------------------------+
//| EA context - everything a strategy needs to decide on one tick    |
//+------------------------------------------------------------------+
struct SEAContext
{
   string      symbol;
   int         index;               // index inside the configured list
   datetime    nowServer;           // TimeTradeServer()
   datetime    nowClock;            // London (or server) wall clock
   int         dayOfWeek;
   int         clockMinutes;        // minutes since midnight on the clock
   bool        inSession;           // inside [sessionStart, sessionEnd)
   bool        pastNoTradeHour;     // after the late-entry cutoff
   bool        fridayCloseZone;     // inside the Friday flat window
   //--- prices
   double      bid, ask, mid, spreadPoints;
   double      atr;                 // primary ATR (strategy timeframe)
   double      atrD1;               // daily ATR
   double      point, pip;
   //--- indicators pre-computed for convenience
   double      ema20, ema50, ema200;
   double      emaH1_50, emaH1_200, emaD1_200;
   double      rsi14;
   double      adx14;
   double      adxH1;               // H1 ADX(14): the regime timeframe the docs quote
   double      adxH4;               // H4 ADX(14): grid gates quote 1H and 4H together
   double      atrH1;               // H1 ATR(14): grid spacing and tripwires quote 1H ATR
   //--- session reference range (built by the strategy when needed)
   double      rangeHigh, rangeLow;
   //--- account state
   double      equity, balance;
   double      dayStartEquity;
   double      riskPct;             // after daily / HWM throttles
   int         qualifyingDays;
   bool        riskHalted;          // no new risk today
   string      riskHaltReason;
   double      floatingPl;          // on this symbol+magic
   int         openPositions;       // this symbol+magic
   int         openPositionsAll;    // all symbols of this EA
   double      dayRealizedPl;       // completed trades only (no floating)
   double      dayPl;               // realized + floating
   int         tradesToday;
   bool        newsBlocked;
   bool        terminalReady;
};

//--- reset a context to neutral values
void EA_ContextReset(SEAContext &ctx)
{
   ctx.symbol = ""; ctx.index = 0;
   ctx.nowServer = 0; ctx.nowClock = 0; ctx.dayOfWeek = 0; ctx.clockMinutes = 0;
   ctx.inSession = true; ctx.pastNoTradeHour = false; ctx.fridayCloseZone = false;
   ctx.bid = 0; ctx.ask = 0; ctx.mid = 0; ctx.spreadPoints = 0;
   ctx.atr = 0; ctx.atrD1 = 0; ctx.point = 0; ctx.pip = 0;
   ctx.ema20 = 0; ctx.ema50 = 0; ctx.ema200 = 0;
   ctx.emaH1_50 = 0; ctx.emaH1_200 = 0; ctx.emaD1_200 = 0;
   ctx.rsi14 = 0; ctx.adx14 = 0; ctx.adxH1 = 0; ctx.adxH4 = 0;
   ctx.atrH1 = 0;
   ctx.rangeHigh = 0; ctx.rangeLow = 0;
   ctx.equity = 0; ctx.balance = 0; ctx.dayStartEquity = 0;
   ctx.riskPct = 0; ctx.riskHalted = false; ctx.riskHaltReason = "";
   ctx.floatingPl = 0; ctx.openPositions = 0; ctx.openPositionsAll = 0;
   ctx.dayRealizedPl = 0; ctx.tradesToday = 0;
   ctx.newsBlocked = false; ctx.terminalReady = false;
}

#endif // EA_CORE_MQH
//+------------------------------------------------------------------+
