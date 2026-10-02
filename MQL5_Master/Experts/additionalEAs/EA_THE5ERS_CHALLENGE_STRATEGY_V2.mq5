//+------------------------------------------------------------------+
//| EA_THE5ERS_CHALLENGE_STRATEGY_V2.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| The5ers Challenge V2 - M1 momentum reversion + daily state machine
//| Source document : docs/prop_firm/THE5ERS-CHALLENGE-STRATEGY-V2.md
//| Tracker entry   : #16  |  Magic: 3102
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CThe5ersV2 class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "The5ers Challenge V2 - M1 momentum reversion + daily state machine"
#property description "Source: docs/prop_firm/THE5ERS-CHALLENGE-STRATEGY-V2.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY";      // Comma separated universe
input double          InpRiskPct          = 0.5;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 1.5;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 1.0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 5.0;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 10;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 2;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 3102; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpPhaseInitialBalance = 2500.0; // Persisted phase initial balance (LOCKED sizing base)
input double InpExtremeBodyAtr    = 2.50;  // Extreme candle body in ATR(M1,14)
input double InpStopAtr           = 1.50;  // Stop beyond the extreme candle (ATR)
input double InpTargetR           = 1.50;  // Fixed +1.5R target
input int    InpTimeStopMinutes   = 45;    // Close if +1R not confirmed within x min
input double InpSpreadMedianMult   = 1.50;  // Spread gate: x times the same-minute/session median
input string InpNewsFile           = "the5ers_red_news.csv"; // Red-folder calendar (MQL5/Files)
input int    InpNewsBeforeMin      = 30;    // No new entry x min before the event
input int    InpNewsAfterMin       = 30;    // No new entry x min after the event
input double InpQualifyingDayCash   = 12.50;  // 0.5% of $2,500: qualifying-day amount
input int    InpQualifyingDayCount  = 3;      // Qualifying days required per phase

