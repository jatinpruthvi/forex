//+------------------------------------------------------------------+
//| EA_studyarena_round4_contestant_a__1_.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 4A(1) - leverage layer: liquidity sniper, gamma scalp and asymmetric exit
//| Source document : docs_v1/docs/coreIdea/studyarena-round4-contestant-a (1).md
//| Tracker entry   : #39  |  Magic: 2008
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound4A class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 4A(1) - leverage layer: liquidity sniper, gamma scalp and asymmetric exit"
#property description "Source: docs_v1/docs/coreIdea/studyarena-round4-contestant-a (1).md"

#include "..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD";      // Comma separated universe
input double          InpRiskPct          = 0.5;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 0;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 20;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 5;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2008; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpSniperStopR        = 1.00;  // Liquidity sniper: 1.0R stop
input double InpSniperTargetR       = 5.00;  // Liquidity sniper: 5R target
input double InpVolumeSurgeMult     = 2.50;  // Volume surge vs 30-bar median
input double InpAsymStopFactor      = 0.70;  // Asymmetric exit: 0.7R stop factor
input bool   InpGammaScalpEnabled   = true;  // Delta-hedge the runner after the partial
input double InpGammaHedgeRatio     = 0.50;  // Hedge 50% of the remaining volume
input int    InpGammaTargetPips     = 15;    // Gamma scalp profit target (pips)
input double InpFundedRiskPct       = 0.30;  // Funded-account mode risk (0.3%)

