//+------------------------------------------------------------------+
//|                                      EA_CF_FirstRedDay.mq5        |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| ChartFanatics playbook: First Red Day (Alex Temiz)                |
//| Card    : chartfanatics/todos/first-red-day.md            (#10)   |
//| Source  : chartfanatics/pdf/first-red-day.pdf                     |
//| Magic   : 3214                                                   |
//|                                                                  |
//| "Stocks that go up like a rocket almost always come back down."   |
//| The setup is short-only and entirely mechanical:                  |
//|                                                                  |
//|   1. CONFIRM THE RUN - three or more strong green days in a row,  |
//|      ideally each stronger than the last, and the total move       |
//|      extended (the playbook's "parabolic, not a slow trend").      |
//|   2. MARK THE PREVIOUS DAY'S CLOSE - the red-to-green line.        |
//|      "The trade does not start until price goes under that line."  |
//|   3. DO NOT ANTICIPATE - no shorting because it 'should' come      |
//|      down; the entry is the break below the line.                  |
//|   4. TWO PATHS: gap up -> push higher then fade -> break the line;  |
//|      gap down -> bounce toward the line fails -> enter on the        |
//|      rejection.  Both are the same trigger: a close below the       |
//|      previous day's close that is not a reclaim.                    |
//|   5. STOP - a reclaim of the line that holds invalidates the idea;  |
//|      the stop sits just above it and is never widened.              |
//|   6. PROFITS - cover portions into the weakness (engine partial),   |
//|      hold a runner because these stay weak for days, and re-enter   |
//|      when a bounce fails again below the line.                      |
//|                                                                  |
//| `[interpretation]`: the playbook trades single stocks it picks for  |
//| the run's quality; an EA cannot see float or news, so the run is    |
//| read mechanically (>= 3 green days, each close higher, total move   |
//| >= InpRunMinPct) and the symbol list is the user's instrument       |
//| selection.  The 'starter size then add on confirmation' schedule is |
//| documented as not implemented - the engine opens one risk-sized     |
//| position at the confirmation, which is the main size the playbook   |
//| describes.                                                          |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics First Red Day - short the first close below the previous day's close after a multi-day run"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade   = "US100,US500,GER40";  // Instrument selection is the user's universe
input ulong             InpMagicNumber      = 3214;                 // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct          = 0.50;                 // Risk per trade (% of equity)
input int               InpStage             = 5;                   // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input double            InpMaxSpreadPoints  = 3.0;                  // Spread gate in points (0 = off)
input double            InpDailyLossPct     = 1.50;                 // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset  = 2;                    // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;        // Log verbosity
input double            InpCommissionPerLotRT = 0.0;                // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.12;               // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;               // Write the engine evidence ledger CSV
//--- the run (step 1)
input int    InpRunDays      = 3;      // "three or more strong days ... one green day is not enough"
input double InpRunMinPct    = 25.0;   // [interpretation] total run that counts as parabolic (the doc gives no number)
input bool   InpRequireStronger = true; // "ideally with each day stronger than the last"
//--- the line and the trigger (steps 2-4)
input double InpBreakBufferAtr = 0.05; // A close this far under the line is a confirmed break, not a touch
input double InpStopBufferAtr  = 0.15; // The stop sits just above the line ("never widen the stop")
input bool   InpGapDownPath    = true; // Also take the gap-down path (bounce fails at the line)
input double InpBounceTouchAtr = 0.50; // How close the bounce must come to the line to count as a failure
//--- exits (step 6)
input double InpPartial1AtR   = 1.0;   // "cover portions of your position into the weakness"
input double InpPartial1Pct   = 50.0;
input double InpTrailAtR      = 1.5;   // "hold a small portion ... they often stay weak for days"
input double InpTrailDistR    = 1.0;

