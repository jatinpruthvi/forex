//+------------------------------------------------------------------+
//| EA_studyarena_round7_contestant_a.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 7A - GER40 cash open gap fade: 20-80 point filter, 1.5x stop, exact gap fill
//| Source document : docs/research/study_arena/studyarena-round7-contestant-a.md
//| Tracker entry   : #55  |  Magic: 2022
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound7A class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 7A - GER40 cash open gap fade: 20-80 point filter, 1.5x stop, exact gap fill"
#property description "Source: docs/research/study_arena/studyarena-round7-contestant-a.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "GER40,DE40,GER30,DAX";      // Comma separated universe
input double          InpRiskPct          = 1.0;   // Base risk per trade (% of equity)
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2022; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpGapMinPoints      = 20.0;  // Minimum gap (index points)
input double InpGapMaxPoints      = 80.0;  // Maximum gap (breakaway gaps excluded)
input int    InpCashOpenMin       = 8 * 60;   // 08:00 UK cash open
input int    InpPriorCashCloseMin = 16 * 60 + 30;  // 16:30 UK prior close
input int    InpHardTimeStopMin   = 11 * 60;  // Flat by 11:00 UK, win or lose

//+------------------------------------------------------------------+
//| Strategy: Round 7A - GER40 cash open gap fade: 20-80 point filter, 1.5x stop, exact gap fill
//+------------------------------------------------------------------+
class CRound7A : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R7A_DAX_GAP_FADE";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round7-contestant-a.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = 1;                 // one trade per day, by design
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 0;
      cfg.sessionStartHour      = 8;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 11;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = false;
      cfg.signalOnNewBarOnly    = true;
      cfg.timeStopMinutes       = 0;                 // managed by the 11:00 clock stop
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      if(ctx.clockMinutes < InpCashOpenMin || ctx.clockMinutes >= InpHardTimeStopMin) return false;

      //--- gap = today's cash open vs yesterday's exact 16:30 close
      double priorClose = PriorCashClose(ctx.symbol);
      double cashOpen   = CashOpen(ctx.symbol);
      if(priorClose <= 0.0 || cashOpen <= 0.0) return false;

      double gap = cashOpen - priorClose;
      double gapAbs = MathAbs(gap);
      if(gapAbs < InpGapMinPoints || gapAbs > InpGapMaxPoints) return false;

      int dir = (gap > 0.0) ? -1 : +1;                 // fade the gap
      double stopDist = 1.5 * gapAbs * ctx.point;      // 1.5x the gap in price units

      plan.Reset();
      plan.dir      = dir;
      plan.entry    = (dir > 0) ? ctx.ask : ctx.bid;
      plan.riskDist = stopDist;
      plan.stop     = (dir > 0) ? plan.entry - stopDist : plan.entry + stopDist;
      plan.target   = priorClose;                      // exact gap fill
      plan.score    = 70.0;
      plan.reason   = StringFormat("R7A-GAPFADE(%.0f pts)", gapAbs);
      return true;
   }

   //--- close of the last session bar before 16:30 prior day
   double PriorCashClose(const string sym)
   {
      MqlRates r[];
      if(EA_Rates(sym, PERIOD_M5, 1, 300, r) < 10) return 0.0;
      MqlDateTime now;
      TimeToStruct(TimeTradeServer(), now);
      for(int i = 0; i < 300; i++)
      {
         MqlDateTime t;
         TimeToStruct(r[i].time, t);
         if(t.day == now.day) continue;                      // yesterday or older
         if(t.hour * 60 + t.min >= InpPriorCashCloseMin) return r[i].close;
      }
      return 0.0;
   }

   //--- open of the first bar at/after 08:00 today
   double CashOpen(const string sym)
   {
      MqlRates r[];
      if(EA_Rates(sym, PERIOD_M5, 0, 120, r) < 5) return 0.0;
      MqlDateTime now;
      TimeToStruct(TimeTradeServer(), now);
      for(int i = ArraySize(r) - 1; i >= 0; i--)
      {
         MqlDateTime t;
         TimeToStruct(r[i].time, t);
         if(t.day != now.day) continue;
         if(t.hour * 60 + t.min >= InpCashOpenMin) return r[i].open;
      }
      return 0.0;
   }

   //--- hard 11:00 UK time stop, win or lose
   void Manage(SEAContext &ctx)
   {
      if(ctx.clockMinutes < InpHardTimeStopMin) return;
      if(EA_CountPositions(ctx.symbol, true) == 0) return;
      g_eaExec.CloseAll("11:00 UK time stop");
   }
};

CRound7A g_Round7A;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round7A);
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
