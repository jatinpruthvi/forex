//+------------------------------------------------------------------+
//|                                          EA_CF_PriceAction.mq5    |
//|                                  Copyright 2026, Master Strategy  |
//|                                                                   |
//| ChartFanatics (Gala Trades): Price Action Strategy                 |
//| "How a $5M Trader Executes His Price Action Strategy Live"         |
//| Card    : chartfanatics/todos/price-action-strategy.md      (#31)  |
//| Source  : chartfanatics/glimpse/70UtrLU6RAg.md                     |
//| Magic   : 3234                                                    |
//|                                                                   |
//| The playbook is a discretionary day-trade routine, but its core    |
//| is mechanical and it states it plainly: trends from successive      |
//| highs and lows, hourly levels, three candle patterns, and a fixed   |
//| 2R risk plan.  Everything below is a rule the document states:      |
//|                                                                   |
//|   R1  TREND: "Identify trends by tracking successive highs and      |
//|       lows rather than parallel lines.  An uptrend has higher       |
//|       highs and higher lows; a downtrend has lower highs and lower  |
//|       lows.  This determines which direction (calls or puts) to     |
//|       trade."  Read from H1 pivots; a mixed structure means no      |
//|       trade.                                                        |
//|   R2  LEVELS: "Mark pivoting points where price reversed on the     |
//|       hourly chart, focusing on candle open prices rather than      |
//|       wicks."  Each H1 pivot becomes a level at its OPEN price.     |
//|   R3  CONFIDENCE: "5/5 for strong pivots, 3/5 for opening prices,   |
//|       2.5/5 for invalidated levels."  A level pivoted at            |
//|       InpStrongTouches or more scores 5/5, a single pivot 3/5, and  |
//|       one that price has closed decisively through 2.5/5.           |
//|   R4  SIZING: "high-confidence levels get full size; low-confidence |
//|       or off-plan setups get 25-50% size" - LotsMultiplier scales    |
//|       the risk by the level's confidence.                           |
//|   R5  ENTRIES: "watch the 2-5 minute timeframe ... Prefer 5-minute  |
//|       candles for conviction, but use 2-minute if both align."      |
//|   R6  "Skip the first 5 minutes of market open to avoid volatility  |
//|       and false breakouts."                                         |
//|   R7  BREAK AND RETEST: "Price breaks above (or below) a level on a |
//|       5-minute candle, then retests it on the next candle(s).       |
//|       Ideal setup has a small wick below the level but body above   |
//|       it ... Enter as close to the level as possible with a tight   |
//|       stop-loss just below the wick."                               |
//|   R8  BOUNCE (calls): "price approaches a support level from above, |
//|       creates 2-3 candles with bodies above the level but wicks     |
//|       probing below it ... Enter near the level with stop-loss at   |
//|       the lowest wick point."                                       |
//|   R9  REJECTION (puts): "price approaches a resistance level from   |
//|       below, creates multiple candles with bodies below the level    |
//|       but wicks pushing up unsuccessfully ... Enter near the level  |
//|       targeting the next lower level."                              |
//|   R10 TWO ENTRIES MAXIMUM: "On the same setup, take a maximum of    |
//|       two entries.  If stopped out once, you may retry once more.   |
//|       A third entry on the same setup is overtrading."  Counted     |
//|       from the day's own deals at that level.                       |
//|   R11 "Once price reaches 2R ... trim 50% of position.  Shift       |
//|       stop-loss above entry so remaining contracts are profitable   |
//|       even if stopped out."                                         |
//|   R12 "Continue trimming at higher multiples."                      |
//|   R13 "shifting stop-loss with each green candle to reduce stress   |
//|       and lock in gains" - the candle trail in Manage().            |
//|   R14 TARGET: "Aim for 2R or 1.5R per trade, not 5R or 10R home     |
//|       runs", and for the rejection pattern the next lower level     |
//|       caps the target.                                              |
//|   R15 "Aim for 2-3 high-quality trades per day; 4+ is overtrading." |
//|   R16 ONE AND DONE: "After a winning trade, stop trading for the    |
//|       day."  The engine's dayLockFirstWin does exactly this.        |
//|   R17 "Never re-enter the same setup on the same day" - a winning   |
//|       exit locks the day (R16), and after a stop-out the same setup |
//|       may be retried only once (R10).                               |
//|   R18 "The trader executes for only 1 hour daily (typically market  |
//|       open)" - entries only inside the first hour of the session.   |
//|   R19 OPTIONAL ORDERFLOW: "price action ... as the core, with       |
//|       optional orderflow (bookmap) as confirmation on liquid         |
//|       instruments like SPY and QQQ."  No bookmap exists in MT5, so  |
//|       the confirmation is a labelled tick-volume skew and it is off |
//|       by default - "optional" in the document too.                  |
//|                                                                   |
//| `[interpretation]`: the pivot wing, the level tolerance, the strong |
//| touch count, the invalidation distance, the probe and entry         |
//| distances, how many candles the bounce/rejection counts, the stop   |
//| buffer, the break-even offset above entry, the second trim, the     |
//| candle-trail buffer and the volume skew cut are engineering numbers |
//| the document does not state - all inputs, all labelled.  The        |
//| pre-market 10-name plan, the economic-calendar check, hiding the    |
//| P&L, and the journaling (star ratings, rules checklist) stay human  |
//| and are not faked: the engine ledger records the setup type and the |
//| R outcome the journal needs.  The playbook's engine note: while the |
//| document trades options on TSLA/SPY/QQQ and futures ES/NQ, the      |
//| symbol list is the user's universe, as in the other cards.          |
//|                                                                   |
//| Note on reuse: `SigFractals` cannot serve this playbook - it is     |
//| bound to the signal timeframe and returns WICK prices, while the    |
//| document's levels are H1 pivot OPEN prices.  The H1 scan is local   |
//| (on top of `EA_Rates`) for that reason, and everything else is the  |
//| engine's: EA_InWindow, the cost gate, the ledger, the partial /     |
//| break-even machinery, EA_ApplyStagePolicy and LotsMultiplier.       |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics Price Action (Gala Trades) - hourly levels with confidence sizing, three candle patterns on M5, 2R management"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade      = "US100,US500";   // Universe (playbook: SPY / QQQ analogues, ES / NQ)
input ulong             InpMagicNumber         = 3234;            // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct             = 0.40;            // Risk per trade (% of equity)
input int               InpStage               = 5;               // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input double            InpMaxSpreadPoints     = 3.0;             // Spread gate in points (0 = off)
input double            InpDailyLossPct        = 1.50;            // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset     = 2;               // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel            = EA_LOG_EVENTS;   // Log verbosity
input double            InpCommissionPerLotRT  = 0.0;             // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR            = 0.12;            // Cost gate: (spread + commission) <= xR
input bool              InpLedger              = true;            // Write the engine evidence ledger CSV

