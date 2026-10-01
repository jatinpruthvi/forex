//+------------------------------------------------------------------+
//| EA_studyarena_round11_contestant_b.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 11B - cost-of-business governor with virtual stops and hard-stop camouflage
//| Source document : docs/research/study_arena/studyarena-round11-contestant-b.md
//| Tracker entry   : #69  |  Magic: 2036
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound11B class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 11B - cost-of-business governor with virtual stops and hard-stop camouflage"
#property description "Source: docs/research/study_arena/studyarena-round11-contestant-b.md"

#include "..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY,XAUUSD";      // Comma separated universe
input double          InpRiskPct          = 0.75;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 0;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 20;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 6;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2036; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpMaxCobPct         = 5.00;  // Cost-of-Business = spread/ATR must stay < 5%
input double InpHardStopMult      = 3.00;  // Broker hard stop = 3x the virtual stop
input double InpVirtualTakeR      = 2.00;  // Virtual TP at 2R (managed locally)

//+------------------------------------------------------------------+
//| Strategy: Round 11B - cost-of-business governor with virtual stops and hard-stop camouflage
//+------------------------------------------------------------------+
class CRound11B : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R11B_COB_VIRTUAL";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round11-contestant-b.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 600;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.timeStopMinutes       = 240;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- governor: CoB = spread / M15 ATR must stay below 5%
      if(!CobOk(ctx)) return false;

      SSweepParams p;
      p.Reset();
      p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
      p.sessionFromMin = 7 * 60; p.sessionToMin = 16 * 60;
      p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
      p.reclaimWindowBars = 3;
      p.wickRatio = 0.60; p.bodyRatio = 0.60;
      p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
      p.entryRetrace = 0.50; p.targetR = InpVirtualTakeR;
      if(!SigSweepReclaim(ctx, p, plan)) return false;

      //--- camouflage: the broker sees a 3x hard stop, the bot manages the real one
      double hard = InpHardStopMult * plan.riskDist;
      plan.stop = (plan.dir > 0) ? plan.entry - hard : plan.entry + hard;
      m_virtualStop[0] = 0.0;                              // filled by Manage when the position opens
      plan.reason = StringFormat("R11B-VIRTUAL(cob %.2f%%) %s",
                                 100.0 * ctx.spreadPoints * ctx.point / MathMax(1e-10, ctx.atr), plan.reason);
      return true;
   }

   double m_virtualStop[16];
   double m_virtualTake[16];
   ulong  m_virtualTicket[16];
   int    m_virtualCount;

   bool CobOk(SEAContext &ctx)
   {
      if(ctx.atr <= 0.0) return false;
      double cost = ctx.spreadPoints * ctx.point;
      return (100.0 * cost / ctx.atr < InpMaxCobPct);
   }

   int Slot(const ulong ticket)
   {
      for(int i = 0; i < m_virtualCount; i++) if(m_virtualTicket[i] == ticket) return i;
      return -1;
   }

   //--- virtual stop/TP engine: local management, broker hard stop only as catastrophe cover
   void Manage(SEAContext &ctx)
   {
      for(int t = 0; t < g_eaTrackCount; t++)
      {
         if(g_eaTrack[t].symbol != ctx.symbol) continue;
         if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;
         int slot = Slot(g_eaTrack[t].ticket);
         if(slot < 0)
         {
            if(m_virtualCount >= 16) continue;
            slot = m_virtualCount++;
            m_virtualTicket[slot] = g_eaTrack[t].ticket;
            double entry = PositionGetDouble(POSITION_PRICE_OPEN);
            double risk  = g_eaTrack[t].riskDist;
            m_virtualStop[slot] = (g_eaTrack[t].dir > 0) ? entry - risk : entry + risk;
            m_virtualTake[slot] = (g_eaTrack[t].dir > 0) ? entry + InpVirtualTakeR * risk
                                                         : entry - InpVirtualTakeR * risk;
         }
         double cur = PositionGetDouble(POSITION_PRICE_CURRENT);
         bool hitStop = (g_eaTrack[t].dir > 0) ? (cur <= m_virtualStop[slot]) : (cur >= m_virtualStop[slot]);
         bool hitTake = (g_eaTrack[t].dir > 0) ? (cur >= m_virtualTake[slot]) : (cur <= m_virtualTake[slot]);
         if(hitStop) { g_eaExec.Close(g_eaTrack[t].ticket, "virtual stop"); }
         else if(hitTake) { g_eaExec.Close(g_eaTrack[t].ticket, "virtual take profit"); }
      }
   }
};

CRound11B g_Round11B;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round11B);
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
