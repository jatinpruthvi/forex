//+------------------------------------------------------------------+
//|                                      EA_CF_RealSimpleStrategy.mq5 |
//|                                  Copyright 2026, Master Strategy  |
//|                                                                   |
//| ChartFanatics playbook: Real Simple (Ariel)                        |
//| Card    : chartfanatics/todos/real-simple-strategy.md      (#33)   |
//| Source  : chartfanatics/pdf/real-simple-strategy.pdf               |
//| Magic   : 3236                                                    |
//|                                                                   |
//| "This approach focuses on 5 to 6 repeatable price action setups,   |
//|  anchored around earnings gaps, high volume closes, and breakout   |
//|  patterns."  All six are implemented, each with the document's own |
//| entry and stop:                                                     |
//|                                                                   |
//|   R1  EPISODIC PIVOT: "Look for a trending stock that gaps up on   |
//|       unexpected news or earnings ... volume is multiple times     |
//|       the normal daily average".  Entry: "Use an Opening Range     |
//|       Break (ORB) on the five-minute chart.  Enter above the high  |
//|       of the first five-minute bar."  Stop: "the low of day."      |
//|   R2  DELAYED HIGH VOLUME CLOSE: "Identify the closing price on    |
//|       the day of the earnings gap ... Draw a horizontal line at    |
//|       the high-volume close.  Enter as price breaks back through   |
//|       that close on any day afterward.  Do not wait for a daily    |
//|       close confirmation; enter on the break."  Stop: the low of   |
//|       the day the entry triggers.                                  |
//|   R3  FLAT BASE BREAKOUT: "a tight range over multiple weeks,       |
//|       often following a strong prior trend ... The 10-day or       |
//|       20-day moving average should tighten up near the price ...   |
//|       progressively smaller daily ranges".  Entry: "above the      |
//|       prior day's high, which also clears the flat base            |
//|       resistance".  Stop: "If the daily candle is very tight ...   |
//|       the previous day's low.  If the candle is wide or includes   |
//|       a wick ... the low of the breakout day."                     |
//|   R4  UNDERCUT AND RALLY: "a quick undercut of that low, followed  |
//|       by a reversal back above.  Enter when price reclaims the     |
//|       prior low."  Stop: "the new swing low formed during the      |
//|       undercut."                                                   |
//|   R5  MOVING AVERAGE U&R: "Price moves below a significant daily   |
//|       moving average (such as the 10-day, 20-day, or 50-day) ...   |
//|       then reclaims the moving average with strength, ideally      |
//|       supported by increased volume."  Entry: "as price rallies    |
//|       back through the moving average."  Stop: "the low of the     |
//|       reclaim day."                                                |
//|   R6  HIGH TIGHT FLAG: "Price advances 50% to 100% in a short      |
//|       period.  A tight flag forms, lasting two to five weeks ...   |
//|       Volume contracts during the flag formation."  Entry: "when   |
//|       the price breaks through the upper half of the tight range." |
//|       Stop: "the low of the breakout day."                         |
//|                                                                   |
//| Key principles, mechanized: Trades aligned with the market         |
//| ("Trades are only taken when the broader market and the stock's    |
//| sector or group support the trade's direction") - the market proxy |
//| must be healthy against its own 20-day EMA and the stock must show |
//| relative strength; "The setup is always based on the daily chart.  |
//| The 5-minute chart is used to refine execution" - D1 context with  |
//| M5 execution, the engine's own two-timeframe split.                |
//|                                                                   |
//| Management, verbatim: "Take partial profits into strength,         |
//| especially after three to five strong days.  Trail the remaining   |
//| position using rising moving averages like the 10-day or 20-day to |
//| stay in winning trades ... If the stock violates your trailing     |
//| stop or closes below key levels on high volume, exit the trade     |
//| without hesitation."  Risk sizing follows "Typical risk ranges     |
//| from 0.5% to 1% of total equity".                                  |
//|                                                                   |
//| `[interpretation]`: the document states no numbers for gap size,   |
//| volume multiples, base widths, convergence, flag length or the     |
//| "strong days" trim - every one is an input and labelled.  "The     |
//| upper half of the tight range" is ambiguous; the EA takes the      |
//| unambiguous geometry - a break of the flag's high (the range's     |
//| upper boundary), disclosed here and in the tracker.                |
//|                                                                   |
//| Disclosed, not faked: sector / group strength is not observable in |
//| an EA, so relative strength versus the market proxy stands in (the |
//| same page's own "relative strength vs. the market" confirmation);  |
//| "progressive exposure" (scaling in as trades work) stays a human   |
//| discipline - the engine opens one risk-sized position per setup.   |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics Real Simple (Ariel) - six swing setups: EP, delayed HVC, flat base, U&R, MA U&R, high tight flag"

