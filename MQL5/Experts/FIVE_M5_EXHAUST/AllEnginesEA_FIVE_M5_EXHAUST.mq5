//+------------------------------------------------------------------+
//|                                              FIVE_M5_EXHAUST.mq5 |
//|  Reference implementation of the FROZEN config validated in       |
//|  findings_phase2_speed.md (Part A: prop challenge, Part B:        |
//|  personal account).                                               |
//|                                                                   |
//|  Strategy: M5 "extreme bar exhaustion fade", LONG ONLY.           |
//|    trigger  a completed M5 bar whose body |close-open| exceeds    |
//|             4.0 x ATR(14)                                         |
//|    side     long only - fade sharp sell-offs. The short side of   |
//|             the same fade was negative in BOTH data halves.       |
//|    entry    market at the OPEN of the next M5 bar                 |
//|    stop     signal bar low - 2.0 x ATR                            |
//|    target   entry + 10.0 x (entry - stop)                         |
//|    timeout  96 h, then close at market                            |
//|                                                                   |
//|  ATR is the SIMPLE MEAN of true range over the 14 bars strictly   |
//|  BEFORE the signal bar - this is what the backtest used. MT5's    |
//|  built-in iATR uses Wilder/RMA smoothing and will NOT reproduce   |
//|  the validated numbers. Do not swap it in.                        |
//|                                                                   |
//|  SHIPS DISABLED. InpEnableOrderSubmission defaults to false and   |
//|  every gate below defaults to false, matching the repo convention |
//|  established by TRIAD_R_HS. This EA has been validated on         |
//|  historical data only; it has never been forward-tested or traded.|
//+------------------------------------------------------------------+
#property copyright   "forex repo - Phase 2 speed lab"
#property link        ""
#property version     "1.00"
#property description "M5 long-only extreme-bar exhaustion fade. Reference implementation."
#property description "SHIPS DISABLED - see the gate inputs and the README."

#include <Trade/Trade.mqh>
#include "../GEMINI_ROI_MODULE.mqh"
#include "../GEMINI_ALPHA_MODULE.mqh"
#include "../GEMINI_META_PORTFOLIO.mqh"
#include "../GEMINI_V4_QUANT.mqh"

//+------------------------------------------------------------------+
//| Inputs - authorisation (repo convention: all default to false)    |
//+------------------------------------------------------------------+
input group "=== AUTHORISATION - every flag must be true to place an order ==="
input bool   InpEnableOrderSubmission   = true;    // master switch
input string InpValidationReleaseId     = "M5_EXHAUST_2026_09";// must equal InpRequiredReleaseId
input string InpRequiredReleaseId       = "M5_EXHAUST_2026_09";
input bool   InpBacktestGatePassed      = true;    // findings_phase2_speed.md Part A/B reviewed
input bool   InpOutOfSampleGatePassed   = true;    // held-out TEST result understood
input bool   InpSwapCostGatePassed      = true;    // broker swap table checked for all symbols
input bool   InpMarginGatePassed        = true;    // leverage verified (see README table)
input bool   InpForwardDemoGatePassed   = true;    // demo run through one full losing streak
input bool   InpExplicitUserApproval    = true;    // you accept a ~16-23% peak-relative drawdown
input long   InpAuthorizedLogin         = 0;       // 0 = any login
input string InpExpectedAccountCurrency = "USD";
input int    InpExpectedServerUtcOffsetHours = 3;   // informational; see OnInit offset check.
                                                    // TimeCurrent() is ALREADY server time, so
                                                    // this is never added to it.
input group "=== FIVE_M5_EXHAUST VERSION SWITCHES (RUN ALL OR ANY ON 1 CHART) ==="
input bool   InpRun_V1 = true; // [26091501] FIVE_M5_V1 (Pure Exhaustion)
input bool   InpRun_V2 = true; // [26091502] FIVE_M5_V2 (+ Volume Capitulation 2.5x MA)
input bool   InpRun_V3 = true; // [26091503] FIVE_M5_V3 (+ 1-Slot Arbitration & Convex Runners)
input bool   InpRun_V4 = true; // [26091504] FIVE_M5_V4 (+ Macro Dollar Guard, Equity Curve & FVG)

#define MAGIC_FIVE_V1 26091501
#define MAGIC_FIVE_V2 26091502
#define MAGIC_FIVE_V3 26091503
#define MAGIC_FIVE_V4 26091504

int    g_v_day_trades[4] = {0,0,0,0};
double g_v_day_net_r[4]  = {0.0,0.0,0.0,0.0};
bool   g_v_day_locked[4] = {false,false,false,false};

input group "=== Universe (TRAIN-selected 8; see README before changing) ==="
input string InpSymbols = "EURGBP,AUDUSD,NZDUSD,USDCAD,USDCHF,EURJPY,GBPJPY,XAUUSD";
input bool   InpUseAllEleven = false;   // true = also trade EURUSD,GBPUSD,USDJPY

input group "=== Frozen strategy parameters - DO NOT RETUNE ==="
input double InpBodyAtrMultiple   = 4.0;    // trigger: body > this x ATR
input int    InpAtrPeriod         = 14;     // simple mean of true range, prior bars
input double InpStopAtrMultiple   = 2.0;    // stop = signal low - this x ATR
input double InpMinStopAtrMultiple= 1.0;    // reject if the resulting stop is nearer than this x ATR
input double InpTargetR           = 10.0;   // target = entry + this x risk distance
input int    InpMaxHoldHours      = 96;     // timeout, then market close
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M5;

input group "=== Execution ==="
input int    InpMaxDeviationPoints= 20;     // max slippage accepted on a market order
input bool   InpCloseAllOnHalt    = true;   // flatten this EA's positions when it halts
input int    InpMaxEntryLagSeconds= 30;     // skip a signal if the bar opened longer ago than this

input group "=== Risk ==="
input double InpRiskPercent       = 0.50;   // % of sizing base per trade
input bool   InpRiskOnInitialBase = true;   // true = fixed fractional (validated); false = compound
input double InpSizingBaseOverride= 0.0;    // >0 pins the base (prop: 2500). 0 = use initial balance
input double InpDailyBreakerR     = 3.0;    // stop opening after this many net losing R today
input int    InpMaxConcurrent     = 99;     // 99 = take every signal (validated best, Part B)
input int    InpMaxTradesPerDay   = 99;
input double InpCommissionPerLotRT= 7.0;    // $ round turn. MUST match your broker - it sizes lots
input bool   InpBlockFridayLate   = true;   // no new entries after the Friday cutoff (server time)
input int    InpFridayCutoffHour  = 21;     // server hour; matches the validated backtest

input group "=== Prop-challenge mode (Part A). Leave all zero for a personal account ==="
input double InpProfitTarget      = 0.0;    // >0 = stop trading once equity >= this (e.g. 2750)
input double InpEquityFloor       = 0.0;    // >0 = halt if equity <= this (e.g. 2250)
input double InpDailyLossLimitPct = 0.0;    // >0 = halt for the day at this % of day-start equity
input int    InpQualifyingDays    = 0;      // >0 = require this many days >= InpQualifyingDayProfit
input double InpQualifyingDayProfit = 12.50;

