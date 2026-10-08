//+------------------------------------------------------------------+
//|            EA_CF_MomentumModelPerformanceDevelopment.mq5          |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| "If You Only Watch One Trading Process Video, Make It This"        |
//| (Jeff Holden, SMB Capital - Glimpse summary)                       |
//| Card    : chartfanatics/todos/momentum-model-performance-development.md (#24)
//| Source  : chartfanatics/glimpse/WDdvnd9vLbM.md                     |
//| Magic   : 3227 (reserved - this EA never trades)                   |
//|                                                                    |
//| This is a PROCESS document, not a market strategy: it teaches the   |
//| four-element momentum model - identify mistakes (daily report card),|
//| diagnose with the five whys, implement ONE clear solution, and      |
//| stack small wins.  There is no entry rule to mechanize, so - like    |
//| the other process cards in this family - the EA is a MONITOR: it     |
//| never opens, sizes or closes a position and instead runs the         |
//| document's own machinery against the account:                        |
//|                                                                    |
//|   * DAILY REPORT CARD - the mechanical mistakes the document names   |
//|     (did not respect the stop, sold too early, held too long,        |
//|     revenge entry after a loss, oversized) are detected from the     |
//|     deal history every midnight for the day that just ended and      |
//|     listed WITHOUT judgement: "this isn't self-criticism, it's data  |
//|     collection";                                                      |
//|   * FIVE WHYS - the week's most recurring mistake is written to a     |
//|     prompt file with the five questions laid out, because "most       |
//|     traders stop at one or two whys, but the real solution emerges    |
//|     at the fourth or fifth level" (the document's own ChatGPT action |
//|     item); the EA asks the questions, the trader answers;            |
//|   * ONE GOAL AT A TIME - the focus skill is an input; while it is     |
//|     stop-loss ("risk management is the foundation"), a stop violation |
//|     turns the day's directive into a LOCK instead of a note;         |
//|   * TRADE GRADING + RISK ALLOCATION - every trade is graded A+/A/B/C  |
//|     and the document's allocation bands (A+ 80% of the daily stop,   |
//|     B 15%, C 5%) are audited against the risk that was actually       |
//|     taken;                                                           |
//|   * ONE PLAYBOOK FIRST - trading more than InpMaxPlaybooksPerWeek     |
//|     magics in a week is flagged: "master one playbook before adding  |
//|     others";                                                          |
//|   * SMALL WINS, NOT BIG MOMENTS - the weekly row counts the rule-     |
//|     following trades and the share of the week's profit that came     |
//|     from a single trade, because "the number of small wins generated  |
//|     will dictate the success that you have as a trader".             |
//|                                                                    |
//| HOW THE R MULTIPLE IS KNOWN (no invention): the executing CF EAs     |
//| persist the planned risk of every position as a terminal global       |
//| variable ("EA_<magic>_R<ticket>", EATrade.mqh) and delete it the       |
//| moment the position closes.  A monitor attached later can therefore   |
//| not read it after the fact, so this EA snapshots each open position    |
//| it can see into a small registry file while the trade is LIVE         |
//| (preferring the engine's own persisted key, falling back to the        |
//| position's stop distance) and joins the closed deals against that      |
//| registry.  Without the engine's volume key the volume seen at first    |
//| sight is used: for a position that was already partially closed before  |
//| the monitor attached, that risk is a lower bound and the R reads high.  |  A trade whose risk could never be captured is reported as  |
//| "ungraded" - never silently graded by a guess.  R is defined exactly  |
//| as the engine defines it (money / (EA_LossPerLot x volume)), so the    |
//| monitor's numbers and the engine's evidence ledger agree.             |
//|                                                                    |
//| [interpretation]: the document gives A+/B/C allocation bands but no    |
//| grade thresholds and no 1R/2R table.  The A+ >= 2R, A >= 1R, B > 0,   |
//| C <= 0 or mistake-flagged ladder, the A band (40%), the early-exit     |
//| and held-too-long thresholds and the replay of "too tight / no stop"   |
//| as cash-over-planned-risk are engineering numbers, exposed as inputs   |
//| and stated here as such.  "Held too long"/"sold too early" are only    |
//| measurable through holding time and the R actually realised - a proxy  |
//| for the document's intent.  The fourth report-card slot (a revenge      |
//| entry straight after a loss) plus its 30-minute window comes from the   |
//| same trading-discipline vocabulary, not from this document's example    |
//| list ("sold too early, didn't respect stop, held too long").  Pods, the |
//| 10-year horizon, "study the new market" and the qualitative grading of  |
//| a setup are organisational / human judgements with no platform signal:  |
//| disclosed, not faked.                                                  |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "Momentum model performance development - daily report card, five whys prompt, grade + risk-allocation audit, small-wins tracking (monitor only, never trades)"

#include "..\..\Include\EACommon.mqh"

