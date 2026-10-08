//+------------------------------------------------------------------+
//|        EA_CF_NqLiquiditySweepReversalScalpingStrategy.mq5         |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| "NQ Liquidity Sweep & Reversal Scalping Strategy"                 |
//| Candice BL - "Trading LIVE With The World's #1 Prop Firm Scalper  |
//| ($2.5M+ Payouts)", Chart Fanatics summary                        |
//| Card    : chartfanatics/todos/nq-liquidity-sweep-reversal-scalping-strategy.md (#26)
//| Source  : chartfanatics/glimpse/-kGVL93XfyE.md                    |
//| Magic   : 3229                                                    |
//|                                                                    |
//| The document is a kill-zone scalping model and the EA follows it   |
//| in its own order:                                                  |
//|                                                                    |
//|   WINDOW - "Candice only trades London session between 2am-5am EST. |
//|   She avoids pre-2am setups despite temptation."  The New-York side |
//|   is the open - "New York trades end within 10-15 minutes" - so the |
//|   EA carries a 09:30 EST window beside the London one.  Both are    |
//|   evaluated on the document's fixed EST clock (UTC-5), never on a   |
//|   DST-shifting local clock.                                         |
//|                                                                    |
//|   LIQUIDITY - "identifying where price has swept liquidity (Asia    |
//|   high/low, swing highs/lows)".  A sweep of the previous Asia range |
//|   (the engine's SigAsianRange) or of a recent swing extreme is the  |
//|   manipulation leg, and it must be swept with a tolerance through   |
//|   the level - a touch is not a sweep.                               |
//|                                                                    |
//|   ENTRY - the inverted fair value gap: "A bearish FVG forms when    |
//|   price gaps down without filling the gap.  When a bullish candle   |
//|   closes above it, it becomes an inverted FVG - a valid entry."     |
//|   The EA takes the conservative variant the document describes      |
//|   ("conservative traders wait for the candle to fully close above   |
//|   it") - a close through the far edge of the counter-directional    |
//|   gap after the sweep - with the trigger candle delivering          |
//|   displacement.                                                     |
//|                                                                    |
//|   STOP - the document's session caps: "London session: 20-25 point  |
//|   max stop loss.  New York session: 30-40 points."  The cap is the  |
//|   upper bound, and the reason is quoted in the code: "If I had to   |
//|   use a larger stop loss to enter, that means that is not the       |
//|   entry point."                                                     |
//|                                                                    |
//|   TARGET - "a 1:2 minimum ratio but adjusts the take-profit to the  |
//|   closest higher timeframe liquidity pool.  If the pool is 1:3 or   |
//|   1:4, she extends the target accordingly."  The pools are the ones |
//|   the document marks: the Asia high/low, daily FVGs, 1-hour FVGs,   |
//|   the RTH gap quarters ("marked in quarters ... she targets the 75  |
//|   percent level") and the midnight opening price.                   |
//|                                                                    |
//|   SIZE - "A+ setups with multiple confluences: 5 contracts ... B/C  |
//|   setups with fewer confluences: 2 contracts."  The confluence      |
//|   count (Asia sweep, daily-FVG sweep, 1H-FVG fill, an equal-highs/  |
//|   lows run, displacement) drives LotsMultiplier(): A+ = full risk,  |
//|   B/C = 0.40x (= 2/5).                                              |
//|                                                                    |
//|   MANAGEMENT - "takes partial profits at the first internal         |
//|   liquidity or swing high, then moves her stop to break-even or     |
//|   trails it lower"; "Once a minor liquidity sweep occurs ... she    |
//|   trails her stop to a tighter level - sometimes to break-even";    |
//|   and "if price enters it [the 1-hour FVG] during a trade, she      |
//|   closes at least half the position".  The engine banks 1R and      |
//|   breaks even, and Manage() adds the two document-specific moves:   |
//|   a half-close when price reaches the opposing 1H FVG (once per     |
//|   position) and a trail behind the newest minor swing once a minor  |
//|   sweep has printed - never loosening a stop.                       |
//|                                                                    |
//| [interpretation]: 15/30-second monitoring ("this is not noise") is |
//| not a MetaTrader timeframe, so speed/displacement is read from M1   |
//| bar internals (body share of range, range against ATR, tick         |
//| volume).  The document's "points" are NQ index points - one index    |
//| point = one price unit, the same convention as the family's 80/20    |
//| EA, exposed as InpIndexPointSize for brokers that quote otherwise.  |
//| The sweep tolerance, gap floors, freshness windows, equal-run        |
//| tolerance, confluence threshold, the daily loss percentage (the doc |
//| quotes $3,000 on a $160,000 account = 1.875%) and the RTH scan depth |
//| are engineering numbers the document does not state.  Disclosed, not |
//| faked: scale-ins on additional FVGs (the engine holds one position  |
//| per symbol), the "outage gap" reference, copy trading across 20     |
//| Apex accounts, and the personality / lifestyle / back-test-the-     |
//| templates / mental-capital sections (human decisions).              |
//|                                                                    |
//| Rule -> code sync (see tests/test_chartfanatics_sync.py):           |
//|   R1  London 2am-5am EST kill zone   -> KillZoneEst()/EstMinutesOfDay()
//|   R2  09:30 EST New-York window      -> EstSession()                |
//|   R3  Asia high/low + swing sweeps   -> SweepLeg()/SigAsianRange()  |
//|   R4  inverted FVG entry             -> InvertedFvg()               |
//|   R5  conservative close-through wait -> closedThrough in BuildPlan()
//|   R6  London/NY stop caps            -> InpLondonMaxStopPts / InpNyMaxStopPts
//|   R7  1:2 minimum RR                 -> InpMinRR in LiquidityTargets()
//|   R8  target = closest HTF pool      -> LiquidityTargets()          |
//|   R9  RTH gap quarters (75%)         -> RthLevels()                 |
//|   R10 midnight opening price         -> RthLevels()                 |
//|   R11 A+ 5 vs B/C 2 contracts        -> ConfluenceCount()/LotsMultiplier()
//|   R12 equal highs/lows run           -> EqualRun()                  |
//|   R13 daily + 1H FVG levels          -> FvgEdges()                  |
//|   R14 1H FVG -> close half           -> Manage() half-close         |
//|   R15 minor sweep -> trail/BE        -> Manage() trail              |
//|   R16 $ daily loss limit             -> cfg.dailyLossPct            |
//|   R17 first-target partial + BE      -> cfg.partial1AtR / breakEvenAtR
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "NQ liquidity-sweep reversal scalping: EST kill-zone windows (London 02:00-05:00, New York 09:30), Asia/swing liquidity sweeps, inverted fair-value-gap entries, session stop caps in index points, HTF liquidity-pool targets with a 2R floor, confluence-based sizing and the document's FVG half-close and minor-sweep trail"

