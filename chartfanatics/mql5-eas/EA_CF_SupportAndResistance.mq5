//+------------------------------------------------------------------+
//|                              EA_CF_SupportAndResistance.mq5       |
//|                                  Copyright 2026, Master Strategy  |
//|                                                                   |
//| ChartFanatics: Support and Resistance (Elite Option Trader)        |
//| "Elite Option Trader's Playbook" - Apr 2025                        |
//| Card    : chartfanatics/todos/support-and-resistance.md    (#37)   |
//| Source  : chartfanatics/pdf/support-and-resistance.pdf             |
//| Magic   : 3240                                                    |
//|                                                                   |
//| "The biggest opportunities in trading come from key support and    |
//|  resistance levels on higher timeframes, especially when they      |
//|  align with major news or data catalysts."                         |
//|                                                                   |
//|   S1  THE LEVELS: "Use weekly and daily charts to find key         |
//|       levels."  "Identify major support/resistance levels from     |
//|       past market highs, lows, and reactions on daily/weekly       |
//|       charts."  -> pivot highs/lows from both series, clustered    |
//|       into levels, weighted by how often they were tested.         |
//|   S2  ROUND NUMBERS: "Round psychological numbers like 5000,       |
//|       6000, or 7000 on SPX tend to act as strong magnets."         |
//|   S3  THE CATALYST: "Only take trades when the technical level and |
//|       fundamental catalyst align."  Catalysts named: FOMC, CPI/NFP,|
//|       earnings, geopolitical.  Two sources: the engine's economic- |
//|       calendar reader (red-folder events) or a volatility-footprint|
//|       proxy (a bar the size of a news bar) so the tester can run   |
//|       without a calendar.                                          |
//|   S4  CONFIRMATION: "A strong bounce or rejection from the level." |
//|       "Multi-day hold or reclaim of the level."  Example 1 adds    |
//|       "two higher weekly lows following the initial test";         |
//|       Example 2 adds "reclaimed and stabilized above" the level.   |
//|   S5  SIZING FOR ZERO: "risk what you're comfortable losing        |
//|       completely, rather than using a tight stop ... Instead of    |
//|       risking $5,000 with a 20% stop, size your total trade to     |
//|       $1,000 ... This allows you to hold through volatility and    |
//|       target massive R multiples (5x, 10x+)."  -> tiny risk, wide  |
//|       stop, no break-even, no trailing ("avoids premature exits"), |
//|       partials at 5R and 10R.                                      |
//|                                                                   |
//| `[interpretation]`: the pivot width, the clustering tolerance, the |
//| round-number step, the approach window, the touch and bounce        |
//| tolerances, the hold bars, the higher-low count, the catalyst       |
//| lookback, the volatility-proxy multiple, the wide stop percentage   |
//| (the document's own 20% example), the time-stop horizon and the     |
//| level cooldown are inputs and labelled - the document draws them    |
//| by eye.                                                            |
//|                                                                   |
//| Disclosed, not faked: this is an OPTIONS playbook (weekly/monthly  |
//| contracts).  MetaTrader has no SPX options chain, so the EA trades  |
//| the underlying index/CFD and expresses the contract horizon as the  |
//| time stop; the option premium/delta mechanics stay out of scope.    |
//| Earnings dates are not in the terminal calendar - the volatility    |
//| proxy covers them; the "clear shift in sentiment" is read as the    |
//| level reaction itself.                                              |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics Support and Resistance - higher-timeframe levels + catalyst + confirmation, sized for zero with 5R/10R targets"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade     = "US500,US100";     // Universe (the playbook trades SPX options - the index itself here)
input ulong             InpMagicNumber        = 3240;             // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpZeroRiskPct        = 0.25;             // [interpretation] "Size for Zero" risk per trade (% of equity)
input int               InpStage              = 5;                // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input double            InpMaxSpreadPoints    = 8.0;              // Spread gate in points (0 = off)
input double            InpDailyLossPct       = 1.50;             // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset    = 2;                // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel           = EA_LOG_EVENTS;    // Log verbosity
input double            InpCommissionPerLotRT = 0.0;              // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.10;             // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;             // Write the engine evidence ledger CSV

