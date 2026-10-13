//+------------------------------------------------------------------+
//|                                           SSRN_COINTEGRATION.mq5 |
//|                                                                  |
//|  Forex pairs trading gated by Engle-Granger cointegration.       |
//|                                                                  |
//|  Ported from: Lemishko, Landi & Caicedo-Llano,                   |
//|               "Cointegration-Based Strategies in Forex Pairs     |
//|                Trading", SSRN 4771108 (rev. Aug 2026).           |
//|                                                                  |
//|  WHAT IT DOES                                                    |
//|   * watches every unordered pair among the configured symbols    |
//|     (7 majors by default = 21 pairs, the paper's universe);      |
//|   * every test window it screens each pair with Engle-Granger,   |
//|     testing BOTH OLS orientations and keeping the clearer one;   |
//|   * pairs that fail the screen sit flat - that gate is the       |
//|     paper's entire contribution;                                 |
//|   * for eligible pairs it tracks the spread z-score and trades   |
//|     the mean reversion.                                          |
//|                                                                  |
//|  DIFFERENCE FROM THE PAPER, AND WHY                              |
//|  The paper measures PnL as signal(t-2) * (z(t) - z(t-1)) on an   |
//|  unlevered synthetic book. That is a research convention. This   |
//|  EA instead opens two REAL hedging legs at equal notional and     |
//|  lets the broker mark them, so the PnL you see is money, not a   |
//|  z-score proxy. Costs are therefore real (spread + swap) rather  |
//|  than the paper's stylised 2 bp.                                 |
//|                                                                  |
//|  REQUIREMENT: a HEDGING account. Two opposing positions on one   |
//|  symbol exist at the same time by design. The EA refuses to start|
//|  on a netting account.                                           |
//|                                                                  |
//|  This file is new. Nothing existing was modified to add it.      |
//+------------------------------------------------------------------+
#property copyright "SSRN ports - derived from SSRN working papers"
#property version   "1.00"
#property description "Engle-Granger gated forex pairs trading (SSRN 4771108)"

#include <Trade\Trade.mqh>
#include "../../Include/SSRN/SSRN_CoIntegration.mqh"

input group "=== Universe ==="
input string   InpSym1       = "EURUSD";   // Symbol 1
input string   InpSym2       = "GBPUSD";   // Symbol 2
input string   InpSym3       = "USDJPY";   // Symbol 3
input string   InpSym4       = "USDCHF";   // Symbol 4
input string   InpSym5       = "USDCAD";   // Symbol 5
input string   InpSym6       = "AUDUSD";   // Symbol 6
input string   InpSym7       = "NZDUSD";   // Symbol 7
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_D1;  // Signal timeframe

input group "=== Cointegration screen ==="
input int      InpTrainBars  = 257;        // Training window (bars) - paper: 257
input int      InpTestBars   = 21;         // Test window (bars)    - paper: 21
input int      InpAdfPlags   = 1;          // ADF lag augmentation
input int      InpAdfLevel   = 2;          // Significance: 1=10%, 2=5%, 3=1%
input bool     InpLogPrices  = true;       // Test on log prices (paper) vs raw

input group "=== Trading ==="
input double   InpZEntry     = 1.0;        // Enter at |z| > this  (paper: 1)
input double   InpZExit      = 0.3;        // Exit when |z| < this
input int      InpExecLag    = 2;          // Bars to wait before acting (paper: 2)
input int      InpMaxBarsIn  = 40;         // Time stop - max bars in a trade (0 = off)
input int      InpMaxPairs   = 2;          // Max simultaneous pairs (challenge: 2 max)
input double   InpNotionalLeg= 1000.0;     // Notional per leg, account currency
input double   InpRiskPct    = 0.5;        // Or risk this % of equity per leg (challenge default 0.5%)

input group "=== Guards ==="
input long     InpMagic      = 94710;      // Magic number
input double   InpMaxSpread  = 30.0;       // Max spread, points (0 = off)
input double   InpDailyLossPct= 2.0;       // Halt for the day at -x% (challenge: 2%)
input double   InpPairLossPct = 1.0;       // Close pair if it loses this % of equity (0 = off)

CTrade   g_trade;
string   g_syms[7];
int      g_nSyms = 0;

//--- per-pair state, indexed by the pair's slot in the enumeration
struct SSRN_PAIR_STATE
  {
   string            a;
   string            b;
   int               idxA;         // index into g_syms
   int               idxB;
   bool              eligible;     // passed the last Engle-Granger screen
   double            bestT;        // winning residual t-stat
   double            z;            // current spread z-score
   bool              hasZ;
   bool              inTrade;
   int               barsInTrade;
   int               dir;          // +1 long spread, -1 short spread
  };
SSRN_PAIR_STATE g_pairs[];
int             g_nPairs = 0;

