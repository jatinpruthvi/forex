//+------------------------------------------------------------------+
//| EA_TRIAD_SURVIVE.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| TRIAD-SURVIVE - three-sleeve portfolio with scored entries and risk caps
//| Source document : docs/strategy/TRIAD-SURVIVE.md
//| Tracker entry   : #25  |  Magic: 3111
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CTriadSurvive class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "TRIAD-SURVIVE - three-sleeve portfolio with scored entries and risk caps"
#property description "Source: docs/strategy/TRIAD-SURVIVE.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY,XAUUSD,GBPJPY,AUDNZD,EURGBP,EURCHF";      // Comma separated universe
input double          InpMaxSpreadPoints  = 4.0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 1.0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 10;   // Permanent floor from start balance (0 = off)
input int             InpMaxTradesPerDay  = 4;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 3111; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpFullTierRiskPct    = 0.24;  // 8/8 or 5/5 score: full tier risk
input double InpHalfTierRiskPct    = 0.12;  // 7/8 or 4/5 score: half tier risk
input double InpMaxTotalOpenRisk   = 1.00;  // Max total open risk at any moment
input double InpMaxGroupRiskPct    = 0.24;  // Max risk per correlated group
input int    InpMaxPositions       = 4;     // Max concurrent positions (all sleeves)
input double InpShutdownDdPct      = 6.00;  // Shutdown from closed-equity high
input int    InpSleeveATimeStopMin = 45;    // Sleeve A: the 45-minute plateau
input double InpRunnerTrailAtr     = 2.5;   // Runner chandelier: 2.5 x ATR(H1,14)
input int    InpSleeveCExitMinute  = 390;   // Sleeve C hard flat 06:30 London
input bool   InpSleeveAEnabled     = true;
input bool   InpSleeveBEnabled     = true;
input bool   InpSleeveCEnabled     = true;

