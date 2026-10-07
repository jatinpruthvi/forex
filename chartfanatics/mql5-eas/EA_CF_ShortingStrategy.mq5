//+------------------------------------------------------------------+
//|                                        EA_CF_ShortingStrategy.mq5 |
//|                                  Copyright 2026, Master Strategy  |
//|                                                                   |
//| ChartFanatics playbook: Shorting Strategy (Kris Verma)             |
//| Card    : chartfanatics/todos/shorting-strategy.md         (#34)   |
//| Source  : chartfanatics/pdf/shorting-strategy.pdf                  |
//| Magic   : 3237                                                    |
//|                                                                   |
//| "This playbook focuses on shorting small-cap stocks that gap up    |
//|  sharply, usually driven by hype ... rather than real business     |
//|  strength."  The document is explicit about what is systematic and |
//|  what is discretionary; the systematic spine is implemented:       |
//|                                                                   |
//|   R1  GAP SELECTION: "Focus on stocks with large percentage gaps.  |
//|       Smaller moves (around 20-40%) are avoided" - the minimum gap |
//|       is an input, defaulted above that avoided band.              |
//|   R2  GAP-UP SHORT WITH FADE VALIDATION: "The stock gaps up        |
//|       strongly in pre-market ... and holds its gains into the      |
//|       open".  "Entry is considered after the open, not in          |
//|       pre-market."                                                 |
//|   R3  THE 10:00 a.m. BEHAVIOR CHECK - the key confirmation: "The   |
//|       stock is trading below the open price by ~10:00 a.m." and    |
//|       "Volume is decreasing as the price moves lower".  Live rule: |
//|       "Above the open: reduce risk or consider exiting" - the EA   |
//|       closes a short once price is back above the session open     |
//|       after the check.                                             |
//|   R4  "Short entries are taken into pops or bounces once downside  |
//|       behavior is confirmed" and "Avoid shorting the exact low of  |
//|       a flush" - the entry bar is a completed bounce that is still |
//|       below the open, and the price must be clear of the session   |
//|       low.                                                         |
//|   R5  BACKSIDE PARABOLIC SHORT (the primary edge): "A large move   |
//|       has already occurred ... Signs of topping appear (upper      |
//|       wicks, failed pushes, slowing momentum).  Volume begins to   |
//|       decline as price fades.  Do not short the first sign of      |
//|       weakness.  Wait for clear confirmation that the move is      |
//|       shifting from front-side to backside.  Avoid shorting lows.  |
//|       Enter on bounces during the fade".                           |
//|   R6  "Downside targets are based on historical pullbacks, often   |
//|       around 30-40%" - the target is that percentage band.         |
//|   R7  MULTI-HALT EXHAUSTION SHORT: "No entries are taken during    |
//|       the early halts.  Entries are only considered after several  |
//|       up-halts, typically once exhaustion is likely ... commonly   |
//|       4-5 ... The overall extension is historically extreme."      |
//|       Halts are not observable in MetaTrader (the symbol simply    |
//|       stops trading), so this setup is proxied by the document's   |
//|       own fallback - the overall extension being extreme - and     |
//|       disclosed.                                                   |
//|   R8  STOP LOGIC: "Pre-market highs are not used as stops" -       |
//|       "Stops are set at a fixed percentage from entry", and the    |
//|       stops are deliberately WIDE: "Wider stops reduce the chance  |
//|       of being stopped out by manipulation.  The goal is staying   |
//|       in the trade, not tight precision."                          |
//|   R9  RISK: "Position size must be kept conservative.  No single   |
//|       trade should put the account at risk."                       |
//|   R10 THE 30-MINUTE VALIDATION: "If the trade is working after     |
//|       ~30 minutes, holding makes sense.  If the price is           |
//|       reclaiming or stalling, reassess the position" - the         |
//|       engine's time stop with an R escape hatch.                   |
//|   R11 RECYCLING: "Take partial profits into sharp drops near       |
//|       support.  Re-enter shorts on bounces near prior support      |
//|       that becomes resistance.  Repeat within a defined range" -   |
//|       a partial at the first R plus re-entries on later bounces    |
//|       (the day's attempts budget), not a single entry and exit.    |
//|   R12 TIME OF DAY: preferred window from the open; "After ~12:00   |
//|       p.m., edge decreases ... Trading is usually reduced or       |
//|       stopped after midday" - no new entries after midday.         |
//|                                                                   |
//| `[interpretation]`: the fixed stop percentage (the document says   |
//| "wide" but quantifies nothing), the volume-decline fraction, the  |
//| bounce definition, the flush clearance, the topping thresholds     |
//| (upper-wick share, failed push, volume fade), the extension that   |
//| proxies halt exhaustion, the attempts budget and the target band   |
//| centre are inputs and labelled.                                    |
//|                                                                   |
//| Disclosed, not faked: market capitalization (<$100-200M) and       |
//| institutional ownership (<40%) are not observable in MetaTrader;   |
//| the user's universe carries that filter, and the gap-size gate is  |
//| the EA's own quantitative stand-in.  Ongoing context checks        |
//| (manipulation reads, sympathy moves, small-cap breadth) and hard-  |
//| to-borrow fees stay human.                                         |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics Shorting Strategy (Kris Verma) - gap-up fade shorts, backside parabolic shorts and the halt-exhaustion proxy"

