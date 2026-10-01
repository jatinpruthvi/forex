//+------------------------------------------------------------------+
//|                                                    EATrade.mqh   |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Risk governor + execution manager shared by every additionalEA.  |
//|                                                                  |
//| Design rules:                                                    |
//|   * the governor is fail-closed: unknown state = no new risk     |
//|   * every send is preceded by volume / stops / margin checks     |
//|   * daily anchors survive terminal restarts (GlobalVariables)    |
//|   * management (BE / partials / trail / time stop) is driven     |
//|     from tracked per-position state, never from guesses          |
//+------------------------------------------------------------------+
#ifndef EA_TRADE_MQH
#define EA_TRADE_MQH

//+------------------------------------------------------------------+
//| Position tracking - survives SL/TP moves because we key on the   |
//| ticket, not on price levels.                                     |
//+------------------------------------------------------------------+
struct SPosTrack
{
   ulong    ticket;
   string   symbol;
   int      dir;
   double   entry;
   double   riskDist;     // initial |entry - stop|
   double   sl0;
   bool     beMoved;
   bool     p1Done;
   bool     p2Done;
   datetime opened;
};

SPosTrack g_eaTrack[EA_MAX_POSITIONS];
int       g_eaTrackCount = 0;

int EA_TrackIndex(const ulong ticket)
{
   for(int i = 0; i < g_eaTrackCount; i++)
      if(g_eaTrack[i].ticket == ticket) return i;
   return -1;
}

void EA_TrackRemoveAt(const int idx)
{
   if(idx < 0 || idx >= g_eaTrackCount) return;
   for(int i = idx; i < g_eaTrackCount - 1; i++) g_eaTrack[i] = g_eaTrack[i + 1];
   g_eaTrackCount--;
}

//--- sync the tracking table with live positions belonging to this EA
void EA_SyncTracks()
{
   //--- drop closed tickets
   for(int i = g_eaTrackCount - 1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(g_eaTrack[i].ticket)) EA_TrackRemoveAt(i);
   }
   //--- add new tickets
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      ulong t = PositionGetTicket(p);
      if(t == 0) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != g_eaCfg.magic) continue;
      if(EA_TrackIndex(t) >= 0) continue;
      if(g_eaTrackCount >= EA_MAX_POSITIONS) break;
      int i = g_eaTrackCount;
      g_eaTrack[i].ticket   = t;
      g_eaTrack[i].symbol   = PositionGetString(POSITION_SYMBOL);
      g_eaTrack[i].dir      = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? +1 : -1;
      g_eaTrack[i].entry    = PositionGetDouble(POSITION_PRICE_OPEN);
      g_eaTrack[i].sl0      = PositionGetDouble(POSITION_SL);
      g_eaTrack[i].riskDist = MathAbs(g_eaTrack[i].entry - g_eaTrack[i].sl0);
      g_eaTrack[i].beMoved  = false;
      g_eaTrack[i].p1Done   = false;
      g_eaTrack[i].p2Done   = false;
      g_eaTrack[i].opened   = (datetime)PositionGetInteger(POSITION_TIME);
      g_eaTrackCount++;
   }
}

//--- restore risk distance for a ticket (used right after entry)
void EA_TrackSetRisk(const ulong ticket, const double riskDist)
{
   int i = EA_TrackIndex(ticket);
   if(i >= 0 && riskDist > 0.0) g_eaTrack[i].riskDist = riskDist;
}

//+------------------------------------------------------------------+
//| Position helpers                                                 |
//+------------------------------------------------------------------+
int EA_CountPositions(const string sym, const bool forSymbol)
{
   int n = 0;
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      ulong t = PositionGetTicket(p);
      if(t == 0) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != g_eaCfg.magic) continue;
      if(forSymbol && PositionGetString(POSITION_SYMBOL) != sym) continue;
      n++;
   }
   return n;
}

double EA_FloatingPl(const string sym, const bool forSymbol)
{
   double pl = 0.0;
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      ulong t = PositionGetTicket(p);
      if(t == 0) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != g_eaCfg.magic) continue;
      if(forSymbol && PositionGetString(POSITION_SYMBOL) != sym) continue;
      pl += PositionGetDouble(POSITION_PROFIT) +
            PositionGetDouble(POSITION_SWAP);
   }
   return pl;
}

