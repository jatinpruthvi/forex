//+------------------------------------------------------------------+
//| EA_studyarena_round10_qwen3_8_2_4t_a95b_high_reasoning.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 10 Qwen - SOS-3 stacker: three sessions, 45-minute kill switch, multi-account sizing
//| Source document : docs/research/study_arena/studyarena-round10-qwen3-8-2-4t-a95b-high-reasoning.md
//| Tracker entry   : #67  |  Magic: 2034
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound10Qwen class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 10 Qwen - SOS-3 stacker: three sessions, 45-minute kill switch, multi-account sizing"
#property description "Source: docs/research/study_arena/studyarena-round10-qwen3-8-2-4t-a95b-high-reasoning.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "AUDNZD,EURGBP,EURUSD,GBPUSD,XAUUSD,GBPJPY,USDJPY";      // Comma separated universe
input double          InpRiskPct          = 0.75;   // Base risk per trade (% of equity)
input int             InpMaxTradesPerDay  = 8;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2034; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input int    InpKillMinutes       = 45;    // 45-minute time stop on stale trades
input double InpStackBoostPct     = 0.25;  // Secondary (stacked) setup sizing boost
input double InpSpreadAvgX        = 1.50;  // Spread gate: current <= this x the time-of-day baseline
input double InpSweepVolumeX      = 1.20;  // Sweep-candle tick volume vs its 20-candle average

//+------------------------------------------------------------------+
//| Strategy: Round 10 Qwen - SOS-3 stacker: three sessions, 45-minute kill switch, multi-account sizing
//+------------------------------------------------------------------+
class CRound10Qwen : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R10QWEN_SOS3_ALGO";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round10-qwen3-8-2-4t-a95b-high-reasoning.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 3;
      cfg.minSecondsBetweenTrades = 120;
      cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 22;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;
      cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 30.0;
      cfg.breakEvenAtR          = 1.00;
      cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 1.00;
      cfg.timeStopMinutes       = InpKillMinutes;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- session-specific reference ranges
      //--- Step 6 gate: current spread <= 1.5x the symbol's own baseline
      double spRef = EA_SpreadBaseline(ctx.symbol, 30);
      if(spRef > 0.0 && ctx.spreadPoints > InpSpreadAvgX * spRef)
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.1f pts > %.2fx its baseline %.1f - skip (doc row %d)", ctx.symbol, ctx.spreadPoints, InpSpreadAvgX, spRef, 67), true);
         return false;
      }

      int fromMin = 21 * 60, toMin = 24 * 60, sessFrom = 0, sessTo = 6 * 60 + 30;
      if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 13 * 60)
      { fromMin = 0; toMin = 7 * 60; sessFrom = 7 * 60; sessTo = 12 * 60; }
      else if(ctx.clockMinutes >= 13 * 60)
      { fromMin = 7 * 60; toMin = 13 * 60; sessFrom = 13 * 60 + 30; sessTo = 21 * 60; }

      double hi = 0.0, lo = 0.0;
      if(!RangeBetween(ctx.symbol, fromMin, toMin, hi, lo)) return false;
      double median = MedianRange(ctx.symbol);
      if(median <= 0.0) return false;
      double ratio = (hi - lo) / median;
      if(ratio < 0.35 || ratio > 0.75) return false;             // manipulation bait vs spent fuel

      int tier = SessionTier(ctx);
      if(tier == 0) return false;

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
      if(!BiasAgrees(ctx, plan.dir)) return false;                // doc Step 2 (waived for Asian MR pairs)
      if(!VolumeConfirms(ctx, plan.sweepBarsAgo)) return false;   // doc Step 6: sweep participation
      m_tier = tier;
      plan.reason = StringFormat("R10QWEN-SOS3(tier %d) %s", tier, plan.reason);
      return true;
   }

   int m_tier;

   bool IsAsianPair(const string sym)
   {
      return (StringFind(sym, "AUDNZD") >= 0 || StringFind(sym, "EURGBP") >= 0);
   }

   //--- doc Step 2: H1 50-EMA slope + price side; Asian mean-reversion pairs
   //--- are exempt while H1 ADX(14) < 16 (pure mean reversion), per the document
   bool BiasAgrees(SEAContext &ctx, const int dir)
   {
      if(IsAsianPair(ctx.symbol) && ctx.clockMinutes < 7 * 60 && ctx.adxH1 < 16.0) return true;
      if(ctx.emaH1_50 <= 0.0) return false;
      double h1Atr = (ctx.atrD1 > 0.0) ? ctx.atrD1 / 6.0 : 0.0;
      if(h1Atr <= 0.0) return false;
      double slope = ctx.emaH1_50 - ctx.emaH1_200;
      if(dir > 0) return (ctx.mid > ctx.emaH1_50 && slope >= -0.05 * h1Atr);
      return (ctx.mid < ctx.emaH1_50 && slope <= 0.05 * h1Atr);
   }

   //--- doc Step 6: the sweep candle's tick volume must be >= 1.2x the 20-candle average
   bool VolumeConfirms(SEAContext &ctx, const int sweepBar)
   {
      if(sweepBar < 1) return true;                            // no sweep bar recorded - fail open
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, sweepBar + 21, r);
      if(got < sweepBar + 21) return true;                     // thin data - fail open
      double sum = 0.0;
      for(int i = sweepBar + 1; i <= sweepBar + 20; i++) sum += (double)r[i].tick_volume;
      double avg = sum / 20.0;
      if(avg <= 0.0) return true;
      return ((double)r[sweepBar].tick_volume >= InpSweepVolumeX * avg);
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

   //--- range of the most recent completed session between two clock minutes
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

   //--- 1 = primary session pair, 2 = secondary stacking pair, 0 = skip
   int SessionTier(SEAContext &ctx)
   {
      bool asian = (ctx.clockMinutes < 7 * 60);
      bool london = (ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 13 * 60);
      if(asian)     return IsAsianPair(ctx.symbol) ? 1 : 0;
      if(london)
      {
         if(StringFind(ctx.symbol, "EURUSD") >= 0 || StringFind(ctx.symbol, "GBPUSD") >= 0 ||
            StringFind(ctx.symbol, "XAU") >= 0) return 1;
         if(StringFind(ctx.symbol, "GBPJPY") >= 0 || StringFind(ctx.symbol, "GER") >= 0) return 2;
         return 0;
      }
      if(StringFind(ctx.symbol, "XAU") >= 0 || StringFind(ctx.symbol, "USDJPY") >= 0) return 1;
      if(StringFind(ctx.symbol, "US30") >= 0 || StringFind(ctx.symbol, "NAS") >= 0) return 2;
      return 0;
   }

   //--- stacked (secondary) setups get a small sizing boost, never a martingale
   double LotsMultiplier(SEAContext &ctx)
   {
      if(ctx.riskPct <= 0.0) return 0.0;
      double risk = InpRiskPct + ((m_tier == 2) ? InpStackBoostPct : 0.0);
      return MathMax(0.0, risk / ctx.riskPct);
   }
};

CRound10Qwen g_Round10Qwen;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round10Qwen);
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
