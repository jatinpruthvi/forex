//+------------------------------------------------------------------+
//| EA_Pr10_Roi_Improvements.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| PR10 ROI improvements - cost-honest M5 fade + gold Donchian(55)
//| Source document : docs/strategy/Pr10 Roi Improvements.md
//| Tracker entry   : #26  |  Magic: 3112
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CPr10RoiImprovements class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "PR10 ROI improvements - cost-honest M5 fade + gold Donchian(55)"
#property description "Source: docs/strategy/Pr10 Roi Improvements.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,AUDUSD,USDCAD,XAUUSD";      // Comma separated universe
input double          InpRiskPct          = 0.4;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 3.0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 1.0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 10;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 0;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 2;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 3112; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpCommissionPerLotRT = 4.50;  // Set to the broker's real round-turn cost
input double InpMaxCostR             = 0.10;  // Reject setups whose all-in cost exceeds xR
input bool   InpTradeIntradayFade    = true;  // M5 exhaustion fade (XAUUSD removed by design)
input bool   InpTradeGoldSwing       = true;  // Gold Donchian(55) chandelier swing leg
input int    InpGoldDonchianDays     = 55;    // N=55 daily channel (findings_swing_and_portfolio)
input double InpGoldStopAtr          = 3.00;  // Initial stop in daily ATR
input double InpGoldTrailAtr         = 2.50;  // Chandelier trail (2.5 x ATR)
input double InpGoldTargetR          = 4.00;  // Wide target; the trail does the work
input double InpFadeTargetR          = 1.50;  // Intraday fade target

//+------------------------------------------------------------------+
//| Strategy: PR10 ROI improvements - cost-honest M5 fade + gold Donchian(55)
//+------------------------------------------------------------------+
class CPr10RoiImprovements : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "PR10_ROI_IMPROVEMENTS";
      cfg.sourceDoc             = "docs/strategy/Pr10 Roi Improvements.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;   // fix the cost variable
      cfg.maxCostR              = InpMaxCostR;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.totalDdPct            = InpTotalDdPct;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 21;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.timeStopMinutes       = 90;
      cfg.breakEvenAtR          = 1.0;
      cfg.trailAtR              = 2.0;  cfg.trailDistanceR = 0.75;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- Gold leg: Donchian(55) breakout with a 2.5 x ATR chandelier trail
      if(ctx.symbol == "XAUUSD")
      {
         if(!InpTradeGoldSwing) return false;
         SDonchianParams d;
         d.Reset();
         d.lookbackDays = InpGoldDonchianDays;
         d.stopD1Atr    = InpGoldStopAtr;
         d.targetR      = InpGoldTargetR;
         d.trailD1Atr   = InpGoldTrailAtr;
         d.longOnly     = false;
         if(!SigDonchian(ctx, d, plan)) return false;
         plan.reason = StringFormat("GOLD-DONCHIAN(%d) %s", InpGoldDonchianDays, plan.reason);
         return true;
      }

      //--- Intraday fade: gold is excluded from this sleeve on purpose
      //--- (measured -0.219R net expectancy on the held-out test window).
      if(!InpTradeIntradayFade) return false;

      SSweepParams p;
      p.Reset();
      p.rangeFromMin   = 0;
      p.rangeToMin     = 7 * 60;
      p.sessionFromMin = 7 * 60;
      p.sessionToMin   = 14 * 60;
      p.sweepMinAtr    = 0.05;
      p.sweepMaxAtr    = 0.50;
      p.reclaimWindowBars = 3;
      p.wickRatio      = 0.60;
      p.bodyRatio      = 0.60;
      p.stopBufferAtr  = 0.10;
      p.minStopAtr     = 0.60;  p.maxStopAtr = 1.50;
      p.entryRetrace   = 0.50;
      p.targetR        = InpFadeTargetR;
      if(!SigSweepReclaim(ctx, p, plan)) return false;
      plan.reason = StringFormat("PR10-FADE %s %s", ctx.symbol, plan.reason);
      return true;
   }

   //--- Rejected by the PR10 findings (kept out of the code on purpose):
   //---   * M1 scalping / ORB        : real costs flip the champion to -1.03R
   //---   * winner pyramiding        : underperformed the single-entry baseline
   //---   * Fibonacci progression    : 18% 99th-percentile sequence drawdown
   //---   * free-margin stacking     : one gapping shock doubles the drawdown
   void Manage(SEAContext &ctx)
   {
      if(ctx.symbol != "XAUUSD") return;
      //--- chandelier trail on the gold swing leg: 2.5 x daily ATR behind the extreme
      double atr = ctx.atrD1;
      if(atr <= 0.0) return;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;
         bool   isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         double sl    = PositionGetDouble(POSITION_SL);
         double tp    = PositionGetDouble(POSITION_TP);
         double cur   = PositionGetDouble(POSITION_PRICE_CURRENT);
         double newSl = isBuy ? cur - InpGoldTrailAtr * atr : cur + InpGoldTrailAtr * atr;
         if((isBuy && newSl > sl) || (!isBuy && (sl <= 0.0 || newSl < sl)))
            g_eaExec.Modify(t, eaRoundSafe(ctx.symbol, newSl), tp);
      }
   }
};

CPr10RoiImprovements g_Pr10RoiImprovements;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Pr10RoiImprovements);
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
