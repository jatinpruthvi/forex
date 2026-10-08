//+------------------------------------------------------------------+
//|                                    EA_CF_PsychGuardrails.mq5     |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| ChartFanatics: "Psychology MasterClass" (Jared Tendler)           |
//| Card    : chartfanatics/todos/full-psychology-masterclass.md (#12)|
//| Source  : chartfanatics/pdf/full-psychology-masterclass.pdf       |
//| Magic   : 3216                                                    |
//|                                                                  |
//| READ THIS FIRST - what this document is and is not:               |
//|                                                                  |
//| The masterclass is a TRADING-PSYCHOLOGY document.  It contains no |
//| entry, exit, stop, target, instrument or timeframe rule anywhere. |
//| Writing an entry EA from it would be inventing rules the document |
//| does not contain.                                                 |
//|                                                                  |
//| What it DOES contain is checkable behaviour, and that is what this|
//| EA mechanizes.  It is a PROCESS MONITOR, not a strategy:          |
//|                                                                  |
//|   * it never opens, sizes or closes a position (AllowTrading()    |
//|     and BuildPlan() both refuse - by design, not by omission);    |
//|   * it reads the ACCOUNT's own deal history (every magic) and     |
//|     maps the masterclass's mental model onto observable events:   |
//|                                                                  |
//|     "Progressive shutdown" - frustration compounds.  The day is   |
//|     replayed through a graded state machine, the 60%-vs-100%      |
//|     idea made mechanical:                                         |
//|        1 loss  -> CAUTION    ("reduce activity, be more           |
//|                               selective, or slow down")           |
//|        2 losses-> COOLDOWN   ("set a limit ... a 15-minute break")|
//|        a trade while the break is running -> LIMIT BREACH ->      |
//|                    "if you break your own limit, your session is  |
//|                     over" -> session locked for the day           |
//|        3 losses-> session over (emotional EV: "sometimes the      |
//|                   smartest trade is no trade at all")             |
//|                                                                  |
//|     "Emotional carryover" - a red yesterday raises today's        |
//|     baseline: thresholds shift one loss earlier and a CARRYOVER   |
//|     row is journalled before the session.                         |
//|                                                                  |
//|     The zone map's early-warning signs get mechanical proxies:    |
//|        "I'll make it back"        -> entry within N minutes of a  |
//|                                      losing close (revenge)       |
//|        "I need to get it back!"   -> an entry larger than the     |
//|                                      prior entry after a loss     |
//|        "trade just to feel        -> more than N entries inside a |
//|          engaged" (low energy)       rolling burst window         |
//|        "promote average setups    -> an entry outside the         |
//|          to A+" (perception)         documented session window    |
//|                                                                  |
//|   * "Journaling is not optional": the EA writes the session       |
//|     journal the document prescribes - a PRE check-in with its     |
//|     own prompts, a DURING note whenever a warning fires (with the |
//|     4-step mid-session reset protocol on the first one), a POST   |
//|     review with the day's top emotional moments (the warnings     |
//|     themselves) and the IF-THEN plan slot, all appended to        |
//|     MQL5/Files/cf_psych_journal.csv.                              |
//|                                                                  |
//| `[interpretation]`: the playbook is subjective by nature.  Every  |
//| threshold below is an input with a documented default; the loss   |
//| counts are the mechanical stand-in for "emotion rising" and the   |
//| day replay is deterministic, so the same account history always   |
//| produces the same warnings.                                       |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics Psychology MasterClass - session guardrails and journal (never trades)"

#include "..\..\Include\EACommon.mqh"

