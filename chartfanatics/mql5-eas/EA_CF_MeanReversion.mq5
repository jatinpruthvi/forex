//+------------------------------------------------------------------+
//|                                  EA_CF_MeanReversion.mq5         |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Lance Breitstein's Mean Reversion Playbook (PDF, Apr 2025)          |
//| Card    : chartfanatics/todos/mean-reversion-strategy.md  (#22)     |
//| Source  : chartfanatics/pdf/mean-reversion-strategy.pdf             |
//| Magic   : 3225                                                      |
//|                                                                    |
//| THE MODEL: markets are usually efficient; occasionally price is      |
//| pushed far from equilibrium by emotional reactions, forced           |
//| liquidations or sentiment shifts.  The playbook trades the reversal  |
//| once the move has turned - never the falling knife.                  |
//|                                                                    |
//|   (1) the move must be ABNORMAL: the daily context is checked first  |
//|       (today's expansion vs the asset's normal daily range, a        |
//|       volume spike, price far from the 20-period mean);              |
//|   (2) it must be FAST: the intraday displacement travels far in a    |
//|       short window and prints consecutive bars in one direction      |
//|       ("the speed of the move is one of the most important factors");|
//|   (3) entry is the RIGHT SIDE of the reversal: the break of the      |
//|       prior bar's high (after a down-leg that respected prior highs) |
//|       - or the prior bar's low for the down-side reversal;           |
//|   (4) the stop sits where the idea dies: below the capitulation low  |
//|       (above the capitulation high for shorts), and the risk must    |
//|       stay clearly defined;                                          |
//|   (5) the target is the 20-period moving average - the centre of the |
//|       Bollinger Bands and the playbook's equilibrium reference -     |
//|       with realistic R fallbacks because the first bounce often      |
//|       retraces only part of the move;                                 |
//|   (6) management trails the stop below prior bar lows (above prior   |
//|       bar highs for shorts);                                         |
//|   (7) setup QUALITY drives size: more favourable variables -> bigger, |
//|       fewer -> smaller or no trade at all;                            |
//|   (8) short trades carry extra risk management (losses are           |
//|       theoretically unlimited) and extreme single-candle panic        |
//|       entries are taken smaller because risk is less defined.         |
//|                                                                    |
//| `[interpretation]`: the document states the conditions but no         |
//| parameter values, so the expansion / volume / displacement multiples, |
//| the speed window, the streak length, the stop cap and the size        |
//| ladder are labelled here.  "News vs fundamental change" cannot be     |
//| decided by an EA (both look the same on a chart) - the engine's       |
//| calendar gate is an optional input and the caveat is disclosed        |
//| rather than silently dropped.  The 20-period reference is read from   |
//| the execution chart's EMA, which is what the engine carries.          |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "Lance Breitstein mean reversion - abnormal + fast displacement, right-side reversal entry, capitulation stop, 20-period mean target, quality-scaled size"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade   = "AAPL,MSFT,NVDA";  // the playbook trades STOCKS - set your universe
input ulong             InpMagicNumber      = 3225;              // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct          = 0.50;              // Risk per trade (% of equity)
input int               InpStage             = 5;                // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input int               InpServerGmtOffset  = 2;                 // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;     // Log verbosity
input double            InpCommissionPerLotRT = 0.0;             // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.12;            // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;            // Write the engine evidence ledger CSV
input bool              InpNewsGate           = false;           // [interpretation] "news vs fundamental" is not decidable from a chart
//--- (1) abnormality: the daily context
input double InpExpandMult     = 2.00;   // today's range vs the 20-day average range ("large candles compared to normal")
input double InpVolMult        = 1.50;   // "unusually high volume"
input double InpDisplaceAtrD1  = 1.00;   // the displacement must reach this many daily ATRs
input int    InpNormDays       = 20;     // the "normal behaviour" window
//--- (2) speed
input int    InpSpeedBars      = 12;     // the fast-move window (execution bars)
input double InpSpeedAtr       = 3.00;   // the window's net travel, in execution ATRs
input int    InpStreakBars     = 5;      // "several bars in one direction"
input double InpPanicBarAtr    = 3.00;   // "extreme panic reversal": one candle this large replaces the streak
//--- (3)+(4) entry and stop
input int    InpConfirmBars    = 3;      // bars the reversal break may have printed in
input double InpStopBufferAtr  = 0.15;   // buffer beyond the capitulation extreme
input double InpMaxStopPct     = 4.00;   // "risk clearly defined": setups needing a wider stop are skipped
//--- (5)+(6) target and management
input double InpMinRr          = 1.50;   // the bounce may only retrace part of the move - stay realistic
input double InpTargetR        = 2.00;   // fallback when the 20-period mean offers no objective
input int    InpTrailBars      = 3;      // prior-bar trail
//--- (7)+(8) quality sizing
input double InpSizeMid        = 1.25;   // one extra favourable variable
input double InpSizeHigh       = 1.50;   // two or more
input double InpShortSizeMult  = 0.75;   // shorts require additional risk management (doc)
input double InpPanicSizeMult  = 0.50;   // single-candle panic entries: risk less defined (doc)
//--- session
input int    InpSessionStartHour = 14;   // US cash session, London clock
input int    InpSessionStartMin  = 30;   // 09:30 ET
input int    InpSessionEndHour   = 21;   // 16:00 ET
input int    InpSessionEndMin    = 0;
input int    InpMaxTradesPerDay  = 2;    // [interpretation]: the doc sets no daily cap