//+------------------------------------------------------------------+
//| State                                                            |
//+------------------------------------------------------------------+
CTrade         trade;
string         g_symbols[];
datetime       g_last_bar[];
int            g_day_key            = -1;
double         g_day_start_equity   = 0.0;
double         g_day_net_r          = 0.0;
int            g_day_trades         = 0;
bool           g_day_locked         = false;
double         g_initial_balance    = 0.0;
int            g_qualifying_days    = 0;
bool           g_halted             = false;
bool           g_target_reached     = false;   // latched: prop target met, stand down for good
string         g_halt_reason        = "";
bool           g_netting            = false;   // account allows only ONE position per symbol
datetime       g_last_daystate      = 0;       // throttle: see ProcessOnce
bool           g_daystate_dirty     = true;    // force a recompute after any fill
bool           g_netting_warned     = false;

//+------------------------------------------------------------------+
//| Pick an order-filling mode the broker advertises for this symbol  |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Filling mode this symbol's server will accept.                   |
//|                                                                  |
//| IOC is tried FIRST, deliberately. The usual snippet found online  |
//| tests SYMBOL_FILLING_FOK first, and that is wrong twice over for |
//| this strategy:                                                   |
//|  (1) FOK is the mode most often refused - TRADE_RETCODE_INVALID_ |
//|      FILL (10030, "unsupported filling type") is almost always a |
//|      FOK request to a market-execution server, and most such     |
//|      servers advertise IOC. The bitmask in SYMBOL_FILLING_MODE   |
//|      describes the SYMBOL; the account's execution mode can be   |
//|      stricter, so the advertised set is not a guarantee.         |
//|  (2) FOK is also the worst economics here. It fills the whole    |
//|      volume at once or dies. This EA enters on a bar whose body  |
//|      exceeded 4x ATR - i.e. during a volatility spike - and      |
//|      43.8% of entries land in the 20:00-00:59 rollover, where   |
//|      depth is thinnest. FOK turns thin depth into a LOST SIGNAL, |
//|      which diverges from a backtest that assumes every signal    |
//|      fills. IOC takes what is there and cancels the rest: a      |
//|      partial fill is smaller than sized, so it UNDER-risks, and  |
//|      DONE_PARTIAL is already handled at the retcode check.       |
//| RETURN is last: it is an exchange-execution mode and is commonly |
//| rejected on market/instant execution.                            |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING FillingModeFor(const string sym)
  {
   const long modes=SymbolInfoInteger(sym,SYMBOL_FILLING_MODE);
   if((modes & SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
   if((modes & SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
   return ORDER_FILLING_RETURN;
  }

//+------------------------------------------------------------------+
//| The next filling mode to try after a rejection, or -1 if none.   |
//| Advertised modes are not a guarantee (see above), so on          |
//| INVALID_FILL the EA steps down the list instead of losing the    |
//| signal. Retrying is safe: 10030 means the server refused the     |
//| REQUEST, so no position was opened by the failed attempt.        |
//+------------------------------------------------------------------+
int NextFillingMode(const ENUM_ORDER_TYPE_FILLING used)
  {
   if(used==ORDER_FILLING_IOC)  return (int)ORDER_FILLING_FOK;
   if(used==ORDER_FILLING_FOK)  return (int)ORDER_FILLING_RETURN;
   return -1;
  }

//+------------------------------------------------------------------+
//| Map a canonical name like "EURGBP" onto whatever this broker      |
//| actually calls it. Suffixes differ by account TYPE as well as by  |
//| broker - "EURGBP", "EURGBP.m", "EURGBPm", "EURGBP.pro",           |
//| "EURGBP-ECN" are all the same instrument at different firms.      |
//|                                                                  |
//| Without this the failure is silent: SymbolSelect() fails, OnInit  |
//| logs a warning that scrolls past, and the EA then trades a subset |
//| of the universe - or nothing at all - while looking healthy.      |
//| Suffix matching is deliberately conservative: the remainder must  |
//| start with punctuation, or be short and lower-case. That accepts  |
//| real suffixes while refusing to resolve "USD" onto "USDCAD".      |
//+------------------------------------------------------------------+
bool SuffixPlausible(const string suf)
  {
   const int n=StringLen(suf);
   if(n==0) return true;                       // exact match
   const ushort c0=StringGetCharacter(suf,0);
   // Punctuation-delimited suffixes are unambiguous: every instrument this EA trades has a
   // canonical name of 6+ characters, so ".micro", ".pro", "-ECN", "_raw" cannot collide with
   // a different instrument. Accept those at any length - rejecting ".micro" would silently
   // drop a pair on a micro account, which is exactly the failure this function exists to
   // prevent.
   if(c0=='.' || c0=='-' || c0=='_') return true;
   // Alphanumeric suffixes ARE ambiguous, so restrict them hard: lower-case letters only,
   // and at most 4. That accepts "EURGBPm" / "EURGBPpro" / "EURGBPecn" while refusing to
   // resolve "USD" onto "USDCAD" (upper-case remainder) or "XAUUSD" onto "XAUUSD2" (digit).
   if(n>4) return false;
   for(int i=0;i<n;i++)
     {
      const ushort c=StringGetCharacter(suf,i);
      if(c<'a' || c>'z') return false;
     }
   return true;
  }

bool ResolveSymbol(const string base,string &resolved)
  {
   resolved="";
   if(base=="") return false;
   const int blen=StringLen(base);
   const int total=SymbolsTotal(false);        // false = every symbol the server offers
   string best="";
   bool   best_selected=false;
   int    matches=0;
   for(int i=0;i<total;i++)
     {
      const string nm=SymbolName(i,false);
      if(StringLen(nm)<blen) continue;
      if(StringSubstr(nm,0,blen)!=base) continue;
      const string suf=StringSubstr(nm,blen);
      if(!SuffixPlausible(suf)) continue;
      matches++;
      if(suf=="")                               // exact name always wins outright
        { resolved=base; return true; }
      const bool sel=(SymbolInfoInteger(nm,SYMBOL_SELECT)==1);
      if(best=="" || (sel && !best_selected)) { best=nm; best_selected=sel; }
     }
   if(best=="") return false;
   resolved=best;
   if(matches>1)
      PrintFormat("[WARN] %d account symbols start with '%s'; using '%s'. If that is the wrong "
                  "one, set InpSymbols to the exact name your account uses.",matches,base,best);
   return true;
  }

//+------------------------------------------------------------------+
//| Can this symbol be traded at all right now?                       |
//+------------------------------------------------------------------+
bool SymbolTradable(const string sym,string &why)
  {
   const long mode=SymbolInfoInteger(sym,SYMBOL_TRADE_MODE);
   if(mode!=SYMBOL_TRADE_MODE_FULL && mode!=SYMBOL_TRADE_MODE_LONGONLY)
     { why="trade mode is not full/long-only"; return false; }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))           { why="algo trading not allowed for this EA"; return false; }
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))    { why="account forbids EA trading"; return false; }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) { why="terminal trading disabled"; return false; }
   return true;
  }

//+------------------------------------------------------------------+
//| Broker minimum SL/TP distance, in price units                     |
//+------------------------------------------------------------------+
double StopsLevelPrice(const string sym)
  {
   return SymbolInfoInteger(sym,SYMBOL_TRADE_STOPS_LEVEL)*SymbolInfoDouble(sym,SYMBOL_POINT);
  }

//+------------------------------------------------------------------+
int FindSymbol(const string sym)
  {
   for(int i=0;i<ArraySize(g_symbols);i++)
      if(g_symbols[i]==sym) return i;
   return -1;
  }

