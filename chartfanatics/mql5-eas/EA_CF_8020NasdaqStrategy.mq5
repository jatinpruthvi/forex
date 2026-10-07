//+------------------------------------------------------------------+
//|                                   EA_CF_8020NasdaqStrategy.mq5   |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| ChartFanatics: "COPY This Prop Firm Simple Trading Strategy with  |
//|                 65% Win Rate" (Okala's 80/20 Strategy)           |
//| Card    : chartfanatics/todos/80-20-nasdaq-strategy.md  (#02)     |
//| Source  : chartfanatics/glimpse/jsUTbjwpFVk.md (video, no PDF)    |
//| Magic   : 3208                                                   |
//|                                                                  |
//| A NASDAQ mean-reversion model built on price levels, not          |
//| indicators (the trader traded it from a phone):                  |
//|                                                                  |
//|   1. THE LEVELS: every price ending in 80 or 20 (25,680 -> the   |
//|      80 level; 25,620 -> the 20 level).  They repeat every 100   |
//|      index points, so the nearest one is never more than 30 away.|
//|   2. THREE STRUCTURES, all entered at a level:                   |
//|        * fork    - downmove -> long-wick initiation candle ->    |
//|                    next candle tests the low without breaking -> |
//|                    higher high (mean-reversion LONG);            |
//|        * H       - bounce off the 20 level, strong move into the |
//|                    80 level, long upper wick, roll over          |
//|                    (continuation SHORT);                          |
//|        * cross-section - two breakdown candles intersect and     |
//|                    price retests the intersection.               |
//|   3. REPAIR CANDLES as magnet targets: a candle with no wick on   |
//|      one side leaves limit orders unfilled on that side, and      |
//|      price tends to return there.                                 |
//|   4. MONEY MANAGEMENT: fixed 10-point stop on every trade, first  |
//|      target 15 points, take half off there (covers risk), move    |
//|      the rest to break-even and let it run to the magnet.         |
//|   5. WHEN: the New York open (09:30 ET) while volatility is       |
//|      highest; the 11:00-13:00 ET lunch hour is skipped.           |
//|      No fixed trade limit - the trader sizes activity to         |
//|      conditions, so the EA sets no daily cap (the daily loss      |
//|      cut-off is the guardrail instead).                           |
//|                                                                  |
//| `[interpretation]` marks where the summary is silent or reads    |
//| oddly (see the notes inline and mql5-eas/README.md).              |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics 80/20 Nasdaq - mean reversion at the 80/20 levels with a fixed 10-point stop"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade   = "US100";               // Universe (the playbook trades NASDAQ)
input ulong             InpMagicNumber      = 3208;                  // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct          = 0.50;                  // Risk per trade (% of equity)
input int               InpStage             = 5;                    // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input double            InpMaxSpreadPoints  = 3.0;                   // Spread gate in points (0 = off)
input double            InpDailyLossPct     = 1.50;                  // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset  = 2;                     // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;         // Log verbosity
input double            InpCommissionPerLotRT = 0.0;                 // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.20;                // Cost gate: (spread + commission) <= xR (10-pt stop -> 2-pt spread = 0.2R)
input bool              InpLedger             = true;                // Write the engine evidence ledger CSV
//--- the 80/20 levels
input int    InpLevelHi          = 80;      // "the 80 level" (price endings the trader watches)
input int    InpLevelLo          = 20;      // "the 20 level"
input double InpLevelTolPoints   = 5.0;     // A "level tap": price within this many index points of the level
//--- money management (fixed points on NASDAQ, exactly as the source states)
input double InpStopPoints       = 10.0;    // "a fixed 10-point stop-loss" (index points)
input double InpTp1Points        = 15.0;    // "first 15-point profit target" -> take half off, cover risk
input bool   InpUseRepairMagnet  = true;    // Use repair candles as magnet targets (they can pay more than TP1)
input int    InpMagnetLookback   = 60;      // Bars searched for a repair-candle magnet
input double InpMagnetMaxPoints  = 45.0;    // Farther magnets than this are not treated as TP1 alternates
//--- the two timeframes ("10-minute chart ... 200-second chart")
input ENUM_TIMEFRAMES InpStructureTf = PERIOD_M10; // 10-minute market structure (the source's exact timeframe)
input int             InpStructureBars = 6;        // Bars the structure move is measured over
input int             InpLookbackBars  = 20;       // Search window for the three structures
//--- windows (London clock; New York = London - 5 in winter)
input int    InpOpenFromMin      = 870;     // 14:30 London = 09:30 ET - the New York open
input int    InpOpenToMin        = 960;     // 16:00 London = 11:00 ET - before the lunch hour
input bool   InpUseAfternoon     = true;    // Also trade 13:00-15:00 ET after the lunch hour
input int    InpAfternoonFromMin = 1080;    // 18:00 London = 13:00 ET
input int    InpAfternoonToMin   = 1200;    // 20:00 London = 15:00 ET
//--- structure ratios
input double InpWickRatio        = 0.50;    // Long-wick rejection: wick / bar range
input double InpMaxBodyRatio     = 0.35;    // "small body" for the fork's initiation candle
input double InpTestTolPoints    = 3.0;     // "tests the low but doesn't break it" tolerance
input double InpBreakTolPoints   = 2.0;     // How far a test may undercut the low before it counts as broken
input double InpRepairNoWickTol  = 0.10;    // "no wick on the opposite side": wick / range ceiling
//--- per-structure switches (for the tester's ablation sweep)
input bool   InpUseCrossSection  = true;    // Trade cross-section retests
input bool   InpUseFork          = true;    // Trade fork setups (mean-reversion longs)
input bool   InpUseHPattern      = true;    // Trade H-pattern setups (continuation shorts)
input bool   InpRequireLevelTap  = true;    // Every structure must be AT a level ("the best entry ... mixing everything")

