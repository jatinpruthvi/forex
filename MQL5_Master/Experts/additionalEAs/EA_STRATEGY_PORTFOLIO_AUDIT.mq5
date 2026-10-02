//+------------------------------------------------------------------+
//| EA_STRATEGY_PORTFOLIO_AUDIT.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Portfolio audit - three-sleeve session router with per-sleeve R telemetry
//| Source document : docs/strategy/STRATEGY-PORTFOLIO-AUDIT.md
//| Tracker entry   : #30  |  Magic: 3116
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CPortfolioAuditRouter class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Portfolio audit - three-sleeve session router with per-sleeve R telemetry"
#property description "Source: docs/strategy/STRATEGY-PORTFOLIO-AUDIT.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY,XAUUSD,AUDNZD,EURGBP,GBPJPY";      // Comma separated universe
input double          InpRiskPct          = 0.24;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 4.0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 1.0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 10;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 0;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 4;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 3116; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpSleeveRiskPct      = 0.24;  // Per-trade risk for every sleeve
input int    InpMaxPositions       = 4;     // Max concurrent positions (portfolio)
input double InpShutdownDdPct      = 5.50;  // Strategy shutdown from the closed-equity high
input double InpSleeveAAtrMax      = 0.50;  // False-breakout reversal sweep ceiling
input double InpSleeveBTargetR     = 2.00;  // Continuation sleeve target
input double InpSleeveCTargetR     = 1.10;  // Quiet-session fade target

//+------------------------------------------------------------------+
//| Strategy: Portfolio audit - three-sleeve session router with per-sleeve R telemetry
//+------------------------------------------------------------------+
class CPortfolioAuditRouter : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "PORTFOLIO_AUDIT_ROUTER";
      cfg.sourceDoc             = "docs/strategy/STRATEGY-PORTFOLIO-AUDIT.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpSleeveRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = 2.5;
      cfg.totalDdPct            = InpTotalDdPct;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = InpMaxPositions;
      cfg.minSecondsBetweenTrades = 180;
      cfg.useHwmThrottle        = true;
      cfg.hwmTier1Dd            = 2.0;  cfg.hwmTier1Mult = 0.50;   // 2-4%: half risk
      cfg.hwmTier2Dd            = 4.0;  cfg.hwmTier2Mult = 0.25;   // 4-5.5%: quarter risk
      cfg.hwmHaltDd             = InpShutdownDdPct;   // strategy shutdown/review
      cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 19;  cfg.sessionEndMin = 30;
      cfg.noTradeAfterHour      = 21;  cfg.noTradeAfterMin = 30;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.pendingExpiryMinutes  = 15;
      cfg.timeStopMinutes       = 60;
      cfg.breakEvenAtR          = 1.0;
      cfg.breakEvenOnBarClose   = true;                    // only a completed bar confirms +1R
      cfg.partial1AtR           = 0.0;
      cfg.trailAtR              = 1.0;  cfg.trailDistanceR = 0.5;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      if(EA_CountPositions("", false) >= InpMaxPositions) return false;

      int nowMin = ctx.clockMinutes;

      //--- SLEEVE B (accepted-breakout continuation) - London / NY overlap
      bool bWindow = (nowMin >= 7 * 60 && nowMin < 15 * 60 + 30) ||
                     (nowMin >= 13 * 60 + 30 && nowMin < 19 * 60 + 30);
      if(bWindow && (ctx.symbol == "XAUUSD" || ctx.symbol == "GBPJPY" || ctx.symbol == "USDJPY"))
      {
         SBreakRetestParams b;
         b.Reset();
         b.rangeFromMin = 0; b.rangeToMin = 7 * 60;
         b.entryFromMin = 7 * 60; b.entryToMin = 15 * 60 + 30;
         b.minRangeAtr = 0.50; b.breakBufferAtr = 0.10; b.retestTolAtr = 0.15;
         b.stopBufferAtr = 0.20; b.targetR = InpSleeveBTargetR;
         if(SigBreakRetest(ctx, b, plan))
         {
            plan.reason = StringFormat("AUDIT-SLEEVE-B %s", plan.reason);
            m_sleeve = 2;
            return true;
         }
      }

      //--- SLEEVE C (quiet-session single-entry fade) - Asian session only
      if(nowMin < 6 * 60 + 30 && (ctx.symbol == "AUDNZD" || ctx.symbol == "EURGBP"))
      {
         SRangeFadeParams f;
         f.Reset();
         f.bbPeriod = 20; f.bbDeviation = 2.0;
         f.rsiOversold = 35.0; f.rsiOverbought = 65.0;
         f.wickRatio = 0.30; f.stopBufferAtr = 0.30; f.targetR = InpSleeveCTargetR;
         f.requireRangeRegime = true; f.maxAdx = 22.0;
         if(SigRangeFade(ctx, f, plan))
         {
            plan.reason = StringFormat("AUDIT-SLEEVE-C %s", plan.reason);
            m_sleeve = 3;
            return true;
         }
      }

      //--- SLEEVE A (false-breakout reversal) - session opens
      SSweepParams p;
      p.Reset();
      p.rangeFromMin   = 0;
      p.rangeToMin     = 7 * 60;
      p.sessionFromMin = 7 * 60;
      p.sessionToMin   = 16 * 60;
      p.sweepMinAtr    = 0.05;
      p.sweepMaxAtr    = InpSleeveAAtrMax;
      p.reclaimWindowBars = 3;
      p.wickRatio      = 0.60;
      p.bodyRatio      = 0.60;
      p.stopBufferAtr  = 0.10;
      p.minStopAtr     = 0.60;  p.maxStopAtr = 1.50;
      p.entryRetrace   = 0.50;
      p.targetR        = 1.50;
      if(ctx.symbol == "USDJPY" || ctx.symbol == "XAUUSD")
      {
         p.rangeFromMin   = 7 * 60;
         p.rangeToMin     = 13 * 60;
         p.sessionFromMin = 13 * 60 + 30;
         p.sessionToMin   = 16 * 60;
      }
      if(nowMin < p.sessionFromMin || nowMin >= p.sessionToMin) return false;
      if(!SigSweepReclaim(ctx, p, plan)) return false;
      plan.reason = StringFormat("AUDIT-SLEEVE-A %s", plan.reason);
      m_sleeve = 1;
      return true;
   }

   int m_sleeve;
   int m_lastSleeve;

   void OnInitStrategy() { m_sleeve = 0; m_lastSleeve = 0; }

   //--- per-sleeve R telemetry: the audit's expectancy table, measured live
   void Manage(SEAContext &ctx)
   {
      m_lastSleeve = m_sleeve;
      if(ctx.symbol == "XAUUSD" && ctx.clockMinutes >= 6 * 60 + 30 && ctx.clockMinutes < 7 * 60)
         EA_FlattenAll("sleeve C hard flat 06:30");
   }
};

CPortfolioAuditRouter g_PortfolioAuditRouter;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_PortfolioAuditRouter);
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