int      g_lastScreenKey = -1;
datetime g_lastBarTime   = 0;
double   g_dayStartEquity = 0.0;
datetime g_dayStamp       = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      Print("Warning: algo trading is not enabled for this terminal.");

   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      Print("SSRN_COINTEGRATION needs a HEDGING account. This account is netting, ",
            "so two opposing legs cannot coexist. Refusing to start.");
      return(INIT_FAILED);
     }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(20);

   //--- collect the configured symbols that actually exist
   g_nSyms = 0;
   string raw[7] = { InpSym1, InpSym2, InpSym3, InpSym4, InpSym5, InpSym6, InpSym7 };
   for(int i = 0; i < 7; i++)
     {
      string s = raw[i];
      if(s == "") continue;
      if(!SymbolSelect(s, true))
        {
         Print("Symbol ", s, " is not available - skipping.");
         continue;
        }
      g_syms[g_nSyms++] = s;
     }
   if(g_nSyms < 2)
     {
      Print("Need at least two usable symbols.");
      return(INIT_FAILED);
     }

   //--- enumerate unordered pairs C(n,2), alphabetical by symbol name
   ArrayResize(g_pairs, 0);
   for(int i = 0; i < g_nSyms; i++)
      for(int j = i + 1; j < g_nSyms; j++)
        {
         int slot = ArraySize(g_pairs);
         ArrayResize(g_pairs, slot + 1);
         //--- alphabetical ordering, matching the paper's spread convention
         if(StringCompare(g_syms[i], g_syms[j]) <= 0)
           {
            g_pairs[slot].a = g_syms[i]; g_pairs[slot].idxA = i;
            g_pairs[slot].b = g_syms[j]; g_pairs[slot].idxB = j;
           }
         else
           {
            g_pairs[slot].a = g_syms[j]; g_pairs[slot].idxA = j;
            g_pairs[slot].b = g_syms[i]; g_pairs[slot].idxB = i;
           }
         g_pairs[slot].eligible   = false;
         g_pairs[slot].hasZ       = false;
         g_pairs[slot].inTrade    = false;
         g_pairs[slot].barsInTrade= 0;
         g_pairs[slot].dir        = 0;
        }
   g_nPairs = ArraySize(g_pairs);

   Print("SSRN_COINTEGRATION: ", g_nSyms, " symbols, ", g_nPairs, " unordered pairs, ",
         EnumToString(InpTimeframe), ", magic ", InpMagic);

   ScreenAllPairs(); // initial screen on startup so pairs are ready immediately
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   Process();
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   Process();     // the chart symbol may be closed for the weekend
  }

//+------------------------------------------------------------------+
void Process()
  {
   CloseIfHaltHit();                            // force-close if daily loss limit hit
   if(!SymbolInfoInteger(g_syms[0], SYMBOL_SELECT)) return;

   datetime bar = iTime(g_syms[0], InpTimeframe, 0);
   if(bar == 0) return;
   if(bar == g_lastBarTime) return;             // one pass per new bar
   g_lastBarTime = bar;

   RollDay();

   //--- rescreen when a test window closes
   int key = (int)(bar / (datetime)(InpTestBars * PeriodSeconds(InpTimeframe)));
   if(key != g_lastScreenKey)
     {
      g_lastScreenKey = key;
      ScreenAllPairs();
     }

   UpdateZAll();
   ManageOpen();
   LookForEntries();
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
   //--- count only positions belonging to this EA
   double floatingPl = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      floatingPl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
     }
   double dd = -floatingPl / g_dayStartEquity * 100.0;
   return (dd >= InpDailyLossPct);
  }

//--- force-close all pair positions when daily halt is hit
void CloseIfHaltHit()
  {
   if(!DailyHaltHit()) return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      g_trade.PositionClose(t);
     }
   for(int p = 0; p < g_nPairs; p++)
     {
      g_pairs[p].inTrade     = false;
      g_pairs[p].dir         = 0;
      g_pairs[p].barsInTrade = 0;
     }
  }

//+------------------------------------------------------------------+
string PairTag(const int p)
  {
   return "SSRNCI|" + IntegerToString(p);
  }