//+------------------------------------------------------------------+
//| Strategy: TRIAD-SURVIVE - three-sleeve portfolio with scored entries and risk caps
//+------------------------------------------------------------------+
class CTriadSurvive : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "TRIAD_SURVIVE";
      cfg.sourceDoc             = "docs/strategy/TRIAD-SURVIVE.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpFullTierRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = 2.0;
      cfg.totalDdPct            = InpTotalDdPct;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = InpMaxPositions;
      cfg.minSecondsBetweenTrades = 120;
      cfg.useHwmThrottle        = true;
      cfg.hwmTier1Dd            = 2.0;  cfg.hwmTier1Mult = 0.50;   // 2-4%: half tier
      cfg.hwmTier2Dd            = 4.0;  cfg.hwmTier2Mult = 0.25;   // 4-6%: quarter tier
      cfg.hwmHaltDd             = InpShutdownDdPct;                // above 6%: shutdown
      cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 19;  cfg.sessionEndMin = 30;
      cfg.noTradeAfterHour      = 21;  cfg.noTradeAfterMin = 30;   // no thin-liquidity entries
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.pendingExpiryMinutes  = 15;                              // three M5 candles
      cfg.timeStopMinutes       = 0;                               // per-sleeve, in Manage()
      cfg.breakEvenAtR          = 0.0;                             // ladder moves the stop instead
      cfg.partial1AtR           = 0.0;                             // per-symbol ladder in Manage()
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- portfolio-level caps first
      m_lastScore = 0.0;
      if(EA_OpenRiskPct() >= InpMaxTotalOpenRisk) return false;
      if(EA_CountPositions("", false) >= InpMaxPositions) return false;

      int    sleeve = 0;
      double tierRisk = InpFullTierRiskPct;
      double score = 0.0;

      //--- SLEEVE C: Asian mean reversion, 00:00-06:30, single entry, hard flat 06:30
      if(IsSleeveCSymbol(ctx.symbol) && InpSleeveCEnabled && ctx.clockMinutes < InpSleeveCExitMinute)
      {
         sleeve = 3;
         if(!SleeveCPlan(ctx, plan, score)) return false;
         tierRisk = (score >= 5.0) ? InpFullTierRiskPct : InpHalfTierRiskPct;
      }
      //--- SLEEVE B: volatility-expansion continuation (M15 breakout + retest)
      else if(IsSleeveBSymbol(ctx.symbol) && InpSleeveBEnabled)
      {
         sleeve = 2;
         if(!SleeveBPlan(ctx, plan, score)) return false;
         tierRisk = (score >= 5.0) ? InpFullTierRiskPct : InpHalfTierRiskPct;
      }
      //--- SLEEVE A: session sweep/reclaim, scored 8-point profile
      else
      {
         if(!InpSleeveAEnabled) return false;
         sleeve = 1;
         SSweepParams p;
         p.Reset();
         p.rangeFromMin   = 0;
         p.rangeToMin     = 7 * 60;
         p.sessionFromMin = 7 * 60;
         p.sessionToMin   = 11 * 60;
         p.sweepMinAtr    = 0.05;
         p.sweepMaxAtr    = 0.50;
         p.reclaimWindowBars = 3;
         p.wickRatio      = 0.60;
         p.bodyRatio      = 0.60;
         p.stopBufferAtr  = 0.10;
         p.minStopAtr     = 0.60;  p.maxStopAtr = 1.50;
         p.entryRetrace   = 0.50;
         p.targetR        = 1.50;
         if(ctx.symbol == "USDJPY" || ctx.symbol == "XAUUSD")
         {
            p.rangeFromMin   = 7 * 60;    // New York window uses the London range
            p.rangeToMin     = 13 * 60;
            p.sessionFromMin = 13 * 60 + 30;
            p.sessionToMin   = 16 * 60;
         }
         if(ctx.clockMinutes < p.sessionFromMin || ctx.clockMinutes >= p.sessionToMin) return false;
         if(!SigSweepReclaim(ctx, p, plan)) return false;
         score = ScoreSleeveA(ctx, plan);
         if(score <= 6.0) return false;                               // 6 or below: no trade
         tierRisk = (score >= 8.0) ? InpFullTierRiskPct : InpHalfTierRiskPct;
      }

      //--- correlated-group cap (USD / JPY / commodity / European cross)
      string group = CorrelatedGroup(ctx.symbol);
      if(group != "" && EA_GroupRiskPct(group) + tierRisk > InpMaxGroupRiskPct) return false;

      m_sleeve    = sleeve;
      m_lastScore = score;
      m_tierRisk  = tierRisk;
      plan.score  = score * 10.0;
      plan.reason = StringFormat("SURVIVE-S%d %s", sleeve, plan.reason);
      return true;
   }

   int    m_sleeve;
   double m_lastScore;
   double m_tierRisk;

   int    m_hAdxH1[EA_MAX_SYMBOLS];      // sleeve C regime gate: ADX(14) on H1
   double m_spread[EA_MAX_SYMBOLS][240]; // rolling spread samples for the 1.5x gate
   int    m_spreadCount[EA_MAX_SYMBOLS];

   void OnInitStrategy()
   {
      for(int i = 0; i < EA_MAX_SYMBOLS; i++)
      {
         m_hAdxH1[i] = INVALID_HANDLE;
         m_spreadCount[i] = 0;
         for(int j = 0; j < 240; j++) m_spread[i][j] = 0.0;
      }
      for(int i = 0; i < g_eaSymbolCount; i++)
         m_hAdxH1[i] = iADX(g_eaSymbols[i], PERIOD_H1, 14);
   }

   void OnDeinitStrategy()
   {
      for(int i = 0; i < EA_MAX_SYMBOLS; i++)
         if(m_hAdxH1[i] != INVALID_HANDLE) { IndicatorRelease(m_hAdxH1[i]); m_hAdxH1[i] = INVALID_HANDLE; }
   }

   bool IsSleeveCSymbol(const string s)
   {
      return (s == "AUDNZD" || s == "EURGBP" || s == "EURCHF");
   }
   bool IsSleeveBSymbol(const string s)
   {
      return (s == "XAUUSD" || s == "GBPJPY" || s == "GER40" || s == "US30" || s == "DE40" || s == "DAX");
   }
   string CorrelatedGroup(const string s)
   {
      if(s == "EURUSD" || s == "GBPUSD" || s == "AUDUSD") return "EURUSD,GBPUSD,AUDUSD";
      if(s == "USDJPY" || s == "GBPJPY" || s == "EURJPY") return "USDJPY,GBPJPY,EURJPY";
      if(s == "AUDUSD" || s == "USDCAD" || s == "XAUUSD") return "AUDUSD,USDCAD,XAUUSD";
      if(s == "EURGBP" || s == "EURCHF") return "EURGBP,EURCHF";
      return "";
   }

   //--- rolling spread gate: live spread at most 1.5x the recent average
   bool SpreadOk(SEAContext &ctx)
   {
      int slot = -1;
      for(int i = 0; i < g_eaSymbolCount; i++) if(g_eaSymbols[i] == ctx.symbol) slot = i;
      if(slot < 0 || slot >= EA_MAX_SYMBOLS) return true;
      datetime barTime = iTime(ctx.symbol, PERIOD_M5, 0);
      static datetime lastBar[EA_MAX_SYMBOLS];
      if(m_spreadCount[slot] == 0 || lastBar[slot] != barTime)
      {
         lastBar[slot] = barTime;
         for(int i = 239; i > 0; i--) m_spread[slot][i] = m_spread[slot][i - 1];
         m_spread[slot][0] = ctx.spreadPoints;
         m_spreadCount[slot] = (int)MathMin(m_spreadCount[slot] + 1, 240);
      }
      //--- doc 2.2 filter 6: live spread at most 1.5x the 20-day average
      double base = EA_SpreadBaseline(ctx.symbol, 720);
      if(base > 0.0)
      {
         if(ctx.spreadPoints > 1.5 * base)
         {
            EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.1f > 1.5x 20d average %.1f - skip",
                   ctx.symbol, ctx.spreadPoints, base), true);
            return false;
         }
         return true;
      }
      int n = m_spreadCount[slot];
      if(n < 20) return true;                                      // warm-up
      double sum = 0.0;
      for(int i = 0; i < n; i++) sum += m_spread[slot][i];
      double avg = sum / n;
      if(avg > 0.0 && ctx.spreadPoints > 1.5 * avg)
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.1f > 1.5x average %.1f - skip",
                ctx.symbol, ctx.spreadPoints, avg), true);
         return false;
      }
      return true;
   }

   //--- SLEEVE A eight-point score (doc 2.2): range quality, HTF bias,
   //--- geometry (implied by the signal), spread, cost, clean book
   double ScoreSleeveA(SEAContext &ctx, const SSignalPlan &plan)
   {
      double score = 3.0;      // sweep band + wick + displacement already proven
      if(!SpreadOk(ctx)) return 0.0;
      score += 1.0;

      //--- 1. range width within 35-75% of the 20-day median
      double widths[20];
      int    n = 0;
      for(int d = 0; d < 20; d++)
      {
         double h = 0.0, l = 0.0; int bars = 0;
         if(SigRangeForDay(ctx.symbol, PERIOD_M5, 0, 7 * 60, d, h, l, bars)) widths[n++] = h - l;
      }
      if(n >= 5)
      {
         for(int i = 1; i < n; i++)
         {
            double key = widths[i]; int j = i - 1;
            while(j >= 0 && widths[j] > key) { widths[j + 1] = widths[j]; j--; }
            widths[j + 1] = key;
         }
         double median = widths[n / 2];
         double h0 = 0.0, l0 = 0.0; int b0 = 0;
         if(SigRangeForDay(ctx.symbol, PERIOD_M5, 0, 7 * 60, 0, h0, l0, b0))
         {
            double width = h0 - l0;
            if(median > 0.0 && width >= 0.35 * median && width <= 0.75 * median) score += 1.0;
         }
      }
      //--- 2. higher-timeframe bias: H1 50-EMA agrees and is sloping the right way
      double hp[];
      if(EA_BufN(g_eaInd[ctx.index].hEmaH1_50, 0, 1, 5, hp) == 5 && ctx.emaH1_50 > 0.0)
      {
         if(plan.dir > 0 && ctx.mid > ctx.emaH1_50 && hp[0] >= hp[4]) score += 1.0;
         if(plan.dir < 0 && ctx.mid < ctx.emaH1_50 && hp[0] <= hp[4]) score += 1.0;
      }
      //--- 7. cost gate: stop distance at least 10x the round-trip cost
      double cost = EA_CostInR(ctx.symbol, plan.riskDist, g_eaCfg.commissionPerLotRT);
      if(cost <= 0.10) score += 1.0;
      //--- 8. clean book: no correlated position already open
      string group = CorrelatedGroup(ctx.symbol);
      if(group == "" || EA_GroupRiskPct(group) <= 0.0) score += 1.0;
      return score;
   }

   //--- SLEEVE B (doc 3.2): daily ATR in the 60-90th percentile, M15 close
   //--- beyond the 4-hour range with body >= 70%, retest within 6 bars, limit
   //--- at the breakout level, stop 1.20 x ATR(M15) beyond the candle extreme
   bool SleeveBPlan(SEAContext &ctx, SSignalPlan &plan, double &score)
   {
      score = 0.0;
      int nowMin = ctx.clockMinutes;
      bool london = (nowMin >= 7 * 60 && nowMin < 15 * 60 + 30);
      bool ny     = (nowMin >= 13 * 60 + 30 && nowMin < 19 * 60 + 30);
      if(!london && !ny) return false;
      if(!SpreadOk(ctx)) return false;

      //--- filter 1: daily ATR(14) inside the 60-90th percentile of 20 days
      MqlRates d[];
      if(EA_Rates(ctx.symbol, PERIOD_D1, 1, 40, d) < 34) return false;
      double atrNow = 0.0;
      for(int i = 0; i < 14; i++) atrNow += (d[i].high - d[i].low);
      atrNow /= 14.0;
      if(atrNow <= 0.0) return false;
      double dist[20];
      for(int j = 0; j < 20; j++)
      {
         double a = 0.0;
         for(int i = j; i < j + 14; i++) a += (d[i].high - d[i].low);
         dist[j] = a / 14.0;
      }
      for(int i = 1; i < 20; i++)
      {
         double key = dist[i]; int j = i - 1;
         while(j >= 0 && dist[j] > key) { dist[j + 1] = dist[j]; j--; }
         dist[j + 1] = key;
      }
      double p60 = dist[12], p90 = dist[18];
      if(atrNow < p60 || atrNow > p90) return false;
      score += 1.0;

      //--- filter 2/4: M15 close beyond the 4-hour range with body >= 70%
      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 30, r) < 20) return false;
      double hi = -1e18, lo = 1e18;
      for(int i = 3; i < 19; i++)                                   // prior 16 bars = 4 hours
      {
         if(r[i].high > hi) hi = r[i].high;
         if(r[i].low  < lo) lo = r[i].low;
      }
      int    dir = 0;
      int    breakIdx = -1;
      double extreme = 0.0;
      for(int i = 1; i <= 6; i++)                                   // breakout within 6 bars
      {
         double range = r[i].high - r[i].low;
         if(range <= 0.0) continue;
         double body = MathAbs(r[i].close - r[i].open) / range;
         if(body < 0.70) continue;
         if(r[i].close > hi)      { dir = +1; breakIdx = i; extreme = r[i].high; break; }
         if(r[i].close < lo)      { dir = -1; breakIdx = i; extreme = r[i].low;  break; }
      }
      if(dir == 0) return false;
      score += 1.0;

      //--- filter 3: volume expansion (skipped when broker volume is unusable)
      double volSum = 0.0; int volN = 0;
      for(int i = breakIdx + 1; i < breakIdx + 21; i++)
      { if(i < ArraySize(r)) { volSum += (double)r[i].tick_volume; volN++; } }
      if(volN > 0 && volSum > 0.0)
      {
         double volAvg = volSum / volN;
         if(volAvg > 0.0 && (double)r[breakIdx].tick_volume >= 1.3 * volAvg) score += 1.0;
      }
      else score += 1.0;                                            // unusable volume: 4/5 path
      score += 1.0;                                                 // filter 4: spread (checked)
      string grp = CorrelatedGroup(ctx.symbol);
      if(grp == "" || EA_GroupRiskPct(grp) <= 0.0) score += 1.0;    // filter 5: clean book
      if(score < 4.0) return false;

      //--- filter 4: pullback to the breakout level inside 6 M15 candles
      int retestIdx = -1;
      for(int i = breakIdx - 1; i >= 1 && i > breakIdx - 6; i--)
      {
         if(dir > 0 && r[i].low  <= hi) { retestIdx = i; break; }
         if(dir < 0 && r[i].high >= lo) { retestIdx = i; break; }
      }
      if(retestIdx < 0) return false;

      double entry = (dir > 0) ? hi : lo;                           // limit at the breakout level
      double stop  = (dir > 0) ? extreme - 1.20 * ctx.atr : extreme + 1.20 * ctx.atr;
      double risk  = (dir > 0) ? entry - stop : stop - entry;
      if(risk <= 0.0) return false;
      plan.Reset();
      plan.dir      = dir;
      plan.entry    = entry;
      plan.stop     = stop;
      plan.riskDist = risk;
      plan.target   = (dir > 0) ? entry + 2.0 * risk : entry - 2.0 * risk;
      plan.score    = score * 10.0;
      plan.isLimit  = true;
      plan.expiry   = TimeTradeServer() + (datetime)(g_eaCfg.pendingExpiryMinutes * 60);
      plan.reason   = StringFormat("SLEEVE-B breakout-retest %s (score %.0f/5)", ctx.symbol, score);
      return true;
   }

   //--- SLEEVE C (doc 4.2): H1 ADX < 16, 2.0-sigma band touch, wick >= 50%,
   //--- RSI(14) > 70 / < 30, limit at the band, stop 1.0 x ATR beyond the
   //--- touch extreme, target = the 20-period middle band
   bool SleeveCPlan(SEAContext &ctx, SSignalPlan &plan, double &score)
   {
      score = 0.0;
      if(ctx.clockMinutes >= InpSleeveCExitMinute) return false;
      if(ctx.atr <= 0.0 || ctx.rsi14 <= 0.0) return false;
      if(!SpreadOk(ctx)) return false;

      //--- regime: ADX(14) on H1 must be below 16
      double adx = 0.0;
      if(ctx.index >= 0 && ctx.index < EA_MAX_SYMBOLS && m_hAdxH1[ctx.index] != INVALID_HANDLE)
      {
         if(!EA_Buf(m_hAdxH1[ctx.index], 0, 1, adx)) adx = 0.0;
      }
      if(adx > 16.0) return false;

      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 24, r) < 21) return false;
      double sum = 0.0, sum2 = 0.0;
      for(int i = 1; i <= 20; i++) { sum += r[i].close; sum2 += r[i].close * r[i].close; }
      double sma = sum / 20.0;
      double var = MathMax(0.0, sum2 / 20.0 - sma * sma);
      double sd  = MathSqrt(var);
      if(sd <= 0.0) return false;
      double up = sma + 2.0 * sd, lo = sma - 2.0 * sd;

      MqlRates b = r[1];
      bool isLong = false, isShort = false;
      if(b.low  <= lo && b.close > lo && ctx.rsi14 <= 30.0) isLong  = true;
      if(b.high >= up && b.close < up && ctx.rsi14 >= 70.0) isShort = true;
      if(!isLong && !isShort) return false;
      if(isLong  && EA_WickRatio(b, +1) < 0.50) return false;
      if(isShort && EA_WickRatio(b, -1) < 0.50) return false;
      score = 5.0;
      if(!SpreadOk(ctx)) score -= 1.0;
      string grp = CorrelatedGroup(ctx.symbol);
      if(grp != "" && EA_GroupRiskPct(grp) > 0.0) score -= 1.0;
      if(score < 4.0) return false;

      double entry = isLong ? lo : up;                              // limit at the band
      double stop  = isLong ? b.low - 1.0 * ctx.atr : b.high + 1.0 * ctx.atr;
      double risk  = isLong ? entry - stop : stop - entry;
      if(risk <= 0.0) return false;
      plan.Reset();
      plan.dir      = isLong ? +1 : -1;
      plan.entry    = entry;
      plan.stop     = stop;
      plan.riskDist = risk;
      plan.target   = sma;                                          // middle band
      plan.score    = score * 10.0;
      plan.isLimit  = true;
      plan.expiry   = TimeTradeServer() + (datetime)(g_eaCfg.pendingExpiryMinutes * 60);
      plan.reason   = StringFormat("SLEEVE-C band fade %s (ADX %.1f, score %.0f/5)", ctx.symbol, adx, score);
      return true;
   }

   //--- exits: sleeve A 45-minute break-even ladder (40/30 FX, 60/20 XAUUSD)
   //--- with a 2.5 x ATR(H1) runner trail; sleeve C hard flat; session-end rule
   void Manage(SEAContext &ctx)
   {
      //--- sleeve C: hard flat at 06:30
      if(IsSleeveCSymbol(ctx.symbol) && ctx.clockMinutes >= InpSleeveCExitMinute)
      {
         g_eaExec.CancelPending(ctx.symbol, "sleeve C hard flat");
         for(int p = PositionsTotal() - 1; p >= 0; p--)
         {
            ulong tk = PositionGetTicket(p);
            if(tk == 0) continue;
            if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
            if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;
            g_eaExec.Close(tk, "sleeve C hard flat 06:30");
         }
         return;
      }

      for(int t = g_eaTrackCount - 1; t >= 0; t--)
      {
         if(g_eaTrack[t].symbol != ctx.symbol) continue;
         if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;

         int    dir   = g_eaTrack[t].dir;
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double cur   = PositionGetDouble(POSITION_PRICE_CURRENT);
         double risk  = g_eaTrack[t].riskDist;
         if(risk <= 0.0) continue;
         double rMult = ((dir > 0) ? (cur - entry) : (entry - cur)) / risk;

         //--- sleeve A: close at market if +1R has not been reached within 45 min
         if(!IsSleeveBSymbol(ctx.symbol) && !IsSleeveCSymbol(ctx.symbol))
         {
            datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
            int minutesOpen = (int)((TimeTradeServer() - opened) / 60);
            if(rMult < 1.0 && minutesOpen >= InpSleeveATimeStopMin)
            {
               g_eaExec.Close(g_eaTrack[t].ticket, "sleeve A 45-minute time stop");
               continue;
            }
         }

         //--- ladder: +1R closes 40% (60% for XAUUSD) and moves the stop to entry
         bool isXau = (ctx.symbol == "XAUUSD");
         if(rMult >= 1.0 && !g_eaTrack[t].p1Done)
         {
            if(g_eaExec.ClosePartial(g_eaTrack[t].ticket, isXau ? 60.0 : 40.0))
               g_eaTrack[t].p1Done = true;
            else g_eaTrack[t].p1Done = true;
            g_eaExec.Modify(g_eaTrack[t].ticket, PositionGetDouble(POSITION_PRICE_OPEN), 0.0);
            g_eaTrack[t].beMoved = true;
         }
         if(rMult >= 2.0 && !g_eaTrack[t].p2Done)
         {
            if(g_eaExec.ClosePartial(g_eaTrack[t].ticket, isXau ? 20.0 : 30.0))
               g_eaTrack[t].p2Done = true;
            else g_eaTrack[t].p2Done = true;
         }

         //--- runner: chandelier 2.5 x ATR(H1,14) once +2R and the stop is at BE
         if(rMult >= 2.0 && g_eaTrack[t].beMoved)
         {
            MqlRates h[];
            if(EA_Rates(ctx.symbol, PERIOD_H1, 1, 20, h) >= 15)
            {
               double atrH1 = 0.0;
               for(int i = 0; i < 14; i++) atrH1 += (h[i].high - h[i].low);
               atrH1 /= 14.0;
               double extreme = h[0].high;
               if(dir < 0)
               {
                  extreme = h[0].low;
                  for(int i = 1; i < 14; i++) if(h[i].low < extreme) extreme = h[i].low;
               }
               else
                  for(int i = 1; i < 14; i++) if(h[i].high > extreme) extreme = h[i].high;
               double trail = (dir > 0) ? extreme - InpRunnerTrailAtr * atrH1
                                        : extreme + InpRunnerTrailAtr * atrH1;
               double sl = PositionGetDouble(POSITION_SL);
               if((dir > 0 && trail > sl) || (dir < 0 && (sl <= 0.0 || trail < sl)))
                  g_eaExec.Modify(g_eaTrack[t].ticket, eaRoundSafe(ctx.symbol, trail), 0.0);
            }
         }

         //--- session close: flat unless the runner is at least +2R with the stop at BE
         if(ctx.clockMinutes >= 19 * 60 + 30 && !(rMult >= 2.0 && g_eaTrack[t].beMoved))
            g_eaExec.Close(g_eaTrack[t].ticket, "session close");
      }
   }
};

CTriadSurvive g_TriadSurvive;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_TriadSurvive);
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