ulong EA_FindPosition(const string sym, const int dir)
{
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      ulong t = PositionGetTicket(p);
      if(t == 0) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != g_eaCfg.magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != sym) continue;
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      if((dir > 0 && isBuy) || (dir < 0 && !isBuy)) return t;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Risk governor                                                    |
//+------------------------------------------------------------------+
class CEARiskGovernor
{
private:
   double   m_dayStartEquity;
   double   m_weekStartEquity;
   datetime m_weekStamp;         // clock-week the weekly anchor belongs to
   int      m_requestsToday;     // non-emergency trade request counter
   datetime m_requestsStamp;
   datetime m_dayStamp;          // clock-day the anchors belong to
   double   m_hwm;               // high-water mark equity
   double   m_startBalance;      // first balance ever seen (DD floor anchor)
   bool     m_halted;
   string   m_haltReason;
   datetime m_lastTradeTime;

   string   KeyDay()   const { return "EA_" + IntegerToString((long)g_eaCfg.magic) + "_DayStart"; }
   string   KeyHwm()   const { return "EA_" + IntegerToString((long)g_eaCfg.magic) + "_Hwm"; }
   string   KeyStart() const { return "EA_" + IntegerToString((long)g_eaCfg.magic) + "_StartBal"; }
   string   KeyHalt()  const { return "EA_" + IntegerToString((long)g_eaCfg.magic) + "_HaltDay"; }

   datetime ClockDayStart() const
   {
      datetime clk = EA_ClockNow();
      MqlDateTime dt;
      TimeToStruct(clk, dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      return StructToTime(dt);
   }

public:
   CEARiskGovernor() { m_dayStartEquity = 0; m_dayStamp = 0; m_hwm = 0;
                       m_startBalance = 0; m_halted = false; m_haltReason = "";
                       m_lastTradeTime = 0; m_weekStartEquity = 0; m_weekStamp = 0;
                       m_requestsToday = 0; m_requestsStamp = 0; }

   void Init()
   {
      m_dayStamp = ClockDayStart();
      double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);

      //--- start balance (permanent DD floor anchor)
      if(GlobalVariableCheck(KeyStart())) m_startBalance = GlobalVariableGet(KeyStart());
      else { m_startBalance = bal; GlobalVariableSet(KeyStart(), m_startBalance); }

      //--- high-water mark
      if(GlobalVariableCheck(KeyHwm())) m_hwm = GlobalVariableGet(KeyHwm());
      else { m_hwm = eq; GlobalVariableSet(KeyHwm(), m_hwm); }
      if(eq > m_hwm) { m_hwm = eq; GlobalVariableSet(KeyHwm(), m_hwm); }

      //--- day anchor (restart-safe)
      if(GlobalVariableCheck(KeyDay()) && (datetime)GlobalVariableGet(KeyDay() + "_Stamp") == m_dayStamp)
         m_dayStartEquity = GlobalVariableGet(KeyDay());
      else
      {
         m_dayStartEquity = eq;
         GlobalVariableSet(KeyDay(), m_dayStartEquity);
         GlobalVariableSet(KeyDay() + "_Stamp", (double)m_dayStamp);
      }
      //--- halted-day persistence
      if(GlobalVariableCheck(KeyHalt()) && (datetime)GlobalVariableGet(KeyHalt()) == m_dayStamp)
      {
         m_halted = true;
         m_haltReason = "daily halt carried over from a previous session";
      }
      //--- weekly anchor (Monday 00:00 clock)
      m_weekStartEquity = eq;
      MqlDateTime wdt;
      TimeToStruct(EA_ClockNow(), wdt);
      wdt.hour = 0; wdt.min = 0; wdt.sec = 0;
      datetime weekStart = StructToTime(wdt) - (datetime)(((wdt.day_of_week == 0 ? 7 : wdt.day_of_week) - 1) * 86400);
      m_weekStamp = weekStart;
      EA_Log(EA_LOG_EVENTS, StringFormat("risk init: dayStart=%.2f weekStart=%.2f hwm=%.2f startBal=%.2f",
                                         m_dayStartEquity, m_weekStartEquity, m_hwm, m_startBalance));
   }

