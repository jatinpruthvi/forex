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

//+------------------------------------------------------------------+
//| Inputs - authorisation (repo convention: all default to false)    |
//+------------------------------------------------------------------+
input group "=== AUTHORISATION - every flag must be true to place an order ==="
input bool   InpEnableOrderSubmission   = false;   // master switch
input string InpValidationReleaseId     = "LOCKED";// must equal InpRequiredReleaseId
input string InpRequiredReleaseId       = "M5_EXHAUST_2026_09";
input bool   InpBacktestGatePassed      = false;   // findings_phase2_speed.md Part A/B reviewed
input bool   InpOutOfSampleGatePassed   = false;   // held-out TEST result understood
input bool   InpSwapCostGatePassed      = false;   // broker swap table checked for all symbols
input bool   InpMarginGatePassed        = false;   // leverage verified (see README table)
input bool   InpForwardDemoGatePassed   = false;   // demo run through one full losing streak
input bool   InpExplicitUserApproval    = false;   // you accept a ~16-23% peak-relative drawdown
input long   InpAuthorizedLogin         = 0;       // 0 = any login
input string InpExpectedAccountCurrency = "USD";
input int    InpExpectedServerUtcOffsetHours = 3;   // repo convention: broker server is UTC+3
input long   InpMagic                   = 26091501;

input group "=== Universe (TRAIN-selected 8; see README before changing) ==="
input string InpSymbols = "EURGBP,AUDUSD,NZDUSD,USDCAD,USDCHF,EURJPY,GBPJPY,XAUUSD";
input bool   InpUseAllEleven = false;   // true = also trade EURUSD,GBPUSD,USDJPY

input group "=== Frozen strategy parameters - DO NOT RETUNE ==="
input double InpBodyAtrMultiple   = 4.0;    // trigger: body > this x ATR
input int    InpAtrPeriod         = 14;     // simple mean of true range, prior bars
input double InpStopAtrMultiple   = 2.0;    // stop = signal low - this x ATR
input double InpTargetR           = 10.0;   // target = entry + this x risk distance
input int    InpMaxHoldHours      = 96;     // timeout, then market close
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M5;

input group "=== Execution ==="
input int    InpMaxDeviationPoints= 20;     // max slippage accepted on a market order
input bool   InpCloseAllOnHalt    = true;   // flatten this EA's positions when it halts

input group "=== Risk ==="
input double InpRiskPercent       = 0.50;   // % of sizing base per trade
input bool   InpRiskOnInitialBase = true;   // true = fixed fractional (validated); false = compound
input double InpSizingBaseOverride= 0.0;    // >0 pins the base (prop: 2500). 0 = use initial balance
input double InpDailyBreakerR     = 3.0;    // stop opening after this many net losing R today
input int    InpMaxConcurrent     = 99;     // 99 = take every signal (validated best, Part B)
input int    InpMaxTradesPerDay   = 99;
input double InpCommissionPerLotRT= 7.0;    // $ round turn, used in lot sizing
input bool   InpBlockFridayLate   = true;   // no new entries after Fri 21:00 server

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
string         g_halt_reason        = "";
int            g_server_utc_offset_s= 0;

