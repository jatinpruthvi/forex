//+------------------------------------------------------------------+
//|                             EA_recommendations_and_next_steps.mq5 |
//|                                  Copyright 2026, Master Strategy |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property strict

//--- Inputs
input string InpSymbolsToTrade = "EURUSD"; 
input ulong  InpMagicNumber = 1008; 
input bool   InpIsPersonalAccount = false; // Evalu/Funded = false, Personal = true
input double InpMaxHeat = 4.0; // Max portfolio heat 4%

//+------------------------------------------------------------------+
//| RNS: Grade-Tier Sizing & Heat Redistribution                     |
//+------------------------------------------------------------------+
double CalculateRedistributedRisk(int tradeGrade, double correlationPenalty)
{
    double baseRisk = 0.005; // 0.5% default
    
    // 1. Grade-Tier Sizing (Only on Personal Accounts)
    if(InpIsPersonalAccount)
    {
        switch(tradeGrade)
        {
            case 1: baseRisk = 0.0125; break; // A+ Grade: 1.25% risk ratchet
            case 2: baseRisk = 0.0075; break; // B Grade: 0.75% risk
            case 3: baseRisk = 0.0025; break; // C Grade: 0.25% risk
        }
        PrintFormat("RNS SIZING: Personal Account detected. Grade %d size selected: %.2f%%", tradeGrade, baseRisk * 100.0);
    }
    else
    {
        // Eval/Funded keep grade-as-filter (C-grades rejected entirely)
        if(tradeGrade > 2) 
        {
            Print("RNS SIZING: Eval/Funded Account. Grade C or lower rejected.");
            return 0.0;
        }
        Print("RNS SIZING: Eval/Funded Account. Standard flat risk applied.");
    }
    
    // 2. Heat Redistribution r_i = H / sqrt(1 + p)
    // p (rho) is correlation penalty. If totally uncorrelated (p=0), full heat headroom given.
    double heatHeadroom = InpMaxHeat / MathSqrt(1 + correlationPenalty);
    
    // Bound risk to the remaining heat headroom
    double finalRisk = MathMin(baseRisk, (heatHeadroom / 100.0));
    return finalRisk;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("Initializing EA: Recommendations & Next Steps (Heat Redistribution)");
    return(INIT_SUCCEEDED);
}

void OnTick()
{
    int currentSignalGrade = 1; // Example: Grade A setup
    double currentCorrelation = 0.2; // Example: slightly correlated to open positions
    
    double riskToApply = CalculateRedistributedRisk(currentSignalGrade, currentCorrelation);
    
    if(riskToApply > 0)
    {
        // Execute trade with riskToApply
    }
}
