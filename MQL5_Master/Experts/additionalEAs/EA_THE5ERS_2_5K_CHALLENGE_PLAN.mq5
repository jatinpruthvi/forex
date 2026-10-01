//+------------------------------------------------------------------+
//| EA_THE5ERS_2_5K_CHALLENGE_PLAN.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| The5ers $2,500 challenge plan - Route A with spread-median and cost gates
//| Source document : docs/prop_firm/THE5ERS-2.5K-CHALLENGE-PLAN.md
//| Tracker entry   : #18  |  Magic: 3104
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CChallengePlan25K class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "The5ers $2,500 challenge plan - Route A with spread-median and cost gates"
#property description "Source: docs/prop_firm/THE5ERS-2.5K-CHALLENGE-PLAN.md"

#include "..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY";      // Comma separated universe
input double          InpRiskPct          = 0.4;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 1.0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 10;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 10;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 2;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 3104; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpSpreadMedianMult   = 1.50;  // Spread gate: x times the symbol/minute median
input int    InpSpreadSamples      = 64;    // Rolling spread window (M5 samples)
input double InpCommissionPerLotRT = 7.00;  // Round-turn commission per lot
input double InpMaxCostR           = 0.10;  // Round-trip cost ceiling in R
input double InpSweepMinAtr        = 0.05;  // Route A: sweep depth band
input double InpSweepMaxAtr        = 0.50;
input double InpReclaimWickRatio   = 0.60;  // Reclaim wick >= x of candle range
input double InpDisplacementBody   = 0.60;  // Displacement body >= x of range
input double InpStopBufferAtr      = 0.10;  // Stop beyond the sweep extreme
input double InpStopMinAtr         = 0.60;  // Reject stop outside [0.60, 1.50] ATR
input double InpStopMaxAtr         = 1.50;
input double InpTargetR            = 1.50;  // Fixed validated target
input int    InpTimeStopMinutes    = 45;    // +1R plateau time stop
input bool   InpTradeUsdJpyNy      = true;  // USDJPY New York combination

//+------------------------------------------------------------------+
//| Strategy: The5ers $2,500 challenge plan - Route A with spread-median and cost gates
//+------------------------------------------------------------------+
class CChallengePlan25K : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "THE5ERS_25K_PLAN";
      cfg.sourceDoc             = "docs/prop_firm/THE5ERS-2.5K-CHALLENGE-PLAN.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;               // 0.40% evaluation default
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;              // estimated cost <= 0.10R
      cfg.dailyLossPct          = InpDailyLossPct;          // internal -1.0% incl. floating
      cfg.weeklyLossPct         = 2.0;                      // internal -2.0% incl. floating
      cfg.totalDdPct            = InpTotalDdPct;
      cfg.profitTargetPct       = InpProfitTargetPct;       // $2,750 phase-1 target
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;       // max two sequential trades
      cfg.maxOpenPositions      = 1;                        // one working entry/position
      cfg.minSecondsBetweenTrades = 60;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;                     // flat at the session hard stop
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 21;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.pendingExpiryMinutes  = 15;                       // cancel after three M5 candles
      cfg.timeStopMinutes       = InpTimeStopMinutes;
      cfg.breakEvenAtR          = 0.0;                      // no BE in the baseline profile
      cfg.partial1AtR           = 0.0;                      // never partial-size on a small account
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      if(ctx.symbol == "USDJPY" && !InpTradeUsdJpyNy) return false;

      //--- shared hard gate: spread no worse than 1.5x its rolling median
      if(!SpreadWithinMedian(ctx)) return false;

      SSweepParams p;
      p.Reset();
      p.rangeFromMin   = 0;
      p.rangeToMin     = 7 * 60;
      p.sessionFromMin = 7 * 60;
      p.sessionToMin   = 11 * 60;
      p.sweepMinAtr    = InpSweepMinAtr;
      p.sweepMaxAtr    = InpSweepMaxAtr;
      p.reclaimWindowBars = 3;
      p.wickRatio      = InpReclaimWickRatio;
      p.bodyRatio      = InpDisplacementBody;
      p.stopBufferAtr  = InpStopBufferAtr;
      p.minStopAtr     = InpStopMinAtr;
      p.maxStopAtr     = InpStopMaxAtr;
      p.entryRetrace   = 0.50;                 // limit at 50% of the displacement body
      p.targetR        = InpTargetR;

      if(ctx.symbol == "USDJPY")
      {
         p.rangeFromMin   = 7 * 60;            // New York: 07:00-13:00 reference range
         p.rangeToMin     = 13 * 60;
         p.sessionFromMin = 13 * 60 + 30;
         p.sessionToMin   = 16 * 60;
      }
      if(ctx.clockMinutes < p.sessionFromMin || ctx.clockMinutes >= p.sessionToMin) return false;

      if(!SigSweepReclaim(ctx, p, plan)) return false;
      plan.reason = StringFormat("25K-ROUTE-A %s %s", ctx.symbol, plan.reason);
      return true;
   }

   //--- rolling spread median per symbol (sampled once per closed M5 bar)
   bool SpreadWithinMedian(SEAContext &ctx)
   {
      int slot = -1;
      for(int i = 0; i < g_eaSymbolCount; i++) if(g_eaSymbols[i] == ctx.symbol) slot = i;
      if(slot < 0 || slot >= EA_MAX_SYMBOLS) return true;

      datetime barTime = iTime(ctx.symbol, PERIOD_M5, 0);
      if(m_spreadCount[slot] == 0 || m_spreadLast[slot] != barTime)
      {
         int cap = (int)MathMin(InpSpreadSamples, 64);
         for(int i = (cap - 1); i > 0; i--) m_spread[slot][i] = m_spread[slot][i - 1];
         m_spread[slot][0]   = ctx.spreadPoints;
         m_spreadCount[slot] = (int)MathMin(m_spreadCount[slot] + 1, cap);
         m_spreadLast[slot]  = barTime;
      }
      int n = (int)MathMin(m_spreadCount[slot], 64);
      if(n < 8) return true;                              // warm-up: no median yet

      double arr[64];
      for(int i = 0; i < n; i++) arr[i] = m_spread[slot][i];
      for(int i = 1; i < n; i++)                          // insertion sort of the valid window
      {
         double key = arr[i];
         int    j   = i - 1;
         while(j >= 0 && arr[j] > key) { arr[j + 1] = arr[j]; j--; }
         arr[j + 1] = key;
      }
      double median = arr[n / 2];
      if(median <= 0.0) return true;
      if(ctx.spreadPoints > InpSpreadMedianMult * median)
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.1f > %.2fx median %.1f - skip",
                ctx.symbol, ctx.spreadPoints, InpSpreadMedianMult, median), true);
         return false;
      }
      return true;
   }

   double   m_spread[EA_MAX_SYMBOLS][64];
   int      m_spreadCount[EA_MAX_SYMBOLS];
   datetime m_spreadLast[EA_MAX_SYMBOLS];

   void OnInitStrategy()
   {
      for(int i = 0; i < EA_MAX_SYMBOLS; i++)
      {
         m_spreadCount[i] = 0;
         m_spreadLast[i]  = 0;
         for(int j = 0; j < 64; j++) m_spread[i][j] = 0.0;
      }
   }
};

CChallengePlan25K g_ChallengePlan25K;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_ChallengePlan25K);
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
