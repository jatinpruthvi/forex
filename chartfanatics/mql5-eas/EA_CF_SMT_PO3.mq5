//+------------------------------------------------------------------+
//|                                            EA_CF_SMT_PO3.mq5     |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| ChartFanatics playbook: SMT Divergence + PO3 (Trader Kane)       |
//| Card    : chartfanatics/todos/smt-divergence-po3.md  (#23)       |
//| Source  : chartfanatics/pdf/smt-divergence-po3.pdf               |
//| Magic   : 3203                                                   |
//|                                                                  |
//| Top-down PO3 reversal into the 50% level of the dealing range:    |
//|   1. Daily marks the range and its 50% level; price must trade    |
//|      into premium (above 50%) for shorts or discount (below 50%)  |
//|      for longs.                                                   |
//|   2. H4/H1 show accumulation -> manipulation -> distribution.     |
//|   3. At the key time (about 10:00 New York) a prior high/low is   |
//|      swept.                                                       |
//|   4. SMT divergence confirms the manipulation is ending: the      |
//|      traded index makes a new extreme while its correlated twin   |
//|      (NQ vs ES) does not.                                         |
//|   5. Entry on the reversal, stop above/below the SMT extreme,     |
//|      target = the 50% level of the range (a base hit, no runner). |
//|                                                                  |
//| The shared engine's own SMT check (E1_SMC_Core) is an RSI proxy   |
//| on DXY and goes inert without that symbol. `SmtDivergence()` here |
//| compares the traded symbol with `InpSmtSymbol` directly, which is |
//| what the playbook describes (NQ making a new high while ES does   |
//| not, and vice versa).                                             |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics SMT Divergence + PO3 - correlated-pair divergence at the sweep, target the 50% level"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade   = "US100";              // The NQ side of the pair
input ulong             InpMagicNumber      = 3203;                 // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct          = 0.50;                 // Risk per trade (% of equity)
input double            InpMaxSpreadPoints  = 3.0;                  // Spread gate in points (0 = off)
input double            InpDailyLossPct     = 1.50;                 // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset  = 2;                    // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;        // Log verbosity
//--- the pair
input string InpSmtSymbol       = "US500"; // Correlated twin (the ES side of NQ vs ES)
input bool   InpRequireSmt      = true;    // The divergence is the model's confirmation
input bool   InpSmtFailClosed   = false;   // true = no reference symbol -> no entries
input int    InpSmtLookbackBars = 30;      // Bars compared on both symbols (signal TF)
input int    InpSmtRecentBars   = 6;       // The "fresh extreme" window inside that lookback
input double InpSmtTolAtr       = 0.10;    // Tolerance so ticks/thin prints do not fake a divergence
//--- PO3 structure (London clock; New York = London - 5)
input int    InpRangeFromMin     = 0;      // Accumulation window start (Asian session)
input int    InpRangeToMin       = 420;    // Accumulation window end (07:00 London)
input int    InpSessionFromMin   = 870;    // Entry window start (14:30 London = 09:30 ET)
input int    InpSessionToMin     = 960;    // Entry window end   (16:00 London = 11:00 ET)
input bool   InpHalfLevelGate    = true;   // Premium/discount gate around the previous day's 50%
input int    InpReclaimWindowBars= 3;
input double InpSweepMinAtr      = 0.05;
input double InpSweepMaxAtr      = 1.20;
input double InpEntryRetrace     = 0.50;   // Limit at 50% of the displacement body
input double InpStopBufferAtr    = 0.10;
input double InpMinStopAtr       = 0.20;
input double InpMaxStopAtr       = 2.50;
input double InpMinRR            = 1.50;   // Reject when the 50% level is closer than this

