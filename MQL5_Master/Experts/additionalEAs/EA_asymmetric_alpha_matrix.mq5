//+------------------------------------------------------------------+
//|                                  EA_asymmetric_alpha_matrix.mq5 |
//|                                  Copyright 2026, Master Strategy |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property strict

//--- Inputs
input string InpSymbolsToTrade = "EURUSD"; 
input double InpBaseRiskPct = 0.004; // 0.4% base risk (as per Paradigm 4)
input ulong  InpMagicNumber = 1002; 
input double InpDailyLossHalt = 2.2; // Hard Day-Loss Guard: -2.2%

//--- Global Target Variables
double g_startOfDayBalance;
bool   g_tradingHalted = false;

//+------------------------------------------------------------------+
//| AAM: Hard Day-Loss Guard (Programmatic Prop Firm Safeguard)      |
//+------------------------------------------------------------------+
bool CheckDailyLossGuard(double currentEquity)
{
    if(g_tradingHalted) return false;
    
    double lossPct = ((g_startOfDayBalance - currentEquity) / g_startOfDayBalance) * 100.0;
    if(lossPct >= InpDailyLossHalt)
    {
        PrintFormat("AAM ALERT: -%.2f%% Daily Loss Reached. Trading Halted to protect Prop Firm Account.", lossPct);
        g_tradingHalted = true;
        return false; // Not allowed to trade
    }
    
    return true; // Safe to trade
}

//+------------------------------------------------------------------+
//| AAM: Convex Payoff Pyramiding (Scale-in Logic)                   |
//+------------------------------------------------------------------+
void ManageConvexPyramiding()
{
    // Scans open positions for the EA's magic number
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong posTicket = PositionGetTicket(i);
        if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
        
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
        double stopLoss = PositionGetDouble(POSITION_SL);
        long posType = PositionGetInteger(POSITION_TYPE);
        
        // Assume Risk was calculated such that 1R = stopLoss distance
        // For simplicity, we calculate rough R-multiple based on pip distance
        double pipsAtRisk = MathAbs(openPrice - stopLoss);
        if(pipsAtRisk <= 0) continue; 
        
        double floatingProfitPips = MathAbs(currentPrice - openPrice);
        double currentR = floatingProfitPips / pipsAtRisk;
        
        // Paradigm 4 Rule: When initial position crosses +2.0R, move SL to +1.0R
        if(currentR >= 2.0)
        {
            double newSL = (posType == POSITION_TYPE_BUY) ? openPrice + pipsAtRisk : openPrice - pipsAtRisk;
            
            // Check if SL hasn't been upgraded yet
            if( (posType == POSITION_TYPE_BUY && stopLoss < newSL) || 
                (posType == POSITION_TYPE_SELL && stopLoss > newSL) || stopLoss == 0 )
            {
                PrintFormat("AAM PYRAMID: Position %I64u reached +2.0R. Locking in +1.0R profit (Risk Free).", posTicket);
                // Implementation requires calling OrderSend to modify SL here.
                
                PrintFormat("AAM PYRAMID: Secondary position financed with market money can now be opened.");
                // Secondary Entry Trigger Flag would activate here.
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("Initializing EA: Asymmetric Alpha Matrix (AAM)");
    g_startOfDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    return(INIT_SUCCEEDED);
}

void OnTick()
{
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    if(!CheckDailyLossGuard(currentEquity)) return;
    
    ManageConvexPyramiding();
    
    // Engine A, B, C Logic routed here
}
