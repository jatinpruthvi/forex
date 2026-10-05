//+------------------------------------------------------------------+
//| EA_studyarena_round11_contestant_c.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 11C - decade-honest risk throttle: halve at -3%, quarter at -5%, month over at -5.5%
//| Source document : docs/research/study_arena/studyarena-round11-contestant-c.md
//| Tracker entry   : #70  |  Magic: 2037
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound11C class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 11C - decade-honest risk throttle: halve at -3%, quarter at -5%, month over at -5.5%"
#property description "Source: docs/research/study_arena/studyarena-round11-contestant-c.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY,XAUUSD";      // Comma separated universe
input int             InpMaxTradesPerDay  = 4;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2037; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpEffectiveRiskPct  = 0.80;  // Effective risk (combined 1/20th Kelly)
input double InpHalfAtDdPct       = 3.00;  // Halve risk at -3% from the equity high
input double InpQuarterAtDdPct    = 5.00;  // Quarter risk at -5%
input double InpMonthOverDdPct    = 5.50;  // Month over at -5.5% (not -6%)
input double InpMinExpectancyR    = 0.10;  // Rolling 30-trade expectancy pause
input double InpMaxSlipPctOfExp   = 20.0;  // Disable a symbol whose slippage eats this % of expectancy

//+------------------------------------------------------------------+
//| Strategy: Round 11C - decade-honest risk throttle: halve at -3%, quarter at -5%, month over at -5.5%
//+------------------------------------------------------------------+
class CRound11C : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R11C_DECADE_THROTTLE";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round11-contestant-c.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpEffectiveRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.totalDdPct            = InpMonthOverDdPct;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
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
      if(!EdgeAlive()) return false;
      //--- cost realism: a symbol whose slippage eats into expectancy is disabled
      if(!EA_SymbolSlippageOk(ctx.symbol, InpMaxSlipPctOfExp))
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("%s disabled: slippage eats > %.0f%% of expectancy",
                ctx.symbol, InpMaxSlipPctOfExp), true);
         return false;
      }
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
      plan.reason = "R11C-DECADE " + plan.reason;
      return true;
   }

   //--- edge-decay governor: rolling 30-trade expectancy must stay above 0.10R
   bool EdgeAlive()
   {
      double expR = RollingExpectancy(30);
      return (expR >= InpMinExpectancyR);
   }

   double RollingExpectancy(const int n)
   {
      if(!HistorySelect(TimeCurrent() - 120 * 24 * 3600, TimeCurrent())) return InpMinExpectancyR;
      double wins = 0.0, losses = 0.0, sumWin = 0.0, sumLoss = 0.0;
      int count = 0;
      for(int i = HistoryDealsTotal() - 1; i >= 0 && count < n; i--)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagicNumber) continue;
         if(HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
         double p = HistoryDealGetDouble(t, DEAL_PROFIT) +
                    HistoryDealGetDouble(t, DEAL_SWAP) +
                    HistoryDealGetDouble(t, DEAL_COMMISSION);
         if(p >= 0.0) { wins++; sumWin += p; }
         else         { losses++; sumLoss -= p; }
         count++;
      }
      if(count < 10) return InpMinExpectancyR;           // not enough evidence: keep trading
      double avgWin  = (wins > 0.0) ? sumWin / wins : 0.0;
      double avgLoss = (losses > 0.0) ? sumLoss / losses : 0.0;
      if(avgLoss <= 0.0) return 1.0;
      double wr = wins / (double)count;
      return wr * (avgWin / avgLoss) - (1.0 - wr);
   }

   //--- three-tier drawdown throttle from the equity high watermark
   double LotsMultiplier(SEAContext &ctx)
   {
      if(ctx.riskPct <= 0.0) return 0.0;
      double dd = DrawdownPct();
      double mult = 1.0;
      if(dd >= InpHalfAtDdPct)    mult = 0.50;
      if(dd >= InpQuarterAtDdPct) mult = 0.25;
      return MathMax(0.0, mult);
   }

   double DrawdownPct()
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double hwm = GlobalVariableGet(EA_HwmKey("R11C", false));
      if(hwm <= 0.0 || equity > hwm) { GlobalVariableSet(EA_HwmKey("R11C", false), MathMax(equity, hwm)); return 0.0; }
      if(hwm <= 0.0) return 0.0;
      return 100.0 * (hwm - equity) / hwm;
   }
};

CRound11C g_Round11C;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round11C);
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
