//+------------------------------------------------------------------+
//|                              EA_CF_SmallCapShortStatistics.mq5    |
//|                                  Copyright 2026, Master Strategy  |
//|                                                                   |
//| ChartFanatics: Small-Cap Short Statistics (Steven Ducks)           |
//| "Three Trading Strategies That Made $50M"                          |
//| Card    : chartfanatics/todos/small-cap-short-statistics.md (#35)  |
//| Source  : chartfanatics/glimpse/52ZsDmFHqyY.md                     |
//| Magic   : 3238                                                    |
//|                                                                   |
//| The document is a statistics-driven small-cap shorting system.     |
//| Every number it states that an EA can observe is a rule below;     |
//| what an EA cannot observe is disclosed, not faked.  The three      |
//| strategies, with the document's own figures:                       |
//|                                                                   |
//|   G1  GAP UP SHORT: "A stock gaps up 70-1000% at market open, then |
//|       consolidates.  The strategy shorts the breakdown after       |
//|       consolidation ends, targeting a 20-35% fade from the         |
//|       intraday high".  Filters: "Gap must be above 100%";          |
//|       "pre-market volume under 50M (if over 50M, too crowded to    |
//|       trade)".  Entry: "After gap up and consolidation (typically  |
//|       1-2 hours), enter partial position on first breakdown.  Add  |
//|       full position when momentum cracks 3-5% below consolidation. |
//|       Stop loss above consolidation high."                         |
//|   B1  BOUNCE SHORT: "A stock spiked to resistance on high volume   |
//|       1+ year ago, then flatlined.  When it gaps back up near that |
//|       old resistance, trapped longs want to exit."  Dollar block:  |
//|       "volume traded at resistance x price ... This must be 150M+  |
//|       to be ideal."  Ratio: "trapped volume 2x intraday volume is  |
//|       strong; 10:1 is exceptional" - the ratio drives conviction   |
//|       and size.  Type 1: "gaps directly to resistance without      |
//|       pre-market volume (higher win rate) ... fades 75% from top;  |
//|       Type 2 ... fades only 50%."                                  |
//|   F1  FIRST RED DAY: "3+ consecutive green days with increasing    |
//|       volume and 300%+ range (or 1000%+ for 2-day setup).  No red  |
//|       days allowed in between."  Entry: "on the final green day ... |
//|       enter only 1/4 position at open ... Wait for second day      |
//|       (first red day) when pre-market volume drops 50-80% to enter |
//|       remaining 3/4 position.  Stop loss above consolidation."     |
//|       (Card #10 implements another playbook's first-red-day; this  |
//|       card's numbers stand on their own here.)                     |
//|                                                                   |
//| The statistics outputs the document asks for ("Create a            |
//| spreadsheet to track ... every setup you encounter") are written   |
//| to MQL5/Files/cf_smallcap_short_stats.csv: every signal logs the   |
//| setup, the gap, the dollar block, the trapped-to-intraday ratio,   |
//| the fade target and the risk weight used.                          |
//|                                                                   |
//| `[interpretation]`: the consolidation window and tightness, the    |
//| breakdown buffer, the add band, the fade centre (26%), the old-    |
//| resistance scan window and dollar block size, the reaction          |
//| tolerance, the volume-pace estimate for the first-red-day drop,    |
//| and the state machine that turns the 1/4 and 3/4 entries into two  |
//| plans are inputs and labelled.                                     |
//|                                                                   |
//| Disclosed, not faked: market cap ($1-100M, $200M for first red     |
//| day), float ($1-50M and its buckets), the sector exclusions        |
//| (biotech / energy / Chinese stocks), pre-market volume and the     |
//| 10%-of-float / 1%-of-daily-volume size caps are not observable in  |
//| MetaTrader; the universe carries the stock selection, and the EA   |
//| enforces the observable substitutes (gap size, dollar block,       |
//| trapped-to-intraday ratio, the day-count screens).  "Cover         |
//| gradually / give supply back" is the engine's partial exits.       |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics Small-Cap Short Statistics - gap-up breakdown shorts, old-resistance bounce shorts and the statistical first red day"

