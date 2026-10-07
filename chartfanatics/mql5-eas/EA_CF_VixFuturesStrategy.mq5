//+------------------------------------------------------------------+
//|                                  EA_CF_VixFuturesStrategy.mq5     |
//|                                  Copyright 2026, Master Strategy  |
//|                                                                   |
//| ChartFanatics: The VIX Futures Strategy (Dylan O'Neill)            |
//| "Dylan O'Neill's Playbook" - Apr 2025                              |
//| Card    : chartfanatics/todos/the-vix-futures-strategy.md  (#38)   |
//| Source  : chartfanatics/pdf/the-vix-futures-strategy.pdf           |
//| Magic   : 3241                                                    |
//|                                                                   |
//| "The VIX tells you whether there is pressure on the S&P 500.      |
//|  When pressure increases, ES struggles.  When pressure decreases,  |
//|  ES can push higher."                                              |
//|                                                                   |
//| The document's own rules, coded:                                   |
//|                                                                   |
//|   S1  PREVIOUS-DAY LEVELS + VIX: "ES breaks below the previous     |
//|       day's low (PDL), the VIX should normally be rising and       |
//|       sitting at or above its previous day's high ... the move    |
//|       down has higher odds of continuing."  -> confirmed break.   |
//|   S2  THE FAKE BREAK: "If ES breaks below the PDL, but the VIX is  |
//|       not doing its part ... the breakdown has a good chance of    |
//|       failing.  ES often snaps back above the level, trapping      |
//|       shorts ... one of the simplest ways to avoid shorting a      |
//|       fake breakdown."  -> the snap-back long (and the symmetric   |
//|       high-side pair).                                             |
//|   S3  BOTH INDICES: "If both ES and NQ break their lows and the    |
//|       VIX is strong, the downside usually has real power."  -> the |
//|       confirming index is required on a confirmed break ("must     |
//|       avoid taking the same trade on multiple instruments" - the   |
//|       EA holds one index trade at a time).                          |
//|   S4  THE HEAD START: "Sometimes the VIX reaches its previous      |
//|       day's high before ES or NQ breaks their previous day's lows  |
//|       ... the VIX is giving a head start signal."  -> scored.      |
//|   S5  THE NATURAL FLOOR: "At all-time highs ... the VIX often      |
//|       reaches a natural floor ... a rising VIX at all-time highs   |
//|       doesn't always mean ES is about to break down.  Context from |
//|       ES levels is needed."  -> a veto on the confirmed short when |
//|       the index is at its own highs, and the reversal setup below. |
//|   S6  THE 1% RULE: "If ES is up 1% or more and the VIX is also up  |
//|       1% or more ... moves into resistance are more likely to      |
//|       fail."  -> a veto on chasing, both directions.               |
//|   S7  VIX SUPPORT = ES RESISTANCE: "Pairing VIX support with ES    |
//|       resistance - or VIX resistance with ES support - creates     |
//|       strong turning points."  -> the playbook's worked example:   |
//|       a VIX double bottom at its contract low while the index      |
//|       fails at all-time highs, taken as a SHORT on the index or -  |
//|       the document's own trade, "long VIX futures ... delivered a  |
//|       6:1 R outcome" - as a LONG on a VIX instrument when the      |
//|       broker offers one (InpTradeVixDirect).                       |
//|                                                                   |
//| `[interpretation]`: the break / reclaim buffers, the stop buffer   |
//| and its width cap, the VIX confirmation tolerance, the floor        |
//| proximity, the double-bottom window and tolerance, the "all-time"  |
//| lookback and distance, the catalyst-free Friday-weakness bonus,    |
//| the 1% threshold and the R targets are inputs and labelled.        |
//|                                                                   |
//| Disclosed, not faked: the terminal calendar has no VIX term        |
//| structure and no futures contract rolls, so "contract low" is      |
//| proxied by the VIX's own multi-month extreme low; the VIX          |
//| instrument itself is an input (`InpVixSymbol`) and the EA stays     |
//| inert (no signals, logged) when the broker does not offer it;      |
//| mode B needs a tradable VIX instrument, which not every broker     |
//| provides.  The playbook's ES/NQ legs are traded as the index CFDs  |
//| the account actually has.                                          |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics VIX Futures Strategy - previous-day levels confirmed (or faked) by the VIX, with the VIX-floor reversal and the 1% rule"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade     = "US500";          // Traded index (the document trades ES; the confirming leg follows)
input string            InpPrimarySymbol      = "US500";          // The document's ES
input string            InpConfirmSymbol      = "US100";          // The document's NQ - must confirm on a real break
input string            InpVixSymbol          = "VIX";            // The VIX instrument; if the broker has none the EA stays inert
input bool              InpTradeVixDirect     = false;            // Mode B: trade the VIX itself (the playbook's 6:1 example)
input ulong             InpMagicNumber        = 3241;             // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct            = 0.35;             // Risk per trade (% of equity)
input int               InpStage              = 5;                // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input double            InpMaxSpreadPoints    = 8.0;              // Spread gate in points (0 = off)
input double            InpDailyLossPct       = 1.50;             // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset    = 2;                // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel           = EA_LOG_EVENTS;    // Log verbosity
input double            InpCommissionPerLotRT = 0.0;              // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.10;             // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;             // Write the engine evidence ledger CSV