//--- R1/R2/R3: the H1 trend, the levels and their confidence
input int               InpLevelLookbackHours  = 120;             // Hours of pivots scanned for levels
input int               InpPivotWing           = 2;               // [interpretation] Bars on each side of a pivot
input double            InpLevelTolAtr         = 0.35;            // [interpretation] How near the pivot open counts as the same level
input int               InpStrongTouches       = 3;               // [interpretation] Pivots that make a 5/5 level
input double            InpInvalidateAtr       = 1.00;            // [interpretation] Close beyond the level that makes it 2.5/5
input int               InpMaxLevels           = 12;              // [interpretation] Levels kept per symbol
input double            InpMidConfSize         = 0.50;            // "low-confidence ... 25-50% size" - the 3/5 level
input double            InpLowConfSize         = 0.25;            // ... and the 2.5/5 level

//--- R5/R6/R7/R8/R9: the M5 patterns
input bool              InpAlignM2             = true;            // "use 2-minute if both align"
input int               InpBounceBars          = 3;               // "2-3 candles" for the bounce / rejection
input int               InpBounceMinBodies     = 2;               // [interpretation] Candles with a body on the defended side
input double            InpMaxProbeAtr         = 0.30;            // [interpretation] How far a wick may probe past the level
input double            InpMaxEntryDistAtr     = 0.50;            // "enter as close to the level as possible"
input double            InpTouchTolAtr         = 0.10;            // [interpretation] How close the retest must come
input int               InpRetestLookback      = 6;               // [interpretation] Bars searched for the break candle
input double            InpStopBufferAtr       = 0.10;            // [interpretation] Buffer beyond the wick