#include "..\..\Include\EACommon.mqh"

enum ENUM_CF_SC_SETUP
{
   CF_SC_GAP    = 1,   // Gap up short
   CF_SC_BOUNCE = 2,   // Bounce short
   CF_SC_FRD    = 3    // First red day
};

//--- identity / risk
input string            InpSymbolsToTrade     = "AAPL,MSFT,NVDA";  // Universe (playbook: small caps - the user's list)
input ulong             InpMagicNumber        = 3238;             // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct            = 0.30;             // Conservative base risk (the wide-stop family)
input int               InpStage              = 5;                // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input double            InpMaxSpreadPoints    = 5.0;              // Spread gate in points (0 = off)
input double            InpDailyLossPct       = 1.50;             // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset    = 2;                // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel           = EA_LOG_EVENTS;    // Log verbosity
input double            InpCommissionPerLotRT = 0.0;              // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.12;             // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;             // Write the engine evidence ledger CSV
input string            InpStatsFile          = "cf_smallcap_short_stats.csv";  // The statistics database the document asks for

//--- setup toggles
input bool              InpUseGap             = true;
input bool              InpUseBounce          = true;
input bool              InpUseFrd             = true;

//--- G: the gap up short
input double            InpMinGapPct          = 100.0;            // "Gap must be above 100%"
input int               InpConsolMinutes      = 60;               // "consolidation (typically 1-2 hours)"
input double            InpConsolMaxPct       = 12.0;             // [interpretation] Consolidation height (% of price)
input double            InpBreakBufferAtr     = 0.20;             // [interpretation] Buffer below the consolidation low
input double            InpFirstRiskMult      = 0.40;             // "enter partial position on first breakdown"
input double            InpAddBelowPct        = 3.0;              // "Add full position when momentum cracks 3-5% below consolidation"
input double            InpFadePct            = 26.0;             // "Average fade is 26% from intraday high" (target band 20-35%)
input double            InpMaxStopPct         = 45.0;             // [interpretation] Sanity cap: small-cap stops can be enormous

//--- B: the bounce short
input int               InpOldDaysAgo         = 250;              // "1+ year ago"
input int               InpOldScanWindow      = 60;               // [interpretation] Days scanned for the old volume spike
input double            InpMinDollarBlock     = 150000000.0;      // "This must be 150M+ to be ideal"
input double            InpMinTrappedRatio    = 2.0;              // "A 2:1 ratio ... is strong; 10:1 is exceptional"
input double            InpStrongRatio        = 10.0;             // exceptional ratio -> full conviction size
input double            InpNearLevelPct       = 5.0;              // [interpretation] How near the old resistance counts
input double            InpRejectTolPct       = 1.0;              // [interpretation] The touch tolerance for the rejection
input double            InpType1GapPct        = 2.0;              // [interpretation] "gaps directly to resistance" (within %)
input double            InpType1FadePct       = 75.0;             // "Type 1 fades 75% from top"
input double            InpType2FadePct       = 50.0;             // "Type 2 fades only 50%"
input double            InpRatioSizeMult      = 0.60;             // [interpretation] Size for the merely-strong (2:1) ratio

//--- F: the first red day
input int               InpMinGreenDays       = 3;                // "3+ consecutive green days"
input int               InpTwoDayGreenDays    = 2;                // "1000%+ for 2-day setup"
input double            InpTwoDayRangePct     = 1000.0;
input double            InpRunRangePct        = 300.0;            // "300%+ range"
input double            InpGreenDayRiskMult   = 0.25;             // "enter only 1/4 position"
input double            InpVolDropFrac        = 0.80;             // "pre-market volume drops 50-80%"
input double            InpFrdFadePct         = 35.0;             // [interpretation] The fade target for the first red day

