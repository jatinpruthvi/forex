//+------------------------------------------------------------------+
//|                                                SSRN_MOMENTUM.mq5 |
//|                                                                  |
//|  Currency momentum from an EMA mixture, time-series portfolio.   |
//|                                                                  |
//|  Ported from: Rohrbach, Suremann & Osterrieder,                  |
//|               "Momentum and Trend Following Trading Strategies   |
//|                for Currencies Revisited", SSRN 2949379.          |
//|                                                                  |
//|  WHAT IT DOES                                                    |
//|  Implements section 4 of the paper exactly: three EMA pairs       |
//|  (8/24, 16/48, 32/96), normalized twice by rolling volatility,   |
//|  squashed into [-1, 1] by the response function, then averaged.  |
//|  The response-function denominator is sqrt(2)*exp(-1/2). The PDF |
//|  renders its root sign as byte 0xC7, so this constant was        |
//|  verified numerically rather than read off the extracted text.   |
//|  The paper's 313-bar warm-up is enforced - it will not trade     |
//|  before it has enough history for both normalizations.           |
//|                                                                  |
//|  TIME-SERIES MODE ONLY. The paper also defines a cross-sectional |
//|  portfolio (long top-3, short bottom-3 signals across currencies). |
//|  That needs one clock over several currencies; a single-chart EA |
//|  cannot do it honestly, so it is deliberately not faked here.    |
//|  Worth noting: the paper reports the time-series portfolio       |
//|  beating the cross-sectional one everywhere, so this is the      |
//|  stronger of the two anyway.                                     |
//|                                                                  |
//|  THE PAPER'S OWN VERDICT, READ BEFORE YOU TRADE THIS            |
//|  On G10 currencies the authors conclude: "there is no momentum   |
//|  in G10 currencies anymore. Therefore, the strategy is not       |
//|  useful anymore." G10 time-series returned 2.45% p.a. at a       |
//|  Sharpe of 0.53 over 1975-2017. Emerging markets held up at      |
//|  2.48% / Sharpe 0.59. The paper also models NO transaction costs,|
//|  so those figures are overstated. Consider running this on an    |
//|  EM cross, not a G10 one.                                        |
//|                                                                  |
//|  This file is new. Nothing existing was modified to add it.      |
//+------------------------------------------------------------------+
#property copyright "SSRN ports - derived from SSRN working papers"
#property version   "1.00"
#property description "Baz/Rohrbach EMA-mixture currency momentum (SSRN 2949379)"

#include <Trade\Trade.mqh>
#include "../../Include/SSRN/SSRN_Momentum.mqh"

input group "=== Signal ==="
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_D1;   // Signal timeframe
input double   InpMinSignal  = 0.10;    // Ignore |signal| below this (hysteresis)
input double   InpFlatBand   = 0.05;    // Go flat when |signal| drops below this

input group "=== Sizing ==="
input double   InpMaxFraction= 100.0;   // Max % of equity deployed at |signal| = 1
input double   InpFixedLots  = 0.0;     // Or a fixed lot size (0 = use fraction)
input double   InpATR_SL     = 0.0;     // ATR stop multiple (0 = none, paper has none)

input group "=== Guards ==="
input int      InpAtrPeriod  = 14;      // ATR period for the optional stop
input long     InpMagic      = 94711;   // Magic number
input double   InpMaxSpread  = 30.0;    // Max spread, points (0 = off)
input double   InpDailyLossPct= 3.0;    // Halt for the day at -x% (0 = off)

CTrade   g_trade;
string   g_sym;
int      g_atrHandle = INVALID_HANDLE;

SSRN_MOMENTUM_STATE g_st;
datetime g_lastBarTime = 0;
datetime g_dayStamp    = 0;
double   g_dayStartEquity = 0.0;
int      g_posDir = 0;          // +1 long, -1 short, 0 flat
double   g_lastLoggedSignal = 1.0e18;

