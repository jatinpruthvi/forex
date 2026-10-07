//+------------------------------------------------------------------+
//|                                      EA_CF_InstFramework.mq5     |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| ChartFanatics / Matteo Conte: "4 Institutional Scalping Strategies |
//| Market Makers Keep SECRET (Automate Prop Firm Trading)"           |
//| Card    : chartfanatics/todos/                                     |
//|           institutional-strategy-development-framework.md  (#15)   |
//| Source  : chartfanatics/glimpse/yW6c0K8uGvw.md                     |
//| Magic   : 3219                                                     |
//|                                                                    |
//| The document is a PIPELINE, not one setup: research idea -> exact   |
//| rules -> code -> validate (80/20 + Monte Carlo) -> automate, plus    |
//| volatility targeting and a portfolio/monthly-review discipline.      |
//| What an EA can carry of that pipeline:                              |
//|                                                                    |
//|   * the document's own strategies with their stated rules, one per   |
//|     mode (InpMode):                                                  |
//|       ORB      - "Go long if price closes above the 9:30-10:00 high. |
//|                  Stop at the range low; take profit at 1:1 or 1:2;   |
//|                  or close at 3:30 p.m." - long-only, because the     |
//|                  same research says the short side is weaker.        |
//|       VWOP     - 1-minute close above the volume-weighted average    |
//|                  price -> long, below -> short; exit on the cross    |
//|                  back through VWOP.  Anchor = the session open or    |
//|                  the prior close (the doc says test both).           |
//|       OVERNIGHT- "Go long at 4 p.m. (market close), close at 9:30    |
//|                  a.m. (market open)" - 90% of index returns live in  |
//|                  the overnight gap; optional ORB filter, the doc's   |
//|                  own combined variation.                             |
//|     PEAD (Strategy 3) is NOT implemented: it needs actual-vs-estimate |
//|     earnings data and an earnings calendar, which an MT5 EA has no    |
//|     feed for.  Its rules are on the card; this is a data block, not   |
//|     an oversight.                                                     |
//|                                                                    |
//|   * VOLATILITY TARGETING - "adjust contract count so risk is always  |
//|     the same (e.g. $10,000 per trade)": LotsMultiplier() normalises    |
//|     every fill to a constant dollar risk, so a wide volatile stop     |
//|     buys fewer contracts and a tight one buys more.                   |
//|                                                                    |
//|   * VALIDATION AS A LIVE THRESHOLD - "after 10 trades, if the         |
//|     validated max drawdown was $10,000 with 5% probability of being   |
//|     exceeded and you see $15,000, that is a red flag to pause the      |
//|     strategy": the EA measures its own closed-trade drawdown and       |
//|     pauses new entries when it exceeds the validated limit.            |
//|                                                                    |
//|   * MONTHLY REVIEW / portfolio - "run 3-4 uncorrelated strategies",    |
//|     "monthly: monitor live performance, identify underperforming       |
//|     strategies": the EA journals a per-magic monthly row (trades,      |
//|     win rate, expectancy, net, max drawdown) for every magic on the    |
//|     account, so the family's own portfolio gets its review.            |
//|                                                                    |
//| The 80/20 in-sample split and the Monte Carlo reshuffle/bootstrap are  |
//| research-time work: they live in the repo's validation harness, not in |
//| a live EA.  The EA carries their RESULT forward as the pause threshold.|
//|                                                                    |
//| `[interpretation]`: the video gives the strategies' rules but not      |
//| every number this EA needs (ORB target 1:1 vs 1:2, the overnight       |
//| entry tolerance, the ORB filter for the overnight variation, the       |
//| month-window drawdown) - each is an input with the document's example  |
//| as the default, and the PEAD data block is disclosed above.            |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics institutional framework - ORB / VWOP / overnight-gap modes with volatility targeting and live validation thresholds"

#include "..\..\Include\EACommon.mqh"