//--- R11/R12/R13/R14/R15/R16: risk and management
input double            InpPartialAtR          = 2.0;             // "Once price reaches 2R ... trim 50%"
input double            InpPartialPct          = 50.0;
input double            InpBeOffsetR           = 0.25;            // [interpretation] "above entry" - this far past it
input double            InpPartial2AtR         = 3.0;             // [interpretation] "continue trimming at higher multiples"
input double            InpPartial2Pct         = 25.0;
input bool              InpCandleTrail         = true;            // "shifting stop-loss with each green candle"
input double            InpTrailBufferAtr      = 0.05;            // [interpretation] Buffer under / over the candle
input double            InpTargetR             = 2.0;             // "Aim for 2R ... not 5R or 10R"
input double            InpMinRR               = 1.5;             // "2R or 1.5R per trade"
input int               InpMaxAttemptsPerSetup = 2;               // "take a maximum of two entries"
input int               InpMaxTradesPerDay     = 3;               // "Aim for 2-3 ... 4+ is overtrading"

//--- R19: the optional orderflow confirmation (labelled proxy)
input bool              InpUseVolumeConfirm    = false;           // "optional orderflow ... as confirmation"
input int               InpVolumeBars          = 12;              // Bars of the aggressive-side read
input double            InpVolLeanCut          = 0.10;            // [interpretation] The skew that counts as agreement

//--- R6/R18: the execution window
input int               InpSessionStartHour    = 14;              // US RTH open, London time (09:30 ET)
input int               InpSessionStartMin     = 30;
input int               InpSkipOpenMinutes     = 5;               // "skip the first 5 minutes of market open"
input int               InpEntryEndHour        = 15;              // "executes for only 1 hour daily" (10:35 ET)
input int               InpEntryEndMin         = 35;
input int               InpSessionEndHour      = 21;              // US RTH close - no overnight holds
input int               InpSessionEndMin       = 0;

//+------------------------------------------------------------------+
struct SPaLevel
{
   double price;      // the pivot candle's OPEN, not the wick (R2)
   int    type;       // +1 = resistance pivot, -1 = support pivot
   int    touches;    // pivots clustered at this price
   double conf;       // 5.0 / 3.0 / 2.5 (R3)
   int    pivotIdx;   // index into the H1 array (for the invalidation scan)
};

struct SPaSetup
{
   bool   found;
   int    kind;       // 1 = break and retest, 2 = bounce, 3 = rejection
   int    dir;
   double level;
   double conf;
   double stopLevel;  // the wick the playbook risks
};

//+------------------------------------------------------------------+
class CCfPriceAction : public CEAStrategy
{
public:
   //--- R4: size by the confidence of the level the plan used
   virtual double LotsMultiplier(SEAContext &ctx)
   {
      double conf = 0.0;
      if(ctx.index >= 0 && ctx.index < ArraySize(m_lastConf)) conf = m_lastConf[ctx.index];
      if(conf >= 5.0) return 1.00;              // "high-confidence levels get full size"
      if(conf >= 3.0) return InpMidConfSize;    // "... low-confidence ... 25-50% size"
      return InpLowConfSize;                    // invalidated / unknown - take the small size
   }

