//+------------------------------------------------------------------+
//|                    EA_CF_OrderFlowStrategy.mq5                    |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| "Order Flow Strategy" - Chart Fanatics (Yosh, $2M+ payouts)       |
//| Card    : chartfanatics/todos/order-flow-strategy.md (#28)        |
//| Source  : chartfanatics/glimpse/hvyf6frvCcA.md                    |
//| Magic   : 3231                                                    |
//|                                                                  |
//| The system in one paragraph: four criteria - MARKET-GENERATED     |
//| LEVELS (previous day high/low, the overnight range 9 PM-9:29 AM   |
//| EST, a 30-minute opening range), the VOLUME PROFILE (the 70%      |
//| value area and its low volume nodes), BIG TRADES (orders above a  |
//| size threshold) and the DELTA PROFILE (absorption, trapped        |
//| orders) - build two models.  In a RANGE, trade the value-area     |
//| edges aggressively with small size, add only on confirmation,     |
//| target the midpoint first and then the opposite edge, and move    |
//| the stop to break-even once the first target has paid.  In a      |
//| TREND, enter pullbacks into low volume nodes with big trades or   |
//| absorption confirming, and sell INTO breakout highs (where the    |
//| breakout traders enter) instead of chasing them.  Two of the four |
//| criteria make a trade valid; three or four make it A+.  Trade the |
//| first 1-3 hours after the open only, 2-3 trades a day, never the  |
//| middle of a range, never against momentum, and never let a winner |
//| go red.                                                           |
//|                                                                  |
//| [interpretation] - what a MetaTrader EA cannot do, and what it    |
//| does instead, always labelled:                                     |
//|   * big trades: the document filters a real order feed (75 lots   |
//|     for NQ / 200 for ES via Sierra Charts or Moto Wave).  MT5      |
//|     gives no individual order sizes, so the proxy is a bar whose   |
//|     tick volume is this many times the window median and which     |
//|     touches the level (InpBigTradeMult).                           |
//|   * delta: ask-vs-bid transaction counts are not available; the    |
//|     engine's delta stand-in is body-directional tick volume, and   |
//|     absorption is read as a heavy bar that tests the level and     |
//|     closes back on the defended side (the document's "aggressive   |
//|     sellers hit the bid but price doesn't fall").                  |
//|   * volume profile: built from bar tick volume in price bins -     |
//|     the same proxy the family's volume-profile EAs use - because   |
//|     MT5 exposes no traded-volume-at-price feed.                    |
//|   * the 75-lot / 200-lot thresholds, the thin-bin cut, the bar     |
//|     counts, the edge band, the chase/pullback tolerances, the      |
//|     delta-lean cut and the stop buffers are engineering numbers    |
//|     the document does not state; all are inputs.                   |
//|   * the DOM speed read ("if orders are moving fast, wait for       |
//|     slowdown") has no platform signal and is not faked; the        |
//|     momentum gate is the mechanical half of it.                    |
//|   * NQ is traded on 2-minute charts and ES on 3-minute charts; the |
//|     engine runs one signal timeframe per EA, so M2 is used for     |
//|     both (the NQ frame) and the ES difference is disclosed.        |
//|   * averaging UP after confirmation is the document's add-on; the  |
//|     engine holds one position per symbol, so the confirmation      |
//|     instead banks the 1R partial and moves the stop to break-even. |
//|                                                                    |
//| Rule -> code sync (see tests/test_chartfanatics_sync.py):          |
//|   R1  four criteria foundation    -> SLevels + BuildProfile +      |
//|                                      BigTrades() + Absorption()    |
//|   R2  at least two of four        -> CriteriaCount() / InpMinCriteria
//|   R3  3-4 alignments = A+         -> InpAPlusCriteria / LotsMultiplier()
//|   R4  market-generated levels     -> SigRangeForDay (overnight, ORB)|
//|                                      + D1 previous high/low        |
//|   R5  70% value area              -> InpValueAreaPct / BuildProfile()
//|   R6  low volume nodes            -> ThinZone()                    |
//|   R7  big trades                  -> BigTrades() (tick-volume proxy)|
//|   R8  delta / absorption          -> DeltaLean() / Absorption()    |
//|   R9  range model                 -> RangePlan()                   |
//|   R10 trend model pullback        -> TrendPlan()                   |
//|   R11 sell into breakout highs    -> FadePlan()                    |
//|   R12 never the middle            -> MiddleOfRange()               |
//|   R13 never chase momentum        -> Chasing()                     |
//|   R14 first 1-3 hours post-open   -> session window in Configure() |
//|   R15 2-3 trades per day          -> InpMaxTradesPerDay            |
//|   R16 never let a winner go red   -> partial1AtR + breakEvenAtR    |
//|   R17 trim at highs / trail       -> partial1Pct + trailAtR +      |
//|                                      StructureExit()              |
//|   R18 3-4R / 2R / 1.5-2R ladders  -> InpRangeMinRR, InpTrendMinRR  |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "Chart Fanatics Order Flow Strategy - four criteria (levels, value area / LVN, big trades, delta absorption) into a range model and a trend model, first 1-3 hours of the session only"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade     = "US100,US500";      // NQ and ES analogues
input ulong             InpMagicNumber        = 3231;               // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct            = 0.35;               // Aggressive entries are small size (doc)
input int               InpStage              = 5;                  // 5-Stage framework stage (5 = policy off)
input double            InpMaxSpreadPoints    = 3.0;                // Spread gate in points (0 = off)
input double            InpDailyLossPct       = 1.50;               // "accept your risk before the day starts"
input double            InpWeeklyLossPct      = 3.0;
input double            InpTotalDdPct         = 8.0;
input int               InpServerGmtOffset    = 2;                  // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel           = EA_LOG_EVENTS;      // Log verbosity
input double            InpCommissionPerLotRT = 0.0;                // Round-turn commission per lot
input double            InpMaxCostR           = 0.12;               // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;               // Write the engine evidence ledger CSV
//--- the session (London clock; 14:30 London = the 09:30 ET open all year)
input int    InpOvernightFromMin = 120;    // 02:00 London = 21:00 ET - the overnight window opens
input int    InpOvernightToMin   = 869;    // 14:29 London = 09:29 ET - the overnight high/low
input int    InpOrbFromMin       = 870;    // 14:30 London = 09:30 ET - opening range start
input int    InpOrbToMin         = 900;    // 15:00 London = 10:00 ET - the first 30 minutes
input int    InpEntryToMin       = 1050;   // 17:30 London = 12:30 ET - first 1-3 hours post-open
input bool   InpUseOrb           = true;   // The 30-minute opening range is one of the levels
input int    InpMaxTradesPerDay  = 3;      // "2-3 trades per day"
//--- the volume profile (criterion 2)
input int    InpProfileBins      = 40;     // Price bins for the tick-volume profile
input double InpValueAreaPct     = 0.70;   // "where 70% of transactions occur"
input int    InpProfileBars      = 420;    // Bars of the developing-day reference (M2: ~1 day)
input double InpThinBinPct       = 0.35;   // [interpretation] a bin under this share of the mean is thin
//--- big trades (criterion 3) -- a tick-volume proxy, labelled
input double InpBigTradeMult     = 2.50;   // [interpretation] bar volume vs the window median
input int    InpBigTradeLookback = 12;     // Bars searched for the big-trade print
input double InpLevelTolAtr      = 0.20;   // "at the level" tolerance for the big-trade test
//--- delta / absorption (criterion 4) -- a body-volume proxy, labelled
input int    InpDeltaBars        = 20;     // Bars of cumulative body-directional volume
input double InpDeltaLean        = 0.20;   // [interpretation] |ask-bid| skew that counts as leaning
input double InpAbsorbVolMult    = 1.80;   // [interpretation] a heavy bar vs the window median
input double InpAbsorbWickPct    = 0.50;   // The close must be back in the defended half
//--- criteria / models / sizing
input int    InpMinCriteria      = 2;      // "at least two confirmations"
input int    InpAPlusCriteria    = 3;      // "3-4 alignments create A+ setups"
input double InpBCSizeMult       = 0.50;   // [interpretation] B/C size vs the A+ size
input bool   InpTradeRange       = true;   // Model one: range-bound edge trading
input bool   InpTradeTrend       = true;   // Model two: trending pullbacks into LVNs
input double InpEdgeBandPct      = 0.25;   // "trade only the edges" - band as a share of VA height
input int    InpBreakBars        = 12;     // Bars a value break stays actionable
input double InpAcceptBody       = 0.55;   // "accepting higher prices" - break bar body share
//--- stops / targets / management
input double InpRangeMinRR       = 2.00;   // Range model: midpoint first, then the opposite edge
input double InpTrendMinRR       = 1.50;   // Trend days: "accept tighter ratios (1.5-2 R)"
input double InpMinStopAtr       = 0.15;   // Reject stops tighter than this
input int    InpStopBufferTicks  = 2;      // Buffer beyond the level (keeps the stop off the wick)
input double InpStopBufferAtr    = 0.08;
input double InpPartial1R        = 1.00;   // "move stop to break-even after the first target hits"
input double InpPartialPct       = 50.0;   // Trim at the highs: 1-2 of 5 contracts
input double InpBreakEvenR       = 1.00;   // "never let a winner go red"
input double InpTrailAtR         = 2.00;   // Trail the remaining position
input double InpTrailDistanceR   = 0.60;
input double InpStructureExitR   = 1.00;   // Exit signal: the trend prints a lower high (or mirror)
//--- no-chase gate ("do not enter while price is aggressively moving")
input double InpChaseAtr         = 1.20;   // A 4-bar move this large is a chase
input double InpPullbackAtr      = 0.15;   // Unless a pullback this deep has already printed

