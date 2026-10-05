//+------------------------------------------------------------------+
//|                                             ExecutionManager.mqh |
//|                                  Copyright 2026, Master Strategy |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property version   "1.00"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

class CExecutionManager
{
private:
    string            m_symbol;
    CTrade            m_trade;
    CPositionInfo     m_position;
    COrderInfo        m_order;
    ulong             m_magic;
    int               m_hATR;

public:
                   CExecutionManager(string symbol, ulong magic = 777112);
                  ~CExecutionManager();
                  
    // Dual-Bracket Entry
    bool           SendDualBracketLimit(string symbol, ENUM_ORDER_TYPE orderType, double totalLotSize, 
                                        double frontPrice, double eqPrice, double stopLoss, double finalTP);
                                        
    // Maintenance loop (called every tick/candle)
    void           OnTickMaintenance(bool isNewsBlocked = false);

    void           ManageDualBracketCancellation();
    void           ManageStagedExits();
    void           ManageDeadMoneyExit();
    double         GetDailyATR(string symbol);
    double         GetDailyRange(string symbol);
    void           CleanupGlobalVariables();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CExecutionManager::CExecutionManager(string symbol, ulong magic)
{
    m_magic = magic;
    m_symbol = symbol;
    m_trade.SetExpertMagicNumber(m_magic);
    m_trade.SetMarginMode();
    m_trade.SetTypeFillingBySymbol(symbol);
    
    m_hATR = iATR(symbol, PERIOD_D1, 14);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CExecutionManager::~CExecutionManager()
{
    IndicatorRelease(m_hATR);
}

//+------------------------------------------------------------------+
//| Send Dual-Bracket Limit Orders                                   |
//+------------------------------------------------------------------+
bool CExecutionManager::SendDualBracketLimit(string symbol, ENUM_ORDER_TYPE orderType, double totalLotSize, 
                                             double frontPrice, double eqPrice, double stopLoss, double finalTP)
{
    // CRITICAL FIX: 50/50 Risk Split. Must round DOWN to step to prevent leverage breaches, then Normalize to prevent floating point trailing decimals
    double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    if(step <= 0) 
    {
        Print("EXECUTION ERROR: Broker returned invalid Volume Step (0). Aborting execution.");
        return false;
    }
    // + 1e-9: some exact multiples divide to just under the integer in IEEE doubles (0.29 / 0.01
    // is 28.999999999999996), and a bare floor() then drops a whole step - a 0.58-lot order was
    // split 2 x 0.28 instead of 2 x 0.29.  (14 of the 399 lot sizes 0.02 .. 8.00 are affected.)
    double halfLot = MathFloor((totalLotSize / 2.0) / step + 1e-9) * step;
    
    // Safety: Find volume digits for strict normalization
    int volDigits = 2;
    if(step == 0.1) volDigits = 1;
    else if(step == 1.0) volDigits = 0;
    else if(step == 0.001) volDigits = 3;
    
    halfLot = NormalizeDouble(halfLot, volDigits);
    
    if(halfLot < SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN))
    {
        Print("EXECUTION ERROR: 50% lot size is below broker minimum.");
        return false;
    }
    
    // Safety: Maximum Lot Cap
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    if(halfLot > maxLot)
    {
        Print("EXECUTION WARNING: Calculated lot size exceeds broker maximum. Capping to Max Lot.");
        halfLot = maxLot;
    }
    
    // 2. Dynamic TP (MQL5 Backport): Shrink if Daily ATR is >75% exhausted
    double atr = GetDailyATR(symbol);
    double dailyRange = GetDailyRange(symbol);
    double adjustedTP = finalTP;
    
    if(atr > 0 && (dailyRange / atr) > 0.75)
    {
        Print("EXECUTION ALERT: Daily ATR > 75% exhausted. Shrinking TP to lock safety.");
        adjustedTP = frontPrice + ((finalTP - frontPrice) * 0.5); 
    }
    
    // 3. Spread and Stop Level Check (CRITICAL)
    double currentAsk = SymbolInfoDouble(symbol, SYMBOL_ASK);
    double currentBid = SymbolInfoDouble(symbol, SYMBOL_BID);
    double stopLevel = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    // Spread protection: Do not place limits during massive news spikes where spread > 3 pips
    // BUG FIX: Critical Pip Calculation for XAUUSD and Indices
    double pip = ((int)SymbolInfoInteger(symbol, SYMBOL_DIGITS) == 5 || (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS) == 3) ? SymbolInfoDouble(symbol, SYMBOL_POINT) * 10 : SymbolInfoDouble(symbol, SYMBOL_POINT);
    string upperSymbol = symbol;
    StringToUpper(upperSymbol);
    if(StringFind(upperSymbol, "XAU") != -1 || StringFind(upperSymbol, "GOLD") != -1) pip = 0.1;
    else if(StringFind(upperSymbol, "US30") != -1 || StringFind(upperSymbol, "NAS") != -1 || StringFind(upperSymbol, "SPX") != -1 || StringFind(upperSymbol, "GER") != -1) pip = 1.0;
    if((currentAsk - currentBid) > (3.0 * pip))
    {
        Print("EXECUTION ERROR: Spread is currently above 3.0 pips. Aborting to protect capital.");
        return false;
    }
    
    if(orderType == ORDER_TYPE_BUY_LIMIT && (currentAsk - frontPrice) < stopLevel)
    {
        Print("EXECUTION ERROR: Front price too close to market. StopLevel violation.");
        return false;
    }
    if(orderType == ORDER_TYPE_SELL_LIMIT && (frontPrice - currentBid) < stopLevel)
    {
        Print("EXECUTION ERROR: Front price too close to market. StopLevel violation.");
        return false;
    }
    
    // CRITICAL FIX: Normalize all prices to the broker's digit structure. 
    // Un-normalized floats (e.g. 1.054329999) cause TRADE_RETCODE_INVALID_PRICE errors.
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    frontPrice = NormalizeDouble(frontPrice, digits);
    eqPrice    = NormalizeDouble(eqPrice, digits);
    stopLoss   = NormalizeDouble(stopLoss, digits);
    adjustedTP = NormalizeDouble(adjustedTP, digits);
    
    // 4. Send the Dual-Bracket
    bool resFront = false;
    bool resEq = false;
    ulong frontTicket = 0;
    ulong eqTicket = 0;
    
    // CRITICAL FIX: Some prop firm brokers reject ORDER_TIME_SPECIFIED with INVALID_EXPIRATION.
    // We MUST use ORDER_TIME_GTC and manage the cleanup manually in OnTickMaintenance.
    
    if(orderType == ORDER_TYPE_BUY_LIMIT)
    {
        resFront = m_trade.BuyLimit(halfLot, frontPrice, symbol, stopLoss, adjustedTP, ORDER_TIME_GTC, 0, "Dual_Front");
        if(resFront) frontTicket = m_trade.ResultOrder();
        
        resEq    = m_trade.BuyLimit(halfLot, eqPrice, symbol, stopLoss, adjustedTP, ORDER_TIME_GTC, 0, "Dual_Eq");
        if(resEq) eqTicket = m_trade.ResultOrder();
    }
    else if(orderType == ORDER_TYPE_SELL_LIMIT)
    {
        resFront = m_trade.SellLimit(halfLot, frontPrice, symbol, stopLoss, adjustedTP, ORDER_TIME_GTC, 0, "Dual_Front");
        if(resFront) frontTicket = m_trade.ResultOrder();
        
        resEq    = m_trade.SellLimit(halfLot, eqPrice, symbol, stopLoss, adjustedTP, ORDER_TIME_GTC, 0, "Dual_Eq");
        if(resEq) eqTicket = m_trade.ResultOrder();
    }
    
    if(resFront && resEq) 
    {
        Print("EXECUTION: Dual-Bracket Limits placed successfully.");
    }
    else if(resFront && !resEq)
    {
        Print("EXECUTION ERROR: Equilibrium limit failed. Canceling Front-edge orphan (Ticket: ", frontTicket, "). Return code: ", m_trade.ResultRetcode());
        m_trade.OrderDelete(frontTicket);
    }
    else if(!resFront && resEq)
    {
        Print("EXECUTION ERROR: Front-edge limit failed. Canceling Equilibrium orphan (Ticket: ", eqTicket, "). Return code: ", m_trade.ResultRetcode());
        m_trade.OrderDelete(eqTicket);
    }
    else 
    {
        Print("EXECUTION ERROR: Failed to place dual-bracket limits. Return code: ", m_trade.ResultRetcode());
    }
        
    return (resFront && resEq);
}

//+------------------------------------------------------------------+
//| OnTick Maintenance                                               |
//+------------------------------------------------------------------+
void CExecutionManager::OnTickMaintenance(bool isNewsBlocked)     // default lives on the declaration only
{
    ManageDualBracketCancellation();
    ManageStagedExits();
    ManageDeadMoneyExit();
    CleanupGlobalVariables();
    
    // CRITICAL PROP FIRM FIX: Active News Block Limit Order Cancellation
    if(isNewsBlocked)
    {
        for(int j = OrdersTotal() - 1; j >= 0; j--)
        {
            if(m_order.SelectByIndex(j))
            {
                if(m_order.Magic() == m_magic && m_order.Symbol() == m_symbol)
                {
                    Print("EXECUTION WARNING: News Block is now ACTIVE. Canceling exposed pending limit order #", m_order.Ticket(), " to protect capital.");
                    for(int r=0;r<3;r++) { if(m_trade.OrderDelete(m_order.Ticket())) break; Sleep(50); }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Manage Dual Bracket Cancellation (Cancel Eq if Front hits 1.0R)  |
//+------------------------------------------------------------------+
void CExecutionManager::ManageDualBracketCancellation()
{
    // Iterate open positions. If we have a front-edge position at +1.0R profit,
    // cancel the pending equilibrium limit order to avoid late double exposure.
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(m_position.SelectByIndex(i))
        {
            // CRITICAL FIX: Ignore manual trades, trades from other EAs, and trades on OTHER symbols!
            if(m_position.Magic() != m_magic || m_position.Symbol() != m_symbol) continue;
            
            double entry = m_position.PriceOpen();
            double sl = m_position.StopLoss();
            double riskDist = MathAbs(entry - sl);
            double currentPrice = m_position.PriceCurrent();
            
            if(riskDist == 0) continue;
            
            double currentR = 0;
            if(m_position.PositionType() == POSITION_TYPE_BUY)
                currentR = (currentPrice - entry) / riskDist;
            else if(m_position.PositionType() == POSITION_TYPE_SELL)
                currentR = (entry - currentPrice) / riskDist;
                
            // If +1.0R is hit
            if(currentR >= 1.0)
            {
                // Find and cancel the sibling pending order on the same symbol
                for(int j = OrdersTotal() - 1; j >= 0; j--)
                {
                    if(m_order.SelectByIndex(j))
                    {
                        if(m_order.Symbol() == m_position.Symbol() && m_order.Magic() == m_position.Magic())
                        {
                            Print("EXECUTION: Front edge hit +1.0R. Canceling Equilibrium Limit Order #", m_order.Ticket());
                            for(int r=0;r<3;r++) { if(m_trade.OrderDelete(m_order.Ticket())) break; Sleep(50); }
                        }
                    }
                }
            }
        }
    }
    
    // CRITICAL FIX: Manual Ghost Order Cleanup (Since we can't trust broker expiration)
    // Delete any pending limit orders older than 45 minutes to prevent stale execution
    for(int j = OrdersTotal() - 1; j >= 0; j--)
    {
        if(m_order.SelectByIndex(j))
        {
            if(m_order.Magic() != m_magic || m_order.Symbol() != m_symbol) continue;
            
            datetime setupTime = (datetime)m_order.TimeSetup();
            // V4 UPGRADE: Limit Order Expiry (3 bars on M15 = 45 minutes)
            if((TimeCurrent() - setupTime) > 2700) 
            {
                Print("EXECUTION: Stale Limit Order cleanup (45m expiry). Deleting limit order #", m_order.Ticket());
                for(int r=0;r<3;r++) { if(m_trade.OrderDelete(m_order.Ticket())) break; Sleep(50); }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Manage Staged Exits (1.5R Partial + BE)                          |
//+------------------------------------------------------------------+
void CExecutionManager::ManageStagedExits()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(m_position.SelectByIndex(i))
        {
            if(m_position.Magic() != m_magic || m_position.Symbol() != m_symbol) continue;

            ulong ticket = m_position.Ticket();
            ulong identifier = m_position.Identifier(); // CRITICAL FIX: Ticket can change on partial close, Identifier never changes.
            string gvName = "Triad_Partial_" + IntegerToString(identifier);

            // The flag means "the 25% partial is banked (or was too small to split)".  The
            // delivered code set it NO MATTER WHETHER the close or the stop move succeeded
            // and skipped the whole block once it existed, so one requote at +1.5R left the
            // trade with neither its partial nor its break-even stop, for good.  The two
            // steps are now independent and each is retried until it works.
            bool partialDone = GlobalVariableCheck(gvName);

            double entry = m_position.PriceOpen();
            double currentPrice = m_position.PriceCurrent();
            double originalSL = m_position.StopLoss();
            double tp = m_position.TakeProfit();

            double riskDist = MathAbs(entry - originalSL);
            if(riskDist == 0) continue;

            double currentR = 0;
            if(m_position.PositionType() == POSITION_TYPE_BUY)
                currentR = (currentPrice - entry) / riskDist;
            else if(m_position.PositionType() == POSITION_TYPE_SELL)
                currentR = (entry - currentPrice) / riskDist;

            // Target: +1.5R -> Close 25% and move SL to BE + 0.2R (to cover swap/commission)
            if(currentR >= 1.5)
            {
                if(!partialDone)
                {
                    double currentVolume = m_position.Volume();
                    double minLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
                    double lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);

                    // 25% rounded DOWN to the lot step.  (NormalizeDouble(v, 2) rounds to
                    // nearest: on a 0.02-lot position 0.005 became 0.01, i.e. 50% - not 25%.)
                    double partialVol = (lotStep > 0.0) ? MathFloor(currentVolume * 0.25 / lotStep + 1e-9) * lotStep : 0.0;

                    if(partialVol >= minLot && partialVol < currentVolume)
                    {
                        Print("EXECUTION: +1.5R Reached! Securing 25% partial profit on ticket #", ticket);
                        if(m_trade.PositionClosePartial(ticket, partialVol)) partialDone = true;
                        else Print("EXECUTION WARNING: partial close failed (retcode ", m_trade.ResultRetcode(), ") - will retry.");
                    }
                    else
                        partialDone = true;       // too small to split: nothing to bank, move on to the stop
                    if(partialDone) GlobalVariableSet(gvName, 1.0);
                }

                // Move Stop Loss to BE + 0.2R.  Idempotent: it never moves backwards, and once
                // applied the recomputed level is no better than the current stop.
                double newSL = 0;
                int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);

                if(m_position.PositionType() == POSITION_TYPE_BUY)
                {
                    newSL = NormalizeDouble(entry + (riskDist * 0.2), digits); // BE + 0.2R
                    if(newSL <= originalSL) newSL = originalSL; // Never move SL backwards
                }
                else if(m_position.PositionType() == POSITION_TYPE_SELL)
                {
                    newSL = NormalizeDouble(entry - (riskDist * 0.2), digits); // BE + 0.2R
                    if(newSL >= originalSL && originalSL != 0) newSL = originalSL; // Never move SL backwards
                }

                if(newSL != originalSL)
                {
                    Print("EXECUTION: Moving Stop Loss to BE + 0.2R on ticket #", ticket);
                    if(!m_trade.PositionModify(ticket, newSL, tp))
                        Print("EXECUTION WARNING: stop move failed (retcode ", m_trade.ResultRetcode(), ") - will retry.");
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Manage Dead-Money Exit                                           |
//+------------------------------------------------------------------+
void CExecutionManager::ManageDeadMoneyExit()
{
    // V4 UPGRADE: 45-Minute Time Stop
    // If trade age > 45 minutes (2700s) AND profit < +0.5R, close at market.
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(m_position.SelectByIndex(i))
        {
            // CRITICAL FIX: Ignore manual trades, trades from other EAs, and trades on OTHER symbols!
            if(m_position.Magic() != m_magic || m_position.Symbol() != m_symbol) continue;
            
            // CRITICAL FIX: Do not apply time stops to Free Runners (trades that already hit partial targets)
            ulong identifier = m_position.Identifier();
            string gvName = "Triad_Partial_" + IntegerToString(identifier);
            if(GlobalVariableCheck(gvName)) continue; 
            
            datetime openTime = (datetime)m_position.Time();
            int ageSeconds = (int)(TimeCurrent() - openTime);
            
            if(ageSeconds > 2700) // 45 minutes = 2700s
            {
                double entry = m_position.PriceOpen();
                double sl = m_position.StopLoss();
                double riskDist = MathAbs(entry - sl);
                double currentPrice = m_position.PriceCurrent();
                
                if(riskDist == 0) continue;
                
                double currentR = 0;
                if(m_position.PositionType() == POSITION_TYPE_BUY)
                    currentR = (currentPrice - entry) / riskDist;
                else if(m_position.PositionType() == POSITION_TYPE_SELL)
                    currentR = (entry - currentPrice) / riskDist;
                    
                if(currentR < 0.5)
                {
                    Print("EXECUTION WARNING: V4 Time Stop hit! Trade age > 45m and profit < +0.5R. Bailing out dead money on ticket: ", m_position.Ticket());
                    m_trade.PositionClose(m_position.Ticket());
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Helper: Daily ATR                                                |
//+------------------------------------------------------------------+
double CExecutionManager::GetDailyATR(string symbol)
{
    double atr[];
    double result = 0.0;
    // CRITICAL FIX: Use index 1 (yesterday's completed ATR) instead of index 0 (today's floating ATR)
    if(CopyBuffer(m_hATR, 0, 1, 1, atr) > 0)
        result = atr[0];
    return result;
}

//+------------------------------------------------------------------+
//| Helper: Daily Range                                              |
//+------------------------------------------------------------------+
double CExecutionManager::GetDailyRange(string symbol)
{
    double high[], low[];
    // #15: index 0 IS today's DEVELOPING range - and that is what the caller
    // wants.  SendDualBracketLimit() asks "is today's travel already past 75% of
    // a normal day?", so the deliberate vintage pair is:
    //     today's developing range  (here, index 0)
    //   vs yesterday's completed ATR (GetDailyATR(), index 1)
    // The delivered comment claimed index 1, which the code never did.
    if(CopyHigh(symbol, PERIOD_D1, 0, 1, high) > 0 && CopyLow(symbol, PERIOD_D1, 0, 1, low) > 0)
        return (high[0] - low[0]);
    return 0.0;
}

//+------------------------------------------------------------------+
//| Helper: Cleanup Stale GlobalVariables                            |
//+------------------------------------------------------------------+
void CExecutionManager::CleanupGlobalVariables()
{
    // MT5 stores global variables across reboots. When a position fully closes,
    // its partial flag (Triad_Partial_XYZ) remains. Over time this causes a memory/resource leak.
    for(int i = GlobalVariablesTotal() - 1; i >= 0; i--)
    {
        string gvName = GlobalVariableName(i);
        if(StringFind(gvName, "Triad_Partial_") == 0)
        {
            string idStr = StringSubstr(gvName, 14); // Length of "Triad_Partial_"
            ulong identifier = StringToInteger(idStr);
            if(identifier > 0)
            {
                // Verify if ANY open position has this identifier
                bool positionStillOpen = false;
                for(int p = 0; p < PositionsTotal(); p++)
                {
                    if(PositionGetSymbol(p) != "") // Selects the position
                    {
                        if(PositionGetInteger(POSITION_IDENTIFIER) == identifier)
                        {
                            positionStillOpen = true;
                            break;
                        }
                    }
                }
                
                // If the position no longer exists, delete the variable
                if(!positionStillOpen)
                {
                    GlobalVariableDel(gvName);
                }
            }
        }
    }
}







