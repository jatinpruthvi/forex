//+------------------------------------------------------------------+
//| TRIAD_SCREEN.mq5                                                 |
//| Multi-symbol demo screening EA with an on-chart challenge dashboard |
//|                                                                   |
//| This is a SEPARATE RESEARCH/SCREENING implementation. It is NOT   |
//| the canonical production EA. The frozen canonical EA is           |
//| TRIAD_R_HS.mq5 and it is not modified by this file.                |
//|                                                                   |
//| Purpose: run ONE symbol+session combination per demo account so   |
//| the user can compare which combinations produce signals/fills and |
//| whether the account would pass/fail the configured funding        |
//| challenge rules. The on-chart dashboard shows, per account:       |
//|   - challenge status (ACTIVE / PASSED / FAILED / DRY_RUN) and why |
//|   - phase progress, qualifying days, daily/overall floor distance |
//|   - today's signals/candidates/fills/rejects, total net R         |
//|   - the exact EA setting fingerprint used                        |
//|                                                                   |
//| Strategy logic (entry, sizing, exits) is a faithful port of the   |
//| frozen V2.1 rules in TRIAD_R_HS.mq5, so a signal here means the   |
//| same signal there for the same symbol/session. Production safety  |
//| machinery (lifecycle locks, GV journals, identity hashes) is      |
//| deliberately omitted: this is a demo screening tool only.         |
//|                                                                   |
//| NOTE: none of this establishes an edge. A signal, fill, or pass   |
//| on a demo account is evidence of mechanics only until the         |
//| canonical Section-13 pipeline runs on real data.                  |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "TRIAD SCREEN: one symbol/session per demo account + challenge dashboard"
#property description "Order submission is disabled by default. DEMO accounts only."
#property tester_file "triad_red_news.csv"

#include <Trade\Trade.mqh>

// ============================================================================
// Enums and constants
// ============================================================================
enum ENUM_TSC_WINDOW
  {
   TSC_WINDOW_LONDON  = 0,
   TSC_WINDOW_NEW_YORK = 1
  };

enum ENUM_TSC_PHASE
  {
   TSC_PHASE_1 = 1,
   TSC_PHASE_2 = 2
  };

enum ENUM_TSC_PROFILE
  {
   TSC_PROFILE_A_040_R150 = 0,
   TSC_PROFILE_B_035_R175 = 1,
   TSC_PROFILE_C_030_R200 = 2,
   TSC_PROFILE_D_025_R250 = 3
  };

enum ENUM_TSC_PATTERN_SIDE
  {
   TSC_PATTERN_NONE  = 0,
   TSC_PATTERN_LONG  = 1,
   TSC_PATTERN_SHORT = -1
  };

const string   TSC_BUILD_ID          = "TRIAD_SCREEN_1.0.0";
const int      TSC_SAFETY_LEAD_SEC   = 10;
const double   TSC_EPS               = 1e-12;

const int      TSC_STATE_VERSION     = 1;
const string   TSC_STATE_HEADER      = "TSC_STATE_V1";
const string   TSC_JOURNAL_HEADER    = "server_time;level;event;detail;balance;equity";
const string   TSC_SUMMARY_HEADER    =
  "server_day;balance;equity;phase;status;qualifying_days;day_closed_net;"
  "signals;candidates;fills;rejects;last_rejection;net_r_total";

const string   TSC_SYMBOLS[] =
  {
   "EURUSD","GBPUSD","USDCHF","AUDUSD","USDCAD","NZDUSD","USDJPY","EURJPY","GBPJPY"
  };

// ============================================================================
// Inputs
// ============================================================================

// ---- Combo selection -------------------------------------------------------
input string               InpSymbol                     = "EURUSD";
input ENUM_TSC_WINDOW      InpWindow                     = TSC_WINDOW_LONDON;
input string               InpComboLabel                 = "";      // auto if empty
input bool                 InpEnableOrderSubmission      = false;   // DEMO ONLY
input bool                 InpSkipFreshMidSessionStart   = true;     // canonical default
input long                 InpMagic                      = 26090399;
input string               InpExpectedAccountCurrency    = "USD";
input int                  InpExpectedServerUtcOffsetHours = 3;
input int                  InpMaxQuoteAgeSeconds         = 10;
input int                  InpMaxDeviationPoints         = 20;

// ---- The5ers-style challenge preset (editable) ------------------------------
input int                  InpChallengePhase             = 1;       // 1 or 2
input double               InpPhaseInitialBalance        = 2500.0;
input double               InpPhase1TargetPercent        = 10.0;    // +10% = $250
input double               InpPhase2TargetPercent        = 5.0;     // +5%  = $125
input int                  InpMinQualifyingDays          = 3;
input double               InpQualifyingDayPercent       = 0.5;     // = $12.50
input double               InpDailyLossPercent           = 5.0;
input double               InpOverallLossPercent         = 10.0;    // $2,250 floor
input int                  InpInactivityDays             = 30;
input bool                 InpAllowPhaseReset            = false;
input int                  InpDashboardConfirmedDays     = 0;       // operator override

// ---- Risk governors (canonical V2.1 defaults) ------------------------------
input ENUM_TSC_PROFILE     InpProfile                    = TSC_PROFILE_A_040_R150;
input double               InpRangePercentileLow         = 30.0;
input double               InpRangePercentileHigh        = 80.0;
input double               InpAtrPercentileLow           = 20.0;
input double               InpAtrPercentileHigh          = 80.0;
input int                  InpComparableSessions         = 60;
input int                  InpTimeStopMinutes            = 45;      // 0 = session only
input bool                 InpMoveStopToEntryAfter1R     = false;

// ---- Fixed entry/risk definitions (frozen V2.1) -----------------------------
input double               InpSweepAtrMin                = 0.05;
input double               InpSweepAtrMax                = 0.50;
input int                  InpReclaimBars                = 3;
input double               InpReclaimWickMin             = 0.60;
input double               InpDisplacementBodyMin        = 0.60;
input int                  InpLimitExpiryBars            = 3;
input double               InpStopBufferAtr              = 0.10;
input double               InpStopAtrMin                 = 0.60;
input double               InpStopAtrMax                 = 1.50;
input double               InpMaxCostToR                 = 0.10;
input double               InpSpreadMedianMultiplier     = 1.50;
input double               InpCommissionRoundTripPerLot  = 4.0;
input int                  InpStopSlippageReservePoints  = 10;
input int                  InpTargetSlippageReservePoints= 5;
input double               InpInternalDailyStopPercent   = 1.00;
input double               InpInternalWeeklyStopPercent  = 2.00;
input double               InpDrawdownReducePercent      = 2.00;
input double               InpDrawdownShutdownPercent    = 5.00;
input double               InpFirmFloorReservePercent    = 0.50;
input int                  InpMaxNonEmergencyRequestsDay = 20;
input int                  InpMaxTradeRequestLatencyMs    = 1000;

// ---- News calendar (same schema as canonical) --------------------------------
input string               InpNewsCsvFile                = "triad_red_news.csv";
input bool                 InpRequireNewsCalendar        = true;
input int                  InpNewsBlockMinutes           = 30;
input int                  InpNewsFlatMinutes            = 15;
input int                  InpRolloverFlatMinutes        = 15;
input int                  InpRequiredNewsCoverageHours  = 24;

// ---- Dashboard ----------------------------------------------------------------
input bool                 InpDashboardShow              = true;
input int                  InpDashboardRefreshSeconds    = 2;
input string               InpStatusFilePrefix           = "TSC";

// ============================================================================
// Structs
// ============================================================================
struct TSC_NewsEvent
  {
   datetime          utc_time;
   string            currency;
   string            title;
  };