#include "..\..\Include\EACommon.mqh"

//--- setups
input bool              InpUseGapFade          = true;   // Gap-up short with fade validation (R2-R4)
input bool              InpUseBackside         = true;   // Backside parabolic short (R5-R6)
input bool              InpUseHaltExhaustion   = true;   // Multi-halt exhaustion proxy (R7)

//--- identity / risk
input string            InpSymbolsToTrade      = "AAPL,MSFT,NVDA";  // Universe (playbook: small-cap gappers - the user's list)
input ulong             InpMagicNumber         = 3237;    // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct             = 0.30;    // "position size must be kept conservative"
input int               InpStage               = 5;       // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input double            InpMaxSpreadPoints     = 5.0;     // Spread gate in points (0 = off)
input double            InpDailyLossPct        = 1.50;    // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset     = 2;       // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel            = EA_LOG_EVENTS;   // Log verbosity
input double            InpCommissionPerLotRT  = 0.0;     // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR            = 0.12;    // Cost gate: (spread + commission) <= xR
input bool              InpLedger              = true;    // Write the engine evidence ledger CSV

//--- R1 the gap gate
input double            InpMinGapPct           = 40.0;    // "Smaller moves (around 20-40%) are avoided"

//--- R2-R4 the gap-up fade
input int               InpBehaviorCheckHour   = 16;      // The 10:00 a.m. ET behavior check, London time
input double            InpVolDeclineFrac      = 0.85;    // [interpretation] "Volume is decreasing": recent vs earlier
input double            InpFlushClearAtr       = 1.00;    // [interpretation] "Avoid shorting the exact low of a flush"

//--- R5-R6 the backside parabolic short
input int               InpParaDays            = 20;      // [interpretation] The "large move" window
input double            InpParaMinPct          = 60.0;    // [interpretation] "A large move has already occurred" (%)
input double            InpToppingVolFrac      = 0.85;    // "Volume begins to decline as price fades"
input double            InpWickShareMin        = 0.30;    // [interpretation] "Signs of topping ... upper wicks"
input double            InpTargetPct           = 35.0;    // "Downside targets ... often around 30-40%"

//--- R7 the halt-exhaustion proxy
input double            InpHaltExtremePct      = 150.0;   // [interpretation] "The overall extension is historically extreme"

//--- R8-R9 the fixed wide stop
input double            InpStopPct             = 15.0;    // "Stops are set at a fixed percentage from entry" (wide by design)
input int               InpValidateMinutes     = 30;      // R10: "if the trade is working after ~30 minutes"
input double            InpValidateUnlessR     = 0.25;    // [interpretation] ... working means at least this R

//--- R11 the recycling
input int               InpMaxAttempts         = 4;       // [interpretation] Re-entry budget for the recycle loop
input double            InpPartialAtR          = 1.0;     // "Take partial profits into sharp drops near support"
input double            InpPartialPct          = 50.0;

//--- R12 the window (entries from the open until midday)
input int               InpSessionStartHour    = 14;      // US RTH open, London time (09:30 ET)
input int               InpSessionStartMin     = 30;
input int               InpLastEntryHour       = 18;      // "usually reduced or stopped after midday" (12:00 ET)
input int               InpSessionEndHour      = 21;      // US RTH close

//+------------------------------------------------------------------+
struct SShortCtx
{
   double openPrice;      // the session's first five-minute bar open
   double sessionHigh;
   double sessionLow;
   double gapPct;         // the pre-market / opening gap
   bool   belowOpen;      // the 10:00 check: trading below the open
   bool   volDeclining;   // "volume is decreasing as the price moves lower"
   bool   barIsBounce;    // the completed bar popped into weakness
   bool   clearOfFlush;   // not at the exact low of the flush
};