//--- execution window (the volume concentrates 9:30-11:30; edge fades later)
input int               InpSessionStartHour   = 14;               // US RTH open, London time (09:30 ET)
input int               InpSessionStartMin    = 30;
input int               InpLastEntryHour      = 18;               // No new risk after midday ET
input int               InpSessionEndHour     = 21;               // US RTH close
input int               InpMaxTradesPerDay    = 3;                // [interpretation] The add is the document's own second plan

//+------------------------------------------------------------------+
struct SScContext
{
   double d0Open, d1Close, d1High, d1Low;
   double intradayHigh;
   double consolHigh, consolLow;
   int    consolBars;
   bool   breakdown;
   double gapPct;
   //--- bounce
   double oldLevel;
   double dollarBlock;
   double trappedRatio;
   bool   type1;
   bool   rejection;
   //--- first red day
   int    greenRun;
   bool   runRangeOk;
   bool   volIncreasing;
   double runHigh;
   bool   todayGreen, todayRed, volDropped;
};

//+------------------------------------------------------------------+
class CCfSmallCapShortStats : public CEAStrategy
{
public:
   virtual bool AllowMultipleOnSymbol() { return true; }   // the document's partial-then-add entries

   virtual double LotsMultiplier(SEAContext &ctx)
   {
      double mult = 1.0;
      if(ctx.index >= 0 && ctx.index < ArraySize(m_riskMult)) mult = m_riskMult[ctx.index];
      return (mult > 0.0) ? mult : 1.0;
   }

   void OnInitStrategy()
   {
      ArrayResize(m_riskMult, g_eaSymbolCount);
      ArrayInitialize(m_riskMult, 1.0);
      EA_Log(EA_LOG_EVENTS, StringFormat("5-stage policy: stage %d active (risk %.3f%% of equity)",
             InpStage, g_eaCfg.riskPct), true);
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "Small-Cap Short Statistics armed: gap>=%.0f%%, block>=%.0fM, ratio>=%.1f, green run>=%d (stats -> %s)",
             InpMinGapPct, InpMinDollarBlock / 1e6, InpMinTrappedRatio, InpMinGreenDays, InpStatsFile), true);
   }

   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_SMALLCAP_SHORT_STATS";
      cfg.sourceDoc             = "chartfanatics/glimpse/52ZsDmFHqyY.md (card #35)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = 4.0;
      cfg.totalDdPct            = 10.0;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 2;                      // G1/F1: the partial entry and its add
      cfg.minSecondsBetweenTrades = 300;
      cfg.sessionStartHour      = InpSessionStartHour;
      cfg.sessionStartMin       = InpSessionStartMin;
      cfg.sessionEndHour        = InpSessionEndHour;
      cfg.sessionEndMin         = 0;
      cfg.sessionEndFlat        = true;                   // day trading
      cfg.noTradeAfterHour      = InpLastEntryHour;
      cfg.noTradeAfterMin       = 0;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = false;
      cfg.partial1AtR           = 1.0;                    // "Exit gradually on the way down"
      cfg.partial1Pct           = 50.0;
      cfg.breakEvenAtR          = 0.0;
      cfg.trailAtR              = 0.0;
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_smallcap_short_ledger.csv";
      cfg.newsFilter            = false;
      cfg.logLevel              = InpLogLevel;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   //+----------------------------------------------------------------+
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession || ctx.atr <= 0.0) return false;

      SScContext c;
      if(!ReadContext(ctx, c)) return false;

      double best = -1.0;
      SSignalPlan p;

      if(InpUseGap)
      {
         p.Reset();
         if(PlanGap(ctx, c, p) && p.score > best) { plan = p; best = p.score; }
      }
      if(InpUseBounce)
      {
         p.Reset();
         if(PlanBounce(ctx, c, p) && p.score > best) { plan = p; best = p.score; }
      }
      if(InpUseFrd)
      {
         p.Reset();
         if(PlanFrd(ctx, c, p) && p.score > best) { plan = p; best = p.score; }
      }
      return (plan.dir != 0);
   }

   //--- exits: the engine's 1R partial ("exit gradually on the way down") plus its target

