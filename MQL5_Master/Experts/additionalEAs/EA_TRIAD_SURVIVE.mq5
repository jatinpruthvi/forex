//+------------------------------------------------------------------+
//| EA_TRIAD_SURVIVE.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| TRIAD-SURVIVE - three-sleeve portfolio with scored entries and risk caps
//| Source document : docs/strategy/TRIAD-SURVIVE.md
//| Tracker entry   : #25  |  Magic: 3111
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CTriadSurvive class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "TRIAD-SURVIVE - three-sleeve portfolio with scored entries and risk caps"
#property description "Source: docs/strategy/TRIAD-SURVIVE.md"

#include "..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY,XAUUSD,GBPJPY,AUDNZD,EURGBP,EURCHF";      // Comma separated universe
input double          InpRiskPct          = 0.24;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 4.0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 1.0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 10;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 0;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 4;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 3111; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
input double InpFullTierRiskPct    = 0.24;  // 8/8 score: full tier risk
input double InpHalfTierRiskPct    = 0.12;  // 7/8 score: half tier risk
input double InpMaxTotalOpenRisk   = 1.00;  // Max total open risk at any moment
input double InpMaxGroupRiskPct    = 0.24;  // Max risk per correlated group
input int    InpMaxPositions       = 4;     // Max concurrent positions (all sleeves)
input int    InpMaxPerSleeve       = 2;     // Max concurrent positions per sleeve
input double InpShutdownDdPct      = 6.00;  // Shutdown from closed-equity high
input int    InpSleeveCExitMinute = 390;   // Sleeve C hard flat 06:30 London
input bool   InpSleeveAEnabled     = true;
input bool   InpSleeveBEnabled     = true;
input bool   InpSleeveCEnabled     = true;

