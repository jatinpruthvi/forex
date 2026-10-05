//+------------------------------------------------------------------+
//| EA_studyarena_round7_contestant_d.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 7D - regime-switched compression breakout with adaptive stops
//| Source document : docs/research/study_arena/studyarena-round7-contestant-d.md
//| Tracker entry   : #58  |  Magic: 2025
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound7D class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 7D - regime-switched compression breakout with adaptive stops"
#property description "Source: docs/research/study_arena/studyarena-round7-contestant-d.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,XAUUSD";      // Comma separated universe
input double          InpRiskPct          = 1.0;   // Base risk per trade (% of equity)
input int             InpMaxTradesPerDay  = 3;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2025; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpRangeLowPct       = 35.0;  // Overnight range vs 20-day median (floor)
input double InpRangeHighPct      = 75.0;  // Overnight range vs 20-day median (ceiling)
input double InpAdxLow            = 18.0;  // H1 ADX band floor
input double InpAdxHigh           = 35.0;  // H1 ADX band ceiling
input double InpStopMinAtr        = 0.60;  // Stop must be within 0.6-1.5 x M15 ATR
input double InpStopMaxAtr        = 1.50;

//+------------------------------------------------------------------+
//| Strategy: Round 7D - regime-switched compression breakout with adaptive stops
//+------------------------------------------------------------------+
class CRound7D : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R7D_REGIME_BREAKOUT";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round7-contestant-d.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 600;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 30;   // doc: close the runner by 16:30 London
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;
      cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 30.0;   // doc: 40% / 30% / 30% runner
      cfg.breakEvenAtR          = 1.00;
      cfg.breakEvenOnBarClose   = true;    // doc: BE only after a close beyond +1R
      cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 0.75;
      cfg.timeStopMinutes       = 240;
      cfg.useLimitEntry         = true;
      cfg.pendingExpiryMinutes  = 15;    // cancel if not filled within three M5 candles
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      if(ctx.clockMinutes < 7 * 60 || ctx.clockMinutes >= 10 * 60) return false;
      if(!ConditionFilter(ctx)) return false;

      //--- long: sweep below the overnight low, close back inside, break the last lower high
      SSweepParams p;
      p.Reset();
      p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
      p.sessionFromMin = 7 * 60; p.sessionToMin = 10 * 60;
      p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
      p.reclaimWindowBars = 6;             // the document allows six M5 candles
      p.wickRatio = 0.60; p.bodyRatio = 0.60;
      p.stopBufferAtr = 0.10;
      p.minStopAtr = InpStopMinAtr; p.maxStopAtr = InpStopMaxAtr;
      p.entryRetrace = 0.50;               // first retracement to 50% of the displacement
      p.targetR = 2.0;
      if(!SigSweepReclaim(ctx, p, plan)) return false;

      //--- adaptive stop band on the M15 ATR
      if(plan.riskDist < InpStopMinAtr * ctx.atr || plan.riskDist > InpStopMaxAtr * ctx.atr)
         return false;
      plan.reason = "R7D-COMPRESSIONBREAK " + plan.reason;
      return true;
   }

   //--- range percentile + H1 regime + EMA structure filter
   bool ConditionFilter(SEAContext &ctx)
   {
      double hi = 0.0, lo = 0.0;
      if(!SigAsianRange(ctx.symbol, hi, lo)) return false;
      double overnight = hi - lo;
      double median = MedianDailyRange(ctx.symbol);
      if(median <= 0.0) return false;
      double ratio = overnight / median;
      if(ratio < InpRangeLowPct / 100.0 || ratio > InpRangeHighPct / 100.0) return false;
      if(ctx.adxH1 < InpAdxLow || ctx.adxH1 > InpAdxHigh) return false;   // doc: H1 ADX(14) 18-35
      if(ctx.emaH1_200 <= 0.0) return false;             // price must hold one side of the 200-EMA
      bool up = (ctx.mid > ctx.emaH1_200);
      if(ctx.emaH1_50 > 0.0)
      {
         bool emaUp = (ctx.emaH1_50 > ctx.emaH1_200);
         if(up != emaUp) return false;                   // 20-EMA slope must agree
      }
      return true;
   }

   double MedianDailyRange(const string sym)
   {
      MqlRates d[];
      int got = EA_Rates(sym, PERIOD_D1, 1, 20, d);
      if(got < 10) return 0.0;
      double s[];
      ArrayResize(s, got);               // (the delivered code sized and read 20 after checking only 10)
      for(int i = 0; i < got; i++) s[i] = d[i].high - d[i].low;
      ArraySort(s);
      return s[got / 2];                 // = s[10] on a full 20-day window
   }
};

CRound7D g_Round7D;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round7D);
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
