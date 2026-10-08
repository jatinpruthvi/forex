//+------------------------------------------------------------------+
//|                                      EA_CF_EpisodicPivot.mq5     |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| ChartFanatics playbook: Episodic Pivot (Pradeep Bonde)            |
//| Card    : chartfanatics/todos/episodic-pivot-strategy.md   (#08)  |
//| Source  : chartfanatics/pdf/episodic-pivot-strategy.pdf           |
//| Magic   : 3212                                                   |
//|                                                                  |
//| "A neglected stock receives new information that forces the       |
//|  market to reprice it very quickly."  Three core elements:        |
//|  NEGLECT (months of nothing), a NEW CATALYST, and RAPID           |
//|  REPRICING (large gap, huge volume).                              |
//|                                                                  |
//| The EA implements the three setups that are mechanical from bars: |
//|                                                                  |
//|  1. CLASSICAL EP, Day-1 (long)                                    |
//|     * neglect: the prior 60 days were a dead range on low volume  |
//|     * catalyst day: a big gap up and heavy volume                 |
//|     * entry "near the open ... within the first 5-10 minutes if   |
//|       strength confirms" -> the opening-range break of the next   |
//|       session, with strength                                      |
//|     * stop "below the opening-range low"; move to break-even once |
//|       the trade pushes favourably; trail under the daily swing    |
//|       lows; exit if the trend breaks (custom Manage below)        |
//|                                                                  |
//|  2. EP 9 MILLION (long)                                           |
//|     * "any stock that trades 9 million shares or more in a single |
//|       day, far above its normal volume" -> the count comes from   |
//|       real volume when the broker publishes it                   |
//|     * enter intraday once that volume aligns with a clear trend   |
//|     * stop under intraday support                                 |
//|                                                                  |
//|  3. DELAYED REACTION (long and short)                             |
//|     * long: after a positive catalyst, a breakout from the tight  |
//|       range that formed afterwards, with strong volume            |
//|     * short: after a negative catalyst gap down, the bounce into  |
//|       resistance fails and the weakness resumes                   |
//|                                                                  |
//| `[interpretation]`: the playbook trades single stocks chosen for  |
//| their catalyst (earnings, guidance, themes).  An EA sees prices   |
//| and volume only, so the "catalyst" is read as its mechanical      |
//| footprint - an outsized gap/move on abnormal volume.  The symbol  |
//| list is therefore the user's instrument selection, and the EA     |
//| documents this instead of pretending to read the news.            |
//| Trade management follows the trade breakdowns (SMCI/ROOT):        |
//| break-even once the trade pushes favourably, then the stop trails |
//| under each day's low until the trend breaks.                      |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics Episodic Pivot - neglect + catalyst + repricing, with day-1, 9M and delayed-reaction entries"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade   = "US100,US500,GER40";  // Instrument selection is the user's catalyst universe
input ulong             InpMagicNumber      = 3212;                 // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct          = 0.50;                 // Risk per trade (% of equity)
input int               InpStage             = 5;                   // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input double            InpMaxSpreadPoints  = 3.0;                  // Spread gate in points (0 = off)
input double            InpDailyLossPct     = 1.50;                 // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset  = 2;                    // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;        // Log verbosity
input double            InpCommissionPerLotRT = 0.0;                // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.12;               // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;               // Write the engine evidence ledger CSV
//--- what counts as a catalyst (its mechanical footprint)
input double InpCatGapPct     = 5.0;    // Catalyst-day gap up vs the prior close (%) - "large gap"
input double InpCatMovePct    = 8.0;    // ... or the catalyst day's own move (%) - "strong follow-through"
input double InpCatVolMult    = 4.0;    // Catalyst volume vs its 20-day average - "huge increase in volume"
input double InpNeglectRange  = 0.35;   // Neglect: the prior 60-day range must be below this share of ATR-sum
input double InpNeglectVol    = 0.80;   // ... and its average volume below this multiple of the longer-run average
//--- entry / risk
input int    InpOrMinutes     = 30;     // Opening range of the entry session (minutes)
input double InpStrengthAtr   = 0.10;   // "if strength confirms": break beyond the OR by this ATR share
input double InpStopBufferAtr = 0.15;   // Buffer beyond the opening-range low / intraday support
input int    InpTrailDays     = 1;      // Trail the stop under this many completed daily lows
input bool   InpExitOnDailyBreak = true; // "exit if the trend breaks": close under the prior daily low
//--- EP 9 million
input bool   InpUseNineMillion = true;  // EP 9M setup
input double InpNineMShares    = 9000000; // "9 million shares or more in a single day"
input double InpNineMVolMult   = 5.0;   // ... when far above its normal volume
//--- delayed reaction
input bool   InpUseDelayedLong  = true; // Post-catalyst range breakout
input bool   InpUseDelayedShort = true; // Negative-catalyst bounce failure
input int    InpDelayedWindowBars = 20; // "monitor it for up to a month" (~20 trading days)
input double InpTightRangeAtr   = 3.0;  // Post-catalyst consolidation width (ATR multiples)

