//+------------------------------------------------------------------+
//| EA_studyarena_round4_contestant_c__1_.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 4C(1) - 23 levers: regime parameter sets, streaks, EOM harvest, CVD and OB scoring
//| Source document : docs_v1/docs/coreIdea/studyarena-round4-contestant-c (1).md
//| Tracker entry   : #43  |  Magic: 2012
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound4C2 class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 4C(1) - 23 levers: regime parameter sets, streaks, EOM harvest, CVD and OB scoring"
#property description "Source: docs_v1/docs/coreIdea/studyarena-round4-contestant-c (1).md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,EURGBP,USDJPY,XAUUSD";      // Comma separated universe
input double          InpRiskPct          = 1.0;   // Base risk per trade (% of equity)
input int             InpMaxTradesPerDay  = 5;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2012; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpStrongTrendRisk    = 2.50;  // ADX>35: 2.5% risk, 0.5R stop
input double InpModerateTrendRisk  = 1.50;  // 25<ADX<35: 1.5% risk, 0.7R stop
input double InpLowVolRangeRisk    = 1.00;  // ATR<0.6x median: 1.0%, 0.4R stop
input double InpHighVolRangeRisk   = 1.00;  // high-vol range: 1.0%, 1.0R stop
input double InpNewsShockRisk      = 0.50;  // ATR>2x median: 0.5%, 1.2R stop
input int    InpStreakReduceAfter  = 3;     // Cut risk after N consecutive losses
input double InpStreakReduceFactor = 0.50;  // Streak de-risking multiplier
input double InpSpreadDivergenceX  = 2.00;  // Spread > 2x median = divergence signal