//--- the levels (S1/S2)
input ENUM_TIMEFRAMES   InpHighTf              = PERIOD_W1;        // The higher timeframe of the playbook ("weekly and daily")
input int               InpPivotSide          = 2;                // [interpretation] Bars each side of a swing pivot
input double            InpClusterPct         = 0.50;             // [interpretation] Levels closer than this are one level
input double            InpApproachPct        = 2.00;             // [interpretation] "Price reaching a key level" window (%)
input double            InpRoundStep          = 500.0;            // [interpretation] "Round psychological numbers" step (5000/6000/7000 on SPX)
input int               InpMinTouches         = 2;                // [interpretation] A major level was tested at least this often
input int               InpMaxLevels          = 12;               // Working set of levels kept around price

//--- confirmation (S4)
input double            InpTouchPct           = 0.35;             // [interpretation] How close counts as "reaching" the level (%)
input double            InpBouncePct          = 0.50;             // [interpretation] Close back beyond the level = "strong bounce or rejection"
input int               InpHoldBars           = 2;                // "Multi-day hold or reclaim" - completed bars on the far side
input int               InpHigherLowsReq      = 2;                // "two higher weekly lows following the initial test"
input bool              InpAllowBreakouts     = true;             // Example 2: the reclaim-and-stabilize continuation
input bool              InpAllowRejections    = true;             // The general "strong bounce or rejection"

//--- the catalyst (S3)
input bool              InpRequireCatalyst    = true;             // "Avoid trading key levels without a strong catalyst"
input int               InpCatalystMode       = 0;                // 0 = volatility-footprint proxy (tester-safe), 1 = engine news cache
input int               InpCatalystDays       = 3;                // [interpretation] How recent the catalyst bar must be
input double            InpCatalystRangeAtr   = 1.50;             // [interpretation] A news bar's range vs its 20-bar average
input int               InpCatalystLookbackH  = 48;               // [interpretation] How recent a calendar event may be (hours)
input string            InpNewsFile           = "cf_red_news.csv"; // Red-folder CSV for the engine news cache (live/tester)

//--- sizing for zero (S5)
input double            InpWideStopPct        = 20.0;             // "a 20% stop" - the loss you accept completely
input double            InpTp1R               = 5.0;              // "target massive R multiples (5x, 10x+)"
input double            InpTp2R               = 10.0;             // ... the second target
input int               InpMaxHoldDays        = 30;               // The monthly contract's horizon (0 = no time stop)

//--- session (entries inside the cash session; the analysis is daily/weekly)
input int               InpSessionStartHour   = 14;               // US cash open, London time (09:30 ET)
input int               InpSessionStartMin    = 30;
input int               InpSessionEndHour     = 21;               // US cash close
input int               InpSessionEndMin      = 0;
input int               InpMaxTradesPerDay    = 1;                // "not every day is a trade day"

//--- level bookkeeping
input int               InpLevelCooldownDays  = 10;               // [interpretation] Do not re-trade the same level for this long

//+------------------------------------------------------------------+
struct SKeyLevel
{
   double price;
   int    touches;      // how often the market reacted there
   bool   weekly;       // confirmed on the higher timeframe
   bool   roundNum;     // a psychological round number ("act as strong magnets")
   bool   isSupport;    // below price = support, above = resistance (operational definition)
   double score;
};

struct SLevelSet
{
   SKeyLevel lv[16];
   int       count;
};

