//+------------------------------------------------------------------+
//| EA_STRATEGY_ROADMAP.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Strategy roadmap - Track A preservation, Track B fast-track families
//| Source document : docs/strategy/STRATEGY-ROADMAP.md
//| Tracker entry   : #31  |  Magic: 3117
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CStrategyRoadmap class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Strategy roadmap - Track A preservation, Track B fast-track families"
#property description "Source: docs/strategy/STRATEGY-ROADMAP.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "GBPJPY,EURJPY,XAUUSD,EURUSD";      // Comma separated universe
input double          InpRiskPct          = 1.5;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 5.0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 1.0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 10;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 10;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 3;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 3117; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
enum ENUM_ROADMAP_TRACK
{
   TRACK_A_LONG_TERM = 0,   // Track A: validated relaxed-geometry triad
   TRACK_B_FAST_TRACK= 1    // Track B: fast-track family set
};
enum ENUM_FAST_FAMILY
{
   FAST_F1_QUIET_FADE   = 0,  // F1 quiet-session range fade
   FAST_F2_FAILED_BREAK = 1,  // F2 failed-breakout reversal (ORB level)
   FAST_F3_BREAK_RIDER  = 2   // F3 breakout rider (no target, session exit)
};
input ENUM_ROADMAP_TRACK  InpTrack        = TRACK_A_LONG_TERM; // Which track to run
input ENUM_FAST_FAMILY    InpFastFamily   = FAST_F2_FAILED_BREAK; // Track B family
input double InpTrackARiskPct             = 1.50;  // Track A: 1.5% per trade
input double InpTrackASweepMin            = 0.02;  // Relaxed geometry: sweep >= x ATR
input double InpTrackAWickMin             = 0.45;  // Relaxed geometry: wick >= x
input double InpTrackABodyMin             = 0.50;  // Relaxed geometry: body >= x
input bool   InpGoldSwingPersonalTrack    = true;  // Personal track: gold swing sleeve

//+------------------------------------------------------------------+
//| Strategy: Strategy roadmap - Track A preservation, Track B fast-track families
//+------------------------------------------------------------------+
class CStrategyRoadmap : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "STRATEGY_ROADMAP";
      cfg.sourceDoc             = "docs/strategy/STRATEGY-ROADMAP.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = (InpTrack == TRACK_A_LONG_TERM) ? InpTrackARiskPct : InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;          // The5ers -5% daily boundary
      cfg.totalDdPct            = InpTotalDdPct;            // -10% total floor
      cfg.profitTargetPct       = InpProfitTargetPct;       // +10% in ~63 trading days
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;                        // one-position compliance
      cfg.minSecondsBetweenTrades = 120;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.pendingExpiryMinutes  = 15;
      cfg.timeStopMinutes       = 90;
      cfg.breakEvenAtR          = 1.0;
      cfg.breakEvenOnBarClose   = true;                    // only a completed bar confirms +1R
      cfg.partial1AtR           = 0.0;
      cfg.useHwmThrottle        = true;
      cfg.hwmTier1Dd            = 3.0;  cfg.hwmTier1Mult = 0.50;
      cfg.hwmTier2Dd            = 6.0;  cfg.hwmTier2Mult = 0.0;  cfg.hwmHaltDd = 6.0;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      if(InpTrack == TRACK_A_LONG_TERM)
      {
         //--- Track A: GBPJPY + EURJPY + XAUUSD, London only, relaxed geometry
         bool isTrackA = (ctx.symbol == "GBPJPY" || ctx.symbol == "EURJPY" || ctx.symbol == "XAUUSD");
         if(!isTrackA)
         {
            //--- personal-account track: gold swing sleeve
            if(!InpGoldSwingPersonalTrack || ctx.symbol != "XAUUSD") return false;
            SDonchianParams d;
            d.Reset();
            d.lookbackDays = 55; d.stopD1Atr = 2.5; d.targetR = 4.0; d.trailD1Atr = 2.5;
            if(!SigDonchian(ctx, d, plan)) return false;
            plan.reason = "PERSONAL-GOLD-SWING " + plan.reason;
            return true;
         }
         if(ctx.clockMinutes < 7 * 60 || ctx.clockMinutes >= 16 * 60) return false;
         SSweepParams p;
         p.Reset();
         p.rangeFromMin   = 0;
         p.rangeToMin     = 7 * 60;
         p.sessionFromMin = 7 * 60;
         p.sessionToMin   = 16 * 60;
         p.sweepMinAtr    = InpTrackASweepMin;
         p.sweepMaxAtr    = 0.50;
         p.reclaimWindowBars = 3;
         p.wickRatio      = InpTrackAWickMin;
         p.bodyRatio      = InpTrackABodyMin;
         p.stopBufferAtr  = 0.10;
         p.minStopAtr     = 0.60;  p.maxStopAtr = 1.50;
         p.entryRetrace   = 0.50;
         p.targetR        = 1.50;
         if(!SigSweepReclaim(ctx, p, plan)) return false;
         plan.reason = "TRACK-A " + plan.reason;
         return true;
      }

      //--- Track B: fast-track families (goal: Phase 1 in <= 3 months)
      if(InpFastFamily == FAST_F1_QUIET_FADE)
      {
         if(ctx.clockMinutes >= 7 * 60) return false;
         SRangeFadeParams f;
         f.Reset();
         f.bbPeriod = 20; f.bbDeviation = 2.0;
         f.rsiOversold = 35.0; f.rsiOverbought = 65.0;
         f.wickRatio = 0.30; f.stopBufferAtr = 0.30; f.targetR = 1.1;
         f.requireRangeRegime = true; f.maxAdx = 22.0;
         if(!SigRangeFade(ctx, f, plan)) return false;
         plan.reason = "TRACK-B-F1 " + plan.reason;
         return true;
      }
      if(InpFastFamily == FAST_F2_FAILED_BREAK)
      {
         SOrbParams o;
         o.Reset();
         o.rangeFromMin = 13 * 60 + 30;      // NY opening range
         o.rangeToMin   = 14 * 60;
         o.entryFromMin = 14 * 60;
         o.entryToMin   = 16 * 60;
         o.minRangeAtr  = 0.20; o.maxRangeAtr = 3.0;
         o.bufferAtr    = 0.02; o.bodyRatio = 0.50;
         o.stopBufferAtr= 0.10; o.targetR = 1.5;
         if(!SigORB(ctx, o, plan)) return false;
         plan.reason = "TRACK-B-F2 " + plan.reason;
         return true;
      }
      //--- F3 breakout rider: no target, the session exit closes it
      SBreakRetestParams r;
      r.Reset();
      r.rangeFromMin = 7 * 60; r.rangeToMin = 13 * 60;
      r.entryFromMin = 13 * 60 + 30; r.entryToMin = 19 * 60;
      r.minRangeAtr = 0.40; r.targetR = 3.0;
      if(!SigBreakRetest(ctx, r, plan)) return false;
      plan.reason = "TRACK-B-F3 " + plan.reason;
      return true;
   }
};

CStrategyRoadmap g_StrategyRoadmap;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_StrategyRoadmap);
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