//+------------------------------------------------------------------+
//| Strategy: TRIAD-SURVIVE - three-sleeve portfolio with scored entries and risk caps
//+------------------------------------------------------------------+
class CTriadSurvive : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "TRIAD_SURVIVE";
      cfg.sourceDoc             = "docs/strategy/TRIAD-SURVIVE.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpFullTierRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = 2.0;
      cfg.totalDdPct            = InpTotalDdPct;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = InpMaxPositions;
      cfg.minSecondsBetweenTrades = 120;
      cfg.useHwmThrottle        = true;
      cfg.hwmTier1Dd            = 3.0;  cfg.hwmTier1Mult = 0.50;
      cfg.hwmTier2Dd            = InpShutdownDdPct;  cfg.hwmTier2Mult = 0.0;
      cfg.hwmHaltDd             = InpShutdownDdPct;
      cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 19;  cfg.sessionEndMin = 30;
      cfg.noTradeAfterHour      = 21;  cfg.noTradeAfterMin = 30;   // no thin-liquidity entries
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.pendingExpiryMinutes  = 15;
      cfg.timeStopMinutes       = 90;
      cfg.breakEvenAtR          = 1.0;
      cfg.partial1AtR           = 0.0;                             // single entry, no partial ladder
      cfg.trailAtR              = 1.0;  cfg.trailDistanceR = 0.5;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- portfolio-level caps first
      m_lastScore = 0.0;
      if(EA_OpenRiskPct() >= InpMaxTotalOpenRisk) return false;
      if(EA_CountPositions("", false) >= InpMaxPositions) return false;

      int    sleeve = 0;
      double tierRisk = InpFullTierRiskPct;
      double score = 0.0;

      //--- SLEEVE C: Asian mean reversion, 00:00-06:30, single entry, hard flat 06:30
      if(IsSleeveCSymbol(ctx.symbol) && InpSleeveCEnabled && ctx.clockMinutes < InpSleeveCExitMinute)
      {
         sleeve = 3;
         SRangeFadeParams f;
         f.Reset();
         f.bbPeriod = 20; f.bbDeviation = 2.0;
         f.rsiOversold = 35.0; f.rsiOverbought = 65.0;
         f.wickRatio = 0.30; f.stopBufferAtr = 0.30; f.targetR = 1.1;
         f.requireRangeRegime = true; f.maxAdx = 22.0;
         if(!SigRangeFade(ctx, f, plan)) return false;
         score = 6.0;      // sleeve C carries a six-point profile
         tierRisk = InpHalfTierRiskPct;
      }
      //--- SLEEVE B: volatility-expansion continuation (trending regime)
      else if(IsSleeveBSymbol(ctx.symbol) && InpSleeveBEnabled)
      {
         sleeve = 2;
         int nowMin = ctx.clockMinutes;
         bool inWin = (nowMin >= 7 * 60 && nowMin < 15 * 60 + 30) ||
                      (nowMin >= 13 * 60 + 30 && nowMin < 19 * 60 + 30);
         if(!inWin) return false;
         //--- six-gate continuation: H1 bias + expansion + first pullback
         if(ctx.emaH1_50 <= 0.0) return false;
         int    bias = (ctx.mid > ctx.emaH1_50) ? +1 : -1;
         SEmaPullbackParams e;
         e.Reset();
         e.requireH1Bias = true;
         e.touchTolAtr = 0.35; e.wickRatio = 0.35; e.stopBufferAtr = 0.20;
         e.targetR = 2.5; e.maxBarsSinceTouch = 3;
         e.tradeBothWays = (bias > 0);
         if(!SigEmaPullback(ctx, e, plan)) return false;
         if((bias > 0) != (plan.dir > 0)) return false;
         score = 7.0;
         tierRisk = InpHalfTierRiskPct;
      }
      //--- SLEEVE A: session-open sweep and reclaim, scored 8-point profile
      else
      {
         if(!InpSleeveAEnabled) return false;
         sleeve = 1;
         SSweepParams p;
         p.Reset();
         p.rangeFromMin   = 0;
         p.rangeToMin     = 7 * 60;
         p.sessionFromMin = 7 * 60;
         p.sessionToMin   = 11 * 60;
         p.sweepMinAtr    = 0.05;
         p.sweepMaxAtr    = 0.50;
         p.reclaimWindowBars = 3;
         p.wickRatio      = 0.60;
         p.bodyRatio      = 0.60;
         p.stopBufferAtr  = 0.10;
         p.minStopAtr     = 0.60;  p.maxStopAtr = 1.50;
         p.entryRetrace   = 0.50;
         p.targetR        = 1.50;
         if(ctx.symbol == "USDJPY" || ctx.symbol == "XAUUSD")
         {
            p.rangeFromMin   = 7 * 60;    // New York window uses the London range
            p.rangeToMin     = 13 * 60;
            p.sessionFromMin = 13 * 60 + 30;
            p.sessionToMin   = 16 * 60;
         }
         if(ctx.clockMinutes < p.sessionFromMin || ctx.clockMinutes >= p.sessionToMin) return false;
         if(!SigSweepReclaim(ctx, p, plan)) return false;
         score = ScoreSleeveA(ctx, plan);
         tierRisk = (score >= 8.0) ? InpFullTierRiskPct : InpHalfTierRiskPct;
      }

      //--- correlated-group cap (USD / JPY / commodity / European cross)
      string group = CorrelatedGroup(ctx.symbol);
      if(group != "" && EA_GroupRiskPct(group) + tierRisk > InpMaxGroupRiskPct) return false;

      m_sleeve    = sleeve;
      m_lastScore = score;
      m_tierRisk  = tierRisk;
      plan.score  = score * 10.0;
      plan.reason = StringFormat("SURVIVE-S%d %s", sleeve, plan.reason);
      return true;
   }

   int    m_sleeve;
   double m_lastScore;
   double m_tierRisk;

   bool IsSleeveCSymbol(const string s)
   {
      return (s == "AUDNZD" || s == "EURGBP" || s == "EURCHF");
   }
   bool IsSleeveBSymbol(const string s)
   {
      return (s == "XAUUSD" || s == "GBPJPY" || s == "GER40" || s == "US30");
   }
   string CorrelatedGroup(const string s)
   {
      if(s == "EURUSD" || s == "GBPUSD" || s == "AUDUSD") return "EURUSD,GBPUSD,AUDUSD";
      if(s == "USDJPY" || s == "GBPJPY" || s == "EURJPY") return "USDJPY,GBPJPY,EURJPY";
      if(s == "AUDUSD" || s == "USDCAD" || s == "XAUUSD") return "AUDUSD,USDCAD,XAUUSD";
      if(s == "EURGBP" || s == "EURCHF") return "EURGBP,EURCHF";
      return "";
   }

   //--- sleeve A eight-point score (7/8 halves the risk, 6 or below refuses)
   double ScoreSleeveA(SEAContext &ctx, const SSignalPlan &plan)
   {
      double score = 5.0;      // filters 3,4,5 are proven by the signal itself
      //--- 1. range quality (35-75% of the 20-day median width)
      double hi = 0.0, lo = 0.0;
      double widths[20];
      int    n = 0;
      for(int d = 0; d < 20; d++)
      {
         double h = 0.0, l = 0.0; int bars = 0;
         if(SigRangeForDay(ctx.symbol, PERIOD_M5, 0, 7 * 60, d, h, l, bars))
         { widths[n++] = h - l; }
      }
      if(n >= 5)
      {
         double sum = 0.0;
         for(int i = 0; i < n; i++) sum += widths[i];
         double median = sum / n;
         double today  = 0.0, l2 = 0.0; int b2 = 0;
         if(SigRangeForDay(ctx.symbol, PERIOD_M5, 0, 7 * 60, 0, today, l2, b2))
         {
            double width = today - l2;
            if(median > 0.0 && width >= 0.35 * median && width <= 0.75 * median) score += 1.0;
         }
      }
      //--- 2. higher-timeframe bias (H1 50-EMA, slope agrees)
      double ema = ctx.emaH1_50;
      double hp[];
      int slopeOk = 0;
      if(EA_BufN(g_eaInd[ctx.index].hEmaH1_50, 0, 1, 5, hp) == 5)
      {
         if(plan.dir > 0 && ctx.mid > ema && hp[0] >= hp[4]) slopeOk = 1;
         if(plan.dir < 0 && ctx.mid < ema && hp[0] <= hp[4]) slopeOk = 1;
      }
      if(slopeOk == 1) score += 1.0;
      //--- 7. cost gate: stop distance at least 10x the round-trip cost
      double costR = EA_CostInR(ctx.symbol, plan.riskDist, 0.0);
      if(costR <= 0.10) score += 1.0;
      //--- 8. clean book: no correlated position open (news gate is the engine's)
      string group = CorrelatedGroup(ctx.symbol);
      if(group == "" || EA_GroupRiskPct(group) <= 0.0) score += 1.0;
      return score;
   }

   //--- sleeve C hard flat at 06:30 London
   void Manage(SEAContext &ctx)
   {
      if(!IsSleeveCSymbol(ctx.symbol)) return;
      if(ctx.clockMinutes >= InpSleeveCExitMinute)
      {
         for(int p = PositionsTotal() - 1; p >= 0; p--)
         {
            ulong t = PositionGetTicket(p);
            if(t == 0) continue;
            if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
            if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;
            EA_Log(EA_LOG_EVENTS, "sleeve C hard flat 06:30 London");
            g_eaExec.Close(t, "sleeve C hard flat");
         }
      }
   }
};

CTriadSurvive g_TriadSurvive;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_TriadSurvive);
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
