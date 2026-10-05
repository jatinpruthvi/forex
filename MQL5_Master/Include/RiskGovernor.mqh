//+------------------------------------------------------------------+
//|                                                 RiskGovernor.mqh |
//|                                  Copyright 2026, Master Strategy |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Constants based on Master Strategy (Stage 0)
#define MAX_DAILY_LOSS_PCT     0.022  // -2.2% Daily Breaker
#define MAX_TRAILING_DD_PCT    0.040  // -4.0% Peak-to-Trough Freeze
#define MAX_FUNDED_HEAT_PCT    0.020  // 2.0% max total heat (funded)
#define MAX_FUNDED_CCY_PCT     0.015  // 1.5% max net currency exposure (funded)
#define MARGIN_FLOOR_PCT       0.100  // 10% free margin floor
#define FREEZE_TRAILING_HOURS  48      // trailing-DD freeze (not cleared by the day boundary)

class CRiskGovernor
{
private:
    double         m_initialDailyBalance;
    double         m_peakEquity;
    datetime       m_dailyFreezeDay;    // daily-loss breaker: frozen for THIS server day
    datetime       m_trailingFreezeUntil; // trailing-DD breaker: absolute expiry (48 h)
    datetime       m_lastDayStart;      // server-day key: the full date, not day_of_year
    datetime       m_lastFlatAttempt;   // rate-limit for the flatten retries
    datetime       m_lastFreezeLog;     // rate-limit for the freeze message (it fired every second)
    ulong          m_magic;
    CPositionInfo  m_position;
    CTrade         m_trade;

    //--- GlobalVariable keys are namespaced by account AND magic (#9): a stale
    //--- peak/anchors from another account or another EA can no longer leak in.
    string         GvKey(const string suffix) const;
    datetime       StartOfServerDay() const;
    void           SaveState() const;

public:
                   CRiskGovernor(ulong magic = 777112);
                  ~CRiskGovernor();
                  
    int            CloseAllPositions();      // returns what is STILL open afterwards (0 = flat)
    int            CountExposure();          // this magic's positions + pending orders
    void           FlattenResidual();        // retry the flatten (rate-limited) until nothing is left
    
    // Core Stage 0 Checks
    bool           IsTradingAllowed();
    
    // Pre-Trade Assertions
    bool           PassesPreTradeAssertions(string symbol, double proposedRiskPct);
    
    // Equity Curve Evasion
    double         GetEquityCurveThrottleMultiplier();

    double         GetDailyRealizedPnL();
    double         GetTotalPortfolioHeat();
    double         GetNetCurrencyExposure(string targetCurrency);
};

//+------------------------------------------------------------------+
//| namespaced GlobalVariable helpers (#9)                           |
//|                                                                  |
//| The delivered code used four fixed names (MasterTriad_PeakEquity |
//| etc.) shared by every account and every magic, and keyed the day  |
//| on day_of_year alone.  Two consequences: switching to a fresh     |
//| prop account inherited the old peak (the -4% trailing breaker     |
//| could trip on the first tick), and a restart exactly one year     |
//| later on the same day-of-year was treated as "same day".          |
//| Every key now carries account + magic, and the day key is the     |
//| full server date.                                                 |
//+------------------------------------------------------------------+
string CRiskGovernor::GvKey(const string suffix) const
{
    return StringFormat("MasterTriad_%I64d_%I64d_%s",
                        (long)AccountInfoInteger(ACCOUNT_LOGIN), (long)m_magic, suffix);
}

datetime CRiskGovernor::StartOfServerDay() const
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    dt.hour = 0; dt.min = 0; dt.sec = 0;
    return StructToTime(dt);
}

