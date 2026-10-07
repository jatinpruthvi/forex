//+------------------------------------------------------------------+
//|                                        EA_CF_Structure_OTE.mq5   |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| ChartFanatics playbook: Structure & OTE (Trader Mayne, Apr 2025) |
//| Card    : chartfanatics/todos/structure-ote.md  (#26)            |
//| Source  : chartfanatics/pdf/structure-ote.pdf                    |
//| Magic   : 3202                                                   |
//|                                                                  |
//| Top-down framework:                                              |
//|   1. HTF (Weekly/Daily/H4) break of structure sets the bias.     |
//|   2. Mark the dealing range of that leg; the 50% line splits      |
//|      premium from discount. Longs only at a discount, shorts      |
//|      only at a premium.                                          |
//|   3. The POI is the order block / breaker / FVG that produced     |
//|      the break; price must pull back INTO it.                     |
//|   4. LTF (H1/M15) confirmation: engineered liquidity is swept     |
//|      and structure breaks the other way (the breaker entry).      |
//|   5. Stop beyond the swept extreme, target the next external      |
//|      liquidity, minimum 2R.                                      |
//|                                                                  |
//| docs/ICT_SMC_COVERAGE.md lists premium/discount and OTE (62-79%)  |
//| as NOT implemented anywhere in this repository. This EA is the    |
//| first implementation: `InOteBand()` measures the retracement of   |
//| the active HTF leg and refuses entries outside the band.          |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics Structure & OTE - HTF break, premium/discount, OTE retracement into the POI"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade   = "US100,US500,GER40";  // Universe (playbook: futures / crypto / forex)
input ulong             InpMagicNumber      = 3202;                 // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct          = 0.50;                 // Risk per trade (% of equity)
input double            InpMaxSpreadPoints  = 3.0;                  // Spread gate in points (0 = off)
input double            InpDailyLossPct     = 1.50;                 // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset  = 2;                    // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;        // Log verbosity
input double            InpCommissionPerLotRT = 0.0;                // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.12;               // Reject setups whose all-in cost exceeds xR
input bool              InpLedger             = true;               // Write the engine evidence ledger CSV
//--- structure / OTE
input ENUM_TIMEFRAMES InpHtfTimeframe   = PERIOD_H4;   // HTF range (Daily -> H1, H4 -> M15 in the playbook)
input ENUM_TIMEFRAMES InpLtfTimeframe   = PERIOD_M15;  // Execution timeframe
input int    InpHtfBars           = 120;    // HTF bars that define the dealing range
input int    InpLegBars           = 40;     // LTF bars that define the active leg (checked with the HTF)
input double InpOteMin            = 0.62;   // OTE band lower bound
input double InpOteMax            = 0.79;   // OTE band upper bound
input bool   InpUseOte            = true;   // Require the entry to sit inside the OTE band
input bool   InpRequireDiscount   = true;   // Longs only in discount, shorts only in premium
input int    InpSessionFromMin    = 420;    // Entry window start (07:00 London)
input int    InpSessionToMin      = 1080;   // Entry window end   (18:00 London)
input int    InpPoILookbackBars   = 12;     // Order-block search window (signal TF)
input double InpDisplacementBody  = 0.55;   // Displacement body ratio for the POI
input double InpTouchTolAtr       = 0.20;   // How close price must come to the POI
input int    InpReclaimWindowBars = 3;      // Breaker fallback: bars from sweep to reclaim
input bool   InpRequireEngineeredLiquidity = true; // Swept extreme must be a swing point (engine SigFractals)
input double InpEntryRetrace      = 0.50;   // Breaker fallback: limit at 50% of the body
input double InpStopBufferAtr     = 0.15;   // Stop buffer beyond the swept extreme / block
input double InpMinRR             = 2.00;   // "Must be at least 2:1 RR to qualify"
input bool   InpUseExternalTarget = true;   // Target the next external liquidity (HTF range extreme)

