//+------------------------------------------------------------------+
//|                        EA_CF_TradingFirstPrinciplesFramework.mq5  |
//|                                  Copyright 2026, Master Strategy  |
//|                                                                   |
//| ChartFanatics: Trading First Principles Framework                  |
//| "Three Core Trading Moves: 20 Years of Institutional Strategy"     |
//| Card    : chartfanatics/todos/trading-first-principles-framework.md|
//| Source  : chartfanatics/glimpse/_wpg45NdMkM.md              (#39)  |
//| Magic   : 3242                                                    |
//|                                                                   |
//| "Pretty much all trading strategies boil down to these three       |
//|  specific moves."                                                  |
//|                                                                   |
//| The document states all three mechanically, so the EA trades all    |
//| three side by side as the portfolio it tells you to build:          |
//|                                                                   |
//|   A  SHORT-TERM MOMENTUM (BREAKOUTS): "Measure volatility          |
//|      expansion - when price moves further than average - and       |
//|      enter.  Exit after 2-5 days or when momentum disappears.      |
//|      Works best on daily timeframes."                              |
//|   B  MEAN REVERSION: "Measure how far price deviates from a moving |
//|      average (e.g., 5-day MA).  When deviation exceeds normal      |
//|      range (e.g., 6-7% vs. 2% average), enter expecting reversion. |
//|      Exit after 1-4 days or when price returns to mean."           |
//|   C  TREND FOLLOWING: "Identify strong support/resistance (e.g.,   |
//|      100-day or 200-day high).  Enter on breakout; exit when price |
//|      closes below a trailing moving average (e.g., 10-day MA).     |
//|      Strongest edge when breaking all-time highs."                 |
//|                                                                   |
//| The portfolio rules are just as explicit:                          |
//|   P1 "Advanced traders should combine 3+ strategies ... Rebalance  |
//|      monthly or quarterly to lock in gains."  -> the three         |
//|      approaches run side by side, each with one equal risk share,  |
//|      and percentage-of-equity sizing resets every position to the  |
//|      base share at every entry - the rebalancing the document      |
//|      describes ("forces you to buy low and sell high").  The        |
//|      scheduled rebalance/review dates are logged.                  |
//|   P2 "Trading fees ... compound into massive profit erosion.  On   |
//|      low-expectancy strategies, fees can consume 50% or more of    |
//|      gross returns." -> the engine's cost gate rejects any trade   |
//|      whose round-trip cost exceeds InpMaxCostR of its risk, and    |
//|      every signal is logged with its cost in R.                    |
//|   P3 "Avoid overcrowded battlefields ... avoid highly liquid,      |
//|      short-timeframe markets" and "Holding time matters more than  |
//|      timeframe" -> the EA reads and trades DAILY bars only and     |
//|      holds for days, never minutes.                                |
//|   P4 "Stocks tend to mean-revert upward long-term ... Avoid        |
//|      shorting large-cap stocks." -> InpLongOnlyList keeps the named |
//|      symbols long-only (the EA cannot detect an asset class).      |
//|                                                                   |
//| `[interpretation]`: the ATR-normalisation of "moves further than    |
//| average", the average-deviation window behind "2% average", the     |
//| breakout/stop buffers, the stop-width caps, the trend stop's ATR    |
//| multiple, the "all-time high" lookback, the rebalance/review        |
//| periods and the far take-profit placeholder are inputs and         |
//| labelled - the exits the document states are the real exits.        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics First Principles - the three core moves (breakout momentum, mean reversion, trend following) as a rebalanced daily-bar portfolio"

#include "..\..\Include\EACommon.mqh"

//--- identity / portfolio risk (P1: one equal share per approach)
input string            InpSymbolsToTrade     = "BTCUSD,ETHUSD";  // Universe (the document's least-efficient markets)
input ulong             InpMagicNumber        = 3242;             // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpSetupRiskPct       = 0.35;             // Risk per trade, one equal share per approach
input int               InpStage              = 5;                // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input double            InpDailyLossPct       = 3.00;             // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset    = 2;                // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel           = EA_LOG_EVENTS;    // Log verbosity
input double            InpCommissionPerLotRT = 0.0;              // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.10;             // P2: reject a trade whose cost exceeds xR
input bool              InpLedger             = true;             // Write the engine evidence ledger CSV