//+------------------------------------------------------------------+
class CCfMeanReversion : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_MEAN_REVERSION";
      cfg.sourceDoc             = "chartfanatics/pdf/mean-reversion-strategy.pdf (card #22)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;     // [interpretation]: the intraday execution chart
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = 3.0;
      cfg.dailyLossPct          = 1.50;
      cfg.weeklyLossPct         = 3.0;
      cfg.totalDdPct            = 8.0;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 120;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = false;
      cfg.newsFilter            = InpNewsGate;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_mean_reversion_ledger.csv";
      cfg.logLevel              = InpLogLevel;
      cfg.sessionStartHour = InpSessionStartHour;  cfg.sessionStartMin = InpSessionStartMin;
      cfg.sessionEndHour   = InpSessionEndHour;    cfg.sessionEndMin   = InpSessionEndMin;
      cfg.noTradeAfterHour = InpSessionEndHour;    cfg.noTradeAfterMin = InpSessionEndMin;
      cfg.partial1AtR      = 1.0;                 // take the first piece on the way to equilibrium
      cfg.partial1Pct      = 50;
      cfg.breakEvenAtR     = 0.0;                 // the stop follows prior bars (Manage), not an R grid
      cfg.trailAtR         = 0.0;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   void OnInitStrategy()
   {
      m_qualityMult = 1.0;
      m_isShort     = false;
      m_isPanic     = false;
      m_stampSymbol = "";
      m_stampEntry  = 0.0;
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "mean reversion armed: abnormality >= %.2fx the %d-day range on %.1fx volume and %.2f daily ATRs of displacement, speed >= %.1f ATR in %d bars, streak >= %d, stop cap %.1f%%, target the 20-period mean",
             InpExpandMult, InpNormDays, InpVolMult, InpDisplaceAtrD1,
             InpSpeedAtr, InpSpeedBars, InpStreakBars, InpMaxStopPct), true);
   }

   //-------------------------------------------------------------------
   // Abnormal + fast displacement, then the right-side reversal break
   //-------------------------------------------------------------------
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession || ctx.atr <= 0.0 || ctx.atrD1 <= 0.0) return false;

      //--- (1) the daily context: is this move abnormal for the asset at all?
      double expand = 0.0, volMult = 0.0;
      if(!AbnormalDay(ctx, expand, volMult)) return false;

      //--- (2) the displacement: far, fast, and in one direction
      int    dir = 0;
      double capExtreme = 0.0, displacement = 0.0, streak = 0.0;
      if(!Displacement(ctx, dir, capExtreme, displacement, streak)) return false;

      //--- (3) the reversal break: the right side of the move
      int breakBar = 0;
      if(!ReversalBreak(ctx, dir, breakBar)) return false;

      double entry = (dir > 0) ? ctx.ask : ctx.bid;
      double stop  = (dir > 0) ? capExtreme - InpStopBufferAtr * ctx.atr
                               : capExtreme + InpStopBufferAtr * ctx.atr;
      double risk  = (dir > 0) ? (entry - stop) : (stop - entry);
      if(risk <= 0.0) return false;
      //--- "risk clearly defined": a stop wider than the cap is a setup to avoid
      if(entry > 0.0 && (risk / entry) * 100.0 > InpMaxStopPct) return false;

      //--- (5) the equilibrium reference: the 20-period mean (the centre of the Bollinger Bands)
      double mean = ctx.ema20;
      double target = 0.0;
      if(mean > 0.0)
      {
         double toMean = (dir > 0) ? (mean - entry) : (entry - mean);
         if(toMean >= InpMinRr * risk) target = mean;               // the first bounce often stops there
      }
      if(target <= 0.0) target = (dir > 0) ? (entry + InpTargetR * risk) : (entry - InpTargetR * risk);

      //--- (7) quality: count the favourable variables the document lists
      int score = 0;
      if(displacement >= 2.0 * ctx.atrD1) score++;                  // extreme price displacement
      if(expand >= 3.0 * InpExpandMult / 2.0) score++;              // candle expansion beyond the gate
      if(volMult >= 2.0 * InpVolMult / 1.5) score++;                // volume spike
      if(MathAbs(ctx.mid - mean) >= 2.0 * ctx.atr) score++;         // far from equilibrium
      if(streak >= InpStreakBars + 2.0) score++;                    // multiple legs in one direction
      if(expand >= InpExpandMult && volMult >= InpVolMult) score++; // clean, well-defined panic
      if(score < 3) return false;                                  // "lower quality ... avoided entirely"

      //--- (8) size modifiers the doc names
      m_qualityMult = (score >= 5) ? InpSizeHigh : ((score >= 4) ? InpSizeMid : 1.0);
      m_isShort     = (dir < 0);
      m_isPanic     = (streak <= 1.0);                             // the move happened in one candle
      m_stampSymbol = ctx.symbol;
      m_stampEntry  = entry;

      plan.dir      = dir;
      plan.entry    = entry;
      plan.stop     = stop;
      plan.target   = target;
      plan.riskDist = risk;
      plan.barsAgo  = breakBar;
      plan.score    = 60.0 + 8.0 * score;
      plan.isLimit  = false;
      plan.reason   = StringFormat("mean reversion: %s displacement %.2f daily ATRs on %.1fx volume (quality %d), reversal break of the prior bar, stop beyond the capitulation extreme, target the 20-period mean",
                                   (dir > 0) ? "downward" : "upward", displacement / ctx.atrD1, volMult, score);
      return true;
   }

   //--- quality / structural-asymmetry sizing (the doc's own instructions)
   double LotsMultiplier(SEAContext &ctx)
   {
      if(m_stampSymbol != ctx.symbol || m_stampEntry <= 0.0) return 1.0;
      if(MathAbs(ctx.mid - m_stampEntry) > 0.5 * ctx.atr) return 1.0;   // stale plan, not this entry
      double mult = m_qualityMult;
      if(m_isShort) mult *= InpShortSizeMult;
      if(m_isPanic) mult *= InpPanicSizeMult;
      return mult;
   }

   //--- (6) trail the stop below prior bar lows / above prior bar highs
   void Manage(SEAContext &ctx)
   {
      if(ctx.atr <= 0.0) return;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong ticket = PositionGetTicket(p);
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;

         int    dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? +1 : -1;
         double sl  = PositionGetDouble(POSITION_SL);
         double prior = PriorBarExtreme(ctx.symbol, dir);
         if(prior <= 0.0) continue;
         double newSl = (dir > 0) ? prior - InpStopBufferAtr * ctx.atr
                                  : prior + InpStopBufferAtr * ctx.atr;
         bool improves = (dir > 0) ? (newSl > sl) : (newSl < sl);
         if(!improves) continue;
         if(dir > 0 && newSl >= ctx.bid) continue;
         if(dir < 0 && newSl <= ctx.ask) continue;
         if(g_eaExec.Modify(ticket, newSl, PositionGetDouble(POSITION_TP)))
            EA_Log(EA_LOG_EVENTS, StringFormat("stop trails below the prior bar low to %.2f", newSl), true);
      }
   }