//+------------------------------------------------------------------+
class CCfFirstRedDay : public CEAStrategy
{
public:
   void OnInitStrategy()
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("5-stage policy: stage %d active (risk %.3f%%, %d trades/day max)",
             InpStage, g_eaCfg.riskPct, g_eaCfg.maxTradesPerDay), true);
      EA_Log(EA_LOG_EVENTS, "first red day armed: >= 3-day run, short the loss of the red-to-green line, stop just above it",
             true);
   }

   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_FIRST_RED_DAY";
      cfg.sourceDoc             = "chartfanatics/pdf/first-red-day.pdf (card #10)";
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
      cfg.maxTradesPerDay       = 2;      // a bounce failure may give a second entry, not a third
      //--- [interpretation]: the doc warns that messing up the first trade leads to forcing the next
      //--- (the FOMO con).  One loss therefore ends the day; the run's own second chance is a
      //--- different session.
      cfg.dayLockAfterLosses    = 1;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 300;
      cfg.sessionStartHour      = 14;  cfg.sessionStartMin = 25;
      cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;
      cfg.noTradeAfterHour      = 20;  cfg.noTradeAfterMin = 0;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = false;                 // "do not anticipate" - the break must happen
      cfg.breakEvenAtR          = 1.0;                   // "hold a position" safely once it works
      cfg.partial1AtR           = InpPartial1AtR;  cfg.partial1Pct = InpPartial1Pct;
      cfg.trailAtR              = InpTrailAtR;     cfg.trailDistanceR = InpTrailDistR;
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_first_red_day_ledger.csv";
      cfg.newsFilter            = false;
      cfg.logLevel              = InpLogLevel;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession || ctx.atr <= 0.0) return false;

      //--- step 1: the multi-day run.  d[1] is yesterday (the last green day of the run), and the
      //--- run must still be the freshest thing on the chart: today is the first red day.
      MqlRates d[];
      if(EA_Rates(ctx.symbol, PERIOD_D1, 0, InpRunDays + 24, d) < InpRunDays + 22) return false;

      double runLow = d[1].low;
      bool   stronger = true;
      for(int i = 1; i <= InpRunDays; i++)
      {
         if(d[i].close <= d[i].open) return false;                 // every day of the run closed green
         runLow = MathMin(runLow, d[i].low);
         if(i < InpRunDays)
         {
            if(d[i].close <= d[i + 1].close) return false;         // each day closed higher than the previous
            if(InpRequireStronger && (d[i].close - d[i].open) < (d[i + 1].close - d[i + 1].open))
               stronger = false;                                   // "ideally each day stronger than the last"
         }
      }
      if(!stronger) return false;
      double runStart = d[InpRunDays].open;
      if(runStart <= 0.0) return false;
      double runPct = (d[1].close - runStart) / runStart * 100.0;
      if(runPct < InpRunMinPct) return false;                      // "a parabolic move, not a slow trend up"

      double line = d[1].close;                                    // step 2: the red-to-green line

      //--- step 3-4: the trigger.  Never anticipate: the last closed bar must CLOSE below the line.
      MqlRates m[];
      if(EA_Rates(ctx.symbol, g_eaIndTf, 0, 6, m) < 5) return false;
      if(!(m[1].close < m[1].open)) return false;
      if(!(m[1].close < line - InpBreakBufferAtr * ctx.atr)) return false;

      //--- gap-up path: price pushed higher at the open and faded - the fade is what we are in.
      //--- gap-down path: price is below the line already and the bar is a failed bounce: it rallied
      //--- toward the line and rejected it, so its high must be near (but under) the line.
      bool gapUpFade   = (m[2].high > line) && (m[1].close < line);
      bool gapDownFail = (m[1].high <= line && m[1].high >= line - InpBounceTouchAtr * ctx.atr);
      if(InpGapDownPath)
      {
         if(!(gapUpFade || gapDownFail)) return false;
      }
      else if(!gapUpFade) return false;

      //--- step 5: the stop is a reclaim that HOLDS above the line - just above it, never widened
      double entry = ctx.bid;
      double stop  = line + InpStopBufferAtr * ctx.atr;
      if(stop <= entry) return false;                              // price already reclaimed: no trade
      double risk  = stop - entry;
      if(risk <= 0.0) return false;

      //--- step 6: cover into the weakness, hold a runner; the first target is the run's own low,
      //--- with an R-based fallback so the trade always has a destination.
      double target = runLow;
      if(target >= entry) target = entry - 2.0 * risk;
      if(MathAbs(target - entry) < risk) target = entry - 2.0 * risk;   // keep at least 1R of runway

      plan.dir = -1; plan.entry = entry; plan.stop = stop; plan.riskDist = risk;
      plan.target = target; plan.barsAgo = 1; plan.score = 70.0; plan.isLimit = false;
      plan.reason = StringFormat("first red day: %d-day run (+%.1f%%), lost the line %.2f (%s)",
                                 InpRunDays, runPct, line, gapUpFade ? "gap-up fade" : "bounce failure");
      return true;
   }
};

CCfFirstRedDay g_cfFirstRedDay;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfFirstRedDay);
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