//+------------------------------------------------------------------+
class CCfEpisodicPivot : public CEAStrategy
{
public:
   void OnInitStrategy()
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("5-stage policy: stage %d active (risk %.3f%%, %d trades/day max)",
             InpStage, g_eaCfg.riskPct, g_eaCfg.maxTradesPerDay), true);
      EA_Log(EA_LOG_EVENTS, "episodic pivot armed: neglect + catalyst + repricing; day-1, 9M and delayed-reaction entries",
             true);
   }

   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_EPISODIC_PIVOT";
      cfg.sourceDoc             = "chartfanatics/pdf/episodic-pivot-strategy.pdf (card #08)";
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
      cfg.maxTradesPerDay       = 2;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 300;
      cfg.sessionStartHour      = 14;  cfg.sessionStartMin = 25;   // the US cash session (where the OR lives)
      cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;
      cfg.noTradeAfterHour      = 20;  cfg.noTradeAfterMin = 0;    // no new EP entries in the last hour
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = false;                     // "do not anticipate" - strength must confirm
      cfg.breakEvenAtR          = 1.0;                       // "stop moved to break-even once the trade pushed favourably"
      cfg.partial1AtR           = 2.0;  cfg.partial1Pct = 33.0;   // scale out on the way (conviction sizing)
      cfg.trailAtR              = 0.0;                       // the DAILY-low trail in Manage() is the real trail
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_episodic_pivot_ledger.csv";
      cfg.newsFilter            = false;                     // the catalyst IS the news; a calendar gate would block it
      cfg.logLevel              = InpLogLevel;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession || ctx.atr <= 0.0) return false;

      if(InpUseNineMillion && NineMillion(ctx, plan)) return true;
      if(DayOneEp(ctx, plan)) return true;
      if(InpUseDelayedLong && DelayedLong(ctx, plan)) return true;
      if(InpUseDelayedShort && DelayedShort(ctx, plan)) return true;
      return false;
   }

   //--- the trade breakdowns' management: trail the stop under the recent completed DAILY lows and
   //--- leave when the trend breaks (a close below the prior daily low).  This is the playbook's own
   //--- "trail the position under daily swing lows" - the engine's R-trail cannot express it.
   void Manage(SEAContext &ctx)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;

         int    dir   = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? +1 : -1;
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl    = PositionGetDouble(POSITION_SL);
         double risk  = (sl > 0.0) ? MathAbs(entry - sl) : 0.0;

         if(dir < 0)     // delayed-reaction shorts: the daily-low trail is a long-side tool
         {
            if(InpExitOnDailyBreak && ClosedAbovePriorHigh(ctx.symbol))
            {
               EA_Log(EA_LOG_EVENTS, "EP short: bounce reclaimed the prior day's high - closing", true);
               g_eaExec.Close(ticket, "rebound reclaimed the level");
            }
            continue;
         }

         //--- exit if the trend breaks: a daily close under the prior day's low
         if(InpExitOnDailyBreak && ClosedBelowPriorLow(ctx.symbol))
         {
            EA_Log(EA_LOG_EVENTS, "EP long: daily close below the prior low - trend broke, closing", true);
            g_eaExec.Close(ticket, "trend broke");
            continue;
         }

         //--- the daily swing-low trail
         MqlRates d[];
         if(EA_Rates(ctx.symbol, PERIOD_D1, 0, InpTrailDays + 2, d) < InpTrailDays + 1) continue;
         double trail = d[InpTrailDays].low - InpStopBufferAtr * ctx.atr;
         if(trail <= 0.0 || entry <= 0.0) continue;
         if(trail > entry) continue;                      // never a stop above the entry
         double cur = PositionGetDouble(POSITION_SL);
         if(trail > cur + SymbolInfoDouble(ctx.symbol, SYMBOL_TRADE_TICK_SIZE) * 0.5)
         {
            double tp = PositionGetDouble(POSITION_TP);
            if(g_eaExec.Modify(ticket, trail, tp))
               EA_Log(EA_LOG_EVENTS, StringFormat("EP long: stop trailed under the daily low to %.2f", trail), true);
         }
      }
   }