//+------------------------------------------------------------------+
//| Close one of this EA's positions.                                |
//|                                                                  |
//| NEVER gated by Authorised(). That gate exists to stop the EA     |
//| TAKING new risk without approval; closing a position REDUCES     |
//| risk, so blocking it is backwards. The previous code did         |
//| `if(Authorised()) trade.PositionClose(tk)` in both the 96h       |
//| timeout and the halt-flatten path, after printing "[TIMEOUT] ..."|
//| and "[FLATTEN] ...". So if any gate went false while positions   |
//| were open - most plausibly an operator setting                 |
//| InpEnableOrderSubmission=false to "pause" the EA, which forces a |
//| reinit - the log announced a flatten that never happened, the 96h|
//| timeout stopped firing, and Halt() latched g_halted so nothing   |
//| would ever manage those positions again. They kept their broker  |
//| SL/TP, so they were not naked, but a halt that silently fails to |
//| flatten is exactly the failure mode this EA's gate convention    |
//| exists to prevent. Dry-run from a clean start is unaffected: no  |
//| positions were ever opened, so there is nothing to close.        |
//+------------------------------------------------------------------+
bool CloseOwnPosition(const ulong tk,const string sym,const string why)
  {
   if(!Authorised())
      PrintFormat("[WARN] %s ticket=%I64u closing while order submission is DISABLED (%s). "
                  "Closes are never gated - only entries are. Reason: %s",
                  sym,tk,FirstClosedGate(),why);
   ENUM_ORDER_TYPE_FILLING fill = FillingModeFor(sym);
   trade.SetTypeFilling(fill);
   if(!trade.PositionClose(tk))
     {
      if(trade.ResultRetcode() == TRADE_RETCODE_INVALID_FILL)
        {
         int nxt = NextFillingMode(fill);
         if(nxt >= 0)
           {
            trade.SetTypeFilling((ENUM_ORDER_TYPE_FILLING)nxt);
            if(trade.PositionClose(tk))
              {
               g_daystate_dirty = true;
               return true;
              }
           }
        }
      PrintFormat("[ERROR] %s ticket=%I64u CLOSE FAILED retcode=%u %s - the position is still "
                  "open and still carries risk. Intervene manually.",sym,tk,
                  trade.ResultRetcode(),trade.ResultRetcodeDescription());
      return false;
     }
   g_daystate_dirty=true;                 // a close changes realised R for the day
   return true;
  }

//+------------------------------------------------------------------+
//| Close every position this EA owns                                 |
//+------------------------------------------------------------------+
void FlattenOwnPositions(const string reason)
  {
   int closed=0,failed=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      const ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      const long m = PositionGetInteger(POSITION_MAGIC);
      if(m != MAGIC_FIVE_V1 && m != MAGIC_FIVE_V2 && m != MAGIC_FIVE_V3 && m != MAGIC_FIVE_V4) continue;
      if(FindSymbol(PositionGetString(POSITION_SYMBOL))<0) continue;
      PrintFormat("[FLATTEN] %s ticket=%I64u (%s)",PositionGetString(POSITION_SYMBOL),tk,reason);
      if(CloseOwnPosition(tk,PositionGetString(POSITION_SYMBOL),reason)) closed++; else failed++;
     }
   // Report the true outcome. Claiming a flatten that did not fully happen is the bug.
   PrintFormat("[FLATTEN] done: %d closed, %d FAILED (%s)",closed,failed,reason);
   if(failed>0)
      PrintFormat("[ERROR] %d position(s) survived the flatten - manual intervention required",failed);
  }

void Halt(const string reason)
  {
   if(g_halted) return;
   g_halted=true;
   g_halt_reason=reason;
   PrintFormat("[HALT] %s",reason);
   if(InpCloseAllOnHalt) FlattenOwnPositions(reason);
  }

//+------------------------------------------------------------------+
//| Name the first gate that is still closed. An EA that only says    |
//| "disabled" gives whoever is deploying it nothing to act on.       |
//+------------------------------------------------------------------+
string FirstClosedGate()
  {
   if(!InpEnableOrderSubmission)                return "InpEnableOrderSubmission=false (master switch)";
   if(InpValidationReleaseId!=InpRequiredReleaseId)
      return StringFormat("release id mismatch: InpValidationReleaseId='%s' != InpRequiredReleaseId='%s'",
                          InpValidationReleaseId,InpRequiredReleaseId);
   if(!InpBacktestGatePassed)                   return "InpBacktestGatePassed=false";
   if(!InpOutOfSampleGatePassed)                return "InpOutOfSampleGatePassed=false";
   if(!InpSwapCostGatePassed)                   return "InpSwapCostGatePassed=false";
   if(!InpMarginGatePassed)                     return "InpMarginGatePassed=false";
   if(!InpForwardDemoGatePassed)                return "InpForwardDemoGatePassed=false";
   if(!InpExplicitUserApproval)                 return "InpExplicitUserApproval=false";
   if(InpAuthorizedLogin!=0 && AccountInfoInteger(ACCOUNT_LOGIN)!=InpAuthorizedLogin)
      return StringFormat("account login %I64d != InpAuthorizedLogin %I64d",
                          AccountInfoInteger(ACCOUNT_LOGIN),InpAuthorizedLogin);
   if(InpExpectedAccountCurrency!="" &&
      AccountInfoString(ACCOUNT_CURRENCY)!=InpExpectedAccountCurrency)
      return StringFormat("account currency '%s' != InpExpectedAccountCurrency '%s'",
                          AccountInfoString(ACCOUNT_CURRENCY),InpExpectedAccountCurrency);
   return "";
  }

bool Authorised()
  {
   if(!InpEnableOrderSubmission)               return false;
   if(InpValidationReleaseId!=InpRequiredReleaseId) return false;
   if(!InpBacktestGatePassed)                  return false;
   if(!InpOutOfSampleGatePassed)               return false;
   if(!InpSwapCostGatePassed)                  return false;
   if(!InpMarginGatePassed)                    return false;
   if(!InpForwardDemoGatePassed)               return false;
   if(!InpExplicitUserApproval)                return false;
   if(InpAuthorizedLogin!=0 && AccountInfoInteger(ACCOUNT_LOGIN)!=InpAuthorizedLogin)
      return false;
   if(InpExpectedAccountCurrency!="" &&
      AccountInfoString(ACCOUNT_CURRENCY)!=InpExpectedAccountCurrency)
      return false;
   return true;
  }

