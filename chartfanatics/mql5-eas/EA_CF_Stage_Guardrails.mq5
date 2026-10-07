//+------------------------------------------------------------------+
//|                                     EA_CF_Stage_Guardrails.mq5   |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| ChartFanatics: "From Novice to Expert: 5-Stage Trader Framework"  |
//| Card    : chartfanatics/todos/5-stage-trading-framework.md  (#01) |
//| Source  : chartfanatics/pdf/5-stage-trading-framework.pdf         |
//| Magic   : 3207                                                    |
//|                                                                  |
//| READ THIS FIRST - what this document is and is not:               |
//|                                                                  |
//| The playbook is a trader-DEVELOPMENT framework (Umar Ashraf).  It |
//| contains no entry, no exit, no stop, no target, no instrument and |
//| no timeframe rule anywhere - it describes five stages of a         |
//| trader's progression (novice -> pro), what to do in each, and the  |
//| mindset traps of each.  Writing an entry EA from it would be       |
//| inventing rules the document does not contain.                    |
//|                                                                  |
//| What it DOES contain is checkable discipline, and that is what     |
//| this EA implements.  It is a PROCESS MONITOR, not a strategy:      |
//|                                                                  |
//|   * it never opens, sizes or closes a position (AllowTrading()     |
//|     and BuildPlan() both refuse - by design, not by omission);     |
//|   * it reads the ACCOUNT's own deal history (every magic, not just |
//|     its own) and holds the trader to the stage's rules:            |
//|        - "cut-off rules"            -> daily loss cut-off breach   |
//|        - "Narrow your focus to      -> daily trade-count cap       |
//|          only 1-2 main setups"        (from the stage policy)      |
//|        - stage-4 trap "revenge      -> an entry within N minutes   |
//|          trade after a loss"          of a losing close            |
//|        - "Sizing up too fast"       -> an entry much larger than   |
//|                                         the day's earlier entries  |
//|        - "Breaking rules after a    -> a loss streak beyond the    |
//|          few losing trades"            stage's pause threshold      |
//|   * "Journaling is not optional": it writes a daily journal CSV     |
//|     (summary rows at rollover/deinit, one row per breach type),     |
//|     which is the document's own closing thought made mechanical.    |
//|                                                                  |
//| The per-stage risk posture it reports against comes from the        |
//| engine helper `EA_ApplyStagePolicy()` (EACore.mqh), so the stage    |
//| table lives in exactly one place - the six playbook EAs in this     |
//| folder call the same helper to tighten their own risk.              |
//|                                                                  |
//| This EA is the "mirror" the document asks the reader to hold up:    |
//| "Ask yourself honestly: what stage am I actually in, and am I       |
//| doing the work that stage requires?"                                |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics 5-Stage framework - process guardrails and journal (never trades)"

#include "..\..\Include\EACommon.mqh"

//--- identity
input string            InpSymbolsToTrade   = "EURUSD";             // Unused for trading: the engine needs one tradable symbol to init
input ulong             InpMagicNumber      = 3207;                 // UNIQUE MAGIC NUMBER (identity only - this EA never trades)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;        // Log verbosity
//--- the stage being mirrored (1 novice .. 5 pro) - drives the caps from EA_ApplyStagePolicy()
input int    InpStage              = 3;      // 5-Stage framework stage the account is being held to
//--- checkable rules
input double InpDailyLossCutoffPct = 1.50;   // "cut-off rules": flag a day that loses more than this % (document gives no number)
input int    InpRevengeWindowMin   = 30;     // Stage-4 trap: entry within N minutes of a losing close
input double InpSizeJumpRatio      = 1.50;   // "Sizing up too fast": entry bigger than N x the day's average entry
input int    InpLossStreakFlag     = 3;      // Fallback streak threshold when the stage policy sets none
//--- output
input string InpJournalFile        = "cf_stage_journal.csv";  // MQL5/Files/ journal ("journaling is not optional")

//+------------------------------------------------------------------+
//| One day of account-wide trade statistics                          |
//+------------------------------------------------------------------+
struct SCfDayStats
{
   int      entries;      // position-opening deals (all magics)
   int      closes;       // closing deals
   int      wins;
   int      losses;
   int      maxStreak;    // longest run of losing closes in the day
   double   pl;           // realised P/L including swap and commission
   bool     revengeEntry; // an entry within InpRevengeWindowMin of a losing close
   bool     sizeJump;     // an entry above InpSizeJumpRatio x the day's earlier average
   datetime dayStart;

   void Reset()
   {
      entries = 0; closes = 0; wins = 0; losses = 0; maxStreak = 0;
      pl = 0.0; revengeEntry = false; sizeJump = false; dayStart = 0;
   }
};

