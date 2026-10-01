//+------------------------------------------------------------------+
//|                                     EA_adaptive_capital_matrix.mq5 |
//|                                  Copyright 2026, Master Strategy |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property strict

//--- Inputs
input string InpSymbolsToTrade = "EURUSD"; 
input double InpBaseRiskPct = 0.005; 
input ulong  InpMagicNumber = 1000; 

//--- Global Variables for ACM (Adaptive Capital Matrix)
double g_weightEngineA = 0.33;
double g_weightEngineB = 0.33;
double g_weightEngineC = 0.34;
double g_kellyMult = 1.0;
datetime g_lastJSONUpdate = 0;

//+------------------------------------------------------------------+
//| Read weights from Python generated JSON file (Common/Files)      |
//+------------------------------------------------------------------+
void ReadACMWeights()
{
    string fileName = "acm_weights.json";
    int fileHandle = FileOpen(fileName, FILE_READ|FILE_TXT|FILE_COMMON);
    
    if(fileHandle != INVALID_HANDLE)
    {
        string json = "";
        while(!FileIsEnding(fileHandle))
        {
            json += FileReadString(fileHandle);
        }
        FileClose(fileHandle);
        
        // Basic String Parsing for JSON
        int idxA = StringFind(json, "\"engineA\":");
        if(idxA > 0) g_weightEngineA = StringToDouble(StringSubstr(json, idxA + 10, 4));
        
        int idxB = StringFind(json, "\"engineB\":");
        if(idxB > 0) g_weightEngineB = StringToDouble(StringSubstr(json, idxB + 10, 4));
        
        int idxC = StringFind(json, "\"engineC\":");
        if(idxC > 0) g_weightEngineC = StringToDouble(StringSubstr(json, idxC + 10, 4));
        
        int idxK = StringFind(json, "\"kelly_mult\":");
        if(idxK > 0) g_kellyMult = StringToDouble(StringSubstr(json, idxK + 13, 4));
        
        g_lastJSONUpdate = TimeCurrent();
        PrintFormat("ACM Weights Updated: A=%.2f, B=%.2f, C=%.2f, Kelly=%.2f", g_weightEngineA, g_weightEngineB, g_weightEngineC, g_kellyMult);
    }
    else
    {
        if(TimeCurrent() - g_lastJSONUpdate > 86400)
        {
            Print("ACM Warning: JSON file stale or missing! Falling back to 0.6x Equal Weights.");
            g_weightEngineA = 0.33;
            g_weightEngineB = 0.33;
            g_weightEngineC = 0.34;
            g_kellyMult = 0.60;
        }
    }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("Initializing EA: Adaptive Capital Matrix (MT5/Python Bridge)");
    ReadACMWeights();
    EventSetTimer(3600); // Check weights every hour
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
    EventKillTimer();
}

void OnTimer()
{
    ReadACMWeights();
}

void OnTick()
{
    double activeRiskA = InpBaseRiskPct * g_weightEngineA * g_kellyMult;
    double activeRiskB = InpBaseRiskPct * g_weightEngineB * g_kellyMult;
}
