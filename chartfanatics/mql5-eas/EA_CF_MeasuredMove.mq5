//+------------------------------------------------------------------+
//|                                     EA_CF_MeasuredMove.mq5       |
//|                                  Copyright 2026, Master Strategy |
//|                                                                    |
//| Marci Silfrain's Measured Move Trend Strategy (PDF, Apr 2025)      |
//| Card    : chartfanatics/todos/measured-move-trend-strategy.md (#23)|
//| Source  : chartfanatics/pdf/measured-move-trend-strategy.pdf       |
//| Magic   : 3226                                                     |
//|                                                                    |
//| THE MODEL: price moves in repeating, measured patterns within a    |
//| trend.  Measure how far price retraces during a pullback and use   |
//| that same distance to project the continuation.                    |
//|                                                                    |
//|   THE "LITTLE RZY" STRUCTURE (downtrend; mirrored uptrend):         |
//|   (1) a strong move down (the impulse), then a bounce;              |
//|   (2) a trendline is drawn across the pullback HIGHS;                |
//|   (3) the structure's LOWEST LOW is measured straight up to that     |
//|       trendline - that distance is the measured move;                |
//|   (4) the same distance is projected DOWN from the low = the target; |
//|   (5) the entry waits for the pullback to reject the trendline and   |
//|       price to start moving back with the trend - never during the   |
//|       impulse;                                                       |
//|   (6) the stop sits above the trendline / the recent swing high      |
//|       ("avoid placing stops too tight"); a confirmed CLOSE beyond it |
//|       invalidates the structure;                                     |
//|   (7) the primary target is the measured move and the core idea is   |
//|       to let the full move play out;                                  |
//|   (8) Bollinger Bands are context: in a downtrend, structures that    |
//|       form near the UPPER band are the higher-probability ones;       |
//|   (9) the first one or two structures in a fresh trend are the        |
//|       strongest - by the fourth or fifth the move is often exhausted  |
//|       and shrinking structures are a warning;                         |
//|  (10) the setup is invalid when price closes beyond the trendline,    |
//|       the structure is too extended/irregular, or price collapses     |
//|       without forming a proper pullback.                              |
//|                                                                    |
//| `[interpretation]`: the document draws trendlines by eye, so the      |
//| mechanical reading is fixed here and labelled - the trend and the      |
//| swing anchors come from fractal swings on the structure timeframe,     |
//| the trendline is the line through the two most recent pullback highs   |
//| (lows for longs) and the measured distance is that line's value at     |
//| the structure low; the 2-sigma Bollinger setting, the structure count  |
//| limit, the trigger freshness window and the stop buffer are numbers    |
//| the document does not state.  The document also describes bottoms       |
//| ("anticipate reversals rather than react to them"), which is the       |
//| mirrored long structure - the same code path with the trend flipped.    |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "Measured move trend - Little RZY structures, trendline measurement, projected continuation target, structure-based stop"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade   = "US100,US500";     // stocks / futures / crypto (the doc's list)
input ulong             InpMagicNumber      = 3226;              // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct          = 0.50;              // Risk per trade (% of equity)
input int               InpStage             = 5;                // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input int               InpServerGmtOffset  = 2;                 // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;     // Log verbosity
input double            InpCommissionPerLotRT = 0.0;             // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.12;            // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;            // Write the engine evidence ledger CSV
//--- structure detection
input ENUM_TIMEFRAMES InpStructTf     = PERIOD_H4;  // "most effective on higher timeframes"
input int    InpSwingBars      = 240;    // structure bars scanned for swings
input int    InpFractalBars    = 2;      // swing strength
input int    InpMinPullbackBars = 2;     // a proper pullback must exist ("price collapses sharply without ... a pullback")
input int    InpMaxStructBars  = 80;     // "too extended or irregular" - the structure may not span more than this
input int    InpTriggerBars    = 6;      // the rejection must be fresh
input double InpTlTouchAtr     = 0.60;   // the pullback must reach this close to the trendline
//--- exhaustion (rule 9)
input int    InpMaxStructures  = 3;      // "by the fourth or fifth pattern the move often becomes exhausted"
input bool   InpShrinkIsWarning = true;  // "when the structures become smaller ... the trend may be ending"
//--- Bollinger context (rule 8)
input int    InpBbPeriod       = 20;
input double InpBbMult         = 2.0;    // the standard 2-sigma setting
input bool   InpRequireStretch = false;  // optional gate: only the structures the doc calls higher probability
//--- stop / target
input double InpStopBufferAtr  = 0.20;   // "avoid placing stops too tight"
input double InpMinRr          = 1.50;   // the measured move must be worth the structure stop
//--- trend filter
input bool   InpUseDailyContext = true;  // the higher-timeframe direction (the doc's top-down note)