//+------------------------------------------------------------------+
//| Pick an order-filling mode the broker advertises for this symbol  |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING FillingModeFor(const string sym)
  {
   const long modes=SymbolInfoInteger(sym,SYMBOL_FILLING_MODE);
   if((modes & SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
   if((modes & SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
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
//| Close every position this EA owns                                 |
//+------------------------------------------------------------------+
void FlattenOwnPositions(const string reason)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      const ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      if(FindSymbol(PositionGetString(POSITION_SYMBOL))<0) continue;
      PrintFormat("[FLATTEN] %s ticket=%I64u (%s)",PositionGetString(POSITION_SYMBOL),tk,reason);
      if(Authorised()) trade.PositionClose(tk);
     }
  }

void Halt(const string reason)
  {
   if(g_halted) return;
   g_halted=true;
   g_halt_reason=reason;
   PrintFormat("[HALT] %s",reason);
   if(InpCloseAllOnHalt) FlattenOwnPositions(reason);
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
   const double tick_val =SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
   if(tick_size<=0.0 || tick_val<=0.0) return -1.0;
   const double px_loss=(distance/tick_size)*tick_val;
   return px_loss+InpCommissionPerLotRT;
  }

double NormaliseLots(const string sym,double lots)
  {
   const double step=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
   const double vmin=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   const double vmax=SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
   if(step<=0.0) return 0.0;
   lots=MathFloor(lots/step)*step;
   if(lots<vmin) return 0.0;
   if(lots>vmax) lots=vmax;
   return lots;
  }

int ServerDayKey(const datetime t)
  {
   return (int)((t+g_server_utc_offset_s)/86400);
  }

int CountOpen()
  {
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      const ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      if(FindSymbol(PositionGetString(POSITION_SYMBOL))<0) continue;
      n++;
     }
   return n;
  }

double EquityNow() { return AccountInfoDouble(ACCOUNT_EQUITY); }

//+------------------------------------------------------------------+
void RollDayIfNeeded(const datetime now)
  {
   const int dk=ServerDayKey(now);
   if(dk==g_day_key) return;
   if(g_day_key!=-1)
     {
      // settle the finished day's qualifying-day count
      const double pnl=EquityNow()-g_day_start_equity;
      if(InpQualifyingDays>0 && pnl>=InpQualifyingDayProfit) g_qualifying_days++;
     }
   g_day_key=dk;
   g_day_start_equity=EquityNow();
   g_day_net_r=0.0;
   g_day_trades=0;
   g_day_locked=false;
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber((ulong)InpMagic);
   trade.SetDeviationInPoints(InpMaxDeviationPoints);
   trade.SetAsyncMode(false);

   g_server_utc_offset_s=InpExpectedServerUtcOffsetHours*3600;
   // CTrade has no per-symbol filling helper; pick a mode the broker advertises.
   trade.SetTypeFilling(FillingModeFor(_Symbol));
   g_initial_balance=AccountInfoDouble(ACCOUNT_BALANCE);

   string raw=InpUseAllEleven
      ? "EURUSD,GBPUSD,EURGBP,AUDUSD,NZDUSD,USDCAD,USDCHF,USDJPY,EURJPY,GBPJPY,XAUUSD"
      : InpSymbols;
   const int n=StringSplit(raw,',',g_symbols);
   if(n<=0) { Halt("no symbols configured"); return INIT_PARAMETERS_INCORRECT; }

   ArrayResize(g_last_bar,n);
   for(int i=0;i<n;i++)
     {
      string s=g_symbols[i];
      StringTrimLeft(s); StringTrimRight(s);
      g_symbols[i]=s;
      if(!SymbolSelect(s,true))
        { PrintFormat("[WARN] symbol %s not available on this account - skipped",s); }
      g_last_bar[i]=0;
     }

   if(InpRiskOnInitialBase && InpSizingBaseOverride>0.0)
      g_initial_balance=InpSizingBaseOverride;

   RebuildTodayState();

   if(Authorised())
      Print("[INIT] order submission ENABLED - all gates true");
   else
      Print("[INIT] order submission DISABLED (gates not satisfied). Analysis/signals only.");

   PrintFormat("[INIT] release=%s symbols=%d risk=%.2f%% base=%.2f targetR=%.1f hold=%dh",
               InpValidationReleaseId,n,InpRiskPercent,SizingBase(),InpTargetR,InpMaxHoldHours);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Reconstruct today's realised R and trade count from history so a  |
//| mid-day restart does not silently reset the -3R daily breaker.    |
//+------------------------------------------------------------------+
void RebuildTodayState()
  {
   const datetime now=TimeCurrent();
   g_day_key=ServerDayKey(now);
   g_day_start_equity=EquityNow();
   g_day_net_r=0.0;
   g_day_trades=0;
   g_day_locked=false;

   const double rc=SizingBase()*InpRiskPercent/100.0;
   if(rc<=0.0) return;

   const datetime day_start=(datetime)(g_day_key*86400)-g_server_utc_offset_s;
   HistorySelect(day_start,now+1);
   const int total=HistoryDealsTotal();
   for(int i=0;i<total;i++)
     {
      const ulong dt=HistoryDealGetTicket(i);
      if(dt==0) continue;
      if(HistoryDealGetInteger(dt,DEAL_MAGIC)!=InpMagic) continue;
      if(FindSymbol(HistoryDealGetString(dt,DEAL_SYMBOL))<0) continue;
      const long ek=HistoryDealGetInteger(dt,DEAL_ENTRY);
      if(ek==DEAL_ENTRY_IN) { g_day_trades++; continue; }
      if(ek!=DEAL_ENTRY_OUT && ek!=DEAL_ENTRY_OUT_BY) continue;
      const double profit=HistoryDealGetDouble(dt,DEAL_PROFIT)
                         +HistoryDealGetDouble(dt,DEAL_SWAP)
                         +HistoryDealGetDouble(dt,DEAL_COMMISSION);
      g_day_net_r+=profit/rc;
     }
   if(InpDailyBreakerR>0.0 && g_day_net_r<=-InpDailyBreakerR) g_day_locked=true;
   PrintFormat("[INIT] restored server-day state: realised R %+.2f, trades %d, locked=%s",
               g_day_net_r,g_day_trades,g_day_locked?"true":"false");
  }

double SizingBase()
  {
   if(InpSizingBaseOverride>0.0) return InpSizingBaseOverride;
   if(InpRiskOnInitialBase)      return g_initial_balance;
   return AccountInfoDouble(ACCOUNT_BALANCE);
  }

void OnDeinit(const int reason)
  {
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
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      const string sym=PositionGetString(POSITION_SYMBOL);
      if(FindSymbol(sym)<0) continue;
      const datetime opened=(datetime)PositionGetInteger(POSITION_TIME);
      if((long)(now-opened)>=max_hold)
        {
         PrintFormat("[TIMEOUT] %s ticket=%I64u held %dh - closing at market",
                     sym,tk,(int)((now-opened)/3600));
         if(Authorised()) trade.PositionClose(tk);
        }
     }
  }

//+------------------------------------------------------------------+
//| Track realised R for the daily breaker                            |
//+------------------------------------------------------------------+
void ScanClosedDeals()
  {
   static datetime last_scan=0;
   const datetime now=TimeCurrent();
   HistorySelect(last_scan==0?now-86400:last_scan,now+1);
   const int total=HistoryDealsTotal();
   for(int i=0;i<total;i++)
     {
      const ulong dt=HistoryDealGetTicket(i);
      if(dt==0) continue;
      if(HistoryDealGetInteger(dt,DEAL_MAGIC)!=InpMagic) continue;
      if(FindSymbol(HistoryDealGetString(dt,DEAL_SYMBOL))<0) continue;
      const long ek=HistoryDealGetInteger(dt,DEAL_ENTRY);
      if(ek!=DEAL_ENTRY_OUT && ek!=DEAL_ENTRY_OUT_BY) continue;
      const double profit=HistoryDealGetDouble(dt,DEAL_PROFIT)
                         +HistoryDealGetDouble(dt,DEAL_SWAP)
                         +HistoryDealGetDouble(dt,DEAL_COMMISSION);
      const double base=SizingBase();
      const double rc=base*InpRiskPercent/100.0;
      if(rc>0.0) g_day_net_r+=profit/rc;
     }
   last_scan=now;
  }

//+------------------------------------------------------------------+
//| Evaluate the just-closed M5 bar for one symbol                    |
//+------------------------------------------------------------------+
void EvaluateSymbol(const int idx,const datetime now)
  {
   const string sym=g_symbols[idx];
   if(SymbolInfoInteger(sym,SYMBOL_SELECT)!=1) return;

   const datetime bar_time=(datetime)SeriesInfoInteger(sym,InpTimeframe,SERIES_LASTBAR_DATE);
   if(bar_time==g_last_bar[idx]) return;      // already processed this bar
   g_last_bar[idx]=bar_time;

   MqlRates b[];
   ArraySetAsSeries(b,true);
   if(CopyRates(sym,InpTimeframe,1,1,b)!=1) return;   // the just-closed bar (shift 1)
   const double o=b[0].open, l=b[0].low, c=b[0].close;

   double atr=0.0;
   if(!SimpleAtrBefore(sym,1,atr)) return;

   const double body=MathAbs(c-o);
   if(body<=InpBodyAtrMultiple*atr) return;   // not an extreme bar
   if(c>o) return;                            // LONG ONLY - fade sell-offs, not rallies

   MqlTick tick;
   if(!SymbolInfoTick(sym,tick)) return;
   const double entry=tick.ask;
   if(entry<=0.0) return;

   const double stop=l-InpStopAtrMultiple*atr;
   const double dist=entry-stop;
   if(dist<=0.0)
     {
      PrintFormat("[SKIP] %s broken geometry: entry %.5f <= stop %.5f",sym,entry,stop);
      return;                                  // matches the backtest's rejection rule
     }
   const double target=entry+InpTargetR*dist;

   // ---- gates that block a new entry ----
   RollDayIfNeeded(now);
   if(g_day_locked) return;
   if(InpMaxConcurrent<99 && CountOpen()>=InpMaxConcurrent) return;
   if(InpMaxTradesPerDay<99 && g_day_trades>=InpMaxTradesPerDay) return;

   if(InpBlockFridayLate)
     {
      MqlDateTime srv;
      TimeToStruct(now+g_server_utc_offset_s,srv);
      if(srv.day_of_week==5 && srv.hour>=21) { g_day_locked=true; return; }
     }
   if(InpDailyBreakerR>0.0 && g_day_net_r<=-InpDailyBreakerR) { g_day_locked=true; return; }
   if(InpProfitTarget>0.0 && EquityNow()>=InpProfitTarget) return;

   // ---- sizing ----
   const double risk_cash=SizingBase()*InpRiskPercent/100.0;
   const double loss_per_lot=LossPerLot(sym,dist);
   if(loss_per_lot<=0.0) { Halt("cannot price stop distance for "+sym); return; }
   const double lots=NormaliseLots(sym,risk_cash/loss_per_lot);
   if(lots<=0.0)
     {
      PrintFormat("[SKIP] %s lot below broker minimum (risk_cash %.2f, loss/lot %.2f)",
                  sym,risk_cash,loss_per_lot);
      return;
     }

   // ---- margin ----
   double need=0.0;
   if(!OrderCalcMargin(ORDER_TYPE_BUY,sym,lots,entry,need))
     { Halt("OrderCalcMargin failed for "+sym); return; }
   const double free=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(need>free*0.90)
     {
      PrintFormat("[SKIP] %s margin %.2f exceeds 90%% of free margin %.2f - reduce leverage or universe",
                  sym,need,free);
      return;
     }

   string why="";
   if(!SymbolTradable(sym,why))
     { PrintFormat("[SKIP] %s not tradable: %s",sym,why); return; }

   const int digits=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   const double sl=NormalizeDouble(stop,digits);
   const double tp=NormalizeDouble(target,digits);

   // Broker minimum stop distance: a 2.0 x ATR stop on a quiet pair can sit inside it,
   // and the order would be rejected. Skip rather than silently widen the stop, because
   // widening changes the risk-per-trade the validation assumed.
   const double min_dist=StopsLevelPrice(sym);
   if(min_dist>0.0)
     {
      if(entry-sl<min_dist)
        { PrintFormat("[SKIP] %s stop distance %.5f is inside broker stops level %.5f",sym,entry-sl,min_dist); return; }
      if(tp-entry<min_dist)
        { PrintFormat("[SKIP] %s target distance %.5f is inside broker stops level %.5f",sym,tp-entry,min_dist); return; }
     }
   trade.SetTypeFilling(FillingModeFor(sym));

   PrintFormat("[SIGNAL] %s LONG body=%.5f atr=%.5f (%.2fx) entry=%.5f sl=%.5f tp=%.5f lots=%.2f risk=$%.2f",
               sym,body,atr,body/atr,entry,sl,tp,lots,risk_cash);

   if(!Authorised())
     {
      Print("[DRY-RUN] order submission disabled - signal logged only");
      return;
     }
   if(trade.Buy(lots,sym,entry,sl,tp,StringFormat("M5EXHAUST %s",sym)))
     {
      g_day_trades++;
      PrintFormat("[FILLED] %s %.2f lots ticket=%I64u",sym,lots,trade.ResultOrder());
     }
   else
      PrintFormat("[ERROR] %s order failed retcode=%d %s",sym,trade.ResultRetcode(),
                  trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| Prop-challenge hard stops                                         |
//+------------------------------------------------------------------+
void CheckHardStops()
  {
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
void OnTick()
  {
   if(g_halted)
     {
      Comment("HALTED: ",g_halt_reason);
      return;
     }
   const datetime now=TimeCurrent();
   RollDayIfNeeded(now);
   ScanClosedDeals();
   ManageTimeouts(now);
   CheckHardStops();

   for(int i=0;i<ArraySize(g_symbols);i++) EvaluateSymbol(i,now);

   Comment(StringFormat("M5_EXHAUST  %s\n equity %.2f  day R %+.2f  day trades %d  open %d  qual days %d%s",
           Authorised()?"LIVE-AUTHORISED":"DRY-RUN (gates closed)",
           EquityNow(),g_day_net_r,g_day_trades,CountOpen(),g_qualifying_days,
           g_day_locked?"\n DAY LOCKED":""));
  }
//+------------------------------------------------------------------+
