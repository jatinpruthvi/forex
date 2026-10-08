//+------------------------------------------------------------------+
//|                                  EA_CF_AlgoPortfolioMonitor.mq5  |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| ChartFanatics: "Master ALGO Trading In Less Than 90 Minutes      |
//|                  (NO Coding) | $1M+ Profits"                     |
//| Card    : chartfanatics/todos/algorithmic-strategy.md   (#03)     |
//| Source  : chartfanatics/glimpse/TyHTEtArsS4.md (video, no PDF)    |
//| Magic   : 3209                                                    |
//|                                                                  |
//| READ THIS FIRST - what this document is and is not:               |
//|                                                                  |
//| The video is NOT a strategy.  It teaches how to BUILD and OPERATE |
//| a portfolio of algorithms: define 2-3 entry rules, backtest across|
//| regimes, filter candidates by robustness (out-of-sample, Monte    |
//| Carlo, parameter sensitivity), rank them by metrics, then monitor |
//| them continuously.  There is no entry, exit, stop, target,        |
//| instrument or session rule in it, so this EA invents none.        |
//|                                                                  |
//| What IS checkable in the document is the part a running portfolio |
//| has to satisfy, and that is what this EA mechanizes:              |
//|                                                                  |
//|   * profit factor    >= 1.5          (ranking filters)            |
//|   * return / max DD  >= 4 : 1        (ranking filters)            |
//|   * >= 2 trades per month            (ranking filters)            |
//|   * average loss     <= 0.5% of account                           |
//|   * implied allocation per algorithm within 5-25% of the account  |
//|   * drawdown flagged past the 20-25% the document calls realistic |
//|   * expectancy from win rate and reward:risk ("breakout traders   |
//|     can be profitable with only a 40% success rate ... risking    |
//|     $1 to make $2")                                               |
//|                                                                  |
//| It reads the ACCOUNT's own deal history - every magic, i.e. every |
//| algorithm in the portfolio - groups it per magic, and writes one  |
//| ranking row per algorithm per scan to a journal CSV.              |
//|                                                                  |
//| `[interpretation]` marks where the document gives an example      |
//| number rather than a hard rule, or where a metric is a proxy:     |
//| Sharpe / UPI are not computable from deal history alone, so the   |
//| return/DD ratio the same page quotes is reported instead.         |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics algo-portfolio monitor - rank live algorithms against the document's filters (never trades)"

#include "..\..\Include\EACommon.mqh"

//--- identity / plumbing
input string            InpSymbolsToTrade   = "EURUSD";             // Unused for trading: the engine needs one symbol to init
input ulong             InpMagicNumber      = 3209;                 // UNIQUE MAGIC NUMBER (identity only - this EA never trades)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;        // Log verbosity
input int               InpServerGmtOffset  = 2;                    // Broker server clock minus GMT (winter)
//--- what is measured, and over which window
input int    InpLookbackDays      = 90;     // Window the portfolio metrics are computed over
input int    InpScanMinutes       = 240;    // Re-scan interval ("continuous monitoring, not passive automation")
input int    InpMinTradesForStats = 10;     // Below this a row is INSUFFICIENT (no verdict is fabricated)
//--- the document's ranking filters and bands (thresholds quoted from the source)
input double InpMinProfitFactor   = 1.50;   // "profit factor (e.g., 1.5+)"
input double InpMinReturnDD       = 4.00;   // "return-to-drawdown ratio (e.g., 4:1)"
input double InpMinTradesPerMonth = 2.00;   // "average trades per month (e.g., 2+)"
input double InpMaxAvgLossPct     = 0.50;   // "average loss as a percentage of account (e.g., 0.5%)"
input double InpAvgLossRulePct    = 0.50;   // "avg loss does not exceed 0.5% of that allocated amount"
input double InpMinAllocPct       = 5.0;    // "allocate 5-25% of total account to a single algorithm"
input double InpMaxAllocPct       = 25.0;
input double InpExpectedDdPct     = 25.0;   // "realistic drawdowns of 20-25%" -> flag beyond the top of the band
//--- output
input string InpJournalFile       = "cf_algo_ranking.csv";   // MQL5/Files/ ranking journal

//+------------------------------------------------------------------+
//| Per-algorithm (per-magic) statistics from the account's history   |
//+------------------------------------------------------------------+
struct SAlgoStats
{
   long     magic;
   int      entries;
   int      closes;
   int      wins;
   int      losses;
   double   grossProfit;
   double   grossLoss;         // positive number
   double   winSum;            // sum of winning closes
   double   lossSum;           // positive sum of losing closes
   double   cumPl;             // running cumulative P/L (for the drawdown walk)
   double   peakPl;            // running high-water mark of cumPl
   double   maxDd;             // peak-to-trough of cumPl
   double   net;
   double   tradesPerMonth;
   double   winRate;
   double   avgWinR;
   double   profitFactor;
   double   returnDD;
   double   avgLossPctOfBal;
   double   impliedAllocPct;
   double   expectancyR;

