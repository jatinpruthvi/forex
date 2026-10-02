//+------------------------------------------------------------------+
//|                                                   EASignals.mqh  |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Reusable, non-repainting signal primitives shared by the         |
//| additionalEAs. Every detector:                                   |
//|   * reads CLOSED bars only (shift >= 1)                          |
//|   * validates every Copy* return value                           |
//|   * fills an SSignalPlan with entry / stop / target / score      |
//|   * never sends an order (EATrade.mqh owns execution)            |
//+------------------------------------------------------------------+
#ifndef EA_SIGNALS_MQH
#define EA_SIGNALS_MQH

//+------------------------------------------------------------------+
//| A complete, executable trade plan                                |
//+------------------------------------------------------------------+
struct SSignalPlan
{
   int      dir;        // +1 buy, -1 sell, 0 none
   double   entry;      // market price (or limit price)
   double   stop;
   double   target;
   double   riskDist;   // |entry - stop|
   double   score;      // 0..100 setup quality (used for collision ranking)
   string   reason;
   int      barsAgo;    // bar that produced the signal (1 = last closed)
   bool     isLimit;    // true when the EA should rest a limit order
   datetime expiry;     // limit expiry (0 = GTC)

   void Reset()
   {
      dir = 0; entry = 0; stop = 0; target = 0; riskDist = 0;
      score = 0; reason = ""; barsAgo = 1; isLimit = false; expiry = 0;
   }
};

//+------------------------------------------------------------------+
//| Indicator handle registry (one set per configured symbol)        |
//+------------------------------------------------------------------+
struct SIndSet
{
   string            sym;
   int               hAtr;      // signal timeframe ATR
   int               hAtrD1;    // daily ATR
   int               hEma20;
   int               hEma50;
   int               hEma200;
   int               hEmaH1_50;
   int               hEmaH1_200;
   int               hEmaD1_200;
   int               hRsi14;
   int               hAdx14;
   int               hAdxD1;   // daily ADX (grid/regime gates)
   bool              valid;
};

SIndSet g_eaInd[EA_MAX_SYMBOLS];
int     g_eaIndCount = 0;
ENUM_TIMEFRAMES g_eaIndTf = PERIOD_M5;

int EA_IndCreate(const string sym, const ENUM_TIMEFRAMES tf)
{
   if(g_eaIndCount >= EA_MAX_SYMBOLS) return -1;
   int i = g_eaIndCount;
   g_eaInd[i].sym        = sym;
   g_eaInd[i].hAtr       = iATR(sym, tf, 14);
   g_eaInd[i].hAtrD1     = iATR(sym, PERIOD_D1, 14);
   g_eaInd[i].hEma20     = iMA(sym, tf, 20,  0, MODE_EMA, PRICE_CLOSE);
   g_eaInd[i].hEma50     = iMA(sym, tf, 50,  0, MODE_EMA, PRICE_CLOSE);
   g_eaInd[i].hEma200    = iMA(sym, tf, 200, 0, MODE_EMA, PRICE_CLOSE);
   g_eaInd[i].hEmaH1_50  = iMA(sym, PERIOD_H1, 50,  0, MODE_EMA, PRICE_CLOSE);
   g_eaInd[i].hEmaH1_200 = iMA(sym, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);
   g_eaInd[i].hEmaD1_200 = iMA(sym, PERIOD_D1, 200, 0, MODE_EMA, PRICE_CLOSE);
   g_eaInd[i].hRsi14     = iRSI(sym, tf, 14, PRICE_CLOSE);
   g_eaInd[i].hAdx14     = iADX(sym, tf, 14);
   g_eaInd[i].hAdxD1     = iADX(sym, PERIOD_D1, 14);
   g_eaInd[i].valid =
      (g_eaInd[i].hAtr       != INVALID_HANDLE &&
       g_eaInd[i].hAtrD1     != INVALID_HANDLE &&
       g_eaInd[i].hEma20     != INVALID_HANDLE &&
       g_eaInd[i].hEma50     != INVALID_HANDLE &&
       g_eaInd[i].hEma200    != INVALID_HANDLE &&
       g_eaInd[i].hEmaH1_50  != INVALID_HANDLE &&
       g_eaInd[i].hEmaH1_200 != INVALID_HANDLE &&
       g_eaInd[i].hEmaD1_200 != INVALID_HANDLE &&
       g_eaInd[i].hRsi14     != INVALID_HANDLE &&
       g_eaInd[i].hAdx14     != INVALID_HANDLE &&
       g_eaInd[i].hAdxD1     != INVALID_HANDLE);
   if(!g_eaInd[i].valid)
   {
      EA_Log(EA_LOG_ERRORS, StringFormat("indicator handles failed for %s (err=%d)", sym, GetLastError()));
      return -1;
   }
   g_eaIndCount++;
   return i;
}

void EA_IndReleaseAll()
{
   for(int i = 0; i < g_eaIndCount; i++)
   {
      if(g_eaInd[i].hAtr       != INVALID_HANDLE) IndicatorRelease(g_eaInd[i].hAtr);
      if(g_eaInd[i].hAtrD1     != INVALID_HANDLE) IndicatorRelease(g_eaInd[i].hAtrD1);
      if(g_eaInd[i].hEma20     != INVALID_HANDLE) IndicatorRelease(g_eaInd[i].hEma20);
      if(g_eaInd[i].hEma50     != INVALID_HANDLE) IndicatorRelease(g_eaInd[i].hEma50);
      if(g_eaInd[i].hEma200    != INVALID_HANDLE) IndicatorRelease(g_eaInd[i].hEma200);
      if(g_eaInd[i].hEmaH1_50  != INVALID_HANDLE) IndicatorRelease(g_eaInd[i].hEmaH1_50);
      if(g_eaInd[i].hEmaH1_200 != INVALID_HANDLE) IndicatorRelease(g_eaInd[i].hEmaH1_200);
      if(g_eaInd[i].hEmaD1_200 != INVALID_HANDLE) IndicatorRelease(g_eaInd[i].hEmaD1_200);
      if(g_eaInd[i].hRsi14     != INVALID_HANDLE) IndicatorRelease(g_eaInd[i].hRsi14);
      if(g_eaInd[i].hAdx14     != INVALID_HANDLE) IndicatorRelease(g_eaInd[i].hAdx14);
      if(g_eaInd[i].hAdxD1     != INVALID_HANDLE) IndicatorRelease(g_eaInd[i].hAdxD1);
   }
   g_eaIndCount = 0;
}

//--- safe single-value buffer read (value at `shift` closed bar)
bool EA_Buf(const int handle, const int buffer, const int shift, double &value)
{
   double tmp[];
   value = 0.0;
   if(handle == INVALID_HANDLE) return false;
   if(CopyBuffer(handle, buffer, shift, 1, tmp) != 1) return false;
   value = tmp[0];
   return (value != EMPTY_VALUE && value != 0.0);
}

//--- safe multi-value buffer read into a series-indexed array
int EA_BufN(const int handle, const int buffer, const int start, const int count, double &out[])
{
   if(handle == INVALID_HANDLE) return 0;
   ArraySetAsSeries(out, true);
   int got = CopyBuffer(handle, buffer, start, count, out);
   if(got <= 0) return 0;
   return got;
}

//--- OHLC fetch, series indexed: r[0] = the bar at `start`, r[k] = k bars older.
//--- CONVENTION: every signal below fetches from bar 0 so that index k == bar k,
//--- i.e. r[0] = the forming bar and r[1] = the most recent CLOSED bar.
//--- (Earlier revisions fetched from start=1 and then indexed r[1], which
//--- silently evaluated every pattern one bar late.)
int EA_Rates(const string sym, const ENUM_TIMEFRAMES tf, const int start, const int count, MqlRates &r[])
{
   ArraySetAsSeries(r, true);
   int got = CopyRates(sym, tf, start, count, r);
   if(got <= 0) return 0;
   return got;
}

