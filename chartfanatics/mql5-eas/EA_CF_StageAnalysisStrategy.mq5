//+------------------------------------------------------------------+
//|                                  EA_CF_StageAnalysisStrategy.mq5  |
//|                                  Copyright 2026, Master Strategy  |
//|                                                                   |
//| ChartFanatics: Stage Analysis Strategy (Ted Zhang)                 |
//| "The 4-Market Cycle Framework"                                     |
//| Card    : chartfanatics/todos/stage-analysis-strategy.md   (#36)   |
//| Source  : chartfanatics/glimpse/VDK200OHNSo.md                     |
//| Magic   : 3239                                                    |
//|                                                                   |
//| The framework is fully mechanical - four stages read from a        |
//| moving-average stack - and the document states its entry and exit  |
//| rules outright:                                                    |
//|                                                                   |
//|   S1  THE STACK: "Use 10, 20, 30, and 40-week simple moving        |
//|       averages.  In uptrends, they stack bullishly (10 > 20 > 30 > |
//|       40); in downtrends, bearishly (10 < 20 < 30 < 40).  When     |
//|       they converge and flatten, a transition is near."  The       |
//|       document also says the framework "applies to weekly, daily,  |
//|       hourly ... charts" - the stack timeframe is an input.        |
//|   S2  STAGE 2 (UPTREND - buy/hold): "Price builds higher lows and  |
//|       higher highs, surfing above all moving averages (10 > 20 >   |
//|       30 > 40)."                                                   |
//|   S3  STAGE 4 (DOWNTREND - avoid / short): "Price builds lower     |
//|       highs and lower lows, trading below the 10, 30, and 40-week  |
//|       moving averages with bearish alignment."                     |
//|   S4  STAGE 1/3 (BASING / TOPPING): "Price oscillates sideways;    |
//|       moving averages converge and slice through price" - the      |
//|       document says avoid these chop zones; the EA reads the       |
//|       convergence and the prior trend to tell them apart.          |
//|   S5  ENTRY (Stage 2): "Wait for price to close above all four     |
//|       moving averages (10, 20, 30, 40) with the 10 above the 20    |
//|       and 30.  Volume should confirm.  On the daily chart, look    |
//|       for a pullback to the 10/20 MA for a lower-risk entry."      |
//|   S6  THE FIRST MULTI-MONTH BASE: "After a big Stage 2 move, the   |
//|       first multi-month consolidation (base) often precedes the    |
//|       next leg up.  This is a high-probability entry point."       |
//|   S7  EXIT (Stage 3): "When price fails to make new highs, MAs     |
//|       flatten and converge, and price starts oscillating wide and  |
//|       loose, it is time to scale out.  Do not wait for Stage 4     |
//|       crash."                                                      |
//|   S8  STAGE 4 SHORT (the other half of the middle 68%): mirror of  |
//|       the Stage 2 rule - price under the whole stack with the      |
//|       bearish alignment, entered on a failed rally back to the     |
//|       10/20 MAs.                                                   |
//|   S9  THE STAGE 4 MEAN REVERSION (advanced, optional): "If a stock |
//|       crashes far below the 30/40-week MAs (Stage 4 extreme), it   |
//|       may bounce back to those MAs" - a bounce trade toward the    |
//|       MAs, not a Stage 2 entry.                                    |
//|                                                                   |
//| The Livermore line - "Forget the first and last eighth of a move;  |
//| catch the middle 68%" - is encoded as: never enter during the      |
//| convergence zones (Stages 1 and 3) and never hold into them; the   |
//| stack must be open and aligned before risk is taken.               |
//|                                                                   |
//| `[interpretation]`: "45 degree" steepness, "flatten" and           |
//| "converge" percentages, the volume-confirmation multiple, the      |
//| pullback tolerance, the base length and tightness, the big-move    |
//| threshold, the fail-high window, the extreme-distance percentage   |
//| for the mean reversion and the stop buffers are inputs and         |
//| labelled - the document draws them by eye.                         |
//|                                                                   |
//| Disclosed, not faked: the narrative/catalyst layer ("price +       |
//| story + catalyst"), the screening of sector ETFs for market        |
//| health and the visual chart reps stay human; the EA trades the     |
//| stage mechanics alone, as the document allows ("this is not        |
//| prediction; it is probabilistic thinking").                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics Stage Analysis (Ted Zhang) - the 4-stage MA-stack framework with Stage 2 entries, the first-base setup, the Stage 3 scale-out and the Stage 4 short"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade     = "AAPL,MSFT,NVDA";  // Universe (the framework is universal; stocks by default)
input ulong             InpMagicNumber        = 3239;             // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct            = 0.40;             // Risk per trade (% of equity)
input int               InpStage              = 5;                // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input double            InpMaxSpreadPoints    = 5.0;              // Spread gate in points (0 = off)
input double            InpDailyLossPct       = 1.50;             // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset    = 2;                // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel           = EA_LOG_EVENTS;    // Log verbosity
input double            InpCommissionPerLotRT = 0.0;              // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.12;             // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;             // Write the engine evidence ledger CSV

