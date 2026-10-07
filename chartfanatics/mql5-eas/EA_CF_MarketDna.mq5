//+------------------------------------------------------------------+
//|                                        EA_CF_MarketDna.mq5       |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Jay Trade's Market DNA Playbook (PDF, Apr 2025)                    |
//| Card    : chartfanatics/todos/market-dna-strategy.md  (#21)         |
//| Source  : chartfanatics/pdf/market-dna-strategy.pdf                 |
//| Magic   : 3224                                                      |
//|                                                                    |
//| THE MODEL: buyers and sellers move the market - indicators only     |
//| reflect what already happened.  Trade where AGGRESSIVE participants  |
//| overwhelm PASSIVE liquidity at a level that previously produced a    |
//| huge directional move (the DNA point).                               |
//|                                                                    |
//|   (1) DNA points are price ZONES that previously created big moves   |
//|       ("20-30% swings, or areas where momentum exploded") - treated  |
//|       as ranges, never as exact lines;                               |
//|   (2) a valid setup is aggression overwhelming absorption at such a   |
//|       level - the passive wall fails and price is displaced away;     |
//|   (3) the entry is taken as close as possible to where the control    |
//|       flips (the aggression bar's close), never chased;               |
//|   (4) the stop goes just beyond the zone that defines the DNA level,  |
//|       because "risk is reduced ... by minimizing stop distance";      |
//|   (5) the target must clear 3:1 minimum ("most setups naturally        |
//|       provide 4-5:1+"); partials go into the first reaction, the       |
//|       remainder rides until aggression flips;                         |
//|   (6) stops trail behind newly formed aggressive zones;               |
//|   (7) no trades in flat / range-bound sessions where aggression is     |
//|       unclear - the day needs a catalyst (relative volume) and range.  |
//|                                                                    |
//| `[interpretation]`: the playbook reads the tape and Level II depth,    |
//| which no MetaTrader EA can read - the engine has bars and tick         |
//| volume, so "aggression" is the library's order-flow proxy: a           |
//| displacement bar (strong body, closing through the zone) on            |
//| above-average participation, and "absorption failure" is the zone      |
//| being closed through rather than defended.  The catalyst (earnings /   |
//| news) becomes relative volume - the name is "in play" - plus the       |
//| engine's calendar gate when enabled; the DNA move multiple, the zone   |
//| width cap, the body/volume thresholds, the chase cap and the fractal   |
//| trail are numbers the document does not state.  The document's         |
//| instrument rules are honoured by configuration: stocks and futures     |
//| only, and forex is deliberately NOT in the default list.               |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "Market DNA - DNA zones from prior impulsive moves, aggression-over-absorption confirmation, tight stops beyond the zone, 3:1 minimum"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade   = "US100,US500";     // futures (catalysts macro sessions); add your stock symbols
input ulong             InpMagicNumber      = 3224;              // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct          = 0.50;              // Risk per trade (% of equity)
input int               InpStage             = 5;                // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input int               InpServerGmtOffset  = 2;                 // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;     // Log verbosity
input double            InpCommissionPerLotRT = 0.0;             // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.12;            // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;            // Write the engine evidence ledger CSV
//--- DNA points (zones that previously produced big moves)
input ENUM_TIMEFRAMES InpDnaTf        = PERIOD_H1;  // the structure chart the DNA points are read from
input int    InpDnaBars        = 300;    // structure bars scanned
input int    InpBaseBars       = 5;      // the base that precedes the impulsive move
input double InpDnaMoveAtr     = 2.50;   // "areas where momentum exploded" - the move away from the base
input double InpZoneMaxAtr     = 1.00;   // a DNA zone is a narrow base, not a wide range
input int    InpMaxZones       = 8;      // recent zones kept
//--- aggression over absorption
input double InpBodyMin        = 0.60;   // displacement body fraction ("control flips")
input double InpAggVolMult     = 1.40;   // aggression vs the zone's own average bar volume
input double InpMaxChaseAtr    = 0.35;   // the entry must stay this close to the zone ("as close as possible")
input double InpStopBufferAtr  = 0.10;   // buffer beyond the zone (tight risk window)
input double InpMaxStopAtr     = 1.20;   // tightest-risk cap: wider setups are skipped
//--- targets / management
input double InpMinRr          = 3.00;   // "must achieve 3:1 R:R minimum"
input double InpPartial1R      = 1.00;   // partial into the first reaction
input int    InpPartialPct     = 50;
input int    InpTrailBars      = 12;     // fractal lookback for "trail behind newly formed zones"
//--- session / catalyst
input int    InpSessionStartHour = 14;   // US cash session, London clock
input int    InpSessionStartMin  = 30;   // 09:30 ET
input int    InpSessionEndHour   = 21;   // 16:00 ET
input int    InpSessionEndMin    = 0;
input int    InpMaxTradesPerDay  = 2;    // [interpretation]: the doc sets no daily cap
input bool   InpRequireCatalyst  = true; // relative volume: the symbol must be "in play"
input double InpCatalystVolMult  = 1.50; // today's volume vs the 20-day average
input double InpMinDayRangeAtr   = 0.50; // no trades in flat / range-bound sessions
input bool   InpNewsGate         = true; // the engine calendar stands in for the doc's news catalysts

