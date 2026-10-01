//+------------------------------------------------------------------+
//| EA_FINAL_OPTIMUM_STRATEGY.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Final Optimum - per-pair Triad stack + gold Donchian
//| Source document : docs/strategy/FINAL_OPTIMUM_STRATEGY.md
//| Tracker entry   : #15  |  Magic: 3101
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CFinalOptimum class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Final Optimum - per-pair Triad stack + gold Donchian"
#property description "Source: docs/strategy/FINAL_OPTIMUM_STRATEGY.md"

#include "..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "AUDUSD,EURJPY,GBPJPY,USDJPY,XAUUSD";      // Comma separated universe
input double          InpRiskPct          = 1.75;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 25;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 4.5;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 10;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 10;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 2;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 3101; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpTriadRiskPct      = 1.75;  // Triad leg risk (champion run)
input double InpGoldRiskPct       = 3.00;  // Gold Donchian leg risk
input int    InpDonchianDays      = 20;    // Gold channel length (completed D1 bars)
input double InpGoldStopAtr       = 1.50;  // Gold stop = x daily ATR
input double InpGoldTargetR       = 3.00;  // Gold target in R
input bool   InpTradeGold          = true; // Enable the XAUUSD Donchian leg

//+------------------------------------------------------------------+
//| Strategy: Final Optimum - per-pair Triad stack + gold Donchian
//+------------------------------------------------------------------+
class CFinalOptimum : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName         = "FINAL_OPTIMUM";
      cfg.sourceDoc            = "docs/strategy/FINAL_OPTIMUM_STRATEGY.md";
      cfg.symbols              = InpSymbolsToTrade;
      cfg.magic                = InpMagicNumber;
      cfg.riskPct              = InpTriadRiskPct;
      cfg.signalTimeframe      = PERIOD_M5;
      cfg.clock                = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset= InpServerGmtOffset;
      cfg.serverFollowsEuDst   = true;
      cfg.maxSpreadPoints      = InpMaxSpreadPoints;
      cfg.dailyLossPct         = InpDailyLossPct;      // 4.5% internal buffer
      cfg.totalDdPct           = InpTotalDdPct;        // $2,250 permanent floor
      cfg.profitTargetPct      = InpProfitTargetPct;   // $2,750 phase-1 target
      cfg.maxTradesPerDay      = InpMaxTradesPerDay;   // max 2 account-wide
      cfg.maxOpenPositions     = 1;                    // one slot account-wide
      cfg.sessionStartHour     = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour       = 13;  cfg.sessionEndMin   = 30;   // flat by 13:30
      cfg.sessionEndFlat       = true;
      cfg.fridayFlat           = true;  cfg.fridayFlatHour = 21;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly   = true;
      cfg.useLimitEntry        = true;
      cfg.pendingExpiryMinutes = 45;
      cfg.breakEvenAtR         = 1.0;
      cfg.timeStopMinutes      = 90;
      cfg.minSecondsBetweenTrades = 120;
      cfg.logLevel             = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      bool isGold = (ctx.symbol == "XAUUSD");
      if(isGold)
      {
         if(!InpTradeGold) return false;
         SDonchianParams d;
         d.Reset();
         d.lookbackDays = InpDonchianDays;
         d.stopD1Atr    = InpGoldStopAtr;
         d.targetR      = InpGoldTargetR;
         d.trailD1Atr   = 2.5;
         d.longOnly     = false;
         if(!SigDonchian(ctx, d, plan)) return false;
         plan.reason = "GOLD-DONCHIAN " + plan.reason;
         return true;
      }

      //--- Leg A: per-pair triad parameters straight from the champion table
      SSweepParams p;
      p.Reset();
      p.rangeFromMin = 0;        // Asian range 00:00-07:00 London
      p.rangeToMin   = 7 * 60;
      p.sessionFromMin = 7 * 60;
      p.sessionToMin   = 11 * 60;                     // AUDUSD / GBPJPY default
      p.sweepMinAtr    = 0.02;
      p.reclaimWindowBars = 2;                        // disp_max = 2
      p.wickRatio      = 0.45;                        // relaxed champion geometry
      p.bodyRatio      = 0.60;
      p.stopBufferAtr  = 0.10;
      p.minStopAtr     = 0.60;   p.maxStopAtr = 1.50;
      p.entryRetrace   = 0.50;                        // limit at 50% of displacement body
      p.targetR        = 1.5;

      if(ctx.symbol == "AUDUSD")      { p.targetR = 2.5; }
      else if(ctx.symbol == "GBPJPY") { p.sweepMinAtr = 0.01; }
      else if(ctx.symbol == "EURJPY") { p.stopBufferAtr = 0.05; p.sessionToMin = 13 * 60 + 30; p.targetR = 1.5; }
      else if(ctx.symbol == "USDJPY") { p.sessionToMin = 13 * 60 + 30; p.targetR = 1.5; }

      //--- XAUUSD no-late cutoff is enforced by the engine session end (13:30);
      //--- the 10:00 signal cutoff is applied here for the gold-triad variant
      if(ctx.symbol == "XAUUSD" && ctx.clockMinutes > 10 * 60) return false;

      if(!SigSweepReclaim(ctx, p, plan)) return false;
      plan.reason = StringFormat("TRIAD-%s %s", ctx.symbol, plan.reason);
      return true;
      }

      //--- gold leg risk (3%) vs triad leg risk (1.75%): scale the engine lot
      double LotsMultiplier(SEAContext &ctx)
      {
         if(ctx.symbol == "XAUUSD" && InpTriadRiskPct > 0.0)
            return InpGoldRiskPct / InpTriadRiskPct;
         return 1.0;
   }
};

CFinalOptimum g_FinalOptimum;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_FinalOptimum);
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
