//+------------------------------------------------------------------+
//| EA_studyarena_round10_claude_fable_5_high_reasoning.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 10 Fable - M1 session-open sweep scalper with a ruthless 30-minute exit
//| Source document : docs/research/study_arena/studyarena-round10-claude-fable-5-high-reasoning.md
//| Tracker entry   : #63  |  Magic: 2030
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound10Fable class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 10 Fable - M1 session-open sweep scalper with a ruthless 30-minute exit"
#property description "Source: docs/research/study_arena/studyarena-round10-claude-fable-5-high-reasoning.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD";      // Comma separated universe
input double          InpRiskPct          = 0.50;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 0;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 20;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 6;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2030; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input int    InpReclaimBars       = 3;     // Reclaim close within 3 x M1 candles
input int    InpScalpTimeStopMin  = 30;    // If not +1R in 30 minutes, close at market
input double InpSpreadStopPct     = 15.0;  // Skip if spread > 15% of stop distance
input double InpSpreadAvgMult     = 2.00;  // Skip if spread > 2x its rolling average

//+------------------------------------------------------------------+
//| Strategy: Round 10 Fable - M1 session-open sweep scalper with a ruthless 30-minute exit
//+------------------------------------------------------------------+
class CRound10Fable : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R10FABLE_SWEEP_SCALPER";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round10-claude-fable-5-high-reasoning.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M1;              // algo-only scalping timeframe
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 300;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 60.0;   // 60% off at +1R
      cfg.breakEvenAtR          = 1.00;
      cfg.trailAtR              = 2.50;  cfg.trailDistanceR = 1.00;
      cfg.timeStopMinutes       = InpScalpTimeStopMin;   // the biggest EV upgrade
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      if(!SpreadGuard(ctx)) return false;

      SSweepParams p;
      p.Reset();
      p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
      p.sessionFromMin = 7 * 60; p.sessionToMin = 12 * 60;
      p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
      p.reclaimWindowBars = InpReclaimBars;
      p.wickRatio = 0.60; p.bodyRatio = 0.60;
      p.stopBufferAtr = 0.10; p.minStopAtr = 0.50; p.maxStopAtr = 1.50;
      p.entryRetrace = 0.00; p.targetR = 2.50;
      if(!SigSweepReclaim(ctx, p, plan)) return false;
      plan.reason = "R10FABLE-M1SCALP " + plan.reason;
      return true;
   }

   //--- spread guard: < 15% of stop distance and < 2x the rolling average
   bool SpreadGuard(SEAContext &ctx)
   {
      PushSpread(ctx.spreadPoints);
      double avg = AverageSpread();
      if(avg > 0.0 && ctx.spreadPoints > InpSpreadAvgMult * avg) return false;
      //--- preliminary stop distance from the M1 ATR before the full signal check
      double stopDist = 0.60 * ctx.atr;
      if(stopDist <= 0.0) return false;
      double cost = ctx.spreadPoints * ctx.point;
      if(cost > InpSpreadStopPct / 100.0 * stopDist) return false;
      return true;
   }

   double m_spreads[120];
   int    m_spreadCount;

   void PushSpread(const double sp)
   {
      if(sp <= 0.0) return;
      if(m_spreadCount < 120) { m_spreads[m_spreadCount++] = sp; return; }
      for(int i = 0; i < 119; i++) m_spreads[i] = m_spreads[i + 1];
      m_spreads[119] = sp;
   }

   double AverageSpread()
   {
      if(m_spreadCount < 30) return 0.0;
      double sum = 0.0;
      for(int i = 0; i < m_spreadCount; i++) sum += m_spreads[i];
      return sum / m_spreadCount;
   }
};

CRound10Fable g_Round10Fable;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round10Fable);
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
