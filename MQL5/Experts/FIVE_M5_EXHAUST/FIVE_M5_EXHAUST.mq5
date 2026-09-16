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
input int    InpExpectedServerUtcOffsetHours = 3;   // informational; see OnInit offset check.
                                                    // TimeCurrent() is ALREADY server time, so
                                                    // this is never added to it.
input long   InpMagic                   = 26091501;

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
input double InpCommissionPerLotRT= 7.0;    // $ round turn, used in lot sizing
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
   const double hours=(double)((detected+1800)/3600);      // round to the nearest whole hour
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
int OnInit()
  {
   trade.SetExpertMagicNumber((ulong)InpMagic);
   trade.SetDeviationInPoints(InpMaxDeviationPoints);
   trade.SetAsyncMode(false);

   // CTrade has no per-symbol filling helper; pick a mode the broker advertises.
   trade.SetTypeFilling(FillingModeFor(_Symbol));
   CheckServerOffset();
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
      Print("[INIT] order submission DISABLED (gates not satisfied). Analysis/signals only.");

   PrintFormat("[INIT] release=%s symbols=%d risk=%.2f%% base=%.2f targetR=%.1f hold=%dh",
               InpValidationReleaseId,n,InpRiskPercent,SizingBase(),InpTargetR,InpMaxHoldHours);
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
//| Recompute today's realised R and trade count FROM SCRATCH.        |
//|                                                                    |
//| This is deliberately idempotent. The previous version added each   |
//| closed deal to a running total using a 1-second-granularity        |
//| watermark; because many ticks share one second, the same deals were|
//| re-selected and re-added on every tick, inflating g_day_net_r until|
//| the -3R breaker tripped spuriously and locked out all trading. It  |
//| also mis-attributed deals closed across midnight to the new day,   |
//| because the day rollover ran before the scan.                      |
//|                                                                    |
//| Recomputing from the server-day window fixes both, and makes the   |
//| restart path and the live path the same code.                      |
//+------------------------------------------------------------------+
void RecomputeDayState(const datetime now)
  {
   const int dk=ServerDayKey(now);
   // cast to long before multiplying: day_key*86400 is ~1.73e9 and overflows int32 in 2038
   const datetime day_start=(datetime)((long)dk*86400L);   // server midnight; now is already server time

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
     }

   const double rc=SizingBase()*InpRiskPercent/100.0;
   double net=0.0;
   int    entries=0;
   if(rc>0.0)
     {
      HistorySelect(day_start,now+1);
      const int total=HistoryDealsTotal();
      for(int i=0;i<total;i++)
        {
         const ulong dt=HistoryDealGetTicket(i);
         if(dt==0) continue;
         if(HistoryDealGetInteger(dt,DEAL_MAGIC)!=InpMagic) continue;
         if(FindSymbol(HistoryDealGetString(dt,DEAL_SYMBOL))<0) continue;
         const long ek=HistoryDealGetInteger(dt,DEAL_ENTRY);
         if(ek==DEAL_ENTRY_IN) { entries++; continue; }
         if(ek!=DEAL_ENTRY_OUT && ek!=DEAL_ENTRY_OUT_BY) continue;
         net+=(HistoryDealGetDouble(dt,DEAL_PROFIT)
              +HistoryDealGetDouble(dt,DEAL_SWAP)
              +HistoryDealGetDouble(dt,DEAL_COMMISSION))/rc;
        }
     }
   g_day_net_r=net;
   // Two sources of truth: EvaluateSymbol increments on fill, this recounts from deal
   // history. Deal history can lag a fill by a tick or two, and letting the recount LOWER
   // the counter would let InpMaxTradesPerDay be exceeded. Take the max so it never
   // regresses within a server day (the rollover above resets it legitimately).
   if(entries>g_day_trades) g_day_trades=entries;
   if(InpDailyBreakerR>0.0 && g_day_net_r<=-InpDailyBreakerR) g_day_locked=true;
  }

