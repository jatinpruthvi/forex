//+------------------------------------------------------------------+
//| EA_studyarena_round8_contestant_d.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 8D - one trade per day, five attempts a week, strict spread and slope filters
//| Source document : docs/research/study_arena/studyarena-round8-contestant-d.md
//| Tracker entry   : #62  |  Magic: 2029
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound8D class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 8D - one trade per day, five attempts a week, strict spread and slope filters"
#property description "Source: docs/research/study_arena/studyarena-round8-contestant-d.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD";      // Comma separated universe
input double          InpRiskPct          = 1.0;   // Base risk per trade (% of equity)
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2029; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpAdxLow            = 18.0;  // H1 ADX floor
input double InpAdxHigh           = 35.0;  // H1 ADX ceiling
input double InpSweepMaxAtr       = 0.30;  // Sweep must not exceed 0.30 x M15 ATR
input double InpSpreadMedianX     = 2.00;  // Skip if spread > 2x the time-of-day median
input int    InpWeeklyAttempts    = 5;     // Maximum attempts per week
input int    InpNoNewAfterMin     = 10 * 60;  // No new position after 10:00
input int    InpHardCloseMin      = 20 * 60;  // Absolute closing time

//+------------------------------------------------------------------+
//| Strategy: Round 8D - one trade per day, five attempts a week, strict spread and slope filters
//+------------------------------------------------------------------+
class CRound8D : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R8D_ONE_SHOT";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round8-contestant-d.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = 1;                 // one trade per day by design
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 0;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 10;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 0;  cfg.fridayFlatMin = 0;  // skip Friday
      cfg.signalOnNewBarOnly    = true;
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;   // doc: 40% at +1R
      cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 30.0;   // doc: 30% at +2R
      cfg.breakEvenAtR          = 1.00;
      cfg.breakEvenOnBarClose   = true;    // doc: BE only after a completed bar close
      cfg.beConfirmTf            = PERIOD_M15;   // doc: M15 close
      cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 0.75;
      cfg.timeStopMinutes       = 0;
      cfg.useLimitEntry         = true;
      cfg.pendingExpiryMinutes  = 15;    // cancel if the retest never comes
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      if(ctx.dayOfWeek == 5) return false;                 // skip Friday entirely
      if(ctx.clockMinutes < 7 * 60 || ctx.clockMinutes >= InpNoNewAfterMin) return false;
      if(WeeklyAttemptsUsed() >= InpWeeklyAttempts) return false;
      if(ctx.adxH1 < InpAdxLow || ctx.adxH1 > InpAdxHigh) return false;   // doc: H1 ADX(14) 18-35
      if(!H1BiasAgrees(ctx)) return false;
      if(!SpreadNormal(ctx)) return false;

      SSweepParams p;
      p.Reset();
      p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
      p.sessionFromMin = 7 * 60; p.sessionToMin = InpNoNewAfterMin;
      p.sweepMinAtr = 0.02; p.sweepMaxAtr = InpSweepMaxAtr;   // deeper sweeps are real breakouts
      p.reclaimWindowBars = 3;
      p.wickRatio = 0.55; p.bodyRatio = 0.60;
      p.stopBufferAtr = 0.10; p.minStopAtr = 0.50; p.maxStopAtr = 2.00;
      p.entryRetrace = 0.50;
      p.targetR = 2.0;
      if(!SigSweepReclaim(ctx, p, plan)) return false;

      //--- displacement candle must close in its upper/lower 25%
      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M5, 1, 6, r) < 6) return false;
      bool strongClose = (plan.dir > 0) ? (r[0].close > r[0].low + 0.75 * (r[0].high - r[0].low))
                                        : (r[0].close < r[0].low + 0.25 * (r[0].high - r[0].low));
      if(!strongClose) return false;
      plan.reason = "R8D-ONESHOT " + plan.reason;
      return true;
   }

   bool H1BiasAgrees(SEAContext &ctx)
   {
      if(ctx.emaH1_200 <= 0.0 || ctx.emaH1_50 <= 0.0) return false;
      bool up = (ctx.mid > ctx.emaH1_200 && ctx.emaH1_50 > ctx.emaH1_200);
      bool dn = (ctx.mid < ctx.emaH1_200 && ctx.emaH1_50 < ctx.emaH1_200);
      return (up || dn);
   }

   int WeeklyAttemptsUsed()
   {
      if(!HistorySelect(TimeCurrent() - 10 * 24 * 3600, TimeCurrent())) return 0;
      datetime weekStart = WeekStart();
      int n = 0;
      for(int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagicNumber) continue;
         if(HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
         if((datetime)HistoryDealGetInteger(t, DEAL_TIME) < weekStart) continue;
         n++;
      }
      return n;
   }

   datetime WeekStart()
   {
      MqlDateTime dt;
      TimeToStruct(TimeTradeServer(), dt);
      int dow = dt.day_of_week;            // 0 = Sunday
      int back = (dow == 0) ? 0 : dow - 1;
      datetime midnight = TimeTradeServer() - (dt.hour * 3600 + dt.min * 60 + dt.sec);
      return midnight - (datetime)(back * 24 * 3600);
   }

   bool SpreadNormal(SEAContext &ctx)
   {
      PushSpread(ctx.spreadPoints);
      double med = EA_SpreadBaseline(ctx.symbol, 30);                     // same time of day
      if(med <= 0.0) med = MedianSpread();                                // fallback: live ring
      if(med <= 0.0) return true;
      if(ctx.spreadPoints <= InpSpreadMedianX * med) return true;
      EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.1f > %.2fx time-of-day median %.1f - skip",
             ctx.symbol, ctx.spreadPoints, InpSpreadMedianX, med), true);
      return false;
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

   //--- close by 16:30 unless the runner already banked +2R; hard stop at 20:00
   void Manage(SEAContext &ctx)
   {
      if(EA_CountPositions(ctx.symbol, true) == 0) return;
      if(ctx.clockMinutes >= InpHardCloseMin) { g_eaExec.CloseAll("20:00 hard close"); return; }
      if(ctx.clockMinutes >= 16 * 60 + 30)
      {
         for(int t = 0; t < g_eaTrackCount; t++)
         {
            if(g_eaTrack[t].symbol != ctx.symbol) continue;
            if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;
            double entry = PositionGetDouble(POSITION_PRICE_OPEN);
            double cur   = PositionGetDouble(POSITION_PRICE_CURRENT);
            double risk  = g_eaTrack[t].riskDist;
            if(risk <= 0.0) continue;
            double rMult = (g_eaTrack[t].dir > 0) ? (cur - entry) / risk : (entry - cur) / risk;
            if(rMult < 2.0) { g_eaExec.Close(g_eaTrack[t].ticket, "16:30 close (not +2R)"); }
         }
      }
   }
};

CRound8D g_Round8D;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round8D);
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