//--- identity
input string            InpSymbolsToTrade   = "EURUSD";             // Unused for trading: the engine needs one tradable symbol to init
input ulong             InpMagicNumber      = 3216;                 // UNIQUE MAGIC NUMBER (identity only - this EA never trades)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;        // Log verbosity
input int               InpServerGmtOffset  = 2;                    // Broker server clock minus GMT (winter) - deal times are server times
//--- the session being watched (London clock, same window the playbook EAs trade)
input int    InpSessionStartHour   = 14;    // Session start hour (London)
input int    InpSessionStartMin    = 25;    // Session start minute
input int    InpSessionEndHour     = 21;    // Session end hour (London)
input int    InpSessionEndMin      = 0;     // Session end minute
input int    InpPreCheckMin        = 10;    // "Take 5 minutes to check in" - opens the pre-session check-in this early
//--- the graded shutdown ladder (all counts; carryover shifts them one loss earlier)
input int    InpCautionLosses      = 1;     // Losses that trigger CAUTION ("reduce activity, be more selective")
input int    InpCooldownLosses     = 2;     // Losses that start the mid-session COOLDOWN ("a 15-minute break")
input int    InpCooldownMin        = 15;    // Length of that break, in minutes
input int    InpEndSessionLosses   = 3;     // Losses that end the session ("the emotional EV of another trade is poor")
//--- the zone map's mechanical stand-ins
input int    InpRevengeMin         = 30;    // "I'll make it back": entry within N minutes of a losing close
input double InpSizeEscalateRatio  = 1.50;  // "I need to get it back!": entry above N x the previous entry, after a loss
input int    InpBurstEntries       = 4;     // "trade just to feel engaged": more than N entries inside ...
input int    InpBurstWindowMin     = 30;    // ... this rolling window
input bool   InpFlagOffWindow      = true;  // "promote average setups to A+": flag entries outside the session window
//--- output
input string InpJournalFile        = "cf_psych_journal.csv";  // MQL5/Files/ journal ("journaling is not optional")

//--- warning bits (one journal line per bit per day, never per tick)
#define CF_PSYCH_CARRYOVER  1
#define CF_PSYCH_CAUTION    2
#define CF_PSYCH_COOLDOWN   4
#define CF_PSYCH_BREACH     8
#define CF_PSYCH_ENDSESSION 16
#define CF_PSYCH_REVENGE    32
#define CF_PSYCH_ESCALATE   64
#define CF_PSYCH_BURST      128
#define CF_PSYCH_OFFWINDOW  256

//+------------------------------------------------------------------+
//| Result of replaying one trading day through the state machine     |
//+------------------------------------------------------------------+
struct SCfPsychDay
{
   int      entries;
   int      closes;
   int      wins;
   int      losses;
   double   pl;
   int      maxStreak;
   int      burstMax;        // most entries inside any InpBurstWindowMin window
   int      revengeEntries;
   int      escalateEntries;
   int      offWindowEntries;
   bool     breach;          // a trade was taken while the COOLDOWN was running
   bool     lockedOut;       // the session ended early (breach or loss budget)
   datetime lastLossClose;
   void Reset()
   {
      entries = 0; closes = 0; wins = 0; losses = 0; pl = 0.0; maxStreak = 0;
      burstMax = 0; revengeEntries = 0; escalateEntries = 0; offWindowEntries = 0;
      breach = false; lockedOut = false; lastLossClose = 0;
   }
};

