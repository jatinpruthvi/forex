//+------------------------------------------------------------------+
//|            EA_CF_PriceCycleContinuationFailedBaseStrategy.mq5     |
//|                                  Copyright 2026, Master Strategy  |
//|                                                                   |
//| ChartFanatics: Price Cycle Continuation & Failed Base              |
//| "Market Cycles: The 500% Champion's Long & Short Strategy"         |
//| Card    : chartfanatics/todos/price-cycle-continuation-failed-     |
//|           base-strategy.md                                 (#32)   |
//| Source  : chartfanatics/glimpse/0_NSmOWVbpA.md                     |
//| Magic   : 3235                                                    |
//|                                                                   |
//| Both sides of the champion's cycle playbook, as documented:        |
//|                                                                   |
//|   L1  THE BULLISH CYCLE is a continuation inside an established    |
//|       uptrend - "wedge pop, EMA cross-back, base formation, and    |
//|       breakout".  Context: price above the 200-day EMA and a       |
//|       rising 50-day EMA.                                           |
//|   L2  BASE FORMATION: a tight consolidation on receding volume     |
//|       ("receding volume during consolidation signals low supply"). |
//|   L3  ENTRY 1 - BUYING ON STRENGTH: "Buy when price breaks above   |
//|       the horizontal consolidation level (the breakout level)      |
//|       with confirmation.  Set stop loss at the low of the current  |
//|       or prior day".  Confirmation = "large volume on the wedge    |
//|       pop confirms demand".                                        |
//|   L4  ENTRY 2 - BUYING ON WEAKNESS: "buy pullbacks into the 10 and |
//|       20-day EMAs ... tighter risk-reward than buying on           |
//|       strength".                                                   |
//|   L5  STOCK SELECTION: "at least $50 million average daily dollar  |
//|       volume, more than 3% average daily range (ADR), strong       |
//|       group momentum, and relative strength versus the market".    |
//|   L6  SCALING: "Take 1/3 of position off when profit reaches 2x    |
//|       the average daily range.  Take another 1/3 when price        |
//|       extends 8-10x ATR from the 50-day moving average.  Trail the |
//|       final 1/3 using the 10 or 20-day EMA as a stop, exiting on   |
//|       violation."                                                  |
//|   L7  TIMEFRAMES: "Daily chart is used for setup identification    |
//|       and context, while 5-minute chart is used for precise entry  |
//|       timing" - the engine's M5 signal phase does exactly this.    |
//|                                                                   |
//|   S1  THE FAILED BASE: stocks that "formed a base, attempted to    |
//|       break out but failed - a late-stage failed base pattern".    |
//|   S2  INVALIDATION: "violates its 20-day exponential moving        |
//|       average on larger volume than recent bars".                  |
//|   S3  WEDGE RECOVERY: "attempt a recovery but form a wedge on      |
//|       minimal volume - this shows weak buying demand" (a lower     |
//|       high that fails to reclaim the base).                        |
//|   S4  ENTRY: "Short the turn lower with stop just above the high   |
//|       of day."                                                     |
//|   S5  MARKET CONFIRMATION: "Ideal short entries occur when the     |
//|       broader market (QQQ) is also declining".                     |
//|   S6  COVERS: "Cover half the position when price undercuts prior  |
//|       lows and then reclaims them ... Cover the remaining half     |
//|       when price reclaims the 10-day EMA."                         |
//|   S7  RE-ENTRY DISCIPLINE: "limit re-entries to a maximum of 3     |
//|       attempts per ticker".                                        |
//|                                                                   |
//| `[interpretation]`: the video-derived document states the numbers  |
//| it states (50M, 3%, 2x ADR, 8-10x ATR, 1/3s, 20 EMA, 10 EMA, 3    |
//| attempts) and leaves the rest to the trader; every remaining       |
//| number - the base window and its tightness, the pullback           |
//| tolerance, the volume ratios, the relative-strength threshold,     |
//| the stop buffers, the wedge lookback and the far take-profit       |
//| placeholder - is an input and labelled.                            |
//|                                                                   |
//| Disclosed, not faked: reading "the biggest winners year by year",  |
//| the AI/fundamental research, the cycle opinion (30% anticipation)  |
//| and the monitor setup are human.  The market proxy is an input     |
//| (QQQ analogue `InpMarketSymbol`), and the dollar-volume filter     |
//| needs share volume: brokers that publish none fall back to tick    |
//| volume (labelled).                                                 |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics Price Cycle Continuation & Failed Base - bullish continuation longs and failed-base shorts with the champion's scaling"