//+------------------------------------------------------------------+
class CCfShortingStrategy : public CEAStrategy
{
public:
   void OnInitStrategy()
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("5-stage policy: stage %d active (risk %.3f%%, %d trades/day max)",
             InpStage, g_eaCfg.riskPct, g_eaCfg.maxTradesPerDay), true);
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "Shorting Strategy armed: gap >= %.0f%%, fixed %.0f%% wide stop, target %.0f%%, entries after the open until midday",
             InpMinGapPct, InpStopPct, InpTargetPct), true);
   }

   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_SHORTING_STRATEGY";
      cfg.sourceDoc             = "chartfanatics/pdf/shorting-strategy.pdf (card #34)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;   // day trading; the intraday behavior reads
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = 4.0;
      cfg.totalDdPct            = 10.0;
      cfg.maxTradesPerDay       = InpMaxAttempts;         // R11: the recycle loop - several attempts, conservative sizing
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 300;
      cfg.sessionStartHour      = InpSessionStartHour;
      cfg.sessionStartMin       = InpSessionStartMin;
      cfg.sessionEndHour        = InpSessionEndHour;
      cfg.sessionEndMin         = 0;
      cfg.sessionEndFlat        = true;                   // day trading: flat at the bell
      cfg.noTradeAfterHour      = InpLastEntryHour;       // R12: "reduced or stopped after midday"
      cfg.noTradeAfterMin       = 0;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = false;
      cfg.partial1AtR           = InpPartialAtR;          // R11: partials into the sharp drops
      cfg.partial1Pct           = InpPartialPct;
      cfg.breakEvenAtR          = 0.0;                    // R8: fixed wide stops, "the goal is staying in the trade"
      cfg.trailAtR              = 0.0;                    // the document states no trailing rule
      cfg.timeStopMinutes       = InpValidateMinutes;     // R10: the 30-minute validation
      cfg.timeStopUnlessR       = InpValidateUnlessR;
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_shorting_ledger.csv";
      cfg.newsFilter            = false;
      cfg.logLevel              = InpLogLevel;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   //+----------------------------------------------------------------+
   //| Signal phase: the session frame, the gap gate, then whichever   |
   //| documented setup is live - the fade, the backside, or the       |
   //| halt-exhaustion proxy.                                          |
   //+----------------------------------------------------------------+
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession || ctx.atr <= 0.0) return false;

      MqlRates m[];
      if(EA_Rates(ctx.symbol, g_eaIndTf, 0, 240, m) < 12) return false;

      SShortCtx sc;
      if(!SessionFrame(ctx, m, sc)) return false;

      //--- R2/R3/R5/R4: the shared weakness frame - after the open, below it, off the flush low,
      //--- on a completed bounce
      if(ctx.clockMinutes < InpSessionStartHour * 60 + InpSessionStartMin + 5) return false;
      if(!sc.belowOpen) return false;                     // holding above the open is "a weak setup"
      if(!sc.clearOfFlush) return false;                  // "Avoid shorting the exact low of a flush"
      if(!sc.barIsBounce) return false;                   // "short entries are taken into pops or bounces"

      //--- R1: the gap gate is the EA's quantitative stand-in for the selection criteria
      MqlRates d[];
      int got = EA_Rates(ctx.symbol, PERIOD_D1, 0, MathMax(80, InpParaDays + 30), d);
      if(got < 45) return false;
      bool gapOk = (sc.gapPct >= InpMinGapPct);

      double stop  = ctx.ask * (1.0 + InpStopPct / 100.0);         // R8: fixed percentage, deliberately wide
      double entry = ctx.bid;
      double risk  = stop - entry;
      if(risk <= 0.0) return false;

      double best = -1.0;
      SSignalPlan p;

      //--- the gap-up fade (R2-R4)
      if(InpUseGapFade && gapOk && ctx.clockMinutes >= InpBehaviorCheckHour * 60 && sc.volDeclining)
      {
         p.Reset();
         if(PlanPayload(ctx, sc, InpTargetPct, 76.0,
                        StringFormat("gap fade: %.0f%% gap, below the open with declining volume, bounce entry", sc.gapPct),
                        entry, stop, risk, p) && p.score > best) { plan = p; best = p.score; }
      }

      //--- the backside parabolic (R5-R6)
      if(InpUseBackside)
      {
         double runPct = 0.0;
         bool topping = false, fading = false;
         if(ParabolicRead(d, got, runPct, topping, fading) && runPct >= InpParaMinPct)
         {
            p.Reset();
            double score = 80.0 + (topping ? 6.0 : 0.0) + (fading ? 6.0 : 0.0);
            if(PlanPayload(ctx, sc, InpTargetPct, score,
                           StringFormat("backside parabolic: %.0f%% run, topping signs, bounce entry during the fade", runPct),
                           entry, stop, risk, p) && p.score > best) { plan = p; best = p.score; }
         }
      }

      //--- the halt-exhaustion proxy (R7): the extension itself is the gate
      if(InpUseHaltExhaustion)
      {
         double extPct = ExtremeExtension(d, got, 2);
         if(extPct >= InpHaltExtremePct)
         {
            p.Reset();
            if(PlanPayload(ctx, sc, InpTargetPct, 84.0,
                           StringFormat("halt-exhaustion proxy: %.0f%% extreme extension, bounce entry after the run", extPct),
                           entry, stop, risk, p) && p.score > best) { plan = p; best = p.score; }
         }
      }
      return (plan.dir != 0);
   }

   //+----------------------------------------------------------------+
   //| R3 live rule: "Above the open: reduce risk or consider exiting" |
   //| - once the behavior check has passed, a reclaim of the session  |
   //| open closes the short.  R10's 30-minute validation lives in the |
   //| engine's time stop.                                             |
   //+----------------------------------------------------------------+
   void Manage(SEAContext &ctx)
   {
      ulong ticket = EA_FindPosition(ctx.symbol, -1);
      if(ticket == 0) return;

      int checkMin = InpBehaviorCheckHour * 60;
      if(ctx.clockMinutes < checkMin) return;              // the check has not happened yet

      double openPx = SessionOpen(ctx);
      if(openPx <= 0.0) return;
      if(ctx.ask > openPx)
      {
         if(g_eaExec.Close(ticket, "price is back above the session open - reduce risk / exit"))
            EA_Log(EA_LOG_EVENTS, StringFormat("Shorting Strategy: closed %I64u, reclaim of the open %.2f", ticket, openPx), true);
      }
   }

