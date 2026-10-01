//+------------------------------------------------------------------+
//|                                   EA_preflight_risk_review.mq5 |
//|                                  Copyright 2026, Master Strategy |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property strict

//--- Inputs
input string InpSymbolsToTrade = "EURUSD"; 
input ulong  InpMagicNumber = 1007; 
input double InpMaxDayGainPct = 4.0; // P1: Prevent Consistency Rule Breach
input int    InpStaleQuoteMaxSeconds = 60; // P8: Stale Price Guard
input int    InpBrokerGmtOffset = 2; // P2: Explicit Timebase for Killzones

//--- Execution Globals
double g_startOfDayBalance;
bool   g_dailyHaltActive = false;

//+------------------------------------------------------------------+
//| PRR: Stale Price Guard (P8)                                      |
//+------------------------------------------------------------------+
bool IsQuoteFresh()
{
    datetime tickTime = (datetime)SymbolInfoInteger(Symbol(), SYMBOL_TIME);
    datetime localTime = TimeCurrent(); // Broker Server Time
    
    if(localTime - tickTime > InpStaleQuoteMaxSeconds)
    {
        Print("PRR ALERT: Stale Price detected! Tick is older than ", InpStaleQuoteMaxSeconds, " seconds. Trading blocked.");
        return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| PRR: Consistency Rule / Max Day Gain Guard (P1)                  |
//+------------------------------------------------------------------+
bool CheckConsistencyGuard(double currentEquity)
{
    if(g_dailyHaltActive) return false;
    
    double gainPct = ((currentEquity - g_startOfDayBalance) / g_startOfDayBalance) * 100.0;
    
    if(gainPct >= InpMaxDayGainPct)
    {
        PrintFormat("PRR ALERT: Max Day Gain (%.2f%%) reached! Trading halted to preserve Prop Firm Consistency Rules.", gainPct);
        g_dailyHaltActive = true;
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("Initializing EA: Preflight Risk Review (PRR Safety Wrappers)");
    g_startOfDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    return(INIT_SUCCEEDED);
}

void OnTick()
{
    // Safety Gates must pass before any execution logic runs
    if(!IsQuoteFresh()) return;
    
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(!CheckConsistencyGuard(currentEquity)) return;
    
    // Core Engine Execution routed here
}
