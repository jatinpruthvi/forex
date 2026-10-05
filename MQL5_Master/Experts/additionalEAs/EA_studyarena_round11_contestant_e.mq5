//+------------------------------------------------------------------+
//| EA_studyarena_round11_contestant_e.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 11E - SWEEP-1 veteran: score gate, DD-tier risk ladder and Friday flat
//| Source document : docs/research/study_arena/studyarena-round11-contestant-e.md
//| Tracker entry   : #72  |  Magic: 2039
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound11E class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 11E - SWEEP-1 veteran: score gate, DD-tier risk ladder and Friday flat"
#property description "Source: docs/research/study_arena/studyarena-round11-contestant-e.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY,XAUUSD,AUDNZD,EURGBP";      // Comma separated universe
input int             InpMaxTradesPerDay  = 6;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2039; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input int    InpMinScore           = 7;     // Score gate (/8)
input double InpTier0RiskPct      = 0.60;  // DD 0-2%
input double InpTier1RiskPct      = 0.30;  // DD 2-4%
input double InpTier2RiskPct      = 0.15;  // DD 4-6%
input double InpShutdownDdPct     = 6.00;  // Shutdown for the month above this
input double InpMaxOpenRiskPct    = 1.20;  // Max total open risk

//+------------------------------------------------------------------+
//| Strategy: Round 11E - SWEEP-1 veteran: score gate, DD-tier risk ladder and Friday flat
//+------------------------------------------------------------------+
class CRound11E : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R11E_SWEEP1_VETERAN";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round11-contestant-e.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpTier0RiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.totalDdPct            = InpShutdownDdPct;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 2;                     // correlated pairs count as one
      cfg.minSecondsBetweenTrades = 120;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 30;   // thin hours excluded
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 45;  // flat Friday close
      cfg.signalOnNewBarOnly    = true;
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;
      cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 30.0;
      cfg.breakEvenAtR          = 1.00;
      cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 1.00;
      cfg.timeStopMinutes       = 180;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      if(ctx.clockMinutes >= 21 * 60 + 30) return false;      // 21:30-23:30 spread blowouts
      if(OpenRiskTooHigh()) return false;
      if(GroupBlocked(ctx)) return false;

      SSweepParams p;
      p.Reset();
      p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
      p.sessionFromMin = 7 * 60; p.sessionToMin = 16 * 60;
      p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
      p.reclaimWindowBars = 3;
      p.wickRatio = 0.60; p.bodyRatio = 0.60;
      p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
      p.entryRetrace = 0.50; p.targetR = 2.0;
      if(!SigSweepReclaim(ctx, p, plan)) return false;

      int score = ScoreSetup(ctx, plan);
      if(score < InpMinScore) return false;
      plan.score  = score * 12.5;
      plan.reason = StringFormat("R11E-SWEEP1(%d/8) %s", score, plan.reason);
      return true;
   }

   int ScoreSetup(SEAContext &ctx, SSignalPlan &plan)
   {
      int score = 4;
      if(ctx.emaH1_50 > 0.0 && ((plan.dir > 0 && ctx.mid > ctx.emaH1_50) ||
                                (plan.dir < 0 && ctx.mid < ctx.emaH1_50))) score++;
      if(ctx.adx14 >= 18.0 && ctx.adx14 <= 35.0) score++;
      double costR = (plan.riskDist > 0.0) ? (ctx.spreadPoints * ctx.point) / plan.riskDist : 1.0;
      if(costR <= 0.10) score++;
      if(ctx.atrD1 > 0.0 && ctx.atr > 0.4 * ctx.atrD1) score++;
      return MathMin(score, 8);
   }

   bool OpenRiskTooHigh()
   {
      return (EA_OpenRiskPct() > InpMaxOpenRiskPct);
   }

   bool GroupBlocked(SEAContext &ctx)
   {
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         string other = PositionGetString(POSITION_SYMBOL);
         if(other == ctx.symbol) continue;
         //--- correlated USD pairs count as ONE position
         bool usdA = (StringFind(ctx.symbol, "USD") >= 0);
         bool usdB = (StringFind(other, "USD") >= 0);
         if(usdA && usdB) return true;
      }
      return false;
   }

   //--- DD-tier risk ladder with a hard monthly shutdown
   double LotsMultiplier(SEAContext &ctx)
   {
      if(ctx.riskPct <= 0.0) return 0.0;
      double dd = DrawdownPct();
      if(dd >= InpShutdownDdPct) return 0.0;             // shutdown for the month
      double risk = InpTier0RiskPct;
      if(dd >= 4.0)      risk = InpTier2RiskPct;
      else if(dd >= 2.0) risk = InpTier1RiskPct;
      return MathMax(0.0, risk / ctx.riskPct);
   }

   double DrawdownPct()
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double hwm = GlobalVariableGet(EA_HwmKey("R11E", true));
      if(hwm <= 0.0 || equity > hwm) { GlobalVariableSet(EA_HwmKey("R11E", true), MathMax(equity, hwm)); return 0.0; }
      if(hwm <= 0.0) return 0.0;
      return 100.0 * (hwm - equity) / hwm;
   }
};

CRound11E g_Round11E;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round11E);
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
