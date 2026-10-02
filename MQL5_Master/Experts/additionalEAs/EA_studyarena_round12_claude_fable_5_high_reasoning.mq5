//+------------------------------------------------------------------+
//| EA_studyarena_round12_claude_fable_5_high_reasoning.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 12 Fable - SWEEP-1 the 10-year machine with six entry gates and flow checks
//| Source document : docs/research/study_arena/studyarena-round12-claude-fable-5-high-reasoning.md
//| Tracker entry   : #74  |  Magic: 2041
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound12Fable class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 12 Fable - SWEEP-1 the 10-year machine with six entry gates and flow checks"
#property description "Source: docs/research/study_arena/studyarena-round12-claude-fable-5-high-reasoning.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "AUDNZD,EURGBP,EURUSD,GBPUSD,XAUUSD,USDJPY";      // Comma separated universe
input double          InpRiskPct          = 0.60;   // Base risk per trade (% of equity)
input int             InpMaxTradesPerDay  = 6;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2041; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpRangeLowPct       = 35.0;  // Range gate: 35% of the 20-day median
input double InpRangeHighPct      = 75.0;  // Range gate: 75% ceiling
input double InpSpreadAvgX        = 1.50;  // Spread <= 1.5x the 20-day average
input double InpSweepVolumeX      = 1.20;  // Sweep-candle volume >= 1.2x the 20-candle average
input int    InpThinHourFrom      = 21 * 60 + 30;  // Thin hours begin (21:30 UK)
input int    InpThinHourTo        = 23 * 60 + 30;

