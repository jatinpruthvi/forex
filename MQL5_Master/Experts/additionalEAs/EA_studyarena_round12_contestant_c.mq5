//+------------------------------------------------------------------+
//| EA_studyarena_round12_contestant_c.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 12C - SR-10 survival: ban list, volatility percentile band and 0.70% open-risk cap
//| Source document : docs/research/study_arena/studyarena-round12-contestant-c.md
//| Tracker entry   : #77  |  Magic: 2044
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound12C class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 12C - SR-10 survival: ban list, volatility percentile band and 0.70% open-risk cap"
#property description "Source: docs/research/study_arena/studyarena-round12-contestant-c.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY,XAUUSD";      // Comma separated universe
input double          InpRiskPct          = 0.50;   // Base risk per trade (% of equity)
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2044; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpOpenRiskCapPct    = 0.70;  // Aggregate open risk ceiling
input int    InpMaxPositions      = 2;     // Max two simultaneous positions
input int    InpMaxTradesDay      = 3;     // Max three completed trades per day

//+------------------------------------------------------------------+
//| Strategy: Round 12C - SR-10 survival: ban list, volatility percentile band and 0.70% open-risk cap
//+------------------------------------------------------------------+
class CRound12C : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R12C_SR10_SURVIVAL";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round12-contestant-c.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M1;              // M1 scalping core
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = InpMaxTradesDay;
      cfg.maxOpenPositions      = InpMaxPositions;
      cfg.minSecondsBetweenTrades = 600;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 20;  cfg.sessionEndMin   = 30;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;
      cfg.breakEvenAtR          = 1.00;
      cfg.trailAtR              = 1.50;  cfg.trailDistanceR = 0.75;
      cfg.timeStopMinutes       = 60;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- banned behaviours are simply not implemented: no grid, no averaging, no martingale
      if(EA_OpenRiskPct() >= InpOpenRiskCapPct) return false;
      if(EA_CountPositions("", false) >= InpMaxPositions) return false;
      if(!VolatilityBandOk(ctx)) return false;
      if(!H1Directional(ctx)) return false;

      //--- one trade per instrument per session: the engine's daily cap plus this guard
      if(TradedThisSession(ctx.symbol)) return false;

      SSweepParams p;
      p.Reset();
      p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
      p.sessionFromMin = 7 * 60; p.sessionToMin = 17 * 60;
      p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
      p.reclaimWindowBars = 3;
      p.wickRatio = 0.55; p.bodyRatio = 0.55;
      p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
      p.entryRetrace = 0.50; p.targetR = 2.0;
      if(!SigSweepReclaim(ctx, p, plan)) return false;

      //--- the sweep must agree with the H1 direction (no counter-trend fading)
      if(!H1AgreesWith(ctx, plan.dir)) return false;
      plan.reason = "R12C-SR10 " + plan.reason;
      return true;
   }

   bool VolatilityBandOk(SEAContext &ctx)
   {
      double av[];
      if(EA_BufN(g_eaInd[ctx.index].hAtr, 0, 1, 500, av) < 50) return true;
      double median = Median(av);
      if(median <= 0.0) return true;
      double ratio = ctx.atr / median;
      //--- 20th-85th percentile band (narrow proxies for the ATR distribution)
      return (ratio >= 0.6 && ratio <= 1.6);
   }

   double Median(double &arr[])
   {
      double s[];
      int n = ArraySize(arr);
      ArrayResize(s, n);
      ArrayCopy(s, arr);
      ArraySort(s);
      return s[n / 2];
   }

   bool H1Directional(SEAContext &ctx)
   {
      if(ctx.emaH1_50 <= 0.0) return false;
      //--- slope over the previous five completed H1 candles (D1 ATR/6 ~ H1 ATR proxy)
      double h1Atr = (ctx.atrD1 > 0.0) ? ctx.atrD1 / 6.0 : 0.0;
      if(h1Atr <= 0.0) return true;
      return (MathAbs(ctx.mid - ctx.emaH1_50) > 0.05 * h1Atr);
   }

   bool H1AgreesWith(SEAContext &ctx, const int dir)
   {
      if(ctx.emaH1_50 <= 0.0) return false;
      return (dir > 0) ? (ctx.mid > ctx.emaH1_50) : (ctx.mid < ctx.emaH1_50);
   }

   bool TradedThisSession(const string sym)
   {
      if(!HistorySelect(TimeCurrent() - 24 * 3600, TimeCurrent())) return false;
      MqlDateTime dt;
      TimeToStruct(TimeTradeServer(), dt);
      int nowMin = dt.hour * 60 + dt.min;
      datetime from = TimeTradeServer() - (datetime)(MathMax(0, nowMin - 7 * 60) * 60);
      for(int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagicNumber) continue;
         if(HistoryDealGetString(t, DEAL_SYMBOL) != sym) continue;
         if(HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
         if((datetime)HistoryDealGetInteger(t, DEAL_TIME) >= from) return true;
      }
      return false;
   }
};

CRound12C g_Round12C;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round12C);
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