#include "..\..\Include\EACommon.mqh"

enum ENUM_CF_PC_SIDE
{
   CF_PC_LONG  = 0,   // Longs only (bullish cycle continuation)
   CF_PC_SHORT = 1,   // Shorts only (failed base)
   CF_PC_BOTH  = 2    // Both sides
};

//--- identity / risk
input string            InpSymbolsToTrade     = "AAPL,MSFT,NVDA";  // Universe (stocks, per the playbook)
input string            InpMarketSymbol       = "US100";           // Market proxy (the doc's QQQ analogue)
input ulong             InpMagicNumber        = 3235;              // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_CF_PC_SIDE   InpSide               = CF_PC_BOTH;        // Which side of the cycle to trade
input double            InpRiskPct            = 0.40;              // Risk per trade (% of equity)
input int               InpStage              = 5;                 // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input double            InpMaxSpreadPoints    = 5.0;               // Spread gate in points (0 = off)
input double            InpDailyLossPct       = 1.50;              // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset    = 2;                 // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel           = EA_LOG_EVENTS;     // Log verbosity
input double            InpCommissionPerLotRT = 0.0;               // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.12;              // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;              // Write the engine evidence ledger CSV

//--- L5 stock selection
input double            InpMinAdvUsd          = 50000000.0;        // "$50 million average daily dollar volume"
input double            InpMinAdrPct          = 3.0;               // "more than 3% average daily range (ADR)"
input int               InpAdrDays            = 20;                // Window for ADR / ADV
input double            InpMinRsPct           = 2.0;               // [interpretation] Relative strength vs market (20-day)

//--- L1/L2 the bullish cycle and its base
input int               InpBaseBars           = 10;                // [interpretation] Base window (days)
input double            InpBaseMaxPct         = 12.0;              // [interpretation] Base tightness (range % of price)
input double            InpBaseMaxVolFrac     = 0.90;              // "receding volume during consolidation"
input double            InpBreakoutVolMult    = 1.20;              // "large volume on the wedge pop confirms demand"

//--- L3/L4 the two long entries
input double            InpPullTolPct         = 1.00;              // [interpretation] How near the 10/20 EMA counts as a pullback
input double            InpStopBufferAtr      = 0.15;              // [interpretation] Buffer beyond the risk level (daily ATR)
input double            InpMaxStopPct         = 12.0;              // [interpretation] Reject stops wider than x% of price

//--- L6 the long scaling (2x ADR / 8-10x ATR / EMA trail)
input double            InpAdrProfitMult      = 2.0;               // "profit reaches 2x the average daily range"
input double            InpPartial1Pct        = 33.4;              // "Take 1/3 of position off"
input double            InpAtrExtMult         = 8.0;               // "8-10x ATR from the 50-day moving average"
input double            InpPartial2Pct        = 33.4;              // "Take another 1/3"
input int               InpTrailEma           = 10;                // "Trail the final 1/3 using the 10 or 20-day EMA"
input double            InpLongTpR            = 12.0;              // [interpretation] Far TP placeholder - the trail is the exit

//--- S1-S4 the failed base
input int               InpFailBaseLookback   = 25;                // [interpretation] Days the failed breakout stays valid
input double            InpInvalidVolMult     = 1.20;              // "larger volume than recent bars" (x recent average)
input double            InpWeakVolFrac        = 0.80;              // "wedge on minimal volume" (x recent average)
input int               InpWedgeLookback      = 10;                // [interpretation] Days the recovery wedge may take
input double            InpShortTpR           = 10.0;              // [interpretation] Far TP placeholder - the covers are the exit
input int               InpMaxShortAttempts   = 3;                 // "maximum of 3 attempts per ticker"

