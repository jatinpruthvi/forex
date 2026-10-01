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

class CRiskGovernor
{
private:
    double         m_initialDailyBalance;
    double         m_peakEquity;
    datetime       m_breakerResetTime;
    int            m_lastDay;
    ulong          m_magic;
    CPositionInfo  m_position;
    CTrade         m_trade;

public:
                   CRiskGovernor(ulong magic = 777112);
                  ~CRiskGovernor();
                  
    void           CloseAllPositions();
    
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
//| Constructor                                                      |
//+------------------------------------------------------------------+
CRiskGovernor::CRiskGovernor(ulong magic)
  : m_magic(magic)
{
    // CRITICAL FIX: Terminal Restart / VPS Reboot Persistence
    // If the terminal crashes, memory resets. We MUST read peak equity and breakers from disk.
    
    if(GlobalVariableCheck("MasterTriad_PeakEquity"))
        m_peakEquity = GlobalVariableGet("MasterTriad_PeakEquity");
    else 
    {
        m_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        GlobalVariableSet("MasterTriad_PeakEquity", m_peakEquity);
    }
    
    if(GlobalVariableCheck("MasterTriad_BreakerTime"))
        m_breakerResetTime = (datetime)GlobalVariableGet("MasterTriad_BreakerTime");
    else 
        m_breakerResetTime = 0;
        
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    // CRITICAL FIX: Prevent Daily Loss Limit reset if VPS reboots mid-day
    if(GlobalVariableCheck("MasterTriad_LastDay") && GlobalVariableGet("MasterTriad_LastDay") == dt.day_of_year)
    {
        m_lastDay = dt.day_of_year;
        if(GlobalVariableCheck("MasterTriad_InitialBalance"))
            m_initialDailyBalance = GlobalVariableGet("MasterTriad_InitialBalance");
        else
            m_initialDailyBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    }
    else
    {
        m_lastDay = -1;
        m_initialDailyBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    }
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
    // CRITICAL FIX: Daily Rollover MUST happen BEFORE the breaker check.
    // Otherwise a 24h freeze blocks the midnight reset from ever firing!
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    if(dt.day_of_year != m_lastDay)
    {
        m_initialDailyBalance = AccountInfoDouble(ACCOUNT_BALANCE); // Static start-of-day balance
        m_lastDay = dt.day_of_year;
        
        GlobalVariableSet("MasterTriad_LastDay", m_lastDay);
        GlobalVariableSet("MasterTriad_InitialBalance", m_initialDailyBalance);
        
        // Reset the daily freeze shield on a new day
        if(m_breakerResetTime > 0)
        {
            m_breakerResetTime = 0;
            GlobalVariableSet("MasterTriad_BreakerTime", 0);
            Print("RISK SHIELD: New trading day detected. Daily Freeze lifted.");
        }
    }

    if(TimeCurrent() < m_breakerResetTime)
    {
        Print("RISK GOVERNOR: Trading disabled until ", TimeToString(m_breakerResetTime));
        return false;
    }
    
    // CRITICAL FIX: Daily Loss must be calculated on EQUITY (Open + Closed), not just closed PnL.
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double dailyLossPct = (m_initialDailyBalance > 0) ? ((currentEquity - m_initialDailyBalance) / m_initialDailyBalance) : 0;
    
    if(dailyLossPct <= -MAX_DAILY_LOSS_PCT)
    {
        Print("RISK GOVERNOR BREAKER TRIPPED: Daily Equity Loss hits ", DoubleToString(dailyLossPct*100, 2), "%. Closing all and freezing 24h.");
        CloseAllPositions();
        m_breakerResetTime = TimeCurrent() + PeriodSeconds(PERIOD_D1);
        GlobalVariableSet("MasterTriad_BreakerTime", (double)m_breakerResetTime);
        return false;
    }
    
    // Check Peak-to-Trough Trailing DD
    if(m_peakEquity == 0 || currentEquity > m_peakEquity) 
    {
        m_peakEquity = currentEquity; 
        GlobalVariableSet("MasterTriad_PeakEquity", m_peakEquity);
    }
    
    double currentDD = (m_peakEquity > 0) ? ((m_peakEquity - currentEquity) / m_peakEquity) : 0;
    if(currentDD >= MAX_TRAILING_DD_PCT)
    {
        Print("RISK GOVERNOR BREAKER TRIPPED: Trailing DD hits ", DoubleToString(currentDD*100, 2), "%. Closing all and freezing 48h.");
        CloseAllPositions();
        m_breakerResetTime = TimeCurrent() + (2 * PeriodSeconds(PERIOD_D1));
        GlobalVariableSet("MasterTriad_BreakerTime", (double)m_breakerResetTime);
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
    datetime startOfDay = TimeCurrent() - (TimeCurrent() % PeriodSeconds(PERIOD_D1));
    HistorySelect(startOfDay, TimeCurrent());
    double pnl = 0;
    for(int i=0; i<HistoryDealsTotal(); i++)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(ticket > 0 && (HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT || HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_INOUT))
        {
            pnl += HistoryDealGetDouble(ticket, DEAL_PROFIT) + HistoryDealGetDouble(ticket, DEAL_COMMISSION) + HistoryDealGetDouble(ticket, DEAL_SWAP);
        }
    }
    return pnl;
}

//+------------------------------------------------------------------+
//| Helper: Close All Positions AND PENDING ORDERS                   |
//+------------------------------------------------------------------+
void CRiskGovernor::CloseAllPositions()
{
    // Close open positions
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(m_position.SelectByIndex(i))
        {
            if(m_position.Magic() == m_magic)
            {
                m_trade.PositionClose(m_position.Ticket());
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
                m_trade.OrderDelete(order.Ticket());
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Helper: Get Total Portfolio Heat (Includes pending orders)       |
//+------------------------------------------------------------------+
double CRiskGovernor::GetTotalPortfolioHeat()
{
    double totalRisk = 0;
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    if(balance <= 0) return 0;
    
    // Sum Open Positions
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(m_position.SelectByIndex(i))
        {
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
    
    // 1. Sum Open Positions
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(m_position.SelectByIndex(i))
        {
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
    
    return exposure;
}
//+------------------------------------------------------------------+
 









