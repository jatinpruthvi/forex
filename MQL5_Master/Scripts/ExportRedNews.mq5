//+------------------------------------------------------------------+
//|                                                  ExportRedNews.mq5|
//|                                  Copyright 2026, Master Strategy  |
//|                                                                   |
//| Writes MQL5\Files\the5ers_red_news.csv from the terminal's OWN     |
//| economic calendar, in the exact format the engine's news gate      |
//| reads:                                                             |
//|                                                                    |
//|     date,time,currency,impact     e.g.  2026.10.02,13:30,USD,HIGH  |
//|                                                                    |
//| Why this exists: six delivered engines (magics 3102, 3104, 3105,   |
//| 3106, 3107, 3109 - the The5ers red-folder family) ship the news    |
//| gate with newsFailClosed, and a missing calendar stops ALL their   |
//| new entries by design ("bad calendar = no new entries").  Running  |
//| this script once fills the gap from data the terminal already has, |
//| instead of hand-typing a calendar.                                 |
//|                                                                    |
//| Contract with the engine (MQL5_Master\Include\EACore.mqh,          |
//| EA_LoadNewsCache / EA_NewsBlocked):                                |
//|   * one event per row, four comma-separated fields;                |
//|   * 'date' is YYYY.MM.DD and 'time' is HH:MM - the engine feeds    |
//|     the two fields to StringToTime() as one timestamp;             |
//|   * times are SERVER time - that is the MT5 calendar's own         |
//|     convention (its API returns trade-server time).  The file      |
//|     therefore starts with the marker row                          |
//|         #timezone=server,,,                                        |
//|     so the engine compares in the same frame.  A CSV *without*     |
//|     that marker keeps the delivered meaning: UTC;                  |
//|   * 'impact' must read HIGH (or a number >= 2);                    |
//|   * 'currency' is matched against the EA's symbol list, so USD     |
//|     events block EURUSD/USDJPY/... engines; ALL blocks any symbol; |
//|   * a header row is harmless: the engine cannot parse it into a    |
//|     timestamp and skips it.                                        |
//|                                                                    |
//| Window: InpDaysBack/InpDaysForward around "now" by default, or an   |
//| explicit InpFromDate/InpToDate (YYYY.MM.DD) - use the same dates as |
//| your tester configs so a sweep sees the same calendar the file has. |
//|                                                                    |
//| Install: copy to <data>\MQL5\Scripts\ExportRedNews.mq5, compile in  |
//| MetaEditor, then drag it onto any chart.  It only READS the         |
//| calendar and writes one file - it never trades.                    |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property version   "1.00"
#property description "Exports high-impact calendar events to MQL5\\Files\\the5ers_red_news.csv"
#property script_show_inputs

input int    InpDaysBack    = 2;                       // days of past events to include (used when InpFromDate is empty)
input int    InpDaysForward = 45;                      // days of future events to include (used when InpToDate is empty)
input string InpFromDate    = "";                      // explicit window start YYYY.MM.DD (e.g. your tester FromDate)
input string InpToDate      = "";                      // explicit window end   YYYY.MM.DD (e.g. your tester ToDate)
input bool   InpHighOnly    = true;                    // HIGH importance only (what the engines gate on)
input string InpFile        = "the5ers_red_news.csv";  // written under MQL5\Files