   void OnTick()
   {
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      if(eq > m_hwm) { m_hwm = eq; GlobalVariableSet(KeyHwm(), m_hwm); }

      //--- weekly anchor rolls on Monday
      MqlDateTime wdt;
      TimeToStruct(EA_ClockNow(), wdt);
      datetime wDayStart = EA_ClockNow();
      MqlDateTime tmp;
      TimeToStruct(wDayStart, tmp);
      tmp.hour = 0; tmp.min = 0; tmp.sec = 0;
      datetime wMonday = StructToTime(tmp) - (datetime)(((tmp.day_of_week == 0 ? 7 : tmp.day_of_week) - 1) * 86400);
      if(wMonday != m_weekStamp)
      {
         m_weekStamp = wMonday;
         m_weekStartEquity = eq;
         EA_Log(EA_LOG_EVENTS, StringFormat("new clock week: weekly anchor reset (%.2f)", eq));
      }
      if(g_eaCfg.weeklyLossPct > 0.0 && m_weekStartEquity > 0.0)
      {
         double wkPct = (eq - m_weekStartEquity) / m_weekStartEquity * 100.0;
         if(wkPct <= -MathAbs(g_eaCfg.weeklyLossPct))
            Halt(StringFormat("weekly loss limit hit (%.2f%%)", wkPct));
      }
      if(m_requestsStamp != ClockDayStart())
      {
         m_requestsStamp = ClockDayStart();
         m_requestsToday = 0;
      }

      datetime dayStart = ClockDayStart();
      if(dayStart != m_dayStamp)
      {
         m_dayStamp = dayStart;
         m_dayStartEquity = eq;
         m_halted = false;
         m_haltReason = "";
         GlobalVariableSet(KeyDay(), m_dayStartEquity);
         GlobalVariableSet(KeyDay() + "_Stamp", (double)m_dayStamp);
         GlobalVariableSet(KeyHalt(), 0.0);
         EA_Log(EA_LOG_EVENTS, StringFormat("new clock day: anchors reset (equity %.2f)", eq));
      }
   }

   double DayStartEquity() const { return m_dayStartEquity; }
   double Hwm()            const { return m_hwm; }
   double StartBalance()   const { return m_startBalance; }
   bool   Halted()         const { return m_halted; }
   string HaltReason()     const { return m_haltReason; }

   void Halt(const string reason)
   {
      if(!m_halted)
      {
         m_halted = true;
         m_haltReason = reason;
         GlobalVariableSet(KeyHalt(), (double)m_dayStamp);
         EA_Log(EA_LOG_EVENTS, "TRADING HALTED: " + reason);
      }
   }