//+------------------------------------------------------------------+
struct SVolProfile
{
   double poc, val, vah;
   double lo, size;
   int    nb, pocBin, valBin, vahBin;
   bool   ok;
};

//+------------------------------------------------------------------+
struct SLevels
{
   double pdh, pdl;                  // previous day high / low
   double onHi, onLo;                // overnight range (9 PM-9:29 AM ET)
   double orbHi, orbLo;              // 30-minute opening range
   bool   havePd, haveOn, haveOrb;
};

//+------------------------------------------------------------------+
struct SCfCandidate
{
   int    dir;
   double entry, stop, target, risk;
   int    crit;
   string why;
};

//+------------------------------------------------------------------+
class CCfOrderFlowStrategy : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_ORDER_FLOW_STRATEGY";
      cfg.sourceDoc             = "chartfanatics/glimpse/hvyf6frvCcA.md (card #28)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M2;      // NQ's 2-minute frame (ES runs 3-minute: disclosed)
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = InpWeeklyLossPct;
      cfg.totalDdPct            = InpTotalDdPct;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 120;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = false;
      cfg.newsFilter            = false;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_order_flow_ledger.csv";
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.logLevel              = InpLogLevel;
      //--- "only trade the first 1-3 hours": the 09:30 ET open in the London frame,
      //--- ending at the input's last-entry minute (default 17:30 London = 12:30 ET)
      cfg.sessionStartHour = InpOrbFromMin / 60;  cfg.sessionStartMin = InpOrbFromMin % 60;
      cfg.sessionEndHour   = InpEntryToMin / 60;  cfg.sessionEndMin   = InpEntryToMin % 60;
      cfg.noTradeAfterHour = InpEntryToMin / 60;  cfg.noTradeAfterMin = InpEntryToMin % 60;
      //--- "target the midpoint first, then the opposite edge" / "move the stop to
      //--- break-even after the first target hits" / "trim 1-2 of 5 contracts at highs"
      cfg.partial1AtR   = InpPartial1R;
      cfg.partial1Pct   = InpPartialPct;
      cfg.breakEvenAtR  = InpBreakEvenR;
      cfg.trailAtR      = InpTrailAtR;
      cfg.trailDistanceR = InpTrailDistanceR;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   void OnInitStrategy()
   {
      m_lastCrit = 0;
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "order flow armed: %s, M2, 14:30-17:30 London (09:30-12:30 ET), max %d trades/day, %.2f%% risk, min %d of 4 criteria (A+ at %d)",
             InpSymbolsToTrade, InpMaxTradesPerDay, InpRiskPct, InpMinCriteria, InpAPlusCriteria), true);
      EA_Log(EA_LOG_EVENTS, "criteria: generated levels (overnight 02:00-14:29 London, ORB 14:30-15:00, D1 high/low) + 70% value area / LVNs + big-trade tick-volume proxy + delta absorption proxy", true);
   }

   //--- A+ 3-4 alignments vs B/C: the document's own sizing ladder
   double LotsMultiplier(SEAContext &ctx)
   {
      return (m_lastCrit >= InpAPlusCriteria) ? 1.0 : InpBCSizeMult;
   }

   //-------------------------------------------------------------------
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession || ctx.atr <= 0.0) return false;
      if(!InpTradeRange && !InpTradeTrend) return false;

      SLevels lv;
      if(!LoadLevels(ctx.symbol, lv)) return false;
      SVolProfile prof;
      double binVol[], meanBin;
      if(!BuildProfile(ctx.symbol, prof, binVol, meanBin)) return false;

      SCfCandidate best;
      best.dir = 0;

      //--- "never trade the middle of ranges": inside the value area, only the edges
      if(MiddleOfRange(ctx, prof)) return false;

      //--- model one: the range-bound edge trade
      if(InpTradeRange)
      {
         SCfCandidate c;
         if(RangePlan(ctx, lv, prof, binVol, meanBin, c))
         {
            if(!Chasing(ctx)) best = c;
         }
      }

      //--- model two, first half: the trap - a wick through a market-generated
      //--- level that closes back inside is where the breakout traders are stuck
      //--- ("sell into breakout highs ... where breakout traders enter")
      if(best.dir == 0 && InpTradeTrend)
      {
         SCfCandidate c;
         if(FadePlan(ctx, lv, prof, c))
         {
            if(!Chasing(ctx)) best = c;
         }
      }

      //--- model two, second half: trend pullbacks into low volume nodes
      if(best.dir == 0 && InpTradeTrend)
      {
         SCfCandidate c;
         if(TrendPlan(ctx, lv, prof, binVol, meanBin, c))
         {
            if(!Chasing(ctx)) best = c;
         }
      }

      if(best.dir == 0) return false;
      if(best.crit < InpMinCriteria) return false;

      plan.dir      = best.dir;
      plan.entry    = (best.dir > 0) ? ctx.ask : ctx.bid;
      plan.stop     = best.stop;
      plan.target   = best.target;
      plan.riskDist = best.risk;
      plan.score    = best.crit;
      plan.reason   = best.why;
      plan.isLimit  = false;

      m_lastCrit = best.crit;
      return (best.risk > 0.0 && MathAbs(best.target - best.entry) > 0.0);
   }

   //-------------------------------------------------------------------
   void Manage(SEAContext &ctx)
   {
      //--- the document's own exit signal on the trend model: "watching for
      //--- lower highs (exit signal)" - the trail is the engine's, this closes
      //--- the position when the structure itself flips.  [interpretation]: the
      //--- document only names the signal; the three-bar reading (and its mirror
      //--- for shorts) is ours, and it only acts once the trade is at 1R+
      if(!InpTradeTrend) return;
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 1, 4, r);
      if(got < 3) return;

      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong ticket = PositionGetTicket(p);
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

         double open  = PositionGetDouble(POSITION_PRICE_OPEN);
         double risk  = CachedRisk(ticket);
         if(risk <= 0.0) continue;
         double mid   = PositionGetDouble(POSITION_PRICE_CURRENT);
         long   type  = PositionGetInteger(POSITION_TYPE);
         bool   isLong = (type == POSITION_TYPE_BUY);

         //--- only once the trade is worth protecting
         double rNow = ((isLong) ? (mid - open) : (open - mid)) / risk;
         if(rNow < InpStructureExitR) continue;

         //--- a lower high (or the mirror) is the trend's own warning
         bool flip = (isLong) ? (r[0].high < r[1].high && r[1].high < r[2].high)
                              : (r[0].low  > r[1].low  && r[1].low  > r[2].low);
         if(flip)
            g_eaExec.Close(ticket, "structure flip after 1R - the document's lower-highs exit");
      }
   }

