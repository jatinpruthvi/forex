//+------------------------------------------------------------------+
//|                          EA_CF_TrendlineBreakPocketStrategy.mq5   |
//|                                  Copyright 2026, Master Strategy  |
//|                                                                   |
//| ChartFanatics: Trendline Break Pocket Playbook (Ali Crook)         |
//| "Trendline Break Pocket Playbook" - Apr 2025, Forex / Swing       |
//| Card    : chartfanatics/todos/trendline-break-pocket-strategy.md   |
//| Source  : chartfanatics/pdf/trendline-break-pocket-strategy.pdf    |
//| Magic   : 3243                                                    |
//|                                                                   |
//| "When these occur together, the market is in the Trendline Break   |
//|  Pocket and ready for execution."                                  |
//|                                                                   |
//| The pocket needs ALL of these, so the EA checks them in order:      |
//|                                                                   |
//|   S1  THE KEY LEVEL (Frequency & Proximity): "a support or         |
//|       resistance zone identified using the Frequency & Proximity   |
//|       method" - multiple highs rejecting the same area (or lows    |
//|       holding) make a zone, and a zone that recent price respected |
//|       is active while one "broken through and chopped around" is   |
//|       weaker.  "Mid-range areas that have been broken through      |
//|       repeatedly are largely ignored."                             |
//|   S2  THE TRENDLINE: "drawn from the most recent swing that        |
//|       created the last higher high or lower low" - the line        |
//|       through the two most recent same-side swings, so "if price   |
//|       steepens ... use the more recent one".  "Breaking the        |
//|       trendline does not trigger a trade.  It simply shifts the    |
//|       market into the Pocket condition."                           |
//|   S3  THE MOMENTUM SHIFT: "the price must break the final swing of |
//|       the previous trend: last lower high in a downtrend, last     |
//|       higher low in an uptrend ... No swing break = no trade."     |
//|   S4  THE OVERSHOOT RULE: "the reaction can include one overshoot  |
//|       (a deeper wick or push).  However, if the price overshoots   |
//|       the level twice, the setup is void."                         |
//|   S5  THE TWO ENTRIES - "There are only two": the core pullback    |
//|       into the 21-period EMA with the entry order placed AT the    |
//|       EMA, or the consolidation breakout (at least two highs and   |
//|       two lows, on the correct side of the broken structure).      |
//|   S6  THE 2R MODEL: "Target = the high/low formed after momentum   |
//|       break; Stop = half the distance to the target" - the base    |
//|       model "targets 2R (2:1 reward:risk)" at a "~58% win rate".  |
//|   S7  CLEAN AIR: "look left.  You must have clean air (no major    |
//|       level, zone, or structure blocking your 2R target) ... Skip  |
//|       the trade."                                                  |
//|   S8  MANAGEMENT: "For standard 2R setups: no micromanagement, no  |
//|       trailing, no early exits."  The target or the stop, nothing  |
//|       else.                                                       |
//|                                                                   |
//| Analysis is on daily bars with weekly context available through    |
//| the pivot width; the trigger frame is daily, as the document's     |
//| default ("4H (optional advanced execution)" is the trader's        |
//| choice, not a new structure).  The MACD divergence check is a      |
//| score bonus (InpRequireMacdDiv makes it a hard gate).              |
//|                                                                   |
//| `[interpretation]`: the pivot width, the zone tolerance and the    |
//| touch / break windows, the proximity percentage, the pocket        |
//| window, the consolidation tolerance and bar count, the trendline   |
//| break's close-through definition, the stop-width sanity cap, the   |
//| clean-air window and the limit order's life are inputs and         |
//| labelled.                                                          |
//|                                                                   |
//| Disclosed, not faked: a retail-sentiment feed (the document's      |
//| "if you want to use a retail sentiment tool") does not exist in    |
//| MetaTrader, so it is not simulated; the weekly analysis frame is    |
//| expressed by the pivot width on the daily series, not by a second   |
//| chart the EA cannot read reliably across brokers.                   |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics Trendline Break Pocket - frequency/proximity zones, the trendline and swing breaks, the two entries, the 2R model"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade     = "EURUSD,GBPUSD,USDJPY";  // Universe (the playbook is Forex swing)
input ulong             InpMagicNumber        = 3243;             // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct            = 0.50;             // Risk per trade (% of equity)
input int               InpStage              = 5;                // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input double            InpMaxSpreadPoints    = 20.0;             // Spread gate (2 pips on a 5-digit feed)
input double            InpDailyLossPct       = 2.00;             // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset    = 2;                // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel           = EA_LOG_EVENTS;    // Log verbosity
input double            InpCommissionPerLotRT = 0.0;              // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.15;             // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;             // Write the engine evidence ledger CSV

