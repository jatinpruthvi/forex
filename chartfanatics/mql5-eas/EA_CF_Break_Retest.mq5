//+------------------------------------------------------------------+
//|                                         EA_CF_Break_Retest.mq5   |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| ChartFanatics playbook: Break & Retest (Vincent Desiano)         |
//| Card    : chartfanatics/todos/break-retest.md  (#07)             |
//| Source  : chartfanatics/pdf/break-retest.pdf                     |
//| Magic   : 3205                                                   |
//|                                                                  |
//| The trade is never the breakout - it is the RETEST:              |
//|   1. Mark the major prior level (previous day high/low,          |
//|      premarket high/low, supply/demand zone).                    |
//|   2. Wait for a CLEAN break with momentum (closed bar beyond     |
//|      the level + buffer). No entry on the break itself.          |
//|   3. The No Trade Zone: the area between the previous day's high |
//|      and low is where price chops and traps - nothing is taken   |
//|      there.                                                      |
//|   4. The battle zone: wait for the pullback to the level, then   |
//|      require a rejection (wick + close back on the right side).  |
//|   5. Stop just beyond the retest structure (above the wick high  |
//|      for shorts, below the wick low for longs). TP1 at the prior |
//|      extreme, take 25-50% off, hold runners.                     |
//|                                                                  |
//| Engine mapping: `SigBreakRetest` (session range -> accepted      |
//| break -> later retest bar that holds) plus an explicit           |
//| rejection-wick confirmation and the NTZ gate.                    |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics Break & Retest - trade the retest inside the battle zone, never the breakout"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade   = "US100,US500,GER40";  // Universe (playbook: stocks / options / futures)
input ulong             InpMagicNumber      = 3205;                 // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct          = 0.50;                 // Risk per trade (% of equity)
input int               InpStage             = 5;                    // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input double            InpMaxSpreadPoints  = 3.0;                  // Spread gate in points (0 = off)
input double            InpDailyLossPct     = 1.50;                 // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset  = 2;                    // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;        // Log verbosity
input double            InpCommissionPerLotRT = 0.0;                // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.12;               // Reject setups whose all-in cost exceeds xR
input bool              InpLedger             = true;               // Write the engine evidence ledger CSV
//--- the level, the break and the retest
input int    InpRangeFromMin   = 0;      // Premarket range start (00:00 London)
input int    InpRangeToMin     = 870;    // Premarket range end   (14:30 London = NY open)
input int    InpEntryFromMin   = 870;    // Entry window start    (14:30 London)
input int    InpEntryToMin     = 1140;   // Entry window end      (19:00 London)
input double InpMinRangeAtr    = 0.30;   // The marked range must be at least this wide
input double InpBreakBufferAtr = 0.10;   // "Clean break": closed bar beyond the level
input double InpRetestTolAtr   = 0.15;   // How close the retest must come to the level
input double InpStopBufferAtr  = 0.20;   // Stop beyond the retest structure
input double InpTargetR        = 2.00;   // TP1 fallback in R when no swing target is ahead
input double InpMinTargetR     = 1.00;   // A structural TP1 must be at least this far from the entry
input bool   InpRequireRejection = true; // The retest must show a rejection (wick or engulf)
input double InpRejectWickRatio  = 0.30; // Rejection wick / bar range
input bool   InpUseTwoBarConfirm = true; // Also accept the engine's pin+engulf (SigTwoBarReversal)
input bool   InpRespectNoTradeZone = true; // Never trade between the previous day's high and low