//--- S6 the short covers
input int               InpPriorLowBars       = 10;                // [interpretation] The "prior lows" the undercut refers to

//--- session (entries timed on the US day, positions held across days)
input int               InpSessionStartHour   = 14;                // US RTH open, London time (09:30 ET)
input int               InpSessionStartMin    = 30;
input int               InpSessionEndHour     = 21;                // US RTH close - the 5-minute execution window
input int               InpSessionEndMin      = 0;
input int               InpMaxTradesPerDay    = 3;                 // [interpretation] Attempts across all setups per day

//+------------------------------------------------------------------+
struct SCycleCtx
{
   //--- daily context
   double ema10, ema20, ema50, ema200;
   double adr;                // average daily range in price
   double adrPct;             // ... as a percentage
   double advUsd;             // average daily dollar volume
   double rs20;               // 20-day relative strength vs the market (%)
   double baseHigh, baseLow;  // the last completed base
   double swingLow;           // recent low the short covers reference
   bool   near10, near20;     // price pulled back into the 10 / 20 EMA
   bool   brokeOut;           // d[1] closed above the base with volume
   bool   failedBase;         // S1: a base whose breakout failed
   double failedBaseHigh;     // the high the recovery must fail to reclaim
   bool   invalidated;        // S2: 20 EMA violated on larger volume
   int    invalidBar;         // days since that violation (1 = yesterday)
   bool   weakRecovery;       // S3: recovered on minimal volume to a lower high
   double recoveryHigh;       // the wedge's high
   bool   marketDown;         // S5: the market proxy is declining
};

//+------------------------------------------------------------------+
class CCfPriceCycle : public CEAStrategy
{
public:
   void OnInitStrategy()
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("5-stage policy: stage %d active (risk %.3f%%, %d trades/day max)",
             InpStage, g_eaCfg.riskPct, g_eaCfg.maxTradesPerDay), true);
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "Price Cycle armed: side %s, base %d days, %.0fx ADR / %.0fx ATR scaling, failed-base shorts with covers",
             SideName(), InpBaseBars, InpAdrProfitMult, InpAtrExtMult), true);
   }

   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_PRICE_CYCLE";
      cfg.sourceDoc             = "chartfanatics/glimpse/0_NSmOWVbpA.md (card #32)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;      // "5-minute chart for precise entry timing" (L7)
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = 4.0;
      cfg.totalDdPct            = 10.0;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 300;
      cfg.sessionStartHour      = InpSessionStartHour;
      cfg.sessionStartMin       = InpSessionStartMin;
      cfg.sessionEndHour        = InpSessionEndHour;
      cfg.sessionEndMin         = InpSessionEndMin;
      cfg.sessionEndFlat        = false;          // the doc holds for days (AFRM: a 20% move in 3 days)
      cfg.fridayFlat            = false;          // no weekend rule in the document
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = false;
      cfg.partial1AtR           = 0.0;            // the doc's scaling is price/volatility based - hand-rolled in Manage()
      cfg.partial2AtR           = 0.0;
      cfg.breakEvenAtR          = 0.0;            // the document states no break-even rule
      cfg.trailAtR              = 0.0;            // the EMA trail is the document's own - see Manage()
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_price_cycle_ledger.csv";
      cfg.newsFilter            = false;
      cfg.logLevel              = InpLogLevel;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   //+----------------------------------------------------------------+
   //| Signal phase: the D1 context first (both sides), then the long |
   //| continuation or the failed-base short (L1-L7 / S1-S5).          |
   //+----------------------------------------------------------------+
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession || ctx.atr <= 0.0) return false;

      SCycleCtx c;
      if(!DailyContext(ctx, c)) return false;

      //--- S7/S3: the short re-entry cap counts the day's deals on this symbol
      if((InpSide == CF_PC_SHORT || InpSide == CF_PC_BOTH) &&
         ShortAttempts(ctx) >= InpMaxShortAttempts) return false;

      double best = -1.0;
      if(InpSide == CF_PC_LONG || InpSide == CF_PC_BOTH)
      {
         SSignalPlan p;
         if(LongPlan(ctx, c, p) && p.score > best) { plan = p; best = p.score; }
      }
      if(InpSide == CF_PC_SHORT || InpSide == CF_PC_BOTH)
      {
         SSignalPlan p;
         if(ShortPlan(ctx, c, p) && p.score > best) { plan = p; best = p.score; }
      }
      return (plan.dir != 0);
   }

   //+----------------------------------------------------------------+
   //| The document's own management: the 1/3 - 1/3 - trail scaling    |
   //| for longs, the undercut-and-rally / EMA10 covers for shorts.    |
   //+----------------------------------------------------------------+
   void Manage(SEAContext &ctx)
   {
      ulong ticket = EA_FindPosition(ctx.symbol, -1);            // shorts first
      if(ticket > 0) { ManageShort(ctx, ticket); return; }
      ticket = EA_FindPosition(ctx.symbol, +1);
      if(ticket > 0) ManageLong(ctx, ticket);
   }