//--- S1: the key levels (Frequency & Proximity)
input int               InpPivotSide          = 2;                // [interpretation] Bars each side of a swing point
input double            InpZoneTolPct         = 0.35;             // [interpretation] Pivots closer than this are one zone
input int               InpMinZoneHits        = 2;                // "multiple highs rejecting a similar price area" (two clean hits)
input int               InpZoneTouchBars      = 90;               // [interpretation] Proximity window: a zone must be recently tested
input int               InpMaxZoneBreaks      = 1;                // "broken through and chopped around it" -> weaker/ignored
input int               InpLevelTouchBars     = 30;               // [interpretation] The reaction must be this recent
input int               InpLevelOvershoots    = 1;                // "if the price overshoots the level twice, the setup is void"
input double            InpLevelPiercePct     = 0.10;             // [interpretation] A pierce beyond the zone by this much counts

//--- S2/S3: the pocket
input int               InpPocketBars         = 10;               // [interpretation] The pocket window after the swing break
input double            InpTlBreakPct         = 0.05;             // [interpretation] A close through the trendline by this much (%)

//--- S5: the two entries
input bool              InpUseEmaEntry        = true;             // Entry type 1 (core): the pullback into the 21 EMA
input int               InpEmaPeriod          = 21;               // "a pullback into the 21-period moving average"
input int               InpLimitDays          = 5;                // [interpretation] How long the EMA limit order may rest
input bool              InpUseConsolEntry     = true;             // Entry type 2: the consolidation breakout
input int               InpConsolBars         = 8;                // [interpretation] The consolidation window
input int               InpConsolTouches      = 2;                // "at least two highs, two lows"
input double            InpConsolTolPct       = 0.30;             // [interpretation] How close the touches must be

//--- S6/S7/S8: the 2R model, clean air, management
input double            InpStopFraction       = 0.50;             // "Stop = half the distance to the target"
input double            InpMaxStopPct         = 3.00;             // [interpretation] Reject stops wider than x% of price
input bool              InpRequireCleanAir    = true;             // "no major level, zone, or structure blocking your 2R target"
input int               InpCleanAirBars       = 120;              // [interpretation] The look-left window
input bool              InpUseMacdDiv         = true;             // "Look for opposite movement between price and MACD lines"
input bool              InpRequireMacdDiv     = false;            // ... as a score bonus unless this makes it a gate
input int               InpMaxSameDir         = 1;                // [interpretation] "multiple correlated markets may trigger together" - cap

//--- session / counters
input int               InpMaxTradesPerDay    = 2;                // The pocket is rare - few attempts

//+------------------------------------------------------------------+
#define CFTBP_LONG  1
#define CFTBP_SHORT 2

struct SZone
{
   double   lo, hi;
   int      hits;        // Frequency: how often the market respected the area
   int      breaks;      // Proximity: how often it was sliced through recently
   int      lastTouchIdx; // Proximity: the bar index of the most recent test (1 = the last completed bar)
   bool     isRes;       // above price = resistance
};

struct SPocket
{
   int      dir;            // +1 long, -1 short, 0 none
   double   swingLevel;     // the last higher low (short) / lower high (long) that must break
   double   target;         // the extreme formed after the momentum shift
   int      swingBreakIdx;  // bar index of the momentum shift
   int      tlBreakIdx;     // bar index of the trendline break
   int      zoneIdx;        // the reaction zone in the book
   bool     macdDiv;
};