private:
   bool ClosedBelowPriorLow(const string sym)
   {
      MqlRates d[];
      if(EA_Rates(sym, PERIOD_D1, 0, 3, d) < 3) return false;
      return (d[1].close < d[2].low);          // yesterday closed under the prior day's low
   }

   bool ClosedAbovePriorHigh(const string sym)
   {
      MqlRates d[];
      if(EA_Rates(sym, PERIOD_D1, 0, 3, d) < 3) return false;
      return (d[1].close > d[2].high);
   }

   //--- the catalyst footprint: a gap up and/or a strong move on abnormal volume, on the last
   //--- COMPLETED day (index 1 of the daily series)
   bool CatalystDay(const string sym, const bool positive, double &gapPct, double &volMult)
   {
      MqlRates d[];
      if(EA_Rates(sym, PERIOD_D1, 0, 24, d) < 22) return false;
      gapPct = (d[2].close > 0.0) ? (d[1].open - d[2].close) / d[2].close * 100.0 : 0.0;
      double movePct = (d[1].open > 0.0) ? (d[1].close - d[1].open) / d[1].open * 100.0 : 0.0;
      double avg = 0.0;
      for(int i = 2; i <= 21; i++) avg += (double)d[i].tick_volume;
      avg /= 20.0;
      volMult = (avg > 0.0) ? (double)d[1].tick_volume / avg : 0.0;
      if(volMult < InpCatVolMult) return false;
      if(positive)
         return (gapPct >= InpCatGapPct) || (movePct >= InpCatMovePct);
      return (gapPct <= -InpCatGapPct) || (movePct <= -InpCatMovePct);
   }

   //--- neglect: the last InpNeglectDays were a dead range on low volume
   bool Neglected(const string sym)
   {
      MqlRates d[];
      if(EA_Rates(sym, PERIOD_D1, 0, 64, d) < 62) return true;   // not enough history: do not block
      double hi = -DBL_MAX, lo = DBL_MAX, vol = 0.0, volLong = 0.0;
      for(int i = 21; i <= 60; i++)                              // the pre-catalyst window
      {
         hi = MathMax(hi, d[i].high);
         lo = MathMin(lo, d[i].low);
         vol += (double)d[i].tick_volume;
      }
      vol /= 40.0;
      for(int i = 20; i >= 1; i--) volLong += (double)d[i].tick_volume;  // recent 20 days
      volLong /= 20.0;
      if(hi <= lo) return false;
      //--- a dead range: its height is a fraction of the recent average true range
      MqlRates m[];
      int got = EA_Rates(sym, g_eaIndTf, 0, 400, m);
      if(got < 100) return false;
      double atrSum = 0.0;
      for(int i = 1; i < got; i++)
      {
         double tr = MathMax(m[i].high - m[i].low,
                     MathMax(MathAbs(m[i].high - m[i - 1].close), MathAbs(m[i].low - m[i - 1].close)));
         atrSum += tr;
      }
      double atrLong = atrSum / (double)(got - 1);
      if(atrLong <= 0.0) return false;
      bool deadRange = (hi - lo) < InpNeglectRange * atrLong * 40.0;   // a dead range, not a trend
      bool quietVol  = (volLong <= InpNeglectVol * MathMax(vol, 1.0)); // recent volume below the older norm
      return (deadRange && quietVol);
   }

   //--- the session's opening range (first InpOrMinutes of the current server day)
   bool OpeningRange(const SEAContext &ctx, double &hi, double &lo)
   {
      //--- both bounds are London-clock minutes, the convention every SigRangeForDay() call uses
      int from = 870;                                            // NY cash open (14:30 London)
      int to   = MathMin(ctx.clockMinutes, from + InpOrMinutes);
      if(to <= from) return false;                               // the OR has not printed yet
      double h = 0.0, l = 0.0;
      int bars = 0;
      if(!SigRangeForDay(ctx.symbol, g_eaIndTf, from, to, 0, h, l, bars)) return false;
      if(h <= 0.0 || l <= 0.0 || h <= l) return false;
      hi = h; lo = l;
      return true;
   }

   //--- SETUP 1: classical EP, day 1.  The catalyst printed yesterday; today the opening-range
   //--- break with strength is the entry, the OR low the stop, and Manage() trails under the days.
   bool DayOneEp(SEAContext &ctx, SSignalPlan &plan)
   {
      double gapPct = 0.0, volMult = 0.0;
      if(!CatalystDay(ctx.symbol, true, gapPct, volMult)) return false;
      if(!Neglected(ctx.symbol)) return false;

      double orHi = 0.0, orLo = 0.0;
      if(!OpeningRange(ctx, orHi, orLo)) return false;
      if(!(ctx.mid > orHi + InpStrengthAtr * ctx.atr)) return false;      // "if strength confirms"

      double entry = ctx.ask;
      double stop  = orLo - InpStopBufferAtr * ctx.atr;                   // "below the opening-range low"
      double risk  = entry - stop;
      if(risk <= 0.0) return false;

      plan.dir = +1; plan.entry = entry; plan.stop = stop; plan.riskDist = risk;
      plan.target = entry + 3.0 * risk;      // long runway: the trail, not the TP, ends the trade
      plan.barsAgo = 1; plan.score = 74.0; plan.isLimit = false;
      plan.reason = StringFormat("classical EP day 1 (gap %.1f%%, volume %.1fx) - OR break", gapPct, volMult);
      return true;
   }

   //--- SETUP 2: EP 9 Million - abnormal absolute volume with a clear trend, entered intraday.
   //--- `[interpretation]`: real share volume is used when the broker publishes it (stocks); on
   //--- CFDs the tick volume stands in, which is why the multiple filter also applies.
   bool NineMillion(SEAContext &ctx, SSignalPlan &plan)
   {
      MqlRates d[];
      if(EA_Rates(ctx.symbol, PERIOD_D1, 0, 24, d) < 22) return false;

      double realVol = (double)iVolumeReal(ctx.symbol, PERIOD_D1, 1);
      double vol = (realVol > 0.0) ? realVol : (double)d[1].tick_volume;
      if(vol < InpNineMShares) return false;

      double avg = 0.0;
      for(int i = 2; i <= 21; i++) avg += (double)d[i].tick_volume;
      avg /= 20.0;
      if(avg <= 0.0 || (double)d[1].tick_volume < InpNineMVolMult * avg) return false;

      //--- "clear trend": the last closed bars are making higher highs above the session's VWAP proxy
      MqlRates m[];
      if(EA_Rates(ctx.symbol, g_eaIndTf, 0, 6, m) < 5) return false;
      bool trend = (m[1].close > m[1].open) && (m[1].high > m[2].high) && (ctx.mid > ctx.ema20);
      if(!trend) return false;

      //--- intraday support: the lowest low of the last 6 bars
      double support = m[1].low;
      for(int i = 2; i <= 5; i++) support = MathMin(support, m[i].low);
      double entry = ctx.ask;
      double stop  = support - InpStopBufferAtr * ctx.atr;
      double risk  = entry - stop;
      if(risk <= 0.0) return false;

      plan.dir = +1; plan.entry = entry; plan.stop = stop; plan.riskDist = risk;
      plan.target = entry + 3.0 * risk;
      plan.barsAgo = 1; plan.score = 68.0; plan.isLimit = false;
      plan.reason = StringFormat("EP 9M: %.1fM volume (%.1fx normal) on a trending day", vol / 1e6,
                                 (double)d[1].tick_volume / avg);
      return true;
   }

   //--- SETUP 3a: delayed reaction long - after a positive catalyst within the window, a breakout
   //--- from the tight post-catalyst range with strong volume.
   bool DelayedLong(SEAContext &ctx, SSignalPlan &plan)
   {
      MqlRates d[];
      if(EA_Rates(ctx.symbol, PERIOD_D1, 0, InpDelayedWindowBars + 24, d) < InpDelayedWindowBars + 22) return false;

      //--- a positive catalyst inside the window (not necessarily yesterday)
      bool catalyst = false;
      for(int i = 2; i <= InpDelayedWindowBars; i++)
      {
         if(d[i].close <= d[i + 1].close) continue;
         double move = (d[i].open > 0.0) ? (d[i].close - d[i].open) / d[i].open * 100.0 : 0.0;
         double gap  = (d[i + 1].close > 0.0) ? (d[i].open - d[i + 1].close) / d[i + 1].close * 100.0 : 0.0;
         if(move >= InpCatMovePct || gap >= InpCatGapPct) { catalyst = true; break; }
      }
      if(!catalyst) return false;

      //--- the consolidation after it: tight range over the last bars before today
      double hi = -DBL_MAX, lo = DBL_MAX;
      for(int i = 2; i <= 10; i++) { hi = MathMax(hi, d[i].high); lo = MathMin(lo, d[i].low); }
      if(hi <= lo || (hi - lo) > InpTightRangeAtr * ctx.atrD1) return false;

      //--- today's breakout from that range with volume
      if(!(ctx.mid > hi)) return false;
      MqlRates m[];
      if(EA_Rates(ctx.symbol, g_eaIndTf, 0, 24, m) < 21) return false;
      double vAvg = 0.0;
      for(int i = 2; i <= 21; i++) vAvg += (double)m[i].tick_volume;
      vAvg /= 20.0;
      if(vAvg <= 0.0 || (double)m[1].tick_volume < 1.5 * vAvg) return false;

      double entry = ctx.ask;
      double stop  = lo - InpStopBufferAtr * ctx.atr;
      double risk  = entry - stop;
      if(risk <= 0.0) return false;
      plan.dir = +1; plan.entry = entry; plan.stop = stop; plan.riskDist = risk;
      plan.target = entry + 3.0 * risk;
      plan.barsAgo = 1; plan.score = 66.0; plan.isLimit = false;
      plan.reason = StringFormat("delayed EP long: range breakout %.2f after the catalyst", hi);
      return true;
   }

   //--- SETUP 3b: delayed reaction short - negative catalyst gap down, then the bounce fails.
   bool DelayedShort(SEAContext &ctx, SSignalPlan &plan)
   {
      double gapPct = 0.0, volMult = 0.0;
      //--- the negative catalyst must be recent (it is the thing being traded)
      MqlRates d[];
      if(EA_Rates(ctx.symbol, PERIOD_D1, 0, InpDelayedWindowBars + 24, d) < InpDelayedWindowBars + 22) return false;
      int catIdx = -1;
      for(int i = 2; i <= InpDelayedWindowBars; i++)
      {
         double gap = (d[i + 1].close > 0.0) ? (d[i].open - d[i + 1].close) / d[i + 1].close * 100.0 : 0.0;
         double move = (d[i].open > 0.0) ? (d[i].close - d[i].open) / d[i].open * 100.0 : 0.0;
         if(gap <= -InpCatGapPct || move <= -InpCatMovePct) { catIdx = i; gapPct = MathMin(gap, move); break; }
      }
      if(catIdx < 0) return false;

      //--- the bounce: price rallied back toward the catalyst day's high and failed - the last closed
      //--- bar rejected it (bearish close) while staying below that high
      if(!(d[1].high < d[catIdx].high)) return false;      // a full reclaim is a different story
      MqlRates m[];
      if(EA_Rates(ctx.symbol, g_eaIndTf, 0, 6, m) < 5) return false;
      if(!(m[1].close < m[1].open)) return false;          // the rejection bar
      if(!(m[1].high >= m[2].high)) return false;          // it actually tested the bounce's high

      double entry = ctx.bid;
      double stop  = m[1].high + InpStopBufferAtr * ctx.atr;   // "above the high of the bounce"
      double risk  = stop - entry;
      if(risk <= 0.0) return false;
      plan.dir = -1; plan.entry = entry; plan.stop = stop; plan.riskDist = risk;
      plan.target = entry - 3.0 * risk;
      plan.barsAgo = 1; plan.score = 66.0; plan.isLimit = false;
      plan.reason = StringFormat("delayed EP short: bounce failed %.1f%% below the catalyst high", gapPct);
      return true;
   }
};

CCfEpisodicPivot g_cfEpisodicPivot;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfEpisodicPivot);
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