void CRiskGovernor::SaveState() const
{
    GlobalVariableSet(GvKey("PeakEquity"), m_peakEquity);
    GlobalVariableSet(GvKey("InitialBalance"), m_initialDailyBalance);
    GlobalVariableSet(GvKey("DayStart"), (double)m_lastDayStart);
    GlobalVariableSet(GvKey("DailyFreezeDay"), (double)m_dailyFreezeDay);
    GlobalVariableSet(GvKey("TrailingFreezeUntil"), (double)m_trailingFreezeUntil);
}

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CRiskGovernor::CRiskGovernor(ulong magic)
  : m_magic(magic)
{
    m_lastFlatAttempt = 0;
    m_lastFreezeLog   = 0;
    // CRITICAL FIX: Terminal Restart / VPS Reboot Persistence
    // If the terminal crashes, memory resets. We MUST read peak equity and breakers from disk.

    if(GlobalVariableCheck(GvKey("PeakEquity")))
        m_peakEquity = GlobalVariableGet(GvKey("PeakEquity"));
    else
    {
        m_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        GlobalVariableSet(GvKey("PeakEquity"), m_peakEquity);
    }

    m_dailyFreezeDay       = GlobalVariableCheck(GvKey("DailyFreezeDay"))
                             ? (datetime)GlobalVariableGet(GvKey("DailyFreezeDay")) : 0;
    m_trailingFreezeUntil  = GlobalVariableCheck(GvKey("TrailingFreezeUntil"))
                             ? (datetime)GlobalVariableGet(GvKey("TrailingFreezeUntil")) : 0;

    // CRITICAL FIX: Prevent the Daily Loss Limit resetting on a VPS reboot mid-day
    datetime dayStart = StartOfServerDay();
    if(GlobalVariableCheck(GvKey("DayStart")) &&
       (datetime)GlobalVariableGet(GvKey("DayStart")) == dayStart)
    {
        m_lastDayStart        = dayStart;
        m_initialDailyBalance = GlobalVariableCheck(GvKey("InitialBalance"))
                                ? GlobalVariableGet(GvKey("InitialBalance"))
                                : AccountInfoDouble(ACCOUNT_BALANCE);
    }
    else
    {
        m_lastDayStart        = 0;      // forces the rollover on the first check
        m_initialDailyBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    }

    //--- UPGRADE PATH: the delivered scheme used un-namespaced keys.  Adopt the
    //--- values once so an existing anchor/freeze survives the upgrade instead of
    //--- silently resetting (a reset peak would *delay* the -4% trailing breaker),
    //--- then delete the legacy keys so they cannot shadow the namespaced state.
    if(!GlobalVariableCheck(GvKey("PeakEquity")) &&
        GlobalVariableCheck("MasterTriad_PeakEquity"))
    {
        m_peakEquity = GlobalVariableGet("MasterTriad_PeakEquity");
        GlobalVariableSet(GvKey("PeakEquity"), m_peakEquity);
        Print("RISK SHIELD: adopted the pre-upgrade peak equity anchor.");
    }
    if(!GlobalVariableCheck(GvKey("InitialBalance")) &&
        GlobalVariableCheck("MasterTriad_InitialBalance"))
    {
        m_initialDailyBalance = GlobalVariableGet("MasterTriad_InitialBalance");
        GlobalVariableSet(GvKey("InitialBalance"), m_initialDailyBalance);
    }
    if(m_trailingFreezeUntil == 0 && GlobalVariableCheck("MasterTriad_BreakerTime"))
    {
        // the delivered single timestamp was the only freeze record - keep it as the
        // trailing freeze (the conservative reading: trading stays blocked until then)
        datetime legacyFreeze = (datetime)GlobalVariableGet("MasterTriad_BreakerTime");
        if(legacyFreeze > TimeCurrent())
        {
            m_trailingFreezeUntil = legacyFreeze;
            GlobalVariableSet(GvKey("TrailingFreezeUntil"), (double)m_trailingFreezeUntil);
        }
    }
    GlobalVariableDel("MasterTriad_PeakEquity");
    GlobalVariableDel("MasterTriad_BreakerTime");
    GlobalVariableDel("MasterTriad_LastDay");
    GlobalVariableDel("MasterTriad_InitialBalance");
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CRiskGovernor::~CRiskGovernor()
{
}

//+------------------------------------------------------------------+
//| Check if trading is allowed (Breakers)                           |
//+------------------------------------------------------------------+
bool CRiskGovernor::IsTradingAllowed()
{
    // The two breakers have DIFFERENT semantics (#10), and the code now says what
    // the messages say:
    //   * daily loss (-2.2% on equity): a prop-firm daily rule - the freeze lasts
    //     for the remainder of THAT trading day and lifts at the day boundary;
    //   * trailing DD (-4% peak-to-trough): a fund-level breach - a full 48 h
    //     freeze that the day boundary does NOT lift.
    // The delivered code set one timestamp for both and cleared it at the day
    // boundary, so a breaker tripped at 23:50 was lifted ten minutes later.

    datetime dayStart = StartOfServerDay();
    if(dayStart != m_lastDayStart)
    {
        m_initialDailyBalance = AccountInfoDouble(ACCOUNT_BALANCE); // static start-of-day balance
        m_lastDayStart        = dayStart;
        m_dailyFreezeDay      = 0;                                  // daily breaker lifts; trailing does not
        SaveState();
        Print("RISK SHIELD: new trading day ", TimeToString(dayStart, TIME_DATE),
              " - daily anchor reset, daily freeze lifted.");
    }

    if(m_trailingFreezeUntil > 0 && TimeCurrent() < m_trailingFreezeUntil)
    {
        FlattenResidual();       // the trip's close may have failed - never leave exposure unmanaged
        if(TimeCurrent() - m_lastFreezeLog >= 900)       // (was: one line per second for 48 hours)
        {
            m_lastFreezeLog = TimeCurrent();
            Print("RISK GOVERNOR: trailing-DD freeze active until ",
                  TimeToString(m_trailingFreezeUntil));
        }
        return false;
    }

    if(m_dailyFreezeDay == dayStart)
    {
        FlattenResidual();
        if(TimeCurrent() - m_lastFreezeLog >= 900)
        {
            m_lastFreezeLog = TimeCurrent();
            Print("RISK GOVERNOR: daily-loss freeze active for ", TimeToString(dayStart, TIME_DATE),
                  " - trading resumes at the next day boundary");
        }
        return false;
    }

    // CRITICAL FIX: Daily Loss must be calculated on EQUITY (Open + Closed), not just closed PnL.
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double dailyLossPct = (m_initialDailyBalance > 0) ? ((currentEquity - m_initialDailyBalance) / m_initialDailyBalance) : 0;

    if(dailyLossPct <= -MAX_DAILY_LOSS_PCT)
    {
        Print("RISK GOVERNOR BREAKER TRIPPED: daily equity loss ",
              DoubleToString(dailyLossPct*100, 2), "%. Closing all; no new entries for the rest of ",
              TimeToString(dayStart, TIME_DATE), ".");
        int left = CloseAllPositions();
        if(left > 0)
            Print("RISK GOVERNOR WARNING: ", left, " position(s)/order(s) could NOT be closed - retrying every 5 s.");
        m_dailyFreezeDay = dayStart;
        SaveState();
        return false;
    }

    // Check Peak-to-Trough Trailing DD
    if(m_peakEquity == 0 || currentEquity > m_peakEquity)
    {
        m_peakEquity = currentEquity;
        GlobalVariableSet(GvKey("PeakEquity"), m_peakEquity);
    }

    double currentDD = (m_peakEquity > 0) ? ((m_peakEquity - currentEquity) / m_peakEquity) : 0;
    if(currentDD >= MAX_TRAILING_DD_PCT)
    {
        Print("RISK GOVERNOR BREAKER TRIPPED: trailing DD ",
              DoubleToString(currentDD*100, 2), "%. Closing all; freeze ",
              FREEZE_TRAILING_HOURS, "h (the day boundary does not lift this one).");
        int left = CloseAllPositions();
        if(left > 0)
            Print("RISK GOVERNOR WARNING: ", left, " position(s)/order(s) could NOT be closed - retrying every 5 s.");
        m_trailingFreezeUntil = TimeCurrent() + (datetime)(FREEZE_TRAILING_HOURS * 3600);
        SaveState();
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Pre-Trade Assertions                                             |
//+------------------------------------------------------------------+
bool CRiskGovernor::PassesPreTradeAssertions(string symbol, double proposedRiskPct)
{
    double marginFree = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    if(marginFree < (balance * MARGIN_FLOOR_PCT))
    {
        Print("ASSERTION FAILED: Free margin below ", DoubleToString(MARGIN_FLOOR_PCT*100,0), "% floor.");
        return false;
    }
    
    double currentHeat = GetTotalPortfolioHeat();
    if((currentHeat + proposedRiskPct) > MAX_FUNDED_HEAT_PCT)
    {
        Print("ASSERTION FAILED: Proposed trade breaches Max Portfolio Heat of ", DoubleToString(MAX_FUNDED_HEAT_PCT*100, 2), "%");
        return false;
    }
    
    // CRITICAL FIX: Suffix/Prefix Support (e.g. EURUSD.m or #EURUSD)
    // Using StringSubstr(0,3) fails on brokers with suffixes. Must use API.
    string baseCcy = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
    string quoteCcy = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
    
    double baseExposure = GetNetCurrencyExposure(baseCcy);
    double quoteExposure = GetNetCurrencyExposure(quoteCcy);
    
    if((baseExposure + proposedRiskPct) > MAX_FUNDED_CCY_PCT || (quoteExposure + proposedRiskPct) > MAX_FUNDED_CCY_PCT)
    {
        Print("ASSERTION FAILED: Proposed trade breaches Net Currency Cap for ", symbol);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Equity Curve Evasion (Throttle)                                  |
//+------------------------------------------------------------------+
double CRiskGovernor::GetEquityCurveThrottleMultiplier()
{
    return 1.0; 
}

//+------------------------------------------------------------------+
//| Helper: Get Daily Realized PnL (Kept for historical logs)        |
//+------------------------------------------------------------------+
double CRiskGovernor::GetDailyRealizedPnL()
{
    // #14: the delivered day start was `TimeCurrent() % 86400` - the epoch modulo
    // is UTC midnight, not the broker's midnight - and the sum ignored magic.
    datetime startOfDay = StartOfServerDay();
    HistorySelect(startOfDay, TimeCurrent() + 1);
    double pnl = 0;
    for(int i = 0; i < HistoryDealsTotal(); i++)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(ticket == 0) continue;
        if((long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != (long)m_magic) continue;
        long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
        if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_INOUT)
            pnl += HistoryDealGetDouble(ticket, DEAL_PROFIT)
                 + HistoryDealGetDouble(ticket, DEAL_COMMISSION)
                 + HistoryDealGetDouble(ticket, DEAL_SWAP);
    }
    return pnl;
}

//+------------------------------------------------------------------+
//| Helper: Close All Positions AND PENDING ORDERS                   |
//|                                                                  |
//| The delivered version was fire-and-forget: it ignored every      |
//| return code, the breaker then set its freeze flag regardless, and |
//| the freeze branches simply returned - so one rejected close (a    |
//| requote, a closed market, an unsupported fill mode) left the      |
//| position open FOR THE WHOLE FREEZE with nothing managing it       |
//| (OnTimer returns before OnTickMaintenance while frozen).  The     |
//| Friday 21:00 auto-close had the same one-shot shape.              |
//|                                                                  |
//| Now: the fill mode is set per symbol before each close (this      |
//| object's CTrade never configured one, while the executors do),    |
//| failures are reported, the function returns what is still open,   |
//| and FlattenResidual() retries every 5 s until nothing is left.    |
//+------------------------------------------------------------------+
int CRiskGovernor::CloseAllPositions()
{
    // Close open positions
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(m_position.SelectByIndex(i))
        {
            if(m_position.Magic() == m_magic)
            {
                string sym = m_position.Symbol();
                m_trade.SetTypeFillingBySymbol(sym);
                if(!m_trade.PositionClose(m_position.Ticket()))
                    Print("RISK GOVERNOR: close of #", m_position.Ticket(), " ", sym,
                          " failed - retcode ", m_trade.ResultRetcode());
            }
        }
    }
    // CRITICAL FIX: Also delete pending limit orders so they don't trigger during freeze
    COrderInfo order;
    for(int j = OrdersTotal() - 1; j >= 0; j--)
    {
        if(order.SelectByIndex(j))
        {
            if(order.Magic() == m_magic)
            {
                if(!m_trade.OrderDelete(order.Ticket()))
                    Print("RISK GOVERNOR: delete of order #", order.Ticket(),
                          " failed - retcode ", m_trade.ResultRetcode());
            }
        }
    }
    return CountExposure();
}

//--- this magic's open positions + pending orders (what a flatten must drive to zero)
int CRiskGovernor::CountExposure()
{
    int n = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
        if(m_position.SelectByIndex(i) && m_position.Magic() == m_magic) n++;
    COrderInfo order;
    for(int j = OrdersTotal() - 1; j >= 0; j--)
        if(order.SelectByIndex(j) && order.Magic() == m_magic) n++;
    return n;
}

//--- called while frozen / on Friday: re-drives the flatten, at most every 5 seconds,
//--- and is silent once the book is flat
void CRiskGovernor::FlattenResidual()
{
    if(CountExposure() == 0) return;
    if(TimeCurrent() - m_lastFlatAttempt < 5) return;
    m_lastFlatAttempt = TimeCurrent();
    int left = CloseAllPositions();
    Print("RISK GOVERNOR: flatten retry - ", left, " position(s)/order(s) still open.");
}

//+------------------------------------------------------------------+
//| Helper: Get Total Portfolio Heat (Includes pending orders)       |
//+------------------------------------------------------------------+
double CRiskGovernor::GetTotalPortfolioHeat()
{
    double totalRisk = 0;
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    if(balance <= 0) return 0;
    
    // Sum Open Positions - only THIS EA's book (#6): a manual position or another
    // EA's trade must not count as this engine's heat (a stop-less one would add
    // the synthetic 100% and silently block every entry).
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(m_position.SelectByIndex(i))
        {
            if(m_position.Magic() != m_magic) continue;
            double sl = m_position.StopLoss();
            double openPrice = m_position.PriceOpen();
            
            // BUG FIX: If SL is 0 (No Stop Loss), the risk is INFINITE. We must not ignore it. We assign a massive synthetic risk to block new trades.
            if(sl == 0.0) 
            {
                totalRisk += 1.0; // 100% synthetic risk to block any further trading
                continue;
            }
            
            if(sl > 0)
            {
                // CRITICAL FIX: Only count risk if Stop Loss is in negative territory
                bool isRiskFree = false;
                if(m_position.PositionType() == POSITION_TYPE_BUY && sl >= openPrice) isRiskFree = true;
                if(m_position.PositionType() == POSITION_TYPE_SELL && sl > 0 && sl <= openPrice) isRiskFree = true;
                
                if(!isRiskFree)
                {
                    double tickSize = SymbolInfoDouble(m_position.Symbol(), SYMBOL_TRADE_TICK_SIZE);
                    if(tickSize > 0)
                    {
                        double pointsRisk = MathAbs(openPrice - sl) / tickSize;
                        totalRisk += ((pointsRisk * SymbolInfoDouble(m_position.Symbol(), SYMBOL_TRADE_TICK_VALUE) * m_position.Volume()) / balance);
                    }
                }
            }
        }
    }
    
    // Sum Pending Orders (so we don't overstack limits)
    COrderInfo order;
    for(int j = 0; j < OrdersTotal(); j++)
    {
        if(order.SelectByIndex(j))
        {
            if(order.Magic() != m_magic) continue;      // #6: our pending orders only
            double sl = order.StopLoss();
            if(sl > 0)
            {
                double tickSize = SymbolInfoDouble(order.Symbol(), SYMBOL_TRADE_TICK_SIZE);
                if(tickSize > 0)
                {
                    double pointsRisk = MathAbs(order.PriceOpen() - sl) / tickSize;
                    totalRisk += ((pointsRisk * SymbolInfoDouble(order.Symbol(), SYMBOL_TRADE_TICK_VALUE) * order.VolumeInitial()) / balance);
                }
            }
        }
    }
    return totalRisk;
}

//+------------------------------------------------------------------+
//| Helper: Get Net Currency Exposure                                |
//+------------------------------------------------------------------+
double CRiskGovernor::GetNetCurrencyExposure(string targetCurrency)
{
    double exposure = 0;
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    if(balance <= 0) return 0;
    
    // 1. Sum Open Positions - magic-filtered like CloseAllPositions() (#6)
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(m_position.SelectByIndex(i))
        {
            if(m_position.Magic() != m_magic) continue;
            string symbol = m_position.Symbol();
            string base = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
            string quote = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
            
            if(base == targetCurrency || quote == targetCurrency)
            {
                double sl = m_position.StopLoss();
                double price = m_position.PriceOpen();
                double volume = m_position.Volume();
                
                if(sl > 0)
                {
                    bool isRiskFree = false;
                    if(m_position.PositionType() == POSITION_TYPE_BUY && sl >= price) isRiskFree = true;
                    if(m_position.PositionType() == POSITION_TYPE_SELL && sl <= price) isRiskFree = true;
                    
                    if(!isRiskFree)
                    {
                        double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
                        double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
                        
                        if(tickSize > 0)
                        {
                            double pointsRisk = MathAbs(price - sl) / tickSize;
                            double monetaryRisk = pointsRisk * tickValue * volume;
                            exposure += (monetaryRisk / balance);
                        }
                    }
                }
            }
        }
    }
    
    // 2. Sum Pending Orders (CRITICAL: Limits lock up currency exposure too!)
    COrderInfo order;
    for(int j = 0; j < OrdersTotal(); j++)
    {
        if(order.SelectByIndex(j))
        {
            if(order.Magic() != m_magic) continue;      // #6: our pending orders only
            string symbol = order.Symbol();
            string base = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
            string quote = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
            
            if(base == targetCurrency || quote == targetCurrency)
            {
                double sl = order.StopLoss();
                double price = order.PriceOpen();
                double volume = order.VolumeInitial();
                
                if(sl > 0)
                {
                    // #4: judge the ORDER's own type - the delivered code read
                    // m_position, so a pending limit inherited the type of whatever
                    // position the previous loop had selected (or of nothing at all).
                    long otype = (long)order.OrderType();
                    bool orderIsBuy = (otype == ORDER_TYPE_BUY || otype == ORDER_TYPE_BUY_LIMIT ||
                                       otype == ORDER_TYPE_BUY_STOP || otype == ORDER_TYPE_BUY_STOP_LIMIT);
                    bool isRiskFree = false;
                    if(orderIsBuy && sl >= price)  isRiskFree = true;
                    if(!orderIsBuy && sl <= price) isRiskFree = true;
                    
                    if(!isRiskFree)
                    {
                        double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
                        double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
                        
                        if(tickSize > 0)
                        {
                            double pointsRisk = MathAbs(price - sl) / tickSize;
                            double monetaryRisk = pointsRisk * tickValue * volume;
                            exposure += (monetaryRisk / balance);
                        }
                    }
                }
            }
        }
    }
    
    return exposure;
}
//+------------------------------------------------------------------+
 