//+------------------------------------------------------------------+
class CCfTrendlineBreakPocket : public CEAStrategy
{
public:
   void OnInitStrategy()
   {
      m_emaCount = 0;
      for(int i = 0; i < 8; i++) { m_emaSym[i] = ""; m_emaH[i] = INVALID_HANDLE; }
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "Trendline Break Pocket armed: %s, %s trigger, 21-EMA limit %s / consolidation breakout %s, the 2R model (stop = %.0f%% of the target distance)",
             InpSymbolsToTrade, EnumToString(PERIOD_D1),
             InpUseEmaEntry ? "on" : "off", InpUseConsolEntry ? "on" : "off", InpStopFraction * 100.0), true);
   }

   void OnDeinitStrategy()
   {
      for(int i = 0; i < m_emaCount; i++)
         if(m_emaH[i] != INVALID_HANDLE) { IndicatorRelease(m_emaH[i]); m_emaH[i] = INVALID_HANDLE; }
      m_emaCount = 0;
   }

   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_TRENDLINE_BREAK_POCKET";
      cfg.sourceDoc             = "chartfanatics/pdf/trendline-break-pocket-strategy.pdf (card #40)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_D1;       // "Trigger Timeframe: Daily (default)"
      cfg.clock                 = EA_CLOCK_SERVER; // FX trades around the clock; the daily bar is the anchor
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = 4.0;
      cfg.totalDdPct            = 10.0;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 2;               // the playbook is selective, and correlated FX triggers together
      cfg.minSecondsBetweenTrades = 3600;
      cfg.sessionStartHour      = 0;               // 24h market: the session gate stays open
      cfg.sessionStartMin       = 0;
      cfg.sessionEndHour        = 23;
      cfg.sessionEndMin         = 59;
      cfg.sessionEndFlat        = false;           // the target is a daily swing, not a session
      cfg.fridayFlat            = false;
      cfg.signalOnNewBarOnly    = true;            // one decision per completed daily bar
      cfg.useLimitEntry         = false;
      //--- S8: "For standard 2R setups: no micromanagement, no trailing, no early exits"
      cfg.breakEvenAtR          = 0.0;
      cfg.trailAtR              = 0.0;
      cfg.partial1AtR           = 0.0;
      cfg.partial2AtR           = 0.0;
      cfg.timeStopMinutes       = 0;
      cfg.pendingExpiryMinutes  = InpLimitDays * 24 * 60;   // the EMA limit's life
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_trendline_break_pocket_ledger.csv";
      cfg.logLevel              = InpLogLevel;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   //+----------------------------------------------------------------+
   //| The pocket, then its two (and only two) entries.                |
   //+----------------------------------------------------------------+
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(ctx.atr <= 0.0 || !ctx.inSession) return false;

      MqlRates d[];
      int got = EA_Rates(ctx.symbol, PERIOD_D1, 0, 320, d);
      if(got < 60) return false;

      SZone zones[24];
      int nZones = BuildZones(ctx, d, got, zones);
      if(nZones == 0) return false;

      SPocket pk;
      if(!FindPocket(ctx, d, got, zones, nZones, pk)) return false;
      if(InpRequireMacdDiv && !pk.macdDiv) return false;

      double best = -1.0;
      SSignalPlan p;
      p.Reset();
      if(InpUseEmaEntry && PlanEmaEntry(ctx, d, got, zones, nZones, pk, p) && p.score > best) { plan = p; best = p.score; }
      p.Reset();
      if(InpUseConsolEntry && PlanConsolEntry(ctx, d, got, zones, nZones, pk, p) && p.score > best) { plan = p; best = p.score; }

      if(plan.dir != 0 && SameDirectionCapReached(ctx.symbol, plan.dir))
         return false;                                     // "multiple correlated markets may trigger together"
      return (plan.dir != 0);
   }