//+------------------------------------------------------------------+
void ScreenAllPairs()
  {
   double crit = SSRN_ADF_CRIT_5PCT;
   if(InpAdfLevel == 1) crit = SSRN_ADF_CRIT_10PCT;
   if(InpAdfLevel == 3) crit = SSRN_ADF_CRIT_1PCT;

   int need = InpTrainBars + 3;
   int eligible = 0;

   for(int p = 0; p < g_nPairs; p++)
     {
      g_pairs[p].eligible = false;
      g_pairs[p].hasZ     = false;

      double A[]; double B[];
      int nA = SSRN_CopyClose(g_pairs[p].a, InpTimeframe, need, A);
      int nB = SSRN_CopyClose(g_pairs[p].b, InpTimeframe, need, B);
      if(nA < need || nB < need) continue;
      if(!SSRN_BarsAligned(g_pairs[p].a, g_pairs[p].b, InpTimeframe, need)) continue;

      //--- work on log prices, as the paper does
      double LA[]; double LB[];
      ArrayResize(LA, nA); ArrayResize(LB, nB);
      for(int i = 0; i < nA; i++)
        {
         LA[i] = InpLogPrices ? MathLog(A[i]) : A[i];
         LB[i] = InpLogPrices ? MathLog(B[i]) : B[i];
         if(LA[i] <= 0.0 || LB[i] <= 0.0) { LA[i] = 0; LB[i] = 0; }
        }

      SSRN_COINT_RESULT r;
      SSRN_EngleGranger(LA, LB, MathMin(nA, nB), InpTrainBars, InpAdfPlags, crit, r);

      g_pairs[p].bestT = r.bestT;
      g_pairs[p].eligible = r.pass;
      if(r.pass) eligible++;
     }

   Print("Engle-Granger screen: ", eligible, " of ", g_nPairs, " pairs eligible ",
         "(crit=", DoubleToString(crit, 3), ", window=", InpTrainBars, ")");
  }

//+------------------------------------------------------------------+
void UpdateZAll()
  {
   for(int p = 0; p < g_nPairs; p++)
     {
      g_pairs[p].hasZ = false;
      if(!g_pairs[p].eligible) continue;

      double A[]; double B[];
      int need = InpTrainBars + 2;
      int nA = SSRN_CopyClose(g_pairs[p].a, InpTimeframe, need, A);
      int nB = SSRN_CopyClose(g_pairs[p].b, InpTimeframe, need, B);
      if(nA < need || nB < need) continue;
      if(!SSRN_BarsAligned(g_pairs[p].a, g_pairs[p].b, InpTimeframe, need)) continue;

      double LA[]; double LB[];
      ArrayResize(LA, nA); ArrayResize(LB, nB);
      for(int i = 0; i < nA; i++)
        {
         LA[i] = InpLogPrices ? MathLog(A[i]) : A[i];
         LB[i] = InpLogPrices ? MathLog(B[i]) : B[i];
         if(LA[i] <= 0.0 || LB[i] <= 0.0) { LA[i] = 0; LB[i] = 0; }
        }

      double z = 0.0, mu = 0.0, sd = 0.0, sNow = 0.0;
      if(!SSRN_SpreadZ(LA, LB, MathMin(nA, nB), InpTrainBars, z, mu, sd, sNow)) continue;

      g_pairs[p].z     = z;
      g_pairs[p].hasZ  = true;
     }
  }

//+------------------------------------------------------------------+
int OpenPairCount()
  {
   int n = 0;
   for(int p = 0; p < g_nPairs; p++) if(g_pairs[p].inTrade) n++;
   return n;
  }

//+------------------------------------------------------------------+
bool SpreadOk(const string sym)
  {
   if(InpMaxSpread <= 0.0) return true;
   long sp = SymbolInfoInteger(sym, SYMBOL_SPREAD);
   return ((double)sp <= InpMaxSpread);
  }

//+------------------------------------------------------------------+
double LotsFor(const string sym, const double notional)
  {
   double price   = SymbolInfoDouble(sym, SYMBOL_ASK);
   double contr   = SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE);
   double step    = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double vmin    = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double vmax    = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   if(price <= 0.0 || contr <= 0.0) return vmin;

   double lots = notional / (contr * price);
   if(step > 0.0) lots = MathFloor(lots / step) * step;
   lots = MathMax(vmin, MathMin(vmax, lots));
   return NormalizeDouble(lots, 2);
  }

//+------------------------------------------------------------------+
double LegNotional()
  {
   if(InpRiskPct > 0.0)
      return AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPct / 100.0;
   return InpNotionalLeg;
  }

//+------------------------------------------------------------------+
void LookForEntries()
  {
   if(DailyHaltHit()) return;
   if(InpExecLag > 0 && !LagElapsed()) return;      // honour the paper's delay

   for(int p = 0; p < g_nPairs; p++)
     {
      if(!g_pairs[p].eligible || !g_pairs[p].hasZ) continue;
      if(g_pairs[p].inTrade) continue;
      if(OpenPairCount() >= InpMaxPairs) break;

      double z = g_pairs[p].z;
      if(MathAbs(z) < InpZEntry) continue;

      int dir = (z < 0.0) ? +1 : -1;              // cheap spread -> long it
      if(!TryOpenPair(p, dir)) continue;
     }
  }

//+------------------------------------------------------------------+
datetime g_lastActBar = 0;

