//+------------------------------------------------------------------+
//|                                        EA_CF_ParabolicShort.mq5   |
//|                                  Copyright 2026, Master Strategy  |
//|                                                                   |
//| ChartFanatics playbook: Parabolic Short Strategy (Marios          |
//| Stamatoudis)                                                      |
//| Card    : chartfanatics/todos/parabolic-short-strategy.md  (#30)  |
//| Source  : chartfanatics/pdf/parabolic-short-strategy.pdf          |
//| Magic   : 3233                                                    |
//|                                                                   |
//| "The goal of this strategy is to recognize when a parabolic move   |
//|  is reaching its final stage, wait for clear confirmation instead  |
//|  of guessing the top, and then ... enter short with a defined      |
//|  setup."                                                           |
//|                                                                   |
//| The playbook states three CORE COMPONENTS and says "if any of      |
//| these are missing, the setup is not valid":                        |
//|                                                                   |
//|   R1  FILTER 1 - SIZE OF THE MOVE.  A small-cap needs ~200% from   |
//|       its last base, a mid-cap ~100%, a large-cap ~50% (cap tier   |
//|       input); the move is measured "from the most recent base, not |
//|       the absolute bottom ... the last time price touched the      |
//|       20-day moving average before the strong move began" (R2),    |
//|       and must clear the tier's percentage (R3).                   |
//|   R4  FILTER 2 - STRUCTURE.  The move must show ACCELERATION:      |
//|       "price starts accelerating, candles become large, and the    |
//|       slope becomes steep.  In some cases, there are gaps between  |
//|       sessions."  Mechanized as the recent leg's average daily     |
//|       range versus the prior base's, with session gaps accepted    |
//|       as an alternative acceleration sign.                         |
//|   R5  ... and it must NOT be a controlled drift with deep          |
//|       pullbacks: "these pullbacks release pressure, which reduces  |
//|       the chance of a sharp reversal" - the leg's deepest          |
//|       give-back is capped.                                         |
//|   R6  Optional strengthening: volume at the highest level of       |
//|       recent history (score only - "these are not required").      |
//|   R7  Optional strengthening: a psychological round number         |
//|       reached for the first time after the strong move (score      |
//|       only - "100, 300, or 500 ... it often triggers reactions").  |
//|   R8  FILTER 3 - THE EXHAUSTION DAY.  The top must be today or     |
//|       the day before: "the exhaustion day usually happens on the    |
//|       same day as the final push higher, or the following day.     |
//|       If nothing happens within two days, the setup should be      |
//|       ignored."                                                    |
//|   R9  "On a true exhaustion day, price moves below VWAP and is     |
//|       unable to reclaim it"; a STRONG reclaim (a completed bar     |
//|       above VWAP + buffer) makes the setup inactive - "if the      |
//|       price stays above VWAP and continues higher, the setup is    |
//|       not active."                                                 |
//|   R10 "Price stops making higher highs.  Lower highs begin to      |
//|       form, followed by lower lows."                               |
//|                                                                   |
//| The playbook grades its entries, early to best, and all three are  |
//| implemented (selectable):                                          |
//|   R11 CF_PS_STRUCTURE    the break of the upward structure         |
//|                          (earliest, "carries more risk")           |
//|   R12 CF_PS_STRUCT_VWAP  structure break and VWAP loss together    |
//|                          ("a stronger entry")                      |
//|   R13 CF_PS_VWAP_REJECT  "the best entry occurs when price tries   |
//|                          to move back above VWAP and fails"        |
//|                                                                   |
//| Risk and management, verbatim from the playbook:                   |
//|   R14 the failed setup may be retried ONCE ("if it fails once, a    |
//|       second attempt can be taken.  If it fails again, it is best  |
//|       to move on")                                                 |
//|   R15 "a common stop level is the high of the day or the most      |
//|       recent lower high"                                           |
//|   R16 "partial profits should be taken once the trade moves in     |
//|       your favor.  After that, the stop can be moved to            |
//|       break-even"                                                  |
//|   R17 THE RISK-FREE ADD: after the partial and the break-even      |
//|       stop, "if price returns to VWAP and fails again, additional  |
//|       size can be added ... earlier profits cover the loss" - the  |
//|       EA only allows the add when the banked partial profit        |
//|       actually covers the add's risk.                              |
//|   R18 THE EXPECTED MOVE: "stronger, more stable stocks usually     |
//|       move around 10 to 20 percent.  More volatile or hype-driven  |
//|       stocks can move 20 to 40 percent" - the target is sized off  |
//|       the expected move, and "if a large part of the move has      |
//|       already happened ... the trade may no longer be worth        |
//|       taking" is a skip filter.                                    |
//|   R19 "the trade should be closed before the end of the day"       |
//|   R20 "if price reclaims VWAP strongly and continues higher, the   |
//|       setup is no longer valid" (position exit)                    |
//|   R21 the playbook trades STOCKS, day-traded: the universe input   |
//|       is the user's own list; the RTH window is the case study's   |
//|       own context.                                                 |
//|                                                                   |
//| `[interpretation]`: the playbook is discretionary about the exact  |
//| numeric triggers, so every number the document does not state is   |
//| an input here and labelled in the code: the acceleration multiple  |
//| (1.5x), the pullback cap (1/3 of the leg), the base touch          |
//| tolerance, the pivot-wing size, the "at the same time" window,     |
//| the rejection lookback, the VWAP reclaim/ rejection tolerances,    |
//| the stop buffer, the expected-move target fraction and R caps,     |
//| the partial level, the add's cover multiple and the session        |
//| window.  The document's volumes, DOM/order-flow reads and          |
//| discretionary "how the move feels" judgements are not              |
//| reproducible; the three filters above are the mechanical core.     |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics Parabolic Short (Stamatoudis) - size / structure / exhaustion-day short with graded VWAP entries and the risk-free add"