//--- the stack (S1)
input ENUM_TIMEFRAMES   InpMaTf               = PERIOD_D1;        // The stack timeframe (weekly / daily / hourly - fractal)
input int               InpMa1                = 10;               // The 10-period simple moving average
input int               InpMa2                = 20;               // The 20
input int               InpMa3                = 30;               // The 30
input int               InpMa4                = 40;               // The 40
input double            InpConvergePct        = 2.0;              // [interpretation] "flatten and converge" spread (% of price)

//--- the entries (S5, S6)
input bool              InpAllowLongs         = true;             // Stage 2 longs
input bool              InpAllowShorts        = true;             // Stage 4 shorts
input bool              InpUseBreakout        = true;             // The transition entry (close above the whole stack)
input bool              InpUsePullback        = true;             // The preferred lower-risk pullback into the 10/20
input double            InpVolMult            = 1.30;             // "Volume should confirm"
input double            InpPullbackTolPct     = 1.00;             // [interpretation] The touch tolerance for the pullback
input int               InpBigMoveLookback     = 250;             // [interpretation] The "big Stage 2 move" window
input double            InpBigMovePct         = 100.0;            // [interpretation] ... and its minimum (%)
input int               InpBaseBars           = 30;               // "the first multi-month consolidation"
input double            InpBaseMaxPct         = 15.0;             // [interpretation] Base tightness (% of price)
input double            InpStopBufferAtr      = 0.20;             // [interpretation] Buffer beyond the structural stop
input double            InpTargetR            = 8.0;              // [interpretation] Far TP placeholder - the stage exit is the real exit
input double            InpMaxStopPct         = 25.0;             // [interpretation] Reject stops wider than x% of price

//--- the Stage 3 exit (S7)
input double            InpScaleOutPct        = 50.0;             // "it is time to scale out"
input int               InpFailHighBars       = 20;               // [interpretation] "fails to make new highs" window
input bool              InpExitOnMa3Break     = true;             // Exit the rest when a close loses the 30-period MA

//--- the Stage 4 mean reversion (S9, advanced/optional)
input bool              InpUseMeanReversion   = false;            // The document marks this an advanced, separate trade
input double            InpExtremeBelowPct    = 20.0;             // [interpretation] "crashes far below the 30/40" (%)

//--- session (entries timed in the US day, positions held for weeks)
input int               InpSessionStartHour   = 14;               // US RTH open, London time (09:30 ET)
input int               InpSessionStartMin    = 30;
input int               InpSessionEndHour     = 21;               // US RTH close
input int               InpSessionEndMin      = 0;
input int               InpMaxTradesPerDay    = 2;                // [interpretation] Swing entries are rare