//+------------------------------------------------------------------+
//| Strategy class                                                   |
//+------------------------------------------------------------------+
class CCfStructureOte : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_STRUCTURE_OTE";
      cfg.sourceDoc             = "chartfanatics/pdf/structure-ote.pdf (card #26)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = InpLtfTimeframe;
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
      cfg.sessionStartHour      = InpSessionFromMin / 60;
      cfg.sessionStartMin       = InpSessionFromMin % 60;
      cfg.sessionEndHour        = InpSessionToMin / 60;
      cfg.sessionEndMin         = InpSessionToMin % 60;
      cfg.noTradeAfterHour      = 18;  cfg.noTradeAfterMin = 0;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 19;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = true;
      cfg.pendingExpiryMinutes  = 30;
      cfg.breakEvenAtR          = 1.0;
      cfg.partial1AtR           = 1.0;  cfg.partial1Pct = 40.0;
      cfg.trailAtR              = 1.5;  cfg.trailDistanceR = 1.0;
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;             // engine cost gate: (spread + commission) <= xR
      cfg.ledgerEnabled         = InpLedger;               // engine ledger: one row per open / partial / close
      cfg.ledgerFile            = "cf_structure_ote_ledger.csv";
      cfg.newsFilter            = false;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession) return false;
      if(ctx.atr <= 0.0 || ctx.atrD1 <= 0.0) return false;

      int bias = HtfBias(ctx);
      if(bias == 0) return false;                     // no clean HTF structure -> stand aside

      double hi = 0.0, lo = 0.0;
      if(!DealingRange(ctx, hi, lo)) return false;
      double half = 0.5 * (hi + lo);

      if(InpRequireDiscount)
      {
         if(bias > 0 && ctx.mid > half) return false;   // no longs in premium
         if(bias < 0 && ctx.mid < half) return false;   // no shorts in discount
      }
      if(InpUseOte && !InOteBand(ctx, bias)) return false;

      SSignalPlan found;
      bool havePlan = OrderBlockPlan(ctx, bias, found);
      if(!havePlan) havePlan = BreakerPlan(ctx, bias, found);
      if(!havePlan) return false;
      if(found.dir != bias) return false;

      double rr = MathAbs(found.target - found.entry) / found.riskDist;
      if(InpUseExternalTarget)
      {
         double external = (found.dir > 0) ? hi : lo;               // next external liquidity
         double externalRr = MathAbs(external - found.entry) / found.riskDist;
         if(externalRr >= InpMinRR)
         {
            found.target = external;
            rr = externalRr;
         }
      }
      if(rr < InpMinRR) return false;

      found.score = found.score + MathMin(20.0, rr * 5.0);
      found.reason = StringFormat("Structure+OTE (bias %d, %.2fR to target): ", bias, rr) + found.reason;
      plan = found;
      return true;
   }