#include "..\..\Include\EACommon.mqh"

//--- Filter 1: the cap tier sets the required move from the base
enum ENUM_CF_PS_CAP
{
   CF_PS_SMALL = 200,   // Small cap (~200% from the base)
   CF_PS_MID   = 100,   // Mid cap (~100% from the base)
   CF_PS_LARGE = 50     // Large cap (~50% from the base)
};

//--- the three graded entries
enum ENUM_CF_PS_ENTRY
{
   CF_PS_STRUCTURE   = 0,   // Structure break only (earliest, more risk)
   CF_PS_STRUCT_VWAP = 1,   // Structure break + VWAP loss together (stronger)
   CF_PS_VWAP_REJECT = 2    // Failed VWAP reclaim (the playbook's best entry)
};

//--- identity / risk
input string            InpSymbolsToTrade     = "AAPL,MSFT,NVDA";  // Universe (playbook: stocks)
input ulong             InpMagicNumber        = 3233;              // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct            = 0.40;              // Risk per trade (% of equity)
input int               InpStage              = 5;                 // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input double            InpMaxSpreadPoints    = 5.0;               // Spread gate in points (0 = off)
input double            InpDailyLossPct       = 1.50;              // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset    = 2;                 // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel           = EA_LOG_EVENTS;     // Log verbosity
input double            InpCommissionPerLotRT = 0.0;               // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.12;              // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;              // Write the engine evidence ledger CSV

//--- Filter 1: size of the move (R1-R3)
input ENUM_CF_PS_CAP    InpCapTier            = CF_PS_LARGE;       // Required move from the base (playbook's cap tiers)
input double            InpMinMovePctOverride = 0.0;               // [interpretation] Override the tier (0 = use the tier)
input int               InpBaseLookbackDays   = 60;                // [interpretation] Window to find the base (20-day MA touch)
input double            InpMaTolPct           = 1.00;              // [interpretation] "Touched the 20-day MA" tolerance (%)

//--- Filter 2: structure of the move (R4-R5)
input int               InpAccelBars          = 5;                 // [interpretation] The accelerating leg (days)
input int               InpAccelBase          = 20;                // [interpretation] The controlled base before it (days)
input double            InpAccelMult          = 1.50;              // [interpretation] Leg range / base range acceleration multiple
input double            InpMaxPullbackFrac    = 0.33;              // [interpretation] Deepest give-back inside the leg (fraction)

//--- optional strengthening signs (R6-R7, score only)
input int               InpVolRecordDays      = 120;               // "highest levels seen in recent history" lookback (days)
input double            InpRoundStep          = 100.0;             // "round numbers like 100, 300, or 500" (0 = off)
input double            InpRoundNearPct       = 1.00;              // [interpretation] How near the round number the top must be (%)