//+------------------------------------------------------------------+
//| Strategy: Round 4A(1) - leverage layer: liquidity sniper, gamma scalp and asymmetric exit
//+------------------------------------------------------------------+
class CRound4A : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R4A_LEVERAGE_LAYER";
      cfg.sourceDoc             = "docs_v1/docs/coreIdea/studyarena-round4-contestant-a (1).md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = MathMin(InpRiskPct, InpFundedRiskPct);   // funded guard rail
      cfg.signalTimeframe       = PERIOD_M15;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 600;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 20;  cfg.sessionEndMin   = 0;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      //--- asymmetric exit ladder: 25% at 1R, 25% at 2R, runner to 5R
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 25.0;
      cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 25.0;
      cfg.breakEvenAtR          = 1.00;
      cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 1.00;
      cfg.timeStopMinutes       = 0;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- Lever 4: liquidity sniper - swing failure with a volume surge and CVD divergence
      if(SniperSetup(ctx, plan)) return true;

      //--- secondary: stop run of the session range, counter-trend to the failed swing
      SSweepParams p;
      p.Reset();
      p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
      p.sessionFromMin = 7 * 60; p.sessionToMin = 16 * 60;
      p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
      p.reclaimWindowBars = 3; p.wickRatio = 0.55; p.bodyRatio = 0.55;
      p.stopBufferAtr = 0.10; p.minStopAtr = 0.50; p.maxStopAtr = 1.50;
      p.entryRetrace = 0.50; p.targetR = InpSniperTargetR;
      if(!SigSweepReclaim(ctx, p, plan)) return false;
      ApplyAsymmetricStop(plan);
      plan.reason = "R4A-SNIPER " + plan.reason;
      return true;
   }

   ulong m_hedgeBase[12];
   ulong m_hedgeTicket[12];
   int   m_hedgeCount;

   //--- Lever 4: swing failure + volume surge + cumulative-volume divergence
   bool SniperSetup(SEAContext &ctx, SSignalPlan &plan)
   {
      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 40, r) < 25) return false;
      //--- volume surge vs 30-bar median
      double vols[];
      ArrayResize(vols, 30);
      for(int i = 0; i < 30; i++) vols[i] = (double)r[i].tick_volume;
      ArraySort(vols);
      double median = vols[15];
      if(median <= 0.0 || r[0].tick_volume < InpVolumeSurgeMult * median) return false;

      double highs[], lows[];
      int    hiIdx[], loIdx[];
      if(SigFractals(ctx.symbol, 6, highs, lows, hiIdx, loIdx) < 2) return false;
      if(ArraySize(highs) < 2 || ArraySize(lows) < 2) return false;

      //--- CVD proxy: signed tick flow over the last 10 bars
      double cvd = 0.0;
      for(int i = 0; i < 10; i++)
         cvd += (r[i].close >= r[i].open ? 1.0 : -1.0) * (double)r[i].tick_volume;
      bool bearDiv = (highs[0] > highs[1] && cvd < 0.0 && ctx.mid < highs[0]);
      bool bullDiv = (lows[0] < lows[1] && cvd > 0.0 && ctx.mid > lows[0]);

      int dir = bearDiv ? -1 : (bullDiv ? +1 : 0);
      if(dir == 0) return false;

      double stopDist = InpSniperStopR * ctx.atr;
      if(stopDist <= 0.0) return false;
      plan.Reset();
      plan.dir      = dir;
      plan.entry    = ctx.mid;
      plan.stop     = (dir > 0) ? ctx.mid - stopDist : ctx.mid + stopDist;
      plan.riskDist = stopDist;
      plan.target   = (dir > 0) ? ctx.mid + InpSniperTargetR * stopDist
                                : ctx.mid - InpSniperTargetR * stopDist;
      plan.score    = 70.0;
      plan.reason   = StringFormat("R4A-LIQUIDITYSNIPER(vol %.1fx)", (double)r[0].tick_volume / median);
      ApplyAsymmetricStop(plan);
      return true;
   }

   //--- Lever 2: asymmetric exit - tighten the stop to 0.7R of the structural swing
   void ApplyAsymmetricStop(SSignalPlan &plan)
   {
      if(plan.riskDist <= 0.0) return;
      double tight = InpAsymStopFactor * plan.riskDist;
      plan.stop     = (plan.dir > 0) ? plan.entry - tight : plan.entry + tight;
      plan.riskDist = tight;
   }

   //--- Lever 1: gamma scalp - put on a delta hedge once the first partial is banked
   void Manage(SEAContext &ctx)
   {
      if(!InpGammaScalpEnabled) return;
      SyncGamma(ctx);
   }

   int HedgeSlot(const ulong base)
   {
      for(int i = 0; i < m_hedgeCount; i++) if(m_hedgeBase[i] == base) return i;
      return -1;
   }

   void DropHedge(const int i)
   {
      for(int j = i; j < m_hedgeCount - 1; j++)
      { m_hedgeBase[j] = m_hedgeBase[j + 1]; m_hedgeTicket[j] = m_hedgeTicket[j + 1]; }
      m_hedgeCount--;
   }

   void SyncGamma(SEAContext &ctx)
   {
      //--- 1) retire closed hedges and take profit on scalps that reached the target
      for(int i = m_hedgeCount - 1; i >= 0; i--)
      {
         if(!PositionSelectByTicket(m_hedgeBase[i]) || !PositionSelectByTicket(m_hedgeTicket[i]))
         { DropHedge(i); continue; }
         if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;
         bool   isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double cur   = PositionGetDouble(POSITION_PRICE_CURRENT);
         double pip   = EA_PipSize(ctx.symbol);
         double gain  = isBuy ? (cur - entry) / pip : (entry - cur) / pip;
         if(gain >= InpGammaTargetPips)
         {
            g_eaExec.Close(m_hedgeTicket[i], "gamma scalp target");
            DropHedge(i);
         }
      }
      if(m_hedgeCount >= 12) return;

      //--- 2) hedge each runner whose first partial has been banked
      for(int t = 0; t < g_eaTrackCount; t++)
      {
         if(g_eaTrack[t].symbol != ctx.symbol) continue;
         if(!g_eaTrack[t].p1Done) continue;
         if(HedgeSlot(g_eaTrack[t].ticket) >= 0) continue;
         if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;
         double vol = PositionGetDouble(POSITION_VOLUME) * InpGammaHedgeRatio;
         double minV = SymbolInfoDouble(ctx.symbol, SYMBOL_VOLUME_MIN);
         if(vol < minV) vol = minV;
         double pip = EA_PipSize(ctx.symbol);
         double px  = (g_eaTrack[t].dir > 0) ? ctx.bid : ctx.ask;
         double sl  = (g_eaTrack[t].dir > 0) ? px + 15.0 * pip : px - 15.0 * pip;
         double tp  = (g_eaTrack[t].dir > 0) ? px - InpGammaTargetPips * pip
                                             : px + InpGammaTargetPips * pip;
         if(g_eaExec.OpenMarket(ctx.symbol, -g_eaTrack[t].dir, vol, sl, tp, "gamma scalp"))
         {
            m_hedgeBase[m_hedgeCount] = g_eaTrack[t].ticket;
            m_hedgeTicket[m_hedgeCount] = NewestHedgeTicket(ctx.symbol);
            m_hedgeCount++;
         }
      }
   }

   ulong NewestHedgeTicket(const string sym)
   {
      ulong best = 0;
      datetime newest = 0;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != sym) continue;
         if(PositionGetInteger(POSITION_TIME) >= newest && PositionGetString(POSITION_COMMENT) == "gamma scalp")
         { newest = PositionGetInteger(POSITION_TIME); best = t; }
      }
      return best;
   }
};

CRound4A g_Round4A;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round4A);
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