//+------------------------------------------------------------------+
//| Strategy class                                                   |
//+------------------------------------------------------------------+
class CCfSmtPo3 : public CEAStrategy
{
public:
   void OnInitStrategy()
   {
      m_warnedSmt = false;
   }

   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_SMT_PO3";
      cfg.sourceDoc             = "chartfanatics/pdf/smt-divergence-po3.pdf (card #23)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = 3.0;
      cfg.totalDdPct            = 8.0;
      cfg.maxTradesPerDay       = 2;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 180;
      cfg.useHwmThrottle        = true;
      cfg.hwmTier1Dd            = 2.0;  cfg.hwmTier1Mult = 0.50;
      cfg.hwmTier2Dd            = 4.0;  cfg.hwmTier2Mult = 0.25;
      cfg.hwmHaltDd             = 6.0;
      cfg.sessionStartHour      = 14;  cfg.sessionStartMin = 30;
      cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
      cfg.noTradeAfterHour      = 16;  cfg.noTradeAfterMin = 30;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 19;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = true;
      cfg.pendingExpiryMinutes  = 20;
      cfg.breakEvenAtR          = 1.0;    // the playbook moves to BE once the 11:00 candle flips
      cfg.partial1AtR           = 1.0;  cfg.partial1Pct = 50.0;
      cfg.trailAtR              = 0.0;    // base hits only: no runner management
      cfg.newsFilter            = false;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession) return false;
      if(ctx.atr <= 0.0) return false;

      //--- the daily dealing range and its 50% level
      double pdHi = 0.0, pdLo = 0.0;
      int bars = 0;
      if(!SigRangeForDay(ctx.symbol, g_eaIndTf, 0, 1440, 1, pdHi, pdLo, bars)) return false;
      if(pdHi <= pdLo) return false;
      double half = 0.5 * (pdHi + pdLo);

      SSweepParams p;
      p.Reset();
      p.rangeFromMin        = InpRangeFromMin;
      p.rangeToMin          = InpRangeToMin;
      p.sessionFromMin      = InpSessionFromMin;
      p.sessionToMin        = InpSessionToMin;
      p.sweepMinAtr         = InpSweepMinAtr;
      p.sweepMaxAtr         = InpSweepMaxAtr;
      p.reclaimWindowBars   = InpReclaimWindowBars;
      p.wickRatio           = 0.50;
      p.bodyRatio           = 0.55;
      p.stopBufferAtr       = InpStopBufferAtr;
      p.minStopAtr          = InpMinStopAtr;
      p.maxStopAtr          = InpMaxStopAtr;
      p.targetR             = InpMinRR;
      p.entryRetrace        = InpEntryRetrace;
      p.requireDisplacement = true;
      p.tradeBothWays       = true;
      p.scoreBase           = 60.0;
      if(!SigSweepReclaim(ctx, p, plan)) return false;

      //--- premium / discount around the 50% level
      if(InpHalfLevelGate)
      {
         if(plan.dir < 0 && ctx.mid < half)
         {
            plan.Reset();
            return false;
         }
         if(plan.dir > 0 && ctx.mid > half)
         {
            plan.Reset();
            return false;
         }
      }

      //--- SMT divergence between the traded index and its twin
      if(!SmtDivergence(ctx, plan.dir))
      {
         plan.Reset();
         return false;
      }

      //--- the model is a base hit: target the 50% level of the dealing range
      double rr = MathAbs(plan.entry - half) / plan.riskDist;
      if(rr < InpMinRR)
      {
         plan.Reset();
         return false;
      }
      plan.target = half;
      plan.score  = plan.score + MathMin(20.0, rr * 5.0);
      plan.reason = StringFormat("SMT+PO3 reversal into the 50%% level (%.2fR): ", rr) + plan.reason;
      return true;
   }

private:
   bool m_warnedSmt;

   //--- our symbol made a fresh extreme while the correlated twin did not
   bool SmtDivergence(SEAContext &ctx, const int dir)
   {
      if(!InpRequireSmt) return true;
      if(StringLen(InpSmtSymbol) == 0) return true;

      MqlRates a[], b[];
      int want = InpSmtLookbackBars;
      int gotA = EA_Rates(ctx.symbol, g_eaIndTf, 1, want, a);
      int gotB = EA_Rates(InpSmtSymbol, g_eaIndTf, 1, want, b);
      if(gotA < want || gotB < want)
      {
         if(!m_warnedSmt)
         {
            m_warnedSmt = true;
            if(InpSmtFailClosed)
               EA_Log(EA_LOG_ERRORS, "SMT reference '" + InpSmtSymbol + "' unavailable - no entries (fail closed)", true);
            else
               EA_Log(EA_LOG_ERRORS, "SMT reference '" + InpSmtSymbol + "' unavailable - SMT gate skipped (fail open)", true);
         }
         return (!InpSmtFailClosed);
      }

      int recent = InpSmtRecentBars;
      if(recent < 1) recent = 1;
      if(recent > want - 1) recent = want - 1;

      double aHiR = -DBL_MAX, aLoR = DBL_MAX, aHiO = -DBL_MAX, aLoO = DBL_MAX;
      double bHiR = -DBL_MAX, bLoR = DBL_MAX, bHiO = -DBL_MAX, bLoO = DBL_MAX;
      for(int i = 0; i < want; i++)
      {
         if(i < recent)
         {
            if(a[i].high > aHiR) aHiR = a[i].high;
            if(a[i].low  < aLoR) aLoR = a[i].low;
            if(b[i].high > bHiR) bHiR = b[i].high;
            if(b[i].low  < bLoR) bLoR = b[i].low;
         }
         else
         {
            if(a[i].high > aHiO) aHiO = a[i].high;
            if(a[i].low  < aLoO) aLoO = a[i].low;
            if(b[i].high > bHiO) bHiO = b[i].high;
            if(b[i].low  < bLoO) bLoO = b[i].low;
         }
      }

      double tol = InpSmtTolAtr * ctx.atr;
      if(dir < 0)
      {
         bool oursNewHigh   = (aHiR > aHiO + tol);
         bool twinNoNewHigh = (bHiR <= bHiO + tol);
         return (oursNewHigh && twinNoNewHigh);
      }
      bool oursNewLow   = (aLoR < aLoO - tol);
      bool twinNoNewLow = (bLoR >= bLoO - tol);
      return (oursNewLow && twinNoNewLow);
   }
};

CCfSmtPo3 g_cfSmtPo3;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfSmtPo3);
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