//+------------------------------------------------------------------+
//| Strategy class - a monitor that is deliberately not a trader      |
//+------------------------------------------------------------------+
class CCfStageGuardrails : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_STAGE_GUARDRAILS";
      cfg.sourceDoc             = "chartfanatics/pdf/5-stage-trading-framework.pdf (card #01)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = 0.0;          // never sizes a position
      cfg.signalTimeframe       = PERIOD_M15;
      cfg.signalOnNewBarOnly    = true;
      cfg.maxOpenPositions      = 0;            // nothing to open
      cfg.maxTradesPerDay       = 0;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.newsFilter            = false;
      cfg.ledgerEnabled         = false;        // its journal is the deliverable, not the engine ledger
      cfg.logLevel              = InpLogLevel;

      //--- read the stage table from the ONE place that defines it.  A scratch settings block
      //--- is run through the engine helper, so this EA cannot drift from the policy the
      //--- playbook EAs apply to their own risk.
      SEASettings policy;
      policy.Reset();
      policy.riskPct            = 1.0;
      policy.maxTradesPerDay    = 0;
      policy.dayLockAfterLosses = 0;
      policy.lossStreakPause    = 0;
      EA_ApplyStagePolicy(policy, InpStage);
      m_capTradesPerDay = policy.maxTradesPerDay;                     // 0 = the stage sets no cap
      m_streakThreshold = (policy.lossStreakPause > 0) ? policy.lossStreakPause : InpLossStreakFlag;
   }

   void OnInitStrategy()
   {
      m_lastCheck  = 0;
      m_dayStart   = 0;
      m_breachMask = 0;
      m_lastLossPct = 0.0;
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "process monitor active: stage %d (trade cap %d/day, streak pause %d, daily loss cut-off %.2f%%)",
             InpStage, m_capTradesPerDay, m_streakThreshold, InpDailyLossCutoffPct), true);
      EA_Log(EA_LOG_EVENTS, "this EA never opens positions - it journals and flags discipline breaches", true);
   }

   void OnDeinitStrategy()
   {
      //--- "Journaling is not optional": never lose the partial day on a chart unload
      if(m_dayStart <= 0) return;
      SCfDayStats st;
      if(!SweepDay(m_dayStart, st)) return;
      JournalRow(m_dayStart, "SUMMARY", st, "partial - written at deinit");
   }

   //--- never trades, and says so instead of merely failing to find a signal
   bool AllowTrading(SEAContext &ctx) { return false; }
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan) { plan.Reset(); return false; }

   //--- the monitor: one account-wide sweep per minute, never per tick
   void Manage(SEAContext &ctx)
   {
      datetime now = TimeTradeServer();
      if(m_lastCheck > 0 && now - m_lastCheck < 60) return;
      m_lastCheck = now;

      datetime todayStart = ServerDayStart(now);

      //--- day rollover: close out the finished day before starting the new one
      if(m_dayStart > 0 && todayStart > m_dayStart)
      {
         SCfDayStats finished;
         if(SweepDay(m_dayStart, finished))
            JournalRow(m_dayStart, "SUMMARY", finished, "day closed");
         m_breachMask = 0;
      }
      m_dayStart = todayStart;

      SCfDayStats st;
      if(!SweepDay(todayStart, st)) return;
      CheckBreaches(st);
   }

