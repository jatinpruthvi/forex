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

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY";      // Comma separated universe
input double          InpRiskPct          = 0.4;   // Base risk per trade (% of equity)
input double          InpDailyLossPct     = 1.0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 10;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 10;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 2;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 3104; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpPhaseInitialBalance = 2500.0; // Persisted phase initial balance (LOCKED sizing base)
input double InpSpreadMedianMult   = 1.50;  // Spread gate: x times the symbol/minute median
input int    InpSpreadSamples      = 64;    // Rolling spread window (M5 samples)
input double InpCommissionPerLotRT = 7.00;  // Round-turn commission per lot
input double InpMaxCostR           = 0.10;  // Round-trip cost ceiling in R
enum ENUM_T5K_PROFILE
{
   T5K_ROUTE_A      = 0,  // Route A sweep/reclaim (research module)
   T5K_M1_MOMENTUM  = 1   // M1 Momentum Reversion (active first-challenge module)
};
input ENUM_T5K_PROFILE InpProfile          = T5K_M1_MOMENTUM; // Active module per doc section 2
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
input string InpNewsFile           = "the5ers_red_news.csv"; // Red-folder calendar (MQL5/Files)
input int    InpNewsBeforeMin      = 30;    // Cancel/protect before the event
input int    InpNewsAfterMin       = 30;    // No retries after the event
input double InpQualifyingDayCash   = 12.50;  // 0.5% of $2,500: qualifying-day amount
input int    InpQualifyingDayCount  = 3;      // Qualifying days required per phase

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
      bool m1Mode = (InpProfile == T5K_M1_MOMENTUM);
      cfg.riskPct               = m1Mode ? 0.50 : InpRiskPct;   // M1 module: 0.50% of initial balance
      cfg.riskBaseBalance       = false;
      cfg.signalTimeframe       = m1Mode ? PERIOD_M1 : PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;              // estimated cost <= 0.10R
      cfg.dailyLossPct          = InpDailyLossPct;          // internal -1.0% incl. floating
      cfg.weeklyLossPct         = 2.0;                      // internal -2.0% incl. floating
      cfg.totalDdPct            = InpTotalDdPct;
      cfg.profitTargetPct       = InpProfitTargetPct;       // $2,750 phase-1 target
      cfg.maxTradesPerDay       = MathMin(m1Mode ? 5 : InpMaxTradesPerDay, 2); // account rule: 2 sequential trades/day
      cfg.maxOpenPositions      = 1;                        // one working entry/position
      cfg.minSecondsBetweenTrades = 60;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;                     // flat at the session hard stop
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 21;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.pendingExpiryMinutes  = 15;                       // cancel after three M5 candles
      cfg.timeStopMinutes       = InpTimeStopMinutes;        // 45-minute plateau
      cfg.breakEvenAtR          = 0.0;                       // M1 contract: fixed stop, +1.5R target
      cfg.breakEvenAtR          = 0.0;                      // no BE in the baseline profile
      cfg.partial1AtR           = 0.0;                      // never partial-size on a small account
      cfg.newsFilter            = true;                     // cancel on blackout (inert without the file)
      cfg.newsFile              = InpNewsFile;
      cfg.newsBeforeMin         = InpNewsBeforeMin;
      cfg.newsAfterMin          = InpNewsAfterMin;
      cfg.newsFailClosed        = true;                     // bad calendar = no new entries
      cfg.qualifyingDayAmount   = InpQualifyingDayCash;
      cfg.qualifyingDaysTarget  = InpQualifyingDayCount;
      //--- LOCKED: phase-initial balance is the sizing base; one working entry account-wide
      cfg.riskBaseInitialBalance = true;  cfg.riskInitialBalance = InpPhaseInitialBalance;
      cfg.oneEntryAccountWide    = true;   // no second entry while one is working or open
      cfg.flattenOnHalt          = true;   // governor halt = cancel entries + close
      cfg.newsFlatBeforeMin      = 15.0;   // flat 15 min before a relevant red event

      cfg.dayAnchorServer        = true;   // firm rollover on the SERVER day, never the clock day
      cfg.dayLockFirstWin        = true;   // any first net-positive exit locks the day

      cfg.dayLockAfterTrades     = 2;      // two completed sequential trades end the day
      cfg.dayLockAfterLosses     = 2;      // stop after two full losses (doc section 14)


      cfg.maxRetries           = 1;                        // one revalidated retry only
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      if(ctx.symbol == "USDJPY" && !InpTradeUsdJpyNy) return false;

      //--- shared hard gate: spread no worse than 1.5x its rolling median
      if(!SpreadWithinMedian(ctx)) return false;

      //--- active module (doc section 2): M1 momentum reversion, EURUSD/GBPUSD
      //--- London and USDJPY New York, 0.5% risk, 1.5 x ATR stop, fixed +1.5R
      if(InpProfile == T5K_M1_MOMENTUM)
      {
         if(ctx.symbol != "EURUSD" && ctx.symbol != "GBPUSD" && ctx.symbol != "USDJPY") return false;
         int fromMin = 7 * 60, toMin = 11 * 60;                     // London scan
         if(ctx.symbol == "USDJPY") { fromMin = 13 * 60 + 30; toMin = 16 * 60; }   // New York
         if(ctx.clockMinutes < fromMin || ctx.clockMinutes >= toMin) return false;
         if(ctx.atr <= 0.0) return false;

         MqlRates m[];
         if(EA_Rates(ctx.symbol, PERIOD_M1, 1, 20, m) < 16) return false;
         for(int i = 1; i <= 3; i++)
         {
            double body = MathAbs(m[i].close - m[i].open);
            if(body < 2.5 * ctx.atr) continue;                       // body > 2.5 x ATR(M1,14)
            int dir = (m[i].close < m[i].open) ? +1 : -1;            // fade the extreme candle
            double entry = (dir > 0) ? ctx.ask : ctx.bid;
            double stop  = (dir > 0) ? m[i].low  - 1.5 * ctx.atr
                                     : m[i].high + 1.5 * ctx.atr;
            double risk  = (dir > 0) ? entry - stop : stop - entry;
            if(risk <= 0.0) continue;
            plan.Reset();
            plan.dir      = dir;
            plan.entry    = entry;
            plan.stop     = stop;
            plan.riskDist = risk;
            plan.target   = (dir > 0) ? entry + 1.5 * risk : entry - 1.5 * risk;
            plan.score    = 65.0;
            plan.barsAgo  = i;
            plan.reason   = StringFormat("M1-MOMENTUM %s fade (body %.2f ATR)", ctx.symbol, body / ctx.atr);
            return true;
         }
         return false;
      }

      //--- research module: Route A sweep/reclaim (shadow until separately approved henceforth
      //--- independent validation, doc section 3)

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

   //--- pending hygiene: cancel at the pair's hard stop, on news blackout,
   //--- or when price reaches +1R without filling (rule 8 of the plan)
   void Manage(SEAContext &ctx)
   {
      if(ctx.newsBlocked) g_eaExec.CancelPending(ctx.symbol, "news blackout");

      int endMin = (ctx.symbol == "USDJPY") ? 16 * 60 : 11 * 60;
      for(int o = OrdersTotal() - 1; o >= 0; o--)
      {
         ulong t = OrderGetTicket(o);
         if(t == 0) continue;
         if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagicNumber) continue;
         string sym = OrderGetString(ORDER_SYMBOL);
         if(sym != ctx.symbol) continue;
         if(ctx.clockMinutes >= endMin)
         {
            g_eaExec.CancelPending(sym, "pair session end");
            continue;
         }
         long type = OrderGetInteger(ORDER_TYPE);
         bool isBuy = (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP);
         double px  = OrderGetDouble(ORDER_PRICE_OPEN);
         double sl  = OrderGetDouble(ORDER_SL);
         double risk = MathAbs(px - sl);
         if(risk <= 0.0) continue;
         if(isBuy  && (ctx.bid - px) >= risk) g_eaExec.CancelPending(sym, "+1R without fill");
         if(!isBuy && (px - ctx.ask) >= risk) g_eaExec.CancelPending(sym, "+1R without fill");
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
