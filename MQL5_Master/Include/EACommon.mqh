//+------------------------------------------------------------------+
//|                                                     EACommon.mqh |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| The engine every additionalEA plugs into.                        |
//|                                                                  |
//| An EA file is then only:                                         |
//|   1. #include "..\Include\EACommon.mqh"                          |
//|   2. an input block                                             |
//|   3. a class derived from CEAStrategy (Configure + BuildPlan)    |
//|   4. OnInit / OnTick / OnDeinit that call EA_Init / EA_Tick /    |
//|      EA_Deinit.                                                  |
//|                                                                  |
//| Signal -> risk gate -> sizing -> execution -> management is      |
//| identical for all 79 EAs, so a fix in one place fixes all of     |
//| them. Strategies only encode the edge.                           |
//+------------------------------------------------------------------+
#ifndef EA_COMMON_MQH
#define EA_COMMON_MQH

#include "EACore.mqh"
#include "EASignals.mqh"
#include "EASpread.mqh"      // spread history / fill slippage / R outcomes
#include "EATrade.mqh"

//+------------------------------------------------------------------+
//| Strategy interface                                               |
//+------------------------------------------------------------------+
class CEAStrategy
{
public:
   virtual              ~CEAStrategy() {}

   //--- called once with a reset SEASettings block: fill in the EA's defaults
   virtual void         Configure(SEASettings &cfg) {}

   //--- called after handles/risk/execution are ready
   virtual void         OnInitStrategy() {}
   virtual void         OnDeinitStrategy() {}

   //--- the edge: fill `plan` (dir != 0 means "trade this")
   virtual bool         BuildPlan(SEAContext &ctx, SSignalPlan &plan) { return false; }

   //--- optional portfolio hook: rank this symbol's setup (collision ranking)
   virtual double       RankSetup(SEAContext &ctx, const SSignalPlan &plan) { return plan.score; }

   //--- per-tick management hook (runs for every symbol, every tick)
   virtual void         Manage(SEAContext &ctx) {}

   //--- extra admissibility gate (news windows, HTF filters, ...)
   virtual bool         AllowTrading(SEAContext &ctx) { return true; }

   //--- optional lot scaler (half-size variants, multi-account farms)
   virtual double       LotsMultiplier(SEAContext &ctx) { return 1.0; }

   //--- optional: allow several positions on the same symbol (grid/basket EAs)
   virtual bool         AllowMultipleOnSymbol() { return false; }
};

CEAStrategy  *g_eaStrategy   = NULL;
string        g_eaSymbols[EA_MAX_SYMBOLS];
int           g_eaSymbolCount = 0;
datetime      g_eaLastSignalBar = 0;
bool          g_eaInitialised = false;

//+------------------------------------------------------------------+
//| Symbol list parsing                                             |
//+------------------------------------------------------------------+
int EA_ParseSymbols(const string csv)
{
   string parts[];
   int n = StringSplit(csv, ',', parts);
   int used = 0;
   for(int i = 0; i < n && used < EA_MAX_SYMBOLS; i++)
   {
      string s = parts[i];
      StringTrimLeft(s);
      StringTrimRight(s);
      if(StringLen(s) == 0) continue;
      if(!SymbolSelect(s, true))
      {
         EA_Log(EA_LOG_ERRORS, StringFormat("symbol '%s' not available at this broker", s));
         continue;
      }
      //--- normalise to the broker's exact name (suffix handling)
      string brokerName = s;
      if(SymbolInfoDouble(brokerName, SYMBOL_BID) <= 0.0)
      {
         EA_Log(EA_LOG_ERRORS, StringFormat("symbol '%s' has no quotes - skipped", s));
         continue;
      }
      g_eaSymbols[used++] = brokerName;
   }
   //--- loud, not silent: EA_MAX_SYMBOLS is a hard cap.  It fits every delivered
   //--- universe since the owner's #72 decision (10 >= the widest, 10), but a
   //--- future universe could still be wider - truncation must never be silent
   //--- (see docs/EA_BUG_AUDIT.md, eighth pass + eleventh-pass follow-up).
   if(used == EA_MAX_SYMBOLS)
   {
      string skipped = "";
      int seen = 0;
      for(int i = 0; i < n; i++)
      {
         string s = parts[i];
         StringTrimLeft(s);
         StringTrimRight(s);
         if(StringLen(s) == 0) continue;
         seen++;
         if(seen > EA_MAX_SYMBOLS)
            skipped += (StringLen(skipped) > 0 ? "," : "") + s;
      }
      if(StringLen(skipped) > 0)
         EA_Log(EA_LOG_ERRORS, StringFormat("universe lists %d symbols but this engine trades at " +
                "most %d - never traded: %s", seen, EA_MAX_SYMBOLS, skipped));
   }
   g_eaSymbolCount = used;
   return used;
}

