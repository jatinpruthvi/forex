//+------------------------------------------------------------------+
//|                                   EA_CF_LiquidityInversion.mq5   |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| ChartFanatics / Desi Trades: "If You Only Watch One ICT Trading    |
//| Video, Make It This (LIVE Trading)"                                |
//| Card    : chartfanatics/todos/liquidity-inversion-model.md  (#17)  |
//| Source  : chartfanatics/glimpse/UIGZtoGGPH4.md                     |
//| Magic   : 3220                                                     |
//|                                                                    |
//| THE MULTI-TIMEFRAME REVERSAL MODEL, LAYER BY LAYER                  |
//|                                                                    |
//|   (1) daily/weekly sweep - "market sweeps monthly/weekly highs or    |
//|       lows (liquidity grab)"; monthly/weekly liquidity is preferred |
//|       over session highs/lows;                                       |
//|   (2) a fair value gap forms on the 4-hour reaction;                 |
//|   (3) that 4-hour gap INVERTS (price breaks through it and rejects) |
//|       - the document's highest-probability confirmation;             |
//|   DAY MODEL   (4) a counter-trend 15-minute gap forms on the          |
//|                    retracement; (5) that 15m gap is inverted on the   |
//|                    5-minute - market execute, not a limit order;      |
//|   SWING MODEL the entry must come off the HOURLY or 4-HOUR timeframe, |
//|                    "never the 15-minute or lower".                    |
//|                                                                    |
//| Stops/targets/management are the document's numbers:                 |
//|   * stop above the current 15-minute high (below the low, for longs), |
//|     wide enough "to allow the trade to breathe";                      |
//|   * target = prior sellside liquidity (previous session/day low, the  |
//|     9:30 NY-open low), and the setup must offer 1.5:1-2:1;            |
//|   * trim 50% at the first target, stop to break-even, let runners go  |
//|     (the engine's partial + break-even + trail);                      |
//|   * swing trades ignore intraday whipsaws: no break-even, no trail,   |
//|     the stop sits beyond the H4 structure;                            |
//|   * size down in high volatility so the same dollar risk applies;     |
//|   * two CONSECUTIVE losses stop the day (a win resets the count), with |
//|     a third attempt allowed after a win - the document's own wording;  |
//|   * prefer the New York open (10:00 ET): the day model does not trade  |
//|     before it ("before 10 a.m. price action is too choppy").           |
//|                                                                    |
//| `[interpretation]`: the video teaches the stack by example, so the    |
//| reading is fixed here - "sweep" = a daily wick beyond the weekly (then|
//| monthly) extreme that closes back inside; "inversion" = a displacement |
//| close through the gap followed by a rejection that keeps the new side  |
//| (the document's own words: "breaks through ... and then rejects it");  |
//| the VIX gate is optional because the symbol is broker-dependent; the   |
//| options-leap workflow is not implementable in an MT5 EA and is         |
//| disclosed on the card, not silently dropped.                           |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics liquidity inversion model - daily/weekly sweep, 4H gap inversion, lower-timeframe entry"

#include "..\..\Include\EACommon.mqh"

enum ENUM_CF_LI_MODEL
{
   CF_LI_DAY   = 0,   // Day model: 15m gap inverted on the 5-minute
   CF_LI_SWING = 1    // Swing model: hourly/4-hour entries only
};