//+------------------------------------------------------------------+
//| Strategy class - a monitor that is deliberately not a trader      |
//+------------------------------------------------------------------+
class CCfPsychGuardrails : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_PSYCH_GUARDRAILS";
      cfg.sourceDoc             = "chartfanatics/pdf/full-psychology-masterclass.pdf (card #12)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = 0.0;          // never sizes a position
      cfg.signalTimeframe       = PERIOD_M15;
      cfg.signalOnNewBarOnly    = true;
      cfg.maxOpenPositions      = 0;            // nothing to open
      cfg.maxTradesPerDay       = 0;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.sessionStartHour      = InpSessionStartHour;   cfg.sessionStartMin = InpSessionStartMin;
      cfg.sessionEndHour        = InpSessionEndHour;     cfg.sessionEndMin   = InpSessionEndMin;
      cfg.newsFilter            = false;
      cfg.ledgerEnabled         = false;        // its journal is the deliverable, not the engine ledger
      cfg.logLevel              = InpLogLevel;
   }

   void OnInitStrategy()
   {
      m_lastCheck     = 0;
      m_dayStart      = 0;
      m_warnMask      = 0;
      m_preWritten    = false;
      m_postWritten   = false;
      m_carryover     = false;
      m_carryPct      = 0.0;
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "psychology monitor active: session opens %02d:%02d London, shutdown ladder %d/%d/%d losses, %d-minute break, carryover shifts it one step",
             InpSessionStartHour, InpSessionStartMin, InpCautionLosses, InpCooldownLosses, InpEndSessionLosses, InpCooldownMin), true);
      EA_Log(EA_LOG_EVENTS, "this EA never opens positions - it journals the mental checklist and flags the early-warning signs", true);
   }

   void OnDeinitStrategy()
   {
      //--- "journaling is not optional": never lose the partial day on a chart unload
      if(m_dayStart <= 0) return;
      SCfPsychDay st;
      if(!ReplayDay(m_dayStart, st)) return;
      if(!m_postWritten && (st.entries > 0 || st.closes > 0 || WarnCount() > 0))
         JournalRow(m_dayStart, "POST", st, "partial - written at deinit");
   }

   //--- never trades, and says so instead of merely failing to find a signal
   bool AllowTrading(SEAContext &ctx) { return false; }
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan) { plan.Reset(); return false; }

   //--- the monitor: one account-wide replay per minute, never per tick
   void Manage(SEAContext &ctx)
   {
      datetime now = TimeTradeServer();
      if(m_lastCheck > 0 && now - m_lastCheck < 60) return;
      m_lastCheck = now;

      datetime todayStart = ServerDayStart(now);
      //--- day rollover: close the finished day's journal before starting the new one
      if(m_dayStart > 0 && todayStart > m_dayStart)
      {
         SCfPsychDay finished;
         if(ReplayDay(m_dayStart, finished) && !m_postWritten)
            JournalRow(m_dayStart, "POST", finished, "day closed");
         m_warnMask    = 0;
         m_preWritten  = false;
         m_postWritten = false;
         m_carryover   = false;
         m_carryPct    = 0.0;
      }
      m_dayStart = todayStart;

      int clockMin = EA_MinutesOfDay(EA_ClockNow());
      int openMin  = InpSessionStartHour * 60 + InpSessionStartMin;
      int closeMin = InpSessionEndHour * 60 + InpSessionEndMin;
      bool sessionDay = (ctx.dayOfWeek >= 1 && ctx.dayOfWeek <= 5);   // Mon..Fri

      //--- carryover first: yesterday's realised result raises today's baseline
      if(!m_preWritten && sessionDay) CarryoverCheck(todayStart);

      //--- "before the session: take 5 minutes to check in"
      if(!m_preWritten && sessionDay && clockMin >= openMin - InpPreCheckMin && clockMin < openMin)
      {
         m_preWritten = true;
         SCfPsychDay st;
         if(ReplayDay(todayStart, st))
            JournalRow(todayStart, "PRE", st, PreNote());
      }

      //--- the shutdown ladder is deterministic: replay the day, then journal what is new
      SCfPsychDay st;
      if(!ReplayDay(todayStart, st)) return;
      CheckLadder(todayStart, st);

      //--- "after the session": the cool-down review, once, with the day's own moments
      if(!m_postWritten && sessionDay && clockMin >= closeMin)
      {
         m_postWritten = true;
         JournalRow(todayStart, "POST", st, PostNote(st));
      }
   }

