//+------------------------------------------------------------------+
//|                                                    EASpread.mqh  |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Execution-cost telemetry for the shared engine:                  |
//|   * per-symbol spread history (one sample per minute) so a       |
//|     strategy can compare the live spread with its own baseline   |
//|     instead of a fixed number ("1.5x the 20-day average",        |
//|     "2x the 60-min average" - round 10/11/12 documents)          |
//|   * fill-vs-signal slippage per symbol, recorded in R units      |
//|   * closed-trade outcomes in R units, for expectancy gating      |
//|     ("disable a symbol whose slippage eats >20% of expectancy")  |
//|                                                                  |
//| Everything lives in fixed-size ring buffers in the terminal      |
//| process. Nothing is persisted: after a restart the history has   |
//| to be rebuilt from live ticks, and every gate in this file fails  |
//| OPEN while the evidence is too thin to call the symbol bad.       |
//|                                                                  |
//| Depends on: EACore.mqh (EA_Point / EA_PipSize / EA_LossPerLot,    |
//| clock helpers). Included by EACommon.mqh before EATrade.mqh.      |
//+------------------------------------------------------------------+
#ifndef EA_SPREAD_MQH
#define EA_SPREAD_MQH

//--- Symbols tracked per program.  One EA per program uses at most
//--- EA_MAX_SYMBOLS (10) slots; the portfolio host runs 65 engines in one
//--- program and the book spans 19 symbols, so 16 slots silently left the last
//--- symbols without spread/slippage baselines (their gates then fail open).
//--- 32 covers the book with headroom; the rings cost ~1.5 MB.
#define EA_STAT_MAX_SYMBOLS 32
#define EA_SPREAD_RING      1440    // one minute-resolution sample per slot
#define EA_SLIP_RING        128     // fill-vs-signal samples per symbol
#define EA_OUTCOME_RING     128     // closed-trade R multiples per symbol
#define EA_SPREAD_MIN_SAMPLES 8     // below this a baseline is "not evidence"
#define EA_SPREAD_MIN_DAYS    2     // a minute-of-day slot needs this many days
#define EA_SPREAD_DECAY       0.05  // per-day weight of a new slot sample:
                                    // time constant = 1/decay = 20 days

string   g_eaStatSym[EA_STAT_MAX_SYMBOLS];
bool     g_eaStatUsed[EA_STAT_MAX_SYMBOLS];

double   g_eaSpPts[EA_STAT_MAX_SYMBOLS][EA_SPREAD_RING];
datetime g_eaSpTime[EA_STAT_MAX_SYMBOLS][EA_SPREAD_RING];
int      g_eaSpHead[EA_STAT_MAX_SYMBOLS];
int      g_eaSpCount[EA_STAT_MAX_SYMBOLS];      // total samples ever written

//--- per-minute-of-day baseline: exponential average over the terminal's
//--- life with a 20-day time constant (one sample per slot per day)
double   g_eaSpSlot[EA_STAT_MAX_SYMBOLS][EA_SPREAD_RING];
int      g_eaSpSlotDays[EA_STAT_MAX_SYMBOLS][EA_SPREAD_RING];

double   g_eaSlipR[EA_STAT_MAX_SYMBOLS][EA_SLIP_RING];
int      g_eaSlipHead[EA_STAT_MAX_SYMBOLS];
int      g_eaSlipCount[EA_STAT_MAX_SYMBOLS];

double   g_eaOutR[EA_STAT_MAX_SYMBOLS][EA_OUTCOME_RING];
int      g_eaOutHead[EA_STAT_MAX_SYMBOLS];
int      g_eaOutCount[EA_STAT_MAX_SYMBOLS];