//--- identity / risk
input string            InpSymbolsToTrade   = "US100,US500";        // "Desi trades NQ almost exclusively" (broker naming applies)
input ulong             InpMagicNumber      = 3220;                 // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct          = 0.50;                 // Risk per trade (% of equity)
input int               InpStage             = 5;                   // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input int               InpServerGmtOffset  = 2;                    // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;        // Log verbosity
input double            InpCommissionPerLotRT = 0.0;                // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.12;               // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;               // Write the engine evidence ledger CSV
//--- model
input ENUM_CF_LI_MODEL InpModel = CF_LI_DAY;  // Which model this instance runs
//--- the stack
input int    InpSweepMaxDays   = 3;     // the sweep must be this recent (completed D1 bars)
input int    InpH4ScanBars     = 30;    // H4 bars scanned for the reaction gap
input int    InpM15ScanBars    = 20;    // M15 bars scanned for the retracement gap
input int    InpH1ScanBars     = 30;    // H1 bars scanned for the swing entry gap
input double InpInvertTolFrac  = 0.10;  // rejection tolerance at the far edge, as a fraction of the gap height
//--- stops / targets / management
input int    InpStop15mBars    = 16;    // "stop loss above the current 15-minute high" (~4 hours of M15 bars)
input int    InpStopH4Bars     = 6;     // swing stop: beyond the H4 structure
input double InpStopBufferAtr  = 0.15;  // buffer beyond the structural high/low
input double InpMinRr          = 1.5;   // "typically yields a 1.5:1 to 2:1 initial risk-reward"
input double InpTrimAtR        = 1.0;   // "trim 50% at the first take-profit target"
input int    InpTrimPct        = 50;    // ... trim half
input double InpRunnerTrailAtR = 2.0;   // "let runners capture additional liquidity"
//--- the document's discipline rules
input int    InpMaxAttemptsPerDay  = 3;  // "if he wins one and loses one, he allows himself a third attempt"
input int    InpConsecutiveLossLock = 2; // "two consecutive losses -> stop trading for the day"
input double InpHighVolAtrMult     = 1.25;  // high-volatility regime: D1 ATR above x times its average
input double InpHighVolSizeMult    = 0.5;   // "size down in high volatility so that the same dollar risk applies"
input string InpVixSymbol          = "";    // optional VIX symbol: "VIX elevation signals setup probability increase"
input double InpMinVix             = 18.0;

