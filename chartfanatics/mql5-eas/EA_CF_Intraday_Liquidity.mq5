//+------------------------------------------------------------------+
//|                                   EA_CF_Intraday_Liquidity.mq5   |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| ChartFanatics: Intraday Liquidity & Volatility Model (JadeCap)   |
//| Card    : chartfanatics/todos/intraday-liquidity-volatility-model.md (#12)
//| Source  : chartfanatics/pdf/intraday-liquidity-volatility-model.pdf
//| Magic   : 3206                                                   |
//|                                                                  |
//| Daily-bias liquidity raid, then trade the reaction:              |
//|   1. Decide the daily bias on the daily chart (recent highs/lows,|
//|      inefficiencies, where price wants to go).                   |
//|   2. Mark the session liquidity zones: previous day high/low,    |
//|      Asian session high/low, London session high/low.            |
//|   3. During the New York session a key session level must be     |
//|      taken out - the stops have been hit.                        |
//|   4. The raid must FAIL to continue (price closes back inside),  |
//|      which is the turtle-soup signal.                            |
//|   5. Confirmation on the LTF (M15/M5): FVG, MSS or breaker.      |
//|      Entry at the FVG retest, stop above the sweep high, target  |
//|      the opposite session liquidity.                             |
//|   6. Setups form between 09:30 and 11:30 New York.               |
//|                                                                  |
//| Engine mapping: `SigFvgRetest` (the example's 1H FVG entry),     |
//| `SigSweepReclaim` (MSS / breaker confirmation), `SigAsianRange`  |
//| and `SigRangeForDay` (the marked session liquidity). The levels  |
//| themselves (PDH/PDL, Asian, London) need `LiquidityRaid()`: the  |
//| engine's `SigSessionFade` (EASignals 14) fades a quiet range only|
//| in the 3 hours AFTER that range closes, which is the 02:00-05:00 |
//| ET window - while this model trades the 09:30-11:30 ET one.      |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics Intraday Liquidity & Volatility - fade a failed session-liquidity raid in the NY window"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade   = "US100,US500,GER40,XAUUSD";  // Universe (playbook: futures / forex)
input ulong             InpMagicNumber      = 3206;                 // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct          = 0.50;                 // Risk per trade (% of equity)
input int               InpStage             = 5;                    // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input double            InpMaxSpreadPoints  = 3.0;                  // Spread gate in points (0 = off)
input double            InpDailyLossPct     = 1.50;                 // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset  = 2;                    // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;        // Log verbosity
input double            InpCommissionPerLotRT = 0.0;                // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.12;               // Reject setups whose all-in cost exceeds xR
input bool              InpLedger             = true;               // Write the engine evidence ledger CSV
//--- daily bias and the raid (London clock; New York = London - 5)
input bool   InpBiasGate       = true;   // Require the daily bias to agree with the fade
input double InpBiasBandAtr    = 0.15;   // |price - D1 200EMA| must exceed this to call a bias
input int    InpSessionFromMin = 870;    // 14:30 London = 09:30 ET
input int    InpSessionToMin   = 990;    // 16:30 London = 11:30 ET
input int    InpRaidLookbackBars = 12;   // How far back the raid may have printed
input double InpRaidMaxAtr     = 0.60;   // Deeper raids than this are trends, not stop runs
input bool   InpUseLondonRange = true;   // Include the London session high/low as a liquidity zone
//--- entry
input double InpImpulseBody    = 0.55;   // Displacement body for the FVG
input double InpMinGapAtr      = 0.08;   // Minimum imbalance size
input double InpStopBufferAtr  = 0.15;   // Beyond the sweep extreme
input double InpMinRR          = 1.50;   // Reject when the opposite session liquidity is closer
input double InpTargetR        = 2.00;   // Fallback target when no session level is far enough
input int    InpReclaimWindowBars = 3;   // MSS fallback: bars from the sweep to the reclaim