//--- one DNA zone: a base that produced a big directional move
struct SDnaZone
{
   double lo, hi;     // the zone's range (the doc: zones, never exact lines)
   int    side;       // +1 demand (moved up), -1 supply (moved down)
   datetime time;     // when the base formed
};

//+------------------------------------------------------------------+
class CCfMarketDna : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_MARKET_DNA";
      cfg.sourceDoc             = "chartfanatics/pdf/market-dna-strategy.pdf (card #21)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;     // [interpretation]: M5 stands in for the tape
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = 3.0;
      cfg.dailyLossPct          = 1.50;
      cfg.weeklyLossPct         = 3.0;
      cfg.totalDdPct            = 8.0;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 120;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = false;          // the entry follows the aggression confirmation
      cfg.newsFilter            = InpNewsGate;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_market_dna_ledger.csv";
      cfg.logLevel              = InpLogLevel;
      cfg.sessionStartHour = InpSessionStartHour;  cfg.sessionStartMin = InpSessionStartMin;
      cfg.sessionEndHour   = InpSessionEndHour;    cfg.sessionEndMin   = InpSessionEndMin;
      cfg.noTradeAfterHour = InpSessionEndHour;    cfg.noTradeAfterMin = InpSessionEndMin;
      cfg.partial1AtR      = InpPartial1R;  cfg.partial1Pct = InpPartialPct;
      cfg.breakEvenAtR     = 0.0;                 // the stop moves behind new zones, not to an R grid
      cfg.trailAtR         = 0.0;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   void OnInitStrategy()
   {
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "market DNA armed: DNA zones from %s bases with >= %.2f ATR moves, aggression body >= %.2f on >= %.1fx volume, stop within %.2f ATR beyond the zone, target >= %.1fR",
             EnumToString(InpDnaTf), InpDnaMoveAtr, InpBodyMin, InpAggVolMult, InpMaxStopAtr, InpMinRr), true);
      EA_Log(EA_LOG_EVENTS, "the doc's instrument rule is honoured: stocks + futures (and their options); forex is deliberately not traded", true);
   }

   //-------------------------------------------------------------------
   // Aggression overwhelming absorption at a DNA zone
   //-------------------------------------------------------------------
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession || ctx.atr <= 0.0) return false;

      //--- "no trades in flat / range-bound sessions where aggression is unclear"
      if(!SessionHasRange(ctx)) return false;
      //--- "the best setups occur when news or earnings push participants into the market"
      if(InpRequireCatalyst && !CatalystPresent(ctx)) return false;

      SDnaZone zones[];
      int count = DnaZones(ctx.symbol, zones);
      if(count <= 0) return false;

      for(int i = 0; i < count; i++)
      {
         int dir = zones[i].side;
         double stopRef = 0.0, aggression = 0.0;
         if(!AggressionAt(ctx, zones[i], dir, stopRef, aggression)) continue;

         double entry = (dir > 0) ? ctx.ask : ctx.bid;
         //--- "enter as close as possible to where aggression confirms" - never chase the move
         double zoneEdge = (dir > 0) ? zones[i].hi : zones[i].lo;
         double dist = (dir > 0) ? (entry - zoneEdge) : (zoneEdge - entry);
         if(dist < 0.0 || dist > InpMaxChaseAtr * ctx.atr) continue;

         double stop = (dir > 0) ? stopRef - InpStopBufferAtr * ctx.atr
                                 : stopRef + InpStopBufferAtr * ctx.atr;
         double risk = (dir > 0) ? (entry - stop) : (stop - entry);
         if(risk <= 0.0) continue;
         if(risk > InpMaxStopAtr * ctx.atr) continue;          // "minimizing stop distance"

         double target = (dir > 0) ? (entry + InpMinRr * risk) : (entry - InpMinRr * risk);
         plan.dir      = dir;
         plan.entry    = entry;
         plan.stop     = stop;
         plan.target   = target;
         plan.riskDist = risk;
         plan.barsAgo  = 1;
         plan.score    = 78.0;
         plan.isLimit  = false;
         plan.reason   = StringFormat("%s DNA zone %.2f-%.2f: aggression %.2fx volume displaced the level, stop %.2f behind the zone, %.1fR target",
                                      (dir > 0) ? "demand" : "supply", zones[i].lo, zones[i].hi, aggression, stop, InpMinRr);
         return true;
      }
      return false;
   }

   //-------------------------------------------------------------------
   // Exits the doc states: the remainder rides until aggression flips,
   // the stop trails behind newly formed aggressive structure
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

         int    idx   = EA_TrackIndex(ticket);
         int    dir   = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? +1 : -1;
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl    = PositionGetDouble(POSITION_SL);
         if(idx < 0) continue;
         double risk  = g_eaTrack[idx].riskDist;
         if(risk <= 0.0) continue;

         //--- "hold the remainder until aggression flips on the tape": once the trade is working,
         //--- an opposing displacement bar closing back through our own zone is that flip
         double moveR = (dir > 0) ? (ctx.mid - entry) : (entry - ctx.mid);
         if(moveR >= InpPartial1R * risk && AggressionFlipped(ctx, dir))
         {
            EA_Log(EA_LOG_EVENTS, StringFormat("aggression flipped against the remaining position at %.2fR - closing", moveR / risk), true);
            g_eaExec.Close(ticket, "aggression flipped");
            continue;
         }

         //--- "trail stops behind newly formed aggressive zones" (the local fractal structure)
         if(!g_eaTrack[idx].p1Done && InpPartial1R > 0.0) continue;
         double structure = FractalStop(ctx.symbol, dir);
         if(structure <= 0.0) continue;
         double newSl = (dir > 0) ? structure - InpStopBufferAtr * ctx.atr
                                  : structure + InpStopBufferAtr * ctx.atr;
         bool improves = (dir > 0) ? (newSl > sl) : (newSl < sl);
         if(!improves) continue;
         if(dir > 0 && newSl >= ctx.bid) continue;
         if(dir < 0 && newSl <= ctx.ask) continue;
         if(g_eaExec.Modify(ticket, newSl, PositionGetDouble(POSITION_TP)))
            EA_Log(EA_LOG_EVENTS, StringFormat("stop trails behind the new %s to %.2f",
                   (dir > 0) ? "higher low" : "lower high", newSl), true);
      }
   }

