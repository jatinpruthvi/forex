//+------------------------------------------------------------------+
//|            EA_CF_NasdaqIctAndOrderFlowScalpingStrategy.mq5        |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| "NASDAQ ICT and Order Flow Scalping Strategy"                     |
//| Abraham Perez - "Pass Prop Firms Using This ICT & Orderflow       |
//| Futures Trading Strategy ($600k+)", Chart Fanatics summary        |
//| Card    : chartfanatics/todos/nasdaq-ict-and-order-flow-scalping-strategy.md (#25)
//| Source  : chartfanatics/glimpse/KkTTCKr-3Ew.md                    |
//| Magic   : 3228                                                    |
//|                                                                    |
//| The document is a THREE-STEP system; the EA runs the three steps   |
//| in order and quotes the source in the code:                        |
//|                                                                    |
//|   STEP 1 - "Use 4-hour and daily charts to identify the overall    |
//|   trend and where price is in the liquidity cycle.  Markets move   |
//|   in trends with higher highs/lows, then pull back to fair value   |
//|   (internal range liquidity) before continuing."                   |
//|     MacroBias(): fractal H4 structure (higher highs + higher lows, |
//|     or the mirror), the D1 200-EMA as the sanity check, and the    |
//|     pullback depth of the newest leg inside                      |
//|     [InpRetraceMin, InpRetraceMax] - shallower means price has not |
//|     pulled back to fair value yet, deeper means a full reversal    |
//|     rather than a pullback.                                        |
//|                                                                    |
//|   STEP 2 - "On 15-minute and 1-hour charts, look for the secondary |
//|   structure (the pullbacks and impulses within the macro move).    |
//|   This structure must align with your macro bias. ... you need to  |
//|   see weakness in the secondary structure (volume, closure below   |
//|   previous highs) before shorting."                                |
//|     SecondaryAlign(): H1 lower highs + a close below the previous  |
//|     high + sell-side volume dominance - the document's own three  |
//|     ingredients - mirrored for longs.                              |
//|                                                                    |
//|   STEP 3 - the three entry models on M1 ("on 1m/5m/30s charts      |
//|   depending on asset volatility") plus the orderflow layer:        |
//|     * IFBG - "Price takes liquidity above a previous high, creates |
//|       a fair value gap, then closes with volume below that gap."   |
//|     * change of character (preferred) - "price reacts at support,  |
//|       makes a candle suggesting a sell, then manipulates with      |
//|       volume, breaks, retests, and closes below with volume".      |
//|       "Requires liquidity to be swept first for best performance." |
//|     * break and retest (continuation) - "Price breaks a level with |
//|       volume and retests it, then continues in the original        |
//|       direction.  Must see a fair value gap displacing the previous|
//|       high and retest closing above the apex".                     |
//|     * orderflow: "confirm with bookmap orderflow ... large volume  |
//|       spikes on the buy side ..., buyers are aggressive"; "If POC  |
//|       is moving down, bearish volume is dominating"; "If buyers    |
//|       can't push price above a level despite high buy volume,      |
//|       sellers are absorbing those buys - a bearish signal."        |
//|       OrderFlowAlign() demands all three reads for the direction.  |
//|                                                                    |
//| Risk and management follow the same document: M1 execution because |
//| "trading 5-minute charts results in huge stop-losses ... 1-minute  |
//| charts reveals crystal-clear structure and allows tight stops"    |
//| (setups needing more than InpMaxStopAtr of M1 ATR are skipped);    |
//| targets are the next liquidity pool - "targeting liquidity below"  |
//| and "took profit before hitting a strong resistance (previous      |
//| daily high)" - with a 1.5R floor; a partial is banked at 1R and    |
//| the stop trailed (the doc's "he trailed his stop"); and the two    |
//| discretionary exits are encoded: "he closed early rather than risk |
//| reversal" (a confirmed order-flow flip against the position) and   |
//| "close at break-even or skip the trade" when conditions turn       |
//| sketchy - the doc's own three examples: "low volume, piano-like    |
//| price action, macro opening volatility".                           |
//|                                                                    |
//| [interpretation]: bookmap's heatmap, volume dots and spoof         |
//| detection are NOT readable from an EA; the orderflow layer is a    |
//| tick-volume proxy (session POC, VWAP, aggression, absorption),     |
//| documented here and in the sync table.  "Watch for spoofing" stays |
//| a human task and is not faked in code.  The fractal strengths,     |
//| sweep tolerance, gap floors, freshness windows, aggression ratio,  |
//| POC bin count, sketchy thresholds, stop cap, target floor, partial |
//| and flip confirmation are engineering numbers the document does    |
//| not state, exposed as inputs.  The document's Asia preference is   |
//| the default window, but the New-York window ships alongside it     |
//| because a CFD broker's US100 may be closed or untradeably wide in  |
//| Asia while the doc trades CME NQ; the card says so too.  "No       |
//| mechanical strategies work long-term" is respected: the EA trades  |
//| only what the document states mechanically (the entry model layer) |
//| and skips everything else - "Skip any setup missing a layer".      |
//|                                                                    |
//| Rule -> code sync (see tests/test_chartfanatics_sync.py):          |
//|   R1  H4 macro + D1 check          -> MacroBias()                  |
//|   R2  higher highs/lows            -> MacroBias()                  |
//|   R3  pullback to fair value band   -> InpRetraceMin/Max in BuildPlan()
//|   R4  secondary weakness            -> SecondaryAlign()/VolumeWeakness()
//|   R5  IFBG                          -> ModelIfbg()                 |
//|   R6  change of character (swept first) -> ModelChoch()            |
//|   R7  break and retest + FVG        -> ModelBreakRetest()/HasGap() |
//|   R8  orderflow aggression          -> Aggression()/OrderFlowAlign()
//|   R9  POC vs VWAP                   -> OrderFlowAlign()            |
//|   R10 absorption                    -> AbsorptionFails()           |
//|   R11 Asia session                  -> InpWindow/Configure()       |
//|   R12 M1 execution + tight stops    -> cfg.signalTimeframe/StopOk()|
//|   R13 targets at the next pool      -> NextPool()                  |
//|   R14 close early on a flip         -> Manage()                    |
//|   R15 sketchy conditions            -> Sketchy()                   |
//|   R16 partial at 1R + trail         -> Configure()                 |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "NASDAQ ICT + order-flow scalping: H4/D1 macro context, H1 secondary structure, IFBG / change-of-character / break-retest entries on M1 with a session POC-VWAP-aggression proxy for bookmap, tight structural stops, liquidity-pool targets and a capital-preservation exit"

