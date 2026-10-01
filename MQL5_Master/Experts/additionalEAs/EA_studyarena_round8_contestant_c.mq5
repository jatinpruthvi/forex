//+------------------------------------------------------------------+
//| EA_studyarena_round8_contestant_c.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 8C - immediate close-entry reclaim with a 50/20/30 ladder and 3-loss de-risk
//| Source document : docs/research/study_arena/studyarena-round8-contestant-c.md
//| Tracker entry   : #61  |  Magic: 2028
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound8C class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 8C - immediate close-entry reclaim with a 50/20/30 ladder and 3-loss de-risk"
#property description "Source: docs/research/study_arena/studyarena-round8-contestant-c.md"

#include "..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD";      // Comma separated universe
input double          InpRiskPct          = 0.5;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 10.0;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 20;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 2;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2028; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpBaseRiskPct       = 0.50;  // Base risk (funded account)
input double InpDeRiskPct         = 0.25;  // Risk after three consecutive losses
input double InpStopAtrMult       = 1.50;  // Stop = 1.5 x M15 ATR beyond the wick
input double InpChandelierMult    = 2.50;  // 30% runner trail on the chandelier

//+------------------------------------------------------------------+
//| Strategy: Round 8C - immediate close-entry reclaim with a 50/20/30 ladder and 3-loss de-risk
//+------------------------------------------------------------------+
class CRound8C : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R8C_RECLAIM_LADDER";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round8-contestant-c.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpBaseRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.totalDdPct            = InpTotalDdPct;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 900;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      //--- 50% at 1R, 20% at 2R, 30% runner at 2.5 x H1 ATR
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;
      cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 20.0;
      cfg.breakEvenAtR          = 1.00;
      cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 1.00;
      cfg.timeStopMinutes       = 0;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- immediate entry on the reclaim close (no waiting for the retest)
      SSweepParams p;
      p.Reset();
      p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
      p.sessionFromMin = 7 * 60; p.sessionToMin = 12 * 60;
      p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
      p.reclaimWindowBars = 3;
      p.wickRatio = 0.55; p.bodyRatio = 0.55;
      p.stopBufferAtr = 0.10; p.minStopAtr = 0.50; p.maxStopAtr = 2.00;
      p.entryRetrace = 0.00;                        // enter at market on the reclaim candle
      p.targetR = 2.0;
      if(!SigSweepReclaim(ctx, p, plan)) return false;

      //--- stop exactly 1.5 x M15 ATR beyond the sweep wick (volatility dictates the stop)
      double buffer = InpStopAtrMult * ctx.atr;
      if(buffer <= 0.0) return false;
      double wickExtreme = (plan.dir > 0) ? plan.entry - plan.riskDist : plan.entry + plan.riskDist;
      plan.stop     = (plan.dir > 0) ? wickExtreme - buffer : wickExtreme + buffer;
      plan.riskDist = MathAbs(plan.entry - plan.stop);
      if(plan.riskDist <= 0.0) return false;
      plan.reason = "R8C-RECLAIM " + plan.reason;
      return true;
   }

   int LosingStreak()
   {
      if(!HistorySelect(TimeCurrent() - 14 * 24 * 3600, TimeCurrent())) return 0;
      int streak = 0;
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagicNumber) continue;
         if(HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
         double profit = HistoryDealGetDouble(t, DEAL_PROFIT) +
                         HistoryDealGetDouble(t, DEAL_SWAP) +
                         HistoryDealGetDouble(t, DEAL_COMMISSION);
         if(profit < 0.0) streak++;
         else break;
         if(streak >= 6) break;
      }
      return streak;
   }

   //--- halve risk after three consecutive losses (the <10% DD guarantee)
   double LotsMultiplier(SEAContext &ctx)
   {
      if(ctx.riskPct <= 0.0) return 0.0;
      double risk = (LosingStreak() >= 3) ? InpDeRiskPct : InpBaseRiskPct;
      return MathMax(0.0, risk / ctx.riskPct);
   }

   void Manage(SEAContext &ctx)
   {
      for(int t = 0; t < g_eaTrackCount; t++)
      {
         if(g_eaTrack[t].symbol != ctx.symbol) continue;
         if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double cur   = PositionGetDouble(POSITION_PRICE_CURRENT);
         double risk  = g_eaTrack[t].riskDist;
         if(risk <= 0.0) continue;
         double rMult = (g_eaTrack[t].dir > 0) ? (cur - entry) / risk : (entry - cur) / risk;
         if(rMult < 2.0) continue;
         double h1Atr = H1Atr(ctx);
         if(h1Atr <= 0.0) continue;
         MqlRates r[];
         if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 20, r) < 5) continue;
         double hh = r[0].high, ll = r[0].low;
         for(int i = 1; i < 20; i++) { hh = MathMax(hh, r[i].high); ll = MathMin(ll, r[i].low); }
         double newSl = (g_eaTrack[t].dir > 0) ? hh - InpChandelierMult * h1Atr
                                               : ll + InpChandelierMult * h1Atr;
         double oldSl = PositionGetDouble(POSITION_SL);
         if(g_eaTrack[t].dir > 0 && newSl > oldSl) g_eaExec.Modify(g_eaTrack[t].ticket, newSl, 0.0);
         if(g_eaTrack[t].dir < 0 && (oldSl == 0.0 || newSl < oldSl))
            g_eaExec.Modify(g_eaTrack[t].ticket, newSl, 0.0);
      }
   }

   double H1Atr(SEAContext &ctx)
   {
      double av[];
      if(EA_BufN(g_eaInd[ctx.index].hAtrD1, 0, 1, 20, av) < 5) return 0.0;
      return (av[0] > 0.0) ? av[0] / 6.0 : 0.0;
   }
};

CRound8C g_Round8C;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round8C);
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