//+------------------------------------------------------------------+
//| Strategy class                                                   |
//+------------------------------------------------------------------+
class CCfIntradayLiquidity : public CEAStrategy
{
public:
   void OnInitStrategy()
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("5-stage policy: stage %d active (risk %.3f%%, %d trades/day max)",
             InpStage, g_eaCfg.riskPct, g_eaCfg.maxTradesPerDay), true);
   }

   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_INTRADAY_LIQUIDITY";
      cfg.sourceDoc             = "chartfanatics/pdf/intraday-liquidity-volatility-model.pdf (card #12)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = 3.0;
      cfg.totalDdPct            = 8.0;
      cfg.maxTradesPerDay       = 3;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 180;
      cfg.useHwmThrottle        = true;
      cfg.hwmTier1Dd            = 2.0;  cfg.hwmTier1Mult = 0.50;
      cfg.hwmTier2Dd            = 4.0;  cfg.hwmTier2Mult = 0.25;
      cfg.hwmHaltDd             = 6.0;
      cfg.sessionStartHour      = 14;  cfg.sessionStartMin = 30;
      cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 30;
      cfg.noTradeAfterHour      = 17;  cfg.noTradeAfterMin = 0;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 19;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = false;
      cfg.pendingExpiryMinutes  = 15;
      cfg.breakEvenAtR          = 1.0;
      cfg.partial1AtR           = 1.0;  cfg.partial1Pct = 50.0;
      cfg.trailAtR              = 1.5;  cfg.trailDistanceR = 0.75;
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;             // engine cost gate: (spread + commission) <= xR
      cfg.ledgerEnabled         = InpLedger;               // engine ledger: one row per open / partial / close
      cfg.ledgerFile            = "cf_intraday_liquidity_ledger.csv";
      cfg.newsFilter            = false;
      cfg.logLevel              = InpLogLevel;

      //--- chartfanatics card #01 (5-Stage framework): tighten the playbook's own risk posture for
      //--- the stage the account is being held to.  Never raises a cap; stage 5 leaves it untouched.
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession) return false;
      if(ctx.atr <= 0.0) return false;

      int bias = DailyBias(ctx);
      if(InpBiasGate && bias == 0) return false;

      //--- which session liquidity was raided and rejected?
      int    raidDir   = 0;
      double raidLevel = 0.0;
      if(!LiquidityRaid(ctx, raidDir, raidLevel)) return false;

      int fadeDir = -raidDir;                       // fade the failed breakout
      if(InpBiasGate && bias != fadeDir) return false;

      //--- confirmation 1: the imbalance left by the reversal (the example's 1H FVG entry)
      SSignalPlan found;
      SFvgParams f;
      f.Reset();
      f.impulseBody   = InpImpulseBody;
      f.minGapAtr     = InpMinGapAtr;
      f.stopBufferAtr = InpStopBufferAtr;
      f.targetR       = InpTargetR;
      f.tradeBothWays = true;
      f.onlyDir       = fadeDir;
      bool havePlan = SigFvgRetest(ctx, f, found);

      //--- confirmation 2: the MSS / breaker (sweep, reclaim, displacement)
      if(!havePlan)
      {
         SSweepParams s;
         s.Reset();
         s.rangeFromMin        = 0;
         s.rangeToMin          = InpSessionFromMin;
         s.sessionFromMin      = InpSessionFromMin;
         s.sessionToMin        = InpSessionToMin;
         s.sweepMinAtr         = 0.05;
         s.sweepMaxAtr         = 1.50;
         s.reclaimWindowBars   = InpReclaimWindowBars;
         s.wickRatio           = 0.50;
         s.bodyRatio           = 0.55;
         s.stopBufferAtr       = InpStopBufferAtr;
         s.minStopAtr          = 0.25;
         s.maxStopAtr          = 2.50;
         s.targetR             = InpTargetR;
         s.entryRetrace        = 0.0;
         s.requireDisplacement = true;
         s.tradeBothWays       = true;
         s.scoreBase           = 58.0;
         havePlan = SigSweepReclaim(ctx, s, found);
      }
      if(!havePlan) return false;
      if(found.dir != fadeDir) return false;

      //--- the stop belongs beyond the sweep extreme, not just beyond the signal bar
      double buffer = InpStopBufferAtr * ctx.atr;
      if(found.dir < 0) found.stop = MathMax(found.stop, raidLevel + buffer);
      else              found.stop = MathMin(found.stop, raidLevel - buffer);
      found.riskDist = MathAbs(found.entry - found.stop);
      if(found.riskDist <= 0.0) return false;
      if(found.dir < 0 && found.stop <= found.entry) return false;
      if(found.dir > 0 && found.stop >= found.entry) return false;

      //--- target: the opposite session liquidity (Asian low for shorts, Asian high for longs)
      double aHi = 0.0, aLo = 0.0;
      if(SigAsianRange(ctx.symbol, aHi, aLo))
      {
         double external = (found.dir < 0) ? aLo : aHi;
         double rr = MathAbs(external - found.entry) / found.riskDist;
         if(rr >= InpMinRR) found.target = external;
      }
      double finalRr = MathAbs(found.target - found.entry) / found.riskDist;
      if(finalRr < InpMinRR) return false;

      found.score  = found.score + MathMin(20.0, finalRr * 5.0);
      found.reason = StringFormat("liquidity raid fade (level %.5f, %.2fR): ", raidLevel, finalRr) + found.reason;
      plan = found;
      return true;
   }