//--- Filter 3: the exhaustion day and the entries (R8-R13)
input ENUM_CF_PS_ENTRY  InpEntryType          = CF_PS_VWAP_REJECT; // Entry grade (the playbook grades these early -> best)
input int               InpMaxDaysSinceTop    = 2;                 // "if nothing happens within two days, the setup should be ignored"
input int               InpSameTimeBars       = 3;                 // [interpretation] "breaks structure and loses VWAP at the same time"
input int               InpRejectLookback     = 6;                 // [interpretation] The failed reclaim must be this recent (bars)
input double            InpReclaimBufferAtr   = 0.30;              // [interpretation] A "strong" reclaim closes this far past VWAP
input double            InpRejectTolAtr       = 0.10;              // [interpretation] How close the failed bounce must reach VWAP
input int               InpSwingWing         = 2;                 // [interpretation] Bars on each side of a pivot (the swing wing)
input double            InpSwingMinAtr        = 0.20;              // [interpretation] Minimum swing size for a pivot to count
input int               InpSwingLookback      = 40;                // [interpretation] Bars scanned for the lower highs / lower lows

//--- risk and management (R14-R18)
input bool              InpUseLowerHighStop   = false;             // false = high of the day, true = the most recent lower high
input double            InpStopBufferAtr      = 0.15;              // [interpretation] Buffer above the stop level
input double            InpMaxStopPct         = 12.0;              // [interpretation] Reject stops wider than x% of price
input double            InpExpectedMovePct    = 20.0;              // "10 to 20 percent" (stable) / "20 to 40 percent" (hype)
input double            InpTargetFrac         = 1.00;              // [interpretation] Share of the expected move to target
input double            InpMaxUsedMoveFrac    = 0.50;              // "if a LARGE part of the move has already happened" (fraction)
input double            InpMinRR              = 1.50;              // [interpretation] Minimum reward:risk the rotation must pay
input double            InpMaxTargetR         = 6.0;               // [interpretation] Target cap in R (the move is intraday)
input double            InpPartialAtR         = 1.0;               // "partial profits once the trade moves in your favor"
input double            InpPartialPct         = 50.0;
input int               InpMaxAttempts        = 2;                 // "if it fails once, a second attempt can be taken"
input bool              InpAllowRiskFreeAdd   = true;              // R17: the add after the partial + the break-even stop
input double            InpAddCoverMult       = 1.00;              // [interpretation] Banked profit must cover the add's risk xN
input bool              InpExitOnVwapReclaim  = true;              // R20: close when VWAP is reclaimed strongly

//--- the day-trading session (the case study's own context, R21)
input int               InpSessionStartHour   = 14;                // US RTH open, London time (09:30 ET)
input int               InpSessionStartMin    = 30;
input int               InpSessionEndHour     = 21;                // US RTH close, London time (16:00 ET)
input int               InpSessionEndMin      = 0;
input int               InpNoTradeAfterHour   = 20;                // No new entries late in the day

//+------------------------------------------------------------------+
//| The playbook's day in one struct: the D1 context (size,           |
//| structure, top recency) and the session geometry (VWAP, swings).  |
//+------------------------------------------------------------------+
struct SParabolicCtx
{
   //--- Filter 1: size (R1-R3)
   double baseLow;          // the last 20-day-MA touch before the move
   double topHigh;          // the parabolic top (the day high of the top day)
   int    topBar;           // 0 = today, 1 = yesterday
   double movePct;          // the extension from the base
   //--- Filter 2: structure (R4-R5)
   double accelRatio;       // leg average range / base average range
   double pullbackFrac;     // deepest give-back inside the leg / the leg's range
   bool   accelOk;          // acceleration or a session gap
   //--- optional strengthening (R6-R7)
   bool   volRecord;
   bool   roundNumber;
};

struct SSessionState
{
   double vwap;
   double dayHigh;          // the session's high ("the high of the day")
   double lastLowerHigh;    // the most recent pivot high (below the prior one)
   double priorSwingLow;    // the most recent pivot low (below the prior one)
   bool   lowerHighs;
   bool   lowerLows;
   bool   belowVwap;
   bool   lostVwap;
   bool   strongReclaim;
   bool   structVwapSame;
   bool   vwapReject;
};

//+------------------------------------------------------------------+
class CCfParabolicShort : public CEAStrategy
{
public:
   //--- R17 needs an open position while a new one is planned
   virtual bool AllowMultipleOnSymbol() { return InpAllowRiskFreeAdd; }

