//+------------------------------------------------------------------+
//|                                              Master_Triad_V1.mq5 |
//|                                  Copyright 2026, Master Strategy |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
//--- Master Includes
#include "..\Include\RiskGovernor.mqh"
#include "..\Include\ExecutionManager.mqh"
#include "..\Include\NewsManager.mqh"
#include "..\Include\E1_SMC_Core.mqh"

//--- Inputs
input string InpSymbolsToTrade = "EURUSD,GBPUSD"; // Comma-separated symbols
input double InpBaseRiskPct = 0.005; // 0.5% Base Risk (Track A Eval / Track B Funded)
input bool   InpUseDxySmtGate = true; // Use Native DXY SMT Divergence Gate
input bool   InpEnableLiveNews = true; // V4 Upgrade: Download Live News from ForexFactory
input ulong InpMagicNumber = 777112; // EA Magic Number
input int    InpBrokerOffset = 7; // Fallback NY->server shift (hours) if the terminal clocks are unusable

//--- V4 Upgrade: Institutional Lifecycle Gates
enum ENUM_LIFECYCLE_LOCK
{
    LIFECYCLE_ACTIVE = 0,
    LIFECYCLE_PAYOUT_REQUEST = 1,
    LIFECYCLE_PHASE_TRANSITION = 2
};
input bool                InpStatisticalGatePassed       = false; // MUST BE TRUE TO TRADE
input bool                InpForwardDemoGatePassed       = false; // MUST BE TRUE TO TRADE
input ENUM_LIFECYCLE_LOCK InpLifecycleLock               = LIFECYCLE_ACTIVE;

//--- Global Objects
CRiskGovernor     *RiskGovernor;
CNewsManager      *NewsManager;

// Arrays for multi-symbol
CExecutionManager *ExecManagers[];
CE1SMCCore        *E1Cores[];
string            TargetSymbols[];
int               TotalSymbols = 0;

//+------------------------------------------------------------------+
//| Helper to parse symbols string                                   |
//+------------------------------------------------------------------+
void ParseSymbols()
{
    ushort sep = StringGetCharacter(",", 0);
    StringSplit(InpSymbolsToTrade, sep, TargetSymbols);
    TotalSymbols = ArraySize(TargetSymbols);
    
    // Trim whitespace
    for(int i = 0; i < TotalSymbols; i++)
    {
        StringTrimLeft(TargetSymbols[i]);
        StringTrimRight(TargetSymbols[i]);
    }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("=====================================================");
    Print(" INITIALIZING MASTER TRIAD V1 (MULTI-SYMBOL) ");
    Print("=====================================================");
    
    if(!InpStatisticalGatePassed || !InpForwardDemoGatePassed)
    {
        Print("FATAL ERROR: Statistical or Forward Demo Validation Gates not passed!");
        return(INIT_PARAMETERS_INCORRECT);
    }
    
    if(InpLifecycleLock != LIFECYCLE_ACTIVE)
    {
        Print("LIFECYCLE LOCK ACTIVE: EA is currently locked. Trading disabled.");
        return(INIT_PARAMETERS_INCORRECT);
    }
    
    ParseSymbols();
    Print("Parsed ", TotalSymbols, " symbols to scan.");
    
    RiskGovernor = new CRiskGovernor(InpMagicNumber);
    NewsManager = new CNewsManager(InpEnableLiveNews, 30, 15, InpBrokerOffset);
    bool newsLoaded = false;
    if(InpEnableLiveNews) newsLoaded = NewsManager.DownloadAndParse(); 
    else newsLoaded = NewsManager.LoadFromCSV();
    
    if(!newsLoaded)
    {
        Print("FATAL ERROR: Failed to load Red News data. EA cannot run safely without News Protection!");
        return(INIT_FAILED);
    }
    
    ArrayResize(ExecManagers, TotalSymbols);
    ArrayResize(E1Cores, TotalSymbols);
    
    for(int i = 0; i < TotalSymbols; i++)
    {
        // CRITICAL FIX: Ensure symbol is active in Market Watch before creating engines
        SymbolSelect(TargetSymbols[i], true);
        
        ExecManagers[i] = new CExecutionManager(TargetSymbols[i], InpMagicNumber); 
        E1Cores[i] = new CE1SMCCore(ExecManagers[i], NewsManager, TargetSymbols[i], InpMagicNumber,
                                     InpUseDxySmtGate);
        Print("✓ Initialized engines for: ", TargetSymbols[i]);
    }
    
    // Use 1-second timer for multi-symbol scanning
    EventSetTimer(1);
    
    Print("=====================================================");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("DEINITIALIZING MASTER TRIAD V1.");
    EventKillTimer();
    
    for(int i = 0; i < TotalSymbols; i++)
    {
        delete E1Cores[i];
        delete ExecManagers[i];
    }
    
    delete NewsManager;
    delete RiskGovernor;
}

//+------------------------------------------------------------------+
//| Expert timer function (Multi-Symbol Scanner)                     |
//+------------------------------------------------------------------+
void OnTimer()
{
    // --- 1. GLOBAL RISK GOVERNOR GATE ---
    if(!RiskGovernor.IsTradingAllowed()) return;
    
    // CRITICAL PROP FIRM FIX: Friday Active Auto-Close (No Weekend Holding)
    static bool fridayClosed = false;
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    if(dt.day_of_week == 5 && dt.hour >= 21)
    {
        if(!fridayClosed)
        {
            Print("CRITICAL: Friday 21:00 reached. Executing Prop Firm Weekend Auto-Close.");
            RiskGovernor.CloseAllPositions();
            fridayClosed = true;
        }
        return; // Halt all trading until Monday
    }
    else if(dt.day_of_week != 5)
    {
        fridayClosed = false; // Reset on other days
    }
    
    double currentRisk = InpBaseRiskPct * RiskGovernor.GetEquityCurveThrottleMultiplier();
    
    // --- 2. SCAN ALL SYMBOLS ---
    for(int i = 0; i < TotalSymbols; i++)
    {
        string sym = TargetSymbols[i];
        
        bool isNewsBlocked = NewsManager.IsNewsBlockActive(sym);
        
        // Maintenance Cycle (Time stops, partials)
        ExecManagers[i].OnTickMaintenance(isNewsBlocked);
        
        // Pre-Trade Assertions
        if(!RiskGovernor.PassesPreTradeAssertions(sym, currentRisk)) continue;
        
        // Engine Signal
        E1Cores[i].OnTickEngine(sym, currentRisk);
    }
}
//+------------------------------------------------------------------+






