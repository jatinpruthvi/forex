#property strict
#property version   "2.15"
#property description "TRIAD-R High Stakes: one-position M5 sweep/reclaim research EA"
#property description "Order submission is disabled by default. Validate before challenge use."
#property tester_file "triad_red_news.csv"

#include <Trade/Trade.mqh>

// ============================================================================
// TRIAD-R High Stakes revision 2.1
// Canonical specification: THE5ERS-CHALLENGE-STRATEGY-V2.md
// This EA is intentionally fail-closed. It is a research implementation and
// must not be enabled on a challenge until the documented validation gates pass.
// ============================================================================

enum ENUM_TRIAD_PHASE
  {
   TRIAD_PHASE_1 = 1,
   TRIAD_PHASE_2 = 2,
   TRIAD_FUNDED  = 3
  };

enum ENUM_TRIAD_PROFILE
  {
   PROFILE_A_040_R150 = 0,
   PROFILE_B_035_R175 = 1,
   PROFILE_C_030_R200 = 2,
   PROFILE_D_025_R250 = 3
  };

enum ENUM_SESSION_KIND
  {
   SESSION_LONDON = 0,
   SESSION_NEW_YORK = 1
  };

enum ENUM_PATTERN_SIDE
  {
   PATTERN_NONE = 0,
   PATTERN_LONG = 1,
   PATTERN_SHORT = -1
  };

enum ENUM_TRIAD_LIFECYCLE_LOCK
  {
   LIFECYCLE_ACTIVE = 0,
   LIFECYCLE_PAYOUT_REQUEST = 1,
   LIFECYCLE_PHASE_TRANSITION = 2,
   LIFECYCLE_SCALE_TRANSITION = 3
  };

// ---- Safety and account identity -------------------------------------------
input bool               InpEnableOrderSubmission       = false;
input string             InpValidationReleaseId         = "LOCKED";
input bool               InpStatisticalGatePassed       = false;
input bool               InpStressGatePassed            = false;
input bool               InpOperationalGatePassed       = false;
input bool               InpExternalRulesGatePassed     = false;
input bool               InpAccountSpecificGatePassed   = false;
input bool               InpForwardDemoGatePassed       = false;
input bool               InpCompilationGatePassed       = false;
input bool               InpExplicitUserApproval        = false;
input string             InpRequiredProductCode         = "HS_NEW_2500";
input long               InpAuthorizedLogin             = 0;
input string             InpExpectedAccountServer       = "";
input string             InpExpectedAccountCurrency     = "USD";
input int                InpExpectedAccountLeverage     = 100;
input ENUM_TRIAD_PHASE   InpPhase                       = TRIAD_PHASE_1;
input ENUM_TRIAD_LIFECYCLE_LOCK InpLifecycleLock        = LIFECYCLE_ACTIVE;
input double             InpPhaseInitialBalance         = 2500.0;
input int                InpDashboardConfirmedDays      = 0;
input bool               InpUseEstimatedDaysInTester    = true;
input bool               InpAuthorizeFreshPhaseState    = false;
input bool               InpAuthorizeHaltReset          = false;
input bool               InpResetTesterStateOnInit      = true;
input long               InpMagic                       = 26090321;

// ---- Fixed server/calendar controls ----------------------------------------
input int                InpExpectedServerUtcOffsetHours= 3;
input int                InpNewsBlockMinutes            = 30;
input int                InpNewsFlatMinutes             = 15;
input int                InpRolloverFlatMinutes         = 15;
input string             InpNewsCsvFile                 = "triad_red_news.csv";
input bool               InpRequireNewsCalendar         = true;
input int                InpRequiredNewsCoverageHours   = 24;
input int                InpMaxQuoteAgeSeconds          = 10;
input int                InpMaxDeviationPoints          = 20;
input int                InpMaxTradeRequestLatencyMs    = 1000;
input int                InpMaxNonEmergencyRequestsDay  = 20;
input bool               InpSkipFreshMidSessionStart    = true;

// ---- Instruments -----------------------------------------------------------
input string             InpEURUSDSymbol                = "EURUSD";
input string             InpGBPUSDSymbol                = "GBPUSD";
input string             InpUSDJPYSymbol                = "USDJPY";
input bool               InpEnableEURUSDLondon          = true;
input bool               InpEnableGBPUSDLondon          = true;
input bool               InpEnableUSDJPYNewYork         = true;
input int                InpEURUSDLondonPriority        = 1;
input int                InpGBPUSDLondonPriority        = 1;
input int                InpUSDJPYNewYorkPriority       = 1;
input bool               InpEURUSDLondonGatePassed      = false;
input bool               InpGBPUSDLondonGatePassed      = false;
input bool               InpUSDJPYNewYorkGatePassed     = false;

// ---- Coarse research candidates --------------------------------------------
input ENUM_TRIAD_PROFILE InpProfile                     = PROFILE_A_040_R150;
input double             InpRangePercentileLow          = 30.0;
input double             InpRangePercentileHigh         = 80.0;
input double             InpAtrPercentileLow            = 20.0;
input double             InpAtrPercentileHigh           = 80.0;
input int                InpComparableSessions          = 60;
input int                InpTimeStopMinutes             = 45; // 0 = session only
input bool               InpMoveStopToEntryAfter1R      = false;

// ---- Fixed entry/risk definitions ------------------------------------------
input double             InpSweepAtrMin                 = 0.05;
input double             InpSweepAtrMax                 = 0.50;
input int                InpReclaimBars                 = 3;
input double             InpReclaimWickMin              = 0.60;
input double             InpDisplacementBodyMin         = 0.60;
input int                InpLimitExpiryBars             = 3;
input double             InpStopBufferAtr               = 0.10;
input double             InpStopAtrMin                  = 0.60;
input double             InpStopAtrMax                  = 1.50;
input double             InpMaxCostToR                  = 0.10;
input double             InpSpreadMedianMultiplier      = 1.50;
input double             InpCommissionRoundTripPerLot   = 4.0;
input int                InpStopSlippageReservePoints   = 10;
input int                InpTargetSlippageReservePoints = 5;
input double             InpFirmFloorReservePercent     = 0.50;
input double             InpInternalDailyStopPercent    = 1.00;
input double             InpInternalWeeklyStopPercent   = 2.00;
input double             InpDrawdownReducePercent       = 2.00;
input double             InpDrawdownShutdownPercent     = 5.00;

// ---- Logging ---------------------------------------------------------------
input bool               InpVerboseLog                  = true;
input string             InpLogFilePrefix               = "TRIAD_R_HS";

struct NewsEvent
  {
   datetime utc_time;
   string   currency;
   string   title;
  };

struct SessionRuntime
  {
   string            id;
   string            symbol;
   string            ccy1;
   string            ccy2;
   ENUM_SESSION_KIND kind;
   bool              enabled;
   int               priority;
   int               local_day_key;
   datetime          range_start;
   datetime          range_end;
   datetime          entry_start;
   datetime          entry_end;
   double            range_high;
   double            range_low;
   bool              range_ready;
   bool              range_warning_logged;
   bool              consumed;
   datetime          last_closed_bar;
  };

struct SignalCandidate
  {
   bool              detected;
   bool              valid;
   int               session_index;
   ENUM_PATTERN_SIDE side;
   string            symbol;
   datetime          signal_bar_time;
   datetime          expiry_time;
   double            atr;
   double            range_high;
   double            range_low;
   double            sweep_extreme;
   double            entry;
   double            stop;
   double            target;
   double            one_r_price;
   double            volume;
   double            cash_risk;
   double            slippage_reserve_cash;
   double            target_net;
   double            cost_to_r;
   double            range_percentile;
   double            atr_percentile;
   double            spread_points;
   double            spread_median_points;
   string            rejection;
  };

const string   EA_BUILD_ID = "TRIAD_R_HS_2.1.5_20260904";
const int      SAFETY_TIME_LEAD_SECONDS = 10;
const int      SERVER_OFFSET_TOLERANCE_SECONDS = 5;

CTrade         g_trade;
NewsEvent      g_news[];
SessionRuntime g_sessions[3];
int            g_atr_handles[3]={INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE};

string   g_prefix                    = "";
string   g_account_lock_prefix       = "";
string   g_log_file                  = "";
bool     g_initialized               = false;
bool     g_halted                    = false;
string   g_halt_reason               = "";
bool     g_news_valid                = false;
datetime g_news_coverage_end_utc     = 0;
bool     g_news_stale_logged         = false;
bool     g_log_failure               = false;
int      g_config_hash               = 0;
int      g_runtime_identity_hash     = 0;
int      g_server_day_key            = 0;
int      g_week_key                  = 0;
datetime g_day_start_time            = 0;
double   g_day_start_balance         = 0.0;
double   g_day_start_equity          = 0.0;
double   g_week_start_balance        = 0.0;
double   g_previous_day_balance      = 0.0;
double   g_firm_daily_floor          = 0.0;
double   g_high_water_balance        = 0.0;
int      g_estimated_profitable_days = 0;
int      g_request_count             = 0;
int      g_rollover_incident_key     = 0;
long     g_history_baseline_msc      = 0;
datetime g_last_cashflow_check       = 0;
bool     g_external_cashflow_detected= false;
bool     g_account_history_fault     = false;
bool     g_rebaseline_required       = false;
datetime g_state_created_time        = 0;
int      g_last_inactivity_alert_day = 0;
datetime g_last_inactivity_check     = 0;
int      g_direction_alert_day_key   = 0;
datetime g_last_direction_check      = 0;
bool     g_instance_lock_held        = false;
ulong    g_safety_request_tickets[4] = {0,0,0,0};
datetime g_safety_request_times[4]   = {0,0,0,0};

// ============================================================================
// Utility and logging
// ============================================================================

bool IsTesterMode()
  {
   return (bool)MQLInfoInteger(MQL_TESTER);
  }

bool AuthorizedAccountContext()
  {
   if(IsTesterMode())
      return true;
   return InpEnableOrderSubmission && InpAuthorizedLogin>0 &&
          AccountInfoInteger(ACCOUNT_LOGIN)==InpAuthorizedLogin &&
          InpExpectedAccountServer!="" &&
          AccountInfoString(ACCOUNT_SERVER)==InpExpectedAccountServer;
  }

bool OwnsLiveInstanceLock()
  {
   if(IsTesterMode())
      return true;
   if(!InpEnableOrderSubmission || !g_instance_lock_held)
      return false;
   string owner_name=g_account_lock_prefix+"Owner";
   return GlobalVariableCheck(owner_name) &&
          GlobalVariableGet(owner_name)==(double)ChartID();
  }

string BoolText(const bool value)
  {
   return value ? "true" : "false";
  }

void LogEvent(const string level,const string event_name,const string detail)
  {
   string message=StringFormat("[%s] %s | %s",level,event_name,detail);
   if(InpVerboseLog || level=="ERROR" || level=="HALT")
      Print(message);

   int handle=FileOpen(g_log_file,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
   if(handle==INVALID_HANDLE)
     {
      if(!g_log_failure) Print("[ERROR] AUDIT_LOG_OPEN_FAILED | ",g_log_file," error=",GetLastError());
      g_log_failure=true;
      return;
     }
   bool write_ok=true;
   if(FileSize(handle)==0 &&
      FileWrite(handle,"server_time","level","event","detail","balance","equity","requests")==0)
      write_ok=false;
   if(!FileSeek(handle,0,SEEK_END)) write_ok=false;
   if(FileWrite(handle,TimeToString(TimeTradeServer(),TIME_DATE|TIME_SECONDS),level,event_name,detail,
                DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2),
                DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2),g_request_count)==0)
      write_ok=false;
   FileClose(handle);
   if(!write_ok)
     {
      if(!g_log_failure) Print("[ERROR] AUDIT_LOG_WRITE_FAILED | ",g_log_file," error=",GetLastError());
      g_log_failure=true;
     }
  }

void Halt(const string reason)
  {
   if(!g_halted || g_halt_reason!=reason)
      LogEvent("HALT","STRATEGY_HALTED",reason);
   g_halted=true;
   g_halt_reason=reason;
   if(g_prefix!="" && GlobalVariableCheck(GVName("Cfg")))
     {
      // Halt is a separate fail-closed journal. Its signature binds both the
      // latch and reason to this exact configuration/account identity, so a
      // changed terminal global cannot silently bypass the reset handshake.
      bool halt_saved=WriteHaltLatch(1.0,(double)HashText(reason));
      if(!halt_saved)
        {
         // Removing the configuration sentinel makes the next live start fail
         // the fresh-state/history handshake rather than forgetting a halt.
         GlobalVariableDel(GVName("Cfg"));
         LogEvent("ERROR","HALT_PERSIST_FAILED","configuration sentinel removed fail-closed");
        }
      GlobalVariablesFlush();
     }
  }

int HashText(const string value,int seed=216613626)
  {
   uint hash=(uint)seed;
   int length=StringLen(value);
   for(int i=0;i<length;i++)
     {
      hash^=(uint)StringGetCharacter(value,i);
      hash*=16777619;
     }
   return (int)(hash & 0x7fffffff);
  }

int BuildConfigHash()
  {
   string text=EA_BUILD_ID+"|"+BoolText(InpEnableOrderSubmission)+"|"+
      InpValidationReleaseId+"|"+InpRequiredProductCode+"|"+
      IntegerToString((int)InpPhase)+"|"+DoubleToString(InpPhaseInitialBalance,2)+"|"+
      IntegerToString(InpExpectedAccountLeverage)+"|"+
      IntegerToString((int)InpProfile)+"|"+BoolText(InpUseEstimatedDaysInTester)+"|"+
      InpEURUSDSymbol+"|"+InpGBPUSDSymbol+"|"+InpUSDJPYSymbol+"|"+
      BoolText(InpEnableEURUSDLondon)+"|"+BoolText(InpEnableGBPUSDLondon)+"|"+
      BoolText(InpEnableUSDJPYNewYork)+"|"+
      IntegerToString(InpEURUSDLondonPriority)+"|"+
      IntegerToString(InpGBPUSDLondonPriority)+"|"+
      IntegerToString(InpUSDJPYNewYorkPriority)+"|"+
      DoubleToString(InpRangePercentileLow,4)+"|"+DoubleToString(InpRangePercentileHigh,4)+"|"+
      DoubleToString(InpAtrPercentileLow,4)+"|"+DoubleToString(InpAtrPercentileHigh,4)+"|"+
      IntegerToString(InpComparableSessions)+"|"+IntegerToString(InpTimeStopMinutes)+"|"+
      BoolText(InpMoveStopToEntryAfter1R)+"|"+
      DoubleToString(InpSweepAtrMin,4)+"|"+DoubleToString(InpSweepAtrMax,4)+"|"+
      IntegerToString(InpReclaimBars)+"|"+DoubleToString(InpReclaimWickMin,4)+"|"+
      DoubleToString(InpDisplacementBodyMin,4)+"|"+IntegerToString(InpLimitExpiryBars)+"|"+
      DoubleToString(InpStopBufferAtr,4)+"|"+DoubleToString(InpStopAtrMin,4)+"|"+
      DoubleToString(InpStopAtrMax,4)+"|"+DoubleToString(InpMaxCostToR,4)+"|"+
      DoubleToString(InpSpreadMedianMultiplier,4)+"|"+
      DoubleToString(InpCommissionRoundTripPerLot,4)+"|"+
      IntegerToString(InpStopSlippageReservePoints)+"|"+
      IntegerToString(InpTargetSlippageReservePoints)+"|"+
      DoubleToString(InpInternalDailyStopPercent,4)+"|"+
      DoubleToString(InpInternalWeeklyStopPercent,4)+"|"+
      DoubleToString(InpDrawdownReducePercent,4)+"|"+
      DoubleToString(InpDrawdownShutdownPercent,4)+"|"+
      DoubleToString(InpFirmFloorReservePercent,4)+"|"+
      IntegerToString(InpExpectedServerUtcOffsetHours)+"|"+
      InpNewsCsvFile+"|"+BoolText(InpRequireNewsCalendar)+"|"+
      IntegerToString(InpNewsBlockMinutes)+"|"+IntegerToString(InpNewsFlatMinutes)+"|"+
      IntegerToString(InpRolloverFlatMinutes)+"|"+IntegerToString(InpRequiredNewsCoverageHours)+"|"+
      IntegerToString(InpMaxQuoteAgeSeconds)+"|"+IntegerToString(InpMaxDeviationPoints)+"|"+
      IntegerToString(InpMaxTradeRequestLatencyMs)+"|"+
      IntegerToString(InpMaxNonEmergencyRequestsDay)+"|"+StringFormat("%I64d",InpMagic);
   return HashText(text);
  }

int RuntimeIdentityHash()
  {
   string text=StringFormat("%I64d",AccountInfoInteger(ACCOUNT_LOGIN))+"|"+
               AccountInfoString(ACCOUNT_SERVER)+"|"+AccountInfoString(ACCOUNT_CURRENCY)+"|"+
               InpRequiredProductCode+"|"+IntegerToString((int)InpPhase);
   return HashText(text);
  }

int AccountStateSignature()
  {
   string text=IntegerToString(g_config_hash)+"|"+IntegerToString(g_runtime_identity_hash)+"|"+
      DoubleToString(InpPhaseInitialBalance,8)+"|"+IntegerToString(g_server_day_key)+"|"+
      StringFormat("%I64d",(long)g_day_start_time)+"|"+DoubleToString(g_day_start_balance,8)+"|"+
      DoubleToString(g_day_start_equity,8)+"|"+IntegerToString(g_week_key)+"|"+
      DoubleToString(g_week_start_balance,8)+"|"+DoubleToString(g_previous_day_balance,8)+"|"+
      DoubleToString(g_firm_daily_floor,8)+"|"+DoubleToString(g_high_water_balance,8)+"|"+
      IntegerToString(g_estimated_profitable_days)+"|"+IntegerToString(g_request_count)+"|"+
      IntegerToString(g_rollover_incident_key)+"|"+StringFormat("%I64d",g_history_baseline_msc)+"|"+
      IntegerToString(g_rebaseline_required ? 1 : 0)+"|"+
      StringFormat("%I64d",(long)g_state_created_time)+"|"+
      IntegerToString(g_last_inactivity_alert_day);
   return HashText(text);
  }

string GVName(const string suffix)
  {
   return g_prefix+suffix;
  }

bool GVRead(const string suffix,double &value)
  {
   string name=GVName(suffix);
   if(!GlobalVariableCheck(name))
      return false;
   value=GlobalVariableGet(name);
   return true;
  }

bool GVWrite(const string suffix,const double value)
  {
   return GlobalVariableSet(GVName(suffix),value)!=0;
  }

int HaltLatchSignature(const double halt_value,const double halt_reason_hash)
  {
   // Use a domain tag so this checksum cannot be confused with the broader
   // accounting-state signature even if all numeric components happen to tie.
   string text="HALT_LATCH_V1|"+IntegerToString(g_config_hash)+"|"+
      IntegerToString(g_runtime_identity_hash)+"|"+
      IntegerToString(halt_value>0.5 ? 1 : 0)+"|"+
      IntegerToString((int)halt_reason_hash);
   return HashText(text);
  }

bool HaltLatchValuesValid(const double halt_value,const double halt_reason_hash)
  {
   if(halt_value!=0.0 && halt_value!=1.0)
      return false;
   if(halt_reason_hash<0.0 || halt_reason_hash>2147483647.0 ||
      halt_reason_hash!=(double)(int)halt_reason_hash)
      return false;
   // An unlocked journal must not retain an unexplained stale reason. A halted
   // journal may carry zero only in the vanishingly rare case that its 31-bit
   // reason hash itself is zero; the signed latch still remains unambiguous.
   return halt_value>0.5 || halt_reason_hash==0.0;
  }

bool WriteHaltLatch(const double halt_value,const double halt_reason_hash)
  {
   bool ok=HaltLatchValuesValid(halt_value,halt_reason_hash);
   if(!GVWrite("Halt",halt_value)) ok=false;
   if(!GVWrite("HaltReason",halt_reason_hash)) ok=false;
   // Commit marker is written after both protected values. A partial update
   // leaves an old/missing signature and therefore fails closed when read.
   if(!GVWrite("HaltSig",HaltLatchSignature(halt_value,halt_reason_hash))) ok=false;
   return ok;
  }

bool ReadHaltLatch(double &halt_value,double &halt_reason_hash)
  {
   double stored_signature=0.0;
   if(!GVRead("Halt",halt_value) || !GVRead("HaltReason",halt_reason_hash) ||
      !GVRead("HaltSig",stored_signature) ||
      !HaltLatchValuesValid(halt_value,halt_reason_hash))
      return false;
   return stored_signature==(double)HaltLatchSignature(halt_value,halt_reason_hash);
  }

bool AcquireLiveInstanceLock()
  {
   if(!InpEnableOrderSubmission || IsTesterMode())
      return true;
   string owner_name=g_account_lock_prefix+"Owner";
   string beat_name=g_account_lock_prefix+"Beat";
   if((!GlobalVariableCheck(owner_name) && GlobalVariableSet(owner_name,0.0)==0) ||
      (!GlobalVariableCheck(beat_name) && GlobalVariableSet(beat_name,0.0)==0))
     {
      LogEvent("ERROR","INSTANCE_LOCK_STORAGE_FAILED","cannot create owner/heartbeat variables");
      return false;
     }
   double owner=GlobalVariableGet(owner_name);
   datetime beat=(datetime)(long)GlobalVariableGet(beat_name);
   double this_owner=(double)ChartID();
   datetime now=TimeTradeServer();
   if(owner!=0.0 && owner!=this_owner && now-beat<=30)
     {
      LogEvent("ERROR","DUPLICATE_LIVE_INSTANCE",StringFormat("owner=%.0f",owner));
      return false;
     }
   // Publish a fresh beat before the owner CAS. This prevents a second starter
   // from observing a newly claimed owner with the old zero/stale heartbeat and
   // immediately stealing it during the claimant's initialization window.
   if(GlobalVariableSet(beat_name,(double)now)==0)
     {
      LogEvent("ERROR","INSTANCE_LOCK_STORAGE_FAILED","cannot persist candidate heartbeat");
      return false;
     }
   if(!GlobalVariableSetOnCondition(owner_name,this_owner,owner))
     {
      LogEvent("ERROR","INSTANCE_LOCK_RACE","another chart acquired the live lock");
      return false;
     }
   g_instance_lock_held=true;
   if(owner!=0.0 && owner!=this_owner)
      LogEvent("WARN","STALE_INSTANCE_LOCK_RECOVERED",StringFormat("old_owner=%.0f",owner));
   return true;
  }