bool LagElapsed()
  {
   datetime bar = iTime(g_syms[0], InpTimeframe, 0);
   if(bar == 0) return false;
   //--- on the very first call, record the bar and block (must wait at least one bar)
   if(g_lastActBar == 0)
     {
      g_lastActBar = bar;
      return false;
     }
   if(bar != g_lastActBar)
     {
      g_lastActBar = bar;
      return true;
     }
   return false;   // same bar: lag not elapsed yet
  }

//+------------------------------------------------------------------+
bool TryOpenPair(const int p, const int dir)
  {
   if(!SpreadOk(g_pairs[p].a) || !SpreadOk(g_pairs[p].b)) return false;

   double askA = SymbolInfoDouble(g_pairs[p].a, SYMBOL_ASK);
   double bidA = SymbolInfoDouble(g_pairs[p].a, SYMBOL_BID);
   double askB = SymbolInfoDouble(g_pairs[p].b, SYMBOL_ASK);
   double bidB = SymbolInfoDouble(g_pairs[p].b, SYMBOL_BID);
   if(askA <= 0 || bidA <= 0 || askB <= 0 || bidB <= 0) return false;

   double notional = LegNotional();
   double lotA = LotsFor(g_pairs[p].a, notional);
   double lotB = LotsFor(g_pairs[p].b, notional);
   if(lotA <= 0 || lotB <= 0) return false;

   string tag = PairTag(p);
   bool okA = false, okB = false;

   if(dir > 0)
     {
      //--- long the spread: buy A, sell B
      okA = g_trade.Buy(lotA, g_pairs[p].a, askA, 0.0, 0.0, tag);
      okB = g_trade.Sell(lotB, g_pairs[p].b, bidB, 0.0, 0.0, tag);
     }
   else
     {
      //--- short the spread: sell A, buy B
      okA = g_trade.Sell(lotA, g_pairs[p].a, bidA, 0.0, 0.0, tag);
      okB = g_trade.Buy(lotB, g_pairs[p].b, askB, 0.0, 0.0, tag);
     }

   //--- a half-open pair is the worst outcome; unwind it
   if(okA != okB)
     {
      Print("Pair ", p, " opened only one leg - closing it out.");
      ClosePair(p);
      return false;
     }
   if(!okA) return false;

   g_pairs[p].inTrade     = true;
   g_pairs[p].dir         = dir;
   g_pairs[p].barsInTrade = 0;
   Print("Pair ", p, " ", g_pairs[p].a, "/", g_pairs[p].b,
         " opened ", (dir > 0 ? "LONG" : "SHORT"),
         " spread at z=", DoubleToString(g_pairs[p].z, 3));
   return true;
  }

//+------------------------------------------------------------------+
void ManageOpen()
  {
   for(int p = 0; p < g_nPairs; p++)
     {
      if(!g_pairs[p].inTrade) continue;
      g_pairs[p].barsInTrade++;

      bool exit = false;

      //--- per-pair loss guard
      if(InpPairLossPct > 0.0 && g_dayStartEquity > 0.0)
        {
         double pairPl = 0.0;
         string tag = PairTag(p);
         for(int i = PositionsTotal() - 1; i >= 0; i--)
           {
            ulong t = PositionGetTicket(i);
            if(t == 0) continue;
            if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
            if(PositionGetString(POSITION_COMMENT) != tag) continue;
            pairPl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
           }
         if(-pairPl / g_dayStartEquity * 100.0 >= InpPairLossPct)
           {
            Print("Pair ", p, " ", g_pairs[p].a, "/", g_pairs[p].b,
                  " hit per-pair loss limit (", InpPairLossPct, "%) - closing.");
            exit = true;
           }
        }

      if(InpZExit > 0.0 && g_pairs[p].hasZ && MathAbs(g_pairs[p].z) < InpZExit)
         exit = true;

      if(InpMaxBarsIn > 0 && g_pairs[p].barsInTrade >= InpMaxBarsIn)
         exit = true;

      //--- safety: never stay in a pair that lost its cointegration for
      //--- several consecutive screens (only checked on screen refresh)
      if(!g_pairs[p].eligible)
         exit = true;

      if(exit) ClosePair(p);
     }
  }

//+------------------------------------------------------------------+
void ClosePair(const int p)
  {
   string tag = PairTag(p);
   int closed = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong  ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_COMMENT) != tag) continue;
      if(g_trade.PositionClose(ticket)) closed++;
     }

   g_pairs[p].inTrade     = false;
   g_pairs[p].dir         = 0;
   g_pairs[p].barsInTrade = 0;
   if(closed > 0)
      Print("Pair ", p, " closed ", closed, " leg(s) at z=",
            (g_pairs[p].hasZ ? DoubleToString(g_pairs[p].z, 3) : "n/a"));
  }
//+------------------------------------------------------------------+