   //--- realized + floating P/L of this EA since the clock-day start
   double DayPl()
   {
      double realized = 0.0;
      datetime from = EA_ClockToServer(m_dayStamp);
      if(HistorySelect(from, TimeTradeServer() + 60))
      {
         int deals = HistoryDealsTotal();
         for(int i = 0; i < deals; i++)
         {
            ulong t = HistoryDealGetTicket(i);
            if(t == 0) continue;
            if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != g_eaCfg.magic) continue;
            long entry = HistoryDealGetInteger(t, DEAL_ENTRY);
            if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY && entry != DEAL_ENTRY_INOUT) continue;
            realized += HistoryDealGetDouble(t, DEAL_PROFIT) +
                        HistoryDealGetDouble(t, DEAL_SWAP) +
                        HistoryDealGetDouble(t, DEAL_COMMISSION);
         }
      }
      return realized + EA_FloatingPl("", false);
   }

   int TradesToday()
   {
      int n = 0;
      datetime from = EA_ClockToServer(m_dayStamp);
      if(HistorySelect(from, TimeTradeServer() + 60))
      {
         int deals = HistoryDealsTotal();
         for(int i = 0; i < deals; i++)
         {
            ulong t = HistoryDealGetTicket(i);
            if(t == 0) continue;
            if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != g_eaCfg.magic) continue;
            if(HistoryDealGetInteger(t, DEAL_ENTRY) == DEAL_ENTRY_IN) n++;
         }
      }
      return n;
   }

   //--- drawdown (percent) from the high-water mark
   double DdFromHwm()
   {
      if(m_hwm <= 0.0) return 0.0;
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      return (m_hwm - eq) / m_hwm * 100.0;
   }

   //--- drawdown (percent) from the starting balance (prop-firm floor)
   double DdFromStart()
   {
      if(m_startBalance <= 0.0) return 0.0;
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      return (m_startBalance - eq) / m_startBalance * 100.0;
   }

   //--- risk multiplier from the tiered HWM throttle (10-year survival docs)
   double HwmThrottle()
   {
      if(!g_eaCfg.useHwmThrottle) return 1.0;
      double dd = DdFromHwm();
      if(g_eaCfg.hwmHaltDd > 0.0 && dd >= g_eaCfg.hwmHaltDd)
      {
         Halt(StringFormat("HWM drawdown %.2f%% >= halt %.2f%%", dd, g_eaCfg.hwmHaltDd));
         return 0.0;
      }
      if(g_eaCfg.hwmTier2Dd > 0.0 && dd >= g_eaCfg.hwmTier2Dd) return g_eaCfg.hwmTier2Mult;
      if(g_eaCfg.hwmTier1Dd > 0.0 && dd >= g_eaCfg.hwmTier1Dd) return g_eaCfg.hwmTier1Mult;
      return 1.0;
   }

   //--- current risk percent after all throttles, or 0 when no new risk
   double EffectiveRiskPct()
   {
      if(g_eaCfg.riskPct <= 0.0) return 0.0;

      double eq = AccountInfoDouble(ACCOUNT_EQUITY);

      //--- prop-firm style permanent floor
      if(g_eaCfg.totalDdPct > 0.0 && DdFromStart() >= g_eaCfg.totalDdPct)
      {
         Halt(StringFormat("equity floor breached (%.2f%% from start balance)", DdFromStart()));
         return 0.0;
      }
      //--- daily loss halt
      if(g_eaCfg.dailyLossPct > 0.0 && m_dayStartEquity > 0.0)
      {
         double dayPct = (eq - m_dayStartEquity) / m_dayStartEquity * 100.0;
         if(dayPct <= -MathAbs(g_eaCfg.dailyLossPct))
         {
            Halt(StringFormat("daily loss limit hit (%.2f%%) - trading resumes next clock day", dayPct));
            return 0.0;
         }
      }
      //--- profit target lock
      if(g_eaCfg.profitTargetPct > 0.0 && m_startBalance > 0.0)
      {
         double gain = (eq - m_startBalance) / m_startBalance * 100.0;
         if(gain >= g_eaCfg.profitTargetPct) return 0.0;
      }
      if(m_halted) return 0.0;

      //--- soft target: shrink risk late in the target zone
      double risk = g_eaCfg.riskPct;
      if(g_eaCfg.softTargetPct > 0.0 && m_startBalance > 0.0)
      {
         double gain = (eq - m_startBalance) / m_startBalance * 100.0;
         if(gain >= g_eaCfg.softTargetPct) risk *= g_eaCfg.softTargetRiskMult;
      }
      //--- HWM drawdown throttle
      risk *= HwmThrottle();
      return MathMax(0.0, risk);
   }

   //--- full pre-trade gate (called by the engine before every entry)
   bool CanOpen(const SEAContext &ctx)
   {
      if(!ctx.terminalReady)            return false;
      if(m_halted)                      return false;
      if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) return false;
      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return false;
      if(ctx.openPositionsAll >= (int)MathMax(1, g_eaCfg.maxOpenPositions)) return false;
      if(g_eaCfg.maxTradesPerDay > 0 && TradesToday() >= g_eaCfg.maxTradesPerDay) return false;
      if(g_eaCfg.minSecondsBetweenTrades > 0 && m_lastTradeTime > 0 &&
         TimeTradeServer() - m_lastTradeTime < g_eaCfg.minSecondsBetweenTrades) return false;
      if(g_eaCfg.maxSpreadPoints > 0.0 && ctx.spreadPoints > g_eaCfg.maxSpreadPoints)
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.1f > %.1f pts - skip", ctx.symbol, ctx.spreadPoints, g_eaCfg.maxSpreadPoints), true);
         return false;
      }
      if(EffectiveRiskPct() <= 0.0)     return false;
      if(g_eaCfg.maxRequestsPerDay > 0 && m_requestsToday >= g_eaCfg.maxRequestsPerDay)
      {
         Halt(StringFormat("daily trade-request cap reached (%d)", m_requestsToday));
         return false;
      }
      if(EA_NewsBlocked())              return false;
      if(g_eaCfg.sessionStartHour >= 0 && !ctx.inSession) return false;
      if(g_eaCfg.noTradeAfterHour >= 0 && ctx.pastNoTradeHour) return false;
      if(ctx.fridayCloseZone)           return false;
      return true;
   }

   void NoteTrade()
   {
      m_lastTradeTime = TimeTradeServer();
      if(m_requestsStamp != ClockDayStart()) { m_requestsStamp = ClockDayStart(); m_requestsToday = 0; }
      m_requestsToday++;
   }

   int RequestsToday() const { return m_requestsToday; }
};

CEARiskGovernor g_eaRisk;

//+------------------------------------------------------------------+
//| Execution manager                                                |
//+------------------------------------------------------------------+
class CEAExecutor
{
private:
   CTrade   m_trade;
   int      m_retries;

