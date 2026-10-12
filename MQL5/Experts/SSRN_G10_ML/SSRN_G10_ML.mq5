//+------------------------------------------------------------------+
//|                                                  SSRN_G10_ML.mq5 |
//|                                                                  |
//|  Short-term G10 trading driven by a logistic model you train.    |
//|                                                                  |
//|  Ported from: Dhruv Agrawal, "Short-Term Trading Strategy on     |
//|               G10 Currencies", SSRN 3693753.                     |
//|                                                                  |
//|  THIS EA SHIPS INERT BY DESIGN. Read this before expecting a     |
//|  trade. The paper publishes its indicator list and its result     |
//|  (27% p.a., Sharpe 1.60) but NOT the things needed to reproduce  |
//|  it:                                      .                      |
//|     * the fractional-differencing parameter d                    |
//|     * the rule that maps a class label to a position             |
//|     * a single trained weight                                    |
//|  There is therefore nothing to embed. Instead this EA implements |
//|  the paper's FEATURE ENGINEERING faithfully (SSRN_Features.mqh)  |
//|  and scores it with weights loaded from a CSV that YOU produce   |
//|  by running ssrn-ml/train_model.py on your broker's exported     |
//|  OHLC.                                                           |
//|                                                                  |
//|  If the model file is missing or its feature order does not      |
//|  match the EA exactly, it refuses to trade and says why. It will |
//|  never fall back to a guess.                                     |
//|                                                                  |
//|  Treat any result you get as an INTERPRETATION of the paper, not |
//|  as the paper's strategy. The published 27% is not reproducible. |
//|                                                                  |
//|  This file is new. Nothing existing was modified to add it.      |
//+------------------------------------------------------------------+
#property copyright "SSRN ports - derived from SSRN working papers"
#property version   "1.00"
#property description "Feature pipeline + offline-trained logistic model (SSRN 3693753)"

#include <Trade\Trade.mqh>
#include "../../Include/SSRN/SSRN_Model.mqh"

input group "=== Model ==="
input string   InpModelFile = "ssrn_g10_model.csv";  // Model in MQL5\Files\
input double   InpMinConf   = 0.55;     // Ignore predictions below this
input string   InpRatesFile = "";       // Optional rate CSV (date,rate)
input double   InpIrStatic  = 0.0;      // Or a static interest differential (%)

input group "=== Trading ==="
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_H4;   // Signal timeframe
input double   InpNotional  = 10000.0;  // Notional per trade, account currency
input double   InpFixedLots = 0.0;      // Or fixed lots (0 = use notional)
input int      InpMaxBarsIn = 0;        // Time stop, bars (0 = off)

input group "=== Guards ==="
input long     InpMagic     = 94712;    // Magic number
input double   InpMaxSpread = 30.0;     // Max spread, points (0 = off)
input double   InpDailyLossPct = 3.0;   // Halt for the day at -x% (0 = off)

CTrade          g_trade;
SSRN_LogitModel g_model;
string          g_sym;

datetime g_lastBarTime  = 0;
datetime g_dayStamp     = 0;
double   g_dayStartEquity = 0;
int      g_posDir       = 0;
int      g_barsInTrade  = 0;

//--- every early-return below used to be silent, which makes a correctly
//--- behaving EA indistinguishable from a broken one. Log each cause once.
bool     g_noDataLogged = false;
bool     g_noFeatLogged = false;
bool     g_noPredLogged = false;
int      g_belowConf    = 0;      // rejections since the last report
bool     g_reportedLive = false;  // model produced at least one usable score