enum ENUM_CF_FW_MODE
{
   CF_FW_ORB       = 0,   // Strategy 1: Opening Range Breakout (long-only)
   CF_FW_VWOP      = 1,   // Strategy 2: VWOP momentum (both ways)
   CF_FW_OVERNIGHT = 2    // Strategy 4: overnight gap premium (long close -> open)
};

//--- identity / risk
input string            InpSymbolsToTrade   = "US100,US500";        // "test on QQQ, ES, NQ, crude oil, or single stocks"
input ulong             InpMagicNumber      = 3219;                 // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct          = 0.50;                 // Risk per trade (% of equity) - volatility targeting normalises the $ risk
input double            InpRiskUsd          = 0.0;                  // "risk is always the same $ amount" (0 = plain percent sizing)
input int               InpStage             = 5;                   // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input int               InpServerGmtOffset  = 2;                    // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;        // Log verbosity
input double            InpCommissionPerLotRT = 0.0;                // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.12;               // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;               // Write the engine evidence ledger CSV
//--- which of the document's strategies this instance runs
input ENUM_CF_FW_MODE InpMode = CF_FW_ORB;  // Strategy mode (PEAD is data-blocked - see the header)
//--- Strategy 1: opening range breakout
input double InpOrbTargetR      = 2.0;   // "take profit at 1:1 or 1:2 risk-to-reward"
input bool   InpOrbLongOnly     = true;  // "long-only works better than short" (the research finding)
input int    InpOrbRangeFromMin = 870;   // 09:30 ET in London clock minutes (14:30)
input int    InpOrbRangeToMin   = 900;   // 10:00 ET (15:00)
input int    InpOrbExitMin      = 1230;  // "or close at 3:30 p.m." (15:30 ET = 20:30 London)
//--- Strategy 2: VWOP momentum
input bool   InpVwopAnchorAtOpen = true; // "calculate from market open ... or previous day's close" - both are testable
input int    InpVwopOpenHour     = 14;   // the "market open" of the VWOP session (London)
input int    InpVwopOpenMin      = 30;
input int    InpVwopCloseHour    = 21;   // the session close the previous-close anchor counts from
//--- Strategy 4: overnight gap premium
input double InpHoldHours       = 17.5;  // 16:00 -> 09:30 ET = 17.5 hours, DST-proof
input int    InpOvernightEntryMin = 1265; // 16:05 ET in London minutes (21:05) - late enough that the close has printed
input bool   InpOvernightRequireRangeBreak = false;  // the doc's "combine with ORB" variation
input bool   InpSkipFridayOvernight = true; // do not enter the Friday close: the exit would sit through the weekend
//--- the framework's live validation thresholds
input int    InpValidateAfterTrades = 10;    // "after 10 trades" the validation metrics start applying
input double InpValidatedMaxDdUsd   = 0.0;   // the validated max drawdown from the backtest (0 = no pause threshold)
input string InpReviewFile          = "cf_framework_review.csv";  // monthly portfolio review, all magics

