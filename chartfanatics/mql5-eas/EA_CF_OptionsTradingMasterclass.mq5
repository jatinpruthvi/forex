//+------------------------------------------------------------------+
//|              EA_CF_OptionsTradingMasterclass.mq5                  |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| "Options Trading Masterclass" - Usman Ashraf's playbook (Apr 2025) |
//| Card    : chartfanatics/todos/options-trading-masterclass.md (#27) |
//| Source  : chartfanatics/pdf/options-trading-masterclass.pdf        |
//| Magic   : 3230                                                     |
//|                                                                    |
//| VERDICT - the document is a FUNDAMENTALS masterclass, not a         |
//| strategy: it defines the option contract (strike, expiration,       |
//| premium), calls and puts, ITM/ATM/OTM, intrinsic vs extrinsic value,|
//| time decay, implied volatility and the volatility crush, the Greeks |
//| (delta / theta / vega / gamma), liquidity (volume and open interest)|
//| and position sizing.  There is NO entry rule, NO exit rule, NO stop |
//| and NO target anywhere in its ten pages - so this EA does not invent|
//| any.  An MT5 EA cannot price an option chain either: delta, gamma,  |
//| vega and open interest have no CFD feed.                           |
//|                                                                    |
//| What the document DOES state mechanically, and what this EA does:   |
//| it is a MONITOR (it never trades) that audits the account against   |
//| the five operational lessons the playbook teaches, each read from a |
//| quantity an EA can genuinely see - the same way the document itself |
//| turns theory into practice:                                         |
//|                                                                    |
//|   PREMIUM = MAXIMUM RISK.  "The premium ... is also the maximum     |
//|   risk for the buyer"; "Buyers pay the premium ... Their risk is    |
//|   capped at that premium."  -> every live position's money at risk  |
//|   (EA_LossPerLot x volume, the engine's own money-risk helper) must |
//|   stay inside the configured premium budget; a position with no     |
//|   stop has no defined premium and is flagged separately (for a CFD  |
//|   that is the opposite of the buyer's capped risk).                 |
//|                                                                    |
//|   THETA = TIME DECAY.  "As expiration approaches, the extrinsic     |
//|   value steadily decreases"; "buying options too close to           |
//|   expiration can be risky: time is constantly working against the   |
//|   buyer"; "Day traders may prefer weekly or zero-day contracts,     |
//|   while swing traders often benefit from expirations weeks or       |
//|   months away."  -> each position is audited against the holding     |
//|   horizon the trader's own style implies, and positions carried      |
//|   past it are counted and reported.                                  |
//|                                                                    |
//|   LIQUIDITY = FILLS.  "Liquidity determines how easily you can get  |
//|   in and out of a trade without delays or poor fills"; "if a strike |
//|   only has 100 contracts of open interest and you want to buy 70    |
//|   contracts, you may struggle to get filled quickly."  -> the fill  |
//|   quality is read from the engine's own slippage ring                |
//|   (EA_SlipMedianR) and the spread baseline (EA_SpreadBaseline); both |
//|   are reported daily and flagged against the trader's budgets.       |
//|                                                                    |
//|   VEGA / IV = VOLATILITY CRUSH.  "before a company announces        |
//|   earnings, implied volatility usually spikes ... Once the news is  |
//|   released, IV often drops sharply ... This is known as volatility  |
//|   crush."  -> no IV feed exists for a CFD symbol, so the proxy is    |
//|   the realised expansion of the day's range against its own          |
//|   `InpMedianDays`-day median; a position entered while that ratio is |
//|   above the flag is counted and reported as an "expanded-volatility  |
//|   entry" - the exact situation the document warns pays rich premium. |
//|                                                                    |
//|   SIZING = CONCENTRATION.  "A small sideways move can wipe out much |
//|   of the premium"; "how you size your positions matters"; "Options  |
//|   offer incredible leverage - but without discipline, losses can     |
//|   compound just as quickly as gains."  -> the day's peak deployed    |
//|   risk (sum of live money-at-risk / equity) is tracked against the   |
//|   configured deployment cap.                                         |
//|                                                                    |
//| The output is the trader's own study sheet, exactly what the         |
//| document's closing line asks for ("Master the basics, respect the   |
//| risks"): a daily CSV row per tenet, a plain-text tenets card with   |
//| PASS/FLAG for the day just ended, and a live risk registry snapshot  |
//| - so every rule the playbook teaches is being watched on the account |
//| the trader actually runs.                                            |
//|                                                                    |
//| [interpretation]: the premium budget percentages, the deployment cap,|
//| the style horizons in hours, the volatility-expansion flag, the      |
//| slippage and spread flags and the median baseline window are         |
//| engineering numbers the document does not state (it gives no sizes,  |
//| no hours and no thresholds at all) - all exposed as inputs.  The     |
//| Greeks themselves are NOT implemented: delta / gamma / theta / vega  |
//| are option-chain quantities, and their CFD stand-ins are reported    |
//| only where they are honest (money risk = the premium analogue, time  |
//| carried = the theta analogue, fills and spreads = the liquidity      |
//| analogue, realised expansion = the IV analogue).  Withdrawal of the  |
//| analogy where it breaks is deliberate: no fake "delta" is printed.   |
//|                                                                    |
//| Rule -> code sync (see tests/test_chartfanatics_sync.py):            |
//|   R1  premium = maximum risk      -> PremiumAudit()                  |
//|   R2  risk capped at the premium  -> InpPremiumBudgetPct             |
//|   R3  writers carry greater risk  -> no-stop positions flagged       |
//|   R4  time decay / theta          -> HoldAudit()                     |
//|   R5  style decides the horizon   -> InpStyle / InpMaxHoldHours*     |
//|   R6  liquidity = fills           -> LiquidityAudit() (EA_SlipMedianR)
//|   R7  open interest vs order size -> InpSlipFlagR                    |
//|   R8  IV spike and the crush      -> VolAudit() / InpVolExpansionFlag|
//|   R9  sizing / leverage           -> InpMaxDeployedPct               |
//|   R10 premium budget in money     -> EA_LossPerLot()                 |
//|   R11 daily study sheet           -> InpReportFile / TENT card       |
//|   R12 the five tenets             -> TenetsFile()                    |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "Options Trading Masterclass monitor (never trades): audits the account against the playbook's five operational lessons - premium as maximum risk, time decay, fills/liquidity, the volatility-crush analogue and position sizing - and writes a daily study sheet plus a tenets card"