//--- a blocked EA must say so; otherwise a warm-up looks like a broken EA
bool     g_warmLogged  = false;
int      g_warmN       = -1;
bool     g_readyLogged = false;

//+------------------------------------------------------------------+
int OnInit()
  {
   g_sym = Symbol();
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(20);

   if(InpATR_SL > 0.0)
     {
      g_atrHandle = iATR(g_sym, InpTimeframe, InpAtrPeriod);
      if(g_atrHandle == INVALID_HANDLE)
        {
         Print("Could not create the ATR handle - continuing without a stop.");
         g_atrHandle = INVALID_HANDLE;
        }
     }

   Print("SSRN_MOMENTUM on ", g_sym, " ", EnumToString(InpTimeframe),
         ", magic ", InpMagic, ", warm-up ", SSRN_MOM_MIN_BARS, " bars. ",
         "Half-lives: n=8 -> ", DoubleToString(SSRN_EMAHalfLife(8), 1),
         " bars, n=96 -> ", DoubleToString(SSRN_EMAHalfLife(96), 1), " bars.");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   datetime bar = iTime(g_sym, InpTimeframe, 0);
   if(bar == 0) return;
   if(bar == g_lastBarTime) return;
   g_lastBarTime = bar;

   RollDay();
   if(DailyHaltHit()) return;

   double close[];
   int n = SSRN_CopyClose(g_sym, InpTimeframe, SSRN_MOM_MIN_BARS + 40, close);

   if(n < SSRN_MOM_MIN_BARS)
     {
      //--- This is the single most common reason this EA places nothing.
      //--- It used to return without a word, which reads as "broken".
      if(!g_warmLogged || MathAbs(n - g_warmN) >= 100)
        {
         g_warmLogged = true;
         g_warmN      = n;
         Print("NO TRADE - warming up. ", n, " bars available on ",
               EnumToString(InpTimeframe), ", need ", SSRN_MOM_MIN_BARS,
               ". Shortfall ", MathMax(0, SSRN_MOM_MIN_BARS - n), " bars.",
               " On PERIOD_D1 that is roughly ", DoubleToString(SSRN_MOM_MIN_BARS / 365.0, 1),
               " years of history. Extend the history/test window, or lower InpTimeframe.");
        }
      return;
     }

   if(!SSRN_MomentumSignal(close, n, g_st))
     {
      if(!g_warmLogged)
         Print("NO TRADE - had ", n,
               " bars but the signal could not be evaluated (a rolling sd came back zero).");
      g_warmLogged = true;
      return;
     }
   if(!g_st.ready) return;

   if(!g_readyLogged)
     {
      g_readyLogged = true;
      g_warmLogged  = false;
      Print("Warm-up complete with ", n, " bars. Signal=",
            DoubleToString(g_st.signal, 4),
            ". Trades only when |signal| >= ", DoubleToString(InpMinSignal, 2),
            "; currently ",
            (MathAbs(g_st.signal) >= InpMinSignal ? "ARMED" : "below threshold"), ".");
     }

   //--- log only on a meaningful move, not every bar
   if(MathAbs(g_st.signal - g_lastLoggedSignal) > 0.25)
     {
      g_lastLoggedSignal = g_st.signal;
      Print("Signal=", DoubleToString(g_st.signal, 4),
            "  u=[", DoubleToString(g_st.u[0], 3), ",",
            DoubleToString(g_st.u[1], 3), ",",
            DoubleToString(g_st.u[2], 3), "]",
            "  z=[", DoubleToString(g_st.z[0], 2), ",",
            DoubleToString(g_st.z[1], 2), ",",
            DoubleToString(g_st.z[2], 2), "]");
     }

   ManagePosition();
  }

//+------------------------------------------------------------------+
void RollDay()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime stamp = StringToTime(IntegerToString(dt.year) + "." +
                                 IntegerToString(dt.mon) + "." + IntegerToString(dt.day));
   if(stamp != g_dayStamp)
     {
      g_dayStamp       = stamp;
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
     }
  }

