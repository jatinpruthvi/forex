//+------------------------------------------------------------------+
//|                                             EA_SIGNAL_DUMP.mq5   |
//|  Verification script for FIVE_M5_EXHAUST.                        |
//|                                                                  |
//|  Dumps, for every M5 bar of your broker's own history, exactly   |
//|  what the EA computes: the simple-mean ATR, the trigger decision,|
//|  the stop/target geometry, the lot size, the server-day key and  |
//|  the Friday-block flag.                                          |
//|                                                                  |
//|  It deliberately ALSO dumps three WRONG values next to each      |
//|  correct one, so you can see the bugs this EA had and confirm    |
//|  they are gone:                                                  |
//|    atr_wilder   MT5's built-in iATR (Wilder/RMA smoothing).      |
//|                 Must differ from atr_simple. If it ever matches, |
//|                 someone replaced the hand-rolled ATR.            |
//|    daykey_bug   server-day key with the UTC offset added to a    |
//|                 value that is ALREADY server time.               |
//|    friday_bug   the same double-offset in the Friday test, which |
//|                 inverted the block (fired 18:00-20:59, missed    |
//|                 21:00-23:59).                                    |
//|                                                                  |
//|  Then run compare_ea_dump.py to diff this against the repo's     |
//|  validated Python backtest.                                      |
//|                                                                  |
//|  READ-ONLY: this script places no orders and modifies nothing.   |
//+------------------------------------------------------------------+
#property copyright   "forex repo - Phase 2 speed lab"
#property version     "1.00"
#property description "Dumps FIVE_M5_EXHAUST's per-bar computation to CSV for verification."
#property description "Read-only: places no orders."
#property script_show_inputs

input string InpSymbols            = "EURGBP,AUDUSD,NZDUSD,USDCAD,USDCHF,EURJPY,GBPJPY,XAUUSD";
input int    InpBarsToDump         = 20000;   // per symbol; 20000 M5 bars is about 10 weeks
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M5;
input double InpBodyAtrMultiple    = 4.0;     // must match the EA
input int    InpAtrPeriod          = 14;      // must match the EA
input double InpStopAtrMultiple    = 2.0;     // must match the EA
input double InpTargetR            = 10.0;    // must match the EA
input double InpMinStopAtrMultiple = 1.0;     // must match the EA
input double InpRiskPercent        = 0.50;    // must match the EA
input double InpSizingBase         = 2500.0;  // account size used for the lot column
input double InpCommissionPerLotRT = 7.0;     // must match the EA
input int    InpFridayCutoffHour   = 21;      // must match the EA
input int    InpServerUtcOffsetHours = 3;     // your broker's offset, for the UTC column
input string InpFileName           = "ea_signal_dump.csv";

//+------------------------------------------------------------------+
//| VERBATIM COPY of FIVE_M5_EXHAUST.mq5 SimpleAtrBefore().           |
//| If the EA's version changes, change this too - or better, diff    |
//| them. Keeping them textually identical is the point.              |
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
//| VERBATIM COPY of the EA's LossPerLot() and NormaliseLots().       |
//+------------------------------------------------------------------+
double LossPerLot(const string sym,const double distance)
  {
   const double tick_size=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
   const double tick_val =SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
   if(tick_size<=0.0 || tick_val<=0.0) return -1.0;
   const double px_loss=(distance/tick_size)*tick_val;
   return px_loss+InpCommissionPerLotRT;
  }

// VERBATIM COPY of the EA's patched NormaliseLots() (round 5). The volume is rounded to
// the step's own decimal count so the value sent to trade.Buy() carries no 1-ULP residue:
// `n*step` cannot represent 0.01 exactly, so 35 steps came out as 0.35000000000000003 and
// a broker validating volume against SYMBOL_VOLUME_STEP with an exact comparison rejects it
// with TRADE_RETCODE_INVALID_VOLUME. The decimal count is derived by scaling, not by
// -log10(step), which would give 0.25 one decimal and round it UP to 0.3.
// selftest_ea_dump.py layer 0 asserts this copy still equals the EA's, semantically.
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

int ServerDayKey(const datetime server_time) { return (int)((long)server_time/86400L); }