//--- optional interest-rate series
datetime g_rateTime[];
double   g_rateVal[];
int      g_nRates = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   g_sym = Symbol();
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(20);

   if(!g_model.Load(InpModelFile))
     {
      Print("SSRN_G10_ML: NOT ARMED - ", g_model.Reason());
      Print("Run ssrn-ml/train_model.py on your broker's data and place the ",
            "resulting file in MQL5\\Files\\ as ", InpModelFile);
     }
   else
      Print("SSRN_G10_ML: model armed - ", g_model.Reason());

   LoadRates();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void LoadRates()
  {
   g_nRates = 0;
   if(InpRatesFile == "") return;
   //--- terminal Files first, then the common folder the tester agents share
   int fh = FileOpen(InpRatesFile, FILE_READ | FILE_TXT | FILE_ANSI);
   if(fh == INVALID_HANDLE)
      fh = FileOpen(InpRatesFile, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(fh == INVALID_HANDLE)
     {
      Print("Rate file ", InpRatesFile, " not found; ir_differential will use ",
            DoubleToString(InpIrStatic, 4));
      return;
     }
   while(!FileIsEnding(fh))
     {
      string line = FileReadString(fh);
      StringTrimLeft(line); StringTrimRight(line);
      if(line == "" || StringGetCharacter(line, 0) == '#') continue;
      string p[];
      if(StringSplit(line, StringGetCharacter(",", 0), p) < 2) continue;
      datetime t = StringToTime(p[0]);
      if(t == 0) continue;
      int n = ArraySize(g_rateTime);
      ArrayResize(g_rateTime, n + 1);
      ArrayResize(g_rateVal,  n + 1);
      g_rateTime[n] = t;
      g_rateVal[n]  = StringToDouble(p[1]);
      g_nRates++;
     }
   FileClose(fh);
   Print("Loaded ", g_nRates, " interest-rate observations");
  }

//+------------------------------------------------------------------+
double RateAt(const datetime t)
  {
   if(g_nRates <= 0) return InpIrStatic;
   //--- most recent observation at or before t
   int lo = 0, hi = g_nRates - 1, best = 0;
   while(lo <= hi)
     {
      int mid = (lo + hi) / 2;
      if(g_rateTime[mid] <= t) { best = mid; lo = mid + 1; }
      else hi = mid - 1;
     }
   return g_rateVal[best];
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
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
   if(g_posDir != 0) g_barsInTrade++;

   if(!g_model.IsLoaded()) return;         // armed check happens once, in log

   int need = SSRN_FEAT_MIN_BARS + 2;
   double o[], h[], l[], c[];
   int nO = SSRN_CopyRange(g_sym, InpTimeframe, PRICE_OPEN,  need, o);
   int nH = SSRN_CopyRange(g_sym, InpTimeframe, PRICE_HIGH,  need, h);
   int nL = SSRN_CopyRange(g_sym, InpTimeframe, PRICE_LOW,   need, l);
   int nC = SSRN_CopyRange(g_sym, InpTimeframe, PRICE_CLOSE, need, c);
   if(nO < need || nH < need || nL < need || nC < need)
     {
      if(!g_noDataLogged)
        {
         g_noDataLogged = true;
         Print("NO TRADE - insufficient history on ", EnumToString(InpTimeframe),
               ". Have ", nC, " bars, need ", need,
               " (feature warm-up ", SSRN_FEAT_MIN_BARS, " + 2). ",
               "Extend the test window or lower InpTimeframe.");
        }
      return;
     }
   g_noDataLogged = false;

   double feat[];
   if(!SSRN_BuildFeatures(o, h, l, c, nC, nC - 1, RateAt(bar), bar, feat))
     {
      if(!g_noFeatLogged)
        {
         g_noFeatLogged = true;
         Print("NO TRADE - feature builder rejected bar ", TimeToString(bar),
               " (degenerate or NaN input). This will repeat only for bad bars.");
        }
      return;
     }
   g_noFeatLogged = false;

   double conf = 0.0;
   int    cls  = g_model.Predict(feat, conf);
   if(cls < 0)
     {
      if(!g_noPredLogged)
        {
         g_noPredLogged = true;
         Print("NO TRADE - model could not score this bar (loaded=",
               (g_model.IsLoaded() ? "yes" : "no"), ").");
        }
      return;
     }
   g_noPredLogged = false;

   int want = 0;
   if(cls == SSRN_CLASS_LONG  && conf >= InpMinConf) want = +1;
   if(cls == SSRN_CLASS_SHORT && conf >= InpMinConf) want = -1;

   //--- a model that scores but never clears the confidence gate looks dead;
   //--- say so at a low rate so the Experts log stays readable.
   if(want == 0)
     {
      g_belowConf++;
      if(!g_reportedLive && g_belowConf <= 3)
         Print("Model scored class=", cls, " conf=", DoubleToString(conf, 3),
               " but InpMinConf=", DoubleToString(InpMinConf, 2),
               ". No trade. (reported for the first 3 only)");
      if(g_belowConf == 3) g_reportedLive = true;
     }

   int cur = MyDir();

   //--- time stop
   if(InpMaxBarsIn > 0 && g_posDir != 0 && g_barsInTrade >= InpMaxBarsIn)
     { CloseMine(); cur = 0; }

   if(want == cur) return;

   if(cur != 0) CloseMine();
   if(want == 0) return;

   if(!SpreadOk()) return;

   double lots = LotsFor();
   if(lots <= 0.0) return;

   bool ok;
   if(want > 0)
      ok = g_trade.Buy(lots, g_sym, SymbolInfoDouble(g_sym, SYMBOL_ASK), 0.0, 0.0, "SSRNML|");
   else
      ok = g_trade.Sell(lots, g_sym, SymbolInfoDouble(g_sym, SYMBOL_BID), 0.0, 0.0, "SSRNML|");

   if(ok)
     {
      g_posDir = want;
      g_barsInTrade = 0;
      Print("ML ", (want > 0 ? "LONG" : "SHORT"), " ", lots, " ", g_sym,
            "  class=", cls, " conf=", DoubleToString(conf, 3));
     }
  }

//+------------------------------------------------------------------+
int SSRN_CopyRange(const string sym, const ENUM_TIMEFRAMES tf, const ENUM_APPLIED_PRICE pp,
                   const int count, double &out[])
  {
   ArraySetAsSeries(out, false);
   ArrayResize(out, 0);
   switch(pp)
     {
      case PRICE_OPEN:   return CopyOpen(sym, tf, 0, count, out);
      case PRICE_HIGH:   return CopyHigh(sym, tf, 0, count, out);
      case PRICE_LOW:    return CopyLow(sym, tf, 0, count, out);
      default:           return CopyClose(sym, tf, 0, count, out);
     }
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
   return (SymbolInfoInteger(g_sym, SYMBOL_SPREAD) <= InpMaxSpread);
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
      return (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? +1 : -1);
     }
   return 0;
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
   g_barsInTrade = 0;
  }

//+------------------------------------------------------------------+
double LotsFor()
  {
   if(InpFixedLots > 0.0) return NormalizeDouble(InpFixedLots, 2);
   double price = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double contr = SymbolInfoDouble(g_sym, SYMBOL_TRADE_CONTRACT_SIZE);
   double step  = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);
   double vmin  = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   double vmax  = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MAX);
   if(price <= 0.0 || contr <= 0.0) return vmin;
   double lots = InpNotional / (contr * price);
   if(step > 0.0) lots = MathFloor(lots / step) * step;
   return NormalizeDouble(MathMax(vmin, MathMin(vmax, lots)), 2);
  }
//+------------------------------------------------------------------+