private:
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

   //--- HTF range from SWING structure: the playbook measures the dealing range from the last
   //--- significant swing low to swing high, not from the window's raw extremes.  The engine's
   //--- SigFractals() is locked to the signal timeframe, so its 3-bar fractal rule is applied to
   //--- the HTF series here; raw window extremes are the fallback when no swing confirms.
   bool HTFRange(SEAContext &ctx, const ENUM_TIMEFRAMES tf, const int bars, double &hi, double &lo)
   {
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, tf, 1, bars, r);
      if(got < 10) return false;

      double swingHi = 0.0, swingLo = 0.0;
      int    hiIdx = -1,   loIdx = -1;
      for(int i = 1; i < got - 2; i++)
      {
         if(hiIdx < 0 && r[i].high > r[i + 1].high && r[i].high > r[i + 2].high &&
            r[i].high > r[i - 1].high)
         {
            swingHi = r[i].high; hiIdx = i;
         }
         if(loIdx < 0 && r[i].low < r[i + 1].low && r[i].low < r[i + 2].low &&
            r[i].low < r[i - 1].low)
         {
            swingLo = r[i].low; loIdx = i;
         }
         if(hiIdx >= 0 && loIdx >= 0) break;
      }
      if(hiIdx >= 0 && loIdx >= 0 && swingHi > swingLo)
      {
         hi = swingHi;
         lo = swingLo;
         return true;
      }

      hi = -DBL_MAX;
      lo =  DBL_MAX;
      for(int i = 0; i < got; i++)
      {
         if(r[i].high > hi) hi = r[i].high;
         if(r[i].low  < lo) lo = r[i].low;
      }
      return (hi > lo);
   }

   //--- dealing range of the last HTF leg
   bool DealingRange(SEAContext &ctx, double &hi, double &lo)
   {
      return HTFRange(ctx, InpHtfTimeframe, InpHtfBars, hi, lo);
   }

   //--- OTE: the entry must sit in the 62-79% retracement of the active leg
   bool InOteBand(SEAContext &ctx, const int dir)
   {
      double hi = 0.0, lo = 0.0;
      if(!HTFRange(ctx, InpHtfTimeframe, InpLegBars, hi, lo)) return false;
      double span = hi - lo;
      if(span <= 0.0) return false;
      double retrace = (dir > 0) ? (hi - ctx.mid) / span : (ctx.mid - lo) / span;
      return (retrace >= InpOteMin && retrace <= InpOteMax);
   }

   //--- "engineered liquidity (a swing low or high)" from the playbook, checked with the engine's
   //--- own swing detector: the swept extreme must sit on a confirmed fractal within tolerance.
   bool SweptEngineeredLiquidity(SEAContext &ctx, const int dir, const double sweptExtreme,
                                 const int sweepBarsAgo)
   {
      if(!InpRequireEngineeredLiquidity) return true;
      if(sweepBarsAgo < 1) return false;
      double highs[], lows[];
      int    hiIdx[], loIdx[];
      if(SigFractals(ctx.symbol, 6, highs, lows, hiIdx, loIdx) < 2) return false;
      double tol = 0.35 * ctx.atr;
      if(dir < 0)
      {
         for(int i = 0; i < ArraySize(highs); i++)
            if(hiIdx[i] <= sweepBarsAgo && MathAbs(highs[i] - sweptExtreme) <= tol) return true;
         return false;
      }
      for(int i = 0; i < ArraySize(lows); i++)
         if(loIdx[i] <= sweepBarsAgo && MathAbs(lows[i] - sweptExtreme) <= tol) return true;
      return false;
   }

   //--- POI entry: the order block (or FVG) that produced the HTF break
   bool OrderBlockPlan(SEAContext &ctx, const int dir, SSignalPlan &out)
   {
      SOrderBlockParams ob;
      ob.Reset();
      ob.lookbackBars     = InpPoILookbackBars;
      ob.displacementBody = InpDisplacementBody;
      ob.touchTolAtr      = InpTouchTolAtr;
      ob.stopBufferAtr    = InpStopBufferAtr;
      ob.targetR          = InpMinRR;
      ob.requireHtfBias   = true;
      ob.tradeBothWays    = true;
      ob.onlyDir          = dir;
      return SigOrderBlockRetest(ctx, ob, out);
   }

   //--- breaker alternative: sweep of engineered liquidity, then a structure break back
   bool BreakerPlan(SEAContext &ctx, const int dir, SSignalPlan &out)
   {
      SSweepParams sp;
      sp.Reset();
      sp.rangeFromMin       = 0;
      sp.rangeToMin         = InpSessionFromMin;
      sp.sessionFromMin     = InpSessionFromMin;
      sp.sessionToMin       = InpSessionToMin;
      sp.sweepMinAtr        = 0.05;
      sp.sweepMaxAtr        = 1.50;
      sp.reclaimWindowBars  = InpReclaimWindowBars;
      sp.wickRatio          = 0.50;
      sp.bodyRatio          = 0.55;
      sp.stopBufferAtr      = InpStopBufferAtr;
      sp.minStopAtr         = 0.25;
      sp.maxStopAtr         = 2.50;
      sp.targetR            = InpMinRR;
      sp.entryRetrace       = InpEntryRetrace;
      sp.requireDisplacement= true;
      sp.tradeBothWays      = true;       // the HTF-bias check below rejects the other side
      sp.scoreBase          = 58.0;
      //--- NOTE: the primitive evaluates the bullish sequence first, so for a bearish bias an
      //--- OLDER bullish sequence can mask a fresh bearish one.  This fallback therefore fires
      //--- less often than the order-block path, which supports `onlyDir` directly.
      if(!SigSweepReclaim(ctx, sp, out)) return false;
      if(out.dir != dir)
      {
         out.Reset();
         return false;
      }
      //--- the sweep has to have taken out a SWING (engineered liquidity), not a random tick
      double buffer = InpStopBufferAtr * ctx.atr;
      double sweptExtreme = (out.dir < 0) ? (out.stop - buffer) : (out.stop + buffer);
      if(!SweptEngineeredLiquidity(ctx, out.dir, sweptExtreme, out.sweepBarsAgo))
      {
         out.Reset();
         return false;
      }
      return true;
   }
};

CCfStructureOte g_cfStructureOte;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfStructureOte);
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
