//+------------------------------------------------------------------+
//|                             EA_max_roi_out_of_box_strategy.mq5 |
//|                                  Copyright 2026, Master Strategy |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property strict

//--- Inputs
input string InpSymbolsToTrade = "EURUSD"; 
input ulong  InpMagicNumber = 1004; 
input bool   InpIsEvalAccount = true; // Turn OFF on Funded

//+------------------------------------------------------------------+
//| ROI: Exam-Only Filters (For Prop Firm Evals)                     |
//+------------------------------------------------------------------+
bool CheckExamFilters()
{
    if(!InpIsEvalAccount) return true; // Disabled for funded
    
    // Filter 1: NO XAUUSD on evals
    if(StringFind(Symbol(), "XAU") != -1 || StringFind(Symbol(), "GOLD") != -1)
    {
        Print("EXAM FILTER: XAUUSD blocked on eval account.");
        return false;
    }
    
    // Filter 2: NO Friday trades
    MqlDateTime dt;
    TimeCurrent(dt);
    if(dt.day_of_week == 5) // Friday
    {
        Print("EXAM FILTER: Friday trading blocked on eval account.");
        return false;
    }
    
    // Filter 3: Killzone Only (London 07-10, NY 13-16)
    if(!((dt.hour >= 7 && dt.hour <= 10) || (dt.hour >= 13 && dt.hour <= 16)))
    {
        // Suppressing print to avoid log spam on every tick
        return false;
    }
    
    // Filter 4: Max 2 positions
    int eaPositions = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong posTicket = PositionGetTicket(i);
        if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) eaPositions++;
    }
    if(eaPositions >= 2)
    {
        return false;
    }
    
    return true; // All exam filters passed
}

//+------------------------------------------------------------------+
//| ROI: The "8% in 20 Days" Dynamic Risk Schedule                   |
//+------------------------------------------------------------------+
double GetEvalRiskScale(double initialBalance, double currentEquity)
{
    if(!InpIsEvalAccount) return 0.005; // 0.5% base on funded
    
    double profitPct = ((currentEquity - initialBalance) / initialBalance) * 100.0;
    
    // Any day -2% drawdown: STOP for the day (Handled by daily governor, assuming here)
    
    // If +6% by day 15: drop to 0.25% risk. Protect the pass.
    if(profitPct >= 6.0)
    {
        Print("EXAM SCHEDULE: +6% Target 1 hit. Throttling risk to 0.25% to protect the pass.");
        return 0.0025;
    }
    
    // Days 11-20 (assuming >+4% achieved): drop to 0.4% risk
    if(profitPct >= 4.0)
    {
        Print("EXAM SCHEDULE: +4% Buffer hit. Throttling risk to 0.40%.");
        return 0.0040;
    }
    
    // Default Days 1-10: 0.5% risk
    return 0.0050;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
double g_startBalance;

int OnInit()
{
    Print("Initializing EA: Max ROI Out of Box (Exam Mode)");
    g_startBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    return(INIT_SUCCEEDED);
}

void OnTick()
{
    if(!CheckExamFilters()) return;
    
    double dynamicRisk = GetEvalRiskScale(g_startBalance, AccountInfoDouble(ACCOUNT_EQUITY));
    
    // Execute Entry logic here using dynamicRisk
}