//+------------------------------------------------------------------+
//| Strategy: Round 12 Fable - SWEEP-1 the 10-year machine with six entry gates and flow checks
//+------------------------------------------------------------------+
class CRound12Fable : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R12FABLE_SWEEP1_MACHINE";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round12-claude-fable-5-high-reasoning.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 2;
      cfg.minSecondsBetweenTrades = 300;
      cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 30;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;
      cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 30.0;
      cfg.breakEvenAtR          = 1.00;
      cfg.breakEvenOnBarClose   = true;    // doc: BE only after a completed bar close
      cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 1.00;
      cfg.pendingExpiryMinutes  = 15;    // cancel the limit if unfilled in 15 minutes
      cfg.useLimitEntry         = true;
      cfg.timeStopMinutes       = 240;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      int fromMin, toMin, sessFrom, sessTo;
      if(!SessionMap(ctx, fromMin, toMin, sessFrom, sessTo)) return false;
      if(ctx.clockMinutes >= InpThinHourFrom && ctx.clockMinutes < InpThinHourTo) return false;
      if(!RangeGate(ctx, fromMin, toMin)) return false;
      if(!FlowGate(ctx)) return false;

      SSweepParams p;
      p.Reset();
      p.rangeFromMin = fromMin; p.rangeToMin = toMin;
      p.sessionFromMin = sessFrom; p.sessionToMin = sessTo;
      p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
      p.reclaimWindowBars = 3;
      p.wickRatio = 0.60; p.bodyRatio = 0.60;
      p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
      p.entryRetrace = 0.50; p.targetR = 2.0;
      if(!SigSweepReclaim(ctx, p, plan)) return false;
      if(!BiasGate(ctx, plan.dir)) return false;
      plan.reason = "R12FABLE-SWEEP1 " + plan.reason;
      return true;
   }

   bool SessionMap(SEAContext &ctx, int &fromMin, int &toMin, int &sessFrom, int &sessTo)
   {
      if(ctx.clockMinutes < 6 * 60 + 30 && (StringFind(ctx.symbol, "AUDNZD") >= 0 ||
                                            StringFind(ctx.symbol, "EURGBP") >= 0))
      { fromMin = 21 * 60; toMin = 24 * 60; sessFrom = 0; sessTo = 6 * 60 + 30; return true; }
      if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 16 * 60 + 30 &&
         (StringFind(ctx.symbol, "EURUSD") >= 0 || StringFind(ctx.symbol, "GBPUSD") >= 0 ||
          StringFind(ctx.symbol, "XAU") >= 0))
      { fromMin = 0; toMin = 7 * 60; sessFrom = 7 * 60; sessTo = 16 * 60 + 30; return true; }
      if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 20 * 60 + 30 &&
         (StringFind(ctx.symbol, "XAU") >= 0 || StringFind(ctx.symbol, "USDJPY") >= 0))
      { fromMin = 7 * 60; toMin = 13 * 60; sessFrom = 13 * 60 + 30; sessTo = 20 * 60 + 30; return true; }
      return false;
   }

   bool RangeGate(SEAContext &ctx, const int fromMin, const int toMin)
   {
      double hi = 0.0, lo = 0.0;
      if(!RangeBetween(ctx.symbol, fromMin, toMin, hi, lo)) return false;
      double median = MedianRange(ctx.symbol);
      if(median <= 0.0) return false;
      double ratio = (hi - lo) / median;
      return (ratio >= InpRangeLowPct / 100.0 && ratio <= InpRangeHighPct / 100.0);
   }

   double MedianRange(const string sym)
   {
      MqlRates d[];
      if(EA_Rates(sym, PERIOD_D1, 1, 20, d) < 10) return 0.0;
      double s[];
      ArrayResize(s, 20);
      for(int i = 0; i < 20; i++) s[i] = d[i].high - d[i].low;
      ArraySort(s);
      return s[10];
   }

   bool RangeBetween(const string sym, const int fromMin, const int toMin, double &hi, double &lo)
   {
      MqlRates r[];
      if(EA_Rates(sym, PERIOD_M15, 1, 400, r) < 30) return false;
      bool wrap = (fromMin > toMin);
      int i = 0;
      for(; i < 400; i++)
      {
         MqlDateTime t;
         TimeToStruct(r[i].time, t);
         int m = t.hour * 60 + t.min;
         bool inWin = wrap ? (m >= fromMin || m < toMin) : (m >= fromMin && m < toMin);
         if(inWin) break;
      }
      if(i >= 400) return false;
      hi = 0.0; lo = 0.0;
      bool found = false;
      for(; i < 400; i++)
      {
         MqlDateTime t;
         TimeToStruct(r[i].time, t);
         int m = t.hour * 60 + t.min;
         bool inWin = wrap ? (m >= fromMin || m < toMin) : (m >= fromMin && m < toMin);
         if(!inWin) break;
         if(!found) { hi = r[i].high; lo = r[i].low; found = true; }
         else { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }
      }
      return found;
   }

   //--- cost/flow gate: spread vs 20-day average, sweep volume vs 20-candle average
   bool FlowGate(SEAContext &ctx)
   {
      PushSpread(ctx.spreadPoints);
      double avgSpread = AverageSpread();
      if(avgSpread > 0.0 && ctx.spreadPoints > InpSpreadAvgX * avgSpread) return false;
      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M5, 1, 22, r) < 21) return false;
      double vsum = 0.0;
      for(int i = 1; i <= 20; i++) vsum += (double)r[i].tick_volume;
      double vavg = vsum / 20.0;
      return (vavg <= 0.0 || r[0].tick_volume >= InpSweepVolumeX * vavg);
   }

   double m_spreads[120];
   int    m_spreadCount;

   void PushSpread(const double sp)
   {
      if(sp <= 0.0) return;
      if(m_spreadCount < 120) { m_spreads[m_spreadCount++] = sp; return; }
      for(int i = 0; i < 119; i++) m_spreads[i] = m_spreads[i + 1];
      m_spreads[119] = sp;
   }

   double AverageSpread()
   {
      if(m_spreadCount < 30) return 0.0;
      double sum = 0.0;
      for(int i = 0; i < m_spreadCount; i++) sum += m_spreads[i];
      return sum / m_spreadCount;
   }

   //--- bias gate (waived for the Asian mean-reversion cross pairs with ADX < 16)
   bool BiasGate(SEAContext &ctx, const int dir)
   {
      bool asianPair = (StringFind(ctx.symbol, "AUDNZD") >= 0 || StringFind(ctx.symbol, "EURGBP") >= 0);
      if(asianPair && ctx.adxH1 < 16.0) return true;                      // H1 ADX waiver (doc)
      if(ctx.emaH1_50 <= 0.0) return false;
      return (dir > 0) ? (ctx.mid > ctx.emaH1_50 && ctx.ema50 >= ctx.emaH1_50)
                       : (ctx.mid < ctx.emaH1_50 && ctx.ema50 <= ctx.emaH1_50);
   }
};

CRound12Fable g_Round12Fable;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round12Fable);
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