//+------------------------------------------------------------------+
//| Strategy: The5ers Challenge V2 - M1 momentum reversion + daily state machine
//+------------------------------------------------------------------+
class CThe5ersV2 : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName         = "THE5ERS_V2";
      cfg.sourceDoc            = "docs/prop_firm/THE5ERS-CHALLENGE-STRATEGY-V2.md";
      cfg.symbols              = InpSymbolsToTrade;
      cfg.magic                = InpMagicNumber;
      cfg.riskPct              = InpRiskPct;               // profile B: 0.50%
      cfg.signalTimeframe      = PERIOD_M1;                // M1 momentum reversion
      cfg.clock                = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset= InpServerGmtOffset;
      cfg.maxSpreadPoints      = InpMaxSpreadPoints;
      cfg.dailyLossPct         = InpDailyLossPct;          // internal -1% daily stop
      cfg.weeklyLossPct        = 2.0;                      // internal -2% weekly stop
      cfg.totalDdPct           = InpTotalDdPct;
      cfg.profitTargetPct      = InpProfitTargetPct;
      cfg.maxTradesPerDay      = InpMaxTradesPerDay;       // max two completed trades
      cfg.maxOpenPositions     = 1;                        // one order/position account-wide
      cfg.sessionStartHour     = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour       = 16;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat       = true;
      cfg.fridayFlat           = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly   = true;                     // completed M1 candle
      cfg.useLimitEntry        = false;                    // enter at market
      cfg.breakEvenAtR         = 0.0;                      // BE is bar-close confirmed in Manage()
      cfg.timeStopMinutes      = InpTimeStopMinutes;
      cfg.useHwmThrottle       = true;                     // 0-2%: 100%, 2-5%: 50%, >=5%: halt
      cfg.hwmTier1Dd           = 2.0;  cfg.hwmTier1Mult = 0.50;
      cfg.hwmTier2Dd           = 5.0;  cfg.hwmTier2Mult = 0.0;
      cfg.hwmHaltDd            = 5.0;
      cfg.newsFilter           = true;                     // mandatory red-folder gate (fail closed)
      cfg.newsFile             = InpNewsFile;              // inert only while the file is absent
      cfg.newsBeforeMin        = InpNewsBeforeMin;
      cfg.newsAfterMin         = InpNewsAfterMin;
      cfg.newsFailClosed       = true;                     // bad calendar = no new entries
      cfg.qualifyingDayAmount  = InpQualifyingDayCash;
      cfg.qualifyingDaysTarget = InpQualifyingDayCount;
      //--- LOCKED: phase-initial balance is the sizing base; one working entry account-wide
      cfg.riskBaseInitialBalance = true;  cfg.riskInitialBalance = InpPhaseInitialBalance;
      cfg.oneEntryAccountWide    = true;   // no second entry while one is working or open
      cfg.flattenOnHalt          = true;   // governor halt = cancel entries + close
      cfg.newsFlatBeforeMin      = 15.0;   // flat 15 min before a relevant red event

      cfg.dayAnchorServer        = true;   // firm rollover on the SERVER day, never the clock day
      cfg.dayLockFirstWin        = true;   // any first net-positive exit locks the day

      cfg.dayLockAfterTrades     = 2;      // two completed sequential trades end the day


      cfg.maxRetries           = 1;                        // one revalidated retry only
      cfg.logLevel             = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      if(ctx.atr <= 0.0) return false;

      //--- certified entry windows: EURUSD/GBPUSD 07:00-11:00, USDJPY 13:30-16:00 London
      int fromMin = 7 * 60;
      int toMin   = 11 * 60;
      if(ctx.symbol == "USDJPY") { fromMin = 13 * 60 + 30; toMin = 16 * 60; }
      if(ctx.clockMinutes < fromMin || ctx.clockMinutes >= toMin) return false;

      //--- mandatory spread gate: no worse than 1.5x the same-minute/session median
      if(!SpreadWithinMedian(ctx)) return false;

      //--- M1 momentum reversion: fade a completed extreme candle
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, PERIOD_M1, 1, 30, r);
      if(got < 20) return false;

      //--- one signal event per session: remember the extreme bar time we traded
      for(int i = 1; i <= 3; i++)
      {
         MqlRates b = r[i];
         double body = MathAbs(b.close - b.open);
         if(body < InpExtremeBodyAtr * ctx.atr) continue;

         int dir = (b.close < b.open) ? +1 : -1;      // bearish extreme -> fade long
         double entry = (dir > 0) ? ctx.ask : ctx.bid;
         double stop  = (dir > 0) ? b.low  - InpStopAtr * ctx.atr
                                  : b.high + InpStopAtr * ctx.atr;
         double risk  = (dir > 0) ? entry - stop : stop - entry;
         if(risk <= 0.0) continue;

         plan.dir      = dir;
         plan.entry    = entry;
         plan.stop     = stop;
         plan.riskDist = risk;
         plan.target   = (dir > 0) ? entry + InpTargetR * risk : entry - InpTargetR * risk;
         plan.score    = 65.0;
         plan.reason   = StringFormat("M1 momentum reversion fade (body %.2f ATR)", body / ctx.atr);
         plan.barsAgo  = i;
         return true;
      }
      return false;
   }

   //--- rolling spread median per minute-of-session over the prior 60 sessions
   double   m_slotRing[1440][60];
   datetime m_slotStamp;
   datetime m_lastDay;
   int      m_dayCycle;

   void OnInitStrategy()
   {
      for(int m = 0; m < 1440; m++)
         for(int d = 0; d < 60; d++) m_slotRing[m][d] = 0.0;
      m_slotStamp = 0; m_lastDay = 0; m_dayCycle = 0;
   }

   bool SpreadWithinMedian(SEAContext &ctx)
   {
      MqlDateTime dt;
      if(!TimeToStruct(ctx.nowClock, dt)) return true;
      int slot = dt.hour * 60 + dt.min;
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      datetime day = StructToTime(dt);
      if(day != m_lastDay)
      {
         m_lastDay  = day;
         m_dayCycle = (m_dayCycle + 1) % 60;
      }
      datetime minute = ctx.nowClock - (ctx.nowClock % 60);
      if(minute != m_slotStamp && ctx.spreadPoints < 1e10 && slot >= 0 && slot < 1440)
      {
         m_slotStamp = minute;
         m_slotRing[slot][m_dayCycle] = ctx.spreadPoints;
      }
      double arr[60];
      int n = 0;
      for(int i = 0; i < 60; i++)
      {
         double v = m_slotRing[slot][i];
         if(v > 0.0) arr[n++] = v;
      }
      if(n < 20) return true;                                   // warm-up
      for(int i = 1; i < n; i++)
      {
         double key = arr[i];
         int    j   = i - 1;
         while(j >= 0 && arr[j] > key) { arr[j + 1] = arr[j]; j--; }
         arr[j + 1] = key;
      }
      double median = arr[n / 2];
      if(median > 0.0 && ctx.spreadPoints > InpSpreadMedianMult * median)
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.1f > %.2fx same-minute median %.1f - skip",
                ctx.symbol, ctx.spreadPoints, InpSpreadMedianMult, median), true);
         return false;
      }
      return true;
   }

   //--- documented BE policy: move the visible stop to entry only after a
   //--- COMPLETED M5 close beyond +1R (no intraday tick trigger)
   void Manage(SEAContext &ctx)
   {
      for(int t = g_eaTrackCount - 1; t >= 0; t--)
      {
         if(g_eaTrack[t].symbol != ctx.symbol) continue;
         if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;
         if(g_eaTrack[t].beMoved) continue;
         MqlRates m[];
         if(EA_Rates(ctx.symbol, PERIOD_M5, 1, 2, m) < 2) continue;
         double d = (g_eaTrack[t].dir > 0) ? (m[1].close - g_eaTrack[t].entry) : (g_eaTrack[t].entry - m[1].close);
         if(d >= g_eaTrack[t].riskDist)
         {
            g_eaTrack[t].beMoved = true;
            g_eaExec.Modify(g_eaTrack[t].ticket, g_eaTrack[t].entry, 0.0);
         }
      }
      DailyStateMachine(ctx);
   }

   //--- daily state machine: any net-positive first trade locks the day
   void DailyStateMachine(SEAContext &ctx)
   {
      static datetime lockedDay = 0;
      MqlDateTime dt;
      TimeToStruct(ctx.nowClock, dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      datetime day = StructToTime(dt);
      if(lockedDay == day) { EA_FlattenAll("day locked by state machine"); return; }
      if(ctx.tradesToday >= 2 && ctx.openPositions == 0 && ctx.floatingPl == 0.0)
         lockedDay = day;                       // second completed trade locks the day
      if(ctx.openPositions == 0 && ctx.dayRealizedPl > 0.0 && ctx.tradesToday >= 1)
         lockedDay = day;                       // first trade net positive -> lock
   }
};

CThe5ersV2 g_The5ersV2;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_The5ersV2);
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
