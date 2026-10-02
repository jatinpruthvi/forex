//+------------------------------------------------------------------+
//| EA_studyarena_round5_contestant_c.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 5C - honest-math London sweep with chandelier trail and fuel filter
//| Source document : docs/research/study_arena/studyarena-round5-contestant-c.md
//| Tracker entry   : #51  |  Magic: 2018
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound5C class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 5C - honest-math London sweep with chandelier trail and fuel filter"
#property description "Source: docs/research/study_arena/studyarena-round5-contestant-c.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD";      // Comma separated universe
input double          InpRiskPct          = 0.75;   // Base risk per trade (% of equity)
input int             InpMaxTradesPerDay  = 2;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2018; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpEurMaxRangePips   = 35;    // Skip if the Asian range already expanded (EURUSD)
input double InpGbpMaxRangePips   = 45;    // GBPUSD fuel filter
input double InpStopAtrMult       = 1.50;  // Stop = 1.5 x M15 ATR
input double InpChandelierH1Atr   = 2.50;  // Trail = high - 2.5 x H1 ATR
input int    InpChandelierBars    = 20;    // Highest high lookback for the trail

//+------------------------------------------------------------------+
//| Strategy: Round 5C - honest-math London sweep with chandelier trail and fuel filter
//+------------------------------------------------------------------+
class CRound5C : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R5C_LONDON_SWEEP_HONEST";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round5-contestant-c.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;              // 0.75%
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 600;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;   // doc: hard flat 16:00 (the >2R runner exemption is not implemented)
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;   // 50% off at 1R
      cfg.breakEvenAtR          = 1.00;
      cfg.trailAtR              = 0.0;   // doc: the 1H-swing chandelier in Manage() is the runner trail
      cfg.trailDistanceR        = 1.00;
      cfg.timeStopMinutes       = 0;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      if(!RangeHasFuel(ctx)) return false;
      SSweepParams p;
      p.Reset();
      p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
      p.sessionFromMin = 7 * 60; p.sessionToMin = 12 * 60;
      p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
      p.reclaimWindowBars = 3; p.wickRatio = 0.55; p.bodyRatio = 0.55;
      p.stopBufferAtr = 0.10; p.minStopAtr = InpStopAtrMult * 0.4;
      p.maxStopAtr = InpStopAtrMult * 1.2;
      p.entryRetrace = 0.50;
      p.targetR = 3.20;                          // 40% runner to ~3.2R
      if(!SigSweepReclaim(ctx, p, plan)) return false;

      //--- mechanical stop: 1.5 x M15 ATR (never a fixed pip count)
      double stopDist = InpStopAtrMult * ctx.atr;
      if(stopDist > 0.0)
      {
         plan.stop     = (plan.dir > 0) ? plan.entry - stopDist : plan.entry + stopDist;
         plan.riskDist = stopDist;
         plan.target   = (plan.dir > 0) ? plan.entry + p.targetR * stopDist
                                        : plan.entry - p.targetR * stopDist;
      }
      plan.reason = "R5C-LONDONSWEEP " + plan.reason;
      return true;
   }

   bool RangeHasFuel(SEAContext &ctx)
   {
      double hi = 0.0, lo = 0.0;
      if(!SigAsianRange(ctx.symbol, hi, lo)) return false;
      double pip = EA_PipSize(ctx.symbol);
      if(pip <= 0.0) return false;
      double pips = (hi - lo) / pip;
      if(StringFind(ctx.symbol, "GBPUSD") >= 0) return (pips <= InpGbpMaxRangePips);
      return (pips <= InpEurMaxRangePips);
   }

   //--- Chandelier trail: high - 2.5 x H1 ATR, updated on every new bar, no TP
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
         if(rMult < 1.0) continue;              // chandelier only after +1R
         double h1Atr = H1Atr(ctx);
         if(h1Atr <= 0.0) continue;
         MqlRates r[];
         if(EA_Rates(ctx.symbol, PERIOD_M15, 1, InpChandelierBars, r) < 5) continue;
         double hh = r[0].high, ll = r[0].low;
         for(int i = 1; i < InpChandelierBars; i++)
         { hh = MathMax(hh, r[i].high); ll = MathMin(ll, r[i].low); }
         double newSl = (g_eaTrack[t].dir > 0) ? hh - InpChandelierH1Atr * h1Atr
                                               : ll + InpChandelierH1Atr * h1Atr;
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
      double d1 = av[0];
      if(ctx.atrH1 > 0.0) return ctx.atrH1;                 // real H1 ATR
      return (d1 > 0.0) ? d1 / 6.0 : 0.0;       // fallback: ~H1 ATR from the daily ATR
   }
};

CRound5C g_Round5C;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round5C);
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