//+------------------------------------------------------------------+
//| Evaluate the just-closed M5 bar for one symbol                    |
//+------------------------------------------------------------------+
void EvaluateSymbol(const int idx,const datetime now)
  {
   const string sym=g_symbols[idx];
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
   // Normalise the stop FIRST, then size from it. Sizing on the raw stop while sending the
   // normalised one meant the dollars actually at risk differed slightly from InpRiskPercent.
   const double sl=NormalizeDouble(l-InpStopAtrMultiple*atr,digits);
   const double dist=entry-sl;
   if(dist<=0.0)
     {
      PrintFormat("[SKIP] %s broken geometry: entry %.5f <= stop %.5f",sym,entry,sl);
      return;                                  // matches the backtest's rejection rule
     }
   // DEGENERATE-STOP GUARD. dist = (next_open - signal_low) + 2*ATR, so a gap down through
   // the signal bar's low shrinks it - in the data, as far as dist == 0. Because lots are
   // sized as risk_cash / (dist x pip_value + commission), a near-zero stop produces an
   // ENORMOUS position: dist == 0 sizes to 1.78 lots on a $2,500 account with no stop
   // protection at all, and round-turn cost exceeds 1R (cost_R > 1) so the trade cannot
   // win. 25 such signals occur in 4 years and they cluster at the daily roll and the
   // weekend close (20:55-22:00), where the next-bar open is a stale, wide-spread print.
   // Requiring a real stop removes ~3% of signals and every degenerate one.
   if(dist<InpMinStopAtrMultiple*atr)
     {
      PrintFormat("[SKIP] %s degenerate stop: distance %.5f < %.2f x ATR (%.5f) - would size "
                  "an unprotected oversized position",sym,dist,InpMinStopAtrMultiple,atr);
      return;
     }
   const double tp=NormalizeDouble(entry+InpTargetR*dist,digits);

   // ---- gates that block a new entry ----
   // (day rollover and realised-R recompute happen centrally in ProcessOnce)
   if(g_day_locked) return;
   if(InpMaxConcurrent<99 && CountOpen()>=InpMaxConcurrent) return;
   if(InpMaxTradesPerDay<99 && g_day_trades>=InpMaxTradesPerDay) return;

   if(InpBlockFridayLate)
     {
      // `now` is already server time - do NOT shift it. Shifting by +3h made this fire on
      // Friday 18:00-20:59 server and then MISS Friday 21:00-23:59 server entirely, because
      // the shifted time rolls into Saturday (day_of_week 6). That is exactly backwards: it
      // blocked a harmless window and left the pre-close window, where a position would be
      // carried into the weekend gap, wide open.
      MqlDateTime srv;
      TimeToStruct(now,srv);
      if(srv.day_of_week==5 && srv.hour>=InpFridayCutoffHour) { g_day_locked=true; return; }
     }
   if(InpDailyBreakerR>0.0 && g_day_net_r<=-InpDailyBreakerR) { g_day_locked=true; return; }
   if(g_target_reached) return;                     // prop target met - no new risk, ever

   // ---- sizing ----
   const double risk_cash=SizingBase()*InpRiskPercent/100.0;
   const double loss_per_lot=LossPerLot(sym,dist);
   if(loss_per_lot<=0.0)
     {
      // Transient: tick size/value can be unavailable for a moment. Skipping this entry is
      // the right response; halting (and flattening) the whole EA over it is not.
      PrintFormat("[SKIP] %s cannot price stop distance (tick size/value unavailable)",sym);
      return;
     }
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
     { PrintFormat("[SKIP] %s OrderCalcMargin failed",sym); return; }
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
      // Buy() can return true for a request that was merely accepted; confirm the retcode.
      const uint rc=trade.ResultRetcode();
      if(rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_DONE_PARTIAL || rc==TRADE_RETCODE_PLACED)
        {
         g_day_trades++;
         PrintFormat("[FILLED] %s %.2f lots retcode=%u order=%I64u",sym,lots,rc,trade.ResultOrder());
        }
      else
         PrintFormat("[ERROR] %s request accepted but retcode=%u %s",sym,rc,
                     trade.ResultRetcodeDescription());
     }
   else
      PrintFormat("[ERROR] %s order failed retcode=%u %s",sym,trade.ResultRetcode(),
                  trade.ResultRetcodeDescription());
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
   RecomputeDayState(now);
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
void OnTick()  { ProcessOnce(); }
void OnTimer() { ProcessOnce(); }
//+------------------------------------------------------------------+