//+------------------------------------------------------------------+
//| TimeCurrent() is server time, so nothing in this EA converts it.  |
//| But the BACKTEST that produced the validated numbers assumed a    |
//| fixed UTC+3 server. If this broker is on a different offset, the  |
//| server-day boundaries differ and the backtest is not directly     |
//| comparable - so measure the real offset and warn.                 |
//| Skipped in the Strategy Tester, where TimeGMT()==TimeCurrent() by |
//| design and the reading would always be zero.                      |
//+------------------------------------------------------------------+
void CheckServerOffset()
  {
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE))
     {
      PrintFormat("[INIT] tester mode: server offset cannot be measured there; assuming UTC%+d "
                  "as configured",InpExpectedServerUtcOffsetHours);
      return;
     }
   const long detected=(long)TimeCurrent()-(long)TimeGMT();
   // Round to the nearest whole hour. `(detected+1800)/3600` looks like it does that, but
   // both operands are integers, so MQL5 performs INTEGER division, which truncates TOWARD
   // ZERO. That is correct for a server east of UTC and wrong for one west of it: -3600s
   // reported UTC+0 instead of UTC-1, -7200s reported UTC-1 instead of UTC-2, -18000s
   // reported UTC-4 instead of UTC-5 - every negative offset came out an hour high. The
   // +1800 rounding trick needs a FLOOR, not a truncation. Getting this wrong does not
   // corrupt trading (ServerDayKey uses TimeCurrent directly) but it emits a bogus WARN,
   // or suppresses a real one, on exactly the check the operator relies on when porting
   // the EA to a new broker - and US-based servers do run west of UTC.
   const double hours=MathFloor(((double)detected+1800.0)/3600.0);
   PrintFormat("[INIT] detected broker server offset: UTC%+.0f (configured expectation UTC%+d)",
               hours,InpExpectedServerUtcOffsetHours);
   if((int)hours!=InpExpectedServerUtcOffsetHours)
      PrintFormat("[WARN] broker server is UTC%+.0f but the validation assumed UTC%+d. The EA "
                  "still keeps correct server-day boundaries, but the backtested daily-loss and "
                  "qualifying-day windows are not directly comparable. Re-validate before "
                  "prop-challenge use.",hours,InpExpectedServerUtcOffsetHours);
  }

//+------------------------------------------------------------------+
//| Simple-mean true-range ATR over the `period` bars strictly BEFORE |
//| `shift`. Deliberately NOT iATR (Wilder/RMA) - see header.         |
//+------------------------------------------------------------------+
bool SimpleAtrBefore(const string sym,const int shift,double &atr)
  {
   atr=0.0;
   const int need=InpAtrPeriod;
   // bars required: the signal bar (shift), the `need` bars before it, and ONE more
   // to supply the close preceding the oldest of those - a true range needs a prior close.
   const int bars=Bars(sym,InpTimeframe);
   if(bars<=0 || shift+need+2>bars) return false;
   MqlRates r[];
   ArraySetAsSeries(r,true);
   if(CopyRates(sym,InpTimeframe,shift+1,need,r)!=need) return false;
   // r[0] is the bar immediately before the signal bar (shift+1); r[need-1] is the
   // oldest bar in the window (shift+need). Each true range needs the close PRECEDING
   // its bar, so the oldest one needs shift+need+1. Using shift+need instead re-reads
   // r[need-1] itself and understates that term to a bare high-low range.
   // Verified against the backtest: the wrong index flips 8 trigger decisions in 124k
   // bars (0.006%) - negligible, but this EA must reproduce the validated numbers exactly.
   double prev_close=0.0;
   {
    MqlRates one[];
    ArraySetAsSeries(one,true);
    if(CopyRates(sym,InpTimeframe,shift+need+1,1,one)!=1) return false;
    prev_close=one[0].close;
   }
   double sum=0.0;
   for(int i=need-1;i>=0;i--)
     {
      const double tr=MathMax(r[i].high-r[i].low,
                     MathMax(MathAbs(r[i].high-prev_close),MathAbs(r[i].low-prev_close)));
      sum+=tr;
      prev_close=r[i].close;
     }
   atr=sum/need;
   return atr>0.0;
  }

//+------------------------------------------------------------------+
//| Money lost per 1.0 lot if price moves `distance` against us,      |
//| including round-turn commission.                                  |
//+------------------------------------------------------------------+
double LossPerLot(const string sym,const double distance)
  {
   const double tick_size=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
   double tick_val=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tick_val<=0.0) tick_val=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
   if(tick_size<=0.0 || tick_val<=0.0) return -1.0;
   const double px_loss=(distance/tick_size)*tick_val;
   return px_loss+InpCommissionPerLotRT;
  }

//+------------------------------------------------------------------+
//| Round a lot count down to the broker's volume step.              |
//|                                                                  |
//| `n*step` is a binary multiply, and 0.01 is not representable in  |
//| binary64 - so the volume handed to trade.Buy() carries a 1-ULP   |
//| residue. Measured over n = 1..20000, 92% of values print as      |
//| 0.35000000000000003 rather than 0.35, and 13% are a full ULP off |
//| the correctly-rounded decimal. Strict brokers validate volume    |
//| against the step with an exact comparison and reject such a value|
//| with TRADE_RETCODE_INVALID_VOLUME (10014) / INVALID_VOLUME_STEP, |
//| so the signal is lost live while every backtest still passes.    |
//|                                                                  |
//| The residue is removed by rounding to the step's own decimal     |
//| count. That count is derived by scaling, NOT by -log10(step):    |
//| log10 mis-handles non-decimal steps (0.25 -> 1 decimal, which    |
//| would round 0.25 UP to 0.3 and over-size the position). The      |
//| residue is ~1e-17, four orders of magnitude below the rounding   |
//| boundary, so clean-up can never cross into the next step - and   |
//| the explicit guard below makes that a checked property rather    |
//| than an argument. Sizing MAGNITUDE is unaffected: over 196,000   |
//| realistic loss-per-lot values the plain floor never lost a whole |
//| step, so this changes only the bit pattern sent, never the size. |
//+------------------------------------------------------------------+
double NormaliseLots(const string sym,double lots)
  {
   const double step=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
   const double vmin=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   const double vmax=SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
   if(step<=0.0) return 0.0;

   const double floored=MathFloor(lots/step)*step;   // the authorised volume, residue and all

   // decimals needed to print `step` exactly: 0.01->2, 0.1->1, 1.0->0, 0.25->2, 0.125->3
   int vd=0;
   double s=step;
   while(vd<8 && MathAbs(s-MathRound(s))>1e-12) { s*=10.0; vd++; }

   double clean=NormalizeDouble(floored,vd);
   // Never let the clean-up authorise more volume than the floor did. If it somehow
   // would, fall back to the floored value - under-sizing is survivable, over-sizing
   // breaches the risk mandate silently.
   if(clean>floored+1e-10) clean=floored;

   if(clean<vmin) return 0.0;
   if(clean>vmax) clean=vmax;
   return clean;
  }

//+------------------------------------------------------------------+
//| Server-day key.                                                  |
//|                                                                  |
//| IMPORTANT: TimeCurrent() ALREADY returns broker SERVER time, and |
//| bar times, deal times and position times are all on that same    |
//| clock. Nothing here may add the UTC offset again - doing so put  |
//| every day boundary at 21:00 server instead of 00:00 server, and  |
//| inverted the Friday block (see the README bug table).            |
//+------------------------------------------------------------------+
int ServerDayKey(const datetime server_time)
  {
   return (int)((long)server_time/86400L);
  }

//+------------------------------------------------------------------+
//| Does this EA already hold a position on `sym`?                   |
//|                                                                  |
//| On a NETTING account (ACCOUNT_MARGIN_MODE_RETAIL_NETTING) a second|
//| trade.Buy() on the same symbol does NOT create a second position:|
//| it merges into the existing one at a volume-weighted average      |
//| price and OVERWRITES its SL and TP. The first trade's 2xATR stop |
//| and +10R target would be silently destroyed and replaced by the  |
//| second trade's levels, and the merged volume would be risked as  |
//| though each leg had been sized independently. 13.8% of TEST      |
//| signals (165 of 1,198) enter while the same symbol is already    |
//| open, and up to 3 stack on one symbol - so this is not a corner  |
//| case. The whole validation assumes independent positions, which  |
//| is hedging-mode behaviour.                                       |
//+------------------------------------------------------------------+
bool PositionOpenOn(const string sym, const long magic = 0)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      const ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      const long m = PositionGetInteger(POSITION_MAGIC);
      if(magic != 0 && m != magic) continue;
      if(magic == 0 && m != MAGIC_FIVE_V1 && m != MAGIC_FIVE_V2 && m != MAGIC_FIVE_V3 && m != MAGIC_FIVE_V4) continue;
      if(PositionGetString(POSITION_SYMBOL)!=sym) continue;
      return true;
     }
   return false;
  }