   void OnInitStrategy()
   {
      ArrayResize(m_lastConf, g_eaSymbolCount);
      ArrayInitialize(m_lastConf, 0.0);
      EA_Log(EA_LOG_EVENTS, StringFormat("5-stage policy: stage %d active (risk %.3f%%, %d trades/day max)",
             InpStage, g_eaCfg.riskPct, g_eaCfg.maxTradesPerDay), true);
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "Price Action armed: H1 levels (%d hours), M5 patterns, %.1fR target, one-and-done %s",
             InpLevelLookbackHours, InpTargetR, InpLedger ? "with ledger" : "no ledger"), true);
   }

   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_PRICE_ACTION";
      cfg.sourceDoc             = "chartfanatics/glimpse/70UtrLU6RAg.md (card #31)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;              // "prefer 5-minute candles for conviction"
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = 3.0;
      cfg.totalDdPct            = 8.0;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;     // R15
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 300;
      cfg.sessionStartHour      = InpSessionStartHour;    // the open
      cfg.sessionStartMin       = InpSessionStartMin;
      cfg.sessionEndHour        = InpSessionEndHour;      // the cash close - "not overnight holds"
      cfg.sessionEndMin         = InpSessionEndMin;
      cfg.sessionEndFlat        = true;
      cfg.noTradeAfterHour      = InpEntryEndHour;        // R18: the one-hour execution window
      cfg.noTradeAfterMin       = InpEntryEndMin;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.dayLockFirstWin       = true;                   // R16 "one and done"
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = false;
      cfg.partial1AtR           = InpPartialAtR;          // R11
      cfg.partial1Pct           = InpPartialPct;
      cfg.breakEvenAtR          = InpPartialAtR;           // "shift stop-loss above entry"
      cfg.beOffsetR             = InpBeOffsetR;
      cfg.partial2AtR           = InpPartial2AtR;         // R12
      cfg.partial2Pct           = InpPartial2Pct;
      cfg.trailAtR              = 0.0;                    // R13 is the candle trail in Manage()
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_price_action_ledger.csv";
      cfg.newsFilter            = false;                  // the calendar check is the trader's (disclosed)
      cfg.logLevel              = InpLogLevel;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   //+----------------------------------------------------------------+
   //| Signal phase: H1 trend and levels, then one of the three M5     |
   //| candle patterns in the trend's direction (R1-R9).                |
   //+----------------------------------------------------------------+
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession || ctx.atr <= 0.0) return false;

      //--- R6/R18: skip the open and stop entering after the first hour
      int openMin = InpSessionStartHour * 60 + InpSessionStartMin;
      if(ctx.clockMinutes < openMin + InpSkipOpenMinutes) return false;
      if(ctx.clockMinutes > InpEntryEndHour * 60 + InpEntryEndMin) return false;

      //--- R15: the daily trade cap (the engine also enforces maxTradesPerDay)
      if(ctx.tradesToday >= InpMaxTradesPerDay) return false;

      //--- R1/R2/R3: the hourly map
      int    pIdx[], pType[];
      double pOpen[], pExt[];
      MqlRates h[];
      int hGot = 0;
      int pivots = BuildPivots(ctx, h, hGot, pIdx, pOpen, pExt, pType);
      if(pivots < 4) return false;
      int trend = H1Trend(pType, pExt, pivots);
      if(trend == 0) return false;                         // "successive highs and lows" - mixed means no trade

      SPaLevel lv[];
      int n = BuildLevels(ctx, h, hGot, pIdx, pOpen, pType, lv);
      if(n <= 0) return false;

      //--- R5/R7/R8/R9: the candle patterns on the signal timeframe
      MqlRates m[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, InpRetestLookback + 10, m);
      if(got < InpRetestLookback) return false;

      SPaSetup s;
      if(!PatternSetup(ctx, lv, n, trend, m, got, s)) return false;
      if(s.conf <= 0.0) return false;

      //--- R5: the 2-minute alignment when both agree
      if(InpAlignM2 && !M2Aligned(ctx, s.dir)) return false;

      //--- R19: the optional orderflow confirmation (a labelled volume skew)
      double lean = VolumeLean(ctx.symbol, InpVolumeBars);
      bool   volOk = (s.dir > 0) ? (lean > InpVolLeanCut) : (lean < -InpVolLeanCut);
      if(InpUseVolumeConfirm && !volOk) return false;

      //--- R10/R17: this setup may be entered at most twice a day
      double tol = InpLevelTolAtr * LevelAtr(ctx);
      if(SameSetupAttempts(ctx, s.level, tol) >= InpMaxAttemptsPerSetup) return false;

      //--- stop, target, risk (R7/R8/R9 geometry + R14 targets)
      double entry = (s.dir > 0) ? ctx.ask : ctx.bid;
      double stop  = (s.dir > 0) ? (s.stopLevel - InpStopBufferAtr * ctx.atr)
                                 : (s.stopLevel + InpStopBufferAtr * ctx.atr);
      double risk  = (s.dir > 0) ? (entry - stop) : (stop - entry);
      if(risk <= 0.0) return false;

      double target = 0.0;
      if(!BestTarget(ctx, lv, n, s.dir, entry, risk, target)) return false;

      plan.dir      = s.dir;
      plan.entry    = entry;
      plan.stop     = stop;
      plan.target   = target;
      plan.riskDist = risk;
      plan.barsAgo  = 1;
      plan.score    = Score(s, volOk);
      plan.isLimit  = false;
      plan.reason   = StringFormat("%s at %.2f (%.1f/5 level): trend-aligned, risk %.2f",
                                   PatternName(s.kind), s.level, s.conf, risk);
      if(ctx.index >= 0 && ctx.index < ArraySize(m_lastConf)) m_lastConf[ctx.index] = s.conf;   // R4
      return true;
   }

   //--- R13: "shifting stop-loss with each green candle" once the trade is past the first trim
   void Manage(SEAContext &ctx)
   {
      if(!InpCandleTrail || ctx.atr <= 0.0) return;

      int dir = -1;
      ulong ticket = EA_FindPosition(ctx.symbol, dir);
      if(ticket == 0) { dir = +1; ticket = EA_FindPosition(ctx.symbol, dir); }
      if(ticket == 0 || !PositionSelectByTicket(ticket)) return;

      double risk = GlobalVariableCheck(EA_RiskKey(ticket)) ? GlobalVariableGet(EA_RiskKey(ticket)) : 0.0;
      if(risk <= 0.0) return;
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double cur   = (dir > 0) ? ctx.bid : ctx.ask;
      double moveR = (dir > 0) ? (cur - entry) : (entry - cur);
      if(moveR / risk < InpPartialAtR) return;             // the trail starts with the first trim (R11 -> R13)

      MqlRates m[];
      if(EA_Rates(ctx.symbol, g_eaIndTf, 0, 3, m) < 2) return;
      double buf  = InpTrailBufferAtr * ctx.atr;
      double newSl = (dir > 0) ? m[1].low - buf : m[1].high + buf;
      if(dir > 0 && newSl >= cur) return;                  // never inside the spread
      if(dir < 0 && newSl <= cur) return;

      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      bool better = (dir > 0) ? (sl <= 0.0 || newSl > sl) : (sl <= 0.0 || newSl < sl);
      if(!better) return;                                  // a trail never loosens
      if(g_eaExec.Modify(ticket, newSl, tp))
         EA_Log(EA_LOG_EVENTS, StringFormat("Price Action: stop trailed to the candle at %.2f", newSl), true);
   }