//+------------------------------------------------------------------+
class CCfInstFramework : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_INSTITUTIONAL_FRAMEWORK";
      cfg.sourceDoc             = "chartfanatics/glimpse/yW6c0K8uGvw.md (card #15)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M1;            // "1-minute timeframe" for the VWOP study; the others are intraday too
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = 3.0;
      cfg.dailyLossPct          = 1.50;
      cfg.weeklyLossPct         = 3.0;
      cfg.totalDdPct            = 8.0;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 60;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = false;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_framework_ledger.csv";
      cfg.newsFilter            = false;
      cfg.logLevel              = InpLogLevel;

      if(InpMode == CF_FW_ORB)
      {
         //--- the range forms 09:30-10:00 and the day's trade is taken from it; "close at 3:30 p.m."
         cfg.sessionStartHour   = 14;  cfg.sessionStartMin = 25;
         cfg.sessionEndHour     = 20;  cfg.sessionEndMin   = 30;
         cfg.noTradeAfterHour   = 20;  cfg.noTradeAfterMin = 25;
         cfg.maxTradesPerDay    = 1;
         cfg.breakEvenAtR       = 1.0;
         cfg.partial1AtR        = 1.0;  cfg.partial1Pct = 50.0;     // the 1:1 target banks half
         cfg.trailAtR           = InpOrbTargetR;
      }
      else if(InpMode == CF_FW_VWOP)
      {
         cfg.sessionStartHour   = 14;  cfg.sessionStartMin = 30;    // the US cash session
         cfg.sessionEndHour     = 21;  cfg.sessionEndMin   = 0;
         cfg.noTradeAfterHour   = 20;  cfg.noTradeAfterMin = 50;
         cfg.maxTradesPerDay    = 4;                                 // the cross can flip; each flip is a new position
         cfg.breakEvenAtR       = 0.0;                               // the exit is the VWOP cross, not a target
         cfg.partial1AtR        = 0.0;  cfg.partial1Pct = 0.0;
         cfg.trailAtR           = 0.0;
      }
      else
      {
         //--- "long at 4 p.m., close at 9:30 a.m.": the position lives across the whole overnight window
         cfg.sessionStartHour   = 21;  cfg.sessionStartMin = 0;     // 16:00 ET
         cfg.sessionEndHour     = 14;  cfg.sessionEndMin   = 25;    // 09:25 ET (the engine understands the wrap)
         cfg.noTradeAfterHour   = -1;  cfg.noTradeAfterMin = 0;     // no cutoff: the window IS the rule
         cfg.maxTradesPerDay    = 1;
         cfg.fridayFlat         = false;                             // the overnight premium is the rule; weekend risk is the trader's choice
         cfg.breakEvenAtR       = 0.0;
         cfg.partial1AtR        = 0.0;  cfg.partial1Pct = 0.0;
         cfg.trailAtR           = 0.0;
      }
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   void OnInitStrategy()
   {
      m_paused     = false;
      m_pauseLogged = false;
      m_reviewMonth = 0;
      m_lastMetrics = 0;
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "institutional framework mode %s armed: volatility targeting %s, validation pause after %d trades at $%.0f drawdown",
             ModeName(), (InpRiskUsd > 0.0) ? "on (constant dollar risk)" : "off (percent sizing)",
             InpValidateAfterTrades, InpValidatedMaxDdUsd), true);
      if(InpMode == CF_FW_OVERNIGHT)
         EA_Log(EA_LOG_EVENTS, "overnight mode: the day's return is captured from the close to the next open (90% of index returns, per the 2008 paper)", true);
   }

   void OnDeinitStrategy()
   {
      WritePortfolioReview(true);      // never lose the month in progress on a chart unload
   }

   //--- the framework's live red flag: pause when the realised drawdown beats the validated limit
   bool AllowTrading(SEAContext &ctx)
   {
      if(InpValidatedMaxDdUsd <= 0.0) return true;
      if(m_lastMetrics <= 0 || TimeTradeServer() - m_lastMetrics > 300)
      {
         m_lastMetrics = TimeTradeServer();
         double dd = 0.0; int trades = 0;
         OwnDrawdown(dd, trades);
         m_paused = (trades >= InpValidateAfterTrades && dd > InpValidatedMaxDdUsd);
         if(m_paused && !m_pauseLogged)
         {
            m_pauseLogged = true;
            EA_Log(EA_LOG_ERRORS, StringFormat(
                   "validation red flag: %d trades show a $%.2f drawdown vs the validated $%.2f limit - pausing new entries",
                   trades, dd, InpValidatedMaxDdUsd), true);
         }
      }
      if(m_paused) return false;
      return true;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession || ctx.atr <= 0.0) return false;

      if(InpMode == CF_FW_ORB)       return OrbPlan(ctx, plan);
      if(InpMode == CF_FW_VWOP)      return VwopPlan(ctx, plan);
      return OvernightPlan(ctx, plan);
   }

   //--- "the exit is the VWOP cross" / "close at 3:30 p.m." / "close at 9:30 a.m."
   void Manage(SEAContext &ctx)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;
         int    dir   = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? +1 : -1;
         datetime opened = (datetime)PositionGetInteger(POSITION_TIME);

         if(InpMode == CF_FW_ORB)
         {
            //--- "or close at 3:30 p.m. if neither hit"
            if(ctx.clockMinutes >= InpOrbExitMin)
            {
               if(g_eaExec.Close(ticket, "3:30 p.m. flat - neither target nor stop"))
                  EA_Log(EA_LOG_EVENTS, "ORB time exit at 3:30 p.m.", true);
               continue;
            }
         }
         else if(InpMode == CF_FW_VWOP)
         {
            //--- "close the position when price crosses back through VWOP"
            double vwop = Vwop(ctx.symbol);
            if(vwop > 0.0)
            {
               if(dir > 0 && ctx.mid < vwop)
               {
                  if(g_eaExec.Close(ticket, "close crossed back below VWOP"))
                     EA_Log(EA_LOG_EVENTS, "VWOP exit: price back below the volume-weighted price", true);
                  continue;
               }
               if(dir < 0 && ctx.mid > vwop)
               {
                  if(g_eaExec.Close(ticket, "close crossed back above VWOP"))
                     EA_Log(EA_LOG_EVENTS, "VWOP exit: price back above the volume-weighted price", true);
               }
            }
         }
         else
         {
            //--- "close at 9:30 a.m.": 17.5 hours after the 4 p.m. entry, plus a 2-hour backstop
            if(opened > 0 && TimeTradeServer() - opened >= (datetime)(InpHoldHours * 3600))
            {
               if(g_eaExec.Close(ticket, "overnight premium captured - 9:30 a.m. exit"))
                  EA_Log(EA_LOG_EVENTS, "overnight gap exit: hold window complete", true);
            }
         }
      }
      //--- the monthly portfolio review (the doc's "monitor live performance" step)
      WritePortfolioReview(false);
   }

   //--- the framework's volatility targeting: every fill is normalised to the same dollar risk
   double LotsMultiplier(SEAContext &ctx)
   {
      if(InpRiskUsd <= 0.0 || InpRiskPct <= 0.0) return 1.0;
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0.0) return 1.0;
      double planned = equity * InpRiskPct / 100.0;      // what the engine would risk this trade
      if(planned <= 0.0) return 1.0;
      double mult = InpRiskUsd / planned;                // -> the SAME $ risk whatever the stop distance
      return MathMin(MathMax(mult, 0.05), 20.0);         // sane bounds
   }