   void Reset()
   {
      magic = 0; entries = 0; closes = 0; wins = 0; losses = 0;
      grossProfit = 0.0; grossLoss = 0.0; winSum = 0.0; lossSum = 0.0;
      cumPl = 0.0; peakPl = 0.0; maxDd = 0.0; net = 0.0; tradesPerMonth = 0.0;
      winRate = 0.0; avgWinR = 0.0; profitFactor = 0.0; returnDD = 0.0;
      avgLossPctOfBal = 0.0; impliedAllocPct = 0.0; expectancyR = 0.0;
   }
};

//+------------------------------------------------------------------+
//| Strategy class - a portfolio monitor that deliberately never      |
//| trades (the document's subject is how to RUN algorithms, not one) |
//+------------------------------------------------------------------+
class CCfAlgoPortfolioMonitor : public CEAStrategy
{
public:
   void OnInitStrategy()
   {
      m_lastScan = 0;
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "algo-portfolio monitor active: %.1f-day window; filters PF>=%.2f, return/DD>=%.1f, "
             "trades/month>=%.1f, avg loss<=%.2f%% (implied allocation %.0f-%.0f%%)",
             (double)InpLookbackDays, InpMinProfitFactor, InpMinReturnDD, InpMinTradesPerMonth,
             InpMaxAvgLossPct, InpMinAllocPct, InpMaxAllocPct), true);
      EA_Log(EA_LOG_EVENTS, "this EA never opens positions - it ranks the algorithms already trading", true);
   }

   void OnDeinitStrategy()
   {
      if(m_lastScan <= 0) return;
      Scan(true);                       // never lose the last snapshot on a chart unload
   }

   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_ALGO_PORTFOLIO_MONITOR";
      cfg.sourceDoc             = "chartfanatics/glimpse/TyHTEtArsS4.md (card #03)";
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
      cfg.ledgerEnabled         = false;        // its journal is the deliverable, not the engine ledger
      cfg.logLevel              = InpLogLevel;
   }

   //--- never trades, and says so instead of merely failing to find a signal
   bool AllowTrading(SEAContext &ctx) { return false; }
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan) { plan.Reset(); return false; }

   void Manage(SEAContext &ctx)
   {
      datetime now = TimeTradeServer();
      if(m_lastScan > 0 && now - m_lastScan < (datetime)(InpScanMinutes * 60)) return;
      Scan(false);
      m_lastScan = now;
   }

