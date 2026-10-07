//+------------------------------------------------------------------+
//|                                          EA_CF_PO3_OTE_ADR.mq5   |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| ChartFanatics playbook: PO3, OTE & ADR (NBB Trader, Apr 2025)    |
//| Card    : chartfanatics/todos/po3-ote-adr.md  (#22)              |
//| Source  : chartfanatics/pdf/po3-ote-adr.pdf                      |
//| Magic   : 3204                                                   |
//|                                                                  |
//| Market Maker Model + fib-anchored Optimal Trade Entry:            |
//|   1. Daily bias is set BEFORE the session; the model never        |
//|      trades both ways.                                            |
//|   2. The setup must occur next to a PD array (previous day high   |
//|      or low) - price has to OPEN close to the level, otherwise    |
//|      the day is skipped.                                          |
//|   3. Accumulation (tight Asian range), then manipulation: the     |
//|      London/NY raid takes out the PD array and prints the high    |
//|      (or low) of the day.                                         |
//|   4. Confirmation: a strong body candle closes back through the   |
//|      level on M15/M30 - never the 1-minute chart.                 |
//|   5. Fib high->low of that leg: entry LIMIT in the 0.62-0.705     |
//|      retracement zone, stop at the 1.0 fib (the manipulation       |
//|      extreme), target at the 0.0 fib (the leg end), which is why  |
//|      the R multiple is fixed by geometry: 0.62 -> 1.63R,          |
//|      0.705 -> 2.39R, 0.79 -> 3.76R.                               |
//|   6. Management: stop to break-even once price closes past the    |
//|      0.20 fib (the default 1.70R tracks the 0.705 entry).         |
//|                                                                  |
//| NOT encoded: the ADR filter below uses daily ATR as the average-  |
//| range proxy; the playbook's scale-in rule (only when the first    |
//| entry is at break-even or better) is off by default because the   |
//| engine holds one position per symbol - see the card's Notes.       |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics PO3 + OTE + ADR - fib-anchored limit entry after a PD-array raid"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade   = "XAUUSD,US100,US500,EURUSD";  // Universe (playbook: forex / indices)
input ulong             InpMagicNumber      = 3204;                 // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct          = 0.50;                 // Risk per trade (% of equity)
input double            InpMaxSpreadPoints  = 3.0;                  // Spread gate in points (0 = off)
input double            InpDailyLossPct     = 1.50;                 // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset  = 2;                    // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;        // Log verbosity
//--- bias and key levels
input double InpBiasBandAtr     = 0.15;   // |price - D1 200EMA| must exceed this to call a bias
input double InpKeyLevelTolAtr  = 0.25;   // Price must open within this distance of the PD array
input double InpAdrConsumedMax  = 0.60;   // Skip when the day already used this share of daily ATR
//--- sessions (London clock; New York = London - 5)
input int InpLondonOpenFromMin  = 420;    // 07:00 London = 02:00 ET
input int InpLondonOpenToMin    = 600;    // 10:00 London = 05:00 ET
input int InpNyOpenFromMin      = 720;    // 12:00 London = 07:00 ET
input int InpNyOpenToMin        = 900;    // 15:00 London = 10:00 ET
input int InpLondonCloseFromMin = 900;    // 15:00 London = 10:00 ET
input int InpLondonCloseToMin   = 1020;   // 17:00 London = 12:00 ET
input bool InpUseLondonClose    = true;   // The third session works best after an earlier move
//--- the leg and the fib
input int    InpManipBars         = 16;    // Bars searched for the manipulation extreme
input double InpDisplacementBody  = 0.55;  // Confirmation candle body ratio
input double InpOteFib            = 0.705; // Limit level inside the 0.62-0.705 zone
input double InpMinRR            = 2.00;   // Reject entries whose fixed geometry is under 2R
input double InpStopBufferAtr    = 0.15;
input int    InpPendingExpiryMinutes = 45; // How long the OTE limit may rest