private:
   string SideName()
   {
      if(InpSide == CF_PC_LONG)  return "longs";
      if(InpSide == CF_PC_SHORT) return "shorts";
      return "both sides";
   }

   //--- per-ticket one-shot flags, persisted like the engine's own (risk keys)
   string FlagKey(const ulong ticket, const string tag)
   {
      return "CFPC_" + IntegerToString((long)g_eaCfg.magic) + "_" + IntegerToString((long)ticket) + "_" + tag;
   }
   bool FlagDone(const ulong ticket, const string tag)
   {
      return GlobalVariableCheck(FlagKey(ticket, tag));
   }
   void FlagSet(const ulong ticket, const string tag)
   {
      GlobalVariableSet(FlagKey(ticket, tag), 1.0);
   }

   //--- daily EMA on a close series (newest-first)
   double EmaOf(const MqlRates &r[], const int got, const int period)
   {
      return EmaOfAt(r, got, period, 0);
   }

   //--- ... and the same EMA as it stood `offset` bars ago (newest-first input)
   double EmaOfAt(const MqlRates &r[], const int got, const int period, const int offset)
   {
      if(got < period + offset + 2 || period < 2) return 0.0;
      double k = 2.0 / (period + 1.0);
      double ema = r[got - 1].close;                            // seed at the oldest close
      for(int i = got - 2; i >= offset; i--) ema = r[i].close * k + ema * (1.0 - k);
      return ema;
   }

   //+----------------------------------------------------------------+
   //| The whole daily map: EMAs, ADR, ADV, relative strength, the     |
   //| base, the failed base and its wedge, the market read.           |
   //+----------------------------------------------------------------+
   bool DailyContext(const SEAContext &ctx, SCycleCtx &c)
   {
      c.ema10 = 0; c.ema20 = 0; c.ema50 = 0; c.ema200 = 0;
      c.adr = 0; c.adrPct = 0; c.advUsd = 0; c.rs20 = 0;
      c.baseHigh = 0; c.baseLow = 0; c.swingLow = 0;
      c.near10 = false; c.near20 = false; c.brokeOut = false;
      c.failedBase = false; c.failedBaseHigh = 0; c.invalidated = false;
      c.invalidBar = 0; c.weakRecovery = false; c.recoveryHigh = 0; c.marketDown = false;

      int want = MathMax(240, InpFailBaseLookback + InpWedgeLookback + 40);
      MqlRates d[];
      int got = EA_Rates(ctx.symbol, PERIOD_D1, 0, want, d);
      if(got < 220) return false;

      c.ema10  = EmaOf(d, MathMin(got, 60),  10);
      c.ema20  = EmaOf(d, MathMin(got, 80),  20);
      c.ema50  = EmaOf(d, MathMin(got, 160), 50);
      c.ema200 = EmaOf(d, got, 200);
      if(c.ema10 <= 0.0 || c.ema20 <= 0.0 || c.ema50 <= 0.0 || c.ema200 <= 0.0) return false;

      //--- ADR / ADV windows
      int n = (int)MathMax(5, MathMin(InpAdrDays, got - 2));
      double rangeSum = 0.0, dollarSum = 0.0;
      for(int i = 1; i <= n; i++)
      {
         rangeSum  += (d[i].high - d[i].low) / MathMax(d[i].close, 0.0001);
         dollarSum += (double)d[i].tick_volume * d[i].close;
      }
      c.adr    = (rangeSum / n) * d[1].close;
      c.adrPct = rangeSum / n * 100.0;
      c.advUsd = dollarSum / n;

      //--- L5 relative strength: the stock's 20-day return minus the market's
      MqlRates mkt[];
      int mgot = EA_Rates(InpMarketSymbol, PERIOD_D1, 0, 40, mkt);
      if(mgot > 21 && d[21].close > 0.0 && mkt[21].close > 0.0)
      {
         double stockRet = (d[1].close - d[21].close) / d[21].close * 100.0;
         double mktRet   = (mkt[1].close - mkt[21].close) / mkt[21].close * 100.0;
         c.rs20 = stockRet - mktRet;
         //--- S5: the market proxy is declining (below its 20-day EMA)
         double mktEma = EmaOf(mkt, mgot, 20);
         c.marketDown = (mktEma > 0.0 && mkt[1].close < mktEma);
      }

      //--- the last completed base (d[2..baseBars+1]) before yesterday
      int bFirst = 2, bLast = 2 + InpBaseBars - 1;
      if(bLast + 1 >= got) return false;
      c.baseHigh = d[bFirst].high; c.baseLow = d[bFirst].low;
      double baseVol = 0.0, priorVol = 0.0;
      for(int i = bFirst; i <= bLast; i++)
      {
         c.baseHigh = MathMax(c.baseHigh, d[i].high);
         c.baseLow  = MathMin(c.baseLow,  d[i].low);
         baseVol += (double)d[i].tick_volume;
      }
      int pFirst = bLast + 1, pLast = bLast + InpBaseBars;
      for(int i = pFirst; i <= pLast && i < got; i++) priorVol += (double)d[i].tick_volume;
      baseVol  /= InpBaseBars;
      priorVol /= InpBaseBars;

      //--- L2: tight consolidation on receding volume ("low supply")
      bool tight   = ((c.baseHigh - c.baseLow) / MathMax(d[1].close, 0.0001) * 100.0) <= InpBaseMaxPct;
      bool receding = (priorVol <= 0.0) || (baseVol <= InpBaseMaxVolFrac * priorVol);
      double ema50Then = EmaOfAt(d, got, 50, 10);
      bool rising50 = (ema50Then > 0.0 && c.ema50 > ema50Then);        // the established uptrend: the 50 EMA is rising

      //--- L1: the bullish context - above the 200 EMA with the 50 EMA rising
      c.brokeOut = (d[1].close > c.baseHigh && d[1].close > d[1].open)
                && ((double)d[1].tick_volume >= InpBreakoutVolMult * baseVol)
                && tight && receding && rising50
                && d[1].close > c.ema200 && c.ema50 > c.ema200;

      //--- L4: the pullback into the 10 / 20 EMA
      double tol = InpPullTolPct / 100.0;
      c.near10 = (d[1].low <= c.ema10 * (1.0 + tol) && d[1].close > c.ema10 && d[1].close > c.ema200);
      c.near20 = (d[1].low <= c.ema20 * (1.0 + tol) && d[1].close > c.ema20 && d[1].close > c.ema200);

      //--- S1: the failed base - a tight base whose breakout attempt failed
      //--- (price poked above the base high and closed back below it)
      for(int i = 1; i <= InpFailBaseLookback && i + InpBaseBars + 1 < got; i++)
      {
         double bHi = d[i + 1].high, bLo = d[i + 1].low;
         for(int k = i + 1; k <= i + InpBaseBars; k++)
         {
            bHi = MathMax(bHi, d[k].high);
            bLo = MathMin(bLo, d[k].low);
         }
         bool baseTight = ((bHi - bLo) / MathMax(d[i].close, 0.0001) * 100.0) <= InpBaseMaxPct;
         bool poked  = (d[i].high > bHi);
         bool failed = (d[i].close < bHi);
         if(baseTight && poked && failed)
         {
            c.failedBase = true;
            c.failedBaseHigh = bHi;
            break;
         }
      }

      //--- S2: the 20-EMA violation on larger volume ("a shift in character")
      double ema20Now = c.ema20;                                // the live 20 EMA is the violation gate's reference
      for(int i = 1; i <= InpWedgeLookback + 15 && i + 12 < got; i++)
      {
         double avg = 0.0;
         for(int k = i + 1; k <= i + 10; k++) avg += (double)d[k].tick_volume;
         avg /= 10.0;
         if(d[i].close < ema20Now && (double)d[i].tick_volume >= InpInvalidVolMult * avg)
         { c.invalidated = true; c.invalidBar = i; break; }
      }

      //--- S3: the wedge recovery - back above/into the 20 EMA on minimal volume,
      //--- stalling at a lower high than the failed base
      if(c.invalidated && c.invalidBar > 1)
      {
         double recHi = 0.0, recVol = 0.0;
         int recBars = 0;
         for(int i = 1; i < c.invalidBar; i++)
         {
            recHi = MathMax(recHi, d[i].high);
            recVol += (double)d[i].tick_volume;
            recBars++;
         }
         if(recBars > 0)
         {
            recVol /= recBars;
            double recentAvg = 0.0;
            for(int k = c.invalidBar + 1; k <= c.invalidBar + 10 && k < got; k++) recentAvg += (double)d[k].tick_volume;
            recentAvg /= 10.0;
            bool minimalVol = (recentAvg <= 0.0) || (recVol <= InpWeakVolFrac * recentAvg);
            bool lowerHigh  = (recHi > 0.0 && recHi < c.failedBaseHigh);
            bool recovered  = (recHi >= c.ema20);              // the recovery reached back to the 20 EMA
            bool turning    = (d[1].close < c.ema20 && d[1].close < d[1].open);   // and now turns lower
            c.weakRecovery = (minimalVol && lowerHigh && recovered && turning);
            c.recoveryHigh = recHi;
         }
      }

      //--- S6: the prior lows the undercut references, and the swing low
      c.swingLow = d[1].low;
      for(int i = 1; i <= (int)MathMax(3, MathMin(InpPriorLowBars, got - 2)); i++)
         c.swingLow = MathMin(c.swingLow, d[i].low);
      return true;
   }

   //+----------------------------------------------------------------+
   //| L3/L4: the long side - buying on strength or on weakness.       |
   //+----------------------------------------------------------------+
   bool LongPlan(const SEAContext &ctx, const SCycleCtx &c, SSignalPlan &plan)
   {
      plan.Reset();
      if(!c.brokeOut && !c.near10 && !c.near20) return false;

      //--- L5 stock selection
      if(c.advUsd < InpMinAdvUsd) return false;
      if(c.adrPct < InpMinAdrPct) return false;
      if(c.rs20 < InpMinRsPct) return false;                    // "relative strength versus the market"

      double entry = ctx.ask;
      double stop  = 0.0;
      string why   = "";
      double score = 0.0;

      if(c.brokeOut)
      {
         //--- L3: stop at "the low of the current or prior day"
         MqlRates m[];
         int got = EA_Rates(ctx.symbol, PERIOD_D1, 0, 3, m);
         if(got < 2) return false;
         double dayLow = m[0].low;                              // the forming day's low so far
         stop = MathMin(dayLow, m[1].low) - InpStopBufferAtr * ctx.atrD1;
         why  = "breakout above the base with volume (buying on strength)";
         score = 78.0 + (c.rs20 > 5.0 ? 6.0 : 0.0);
      }
      else
      {
         //--- L4: the pullback buy - stop under the pullback low, tighter risk
         MqlRates m[];
         if(EA_Rates(ctx.symbol, PERIOD_D1, 0, 3, m) < 2) return false;
         stop = MathMin(m[1].low, c.near10 ? c.ema10 : c.ema20) - InpStopBufferAtr * ctx.atrD1;
         why  = c.near10 ? "pullback into the 10-day EMA (buying on weakness)"
                         : "pullback into the 20-day EMA (buying on weakness)";
         score = 70.0 + (c.rs20 > 5.0 ? 6.0 : 0.0);
      }
      if(stop <= 0.0 || stop >= entry) return false;
      double risk = entry - stop;
      if(risk <= 0.0 || risk > entry * InpMaxStopPct / 100.0) return false;

      plan.dir      = +1;
      plan.entry    = entry;
      plan.stop     = stop;
      plan.target   = entry + InpLongTpR * risk;                // far by design - the scaling/trail is the exit
      plan.riskDist = risk;
      plan.barsAgo  = 1;
      plan.score    = MathMin(score, 100.0);
      plan.isLimit  = false;
      plan.reason   = StringFormat("%s: ADR %.1f%%, RS %.1f%%, base %.2f-%.2f",
                                   why, c.adrPct, c.rs20, c.baseLow, c.baseHigh);
      return true;
   }

   //+----------------------------------------------------------------+
   //| S1-S5: the failed-base short.                                   |
   //+----------------------------------------------------------------+
   bool ShortPlan(const SEAContext &ctx, const SCycleCtx &c, SSignalPlan &plan)
   {
      plan.Reset();
      if(!c.failedBase || !c.invalidated || !c.weakRecovery) return false;
      if(!c.marketDown) return false;                           // S5: "wind at your back"

      //--- S4: stop just above the high of day (the recovery/wedge high)
      MqlRates m[];
      if(EA_Rates(ctx.symbol, PERIOD_D1, 0, 2, m) < 2) return false;
      double stopLevel = MathMax(m[0].high, c.recoveryHigh);
      if(stopLevel <= 0.0) return false;
      double entry = ctx.bid;
      double stop  = stopLevel + InpStopBufferAtr * ctx.atrD1;
      if(stop <= entry) return false;
      double risk = stop - entry;
      if(risk > entry * InpMaxStopPct / 100.0) return false;

      plan.dir      = -1;
      plan.entry    = entry;
      plan.stop     = stop;
      plan.target   = entry - InpShortTpR * risk;               // far by design - the covers are the exit
      plan.riskDist = risk;
      plan.barsAgo  = 1;
      plan.score    = 76.0;
      plan.isLimit  = false;
      plan.reason   = StringFormat("failed base: 20 EMA violated on volume (d-%d), weak wedge to %.2f, market declining",
                                   c.invalidBar, c.recoveryHigh);
      return true;
   }

   //--- S7: how many shorts were already attempted on this symbol today
   int ShortAttempts(const SEAContext &ctx)
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
         //--- only sell-side entries count toward the short cap
         long type = (long)HistoryDealGetInteger(t, DEAL_TYPE);
         if(type == (long)DEAL_TYPE_SELL) n++;
      }
      return n;
   }

   //+----------------------------------------------------------------+
   //| L6: the long scaling - 1/3 at 2x ADR, 1/3 at 8-10x ATR from    |
   //| the 50-day EMA, then the 10/20 EMA trail on the final third.    |
   //+----------------------------------------------------------------+
   void ManageLong(const SEAContext &ctx, const ulong ticket)
   {
      if(!PositionSelectByTicket(ticket)) return;
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double adr   = DailyAdr(ctx.symbol);
      if(adr <= 0.0) return;

      double profit = ctx.bid - entry;
      if(!FlagDone(ticket, "P1") && profit >= InpAdrProfitMult * adr)         // "profit reaches 2x the ADR"
      {
         if(g_eaExec.ClosePartial(ticket, InpPartial1Pct) || !g_eaExec.CanPartial(ticket, InpPartial1Pct))
         {
            FlagSet(ticket, "P1");
            EA_Log(EA_LOG_EVENTS, StringFormat("Price Cycle: took the first 1/3 at %.2fx ADR", profit / adr), true);
         }
      }
      if(!FlagDone(ticket, "P2"))                                            // "8-10x ATR from the 50-day MA"
      {
         double ema50 = DailyEma(ctx.symbol, 50);
         double extTarget = (ema50 > 0.0) ? ema50 + InpAtrExtMult * ctx.atrD1 : 0.0;
         if(extTarget > 0.0 && ctx.bid >= extTarget)
         {
            if(g_eaExec.ClosePartial(ticket, InpPartial2Pct) || !g_eaExec.CanPartial(ticket, InpPartial2Pct))
            {
               FlagSet(ticket, "P2");
               EA_Log(EA_LOG_EVENTS, StringFormat("Price Cycle: took the second 1/3 at %.2f (50EMA + %.0fxATR)",
                      ctx.bid, InpAtrExtMult), true);
            }
         }
      }
      //--- "Trail the final 1/3 using the 10 or 20-day EMA as a stop, exiting on violation"
      if(FlagDone(ticket, "P2") && !FlagDone(ticket, "P3"))
      {
         double emaT = DailyEma(ctx.symbol, InpTrailEma);
         MqlRates d[];
         if(emaT > 0.0 && EA_Rates(ctx.symbol, PERIOD_D1, 0, 2, d) >= 2 && d[1].close < emaT)
         {
            if(g_eaExec.Close(ticket, StringFormat("daily close below the %d-day EMA - the trail exits", InpTrailEma)))
            {
               FlagSet(ticket, "P3");
               EA_Log(EA_LOG_EVENTS, StringFormat("Price Cycle: final third exited, close %.2f under EMA%d %.2f",
                      d[1].close, InpTrailEma, emaT), true);
            }
         }
      }
   }

   //+----------------------------------------------------------------+
   //| S6: the short covers - half on the undercut and rally, the      |
   //| rest when price reclaims the 10-day EMA.                        |
   //+----------------------------------------------------------------+
   void ManageShort(const SEAContext &ctx, const ulong ticket)
   {
      if(!PositionSelectByTicket(ticket)) return;
      MqlRates d[];
      if(EA_Rates(ctx.symbol, PERIOD_D1, 0, 3, d) < 2) return;

      //--- cover half: the undercut of the prior lows, then the reclaim of them
      if(!FlagDone(ticket, "C1"))
      {
         double priorLow = d[1].low;
         for(int i = 1; i <= (int)MathMax(3, MathMin(InpPriorLowBars, ArraySize(d) - 1)); i++)
            priorLow = MathMin(priorLow, d[i].low);
         bool undercut = (d[0].low < priorLow);
         bool reclaimed = (ctx.mid > priorLow);
         if(undercut && reclaimed)
         {
            if(g_eaExec.ClosePartial(ticket, 50.0) || !g_eaExec.CanPartial(ticket, 50.0))
            {
               FlagSet(ticket, "C1");
               EA_Log(EA_LOG_EVENTS, StringFormat("Price Cycle: covered half, undercut %.2f and reclaimed", priorLow), true);
            }
         }
      }
      //--- cover the rest: "when price reclaims the 10-day EMA"
      if(!FlagDone(ticket, "C2"))
      {
         double ema10 = DailyEma(ctx.symbol, 10);
         if(ema10 > 0.0 && d[1].close > ema10)
         {
            if(g_eaExec.Close(ticket, "price reclaimed the 10-day EMA - the cover completes"))
            {
               FlagSet(ticket, "C2");
               EA_Log(EA_LOG_EVENTS, StringFormat("Price Cycle: remaining cover, close %.2f over EMA10 %.2f",
                      d[1].close, ema10), true);
            }
         }
      }
   }

   double DailyAdr(const string sym)
   {
      MqlRates d[];
      int n = (int)MathMax(5, MathMin(InpAdrDays, 60));
      int got = EA_Rates(sym, PERIOD_D1, 1, n, d);
      if(got < 5) return 0.0;
      double sum = 0.0;
      for(int i = 0; i < got; i++) sum += (d[i].high - d[i].low);
      return sum / got;
   }

   double DailyEma(const string sym, const int period)
   {
      MqlRates d[];
      int want = (int)MathMax(period + 20, 60);
      int got = EA_Rates(sym, PERIOD_D1, 0, want, d);
      if(got < period + 2) return 0.0;
      return EmaOf(d, got, period);
   }
};

CCfPriceCycle g_cfPriceCycle;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfPriceCycle);
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
