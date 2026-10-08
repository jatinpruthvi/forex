//+------------------------------------------------------------------+
//|              EA_CF_OrderflowTradingMasterclass.mq5                |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| "OrderFlow Masterclass" - Carmine Rosato's playbook (Apr 2025)    |
//| Card    : chartfanatics/todos/orderflow-trading-masterclass.md (#29)
//| Source  : chartfanatics/pdf/orderflow-trading-masterclass.pdf     |
//| Magic   : 3232                                                    |
//|                                                                  |
//| Verdict: MECHANIZABLE.  The document teaches the auction and then |
//| hands over two fully worked setups with numbers.  It is not only  |
//| theory - the two case studies are engine-expressible rules:       |
//|                                                                   |
//|   * "Stop Run and Reclaim Long": price flushed below the previous |
//|     day's low, heavy negative delta printed, but price stopped    |
//|     moving lower (absorption at the lows), and once it reclaimed  |
//|     the previous day's low the trapped sellers were forced to     |
//|     cover.  "The long entry came on the reclaim ... with a stop   |
//|     just below the low of the flush."  The 5844 level had already |
//|     acted as support four or five times that session.             |
//|   * "Absorption Short at Resistance": a wall of resting sell      |
//|     orders around 5710; aggressive buyers kept lifting the offers |
//|     with strong positive delta "yet the price wasn't moving        |
//|     higher"; when the buying faded, sellers took over and price    |
//|     rejected the level.                                           |
//|                                                                   |
//| The framework the document closes on - "Context, Location, and     |
//| Confirmation" - is the EA's three gates: context = a real push     |
//| into the level (aggression, read from volume); location = a        |
//| documented level (previous day high/low, the session extreme, a    |
//| value-area edge / POC, or a level the session has already tested   |
//| several times - "it had already acted as support four or five      |
//| times"); confirmation = absorption (heavy volume, no progress,     |
//| the close back on the defended side) and, for the stop-run setup,  |
//| the reclaim itself.                                                |
//|                                                                   |
//| [interpretation] - everything the tools the document requires      |
//| cannot give an MT5 EA, always labelled:                            |
//|   * DOM, heatmap and footprint chart (resting limit orders, order |
//|     book depth, bid-vs-ask executed volume) do not exist here.     |
//|     "Aggression" is read as body-directional tick volume, the      |
//|     "delta divergence" as that skew failing to progress price,     |
//|     and a "liquidity wall" as a level the session has tested and   |
//|     held repeatedly (the footprint analogue) plus a high-volume    |
//|     node in the volume profile.  Nothing pretends to be a real     |
//|     order book.                                                    |
//|   * the volume profile is built from bar tick volume in price bins |
//|     (the family's proxy); the 70% value area is the standard split |
//|     the document does not quantify.                                |
//|   * the document states no stop size, no target rule, no sizing    |
//|     ladder and no session window: the stop is structural (beyond   |
//|     the flush / test extreme), the target is the rotation back to  |
//|     the value reference (POC / opposite edge / opposite extreme)   |
//|     with a minimum R multiple, the size is single-risk, and the    |
//|     RTH window is the case studies' own context.  All exposed as   |
//|     inputs and marked as engineering numbers.                      |
//|   * the engine's partial / break-even / trailing machinery is off  |
//|     because the document states no management rules - the plan's   |
//|     target is the exit, exactly as the case studies trade.         |
//|                                                                    |
//| Rule -> code sync (see tests/test_chartfanatics_sync.py):          |
//|   R1  limit vs market orders    -> the aggression proxy (volume +  |
//|                                    body direction), the auction read
//|   R2  absorption                -> AbsorptionAt() (heavy, no        |
//|                                    progress, close back, wick)      |
//|   R3  liquidity wall            -> TouchCount() (a tested level) +  |
//|                                    the profile's high-volume node   |
//|   R4  stop run / liquidity grab -> StopRunReclaim() (a flush        |
//|                                    through the level)               |
//|   R5  reclaim entry             -> "the long entry came on the      |
//|                                    reclaim" - the reclaim close     |
//|   R6  stop below the flush low  -> StopRunReclaim()'s structural    |
//|                                    stop                             |
//|   R7  delta cannot be seen      -> DeltaLean() body-volume proxy    |
//|   R8  delta divergence          -> the skew leans into the level    |
//|                                    while price does not progress    |
//|   R9  volume profile / value    -> BuildProfile() POC / VAH / VAL   |
//|   R10 a level tested 4-5 times  -> InpStrongTouchCount / sizing     |
//|   R11 context gate              -> ImpulseContext()                 |
//|   R12 location gate             -> CollectLevels()                  |
//|   R13 confirmation gate         -> AbsorptionAt() + the reclaim     |
//|   R14 day trading / RTH         -> the session window               |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "Chart Fanatics OrderFlow Masterclass - absorption at a level and the stop-run reclaim, gated by the document's own Context / Location / Confirmation framework"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade     = "US100,US500";      // "Futures" per the playbook
input ulong             InpMagicNumber        = 3232;               // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct            = 0.40;               // "tight and efficient risk"
input int               InpStage              = 5;                  // 5-Stage framework stage (5 = policy off)
input double            InpMaxSpreadPoints    = 3.0;                // Spread gate in points (0 = off)
input double            InpDailyLossPct       = 1.50;               // Halt for the day at -x% (0 = off)
input double            InpWeeklyLossPct      = 3.0;
input double            InpTotalDdPct         = 8.0;
input int               InpServerGmtOffset    = 2;                  // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel           = EA_LOG_EVENTS;      // Log verbosity
input double            InpCommissionPerLotRT = 0.0;                // Round-turn commission per lot
input double            InpMaxCostR           = 0.12;               // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;               // Write the engine evidence ledger CSV
//--- the session (day trading; the case studies are the regular session)
input int    InpSessionStartHour  = 14;    // 14:30 London = 09:30 ET
input int    InpSessionStartMin   = 30;
input int    InpSessionEndHour    = 20;    // 20:30 London = 15:30 ET
input int    InpSessionEndMin     = 30;
input int    InpMaxTradesPerDay   = 4;
//--- context: a real push must exist before a level can be defended
input int    InpImpulseBars       = 6;      // Bars the push is measured over
input double InpImpulseAtr        = 0.80;   // [interpretation] push size that counts as aggression
input double InpPushVolMult       = 1.30;   // [interpretation] push volume vs the window median
//--- location: the documented levels
input int    InpLevelLookback     = 240;    // Bars scanned for repeated-touch levels (M5: ~20h)
input int    InpSwingStrength     = 2;      // Fractal strength for candidate levels
input double InpTouchTolAtr       = 0.15;   // [interpretation] how close a test must come to the level
input int    InpMinTouches        = 2;      // A level needs at least this many tests to matter
input int    InpStrongTouchCount  = 4;      // "it had already acted as support four or five times"
input int    InpMaxLevels         = 12;     // Cap on the level list
//--- confirmation: absorption and the delta divergence ("strong positive delta ...
//--- but the price fails to move higher" is the document's key insight)
input int    InpDeltaBars         = 12;     // Bars of the aggressive-side read
input double InpDeltaLeanCut      = 0.10;   // [interpretation] the skew that counts as one side being aggressive
input double InpAbsorbVolMult     = 2.00;   // [interpretation] heavy test volume vs the window median
input double InpAbsorbMaxProgress = 0.25;   // [interpretation] progress beyond the level that still counts as none
input double InpWickPct           = 0.35;   // The rejection wick's share of the bar's range
input int    InpTestBars          = 3;      // The test and the control-flip close live in this window
//--- the stop run
input double InpFlushMinAtr       = 0.15;   // [interpretation] the flush must clear the level by this much
input int    InpReclaimBars       = 3;      // The reclaim must follow within this many bars
//--- stops / targets
input double InpMinStopAtr        = 0.15;   // Reject stops tighter than this
input int    InpStopBufferTicks   = 2;      // Buffer beyond the extreme (keeps the stop off the wick)
input double InpStopBufferAtr     = 0.08;
input double InpMinRR             = 1.50;   // The target must pay for the risk
input double InpStrongSizeMult    = 1.00;   // [interpretation] the doc gives no sizing ladder (1.0 = unchanged)
//--- the value profile (the "where value was accepted" reference)
input int    InpProfileBins       = 40;
input double InpValueAreaPct      = 0.70;
input int    InpProfileBars       = 420;