//+------------------------------------------------------------------+
//| Strategy class                                                   |
//+------------------------------------------------------------------+
class CCfPo3OteAdr : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_PO3_OTE_ADR";
      cfg.sourceDoc             = "chartfanatics/pdf/po3-ote-adr.pdf (card #22)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M15;   // "use the 15-minute or 30-minute chart"
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = 3.0;
      cfg.totalDdPct            = 8.0;
      cfg.maxTradesPerDay       = 2;
      cfg.dayLockAfterLosses    = 2;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 180;
      cfg.useHwmThrottle        = true;
      cfg.hwmTier1Dd            = 2.0;  cfg.hwmTier1Mult = 0.50;
      cfg.hwmTier2Dd            = 4.0;  cfg.hwmTier2Mult = 0.25;
      cfg.hwmHaltDd             = 6.0;
      cfg.sessionStartHour      = InpLondonOpenFromMin / 60;
      cfg.sessionStartMin       = InpLondonOpenFromMin % 60;
      cfg.sessionEndHour        = InpLondonCloseToMin / 60;
      cfg.sessionEndMin         = InpLondonCloseToMin % 60;
      cfg.noTradeAfterHour      = 17;  cfg.noTradeAfterMin = 0;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 19;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = true;    // the OTE zone is a resting limit, never a chase
      cfg.pendingExpiryMinutes  = InpPendingExpiryMinutes;
      cfg.breakEvenAtR          = 1.70;    // the 0.20 fib level, entered at 0.705
      cfg.partial1AtR           = 2.39;    // 0.0 fib is 2.39R from a 0.705 entry
      cfg.partial1Pct           = 60.0;
      cfg.trailAtR              = 2.39;    // "make the old TP the new stop loss"
      cfg.trailDistanceR        = 0.50;
      cfg.newsFilter            = false;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(ctx.atr <= 0.0 || ctx.atrD1 <= 0.0) return false;
      if(!InTradingBlock(ctx.clockMinutes)) return false;

      int bias = DailyBias(ctx);
      if(bias == 0) return false;                       // no bias, no trade

      double pdh = 0.0, pdl = 0.0;
      int bars = 0;
      if(!SigRangeForDay(ctx.symbol, g_eaIndTf, 0, 1440, 1, pdh, pdl, bars)) return false;
      if(!NearKeyLevel(ctx, bias, pdh, pdl)) return false;
      if(!AdrRoomLeft(ctx)) return false;

      MqlRates r[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, InpManipBars + 2, r);
      if(got < 8) return false;

      //--- 1. manipulation: the extreme of the raid (the future 1.0 fib)
      int    manipIdx     = -1;
      double manipExtreme = (bias < 0) ? -DBL_MAX : DBL_MAX;
      for(int i = 1; i <= InpManipBars && i < got; i++)
      {
         if(bias < 0 && r[i].high > manipExtreme)
         {
            manipExtreme = r[i].high;
            manipIdx     = i;
         }
         if(bias > 0 && r[i].low < manipExtreme)
         {
            manipExtreme = r[i].low;
            manipIdx     = i;
         }
      }
      if(manipIdx < 2) return false;
      double tol = InpKeyLevelTolAtr * ctx.atr;
      if(bias < 0 && manipExtreme < pdh - tol) return false;    // the raid missed the PD array
      if(bias > 0 && manipExtreme > pdl + tol) return false;

      //--- 2. displacement: a strong body bar NEWER than the raid that breaks structure back
      bool   displaced  = false;
      double legExtreme = (bias < 0) ? DBL_MAX : -DBL_MAX;
      for(int i = 1; i < manipIdx; i++)
      {
         if(EA_BodyRatio(r[i]) < InpDisplacementBody) continue;
         if(bias < 0 && r[i].close < r[i].open && r[i].close < r[i + 1].low)
         {
            displaced = true;
            if(r[i].low < legExtreme) legExtreme = r[i].low;
         }
         if(bias > 0 && r[i].close > r[i].open && r[i].close > r[i + 1].high)
         {
            displaced = true;
            if(r[i].high > legExtreme) legExtreme = r[i].high;
         }
      }
      if(!displaced) return false;

      //--- the leg runs to the newest closed bar
      double lastExtreme = (bias < 0) ? r[1].low : r[1].high;
      if(bias < 0 && lastExtreme < legExtreme) legExtreme = lastExtreme;
      if(bias > 0 && lastExtreme > legExtreme) legExtreme = lastExtreme;
      double span = MathAbs(manipExtreme - legExtreme);
      if(span <= 0.0) return false;

      //--- 3. the OTE limit: 0.62-0.705 retracement, stop at 1.0 fib, target at 0.0 fib
      double entry = (bias < 0) ? legExtreme + InpOteFib * span
                                : legExtreme - InpOteFib * span;
      double stop  = (bias < 0) ? manipExtreme + InpStopBufferAtr * ctx.atr
                                : manipExtreme - InpStopBufferAtr * ctx.atr;
      double risk  = MathAbs(entry - stop);
      if(risk <= 0.0) return false;
      double rr = MathAbs(legExtreme - entry) / risk;
      if(rr < InpMinRR) return false;
      if(bias < 0 && ctx.ask <= entry) return false;    // price already ran: no resting limit
      if(bias > 0 && ctx.bid >= entry) return false;

      plan.dir      = bias;
      plan.entry    = entry;
      plan.stop     = stop;
      plan.riskDist = risk;
      plan.target   = legExtreme;
      plan.isLimit  = true;
      plan.expiry   = TimeTradeServer() + (datetime)(InpPendingExpiryMinutes * 60);
      plan.barsAgo  = 1;
      plan.score    = 72.0;
      plan.reason   = StringFormat("PO3 fib-OTE at %.3f of the manipulation leg (%.2fR)", InpOteFib, rr);
      return true;
   }