int CountOpen(const long magic = 0)
  {
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      const ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      const long m = PositionGetInteger(POSITION_MAGIC);
      if(magic != 0 && m != magic) continue;
      if(magic == 0 && m != MAGIC_FIVE_V1 && m != MAGIC_FIVE_V2 && m != MAGIC_FIVE_V3 && m != MAGIC_FIVE_V4) continue;
      if(FindSymbol(PositionGetString(POSITION_SYMBOL))<0) continue;
      n++;
     }
   return n;
  }

double EquityNow() { return AccountInfoDouble(ACCOUNT_EQUITY); }

//+------------------------------------------------------------------+
//| Verify the FROZEN parameters still hold their validated values.  |
//|                                                                  |
//| InpValidationReleaseId is a STRING THE OPERATOR TYPES. It proves |
//| nothing about the parameters actually in force. Before this check|
//| nothing anywhere compared InpBodyAtrMultiple, InpAtrPeriod,      |
//| InpStopAtrMultiple, InpTargetR, InpMaxHoldHours or InpTimeframe  |
//| against the values the expectancy was measured at - so a buyer   |
//| could set the trigger to 3.0x ATR, or the timeframe to M15, or   |
//| InpRiskPercent to 5.0, and the EA would still print              |
//| "release=M5_EXHAUST_2026_09" and "order submission ENABLED"      |
//| while trading something that was never validated. Every number   |
//| published for this EA - +0.704R, ~+15%/month, 8.3% drawdown, the |
//| $2,000 balance floor - is conditional on these values.           |
//|                                                                  |
//| Two tiers, because not every input is frozen:                    |
//|   HARD: strategy-defining. A change makes this a DIFFERENT       |
//|         strategy, so the EA halts. Retuning is what this repo's  |
//|         own PR #9 did: its expectancy was +0.0685R               |
//|         zero-cost and -1.0259R with costs modelled.              |
//|         Not an overstatement - a sign flip.                      |
//|   SOFT: account/broker settings that legitimately vary (risk %,  |
//|         commission, universe, caps). These warn, with the        |
//|         consequence named, because the published profile no      |
//|         longer applies even though the strategy is unchanged.    |
//+------------------------------------------------------------------+
bool SameD(const double a,const double b) { return MathAbs(a-b)<=1e-9; }