#include "..\..\Include\EACommon.mqh"

//--- session window (the document's own preference first)
enum ENUM_CF_WINDOW
{
   CF_WINDOW_ASIA    = 0,   // Asia - "clearer structure and less manipulation" (see header caveat)
   CF_WINDOW_NEWYORK = 1,   // New York
   CF_WINDOW_ALL     = 2    // every hour the symbol trades
};

//--- identity / risk
input string            InpSymbolsToTrade   = "US100";            // the document's instrument (NASDAQ)
input ulong             InpMagicNumber      = 3228;               // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct          = 0.50;               // Risk per trade (% of equity)
input int               InpStage            = 5;                  // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input int               InpServerGmtOffset  = 2;                  // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;      // Log verbosity
input double            InpCommissionPerLotRT = 0.0;              // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR         = 0.20;               // Cost gate: (spread + commission) <= xR
input bool              InpLedger           = true;               // Write the engine evidence ledger CSV
input double            InpMaxSpreadPoints  = 6.0;                // [interpretation] static spread ceiling (points)
//--- step 1: macro context (4h/daily)
input ENUM_TIMEFRAMES   InpMacroTf          = PERIOD_H4;          // "Use 4-hour and daily charts"
input int               InpMacroBars        = 120;                // H4 bars scanned for the macro structure
input int               InpMacroFractal     = 2;                  // swing strength that defines macro structure
input bool              InpUseD1Filter      = true;               // daily 200-EMA must agree with the macro bias
input double            InpRetraceMin       = 0.25;               // [interpretation] "pull back to fair value": min depth
input double            InpRetraceMax       = 0.90;               // [interpretation] deeper than this = full reversal, skip
//--- step 2: secondary structure (15m/1h)
input ENUM_TIMEFRAMES   InpSecondTf         = PERIOD_H1;          // "On 15-minute and 1-hour charts"
input int               InpSecondBars       = 96;                 // H1 bars scanned
input int               InpSecondFractal    = 2;                  // swing strength on the secondary chart
input int               InpWeaknessBars     = 12;                 // H1 bars the "weakness in the secondary structure" is read over
//--- step 3: entry models (M1 - the doc's 30s/1m execution)
input int               InpEntryBars        = 90;                 // M1 bars scanned for the models
input int               InpEntryFractal     = 1;                  // M1 pivot strength
input int               InpSweepLookback    = 20;                 // bars that define the prior high/low that gets swept
input int               InpLevelLookback    = 30;                 // bars that define the level being broken (continuation)
input double            InpSweepTolAtr      = 0.05;               // how far through counts as "liquidity taken"
input double            InpVolumeMult       = 1.30;               // "with volume" / aggression: x the window average
input double            InpImpulseBody      = 0.55;               // displacement candle body (FVG mid bar)
input double            InpMinGapAtr        = 0.08;               // fair value gap size floor
input int               InpModelFreshBars   = 30;                 // bars allowed between the trigger leg and the retest
input int               InpStructureBars    = 60;                 // bars searched for the broken structure level
//--- orderflow proxy (bookmap)
input int               InpProfileBars      = 360;                // M1 bars the session POC / VWAP are built from
input int               InpPocBins          = 40;                 // profile resolution
input int               InpAggressionBars   = 10;                 // bars the buy/sell aggression is read over
input int               InpAbsorbLookback   = 12;                 // bars the absorption high/low is read over
input int               InpFlipConfirmBars  = 2;                  // closed bars a flip must persist before it exits
input int               InpMinSessionBars   = 20;                 // [interpretation] profile maturity before the gates apply
//--- stops / targets / management
input double            InpMaxStopAtr       = 1.00;               // "tight stops": skip setups needing a wider stop (M1 ATR)
input double            InpStopBufferAtr    = 0.15;               // stop buffer beyond the structure
input double            InpMinTargetR       = 1.50;               // the next pool must beat this R floor ([interpretation])
input int               InpPoolDays         = 1;                  // prior-day extreme as the liquidity magnet
input int               InpPartialPct       = 50;                 // partial banked at 1R
input bool              InpBreakevenAfterPartial = true;          // the stop moves to break-even after the partial
input double            InpCloseSketchyR    = 0.50;               // sketchy market: close below this R ("capital preservation")
//--- sketchy-condition thresholds (the doc's three examples)
input double            InpSketchyVolMult   = 0.70;               // "low volume": recent pace vs session pace
input double            InpSketchyRangeAtr  = 4.00;               // "piano-like price action": session range in ATRs
input double            InpSketchyPocDom    = 1.20;               // "unclear POC": POC bin vs average bin volume
input double            InpBurstAtr         = 4.00;               // "macro opening volatility": single-bar range in ATRs
//--- session / patience
input ENUM_CF_WINDOW    InpWindow           = CF_WINDOW_ASIA;     // "Asia session on NASDAQ tends to have clearer structure"
input int               InpAsiaStartHour    = 0;                  // 00:00 London (Tokyo session)
input int               InpAsiaEndHour      = 8;                  // 08:00 London
input int               InpNyStartHour      = 14;                 // 14:30 London = 09:30 ET
input int               InpNyStartMin       = 30;
input int               InpNyEndHour        = 20;                 // 20:00 London = 15:00 ET
input int               InpMaxTradesPerDay  = 3;                  // "the most powerful tool that traders have is patience"

//--- one entry-model result
struct SCfEntry
{
   int      dir;         // +1 long, -1 short
   int      model;       // 1 = IFBG, 2 = change of character, 3 = break and retest
   int      sweepBar;    // bars-ago index of the sweep bar (-1 = the model has no sweep)
   double   entry;
   double   stop;
   double   score;
   string   reason;
};

//--- session order-flow state
struct SCfFlow
{
   double   poc;          // price bin with the most session volume
   double   vwap;         // session VWAP, "anchored to the open"
   double   pocDominance; // POC bin volume / average bin volume (0 = not computed)
   double   lastClose;    // last closed M1 close
   double   sessionHi;    // session high (closed bars of the clock day)
   double   sessionLo;    // session low
   double   sessionAvgVol;// average tick volume per closed session bar
   int      aggression;   // +1 buyers, -1 sellers, 0 unclear
   int      sessionBars;  // closed M1 bars inside the clock day
   bool     ok;
};

