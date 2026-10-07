//+------------------------------------------------------------------+
//|                                    EA_CF_FirstRedDayPro.mq5      |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| ChartFanatics playbook: First Red Day (Kyle William)              |
//| Card    : chartfanatics/todos/first-red-day-strategy.md   (#11)   |
//| Source  : chartfanatics/pdf/first-red-day-strategy.pdf            |
//| Magic   : 3215                                                   |
//|                                                                  |
//| "The best signal that a stock is ready to go down is when it can   |
//|  no longer continue going up."                                     |
//|                                                                  |
//| The MINIMUM CRITERIA are non-negotiable in this playbook:          |
//|   * at least 2-3 consecutive green days                            |
//|   * 80-100%+ extension from the start of the run                    |
//|   * expanding daily volume                                          |
//|   * expanding daily range (acceleration)                            |
//| and the run must have no red days.  The previous day's close is the |
//| psychological trigger ("retail determines profit/loss versus the    |
//| prior close, not the open").                                        |
//|                                                                  |
//| Three entry methods, aggressive to conservative (selectable):       |
//|   PRE-RED        short a failure to make new highs BEFORE the break |
//|                  of the prior close; risk = the all-time high of    |
//|                  the run; best R:R, most stop-outs                  |
//|   STANDARD       short the crack below the prior close; risk =      |
//|                  today's high of day; add on failed bounces         |
//|   LOWER HIGH     wait for the breakdown, then the first bounce,     |
//|                  then short the failed lower high; highest win      |
//|                  rate, worst R:R                                    |
//|                                                                  |
//| Exits: VWAP is the primary magnet, cover into weakness without      |
//| waiting for the perfect bottom, scale out, and optionally trail     |
//| the stop under the 15-minute high.  The "overextended gap down"     |
//| variation is respected: after consecutive gap ups, never short      |
//| once price is already down InpMaxDownPct or more - wait for the     |
//| bounce to improve the R:R.  The MAXIMUM ATTEMPTS rule (3-5) is a    |
//| hard cap on daily entries.                                          |
//|                                                                  |
//| `[interpretation]`: single-stock selection (small-cap euphoria) is  |
//| the user's universe as in the other stock playbooks; VWAP is        |
//| computed from the session's M5 bars; the fallback target uses the   |
//| playbook's "larger assets: 2-3%" band where no VWAP magnet applies. |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics First Red Day (Kyle William) - pre-red, standard-break and lower-high entries into a parabolic exhaustion"

#include "..\..\Include\EACommon.mqh"

enum ENUM_CF_FRD_ENTRY
{
   CF_FRD_PRE_RED    = 0,   // Pre-red: failure to make new highs
   CF_FRD_STANDARD   = 1,   // Standard: crack below the prior close
   CF_FRD_LOWER_HIGH = 2    // Lower high: failed first bounce after the breakdown
};

//--- identity / risk
input string            InpSymbolsToTrade   = "US100,US500,GER40";  // Instrument selection is the user's universe
input ulong             InpMagicNumber      = 3215;                 // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct          = 0.50;                 // Risk per trade (% of equity)
input int               InpStage             = 5;                   // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input double            InpMaxSpreadPoints  = 3.0;                  // Spread gate in points (0 = off)
input double            InpDailyLossPct     = 1.50;                 // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset  = 2;                    // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;        // Log verbosity
input double            InpCommissionPerLotRT = 0.0;                // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.12;               // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;               // Write the engine evidence ledger CSV
//--- the minimum criteria (non-negotiable in the playbook)
input int    InpMinGreenDays   = 3;     // "minimum 2-3 consecutive green days"
input double InpMinExtensionPct= 80.0;  // "80-100%+ extension from the start of the run"
input bool   InpRequireExpandingVol  = true; // "expanding daily volume"
input bool   InpRequireExpandingRange= true; // "expanding daily range (acceleration)"
//--- entry method and its risk
input ENUM_CF_FRD_ENTRY InpEntryMethod = CF_FRD_STANDARD;  // Entry method (aggressive -> conservative)
input double InpMaxDownPct     = 10.0;  // "do not short if already down 10%+" (overextended gap down)
input double InpFadeBufferAtr  = 0.15;  // Buffer above the level the method risks (ATH / HOD / bounce high)
input double InpBounceMinAtr   = 0.30;  // A bounce must lift at least this far to count (lower-high method)
//--- exits
input bool   InpUseVwapTarget  = true;  // "VWAP is the primary magnet"
input double InpFallbackTgtPct = 2.5;   // "larger assets: 2-3%" - used when no VWAP magnet applies
input double InpPartial1AtR    = 1.0;   // "cover into weakness ... scale out"
input double InpPartial1Pct    = 50.0;
input bool   InpTrailM15High   = true;  // "optional: trail using 15-minute high"
input int    InpMaxAttempts    = 3;     // "hard rule: 3-5 attempts maximum"

