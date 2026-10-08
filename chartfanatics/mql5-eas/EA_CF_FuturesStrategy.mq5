//+------------------------------------------------------------------+
//|                                    EA_CF_FuturesStrategy.mq5     |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| ChartFanatics: "Futures Trading Strategy" (Anthony Crudele)       |
//| Card    : chartfanatics/todos/futures-trading-strategy.md  (#13)  |
//| Source  : chartfanatics/pdf/futures-trading-strategy.pdf          |
//| Magic   : 3217                                                    |
//|                                                                  |
//| "Trade better by first identifying the market environment."        |
//|                                                                    |
//| The daily chart answers one question - which of three environments  |
//| is the market in - and only then does execution drop down:          |
//|                                                                    |
//|   CONSOLIDATION (two-way tape)                                     |
//|     Bollinger Bands contract, price rang es.  Fake breakouts snap   |
//|     back.  Trade the EDGES of the range, stay out of the middle;    |
//|     "drop down in timeframe" to execute (the doc names 60-min/30-   |
//|     min -> this EA's signal timeframe is M30).                      |
//|                                                                    |
//|   EXPANSION (one-directional only)                                 |
//|     Bands expand out of the prior consolidation, price tags the     |
//|     upper band in uptrends / lower in downtrends.  Bullish =        |
//|     long-only, bearish = short-only - "no fading rallies in an      |
//|     up-expansion".  Entry after breakout/confirmation.  Targets:    |
//|     the prior Bollinger-band peak ("unfinished business") and       |
//|     higher-timeframe levels (week extremes).                        |
//|                                                                    |
//|   MEAN REVERSION (pullback against the primary trend)              |
//|     After an expansion the bands contract again.  The Beacon fib    |
//|     levels are 30% / 50% (main target) / 70% of the leg the band    |
//|     peaks delimit.  Bearish rule (the doc's explicit example): a    |
//|     daily close BELOW the 30% line starts the trade, the target is  |
//|     50%, and the trade lives until a daily close back above the     |
//|     level.  Once 50% is hit the objective is done - "hands in       |
//|     pocket" until the environment is clear again.  Counter-trend    |
//|     means smaller size.                                             |
//|                                                                    |
//| Risk: "managed in dollars, not one contract every time" - the       |
//| engine sizes by risk percent.  The stop is structural (a key high   |
//| or low, via the engine's fractal detector); when that stop is       |
//| unrealistically wide the document's answer is options, which an     |
//| EA cannot take - so the trade is skipped (labelled below).          |
//| Typical holding time 1-5 trading days is enforced as a max hold.    |
//|                                                                    |
//| `[interpretation]`: the Beacon is a proprietary auto-tool described |
//| in words only, so the levels are the standard retracements of the   |
//| leg the two band peaks delimit; "contracting/expanding" needs a     |
//| number (ratio vs the 20-day average bandwidth); the anchored-VWAP   |
//| anchor is the phase anchor and its bands are represented by the     |
//| engine's 1R partial; the MA exit context is read as a daily close   |
//| on the wrong side of both the 8 and the 21 average.                 |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics Futures Trading Strategy - environment first (consolidation / expansion / mean reversion)"

#include "..\..\Include\EACommon.mqh"

enum ENUM_CF_FUT_ENV
{
   CF_FUT_UNCLEAR       = 0,
   CF_FUT_CONSOLIDATION = 1,   // two-way tape, trade the edges
   CF_FUT_EXPANSION_BULL= 2,   // one direction only: long-only
   CF_FUT_EXPANSION_BEAR= 3,   // one direction only: short-only
   CF_FUT_MEANREV_BEAR  = 4,   // daily close below the 30% line -> target 50%
   CF_FUT_MEANREV_BULL  = 5    // mirror: daily close above the 30% line -> target 50%
};

