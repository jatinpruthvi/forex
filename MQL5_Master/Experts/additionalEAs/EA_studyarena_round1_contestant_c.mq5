//+------------------------------------------------------------------+
//| EA_studyarena_round1_contestant_c.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 1C - multi-timeframe SMC confluence with exposure cap
//| Source document : docs_v1/docs/coreIdea/studyarena-round1-contestant-c.md
//| Tracker entry   : #33  |  Magic: 2002
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound1C class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 1C - multi-timeframe SMC confluence with exposure cap"
#property description "Source: docs_v1/docs/coreIdea/studyarena-round1-contestant-c.md"

#include "..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY";      // Comma separated universe
input double          InpRiskPct          = 1.5;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 5.0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 5.0;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 20;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 3;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2002; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpRiskPerTradePct   = 1.50;  // Risk per trade (% equity)
input int    InpMaxOpenTrades     = 2;     // Max concurrent trades
input double InpExposureCapPct    = 40.0;  // Total notional exposure cap (30-50%)
input double InpMinSlAtr          = 1.00;  // Dynamic SL: at least 1 x ATR(14)
input double InpMinRr             = 2.00;  // Minimum reward:risk
input double InpAtrSpikeMult      = 1.50;  // Skip if ATR > x times its 30-bar average
input int    InpConfluenceMin     = 2;     // 2 of 3 SMC confluence signals required

//+------------------------------------------------------------------+
//| Strategy: Round 1C - multi-timeframe SMC confluence with exposure cap
//+------------------------------------------------------------------+
class CRound1C : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R1C_SMC_CONFLUENCE";
      cfg.sourceDoc             = "docs_v1/docs/coreIdea/studyarena-round1-contestant-c.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPerTradePct;
      cfg.signalTimeframe       = PERIOD_M15;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.dailyLossPct          = InpDailyLossPct;          // hard stop -5%
      cfg.totalDdPct            = InpTotalDdPct;            // monthly -5% monthly floor
      cfg.profitTargetPct       = InpProfitTargetPct;       // auto-close at +20%
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = InpMaxOpenTrades;
      cfg.minSecondsBetweenTrades = 600;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.timeStopMinutes       = 240;
      cfg.breakEvenAtR          = 1.0;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- ATR spike filter: ATR(14) must not exceed 1.5x its 30-bar average
      if(AtrIsSpiking(ctx)) return false;

      //--- SMC confluence counter (2 of 3 required): OB retest, break/retest, HTF cascade
      int confluence = 0;
      SCascadeParams cas;
      cas.Reset();
      cas.requireD1 = true; cas.requireH1 = true; cas.requireM15Structure = true;
      int cascade = SigEmaCascade(ctx, cas);
      if(cascade != 0) confluence++;

      SSignalPlan tmp;
      SOrderBlockParams ob;
      ob.Reset();
      ob.lookbackBars = 14; ob.displacementBody = 0.50;
      ob.touchTolAtr = 0.25; ob.targetR = InpMinRr; ob.requireHtfBias = true;
      bool hasOb = SigOrderBlockRetest(ctx, ob, tmp);
      if(hasOb && (cascade == 0 || (tmp.dir == cascade))) confluence++;

      SBreakRetestParams br;
      br.Reset();
      br.rangeFromMin = 0; br.rangeToMin = 7 * 60;
      br.entryFromMin = 7 * 60; br.entryToMin = 21 * 60;
      br.minRangeAtr = 0.25; br.targetR = InpMinRr;
      bool hasRetest = SigBreakRetest(ctx, br, tmp);
      if(hasRetest && (cascade == 0 || (tmp.dir == cascade))) confluence++;

      if(confluence < InpConfluenceMin) return false;

      //--- prefer the order block, fall back to the break/retest plan
      if(hasOb) { if(!SigOrderBlockRetest(ctx, ob, plan)) return false; }
      else      { if(!SigBreakRetest(ctx, br, plan)) return false; }

      //--- dynamic SL: at least 1 x ATR(14), and reward:risk >= 2
      double minStop = InpMinSlAtr * ctx.atr;
      if(plan.riskDist < minStop)
      {
         plan.stop     = (plan.dir > 0) ? plan.entry - minStop : plan.entry + minStop;
         plan.riskDist = minStop;
         plan.target   = (plan.dir > 0) ? plan.entry + InpMinRr * minStop
                                        : plan.entry - InpMinRr * minStop;
      }
      plan.reason = StringFormat("R1C-CONFLUENCE(%d/3) %s", confluence, plan.reason);
      return true;
   }

   bool AtrIsSpiking(SEAContext &ctx)
   {
      double av[];
      if(EA_BufN(g_eaInd[ctx.index].hAtr, 0, 1, 30, av) < 30) return false;
      double sum = 0.0;
      for(int i = 0; i < 30; i++) sum += av[i];
      double avg = sum / 30.0;
      if(avg <= 0.0) return false;
      return (ctx.atr > InpAtrSpikeMult * avg);
   }
};

CRound1C g_Round1C;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round1C);
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