private:
   datetime m_lastScan;

   //--- one pass over the account's deals, grouped per magic (= per algorithm).
   //--- HistorySelect returns deals in chronological order, so the drawdown walk is a running
   //--- high-water mark of each algorithm's cumulative P/L.
   void Scan(const bool finalPass)
   {
      datetime from = TimeTradeServer() - (datetime)InpLookbackDays * 86400;
      if(!HistorySelect(from, TimeTradeServer() + 60))
      {
         EA_Log(EA_LOG_ERRORS, "algo monitor: HistorySelect failed", true);
         return;
      }

      SAlgoStats algos[];
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         long type = HistoryDealGetInteger(ticket, DEAL_TYPE);
         if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL) continue;
         long entryKind = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);

         int slot = SlotOf(algos, magic);
         if(entryKind == DEAL_ENTRY_IN) { algos[slot].entries++; continue; }
         if(entryKind != DEAL_ENTRY_OUT && entryKind != DEAL_ENTRY_OUT_BY &&
            entryKind != DEAL_ENTRY_INOUT) continue;

         double pl = HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                     HistoryDealGetDouble(ticket, DEAL_SWAP) +
                     HistoryDealGetDouble(ticket, DEAL_COMMISSION);

         algos[slot].closes++;
         algos[slot].net   += pl;
         algos[slot].cumPl += pl;
         if(pl > 0.0)      { algos[slot].wins++;   algos[slot].grossProfit += pl;  algos[slot].winSum  += pl; }
         else if(pl < 0.0) { algos[slot].losses++; algos[slot].grossLoss += -pl;   algos[slot].lossSum += -pl; }
         if(algos[slot].cumPl > algos[slot].peakPl) algos[slot].peakPl = algos[slot].cumPl;
         double dd = algos[slot].peakPl - algos[slot].cumPl;
         if(dd > algos[slot].maxDd) algos[slot].maxDd = dd;
      }

      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      int flagged = 0, ranked = 0, insufficient = 0, scored = 0;
      for(int a = 0; a < ArraySize(algos); a++)
      {
         if(algos[a].closes <= 0) continue;
         scored++;

         //--- derive the metrics in place (the struct stays plain data - no copies of strings)
         algos[a].tradesPerMonth  = (double)algos[a].closes / ((double)InpLookbackDays / 30.44);
         algos[a].winRate         = (double)algos[a].wins / (double)algos[a].closes;
         algos[a].profitFactor    = (algos[a].grossLoss > 0.0) ? algos[a].grossProfit / algos[a].grossLoss : 0.0;
         algos[a].returnDD        = (algos[a].maxDd > 0.0) ? algos[a].net / algos[a].maxDd : 0.0;
         double avgLoss           = (algos[a].losses > 0) ? algos[a].lossSum / (double)algos[a].losses : 0.0;
         double avgWin            = (algos[a].wins   > 0) ? algos[a].winSum  / (double)algos[a].wins   : 0.0;
         algos[a].avgWinR         = (avgLoss > 0.0) ? avgWin / avgLoss : 0.0;
         algos[a].expectancyR     = algos[a].winRate * algos[a].avgWinR - (1.0 - algos[a].winRate);
         algos[a].avgLossPctOfBal = (balance > 0.0) ? avgLoss / balance * 100.0 : 0.0;
         //--- the sizing rule inverted: allocation = average loss / 0.5%
         algos[a].impliedAllocPct = (balance > 0.0 && InpAvgLossRulePct > 0.0)
                                    ? (avgLoss / (InpAvgLossRulePct / 100.0)) / balance * 100.0 : 0.0;

         string verdict = "";
         if(algos[a].closes < InpMinTradesForStats)
         {
            verdict = "INSUFFICIENT";
            insufficient++;
         }
         else
         {
            string notes = "";
            if(algos[a].profitFactor < InpMinProfitFactor)      notes += "PF<min;";
            if(algos[a].returnDD < InpMinReturnDD)              notes += "return/DD<min;";
            if(algos[a].tradesPerMonth < InpMinTradesPerMonth)  notes += "too-few-trades;";
            if(algos[a].avgLossPctOfBal > InpMaxAvgLossPct)     notes += "avg-loss>band;";
            if(algos[a].expectancyR <= 0.0)                     notes += "negative-expectancy;";
            if(algos[a].maxDd > InpExpectedDdPct / 100.0 * balance) notes += "drawdown>expected;";
            if(balance > 0.0 && algos[a].impliedAllocPct > InpMaxAllocPct) notes += "implied-alloc>max;";
            verdict = (StringLen(notes) == 0) ? "PASS" : ("FLAG:" + notes);
            if(StringLen(notes) == 0) ranked++; else flagged++;
         }
         JournalRow(algos[a], verdict);
      }

      EA_Log(EA_LOG_EVENTS, StringFormat(
             "algo ranking over %d days: %d algorithms (%d with statistics), %d pass, %d flagged, %d insufficient%s",
             InpLookbackDays, scored, ArraySize(algos), ranked, flagged, insufficient,
             finalPass ? " (final pass)" : ""), true);
   }

   //--- find (or add) the slot for a magic
   int SlotOf(SAlgoStats &algos[], const long magic)
   {
      for(int i = 0; i < ArraySize(algos); i++)
         if(algos[i].magic == magic) return i;
      int n = ArraySize(algos);
      ArrayResize(algos, n + 1);
      algos[n].Reset();
      algos[n].magic = magic;
      return n;
   }

   //--- the ranking journal: append-only CSV in MQL5/Files, one row per algorithm per scan
   void JournalRow(const SAlgoStats &st, const string verdict)
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
         FileWrite(fh, "scan_time", "window_days", "magic", "trades", "trades_per_month", "win_rate",
                   "profit_factor", "net", "max_dd", "return_dd", "avg_win_r", "expectancy_r",
                   "avg_loss_pct_balance", "implied_alloc_pct", "verdict");
      FileWrite(fh,
                TimeToString(TimeTradeServer(), TIME_DATE | TIME_MINUTES),
                IntegerToString(InpLookbackDays),
                IntegerToString((long)st.magic),
                IntegerToString(st.closes),
                DoubleToString(st.tradesPerMonth, 2),
                DoubleToString(st.winRate * 100.0, 1),
                DoubleToString(st.profitFactor, 3),
                DoubleToString(st.net, 2),
                DoubleToString(st.maxDd, 2),
                DoubleToString(st.returnDD, 2),
                DoubleToString(st.avgWinR, 2),
                DoubleToString(st.expectancyR, 3),
                DoubleToString(st.avgLossPctOfBal, 3),
                DoubleToString(st.impliedAllocPct, 1),
                verdict);
      FileClose(fh);
   }
};

CCfAlgoPortfolioMonitor g_cfAlgoPortfolioMonitor;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfAlgoPortfolioMonitor);
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