   bool SendWithRetry(const bool isBuy, const double lots, const string sym,
                      const double sl, const double tp, const string comment)
   {
      for(int attempt = 0; attempt < m_retries; attempt++)
      {
         bool ok = isBuy ? m_trade.Buy(lots, sym, 0.0, sl, tp, comment)
                         : m_trade.Sell(lots, sym, 0.0, sl, tp, comment);
         uint rc = m_trade.ResultRetcode();
         if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL ||
                   rc == TRADE_RETCODE_PLACED))
            return true;
         if(rc != TRADE_RETCODE_REQUOTE && rc != TRADE_RETCODE_PRICE_CHANGED &&
            rc != TRADE_RETCODE_PRICE_OFF  && rc != TRADE_RETCODE_TIMEOUT)
            break;
         Sleep(150);
      }
      EA_Log(EA_LOG_ERRORS, StringFormat("order failed retcode=%u (%s)",
             m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription()));
      return false;
   }

public:
   CEAExecutor() { m_retries = 3; }

   void Init()
   {
      m_retries = (int)MathMax(1, g_eaCfg.maxRetries);
      m_trade.SetExpertMagicNumber(g_eaCfg.magic);
      m_trade.SetDeviationInPoints((int)MathMax(1, g_eaCfg.deviationPoints));
      m_trade.SetMarginMode();
      m_trade.SetTypeFillingBySymbol(_Symbol);
      m_trade.LogLevel(LOG_LEVEL_ERRORS);
   }

   //--- margin / stops validation shared by market and pending sends
   bool ValidateSend(const string sym, const ENUM_ORDER_TYPE type, const double lots,
                     const double price, const double sl, const double tp)
   {
      if(lots <= 0.0) return false;
      double minV = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double maxV = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
      if(lots < minV - 1e-9 || lots > maxV + 1e-9) return false;

      double point = EA_Point(sym);
      long   stops = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
      if(stops > 0)
      {
         if(sl > 0.0 && MathAbs(price - sl) < stops * point) return false;
         if(tp > 0.0 && MathAbs(price - tp) < stops * point) return false;
      }
      if(g_eaCfg.marginCheck)
      {
         double need = 0.0;
         ENUM_ORDER_TYPE mtype = (type == ORDER_TYPE_BUY || type == ORDER_TYPE_BUY_LIMIT ||
                                  type == ORDER_TYPE_BUY_STOP) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         if(!OrderCalcMargin(mtype, sym, lots, price, need)) return false;
         double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
         double floor = free * (g_eaCfg.marginFreeFloorPct / 100.0);
         if(need > free - floor) return false;
      }
      return true;
   }

   bool OpenMarket(const string sym, const int dir, const double lots,
                   const double sl, const double tp, const string comment)
   {
      ENUM_ORDER_TYPE type = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double px = (dir > 0) ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
      if(px <= 0.0) return false;
      if(!ValidateSend(sym, type, lots, px, sl, tp))
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("%s send validation failed (lots=%.2f)", sym, lots), true);
         return false;
      }
      if(SendWithRetry(dir > 0, lots, sym, sl, tp, comment))
      {
         g_eaRisk.NoteTrade();
         EA_Ledger("OPEN_MARKET", sym, px, sl, tp, lots, comment);
         return true;
      }
      return false;
   }

   bool OpenLimit(const string sym, const int dir, const double price, const double lots,
                  const double sl, const double tp, const int expiryMinutes, const string comment)
   {
      ENUM_ORDER_TYPE type = (dir > 0) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
      if(!ValidateSend(sym, type, lots, price, sl, tp)) return false;
      ENUM_ORDER_TYPE_TIME ttime = ORDER_TIME_GTC;
      datetime expiry = 0;
      if(expiryMinutes > 0)
      {
         ttime  = ORDER_TIME_SPECIFIED;
         expiry = TimeTradeServer() + (datetime)(expiryMinutes * 60);
      }
      for(int attempt = 0; attempt < m_retries; attempt++)
      {
         bool ok = (dir > 0) ? m_trade.BuyLimit(lots, price, sym, sl, tp, ttime, expiry, comment)
                             : m_trade.SellLimit(lots, price, sym, sl, tp, ttime, expiry, comment);
         uint rc = m_trade.ResultRetcode();
         if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED)) 
         {
            g_eaRisk.NoteTrade();
            EA_Ledger("OPEN_LIMIT", sym, price, sl, tp, lots, comment);
            return true;
         }
         if(rc != TRADE_RETCODE_REQUOTE && rc != TRADE_RETCODE_PRICE_CHANGED &&
            rc != TRADE_RETCODE_PRICE_OFF && rc != TRADE_RETCODE_TIMEOUT) break;
         Sleep(150);
      }
      EA_Log(EA_LOG_ERRORS, StringFormat("limit send failed retcode=%u (%s)",
             m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription()));
      return false;
   }

   bool Modify(const ulong ticket, const double sl, const double tp)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      double curSl = PositionGetDouble(POSITION_SL);
      double curTp = PositionGetDouble(POSITION_TP);
      double point = EA_Point(PositionGetString(POSITION_SYMBOL));
      //--- never send a no-op modify (retcode 10025)
      if(MathAbs(curSl - sl) < point * 0.5 && MathAbs(curTp - tp) < point * 0.5) return true;
      if(!m_trade.PositionModify(ticket, sl, tp))
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("modify failed ticket=%I64u retcode=%u", ticket, m_trade.ResultRetcode()), true);
         return false;
      }
      return true;
   }

   bool ClosePartial(const ulong ticket, const double pct)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      double vol    = PositionGetDouble(POSITION_VOLUME);
      string sym    = PositionGetString(POSITION_SYMBOL);
      double minV   = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double step   = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
      if(step <= 0.0) step = minV;
      double part   = EA_NormalizeVolume(sym, vol * pct / 100.0);
      double remain = vol - part;
      if(part < minV - 1e-9 || remain < minV - 1e-9) return false;   // cannot split
      if(!m_trade.PositionClosePartial(ticket, part))
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("partial close failed ticket=%I64u retcode=%u", ticket, m_trade.ResultRetcode()), true);
         return false;
      }
      EA_Ledger("PARTIAL", sym, PositionGetDouble(POSITION_PRICE_CURRENT), 0, 0, part,
                StringFormat("%.0f%% of position", pct));
      return true;
   }

   bool Close(const ulong ticket, const string reason)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      string sym = PositionGetString(POSITION_SYMBOL);
      double px  = PositionGetDouble(POSITION_PRICE_CURRENT);
      if(!m_trade.PositionClose(ticket))
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("close failed ticket=%I64u retcode=%u", ticket, m_trade.ResultRetcode()), true);
         return false;
      }
      EA_Ledger("CLOSE", sym, px, 0, 0, 0, reason);
      return true;
   }

   void CloseAll(const string reason)
   {
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != g_eaCfg.magic) continue;
         Close(t, reason);
      }
   }

   void CancelPending(const string sym, const string reason)
   {
      for(int o = OrdersTotal() - 1; o >= 0; o--)
      {
         ulong t = OrderGetTicket(o);
         if(t == 0) continue;
         if((ulong)OrderGetInteger(ORDER_MAGIC) != g_eaCfg.magic) continue;
         if(sym != "" && OrderGetString(ORDER_SYMBOL) != sym) continue;
         if(m_trade.OrderDelete(t))
            EA_Ledger("CANCEL", OrderGetString(ORDER_SYMBOL), OrderGetDouble(ORDER_PRICE_OPEN), 0, 0, 0, reason);
      }
   }

   bool HasPending(const string sym, const int dir)
   {
      for(int o = OrdersTotal() - 1; o >= 0; o--)
      {
         ulong t = OrderGetTicket(o);
         if(t == 0) continue;
         if((ulong)OrderGetInteger(ORDER_MAGIC) != g_eaCfg.magic) continue;
         if(sym != "" && OrderGetString(ORDER_SYMBOL) != sym) continue;
         ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         if(dir > 0 && (ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_BUY_STOP)) return true;
         if(dir < 0 && (ot == ORDER_TYPE_SELL_LIMIT || ot == ORDER_TYPE_SELL_STOP)) return true;
      }
      return false;
   }
};

