//+------------------------------------------------------------------+
//| EA_studyarena_round8_contestant_b.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 8B - SOS-3 session-open sweep and reclaim with an A+ free-roll booster
//| Source document : docs/research/study_arena/studyarena-round8-contestant-b.md
//| Tracker entry   : #60  |  Magic: 2027
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound8B class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 8B - SOS-3 session-open sweep and reclaim with an A+ free-roll booster"
#property description "Source: docs/research/study_arena/studyarena-round8-contestant-b.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,XAUUSD,USDJPY,AUDNZD,EURGBP";      // Comma separated universe
input int             InpMaxTradesPerDay  = 4;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2027; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpBaseRiskPct       = 0.75;  // Base engine risk
input double InpAplusBoostPct     = 0.50;  // A+ setup adds 0.5% free-roll risk
input double InpMaxOpenRiskPct   = 1.50;  // Doc: max open risk at any instant
input double InpChandelierMult    = 2.50;  // Runner trail (High - 2.5 x H1 ATR)

//+------------------------------------------------------------------+
//| Strategy: Round 8B - SOS-3 session-open sweep and reclaim with an A+ free-roll booster
//+------------------------------------------------------------------+
class CRound8B : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R8B_SOS3_FREEROLL";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round8-contestant-b.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpBaseRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 2;
      cfg.minSecondsBetweenTrades = 300;
      cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 22;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      //--- document ladder: 40% at +1R, 30% at +2R, 30% runner
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;
      cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 30.0;
      cfg.breakEvenAtR          = 1.00;
      cfg.breakEvenOnBarClose   = true;   // doc: BE only after an M5 close beyond +1R
      cfg.trailAtR              = 0.0;    // doc: the 30% runner trails on the chandelier in Manage()
      cfg.trailDistanceR        = 1.00;
      cfg.timeStopMinutes       = 180;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- the identical SOS-3 setup at all three sessions
      int rangeFrom = 0, rangeTo = 0, sessFrom = 0, sessTo = 0;
      if(ctx.clockMinutes < 7 * 60)            { rangeFrom = 21 * 60; rangeTo = 24 * 60; sessFrom = 0;   sessTo = 3 * 60; }           // doc: Asian entries 00:00-03:00
      else if(ctx.clockMinutes < 13 * 60 + 30) { rangeFrom = 0;  rangeTo = 7 * 60;  sessFrom = 7 * 60;    sessTo = 10 * 60; }          // doc: London entries 07:00-10:00
      else                                     { rangeFrom = 7 * 60; rangeTo = 13 * 60; sessFrom = 13 * 60 + 30; sessTo = 15 * 60 + 30; }  // doc: NY entries 13:30-15:30
      if(ctx.clockMinutes >= sessTo) return false;   // doc: no entries outside the session's entry window

      //--- doc risk block: one position per currency group, max 2 trades/session, max 1.5% open risk
      if(GroupBlocked(ctx.symbol)) return false;
      if(SessionEntries(ctx, sessFrom, sessTo) >= 2) return false;
      if(EA_OpenRiskPct() >= InpMaxOpenRiskPct) return false;

      if(!RangeQualifies(ctx, rangeFrom, rangeTo)) return false;
      //--- Asian mean reversion pairs need no directional bias; others need the H1 trend
      if(!IsAsianPair(ctx.symbol))
      {
         if(ctx.emaH1_50 <= 0.0) return false;
         bool up = (ctx.mid > ctx.emaH1_50 && ctx.ema50 > ctx.emaH1_50);
         bool dn = (ctx.mid < ctx.emaH1_50 && ctx.ema50 < ctx.emaH1_50);
         if(!up && !dn) return false;
      }
      else if(ctx.adxH1 >= 16.0) return false;                    // doc: Asian waiver only while H1 ADX < 16

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
      plan.score = SetupScore(ctx);
      plan.reason = StringFormat("R8B-SOS3(%.0f) %s", plan.score, plan.reason);
      return true;
   }

   bool IsAsianPair(const string sym)
   {
      return (StringFind(sym, "AUDNZD") >= 0 || StringFind(sym, "EURGBP") >= 0);
   }

   bool RangeQualifies(SEAContext &ctx, const int fromMin, const int toMin)
   {
      double hi = 0.0, lo = 0.0;
      if(!RangeBetween(ctx.symbol, fromMin, toMin, hi, lo)) return false;
      double median = MedianRange(ctx.symbol);
      if(median <= 0.0) return false;
      double ratio = (hi - lo) / median;
      return (ratio >= 0.35 && ratio <= 0.75);
   }

   double MedianRange(const string sym)
   {
      MqlRates d[];
      if(EA_Rates(sym, PERIOD_D1, 1, 20, d) < 10) return 0.0;
      double s[];
      ArrayResize(s, 20);
      for(int i = 0; i < 20; i++) s[i] = d[i].high - d[i].low;
      ArraySort(s);
      return s[10];
   }

   //--- range of the most recent completed session between two clock minutes
   bool RangeBetween(const string sym, const int fromMin, const int toMin, double &hi, double &lo)
   {
      MqlRates r[];
      if(EA_Rates(sym, PERIOD_M15, 1, 400, r) < 30) return false;
      bool wrap = (fromMin > toMin);
      int i = 0;
      for(; i < 400; i++)
      {
         MqlDateTime t;
         TimeToStruct(r[i].time, t);
         int m = t.hour * 60 + t.min;
         bool inWin = wrap ? (m >= fromMin || m < toMin) : (m >= fromMin && m < toMin);
         if(inWin) break;
      }
      if(i >= 400) return false;
      hi = 0.0; lo = 0.0;
      bool found = false;
      for(; i < 400; i++)
      {
         MqlDateTime t;
         TimeToStruct(r[i].time, t);
         int m = t.hour * 60 + t.min;
         bool inWin = wrap ? (m >= fromMin || m < toMin) : (m >= fromMin && m < toMin);
         if(!inWin) break;
         if(!found) { hi = r[i].high; lo = r[i].low; found = true; }
         else { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }
      }
      return found;
   }

   double m_setupScore;

   double SetupScore(SEAContext &ctx)
   {
      double score = 70.0;
      if(ctx.atrD1 > 0.0 && ctx.atr > 0.5 * ctx.atrD1) score += 10.0;
      if(ctx.adx14 >= 20.0 && ctx.adx14 <= 35.0) score += 10.0;
      if(ctx.emaD1_200 > 0.0 && ((ctx.mid > ctx.emaD1_200) || (ctx.mid < ctx.emaD1_200))) score += 5.0;
      m_setupScore = MathMin(score, 100.0);
      return m_setupScore;
   }

   //--- A+ setups get the free-roll booster on top of base risk
   double LotsMultiplier(SEAContext &ctx)
   {
      if(ctx.riskPct <= 0.0) return 0.0;
      double risk = InpBaseRiskPct + ((m_setupScore >= InpAplusScore) ? InpAplusBoostPct : 0.0);
      return MathMax(0.0, risk / ctx.riskPct);
   }

   int CurrencyGroupId(const string sym)
   {
      //--- doc: one position per currency group; the USD block includes gold,
      //--- USDJPY is counted as the JPY bet, AUDNZD and EURGBP stand alone
      if(StringFind(sym, "JPY") >= 0) return 2;
      if(StringFind(sym, "USD") >= 0 || StringFind(sym, "XAU") >= 0) return 1;
      if(StringFind(sym, "AUDNZD") >= 0) return 3;
      if(StringFind(sym, "EURGBP") >= 0) return 4;
      return 5;
   }

   bool GroupBlocked(const string sym)
   {
      int g = CurrencyGroupId(sym);
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(CurrencyGroupId(PositionGetString(POSITION_SYMBOL)) == g) return true;
      }
      return false;
   }

   //--- doc: max 2 trades per session; entries are counted from the deal history
   int SessionEntries(SEAContext &ctx, const int sessFrom, const int sessTo)
   {
      MqlDateTime dt;
      if(!TimeToStruct(ctx.nowClock, dt)) return 0;
      dt.hour = sessFrom / 60; dt.min = sessFrom % 60; dt.sec = 0;
      datetime from = EA_ClockToServer(StructToTime(dt));
      datetime to   = from + (datetime)((sessTo - sessFrom) * 60);
      if(!HistorySelect(from, to)) return 0;
      int n = 0;
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagicNumber) continue;
         if(HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
         n++;
      }
      return n;
   }

   //--- doc: the 30% runner trails at High - 2.5 x H1 ATR, hourly, no TP
   void Manage(SEAContext &ctx)
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
         if(rMult < 1.0) continue;
         double h1Atr = H1Atr(ctx);
         if(h1Atr <= 0.0) continue;
         MqlRates r[];
         if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 20, r) < 5) continue;
         double hh = r[0].high, ll = r[0].low;
         for(int i = 1; i < 20; i++) { hh = MathMax(hh, r[i].high); ll = MathMin(ll, r[i].low); }
         double newSl = (g_eaTrack[t].dir > 0) ? hh - InpChandelierMult * h1Atr
                                               : ll + InpChandelierMult * h1Atr;
         double oldSl = PositionGetDouble(POSITION_SL);
         if(g_eaTrack[t].dir > 0 && newSl > oldSl) g_eaExec.Modify(g_eaTrack[t].ticket, newSl, 0.0);
         if(g_eaTrack[t].dir < 0 && (oldSl == 0.0 || newSl < oldSl))
            g_eaExec.Modify(g_eaTrack[t].ticket, newSl, 0.0);
      }
   }

   double H1Atr(SEAContext &ctx)
   {
      if(ctx.atrH1 > 0.0) return ctx.atrH1;                 // real H1 ATR
      double av[];
      if(EA_BufN(g_eaInd[ctx.index].hAtrD1, 0, 1, 20, av) < 5) return 0.0;
      return (av[0] > 0.0) ? av[0] / 6.0 : 0.0;   // fallback: ~H1 ATR from the daily ATR
   }
};

CRound8B g_Round8B;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round8B);
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
