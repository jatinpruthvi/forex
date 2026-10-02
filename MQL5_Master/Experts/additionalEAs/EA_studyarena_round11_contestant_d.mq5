//+------------------------------------------------------------------+
//| EA_studyarena_round11_contestant_d.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 11D - veteran spec: 0.4-0.5% cap, -2% throttle steps and three decorrelated sleeves
//| Source document : docs/research/study_arena/studyarena-round11-contestant-d.md
//| Tracker entry   : #71  |  Magic: 2038
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound11D class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 11D - veteran spec: 0.4-0.5% cap, -2% throttle steps and three decorrelated sleeves"
#property description "Source: docs/research/study_arena/studyarena-round11-contestant-d.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,XAUUSD,USDJPY,EURGBP";      // Comma separated universe
input double          InpRiskPct          = 0.50;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 0;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 20;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 4;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2038; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpVeteranRiskPct    = 0.50;  // Hard per-trade cap (veteran version)
input double InpThrottleStepPct   = 2.00;  // Halve risk every -2% from the equity high
input int    InpExpectancyWindow  = 50;    // Rolling expectation window (trades)
input double InpRetireExpectancyR = 0.05;  // Auto-retire threshold

//+------------------------------------------------------------------+
//| Strategy: Round 11D - veteran spec: 0.4-0.5% cap, -2% throttle steps and three decorrelated sleeves
//+------------------------------------------------------------------+
class CRound11D : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R11D_VETERAN_SPEC";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round11-contestant-d.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpVeteranRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 2;
      cfg.minSecondsBetweenTrades = 600;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;
      cfg.breakEvenAtR          = 1.00;
      cfg.trailAtR              = 1.50;  cfg.trailDistanceR = 0.75;
      cfg.timeStopMinutes       = 240;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- Sleeve 1: sweep-reclaim core (M5)
      SSweepParams p;
      p.Reset();
      p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
      p.sessionFromMin = 7 * 60; p.sessionToMin = 16 * 60;
      p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
      p.reclaimWindowBars = 3;
      p.wickRatio = 0.55; p.bodyRatio = 0.55;
      p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
      p.entryRetrace = 0.50; p.targetR = 2.0;
      if(SigSweepReclaim(ctx, p, plan)) { m_sleeve = 1; plan.reason = "R11D-CORE " + plan.reason; return true; }

      //--- Sleeve 2: volatility-expansion continuation
      if(ctx.adx14 > 25.0 && ctx.atrD1 > 0.0 && ctx.atr > 0.5 * ctx.atrD1)
      {
         if(SigEmaPullback(ctx, PullbackParams(), plan)) { m_sleeve = 2; plan.reason = "R11D-EXPANSION " + plan.reason; return true; }
      }

      //--- Sleeve 3: Asian-session mean reversion on the quiet crosses
      if(ctx.clockMinutes < 7 * 60 && (StringFind(ctx.symbol, "EURGBP") >= 0 || StringFind(ctx.symbol, "AUDNZD") >= 0))
      {
         SRangeFadeParams rf;
         rf.Reset();
         rf.bbPeriod = 20; rf.bbDeviation = 2.0;
         rf.rsiOversold = 5.0; rf.rsiOverbought = 95.0;
         rf.wickRatio = 0.50; rf.stopBufferAtr = 0.20;
         rf.targetR = 0.80; rf.requireRangeRegime = true; rf.maxAdx = 16.0;
         if(SigRangeFade(ctx, rf, plan)) { m_sleeve = 3; plan.reason = "R11D-ASIANMR " + plan.reason; return true; }
      }
      return false;
   }

   int m_sleeve;

   SEmaPullbackParams PullbackParams()
   {
      SEmaPullbackParams ep;
      ep.Reset();
      ep.emaPeriod = 20; ep.maxDistanceAtr = 1.20;
      ep.requireTrend = true; ep.targetR = 2.0;
      return ep;
   }

   //--- auto-retire protocol: rolling 50-trade expectancy below threshold
   bool RetireCheck()
   {
      if(!HistorySelect(TimeCurrent() - 180 * 24 * 3600, TimeCurrent())) return true;
      double wins = 0.0, losses = 0.0, sumWin = 0.0, sumLoss = 0.0;
      int count = 0;
      for(int i = HistoryDealsTotal() - 1; i >= 0 && count < InpExpectancyWindow; i--)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagicNumber) continue;
         if(HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
         double p = HistoryDealGetDouble(t, DEAL_PROFIT) +
                    HistoryDealGetDouble(t, DEAL_SWAP) +
                    HistoryDealGetDouble(t, DEAL_COMMISSION);
         if(p >= 0.0) { wins++; sumWin += p; } else { losses++; sumLoss -= p; }
         count++;
      }
      if(count < InpExpectancyWindow / 2) return true;
      double avgWin  = (wins > 0.0) ? sumWin / wins : 0.0;
      double avgLoss = (losses > 0.0) ? sumLoss / losses : 0.0;
      if(avgLoss <= 0.0) return true;
      double wr = wins / (double)count;
      double expR = wr * (avgWin / avgLoss) - (1.0 - wr);
      return (expR >= InpRetireExpectancyR);
   }

   //--- throttle: halve the risk for every -2% below the equity high
   double LotsMultiplier(SEAContext &ctx)
   {
      if(!RetireCheck()) return 0.0;                     // auto-retired
      if(ctx.riskPct <= 0.0) return 0.0;
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double hwm = GlobalVariableGet("R11D_HWM");
      if(hwm <= 0.0 || equity > hwm) { GlobalVariableSet("R11D_HWM", MathMax(equity, hwm)); return 1.0; }
      double dd = 100.0 * (hwm - equity) / hwm;
      int steps = (int)MathFloor(dd / InpThrottleStepPct);
      double mult = MathPow(0.5, steps);
      return MathMax(0.0, MathMin(mult, 1.0));
   }

   //--- shared risk budget: max four concurrent positions across the sleeves
   bool AllowMultipleOnSymbol() { return false; }
};

CRound11D g_Round11D;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round11D);
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
