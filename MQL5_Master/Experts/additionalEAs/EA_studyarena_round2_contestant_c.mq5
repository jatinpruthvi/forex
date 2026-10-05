//+------------------------------------------------------------------+
//| EA_studyarena_round2_contestant_c.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 2C - SMC pillars: HTF bias, fractal sweep, CHoCH and OB zone
//| Source document : docs_v1/docs/coreIdea/studyarena-round2-contestant-c.md
//| Tracker entry   : #36  |  Magic: 2005
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound2C class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 2C - SMC pillars: HTF bias, fractal sweep, CHoCH and OB zone"
#property description "Source: docs_v1/docs/coreIdea/studyarena-round2-contestant-c.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY,XAUUSD";      // Comma separated universe
input double          InpRiskPct          = 1.0;   // Base risk per trade (% of equity)
input double          InpProfitTargetPct  = 20;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 4;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2005; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input int    InpFractalCount      = 6;     // Last N swing highs/lows scanned
input double InpSweepRr           = 2.00;  // Sweep structure reward:risk
input bool   InpRequireChoch      = true;  // Require the high-low-high-close-high CHoCH
input double InpMaxSpreadPts      = 35.0;  // Over-spread guard: skip this symbol above N points (doc: ~35 for XAU/JPY)

//+------------------------------------------------------------------+
//| Strategy: Round 2C - SMC pillars: HTF bias, fractal sweep, CHoCH and OB zone
//+------------------------------------------------------------------+
class CRound2C : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R2C_SMC_PILLARS";
      cfg.sourceDoc             = "docs_v1/docs/coreIdea/studyarena-round2-contestant-c.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M15;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.profitTargetPct       = InpProfitTargetPct;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 600;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.timeStopMinutes       = 240;
      cfg.breakEvenAtR          = 1.0;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- Pillar 1: H4/H1 higher-timeframe bias (primary directional filter)
      //--- Step 9 safeguard: an over-spread symbol is skipped before any analysis
      if(ctx.spreadPoints > InpMaxSpreadPts)
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.1f pts > %.1f - skip (doc Step 9 over-spread)", ctx.symbol, ctx.spreadPoints, InpMaxSpreadPts), true);
         return false;
      }

      int htfBias = 0;
      if(ctx.emaH1_200 > 0.0 && ctx.emaH1_50 > 0.0)
      {
         if(ctx.mid > ctx.emaH1_200 && ctx.emaH1_50 > ctx.emaH1_200) htfBias = +1;
         if(ctx.mid < ctx.emaH1_200 && ctx.emaH1_50 < ctx.emaH1_200) htfBias = -1;
      }
      if(htfBias == 0) return false;

      //--- Pillar 2 + 3: fractal sweep with CHoCH confirmation
      double highs[], lows[];
      int    hiIdx[], loIdx[];
      if(SigFractals(ctx.symbol, InpFractalCount, highs, lows, hiIdx, loIdx) < 2) return false;

      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 12, r) < 4) return false;
      double lastClose = r[0].close;

      bool sweepLong  = (ArraySize(lows)  >= 2 && lows[0] < lows[1] && lastClose > lows[0]);
      bool sweepShort = (ArraySize(highs) >= 2 && highs[0] > highs[1] && lastClose < highs[0]);
      if(htfBias > 0 && !sweepLong)  return false;
      if(htfBias < 0 && !sweepShort) return false;
      if(sweepLong && sweepShort)    return false;

      if(InpRequireChoch)
      {
         //--- high-low-high-close-high sequence (long) and its mirror
         if(sweepLong)
         {
            bool choch = (r[3].high > r[4].high) && (r[2].low < r[3].low) && (lastClose > r[3].high);
            if(!choch) return false;
         }
         else
         {
            bool choch = (r[3].low < r[4].low) && (r[2].high > r[3].high) && (lastClose < r[3].low);
            if(!choch) return false;
         }
      }

      //--- Pillar 4: order block / FVG proximity is the entry zone
      SOrderBlockParams ob;
      ob.Reset();
      ob.lookbackBars = 16; ob.displacementBody = 0.45;
      ob.touchTolAtr = 0.35; ob.targetR = InpSweepRr;
      //--- one-sided search: the delivered `tradeBothWays = (htfBias > 0)` switched the bearish
      //--- branch OFF exactly when the bias was bearish, so this EA could never go short
      ob.requireHtfBias = true; ob.onlyDir = htfBias;
      SSignalPlan obPlan;
      if(!SigOrderBlockRetest(ctx, ob, obPlan)) return false;
      if(obPlan.dir != htfBias) return false;
      plan = obPlan;
      plan.reason = StringFormat("R2C-PILLARS(bias %s, fractal sweep, CHoCH) %s",
                                 htfBias > 0 ? "bull" : "bear", plan.reason);
      return true;
   }
};

CRound2C g_Round2C;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round2C);
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