//+------------------------------------------------------------------+
class CCfSupportResistance : public CEAStrategy
{
public:
   void OnInitStrategy()
   {
      m_pendingLevel = 0.0;
      m_planLevel    = 0.0;
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "Support/Resistance armed: %s levels on %s + %s, catalyst mode %d, size-for-zero risk %.2f%% with a %.0f%% wide stop, targets %.0fR/%.0fR",
             EnumToString(InpHighTf), EnumToString(PERIOD_D1), EnumToString(InpHighTf),
             InpCatalystMode, InpZeroRiskPct, InpWideStopPct, InpTp1R, InpTp2R), true);
   }

   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_SUPPORT_RESISTANCE";
      cfg.sourceDoc             = "chartfanatics/pdf/support-and-resistance.pdf (card #37)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpZeroRiskPct;         // S5: the loss you accept completely
      cfg.signalTimeframe       = PERIOD_M5;              // execution frame; the analysis reads D1/W1 directly
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = 4.0;
      cfg.totalDdPct            = 10.0;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;     // "not every day is a trade day"
      cfg.maxOpenPositions      = 1;                      // high-conviction, one at a time
      cfg.minSecondsBetweenTrades = 3600;
      cfg.sessionStartHour      = InpSessionStartHour;
      cfg.sessionStartMin       = InpSessionStartMin;
      cfg.sessionEndHour        = InpSessionEndHour;
      cfg.sessionEndMin         = InpSessionEndMin;
      cfg.sessionEndFlat        = false;                  // the thesis is the multi-day level, not the day
      cfg.fridayFlat            = false;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = false;
      //--- S5: "This allows you to hold through volatility and target massive R multiples"
      cfg.breakEvenAtR          = 0.0;                    // no break-even - it "avoids premature exits"
      cfg.trailAtR              = 0.0;                    // no trailing
      cfg.partial1AtR           = InpTp1R;                // 5x
      cfg.partial1Pct           = 50.0;
      cfg.partial2AtR           = InpTp2R;                // 10x+
      cfg.partial2Pct           = 50.0;
      cfg.timeStopMinutes       = InpMaxHoldDays * 24 * 60;   // the monthly contract's horizon
      cfg.timeStopUnlessR       = InpTp1R;                    // once it works, let it run for the 10R
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;
      //--- S3: the engine's red-folder reader; the calendar is live-only, the CSV covers the tester
      cfg.newsFilter            = InpRequireCatalyst;
      cfg.newsUseCalendar       = (InpCatalystMode == 1);
      cfg.newsFile              = InpNewsFile;
      cfg.newsFailClosed        = false;                  // a missing calendar must not stop the tester
      cfg.newsBeforeMin         = 15;                     // do not open into the print
      cfg.newsAfterMin          = 15;                     // ... nor into the first minutes of it
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_support_resistance_ledger.csv";
      cfg.logLevel              = InpLogLevel;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   //+----------------------------------------------------------------+
   //| One level, one decision: which side of it is price on, has the |
   //| market reached it, did the catalyst print, and how did the      |
   //| completed day answer?                                           |
   //+----------------------------------------------------------------+
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(ctx.atr <= 0.0) return false;

      MqlRates d[];
      int dGot = EA_Rates(ctx.symbol, PERIOD_D1, 0, 90, d);
      if(dGot < 30) return false;
      MqlRates w[];
      int wGot = EA_Rates(ctx.symbol, InpHighTf, 0, 12, w);
      if(wGot < 4) return false;

      SLevelSet set;
      if(!BuildLevels(ctx, d, dGot, w, wGot, set)) return false;
      MaybeDumpLevels(ctx, set, d[0].time);

      //--- the catalyst gate (S3) - checked before the level loop so the log tells the truth
      int minsAgo = -1;
      if(!CatalystRecent(ctx, d, dGot, minsAgo)) return false;
      //--- never open INTO the print - the engine's own red-folder blackout
      if(EA_NewsBlocked()) return false;
      if(!ctx.inSession) return false;

      double best = -1.0;
      SSignalPlan p;
      for(int i = 0; i < set.count; i++)
      {
         SKeyLevel lv = set.lv[i];
         if(LevelOnCooldown(ctx, lv.price)) continue;
         p.Reset();
         if(PlanAtLevel(ctx, lv, d, dGot, w, wGot, minsAgo, p) && p.score > best) { plan = p; best = p.score; }
      }
      //--- arm the level cooldown only for a plan that can actually be filled (no position yet);
      //--- if the engine rejects the plan, Manage() clears the pending level on the next tick.
      if(plan.dir != 0 && EA_FindPosition(ctx.symbol, -1) == 0 && EA_FindPosition(ctx.symbol, +1) == 0)
         m_pendingLevel = m_planLevel;
      return (plan.dir != 0);
   }

   //+----------------------------------------------------------------+
   //| The contract horizon (the monthly option's life) and the level |
   //| bookkeeping: once a plan becomes a position the level goes on   |
   //| cooldown, so the same magnet is not re-traded every day.        |
   //+----------------------------------------------------------------+
   void Manage(SEAContext &ctx)
   {
      ulong ticket = EA_FindPosition(ctx.symbol, -1);
      if(ticket == 0) ticket = EA_FindPosition(ctx.symbol, +1);
      if(ticket == 0)
      {
         m_pendingLevel = 0.0;
         return;
      }
      if(m_pendingLevel > 0.0)
      {
         LevelCooldownSet(ctx, m_pendingLevel);
         EA_Log(EA_LOG_EVENTS, StringFormat("Support/Resistance: the level %.2f is on cooldown for %d day(s) after the fill",
                m_pendingLevel, InpLevelCooldownDays), true);
         m_pendingLevel = 0.0;
      }
   }

