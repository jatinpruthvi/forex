//+------------------------------------------------------------------+
//|                                           EA_apex_eigen_matrix.mq5 |
//|                                  Copyright 2026, Master Strategy |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property strict

//--- Inputs
input string InpSymbolsToTrade = "EURUSD"; 
input ulong  InpMagicNumber = 1001; 
input double InpAccountTargetPct = 8.0; // Phase 1 Target (+8.0%)
input double InpMaxDrawdownPct = 10.0;  // Max DD Limit

//--- Global Target Variables
double g_initialBalance;

//+------------------------------------------------------------------+
//| AEM: Asymmetric Barrier Sizing Function                          |
//+------------------------------------------------------------------+
double GetAEMOptimalRisk(double currentEquity)
{
    // Calculates the distance to pass (b) and distance to ruin (a)
    double profitPct = ((currentEquity - g_initialBalance) / g_initialBalance) * 100.0;
    
    // Zone 3: Target Lock (X_t >= Target - 1.0%)
    if(profitPct >= (InpAccountTargetPct - 1.0))
    {
        double remainingPct = InpAccountTargetPct - profitPct;
        if(remainingPct <= 0) return 0.0; // Target reached
        double targetLockRisk = MathMin(0.20, (remainingPct / 2.0)); // Assuming 1:2 average RR
        PrintFormat("AEM Zone 3: Target Lock engaged. Distance: %.2f%%. Risk throttled to: %.2f%%", remainingPct, targetLockRisk);
        return targetLockRisk / 100.0;
    }
    
    // Zone 2: Convex Acceleration (3.0% <= X_t < Target - 1.0%)
    if(profitPct >= 3.0)
    {
        PrintFormat("AEM Zone 2: Convex Acceleration. Distance to ruin large. Risk maximized: 1.20%%");
        return 0.012; // 1.2% Risk
    }
    
    // Zone 0: Ruin Buffer (X_t <= -2.5% drawdown)
    if(profitPct <= -2.5)
    {
        PrintFormat("AEM Zone 0: Defense/Ruin Buffer. Distance to ruin shrinking. Risk throttled to: 0.25%%");
        return 0.0025; // 0.25% Risk
    }
    
    // Zone 1: Neutral Base (-2.5% < X_t < +3.0%)
    PrintFormat("AEM Zone 1: Neutral Base. Standard Risk applied: 0.50%%");
    return 0.005; // 0.5% Risk
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("Initializing EA: Apex Eigen Matrix (Optimal Control Barrier Math)");
    g_initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
    Print("Deinitializing AEM EA.");
}

void OnTick()
{
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    // AEM Barrier Math executed every tick before any execution engine runs
    double dynamicRiskPct = GetAEMOptimalRisk(currentEquity);
    
    if(dynamicRiskPct <= 0)
    {
        // Trading halted (Target hit or ruin hit)
        return;
    }
    
    // Z-Score Kalman Filter Trigger Logic would be routed here
    // using dynamicRiskPct for the order sizing.
}