void RefreshLiveInstanceLock()
  {
   if(!g_instance_lock_held) return;
   string owner_name=g_account_lock_prefix+"Owner";
   if(!GlobalVariableCheck(owner_name) || GlobalVariableGet(owner_name)!=(double)ChartID())
     {
      // Lease fencing: stop this stale instance locally without writing or
      // trading through the journal now owned by a newer claimant.
      g_instance_lock_held=false;
      g_halted=true;
      g_halt_reason="live_instance_lock_lost";
      LogEvent("HALT","STALE_INSTANCE_FENCED",g_halt_reason);
      return;
     }
   if(GlobalVariableSet(g_account_lock_prefix+"Beat",(double)TimeTradeServer())==0)
     {
      Halt("live_instance_heartbeat_failure");
      CancelAllPending("live_instance_heartbeat_failure",true);
      CloseAllPositions("live_instance_heartbeat_failure",true);
     }
  }

void ReleaseLiveInstanceLock()
  {
   if(!g_instance_lock_held) return;
   string owner_name=g_account_lock_prefix+"Owner";
   double this_owner=(double)ChartID();
   // Clear only the conditionally owned token. Do not zero the separate beat:
   // a new claimant can publish its beat and acquire owner=0 between those two
   // operations, and a late zero would make that fresh owner look stale.
   GlobalVariableSetOnCondition(owner_name,0.0,this_owner);
   g_instance_lock_held=false;
  }

bool PersistAccountState()
  {
   bool ok=true;
   if(!GVWrite("Cfg",g_config_hash)) ok=false;
   if(!GVWrite("Identity",g_runtime_identity_hash)) ok=false;
   double halt_value=(g_halted ? 1.0 : 0.0);
   double halt_reason_hash=(g_halted ? (double)HashText(g_halt_reason) : 0.0);
   if(!WriteHaltLatch(halt_value,halt_reason_hash)) ok=false;
   if(!GVWrite("Initial",InpPhaseInitialBalance)) ok=false;
   if(!GVWrite("DayKey",g_server_day_key)) ok=false;
   if(!GVWrite("DayStartT",(double)g_day_start_time)) ok=false;
   if(!GVWrite("DayBal",g_day_start_balance)) ok=false;
   if(!GVWrite("DayEq",g_day_start_equity)) ok=false;
   if(!GVWrite("WeekKey",g_week_key)) ok=false;
   if(!GVWrite("WeekBal",g_week_start_balance)) ok=false;
   if(!GVWrite("PrevBal",g_previous_day_balance)) ok=false;
   if(!GVWrite("DailyFloor",g_firm_daily_floor)) ok=false;
   if(!GVWrite("HighWater",g_high_water_balance)) ok=false;
   if(!GVWrite("ProfitDays",g_estimated_profitable_days)) ok=false;
   if(!GVWrite("ReqCount",g_request_count)) ok=false;
   if(!GVWrite("RollIncident",g_rollover_incident_key)) ok=false;
   if(!GVWrite("HistoryBaseMs",(double)g_history_baseline_msc)) ok=false;
   if(!GVWrite("Rebase",g_rebaseline_required ? 1.0 : 0.0)) ok=false;
   if(!GVWrite("CreatedT",(double)g_state_created_time)) ok=false;
   if(!GVWrite("InactAlert",g_last_inactivity_alert_day)) ok=false;
   // Commit marker is written last. A crash or partial terminal-global update
   // leaves the prior signature and is rejected on the next initialization.
   if(!GVWrite("StateSig",AccountStateSignature())) ok=false;
   GlobalVariablesFlush();
   if(!ok)
      LogEvent("ERROR","STATE_PERSIST_FAILED","terminal global-variable write failed; flush was requested");
   return ok;
  }

bool RequireStateMigration(const string incident)
  {
   g_rebaseline_required=true;
   bool saved=GVWrite("Rebase",1.0) && GVWrite("StateSig",AccountStateSignature());
   GlobalVariablesFlush();
   if(!saved)
     {
      // A missing migration latch must never be mistaken for resettable state.
      GlobalVariableDel(GVName("Cfg"));
      LogEvent("ERROR","REBASELINE_FLAG_PERSIST_FAILED",incident);
      return false;
     }
   LogEvent("WARN","STATE_MIGRATION_REQUIRED",incident);
   return true;
  }

// ============================================================================
// Civil time conversion. Datetime values produced here are UTC-like epoch
// seconds; server timestamps are UTC plus the configured/verified server offset.
// ============================================================================

datetime MakeDateTime(const int year,const int mon,const int day,const int hour,const int minute,const int second=0)
  {
   MqlDateTime value;
   ZeroMemory(value);
   value.year=year;
   value.mon=mon;
   value.day=day;
   value.hour=hour;
   value.min=minute;
   value.sec=second;
   return StructToTime(value);
  }

datetime LastSundayUtc(const int year,const int month,const int hour)
  {
   int next_year=year;
   int next_month=month+1;
   if(next_month==13)
     {
      next_month=1;
      next_year++;
     }
   datetime last_day=MakeDateTime(next_year,next_month,1,0,0)-86400;
   MqlDateTime parts;
   TimeToStruct(last_day,parts);
   int day=parts.day-parts.day_of_week;
   return MakeDateTime(year,month,day,hour,0);
  }

datetime NthSundayUtc(const int year,const int month,const int occurrence,const int hour)
  {
   datetime first=MakeDateTime(year,month,1,0,0);
   MqlDateTime parts;
   TimeToStruct(first,parts);
   int first_sunday=1+((7-parts.day_of_week)%7);
   int day=first_sunday+7*(occurrence-1);
   return MakeDateTime(year,month,day,hour,0);
  }

int LondonUtcOffsetSeconds(const datetime utc_time)
  {
   MqlDateTime p;
   TimeToStruct(utc_time,p);
   datetime start=LastSundayUtc(p.year,3,1);
   datetime finish=LastSundayUtc(p.year,10,1);
   return (utc_time>=start && utc_time<finish) ? 3600 : 0;
  }

int NewYorkUtcOffsetSeconds(const datetime utc_time)
  {
   MqlDateTime p;
   TimeToStruct(utc_time,p);
   datetime start=NthSundayUtc(p.year,3,2,7); // 02:00 EST
   datetime finish=NthSundayUtc(p.year,11,1,6); // 02:00 EDT
   return (utc_time>=start && utc_time<finish) ? -4*3600 : -5*3600;
  }

datetime LocalWallToUtc(const int year,const int mon,const int day,const int hour,const int minute,
                        const ENUM_SESSION_KIND zone)
  {
   datetime wall=MakeDateTime(year,mon,day,hour,minute);
   int standard=(zone==SESSION_LONDON ? 0 : -5*3600);
   datetime guess=wall-standard;
   int offset=(zone==SESSION_LONDON ? LondonUtcOffsetSeconds(guess) : NewYorkUtcOffsetSeconds(guess));
   datetime utc=wall-offset;
   offset=(zone==SESSION_LONDON ? LondonUtcOffsetSeconds(utc) : NewYorkUtcOffsetSeconds(utc));
   return wall-offset;
  }

datetime UtcToServer(const datetime utc_time)
  {
   return utc_time+InpExpectedServerUtcOffsetHours*3600;
  }

datetime ServerToUtc(const datetime server_time)
  {
   return server_time-InpExpectedServerUtcOffsetHours*3600;
  }

void GetLocalDate(const datetime utc_time,const ENUM_SESSION_KIND zone,int &year,int &mon,int &day,int &day_key)
  {
   int offset=(zone==SESSION_LONDON ? LondonUtcOffsetSeconds(utc_time) : NewYorkUtcOffsetSeconds(utc_time));
   MqlDateTime p;
   TimeToStruct(utc_time+offset,p);
   year=p.year;
   mon=p.mon;
   day=p.day;
   day_key=year*10000+mon*100+day;
  }

void ShiftCivilDate(const int year,const int mon,const int day,const int shift_days,int &out_year,int &out_mon,int &out_day)
  {
   datetime wall=MakeDateTime(year,mon,day,12,0)+shift_days*86400;
   MqlDateTime p;
   TimeToStruct(wall,p);
   out_year=p.year;
   out_mon=p.mon;
   out_day=p.day;
  }

bool IsWeekendCivilDate(const int year,const int mon,const int day)
  {
   MqlDateTime p;
   TimeToStruct(MakeDateTime(year,mon,day,12,0),p);
   return (p.day_of_week==0 || p.day_of_week==6);
  }

int ServerDayKey(const datetime server_time)
  {
   MqlDateTime p;
   TimeToStruct(server_time,p);
   return p.year*10000+p.mon*100+p.day;
  }

int ServerWeekKey(const datetime server_time)
  {
   MqlDateTime p;
   TimeToStruct(server_time,p);
   datetime monday=server_time-(p.day_of_week==0 ? 6 : p.day_of_week-1)*86400;
   TimeToStruct(monday,p);
   return p.year*10000+p.mon*100+p.day;
  }

datetime ServerMidnight(const datetime server_time)
  {
   MqlDateTime p;
   TimeToStruct(server_time,p);
   return MakeDateTime(p.year,p.mon,p.day,0,0);
  }

bool BuildBoundsForCivilDate(const int session_index,const int year,const int mon,const int day,
                             datetime &range_start,datetime &range_end,
                             datetime &entry_start,datetime &entry_end)
  {
   if(session_index<0 || session_index>=3)
      return false;

   if(g_sessions[session_index].kind==SESSION_LONDON)
     {
      range_start=UtcToServer(LocalWallToUtc(year,mon,day,0,0,SESSION_LONDON));
      range_end=UtcToServer(LocalWallToUtc(year,mon,day,7,0,SESSION_LONDON));
      entry_start=UtcToServer(LocalWallToUtc(year,mon,day,7,0,SESSION_LONDON));
      entry_end=UtcToServer(LocalWallToUtc(year,mon,day,11,0,SESSION_LONDON));
      return true;
     }

   entry_start=UtcToServer(LocalWallToUtc(year,mon,day,8,30,SESSION_NEW_YORK));
   entry_end=UtcToServer(LocalWallToUtc(year,mon,day,11,0,SESSION_NEW_YORK));

   datetime entry_start_utc=ServerToUtc(entry_start);
   int ly,lm,ld,lkey;
   GetLocalDate(entry_start_utc,SESSION_LONDON,ly,lm,ld,lkey);
   range_start=UtcToServer(LocalWallToUtc(ly,lm,ld,7,0,SESSION_LONDON));
   range_end=UtcToServer(LocalWallToUtc(ly,lm,ld,13,0,SESSION_LONDON));
   return true;
  }

bool GetCurrentSessionBounds(const int session_index,const datetime server_now,
                             int &day_key,datetime &range_start,datetime &range_end,
                             datetime &entry_start,datetime &entry_end)
  {
   datetime utc_now=ServerToUtc(server_now);
   int y,m,d;
   GetLocalDate(utc_now,g_sessions[session_index].kind,y,m,d,day_key);
   return BuildBoundsForCivilDate(session_index,y,m,d,range_start,range_end,entry_start,entry_end);
  }

// ============================================================================
// News calendar
// CSV format: utc_time,currency,impact,title
// Example event: 2026.09.04 12:30,USD,RED,Example release
// Required coverage marker: 2026.09.05 23:59,ALL,COVERAGE,Verified through
// Only RED/HIGH event rows are loaded. Times and coverage are UTC.
// ============================================================================

bool ValidUtcTimestampText(const string value)
  {
   if(StringLen(value)!=16)
      return false;
   for(int i=0;i<16;i++)
     {
      ushort ch=StringGetCharacter(value,i);
      if(i==4 || i==7)
        {
         if(ch!='.') return false;
        }
      else if(i==10)
        {
         if(ch!=' ') return false;
        }
      else if(i==13)
        {
         if(ch!=':') return false;
        }
      else if(ch<'0' || ch>'9')
         return false;
     }
   return true;
  }

bool ValidCurrencyCode(const string value)
  {
   if(StringLen(value)!=3)
      return false;
   for(int i=0;i<3;i++)
     {
      ushort ch=StringGetCharacter(value,i);
      if(ch<'A' || ch>'Z') return false;
     }
   return true;
  }

bool LoadNewsCalendar()
  {
   ArrayResize(g_news,0);
   g_news_coverage_end_utc=0;
   g_news_stale_logged=false;
   int handle=FileOpen(InpNewsCsvFile,FILE_READ|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(handle==INVALID_HANDLE)
     {
      LogEvent("ERROR","NEWS_FILE_OPEN",InpNewsCsvFile);
      return !InpRequireNewsCalendar;
     }

   datetime declared_coverage_end=0;
   while(!FileIsEnding(handle))
     {
      string time_text=FileReadString(handle);
      if(FileIsEnding(handle) && time_text=="")
         break;
      string currency=FileReadString(handle);
      string impact=FileReadString(handle);
      string title=FileReadString(handle);
      StringTrimLeft(time_text);
      StringTrimRight(time_text);
      StringTrimLeft(currency);
      StringTrimRight(currency);
      StringTrimLeft(impact);
      StringTrimRight(impact);
      StringTrimLeft(title);
      StringTrimRight(title);
      StringToUpper(currency);
      StringToUpper(impact);
      string lower_time=time_text;
      StringToLower(lower_time);
      if(time_text=="" || StringFind(lower_time,"utc")>=0)
         continue;
      datetime row_time=(ValidUtcTimestampText(time_text) ? StringToTime(time_text) : 0);
      bool valid_time=(row_time>0 && TimeToString(row_time,TIME_DATE|TIME_MINUTES)==time_text);
      // A far-future event cannot prove that intervening rows are complete.
      // Require an explicit operator-verified coverage declaration instead.
      if(impact=="COVERAGE")
        {
         if(!valid_time || currency!="ALL")
           {
            LogEvent("ERROR","NEWS_COVERAGE_ROW_INVALID",time_text+"|"+currency+"|"+impact);
            FileClose(handle);
            return false;
           }
         if(row_time>declared_coverage_end)
            declared_coverage_end=row_time;
         continue;
        }
      if(impact!="RED" && impact!="HIGH")
         continue;
      if(!valid_time || !ValidCurrencyCode(currency))
        {
         LogEvent("ERROR","NEWS_ROW_INVALID",time_text+"|"+currency+"|"+impact);
         FileClose(handle);
         return false;
        }
      int n=ArraySize(g_news);
      ArrayResize(g_news,n+1);
      g_news[n].utc_time=row_time;
      g_news[n].currency=currency;
      g_news[n].title=title;
     }
   FileClose(handle);
   g_news_coverage_end_utc=declared_coverage_end;

   if(!InpRequireNewsCalendar)
      return true;
   datetime now_utc=ServerToUtc(TimeTradeServer());
   if(declared_coverage_end<now_utc+InpRequiredNewsCoverageHours*3600)
     {
      LogEvent("ERROR","NEWS_COVERAGE_INSUFFICIENT",
               StringFormat("events=%d declared_through=%s required_through=%s",ArraySize(g_news),
                            TimeToString(declared_coverage_end,TIME_DATE|TIME_MINUTES),
                            TimeToString(now_utc+InpRequiredNewsCoverageHours*3600,TIME_DATE|TIME_MINUTES)));
      return false;
     }
   LogEvent("INFO","NEWS_LOADED",StringFormat("red_events=%d coverage_end_utc=%s",ArraySize(g_news),
            TimeToString(g_news_coverage_end_utc,TIME_DATE|TIME_MINUTES)));
   return true;
  }

bool NewsCalendarCurrent()
  {
   if(!InpRequireNewsCalendar)
      return true;
   datetime now_utc=ServerToUtc(TimeTradeServer());
   bool current=(g_news_valid && now_utc>0 &&
                 g_news_coverage_end_utc>=now_utc+InpRequiredNewsCoverageHours*3600);
   if(!current && !g_news_stale_logged)
     {
      g_news_stale_logged=true;
      LogEvent("ERROR","NEWS_RUNTIME_COVERAGE_STALE",
               StringFormat("coverage_end_utc=%s required_through_utc=%s",
                            TimeToString(g_news_coverage_end_utc,TIME_DATE|TIME_MINUTES),
                            TimeToString(now_utc+InpRequiredNewsCoverageHours*3600,
                                         TIME_DATE|TIME_MINUTES)));
     }
   return current;
  }

bool IsRelevantNewsWindow(const string ccy1,const string ccy2,const datetime server_time,const int minutes)
  {
   if(!NewsCalendarCurrent())
      return true;
   datetime utc=ServerToUtc(server_time);
   int window=minutes*60;
   for(int i=0;i<ArraySize(g_news);i++)
     {
      if(g_news[i].currency!=ccy1 && g_news[i].currency!=ccy2)
         continue;
      long delta=(long)(g_news[i].utc_time-utc);
      if(MathAbs((double)delta)<=window+SAFETY_TIME_LEAD_SECONDS)
         return true;
     }
   return false;
  }

bool UpcomingRelevantNews(const string ccy1,const string ccy2,const datetime server_time,
                          const int minutes,datetime &event_server,string &title)
  {
   event_server=0;
   title="";
   if(!NewsCalendarCurrent())
     {
      title="calendar_unavailable_or_stale";
      return true;
     }
   datetime utc=ServerToUtc(server_time);
   long best=0;
   bool found=false;
   for(int i=0;i<ArraySize(g_news);i++)
     {
      if(g_news[i].currency!=ccy1 && g_news[i].currency!=ccy2)
         continue;
      long delta=(long)(g_news[i].utc_time-utc);
      if(delta>=0 && delta<=minutes*60+SAFETY_TIME_LEAD_SECONDS && (!found || delta<best))
        {
         found=true;
         best=delta;
         event_server=UtcToServer(g_news[i].utc_time);
         title=g_news[i].title;
        }
     }
   return found;
  }

bool RecentRelevantNews(const string ccy1,const string ccy2,const datetime server_time,
                        const int minutes)
  {
   if(!NewsCalendarCurrent())
      return true;
   datetime utc=ServerToUtc(server_time);
   for(int i=0;i<ArraySize(g_news);i++)
     {
      if(g_news[i].currency!=ccy1 && g_news[i].currency!=ccy2)
         continue;
      long elapsed=(long)(utc-g_news[i].utc_time);
      if(elapsed>=0 && elapsed<=minutes*60+SAFETY_TIME_LEAD_SECONDS)
         return true;
     }
   return false;
  }

// ============================================================================
// Market data and statistics
// ============================================================================

bool TickIsFresh(const MqlTick &tick)
  {
   datetime now=TimeTradeServer();
   long age=(long)(now-tick.time);
   return (tick.time>0 && tick.bid>0.0 && tick.ask>tick.bid &&
           age>=0 && age<=InpMaxQuoteAgeSeconds);
  }

bool ReadRange(const string symbol,const datetime start_time,const datetime end_time,double &high,double &low)
  {
   MqlRates rates[];
   ArraySetAsSeries(rates,false);
   int period=PeriodSeconds(PERIOD_M5);
   int copied=CopyRates(symbol,PERIOD_M5,start_time,end_time-1,rates);
   int expected=(int)((end_time-start_time)/period);
   if(expected<=0 || copied!=expected || ArraySize(rates)!=expected)
      return false;
   high=-DBL_MAX;
   low=DBL_MAX;
   for(int i=0;i<copied;i++)
     {
      if(rates[i].time!=start_time+i*period)
         return false;
      if(rates[i].high>high) high=rates[i].high;
      if(rates[i].low<low) low=rates[i].low;
     }
   return (high>low && high>-DBL_MAX/2 && low<DBL_MAX/2);
  }

bool ComputeAtrBefore(const string symbol,const datetime before_time,double &atr)
  {
   atr=0.0;
   int handle=INVALID_HANDLE;
   for(int i=0;i<3;i++)
      if(g_sessions[i].symbol==symbol)
        {
         handle=g_atr_handles[i];
         break;
        }
   if(handle==INVALID_HANDLE || BarsCalculated(handle)<=14)
      return false;

   // Use MT5's canonical iATR implementation rather than a simple 14-TR
   // arithmetic mean. The shift is anchored to one second before the boundary,
   // guaranteeing that only a fully completed M15 bar is sampled.
   int shift=iBarShift(symbol,PERIOD_M15,before_time-1,false);
   if(shift<0)
      return false;
   datetime bar_open=iTime(symbol,PERIOD_M15,shift);
   if(bar_open<=0 || bar_open+PeriodSeconds(PERIOD_M15)>before_time)
      return false;
   double values[];
   ArrayResize(values,1);
   if(CopyBuffer(handle,0,shift,1,values)!=1)
      return false;
   atr=values[0];
   return atr>0.0 && atr!=EMPTY_VALUE;
  }

bool GetCompletedSessionBars(const string symbol,const datetime session_start,MqlRates &rates[])
  {
   ArrayResize(rates,0);
   datetime current_open=iTime(symbol,PERIOD_M5,0);
   if(current_open<=session_start)
      return true;
   int period=PeriodSeconds(PERIOD_M5);
   int expected=(int)((current_open-session_start)/period);
   if(expected<=0)
      return true;
   ArraySetAsSeries(rates,false);
   int copied=CopyRates(symbol,PERIOD_M5,session_start,current_open-1,rates);
   if(copied!=expected || ArraySize(rates)!=expected || rates[0].time!=session_start ||
      rates[expected-1].time+period!=current_open)
      return false;
   for(int i=1;i<expected;i++)
      if(rates[i].time-rates[i-1].time!=period)
         return false;
   return true;
  }

bool GetCompletedBarAt(const string symbol,const datetime bar_open,MqlRates &rate)
  {
   MqlRates values[];
   ArraySetAsSeries(values,false);
   int copied=CopyRates(symbol,PERIOD_M5,bar_open,bar_open+PeriodSeconds(PERIOD_M5)-1,values);
   if(copied!=1 || values[0].time!=bar_open ||
      bar_open+PeriodSeconds(PERIOD_M5)>iTime(symbol,PERIOD_M5,0))
      return false;
   rate=values[0];
   return true;
  }

bool HasConfirmedOneRClose(const string symbol,const datetime opened,
                           const ENUM_POSITION_TYPE type,const double one_r_price)
  {
   datetime current_open=iTime(symbol,PERIOD_M5,0);
   if(current_open<=0 || one_r_price<=0.0 || current_open<=opened)
      return false;
   MqlRates bars[];
   ArraySetAsSeries(bars,false);
   datetime copy_start=opened-PeriodSeconds(PERIOD_M5);
   if(copy_start<0) copy_start=0;
   int copied=CopyRates(symbol,PERIOD_M5,copy_start,current_open-1,bars);
   if(copied<=0)
      return false;
   for(int i=0;i<copied;i++)
     {
      // Include the bar containing a mid-bar fill, but never a bar that had
      // already completed at or before the confirmed fill timestamp.
      if(bars[i].time+PeriodSeconds(PERIOD_M5)<=opened || bars[i].time>=current_open)
         continue;
      if(type==POSITION_TYPE_BUY && bars[i].close>=one_r_price)
         return true;
      if(type==POSITION_TYPE_SELL && bars[i].close<=one_r_price)
         return true;
     }
   return false;
  }

void SortDoubles(double &values[])
  {
   ArraySort(values);
  }

double Median(double &values[])
  {
   int n=ArraySize(values);
   if(n==0) return 0.0;
   SortDoubles(values);
   if((n%2)==1) return values[n/2];
   return (values[n/2-1]+values[n/2])/2.0;
  }

double PercentileRank(const double value,double &history[])
  {
   int n=ArraySize(history);
   if(n==0) return -1.0;
   int less_or_equal=0;
   for(int i=0;i<n;i++)
      if(history[i]<=value) less_or_equal++;
   return 100.0*less_or_equal/n;
  }

bool GetHistoricalMinuteSpread(const string symbol,const datetime server_time,double &spread_points)
  {
   MqlRates rate[];
   ArraySetAsSeries(rate,false);
   int copied=CopyRates(symbol,PERIOD_M1,server_time,server_time+59,rate);
   if(copied!=1 || rate[0].time!=server_time)
      return false;
   spread_points=(double)rate[0].spread;
   return spread_points>0.0;
  }

bool ComparableStatistics(const int session_index,const datetime signal_time,const double current_range_width,
                          const double current_atr,double &range_percentile,double &atr_percentile,
                          double &spread_median)
  {
   SessionRuntime s=g_sessions[session_index];
   datetime signal_utc=ServerToUtc(signal_time);
   int y,m,d,current_key;
   GetLocalDate(signal_utc,s.kind,y,m,d,current_key);
   // The order decision exists only after the displacement M5 bar closes, so
   // minute-matched spread history must use that close/decision minute rather
   // than the bar's open timestamp.
   int elapsed=(int)(signal_time+PeriodSeconds(PERIOD_M5)-s.entry_start);
   if(elapsed<0) return false;

   double ranges[];
   double atrs[];
   double spreads[];
   ArrayResize(ranges,0);
   ArrayResize(atrs,0);
   ArrayResize(spreads,0);

   int attempts=0;
   for(int shift=-1;attempts<160 && ArraySize(ranges)<InpComparableSessions;shift--,attempts++)
     {
      int hy,hm,hd;
      ShiftCivilDate(y,m,d,shift,hy,hm,hd);
      if(IsWeekendCivilDate(hy,hm,hd))
         continue;
      datetime rs,re,es,ee;
      if(!BuildBoundsForCivilDate(session_index,hy,hm,hd,rs,re,es,ee))
         continue;
      double rh,rl;
      if(!ReadRange(s.symbol,rs,re,rh,rl))
         continue;
      datetime comparable_time=es+elapsed;
      double av,sv;
      // The ATR regime sample is frozen at each comparable session open;
      // spread remains minute-of-session matched to the signal time.
      if(!ComputeAtrBefore(s.symbol,es,av))
         continue;
      if(!GetHistoricalMinuteSpread(s.symbol,comparable_time,sv))
         continue;
      int n=ArraySize(ranges);
      ArrayResize(ranges,n+1);
      ArrayResize(atrs,n+1);
      ArrayResize(spreads,n+1);
      ranges[n]=rh-rl;
      atrs[n]=av;
      spreads[n]=sv;
     }

   if(ArraySize(ranges)<InpComparableSessions)
     {
      LogEvent("WARN","STATS_INSUFFICIENT",StringFormat("%s got=%d need=%d",s.id,ArraySize(ranges),InpComparableSessions));
      return false;
     }
   range_percentile=PercentileRank(current_range_width,ranges);
   atr_percentile=PercentileRank(current_atr,atrs);
   spread_median=Median(spreads);
   return true;
  }

// ============================================================================
// Account exposure, daily history, and guard state
// ============================================================================

bool IsPendingEntryType(const ENUM_ORDER_TYPE type)
  {
   return type==ORDER_TYPE_BUY_LIMIT || type==ORDER_TYPE_SELL_LIMIT ||
          type==ORDER_TYPE_BUY_STOP || type==ORDER_TYPE_SELL_STOP ||
          type==ORDER_TYPE_BUY_STOP_LIMIT || type==ORDER_TYPE_SELL_STOP_LIMIT;
  }

int PendingEntryCount()
  {
   int count=0;
   for(int i=0;i<OrdersTotal();i++)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0) continue;
      ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(IsPendingEntryType(type))
         count++;
     }
   return count;
  }

