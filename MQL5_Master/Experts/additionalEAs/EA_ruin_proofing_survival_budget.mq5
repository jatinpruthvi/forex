//+------------------------------------------------------------------+
//|                        EA_ruin_proofing_survival_budget.mq5 |
//|                                  Copyright 2026, Master Strategy |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property strict

//--- Inputs
input string InpSymbolsToTrade = "EURUSD"; 
input ulong  InpMagicNumber = 1010; 
input double InpMaxSpreadPoints = 15; // Deterministic Gate 1
input double InpMinMarginLevelPct = 250; // Deterministic Gate 2

//+------------------------------------------------------------------+
//| RPSB: Delivery Gates (Deterministic Pre-execution Checks)        |
//+------------------------------------------------------------------+
bool CheckDeliveryGates()
{
    // Gate 1: Spread Verification (No AI inference, pure math)
    double currentSpread = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
    if(currentSpread > InpMaxSpreadPoints)
    {
        PrintFormat("RPSB GATE FAILED: Spread (%.0f) exceeds safety cap (%.0f).", currentSpread, InpMaxSpreadPoints);
        return false;
    }
    
    // Gate 2: Margin Level Verification
    double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
    if(marginLevel > 0 && marginLevel < InpMinMarginLevelPct)
    {
        PrintFormat("RPSB GATE FAILED: Margin Level (%.2f%%) is dangerously low. Trading blocked.", marginLevel);
        return false;
    }
    
    return true; // All deterministic gates passed
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("Initializing EA: Ruin-Proofing Survival Budget (Deterministic Gates)");
    return(INIT_SUCCEEDED);
}

void OnTick()
{
    if(!CheckDeliveryGates()) return;
    
    // Execution allowed here
}