//+------------------------------------------------------------------+
struct SVolProfile
{
   double poc, val, vah;
   double lo, size;
   int    nb, pocBin, valBin, vahBin;
   bool   ok;
};

//+------------------------------------------------------------------+
//| A level of interest: where the document expects the auction to    |
//| be defended (previous day, session extreme, value edge, or a      |
//| level the session has tested and held several times)              |
//+------------------------------------------------------------------+
struct SLevelInfo
{
   double price;
   int    touches;
   int    kind;      // 1 = previous day, 2 = session, 3 = value area, 4 = repeated test
};

//+------------------------------------------------------------------+
struct SCfSetup
{
   int    dir;
   double stop, target, risk;
   int    touches;
   string why;
};

//+------------------------------------------------------------------+
class CCfOrderflowMasterclass : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_ORDERFLOW_MASTERCLASS";
      cfg.sourceDoc             = "chartfanatics/pdf/orderflow-trading-masterclass.pdf (card #29)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;      // day trading; the case studies are intraday
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = InpWeeklyLossPct;
      cfg.totalDdPct            = InpTotalDdPct;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 120;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = false;
      cfg.newsFilter            = false;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_orderflow_masterclass_ledger.csv";
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.logLevel              = InpLogLevel;
      cfg.sessionStartHour = InpSessionStartHour;  cfg.sessionStartMin = InpSessionStartMin;
      cfg.sessionEndHour   = InpSessionEndHour;    cfg.sessionEndMin   = InpSessionEndMin;
      cfg.noTradeAfterHour = InpSessionEndHour;    cfg.noTradeAfterMin = InpSessionEndMin;
      //--- the document states no management rules: the plan's target is the exit
      cfg.partial1AtR   = 0.0;
      cfg.breakEvenAtR  = 0.0;
      cfg.trailAtR      = 0.0;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   void OnInitStrategy()
   {
      m_lastTouches = 0;
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "orderflow masterclass armed: %s, M5, session %02d:%02d-%02d:%02d London, min %d touches, min RR %.2f",
             InpSymbolsToTrade, InpSessionStartHour, InpSessionStartMin,
             InpSessionEndHour, InpSessionEndMin, InpMinTouches, InpMinRR), true);
      EA_Log(EA_LOG_EVENTS, "gates: Context (a real push) -> Location (a documented level) -> Confirmation (absorption, and the reclaim for a stop run)", true);
   }

   //--- "acted as support four or five times": size the well-tested levels up
   double LotsMultiplier(SEAContext &ctx)
   {
      return (m_lastTouches >= InpStrongTouchCount) ? InpStrongSizeMult : 1.0;
   }

   //-------------------------------------------------------------------
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession || ctx.atr <= 0.0) return false;

      //--- CONTEXT: the document waits for a real push before fading a level
      if(!ImpulseContext(ctx)) return false;

      SVolProfile prof;
      if(!BuildProfile(ctx.symbol, prof)) return false;

      SLevelInfo levels[];
      int nLevels = 0;
      if(!CollectLevels(ctx, prof, levels, nLevels) || nLevels <= 0) return false;

      MqlRates r[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, 120, r);   // r[0] is the forming bar
      if(got < 60) return false;

      //--- LOCATION + CONFIRMATION: walk the levels, both directions
      SCfSetup best;
      best.dir = 0;
      for(int i = 0; i < nLevels; i++)
      {
         for(int d = -1; d <= 1; d += 2)
         {
            SCfSetup s;
            s.dir = 0;
            if(StopRunReclaim(ctx, r, got, levels[i], d, s))            // the flush + reclaim
            {
               if(best.dir == 0 || levels[i].touches > best.touches) best = s;
               continue;
            }
            if(AbsorptionAt(ctx, r, got, levels[i], d, s))              // the wall that held
            {
               if(best.dir == 0 || levels[i].touches > best.touches) best = s;
            }
         }
      }
      if(best.dir == 0) return false;

      plan.dir      = best.dir;
      plan.entry    = (best.dir > 0) ? ctx.ask : ctx.bid;
      plan.stop     = best.stop;
      plan.target   = best.target;
      plan.riskDist = best.risk;
      int capped = (int)MathMin(4, best.touches);
      plan.score    = 40 + capped * 10;
      plan.reason   = best.why;
      plan.isLimit  = false;
      m_lastTouches = best.touches;
      return (best.risk >= InpMinStopAtr * ctx.atr);
   }

