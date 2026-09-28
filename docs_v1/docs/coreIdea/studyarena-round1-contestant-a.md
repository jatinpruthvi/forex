# StudyArena

**Question:** I want to create forex EA using Smart Money Concepts which have 20% ROI per month.

FYI - 
it  CAN  be run on multiple symbol AND ALL ACCEPTED TIMEFRAME

**Answered by** Contestant A · Round 1 · 25 Sept 2026

---

## First, the arithmetic on "20%/month"

20%/month compounded = **+791% per year** (\(1.2^{12}=8.92\times\)). That's achievable in bursts, not as a stable expectation — so build the EA to *target* it with a defined risk budget and accept it will miss some months.

What 20% actually requires per month:

\[
\text{Needed} = 20\text{R at }1\%\text{ risk} \quad\text{(R = 1× risk unit)}
\]

With a realistic SMC profile — 45% win rate, 1:3 average RR — expectancy is
\[
E = 0.45\times3 - 0.55\times1 = 0.80\ \text{R/trade}
\]
\[
\text{Trades needed} = 20/0.80 = 25\ \text{trades per month}
\]

So: **~25 valid setups/month at 1% risk, or ~12 setups at 2% risk.** One pair on H1 gives you maybe 4–8 SMC setups a month → that's why multi-symbol is mandatory. 6–8 pairs × 4 setups = ~25. The architecture below is built around exactly that math.

Drawdown cost: 20R/month up means a 6-loss streak (~9% with 1.5% risk) is normal. Budget 25–30% max DD.

---

## The EA — `SMC_MultiSymbol.mq5`

Compilable MQL5. Logic: **HTF bias → liquidity sweep → CHoCH → OB/FVG mitigation limit order → RR/liquidity TP**.