enum ENUM_CF_FOCUS_SKILL
{
   CF_FOCUS_STOPLOSS = 0,   // Fix stop-loss discipline first (risk management is the foundation)
   CF_FOCUS_EXITS    = 1,   // Fix take-profit / exit discipline
   CF_FOCUS_ENTRIES  = 2,   // Fix entry selection
   CF_FOCUS_NONE     = 3    // No focus lock - report only
};

//--- monitor identity
input string            InpSymbolsToTrade   = "US100,US500";     // monitor scope (never trades)
input ulong             InpMagicNumber      = 3227;              // magic (reserved; the monitor never trades)
input int               InpStage            = 5;                 // stage policy (the card #01 helper)
input int               InpServerGmtOffset  = 2;                 // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;     // Log verbosity
input int               InpScanSeconds      = 60;                // how often open positions are snapshotted
input ulong             InpMagicFilter      = 0;                 // 0 = every magic on the account scope
//--- the document's own numbers
input double InpDailyStopUsd    = 1000.0;  // the daily stop the grade bands are percentages of
input ENUM_CF_FOCUS_SKILL InpFocusSkill = CF_FOCUS_STOPLOSS;   // "one goal at a time"
input int    InpMaxPlaybooksPerWeek = 1;   // "master one playbook before adding others"
input double InpBandAPlusPct    = 80.0;    // A+ allocation band (% of the daily stop)
input double InpBandAPct        = 40.0;    // A  allocation band [interpretation - the doc names A but no %]
input double InpBandBPct        = 15.0;    // B  allocation band
input double InpBandCPct        = 5.0;     // C  allocation band
input double InpBandTolPct      = 5.0;     // tolerance before "oversized" (percent of the daily stop)
//--- mistake thresholds (see the interpretation note in the header)
input double InpStopTolR        = 0.10;    // a loss beyond -(1 + tol) R is a stop violation
input double InpEarlyExitR      = 0.50;    // a winner taken below this R ...
input int    InpEarlyExitMin    = 20;      // ... inside this many minutes reads as "sold too early"
input int    InpMaxHoldMinutes  = 240;     // ... or after this long reads as "held too long"
input int    InpRevengeMinutes  = 30;      // an entry this soon after a losing close reads as revenge
input int    InpWeeksForReview  = 5;       // "after 4-5 weeks, review your progress"
//--- files (MQL5/Files/)
input string InpReportFile      = "cf_momentum_daily_report.csv";
input string InpWinsFile        = "cf_momentum_weekly_wins.csv";
input string InpPromptFile      = "cf_momentum_five_whys.txt";
input string InpRegistryFile    = "cf_momentum_risk_registry.txt";
input int    InpRegistryKeepDays = 120;   // registry rows older than this are pruned

//--- one closed trade, rebuilt from the deal history
struct SReviewTrade
{
   ulong    pid;
   string   sym;
   ulong    magic;
   double   money;        // profit + swap + commission, account currency
   double   riskMoney;    // planned cash risk when known (0 = ungraded)
   double   rMult;        // money / riskMoney (0 when ungraded)
   double   entryPrice;
   double   exitPrice;
   int      dir;          // +1 long, -1 short
   int      holdMin;
   datetime entryTime;
   datetime exitTime;
};

//--- the document's mistake list, mechanically detected
struct SReviewFlags
{
   bool stopViolation;
   bool earlyExit;
   bool heldTooLong;
   bool revenge;
   bool oversized;
   int  grade;            // -1 A+, 0 A, 1 B, 2 C, 3 ungraded
};

//+------------------------------------------------------------------+
class CCfMomentumModelReview : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_MOMENTUM_MODEL_REVIEW";
      cfg.sourceDoc             = "chartfanatics/glimpse/WDdvnd9vLbM.md (card #24)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = 0.0;          // never sizes a position
      cfg.signalTimeframe       = PERIOD_M15;
      cfg.signalOnNewBarOnly    = true;
      cfg.maxOpenPositions      = 0;
      cfg.maxTradesPerDay       = 0;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.newsFilter            = false;
      cfg.ledgerEnabled         = false;        // its own journals ARE the deliverable
      cfg.logLevel              = InpLogLevel;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   void OnInitStrategy()
   {
      m_lastDay    = 0;
      m_lastWeek   = 0;
      m_regCount   = 0;
      m_scopeCount = 0;
      for(int i = 0; i < g_eaSymbolCount && i < 16; i++)
      {
         m_scope[m_scopeCount]     = g_eaSymbols[i];
         m_scopeSeen[m_scopeCount] = 0;
         m_scopeCount++;
      }
      LoadRegistry();
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "momentum model review active (monitor only): report %s, five-whys prompt %s, focus %s, grade bands audited against a %.0f %s daily stop",
             InpReportFile, InpPromptFile, FocusName(), InpDailyStopUsd, AccountInfoString(ACCOUNT_CURRENCY)), true);
      EA_Log(EA_LOG_EVENTS, "this EA never trades: the document describes a process, and a process is measured, not executed", true);
   }

   //--- never trades, and says so instead of merely failing to find a signal
   bool AllowTrading(SEAContext &ctx) { return false; }
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan) { plan.Reset(); return false; }

   void Manage(SEAContext &ctx)
   {
      ScanOpenPositions();
      //--- the two period paths use separate markers: the engine calls Manage once
      //--- per configured symbol, and a shared flag would double-write the rows
      datetime day = DayStart(TimeTradeServer());
      if(day != m_lastDay)
      {
         m_lastDay = day;
         DailyReportCard(day - 86400);          // the day that just ended
      }
      datetime week = WeekStart(TimeTradeServer());
      if(week != m_lastWeek)
      {
         m_lastWeek = week;
         WeeklyReview(week - 7 * 86400);        // the week that just ended
      }
   }