//+------------------------------------------------------------------+
class CCfFirstRedDayPro : public CEAStrategy
{
public:
   void OnInitStrategy()
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("5-stage policy: stage %d active (risk %.3f%%, %d trades/day max)",
             InpStage, g_eaCfg.riskPct, g_eaCfg.maxTradesPerDay), true);
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "FRD armed: method %s, minimum criteria %d green days / %.0f%% extension, max %d attempts",
             MethodName(), InpMinGreenDays, InpMinExtensionPct, InpMaxAttempts), true);
   }

   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_FIRST_RED_DAY_PRO";
      cfg.sourceDoc             = "chartfanatics/pdf/first-red-day-strategy.pdf (card #11)";
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
      cfg.maxTradesPerDay       = InpMaxAttempts;   // "3-5 attempts maximum" - one input, capped by the stage policy
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 300;
      cfg.sessionStartHour      = 14;  cfg.sessionStartMin = 25;
      cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;
      cfg.noTradeAfterHour      = 20;  cfg.noTradeAfterMin = 0;   // "avoid entering new positions late in the day"
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = false;
      cfg.breakEvenAtR          = 1.0;
      cfg.partial1AtR           = InpPartial1AtR;  cfg.partial1Pct = InpPartial1Pct;
      cfg.trailAtR              = 0.0;               // the M15-high trail below is the playbook's own tool
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_frd_pro_ledger.csv";
      cfg.newsFilter            = false;
      cfg.logLevel              = InpLogLevel;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession || ctx.atr <= 0.0) return false;

      MqlRates d[];
      int need = InpMinGreenDays + 24;        // room to walk a long run back, not only the minimum
      int got  = EA_Rates(ctx.symbol, PERIOD_D1, 0, need, d);
      if(got < InpMinGreenDays + 2) return false;

      //--- the run: walk back from yesterday (d[1]) to the first non-green day.  "No red days
      //--- during the run" - the walk stops there, so a red day inside is impossible by construction.
      int runLen = 0;
      for(int i = 1; i < got - 1; i++)
      {
         if(d[i].close <= d[i].open) break;                       // a red day ends the run
         runLen++;
      }
      if(runLen < InpMinGreenDays) return false;                  // "minimum 2-3 consecutive green days"

      double runLow = d[1].low, runHigh = d[1].high;
      for(int i = 1; i <= runLen; i++)
      {
         runLow  = MathMin(runLow,  d[i].low);
         runHigh = MathMax(runHigh, d[i].high);
      }

      //--- "80-100%+ extension from the start of the run" (the open of the run's first green day)
      double start = d[runLen].open;
      if(start <= 0.0) return false;
      double extension = (runHigh - start) / start * 100.0;
      if(extension < InpMinExtensionPct) return false;

      //--- "expanding daily volume" and "expanding daily range (acceleration)"
      if(InpRequireExpandingVol && !(d[1].tick_volume > d[2].tick_volume && d[2].tick_volume >= d[3].tick_volume))
         return false;
      if(InpRequireExpandingRange)
      {
         double r1 = d[1].high - d[1].low, r2 = d[2].high - d[2].low, r3 = d[3].high - d[3].low;
         if(!(r1 > r2 && r2 >= r3)) return false;
      }

      double priorClose = d[1].close;                            // the psychological trigger

      //--- "the overextended gap down variation": after consecutive gap ups, never short once the
      //--- price is already down 10%+ - the bounce must improve the R:R first
      double downPct = (priorClose > 0.0) ? (priorClose - ctx.mid) / priorClose * 100.0 : 0.0;
      if(downPct >= InpMaxDownPct) return false;

      MqlRates m[];
      if(EA_Rates(ctx.symbol, g_eaIndTf, 0, 8, m) < 6) return false;
      //--- "risk: today's high of day" - the forming D1 bar carries the exact session high
      double hod = (d[0].high > 0.0) ? d[0].high : m[1].high;

      int    dir = 0;
      double stopLevel = 0.0;
      string why = "";

      if(InpEntryMethod == CF_FRD_PRE_RED)
      {
         //--- failure to make new highs while still above the prior close: the top is stalling
         if(!(ctx.mid > priorClose)) return false;               // pre-red means BEFORE the break
         if(!(m[1].high < runHigh - InpFadeBufferAtr * ctx.atr)) return false;
         if(!(m[1].close < m[1].open)) return false;
         dir = -1; stopLevel = runHigh; why = "pre-red stall (no new high)";     // "risk: all-time high of run"
      }
      else if(InpEntryMethod == CF_FRD_STANDARD)
      {
         //--- the crack below the prior close
         if(!(m[1].close < priorClose && m[1].close < m[1].open)) return false;
         dir = -1; stopLevel = hod; why = "standard break of the prior close";    // "risk: today's high of day"
      }
      else
      {
         //--- the breakdown, then a bounce, then the failed lower high
         bool broke = false;
         for(int i = 2; i <= 6 && i < 8; i++)
            if(m[i].close < priorClose) { broke = true; break; }
         if(!broke) return false;
         double bounceHigh = MathMax(m[2].high, m[3].high);
         if(bounceHigh < priorClose - InpBounceMinAtr * ctx.atr) return false;     // a real bounce, not noise
         if(!(m[1].high < bounceHigh && m[1].close < m[1].open)) return false;     // the lower high fails
         dir = -1; stopLevel = bounceHigh; why = "failed lower high after the breakdown";
      }
      if(dir == 0) return false;

      double entry = ctx.bid;
      double stop  = stopLevel + InpFadeBufferAtr * ctx.atr;
      double risk  = stop - entry;
      if(risk <= 0.0) return false;

      //--- the VWAP magnet, or the playbook's 2-3% fallback for larger assets
      double target = 0.0;
      double vwap = SessionVwap(ctx.symbol);
      if(InpUseVwapTarget && vwap > 0.0 && vwap < entry - risk) target = vwap;
      if(target <= 0.0) target = entry * (1.0 - InpFallbackTgtPct / 100.0);
      if(target >= entry - risk) target = entry - risk;         // never a sub-1R destination

      plan.dir = -1; plan.entry = entry; plan.stop = stop; plan.riskDist = risk;
      plan.target = target; plan.barsAgo = 1; plan.score = 72.0; plan.isLimit = false;
      plan.reason = StringFormat("%s (%.0f%% run, %d green days)", why, extension, InpMinGreenDays);
      return true;
   }

   //--- "optional: trail using 15-minute high" - the playbook's own trailing tool for this setup
   void Manage(SEAContext &ctx)
   {
      if(!InpTrailM15High) return;
      MqlRates q[];
      if(EA_Rates(ctx.symbol, PERIOD_M15, 0, 4, q) < 3) return;
      double m15High = q[1].high;                     // the last COMPLETED 15-minute high

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;
         if(PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_SELL) continue;

         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         if(ctx.mid >= entry) continue;                          // only once the trade is working
         //--- the trail must never loosen: it only ever moves the stop toward the market.  Do NOT
         //--- re-derive risk from the live SL - after the engine breaks even SL == entry, so a
         //--- risk-based gate silently disables this trail exactly when it should start working.
         double trail = m15High + InpFadeBufferAtr * ctx.atr;
         if(trail >= entry) continue;                             // never above the entry
         double cur = PositionGetDouble(POSITION_SL);
         if(cur > 0.0 && trail >= cur - SymbolInfoDouble(ctx.symbol, SYMBOL_TRADE_TICK_SIZE) * 0.5) continue;
         double tp = PositionGetDouble(POSITION_TP);
         if(g_eaExec.Modify(ticket, trail, tp))
            EA_Log(EA_LOG_EVENTS, StringFormat("FRD pro: stop trailed under the 15-minute high to %.2f", trail), true);
      }
   }

private:
   string MethodName()
   {
      if(InpEntryMethod == CF_FRD_PRE_RED)    return "pre-red";
      if(InpEntryMethod == CF_FRD_LOWER_HIGH) return "lower-high";
      return "standard";
   }

   //--- session VWAP from the signal-timeframe bars of the current day (the playbook's magnet).
   //--- `[interpretation]`: bar tick volume stands in for true traded volume where unavailable.
   double SessionVwap(const string sym)
   {
      MqlRates m[];
      int got = EA_Rates(sym, g_eaIndTf, 0, 300, m);
      if(got < 6) return 0.0;
      MqlDateTime first, cur;
      TimeToStruct(m[1].time, first);
      double pv = 0.0, vol = 0.0;
      for(int i = 1; i < got; i++)
      {
         TimeToStruct(m[i].time, cur);
         if(cur.day != first.day) break;                        // only today's bars
         double typical = (m[i].high + m[i].low + m[i].close) / 3.0;
         double v = (double)m[i].tick_volume;
         pv  += typical * v;
         vol += v;
      }
      if(vol <= 0.0) return 0.0;
      return pv / vol;
   }
};

CCfFirstRedDayPro g_cfFirstRedDayPro;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfFirstRedDayPro);
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
