//+------------------------------------------------------------------+
//| EA_strategy_improvements_plan.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Strategy improvements plan - H1 bias filter, news-day counter, stats gate
//| Source document : docs/strategy/strategy-improvements-plan.md
//| Tracker entry   : #29  |  Magic: 3115
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CStrategyImprovementsPlan class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Strategy improvements plan - H1 bias filter, news-day counter, stats gate"
#property description "Source: docs/strategy/strategy-improvements-plan.md"

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
input ulong           InpMagicNumber      = 3115; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input bool   InpUseH1EmaBias       = true;   // Sub-task 1: H1 50-EMA directional filter
input int    InpH1BiasSlopeBars   = 3;      // H1 bars used for the slope check
input bool   InpCountNewsDays     = true;   // Sub-task 2: news-blocked day counter
input int    InpInactivityDays    = 25;     // Sub-task 2: inactivity alert threshold
input bool   InpStatsSufficient   = false;  // Sub-task 3: STATS_INSUFFICIENT is an ERROR

//+------------------------------------------------------------------+
//| Strategy: Strategy improvements plan - H1 bias filter, news-day counter, stats gate
//+------------------------------------------------------------------+
class CStrategyImprovementsPlan : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "STRATEGY_IMPROVEMENTS";
      cfg.sourceDoc             = "docs/strategy/strategy-improvements-plan.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = 2.0;
      cfg.totalDdPct            = InpTotalDdPct;
      cfg.profitTargetPct       = InpProfitTargetPct;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.pendingExpiryMinutes  = 15;
      cfg.timeStopMinutes       = 45;
      cfg.breakEvenAtR          = 1.0;
      cfg.partial1AtR           = 0.0;
      cfg.useHwmThrottle        = true;
      cfg.hwmTier1Dd            = 2.0;  cfg.hwmTier1Mult = 0.50;
      cfg.hwmTier2Dd            = 5.0;  cfg.hwmTier2Mult = 0.0;  cfg.hwmHaltDd = 5.0;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- Sub-task 3: the statistical gate is an ERROR, not a warning
      if(!InpStatsSufficient)
      {
         EA_Log(EA_LOG_ERRORS, "STATS_INSUFFICIENT: statistical acceptance gate is not satisfied", true);
         return false;
      }

      SSweepParams p;
      p.Reset();
      p.rangeFromMin   = 0;
      p.rangeToMin     = 7 * 60;
      p.sessionFromMin = 7 * 60;
      p.sessionToMin   = 11 * 60;
      p.sweepMinAtr    = 0.05;
      p.sweepMaxAtr    = 0.50;
      p.reclaimWindowBars = 3;
      p.wickRatio      = 0.60;
      p.bodyRatio      = 0.60;
      p.stopBufferAtr  = 0.10;
      p.minStopAtr     = 0.60;  p.maxStopAtr = 1.50;
      p.entryRetrace   = 0.50;
      p.targetR        = 1.50;
      if(ctx.symbol == "USDJPY")
      {
         p.rangeFromMin   = 7 * 60;
         p.rangeToMin     = 13 * 60;
         p.sessionFromMin = 13 * 60 + 30;
         p.sessionToMin   = 16 * 60;
      }
      if(ctx.clockMinutes < p.sessionFromMin || ctx.clockMinutes >= p.sessionToMin) return false;
      if(!SigSweepReclaim(ctx, p, plan)) return false;

      //--- Sub-task 1: H1 50-EMA directional bias filter
      if(InpUseH1EmaBias && !H1BiasAgrees(ctx, plan.dir))
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("%s blocked by H1 50-EMA bias filter", ctx.symbol), true);
         return false;
      }
      plan.reason = StringFormat("IMPROVED %s %s", ctx.symbol, plan.reason);
      return true;
   }

   //--- Sub-task 1: price on the correct side of the H1 50-EMA and slope agrees
   bool H1BiasAgrees(SEAContext &ctx, const int dir)
   {
      if(ctx.emaH1_50 <= 0.0) return false;           // fail closed without a bias
      double hp[];
      if(EA_BufN(g_eaInd[ctx.index].hEmaH1_50, 0, 1, InpH1BiasSlopeBars + 2, hp) < InpH1BiasSlopeBars + 2)
         return false;
      double slope = hp[0] - hp[InpH1BiasSlopeBars];
      if(dir > 0) return (ctx.mid > ctx.emaH1_50 && slope >= 0.0);
      return (ctx.mid < ctx.emaH1_50 && slope <= 0.0);
   }

   //--- Sub-task 2: news-blocked day counter + inactivity alert
   void Manage(SEAContext &ctx)
   {
      static datetime lastDay = 0;
      static bool     newsSeenToday = false;
      MqlDateTime dt;
      TimeToStruct(ctx.nowClock, dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      datetime day = StructToTime(dt);
      if(ctx.newsBlocked) newsSeenToday = true;
      if(lastDay != 0 && day != lastDay)
      {
         if(newsSeenToday && InpCountNewsDays)
         {
            string key = "EA_" + IntegerToString((long)InpMagicNumber) + "_NewsDays";
            int n = GlobalVariableCheck(key) ? (int)GlobalVariableGet(key) : 0;
            GlobalVariableSet(key, (double)(n + 1));
            EA_Log(EA_LOG_EVENTS, StringFormat("news-blocked day counted (%d total)", n + 1));
         }
         newsSeenToday = false;
      }
      lastDay = day;

      string tkey = "EA_" + IntegerToString((long)InpMagicNumber) + "_LastTrade";
      if(!GlobalVariableCheck(tkey)) GlobalVariableSet(tkey, (double)ctx.nowServer);
      int idleDays = (int)((ctx.nowServer - (datetime)GlobalVariableGet(tkey)) / 86400);
      if(idleDays >= InpInactivityDays)
         EA_Log(EA_LOG_EVENTS, StringFormat("INACTIVITY ALERT: %d days without a trade", idleDays), true);
   }
};

CStrategyImprovementsPlan g_StrategyImprovementsPlan;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_StrategyImprovementsPlan);
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