//+------------------------------------------------------------------+
struct SStageCtx
{
   int    stage;          // 1 basing, 2 uptrend, 3 topping, 4 downtrend, 0 unknown
   double ma1, ma2, ma3, ma4;
   double convergePct;    // the stack spread as % of price
   double priorMove;      // the lookback move (%)
   double rangePos;       // where price sits inside the lookback range (0 low .. 1 high)
   double baseHigh, baseLow;
   double avgVol20;
   double failHighLevel;  // the recent high the topping read measures against
};

//+------------------------------------------------------------------+
class CCfStageAnalysis : public CEAStrategy
{
public:
   void OnInitStrategy()
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("5-stage policy: stage %d active (risk %.3f%%)",
             InpStage, g_eaCfg.riskPct), true);
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "Stage Analysis armed: %s stack %d/%d/%d/%d, longs %s, shorts %s, mean reversion %s",
             EnumToString(InpMaTf), InpMa1, InpMa2, InpMa3, InpMa4,
             InpAllowLongs ? "on" : "off", InpAllowShorts ? "on" : "off",
             InpUseMeanReversion ? "on" : "off"), true);
   }

   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_STAGE_ANALYSIS";
      cfg.sourceDoc             = "chartfanatics/glimpse/VDK200OHNSo.md (card #36)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;      // intraday execution inside the stage context
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = 5.0;
      cfg.totalDdPct            = 12.0;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 300;
      cfg.sessionStartHour      = InpSessionStartHour;
      cfg.sessionStartMin       = InpSessionStartMin;
      cfg.sessionEndHour        = InpSessionEndHour;
      cfg.sessionEndMin         = InpSessionEndMin;
      cfg.sessionEndFlat        = false;           // Stage 2 is "buy/HOLD" - positions ride the stage, not the bell
      cfg.fridayFlat            = false;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = false;
      cfg.partial1AtR           = 0.0;             // the Stage 3 scale-out is structural - hand-rolled in Manage()
      cfg.partial2AtR           = 0.0;
      cfg.breakEvenAtR          = 0.0;             // the document states no break-even rule
      cfg.trailAtR              = 0.0;             // the stack exit is the document's own
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_stage_analysis_ledger.csv";
      cfg.newsFilter            = false;
      cfg.logLevel              = InpLogLevel;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   //+----------------------------------------------------------------+
   //| Signal phase: read the stage, then the stage's own entry.       |
   //+----------------------------------------------------------------+
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession || ctx.atr <= 0.0) return false;

      SStageCtx c;
      if(!ReadStage(ctx, c)) return false;

      MqlRates m[];
      if(EA_Rates(ctx.symbol, g_eaIndTf, 0, 30, m) < 20) return false;
      MqlRates t[];                                   // the stack timeframe bars (for the completed-close reads)
      int tGot = EA_Rates(ctx.symbol, InpMaTf, 0, 4, t);
      if(tGot < 3) return false;

      double best = -1.0;
      SSignalPlan p;

      //--- the Stage 2 entries (S5/S6).  The pullback needs the established uptrend; the transition
      //--- entries (a completed close above the whole stack / above the first base) are exactly the
      //--- moments the converged read resolves upward, so they are evaluated outside Stage 4 - but
      //--- convergence alone never triggers anything ("forget the first eighth": the base is only
      //--- traded once it breaks).
      if(InpAllowLongs && c.stage != 4)
      {
         if(c.stage == 2)
         {
            p.Reset();
            if(InpUsePullback && PlanPullbackLong(ctx, c, t, p) && p.score > best) { plan = p; best = p.score; }
         }
         p.Reset();
         if(InpUseBreakout && PlanBreakoutLong(ctx, c, t, p) && p.score > best) { plan = p; best = p.score; }
         p.Reset();
         if(PlanFirstBaseLong(ctx, c, t, p) && p.score > best) { plan = p; best = p.score; }
      }

      //--- the Stage 4 short (S8)
      if(InpAllowShorts && c.stage == 4)
      {
         p.Reset();
         if(PlanStage4Short(ctx, c, t, p) && p.score > best) { plan = p; best = p.score; }
      }

      //--- the advanced Stage 4 mean reversion (S9)
      if(InpUseMeanReversion && InpAllowLongs && c.stage == 4)
      {
         p.Reset();
         if(PlanMeanReversion(ctx, c, m, p) && p.score > best) { plan = p; best = p.score; }
      }
      return (plan.dir != 0);
   }

   //+----------------------------------------------------------------+
   //| S7: "When price fails to make new highs, MAs flatten and        |
   //| converge, and price starts oscillating wide and loose, it is    |
   //| time to scale out" - the Stage 3 management, and the 30-period  |
   //| MA break closes the rest.                                       |
   //+----------------------------------------------------------------+
   void Manage(SEAContext &ctx)
   {
      int dir = -1;
      ulong ticket = EA_FindPosition(ctx.symbol, dir);
      if(ticket == 0) { dir = +1; ticket = EA_FindPosition(ctx.symbol, dir); }
      if(ticket == 0 || !PositionSelectByTicket(ticket)) return;

      SStageCtx c;
      if(!ReadStage(ctx, c)) return;

      double maExit = c.ma3;                          // the 30-period MA of the same stack
      MqlRates t[];
      if(EA_Rates(ctx.symbol, InpMaTf, 0, 3, t) < 2) return;

      //--- the scale-out: the topping read while the trade is in profit
      if(!FlagDone(ticket, "S3"))
      {
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double cur   = (dir > 0) ? ctx.bid : ctx.ask;
         bool inProfit = (dir > 0) ? (cur > entry) : (cur < entry);
         bool failHigh = (dir > 0) ? (t[1].high < c.failHighLevel) : (t[1].low > c.failHighLevel);
         bool converged = (c.convergePct <= InpConvergePct);
         if(inProfit && converged && failHigh)
         {
            if(g_eaExec.ClosePartial(ticket, InpScaleOutPct) || !g_eaExec.CanPartial(ticket, InpScaleOutPct))
            {
               FlagSet(ticket, "S3");
               EA_Log(EA_LOG_EVENTS, StringFormat("Stage Analysis: scaling out - the stack converged (%.2f%%) and the move failed to extend",
                      c.convergePct), true);
            }
         }
      }

      //--- the structural exit: a completed close through the 30-period MA
      if(InpExitOnMa3Break && maExit > 0.0)
      {
         bool broke = (dir > 0) ? (t[1].close < maExit) : (t[1].close > maExit);
         if(broke)
         {
            if(g_eaExec.Close(ticket, "the completed close lost the 30-period MA - the stage has turned"))
               EA_Log(EA_LOG_EVENTS, StringFormat("Stage Analysis: exited on the %s close vs the 30 MA %.2f",
                      EnumToString(InpMaTf), maExit), true);
         }
      }
   }

