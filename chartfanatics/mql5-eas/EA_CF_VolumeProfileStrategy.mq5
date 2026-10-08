//+------------------------------------------------------------------+
//|                                EA_CF_VolumeProfileStrategy.mq5    |
//|                                  Copyright 2026, Master Strategy  |
//|                                                                   |
//| ChartFanatics: Volume Profile Strategy (Forrest Knight's Playbook) |
//| "Volume Profile Playbook" - Apr 2025, Futures / Options            |
//| Card    : chartfanatics/todos/volume-profile-strategy.md    (#44)  |
//| Source  : chartfanatics/pdf/volume-profile-strategy.pdf            |
//| Magic   : 3247                                                    |
//|                                                                   |
//| "price reacts differently depending on how much volume has been    |
//|  transacted at each price level ... High-Value Areas (HVAs) -      |
//|  price tends to consolidate where a large number of transactions   |
//|  have occurred.  These zones are 'sticky'.  Low-Value Areas (LVAs) |
//|  - price tends to move quickly through zones with little trading   |
//|  activity."                                                        |
//|                                                                   |
//|   S1  THE FOUR KEY DAILY LEVELS: "Overnight High, Overnight Low,    |
//|       Prior Day High, Prior Day Low ... liquidity zones where       |
//|       trapped traders are likely to act aggressively when the      |
//|       price returns."                                              |
//|   S2  THE THREE ELEMENTS OF A TRADE: "Price is touching a volume    |
//|       profile edge (transition from HVA to LVA or vice versa).     |
//|       The location aligns with a key contextual level (ONH/ONL/    |
//|       PDH/PDL).  A high volume signal candle forms with a visible  |
//|       wick rejecting the area and closing in the trade direction." |
//|       "Always wait for the signal candle to close.  Do not         |
//|       front-run it."                                               |
//|   S3  THE HIGHER-TIMEFRAME BIAS: "If the Weekly chart closes with a |
//|       high volume bottom-wick reversal candle at a volume edge,    |
//|       then the bias is long.  All intraday setups should then      |
//|       favour long trades" - and the mirror for shorts.             |
//|   S4  EXECUTION: "Entry: after the signal candle closes at the     |
//|       volume edge.  Stop: just beyond the signal candle's wick or  |
//|       beyond the edge of the high value node.  Target: the next    |
//|       shelf - edge-to-edge targeting.  You trade through           |
//|       low-volume zones and look for the next high-volume area."    |
//|   S5  THE TWO NAMED SETUPS: the Previous Day POC Retest ("after a  |
//|       breakout or trend day, the price often returns to the prior  |
//|       day's POC before resuming the trend ... look for a signal    |
//|       candle at the prior day's POC and target a new high/low")    |
//|       and the Volatility-Based Retest Entry ("If the signal candle |
//|       has a long wick -> expect a 50-80% wick retrace before       |
//|       continuation.  Set a limit order in that retrace zone").     |
//|   S6  THE MID-ZONE RULE: "Low-volume zones are unpredictable;      |
//|       avoid entries in the middle.  Wait for the price to hit an   |
//|       edge before trading."                                        |
//|                                                                   |
//| `[interpretation]`: the signal timeframe (the document names 4H    |
//| and 1H), profile bucket counts, HVA/LVA thresholds, edge tolerance,|
//| overnight clock hours, wick/volume thresholds and lookbacks, the   |
//| sweep-and-close gate applied to the worked example's generic       |
//| contextual-level rejection, and the named POC setup's exception   |
//| (used only if no standard edge setup qualifies) to the generic    |
//| edge/mid-zone gate.  The 50-80% retest fraction is                |
//| measured inside the actual rejection wick from the body edge.     |
//| Trend-day threshold, session-profile HVN stop fallback, stop     |
//| buffer/cap, target floor/fallback, and trade caps are also        |
//| interpretations where the document gives no number.              |
//|                                                                   |
//| Disclosed, not faked: MetaTrader exposes tick volume, not exchange |
//| volume, so every profile below is built from tick volume spread    |
//| across each bar's range - the same proxy the house's other         |
//| profile EAs use.  The document also says the method "requires       |
//| volume data: not viable in decentralized markets like spot forex", |
//| which is why the default universe is the NQ/ES index proxies the   |
//| worked example uses rather than an FX pair.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics Volume Profile Strategy - HVN/LVN edges built from tick volume, the four key daily levels (ONH/ONL/PDH/PDL), a high-volume signal candle with a rejection wick, the weekly bias, the prior-day POC retest and edge-to-edge targeting"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade     = "US100,US500";    // "Works well for NQ" - and the method needs centralized volume data
input ulong             InpMagicNumber        = 3247;             // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct            = 0.50;             // Risk per trade (% of equity)
input int               InpStage              = 5;                // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input double            InpMaxSpreadPoints    = 40.0;             // Spread gate in points (0 = off)
input double            InpDailyLossPct       = 2.00;             // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset    = 2;                // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel           = EA_LOG_EVENTS;    // Log verbosity
input double            InpCommissionPerLotRT = 0.0;              // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.15;             // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;             // Write the engine evidence ledger CSV