//+------------------------------------------------------------------+
void OnStart()
  {
   const int offset_s=InpServerUtcOffsetHours*3600;

   // Measure the real offset in a live terminal; in the tester TimeGMT()==TimeCurrent()
   // by design, so the configured value is the only thing available.
   int detected_offset_h=InpServerUtcOffsetHours;
   const bool in_tester=(MQLInfoInteger(MQL_TESTER)!=0);
   if(!in_tester)
     {
      const long diff=(long)TimeCurrent()-(long)TimeGMT();
      detected_offset_h=(int)((diff+1800)/3600);
      if(detected_offset_h!=InpServerUtcOffsetHours)
         PrintFormat("[WARN] measured broker offset UTC%+d differs from the configured UTC%+d - "
                     "the utc_time column uses the MEASURED value",
                     detected_offset_h,InpServerUtcOffsetHours);
     }
   else
      Print("[INFO] Strategy Tester: offset cannot be measured here; using the configured value");
   const int use_offset_s=detected_offset_h*3600;

   string syms[];
   const int nsym=StringSplit(InpSymbols,',',syms);
   if(nsym<=0) { Print("[ERROR] no symbols"); return; }

   const int fh=FileOpen(InpFileName,FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(fh==INVALID_HANDLE)
     { PrintFormat("[ERROR] cannot open %s: %d",InpFileName,GetLastError()); return; }

   FileWrite(fh,"symbol","digits","shift","signal_time_server","entry_time_server","utc_time",
             "server_offset_hours","open","high","low","close",
             "atr_simple","atr_wilder","atr_ratio_wilder_over_simple",
             "body","body_over_atr","trigger","long_only","signal_fires",
             "pip","tick_size","tick_value","volume_step","volume_min","volume_max",
             "entry_next_open","stop_raw","stop_norm","dist","dist_pips","dist_over_atr",
             "reject_broken_geom","reject_degenerate_stop","target","lots","loss_per_lot",
             "daykey_correct","daykey_bug","friday_correct","friday_bug");

   int rows=0, fires=0, n_rej_geom=0, n_rej_degen=0;
   double worst_ratio=0.0;

   for(int si=0;si<nsym;si++)
     {
      string sym=syms[si];
      StringTrimLeft(sym); StringTrimRight(sym);
      if(sym=="") continue;
      if(!SymbolSelect(sym,true))
        { PrintFormat("[WARN] %s unavailable on this account - skipped",sym); continue; }

      const int bars=Bars(sym,InpTimeframe);
      const int need=InpAtrPeriod;
      if(bars<need+10)
        { PrintFormat("[WARN] %s has only %d bars - skipped",sym,bars); continue; }

      const int atr_handle=iATR(sym,InpTimeframe,need);
      const int digits=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
      const double pip=MathPow(10.0,-(double)digits)*10.0;   // 5-digit -> 0.0001
      // Dumped so the comparator can verify LossPerLot()/NormaliseLots() against the
      // BROKER's own contract terms instead of guessing them. A repo-side pip-value
      // assumption that disagrees with your broker is itself worth knowing about.
      const double tick_size=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
      const double tick_val =SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
      const double vol_step =SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
      const double vol_min  =SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
      const double vol_max  =SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);

      // shift counts BACK from the newest bar: shift 1 is the last closed bar, shift
      // bars-1 is the oldest. To dump the most RECENT InpBarsToDump bars we therefore run
      // from min(InpBarsToDump, bars-need-3) DOWN to 2 - oldest-of-window to newest.
      const int hi=MathMin(bars-need-3,InpBarsToDump);
      int written=0;

      for(int s=hi; s>=2; s--)                               // oldest -> newest
        {
         double atr=0.0;
         if(!SimpleAtrBefore(sym,s,atr)) continue;

         double wilder=0.0;
         if(atr_handle!=INVALID_HANDLE)
           {
            double buf[];
            ArraySetAsSeries(buf,true);
            if(CopyBuffer(atr_handle,0,s,1,buf)==1) wilder=buf[0];
           }
         if(atr>0.0 && wilder>0.0)
            worst_ratio=MathMax(worst_ratio,MathAbs(wilder/atr-1.0));

         const double o=iOpen(sym,InpTimeframe,s);
         const double h=iHigh(sym,InpTimeframe,s);
         const double l=iLow(sym,InpTimeframe,s);
         const double c=iClose(sym,InpTimeframe,s);
         if(o<=0.0 || h<=0.0 || l<=0.0 || c<=0.0) continue;

         const double body=MathAbs(c-o);
         const bool trigger=(body>InpBodyAtrMultiple*atr);
         const bool long_only=(c<o);                          // fade sharp SELL-OFFS only
         const bool signal_fires=(trigger && long_only);

         const datetime sig_time=(datetime)iTime(sym,InpTimeframe,s);
         const datetime now_time=(datetime)iTime(sym,InpTimeframe,s-1);  // the entry bar's open
         const double entry=iOpen(sym,InpTimeframe,s-1);
         if(entry<=0.0) continue;

         const double stop_raw=l-InpStopAtrMultiple*atr;
         const double stop_norm=NormalizeDouble(stop_raw,digits);
         const double dist=entry-stop_norm;
         const double dist_pips=dist/pip;
         const double dist_atr=(atr>0.0? dist/atr : 0.0);
         const bool rej_geom=(dist<=0.0);
         const bool rej_degen=(!rej_geom && dist<InpMinStopAtrMultiple*atr);
         const double target=NormalizeDouble(entry+InpTargetR*dist,digits);

         const double risk_cash=InpSizingBase*InpRiskPercent/100.0;
         const double lpl=LossPerLot(sym,dist);
         const double lots=(lpl>0.0 && !rej_geom && !rej_degen)
                            ? NormaliseLots(sym,risk_cash/lpl) : 0.0;

         // correct vs the double-offset bug
         const int  daykey_ok =ServerDayKey(now_time);
         const int  daykey_bug=(int)(((long)now_time+offset_s)/86400L);
         MqlDateTime a,b;
         TimeToStruct(now_time,a);                            // now_time IS server time
         TimeToStruct((datetime)((long)now_time+offset_s),b); // the bug shifted it again
         const bool fri_ok =(a.day_of_week==5 && a.hour>=InpFridayCutoffHour);
         const bool fri_bug=(b.day_of_week==5 && b.hour>=InpFridayCutoffHour);

         // 10 decimals everywhere: prices are written unrounded so the Python comparator
         // can check them tightly. `digits` is the broker's own SYMBOL_DIGITS - the reader
         // must never try to infer it from the text.
         FileWrite(fh,sym,digits,s,
                   TimeToString(sig_time,TIME_DATE|TIME_SECONDS),
                   TimeToString(now_time,TIME_DATE|TIME_SECONDS),
                   TimeToString((datetime)((long)now_time-use_offset_s),TIME_DATE|TIME_SECONDS),
                   detected_offset_h,
                   DoubleToString(o,10),DoubleToString(h,10),
                   DoubleToString(l,10),DoubleToString(c,10),
                   DoubleToString(atr,10),DoubleToString(wilder,10),
                   DoubleToString(atr>0.0?wilder/atr:0.0,10),
                   DoubleToString(body,10),DoubleToString(body/atr,10),
                   trigger?1:0,long_only?1:0,signal_fires?1:0,
                   DoubleToString(pip,10),DoubleToString(tick_size,10),
                   DoubleToString(tick_val,10),DoubleToString(vol_step,10),
                   DoubleToString(vol_min,10),DoubleToString(vol_max,10),
                   DoubleToString(entry,10),DoubleToString(stop_raw,10),
                   DoubleToString(stop_norm,10),DoubleToString(dist,10),
                   DoubleToString(dist_pips,10),DoubleToString(dist_atr,10),
                   rej_geom?1:0,rej_degen?1:0,DoubleToString(target,10),
                   DoubleToString(lots,10),DoubleToString(lpl,10),
                   daykey_ok,daykey_bug,fri_ok?1:0,fri_bug?1:0);

         rows++; written++;
         if(signal_fires) fires++;
         if(rej_geom)   n_rej_geom++;
         if(rej_degen)  n_rej_degen++;
        }
      if(atr_handle!=INVALID_HANDLE) IndicatorRelease(atr_handle);
      PrintFormat("[OK] %s: %d rows dumped (%d bars available)",sym,written,bars);
     }

   FileClose(fh);
   PrintFormat("[DONE] %s: %d rows, %d signals fire, %d rejected broken-geometry, "
               "%d rejected degenerate-stop",InpFileName,rows,fires,n_rej_geom,n_rej_degen);
   PrintFormat("[DONE] max |iATR/simpleATR - 1| seen = %.4f  -> Wilder and simple-mean ATR "
               "are NOT interchangeable; the EA must use the simple mean",worst_ratio);
   PrintFormat("[NEXT] run:  python3 validation/speed_lab/compare_ea_dump.py  "
               "(file is in MQL5/Files/%s)",InpFileName);
  }
//+------------------------------------------------------------------+