//+------------------------------------------------------------------+
class CCfMeasuredMove : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_MEASURED_MOVE";
      cfg.sourceDoc             = "chartfanatics/pdf/measured-move-trend-strategy.pdf (card #23)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = InpStructTf;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = 3.0;
      cfg.dailyLossPct          = 1.50;
      cfg.weeklyLossPct         = 3.0;
      cfg.totalDdPct            = 8.0;
      cfg.maxTradesPerDay       = 2;              // [interpretation]: the doc sets no daily cap
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 120;
      cfg.signalOnNewBarOnly    = true;           // the structure is judged on completed bars
      cfg.useLimitEntry         = false;
      cfg.newsFilter            = false;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_measured_move_ledger.csv";
      cfg.logLevel              = InpLogLevel;
      //--- swing trading: no session gate; the entry comes when the structure rejects
      cfg.sessionStartHour = 0;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour   = 0;   cfg.sessionEndMin   = 0;   // from == to -> the engine treats it as all day
      cfg.noTradeAfterHour = -1;
      //--- "partial exits can be considered, but the core idea is to allow the full move to play out"
      cfg.partial1AtR      = 0.0;
      cfg.breakEvenAtR     = 0.0;
      cfg.trailAtR         = 0.0;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   void OnInitStrategy()
   {
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "measured move armed: %s Little RZY structures (fractal %d), trendline across the pullback extremes, measured move projected from the structure low, stop beyond the line/swing, structures beyond %d skipped",
             EnumToString(InpStructTf), InpFractalBars, InpMaxStructures), true);
   }

   //-------------------------------------------------------------------
   // Trend -> structure -> measurement -> rejection
   //-------------------------------------------------------------------
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(ctx.atr <= 0.0) return false;

      for(int dir = -1; dir <= 1; dir += 2)                 // the downtrend (short) case first, as documented
      {
         double structLow = 0.0, structHigh = 0.0, measure = 0.0, lineNow = 0.0;
         int    anchorBar = 0, structBars = 0, structures = 0;
         if(!LittleRzy(ctx.symbol, dir, structLow, structHigh, measure, lineNow, anchorBar, structBars, structures)) continue;

         //--- (9) exhaustion: the first one or two structures are the strongest
         if(structures > InpMaxStructures) continue;

         //--- (8) Bollinger context
         double bbMid = 0.0, bbUp = 0.0, bbLo = 0.0;
         Bollinger(ctx.symbol, bbMid, bbUp, bbLo);
         bool stretched = false;
         if(bbUp > bbLo)
            stretched = (dir < 0) ? (structHigh >= bbUp * 0.999)      // a downtrend structure near the upper band
                                  : (structLow  <= bbLo * 1.001);     // an uptrend structure near the lower band
         if(InpRequireStretch && !stretched) continue;

         //--- (10) invalidation: a confirmed close beyond the trendline kills the structure
         if(dir < 0 && ctx.mid > lineNow) continue;
         if(dir > 0 && ctx.mid < lineNow) continue;

         //--- the measured move and the structure stop
         double entry = (dir > 0) ? ctx.ask : ctx.bid;
         double target = (dir > 0) ? (structHigh + measure) : (structLow - measure);
         double stopRef = (dir > 0) ? MathMin(structLow,  lineNow) : MathMax(structHigh, lineNow);
         double stop = (dir > 0) ? stopRef - InpStopBufferAtr * ctx.atr
                                 : stopRef + InpStopBufferAtr * ctx.atr;
         double risk = (dir > 0) ? (entry - stop) : (stop - entry);
         if(risk <= 0.0) continue;
         double rr = MathAbs(target - entry) / risk;
         if(rr < InpMinRr) continue;

         plan.dir      = dir;
         plan.entry    = entry;
         plan.stop     = stop;
         plan.target   = target;
         plan.riskDist = risk;
         plan.barsAgo  = 1;
         plan.score    = 68.0 + (stretched ? 8.0 : 0.0) + ((structures <= 2) ? 6.0 : 0.0);
         plan.isLimit  = false;
         plan.reason   = StringFormat("Little RZY %s structure (%d in the trend): measured move %.2f projected from the %s, trendline %.2f, stop %.2f, %.2fR",
                                      (dir > 0) ? "bullish" : "bearish", structures, measure,
                                      (dir > 0) ? "high" : "low", lineNow, stop, rr);
         return true;
      }
      return false;
   }

   //-------------------------------------------------------------------
   // Rule 6/10: a confirmed close beyond the trendline invalidates the
   // structure - leave instead of waiting for the stop
   //-------------------------------------------------------------------
   void Manage(SEAContext &ctx)
   {
      if(ctx.atr <= 0.0) return;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong ticket = PositionGetTicket(p);
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;

         int dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? +1 : -1;
         double lineNow = 0.0;
         if(!TrendlineNow(ctx.symbol, dir, lineNow)) continue;
         MqlRates m[];
         if(EA_Rates(ctx.symbol, g_eaIndTf, 0, 3, m) < 3) continue;
         bool confirmed = (dir < 0) ? (m[1].close > lineNow) : (m[1].close < lineNow);
         if(!confirmed) continue;
         EA_Log(EA_LOG_EVENTS, StringFormat("a bar closed beyond the trendline (%.2f) - the structure is invalid, exiting", lineNow), true);
         g_eaExec.Close(ticket, "trendline invalidated");
      }
   }