bool HasAnyExposure()
  {
   return PositionsTotal()>0 || PendingEntryCount()>0;
  }

bool HasForeignExposure()
  {
   for(int i=0;i<PositionsTotal();i++)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=InpMagic)
         return true;
     }
   for(int i=0;i<OrdersTotal();i++)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0) continue;
      if((long)OrderGetInteger(ORDER_MAGIC)!=InpMagic)
         return true;
     }
   return false;
  }

bool RebuildDailyClosedTrades(int &trade_count,double &first_trade_net,double &day_closed_net,bool &foreign_deal)
  {
   trade_count=0;
   first_trade_net=0.0;
   day_closed_net=0.0;
   foreign_deal=false;
   if(g_day_start_time<=0 || !HistorySelect(g_day_start_time,TimeTradeServer()))
      return false;

   long ids[];
   datetime exit_times[];
   ArrayResize(ids,0);
   ArrayResize(exit_times,0);

   int total=HistoryDealsTotal();
   for(int i=0;i<total;i++)
     {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0) continue;
      long magic=HistoryDealGetInteger(deal,DEAL_MAGIC);
      if(magic!=InpMagic)
        {
         ENUM_DEAL_TYPE foreign_type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE);
         if(foreign_type==DEAL_TYPE_BUY || foreign_type==DEAL_TYPE_SELL)
            foreign_deal=true;
         continue;
        }
      ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
      if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY)
         continue;
      long position_id=HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      datetime deal_time=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
      int found=-1;
      for(int j=0;j<ArraySize(ids);j++)
         if(ids[j]==position_id) { found=j; break; }
      if(found<0)
        {
         int n=ArraySize(ids);
         ArrayResize(ids,n+1);
         ArrayResize(exit_times,n+1);
         ids[n]=position_id;
         exit_times[n]=deal_time;
        }
      else if(deal_time<exit_times[found])
         exit_times[found]=deal_time;
     }

   double nets[];
   ArrayResize(nets,ArraySize(ids));
   ArrayInitialize(nets,0.0);
   for(int i=0;i<total;i++)
     {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0) continue;
      long position_id=HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      for(int j=0;j<ArraySize(ids);j++)
        {
         if(ids[j]!=position_id) continue;
         nets[j]+=HistoryDealGetDouble(deal,DEAL_PROFIT)+
                  HistoryDealGetDouble(deal,DEAL_COMMISSION)+
                  HistoryDealGetDouble(deal,DEAL_SWAP)+
                  HistoryDealGetDouble(deal,DEAL_FEE);
        }
     }

   // Sort by exit time so the first trade's outcome is deterministic.
   for(int i=0;i<ArraySize(ids)-1;i++)
      for(int j=i+1;j<ArraySize(ids);j++)
         if(exit_times[j]<exit_times[i])
           {
            datetime tt=exit_times[i]; exit_times[i]=exit_times[j]; exit_times[j]=tt;
            double nn=nets[i]; nets[i]=nets[j]; nets[j]=nn;
           }

   trade_count=ArraySize(ids);
   for(int i=0;i<trade_count;i++) day_closed_net+=nets[i];
   if(trade_count>0) first_trade_net=nets[0];
   return true;
  }

bool StrategyPositionNetFromHistory(const long position_id,double &net)
  {
   net=0.0;
   if(position_id<=0 || !HistorySelect(g_state_created_time>1 ? g_state_created_time-1 : 0,
                                       TimeTradeServer()))
      return false;
   bool owned_entry=false;
   bool completed=false;
   for(int i=0;i<HistoryDealsTotal();i++)
     {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0 || HistoryDealGetInteger(deal,DEAL_POSITION_ID)!=position_id)
         continue;
      ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE);
      ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
      if((type==DEAL_TYPE_BUY || type==DEAL_TYPE_SELL) && entry==DEAL_ENTRY_IN &&
         HistoryDealGetInteger(deal,DEAL_MAGIC)==InpMagic &&
         StringFind(HistoryDealGetString(deal,DEAL_COMMENT),"TRIAD|")==0)
         owned_entry=true;
      if((type==DEAL_TYPE_BUY || type==DEAL_TYPE_SELL) &&
         (entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY))
         completed=true;
      net+=HistoryDealGetDouble(deal,DEAL_PROFIT)+
           HistoryDealGetDouble(deal,DEAL_COMMISSION)+
           HistoryDealGetDouble(deal,DEAL_SWAP)+
           HistoryDealGetDouble(deal,DEAL_FEE);
     }
   return owned_entry && completed;
  }

datetime LastTradingActivityTime()
  {
   datetime from=(g_state_created_time>0 ? g_state_created_time : TimeTradeServer()-365*86400);
   if(!HistorySelect(from,TimeTradeServer()))
      return from;
   datetime latest=from;
   for(int i=0;i<HistoryDealsTotal();i++)
     {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0) continue;
      ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE);
      if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) continue;
      datetime when=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
      if(when>latest) latest=when;
     }
   return latest;
  }

bool IsCommissionCashflowDeal(const ENUM_DEAL_TYPE type)
  {
   return type==DEAL_TYPE_COMMISSION || type==DEAL_TYPE_COMMISSION_DAILY ||
          type==DEAL_TYPE_COMMISSION_MONTHLY || type==DEAL_TYPE_COMMISSION_AGENT_DAILY ||
          type==DEAL_TYPE_COMMISSION_AGENT_MONTHLY;
  }

bool IsExternalCashflowDeal(const ENUM_DEAL_TYPE type)
  {
   return type==DEAL_TYPE_BALANCE || type==DEAL_TYPE_CREDIT || type==DEAL_TYPE_CHARGE ||
          type==DEAL_TYPE_CORRECTION || type==DEAL_TYPE_BONUS ||
          IsCommissionCashflowDeal(type) || type==DEAL_TYPE_INTEREST ||
          type==DEAL_TYPE_BUY_CANCELED || type==DEAL_TYPE_SELL_CANCELED ||
          type==DEAL_TYPE_DIVIDEND || type==DEAL_TYPE_DIVIDEND_FRANKED ||
          type==DEAL_TYPE_TAX;
  }

void CheckExternalCashflow(const bool force=false)
  {
   datetime now=TimeTradeServer();
   if(g_external_cashflow_detected || g_account_history_fault ||
      (!force && g_last_cashflow_check>0 && now-g_last_cashflow_check<10))
      return;
   g_last_cashflow_check=now;
   datetime from=(g_state_created_time>1 ? g_state_created_time-1 : 0);
   if(!HistorySelect(from,now))
     {
      g_external_cashflow_detected=true;
      Halt("external_cashflow_history_unavailable");
      return;
     }
   // Deals alone cannot reveal a pending order that was placed and cancelled
   // while this EA was offline. Audit historical orders created after the state
   // handshake so that no-trade manual/foreign activity is still quarantined.
   for(int i=0;i<HistoryOrdersTotal();i++)
     {
      ulong order=HistoryOrderGetTicket(i);
      if(order==0) continue;
      datetime setup=(datetime)HistoryOrderGetInteger(order,ORDER_TIME_SETUP);
      if(setup<g_state_created_time) continue;
      ENUM_ORDER_TYPE order_type=(ENUM_ORDER_TYPE)HistoryOrderGetInteger(order,ORDER_TYPE);
      if(!IsPendingEntryType(order_type))
         continue; // market-order activity is audited through its resulting deal
      long magic=HistoryOrderGetInteger(order,ORDER_MAGIC);
      string symbol=HistoryOrderGetString(order,ORDER_SYMBOL);
      bool enabled_symbol=false;
      for(int s=0;s<3;s++)
         if(g_sessions[s].enabled && g_sessions[s].symbol==symbol)
           {
            enabled_symbol=true;
            break;
           }
      bool strategy_type=(order_type==ORDER_TYPE_BUY_LIMIT || order_type==ORDER_TYPE_SELL_LIMIT);
      bool pending_comment_ok=(StringFind(HistoryOrderGetString(order,ORDER_COMMENT),"TRIAD|")==0);
      if(magic!=InpMagic || !enabled_symbol || !strategy_type || !pending_comment_ok)
        {
         g_account_history_fault=true;
         LogEvent("WARN","UNAUTHORIZED_ORDER_HISTORY",
                  StringFormat("order=%I64u magic=%I64d symbol=%s type=%d",order,magic,symbol,
                               (int)order_type));
         RequireStateMigration("unauthorized_order_history");
         Halt("unauthorized_order_history");
         return;
        }
     }
   for(int i=0;i<HistoryDealsTotal();i++)
     {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0) continue;
      long deal_msc=HistoryDealGetInteger(deal,DEAL_TIME_MSC);
      if(deal_msc<=g_history_baseline_msc) continue;
      ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE);
      if(type==DEAL_TYPE_BUY || type==DEAL_TYPE_SELL)
        {
         long magic=HistoryDealGetInteger(deal,DEAL_MAGIC);
         if(magic!=InpMagic)
           {
            g_account_history_fault=true;
            LogEvent("WARN","UNAUTHORIZED_TRADING_HISTORY",
                     StringFormat("deal=%I64u magic=%I64d",deal,magic));
            RequireStateMigration("unauthorized_trading_history");
            Halt("unauthorized_trading_history");
            return;
           }
         string symbol=HistoryDealGetString(deal,DEAL_SYMBOL);
         bool enabled_symbol=false;
         for(int s=0;s<3;s++)
            if(g_sessions[s].enabled && g_sessions[s].symbol==symbol)
              {
               enabled_symbol=true;
               break;
              }
         ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
         bool entry_comment_ok=(entry!=DEAL_ENTRY_IN ||
                                StringFind(HistoryDealGetString(deal,DEAL_COMMENT),"TRIAD|")==0);
         if(!enabled_symbol || !entry_comment_ok)
           {
            g_account_history_fault=true;
            LogEvent("WARN","UNAUTHORIZED_STRATEGY_MAGIC_HISTORY",
                     StringFormat("deal=%I64u symbol=%s entry=%d",deal,symbol,(int)entry));
            RequireStateMigration("unauthorized_strategy_magic_history");
            Halt("unauthorized_strategy_magic_history");
            return;
           }
        }
      if(IsExternalCashflowDeal(type))
        {
         // A separate commission deal tied to a position is part of that
         // trade's net result and is aggregated by position ID. Untied
         // commission/charge operations remain external cashflows.
         if(IsCommissionCashflowDeal(type) &&
            HistoryDealGetInteger(deal,DEAL_POSITION_ID)>0)
            continue;
         g_external_cashflow_detected=true;
         LogEvent("WARN","EXTERNAL_CASHFLOW_DETECTED",
                  StringFormat("deal=%I64u type=%d time_msc=%I64d",deal,(int)type,deal_msc));
         RequireStateMigration("external_cashflow_requires_rebaseline_release");
         Halt("external_cashflow_requires_rebaseline_release");
         return;
        }
     }
  }

void CheckInactivity()
  {
   datetime now=TimeTradeServer();
   if(g_last_inactivity_check>0 && now-g_last_inactivity_check<3600)
      return;
   g_last_inactivity_check=now;
   datetime last=LastTradingActivityTime();
   int days=(int)((now-last)/86400);
   int alert_level=(days>=25 ? 25 : (days>=20 ? 20 : 0));
   if(alert_level>0 && alert_level!=g_last_inactivity_alert_day)
     {
      g_last_inactivity_alert_day=alert_level;
      if(!GVWrite("InactAlert",alert_level) ||
         !GVWrite("StateSig",AccountStateSignature()))
         Halt("inactivity_state_persistence_failure");
      GlobalVariablesFlush();
      LogEvent("WARN","INACTIVITY_ALERT",StringFormat("days=%d; no maintenance trade will be placed",days));
     }
   if(days<20 && g_last_inactivity_alert_day!=0)
     {
      g_last_inactivity_alert_day=0;
      if(!GVWrite("InactAlert",0.0) ||
         !GVWrite("StateSig",AccountStateSignature()))
         Halt("inactivity_state_persistence_failure");
      GlobalVariablesFlush();
     }
  }

void CheckDirectionConcentration()
  {
   datetime now=TimeTradeServer();
   if(g_last_direction_check>0 && now-g_last_direction_check<3600)
      return;
   g_last_direction_check=now;
   int today=ServerDayKey(now);
   if(g_direction_alert_day_key==today)
      return;
   datetime from=(g_state_created_time>0 ? g_state_created_time : TimeTradeServer()-365*86400);
   if(!HistorySelect(from,TimeTradeServer()))
      return;
   int buys=0,sells=0,collected=0;
   long position_ids[];
   ArrayResize(position_ids,0);
   for(int i=HistoryDealsTotal()-1;i>=0 && collected<20;i--)
     {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0 || HistoryDealGetInteger(deal,DEAL_MAGIC)!=InpMagic) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
      long position_id=HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      bool duplicate=false;
      for(int j=0;j<ArraySize(position_ids);j++)
         if(position_ids[j]==position_id) { duplicate=true; break; }
      if(duplicate) continue;
      int n=ArraySize(position_ids);
      ArrayResize(position_ids,n+1);
      position_ids[n]=position_id;
      ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE);
      if(type==DEAL_TYPE_BUY) { buys++; collected++; }
      else if(type==DEAL_TYPE_SELL) { sells++; collected++; }
     }
   if(collected==20 && MathMax(buys,sells)>=18)
     {
      g_direction_alert_day_key=today;
      LogEvent("WARN","DIRECTION_CONCENTRATION_REVIEW",
               StringFormat("last20 buys=%d sells=%d; no opposite trade will be forced",buys,sells));
     }
  }

bool DailyStateAllowsEntry(string &reason)
  {
   int count;
   double first_net,closed_net;
   bool foreign_deal;
   if(!RebuildDailyClosedTrades(count,first_net,closed_net,foreign_deal))
     {
      reason="daily_history_unavailable";
      return false;
     }
   if(foreign_deal)
     {
      reason="manual_or_foreign_deal_detected";
      return false;
     }
   if(count>=2)
     {
      reason="two_completed_trades";
      return false;
     }
   if(count==1 && first_net>0.0)
     {
      reason="first_trade_net_positive";
      return false;
     }
   return true;
  }

double CurrentStrategyDrawdownPercent()
  {
   if(g_high_water_balance<=0.0) return 0.0;
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   return MathMax(0.0,100.0*(g_high_water_balance-equity)/g_high_water_balance);
  }

double SelectedBaseRiskFraction()
  {
   switch(InpProfile)
     {
      case PROFILE_A_040_R150: return 0.0040;
      case PROFILE_B_035_R175: return 0.0035;
      case PROFILE_C_030_R200: return 0.0030;
      case PROFILE_D_025_R250: return 0.0025;
     }
   return 0.0;
  }

double SelectedTargetR()
  {
   switch(InpProfile)
     {
      case PROFILE_A_040_R150: return 1.50;
      case PROFILE_B_035_R175: return 1.75;
      case PROFILE_C_030_R200: return 2.00;
      case PROFILE_D_025_R250: return 2.50;
     }
   return 0.0;
  }

double ActiveRiskFraction()
  {
   double risk=SelectedBaseRiskFraction();
   if(CurrentStrategyDrawdownPercent()>=InpDrawdownReducePercent)
      risk*=0.5;
   return risk;
  }

double PhaseTargetBalance()
  {
   if(InpPhase==TRIAD_PHASE_1) return InpPhaseInitialBalance*1.10;
   if(InpPhase==TRIAD_PHASE_2) return InpPhaseInitialBalance*1.05;
   return InpPhaseInitialBalance*1.10; // funded scale candidate; dashboard controls
  }

int EffectiveConfirmedDays()
  {
   if(IsTesterMode() && InpUseEstimatedDaysInTester)
      return g_estimated_profitable_days;
   return InpDashboardConfirmedDays;
  }

double FirmOverallFloor()
  {
   return InpPhaseInitialBalance*0.90;
  }

double FirmReserveCash(const double one_trade_slippage_reserve)
  {
   double percent_reserve=InpPhaseInitialBalance*InpFirmFloorReservePercent/100.0;
   return MathMax(percent_reserve,2.0*MathMax(0.0,one_trade_slippage_reserve));
  }

bool CanTakeCashRisk(const double stressed_loss,const double slippage_reserve,string &reason)
  {
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double projected=equity-stressed_loss;
   double active_firm_floor=MathMax(g_firm_daily_floor,FirmOverallFloor());
   if(projected<=active_firm_floor+FirmReserveCash(slippage_reserve))
     {
      reason="firm_floor_projection";
      return false;
     }
   if(projected<=g_day_start_balance-InpPhaseInitialBalance*InpInternalDailyStopPercent/100.0)
     {
      reason="internal_daily_projection";
      return false;
     }
   if(projected<=g_week_start_balance-InpPhaseInitialBalance*InpInternalWeeklyStopPercent/100.0)
     {
      reason="internal_weekly_projection";
      return false;
     }
   double shutdown_equity=g_high_water_balance*(1.0-InpDrawdownShutdownPercent/100.0);
   if(projected<=shutdown_equity)
     {
      reason="strategy_drawdown_projection";
      return false;
     }
   return true;
  }

bool RuntimeAccountIdentityValid()
  {
   if(!InpEnableOrderSubmission || IsTesterMode())
      return true;
   double stored_config=0.0,stored_identity=0.0;
   datetime gmt=TimeGMT();
   datetime server=TimeTradeServer();
   if(gmt<=0 || server<=0) return false;
   long offset_error=(long)(server-gmt-InpExpectedServerUtcOffsetHours*3600);
   if(offset_error<0) offset_error=-offset_error;
   return GVRead("Cfg",stored_config) && (int)stored_config==g_config_hash &&
          GVRead("Identity",stored_identity) &&
          (int)stored_identity==g_runtime_identity_hash &&
          RuntimeIdentityHash()==g_runtime_identity_hash &&
          AuthorizedAccountContext() && OwnsLiveInstanceLock() &&
          AccountInfoString(ACCOUNT_CURRENCY)==InpExpectedAccountCurrency &&
          (int)AccountInfoInteger(ACCOUNT_LEVERAGE)==InpExpectedAccountLeverage &&
          (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)==
             ACCOUNT_MARGIN_MODE_RETAIL_HEDGING &&
          AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) && AccountInfoInteger(ACCOUNT_TRADE_EXPERT) &&
          TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && MQLInfoInteger(MQL_TRADE_ALLOWED) &&
          offset_error<=SERVER_OFFSET_TOLERANCE_SECONDS;
  }