//+------------------------------------------------------------------+
class CCfNasdaqIctOrderFlow : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_NASDAQ_ICT_ORDERFLOW";
      cfg.sourceDoc             = "chartfanatics/glimpse/KkTTCKr-3Ew.md (card #25)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M1;          // "1-minute charts reveals crystal-clear structure and allows tight stops"
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.maxCostR              = InpMaxCostR;
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay; // "the most powerful tool that traders have is patience"
      cfg.maxOpenPositions      = 1;                  // one scalp at a time
      cfg.minSecondsBetweenTrades = 300;              // 5 minutes between scalps ([interpretation])
      cfg.dailyLossPct          = 1.50;
      cfg.weeklyLossPct         = 3.0;
      cfg.totalDdPct            = 8.0;
      cfg.useLimitEntry         = false;              // "waiting for price to come to you" is the model's retest, filled at market
      cfg.signalOnNewBarOnly    = true;
      cfg.newsFilter            = false;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_nasdaq_ict_ledger.csv";
      cfg.logLevel              = InpLogLevel;
      //--- "took profit before hitting a strong resistance": a partial is banked at 1R
      cfg.partial1AtR           = 1.0;
      cfg.partial1Pct           = (double)InpPartialPct;
      cfg.breakEvenAtR          = InpBreakevenAfterPartial ? 1.0 : 0.0;
      cfg.breakEvenOnBarClose   = true;
      //--- "He trailed his stop and took profit before hitting a strong resistance"
      cfg.trailAtR              = 1.0;
      cfg.trailDistanceR        = 0.5;
      //--- the session window (clock = London, like the rest of the family)
      int sh = InpAsiaStartHour, eh = InpAsiaEndHour, sm = 0, em = 0;
      if(InpWindow == CF_WINDOW_NEWYORK) { sh = InpNyStartHour; sm = InpNyStartMin; eh = InpNyEndHour; em = 0; }
      if(InpWindow == CF_WINDOW_ALL)     { sh = 0; sm = 0; eh = 23; em = 59; }
      cfg.sessionStartHour = sh; cfg.sessionStartMin = sm;
      cfg.sessionEndHour   = eh; cfg.sessionEndMin   = em;
      cfg.noTradeAfterHour = eh; cfg.noTradeAfterMin = em;      // no late entries in the window (patience)
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   void OnInitStrategy()
   {
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "NASDAQ ICT + order flow armed: macro %s (+ D1-EMA200 %s), secondary %s, entries on M1 (%d bars), window %s, tight-stop cap %.2f ATR, target floor %.1fR, partial %d%% at 1R",
             EnumToString(InpMacroTf), InpUseD1Filter ? "on" : "off", EnumToString(InpSecondTf),
             InpEntryBars, WindowName(), InpMaxStopAtr, InpMinTargetR, InpPartialPct), true);
      EA_Log(EA_LOG_EVENTS, "bookmap's heatmap is proxied by the session POC, VWAP and tick-volume aggression; spoof detection stays a human task", true);
      m_flowValid = false; m_flowKey = 0;           // the flow cache is rebuilt on the first tick
   }

   //-------------------------------------------------------------------
   // THE THREE STEPS
   //-------------------------------------------------------------------
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession || ctx.atr <= 0.0) return false;
      if(ctx.pastNoTradeHour) return false;

      SCfFlow flow;
      if(!EnsureFlow(ctx, flow) || !flow.ok) return false;      // no POC/VWAP = no order-flow read
      if(Sketchy(ctx, flow, true)) return false;                // "close at break-even or skip the trade"

      //--- step 1: the macro bias and the pullback depth ("pull back to fair value")
      double retrace = 0.0;
      int bias = MacroBias(ctx, retrace);
      if(bias == 0) return false;                               // no trend, no context
      if(retrace < InpRetraceMin || retrace > InpRetraceMax) return false;

      //--- steps 2 + 3 for both directions; the change of character model is preferred
      for(int k = 0; k < 2; k++)
      {
         int dir = (k == 0) ? -1 : +1;
         if(!SecondaryAlign(ctx, dir)) continue;                // step 2: "This structure must align with your macro bias"
         if(!OrderFlowAlign(ctx, flow, dir)) continue;          // "confirm with bookmap orderflow"

         SCfEntry e;
         bool found = ModelChoch(ctx, dir, e);                  // the document's preferred model
         if(!found) found = ModelIfbg(ctx, dir, e);             // the first model
         if(!found && bias == dir) found = ModelBreakRetest(ctx, dir, e);  // continuation needs the macro to agree
         if(!found) continue;

         double risk = MathAbs(e.entry - e.stop);
         if(risk <= 0.0) continue;
         double target = 0.0;
         if(!NextPool(ctx, dir, e.entry, risk, target)) continue;

         plan.dir          = dir;
         plan.entry        = e.entry;
         plan.stop         = e.stop;
         plan.target       = target;
         plan.riskDist     = risk;
         plan.score        = e.score;
         plan.reason       = e.reason;
         plan.isLimit      = false;
         plan.barsAgo      = 1;
         plan.sweepBarsAgo = e.sweepBar;
         return true;
      }
      return false;
   }

   //-------------------------------------------------------------------
   // Management: the two discretionary exits the document demonstrates
   //-------------------------------------------------------------------
   void Manage(SEAContext &ctx)
   {
      if(ctx.atr <= 0.0) return;
      SCfFlow flow;
      bool haveFlow = EnsureFlow(ctx, flow) && flow.ok;

      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong ticket = PositionGetTicket(p);
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;

         int dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? +1 : -1;
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double rMult = RMultiple(ticket, dir, entry);

         //--- "he closed early rather than risk reversal": a confirmed order-flow flip
         if(haveFlow && FlipPersists(ctx, flow, -dir, InpFlipConfirmBars))
         {
            string side = (dir > 0) ? "long" : "short";
            EA_Log(EA_LOG_EVENTS, StringFormat(
                   "position #%I64u: order flow flipped against the %s side for %d closed bars - closing early rather than risk reversal (%.2fR)",
                   ticket, side, InpFlipConfirmBars, rMult), true);
            g_eaExec.Close(ticket, "orderflow flipped - close early rather than risk reversal");
            continue;
         }

         //--- "close at break-even or skip the trade ... prioritize capital preservation"
         if(Sketchy(ctx, flow, false) && rMult < InpCloseSketchyR)
         {
            EA_Log(EA_LOG_EVENTS, StringFormat(
                   "position #%I64u: conditions turned sketchy (%.2fR) - closing for capital preservation",
                   ticket, rMult), true);
            g_eaExec.Close(ticket, "sketchy conditions - capital preservation");
         }
      }
   }