#include "..\..\Include\EACommon.mqh"

//--- which of the six setups may fire
input bool              InpUseEp              = true;              // Episodic Pivot (R1)
input bool              InpUseHvc             = true;              // Delayed High Volume Close (R2)
input bool              InpUseFlatBase        = true;              // Flat Base Breakout (R3)
input bool              InpUseUr              = true;              // Undercut and Rally (R4)
input bool              InpUseMaUr            = true;              // Moving Average U&R (R5)
input bool              InpUseHtf             = true;              // High Tight Flag (R6)

//--- identity / risk
input string            InpSymbolsToTrade     = "AAPL,MSFT,NVDA";  // Universe (playbook: stocks, swing trading)
input string            InpMarketSymbol       = "US100";           // Market proxy for the alignment gate
input ulong             InpMagicNumber        = 3236;              // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct            = 0.75;              // "Typical risk ranges from 0.5% to 1% of total equity"
input int               InpStage              = 5;                 // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input double            InpMaxSpreadPoints    = 5.0;               // Spread gate in points (0 = off)
input double            InpDailyLossPct       = 1.50;              // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset    = 2;                 // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel           = EA_LOG_EVENTS;     // Log verbosity
input double            InpCommissionPerLotRT = 0.0;               // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.12;              // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;              // Write the engine evidence ledger CSV

//--- the market / strength alignment
input double            InpMinRsPct           = 0.0;               // [interpretation] Relative strength vs market gate (%)
input int               InpRsDays             = 20;                // Window for the relative-strength read

//--- shared geometry
input double            InpStopBufferAtr      = 0.15;              // [interpretation] Buffer beyond the structural stop (daily ATR)
input double            InpMaxStopPct         = 12.0;              // [interpretation] Reject stops wider than x% of price
input double            InpTightRangeAtr      = 0.60;              // [interpretation] A candle this narrow is tight (R3 stop rule)

//--- R1/R2 the gap family
input int               InpEpMaxDaysAfterGap  = 5;                 // [interpretation] How fresh the EP gap must be
input double            InpGapMinPct          = 2.0;               // [interpretation] Minimum gap size (%)
input double            InpGapVolMult         = 2.0;               // "volume is multiple times the normal daily average"
input int               InpHvcMaxDays         = 25;                // [interpretation] The HVC stays live this long
input int               InpHvcNearBars        = 10;                // [interpretation] The consolidation window near the HVC

//--- R3 the flat base
input int               InpFlatBaseBars       = 15;                // "a tight range over multiple weeks" (~3 weeks)
input double            InpFlatBaseMaxPct     = 15.0;              // [interpretation] Base height (% of price)
input double            InpMaConvergePct      = 2.0;               // "the 10-day or 20-day moving average should tighten up"
input double            InpPriorTrendPct      = 15.0;              // [interpretation] "following a strong prior trend"

//--- R4 the undercut and rally
input int               InpUrLookback         = 12;                // [interpretation] The prior low window (days)

//--- R5 the moving average U&R
input double            InpReclaimVolMult     = 1.20;              // "ideally supported by increased volume"
input double            InpMaUrMaxDistPct     = 3.0;               // [interpretation] How far the reclaim may run from the MA (%)

//--- R6 the high tight flag
input int               InpHtfRunDays         = 40;                // [interpretation] The advance window
input double            InpHtfMinAdvancePct   = 50.0;              // "Price advances 50% to 100% in a short period"
input int               InpHtfFlagBars        = 15;                // "a tight flag ... lasting two to five weeks"
input double            InpHtfMaxRangePct     = 12.0;              // [interpretation] Flag height (% of price)
input double            InpHtfHoldPct         = 10.0;              // [interpretation] "holding near highs" (within % of the run high)
input double            InpHtfVolFrac         = 0.80;              // "Volume contracts during the flag formation"

//--- management (the document's own)
input int               InpStrongDaysForTrim  = 4;                 // "after three to five strong days"
input double            InpTrimPct            = 33.4;              // "Take partial profits into strength"
input double            InpTargetR            = 8.0;               // [interpretation] Far TP placeholder - the EMA trail is the exit
input int               InpTrailEma           = 10;                // "Trail ... using rising moving averages like the 10-day or 20-day"
input double            InpExitVolMult        = 1.50;              // "closes below key levels on high volume, exit"