//--- previous-day levels (S1/S2)
input double            InpBreakPct           = 0.03;             // [interpretation] A completed close beyond the level by x% = the break
input double            InpReclaimPct         = 0.03;             // [interpretation] "gets back above the previous day's low" by x%
input double            InpStopBufferAtr      = 0.35;             // [interpretation] Stop buffer beyond the structural level
input double            InpMaxStopPct         = 0.70;             // [interpretation] Reject stops wider than x% of price (anti-chase)

//--- the VIX read (S1/S2/S3/S3b/S5)
input double            InpVixConfirmTol      = 0.05;             // [interpretation] How far from the VIX level still counts as "at" it
input int               InpVixLowLookback     = 60;               // [interpretation] The VIX "contract low" window (sessions)
input double            InpVixFloorPct        = 3.00;             // [interpretation] "near the natural floor" distance
input int               InpDbLookback         = 10;               // [interpretation] The double-bottom window either side
input double            InpDbTolPct           = 1.50;             // [interpretation] Two lows this close form the double bottom
input int               InpAthLookback        = 250;              // [interpretation] The "all-time / multi-year high" lookback
input double            InpAthDistPct         = 1.00;             // [interpretation] "failing at the highs" distance
input int               InpFailBars           = 3;                // [interpretation] A failed breakout counts within these bars
input bool              InpRequireConfirmIdx  = true;             // "If both ES and NQ break their lows ... the move has real power"
input int               InpFridayWeakLookback = 5;                // [interpretation] "sold off on four of the previous five Fridays" window
input int               InpFridayWeakCount    = 3;                // [interpretation] ... and how many make the pattern "in play"

//--- the 1% rule (S6)
input bool              InpOnePctRule         = true;             // "This rule helps avoid chasing extended moves"
input double            InpOnePct             = 1.0;              // the rule's threshold

//--- management
input double            InpTp1R               = 1.5;              // [interpretation] Scale out here (the document's R outcome is 6:1)
input double            InpTp1Pct             = 40.0;             // ... this much
input double            InpTp2R               = 3.0;              // [interpretation] ... and again here
input double            InpTp2Pct             = 30.0;             // ... this much
input double            InpTargetR            = 6.0;              // "delivered a 6:1 R outcome" - the tail rides to this
input int               InpTimeStopMin        = 240;              // [interpretation] Intraday edge - give it x minutes (0 = off)

//--- session
input int               InpSessionStartHour   = 14;               // US cash open, London time (09:30 ET)
input int               InpSessionStartMin    = 30;
input int               InpSessionEndHour     = 21;               // US cash close
input int               InpSessionEndMin      = 0;
input bool              InpSessionEndFlat     = true;             // The previous-day levels are an intraday edge
input int               InpMaxTradesPerDay    = 3;                // Few, high-conviction

//+------------------------------------------------------------------+
struct SDayLevel
{
   double   pdh, pdl, pdc;        // the previous day's high, low, close
   double   highRef;              // the "all-time" reference high over InpAthLookback sessions
   double   sessHigh, sessLow;    // today's session extremes
   double   cur;                  // current bid
   datetime firstLowBreak;        // first session bar trading below the PDL (head-start bookkeeping)
   datetime firstHighBreak;
   bool     brokeLow, brokeHigh;  // the level traded through in the session
   bool     reclaimLow, failHigh; // the snap-back (S2) and the failed breakout (S2 mirror)
   bool     confirmLow, confirmHigh;   // the completed close through the level (S1)
   bool     failedAth;            // poked above the high reference and closed back below
};