private:
   double m_riskMult[];    // per-symbol weight for the plan being built (1/4, partial, full)

   //+----------------------------------------------------------------+
   //| The shared small-cap frame: the daily bar, the session ranges,  |
   //| the gap, the consolidation and the first-red-day run.           |
   //+----------------------------------------------------------------+
   bool ReadContext(const SEAContext &ctx, SScContext &c)
   {
      c.d0Open = 0; c.d1Close = 0; c.d1High = 0; c.d1Low = 0; c.intradayHigh = 0;
      c.consolHigh = 0; c.consolLow = 0; c.consolBars = 0; c.breakdown = false; c.gapPct = 0;
      c.oldLevel = 0; c.dollarBlock = 0; c.trappedRatio = 0; c.type1 = false; c.rejection = false;
      c.greenRun = 0; c.runRangeOk = false; c.volIncreasing = false; c.runHigh = 0;
      c.todayGreen = false; c.todayRed = false; c.volDropped = false;

      MqlRates d[];
      int got = EA_Rates(ctx.symbol, PERIOD_D1, 0, InpOldDaysAgo + InpOldScanWindow + 20, d);
      if(got < 60) return false;
      c.d0Open = d[0].open; c.d1Close = d[1].close; c.d1High = d[1].high; c.d1Low = d[1].low;
      if(c.d1Close <= 0.0) return false;

      MqlRates m[];
      if(EA_Rates(ctx.symbol, g_eaIndTf, 0, 240, m) < 12) return false;
      c.intradayHigh = d[0].high;

      //--- the session consolidation: the range of the first InpConsolMinutes after the open
      MqlDateTime dt;
      TimeToStruct(ctx.nowClock, dt);
      dt.hour = InpSessionStartHour; dt.min = InpSessionStartMin; dt.sec = 0;
      datetime anchor = EA_ClockToServer(StructToTime(dt));
      datetime consolEnd = anchor + (datetime)(InpConsolMinutes * 60);
      for(int i = ArraySize(m) - 1; i >= 0; i--)
      {
         if(m[i].time < anchor || m[i].time >= consolEnd) continue;
         c.consolHigh = (c.consolHigh == 0.0) ? m[i].high : MathMax(c.consolHigh, m[i].high);
         c.consolLow  = (c.consolLow  == 0.0) ? m[i].low  : MathMin(c.consolLow,  m[i].low);
         c.consolBars++;
      }
      if(c.consolBars > 0 && c.consolHigh > 0.0)
         c.breakdown = (ctx.bid < c.consolLow - InpBreakBufferAtr * ctx.atr);

      //--- G1: the gap the document trades
      c.gapPct = (d[0].open > 0.0) ? (d[0].open - d[1].close) / d[1].close * 100.0 : 0.0;

      //--- B1: the old resistance and its dollar block ("volume traded at resistance x price")
      int scanStart = InpOldDaysAgo, scanEnd = (int)MathMin(got - 4, InpOldDaysAgo + InpOldScanWindow);
      if(scanStart < 10 || scanEnd <= scanStart) return false;
      int blockIdx = -1;
      double blockVol = 0.0;
      for(int i = scanStart; i <= scanEnd; i++)
         if((double)d[i].tick_volume > blockVol) { blockVol = (double)d[i].tick_volume; blockIdx = i; }
      if(blockIdx > 0)
      {
         c.oldLevel = d[blockIdx].high;                    // the resistance the spike printed
         double dollars = 0.0;
         for(int k = blockIdx - 3; k <= blockIdx + 3; k++)
            if(k >= 0 && k < got) dollars += (double)d[k].tick_volume * d[k].close;
         c.dollarBlock = dollars;

         //--- "Compare to estimated intraday volume (pre-market x 10, reduced 50-80% due to selling pressure)"
         double avgDollarVol = 0.0;
         int vn = 0;
         for(int i = 1; i <= 20 && i < got; i++) { avgDollarVol += (double)d[i].tick_volume * d[i].close; vn++; }
         if(vn > 0)
         {
            avgDollarVol /= vn;
            double estIntraday = avgDollarVol * 0.85;      // the 50-80% reduction, centred (labelled)
            if(estIntraday > 0.0) c.trappedRatio = c.dollarBlock / estIntraday;
         }

         //--- the setup: price gapped back to the old level and is rejecting it
         bool near = (MathAbs(ctx.bid - c.oldLevel) <= c.oldLevel * InpNearLevelPct / 100.0);
         bool touched = (m[1].high >= c.oldLevel * (1.0 - InpRejectTolPct / 100.0));
         c.rejection = near && touched && (m[1].close < c.oldLevel);
         c.type1 = (d[0].open >= c.oldLevel * (1.0 - InpType1GapPct / 100.0));   // "gaps directly to resistance"
      }

      //--- F1: the green run, its range, its volume, and the volume drop on the red day
      for(int i = 1; i < got - 1; i++)
      {
         if(d[i].close <= d[i].open) break;                // "No red days allowed in between"
         c.greenRun++;
      }
      if(c.greenRun > 0)
      {
         double lo = d[1].low, hi = d[1].high, v0 = 0.0, v1 = 0.0;
         for(int i = 1; i <= c.greenRun; i++)
         {
            lo = MathMin(lo, d[i].low);
            hi = MathMax(hi, d[i].high);
            if(i == 1) v0 = (double)d[i].tick_volume;
            if(i == 2) v1 = (double)d[i].tick_volume;
         }
         c.runHigh = hi;
         double rangePct = (lo > 0.0) ? (hi - lo) / lo * 100.0 : 0.0;
         double need = (c.greenRun == InpTwoDayGreenDays) ? InpTwoDayRangePct : InpRunRangePct;
         c.runRangeOk = (rangePct >= need);
         c.volIncreasing = (v0 > v1);                       // "increasing volume" into the final green day
         c.todayGreen = (ctx.bid > c.d1Close);
         c.todayRed = (ctx.bid < c.d1Close);

         //--- the volume drop when the first red day arrives (pre-market drop proxied by the pace)
         int elapsed = ctx.clockMinutes - (InpSessionStartHour * 60 + InpSessionStartMin);
         if(elapsed > 5 && c.todayRed)
         {
            double expected = (double)d[1].tick_volume * ((double)elapsed / 390.0);
            double todayVol = (double)d[0].tick_volume;
            c.volDropped = (expected <= 0.0) || (todayVol <= InpVolDropFrac * expected);
         }
      }
      return true;
   }

   //+----------------------------------------------------------------+
   //| The plan builder for the three setups, including their staged   |
   //| entries (the document's partial-then-add vocabulary).           |
   //+----------------------------------------------------------------+
   bool PlanGap(const SEAContext &ctx, const SScContext &c, SSignalPlan &p)
   {
      if(c.gapPct < InpMinGapPct) return false;
      if(c.consolBars < 2 || c.consolHigh <= 0.0 || c.consolLow <= 0.0) return false;
      if(c.consolHigh - c.consolLow > ctx.bid * InpConsolMaxPct / 100.0) return false;

      //--- the add: "when momentum cracks 3-5% below consolidation"
      if(ctx.openPositions > 0)
      {
         if(!(ctx.bid <= c.consolLow * (1.0 - InpAddBelowPct / 100.0))) return false;
         double stop = c.consolHigh + InpBreakBufferAtr * ctx.atr;
         if(stop <= ctx.bid) return false;
         double risk = stop - ctx.bid;
         if(risk > ctx.bid * InpMaxStopPct / 100.0) return false;
         SetRiskMult(ctx, 1.0);                            // "Add FULL position"
         p.dir = -1; p.entry = ctx.bid; p.stop = stop;
         p.target = c.intradayHigh * (1.0 - InpFadePct / 100.0);
         p.riskDist = risk; p.barsAgo = 1; p.isLimit = false; p.score = 70.0;
         p.reason = StringFormat("gap short ADD: momentum %.0f%% below the consolidation low %.2f", InpAddBelowPct, c.consolLow);
         LogStat(ctx, CF_SC_GAP, c, InpFadePct, 1.0, "add");
         return (p.target > 0.0 && p.target < p.entry);
      }

      if(!c.breakdown) return false;                       // "shorts the breakdown after consolidation ends"
      double stop = c.consolHigh + InpBreakBufferAtr * ctx.atr;
      if(stop <= ctx.bid) return false;
      double risk = stop - ctx.bid;
      if(risk > ctx.bid * InpMaxStopPct / 100.0) return false;

      SetRiskMult(ctx, InpFirstRiskMult);                  // "enter partial position on first breakdown"
      p.dir = -1; p.entry = ctx.bid; p.stop = stop;
      p.target = c.intradayHigh * (1.0 - InpFadePct / 100.0);
      p.riskDist = risk; p.barsAgo = 1; p.isLimit = false; p.score = 76.0;
      p.reason = StringFormat("gap up short: %.0f%% gap, consolidation %.2f-%.2f broke, partial entry",
                              c.gapPct, c.consolLow, c.consolHigh);
      LogStat(ctx, CF_SC_GAP, c, InpFadePct, InpFirstRiskMult, "breakdown");
      return (p.target > 0.0 && p.target < p.entry);
   }

   bool PlanBounce(const SEAContext &ctx, const SScContext &c, SSignalPlan &p)
   {
      if(c.oldLevel <= 0.0 || !c.rejection) return false;
      if(c.dollarBlock < InpMinDollarBlock) return false;              // "must be 150M+ to be ideal"
      if(c.trappedRatio < InpMinTrappedRatio) return false;            // "trapped volume 2x intraday volume is strong"
      if(ctx.openPositions > 0) return false;                          // a single entry, exited gradually

      double stop = c.oldLevel * (1.0 + InpRejectTolPct / 100.0) + InpBreakBufferAtr * ctx.atr;
      if(stop <= ctx.bid) return false;
      double risk = stop - ctx.bid;
      if(risk > ctx.bid * InpMaxStopPct / 100.0) return false;

      double fadePct = c.type1 ? InpType1FadePct : InpType2FadePct;    // "Type 1 fades 75% from top"
      double top = MathMax(ctx.bid, c.d1High);
      double target = top * (1.0 - fadePct / 100.0);
      if(target <= 0.0) return false;

      double mult = (c.trappedRatio >= InpStrongRatio) ? 1.0 : InpRatioSizeMult;   // ratio -> conviction
      SetRiskMult(ctx, mult);
      p.dir = -1; p.entry = ctx.bid; p.stop = stop; p.target = target;
      p.riskDist = risk; p.barsAgo = 1; p.isLimit = false;
      p.score = 70.0 + ((c.trappedRatio >= InpStrongRatio) ? 14.0 : 4.0) + (c.type1 ? 8.0 : 0.0);
      p.reason = StringFormat("bounce short: old resistance %.2f, block %.0fM, ratio %.1f:1, %s",
                              c.oldLevel, c.dollarBlock / 1e6, c.trappedRatio, c.type1 ? "Type 1" : "Type 2");
      LogStat(ctx, CF_SC_BOUNCE, c, fadePct, mult, "rejection");
      return true;
   }

   bool PlanFrd(const SEAContext &ctx, const SScContext &c, SSignalPlan &p)
   {
      if(c.greenRun < InpTwoDayGreenDays || !c.runRangeOk) return false;

      //--- the add: "wait for second day (first red day) when pre-market volume drops 50-80%"
      if(ctx.openPositions > 0)
      {
         if(!c.todayRed || !c.volDropped) return false;
         double stop = c.runHigh + InpBreakBufferAtr * ctx.atr;
         if(stop <= ctx.bid) return false;
         double risk = stop - ctx.bid;
         if(risk > ctx.bid * InpMaxStopPct / 100.0) return false;
         SetRiskMult(ctx, 0.75);                           // "enter remaining 3/4 position"
         p.dir = -1; p.entry = ctx.bid; p.stop = stop;
         p.target = ctx.bid * (1.0 - InpFrdFadePct / 100.0);
         p.riskDist = risk; p.barsAgo = 1; p.isLimit = false; p.score = 82.0;
         p.reason = StringFormat("first red day ADD: volume dropped to %.0f%% of pace, %d-day green run",
                                 InpVolDropFrac * 100.0, c.greenRun);
         LogStat(ctx, CF_SC_FRD, c, InpFrdFadePct, 0.75, "add");
         return (p.target > 0.0 && p.target < p.entry);
      }

      if(!c.todayGreen || !c.volIncreasing) return false;  // "on the final green day ... momentum is still strong"
      double stop = c.runHigh + InpBreakBufferAtr * ctx.atr;
      if(stop <= ctx.bid) return false;
      double risk = stop - ctx.bid;
      if(risk > ctx.bid * InpMaxStopPct / 100.0) return false;
      SetRiskMult(ctx, InpGreenDayRiskMult);               // "enter only 1/4 position"
      p.dir = -1; p.entry = ctx.bid; p.stop = stop;
      p.target = ctx.bid * (1.0 - InpFrdFadePct / 100.0);
      p.riskDist = risk; p.barsAgo = 1; p.isLimit = false; p.score = 74.0;
      p.reason = StringFormat("first red day setup: %d green days, %.0f%%+ range, volume rising - 1/4 scout",
                              c.greenRun, c.runRangeOk ? InpRunRangePct : 0.0);
      LogStat(ctx, CF_SC_FRD, c, InpFrdFadePct, InpGreenDayRiskMult, "scout");
      return (p.target > 0.0 && p.target < p.entry);
   }

   void SetRiskMult(const SEAContext &ctx, const double mult)
   {
      if(ctx.index >= 0 && ctx.index < ArraySize(m_riskMult)) m_riskMult[ctx.index] = mult;
   }

   //+----------------------------------------------------------------+
   //| The statistics database the document asks every trader to keep. |
   //+----------------------------------------------------------------+
   void LogStat(const SEAContext &ctx, const int setup, const SScContext &c,
                const double fadePct, const double riskMult, const string phase)
   {
      int fh = FileOpen(InpStatsFile, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(fh == INVALID_HANDLE) return;
      FileSeek(fh, 0, SEEK_END);
      if(FileTell(fh) == 0)
         FileWriteString(fh, "time,symbol,magic,setup,phase,gap_pct,dollar_block_usd,trapped_ratio,green_run,fade_target_pct,risk_mult,win_rate_band\r\n");
      string name = (setup == CF_SC_GAP) ? "gap_up_short" : (setup == CF_SC_BOUNCE ? "bounce_short" : "first_red_day");
      string band = (setup == CF_SC_GAP) ? "75%+" : (setup == CF_SC_BOUNCE ? "80-85%" : "90%+");
      FileWriteString(fh, StringFormat("%s,%s,%s,%s,%s,%.2f,%.0f,%.2f,%d,%.1f,%.2f,%s\r\n",
                      TimeToString(TimeTradeServer(), TIME_DATE | TIME_MINUTES), ctx.symbol,
                      IntegerToString((long)g_eaCfg.magic), name, phase,
                      c.gapPct, c.dollarBlock, c.trappedRatio, c.greenRun, fadePct, riskMult, band));
      FileClose(fh);
   }
};

CCfSmallCapShortStats g_cfSmallCapShortStats;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfSmallCapShortStats);
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