bool RuntimeJournalValid(string &reason)
  {
   if(!InpEnableOrderSubmission || IsTesterMode())
      return true;
   double persisted_halt=0.0,persisted_halt_reason=0.0;
   double persisted_rebase=0.0,persisted_signature=0.0;
   if(!ReadHaltLatch(persisted_halt,persisted_halt_reason) ||
      !GVRead("Rebase",persisted_rebase) || !GVRead("StateSig",persisted_signature) ||
      (int)persisted_signature!=AccountStateSignature() ||
      (!NearlyEqual(persisted_rebase,0.0) && !NearlyEqual(persisted_rebase,1.0)))
     {
      reason="runtime_persisted_state_mismatch";
      return false;
     }
   if(persisted_halt>0.5 || persisted_rebase>0.5)
     {
      g_halted=true;
      g_halt_reason=(persisted_rebase>0.5 ? "runtime_state_migration_latch" :
                                                "runtime_persisted_halt_latch");
      LogEvent("HALT","PERSISTED_RUNTIME_LATCH",g_halt_reason);
      reason=g_halt_reason;
      return false;
     }
   return true;
  }

bool RiskGuardRequiresPersistentHalt(const string reason)
  {
   // Daily and weekly governors are calendar locks that reset only through the
   // confirmed rollover state machine. All other global-guard failures require
   // explicit reconciliation before this release can resume.
   return reason!="internal_daily_stop" && reason!="internal_weekly_stop";
  }

bool GlobalRiskGuards(string &reason)
  {
   if(g_halted)
     {
      reason="runtime_halt_latched";
      return false;
     }
   if(!RuntimeAccountIdentityValid())
     {
      reason="runtime_account_identity_mismatch";
      return false;
     }
   if(!RuntimeJournalValid(reason))
      return false;
   if(g_log_failure)
     {
      reason="audit_log_failure";
      return false;
     }
   if(g_rebaseline_required)
     {
      reason="state_migration_required";
      return false;
     }
   if(g_account_history_fault)
     {
      reason="unauthorized_trading_history";
      return false;
     }
   if(g_external_cashflow_detected)
     {
      reason="external_cashflow_requires_rebaseline_release";
      return false;
     }
   if(InpLifecycleLock!=LIFECYCLE_ACTIVE)
     {
      if(InpLifecycleLock==LIFECYCLE_PAYOUT_REQUEST) reason="payout_request_lock";
      else if(InpLifecycleLock==LIFECYCLE_PHASE_TRANSITION) reason="phase_transition_lock";
      else if(InpLifecycleLock==LIFECYCLE_SCALE_TRANSITION) reason="scale_transition_lock";
      else reason="invalid_lifecycle_lock";
      return false;
     }
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity<=FirmOverallFloor())
     {
      reason="firm_overall_floor";
      return false;
     }
   if(equity<=g_firm_daily_floor)
     {
      reason="firm_daily_floor";
      return false;
     }
   if(equity<=g_day_start_balance-InpPhaseInitialBalance*InpInternalDailyStopPercent/100.0)
     {
      reason="internal_daily_stop";
      return false;
     }
   if(equity<=g_week_start_balance-InpPhaseInitialBalance*InpInternalWeeklyStopPercent/100.0)
     {
      reason="internal_weekly_stop";
      return false;
     }
   if(CurrentStrategyDrawdownPercent()>=InpDrawdownShutdownPercent)
     {
      reason="strategy_drawdown_shutdown";
      return false;
     }
   if(AccountInfoDouble(ACCOUNT_BALANCE)>=PhaseTargetBalance())
     {
      reason=(EffectiveConfirmedDays()>=3 ? "phase_complete" : "target_pending_days");
      return false;
     }
   return true;
  }

// ============================================================================
// Session state
// ============================================================================

string SessionConsumedKey(const int index)
  {
   return "S"+IntegerToString(index)+"Done";
  }

void PersistSessionConsumed(const int index)
  {
   if(g_sessions[index].consumed)
     {
      if(!GVWrite(SessionConsumedKey(index),g_sessions[index].local_day_key))
         Halt("session_state_persistence_failure");
      GlobalVariablesFlush();
     }
  }

bool RefreshSession(const int index,const datetime now)
  {
   int key;
   datetime rs,re,es,ee;
   if(!GetCurrentSessionBounds(index,now,key,rs,re,es,ee))
      return false;
   if(g_sessions[index].local_day_key!=key)
     {
      g_sessions[index].local_day_key=key;
      g_sessions[index].range_start=rs;
      g_sessions[index].range_end=re;
      g_sessions[index].entry_start=es;
      g_sessions[index].entry_end=ee;
      g_sessions[index].range_ready=false;
      g_sessions[index].range_warning_logged=false;
      g_sessions[index].range_high=0.0;
      g_sessions[index].range_low=0.0;
      g_sessions[index].consumed=false;
      g_sessions[index].last_closed_bar=0;
      double consumed_key;
      if(GVRead(SessionConsumedKey(index),consumed_key) && (int)consumed_key==key)
         g_sessions[index].consumed=true;
      else if(InpEnableOrderSubmission && !IsTesterMode() && InpSkipFreshMidSessionStart &&
              now>es+300 && now<ee)
        {
         g_sessions[index].consumed=true;
         PersistSessionConsumed(index);
         LogEvent("WARN","MID_SESSION_START_SKIPPED",g_sessions[index].id);
        }
     }
   if(!g_sessions[index].range_ready && now>=g_sessions[index].range_end)
     {
      g_sessions[index].range_ready=ReadRange(g_sessions[index].symbol,g_sessions[index].range_start,
                                              g_sessions[index].range_end,
                                              g_sessions[index].range_high,g_sessions[index].range_low);
      if(!g_sessions[index].range_ready && !g_sessions[index].range_warning_logged)
        {
         g_sessions[index].range_warning_logged=true;
         LogEvent("WARN","RANGE_NOT_READY",g_sessions[index].id);
        }
     }
   return true;
  }

// ============================================================================
// Signal detection and order preparation
// ============================================================================

double LowerWickRatio(const MqlRates &bar)
  {
   double total=bar.high-bar.low;
   if(total<=0.0) return 0.0;
   return (MathMin(bar.open,bar.close)-bar.low)/total;
  }

double UpperWickRatio(const MqlRates &bar)
  {
   double total=bar.high-bar.low;
   if(total<=0.0) return 0.0;
   return (bar.high-MathMax(bar.open,bar.close))/total;
  }

double BodyRatio(const MqlRates &bar)
  {
   double total=bar.high-bar.low;
   if(total<=0.0) return 0.0;
   return MathAbs(bar.close-bar.open)/total;
  }

bool DetectPattern(const int session_index,SignalCandidate &candidate)
  {
   ZeroMemory(candidate);
   candidate.session_index=session_index;
   candidate.symbol=g_sessions[session_index].symbol;
   candidate.detected=false;
   candidate.valid=false;

   MqlRates bars[];
   datetime signal_start=(g_sessions[session_index].entry_start>g_sessions[session_index].range_end ?
                          g_sessions[session_index].entry_start : g_sessions[session_index].range_end);
   // During the temporary US/UK DST mismatch the NY entry clock can open
   // before its London reference range ends. Never reconstruct or trade a bar
   // from that overlap; the completed range must already have been knowable.
   if(!GetCompletedSessionBars(candidate.symbol,signal_start,bars))
     {
      candidate.rejection="session_bars_unavailable";
      return false;
     }
   int n=ArraySize(bars);
   if(n==0 || bars[n-1].time==g_sessions[session_index].last_closed_bar)
      return false;
   g_sessions[session_index].last_closed_bar=bars[n-1].time;
   candidate.signal_bar_time=bars[n-1].time;

   // Freeze ATR at the candidate entry-window open. This keeps the current
   // regime value aligned with the prior-60 session-open reference sample and
   // prevents a later signal from changing its own sweep/stop scale.
   double atr;
   if(!ComputeAtrBefore(candidate.symbol,g_sessions[session_index].entry_start,atr))
     {
      candidate.rejection="atr_unavailable";
      return false;
     }
   candidate.atr=atr;
   candidate.range_high=g_sessions[session_index].range_high;
   candidate.range_low=g_sessions[session_index].range_low;

   // Reconstruct the first qualifying sweep event from the start of the entry
   // window. Once that event resolves—validly or invalidly—the session is
   // consumed, so a later repeated sweep cannot reset the sequence.
   int sweep_index=-1;
   ENUM_PATTERN_SIDE sweep_side=PATTERN_NONE;
   for(int i=0;i<n;i++)
     {
      double long_depth=(candidate.range_low-bars[i].low)/atr;
      double short_depth=(bars[i].high-candidate.range_high)/atr;
      bool long_sweep=(long_depth>=InpSweepAtrMin);
      bool short_sweep=(short_depth>=InpSweepAtrMin);
      if(!long_sweep && !short_sweep)
         continue;
      sweep_index=i;
      if(long_sweep && short_sweep)
        {
         candidate.detected=true;
         candidate.signal_bar_time=bars[i].time;
         candidate.rejection="ambiguous_two_sided_sweep";
         return true;
        }
      sweep_side=(long_sweep ? PATTERN_LONG : PATTERN_SHORT);
      break;
     }
   if(sweep_index<0)
     {
      candidate.rejection="no_sweep_event";
      return false;
     }

   candidate.side=sweep_side;
   double sweep_extreme=(sweep_side==PATTERN_LONG ? bars[sweep_index].low
                                                  : bars[sweep_index].high);
   int reclaim_index=-1;
   int last_reclaim_bar=(n-1<sweep_index+InpReclaimBars-1 ? n-1
                                                          : sweep_index+InpReclaimBars-1);
   for(int i=sweep_index;i<=last_reclaim_bar;i++)
     {
      if(sweep_side==PATTERN_LONG)
        {
         sweep_extreme=MathMin(sweep_extreme,bars[i].low);
         double depth=(candidate.range_low-sweep_extreme)/atr;
         if(depth>InpSweepAtrMax)
           {
            candidate.detected=true;
            candidate.signal_bar_time=bars[i].time;
            candidate.rejection="sweep_too_deep";
            return true;
           }
         if((bars[i].high-candidate.range_high)/atr>=InpSweepAtrMin)
           {
            candidate.detected=true;
            candidate.signal_bar_time=bars[i].time;
            candidate.rejection="opposite_sweep_before_reclaim";
            return true;
           }
         if(bars[i].close>candidate.range_low && bars[i].close<candidate.range_high)
           {
            if(LowerWickRatio(bars[i])<InpReclaimWickMin)
              {
               candidate.detected=true;
               candidate.signal_bar_time=bars[i].time;
               candidate.rejection="reclaim_wick";
               return true;
              }
            reclaim_index=i;
            break;
           }
        }
      else
        {
         sweep_extreme=MathMax(sweep_extreme,bars[i].high);
         double depth=(sweep_extreme-candidate.range_high)/atr;
         if(depth>InpSweepAtrMax)
           {
            candidate.detected=true;
            candidate.signal_bar_time=bars[i].time;
            candidate.rejection="sweep_too_deep";
            return true;
           }
         if((candidate.range_low-bars[i].low)/atr>=InpSweepAtrMin)
           {
            candidate.detected=true;
            candidate.signal_bar_time=bars[i].time;
            candidate.rejection="opposite_sweep_before_reclaim";
            return true;
           }
         if(bars[i].close<candidate.range_high && bars[i].close>candidate.range_low)
           {
            if(UpperWickRatio(bars[i])<InpReclaimWickMin)
              {
               candidate.detected=true;
               candidate.signal_bar_time=bars[i].time;
               candidate.rejection="reclaim_wick";
               return true;
              }
            reclaim_index=i;
            break;
           }
        }
     }

   if(reclaim_index<0)
     {
      if(n<sweep_index+InpReclaimBars)
        {
         candidate.rejection="sweep_waiting_for_reclaim";
         return false;
        }
      candidate.detected=true;
      candidate.signal_bar_time=bars[sweep_index+InpReclaimBars-1].time;
      candidate.rejection="no_reclaim_within_three";
      return true;
     }
   if(n<=reclaim_index+1)
     {
      candidate.rejection="reclaim_waiting_for_displacement";
      return false;
     }

   MqlRates reclaim=bars[reclaim_index];
   MqlRates displacement=bars[reclaim_index+1];
   candidate.detected=true;
   candidate.signal_bar_time=displacement.time;
   candidate.sweep_extreme=sweep_extreme;
   if(displacement.time!=bars[n-1].time)
     {
      candidate.rejection="stale_signal_event";
      return true;
     }
   bool displacement_valid=false;
   if(sweep_side==PATTERN_LONG)
      displacement_valid=(displacement.close>displacement.open &&
                          BodyRatio(displacement)>=InpDisplacementBodyMin &&
                          displacement.close>(reclaim.high+reclaim.low)/2.0);
   else
      displacement_valid=(displacement.close<displacement.open &&
                          BodyRatio(displacement)>=InpDisplacementBodyMin &&
                          displacement.close<(reclaim.high+reclaim.low)/2.0);
   if(!displacement_valid)
      candidate.rejection="weak_displacement";
   return true;
  }

int VolumeDigits(const double step)
  {
   int digits=0;
   double scaled=step;
   while(digits<8 && MathAbs(scaled-MathRound(scaled))>1e-9)
     {
      scaled*=10.0;
      digits++;
     }
   return digits;
  }

double NormalizePriceToTick(const string symbol,const double price)
  {
   double tick_size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   if(tick_size<=0.0) tick_size=SymbolInfoDouble(symbol,SYMBOL_POINT);
   return NormalizeDouble(MathRound(price/tick_size)*tick_size,digits);
  }

double NormalizePriceDown(const string symbol,const double price)
  {
   double tick_size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   if(tick_size<=0.0) tick_size=SymbolInfoDouble(symbol,SYMBOL_POINT);
   return NormalizeDouble(MathFloor((price+1e-12)/tick_size)*tick_size,digits);
  }

double NormalizePriceUp(const string symbol,const double price)
  {
   double tick_size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   if(tick_size<=0.0) tick_size=SymbolInfoDouble(symbol,SYMBOL_POINT);
   return NormalizeDouble(MathCeil((price-1e-12)/tick_size)*tick_size,digits);
  }