CEAExecutor g_eaExec;

//+------------------------------------------------------------------+
//| Open-risk accounting (portfolio sleeves, correlated groups)       |
//+------------------------------------------------------------------+
//--- money currently at risk across this EA's open positions
double EA_OpenRiskMoney()
{
   double total = 0.0;
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      ulong t = PositionGetTicket(p);
      if(t == 0) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != g_eaCfg.magic) continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      double sl  = PositionGetDouble(POSITION_SL);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double vol = PositionGetDouble(POSITION_VOLUME);
      if(sl <= 0.0 || vol <= 0.0) continue;
      bool   isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double dist  = isBuy ? (entry - sl) : (sl - entry);
      if(dist <= 0.0) continue;                       // stop at/beyond entry -> no risk left
      total += EA_LossPerLot(sym, dist) * vol;
   }
   return total;
}

double EA_OpenRiskPct()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq <= 0.0) return 0.0;
   return EA_OpenRiskMoney() / eq * 100.0;
}

//--- open risk restricted to a comma separated symbol group
double EA_GroupRiskPct(const string groupCsv)
{
   double total = 0.0;
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      ulong t = PositionGetTicket(p);
      if(t == 0) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != g_eaCfg.magic) continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      if(StringFind(groupCsv, sym) < 0) continue;
      double sl  = PositionGetDouble(POSITION_SL);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double vol = PositionGetDouble(POSITION_VOLUME);
      if(sl <= 0.0 || vol <= 0.0) continue;
      bool   isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double dist  = isBuy ? (entry - sl) : (sl - entry);
      if(dist <= 0.0) continue;
      total += EA_LossPerLot(sym, dist) * vol;
   }
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq <= 0.0) return 0.0;
   return total / eq * 100.0;
}