//+------------------------------------------------------------------+
//| Clock helpers for bars                                           |
//+------------------------------------------------------------------+
datetime EA_BarClockTime(const datetime serverBarTime)
{
   return EA_UtcToLondon(EA_ServerToUtc(serverBarTime));
}

//--- minutes of the current clock day
int EA_ClockMinutes(const datetime clockTime)
{
   return EA_MinutesOfDay(clockTime);
}

//+------------------------------------------------------------------+
//| Session / range builders                                         |
//+------------------------------------------------------------------+

//--- build high/low of a wall-clock window on the clock day that
//--- `dayOffset` days back from today (0 = today, 1 = yesterday ...)
bool SigRangeForDay(const string sym, const ENUM_TIMEFRAMES tf,
                    const int fromMin, const int toMin,
                    const int dayOffset,
                    double &hi, double &lo, int &barsUsed)
{
   hi = 0.0; lo = 0.0; barsUsed = 0;
   datetime today = EA_ClockNow();
   datetime targetDay = today - (datetime)(dayOffset * 86400);
   MqlDateTime dt;
   TimeToStruct(targetDay, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime dayStart = StructToTime(dt);

   MqlRates r[];
   int want = 400;                       // enough M5 bars for any window
   int got  = EA_Rates(sym, tf, 1, want, r);
   if(got < 10) return false;

   double h = -DBL_MAX, l = DBL_MAX;
   for(int i = 0; i < got; i++)
   {
      datetime bt  = r[i].time;
      datetime clk = EA_BarClockTime(bt);
      if(clk < dayStart || clk >= dayStart + 86400) continue;
      int m = EA_MinutesOfDay(clk);
      bool inside;
      if(fromMin <= toMin) inside = (m >= fromMin && m < toMin);
      else                 inside = (m >= fromMin || m < toMin);
      if(!inside) continue;
      if(r[i].high > h) h = r[i].high;
      if(r[i].low  < l) l = r[i].low;
      barsUsed++;
   }
   if(barsUsed < 3 || h <= -DBL_MAX || l >= DBL_MAX) return false;
   hi = h; lo = l;
   return true;
}

//--- most recent COMPLETED window (yesterday if today's window is still open)
bool SigPrevSessionRange(const string sym, const ENUM_TIMEFRAMES tf,
                         const int fromMin, const int toMin,
                         double &hi, double &lo)
{
   int nowMin = EA_MinutesOfDay(EA_ClockNow());
   int offset = (nowMin >= toMin) ? 0 : 1;      // today's window already closed?
   if(SigRangeForDay(sym, tf, fromMin, toMin, offset, hi, lo))
      return true;
   return SigRangeForDay(sym, tf, fromMin, toMin, offset + 1, hi, lo);
}

//--- Asia range (London 00:00-07:00) convenience wrapper
bool SigAsianRange(const string sym, double &hi, double &lo)
{
   return SigPrevSessionRange(sym, PERIOD_M5, 0, 7 * 60, hi, lo);
}

//--- daily (D1) Donchian channel of the last `days` completed days
bool SigDonchian(const string sym, const int days, double &hi, double &lo)
{
   hi = 0.0; lo = 0.0;
   MqlRates r[];
   int got = EA_Rates(sym, PERIOD_D1, 1, days + 2, r);
   if(got < days) return false;
   double h = -DBL_MAX, l = DBL_MAX;
   for(int i = 0; i < days; i++)
   {
      if(r[i].high > h) h = r[i].high;
      if(r[i].low  < l) l = r[i].low;
   }
   hi = h; lo = l;
   return true;
}

//+------------------------------------------------------------------+
//| Body / wick helpers                                              |
//+------------------------------------------------------------------+
double EA_BodyRatio(const MqlRates &r)
{
   double range = r.high - r.low;
   if(range <= 0.0) return 0.0;
   return MathAbs(r.close - r.open) / range;
}

//--- wick ratio in `dir` (+1 = lower wick for a bullish rejection)
double EA_WickRatio(const MqlRates &r, const int dir)
{
   double range = r.high - r.low;
   if(range <= 0.0) return 0.0;
   double bodyLow  = MathMin(r.open, r.close);
   double bodyHigh = MathMax(r.open, r.close);
   if(dir > 0) return (bodyLow - r.low) / range;
   return (r.high - bodyHigh) / range;
}

bool EA_BullishEngulf(const MqlRates &prev, const MqlRates &cur)
{
   return (cur.close > cur.open && prev.close < prev.open &&
           cur.close >= prev.open && cur.open <= prev.close);
}

bool EA_BearishEngulf(const MqlRates &prev, const MqlRates &cur)
{
   return (cur.close < cur.open && prev.close > prev.open &&
           cur.close <= prev.open && cur.open >= prev.close);
}

//+------------------------------------------------------------------+
//| 1. SESSION-OPEN SWEEP / RECLAIM / DISPLACEMENT (SOS core)        |
//+------------------------------------------------------------------+
struct SSweepParams
{
   int      rangeFromMin;      // clock minutes, e.g. 0  (00:00)
   int      rangeToMin;        // e.g. 420 (07:00)
   int      sessionFromMin;    // entry window start (e.g. 420)
   int      sessionToMin;      // entry window end   (e.g. 660)
   double   sweepMinAtr;       // min sweep depth in ATR
   double   sweepMaxAtr;       // max sweep depth in ATR (0 = unlimited)
   int      reclaimWindowBars; // max bars from sweep to reclaim
   double   wickRatio;         // sweep-bar rejection wick >= x of range
   double   bodyRatio;         // displacement body >= x of range
   double   stopBufferAtr;     // stop beyond sweep extreme
   double   minStopAtr;        // reject if stop > this ATR
   double   maxStopAtr;        // reject if stop < this ATR
   double   targetR;           // take-profit in R
   double   entryRetrace;      // 0 = market at close, 0.5 = limit at 50% body
   bool     requireDisplacement;
   bool     tradeBothWays;
   double   scoreBase;

   void Reset()
   {
      rangeFromMin = 0; rangeToMin = 420;
      sessionFromMin = 420; sessionToMin = 660;
      sweepMinAtr = 0.02; sweepMaxAtr = 1.0;
      reclaimWindowBars = 3; wickRatio = 0.60; bodyRatio = 0.60;
      stopBufferAtr = 0.10; minStopAtr = 0.20; maxStopAtr = 2.5;
      targetR = 1.5; entryRetrace = 0.0; requireDisplacement = true;
      tradeBothWays = true; scoreBase = 60.0;
   }
};

//--- returns true when a sweep/reclaim/displacement sequence completed on closed bars
//--- bar order (series index): r[1]=displacement, r[2]=reclaim, r[3+]=sweep candidate
bool SigSweepReclaim(const SEAContext &ctx, const SSweepParams &p, SSignalPlan &out)
{
   out.Reset();
   if(ctx.atr <= 0.0) return false;
   int nowMin = ctx.clockMinutes;
   bool inWindow = (p.sessionFromMin <= p.sessionToMin)
                   ? (nowMin >= p.sessionFromMin && nowMin < p.sessionToMin)
                   : (nowMin >= p.sessionFromMin || nowMin < p.sessionToMin);
   if(!inWindow) return false;

   double rHi = 0.0, rLo = 0.0;
   int    rangeBars = 0;
   if(!SigRangeForDay(ctx.symbol, g_eaIndTf, p.rangeFromMin, p.rangeToMin, 0, rHi, rLo, rangeBars))
   {
      if(!SigPrevSessionRange(ctx.symbol, g_eaIndTf, p.rangeFromMin, p.rangeToMin, rHi, rLo))
         return false;
   }
   if(rHi <= rLo) return false;

   int need = 2 + p.reclaimWindowBars + 2;
   MqlRates r[];
   int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, need, r);
   if(got < 4) return false;

   double sweepMax = (p.sweepMaxAtr > 0.0) ? p.sweepMaxAtr * ctx.atr : DBL_MAX;

   int maxDisp = (int)MathMin(3, got - 3);
   for(int d = 1; d <= maxDisp; d++)
   {
      MqlRates disp = r[d];
      MqlRates recl = r[d + 1];
      bool dispUp = (disp.close > disp.open);
      bool dispDn = (disp.close < disp.open);
      if(p.requireDisplacement && EA_BodyRatio(disp) < p.bodyRatio) continue;

      for(int k = 0; k < p.reclaimWindowBars; k++)
      {
         int si = d + 2 + k;
         if(si >= got) continue;
         MqlRates sw = r[si];

         //--- bullish sequence: sweep of the range low, reclaim, bullish displacement
         bool sweptLow = (sw.low < rLo - p.sweepMinAtr * ctx.atr) && ((rLo - sw.low) <= sweepMax);
         if(sweptLow && EA_WickRatio(sw, +1) >= p.wickRatio && recl.close > rLo && (!p.requireDisplacement || dispUp))
         {
            double stop = sw.low - p.stopBufferAtr * ctx.atr;
            double entry;
            if(p.entryRetrace > 0.0)
            {
               double bodyLow  = MathMin(disp.open, disp.close);
               double bodyHigh = MathMax(disp.open, disp.close);
               entry = bodyHigh - (bodyHigh - bodyLow) * p.entryRetrace;
            }
            else
               entry = (ctx.ask > 0.0 ? ctx.ask : recl.close);
            if(entry <= stop) continue;
            double risk = entry - stop;
            if(risk < p.minStopAtr * ctx.atr) continue;
            if(risk > p.maxStopAtr * ctx.atr) continue;
            if(p.entryRetrace > 0.0 && ctx.ask > 0.0 && entry >= ctx.ask) continue; // limit would be invalid
            out.dir      = +1;
            out.entry    = entry;
            out.stop     = stop;
            out.riskDist = risk;
            out.target   = entry + p.targetR * risk;
            out.score    = p.scoreBase + MathMin(30.0, (rLo - sw.low) / ctx.atr * 20.0);
            out.reason   = StringFormat("SOS sweep-low reclaim (sweep %.2f ATR, reclaim bar %d)", (rLo - sw.low) / ctx.atr, d + 1);
            out.barsAgo  = d;
            out.isLimit  = (p.entryRetrace > 0.0);
            if(out.isLimit) out.expiry = TimeTradeServer() + (datetime)(g_eaCfg.pendingExpiryMinutes * 60);
            return true;
         }

         if(!p.tradeBothWays) continue;
         //--- bearish sequence: sweep of the range high, reclaim, bearish displacement
         bool sweptHigh = (sw.high > rHi + p.sweepMinAtr * ctx.atr) && ((sw.high - rHi) <= sweepMax);
         if(sweptHigh && EA_WickRatio(sw, -1) >= p.wickRatio && recl.close < rHi && (!p.requireDisplacement || dispDn))
         {
            double stop = sw.high + p.stopBufferAtr * ctx.atr;
            double entry;
            if(p.entryRetrace > 0.0)
            {
               double bodyLow  = MathMin(disp.open, disp.close);
               double bodyHigh = MathMax(disp.open, disp.close);
               entry = bodyLow + (bodyHigh - bodyLow) * p.entryRetrace;
            }
            else
               entry = (ctx.bid > 0.0 ? ctx.bid : recl.close);
            if(entry >= stop) continue;
            double risk = stop - entry;
            if(risk < p.minStopAtr * ctx.atr) continue;
            if(risk > p.maxStopAtr * ctx.atr) continue;
            if(p.entryRetrace > 0.0 && ctx.bid > 0.0 && entry <= ctx.bid) continue;
            out.dir      = -1;
            out.entry    = entry;
            out.stop     = stop;
            out.riskDist = risk;
            out.target   = entry - p.targetR * risk;
            out.score    = p.scoreBase + 5.0;
            out.reason   = StringFormat("SOS sweep-high reclaim (sweep %.2f ATR, reclaim bar %d)", (sw.high - rHi) / ctx.atr, d + 1);
            out.barsAgo  = d;
            out.isLimit  = (p.entryRetrace > 0.0);
            if(out.isLimit) out.expiry = TimeTradeServer() + (datetime)(g_eaCfg.pendingExpiryMinutes * 60);
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| 2. OPENING-RANGE BREAKOUT (ORB)                                  |
//+------------------------------------------------------------------+
struct SOrbParams
{
   int      rangeFromMin;      // opening range start (clock minutes)
   int      rangeToMin;        // opening range end
   int      entryFromMin;      // earliest entry
   int      entryToMin;        // latest entry
   double   minRangeAtr;       // range must be >= x ATR
   double   maxRangeAtr;       // range must be <= x ATR
   double   bufferAtr;         // breakout buffer beyond range edge
   double   bodyRatio;         // breakout candle body ratio
   double   stopBufferAtr;     // stop beyond opposite range edge
   double   targetR;
   bool     requireRetest;     // wait for retest of the broken edge
   double   retestTolAtr;
   bool     tradeBothWays;
   double   scoreBase;

   void Reset()
   {
      rangeFromMin = 0; rangeToMin = 30;
      entryFromMin = 30; entryToMin = 240;
      minRangeAtr = 0.10; maxRangeAtr = 3.0;
      bufferAtr = 0.02; bodyRatio = 0.60;
      stopBufferAtr = 0.10; targetR = 2.0;
      requireRetest = false; retestTolAtr = 0.05;
      tradeBothWays = true; scoreBase = 55.0;
   }
};

bool SigORB(const SEAContext &ctx, const SOrbParams &p, SSignalPlan &out)
{
   out.Reset();
   if(ctx.atr <= 0.0) return false;
   int nowMin = ctx.clockMinutes;
   if(nowMin < p.entryFromMin || nowMin >= p.entryToMin) return false;

   double rHi = 0.0, rLo = 0.0;
   int bars = 0;
   if(!SigRangeForDay(ctx.symbol, g_eaIndTf, p.rangeFromMin, p.rangeToMin, 0, rHi, rLo, bars)) return false;
   if(rHi <= rLo) return false;
   double rangeSize = rHi - rLo;
   if(rangeSize < p.minRangeAtr * ctx.atr) return false;
   if(p.maxRangeAtr > 0.0 && rangeSize > p.maxRangeAtr * ctx.atr) return false;

   MqlRates r[];
   int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, 6, r);
   if(got < 3) return false;

   for(int i = 1; i <= (int)MathMin(got - 1, 3); i++)
   {
      MqlRates b = r[i];
      //--- bullish break
      if(b.close > rHi + p.bufferAtr * ctx.atr && EA_BodyRatio(b) >= p.bodyRatio)
      {
         if(p.requireRetest)
         {
            bool retested = false;
            for(int k = 1; k < i; k++)
               if(r[k].low <= rHi + p.retestTolAtr * ctx.atr && r[k].close > rHi) retested = true;
            if(!retested) continue;
         }
         double entry = ctx.ask > 0 ? ctx.ask : b.close;
         double stop  = rLo - p.stopBufferAtr * ctx.atr;
         double risk  = entry - stop;
         if(risk <= 0.0) continue;
         out.dir = +1; out.entry = entry; out.stop = stop;
         out.target = entry + p.targetR * risk; out.riskDist = risk;
         out.score = p.scoreBase + MathMin(25.0, (b.close - rHi) / ctx.atr * 25.0);
         out.reason = "ORB bullish break of opening range";
         out.barsAgo = i;
         return true;
      }
      if(!p.tradeBothWays) continue;
      //--- bearish break
      if(b.close < rLo - p.bufferAtr * ctx.atr && EA_BodyRatio(b) >= p.bodyRatio)
      {
         if(p.requireRetest)
         {
            bool retested = false;
            for(int k = 1; k < i; k++)
               if(r[k].high >= rLo - p.retestTolAtr * ctx.atr && r[k].close < rLo) retested = true;
            if(!retested) continue;
         }
         double entry = (ctx.bid > 0 ? ctx.bid : b.close);
         double stop  = rHi + p.stopBufferAtr * ctx.atr;
         double risk  = stop - entry;
         if(risk <= 0.0) continue;
         out.dir = -1; out.entry = entry; out.stop = stop;
         out.target = entry - p.targetR * risk; out.riskDist = risk;
         out.score = p.scoreBase + 5.0;
         out.reason = "ORB bearish break of opening range";
         out.barsAgo = i;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| 3. DONCHIAN BREAKOUT (daily swing)                               |
//+------------------------------------------------------------------+
struct SDonchianParams
{
   int      lookbackDays;   // channel length in completed D1 bars
   double   bufferAtr;      // breakout buffer (daily ATR units)
   double   stopD1Atr;      // stop = x daily ATR back from entry
   double   targetR;
   double   trailD1Atr;     // chandelier trail (0 = off)
   bool     tradeBothWays;
   bool     longOnly;
   int      maxHoldDays;    // 0 = off

   void Reset()
   {
      lookbackDays = 20; bufferAtr = 0.05; stopD1Atr = 1.5;
      targetR = 3.0; trailD1Atr = 2.5;
      tradeBothWays = true; longOnly = false; maxHoldDays = 0;
   }
};

bool SigDonchian(const SEAContext &ctx, const SDonchianParams &p, SSignalPlan &out)
{
   out.Reset();
   double atrD1 = ctx.atrD1;
   if(atrD1 <= 0.0) return false;
   double hi = 0.0, lo = 0.0;
   if(!SigDonchian(ctx.symbol, p.lookbackDays, hi, lo)) return false;
   if(hi <= lo) return false;

   double buffer = p.bufferAtr * atrD1;
   double px     = ctx.mid;
   int    dir    = 0;
   if(px > hi + buffer)                        dir = +1;
   else if(!p.longOnly && px < lo - buffer)    dir = -1;
   if(dir == 0) return false;

   double entry = (dir > 0) ? ctx.ask : ctx.bid;
   double stop  = (dir > 0) ? entry - p.stopD1Atr * atrD1 : entry + p.stopD1Atr * atrD1;
   double risk  = MathAbs(entry - stop);
   if(risk <= 0.0) return false;
   out.dir = dir; out.entry = entry; out.stop = stop;
   out.target = (dir > 0) ? entry + p.targetR * risk : entry - p.targetR * risk;
   out.riskDist = risk;
   out.score = 70.0;
   out.reason = StringFormat("Donchian(%d) %s break", p.lookbackDays, dir > 0 ? "upside" : "downside");
   out.barsAgo = 0;
   return true;
}

//+------------------------------------------------------------------+
//| 4. TREND PULLBACK TO EMA (with rejection candle)                 |
//+------------------------------------------------------------------+
struct SEmaPullbackParams
{
   bool     requireH1Bias;     // H1 200 EMA must agree
   bool     requireD1Bias;     // D1 200 EMA must agree
   double   touchTolAtr;       // how close price must come to the EMA
   double   wickRatio;         // rejection wick
   double   stopBufferAtr;     // beyond the rejection wick
   double   targetR;
   int      maxBarsSinceTouch;
   bool     tradeBothWays;
   double   scoreBase;

   void Reset()
   {
      requireH1Bias = false; requireD1Bias = false;
      touchTolAtr = 0.25; wickRatio = 0.40; stopBufferAtr = 0.15;
      targetR = 2.0; maxBarsSinceTouch = 3; tradeBothWays = true; scoreBase = 58.0;
   }
};

bool SigEmaPullback(const SEAContext &ctx, const SEmaPullbackParams &p, SSignalPlan &out)
{
   out.Reset();
   if(ctx.atr <= 0.0 || ctx.ema20 <= 0.0) return false;
   if(p.requireD1Bias)
   {
      if(ctx.emaD1_200 <= 0.0) return false;
      if(ctx.mid > ctx.emaD1_200 && ctx.mid < ctx.ema20) return false;
      if(ctx.mid < ctx.emaD1_200 && ctx.mid > ctx.ema20) return false;
   }
   if(p.requireH1Bias)
   {
      if(ctx.emaH1_200 <= 0.0) return false;
      if(ctx.mid > ctx.emaH1_200 && ctx.mid < ctx.ema20) return false;
      if(ctx.mid < ctx.emaH1_200 && ctx.mid > ctx.ema20) return false;
   }

   MqlRates r[];
   int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, p.maxBarsSinceTouch + 2, r);
   if(got < 2) return false;

   for(int i = 1; i <= (int)MathMin(got - 1, p.maxBarsSinceTouch); i++)
   {
      MqlRates b = r[i];
      double tol = p.touchTolAtr * ctx.atr;
      //--- bullish pullback: bar dips into the EMA and closes above it
      if(b.low <= ctx.ema20 + tol && b.close > ctx.ema20 && ctx.ema20 > ctx.ema50)
      {
         if(EA_WickRatio(b, +1) < p.wickRatio) continue;
         double entry = ctx.ask;
         double stop  = MathMin(b.low, ctx.ema20) - p.stopBufferAtr * ctx.atr;
         double risk  = entry - stop;
         if(risk <= 0.0) continue;
         out.dir = +1; out.entry = entry; out.stop = stop;
         out.target = entry + p.targetR * risk; out.riskDist = risk;
         out.score = p.scoreBase; out.reason = "EMA20 pullback rejection (long)"; out.barsAgo = i;
         return true;
      }
      //--- bearish pullback
      if(!p.tradeBothWays) continue;
      if(b.high >= ctx.ema20 - tol && b.close < ctx.ema20 && ctx.ema20 < ctx.ema50)
      {
         if(EA_WickRatio(b, -1) < p.wickRatio) continue;
         double entry = ctx.bid;
         double stop  = MathMax(b.high, ctx.ema20) + p.stopBufferAtr * ctx.atr;
         double risk  = stop - entry;
         if(risk <= 0.0) continue;
         out.dir = -1; out.entry = entry; out.stop = stop;
         out.target = entry - p.targetR * risk; out.riskDist = risk;
         out.score = p.scoreBase; out.reason = "EMA20 pullback rejection (short)"; out.barsAgo = i;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| 5. RANGE FADE (Bollinger / RSI mean reversion)                   |
//+------------------------------------------------------------------+
struct SRangeFadeParams
{
   int      bbPeriod;
   double   bbDeviation;
   double   rsiOversold;
   double   rsiOverbought;
   double   wickRatio;
   double   stopBufferAtr;
   double   targetR;          // often the mid-band -> expressed in R
   bool     tradeBothWays;
   bool     requireRangeRegime;   // ADX below threshold
   double   maxAdx;
   double   scoreBase;

   void Reset()
   {
      bbPeriod = 20; bbDeviation = 2.0;
      rsiOversold = 30.0; rsiOverbought = 70.0;
      wickRatio = 0.35; stopBufferAtr = 0.30; targetR = 1.0;
      tradeBothWays = true; requireRangeRegime = true; maxAdx = 22.0;
      scoreBase = 52.0;
   }
};

bool SigRangeFade(const SEAContext &ctx, const SRangeFadeParams &p, SSignalPlan &out)
{
   out.Reset();
   if(ctx.atr <= 0.0 || ctx.rsi14 <= 0.0) return false;
   if(p.requireRangeRegime && ctx.adx14 > 0.0 && ctx.adx14 > p.maxAdx) return false;

   MqlRates r[];
   int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, p.bbPeriod + 3, r);
   if(got < p.bbPeriod + 1) return false;

   //--- Bollinger computed in-line from closed bars (no indicator handle churn)
   double sum = 0.0, sum2 = 0.0;
   for(int i = 1; i <= p.bbPeriod; i++) { sum += r[i].close; sum2 += r[i].close * r[i].close; }
   double sma  = sum / p.bbPeriod;
   double var  = MathMax(0.0, sum2 / p.bbPeriod - sma * sma);
   double sd   = MathSqrt(var);
   if(sd <= 0.0) return false;
   double up = sma + p.bbDeviation * sd;
   double lo = sma - p.bbDeviation * sd;

   MqlRates b = r[1];
   //--- long fade at the lower band
   if(b.low <= lo && b.close > lo && ctx.rsi14 <= p.rsiOversold + 5.0)
   {
      if(EA_WickRatio(b, +1) < p.wickRatio) return false;
      double entry = (ctx.ask > 0.0 ? ctx.ask : b.close);
      double stop  = b.low - p.stopBufferAtr * ctx.atr;
      double risk  = entry - stop;
      if(risk <= 0.0) return false;
      out.dir = +1; out.entry = entry; out.stop = stop;
      out.target = entry + p.targetR * risk; out.riskDist = risk;
      out.score = p.scoreBase; out.reason = "Bollinger lower-band fade"; out.barsAgo = 1;
      return true;
   }
   if(!p.tradeBothWays) return false;
   //--- short fade at the upper band
   if(b.high >= up && b.close < up && ctx.rsi14 >= p.rsiOverbought - 5.0)
   {
      if(EA_WickRatio(b, -1) < p.wickRatio) return false;
      double entry = (ctx.bid > 0.0 ? ctx.bid : b.close);
      double stop  = b.high + p.stopBufferAtr * ctx.atr;
      double risk  = stop - entry;
      if(risk <= 0.0) return false;
      out.dir = -1; out.entry = entry; out.stop = stop;
      out.target = entry - p.targetR * risk; out.riskDist = risk;
      out.score = p.scoreBase; out.reason = "Bollinger upper-band fade"; out.barsAgo = 1;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| 6. MULTI-TIMEFRAME EMA CASCADE                                   |
//+------------------------------------------------------------------+
struct SCascadeParams
{
   bool     requireD1;
   bool     requireH1;
   bool     requireM15Structure;   // signal TF EMA50 agreement
   double   scoreBase;

   void Reset()
   {
      requireD1 = true; requireH1 = true; requireM15Structure = true; scoreBase = 60.0;
   }
};

//--- returns +1 bullish cascade, -1 bearish, 0 mixed
int SigEmaCascade(const SEAContext &ctx, const SCascadeParams &p)
{
   int scoreUp = 0, scoreDn = 0, used = 0;
   if(p.requireD1)
   {
      if(ctx.emaD1_200 <= 0.0) return 0;
      used++;
      if(ctx.mid > ctx.emaD1_200) scoreUp++; else scoreDn++;
   }
   if(p.requireH1)
   {
      if(ctx.emaH1_200 <= 0.0) return 0;
      used++;
      if(ctx.mid > ctx.emaH1_200) scoreUp++; else scoreDn++;
      if(ctx.emaH1_50 > 0.0 && ctx.emaH1_200 > 0.0)
      {
         if(ctx.emaH1_50 > ctx.emaH1_200) scoreUp++; else scoreDn++;
         used++;
      }
   }
   if(p.requireM15Structure)
   {
      if(ctx.ema50 <= 0.0) return 0;
      used++;
      if(ctx.mid > ctx.ema50) scoreUp++; else scoreDn++;
   }
   if(used == 0) return 0;
   if(scoreUp == used) return +1;
   if(scoreDn == used) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| 7. BREAK-RETEST CONTINUATION (accepted breakout)                 |
//+------------------------------------------------------------------+
struct SBreakRetestParams
{
   int      rangeFromMin;
   int      rangeToMin;
   int      entryFromMin;
   int      entryToMin;
   double   minRangeAtr;
   double   breakBufferAtr;
   double   retestTolAtr;
   double   stopBufferAtr;
   double   targetR;
   bool     tradeBothWays;
   double   scoreBase;

   void Reset()
   {
      rangeFromMin = 0; rangeToMin = 420;
      entryFromMin = 420; entryToMin = 900;
      minRangeAtr = 0.30; breakBufferAtr = 0.10; retestTolAtr = 0.15;
      stopBufferAtr = 0.20; targetR = 2.0; tradeBothWays = true; scoreBase = 62.0;
   }
};

bool SigBreakRetest(const SEAContext &ctx, const SBreakRetestParams &p, SSignalPlan &out)
{
   out.Reset();
   if(ctx.atr <= 0.0) return false;
   if(ctx.clockMinutes < p.entryFromMin || ctx.clockMinutes >= p.entryToMin) return false;

   double rHi = 0.0, rLo = 0.0;
   int bars = 0;
   if(!SigRangeForDay(ctx.symbol, g_eaIndTf, p.rangeFromMin, p.rangeToMin, 0, rHi, rLo, bars)) return false;
   if(rHi <= rLo || (rHi - rLo) < p.minRangeAtr * ctx.atr) return false;

   MqlRates r[];
   int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, 8, r);
   if(got < 4) return false;

   //--- find an accepted break (close beyond range) then a retest holding the level
   for(int i = 1; i <= (int)MathMin(got - 2, 4); i++)
   {
      MqlRates b = r[i];
      if(b.close > rHi + p.breakBufferAtr * ctx.atr)
      {
         if(b.low > rHi + p.retestTolAtr * ctx.atr) continue;      // no retest yet
         if(b.close < rHi) continue;                               // retest failed
         double entry = ctx.ask;
         double stop  = rLo - p.stopBufferAtr * ctx.atr;
         double risk  = entry - stop;
         if(risk <= 0.0) continue;
         out.dir = +1; out.entry = entry; out.stop = stop;
         out.target = entry + p.targetR * risk; out.riskDist = risk;
         out.score = p.scoreBase; out.reason = "Break-retest long of session range"; out.barsAgo = i;
         return true;
      }
      if(!p.tradeBothWays) continue;
      if(b.close < rLo - p.breakBufferAtr * ctx.atr)
      {
         if(b.high < rLo - p.retestTolAtr * ctx.atr) continue;
         if(b.close > rLo) continue;
         double entry = ctx.bid;
         double stop  = rHi + p.stopBufferAtr * ctx.atr;
         double risk  = stop - entry;
         if(risk <= 0.0) continue;
         out.dir = -1; out.entry = entry; out.stop = stop;
         out.target = entry - p.targetR * risk; out.riskDist = risk;
         out.score = p.scoreBase; out.reason = "Break-retest short of session range"; out.barsAgo = i;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| 8. VWAP REVERSION (NY afternoon fade)                            |
//+------------------------------------------------------------------+
bool SigVwapFade(const SEAContext &ctx, const double deviationBand, SSignalPlan &out)
{
   out.Reset();
   if(ctx.atr <= 0.0) return false;

   MqlRates r[];
   int got = EA_Rates(ctx.symbol, g_eaIndTf, 1, 120, r);
   if(got < 20) return false;

   //--- session VWAP from the current clock day
   MqlDateTime dt;
   TimeToStruct(ctx.nowClock, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime dayStart = StructToTime(dt);

   double sumPV = 0.0, sumV = 0.0, sumP2V = 0.0;
   int used = 0;
   for(int i = 0; i < got; i++)
   {
      if(r[i].time < EA_ClockToServer(dayStart)) break;
      double tp = (r[i].high + r[i].low + r[i].close) / 3.0;
      double v  = (double)r[i].tick_volume;
      if(v <= 0.0) v = 1.0;
      sumPV  += tp * v;
      sumP2V += tp * tp * v;
      sumV   += v;
      used++;
   }
   if(used < 10 || sumV <= 0.0) return false;
   double vwap = sumPV / sumV;
   double var  = MathMax(0.0, sumP2V / sumV - vwap * vwap);
   double sd   = MathSqrt(var);
   if(sd <= 0.0) return false;
   double upper = vwap + deviationBand * sd;
   double lower = vwap - deviationBand * sd;

   double px = ctx.mid;
   if(px >= upper)
   {
      double entry = ctx.bid;
      double stop  = upper + 0.5 * ctx.atr;
      double risk  = stop - entry;
      if(risk <= 0.0) return false;
      out.dir = -1; out.entry = entry; out.stop = stop;
      out.target = MathMax(vwap, entry - 1.5 * risk); out.riskDist = risk;
      out.score = 50.0; out.reason = "VWAP upper-band fade";
      return true;
   }
   if(px <= lower)
   {
      double entry = ctx.ask;
      double stop  = lower - 0.5 * ctx.atr;
      double risk  = entry - stop;
      if(risk <= 0.0) return false;
      out.dir = +1; out.entry = entry; out.stop = stop;
      out.target = MathMin(vwap, entry + 1.5 * risk); out.riskDist = risk;
      out.score = 50.0; out.reason = "VWAP lower-band fade";
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| 9. MOMENTUM BURST (wide body + ATR expansion)                    |
//+------------------------------------------------------------------+
struct SMomentumParams
{
   double   bodyRatio;      // e.g. 0.60
   double   minRangeAtr;    // candle range >= x ATR
   double   stopBufferAtr;
   double   targetR;
   bool     requireTrend;   // signal-TF EMA50 agreement
   bool     tradeBothWays;

   void Reset()
   {
      bodyRatio = 0.60; minRangeAtr = 0.80; stopBufferAtr = 0.20;
      targetR = 2.0; requireTrend = true; tradeBothWays = true;
   }
};

bool SigMomentumBurst(const SEAContext &ctx, const SMomentumParams &p, SSignalPlan &out)
{
   out.Reset();
   if(ctx.atr <= 0.0) return false;
   MqlRates r[];
   int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, 3, r);
   if(got < 2) return false;
   MqlRates b = r[1];
   double range = b.high - b.low;
   if(range < p.minRangeAtr * ctx.atr) return false;
   if(EA_BodyRatio(b) < p.bodyRatio) return false;
   bool bull = (b.close > b.open);
   if(p.requireTrend && ctx.ema50 > 0.0)
   {
      if(bull && ctx.mid < ctx.ema50) return false;
      if(!bull && ctx.mid > ctx.ema50) return false;
   }
   if(bull)
   {
      double entry = ctx.ask;
      double stop  = b.low - p.stopBufferAtr * ctx.atr;
      double risk  = entry - stop;
      if(risk <= 0.0) return false;
      out.dir = +1; out.entry = entry; out.stop = stop;
      out.target = entry + p.targetR * risk; out.riskDist = risk;
      out.score = 56.0; out.reason = "Momentum burst long"; return true;
   }
   if(!p.tradeBothWays) return false;
   double entry = ctx.bid;
   double stop  = b.high + p.stopBufferAtr * ctx.atr;
   double risk  = stop - entry;
   if(risk <= 0.0) return false;
   out.dir = -1; out.entry = entry; out.stop = stop;
   out.target = entry - p.targetR * risk; out.riskDist = risk;
   out.score = 56.0; out.reason = "Momentum burst short"; return true;
}

//+------------------------------------------------------------------+
//| 10. ASIAN-RANGE BREAKOUT (single, non-retest variant)            |
//+------------------------------------------------------------------+
bool SigAsianBreakout(const SEAContext &ctx, const double bufferAtr,
                      const double stopBufferAtr, const double targetR, SSignalPlan &out)
{
   out.Reset();
   if(ctx.atr <= 0.0) return false;
   double hi = 0.0, lo = 0.0;
   if(!SigPrevSessionRange(ctx.symbol, g_eaIndTf, 0, 7 * 60, hi, lo)) return false;
   if(hi <= lo) return false;
   MqlRates r[];
   int got = EA_Rates(ctx.symbol, g_eaIndTf, 1, 3, r);
   if(got < 1) return false;
   double px = r[0].close;
   if(px > hi + bufferAtr * ctx.atr)
   {
      double entry = ctx.ask;
      double stop  = lo - stopBufferAtr * ctx.atr;
      double risk  = entry - stop;
      if(risk <= 0.0) return false;
      out.dir = +1; out.entry = entry; out.stop = stop;
      out.target = entry + targetR * risk; out.riskDist = risk;
      out.score = 54.0; out.reason = "Asian-range breakout long"; return true;
   }
   if(px < lo - bufferAtr * ctx.atr)
   {
      double entry = ctx.bid;
      double stop  = hi + stopBufferAtr * ctx.atr;
      double risk  = stop - entry;
      if(risk <= 0.0) return false;
      out.dir = -1; out.entry = entry; out.stop = stop;
      out.target = entry - targetR * risk; out.riskDist = risk;
      out.score = 54.0; out.reason = "Asian-range breakout short"; return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| 11. INSIDE-BAR / NR4 BREAKOUT                                    |
//+------------------------------------------------------------------+
bool SigInsideBarBreakout(const SEAContext &ctx, const int nr4Lookback,
                          const double stopBufferAtr, const double targetR,
                          const bool tradeBothWays, SSignalPlan &out)
{
   out.Reset();
   if(ctx.atr <= 0.0) return false;
   MqlRates r[];
   int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, nr4Lookback + 3, r);
   if(got < nr4Lookback + 2) return false;
   MqlRates mother = r[2];
   MqlRates inside = r[1];
   if(!(inside.high <= mother.high && inside.low >= mother.low)) return false;
   //--- NR4 confirmation: mother range is the smallest of the lookback
   double mr = mother.high - mother.low;
   for(int i = 2; i <= nr4Lookback + 1 && i < got; i++)
      if((r[i].high - r[i].low) < mr) return false;

   if(ctx.mid > mother.high)
   {
      double entry = ctx.ask;
      double stop  = MathMin(inside.low, mother.low) - stopBufferAtr * ctx.atr;
      double risk  = entry - stop;
      if(risk <= 0.0) return false;
      out.dir = +1; out.entry = entry; out.stop = stop;
      out.target = entry + targetR * risk; out.riskDist = risk;
      out.score = 53.0; out.reason = "NR4 inside-bar breakout long"; return true;
   }
   if(!tradeBothWays) return false;
   if(ctx.mid < mother.low)
   {
      double entry = ctx.bid;
      double stop  = MathMax(inside.high, mother.high) + stopBufferAtr * ctx.atr;
      double risk  = stop - entry;
      if(risk <= 0.0) return false;
      out.dir = -1; out.entry = entry; out.stop = stop;
      out.target = entry - targetR * risk; out.riskDist = risk;
      out.score = 53.0; out.reason = "NR4 inside-bar breakout short"; return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| 12. GRID / BASKET ARMING (Asian range mean reversion)            |
//+------------------------------------------------------------------+
struct SGridParams
{
   int      armFromMin;      // arm the basket inside this window
   int      armToMin;
   int      bbPeriod;
   double   bbDeviation;
   double   maxAdxDaily;
   double   meanBand;        // trade only within x sigma of the mean
   int      legs;
   double   legSpacingAtr;   // spacing in ATR (signal TF)
   double   basketTargetAtr; // whole-basket profit in ATR from average
   bool     longOnlyBelowMean;
   bool     shortOnlyAboveMean;

   void Reset()
   {
      armFromMin = 22 * 60; armToMin = 24 * 60 + 7 * 60; // 22:00 -> 07:00
      bbPeriod = 20; bbDeviation = 2.0; maxAdxDaily = 20.0; meanBand = 1.0;
      legs = 6; legSpacingAtr = 0.50; basketTargetAtr = 0.30;
      longOnlyBelowMean = true; shortOnlyAboveMean = true;
   }
};

//--- returns the basket direction allowed right now (+1 long grid below mean, -1 short above)
int SigGridArm(const SEAContext &ctx, const SGridParams &p)
{
   if(ctx.atr <= 0.0) return 0;
   int nowMin = ctx.clockMinutes;
   bool inWindow = (p.armFromMin <= p.armToMin)
                   ? (nowMin >= p.armFromMin && nowMin < p.armToMin)
                   : (nowMin >= p.armFromMin || nowMin < p.armToMin);
   if(!inWindow) return 0;
   if(ctx.adx14 > 0.0 && p.maxAdxDaily > 0.0 && ctx.adx14 > p.maxAdxDaily) return 0;

   MqlRates r[];
   int got = EA_Rates(ctx.symbol, PERIOD_D1, 1, p.bbPeriod + 5, r);
   if(got < p.bbPeriod) return 0;
   double sum = 0.0, sum2 = 0.0;
   for(int i = 0; i < p.bbPeriod; i++) { sum += r[i].close; sum2 += r[i].close * r[i].close; }
   double mean = sum / p.bbPeriod;
   double var  = MathMax(0.0, sum2 / p.bbPeriod - mean * mean);
   double sd   = MathSqrt(var);
   if(sd <= 0.0) return 0;
   double z = (ctx.mid - mean) / sd;
   if(MathAbs(z) > p.meanBand) return 0;                 // outside the permitted zone
   if(p.longOnlyBelowMean  && ctx.mid < mean) return +1;
   if(p.shortOnlyAboveMean && ctx.mid > mean) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| 13. TWO-BAR REVERSAL (pin + engulf)                              |
//+------------------------------------------------------------------+
bool SigTwoBarReversal(const SEAContext &ctx, const double wickRatio,
                       const double stopBufferAtr, const double targetR,
                       const bool tradeBothWays, SSignalPlan &out)
{
   out.Reset();
   if(ctx.atr <= 0.0) return false;
   MqlRates r[];
   int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, 3, r);
   if(got < 2) return false;
   MqlRates prev = r[2], cur = r[1];
   if(EA_WickRatio(cur, +1) >= wickRatio && cur.close > prev.high)
   {
      double entry = ctx.ask;
      double stop  = cur.low - stopBufferAtr * ctx.atr;
      double risk  = entry - stop;
      if(risk <= 0.0) return false;
      out.dir = +1; out.entry = entry; out.stop = stop;
      out.target = entry + targetR * risk; out.riskDist = risk;
      out.score = 51.0; out.reason = "Pin-bar reversal long"; return true;
   }
   if(!tradeBothWays) return false;
   if(EA_WickRatio(cur, -1) >= wickRatio && cur.close < prev.low)
   {
      double entry = ctx.bid;
      double stop  = cur.high + stopBufferAtr * ctx.atr;
      double risk  = stop - entry;
      if(risk <= 0.0) return false;
      out.dir = -1; out.entry = entry; out.stop = stop;
      out.target = entry - targetR * risk; out.riskDist = risk;
      out.score = 51.0; out.reason = "Pin-bar reversal short"; return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| 14. SESSION-OPEN FALSE BREAK (quiet-session fade)                |
//+------------------------------------------------------------------+
bool SigSessionFade(const SEAContext &ctx, const int rangeFromMin, const int rangeToMin,
                    const double sweepMaxAtr, const double stopBufferAtr,
                    const double targetR, const bool tradeBothWays, SSignalPlan &out)
{
   out.Reset();
   if(ctx.atr <= 0.0) return false;
   int nowMin = ctx.clockMinutes;
   if(nowMin < rangeToMin || nowMin > rangeToMin + 180) return false;   // only just after the range
   double hi = 0.0, lo = 0.0;
   int bars = 0;
   if(!SigRangeForDay(ctx.symbol, g_eaIndTf, rangeFromMin, rangeToMin, 0, hi, lo, bars)) return false;
   if(hi <= lo) return false;
   if(ctx.mid > hi && (ctx.mid - hi) <= sweepMaxAtr * ctx.atr)
   {
      double entry = ctx.bid;
      double stop  = ctx.mid + stopBufferAtr * ctx.atr;
      double risk  = stop - entry;
      if(risk <= 0.0) return false;
      out.dir = -1; out.entry = entry; out.stop = stop;
      out.target = MathMin(lo, entry - targetR * risk); out.riskDist = risk;
      out.score = 49.0; out.reason = "False break above quiet range"; return true;
   }
   if(!tradeBothWays) return false;
   if(ctx.mid < lo && (lo - ctx.mid) <= sweepMaxAtr * ctx.atr)
   {
      double entry = ctx.ask;
      double stop  = ctx.mid - stopBufferAtr * ctx.atr;
      double risk  = entry - stop;
      if(risk <= 0.0) return false;
      out.dir = +1; out.entry = entry; out.stop = stop;
      out.target = MathMax(hi, entry + targetR * risk); out.riskDist = risk;
      out.score = 49.0; out.reason = "False break below quiet range"; return true;
   }
   return false;
}


//+------------------------------------------------------------------+
//| 15. ORDER-BLOCK RETEST (SMC)                                     |
//|   bullish: last bearish candle before a displacement leg up;     |
//|   the retest of that block is the entry. Mirror for bearish.     |
//+------------------------------------------------------------------+
struct SOrderBlockParams
{
   int      lookbackBars;     // block search window
   double   displacementBody; // displacement candle body ratio
   double   touchTolAtr;      // how close price must come to the block
   double   stopBufferAtr;    // stop beyond the block
   double   targetR;
   bool     requireHtfBias;   // H1 200-EMA must agree
   bool     tradeBothWays;

   void Reset()
   {
      lookbackBars = 12; displacementBody = 0.55; touchTolAtr = 0.15;
      stopBufferAtr = 0.10; targetR = 2.5; requireHtfBias = true; tradeBothWays = true;
   }
};

bool SigOrderBlockRetest(const SEAContext &ctx, const SOrderBlockParams &p, SSignalPlan &out)
{
   out.Reset();
   if(ctx.atr <= 0.0) return false;
   MqlRates r[];
   int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, p.lookbackBars + 2, r);
   if(got < 5) return false;
   double tol = p.touchTolAtr * ctx.atr;

   for(int i = 2; i < got - 1; i++)
   {
      //--- bullish order block: bearish candle followed by a bullish displacement
      MqlRates block = r[i];
      MqlRates disp  = r[i - 1];
      if(block.close < block.open && disp.close > disp.open &&
         EA_BodyRatio(disp) >= p.displacementBody && disp.close > block.high)
      {
         if(p.requireHtfBias && ctx.emaH1_200 > 0.0 && ctx.mid < ctx.emaH1_200) continue;
         //--- price must be retesting the block from above
         if(ctx.mid <= block.low - tol || ctx.mid > block.high + tol) continue;
         double entry = (ctx.ask > 0.0) ? ctx.ask : ctx.mid;
         double stop  = block.low - p.stopBufferAtr * ctx.atr;
         double risk  = entry - stop;
         if(risk <= 0.0) continue;
         out.dir = +1; out.entry = entry; out.stop = stop;
         out.target = entry + p.targetR * risk; out.riskDist = risk;
         out.score = 64.0; out.barsAgo = i;
         out.reason = StringFormat("bullish OB retest (block bar %d)", i);
         return true;
      }
      if(!p.tradeBothWays) continue;
      //--- bearish order block
      if(block.close > block.open && disp.close < disp.open &&
         EA_BodyRatio(disp) >= p.displacementBody && disp.close < block.low)
      {
         if(p.requireHtfBias && ctx.emaH1_200 > 0.0 && ctx.mid > ctx.emaH1_200) continue;
         if(ctx.mid >= block.high + tol || ctx.mid < block.low - tol) continue;
         double entry = (ctx.bid > 0.0) ? ctx.bid : ctx.mid;
         double stop  = block.high + p.stopBufferAtr * ctx.atr;
         double risk  = stop - entry;
         if(risk <= 0.0) continue;
         out.dir = -1; out.entry = entry; out.stop = stop;
         out.target = entry - p.targetR * risk; out.riskDist = risk;
         out.score = 64.0; out.barsAgo = i;
         out.reason = StringFormat("bearish OB retest (block bar %d)", i);
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| 16. FAIR-VALUE-GAP (IMBALANCE) RETEST                            |
//|   bullish gap = bar[i+2].high < bar[i].low over a 3-bar window;  |
//|   the retrace into the gap is the entry.                         |
//+------------------------------------------------------------------+
struct SFvgParams
{
   double   impulseBody;    // middle candle body ratio (the displacement)
   double   minGapAtr;      // gap size floor
   double   stopBufferAtr;
   double   targetR;
   double   maxRetrace;     // allowed retrace into the gap (0..1)
   bool     tradeBothWays;

   void Reset()
   {
      impulseBody = 0.60; minGapAtr = 0.10; stopBufferAtr = 0.15;
      targetR = 3.0; maxRetrace = 0.75; tradeBothWays = true;
   }
};

bool SigFvgRetest(const SEAContext &ctx, const SFvgParams &p, SSignalPlan &out)
{
   out.Reset();
   if(ctx.atr <= 0.0) return false;
   MqlRates r[];
   int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, 10, r);
   if(got < 4) return false;

   for(int i = 1; i <= 3; i++)
   {
      if(i + 2 >= got) continue;
      MqlRates left = r[i + 2], mid = r[i + 1], right = r[i];
      //--- bullish imbalance: gap between left.high and right.low
      if(mid.close > mid.open && EA_BodyRatio(mid) >= p.impulseBody &&
         left.high < right.low && (right.low - left.high) >= p.minGapAtr * ctx.atr)
      {
         double gapLow = left.high, gapHigh = right.low;
         if(ctx.mid < gapLow || ctx.mid > gapHigh + p.stopBufferAtr * ctx.atr) continue;
         if(ctx.mid > gapLow + (gapHigh - gapLow) * p.maxRetrace) continue;
         double entry = (ctx.ask > 0.0) ? ctx.ask : ctx.mid;
         double stop  = gapLow - p.stopBufferAtr * ctx.atr;
         double risk  = entry - stop;
         if(risk <= 0.0) continue;
         out.dir = +1; out.entry = entry; out.stop = stop;
         out.target = entry + p.targetR * risk; out.riskDist = risk;
         out.score = 66.0; out.barsAgo = i;
         out.reason = "bullish FVG retest";
         return true;
      }
      if(!p.tradeBothWays) continue;
      //--- bearish imbalance: gap between left.low and right.high
      if(mid.close < mid.open && EA_BodyRatio(mid) >= p.impulseBody &&
         left.low > right.high && (left.low - right.high) >= p.minGapAtr * ctx.atr)
      {
         double gapHigh = left.low, gapLow = right.high;
         if(ctx.mid > gapHigh || ctx.mid < gapLow - p.stopBufferAtr * ctx.atr) continue;
         if(ctx.mid < gapHigh - (gapHigh - gapLow) * p.maxRetrace) continue;
         double entry = (ctx.bid > 0.0) ? ctx.bid : ctx.mid;
         double stop  = gapHigh + p.stopBufferAtr * ctx.atr;
         double risk  = stop - entry;
         if(risk <= 0.0) continue;
         out.dir = -1; out.entry = entry; out.stop = stop;
         out.target = entry - p.targetR * risk; out.riskDist = risk;
         out.score = 66.0; out.barsAgo = i;
         out.reason = "bearish FVG retest";
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| 17. Z-SCORE / MEAN-REVERSION OVEREXTENSION                       |
//+------------------------------------------------------------------+
bool SigZScoreFade(const SEAContext &ctx, const int period, const double zEntry,
                   const double stopBufferAtr, const double targetR, SSignalPlan &out)
{
   out.Reset();
   if(ctx.atr <= 0.0) return false;
   MqlRates r[];
   int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, period + 3, r);
   if(got < period + 1) return false;
   double sum = 0.0, sum2 = 0.0;
   for(int i = 1; i <= period; i++) { sum += r[i].close; sum2 += r[i].close * r[i].close; }
   double mean = sum / period;
   double var  = MathMax(0.0, sum2 / period - mean * mean);
   double sd   = MathSqrt(var);
   if(sd <= 0.0 || mean <= 0.0) return false;
   double z = (ctx.mid - mean) / sd;

   if(z <= -zEntry)
   {
      double entry = (ctx.ask > 0.0) ? ctx.ask : ctx.mid;
      double stop  = entry - stopBufferAtr * ctx.atr;
      double risk  = entry - stop;
      if(risk <= 0.0) return false;
      out.dir = +1; out.entry = entry; out.stop = stop;
      out.target = MathMax(mean, entry + targetR * risk); out.riskDist = risk;
      out.score = 60.0; out.reason = StringFormat("Z-score fade (z=%.2f)", z);
      return true;
   }
   if(z >= zEntry)
   {
      double entry = (ctx.bid > 0.0) ? ctx.bid : ctx.mid;
      double stop  = entry + stopBufferAtr * ctx.atr;
      double risk  = stop - entry;
      if(risk <= 0.0) return false;
      out.dir = -1; out.entry = entry; out.stop = stop;
      out.target = MathMin(mean, entry - targetR * risk); out.riskDist = risk;
      out.score = 60.0; out.reason = StringFormat("Z-score fade (z=%.2f)", z);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| 18. FRACTAL STRUCTURE (swing highs / lows, sweep detection)      |
//+------------------------------------------------------------------+
//--- fills the last `count` fractal swing highs/lows (series indices, newest first)
int SigFractals(const string sym, const int count, double &highs[], double &lows[], int &hiIdx[], int &loIdx[])
{
   MqlRates r[];
   int got = EA_Rates(sym, g_eaIndTf, 1, 120, r);
   if(got < 10) return 0;
   ArrayResize(highs, 0); ArrayResize(lows, 0);
   ArrayResize(hiIdx, 0); ArrayResize(loIdx, 0);
   for(int i = 1; i < got - 2 && (ArraySize(highs) < count || ArraySize(lows) < count); i++)
   {
      if(r[i].high > r[i + 1].high && r[i].high > r[i + 2].high &&
         r[i].high > r[i - 1].high && (i - 1 >= 0 ? r[i].high >= r[i - 1].high : true))
      {
         if(ArraySize(highs) < count)
         {
            int n = ArraySize(highs);
            ArrayResize(highs, n + 1); ArrayResize(hiIdx, n + 1);
            highs[n] = r[i].high; hiIdx[n] = i;
         }
      }
      if(r[i].low < r[i + 1].low && r[i].low < r[i + 2].low &&
         r[i].low < r[i - 1].low && (i - 1 >= 0 ? r[i].low <= r[i - 1].low : true))
      {
         if(ArraySize(lows) < count)
         {
            int n = ArraySize(lows);
            ArrayResize(lows, n + 1); ArrayResize(loIdx, n + 1);
            lows[n] = r[i].low; loIdx[n] = i;
         }
      }
   }
   return (int)MathMin(ArraySize(highs), ArraySize(lows));
}

#endif // EA_SIGNALS_MQH
//+------------------------------------------------------------------+