//--- map a symbol to its stats slot (created on first use)
int EA_StatIndex(const string sym, const bool create)
{
   if(sym == "") return -1;
   for(int i = 0; i < EA_STAT_MAX_SYMBOLS; i++)
      if(g_eaStatUsed[i] && g_eaStatSym[i] == sym) return i;
   if(!create) return -1;
   for(int i = 0; i < EA_STAT_MAX_SYMBOLS; i++)
   {
      if(g_eaStatUsed[i]) continue;
      g_eaStatUsed[i]      = true;
      g_eaStatSym[i]       = sym;
      g_eaSpHead[i]        = 0;
      g_eaSpCount[i]       = 0;
      g_eaSlipHead[i]      = 0;
      g_eaSlipCount[i]     = 0;
      g_eaOutHead[i]       = 0;
      g_eaOutCount[i]      = 0;
      for(int k = 0; k < EA_SPREAD_RING; k++)
      {
         g_eaSpSlot[i][k]     = 0.0;
         g_eaSpSlotDays[i][k] = 0;
      }
      return i;
   }
   return -1;                                   // more symbols than slots: telemetry off
}

//--- median of a dynamic double array (sorts a copy)
double EA_MedianOf(double &values[])
{
   int n = ArraySize(values);
   if(n <= 0) return 0.0;
   double s[];
   ArrayResize(s, n);
   ArrayCopy(s, values);
   ArraySort(s);
   if(n % 2 == 1) return s[n / 2];
   return 0.5 * (s[n / 2 - 1] + s[n / 2]);
}

//+------------------------------------------------------------------+
//| Spread history                                                   |
//+------------------------------------------------------------------+

//--- sample the live spread, at most once per minute per symbol
//--- (called from the engine's per-tick management pass)
void EA_SpreadSample(const string sym, const double points)
{
   if(points <= 0.0 || points >= 1e11) return;      // no usable quote
   int i = EA_StatIndex(sym, true);
   if(i < 0) return;
   datetime now = TimeTradeServer();
   int last = g_eaSpHead[i];
   if(g_eaSpCount[i] > 0)
   {
      last = (g_eaSpHead[i] - 1 + EA_SPREAD_RING) % EA_SPREAD_RING;
      if(now - g_eaSpTime[i][last] < 60)
      {
         //--- same minute: refresh the sample with the newest quote
         g_eaSpPts[i][last]  = points;
         g_eaSpTime[i][last] = now;
         return;
      }
   }
   //--- minute-of-day baseline: one update per slot per day, 20-day decay
   MqlDateTime sd;
   TimeToStruct(EA_BarClockTime(now), sd);
   int slot = sd.hour * 60 + sd.min;
   if(slot >= 0 && slot < EA_SPREAD_RING)
   {
      if(g_eaSpSlotDays[i][slot] == 0) g_eaSpSlot[i][slot] = points;
      else g_eaSpSlot[i][slot] += EA_SPREAD_DECAY * (points - g_eaSpSlot[i][slot]);
      if(g_eaSpSlotDays[i][slot] < 100000) g_eaSpSlotDays[i][slot]++;
   }
   g_eaSpPts[i][g_eaSpHead[i]]  = points;
   g_eaSpTime[i][g_eaSpHead[i]] = now;
   g_eaSpHead[i] = (g_eaSpHead[i] + 1) % EA_SPREAD_RING;
   g_eaSpCount[i]++;
}

//--- median of the most recent `samples` spread samples (0 = no evidence)
double EA_SpreadMedianRecent(const string sym, const int samples)
{
   int i = EA_StatIndex(sym, false);
   if(i < 0) return 0.0;
   int have = MathMin(g_eaSpCount[i], EA_SPREAD_RING);
   int n    = MathMin(have, MathMax(1, samples));
   if(n <= 0) return 0.0;
   double v[];
   ArrayResize(v, n);
   for(int k = 0; k < n; k++)
   {
      int pos = (g_eaSpHead[i] - 1 - k + 2 * EA_SPREAD_RING) % EA_SPREAD_RING;
      v[k] = g_eaSpPts[i][pos];
   }
   return EA_MedianOf(v);
}