//--- the frame
input ENUM_TIMEFRAMES   InpSignalTf           = PERIOD_H1;        // "4H and 1H are the main chart timeframes"
input int               InpSessionBuckets     = 60;               // [interpretation] Buckets in the current server-day profile; source gives no session hours
input int               InpVrBars             = 120;              // [interpretation] The "Visible Range" window, in signal bars
input int               InpVrBuckets          = 60;               // [interpretation] Price buckets in the visible-range profile
input int               InpHtfDays            = 5;                // "Higher timeframes (Weekly, Daily) are used to identify long-term value areas"

//--- S1: the four key daily levels
input int               InpOnStartHour        = 18;               // [interpretation] The overnight window's start (server hour)
input int               InpOnStartMin         = 0;
input int               InpOnEndHour          = 0;                // [interpretation] ... and its end (the day's open, server hour)
input int               InpOnEndMin           = 0;

//--- S2: the volume edge and the signal candle
input double            InpHvnFactor          = 1.30;             // [interpretation] A bucket at x times the average volume is high-value
input double            InpLvaFactor          = 0.60;             // [interpretation] ... and this quiet is low-value (the edge between them)
input double            InpEdgeTolPct         = 0.15;             // [interpretation] How close the key level must sit to a profile edge
input double            InpWickFrac           = 0.50;             // "a visible wick rejecting the area" - this share of the candle's range
input double            InpVolFactor          = 1.50;             // "a high volume signal candle" - this multiple of the average bar volume
input int               InpVolAvgBars         = 20;               // [interpretation] ... measured over this many bars
input int               InpMinSignalBodyPct   = 10;               // [interpretation] "closing in the trade direction": a body at least this big (in % of range)

//--- S3: the weekly bias
input int               InpBiasWeeks          = 12;               // [interpretation] Prior-week profile and volume baseline for the weekly reversal candle
input double            InpBiasWickFrac       = 0.50;             // "a high volume bottom-wick reversal candle" - the wick's share of the range

//--- S5: the two named setups
input bool              InpUsePocRetest       = true;             // "A core setup is the Previous Point of Control (POC) Retest"
input double            InpTrendDayAtr        = 0.70;             // [interpretation] ATR-sized trend threshold; a directional close breakout is an alternative
input bool              InpUseWickRetrace     = true;             // "expect a 50-80% wick retrace before continuation"
input double            InpLongWickFrac       = 0.60;             // [interpretation] What counts as "a long wick"
input double            InpRetraceFrac        = 0.50;             // [interpretation] 50-80% of the actual wick from body edge toward its tip
input int               InpLimitBars          = 3;                // [interpretation] The retrace limit's life, in signal bars

//--- S4: the stop, the target and the caps
input double            InpStopBufferAtr      = 0.10;             // "just beyond the signal candle's wick" - a small structural buffer
input double            InpMaxStopPct         = 2.50;             // [interpretation] Reject stops wider than x% of price
input double            InpMinTargetR         = 1.50;             // [interpretation] Minimum reward floor for the next shelf or POC target
input double            InpTargetR            = 3.00;             // [interpretation] Far fallback target
input int               InpMaxTradesPerDay    = 3;                // [interpretation] "Fewer Trades ... requiring patience"
input int               InpMaxOpenPositions   = 2;                // [interpretation] A small portfolio cap
input int               InpMinSecondsBetween  = 1800;             // [interpretation] One attempt per signal bar at most

//+------------------------------------------------------------------+
//| A tick-volume profile: `buckets` price buckets over [lo, hi]      |
//+------------------------------------------------------------------+
#define CFVP_MAX_BUCKETS 128

struct SProfile
{
   double lo;
   double hi;
   double step;
   int    buckets;
   double vol[CFVP_MAX_BUCKETS];
};

//--- A profile with unavailable history must be inert, not stack garbage.
void CFVP_InitProfile(SProfile &pf)
{
   pf.lo = 0.0;
   pf.hi = 0.0;
   pf.step = 0.0;
   pf.buckets = 0;
   for(int i = 0; i < CFVP_MAX_BUCKETS; i++) pf.vol[i] = 0.0;
}