//+------------------------------------------------------------------+
//| Strategy: Round 4C(1) - 23 levers: regime parameter sets, streaks, EOM harvest, CVD and OB scoring
//+------------------------------------------------------------------+
class CRound4C2 : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R4C2_REGIME_LEVERS";
      cfg.sourceDoc             = "docs_v1/docs/coreIdea/studyarena-round4-contestant-c (1).md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;             // scaled by the regime table
      cfg.signalTimeframe       = PERIOD_M15;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 600;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.timeStopMinutes       = 120;
      cfg.breakEvenAtR          = 1.0;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- Lever 4: spread-divergence signal (spread blow-out with direction = information)
      if(SpreadDivergence(ctx, plan)) return true;

      //--- Lever 5: cumulative tick-volume divergence at the prior swing
      if(CvdDivergence(ctx, plan)) return true;

      //--- Lever 6: order-block quality scoring engine (only A/B grade blocks trade)
      SOrderBlockParams ob;
      ob.Reset();
      ob.lookbackBars = 16; ob.displacementBody = 0.50;
      ob.touchTolAtr = 0.25; ob.stopBufferAtr = 0.10; ob.targetR = 2.0;
      ob.requireHtfBias = false;
      SSignalPlan base;
      if(!SigOrderBlockRetest(ctx, ob, base)) return false;
      double quality = ObQualityScore(ctx, base);
      if(quality < 6.0) return false;
      plan = base;
      plan.score  = quality * 10.0;
      plan.reason = StringFormat("R4C2-OBQUALITY(%.0f/12) %s", quality, plan.reason);
      ApplyRegime(plan);
      return true;
   }

   double m_regimeRisk;
   double m_regimeStop;

   //--- Lever 1: regime parameter table
   void RegimeParams(SEAContext &ctx)
   {
      double medianAtr = MedianAtr(ctx);
      m_regimeRisk = InpModerateTrendRisk;
      m_regimeStop = 0.70;
      if(ctx.adx14 > 35.0)                 { m_regimeRisk = InpStrongTrendRisk;   m_regimeStop = 0.50; }
      else if(ctx.adx14 > 25.0)            { m_regimeRisk = InpModerateTrendRisk; m_regimeStop = 0.70; }
      else if(ctx.adx14 < 18.0 && medianAtr > 0.0 && ctx.atr < 0.60 * medianAtr)
                                           { m_regimeRisk = InpLowVolRangeRisk;    m_regimeStop = 0.40; }
      else if(ctx.adx14 < 18.0)            { m_regimeRisk = InpHighVolRangeRisk;   m_regimeStop = 1.00; }
      if(medianAtr > 0.0 && ctx.atr > 2.0 * medianAtr)
                                           { m_regimeRisk = InpNewsShockRisk;      m_regimeStop = 1.20; }
   }

   void ApplyRegime(SSignalPlan &plan)
   {
      if(plan.riskDist <= 0.0 || m_regimeStop <= 0.0) return;
      double stop = m_regimeStop * plan.riskDist;
      plan.stop     = (plan.dir > 0) ? plan.entry - stop : plan.entry + stop;
      plan.riskDist = stop;
   }

   double MedianAtr(SEAContext &ctx)
   {
      double av[];
      if(EA_BufN(g_eaInd[ctx.index].hAtr, 0, 1, 60, av) < 30) return 0.0;
      double s[];
      ArrayResize(s, ArraySize(av));
      ArrayCopy(s, av);
      ArraySort(s);
      return s[ArraySize(s) / 2];
   }

   //--- Lever 2: consecutive-streak exploitation (de-risk after 3 losses)
   int LosingStreak()
   {
      if(!HistorySelect(TimeCurrent() - 7 * 24 * 3600, TimeCurrent())) return 0;
      int streak = 0;
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagicNumber) continue;
         if(HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
         double profit = HistoryDealGetDouble(t, DEAL_PROFIT) +
                         HistoryDealGetDouble(t, DEAL_SWAP) +
                         HistoryDealGetDouble(t, DEAL_COMMISSION);
         if(profit < 0.0) streak++;
         else break;
         if(streak >= 5) break;
      }
      return streak;
   }

   //--- Lever 5: CVD proxy divergence
   bool CvdDivergence(SEAContext &ctx, SSignalPlan &plan)
   {
      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 12, r) < 8) return false;
      double cvd = 0.0;
      for(int i = 0; i < 6; i++)
         cvd += (r[i].close >= r[i].open ? 1.0 : -1.0) * (double)r[i].tick_volume;
      double swingLo = r[1].low, swingHi = r[1].high;
      for(int i = 1; i <= 6; i++) { swingLo = MathMin(swingLo, r[i].low); swingHi = MathMax(swingHi, r[i].high); }
      bool bull = (r[0].low < swingLo && ctx.mid > swingLo && cvd > 0.0);
      bool bear = (r[0].high > swingHi && ctx.mid < swingHi && cvd < 0.0);
      if(!bull && !bear) return false;
      int dir = bull ? +1 : -1;
      plan.Reset();
      plan.dir      = dir;
      plan.entry    = ctx.mid;
      plan.riskDist = 0.80 * ctx.atr;
      if(plan.riskDist <= 0.0) return false;
      plan.stop     = (dir > 0) ? plan.entry - plan.riskDist : plan.entry + plan.riskDist;
      plan.target   = (dir > 0) ? plan.entry + 2.0 * plan.riskDist : plan.entry - 2.0 * plan.riskDist;
      plan.score    = 60.0;
      plan.reason   = "R4C2-CVDDIVERGENCE";
      ApplyRegime(plan);
      return true;
   }

   //--- Lever 4: spread divergence (2x normal spread while price trends)
   bool SpreadDivergence(SEAContext &ctx, SSignalPlan &plan)
   {
      PushSpread(ctx.spreadPoints);
      double med = MedianSpread();
      if(med <= 0.0 || ctx.spreadPoints < InpSpreadDivergenceX * med) return false;
      MqlRates r[];
      if(EA_Rates(ctx.symbol, (ENUM_TIMEFRAMES)g_eaCfg.signalTimeframe, 1, 3, r) < 2) return false;
      double body = r[0].close - r[0].open;
      if(ctx.atr <= 0.0 || MathAbs(body) < 0.30 * ctx.atr) return false;
      int dir = (body > 0.0) ? +1 : -1;
      plan.Reset();
      plan.dir      = dir;
      plan.entry    = ctx.mid;
      plan.riskDist = 0.50 * ctx.atr;
      plan.stop     = (dir > 0) ? plan.entry - plan.riskDist : plan.entry + plan.riskDist;
      plan.target   = (dir > 0) ? plan.entry + 3.0 * plan.riskDist : plan.entry - 3.0 * plan.riskDist;
      plan.score    = 55.0;
      plan.reason   = StringFormat("R4C2-SPREADDIV(%.1fx)", ctx.spreadPoints / med);
      ApplyRegime(plan);
      return true;
   }

   double m_spreads[64];
   int    m_spreadCount;

   void PushSpread(const double sp)
   {
      if(sp <= 0.0) return;
      if(m_spreadCount < 64) { m_spreads[m_spreadCount++] = sp; return; }
      for(int i = 0; i < 63; i++) m_spreads[i] = m_spreads[i + 1];
      m_spreads[63] = sp;
   }

   double MedianSpread()
   {
      if(m_spreadCount < 20) return 0.0;
      double s[];
      ArrayResize(s, m_spreadCount);
      for(int i = 0; i < m_spreadCount; i++) s[i] = m_spreads[i];
      ArraySort(s);
      return s[m_spreadCount / 2];
   }

   //--- Lever 6: order-block quality score (0..12) per the document's table
   double ObQualityScore(SEAContext &ctx, SSignalPlan &p)
   {
      double score = 0.0;
      MqlRates r[];
      if(EA_Rates(ctx.symbol, (ENUM_TIMEFRAMES)g_eaCfg.signalTimeframe, 1, 20, r) < 5) return 0.0;
      //--- touches of the zone
      int touches = 0;
      for(int i = 1; i <= 15; i++)
         if(r[i].low <= MathMax(p.entry, p.stop) && r[i].high >= MathMin(p.entry, p.stop)) touches++;
      if(touches > 3) score += 2.0;
      //--- high-volume origin candle
      double vsum = 0.0;
      for(int i = 1; i <= 15; i++) vsum += (double)r[i].tick_volume;
      double vavg = vsum / 15.0;
      if(vavg > 0.0 && r[1].tick_volume > 1.5 * vavg) score += 2.0;
      //--- weekly/monthly level proximity (~prior 5-day extreme)
      double hi5 = r[1].high, lo5 = r[1].low;
      for(int i = 1; i <= 15; i++) { hi5 = MathMax(hi5, r[i].high); lo5 = MathMin(lo5, r[i].low); }
      if(MathAbs(ctx.mid - hi5) < 0.25 * ctx.atr || MathAbs(ctx.mid - lo5) < 0.25 * ctx.atr) score += 2.0;
      //--- no opposing structure within 2R
      score += 1.0;
      //--- D1 trend agreement
      if(ctx.emaD1_200 > 0.0 && ((p.dir > 0 && ctx.mid > ctx.emaD1_200) ||
                                 (p.dir < 0 && ctx.mid < ctx.emaD1_200))) score += 2.0;
      //--- session (London/NY overlap preferred)
      if(ctx.clockMinutes >= 13 * 60 && ctx.clockMinutes < 16 * 60) score += 2.0;
      return score;
   }

   //--- Lever 1+2: regime risk scaled, de-risked after a losing streak
   double LotsMultiplier(SEAContext &ctx)
   {
      RegimeParams(ctx);
      double risk = m_regimeRisk;
      if(LosingStreak() >= InpStreakReduceAfter) risk *= InpStreakReduceFactor;
      if(ctx.riskPct <= 0.0) return 0.0;
      return MathMax(0.0, risk / ctx.riskPct);
   }

   //--- Lever 3: end-of-month liquidity harvest bias
   bool EndOfMonthWindow()
   {
      MqlDateTime dt;
      TimeToStruct(TimeTradeServer(), dt);
      int dim = 31;
      if(dt.mon == 2) dim = 28;
      else if(dt.mon == 4 || dt.mon == 6 || dt.mon == 9 || dt.mon == 11) dim = 30;
      return (dt.day >= dim - 1 || dt.day <= 2);
   }
};

CRound4C2 g_Round4C2;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round4C2);
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