//--- the levels one environment classification produces
struct SFutLevels
{
   double consHi, consLo;        // prior consolidation box (Donchian)
   double peakHigh, legLow;      // up-leg: top reached and the leg's origin
   double troughLow, legHigh;    // down-leg mirror
   double l30, l50, l70;         // the Beacon levels for the current leg
   int    peakBar;               // bars-ago of the band peak (anchor for VWAP)
   bool   legUp;                 // the band peaked on an up-leg
   void Reset()
   {
      consHi = consLo = 0.0;
      peakHigh = legLow = troughLow = legHigh = 0.0;
      l30 = l50 = l70 = 0.0; peakBar = 0; legUp = false;
   }
};

//--- identity / risk
input string            InpSymbolsToTrade   = "US100,US500,GER40";  // "primarily designed for index markets (S&P / Nasdaq / Russell)"
input ulong             InpMagicNumber      = 3217;                 // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct          = 0.50;                 // Risk per trade (% of equity) - "risk is managed in dollars"
input int               InpStage             = 5;                   // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input double            InpMaxSpreadPoints  = 3.0;                  // Spread gate in points (0 = off)
input double            InpDailyLossPct     = 1.50;                 // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset  = 2;                    // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;        // Log verbosity
input double            InpCommissionPerLotRT = 0.0;                // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.12;               // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;               // Write the engine evidence ledger CSV
//--- environment (Bollinger 20 / 3 sigma, the document's required core indicator)
input int    InpBbPeriod        = 20;    // Bollinger length (doc: 20)
input double InpBbDeviations    = 3.0;   // Bollinger standard deviations (doc: 3)
input double InpContractRatio   = 0.90;  // `[interpretation]` bandwidth <= x * 20-day average = contracting
input double InpExpandRatio     = 1.10;  // `[interpretation]` bandwidth >= x * 20-day average = expanding
input int    InpPeakLookbackDays= 15;    // A band peak this recent keeps the mean-reversion phase live
input int    InpPeakWin         = 5;     // local-max window that defines a band peak
input int    InpLegLookbackDays = 20;    // how far back the leg that the band peaks delimit may start
//--- consolidation
input int    InpConsRangeDays   = 20;    // the range box (Donchian) traded at its edges
input double InpEdgeZonePct     = 0.15;  // an edge means within x% of the box width
input double InpWickRatio       = 0.35;  // rejection wick the edge entry must show
//--- expansion
input double InpBreakBufferAtr  = 0.10;  // daily-ATR buffer beyond the box that confirms the breakout
input int    InpSwingCount      = 6;     // fractals scanned for the structural stop ("above a key high")
input double InpStopBufferAtr   = 0.15;  // buffer beyond the key high/low
input double InpMaxStopPct      = 8.0;   // `[interpretation]` stop wider than x% = "use options" = skip the trade
input double InpTargetR         = 2.5;   // fallback target when no unfinished-business / week level applies
//--- mean reversion
input double InpBeacon30        = 0.30;  // the document's levels (30 / 50 / 70 on the leg)
input double InpBeacon50        = 0.50;
input double InpBeacon70        = 0.70;
input double InpCounterTrendRiskMult = 0.5;  // "smaller size if against the primary trend"
//--- management (all exits are the document's own tools)
input bool   InpUseAnchoredVwap = true;  // "anchored VWAP (when volatility is extreme)" - close back through it exits
input bool   InpUseMaExitContext= true;  // "8/21/34 moving averages (exit context, not entry signals)"
input int    InpMaxHoldDays     = 5;     // "typical holding time: 1 to 5 trading days"
input double InpPartial1AtR     = 1.0;   // "scale out into targets/levels"