//+------------------------------------------------------------------+
class CCfVolumeProfile : public CEAStrategy
{
public:
   bool InputsValid()
   {
      if(PeriodSeconds(InpSignalTf) <= 0 || PeriodSeconds(InpSignalTf) >= 86400)
      {
         Print("CF_VOLUME_PROFILE: signal timeframe must be a valid intraday period");
         return false;
      }
      if(InpVolAvgBars < 1 || InpVolAvgBars > 1000 || InpVrBars < 1 || InpVrBars > 10000)
      {
         Print("CF_VOLUME_PROFILE: volume lookback and visible-range bars must be positive and bounded");
         return false;
      }
      if(InpHtfDays < 1 || InpHtfDays > 365 || InpBiasWeeks < 1 || InpBiasWeeks > 260)
      {
         Print("CF_VOLUME_PROFILE: higher-timeframe lookbacks must be positive and bounded");
         return false;
      }
      if(InpOnStartHour < 0 || InpOnStartHour > 23 || InpOnEndHour < 0 || InpOnEndHour > 23 ||
         InpOnStartMin < 0 || InpOnStartMin > 59 || InpOnEndMin < 0 || InpOnEndMin > 59 ||
         (InpOnStartHour == InpOnEndHour && InpOnStartMin == InpOnEndMin))
      {
         Print("CF_VOLUME_PROFILE: overnight window must use valid, distinct server-clock times");
         return false;
      }
      if(InpHvnFactor <= InpLvaFactor || InpLvaFactor < 0.0 || InpEdgeTolPct < 0.0 ||
         InpVolFactor <= 0.0 || InpWickFrac <= 0.0 || InpWickFrac >= 1.0 ||
         InpMinSignalBodyPct < 0 || InpMinSignalBodyPct > 100 ||
         InpBiasWickFrac <= 0.0 || InpBiasWickFrac >= 1.0 || InpLongWickFrac <= 0.0 || InpLongWickFrac >= 1.0)
      {
         Print("CF_VOLUME_PROFILE: profile and signal thresholds are inconsistent");
         return false;
      }
      if(InpUseWickRetrace && (InpLimitBars < 1 || InpRetraceFrac < 0.50 || InpRetraceFrac > 0.80))
      {
         Print("CF_VOLUME_PROFILE: wick retrace must be 50-80% of the rejection wick and have a positive expiry");
         return false;
      }
      if(InpUsePocRetest && InpTrendDayAtr <= 0.0)
      {
         Print("CF_VOLUME_PROFILE: the POC trend-day ATR threshold must be positive");
         return false;
      }
      if(InpStopBufferAtr <= 0.0 || InpMaxStopPct <= 0.0 || InpMinTargetR < 0.0 ||
         InpTargetR <= 0.0 || InpTargetR < InpMinTargetR)
      {
         Print("CF_VOLUME_PROFILE: the structural stop buffer must be positive and stop/target distances consistent");
         return false;
      }
      return true;
   }

   void OnInitStrategy()
   {
      for(int i = 0; i < EA_MAX_SYMBOLS; i++) m_lastPlanBar[i] = 0;
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "Volume Profile armed: %s on %s, session profile %d buckets, visible range %d bars over %d buckets, key levels ONH/ONL (server %02d:%02d-%02d:%02d) + PDH/PDL, signal candle wick %.0f%% of range at >= %.1fx volume, weekly bias %s",
             InpSymbolsToTrade, EnumToString(InpSignalTf), InpSessionBuckets, InpVrBars, InpVrBuckets,
             InpOnStartHour, InpOnStartMin, InpOnEndHour, InpOnEndMin,
             InpWickFrac * 100.0, InpVolFactor, "on"), true);
   }

   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_VOLUME_PROFILE";
      cfg.sourceDoc             = "chartfanatics/pdf/volume-profile-strategy.pdf (card #44)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = InpSignalTf;      // "Execution timeframes: 4H and 1H"
      cfg.clock                 = EA_CLOCK_SERVER;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = 4.0;
      cfg.totalDdPct            = 10.0;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = InpMaxOpenPositions;
      cfg.minSecondsBetweenTrades = InpMinSecondsBetween;
      cfg.sessionStartHour      = 0;
      cfg.sessionStartMin       = 0;
      cfg.sessionEndHour        = 23;
      cfg.sessionEndMin         = 59;
      cfg.sessionEndFlat        = false;
      cfg.fridayFlat            = false;
      cfg.signalOnNewBarOnly    = true;             // "Always wait for the signal candle to close.  Do not front-run it."
      cfg.useLimitEntry         = false;
      //--- the document states the stop and the target and nothing else
      cfg.breakEvenAtR          = 0.0;
      cfg.trailAtR              = 0.0;
      cfg.partial1AtR           = 0.0;
      cfg.partial2AtR           = 0.0;
      cfg.timeStopMinutes       = 0;
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_volume_profile_ledger.csv";
      cfg.logLevel              = InpLogLevel;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   //+----------------------------------------------------------------+
   //| S2: the signal candle at a key level that is also a volume edge |
   //+----------------------------------------------------------------+
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      // EACommon's outer new-bar gate follows the first configured symbol. A
      // second symbol with missing/delayed bars can otherwise replay one old
      // closed-candle signal on several later outer-bar events.
      if(ctx.index < 0 || ctx.index >= EA_MAX_SYMBOLS) return false;
      datetime symbolBar = iTime(ctx.symbol, g_eaIndTf, 0);
      if(symbolBar <= 0 || symbolBar <= m_lastPlanBar[ctx.index]) return false;
      m_lastPlanBar[ctx.index] = symbolBar;
      if(ctx.atr <= 0.0 || !ctx.inSession) return false;

      MqlRates d[];
      int signalSeconds = PeriodSeconds(g_eaIndTf);
      if(signalSeconds <= 0) return false;
      int sessionBars = (86400 + signalSeconds - 1) / signalSeconds + 2;
      int historyBars = (int)MathMax(MathMax(InpVrBars, InpVolAvgBars), sessionBars) + 5;
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, historyBars, d);
      if(got < InpVolAvgBars + 5) return false;

      //--- initialize optional profiles too: missing higher-timeframe history is neutral,
      //--- never an uninitialized step/bucket count.
      SProfile sess, vr, htf, weekly;
      CFVP_InitProfile(sess);
      CFVP_InitProfile(vr);
      CFVP_InitProfile(htf);
      CFVP_InitProfile(weekly);
      if(!BuildSessionProfile(d, got, sess)) return false;
      BuildProfileRange(vr, d, got, 1, (int)MathMin(InpVrBars, got - 1), InpVrBuckets);
      MqlRates dr[];
      int dgot = EA_Rates(ctx.symbol, PERIOD_D1, 0, InpHtfDays + 5, dr);
      if(dgot >= 5) BuildProfileRange(htf, dr, dgot, 1, (int)MathMin(InpHtfDays, dgot - 1), InpVrBuckets);

      //--- S1: the four key daily levels
      double lv[5];
      int    lvSet = KeyLevels(ctx.symbol, lv);
      if(lvSet <= 0) return false;

      //--- S5: the prior day's POC, for the retest setup
      double poc = PriorDayPoc(ctx.symbol);

      //--- S3: the weekly bias is measured against its own prior-week profile,
      //--- separate from the intraday execution profile.
      int bias = WeeklyBias(ctx.symbol, weekly);

      double best = -1.0;
      SSignalPlan p;
      for(int dir = +1; dir >= -1; dir -= 2)
      {
         if(bias != 0 && bias != dir) continue;      // "all intraday setups should then favour" that side
         p.Reset();
         if(PlanSignal(ctx, d, got, dir, lv, lvSet, poc, sess, vr, htf, bias, p) && p.score > best)
         {
            plan = p; best = p.score;
         }
      }
      if(plan.dir != 0)
         EA_Log(EA_LOG_EVENTS, StringFormat("%s: %s", ctx.symbol, plan.reason), true);
      return (plan.dir != 0);
   }