//+------------------------------------------------------------------+
//| Context construction                                             |
//+------------------------------------------------------------------+
bool EA_BuildContext(SEAContext &ctx, const string sym, const int idx)
{
   EA_ContextReset(ctx);
   ctx.symbol = sym;
   ctx.index  = idx;

   ctx.nowServer = TimeTradeServer();
   ctx.nowClock  = EA_ClockNow();
   MqlDateTime dt;
   if(!TimeToStruct(ctx.nowClock, dt)) return false;
   ctx.dayOfWeek    = dt.day_of_week;
   ctx.clockMinutes = dt.hour * 60 + dt.min;

   ctx.inSession = true;
   if(g_eaCfg.sessionStartHour >= 0 && g_eaCfg.sessionEndHour >= 0)
      ctx.inSession = EA_InWindow(ctx.nowClock, g_eaCfg.sessionStartHour, g_eaCfg.sessionStartMin,
                                  g_eaCfg.sessionEndHour, g_eaCfg.sessionEndMin);

   ctx.pastNoTradeHour = false;
   if(g_eaCfg.noTradeAfterHour >= 0)
      ctx.pastNoTradeHour = !EA_InWindow(ctx.nowClock, 0, 0, g_eaCfg.noTradeAfterHour, g_eaCfg.noTradeAfterMin);

   ctx.fridayCloseZone = false;
   if(g_eaCfg.fridayFlat && ctx.dayOfWeek == 5)
      ctx.fridayCloseZone = !EA_InWindow(ctx.nowClock, 0, 0, g_eaCfg.fridayFlatHour, g_eaCfg.fridayFlatMin);

   ctx.bid = SymbolInfoDouble(sym, SYMBOL_BID);
   ctx.ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   if(ctx.bid <= 0.0 || ctx.ask <= 0.0) return false;
   ctx.mid = (ctx.bid + ctx.ask) / 2.0;
   ctx.point = EA_Point(sym);
   ctx.pip   = EA_PipSize(sym);
   ctx.spreadPoints = EA_SpreadPoints(sym);
   if(!EA_SymbolReady(sym)) return false;

   if(idx < 0 || idx >= g_eaIndCount) return false;
   SIndSet ind = g_eaInd[idx];
   if(!ind.valid) return false;
   EA_Buf(ind.hAtr,    0, 1, ctx.atr);
   EA_Buf(ind.hAtrD1,  0, 1, ctx.atrD1);
   EA_Buf(ind.hEma20,  0, 1, ctx.ema20);
   EA_Buf(ind.hEma50,  0, 1, ctx.ema50);
   EA_Buf(ind.hEma200, 0, 1, ctx.ema200);
   EA_Buf(ind.hEmaH1_50,  0, 1, ctx.emaH1_50);
   EA_Buf(ind.hEmaH1_200, 0, 1, ctx.emaH1_200);
   EA_Buf(ind.hEmaD1_200, 0, 1, ctx.emaD1_200);
   EA_Buf(ind.hRsi14, 0, 1, ctx.rsi14);
   EA_Buf(ind.hAdx14, 0, 1, ctx.adx14);
   EA_Buf(ind.hAdxD1, 0, 1, ctx.adxD1);
   EA_Buf(ind.hAdxH1, 0, 1, ctx.adxH1);
   EA_Buf(ind.hAdxH4, 0, 1, ctx.adxH4);
   EA_Buf(ind.hAtrH1, 0, 1, ctx.atrH1);

   ctx.equity         = AccountInfoDouble(ACCOUNT_EQUITY);
   ctx.balance        = AccountInfoDouble(ACCOUNT_BALANCE);
   ctx.dayStartEquity = g_eaRisk.DayStartEquity();
   ctx.riskPct        = g_eaRisk.EffectiveRiskPct();
   ctx.riskHalted     = g_eaRisk.Halted();
   ctx.riskHaltReason = g_eaRisk.HaltReason();
   ctx.newsBlocked    = EA_NewsBlocked();
   ctx.openPositions  = EA_CountPositions(sym, true);
   ctx.openPositionsAll = EA_CountPositions("", false);
   ctx.floatingPl     = EA_FloatingPl(sym, true);
   ctx.tradesToday    = g_eaRisk.TradesToday();
   ctx.qualifyingDays = g_eaRisk.QualifyingDays();
   ctx.dayRealizedPl  = g_eaRisk.DayRealizedPl();   // name matches content
   ctx.dayPl          = g_eaRisk.DayPl();
   ctx.terminalReady  = (bool)MQLInfoInteger(MQL_TRADE_ALLOWED) &&
                        (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   return true;
}

//+------------------------------------------------------------------+
//| Init / Deinit                                                    |
//+------------------------------------------------------------------+
int EA_Init(CEAStrategy *strategy)
{
   ResetLastError();
   g_eaStrategy = strategy;
   if(g_eaStrategy == NULL)
   {
      Print("EA_Init: no strategy object supplied");
      return INIT_FAILED;
   }

   SEASettings cfg;
   cfg.Reset();
   g_eaStrategy.Configure(cfg);
   g_eaCfg = cfg;

   if(g_eaCfg.magic == 0)
   {
      Print("EA_Init: magic number must be set (0 = refuse to trade)");
      return INIT_FAILED;
   }
   if(StringLen(g_eaCfg.symbols) == 0)
   {
      Print("EA_Init: no symbols configured");
      return INIT_FAILED;
   }

   g_eaIndTf = g_eaCfg.signalTimeframe;
   if(EA_ParseSymbols(g_eaCfg.symbols) <= 0)
   {
      Print("EA_Init: none of the configured symbols are tradable here");
      return INIT_FAILED;
   }

   //--- indicator handles (created once - never inside OnTick)
   for(int i = 0; i < g_eaSymbolCount; i++)
   {
      if(EA_IndCreate(g_eaSymbols[i], g_eaCfg.signalTimeframe) < 0)
         return INIT_FAILED;
   }

   g_eaRisk.Init();
   g_eaExec.Init();
   g_eaStrategy.OnInitStrategy();

   g_eaInitialised = true;
   EA_Log(EA_LOG_EVENTS, StringFormat("================================================="));
   EA_Log(EA_LOG_EVENTS, StringFormat("%s initialised (magic %s)", g_eaCfg.strategyName, EA_PrettyMagic(g_eaCfg.magic)));
   if(StringLen(g_eaCfg.sourceDoc) > 0) EA_Log(EA_LOG_EVENTS, "source: " + g_eaCfg.sourceDoc);
   EA_Log(EA_LOG_EVENTS, StringFormat("symbols: %s | tf: %s | build: %s",
          g_eaCfg.symbols, EnumToString(g_eaCfg.signalTimeframe), EA_CORE_BUILD_ID));
   EA_Log(EA_LOG_EVENTS, StringFormat("risk/trade: %.3f%% | max positions: %d | max trades/day: %d",
          g_eaCfg.riskPct, g_eaCfg.maxOpenPositions, g_eaCfg.maxTradesPerDay));
   EA_Log(EA_LOG_EVENTS, StringFormat("================================================="));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Tester-only results dump (validation harness)                    |
//|                                                                  |
//| Every Strategy Tester run of every EA writes ONE machine-readable |
//| row, so a 65-EA validation sweep can be summarised without        |
//| opening a single chart.  The file goes to the terminal's COMMON   |
//| folder (shared across tester agents and NOT wiped with the        |
//| per-run sandbox):                                                 |
//|     Common\Files\EA_TestReports\<strategy>_<magic>_<sym>.csv     |
//| Read by validation/mt5_harness/parse_results.py.                  |
//|                                                                  |
//| Optimization passes are skipped (65 x N rows would be noise); the |
//| harness runs single passes (Optimization=0).                      |
//+------------------------------------------------------------------+
void EA_TestReport()
{
   if(!MQLInfoInteger(MQL_TESTER)) return;
   if(MQLInfoInteger(MQL_OPTIMIZATION)) return;

   string dir = "EA_TestReports";
   FolderCreate(dir, FILE_COMMON);                 // false if it already exists
   //--- the TEST symbol is part of the file name: a multi-symbol sweep runs the
   //--- same EA once per universe symbol, and without it every run after the
   //--- first would overwrite the previous result row (eleventh-pass follow-up,
   //--- the "wide universe" sweeps enabled by EA_MAX_SYMBOLS = 10)
   string fname = dir + "/" + g_eaCfg.strategyName + "_" +
                  IntegerToString((long)g_eaCfg.magic) + "_" + _Symbol + ".csv";
   int h = FileOpen(fname, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE)
   {
      EA_Log(EA_LOG_ERRORS, "tester report: cannot write " + fname);
      return;
   }
   FileWriteString(h,
      "strategy,magic,expert,symbols,test_symbol,timeframe,risk_pct," +
      "trades,profit_trades,loss_trades,net_profit,gross_profit,gross_loss," +
      "profit_factor,expected_payoff,equity_dd_pct,balance_dd_pct," +
      "recovery_factor,sharpe,min_lots,max_lots,end_time\r\n");
   FileWriteString(h, StringFormat(
      "%s,%I64d,%s,\"%s\",%s,%s,%.3f," +
      "%d,%d,%d,%.2f,%.2f,%.2f," +
      "%.3f,%.3f,%.3f,%.3f," +
      "%.3f,%.3f,%.2f,%.2f,%s\r\n",
      g_eaCfg.strategyName, (long)g_eaCfg.magic, MQLInfoString(MQL_PROGRAM_NAME),
      g_eaCfg.symbols, _Symbol, EnumToString(g_eaCfg.signalTimeframe), g_eaCfg.riskPct,
      (int)TesterStatistics(STAT_TRADES),
      (int)TesterStatistics(STAT_PROFIT_TRADES),
      (int)TesterStatistics(STAT_LOSS_TRADES),
      TesterStatistics(STAT_PROFIT),
      TesterStatistics(STAT_GROSS_PROFIT),
      TesterStatistics(STAT_GROSS_LOSS),
      TesterStatistics(STAT_PROFIT_FACTOR),
      TesterStatistics(STAT_EXPECTED_PAYOFF),
      TesterStatistics(STAT_EQUITYDD_PERCENT),
      TesterStatistics(STAT_BALANCEDD_PERCENT),
      TesterStatistics(STAT_RECOVERY_FACTOR),
      TesterStatistics(STAT_SHARPE_RATIO),
      TesterStatistics(STAT_MINLOTS_VOLUME),
      TesterStatistics(STAT_MAXLOTS_VOLUME),
      TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES)));
   FileClose(h);
   EA_Log(EA_LOG_EVENTS, "tester report written: Common\\Files\\" + fname);
}

void EA_Deinit(const int reason)
{
   EA_TestReport();                                // tester-only, no-op live
   if(g_eaStrategy != NULL) g_eaStrategy.OnDeinitStrategy();
   EA_IndReleaseAll();
   g_eaInitialised = false;
   EA_Log(EA_LOG_EVENTS, StringFormat("deinitialised (reason %d)", reason));
}

//+------------------------------------------------------------------+
//| Exit management for every symbol (runs on every tick)            |
//+------------------------------------------------------------------+
void EA_ManageAll()
{
   for(int i = 0; i < g_eaSymbolCount; i++)
   {
      SEAContext ctx;
      if(!EA_BuildContext(ctx, g_eaSymbols[i], i)) continue;
      //--- execution-cost telemetry: one spread sample per symbol per minute
      EA_SpreadSample(ctx.symbol, ctx.spreadPoints);
      g_eaStrategy.Manage(ctx);
      EA_PendingHygiene(ctx);
      EA_ManagePositions(ctx);
      EA_CalendarFlats(ctx);
   }
}

//+------------------------------------------------------------------+
//| Signal phase - only on a new bar of the signal timeframe         |
//+------------------------------------------------------------------+
bool EA_IsNewSignalBar()
{
   if(g_eaSymbolCount <= 0) return false;
   datetime t = iTime(g_eaSymbols[0], g_eaCfg.signalTimeframe, 0);
   if(t == 0) return false;
   if(t == g_eaLastSignalBar) return false;
   g_eaLastSignalBar = t;
   return true;
}

//--- choose the highest-ranked admissible plan across the universe
bool EA_SelectPlan(SSignalPlan &best, SEAContext &bestCtx)
{
   bool found = false;
   best.Reset();

   for(int i = 0; i < g_eaSymbolCount; i++)
   {
      SEAContext ctx;
      if(!EA_BuildContext(ctx, g_eaSymbols[i], i)) continue;
      if(!g_eaStrategy.AllowTrading(ctx)) continue;
      if(g_eaCfg.newsFilter && EA_NewsBlocked())
      {
         EA_Log(EA_LOG_EVENTS, "news blackout active - no new risk", true);
         continue;
      }
      if(!g_eaRisk.CanOpen(ctx)) continue;
      if(g_eaCfg.oneEntryAccountWide)
      {
         if(ctx.openPositionsAll > 0) continue;                           // one position account-wide
         if(EA_CountPendings("") > 0) continue;                           // one working entry account-wide
      }
      if(!g_eaStrategy.AllowMultipleOnSymbol())
      {
         if(ctx.openPositions > 0) continue;                              // already positioned
         if(g_eaExec.HasPending(ctx.symbol, +1) || g_eaExec.HasPending(ctx.symbol, -1)) continue;
      }

      SSignalPlan plan;
      if(!g_eaStrategy.BuildPlan(ctx, plan)) continue;
      if(plan.dir == 0) continue;
      if(plan.riskDist <= 0.0) continue;
      if(plan.entry <= 0.0) continue;
      if(plan.dir > 0 && plan.stop >= plan.entry) continue;
      if(plan.dir < 0 && plan.stop <= plan.entry) continue;
      plan.score = g_eaStrategy.RankSetup(ctx, plan);
      if(!found || plan.score > best.score)
      {
         best     = plan;
         bestCtx  = ctx;
         found    = true;
      }
   }
   return found;
}

//--- record the risk distance and the fill for a position that just opened
void EA_BookFill(const SEAContext &ctx, const SSignalPlan &plan, const ulong ticket)
{
   if(ticket == 0) return;
   EA_TrackSetRisk(ticket, plan.riskDist);
   //--- fill-vs-signal (documents require every fill to be logged)
   if(PositionSelectByTicket(ticket))
      EA_SlipRecord(ctx.symbol, plan.entry, PositionGetDouble(POSITION_PRICE_OPEN), plan.riskDist);
}

//--- size and execute a plan
void EA_ExecutePlan(const SEAContext &ctx, const SSignalPlan &plan)
{
   if(plan.dir == 0) return;
   double riskPct = MathMin(ctx.riskPct, 5.0);                 // hard safety clamp
   if(riskPct <= 0.0) return;
   riskPct *= g_eaStrategy.LotsMultiplier(ctx);
   if(riskPct <= 0.0) return;

   //--- all-in cost gate: spread + commission expressed in R
   if(g_eaCfg.maxCostR > 0.0)
   {
      double costR = EA_CostInR(ctx.symbol, plan.riskDist, g_eaCfg.commissionPerLotRT);
      if(costR > g_eaCfg.maxCostR)
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("%s all-in cost %.3fR > %.3fR budget - skip",
                ctx.symbol, costR, g_eaCfg.maxCostR), true);
         return;
      }
   }

   double base = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_eaCfg.riskBaseInitialBalance && g_eaCfg.riskInitialBalance > 0.0)
      base = g_eaCfg.riskInitialBalance;                      // phase-initial balance (LOCKED risk base)
   else if(g_eaCfg.riskBaseBalance)
      base = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = base * riskPct / 100.0;
   double lots      = EA_LotsForRisk(ctx.symbol, riskMoney, plan.riskDist);
   //--- re-check with commission included so the all-in loss stays inside the budget
   if(lots > 0.0 && g_eaCfg.commissionPerLotRT > 0.0)
   {
      double allIn = EA_LossPerLotAllIn(ctx.symbol, plan.riskDist, g_eaCfg.commissionPerLotRT);
      if(allIn > 0.0)
      {
         double lotsAllIn = EA_NormalizeVolume(ctx.symbol, riskMoney / allIn);
         if(lotsAllIn > 0.0) lots = MathMin(lots, lotsAllIn);
      }
   }
   if(lots <= 0.0)
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("%s lot sizing produced 0 (risk=%.2f dist=%.5f)",
             ctx.symbol, riskMoney, plan.riskDist), true);
      return;
   }

   //--- Stage 6: the smallest tradable lot must still fit the risk budget,
   //--- otherwise the broker minimum forces more risk than the tier allows
   double minLots = SymbolInfoDouble(ctx.symbol, SYMBOL_VOLUME_MIN);
   if(minLots > 0.0)
   {
      double allInPerLot = EA_LossPerLotAllIn(ctx.symbol, plan.riskDist, g_eaCfg.commissionPerLotRT);
      double minLotRisk   = allInPerLot * minLots;
      if(minLotRisk > riskMoney * 1.0001)
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("%s minimum lot %.2f risks %.2f > budget %.2f - skip (minimum lot unsafe)",
                ctx.symbol, minLots, minLotRisk, riskMoney), true);
         return;
      }
   }

   double sl = eaRoundSafe(ctx.symbol, plan.stop);
   double tp = eaRoundSafe(ctx.symbol, plan.target);
   string note = plan.reason;

   //--- limit-only configurations never chase a market fill
   if(g_eaCfg.useLimitEntry && !(plan.entry > 0.0))
   {
      EA_Log(EA_LOG_ERRORS, StringFormat("%s limit-only config without a limit price - entry skipped", ctx.symbol), true);
      return;
   }

   if((plan.isLimit || g_eaCfg.useLimitEntry) && plan.entry > 0.0)
   {
      double px  = eaRoundSafe(ctx.symbol, plan.entry);
      double gap = EA_MinStopDistance(ctx.symbol);
      //--- a resting limit must sit BEHIND the market: a buy limit at or above
      //--- the ask (sell at or below the bid) is rejected as an invalid price,
      //--- so a plan asking for a price the market already offers must be filled
      //--- now - send it as a market order instead of a dead resting order
      bool marketable = (plan.dir > 0) ? (px >= ctx.ask) : (px <= ctx.bid);
      bool tooClose   = (plan.dir > 0) ? (px > ctx.ask - gap) : (px < ctx.bid + gap);
      if(marketable)
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("%s limit %.5f already offered (bid %.5f ask %.5f) - entering at market",
                ctx.symbol, px, ctx.bid, ctx.ask), true);
         if(g_eaExec.OpenMarket(ctx.symbol, plan.dir, lots, sl, tp, note))
            EA_BookFill(ctx, plan, EA_FindPosition(ctx.symbol, plan.dir));
         return;
      }
      if(tooClose)
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("%s limit %.5f is inside the broker stops level - entry skipped",
                ctx.symbol, px), true);
         return;
      }
      if(g_eaExec.HasPending(ctx.symbol, plan.dir)) return;
      //--- plan.expiry is an absolute server timestamp while OpenLimit wants a
      //--- lifetime in minutes: convert, so a plan that pins its own expiry is
      //--- honoured and the standard helpers (now + cfg.pendingExpiryMinutes)
      //--- still yield exactly the configured lifetime.
      int expMinutes = 0;
      if(plan.expiry > 0)
      {
         datetime srvNow = TimeTradeServer();
         expMinutes = (plan.expiry > srvNow)
                      ? (int)MathMax(1, (plan.expiry - srvNow) / 60)
                      : g_eaCfg.pendingExpiryMinutes;
      }
      g_eaExec.OpenLimit(ctx.symbol, plan.dir, px, lots, sl, tp, expMinutes, note);
   }
   else
   {
      if(g_eaExec.OpenMarket(ctx.symbol, plan.dir, lots, sl, tp, note))
         EA_BookFill(ctx, plan, EA_FindPosition(ctx.symbol, plan.dir));
   }
}