bool BrokerDistancesValid(const SignalCandidate &candidate,const MqlTick &tick)
  {
   double point=SymbolInfoDouble(candidate.symbol,SYMBOL_POINT);
   int stops=(int)SymbolInfoInteger(candidate.symbol,SYMBOL_TRADE_STOPS_LEVEL);
   int freeze=(int)SymbolInfoInteger(candidate.symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   double minimum=MathMax(stops,freeze)*point;
   double epsilon=point*0.1;
   if(candidate.side==PATTERN_LONG)
      return candidate.entry<tick.ask && candidate.stop<candidate.entry && candidate.target>candidate.entry &&
             tick.ask-candidate.entry+epsilon>=minimum &&
             candidate.entry-candidate.stop+epsilon>=minimum &&
             candidate.target-candidate.entry+epsilon>=minimum;
   return candidate.entry>tick.bid && candidate.stop>candidate.entry && candidate.target<candidate.entry &&
          candidate.entry-tick.bid+epsilon>=minimum &&
          candidate.stop-candidate.entry+epsilon>=minimum &&
          candidate.entry-candidate.target+epsilon>=minimum;
  }

bool CurrentCostToR(const SignalCandidate &candidate,const MqlTick &tick,double &cost_to_r)
  {
   cost_to_r=DBL_MAX;
   if(tick.bid<=0.0 || tick.ask<=tick.bid)
      return false;
   double point=SymbolInfoDouble(candidate.symbol,SYMBOL_POINT);
   if(point<=0.0)
      return false;
   ENUM_ORDER_TYPE order_type=(candidate.side==PATTERN_LONG ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   double spread_result;
   if(candidate.side==PATTERN_LONG)
     {
      if(!OrderCalcProfit(order_type,candidate.symbol,1.0,tick.ask,tick.bid,spread_result))
         return false;
     }
   else
     {
      if(!OrderCalcProfit(order_type,candidate.symbol,1.0,tick.bid,tick.ask,spread_result))
         return false;
     }
   double slippage_distance=(InpStopSlippageReservePoints+InpTargetSlippageReservePoints)*point;
   double adverse_slippage_price=(candidate.side==PATTERN_LONG ? candidate.entry-slippage_distance
                                                               : candidate.entry+slippage_distance);
   double slippage_result,price_risk;
   if(!OrderCalcProfit(order_type,candidate.symbol,1.0,candidate.entry,
                       adverse_slippage_price,slippage_result) ||
      !OrderCalcProfit(order_type,candidate.symbol,1.0,candidate.entry,candidate.stop,price_risk) ||
      MathAbs(price_risk)<=1e-12)
      return false;
   cost_to_r=(MathAbs(spread_result)+MathAbs(slippage_result)+
              InpCommissionRoundTripPerLot)/MathAbs(price_risk);
   return cost_to_r>=0.0;
  }

bool MarginAvailableForCandidate(const SignalCandidate &candidate)
  {
   // OrderCalcMargin is evaluated with the corresponding market side, as in
   // the MQL5 reference example for pending-order margin estimation.
   ENUM_ORDER_TYPE order_type=(candidate.side==PATTERN_LONG ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   double required_margin=0.0;
   if(!OrderCalcMargin(order_type,candidate.symbol,candidate.volume,candidate.entry,required_margin))
      return false;
   return required_margin>=0.0 && required_margin<=AccountInfoDouble(ACCOUNT_MARGIN_FREE)+1e-6;
  }

bool CashLossForVolume(const SignalCandidate &candidate,const double volume,double &cash_loss,
                       double &slippage_reserve_cash)
  {
   double point=SymbolInfoDouble(candidate.symbol,SYMBOL_POINT);
   double adverse_stop=candidate.stop;
   ENUM_ORDER_TYPE order_type=(candidate.side==PATTERN_LONG ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   if(candidate.side==PATTERN_LONG)
      adverse_stop-=InpStopSlippageReservePoints*point;
   else
      adverse_stop+=InpStopSlippageReservePoints*point;
   double base_result,adverse_result;
   if(!OrderCalcProfit(order_type,candidate.symbol,volume,candidate.entry,candidate.stop,base_result) ||
      !OrderCalcProfit(order_type,candidate.symbol,volume,candidate.entry,adverse_stop,adverse_result))
      return false;
   slippage_reserve_cash=MathMax(0.0,MathAbs(adverse_result)-MathAbs(base_result));
   cash_loss=MathAbs(adverse_result)+InpCommissionRoundTripPerLot*volume;
   return cash_loss>0.0;
  }

bool CalculateVolume(SignalCandidate &candidate,const double budget)
  {
   double one_lot_loss,one_lot_slippage;
   if(!CashLossForVolume(candidate,1.0,one_lot_loss,one_lot_slippage) ||
      one_lot_slippage<0.0)
      return false;
   double minimum=SymbolInfoDouble(candidate.symbol,SYMBOL_VOLUME_MIN);
   double maximum=SymbolInfoDouble(candidate.symbol,SYMBOL_VOLUME_MAX);
   double directional_limit=SymbolInfoDouble(candidate.symbol,SYMBOL_VOLUME_LIMIT);
   if(directional_limit>0.0) maximum=MathMin(maximum,directional_limit);
   double step=SymbolInfoDouble(candidate.symbol,SYMBOL_VOLUME_STEP);
   if(minimum<=0.0 || maximum<=0.0 || step<=0.0)
      return false;
   double raw=budget/one_lot_loss;
   if(raw<minimum-1e-12 || maximum<minimum)
      return false;
   // Volume grids are anchored at SYMBOL_VOLUME_MIN, not necessarily at zero.
   // This remains identical for ordinary 0.01/0.01 FX grids but avoids creating
   // an invalid lot value when a broker exposes a non-zero-offset step lattice.
   double units=MathFloor((raw-minimum+1e-12)/step);
   double maximum_units=MathFloor((maximum-minimum+1e-12)/step);
   double volume=minimum+MathMin(units,maximum_units)*step;
   int volume_digits=VolumeDigits(step);
   int minimum_digits=VolumeDigits(minimum);
   if(minimum_digits>volume_digits) volume_digits=minimum_digits;
   volume=NormalizeDouble(volume,volume_digits);
   if(volume<minimum-1e-12 || volume>maximum+1e-12)
      return false;
   double actual_loss,slippage_reserve;
   if(!CashLossForVolume(candidate,volume,actual_loss,slippage_reserve) || actual_loss>budget+1e-6)
      return false;
   candidate.volume=volume;
   candidate.cash_risk=actual_loss;
   candidate.slippage_reserve_cash=slippage_reserve;
   return true;
  }

bool SolveTargetPrice(SignalCandidate &candidate,const double target_r)
  {
   ENUM_ORDER_TYPE order_type=(candidate.side==PATTERN_LONG ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   double point=SymbolInfoDouble(candidate.symbol,SYMBOL_POINT);
   double stop_distance=MathAbs(candidate.entry-candidate.stop);
   double desired_net=candidate.cash_risk*target_r;
   double low=0.0;
   double high=stop_distance*target_r*3.0;
   for(int iteration=0;iteration<60;iteration++)
     {
      double distance=(low+high)/2.0;
      double nominal=(candidate.side==PATTERN_LONG ? candidate.entry+distance : candidate.entry-distance);
      double effective=(candidate.side==PATTERN_LONG ? nominal-InpTargetSlippageReservePoints*point
                                                     : nominal+InpTargetSlippageReservePoints*point);
      double gross;
      if(!OrderCalcProfit(order_type,candidate.symbol,candidate.volume,candidate.entry,effective,gross))
         return false;
      double net=gross-InpCommissionRoundTripPerLot*candidate.volume;
      if(net<desired_net) low=distance; else high=distance;
     }
   double raw_target=(candidate.side==PATTERN_LONG ? candidate.entry+high : candidate.entry-high);
   candidate.target=(candidate.side==PATTERN_LONG ? NormalizePriceUp(candidate.symbol,raw_target)
                                                  : NormalizePriceDown(candidate.symbol,raw_target));
   double effective_target=(candidate.side==PATTERN_LONG ?
                            candidate.target-InpTargetSlippageReservePoints*point :
                            candidate.target+InpTargetSlippageReservePoints*point);
   double actual_gross;
   if(!OrderCalcProfit(order_type,candidate.symbol,candidate.volume,candidate.entry,
                       effective_target,actual_gross))
      return false;
   candidate.target_net=actual_gross-InpCommissionRoundTripPerLot*candidate.volume;
   double raw_one_r=(candidate.side==PATTERN_LONG ? candidate.entry+stop_distance
                                                  : candidate.entry-stop_distance);
   candidate.one_r_price=(candidate.side==PATTERN_LONG ? NormalizePriceUp(candidate.symbol,raw_one_r)
                                                       : NormalizePriceDown(candidate.symbol,raw_one_r));
   return candidate.target>0.0 && candidate.target_net+1e-6>=desired_net;
  }

bool RefreshCandidateQuoteState(SignalCandidate &candidate)
  {
   MqlTick tick;
   double point=SymbolInfoDouble(candidate.symbol,SYMBOL_POINT);
   if(point<=0.0 || !SymbolInfoTick(candidate.symbol,tick) || !TickIsFresh(tick) ||
      (candidate.side==PATTERN_LONG && candidate.entry>=tick.ask) ||
      (candidate.side==PATTERN_SHORT && candidate.entry<=tick.bid))
     {
      candidate.rejection="quote_changed_or_stale";
      return false;
     }
   candidate.spread_points=(tick.ask-tick.bid)/point;
   if(candidate.spread_median_points<=0.0 ||
      candidate.spread_points>InpSpreadMedianMultiplier*candidate.spread_median_points)
     {
      candidate.rejection="spread_gate_recheck";
      return false;
     }
   if(!CurrentCostToR(candidate,tick,candidate.cost_to_r) ||
      candidate.cost_to_r>InpMaxCostToR)
     {
      candidate.rejection="cost_to_r_recheck";
      return false;
     }
   if(!BrokerDistancesValid(candidate,tick))
     {
      candidate.rejection="broker_stop_or_freeze_level";
      return false;
     }
   return true;
  }

bool PrepareCandidate(SignalCandidate &candidate)
  {
   SessionRuntime s=g_sessions[candidate.session_index];
   MqlRates displacement;
   if(!GetCompletedBarAt(candidate.symbol,candidate.signal_bar_time,displacement))
     {
      candidate.rejection="displacement_bar_unavailable";
      return false;
     }
   candidate.entry=NormalizePriceToTick(candidate.symbol,(displacement.open+displacement.close)/2.0);
   double raw_stop=(candidate.side==PATTERN_LONG ?
                    candidate.sweep_extreme-InpStopBufferAtr*candidate.atr :
                    candidate.sweep_extreme+InpStopBufferAtr*candidate.atr);
   candidate.stop=(candidate.side==PATTERN_LONG ? NormalizePriceDown(candidate.symbol,raw_stop)
                                               : NormalizePriceUp(candidate.symbol,raw_stop));

   double stop_distance=MathAbs(candidate.entry-candidate.stop);
   double stop_atr=stop_distance/candidate.atr;
   if(stop_atr<InpStopAtrMin || stop_atr>InpStopAtrMax)
     {
      candidate.rejection="stop_atr";
      return false;
     }

   if((ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(candidate.symbol,SYMBOL_TRADE_MODE)!=SYMBOL_TRADE_MODE_FULL)
     {
      candidate.rejection="symbol_not_full_trade_mode";
      return false;
     }
   MqlTick tick;
   if(!SymbolInfoTick(candidate.symbol,tick) || !TickIsFresh(tick))
     {
      candidate.rejection="quote_stale";
      return false;
     }
   double point=SymbolInfoDouble(candidate.symbol,SYMBOL_POINT);
   candidate.spread_points=(tick.ask-tick.bid)/point;
   if(candidate.side==PATTERN_LONG && candidate.entry>=tick.ask)
     {
      candidate.rejection="buy_limit_marketable_or_missed";
      return false;
     }
   if(candidate.side==PATTERN_SHORT && candidate.entry<=tick.bid)
     {
      candidate.rejection="sell_limit_marketable_or_missed";
      return false;
     }

   if(IsRelevantNewsWindow(s.ccy1,s.ccy2,TimeTradeServer(),InpNewsBlockMinutes))
     {
      candidate.rejection="news_blackout";
      return false;
     }

   if(!ComparableStatistics(candidate.session_index,candidate.signal_bar_time,
                            candidate.range_high-candidate.range_low,candidate.atr,
                            candidate.range_percentile,candidate.atr_percentile,
                            candidate.spread_median_points))
     {
      candidate.rejection="comparable_stats";
      return false;
     }
   if(candidate.range_percentile<InpRangePercentileLow || candidate.range_percentile>InpRangePercentileHigh)
     {
      candidate.rejection="range_percentile";
      return false;
     }
   if(candidate.atr_percentile<InpAtrPercentileLow || candidate.atr_percentile>InpAtrPercentileHigh)
     {
      candidate.rejection="atr_percentile";
      return false;
     }
   if(candidate.spread_median_points<=0.0 ||
      candidate.spread_points>InpSpreadMedianMultiplier*candidate.spread_median_points)
     {
      candidate.rejection="spread_gate";
      return false;
     }

   // Cost-to-R includes current spread, configured round-trip slippage, and
   // round-trip commission, all converted by OrderCalcProfit.
   if(!CurrentCostToR(candidate,tick,candidate.cost_to_r))
     { candidate.rejection="cost_calc"; return false; }
   if(candidate.cost_to_r>InpMaxCostToR)
     {
      candidate.rejection="cost_to_r";
      return false;
     }

   double budget=InpPhaseInitialBalance*ActiveRiskFraction();
   if(!CalculateVolume(candidate,budget))
     {
      candidate.rejection="volume_or_min_lot";
      return false;
     }
   if(!MarginAvailableForCandidate(candidate))
     {
      candidate.rejection="insufficient_or_unknown_margin";
      return false;
     }
   if(!SolveTargetPrice(candidate,SelectedTargetR()))
     {
      candidate.rejection="target_calc";
      return false;
     }
   // Historical-statistics loading can take long enough for the first quote
   // snapshot to age. Refresh every quote-derived field before accepting it.
   if(!RefreshCandidateQuoteState(candidate))
      return false;

   if(candidate.side==PATTERN_LONG && candidate.range_high-candidate.entry<candidate.target-candidate.entry)
     {
      candidate.rejection="target_room";
      return false;
     }
   if(candidate.side==PATTERN_SHORT && candidate.entry-candidate.range_low<candidate.entry-candidate.target)
     {
      candidate.rejection="target_room";
      return false;
     }

   string risk_reason;
   if(!CanTakeCashRisk(candidate.cash_risk,candidate.slippage_reserve_cash,risk_reason))
     {
      candidate.rejection=risk_reason;
      return false;
     }

   candidate.expiry_time=candidate.signal_bar_time+(InpLimitExpiryBars+1)*PeriodSeconds(PERIOD_M5);
   candidate.valid=true;
   return true;
  }

// ============================================================================
// Trade requests and management
// ============================================================================

bool CanSendNonEmergencyRequest()
  {
   if(g_request_count>=InpMaxNonEmergencyRequestsDay)
     {
      Halt("non_emergency_request_cap");
      return false;
     }
   return true;
  }

bool CountTradeRequest(const string operation,const bool emergency)
  {
   if(!emergency)
     {
      g_request_count++;
      if(!GVWrite("ReqCount",g_request_count) ||
         !GVWrite("StateSig",AccountStateSignature()))
        {
         Halt("request_count_persistence_failure");
         return false;
        }
      GlobalVariablesFlush();
     }
   LogEvent("INFO","TRADE_REQUEST",operation+" emergency="+BoolText(emergency));
   if(g_log_failure && !emergency)
     {
      Halt("audit_log_failure_before_nonemergency_request");
      return false;
     }
   return true;
  }

bool SafetyRequestDue(const ulong ticket,const string operation,const int minimum_seconds=10,
                      const bool must_execute=false)
  {
   int slot=(operation=="D" ? 0 : (operation=="C" ? 1 : (operation=="R" ? 2 : 3)));
   datetime now=TimeTradeServer();
   if(g_safety_request_tickets[slot]==ticket &&
      now-g_safety_request_times[slot]<minimum_seconds)
      return false;
   // Keep the suffix compact: terminal-global names are limited to 63 chars.
   string name=GVName("X"+operation+"."+StringFormat("%I64u",ticket));
   if(GlobalVariableCheck(name) && now-(datetime)(long)GlobalVariableGet(name)<minimum_seconds)
      return false;
   // Update the in-memory fallback before storage. If terminal-global storage
   // fails, emergency cleanup may still make one throttled attempt; an optional
   // modification is blocked rather than becoming unrate-limited.
   g_safety_request_tickets[slot]=ticket;
   g_safety_request_times[slot]=now;
   if(GlobalVariableSet(name,(double)now)==0)
     {
      Halt("safety_request_throttle_persistence_failure");
      return must_execute;
     }
   return true;
  }

bool TradeRetcodeAccepted(const bool allow_placed=false,const bool allow_no_changes=true)
  {
   uint code=g_trade.ResultRetcode();
   return code==TRADE_RETCODE_DONE || code==TRADE_RETCODE_DONE_PARTIAL ||
          (allow_no_changes && code==TRADE_RETCODE_NO_CHANGES) ||
          (allow_placed && code==TRADE_RETCODE_PLACED);
  }

bool TransientTradeRetcode(const uint code)
  {
   return code==TRADE_RETCODE_REQUOTE || code==TRADE_RETCODE_TIMEOUT ||
          code==TRADE_RETCODE_PRICE_CHANGED || code==TRADE_RETCODE_PRICE_OFF ||
          code==TRADE_RETCODE_TOO_MANY_REQUESTS || code==TRADE_RETCODE_LOCKED ||
          code==TRADE_RETCODE_CONNECTION;
  }

bool DeleteOrder(const ulong ticket,const string reason,const bool emergency=true)
  {
   if(!InpEnableOrderSubmission || !AuthorizedAccountContext() || !OwnsLiveInstanceLock())
      return false;
   if(!OrderSelect(ticket)) return true;
   if(emergency && !SafetyRequestDue(ticket,"D",10,true)) return false;
   CountTradeRequest(StringFormat("delete_order %I64u %s",ticket,reason),emergency);
   bool ok=g_trade.OrderDelete(ticket);
   ok=ok && TradeRetcodeAccepted(false);
   if(!ok && !OrderSelect(ticket))
     {
      ok=true;
      LogEvent("INFO","ORDER_ALREADY_ABSENT_AFTER_DELETE",StringFormat("ticket=%I64u",ticket));
     }
   else if(ok && OrderSelect(ticket))
     {
      ok=false;
      LogEvent("ERROR","ORDER_DELETE_INCOMPLETE",StringFormat("ticket=%I64u remains active",ticket));
     }
   if(!ok)
     {
      LogEvent("ERROR","ORDER_DELETE_FAILED",StringFormat("ticket=%I64u ret=%u %s",ticket,
               g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription()));
      if(emergency) Halt("emergency_order_delete_failed_"+reason);
     }
   else if(!OrderSelect(ticket))
      GlobalVariableDel(GVName("XD."+StringFormat("%I64u",ticket)));
   return ok;
  }

bool ClosePosition(const ulong ticket,const string reason,const bool emergency=true)
  {
   if(!InpEnableOrderSubmission || !AuthorizedAccountContext() || !OwnsLiveInstanceLock())
      return false;
   if(!PositionSelectByTicket(ticket)) return true;
   if(emergency && !SafetyRequestDue(ticket,"C",10,true)) return false;
   CountTradeRequest(StringFormat("close_position %I64u %s",ticket,reason),emergency);
   if(!g_trade.SetTypeFillingBySymbol(PositionGetString(POSITION_SYMBOL)))
     {
      LogEvent("ERROR","POSITION_CLOSE_FILLING_MODE_FAILED",StringFormat("ticket=%I64u",ticket));
      if(emergency) Halt("emergency_position_close_filling_mode_failed_"+reason);
      return false;
     }
   bool ok=g_trade.PositionClose(ticket,InpMaxDeviationPoints);
   ok=ok && TradeRetcodeAccepted(false);
   if(!ok && !PositionSelectByTicket(ticket))
     {
      ok=true;
      LogEvent("INFO","POSITION_ALREADY_ABSENT_AFTER_CLOSE",StringFormat("ticket=%I64u",ticket));
     }
   else if(ok && PositionSelectByTicket(ticket))
     {
      ok=false;
      LogEvent("ERROR","POSITION_CLOSE_INCOMPLETE",StringFormat("ticket=%I64u remains open",ticket));
     }
   if(!ok)
     {
      LogEvent("ERROR","POSITION_CLOSE_FAILED",StringFormat("ticket=%I64u ret=%u %s",ticket,
               g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription()));
      if(emergency) Halt("emergency_position_close_failed_"+reason);
     }
   else if(!PositionSelectByTicket(ticket))
     {
      string ticket_text=StringFormat("%I64u",ticket);
      GlobalVariableDel(GVName("XC."+ticket_text));
      GlobalVariableDel(GVName("XB."+ticket_text));
      GlobalVariableDel(GVName("XR."+ticket_text));
     }
   return ok;
  }

void CancelAllPending(const string reason,const bool emergency=true)
  {
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0 || (long)OrderGetInteger(ORDER_MAGIC)!=InpMagic) continue;
      DeleteOrder(ticket,reason,emergency);
     }
  }

void CloseAllPositions(const string reason,const bool emergency=true)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || (long)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      ClosePosition(ticket,reason,emergency);
     }
  }

bool SubmitCandidate(const SignalCandidate &candidate)
  {
   int price_digits=(int)SymbolInfoInteger(candidate.symbol,SYMBOL_DIGITS);
   string detail="session="+g_sessions[candidate.session_index].id+
                 " symbol="+candidate.symbol+
                 " side="+IntegerToString((int)candidate.side)+
                 " entry="+DoubleToString(candidate.entry,price_digits)+
                 " stop="+DoubleToString(candidate.stop,price_digits)+
                 " target="+DoubleToString(candidate.target,price_digits)+
                 " vol="+DoubleToString(candidate.volume,VolumeDigits(SymbolInfoDouble(candidate.symbol,SYMBOL_VOLUME_STEP)))+
                 " risk="+DoubleToString(candidate.cash_risk,2)+
                 " target_net="+DoubleToString(candidate.target_net,2)+
                 " range_pct="+DoubleToString(candidate.range_percentile,1)+
                 " atr_pct="+DoubleToString(candidate.atr_percentile,1)+
                 " costR="+DoubleToString(candidate.cost_to_r,3);
   LogEvent("INFO","VALID_CANDIDATE",detail);

   if(!InpEnableOrderSubmission)
     {
      LogEvent("INFO","DRY_RUN_NO_ORDER",detail);
      return true;
     }
   if(!AuthorizedAccountContext())
     {
      Halt("runtime_account_context_changed");
      return false;
     }
   if(!OwnsLiveInstanceLock())
     {
      Halt("live_instance_lock_not_owned");
      return false;
     }
   if(g_halted)
     {
      LogEvent("WARN","ORDER_BLOCKED","strategy_halted "+g_halt_reason);
      return false;
     }
   CheckExternalCashflow(true);
   if(g_halted)
     {
      LogEvent("WARN","ORDER_BLOCKED","account history changed during final revalidation");
      return false;
     }
   string recheck_reason="";
   datetime recheck_now=TimeTradeServer();
   MqlTick recheck_tick;
   double recheck_cost_to_r=DBL_MAX;
   double recheck_cash_loss=0.0;
   double recheck_slippage_reserve=0.0;
   double point=SymbolInfoDouble(candidate.symbol,SYMBOL_POINT);
   if(recheck_now+SAFETY_TIME_LEAD_SECONDS>=candidate.expiry_time ||
      recheck_now+SAFETY_TIME_LEAD_SECONDS>=g_sessions[candidate.session_index].entry_end)
      recheck_reason="candidate_expired_or_session_closed";
   else if(!TerminalInfoInteger(TERMINAL_CONNECTED))
      recheck_reason="terminal_disconnected";
   else if((ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(candidate.symbol,SYMBOL_TRADE_MODE)!=SYMBOL_TRADE_MODE_FULL)
      recheck_reason="symbol_not_full_trade_mode";
   else if(!SymbolInfoTick(candidate.symbol,recheck_tick) || !TickIsFresh(recheck_tick))
      recheck_reason="quote_stale_or_invalid";
   else if(!BrokerDistancesValid(candidate,recheck_tick))
      recheck_reason="broker_stop_or_freeze_level";
   else if(point<=0.0 || candidate.spread_median_points<=0.0 ||
           (recheck_tick.ask-recheck_tick.bid)/point>
              InpSpreadMedianMultiplier*candidate.spread_median_points)
      recheck_reason="spread_gate_recheck";
   else if(!CurrentCostToR(candidate,recheck_tick,recheck_cost_to_r) ||
           recheck_cost_to_r>InpMaxCostToR)
      recheck_reason="cost_to_r_recheck";
   else if(!CashLossForVolume(candidate,candidate.volume,recheck_cash_loss,
                              recheck_slippage_reserve) ||
           recheck_cash_loss>InpPhaseInitialBalance*ActiveRiskFraction()+1e-6)
      recheck_reason="cash_risk_budget_recheck";
   else if(!MarginAvailableForCandidate(candidate))
      recheck_reason="margin_recheck";
   else if(IsRelevantNewsWindow(g_sessions[candidate.session_index].ccy1,
                                g_sessions[candidate.session_index].ccy2,
                                recheck_now,InpNewsBlockMinutes))
      recheck_reason="news_blackout";
   else if(!DailyStateAllowsEntry(recheck_reason))
      recheck_reason=(recheck_reason=="" ? "daily_state_recheck" : recheck_reason);
   else if(!GlobalRiskGuards(recheck_reason))
      recheck_reason=(recheck_reason=="" ? "global_risk_recheck" : recheck_reason);
   else if(!CanTakeCashRisk(recheck_cash_loss,recheck_slippage_reserve,recheck_reason))
      recheck_reason=(recheck_reason=="" ? "cash_risk_recheck" : recheck_reason);
   if(recheck_reason!="")
     {
      LogEvent("WARN","ORDER_REVALIDATION_FAILED",recheck_reason);
      return false;
     }
   if(!CanSendNonEmergencyRequest())
      return false;
   if(HasAnyExposure())
     {
      LogEvent("WARN","ORDER_BLOCKED","account_exposure_mutex");
      return false;
     }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpMaxDeviationPoints);
   if(!g_trade.SetTypeFillingBySymbol(candidate.symbol))
     {
      Halt("filling_mode_configuration_failed");
      return false;
     }
   string comment="TRIAD|"+g_sessions[candidate.session_index].id+"|"+
                  IntegerToString(g_sessions[candidate.session_index].local_day_key);
   bool plan_persisted=true;
   if(!GVWrite("ExpectedEntry",candidate.entry)) plan_persisted=false;
   if(!GVWrite("ExpectedSL",candidate.stop)) plan_persisted=false;
   if(!GVWrite("ExpectedTP",candidate.target)) plan_persisted=false;
   if(!GVWrite("Expected1R",candidate.one_r_price)) plan_persisted=false;
   if(!GVWrite("ExpectedVolume",candidate.volume)) plan_persisted=false;
   if(!GVWrite("ExpectedSession",candidate.session_index)) plan_persisted=false;
   if(!GVWrite("ExpectedExpiry",(double)candidate.expiry_time)) plan_persisted=false;
   if(!GVWrite("OneRConfirmed",0.0)) plan_persisted=false;
   if(!GVWrite("BreakEvenAttempts",0.0)) plan_persisted=false;
   if(!GVWrite("PredictedNetTarget",candidate.target_net)) plan_persisted=false;
   if(!GVWrite("ActualTradeNet",0.0)) plan_persisted=false;
   if(!GVWrite("PlannedCashRisk",candidate.cash_risk)) plan_persisted=false;
   GlobalVariablesFlush();
   if(!plan_persisted)
     {
      Halt("trade_plan_persistence_failure");
      return false;
     }
   if(!CountTradeRequest("submit "+comment,false))
      return false;
   bool ok=false;
   ulong request_started=GetTickCount64();
   if(candidate.side==PATTERN_LONG)
      ok=g_trade.BuyLimit(candidate.volume,candidate.entry,candidate.symbol,candidate.stop,candidate.target,
                         ORDER_TIME_SPECIFIED,candidate.expiry_time,comment);
   else
      ok=g_trade.SellLimit(candidate.volume,candidate.entry,candidate.symbol,candidate.stop,candidate.target,
                          ORDER_TIME_SPECIFIED,candidate.expiry_time,comment);
   ulong request_latency=GetTickCount64()-request_started;
   LogEvent("INFO","ORDER_REQUEST_LATENCY",StringFormat("milliseconds=%I64u",request_latency));
   ok=ok && TradeRetcodeAccepted(true,false);
   if(g_log_failure)
     {
      Halt("audit_log_failure_after_order_request");
      ulong uncertain_order=g_trade.ResultOrder();
      if(uncertain_order>0 && OrderSelect(uncertain_order))
         DeleteOrder(uncertain_order,"audit_log_failure",true);
      CancelAllPending("audit_log_failure",true);
      CloseAllPositions("audit_log_failure",true);
      return false;
     }
   if(!ok)
     {
      uint failed_code=g_trade.ResultRetcode();
      LogEvent("ERROR","ORDER_SUBMIT_FAILED",StringFormat("ret=%u %s",failed_code,
               g_trade.ResultRetcodeDescription()));
      // A transport timeout or late server acknowledgement can create exposure
      // even when the synchronous wrapper reports failure. Latch first, then
      // reconcile and clean up instead of treating the plan as safely absent.
      Halt("order_submission_failed");
      ulong possible_order=g_trade.ResultOrder();
      if(possible_order>0 && OrderSelect(possible_order))
         DeleteOrder(possible_order,"failed_submission_reconcile",true);
      CancelAllPending("failed_submission_reconcile",true);
      CloseAllPositions("failed_submission_reconcile",true);
      if(!HasAnyExposure())
        {
         bool plan_cleared=true;
         if(!GVWrite("ExpectedEntry",0.0)) plan_cleared=false;
         if(!GVWrite("ExpectedSL",0.0)) plan_cleared=false;
         if(!GVWrite("ExpectedTP",0.0)) plan_cleared=false;
         if(!GVWrite("Expected1R",0.0)) plan_cleared=false;
         if(!GVWrite("ExpectedVolume",0.0)) plan_cleared=false;
         if(!GVWrite("ExpectedSession",-1.0)) plan_cleared=false;
         if(!GVWrite("ExpectedExpiry",0.0)) plan_cleared=false;
         if(!GVWrite("OneRConfirmed",0.0)) plan_cleared=false;
         if(!GVWrite("BreakEvenAttempts",0.0)) plan_cleared=false;
         if(!GVWrite("PredictedNetTarget",0.0)) plan_cleared=false;
         if(!GVWrite("ActualTradeNet",0.0)) plan_cleared=false;
         if(!GVWrite("PlannedCashRisk",0.0)) plan_cleared=false;
         GlobalVariablesFlush();
         if(!plan_cleared) Halt("trade_plan_clear_failure");
        }
      return false;
     }
   if(request_latency>(ulong)InpMaxTradeRequestLatencyMs)
     {
      LogEvent("ERROR","ORDER_REQUEST_LATENCY_BREACH",
               StringFormat("milliseconds=%I64u limit=%d",request_latency,InpMaxTradeRequestLatencyMs));
      Halt("order_request_latency_breach");
      ulong order_ticket=g_trade.ResultOrder();
      if(order_ticket>0 && OrderSelect(order_ticket))
         DeleteOrder(order_ticket,"latency_breach",true);
      CancelAllPending("latency_breach",true);
      CloseAllPositions("latency_breach",true);
      return false;
     }
   LogEvent("INFO","ORDER_SUBMITTED",StringFormat("order=%I64u",g_trade.ResultOrder()));
   if(g_log_failure)
     {
      Halt("audit_log_failure_after_order_submit");
      ulong submitted_order=g_trade.ResultOrder();
      if(submitted_order>0 && OrderSelect(submitted_order))
         DeleteOrder(submitted_order,"audit_log_failure",true);
      CancelAllPending("audit_log_failure",true);
      CloseAllPositions("audit_log_failure",true);
      return false;
     }
   // Reconcile the accepted order/instant fill synchronously; do not leave a
   // full timer interval in which broker-adjusted or missing exits go unchecked.
   ManageExposure();
   return !g_halted;
  }

bool LoadExpectedTradePlan(double &entry,double &stop,double &target,double &volume,int &session_index)
  {
   double stored_session;
   if(!GVRead("ExpectedEntry",entry) || !GVRead("ExpectedSL",stop) ||
      !GVRead("ExpectedTP",target) || !GVRead("ExpectedVolume",volume) ||
      !GVRead("ExpectedSession",stored_session))
      return false;
   session_index=(int)stored_session;
   return entry>0.0 && stop>0.0 && target>0.0 && volume>0.0 &&
          session_index>=0 && session_index<3;
  }

bool PriceMatches(const string symbol,const double left,const double right)
  {
   double tick_size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tick_size<=0.0) tick_size=SymbolInfoDouble(symbol,SYMBOL_POINT);
   return tick_size>0.0 && MathAbs(left-right)<=tick_size*0.51;
  }

bool VolumeMatches(const string symbol,const double left,const double right)
  {
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   return step>0.0 && MathAbs(left-right)<=step*0.1;
  }

bool PositionCurrencies(const string symbol,string &ccy1,string &ccy2)
  {
   for(int i=0;i<3;i++)
      if(g_sessions[i].symbol==symbol)
        {
         ccy1=g_sessions[i].ccy1;
         ccy2=g_sessions[i].ccy2;
         return true;
        }
   ccy1=StringSubstr(symbol,0,3);
   ccy2=StringSubstr(symbol,3,3);
   return StringLen(ccy1)==3 && StringLen(ccy2)==3;
  }

void ManageExposure()
  {
   // Research/dry mode must never issue any trade-server request, including a
   // seemingly protective close, delete, or stop modification.
   if(!InpEnableOrderSubmission)
      return;
   if(!AuthorizedAccountContext())
     {
      // Never issue cleanup requests after MT5 has switched away from the
      // explicitly authorized login/server. The old account must rely on its
      // visible exits until that exact context is restored and reconciled.
      Halt("runtime_account_context_changed");
      return;
     }
   if(!OwnsLiveInstanceLock())
     {
      Halt("live_instance_lock_not_owned");
      return;
     }
   datetime now=TimeTradeServer();

   if(HasForeignExposure())
     {
      Halt("manual_or_foreign_exposure");
      CancelAllPending("foreign_exposure_cleanup",true);
      CloseAllPositions("foreign_exposure_cleanup",true);
      return;
     }
   if(PendingEntryCount()>1 || PositionsTotal()>1 || (PendingEntryCount()>0 && PositionsTotal()>0))
     {
      Halt("multiple_or_overlapping_exposure");
      CancelAllPending("exposure_invariant",true);
      CloseAllPositions("exposure_invariant",true);
      return;
     }

   string guard_reason;
   if(!GlobalRiskGuards(guard_reason))
     {
      CancelAllPending(guard_reason,true);
      if(g_halted || guard_reason=="firm_overall_floor" || guard_reason=="firm_daily_floor" ||
         guard_reason=="internal_daily_stop" || guard_reason=="internal_weekly_stop" ||
         guard_reason=="strategy_drawdown_shutdown" || guard_reason=="phase_complete" ||
         guard_reason=="target_pending_days" || guard_reason=="payout_request_lock" ||
         guard_reason=="phase_transition_lock" || guard_reason=="scale_transition_lock" ||
         guard_reason=="external_cashflow_requires_rebaseline_release" ||
         guard_reason=="unauthorized_trading_history" || guard_reason=="audit_log_failure" ||
         guard_reason=="runtime_account_identity_mismatch")
         CloseAllPositions(guard_reason,true);
      if(!g_halted && RiskGuardRequiresPersistentHalt(guard_reason))
         Halt(guard_reason);
      return;
     }

   // Pending order controls.
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0) continue;
      string symbol=OrderGetString(ORDER_SYMBOL);
      datetime expiration=(datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
      string ccy1,ccy2;
      PositionCurrencies(symbol,ccy1,ccy2);
      MqlTick tick;
      bool quote_valid=SymbolInfoTick(symbol,tick) && TickIsFresh(tick);
      double entry=OrderGetDouble(ORDER_PRICE_OPEN);
      double sl=OrderGetDouble(ORDER_SL);
      double tp=OrderGetDouble(ORDER_TP);
      double volume=OrderGetDouble(ORDER_VOLUME_CURRENT);
      ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if((ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE)!=SYMBOL_TRADE_MODE_FULL)
        {
         DeleteOrder(ticket,"symbol_not_full_trade_mode",true);
         continue;
        }
      if(sl<=0.0 || tp<=0.0)
        {
         DeleteOrder(ticket,"pending_missing_visible_stop_or_target",true);
         Halt("pending_missing_visible_stop_or_target");
         continue;
        }
      double expected_entry,expected_sl,expected_tp,expected_volume;
      int expected_session;
      bool plan_match=LoadExpectedTradePlan(expected_entry,expected_sl,expected_tp,
                                            expected_volume,expected_session);
      double expected_expiry_value=0.0;
      plan_match=plan_match && GVRead("ExpectedExpiry",expected_expiry_value) &&
                 (datetime)(long)expected_expiry_value==expiration;
      if(plan_match)
        {
         bool expected_long=expected_sl<expected_entry;
         plan_match=((expected_long && type==ORDER_TYPE_BUY_LIMIT) ||
                     (!expected_long && type==ORDER_TYPE_SELL_LIMIT)) &&
                    (ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME)==ORDER_TIME_SPECIFIED &&
                    g_sessions[expected_session].symbol==symbol &&
                    PriceMatches(symbol,entry,expected_entry) &&
                    PriceMatches(symbol,sl,expected_sl) &&
                    PriceMatches(symbol,tp,expected_tp) &&
                    VolumeMatches(symbol,volume,expected_volume) &&
                    StringFind(OrderGetString(ORDER_COMMENT),"TRIAD|")==0;
        }
      if(!plan_match)
        {
         DeleteOrder(ticket,"pending_plan_mismatch",true);
         Halt("pending_plan_mismatch");
         continue;
        }
      double one_r=(type==ORDER_TYPE_BUY_LIMIT ? entry+(entry-sl) : entry-(sl-entry));
      if(expiration>0 && now>=expiration)
        { DeleteOrder(ticket,"expired",true); continue; }
      if(IsRelevantNewsWindow(ccy1,ccy2,now,InpNewsBlockMinutes))
        { DeleteOrder(ticket,"news_blackout",true); continue; }
      if(!quote_valid)
        { DeleteOrder(ticket,"stale_quote",true); continue; }
      if(type==ORDER_TYPE_BUY_LIMIT && tick.bid>=one_r)
        { DeleteOrder(ticket,"theoretical_1R_without_fill",true); continue; }
      if(type==ORDER_TYPE_SELL_LIMIT && tick.ask<=one_r)
        { DeleteOrder(ticket,"theoretical_1R_without_fill",true); continue; }
      for(int s=0;s<3;s++)
         if(g_sessions[s].symbol==symbol &&
            now+SAFETY_TIME_LEAD_SECONDS>=g_sessions[s].entry_end)
           { DeleteOrder(ticket,"session_end",true); break; }
     }

   // Position controls. One-position invariant has already been checked.
   if(PositionsTotal()==0)
      return;
   ulong ticket=PositionGetTicket(0);
   if(ticket==0) return;
   string symbol=PositionGetString(POSITION_SYMBOL);
   ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   datetime opened=(datetime)PositionGetInteger(POSITION_TIME);
   double open_price=PositionGetDouble(POSITION_PRICE_OPEN);
   double sl=PositionGetDouble(POSITION_SL);
   double tp=PositionGetDouble(POSITION_TP);
   double position_volume=PositionGetDouble(POSITION_VOLUME);
   string ccy1,ccy2;
   PositionCurrencies(symbol,ccy1,ccy2);

   double expected_entry,expected_sl,expected_tp,expected_volume;
   int expected_session;
   bool position_plan=LoadExpectedTradePlan(expected_entry,expected_sl,expected_tp,
                                            expected_volume,expected_session);
   if(position_plan)
     {
      double tick_size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
      if(tick_size<=0.0) tick_size=SymbolInfoDouble(symbol,SYMBOL_POINT);
      bool expected_long=expected_sl<expected_entry;
      bool side_matches=(expected_long && type==POSITION_TYPE_BUY) ||
                        (!expected_long && type==POSITION_TYPE_SELL);
      bool fill_not_worse=(type==POSITION_TYPE_BUY ? open_price<=expected_entry+tick_size*0.10
                                                  : open_price>=expected_entry-tick_size*0.10);
      position_plan=g_sessions[expected_session].symbol==symbol && side_matches && fill_not_worse &&
                    VolumeMatches(symbol,position_volume,expected_volume) &&
                    StringFind(PositionGetString(POSITION_COMMENT),"TRIAD|")==0;
     }
   if(!position_plan)
     {
      ClosePosition(ticket,"position_plan_mismatch",true);
      Halt("position_plan_mismatch");
      return;
     }

   if(sl<=0.0 || tp<=0.0)
     {
      bool repaired=false;
      if(expected_sl>0.0 && tp>0.0 && PriceMatches(symbol,tp,expected_tp))
        {
         if(SafetyRequestDue(ticket,"R",10,true))
           {
            CountTradeRequest("repair_missing_stop",true);
            bool repair_request=g_trade.PositionModify(ticket,expected_sl,tp) && TradeRetcodeAccepted(false);
            repaired=repair_request && PositionSelectByTicket(ticket) &&
                     PriceMatches(symbol,PositionGetDouble(POSITION_SL),expected_sl) &&
                     PriceMatches(symbol,PositionGetDouble(POSITION_TP),tp);
            if(repaired)
              {
               sl=PositionGetDouble(POSITION_SL);
               GlobalVariableDel(GVName("XR."+StringFormat("%I64u",ticket)));
              }
           }
        }
      if(!repaired)
        {
         ClosePosition(ticket,"missing_visible_stop_or_target",true);
         Halt("missing_visible_stop_or_target");
         return;
        }
     }

   double confirmed_value=0.0;
   bool one_r_was_confirmed=GVRead("OneRConfirmed",confirmed_value) && confirmed_value>0.5;
   bool original_stop=PriceMatches(symbol,sl,expected_sl);
   bool confirmed_breakeven=InpMoveStopToEntryAfter1R && one_r_was_confirmed &&
                            PriceMatches(symbol,sl,NormalizePriceToTick(symbol,open_price));
   if(!PriceMatches(symbol,tp,expected_tp) || (!original_stop && !confirmed_breakeven))
     {
      ClosePosition(ticket,"visible_exit_plan_mismatch",true);
      Halt("visible_exit_plan_mismatch");
      return;
     }

   datetime news_time;
   string news_title;
   if(UpcomingRelevantNews(ccy1,ccy2,now,InpNewsFlatMinutes,news_time,news_title))
     {
      ClosePosition(ticket,"pre_news_flat "+news_title,true);
      return;
     }
   if(RecentRelevantNews(ccy1,ccy2,now,InpNewsBlockMinutes))
     {
      ClosePosition(ticket,"post_news_recovery_flat",true);
      return;
     }

   datetime server_midnight=ServerMidnight(now)+86400;
   if(server_midnight-now<=InpRolloverFlatMinutes*60+SAFETY_TIME_LEAD_SECONDS)
     {
      ClosePosition(ticket,"pre_rollover_flat",true);
      return;
     }

   datetime utc_now=ServerToUtc(now);
   int ly,lm,ld,lkey;
   GetLocalDate(utc_now,SESSION_LONDON,ly,lm,ld,lkey);
   MqlDateTime lp;
   TimeToStruct(utc_now+LondonUtcOffsetSeconds(utc_now),lp);
   datetime friday_flat_utc=LocalWallToUtc(ly,lm,ld,20,0,SESSION_LONDON);
   if(lp.day_of_week==5 &&
      utc_now+SAFETY_TIME_LEAD_SECONDS>=friday_flat_utc)
     {
      ClosePosition(ticket,"friday_flat",true);
      return;
     }

   for(int s=0;s<3;s++)
      if(g_sessions[s].symbol==symbol &&
         now+SAFETY_TIME_LEAD_SECONDS>=g_sessions[s].entry_end)
        {
         ClosePosition(ticket,"session_flat",true);
         return;
        }

   double stop_distance=MathAbs(open_price-expected_sl);
   double raw_one_r=(type==POSITION_TYPE_BUY ? open_price+stop_distance
                                             : open_price-stop_distance);
   double expected_one_r=(type==POSITION_TYPE_BUY ? NormalizePriceUp(symbol,raw_one_r)
                                                  : NormalizePriceDown(symbol,raw_one_r));
   double stored_one_r=0.0;
   if(!GVRead("Expected1R",stored_one_r) || !PriceMatches(symbol,stored_one_r,expected_one_r))
     {
      if(!GVWrite("Expected1R",expected_one_r))
        {
         ClosePosition(ticket,"one_r_state_persistence_failure",true);
         Halt("one_r_state_persistence_failure");
         return;
        }
      GlobalVariablesFlush();
     }

   bool one_r_confirmed=one_r_was_confirmed;
   // Scan every completed post-fill M5 close, not only the latest one. This
   // reconstructs a missed confirmation after a disconnect or EA restart.
   if(!one_r_confirmed &&
      HasConfirmedOneRClose(symbol,opened,type,expected_one_r))
     {
      one_r_confirmed=true;
      if(!GVWrite("OneRConfirmed",1.0))
        {
         ClosePosition(ticket,"one_r_confirmation_persistence_failure",true);
         Halt("one_r_confirmation_persistence_failure");
         return;
        }
      GlobalVariablesFlush();
      LogEvent("INFO","ONE_R_CONFIRMED",StringFormat("position=%I64u level=%s",ticket,
               DoubleToString(expected_one_r,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS))));
     }

   if(InpMoveStopToEntryAfter1R && one_r_confirmed)
     {
      bool needs_move=(type==POSITION_TYPE_BUY ? sl<open_price : sl>open_price);
      if(needs_move)
        {
         double attempt_value=0.0;
         if(!GVRead("BreakEvenAttempts",attempt_value) || attempt_value<0.0)
           {
            Halt("breakeven_attempt_state_missing");
            return;
           }
         int attempts=(int)attempt_value;
         if(attempts>=2)
           {
            Halt("breakeven_retry_limit");
            return;
           }
         if(SafetyRequestDue(ticket,"B",60) && CanSendNonEmergencyRequest())
           {
            attempts++;
            if(!GVWrite("BreakEvenAttempts",attempts))
              {
               Halt("breakeven_attempt_persistence_failure");
               return;
              }
            GlobalVariablesFlush();
            if(!CountTradeRequest("move_stop_to_entry",false))
               return;
            double breakeven_stop=NormalizePriceToTick(symbol,open_price);
            bool modified=g_trade.PositionModify(ticket,breakeven_stop,tp) && TradeRetcodeAccepted(false);
            modified=modified && PositionSelectByTicket(ticket) &&
                     PriceMatches(symbol,PositionGetDouble(POSITION_SL),breakeven_stop) &&
                     PriceMatches(symbol,PositionGetDouble(POSITION_TP),tp);
            if(!modified)
              {
               uint code=g_trade.ResultRetcode();
               LogEvent("ERROR","BREAKEVEN_MODIFY_FAILED",
                        StringFormat("attempt=%d ret=%u %s",attempts,code,
                                     g_trade.ResultRetcodeDescription()));
               if(!TransientTradeRetcode(code) || attempts>=2)
                 {
                  if(attempts<2)
                    {
                     if(!GVWrite("BreakEvenAttempts",2.0))
                       {
                        Halt("breakeven_attempt_persistence_failure");
                        return;
                       }
                     GlobalVariablesFlush();
                    }
                  Halt("breakeven_modify_failed");
                 }
               else
                  LogEvent("WARN","BREAKEVEN_RETRY_ARMED","one revalidated retry remains");
              }
           }
        }
     }

   if(InpTimeStopMinutes>0 && now-opened>=InpTimeStopMinutes*60 && !one_r_confirmed)
     {
      ClosePosition(ticket,"time_stop_no_confirmed_1R",true);
      return;
     }
  }