//--- session (daily setups, intraday execution)
input int               InpSessionStartHour   = 14;                // US RTH open, London time (09:30 ET)
input int               InpSessionStartMin    = 30;
input int               InpSessionEndHour     = 21;                // US RTH close - the 5-minute execution window
input int               InpSessionEndMin      = 0;
input int               InpMaxTradesPerDay    = 3;                 // [interpretation] Swing entries are rare; a small daily cap

//+------------------------------------------------------------------+
struct SRealSimple
{
   //--- daily geometry
   double ema10, ema20, ema50, ema200;
   double atrD1;
   double avgVol10;
   double runHigh;            // R6: the advance high
   double flagHigh;           // R6: the flag's upper boundary
   //--- relative strength / market alignment
   double rs;
   bool   marketHealthy;
   //--- the gap family
   int    gapIdx;             // the most recent qualifying gap day (0 = none)
   double hvc;                // the gap day's close
   //--- R3
   double baseHigh;
   bool   flatBase;
   //--- R4 / R5
   double priorLow;
   bool   undercutSeen;       // an undercut happened on the newest bars
   double undercutLow;        // the swing low the undercut formed
   double maUrLevel;          // the MA being reclaimed
};

//+------------------------------------------------------------------+
class CCfRealSimpleStrategy : public CEAStrategy
{
public:
   void OnInitStrategy()
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("5-stage policy: stage %d active (risk %.3f%%, %d trades/day max)",
             InpStage, g_eaCfg.riskPct, g_eaCfg.maxTradesPerDay), true);
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "Real Simple armed: setups EP:%s HVC:%s thin:%s U&R:%s MAU&R:%s HTF:%s, risk %.2f%%",
             InpUseEp ? "on" : "off", InpUseHvc ? "on" : "off", InpUseFlatBase ? "on" : "off",
             InpUseUr ? "on" : "off", InpUseMaUr ? "on" : "off", InpUseHtf ? "on" : "off",
             g_eaCfg.riskPct), true);
   }

   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_REAL_SIMPLE";
      cfg.sourceDoc             = "chartfanatics/pdf/real-simple-strategy.pdf (card #33)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;      // "The 5-minute chart is used to refine execution"
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = 4.0;
      cfg.totalDdPct            = 10.0;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 300;
      cfg.sessionStartHour      = InpSessionStartHour;
      cfg.sessionStartMin       = InpSessionStartMin;
      cfg.sessionEndHour        = InpSessionEndHour;
      cfg.sessionEndMin         = InpSessionEndMin;
      cfg.sessionEndFlat        = false;          // swing trading: winners are trailed, not flattened at the bell
      cfg.fridayFlat            = false;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = false;
      cfg.partial1AtR           = 0.0;            // the doc's trim is day-count based - hand-rolled in Manage()
      cfg.breakEvenAtR          = 0.0;            // the document states no break-even rule
      cfg.trailAtR              = 0.0;            // the EMA trail is the document's own - see Manage()
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_real_simple_ledger.csv";
      cfg.newsFilter            = false;
      cfg.logLevel              = InpLogLevel;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   //+----------------------------------------------------------------+
   //| Signal phase: the daily map, the alignment gate, then the six   |
   //| setups - the best-scoring valid one wins.                       |
   //+----------------------------------------------------------------+
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession || ctx.atr <= 0.0) return false;
      if(ctx.clockMinutes < InpSessionStartHour * 60 + InpSessionStartMin + 5) return false;   // the ORB needs its first bar

      SRealSimple c;
      if(!DailyMap(ctx, c)) return false;

      //--- the alignment principle: the market must support the trade and the stock must lead it
      if(!c.marketHealthy) return false;
      if(c.rs < InpMinRsPct) return false;

      MqlRates d[];
      int got = EA_Rates(ctx.symbol, PERIOD_D1, 0, (int)MathMax(80, InpHtfRunDays + InpHtfFlagBars + 20), d);
      if(got < 60) return false;

      MqlRates m[];
      if(EA_Rates(ctx.symbol, g_eaIndTf, 0, 240, m) < 10) return false;

      double best = -1.0;
      SSignalPlan p;
      for(int k = 0; k < 6; k++)
      {
         bool ok = false;
         if(k == 0 && InpUseEp)       ok = PlanEp(ctx, c, d, got, m, p);
         if(k == 1 && InpUseHvc)      ok = PlanHvc(ctx, c, d, got, m, p);
         if(k == 2 && InpUseFlatBase) ok = PlanFlatBase(ctx, c, d, got, m, p);
         if(k == 3 && InpUseUr)       ok = PlanUr(ctx, c, d, got, m, p);
         if(k == 4 && InpUseMaUr)     ok = PlanMaUr(ctx, c, d, got, m, p);
         if(k == 5 && InpUseHtf)      ok = PlanHtf(ctx, c, d, got, m, p);
         if(ok && p.score > best) { plan = p; best = p.score; }
      }
      return (plan.dir != 0);
   }

   //+----------------------------------------------------------------+
   //| The document's management: trim into strength after several     |
   //| strong days, trail on the rising 10/20-day EMA, and exit on     |
   //| a high-volume close below the 20-day EMA.                        |
   //+----------------------------------------------------------------+
   void Manage(SEAContext &ctx)
   {
      ulong ticket = EA_FindPosition(ctx.symbol, +1);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) return;

      MqlRates d[];
      if(EA_Rates(ctx.symbol, PERIOD_D1, 0, 30, d) < 15) return;

      //--- "Take partial profits into strength, especially after three to five strong days"
      if(!FlagDone(ticket, "TRIM"))
      {
         int strong = 0;
         for(int i = 1; i < 10 && i + 1 < ArraySize(d); i++)
         {
            if(d[i].close > d[i + 1].close) strong++;
            else break;
         }
         if(strong >= InpStrongDaysForTrim)
         {
            double entry = PositionGetDouble(POSITION_PRICE_OPEN);
            if(ctx.bid > entry)
            {
               if(g_eaExec.ClosePartial(ticket, InpTrimPct) || !g_eaExec.CanPartial(ticket, InpTrimPct))
               {
                  FlagSet(ticket, "TRIM");
                  EA_Log(EA_LOG_EVENTS, StringFormat("Real Simple: trimmed into strength after %d strong days", strong), true);
               }
            }
         }
      }

      //--- "Trail the remaining position using rising moving averages like the 10-day or 20-day"
      double emaT = DailyEma(ctx.symbol, InpTrailEma, 60);
      if(emaT > 0.0 && d[1].close < emaT)
      {
         if(g_eaExec.Close(ticket, StringFormat("daily close %.2f under the %d-day EMA %.2f - trailing exit", d[1].close, InpTrailEma, emaT)))
            EA_Log(EA_LOG_EVENTS, StringFormat("Real Simple: trailed out on the %d-day EMA violation", InpTrailEma), true);
         return;
      }
      //--- "closes below key levels on high volume, exit the trade without hesitation"
      double ema20 = DailyEma(ctx.symbol, 20, 60);
      double avgVol = AvgVolume(d, 10);
      if(ema20 > 0.0 && d[1].close < ema20 && avgVol > 0.0 && (double)d[1].tick_volume >= InpExitVolMult * avgVol)
      {
         if(g_eaExec.Close(ticket, "close below the 20-day EMA on high volume - exit"))
            EA_Log(EA_LOG_EVENTS, "Real Simple: high-volume close below the 20-day EMA - exited", true);
      }
   }