private:
   datetime m_lastCheck;
   datetime m_dayStart;
   int      m_warnMask;
   bool     m_preWritten;
   bool     m_postWritten;
   bool     m_carryover;
   double   m_carryPct;

   //--- midnight of the current broker-server day
   datetime ServerDayStart(const datetime serverNow)
   {
      MqlDateTime dt;
      if(!TimeToStruct(serverNow, dt)) return 0;
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      return StructToTime(dt);
   }

   //--- "emotional carryover": was the previous session red?
   void CarryoverCheck(const datetime todayStart)
   {
      if(m_carryover) return;
      datetime yStart = ServerDayStart(todayStart - 86400);
      if(yStart <= 0 || yStart >= todayStart) return;
      SCfPsychDay yst;
      if(!ReplayDay(yStart, yst)) return;
      if(yst.closes <= 0 || yst.pl >= 0.0) return;      // no red yesterday: today starts at baseline
      m_carryover = true;
      m_carryPct  = yst.pl;
      m_warnMask |= CF_PSYCH_CARRYOVER;
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "emotional carryover: yesterday closed %.2f - \"emotions don't reset overnight\", today's ladder starts one step up", m_carryPct), true);
      JournalRow(m_dayStart, "CARRYOVER", yst, StringFormat(
             "yesterday closed %.2f with %d losing closes - the ladder is shifted one step earlier today", m_carryPct, yst.losses));
   }

   //--- the session window in SERVER time for the day a server timestamp belongs to
   datetime WindowStartServer(const datetime serverRef)
   {
      MqlDateTime dt;
      if(!TimeToStruct(serverRef, dt)) return 0;
      dt.hour = InpSessionStartHour; dt.min = InpSessionStartMin; dt.sec = 0;
      return EA_ClockToServer(StructToTime(dt));
   }

   //--- replay one day of the account's deals (every magic) through the ladder
   bool ReplayDay(const datetime dayStart, SCfPsychDay &st)
   {
      st.Reset();
      if(dayStart <= 0) return false;
      if(!HistorySelect(dayStart, dayStart + 86400)) return false;

      //--- thresholds, shifted one step earlier after a red day ("carryover")
      int shift = m_carryover ? 1 : 0;
      int cautionAt = MathMax(1, InpCautionLosses - shift);
      int cooldownAt = MathMax(cautionAt + 1, InpCooldownLosses - shift);
      int endAt      = MathMax(cooldownAt + 1, InpEndSessionLosses - shift);

      datetime windowStart = WindowStartServer(dayStart + 43200);   // midday of the day: no date ambiguity
      datetime windowEnd   = windowStart + (datetime)((InpSessionEndHour * 60 + InpSessionEndMin) -
                                                      (InpSessionStartHour * 60 + InpSessionStartMin)) * 60;
      int   streak      = 0;
      int   losses      = 0;
      double lastEntryVol = 0.0;
      datetime cooldownUntil = 0;
      datetime entryTimes[256];
      int      entryCount = 0;

      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong  t      = HistoryDealGetTicket(i);
         if(t == 0) continue;
         long   type   = HistoryDealGetInteger(t, DEAL_TYPE);
         if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL) continue;      // skip balance / credit rows
         long   kind   = HistoryDealGetInteger(t, DEAL_ENTRY);
         datetime when = (datetime)HistoryDealGetInteger(t, DEAL_TIME);

         if(kind == DEAL_ENTRY_IN || kind == DEAL_ENTRY_INOUT)
         {
            double vol = HistoryDealGetDouble(t, DEAL_VOLUME);
            st.entries++;
            if(entryCount < 256) entryTimes[entryCount++] = when;

            //--- "perception shifts": trading outside the documented window
            if(InpFlagOffWindow && (when < windowStart || when >= windowEnd)) st.offWindowEntries++;

            //--- "one small trade max, or a 15-minute break. If you break your own limit,
            //---  your session is over." - a trade while the break runs is the breach.
            if(cooldownUntil > when)
            {
               st.breach    = true;
               st.lockedOut = true;
               cooldownUntil = 0;
            }

            //--- "I'll make it back": an entry soon after a losing close
            if(st.lastLossClose > 0 && when - st.lastLossClose <= (datetime)(InpRevengeMin * 60))
               st.revengeEntries++;

            //--- "I need to get it back!": re-entry larger than the previous entry, after a loss
            if(st.lastLossClose > 0 && lastEntryVol > 0.0 && vol > InpSizeEscalateRatio * lastEntryVol)
               st.escalateEntries++;

            lastEntryVol = vol;
            continue;
         }

         if(kind != DEAL_ENTRY_OUT && kind != DEAL_ENTRY_OUT_BY && kind != DEAL_ENTRY_INOUT) continue;

         double p = HistoryDealGetDouble(t, DEAL_PROFIT) +
                    HistoryDealGetDouble(t, DEAL_SWAP) +
                    HistoryDealGetDouble(t, DEAL_COMMISSION);
         st.pl += p;
         st.closes++;
         if(p < 0.0)
         {
            st.losses++;
            losses++;
            streak++;
            if(streak > st.maxStreak) st.maxStreak = streak;
            st.lastLossClose = when;
            if(losses >= cooldownAt) cooldownUntil = when + (datetime)(InpCooldownMin * 60);
            if(losses >= endAt)      st.lockedOut = true;
         }
         else if(p > 0.0)
         {
            st.wins++;
            streak = 0;
         }
      }

      //--- "trade just to feel engaged": the densest burst of entries inside the window
      int winSec = InpBurstWindowMin * 60;
      for(int i = 0; i < entryCount; i++)
      {
         int n = 0;
         for(int j = 0; j < entryCount; j++)
            if(entryTimes[j] >= entryTimes[i] && entryTimes[j] - entryTimes[i] < (datetime)winSec) n++;
         if(n > st.burstMax) st.burstMax = n;
      }
      return true;
   }

   //--- journal / log what the replay found that has not been reported yet today
   void CheckLadder(const datetime dayStart, const SCfPsychDay &st)
   {
      int shift = m_carryover ? 1 : 0;
      int cautionAt = MathMax(1, InpCautionLosses - shift);
      int cooldownAt = MathMax(cautionAt + 1, InpCooldownLosses - shift);
      int endAt      = MathMax(cooldownAt + 1, InpEndSessionLosses - shift);

      if(st.losses >= cautionAt)
         Warn(CF_PSYCH_CAUTION, dayStart, st, StringFormat(
              "%d losing close(s) - \"reduce activity, be more selective, or slow down\" (the 60%% point: you can still reset)", st.losses));
      if(st.losses >= cooldownAt)
         Warn(CF_PSYCH_COOLDOWN, dayStart, st, StringFormat(
              "%d losing closes - mid-session reset: stand up, stretch, breathe deeply for 2 minutes, then ask \"what is the market actually doing right now, not what I want it to do?\" - the next %d minutes are a break",
              st.losses, InpCooldownMin));
      if(st.breach)
         Warn(CF_PSYCH_BREACH, dayStart, st, StringFormat(
              "a trade was taken during the %d-minute break - \"if you break your own limit, your session is over\": session locked for today", InpCooldownMin));
      if(st.losses >= endAt)
         Warn(CF_PSYCH_ENDSESSION, dayStart, st, StringFormat(
              "%d losing closes - the emotional EV of another trade is poor; \"sometimes the smartest trade is no trade at all\": session over", st.losses));
      if(st.revengeEntries > 0)
         Warn(CF_PSYCH_REVENGE, dayStart, st, StringFormat(
              "%d entry(ies) within %d minutes of a losing close - the \"I'll make it back\" pattern", st.revengeEntries, InpRevengeMin));
      if(st.escalateEntries > 0)
         Warn(CF_PSYCH_ESCALATE, dayStart, st, StringFormat(
              "%d entry(ies) larger than %.2fx the previous entry after a loss - the \"I need to get it back!\" pattern",
              st.escalateEntries, InpSizeEscalateRatio));
      if(st.burstMax > InpBurstEntries)
         Warn(CF_PSYCH_BURST, dayStart, st, StringFormat(
              "%d entries inside %d minutes - \"impatient and trade just to feel engaged\" (low-energy overtrading)",
              st.burstMax, InpBurstWindowMin));
      if(st.offWindowEntries > 0)
         Warn(CF_PSYCH_OFFWINDOW, dayStart, st, StringFormat(
              "%d entry(ies) outside the %02d:%02d-%02d:%02d window - the \"promote average setups to A+\" perception shift",
              st.offWindowEntries, InpSessionStartHour, InpSessionStartMin, InpSessionEndHour, InpSessionEndMin));
   }

   //--- one log line and one journal row per warning type per day
   void Warn(const int bit, const datetime dayStart, const SCfPsychDay &st, const string note)
   {
      if((m_warnMask & bit) != 0) return;
      m_warnMask |= bit;
      EA_Log(EA_LOG_EVENTS, "psychology warning: " + note, true);
      JournalRow(dayStart, "WARN", st, note);
   }

   //--- the document's own pre-session prompts
   string PreNote()
   {
      string note = "check-in: how do you feel physically, mentally and emotionally? set one goal (e.g. stay patient for the first 30 minutes)";
      if(m_carryover)
         note += StringFormat(" | carryover: yesterday closed %.2f - monitor your energy, today starts charged", m_carryPct);
      return note;
   }

   //--- the document's own post-session prompts, filled with the day's detected moments
   string PostNote(const SCfPsychDay &st)
   {
      return StringFormat(
         "review: list your top emotional moments/lessons and end with an if-then plan for tomorrow "
         "(\"if I feel FOMO, I'll take three deep breaths and wait for confirmation\") | "
         "day: %d entries, %dW/%dL, pl %.2f, longest losing run %d, moments flagged this session: %d",
         st.entries, st.wins, st.losses, st.pl, st.maxStreak, WarnCount());
   }

   int WarnCount()
   {
      int n = 0;
      for(int i = 1; i <= 256; i <<= 1) if((m_warnMask & i) != 0) n++;
      return n;
   }

   //--- the journal: append-only CSV in MQL5/Files
   void JournalRow(const datetime day, const string kind, const SCfPsychDay &st, const string note)
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
         FileWrite(fh, "date", "kind", "entries", "wins", "losses", "pl", "max_loss_streak",
                   "burst_max", "revenge", "escalate", "off_window", "breach", "warnings", "note");
      FileWrite(fh,
                TimeToString(day, TIME_DATE),
                kind,
                IntegerToString(st.entries),
                IntegerToString(st.wins),
                IntegerToString(st.losses),
                DoubleToString(st.pl, 2),
                IntegerToString(st.maxStreak),
                IntegerToString(st.burstMax),
                IntegerToString(st.revengeEntries),
                IntegerToString(st.escalateEntries),
                IntegerToString(st.offWindowEntries),
                st.breach ? "yes" : "no",
                IntegerToString(WarnCount()),
                note);
      FileClose(fh);
   }
};

CCfPsychGuardrails g_cfPsychGuardrails;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfPsychGuardrails);
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