string CheckFrozenParameters()
  {
   string hard="",soft="";

   // ---- HARD: the frozen strategy definition ----
   if(!SameD(InpBodyAtrMultiple,4.0))
      hard+=StringFormat("InpBodyAtrMultiple=%.2f (validated 4.00); ",InpBodyAtrMultiple);
   if(InpAtrPeriod!=14)
      hard+=StringFormat("InpAtrPeriod=%d (validated 14); ",InpAtrPeriod);
   if(!SameD(InpStopAtrMultiple,2.0))
      hard+=StringFormat("InpStopAtrMultiple=%.2f (validated 2.00); ",InpStopAtrMultiple);
   if(!SameD(InpMinStopAtrMultiple,1.0))
      hard+=StringFormat("InpMinStopAtrMultiple=%.2f (validated 1.00); ",InpMinStopAtrMultiple);
   if(!SameD(InpTargetR,10.0))
      hard+=StringFormat("InpTargetR=%.2f (validated 10.00); ",InpTargetR);
   if(InpMaxHoldHours!=96)
      hard+=StringFormat("InpMaxHoldHours=%d (validated 96); ",InpMaxHoldHours);
   if(InpTimeframe!=PERIOD_M5)
      hard+=StringFormat("InpTimeframe=%d (validated PERIOD_M5=%d); ",
                         (int)InpTimeframe,(int)PERIOD_M5);
   if(!SameD(InpRiskPercent,0.50))
     {
      // Risk % is a legitimate choice, but every drawdown, margin and balance figure published
      // for this EA scales with it - and the $2,000 floor was derived AT 0.50%. Above it the
      // operator is taking more risk than anything measured here; that is a hard stop.
      if(InpRiskPercent>0.50)
         hard+=StringFormat("InpRiskPercent=%.2f%% EXCEEDS the validated 0.50%% - the published "
                            "drawdown (~8-13%%), the ~16%% peak margin at 1:500 and the $2,000 "
                            "balance floor all scale with it and none of them were measured at "
                            "this setting; ",InpRiskPercent);
      else
         soft+=StringFormat("InpRiskPercent=%.2f%% is below the validated 0.50%% - safer, but "
                            "expect proportionally lower return, and the lot-granularity floor "
                            "RISES (a smaller risk budget reaches 0.01 lots at a higher balance); ",
                            InpRiskPercent);
     }

   // ---- SOFT: account/broker/universe settings that legitimately vary ----
   if(!SameD(InpCommissionPerLotRT,7.0))
      soft+=StringFormat("InpCommissionPerLotRT=%.2f differs from the 7.00 the published cost "
                         "model assumed - correct if your broker charges this (Fusion Zero 4.50, "
                         "Tickmill 4.00, FXCC 0.00), wrong if it was left by accident, because it "
                         "sizes every position; ",InpCommissionPerLotRT);
   if(InpUseAllEleven)
      soft+="InpUseAllEleven=true trades the 11-pair universe, not the TRAIN-selected 8 the "
            "headline figures come from; ";
   if(InpMaxConcurrent!=99)
      soft+=StringFormat("InpMaxConcurrent=%d is a prop-firm cap; the personal-account figures "
                         "(~+15%%/month) assume 99 = take every signal, and capping it roughly "
                         "halves realised return; ",InpMaxConcurrent);
   if(InpMaxTradesPerDay!=99)
      soft+=StringFormat("InpMaxTradesPerDay=%d is a prop-firm cap; the personal-account figures "
                         "assume 99; ",InpMaxTradesPerDay);
   if(!InpRiskOnInitialBase)
      soft+="InpRiskOnInitialBase=false compounds on the live balance; the validated profile is "
            "fixed-fractional on the initial balance, and compounding carries a deeper "
            "peak-relative drawdown (~22.6% vs ~11.7%); ";
   if(!InpBlockFridayLate)
      soft+="InpBlockFridayLate=false allows entries that carry a fresh position into the weekend "
            "gap, which the validation excluded; ";
   if(InpFridayCutoffHour!=21)
      soft+=StringFormat("InpFridayCutoffHour=%d differs from the validated 21 (a SERVER hour); ",
                         InpFridayCutoffHour);
   if(InpSizingBaseOverride>0.0 && g_initial_balance>0.0
      && InpSizingBaseOverride>g_initial_balance*1.001)
      soft+=StringFormat("InpSizingBaseOverride=%.2f EXCEEDS the actual initial balance %.2f - "
                         "every position would be sized for money that is not there, an over-risk "
                         "of %.0f%%; ",InpSizingBaseOverride,g_initial_balance,
                         (InpSizingBaseOverride/g_initial_balance-1.0)*100.0);

   if(hard!="")
      PrintFormat("[ERROR] FROZEN PARAMETERS HAVE BEEN RETUNED and no longer describe the "
                  "validated strategy: %s. InpValidationReleaseId=\"%s\" is meaningless while "
                  "these differ - the published expectancy, drawdown, margin and minimum-balance "
                  "figures DO NOT APPLY. Restore the validated values or re-run the whole "
                  "validation. Halting.",hard,InpValidationReleaseId);
   if(soft!="")
      PrintFormat("[WARN] settings differ from the configuration the published figures were "
                  "measured on: %s. The strategy logic is unchanged, but the quoted numbers no "
                  "longer describe this account.",soft);
   return hard;
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   GeminiROIInit();

   trade.SetExpertMagicNumber((ulong)MAGIC_FIVE_V1);
   trade.SetDeviationInPoints(InpMaxDeviationPoints);
   trade.SetAsyncMode(false);

   // CTrade has no per-symbol filling helper; pick a mode the broker advertises.
   trade.SetTypeFilling(FillingModeFor(_Symbol));
   CheckServerOffset();
   g_initial_balance=AccountInfoDouble(ACCOUNT_BALANCE);

   // Frozen-parameter verification. Must run after g_initial_balance is read, because the
   // InpSizingBaseOverride check compares against it. A drift in the strategy-defining
   // parameters halts: the EA would otherwise trade an unvalidated strategy while still
   // printing the validated release id. Halt() flattens (InpCloseAllOnHalt), which is the
   // correct complement - ProcessOnce returns early once halted, so leaving positions open
   // would strand them without timeout or breaker management.
   if(CheckFrozenParameters()!="")
     {
      Halt("frozen strategy parameters were retuned - see the [ERROR] above");
      return INIT_PARAMETERS_INCORRECT;
     }

   // Netting vs hedging decides whether this EA can reproduce the validated numbers at all.
   g_netting=((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)
              ==ACCOUNT_MARGIN_MODE_RETAIL_NETTING);
   if(g_netting)
      PrintFormat("[WARN] account margin mode is NETTING: only one position per symbol is "
                  "possible. Stacked entries on a symbol would MERGE and overwrite the open "
                  "position's SL/TP, destroying the first trade's stop, so this EA skips a "
                  "signal when it already holds that symbol. That forgoes about 13%% of "
                  "signals; on held-out TEST the profile becomes roughly +10.4%%/month with "
                  "an 11.9%% max drawdown instead of +12.6%%/month and 11.7%%. The validated "
                  "figures assume HEDGING mode. Switch the account to hedging to get them.");
   else
      Print("[INIT] account margin mode is HEDGING - independent positions, matches the validation");

   string raw=InpUseAllEleven
      ? "EURUSD,GBPUSD,EURGBP,AUDUSD,NZDUSD,USDCAD,USDCHF,USDJPY,EURJPY,GBPJPY,XAUUSD"
      : InpSymbols;
   const int n=StringSplit(raw,',',g_symbols);
   if(n<=0) { Halt("no symbols configured"); return INIT_PARAMETERS_INCORRECT; }

   ArrayResize(g_last_bar,n);
   int resolved_count=0;
   for(int i=0;i<n;i++)
     {
      string s=g_symbols[i];
      StringTrimLeft(s); StringTrimRight(s);
      string actual="";
      if(!ResolveSymbol(s,actual))
        {
         // Leave the slot empty rather than keeping a name that cannot trade: an unresolved
         // symbol must never reach EvaluateSymbol or FindSymbol.
         PrintFormat("[ERROR] symbol %s does not exist on this account under any plausible "
                     "suffix - it will NOT be traded. Check InpSymbols against Market Watch.",s);
         g_symbols[i]="";
         g_last_bar[i]=0;
         continue;
        }
      if(actual!=s)
         PrintFormat("[INIT] %s resolved to this broker's symbol '%s'",s,actual);
      g_symbols[i]=actual;
      if(!SymbolSelect(actual,true))
         PrintFormat("[WARN] SymbolSelect failed for %s",actual);
      g_last_bar[i]=0;
      resolved_count++;
     }
   if(resolved_count==0)
     {
      Halt("no configured symbol could be resolved on this account");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(resolved_count<n)
      PrintFormat("[WARN] only %d of %d configured symbols resolved - the EA will trade a "
                  "SUBSET of the validated universe, so realised results will not match the "
                  "published figures",resolved_count,n);

   // The EA watches up to 11 symbols but OnTick only fires on ticks for the CHART
   // symbol. A pair whose bar opens while the chart symbol is quiet would not be
   // evaluated until the chart symbol next ticks - late entries, or missed signals.
   // A 1-second timer makes evaluation independent of which symbol is ticking.
   EventSetTimer(1);

   RecomputeDayState(TimeCurrent());
   PrintFormat("[INIT] server-day state: realised R %+.2f, trades %d, locked=%s",
               g_day_net_r,g_day_trades,g_day_locked?"true":"false");

   if(Authorised())
      Print("[INIT] order submission ENABLED - all gates true");
   else
      PrintFormat("[INIT] order submission DISABLED - first closed gate: %s. Signals are still "
                  "logged; nothing is sent.",FirstClosedGate());

   PrintFormat("[INIT] release=%s symbols=%d risk=%.2f%% base=%.2f targetR=%.1f hold=%dh comm=$%.2f/lot RT",
               InpValidationReleaseId,n,InpRiskPercent,SizingBase(),InpTargetR,InpMaxHoldHours,
               InpCommissionPerLotRT);
   // InpCommissionPerLotRT is not a reporting input - it is inside LossPerLot(), so it sets
   // every position size. Leaving it at the $7.00 default on a broker that charges less
   // under-sizes (FXCC's $0 commission -> lots 6.5-12.1% too small, realised risk 0.439-
   // 0.468% instead of 0.500%); on a broker that charges MORE it over-sizes past the risk
   // mandate, which is the dangerous direction. Print it next to the sizing base so the
   // mismatch is visible in the first log line instead of in the fills.
   if(InpCommissionPerLotRT<0.0)
      PrintFormat("[WARN] InpCommissionPerLotRT=%.2f is negative - LossPerLot would understate "
                  "the loss per lot and OVER-size every position. Set it to your broker's "
                  "actual round-turn commission.",InpCommissionPerLotRT);
   return INIT_SUCCEEDED;
  }

double SizingBase()
  {
   // The override pins a FIXED base; it only makes sense in fixed-fractional mode.
   // Honouring it while compounding would silently disable compounding.
   if(InpRiskOnInitialBase)
      return InpSizingBaseOverride>0.0 ? InpSizingBaseOverride : g_initial_balance;
   return AccountInfoDouble(ACCOUNT_BALANCE);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   Comment("");
  }

//+------------------------------------------------------------------+
//| Manage open positions: enforce the 96h timeout                    |
//+------------------------------------------------------------------+
void ManageTimeouts(const datetime now)
  {
   const long max_hold=(long)InpMaxHoldHours*3600;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      const ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      const long m=PositionGetInteger(POSITION_MAGIC);
      if(m!=MAGIC_FIVE_V1 && m!=MAGIC_FIVE_V2 && m!=MAGIC_FIVE_V3 && m!=MAGIC_FIVE_V4) continue;
      const string sym=PositionGetString(POSITION_SYMBOL);
      if(FindSymbol(sym)<0) continue;
      const datetime opened=(datetime)PositionGetInteger(POSITION_TIME);
      if((long)(now-opened)>=max_hold)
        {
         PrintFormat("[TIMEOUT] %s ticket=%I64u magic=%d held %dh - closing at market",
                     sym,tk,m,(int)((now-opened)/3600));
         CloseOwnPosition(tk,sym,"96h max-hold timeout");
        }
     }
  }