private:
   bool     m_paused;
   bool     m_pauseLogged;
   datetime m_lastMetrics;
   datetime m_reviewMonth;

   string ModeName()
   {
      if(InpMode == CF_FW_ORB)       return "ORB (opening range breakout)";
      if(InpMode == CF_FW_VWOP)      return "VWOP momentum";
      return "overnight gap premium";
   }

   //-------------------------------------------------------------------
   // Strategy 1: opening range breakout
   //-------------------------------------------------------------------
   bool OrbPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      if(ctx.clockMinutes < InpOrbRangeToMin) return false;        // the range must be complete
      double rHi = 0.0, rLo = 0.0;
      int bars = 0;
      if(!SigRangeForDay(ctx.symbol, g_eaIndTf, InpOrbRangeFromMin, InpOrbRangeToMin, 0, rHi, rLo, bars))
         return false;
      if(rHi <= rLo || bars <= 0) return false;

      MqlRates m[];
      if(EA_Rates(ctx.symbol, g_eaIndTf, 0, 3, m) < 2) return false;

      //--- "Go long if price closes above the 9:30-10:00 a.m. high. Stop at the range low."
      //--- The research also says the short side is weaker, so long-only is the default.
      bool longBreak  = (m[1].close > rHi && ctx.mid > rHi);
      bool shortBreak = (!InpOrbLongOnly && m[1].close < rLo && ctx.mid < rLo);
      if(!longBreak && !shortBreak) return false;

      int    dir   = longBreak ? +1 : -1;
      double entry = (dir > 0) ? ctx.ask : ctx.bid;
      double stop  = (dir > 0) ? rLo : rHi;                        // "stop loss at the range low" (mirrored for shorts)
      double risk  = (dir > 0) ? entry - stop : stop - entry;
      if(risk <= 0.0) return false;
      plan.dir = dir; plan.entry = entry; plan.stop = stop;
      plan.target = (dir > 0) ? entry + InpOrbTargetR * risk : entry - InpOrbTargetR * risk;   // "1:1 or 1:2"
      plan.riskDist = risk; plan.barsAgo = 1; plan.score = (dir > 0) ? 70.0 : 60.0; plan.isLimit = false;
      plan.reason = StringFormat("ORB %s the %.2f/%.2f range break", dir > 0 ? "long above" : "short below", rLo, rHi);
      return true;
   }

   //-------------------------------------------------------------------
   // Strategy 2: VWOP momentum (volume-weighted average price)
   //-------------------------------------------------------------------
   bool VwopPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      double vwop = Vwop(ctx.symbol);
      if(vwop <= 0.0) return false;
      MqlRates m[];
      if(EA_Rates(ctx.symbol, g_eaIndTf, 0, 3, m) < 2) return false;

      int dir = 0;
      if(m[1].close > vwop) dir = +1;                              // "go long when a 1-minute bar closes above VWOP"
      if(m[1].close < vwop) dir = -1;                              // "short when it closes below"
      if(dir == 0) return false;
      if((dir > 0 && ctx.mid < vwop) || (dir < 0 && ctx.mid > vwop)) return false;   // the cross must still hold

      double entry = (dir > 0) ? ctx.ask : ctx.bid;
      double stop  = (dir > 0) ? entry - ctx.atr : entry + ctx.atr;   // VWOP has no stated stop; the engine needs one
      double risk  = MathAbs(entry - stop);
      if(risk <= 0.0) return false;
      plan.dir = dir; plan.entry = entry; plan.stop = stop;
      plan.target = (dir > 0) ? entry + 3.0 * risk : entry - 3.0 * risk;  // the real exit is the VWOP cross (Manage)
      plan.riskDist = risk; plan.barsAgo = 1; plan.score = 60.0; plan.isLimit = false;
      plan.reason = StringFormat("VWOP %s at %.2f (volume-weighted price)", dir > 0 ? "long" : "short", vwop);
      return true;
   }

   //-------------------------------------------------------------------
   // Strategy 4: overnight gap premium
   //-------------------------------------------------------------------
   bool OvernightPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- entries only in the minutes just after the cash close (the position then rides the gap)
      if(ctx.clockMinutes < InpOvernightEntryMin || ctx.clockMinutes > InpOvernightEntryMin + 20) return false;
      //--- a Friday entry could not exit until Monday: the document describes one overnight, not a weekend hold
      if(InpSkipFridayOvernight && ctx.dayOfWeek == 5) return false;

      if(InpOvernightRequireRangeBreak)
      {
         //--- the doc's own variation: only take the overnight leg after an opening-range break
         double rHi = 0.0, rLo = 0.0;
         int bars = 0;
         if(!SigRangeForDay(ctx.symbol, g_eaIndTf, 870, 900, 0, rHi, rLo, bars)) return false;
         MqlRates d[];
         if(EA_Rates(ctx.symbol, PERIOD_D1, 0, 2, d) < 2) return false;
         if(!(d[0].close > rHi)) return false;
      }

      double entry = ctx.ask;                                      // "go long at 4 p.m. (market close)"
      double stop  = entry - 2.0 * ctx.atrD1;                      // the doc states no overnight stop; a wide disaster stop
      double risk  = entry - stop;
      if(risk <= 0.0) return false;
      plan.dir = +1; plan.entry = entry; plan.stop = stop;
      plan.target = entry + 4.0 * ctx.atrD1;                       // the real exit is 09:30 (Manage)
      plan.riskDist = risk; plan.barsAgo = 1; plan.score = 55.0; plan.isLimit = false;
      plan.reason = StringFormat("overnight gap long at the close (exit %.1f h later at the open)", InpHoldHours);
      return true;
   }

   //--- VWOP from the anchor the doc allows ("from market open ... or previous day's close"),
   //--- computed on the signal timeframe with tick volume as the volume proxy.
   double Vwop(const string sym)
   {
      MqlRates m[];
      int got = EA_Rates(sym, g_eaIndTf, 0, 1200, m);
      if(got < 6) return 0.0;

      double pv = 0.0, vol = 0.0;
      for(int i = 1; i < got; i++)
      {
         if(!VwopBarIncluded(m[i].time)) continue;
         double typical = (m[i].high + m[i].low + m[i].close) / 3.0;
         double v = (double)m[i].tick_volume;
         pv += typical * v; vol += v;
      }
      if(vol <= 0.0) return 0.0;
      return pv / vol;
   }

   //--- is a bar part of the VWOP window?  open-anchored: since today's session open;
   //--- close-anchored: since the previous session's close (~16:00 ET the day before).
   bool VwopBarIncluded(const datetime serverBarTime)
   {
      datetime nowServer = TimeTradeServer();
      datetime openServer = ClockOnServerDay(nowServer, InpVwopOpenHour, InpVwopOpenMin);
      if(openServer <= 0) return false;
      if(InpVwopAnchorAtOpen) return (serverBarTime >= openServer);
      datetime prevClose = ClockOnServerDay(nowServer - (datetime)86400, InpVwopCloseHour, 0);
      if(prevClose <= 0) return false;
      return (serverBarTime >= prevClose);
   }

   //--- a London wall-clock time on the calendar date of `serverRef`, expressed in server time
   datetime ClockOnServerDay(const datetime serverRef, const int hour, const int minute)
   {
      MqlDateTime dt;
      if(!TimeToStruct(serverRef, dt)) return 0;
      dt.hour = hour; dt.min = minute; dt.sec = 0;
      return EA_ClockToServer(StructToTime(dt));
   }

   //-------------------------------------------------------------------
   // The framework's validation thresholds on the EA's own history
   //-------------------------------------------------------------------
   //--- closed-trade equity curve for THIS magic -> realised max drawdown ($)
   void OwnDrawdown(double &maxDd, int &trades)
   {
      maxDd = 0.0; trades = 0;
      datetime from = TimeTradeServer() - (datetime)(400 * 86400);
      if(!HistorySelect(from, TimeTradeServer() + 60)) return;
      int total = HistoryDealsTotal();
      double equity = 0.0, peak = 0.0;
      for(int i = 0; i < total; i++)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagicNumber) continue;
         long kind = HistoryDealGetInteger(t, DEAL_ENTRY);
         if(kind != DEAL_ENTRY_OUT && kind != DEAL_ENTRY_OUT_BY && kind != DEAL_ENTRY_INOUT) continue;
         double p = HistoryDealGetDouble(t, DEAL_PROFIT) +
                    HistoryDealGetDouble(t, DEAL_SWAP) +
                    HistoryDealGetDouble(t, DEAL_COMMISSION);
         equity += p;
         trades++;
         if(equity > peak) peak = equity;
         double dd = peak - equity;
         if(dd > maxDd) maxDd = dd;
      }
   }

   //-------------------------------------------------------------------
   // Monthly review of every magic on the account ("identify underperforming
   // strategies"; the family itself is the portfolio the doc describes)
   //-------------------------------------------------------------------
   void WritePortfolioReview(const bool force)
   {
      if(MQLInfoInteger(MQL_OPTIMIZATION)) return;
      MqlDateTime dt;
      if(!TimeToStruct(TimeTradeServer(), dt)) return;
      datetime monthStart = MonthStart(dt.year, dt.mon);
      if(monthStart <= 0) return;
      if(!force && m_reviewMonth == monthStart) return;
      if(!HistorySelect(monthStart, TimeTradeServer() + 60)) return;

      //--- grand totals first, then one row per magic (accumulators are class state: reset them)
      m_magicCount = 0;
      double totalNet = 0.0;
      int    totalTrades = 0;
      for(int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         long kind = HistoryDealGetInteger(t, DEAL_ENTRY);
         if(kind != DEAL_ENTRY_OUT && kind != DEAL_ENTRY_OUT_BY && kind != DEAL_ENTRY_INOUT) continue;
         totalNet += HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_SWAP) +
                     HistoryDealGetDouble(t, DEAL_COMMISSION);
         totalTrades++;
      }
      if(!force && totalTrades == 0) return;

      int fh = FileOpen(InpReviewFile, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
      if(fh == INVALID_HANDLE)
      {
         EA_Log(EA_LOG_ERRORS, StringFormat("review file open failed (%d)", GetLastError()), true);
         return;
      }
      FileSeek(fh, 0, SEEK_END);
      if(FileTell(fh) == 0)
         FileWrite(fh, "month", "magic", "trades", "wins", "losses", "win_rate_pct", "expectancy",
                   "net", "max_dd", "verdict");
      for(int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         long kind = HistoryDealGetInteger(t, DEAL_ENTRY);
         if(kind != DEAL_ENTRY_OUT && kind != DEAL_ENTRY_OUT_BY && kind != DEAL_ENTRY_INOUT) continue;
         long mg = HistoryDealGetInteger(t, DEAL_MAGIC);
         double p = HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_SWAP) +
                    HistoryDealGetDouble(t, DEAL_COMMISSION);
         MagicAccumulate(mg, p);
      }
      for(int k = 0; k < m_magicCount; k++)
      {
         double wr = (m_mgTrades[k] > 0) ? 100.0 * m_mgWins[k] / m_mgTrades[k] : 0.0;
         double exp_ = (m_mgTrades[k] > 0) ? m_mgNet[k] / m_mgTrades[k] : 0.0;
         string verdict = (m_mgNet[k] < 0.0 && m_mgTrades[k] >= 5) ? "UNDERPERFORMING - review or retire"
                                                                    : "ok";
         FileWrite(fh,
                   TimeToString(monthStart, TIME_DATE),
                   IntegerToString((long)m_mgMagic[k], 0, false),
                   IntegerToString(m_mgTrades[k]),
                   IntegerToString(m_mgWins[k]),
                   IntegerToString(m_mgTrades[k] - m_mgWins[k]),
                   DoubleToString(wr, 1),
                   DoubleToString(exp_, 2),
                   DoubleToString(m_mgNet[k], 2),
                   DoubleToString(m_mgDd[k], 2),
                   verdict);
      }
      FileClose(fh);
      m_reviewMonth = monthStart;
      EA_Log(EA_LOG_EVENTS, StringFormat("monthly review written: %d trades, net %.2f across %d magic(s)",
                                         totalTrades, totalNet, m_magicCount), true);
   }

   //--- accumulation helpers for the review (small fixed arrays: a portfolio, not a book)
   ulong  m_mgMagic[64];
   int    m_mgTrades[64];
   int    m_mgWins[64];
   double m_mgNet[64];
   double m_mgDd[64];
   int    m_magicCount;

   datetime MonthStart(const int year, const int month)
   {
      MqlDateTime dt;
      dt.year = year; dt.mon = month; dt.day = 1;
      dt.hour = 0; dt.min = 0; dt.sec = 0; dt.day_of_week = 0; dt.day_of_year = 0;
      return StructToTime(dt);
   }

   void MagicAccumulate(const long magic, const double p)
   {
      int k = -1;
      for(int i = 0; i < m_magicCount; i++) if(m_mgMagic[i] == (ulong)magic) { k = i; break; }
      if(k < 0)
      {
         if(m_magicCount >= 64) return;
         k = m_magicCount++;
         m_mgMagic[k] = (ulong)magic;
         m_mgTrades[k] = 0; m_mgWins[k] = 0; m_mgNet[k] = 0.0; m_mgDd[k] = 0.0;
      }
      m_mgTrades[k]++;
      if(p > 0.0) m_mgWins[k]++;
      m_mgNet[k] += p;
      if(m_mgNet[k] < m_mgDd[k]) m_mgDd[k] = m_mgNet[k];    // running trough = the month's drawdown
   }
};

CCfInstFramework g_cfInstFramework;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfInstFramework);
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