private:
   int DailyBias(SEAContext &ctx)
   {
      if(ctx.emaD1_200 <= 0.0 || ctx.atrD1 <= 0.0) return 0;
      double distance = ctx.mid - ctx.emaD1_200;
      if(MathAbs(distance) < InpBiasBandAtr * ctx.atrD1) return 0;   // the daily is undecided
      return (distance > 0.0) ? +1 : -1;
   }

   bool NearKeyLevel(SEAContext &ctx, const int bias, const double pdh, const double pdl)
   {
      double tol = InpKeyLevelTolAtr * ctx.atr;
      if(bias < 0) return (MathAbs(ctx.mid - pdh) <= tol || MathAbs(ctx.mid - pdl) <= tol);
      return (MathAbs(ctx.mid - pdl) <= tol || MathAbs(ctx.mid - pdh) <= tol);
   }

   bool AdrRoomLeft(SEAContext &ctx)
   {
      double hi = 0.0, lo = 0.0;
      int bars = 0;
      if(!SigRangeForDay(ctx.symbol, g_eaIndTf, 0, 1440, 0, hi, lo, bars)) return true;  // unmeasurable -> allow
      if(ctx.atrD1 <= 0.0) return true;
      double used = (hi - lo) / ctx.atrD1;
      return (used <= InpAdrConsumedMax);
   }

   bool InTradingBlock(const int clockMinutes)
   {
      if(clockMinutes >= InpLondonOpenFromMin  && clockMinutes < InpLondonOpenToMin)  return true;
      if(clockMinutes >= InpNyOpenFromMin      && clockMinutes < InpNyOpenToMin)      return true;
      if(InpUseLondonClose && clockMinutes >= InpLondonCloseFromMin &&
         clockMinutes < InpLondonCloseToMin) return true;
      return false;
   }
};

CCfPo3OteAdr g_cfPo3OteAdr;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfPo3OteAdr);
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