//--- spread baseline for the current time of day: the median of the
//--- minute-of-day slots within ±windowMin, each slot an exponential average
//--- with a ~20-day time constant (the documents' "20-day average spread",
//--- as far as a terminal that has to learn it live can get there).
//--- Falls back to the previous-day samples held in the minute ring, then to
//--- the recent median. Returns 0.0 when there is no evidence at all; callers
//--- treat 0.0 as "cannot judge" and let the entry through.
double EA_SpreadBaseline(const string sym, const int windowMin)
{
   int i = EA_StatIndex(sym, false);
   if(i < 0) return 0.0;
   int have = MathMin(g_eaSpCount[i], EA_SPREAD_RING);
   if(have <= 0) return 0.0;

   datetime nowClock = EA_ClockNow();
   MqlDateTime nd;
   TimeToStruct(nowClock, nd);
   int nowMin = nd.hour * 60 + nd.min;

   //--- 1) multi-day minute-of-day slots with at least EA_SPREAD_MIN_DAYS days
   double slots[];
   ArrayResize(slots, 2 * windowMin + 1);
   int ns = 0;
   for(int d = -windowMin; d <= windowMin; d++)
   {
      int slot = (nowMin + d + EA_SPREAD_RING) % EA_SPREAD_RING;
      if(g_eaSpSlotDays[i][slot] < EA_SPREAD_MIN_DAYS) continue;
      slots[ns++] = g_eaSpSlot[i][slot];
   }
   if(ns >= 5)
   {
      ArrayResize(slots, ns);
      return EA_MedianOf(slots);
   }

   //--- 2) previous-day samples in the same window, from the minute ring
   double v[];
   ArrayResize(v, have);
   int n = 0;
   for(int k = 0; k < have; k++)
   {
      int pos = (g_eaSpHead[i] - 1 - k + 2 * EA_SPREAD_RING) % EA_SPREAD_RING;
      datetime st = EA_BarClockTime(g_eaSpTime[i][pos]);
      MqlDateTime sd;
      TimeToStruct(st, sd);
      if(sd.day == nd.day && sd.mon == nd.mon && sd.year == nd.year) continue;   // today: not a baseline
      int sm = sd.hour * 60 + sd.min;
      int diff = MathAbs(sm - nowMin);
      if(diff > 720) diff = 1440 - diff;                                          // wrap midnight
      if(diff > windowMin) continue;
      v[n++] = g_eaSpPts[i][pos];
   }
   if(n >= EA_SPREAD_MIN_SAMPLES)
   {
      ArrayResize(v, n);
      return EA_MedianOf(v);
   }

   //--- 3) no time-of-day evidence yet
   return EA_SpreadMedianRecent(sym, 240);
}

//--- live spread expressed in pips (engine convention: EA_PipSize)
double EA_SpreadPips(const string sym)
{
   double pip = EA_PipSize(sym);
   if(pip <= 0.0) return 1e12;
   return EA_SpreadPoints(sym) * EA_Point(sym) / pip;
}

//+------------------------------------------------------------------+
//| Fill-vs-signal slippage                                          |
//+------------------------------------------------------------------+

//--- record how far the fill landed from the price the signal wanted,
//--- expressed in R (|filled - expected| / riskDist). One sample per
//--- entry; a failed measurement is simply not recorded.
void EA_SlipRecord(const string sym, const double expected, const double filled, const double riskDist)
{
   if(expected <= 0.0 || filled <= 0.0 || riskDist <= 0.0) return;
   int i = EA_StatIndex(sym, true);
   if(i < 0) return;
   double slipR = MathAbs(filled - expected) / riskDist;
   g_eaSlipR[i][g_eaSlipHead[i]] = slipR;
   g_eaSlipHead[i] = (g_eaSlipHead[i] + 1) % EA_SLIP_RING;
   g_eaSlipCount[i]++;
   EA_Log(EA_LOG_EVENTS, StringFormat("%s fill-vs-signal %.5f vs %.5f = %.3fR slippage",
          sym, filled, expected, slipR));
}

