//+------------------------------------------------------------------+
//| EA_studyarena_round10_claude_opus_5_high_reasoning.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 10 Opus - LSR-A cost-gated micro-swing state machine with correlation cap
//| Source document : docs/research/study_arena/studyarena-round10-claude-opus-5-high-reasoning.md
//| Tracker entry   : #64  |  Magic: 2031
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound10Opus class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 10 Opus - LSR-A cost-gated micro-swing state machine with correlation cap"
#property description "Source: docs/research/study_arena/studyarena-round10-claude-opus-5-high-reasoning.md"

#include "..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY,AUDUSD,USDCAD";      // Comma separated universe
input double          InpRiskPct          = 1.0;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 0;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 20;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 4;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2031; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpAtrBandLow        = 0.70;  // ATR(14) >= 0.7x its 20-day median
input double InpAtrBandHigh       = 1.80;  // ATR(14) <= 1.8x its 20-day median
input double InpSpreadMedianX     = 1.50;  // Live spread <= 1.5x the median
input double InpMinCostMultiple   = 10.0;  // Stop must be >= 10x round-trip cost
input double InpCorrelationCap    = 0.70;  // |rho_60d| cap between open symbols

//+------------------------------------------------------------------+
//| Strategy: Round 10 Opus - LSR-A cost-gated micro-swing state machine with correlation cap
//+------------------------------------------------------------------+
class CRound10Opus : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R10OPUS_LSRA";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round10-claude-opus-5-high-reasoning.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M15;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 2;
      cfg.minSecondsBetweenTrades = 600;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 20;  cfg.sessionEndMin   = 0;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      //--- 40% at +1R, 30% at +2R, 30% runner at 2.5 x H1 ATR recalculated hourly
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;
      cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 30.0;
      cfg.breakEvenAtR          = 1.00;
      cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 1.00;
      cfg.timeStopMinutes       = 240;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      if(!VolatilityRegimeOk(ctx)) return false;
      if(!SpreadOk(ctx)) return false;
      if(!CorrelationOk(ctx)) return false;

      SSweepParams p;
      p.Reset();
      p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
      p.sessionFromMin = 7 * 60; p.sessionToMin = 16 * 60;
      p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
      p.reclaimWindowBars = 3;
      p.wickRatio = 0.55; p.bodyRatio = 0.60;
      p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
      p.entryRetrace = 0.50; p.targetR = 2.0;
      if(!SigSweepReclaim(ctx, p, plan)) return false;

      //--- non-negotiable cost gate: stop >= 10x round-trip cost
      double cost = ctx.spreadPoints * ctx.point + 2.0 * SanityCommission(ctx.symbol);
      if(cost > 0.0 && plan.riskDist < InpMinCostMultiple * cost) return false;
      plan.reason = "R10OPUS-LSRA " + plan.reason;
      return true;
   }

   bool VolatilityRegimeOk(SEAContext &ctx)
   {
      double av[];
      if(EA_BufN(g_eaInd[ctx.index].hAtr, 0, 1, 2880, av) < 100) return true;   // ~20 days of M15
      double s[];
      ArrayResize(s, ArraySize(av));
      ArrayCopy(s, av);
      ArraySort(s);
      double median = s[ArraySize(s) / 2];
      if(median <= 0.0) return true;
      double ratio = ctx.atr / median;
      return (ratio >= InpAtrBandLow && ratio <= InpAtrBandHigh);
   }

   bool SpreadOk(SEAContext &ctx)
   {
      PushSpread(ctx.spreadPoints);
      double med = MedianSpread();
      if(med <= 0.0) return true;
      return (ctx.spreadPoints <= InpSpreadMedianX * med);
   }

   double m_spreads[96];
   int    m_spreadCount;

   void PushSpread(const double sp)
   {
      if(sp <= 0.0) return;
      if(m_spreadCount < 96) { m_spreads[m_spreadCount++] = sp; return; }
      for(int i = 0; i < 95; i++) m_spreads[i] = m_spreads[i + 1];
      m_spreads[95] = sp;
   }

   double MedianSpread()
   {
      if(m_spreadCount < 30) return 0.0;
      double s[];
      ArrayResize(s, m_spreadCount);
      for(int i = 0; i < m_spreadCount; i++) s[i] = m_spreads[i];
      ArraySort(s);
      return s[m_spreadCount / 2];
   }

   double SanityCommission(const string sym)
   {
      //--- conservative $7/round-trip-lot converted to price terms
      double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
      double point     = EA_Point(sym);
      if(tickValue <= 0.0 || tickSize <= 0.0 || point <= 0.0) return 0.0;
      double valuePerPointPerLot = tickValue * (point / tickSize);
      if(valuePerPointPerLot <= 0.0) return 0.0;
      return 7.0 / valuePerPointPerLot * point;
   }

   bool CorrelationOk(SEAContext &ctx)
   {
      if(EA_CountPositions("", false) == 0) return true;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         string other = PositionGetString(POSITION_SYMBOL);
         if(other == ctx.symbol) continue;
         double rho = Correlation(ctx.symbol, other, 60);
         if(MathAbs(rho) > InpCorrelationCap) return false;
      }
      return true;
   }

   double Correlation(const string a, const string b, const int bars)
   {
      MqlRates ra[], rb[];
      if(EA_Rates(a, PERIOD_H1, 1, bars, ra) < bars) return 0.0;
      if(EA_Rates(b, PERIOD_H1, 1, bars, rb) < bars) return 0.0;
      double ma = 0.0, mb = 0.0;
      double x[], y[];
      ArrayResize(x, bars); ArrayResize(y, bars);
      for(int i = 0; i < bars; i++)
      {
         x[i] = ra[i].close / ra[bars - 1].close - 1.0;
         y[i] = rb[i].close / rb[bars - 1].close - 1.0;
         ma += x[i]; mb += y[i];
      }
      ma /= bars; mb /= bars;
      double cov = 0.0, va = 0.0, vb = 0.0;
      for(int i = 0; i < bars; i++)
      {
         cov += (x[i] - ma) * (y[i] - mb);
         va  += (x[i] - ma) * (x[i] - ma);
         vb  += (y[i] - mb) * (y[i] - mb);
      }
      if(va <= 0.0 || vb <= 0.0) return 0.0;
      return cov / MathSqrt(va * vb);
   }
};

CRound10Opus g_Round10Opus;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round10Opus);
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