// ============================================================================
// Rollover, account validation, and scan loop
// ============================================================================

bool MissedRolloverExposure(bool &history_ok)
  {
   history_ok=false;
   datetime now=TimeTradeServer();
   datetime from=(g_state_created_time>1 ? g_state_created_time-1 : 0);
   if(!HistorySelect(from,now))
      return false;
   history_ok=true;

   // A pending entry that was created on one server day and completed on a
   // later day was necessarily working across at least one rollover.
   for(int i=0;i<HistoryOrdersTotal();i++)
     {
      ulong order=HistoryOrderGetTicket(i);
      if(order==0 || HistoryOrderGetInteger(order,ORDER_MAGIC)!=InpMagic)
         continue;
      ENUM_ORDER_TYPE order_type=(ENUM_ORDER_TYPE)HistoryOrderGetInteger(order,ORDER_TYPE);
      if(!IsPendingEntryType(order_type))
         continue;
      datetime setup=(datetime)HistoryOrderGetInteger(order,ORDER_TIME_SETUP);
      datetime done=(datetime)HistoryOrderGetInteger(order,ORDER_TIME_DONE);
      if(setup>0 && done>g_day_start_time &&
         ServerDayKey(setup)!=ServerDayKey(done))
         return true;
     }

   // Reconstruct strategy position lifetimes. Exit magic/comment can differ for
   // broker SL/TP or manual emergency closure, so exits are linked by position
   // identifier after an authorized TRIAD entry has established ownership.
   long position_ids[];
   datetime entry_times[];
   datetime exit_times[];
   ArrayResize(position_ids,0);
   ArrayResize(entry_times,0);
   ArrayResize(exit_times,0);
   int total=HistoryDealsTotal();
   for(int i=0;i<total;i++)
     {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0 || HistoryDealGetInteger(deal,DEAL_MAGIC)!=InpMagic)
         continue;
      ENUM_DEAL_TYPE deal_type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE);
      ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
      if((deal_type!=DEAL_TYPE_BUY && deal_type!=DEAL_TYPE_SELL) || entry!=DEAL_ENTRY_IN ||
         StringFind(HistoryDealGetString(deal,DEAL_COMMENT),"TRIAD|")!=0)
         continue;
      long position_id=HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      datetime deal_time=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
      int found=-1;
      for(int j=0;j<ArraySize(position_ids);j++)
         if(position_ids[j]==position_id) { found=j; break; }
      if(found<0)
        {
         int n=ArraySize(position_ids);
         ArrayResize(position_ids,n+1);
         ArrayResize(entry_times,n+1);
         ArrayResize(exit_times,n+1);
         position_ids[n]=position_id;
         entry_times[n]=deal_time;
         exit_times[n]=0;
        }
      else if(deal_time<entry_times[found])
         entry_times[found]=deal_time;
     }
   for(int i=0;i<total;i++)
     {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0) continue;
      ENUM_DEAL_TYPE deal_type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE);
      ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
      if((deal_type!=DEAL_TYPE_BUY && deal_type!=DEAL_TYPE_SELL) ||
         (entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY))
         continue;
      long position_id=HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      for(int j=0;j<ArraySize(position_ids);j++)
         if(position_ids[j]==position_id)
           {
            datetime deal_time=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
            if(deal_time>exit_times[j]) exit_times[j]=deal_time;
            break;
           }
     }
   for(int i=0;i<ArraySize(position_ids);i++)
      if(exit_times[i]>g_day_start_time &&
         ServerDayKey(entry_times[i])!=ServerDayKey(exit_times[i]))
         return true;
   return false;
  }