private:
   int DailyBias(SEAContext &ctx)
   {
      if(ctx.emaD1_200 <= 0.0 || ctx.atrD1 <= 0.0) return 0;
      double distance = ctx.mid - ctx.emaD1_200;
      if(MathAbs(distance) < InpBiasBandAtr * ctx.atrD1) return 0;
      return (distance > 0.0) ? +1 : -1;
   }

   //--- did a marked level get taken out and then given back (a failed raid)?
   bool LiquidityRaid(SEAContext &ctx, int &raidDir, double &raidLevel)
   {
      double levels[6];
      int    dirs[6];
      int    n = 0;

      double pdh = 0.0, pdl = 0.0;
      int bars = 0;
      if(SigRangeForDay(ctx.symbol, g_eaIndTf, 0, 1440, 1, pdh, pdl, bars))
      {
         levels[n] = pdh; dirs[n] = +1; n++;
         levels[n] = pdl; dirs[n] = -1; n++;
      }
      double aHi = 0.0, aLo = 0.0;
      if(SigAsianRange(ctx.symbol, aHi, aLo))
      {
         levels[n] = aHi; dirs[n] = +1; n++;
         levels[n] = aLo; dirs[n] = -1; n++;
      }
      double lHi = 0.0, lLo = 0.0;
      if(InpUseLondonRange && SigPrevSessionRange(ctx.symbol, g_eaIndTf, 7 * 60, 12 * 60, lHi, lLo))
      {
         levels[n] = lHi; dirs[n] = +1; n++;
         levels[n] = lLo; dirs[n] = -1; n++;
      }
      if(n == 0) return false;

      MqlRates r[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, InpRaidLookbackBars + 2, r);
      if(got < 4) return false;

      double tol = InpRaidMaxAtr * ctx.atr;
      for(int li = 0; li < n; li++)
      {
         double level = levels[li];
         int    side  = dirs[li];
         if(level <= 0.0) continue;
         for(int i = 1; i <= InpRaidLookbackBars && i < got; i++)
         {
            double beyond = (side > 0) ? (r[i].high - level) : (level - r[i].low);
            if(beyond <= 0.0 || beyond > tol) continue;             // no raid, or too deep to fade
            double backInside = (side > 0) ? (level - r[i].close) : (r[i].close - level);
            if(backInside <= 0.0) continue;                          // closed beyond: continuation
            raidDir   = side;
            raidLevel = (side > 0) ? r[i].high : r[i].low;
            return true;
         }
      }
      return false;
   }
};

CCfIntradayLiquidity g_cfIntradayLiquidity;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfIntradayLiquidity);
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