private:
   //-------------------------------------------------------------------
   // The structure: trend, swing anchors, trendline, measurement
   //-------------------------------------------------------------------
   bool LittleRzy(const string sym, const int dir, double &structLow, double &structHigh,
                  double &measure, double &lineNow, int &anchorBar, int &structBars, int &structures)
   {
      structLow = 0.0; structHigh = 0.0; measure = 0.0; lineNow = 0.0;
      anchorBar = 0; structBars = 0; structures = 0;

      MqlRates r[];
      int got = EA_Rates(sym, InpStructTf, 0, InpSwingBars + 4, r);
      if(got < InpFractalBars * 4 + 8) return false;

      //--- collect fractal swings (newest first), separated by the fractal strength
      double  sh[], sl[];
      int     shBar[], slBar[];
      if(!Swings(r, got, sh, shBar, sl, slBar)) return false;
      int nh = ArraySize(sh), nl = ArraySize(sl);
      if(nh < 2 || nl < 1) return false;

      //--- (1) the trend: lower highs AND lower lows - or the mirror for an uptrend
      bool trendOk = false;
      if(dir < 0) trendOk = (sh[0] < sh[1]);
      else        trendOk = (sh[0] > sh[1]);
      if(nl >= 2)
      {
         if(dir < 0) trendOk = trendOk && (sl[0] < sl[1]);
         else        trendOk = trendOk && (sl[0] > sl[1]);
      }
      if(!trendOk) return false;

      //--- structure count: how many descending swing highs run into the current one
      structures = CountStructures(sh, dir);

      //--- (2)+(3) the trendline across the two newest pullback highs (lows for longs)
      double a1 = sh[1], a2 = sh[0];                 // price anchors, newest second
      int    b1 = shBar[1], b2 = shBar[0];           // bar indices
      if(dir > 0)
      {
         if(nl < 2) return false;
         a1 = sl[1]; a2 = sl[0];                     // the two newest pullback lows
         b1 = slBar[1]; b2 = slBar[0];
      }
      if(b1 == b2) return false;

      //--- the structure extreme sits between (or at the newer end of) the anchors
      double ext = (dir < 0) ? DBL_MAX : -DBL_MAX;
      int    extBar = 0;
      int    from = MathMin(b1, b2), to = MathMax(b1, b2);
      for(int i = to; i >= from && i >= 1; i--)
      {
         if(dir < 0) { if(r[i].low < ext) { ext = r[i].low; extBar = i; } }
         else        { if(r[i].high > ext) { ext = r[i].high; extBar = i; } }
      }
      if(extBar == 0) return false;
      structBars = to - from;
      if(structBars > InpMaxStructBars) return false;                 // "too extended or irregular"
      if(structBars < InpMinPullbackBars) return false;               // "without forming a proper pullback"

      //--- (4) the measurement: the trendline's value at the structure extreme
      double lineAtExt = ValueOnLine(b1, a1, b2, a2, extBar);
      measure = (dir < 0) ? (lineAtExt - ext) : (ext - lineAtExt);
      if(measure <= 0.0) return false;

      //--- (9) "when the structures become smaller ... this signals that the trend may be ending"
      if(InpShrinkIsWarning && nh >= 2 && nl >= 2)
      {
         double prevHeight = MathAbs(sh[1] - sl[1]);
         double curHeight  = MathAbs(sh[0] - sl[0]);
         if(prevHeight > 0.0 && curHeight < 0.7 * prevHeight) return false;
      }

      //--- (5) the pullback must have reached the trendline, and the newest bar must be rejecting it
      lineNow = ValueOnLine(b1, a1, b2, a2, 1);
      MqlRates m[];
      if(EA_Rates(sym, InpStructTf, 0, InpTriggerBars + 3, m) < InpTriggerBars + 2) return false;

      double touchTol = InpTlTouchAtr * StructureAtr(sym);   // "the pullback must reach the trendline"
      bool touched = false;
      for(int i = 1; i <= InpTriggerBars && i < got - 1; i++)
      {
         double lineAtI = ValueOnLine(b1, a1, b2, a2, i);
         if(dir < 0 && m[i].high >= lineAtI - touchTol) { touched = true; break; }
         if(dir > 0 && m[i].low  <= lineAtI + touchTol) { touched = true; break; }
      }
      if(!touched) return false;

      //--- the rejection: the newest completed bar turns back with the trend
      bool reject = (dir < 0) ? (m[1].close < m[1].open && m[1].close < m[2].low)
                              : (m[1].close > m[1].open && m[1].close > m[2].high);
      if(!reject) return false;

      //--- (7) the daily context the doc asks for
      if(InpUseDailyContext && !DailyContext(sym, dir)) return false;

      //--- the stop anchors: the structure extreme and the pullback anchor on the trendline side
      if(dir < 0) { structLow = ext;  structHigh = a2; }    // short: low = the structure low, high = the pullback high
      else        { structHigh = ext; structLow  = a2; }    // long: mirrored
      anchorBar = extBar;
      return true;
   }

   //--- fractal swings, newest first
   bool Swings(const MqlRates &r[], const int got, double &sh[], int &shBar[], double &sl[], int &slBar[])
   {
      ArrayResize(sh, 0); ArrayResize(shBar, 0);
      ArrayResize(sl, 0); ArrayResize(slBar, 0);
      for(int k = InpFractalBars + 1; k <= got - InpFractalBars - 1; k++)
      {
         bool isHigh = true, isLow = true;
         for(int j = 1; j <= InpFractalBars; j++)
         {
            if(r[k + j].high >= r[k].high || r[k - j].high >= r[k].high) isHigh = false;
            if(r[k + j].low  <= r[k].low  || r[k - j].low  <= r[k].low ) isLow  = false;
         }
         if(isHigh)
         {
            int n = ArraySize(sh);
            ArrayResize(sh, n + 1); ArrayResize(shBar, n + 1);
            sh[n] = r[k].high; shBar[n] = k;
         }
         if(isLow)
         {
            int n = ArraySize(sl);
            ArrayResize(sl, n + 1); ArrayResize(slBar, n + 1);
            sl[n] = r[k].low; slBar[n] = k;
         }
      }
      return (ArraySize(sh) >= 2 && ArraySize(sl) >= 1);
   }

   //--- how many descending (ascending) highs run into the newest swing high
   int CountStructures(const double &sh[], const int dir)
   {
      int n = ArraySize(sh);
      int count = 1;
      for(int i = 1; i < n; i++)
      {
         bool step = (dir < 0) ? (sh[i] < sh[i - 1]) : (sh[i] > sh[i - 1]);
         if(!step) break;
         count++;
      }
      return count;
   }

   //--- the line through (bar b1, price a1) and (bar b2, price a2), evaluated at bar `at`
   double ValueOnLine(const int b1, const double a1, const int b2, const double a2, const int at)
   {
      if(b1 == b2) return a1;
      double slope = (a2 - a1) / (double)(b2 - b1);
      return a1 + slope * (double)(at - b1);
   }

   double StructureAtr(const string sym)
   {
      MqlRates r[];
      int got = EA_Rates(sym, InpStructTf, 0, 20, r);
      if(got < 6) return 0.0;
      double sum = 0.0;
      int n = 0;
      for(int i = 1; i <= 14 && i < got - 1; i++)
      {
         double tr = MathMax(r[i].high - r[i].low,
                             MathMax(MathAbs(r[i].high - r[i + 1].close),
                                     MathAbs(r[i].low  - r[i + 1].close)));
         sum += tr; n++;
      }
      return (n > 0) ? sum / n : 0.0;
   }

   //--- the trendline value now, for the invalidation exit
   bool TrendlineNow(const string sym, const int dir, double &lineNow)
   {
      lineNow = 0.0;
      MqlRates r[];
      int got = EA_Rates(sym, InpStructTf, 0, InpSwingBars + 4, r);
      if(got < InpFractalBars * 4 + 8) return false;
      double sh[], sl[]; int shBar[], slBar[];
      if(!Swings(r, got, sh, shBar, sl, slBar)) return false;
      if(ArraySize(sh) < 2) return false;
      if(dir < 0) lineNow = ValueOnLine(shBar[1], sh[1], shBar[0], sh[0], 1);
      else
      {
         int nl = ArraySize(sl);
         if(nl < 2) return false;
         lineNow = ValueOnLine(slBar[nl - 1], sl[nl - 1], slBar[0], sl[0], 1);
      }
      return (lineNow > 0.0);
   }

   void Bollinger(const string sym, double &mid, double &up, double &lo)
   {
      mid = 0.0; up = 0.0; lo = 0.0;
      MqlRates r[];
      int got = EA_Rates(sym, InpStructTf, 0, InpBbPeriod + 3, r);
      if(got < InpBbPeriod + 2) return;
      double sum = 0.0;
      for(int i = 1; i <= InpBbPeriod; i++) sum += r[i].close;
      mid = sum / (double)InpBbPeriod;
      double var = 0.0;
      for(int i = 1; i <= InpBbPeriod; i++) var += MathPow(r[i].close - mid, 2.0);
      double sd = MathSqrt(var / (double)InpBbPeriod);
      up = mid + InpBbMult * sd;
      lo = mid - InpBbMult * sd;
   }

   //--- the doc's top-down note: the higher timeframe must agree
   bool DailyContext(const string sym, const int dir)
   {
      MqlRates d[];
      if(EA_Rates(sym, PERIOD_D1, 1, 4, d) < 3) return true;      // no daily data - do not block
      if(dir < 0) return (d[0].close < d[1].close);
      return (d[0].close > d[1].close);
   }
};

CCfMeasuredMove g_cfMeasuredMove;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfMeasuredMove);
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