//+------------------------------------------------------------------+
//| Strategy class                                                   |
//+------------------------------------------------------------------+
class CCf8020Nasdaq : public CEAStrategy
{
public:
   void OnInitStrategy()
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("5-stage policy: stage %d active (risk %.3f%%, %d trades/day max)",
             InpStage, g_eaCfg.riskPct, g_eaCfg.maxTradesPerDay), true);
      EA_Log(EA_LOG_EVENTS, StringFormat("80/20 levels armed: %d and %d endings, tap tolerance %.1f points; "
             "fixed stop %.1f, first target %.1f points", InpLevelHi, InpLevelLo, InpLevelTolPoints,
             InpStopPoints, InpTp1Points), true);
   }

   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_8020_NASDAQ";
      cfg.sourceDoc             = "chartfanatics/glimpse/jsUTbjwpFVk.md (card #02)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M3;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = 3.0;
      cfg.totalDdPct            = 8.0;
      cfg.maxTradesPerDay       = 0;      // the source explicitly has NO fixed trade limit (condition-based)
      cfg.dayLockAfterLosses    = 0;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 120;
      cfg.useHwmThrottle        = true;
      cfg.hwmTier1Dd            = 2.0;  cfg.hwmTier1Mult = 0.50;
      cfg.hwmTier2Dd            = 4.0;  cfg.hwmTier2Mult = 0.25;
      cfg.hwmHaltDd             = 6.0;
      cfg.sessionStartHour      = 14;  cfg.sessionStartMin = 25;   // five minutes before the NY open
      cfg.sessionEndHour        = 20;  cfg.sessionEndMin   = 5;    // the afternoon window's end
      cfg.noTradeAfterHour      = 20;  cfg.noTradeAfterMin = 0;    // 15:00 ET - the source's day is done
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 19;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = false;   // structures trigger at the close of the signal bar
      cfg.breakEvenAtR          = 1.5;     // 15 points on a 10-point stop: "move remaining to break-even"
      cfg.partial1AtR           = 1.5;     // "at the first 15-point profit target, take 1-2 contracts off"
      cfg.partial1Pct           = 50.0;
      cfg.trailAtR              = 2.5;     // "trust the process: trail the rest"
      cfg.trailDistanceR        = 1.0;
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;              // engine cost gate: (spread + commission) <= xR
      cfg.ledgerEnabled         = InpLedger;                // engine ledger: one row per open / partial / close
      cfg.ledgerFile            = "cf_8020_nasdaq_ledger.csv";
      cfg.newsFilter            = false;   // the source trades volatility, not calendar events
      cfg.logLevel              = InpLogLevel;

      //--- chartfanatics card #01 (5-Stage framework): tighten the playbook's own risk posture for
      //--- the stage the account is being held to.  Never raises a cap; stage 5 leaves it untouched.
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession) return false;
      if(!InSourceWindow(ctx)) return false;

      //--- the three structures the source lists, in confluence order: the cross-section (level +
      //--- structure stacked) first, then the two named patterns.  One position at a time.
      int    dir = 0;
      string why = "";
      double entryRef = 0.0;
      bool   found = false;

      if(InpUseCrossSection && CrossSection(ctx, dir, why, entryRef)) found = true;   // dir set by the retest side
      else if(InpUseFork && ForkLong(ctx, why, entryRef))            { dir = +1; found = true; }
      else if(InpUseHPattern && HPatternShort(ctx, why, entryRef))   { dir = -1; found = true; }
      if(!found) return false;

      double entry = (dir > 0) ? ctx.ask : ctx.bid;
      if(entry <= 0.0) return false;

      //--- fixed 10-point stop, exactly as the source states (risk is constant in points, so the
      //--- engine's sizing keeps the cash risk constant while the trader "steps on the gas")
      double stop = (dir > 0) ? entry - InpStopPoints : entry + InpStopPoints;
      double risk = MathAbs(entry - stop);
      if(risk <= 0.0) return false;

      //--- first target 15 points; a repair-candle magnet can replace it when it pays more
      double target = (dir > 0) ? entry + InpTp1Points : entry - InpTp1Points;
      double magnet = 0.0;
      if(InpUseRepairMagnet && RepairMagnet(ctx, dir, entry, magnet))
         target = magnet;

      plan.dir      = dir;
      plan.entry    = entry;
      plan.stop     = stop;
      plan.riskDist = risk;
      plan.target   = target;
      plan.isLimit  = false;
      plan.barsAgo  = 1;
      plan.score    = 66.0;                       // engine convention; the source gives no score
      plan.reason   = StringFormat("80/20 %s at %.1f (ref %.1f)", why, LevelOf(entry), entryRef);
      return true;
   }