//+------------------------------------------------------------------+
bool DailyHaltHit()
  {
   if(InpDailyLossPct <= 0.0) return false;
   if(g_dayStartEquity <= 0.0) return false;
   double dd = (g_dayStartEquity - AccountInfoDouble(ACCOUNT_EQUITY)) / g_dayStartEquity * 100.0;
   return (dd >= InpDailyLossPct);
  }

//+------------------------------------------------------------------+
bool SpreadOk()
  {
   if(InpMaxSpread <= 0.0) return true;
   long sp = SymbolInfoInteger(g_sym, SYMBOL_SPREAD);
   return ((double)sp <= InpMaxSpread);
  }

//+------------------------------------------------------------------+
int MyDir()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_sym) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      return (type == POSITION_TYPE_BUY ? +1 : -1);
     }
   return 0;
  }

//+------------------------------------------------------------------+
double LotsFor(const double notional)
  {
   if(InpFixedLots > 0.0) return NormalizeDouble(InpFixedLots, 2);
   double price = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double contr = SymbolInfoDouble(g_sym, SYMBOL_TRADE_CONTRACT_SIZE);
   double step  = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);
   double vmin  = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   double vmax  = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MAX);
   if(price <= 0.0 || contr <= 0.0) return vmin;
   double lots = notional / (contr * price);
   if(step > 0.0) lots = MathFloor(lots / step) * step;
   return NormalizeDouble(MathMax(vmin, MathMin(vmax, lots)), 2);
  }

//+------------------------------------------------------------------+
void CloseMine()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_sym) continue;
      g_trade.PositionClose(t);
     }
   g_posDir = 0;
  }

//+------------------------------------------------------------------+
double StopPrice(const int dir)
  {
   if(InpATR_SL <= 0.0 || g_atrHandle == INVALID_HANDLE) return 0.0;
   double buf[];
   if(CopyBuffer(g_atrHandle, 0, 1, 1, buf) < 1) return 0.0;
   double atr = buf[0];
   if(atr <= 0.0) return 0.0;
   if(dir > 0) return SymbolInfoDouble(g_sym, SYMBOL_BID) - atr * InpATR_SL;
   return SymbolInfoDouble(g_sym, SYMBOL_ASK) + atr * InpATR_SL;
  }

//+------------------------------------------------------------------+
void ManagePosition()
  {
   double s = g_st.signal;
   int    cur = MyDir();
   int    want = 0;

   if(s >= InpMinSignal)       want = +1;
   else if(s <= -InpMinSignal) want = -1;
   else if(MathAbs(s) <= InpFlatBand) want = 0;
   else want = cur;                       // inside the hysteresis band: hold

   if(want == cur) return;

   if(cur != 0) CloseMine();
   if(want == 0) return;

   if(!SpreadOk()) return;

   //--- the paper's time-series book sizes the position by the signal
   double frac = MathMin(1.0, MathAbs(s));
   double notional = AccountInfoDouble(ACCOUNT_EQUITY) * InpMaxFraction / 100.0 * frac;
   if(notional <= 0.0) return;

   double lots = LotsFor(notional);
   if(lots <= 0.0) return;

   double sl = StopPrice(want);
   bool ok;
   if(want > 0)
      ok = g_trade.Buy(lots, g_sym, SymbolInfoDouble(g_sym, SYMBOL_ASK), sl, 0.0, "SSRNMOM|");
   else
      ok = g_trade.Sell(lots, g_sym, SymbolInfoDouble(g_sym, SYMBOL_BID), sl, 0.0, "SSRNMOM|");

   if(ok)
     {
      g_posDir = want;
      Print("Momentum ", (want > 0 ? "LONG" : "SHORT"), " ", lots, " ", g_sym,
            " on signal ", DoubleToString(s, 4));
     }
  }
//+------------------------------------------------------------------+