private:
   datetime m_lastDay;
   datetime m_lastWeek;
   //--- the symbols this monitor follows (copied from the engine's parsed list)
   string   m_scope[16];
   datetime m_scopeSeen[16];
   int      m_scopeCount;
   //--- risk registry: snapshot of every position the monitor has seen live
   ulong    m_regTicket[];
   string   m_regSym[];
   ulong    m_regMagic[];
   double   m_regRisk[];
   double   m_regVol[];
   double   m_regMoney[];
   datetime m_regSeen[];
   int      m_regCount;

   //-------------------------------------------------------------------
   // calendar helpers
   //-------------------------------------------------------------------
   datetime DayStart(const datetime t)
   {
      MqlDateTime dt;
      if(!TimeToStruct(t, dt)) return 0;
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      return StructToTime(dt);
   }

   datetime WeekStart(const datetime t)
   {
      datetime d = DayStart(t);
      if(d <= 0) return 0;
      MqlDateTime dt;
      if(!TimeToStruct(d, dt)) return 0;
      int back = (dt.day_of_week == 0) ? 6 : (dt.day_of_week - 1);   // Monday-based week
      return d - (datetime)(back * 86400);
   }

   string FocusName()
   {
      switch(InpFocusSkill)
      {
         case CF_FOCUS_STOPLOSS: return "stop-loss discipline";
         case CF_FOCUS_EXITS:    return "exit discipline";
         case CF_FOCUS_ENTRIES:  return "entry selection";
      }
      return "none";
   }

   double GradeBandPct(const int grade)
   {
      switch(grade)
      {
         case -1: return InpBandAPlusPct;
         case  0: return InpBandAPct;
         case  1: return InpBandBPct;
         case  2: return InpBandCPct;
      }
      return 0.0;                                // ungraded: no band to audit against
   }

   //-------------------------------------------------------------------
   // The risk registry
   //-------------------------------------------------------------------
   int RegistryIndex(const ulong ticket)
   {
      for(int i = 0; i < m_regCount; i++) if(m_regTicket[i] == ticket) return i;
      return -1;
   }

   void RegistryAppend(const ulong ticket, const string sym, const ulong magic,
                       const double risk, const double vol, const double money, const datetime seen)
   {
      if(m_regCount >= ArraySize(m_regTicket))
      {
         int want = m_regCount + 128;
         ArrayResize(m_regTicket, want);
         ArrayResize(m_regSym, want);
         ArrayResize(m_regMagic, want);
         ArrayResize(m_regRisk, want);
         ArrayResize(m_regVol, want);
         ArrayResize(m_regMoney, want);
         ArrayResize(m_regSeen, want);
      }
      m_regTicket[m_regCount] = ticket;
      m_regSym[m_regCount]    = sym;
      m_regMagic[m_regCount]  = magic;
      m_regRisk[m_regCount]   = risk;
      m_regVol[m_regCount]    = vol;
      m_regMoney[m_regCount]  = money;
      m_regSeen[m_regCount]   = seen;
      m_regCount++;
   }

   //--- rows: ticket,symbol,magic,riskDist,volume,riskMoney,seen
   void LoadRegistry()
   {
      m_regCount = 0;
      ArrayResize(m_regTicket, 0);
      ArrayResize(m_regSym, 0);
      ArrayResize(m_regMagic, 0);
      ArrayResize(m_regRisk, 0);
      ArrayResize(m_regVol, 0);
      ArrayResize(m_regMoney, 0);
      ArrayResize(m_regSeen, 0);

      int fh = FileOpen(InpRegistryFile, FILE_READ | FILE_TXT | FILE_ANSI);
      if(fh == INVALID_HANDLE) return;
      datetime now = TimeTradeServer();
      datetime keep = (datetime)(MathMax(1, InpRegistryKeepDays) * 86400);
      int loaded = 0, dropped = 0, guard = 0;
      while(!FileIsEnding(fh) && guard++ < 200000)
      {
         string line = FileReadString(fh);
         StringTrimLeft(line);
         StringTrimRight(line);
         if(StringLen(line) == 0) continue;
         string parts[];
         int n = StringSplit(line, ',', parts);
         if(n < 7) { dropped++; continue; }
         ulong ticket = (ulong)StringToInteger(parts[0]);
         if(ticket == 0) { dropped++; continue; }
         datetime seen = StringToTime(parts[6]);
         if(seen <= 0 || now - seen > keep) { dropped++; continue; }
         RegistryAppend(ticket, parts[1], (ulong)StringToInteger(parts[2]),
                        StringToDouble(parts[3]), StringToDouble(parts[4]), StringToDouble(parts[5]), seen);
         loaded++;
      }
      FileClose(fh);
      if(loaded > 0)
         EA_Log(EA_LOG_EVENTS, StringFormat("risk registry: %d trade(s) loaded from %s", loaded, InpRegistryFile), true);
      if(dropped > 0)
      {
         RewriteRegistry();
         EA_Log(EA_LOG_EVENTS, StringFormat("risk registry: %d stale row(s) pruned", dropped), true);
      }
   }

   void RewriteRegistry()
   {
      int fh = FileOpen(InpRegistryFile, FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(fh == INVALID_HANDLE) return;
      for(int i = 0; i < m_regCount; i++)
         FileWriteString(fh, StringFormat("%I64d,%s,%I64d,%.5f,%.2f,%.2f,%s\r\n",
                        (long)m_regTicket[i], m_regSym[i], (long)m_regMagic[i],
                        m_regRisk[i], m_regVol[i], m_regMoney[i],
                        TimeToString(m_regSeen[i], TIME_DATE | TIME_MINUTES)));
      FileClose(fh);
   }

   void RegisterPosition(const ulong ticket, const string sym, const ulong magic,
                         const double risk, const double vol, const double money)
   {
      datetime now = TimeTradeServer();
      RegistryAppend(ticket, sym, magic, risk, vol, money, now);
      int fh = FileOpen(InpRegistryFile, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(fh == INVALID_HANDLE)
      {
         EA_Log(EA_LOG_ERRORS, "risk registry: cannot append to " + InpRegistryFile, true);
         return;
      }
      FileSeek(fh, 0, SEEK_END);
      FileWriteString(fh, StringFormat("%I64d,%s,%I64d,%.5f,%.2f,%.2f,%s\r\n",
                     (long)ticket, sym, (long)magic, risk, vol, money,
                     TimeToString(now, TIME_DATE | TIME_MINUTES)));
      FileClose(fh);
   }

   int ScopeIndex(const string sym)
   {
      for(int i = 0; i < m_scopeCount; i++) if(m_scope[i] == sym) return i;
      return -1;
   }

   //--- snapshot every open position on the monitor's scope while it is live
   void ScanOpenPositions()
   {
      if(m_scopeCount <= 0) return;
      datetime now = TimeTradeServer();
      datetime throttle = (datetime)MathMax(5, InpScanSeconds);
      int scanned[16];
      ArrayInitialize(scanned, 0);

      int total = PositionsTotal();
      for(int p = 0; p < total; p++)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         string sym = PositionGetString(POSITION_SYMBOL);
         int s = ScopeIndex(sym);
         if(s < 0) continue;
         if(scanned[s] == 0)                         // this symbol's turn in the throttle?
         {
            if(m_scopeSeen[s] > 0 && now - m_scopeSeen[s] < throttle) continue;
            scanned[s]     = 1;
            m_scopeSeen[s] = now;
         }
         //--- the registry key is the position IDENTIFIER: it is what history
         //--- reports as DEAL_POSITION_ID, while the ticket is what the engine
         //--- executor persists its risk under (EATrade.mqh uses its own ticket)
         ulong pid = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
         if(pid == 0) pid = t;
         ulong magic = (ulong)PositionGetInteger(POSITION_MAGIC);
         if(InpMagicFilter > 0 && magic != InpMagicFilter) continue;
         if(RegistryIndex(pid) >= 0) continue;           // already snapshotted

         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl    = PositionGetDouble(POSITION_SL);
         double vol   = PositionGetDouble(POSITION_VOLUME);
         //--- the engine executor's own persisted keys for THIS magic (same format
         //--- EATrade.mqh writes; EA_RiskKey() itself is bound to the calling EA's magic)
         string rk = "EA_" + IntegerToString((long)magic) + "_R" + IntegerToString((long)t);
         string vk = "EA_" + IntegerToString((long)magic) + "_V" + IntegerToString((long)t);
         double dist = GlobalVariableCheck(rk) ? GlobalVariableGet(rk) : 0.0;
         double vol0 = GlobalVariableCheck(vk) ? GlobalVariableGet(vk) : 0.0;
         if(vol0 <= 0.0) vol0 = vol;
         if(dist <= 0.0 && sl > 0.0) dist = MathAbs(entry - sl);   // fallback: the stop in the book

         if(dist <= 0.0 || vol0 <= 0.0)
         {
            EA_Log(EA_LOG_EVENTS, StringFormat(
                   "registry: position #%I64d %s has no stop and no persisted risk - its report row will read 'ungraded'",
                   (long)pid, sym), true);
            RegisterPosition(pid, sym, magic, 0.0, vol0, 0.0);
            continue;
         }
         double riskMoney = EA_LossPerLot(sym, dist) * vol0;
         if(riskMoney <= 0.0)
         {
            EA_Log(EA_LOG_EVENTS, StringFormat(
                   "registry: %s risk cannot be priced (not in Market Watch?) - position #%I64d will read 'ungraded'",
                   sym, (long)pid), true);
            RegisterPosition(pid, sym, magic, dist, vol0, 0.0);
            continue;
         }
         RegisterPosition(pid, sym, magic, dist, vol0, riskMoney);
      }
   }

   double RegistryRiskMoney(const ulong pid)
   {
      int i = RegistryIndex(pid);
      return (i >= 0) ? m_regMoney[i] : 0.0;
   }

   //-------------------------------------------------------------------
   // Rebuild one fully closed position from the deal history
   //-------------------------------------------------------------------
   bool BuildReviewTrade(const ulong pid, SReviewTrade &rt)
   {
      rt.pid = pid; rt.sym = ""; rt.magic = 0; rt.money = 0.0; rt.riskMoney = 0.0;
      rt.rMult = 0.0; rt.entryPrice = 0.0; rt.exitPrice = 0.0; rt.dir = 0;
      rt.holdMin = 0; rt.entryTime = 0; rt.exitTime = 0;
      if(pid == 0) return false;
      if(PositionSelectByTicket(pid)) return false;          // still open - not this day's card
      if(!HistorySelectByPosition(pid)) return false;
      int n = HistoryDealsTotal();
      if(n <= 0) return false;

      double money = 0.0, volOut = 0.0;
      for(int i = 0; i < n; i++)
      {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0) continue;
         long kind = HistoryDealGetInteger(d, DEAL_ENTRY);
         if(kind == DEAL_ENTRY_IN)
         {
            datetime t = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
            if(rt.entryTime == 0 || t < rt.entryTime)
            {
               rt.entryTime  = t;
               rt.entryPrice = HistoryDealGetDouble(d, DEAL_PRICE);
               rt.dir = (HistoryDealGetInteger(d, DEAL_TYPE) == DEAL_TYPE_BUY) ? +1 : -1;
            }
            if(rt.sym == "") rt.sym = HistoryDealGetString(d, DEAL_SYMBOL);
            if(rt.magic == 0) rt.magic = (ulong)HistoryDealGetInteger(d, DEAL_MAGIC);
         }
         else if(kind == DEAL_ENTRY_OUT || kind == DEAL_ENTRY_OUT_BY || kind == DEAL_ENTRY_INOUT)
         {
            money  += HistoryDealGetDouble(d, DEAL_PROFIT) +
                      HistoryDealGetDouble(d, DEAL_SWAP) +
                      HistoryDealGetDouble(d, DEAL_COMMISSION);
            volOut += HistoryDealGetDouble(d, DEAL_VOLUME);
            datetime t = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
            if(t > rt.exitTime)
            {
               rt.exitTime  = t;
               rt.exitPrice = HistoryDealGetDouble(d, DEAL_PRICE);
            }
            if(rt.sym == "") rt.sym = HistoryDealGetString(d, DEAL_SYMBOL);
            if(rt.magic == 0) rt.magic = (ulong)HistoryDealGetInteger(d, DEAL_MAGIC);
         }
      }
      if(volOut <= 0.0 || rt.entryTime == 0 || rt.exitTime == 0) return false;
      rt.money     = money;
      rt.riskMoney = RegistryRiskMoney(pid);
      rt.rMult     = (rt.riskMoney > 0.0) ? money / rt.riskMoney : 0.0;
      rt.holdMin   = (int)((rt.exitTime - rt.entryTime) / 60);
      return true;
   }

   //--- the document's mistake list, read off one closed trade
   void GradeTrade(const SReviewTrade &rt, const datetime lastLossClose, SReviewFlags &fl)
   {
      fl.stopViolation = false;
      fl.earlyExit     = false;
      fl.heldTooLong   = false;
      fl.revenge       = false;
      fl.oversized     = false;
      fl.grade         = 3;                                  // ungraded until proved otherwise

      if(rt.riskMoney > 0.0)
      {
         bool flagged = false;
         if(rt.rMult < -(1.0 + InpStopTolR)) { fl.stopViolation = true; flagged = true; }
         if(rt.rMult > 0.0 && rt.rMult < InpEarlyExitR && rt.holdMin <= InpEarlyExitMin)
         {
            fl.earlyExit = true; flagged = true;
         }
         if(rt.rMult > 0.0 && rt.rMult < InpEarlyExitR && rt.holdMin >= InpMaxHoldMinutes)
         {
            fl.heldTooLong = true; flagged = true;
         }
         if(flagged)                                       fl.grade = 2;
         else if(rt.rMult >= 2.0)                           fl.grade = -1;
         else if(rt.rMult >= 1.0)                           fl.grade = 0;
         else if(rt.rMult > 0.0)                            fl.grade = 1;
         else                                               fl.grade = 2;

         double bandPct = GradeBandPct(fl.grade);
         if(bandPct > 0.0 && InpDailyStopUsd > 0.0 &&
            (rt.riskMoney / InpDailyStopUsd) * 100.0 > bandPct + InpBandTolPct)
            fl.oversized = true;
      }
      if(lastLossClose > 0 && rt.entryTime > lastLossClose &&
         (rt.entryTime - lastLossClose) <= (datetime)(MathMax(1, InpRevengeMinutes) * 60))
      {
         fl.revenge = true;
         if(fl.grade != 3) fl.grade = 2;                   // a revenge entry is never a good grade
      }
   }

   //--- collect the position ids that carry an OUT deal inside [from, to)
   int CollectClosedIds(const datetime from, const datetime to, ulong &ids[])
   {
      ArrayResize(ids, 0);
      if(!HistorySelect(from, to)) return 0;
      int deals = HistoryDealsTotal();
      int n = 0;
      for(int i = 0; i < deals; i++)
      {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0) continue;
         long kind = HistoryDealGetInteger(d, DEAL_ENTRY);
         if(kind != DEAL_ENTRY_OUT && kind != DEAL_ENTRY_OUT_BY && kind != DEAL_ENTRY_INOUT) continue;
         ulong magic = (ulong)HistoryDealGetInteger(d, DEAL_MAGIC);
         if(InpMagicFilter > 0 && magic != InpMagicFilter) continue;
         ulong pid = (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID);
         if(pid == 0) continue;
         bool seen = false;
         for(int k = 0; k < n; k++) if(ids[k] == pid) { seen = true; break; }
         if(seen) continue;
         ArrayResize(ids, n + 1);
         ids[n] = pid;
         n++;
      }
      return n;
   }

   //--- rebuild + order by entry time (insertion sort: n is a day's or week's trades)
   int BuildTrades(const datetime from, const datetime to, SReviewTrade &trades[])
   {
      ulong ids[];
      int nIds = CollectClosedIds(from, to, ids);
      ArrayResize(trades, 0);
      int n = 0;
      for(int i = 0; i < nIds; i++)
      {
         SReviewTrade rt;
         if(!BuildReviewTrade(ids[i], rt)) continue;
         ArrayResize(trades, n + 1);
         trades[n] = rt;
         n++;
      }
      for(int i = 1; i < n; i++)
      {
         SReviewTrade key = trades[i];
         int j = i - 1;
         while(j >= 0 && trades[j].entryTime > key.entryTime) { trades[j + 1] = trades[j]; j--; }
         trades[j + 1] = key;
      }
      return n;
   }

   //-------------------------------------------------------------------
   // Daily report card
   //-------------------------------------------------------------------
   void DailyReportCard(const datetime day)
   {
      if(day <= 0) return;
      SReviewTrade trades[];
      int n = BuildTrades(day, day + 86400, trades);
      if(n <= 0) return;                                  // a day without trades gets no row

      int    graded = 0, ungraded = 0, aPlus = 0, a = 0, b = 0, c = 0;
      int    stopV = 0, earlyV = 0, lateV = 0, revengeV = 0, oversizeV = 0;
      double net = 0.0, worstR = 0.0;
      string worstSym = ""; int worstDir = 0;
      double worstEntry = 0.0, worstExit = 0.0;
      datetime lastLossClose = 0;

      for(int i = 0; i < n; i++)
      {
         SReviewTrade rt = trades[i];
         SReviewFlags fl;
         GradeTrade(rt, lastLossClose, fl);
         net += rt.money;
         if(fl.grade == 3) ungraded++; else graded++;
         switch(fl.grade)
         {
            case -1: aPlus++; break;
            case  0: a++;     break;
            case  1: b++;     break;
            case  2: c++;     break;
         }
         if(fl.stopViolation)
         {
            stopV++;
            if(rt.rMult < worstR)
            {
               worstR = rt.rMult; worstSym = rt.sym; worstDir = rt.dir;
               worstEntry = rt.entryPrice; worstExit = rt.exitPrice;
            }
         }
         if(fl.earlyExit)     earlyV++;
         if(fl.heldTooLong)   lateV++;
         if(fl.revenge)       revengeV++;
         if(fl.oversized)     oversizeV++;
         if(rt.money < 0.0)   lastLossClose = rt.exitTime;
      }

      //--- the document's "one goal at a time" directive
      string directive = "report only";
      if(InpFocusSkill == CF_FOCUS_STOPLOSS && stopV > 0)
         directive = "LOCK: fix stop-loss discipline before anything else (one goal at a time)";
      else if(InpFocusSkill == CF_FOCUS_EXITS && (earlyV + lateV) > 0)
         directive = "FOCUS: exit discipline is the one goal today";
      else if(InpFocusSkill == CF_FOCUS_ENTRIES && revengeV > 0)
         directive = "FOCUS: entry selection - no entries straight after a loss";

      int fh = FileOpen(InpReportFile, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(fh == INVALID_HANDLE)
      {
         EA_Log(EA_LOG_ERRORS, "report card: cannot write " + InpReportFile, true);
         return;
      }
      FileSeek(fh, 0, SEEK_END);
      if(FileTell(fh) == 0)
         FileWriteString(fh, "date,trades,graded,ungraded,net,A_plus,A,B,C,stop_violations,"
                             "sold_too_early,held_too_long,revenge_entries,oversized,focus,directive\r\n");
      FileWriteString(fh, StringFormat("%s,%d,%d,%d,%.2f,%d,%d,%d,%d,%d,%d,%d,%d,%d,%s,%s\r\n",
                     TimeToString(day, TIME_DATE), n, graded, ungraded, net,
                     aPlus, a, b, c, stopV, earlyV, lateV, revengeV, oversizeV,
                     FocusName(), directive));
      FileClose(fh);

      EA_Log(EA_LOG_EVENTS, StringFormat(
             "report card %s: %d trade(s) net %.2f | grades A+/A/B/C %d/%d/%d/%d (ungraded %d) | flags: stop %d, early %d, late %d, revenge %d, oversize %d",
             TimeToString(day, TIME_DATE), n, net, aPlus, a, b, c, ungraded,
             stopV, earlyV, lateV, revengeV, oversizeV), true);
      if(stopV > 0)
         EA_Log(EA_LOG_EVENTS, StringFormat("worst stop violation: %.2fR on %s (%s %.5f -> %.5f) - the plan said -1.00R",
                worstR, worstSym, (worstDir > 0 ? "buy" : "sell"), worstEntry, worstExit), true);
      if(directive != "report only")
         EA_Log(EA_LOG_EVENTS, "momentum review directive: " + directive, true);
   }

   //-------------------------------------------------------------------
   // Weekly review: five whys, small wins, playbook count
   //-------------------------------------------------------------------
   void WeeklyReview(const datetime week)
   {
      if(week <= 0) return;
      SReviewTrade trades[];
      int n = BuildTrades(week, week + 7 * 86400, trades);
      if(n <= 0) return;

      int    smallWins = 0, stopV = 0, earlyV = 0, lateV = 0, revengeV = 0, oversizeV = 0;
      double net = 0.0, grossWin = 0.0, bestWin = 0.0;
      ulong  magics[64];
      int    magicCount = 0;
      datetime lastLossClose = 0;
      //--- win / loss days, counted from the trades themselves (exit day)
      datetime dayKey[16];
      double   dayNet[16];
      int      dayCount = 0;

      for(int i = 0; i < n; i++)
      {
         SReviewTrade rt = trades[i];
         SReviewFlags fl;
         GradeTrade(rt, lastLossClose, fl);
         net += rt.money;

         datetime dk = DayStart(rt.exitTime);
         int di = -1;
         for(int k = 0; k < dayCount; k++) if(dayKey[k] == dk) { di = k; break; }
         if(di < 0 && dayCount < 16) { di = dayCount; dayKey[di] = dk; dayNet[di] = 0.0; dayCount++; }
         if(di >= 0) dayNet[di] += rt.money;
         if(rt.money > 0.0)
         {
            grossWin += rt.money;
            if(rt.money > bestWin) bestWin = rt.money;
         }
         if(fl.stopViolation) stopV++;
         if(fl.earlyExit)     earlyV++;
         if(fl.heldTooLong)   lateV++;
         if(fl.revenge)       revengeV++;
         if(fl.oversized)     oversizeV++;
         if(rt.money < 0.0)   lastLossClose = rt.exitTime;

         bool known = false;
         for(int k = 0; k < magicCount; k++) if(magics[k] == rt.magic) { known = true; break; }
         if(!known && magicCount < 64) { magics[magicCount] = rt.magic; magicCount++; }

         //--- a rule-following trade is one the report card could not flag
         if(!fl.stopViolation && !fl.earlyExit && !fl.heldTooLong && !fl.revenge && !fl.oversized)
            smallWins++;
      }

      //--- win / loss days, read off the per-day net accumulated above
      int winDays = 0, lossDays = 0;
      for(int k = 0; k < dayCount; k++)
      {
         if(dayNet[k] > 0.0) winDays++;
         else if(dayNet[k] < 0.0) lossDays++;
      }

      double oneTradeShare = (grossWin > 0.0) ? bestWin / grossWin : 0.0;
      bool tooManyPlaybooks = (magicCount > MathMax(1, InpMaxPlaybooksPerWeek));
      string top = TopMistake(stopV, earlyV, lateV, revengeV, oversizeV);

      WriteWeeklyRow(week, n, smallWins, winDays, lossDays, net, oneTradeShare,
                     magicCount, tooManyPlaybooks ? "too many playbooks at once - master one first" : "ok");
      WriteFiveWhys(week, top);

      EA_Log(EA_LOG_EVENTS, StringFormat(
             "weekly review %s: %d trade(s), %d rule-following small win(s), %d win day(s) / %d loss day(s), net %.2f, top mistake: %s",
             TimeToString(week, TIME_DATE), n, smallWins, winDays, lossDays, net, top), true);
      if(oneTradeShare > 0.6)
         EA_Log(EA_LOG_EVENTS, StringFormat(
                "warning: %.0f%% of the week's gross profit came from a single trade - the document's point is compounded small wins, not one big moment",
                oneTradeShare * 100.0), true);
      if(tooManyPlaybooks)
         EA_Log(EA_LOG_EVENTS, StringFormat(
                "%d magics traded this week - master one playbook before adding others", magicCount), true);
      int weeksLogged = WeeklyRowCount();
      if(weeksLogged > 0 && weeksLogged % MathMax(1, InpWeeksForReview) == 0)
         EA_Log(EA_LOG_EVENTS, StringFormat(
                "%d weeks logged - the document's action item: review progress on process consistency, not P&L",
                weeksLogged), true);
   }

   int WeeklyRowCount()
   {
      int fh = FileOpen(InpWinsFile, FILE_READ | FILE_TXT | FILE_ANSI);
      if(fh == INVALID_HANDLE) return 0;
      int rows = 0, guard = 0;
      while(!FileIsEnding(fh) && guard++ < 200000)
      {
         string line = FileReadString(fh);
         StringTrimLeft(line);
         StringTrimRight(line);
         if(StringLen(line) == 0) continue;
         if(StringSubstr(line, 0, 4) == "week") continue;
         rows++;
      }
      FileClose(fh);
      return rows;
   }

   void WriteWeeklyRow(const datetime week, const int trades, const int smallWins,
                       const int winDays, const int lossDays, const double net,
                       const double oneTradeShare, const int magics, const string note)
   {
      int fh = FileOpen(InpWinsFile, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(fh == INVALID_HANDLE)
      {
         EA_Log(EA_LOG_ERRORS, "weekly review: cannot write " + InpWinsFile, true);
         return;
      }
      FileSeek(fh, 0, SEEK_END);
      if(FileTell(fh) == 0)
         FileWriteString(fh, "week,trades,rule_following_small_wins,win_days,loss_days,net,"
                             "one_trade_share_pct,magics_used,focus,note\r\n");
      FileWriteString(fh, StringFormat("%s,%d,%d,%d,%d,%.2f,%.1f,%d,%s,%s\r\n",
                     TimeToString(week, TIME_DATE), trades, smallWins, winDays, lossDays,
                     net, oneTradeShare * 100.0, magics, FocusName(), note));
      FileClose(fh);
   }

   //--- the document's own action item: five whys with the AI assistant
   void WriteFiveWhys(const datetime week, const string topMistake)
   {
      int fh = FileOpen(InpPromptFile, FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(fh == INVALID_HANDLE) return;
      FileWriteString(fh, "Momentum model - five whys for the week from " + TimeToString(week, TIME_DATE) + "\r\n");
      FileWriteString(fh, "Recurring mistake #1: " + topMistake + "\r\n\r\n");
      FileWriteString(fh, "Ask why five times (the real solution appears at level 4-5):\r\n");
      FileWriteString(fh, "  why 1: why did this happen?\r\n");
      FileWriteString(fh, "  why 2: why did that happen?\r\n");
      FileWriteString(fh, "  why 3: why did that happen?\r\n");
      FileWriteString(fh, "  why 4: why did that happen?\r\n");
      FileWriteString(fh, "  why 5: why did that happen?\r\n\r\n");
      FileWriteString(fh, "Then write ONE clear solution, make it the only goal for the next cycle,\r\n");
      FileWriteString(fh, "and keep the daily report cards coming - the small wins are the compounding.\r\n");
      FileClose(fh);
   }

   string TopMistake(const int stopV, const int earlyV, const int lateV,
                     const int revengeV, const int oversizeV)
   {
      int best = stopV; string name = "did not respect the stop";
      if(earlyV   > best) { best = earlyV;   name = "sold too early"; }
      if(lateV    > best) { best = lateV;    name = "held too long"; }
      if(revengeV > best) { best = revengeV; name = "revenge entry straight after a loss"; }
      if(oversizeV > best) { best = oversizeV; name = "risk above the grade's allocation band"; }
      if(best <= 0) return "none detected - keep the process steady";
      return name;
   }
};

CCfMomentumModelReview g_cfMomentumModelReview;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfMomentumModelReview);
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