//--- close everything for this EA (kill switch)
void EA_FlattenAll(const string reason)
{
   g_eaExec.CancelPending("", reason);
   g_eaExec.CloseAll(reason);
}

//--- count our pending orders
int EA_CountPendings(const string sym)
{
   int n = 0;
   for(int o = OrdersTotal() - 1; o >= 0; o--)
   {
      ulong t = OrderGetTicket(o);
      if(t == 0) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != g_eaCfg.magic) continue;
      if(sym != "" && OrderGetString(ORDER_SYMBOL) != sym) continue;
      n++;
   }
   return n;
}

//--- one halt-flatten per engine.  The delivered EAs are one program per
//--- magic, but the portfolio host runs all 65 in one program, so the latch
//--- is keyed by magic: a shared static would let a second halted engine
//--- skip its flatten because the first one already fired.
long g_eaHaltHandledMagic = 0;

//+------------------------------------------------------------------+
//| Main tick                                                        |
//+------------------------------------------------------------------+
void EA_Tick()
{
   if(!g_eaInitialised || g_eaStrategy == NULL) return;
   g_eaRisk.OnTick();
   EA_ManageAll();

   //--- a halt cancels every entry and closes exposure (kill switch)
   if(g_eaCfg.flattenOnHalt)
   {
      if(!g_eaRisk.Halted()) g_eaHaltHandledMagic = 0;
      else if(g_eaHaltHandledMagic != (long)g_eaCfg.magic)
      {
         g_eaHaltHandledMagic = (long)g_eaCfg.magic;
         EA_Log(EA_LOG_EVENTS, "halt: cancelling entries and flattening (" + g_eaRisk.HaltReason() + ")", true);
         EA_FlattenAll("halt flatten");
      }
   }

   //--- red-folder rule: flat this many minutes before the event
   if(g_eaCfg.newsFlatBeforeMin > 0.0)
   {
      int toNews = EA_NewsMinutesToNext();
      if(toNews >= 0 && toNews <= (int)MathCeil(g_eaCfg.newsFlatBeforeMin) &&
         (EA_CountPositions("", false) > 0 || EA_CountPendings("") > 0))
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("red event in %d min: flattening before the release", toNews), true);
         EA_FlattenAll("pre-news flat");
      }
   }

   if(g_eaCfg.signalOnNewBarOnly && !EA_IsNewSignalBar()) return;
   if(!g_eaCfg.signalOnNewBarOnly) g_eaLastSignalBar = iTime(g_eaSymbols[0], g_eaCfg.signalTimeframe, 0);

   SSignalPlan best;
   SEAContext  bestCtx;
   if(!EA_SelectPlan(best, bestCtx)) return;
   EA_ExecutePlan(bestCtx, best);
   EA_Log(EA_LOG_EVENTS, StringFormat("signal %s %s @ %.5f sl %.5f tp %.5f (%.0f)",
          bestCtx.symbol, best.dir > 0 ? "BUY" : "SELL", best.entry, best.stop, best.target, best.score));
}

//+------------------------------------------------------------------+
//| Optional helpers used by individual EAs                          |
//+------------------------------------------------------------------+

#endif // EA_COMMON_MQH
//+------------------------------------------------------------------+