//+------------------------------------------------------------------+
//| The strategy: environment first, execution second                 |
//+------------------------------------------------------------------+
class CCfFuturesStrategy : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_FUTURES_ENVIRONMENT";
      cfg.sourceDoc             = "chartfanatics/pdf/futures-trading-strategy.pdf (card #13)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M30;      // the doc's execution timeframes: 60-min / 30-min
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = 3.0;
      cfg.totalDdPct            = 8.0;
      cfg.maxTradesPerDay       = 0;               // the document sets no daily cap; one position at a time limits it
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 300;
      cfg.sessionStartHour      = 14;  cfg.sessionStartMin = 30;   // US cash session (the index RTH)
      cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;
      cfg.noTradeAfterHour      = 20;  cfg.noTradeAfterMin = 30;
      cfg.fridayFlat            = false;           // a 1-5 day swing may hold through the weekend
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = false;
      cfg.breakEvenAtR          = 1.0;
      cfg.partial1AtR           = InpPartial1AtR;  cfg.partial1Pct = 50.0;
      cfg.trailAtR              = 2.0;             // the runner rides a widening trail while the levels are worked
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_futures_ledger.csv";
      cfg.newsFilter            = false;
      cfg.logLevel              = InpLogLevel;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   void OnInitStrategy()
   {
      m_sizeMult = 1.0;
      m_smSymbol = ""; m_smEntry = 0.0; m_smRisk = 0.0;
      m_anchorBars = InpConsRangeDays;
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "environment-first system armed: BB(%d,%.1f) on D1, exec %s, max hold %d days, counter-trend size x%.2f",
             InpBbPeriod, InpBbDeviations, EnumToString(g_eaCfg.signalTimeframe), InpMaxHoldDays,
             InpCounterTrendRiskMult), true);
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession || ctx.atr <= 0.0 || ctx.atrD1 <= 0.0) return false;

      ENUM_CF_FUT_ENV env = CF_FUT_UNCLEAR;
      SFutLevels lv;
      bool counter = false;
      if(!Classify(ctx, env, lv, counter)) return false;

      double entry = 0.0, stop = 0.0, target = 0.0;
      int    dir = 0;
      string why = "";
      double score = 0.0;

      if(env == CF_FUT_EXPANSION_BULL || env == CF_FUT_EXPANSION_BEAR)
      {
         //--- "Expansion: enter after breakout/confirmation; manage as trend continuation"
         MqlRates m[];
         if(EA_Rates(ctx.symbol, g_eaIndTf, 0, 4, m) < 2) return false;
         dir = (env == CF_FUT_EXPANSION_BULL) ? +1 : -1;
         double box   = (dir > 0) ? lv.consHi : lv.consLo;
         double close = m[1].close;
         if(dir > 0 && !(close > box + InpBreakBufferAtr * ctx.atrD1 && close > m[1].open && ctx.mid > box)) return false;
         if(dir < 0 && !(close < box - InpBreakBufferAtr * ctx.atrD1 && close < m[1].open && ctx.mid < box)) return false;

         entry = (dir > 0) ? ctx.ask : ctx.bid;
         //--- "the logical stop is above a key high (below a key low)"
         double key = KeyLevel(ctx, dir, lv);
         if(key <= 0.0) return false;
         stop = (dir > 0) ? key - InpStopBufferAtr * ctx.atrD1 : key + InpStopBufferAtr * ctx.atrD1;
         double risk = (dir > 0) ? entry - stop : stop - entry;
         if(risk <= 0.0) return false;
         //--- "if the stop becomes unrealistically wide ... use options" - an EA cannot, so it stands aside
         if((risk / entry) * 100.0 > InpMaxStopPct) return false;
         target = LevelTarget(ctx, dir, entry, risk, lv);
         why    = (dir > 0) ? "bullish expansion breakout" : "bearish expansion breakdown";
         score  = 80.0;
      }
      else if(env == CF_FUT_MEANREV_BEAR || env == CF_FUT_MEANREV_BULL)
      {
         //--- "execute after daily trigger (close below 30% line), aim for 50%"
         MqlRates d[];
         if(EA_Rates(ctx.symbol, PERIOD_D1, 0, 3, d) < 3) return false;
         dir = (env == CF_FUT_MEANREV_BEAR) ? -1 : +1;
         double trig = lv.l30;                                      // the 30% line of the current leg
         double dst  = lv.l50;                                      // the 50% objective
         if(dir < 0 && !(d[1].close < trig)) return false;            // the daily trigger
         if(dir > 0 && !(d[1].close > trig)) return false;
         //--- "once 50% is hit the objective is done" - no new trades beyond the objective
         if(dir < 0 && ctx.mid <= dst) return false;
         if(dir > 0 && ctx.mid >= dst) return false;
         //--- M30 confirmation in the trigger's direction (execution refinement)
         MqlRates m[];
         if(EA_Rates(ctx.symbol, g_eaIndTf, 0, 3, m) < 2) return false;
         if(dir < 0 && !(m[1].close < m[1].open && m[1].close < trig)) return false;
         if(dir > 0 && !(m[1].close > m[1].open && m[1].close > trig)) return false;

         entry = (dir > 0) ? ctx.ask : ctx.bid;
         //--- "until a daily close back above the relevant level": the line plus a daily-ATR buffer,
         //--- enforced as a hard stop as well as the close-based exit in Manage()
         stop = (dir < 0) ? trig + InpStopBufferAtr * ctx.atrD1 : trig - InpStopBufferAtr * ctx.atrD1;
         double risk = (dir < 0) ? stop - entry : entry - stop;
         if(risk <= 0.0) return false;
         if((risk / entry) * 100.0 > InpMaxStopPct) return false;     // "use options" = an EA stands aside
         if(dir < 0 && dst >= entry - ctx.atr * 0.5) return false;    // no room left to the 50% objective
         if(dir > 0 && dst <= entry + ctx.atr * 0.5) return false;
         target = dst;
         why    = StringFormat("%s mean reversion: daily close beyond the 30%% line, target 50%% (ladder 30/50/70 = %.2f/%.2f/%.2f)",
                               (dir < 0) ? "bearish" : "bullish", lv.l30, lv.l50, lv.l70);
         score  = 70.0;
      }
      else if(env == CF_FUT_CONSOLIDATION)
      {
         //--- two-way tape: trade the EDGES, stay out of the MIDDLE
         if(!ConsolidationEdge(ctx, lv, dir, entry, stop, target)) return false;
         why   = (dir > 0) ? "consolidation lower-edge fade" : "consolidation upper-edge fade";
         score = 55.0;      // "the environment most likely to chop up swing traders" - ranked last
      }
      else return false;

      double riskDist = (dir > 0) ? entry - stop : stop - entry;
      if(riskDist <= 0.0) return false;

      plan.dir = dir; plan.entry = entry; plan.stop = stop; plan.target = target;
      plan.riskDist = riskDist; plan.barsAgo = 1; plan.score = score; plan.isLimit = false;
      plan.reason = why;

      //--- "smaller size if against the primary trend" - consumed by LotsMultiplier() on this fill
      m_sizeMult = counter ? InpCounterTrendRiskMult : 1.0;
      m_smSymbol = ctx.symbol; m_smEntry = entry; m_smRisk = riskDist;
      //--- the anchored-VWAP anchor of this phase: the band peak (mean reversion) or the box start
      if(env == CF_FUT_MEANREV_BEAR || env == CF_FUT_MEANREV_BULL) m_anchorBars = (lv.peakBar > 1) ? lv.peakBar : InpConsRangeDays;
      else                                                          m_anchorBars = InpConsRangeDays;
      return true;
   }

   //--- the document says smaller size against the primary trend; the engine calls this at fill time
   double LotsMultiplier(SEAContext &ctx)
   {
      if(m_smSymbol != ctx.symbol || m_smRisk <= 0.0) return 1.0;
      if(MathAbs(ctx.mid - m_smEntry) > MathMax(m_smRisk * 0.5, ctx.atr * 0.25)) return 1.0;  // stale plan
      return m_sizeMult;
   }

   //--- "Trade management & exits": the document's own tools, nothing invented
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
         double moveR = (dir > 0) ? ctx.mid - entry : entry - ctx.mid;
         double risk  = MathAbs(entry - PositionGetDouble(POSITION_SL));
         if(risk <= 0.0) continue;
         bool inProfit = (moveR > 0.0);

         //--- "typical holding time: 1 to 5 trading days"
         if(InpMaxHoldDays > 0 && inProfit)
         {
            datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
            if(opened > 0 && TradingDaysSince(opened) > InpMaxHoldDays)
            {
               if(g_eaExec.Close(ticket, StringFormat("max hold %d days reached", InpMaxHoldDays)))
                  EA_Log(EA_LOG_EVENTS, "swing window elapsed - position closed", true);
               continue;
            }
         }

         if(!inProfit || moveR < InpPartial1AtR * risk * 0.5) continue;   // exits below are protective, not forced

         //--- "8/21/34 moving averages (exit context, not entry signals)":
         //--- a daily close on the wrong side of BOTH the 8 and the 21 average ends the context
         if(InpUseMaExitContext && MaContextBroken(ctx, dir))
         {
            if(g_eaExec.Close(ticket, "daily close lost the 8/21 context"))
               EA_Log(EA_LOG_EVENTS, "exit context: daily close broke the 8/21 averages", true);
            continue;
         }

         //--- "anchored VWAP: can it stay below VWAP?" - the bear case, mirrored for longs
         if(InpUseAnchoredVwap)
         {
            double av = AnchoredVwap(ctx.symbol);
            if(av > 0.0)
            {
               double lastClose = LastDailyClose(ctx.symbol);
               if(dir < 0 && lastClose > av)
               {
                  if(g_eaExec.Close(ticket, "daily close back above the anchored VWAP"))
                     EA_Log(EA_LOG_EVENTS, "anchored VWAP lost - position closed", true);
                  continue;
               }
               if(dir > 0 && lastClose < av)
               {
                  if(g_eaExec.Close(ticket, "daily close back below the anchored VWAP"))
                     EA_Log(EA_LOG_EVENTS, "anchored VWAP lost - position closed", true);
               }
            }
         }
      }
   }