void ProcessRollover()
  {
   datetime now=TimeTradeServer();
   int key=ServerDayKey(now);
   if(g_server_day_key==0)
      g_server_day_key=key;
   if(key==g_server_day_key)
      return;
   if(now<=0 || key<g_server_day_key || (g_day_start_time>0 && now<g_day_start_time))
     {
      Halt("server_day_regression");
      return;
     }
   // A cashflow or unauthorized-history incident invalidates the existing
   // accounting basis. Do not migrate that contaminated balance into a new
   // daily/weekly/high-water journal; a separately approved rebaseline is
   // required.
   if(g_external_cashflow_detected || g_account_history_fault)
      return;

   bool rollover_history_ok=false;
   bool missed_rollover_exposure=MissedRolloverExposure(rollover_history_ok);
   if(!rollover_history_ok)
     {
      Halt("rollover_history_unavailable");
      return;
     }
   bool rollover_incident=(g_rollover_incident_key==key || missed_rollover_exposure);
   if(missed_rollover_exposure)
     {
      g_rollover_incident_key=key;
      if(!GVWrite("RollIncident",g_rollover_incident_key) ||
         !GVWrite("StateSig",AccountStateSignature()))
         Halt("rollover_incident_persistence_failure");
      GlobalVariablesFlush();
      // Historical deals cannot reconstruct the exact equity sampled at the
      // missed midnight, so the official daily floor cannot be safely inferred.
      RequireStateMigration("missed_rollover_exposure");
      Halt("missed_rollover_exposure");
     }
   double rollover_floor_base=0.0;
   if(HasAnyExposure())
     {
      // Preserve the higher balance/equity observed at the boundary for the
      // official daily floor even though the flat operating snapshot must be
      // deferred until cleanup completes.
      rollover_floor_base=MathMax(AccountInfoDouble(ACCOUNT_BALANCE),
                                  AccountInfoDouble(ACCOUNT_EQUITY));
      rollover_incident=true;
      g_rollover_incident_key=key;
      g_firm_daily_floor=MathMax(g_firm_daily_floor,rollover_floor_base*0.95);
      if(!GVWrite("RollIncident",g_rollover_incident_key) ||
         !GVWrite("DailyFloor",g_firm_daily_floor) ||
         !GVWrite("StateSig",AccountStateSignature()))
         Halt("rollover_incident_persistence_failure");
      GlobalVariablesFlush();
      RequireStateMigration("unexpected_rollover_exposure");
      Halt("unexpected_rollover_exposure");
      CancelAllPending("rollover_exposure",true);
      CloseAllPositions("rollover_exposure",true);
      // Never snapshot a pre-close balance/equity as the new day. If any
      // exposure remains (including foreign exposure), retry safety management
      // and defer rollover state creation.
      if(HasAnyExposure())
         return;
     }

   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(rollover_incident)
      LogEvent("WARN","PROFITABLE_DAY_NOT_ESTIMATED",
               "rollover exposure incident; dashboard reconciliation required");
   else if(g_previous_day_balance>0.0)
     {
      if(g_day_start_time>0 && now-g_day_start_time<=36*3600)
        {
         double result=MathMin(balance,equity)-g_previous_day_balance;
         double threshold=InpPhaseInitialBalance*0.005;
         if(result+0.0000001>=threshold)
           {
            g_estimated_profitable_days++;
            LogEvent("INFO","ESTIMATED_PROFITABLE_DAY",StringFormat("result=%.2f count=%d",result,g_estimated_profitable_days));
           }
         else
            LogEvent("INFO","DAY_NOT_QUALIFYING",StringFormat("result=%.2f threshold=%.2f",result,threshold));
        }
      else
         LogEvent("WARN","PROFITABLE_DAY_NOT_ESTIMATED","EA was offline across more than one rollover; dashboard reconciliation required");
     }

   g_server_day_key=key;
   g_rollover_incident_key=0;
   g_day_start_time=ServerMidnight(now);
   g_day_start_balance=balance;
   g_day_start_equity=equity;
   g_previous_day_balance=balance;
   double reconciled_daily_floor=MathMax(balance,equity)*0.95;
   if(rollover_incident)
      reconciled_daily_floor=MathMax(reconciled_daily_floor,g_firm_daily_floor);
   g_firm_daily_floor=reconciled_daily_floor;
   g_request_count=0;
   int new_week=ServerWeekKey(now);
   if(new_week!=g_week_key)
     {
      g_week_key=new_week;
      g_week_start_balance=balance;
     }
   g_news_valid=LoadNewsCalendar();
   if(InpRequireNewsCalendar && !g_news_valid)
      LogEvent("WARN","NEWS_RELOAD_FAIL_CLOSED","new entries disabled");
   if(!PersistAccountState())
      Halt("state_persistence_failure");
  }

void UpdateHighWater()
  {
   if(g_halted || g_external_cashflow_detected || g_account_history_fault || HasAnyExposure())
      return;
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance>g_high_water_balance)
     {
      g_high_water_balance=balance;
      if(!GVWrite("HighWater",g_high_water_balance) ||
         !GVWrite("StateSig",AccountStateSignature()))
         Halt("high_water_persistence_failure");
      GlobalVariablesFlush();
     }
  }

bool NearlyEqual(const double left,const double right,const double tolerance=1e-9)
  {
   return MathAbs(left-right)<=tolerance;
  }

bool ValidateInputs()
  {
   if((int)InpPhase<(int)TRIAD_PHASE_1 || (int)InpPhase>(int)TRIAD_FUNDED)
     { LogEvent("ERROR","INPUT_PHASE","unsupported phase"); return false; }
   if((int)InpLifecycleLock<(int)LIFECYCLE_ACTIVE ||
      (int)InpLifecycleLock>(int)LIFECYCLE_SCALE_TRANSITION)
     { LogEvent("ERROR","INPUT_LIFECYCLE_LOCK","unsupported lifecycle lock"); return false; }
   if((int)InpProfile<(int)PROFILE_A_040_R150 || (int)InpProfile>(int)PROFILE_D_025_R250)
     { LogEvent("ERROR","INPUT_PROFILE","unsupported profile"); return false; }
   if(InpExpectedAccountCurrency!="USD")
     { LogEvent("ERROR","INPUT_ACCOUNT_CURRENCY","New High Stakes $2,500 profile must remain USD"); return false; }
   if(InpExpectedAccountLeverage!=100)
     { LogEvent("ERROR","INPUT_ACCOUNT_LEVERAGE","New High Stakes requires the verified 1:100 profile"); return false; }
   if(InpMagic<=0 || InpNewsCsvFile=="" || InpLogFilePrefix=="")
     { LogEvent("ERROR","INPUT_ID_OR_FILES","magic and runtime filenames must be nonempty"); return false; }
   if(InpDashboardConfirmedDays<0)
     { LogEvent("ERROR","INPUT_DASHBOARD_DAYS","must be nonnegative"); return false; }
   bool range_ok=(NearlyEqual(InpRangePercentileLow,30.0) && NearlyEqual(InpRangePercentileHigh,80.0)) ||
                 (NearlyEqual(InpRangePercentileLow,35.0) && NearlyEqual(InpRangePercentileHigh,75.0));
   bool atr_ok=(NearlyEqual(InpAtrPercentileLow,20.0) && NearlyEqual(InpAtrPercentileHigh,80.0)) ||
               (NearlyEqual(InpAtrPercentileLow,25.0) && NearlyEqual(InpAtrPercentileHigh,75.0));
   if(!range_ok || !atr_ok || InpComparableSessions!=60)
     { LogEvent("ERROR","INPUT_RESEARCH_BANDS","only canonical offline candidates and 60 sessions are allowed"); return false; }
   if(InpTimeStopMinutes!=0 && InpTimeStopMinutes!=30 && InpTimeStopMinutes!=45 &&
      InpTimeStopMinutes!=60 && InpTimeStopMinutes!=90)
     { LogEvent("ERROR","INPUT_TIME_STOP","allowed: 0,30,45,60,90"); return false; }
   if(!NearlyEqual(InpSweepAtrMin,0.05) || !NearlyEqual(InpSweepAtrMax,0.50) ||
      InpReclaimBars!=3 || !NearlyEqual(InpReclaimWickMin,0.60) ||
      !NearlyEqual(InpDisplacementBodyMin,0.60) || InpLimitExpiryBars!=3 ||
      !NearlyEqual(InpStopBufferAtr,0.10) || !NearlyEqual(InpStopAtrMin,0.60) ||
      !NearlyEqual(InpStopAtrMax,1.50))
     { LogEvent("ERROR","INPUT_ENTRY_CONTRACT","fixed revision 2.1 entry contract changed"); return false; }
   if(!NearlyEqual(InpMaxCostToR,0.10) || !NearlyEqual(InpSpreadMedianMultiplier,1.50) ||
      InpCommissionRoundTripPerLot<4.0 || InpStopSlippageReservePoints<10 ||
      InpTargetSlippageReservePoints<5)
     { LogEvent("ERROR","INPUT_COST_CONTRACT","cost assumptions are weaker than the canonical defaults"); return false; }
   if(InpExpectedServerUtcOffsetHours!=3 || InpNewsBlockMinutes!=30 ||
      InpNewsFlatMinutes!=15 || InpRolloverFlatMinutes!=15 ||
      InpRequiredNewsCoverageHours<24 || InpRequiredNewsCoverageHours>720 ||
      InpMaxQuoteAgeSeconds<=0 ||
      InpMaxQuoteAgeSeconds>10 || InpMaxDeviationPoints<0 || InpMaxDeviationPoints>20 ||
      InpMaxTradeRequestLatencyMs<=0 || InpMaxTradeRequestLatencyMs>1000 ||
      InpMaxNonEmergencyRequestsDay<=0 || InpMaxNonEmergencyRequestsDay>20 ||
      !InpSkipFreshMidSessionStart)
     { LogEvent("ERROR","INPUT_OPERATIONAL_CONTRACT","calendar, quote, or request safety changed"); return false; }
   if(InpFirmFloorReservePercent<0.50 || InpInternalDailyStopPercent<=0.0 ||
      InpInternalDailyStopPercent>1.0 || InpInternalWeeklyStopPercent<=0.0 ||
      InpInternalWeeklyStopPercent>2.0 || !NearlyEqual(InpDrawdownReducePercent,2.0) ||
      !NearlyEqual(InpDrawdownShutdownPercent,5.0))
     { LogEvent("ERROR","INPUT_RISK_CONTRACT","risk governor is outside revision 2.1"); return false; }
   if(InpEURUSDSymbol==InpGBPUSDSymbol || InpEURUSDSymbol==InpUSDJPYSymbol ||
      InpGBPUSDSymbol==InpUSDJPYSymbol ||
      (!InpEnableEURUSDLondon && !InpEnableGBPUSDLondon && !InpEnableUSDJPYNewYork))
     { LogEvent("ERROR","INPUT_SYMBOLS","symbols must be unique and at least one sleeve enabled"); return false; }
   if(InpEURUSDLondonPriority<1 || InpEURUSDLondonPriority>3 ||
      InpGBPUSDLondonPriority<1 || InpGBPUSDLondonPriority>3 ||
      InpUSDJPYNewYorkPriority<1 || InpUSDJPYNewYorkPriority>3)
     { LogEvent("ERROR","INPUT_COLLISION_PRIORITY","locked priorities must be in the range 1..3"); return false; }
   if(InpEnableOrderSubmission && !InpRequireNewsCalendar)
     { LogEvent("ERROR","INPUT_NEWS_FAIL_OPEN","live order mode requires the calendar"); return false; }
   return true;
  }

bool ValidateReleaseGates()
  {
   if(!InpEnableOrderSubmission || IsTesterMode())
      return true;
   if(InpValidationReleaseId=="" || InpValidationReleaseId=="LOCKED" || StringLen(InpValidationReleaseId)<8)
     { LogEvent("ERROR","VALIDATION_RELEASE_LOCKED","a traceable approved release ID is required"); return false; }
   if(!InpStatisticalGatePassed || !InpStressGatePassed || !InpOperationalGatePassed ||
      !InpExternalRulesGatePassed || !InpAccountSpecificGatePassed ||
      !InpForwardDemoGatePassed || !InpCompilationGatePassed || !InpExplicitUserApproval)
     { LogEvent("ERROR","VALIDATION_GATES_INCOMPLETE","all revision 2.1 release attestations must be true"); return false; }
   if((InpEnableEURUSDLondon && !InpEURUSDLondonGatePassed) ||
      (InpEnableGBPUSDLondon && !InpGBPUSDLondonGatePassed) ||
      (InpEnableUSDJPYNewYork && !InpUSDJPYNewYorkGatePassed))
     { LogEvent("ERROR","COMBINATION_GATE_INCOMPLETE","every enabled symbol/session requires independent approval"); return false; }
   return true;
  }

bool ValidateSymbolContracts()
  {
   string expected_base[3];
   string expected_profit[3];
   string symbols[3];
   bool enabled[3];
   expected_base[0]="EUR"; expected_base[1]="GBP"; expected_base[2]="USD";
   expected_profit[0]="USD"; expected_profit[1]="USD"; expected_profit[2]="JPY";
   symbols[0]=InpEURUSDSymbol; symbols[1]=InpGBPUSDSymbol; symbols[2]=InpUSDJPYSymbol;
   enabled[0]=InpEnableEURUSDLondon; enabled[1]=InpEnableGBPUSDLondon; enabled[2]=InpEnableUSDJPYNewYork;
   for(int i=0;i<3;i++)
     {
      if(!enabled[i]) continue;
      if(!SymbolSelect(symbols[i],true))
        { LogEvent("ERROR","SYMBOL_SELECT",symbols[i]); return false; }
      if(SymbolInfoString(symbols[i],SYMBOL_CURRENCY_BASE)!=expected_base[i] ||
         SymbolInfoString(symbols[i],SYMBOL_CURRENCY_PROFIT)!=expected_profit[i])
        { LogEvent("ERROR","SYMBOL_CURRENCY_MAP",symbols[i]); return false; }
      if(SymbolInfoDouble(symbols[i],SYMBOL_POINT)<=0.0 ||
         SymbolInfoDouble(symbols[i],SYMBOL_TRADE_TICK_SIZE)<=0.0 ||
         SymbolInfoDouble(symbols[i],SYMBOL_TRADE_TICK_VALUE_LOSS)<=0.0 ||
         SymbolInfoDouble(symbols[i],SYMBOL_TRADE_TICK_VALUE_PROFIT)<=0.0 ||
         SymbolInfoDouble(symbols[i],SYMBOL_TRADE_CONTRACT_SIZE)<=0.0 ||
         SymbolInfoDouble(symbols[i],SYMBOL_VOLUME_MIN)<=0.0 ||
         SymbolInfoDouble(symbols[i],SYMBOL_VOLUME_MAX)<
            SymbolInfoDouble(symbols[i],SYMBOL_VOLUME_MIN) ||
         SymbolInfoDouble(symbols[i],SYMBOL_VOLUME_STEP)<=0.0)
        { LogEvent("ERROR","SYMBOL_PROPERTIES",symbols[i]); return false; }
      long order_mode=SymbolInfoInteger(symbols[i],SYMBOL_ORDER_MODE);
      long expiration_mode=SymbolInfoInteger(symbols[i],SYMBOL_EXPIRATION_MODE);
      if((order_mode & SYMBOL_ORDER_LIMIT)==0 || (order_mode & SYMBOL_ORDER_SL)==0 ||
         (order_mode & SYMBOL_ORDER_TP)==0 ||
         (expiration_mode & SYMBOL_EXPIRATION_SPECIFIED)==0)
        { LogEvent("ERROR","SYMBOL_ORDER_CAPABILITIES",symbols[i]); return false; }
     }
   return true;
  }

bool ValidateServerOffset()
  {
   if(IsTesterMode()) return true;
   datetime gmt=TimeGMT();
   datetime server=TimeTradeServer();
   if(gmt<=0 || server<=0) return false;
   long observed_seconds=(long)(server-gmt);
   long expected_seconds=(long)InpExpectedServerUtcOffsetHours*3600;
   long error_seconds=observed_seconds-expected_seconds;
   if(error_seconds<0) error_seconds=-error_seconds;
   if(error_seconds>SERVER_OFFSET_TOLERANCE_SECONDS)
     {
      LogEvent("ERROR","SERVER_OFFSET_MISMATCH",
               StringFormat("expected_seconds=%I64d observed_seconds=%I64d tolerance=%d",
                            expected_seconds,observed_seconds,SERVER_OFFSET_TOLERANCE_SECONDS));
      return false;
     }
   return true;
  }

bool ValidateAccountIdentity()
  {
   if(InpRequiredProductCode!="HS_NEW_2500")
     {
      LogEvent("ERROR","PRODUCT_CODE",InpRequiredProductCode);
      return false;
     }
   if((InpPhase==TRIAD_PHASE_1 || InpPhase==TRIAD_PHASE_2) &&
      MathAbs(InpPhaseInitialBalance-2500.0)>0.01)
     {
      LogEvent("ERROR","INITIAL_BALANCE_CONFIG",DoubleToString(InpPhaseInitialBalance,2));
      return false;
     }
   if(InpPhase==TRIAD_FUNDED && InpPhaseInitialBalance<=0.0)
     {
      LogEvent("ERROR","FUNDED_INITIAL_BALANCE_CONFIG",DoubleToString(InpPhaseInitialBalance,2));
      return false;
     }
   if(IsTesterMode() || !InpEnableOrderSubmission)
      return true;
   long login=AccountInfoInteger(ACCOUNT_LOGIN);
   if(InpAuthorizedLogin<=0 || login!=InpAuthorizedLogin)
     {
      LogEvent("ERROR","LOGIN_NOT_AUTHORIZED",StringFormat("configured=%I64d actual=%I64d",InpAuthorizedLogin,login));
      return false;
     }
   if(InpExpectedAccountServer=="" || AccountInfoString(ACCOUNT_SERVER)!=InpExpectedAccountServer)
     {
      LogEvent("ERROR","ACCOUNT_SERVER",AccountInfoString(ACCOUNT_SERVER));
      return false;
     }
   if(AccountInfoString(ACCOUNT_CURRENCY)!=InpExpectedAccountCurrency)
     {
      LogEvent("ERROR","ACCOUNT_CURRENCY",AccountInfoString(ACCOUNT_CURRENCY));
      return false;
     }
   if((int)AccountInfoInteger(ACCOUNT_LEVERAGE)!=InpExpectedAccountLeverage)
     {
      LogEvent("ERROR","ACCOUNT_LEVERAGE",StringFormat("expected=%d actual=%I64d",
               InpExpectedAccountLeverage,AccountInfoInteger(ACCOUNT_LEVERAGE)));
      return false;
     }
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      LogEvent("ERROR","ACCOUNT_MARGIN_MODE","hedging account required");
      return false;
     }
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_EXPERT) ||
      !TerminalInfoInteger(TERMINAL_CONNECTED) || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||
      !MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      LogEvent("ERROR","AUTOTRADING_NOT_ALLOWED","terminal disconnected or account/terminal/program trading permission disabled");
      return false;
     }
   if(!ValidateServerOffset())
      return false;
   return true;
  }

long LatestHistoryDealTimeMsc()
  {
   if(!HistorySelect(0,TimeTradeServer()))
      return -1;
   long latest=0;
   for(int i=0;i<HistoryDealsTotal();i++)
     {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0) continue;
      long deal_msc=HistoryDealGetInteger(deal,DEAL_TIME_MSC);
      if(deal_msc>latest) latest=deal_msc;
     }
   return latest;
  }

bool HasTradingHistory()
  {
   if(!HistorySelect(0,TimeTradeServer()))
      return true;
   if(HistoryOrdersTotal()>0)
      return true;
   for(int i=0;i<HistoryDealsTotal();i++)
     {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0) continue;
      ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE);
      if(type==DEAL_TYPE_BUY || type==DEAL_TYPE_SELL)
         return true;
     }
   return false;
  }