//--- A: short-term momentum / breakouts
input bool              InpUseMomentum        = true;             // "Measure volatility expansion ... and enter"
input double            InpVolExpMult         = 1.50;             // [interpretation] "moves further than average" (x its average range)
input int               InpVolExpLen          = 20;               // [interpretation] The average-range window
input int               InpMomMaxDays         = 5;                // "Exit after 2-5 days"
input double            InpStopBufferAtr      = 0.35;             // [interpretation] Stop buffer beyond the expansion bar
input double            InpMaxStopPct         = 15.0;             // [interpretation] Reject stops wider than x% of price

//--- B: mean reversion
input bool              InpUseMeanReversion   = true;             // "When deviation exceeds normal range ... enter expecting reversion"
input int               InpDevMaLen           = 5;                // "a moving average (e.g., 5-day MA)"
input int               InpDevLookback        = 20;               // [interpretation] The window behind the "normal range"
input double            InpDevTriggerPct      = 6.00;             // "deviation exceeds normal range (e.g., 6-7%)"
input double            InpDevAbnormalMult    = 2.00;             // [interpretation] ... vs the average (the document's 6-7% vs 2%)
input int               InpMrMaxDays          = 4;                // "Exit after 1-4 days"
input double            InpMrMeanTolPct       = 0.50;             // [interpretation] "returns to mean" tolerance
input bool              InpMrShortAbove       = true;             // ... and the mirror below (buy the dip / sell the rip)

//--- C: trend following
input bool              InpUseTrendFollowing  = true;             // "Enter on breakout ... exit below the trailing MA"
input int               InpTrendLookback      = 200;              // "100-day or 200-day high"
input int               InpTrendExitMa        = 10;               // "a trailing moving average (e.g., 10-day MA)"
input int               InpAthLookback        = 750;              // [interpretation] The "all-time high" horizon
input double            InpTrendStopAtr       = 2.00;             // [interpretation] The trend stop's ATR multiple (the document exits on the MA)

//--- management / portfolio housekeeping
input double            InpTargetR            = 8.0;              // [interpretation] Far TP placeholder - the document's own exits are the exits
input int               InpRebalanceDays      = 30;               // "Rebalance monthly or quarterly to lock in gains"
input int               InpReviewDays         = 90;               // "schedule quarterly research reviews" (edge decay)
input string            InpLongOnlyList       = "";               // P4: symbols to keep long-only (stocks are long-biased)
input string            InpPortfolioFile      = "cf_first_principles_signals.csv";  // The per-approach evidence for the reviews

//+------------------------------------------------------------------+
#define CFTP_A 1   // volatility expansion / momentum
#define CFTP_B 2   // mean reversion
#define CFTP_C 3   // trend following