private:
   double m_qualityMult;
   bool   m_isShort;
   bool   m_isPanic;
   string m_stampSymbol;
   double m_stampEntry;

   //-------------------------------------------------------------------
   // (1) the daily context: abnormal vs the asset's normal behaviour
   //-------------------------------------------------------------------
   bool AbnormalDay(const SEAContext &ctx, double &expand, double &volMult)
   {
      expand = 0.0; volMult = 0.0;
      MqlRates d[];
      int got = EA_Rates(ctx.symbol, PERIOD_D1, 0, InpNormDays + 4, d);
      if(got < InpNormDays + 3) return false;

      double avgRange = 0.0, avgVol = 0.0;
      for(int i = 1; i <= InpNormDays; i++)
      {
         avgRange += (d[i].high - d[i].low);
         avgVol   += (double)d[i].tick_volume;
      }
      avgRange /= (double)InpNormDays;
      avgVol   /= (double)InpNormDays;
      if(avgRange <= 0.0 || avgVol <= 0.0) return false;

      //--- the active day's range and volume, pace-adjusted early in the session
      double dayRange = d[0].high - d[0].low;
      double elapsed = (double)(ctx.clockMinutes - (InpSessionStartHour * 60 + InpSessionStartMin)) /
                       (double)MathMax(1, (InpSessionEndHour * 60 + InpSessionEndMin) - (InpSessionStartHour * 60 + InpSessionStartMin));
      elapsed = MathMax(0.10, MathMin(1.0, elapsed));              // never compare the first minutes to a full day
      double dayVol = (double)d[0].tick_volume / elapsed;

      expand  = dayRange / avgRange;
      volMult = dayVol / avgVol;
      if(expand < InpExpandMult) return false;                     // "large candles compared to the normal ranges"
      if(volMult < InpVolMult) return false;                       // "high trading volume"
      return true;
   }

   //-------------------------------------------------------------------
   // (2) the displacement: far, fast, one direction
   //-------------------------------------------------------------------
   bool Displacement(const SEAContext &ctx, int &dir, double &capExtreme, double &displacement, double &streak)
   {
      dir = 0; capExtreme = 0.0; displacement = 0.0; streak = 0.0;
      MqlRates m[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, InpSpeedBars + InpStreakBars + 6, m);
      if(got < InpSpeedBars + 4) return false;

      //--- the fast move: net travel over the speed window, against the direction of the streak
      for(int trial = 0; trial < 2; trial++)
      {
         int d = (trial == 0) ? -1 : +1;                             // -1 = a down-leg (look for a long)
         //--- distance travelled in the leg's direction, always positive
         double travel = (d < 0) ? (m[InpSpeedBars].high - m[1].close) : (m[1].close - m[InpSpeedBars].low);
         if(travel < InpSpeedAtr * ctx.atr) continue;

         //--- consecutive bars in the direction of the leg
         double run = 0.0;
         for(int i = 1; i <= InpStreakBars + 4 && i < got - 1; i++)
         {
            bool downBar = (m[i].close < m[i].open);
            if((d < 0 && !downBar) || (d > 0 && downBar)) break;
            run++;
         }
         bool panicCandle = false;
         if(run < InpStreakBars)
         {
            //--- "in rare situations where the move is extremely fast the reversal may occur within a
            //--- single candle": one huge bar replaces the streak, and the entry is taken smaller
            for(int i = 1; i <= InpSpeedBars && i < got - 1; i++)
            {
               if((m[i].high - m[i].low) >= InpPanicBarAtr * ctx.atr) { panicCandle = true; break; }
            }
            if(!panicCandle) continue;                                // neither a streak nor a panic bar
         }

         //--- the capitulation extreme the stop will sit beyond
         double ext = (d < 0) ? DBL_MAX : -DBL_MAX;
         for(int i = 1; i <= InpSpeedBars && i < got - 1; i++)
            ext = (d < 0) ? MathMin(ext, m[i].low) : MathMax(ext, m[i].high);
         if((d < 0 && ext == DBL_MAX) || (d > 0 && ext == -DBL_MAX)) continue;

         dir = -d;                                                   // trade the reversal
         capExtreme = ext;
         displacement = travel;
         streak = run;
         if(panicCandle) streak = 0.0;                               // marks the panic path for sizing
         return true;
      }
      return false;
   }

   //-------------------------------------------------------------------
   // (3) the reversal break: the prior bar's extreme gives way
   //-------------------------------------------------------------------
   bool ReversalBreak(const SEAContext &ctx, const int dir, int &breakBar)
   {
      breakBar = 0;
      MqlRates m[];
      if(EA_Rates(ctx.symbol, g_eaIndTf, 0, InpConfirmBars + 4, m) < InpConfirmBars + 3) return false;
      for(int i = 1; i <= InpConfirmBars; i++)
      {
         //--- a LONG reversal after the down-leg: the bar closes above the prior bar's high
         if(dir > 0 && m[i].close > m[i + 1].high) { breakBar = i; return true; }
         //--- a SHORT reversal after the up-leg: the bar closes below the prior bar's low
         if(dir < 0 && m[i].close < m[i + 1].low) { breakBar = i; return true; }
      }
      return false;
   }

   //--- (6) the prior-bar trail: the lowest low / highest high of the last bars
   double PriorBarExtreme(const string sym, const int dir)
   {
      MqlRates r[];
      int got = EA_Rates(sym, g_eaIndTf, 0, InpTrailBars + 2, r);
      if(got < 4) return 0.0;
      double ext = (dir > 0) ? DBL_MAX : -DBL_MAX;
      for(int i = 1; i <= InpTrailBars && i < got - 1; i++)
         ext = (dir > 0) ? MathMin(ext, r[i].low) : MathMax(ext, r[i].high);
      if((dir > 0 && ext == DBL_MAX) || (dir < 0 && ext == -DBL_MAX)) return 0.0;
      return ext;
   }
};

CCfMeanReversion g_cfMeanReversion;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfMeanReversion);
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