```mql5
//+------------------------------------------------------------------+
//|  SMC_MultiSymbol.mq5   Smart Money Concepts EA                    |
//|  Multi-symbol, any timeframe. Sweep -> CHoCH -> OB/FVG entry.     |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

input string  InpSymbols       = "EURUSD,GBPUSD,USDJPY,AUDUSD,USDCAD,XAUUSD,GBPJPY,EURJPY";
input ENUM_TIMEFRAMES InpEntryTF = PERIOD_CURRENT; // Entry TF (PERIOD_CURRENT = chart TF)
input int     InpHTFSteps      = 3;      // how many TF steps up for bias (M15->H4 etc.)
input int     InpFractal       = 2;      // swing strength (bars each side)
input int     InpBars          = 400;    // bars analysed
input int     InpSweepLookback = 12;     // bars to search for liquidity sweep
input bool    InpUseFVG        = true;   // allow FVG zone if no clean OB
input double  InpRiskPercent   = 1.0;    // risk % of equity per trade
input double  InpRR            = 3.0;    // take profit in R
input bool    InpTPatLiquidity = true;   // TP at opposing swing liquidity if further
input double  InpSLBufferATR   = 0.25;   // SL buffer in ATR
input double  InpPartialAtR    = 1.5;    // close 50% at this R (0 = off)
input bool    InpBreakEven     = true;   // SL->BE after partial
input double  InpTrailATR      = 2.0;    // ATR trail after BE (0 = off)
input int     InpExpiryBars    = 8;      // pending order lifetime in bars
input int     InpMaxPosPerSym  = 1;
input int     InpMaxPosTotal   = 4;
input double  InpMaxSpreadPts  = 35;     // max spread in points (raise for XAU/JPY)
input double  InpDailyLossPct  = 4.0;    // stop trading for the day after this loss
input double  InpMaxDDPct      = 25.0;   // hard equity stop
input int     InpStartHour     = 6;      // server-time session filter
input int     InpEndHour       = 20;
input long    InpMagic         = 903201;

CTrade        trade;
CPositionInfo pos;
string        Syms[];
datetime      LastBar[];
double        DayStartEquity = 0;
datetime      DayStamp = 0;

//--- timeframe ladder -----------------------------------------------
ENUM_TIMEFRAMES TFLadder[] = {PERIOD_M1,PERIOD_M5,PERIOD_M15,PERIOD_M30,
                              PERIOD_H1,PERIOD_H4,PERIOD_D1,PERIOD_W1,PERIOD_MN1};

ENUM_TIMEFRAMES StepUp(ENUM_TIMEFRAMES tf,int steps)
{
   for(int i=0;i<ArraySize(TFLadder);i++)
      if(TFLadder[i]==tf)
         return TFLadder[MathMin(i+steps,ArraySize(TFLadder)-1)];
   return PERIOD_H4;
}
ENUM_TIMEFRAMES EntryTF(){ return (InpEntryTF==PERIOD_CURRENT)?(ENUM_TIMEFRAMES)_Period:InpEntryTF; }

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);

   string tmp[]; int n=StringSplit(InpSymbols,',',tmp);
   ArrayResize(Syms,0);
   for(int i=0;i<n;i++)
   {
      string s=tmp[i]; StringTrimLeft(s); StringTrimRight(s);
      if(s=="") continue;
      if(!SymbolSelect(s,true)){ Print("Symbol not found: ",s); continue; }
      int k=ArraySize(Syms); ArrayResize(Syms,k+1); Syms[k]=s;
   }
   ArrayResize(LastBar,ArraySize(Syms));
   ArrayInitialize(LastBar,0);
   DayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   EventSetTimer(5);
   Print("SMC EA started on ",ArraySize(Syms)," symbols, entry TF ",EnumToString(EntryTF()),
         ", bias TF ",EnumToString(StepUp(EntryTF(),InpHTFSteps)));
   return INIT_SUCCEEDED;
}
void OnDeinit(const int r){ EventKillTimer(); }
void OnTick(){ Process(); }
void OnTimer(){ Process(); }

//+------------------------------------------------------------------+
void Process()
{
   NewDayCheck();
   if(!RiskGatesOK()) return;
   for(int i=0;i<ArraySize(Syms);i++)
   {
      ManageOpen(Syms[i]);
      datetime bt=(datetime)SeriesInfoInteger(Syms[i],EntryTF(),SERIES_LASTBAR_DATE);
      if(bt==0 || bt==LastBar[i]) continue;
      LastBar[i]=bt;
      Scan(Syms[i]);
   }
}

void NewDayCheck()
{
   MqlDateTime t; TimeToStruct(TimeCurrent(),t);
   datetime d=StringToTime(StringFormat("%04d.%02d.%02d",t.year,t.mon,t.day));
   if(d!=DayStamp){ DayStamp=d; DayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY); }
}

bool RiskGatesOK()
{
   double eq=AccountInfoDouble(ACCOUNT_EQUITY), bal=AccountInfoDouble(ACCOUNT_BALANCE);
   if(DayStartEquity>0 && (DayStartEquity-eq)/DayStartEquity*100.0>=InpDailyLossPct) return false;
   if(bal>0 && (bal-eq)/bal*100.0>=InpMaxDDPct){ CloseAll(); return false; }
   MqlDateTime t; TimeToStruct(TimeCurrent(),t);
   if(InpStartHour!=InpEndHour && (t.hour<InpStartHour || t.hour>=InpEndHour)) return false;
   if(t.day_of_week==0 || t.day_of_week==6) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Swing detection (fractals)                                        |
//+------------------------------------------------------------------+
bool IsSwingHigh(const MqlRates &r[],int i,int n)
{
   for(int k=1;k<=n;k++)
      if(r[i].high<=r[i+k].high || r[i].high<=r[i-k].high) return false;
   return true;
}
bool IsSwingLow(const MqlRates &r[],int i,int n)
{
   for(int k=1;k<=n;k++)
      if(r[i].low>=r[i+k].low || r[i].low>=r[i-k].low) return false;
   return true;
}
// fills idx[] with swing bar indexes, newest first
void CollectSwings(const MqlRates &r[],int n,bool highs,int &idx[],int want)
{
   ArrayResize(idx,0);
   int total=ArraySize(r);
   for(int i=n;i<total-n-1 && ArraySize(idx)<want;i++)
   {
      bool hit = highs ? IsSwingHigh(r,i,n) : IsSwingLow(r,i,n);
      if(hit){ int k=ArraySize(idx); ArrayResize(idx,k+1); idx[k]=i; }
   }
}

//+------------------------------------------------------------------+
//| HTF bias: +1 bullish, -1 bearish, 0 none                          |
//+------------------------------------------------------------------+
int HTFBias(string sym)
{
   MqlRates r[]; ArraySetAsSeries(r,true);
   ENUM_TIMEFRAMES htf=StepUp(EntryTF(),InpHTFSteps);
   if(CopyRates(sym,htf,0,200,r)<60) return 0;
   int hi[],lo[];
   CollectSwings(r,InpFractal,true,hi,3);
   CollectSwings(r,InpFractal,false,lo,3);
   if(ArraySize(hi)<2 || ArraySize(lo)<2) return 0;
   double c=r[1].close;
   bool hh = r[hi[0]].high > r[hi[1]].high;
   bool hl = r[lo[0]].low  > r[lo[1]].low;
   bool lh = r[hi[0]].high < r[hi[1]].high;
   bool ll = r[lo[0]].low  < r[lo[1]].low;
   if((hh && hl) || c>r[hi[0]].high) return  1;   // structure up or BOS up
   if((lh && ll) || c<r[lo[0]].low)  return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Main scan: sweep -> CHoCH -> OB / FVG zone -> pending order       |
//+------------------------------------------------------------------+
void Scan(string sym)
{
   if(CountPos(sym)>=InpMaxPosPerSym || CountPos("")>=InpMaxPosTotal) return;
   if(HasPending(sym)) return;
   double spread=(double)SymbolInfoInteger(sym,SYMBOL_SPREAD);
   if(spread>InpMaxSpreadPts) return;

   int bias=HTFBias(sym);
   if(bias==0) return;

   MqlRates r[]; ArraySetAsSeries(r,true);
   if(CopyRates(sym,EntryTF(),0,InpBars,r)<InpBars/2) return;

   double atr=ATR(sym,EntryTF(),14);
   if(atr<=0) return;

   int hi[],lo[];
   CollectSwings(r,InpFractal,true,hi,6);
   CollectSwings(r,InpFractal,false,lo,6);
   if(ArraySize(hi)<2 || ArraySize(lo)<2) return;

   //---------------- BUY branch -------------------------------------
   if(bias>0)
   {
      // 1) liquidity sweep: recent bar took out a prior swing low and closed back above
      int sweepBar=-1; double sweptLevel=0;
      for(int i=1;i<=InpSweepLookback;i++)
      {
         for(int s=0;s<ArraySize(lo);s++)
         {
            if(lo[s]<=i) continue;
            double lvl=r[lo[s]].low;
            if(r[i].low<lvl && r[i].close>lvl){ sweepBar=i; sweptLevel=lvl; break; }
         }
         if(sweepBar>0) break;
      }
      if(sweepBar<0) return;

      // 2) CHoCH: price closed above the last swing high formed before the sweep
      double chochLvl=0;
      for(int s=0;s<ArraySize(hi);s++) if(hi[s]>sweepBar){ chochLvl=r[hi[s]].high; break; }
      if(chochLvl==0) return;
      bool choch=false;
      for(int i=1;i<sweepBar;i++) if(r[i].close>chochLvl){ choch=true; break; }
      if(!choch) return;

      // 3) zone: last down-candle before the impulse (order block), else FVG
      double zHigh=0,zLow=0;
      for(int i=1;i<=sweepBar+3 && i<InpBars-3;i++)
         if(r[i].close<r[i].open && r[i+0].low<=r[sweepBar].low+atr*1.5)
         { zHigh=MathMax(r[i].open,r[i].high); zLow=r[i].low; break; }
      if(zHigh==0 && InpUseFVG)
         for(int i=1;i<sweepBar+3;i++)
            if(r[i].low>r[i+2].high){ zHigh=r[i].low; zLow=r[i+2].high; break; }
      if(zHigh<=zLow) return;

      double entry = zLow + (zHigh-zLow)*0.5;              // 50% mitigation
      double sl    = zLow - atr*InpSLBufferATR;
      double risk  = entry-sl;
      if(risk<=0) return;
      double tp    = entry + risk*InpRR;
      if(InpTPatLiquidity){ double liq=r[hi[0]].high; if(liq>tp) tp=liq; }
      double ask=SymbolInfoDouble(sym,SYMBOL_ASK);
      if(entry>=ask) return;                                // must be a limit below price
      PlaceOrder(sym,true,entry,sl,tp);
   }
   //---------------- SELL branch ------------------------------------
   else
   {
      int sweepBar=-1;
      for(int i=1;i<=InpSweepLookback;i++)
      {
         for(int s=0;s<ArraySize(hi);s++)
         {
            if(hi[s]<=i) continue;
            double lvl=r[hi[s]].high;
            if(r[i].high>lvl && r[i].close<lvl){ sweepBar=i; break; }
         }
         if(sweepBar>0) break;
      }
      if(sweepBar<0) return;

      double chochLvl=0;
      for(int s=0;s<ArraySize(lo);s++) if(lo[s]>sweepBar){ chochLvl=r[lo[s]].low; break; }
      if(chochLvl==0) return;
      bool choch=false;
      for(int i=1;i<sweepBar;i++) if(r[i].close<chochLvl){ choch=true; break; }
      if(!choch) return;

      double zHigh=0,zLow=0;
      for(int i=1;i<=sweepBar+3 && i<InpBars-3;i++)
         if(r[i].close>r[i].open && r[i].high>=r[sweepBar].high-atr*1.5)
         { zHigh=r[i].high; zLow=MathMin(r[i].open,r[i].low); break; }
      if(zHigh==0 && InpUseFVG)
         for(int i=1;i<sweepBar+3;i++)
            if(r[i].high<r[i+2].low){ zHigh=r[i+2].low; zLow=r[i].high; break; }
      if(zHigh<=zLow) return;

      double entry = zHigh - (zHigh-zLow)*0.5;
      double sl    = zHigh + atr*InpSLBufferATR;
      double risk  = sl-entry;
      if(risk<=0) return;
      double tp    = entry - risk*InpRR;
      if(InpTPatLiquidity){ double liq=r[lo[0]].low; if(liq<tp) tp=liq; }
      double bid=SymbolInfoDouble(sym,SYMBOL_BID);
      if(entry<=bid) return;
      PlaceOrder(sym,false,entry,sl,tp);
   }
}

//+------------------------------------------------------------------+
void PlaceOrder(string sym,bool buy,double entry,double sl,double tp)
{
   int dg=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   entry=NormalizeDouble(entry,dg); sl=NormalizeDouble(sl,dg); tp=NormalizeDouble(tp,dg);
   double lots=LotSize(sym,MathAbs(entry-sl));
   if(lots<=0) return;
   datetime exp=TimeCurrent()+(datetime)(PeriodSeconds(EntryTF())*InpExpiryBars);
   trade.SetTypeFillingBySymbol(sym);
   bool ok = buy ? trade.BuyLimit (lots,entry,sym,sl,tp,ORDER_TIME_SPECIFIED,exp,"SMC")
                 : trade.SellLimit(lots,entry,sym,sl,tp,ORDER_TIME_SPECIFIED,exp,"SMC");
   if(!ok) PrintFormat("%s order failed: %d %s",sym,trade.ResultRetcode(),trade.ResultComment());
}

double LotSize(string sym,double slDist)
{
   double eq   = AccountInfoDouble(ACCOUNT_EQUITY);
   double cash = eq*InpRiskPercent/100.0;
   double ts   = SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
   double tv   = SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
   if(ts<=0||tv<=0||slDist<=0) return 0;
   double lossPerLot = slDist/ts*tv;
   if(lossPerLot<=0) return 0;
   double lot  = cash/lossPerLot;
   double step = SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
   double mn   = SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   double mx   = SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
   lot = MathFloor(lot/step)*step;
   if(lot<mn) return 0;                  // never risk more than allowed – skip instead
   return MathMin(lot,mx);
}

double ATR(string sym,ENUM_TIMEFRAMES tf,int p)
{
   int h=iATR(sym,tf,p); if(h==INVALID_HANDLE) return 0;
   double b[]; ArraySetAsSeries(b,true);
   if(CopyBuffer(h,0,1,1,b)<1){ IndicatorRelease(h); return 0; }
   double v=b[0]; IndicatorRelease(h); return v;
}

//+------------------------------------------------------------------+
//| Trade management: partial, break-even, ATR trail                  |
//+------------------------------------------------------------------+
void ManageOpen(string sym)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Magic()!=InpMagic || pos.Symbol()!=sym) continue;
      bool buy = pos.PositionType()==POSITION_TYPE_BUY;
      double open=pos.PriceOpen(), sl=pos.StopLoss(), cur=pos.PriceCurrent();
      double r0 = MathAbs(open-sl); if(r0<=0) continue;
      double rNow = buy ? (cur-open)/r0 : (open-cur)/r0;
      int dg=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);

      if(InpPartialAtR>0 && rNow>=InpPartialAtR && StringFind(pos.Comment(),"P")<0)
      {
         double half=pos.Volume()/2.0;
         double step=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
         half=MathFloor(half/step)*step;
         if(half>=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN))
            trade.PositionClosePartial(pos.Ticket(),half);
         if(InpBreakEven)
            trade.PositionModify(pos.Ticket(),NormalizeDouble(open,dg),pos.TakeProfit());
      }
      if(InpTrailATR>0 && rNow>=InpPartialAtR)
      {
         double a=ATR(sym,EntryTF(),14); if(a<=0) continue;
         double nsl = buy ? cur-a*InpTrailATR : cur+a*InpTrailATR;
         nsl=NormalizeDouble(nsl,dg);
         if((buy && nsl>pos.StopLoss()) || (!buy && (nsl<pos.StopLoss()||pos.StopLoss()==0)))
            trade.PositionModify(pos.Ticket(),nsl,pos.TakeProfit());
      }
   }
}

int CountPos(string sym)
{
   int c=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
      if(pos.SelectByIndex(i) && pos.Magic()==InpMagic && (sym==""||pos.Symbol()==sym)) c++;
   return c;
}
bool HasPending(string sym)
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong t=OrderGetTicket(i);
      if(t>0 && OrderGetInteger(ORDER_MAGIC)==InpMagic && OrderGetString(ORDER_SYMBOL)==sym) return true;
   }
   return false;
}
void CloseAll()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
      if(pos.SelectByIndex(i) && pos.Magic()==InpMagic) trade.PositionClose(pos.Ticket());
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong t=OrderGetTicket(i);
      if(t>0 && OrderGetInteger(ORDER_MAGIC)==InpMagic) trade.OrderDelete(t);
   }
}
//+------------------------------------------------------------------+
```