   void OnInitStrategy()
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("5-stage policy: stage %d active (risk %.3f%%, %d trades/day max)",
             InpStage, g_eaCfg.riskPct, g_eaCfg.maxTradesPerDay), true);
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "Parabolic Short armed: tier needs %.0f%% from the base, entry %s, %d attempts, risk-free add %s",
             RequiredMovePct(), EntryName(), InpMaxAttempts,
             InpAllowRiskFreeAdd ? "on" : "off"), true);
   }

   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_PARABOLIC_SHORT";
      cfg.sourceDoc             = "chartfanatics/pdf/parabolic-short-strategy.pdf (card #30)";
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
      //--- R14: the failed setup may be retried once; R17: the add rides on top of that
      cfg.maxTradesPerDay       = InpMaxAttempts + (InpAllowRiskFreeAdd ? 1 : 0);
      cfg.maxOpenPositions      = InpAllowRiskFreeAdd ? 2 : 1;
      cfg.minSecondsBetweenTrades = 300;
      cfg.sessionStartHour      = InpSessionStartHour;
      cfg.sessionStartMin       = InpSessionStartMin;
      cfg.sessionEndHour        = InpSessionEndHour;
      cfg.sessionEndMin         = InpSessionEndMin;
      cfg.sessionEndFlat        = true;                 // R19: "closed before the end of the day"
      cfg.noTradeAfterHour      = InpNoTradeAfterHour;
      cfg.noTradeAfterMin       = 0;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = false;
      cfg.partial1AtR           = InpPartialAtR;        // R16
      cfg.partial1Pct           = InpPartialPct;
      cfg.breakEvenAtR          = InpPartialAtR;        // "after that, the stop can be moved to break-even"
      cfg.trailAtR              = 0.0;                  // the playbook states no trailing rule
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_parabolic_short_ledger.csv";
      cfg.newsFilter            = false;
      cfg.logLevel              = InpLogLevel;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   //+----------------------------------------------------------------+
   //| The signal phase (a new M5 bar): either a fresh short (R1-R13)  |
   //| or the risk-free add (R17) on a protected position.             |
   //+----------------------------------------------------------------+
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession || ctx.atr <= 0.0) return false;

      SParabolicCtx pc;
      if(!ParabolicContext(ctx, pc)) return false;

      MqlRates m[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, InpSwingLookback + InpRejectLookback + 10, m);
      if(got < InpSwingLookback + 4) return false;

      SSessionState ss;
      if(!SessionState(ctx, m, got, ss)) return false;
      if(ss.strongReclaim) return false;                  // R9: "the setup is not active"

      //--- R18: "if a large part of the move has already happened ... no longer worth taking"
      double expected = ctx.bid * InpExpectedMovePct / 100.0;
      double used     = (pc.topHigh > 0.0) ? (pc.topHigh - ctx.bid) / pc.topHigh : 0.0;
      double usedFrac = (InpExpectedMovePct > 0.0) ? used / (InpExpectedMovePct / 100.0) : 0.0;
      if(expected <= 0.0 || usedFrac >= InpMaxUsedMoveFrac) return false;

      //--- stop and target geometry (shared by the fresh entry and the add)
      double stopLevel = (InpUseLowerHighStop && ss.lastLowerHigh > ctx.bid) ? ss.lastLowerHigh : ss.dayHigh;
      if(stopLevel <= 0.0) return false;
      double entry = ctx.bid;
      double stop  = stopLevel + InpStopBufferAtr * ctx.atr;
      double risk  = stop - entry;
      if(risk <= 0.0) return false;
      if(risk > entry * InpMaxStopPct / 100.0) return false;    // [interpretation] sanity cap

      double target = BestTarget(entry, risk, expected);
      if(target <= 0.0 || target >= entry - risk * 0.999) return false;

      //--- the add first: an open, protected position wants size on the second VWAP failure
      if(ctx.openPositions > 0)
         return AddPlan(ctx, pc, ss, entry, stop, risk, target, plan);

      //--- a fresh short: at most InpMaxAttempts entries per day (R14)
      if(ctx.tradesToday >= InpMaxAttempts) return false;
      return FreshEntry(ctx, pc, ss, entry, stop, risk, target, plan);
   }

   //--- R20: "if price reclaims VWAP strongly and continues higher, the setup is no longer valid"
   void Manage(SEAContext &ctx)
   {
      if(!InpExitOnVwapReclaim || ctx.atr <= 0.0) return;
      ulong ticket = EA_FindPosition(ctx.symbol, -1);
      if(ticket == 0) return;

      double vwap = SessionVwap(ctx, g_eaIndTf);
      if(vwap <= 0.0) return;
      MqlRates m[];
      if(EA_Rates(ctx.symbol, g_eaIndTf, 0, 3, m) < 2) return;
      if(m[1].close <= vwap + InpReclaimBufferAtr * ctx.atr) return;   // a completed strong reclaim only

      if(g_eaExec.Close(ticket, "VWAP reclaimed strongly - the setup is invalid"))
         EA_Log(EA_LOG_EVENTS, StringFormat("Parabolic Short: closed %I64u, VWAP reclaimed strongly (%.2f)", ticket, vwap), true);
   }

