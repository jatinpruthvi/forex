//+------------------------------------------------------------------+
//| EA_studyarena_round10_gemini_3_1_pro_preview_high_reasoning.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 10 Gemini - M1 delta-sweep scalper with volume divergence and tick acceleration
//| Source document : docs/research/study_arena/studyarena-round10-gemini-3-1-pro-preview-high-reasoning.md
//| Tracker entry   : #65  |  Magic: 2032
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound10Gemini class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 10 Gemini - M1 delta-sweep scalper with volume divergence and tick acceleration"
#property description "Source: docs/research/study_arena/studyarena-round10-gemini-3-1-pro-preview-high-reasoning.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY,XAUUSD";      // Comma separated universe
input double          InpRiskPct          = 0.50;   // Base risk per trade (% of equity)
input int             InpMaxTradesPerDay  = 8;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2032; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input int    InpSwingBars         = 240;   // 4-hour local extreme window (M1 bars)
input double InpMinPierceAtr      = 0.05;  // Piercing depth minimum
input double InpTickAcceleration  = 2.00;  // Tick speed must be 200% of the 5-min average
input double InpMaxSpreadPips     = 0.80;  // Spread gate (doc: < 0.8 pips; raise it for 2-digit metals)

//+------------------------------------------------------------------+
//| Strategy: Round 10 Gemini - M1 delta-sweep scalper with volume divergence and tick acceleration
//+------------------------------------------------------------------+
class CRound10Gemini : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R10GEMINI_DELTA_SCALP";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round10-gemini-3-1-pro-preview-high-reasoning.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M1;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 120;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 19;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.partial1AtR           = 1.50;  cfg.partial1Pct = 60.0;   // doc TP1: 60% at +1.5R
      cfg.breakEvenAtR          = 1.50;   // doc: BE at TP1 (+1.5R)
      cfg.trailAtR              = 1.50;  cfg.trailDistanceR = 0.50;
      cfg.timeStopMinutes       = 12;     // doc: 12 minutes (12 M1 candles)
      cfg.timeStopUnlessR       = 1.00;   // doc: only while the trade is below +1R
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      MqlRates r[];
      //--- doc: the instrument list requires spreads below 0.8 pips
      if(EA_SpreadPips(ctx.symbol) > InpMaxSpreadPips)
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.2f pips > %.2f - skip (doc < 0.8 pips)", ctx.symbol, EA_SpreadPips(ctx.symbol), InpMaxSpreadPips), true);
         return false;
      }
      if(EA_Rates(ctx.symbol, PERIOD_M1, 1, InpSwingBars + 6, r) < InpSwingBars + 5) return false;

      //--- local 4-hour extreme, EXCLUDING the sweep bar itself: seeding the
      //--- extreme from r[0] and then testing r[0] against it can never be true
      double hi = r[1].high, lo = r[1].low;
      for(int i = 2; i <= InpSwingBars; i++) { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }

      bool sweptLow  = (r[0].low  < lo - InpMinPierceAtr * ctx.atr && r[0].close > lo);
      bool sweptHigh = (r[0].high > hi + InpMinPierceAtr * ctx.atr && r[0].close < hi);
      if(!sweptLow && !sweptHigh) return false;

      //--- volume-delta divergence: delta must improve against the sweep direction
      double d0 = Delta(r[0]), d1 = Delta(r[1]), d2 = Delta(r[2]);
      bool deltaOk = sweptLow ? (d0 > d1 && d1 < d2)      // declining negative flow on a low sweep
                              : (d0 < d1 && d1 > d2);
      if(!deltaOk) return false;

      //--- tick acceleration vs the 5-minute rolling average
      double tickNow = (double)r[0].tick_volume;
      double avg = 0.0;
      for(int i = 1; i <= 5; i++) avg += (double)r[i].tick_volume;
      avg /= 5.0;
      if(avg <= 0.0 || tickNow < InpTickAcceleration * avg) return false;

      int dir = sweptLow ? +1 : -1;
      plan.Reset();
      plan.dir   = dir;
      plan.entry = (dir > 0) ? ctx.ask : ctx.bid;
      double pt  = EA_Point(ctx.symbol);
      plan.stop  = (dir > 0) ? r[0].low - pt : r[0].high + pt;    // 1 pip beyond the extremum
      plan.riskDist = MathAbs(plan.entry - plan.stop);
      if(plan.riskDist <= 0.0) return false;
      plan.target = (dir > 0) ? plan.entry + 3.0 * plan.riskDist : plan.entry - 3.0 * plan.riskDist;
      plan.score    = 65.0;
      plan.reason   = StringFormat("R10GEMINI-DELTA(tick %.1fx)", tickNow / avg);
      return true;
   }

   double Delta(const MqlRates &bar)
   {
      double range = bar.high - bar.low;
      if(range <= 0.0) return 0.0;
      double buyFrac  = (bar.close - bar.low) / range;
      double sellFrac = (bar.high - bar.close) / range;
      return (buyFrac - sellFrac) * (double)bar.tick_volume;
   }
};

CRound10Gemini g_Round10Gemini;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round10Gemini);
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