struct TSC_Candidate
  {
   bool              detected;
   bool              valid;
   ENUM_TSC_PATTERN_SIDE side;
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

struct TSC_OpenPlan
  {
   ulong             ticket;
   string            symbol;
   datetime          opened;
   double            open_price;
   double            stop;
   double            target;
   double            volume;
   double            risk_cash;
   double            one_r_price;
   int               day_key;
  };

// ============================================================================
// Globals
// ============================================================================
CTrade            g_trade;
TSC_NewsEvent     g_news[];
TSC_Candidate     g_candidate;
TSC_OpenPlan      g_open;

string            g_symbol        = "";
ENUM_TSC_WINDOW   g_window        = TSC_WINDOW_LONDON;
string            g_combo         = "";
bool              g_symbol_ok     = false;
int               g_atr_handle    = INVALID_HANDLE;

bool              g_halted        = false;
string            g_halt_reason   = "";
bool              g_news_valid    = false;
datetime          g_news_coverage_end_utc = 0;
bool              g_news_stale_logged     = false;

// Session state (single combo).
datetime          g_range_start   = 0;
datetime          g_range_end     = 0;
datetime          g_entry_start   = 0;
datetime          g_entry_end     = 0;
bool              g_range_ready   = false;
bool              g_range_warn_logged = false;
double            g_range_high    = 0.0;
double            g_range_low     = 0.0;
bool              g_consumed      = false;
int               g_session_day_key = 0;
datetime          g_last_closed_bar = 0;

// Account/challenge state.
int               g_day_key       = 0;
datetime          g_day_start_time = 0;
double            g_day_start_balance = 0.0;
double            g_day_start_equity  = 0.0;
double            g_prev_day_balance  = 0.0;
double            g_high_water    = 0.0;
int               g_week_key      = 0;
double            g_week_start_balance = 0.0;
int               g_qualifying_days = 0;
datetime          g_state_created = 0;
datetime          g_last_trade_time = 0;
int               g_stored_phase  = 0;
double            g_firm_daily_floor = 0.0;
int               g_request_count = 0;

// Today's counters (reset at rollover).
int               g_today_signals = 0;
int               g_today_candidates = 0;
int               g_today_fills  = 0;
int               g_today_rejects = 0;
string            g_last_rejection = "";
double            g_net_r_total  = 0.0;
double            g_net_cash_total = 0.0;

// Request throttling / fill tracking.
datetime          g_last_request_time = 0;
double            g_last_trade_risk_cash = 0.0;
ulong             g_last_seen_position_ticket = 0;

// Emergency-safety per-ticket throttle (0=order delete, 1=position close,
// 2=repair/breakeven modify). Emergency cleanup must never be gated by the
// non-emergency request cap.
datetime          g_emergency_last_time[3];
ulong             g_emergency_last_ticket[3];

// Closed-trade ledger id set: loaded from T.csv so a crash between the append
// and plan removal can never double-account a position.
long              g_ledger_position_ids[];

// Inactivity: hourly recompute of the last account BUY/SELL deal time.
datetime          g_last_activity_check = 0;

// Foreign-exposure log throttle.
datetime          g_last_foreign_exposure_log = 0;

// ============================================================================
// Small helpers
// ============================================================================
string TscFileName(const string kind)
  {
   long login=AccountInfoInteger(ACCOUNT_LOGIN);
   return StringFormat("%s_%s_%I64d_%s",InpStatusFilePrefix,kind,login,g_combo);
  }

bool BoolText(const bool value)
  {
   return (value ? "true" : "false");
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

string LogFilePath()
  {
   return TscFileName("J")+".csv";
  }

string StateFilePath()
  {
   return TscFileName("S")+".csv";
  }

string SummaryFilePath()
  {
   return TscFileName("D")+".csv";
  }

void LogEvent(const string level,const string event_name,const string detail)
  {
   string message=StringFormat("[%s] %s | %s",level,event_name,detail);
   if(level=="ERROR" || level=="HALT" || InpDashboardShow)
      Print(message);

   int handle=FileOpen(LogFilePath(),FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
   if(handle==INVALID_HANDLE)
     {
      if(level=="ERROR" || level=="HALT")
         Print("[ERROR] TSC_AUDIT_LOG_OPEN_FAILED | ",LogFilePath(),
               " error=",GetLastError());
      return;
     }
   if(FileSize(handle)==0)
      FileWrite(handle,"server_time","level","event","detail","balance","equity");
   if(!FileSeek(handle,0,SEEK_END))
     {
      FileClose(handle);
      return;
     }
   FileWrite(handle,TimeToString(TimeTradeServer(),TIME_DATE|TIME_SECONDS),level,event_name,detail,
             DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2),
             DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2));
   FileClose(handle);
  }

bool SymbolSupported(const string symbol)
  {
   for(int i=0;i<ArraySize(TSC_SYMBOLS);i++)
      if(TSC_SYMBOLS[i]==symbol)
         return true;
   return false;
  }

bool SymbolCurrencies(const string symbol,string &ccy1,string &ccy2)
  {
   ccy1=StringSubstr(symbol,0,3);
   ccy2=StringSubstr(symbol,3,3);
   return StringLen(ccy1)==3 && StringLen(ccy2)==3;
  }

// ============================================================================
// Config hash (dashboard fingerprint of every setting that affects behavior)
// ============================================================================
uint FnvStep(uint seed,const string text)
  {
   seed^=StringLen(text);
   seed*=16777619;
   for(int j=0;j<StringLen(text);j++)
     {
      seed^=(uint)StringGetCharacter(text,j);
      seed*=16777619;
     }
   return seed;
  }

int ConfigHash()
  {
   uint seed=2166136261;
   int n=0;
   string parts[];
   ArrayResize(parts,64);
   parts[n++]=TscFileName("");
   parts[n++]=InpSymbol;
   parts[n++]=IntegerToString((int)InpWindow);
   parts[n++]=IntegerToString((int)InpProfile);
   parts[n++]=DoubleToString(InpRangePercentileLow,4);
   parts[n++]=DoubleToString(InpRangePercentileHigh,4);
   parts[n++]=DoubleToString(InpAtrPercentileLow,4);
   parts[n++]=DoubleToString(InpAtrPercentileHigh,4);
   parts[n++]=IntegerToString(InpComparableSessions);
   parts[n++]=IntegerToString(InpTimeStopMinutes);
   parts[n++]=BoolText(InpMoveStopToEntryAfter1R);
   parts[n++]=DoubleToString(InpSweepAtrMin,4);
   parts[n++]=DoubleToString(InpSweepAtrMax,4);
   parts[n++]=IntegerToString(InpReclaimBars);
   parts[n++]=DoubleToString(InpReclaimWickMin,4);
   parts[n++]=DoubleToString(InpDisplacementBodyMin,4);
   parts[n++]=IntegerToString(InpLimitExpiryBars);
   parts[n++]=DoubleToString(InpStopBufferAtr,4);
   parts[n++]=DoubleToString(InpStopAtrMin,4);
   parts[n++]=DoubleToString(InpStopAtrMax,4);
   parts[n++]=DoubleToString(InpMaxCostToR,4);
   parts[n++]=DoubleToString(InpSpreadMedianMultiplier,4);
   parts[n++]=DoubleToString(InpCommissionRoundTripPerLot,4);
   parts[n++]=IntegerToString(InpStopSlippageReservePoints);
   parts[n++]=IntegerToString(InpTargetSlippageReservePoints);
   parts[n++]=DoubleToString(InpInternalDailyStopPercent,4);
   parts[n++]=DoubleToString(InpInternalWeeklyStopPercent,4);
   parts[n++]=DoubleToString(InpDrawdownReducePercent,4);
   parts[n++]=DoubleToString(InpDrawdownShutdownPercent,4);
   parts[n++]=DoubleToString(InpFirmFloorReservePercent,4);
   parts[n++]=IntegerToString(InpChallengePhase);
   parts[n++]=DoubleToString(InpPhaseInitialBalance,4);
   parts[n++]=DoubleToString(InpPhase1TargetPercent,4);
   parts[n++]=DoubleToString(InpPhase2TargetPercent,4);
   parts[n++]=IntegerToString(InpMinQualifyingDays);
   parts[n++]=DoubleToString(InpQualifyingDayPercent,4);
   parts[n++]=DoubleToString(InpDailyLossPercent,4);
   parts[n++]=DoubleToString(InpOverallLossPercent,4);
   parts[n++]=IntegerToString(InpInactivityDays);
   parts[n++]=BoolText(InpRequireNewsCalendar);
   parts[n++]=IntegerToString(InpNewsBlockMinutes);
   parts[n++]=IntegerToString(InpNewsFlatMinutes);
   parts[n++]=IntegerToString(InpRolloverFlatMinutes);
   parts[n++]=IntegerToString(InpRequiredNewsCoverageHours);
   parts[n++]=BoolText(InpEnableOrderSubmission);
   parts[n++]=BoolText(InpSkipFreshMidSessionStart);
   parts[n++]=IntegerToString((long)InpMagic);
   parts[n++]=InpExpectedAccountCurrency;
   parts[n++]=IntegerToString(InpExpectedServerUtcOffsetHours);
   parts[n++]=IntegerToString(InpMaxQuoteAgeSeconds);
   parts[n++]=IntegerToString(InpMaxDeviationPoints);
   parts[n++]=IntegerToString(InpMaxNonEmergencyRequestsDay);
   parts[n++]=IntegerToString(InpMaxTradeRequestLatencyMs);
   parts[n++]=InpNewsCsvFile;
   parts[n++]=BoolText(InpAllowPhaseReset);
   parts[n++]=IntegerToString(InpDashboardConfirmedDays);
   for(int i=0;i<n;i++)
      seed=FnvStep(seed,parts[i]);
   return (int)(seed&0x7FFFFFFF);
  }

// ============================================================================
// Persisted account/challenge state (small CSV, one row, per combo+login)
// ============================================================================
bool LoadState()
  {
   int handle=FileOpen(StateFilePath(),FILE_READ|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
   if(handle==INVALID_HANDLE)
      return false;
   string header=FileReadString(handle);
   if(header!=TSC_STATE_HEADER)
     {
      FileClose(handle);
      return false;
     }
   string version_s=FileReadString(handle);
   string day_key_s=FileReadString(handle);
   string day_start_time_s=FileReadString(handle);
   string day_start_bal_s=FileReadString(handle);
   string day_start_eq_s=FileReadString(handle);
   string prev_bal_s=FileReadString(handle);
   string high_water_s=FileReadString(handle);
   string week_key_s=FileReadString(handle);
   string week_bal_s=FileReadString(handle);
   string qualifying_s=FileReadString(handle);
   string created_s=FileReadString(handle);
   string last_trade_s=FileReadString(handle);
   string phase_s=FileReadString(handle);
   string halted_s=FileReadString(handle);
   string halt_reason_s=FileReadString(handle);
   string req_count_s=FileReadString(handle);
   string symbol_s=FileReadString(handle);
   FileClose(handle);

   if((int)StringToInteger(version_s)!=TSC_STATE_VERSION ||
      symbol_s!=g_combo)
      return false;
   if((int)StringToInteger(phase_s)!=(int)InpChallengePhase)
      return false;

   g_day_key=(int)StringToInteger(day_key_s);
   g_day_start_time=(datetime)StringToInteger(day_start_time_s);
   g_day_start_balance=StringToDouble(day_start_bal_s);
   g_day_start_equity=StringToDouble(day_start_eq_s);
   g_prev_day_balance=StringToDouble(prev_bal_s);
   g_high_water=StringToDouble(high_water_s);
   g_week_key=(int)StringToInteger(week_key_s);
   g_week_start_balance=StringToDouble(week_bal_s);
   g_qualifying_days=(int)StringToInteger(qualifying_s);
   g_state_created=(datetime)StringToInteger(created_s);
   g_last_trade_time=(datetime)StringToInteger(last_trade_s);
   g_stored_phase=(int)StringToInteger(phase_s);
   // A persisted halt is deliberately NOT restored. The screen tool's halt is
   // a per-run latch (request cap, config failure) that the canonical EA would
   // keep until an authorized reset; here a restart is the documented recovery
   // and the economic status machine re-derives everything from account state.
   g_halt_reason=halt_reason_s;
   g_request_count=(int)StringToInteger(req_count_s);
   g_halted=false;
   if(StringToInteger(halted_s)>0.5)
      LogEvent("WARN","STATE_HALT_NOT_RESTORED",halt_reason_s);
   return true;
  }

bool SaveState()
  {
   int handle=FileOpen(StateFilePath(),FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
   if(handle==INVALID_HANDLE)
     {
      LogEvent("ERROR","STATE_WRITE_OPEN_FAILED",StateFilePath());
      return false;
     }
   FileWrite(handle,
             TSC_STATE_HEADER,
             IntegerToString(TSC_STATE_VERSION),
             IntegerToString(g_day_key),
             IntegerToString((long)g_day_start_time),
             DoubleToString(g_day_start_balance,4),
             DoubleToString(g_day_start_equity,4),
             DoubleToString(g_prev_day_balance,4),
             DoubleToString(g_high_water,4),
             IntegerToString(g_week_key),
             DoubleToString(g_week_start_balance,4),
             IntegerToString(g_qualifying_days),
             IntegerToString((long)g_state_created),
             IntegerToString((long)g_last_trade_time),
             IntegerToString(g_stored_phase),
             IntegerToString(g_halted ? 1 : 0),
             g_halt_reason,
             IntegerToString(g_request_count),
             g_combo);
   FileClose(handle);
   return true;
  }

void AppendDailySummary(const string status)
  {
   int handle=FileOpen(SummaryFilePath(),FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
   if(handle==INVALID_HANDLE)
      return;
   if(FileSize(handle)==0)
      FileWrite(handle,"server_day","balance","equity","phase","status",
                "qualifying_days","day_closed_net","signals","candidates",
                "fills","rejects","last_rejection","net_r_total");
   int trade_count;
   double first_net,day_closed_net;
   bool foreign_deal;
   bool daily_ok=RebuildDailyClosedTrades(trade_count,first_net,day_closed_net,foreign_deal);
   if(!daily_ok)
      day_closed_net=0.0;
   FileSeek(handle,0,SEEK_END);
   FileWrite(handle,
             IntegerToString(g_day_key),
             DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2),
             DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2),
             IntegerToString(InpChallengePhase),
             status,
             IntegerToString(EffectiveConfirmedDays()),
             DoubleToString(day_closed_net,2),
             IntegerToString(g_today_signals),
             IntegerToString(g_today_candidates),
             IntegerToString(g_today_fills),
             IntegerToString(g_today_rejects),
             g_last_rejection,
             DoubleToString(g_net_r_total,3));
   FileClose(handle);
  }

// ============================================================================
// Civil-time / DST helpers (ported verbatim from the canonical EA)
// ============================================================================
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

datetime MakeDateTime(const int year,const int mon,const int day,const int hour,const int minute)
  {
   MqlDateTime value;
   value.year=year;
   value.mon=mon;
   value.day=day;
   value.hour=hour;
   value.min=minute;
   value.sec=0;
   return StructToTime(value);
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
   datetime start=NthSundayUtc(p.year,3,2,7);
   datetime finish=NthSundayUtc(p.year,11,1,6);
   return (utc_time>=start && utc_time<finish) ? -4*3600 : -5*3600;
  }

datetime LocalWallToUtc(const int year,const int mon,const int day,const int hour,const int minute,
                        const ENUM_TSC_WINDOW zone)
  {
   datetime wall=MakeDateTime(year,mon,day,hour,minute);
   int standard=(zone==TSC_WINDOW_LONDON ? 0 : -5*3600);
   datetime guess=wall-standard;
   int offset=(zone==TSC_WINDOW_LONDON ? LondonUtcOffsetSeconds(guess)
                                      : NewYorkUtcOffsetSeconds(guess));
   datetime utc=wall-offset;
   offset=(zone==TSC_WINDOW_LONDON ? LondonUtcOffsetSeconds(utc)
                                   : NewYorkUtcOffsetSeconds(utc));
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

void GetLocalDate(const datetime utc_time,const ENUM_TSC_WINDOW zone,
                  int &year,int &mon,int &day,int &day_key)
  {
   int offset=(zone==TSC_WINDOW_LONDON ? LondonUtcOffsetSeconds(utc_time)
                                       : NewYorkUtcOffsetSeconds(utc_time));
   MqlDateTime p;
   TimeToStruct(utc_time+offset,p);
   year=p.year;
   mon=p.mon;
   day=p.day;
   day_key=year*10000+mon*100+day;
  }

void ShiftCivilDate(const int year,const int mon,const int day,const int shift_days,
                    int &out_year,int &out_mon,int &out_day)
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

bool BuildBoundsForCivilDate(const int year,const int mon,const int day,
                             datetime &range_start,datetime &range_end,
                             datetime &entry_start,datetime &entry_end)
  {
   if(g_window==TSC_WINDOW_LONDON)
     {
      range_start=UtcToServer(LocalWallToUtc(year,mon,day,0,0,TSC_WINDOW_LONDON));
      range_end=UtcToServer(LocalWallToUtc(year,mon,day,7,0,TSC_WINDOW_LONDON));
      entry_start=UtcToServer(LocalWallToUtc(year,mon,day,7,0,TSC_WINDOW_LONDON));
      entry_end=UtcToServer(LocalWallToUtc(year,mon,day,11,0,TSC_WINDOW_LONDON));
      return true;
     }

   entry_start=UtcToServer(LocalWallToUtc(year,mon,day,8,30,TSC_WINDOW_NEW_YORK));
   entry_end=UtcToServer(LocalWallToUtc(year,mon,day,11,0,TSC_WINDOW_NEW_YORK));

   datetime entry_start_utc=ServerToUtc(entry_start);
   int ly,lm,ld,lkey;
   GetLocalDate(entry_start_utc,TSC_WINDOW_LONDON,ly,lm,ld,lkey);
   range_start=UtcToServer(LocalWallToUtc(ly,lm,ld,7,0,TSC_WINDOW_LONDON));
   range_end=UtcToServer(LocalWallToUtc(ly,lm,ld,13,0,TSC_WINDOW_LONDON));
   return true;
  }

bool GetCurrentSessionBounds(const datetime server_now,
                             int &day_key,datetime &range_start,datetime &range_end,
                             datetime &entry_start,datetime &entry_end)
  {
   datetime utc_now=ServerToUtc(server_now);
   int y,m,d;
   GetLocalDate(utc_now,g_window,y,m,d,day_key);
   return BuildBoundsForCivilDate(y,m,d,range_start,range_end,entry_start,entry_end);
  }

bool RefreshSession(const datetime now)
  {
   int day_key;
   datetime rs,re,es,ee;
   if(!GetCurrentSessionBounds(now,day_key,rs,re,es,ee))
      return false;

   if(day_key!=g_session_day_key)
     {
      g_session_day_key=day_key;
      g_range_start=rs;
      g_range_end=re;
      g_entry_start=es;
      g_entry_end=ee;
      g_range_ready=false;
      g_range_warn_logged=false;
      g_consumed=false;
      g_last_closed_bar=0;
      g_range_high=0.0;
      g_range_low=0.0;
      // Canonical fresh-session rule: an attach that lands inside the entry
      // window (after its first bar) must not reconstruct and trade a stale
      // event for the remainder of the session.
      if(InpEnableOrderSubmission && !IsTesterMode() && InpSkipFreshMidSessionStart &&
         now>es+300 && now<ee)
        {
         g_consumed=true;
         LogEvent("WARN","MID_SESSION_START_SKIPPED",g_combo);
        }
     }

   // The completed range is authoritative. Read it only once every request
   // bar exists (now>=range_end). Reading while inside [range_start,range_end)
   // can never satisfy ReadRange and, worse, stops being attempted at the
   // boundary (the New York range closes 30 minutes BEFORE its entry window).
   if(!g_range_ready && now>=g_range_end)
     {
      double high,low;
      if(ReadRange(g_symbol,g_range_start,g_range_end,high,low))
        {
         g_range_high=high;
         g_range_low=low;
         g_range_ready=true;
        }
      else if(!g_range_warn_logged)
        {
         g_range_warn_logged=true;
         LogEvent("WARN","RANGE_UNAVAILABLE",StringFormat("window=%s time=%s..%s",
                  (g_window==TSC_WINDOW_LONDON ? "LONDON":"NEW_YORK"),
                  TimeToString(g_range_start,TIME_DATE|TIME_MINUTES),
                  TimeToString(g_range_end,TIME_DATE|TIME_MINUTES)));
        }
     }
   return true;
  }

// ============================================================================
// News calendar (same schema/behavior as canonical)
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
               StringFormat("events=%d declared_through=%s required_through=%s",
                            ArraySize(g_news),
                            TimeToString(declared_coverage_end,TIME_DATE|TIME_MINUTES),
                            TimeToString(now_utc+InpRequiredNewsCoverageHours*3600,
                                         TIME_DATE|TIME_MINUTES)));
      return false;
     }
   LogEvent("INFO","NEWS_LOADED",StringFormat("red_events=%d coverage_end_utc=%s",
            ArraySize(g_news),TimeToString(g_news_coverage_end_utc,TIME_DATE|TIME_MINUTES)));
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

bool IsRelevantNewsWindow(const string ccy1,const string ccy2,const datetime server_time,
                          const int minutes)
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
      if(MathAbs((double)delta)<=window+TSC_SAFETY_LEAD_SEC)
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
      if(delta>=0 && delta<=minutes*60+TSC_SAFETY_LEAD_SEC && (!found || delta<best))
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
      if(elapsed>=0 && elapsed<=minutes*60+TSC_SAFETY_LEAD_SEC)
         return true;
     }
   return false;
  }