#include "..\..\Include\EACommon.mqh"

//--- which of the document's two windows may trade
enum ENUM_CF_SESSION
{
   CF_SESSION_LONDON  = 0,   // London kill zone 02:00-05:00 EST only
   CF_SESSION_NEWYORK = 1,   // New York open 09:30-09:50 EST only
   CF_SESSION_BOTH    = 2    // both (the document trades both)
};

//--- identity / risk
input string            InpSymbolsToTrade   = "US100";            // the document's instrument (NQ on a CFD feed)
input ulong             InpMagicNumber      = 3229;               // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct          = 0.50;               // Risk per trade (% of equity) - B/C setups scale to 0.40x
input int               InpStage            = 5;                  // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input int               InpServerGmtOffset  = 2;                  // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;      // Log verbosity
input double            InpCommissionPerLotRT = 0.0;              // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR         = 0.20;               // Cost gate: (spread + commission) <= xR
input bool              InpLedger           = true;               // Write the engine evidence ledger CSV
input double            InpMaxSpreadPoints  = 6.0;                // [interpretation] static spread ceiling (points)
input double            InpIndexPointSize   = 1.0;                // [interpretation] price units per NQ index point
input double            InpDailyLossPct     = 1.875;              // "$3,000 daily loss limit" on a $160,000 account
//--- windows (the document's own EST clock, UTC-5)
input ENUM_CF_SESSION   InpSessions         = CF_SESSION_BOTH;    // which window(s) may trade
input int               InpKzStartHourEst   = 2;                  // "between 2am-5am EST"
input int               InpKzEndHourEst     = 5;                  // end of the London kill zone
input int               InpNyStartHourEst   = 9;                  // "New York trades end within 10-15 minutes"
input int               InpNyStartMinEst    = 30;                 // 09:30 EST open
input int               InpNyEndHourEst     = 9;                  // 09:50 EST (the entry window, not the move)
input int               InpNyEndMinEst      = 50;
//--- sweep / liquidity
input int               InpScanBars         = 240;                // M1 bars scanned for sweeps/gaps/runs
input int               InpSweepWindow      = 30;                 // bars the sweep may sit back from the trigger
input int               InpSweepLookback    = 20;                 // bars that define the swing level being swept
input double            InpSweepTolPts      = 1.0;                // index points through the level that count as a sweep
//--- inverted FVG entry
input double            InpImpulseBody      = 0.55;               // displacement candle body share (the gap's mid bar)
input double            InpMinGapPts        = 2.0;                // fair value gap size floor (index points)
input int               InpFvgFreshBars     = 30;                 // bars allowed between the sweep and the inversion close
input double            InpDisplacementBody = 0.60;               // trigger candle body share ("speed")
input double            InpDisplacementAtr  = 1.20;               // trigger candle range in ATRs
//--- stop caps (the document's own numbers)
input double            InpLondonMaxStopPts = 25.0;               // "London session: 20-25 point max stop loss"
input double            InpNyMaxStopPts     = 40.0;               // "New York session: 30-40 points"
input double            InpStopBufferPts    = 2.0;                // buffer beyond the sweep extreme
//--- targets
input double            InpMinRR            = 2.0;                // "a 1:2 minimum ratio"
input int               InpRthScanBars      = 1500;               // M1 bars scanned for the 16:00/09:30 RTH levels
input double            InpRthTargetPct     = 75.0;               // "she targets the 75 percent level"
//--- confluence / sizing
input int               InpAPlusConfluences = 3;                  // "A+ setups with multiple confluences"
input double            InpBCSizeMult       = 0.40;               // "5 contracts" vs "2 contracts" = 2/5
input bool              InpOnlyAPlus        = false;              // "On your first 20 trades, focus only on A+ setups"
input int               InpEqualLookback    = 40;                 // bars the equal-highs/lows run is read over
input double            InpEqualTolPts      = 3.0;                // "equal" tolerance (index points)
input int               InpEqualCount       = 2;                  // matches that make a "series"
//--- management
input int               InpH1FvgBars        = 80;                 // H1 bars the 1-hour FVG levels are read from
input bool              InpCloseHalfInFvg   = true;               // "if price enters it during a trade, close at least half"
input bool              InpTrailAfterSweep  = true;               // "once a minor liquidity sweep occurs ... trails her stop"
input int               InpMinorSweepBars   = 12;                 // window of the minor sweep / swing that anchors the trail
input int               InpPartialPct       = 50;                 // the first-target partial ("partial profits at the first ... swing high")