//+------------------------------------------------------------------+
//| Engine-level exit management (BE / partials / trail / time stop)  |
//+------------------------------------------------------------------+
//--- price rounding helper (kept separate so it can be reused by strategies)
double eaRoundSafe(const string sym, const double price)
{
   double tick = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0) tick = EA_Point(sym);
   if(tick <= 0.0) return price;
   return MathRound(price / tick) * tick;
}


void EA_ManagePositions(const SEAContext &ctx)
{
   EA_SyncTracks();
   if(g_eaTrackCount == 0) return;

   for(int i = 0; i < g_eaTrackCount; i++)
   {
      ulong  t   = g_eaTrack[i].ticket;
      string sym = g_eaTrack[i].symbol;
      if(!PositionSelectByTicket(t)) continue;
      int    dir  = g_eaTrack[i].dir;
      double risk = g_eaTrack[i].riskDist;
      if(risk <= 0.0) continue;

      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double cur   = PositionGetDouble(POSITION_PRICE_CURRENT);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      double moveR = (dir > 0) ? (cur - entry) : (entry - cur);
      double rMult = moveR / risk;
      double point = EA_Point(sym);

      //--- time stop first (premise dead)
      if(g_eaCfg.timeStopMinutes > 0)
      {
         datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
         if(TimeTradeServer() - opened >= (datetime)(g_eaCfg.timeStopMinutes * 60))
         {
            EA_Log(EA_LOG_EVENTS, StringFormat("%s time stop at %.2fR - closing", sym, rMult));
            g_eaExec.Close(t, "time stop");
            continue;
         }
      }

      //--- partial exits
      if(g_eaCfg.partial1AtR > 0.0 && !g_eaTrack[i].p1Done && rMult >= g_eaCfg.partial1AtR)
      {
         if(g_eaExec.ClosePartial(t, g_eaCfg.partial1Pct)) g_eaTrack[i].p1Done = true;
         else g_eaTrack[i].p1Done = true;   // volume cannot split - treat as done
      }
      if(g_eaCfg.partial2AtR > 0.0 && !g_eaTrack[i].p2Done && rMult >= g_eaCfg.partial2AtR)
      {
         if(g_eaExec.ClosePartial(t, g_eaCfg.partial2Pct)) g_eaTrack[i].p2Done = true;
         else g_eaTrack[i].p2Done = true;
      }

      //--- break-even move
      if(g_eaCfg.breakEvenAtR > 0.0 && !g_eaTrack[i].beMoved && rMult >= g_eaCfg.breakEvenAtR)
      {
         double be = entry + dir * (point * 2.0);      // 2 points past entry
         double newSl = eaRoundSafe(sym, be);
         if((dir > 0 && (sl <= 0.0 || newSl > sl)) || (dir < 0 && (sl <= 0.0 || newSl < sl)))
         {
            if(g_eaExec.Modify(t, newSl, tp)) g_eaTrack[i].beMoved = true;
         }
         else
            g_eaTrack[i].beMoved = true;
      }

      //--- R-based trailing stop
      if(g_eaCfg.trailAtR > 0.0 && rMult >= g_eaCfg.trailAtR)
      {
         double trailDist = g_eaCfg.trailDistanceR * risk;
         double newSl = (dir > 0) ? cur - trailDist : cur + trailDist;
         newSl = eaRoundSafe(sym, newSl);
         if((dir > 0 && newSl > sl + point) || (dir < 0 && (sl <= 0.0 || newSl < sl - point)))
            g_eaExec.Modify(t, newSl, tp);
      }
   }
}

