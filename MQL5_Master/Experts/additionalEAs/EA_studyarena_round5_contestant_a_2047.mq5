//+------------------------------------------------------------------+
//| EA_studyarena_round5_contestant_a_2047.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 5A-2047 - percentile-gated London sweep with the full checklist and 40/40/20 ladder
//| Source document : docs/research/study_arena/studyarena-round5-contestant-a.md
//| Tracker entry   : #48  |  Magic: 2047
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound5A2 class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 5A-2047 - percentile-gated London sweep with the full checklist and 40/40/20 ladder"
#property description "Source: docs/research/study_arena/studyarena-round5-contestant-a.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD";      // Comma separated universe
input double          InpRiskPct          = 1.0;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 0;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 20;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 3;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2047; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpPctLow            = 20.0;  // Asian range percentile floor
input double InpPctHigh           = 65.0;  // Asian range percentile ceiling
input double InpSpreadTol         = 1.50;  // Spread must be <= 1.5x its normal
input int    InpLondonFlatMin     = 12 * 60;  // Close anything left by 12:00 London
input double InpStopMaxAdr        = 0.35;  // Skip if the stop > 0.35 x ADR20

//+------------------------------------------------------------------+
//| Strategy: Round 5A-2047 - percentile-gated London sweep with the full checklist and 40/40/20 ladder
//+------------------------------------------------------------------+
class CRound5A2 : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R5A2_PERCENTILE_SWEEP";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round5-contestant-a.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 900;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 12;  cfg.sessionEndMin   = 0;   // flat by 12:00 London
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;
      cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 40.0;   // 40/40, runner trails
      cfg.breakEvenAtR          = 1.00;
      cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 0.50;
      cfg.timeStopMinutes       = 0;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      if(ctx.clockMinutes < 7 * 60 || ctx.clockMinutes >= InpLondonFlatMin) return false;
      if(SymbolRank(ctx) <= 0) return false;               // EURUSD preferred over GBPUSD
      if(!GatePass(ctx)) return false;

      SSweepParams p;
      p.Reset();
      p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
      p.sessionFromMin = 7 * 60; p.sessionToMin = 10 * 60 + 30;
      p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.50;
      p.reclaimWindowBars = 3; p.wickRatio = 0.55; p.bodyRatio = 0.55;
      p.stopBufferAtr = 0.10; p.minStopAtr = 0.50; p.maxStopAtr = 1.50;
      p.entryRetrace = 0.50; p.targetR = 2.0;
      if(!SigSweepReclaim(ctx, p, plan)) return false;

      //--- skip if the structural stop exceeds 0.35 x ADR20
      double adr = ctx.atrD1 * 4.0;
      if(adr > 0.0 && plan.riskDist > InpStopMaxAdr * adr) return false;
      plan.reason = "R5A2-LONDONSWEEP " + plan.reason;
      return true;
   }

   //--- full gate: percentile band + ADR cap + spread normalization
   bool GatePass(SEAContext &ctx)
   {
      double hi = 0.0, lo = 0.0;
      if(!SigAsianRange(ctx.symbol, hi, lo)) return false;
      double pct = AsiaRangePercentile(ctx.symbol, hi - lo);
      if(pct < InpPctLow || pct > InpPctHigh) return false;
      double adr = ctx.atrD1 * 4.0;
      if(adr > 0.0)
      {
         MqlRates d[];
         if(EA_Rates(ctx.symbol, PERIOD_D1, 0, 1, d) >= 1 && (d[0].high - d[0].low) > 0.70 * adr)
            return false;
      }
      PushSpread(ctx.spreadPoints);
      double med = MedianSpread();
      if(med > 0.0 && ctx.spreadPoints > InpSpreadTol * med) return false;
      return true;
   }

   double m_spreads[64];
   int    m_spreadCount;

   void PushSpread(const double sp)
   {
      if(sp <= 0.0) return;
      if(m_spreadCount < 64) { m_spreads[m_spreadCount++] = sp; return; }
      for(int i = 0; i < 63; i++) m_spreads[i] = m_spreads[i + 1];
      m_spreads[63] = sp;
   }

   double MedianSpread()
   {
      if(m_spreadCount < 20) return 0.0;
      double s[];
      ArrayResize(s, m_spreadCount);
      for(int i = 0; i < m_spreadCount; i++) s[i] = m_spreads[i];
      ArraySort(s);
      return s[m_spreadCount / 2];
   }

   double AsiaRangePercentile(const string sym, const double todayRange)
   {
      MqlRates d[];
      if(EA_Rates(sym, PERIOD_D1, 1, 60, d) < 30) return 50.0;
      int below = 0, n = 0;
      for(int i = 0; i < 60; i++)
      {
         double r = d[i].high - d[i].low;
         if(r <= 0.0) continue;
         n++;
         if(todayRange >= r) below++;
      }
      return (n > 0) ? 100.0 * below / (double)n : 50.0;
   }

   //--- ranking table: H1+H4 trend agreement, sweep at prior-day extreme, cost
   double SymbolRank(SEAContext &ctx)
   {
      double rank = 1.0;
      if(StringFind(ctx.symbol, "EURUSD") >= 0) rank += 1.0;      // lower transaction cost
      if(ctx.emaH1_50 > 0.0 && ctx.emaD1_200 > 0.0)
      {
         bool h1Up = (ctx.mid > ctx.emaH1_50), h4Up = (ctx.mid > ctx.emaD1_200);
         if(h1Up == h4Up) rank += 2.0;
      }
      MqlRates d[];
      if(EA_Rates(ctx.symbol, PERIOD_D1, 1, 1, d) >= 1)
      {
         double tol = 0.25 * ctx.atr * 4.0;
         if(MathAbs(ctx.mid - d[0].high) < tol || MathAbs(ctx.mid - d[0].low) < tol) rank += 2.0;
      }
      return rank;
   }
};

CRound5A2 g_Round5A2;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round5A2);
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