private:
   //--- the session's first five-minute bar open ("the open" of the playbook)
   datetime SessionAnchor(const SEAContext &ctx)
   {
      MqlDateTime dt;
      TimeToStruct(ctx.nowClock, dt);
      dt.hour = InpSessionStartHour; dt.min = InpSessionStartMin; dt.sec = 0;
      return EA_ClockToServer(StructToTime(dt));
   }

   double SessionOpen(const SEAContext &ctx)
   {
      MqlRates m[];
      if(EA_Rates(ctx.symbol, g_eaIndTf, 0, 240, m) < 6) return 0.0;
      datetime anchor = SessionAnchor(ctx);
      for(int i = ArraySize(m) - 1; i >= 0; i--)
      {
         if(m[i].time < anchor) continue;
         return m[i].open;                                 // the first session bar's open
      }
      return 0.0;
   }

   //--- the session frame: the open, the extremes, the gap, the check, the bounce
   bool SessionFrame(const SEAContext &ctx, const MqlRates &m[], SShortCtx &sc)
   {
      sc.openPrice = 0.0; sc.sessionHigh = 0.0; sc.sessionLow = 0.0; sc.gapPct = 0.0;
      sc.belowOpen = false; sc.volDeclining = false; sc.barIsBounce = false; sc.clearOfFlush = false;

      datetime anchor = SessionAnchor(ctx);
      sc.openPrice = SessionOpen(ctx);
      if(sc.openPrice <= 0.0) return false;

      for(int i = 0; i < ArraySize(m); i++)
      {
         if(m[i].time < anchor) break;
         sc.sessionHigh = (sc.sessionHigh == 0.0) ? m[i].high : MathMax(sc.sessionHigh, m[i].high);
         sc.sessionLow  = (sc.sessionLow == 0.0)  ? m[i].low  : MathMin(sc.sessionLow,  m[i].low);
      }
      if(sc.sessionLow <= 0.0) return false;

      //--- R3: the behavior read - trading below the open price
      sc.belowOpen = (ctx.bid < sc.openPrice);
      if(!sc.belowOpen) return false;

      //--- "Volume is decreasing as the price moves lower": recent bars vs the earlier fade
      double recent = 0.0, earlier = 0.0;
      int rn = 0, en = 0;
      for(int i = 1; i <= 6 && i < ArraySize(m); i++) { recent += (double)m[i].tick_volume; rn++; }
      for(int i = 7; i <= 18 && i < ArraySize(m); i++) { earlier += (double)m[i].tick_volume; en++; }
      if(rn > 0 && en > 0)
      {
         recent /= rn; earlier /= en;
         sc.volDeclining = (earlier <= 0.0) || (recent <= InpVolDeclineFrac * earlier);
      }

      //--- R4: the entry bar is a completed bounce that is still weak
      sc.barIsBounce = (m[1].close > m[1].open) && (m[1].close < sc.openPrice) && (ctx.bid < m[1].high);

      //--- "avoid the exact low of a flush"
      sc.clearOfFlush = ((ctx.bid - sc.sessionLow) >= InpFlushClearAtr * ctx.atr);

      //--- R1: the gap read - the pre-market / opening gap versus the prior close
      MqlRates d[];
      if(EA_Rates(ctx.symbol, PERIOD_D1, 0, 3, d) >= 2 && d[1].close > 0.0)
      {
         double gapRef = (d[0].open > 0.0) ? d[0].open : sc.openPrice;
         sc.gapPct = (gapRef - d[1].close) / d[1].close * 100.0;
      }
      return true;
   }

   //--- R5: the parabolic read - the run-up, the topping signs, the fading volume
   bool ParabolicRead(const MqlRates &d[], const int got, double &runPct, bool &topping, bool &fading)
   {
      runPct = 0.0; topping = false; fading = false;
      int n = (int)MathMax(5, MathMin(InpParaDays, got - 20));
      double lo = d[1].low, hi = d[1].high;
      for(int i = 1; i <= n; i++)
      {
         lo = MathMin(lo, d[i].low);
         hi = MathMax(hi, d[i].high);
      }
      if(lo <= 0.0) return false;
      runPct = (hi - lo) / lo * 100.0;

      //--- "signs of topping appear (upper wicks, failed pushes)": the recent bars carry big
      //--- upper wicks and yesterday failed to make a new high
      int wickBars = 0;
      for(int i = 1; i <= 5; i++)
      {
         double rng = d[i].high - d[i].low;
         if(rng <= 0.0) continue;
         double upper = d[i].high - MathMax(d[i].open, d[i].close);
         if(upper / rng >= InpWickShareMin) wickBars++;
      }
      bool failedPush = (d[1].high < hi);                  // no new high - a failed push
      topping = (wickBars >= 2) || failedPush;

      //--- "volume begins to decline as price fades"
      double recentVol = 0.0, earlierVol = 0.0;
      for(int i = 1; i <= 3; i++) recentVol += (double)d[i].tick_volume;
      for(int i = 4; i <= 13; i++) earlierVol += (double)d[i].tick_volume;
      recentVol /= 3.0; earlierVol /= 10.0;
      fading = (earlierVol <= 0.0) || (recentVol <= InpToppingVolFrac * earlierVol);
      return true;
   }

   //--- R7: the extension over a short window (the halt-exhaustion proxy)
   double ExtremeExtension(const MqlRates &d[], const int got, const int days)
   {
      int n = (int)MathMax(2, MathMin(days, got - 2));
      double lo = d[1].low;
      for(int i = 1; i <= n; i++) lo = MathMin(lo, d[i].low);
      if(lo <= 0.0) return 0.0;
      return (d[1].high - lo) / lo * 100.0;
   }

   //--- the shared plan assembly (target from the historical pullback band)
   bool PlanPayload(const SEAContext &ctx, const SShortCtx &sc, const double targetPct, const double score,
                    const string why, const double entry, const double stop, const double risk, SSignalPlan &p)
   {
      double target = entry * (1.0 - targetPct / 100.0);   // "around 30-40%"
      if(target <= 0.0) return false;

      p.dir      = -1;
      p.entry    = entry;
      p.stop     = stop;
      p.target   = target;
      p.riskDist = risk;
      p.barsAgo  = 1;
      p.score    = MathMin(score, 100.0);
      p.isLimit  = false;
      p.reason   = StringFormat("%s (open %.2f, low %.2f)", why, sc.openPrice, sc.sessionLow);
      return true;
   }
};

CCfShortingStrategy g_cfShorting;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfShorting);
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