struct SVixState
{
   double   pdh, pdl, pdc;
   double   cur;
   double   highToday, lowToday;
   double   lowRef, lowRef2;      // the two lows of the double bottom
   bool     doubleBottom;         // they are within tolerance of each other
   datetime firstAtPdh;           // the first session bar at/above its previous day's high (the head start)
};

//+------------------------------------------------------------------+
class CCfVixFutures : public CEAStrategy
{
public:
   void OnInitStrategy()
   {
      if(!SymbolSelect(InpVixSymbol, true))
         EA_Log(EA_LOG_ERRORS, StringFormat(
                "VIX symbol '%s' is not available at this broker - the VIX confirmation cannot be read, so no signals will be produced",
                InpVixSymbol), true);
      if(InpRequireConfirmIdx && !SymbolSelect(InpConfirmSymbol, true))
         EA_Log(EA_LOG_ERRORS, StringFormat("confirming index '%s' is not available - confirmed breaks will be skipped",
                InpConfirmSymbol), true);
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "VIX strategy armed: traded %s, confirming %s, VIX %s, mode %s, risk %.2f%%, targets %.1fR/%.1fR then %.0fR",
             InpSymbolsToTrade, InpConfirmSymbol, InpVixSymbol,
             InpTradeVixDirect ? "VIX direct" : "index legs", InpRiskPct, InpTp1R, InpTp2R, InpTargetR), true);
   }

   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_VIX_FUTURES";
      cfg.sourceDoc             = "chartfanatics/pdf/the-vix-futures-strategy.pdf (card #38)";
      cfg.symbols               = InpTradeVixDirect ? InpVixSymbol : InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M15;      // "needs matching timeframes across ES, NQ, and VIX"
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = 4.0;
      cfg.totalDdPct            = 10.0;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;               // "must avoid taking the same trade on multiple instruments"
      cfg.minSecondsBetweenTrades = 900;
      cfg.sessionStartHour      = InpSessionStartHour;
      cfg.sessionStartMin       = InpSessionStartMin;
      cfg.sessionEndHour        = InpSessionEndHour;
      cfg.sessionEndMin         = InpSessionEndMin;
      cfg.sessionEndFlat        = InpSessionEndFlat && !InpTradeVixDirect;
      cfg.fridayFlat            = false;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = false;
      cfg.breakEvenAtR          = 0.0;             // the document states no break-even rule
      cfg.partial1AtR           = InpTp1R;         // 40% off the squeeze
      cfg.partial1Pct           = InpTp1Pct;
      cfg.partial2AtR           = InpTp2R;         // 30% more
      cfg.partial2Pct           = InpTp2Pct;
      cfg.trailAtR              = 0.0;             // the tail rides to the 6:1 target
      cfg.timeStopMinutes       = InpTimeStopMin;
      cfg.timeStopUnlessR       = InpTp1R;
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_vix_futures_ledger.csv";
      cfg.logLevel              = InpLogLevel;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   //+----------------------------------------------------------------+
   //| The dispatcher: the two modes of the playbook - the index legs  |
   //| filtered by the VIX, or the VIX itself at its floor.            |
   //+----------------------------------------------------------------+
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(ctx.atr <= 0.0) return false;
      if(!ctx.inSession) return false;

      if(InpTradeVixDirect || ctx.symbol == InpVixSymbol)
         return PlanVixDirectLong(ctx, plan);

      //--- the three reads the playbook needs at once
      SDayLevel es;
      if(!LoadDay(ctx.symbol, es)) return false;
      SDayLevel nq;
      bool haveNq = LoadDay(OtherIndex(ctx), nq);
      SVixState vx;
      if(!LoadVix(vx)) return false;

      //--- S6: "This rule helps avoid chasing extended moves"
      double esPct  = (es.pdc > 0.0) ? (es.cur - es.pdc) / es.pdc * 100.0 : 0.0;
      double vixPct = (vx.pdc > 0.0) ? (vx.cur - vx.pdc) / vx.pdc * 100.0 : 0.0;

      double best = -1.0;
      SSignalPlan p;

      //--- S2: the fake low break ("ES often snaps back above the level, trapping shorts")
      p.Reset();
      if(!OnePercentVeto(true, esPct, vixPct) && PlanFakeLowBreakLong(ctx, es, nq, haveNq, vx, p) && p.score > best)
      { plan = p; best = p.score; }

      //--- S1/S3: the confirmed low break ("the move down has higher odds of continuing")
      p.Reset();
      if(!OnePercentVeto(false, esPct, vixPct) && PlanConfirmedLowBreakShort(ctx, es, nq, haveNq, vx, p) && p.score > best)
      { plan = p; best = p.score; }

      //--- the high-side mirror of S2
      p.Reset();
      if(!OnePercentVeto(false, esPct, vixPct) && PlanFakeHighBreakShort(ctx, es, nq, haveNq, vx, p) && p.score > best)
      { plan = p; best = p.score; }

      //--- the high-side mirror of S1
      p.Reset();
      if(!OnePercentVeto(true, esPct, vixPct) && PlanConfirmedHighBreakLong(ctx, es, nq, haveNq, vx, p) && p.score > best)
      { plan = p; best = p.score; }

      //--- S5/S7: VIX support against index resistance ("strong turning points")
      p.Reset();
      if(!OnePercentVeto(false, esPct, vixPct) && PlanVixFloorReversalShort(ctx, es, vx, p) && p.score > best)
      { plan = p; best = p.score; }

      //--- "must avoid taking the same trade on multiple instruments"
      if(plan.dir != 0 && SameTradeAlreadyOn(ctx, plan.dir)) return false;
      return (plan.dir != 0);
   }

