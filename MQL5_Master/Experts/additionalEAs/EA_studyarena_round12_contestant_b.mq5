//+------------------------------------------------------------------+
//| EA_studyarena_round12_contestant_b.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 12B - three-tier DD throttle on top of the programmatic M5 sweep-reclaim
//| Source document : docs/research/study_arena/studyarena-round12-contestant-b.md
//| Tracker entry   : #76  |  Magic: 2043
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound12B class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 12B - three-tier DD throttle on top of the programmatic M5 sweep-reclaim"
#property description "Source: docs/research/study_arena/studyarena-round12-contestant-b.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,XAUUSD,USDJPY,US30,AUDNZD";      // Comma separated universe
input int             InpMaxTradesPerDay  = 6;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2043; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpTier1RiskPct      = 0.60;  // DD 0-2%
input double InpTier2RiskPct      = 0.30;  // DD 2-4%
input double InpTier3RiskPct      = 0.15;  // DD 4-6%
input double InpShutdownDdPct     = 8.00;  // Hard 8% DD cap
input double InpWickRatio         = 0.60;  // Sweep-candle wick >= 60% of the candle

//+------------------------------------------------------------------+
//| Strategy: Round 12B - three-tier DD throttle on top of the programmatic M5 sweep-reclaim
//+------------------------------------------------------------------+
class CRound12B : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R12B_THREE_TIER_DD";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round12-contestant-b.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpTier1RiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.totalDdPct            = InpShutdownDdPct;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 2;
      cfg.minSecondsBetweenTrades = 300;
      cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 20;  cfg.sessionEndMin   = 30;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;   // doc TP1: 50% at +1R
      cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 30.0;
      cfg.breakEvenAtR          = 1.00;
      cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 1.00;
      cfg.useLimitEntry         = true;
      cfg.pendingExpiryMinutes  = 15;
      cfg.timeStopMinutes       = 240;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      int fromMin, toMin, sessFrom, sessTo;
      if(!SessionMap(ctx, fromMin, toMin, sessFrom, sessTo)) return false;

      SSweepParams p;
      p.Reset();
      p.rangeFromMin = fromMin; p.rangeToMin = toMin;
      p.sessionFromMin = sessFrom; p.sessionToMin = sessTo;
      p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
      p.reclaimWindowBars = 3;
      p.wickRatio = InpWickRatio; p.bodyRatio = 0.60;
      p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
      p.entryRetrace = 0.50; p.targetR = 2.0;
      if(!SigSweepReclaim(ctx, p, plan)) return false;
      if(!BiasAgrees(ctx, plan.dir)) return false;
      plan.reason = "R12B-SWEEPRECLAIM " + plan.reason;
      return true;
   }

   bool SessionMap(SEAContext &ctx, int &fromMin, int &toMin, int &sessFrom, int &sessTo)
   {
      if(ctx.clockMinutes < 6 * 60 + 30 && StringFind(ctx.symbol, "AUDNZD") >= 0)
      { fromMin = 21 * 60; toMin = 24 * 60; sessFrom = 0; sessTo = 6 * 60 + 30; return true; }
      if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 16 * 60 + 30 &&
         (StringFind(ctx.symbol, "EURUSD") >= 0 || StringFind(ctx.symbol, "GBPUSD") >= 0 ||
          StringFind(ctx.symbol, "XAU") >= 0))
      { fromMin = 0; toMin = 7 * 60; sessFrom = 7 * 60; sessTo = 16 * 60 + 30; return true; }
      if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 20 * 60 + 30 &&
         (StringFind(ctx.symbol, "USDJPY") >= 0 || StringFind(ctx.symbol, "US30") >= 0))
      { fromMin = 7 * 60; toMin = 13 * 60; sessFrom = 13 * 60 + 30; sessTo = 20 * 60 + 30; return true; }
      return false;
   }

   bool BiasAgrees(SEAContext &ctx, const int dir)
   {
      if(StringFind(ctx.symbol, "AUDNZD") >= 0) return true;   // Asian mean reversion
      if(ctx.emaH1_50 <= 0.0) return false;
      return (dir > 0) ? (ctx.mid > ctx.emaH1_50) : (ctx.mid < ctx.emaH1_50);
   }

   //--- three-tier DD throttle with an 8% hard cap
   double LotsMultiplier(SEAContext &ctx)
   {
      if(ctx.riskPct <= 0.0) return 0.0;
      double dd = DrawdownPct();
      if(dd >= InpShutdownDdPct) return 0.0;
      double risk = InpTier1RiskPct;
      if(dd >= 4.0)      risk = InpTier3RiskPct;
      else if(dd >= 2.0) risk = InpTier2RiskPct;
      return MathMax(0.0, risk / ctx.riskPct);
   }

   double DrawdownPct()
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double hwm = GlobalVariableGet(EA_HwmKey("R12B", true));
      if(hwm <= 0.0 || equity > hwm) { GlobalVariableSet(EA_HwmKey("R12B", true), MathMax(equity, hwm)); return 0.0; }
      if(hwm <= 0.0) return 0.0;
      return 100.0 * (hwm - equity) / hwm;
   }
};

CRound12B g_Round12B;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round12B);
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