//--- one accepted setup
struct SCfSetup
{
   int      dir;
   int      sweepBar;      // bars-ago index of the manipulation bar
   string   why;           // which liquidity the sweep took (Asia range / swing)
};

//+------------------------------------------------------------------+
class CCfNqLiquiditySweepReverse : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_NQ_LIQUIDITY_SWEEP_REVERSAL";
      cfg.sourceDoc             = "chartfanatics/glimpse/-kGVL93XfyE.md (card #26)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M1;          // "Candice enters on 1-minute charts"
      cfg.clock                 = EA_CLOCK_LONDON;    // the EST windows are converted explicitly, DST-proof
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.maxCostR              = InpMaxCostR;
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxTradesPerDay       = 6;                  // two windows, a few attempts each ([interpretation])
      cfg.maxOpenPositions      = 1;                  // the document scalps one position at a time
      cfg.minSecondsBetweenTrades = 120;              // 2 minutes between scalps ([interpretation])
      cfg.dailyLossPct          = InpDailyLossPct;    // "$3,000 daily loss limit" - dollar-based, in % terms
      cfg.weeklyLossPct         = 4.0;
      cfg.totalDdPct            = 8.0;
      cfg.useLimitEntry         = false;              // the trigger is a completed close; fill at market
      cfg.signalOnNewBarOnly    = true;
      cfg.newsFilter            = false;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_nq_sweep_ledger.csv";
      cfg.logLevel              = InpLogLevel;
      //--- "takes partial profits at the first internal liquidity or swing high, then moves her stop to break-even"
      cfg.partial1AtR           = 1.0;
      cfg.partial1Pct           = (double)InpPartialPct;
      cfg.breakEvenAtR          = 1.0;
      cfg.breakEvenOnBarClose   = true;
      cfg.trailAtR              = 0.0;                // the document's trail is the minor-sweep one, done in Manage()
      //--- a generous London-clock window around both EST windows; the exact gate is EstSession()
      cfg.sessionStartHour      = 6;                  // 02:00 EST = 07:00/08:00 London - safely inside
      cfg.sessionStartMin       = 0;
      cfg.sessionEndHour        = 16;                 // 09:50 EST = 14:50/15:50 London - safely inside
      cfg.sessionEndMin         = 0;
      cfg.noTradeAfterHour      = -1;                 // the EST gate is precise; no second cutoff
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   void OnInitStrategy()
   {
      m_lastConf = 0; m_scoreSymbol = "";
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "NQ liquidity-sweep reversal armed: %s, London KZ %02d:00-%02d:00 EST, NY %02d:%02d-%02d:%02d EST, stop caps %.0f/%.0f points, min RR %.1f, A+ >= %d confluences (B/C size %.2fx)",
             SessionName(), InpKzStartHourEst, InpKzEndHourEst,
             InpNyStartHourEst, InpNyStartMinEst, InpNyEndHourEst, InpNyEndMinEst,
             InpLondonMaxStopPts, InpNyMaxStopPts, InpMinRR, InpAPlusConfluences, InpBCSizeMult), true);
      EA_Log(EA_LOG_EVENTS, "15/30-second monitoring is not a MetaTrader timeframe - displacement is read from M1 bar internals (body share, range vs ATR, tick volume)", true);
   }

   //--- "A+ setups: 5 contracts ... B/C setups: 2 contracts"
   double LotsMultiplier(SEAContext &ctx)
   {
      if(m_scoreSymbol != ctx.symbol) return 1.0;
      return (m_lastConf >= InpAPlusConfluences) ? 1.0 : InpBCSizeMult;
   }

   //-------------------------------------------------------------------
   // The entry engine
   //-------------------------------------------------------------------
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession || ctx.atr <= 0.0) return false;

      int session = EstSession();                               // 0 none, 1 London KZ, 2 New York
      if(session == 0) return false;

      MqlRates m[];
      int got = EA_Rates(ctx.symbol, PERIOD_M1, 0, InpScanBars + InpSweepWindow + 6, m);
      if(got < InpSweepWindow + 12) return false;

      double maxStopPts = (session == 1) ? InpLondonMaxStopPts : InpNyMaxStopPts;
      double price = ctx.mid;
      if(price <= 0.0) return false;

      //--- the Asia range the document sweeps ("Asia high/low")
      double asiaHi = 0.0, asiaLo = 0.0;
      bool haveAsia = SigAsianRange(ctx.symbol, asiaHi, asiaLo);

      //--- both directions; the score decides which side wins when both are possible
      int    bestDir = 0;
      SCfSetup best;
      double bestEntry = 0.0, bestStop = 0.0, bestTarget = 0.0;
      double bestRisk = 0.0;
      int    bestConf = -1;

      for(int k = 0; k < 2; k++)
      {
         int dir = (k == 0) ? -1 : +1;

         double stop = 0.0;
         SCfSetup s;
         if(!SweepLeg(ctx, m, got, dir, haveAsia, asiaHi, asiaLo, maxStopPts, s, stop)) continue;

         double entry = FairPrice(ctx, dir);
         double risk  = MathAbs(entry - stop);
         if(risk <= 0.0) continue;

         double target = 0.0;
         if(!LiquidityTargets(ctx, m, got, dir, entry, risk, session, asiaHi, asiaLo, target)) continue;

         int conf = ConfluenceCount(ctx, m, got, dir, s, haveAsia, asiaHi, asiaLo);
         if(InpOnlyAPlus && conf < InpAPlusConfluences) continue;
         if(conf <= bestConf) continue;

         bestDir = dir; best = s; bestEntry = entry; bestStop = stop;
         bestTarget = target; bestRisk = risk; bestConf = conf;
      }
      if(bestDir == 0) return false;

      plan.dir          = bestDir;
      plan.entry        = bestEntry;
      plan.stop         = bestStop;
      plan.target       = bestTarget;
      plan.riskDist     = bestRisk;
      plan.score        = 45.0 + 11.0 * (double)bestConf;
      plan.reason       = StringFormat("sweep -> inverted FVG [%s], %d confluences", best.why, bestConf);
      plan.isLimit      = false;
      plan.barsAgo      = 1;
      plan.sweepBarsAgo = best.sweepBar;

      m_lastConf    = bestConf;                                 // read back by LotsMultiplier()
      m_scoreSymbol = ctx.symbol;
      return true;
   }

   //-------------------------------------------------------------------
   // Management: the document's own two moves
   //-------------------------------------------------------------------
   void Manage(SEAContext &ctx)
   {
      if(ctx.atr <= 0.0) return;

      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong ticket = PositionGetTicket(p);
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;

         int    dir   = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? +1 : -1;
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl    = PositionGetDouble(POSITION_SL);
         double tp    = PositionGetDouble(POSITION_TP);

         //--- "if price enters it [the 1-hour FVG] during a trade, she closes at least half the position"
         if(InpCloseHalfInFvg && ReachedOpposingH1Fvg(ctx, dir))
         {
            string key = HalfKey(ticket);
            if(!GlobalVariableCheck(key))
            {
               if(g_eaExec.CanPartial(ticket, (double)InpPartialPct))
               {
                  if(g_eaExec.ClosePartial(ticket, (double)InpPartialPct))
                  {
                     GlobalVariableSet(key, 1.0);
                     EA_Log(EA_LOG_EVENTS, StringFormat(
                            "position #%I64u: price reached the opposing 1H FVG - closed half (the document's own rule)",
                            ticket), true);
                  }
               }
               else
                  GlobalVariableSet(key, 1.0);                    // too small to split: do not retry every tick
            }
         }

         //--- "once a minor liquidity sweep occurs ... she trails her stop to a tighter level - sometimes to break-even"
         if(InpTrailAfterSweep)
         {
            double anchor = 0.0;
            if(MinorSweepAnchor(ctx, dir, anchor))                 // the newest minor swing behind the move
            {
               double buffer = InpStopBufferPts * InpIndexPointSize;
               double newSl = (dir > 0) ? (anchor - buffer) : (anchor + buffer);
               //--- never loose a stop, never below break-even once the sweep has printed
               if(dir > 0)
               {
                  if(newSl < entry) newSl = entry;
                  if(newSl > sl + ctx.point * 0.5) g_eaExec.Modify(ticket, newSl, tp);
               }
               else
               {
                  if(newSl > entry) newSl = entry;
                  if(newSl < sl - ctx.point * 0.5) g_eaExec.Modify(ticket, newSl, tp);
               }
            }
         }
      }
   }