//+------------------------------------------------------------------+
//| One row per blocking event, in calendar order                     |
//+------------------------------------------------------------------+
void OnStart()
{
   datetime now  = TimeTradeServer();
   //--- explicit window wins: a tester sweep runs a FIXED date range (the
   //--- generated configs default to 2025.01.01 .. 2026.09.30), and a calendar
   //--- exported "from now" would not cover it - the fail-closed engines would
   //--- then block on events the file cannot see (eleventh-pass follow-up)
   datetime from = now - (datetime)((long)MathMax(0, InpDaysBack) * 86400);
   datetime to   = now + (datetime)((long)MathMax(1, InpDaysForward) * 86400);
   string fromStr = StringTrimLeft(StringTrimRight(InpFromDate));
   string toStr   = StringTrimLeft(StringTrimRight(InpToDate));
   if(StringLen(fromStr) > 0)
   {
      datetime t = StringToTime(fromStr);
      if(t > 0) from = t;
      else PrintFormat("ExportRedNews: InpFromDate '%s' is not YYYY.MM.DD - using the relative window.",
                       InpFromDate);
   }
   if(StringLen(toStr) > 0)
   {
      datetime t = StringToTime(toStr);
      if(t > 0) to = t + 86400;          // the ToDate day itself is included
      else PrintFormat("ExportRedNews: InpToDate '%s' is not YYYY.MM.DD - using the relative window.",
                       InpToDate);
   }
   if(to <= from)
   {
      PrintFormat("ExportRedNews: empty window (%s .. %s) - check InpFromDate/InpToDate.",
                  TimeToString(from, TIME_DATE), TimeToString(to, TIME_DATE));
      return;
   }

   MqlCalendarValue values[];
   ResetLastError();
   int n = CalendarValueHistory(values, from, to, NULL, NULL);
   if(n <= 0)
   {
      PrintFormat("ExportRedNews: the economic calendar returned no values (count %d, err %d) for %s .. %s.",
                  n, GetLastError(),
                  TimeToString(from, TIME_DATE), TimeToString(to, TIME_DATE));
      PrintFormat("ExportRedNews: your broker may not carry the MT5 calendar.  Until %s exists, the "
                  "six fail-closed engines (3102/3104/3105/3106/3107/3109) take NO new entries - "
                  "supply the file by hand (format: date,time,currency,impact) or untick them.",
                  InpFile);
      return;
   }

   int h = FileOpen(InpFile, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
   {
      PrintFormat("ExportRedNews: cannot write MQL5\\Files\\%s (error %d).", InpFile, GetLastError());
      return;
   }

   //--- frame marker first: MT5 calendar times are SERVER time, and the engine
   //--- must compare them against the server clock, not the UTC-converted one.
   //--- The three empty fields keep the 4-field row structure the engine's
   //--- parser relies on; a row without a parseable timestamp is skipped.
   FileWriteString(h, "#timezone=server,,,\r\n");
   FileWriteString(h, "date,time,currency,impact\r\n");

   int written = 0, skipped = 0;
   for(int i = 0; i < n; i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev))
      {
         skipped++;
         continue;
      }
      if(InpHighOnly && ev.importance != CALENDAR_IMPORTANCE_HIGH)
         continue;

      //--- currency of the event's country ("USD", "EUR", ...; ALL if unknown)
      string cc = "ALL";
      MqlCalendarCountry country;
      if(CalendarCountryById((long)ev.country_id, country) && StringLen(country.currency) > 0)
         cc = country.currency;

      //--- "YYYY.MM.DD HH:MM" -> "YYYY.MM.DD,HH:MM"
      string stamp = TimeToString(values[i].time, TIME_DATE | TIME_MINUTES);
      StringReplace(stamp, " ", ",");

      FileWriteString(h, stamp + "," + cc + ",HIGH\r\n");
      written++;
   }
   FileClose(h);

   PrintFormat("ExportRedNews: %d blocking event(s) written to MQL5\\Files\\%s in SERVER time "
               "(window %s .. %s, %d value(s) read, %d event lookup(s) failed).%s",
               written, InpFile,
               TimeToString(from, TIME_DATE), TimeToString(to, TIME_DATE),
               n, skipped,
               InpHighOnly ? "" : "  NOTE: high-only filter is OFF - every importance level was written.");
   if(written == 0)
      PrintFormat("ExportRedNews: no events in the window - widen InpDaysForward, or the calendar has "
                  "nothing to offer for %s .. %s yet.", TimeToString(from, TIME_DATE), TimeToString(to, TIME_DATE));
}
//+------------------------------------------------------------------+