private:
   double m_pendingLevel;   // the level of the plan that just became a position (cooldown bookkeeping)
   double m_planLevel;      // the level the plan being assembled sits on

   //+----------------------------------------------------------------+
   //| Level construction (S1/S2): pivots on daily and weekly bars,     |
   //| clustered, weighted by touches, weekly confirmation and the      |
   //| round-number magnet.                                             |
   //+----------------------------------------------------------------+
   bool BuildLevels(const SEAContext &ctx, const MqlRates &d[], const int dGot,
                    const MqlRates &w[], const int wGot, SLevelSet &set)
   {
      //--- room for a year of daily pivots plus the weekly ones
      int cap = 256;
      double price_[256];
      int    touch_[256];
      bool   weekly_[256];
      bool   round_[256];
      int    n = 0;

      //--- daily pivots ("past market highs, lows, and reactions on daily/weekly charts")
      int side = (int)MathMax(1, InpPivotSide);
      for(int i = side; i + side < dGot - 1 && n < cap; i++)
      {
         bool ph = true, pl = true;
         for(int k = 1; k <= side; k++)
         {
            if(d[i].high <= d[i - k].high || d[i].high <= d[i + k].high) ph = false;
            if(d[i].low  >= d[i - k].low  || d[i].low  >= d[i + k].low)  pl = false;
         }
         if(ph) AddLevel(ctx, price_, touch_, weekly_, round_, n, cap, d[i].high, false);
         if(pl) AddLevel(ctx, price_, touch_, weekly_, round_, n, cap, d[i].low,  false);
      }
      //--- weekly pivots: the "major" half of the instruction
      int wside = (int)MathMax(1, InpPivotSide);
      for(int i = wside; i + wside < wGot - 1 && n < cap; i++)
      {
         bool ph = true, pl = true;
         for(int k = 1; k <= wside; k++)
         {
            if(w[i].high <= w[i - k].high || w[i].high <= w[i + k].high) ph = false;
            if(w[i].low  >= w[i - k].low  || w[i].low  >= w[i + k].low)  pl = false;
         }
         if(ph) AddLevel(ctx, price_, touch_, weekly_, round_, n, cap, w[i].high, true);
         if(pl) AddLevel(ctx, price_, touch_, weekly_, round_, n, cap, w[i].low,  true);
      }
      if(n == 0) return false;

      //--- keep the levels that price can actually reach, ranked
      set.count = 0;
      double px = ctx.bid;
      double near = InpApproachPct / 100.0;
      int keepMax = (int)MathMin(InpMaxLevels, 16);
      for(int i = 0; i < n; i++)
      {
         if(keepMax <= 0) return false;
         if(MathAbs(price_[i] - px) / px > near) continue;
         if(set.count >= keepMax) break;
         if(touch_[i] < InpMinTouches && !weekly_[i]) continue;   // "major support/resistance levels"
         set.lv[set.count].price    = price_[i];
         set.lv[set.count].touches  = touch_[i];
         set.lv[set.count].weekly   = weekly_[i];
         set.lv[set.count].roundNum = round_[i];
         set.lv[set.count].isSupport = (price_[i] < px);
         double sc = 80.0;                                  // the document's own alignment figure
         sc += MathMin(6.0, 2.0 * touch_[i]);               // reactions at the level
         if(weekly_[i]) sc += 4.0;                          // "weekly and daily charts"
         if(round_[i])  sc += 4.0;                          // "strong magnets"
         set.lv[set.count].score = sc;
         set.count++;
      }
      //--- sort by score (a tiny insertion sort over at most 16 entries)
      for(int a = 1; a < set.count; a++)
      {
         SKeyLevel key = set.lv[a];
         int b = a - 1;
         while(b >= 0 && set.lv[b].score < key.score)
         {
            set.lv[b + 1] = set.lv[b];
            b--;
         }
         set.lv[b + 1] = key;
      }
      return (set.count > 0);
   }

   //--- cluster a price into the level book (within InpClusterPct) or start a new one;
   //--- a level that merges with daily+weekly evidence is marked weekly, and a price
   //--- that sits on a round psychological number is marked as the magnet it is.
   void AddLevel(const SEAContext &ctx, double &price_[], int &touch_[], bool &weekly_[], bool &round_[],
                 int &n, const int cap, const double p, const bool isWeekly)
   {
      for(int i = 0; i < n; i++)
      {
         if(MathAbs(price_[i] - p) / p <= InpClusterPct / 100.0)
         {
            price_[i] = (price_[i] * touch_[i] + p) / (touch_[i] + 1);   // running mean of the cluster
            touch_[i] = touch_[i] + 1;
            if(isWeekly) weekly_[i] = true;
            if(IsRoundNumber(p)) round_[i] = true;
            return;
         }
      }
      if(n >= cap) return;
      price_[n]  = p;
      touch_[n]  = 1;
      weekly_[n] = isWeekly;
      round_[n]  = IsRoundNumber(p);
      n++;
   }

   //--- "Round psychological numbers like 5000, 6000, or 7000 on SPX tend to act as strong magnets"
   bool IsRoundNumber(const double p)
   {
      if(InpRoundStep <= 0.0) return false;
      double r = MathRound(p / InpRoundStep) * InpRoundStep;
      return (MathAbs(p - r) / p <= 0.20 / 100.0);
   }

   //+----------------------------------------------------------------+
   //| The catalyst gate (S3).                                         |
   //|  mode 1: the engine's news cache (terminal calendar live, CSV   |
   //|          in the tester) must hold a red-folder event in the last |
   //|          InpCatalystLookbackH hours - "post-catalyst".           |
   //|  mode 0: the volatility footprint - the events the document     |
   //|          names (FOMC, CPI/NFP, earnings) all print one wide bar; |
   //|          a recent bar that size is the observable alignment.     |
   //+----------------------------------------------------------------+
   bool CatalystRecent(const SEAContext &ctx, const MqlRates &d[], const int dGot, int &minsAgo)
   {
      minsAgo = -1;
      if(!InpRequireCatalyst) return true;

      if(InpCatalystMode == 1)
      {
         EA_LoadNewsCache();                       // the engine's reader (calendar or CSV)
         if(g_eaNewsCount == 0)
         {
            EA_Log(EA_LOG_EVENTS, "Support/Resistance: no red-folder events loaded - no catalyst evidence, no new risk");
            return false;
         }
         datetime nowRef = EA_NewsNowRef();
         for(int i = 0; i < g_eaNewsCount; i++)
         {
            long secs = (long)nowRef - (long)g_eaNewsTimes[i];   // positive = the event already printed
            if(secs < 0) continue;                                // future event: not a catalyst yet
            if(secs <= (long)InpCatalystLookbackH * 3600)
            {
               minsAgo = (int)MathFloor((double)secs / 60.0);
               return true;
            }
         }
         return false;
      }

      //--- mode 0: a news-sized bar in the last InpCatalystDays completed sessions
      double sum = 0.0;
      int cnt = 0;
      for(int i = 2; i < dGot && cnt < 20; i++) { sum += (d[i].high - d[i].low); cnt++; }
      if(cnt < 10) return false;
      double avg = sum / cnt;
      if(avg <= 0.0) return false;
      int look = (int)MathMax(1, InpCatalystDays);
      for(int i = 1; i <= look && i < dGot; i++)
      {
         if((d[i].high - d[i].low) >= InpCatalystRangeAtr * avg)
         {
            minsAgo = i * 1440;                     // completed session i days back
            return true;
         }
      }
      return false;
   }

   //+----------------------------------------------------------------+
   //| One level, all four doc rules: reached, catalyst-aligned,       |
   //| confirmed, and sized for zero.                                  |
   //+----------------------------------------------------------------+
   bool PlanAtLevel(const SEAContext &ctx, const SKeyLevel &lv,
                    const MqlRates &d[], const int dGot, const MqlRates &w[], const int wGot,
                    const int minsAgo, SSignalPlan &p)
   {
      double L = lv.price;
      if(L <= 0.0 || dGot < InpHoldBars + 3 || wGot < InpHigherLowsReq + 2) return false;

      double touch = InpTouchPct / 100.0;
      double bo    = InpBouncePct / 100.0;
      double lastClose = d[1].close;

      //--- "Multi-day hold or reclaim of the level" - completed closes on the far side
      int heldAbove = 0, heldBelow = 0;
      for(int i = 1; i <= InpHoldBars && i < dGot; i++)
      {
         if(d[i].close >= L * (1.0 + bo)) heldAbove++;
         if(d[i].close <= L * (1.0 - bo)) heldBelow++;
      }

      int dir = 0;
      string kind = "";
      double stop = 0.0, risk = 0.0, score = lv.score;

      if(lv.isSupport)
      {
         //--- "A strong bounce ... from the level": the day reached it and closed back above
         bool touched = (d[1].low <= L * (1.0 + touch));
         if(InpAllowRejections && touched && lastClose >= L * (1.0 + bo))
         {
            if(HigherLowsAfterTest(w, wGot, L) < InpHigherLowsReq) return false;   // Example 1's own context
            dir = +1; kind = "bounce off support";
         }
         //--- the mirror: the level failed and held below it
         else if(InpAllowBreakouts && heldBelow >= InpHoldBars)
         {
            dir = -1; kind = "support lost and held below";
            score += 2.0;
         }
         else return false;
      }
      else
      {
         //--- "A strong ... rejection from the level": the day reached it and closed back below
         bool touched = (d[1].high >= L * (1.0 - touch));
         if(InpAllowRejections && touched && lastClose <= L * (1.0 - bo))
         {
            dir = -1; kind = "rejection at resistance";
         }
         //--- Example 2: "the price reclaimed and stabilized above this level" -> long continuation
         else if(InpAllowBreakouts && heldAbove >= InpHoldBars)
         {
            dir = +1; kind = "reclaim and hold above resistance";
            score += 4.0;                                 // the document's own breakout example
         }
         else return false;
      }

      //--- S5: "size your total trade to $1,000 - fully acceptable loss if the trade goes to zero"
      double entry = (dir > 0) ? ctx.ask : ctx.bid;
      stop = (dir > 0) ? entry * (1.0 - InpWideStopPct / 100.0)
                       : entry * (1.0 + InpWideStopPct / 100.0);   // "a 20% stop" in the example
      if(stop <= 0.0) return false;
      risk = MathAbs(entry - stop);
      if(risk <= 0.0) return false;

      p.dir      = dir;
      p.entry    = entry;
      p.stop     = stop;
      p.target   = (dir > 0) ? entry + InpTp2R * risk : entry - InpTp2R * risk;   // "target massive R multiples"
      p.riskDist = risk;
      p.barsAgo  = 1;
      p.isLimit  = false;
      p.score    = MathMin(score + (minsAgo >= 0 && minsAgo <= 2880 ? 2.0 : 0.0), 99.0);
      m_planLevel = L;
      p.reason   = StringFormat("%s at %.2f (%s%s, %d touches, catalyst %s) -> %s",
                                kind, L,
                                lv.weekly ? "weekly " : "daily ",
                                lv.roundNum ? "round-number magnet" : "pivot level",
                                lv.touches,
                                (minsAgo < 0 ? "screened" : StringFormat("%dh ago", (int)(minsAgo / 60))),
                                (dir > 0 ? "LONG" : "SHORT"));
      return true;
   }

   //--- Example 1: "Price formed two higher weekly lows following the initial test"
   int HigherLowsAfterTest(const MqlRates &w[], const int wGot, const double L)
   {
      int lows = 0;
      double prev = 0.0;
      for(int i = wGot - 1; i >= 1; i--)                  // oldest -> newest
      {
         if(MathAbs(w[i].low - L) / L > InpApproachPct / 100.0) continue;   // only the tests of THIS level
         if(prev > 0.0 && w[i].low > prev) lows++;
         prev = w[i].low;
      }
      return lows;
   }

   //+----------------------------------------------------------------+
   //| Level cooldown (global variables survive restarts)              |
   //+----------------------------------------------------------------+
   string CooldownKey(const SEAContext &ctx, const string tag)
   {
      return "CFSR_" + IntegerToString((long)g_eaCfg.magic) + "_" + ctx.symbol + tag;
   }
   bool LevelOnCooldown(const SEAContext &ctx, const double L)
   {
      string key = CooldownKey(ctx, "_LV");
      if(!GlobalVariableCheck(key)) return false;
      double lp = GlobalVariableGet(key);
      if(L <= 0.0 || MathAbs(lp - L) / L > InpClusterPct / 100.0) return false;
      datetime ts = (datetime)GlobalVariableGet(CooldownKey(ctx, "_TS"));
      return (TimeTradeServer() - ts < (datetime)(InpLevelCooldownDays * 86400));
   }
   void LevelCooldownSet(const SEAContext &ctx, const double L)
   {
      GlobalVariableSet(CooldownKey(ctx, "_LV"), L);
      GlobalVariableSet(CooldownKey(ctx, "_TS"), (double)(long)TimeTradeServer());
   }

   //+----------------------------------------------------------------+
   //| The level book as evidence: one small CSV row per level per day |
   //+----------------------------------------------------------------+
   void MaybeDumpLevels(const SEAContext &ctx, const SLevelSet &set, const datetime dayStamp)
   {
      string f = "cf_support_resistance_levels.csv";
      string key = "CFSRLV_" + IntegerToString((long)g_eaCfg.magic) + "_" + ctx.symbol;
      if(GlobalVariableGet(key) == (double)dayStamp) return;
      GlobalVariableSet(key, (double)dayStamp);

      int fh = FileOpen(f, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
      if(fh == INVALID_HANDLE) return;
      FileSeek(fh, 0, SEEK_END);
      if(FileTell(fh) == 0)
         FileWrite(fh, "day", "symbol", "level", "support", "weekly", "round_number", "touches", "score");
      for(int i = 0; i < set.count; i++)
         FileWrite(fh, TimeToString(dayStamp, TIME_DATE), ctx.symbol,
                   DoubleToString(set.lv[i].price, EA_Digits(ctx.symbol)),
                   (set.lv[i].isSupport ? "yes" : "no"),
                   (set.lv[i].weekly ? "yes" : "no"),
                   (set.lv[i].roundNum ? "yes" : "no"),
                   IntegerToString(set.lv[i].touches),
                   DoubleToString(set.lv[i].score, 1));
      FileClose(fh);
   }
};

CCfSupportResistance g_cfSupportResistance;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfSupportResistance);
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
