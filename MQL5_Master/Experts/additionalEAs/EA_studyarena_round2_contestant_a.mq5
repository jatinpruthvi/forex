//+------------------------------------------------------------------+
//| EA_studyarena_round2_contestant_a.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 2A - liquidity-hunting with correlation ripple and z-score reversion
//| Source document : docs_v1/docs/coreIdea/studyarena-round2-contestant-a.md
//| Tracker entry   : #34  |  Magic: 2003
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound2A class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 2A - liquidity-hunting with correlation ripple and z-score reversion"
#property description "Source: docs_v1/docs/coreIdea/studyarena-round2-contestant-a.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,AUDUSD,USDJPY";      // Comma separated universe
input double          InpRiskPct          = 1.0;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 0;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 20;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 5;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2003; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input int    InpOverlapFromMin     = 13 * 60;  // London/NY overlap start (08:00 EST)
input int    InpOverlapToMin       = 16 * 60;  // London/NY overlap end (11:00 EST)
input double InpCorrelationRr      = 1.50;     // Cross-pair "fast trade" reward:risk
input double InpZScoreEntry        = 2.50;     // Mean reversion entry threshold
input double InpZScoreAsia         = 3.50;     // 80% more selective during Asia
input int    InpZScorePeriod       = 20;       // Z-score lookback bars

//+------------------------------------------------------------------+
//| Strategy: Round 2A - liquidity-hunting with correlation ripple and z-score reversion
//+------------------------------------------------------------------+
class CRound2A : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R2A_LIQUIDITY_HUNTING";
      cfg.sourceDoc             = "docs_v1/docs/coreIdea/studyarena-round2-contestant-a.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M15;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.profitTargetPct       = InpProfitTargetPct;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 2;
      cfg.minSecondsBetweenTrades = 300;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.timeStopMinutes       = 120;
      cfg.breakEvenAtR          = 1.0;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      bool inOverlap = (ctx.clockMinutes >= InpOverlapFromMin && ctx.clockMinutes < InpOverlapToMin);
      bool inAsia    = (ctx.clockMinutes < 7 * 60);

      //--- Engine 1: liquidity hunting (stop run of the previous session range)
      SSweepParams p;
      p.Reset();
      p.rangeFromMin   = 0;
      p.rangeToMin     = 7 * 60;
      p.sessionFromMin = 7 * 60;
      p.sessionToMin   = 16 * 60;
      p.sweepMinAtr    = 0.05;
      p.sweepMaxAtr    = 0.50;
      p.reclaimWindowBars = 3;
      p.wickRatio      = 0.55;
      p.bodyRatio      = 0.55;
      p.stopBufferAtr  = 0.10;
      p.minStopAtr     = 0.40;  p.maxStopAtr = 2.00;
      p.entryRetrace   = 0.00;              // the fast trade enters at market
      p.targetR        = inOverlap ? 2.0 : InpCorrelationRr;
      p.scoreBase      = inOverlap ? 70.0 : 50.0;
      if(SigSweepReclaim(ctx, p, plan))
      {
         //--- correlation ripple: outside the overlap the tighter 1:1.5 fast profile applies
         plan.reason = StringFormat("R2A-%s %s", inOverlap ? "STOPRUN" : "FASTTICK", plan.reason);
         return true;
      }
      if(inOverlap) return false;          // no z-score reversion during the overlap window

      //--- Engine 2: statistical mean reversion (z-score overextension)
      double zEntry = inAsia ? InpZScoreAsia : InpZScoreEntry;
      if(!SigZScoreFade(ctx, InpZScorePeriod, zEntry, 0.50, 1.20, plan)) return false;
      plan.reason = StringFormat("R2A-ZSCORE %s", plan.reason);
      return true;
   }
};

CRound2A g_Round2A;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round2A);
}

void OnTick()
{
   EA_Tick();
}

void OnDeinit(const int reason)
{
   EA_Deinit(reason);
}
//+------------------------------------------------------------------+
