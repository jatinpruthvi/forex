//+------------------------------------------------------------------+
//|                                             EA_CF_AMD_Model.mq5  |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| ChartFanatics playbook: AMD Model (Tanja Trades, Apr 2025)       |
//| Card    : chartfanatics/todos/amd-model.md  (#04)                |
//| Source  : chartfanatics/pdf/amd-model.pdf                        |
//| Magic   : 3201                                                   |
//|                                                                  |
//| The playbook trades the DISTRIBUTION leg of accumulation ->       |
//| manipulation -> distribution, and never the sweep itself:         |
//|   1. Accumulation builds a range before the New York session.     |
//|   2. Manipulation sweeps one side of that range; the sweep        |
//|      extreme is the stop anchor ("stop above the high of the      |
//|      manipulation spike").                                        |
//|   3. Distribution displaces through the other side of the         |
//|      manipulation leg and leaves an imbalance behind.             |
//|   4. Entry is on the RETRACE into that imbalance - never chased   |
//|      ("if there is no retracement, skip the trade").              |
//|                                                                  |
//| Engine mapping: `SigSweepReclaim` (range sweep -> reclaim ->      |
//| displacement -> retracement limit) with the playbook's two macro  |
//| windows (09:50-10:10 and 10:50-11:10 New York) enforced on top,   |
//| two trades per session max, and a two-loss day lock.              |
//|                                                                  |
//| NOT encoded (needs a live calendar, see the card's Notes):        |
//| the "high probability day" news filter - the playbook wants the   |
//| POST-news move, so the red-folder news filter is OFF by default.  |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics AMD Model - trade the distribution leg after a manipulation sweep"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade   = "US100,US500,GER40";  // Universe (the playbook trades NQ / ES)
input ulong             InpMagicNumber      = 3201;                 // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct          = 0.50;                 // Risk per trade (% of equity)
input double            InpMaxSpreadPoints  = 3.0;                  // Spread gate in points (0 = off)
input double            InpDailyLossPct     = 1.50;                 // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset  = 2;                    // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;        // Log verbosity
//--- AMD structure (clock minutes on the London wall clock; New York = London - 5)
input int    InpRangeFromMin      = 0;      // Accumulation window start (00:00 London)
input int    InpRangeToMin        = 870;    // Accumulation window end   (14:30 London = NY open)
input int    InpMacro1FromMin     = 890;    // 14:50 London = 09:50 ET
input int    InpMacro1ToMin       = 910;    // 15:10 London = 10:10 ET
input int    InpMacro2FromMin     = 950;    // 15:50 London = 10:50 ET
input int    InpMacro2ToMin       = 970;    // 16:10 London = 11:10 ET
input bool   InpMacroWindowsOnly  = true;   // Respect the playbook's two macro windows
input int    InpReclaimWindowBars = 3;      // Max bars from the sweep to the reclaim
input double InpSweepMinAtr       = 0.05;   // Min sweep depth in ATR
input double InpSweepMaxAtr       = 1.20;   // Max sweep depth in ATR (0 = unlimited)
input double InpEntryRetrace      = 0.50;   // Limit at 50% of the displacement body (the imbalance)
input double InpStopBufferAtr     = 0.10;   // Stop buffer beyond the manipulation extreme
input double InpMinStopAtr        = 0.20;   // Reject if the stop is tighter than this
input double InpMaxStopAtr        = 2.50;   // Reject if the stop is wider than this
input double InpTargetR           = 2.00;   // Target in R (opposite side of the accumulation range)
input bool   InpRequireHtfAlign   = true;   // 1H + D1 must agree with the trade (playbook's HTF clarity)

//+------------------------------------------------------------------+
//| Strategy class                                                   |
//+------------------------------------------------------------------+
class CCfAmdModel : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_AMD_MODEL";
      cfg.sourceDoc             = "chartfanatics/pdf/amd-model.pdf (card #04)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = 3.0;
      cfg.totalDdPct            = 8.0;
      cfg.maxTradesPerDay       = 2;      // "limit yourself to two trades per session"
      cfg.dayLockAfterLosses    = 2;      // "if you take two losses, step away for the day"
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 120;
      cfg.useHwmThrottle        = true;
      cfg.hwmTier1Dd            = 2.0;  cfg.hwmTier1Mult = 0.50;
      cfg.hwmTier2Dd            = 4.0;  cfg.hwmTier2Mult = 0.25;
      cfg.hwmHaltDd             = 6.0;
      cfg.sessionStartHour      = 14;  cfg.sessionStartMin = 40;   // 09:40 ET - before macro window 1
      cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 20;   // 11:20 ET - after macro window 2
      cfg.noTradeAfterHour      = 17;  cfg.noTradeAfterMin = 0;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 19;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = true;
      cfg.pendingExpiryMinutes  = 15;      // three M5 candles for the retrace to appear
      cfg.breakEvenAtR          = 1.0;
      cfg.partial1AtR           = 1.0;  cfg.partial1Pct = 50.0;     // "take partial profits at logical targets"
      cfg.trailAtR              = 1.5;  cfg.trailDistanceR = 0.75;
      cfg.newsFilter            = false;   // the playbook's best setups ARE the post-news moves
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession) return false;
      if(ctx.atr <= 0.0) return false;
      if(InpMacroWindowsOnly && !InMacroWindow(ctx.clockMinutes)) return false;

      SSweepParams p;
      p.Reset();
      p.rangeFromMin        = InpRangeFromMin;
      p.rangeToMin          = InpRangeToMin;
      p.sessionFromMin      = InpMacro1FromMin;
      p.sessionToMin        = InpMacro2ToMin;
      p.sweepMinAtr         = InpSweepMinAtr;
      p.sweepMaxAtr         = InpSweepMaxAtr;
      p.reclaimWindowBars   = InpReclaimWindowBars;
      p.wickRatio           = 0.55;         // the manipulation candle must reject the range
      p.bodyRatio           = 0.60;         // displacement body ("breaks with intent")
      p.stopBufferAtr       = InpStopBufferAtr;
      p.minStopAtr          = InpMinStopAtr;
      p.maxStopAtr          = InpMaxStopAtr;
      p.targetR             = InpTargetR;
      p.entryRetrace        = InpEntryRetrace;
      p.requireDisplacement = true;
      p.requireMidpointBreak= true;         // the displacement must close beyond the reclaim midpoint
      p.tradeBothWays       = true;
      p.scoreBase           = 62.0;
      if(!SigSweepReclaim(ctx, p, plan)) return false;

      //--- the higher timeframe must be clear, or the playbook says no trade
      if(InpRequireHtfAlign && plan.dir != HtfBias(ctx))
      {
         plan.Reset();
         return false;
      }
      plan.reason = "AMD distribution leg: " + plan.reason;
      return true;
   }

private:
   bool InMacroWindow(const int clockMinutes)
   {
      if(clockMinutes >= InpMacro1FromMin && clockMinutes < InpMacro1ToMin) return true;
      if(clockMinutes >= InpMacro2FromMin && clockMinutes < InpMacro2ToMin) return true;
      return false;
   }

   //--- HTF clarity: D1 and H1 200-EMA agreement (the playbook reads 1H/4H/D1, not the M5 signal TF)
   int HtfBias(SEAContext &ctx)
   {
      SCascadeParams c;
      c.Reset();
      c.requireD1           = true;
      c.requireH1           = true;
      c.requireM15Structure = false;
      c.scoreBase           = 60.0;
      return SigEmaCascade(ctx, c);
   }
};

CCfAmdModel g_cfAmdModel;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfAmdModel);
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