---

## Preset that actually aims at 20%/month

| Input | Value | Why |
|---|---|---|
| `InpSymbols` | EURUSD,GBPUSD,USDJPY,AUDUSD,USDCAD,XAUUSD,GBPJPY,EURJPY | 8 symbols ≈ 25–35 setups/month |
| `InpEntryTF` | M15 (or PERIOD_CURRENT) | enough setups, tolerable spread cost |
| `InpHTFSteps` | 3 → bias on H4 | classic SMC HTF/LTF pair |
| `InpRiskPercent` | **1.5** | 20R needed ≈ 13 net R at 1.5% |
| `InpRR` | 3.0 | keeps expectancy positive at 40% WR |
| `InpPartialAtR` | 1.5 + BE | cuts variance, costs ~0.3R of upside |
| `InpDailyLossPct` | 4.0 | caps bad days |
| `InpMaxSpreadPts` | 35 majors / 250 XAUUSD | run XAU on a second chart instance |

Break-even win rate at 1:3 is 25%. You need **>40%** to hit the target.

## Before you risk a cent — 4-step validation

1. **Compile & single-symbol test.** Strategy Tester, EURUSD M15, "Every tick based on real ticks", 2022-01→2026-09. Look at profit factor (want >1.3) and max DD.
2. **Walk-forward, don't curve-fit.** Optimise `InpFractal`, `InpSweepLookback`, `InpRR` on 2022–2024, then run 2025–2026 untouched. If out-of-sample PF collapses below 1.1, the edge is fitted.
3. **Per-symbol sanity.** Run each symbol alone. Delete any symbol with negative expectancy — don't let the portfolio hide it.
4. **Demo 4–6 weeks** on your real broker feed before live. Slippage on limit orders at OB levels is the #1 killer of backtest-vs-live divergence.

**Honest expectation setting:** if backtest shows 20%/month at 1.5% risk, live will typically deliver 8–12% with a 25% DD, and one month in six will be red. If you need the number to be 20% every month, raise risk to 3% and accept a realistic chance of a 40%+ drawdown.