//+------------------------------------------------------------------+
class CCfLiquidityInversion : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_LIQUIDITY_INVERSION";
      cfg.sourceDoc             = "chartfanatics/glimpse/UIGZtoGGPH4.md (card #16)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = (InpModel == CF_LI_DAY) ? PERIOD_M5 : PERIOD_H1;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = 3.0;
      cfg.dailyLossPct          = 1.50;
      cfg.weeklyLossPct         = 3.0;
      cfg.totalDdPct            = 8.0;
      cfg.maxTradesPerDay       = InpMaxAttemptsPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 120;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = false;          // "market execute ... rather than using limit orders"
      cfg.newsFilter            = false;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_liquidity_inversion_ledger.csv";
      cfg.logLevel              = InpLogLevel;

      if(InpModel == CF_LI_DAY)
      {
         //--- "prefer the New York open (10:00 ET) for day trades ... avoids trading before this time"
         cfg.sessionStartHour = 15;  cfg.sessionStartMin = 0;
         cfg.sessionEndHour   = 21;  cfg.sessionEndMin   = 0;
         cfg.noTradeAfterHour = 20;  cfg.noTradeAfterMin = 30;
         cfg.breakEvenAtR     = 1.0;                 // stop to break-even after the trim
         cfg.partial1AtR      = InpTrimAtR;  cfg.partial1Pct = InpTrimPct;
         cfg.trailAtR         = InpRunnerTrailAtR;   // runners chase extended liquidity
      }
      else
      {
         //--- swing: "all sessions tradable when volatility is elevated"; the entry discipline is the timeframe,
         //--- and intraday whipsaws are ignored because no break-even/trail is applied
         cfg.sessionStartHour = -1;  cfg.sessionStartMin = 0;     // -1 = no session gate
         cfg.sessionEndHour   = -1;  cfg.sessionEndMin   = 0;
         cfg.noTradeAfterHour = -1;
         cfg.breakEvenAtR     = 0.0;
         cfg.partial1AtR      = InpTrimAtR;  cfg.partial1Pct = InpTrimPct;   // the trim still happens; the rest rides
         cfg.trailAtR         = 0.0;
      }
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   void OnInitStrategy()
   {
      m_lossLockDay = 0;
      m_standAsideDay = 0;
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "liquidity inversion armed (%s): sweep -> 4H gap inversion -> %s entry, stop beyond the %s, >= %.1fR target, trim %d%% at %.1fR",
             ModelName(), (InpModel == CF_LI_DAY) ? "15m gap inverted on the 5m" : "hourly/4-hour inversion",
             (InpModel == CF_LI_DAY) ? "15-minute high/low" : "H4 structure",
             InpMinRr, InpTrimPct, InpTrimAtR), true);
   }

   //--- "two consecutive losses -> stop trading for the day" (a win resets the count)
   bool AllowTrading(SEAContext &ctx)
   {
      if(InpConsecutiveLossLock > 0 && ConsecutiveLossesToday() >= InpConsecutiveLossLock)
      {
         if(!LossLockLoggedToday(ctx.nowClock))
         {
            LossLockLoggedToday(ctx.nowClock, true);
            EA_Log(EA_LOG_EVENTS, StringFormat(
                   "%d consecutive losses today - the document stops the day here (a win would reset the count)",
                   InpConsecutiveLossLock), true);
         }
         return false;
      }
      //--- "VIX elevation signals setup probability increase" (optional: the symbol is broker-dependent)
      if(StringLen(InpVixSymbol) > 0)
      {
         MqlRates v[];
         if(EA_Rates(InpVixSymbol, PERIOD_D1, 0, 3, v) >= 2 && v[1].close < InpMinVix)
         {
            LogOnce(ctx.nowClock, StringFormat("VIX %.2f below %.1f - the document calls flat-volatility periods lower probability",
                                               v[1].close, InpMinVix));
            return false;
         }
      }
      return true;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession || ctx.atr <= 0.0 || ctx.atrD1 <= 0.0) return false;

      //--- (1) the sweep: monthly/weekly liquidity first (the document's priority), daily second
      int    bias = 0;
      double sweptLevel = 0.0;
      if(!SweepBias(ctx, bias, sweptLevel)) return false;

      //--- (2)+(3) the reaction gap on the 4-hour and its inversion = the bias confirmation
      if(!H4Inversion(ctx, bias)) return false;

      //--- (4)+(5) the lower-timeframe entry, per model
      double zoneLo = 0.0, zoneHi = 0.0;
      ENUM_TIMEFRAMES entryTf = (InpModel == CF_LI_DAY) ? PERIOD_M5 : PERIOD_H1;
      ENUM_TIMEFRAMES zoneTf  = PERIOD_M15;                       // the day model's retracement gap
      int             scanBars = (InpModel == CF_LI_DAY) ? InpM15ScanBars : InpH1ScanBars;
      if(InpModel == CF_LI_SWING) zoneTf = PERIOD_H1;             // "never the 15-minute or lower"
      if(!FindFvg(ctx.symbol, zoneTf, -bias, scanBars, zoneLo, zoneHi, 0)) return false;
      if(!ZoneInvertedOn(ctx.symbol, entryTf, bias, zoneLo, zoneHi, InpInvertTolFrac * (zoneHi - zoneLo)))
         return false;

      //--- the stop: above the 15-minute high (day) or beyond the H4 structure (swing)
      double stopLevel = StopLevel(ctx, bias);
      if(stopLevel <= 0.0) return false;

      double entry = (bias > 0) ? ctx.ask : ctx.bid;
      double stop  = (bias > 0) ? stopLevel - InpStopBufferAtr * ctx.atr
                                : stopLevel + InpStopBufferAtr * ctx.atr;
      double risk  = (bias > 0) ? entry - stop : stop - entry;
      if(risk <= 0.0) return false;

      //--- the target: prior sellside/buyside liquidity (prior session low/high, the 9:30 NY open level)
      double target = LiquidityTarget(ctx, bias, entry, risk);
      if(target <= 0.0) return false;
      double rr = MathAbs(target - entry) / risk;
      if(rr < InpMinRr) return false;                             // "typically yields a 1.5:1 to 2:1"

      plan.dir = bias; plan.entry = entry; plan.stop = stop; plan.target = target;
      plan.riskDist = risk; plan.barsAgo = 1; plan.score = 74.0; plan.isLimit = false;
      plan.reason = StringFormat("%s model: sweep of %.2f + 4H inversion + %s entry (%.2fR to prior liquidity)",
                                 (InpModel == CF_LI_DAY) ? "day" : "swing", sweptLevel,
                                 (InpModel == CF_LI_DAY) ? "5m" : "H1", rr);
      return true;
   }

   //--- "size down in high volatility so that the same dollar risk applies"
   double LotsMultiplier(SEAContext &ctx)
   {
      if(ctx.atrD1 <= 0.0) return 1.0;
      MqlRates d[];
      int got = EA_Rates(ctx.symbol, PERIOD_D1, 0, 60, d);
      if(got < 20) return 1.0;
      double sum = 0.0;
      int    n   = 0;
      for(int i = 1; i <= 20 && i < got; i++) { sum += (d[i].high - d[i].low); n++; }
      if(n <= 0) return 1.0;
      double avgRange = sum / n;
      double todayRange = ctx.atrD1;                              // daily ATR is the volatility meter the engine carries
      if(avgRange > 0.0 && todayRange > InpHighVolAtrMult * avgRange)
         return InpHighVolSizeMult;                               // high-volatility session: half size, same $ risk
      return 1.0;
   }