private:
   //+----------------------------------------------------------------+
   //| Data readers                                                    |
   //+----------------------------------------------------------------+
   double SymBid(const string sym) { return SymbolInfoDouble(sym, SYMBOL_BID); }

   //--- in mode B the traded symbol IS the VIX; when the traded index is the
   //--- confirming index itself, the document's ES role falls back to the primary
   string OtherIndex(const SEAContext &ctx)
   {
      if(ctx.symbol != InpConfirmSymbol) return InpConfirmSymbol;
      return InpPrimarySymbol;
   }

   //--- today's session start in server time (the EA clock is London)
   datetime SessionStartServer()
   {
      MqlDateTime lt;
      TimeToStruct(EA_LondonNow(), lt);
      lt.hour = InpSessionStartHour;
      lt.min  = InpSessionStartMin;
      lt.sec  = 0;
      return EA_ClockToServer(StructToTime(lt));
   }

   //+----------------------------------------------------------------+
   //| The previous-day frame plus today's session behaviour.          |
   //+----------------------------------------------------------------+
   bool LoadDay(const string sym, SDayLevel &s)
   {
      s.pdh = 0; s.pdl = 0; s.pdc = 0; s.highRef = 0;
      s.sessHigh = 0; s.sessLow = 0; s.cur = SymBid(sym);
      s.firstLowBreak = 0; s.firstHighBreak = 0;
      s.brokeLow = false; s.brokeHigh = false;
      s.reclaimLow = false; s.failHigh = false;
      s.confirmLow = false; s.confirmHigh = false; s.failedAth = false;
      if(s.cur <= 0.0) return false;

      MqlRates d[];
      int dGot = EA_Rates(sym, PERIOD_D1, 0, InpAthLookback + 5, d);
      if(dGot < 5) return false;
      s.pdh = d[1].high; s.pdl = d[1].low; s.pdc = d[1].close;
      s.highRef = d[1].high;
      int lb = (int)MathMin(InpAthLookback, dGot - 1);
      for(int i = 1; i <= lb; i++) s.highRef = MathMax(s.highRef, d[i].high);

      MqlRates m[];
      int mGot = EA_Rates(sym, g_eaIndTf, 0, 200, m);
      if(mGot < 4) return false;
      datetime sessStart = SessionStartServer();

      for(int i = mGot - 1; i >= 1; i--)          // oldest -> newest, completed bars
      {
         if(m[i].time < sessStart) continue;
         s.sessHigh = MathMax(s.sessHigh, m[i].high);
         s.sessLow  = (s.sessLow == 0.0) ? m[i].low : MathMin(s.sessLow, m[i].low);
         if(m[i].low < s.pdl && s.firstLowBreak == 0)  s.firstLowBreak = m[i].time;
         if(m[i].high > s.pdh && s.firstHighBreak == 0) s.firstHighBreak = m[i].time;
      }
      s.brokeLow  = (s.sessLow > 0.0 && s.sessLow < s.pdl);
      s.brokeHigh = (s.sessHigh > 0.0 && s.sessHigh > s.pdh);

      double br = InpBreakPct / 100.0;
      double rc = InpReclaimPct / 100.0;
      //--- the break of S1 is a completed close through the level
      s.confirmLow  = (m[1].close <= s.pdl * (1.0 - br));
      s.confirmHigh = (m[1].close >= s.pdh * (1.0 + br));
      //--- S2's snap-back: the level broke and the last completed bar closed back beyond it
      s.reclaimLow = (m[1].close >= s.pdl * (1.0 + rc)) && (m[1].low < s.pdl || m[2].close < s.pdl);
      s.failHigh   = (m[1].close <= s.pdh * (1.0 - rc)) && (m[1].high > s.pdh || m[2].close > s.pdh);
      //--- "ES was struggling to break through its all-time high area": a poke above and a close back below
      for(int i = 1; i <= (int)MathMax(1, InpFailBars) && i < mGot; i++)
      {
         if(m[i].high > s.highRef && m[i].close < s.highRef) { s.failedAth = true; break; }
      }
      return true;
   }

   //+----------------------------------------------------------------+
   //| The VIX read: its previous-day frame, today's extremes, the     |
   //| "contract low" (the multi-month extreme low) and the double     |
   //| bottom the worked example trades.                               |
   //+----------------------------------------------------------------+
   bool LoadVix(SVixState &v)
   {
      v.pdh = 0; v.pdl = 0; v.pdc = 0; v.cur = SymBid(InpVixSymbol);
      v.highToday = 0; v.lowToday = 0; v.lowRef = 0; v.lowRef2 = 0;
      v.doubleBottom = false; v.firstAtPdh = 0;
      if(v.cur <= 0.0) return false;

      MqlRates d[];
      int dGot = EA_Rates(InpVixSymbol, PERIOD_D1, 0, InpVixLowLookback + InpDbLookback * 2 + 5, d);
      if(dGot < 20) return false;
      v.pdh = d[1].high; v.pdl = d[1].low; v.pdc = d[1].close;

      int w1 = (int)MathMin(InpVixLowLookback, dGot - 1);
      for(int i = 1; i <= w1; i++)
         v.lowRef = (v.lowRef == 0.0) ? d[i].low : MathMin(v.lowRef, d[i].low);
      int w2 = (int)MathMin(InpDbLookback, dGot - 1 - w1);
      for(int i = w1 + 1; i <= w1 + w2; i++)
         v.lowRef2 = (v.lowRef2 == 0.0) ? d[i].low : MathMin(v.lowRef2, d[i].low);
      v.doubleBottom = (v.lowRef > 0.0 && v.lowRef2 > 0.0 &&
                        MathAbs(v.lowRef - v.lowRef2) / v.lowRef2 <= InpDbTolPct / 100.0);

      MqlRates m[];
      int mGot = EA_Rates(InpVixSymbol, g_eaIndTf, 0, 200, m);
      if(mGot < 4) return false;
      datetime sessStart = SessionStartServer();
      for(int i = mGot - 1; i >= 1; i--)
      {
         if(m[i].time < sessStart) continue;
         v.highToday = MathMax(v.highToday, m[i].high);
         v.lowToday  = (v.lowToday == 0.0) ? m[i].low : MathMin(v.lowToday, m[i].low);
         if(v.firstAtPdh == 0 && m[i].high >= v.pdh) v.firstAtPdh = m[i].time;
      }
      return true;
   }

   //--- "the VIX is not doing its part": not at its previous day's high and making a
   //--- lower high instead of a higher high (both read on today's bars)
   bool VixNotConfirmingDown(const SVixState &v)
   {
      double tol = InpVixConfirmTol / 100.0;
      if(v.cur >= v.pdh * (1.0 - tol)) return false;             // it IS at the previous day's high
      if(v.highToday >= v.pdh * (1.0 - tol)) return false;       // it DID reach it
      return true;                                               // weak: a lower high, no confirmation
   }
   //--- the mirror: the VIX never got to its previous day's low, so the up move is not confirmed
   bool VixNotConfirmingUp(const SVixState &v)
   {
      double tol = InpVixConfirmTol / 100.0;
      if(v.cur <= v.pdl * (1.0 + tol)) return false;
      if(v.lowToday > 0.0 && v.lowToday <= v.pdl * (1.0 + tol)) return false;
      return true;
   }

   //--- S6: "If ES is up 1% or more and the VIX is also up 1% or more ... moves into
   //--- resistance are more likely to fail" (and the mirror for down moves)
   bool OnePercentVeto(const bool isLong, const double esPct, const double vixPct)
   {
      if(!InpOnePctRule) return false;
      double t = InpOnePct;
      if(isLong && esPct >= t && vixPct >= t)   return true;     // fragile strength
      if(!isLong && esPct <= -t && vixPct <= -t) return true;    // fragile weakness
      return false;
   }

   //--- S5: "at all-time highs ... a rising VIX doesn't always mean ES is about to
   //--- break down.  Context from ES levels is needed" - so the confirmed short waits
   bool AtMajorHighs(const SDayLevel &es)
   {
      if(es.highRef <= 0.0) return false;
      return (MathAbs(es.cur - es.highRef) / es.highRef <= InpAthDistPct / 100.0);
   }

   //--- "Must avoid taking the same trade on multiple instruments"
   bool SameTradeAlreadyOn(const SEAContext &ctx, const int dir)
   {
      for(int i = 0; i < g_eaSymbolCount; i++)
      {
         if(g_eaSymbols[i] == ctx.symbol) continue;
         if(g_eaSymbols[i] == InpVixSymbol) continue;            // the VIX leg is the same trade, not another one
         if(EA_FindPosition(g_eaSymbols[i], dir) != 0) return true;
      }
      return false;
   }

   //--- "The S&P had sold off on four of the previous five Fridays" - the context bonus
   int FridayWeakness(const string sym)
   {
      MqlRates d[];
      int got = EA_Rates(sym, PERIOD_D1, 0, 30, d);
      if(got < 8) return 0;
      int seen = 0, weak = 0;
      for(int i = 1; i + 1 < got && seen < (int)MathMax(1, InpFridayWeakLookback); i++)
      {
         MqlDateTime dt;
         if(!TimeToStruct(d[i].time, dt)) continue;
         if(dt.day_of_week != 5) continue;                       // Friday
         seen++;
         if(d[i].close < d[i + 1].close) weak++;                 // closed below Thursday
      }
      return weak;
   }

   //--- a stop the anti-chase guard accepts, or no trade
   bool StopOk(const double entry, const double stop, const double mult)
   {
      if(stop <= 0.0) return false;
      double risk = MathAbs(entry - stop);
      if(risk <= 0.0) return false;
      return (risk <= entry * InpMaxStopPct / 100.0 * mult);
   }

   //+----------------------------------------------------------------+
   //| S2: ES breaks the PDL, the VIX does not confirm -> the snap-back|
   //| long ("ES often snaps back above the level, trapping shorts").  |
   //+----------------------------------------------------------------+
   bool PlanFakeLowBreakLong(const SEAContext &ctx, const SDayLevel &es, const SDayLevel &nq,
                             const bool haveNq, const SVixState &vx, SSignalPlan &p)
   {
      if(!es.brokeLow || !es.reclaimLow) return false;
      if(!VixNotConfirmingDown(vx)) return false;                 // "the VIX is not doing its part"

      double stop = MathMin(es.sessLow, es.pdl) - InpStopBufferAtr * ctx.atr;
      if(!StopOk(ctx.ask, stop, 1.0)) return false;
      double risk = ctx.ask - stop;

      p.dir = +1; p.entry = ctx.ask; p.stop = stop;
      p.target = ctx.ask + InpTargetR * risk;
      p.riskDist = risk; p.barsAgo = 1; p.isLimit = false;
      p.score = 84.0;
      if(haveNq && !nq.brokeLow) { p.score += 4.0; }              // "NQ is showing relative strength"
      p.reason = StringFormat("fake PDL break: closed back above %.2f while the VIX stayed under its PDH %s -> LONG",
                              es.pdl, haveNq ? (!nq.brokeLow ? "(NQ holds its low)" : "(NQ weak)") : "(no NQ read)");
      return true;
   }

   //+----------------------------------------------------------------+
   //| S1/S3: the confirmed PDL break - "the move down has higher odds |
   //| of continuing" - with the confirming index and the head start.  |
   //+----------------------------------------------------------------+
   bool PlanConfirmedLowBreakShort(const SEAContext &ctx, const SDayLevel &es, const SDayLevel &nq,
                                   const bool haveNq, const SVixState &vx, SSignalPlan &p)
   {
      if(!es.brokeLow || !es.confirmLow) return false;
      if(AtMajorHighs(es)) return false;                          // S5: the natural-floor caution
      double tol = InpVixConfirmTol / 100.0;
      if(vx.cur < vx.pdh * (1.0 - tol)) return false;             // "rising and sitting at or above its previous day's high"
      if(InpRequireConfirmIdx && !(haveNq && nq.brokeLow)) return false;   // "both ES and NQ break their lows"

      double stop = es.pdl + InpStopBufferAtr * ctx.atr;
      if(!StopOk(ctx.bid, stop, 1.0)) return false;
      double risk = stop - ctx.bid;

      p.dir = -1; p.entry = ctx.bid; p.stop = stop;
      p.target = ctx.bid - InpTargetR * risk;
      p.riskDist = risk; p.barsAgo = 1; p.isLimit = false;
      p.score = 80.0;
      if(vx.firstAtPdh > 0 && es.firstLowBreak > 0 && vx.firstAtPdh <= es.firstLowBreak) p.score += 5.0;  // the VIX "head start"
      p.reason = StringFormat("confirmed PDL break %.2f with the VIX at/above its PDH %.2f%s -> SHORT",
                              es.pdl, vx.pdh, (vx.firstAtPdh > 0 ? " (VIX moved first)" : ""));
      return (p.target > 0.0);
   }

   //--- the high-side mirror of S2
   bool PlanFakeHighBreakShort(const SEAContext &ctx, const SDayLevel &es, const SDayLevel &nq,
                               const bool haveNq, const SVixState &vx, SSignalPlan &p)
   {
      if(!es.brokeHigh || !es.failHigh) return false;
      if(!VixNotConfirmingUp(vx)) return false;                   // the VIX did not go weak, so the break is suspect

      double stop = MathMax(es.sessHigh, es.pdh) + InpStopBufferAtr * ctx.atr;
      if(!StopOk(ctx.bid, stop, 1.0)) return false;
      double risk = stop - ctx.bid;

      p.dir = -1; p.entry = ctx.bid; p.stop = stop;
      p.target = ctx.bid - InpTargetR * risk;
      p.riskDist = risk; p.barsAgo = 1; p.isLimit = false;
      p.score = 82.0;
      if(haveNq && !nq.brokeHigh) p.score += 2.0;
      p.reason = StringFormat("fake PDH break: closed back below %.2f while the VIX held above its PDL -> SHORT", es.pdh);
      return true;
   }

   //--- the high-side mirror of S1: the VIX weak, both indices through their highs
   bool PlanConfirmedHighBreakLong(const SEAContext &ctx, const SDayLevel &es, const SDayLevel &nq,
                                   const bool haveNq, const SVixState &vx, SSignalPlan &p)
   {
      if(!es.brokeHigh || !es.confirmHigh) return false;
      double tol = InpVixConfirmTol / 100.0;
      if(vx.cur > vx.pdl * (1.0 + tol)) return false;             // pressure removed: at/below its previous day's low
      if(InpRequireConfirmIdx && !(haveNq && nq.brokeHigh)) return false;

      double stop = es.pdh - InpStopBufferAtr * ctx.atr;
      if(!StopOk(ctx.ask, stop, 1.0)) return false;
      double risk = ctx.ask - stop;

      p.dir = +1; p.entry = ctx.ask; p.stop = stop;
      p.target = ctx.ask + InpTargetR * risk;
      p.riskDist = risk; p.barsAgo = 1; p.isLimit = false;
      p.score = 78.0;
      if(vx.firstAtPdh == 0 && vx.lowToday > 0.0 && vx.lowToday <= vx.pdl * (1.0 + tol)) p.score += 5.0;  // the VIX broke down first
      p.reason = StringFormat("confirmed PDH break %.2f with the VIX at/below its PDL %.2f -> LONG", es.pdh, vx.pdl);
      return true;
   }

   //+----------------------------------------------------------------+
   //| S7: the playbook's worked example, index side - "VIX support    |
   //| with ES resistance ... creates strong turning points".          |
   //+----------------------------------------------------------------+
   bool PlanVixFloorReversalShort(const SEAContext &ctx, const SDayLevel &es, const SVixState &vx, SSignalPlan &p)
   {
      if(!vx.doubleBottom) return false;                          // "VIX forms a double bottom at contract lows"
      if(vx.cur > vx.lowRef * (1.0 + InpVixFloorPct / 100.0)) return false;  // ... at the floor
      if(!es.failedAth) return false;                             // "ES fails a breakout at all-time highs"
      if(es.highRef <= 0.0 || MathAbs(es.cur - es.highRef) / es.highRef > InpAthDistPct / 100.0) return false;
      if(!es.brokeHigh) return false;                             // it actually reached the high area today

      double stop = es.sessHigh + InpStopBufferAtr * ctx.atr;
      if(!StopOk(ctx.bid, stop, 1.0)) return false;
      double risk = stop - ctx.bid;

      p.dir = -1; p.entry = ctx.bid; p.stop = stop;
      p.target = ctx.bid - InpTargetR * risk;
      p.riskDist = risk; p.barsAgo = 1; p.isLimit = false;
      p.score = 90.0;                                             // the document's own worked trade
      int fri = FridayWeakness(ctx.symbol);
      if(fri >= InpFridayWeakCount) p.score += 3.0;               // "a recent pattern was in play"
      p.reason = StringFormat("VIX double bottom at its %.2f floor (index %.2f vs high %.2f, Friday weakness %d/%d) -> SHORT",
                              vx.lowRef, es.pdh, es.highRef, fri, InpFridayWeakLookback);
      return true;
   }

   //+----------------------------------------------------------------+
   //| Mode B: "Long VIX Futures at Contract Lows" - the document's   |
   //| own trade, "delivered a 6:1 R outcome".  Needs a tradable VIX   |
   //| instrument; the traded symbol IS the VIX.                      |
   //+----------------------------------------------------------------+
   bool PlanVixDirectLong(const SEAContext &ctx, SSignalPlan &p)
   {
      //--- the 1% rule vetoes chasing the index; the VIX long is the other side of that
      //--- divergence (the document's own example has the index failing at its highs)
      SDayLevel vxDay;
      if(!LoadDay(ctx.symbol, vxDay)) return false;               // the VIX's own day frame
      SDayLevel es;
      bool haveEs = LoadDay(InpPrimarySymbol, es);

      double lowRef = vxDay.pdl;
      int got = 0;
      MqlRates d[];
      got = EA_Rates(ctx.symbol, PERIOD_D1, 0, InpVixLowLookback + InpDbLookback * 2 + 5, d);
      if(got < 20) return false;
      double ref1 = 0.0, ref2 = 0.0;
      int w1 = (int)MathMin(InpVixLowLookback, got - 1);
      for(int i = 1; i <= w1; i++) ref1 = (ref1 == 0.0) ? d[i].low : MathMin(ref1, d[i].low);
      int w2 = (int)MathMin(InpDbLookback, got - 1 - w1);
      for(int i = w1 + 1; i <= w1 + w2; i++) ref2 = (ref2 == 0.0) ? d[i].low : MathMin(ref2, d[i].low);
      if(ref1 <= 0.0 || ref2 <= 0.0) return false;
      lowRef = MathMin(ref1, ref2);
      bool db = (MathAbs(ref1 - ref2) / ref2 <= InpDbTolPct / 100.0);
      if(!db) return false;                                       // "a double bottom at a contract low"
      if(ctx.bid > lowRef * (1.0 + InpVixFloorPct / 100.0)) return false;   // at the floor
      if(!haveEs || !es.failedAth) return false;                  // "ES fails a breakout at all-time highs"

      //--- the VIX moves far more than the index in percentage terms, so its stop cap is wider
      double stop = MathMin(lowRef, ctx.bid) - InpStopBufferAtr * ctx.atr;
      if(!StopOk(ctx.ask, stop, 4.0)) return false;
      double risk = ctx.ask - stop;

      p.dir = +1; p.entry = ctx.ask; p.stop = stop;
      p.target = ctx.ask + InpTargetR * risk;                     // "delivered a 6:1 R outcome"
      p.riskDist = risk; p.barsAgo = 1; p.isLimit = false;
      p.score = 92.0;                                             // the document's worked trade, verbatim
      int fri = FridayWeakness(InpPrimarySymbol);
      if(fri >= InpFridayWeakCount) p.score += 3.0;
      p.reason = StringFormat("long the VIX off its %.2f contract-low double bottom while the index fails at %.2f",
                              lowRef, es.highRef);
      return true;
   }
};

CCfVixFutures g_cfVixFutures;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfVixFutures);
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