//+------------------------------------------------------------------+
//| Hard calendar flat: session end / Friday close                    |
//+------------------------------------------------------------------+
void EA_CalendarFlats(const SEAContext &ctx)
{
   if(g_eaTrackCount == 0 && EA_CountPositions("", false) == 0) return;

   if(g_eaCfg.sessionEndFlat && g_eaCfg.sessionEndHour >= 0)
   {
      if(!EA_InWindow(ctx.nowClock, g_eaCfg.sessionStartHour, g_eaCfg.sessionStartMin,
                      g_eaCfg.sessionEndHour, g_eaCfg.sessionEndMin))
      {
         EA_Log(EA_LOG_EVENTS, "session ended - flattening EA exposure", true);
         g_eaExec.CancelPending("", "session end");
         g_eaExec.CloseAll("session end flat");
         return;
      }
   }
   if(g_eaCfg.fridayFlat && ctx.dayOfWeek == 5)
   {
      if(!EA_InWindow(ctx.nowClock, 0, 0, g_eaCfg.fridayFlatHour, g_eaCfg.fridayFlatMin))
      {
         EA_Log(EA_LOG_EVENTS, "Friday close zone - flattening EA exposure", true);
         g_eaExec.CancelPending("", "friday flat");
         g_eaExec.CloseAll("friday flat");
      }
   }
}

//+------------------------------------------------------------------+
//| Capped grid / basket manager (round-4 style mean-reversion       |
//| baskets). The basket is defined-risk by construction: `maxLegs`  |
//| legs, `spacing` apart, one direction, hard basket stop.          |
//+------------------------------------------------------------------+
struct SEABasket
{
   bool     active;
   string   symbol;
   int      dir;
   double   anchor;
   double   spacing;
   int      maxLegs;
   double   legLots;
   double   tpDistance;
   double   stopDistance;
   datetime armed;

   void Reset()
   {
      active = false; symbol = ""; dir = 0; anchor = 0; spacing = 0;
      maxLegs = 0; legLots = 0; tpDistance = 0; stopDistance = 0; armed = 0;
   }
};

double EA_BasketAvgEntry(SEABasket &b, int &legCount)
{
   double sumPV = 0.0, sumV = 0.0;
   legCount = 0;
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      ulong t = PositionGetTicket(p);
      if(t == 0) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != g_eaCfg.magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != b.symbol) continue;
      double vol = PositionGetDouble(POSITION_VOLUME);
      sumPV += PositionGetDouble(POSITION_PRICE_OPEN) * vol;
      sumV  += vol;
      legCount++;
   }
   if(sumV <= 0.0) return 0.0;
   return sumPV / sumV;
}

//--- returns true when the basket should fire a new leg
bool EA_BasketShouldAddLeg(SEABasket &b, const double px, int &legCount)
{
   if(!b.active) return false;
   double avg = EA_BasketAvgEntry(b, legCount);
   if(legCount == 0) return false;
   if(legCount >= b.maxLegs) return false;
   double adverse = (b.dir > 0) ? (avg - px) : (px - avg);
   double nextLevel = b.spacing * legCount;
   return (adverse >= nextLevel - 1e-9);
}

void EA_BasketManage(SEABasket &b)
{
   if(!b.active) return;
   int legs = 0;
   double avg = EA_BasketAvgEntry(b, legs);
   if(legs == 0) { b.Reset(); return; }

   double px = (b.dir > 0) ? SymbolInfoDouble(b.symbol, SYMBOL_BID)
                           : SymbolInfoDouble(b.symbol, SYMBOL_ASK);
   if(px <= 0.0 || avg <= 0.0) return;
   double move = (b.dir > 0) ? (px - avg) : (avg - px);

   if(move >= b.tpDistance)
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("basket TP hit (%.1f pts vs %.1f) - closing %d legs",
             move / EA_Point(b.symbol), b.tpDistance / EA_Point(b.symbol), legs));
      g_eaExec.CloseAll("basket take profit");
      b.Reset();
      return;
   }
   if(move <= -b.stopDistance)
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("basket STOP hit (%.1f pts) - closing %d legs",
             move / EA_Point(b.symbol), legs));
      g_eaExec.CloseAll("basket stop loss");
      b.Reset();
      return;
   }
}

#endif // EA_TRADE_MQH
//+------------------------------------------------------------------+
