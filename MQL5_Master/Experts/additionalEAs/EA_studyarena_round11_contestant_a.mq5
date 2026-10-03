//+------------------------------------------------------------------+
//| EA_studyarena_round11_contestant_a.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 11A - adaptive session sweep-reclaim with session caps and cost governors
//| Source document : docs/research/study_arena/studyarena-round11-contestant-a.md
//| Tracker entry   : #68  |  Magic: 2035
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound11A class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 11A - adaptive session sweep-reclaim with session caps and cost governors"
#property description "Source: docs/research/study_arena/studyarena-round11-contestant-a.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY,XAUUSD";      // Comma separated universe
input double          InpRiskPct          = 1.0;   // Base risk per trade (% of equity)
input double          InpTotalDdPct       = 6.0;   // Permanent floor from start balance (0 = off)
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2035; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input int    InpSessionWindowMin  = 120;   // First 120 minutes after the session open
input int    InpMaxTradesSession   = 3;     // Max completed trades per session
input double InpMaxSpreadMedianX   = 2.00;  // Spread vs its 20-session median
input double InpMaxAdrTravelPct    = 80.0;  // Already-travelled daily ATR ceiling
input double InpMaxEmaDistAtr      = 0.75;  // Distance from the H1 50-EMA (ATR_H1)
input double InpCommissionPerLotRT = 7.0;   // Round-turn commission per lot (broker figure)
input double InpMaxCostR           = 0.10;  // Doc: reject when spread + commission exceeds 0.10R

//+------------------------------------------------------------------+
//| Strategy: Round 11A - adaptive session sweep-reclaim with session caps and cost governors
//+------------------------------------------------------------------+
class CRound11A : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R11A_ADAPTIVE_SWEEP";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round11-contestant-a.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.totalDdPct            = InpTotalDdPct;
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;   // doc: cost gate uses commission
      cfg.maxCostR              = InpMaxCostR;
      cfg.maxTradesPerDay       = InpMaxTradesSession;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 600;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;
      cfg.breakEvenAtR          = 1.00;
      cfg.breakEvenOnBarClose   = true;    // doc: BE only after a completed bar close
      cfg.beConfirmTf            = PERIOD_M1;    // doc: M1 close
      cfg.trailAtR              = 1.50;  cfg.trailDistanceR = 0.75;
      cfg.timeStopMinutes       = 240;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      int sessFrom = 0, sessTo = 0, rangeFrom = 0, rangeTo = 0;
      if(!SessionWindow(ctx, sessFrom, sessTo, rangeFrom, rangeTo)) return false;
      if(TradesThisSession(sessFrom) >= InpMaxTradesSession) return false;
      if(!SpreadOk(ctx)) return false;
      if(AdrTravelPct(ctx) > InpMaxAdrTravelPct) return false;

      SSweepParams p;
      p.Reset();
      p.rangeFromMin = rangeFrom; p.rangeToMin = rangeTo;
      p.sessionFromMin = sessFrom; p.sessionToMin = sessTo;
      p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
      p.reclaimWindowBars = 3;
      p.wickRatio = 0.60; p.bodyRatio = 0.60;
      p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
      p.entryRetrace = 0.50; p.targetR = 2.0;
      if(!SigSweepReclaim(ctx, p, plan)) return false;
      if(!EmaSlopeAgrees(ctx, plan.dir)) return false;
      if(!EmaDistanceOk(ctx)) return false;
      plan.reason = StringFormat("R11A-%sSWEEP %s", sessFrom == 7 * 60 ? "LONDON" : "NY", plan.reason);
      return true;
   }

   bool SessionWindow(SEAContext &ctx, int &sessFrom, int &sessTo, int &rangeFrom, int &rangeTo)
   {
      //--- London: first 120 minutes after 07:00, NY: first 120 after 13:30
      if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 7 * 60 + InpSessionWindowMin)
      { sessFrom = 7 * 60; sessTo = 7 * 60 + InpSessionWindowMin; rangeFrom = 0; rangeTo = 7 * 60; return true; }
      if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 13 * 60 + 30 + InpSessionWindowMin)
      { sessFrom = 13 * 60 + 30; sessTo = sessFrom + InpSessionWindowMin; rangeFrom = 7 * 60; rangeTo = 13 * 60; return true; }
      return false;                                      // no Asian trading
   }

   bool SpreadOk(SEAContext &ctx)
   {
      PushSpread(ctx.spreadPoints);
      double med = MedianSpread();
      if(med <= 0.0) return true;
      return (ctx.spreadPoints <= InpMaxSpreadMedianX * med);
   }

   double m_spreads[96];
   int    m_spreadCount;

   void PushSpread(const double sp)
   {
      if(sp <= 0.0) return;
      if(m_spreadCount < 96) { m_spreads[m_spreadCount++] = sp; return; }
      for(int i = 0; i < 95; i++) m_spreads[i] = m_spreads[i + 1];
      m_spreads[95] = sp;
   }

   double MedianSpread()
   {
      if(m_spreadCount < 30) return 0.0;
      double s[];
      ArrayResize(s, m_spreadCount);
      for(int i = 0; i < m_spreadCount; i++) s[i] = m_spreads[i];
      ArraySort(s);
      return s[m_spreadCount / 2];
   }

   double AdrTravelPct(SEAContext &ctx)
   {
      double adr = ctx.atrD1;
      if(adr <= 0.0) return 0.0;
      MqlRates d[];
      if(EA_Rates(ctx.symbol, PERIOD_D1, 0, 1, d) < 1) return 0.0;
      return 100.0 * (d[0].high - d[0].low) / adr;
   }

   bool EmaSlopeAgrees(SEAContext &ctx, const int dir)
   {
      if(ctx.emaH1_50 <= 0.0) return false;
      return (dir > 0) ? (ctx.mid >= ctx.emaH1_50) : (ctx.mid <= ctx.emaH1_50);
   }

   //--- distance is direction-agnostic; the direction test lives in EmaSlopeAgrees
   bool EmaDistanceOk(SEAContext &ctx)
   {
      double h1Atr = (ctx.atrH1 > 0.0) ? ctx.atrH1
                                      : ((ctx.atrD1 > 0.0) ? ctx.atrD1 / 6.0 : 0.0);   // real H1 ATR, daily/6 as fallback
      if(h1Atr <= 0.0) return true;
      return (MathAbs(ctx.mid - ctx.emaH1_50) <= InpMaxEmaDistAtr * h1Atr);
   }

   //--- completed trades inside the current session window
   int TradesThisSession(const int sessFrom)
   {
      if(!HistorySelect(TimeCurrent() - 3 * 24 * 3600, TimeCurrent())) return 0;
      MqlDateTime dt;
      TimeToStruct(TimeTradeServer(), dt);
      int nowMin = dt.hour * 60 + dt.min;
      int elapsed = nowMin - sessFrom;
      if(elapsed < 0) elapsed = 0;
      datetime from = TimeTradeServer() - (datetime)(elapsed * 60);
      int n = 0;
      for(int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagicNumber) continue;
         if(HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
         if((datetime)HistoryDealGetInteger(t, DEAL_TIME) < from) continue;
         n++;
      }
      return n;
   }
};

CRound11A g_Round11A;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round11A);
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