private:
   string   m_emaSym[8];
   int      m_emaH[8];
   int      m_emaCount;

   //+----------------------------------------------------------------+
   //| S1: zones from swing pivots, counted (frequency) and dated      |
   //| (proximity).                                                    |
   //+----------------------------------------------------------------+
   int BuildZones(const SEAContext &ctx, const MqlRates &d[], const int got, SZone &zones[])
   {
      int n = 0;
      int side = (int)MathMax(1, InpPivotSide);
      double tol = InpZoneTolPct / 100.0;
      int scan = (int)MathMin(260, got - 2);

      for(int i = side; i + side < scan; i++)
      {
         bool ph = true, pl = true;
         for(int k = 1; k <= side; k++)
         {
            if(d[i].high <= d[i - k].high || d[i].high <= d[i + k].high) ph = false;
            if(d[i].low  >= d[i - k].low  || d[i].low  >= d[i + k].low)  pl = false;
         }
         if(ph) AddZone(zones, n, d[i].high, tol);
         if(pl) AddZone(zones, n, d[i].low,  tol);
      }
      if(n == 0) return 0;

      //--- proximity: the most recent test and the decisive breaks inside the window
      int window = (int)MathMin(InpZoneTouchBars, got - 2);
      for(int z = 0; z < n; z++)
      {
         zones[z].lastTouchIdx = 0;
         zones[z].breaks = 0;
         bool inBreak = false;
         for(int i = 1; i <= window; i++)
         {
            bool touched = (d[i].high >= zones[z].lo && d[i].low <= zones[z].hi);
            if(touched && zones[z].lastTouchIdx == 0) zones[z].lastTouchIdx = i;
            bool through = (d[i].close > zones[z].hi + zones[z].hi * tol) ||
                           (d[i].close < zones[z].lo - zones[z].lo * tol);
            if(through && !inBreak) { zones[z].breaks++; inBreak = true; }
            else if(!through) inBreak = false;
         }
         zones[z].isRes = ((zones[z].lo + zones[z].hi) / 2.0 > ctx.bid);
      }
      return n;
   }

   void AddZone(SZone &zones[], int &n, const double price, const double tol)
   {
      for(int i = 0; i < n; i++)
      {
         double mid = (zones[i].lo + zones[i].hi) / 2.0;
         if(MathAbs(mid - price) / price <= tol)
         {
            zones[i].hits++;
            zones[i].lo = MathMin(zones[i].lo, price);
            zones[i].hi = MathMax(zones[i].hi, price);
            return;
         }
      }
      if(n >= 24) return;
      zones[n].lo = price;
      zones[n].hi = price;
      zones[n].hits = 1;
      zones[n].breaks = 0;
      zones[n].lastTouchIdx = 0;
      zones[n].isRes = false;
      n++;
   }

   //--- "Good frequency + recently respected" -> usable; "only one clean reaction,
   //--- or recent breaks through" -> lower confidence; "broken through repeatedly" -> ignored
   bool ZoneUsable(const SZone &z)
   {
      if(z.hits < InpMinZoneHits) return false;               // frequency
      if(z.breaks > InpMaxZoneBreaks) return false;           // "broken through and chopped around it"
      if(z.lastTouchIdx == 0) return false;
      return (z.lastTouchIdx <= InpZoneTouchBars);            // proximity: respected recently
   }

   //--- "the reaction can include one overshoot ... if the price overshoots the
   //--- level twice, the setup is void" - count distinct pierces beyond the zone
   int CountOvershoots(const MqlRates &d[], const int got, const SZone &z, const bool above)
   {
      int n = 0;
      bool inPierce = false;
      int scan = (int)MathMin(60, got - 2);
      for(int i = 1; i <= scan; i++)
      {
         double edge = above ? z.hi * (1.0 + InpLevelPiercePct / 100.0)
                             : z.lo * (1.0 - InpLevelPiercePct / 100.0);
         bool pierced = above ? (d[i].high > edge) : (d[i].low < edge);
         if(pierced && !inPierce) { n++; inPierce = true; }
         else if(!pierced) inPierce = false;
      }
      return n;
   }

   //+----------------------------------------------------------------+
   //| S2/S3/S4: the pocket - level reaction, trendline break, last    |
   //| swing break, and no second overshoot.                            |
   //+----------------------------------------------------------------+
   bool FindPocket(const SEAContext &ctx, const MqlRates &d[], const int got, const SZone &zones[], const int nZones, SPocket &pk)
   {
      pk.dir = 0; pk.zoneIdx = -1; pk.macdDiv = false;
      pk.swingLevel = 0.0; pk.target = 0.0; pk.swingBreakIdx = 0; pk.tlBreakIdx = 0;

      int side = (int)MathMax(1, InpPivotSide);
      double tolPct = InpTlBreakPct / 100.0;

      //--- collect the four most recent same-side swings
      double hiPrice[4]; int hiIdx[4]; int nHi = 0;
      double loPrice[4]; int loIdx[4]; int nLo = 0;
      for(int i = side; i + side < got - 1 && (nHi < 4 || nLo < 4); i++)
      {
         bool ph = true, pl = true;
         for(int k = 1; k <= side; k++)
         {
            if(d[i].high <= d[i - k].high || d[i].high <= d[i + k].high) ph = false;
            if(d[i].low  >= d[i - k].low  || d[i].low  >= d[i + k].low)  pl = false;
         }
         if(ph && nHi < 4) { hiPrice[nHi] = d[i].high; hiIdx[nHi] = i; nHi++; }
         if(pl && nLo < 4) { loPrice[nLo] = d[i].low;  loIdx[nLo] = i; nLo++; }
      }

      //--- BOTH directions are evaluated; the score picks (the pocket is symmetric)
      for(int dir = 0; dir < 2; dir++)
      {
         bool isShort = (dir == 0);
         if((isShort && nLo < 2) || (!isShort && nHi < 2)) continue;

         //--- the trendline through the two most recent same-side swings: the up line
         //--- under the higher lows breaks downward, the down line over the lower highs
         //--- breaks upward.  "[the] most recent swing that created the last higher
         //--- high or lower low" keeps the line aligned with current momentum.
         double p0 = isShort ? loPrice[0] : hiPrice[0];
         double p1 = isShort ? loPrice[1] : hiPrice[1];
         int    i0 = isShort ? loIdx[0]   : hiIdx[0];
         int    i1 = isShort ? loIdx[1]   : hiIdx[1];
         if(i1 == i0) continue;

         bool tlBroken = false; int tlIdx = 0;
         for(int i = 1; i <= (int)MathMax(1, InpPocketBars) + 5 && i < got - 1; i++)
         {
            double line = p0 + (p1 - p0) * (double)(i - i0) / (double)(i1 - i0);
            bool through = isShort ? (d[i].close < line * (1.0 - tolPct))
                                   : (d[i].close > line * (1.0 + tolPct));
            if(through) { tlBroken = true; tlIdx = i; break; }
         }
         if(!tlBroken) continue;

         //--- S3: "the price must break the final swing of the previous trend: last
         //--- lower high in a downtrend, last higher low in an uptrend"
         double swingLevel = isShort ? loPrice[0] : hiPrice[0];
         int swingIdx = 0;
         for(int i = tlIdx - 1; i >= 1; i--)                  // walk older -> newer from the TL break
         {
            bool through = isShort ? (d[i].close < swingLevel) : (d[i].close > swingLevel);
            if(through) { swingIdx = i; break; }             // the break the document calls the shift
         }
         if(swingIdx == 0) continue;                          // "No swing break = no trade"
         if(swingIdx > (int)MathMax(1, InpPocketBars)) continue;   // the pocket is a small window, not history

         //--- S1: the reaction must have happened at a usable zone on the trade's side
         int zi = -1;
         for(int z = 0; z < nZones; z++)
         {
            if(!ZoneUsable(zones[z])) continue;
            if(isShort && !zones[z].isRes) continue;          // a resistance above price
            if(!isShort && zones[z].isRes) continue;          // a support below price
            if(CountOvershoots(d, got, zones[z], isShort) > InpLevelOvershoots) continue;  // S4
            if(zones[z].lastTouchIdx > InpLevelTouchBars) continue;   // the reaction must be recent
            zi = z;
            break;
         }
         if(zi < 0) continue;

         //--- S6: "Target = the high/low formed after momentum break"
         double target = isShort ? d[1].low : d[1].high;
         for(int i = 1; i <= swingIdx; i++)                  // every completed bar since the shift
            target = isShort ? MathMin(target, d[i].low) : MathMax(target, d[i].high);
         if(isShort && !(target < d[1].close)) continue;
         if(!isShort && !(target > d[1].close)) continue;

         pk.dir = isShort ? -1 : +1;
         pk.swingLevel = swingLevel;
         pk.target = target;
         pk.swingBreakIdx = swingIdx;
         pk.tlBreakIdx = tlIdx;
         pk.zoneIdx = zi;
         pk.macdDiv = MacdDivergence(d, got, isShort);
         return true;                                          // the first direction that qualifies wins
      }
      return false;
   }

   //--- S7: "look left ... no major level, zone, or structure blocking your 2R target"
   bool CleanAir(const double entry, const double target, const SZone &zones[], const int nZones, const int skipZone)
   {
      if(!InpRequireCleanAir) return true;
      double lo = MathMin(entry, target);
      double hi = MathMax(entry, target);
      for(int z = 0; z < nZones; z++)
      {
         if(z == skipZone) continue;
         if(zones[z].hits < InpMinZoneHits) continue;          // only major levels block
         if(zones[z].lastTouchIdx == 0 || zones[z].lastTouchIdx > InpCleanAirBars) continue;  // "look left"
         if(zones[z].hi >= lo && zones[z].lo <= hi) return false;
      }
      return true;
   }

   //--- "Look for opposite movement between: Price / MACD lines"
   bool MacdDivergence(const MqlRates &d[], const int got, const bool isShort)
   {
      if(!InpUseMacdDiv) return false;
      double fast[400], slow[400];
      int n = (int)MathMin(320, got - 2);
      if(n < 60) return false;
      //--- the series is newest-first: walk it oldest-first for the EMAs
      double k12 = 2.0 / 13.0, k26 = 2.0 / 27.0;
      double e12 = d[n].close, e26 = d[n].close;
      for(int i = n; i >= 1; i--)
      {
         e12 = e12 + k12 * (d[i].close - e12);
         e26 = e26 + k26 * (d[i].close - e26);
         fast[i] = e12;
         slow[i] = e26;
      }
      //--- the two most recent same-side swings of PRICE vs the MACD line there
      int side = (int)MathMax(1, InpPivotSide);
      double px[2]; double macd[2]; int found = 0;
      for(int i = side; i + side < n && found < 2; i++)
      {
         bool piv = true;
         for(int k = 1; k <= side; k++)
         {
            if(isShort)
            {
               if(d[i].high <= d[i - k].high || d[i].high <= d[i + k].high) piv = false;
            }
            else
            {
               if(d[i].low >= d[i - k].low || d[i].low >= d[i + k].low) piv = false;
            }
         }
         if(piv) { px[found] = isShort ? d[i].high : d[i].low; macd[found] = fast[i] - slow[i]; found++; }
      }
      if(found < 2) return false;
      //--- price higher high with a lower MACD high = weakening momentum
      bool div = isShort ? (px[0] > px[1] && macd[0] < macd[1]) : (px[0] < px[1] && macd[0] > macd[1]);
      return div;
   }

   //+----------------------------------------------------------------+
   //| S5 entry type 1 (core): "price pulls back into the 21 EMA ...   |
   //| entry order is placed at the EMA" - a resting limit at the EMA. |
   //+----------------------------------------------------------------+
   bool PlanEmaEntry(const SEAContext &ctx, const MqlRates &d[], const int got, const SZone &zones[], const int nZones,
                     const SPocket &pk, SSignalPlan &p)
   {
      int h = EmaHandle(ctx.symbol);
      double ema = 0.0;
      if(!EA_Buf(h, 0, 1, ema)) return false;
      double price = (pk.dir > 0) ? ctx.ask : ctx.bid;
      //--- the retracement must still be ahead of the market, not behind it
      if(pk.dir > 0 && !(ema < price)) return false;
      if(pk.dir < 0 && !(ema > price)) return false;
      if(pk.dir > 0 && !(pk.target > ema)) return false;      // the target must be beyond the entry
      if(pk.dir < 0 && !(pk.target < ema)) return false;

      double risk = MathAbs(ema - pk.target) * InpStopFraction;
      if(risk <= 0.0) return false;
      double stop = (pk.dir > 0) ? ema - risk : ema + risk;
      if(!StopOk(ema, stop)) return false;

      p.dir = pk.dir;
      p.entry = ema;
      p.stop = stop;
      p.target = pk.target;
      p.riskDist = risk;
      p.barsAgo = 1;
      p.isLimit = true;                                   // "Entry order is placed at the EMA"
      p.expiry = TimeTradeServer() + (datetime)((long)InpLimitDays * 86400);
      p.score = 88.0;                                     // "the primary entry of the playbook"
      if(pk.macdDiv) p.score += 4.0;
      if(!CleanAir(ema, pk.target, zones, nZones, pk.zoneIdx)) return false;
      p.reason = StringFormat("pocket %s: trendline + last swing broken, pullback into the %d EMA %.5f (limit, %d day life)",
                              (pk.dir > 0 ? "LONG" : "SHORT"), InpEmaPeriod, ema, InpLimitDays);
      return true;
   }

   //+----------------------------------------------------------------+
   //| S5 entry type 2: "a small consolidation below/above the broken  |
   //| structure ... breakout entry above/below the consolidation"     |
   //+----------------------------------------------------------------+
   bool PlanConsolEntry(const SEAContext &ctx, const MqlRates &d[], const int got, const SZone &zones[], const int nZones,
                        const SPocket &pk, SSignalPlan &p)
   {
      int n = (int)MathMax(3, InpConsolBars);
      if(got < n + 5) return false;
      if(pk.swingBreakIdx <= n + 1) return false;            // the box must sit after the momentum shift
      //--- the consolidation is the newest stretch of completed bars ("forms after the last swing break")
      int from = 2, to = n + 1;
      double cHi = d[from].high, cLo = d[from].low;
      for(int i = from; i <= to; i++)
      {
         cHi = MathMax(cHi, d[i].high);
         cLo = MathMin(cLo, d[i].low);
      }
      if((cHi - cLo) / cLo * 100.0 > 3.0) return false;             // [interpretation] a consolidation, not a leg
      if(pk.dir > 0 && !(cLo > pk.swingLevel)) return false;        // above the broken structure
      if(pk.dir < 0 && !(cHi < pk.swingLevel)) return false;        // below it

      //--- "at least two highs, two lows": touches of the box edges
      double tol = InpConsolTolPct / 100.0;
      int hiTouches = 0, loTouches = 0;
      for(int i = from; i <= to; i++)
      {
         if(d[i].high >= cHi * (1.0 - tol)) hiTouches++;
         if(d[i].low  <= cLo * (1.0 + tol)) loTouches++;
      }
      if(hiTouches < InpConsolTouches || loTouches < InpConsolTouches) return false;

      //--- the breakout of the box, on the completed bar
      double entry = (pk.dir > 0) ? ctx.ask : ctx.bid;
      if(pk.dir > 0 && !(d[1].close > cHi)) return false;
      if(pk.dir < 0 && !(d[1].close < cLo)) return false;

      double risk = MathAbs(entry - pk.target) * InpStopFraction;
      if(risk <= 0.0) return false;
      double stop = (pk.dir > 0) ? entry - risk : entry + risk;
      if(!StopOk(entry, stop)) return false;
      if(!CleanAir(entry, pk.target, zones, nZones, pk.zoneIdx)) return false;

      p.dir = pk.dir;
      p.entry = entry;
      p.stop = stop;
      p.target = pk.target;
      p.riskDist = risk;
      p.barsAgo = 1;
      p.isLimit = false;
      p.score = 84.0;
      if(pk.macdDiv) p.score += 4.0;
      p.reason = StringFormat("pocket %s: consolidation breakout (%.5f-%.5f, %d/%d touches) after the momentum shift",
                              (pk.dir > 0 ? "LONG" : "SHORT"), cLo, cHi, hiTouches, loTouches);
      return true;
   }

   bool StopOk(const double entry, const double stop)
   {
      if(stop <= 0.0) return false;
      double risk = MathAbs(entry - stop);
      if(risk <= 0.0) return false;
      return (risk <= entry * InpMaxStopPct / 100.0);
   }

   //--- "Multiple correlated markets may trigger together" - one trade per direction
   bool SameDirectionCapReached(const string sym, const int dir)
   {
      int open = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != (long)g_eaCfg.magic) continue;
         bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         if((dir > 0 && isBuy) || (dir < 0 && !isBuy)) open++;
      }
      return (open >= InpMaxSameDir);
   }

   //--- one EMA21 handle per symbol, created on demand
   int EmaHandle(const string sym)
   {
      for(int i = 0; i < m_emaCount; i++)
         if(m_emaSym[i] == sym) return m_emaH[i];
      if(m_emaCount >= 8) return INVALID_HANDLE;
      m_emaSym[m_emaCount] = sym;
      m_emaH[m_emaCount] = iMA(sym, PERIOD_D1, InpEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(m_emaH[m_emaCount] == INVALID_HANDLE)
         EA_Log(EA_LOG_ERRORS, StringFormat("EMA(%d) handle failed for %s (err %d)", InpEmaPeriod, sym, GetLastError()), true);
      m_emaCount++;
      return m_emaH[m_emaCount - 1];
   }

};

CCfTrendlineBreakPocket g_cfTrendlineBreakPocket;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfTrendlineBreakPocket);
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
