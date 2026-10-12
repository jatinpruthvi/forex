//+------------------------------------------------------------------+
//|                                              CloseAllCharts.mq5  |
//|                                  Copyright 2026, Master Strategy |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property script_show_inputs
#property description "Closes all open charts in MetaTrader 5."
#property description "Can close every chart or keep the current chart active."

//--- Inputs
input bool InpKeepCurrentChart = false; // Keep the current chart (where script is run)?
input bool InpConfirm          = true;  // Ask for confirmation before closing?

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
   long myChartId = ChartID();
   
   // 1. Collect all open chart IDs first
   long chartIds[];
   int total = 0;
   long id = ChartFirst();
   while(id >= 0)
   {
      ArrayResize(chartIds, total + 1);
      chartIds[total] = id;
      total++;
      id = ChartNext(id);
   }
   
   if(total == 0 || (total == 1 && InpKeepCurrentChart && chartIds[0] == myChartId))
   {
      Print("[CloseAllCharts] No other charts to close.");
      return;
   }
   
   // 2. Optional Confirmation
   if(InpConfirm)
   {
      int toCloseCount = InpKeepCurrentChart ? (total - 1) : total;
      string msg = StringFormat("Are you sure you want to close %d open chart(s)?", toCloseCount);
      if(MessageBox(msg, "Close All Charts Confirmation", MB_YESNO | MB_ICONQUESTION) != IDYES)
      {
         Print("[CloseAllCharts] Operation cancelled by user.");
         return;
      }
   }
   
   int closedCount = 0;
   bool closeMyChartLast = false;
   
   // 3. Close all charts (closing current chart last so script does not abort early)
   for(int i = 0; i < total; i++)
   {
      long cid = chartIds[i];
      if(cid == myChartId)
      {
         if(!InpKeepCurrentChart)
            closeMyChartLast = true;
         continue; // don't close current chart yet
      }
      
      string sym = ChartSymbol(cid);
      ENUM_TIMEFRAMES tf = ChartPeriod(cid);
      if(ChartClose(cid))
      {
         closedCount++;
         PrintFormat("[CloseAllCharts] Closed chart: %s (%s, ID: %I64d)", sym, EnumToString(tf), cid);
      }
      else
      {
         PrintFormat("[CloseAllCharts] Failed to close chart ID: %I64d (Error: %d)", cid, GetLastError());
      }
   }
   
   PrintFormat("[CloseAllCharts] Successfully closed %d chart(s).", closedCount);
   
   // 4. Close current chart last if requested
   if(closeMyChartLast)
   {
      PrintFormat("[CloseAllCharts] Closing current chart (ID: %I64d)...", myChartId);
      ChartClose(myChartId);
   }
}
//+------------------------------------------------------------------+