private:
   datetime m_lossLockDay;
   datetime m_standAsideDay;

   string ModelName() { return (InpModel == CF_LI_DAY) ? "day" : "swing"; }

   //-------------------------------------------------------------------
   // (1) the sweep: a wick beyond monthly/weekly (then daily) liquidity,
   // closed back inside.  Monthly/weekly carries the higher probability.
   //-------------------------------------------------------------------
   bool SweepBias(SEAContext &ctx, int &bias, double &level)
   {
      bias = 0; level = 0.0;
      if(!SweepAt(ctx.symbol, 20, bias, level) || bias == 0)     // monthly proxy: 20 completed days
         if(!SweepAt(ctx.symbol, 5, bias, level) || bias == 0)   // weekly
            SweepAt(ctx.symbol, 1, bias, level);                // daily/session
      return (bias != 0);
   }

   //--- The engine's SigDonchian includes the newest completed bar, so a box built from it can never
   //--- be exceeded by that same bar: the sweep geometry needs the liquidity taken from the days
   //--- BEFORE the candidate, so the same channel maths is applied here with the candidate excluded.
   bool SweepAt(const string sym, const int days, int &bias, double &level)
   {
      bias = 0; level = 0.0;
      MqlRates d[];
      int need = InpSweepMaxDays + days + 4;
      int got  = EA_Rates(sym, PERIOD_D1, 0, need, d);
      if(got < InpSweepMaxDays + days + 2) return false;

      for(int i = 1; i <= InpSweepMaxDays; i++)                   // the sweep candidate (newest first)
      {
         double hi = -DBL_MAX, lo = DBL_MAX;
         for(int k = i + 1; k <= i + days && k < got; k++)         // the prior liquidity, the candidate excluded
         {
            hi = MathMax(hi, d[k].high);
            lo = MathMin(lo, d[k].low);
         }
         if(hi <= -DBL_MAX || lo >= DBL_MAX) continue;
         if(d[i].high > hi && d[i].close < hi) { bias = -1; level = hi; return true; }   // swept highs -> bearish
         if(d[i].low  < lo && d[i].close > lo) { bias = +1; level = lo; return true; }   // swept lows  -> bullish
      }
      return false;
   }

   //-------------------------------------------------------------------
   // (2)+(3) the 4-hour reaction gap and its inversion
   //-------------------------------------------------------------------
   bool H4Inversion(const SEAContext &ctx, const int bias)
   {
      double lo = 0.0, hi = 0.0;
      int    barAgo = 0;
      //--- the reaction leaves a COUNTER-trend gap first ...
      if(!FindFvg(ctx.symbol, PERIOD_H4, -bias, InpH4ScanBars, lo, hi, barAgo)) return false;
      //--- ... and that gap must have inverted on the 4-hour (break-through + rejection)
      return FvgInvertedBias(ctx.symbol, PERIOD_H4, bias, InpH4ScanBars, InpInvertTolFrac * (hi - lo));
   }

   //--- the most recent fair value gap on `tf` in `dir` polarity (series index k = the middle bar)
   bool FindFvg(const string sym, const ENUM_TIMEFRAMES tf, const int dir,
                const int scanBars, double &lo, double &hi, int &barAgo)
   {
      lo = 0.0; hi = 0.0; barAgo = 0;
      MqlRates r[];
      int got = EA_Rates(sym, tf, 0, scanBars + 4, r);
      if(got < 5) return false;
      for(int k = 2; k < got - 1; k++)
      {
         if(dir > 0)    // bullish gap: the newer bar's low sits above the older bar's high
         {
            if(r[k - 1].low > r[k + 1].high)
            {
               lo = r[k + 1].high; hi = r[k - 1].low; barAgo = k;
               return true;
            }
         }
         else           // bearish gap: the older bar's low sits above the newer bar's high
         {
            if(r[k + 1].low > r[k - 1].high)
            {
               lo = r[k - 1].high; hi = r[k + 1].low; barAgo = k;
               return true;
            }
         }
      }
      return false;
   }

   //--- "price breaks through a fair value gap and then rejects it" (the document's inversion).
   //--- bias +1: a BEARISH gap was broken upward and the rejection holds above it;
   //--- bias -1: a BULLISH gap was broken downward and the rejection holds below it.
   bool FvgInvertedBias(const string sym, const ENUM_TIMEFRAMES tf, const int bias,
                        const int scanBars, const double tol)
   {
      double lo = 0.0, hi = 0.0;
      int    k = 0;
      if(!FindFvg(sym, tf, -bias, scanBars, lo, hi, k)) return false;
      if(k < 2 || hi <= lo) return false;

      MqlRates r[];
      int got = EA_Rates(sym, tf, 0, scanBars + 4, r);
      if(got < 5 || k >= got - 1) return false;

      //--- the inversion is chronological: the gap sits at k, the break-through is NEWER (smaller
      //--- index), and the rejection that keeps the new side is the newest bar of the test.
      for(int j = k - 1; j >= 2; j--)                 // the break-through bar
      {
         if(bias > 0)
         {
            if(r[j].close <= hi) continue;
            for(int c = j - 1; c >= 1; c--)           // newer bars: the retest must hold above
               if(r[c].low <= hi + tol && r[c].close > hi) return true;
         }
         else
         {
            if(r[j].close >= lo) continue;
            for(int c = j - 1; c >= 1; c--)           // newer bars: the retest must hold below
               if(r[c].high >= lo - tol && r[c].close < lo) return true;
         }
      }
      return false;
   }

   //--- the entry trigger: the HIGHER-timeframe zone inverted on the entry timeframe
   //--- (the day model's "that 15-minute gap gets inverted on the 1- or 5-minute").
   //--- bias +1: a bearish zone broken upward, retested and held above;
   //--- bias -1: a bullish zone broken downward, retested and held below.
   bool ZoneInvertedOn(const string sym, const ENUM_TIMEFRAMES tf, const int bias,
                       const double zoneLo, const double zoneHi, const double tol)
   {
      if(zoneHi <= zoneLo) return false;
      MqlRates r[];
      int got = EA_Rates(sym, tf, 0, 120, r);
      if(got < 8) return false;

      for(int j = 2; j < got - 4; j++)                // the break-through bar
      {
         if(bias > 0 && r[j].close > zoneHi)
         {
            for(int c = j - 1; c >= 1; c--)           // newer bars: retest held above the zone
               if(r[c].low <= zoneHi + tol && r[c].close > zoneHi) return true;
         }
         if(bias < 0 && r[j].close < zoneLo)
         {
            for(int c = j - 1; c >= 1; c--)
               if(r[c].high >= zoneLo - tol && r[c].close < zoneLo) return true;
         }
      }
      return false;
   }

   //-------------------------------------------------------------------
   // The stop: the 15-minute high/low (day) or the H4 structure (swing)
   //-------------------------------------------------------------------
   double StopLevel(const SEAContext &ctx, const int bias)
   {
      ENUM_TIMEFRAMES tf = (InpModel == CF_LI_DAY) ? PERIOD_M15 : PERIOD_H4;
      int bars = (InpModel == CF_LI_DAY) ? InpStop15mBars : InpStopH4Bars;
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, tf, 0, bars + 2, r);
      if(got < 3) return 0.0;
      double extreme = (bias > 0) ? DBL_MAX : -DBL_MAX;
      for(int i = 1; i <= bars && i < got; i++)
      {
         if(bias > 0) extreme = MathMin(extreme, r[i].low);      // long: the stop goes below the 15m low
         else         extreme = MathMax(extreme, r[i].high);     // short: above the 15m high
      }
      if(bias > 0 && extreme == DBL_MAX) return 0.0;
      if(bias < 0 && extreme == -DBL_MAX) return 0.0;
      return extreme;
   }

   //-------------------------------------------------------------------
   // Targets: prior sellside/buyside liquidity, and for swings the unfilled
   // higher-timeframe gaps ("mark multiple partials: daily gaps, weekly gaps")
   //-------------------------------------------------------------------
   double LiquidityTarget(const SEAContext &ctx, const int bias, const double entry, const double risk)
   {
      double best = 0.0;
      double floorDist = InpMinRr * risk;                         // every candidate starts at the document's R floor
      //--- prior day's extreme
      MqlRates d[];
      if(EA_Rates(ctx.symbol, PERIOD_D1, 1, 3, d) >= 2)
      {
         double priorDay = (bias > 0) ? d[0].high : d[0].low;     // the last completed day
         if(IsBeyond(priorDay, entry, bias, floorDist)) best = priorDay;
      }
      //--- the 9:30 a.m. New York open level (the session's low for shorts / high for longs)
      double nyHi = 0.0, nyLo = 0.0;
      int    bars = 0;
      if(SigRangeForDay(ctx.symbol, g_eaIndTf, 870, 875, 0, nyHi, nyLo, bars) && bars > 0)
      {
         double nyLevel = (bias > 0) ? nyHi : nyLo;
         if(IsBeyond(nyLevel, entry, bias, floorDist) && (best == 0.0 || IsNearer(nyLevel, entry, best, bias)))
            best = nyLevel;
      }
      //--- swings also aim at unfilled daily gaps
      if(InpModel == CF_LI_SWING)
      {
         double lo = 0.0, hi = 0.0;
         int    k = 0;
         if(FindFvg(ctx.symbol, PERIOD_D1, -bias, 60, lo, hi, k))
         {
            double gapEdge = (bias > 0) ? hi : lo;
            if(IsBeyond(gapEdge, entry, bias, floorDist) && (best == 0.0 || IsNearer(gapEdge, entry, best, bias)))
               best = gapEdge;
         }
      }
      //--- fallback objective: prior weekly liquidity (the engine's Donchian over 5 completed days)
      if(best == 0.0)
      {
         double wHi = 0.0, wLo = 0.0;
         if(SigDonchian(ctx.symbol, 5, wHi, wLo))
         {
            double weekly = (bias > 0) ? wHi : wLo;
            if(IsBeyond(weekly, entry, bias, floorDist)) best = weekly;
         }
      }
      return best;
   }

   bool IsBeyond(const double level, const double entry, const int bias, const double risk)
   {
      if(level <= 0.0) return false;
      return (bias > 0) ? (level >= entry + risk) : (level <= entry - risk);
   }

   bool IsNearer(const double a, const double entry, const double b, const int bias)
   {
      return (bias > 0) ? (a < b) : (a > b);
   }

   //-------------------------------------------------------------------
   // Discipline helpers
   //-------------------------------------------------------------------
   //--- trailing run of losses in today's completed trades (a win resets it)
   int ConsecutiveLossesToday()
   {
      MqlDateTime dt;
      if(!TimeToStruct(TimeTradeServer(), dt)) return 0;
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      datetime dayStart = StructToTime(dt);
      if(!HistorySelect(dayStart, TimeTradeServer() + 60)) return 0;

      int  streak = 0;
      int  total  = HistoryDealsTotal();
      for(int i = 0; i < total; i++)                        // chronological: deals arrive oldest first
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagicNumber) continue;
         long kind = HistoryDealGetInteger(t, DEAL_ENTRY);
         if(kind != DEAL_ENTRY_OUT && kind != DEAL_ENTRY_OUT_BY && kind != DEAL_ENTRY_INOUT) continue;
         double p = HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_SWAP) +
                    HistoryDealGetDouble(t, DEAL_COMMISSION);
         if(p < 0.0) streak++;
         else if(p > 0.0) streak = 0;                       // "if he wins one and loses one, a third attempt"
      }
      return streak;
   }

   //--- one consecutive-loss log line per day (the day is carried in a dedicated field)
   bool LossLockLoggedToday(const datetime now, const bool mark = false)
   {
      MqlDateTime dt, ld;
      if(!TimeToStruct(now, dt)) return true;
      bool sameDay = (m_lossLockDay > 0 && TimeToStruct(m_lossLockDay, ld) &&
                      ld.year == dt.year && ld.mon == dt.mon && ld.day == dt.day);
      if(mark) m_lossLockDay = now;
      return sameDay;
   }

   void LogOnce(const datetime now, const string why)
   {
      MqlDateTime dt, ld;
      if(!TimeToStruct(now, dt)) return;
      if(m_standAsideDay > 0 && TimeToStruct(m_standAsideDay, ld) &&
         ld.year == dt.year && ld.mon == dt.mon && ld.day == dt.day) return;    // once per day, never per tick
      m_standAsideDay = now;
      EA_Log(EA_LOG_EVENTS, "liquidity inversion stands aside: " + why, true);
   }
};

CCfLiquidityInversion g_cfLiquidityInversion;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfLiquidityInversion);
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