private:
   double   m_lastConf;                                  // confluences of the last plan (sizing)
   string   m_scoreSymbol;

   //-------------------------------------------------------------------
   // The document's clock: EST is UTC-5, fixed (never DST-shifted)
   //-------------------------------------------------------------------
   int EstMinutesOfDay(const datetime serverTime)
   {
      MqlDateTime d;
      TimeToStruct(EstStamp(serverTime), d);
      return d.hour * 60 + d.min;
   }

   //--- the document's clock: EST = UTC-5, fixed (no DST), as a plain timestamp
   datetime EstStamp(const datetime serverTime)
   {
      return EA_ServerToUtc(serverTime) - (datetime)(5 * 3600);
   }

   //--- 0 = outside both windows, 1 = London kill zone, 2 = New York open
   int EstSession()
   {
      int now = EstMinutesOfDay(TimeTradeServer());
      int kzS = InpKzStartHourEst * 60;
      int kzE = InpKzEndHourEst * 60;
      int nyS = InpNyStartHourEst * 60 + InpNyStartMinEst;
      int nyE = InpNyEndHourEst * 60 + InpNyEndMinEst;
      bool london = (now >= kzS && now < kzE);                // "she avoids pre-2am setups"
      bool ny     = (now >= nyS && now < nyE);
      if(InpSessions == CF_SESSION_LONDON)  return london ? 1 : 0;
      if(InpSessions == CF_SESSION_NEWYORK) return ny ? 2 : 0;
      if(london) return 1;
      if(ny) return 2;
      return 0;
   }

   //-------------------------------------------------------------------
   // Sweep -> inverted FVG (the entry model)
   //-------------------------------------------------------------------
   bool SweepLeg(const SEAContext &ctx, const MqlRates &m[], const int got, const int dir,
                 const bool haveAsia, const double asiaHi, const double asiaLo,
                 const double maxStopPts, SCfSetup &s, double &stop)
   {
      stop = 0.0;
      double tol    = InpSweepTolPts * InpIndexPointSize;
      double minGap = InpMinGapPts * InpIndexPointSize;
      double buffer = InpStopBufferPts * InpIndexPointSize;
      double maxStop = maxStopPts * InpIndexPointSize;

      for(int sw = 1; sw <= InpSweepWindow; sw++)              // the manipulation bar, newest first
      {
         if(sw + InpSweepLookback + 2 >= got) break;
         double prior = (dir > 0) ? LowestLow(m, got, sw + 1, InpSweepLookback)
                                  : HighestHigh(m, got, sw + 1, InpSweepLookback);
         if(prior <= 0.0) continue;

         bool sweptSwing = (dir > 0) ? (m[sw].low < prior - tol) : (m[sw].high > prior + tol);
         bool sweptAsia  = haveAsia && ((dir > 0) ? (m[sw].low < asiaLo - tol) : (m[sw].high > asiaHi + tol));
         if(!sweptSwing && !sweptAsia) continue;

         //--- the counter-directional gap of the same zone, then its INVERSION:
         //--- "A bearish FVG forms when price gaps down without filling the gap.  When a
         //---  bullish candle closes above it, it becomes an inverted FVG" (the
         //---  conservative variant: the full close, not the tap inside).  The gap forms
         //---  on the way into the sweep or just after it, so the zone is deliberately
         //---  two-sided around the manipulation bar - and the inversion must be FRESH
         //---  (the previous closed bar was still on the far side), otherwise an entry
         //---  would fire bars after the actual inverted-FVG close.
         int    gapBar = 0;
         int    gOldest = (int)MathMin(got - 3, sw + InpFvgFreshBars);
         for(int g = 2; g <= gOldest; g++)
         {
            if(MathAbs(g - sw) > InpFvgFreshBars) continue;
            MqlRates left = m[g + 2], mid = m[g + 1], right = m[g];
            double gapFar = 0.0;                                  // the edge the close must clear
            if(dir > 0)
            {
               //--- a BEARISH gap (gap down), inverted by a bullish close above its upper edge
               if(!(mid.close < mid.open && EA_BodyRatio(mid) >= InpImpulseBody)) continue;
               if(!(left.low > right.high && (left.low - right.high) >= minGap)) continue;
               gapFar = left.low;
               if(!(m[1].close > gapFar + tol)) continue;         // inverted now
               if(m[2].close > gapFar + tol) continue;            // ... but already was: stale
            }
            else
            {
               //--- a BULLISH gap (gap up), inverted by a bearish close below its lower edge
               if(!(mid.close > mid.open && EA_BodyRatio(mid) >= InpImpulseBody)) continue;
               if(!(left.high < right.low && (right.low - left.high) >= minGap)) continue;
               gapFar = left.high;
               if(!(m[1].close < gapFar - tol)) continue;
               if(m[2].close < gapFar - tol) continue;            // stale inversion
            }
            gapBar = g;
            break;
         }
         if(gapBar == 0) continue;

         bool trigger = (dir > 0) ? (m[1].close > m[1].open) : (m[1].close < m[1].open);
         if(!trigger) continue;

         //--- the entry level and stop: beyond the sweep extreme, capped by the session rule
         double ext = (dir > 0) ? SweepLow(m, got, sw) : SweepHigh(m, got, sw);
         double candidate = (dir > 0) ? (ext - buffer) : (ext + buffer);
         double entry = FairPrice(ctx, dir);
         if(MathAbs(entry - candidate) > maxStop) continue;      // "that is not the entry point"
         if(dir > 0 && candidate >= entry) continue;
         if(dir < 0 && candidate <= entry) continue;

         s.dir = dir;
         s.sweepBar = sw;
         s.why = sweptAsia ? "Asia liquidity" : "swing liquidity";
         stop = candidate;
         return true;
      }
      return false;
   }

   //--- the manipulation leg's extreme: the sweep bar plus two bars either side (a spike
   //--- can print its extreme one bar later), never the trigger bar itself
   double SweepLow(const MqlRates &m[], const int got, const int fromBar)
   {
      double lo = 0.0;
      int first = (int)MathMax(2, fromBar - 2);
      int end   = (int)MathMin(got - 1, fromBar + 3);
      for(int i = first; i <= end; i++)
         if(lo == 0.0 || m[i].low < lo) lo = m[i].low;
      return lo;
   }

   double SweepHigh(const MqlRates &m[], const int got, const int fromBar)
   {
      double hi = 0.0;
      int first = (int)MathMax(2, fromBar - 2);
      int end   = (int)MathMin(got - 1, fromBar + 3);
      for(int i = first; i <= end; i++)
         if(m[i].high > hi) hi = m[i].high;
      return hi;
   }

   //--- displacement ("speed and displacement ... why seconds matter"), read from M1 internals
   bool IsDisplacement(const MqlRates &r, const SEAContext &ctx)
   {
      if(EA_BodyRatio(r) < InpDisplacementBody) return false;
      return ((r.high - r.low) >= InpDisplacementAtr * ctx.atr);
   }

   //-------------------------------------------------------------------
   // Confluences ("A+ setups have multiple confluences")
   //-------------------------------------------------------------------
   int ConfluenceCount(const SEAContext &ctx, const MqlRates &m[], const int got, const int dir,
                       const SCfSetup &s, const bool haveAsia, const double asiaHi, const double asiaLo)
   {
      int conf = 0;

      //--- 1) the sweep took session liquidity ("Asia high/low")
      if(haveAsia)
      {
         double tol = InpSweepTolPts * InpIndexPointSize;
         if(dir > 0 && m[s.sweepBar].low < asiaLo + tol) conf++;
         if(dir < 0 && m[s.sweepBar].high > asiaHi - tol) conf++;
      }

      //--- 2) the sweep took a daily FVG edge ("daily FVG sweep")
      if(DailyFvgSwept(ctx, m, s.sweepBar, dir)) conf++;

      //--- 3) price is filling a 1-hour FVG ("1-hour FVG fill")
      double h1a = 0.0, h1b = 0.0;
      if(H1FvgAligned(ctx, dir, h1a, h1b)) conf++;

      //--- 4) an equal-highs/lows run ("a series of equal highs or lows")
      if(EqualRun(m, got, dir)) conf++;

      //--- 5) the trigger candle delivered displacement
      if(IsDisplacement(m[1], ctx)) conf++;
      return conf;
   }

   //--- a "series of equal highs or lows" in the trade's direction
   bool EqualRun(const MqlRates &m[], const int got, const int dir)
   {
      int    lookback = (int)MathMin(InpEqualLookback, got - 3);
      if(lookback < 6) return false;
      double tol = InpEqualTolPts * InpIndexPointSize;
      int    matches = 0;
      double anchor = 0.0;
      for(int i = 2; i <= lookback; i++)
      {
         bool pivot = (dir > 0) ? (m[i].low < m[i - 1].low && m[i].low < m[i + 1].low)
                                : (m[i].high > m[i - 1].high && m[i].high > m[i + 1].high);
         if(!pivot) continue;
         double level = (dir > 0) ? m[i].low : m[i].high;
         if(anchor == 0.0) { anchor = level; matches = 1; continue; }
         if(MathAbs(level - anchor) <= tol) matches++;
      }
      return (matches >= InpEqualCount);
   }

   //--- the manipulation bar swept a daily FVG edge ("daily FVG sweep"): a bullish
   //--- daily gap for a long (its low edge is the support being raided) and the mirror
   //--- for a short
   bool DailyFvgSwept(const SEAContext &ctx, const MqlRates &m[], const int sweepBar, const int dir)
   {
      MqlRates d[];
      int got = EA_Rates(ctx.symbol, PERIOD_D1, 0, 30, d);
      if(got < 5 || sweepBar >= got) return false;
      double minGap = InpMinGapPts * InpIndexPointSize;
      for(int g = 1; g <= 10 && g + 2 < got; g++)
      {
         MqlRates left = d[g + 2], mid = d[g + 1], right = d[g];
         if(dir > 0)
         {
            if(!(mid.close > mid.open && left.high < right.low)) continue;
            if((right.low - left.high) < minGap) continue;
            if(m[sweepBar].low <= left.high) return true;       // the sweep dipped into the gap
         }
         else
         {
            if(!(mid.close < mid.open && left.low > right.high)) continue;
            if((left.low - right.high) < minGap) continue;
            if(m[sweepBar].high >= left.low) return true;
         }
      }
      return false;
   }

   //--- the nearest 1-hour FVG the trade is filling (bullish for longs, bearish for shorts)
   bool H1FvgAligned(const SEAContext &ctx, const int dir, double &nearEdge, double &farEdge)
   {
      nearEdge = 0.0; farEdge = 0.0;
      MqlRates h[];
      int got = EA_Rates(ctx.symbol, PERIOD_H1, 0, InpH1FvgBars + 3, h);
      if(got < 6) return false;
      double minGap = InpMinGapPts * InpIndexPointSize;
      double price = (dir > 0) ? SymbolInfoDouble(ctx.symbol, SYMBOL_BID)
                               : SymbolInfoDouble(ctx.symbol, SYMBOL_ASK);
      if(price <= 0.0) return false;
      for(int g = 1; g <= InpH1FvgBars && g + 2 < got; g++)
      {
         MqlRates left = h[g + 2], mid = h[g + 1], right = h[g];
         if(dir > 0)
         {
            if(!(mid.close > mid.open && left.high < right.low)) continue;
            if((right.low - left.high) < minGap) continue;
            if(price >= left.high && price <= right.low) { nearEdge = left.high; farEdge = right.low; return true; }
         }
         else
         {
            if(!(mid.close < mid.open && left.low > right.high)) continue;
            if((left.low - right.high) < minGap) continue;
            if(price <= left.low && price >= right.high) { nearEdge = left.low; farEdge = right.high; return true; }
         }
      }
      return false;
   }

   //--- price reaching the 1-hour FVG AGAINST the trade ("prevents overextension")
   bool ReachedOpposingH1Fvg(const SEAContext &ctx, const int dir)
   {
      MqlRates h[];
      int got = EA_Rates(ctx.symbol, PERIOD_H1, 0, InpH1FvgBars + 3, h);
      if(got < 6) return false;
      double minGap = InpMinGapPts * InpIndexPointSize;
      double price = (dir > 0) ? SymbolInfoDouble(ctx.symbol, SYMBOL_BID)
                               : SymbolInfoDouble(ctx.symbol, SYMBOL_ASK);
      if(price <= 0.0) return false;
      for(int g = 1; g <= InpH1FvgBars && g + 2 < got; g++)
      {
         MqlRates left = h[g + 2], mid = h[g + 1], right = h[g];
         if(dir > 0)
         {
            //--- a bearish H1 gap overhead: price trading up into it
            if(!(mid.close < mid.open && left.low > right.high)) continue;
            if((left.low - right.high) < minGap) continue;
            if(price >= right.high && price <= left.low + minGap) return true;
         }
         else
         {
            if(!(mid.close > mid.open && left.high < right.low)) continue;
            if((right.low - left.high) < minGap) continue;
            if(price <= right.low && price >= left.high - minGap) return true;
         }
      }
      return false;
   }

   //-------------------------------------------------------------------
   // Targets: "the closest higher timeframe liquidity pool"
   //-------------------------------------------------------------------
   bool LiquidityTargets(const SEAContext &ctx, const MqlRates &m[], const int got, const int dir,
                         const double entry, const double risk, const int session,
                         const double asiaHi, const double asiaLo, double &target)
   {
      target = 0.0;
      if(risk <= 0.0) return false;
      double need = InpMinRR * risk;                            // "a 1:2 minimum ratio"

      double best = 0.0;
      //--- the Asia high/low the document marks
      if(asiaHi > 0.0 && asiaLo > 0.0)
      {
         if(dir > 0 && asiaHi > entry + need) best = PickNear(best, asiaHi, dir);
         if(dir < 0 && asiaLo < entry - need) best = PickNear(best, asiaLo, dir);
      }

      //--- daily and 1-hour FVG edges
      best = PickFvgLevels(ctx, dir, entry, need, best, PERIOD_D1, 30);
      best = PickFvgLevels(ctx, dir, entry, need, best, PERIOD_H1, InpH1FvgBars);

      //--- the RTH gap quarters and the midnight opening price
      double q25 = 0.0, q50 = 0.0, q75 = 0.0, midnight = 0.0;
      if(RthLevels(ctx, q25, q50, q75, midnight))
      {
         if(dir > 0)
         {
            if(q75 > entry + need) best = PickNear(best, q75, dir);       // "she targets the 75 percent level"
            if(midnight > entry + need) best = PickNear(best, midnight, dir);
         }
         else
         {
            if(q25 < entry - need) best = PickNear(best, q25, dir);
            if(midnight < entry - need) best = PickNear(best, midnight, dir);
         }
         if(session == 2 && q50 > 0.0)                                     // intraday reference in the NY window
         {
            if(dir > 0 && q50 > entry + need) best = PickNear(best, q50, dir);
            if(dir < 0 && q50 < entry - need) best = PickNear(best, q50, dir);
         }
      }

      //--- the recent swing extreme as the fallback pool
      double swHi = HighestHigh(m, got, 1, (int)MathMin(InpScanBars, got - 2));
      double swLo = LowestLow(m, got, 1, (int)MathMin(InpScanBars, got - 2));
      if(dir > 0 && swHi > entry + need) best = PickNear(best, swHi, dir);
      if(dir < 0 && swLo < entry - need) best = PickNear(best, swLo, dir);

      if(best == 0.0) return false;
      target = best;
      return true;
   }

   //--- nearest candidate beyond the floor (in the trade's direction)
   double PickNear(const double current, const double candidate, const int dir)
   {
      if(current == 0.0) return candidate;
      if(dir > 0) return (candidate < current ? candidate : current);
      return (candidate > current ? candidate : current);
   }

   double PickFvgLevels(const SEAContext &ctx, const int dir, const double entry, const double need,
                        const double current, const ENUM_TIMEFRAMES tf, const int bars)
   {
      MqlRates h[];
      int got = EA_Rates(ctx.symbol, tf, 0, bars + 3, h);
      if(got < 6) return current;
      double minGap = InpMinGapPts * InpIndexPointSize;
      double best = current;
      for(int g = 1; g <= bars && g + 2 < got; g++)
      {
         MqlRates left = h[g + 2], mid = h[g + 1], right = h[g];
         if(dir > 0)
         {
            if(!(mid.close > mid.open && left.high < right.low && (right.low - left.high) >= minGap)) continue;
            if(right.low > entry + need) best = PickNear(best, right.low, dir);
         }
         else
         {
            if(!(mid.close < mid.open && left.low > right.high && (left.low - right.high) >= minGap)) continue;
            if(right.high < entry - need) best = PickNear(best, right.high, dir);
         }
      }
      return best;
   }

   //--- the RTH gap quarters ("the gap between 4pm close and 9:30am open ... marked in quarters")
   //--- and the midnight opening price, both on the document's EST clock
   bool RthLevels(const SEAContext &ctx, double &q25, double &q50, double &q75, double &midnight)
   {
      q25 = 0.0; q50 = 0.0; q75 = 0.0; midnight = 0.0;
      MqlRates m[];
      int got = EA_Rates(ctx.symbol, PERIOD_M1, 0, InpRthScanBars, m);
      if(got < 60) return false;

      int todayDate = EstDate(TimeTradeServer());
      int nyMin     = InpNyStartHourEst * 60 + InpNyStartMinEst;
      double close16 = 0.0, open930 = 0.0;
      bool haveClose = false, haveOpen = false;

      for(int i = 1; i < got; i++)                              // newest first
      {
         int mins = EstMinutesOfDay(m[i].time);
         int date = EstDate(m[i].time);

         //--- the midnight opening price: "mark your higher timeframe liquidity
         //--- (daily FVG, 1-hour FVG, RTH gap, midnight opening price)"
         if(midnight == 0.0 && date == todayDate && mins < 5)
            midnight = m[i].open;

         //--- "the gap between 4pm close and 9:30am open": today's open, then the
         //--- most recent 16:00 EST close older than it (yesterday's cash close)
         if(!haveOpen && date == todayDate && mins >= nyMin && mins < nyMin + 5)
         {
            open930 = m[i].open;
            haveOpen = true;
            continue;
         }
         if(haveOpen && !haveClose && mins >= 16 * 60 && mins < 16 * 60 + 5)
         {
            close16 = m[i].close;
            haveClose = true;
         }
         if(midnight != 0.0 && haveOpen && haveClose) break;
      }

      //--- "marked in quarters (25 percent, 50 percent, 75 percent, 100 percent)"
      if(haveOpen && haveClose && MathAbs(close16 - open930) > InpMinGapPts * InpIndexPointSize)
      {
         double hi = MathMax(close16, open930);
         double lo = MathMin(close16, open930);
         q25 = lo + 0.25 * (hi - lo);
         q50 = lo + 0.50 * (hi - lo);
         q75 = lo + InpRthTargetPct / 100.0 * (hi - lo);          // "she targets the 75 percent level"
      }
      return (q50 > 0.0 || midnight > 0.0);
   }

   int EstDate(const datetime serverTime)
   {
      MqlDateTime d;
      TimeToStruct(EstStamp(serverTime), d);                    // datetime maths handles the rollover
      return d.year * 10000 + d.mon * 100 + d.day;
   }

   //--- the newest minor swing behind the move, once a minor sweep has printed
   bool MinorSweepAnchor(const SEAContext &ctx, const int dir, double &anchor)
   {
      anchor = 0.0;
      MqlRates m[];
      int got = EA_Rates(ctx.symbol, PERIOD_M1, 0, InpMinorSweepBars + 6, m);
      if(got < InpMinorSweepBars + 4) return false;

      //--- a minor sweep: the last bars took a small swing extreme in the trade's direction
      bool swept = false;
      for(int i = 2; i <= 4 && !swept; i++)
      {
         double prior = (dir > 0) ? HighestHigh(m, got, i + 1, InpMinorSweepBars)
                                  : LowestLow(m, got, i + 1, InpMinorSweepBars);
         if(prior <= 0.0) continue;
         if(dir > 0 && m[i].high > prior) swept = true;
         if(dir < 0 && m[i].low  < prior) swept = true;
      }
      if(!swept) return false;

      //--- the anchor is the mirror swing: the newest minor high behind a long / low behind a short
      MqlRates r[];
      int rg = EA_Rates(ctx.symbol, PERIOD_M1, 1, InpMinorSweepBars, r);
      if(rg < 6) return false;
      for(int i = 1; i < rg - 1; i++)
      {
         bool pivot = (dir > 0) ? (r[i].low < r[i - 1].low && r[i].low < r[i + 1].low)
                                : (r[i].high > r[i - 1].high && r[i].high > r[i + 1].high);
         if(!pivot) continue;
         anchor = (dir > 0) ? r[i].low : r[i].high;
         return true;
      }
      return false;
   }

   //-------------------------------------------------------------------
   // Small helpers
   //-------------------------------------------------------------------
   double FairPrice(const SEAContext &ctx, const int dir)
   {
      if(dir > 0) return (ctx.ask > 0.0) ? ctx.ask : ctx.mid;
      return (ctx.bid > 0.0) ? ctx.bid : ctx.mid;
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

   string HalfKey(const ulong ticket)
   {
      long opened = 0;
      if(PositionSelectByTicket(ticket)) opened = (long)PositionGetInteger(POSITION_TIME);
      return StringFormat("EA_%I64u_%I64u_FVGHALF_%I64d", InpMagicNumber, ticket, opened);
   }

   string SessionName()
   {
      if(InpSessions == CF_SESSION_LONDON)  return "London kill zone only";
      if(InpSessions == CF_SESSION_NEWYORK) return "New York open only";
      return "London kill zone + New York open";
   }
};

CCfNqLiquiditySweepReverse g_cfNqLiquiditySweep;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfNqLiquiditySweep);
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