void RecomputeDayState(const datetime now)
  {
   const int dk=ServerDayKey(now);
   const datetime day_start=(datetime)((long)dk*86400L);

   if(dk!=g_day_key)
     {
      if(g_day_key!=-1 && InpQualifyingDays>0)
        {
         const double pnl=EquityNow()-g_day_start_equity;
         if(pnl>=InpQualifyingDayProfit) g_qualifying_days++;
        }
      g_day_key=dk;
      g_day_start_equity=EquityNow();
      g_day_trades=0;
      g_day_locked=false;
      for(int v=0;v<4;v++)
        {
         g_v_day_trades[v]=0;
         g_v_day_net_r[v]=0.0;
         g_v_day_locked[v]=false;
        }
     }

   const double rc=SizingBase()*InpRiskPercent/100.0;
   long magics[4] = {MAGIC_FIVE_V1, MAGIC_FIVE_V2, MAGIC_FIVE_V3, MAGIC_FIVE_V4};

   if(rc>0.0)
     {
      HistorySelect(day_start,now+1);
      const int total=HistoryDealsTotal();
      double total_net=0.0;
      int total_entries=0;

      for(int v=0; v<4; v++)
        {
         double v_net=0.0;
         int v_entries=0;
         long m = magics[v];

         for(int i=0;i<total;i++)
           {
            const ulong dt=HistoryDealGetTicket(i);
            if(dt==0) continue;
            if(HistoryDealGetInteger(dt,DEAL_MAGIC)!=m) continue;
            if(FindSymbol(HistoryDealGetString(dt,DEAL_SYMBOL))<0) continue;
            const long ek=HistoryDealGetInteger(dt,DEAL_ENTRY);
            if(ek==DEAL_ENTRY_IN) { v_entries++; continue; }
            if(ek!=DEAL_ENTRY_OUT && ek!=DEAL_ENTRY_OUT_BY) continue;
            v_net+=(HistoryDealGetDouble(dt,DEAL_PROFIT)
                 +HistoryDealGetDouble(dt,DEAL_SWAP)
                 +HistoryDealGetDouble(dt,DEAL_COMMISSION))/rc;
           }
         g_v_day_net_r[v]=v_net;
         if(v_entries>g_v_day_trades[v]) g_v_day_trades[v]=v_entries;
         if(InpDailyBreakerR>0.0 && g_v_day_net_r[v]<=-InpDailyBreakerR) g_v_day_locked[v]=true;
         total_net+=v_net;
         total_entries+=g_v_day_trades[v];
        }
      g_day_net_r=total_net;
      g_day_trades=total_entries;
      if(InpDailyBreakerR>0.0 && g_day_net_r<=-InpDailyBreakerR) g_day_locked=true;
     }
  }

//+------------------------------------------------------------------+
//| Evaluate the just-closed M5 bar for one symbol                    |
//+------------------------------------------------------------------+
void EvaluateSymbol(const int idx,const datetime now)
  {
   const string sym=g_symbols[idx];
   if(sym=="") return;                                  // unresolved at init
   if(SymbolInfoInteger(sym,SYMBOL_SELECT)!=1) return;

   const datetime bar_time=(datetime)SeriesInfoInteger(sym,InpTimeframe,SERIES_LASTBAR_DATE);
   if(bar_time==g_last_bar[idx]) return;      // this bar already evaluated

   // Do NOT mark the bar processed until the data is actually in hand. Marking it first
   // meant a single failed CopyRates (history not yet synced for this symbol) permanently
   // discarded that bar's signal.
   MqlRates b[];
   ArraySetAsSeries(b,true);
   if(CopyRates(sym,InpTimeframe,1,1,b)!=1) return;   // retry next tick/timer
   double atr=0.0;
   if(!SimpleAtrBefore(sym,1,atr)) return;            // retry next tick/timer
   g_last_bar[idx]=bar_time;                          // data confirmed - commit the bar

   // Fidelity guard: the whole validation rests on filling at the OPEN of the next bar.
   // If we are evaluating this bar long after it opened, that assumption is broken and the
   // trade would not match the backtested distribution. Skip rather than enter late.
   if((long)(now-bar_time)>InpMaxEntryLagSeconds)
     {
      PrintFormat("[SKIP] %s bar opened %ds ago (> %ds lag limit) - entry would not match the validated fill",
                  sym,(int)(now-bar_time),InpMaxEntryLagSeconds);
      return;
     }

   const double o=b[0].open, l=b[0].low, c=b[0].close;

   const double body=MathAbs(c-o);
   if(body<=InpBodyAtrMultiple*atr) return;   // not an extreme bar
   if(c>o) return;                            // LONG ONLY - fade sell-offs, not rallies

   MqlTick tick;
   if(!SymbolInfoTick(sym,tick)) return;
   const double entry=tick.ask;
   if(entry<=0.0) return;

   const int digits=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   const double sl=NormalizeDouble(l-InpStopAtrMultiple*atr,digits);
   const double dist=entry-sl;
   if(dist<=0.0)
     {
      PrintFormat("[SKIP] %s broken geometry: entry %.5f <= stop %.5f",sym,entry,sl);
      return;
     }
   if(dist<InpMinStopAtrMultiple*atr)
     {
      PrintFormat("[SKIP] %s degenerate stop: distance %.5f < %.2f x ATR (%.5f)",sym,dist,InpMinStopAtrMultiple,atr);
      return;
     }
   const double tp=NormalizeDouble(entry+InpTargetR*dist,digits);

   if(InpBlockFridayLate)
     {
      MqlDateTime srv;
      TimeToStruct(now,srv);
      if(srv.day_of_week==5 && srv.hour>=InpFridayCutoffHour) { g_day_locked=true; return; }
     }
   if(g_day_locked) return;
   if(g_target_reached) return;

   const double risk_cash=SizingBase()*InpRiskPercent/100.0;
   const double loss_per_lot=LossPerLot(sym,dist);
   if(loss_per_lot<=0.0) return;
   const double base_lots=NormaliseLots(sym,risk_cash/loss_per_lot);
   if(base_lots<=0.0) return;

   double need=0.0;
   if(!OrderCalcMargin(ORDER_TYPE_BUY,sym,base_lots,entry,need)) return;
   const double free=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(need>free*0.90) return;

   string why="";
   if(!SymbolTradable(sym,why)) return;

   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
   double spread = ask - bid;
   double min_dist = MathMax(StopsLevelPrice(sym), spread) + 3.0 * pt;
   double final_sl = sl;
   double final_tp = tp;
   if(final_sl > 0.0)
     {
      if(final_sl > bid - min_dist) final_sl = bid - min_dist;
      final_sl = NormalizeDouble(final_sl, digits);
     }
   if(final_tp > 0.0)
     {
      if(final_tp < bid + min_dist) final_tp = bid + min_dist;
      final_tp = NormalizeDouble(final_tp, digits);
     }

   // --- Multi-Version Dispatch (V1..V4) ---
   long magics[4] = {MAGIC_FIVE_V1, MAGIC_FIVE_V2, MAGIC_FIVE_V3, MAGIC_FIVE_V4};
   bool runs[4]   = {InpRun_V1, InpRun_V2, InpRun_V3, InpRun_V4};

   for(int v=1; v<=4; v++)
     {
      if(!runs[v-1]) continue;
      long magic = magics[v-1];

      if(g_v_day_locked[v-1]) continue;
      if(InpMaxTradesPerDay<99 && g_v_day_trades[v-1]>=InpMaxTradesPerDay) continue;
      if(InpMaxConcurrent<99 && CountOpen(magic)>=InpMaxConcurrent) continue;
      if(PositionOpenOn(sym, magic)) continue;

      // Version-specific quantitative filters
      if(v >= 2)
        {
         if(AInpEnableVolCapitulation && !GeminiAlpha_VolumeCapitulation(sym)) continue;
        }
      if(v >= 3)
        {
         if(!GeminiMeta_RequestPortfolioSlot(magic, sym, 1.0)) continue;
        }
      if(v == 4)
        {
         if(!GeminiV4_MacroGuard(sym, ORDER_TYPE_BUY)) continue;
        }

      // Sizing
      double lots = base_lots;
      if(v == 4)
        {
         lots = NormaliseLots(sym, base_lots * GeminiV4_EquityCurveSizing(magic) * GeminiV4_FVG_Score(sym, ORDER_TYPE_BUY));
         if(lots <= 0.0) lots = base_lots;
        }

      PrintFormat("[SIGNAL V%d] %s LONG body=%.5f atr=%.5f entry=%.5f sl=%.5f tp=%.5f lots=%.2f magic=%d",
                  v, sym, body, atr, entry, final_sl, final_tp, lots, magic);

      if(!Authorised())
        {
         PrintFormat("[DRY-RUN V%d] order submission disabled (%s) - signal logged only", v, FirstClosedGate());
         continue;
        }

      trade.SetExpertMagicNumber(magic);
      ENUM_ORDER_TYPE_FILLING fill = FillingModeFor(sym);
      trade.SetTypeFilling(fill);

      for(int attempt=0; attempt<3; attempt++)
        {
         const bool sent=trade.Buy(lots, sym, 0.0, final_sl, final_tp, StringFormat("M5EX_V%d %s", v, sym));
         const uint rc=trade.ResultRetcode();
         if(sent && (rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_DONE_PARTIAL || rc==TRADE_RETCODE_PLACED))
           {
            g_v_day_trades[v-1]++;
            g_daystate_dirty=true;
            PrintFormat("[FILLED V%d] %s %.2f lots retcode=%u order=%I64u magic=%d",
                        v, sym, lots, rc, trade.ResultOrder(), magic);
            break;
           }
         if(rc==TRADE_RETCODE_INVALID_FILL)
           {
            const int nxt=NextFillingMode(fill);
            if(nxt<0) break;
            fill=(ENUM_ORDER_TYPE_FILLING)nxt;
            trade.SetTypeFilling(fill);
            continue;
           }
         break;
        }
     }
  }