private:
   string FlagKey(const ulong ticket, const string tag)
   {
      return "CFRS_" + IntegerToString((long)g_eaCfg.magic) + "_" + IntegerToString((long)ticket) + "_" + tag;
   }
   bool FlagDone(const ulong ticket, const string tag) { return GlobalVariableCheck(FlagKey(ticket, tag)); }
   void FlagSet(const ulong ticket, const string tag)  { GlobalVariableSet(FlagKey(ticket, tag), 1.0); }

   double EmaOfAt(const MqlRates &r[], const int got, const int period, const int offset)
   {
      if(got < period + offset + 2 || period < 2) return 0.0;
      double k = 2.0 / (period + 1.0);
      double ema = r[got - 1].close;
      for(int i = got - 2; i >= offset; i--) ema = r[i].close * k + ema * (1.0 - k);
      return ema;
   }
   double EmaOf(const MqlRates &r[], const int got, const int period) { return EmaOfAt(r, got, period, 0); }

   double AvgVolume(const MqlRates &r[], const int bars)
   {
      int n = (int)MathMax(1, MathMin(bars, ArraySize(r) - 1));
      double sum = 0.0;
      for(int i = 1; i <= n; i++) sum += (double)r[i].tick_volume;
      return sum / n;
   }

   double DailyEma(const string sym, const int period, const int want)
   {
      MqlRates d[];
      int got = EA_Rates(sym, PERIOD_D1, 0, (int)MathMax(want, period + 20), d);
      if(got < period + 2) return 0.0;
      return EmaOf(d, got, period);
   }

   //--- the session anchors and the first five-minute bar (the ORB reference)
   datetime SessionAnchor(const SEAContext &ctx)
   {
      MqlDateTime dt;
      TimeToStruct(ctx.nowClock, dt);
      dt.hour = InpSessionStartHour; dt.min = InpSessionStartMin; dt.sec = 0;
      return EA_ClockToServer(StructToTime(dt));
   }

   double OrbHigh(const SEAContext &ctx, const MqlRates &m[])
   {
      datetime anchor = SessionAnchor(ctx);
      double hi = 0.0;
      for(int i = ArraySize(m) - 1; i >= 0; i--)          // walk oldest -> newest
      {
         if(m[i].time < anchor) continue;
         hi = m[i].high;                                   // the first bar of the session carries the ORB high
         break;
      }
      return hi;
   }

   double SessionLow(const SEAContext &ctx, const MqlRates &m[])
   {
      datetime anchor = SessionAnchor(ctx);
      double lo = 0.0;
      for(int i = 0; i < ArraySize(m); i++)
      {
         if(m[i].time < anchor) break;
         if(lo == 0.0 || m[i].low < lo) lo = m[i].low;
      }
      return lo;
   }

   //+----------------------------------------------------------------+
   //| The daily map: EMAs, ATR, volumes, relative strength, the gap   |
   //| family, the flat base, the prior lows and the flag.             |
   //+----------------------------------------------------------------+
   bool DailyMap(const SEAContext &ctx, SRealSimple &c)
   {
      c.ema10 = 0; c.ema20 = 0; c.ema50 = 0; c.ema200 = 0;
      c.atrD1 = 0; c.avgVol10 = 0; c.runHigh = 0; c.flagHigh = 0;
      c.rs = 0; c.marketHealthy = false; c.gapIdx = 0; c.hvc = 0;
      c.baseHigh = 0; c.flatBase = false; c.priorLow = 0;
      c.undercutSeen = false; c.undercutLow = 0; c.maUrLevel = 0;

      MqlRates d[];
      int got = EA_Rates(ctx.symbol, PERIOD_D1, 0, (int)MathMax(260, InpHtfRunDays + InpHtfFlagBars + 40), d);
      if(got < 230) return false;

      c.ema10  = EmaOf(d, (int)MathMin(got, 60), 10);
      c.ema20  = EmaOf(d, (int)MathMin(got, 80), 20);
      c.ema50  = EmaOf(d, (int)MathMin(got, 160), 50);
      c.ema200 = EmaOf(d, got, 200);
      if(c.ema10 <= 0.0 || c.ema20 <= 0.0 || c.ema50 <= 0.0 || c.ema200 <= 0.0) return false;
      c.atrD1   = ctx.atrD1;
      c.avgVol10 = AvgVolume(d, 10);
      if(c.avgVol10 <= 0.0) return false;

      //--- relative strength vs the market proxy and the market's own health
      MqlRates mkt[];
      int mgot = EA_Rates(InpMarketSymbol, PERIOD_D1, 0, 60, mkt);
      if(mgot > InpRsDays + 1 && d[InpRsDays].close > 0.0 && mkt[InpRsDays].close > 0.0)
      {
         double stockRet = (d[1].close - d[InpRsDays].close) / d[InpRsDays].close * 100.0;
         double mktRet   = (mkt[1].close - mkt[InpRsDays].close) / mkt[InpRsDays].close * 100.0;
         c.rs = stockRet - mktRet;
         double mktEma = EmaOf(mkt, mgot, 20);
         c.marketHealthy = (mktEma > 0.0 && mkt[1].close > mktEma);
      }
      if(!c.marketHealthy) return false;

      //--- R1/R2: the most recent qualifying gap day (a gap up on a volume multiple)
      for(int i = 1; i <= InpHvcMaxDays + 5 && i + 12 < got; i++)
      {
         double prevHigh = d[i + 1].high;
         double avg = 0.0;
         for(int k = i + 1; k <= i + 10; k++) avg += (double)d[k].tick_volume;
         avg /= 10.0;
         bool gap = (d[i].open > prevHigh * (1.0 + InpGapMinPct / 100.0));
         bool vol = (avg <= 0.0) || ((double)d[i].tick_volume >= InpGapVolMult * avg);
         if(gap && vol) { c.gapIdx = i; c.hvc = d[i].close; break; }
      }

      //--- R3: the flat base over the last completed weeks
      int bFirst = 2, bLast = 2 + InpFlatBaseBars - 1;
      if(bLast + 25 >= got) return false;
      double bHi = d[bFirst].high, bLo = d[bFirst].low;
      double baseRange = 0.0, recentRange = 0.0;
      for(int i = bFirst; i <= bLast; i++)
      {
         bHi = MathMax(bHi, d[i].high);
         bLo = MathMin(bLo, d[i].low);
         baseRange += (d[i].high - d[i].low);
      }
      for(int i = 1; i <= 3; i++) recentRange += (d[i].high - d[i].low);
      c.baseHigh = bHi;
      double basePct = (bHi - bLo) / MathMax(d[1].close, 0.0001) * 100.0;
      double converge = MathAbs(c.ema10 - c.ema20) / MathMax(d[1].close, 0.0001) * 100.0;
      bool priorTrend = (d[bLast + 1].close > 0.0) &&
                        ((d[bLast + 20 < got ? bLast + 20 : got - 1].close - d[bLast + 1].close) / d[bLast + 1].close * 100.0 >= InpPriorTrendPct);
      bool shrinking = (baseRange / InpFlatBaseBars) > 0.0 && (recentRange / 3.0) < (baseRange / InpFlatBaseBars);
      c.flatBase = (basePct <= InpFlatBaseMaxPct) && (converge <= InpMaConvergePct) &&
                   priorTrend && shrinking;         // "progressively smaller daily ranges near the breakout level"

      //--- R4: the prior low, the undercut and the reclaim
      c.priorLow = d[1].low;
      for(int i = 1; i <= (int)MathMax(3, MathMin(InpUrLookback, got - 2)); i++)
         c.priorLow = MathMin(c.priorLow, d[i].low);
      bool undercutToday = (d[0].low < c.priorLow);
      bool undercutYesterday = (d[1].low < c.priorLow && d[1].close < c.priorLow);
      c.undercutSeen = (undercutToday || undercutYesterday);
      c.undercutLow = d[0].low;
      if(undercutYesterday) c.undercutLow = MathMin(c.undercutLow, d[1].low);

      //--- R5: the MA undercut - a close below a significant MA, reclaiming now
      double mas[3] = {c.ema10, c.ema20, c.ema50};
      for(int k = 0; k < 3; k++)
      {
         double ma = mas[k];
         if(ma <= 0.0) continue;
         bool below = (d[1].close < ma);
         bool reclaimed = (ctx.bid > ma);
         if(below && reclaimed) { c.maUrLevel = ma; break; }
      }

      //--- R6: the advance, the flag, the contracting volume
      int rFirst = InpHtfFlagBars + 1, rLast = InpHtfFlagBars + InpHtfRunDays;
      if(rLast + 2 < got)
      {
         double advLow = d[rLast].low, advHigh = d[rLast].high;
         for(int i = rFirst; i <= rLast; i++)
         {
            advLow  = MathMin(advLow,  d[i].low);
            advHigh = MathMax(advHigh, d[i].high);
         }
         c.runHigh = advHigh;
         double fHi = d[1].high, fLo = d[1].low, flagVol = 0.0, advVol = 0.0;
         for(int i = 1; i <= InpHtfFlagBars; i++)
         {
            fHi = MathMax(fHi, d[i].high);
            fLo = MathMin(fLo, d[i].low);
            flagVol += (double)d[i].tick_volume;
         }
         for(int i = rFirst; i <= rLast; i++) advVol += (double)d[i].tick_volume;
         flagVol /= InpHtfFlagBars;
         advVol  /= InpHtfRunDays;
         double advancePct = (advLow > 0.0) ? (advHigh - advLow) / advLow * 100.0 : 0.0;
         double flagPct    = (d[1].close > 0.0) ? (fHi - fLo) / d[1].close * 100.0 : 100.0;
         bool nearHighs    = (advHigh > 0.0) && (fLo >= advHigh * (1.0 - InpHtfHoldPct / 100.0));
         bool volContract  = (advVol <= 0.0) || (flagVol <= InpHtfVolFrac * advVol);
         if(advancePct >= InpHtfMinAdvancePct && flagPct <= InpHtfMaxRangePct && nearHighs && volContract)
            c.flagHigh = fHi;
      }
      return true;
   }

   //--- R1: the episodic pivot - the ORB above the first five-minute bar
   bool PlanEp(const SEAContext &ctx, const SRealSimple &c, const MqlRates &d[], const int got,
               const MqlRates &m[], SSignalPlan &plan)
   {
      plan.Reset();
      if(c.gapIdx == 0 || c.gapIdx > InpEpMaxDaysAfterGap) return false;
      double orb = OrbHigh(ctx, m);
      if(orb <= 0.0 || ctx.mid <= orb) return false;
      double lowDay = SessionLow(ctx, m);
      if(lowDay <= 0.0) return false;
      double stop = lowDay - InpStopBufferAtr * c.atrD1;
      double entry = ctx.ask;
      if(stop >= entry) return false;
      double risk = entry - stop;
      if(risk > entry * InpMaxStopPct / 100.0) return false;

      plan.dir = +1; plan.entry = entry; plan.stop = stop;
      plan.target = entry + InpTargetR * risk;
      plan.riskDist = risk; plan.barsAgo = 1; plan.isLimit = false;
      plan.score = 82.0;
      plan.reason = StringFormat("EP: gap d-%d (HVC %.2f), ORB break above %.2f, stop at the low of day", c.gapIdx, c.hvc, orb);
      return true;
   }

   //--- R2: the delayed high volume close
   bool PlanHvc(const SEAContext &ctx, const SRealSimple &c, const MqlRates &d[], const int got,
                const MqlRates &m[], SSignalPlan &plan)
   {
      plan.Reset();
      if(c.gapIdx == 0 || c.hvc <= 0.0) return false;
      if(d[1].close >= c.hvc) return false;                       // the break must happen now
      if(ctx.bid <= c.hvc) return false;                          // "enter as price breaks back through that close"
      //--- "works best if the stock consolidates near the HVC for several days"
      bool near = false;
      int look = (int)MathMax(3, MathMin(InpHvcNearBars, got - 2));
      for(int i = 1; i <= look; i++)
         if(MathAbs(d[i].close - c.hvc) <= 0.5 * (c.atrD1 > 0.0 ? c.atrD1 : c.hvc * 0.02)) { near = true; break; }
      if(!near) return false;
      double lowDay = SessionLow(ctx, m);
      if(lowDay <= 0.0) return false;
      double entry = ctx.ask, stop = lowDay - InpStopBufferAtr * c.atrD1;
      if(stop >= entry) return false;
      double risk = entry - stop;
      if(risk > entry * InpMaxStopPct / 100.0) return false;

      plan.dir = +1; plan.entry = entry; plan.stop = stop;
      plan.target = entry + InpTargetR * risk;
      plan.riskDist = risk; plan.barsAgo = 1; plan.isLimit = false;
      plan.score = 74.0;
      plan.reason = StringFormat("HVC: reclaim of the gap-day close %.2f (gap d-%d), stop at the low of day", c.hvc, c.gapIdx);
      return true;
   }

   //--- R3: the flat base breakout
   bool PlanFlatBase(const SEAContext &ctx, const SRealSimple &c, const MqlRates &d[], const int got,
                     const MqlRates &m[], SSignalPlan &plan)
   {
      plan.Reset();
      if(!c.flatBase || c.baseHigh <= 0.0) return false;
      if(!(ctx.bid > d[1].high && ctx.bid > c.baseHigh)) return false;    // "above the prior day's high ... clears the base"
      bool tightCandle = ((d[1].high - d[1].low) <= InpTightRangeAtr * c.atrD1);
      double stopLevel = tightCandle ? d[1].low : SessionLow(ctx, m);
      if(stopLevel <= 0.0) return false;
      double entry = ctx.ask, stop = stopLevel - InpStopBufferAtr * c.atrD1;
      if(stop >= entry) return false;
      double risk = entry - stop;
      if(risk > entry * InpMaxStopPct / 100.0) return false;

      plan.dir = +1; plan.entry = entry; plan.stop = stop;
      plan.target = entry + InpTargetR * risk;
      plan.riskDist = risk; plan.barsAgo = 1; plan.isLimit = false;
      plan.score = 78.0;
      plan.reason = StringFormat("flat base: break of %.2f and yesterday high%s", c.baseHigh,
                                 tightCandle ? ", stop at the prior day low (tight candle)" : ", stop at the breakout-day low");
      return true;
   }

   //--- R4: the undercut and rally
   bool PlanUr(const SEAContext &ctx, const SRealSimple &c, const MqlRates &d[], const int got,
               const MqlRates &m[], SSignalPlan &plan)
   {
      plan.Reset();
      if(!c.undercutSeen || c.priorLow <= 0.0) return false;
      if(ctx.bid <= c.priorLow) return false;                      // "enter when price reclaims the prior low"
      if(c.undercutLow <= 0.0) return false;
      double entry = ctx.ask, stop = c.undercutLow - InpStopBufferAtr * c.atrD1;
      if(stop >= entry) return false;
      double risk = entry - stop;
      if(risk > entry * InpMaxStopPct / 100.0) return false;

      plan.dir = +1; plan.entry = entry; plan.stop = stop;
      plan.target = entry + InpTargetR * risk;
      plan.riskDist = risk; plan.barsAgo = 1; plan.isLimit = false;
      plan.score = 72.0;
      plan.reason = StringFormat("U&R: reclaim of the prior low %.2f, stop at the undercut swing low %.2f", c.priorLow, c.undercutLow);
      return true;
   }

   //--- R5: the moving average undercut and rally
   bool PlanMaUr(const SEAContext &ctx, const SRealSimple &c, const MqlRates &d[], const int got,
                 const MqlRates &m[], SSignalPlan &plan)
   {
      plan.Reset();
      if(c.maUrLevel <= 0.0) return false;
      double distPct = (ctx.bid - c.maUrLevel) / c.maUrLevel * 100.0;
      if(distPct > InpMaUrMaxDistPct) return false;                // enter as it rallies back THROUGH the MA
      double lowDay = SessionLow(ctx, m);
      double stopLevel = (lowDay > 0.0) ? MathMin(lowDay, d[1].low) : d[1].low;
      double entry = ctx.ask, stop = stopLevel - InpStopBufferAtr * c.atrD1;
      if(stop >= entry) return false;
      double risk = entry - stop;
      if(risk > entry * InpMaxStopPct / 100.0) return false;

      //--- "ideally supported by increased volume" - scored, not gated
      double recentVol = 0.0;
      int n = (int)MathMax(2, MathMin(20, ArraySize(m) - 1));
      for(int i = 1; i <= n; i++) recentVol += (double)m[i].tick_volume;
      recentVol /= n;
      double strongVol = ((double)m[1].tick_volume >= InpReclaimVolMult * recentVol) ? 6.0 : 0.0;

      plan.dir = +1; plan.entry = entry; plan.stop = stop;
      plan.target = entry + InpTargetR * risk;
      plan.riskDist = risk; plan.barsAgo = 1; plan.isLimit = false;
      plan.score = 70.0 + strongVol;
      plan.reason = StringFormat("MA U&R: reclaim of %.2f (closed below d-1), stop at the reclaim-day low", c.maUrLevel);
      return true;
   }

   //--- R6: the high tight flag
   bool PlanHtf(const SEAContext &ctx, const SRealSimple &c, const MqlRates &d[], const int got,
                const MqlRates &m[], SSignalPlan &plan)
   {
      plan.Reset();
      if(c.flagHigh <= 0.0) return false;
      if(ctx.bid <= c.flagHigh) return false;                      // the break of the flag's upper boundary
      double lowDay = SessionLow(ctx, m);
      if(lowDay <= 0.0) return false;
      double entry = ctx.ask, stop = lowDay - InpStopBufferAtr * c.atrD1;
      if(stop >= entry) return false;
      double risk = entry - stop;
      if(risk > entry * InpMaxStopPct / 100.0) return false;

      plan.dir = +1; plan.entry = entry; plan.stop = stop;
      plan.target = entry + InpTargetR * risk;
      plan.riskDist = risk; plan.barsAgo = 1; plan.isLimit = false;
      plan.score = 80.0;
      plan.reason = StringFormat("high tight flag: break of %.2f (run high %.2f), stop at the breakout-day low", c.flagHigh, c.runHigh);
      return true;
   }
};

CCfRealSimpleStrategy g_cfRealSimple;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfRealSimple);
}

void OnTick()
{
   EA_Tick();
}

void OnDeinit(const int reason)
{
   EA_Deinit(reason);
}
//+------------------------------------------------------------------+