//+------------------------------------------------------------------+
//| Strategy class                                                   |
//+------------------------------------------------------------------+
class CCfBreakRetest : public CEAStrategy
{
public:
   void OnInitStrategy()
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("5-stage policy: stage %d active (risk %.3f%%, %d trades/day max)",
             InpStage, g_eaCfg.riskPct, g_eaCfg.maxTradesPerDay), true);
   }

   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_BREAK_RETEST";
      cfg.sourceDoc             = "chartfanatics/pdf/break-retest.pdf (card #07)";
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
      cfg.maxTradesPerDay       = 3;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 180;
      cfg.useHwmThrottle        = true;
      cfg.hwmTier1Dd            = 2.0;  cfg.hwmTier1Mult = 0.50;
      cfg.hwmTier2Dd            = 4.0;  cfg.hwmTier2Mult = 0.25;
      cfg.hwmHaltDd             = 6.0;
      cfg.sessionStartHour      = InpEntryFromMin / 60;
      cfg.sessionStartMin       = InpEntryFromMin % 60;
      cfg.sessionEndHour        = InpEntryToMin / 60;
      cfg.sessionEndMin         = InpEntryToMin % 60;
      cfg.noTradeAfterHour      = 19;  cfg.noTradeAfterMin = 0;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 19;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = false;   // the retest is confirmed, then taken at market
      cfg.pendingExpiryMinutes  = 15;
      cfg.breakEvenAtR          = 1.0;
      cfg.partial1AtR           = 1.0;  cfg.partial1Pct = 50.0;    // "take 25-50% off at TP1"
      cfg.partial2AtR           = 2.0;  cfg.partial2Pct = 25.0;
      cfg.trailAtR              = 1.5;  cfg.trailDistanceR = 0.75; // hold runners
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;             // engine cost gate: (spread + commission) <= xR
      cfg.ledgerEnabled         = InpLedger;               // engine ledger: one row per open / partial / close
      cfg.ledgerFile            = "cf_break_retest_ledger.csv";
      cfg.newsFilter            = false;
      cfg.logLevel              = InpLogLevel;

      //--- chartfanatics card #01 (5-Stage framework): tighten the playbook's own risk posture for
      //--- the stage the account is being held to.  Never raises a cap; stage 5 leaves it untouched.
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession) return false;
      if(ctx.atr <= 0.0) return false;

      //--- the No Trade Zone: between the previous day's high and low
      if(InpRespectNoTradeZone)
      {
         double pdh = 0.0, pdl = 0.0;
         int bars = 0;
         if(SigRangeForDay(ctx.symbol, g_eaIndTf, 0, 1440, 1, pdh, pdl, bars))
         {
            if(ctx.mid < pdh && ctx.mid > pdl) return false;
         }
      }

      SBreakRetestParams p;
      p.Reset();
      p.rangeFromMin    = InpRangeFromMin;
      p.rangeToMin      = InpRangeToMin;
      p.entryFromMin    = InpEntryFromMin;
      p.entryToMin      = InpEntryToMin;
      p.minRangeAtr     = InpMinRangeAtr;
      p.breakBufferAtr  = InpBreakBufferAtr;
      p.retestTolAtr    = InpRetestTolAtr;
      p.stopBufferAtr   = InpStopBufferAtr;
      p.targetR         = InpTargetR;
      p.tradeBothWays   = true;
      p.scoreBase       = 62.0;
      if(!SigBreakRetest(ctx, p, plan)) return false;

      //--- confirmation the playbook names: rejection candle / engulfing / wick at the level
      if(InpRequireRejection && !ConfirmedAtLevel(ctx, plan.dir, plan.barsAgo))
      {
         plan.Reset();
         return false;
      }

      //--- "First Target (TP1) is the prior high (for longs) or prior low (for shorts)": the
      //--- nearest swing extreme of the signal timeframe that sits ahead of the entry.  The
      //--- R target stays the fallback when no swing qualifies.  (The partial itself is the
      //--- engine's R-based partial, configured below at 1R / 50%.)
      double cand = 0.0;
      if(NearestSwingAhead(ctx, plan.dir, plan.entry, cand) &&
         MathAbs(cand - plan.entry) / plan.riskDist >= InpMinTargetR)
      {
         plan.target  = cand;
         plan.reason += " | TP1 = prior swing";
      }
      plan.score  = plan.score + 5.0;
      plan.reason = "Break & Retest (battle zone): " + plan.reason;
      return true;
   }

private:
   //--- The playbook accepts a rejection candle, an engulfing close or a wick at the level.
   //--- The wick test covers the first and third cases; `SigTwoBarReversal` is the engine's own
   //--- pin+engulf rule (EASignals section 13) and covers the engulfing case - both are existing
   //--- engine utilities rather than a second hand-rolled candle matcher.
   //--- the nearest swing extreme ahead of the entry ("the prior high / prior low").
   //--- SigFractals() is locked to the signal timeframe: swings of the timeframe being traded.
   bool NearestSwingAhead(SEAContext &ctx, const int dir, const double entry, double &target)
   {
      double hi[], lo[];
      int hiIdx[], loIdx[];
      int n = SigFractals(ctx.symbol, 20, hi, lo, hiIdx, loIdx);
      if(n <= 0) return false;
      double best = 0.0;
      double bestDist = DBL_MAX;
      for(int i = 0; i < n; i++)
      {
         double c = (dir > 0) ? hi[i] : lo[i];
         if(c <= 0.0) continue;
         double dist = (dir > 0) ? (c - entry) : (entry - c);
         if(dist <= 0.0) continue;                 // behind the entry: already traded through
         if(dist < bestDist) { bestDist = dist; best = c; }
      }
      if(best <= 0.0) return false;
      target = best;
      return true;
   }

   bool ConfirmedAtLevel(SEAContext &ctx, const int dir, const int barsAgo)
   {
      if(barsAgo < 1) return false;
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, barsAgo + 2, r);
      if(got < barsAgo + 1) return false;
      if(EA_WickRatio(r[barsAgo], dir) >= InpRejectWickRatio) return true;
      //--- the engine detector reads the LAST closed bar, so it can only vouch for a retest that
      //--- closed on that same bar; an older retest is confirmed by its own wick test alone
      if(!InpUseTwoBarConfirm || barsAgo != 1) return false;
      SSignalPlan reversal;
      if(!SigTwoBarReversal(ctx, InpRejectWickRatio, InpStopBufferAtr, InpTargetR, true, reversal))
         return false;
      return (reversal.dir == dir);
   }
};

CCfBreakRetest g_cfBreakRetest;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfBreakRetest);
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