#include "..\..\Include\EACommon.mqh"

//--- the trader's own style decides the holding horizon the document describes
enum ENUM_CF_STYLE
{
   CF_STYLE_DAY   = 0,   // "day traders may prefer weekly or zero-day contracts"
   CF_STYLE_SWING = 1    // "swing traders often benefit from expirations weeks or months away"
};

//--- identity
input string            InpSymbolsToTrade    = "US100,US500";     // symbols this monitor follows
input ulong             InpMagicNumber       = 3230;              // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ulong             InpMagicFilter       = 0;                 // 0 = every magic on the account (a monitor)
input int               InpStage             = 5;                 // 5-Stage framework stage (5 = policy off)
input int               InpServerGmtOffset   = 2;                 // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel          = EA_LOG_EVENTS;     // Log verbosity
input bool              InpLedger            = true;              // Write the engine evidence ledger CSV
//--- premium = maximum risk ("the premium ... is also the maximum risk for the buyer")
input double            InpPremiumBudgetPct  = 1.0;               // [interpretation] money at risk per position (<= x% equity)
input bool              InpUseAllInRisk      = true;              // count commission in the money-at-risk figure
input double            InpCommissionPerLotRT = 0.0;              // Round-turn commission per lot
//--- sizing / concentration ("how you size your positions matters")
input double            InpMaxDeployedPct    = 3.0;               // [interpretation] peak live risk (<= x% equity)
//--- theta ("time is constantly working against the buyer")
input ENUM_CF_STYLE     InpStyle             = CF_STYLE_DAY;      // "matching your position size and expiration to your trading style"
input double            InpMaxHoldHoursDay   = 8.0;               // [interpretation] day-style horizon (zero-day / weekly)
input double            InpMaxHoldHoursSwing = 120.0;             // [interpretation] swing-style horizon (weeks / months)
//--- liquidity ("you may struggle to get filled quickly")
input double            InpSlipFlagR         = 0.10;              // [interpretation] median fill slippage budget (R)
input double            InpSpreadFlagPts     = 5.0;               // [interpretation] median spread budget (points)
//--- IV / volatility crush ("implied volatility usually spikes ... once the news is released, IV often drops")
input double            InpVolExpansionFlag  = 1.50;              // [interpretation] day range vs its baseline = "expanded"
input int               InpMedianDays        = 20;                // [interpretation] baseline window for that ratio
//--- outputs (the trader's study sheet)
input string            InpReportFile        = "cf_options_masterclass_audit.csv";   // daily audit rows
input string            InpTentFile          = "cf_options_tenets.txt";              // the five tenets, checked daily
input string            InpRegistryFile      = "cf_options_risk_registry.txt";       // live risk registry snapshot