// ============================================================================
// Market data and statistics (ported from canonical)
// ============================================================================
bool TickIsFresh(const MqlTick &tick)
  {
   datetime now=TimeTradeServer();
   long age=(long)(now-tick.time);
   return (tick.time>0 && tick.bid>0.0 && tick.ask>tick.bid &&
           age>=0 && age<=InpMaxQuoteAgeSeconds);
  }

bool ReadRange(const string symbol,const datetime start_time,const datetime end_time,
               double &high,double &low)
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
   if(g_atr_handle==INVALID_HANDLE || BarsCalculated(g_atr_handle)<=14)
      return false;
   int shift=iBarShift(symbol,PERIOD_M15,before_time-1,false);
   if(shift<0)
      return false;
   datetime bar_open=iTime(symbol,PERIOD_M15,shift);
   if(bar_open<=0 || bar_open+PeriodSeconds(PERIOD_M15)>before_time)
      return false;
   double values[];
   ArrayResize(values,1);
   if(CopyBuffer(g_atr_handle,0,shift,1,values)!=1)
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
      if(bars[i].time+PeriodSeconds(PERIOD_M5)<=opened || bars[i].time>=current_open)
         continue;
      if(type==POSITION_TYPE_BUY && bars[i].close>=one_r_price)
         return true;
      if(type==POSITION_TYPE_SELL && bars[i].close<=one_r_price)
         return true;
     }
   return false;
  }

double Median(double &values[])
  {
   int n=ArraySize(values);
   if(n==0) return 0.0;
   ArraySort(values);
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

bool ComparableStatistics(const datetime signal_time,const double current_range_width,
                          const double current_atr,double &range_percentile,
                          double &atr_percentile,double &spread_median)
  {
   datetime signal_utc=ServerToUtc(signal_time);
   int y,m,d,current_key;
   GetLocalDate(signal_utc,g_window,y,m,d,current_key);
   int elapsed=(int)(signal_time+PeriodSeconds(PERIOD_M5)-g_entry_start);
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
      if(!BuildBoundsForCivilDate(hy,hm,hd,rs,re,es,ee))
         continue;
      double rh,rl;
      if(!ReadRange(g_symbol,rs,re,rh,rl))
         continue;
      datetime comparable_time=es+elapsed;
      double av,sv;
      if(!ComputeAtrBefore(g_symbol,es,av))
         continue;
      if(!GetHistoricalMinuteSpread(g_symbol,comparable_time,sv))
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
      LogEvent("WARN","STATS_INSUFFICIENT",StringFormat("%s got=%d need=%d",
               g_combo,ArraySize(ranges),InpComparableSessions));
      return false;
     }
   range_percentile=PercentileRank(current_range_width,ranges);
   atr_percentile=PercentileRank(current_atr,atrs);
   spread_median=Median(spreads);
   return true;
  }

// ============================================================================
// Pattern detection (ported verbatim; single-session variant)
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

