//+------------------------------------------------------------------+
//| EA_studyarena_round4_contestant_b.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 4B - session map portfolio with grid, sweep, pullback and VWAP engines
//| Source document : docs/research/study_arena/studyarena-round4-contestant-b.md
//| Tracker entry   : #40  |  Magic: 2009
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound4B class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 4B - session map portfolio with grid, sweep, pullback and VWAP engines"
#property description "Source: docs/research/study_arena/studyarena-round4-contestant-b.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,XAUUSD,AUDNZD,EURCHF,GBPJPY,USDJPY";      // Comma separated universe
input double          InpDailyLossPct     = 5.0;   // Halt for the day at -x% (0 = off)
input int             InpMaxTradesPerDay  = 6;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2009; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpDecideRiskPct      = 1.50;  // Risk/trade for the 23.3%/mo decomposition
input double InpPullbackRr        = 2.00;  // London-mid / NY 20-EMA pullback target
input int    InpRolloverStopMin   = 21 * 60;  // No new risk from 21:00 (rollover)

//+------------------------------------------------------------------+
//| Strategy: Round 4B - session map portfolio with grid, sweep, pullback and VWAP engines
//+------------------------------------------------------------------+
class CRound4B : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R4B_SESSION_PORTFOLIO";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round4-contestant-b.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpDecideRiskPct;
      cfg.signalTimeframe       = PERIOD_M15;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 2;
      cfg.minSecondsBetweenTrades = 300;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;
      cfg.breakEvenAtR          = 1.00;
      cfg.timeStopMinutes       = 180;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      double pipDist = AsiaRangePips(ctx);

      //--- 21:00-00:00 rollover: nothing at all
      if(ctx.clockMinutes >= InpRolloverStopMin || ctx.clockMinutes < 60) return false;

      //--- 00:00-07:00 Tokyo: grid / range fade on the low-vol crosses
      if(ctx.clockMinutes < 7 * 60)
      {
         if(!IsGridPair(ctx.symbol)) return false;
         if(ctx.adxD1 >= 20.0) return false;                     // doc: ADX(14) daily < 20 (hard gate)
         SRangeFadeParams rf;
         rf.Reset();
         rf.bbPeriod = 20; rf.bbDeviation = 2.0;
         rf.rsiOversold = 5.0; rf.rsiOverbought = 95.0;
         rf.wickRatio = 0.50; rf.stopBufferAtr = 0.20;
         rf.targetR = 1.00; rf.requireRangeRegime = false;       // regime gate is the daily ADX above
         if(!SigRangeFade(ctx, rf, plan)) return false;
         plan.reason = "R4B-TOKYOGRID " + plan.reason;
         return true;
      }

      //--- 07:00-10:00 London open: sweep + break-retest (never a grid here)
      if(ctx.clockMinutes < 10 * 60)
      {
         if(!IsLondonPair(ctx.symbol)) return false;              // doc sleeve 1 instruments
         SBreakRetestParams br;
         br.Reset();
         br.rangeFromMin = 0; br.rangeToMin = 7 * 60;
         br.entryFromMin = 7 * 60; br.entryToMin = 10 * 60;
         br.minRangeAtr = 0.20; br.targetR = 2.0;
         if(!SigBreakRetest(ctx, br, plan)) return false;
         plan.reason = StringFormat("R4B-LONDON(%.0fp Asia) %s", pipDist, plan.reason);
         return true;
      }

      //--- 10:00-12:30 London mid: 20-EMA pullback in the London direction
      if(ctx.clockMinutes < 12 * 60 + 30)
      {
         SEmaPullbackParams ep;
         ep.Reset();
         ep.emaPeriod = 20; ep.maxDistanceAtr = 1.20;
         ep.requireTrend = true; ep.targetR = InpPullbackRr;
         if(!SigEmaPullback(ctx, ep, plan)) return false;
         plan.reason = "R4B-LONDONMID " + plan.reason;
         return true;
      }

      //--- 13:30-16:00 NY overlap: continuation or failed-London reversal
      if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 16 * 60)
      {
         if(!IsNySleevePair(ctx.symbol)) return false;            // doc NY sleeve instruments
         if(!SigEmaPullback(ctx, PullbackParams(), plan)) return false;
         plan.reason = "R4B-NYPULLBACK " + plan.reason;
         return true;
      }

      //--- 16:00-20:00 NY afternoon: fade back to the daily VWAP
      if(ctx.clockMinutes >= 16 * 60 && ctx.clockMinutes < 20 * 60)
      {
         if(!SigZScoreFade(ctx, 20, 2.0, 0.50, 1.00, plan)) return false;
         plan.reason = "R4B-VWAPFADE " + plan.reason;
         return true;
      }
      return false;
   }

   SEmaPullbackParams PullbackParams()
   {
      SEmaPullbackParams ep;
      ep.Reset();
      ep.emaPeriod = 20; ep.maxDistanceAtr = 1.50;
      ep.requireTrend = true; ep.targetR = InpPullbackRr;
      return ep;
   }

   //--- doc: flat by 07:00 UK - London volume destroys grids
   void Manage(SEAContext &ctx)
   {
      if(ctx.clockMinutes < 7 * 60) return;
      if(!IsGridPair(ctx.symbol)) return;
      for(int t = g_eaTrackCount - 1; t >= 0; t--)
      {
         if(g_eaTrack[t].symbol != ctx.symbol) continue;
         if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;
         g_eaExec.Close(g_eaTrack[t].ticket, "grid flat 07:00");
      }
   }

   bool IsGridPair(const string sym)
   {
      return (StringFind(sym, "AUDNZD") >= 0 || StringFind(sym, "EURCHF") >= 0 ||
              StringFind(sym, "USDCHF") >= 0);
   }

   //--- doc sleeve 1 (London-open sweep + range-break retest): GBPUSD, EURUSD, XAUUSD.
   //--- GBPJPY is the document's momentum-break pair ("no retest wait"): that trigger
   //--- is not implemented, so the pair is excluded rather than traded with the wrong one.
   bool IsLondonPair(const string sym)
   {
      return (StringFind(sym, "GBPUSD") >= 0 || StringFind(sym, "EURUSD") >= 0 ||
              StringFind(sym, "XAUUSD") >= 0);
   }

   //--- doc 13:30-16:00 NY sleeve: XAUUSD (EMA pullback), USDJPY (continuation).
   //--- USDCAD's oil-divergence fade is not implemented, so it is excluded.
   bool IsNySleevePair(const string sym)
   {
      return (StringFind(sym, "XAUUSD") >= 0 || StringFind(sym, "USDJPY") >= 0);
   }

   double AsiaRangePips(SEAContext &ctx)
   {
      double hi = 0.0, lo = 0.0;
      if(!SigAsianRange(ctx.symbol, hi, lo)) return 0.0;
      double pip = EA_PipSize(ctx.symbol);
      return (pip > 0.0) ? (hi - lo) / pip : 0.0;
   }
};

CRound4B g_Round4B;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round4B);
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