//+------------------------------------------------------------------+
class CCfOptionsMasterclassAudit : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_OPTIONS_MASTERCLASS_AUDIT";
      cfg.sourceDoc             = "chartfanatics/pdf/options-trading-masterclass.pdf (card #27)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = 0.0;                 // a monitor never sizes a trade
      cfg.signalTimeframe       = PERIOD_M15;          // report/audit tick, not a trading timeframe
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxTradesPerDay       = 0;
      cfg.maxOpenPositions      = 0;
      cfg.dailyLossPct          = 0.0;
      cfg.weeklyLossPct         = 0.0;
      cfg.totalDdPct            = 0.0;
      cfg.useLimitEntry         = false;
      cfg.signalOnNewBarOnly    = false;
      cfg.newsFilter            = false;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_options_masterclass_ledger.csv";
      cfg.logLevel              = InpLogLevel;
      cfg.sessionStartHour      = 0; cfg.sessionStartMin = 0;
      cfg.sessionEndHour        = 23; cfg.sessionEndMin  = 59;
      cfg.noTradeAfterHour      = -1;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   void OnInitStrategy()
   {
      m_lastDay    = 0;
      m_dayViolations = 0;
      m_dayNoStop = 0;
      m_dayExpandedEntries = 0;
      m_dayMaxDeployedPct = 0.0;
      m_dayEquityStart = AccountInfoDouble(ACCOUNT_EQUITY);
      m_regCount = 0;
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "options masterclass monitor armed (never trades): premium budget %.2f%% of equity, deployment cap %.2f%%, %s style horizon %.0f h, slip flag %.2fR, spread flag %.1f pts, expansion flag %.2fx",
             InpPremiumBudgetPct, InpMaxDeployedPct, (InpStyle == CF_STYLE_DAY ? "day" : "swing"),
             StyleHorizonHours(), InpSlipFlagR, InpSpreadFlagPts, InpVolExpansionFlag), true);
      EA_Log(EA_LOG_EVENTS, "delta / gamma / theta / vega and open interest are option-chain quantities with no CFD feed - the analogies are labelled and nothing is faked", true);
   }

   //--- a monitor: it never proposes a trade
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan) { plan.Reset(); return false; }

   void Manage(SEAContext &ctx)
   {
      ScanPositions(ctx);

      datetime day = DayStart(TimeTradeServer());
      if(day != m_lastDay)
      {
         m_lastDay = day;
         DailyAudit(day - 86400);                     // the day that just ended
      }
   }

