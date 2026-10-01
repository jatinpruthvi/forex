//+------------------------------------------------------------------+
//| EA_studyarena_round7_contestant_c.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 7C - 5% single strategy: 1.5x M15 ATR stop with an hourly chandelier runner
//| Source document : docs/research/study_arena/studyarena-round7-contestant-c.md
//| Tracker entry   : #57  |  Magic: 2024
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound7C class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 7C - 5% single strategy: 1.5x M15 ATR stop with an hourly chandelier runner"
#property description "Source: docs/research/study_arena/studyarena-round7-contestant-c.md"

#include "..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD";      // Comma separated universe
input double          InpRiskPct          = 0.75;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 0;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 20;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 2;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2024; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpEurFuelPips       = 35;    // Skip if the Asian range already expanded (EURUSD)
input double InpGbpFuelPips       = 45;    // GBPUSD expansion filter
input double InpStopAtrMult       = 1.50;  // Stop = 1.5 x M15 ATR
input double InpChandelierMult    = 2.50;  // Chandelier = high - 2.5 x H1 ATR
input bool   InpCarryHarvest      = true;  // Positive-carry overlay sleeve

//+------------------------------------------------------------------+
//| Strategy: Round 7C - 5% single strategy: 1.5x M15 ATR stop with an hourly chandelier runner
//+------------------------------------------------------------------+
class CRound7C : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R7C_FIVE_PERCENT";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round7-contestant-c.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;             // 0.75%
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 900;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;
      cfg.breakEvenAtR          = 1.00;
      cfg.trailAtR              = 1.00;  cfg.trailDistanceR = 1.00;
      cfg.timeStopMinutes       = 0;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      if(!FuelAvailable(ctx)) return false;

      SSweepParams p;
      p.Reset();
      p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
      p.sessionFromMin = 7 * 60; p.sessionToMin = 12 * 60;
      p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.55;
      p.reclaimWindowBars = 3; p.wickRatio = 0.55; p.bodyRatio = 0.55;
      p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.80;
      p.entryRetrace = 0.50; p.targetR = 3.20;         // no fixed TP - the trail decides
      if(!SigSweepReclaim(ctx, p, plan)) return false;

      double stopDist = InpStopAtrMult * ctx.atr;       // mechanics, not fixed pips
      if(stopDist > 0.0)
      {
         plan.stop     = (plan.dir > 0) ? plan.entry - stopDist : plan.entry + stopDist;
         plan.riskDist = stopDist;
         plan.target   = (plan.dir > 0) ? plan.entry + 3.20 * stopDist
                                        : plan.entry - 3.20 * stopDist;
      }
      plan.reason = "R7C-SWEEP " + plan.reason;
      return true;
   }

   bool FuelAvailable(SEAContext &ctx)
   {
      double hi = 0.0, lo = 0.0;
      if(!SigAsianRange(ctx.symbol, hi, lo)) return false;
      double pip = EA_PipSize(ctx.symbol);
      if(pip <= 0.0) return false;
      double pips = (hi - lo) / pip;
      if(StringFind(ctx.symbol, "GBPUSD") >= 0) return (pips <= InpGbpFuelPips);
      return (pips <= InpEurFuelPips);
   }

   //--- hourly chandelier trail on the runner half
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
         if(rMult < 1.0) continue;
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

CRound7C g_Round7C;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round7C);
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