private:
   //--- session order-flow cache: Manage() runs on every tick, and the profile is
   //--- built from closed bars only, so it is recomputed once per closed M1 bar
   //--- (or when the clock day rolls over) instead of on every tick
   SCfFlow  m_flowCache;
   datetime m_flowKey;
   bool     m_flowValid;

   bool EnsureFlow(const SEAContext &ctx, SCfFlow &flow)
   {
      MqlRates m[];
      int got = EA_Rates(ctx.symbol, PERIOD_M1, 0, 2, m);
      if(got < 2) return false;
      if(m_flowValid && m_flowKey == m[1].time)
      {
         flow = m_flowCache;
         return flow.ok;
      }
      bool built = SessionFlow(ctx, flow);
      m_flowCache = flow;
      m_flowKey   = m[1].time;
      m_flowValid = true;                            // even a failed build is cached for this bar
      return built;
   }

   //-------------------------------------------------------------------
   // STEP 1 - macro context on the H4 chart + the D1 sanity check
   //-------------------------------------------------------------------
   int MacroBias(const SEAContext &ctx, double &retracePct)
   {
      retracePct = 0.0;
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, InpMacroTf, 0, InpMacroBars, r);
      if(got < InpMacroFractal * 4 + 10) return 0;

      double sh[], sl[];
      int    shBar[], slBar[];
      int nh = SwingHighs(r, got, InpMacroFractal, sh, shBar);
      int nl = SwingLows(r, got, InpMacroFractal, sl, slBar);
      if(nh < 2 || nl < 2) return 0;

      int bias = 0;
      if(sh[0] > sh[1] && sl[0] > sl[1]) bias = +1;             // "higher highs/lows"
      if(sh[0] < sh[1] && sl[0] < sl[1]) bias = -1;             // the mirror
      if(bias == 0) return 0;                                   // sideways = no context

      //--- "pull back to fair value": how far the newest leg has retraced from its extreme
      double hi = sh[0], lo = sl[0];
      if(hi <= lo) return 0;
      if(bias > 0) retracePct = (r[1].close - lo) / (hi - lo);  // bounce off the low of the leg
      else         retracePct = (hi - r[1].close) / (hi - lo);  // drop from the high of the leg

      //--- the daily sanity check (the engine's own D1 EMA200)
      if(InpUseD1Filter && ctx.emaD1_200 > 0.0 && ctx.mid > 0.0)
      {
         if(bias > 0 && ctx.mid < ctx.emaD1_200) return 0;
         if(bias < 0 && ctx.mid > ctx.emaD1_200) return 0;
      }
      return bias;
   }

   //-------------------------------------------------------------------
   // STEP 2 - secondary structure must agree with the intended direction
   //-------------------------------------------------------------------
   bool SecondaryAlign(const SEAContext &ctx, const int dir)
   {
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, InpSecondTf, 0, InpSecondBars, r);
      if(got < InpSecondFractal * 4 + 6) return false;

      double sh[], sl[];
      int    shBar[], slBar[];
      int nh = SwingHighs(r, got, InpSecondFractal, sh, shBar);
      int nl = SwingLows(r, got, InpSecondFractal, sl, slBar);

      //--- "you need to see weakness in the secondary structure (volume, closure below
      //---  previous highs) before shorting" - and the mirror for longs
      if(dir < 0)
      {
         if(nh < 2 || sh[0] >= sh[1]) return false;            // lower highs
         if(r[1].close >= sh[0]) return false;                 // closure below the previous high
         return VolumeWeakness(r, got, -1);                    // volume: sellers beating buyers
      }
      if(nl < 2 || sl[0] <= sl[1]) return false;                // higher lows
      if(r[1].close <= sl[0]) return false;                     // closure above the previous low
      return VolumeWeakness(r, got, +1);                        // volume: buyers beating sellers
   }

   //--- volume weakness: the last WeaknessBars secondary bars lean with `dir`
   bool VolumeWeakness(const MqlRates &r[], const int got, const int dir)
   {
      int n = (int)MathMin(InpWeaknessBars, got - 2);
      if(n < 4) return false;
      double up = 0.0, dn = 0.0;
      for(int i = 1; i <= n; i++)
      {
         if(r[i].close > r[i].open) up += (double)r[i].tick_volume;
         else if(r[i].close < r[i].open) dn += (double)r[i].tick_volume;
      }
      if(up <= 0.0 || dn <= 0.0) return false;
      if(dir < 0) return (dn >= InpVolumeMult * up);
      return (up >= InpVolumeMult * dn);
   }

   //-------------------------------------------------------------------
   // Order-flow layer (bookmap proxy): POC, VWAP, aggression, absorption
   //-------------------------------------------------------------------
   bool SessionFlow(const SEAContext &ctx, SCfFlow &flow)
   {
      flow.poc = 0.0; flow.vwap = 0.0; flow.pocDominance = 0.0;
      flow.lastClose = 0.0; flow.sessionHi = 0.0; flow.sessionLo = 0.0; flow.sessionAvgVol = 0.0;
      flow.aggression = 0; flow.sessionBars = 0; flow.ok = false;

      MqlRates m[];
      int got = EA_Rates(ctx.symbol, PERIOD_M1, 0, InpProfileBars + 2, m);
      if(got < 30) return false;

      MqlDateTime today;
      TimeToStruct(ctx.nowClock, today);                        // the session is the EA's own clock day

      int    firstSum = -1;
      double sumPv = 0.0, sumV = 0.0;
      double hi = 0.0, lo = 0.0;
      for(int i = got - 1; i >= 1; i--)                         // closed bars only
      {
         datetime cb = EA_BarClockTime(m[i].time);
         MqlDateTime d;
         TimeToStruct(cb, d);
         if(d.day != today.day || d.mon != today.mon || d.year != today.year) continue;
         firstSum = i;
         double typ = (m[i].high + m[i].low + m[i].close) / 3.0;
         double v = (double)m[i].tick_volume;
         sumPv += typ * v;
         sumV  += v;
         if(m[i].high > hi) hi = m[i].high;
         if(lo == 0.0 || m[i].low < lo) lo = m[i].low;
      }
      if(firstSum < 0 || sumV <= 0.0 || hi <= lo) return false;
      flow.vwap = sumPv / sumV;
      flow.lastClose = m[1].close;

      //--- "POC is the price level with the most volume in the session profile":
      //--- tick volume binned across the session's own range
      int bins = (int)MathMax(8, MathMin(120, InpPocBins));
      double binW = (hi - lo) / (double)bins;
      if(binW <= 0.0) return false;
      double binVol[];
      ArrayResize(binVol, bins);
      ArrayInitialize(binVol, 0.0);
      int counted = 0;
      for(int i = firstSum; i >= 1; i--)
      {
         datetime cb = EA_BarClockTime(m[i].time);
         MqlDateTime d;
         TimeToStruct(cb, d);
         if(d.day != today.day || d.mon != today.mon || d.year != today.year) continue;
         int b = (int)MathFloor((m[i].close - lo) / binW);
         if(b < 0) b = 0;
         if(b >= bins) b = bins - 1;
         binVol[b] += (double)m[i].tick_volume;
         counted++;
      }
      if(counted <= 0) return false;
      int bestBin = 0;
      double best = 0.0, avg = 0.0;
      for(int b = 0; b < bins; b++)
      {
         avg += binVol[b];
         if(binVol[b] > best) { best = binVol[b]; bestBin = b; }
      }
      avg /= (double)bins;
      flow.poc = lo + ((double)bestBin + 0.5) * binW;
      flow.pocDominance = (avg > 0.0) ? best / avg : 0.0;
      flow.sessionBars = counted;
      flow.sessionHi = hi;
      flow.sessionLo = lo;
      flow.sessionAvgVol = sumV / (double)counted;   // the session's own pace, never the previous day's

      //--- "large volume spikes on the buy side (green), buyers are aggressive"
      flow.aggression = Aggression(m, got, InpAggressionBars);
      flow.ok = true;
      return true;
   }

   int Aggression(const MqlRates &m[], const int got, const int bars)
   {
      int n = (int)MathMin(bars, got - 2);
      if(n < 3) return 0;
      double up = 0.0, dn = 0.0;
      for(int i = 1; i <= n; i++)
      {
         if(m[i].close > m[i].open) up += (double)m[i].tick_volume;
         else if(m[i].close < m[i].open) dn += (double)m[i].tick_volume;
      }
      if(up <= 0.0 || dn <= 0.0) return 0;
      if(up >= InpVolumeMult * dn) return +1;                   // aggressive buyers
      if(dn >= InpVolumeMult * up) return -1;                   // aggressive sellers
      return 0;                                                 // no side in control
   }

   //--- the full confirmation for one direction: "Only take the setup when everything aligns"
   bool OrderFlowAlign(const SEAContext &ctx, const SCfFlow &flow, const int dir)
   {
      if(!flow.ok) return false;
      if(dir < 0)
      {
         if(flow.lastClose >= flow.vwap) return false;          // sellers must hold price below VWAP
         if(flow.poc > flow.vwap) return false;                 // "If POC is moving down, bearish volume is dominating"
         if(flow.aggression != -1) return false;                // the doc's red volume spikes
         return AbsorptionFails(ctx, -1);
      }
      if(flow.lastClose <= flow.vwap) return false;
      if(flow.poc < flow.vwap) return false;
      if(flow.aggression != +1) return false;
      return AbsorptionFails(ctx, +1);
   }

   //--- "If buyers can't push price above a level despite high buy volume, sellers are
   //---  absorbing those buys - a bearish signal" (and the mirror for longs):
   //--- a heavy directional bar that failed to take the prior extreme
   bool AbsorptionFails(const SEAContext &ctx, const int dir)
   {
      MqlRates m[];
      int got = EA_Rates(ctx.symbol, PERIOD_M1, 0, InpAbsorbLookback + 4, m);
      if(got < InpAbsorbLookback + 2) return false;
      double avg = AvgVolume(m, got, 2, InpAbsorbLookback);
      if(avg <= 0.0) return false;

      for(int i = 1; i <= InpAbsorbLookback; i++)
      {
         if((double)m[i].tick_volume < InpVolumeMult * avg) continue;
         if(dir < 0)
         {
            if(m[i].close <= m[i].open) continue;               // the heavy bar must be a buy
            double prior = HighestHigh(m, got, i + 1, InpAbsorbLookback);
            if(prior > 0.0 && m[i].high < prior - InpSweepTolAtr * ctx.atr) return true;
         }
         else
         {
            if(m[i].close >= m[i].open) continue;               // the heavy bar must be a sell
            double prior = LowestLow(m, got, i + 1, InpAbsorbLookback);
            if(prior > 0.0 && m[i].low > prior + InpSweepTolAtr * ctx.atr) return true;
         }
      }
      return false;
   }

   //--- "market conditions were unclear (low volume, piano-like price action, macro
   //---  opening volatility)" + "unclear POC" from the action items.  Every term is
   //---  session-scoped on purpose: a window that reached back into the previous
   //---  (much busier) New York session would read every quiet Asia bar as "low
   //---  volume" and block the document's own preferred window.  Entry gate: all
   //---  terms; live position: the volume/POC terms only (a momentary spread
   //---  widening or one burst bar is not a reason to dump a working trade).
   bool Sketchy(const SEAContext &ctx, const SCfFlow &flow, const bool forEntry)
   {
      if(forEntry && ctx.spreadPoints > InpMaxSpreadPoints) return true;
      if(!flow.ok) return false;                     // no profile = no order-flow read to call sketchy
      MqlRates m[];
      int got = EA_Rates(ctx.symbol, PERIOD_M1, 0, 64, m);
      if(got < 4) return false;                      // unreadable history is not "sketchy conditions"

      //--- young session: only the doc's "macro opening volatility" is measurable
      if(flow.sessionBars < InpMinSessionBars)
      {
         if(!forEntry) return false;                 // not a reason to close a working trade
         double avg = AvgVolume(m, got, 2, (int)MathMin(InpProfileBars, got - 2));
         if(m[1].high - m[1].low > InpBurstAtr * ctx.atr) return true;
         if(avg > 0.0 && (double)m[1].tick_volume > 3.0 * avg) return true;
         return false;
      }

      //--- 1) "low volume": the recent pace against the session's own pace
      double recent = AvgVolume(m, got, 1, (int)MathMin(30, got - 2));
      if(flow.sessionAvgVol > 0.0 && recent < InpSketchyVolMult * flow.sessionAvgVol) return true;

      //--- 2) "piano-like price action": the session's whole range is a rounding error
      if(flow.sessionHi > flow.sessionLo && (flow.sessionHi - flow.sessionLo) < InpSketchyRangeAtr * ctx.atr)
         return true;

      //--- 3) "unclear POC": no price level dominates the profile
      if(flow.pocDominance > 0.0 && flow.pocDominance < InpSketchyPocDom) return true;
      return false;
   }

   //--- a flip is only trusted after FlipConfirmBars consecutive closed bars confirm it
   bool FlipPersists(const SEAContext &ctx, const SCfFlow &flow, const int dir, const int bars)
   {
      MqlRates m[];
      int got = EA_Rates(ctx.symbol, PERIOD_M1, 0, bars + 2, m);
      if(got < bars + 1) return false;
      for(int i = 1; i <= bars; i++)
      {
         if(dir < 0)
         {
            if(m[i].close >= flow.vwap) return false;
            if(m[i].close > m[i].open)  return false;          // the flip bars must lean down too
         }
         else
         {
            if(m[i].close <= flow.vwap) return false;
            if(m[i].close < m[i].open)  return false;
         }
      }
      return true;
   }

   //-------------------------------------------------------------------
   // STEP 3 - the three entry models
   //-------------------------------------------------------------------
   //--- model 1: "Price takes liquidity above a previous high, creates a fair value
   //---  gap, then closes with volume below that gap."
   bool ModelIfbg(const SEAContext &ctx, const int dir, SCfEntry &e)
   {
      MqlRates m[];
      int got = EA_Rates(ctx.symbol, PERIOD_M1, 0, InpEntryBars + InpSweepLookback + 6, m);
      if(got < InpSweepLookback + 8) return false;
      double avg = AvgVolume(m, got, 2, (int)MathMin(InpEntryBars, got - 3));
      if(avg <= 0.0) return false;
      double tol = InpSweepTolAtr * ctx.atr;

      //--- the newest matching gap inside the window
      for(int g = 1; g <= InpEntryBars; g++)
      {
         if(g + 2 >= got) continue;
         MqlRates left = m[g + 2], mid = m[g + 1], right = m[g];
         double gapLow = 0.0, gapHigh = 0.0;
         bool isBull = false;
         if(dir < 0)
         {
            if(!(mid.close > mid.open && EA_BodyRatio(mid) >= InpImpulseBody)) continue;
            if(!(left.high < right.low && (right.low - left.high) >= InpMinGapAtr * ctx.atr)) continue;
            gapLow = left.high; gapHigh = right.low; isBull = true;
         }
         else
         {
            if(!(mid.close < mid.open && EA_BodyRatio(mid) >= InpImpulseBody)) continue;
            if(!(left.low > right.high && (left.low - right.high) >= InpMinGapAtr * ctx.atr)) continue;
            gapHigh = left.low; gapLow = right.high; isBull = false;
         }

         //--- "takes liquidity above a previous high": a bar NEWER than the gap
         for(int s = g - 1; s >= 1; s--)
         {
            if(g - s > InpModelFreshBars) break;
            double prior = (dir < 0) ? HighestHigh(m, got, s + 1, InpSweepLookback)
                                     : LowestLow(m, got, s + 1, InpSweepLookback);
            if(prior <= 0.0) continue;
            bool swept = (dir < 0) ? (m[s].high > prior + tol) : (m[s].low < prior - tol);
            if(!swept) continue;

            //--- "then closes with volume below that gap"
            bool closedThrough = (dir < 0) ? (m[1].close < gapLow - tol) : (m[1].close > gapHigh + tol);
            if(!closedThrough) continue;
            if((double)m[1].tick_volume < InpVolumeMult * avg) continue;

            e.dir = dir; e.model = 1; e.sweepBar = s;
            e.entry = FairPrice(ctx, dir);
            e.stop  = (dir < 0) ? (SweepExtreme(m, got, s, +1) + InpStopBufferAtr * ctx.atr)
                                : (SweepExtreme(m, got, s, -1) - InpStopBufferAtr * ctx.atr);
            if(!StopOk(e.entry, e.stop, ctx)) continue;
            e.score = 68.0;
            string why = isBull ? "IFBG: liquidity swept above the high, price closed with volume below the gap"
                                : "IFBG: liquidity swept below the low, price closed with volume above the gap";
            e.reason = why;
            return true;
         }
      }
      return false;
   }

   //--- model 2 (the document's preference): "reacts at support, makes a candle
   //---  suggesting a sell, then manipulates with volume, breaks, retests, and closes
   //---  below with volume".  "Requires liquidity to be swept first."
   bool ModelChoch(const SEAContext &ctx, const int dir, SCfEntry &e)
   {
      MqlRates m[];
      int got = EA_Rates(ctx.symbol, PERIOD_M1, 0, InpEntryBars + InpSweepLookback + 6, m);
      if(got < InpSweepLookback + 8) return false;
      double avg = AvgVolume(m, got, 2, (int)MathMin(InpEntryBars, got - 3));
      if(avg <= 0.0) return false;
      double tol = InpSweepTolAtr * ctx.atr;

      for(int s = 1; s <= InpEntryBars; s++)                    // the manipulation bar (newest first)
      {
         if(s + InpSweepLookback + 1 >= got) continue;
         double prior = (dir < 0) ? HighestHigh(m, got, s + 1, InpSweepLookback)
                                  : LowestLow(m, got, s + 1, InpSweepLookback);
         if(prior <= 0.0) continue;
         bool swept = (dir < 0) ? (m[s].high > prior + tol) : (m[s].low < prior - tol);
         if(!swept) continue;

         //--- the structure level: the last opposing pivot before the manipulation
         double level = 0.0;
         if(dir < 0) { if(!LastPivotLow(m, got, s + 1, InpStructureBars, InpEntryFractal, level)) continue; }
         else        { if(!LastPivotHigh(m, got, s + 1, InpStructureBars, InpEntryFractal, level)) continue; }

         //--- "breaks ... with volume"
         int breakBar = 0;
         for(int b = s - 1; b >= 1; b--)
         {
            if((double)m[b].tick_volume < InpVolumeMult * avg) continue;
            bool broke = (dir < 0) ? (m[b].close < level - tol) : (m[b].close > level + tol);
            if(broke) { breakBar = b; break; }
         }
         if(breakBar == 0) continue;
         if(breakBar - 1 > InpModelFreshBars) continue;         // the retest must still be fresh

         //--- "retests, and closes below with volume": the newest closed bar touches the
         //--- level, cannot reclaim it, and the failure carries volume
         bool retest = false;
         if(dir < 0)
            retest = (m[1].high >= level - tol && m[1].close < level - tol);
         else
            retest = (m[1].low  <= level + tol && m[1].close > level + tol);
         if(!retest) continue;
         if((double)m[1].tick_volume < InpVolumeMult * avg) continue;

         e.dir = dir; e.model = 2; e.sweepBar = s;
         e.entry = FairPrice(ctx, dir);
         e.stop  = (dir < 0) ? (MathMax(SweepExtreme(m, got, s, +1), m[1].high) + InpStopBufferAtr * ctx.atr)
                             : (MathMin(SweepExtreme(m, got, s, -1), m[1].low)  - InpStopBufferAtr * ctx.atr);
         if(!StopOk(e.entry, e.stop, ctx)) continue;
         e.score = 74.0;                                        // the document's preferred model
         e.reason = "change of character: liquidity swept, structure broken with volume, retest failed to reclaim";
         return true;
      }
      return false;
   }

   //--- model 3 (continuation): "Price breaks a level with volume and retests it, then
   //---  continues in the original direction.  Must see a fair value gap displacing the
   //---  previous high and retest closing above the apex"
   bool ModelBreakRetest(const SEAContext &ctx, const int dir, SCfEntry &e)
   {
      MqlRates m[];
      int got = EA_Rates(ctx.symbol, PERIOD_M1, 0, InpEntryBars + InpLevelLookback + 6, m);
      if(got < InpLevelLookback + 8) return false;
      double avg = AvgVolume(m, got, 2, (int)MathMin(InpEntryBars, got - 3));
      if(avg <= 0.0) return false;
      double tol = InpSweepTolAtr * ctx.atr;

      for(int j = 1; j <= InpEntryBars; j++)                    // the break bar (newest first)
      {
         if(j + InpLevelLookback + 1 >= got) continue;
         if((double)m[j].tick_volume < InpVolumeMult * avg) continue;
         double level = (dir > 0) ? HighestHigh(m, got, j + 1, InpLevelLookback)
                                  : LowestLow(m, got, j + 1, InpLevelLookback);
         if(level <= 0.0) continue;
         bool broke = (dir > 0) ? (m[j].close > level + tol) : (m[j].close < level - tol);
         if(!broke) continue;
         if(!HasGap(m, got, j, dir, level, ctx.atr)) continue;  // "a fair value gap displacing the previous high"
         if(j - 1 > InpModelFreshBars) continue;                // the retest must be fresh

         //--- "retest closing above the apex": the newest closed bar holds the level
         bool held = false;
         if(dir > 0)
            held = (m[1].low <= level + tol && m[1].close > level + tol);
         else
            held = (m[1].high >= level - tol && m[1].close < level - tol);
         if(!held) continue;
         if((double)m[1].tick_volume < InpVolumeMult * avg) continue;

         e.dir = dir; e.model = 3; e.sweepBar = -1;
         e.entry = FairPrice(ctx, dir);
         e.stop  = (dir > 0) ? (level - InpStopBufferAtr * ctx.atr)
                             : (level + InpStopBufferAtr * ctx.atr);
         if(!StopOk(e.entry, e.stop, ctx)) continue;
         e.score = 70.0;
         e.reason = "break and retest: the level broke with volume and a fair value gap, the retest held";
         return true;
      }
      return false;
   }

   //--- a fair value gap inside the impulse that broke the level; the gap's newest bar
   //--- (the displacement bar) must itself be beyond the level
   bool HasGap(const MqlRates &m[], const int got, const int breakBar, const int dir,
               const double level, const double atr)
   {
      for(int g = breakBar; g <= breakBar + 3 && g + 2 < got; g++)
      {
         MqlRates left = m[g + 2], mid = m[g + 1], right = m[g];
         if(dir > 0)
         {
            if(mid.close > mid.open && EA_BodyRatio(mid) >= InpImpulseBody &&
               left.low > right.high && (left.low - right.high) >= InpMinGapAtr * atr &&
               right.close > level)
               return true;
         }
         else
         {
            if(mid.close < mid.open && EA_BodyRatio(mid) >= InpImpulseBody &&
               left.high < right.low && (right.low - left.high) >= InpMinGapAtr * atr &&
               right.close < level)
               return true;
         }
      }
      return false;
   }

   //--- "targeting liquidity below" / "took profit before hitting a strong resistance
   //---  (previous daily high)": the nearest liquidity pool beyond the R floor
   bool NextPool(const SEAContext &ctx, const int dir, const double entry, const double risk, double &target)
   {
      target = 0.0;
      if(risk <= 0.0) return false;
      double need = InpMinTargetR * risk;

      double pdHi = 0.0, pdLo = 0.0;
      bool havePd = SigDonchian(ctx.symbol, (int)MathMax(1, InpPoolDays), pdHi, pdLo);
      double sesHi = 0.0, sesLo = 0.0;
      bool haveSes = SessionExtremes(ctx, sesHi, sesLo);

      double best = 0.0;
      if(dir > 0)
      {
         if(haveSes && sesHi > entry + need && (best == 0.0 || sesHi < best)) best = sesHi;
         if(havePd  && pdHi  > entry + need && (best == 0.0 || pdHi  < best)) best = pdHi;
      }
      else
      {
         if(haveSes && sesLo < entry - need && (best == 0.0 || sesLo > best)) best = sesLo;
         if(havePd  && pdLo  < entry - need && (best == 0.0 || pdLo  > best)) best = pdLo;
      }
      if(best == 0.0) return false;
      target = best;
      return true;
   }

   bool SessionExtremes(const SEAContext &ctx, double &hi, double &lo)
   {
      hi = 0.0; lo = 0.0;
      MqlRates m[];
      int got = EA_Rates(ctx.symbol, PERIOD_M1, 0, InpProfileBars + 2, m);
      if(got < 30) return false;
      MqlDateTime today;
      TimeToStruct(ctx.nowClock, today);
      for(int i = got - 1; i >= 1; i--)
      {
         datetime cb = EA_BarClockTime(m[i].time);
         MqlDateTime d;
         TimeToStruct(cb, d);
         if(d.day != today.day || d.mon != today.mon || d.year != today.year) continue;
         if(m[i].high > hi) hi = m[i].high;
         if(lo == 0.0 || m[i].low < lo) lo = m[i].low;
      }
      return (hi > 0.0 && lo > 0.0);
   }

   //-------------------------------------------------------------------
   // Small helpers
   //-------------------------------------------------------------------
   double FairPrice(const SEAContext &ctx, const int dir)
   {
      if(dir > 0) return (ctx.ask > 0.0) ? ctx.ask : ctx.mid;
      return (ctx.bid > 0.0) ? ctx.bid : ctx.mid;
   }

   //--- "trading 5-minute charts results in huge stop-losses ... allows tight stops":
   //--- a setup whose structural stop needs more than InpMaxStopAtr of M1 ATR is skipped
   bool StopOk(const double entry, const double stop, const SEAContext &ctx)
   {
      double risk = MathAbs(entry - stop);
      if(risk <= 0.0) return false;
      return (risk <= InpMaxStopAtr * ctx.atr);
   }

   //--- swing highs/lows (newest first) from a rates array.  SigFractals() is bound to
   //--- g_eaIndTf and returns both sides in one pass, so the multi-timeframe structure
   //--- (H4 macro, H1 secondary) needs this local scan - documented deviation.
   int SwingHighs(const MqlRates &r[], const int got, const int fractal, double &highs[], int &bars[])
   {
      ArrayResize(highs, 0);
      ArrayResize(bars, 0);
      for(int i = fractal; i <= got - fractal - 1; i++)
      {
         bool piv = true;
         for(int k = 1; k <= fractal && piv; k++)
            if(!(r[i].high > r[i - k].high && r[i].high > r[i + k].high)) piv = false;
         if(!piv) continue;
         int n = ArraySize(highs);
         ArrayResize(highs, n + 1);
         ArrayResize(bars, n + 1);
         highs[n] = r[i].high;
         bars[n]  = i;
      }
      ReverseDoubles(highs);
      ReverseInts(bars);
      return ArraySize(highs);
   }

   int SwingLows(const MqlRates &r[], const int got, const int fractal, double &lows[], int &bars[])
   {
      ArrayResize(lows, 0);
      ArrayResize(bars, 0);
      for(int i = fractal; i <= got - fractal - 1; i++)
      {
         bool piv = true;
         for(int k = 1; k <= fractal && piv; k++)
            if(!(r[i].low < r[i - k].low && r[i].low < r[i + k].low)) piv = false;
         if(!piv) continue;
         int n = ArraySize(lows);
         ArrayResize(lows, n + 1);
         ArrayResize(bars, n + 1);
         lows[n] = r[i].low;
         bars[n] = i;
      }
      ReverseDoubles(lows);
      ReverseInts(bars);
      return ArraySize(lows);
   }

   void ReverseDoubles(double &v[])
   {
      int n = ArraySize(v);
      for(int i = 0; i < n / 2; i++)
      {
         double t = v[i]; v[i] = v[n - 1 - i]; v[n - 1 - i] = t;
      }
   }

   void ReverseInts(int &v[])
   {
      int n = ArraySize(v);
      for(int i = 0; i < n / 2; i++)
      {
         int t = v[i]; v[i] = v[n - 1 - i]; v[n - 1 - i] = t;
      }
   }

   //--- the last pivot low / high strictly OLDER than bar `from` (bars are newest-first)
   bool LastPivotLow(const MqlRates &m[], const int got, const int from, const int span, const int fractal, double &level)
   {
      level = 0.0;
      int end = (int)MathMin(got - fractal - 1, from + span);
      for(int i = from; i <= end; i++)
      {
         bool piv = true;
         for(int k = 1; k <= fractal && piv; k++)
            if(!(m[i].low < m[i - k].low && m[i].low < m[i + k].low)) piv = false;
         if(piv) { level = m[i].low; return true; }
      }
      return false;
   }

   bool LastPivotHigh(const MqlRates &m[], const int got, const int from, const int span, const int fractal, double &level)
   {
      level = 0.0;
      int end = (int)MathMin(got - fractal - 1, from + span);
      for(int i = from; i <= end; i++)
      {
         bool piv = true;
         for(int k = 1; k <= fractal && piv; k++)
            if(!(m[i].high > m[i - k].high && m[i].high > m[i + k].high)) piv = false;
         if(piv) { level = m[i].high; return true; }
      }
      return false;
   }

   //--- the extreme of the manipulation leg (the stop reference)
   double SweepExtreme(const MqlRates &m[], const int got, const int fromBar, const int dir)
   {
      double ext = 0.0;
      int end = (int)MathMin(got - 1, fromBar + InpSweepLookback);
      for(int i = fromBar; i <= end; i++)
      {
         if(dir > 0) { if(m[i].high > ext) ext = m[i].high; }
         else        { if(ext == 0.0 || m[i].low < ext) ext = m[i].low; }
      }
      return ext;
   }

   double AvgVolume(const MqlRates &m[], const int got, const int from, const int count)
   {
      int n = (int)MathMin(count, got - from);
      if(n <= 0) return 0.0;
      double s = 0.0;
      for(int i = from; i < from + n; i++) s += (double)m[i].tick_volume;
      return s / (double)n;
   }

   double HighestHigh(const MqlRates &m[], const int got, const int from, const int count)
   {
      double best = 0.0;
      int end = (int)MathMin(got - 1, from + count - 1);
      for(int i = from; i <= end; i++) if(m[i].high > best) best = m[i].high;
      return best;
   }

   double LowestLow(const MqlRates &m[], const int got, const int from, const int count)
   {
      double best = 0.0;
      int end = (int)MathMin(got - 1, from + count - 1);
      for(int i = from; i <= end; i++)
         if(best == 0.0 || m[i].low < best) best = m[i].low;
      return best;
   }

   //--- the R multiple of a live position (the engine's persisted planned risk first)
   double RMultiple(const ulong ticket, const int dir, const double entry)
   {
      if(!PositionSelectByTicket(ticket)) return 0.0;
      double risk = GlobalVariableCheck(EA_RiskKey(ticket)) ? GlobalVariableGet(EA_RiskKey(ticket)) : 0.0;
      if(risk <= 0.0)
      {
         double sl = PositionGetDouble(POSITION_SL);
         if(sl > 0.0) risk = MathAbs(entry - sl);
      }
      if(risk <= 0.0) return 0.0;
      double price = PositionGetDouble(POSITION_PRICE_CURRENT);
      return ((price - entry) / risk) * (double)dir;
   }

   string WindowName()
   {
      if(InpWindow == CF_WINDOW_ASIA)    return "Asia 00:00-08:00 London";
      if(InpWindow == CF_WINDOW_NEWYORK) return "New York 14:30-20:00 London";
      return "all hours";
   }
};

CCfNasdaqIctOrderFlow g_cfNasdaqIctOrderFlow;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfNasdaqIctOrderFlow);
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
