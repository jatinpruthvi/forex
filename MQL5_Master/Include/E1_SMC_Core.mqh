//+------------------------------------------------------------------+
//|                                                  E1_SMC_Core.mqh |
//|                                  Copyright 2026, Master Strategy |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property version   "1.00"
#property strict

#include "ExecutionManager.mqh"

class CE1SMCCore
{
private:
    string            m_symbol;
    CExecutionManager *m_execManager;
    CNewsManager      *m_newsManager;
    ulong             m_magic;
    int               m_tickCount;

    int               m_hFast;
    int               m_hSlow;
    int               m_hEmaH1;
    int               m_hAtr_D1;
    int               m_hAtr_M15;
    int               m_hDxySmt;
    int               m_hRsi_DXY;

    datetime          m_setupSweepTime;
    datetime          m_lastTradedSweepTime;
    datetime          m_lastAttemptTime;
    double            m_setupFrontPrice;
    double            m_setupEqPrice;
    double            m_setupSL;
    double            m_setupTP;

public:
                   CE1SMCCore(CExecutionManager *execManager, CNewsManager *newsManager, string symbol, ulong magic = 777112);
                  ~CE1SMCCore();
                  
    // Core Engine Tick
    void           OnTickEngine(string symbol, double lotSize);

    int            GetTrendBias(string symbol);
    bool           DetectLiquiditySweep(string symbol, int bias);
    bool           DetectM15CHoCH(string symbol, int bias);
    int            GradeSetup(string symbol, int bias);
    bool           HasActiveSetup(string symbol);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CE1SMCCore::CE1SMCCore(CExecutionManager *execManager, CNewsManager *newsManager, string symbol, ulong magic)
{
    m_symbol = symbol;
    m_execManager = execManager;
    m_newsManager = newsManager;
    m_magic = magic;
    m_tickCount = 0;
    m_lastAttemptTime = 0;
    
    if(GlobalVariableCheck("MasterTriad_SweepTime_"+symbol))
        m_lastTradedSweepTime = (datetime)GlobalVariableGet("MasterTriad_SweepTime_"+symbol);
    else
        m_lastTradedSweepTime = 0;
    
    // Pre-initialize indicator handles to prevent memory/performance issues
    m_hFast = iMA(symbol, PERIOD_H4, 20, 0, MODE_EMA, PRICE_CLOSE);
    m_hSlow = iMA(symbol, PERIOD_H4, 50, 0, MODE_EMA, PRICE_CLOSE);
    m_hEmaH1 = iMA(symbol, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE);
    m_hAtr_M15 = iATR(symbol, PERIOD_M15, 14);
    m_hAtr_D1 = iATR(symbol, PERIOD_D1, 14);
    m_hRsi_DXY = iRSI("US Dollar Index", PERIOD_M15, 14, PRICE_CLOSE);
    if(m_hRsi_DXY == INVALID_HANDLE) m_hRsi_DXY = iRSI("DXY", PERIOD_M15, 14, PRICE_CLOSE); // Fallback
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CE1SMCCore::~CE1SMCCore()
{
    IndicatorRelease(m_hFast);
    IndicatorRelease(m_hSlow);
    IndicatorRelease(m_hEmaH1);
    IndicatorRelease(m_hAtr_M15);
    IndicatorRelease(m_hAtr_D1);
    if(m_hRsi_DXY != INVALID_HANDLE) IndicatorRelease(m_hRsi_DXY);
}

//+------------------------------------------------------------------+
//| Core Engine Tick                                                 |
//+------------------------------------------------------------------+
void CE1SMCCore::OnTickEngine(string symbol, double lotSize)
{
    // 1. News Block Check (V4 Upgrade)
    if(m_newsManager.IsNewsBlockActive(symbol)) return;
    
    // CRITICAL PROP FIRM FIX: Session Times
    // Only trade during high liquidity (London/NY overlap). Example: 08:00 to 18:00 Broker Time.
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    if(dt.hour < 8 || dt.hour > 18) return; 
    
    // CRITICAL PROP FIRM FIX: Friday Auto-Close Block
    // Do not open new trades on Friday after 16:00 to prevent weekend gap breaches.
    if(dt.day_of_week == 5 && dt.hour >= 16) return;
    
    // 2. Trend Bias (V4 Upgrade: H4 Cross + H1 EMA Filter)
    int bias = GetTrendBias(symbol); // 1 = Bullish, -1 = Bearish, 0 = Neutral
    if(bias == 0) return;
    
    // 3. Liquidity Sweep
    if(!DetectLiquiditySweep(symbol, bias)) return;
    
    // 3.5 V4 UPGRADE: SMT Divergence (Smart Money Tool)
    // If trading EURUSD or GBPUSD, DXY must confirm the structural shift.
    // E.g., if EURUSD sweeps a Low (Bullish setup), DXY must FAIL to sweep its High (Divergence).
    bool useDxySmtGate = (bool)GlobalVariableGet("MasterTriad_UseDxySmt");
    if(useDxySmtGate && (symbol == "EURUSD" || symbol == "GBPUSD"))
    {
        // Simple SMT proxy: DXY and EURUSD should be inversely correlated.
        // If EURUSD is making a bullish SMC reversal, DXY RSI should be overbought/exhausted.
        double rsiDxy[];
        if(m_hRsi_DXY != INVALID_HANDLE && CopyBuffer(m_hRsi_DXY, 0, 1, 1, rsiDxy) > 0)
        {
            if(bias == 1 && rsiDxy[0] < 60) 
            {
                return; // DXY is not exhausted at the high, SMT divergence fails.
            }
            if(bias == -1 && rsiDxy[0] > 40) 
            {
                return; // DXY is not exhausted at the low, SMT divergence fails.
            }
        }
    }
    
    // 3.75 V4 UPGRADE: Daily ATR Exhaustion Filter
    // Do not buy if the market has already moved >80% of its Daily ATR (Exhausted).
    double dailyAtr[];
    if(CopyBuffer(m_hAtr_D1, 0, 1, 1, dailyAtr) > 0)
    {
        double currentHigh = iHigh(symbol, PERIOD_D1, 0);
        double currentLow = iLow(symbol, PERIOD_D1, 0);
        double currentRange = currentHigh - currentLow;
        
        if(dailyAtr[0] > 0 && (currentRange / dailyAtr[0]) > 0.80) // 80% Exhaustion
        {
            return; // Market is exhausted for the day, skip further trades
        }
    }
    
    // 4. M15 CHoCH (Change of Character)
    if(!DetectM15CHoCH(symbol, bias)) return;
    
    // CRITICAL FIX: Check if we already have an open position or pending limit order for this symbol.
    // Without this, the EA will "machine-gun" limit orders on every single tick while the setup remains valid.
    if(HasActiveSetup(symbol)) return;
    
    // CRITICAL FIX: Add a cooldown timer to prevent infinite terminal spam if execution is rejected by broker!
    datetime currentCandleTime = (datetime)SeriesInfoInteger(symbol, PERIOD_CURRENT, SERIES_LASTBAR_DATE);
    if(m_lastAttemptTime == currentCandleTime) return; // We already tried (and failed or succeeded) on this candle
    
    // 5. Grade the Setup
    int grade = GradeSetup(symbol, bias);
    if(grade < 5) // Skip if grade is < 5 (C-grade or Skip)
    {
        Print("E1 ENGINE: Setup found but graded ", grade, ". Skipping (Grade Filter).");
        return;
    }
    
    Print("E1 ENGINE: High-Probability Setup Confirmed. Grade: ", grade);
    
    // 6. Calculate Pricing (Using actual SMC Order Block edges)
    // BUG FIX: Critical Pip Calculation for XAUUSD and Indices (prevents instant stop-outs on non-Forex pairs)
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    double pip = (digits == 5 || digits == 3) ? SymbolInfoDouble(symbol, SYMBOL_POINT) * 10 : SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    string upperSymbol = symbol;
    StringToUpper(upperSymbol);
    if(StringFind(upperSymbol, "XAU") != -1 || StringFind(upperSymbol, "GOLD") != -1) pip = 0.1;
    else if(StringFind(upperSymbol, "US30") != -1 || StringFind(upperSymbol, "NAS") != -1 || StringFind(upperSymbol, "SPX") != -1 || StringFind(upperSymbol, "GER") != -1) pip = 1.0;
    
    // CRITICAL FIX: Calculate ACTUAL Lot Size from Risk Percentage!
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskMoney = accountBalance * lotSize;
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    
    // Use dynamically detected edges from DetectM15CHoCH
    double frontPrice = m_setupFrontPrice;
    double eqPrice = m_setupEqPrice;
    double sl = m_setupSL;
    double tp = m_setupTP;
    
    // CRITICAL PROP FIRM FIX: Minimum SL Protection
    // If the Order Block is only a 1-pip doji, spread noise will instantly stop us out.
    double minSlPoints = 5 * pip; // Minimum 5 pips
    if(MathAbs(frontPrice - sl) < minSlPoints)
    {
        if(bias == 1) sl = frontPrice - minSlPoints; // Push SL lower
        if(bias == -1) sl = frontPrice + minSlPoints; // Push SL higher
        
        // Recalculate TP based on the new widened SL to maintain 3R exactly
        if(bias == 1) tp = frontPrice + (MathAbs(frontPrice - sl) * 3.0);
        if(bias == -1) tp = frontPrice - (MathAbs(sl - frontPrice) * 3.0);
    }
    
    if(bias == 1) // Buy
    {
        double pointsRisk = MathAbs(frontPrice - sl) / tickSize;
        double actualLotSize = (pointsRisk > 0 && tickValue > 0) ? (riskMoney / (pointsRisk * tickValue)) : 0;
        m_lastAttemptTime = currentCandleTime; // Mark attempt
        m_lastTradedSweepTime = m_setupSweepTime; // Mark this specific structural sweep as traded
        GlobalVariableSet("MasterTriad_SweepTime_"+symbol, (double)m_lastTradedSweepTime);
        m_execManager.SendDualBracketLimit(symbol, ORDER_TYPE_BUY_LIMIT, actualLotSize, frontPrice, eqPrice, sl, tp);
    }
    else if(bias == -1) // Sell
    {
        double pointsRisk = MathAbs(frontPrice - sl) / tickSize;
        double actualLotSize = (pointsRisk > 0 && tickValue > 0) ? (riskMoney / (pointsRisk * tickValue)) : 0;
        m_lastAttemptTime = currentCandleTime; // Mark attempt
        m_lastTradedSweepTime = m_setupSweepTime; // Mark this specific structural sweep as traded
        GlobalVariableSet("MasterTriad_SweepTime_"+symbol, (double)m_lastTradedSweepTime);
        m_execManager.SendDualBracketLimit(symbol, ORDER_TYPE_SELL_LIMIT, actualLotSize, frontPrice, eqPrice, sl, tp);
    }
}

//+------------------------------------------------------------------+
//| V4 Trend Bias Filter                                             |
//+------------------------------------------------------------------+
int CE1SMCCore::GetTrendBias(string symbol)
{
    double emaFast[], emaSlow[], emaH1[];
    double closeH1[];
    int result = 0;
    
    // CRITICAL FIX: Must check index 1 (closed candle) not 0 (repainting candle)
    if(CopyBuffer(m_hFast, 0, 1, 1, emaFast) > 0 && CopyBuffer(m_hSlow, 0, 1, 1, emaSlow) > 0)
    {
        if(emaFast[0] > emaSlow[0]) result = 1;
        else if(emaFast[0] < emaSlow[0]) result = -1;
    }
    
    if(result == 0) return 0;
    
    // V4 UPGRADE: H1 EMA Bias Filter
    // Ensure the recent H1 price action agrees with the H4 macro trend
    double h1Close[];
    if(CopyBuffer(m_hEmaH1, 0, 1, 2, emaH1) >= 2 && CopyClose(symbol, PERIOD_H1, 1, 1, h1Close) >= 1)
    {
        // For Bullish: H1 Close must be ABOVE H1 50 EMA, and EMA must be sloping UP
        if(result == 1)
        {
            if(h1Close[0] < emaH1[1] || emaH1[1] < emaH1[0]) return 0; // emaH1[1] is the latest closed bar, emaH1[0] is the previous
        }
        // For Bearish: H1 Close must be BELOW H1 50 EMA, and EMA must be sloping DOWN
        else if(result == -1)
        {
            if(h1Close[0] > emaH1[1] || emaH1[1] > emaH1[0]) return 0;
        }
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Detect Liquidity Sweep                                           |
//+------------------------------------------------------------------+
bool CE1SMCCore::DetectLiquiditySweep(string symbol, int bias)
{
    return true; 
}

bool CE1SMCCore::DetectM15CHoCH(string symbol, int bias)
{
    MqlRates rates[];
    // Fetch last 60 M15 candles for deeper structural context
    if(CopyRates(symbol, PERIOD_M15, 1, 60, rates) < 60) return false;
    
    // Safety check pip sizes
    // BUG FIX: Critical Pip Calculation for XAUUSD and Indices (prevents instant stop-outs on non-Forex pairs)
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    double pip = (digits == 5 || digits == 3) ? SymbolInfoDouble(symbol, SYMBOL_POINT) * 10 : SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    string upperSymbol = symbol;
    StringToUpper(upperSymbol);
    if(StringFind(upperSymbol, "XAU") != -1 || StringFind(upperSymbol, "GOLD") != -1) pip = 0.1;
    else if(StringFind(upperSymbol, "US30") != -1 || StringFind(upperSymbol, "NAS") != -1 || StringFind(upperSymbol, "SPX") != -1 || StringFind(upperSymbol, "GER") != -1) pip = 1.0;
    
    if(bias == 1) // Bullish SMC Setup
    {
        // 1. Find the Absolute Low (Liquidity Sweep) in the entire window
        int sweepIdx = 0;
        double lowest = rates[0].low;
        for(int i = 1; i < 50; i++) // Leave last 10 candles for CHoCH and pullback
        {
            if(rates[i].low <= lowest) // <= ensures we get the most recent bottom if double bottom
            {
                lowest = rates[i].low;
                sweepIdx = i;
            }
        }
        
        // 2. Find the structural Swing High that occurred AFTER the sweep
        int swingHighIdx = -1;
        double swingHigh = 0;
        for(int i = sweepIdx + 1; i < 55; i++)
        {
            if(rates[i].high > swingHigh)
            {
                swingHigh = rates[i].high;
                swingHighIdx = i;
            }
        }
        
        if(swingHighIdx == -1) return false; // No pullback found
        
        // 3. Find the CHoCH break: First candle to close above the Swing High
        int chochIdx = -1;
        for(int i = swingHighIdx + 1; i < ArraySize(rates); i++)
        {
            if(rates[i].close > swingHigh)
            {
                chochIdx = i;
                break;
            }
        }
        
        if(chochIdx != -1)
        {
            // Ensure we haven't already traded this exact sweep!
            if(rates[sweepIdx].time <= m_lastTradedSweepTime) return false;
            
            // Order Block (Sweep candle)
            double obHigh = rates[sweepIdx].high;
            double obLow = rates[sweepIdx].low;
            
            // OB Edges
            double frontEdge = obHigh + (2 * pip);
            
            // 4. MITIGATION CHECK (CRITICAL FOR REAL MONEY)
            // If the CHoCH candle itself, or any candle AFTER it, taps the OB, it's mitigated.
            for(int i = chochIdx; i < ArraySize(rates); i++)
            {
                if(rates[i].low <= frontEdge)
                {
                    // OB is already mitigated!
                    return false;
                }
            }
            
            // Setup is Valid and Unmitigated
            m_setupFrontPrice = frontEdge;
            m_setupEqPrice = obLow + ((obHigh - obLow) / 2.0); 
            m_setupSL = obLow - (3 * pip);                    
            m_setupTP = m_setupFrontPrice + (MathAbs(m_setupFrontPrice - m_setupSL) * 3.0); 
            m_setupSweepTime = rates[sweepIdx].time;          
            return true;
        }
    }
    else if(bias == -1) // Bearish SMC Setup
    {
        // 1. Find the Absolute High (Liquidity Sweep) in the window
        int sweepIdx = 0;
        double highest = rates[0].high;
        for(int i = 1; i < 50; i++)
        {
            if(rates[i].high >= highest)
            {
                highest = rates[i].high;
                sweepIdx = i;
            }
        }
        
        // 2. Find the structural Swing Low that occurred AFTER the sweep
        int swingLowIdx = -1;
        double swingLow = 0;
        for(int i = sweepIdx + 1; i < 55; i++)
        {
            if(rates[i].low < rates[i-1].low && rates[i].low < rates[i+1].low)
            {
                swingLow = rates[i].low;
                swingLowIdx = i;
                break; // Found the immediate swing low after the sweep
            }
        }
        
        if(swingLowIdx == -1) return false;
        
        // 3. Find the CHoCH break: First candle to close below the Swing Low
        int chochIdx = -1;
        for(int i = swingLowIdx + 1; i < ArraySize(rates); i++)
        {
            if(rates[i].close < swingLow)
            {
                chochIdx = i;
                break;
            }
        }
        
        if(chochIdx != -1)
        {
            // Ensure we haven't already traded this exact sweep!
            if(rates[sweepIdx].time <= m_lastTradedSweepTime) return false;
            
            // Order Block (Sweep candle)
            double obHigh = rates[sweepIdx].high;
            double obLow = rates[sweepIdx].low;
            
            // OB Edges
            double frontEdge = obLow - (2 * pip);
            
            // 4. MITIGATION CHECK (CRITICAL FOR REAL MONEY)
            for(int i = chochIdx; i < ArraySize(rates); i++)
            {
                if(rates[i].high >= frontEdge)
                {
                    // OB is already mitigated!
                    return false;
                }
            }
            
            // Setup is Valid and Unmitigated
            m_setupFrontPrice = frontEdge;
            m_setupEqPrice = obHigh - ((obHigh - obLow) / 2.0); 
            m_setupSL = obHigh + (3 * pip);                   
            m_setupTP = m_setupFrontPrice - (MathAbs(m_setupSL - m_setupFrontPrice) * 3.0); 
            m_setupSweepTime = rates[sweepIdx].time;          
            return true;
        }
    }
    
    return false;
}

// Removed dummy NewsBlock. Using CNewsManager instead.//+------------------------------------------------------------------+
//| Setup Grading (Algorithmic Scoring)                              |
//+------------------------------------------------------------------+
int CE1SMCCore::GradeSetup(string symbol, int bias)
{
    int score = 0;
    
    // 1. Trend Alignment (Since GetTrendBias already passed, we know H4 and H1 agree)
    score += 4; 
    
    // 2. Session Liquidity Bonus
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    // London Open (08:00 - 12:00) is the highest probability for SMC Sweeps
    if(dt.hour >= 8 && dt.hour <= 12) score += 3;
    // NY Overlap (13:00 - 16:00) is secondary high probability
    else if(dt.hour >= 13 && dt.hour <= 16) score += 2;
    // Asian session (late)
    else score += 0;
    
    // 3. Volatility Check (Is the ATR healthy?)
    double atr[];
    if(CopyBuffer(m_hAtr_M15, 0, 1, 1, atr) > 0)
    {
        // BUG FIX: Critical Pip Calculation for XAUUSD and Indices
        double pip = ((int)SymbolInfoInteger(symbol, SYMBOL_DIGITS) == 5 || (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS) == 3) ? SymbolInfoDouble(symbol, SYMBOL_POINT) * 10 : SymbolInfoDouble(symbol, SYMBOL_POINT);
        string upperSymbol = symbol;
        StringToUpper(upperSymbol);
        if(StringFind(upperSymbol, "XAU") != -1 || StringFind(upperSymbol, "GOLD") != -1) pip = 0.1;
        else if(StringFind(upperSymbol, "US30") != -1 || StringFind(upperSymbol, "NAS") != -1 || StringFind(upperSymbol, "SPX") != -1 || StringFind(upperSymbol, "GER") != -1) pip = 1.0;
        // If M15 ATR is greater than 6 pips, the market is moving nicely
        if((atr[0] / pip) >= 6.0) score += 2;
        else score -= 2; // Dead market, chop risk
    }
    
    // 4. Time of Day Penalty
    // Don't trade right before the daily rollover (spread widening)
    if(dt.hour == 23 || dt.hour == 0) score -= 5;
    
    return score; 
}

//+------------------------------------------------------------------+
//| Check if Setup is already active                                 |
//+------------------------------------------------------------------+
bool CE1SMCCore::HasActiveSetup(string symbol)
{
    // Check open positions (Only count our EA's trades)
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetSymbol(i) == symbol && PositionGetInteger(POSITION_MAGIC) == m_magic) return true;
    }
    // Check pending limit orders (Only count our EA's trades)
    for(int j = 0; j < OrdersTotal(); j++)
    {
        ulong ticket = OrderGetTicket(j);
        if(ticket > 0 && OrderGetString(ORDER_SYMBOL) == symbol && OrderGetInteger(ORDER_MAGIC) == m_magic) return true;
    }
    return false;
}
//+------------------------------------------------------------------+


