private:
   //--- the source's own trading day: the NY open, and (optionally) the afternoon; never lunch
   bool InSourceWindow(const SEAContext &ctx)
   {
      if(EA_InWindow(ctx.nowClock, InpOpenFromMin / 60, InpOpenFromMin % 60,
                                     InpOpenToMin / 60,   InpOpenToMin % 60)) return true;
      if(InpUseAfternoon)
         return EA_InWindow(ctx.nowClock, InpAfternoonFromMin / 60, InpAfternoonFromMin % 60,
                                        InpAfternoonToMin / 60,   InpAfternoonToMin % 60);
      return false;
   }

   //--- the nearest price ending in 80 or 20.  Levels repeat every 100 index points, so the
   //--- nearest is at most 30 away; `ending` reports which one was found (80 or 20).
   double NearestLevel(const double price, int &ending)
   {
      double prefix = MathFloor(price / 100.0) * 100.0;
      double best = 0.0, bestDist = DBL_MAX;
      ending = 0;
      for(int k = -1; k <= 1; k++)
      {
         double base = prefix + (double)k * 100.0;
         double cand[2];
         cand[0] = base + (double)InpLevelLo;
         cand[1] = base + (double)InpLevelHi;
         for(int j = 0; j < 2; j++)
         {
            double d = MathAbs(price - cand[j]);
            if(d < bestDist)
            {
               bestDist = d;
               best     = cand[j];
               ending   = (j == 0) ? InpLevelLo : InpLevelHi;
            }
         }
      }
      return best;
   }

   bool AtLevel(const double price, int &ending)
   {
      int e = 0;
      double lvl = NearestLevel(price, e);
      ending = e;
      return (MathAbs(price - lvl) <= InpLevelTolPoints);
   }

   double LevelOf(const double price)
   {
      int e = 0;
      return NearestLevel(price, e);
   }

   //--- 10-minute market structure: net direction of the last `InpStructureBars` closed M10 bars.
   //--- The source reads structure on the 10-minute chart while entries come from the 200-second one.
   int StructureDir(const SEAContext &ctx)
   {
      MqlRates m[];
      int got = EA_Rates(ctx.symbol, InpStructureTf, 0, InpStructureBars + 2, m);
      if(got < InpStructureBars + 1) return 0;
      double now = m[1].close;
      double then = m[InpStructureBars].close;
      if(now > then) return +1;
      if(now < then) return -1;
      return 0;
   }

   //--- FORK (mean-reversion long): a strong downmove puts in a long-lower-wick, small-body
   //--- initiation candle; the next candle tests that low without breaking it; then a candle makes
   //--- a higher high.  Enter on the higher-high candle.
   //--- `[interpretation]` the summary's "targeting the previous low" reads oddly for a long, so
   //--- the fixed 10-point stop and 15-point first target the document states elsewhere are used;
   //--- the fork low is only the structural reference.
   bool ForkLong(SEAContext &ctx, string &why, double &ref)
   {
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, InpLookbackBars + 4, r);
      if(got < 8) return false;

      if(StructureDir(ctx) >= 0) return false;                 // the fork lives inside a downmove

      MqlRates initBar = r[3];                                 // the initiation candle
      MqlRates test = r[2];                                    // tests the low, holds it
      MqlRates trig = r[1];                                    // the higher-high candle

      if(EA_WickRatio(initBar, +1) < InpWickRatio) return false;   // long lower wick
      if(EA_BodyRatio(initBar) > InpMaxBodyRatio) return false;    // small body

      //--- "after a strong downmove": the initiation low is the extreme of the window
      for(int i = 4; i < got && i <= InpLookbackBars; i++)
         if(r[i].low < initBar.low) return false;

      //--- "the next candle tests the low but doesn't break it"
      if(test.low > initBar.low + InpTestTolPoints) return false;
      if(test.low < initBar.low - InpBreakTolPoints) return false;

      //--- "then makes a higher high"
      if(!(trig.high > test.high && trig.close > test.high)) return false;

      int ending = 0;
      if(InpRequireLevelTap && !AtLevel(initBar.low, ending)) return false;

      why = (ending > 0) ? StringFormat("fork at the %d level", ending) : "fork";
      ref = initBar.low;
      return true;
   }

   //--- H-PATTERN (continuation short): price bounces off the 20 level, makes a strong move into
   //--- the 80 level with a long upper wick, then rolls over.  Enter on the rollover.
   bool HPatternShort(SEAContext &ctx, string &why, double &ref)
   {
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, InpLookbackBars + 4, r);
      if(got < 8) return false;

      if(StructureDir(ctx) <= 0) return false;                 // the H lives inside an upmove

      //--- the bounce: some bar in the window tapped a 20-ending level from above
      bool bounced = false;
      double bouncePrice = 0.0;
      for(int i = 2; i < got && i <= InpLookbackBars; i++)
      {
         int tapEnding = 0;
         if(!AtLevel(r[i].low, tapEnding)) continue;
         if(r[i].close > r[i].low) { bounced = true; bouncePrice = r[i].low; break; }
      }
      if(!bounced) return false;

      //--- the rejection: the last closed bar tapped an 80-ending level and left a long upper wick
      int ending = 0;
      if(!AtLevel(r[1].high, ending) || ending != InpLevelHi) return false;
      if(EA_WickRatio(r[1], -1) < InpWickRatio) return false;

      //--- the rollover: it closed bearish, below the bounce's advance
      if(!(r[1].close < r[1].open)) return false;
      if(r[1].high <= bouncePrice) return false;

      why = StringFormat("H-pattern short from the %d level", InpLevelHi);
      ref = r[1].high;
      return true;
   }

   //--- CROSS-SECTION: two consecutive breakdown candles intersect; price retests the exact
   //--- intersection and the retest side decides the direction (from above -> long).
   //--- `[interpretation]` the source calls cross-sections direction-neutral ("depending on market
   //--- structure"); the retest side plus the 80/20 confluence is the mechanical reading used here.
   bool CrossSection(SEAContext &ctx, int &dir, string &why, double &ref)
   {
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, InpLookbackBars + 4, r);
      if(got < 8) return false;

      //--- find the most recent pair of breakdown candles (bearish bars that broke a prior low)
      double zlo = 0.0, zhi = 0.0;
      bool found = false;
      for(int i = 1; i <= InpLookbackBars && i + 2 < got; i++)
      {
         if(!(r[i].close < r[i].open && r[i].close < r[i + 1].low)) continue;
         if(!(r[i + 1].close < r[i + 1].open && r[i + 1].close < r[i + 2].low)) continue;
         double lo = MathMax(r[i].low, r[i + 1].low);
         double hi = MathMin(r[i].high, r[i + 1].high);
         if(lo > hi) continue;                                  // the candles do not intersect
         zlo = lo; zhi = hi; found = true; break;                // the newest intersection wins
      }
      if(!found) return false;

      //--- confluence: the intersection must sit at an 80/20 level
      int ending = 0;
      double mid = (zlo + zhi) * 0.5;
      if(InpRequireLevelTap)
      {
         bool atLevel = AtLevel(mid, ending) || AtLevel(zlo, ending) || AtLevel(zhi, ending);
         if(!atLevel) return false;
      }

      //--- the retest: the last closed bar came back into the zone and rejected it
      double tol = InpLevelTolPoints;
      bool touchedFromAbove = (r[1].low <= zhi + tol && r[1].low >= zlo - tol && r[1].close > zlo);
      bool touchedFromBelow = (r[1].high >= zlo - tol && r[1].high <= zhi + tol && r[1].close < zhi);
      if(touchedFromAbove && r[1].close > r[1].open && ctx.mid >= zlo)
      {
         dir = +1;
         why = "cross-section long (retest from above)";
         ref = mid;
         return true;
      }
      if(touchedFromBelow && r[1].close < r[1].open && ctx.mid <= zhi)
      {
         dir = -1;
         why = "cross-section short (retest from below)";
         ref = mid;
         return true;
      }
      return false;
   }

   //--- a repair candle: it opens and moves one way with NO wick on the opposite side, so the
   //--- orders that would have filled there are still open - price tends to return (the "magnet").
   //--- For a long, the magnet is above a no-top-wick candle; for a short, below a no-bottom-wick one.
   bool RepairMagnet(SEAContext &ctx, const int dir, const double entry, double &target)
   {
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, InpMagnetLookback + 4, r);
      if(got < 6) return false;

      double best = 0.0, bestDist = DBL_MAX;
      double minPay = InpTp1Points;                        // only replaces TP1 when it pays more
      for(int i = 1; i < got && i <= InpMagnetLookback; i++)
      {
         double range = r[i].high - r[i].low;
         if(range <= 0.0) continue;
         double bodyLow  = MathMin(r[i].open, r[i].close);
         double bodyHigh = MathMax(r[i].open, r[i].close);
         double topWick    = (r[i].high - bodyHigh) / range;
         double bottomWick = (bodyLow - r[i].low) / range;

         if(dir > 0)
         {
            //--- bearish candle with no top wick: unfilled sellers above -> magnet above
            if(!(r[i].close < r[i].open) || topWick > InpRepairNoWickTol) continue;
            double cand = r[i].high;
            double dist = cand - entry;
            if(dist < minPay || dist > InpMagnetMaxPoints) continue;
            if(dist < bestDist) { bestDist = dist; best = cand; }
         }
         else
         {
            //--- bullish candle with no bottom wick: unfilled buyers below -> magnet below
            if(!(r[i].close > r[i].open) || bottomWick > InpRepairNoWickTol) continue;
            double cand = r[i].low;
            double dist = entry - cand;
            if(dist < minPay || dist > InpMagnetMaxPoints) continue;
            if(dist < bestDist) { bestDist = dist; best = cand; }
         }
      }
      if(best <= 0.0) return false;
      target = best;
      return true;
   }
};

CCf8020Nasdaq g_cf8020Nasdaq;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cf8020Nasdaq);
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