private:
   string FlagKey(const ulong ticket, const string tag)
   {
      return "CFSA_" + IntegerToString((long)g_eaCfg.magic) + "_" + IntegerToString((long)ticket) + "_" + tag;
   }
   bool FlagDone(const ulong ticket, const string tag) { return GlobalVariableCheck(FlagKey(ticket, tag)); }
   void FlagSet(const ulong ticket, const string tag)  { GlobalVariableSet(FlagKey(ticket, tag), 1.0); }

   //--- a simple moving average of closes ending at bar `end` (newest-first series)
   double SmaOf(const MqlRates &r[], const int got, const int period, const int end)
   {
      if(period < 2 || end + period > got) return 0.0;
      double sum = 0.0;
      for(int i = end; i < end + period; i++) sum += r[i].close;
      return sum / period;
   }

   //+----------------------------------------------------------------+
   //| S1/S2/S3/S4: the four stages from the stack, the structure and  |
   //| the convergence - "this visual alignment is the fastest way to  |
   //| gauge market structure".                                        |
   //+----------------------------------------------------------------+
   bool ReadStage(const SEAContext &ctx, SStageCtx &c)
   {
      c.stage = 0; c.ma1 = 0; c.ma2 = 0; c.ma3 = 0; c.ma4 = 0;
      c.convergePct = 0; c.priorMove = 0; c.rangePos = 0.5; c.baseHigh = 0; c.baseLow = 0;
      c.avgVol20 = 0; c.failHighLevel = 0;

      int want = (int)MathMax(InpMa4 + 5, InpBigMoveLookback);
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, InpMaTf, 0, want, r);
      if(got < InpMa4 + 5 || got < 60) return false;

      c.ma1 = SmaOf(r, got, InpMa1, 0);
      c.ma2 = SmaOf(r, got, InpMa2, 0);
      c.ma3 = SmaOf(r, got, InpMa3, 0);
      c.ma4 = SmaOf(r, got, InpMa4, 0);
      if(c.ma1 <= 0.0 || c.ma2 <= 0.0 || c.ma3 <= 0.0 || c.ma4 <= 0.0) return false;
      double px = r[0].close;
      if(px <= 0.0) return false;

      double hi = MathMax(c.ma1, MathMax(c.ma2, MathMax(c.ma3, c.ma4)));
      double lo = MathMin(c.ma1, MathMin(c.ma2, MathMin(c.ma3, c.ma4)));
      c.convergePct = (hi - lo) / px * 100.0;

      bool bullish = (c.ma1 > c.ma2 && c.ma2 > c.ma3 && c.ma3 > c.ma4);
      bool bearish = (c.ma1 < c.ma2 && c.ma2 < c.ma3 && c.ma3 < c.ma4);
      bool aboveAll = (px > hi);
      bool belowAll = (px < lo);
      bool converged = (c.convergePct <= InpConvergePct);

      //--- the lookback move tells the bases and tops apart ("this mirrors Stage 1 but at the top")
      int lb = (int)MathMin(InpBigMoveLookback, got - 1);
      double loRef = r[lb].low, hiRef = r[lb].high;
      for(int i = 1; i <= lb; i++)
      {
         loRef = MathMin(loRef, r[i].low);
         hiRef = MathMax(hiRef, r[i].high);
      }
      c.priorMove = (loRef > 0.0) ? (r[0].close - loRef) / loRef * 100.0 : 0.0;
      c.rangePos  = (hiRef > loRef) ? (r[0].close - loRef) / (hiRef - loRef) : 0.5;

      if(bullish && aboveAll)      c.stage = 2;        // "surfing above all moving averages"
      else if(bearish && belowAll) c.stage = 4;        // "trading below the 10, 30, and 40 ... bearish alignment"
      //--- "This mirrors Stage 1 but at the top": price near the highs of the range = topping,
      //--- near the lows after a decline = basing ([interpretation] - the document reads it by eye).
      else if(converged)           c.stage = (c.rangePos >= 0.5) ? 3 : 1;
      else                         c.stage = 0;        // mixed - the document says avoid the chop

      //--- the base (S6) and the fail-high level (S7)
      int bLast = (int)MathMin(InpBaseBars, got - 2);
      if(bLast > 5)
      {
         c.baseHigh = r[1].high; c.baseLow = r[1].low;
         for(int i = 1; i <= bLast; i++)
         {
            c.baseHigh = MathMax(c.baseHigh, r[i].high);
            c.baseLow  = MathMin(c.baseLow,  r[i].low);
         }
      }
      int fLast = (int)MathMin(InpFailHighBars, got - 2);
      if(fLast > 3)
      {
         c.failHighLevel = r[1].high;
         for(int i = 1; i <= fLast; i++) c.failHighLevel = MathMax(c.failHighLevel, r[i].high);
      }
      double volSum = 0.0;
      int vn = (int)MathMin(20, got - 1);
      for(int i = 1; i <= vn; i++) volSum += (double)r[i].tick_volume;
      c.avgVol20 = (vn > 0) ? volSum / vn : 0.0;
      return true;
   }

   //--- "the first multi-month consolidation": is there any earlier multi-month base inside the
   //--- big-move window?  [interpretation] the document calls the setup "the first" but draws the
   //--- window by eye; a stride of 5 bars keeps the scan cheap.
   bool HasPriorBase(const SEAContext &ctx)
   {
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, InpMaTf, 0, InpBigMoveLookback + 5, r);
      int bars = (int)MathMin(InpBaseBars, 60);
      if(got < bars * 2 || bars < 5) return false;
      for(int k = bars + 1; k + bars < got - 1; k += 5)
      {
         double hi = r[k].high, lo = r[k].low;
         for(int j = k; j < k + bars; j++) { hi = MathMax(hi, r[j].high); lo = MathMin(lo, r[j].low); }
         double pct = (hi - lo) / MathMax(r[k].close, 0.0001) * 100.0;
         if(pct <= InpBaseMaxPct) return true;
      }
      return false;
   }

   bool VolumeConfirms(const SStageCtx &c, const MqlRates &t[])
   {
      if(c.avgVol20 <= 0.0) return true;
      return ((double)t[1].tick_volume >= InpVolMult * c.avgVol20);      // "Volume should confirm"
   }

   //--- S5: "look for a pullback to the 10/20 MA for a lower-risk entry"
   bool PlanPullbackLong(const SEAContext &ctx, const SStageCtx &c, const MqlRates &t[], SSignalPlan &p)
   {
      double tol = InpPullbackTolPct / 100.0;
      bool touch10 = (t[1].low <= c.ma1 * (1.0 + tol) && t[1].close > c.ma1);
      bool touch20 = (t[1].low <= c.ma2 * (1.0 + tol) && t[1].close > c.ma2);
      if(!touch10 && !touch20) return false;
      double maRef = touch10 ? c.ma1 : c.ma2;
      double stop = t[1].low - InpStopBufferAtr * ctx.atr;
      if(stop <= 0.0 || stop >= ctx.ask) return false;
      double risk = ctx.ask - stop;
      if(risk > ctx.ask * InpMaxStopPct / 100.0) return false;

      p.dir = +1; p.entry = ctx.ask; p.stop = stop;
      p.target = ctx.ask + InpTargetR * risk;         // far - the stage exit is the real exit
      p.riskDist = risk; p.barsAgo = 1; p.isLimit = false;
      p.score = 82.0;
      p.reason = StringFormat("Stage 2 pullback into the %s MA %.2f (stack open %.2f%%)",
                              touch10 ? "10" : "20", maRef, c.convergePct);
      return true;
   }

   //--- S5: "price ... close above all four moving averages with the 10 above the 20 and 30.  Volume should confirm"
   bool PlanBreakoutLong(const SEAContext &ctx, const SStageCtx &c, const MqlRates &t[], SSignalPlan &p)
   {
      double hi = MathMax(c.ma1, MathMax(c.ma2, MathMax(c.ma3, c.ma4)));
      if(!(t[1].close > hi)) return false;
      if(!(c.ma1 > c.ma2 && c.ma1 > c.ma3)) return false;
      if(!VolumeConfirms(c, t)) return false;

      //--- a fresh transition, not a trade already extended above the stack
      bool fresh = false;
      for(int i = 1; i <= (int)MathMax(2, MathMin(4, ArraySize(t) - 1)); i++)
         if(t[i].close <= hi) { fresh = true; break; }
      if(!fresh) return false;

      double stop = MathMin(c.ma4, t[1].low) - InpStopBufferAtr * ctx.atr;
      if(stop <= 0.0 || stop >= ctx.ask) return false;
      double risk = ctx.ask - stop;
      if(risk > ctx.ask * InpMaxStopPct / 100.0) return false;

      p.dir = +1; p.entry = ctx.ask; p.stop = stop;
      p.target = ctx.ask + InpTargetR * risk;
      p.riskDist = risk; p.barsAgo = 1; p.isLimit = false;
      p.score = 86.0;
      p.reason = "Stage 1 -> 2 transition: close above the whole stack with volume";
      return true;
   }

   //--- S6: "the first multi-month consolidation ... often precedes the next leg up"
   bool PlanFirstBaseLong(const SEAContext &ctx, const SStageCtx &c, const MqlRates &t[], SSignalPlan &p)
   {
      if(c.baseHigh <= 0.0 || c.baseLow <= 0.0) return false;
      if(c.priorMove < InpBigMovePct) return false;                  // "after a big Stage 2 move"
      double basePct = (c.baseHigh - c.baseLow) / MathMax(t[1].close, 0.0001) * 100.0;
      if(basePct > InpBaseMaxPct) return false;                      // the consolidation must be tight
      if(!(t[1].close > c.baseHigh)) return false;                   // the breakout above the base
      if(!(t[1].close > c.ma1 && t[1].close > c.ma2)) return false;  // back above the short MAs (S5 family)
      if(HasPriorBase(ctx)) return false;                            // the FIRST consolidation, not a later one
      if(!VolumeConfirms(c, t)) return false;

      double stop = MathMin(c.baseLow, t[1].low) - InpStopBufferAtr * ctx.atr;
      if(stop <= 0.0 || stop >= ctx.ask) return false;
      double risk = ctx.ask - stop;
      if(risk > ctx.ask * InpMaxStopPct / 100.0) return false;

      p.dir = +1; p.entry = ctx.ask; p.stop = stop;
      p.target = ctx.ask + InpTargetR * risk;
      p.riskDist = risk; p.barsAgo = 1; p.isLimit = false;
      p.score = 88.0;
      p.reason = StringFormat("first multi-month base after a %.0f%% move: breakout above %.2f", c.priorMove, c.baseHigh);
      return true;
   }

   //--- S8: the Stage 4 short - a failed rally back to the 10/20 MAs under a bearish stack
   bool PlanStage4Short(const SEAContext &ctx, const SStageCtx &c, const MqlRates &t[], SSignalPlan &p)
   {
      double tol = InpPullbackTolPct / 100.0;
      bool tagged = (t[1].high >= c.ma1 * (1.0 - tol) && t[1].close < c.ma1);
      if(!tagged) return false;
      double stop = t[1].high + InpStopBufferAtr * ctx.atr;
      if(stop <= ctx.bid) return false;
      double risk = stop - ctx.bid;
      if(risk > ctx.bid * InpMaxStopPct / 100.0) return false;

      p.dir = -1; p.entry = ctx.bid; p.stop = stop;
      p.target = ctx.bid - InpTargetR * risk;
      p.riskDist = risk; p.barsAgo = 1; p.isLimit = false;
      p.score = 80.0;
      p.reason = StringFormat("Stage 4: failed rally into the 10 MA %.2f under the bearish stack", c.ma1);
      return (p.target > 0.0);
   }

   //--- S9: "If a stock crashes far below the 30/40-week MAs ... it may bounce back to those MAs"
   bool PlanMeanReversion(const SEAContext &ctx, const SStageCtx &c, const MqlRates &m[], SSignalPlan &p)
   {
      double dist = (c.ma3 - ctx.bid) / c.ma3 * 100.0;
      if(dist < InpExtremeBelowPct) return false;                    // "far below" the 30/40 MAs
      if(!(m[1].close > m[1].open)) return false;                    // the bounce must have started
      double stop = m[1].low - InpStopBufferAtr * ctx.atr;
      if(stop <= 0.0 || stop >= ctx.ask) return false;
      double risk = ctx.ask - stop;
      if(risk > ctx.ask * InpMaxStopPct / 100.0) return false;

      p.dir = +1; p.entry = ctx.ask; p.stop = stop;
      p.target = c.ma3;                                              // "bounce back to those MAs as support"
      p.riskDist = risk; p.barsAgo = 1; p.isLimit = false;
      p.score = 70.0;
      p.reason = StringFormat("Stage 4 mean reversion: %.0f%% below the 30 MA, bounce toward %.2f", dist, c.ma3);
      return (p.target > p.entry);
   }
};

CCfStageAnalysis g_cfStageAnalysis;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfStageAnalysis);
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