private:
   double m_lastConf[];   // R4: per-symbol confidence of the plan handed to the engine

   //--- the H1 pivot scan (R2).  Returns the pivot count; the arrays are newest-first.
   int BuildPivots(const SEAContext &ctx, MqlRates &h[], int &got,
                   int &idx[], double &openP[], double &ext[], int &type[])
   {
      ArrayResize(idx, 0); ArrayResize(openP, 0); ArrayResize(ext, 0); ArrayResize(type, 0);

      got = EA_Rates(ctx.symbol, PERIOD_H1, 1, InpLevelLookbackHours + 4, h);
      if(got < InpLevelLookbackHours / 2) return 0;
      int wing = (InpPivotWing >= 1) ? InpPivotWing : 1;

      for(int i = wing; i + wing < got; i++)
      {
         bool ph = true, pl = true;
         for(int k = 1; k <= wing; k++)
         {
            if(h[i].high <= h[i - k].high || h[i].high <= h[i + k].high) ph = false;
            if(h[i].low  >= h[i - k].low  || h[i].low  >= h[i + k].low)  pl = false;
            if(!ph && !pl) break;
         }
         if(!ph && !pl) continue;
         int n = ArraySize(idx);
         ArrayResize(idx, n + 1); ArrayResize(openP, n + 1);
         ArrayResize(ext, n + 1); ArrayResize(type, n + 1);
         idx[n]  = i;
         openP[n] = h[i].open;                             // R2: the level is the pivot candle OPEN
         type[n] = ph ? +1 : -1;                           // a pivot high before a pivot low (never both here)
         ext[n]  = ph ? h[i].high : h[i].low;              // the wick, used by the trend read (R1)
         if(ph && pl) type[n] = 0;                         // an outside pivot states no direction
      }
      return ArraySize(idx);
   }

   //--- R1: higher highs AND higher lows, or lower highs AND lower lows
   int H1Trend(const int &type[], const double &ext[], const int n)
   {
      double hi0 = 0.0, hi1 = 0.0, lo0 = 0.0, lo1 = 0.0;
      int nh = 0, nl = 0;
      for(int k = 0; k < n && (nh < 2 || nl < 2); k++)
      {
         if(type[k] == 0) continue;
         if(type[k] > 0 && nh < 2) { if(nh == 0) hi0 = ext[k]; else hi1 = ext[k]; nh++; }
         if(type[k] < 0 && nl < 2) { if(nl == 0) lo0 = ext[k]; else lo1 = ext[k]; nl++; }
      }
      if(nh < 2 || nl < 2) return 0;
      if(hi0 > hi1 && lo0 > lo1) return +1;
      if(hi0 < hi1 && lo0 < lo1) return -1;
      return 0;
   }

   //--- R2/R3: cluster the pivots into levels and score their confidence
   int BuildLevels(const SEAContext &ctx, const MqlRates &h[], const int got,
                   const int &idx[], const double &openP[], const int &type[], SPaLevel &lv[])
   {
      ArrayResize(lv, 0);
      double atrH1 = LevelAtr(ctx);
      double tol   = InpLevelTolAtr * atrH1;

      for(int k = 0; k < ArraySize(idx); k++)
      {
         if(type[k] == 0) continue;
         int found = -1;
         for(int j = 0; j < ArraySize(lv); j++)
            if(lv[j].type == type[k] && MathAbs(lv[j].price - openP[k]) <= tol) { found = j; break; }

         if(found < 0)
         {
            int m = ArraySize(lv);
            ArrayResize(lv, m + 1);
            lv[m].price    = openP[k];
            lv[m].type     = type[k];
            lv[m].touches  = 1;
            lv[m].conf     = 3.0;                          // "3/5 for opening prices"
            lv[m].pivotIdx = idx[k];
         }
         else
            lv[found].touches++;                           // a level pivoted here again
      }

      //--- confidence and invalidation (R3), then the cap
      for(int j = 0; j < ArraySize(lv); j++)
      {
         if(lv[j].touches >= InpStrongTouches) lv[j].conf = 5.0;   // "5/5 for strong pivots"
         if(got > 2)
         {
            for(int i = 0; i < lv[j].pivotIdx && i < got; i++)     // bars NEWER than the pivot
            {
               bool through = (lv[j].type > 0) ? (h[i].close > lv[j].price + InpInvalidateAtr * atrH1)
                                               : (h[i].close < lv[j].price - InpInvalidateAtr * atrH1);
               if(through) { lv[j].conf = 2.5; break; }            // "2.5/5 for invalidated levels"
            }
         }
      }
      if(ArraySize(lv) > InpMaxLevels) ArrayResize(lv, InpMaxLevels);
      return ArraySize(lv);
   }

   //--- R7/R8/R9: the three patterns, trend-aligned, at the nearest applicable level
   bool PatternSetup(const SEAContext &ctx, const SPaLevel &lv[], const int n, const int trendDir,
                     const MqlRates &m[], const int got, SPaSetup &out)
   {
      out.found = false; out.kind = 0; out.dir = 0;
      out.level = 0.0; out.conf = 0.0; out.stopLevel = 0.0;
      double atr = ctx.atr;
      double near = InpMaxEntryDistAtr * atr;

      for(int k = 0; k < n; k++)
      {
         SPaSetup c;
         c.found = false;
         bool hit = false;
         if(trendDir > 0)
         {
            if(lv[k].type < 0)      hit = BounceLong(ctx, lv[k].price, m, got, c);         // R8
            else                    hit = BreakRetestLong(ctx, lv[k].price, m, got, c);    // R7
         }
         else
         {
            if(lv[k].type > 0)      hit = RejectionShort(ctx, lv[k].price, m, got, c);     // R9
            else                    hit = BreakRetestShort(ctx, lv[k].price, m, got, c);   // R7 (down)
         }
         if(!hit || !c.found) continue;
         c.conf = lv[k].conf;                                         // R3 -> R4 sizing and R14 scoring
         double dist = MathAbs(ctx.mid - c.level);
         if(dist > near) continue;                                    // "enter as close to the level as possible"
         if(!out.found || c.conf > out.conf || (c.conf == out.conf && dist < MathAbs(ctx.mid - out.level)))
            out = c;
      }
      return out.found;
   }

   //--- R8 BOUNCE: bodies above the support, wicks probing below, stop at the lowest wick
   bool BounceLong(const SEAContext &ctx, const double level, const MqlRates &m[], const int got, SPaSetup &out)
   {
      if(!(ctx.mid > level)) return false;                            // price approaches from above
      double atr = ctx.atr;
      int    look = (int)MathMax(1, MathMin(InpBounceBars, got - 1));
      int    hold = 0, newest = -1;
      double lowest = 0.0;
      for(int i = 1; i <= look; i++)
      {
         if(MathMin(m[i].open, m[i].close) > level && m[i].low < level)
         {
            hold++;
            if(lowest == 0.0 || m[i].low < lowest) lowest = m[i].low;
            if(newest < 0) newest = i;
         }
      }
      if(hold < InpBounceMinBodies || newest != 1) return false;      // the pattern must include the newest bar
      if((level - lowest) > InpMaxProbeAtr * atr) return false;       // the probes must stay small
      out.found = true; out.kind = 2; out.dir = +1;
      out.level = level; out.stopLevel = lowest;
      return true;
   }

   //--- R9 REJECTION: bodies below the resistance, wicks pushing up, stop at the highest wick
   bool RejectionShort(const SEAContext &ctx, const double level, const MqlRates &m[], const int got, SPaSetup &out)
   {
      if(!(ctx.mid < level)) return false;                            // price approaches from below
      double atr = ctx.atr;
      int    look = (int)MathMax(1, MathMin(InpBounceBars, got - 1));
      int    hold = 0, newest = -1;
      double highest = 0.0;
      for(int i = 1; i <= look; i++)
      {
         if(MathMax(m[i].open, m[i].close) < level && m[i].high > level)
         {
            hold++;
            if(m[i].high > highest) highest = m[i].high;
            if(newest < 0) newest = i;
         }
      }
      if(hold < InpBounceMinBodies || newest != 1) return false;
      if((highest - level) > InpMaxProbeAtr * atr) return false;
      out.found = true; out.kind = 3; out.dir = -1;
      out.level = level; out.stopLevel = highest;
      return true;
   }

   //--- R7 BREAK AND RETEST (up): a 5-minute close above the level, then the retest that holds
   bool BreakRetestLong(const SEAContext &ctx, const double level, const MqlRates &m[], const int got, SPaSetup &out)
   {
      if(!(ctx.mid > level)) return false;                            // the break has happened
      double atr = ctx.atr;
      if(!(m[1].low <= level + InpTouchTolAtr * atr)) return false;   // the retest came back to the level
      if(!(m[1].close > level)) return false;                         // and closed back above
      if(!(MathMin(m[1].open, m[1].close) > level)) return false;     // "body above it"
      double probe = (m[1].low < level) ? (level - m[1].low) : 0.0;
      if(probe > InpMaxProbeAtr * atr) return false;                  // "small wick below the level"
      int look = (int)MathMax(3, MathMin(InpRetestLookback, got - 1));
      bool broke = false;
      for(int j = 2; j <= look; j++)
         if(m[j].close > level && m[j].close > m[j].open) { broke = true; break; }
      if(!broke) return false;
      out.found = true; out.kind = 1; out.dir = +1;
      out.level = level; out.stopLevel = m[1].low;                    // "stop-loss just below the wick"
      return true;
   }

   //--- R7 BREAK AND RETEST (down): a 5-minute close below the level, then the retest that fails
   bool BreakRetestShort(const SEAContext &ctx, const double level, const MqlRates &m[], const int got, SPaSetup &out)
   {
      if(!(ctx.mid < level)) return false;
      double atr = ctx.atr;
      if(!(m[1].high >= level - InpTouchTolAtr * atr)) return false;
      if(!(m[1].close < level)) return false;
      if(!(MathMax(m[1].open, m[1].close) < level)) return false;     // "body below it"
      double probe = (m[1].high > level) ? (m[1].high - level) : 0.0;
      if(probe > InpMaxProbeAtr * atr) return false;
      int look = (int)MathMax(3, MathMin(InpRetestLookback, got - 1));
      bool broke = false;
      for(int j = 2; j <= look; j++)
         if(m[j].close < level && m[j].close < m[j].open) { broke = true; break; }
      if(!broke) return false;
      out.found = true; out.kind = 1; out.dir = -1;
      out.level = level; out.stopLevel = m[1].high;
      return true;
   }

   //--- R14: 2R (floored at 1.5R), capped by the next level beyond the entry
   bool BestTarget(const SEAContext &ctx, const SPaLevel &lv[], const int n, const int dir,
                   const double entry, const double risk, double &target)
   {
      double need = InpMinRR * risk;
      double dist = InpTargetR * risk;
      double next = NextLevelDist(lv, n, dir, entry);
      if(next > 0.0 && next >= need) dist = MathMin(dist, next);      // "targeting the next lower level"
      if(dist < need) dist = need;
      target = (dir > 0) ? entry + dist : entry - dist;
      return (target > 0.0);
   }

   //--- the nearest level strictly beyond the entry in the trade's direction
   double NextLevelDist(const SPaLevel &lv[], const int n, const int dir, const double entry)
   {
      double best = 0.0;
      for(int k = 0; k < n; k++)
      {
         double d = (dir > 0) ? (lv[k].price - entry) : (entry - lv[k].price);
         if(d <= 0.0) continue;
         if(best == 0.0 || d < best) best = d;
      }
      return best;
   }

   //--- R5: the 2-minute bar agrees with the 5-minute pattern
   bool M2Aligned(const SEAContext &ctx, const int dir)
   {
      MqlRates q[];
      if(EA_Rates(ctx.symbol, PERIOD_M2, 0, 3, q) < 2) return true;   // no M2 history -> the M5 read stands
      if(dir > 0) return (q[1].close > q[1].open);
      return (q[1].close < q[1].open);
   }

   //--- R19: which side was aggressive (ask vs bid transactions).  MT5 has no bid/ask
   //--- executed volume, so the proxy is body-directional tick volume - labelled.
   double VolumeLean(const string sym, const int bars)
   {
      MqlRates r[];
      int got = EA_Rates(sym, g_eaIndTf, 1, (int)MathMax(4, bars), r);
      if(got < 4) return 0.0;
      double up = 0.0, dn = 0.0;
      for(int i = 0; i < got; i++)
      {
         double v = (double)r[i].tick_volume;
         if(r[i].close > r[i].open) up += v;
         else if(r[i].close < r[i].open) dn += v;
      }
      if(up + dn <= 0.0) return 0.0;
      return (up - dn) / (up + dn);
   }

   //--- R10: entries today at this level, straight from the day's deal history
   int SameSetupAttempts(const SEAContext &ctx, const double level, const double tol)
   {
      MqlDateTime dt;
      TimeToStruct(ctx.nowClock, dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      datetime from = EA_ClockToServer(StructToTime(dt));
      if(!HistorySelect(from, TimeTradeServer() + 60)) return 0;
      int n = 0;
      int deals = HistoryDealsTotal();
      for(int i = 0; i < deals; i++)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != g_eaCfg.magic) continue;
         if(HistoryDealGetString(t, DEAL_SYMBOL) != ctx.symbol) continue;
         if((long)HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
         if(MathAbs(HistoryDealGetDouble(t, DEAL_PRICE) - level) <= tol) n++;
      }
      return n;
   }

   double Score(const SPaSetup &s, const bool volOk)
   {
      double score = 55.0 + s.conf * 5.0;                             // the level's confidence carries the score
      if(s.kind == 1) score += 5.0;                                   // the break-retest is the playbook's flagship
      if(volOk) score += 6.0;                                         // R19 confirmation
      return MathMin(score, 100.0);
   }

   string PatternName(const int kind)
   {
      if(kind == 1) return "break and retest";
      if(kind == 2) return "bounce";
      if(kind == 3) return "rejection";
      return "setup";
   }

   double LevelAtr(const SEAContext &ctx)
   {
      if(ctx.atrH1 > 0.0) return ctx.atrH1;
      return ctx.atr;                                                 // fall back to the signal-timeframe ATR
   }
};

CCfPriceAction g_cfPriceAction;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfPriceAction);
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
