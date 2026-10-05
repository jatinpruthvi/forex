//+------------------------------------------------------------------+
//|                                            UniversePreflight.mq5 |
//|                                              Master Strategy      |
//|                                                                  |
//| Run this ONCE per broker, before the 65-EA Strategy Tester sweep. |
//| It resolves every symbol the 65 implemented EAs need and reports  |
//| which ones exist, their spread, contract size and volume limits.   |
//|                                                                  |
//| Why: the EAs' `InpSymbolsToTrade` lists are the documents' lists.  |
//| `EA_ParseSymbols()` skips and logs a symbol the broker does not    |
//| offer, so an unavailable symbol is NOT an error - but it silently  |
//| kills a sleeve, and index aliases differ per broker (GER40 vs      |
//| DE40 vs DAX vs GERMANY40).                                         |
//|                                                                  |
//| Drag onto any chart.  Results:                                     |
//|   Common\Files\EA_TestReports\universe_preflight.csv               |
//|   (and the Experts/Journal tab)                                    |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property version   "1.00"
#property script_show_inputs

//--- union of every universe in the 65 implemented EAs.  KEEP THIS LIST AS THE
//--- FALLBACK ONLY (#19): the harness writes symbols.txt next to the launch plan
//--- (validation/mt5_harness/gen_launcher.py runs it out of the same generator
//--- the configs come from), and the script prefers that file when it is present.
input string InpSymbols = "EURUSD;GBPUSD;USDJPY;XAUUSD;AUDUSD;USDCAD;USDCHF;EURGBP;AUDNZD;EURCHF;EURJPY;GBPJPY;AUDJPY;GER40;DE40;GER30;DAX;US30;US100;NAS100";

//--- folder under MQL5\Files holding the harness output (launch_plan.csv, symbols.txt)
input string InpLaunchFolder = "EA_Launch";

//--- index aliases to probe even when the list above does not contain them
input string InpIndexAliases = "GER40;DE40;GER30;DAX;GERMANY40;US30;DJ30;DOW30;US100;NAS100;USTEC;US500;SPX500";

void WriteRow(const int h, const string sym, const string state,
              const double spread, const double contract,
              const double volMin, const double volStep)
{
   if(h == INVALID_HANDLE) return;          // CSV is best-effort; the Journal always prints
   FileWriteString(h, StringFormat("%s,%s,%.1f,%.2f,%.2f,%.2f,%s\r\n",
                  sym, state, spread, contract, volMin, volStep,
                  TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES)));
}

void Probe(const int h, const string sym, const bool quiet)
{
   if(StringLen(sym) == 0) return;
   if(!SymbolSelect(sym, true))
   {
      if(!quiet) PrintFormat("MISSING  %-12s  not offered by this broker", sym);
      WriteRow(h, sym, "MISSING", 0, 0, 0, 0);
      return;
   }
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   if(bid <= 0.0 && ask <= 0.0)
   {
      if(!quiet) PrintFormat("NOQUOTES %-12s  listed but no quotes right now", sym);
      WriteRow(h, sym, "NOQUOTES", 0, 0, 0, 0);
      return;
   }
   double point    = SymbolInfoDouble(sym, SYMBOL_POINT);
   double spread   = (point > 0.0) ? (ask - bid) / point : 0.0;
   double contract = SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE);
   double volMin   = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double volStep  = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(!quiet)
      PrintFormat("OK       %-12s  spread %5.1f pts | contract %10.2f | lot %.2f/%.2f",
                  sym, spread, contract, volMin, volStep);
   WriteRow(h, sym, "OK", spread, contract, volMin, volStep);
}

void OnStart()
{
   Print("=== Universe preflight (65 implemented EAs) ===");
   PrintFormat("broker: %s | account: %I64d | leverage: 1:%d",
               AccountInfoString(ACCOUNT_COMPANY), AccountInfoInteger(ACCOUNT_LOGIN),
               (int)AccountInfoInteger(ACCOUNT_LEVERAGE));

   FolderCreate("EA_TestReports", FILE_COMMON);          // false if it exists
   int h = FileOpen("EA_TestReports/universe_preflight.csv",
                    FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE)
   {
      Print("could not open Common\\Files\\EA_TestReports\\universe_preflight.csv - " +
            "results are printed to the Journal only");
   }
   else
      FileWriteString(h, "symbol,state,spread_points,contract_size,volume_min,volume_step,checked\r\n");

   //--- 0. symbol list: the generated symbols.txt wins when it is present (#19)
   string list = InpSymbols;
   string listFile = InpLaunchFolder + "\\symbols.txt";
   int lf = FileOpen(listFile, FILE_READ | FILE_TXT | FILE_ANSI);
   if(lf != INVALID_HANDLE)
   {
      string loaded = "";
      while(!FileIsEnding(lf))
      {
         string line = FileReadString(lf);
         StringTrimLeft(line);
         StringTrimRight(line);
         if(StringLen(line) == 0) continue;
         if(StringLen(loaded) > 0) loaded += ";";
         loaded += line;
      }
      FileClose(lf);
      if(StringLen(loaded) > 0)
      {
         list = loaded;
         int listed = 1;
         for(int c = 0; c < StringLen(list); c++)
            if(StringGetCharacter(list, c) == ';') listed++;
         PrintFormat("symbol list: MQL5\\Files\\%s (%d entries, generated)", listFile, listed);
      }
   }
   else
      Print("symbol list: BUILTIN snapshot - copy the harness output folder into MQL5\\Files\\",
            InpLaunchFolder, "\\ (or re-run gen_launcher.py) so symbols.txt keeps this list fresh.");

   //--- 1. the union of the EAs' universes
   string parts[];
   int n = StringSplit(list, ';', parts);
   int ok = 0, missing = 0;
   for(int i = 0; i < n; i++)
   {
      string s = parts[i];
      StringTrimLeft(s);
      StringTrimRight(s);
      if(StringLen(s) == 0) continue;
      if(SymbolSelect(s, true)) ok++; else missing++;
      Probe(h, s, false);
   }

   //--- 2. index aliases: report which spelling this broker uses
   Print("--- index aliases offered by this broker ---");
   string idx[];
   int m = StringSplit(InpIndexAliases, ';', idx);
   for(int i = 0; i < m; i++)
   {
      string s = idx[i];
      StringTrimLeft(s);
      StringTrimRight(s);
      if(StringLen(s) == 0) continue;
      if(SymbolSelect(s, true)) Probe(h, s, false);
   }

   if(h != INVALID_HANDLE) FileClose(h);
   PrintFormat("=== preflight done: %d symbols resolvable, %d missing ===", ok, missing);
   Print("CSV: Common\\Files\\EA_TestReports\\universe_preflight.csv");
   Print("Symbols flagged MISSING are skipped by the engine at startup and their sleeve is inert.");
}
//+------------------------------------------------------------------+