//+------------------------------------------------------------------+
class CCfFirstPrinciples : public CEAStrategy
{
public:
   void OnInitStrategy()
   {
      m_planSetup = 0;
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "First Principles armed: %s on daily bars - momentum %s, mean reversion %s, trend following %s, one %.2f%% share each, rebalance every %d day(s)",
             InpSymbolsToTrade,
             InpUseMomentum ? "on" : "off", InpUseMeanReversion ? "on" : "off", InpUseTrendFollowing ? "on" : "off",
             InpSetupRiskPct, InpRebalanceDays), true);
      EA_Log(EA_LOG_EVENTS, "the three approaches are the portfolio: percentage-of-equity sizing resets every entry to its base share (the document's rebalancing), and every signal is logged with its cost in R (the fee warning)", true);
   }

   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_FIRST_PRINCIPLES";
      cfg.sourceDoc             = "chartfanatics/glimpse/_wpg45NdMkM.md (card #39)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpSetupRiskPct;         // one equal share per approach
      cfg.signalTimeframe       = PERIOD_D1;               // P3: "Holding time matters more than timeframe"
      cfg.clock                 = EA_CLOCK_SERVER;         // daily bars: the server day is the natural anchor
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = 0.0;                     // the cost gate below is the doc's own tool
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = 6.0;
      cfg.totalDdPct            = 15.0;
      cfg.maxTradesPerDay       = 3;                       // one per approach
      cfg.maxOpenPositions      = 3;                       // the portfolio: "combine 3+ strategies"
      cfg.minSecondsBetweenTrades = 3600;
      cfg.sessionStartHour      = 0;                       // daily bars: any moment of the server day
      cfg.sessionStartMin       = 0;
      cfg.sessionEndHour        = 23;
      cfg.sessionEndMin         = 59;
      cfg.sessionEndFlat        = false;                   // the holds are multi-day by design
      cfg.fridayFlat            = false;
      cfg.signalOnNewBarOnly    = true;                    // one decision per completed day
      cfg.useLimitEntry         = false;
      cfg.breakEvenAtR          = 0.0;                     // the document's exits are time/structure, not break-even
      cfg.partial1AtR           = 0.0;                     // no partials either - the exits below are the document's
      cfg.partial2AtR           = 0.0;
      cfg.trailAtR              = 0.0;
      cfg.timeStopMinutes       = 0;                       // the holds are enforced per approach in Manage()
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;             // P2
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_first_principles_ledger.csv";
      cfg.logLevel              = InpLogLevel;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   //+----------------------------------------------------------------+
   //| One decision per completed day: which of the three approaches   |
   //| has a setup, and is it the best one today?                      |
   //+----------------------------------------------------------------+
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      m_planSetup = 0;
      if(ctx.atr <= 0.0) return false;

      MqlRates d[];
      int got = EA_Rates(ctx.symbol, PERIOD_D1, 0, (int)MathMax(InpTrendLookback, InpAthLookback) + 5, d);
      if(got < 30) return false;

      MaybeRebalance();

      double best = -1.0;
      SSignalPlan p;
      p.Reset();
      if(InpUseMomentum && PlanMomentum(ctx, d, got, p) && p.score > best) { plan = p; best = p.score; }
      p.Reset();
      if(InpUseMeanReversion && PlanMeanReversion(ctx, d, got, p) && p.score > best) { plan = p; best = p.score; }
      p.Reset();
      if(InpUseTrendFollowing && PlanTrendFollowing(ctx, d, got, p) && p.score > best) { plan = p; best = p.score; }

      if(plan.dir != 0)
      {
         if(IsLongOnly(ctx.symbol) && plan.dir < 0) return false;      // P4
         if(!SetupAllowed(ctx.symbol, m_planSetup)) return false;      // one open trade per approach
         PendingSetupSet(ctx.symbol, m_planSetup);
         LogSignal(ctx, plan, m_planSetup);
      }
      return (plan.dir != 0);
   }

   //+----------------------------------------------------------------+
   //| The document's exits, per approach, on completed daily bars:    |
   //|  A "Exit after 2-5 days or when momentum disappears"            |
   //|  B "Exit after 1-4 days or when price returns to mean"          |
   //|  C "exit when price closes below a trailing MA (10-day)"        |
   //+----------------------------------------------------------------+
   void Manage(SEAContext &ctx)
   {
      if(PositionsTotal() == 0) return;
      MqlRates d[];
      int got = EA_Rates(ctx.symbol, PERIOD_D1, 0, 40, d);
      if(got < 15) return;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != (long)g_eaCfg.magic) continue;

         int setup = SetupOf(ctx.symbol, t);
         if(setup == 0)
         {
            setup = PendingSetupGet(ctx.symbol);
            if(setup != 0) SetupRemember(ctx.symbol, t, setup);
            else continue;                                   // not ours to manage (should not happen)
         }

         bool isLong = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         int daysHeld = (int)(((long)TimeTradeServer() - (long)PositionGetInteger(POSITION_TIME)) / 86400);
         if(daysHeld < 0) daysHeld = 0;

         if(setup == CFTP_A)
         {
            bool gone = isLong ? (d[1].close < d[2].low) : (d[1].close > d[2].high);
            if(daysHeld >= InpMomMaxDays || gone)
               CloseOnce(t, StringFormat("momentum: %s (held %d day(s))",
                         (daysHeld >= InpMomMaxDays ? "the 2-5 day window ended" : "momentum disappeared"), daysHeld));
         }
         else if(setup == CFTP_B)
         {
            double ma = SmaClose(d, got, InpDevMaLen, 1);
            bool atMean = (ma > 0.0 && MathAbs(d[1].close - ma) / ma * 100.0 <= InpMrMeanTolPct);
            if(daysHeld >= InpMrMaxDays || atMean)
               CloseOnce(t, StringFormat("mean reversion: %s (held %d day(s))",
                         (atMean ? "price returned to the mean" : "the 1-4 day window ended"), daysHeld));
         }
         else if(setup == CFTP_C)
         {
            double ma = SmaClose(d, got, InpTrendExitMa, 1);
            if(ma > 0.0 && ((isLong && d[1].close < ma) || (!isLong && d[1].close > ma)))
               CloseOnce(t, StringFormat("trend: the completed close crossed the %d-day MA %.2f", InpTrendExitMa, ma));
         }
      }
   }

