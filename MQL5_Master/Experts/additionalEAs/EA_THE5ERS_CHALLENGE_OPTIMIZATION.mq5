//+------------------------------------------------------------------+
//| EA_THE5ERS_CHALLENGE_OPTIMIZATION.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| The5ers optimization - non-market-failure elimination + Route A router
//| Source document : docs/prop_firm/THE5ERS-CHALLENGE-OPTIMIZATION.md
//| Tracker entry   : #17  |  Magic: 3103
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CChallengeOptimization class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "The5ers optimization - non-market-failure elimination + Route A router"
#property description "Source: docs/prop_firm/THE5ERS-CHALLENGE-OPTIMIZATION.md"

#include "..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY";      // Comma separated universe
input double          InpRiskPct          = 0.4;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 3.0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 1.0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 10;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 10;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 2;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 3103; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpCommissionPerLotRT = 7.00;  // Round-turn commission per lot (cost model)
input double InpMaxCostR             = 0.10;  // Priority-1 gate: reject when all-in cost > xR
input int    InpMaxRequestsPerDay    = 20;    // Rate limit: non-emergency trade requests/day
input int    InpTimeStopMinutes      = 45;    // Plateau time stop (30/45/60/90 candidates)
input double InpTargetR              = 1.50;  // Champion exit model A (fixed +1.5R)
input bool   InpUseBreakEven         = false; // Challenger policy: move stop to entry after +1R
input bool   InpTradeUsdJpyNy        = true;  // Enable the USDJPY New York combination
input int    InpUsdJpyFromMin        = 810;   // 13:30 London = 08:30 New York
input int    InpUsdJpyToMin          = 960;   // 16:00 London = 11:00 New York

//+------------------------------------------------------------------+
//| Strategy: The5ers optimization - non-market-failure elimination + Route A router
//+------------------------------------------------------------------+
class CChallengeOptimization : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "THE5ERS_OPTIMIZATION";
      cfg.sourceDoc             = "docs/prop_firm/THE5ERS-CHALLENGE-OPTIMIZATION.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;              // max 0.50% permitted for this product
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;   // Priority 1: honest cost model
      cfg.maxCostR              = InpMaxCostR;             // round-trip cost <= 0.10R
      cfg.maxRequestsPerDay     = InpMaxRequestsPerDay;    // rate-limited order requests
      cfg.dailyLossPct          = InpDailyLossPct;         // internal daily stop
      cfg.weeklyLossPct         = 2.0;                     // internal weekly stop
      cfg.totalDdPct            = InpTotalDdPct;
      cfg.profitTargetPct       = InpProfitTargetPct;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;      // max two sequential trades
      cfg.maxOpenPositions      = 1;                       // one slot account-wide
      cfg.minSecondsBetweenTrades = 60;
      cfg.useHwmThrottle        = true;                    // 50% risk tier at 2% drawdown
      cfg.hwmTier1Dd            = 2.0;  cfg.hwmTier1Mult = 0.50;
      cfg.hwmTier2Dd            = 5.0;  cfg.hwmTier2Mult = 0.0;  cfg.hwmHaltDd = 5.0;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;                    // flat by the session hard stop
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 21;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.pendingExpiryMinutes  = 15;                      // three M5 candles
      cfg.timeStopMinutes       = InpTimeStopMinutes;
      cfg.breakEvenAtR          = (InpUseBreakEven ? 1.0 : 0.0);
      cfg.partial1AtR           = 0.0;                     // no partials in this profile
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- Priority 3: accepted breakouts are no-trades; only the reversal is traded
      SSweepParams p;
      p.Reset();
      p.rangeFromMin   = 0;
      p.rangeToMin     = 7 * 60;          // 00:00-07:00 London reference range
      p.sessionFromMin = 7 * 60;
      p.sessionToMin   = 11 * 60;         // London combinations
      p.sweepMinAtr    = 0.05;
      p.sweepMaxAtr    = 0.50;
      p.reclaimWindowBars = 3;
      p.wickRatio      = 0.60;
      p.bodyRatio      = 0.60;
      p.stopBufferAtr  = 0.10;
      p.minStopAtr     = 0.60;  p.maxStopAtr = 1.50;
      p.entryRetrace   = 0.50;
      p.targetR        = InpTargetR;

      if(ctx.symbol == "USDJPY")
      {
         if(!InpTradeUsdJpyNy) return false;
         p.rangeFromMin   = 7 * 60;       // 07:00-13:00 London reference range
         p.rangeToMin     = 13 * 60;
         p.sessionFromMin = InpUsdJpyFromMin;
         p.sessionToMin   = InpUsdJpyToMin;
      }
      if(ctx.clockMinutes < p.sessionFromMin || ctx.clockMinutes >= p.sessionToMin) return false;

      if(!SigSweepReclaim(ctx, p, plan)) return false;
      plan.reason = StringFormat("OPT-ROUTE-A %s %s", ctx.symbol, plan.reason);
      return true;
   }

   //--- Priority 1: no market chase after an expired/unfilled limit.
   //--- Cancel a resting entry once price has travelled +1R away from it.
   void Manage(SEAContext &ctx)
   {
      for(int o = OrdersTotal() - 1; o >= 0; o--)
      {
         ulong t = OrderGetTicket(o);
         if(t == 0) continue;
         if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagicNumber) continue;
         if(OrderGetString(ORDER_SYMBOL) != ctx.symbol) continue;
         ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         int dir = (ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_BUY_STOP) ? +1 : -1;
         double entry = OrderGetDouble(ORDER_PRICE_OPEN);
         double sl    = OrderGetDouble(ORDER_SL);
         double risk  = MathAbs(entry - sl);
         if(risk <= 0.0 || entry <= 0.0) continue;
         double px  = (dir > 0) ? ctx.bid : ctx.ask;
         double fav = (dir > 0) ? (px - entry) : (entry - px);
         if(fav >= risk)
         {
            EA_Log(EA_LOG_EVENTS, StringFormat("%s +1R reached unfilled - cancelling entry", ctx.symbol));
            g_eaExec.CancelPending(ctx.symbol, "price reached +1R unfilled");
         }
      }
   }
};

CChallengeOptimization g_ChallengeOptimization;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_ChallengeOptimization);
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