private:
   datetime m_lastDay;
   double   m_dayEquityStart;
   int      m_dayViolations;
   int      m_dayNoStop;
   int      m_dayExpandedEntries;
   double   m_dayMaxDeployedPct;

   //--- live registry: every position the monitor has seen, so a closed trade
   //--- still counts in the day's audit (the engine's risk key dies with the
   //--- position, so the monitor snapshots what it saw while it was live)
   ulong    m_regTicket[];
   string   m_regSym[];
   double   m_regMoney[];
   double   m_regVolume[];
   datetime m_regSeen[];
   bool     m_regNoStop[];
   bool     m_regViolated[];
   int      m_regCount;

   //-------------------------------------------------------------------
   // calendar (London clock, like the family)
   //-------------------------------------------------------------------
   datetime DayStart(const datetime t)
   {
      MqlDateTime d;
      TimeToStruct(t, d);
      d.hour = 0; d.min = 0; d.sec = 0;
      return StructToTime(d);
   }

   double StyleHorizonHours()
   {
      return (InpStyle == CF_STYLE_DAY) ? InpMaxHoldHoursDay : InpMaxHoldHoursSwing;
   }

   //-------------------------------------------------------------------
   // the five tenets, read from quantities an EA can actually see
   //-------------------------------------------------------------------
   double MoneyAtRisk(const string sym, const double volume, const double slDistance)
   {
      if(volume <= 0.0 || slDistance <= 0.0) return 0.0;
      double perLot = InpUseAllInRisk
                      ? EA_LossPerLotAllIn(sym, slDistance, InpCommissionPerLotRT)
                      : EA_LossPerLot(sym, slDistance);
      return perLot * volume;
   }

   //--- "implied volatility usually spikes": realised expansion of today's range
   //--- against its own `InpMedianDays`-day median (the labelled IV proxy)
   double VolExpansionRatio(const string sym)
   {
      MqlRates r[];
      int got = EA_Rates(sym, PERIOD_D1, 0, InpMedianDays + 3, r);
      if(got < 5) return 0.0;
      double today = r[0].high - r[0].low;
      if(today <= 0.0) return 0.0;
      int n = MathMin(InpMedianDays, got - 1);
      double v[];
      ArrayResize(v, n);
      for(int i = 0; i < n; i++) v[i] = r[i + 1].high - r[i + 1].low;
      double med = MedianOf(v);
      if(med <= 0.0) return 0.0;
      return today / med;
   }

   double MedianOf(double &v[])
   {
      int n = ArraySize(v);
      if(n <= 0) return 0.0;
      //--- insertion sort: the samples are small and it never allocates again
      for(int i = 1; i < n; i++)
      {
         double key = v[i];
         int j = i - 1;
         while(j >= 0 && v[j] > key) { v[j + 1] = v[j]; j--; }
         v[j + 1] = key;
      }
      if(n % 2 == 1) return v[n / 2];
      return 0.5 * (v[n / 2 - 1] + v[n / 2]);
   }

   //--- per-trade holding times for the audited day (entry deal -> exit deal)
   //--- two passes: the day's closes pick the positions, HistorySelectByPosition
   //--- then gives every one of them its TRUE open time (cross-day holds included)
   void DayHoldStats(const datetime day, double &avgHold, double &maxHold, int &trades, int &beyond)
   {
      avgHold = 0.0; maxHold = 0.0; trades = 0; beyond = 0;
      datetime dayEnd = day + 86400;
      if(!HistorySelect(day, dayEnd)) return;

      long  pids[];
      int   used  = 0;
      int   total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if(InpMagicFilter != 0 && (ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagicFilter) continue;
         if(!SymInScope(HistoryDealGetString(t, DEAL_SYMBOL))) continue;
         int entry = (int)HistoryDealGetInteger(t, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) continue;   // a close inside the day
         long pid = HistoryDealGetInteger(t, DEAL_POSITION_ID);
         if(pid == 0) continue;
         bool have = false;
         for(int k = 0; k < used; k++) if(pids[k] == pid) { have = true; break; }
         if(have || used >= 128) continue;
         used++;
         ArrayResize(pids, used);
         pids[used - 1] = pid;
      }

      double horizon = StyleHorizonHours();
      for(int k = 0; k < used; k++)
      {
         if(!HistorySelectByPosition(pids[k])) continue;
         datetime openT = 0, closeT = 0;
         int n = HistoryDealsTotal();
         for(int i = 0; i < n; i++)
         {
            ulong t = HistoryDealGetTicket(i);
            if(t == 0) continue;
            datetime dt = (datetime)HistoryDealGetInteger(t, DEAL_TIME);
            int entry = (int)HistoryDealGetInteger(t, DEAL_ENTRY);
            if(entry == DEAL_ENTRY_IN && (openT == 0 || dt < openT)) openT = dt;
            if((entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY) && dt > closeT) closeT = dt;
         }
         if(openT == 0 || closeT == 0) continue;
         if(closeT < day || closeT >= dayEnd) continue;                        // closed yesterday: yesterday's sheet
         double hours = (double)(closeT - openT) / 3600.0;
         trades++;
         avgHold += hours;
         if(hours > maxHold) maxHold = hours;
         if(hours > horizon) beyond++;
      }
      if(trades > 0) avgHold /= (double)trades;
   }

   //-------------------------------------------------------------------
   // live scan: registers positions, counts the day's flags
   //-------------------------------------------------------------------
   void ScanPositions(const SEAContext &ctx)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0.0) return;
      double budget = equity * InpPremiumBudgetPct / 100.0;

      double deployed = 0.0;

      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong ticket = PositionGetTicket(p);
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         if(InpMagicFilter != 0 && (ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicFilter) continue;

         string sym    = PositionGetString(POSITION_SYMBOL);
         double volume = PositionGetDouble(POSITION_VOLUME);
         double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl     = PositionGetDouble(POSITION_SL);
         bool   noStop = (sl <= 0.0);
         double dist   = noStop ? 0.0 : MathAbs(entry - sl);
         double money  = MoneyAtRisk(sym, volume, dist);

         if(!noStop) deployed += money;

         //--- register on first sight, with the volatility read at entry time
         int known = RegIndex(ticket);
         if(known < 0)
         {
            int n = m_regCount;
            ArrayResize(m_regTicket, n + 1);
            ArrayResize(m_regSym, n + 1);
            ArrayResize(m_regMoney, n + 1);
            ArrayResize(m_regVolume, n + 1);
            ArrayResize(m_regSeen, n + 1);
            ArrayResize(m_regNoStop, n + 1);
            ArrayResize(m_regViolated, n + 1);
            m_regTicket[n] = ticket;
            m_regSym[n]    = sym;
            m_regMoney[n]  = money;
            m_regVolume[n] = volume;
            m_regSeen[n]    = TimeTradeServer();
            m_regNoStop[n]  = noStop;
            m_regViolated[n] = (!noStop && money > budget);
            m_regCount      = n + 1;

            //--- the day's counters are per position: one flag each, never per tick
            if(noStop) m_dayNoStop++;
            else if(money > budget) m_dayViolations++;

            double ratio = VolExpansionRatio(sym);
            if(!noStop && ratio >= InpVolExpansionFlag) m_dayExpandedEntries++;
         }
         else
         {
            //--- "sizing to zero": a stop that is moved changes the money at risk;
            //--- crossing a line is counted once per position
            m_regMoney[known] = money;
            if(noStop && !m_regNoStop[known]) m_dayNoStop++;
            if(!noStop && !m_regViolated[known] && money > budget)
            {
               m_regViolated[known] = true;
               m_dayViolations++;
            }
            m_regNoStop[known] = noStop;
         }
      }

      double deployedPct = (equity > 0.0) ? (deployed / equity) * 100.0 : 0.0;
      if(deployedPct > m_dayMaxDeployedPct) m_dayMaxDeployedPct = deployedPct;
   }

   bool SymInScope(const string sym)
   {
      for(int i = 0; i < g_eaSymbolCount; i++)
         if(g_eaSymbols[i] == sym) return true;
      return false;
   }

   int RegIndex(const ulong ticket)
   {
      for(int i = 0; i < m_regCount; i++)
         if(m_regTicket[i] == ticket) return i;
      return -1;
   }

   //-------------------------------------------------------------------
   // the daily study sheet: one CSV row + the tenets card
   //-------------------------------------------------------------------
   void DailyAudit(const datetime day)
   {
      double equityNow = AccountInfoDouble(ACCOUNT_EQUITY);
      double dayPl     = equityNow - m_dayEquityStart;

      double slipR     = SlipAcrossScope();
      double spreadPts = SpreadAcrossScope();

      //--- the theta read comes from the day's deal history: entry deal -> exit deal,
      //--- so the holding time is per TRADE, not per tick
      double avgHold = 0.0, maxHold = 0.0;
      int    trades = 0, beyond = 0;
      DayHoldStats(day, avgHold, maxHold, trades, beyond);

      //--- the five tenets, PASS/FLAG for the day that ended
      bool premiumOk  = (m_dayViolations == 0 && m_dayNoStop == 0);
      bool thetaOk    = (beyond == 0);
      bool liquidOk   = (slipR <= InpSlipFlagR && spreadPts <= InpSpreadFlagPts);
      bool volOk      = (m_dayExpandedEntries == 0);
      bool sizingOk   = (m_dayMaxDeployedPct <= InpMaxDeployedPct);
      int  passed     = (premiumOk ? 1 : 0) + (thetaOk ? 1 : 0) + (liquidOk ? 1 : 0)
                      + (volOk ? 1 : 0) + (sizingOk ? 1 : 0);

      //--- the CSV row
      int fh = FileOpen(InpReportFile, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(fh != INVALID_HANDLE)
      {
         FileSeek(fh, 0, SEEK_END);
         if(FileTell(fh) == 0)
            FileWriteString(fh, "date,closed_trades,premium_violations,no_stop_positions,max_deployed_pct,avg_hold_hours,max_hold_hours,held_beyond_style,median_slip_r,median_spread_pts,expanded_vol_entries,day_pl,tenets_passed\r\n");
         FileWriteString(fh, StringFormat("%s,%d,%d,%d,%.2f,%.2f,%.2f,%d,%.3f,%.2f,%d,%.2f,%d/5\r\n",
                         TimeToString(day, TIME_DATE), trades, m_dayViolations, m_dayNoStop,
                         m_dayMaxDeployedPct, avgHold, maxHold, beyond,
                         slipR, spreadPts, m_dayExpandedEntries, dayPl, passed));
         FileClose(fh);
      }
      else
         EA_Log(EA_LOG_ERRORS, StringFormat("cannot write %s (error %d)", InpReportFile, GetLastError()), true);

      //--- the tenets card the trader reads
      TenetsCard(day, premiumOk, thetaOk, liquidOk, volOk, sizingOk, slipR, spreadPts,
                 avgHold, maxHold, beyond, trades, passed);
      WriteRegistry();
      LogFlags(day, premiumOk, thetaOk, liquidOk, volOk, sizingOk, passed);

      //--- reset the day counters for the day that just started
      m_dayViolations = 0;
      m_dayNoStop = 0;
      m_dayExpandedEntries = 0;
      m_dayMaxDeployedPct = 0.0;
      m_dayEquityStart = equityNow;
      PruneRegistry();                                 // closed tickets retire with the day
   }

   //--- keep the live registry alive, drop everyone else (bounded memory, fresh file)
   void PruneRegistry()
   {
      int keep = 0;
      for(int i = 0; i < m_regCount; i++)
      {
         if(!PositionSelectByTicket(m_regTicket[i])) continue;   // closed or otherwise gone
         if(keep != i)
         {
            m_regTicket[keep] = m_regTicket[i];
            m_regSym[keep]    = m_regSym[i];
            m_regMoney[keep]  = m_regMoney[i];
            m_regVolume[keep] = m_regVolume[i];
            m_regSeen[keep]   = m_regSeen[i];
            m_regNoStop[keep] = m_regNoStop[i];
            m_regViolated[keep] = m_regViolated[i];
         }
         keep++;
      }
      m_regCount = keep;
   }

   void OnDeinitStrategy()
   {
      WriteRegistry();                                  // keep the last snapshot on the reader's desk
   }

   string TenetName(const int i)
   {
      if(i == 0) return "PREMIUM = MAXIMUM RISK";
      if(i == 1) return "THETA = TIME DECAY";
      if(i == 2) return "LIQUIDITY = FILLS";
      if(i == 3) return "VEGA = VOLATILITY CRUSH";
      return "SIZING = CONCENTRATION";
   }

   void TenetsCard(const datetime day, const bool pOk, const bool tOk, const bool lOk,
                   const bool vOk, const bool sOk, const double slipR, const double spreadPts,
                   const double avgHold, const double maxHold, const int beyond,
                   const int trades, const int passed)
   {
      int fh = FileOpen(InpTentFile, FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(fh == INVALID_HANDLE) return;
      FileWriteString(fh, "Options Trading Masterclass - daily tenets card (Usman Ashraf's playbook)\r\n");
      FileWriteString(fh, StringFormat("day audited: %s   tenets passed: %d/5\r\n\r\n", TimeToString(day, TIME_DATE), passed));
      FileWriteString(fh, StringFormat("[%s] %s\r\n  money at risk above the budget: %d   positions with no stop (no defined premium): %d\r\n",
                     pOk ? "PASS" : "FLAG", TenetName(0), m_dayViolations, m_dayNoStop));
      FileWriteString(fh, StringFormat("[%s] %s\r\n  %d closed trades: average hold %.1f h, longest %.1f h, held past the %s-style %.0f h horizon: %d\r\n",
                     tOk ? "PASS" : "FLAG", TenetName(1), trades, avgHold, maxHold,
                     (InpStyle == CF_STYLE_DAY ? "day" : "swing"), StyleHorizonHours(), beyond));
      FileWriteString(fh, StringFormat("[%s] %s\r\n  median fill slippage %.3fR (budget %.2fR), median spread %.2f pts (budget %.2f)\r\n",
                     lOk ? "PASS" : "FLAG", TenetName(2), slipR, InpSlipFlagR, spreadPts, InpSpreadFlagPts));
      FileWriteString(fh, StringFormat("[%s] %s\r\n  entries taken while the day range was >= %.2fx its %d-day median: %d\r\n",
                     vOk ? "PASS" : "FLAG", TenetName(3), InpVolExpansionFlag, InpMedianDays, m_dayExpandedEntries));
      FileWriteString(fh, StringFormat("[%s] %s\r\n  peak live risk %.2f%% of equity (cap %.2f%%)\r\n",
                     sOk ? "PASS" : "FLAG", TenetName(4), m_dayMaxDeployedPct, InpMaxDeployedPct));
      FileWriteString(fh, "\r\ndelta, gamma and vega are option-chain quantities with no CFD feed: they are not faked here.\r\n");
      FileClose(fh);
   }

   void LogFlags(const datetime day, const bool pOk, const bool tOk, const bool lOk,
                 const bool vOk, const bool sOk, const int passed)
   {
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "options masterclass audit %s: %d/5 tenets passed (premium %s, theta %s, liquidity %s, vega %s, sizing %s)",
             TimeToString(day, TIME_DATE), passed,
             pOk ? "ok" : "FLAG", tOk ? "ok" : "FLAG", lOk ? "ok" : "FLAG",
             vOk ? "ok" : "FLAG", sOk ? "ok" : "FLAG"), true);
   }

   //--- liquidity read across the monitored universe (the engine's own rings)
   double SlipAcrossScope()
   {
      double worst = 0.0;
      for(int i = 0; i < g_eaSymbolCount; i++)
      {
         double v = EA_SlipMedianR(g_eaSymbols[i]);
         if(v > worst) worst = v;
      }
      return worst;
   }

   double SpreadAcrossScope()
   {
      double worst = 0.0;
      for(int i = 0; i < g_eaSymbolCount; i++)
      {
         double v = EA_SpreadPoints(g_eaSymbols[i]);
         if(v > 0.0 && v < 1e11 && v > worst) worst = v;
      }
      return worst;
   }

   //--- live risk registry: what the monitor saw while it was live
   void WriteRegistry()
   {
      int fh = FileOpen(InpRegistryFile, FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(fh == INVALID_HANDLE) return;
      FileWriteString(fh, "ticket,symbol,volume,money_at_risk,no_stop,first_seen\r\n");
      for(int i = 0; i < m_regCount; i++)
      {
         if(!PositionSelectByTicket(m_regTicket[i])) continue;    // only what is still live
         FileWriteString(fh, StringFormat("%I64u,%s,%.2f,%.2f,%s,%s\r\n",
                         m_regTicket[i], m_regSym[i], m_regVolume[i], m_regMoney[i],
                         m_regNoStop[i] ? "yes" : "no", TimeToString(m_regSeen[i], TIME_DATE | TIME_MINUTES)));
      }
      FileClose(fh);
   }
};

CCfOptionsMasterclassAudit g_cfOptionsMasterclassAudit;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfOptionsMasterclassAudit);
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