private:
   int m_lastTouches;

   //-------------------------------------------------------------------
   // helpers
   //-------------------------------------------------------------------
   double MedianVolume(const MqlRates &r[], const int got)
   {
      double v[];
      ArrayResize(v, got);
      for(int i = 0; i < got; i++) v[i] = (double)r[i].tick_volume;
      for(int i = 1; i < got; i++)
      {
         double key = v[i];
         int j = i - 1;
         while(j >= 0 && v[j] > key) { v[j + 1] = v[j]; j--; }
         v[j + 1] = key;
      }
      if(got % 2 == 1) return v[got / 2];
      return 0.5 * (v[got / 2 - 1] + v[got / 2]);
   }

   //--- the document's delta read: which side was aggressive (ask vs bid
   //--- transactions).  MT5 exposes no bid/ask executed volume, so the proxy is
   //--- body-directional tick volume - labelled, like every order-flow proxy here
   double DeltaLean(const string sym, const int bars)
   {
      MqlRates r[];
      int got = EA_Rates(sym, g_eaIndTf, 1, bars + 2, r);
      if(got < 5) return 0.0;
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

   //--- CONTEXT: "aggressive participants reveal intent" - a push with volume
   bool ImpulseContext(const SEAContext &ctx)
   {
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 1, InpImpulseBars + 2, r);
      if(got < InpImpulseBars + 1 || ctx.atr <= 0.0) return false;
      double med = MedianVolume(r, got);
      if(med <= 0.0) return false;

      double move = r[0].close - r[InpImpulseBars - 1].close;
      if(MathAbs(move) >= InpImpulseAtr * ctx.atr) return true;

      //--- or a single aggressive bar (the flush / the push into the wall)
      for(int i = 0; i < got; i++)
      {
         if((double)r[i].tick_volume < InpPushVolMult * med) continue;
         if(MathAbs(r[i].close - r[i].open) >= InpImpulseAtr * ctx.atr * 0.5) return true;
      }
      return false;
   }

   //--- the value profile (developing session), the family's tick-volume proxy
   bool BuildProfile(const string sym, SVolProfile &out)
   {
      out.ok = false;
      if(InpProfileBins < 8) return false;
      MqlRates r[];
      int got = EA_Rates(sym, g_eaIndTf, 0, InpProfileBars + 2, r);
      if(got < 30) return false;

      datetime winStart = DayStart(EA_ClockNow()) + (datetime)(InpSessionStartHour * 3600 + InpSessionStartMin * 60);
      int fromBar = -1;
      for(int i = got - 1; i >= 0; i--)
      {
         if(EA_BarClockTime(r[i].time) < winStart) break;
         fromBar = i;
      }
      if(fromBar < 0 || got - fromBar < 20) fromBar = 0;

      double hi = -DBL_MAX, lo = DBL_MAX;
      for(int i = fromBar; i < got; i++)
      { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }
      if(hi <= lo) return false;

      int nb = InpProfileBins;
      double size = (hi - lo) / (double)nb;
      double binVol[];
      ArrayResize(binVol, nb);
      ArrayInitialize(binVol, 0.0);
      for(int i = fromBar; i < got; i++)
      {
         int b1 = (int)MathMax(0, MathMin(nb - 1, (int)MathFloor((r[i].low  - lo) / size)));
         int b2 = (int)MathMax(0, MathMin(nb - 1, (int)MathFloor((r[i].high - lo) / size)));
         double v = (double)r[i].tick_volume;
         int span = b2 - b1 + 1;
         for(int b = b1; b <= b2; b++) binVol[b] += v / (double)span;
      }

      int pocBin = 0;
      double total = 0.0;
      for(int b = 0; b < nb; b++)
      {
         total += binVol[b];
         if(binVol[b] > binVol[pocBin]) pocBin = b;
      }
      if(total <= 0.0) return false;

      int loBin = pocBin, hiBin = pocBin;
      double covered = binVol[pocBin];
      while(covered < InpValueAreaPct * total && (loBin > 0 || hiBin < nb - 1))
      {
         double below = (loBin > 0)      ? binVol[loBin - 1] : -1.0;
         double above = (hiBin < nb - 1) ? binVol[hiBin + 1] : -1.0;
         if(above >= below) { hiBin++; covered += binVol[hiBin]; }
         else               { loBin--; covered += binVol[loBin]; }
      }

      out.poc    = lo + (pocBin + 0.5) * size;
      out.val    = lo + loBin * size;
      out.vah    = lo + (hiBin + 1) * size;
      out.lo     = lo;
      out.size   = size;
      out.nb     = nb;
      out.pocBin = pocBin;
      out.valBin = loBin;
      out.vahBin = hiBin;
      out.ok     = true;
      return true;
   }

   datetime DayStart(const datetime clockTime)
   {
      MqlDateTime d;
      TimeToStruct(clockTime, d);
      d.hour = 0; d.min = 0; d.sec = 0;
      return StructToTime(d);
   }

   //--- how many times the session has tested this price ("support four or five times")
   int TouchCount(const string sym, const double price, const double tol)
   {
      MqlRates r[];
      int got = EA_Rates(sym, g_eaIndTf, 1, InpLevelLookback, r);
      if(got < 20) return 0;
      int n = 0;
      for(int i = 0; i < got; i++)
      {
         if(MathAbs(r[i].high - price) <= tol || MathAbs(r[i].low - price) <= tol) n++;
         else if(price > r[i].low && price < r[i].high) n++;      // traded through the level
      }
      return n;
   }

   void AddLevel(SLevelInfo &lv[], int &n, const double price, const int touches, const int kind)
   {
      if(price <= 0.0 || n >= InpMaxLevels) return;
      for(int i = 0; i < n; i++)
         if(MathAbs(lv[i].price - price) <= 1e-9) return;         // already known
      lv[n].price   = price;
      lv[n].touches = touches;
      lv[n].kind    = kind;
      n++;
   }

   //--- LOCATION: previous day high/low, the session extreme, the value area,
   //--- and the levels the session has already tested and held
   bool CollectLevels(const SEAContext &ctx, const SVolProfile &prof, SLevelInfo &lv[], int &n)
   {
      n = 0;
      ArrayResize(lv, InpMaxLevels);
      double tol = InpTouchTolAtr * ctx.atr;

      MqlRates d[];
      int got = EA_Rates(ctx.symbol, PERIOD_D1, 1, 2, d);
      if(got >= 1 && d[0].high > 0.0)
      {
         AddLevel(lv, n, d[0].high, TouchCount(ctx.symbol, d[0].high, tol), 1);
         AddLevel(lv, n, d[0].low,  TouchCount(ctx.symbol, d[0].low,  tol), 1);
      }

      //--- the regular-session extreme (the case studies' own context)
      double sHi = 0.0, sLo = 0.0;
      int bars = 0;
      int nowMin = EA_MinutesOfDay(EA_ClockNow());
      int toMin = (int)MathMax(nowMin, InpSessionStartHour * 60 + InpSessionStartMin + 1);
      if(SigRangeForDay(ctx.symbol, g_eaIndTf, InpSessionStartHour * 60 + InpSessionStartMin,
                        toMin, 0, sHi, sLo, bars))
      {
         if(sHi > 0.0) AddLevel(lv, n, sHi, TouchCount(ctx.symbol, sHi, tol), 2);
         if(sLo > 0.0) AddLevel(lv, n, sLo, TouchCount(ctx.symbol, sLo, tol), 2);
      }

      if(prof.ok)
      {
         AddLevel(lv, n, prof.vah, TouchCount(ctx.symbol, prof.vah, tol), 3);
         AddLevel(lv, n, prof.val, TouchCount(ctx.symbol, prof.val, tol), 3);
         AddLevel(lv, n, prof.poc, TouchCount(ctx.symbol, prof.poc, tol), 3);
      }

      //--- repeated-touch levels from the session's own swing extremes
      MqlRates r[];
      int rg = EA_Rates(ctx.symbol, g_eaIndTf, 1, InpLevelLookback, r);
      if(rg < 30) return (n > 0);
      for(int i = InpSwingStrength; i < rg - InpSwingStrength; i++)
      {
         bool hi = true, lo = true;
         for(int k = 1; k <= InpSwingStrength; k++)
         {
            if(r[i].high <= r[i - k].high || r[i].high <= r[i + k].high) hi = false;
            if(r[i].low  >= r[i - k].low  || r[i].low  >= r[i + k].low)  lo = false;
         }
         if(!hi && !lo) continue;
         double px = hi ? r[i].high : r[i].low;
         int tc = TouchCount(ctx.symbol, px, tol);
         if(tc >= InpMinTouches) AddLevel(lv, n, px, tc, 4);
      }
      return (n > 0);
   }

   //--- CONFIRMATION: absorption - "aggressive orders hit the market, but the
   //--- price barely moves" against a level, then control flips
   bool AbsorptionAt(const SEAContext &ctx, const MqlRates &r[], const int got,
                     const SLevelInfo &lvl, const int dir, SCfSetup &out)
   {
      if(lvl.price <= 0.0) return false;
      double tol  = MathMax(InpTouchTolAtr * ctx.atr, ctx.point);
      double prog = InpAbsorbMaxProgress * ctx.atr;
      double med  = MedianVolume(r, got);
      if(med <= 0.0) return false;

      //--- the delta divergence: the aggressive side must have been pushing INTO
      //--- the level while the price failed to progress - that is the absorption
      double lean = DeltaLean(ctx.symbol, InpDeltaBars);
      if(dir < 0 && lean <  InpDeltaLeanCut) return false;   // buyers were the aggressive side
      if(dir > 0 && lean > -InpDeltaLeanCut) return false;   // sellers were the aggressive side

      //--- dir = -1: fade a push UP into the level; dir = +1: fade a push DOWN into it
      for(int i = 1; i <= InpTestBars && i < got; i++)
      {
         if((double)r[i].tick_volume < InpAbsorbVolMult * med) continue;    // not "aggressive"

         if(dir < 0)
         {
            if(r[i].high < lvl.price - tol) continue;                       // never reached the level
            if(r[i].high > lvl.price + prog) continue;                      // broke through: not absorbed
            if(r[i].close >= lvl.price) continue;                           // closed through: no rejection
            if(EA_WickRatio(r[i], -1) < InpWickPct) continue;               // the rejection wick is tiny
            //--- the control flip: a newer bar pushes away from the level
            if(i < 2) continue;
            if(r[i - 1].close > r[i - 1].open) continue;                    // the flip bar must sell
            double entry = ctx.bid;
            double buf = MathMax(InpStopBufferAtr * ctx.atr, InpStopBufferTicks * ctx.point);
            out.dir    = -1;
            out.stop   = MathMax(r[i].high, r[i - 1].high) + buf;
            out.risk   = MathAbs(entry - out.stop);
            if(out.risk < InpMinStopAtr * ctx.atr) continue;
            if(!BestTarget(ctx, r, got, -1, entry, out.risk, out)) continue;
            out.touches = lvl.touches;
            out.why     = StringFormat("absorption at %s (level %s, %d touches): aggressive buys failed, sellers took over",
                                       DoubleToString(lvl.price, 2),
                                       (lvl.kind == 1 ? "previous day" : (lvl.kind == 2 ? "session extreme" :
                                       (lvl.kind == 3 ? "value area" : "repeated test"))), lvl.touches);
            return true;
         }
         else
         {
            if(r[i].low > lvl.price + tol) continue;
            if(r[i].low < lvl.price - prog) continue;
            if(r[i].close <= lvl.price) continue;
            if(EA_WickRatio(r[i], 1) < InpWickPct) continue;
            if(i < 2) continue;
            if(r[i - 1].close < r[i - 1].open) continue;                    // the flip bar must buy
            double entry = ctx.bid;
            double buf = MathMax(InpStopBufferAtr * ctx.atr, InpStopBufferTicks * ctx.point);
            out.dir    = 1;
            out.stop   = MathMin(r[i].low, r[i - 1].low) - buf;
            out.risk   = MathAbs(out.stop - entry);
            if(out.risk < InpMinStopAtr * ctx.atr) continue;
            if(!BestTarget(ctx, r, got, 1, entry, out.risk, out)) continue;
            out.touches = lvl.touches;
            out.why     = StringFormat("absorption at %s (level %s, %d touches): aggressive sells failed, buyers took over",
                                       DoubleToString(lvl.price, 2),
                                       (lvl.kind == 1 ? "previous day" : (lvl.kind == 2 ? "session extreme" :
                                       (lvl.kind == 3 ? "value area" : "repeated test"))), lvl.touches);
            return true;
         }
      }
      return false;
   }

   //--- the stop run: a flush through the level, then the reclaim
   bool StopRunReclaim(const SEAContext &ctx, const MqlRates &r[], const int got,
                       const SLevelInfo &lvl, const int dir, SCfSetup &out)
   {
      if(lvl.price <= 0.0 || ctx.atr <= 0.0) return false;
      double flush = InpFlushMinAtr * ctx.atr;

      for(int i = 1; i <= InpReclaimBars && i < got; i++)
      {
         if(dir > 0)
         {
            //--- flushed below the level, then reclaimed it (the trapped sellers cover)
            if(r[i].low > lvl.price - flush) continue;
            bool reclaimed = false;
            for(int k = i - 1; k >= 1 && k >= i - InpReclaimBars; k--)
               if(r[k].close > lvl.price) { reclaimed = true; break; }
            if(!reclaimed) continue;
            double entry = ctx.ask;
            double buf = MathMax(InpStopBufferAtr * ctx.atr, InpStopBufferTicks * ctx.point);
            out.dir  = 1;
            out.stop = r[i].low - buf;                                      // "a stop just below the low of the flush"
            out.risk = MathAbs(entry - out.stop);
            if(out.risk < InpMinStopAtr * ctx.atr) continue;
            if(!BestTarget(ctx, r, got, 1, entry, out.risk, out)) continue;
            out.touches = lvl.touches;
            out.why     = StringFormat("stop run: flush below %s then the reclaim (level %s, %d touches)",
                                       DoubleToString(lvl.price, 2),
                                       (lvl.kind == 1 ? "previous day" : (lvl.kind == 2 ? "session extreme" :
                                       (lvl.kind == 3 ? "value area" : "repeated test"))), lvl.touches);
            return true;
         }
         else
         {
            if(r[i].high < lvl.price + flush) continue;
            bool reclaimed = false;
            for(int k = i - 1; k >= 1 && k >= i - InpReclaimBars; k--)
               if(r[k].close < lvl.price) { reclaimed = true; break; }
            if(!reclaimed) continue;
            double entry = ctx.bid;
            double buf = MathMax(InpStopBufferAtr * ctx.atr, InpStopBufferTicks * ctx.point);
            out.dir  = -1;
            out.stop = r[i].high + buf;
            out.risk = MathAbs(out.stop - entry);
            if(out.risk < InpMinStopAtr * ctx.atr) continue;
            if(!BestTarget(ctx, r, got, -1, entry, out.risk, out)) continue;
            out.touches = lvl.touches;
            out.why     = StringFormat("stop run: flush above %s then the reclaim (level %s, %d touches)",
                                       DoubleToString(lvl.price, 2),
                                       (lvl.kind == 1 ? "previous day" : (lvl.kind == 2 ? "session extreme" :
                                       (lvl.kind == 3 ? "value area" : "repeated test"))), lvl.touches);
            return true;
         }
      }
      return false;
   }

   //--- the rotation target: the other side of the range the trade is fading,
   //--- never closer than the minimum R multiple ("price quickly rejected 5710
   //--- and rotated lower"; "...price moved sharply higher, producing a clean
   //--- reversal long setup" - the document states no target rule, so the
   //--- session's own far extreme is the measured objective)
   bool BestTarget(const SEAContext &ctx, const MqlRates &r[], const int got,
                   const int dir, const double entry, const double risk, SCfSetup &out)
   {
      out.target = 0.0;
      double need = InpMinRR * risk;
      int    scan = (int)MathMax(2, MathMin(got, InpLevelLookback));
      double hi = -DBL_MAX, lo = DBL_MAX;
      for(int i = 1; i < scan; i++)                                        // r[0] is forming
      { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }
      if(hi <= -DBL_MAX || lo >= DBL_MAX) return false;

      double cand = (dir > 0) ? hi : lo;
      if(dir > 0 && cand < entry + need) cand = entry + need;
      if(dir < 0 && cand > entry - need) cand = entry - need;
      if((dir > 0 && cand <= entry) || (dir < 0 && cand >= entry)) return false;

      out.target = cand;
      return (MathAbs(cand - entry) >= need * 0.999);
   }
};

CCfOrderflowMasterclass g_cfOrderflowMasterclass;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfOrderflowMasterclass);
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