private:
   datetime m_lastPlanBar[EA_MAX_SYMBOLS];

   //+----------------------------------------------------------------+
   //| Profiles                                                         |
   //+----------------------------------------------------------------+
   //--- profile the bars [idxNewest .. idxOldest] (newest first, both inclusive)
   void BuildProfileRange(SProfile &pf, const MqlRates &d[], const int got, const int idxNewest, const int idxOldest, const int buckets)
   {
      pf.buckets = (int)MathMax(8, MathMin(CFVP_MAX_BUCKETS, buckets));
      pf.lo = 0.0; pf.hi = 0.0; pf.step = 0.0;
      for(int i = 0; i < pf.buckets; i++) pf.vol[i] = 0.0;
      int a = (int)MathMax(1, idxNewest);
      int b = (int)MathMin(idxOldest, got - 1);
      if(b < a) return;
      double lo = d[a].low, hi = d[a].high;
      for(int i = a; i <= b; i++)
      {
         if(d[i].low  < lo) lo = d[i].low;
         if(d[i].high > hi) hi = d[i].high;
      }
      if(!(hi > lo)) return;
      pf.lo = lo;
      pf.hi = hi;
      pf.step = (hi - lo) / (double)pf.buckets;
      if(pf.step <= 0.0) return;
      for(int i = a; i <= b; i++)
      {
         double v = (double)d[i].tick_volume;          // disclosed: MT5 has tick volume, not exchange volume
         if(v <= 0.0) continue;
         double span = d[i].high - d[i].low;
         int b1 = (int)MathFloor((d[i].low  - lo) / pf.step);
         int b2 = (int)MathFloor((d[i].high - lo) / pf.step);
         if(b1 < 0) b1 = 0;
         if(b1 >= pf.buckets) b1 = pf.buckets - 1;   // a zero-range bar at pf.hi belongs in the last bucket
         if(b2 < 0) b2 = 0;
         if(b2 >= pf.buckets) b2 = pf.buckets - 1;
         if(span <= 0.0) { pf.vol[b1] += v; continue; }
         int nb = b2 - b1 + 1;
         double each = v / (double)nb;
         for(int bb = b1; bb <= b2; bb++) pf.vol[bb] += each;
      }
   }

   //--- the session profile: the completed bars of the current server day
   bool BuildSessionProfile(const MqlRates &d[], const int got, SProfile &pf)
   {
      MqlDateTime st;
      TimeToStruct(TimeTradeServer(), st);
      st.hour = 0; st.min = 0; st.sec = 0;
      datetime todayStart = StructToTime(st);
      // At the first signal bar of a server day there may be no completed bar
      // from today yet. Do not manufacture a "session" profile from yesterday's
      // last bar; wait until at least one current-day signal bar has closed.
      if(got < 2 || d[1].time < todayStart) return false;
      int oldest = 1;
      for(int i = 1; i < got; i++)
      {
         if(d[i].time < todayStart) break;
         oldest = i;
      }
      BuildProfileRange(pf, d, got, 1, oldest, InpSessionBuckets);
      return (pf.step > 0.0 && pf.buckets > 0);
   }

   double AvgBucket(const SProfile &pf)
   {
      if(pf.buckets <= 0) return 0.0;
      double sum = 0.0;
      for(int i = 0; i < pf.buckets; i++) sum += pf.vol[i];
      return sum / (double)pf.buckets;
   }
   int BucketOf(const SProfile &pf, const double px)
   {
      if(pf.step <= 0.0 || pf.buckets <= 0 || px < pf.lo || px > pf.hi) return -1;
      int b = (int)MathFloor((px - pf.lo) / pf.step);
      if(b == pf.buckets && px <= pf.hi) b = pf.buckets - 1;   // inclusive profile maximum
      if(b < 0 || b >= pf.buckets) return -1;
      return b;
   }
   double BucketCenter(const SProfile &pf, const int b) { return pf.lo + ((double)b + 0.5) * pf.step; }
   bool IsHvn(const SProfile &pf, const int b)
   {
      double avg = AvgBucket(pf);
      return (b >= 0 && b < pf.buckets && avg > 0.0 && pf.vol[b] >= InpHvnFactor * avg);
   }
   bool IsLva(const SProfile &pf, const int b)
   {
      double avg = AvgBucket(pf);
      return (b >= 0 && b < pf.buckets && avg > 0.0 && pf.vol[b] <= InpLvaFactor * avg);
   }

   //--- "volume edges": the nearest HVA/LVA boundary in `dir` (above = +1, below = -1) from `from`
   double NearestEdge(const SProfile &pf, const double from, const int dir)
   {
      if(pf.step <= 0.0) return 0.0;
      int b = BucketOf(pf, from);
      if(b < 0) return 0.0;
      int step = (dir > 0) ? +1 : -1;
      for(int i = b; i >= 0 && i < pf.buckets; i += step)
      {
         int nb = i + step;
         if(nb < 0 || nb >= pf.buckets) break;
         //--- the boundary between a high-value block and the quiet beyond it
         if(IsHvn(pf, i) && IsLva(pf, nb)) return (dir > 0) ? (pf.lo + (double)nb * pf.step) : (pf.lo + (double)i * pf.step);
         if(IsLva(pf, i) && IsHvn(pf, nb)) return (dir > 0) ? (pf.lo + (double)nb * pf.step) : (pf.lo + (double)i * pf.step);
      }
      //--- no clean HVN/LVA transition in that direction: the extreme of the range
      return 0.0;
   }

   bool AtProfileEdge(const double level, const SProfile &sess, const SProfile &vr, const SProfile &htf)
   {
      if(level <= 0.0) return false;
      double tol = InpEdgeTolPct / 100.0 * level;
      double eUp = NearestEdge(sess, level, +1);
      double eDn = NearestEdge(sess, level, -1);
      double eUp2 = NearestEdge(vr, level, +1);
      double eDn2 = NearestEdge(vr, level, -1);
      if(eUp  > 0.0 && MathAbs(eUp  - level) <= tol) return true;
      if(eDn  > 0.0 && MathAbs(eDn  - level) <= tol) return true;
      if(eUp2 > 0.0 && MathAbs(eUp2 - level) <= tol) return true;
      if(eDn2 > 0.0 && MathAbs(eDn2 - level) <= tol) return true;
      //--- the higher timeframe's own edges ("higher timeframes are used to identify
      //--- long-term value areas and edges")
      if(htf.step > 0.0)
      {
         double eH1 = NearestEdge(htf, level, +1);
         double eH2 = NearestEdge(htf, level, -1);
         if(eH1 > 0.0 && MathAbs(eH1 - level) <= tol) return true;
         if(eH2 > 0.0 && MathAbs(eH2 - level) <= tol) return true;
      }
      return false;
   }

   //--- "the next shelf - edge-to-edge targeting": the first visible-range HVA in path;
   //--- target its edge facing the entry, not its bucket centre.
   double NextShelf(const SProfile &pf, const double from, const int dir)
   {
      if(pf.step <= 0.0) return 0.0;
      int b = BucketOf(pf, from);
      if(b < 0) return 0.0;
      double avg = AvgBucket(pf);
      if(avg <= 0.0) return 0.0;
      int step = (dir > 0) ? +1 : -1;
      for(int i = b + step; i >= 0 && i < pf.buckets; i += step)
      {
         if(pf.vol[i] >= InpHvnFactor * avg)
            // Target the entry-facing edge of the first high-volume bucket.
            return (dir > 0) ? (pf.lo + (double)i * pf.step)
                             : (pf.lo + (double)(i + 1) * pf.step);
      }
      return 0.0;
   }

   //--- "the high value node" the stop may sit beyond
   double HvnBeyond(const SProfile &pf, const double from, const int dir)
   {
      if(pf.step <= 0.0 || pf.buckets <= 0) return 0.0;
      int b = BucketOf(pf, from);
      if(b < 0) return 0.0;
      // The structural stop searches against the trade: below a long, above a short.
      int step = (dir > 0) ? -1 : +1;
      int node = -1;
      for(int i = b; i >= 0 && i < pf.buckets; i += step)
      {
         if(IsHvn(pf, i)) { node = i; break; }
      }
      if(node < 0) return 0.0;
      // Walk through the contiguous node and use its far edge, not the edge facing entry.
      int far = node;
      for(int i = node + step; i >= 0 && i < pf.buckets; i += step)
      {
         if(!IsHvn(pf, i)) break;
         far = i;
      }
      return (dir > 0) ? (pf.lo + (double)far * pf.step)
                       : (pf.lo + (double)(far + 1) * pf.step);
   }

   //+----------------------------------------------------------------+
   //| S1: ONH / ONL / PDH / PDL                                       |
   //+----------------------------------------------------------------+
   void OvernightWindow(const datetime now, datetime &onStart, datetime &onEnd)
   {
      MqlDateTime st;
      TimeToStruct(now, st);
      int nowMinute = st.hour * 60 + st.min;
      st.hour = 0; st.min = 0; st.sec = 0;
      datetime todayStart = StructToTime(st);
      int startMinute = InpOnStartHour * 60 + InpOnStartMin;
      int endMinute = InpOnEndHour * 60 + InpOnEndMin;
      if(startMinute > endMinute)
      {
         // Overnight window: after start use today's window; before start use
         // yesterday's start and today's end.
         if(nowMinute >= startMinute)
         {
            onStart = todayStart + (datetime)(startMinute * 60);
            onEnd = todayStart + (datetime)86400 + (datetime)(endMinute * 60);
         }
         else
         {
            onStart = todayStart - (datetime)86400 + (datetime)(startMinute * 60);
            onEnd = todayStart + (datetime)(endMinute * 60);
         }
      }
      else if(nowMinute < startMinute)
      {
         // Daytime window has not started yet; use the previous completed one.
         onStart = todayStart - (datetime)86400 + (datetime)(startMinute * 60);
         onEnd = todayStart - (datetime)86400 + (datetime)(endMinute * 60);
      }
      else
      {
         onStart = todayStart + (datetime)(startMinute * 60);
         onEnd = todayStart + (datetime)(endMinute * 60);
      }
      if(onEnd > now) onEnd = now;    // the selected window may still be running
   }

   int KeyLevels(const string sym, double &lv[])
   {
      int n = 0;
      //--- prior day high / low, from the last completed daily bar
      MqlRates dd[];
      int dg = EA_Rates(sym, PERIOD_D1, 1, 1, dd);
      if(dg >= 1)
      {
         lv[n] = dd[0].high; n++;
         lv[n] = dd[0].low;  n++;
      }
      //--- overnight high / low: closed M1 bars in the configured server-clock window
      datetime now = TimeTradeServer();
      datetime onStart = 0, onEnd = 0;
      OvernightWindow(now, onStart, onEnd);
      double onh = 0.0, onl = 0.0;
      //--- minute bars keep ONH/ONL correct even when the signal frame is H4;
      //--- a half-open [start,end) window excludes the midnight bar at the end.
      int seconds = PeriodSeconds(PERIOD_M1);
      if(seconds <= 0) return n;
      int barsPerDay = (int)MathCeil(86400.0 / (double)seconds);
      int need = 2 * barsPerDay + 5;
      MqlRates overnight[];
      int onGot = EA_Rates(sym, PERIOD_M1, 0, need, overnight);
      for(int i = 1; i < onGot; i++)
      {
         datetime t = overnight[i].time;
         if(t < onStart || t >= onEnd) continue;
         if(onh == 0.0 || overnight[i].high > onh) onh = overnight[i].high;
         if(onl == 0.0 || overnight[i].low  < onl) onl = overnight[i].low;
      }
      if(onh > 0.0) { lv[n] = onh; n++; }
      if(onl > 0.0) { lv[n] = onl; n++; }
      return n;
   }

   //--- "the prior day's POC" - the busiest bucket of the previous completed broker D1 bar
   double PriorDayPoc(const string sym)
   {
      // Anchor to the broker's previous completed D1 bar, not calendar yesterday:
      // weekends, holidays, and broker server-day boundaries otherwise truncate POC.
      MqlRates days[];
      int dg = EA_Rates(sym, PERIOD_D1, 0, 3, days);
      if(dg < 2 || days[0].time <= days[1].time) return 0.0;
      datetime priorStart = days[1].time;
      int d1Seconds = PeriodSeconds(PERIOD_D1);
      if(d1Seconds <= 0) return 0.0;
      datetime priorEnd = priorStart + (datetime)d1Seconds;
      if(days[0].time > priorStart && days[0].time < priorEnd) priorEnd = days[0].time;
      MqlRates h1[];
      int periodSeconds = PeriodSeconds(g_eaIndTf);
      if(periodSeconds <= 0) return 0.0;
      int need = (int)MathCeil((double)(TimeTradeServer() - priorStart) / (double)periodSeconds) + 5;
      if(need < 5) need = 5;
      if(need > 10000) need = 10000;
      int gg = EA_Rates(sym, g_eaIndTf, 0, need, h1);
      if(gg < 5) return 0.0;
      int from = 0, to = 0;
      for(int i = 1; i < gg; i++)
      {
         if(h1[i].time >= priorStart && h1[i].time < priorEnd)
         {
            if(from == 0) from = i;
            to = i;
         }
      }
      if(from == 0 || to == 0) return 0.0;
      SProfile pf;
      BuildProfileRange(pf, h1, gg, from, to, InpVrBuckets);   // the bars are ordered newest first
      if(pf.step <= 0.0) return 0.0;
      int best = 0;
      for(int b = 1; b < pf.buckets; b++)
         if(pf.vol[b] > pf.vol[best]) best = b;
      return BucketCenter(pf, best);
   }

   //+----------------------------------------------------------------+
   //| S3: the weekly reversal candle at a volume edge                 |
   //+----------------------------------------------------------------+
   int WeeklyBias(const string sym, SProfile &weekly)
   {
      MqlRates w[];
      // w[0] is the latest completed week; the following N bars build its
      // independent context profile and volume baseline.
      int got = EA_Rates(sym, PERIOD_W1, 1, InpBiasWeeks + 1, w);
      if(got < InpBiasWeeks + 1) return 0;
      BuildProfileRange(weekly, w, got, 1, InpBiasWeeks, InpVrBuckets);
      if(weekly.step <= 0.0) return 0;
      double rng = w[0].high - w[0].low;
      if(rng <= 0.0) return 0;
      double avg = 0.0;
      for(int i = 1; i <= InpBiasWeeks; i++) avg += (double)w[i].tick_volume;
      avg /= (double)InpBiasWeeks;
      if(avg <= 0.0 || (double)w[0].tick_volume < avg) return 0;       // "high volume"
      double lower = MathMin(w[0].open, w[0].close) - w[0].low;
      double upper = w[0].high - MathMax(w[0].open, w[0].close);
      double edgeTol = InpEdgeTolPct / 100.0 * w[0].close;
      double eLow  = NearestEdge(weekly, w[0].low,  -1);
      double eHigh = NearestEdge(weekly, w[0].high, +1);
      bool atLowEdge  = (eLow  > 0.0 && MathAbs(w[0].low  - eLow)  <= edgeTol);
      bool atHighEdge = (eHigh > 0.0 && MathAbs(w[0].high - eHigh) <= edgeTol);
      //--- "a high volume bottom-wick reversal candle at a volume edge" -> long bias
      if(lower >= rng * InpBiasWickFrac && w[0].close >= w[0].open && atLowEdge)  return +1;
      //--- the mirror the document implies with "and vice versa"
      if(upper >= rng * InpBiasWickFrac && w[0].close <= w[0].open && atHighEdge) return -1;
      return 0;
   }

   //+----------------------------------------------------------------+
   //| S2 + S4 + S5: the signal candle, the entry, the stop, the shelf |
   //+----------------------------------------------------------------+
   bool PlanSignal(const SEAContext &ctx, const MqlRates &d[], const int got, const int dir,
                   const double &lv[], const int lvSet, const double poc,
                   const SProfile &sess, const SProfile &vr, const SProfile &htf, const int bias,
                   SSignalPlan &p)
   {
      //--- "a high volume signal candle ... closing in the trade direction"
      double rng = d[1].high - d[1].low;
      if(rng <= 0.0) return false;
      bool dirBody = (dir > 0) ? (d[1].close > d[1].open) : (d[1].close < d[1].open);
      if(!dirBody) return false;
      double body = MathAbs(d[1].close - d[1].open);
      if(body < rng * InpMinSignalBodyPct / 100.0) return false;
      double avgVol = 0.0;
      for(int i = 2; i <= InpVolAvgBars + 1 && i < got; i++) avgVol += (double)d[i].tick_volume;
      avgVol /= (double)InpVolAvgBars;
      if(avgVol <= 0.0 || (double)d[1].tick_volume < InpVolFactor * avgVol) return false;
      //--- "a visible wick rejecting the area"
      double wick = (dir > 0) ? (MathMin(d[1].open, d[1].close) - d[1].low)
                              : (d[1].high - MathMax(d[1].open, d[1].close));
      if(wick < rng * InpWickFrac) return false;

      //--- The standard setup must find a swept key level that is also a profile edge.
      //--- Check all four: an earlier non-edge level must not mask a later valid one.
      double level = 0.0;
      double bestLevelGap = 1.0e100;
      bool atEdge = false;
      for(int i = 0; i < lvSet; i++)
      {
         double l = lv[i];
         if(l <= 0.0) continue;
         bool swept = (dir > 0) ? (d[1].low < l && d[1].close > l) : (d[1].high > l && d[1].close < l);
         if(!swept || !AtProfileEdge(l, sess, vr, htf)) continue;
         //--- if a wide signal sweeps several levels, use the closest valid context level
         double gap = MathAbs(d[1].close - l);
         if(gap < bestLevelGap) { level = l; bestLevelGap = gap; atEdge = true; }
      }
      bool isPoc = false;
      bool pocOk = false;
      //--- Standard edge setups win when present; the named POC branch is considered
      //--- only when none qualifies. It substitutes for the generic key-level/edge
      //--- confluences, but still needs rejection plus a
      //--- qualifying prior-day directional breakout or ATR-sized trend.
      if(level <= 0.0 && InpUsePocRetest && poc > 0.0)
      {
         bool swept = (dir > 0) ? (d[1].low < poc && d[1].close > poc) : (d[1].high > poc && d[1].close < poc);
         if(swept && PriorTrendDay(ctx, dir))
         {
            level = poc;
            isPoc = true;
            pocOk = true;
         }
      }
      if(level <= 0.0 || (!atEdge && !isPoc)) return false;

      //--- S4: "entry after the signal candle closes at the volume edge", or the
      //--- volatility-based retrace limit when the wick is long
      bool retrace = (InpUseWickRetrace && wick >= rng * InpLongWickFrac);
      double entry = 0.0;
      if(retrace)
      {
         // Retrace 50-80% of the actual rejection wick from the candle body edge;
         // do not include the candle body in the measured wick distance.
         double bodyLo = MathMin(d[1].open, d[1].close);
         double bodyHi = MathMax(d[1].open, d[1].close);
         entry = (dir > 0) ? (bodyLo - InpRetraceFrac * wick)
                           : (bodyHi + InpRetraceFrac * wick);
      }
      else
      {
         entry = (dir > 0) ? ctx.ask : ctx.bid;
      }
      if(entry <= 0.0) return false;

      //--- The source allows a stop beyond the signal wick or an HVN edge; use
      //--- the session profile as the primary execution profile for that HVN fallback.
      double hvn = HvnBeyond(sess, entry, dir);
      double far = (dir > 0) ? MathMin(d[1].low, (hvn > 0.0 ? hvn : d[1].low))
                             : MathMax(d[1].high, (hvn > 0.0 ? hvn : d[1].high));
      double stop = (dir > 0) ? far - InpStopBufferAtr * ctx.atr : far + InpStopBufferAtr * ctx.atr;
      if(stop <= 0.0) return false;
      if(dir > 0 && !(stop < entry)) return false;
      if(dir < 0 && !(stop > entry)) return false;
      double risk = MathAbs(entry - stop);
      if(risk <= 0.0) return false;
      if(risk > entry * InpMaxStopPct / 100.0) return false;
      // A retrace that has already crossed its invalidation is not a valid limit entry.
      if(retrace && ((dir > 0 && ctx.bid <= stop) || (dir < 0 && ctx.ask >= stop))) return false;

      //--- The POC setup targets the prior-day extreme; do not silently replace
      //--- that target with a generic shelf if the stated objective is unavailable
      //--- or too close. Standard setups take the nearest shelf, and reject it if
      //--- it is below the configured reward floor rather than targeting through it.
      double tgt = 0.0;
      string targetType = "";
      if(pocOk)
      {
         MqlRates dd[];
         int dg = EA_Rates(ctx.symbol, PERIOD_D1, 1, 1, dd);
         if(dg < 1) return false;
         tgt = (dir > 0) ? dd[0].high : dd[0].low;
         targetType = "prior-day extreme";
         if(dir > 0 && !(tgt > entry + InpMinTargetR * risk)) return false;
         if(dir < 0 && !(tgt < entry - InpMinTargetR * risk)) return false;
      }
      else
      {
         double shelf = NextShelf(vr, entry, dir);
         if(shelf > 0.0)
         {
            if(dir > 0 && !(shelf > entry + InpMinTargetR * risk)) return false;
            if(dir < 0 && !(shelf < entry - InpMinTargetR * risk)) return false;
            tgt = shelf;
            targetType = "nearest shelf";
         }
         else
         {
            tgt = (dir > 0) ? entry + InpTargetR * risk : entry - InpTargetR * risk;
            targetType = "fixed-R fallback";
         }
      }
      if(dir > 0 && !(tgt > entry)) return false;
      if(dir < 0 && !(tgt < entry)) return false;

      p.dir      = dir;
      p.entry    = entry;
      p.stop     = stop;
      p.target   = tgt;
      p.riskDist = risk;
      p.barsAgo  = 1;
      p.isLimit  = retrace;
      if(retrace) p.expiry = TimeTradeServer() + (datetime)(InpLimitBars * PeriodSeconds(g_eaIndTf));
      p.score = 82.0;
      if(bias == dir) p.score += 3.0;                    // the weekly candle agrees
      if(retrace)     p.score += 3.0;                    // the retrace limit buys a better price
      if(isPoc)       p.score += 1.0;                    // the named POC setup
      p.reason = StringFormat("%s %s: %s at %.5f swept and closed back (wick %.0f%% of range on %.1fx volume), %s, stop %.5f, %s entry, %s target %.5f",
                              (isPoc ? "POC retest" : "volume edge"),
                              (dir > 0 ? "LONG" : "SHORT"),
                              (isPoc ? "prior-day POC" : "key daily level"),
                              level, wick / rng * 100.0, (double)d[1].tick_volume / avgVol,
                              (isPoc ? "named setup exception" : "profile edge confirmed"),
                              stop, (retrace ? "retrace-limit" : "market"), targetType, tgt);
      return true;
   }

   //--- The source says "a breakout or trend day": either directional condition qualifies.
   bool PriorTrendDay(const SEAContext &ctx, const int dir)
   {
      MqlRates dd[];
      int dg = EA_Rates(ctx.symbol, PERIOD_D1, 1, 2, dd);
      if(dg < 1) return false;
      double body = (dir > 0) ? (dd[0].close - dd[0].open) : (dd[0].open - dd[0].close);
      bool trend = (body > 0.0 && ctx.atrD1 > 0.0 && body >= InpTrendDayAtr * ctx.atrD1);
      bool breakout = false;
      if(dg >= 2)
         breakout = (dir > 0) ? (dd[0].close > dd[1].high) : (dd[0].close < dd[1].low);
      return (trend || breakout);
   }


};

CCfVolumeProfile g_cfVolumeProfile;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!g_cfVolumeProfile.InputsValid()) return INIT_PARAMETERS_INCORRECT;
   return EA_Init(&g_cfVolumeProfile);
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