private:
   double m_sizeMult;
   string m_smSymbol;
   double m_smEntry;
   double m_smRisk;

   //-------------------------------------------------------------------
   // Environment classification: the daily chart answers one question
   //-------------------------------------------------------------------
   bool Classify(SEAContext &ctx, ENUM_CF_FUT_ENV &env, SFutLevels &lv, bool &counter)
   {
      env = CF_FUT_UNCLEAR; lv.Reset(); counter = false;
      MqlRates d[];
      int need = InpBbPeriod + InpPeakLookbackDays + InpLegLookbackDays + InpPeakWin + 10;
      int got  = EA_Rates(ctx.symbol, PERIOD_D1, 0, need, d);
      if(got < InpBbPeriod + InpPeakLookbackDays + 5) return false;

      //--- Bollinger 20 / 3 sigma over completed D1 bars (band at bar i uses closes i..i+19)
      int n = got - InpBbPeriod;                       // highest usable bar index for a full window
      double bw[256];
      double bbUp[256], bbLo[256];
      if(n > 256) n = 256;
      for(int i = 1; i < n; i++)
      {
         double sum = 0.0;
         for(int k = i; k < i + InpBbPeriod; k++) sum += d[k].close;
         double mid = sum / InpBbPeriod;
         double sq = 0.0;
         for(int k = i; k < i + InpBbPeriod; k++) sq += (d[k].close - mid) * (d[k].close - mid);
         double sd = MathSqrt(sq / InpBbPeriod);
         bbUp[i] = mid + InpBbDeviations * sd;
         bbLo[i] = mid - InpBbDeviations * sd;
         bw[i]   = (mid > 0.0) ? (bbUp[i] - bbLo[i]) / mid : 0.0;
      }
      if(n < 6) return false;

      //--- the document's whole framework runs on the daily trigger and the daily close
      double d1Close = d[1].close;
      double d1Mid   = (bbUp[1] + bbLo[1]) * 0.5;
      double avgBw   = 0.0;
      int    avgN    = MathMin(n - 1, 20);
      for(int i = 1; i <= avgN; i++) avgBw += bw[i];
      if(avgN <= 0) return false;
      avgBw /= avgN;

      bool contracting = (bw[1] <= bw[2] && bw[1] < avgBw * InpContractRatio);
      bool expanding   = (bw[1] > bw[2]  && bw[1] > avgBw * InpExpandRatio);

      //--- the most recent Bollinger-band peak: a local bandwidth maximum
      int pk = 0;
      for(int i = 1; i <= InpPeakLookbackDays && i < n; i++)
      {
         bool isPeak = true;
         for(int j = i - InpPeakWin; j <= i + InpPeakWin; j++)
         {
            if(j < 1 || j >= n || j == i) continue;
            if(bw[j] > bw[i]) { isPeak = false; break; }
         }
         if(isPeak) { pk = i; break; }
      }

      //--- the primary trend (for "smaller size if against the primary trend" and the posture rule)
      double ma8 = Sma(d, 8), ma21 = Sma(d, 21), ma34 = Sma(d, 34);
      bool primaryUp   = (ma8 > ma21 && ma21 > ma34 && d1Close > ma34);
      bool primaryDown = (ma8 < ma21 && ma21 < ma34 && d1Close < ma34);

      //--- the unfinished-business target: the prior band peak's price extreme
      if(pk > 0)
      {
         lv.peakBar  = pk;
         double top  = -DBL_MAX, bot = DBL_MAX, olderTop = -DBL_MAX, olderBot = DBL_MAX;
         for(int i = 1; i <= pk; i++)                     // at/after the peak: the leg's extreme
         {
            top = MathMax(top, d[i].high);
            bot = MathMin(bot, d[i].low);
         }
         for(int i = pk; i <= pk + InpLegLookbackDays && i < got; i++)   // before the peak: the leg's origin
         {
            olderTop = MathMax(olderTop, d[i].high);
            olderBot = MathMin(olderBot, d[i].low);
         }
         lv.peakHigh = (top  > -DBL_MAX) ? top  : 0.0;
         lv.legLow   = (olderBot < DBL_MAX) ? olderBot : 0.0;
         lv.troughLow= (bot < DBL_MAX) ? bot : 0.0;
         lv.legHigh  = (olderTop > -DBL_MAX) ? olderTop : 0.0;
         lv.legUp    = (d[pk].close > d1Mid);            // the band peaked while price was in the upper half
      }

      //--- consolidation box for both the edge trades and the expansion breakout
      if(!SigDonchian(ctx.symbol, InpConsRangeDays, lv.consHi, lv.consLo)) return false;
      if(lv.consHi <= lv.consLo) return false;

      //--- 1) mean reversion: contracting AFTER a band peak, with the leg's fib levels
      if(pk > 0 && contracting && bw[1] < bw[pk])
      {
         if(lv.legUp && lv.peakHigh > lv.legLow)
         {
            double span = lv.peakHigh - lv.legLow;
            lv.l30 = lv.peakHigh - InpBeacon30 * span;
            lv.l50 = lv.peakHigh - InpBeacon50 * span;
            lv.l70 = lv.peakHigh - InpBeacon70 * span;
            env = CF_FUT_MEANREV_BEAR;
            counter = primaryUp;                          // shorting into an up market = counter-trend
            return true;
         }
         if(!lv.legUp && lv.legHigh > lv.troughLow)
         {
            double span = lv.legHigh - lv.troughLow;
            lv.l30 = lv.troughLow + InpBeacon30 * span;
            lv.l50 = lv.troughLow + InpBeacon50 * span;
            lv.l70 = lv.troughLow + InpBeacon70 * span;
            env = CF_FUT_MEANREV_BULL;
            counter = primaryDown;
            return true;
         }
      }

      //--- 2) expansion: bands expanding out of the box, price tagging the extreme band
      if(expanding)
      {
         bool tagsUpper = (d[1].high >= bbUp[1] || d1Close > bbUp[1]);
         bool tagsLower = (d[1].low  <= bbLo[1] || d1Close < bbLo[1]);
         if(d1Close > d1Mid && d1Close > lv.consHi && tagsUpper)
         {
            env = CF_FUT_EXPANSION_BULL;
            return true;
         }
         if(d1Close < d1Mid && d1Close < lv.consLo && tagsLower)
         {
            env = CF_FUT_EXPANSION_BEAR;
            return true;
         }
      }

      //--- 3) consolidation: contracting / flat bands, price inside the box
      if(contracting || bw[1] < avgBw)
      {
         if(d1Close <= lv.consHi && d1Close >= lv.consLo)
         {
            env = CF_FUT_CONSOLIDATION;
            return true;
         }
      }
      return true;      // UNCLEAR is a state: the document says sometimes the correct trade is no trade
   }

   //-------------------------------------------------------------------
   // Consolidation: trade the edges, stay out of the middle
   //-------------------------------------------------------------------
   bool ConsolidationEdge(SEAContext &ctx, const SFutLevels &lv, int &dir, double &entry, double &stop, double &target)
   {
      dir = 0; entry = stop = target = 0.0;
      double width = lv.consHi - lv.consLo;
      if(width <= 0.0) return false;
      double zone = width * InpEdgeZonePct;

      MqlRates m[];
      if(EA_Rates(ctx.symbol, g_eaIndTf, 0, 3, m) < 2) return false;
      double range = m[1].high - m[1].low;
      if(range <= 0.0) return false;
      double lowerWick = MathMin(m[1].open, m[1].close) - m[1].low;
      double upperWick = m[1].high - MathMax(m[1].open, m[1].close);

      //--- the middle is where the tape chops: an entry must come from an edge
      if(ctx.mid <= lv.consLo + zone && lowerWick >= InpWickRatio * range && m[1].close > m[1].open)
      {
         dir   = +1;
         entry = ctx.ask;
         stop  = lv.consLo - InpStopBufferAtr * ctx.atrD1;
         double risk = entry - stop;
         if(risk <= 0.0) return false;
         if((risk / entry) * 100.0 > InpMaxStopPct) return false;
         double mid = (lv.consHi + lv.consLo) * 0.5;             // reversion back into the range
         target = (mid > entry + risk) ? mid : entry + InpTargetR * risk;
         return true;
      }
      if(ctx.mid >= lv.consHi - zone && upperWick >= InpWickRatio * range && m[1].close < m[1].open)
      {
         dir   = -1;
         entry = ctx.bid;
         stop  = lv.consHi + InpStopBufferAtr * ctx.atrD1;
         double risk = stop - entry;
         if(risk <= 0.0) return false;
         if((risk / entry) * 100.0 > InpMaxStopPct) return false;
         double mid = (lv.consHi + lv.consLo) * 0.5;
         target = (mid < entry - risk) ? mid : entry - InpTargetR * risk;
         return true;
      }
      return false;
   }

   //--- The structural stop: the nearest DAILY swing point beyond the entry ("above a key
   //--- high, below a key low").  The engine's SigFractals is hard-wired to the signal
   //--- timeframe (M30 here), and the document's key levels are swing structure, so the same
   //--- 3-bar fractal geometry is applied to the daily bars locally.
   double KeyLevel(const SEAContext &ctx, const int dir, const SFutLevels &lv)
   {
      MqlRates d[];
      int got = EA_Rates(ctx.symbol, PERIOD_D1, 1, InpSwingCount * 6, d);   // completed days only
      if(got < 10) return (dir > 0) ? lv.consLo : lv.consHi;
      double best = 0.0;
      for(int i = 2; i < got - 2; i++)
      {
         //--- fractal high/low: strictly beyond its two neighbours on each side
         bool fracHigh = (d[i].high > d[i + 1].high && d[i].high > d[i + 2].high &&
                          d[i].high > d[i - 1].high && d[i].high > d[i - 2].high);
         bool fracLow  = (d[i].low  < d[i + 1].low  && d[i].low  < d[i + 2].low  &&
                          d[i].low  < d[i - 1].low  && d[i].low  < d[i - 2].low);
         if(dir > 0 && fracLow && d[i].low < ctx.mid && (best == 0.0 || d[i].low > best))
            best = d[i].low;
         if(dir < 0 && fracHigh && d[i].high > ctx.mid && (best == 0.0 || d[i].high < best))
            best = d[i].high;
      }
      if(best == 0.0) best = (dir > 0) ? lv.consLo : lv.consHi;    // fallback: the prior box edge
      return best;
   }

   //--- targets inside expansion: "unfinished business" first, then the week extreme, then R
   double LevelTarget(const SEAContext &ctx, const int dir, const double entry, const double risk, const SFutLevels &lv)
   {
      double unfinished = 0.0;
      if(lv.peakBar > 0)
         unfinished = (dir > 0) ? lv.peakHigh : lv.troughLow;
      double wHi = 0.0, wLo = 0.0;
      bool haveWeek = SigDonchian(ctx.symbol, 5, wHi, wLo);
      double weekLevel = haveWeek ? ((dir > 0) ? wHi : wLo) : 0.0;

      double best = 0.0;
      if(dir > 0)
      {
         if(unfinished > entry + risk) best = unfinished;
         if(weekLevel > entry + risk && (best == 0.0 || weekLevel < best)) best = weekLevel;   // nearest objective
      }
      else
      {
         if(unfinished > 0.0 && unfinished < entry - risk) best = unfinished;
         if(weekLevel > 0.0 && weekLevel < entry - risk && (best == 0.0 || weekLevel > best)) best = weekLevel;
      }
      if(best == 0.0) best = (dir > 0) ? entry + InpTargetR * risk : entry - InpTargetR * risk;
      return best;
   }

   //-------------------------------------------------------------------
   // The document's exit-context tools
   //-------------------------------------------------------------------
   bool MaContextBroken(const SEAContext &ctx, const int dir)
   {
      MqlRates d[];
      if(EA_Rates(ctx.symbol, PERIOD_D1, 0, 40, d) < 35) return false;
      double ma8 = Sma(d, 8), ma21 = Sma(d, 21), ma34 = Sma(d, 34);
      if(ma8 <= 0.0 || ma21 <= 0.0 || ma34 <= 0.0) return false;
      double c = d[1].close;
      //--- "exit context, not entry signals": the context is lost when the daily close is on the
      //--- wrong side of both the fast pair and the middle average
      if(dir > 0) return (c < ma8 && c < ma21 && ma8 < ma21 && ma21 < ma34);
      return (c > ma8 && c > ma21 && ma8 > ma21 && ma21 > ma34);
   }

   //--- `[interpretation]`: the anchor is the phase anchor (band peak / box start), tick volume
   //--- stands in for traded volume, and the deviation bands are represented by the 1R partial.
   double AnchoredVwap(const string sym)
   {
      MqlRates d[];
      int got = EA_Rates(sym, PERIOD_D1, 0, InpPeakLookbackDays + InpLegLookbackDays + 5, d);
      if(got < 6) return 0.0;
      int anchor = m_anchorBars;
      if(anchor < 2) anchor = InpConsRangeDays;
      if(anchor >= got) anchor = got - 1;
      double pv = 0.0, vol = 0.0;
      for(int i = 1; i <= anchor; i++)
      {
         double typical = (d[i].high + d[i].low + d[i].close) / 3.0;
         double v = (double)d[i].tick_volume;
         pv  += typical * v;
         vol += v;
      }
      if(vol <= 0.0) return 0.0;
      return pv / vol;
   }

   double LastDailyClose(const string sym)
   {
      MqlRates d[];
      if(EA_Rates(sym, PERIOD_D1, 0, 3, d) < 2) return 0.0;
      return d[1].close;
   }

   //--- "1 to 5 trading days": count Mon-Fri days between the open and now, weekends never count
   int TradingDaysSince(const datetime from)
   {
      datetime now = TimeTradeServer();
      if(from <= 0 || now <= from) return 0;
      int days = 0;
      for(datetime t = from; t < now && days < 400; t += 86400)
      {
         MqlDateTime dt;
         if(!TimeToStruct(t, dt)) break;
         if(dt.day_of_week >= 1 && dt.day_of_week <= 5) days++;
      }
      return days;
   }

   double Sma(MqlRates &r[], const int period)
   {
      if(period <= 0 || ArraySize(r) < period + 1) return 0.0;
      double sum = 0.0;
      for(int i = 1; i <= period; i++) sum += r[i].close;
      return sum / period;
   }

   //--- anchor used by AnchoredVwap(): the phase anchor of the live setup (band peak / box start)
   int m_anchorBars;
};

CCfFuturesStrategy g_cfFuturesStrategy;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfFuturesStrategy);
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
