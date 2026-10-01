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

#include "..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD";      // Comma separated universe
input double          InpRiskPct          = 0.5;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 1.5;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 1.0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 5.0;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 10;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 2;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 3102; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpExtremeBodyAtr    = 2.50;  // Extreme candle body in ATR(M1,14)
input double InpStopAtr           = 1.50;  // Stop beyond the extreme candle (ATR)
input double InpTargetR           = 1.50;  // Fixed +1.5R target
input int    InpTimeStopMinutes   = 45;    // Close if +1R not confirmed within x min
input int    InpMaxTradesPerSession = 1;   // One signal event per symbol/session

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
      cfg.breakEvenAtR         = 1.0;                      // tested BE policy
      cfg.timeStopMinutes      = InpTimeStopMinutes;
      cfg.useHwmThrottle       = true;                     // 0-2%: 100%, 2-5%: 50%, >=5%: halt
      cfg.hwmTier1Dd           = 2.0;  cfg.hwmTier1Mult = 0.50;
      cfg.hwmTier2Dd           = 5.0;  cfg.hwmTier2Mult = 0.0;
      cfg.hwmHaltDd            = 5.0;
      cfg.newsFilter           = false;                    // attach a verified feed before live use
      cfg.logLevel             = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      if(ctx.atr <= 0.0) return false;

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

   //--- daily state machine: any net-positive first trade locks the day
   void Manage(SEAContext &ctx)
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