bool LoadOrCreateAccountState()
  {
   double stored_cfg=0.0,stored_initial=0.0;
   bool exists=GVRead("Cfg",stored_cfg);
   if(!exists)
     {
      if(InpAuthorizeHaltReset)
        {
         LogEvent("ERROR","HALT_RESET_WITHOUT_STATE","halt-reset authorization is not a fresh-state control");
         return false;
        }
      if(InpEnableOrderSubmission && !IsTesterMode() && !InpAuthorizeFreshPhaseState)
        {
         LogEvent("ERROR","FRESH_STATE_NOT_AUTHORIZED","set InpAuthorizeFreshPhaseState once after account verification");
         return false;
        }
      datetime now=TimeTradeServer();
      double balance=AccountInfoDouble(ACCOUNT_BALANCE);
      double equity=AccountInfoDouble(ACCOUNT_EQUITY);
      if(InpEnableOrderSubmission && !IsTesterMode())
        {
         if(HasAnyExposure() || HasTradingHistory() || MathAbs(balance-InpPhaseInitialBalance)>0.01 ||
            MathAbs(equity-InpPhaseInitialBalance)>0.01)
           {
            LogEvent("ERROR","FRESH_STATE_ACCOUNT_NOT_CLEAN",
                     StringFormat("balance=%.2f equity=%.2f exposure=%s history=%s",balance,equity,
                                  BoolText(HasAnyExposure()),BoolText(HasTradingHistory())));
            return false;
           }
        }
      g_server_day_key=ServerDayKey(now);
      g_week_key=ServerWeekKey(now);
      g_day_start_time=ServerMidnight(now);
      g_day_start_balance=balance;
      g_day_start_equity=equity;
      g_week_start_balance=balance;
      g_previous_day_balance=balance;
      g_firm_daily_floor=MathMax(balance,equity)*0.95;
      g_high_water_balance=balance;
      g_estimated_profitable_days=0;
      g_request_count=0;
      g_rollover_incident_key=0;
      g_rebaseline_required=false;
      g_history_baseline_msc=LatestHistoryDealTimeMsc();
      if(g_history_baseline_msc<0)
        {
         LogEvent("ERROR","HISTORY_BASELINE_FAILED","cannot establish external-cashflow baseline");
         return false;
        }
      g_state_created_time=now;
      g_last_inactivity_alert_day=0;
      if(!PersistAccountState())
         return false;
      LogEvent("INFO","STATE_CREATED",StringFormat("balance=%.2f",balance));
      if(g_log_failure)
        {
         Halt("audit_log_failure_during_state_creation");
         return false;
        }
      if(InpEnableOrderSubmission && !IsTesterMode())
        {
         LogEvent("WARN","FRESH_STATE_AUTHORIZATION_CONSUMED","return authorization input to false and reattach");
         if(g_log_failure)
            Halt("audit_log_failure_during_state_creation");
         return false;
        }
      return true;
     }
   if(InpAuthorizeFreshPhaseState)
     {
      LogEvent("ERROR","FRESH_STATE_AUTHORIZATION_NOT_REQUIRED","return one-time authorization input to false");
      return false;
     }
   if((int)stored_cfg!=g_config_hash)
     {
      LogEvent("ERROR","CONFIG_HASH_MISMATCH",StringFormat("stored=%d current=%d",(int)stored_cfg,g_config_hash));
      return false;
     }
   double stored_identity;
   if(!GVRead("Identity",stored_identity) || (int)stored_identity!=RuntimeIdentityHash())
     {
      LogEvent("ERROR","PERSISTED_IDENTITY_MISMATCH","login/server/currency/product/phase mismatch");
      return false;
     }
   if(!GVRead("Initial",stored_initial) || MathAbs(stored_initial-InpPhaseInitialBalance)>0.01)
     {
      LogEvent("ERROR","PERSISTED_INITIAL_MISMATCH",DoubleToString(stored_initial,2));
      return false;
     }
   double halt_value=0.0,halt_reason_hash=0.0,rebaseline_required=0.0;
   if(!ReadHaltLatch(halt_value,halt_reason_hash))
     {
      LogEvent("ERROR","PERSISTED_HALT_SIGNATURE_MISMATCH",
               "halt latch is missing, invalid, partially written, or changed");
      return false;
     }
   if(!GVRead("Rebase",rebaseline_required))
     {
      LogEvent("ERROR","PERSISTED_STATE_INCOMPLETE","missing migration latch");
      return false;
     }
   if(rebaseline_required>0.5)
     {
      LogEvent("ERROR","PERSISTED_STATE_MIGRATION_LOCK",
               "ordinary halt reset is prohibited; use a separately reviewed migration release");
      return false;
     }
   if(!NearlyEqual(rebaseline_required,0.0) ||
      (!NearlyEqual(halt_value,0.0) && !NearlyEqual(halt_value,1.0)))
     {
      LogEvent("ERROR","PERSISTED_STATE_INCOMPLETE","halt or migration latch has an invalid value");
      return false;
     }
   if(halt_value>0.5)
     {
      if(!InpAuthorizeHaltReset || HasAnyExposure())
        {
         LogEvent("ERROR","PERSISTED_HALT_LOCK","formal revalidation and one-time halt-reset authorization required");
         return false;
        }
      bool reset_saved=WriteHaltLatch(0.0,0.0);
      GlobalVariablesFlush();
      if(!reset_saved)
        {
         LogEvent("ERROR","PERSISTED_HALT_RESET_FAILED","terminal state was not fully updated");
         return false;
        }
      LogEvent("WARN","PERSISTED_HALT_RESET","reset consumed; return authorization input to false and reattach");
      return false;
     }
   if(InpAuthorizeHaltReset)
     {
      LogEvent("ERROR","HALT_RESET_NOT_REQUIRED","return one-time authorization input to false");
      return false;
     }

   double day_key=0.0,day_start=0.0,day_balance=0.0,day_equity=0.0;
   double week_key=0.0,week_balance=0.0,previous_balance=0.0,daily_floor=0.0;
   double high_water=0.0,profit_days=0.0,request_count=0.0,rollover_incident=0.0;
   double history_base=0.0,state_created=0.0,inactivity_alert=0.0,state_signature=0.0;
   bool complete=GVRead("DayKey",day_key) && GVRead("DayStartT",day_start) &&
                 GVRead("DayBal",day_balance) && GVRead("DayEq",day_equity) &&
                 GVRead("WeekKey",week_key) && GVRead("WeekBal",week_balance) &&
                 GVRead("PrevBal",previous_balance) && GVRead("DailyFloor",daily_floor) &&
                 GVRead("HighWater",high_water) && GVRead("ProfitDays",profit_days) &&
                 GVRead("ReqCount",request_count) && GVRead("RollIncident",rollover_incident) &&
                 GVRead("HistoryBaseMs",history_base) && GVRead("CreatedT",state_created) &&
                 GVRead("InactAlert",inactivity_alert) && GVRead("StateSig",state_signature);
   if(!complete || day_key<=0.0 || day_start<=0.0 || day_balance<=0.0 || day_equity<=0.0 ||
      week_key<=0.0 || week_balance<=0.0 || previous_balance<=0.0 || daily_floor<=0.0 ||
      high_water<=0.0 || profit_days<0.0 || request_count<0.0 ||
      history_base<0.0 || state_created<=0.0)
     {
      LogEvent("ERROR","PERSISTED_STATE_INCOMPLETE","required field missing or outside valid range");
      return false;
     }
   g_server_day_key=(int)day_key;
   g_day_start_time=(datetime)(long)day_start;
   g_day_start_balance=day_balance;
   g_day_start_equity=day_equity;
   g_week_key=(int)week_key;
   g_week_start_balance=week_balance;
   g_previous_day_balance=previous_balance;
   g_firm_daily_floor=daily_floor;
   g_high_water_balance=high_water;
   g_estimated_profitable_days=(int)profit_days;
   g_request_count=(int)request_count;
   g_rollover_incident_key=(int)rollover_incident;
   g_history_baseline_msc=(long)history_base;
   g_rebaseline_required=(rebaseline_required>0.5);
   g_state_created_time=(datetime)(long)state_created;
   g_last_inactivity_alert_day=(int)inactivity_alert;
   if((int)state_signature!=AccountStateSignature())
     {
      LogEvent("ERROR","PERSISTED_STATE_SIGNATURE_MISMATCH",
               "partial, stale, or internally inconsistent account state");
      return false;
     }
   return true;
  }

void InitializeSessions()
  {
   g_sessions[0].id="LON_EURUSD";
   g_sessions[0].symbol=InpEURUSDSymbol;
   g_sessions[0].ccy1="EUR";
   g_sessions[0].ccy2="USD";
   g_sessions[0].kind=SESSION_LONDON;
   g_sessions[0].enabled=InpEnableEURUSDLondon;
   g_sessions[0].priority=InpEURUSDLondonPriority;

   g_sessions[1].id="LON_GBPUSD";
   g_sessions[1].symbol=InpGBPUSDSymbol;
   g_sessions[1].ccy1="GBP";
   g_sessions[1].ccy2="USD";
   g_sessions[1].kind=SESSION_LONDON;
   g_sessions[1].enabled=InpEnableGBPUSDLondon;
   g_sessions[1].priority=InpGBPUSDLondonPriority;

   g_sessions[2].id="NY_USDJPY";
   g_sessions[2].symbol=InpUSDJPYSymbol;
   g_sessions[2].ccy1="USD";
   g_sessions[2].ccy2="JPY";
   g_sessions[2].kind=SESSION_NEW_YORK;
   g_sessions[2].enabled=InpEnableUSDJPYNewYork;
   g_sessions[2].priority=InpUSDJPYNewYorkPriority;

   for(int i=0;i<3;i++)
     {
      g_sessions[i].local_day_key=0;
      g_sessions[i].range_ready=false;
      g_sessions[i].range_warning_logged=false;
      g_sessions[i].consumed=false;
      g_sessions[i].last_closed_bar=0;
      g_atr_handles[i]=INVALID_HANDLE;
      if(!g_sessions[i].enabled) continue;
      if(!SymbolSelect(g_sessions[i].symbol,true))
        {
         Halt("symbol_select_failed_"+g_sessions[i].symbol);
         continue;
        }
      g_atr_handles[i]=iATR(g_sessions[i].symbol,PERIOD_M15,14);
      if(g_atr_handles[i]==INVALID_HANDLE)
         Halt("atr_handle_failed_"+g_sessions[i].symbol);
     }
  }

void ScanForSignals()
  {
   if(g_halted || HasAnyExposure()) return;
   string reason;
   if(!GlobalRiskGuards(reason))
     {
      if(RiskGuardRequiresPersistentHalt(reason)) Halt(reason);
      return;
     }
   if(!DailyStateAllowsEntry(reason))
     {
      if(reason=="manual_or_foreign_deal_detected") Halt(reason);
      return;
     }
   if(!NewsCalendarCurrent())
      return;

   datetime now=TimeTradeServer();
   SignalCandidate candidates[3];
   int valid_indices[];
   ArrayResize(valid_indices,0);

   for(int i=0;i<3;i++)
     {
      if(!g_sessions[i].enabled) continue;
      if(!RefreshSession(i,now)) continue;
      if(g_sessions[i].consumed || !g_sessions[i].range_ready) continue;
      if(now<g_sessions[i].entry_start ||
         now+SAFETY_TIME_LEAD_SECONDS>=g_sessions[i].entry_end) continue;

      SignalCandidate candidate;
      if(!DetectPattern(i,candidate) || !candidate.detected)
        {
         if(candidate.signal_bar_time>0)
            LogEvent("INFO","NO_COMPLETED_EVENT",
                     g_sessions[i].id+" reason="+candidate.rejection+" bar="+
                     TimeToString(candidate.signal_bar_time,TIME_DATE|TIME_MINUTES));
         continue;
        }

      // One detected event consumes this symbol/session for the civil day,
      // regardless of a later gate rejection.
      g_sessions[i].consumed=true;
      PersistSessionConsumed(i);
      bool prepared=(candidate.rejection=="" && PrepareCandidate(candidate));
      candidates[i]=candidate;
      if(!prepared)
        {
         LogEvent("INFO","CANDIDATE_REJECTED",g_sessions[i].id+" reason="+candidate.rejection);
         continue;
        }
      int n=ArraySize(valid_indices);
      ArrayResize(valid_indices,n+1);
      valid_indices[n]=i;
     }

   if(ArraySize(valid_indices)==0) return;

   // Candidate preparation is sequential and can load substantial history.
   // Refresh every surviving quote again immediately before cross-symbol
   // ranking so an earlier candidate cannot win on an aged cost snapshot.
   int ranked_indices[];
   ArrayResize(ranked_indices,0);
   for(int i=0;i<ArraySize(valid_indices);i++)
     {
      int index=valid_indices[i];
      if(!RefreshCandidateQuoteState(candidates[index]))
        {
         LogEvent("INFO","COLLISION_REVALIDATION_REJECTED",
                  g_sessions[index].id+" reason="+candidates[index].rejection);
         continue;
        }
      int n=ArraySize(ranked_indices);
      ArrayResize(ranked_indices,n+1);
      ranked_indices[n]=index;
     }
   if(ArraySize(ranked_indices)==0) return;

   // Use the validation-frozen combination priority first. Equal priorities
   // fall back to lower cost/R, then first completed signal, then stable session
   // index (the initialized winner) for an exact tie.
   int winner=ranked_indices[0];
   for(int i=1;i<ArraySize(ranked_indices);i++)
     {
      int index=ranked_indices[i];
      if(g_sessions[index].priority<g_sessions[winner].priority ||
         (g_sessions[index].priority==g_sessions[winner].priority &&
          (candidates[index].cost_to_r<candidates[winner].cost_to_r-1e-9 ||
           (MathAbs(candidates[index].cost_to_r-candidates[winner].cost_to_r)<=1e-9 &&
            candidates[index].signal_bar_time<candidates[winner].signal_bar_time))))
         winner=index;
     }
   for(int i=0;i<ArraySize(ranked_indices);i++)
      if(ranked_indices[i]!=winner)
         LogEvent("INFO","COLLISION_REJECTED",g_sessions[ranked_indices[i]].id+" winner="+g_sessions[winner].id);
   SubmitCandidate(candidates[winner]);
  }

// ============================================================================
// MQL5 event handlers
// ============================================================================

int OnInit()
  {
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetAsyncMode(false);
   g_trade.SetDeviationInPoints(InpMaxDeviationPoints);

   long login=AccountInfoInteger(ACCOUNT_LOGIN);
   string login_text=StringFormat("%I64d",login);
   bool tester=IsTesterMode();
   string mode=(tester ? "TEST" : (InpEnableOrderSubmission ? "LIVE" : "DRY"));
   string state_mode=(tester ? "T" : (InpEnableOrderSubmission ? "L" : "D"));
   g_config_hash=BuildConfigHash();
   g_runtime_identity_hash=RuntimeIdentityHash();
   bool research_mode=(tester || !InpEnableOrderSubmission);
   string research_suffix=(research_mode ? IntegerToString(g_config_hash)+"." : "");
   // Keep enough room for a 20-digit ticket and compact safety suffix under
   // the terminal's 63-character global-variable name limit.
   g_prefix="TR."+login_text+"."+IntegerToString((int)InpPhase)+"."+state_mode+"."+research_suffix;
   g_account_lock_prefix="TRL."+login_text+"."+
                         IntegerToString(HashText(AccountInfoString(ACCOUNT_SERVER)))+".";
   g_log_file=InpLogFilePrefix+"_"+login_text+"_"+mode+
              (research_mode ? "_"+IntegerToString(g_config_hash) : "")+".csv";

   if(!ValidateInputs()) return INIT_PARAMETERS_INCORRECT;
   if(!ValidateReleaseGates()) return INIT_PARAMETERS_INCORRECT;
   if(!ValidateSymbolContracts()) return INIT_FAILED;
   if(!ValidateAccountIdentity()) return INIT_FAILED;
   if(IsTesterMode() && InpResetTesterStateOnInit)
      GlobalVariablesDeleteAll(g_prefix);
   // Own the account-level execution lock before any initialization path can
   // latch shared state or reconcile old exposure. A duplicate live instance
   // never reaches handle creation, state loading, or cleanup.
   if(!AcquireLiveInstanceLock()) return INIT_FAILED;
   InitializeSessions();
   if(g_halted)
     {
      CancelAllPending("initialization_runtime_failure",true);
      CloseAllPositions("initialization_runtime_failure",true);
      ReleaseLiveInstanceLock();
      return INIT_FAILED;
     }
   // If a halt/config/state failure is discovered while old strategy exposure
   // still exists, the lock-owning authorized instance attempts cleanup instead
   // of leaving the account with only passive broker exits.
   if(!LoadOrCreateAccountState())
     {
      CancelAllPending("initialization_state_failure",true);
      CloseAllPositions("initialization_state_failure",true);
      ReleaseLiveInstanceLock();
      return INIT_FAILED;
     }
   CheckExternalCashflow();
   if(g_halted)
     {
      CancelAllPending("initialization_halt",true);
      CloseAllPositions("initialization_halt",true);
      ReleaseLiveInstanceLock();
      return INIT_FAILED;
     }

   g_news_valid=LoadNewsCalendar();
   if(InpRequireNewsCalendar && !g_news_valid)
      LogEvent("WARN","NEWS_FAIL_CLOSED","signals disabled until valid calendar is loaded");
   if(g_log_failure)
     {
      Halt("audit_log_failure");
      CancelAllPending("audit_log_failure",true);
      CloseAllPositions("audit_log_failure",true);
      ReleaseLiveInstanceLock();
      return INIT_FAILED;
     }

   for(int i=0;i<3;i++)
      if(g_sessions[i].enabled)
         RefreshSession(i,TimeTradeServer());
   if(g_halted)
     {
      CancelAllPending("initialization_session_state_halt",true);
      CloseAllPositions("initialization_session_state_halt",true);
      ReleaseLiveInstanceLock();
      return INIT_FAILED;
     }
   if(InpEnableOrderSubmission && !IsTesterMode() && !OwnsLiveInstanceLock())
     {
      g_instance_lock_held=false;
      LogEvent("ERROR","INSTANCE_LOCK_LOST_DURING_INITIALIZATION","startup fenced before activation");
      return INIT_FAILED;
     }

   LogEvent("INFO","EA_INITIALIZED",
            StringFormat("build=%s release=%s orders=%s profile=%d hash=%d phase=%d",
                         EA_BUILD_ID,InpValidationReleaseId,BoolText(InpEnableOrderSubmission),
                         (int)InpProfile,g_config_hash,(int)InpPhase));
   if(g_log_failure)
     {
      Halt("audit_log_failure_during_initialization");
      CancelAllPending("audit_log_failure",true);
      CloseAllPositions("audit_log_failure",true);
      ReleaseLiveInstanceLock();
      return INIT_FAILED;
     }
   if(!EventSetTimer(1))
     {
      Halt("timer_initialization_failure");
      CancelAllPending("timer_initialization_failure",true);
      CloseAllPositions("timer_initialization_failure",true);
      ReleaseLiveInstanceLock();
      return INIT_FAILED;
     }
   g_initialized=true;
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   bool authorized_context=AuthorizedAccountContext();
   bool owns_live_lock=OwnsLiveInstanceLock();
   if(g_initialized && InpEnableOrderSubmission && reason==REASON_ACCOUNT &&
      !authorized_context && owns_live_lock)
      Halt("deinitialization_account_context_changed");
   if(g_initialized && InpEnableOrderSubmission && reason!=REASON_CLOSE &&
      authorized_context && owns_live_lock && HasAnyExposure())
     {
      // An intentional detach, chart/input change, template change, or
      // recompile must not strand managed exposure. Never send a cleanup
      // request after MT5 has already switched to an unauthorized account.
      // A terminal shutdown keeps visible broker exits and the restart plan.
      Halt("deinitialization_with_exposure");
      CancelAllPending("deinitialization_with_exposure",true);
      CloseAllPositions("deinitialization_with_exposure",true);
     }
   if(g_initialized)
     {
      bool may_persist=(!InpEnableOrderSubmission || IsTesterMode() || owns_live_lock);
      if(may_persist && !PersistAccountState())
         Halt("deinitialization_state_persistence_failure");
      if(!may_persist)
         LogEvent("WARN","DEINITIALIZATION_STATE_WRITE_SKIPPED","live instance lock is not owned");
      LogEvent("INFO","EA_DEINITIALIZED",IntegerToString(reason));
      if(g_log_failure)
         Halt("audit_log_failure_during_deinitialization");
     }
   for(int i=0;i<3;i++)
      if(g_atr_handles[i]!=INVALID_HANDLE)
        {
         IndicatorRelease(g_atr_handles[i]);
         g_atr_handles[i]=INVALID_HANDLE;
        }
   ReleaseLiveInstanceLock();
  }

void OnTick()
  {
   // Cross-symbol work is timer-driven. OnTick keeps emergency equity checks
   // responsive on the chart symbol without creating per-tick order traffic.
   if(!g_initialized) return;
   if(InpEnableOrderSubmission && !AuthorizedAccountContext())
     {
      if(OwnsLiveInstanceLock())
         Halt("runtime_account_context_changed");
      else
        {
         g_instance_lock_held=false;
         g_halted=true;
         g_halt_reason="account_changed_without_instance_lock";
         LogEvent("HALT","STALE_INSTANCE_FENCED",g_halt_reason);
        }
      return;
     }
   if(InpEnableOrderSubmission && !IsTesterMode() && !OwnsLiveInstanceLock())
     {
      g_instance_lock_held=false;
      g_halted=true;
      g_halt_reason="live_instance_lock_lost";
      LogEvent("HALT","STALE_INSTANCE_FENCED",g_halt_reason);
      return;
     }
   string reason;
   if(!GlobalRiskGuards(reason) && HasAnyExposure())
      ManageExposure();
  }

void OnTimer()
  {
   if(!g_initialized) return;
   if(InpEnableOrderSubmission && !AuthorizedAccountContext())
     {
      if(OwnsLiveInstanceLock())
         Halt("runtime_account_context_changed");
      else
        {
         g_instance_lock_held=false;
         g_halted=true;
         g_halt_reason="account_changed_without_instance_lock";
         LogEvent("HALT","STALE_INSTANCE_FENCED",g_halt_reason);
        }
      return;
     }
   RefreshLiveInstanceLock();
   if(InpEnableOrderSubmission && !IsTesterMode() && !g_instance_lock_held)
      return;
   if(!RuntimeAccountIdentityValid())
     {
      Halt("runtime_account_identity_mismatch");
      ManageExposure();
      return;
     }
   string journal_reason="";
   if(!RuntimeJournalValid(journal_reason))
     {
      if(!g_halted) Halt(journal_reason);
      ManageExposure();
      return;
     }
   CheckExternalCashflow();
   ProcessRollover();
   for(int i=0;i<3;i++)
      if(g_sessions[i].enabled)
         RefreshSession(i,TimeTradeServer());
   UpdateHighWater();
   CheckInactivity();
   CheckDirectionConcentration();
   ManageExposure();
   if(!g_halted)
      ScanForSignals();
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
  {
   if(InpEnableOrderSubmission && !AuthorizedAccountContext())
     {
      if(OwnsLiveInstanceLock())
         Halt("runtime_account_context_changed");
      else
        {
         g_instance_lock_held=false;
         g_halted=true;
         g_halt_reason="account_changed_without_instance_lock";
         LogEvent("HALT","STALE_INSTANCE_FENCED",g_halt_reason);
        }
      return;
     }
   if(InpEnableOrderSubmission && !IsTesterMode() && !OwnsLiveInstanceLock())
     {
      g_instance_lock_held=false;
      g_halted=true;
      g_halt_reason="live_instance_lock_lost";
      LogEvent("HALT","STALE_INSTANCE_FENCED",g_halt_reason);
      return;
     }
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD)
     {
      string detail=StringFormat("deal=%I64u order=%I64u price=%s volume=%.2f",
                    trans.deal,trans.order,DoubleToString(trans.price,8),trans.volume);
      if(HistoryDealSelect(trans.deal) && HistoryDealGetInteger(trans.deal,DEAL_MAGIC)==InpMagic)
        {
         ENUM_DEAL_ENTRY entry_kind=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
         if(entry_kind==DEAL_ENTRY_IN)
           {
            double expected_entry=0.0;
            if(GVRead("ExpectedEntry",expected_entry) && expected_entry>0.0)
              {
               string symbol=HistoryDealGetString(trans.deal,DEAL_SYMBOL);
               double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
               if(point>0.0)
                  detail+=" entry_slippage_points="+DoubleToString(MathAbs(trans.price-expected_entry)/point,1);
              }
           }
         else
           {
            double actual_net=HistoryDealGetDouble(trans.deal,DEAL_PROFIT)+
                              HistoryDealGetDouble(trans.deal,DEAL_COMMISSION)+
                              HistoryDealGetDouble(trans.deal,DEAL_SWAP)+
                              HistoryDealGetDouble(trans.deal,DEAL_FEE);
            detail+=" exit_deal_net="+DoubleToString(actual_net,2);
           }
        }
      if(HistoryDealSelect(trans.deal))
        {
         long position_id=HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
         double position_net=0.0;
         if(StrategyPositionNetFromHistory(position_id,position_net))
           {
            detail+=" position_net="+DoubleToString(position_net,2);
            if(!GVWrite("ActualTradeNet",position_net))
               Halt("actual_trade_net_persistence_failure");
            else
               GlobalVariablesFlush();
           }
        }
      LogEvent("INFO","DEAL_ADDED",detail);
     }
   if(trans.type==TRADE_TRANSACTION_ORDER_DELETE)
      LogEvent("INFO","ORDER_REMOVED",StringFormat("order=%I64u",trans.order));
  }