private:
   //--- the cap tier, or the user's override (R1/R3)
   double RequiredMovePct()
   {
      if(InpMinMovePctOverride > 0.0) return InpMinMovePctOverride;
      return (double)InpCapTier;
   }

   string EntryName()
   {
      if(InpEntryType == CF_PS_STRUCTURE)   return "structure-break";
      if(InpEntryType == CF_PS_STRUCT_VWAP) return "structure+VWAP";
      return "VWAP-reclaim-failure";
   }

   //+----------------------------------------------------------------+
   //| FILTER 1 + FILTER 2 + the top's recency (R1-R8).                |
   //| All D1: the base is the last 20-day-MA touch before the move,   |
   //| the extension is measured from that base's low to the top, the  |
   //| leg's range versus the base's range is the acceleration, and    |
   //| the top must be today's or yesterday's high (the two-day        |
   //| window of the exhaustion day).                                  |
   //+----------------------------------------------------------------+
   bool ParabolicContext(const SEAContext &ctx, SParabolicCtx &pc)
   {
      pc.baseLow = 0.0; pc.topHigh = 0.0; pc.topBar = -1;
      pc.movePct = 0.0; pc.accelRatio = 0.0; pc.pullbackFrac = 0.0;
      pc.accelOk = false; pc.volRecord = false; pc.roundNumber = false;

      if(InpAccelBars < 1 || InpAccelBase < 2 || InpBaseLookbackDays < 1) return false;
      int want = InpBaseLookbackDays + InpAccelBars + InpAccelBase + 30;
      MqlRates d[];
      int got = EA_Rates(ctx.symbol, PERIOD_D1, 0, want, d);
      if(got < InpAccelBars + InpAccelBase + 25) return false;

      //--- R3 + the two-day window (R8): the top is today's or yesterday's high
      double topToday = d[0].high, topYest = d[1].high, topPrev = d[2].high;
      double tol = 0.05 * ctx.atrD1;
      if(topToday > topYest && topToday > topPrev + tol)      { pc.topBar = 0; pc.topHigh = topToday; }
      else if(topYest > topPrev + tol)                        { pc.topBar = 1; pc.topHigh = topYest; }
      else return false;                                       // the top is older than two days
      if(InpMaxDaysSinceTop < 2 && pc.topBar > InpMaxDaysSinceTop - 1) return false;

      //--- R2: the base - the most recent 20-day-MA touch BEFORE the accelerating leg
      int firstLeg = InpAccelBars + 1;                          // d[1..InpAccelBars] is the leg
      for(int i = firstLeg; i <= firstLeg + InpBaseLookbackDays; i++)
      {
         if(i + 19 >= got) break;
         double ma = Ma20At(d, i);
         if(ma <= 0.0) continue;
         if(d[i].low <= ma * (1.0 + InpMaTolPct / 100.0) && d[i].close >= ma * (1.0 - InpMaTolPct / 100.0))
         { pc.baseLow = d[i].low; break; }
      }
      if(pc.baseLow <= 0.0) return false;

      //--- R1: the extension from the base must clear the tier's percentage
      pc.movePct = (pc.topHigh - pc.baseLow) / pc.baseLow * 100.0;
      if(pc.movePct < RequiredMovePct()) return false;

      //--- R4: acceleration - the leg's average daily range versus the base's, or a session gap
      double legRange = 0.0, baseRange = 0.0;
      for(int i = 1; i <= InpAccelBars; i++)
         legRange += (d[i].high - d[i].low) / MathMax(d[i].close, 0.0001);
      for(int i = InpAccelBars + 1; i <= InpAccelBars + InpAccelBase; i++)
         baseRange += (d[i].high - d[i].low) / MathMax(d[i].close, 0.0001);
      legRange  /= (double)InpAccelBars;
      baseRange /= (double)InpAccelBase;
      pc.accelRatio = (baseRange > 0.0) ? legRange / baseRange : 0.0;
      bool gapUp = false;
      for(int i = 1; i < InpAccelBars && i + 1 < got; i++)
         if(d[i].open > d[i + 1].high) { gapUp = true; break; }
      pc.accelOk = (baseRange <= 0.0) || (pc.accelRatio >= InpAccelMult) || gapUp;
      if(!pc.accelOk) return false;

      //--- R5: shallow pullbacks - "these pullbacks release pressure"
      double runTop = d[1].high, legLow = d[1].low, maxDd = 0.0;
      for(int i = 1; i <= InpAccelBars; i++)
      {
         maxDd  = MathMax(maxDd, runTop - d[i].low);
         runTop = MathMax(runTop, d[i].high);
         legLow = MathMin(legLow, d[i].low);
      }
      double legSpan = pc.topHigh - legLow;
      pc.pullbackFrac = (legSpan > 0.0) ? maxDd / legSpan : 1.0;
      if(pc.pullbackFrac > InpMaxPullbackFrac) return false;

      //--- R6: "volume reaches the highest levels seen in recent history"
      if(InpVolRecordDays > InpAccelBars)
      {
         int    limit = (int)MathMin(InpVolRecordDays, got - 1);
         double best  = 0.0;
         int    bestI = -1;
         for(int i = 1; i <= limit; i++)
            if((double)d[i].tick_volume > best) { best = (double)d[i].tick_volume; bestI = i; }
         pc.volRecord = (bestI >= 1 && bestI <= InpAccelBars);
      }

      //--- R7: a psychological round number reached for the first time in the move
      if(InpRoundStep > 0.0)
      {
         double level = MathFloor(pc.topHigh / InpRoundStep) * InpRoundStep;
         double near  = InpRoundNearPct / 100.0 * InpRoundStep;
         pc.roundNumber = (level >= pc.baseLow && (pc.topHigh - level) <= near);
      }
      return true;
   }

   //--- the 20-day moving average ending at bar i (d is newest-first)
   double Ma20At(const MqlRates &d[], const int i)
   {
      double sum = 0.0;
      for(int k = 0; k < 20; k++) sum += d[i + k].close;
      return sum / 20.0;
   }

   //+----------------------------------------------------------------+
   //| FILTER 3 (R9-R13): the exhaustion day's geometry.               |
   //| Below VWAP and unable to reclaim it, lower highs and lower       |
   //| lows, plus the three graded entry patterns.                      |
   //+----------------------------------------------------------------+
   bool SessionState(const SEAContext &ctx, const MqlRates &m[], const int got, SSessionState &ss)
   {
      ss.vwap = 0.0; ss.dayHigh = 0.0; ss.lastLowerHigh = 0.0; ss.priorSwingLow = 0.0;
      ss.lowerHighs = false; ss.lowerLows = false; ss.belowVwap = false; ss.lostVwap = false;
      ss.strongReclaim = false; ss.structVwapSame = false; ss.vwapReject = false;

      ss.vwap = SessionVwap(ctx, g_eaIndTf);
      if(ss.vwap <= 0.0) return false;

      //--- the session's own high ("the high of the day") from the RTH bars
      ss.dayHigh = SessionHigh(ctx, g_eaIndTf);
      if(ss.dayHigh <= 0.0) return false;

      //--- R9: below VWAP now, and above it earlier in the day, and no strong reclaim
      ss.belowVwap = (m[1].close < ss.vwap);
      if(!ss.belowVwap) return false;
      double reclaim = ss.vwap + InpReclaimBufferAtr * ctx.atr;
      ss.strongReclaim = (m[1].close > reclaim || m[2].close > reclaim);
      if(ss.strongReclaim) return false;
      bool wasAbove = false;
      for(int i = 1; i < got; i++)
      {
         if(m[i].time < SessionAnchor(ctx)) break;
         if(m[i].close > ss.vwap) { wasAbove = true; break; }
      }
      ss.lostVwap = wasAbove;
      if(!ss.lostVwap) return false;                       // "if the price stays above VWAP ... not active"

      //--- R10: the swings - lower highs and lower lows
      double ph0 = 0.0, ph1 = 0.0, pl0 = 0.0, pl1 = 0.0;
      int foundH = 0, foundL = 0;
      int wing = (InpSwingWing >= 1) ? InpSwingWing : 1;
      for(int i = 1 + wing; i < got - wing && i <= InpSwingLookback; i++)
      {
         if(foundH < 2 && PivotHigh(m, i, wing, ctx.atr))
         {
            if(foundH == 0) ph0 = m[i].high; else ph1 = m[i].high;
            foundH++;
         }
         if(foundL < 2 && PivotLow(m, i, wing, ctx.atr))
         {
            if(foundL == 0) pl0 = m[i].low; else pl1 = m[i].low;
            foundL++;
         }
         if(foundH >= 2 && foundL >= 2) break;
      }
      ss.lastLowerHigh = ph0;
      ss.priorSwingLow  = pl0;
      ss.lowerHighs = (foundH >= 2 && ph0 < ph1);
      ss.lowerLows  = (foundL >= 2 && pl0 < pl1);

      //--- R12: "breaks structure and loses VWAP at the same time"
      int sameWin = (int)MathMax(1, MathMin(InpSameTimeBars, got - 2));
      for(int i = 1; i <= sameWin && i < got; i++)
      {
         if(m[i].close < ss.vwap && foundL >= 2 && m[i].close < pl1)
         { ss.structVwapSame = true; break; }
      }

      //--- R13: "price tries to move back above VWAP and fails" - the failed bounce, then
      //--- the price stays below VWAP on every bar since
      int look = (int)MathMax(2, MathMin(InpRejectLookback, got - 2));
      for(int j = 2; j <= look; j++)
      {
         bool bearish = (m[j].close < m[j].open);
         bool reached = (m[j].high >= ss.vwap - InpRejectTolAtr * ctx.atr);
         if(!(bearish && reached && m[j].close < ss.vwap)) continue;
         bool stayedBelow = true;
         for(int i = 1; i < j; i++)
            if(m[i].close >= ss.vwap) { stayedBelow = false; break; }
         if(stayedBelow) { ss.vwapReject = true; break; }
      }
      return true;
   }

   //--- the three graded entries (R11-R13), plus the optional score boosts (R6-R7)
   bool FreshEntry(const SEAContext &ctx, const SParabolicCtx &pc, const SSessionState &ss,
                   const double entry, const double stop, const double risk, const double target,
                   SSignalPlan &plan)
   {
      if(!ss.lowerHighs || !ss.lowerLows) return false;              // R10 is the common floor
      if(!(entry < ss.lastLowerHigh)) return false;                  // price is under the broken structure

      double score = 0.0;
      string why = "";
      if(InpEntryType == CF_PS_STRUCTURE)
      {
         score = 60.0; why = "structure break (lower highs / lower lows)";        // R11
      }
      else if(InpEntryType == CF_PS_STRUCT_VWAP)
      {
         if(!ss.structVwapSame) return false;
         score = 74.0; why = "structure break with the VWAP loss together";      // R12
      }
      else
      {
         if(!ss.vwapReject) return false;
         score = 88.0; why = "failed VWAP reclaim (the playbook's best entry)";  // R13
      }
      if(pc.volRecord)   score += 8.0;                               // R6
      if(pc.roundNumber) score += 5.0;                               // R7

      plan.dir      = -1;
      plan.entry    = entry;
      plan.stop     = stop;
      plan.target   = target;
      plan.riskDist = risk;
      plan.barsAgo  = 1;
      plan.score    = MathMin(score, 100.0);
      plan.isLimit  = false;
      plan.reason   = StringFormat("%s: %.0f%% from the base, top d-%d%s%s",
                                   why, pc.movePct, pc.topBar,
                                   pc.volRecord ? ", volume record" : "",
                                   pc.roundNumber ? ", round number" : "");
      return true;
   }

   //+----------------------------------------------------------------+
   //| R17: THE RISK-FREE ADD.  Only when the live short is already    |
   //| protected (partial banked, stop at or beyond break-even) and    |
   //| the banked partial profit covers the add's own risk - the       |
   //| playbook's "earlier profits cover the loss" made arithmetic.    |
   //+----------------------------------------------------------------+
   bool AddPlan(const SEAContext &ctx, const SParabolicCtx &pc, const SSessionState &ss,
                const double entry, const double stop, const double risk, const double target,
                SSignalPlan &plan)
   {
      if(!InpAllowRiskFreeAdd) return false;
      if(ctx.openPositions != 1) return false;                       // one protected leg only
      if(!ss.vwapReject) return false;                               // "returns to VWAP and fails again"

      ulong ticket = EA_FindPosition(ctx.symbol, -1);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) return false;
      double posEntry = PositionGetDouble(POSITION_PRICE_OPEN);
      double posSl    = PositionGetDouble(POSITION_SL);
      if(posSl <= 0.0 || posSl > posEntry) return false;             // stop must be at/beyond break-even

      double banked = BankedOutProfit((ulong)PositionGetInteger(POSITION_IDENTIFIER));
      double cover  = AddRiskMoney(ctx, risk) * InpAddCoverMult;
      if(banked <= 0.0 || banked < cover) return false;              // "earlier profits cover the loss"

      plan.dir      = -1;
      plan.entry    = entry;
      plan.stop     = stop;
      plan.target   = target;
      plan.riskDist = risk;
      plan.barsAgo  = 1;
      plan.score    = 80.0;
      plan.isLimit  = false;
      plan.reason   = StringFormat("risk-free add: protected leg, %.2f banked covers %.2f risk (top d-%d)",
                                   banked, cover, pc.topBar);
      return true;
   }

   //--- the realized profit of the position's partial closes (the engine leaves the rest open)
   double BankedOutProfit(const ulong posId)
   {
      if(!HistorySelectByPosition(posId)) return 0.0;
      double sum = 0.0;
      int deals = HistoryDealsTotal();
      for(int i = 0; i < deals; i++)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         long entry = (long)HistoryDealGetInteger(t, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) continue;
         sum += HistoryDealGetDouble(t, DEAL_PROFIT)
              + HistoryDealGetDouble(t, DEAL_COMMISSION)
              + HistoryDealGetDouble(t, DEAL_SWAP);
      }
      return sum;
   }

   //--- the money the add risks if its stop is hit (engine sizing math, same as the engine)
   double AddRiskMoney(const SEAContext &ctx, const double risk)
   {
      double riskMoney = ctx.equity * ctx.riskPct / 100.0;
      double lots      = EA_LotsForRisk(ctx.symbol, riskMoney, risk);
      if(lots <= 0.0) return riskMoney;                              // fall back to the intended risk
      return lots * EA_LossPerLotAllIn(ctx.symbol, risk, g_eaCfg.commissionPerLotRT);
   }

   //--- R18: the target is a share of the expected move, floored at the minimum R and capped
   double BestTarget(const double entry, const double risk, const double expected)
   {
      double need = InpMinRR * risk;
      double want = MathMin(expected * InpTargetFrac, InpMaxTargetR * risk);
      double dist = MathMax(want, need);
      double target = entry - dist;
      if(target <= 0.0) return 0.0;
      return target;
   }

   //--- a meaningful pivot high (a swing above the wing bars on both sides)
   bool PivotHigh(const MqlRates &m[], const int i, const int wing, const double atr)
   {
      for(int k = 1; k <= wing; k++)
      {
         if(i - k < 0 || i + k >= ArraySize(m)) return false;
         if(m[i].high <= m[i - k].high || m[i].high <= m[i + k].high) return false;
      }
      double low = MathMin(m[i - 1].low, m[i + 1].low);
      return ((m[i].high - low) >= InpSwingMinAtr * atr);
   }

   bool PivotLow(const MqlRates &m[], const int i, const int wing, const double atr)
   {
      for(int k = 1; k <= wing; k++)
      {
         if(i - k < 0 || i + k >= ArraySize(m)) return false;
         if(m[i].low >= m[i - k].low || m[i].low >= m[i + k].low) return false;
      }
      double high = MathMax(m[i - 1].high, m[i + 1].high);
      return ((high - m[i].low) >= InpSwingMinAtr * atr);
   }

   //--- the RTH session's start in broker server time (the case study's window)
   datetime SessionAnchor(const SEAContext &ctx)
   {
      MqlDateTime dt;
      TimeToStruct(ctx.nowClock, dt);
      dt.hour = InpSessionStartHour; dt.min = InpSessionStartMin; dt.sec = 0;
      return EA_ClockToServer(StructToTime(dt));
   }

   //--- session VWAP: typical price weighted by bar volume from the RTH open onwards.
   //--- `[interpretation]`: bar tick volume stands in for true traded volume.
   double SessionVwap(const SEAContext &ctx, const ENUM_TIMEFRAMES tf)
   {
      MqlRates m[];
      int got = EA_Rates(ctx.symbol, tf, 0, 240, m);
      if(got < 8) return 0.0;
      datetime anchor = SessionAnchor(ctx);
      if(ctx.nowClock < anchor) return 0.0;                        // the session has not opened yet
      double pv = 0.0, vol = 0.0;
      for(int i = 1; i < got; i++)
      {
         if(m[i].time < anchor) break;
         double typical = (m[i].high + m[i].low + m[i].close) / 3.0;
         double v = (double)m[i].tick_volume;
         if(v <= 0.0) v = 1.0;
         pv  += typical * v;
         vol += v;
      }
      if(vol <= 0.0) return 0.0;
      return pv / vol;
   }

   //--- the session's high from the RTH bars ("the high of the day")
   double SessionHigh(const SEAContext &ctx, const ENUM_TIMEFRAMES tf)
   {
      MqlRates m[];
      int got = EA_Rates(ctx.symbol, tf, 0, 240, m);
      if(got < 8) return 0.0;
      datetime anchor = SessionAnchor(ctx);
      double hi = 0.0;
      for(int i = 0; i < got; i++)
      {
         if(m[i].time < anchor) break;
         hi = MathMax(hi, m[i].high);
      }
      return hi;
   }
};

CCfParabolicShort g_cfParabolicShort;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfParabolicShort);
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
