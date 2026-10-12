//+------------------------------------------------------------------+
//|                                              CloseAllCharts.mq5  |
//|                                     Closes all open chart tabs.  |
//+------------------------------------------------------------------+
#property script_show_inputs

void OnStart()
{
   long currChart = ChartID();
   long chart = ChartFirst();
   int count = 0;
   
   // Collect all chart IDs first to avoid breaking the iterator
   long charts[];
   while(chart != -1)
   {
      int size = ArraySize(charts);
      ArrayResize(charts, size + 1);
      charts[size] = chart;
      chart = ChartNext(chart);
   }
   
   // Close all except the one running the script (close that last)
   for(int i = 0; i < ArraySize(charts); i++)
   {
      if(charts[i] != currChart)
      {
         ChartClose(charts[i]);
         count++;
      }
   }
   
   Print("Closed ", count, " background charts.");
   
   // Finally, close the chart this script is attached to
   ChartClose(currChart);
}