private:
   int m_lastCrit;

   //-------------------------------------------------------------------
   // calendar helpers
   //-------------------------------------------------------------------
   datetime DayStart(const datetime clockTime)
   {
      MqlDateTime d;
      TimeToStruct(clockTime, d);
      d.hour = 0; d.min = 0; d.sec = 0;
      return StructToTime(d);
   }

   double CachedRisk(const ulong ticket)
   {
      //--- the engine persists the planned risk per ticket while the trade lives
      double v = GlobalVariableCheck(EA_RiskKey(ticket)) ? GlobalVariableGet(EA_RiskKey(ticket)) : 0.0;
      if(v > 0.0) return v;
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      if(sl > 0.0) return MathAbs(open - sl);
      return 0.0;
   }

   //-------------------------------------------------------------------
   // the four criteria
   //-------------------------------------------------------------------
   bool LoadLevels(const string sym, SLevels &lv)
   {
      lv.pdh = 0.0; lv.pdl = 0.0; lv.onHi = 0.0; lv.onLo = 0.0; lv.orbHi = 0.0; lv.orbLo = 0.0;
      lv.havePd = false; lv.haveOn = false; lv.haveOrb = false;

      MqlRates d[];
      int got = EA_Rates(sym, PERIOD_D1, 1, 2, d);          // index 0 = yesterday
      if(got >= 1 && d[0].high > 0.0 && d[0].low > 0.0)
      {
         lv.pdh = d[0].high; lv.pdl = d[0].low; lv.havePd = true;
      }

      int bars = 0;
      lv.haveOn = SigRangeForDay(sym, g_eaIndTf, InpOvernightFromMin, InpOvernightToMin, 0,
                                 lv.onHi, lv.onLo, bars);
      if(InpUseOrb)
         lv.haveOrb = SigRangeForDay(sym, g_eaIndTf, InpOrbFromMin, InpOrbToMin, 0,
                                     lv.orbHi, lv.orbLo, bars);
      return (lv.havePd || lv.haveOn || lv.haveOrb);
   }

   //--- the 70% value area from the developing-day tick-volume profile; the
   //--- bin volumes come back for the low-volume-node test
   bool BuildProfile(const string sym, SVolProfile &out, double &binVol[], double &meanBin)
   {
      out.ok = false; meanBin = 0.0;
      if(InpProfileBins < 8) return false;

      MqlRates r[];
      int got = EA_Rates(sym, g_eaIndTf, 0, InpProfileBars + 2, r);
      if(got < 30) return false;

      //--- the reference window: the overnight window onwards (the developing day)
      datetime winStart = DayStart(EA_ClockNow()) + (datetime)(InpOvernightFromMin * 60);
      int fromBar = -1;
      for(int i = got - 1; i >= 0; i--)
      {
         if(EA_BarClockTime(r[i].time) < winStart) break;
         fromBar = i;
      }
      if(fromBar < 0 || got - fromBar < 30) fromBar = 0;    // fallback: the whole fetch

      double hi = -DBL_MAX, lo = DBL_MAX;
      for(int i = fromBar; i < got; i++)
      { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }
      if(hi <= lo) return false;

      int nb = InpProfileBins;
      double size = (hi - lo) / (double)nb;
      ArrayResize(binVol, nb);
      ArrayInitialize(binVol, 0.0);
      for(int i = fromBar; i < got; i++)
      {
         int b1 = (int)MathMax(0, MathMin(nb - 1, (int)MathFloor((r[i].low  - lo) / size)));
         int b2 = (int)MathMax(0, MathMin(nb - 1, (int)MathFloor((r[i].high - lo) / size)));
         double v = (double)r[i].tick_volume;
         int span = b2 - b1 + 1;
         for(int b = b1; b <= b2; b++) binVol[b] += v / (double)span;
      }

      int pocBin = 0;
      double total = 0.0, sum = 0.0;
      for(int b = 0; b < nb; b++)
      {
         total += binVol[b];
         sum   += binVol[b];
         if(binVol[b] > binVol[pocBin]) pocBin = b;
      }
      if(total <= 0.0) return false;
      meanBin = sum / (double)nb;

      int loBin = pocBin, hiBin = pocBin;
      double covered = binVol[pocBin];
      while(covered < InpValueAreaPct * total && (loBin > 0 || hiBin < nb - 1))
      {
         double below = (loBin > 0)        ? binVol[loBin - 1] : -1.0;
         double above = (hiBin < nb - 1)   ? binVol[hiBin + 1] : -1.0;
         if(above >= below) { hiBin++; covered += binVol[hiBin]; }
         else               { loBin--; covered += binVol[loBin]; }
      }

      out.poc    = lo + (pocBin + 0.5) * size;
      out.val    = lo + loBin * size;
      out.vah    = lo + (hiBin + 1) * size;
      out.lo     = lo;
      out.size   = size;
      out.nb     = nb;
      out.pocBin = pocBin;
      out.valBin = loBin;
      out.vahBin = hiBin;
      out.ok     = true;
      return true;
   }

   //--- the low volume node between the value edge and the price: the widest
   //--- run of thin bins on the pullback path ("where one side got aggressive,
   //--- leaving gaps")
   bool ThinZone(const SVolProfile &prof, double &binVol[], const double meanBin,
                 const int dir, const double price, double &zoneLo, double &zoneHi)
   {
      zoneLo = 0.0; zoneHi = 0.0;
      if(!prof.ok || meanBin <= 0.0) return false;

      int fromBin, toBin;
      if(dir > 0) { fromBin = prof.vahBin; toBin = (int)MathFloor((price - prof.lo) / prof.size); }
      else        { fromBin = (int)MathFloor((price - prof.lo) / prof.size); toBin = prof.valBin; }
      fromBin = (int)MathMax(0, MathMin(prof.nb - 1, fromBin));
      toBin   = (int)MathMax(0, MathMin(prof.nb - 1, toBin));
      if(fromBin > toBin) { int tmp = fromBin; fromBin = toBin; toBin = tmp; }

      double bestLo = 0.0, bestHi = 0.0;
      int runStart = -1;
      for(int b = fromBin; b <= toBin + 1; b++)
      {
         bool thin = (b <= toBin) && (binVol[b] < InpThinBinPct * meanBin);
         if(thin) { if(runStart < 0) runStart = b; continue; }
         if(runStart >= 0)
         {
            double lo = prof.lo + runStart * prof.size;
            double hi = prof.lo + (b) * prof.size;
            if(hi - lo > bestHi - bestLo) { bestLo = lo; bestHi = hi; }
            runStart = -1;
         }
      }
      if(bestHi <= bestLo) return false;
      zoneLo = bestLo; zoneHi = bestHi;
      return true;
   }

   //--- criterion 1: price is at one of the market-generated levels
   bool AtGeneratedLevel(const SEAContext &ctx, const SLevels &lv, const double price, double &level)
   {
      double tol = InpLevelTolAtr * ctx.atr;
      level = 0.0;
      double cand[6];
      int n = 0;
      if(lv.havePd)  { cand[n++] = lv.pdh; cand[n++] = lv.pdl; }
      if(lv.haveOn)  { cand[n++] = lv.onHi; cand[n++] = lv.onLo; }
      if(lv.haveOrb) { cand[n++] = lv.orbHi; cand[n++] = lv.orbLo; }
      for(int i = 0; i < n; i++)
      {
         if(MathAbs(price - cand[i]) <= tol) { level = cand[i]; return true; }
      }
      return false;
   }

   //--- criterion 3: a "big trade" print - a bar far above the median volume
   //--- that touches the level (the document filters a real order feed; this
   //--- is the tick-volume stand-in)
   bool BigTrades(const SEAContext &ctx, const double level, const int dir)
   {
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 1, InpBigTradeLookback + 2, r);
      if(got < 4) return false;
      double med = MedianVolume(r, got);
      if(med <= 0.0) return false;
      double tol = InpLevelTolAtr * ctx.atr;

      for(int i = 0; i < got; i++)
      {
         if((double)r[i].tick_volume < InpBigTradeMult * med) continue;
         if(level > 0.0 && r[i].low > level + tol) continue;      // never traded at the level
         if(level > 0.0 && r[i].high < level - tol) continue;
         bool supports = (dir < 0) ? (r[i].close < r[i].open) : (r[i].close > r[i].open);
         bool atHigh   = (dir < 0) ? (r[i].high >= level - tol) : (r[i].low <= level + tol);
         if(supports || atHigh) return true;
      }
      return false;
   }

   double MedianVolume(const MqlRates &r[], const int got)
   {
      double v[];
      ArrayResize(v, got);
      for(int i = 0; i < got; i++) v[i] = (double)r[i].tick_volume;
      for(int i = 1; i < got; i++)
      {
         double key = v[i];
         int j = i - 1;
         while(j >= 0 && v[j] > key) { v[j + 1] = v[j]; j--; }
         v[j + 1] = key;
      }
      if(got % 2 == 1) return v[got / 2];
      return 0.5 * (v[got / 2 - 1] + v[got / 2]);
   }

   //--- criterion 4a: absorption - a heavy bar tests the level and closes back
   //--- on the defended side ("aggressive sellers hit the bid but price doesn't
   //--- fall - a passive buyer is consuming orders")
   bool Absorption(const SEAContext &ctx, const double level, const int dir)
   {
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 1, 5, r);
      if(got < 4) return false;
      double med = MedianVolume(r, got);
      if(med <= 0.0) return false;
      double tol = InpLevelTolAtr * ctx.atr;

      for(int i = 0; i < got - 1; i++)
      {
         if((double)r[i].tick_volume < InpAbsorbVolMult * med) continue;
         double range = r[i].high - r[i].low;
         if(range <= 0.0) continue;
         double closePos = (r[i].close - r[i].low) / range;
         if(dir < 0 && r[i].high >= level - tol)
         {
            //--- buyers tried the level and were absorbed by passive sellers
            if(closePos >= InpAbsorbWickPct) continue;
            return true;
         }
         if(dir > 0 && r[i].low <= level + tol)
         {
            if(closePos <= 1.0 - InpAbsorbWickPct) continue;
            return true;
         }
      }
      return false;
   }

   //--- criterion 4b: the delta lean - ask-side volume versus bid-side volume,
   //--- proxied from body-directional tick volume
   double DeltaLean(const string sym)
   {
      MqlRates r[];
      int got = EA_Rates(sym, g_eaIndTf, 1, InpDeltaBars + 2, r);
      if(got < 5) return 0.0;
      double up = 0.0, dn = 0.0;
      for(int i = 0; i < got; i++)
      {
         double v = (double)r[i].tick_volume;
         if(r[i].close > r[i].open) up += v;
         else if(r[i].close < r[i].open) dn += v;
      }
      if(up + dn <= 0.0) return 0.0;
      return (up - dn) / (up + dn);
   }

   //-------------------------------------------------------------------
   // model one: the range-bound edge trade
   //-------------------------------------------------------------------
   bool RangePlan(const SEAContext &ctx, const SLevels &lv, const SVolProfile &prof,
                  double &binVol[], const double meanBin, SCfCandidate &out)
   {
      if(!prof.ok) return false;
      double vaHi = prof.vah, vaLo = prof.val;
      double vaRange = vaHi - vaLo;
      if(vaRange <= 0.0) return false;
      double band = InpEdgeBandPct * vaRange;
      double price = ctx.mid;

      //--- the price must be INSIDE the value area at one of its edges
      if(price <= vaLo || price >= vaHi) return false;
      int dir = 0;
      double level = 0.0;
      if(price >= vaHi - band) { dir = -1; level = vaHi; }
      else if(price <= vaLo + band) { dir = 1; level = vaLo; }
      else return false;                                   // the middle: no trade

      //--- the range is only tradeable when it holds no thin node inside
      double zoneLo, zoneHi;
      if(ThinZone(prof, binVol, meanBin, dir, price, zoneLo, zoneHi) && zoneLo > vaLo && zoneHi < vaHi)
         return false;

      out.dir    = dir;
      out.entry  = (dir > 0) ? ctx.ask : ctx.bid;
      out.target = (dir > 0) ? vaHi : vaLo;                 // the opposite edge
      double buf = MathMax(InpStopBufferAtr * ctx.atr, InpStopBufferTicks * ctx.point);
      out.stop   = (dir > 0) ? (level - buf) : (level + buf);
      out.risk   = MathAbs(out.entry - out.stop);
      if(out.risk < InpMinStopAtr * ctx.atr) return false;

      double reward = MathAbs(out.target - out.entry);
      if(reward < InpRangeMinRR * out.risk) return false;

      double hit = 0.0;
      bool atLevel = AtGeneratedLevel(ctx, lv, level, hit);
      bool big     = BigTrades(ctx, level, dir);
      bool absorp  = Absorption(ctx, level, dir);
      bool lean    = LeanSupports(dir, ctx.symbol);
      int  crit    = (atLevel ? 1 : 0) + 1 + (big ? 1 : 0) + ((absorp || lean) ? 1 : 0);
      out.crit = crit;
      out.why  = StringFormat("range edge %s %s: VA edge + %s + %s + %s (crit %d)",
                              (dir > 0 ? "buy" : "sell"), (dir > 0 ? "value low" : "value high"),
                              (atLevel ? "generated level" : "no generated level"),
                              (big ? "big trades" : "no big trades"),
                              (absorp ? "absorption" : (lean ? "delta lean" : "neither")), crit);
      return true;
   }

   bool LeanSupports(const int dir, const string sym)
   {
      double lean = DeltaLean(sym);
      if(MathAbs(lean) < InpDeltaLean) return false;
      return (dir > 0) ? (lean > 0.0) : (lean < 0.0);
   }

   //-------------------------------------------------------------------
   // the trap fade: a wick through a generated level that fails and closes back
   // inside - "price wicked above overnight high, trapping buyers ... big trades
   // at highs, then negative delta on reversal"
   //-------------------------------------------------------------------
   bool FadePlan(const SEAContext &ctx, const SLevels &lv, const SVolProfile &prof, SCfCandidate &out)
   {
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 1, 4, r);
      if(got < 3 || ctx.atr <= 0.0) return false;
      double tol   = InpLevelTolAtr * ctx.atr;
      double price = ctx.mid;

      double cand[6];
      int n = 0;
      if(lv.havePd)  { cand[n++] = lv.pdh; cand[n++] = lv.pdl; }
      if(lv.haveOn)  { cand[n++] = lv.onHi; cand[n++] = lv.onLo; }
      if(lv.haveOrb) { cand[n++] = lv.orbHi; cand[n++] = lv.orbLo; }

      for(int k = 0; k < n; k++)
      {
         double lvl = cand[k];
         if(lvl <= 0.0) continue;
         for(int i = 0; i < 2; i++)                        // the two newest completed bars
         {
            bool upWick = (r[i].high > lvl + tol && r[i].close < lvl);
            bool dnWick = (r[i].low  < lvl - tol && r[i].close > lvl);
            if(!upWick && !dnWick) continue;

            int dir = upWick ? -1 : 1;
            if(dir < 0 && price > lvl + tol) continue;     // price already ran away: too late
            if(dir > 0 && price < lvl - tol) continue;
            if(!prof.ok) continue;                         // need the interior reference

            out.dir   = dir;
            out.entry = (dir > 0) ? ctx.ask : ctx.bid;
            double buf = MathMax(InpStopBufferAtr * ctx.atr, InpStopBufferTicks * ctx.point);
            out.stop  = (dir > 0) ? (r[i].low - buf) : (r[i].high + buf);
            out.risk  = MathAbs(out.entry - out.stop);
            if(out.risk < InpMinStopAtr * ctx.atr) continue;

            //--- the interior target: the value edge it broke from, or the POC deeper in
            double tgt = (dir < 0) ? ((prof.vah < out.entry) ? prof.vah : prof.poc)
                                   : ((prof.val > out.entry) ? prof.val : prof.poc);
            if(tgt <= 0.0) continue;
            double reward = MathAbs(tgt - out.entry);
            if(reward < InpRangeMinRR * out.risk) continue;   // the doc's 3-4R trap trade

            bool big    = BigTrades(ctx, lvl, dir);
            bool absorp = Absorption(ctx, lvl, dir);
            bool lean   = LeanSupports(dir, ctx.symbol);
            int  crit   = 1 + (big ? 1 : 0) + ((absorp || lean) ? 1 : 0);   // level + (at least) one confirmation
            out.target  = tgt;
            out.crit    = crit;
            out.why     = StringFormat("failed break of a generated level (wick %s), %s (crit %d)",
                                       (upWick ? "above" : "below"),
                                       (absorp ? "absorption" : (lean ? "delta lean" : (big ? "big trades" : "level only"))), crit);
            return true;
         }
      }
      return false;
   }

   //-------------------------------------------------------------------
   // model two: trending pullbacks into low volume nodes
   //-------------------------------------------------------------------
   bool TrendPlan(const SEAContext &ctx, const SLevels &lv, const SVolProfile &prof,
                  double &binVol[], const double meanBin, SCfCandidate &out)
   {
      if(!prof.ok) return false;
      double price = ctx.mid;
      int dir = 0;
      if(price > prof.vah) dir = 1;                        // accepting higher prices
      else if(price < prof.val) dir = -1;
      else return false;

      //--- a value break must have printed with a body ("accepting" the new area)
      if(!AcceptedBreak(ctx, prof, dir)) return false;

      //--- the pullback must be in a low volume node between the old edge and price
      double zoneLo, zoneHi;
      if(!ThinZone(prof, binVol, meanBin, dir, price, zoneLo, zoneHi)) return false;
      double tol = MathMax(prof.size, InpLevelTolAtr * ctx.atr);
      bool inZone = (price >= zoneLo - tol && price <= zoneHi + tol);
      if(!inZone) return false;

      out.dir   = dir;
      out.entry = (dir > 0) ? ctx.ask : ctx.bid;
      double buf = MathMax(InpStopBufferAtr * ctx.atr, InpStopBufferTicks * ctx.point);
      //--- the stop goes beyond the node's far edge (the pullback extreme)
      out.stop = (dir > 0) ? (zoneLo - buf) : (zoneHi + buf);
      out.risk = MathAbs(out.entry - out.stop);
      if(out.risk < InpMinStopAtr * ctx.atr) return false;

      //--- the extension target: the value range projected from the broken edge,
      //--- with the next generated level as a cap
      double vaRange = prof.vah - prof.val;
      double ext = (dir > 0) ? (prof.vah + vaRange) : (prof.val - vaRange);
      double levelCap = 0.0;
      if(dir > 0)
      {
         if(lv.havePd && lv.pdh > out.entry) levelCap = lv.pdh;
         if(lv.haveOn && lv.onHi > out.entry && (levelCap == 0.0 || lv.onHi < levelCap)) levelCap = lv.onHi;
      }
      else
      {
         if(lv.havePd && lv.pdl < out.entry) levelCap = lv.pdl;
         if(lv.haveOn && lv.onLo < out.entry && (levelCap == 0.0 || lv.onLo > levelCap)) levelCap = lv.onLo;
      }
      out.target = (levelCap != 0.0) ? levelCap : ext;

      double reward = MathAbs(out.target - out.entry);
      if(reward < InpTrendMinRR * out.risk) return false;

      double hit = 0.0;
      bool atLevel = AtGeneratedLevel(ctx, lv, price, hit);
      bool big     = BigTrades(ctx, price, dir);
      bool absorp  = Absorption(ctx, price, dir);
      bool lean    = LeanSupports(dir, ctx.symbol);
      int  crit    = (atLevel ? 1 : 0) + 1 + (big ? 1 : 0) + ((absorp || lean) ? 1 : 0);
      out.crit = crit;
      out.why  = StringFormat("trend pullback %s into a low volume node, target %s, %s (crit %d)",
                              (dir > 0 ? "long" : "short"),
                              (levelCap != 0.0 ? "the next generated level" : "a measured extension"),
                              (absorp ? "absorption confirmed" : (big ? "big trades confirmed" : "delta lean")), crit);
      return true;
   }

   bool AcceptedBreak(const SEAContext &ctx, const SVolProfile &prof, const int dir)
   {
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 1, InpBreakBars + 2, r);
      if(got < 4) return false;
      for(int i = 0; i < got; i++)
      {
         double body = EA_BodyRatio(r[i]);
         if(body < InpAcceptBody) continue;
         if(dir > 0 && r[i].close > prof.vah) return true;
         if(dir < 0 && r[i].close < prof.val) return true;
      }
      return false;
   }

   //-------------------------------------------------------------------
   // gates
   //-------------------------------------------------------------------
   bool MiddleOfRange(const SEAContext &ctx, const SVolProfile &prof)
   {
      if(!prof.ok) return false;
      double vaRange = prof.vah - prof.val;
      if(vaRange <= 0.0) return false;
      double band = InpEdgeBandPct * vaRange;
      double price = ctx.mid;
      if(price <= prof.val || price >= prof.vah) return false;     // outside: not "the middle"
      return (price > prof.val + band && price < prof.vah - band);
   }

   bool Chasing(const SEAContext &ctx)
   {
      //--- "if price is aggressively moving up or down without pullback, do not
      //--- enter": the gate is direction-agnostic - a fast move with no pullback
      //--- inside it is untouchable on either side, which is exactly what both
      //--- models wait out (an edge touch or a node pullback is the pause)
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 1, 6, r);
      if(got < 4 || ctx.atr <= 0.0) return false;
      double move = r[0].close - r[3].close;
      if(MathAbs(move) < InpChaseAtr * ctx.atr) return false;

      double against = 0.0;
      for(int i = 0; i < 4; i++)
      {
         double push = (move > 0.0) ? (MathMax(r[i].open, r[i].close) - r[i].low)
                                    : (r[i].high - MathMin(r[i].open, r[i].close));
         against = MathMax(against, push);
      }
      return (against < InpPullbackAtr * ctx.atr);
   }
};

CCfOrderFlowStrategy g_cfOrderFlowStrategy;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfOrderFlowStrategy);
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