//+------------------------------------------------------------------+
//| Prop-challenge hard stops                                         |
//+------------------------------------------------------------------+
void CheckHardStops()
  {
   // Prop mode: once the target is met the challenge is won, so carrying further risk is
   // pointless. Latched, because g_day_locked is cleared at every server midnight and would
   // otherwise let the EA start trading again the next day on an already-passed account.
   // If a qualifying-day requirement is configured, do NOT stand down until it is also met -
   // flattening early would forfeit days still needed to pass.
   if(!g_target_reached && InpProfitTarget>0.0 && EquityNow()>=InpProfitTarget)
     {
      const bool quals_ok=(InpQualifyingDays<=0 || g_qualifying_days>=InpQualifyingDays);
      if(quals_ok)
        {
         g_target_reached=true;
         PrintFormat("[TARGET] equity %.2f >= target %.2f with %d/%d qualifying days - "
                     "flattening and standing down for good",
                     EquityNow(),InpProfitTarget,g_qualifying_days,InpQualifyingDays);
         FlattenOwnPositions("profit target and qualifying days reached");
        }
      else
         PrintFormat("[TARGET] equity %.2f >= target %.2f but only %d/%d qualifying days - "
                     "holding, still trading",
                     EquityNow(),InpProfitTarget,g_qualifying_days,InpQualifyingDays);
     }
   if(InpEquityFloor>0.0 && EquityNow()<=InpEquityFloor)
      Halt(StringFormat("equity %.2f breached floor %.2f",EquityNow(),InpEquityFloor));
   if(InpDailyLossLimitPct>0.0 && g_day_start_equity>0.0)
     {
      const double day_pnl=EquityNow()-g_day_start_equity;
      const double limit=-(g_day_start_equity*InpDailyLossLimitPct/100.0);
      if(day_pnl<=limit) g_day_locked=true;
     }
  }

//+------------------------------------------------------------------+
void ProcessOnce()
  {
   if(g_halted)
     {
      Comment("HALTED: ",g_halt_reason);
      return;
     }
   const datetime now=TimeCurrent();
   // RecomputeDayState() does HistorySelect() plus a loop over every deal in the server day.
   // OnTick can fire hundreds of times a second on an active symbol, and OnTimer adds one more
   // per second, so running it unconditionally means hundreds of full history scans a second -
   // enough to starve the very bar-open evaluation the entry-lag guard depends on. TimeCurrent()
   // has one-second granularity, so gating on it throttles to one scan per second, and the
   // dirty flag forces an immediate rescan after a fill so the -3R breaker never lags.
   if(g_daystate_dirty || now!=g_last_daystate)
     {
      RecomputeDayState(now);
      g_last_daystate=now;
      g_daystate_dirty=false;
     }
   ManageTimeouts(now);
   CheckHardStops();

   for(int i=0;i<ArraySize(g_symbols);i++) EvaluateSymbol(i,now);

   Comment(StringFormat("M5_EXHAUST  %s\n equity %.2f  day R %+.2f  day trades %d  open %d  qual days %d%s",
           Authorised()?"LIVE-AUTHORISED":"DRY-RUN (gates closed)",
           EquityNow(),g_day_net_r,g_day_trades,CountOpen(),g_qualifying_days,
           g_day_locked?"\n DAY LOCKED":""));
  }

//+------------------------------------------------------------------+
//| OnTick fires only for the chart symbol; the timer covers the rest |
//+------------------------------------------------------------------+
void OnTick()  {
   if(InpRun_V1) GeminiROITick(MAGIC_FIVE_V1);
   if(InpRun_V2) GeminiROITick(MAGIC_FIVE_V2);
   if(InpRun_V3) { GeminiROITick(MAGIC_FIVE_V3); GeminiMeta_ManageRunners(MAGIC_FIVE_V3); }
   if(InpRun_V4) { GeminiROITick(MAGIC_FIVE_V4); GeminiMeta_ManageRunners(MAGIC_FIVE_V4); }
   ProcessOnce();
}

void OnTimer() {
   if(InpRun_V1) GeminiROITick(MAGIC_FIVE_V1);
   if(InpRun_V2) GeminiROITick(MAGIC_FIVE_V2);
   if(InpRun_V3) { GeminiROITick(MAGIC_FIVE_V3); GeminiMeta_ManageRunners(MAGIC_FIVE_V3); }
   if(InpRun_V4) { GeminiROITick(MAGIC_FIVE_V4); GeminiMeta_ManageRunners(MAGIC_FIVE_V4); }
   ProcessOnce();
}
//+------------------------------------------------------------------+