private:
   //-------------------------------------------------------------------
   // DNA points: bases that produced big directional moves
   //-------------------------------------------------------------------
   int DnaZones(const string sym, SDnaZone &zones[])
   {
      ArrayResize(zones, 0);
      MqlRates r[];
      int got = EA_Rates(sym, InpDnaTf, 0, InpDnaBars + 4, r);
      if(got < InpBaseBars + 8) return 0;

      double atr = StructureAtr(sym);
      if(atr <= 0.0) return 0;

      int count = 0;
      for(int b = InpBaseBars + 1; b <= got - InpBaseBars - 1 && count < InpMaxZones; b++)
      {
         //--- the base: bars [b .. b + InpBaseBars - 1] (older)
         double bLo = DBL_MAX, bHi = -DBL_MAX;
         for(int i = b; i < b + InpBaseBars; i++)
         { bLo = MathMin(bLo, r[i].low); bHi = MathMax(bHi, r[i].high); }
         if(bHi <= bLo || (bHi - bLo) > InpZoneMaxAtr * atr) continue;

         //--- the displacement: bars [1 .. b - 1] (newer) must have travelled far from the base
         double moveUp = -DBL_MAX, moveDn = -DBL_MAX;
         for(int i = 1; i < b; i++)
         {
            moveUp = MathMax(moveUp, r[i].high - bHi);
            moveDn = MathMax(moveDn, bLo - r[i].low);
         }
         int side = 0;
         if(moveUp >= moveDn && moveUp >= InpDnaMoveAtr * atr) side = +1;
         else if(moveDn > moveUp && moveDn >= InpDnaMoveAtr * atr) side = -1;
         if(side == 0) continue;

         //--- the level must not have been invalidated since (no close through the far side)
         bool consumed = false;
         for(int i = 1; i < b; i++)
         {
            if(side > 0 && r[i].close < bLo) { consumed = true; break; }
            if(side < 0 && r[i].close > bHi) { consumed = true; break; }
         }
         if(consumed) continue;

         ArrayResize(zones, count + 1);
         zones[count].lo = bLo; zones[count].hi = bHi;
         zones[count].side = side; zones[count].time = r[b].time;
         count++;
      }
      return count;
   }

   double StructureAtr(const string sym)
   {
      MqlRates r[];
      int got = EA_Rates(sym, InpDnaTf, 0, 20, r);
      if(got < 6) return 0.0;
      double sum = 0.0;
      int n = 0;
      for(int i = 1; i <= 14 && i < got - 1; i++)
      {
         double tr = MathMax(r[i].high - r[i].low,
                             MathMax(MathAbs(r[i].high - r[i + 1].close),
                                     MathAbs(r[i].low  - r[i + 1].close)));
         sum += tr; n++;
      }
      return (n > 0) ? sum / n : 0.0;
   }

   //-------------------------------------------------------------------
   // Aggression: a displacement bar closing out of the zone on volume
   //-------------------------------------------------------------------
   //--- `[interpretation]`: the tape shows aggressive market orders lifting offers /
   //--- hitting bids; with bars the stand-in is a strong-bodied bar that closes OUT of the
   //--- zone (absorption failed) on above-average participation.
   bool AggressionAt(const SEAContext &ctx, const SDnaZone &zone, const int dir,
                     double &stopRef, double &aggression)
   {
      stopRef = 0.0; aggression = 0.0;
      MqlRates m[];
      if(EA_Rates(ctx.symbol, g_eaIndTf, 0, 24, m) < 22) return false;

      double avg = AvgVolume(m, 2, 21);
      if(avg <= 0.0) return false;

      //--- the newest completed bar is the candidate confirmation
      if(EA_BodyRatio(m[1]) < InpBodyMin) return false;
      double volMult = (double)m[1].tick_volume / avg;
      if(volMult < InpAggVolMult) return false;

      if(dir > 0)
      {
         if(!(m[1].close > m[1].open)) return false;
         if(m[1].low > zone.hi) return false;              // price must have tested the zone
         if(m[1].close <= zone.hi) return false;           // ... and closed OUT of it (absorption failed)
         stopRef = MathMin(zone.lo, m[1].low);
      }
      else
      {
         if(!(m[1].close < m[1].open)) return false;
         if(m[1].high < zone.lo) return false;
         if(m[1].close >= zone.lo) return false;
         stopRef = MathMax(zone.hi, m[1].high);
      }
      aggression = volMult;
      return true;
   }

   //--- the mirror check used on an open runner: the tape flipped against us
   bool AggressionFlipped(const SEAContext &ctx, const int dir)
   {
      MqlRates m[];
      if(EA_Rates(ctx.symbol, g_eaIndTf, 0, 24, m) < 22) return false;
      double avg = AvgVolume(m, 2, 21);
      if(avg <= 0.0) return false;
      if(EA_BodyRatio(m[1]) < InpBodyMin) return false;
      if((double)m[1].tick_volume < InpAggVolMult * avg) return false;
      if(dir > 0) return (m[1].close < m[1].open && m[1].close < m[2].low);
      return (m[1].close > m[1].open && m[1].close > m[2].high);
   }

   //--- the stop trails behind newly formed structure (the doc's "behind aggressive zones")
   double FractalStop(const string sym, const int dir)
   {
      MqlRates r[];
      int got = EA_Rates(sym, g_eaIndTf, 0, InpTrailBars + 3, r);
      if(got < 6) return 0.0;
      for(int k = 2; k <= got - 2; k++)
      {
         bool fractal = (dir > 0) ? (r[k].low < r[k - 1].low && r[k].low < r[k + 1].low)
                                  : (r[k].high > r[k - 1].high && r[k].high > r[k + 1].high);
         if(fractal) return (dir > 0) ? r[k].low : r[k].high;
      }
      return 0.0;
   }

   double AvgVolume(const MqlRates &m[], const int fromBar, const int toBar)
   {
      int got = ArraySize(m);
      if(toBar >= got) return 0.0;
      double sum = 0.0;
      int n = 0;
      for(int i = fromBar; i <= toBar; i++) { sum += (double)m[i].tick_volume; n++; }
      return (n > 0) ? sum / n : 0.0;
   }

   //-------------------------------------------------------------------
   // Market selection: the day must be in play and not flat
   //-------------------------------------------------------------------
   bool CatalystPresent(const SEAContext &ctx)
   {
      MqlRates d[];
      int got = EA_Rates(ctx.symbol, PERIOD_D1, 0, 24, d);
      if(got < 22) return false;
      double sum = 0.0;
      for(int i = 1; i <= 20; i++) sum += (double)d[i].tick_volume;
      double avg = sum / 20.0;
      if(avg <= 0.0) return false;

      //--- the day is "in play" when its volume is running ahead of the 20-day average pace:
      //--- elapsed fraction of the cash session, so early in the session the bar is not trivial
      int openMin = InpSessionStartHour * 60 + InpSessionStartMin;
      int closeMin = InpSessionEndHour * 60 + InpSessionEndMin;
      if(closeMin <= openMin) return true;                     // overnight server day: no pace maths
      double elapsed = (double)(ctx.clockMinutes - openMin) / (double)(closeMin - openMin);
      if(elapsed < 0.05) return true;                          // too early to tell - do not block
      double expected = avg * MathMin(1.0, elapsed);
      return ((double)d[0].tick_volume >= InpCatalystVolMult * expected);
   }

   bool SessionHasRange(const SEAContext &ctx)
   {
      double hi = 0.0, lo = 0.0;
      int    bars = 0;
      int fromMin = InpSessionStartHour * 60 + InpSessionStartMin;
      int toMin   = MathMax(fromMin + 1, MathMin(fromMin + 45, EA_MinutesOfDay(EA_ClockNow())));
      if(!SigRangeForDay(ctx.symbol, g_eaIndTf, fromMin, toMin, 0, hi, lo, bars)) return false;
      if(bars < 5) return false;
      if(ctx.atrH1 <= 0.0) return true;                       // no volatility reference - do not block
      return ((hi - lo) >= InpMinDayRangeAtr * ctx.atrH1);    // a flat open = no aggression to trade
   }
};

CCfMarketDna g_cfMarketDna;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfMarketDna);
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