//--- median fill slippage in R (0 = no evidence)
double EA_SlipMedianR(const string sym)
{
   int i = EA_StatIndex(sym, false);
   if(i < 0) return 0.0;
   int have = MathMin(g_eaSlipCount[i], EA_SLIP_RING);
   if(have <= 0) return 0.0;
   double v[];
   ArrayResize(v, have);
   for(int k = 0; k < have; k++)
   {
      int pos = (g_eaSlipHead[i] - 1 - k + 2 * EA_SLIP_RING) % EA_SLIP_RING;
      v[k] = g_eaSlipR[i][pos];
   }
   return EA_MedianOf(v);
}

//+------------------------------------------------------------------+
//| Closed-trade outcomes (R multiples)                              |
//+------------------------------------------------------------------+
void EA_OutcomeRecord(const string sym, const double rMultiple)
{
   if(sym == "") return;
   int i = EA_StatIndex(sym, true);
   if(i < 0) return;
   g_eaOutR[i][g_eaOutHead[i]] = rMultiple;
   g_eaOutHead[i] = (g_eaOutHead[i] + 1) % EA_OUTCOME_RING;
   g_eaOutCount[i]++;
}

//--- average R of the last `samples` closed trades (0 = no evidence)
double EA_ExpectancyR(const string sym, const int samples)
{
   int i = EA_StatIndex(sym, false);
   if(i < 0) return 0.0;
   int have = MathMin(g_eaOutCount[i], EA_OUTCOME_RING);
   int n    = MathMin(have, MathMax(1, samples));
   if(n <= 0) return 0.0;
   double sum = 0.0;
   for(int k = 0; k < n; k++)
   {
      int pos = (g_eaOutHead[i] - 1 - k + 2 * EA_OUTCOME_RING) % EA_OUTCOME_RING;
      sum += g_eaOutR[i][pos];
   }
   return sum / n;
}

//--- "Slippage > 20% of expectancy on a symbol -> symbol disabled".
//--- Fails open: while either sample is too thin to be evidence, or the
//--- expectancy is not positive (that is the expectancy governor's job),
//--- the symbol stays enabled.
bool EA_SymbolSlippageOk(const string sym, const double pctOfExpectancy)
{
   int i = EA_StatIndex(sym, false);
   if(i < 0) return true;
   if(MathMin(g_eaSlipCount[i], EA_SLIP_RING) < 5) return true;
   if(MathMin(g_eaOutCount[i], EA_OUTCOME_RING) < 10) return true;
   int window = MathMin(g_eaOutCount[i], 30);
   double expR = EA_ExpectancyR(sym, window);
   if(expR <= 0.0) return true;
   double slipR = EA_SlipMedianR(sym);
   if(slipR <= pctOfExpectancy / 100.0 * expR) return true;
   EA_Log(EA_LOG_EVENTS, StringFormat("%s disabled: median slippage %.3fR > %.0f%% of %.3fR expectancy",
          sym, slipR, pctOfExpectancy, expR), true);
   return false;
}

//--- history for a symbol (diagnostics / strategy logs)
string EA_SpreadSummary(const string sym)
{
   int i = EA_StatIndex(sym, false);
   if(i < 0) return sym + ": no telemetry";
   return StringFormat("%s spread %.1f pts, median %.1f pts (recent), %.1f pts (time-of-day), slip %.3fR, exp %.3fR",
          sym, EA_SpreadPoints(sym), EA_SpreadMedianRecent(sym, 240),
          EA_SpreadBaseline(sym, 30), EA_SlipMedianR(sym), EA_ExpectancyR(sym, 30));
}

#endif // EA_SPREAD_MQH
//+------------------------------------------------------------------+