private:
   int m_planSetup;     // the approach behind the plan being assembled (SSignalPlan has no field for it)

   //+----------------------------------------------------------------+
   //| A: "when price moves further than average"                      |
   //+----------------------------------------------------------------+
   bool PlanMomentum(const SEAContext &ctx, const MqlRates &d[], const int got, SSignalPlan &p)
   {
      if(got < InpVolExpLen + 3) return false;
      double sum = 0.0;
      for(int i = 2; i <= InpVolExpLen + 1; i++) sum += (d[i].high - d[i].low);
      double avg = sum / InpVolExpLen;
      if(avg <= 0.0) return false;
      double rng = d[1].high - d[1].low;
      if(rng < InpVolExpMult * avg) return false;             // "volatility expansion"

      int dir = (d[1].close >= d[1].open) ? +1 : -1;
      double entry = (dir > 0) ? ctx.ask : ctx.bid;
      double stop  = (dir > 0) ? d[1].low - InpStopBufferAtr * ctx.atr
                               : d[1].high + InpStopBufferAtr * ctx.atr;
      if(!StopOk(entry, stop)) return false;
      double risk = MathAbs(entry - stop);

      p.dir = dir; p.entry = entry; p.stop = stop;
      p.target = (dir > 0) ? entry + InpTargetR * risk : entry - InpTargetR * risk;
      p.riskDist = risk; p.barsAgo = 1; p.isLimit = false;
      m_planSetup = CFTP_A;
      p.score = 82.0;
      p.reason = StringFormat("volatility expansion: the day's range %.0f%% of its %d-day average -> %s",
                              rng / avg * 100.0, InpVolExpLen, (dir > 0 ? "LONG" : "SHORT"));
      return (p.target > 0.0);
   }

   //+----------------------------------------------------------------+
   //| B: "how far price deviates from a moving average"                |
   //+----------------------------------------------------------------+
   bool PlanMeanReversion(const SEAContext &ctx, const MqlRates &d[], const int got, SSignalPlan &p)
   {
      if(got < InpDevLookback + InpDevMaLen + 3) return false;
      double ma = SmaClose(d, got, InpDevMaLen, 1);
      if(ma <= 0.0) return false;
      double dev = (d[1].close - ma) / ma * 100.0;

      //--- the "normal range": the average absolute deviation of the last stretch
      double sum = 0.0;
      int n = 0;
      for(int i = 1; i <= InpDevLookback; i++)
      {
         double m = SmaClose(d, got, InpDevMaLen, i);
         if(m <= 0.0) continue;
         sum += MathAbs((d[i].close - m) / m * 100.0);
         n++;
      }
      if(n < 5) return false;
      double avgDev = sum / n;
      if(avgDev <= 0.0) return false;

      if(MathAbs(dev) < InpDevTriggerPct) return false;        // "exceeds normal range (e.g., 6-7%)"
      if(MathAbs(dev) < InpDevAbnormalMult * avgDev) return false;   // ... "vs. 2% average"

      int dir = (dev > 0.0) ? -1 : +1;                          // expecting reversion
      if(dir < 0 && !InpMrShortAbove) return false;
      double entry = (dir > 0) ? ctx.ask : ctx.bid;
      double stop  = (dir > 0) ? d[1].low - InpStopBufferAtr * ctx.atr
                               : d[1].high + InpStopBufferAtr * ctx.atr;
      if(!StopOk(entry, stop)) return false;
      double risk = MathAbs(entry - stop);

      p.dir = dir; p.entry = entry; p.stop = stop;
      p.target = (dir > 0) ? entry + InpTargetR * risk : entry - InpTargetR * risk;
      p.riskDist = risk; p.barsAgo = 1; p.isLimit = false;
      m_planSetup = CFTP_B;
      p.score = 84.0 + MathMin(6.0, MathAbs(dev) - InpDevTriggerPct);
      p.reason = StringFormat("mean reversion: %.1f%% from the %d-day MA vs a %.1f%% normal range -> %s",
                              dev, InpDevMaLen, avgDev, (dir > 0 ? "LONG" : "SHORT"));
      return (p.target > 0.0);
   }

   //+----------------------------------------------------------------+
   //| C: "Identify strong support/resistance (e.g., 100-day or        |
   //| 200-day high).  Enter on breakout"                              |
   //+----------------------------------------------------------------+
   bool PlanTrendFollowing(const SEAContext &ctx, const MqlRates &d[], const int got, SSignalPlan &p)
   {
      int lb = (int)MathMin(InpTrendLookback, got - 3);
      if(lb < 20) return false;
      double hi = d[2].high, lo = d[2].low;
      for(int i = 3; i <= lb + 1; i++)
      {
         hi = MathMax(hi, d[i].high);
         lo = MathMin(lo, d[i].low);
      }
      int dir = (d[1].close > hi) ? +1 : ((d[1].close < lo) ? -1 : 0);
      if(dir == 0) return false;

      double entry = (dir > 0) ? ctx.ask : ctx.bid;
      double stop  = (dir > 0) ? entry - InpTrendStopAtr * ctx.atr
                               : entry + InpTrendStopAtr * ctx.atr;
      if(!StopOk(entry, stop)) return false;
      double risk = MathAbs(entry - stop);

      p.dir = dir; p.entry = entry; p.stop = stop;
      p.target = (dir > 0) ? entry + InpTargetR * risk : entry - InpTargetR * risk;
      p.riskDist = risk; p.barsAgo = 1; p.isLimit = false;
      m_planSetup = CFTP_C;
      p.score = 86.0;

      //--- "Strongest edge when breaking all-time highs"
      int ath = (int)MathMin(InpAthLookback, got - 2);
      bool athBreak = true;
      for(int i = 2; i <= ath + 1 && athBreak; i++)
      {
         if(dir > 0 && d[i].high > d[1].close) athBreak = false;
         if(dir < 0 && d[i].low  < d[1].close) athBreak = false;
      }
      if(athBreak) p.score += 6.0;
      p.reason = StringFormat("%d-day %s breakout%s -> %s",
                              lb, (dir > 0 ? "high" : "low"), (athBreak ? " (an all-time-high break)" : ""),
                              (dir > 0 ? "LONG" : "SHORT"));
      return (p.target > 0.0);
   }

   //+----------------------------------------------------------------+
   //| Helpers                                                         |
   //+----------------------------------------------------------------+
   double SmaClose(const MqlRates &d[], const int got, const int len, const int end)
   {
      if(len < 2 || end + len > got) return 0.0;
      double sum = 0.0;
      for(int i = end; i < end + len; i++) sum += d[i].close;
      return sum / len;
   }

   bool StopOk(const double entry, const double stop)
   {
      if(stop <= 0.0) return false;
      double risk = MathAbs(entry - stop);
      return (risk > 0.0 && risk <= entry * InpMaxStopPct / 100.0);
   }

   //--- P4: the EA cannot detect an asset class, so the long-only rule is a list
   bool IsLongOnly(const string sym)
   {
      if(StringLen(InpLongOnlyList) == 0) return false;
      return (StringFind(InpLongOnlyList, sym) >= 0);
   }

   //--- one open trade per approach: the portfolio slots are the three strategies
   bool SetupAllowed(const string sym, const int setup)
   {
      if(PositionsTotal() == 0) return true;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != sym) continue;
         if(PositionGetInteger(POSITION_MAGIC) != (long)g_eaCfg.magic) continue;
         if(SetupOf(sym, t) == setup) return false;
      }
      return true;
   }

   //--- the setup tag travels on a global variable keyed by symbol,
   //--- consumed by the ticket the moment the engine fills the plan
   string PendKey(const string sym)  { return "CFTP_" + IntegerToString((long)g_eaCfg.magic) + "_" + sym + "_P"; }
   void PendingSetupSet(const string sym, const int setup) { GlobalVariableSet(PendKey(sym), (double)setup); }
   int  PendingSetupGet(const string sym)
   {
      if(!GlobalVariableCheck(PendKey(sym))) return 0;
      return (int)GlobalVariableGet(PendKey(sym));
   }
   string TagKey(const string sym, const ulong ticket)
   {
      return "CFTP_" + IntegerToString((long)g_eaCfg.magic) + "_" + sym + "_" + IntegerToString((long)ticket);
   }
   int SetupOf(const string sym, const ulong ticket)
   {
      if(!GlobalVariableCheck(TagKey(sym, ticket))) return 0;
      return (int)GlobalVariableGet(TagKey(sym, ticket));
   }
   void SetupRemember(const string sym, const ulong ticket, const int setup)
   {
      GlobalVariableSet(TagKey(sym, ticket), (double)setup);
   }

   //--- the exits below are one-shot: the engine's Close is the only way out once issued
   void CloseOnce(const ulong ticket, const string why)
   {
      string key = "CFTP_X_" + IntegerToString((long)ticket);
      if(GlobalVariableCheck(key)) return;
      if(g_eaExec.Close(ticket, why))
      {
         GlobalVariableSet(key, 1.0);
         EA_Log(EA_LOG_EVENTS, StringFormat("First Principles exit: %s", why), true);
      }
   }

   //+----------------------------------------------------------------+
   //| P1: the scheduled rebalance/review - the document's "holy grail"|
   //| and its edge-decay discipline.  Percentage-of-equity sizing      |
   //| already resets every entry to its base share (the mechanical     |
   //| rebalancing); these dates log the portfolio state around the     |
   //| reset so the quarterly review has its data.                     |
   //+----------------------------------------------------------------+
   void MaybeRebalance()
   {
      string key = "CFTP_" + IntegerToString((long)g_eaCfg.magic) + "_RB";
      datetime now = TimeTradeServer();
      if(GlobalVariableCheck(key))
      {
         datetime last = (datetime)GlobalVariableGet(key);
         if(now - last < (datetime)(InpRebalanceDays * 86400)) return;
         EA_Log(EA_LOG_EVENTS, StringFormat(
                "portfolio rebalance: %d day(s) since the last reset - each of the three approaches back to its %.2f%% share (equity %.2f)",
                (int)((now - last) / 86400), InpSetupRiskPct, AccountInfoDouble(ACCOUNT_EQUITY)), true);
      }
      GlobalVariableSet(key, (double)(long)now);

      string rkey = "CFTP_" + IntegerToString((long)g_eaCfg.magic) + "_RV";
      if(!GlobalVariableCheck(rkey))
      {
         GlobalVariableSet(rkey, (double)(long)now);      // first run: just start the review clock
         return;
      }
      datetime rv = (datetime)GlobalVariableGet(rkey);
      if(now - rv >= (datetime)(InpReviewDays * 86400))
      {
         GlobalVariableSet(rkey, (double)(long)now);
         EA_Log(EA_LOG_EVENTS, StringFormat(
                "edge-decay review due (%d day cycle): check %s - every signal is written there with its cost in R",
                InpReviewDays, InpPortfolioFile), true);
      }
   }

   //--- the evidence the reviews need: one row per signal, with the fee in R (P2)
   void LogSignal(const SEAContext &ctx, const SSignalPlan &p, const int setup)
   {
      if(MQLInfoInteger(MQL_OPTIMIZATION)) return;
      double costR = EA_CostInR(ctx.symbol, p.riskDist, g_eaCfg.commissionPerLotRT);
      int fh = FileOpen(InpPortfolioFile, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
      if(fh == INVALID_HANDLE) return;
      FileSeek(fh, 0, SEEK_END);
      if(FileTell(fh) == 0)
         FileWrite(fh, "day", "symbol", "approach", "dir", "entry", "stop", "target", "risk_dist", "cost_r", "reason");
      FileWrite(fh,
                TimeToString(TimeTradeServer(), TIME_DATE),
                ctx.symbol,
                ApproachName(setup),
                (p.dir > 0 ? "long" : "short"),
                DoubleToString(p.entry, EA_Digits(ctx.symbol)),
                DoubleToString(p.stop, EA_Digits(ctx.symbol)),
                DoubleToString(p.target, EA_Digits(ctx.symbol)),
                DoubleToString(p.riskDist, EA_Digits(ctx.symbol)),
                DoubleToString(costR, 4),
                p.reason);
      FileClose(fh);
   }

   string ApproachName(const int setup)
   {
      if(setup == CFTP_A) return "momentum";
      if(setup == CFTP_B) return "mean-reversion";
      return "trend-following";
   }
};

CCfFirstPrinciples g_cfFirstPrinciples;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfFirstPrinciples);
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