private:
   int      m_capTradesPerDay;
   int      m_streakThreshold;
   datetime m_lastCheck;
   datetime m_dayStart;
   int      m_breachMask;      // one log line per breach type per day (never per tick)
   double   m_lastLossPct;

   //--- midnight of the current broker-server day
   datetime ServerDayStart(const datetime serverNow)
   {
      MqlDateTime dt;
      if(!TimeToStruct(serverNow, dt)) return 0;
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      return StructToTime(dt);
   }

   //--- account-wide day statistics: every magic, every symbol, read-only
   bool SweepDay(const datetime dayStart, SCfDayStats &st)
   {
      st.Reset();
      st.dayStart = dayStart;
      if(dayStart <= 0) return false;
      if(!HistorySelect(dayStart, TimeTradeServer() + 60)) return false;

      double volSum     = 0.0;      // sum of volumes of the entries seen so far today
      int    nEntries   = 0;
      int    streak     = 0;
      datetime lastLossClose = 0;

      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         long type = HistoryDealGetInteger(t, DEAL_TYPE);
         if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL) continue;   // skip balance / credit rows

         long entryKind = HistoryDealGetInteger(t, DEAL_ENTRY);
         datetime dealTime = (datetime)HistoryDealGetInteger(t, DEAL_TIME);

         if(entryKind == DEAL_ENTRY_IN)
         {
            nEntries++;
            double vol = HistoryDealGetDouble(t, DEAL_VOLUME);
            //--- "Sizing up too fast": this entry against the day's earlier average
            if(nEntries > 1 && volSum > 0.0 && vol > InpSizeJumpRatio * (volSum / (double)(nEntries - 1)))
               st.sizeJump = true;
            //--- stage-4 trap "revenge trade after a loss"
            if(lastLossClose > 0 && dealTime - lastLossClose <= (datetime)(InpRevengeWindowMin * 60))
               st.revengeEntry = true;
            volSum += vol;
            st.entries++;
            continue;
         }

         if(entryKind != DEAL_ENTRY_OUT && entryKind != DEAL_ENTRY_OUT_BY &&
            entryKind != DEAL_ENTRY_INOUT) continue;

         double p = HistoryDealGetDouble(t, DEAL_PROFIT) +
                    HistoryDealGetDouble(t, DEAL_SWAP) +
                    HistoryDealGetDouble(t, DEAL_COMMISSION);
         st.pl += p;
         st.closes++;
         if(p < 0.0)
         {
            st.losses++;
            streak++;
            if(streak > st.maxStreak) st.maxStreak = streak;
            lastLossClose = dealTime;
         }
         else if(p > 0.0)
         {
            st.wins++;
            streak = 0;
         }
      }
      return true;
   }

   //--- the account's daily loss against its own day-start balance, in percent
   double DayLossPct(const SCfDayStats &st)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
      double dayStartBalance = balance - st.pl;          // closed P/L came out of this day's start
      if(dayStartBalance <= 0.0) return 0.0;
      return (equity - dayStartBalance) / dayStartBalance * 100.0;
   }

   void CheckBreaches(const SCfDayStats &st)
   {
      double lossPct = DayLossPct(st);
      m_lastLossPct  = lossPct;

      if(m_capTradesPerDay > 0 && st.entries > m_capTradesPerDay)
         Breach(1, st, lossPct, StringFormat("%d entries today vs the stage %d cap - \"narrow your focus to only 1-2 main setups\"",
                                             st.entries, m_capTradesPerDay));
      if(lossPct <= -InpDailyLossCutoffPct)
         Breach(2, st, lossPct, StringFormat("daily loss %.2f%% breaches the %.2f%% cut-off rule",
                                             lossPct, InpDailyLossCutoffPct));
      if(st.revengeEntry)
         Breach(4, st, lossPct, StringFormat("entry within %d minutes of a losing close (stage-4 trap: revenge trading)",
                                             InpRevengeWindowMin));
      if(st.sizeJump)
         Breach(8, st, lossPct, StringFormat("entry above %.2fx the day's earlier average size (\"sizing up too fast\")",
                                             InpSizeJumpRatio));
      if(m_streakThreshold > 0 && st.maxStreak >= m_streakThreshold)
         Breach(16, st, lossPct, StringFormat("%d consecutive losing trades - \"breaking rules after a few losing trades\"",
                                              st.maxStreak));
   }

   //--- one log line and one journal row per breach type per day (never per tick)
   void Breach(const int flag, const SCfDayStats &st, const double lossPct, const string note)
   {
      if((m_breachMask & flag) != 0) return;
      m_breachMask |= flag;
      EA_Log(EA_LOG_EVENTS, "discipline breach: " + note, true);
      JournalRow(m_dayStart, "BREACH", st, note + StringFormat(" | day pl %.2f | loss %.2f%%", st.pl, lossPct));
   }

   //--- the journal: append-only CSV in MQL5/Files
   void JournalRow(const datetime day, const string kind, const SCfDayStats &st, const string note)
   {
      if(MQLInfoInteger(MQL_OPTIMIZATION)) return;
      int fh = FileOpen(InpJournalFile, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
      if(fh == INVALID_HANDLE)
      {
         EA_Log(EA_LOG_ERRORS, StringFormat("journal open failed (%d) - check MQL5\\Files permissions",
                                            GetLastError()), true);
         return;
      }
      FileSeek(fh, 0, SEEK_END);
      if(FileTell(fh) == 0)
         FileWrite(fh, "date", "kind", "entries", "closes", "wins", "losses", "pl", "max_loss_streak",
                   "stage", "entry_cap", "loss_pct", "note");
      FileWrite(fh,
                TimeToString(day, TIME_DATE),
                kind,
                IntegerToString(st.entries),
                IntegerToString(st.closes),
                IntegerToString(st.wins),
                IntegerToString(st.losses),
                DoubleToString(st.pl, 2),
                IntegerToString(st.maxStreak),
                IntegerToString(InpStage),
                IntegerToString(m_capTradesPerDay),
                DoubleToString(DayLossPct(st), 2),
                note);
      FileClose(fh);
   }
};

CCfStageGuardrails g_cfStageGuardrails;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfStageGuardrails);
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
