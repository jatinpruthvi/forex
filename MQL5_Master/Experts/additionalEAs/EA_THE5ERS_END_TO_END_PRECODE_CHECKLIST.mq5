//+------------------------------------------------------------------+
//| EA_THE5ERS_END_TO_END_PRECODE_CHECKLIST.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| The5ers pre-code checklist - staged compliance gates + paired profiles
//| Source document : docs/prop_firm/THE5ERS-END-TO-END-PRECODE-CHECKLIST.md
//| Tracker entry   : #20  |  Magic: 3106
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the CPrecodeChecklist class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "The5ers pre-code checklist - staged compliance gates + paired profiles"
#property description "Source: docs/prop_firm/THE5ERS-END-TO-END-PRECODE-CHECKLIST.md"

#include "..\Include\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string          InpSymbolsToTrade   = "EURUSD,GBPUSD,USDJPY";      // Comma separated universe
input double          InpRiskPct          = 0.4;   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = 3.0;   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = 1.0;   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = 10;   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = 10;   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = 2;      // 0 = unlimited
input int             InpServerGmtOffset  = 2;      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = 3106; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity
enum ENUM_PHASE25K
{
   PHASE25K_EVALUATION_1 = 0,  // Phase 1 (10% target)
   PHASE25K_EVALUATION_2 = 1,  // Phase 2 (5% target)
   PHASE25K_FUNDED       = 2   // Funded (capital preservation)
};
enum ENUM_RR_PROFILE
{
   RR_A_040_15 = 0,  // A: 0.40% risk / +1.50R
   RR_B_035_175= 1,  // B: 0.35% risk / +1.75R
   RR_C_030_20 = 2,  // C: 0.30% risk / +2.00R
   RR_D_025_25 = 3   // D: 0.25% risk / +2.50R
};
input ENUM_PHASE25K   InpPhase               = PHASE25K_EVALUATION_1; // Current product phase
input ENUM_RR_PROFILE InpProfile             = RR_A_040_15;           // Frozen risk/target pair
input double          InpPhaseInitialBalance = 2500.0;  // Persisted phase initial balance
input long            InpAuthorizedLogin     = 0;       // Account login (0 = skip the identity gate)
input string          InpAuthorizedProduct   = "$2,500 New High Stakes"; // Stage 0 product check
input bool            InpEnableTrading        = false;  // Stage 0/15 gate: refuse until verified
input int             InpTimeStopMinutes      = 45;     // Time exit candidate (30/45/60/90)
input bool            InpMoveBeAfter1R        = false;  // Breakeven challenger: M5 close beyond +1R

//+------------------------------------------------------------------+
//| Strategy: The5ers pre-code checklist - staged compliance gates + paired profiles
//+------------------------------------------------------------------+
class CPrecodeChecklist : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      //--- paired profile A-D (Stage 1 candidates)
      double riskPct = 0.40, targetR = 1.50;
      if(InpProfile == RR_B_035_175) { riskPct = 0.35; targetR = 1.75; }
      if(InpProfile == RR_C_030_20)  { riskPct = 0.30; targetR = 2.00; }
      if(InpProfile == RR_D_025_25)  { riskPct = 0.25; targetR = 2.50; }
      if(InpPhase == PHASE25K_FUNDED) riskPct *= 0.5;          // funded preservation

      cfg.strategyName          = "PRECODE_CHECKLIST";
      cfg.sourceDoc             = "docs/prop_firm/THE5ERS-END-TO-END-PRECODE-CHECKLIST.md";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = riskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;             // internal daily stop
      cfg.weeklyLossPct         = 2.0;                         // internal weekly stop
      cfg.totalDdPct            = InpTotalDdPct;               // static 10% floor
      cfg.profitTargetPct       = (InpPhase == PHASE25K_EVALUATION_2) ? 5.0 : InpProfitTargetPct;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;                           // one working order/position
      cfg.minSecondsBetweenTrades = 60;
      cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
      cfg.sessionEndFlat        = true;                        // flat before rollover
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.pendingExpiryMinutes  = 15;                          // three M5 candles
      cfg.timeStopMinutes       = InpTimeStopMinutes;
      cfg.partial1AtR           = 0.0;                         // partial closing removed
      cfg.breakEvenAtR          = (InpMoveBeAfter1R ? 1.0 : 0.0);
      cfg.useHwmThrottle        = true;                        // single documented half-risk tier
      cfg.hwmTier1Dd            = 2.0;  cfg.hwmTier1Mult = 0.50;
      cfg.hwmTier2Dd            = 5.0;  cfg.hwmTier2Mult = 0.0;  cfg.hwmHaltDd = 5.0;
      cfg.newsFilter            = false;
      cfg.logLevel              = InpLogLevel;
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- Stage 0/15 gate: never trade an unverified product/account
      if(!InpEnableTrading) return false;
      if(InpAuthorizedLogin > 0 && AccountInfoInteger(ACCOUNT_LOGIN) != InpAuthorizedLogin) return false;

      double targetR = 1.50;
      if(InpProfile == RR_B_035_175) targetR = 1.75;
      if(InpProfile == RR_C_030_20)  targetR = 2.00;
      if(InpProfile == RR_D_025_25)  targetR = 2.50;

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
      p.targetR        = targetR;

      if(ctx.symbol == "USDJPY")
      {
         p.rangeFromMin   = 7 * 60;
         p.rangeToMin     = 13 * 60;
         p.sessionFromMin = 13 * 60 + 30;
         p.sessionToMin   = 16 * 60;
      }
      if(ctx.clockMinutes < p.sessionFromMin || ctx.clockMinutes >= p.sessionToMin) return false;

      if(!SigSweepReclaim(ctx, p, plan)) return false;
      plan.reason = StringFormat("PRECODE-%s %s", EnumToString(InpProfile), plan.reason);
      return true;
   }

   //--- Stage 8/9/11: day lock, profitable-day accounting, phase transition
   void Manage(SEAContext &ctx)
   {
      static datetime lockedDay = 0;
      MqlDateTime dt;
      TimeToStruct(ctx.nowClock, dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      datetime day = StructToTime(dt);

      if(lockedDay == day)
      {
         if(ctx.openPositions == 0) EA_FlattenAll("day locked (pre-code state machine)");
         return;
      }
      //--- profitable-day engine: a first net-positive exit locks the day
      if(ctx.tradesToday == 1 && ctx.openPositions == 0 && ctx.dayRealizedPl > 0.0)
         lockedDay = day;
      //--- second completed trade always locks the day
      if(ctx.tradesToday >= 2 && ctx.openPositions == 0)
         lockedDay = day;

      //--- Stage 11: phase target reached (log the transition; a human flips InpPhase)
      double base = (InpPhaseInitialBalance > 0.0) ? InpPhaseInitialBalance : 2500.0;
      double target = (InpPhase == PHASE25K_EVALUATION_2) ? base * 1.05 : base * 1.10;
      if(AccountInfoDouble(ACCOUNT_EQUITY) >= target)
      {
         double qdays = 0;
         string key = "EA_" + IntegerToString((long)InpMagicNumber) + "_QualDays";
         if(GlobalVariableCheck(key)) qdays = GlobalVariableGet(key);
         EA_Log(EA_LOG_EVENTS, StringFormat("PHASE TARGET REACHED: equity %.2f >= %.2f (%d qualifying days) - verify on the dashboard before switching phase",
                AccountInfoDouble(ACCOUNT_EQUITY), target, (int)qdays), true);
      }
   }
};

CPrecodeChecklist g_PrecodeChecklist;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_PrecodeChecklist);
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