bool DetectPattern(TSC_Candidate &candidate)
  {
   // Explicit reset: ZeroMemory is not defined for structs containing string
   // members (documented restriction), so every field is set explicitly.
   candidate.detected=false;
   candidate.valid=false;
   candidate.side=TSC_PATTERN_NONE;
   candidate.symbol=g_symbol;
   candidate.signal_bar_time=0;
   candidate.expiry_time=0;
   candidate.atr=0.0;
   candidate.range_high=0.0;
   candidate.range_low=0.0;
   candidate.sweep_extreme=0.0;
   candidate.entry=0.0;
   candidate.stop=0.0;
   candidate.target=0.0;
   candidate.one_r_price=0.0;
   candidate.volume=0.0;
   candidate.cash_risk=0.0;
   candidate.slippage_reserve_cash=0.0;
   candidate.target_net=0.0;
   candidate.cost_to_r=0.0;
   candidate.range_percentile=0.0;
   candidate.atr_percentile=0.0;
   candidate.spread_points=0.0;
   candidate.spread_median_points=0.0;
   candidate.rejection="";

   MqlRates bars[];
   datetime signal_start=(g_entry_start>g_range_end ? g_entry_start : g_range_end);
   if(!GetCompletedSessionBars(g_symbol,signal_start,bars))
     {
      candidate.rejection="session_bars_unavailable";
      return false;
     }
   int n=ArraySize(bars);
   if(n==0 || bars[n-1].time==g_last_closed_bar)
      return false;
   g_last_closed_bar=bars[n-1].time;
   candidate.signal_bar_time=bars[n-1].time;

   double atr;
   if(!ComputeAtrBefore(g_symbol,g_entry_start,atr))
     {
      candidate.rejection="atr_unavailable";
      return false;
     }
   candidate.atr=atr;
   candidate.range_high=g_range_high;
   candidate.range_low=g_range_low;

   int sweep_index=-1;
   ENUM_TSC_PATTERN_SIDE sweep_side=TSC_PATTERN_NONE;
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
      sweep_side=(long_sweep ? TSC_PATTERN_LONG : TSC_PATTERN_SHORT);
      break;
     }
   if(sweep_index<0)
     {
      candidate.rejection="no_sweep_event";
      return false;
     }

   candidate.side=sweep_side;
   double sweep_extreme=(sweep_side==TSC_PATTERN_LONG ? bars[sweep_index].low
                                                      : bars[sweep_index].high);
   int reclaim_index=-1;
   int last_reclaim_bar=(n-1<sweep_index+InpReclaimBars-1 ? n-1
                                                          : sweep_index+InpReclaimBars-1);
   for(int i=sweep_index;i<=last_reclaim_bar;i++)
     {
      if(sweep_side==TSC_PATTERN_LONG)
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
   if(sweep_side==TSC_PATTERN_LONG)
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

// ============================================================================
// Pricing, cost, volume, and target (ported from canonical)
// ============================================================================
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

bool BrokerDistancesValid(const TSC_Candidate &candidate,const MqlTick &tick)
  {
   double point=SymbolInfoDouble(candidate.symbol,SYMBOL_POINT);
   int stops=(int)SymbolInfoInteger(candidate.symbol,SYMBOL_TRADE_STOPS_LEVEL);
   int freeze=(int)SymbolInfoInteger(candidate.symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   double minimum=MathMax(stops,freeze)*point;
   double epsilon=point*0.1;
   if(candidate.side==TSC_PATTERN_LONG)
      return candidate.entry<tick.ask && candidate.stop<candidate.entry && candidate.target>candidate.entry &&
             tick.ask-candidate.entry+epsilon>=minimum &&
             candidate.entry-candidate.stop+epsilon>=minimum &&
             candidate.target-candidate.entry+epsilon>=minimum;
   return candidate.entry>tick.bid && candidate.stop>candidate.entry && candidate.target<candidate.entry &&
          candidate.entry-tick.bid+epsilon>=minimum &&
          candidate.stop-candidate.entry+epsilon>=minimum &&
          candidate.entry-candidate.target+epsilon>=minimum;
  }

bool CurrentCostToR(const TSC_Candidate &candidate,const MqlTick &tick,double &cost_to_r)
  {
   cost_to_r=DBL_MAX;
   if(tick.bid<=0.0 || tick.ask<=tick.bid)
      return false;
   double point=SymbolInfoDouble(candidate.symbol,SYMBOL_POINT);
   if(point<=0.0)
      return false;
   ENUM_ORDER_TYPE order_type=(candidate.side==TSC_PATTERN_LONG ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   double spread_result;
   if(candidate.side==TSC_PATTERN_LONG)
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
   double adverse_slippage_price=(candidate.side==TSC_PATTERN_LONG ? candidate.entry-slippage_distance
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

bool MarginAvailableForCandidate(const TSC_Candidate &candidate)
  {
   ENUM_ORDER_TYPE order_type=(candidate.side==TSC_PATTERN_LONG ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   double required_margin=0.0;
   if(!OrderCalcMargin(order_type,candidate.symbol,candidate.volume,candidate.entry,required_margin))
      return false;
   return required_margin>=0.0 && required_margin<=AccountInfoDouble(ACCOUNT_MARGIN_FREE)+1e-6;
  }

bool CashLossForVolume(const TSC_Candidate &candidate,const double volume,double &cash_loss,
                       double &slippage_reserve_cash)
  {
   double point=SymbolInfoDouble(candidate.symbol,SYMBOL_POINT);
   double adverse_stop=candidate.stop;
   ENUM_ORDER_TYPE order_type=(candidate.side==TSC_PATTERN_LONG ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   if(candidate.side==TSC_PATTERN_LONG)
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

bool CalculateVolume(TSC_Candidate &candidate,const double budget)
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

bool SolveTargetPrice(TSC_Candidate &candidate,const double target_r)
  {
   ENUM_ORDER_TYPE order_type=(candidate.side==TSC_PATTERN_LONG ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   double point=SymbolInfoDouble(candidate.symbol,SYMBOL_POINT);
   double stop_distance=MathAbs(candidate.entry-candidate.stop);
   double desired_net=candidate.cash_risk*target_r;
   double low=0.0;
   double high=stop_distance*target_r*3.0;
   for(int iteration=0;iteration<60;iteration++)
     {
      double distance=(low+high)/2.0;
      double nominal=(candidate.side==TSC_PATTERN_LONG ? candidate.entry+distance
                                                       : candidate.entry-distance);
      double effective=(candidate.side==TSC_PATTERN_LONG ? nominal-InpTargetSlippageReservePoints*point
                                                         : nominal+InpTargetSlippageReservePoints*point);
      double gross;
      if(!OrderCalcProfit(order_type,candidate.symbol,candidate.volume,candidate.entry,effective,gross))
         return false;
      double net=gross-InpCommissionRoundTripPerLot*candidate.volume;
      if(net<desired_net) low=distance; else high=distance;
     }
   double raw_target=(candidate.side==TSC_PATTERN_LONG ? candidate.entry+high : candidate.entry-high);
   candidate.target=(candidate.side==TSC_PATTERN_LONG ? NormalizePriceUp(candidate.symbol,raw_target)
                                                      : NormalizePriceDown(candidate.symbol,raw_target));
   double effective_target=(candidate.side==TSC_PATTERN_LONG ?
                            candidate.target-InpTargetSlippageReservePoints*point :
                            candidate.target+InpTargetSlippageReservePoints*point);
   double actual_gross;
   if(!OrderCalcProfit(order_type,candidate.symbol,candidate.volume,candidate.entry,
                       effective_target,actual_gross))
      return false;
   candidate.target_net=actual_gross-InpCommissionRoundTripPerLot*candidate.volume;
   double raw_one_r=(candidate.side==TSC_PATTERN_LONG ? candidate.entry+stop_distance
                                                      : candidate.entry-stop_distance);
   candidate.one_r_price=(candidate.side==TSC_PATTERN_LONG ? NormalizePriceUp(candidate.symbol,raw_one_r)
                                                           : NormalizePriceDown(candidate.symbol,raw_one_r));
   return candidate.target>0.0 && candidate.target_net+1e-6>=desired_net;
  }

bool RefreshCandidateQuoteState(TSC_Candidate &candidate)
  {
   MqlTick tick;
   double point=SymbolInfoDouble(candidate.symbol,SYMBOL_POINT);
   if(point<=0.0 || !SymbolInfoTick(candidate.symbol,tick) || !TickIsFresh(tick) ||
      (candidate.side==TSC_PATTERN_LONG && candidate.entry>=tick.ask) ||
      (candidate.side==TSC_PATTERN_SHORT && candidate.entry<=tick.bid))
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

bool PrepareCandidate(TSC_Candidate &candidate)
  {
   candidate.valid=false;
   MqlRates displacement;
   if(!GetCompletedBarAt(g_symbol,candidate.signal_bar_time,displacement))
     {
      candidate.rejection="displacement_bar_unavailable";
      return false;
     }
   candidate.entry=NormalizePriceToTick(g_symbol,(displacement.open+displacement.close)/2.0);
   double raw_stop=(candidate.side==TSC_PATTERN_LONG ?
                    candidate.sweep_extreme-InpStopBufferAtr*candidate.atr :
                    candidate.sweep_extreme+InpStopBufferAtr*candidate.atr);
   candidate.stop=(candidate.side==TSC_PATTERN_LONG ? NormalizePriceDown(g_symbol,raw_stop)
                                                    : NormalizePriceUp(g_symbol,raw_stop));

   double stop_distance=MathAbs(candidate.entry-candidate.stop);
   double stop_atr=stop_distance/candidate.atr;
   if(stop_atr<InpStopAtrMin || stop_atr>InpStopAtrMax)
     {
      candidate.rejection="stop_atr";
      return false;
     }

   if((ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(g_symbol,SYMBOL_TRADE_MODE)!=SYMBOL_TRADE_MODE_FULL)
     {
      candidate.rejection="symbol_not_full_trade_mode";
      return false;
     }
   MqlTick tick;
   if(!SymbolInfoTick(g_symbol,tick) || !TickIsFresh(tick))
     {
      candidate.rejection="quote_stale";
      return false;
     }
   double point=SymbolInfoDouble(g_symbol,SYMBOL_POINT);
   candidate.spread_points=(tick.ask-tick.bid)/point;
   if(candidate.side==TSC_PATTERN_LONG && candidate.entry>=tick.ask)
     {
      candidate.rejection="buy_limit_marketable_or_missed";
      return false;
     }
   if(candidate.side==TSC_PATTERN_SHORT && candidate.entry<=tick.bid)
     {
      candidate.rejection="sell_limit_marketable_or_missed";
      return false;
     }

   string ccy1,ccy2;
   SymbolCurrencies(g_symbol,ccy1,ccy2);
   if(IsRelevantNewsWindow(ccy1,ccy2,TimeTradeServer(),InpNewsBlockMinutes))
     {
      candidate.rejection="news_blackout";
      return false;
     }

   if(!ComparableStatistics(candidate.signal_bar_time,
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
   if(!RefreshCandidateQuoteState(candidate))
      return false;

   if(candidate.side==TSC_PATTERN_LONG && candidate.range_high-candidate.entry<candidate.target-candidate.entry)
     {
      candidate.rejection="target_room";
      return false;
     }
   if(candidate.side==TSC_PATTERN_SHORT && candidate.entry-candidate.range_low<candidate.entry-candidate.target)
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
// Risk selection and guards (ported from canonical)
// ============================================================================
int EffectiveConfirmedDays()
  {
   if(IsTesterMode() && InpDashboardConfirmedDays==0)
      return g_qualifying_days;
   return (InpDashboardConfirmedDays>0 ? InpDashboardConfirmedDays : g_qualifying_days);
  }

double SelectedBaseRiskFraction()
  {
   switch(InpProfile)
     {
      case TSC_PROFILE_A_040_R150: return 0.0040;
      case TSC_PROFILE_B_035_R175: return 0.0035;
      case TSC_PROFILE_C_030_R200: return 0.0030;
      case TSC_PROFILE_D_025_R250: return 0.0025;
     }
   return 0.0;
  }

double SelectedTargetR()
  {
   switch(InpProfile)
     {
      case TSC_PROFILE_A_040_R150: return 1.50;
      case TSC_PROFILE_B_035_R175: return 1.75;
      case TSC_PROFILE_C_030_R200: return 2.00;
      case TSC_PROFILE_D_025_R250: return 2.50;
     }
   return 0.0;
  }

double CurrentStrategyDrawdownPercent()
  {
   if(g_high_water<=0.0) return 0.0;
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   return MathMax(0.0,100.0*(g_high_water-equity)/g_high_water);
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
   double percent=(InpChallengePhase==TSC_PHASE_1 ? InpPhase1TargetPercent
                                                    : InpPhase2TargetPercent);
   return InpPhaseInitialBalance*(1.0+percent/100.0);
  }

double FirmOverallFloor()
  {
   return InpPhaseInitialBalance*(1.0-InpOverallLossPercent/100.0);
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
   double shutdown_equity=g_high_water*(1.0-InpDrawdownShutdownPercent/100.0);
   if(projected<=shutdown_equity)
     {
      reason="strategy_drawdown_projection";
      return false;
     }
   return true;
  }

bool RebuildDailyClosedTrades(int &trade_count,double &first_trade_net,double &day_closed_net,
                              bool &foreign_deal)
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
      if(position_id>0 && PositionSelectByTicket((ulong)position_id))
         continue; // partial close: position still open, not a completed trade
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

bool GlobalRiskGuards(string &reason)
  {
   if(g_halted)
     {
      reason="runtime_halt_latched";
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
      reason=(EffectiveConfirmedDays()>=InpMinQualifyingDays ? "phase_complete"
                                                            : "target_pending_days");
      return false;
     }
   return true;
  }

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

int RequestCountToday()
  {
   return g_request_count;
  }

bool CanSendNonEmergencyRequest()
  {
   if(g_request_count>=InpMaxNonEmergencyRequestsDay)
     {
      LogEvent("WARN","REQUEST_CAP_REACHED",
               StringFormat("%d/%d today",g_request_count,InpMaxNonEmergencyRequestsDay));
      return false;
     }
   datetime now=TimeTradeServer();
   if(g_last_request_time>0 && now-g_last_request_time<2)
      return false;
   return true;
  }

void CountTradeRequest(const string operation,const bool emergency)
  {
   if(!emergency)
      g_request_count++;
   g_last_request_time=TimeTradeServer();
   LogEvent("INFO","TRADE_REQUEST",operation+" emergency="+(emergency?"true":"false"));
  }

void Halt(const string reason)
  {
   g_halted=true;
   g_halt_reason=reason;
   LogEvent("HALT","EA_HALTED",reason);
   SaveState();
  }

// ============================================================================
// Order submission and exposure management (simplified screen variant)
// ============================================================================
bool SubmitCandidate(const TSC_Candidate &candidate)
  {
   int price_digits=(int)SymbolInfoInteger(candidate.symbol,SYMBOL_DIGITS);
   string detail=StringFormat("combo=%s side=%d entry=%s stop=%s target=%s vol=%s risk=%.2f target_net=%.2f range_pct=%.1f atr_pct=%.1f costR=%.3f",
            g_combo,(int)candidate.side,
            DoubleToString(candidate.entry,price_digits),
            DoubleToString(candidate.stop,price_digits),
            DoubleToString(candidate.target,price_digits),
            DoubleToString(candidate.volume,VolumeDigits(SymbolInfoDouble(candidate.symbol,SYMBOL_VOLUME_STEP))),
            candidate.cash_risk,candidate.target_net,
            candidate.range_percentile,candidate.atr_percentile,candidate.cost_to_r);
   LogEvent("INFO","VALID_CANDIDATE",detail);

   if(!InpEnableOrderSubmission)
     {
      LogEvent("INFO","DRY_RUN_NO_ORDER",detail);
      return true;
     }

   string recheck_reason="";
   datetime recheck_now=TimeTradeServer();
   MqlTick recheck_tick;
   double recheck_cost_to_r=DBL_MAX;
   double recheck_cash_loss=0.0;
   double recheck_slippage_reserve=0.0;
   double point=SymbolInfoDouble(candidate.symbol,SYMBOL_POINT);
   if(recheck_now+TSC_SAFETY_LEAD_SEC>=candidate.expiry_time ||
      recheck_now+TSC_SAFETY_LEAD_SEC>=g_entry_end)
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
   else
     {
      string ccy1,ccy2;
      SymbolCurrencies(candidate.symbol,ccy1,ccy2);
      if(IsRelevantNewsWindow(ccy1,ccy2,recheck_now,InpNewsBlockMinutes))
         recheck_reason="news_blackout";
      else if(!DailyStateAllowsEntry(recheck_reason))
         recheck_reason=(recheck_reason=="" ? "daily_state_recheck" : recheck_reason);
      else if(!GlobalRiskGuards(recheck_reason))
         recheck_reason=(recheck_reason=="" ? "global_risk_recheck" : recheck_reason);
      else if(!CanTakeCashRisk(recheck_cash_loss,recheck_slippage_reserve,recheck_reason))
         recheck_reason=(recheck_reason=="" ? "cash_risk_recheck" : recheck_reason);
     }
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
   string comment=StringFormat("TSC|%s|%d",g_combo,g_day_key);
   bool submitted=false;
   double volume=candidate.volume;
   datetime expiration=(datetime)(candidate.expiry_time);
   ulong request_started=GetTickCount64();
   if(candidate.side==TSC_PATTERN_LONG)
      submitted=g_trade.BuyLimit(volume,candidate.entry,g_symbol,candidate.stop,candidate.target,
                                 ORDER_TIME_SPECIFIED,expiration,comment);
   else
      submitted=g_trade.SellLimit(volume,candidate.entry,g_symbol,candidate.stop,candidate.target,
                                  ORDER_TIME_SPECIFIED,expiration,comment);
   ulong request_latency=GetTickCount64()-request_started;
   LogEvent("INFO","ORDER_REQUEST_LATENCY",StringFormat("milliseconds=%I64u",request_latency));
   if(request_latency>(ulong)InpMaxTradeRequestLatencyMs)
      LogEvent("ERROR","ORDER_REQUEST_LATENCY_BREACH",
               StringFormat("milliseconds=%I64u limit=%d",request_latency,InpMaxTradeRequestLatencyMs));
   if(!submitted || !TradeRetcodeAccepted(true,false))
     {
      LogEvent("ERROR","ORDER_SUBMIT_FAILED",
               StringFormat("ret=%u %s",g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription()));
      return false;
     }
   CountTradeRequest("submit_pending",false);
   g_last_trade_risk_cash=candidate.cash_risk;

   g_open.ticket=g_trade.ResultOrder();
   g_open.symbol=candidate.symbol;
   g_open.opened=0;
   g_open.open_price=candidate.entry;
   g_open.stop=candidate.stop;
   g_open.target=candidate.target;
   g_open.volume=candidate.volume;
   g_open.risk_cash=candidate.cash_risk;
   g_open.one_r_price=candidate.one_r_price;
   g_open.day_key=g_day_key;
   LogEvent("INFO","ORDER_SUBMITTED",
            StringFormat("ticket=%I64u %s %s vol=%s",g_open.ticket,
                         (candidate.side==TSC_PATTERN_LONG?"BUY_LIMIT":"SELL_LIMIT"),
                         g_symbol,DoubleToString(candidate.volume,2)));
   return true;
  }

bool DeleteOrder(const ulong ticket,const string reason,const bool emergency=true)
  {
   if(!InpEnableOrderSubmission)
      return false;
   if(!OrderSelect(ticket)) return true;
   // Emergency cleanup is never gated by the non-emergency request cap. It is
   // only per-ticket throttled so a retry storm cannot issue back-to-back
   // delete requests for the same order.
   if(emergency && !SafetyRequestDue(ticket,0,10)) return false;
   if(!emergency && !CanSendNonEmergencyRequest()) return false;
   CountTradeRequest(StringFormat("delete_order %I64u %s",ticket,reason),emergency);
   bool ok=g_trade.OrderDelete(ticket);
   ok=ok && TradeRetcodeAccepted(false,true);
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
      LogEvent("ERROR","ORDER_DELETE_FAILED",
               StringFormat("ticket=%I64u ret=%u %s",ticket,g_trade.ResultRetcode(),
                            g_trade.ResultRetcodeDescription()));
   else
      LogEvent("INFO","ORDER_DELETED",StringFormat("ticket=%I64u reason=%s",ticket,reason));
   return ok;
  }

bool ClosePosition(const ulong ticket,const string reason,const bool emergency=true)
  {
   if(!InpEnableOrderSubmission)
      return false;
   if(!PositionSelectByTicket(ticket)) return true;
   if(emergency && !SafetyRequestDue(ticket,1,10)) return false;
   if(!emergency && !CanSendNonEmergencyRequest()) return false;
   CountTradeRequest(StringFormat("close_position %I64u %s",ticket,reason),emergency);
   if(!g_trade.SetTypeFillingBySymbol(PositionGetString(POSITION_SYMBOL)))
     {
      LogEvent("ERROR","POSITION_CLOSE_FILLING_MODE_FAILED",StringFormat("ticket=%I64u",ticket));
      return false;
     }
   bool ok=g_trade.PositionClose(ticket,InpMaxDeviationPoints);
   ok=ok && TradeRetcodeAccepted(false,true);
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
      LogEvent("ERROR","POSITION_CLOSE_FAILED",
               StringFormat("ticket=%I64u ret=%u %s",ticket,g_trade.ResultRetcode(),
                            g_trade.ResultRetcodeDescription()));
   else
      LogEvent("INFO","POSITION_CLOSED",StringFormat("ticket=%I64u reason=%s",ticket,reason));
   return ok;
  }

// ============================================================================
// Safety request helpers (canonical parity; simplified to in-memory state)
// ============================================================================
bool SafetyRequestDue(const ulong ticket,const int slot,const int minimum_seconds=10)
  {
   datetime now=TimeTradeServer();
   if(g_emergency_last_ticket[slot]==ticket && now-g_emergency_last_time[slot]<minimum_seconds)
      return false;
   g_emergency_last_ticket[slot]=ticket;
   g_emergency_last_time[slot]=now;
   return true;
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

datetime LastTradingActivityTime()
  {
   datetime from=(g_state_created>0 ? g_state_created : TimeTradeServer()-365*86400);
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

// ============================================================================
// ManageExposure (simplified: no GV plan persistence, no identity locks)
// ============================================================================
void ManageExposure()
  {
   if(!InpEnableOrderSubmission)
      return;
   datetime now=TimeTradeServer();
   string ccy1,ccy2;
   SymbolCurrencies(g_symbol,ccy1,ccy2);

   // Foreign exposure: never trade around manual/foreign objects. Own-magic
   // exposure is cleaned; foreign objects are left alone but logged.
   if(HasForeignExposure())
     {
      if(now-g_last_foreign_exposure_log>=60)
        {
         g_last_foreign_exposure_log=now;
         LogEvent("ERROR","FOREIGN_EXPOSURE",
                  "manual or foreign orders/positions detected; own-magic exposure cleaned");
        }
      CancelAllPending("foreign_exposure_cleanup",true);
      CloseAllPositions("foreign_exposure_cleanup",true);
      return;
     }

   // Exposure invariant: at most one own pending entry or one own position.
   int own_pending=0;
   for(int i=0;i<OrdersTotal();i++)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0 || (long)OrderGetInteger(ORDER_MAGIC)!=InpMagic) continue;
      ENUM_ORDER_TYPE otype=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(IsPendingEntryType(otype))
         own_pending++;
     }
   int own_positions=0;
   for(int i=0;i<PositionsTotal();i++)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || (long)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      own_positions++;
     }
   if(own_pending>1 || own_positions>1 || (own_pending>0 && own_positions>0))
     {
      LogEvent("ERROR","EXPOSURE_INVARIANT_VIOLATED",
               StringFormat("pending=%d positions=%d",own_pending,own_positions));
      CancelAllPending("exposure_invariant",true);
      CloseAllPositions("exposure_invariant",true);
      return;
     }

   // The same rules that block new entries must also flatten exposure when
   // violated (floor breach, phase complete, drawdown shutdown, ...).
   string guard_reason;
   if(!GlobalRiskGuards(guard_reason))
     {
      CancelAllPending(guard_reason,true);
      CloseAllPositions(guard_reason,true);
      return;
     }

   // Pending order controls (one allowed; managed by plan fields).
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0) continue;
      if((long)OrderGetInteger(ORDER_MAGIC)!=InpMagic)
         continue;
      string symbol=OrderGetString(ORDER_SYMBOL);
      datetime expiration=(datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
      double entry=OrderGetDouble(ORDER_PRICE_OPEN);
      double sl=OrderGetDouble(ORDER_SL);
      double tp=OrderGetDouble(ORDER_TP);
      ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if((ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE)!=SYMBOL_TRADE_MODE_FULL)
        { DeleteOrder(ticket,"symbol_not_full_trade_mode",true); continue; }
      if(sl<=0.0 || tp<=0.0)
        { DeleteOrder(ticket,"pending_missing_visible_stop_or_target",true); continue; }
      bool expected_long=(g_open.stop<g_open.open_price);
      bool type_ok=((expected_long && type==ORDER_TYPE_BUY_LIMIT) ||
                    (!expected_long && type==ORDER_TYPE_SELL_LIMIT));
      bool plan_ok=(g_open.ticket==ticket && g_open.open_price>0.0 &&
                    (ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME)==ORDER_TIME_SPECIFIED &&
                    type_ok && PriceMatches(symbol,entry,g_open.open_price) &&
                    PriceMatches(symbol,sl,g_open.stop) && PriceMatches(symbol,tp,g_open.target) &&
                    VolumeMatches(symbol,OrderGetDouble(ORDER_VOLUME_CURRENT),g_open.volume) &&
                    StringFind(OrderGetString(ORDER_COMMENT),"TSC|")==0);
      if(!plan_ok)
        {
         LogEvent("WARN",
                  (g_open.ticket==ticket ? "PENDING_PLAN_MISMATCH" : "PENDING_NOT_OWNED"),
                  StringFormat("ticket=%I64u",ticket));
         DeleteOrder(ticket,
                     (g_open.ticket==ticket ? "pending_plan_mismatch" : "pending_not_owned"),true);
         continue;
        }

      if(expiration>0 && now>=expiration)
        { DeleteOrder(ticket,"expired",true); continue; }
      if(IsRelevantNewsWindow(ccy1,ccy2,now,InpNewsBlockMinutes))
        { DeleteOrder(ticket,"news_blackout",true); continue; }
      double one_r=(type==ORDER_TYPE_BUY_LIMIT ? entry+(entry-sl) : entry-(sl-entry));
      MqlTick tick;
      bool quote_valid=SymbolInfoTick(symbol,tick) && TickIsFresh(tick);
      if(!quote_valid)
        { DeleteOrder(ticket,"stale_quote",true); continue; }
      if(type==ORDER_TYPE_BUY_LIMIT && tick.bid>=one_r)
        { DeleteOrder(ticket,"theoretical_1R_without_fill",true); continue; }
      if(type==ORDER_TYPE_SELL_LIMIT && tick.ask<=one_r)
        { DeleteOrder(ticket,"theoretical_1R_without_fill",true); continue; }
      if(now+TSC_SAFETY_LEAD_SEC>=g_entry_end)
        { DeleteOrder(ticket,"session_end",true); continue; }
     }

   if(PositionsTotal()==0)
     {
      g_last_seen_position_ticket=0;
      return;
     }
   ulong pos_ticket=PositionGetTicket(0);
   if(pos_ticket==0)
     {
      g_last_seen_position_ticket=0;
      return;
     }
   string symbol=PositionGetString(POSITION_SYMBOL);
   ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   datetime opened=(datetime)PositionGetInteger(POSITION_TIME);
   double open_price=PositionGetDouble(POSITION_PRICE_OPEN);
   double sl=PositionGetDouble(POSITION_SL);
   double tp=PositionGetDouble(POSITION_TP);
   double position_volume=PositionGetDouble(POSITION_VOLUME);

   // Adoption: a pending order that fills keeps the same ticket, so the fill
   // must also be adopted when the plan is still marked "pending" (opened==0).
   bool same_plan=(g_open.ticket==pos_ticket && g_open.opened==0 && g_open.open_price>0.0);
   bool adopt=(g_open.ticket!=pos_ticket) || same_plan;
   if(adopt)
     {
      if(same_plan)
        {
         // Validate the fill against the submitted plan before adopting.
         double tick_size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
         if(tick_size<=0.0) tick_size=SymbolInfoDouble(symbol,SYMBOL_POINT);
         bool expected_long=(g_open.stop<g_open.open_price);
         bool side_ok=((expected_long && type==POSITION_TYPE_BUY) ||
                       (!expected_long && type==POSITION_TYPE_SELL));
         bool fill_not_worse=(type==POSITION_TYPE_BUY ?
                              open_price<=g_open.open_price+tick_size*0.10 :
                              open_price>=g_open.open_price-tick_size*0.10);
         if(!side_ok || !fill_not_worse ||
            !VolumeMatches(symbol,position_volume,g_open.volume))
           {
            LogEvent("ERROR","FILL_PLAN_MISMATCH",
                     StringFormat("ticket=%I64u entry=%s planned=%s vol=%s planned_vol=%s",
                                  pos_ticket,
                                  DoubleToString(open_price,5),
                                  DoubleToString(g_open.open_price,5),
                                  DoubleToString(position_volume,2),
                                  DoubleToString(g_open.volume,2)));
            ClosePosition(pos_ticket,"fill_plan_mismatch",true);
            return;
           }
        }
      double planned_risk=(same_plan ? g_open.risk_cash :
                           (g_last_trade_risk_cash>0.0 ? g_last_trade_risk_cash : 0.0));
      g_open.ticket=pos_ticket;
      g_open.symbol=symbol;
      g_open.opened=opened;
      g_open.open_price=open_price;
      g_open.stop=sl;
      g_open.target=tp;
      g_open.volume=position_volume;
      g_open.one_r_price=(type==POSITION_TYPE_BUY ?
                          NormalizePriceUp(symbol,open_price+MathAbs(open_price-sl)) :
                          NormalizePriceDown(symbol,open_price-MathAbs(sl-open_price)));
      g_open.risk_cash=planned_risk;
      g_open.day_key=ServerDayKey(opened);
      if(g_last_seen_position_ticket==0)
        {
         if(planned_risk>0.0)
           {
            WritePlanEntry(pos_ticket,planned_risk);
            g_today_fills++;
            g_last_trade_time=TimeTradeServer();
            LogEvent("INFO","POSITION_FILL_RECORDED",
                     StringFormat("ticket=%I64u risk=%.2f",pos_ticket,planned_risk));
           }
         else
            LogEvent("WARN","POSITION_ADOPTED_AFTER_RESTART",
                     StringFormat("ticket=%I64u entry=%s (risk unknown, plan not recorded)",
                                  pos_ticket,DoubleToString(open_price,5)));
        }
      g_last_seen_position_ticket=pos_ticket;
     }

   if(sl<=0.0 || tp<=0.0)
     {
      // Try to repair a broker-dropped stop from the known plan first.
      bool repaired=false;
      if(g_open.stop>0.0 && tp>0.0 && PriceMatches(symbol,tp,g_open.target))
        {
         if(SafetyRequestDue(pos_ticket,2,10) && CanSendNonEmergencyRequest())
           {
            CountTradeRequest("repair_missing_stop",true);
            bool repair_request=g_trade.PositionModify(pos_ticket,g_open.stop,tp) &&
                                TradeRetcodeAccepted(false,true);
            repaired=repair_request && PositionSelectByTicket(pos_ticket) &&
                     PriceMatches(symbol,PositionGetDouble(POSITION_SL),g_open.stop) &&
                     PriceMatches(symbol,PositionGetDouble(POSITION_TP),tp);
            if(repaired)
              {
               sl=PositionGetDouble(POSITION_SL);
               LogEvent("INFO","STOP_REPAIRED",StringFormat("ticket=%I64u",pos_ticket));
              }
           }
        }
      if(!repaired)
        { ClosePosition(pos_ticket,"missing_visible_stop_or_target",true); return; }
     }

   // One-R confirmation is re-derived from closed M5 bars after the actual
   // fill (reconstructs a confirmation missed during a disconnect).
   bool one_r_confirmed=false;
   double confirmed_price=g_open.one_r_price;
   if(confirmed_price>0.0 &&
      HasConfirmedOneRClose(symbol,opened,type,confirmed_price))
      one_r_confirmed=true;

   // Visible exit plan: target must match the plan and the stop must be the
   // original plan stop or a confirmed breakeven move.
   bool original_stop=(g_open.stop>0.0 && PriceMatches(symbol,sl,g_open.stop));
   bool confirmed_breakeven=(InpMoveStopToEntryAfter1R && one_r_confirmed &&
                             PriceMatches(symbol,sl,NormalizePriceToTick(symbol,open_price)));
   if(!(g_open.target>0.0 && PriceMatches(symbol,tp,g_open.target)) ||
      (!original_stop && !confirmed_breakeven))
     {
      ClosePosition(pos_ticket,"visible_exit_plan_mismatch",true);
      return;
     }

   datetime news_time;
   string news_title;
   if(UpcomingRelevantNews(ccy1,ccy2,now,InpNewsFlatMinutes,news_time,news_title))
     {
      ClosePosition(pos_ticket,"pre_news_flat "+news_title,true);
      return;
     }
   if(RecentRelevantNews(ccy1,ccy2,now,InpNewsBlockMinutes))
     {
      ClosePosition(pos_ticket,"post_news_recovery_flat",true);
      return;
     }
   datetime server_midnight=ServerMidnight(now)+86400;
   if(server_midnight-now<=InpRolloverFlatMinutes*60+TSC_SAFETY_LEAD_SEC)
     {
      ClosePosition(pos_ticket,"pre_rollover_flat",true);
      return;
     }

   // Friday flat (canonical parity): no exposure across the weekend.
   datetime utc_now=ServerToUtc(now);
   int ly,lm,ld,lkey;
   GetLocalDate(utc_now,TSC_WINDOW_LONDON,ly,lm,ld,lkey);
   MqlDateTime lp;
   TimeToStruct(utc_now+LondonUtcOffsetSeconds(utc_now),lp);
   datetime friday_flat_utc=LocalWallToUtc(ly,lm,ld,20,0,TSC_WINDOW_LONDON);
   if(lp.day_of_week==5 &&
      utc_now+TSC_SAFETY_LEAD_SEC>=friday_flat_utc)
     {
      ClosePosition(pos_ticket,"friday_flat",true);
      return;
     }

   if(now+TSC_SAFETY_LEAD_SEC>=g_entry_end)
     {
      ClosePosition(pos_ticket,"session_flat",true);
      return;
     }

   if(InpMoveStopToEntryAfter1R && one_r_confirmed)
     {
      bool needs_move=(type==POSITION_TYPE_BUY ? sl<open_price : sl>open_price);
      if(needs_move && SafetyRequestDue(pos_ticket,2,60) && CanSendNonEmergencyRequest())
        {
         CountTradeRequest("move_stop_to_entry",false);
         double breakeven_stop=NormalizePriceToTick(symbol,open_price);
         bool modified=g_trade.PositionModify(pos_ticket,breakeven_stop,tp) &&
                       TradeRetcodeAccepted(false,true);
         modified=modified && PositionSelectByTicket(pos_ticket) &&
                  PriceMatches(symbol,PositionGetDouble(POSITION_SL),breakeven_stop) &&
                  PriceMatches(symbol,PositionGetDouble(POSITION_TP),tp);
         if(!modified)
            LogEvent("ERROR","BREAKEVEN_MODIFY_FAILED",
                     StringFormat("ret=%u %s",g_trade.ResultRetcode(),
                                  g_trade.ResultRetcodeDescription()));
        }
     }

   if(InpTimeStopMinutes>0 && now-opened>=InpTimeStopMinutes*60 && !one_r_confirmed)
     {
      ClosePosition(pos_ticket,"time_stop_no_confirmed_1R",true);
      return;
     }
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

bool TradeRetcodeAccepted(const bool allow_placed=false,const bool allow_no_changes=true)
  {
   uint code=g_trade.ResultRetcode();
   return code==TRADE_RETCODE_DONE || code==TRADE_RETCODE_DONE_PARTIAL ||
          (allow_no_changes && code==TRADE_RETCODE_NO_CHANGES) ||
          (allow_placed && code==TRADE_RETCODE_PLACED);
  }

// ============================================================================
// Trade ledger: explicit plan-risk records so net R stays accurate across
// restarts (deal history does not store the planned cash risk per position).
// ============================================================================
string PlanFilePath()
  {
   return TscFileName("P")+".csv";
  }

string TradeFilePath()
  {
   return TscFileName("T")+".csv";
  }

bool LoadTradeLedger()
  {
   g_net_r_total=0.0;
   g_net_cash_total=0.0;
   ArrayResize(g_ledger_position_ids,0);
   int handle=FileOpen(TradeFilePath(),FILE_READ|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
   if(handle==INVALID_HANDLE)
      return true;
   FileReadString(handle); // header
   while(!FileIsEnding(handle))
     {
      string pos_s=FileReadString(handle);
      if(FileIsEnding(handle) && pos_s=="")
         break;
      string net_cash_s=FileReadString(handle);
      string net_r_s=FileReadString(handle);
      if(pos_s=="" || net_cash_s=="" || net_r_s=="")
         continue;
      g_net_cash_total+=StringToDouble(net_cash_s);
      g_net_r_total+=StringToDouble(net_r_s);
      long id=(long)StringToInteger(pos_s);
      if(id>0)
        {
         int n=ArraySize(g_ledger_position_ids);
         ArrayResize(g_ledger_position_ids,n+1);
         g_ledger_position_ids[n]=id;
        }
     }
   FileClose(handle);
   return true;
  }

bool WritePlanEntry(const ulong position_id,const double risk_cash)
  {
   if(position_id==0)
      return false;
   // Read the existing table into memory first, then rebuild the file from
   // scratch (FileOpen does NOT truncate: an in-place rewrite could leave a
   // stale tail that later reads as phantom plan rows).
   string rows[];
   ArrayResize(rows,0);
   int read_handle=FileOpen(PlanFilePath(),FILE_READ|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
   if(read_handle!=INVALID_HANDLE)
     {
      FileReadString(read_handle); // header
      while(!FileIsEnding(read_handle))
        {
         string pos_s=FileReadString(read_handle);
         if(FileIsEnding(read_handle) && pos_s=="")
            break;
         string risk_s=FileReadString(read_handle);
         if(pos_s=="" || risk_s=="")
            continue;
         if((ulong)StringToInteger(pos_s)==position_id)
            continue; // replaced/removed below
         int n=ArraySize(rows);
         ArrayResize(rows,n+1);
         rows[n]=pos_s+";"+risk_s;
        }
      FileClose(read_handle);
     }
   if(risk_cash>0.0)
     {
      int n=ArraySize(rows);
      ArrayResize(rows,n+1);
      rows[n]=StringFormat("%I64u;%.4f",position_id,risk_cash);
     }
   FileDelete(PlanFilePath());
   int handle=FileOpen(PlanFilePath(),FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
   if(handle==INVALID_HANDLE)
      return false;
   FileWrite(handle,"position_id","risk_cash");
   for(int i=0;i<ArraySize(rows);i++)
     {
      string fields[];
      if(StringSplit(rows[i],';',fields)>=2)
         FileWrite(handle,fields[0],fields[1]);
     }
   FileClose(handle);
   return true;
  }

bool ReadPlanRisk(const ulong position_id,double &risk_cash)
  {
   risk_cash=0.0;
   int handle=FileOpen(PlanFilePath(),FILE_READ|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
   if(handle==INVALID_HANDLE)
      return false;
   FileReadString(handle);
   while(!FileIsEnding(handle))
     {
      string pos_s=FileReadString(handle);
      if(FileIsEnding(handle) && pos_s=="")
         break;
      string risk_s=FileReadString(handle);
      if((ulong)StringToInteger(pos_s)==position_id)
        {
         risk_cash=StringToDouble(risk_s);
         FileClose(handle);
         return risk_cash>0.0;
        }
     }
   FileClose(handle);
   return false;
  }

void AppendClosedTrade(const ulong position_id,const double net_cash,const double net_r)
  {
   int handle=FileOpen(TradeFilePath(),FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
   if(handle==INVALID_HANDLE)
      return;
   if(FileSize(handle)==0)
      FileWrite(handle,"position_id","net_cash","net_r","closed_at","combo");
   FileSeek(handle,0,SEEK_END);
   FileWrite(handle,StringFormat("%I64u",position_id),
             DoubleToString(net_cash,4),DoubleToString(net_r,4),
             TimeToString(TimeTradeServer(),TIME_DATE|TIME_MINUTES),g_combo);
   FileClose(handle);
   g_net_cash_total+=net_cash;
   g_net_r_total+=net_r;
  }

bool PositionNetFromHistory(const long position_id,double &net,datetime &closed_time)
  {
   net=0.0;
   closed_time=0;
   if(position_id<=0 || !HistorySelect(g_state_created>1 ? g_state_created-1 : 0,
                                       TimeTradeServer()))
      return false;
   bool saw_out=false;
   for(int i=0;i<HistoryDealsTotal();i++)
     {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0 || HistoryDealGetInteger(deal,DEAL_POSITION_ID)!=position_id)
         continue;
      if(HistoryDealGetInteger(deal,DEAL_MAGIC)!=InpMagic)
         continue;
      ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
      if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY || entry==DEAL_ENTRY_INOUT)
        {
         net+=HistoryDealGetDouble(deal,DEAL_PROFIT)+
              HistoryDealGetDouble(deal,DEAL_COMMISSION)+
              HistoryDealGetDouble(deal,DEAL_SWAP)+
              HistoryDealGetDouble(deal,DEAL_FEE);
         datetime dt=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
         if(dt>closed_time) closed_time=dt;
         saw_out=true;
        }
     }
   return saw_out;
  }

// Reconcile any position that closed since the last check; the processed set
// is the trade ledger itself (ids never repeat because positions are unique).
void ReconcileClosedTrades()
  {
   if(!HistorySelect(g_state_created>1 ? g_state_created-1 : 0,TimeTradeServer()))
      return;
   long seen[];
   ArrayResize(seen,0);
   int total=HistoryDealsTotal();
   for(int i=0;i<total;i++)
     {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0) continue;
      if(HistoryDealGetInteger(deal,DEAL_MAGIC)!=InpMagic)
         continue;
      ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
      if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY && entry!=DEAL_ENTRY_INOUT)
         continue;
      long position_id=HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      if(position_id<=0) continue;
      bool already=false;
      for(int j=0;j<ArraySize(seen);j++)
         if(seen[j]==position_id) { already=true; break; }
      if(already) continue;
      // Never account a position that is already in the closed-trade ledger
      // (crash between append and plan removal would otherwise double count).
      for(int j=0;j<ArraySize(g_ledger_position_ids);j++)
         if(g_ledger_position_ids[j]==position_id) { already=true; break; }
      if(already) continue;
      int n=ArraySize(seen);
      ArrayResize(seen,n+1);
      seen[n]=position_id;

      // A partial close (DEAL_ENTRY_OUT on a still-open position) is not a
      // completed trade; wait for the position to leave the trade pool.
      if(PositionSelectByTicket((ulong)position_id))
         continue;

      double risk;
      if(!ReadPlanRisk((ulong)position_id,risk))
         continue; // not ours or already recorded without a plan
      double net;
      datetime closed_time;
      if(!PositionNetFromHistory(position_id,net,closed_time))
         continue;
      double net_r=(risk>0.0 ? net/risk : 0.0);
      // Remove the plan row first: if interrupted, the trade is skipped on
      // restart rather than double-accounted (the ledger id set is the guard).
      WritePlanEntry((ulong)position_id,0.0);
      AppendClosedTrade((ulong)position_id,net,net_r);
      int m=ArraySize(g_ledger_position_ids);
      ArrayResize(g_ledger_position_ids,m+1);
      g_ledger_position_ids[m]=position_id;
      if(closed_time>g_last_trade_time)
         g_last_trade_time=closed_time;
      LogEvent("INFO","TRADE_CLOSED_ACCOUNTED",
               StringFormat("position=%I64u net=%.2f net_r=%.3f risk=%.2f",
                            position_id,net,net_r,risk));
      SaveState();
     }
  }


// ============================================================================
// Daily rollover and qualifying-day accounting (ported rules)
// ============================================================================
bool MissedRolloverExposure(bool &history_ok)
  {
   history_ok=false;
   datetime now=TimeTradeServer();
   datetime from=(g_state_created>1 ? g_state_created-1 : 0);
   if(!HistorySelect(from,now))
      return false;
   history_ok=true;

   // A pending entry created on one server day and completed on a later day
   // was necessarily working across at least one rollover.
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

   // Reconstruct strategy position lifetimes: an entry opened before a
   // server midnight and exited after it crossed the rollover snapshot.
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
         StringFind(HistoryDealGetString(deal,DEAL_COMMENT),"TSC|")!=0)
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

void HandleRollover()
  {
   if(g_day_start_time<=0)
      return;
   datetime now=TimeTradeServer();
   int key=ServerDayKey(now);
   int new_week=ServerWeekKey(now);
   if(key==g_day_key && new_week==g_week_key)
      return;
   if(key<g_day_key)
     {
      LogEvent("ERROR","SERVER_DAY_REGRESSION",
               StringFormat("stored=%d current=%d",g_day_key,key));
      return;
     }

   bool rollover_history_ok=false;
   bool missed=MissedRolloverExposure(rollover_history_ok);
   if(!rollover_history_ok)
     {
      LogEvent("ERROR","ROLLOVER_HISTORY_UNAVAILABLE","qualifying-day not estimated");
      g_day_key=key;
      SaveState();
      return;
     }
   if(missed)
     {
      LogEvent("WARN","PROFITABLE_DAY_NOT_ESTIMATED","rollover exposure incident");
      g_day_key=key;
      SaveState();
      return;
     }

   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   bool exposure_now=HasAnyExposure();
   if(exposure_now)
     {
      // Never snapshot a pre-close balance as the new day; keep the higher
      // boundary for the official daily floor and defer the snapshot.
      double rollover_floor_base=MathMax(balance,equity);
      g_firm_daily_floor=MathMax(g_firm_daily_floor,rollover_floor_base*(1.0-InpDailyLossPercent/100.0));
      LogEvent("WARN","PROFITABLE_DAY_NOT_ESTIMATED","rollover exposure present; next clean rollover snapshots");
      g_day_key=key;
      SaveState();
      return;
     }

   if(g_prev_day_balance>0.0 &&
      g_day_start_time>0 && now-g_day_start_time<=36*3600)
     {
      double result=MathMin(balance,equity)-g_prev_day_balance;
      double threshold=InpPhaseInitialBalance*InpQualifyingDayPercent/100.0;
      if(result+0.0000001>=threshold)
        {
         g_qualifying_days++;
         LogEvent("INFO","ESTIMATED_PROFITABLE_DAY",
                  StringFormat("result=%.2f count=%d",result,g_qualifying_days));
        }
      else
         LogEvent("INFO","DAY_NOT_QUALIFYING",
                  StringFormat("result=%.2f threshold=%.2f",result,threshold));
     }
   else
      LogEvent("WARN","PROFITABLE_DAY_NOT_ESTIMATED","offline across more than one rollover");

   // Flatten-only snapshot point is official; reset day state.
   g_day_key=key;
   g_day_start_time=ServerMidnight(now);
   g_day_start_balance=balance;
   g_day_start_equity=equity;
   g_prev_day_balance=balance;
   double reconciled_daily_floor=MathMax(balance,equity)*(1.0-InpDailyLossPercent/100.0);
   g_firm_daily_floor=MathMax(g_firm_daily_floor,reconciled_daily_floor);
   g_request_count=0;
   if(new_week!=g_week_key)
     {
      g_week_key=new_week;
      g_week_start_balance=balance;
     }
   g_today_signals=0;
   g_today_candidates=0;
   g_today_fills=0;
   g_today_rejects=0;
   g_last_rejection="";
   string status=ChallengeStatus();
   AppendDailySummary(status);
   g_news_valid=LoadNewsCalendar();
   LogEvent("INFO","ROLLOVER_ACCOUNTED",
            StringFormat("day=%d balance=%.2f equity=%.2f qualifying=%d",
                         g_day_key,balance,equity,g_qualifying_days));
   SaveState();
  }

// ============================================================================
// Challenge status (The5ers-style preset; dashboard-facing)
// ============================================================================
string ChallengeStatus()
  {
   if(g_halted)
      return "HALTED:"+g_halt_reason;
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double target=PhaseTargetBalance();
   if(balance>=target)
     {
      int days=EffectiveConfirmedDays();
      if(days>=InpMinQualifyingDays)
         return "PASSED";
      return "TARGET_REACHED_DAYS_PENDING";
     }
   if(equity<=FirmOverallFloor())
      return "FAILED_OVERALL_FLOOR";
   if(equity<=g_firm_daily_floor)
      return "FAILED_DAILY_FLOOR";
   if(InpInactivityDays>0)
     {
      // Account-level activity: any executed buy/sell deal counts toward the
      // inactivity rule, not only fills recorded by this EA run (canonical).
      if(g_last_activity_check==0 ||
         TimeTradeServer()-g_last_activity_check>=3600)
        {
         datetime from_history=LastTradingActivityTime();
         if(from_history>g_last_trade_time)
            g_last_trade_time=from_history;
         g_last_activity_check=TimeTradeServer();
        }
      if(g_last_trade_time>1)
        {
         int idle_days=(int)((TimeTradeServer()-g_last_trade_time)/86400);
         if(idle_days>=InpInactivityDays)
            return "FAILED_INACTIVITY";
        }
     }
   return "ACTIVE";
  }

double PercentToTarget()
  {
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double target=PhaseTargetBalance();
   double initial=InpPhaseInitialBalance;
   if(target<=initial) return 0.0;
   return 100.0*(balance-initial)/(target-initial);
  }

// ============================================================================
// Signal scan
// ============================================================================
void ScanForSignals()
  {
   if(g_halted || HasAnyExposure() || g_consumed || !g_range_ready)
      return;
   string reason;
   if(!GlobalRiskGuards(reason))
     {
      LogEvent("WARN","ENTRY_BLOCKED",reason);
      return;
     }
   if(!DailyStateAllowsEntry(reason))
     {
      LogEvent("WARN","ENTRY_BLOCKED",reason);
      return;
     }
   if(!NewsCalendarCurrent())
      return;
   datetime now=TimeTradeServer();
   if(now<g_entry_start || now+TSC_SAFETY_LEAD_SEC>=g_entry_end)
      return;

   if(!DetectPattern(g_candidate))
     {
      if(g_candidate.rejection!="" && g_candidate.rejection!="sweep_waiting_for_reclaim" &&
         g_candidate.rejection!="reclaim_waiting_for_displacement" &&
         g_candidate.rejection!="no_sweep_event" &&
         g_candidate.rejection!="session_bars_unavailable" &&
         g_candidate.rejection!="atr_unavailable")
        {
         g_today_rejects++;
         g_last_rejection=g_candidate.rejection;
         LogEvent("INFO","PATTERN_REJECTED",g_candidate.rejection);
        }
      return;
     }
   // Canonical rule: one detected event consumes the session for the civil
   // day, regardless of a later gate rejection.
   g_consumed=true;
   g_today_signals++;
   if(g_candidate.rejection!="")
     {
      g_today_rejects++;
      g_last_rejection=g_candidate.rejection;
      LogEvent("INFO","CANDIDATE_REJECTED",g_candidate.rejection);
      return;
     }
   if(!PrepareCandidate(g_candidate))
     {
      g_today_rejects++;
      g_last_rejection=g_candidate.rejection;
      LogEvent("INFO","CANDIDATE_REJECTED",g_candidate.rejection);
      return;
     }
   g_today_candidates++;
   SubmitCandidate(g_candidate);
  }

// ============================================================================
// Dashboard (on-chart panel; simple and terminal-local)
// ============================================================================
string DashName(const string suffix)
  {
   return "TSC_"+g_combo+"_"+suffix;
  }

bool DashSet(const string suffix,const string text,const color clr,const int row)
  {
   string name=DashName(suffix);
   if(!ObjectCreate(0,name,OBJ_LABEL,0,0,0))
      if(ObjectFind(0,name)<0)
         return false;
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,12);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,24+row*16);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,9);
   ObjectSetInteger(0,name,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   return true;
  }

void RemoveDashboard()
  {
   string prefix="TSC_"+g_combo+"_";
   for(int i=ObjectsTotal(0,-1,-1)-1;i>=0;i--)
     {
      string name=ObjectName(0,i);
      if(StringFind(name,prefix)==0)
         ObjectDelete(0,name);
     }
  }

void UpdateDashboard()
  {
   if(!InpDashboardShow)
     {
      RemoveDashboard();
      return;
     }
   int row=0;
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   string status=ChallengeStatus();
   color status_clr=clrLime;
   if(StringFind(status,"FAILED")==0) status_clr=clrTomato;
   else if(StringFind(status,"PASSED")==0) status_clr=clrGold;
   else if(StringFind(status,"HALTED")==0 || StringFind(status,"DRY_RUN_HALTED")==0)
      status_clr=clrOrange;
   else if(StringFind(status,"DRY_RUN")==0) status_clr=clrSilver;

   DashSet("hdr",StringFormat("TRIAD SCREEN %s | %s",TSC_BUILD_ID,g_combo),clrAqua,row++);
   DashSet("acct",StringFormat("Account %I64d @ %s  %s",
            AccountInfoInteger(ACCOUNT_LOGIN),
            AccountInfoString(ACCOUNT_SERVER),
            AccountInfoString(ACCOUNT_CURRENCY)),clrWhite,row++);
   DashSet("sym",StringFormat("Symbol=%s Window=%s  ConfigHash=%08X",
            g_symbol,(g_window==TSC_WINDOW_LONDON?"LONDON":"NEW_YORK"),ConfigHash()),
            clrWhite,row++);
   DashSet("sess",StringFormat("Range %s..%s  Entry %s..%s",
            (g_range_ready ? TimeToString(g_range_start,TIME_MINUTES) : "--:--"),
            (g_range_ready ? TimeToString(g_range_end,TIME_MINUTES) : "--:--"),
            TimeToString(g_entry_start,TIME_MINUTES),
            TimeToString(g_entry_end,TIME_MINUTES)),clrWhite,row++);

   string status_line=StringFormat("STATUS: %s%s",status,
            (InpEnableOrderSubmission ? "" : "  (DRY RUN - orders disabled)"));
   DashSet("st",status_line,status_clr,row++);
   DashSet("ch",StringFormat("Phase %d  Balance $%.2f  Equity $%.2f  Target $%.2f",
            InpChallengePhase,balance,equity,PhaseTargetBalance()),clrWhite,row++);
   DashSet("pr",StringFormat("Progress %.1f%%  Qualifying days %d/%d  Confirmed(dash) %d",
            PercentToTarget(),g_qualifying_days,InpMinQualifyingDays,
            InpDashboardConfirmedDays),clrWhite,row++);
   DashSet("fl",StringFormat("Daily floor $%.2f  Overall floor $%.2f  Reserve $%.2f",
            g_firm_daily_floor,FirmOverallFloor(),
            FirmReserveCash(g_last_trade_risk_cash)),clrWhite,row++);

   int trade_count;
   double first_net,day_closed_net;
   bool foreign_deal;
   bool daily_ok=RebuildDailyClosedTrades(trade_count,first_net,day_closed_net,foreign_deal);
   DashSet("day",StringFormat("Today: closed=%d net=$%.2f  floor=$%.2f",
            trade_count,day_closed_net,g_day_start_balance-InpPhaseInitialBalance*
            InpInternalDailyStopPercent/100.0),clrWhite,row++);
   int pending_count=PendingEntryCount();
   int pos_count=PositionsTotal();
   DashSet("exp",StringFormat("Pending=%d Positions=%d  Signals=%d Candidates=%d Fills=%d Rejects=%d",
            pending_count,pos_count,g_today_signals,g_today_candidates,
            g_today_fills,g_today_rejects),clrWhite,row++);
   DashSet("rej",StringFormat("Last rejection: %s",(g_last_rejection==""?"-":g_last_rejection)),
            clrSilver,row++);
   DashSet("led",StringFormat("Ledger: net_r=%.3f  net_cash=$%.2f",g_net_r_total,g_net_cash_total),
            clrWhite,row++);
   if(pos_count>0)
     {
      ulong pos_ticket=PositionGetTicket(0);
      if(pos_ticket>0 && PositionSelectByTicket(pos_ticket))
        {
         double open_pnl=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
         DashSet("pos",StringFormat("Open: %s  pnl=$%.2f  sl=%s  tp=%s",
                  (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?"BUY":"SELL"),
                  open_pnl,
                  DoubleToString(PositionGetDouble(POSITION_SL),5),
                  DoubleToString(PositionGetDouble(POSITION_TP),5)),
                  clrWhite,row++);
        }
     }
   DashSet("set",StringFormat("Profile %s risk=%.2f%% target=%.2fR timestop=%d BE=%s",
            (InpProfile==TSC_PROFILE_A_040_R150?"A":
             InpProfile==TSC_PROFILE_B_035_R175?"B":
             InpProfile==TSC_PROFILE_C_030_R200?"C":"D"),
            SelectedBaseRiskFraction()*100.0,SelectedTargetR(),InpTimeStopMinutes,
            (InpMoveStopToEntryAfter1R?"on":"off")),clrWhite,row++);
   DashSet("news",StringFormat("Calendar: %s  coverage %s",
            (InpRequireNewsCalendar?(g_news_valid?"OK":"STALE/LOADING"):"DISABLED"),
            (g_news_coverage_end_utc>0?
             TimeToString(g_news_coverage_end_utc,TIME_DATE|TIME_MINUTES):"-")),clrSilver,row++);
   DashSet("warn",StringFormat("ORDER SUBMISSION %s",
            (InpEnableOrderSubmission?"ENABLED (demo only)":"DISABLED")),
            (InpEnableOrderSubmission?clrGold:clrOrange),row++);
   ChartRedraw();
  }

// ============================================================================
// Entry point and lifecycle
// ============================================================================
int OnInit()
  {
   g_symbol=InpSymbol;
   g_window=InpWindow;
   g_combo=(InpComboLabel=="" ?
            StringFormat("%s_%s",g_symbol,
                         (g_window==TSC_WINDOW_LONDON?"LON":"NY")) : InpComboLabel);

   if(!SymbolSupported(g_symbol) || !SymbolSelect(g_symbol,true))
     {
      LogEvent("ERROR","SYMBOL_UNSUPPORTED",
               StringFormat("symbol=%s supported: %s",g_symbol,
                            (SymbolSupported(g_symbol)?"yes":"no")));
      Print("[ERROR] TSC_INIT | unsupported or unavailable symbol: ",g_symbol);
      return INIT_FAILED;
     }
   if(SymbolInfoInteger(g_symbol,SYMBOL_TRADE_MODE)==SYMBOL_TRADE_MODE_DISABLED)
     {
      LogEvent("ERROR","SYMBOL_TRADE_MODE",StringFormat("%s disabled for trading",g_symbol));
      return INIT_FAILED;
     }
   if((int)InpChallengePhase!=(int)TSC_PHASE_1 &&
      (int)InpChallengePhase!=(int)TSC_PHASE_2)
     {
      Print("[ERROR] TSC_INIT | InpChallengePhase must be 1 or 2");
      return INIT_FAILED;
     }
   if(InpPhaseInitialBalance<=0.0)
     {
      Print("[ERROR] TSC_INIT | InpPhaseInitialBalance must be positive");
      return INIT_FAILED;
     }
   if(MathAbs(InpPhaseInitialBalance-AccountInfoDouble(ACCOUNT_BALANCE))>0.01 &&
      !IsTesterMode())
     LogEvent("WARN","BALANCE_MISMATCH",
              StringFormat("configured initial=%.2f account=%.2f",
                           InpPhaseInitialBalance,AccountInfoDouble(ACCOUNT_BALANCE)));
   if(InpExpectedAccountCurrency!="" && !IsTesterMode() &&
      AccountInfoString(ACCOUNT_CURRENCY)!=InpExpectedAccountCurrency)
     LogEvent("WARN","ACCOUNT_CURRENCY_MISMATCH",
              StringFormat("configured=%s account=%s",
                           InpExpectedAccountCurrency,
                           AccountInfoString(ACCOUNT_CURRENCY)));

   g_atr_handle=iATR(g_symbol,PERIOD_M15,14);
   if(g_atr_handle==INVALID_HANDLE)
     {
      LogEvent("ERROR","ATR_HANDLE_FAILED",g_symbol);
      return INIT_FAILED;
     }

   g_news_valid=LoadNewsCalendar();

   // Load persisted state or initialize a fresh day. A phase change on a
   // state-bearing file must be explicit, never silent.
   int probe=FileOpen(StateFilePath(),FILE_READ|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
   bool state_file_exists=(probe!=INVALID_HANDLE);
   if(state_file_exists)
      FileClose(probe);
   bool loaded=LoadState();
   if(state_file_exists && !loaded)
     {
      if(InpAllowPhaseReset && FileDelete(StateFilePath()))
        {
         LogEvent("WARN","STATE_RESET_REQUESTED",
                  StringFormat("combo=%s phase=%d state file removed",g_combo,InpChallengePhase));
         loaded=false;
        }
      else
        {
         LogEvent("HALT","STATE_LOAD_MISMATCH",
                  StringFormat("state file exists but does not match combo=%s phase=%d",
                               g_combo,InpChallengePhase));
         return INIT_FAILED;
        }
     }
   if(!loaded)
     {
      datetime now=TimeTradeServer();
      g_day_key=ServerDayKey(now);
      g_day_start_time=ServerMidnight(now);
      g_day_start_balance=AccountInfoDouble(ACCOUNT_BALANCE);
      g_day_start_equity=AccountInfoDouble(ACCOUNT_EQUITY);
      g_prev_day_balance=g_day_start_balance;
      g_firm_daily_floor=MathMax(g_day_start_balance,g_day_start_equity)*
                         (1.0-InpDailyLossPercent/100.0);
      g_week_key=ServerWeekKey(now);
      g_week_start_balance=g_day_start_balance;
      g_high_water=g_day_start_balance;
      g_qualifying_days=0;
      g_state_created=now;
      g_stored_phase=InpChallengePhase;
      g_last_trade_time=0;
      LogEvent("INFO","STATE_INITIALIZED",
               StringFormat("combo=%s day=%d balance=%.2f",g_combo,g_day_key,
                            g_day_start_balance));
     }
   else
     {
      // Phase match is guaranteed here (LoadState rejects otherwise), so the
      // stored phase always equals the configured phase.
      g_stored_phase=InpChallengePhase;
     }

   LoadTradeLedger();
   g_high_water=MathMax(g_high_water,AccountInfoDouble(ACCOUNT_BALANCE));

   RefreshSession(TimeTradeServer());

   if(InpDashboardShow)
     EventSetTimer(MathMax(1,InpDashboardRefreshSeconds));
   LogEvent("INFO","EA_INIT_OK",
            StringFormat("combo=%s build=%s hash=%08X",g_combo,TSC_BUILD_ID,ConfigHash()));
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(InpDashboardShow)
      RemoveDashboard();
   // Canonical parity: an intentional detach must not strand managed exposure.
   // A terminal shutdown (REASON_CLOSE) or init failure keeps visible broker
   // exits and the restart plan.
   if(InpEnableOrderSubmission && g_day_key!=0 &&
      reason!=REASON_CLOSE && reason!=REASON_INITFAILED && HasAnyExposure())
     {
      LogEvent("WARN","DEINIT_EXPOSURE_CLEANUP",IntegerToString(reason));
      CancelAllPending("deinitialization_with_exposure",true);
      CloseAllPositions("deinitialization_with_exposure",true);
     }
   if(g_atr_handle!=INVALID_HANDLE)
     {
      IndicatorRelease(g_atr_handle);
      g_atr_handle=INVALID_HANDLE;
     }
   SaveState();
   LogEvent("INFO","EA_DEINIT",IntegerToString(reason));
  }

void OnTick()
  {
   datetime now=TimeTradeServer();
   if(g_day_key==0)
      return;

   HandleRollover();

   // Keep high water current outside the rollover path. The canonical EA only
   // refreshes the high-water reference while flat so a loading/position phase
   // cannot distort the strategy drawdown basis.
   if(!HasAnyExposure())
     {
      double balance=AccountInfoDouble(ACCOUNT_BALANCE);
      if(balance>g_high_water)
        {
         g_high_water=balance;
         SaveState();
        }
     }

   RefreshSession(now);
   if(g_halted)
     {
      LogEvent("WARN","TICK_SKIPPED_HALTED",g_halt_reason);
      UpdateDashboard();
      return;
     }

   ReconcileClosedTrades();
   ManageExposure();
   ScanForSignals();
   UpdateDashboard();
  }

void OnTimer()
  {
   UpdateDashboard();
  }
