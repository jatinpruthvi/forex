//+------------------------------------------------------------------+
//| EA_studyarena_round4_contestant_e.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Round 4E - pair/session map with correlation groups and exact entry steps
//| Source document : docs/research/study_arena/studyarena-round4-contestant-e.md
//| Tracker entry   : #45  |  Magic: 2014
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CRound4E class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "Round 4E - pair/session map with correlation groups and exact entry steps"
#property description "Source: docs/research/study_arena/studyarena-round4-contestant-e.md"

#include "..\..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY,AUDUSD,USDCAD,EURGBP,AUDNZD";      // Comma separated universe
input double          InpRiskPct          = 1.0;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 2.0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 5.0;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 20;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 5;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 2014; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpEurAsiaMinPips   = 15;    // EURUSD Asian range floor (pips)
input double InpEurAsiaMaxPips     = 35;    // EURUSD Asian range ceiling
input double InpGbpAsiaMaxPips     = 45;    // GBPUSD Asian range ceiling
input double InpGroupRiskPct       = 1.00;  // Max open risk per correlation group
input double InpNyVwapTolAtr       = 0.50;  // NY continuation: distance to 30m VWAP

//+------------------------------------------------------------------+
//| Strategy: Round 4E - pair/session map with correlation groups and exact entry steps
//+------------------------------------------------------------------+
class CRound4E : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "R4E_PAIR_SESSION_MAP";
      cfg.sourceDoc             = "docs/research/study_arena/studyarena-round4-contestant-e.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.totalDdPct            = InpTotalDdPct;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 2;
      cfg.minSecondsBetweenTrades = 600;
      cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 22;  cfg.sessionEndMin   = 0;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;
      cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 40.0;
      cfg.breakEvenAtR          = 1.00;
      cfg.timeStopMinutes       = 300;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      if(GroupBlocked(ctx)) return false;

      //--- Strategy 1: London liquidity sweep + continuation (EURUSD / GBPUSD, 07:00-10:30)
      if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 10 * 60 + 30 &&
         (StringFind(ctx.symbol, "EURUSD") >= 0 || StringFind(ctx.symbol, "GBPUSD") >= 0))
      {
         if(!AsiaRangeInBand(ctx)) return false;
         //--- H1 trend agreement: above/below the 50-EMA with the 20-EMA sloping
         if(!H1TrendAgrees(ctx)) return false;
         SSweepParams p;
         p.Reset();
         p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
         p.sessionFromMin = 7 * 60; p.sessionToMin = 10 * 60 + 30;
         p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
         p.reclaimWindowBars = 3; p.wickRatio = 0.55; p.bodyRatio = 0.55;
         p.stopBufferAtr = 0.10; p.minStopAtr = 0.50; p.maxStopAtr = 1.50;
         p.entryRetrace = 0.50; p.targetR = 2.0;
         if(!SigSweepReclaim(ctx, p, plan)) return false;
         plan.reason = "R4E-LONDONSWEEP " + plan.reason;
         return true;
      }

      //--- Strategy 2: New York opening-range continuation (USDJPY / USDCAD / EURUSD)
      if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 16 * 60)
      {
         if(!LondonDirectional(ctx)) return false;
         if(!SigEmaPullback(ctx, NyParams(), plan)) return false;
         plan.reason = "R4E-NYCONTINUATION " + plan.reason;
         return true;
      }

      //--- Strategy 3: Asian range breakout (AUDUSD / USDJPY)
      if(ctx.clockMinutes < 3 * 60 && (StringFind(ctx.symbol, "AUD") >= 0 || StringFind(ctx.symbol, "JPY") >= 0))
      {
         if(ctx.adx14 <= 20.0) return false;
         if(!SigAsianBreakout(ctx, 0.10, 0.20, 2.0, plan)) return false;
         plan.reason = "R4E-ASIANBREAK " + plan.reason;
         return true;
      }
      return false;
   }

   SEmaPullbackParams NyParams()
   {
      SEmaPullbackParams ep;
      ep.Reset();
      ep.emaPeriod = 20; ep.maxDistanceAtr = InpNyVwapTolAtr;
      ep.requireTrend = true; ep.targetR = 2.0;
      return ep;
   }

   bool H1TrendAgrees(SEAContext &ctx)
   {
      if(ctx.emaH1_50 <= 0.0) return false;
      bool up = (ctx.mid > ctx.emaH1_50 && ctx.ema50 > ctx.emaH1_50);
      bool dn = (ctx.mid < ctx.emaH1_50 && ctx.ema50 < ctx.emaH1_50);
      return (up || dn);
   }

   bool LondonDirectional(SEAContext &ctx)
   {
      MqlRates h1[];
      if(EA_Rates(ctx.symbol, PERIOD_H1, 1, 4, h1) < 3) return false;
      return (MathAbs(h1[0].close - h1[2].open) > 0.25 * ctx.atr * 4.0);
   }

   bool AsiaRangeInBand(SEAContext &ctx)
   {
      double hi = 0.0, lo = 0.0;
      if(!SigAsianRange(ctx.symbol, hi, lo)) return false;
      double pip = EA_PipSize(ctx.symbol);
      if(pip <= 0.0) return false;
      double pips = (hi - lo) / pip;
      if(StringFind(ctx.symbol, "GBPUSD") >= 0)
         return (pips >= 20.0 && pips <= InpGbpAsiaMaxPips);
      return (pips >= InpEurAsiaMinPips && pips <= InpEurAsiaMaxPips);
   }

   //--- one open trade per correlation group (USD / JPY / commodity / European cross)
   bool GroupBlocked(SEAContext &ctx)
   {
      if(ctx.openPositionsAll == 0) return false;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         string other = PositionGetString(POSITION_SYMBOL);
         if(other == ctx.symbol) continue;
         if(SharesGroup(ctx.symbol, other)) return true;
      }
      return false;
   }

   bool SharesGroup(const string a, const string b)
   {
      string groups[4][6];
      groups[0][0] = "EURUSD"; groups[0][1] = "GBPUSD"; groups[0][2] = "AUDUSD";
      groups[0][3] = "USDCAD"; groups[0][4] = "NZDUSD"; groups[0][5] = "USDCHF";
      groups[1][0] = "USDJPY"; groups[1][1] = "GBPJPY"; groups[1][2] = "EURJPY";
      groups[1][3] = "AUDJPY"; groups[1][4] = "";       groups[1][5] = "";
      groups[2][0] = "EURGBP"; groups[2][1] = "EURCHF"; groups[2][2] = "";
      groups[2][3] = "";       groups[2][4] = "";       groups[2][5] = "";
      groups[3][0] = "AUDNZD"; groups[3][1] = "AUDUSD"; groups[3][2] = "NZDUSD";
      groups[3][3] = "AUDJPY"; groups[3][4] = "";       groups[3][5] = "";
      for(int g = 0; g < 4; g++)
      {
         bool hasA = false, hasB = false;
         for(int i = 0; i < 6; i++)
         {
            if(groups[g][i] == "") continue;
            if(StringFind(a, groups[g][i]) >= 0) hasA = true;
            if(StringFind(b, groups[g][i]) >= 0) hasB = true;
         }
         if(hasA && hasB) return true;
      }
      return false;
   }
};

CRound4E g_Round4E;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_Round4E);
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
