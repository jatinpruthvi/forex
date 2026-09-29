//+------------------------------------------------------------------+
//|                                           Indicator_Template.mq5 |
//|  Production indicator skeleton: correct prev_calculated loop,    |
//|  arrow signals + colored line, capped chart drawings.            |
//|  قالب مؤشر جاهز: حلقة الحساب الصحيحة + إشارات + رسوم محدودة     |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   3

#property indicator_label1  "Trend"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrGray,clrLimeGreen,clrTomato
#property indicator_width1  2

#property indicator_label2  "Buy"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLimeGreen
#property indicator_width2  2

#property indicator_label3  "Sell"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrTomato
#property indicator_width3  2

//+------------------------------------------------------------------+
//| CONFIG                                                           |
//+------------------------------------------------------------------+
input int InpPeriod = 20;    // MA Period

#define ARROW_BUY    233     // رمز Wingdings: سهم لأعلى
#define ARROW_SELL   234     // سهم لأسفل
#define ARROW_GAP    0.3     // إزاحة السهم عن الشمعة (نسبة من ATR التقريبي)

//+------------------------------------------------------------------+
//| BUFFERS — STATE الخاص بالمؤشر                                    |
//+------------------------------------------------------------------+
double g_line[];      // قيمة الخط
double g_lineClr[];   // فهرس لون الخط: 0 محايد، 1 صاعد، 2 هابط
double g_buy[];       // أسهم الشراء
double g_sell[];      // أسهم البيع

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, g_line,    INDICATOR_DATA);
   SetIndexBuffer(1, g_lineClr, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, g_buy,     INDICATOR_DATA);
   SetIndexBuffer(3, g_sell,    INDICATOR_DATA);

   PlotIndexSetInteger(1, PLOT_ARROW, ARROW_BUY);
   PlotIndexSetInteger(2, PLOT_ARROW, ARROW_SELL);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, InpPeriod);

   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("TrendTpl(%d)", InpPeriod));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
//| OnCalculate — النمط القياسي: فهرسة غير series، حلقة تصاعدية     |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[],
                const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
{
   if(rates_total < InpPeriod + 2) return 0;       // بيانات غير كافية
   if(rates_total < prev_calculated) return 0;     // حارس حالة تبديل السيرفر

   int start;
   if(prev_calculated == 0)
   {
      ArrayInitialize(g_line,    EMPTY_VALUE);
      ArrayInitialize(g_lineClr, 0);
      ArrayInitialize(g_buy,     EMPTY_VALUE);
      ArrayInitialize(g_sell,    EMPTY_VALUE);
      start = InpPeriod;                           // فترة الإحماء
   }
   else
      start = prev_calculated - 1;                 // أعد حساب الشمعة المتكونة

   for(int i = start; i < rates_total && !IsStopped(); i++)
   {
      // SMA تراكمي بسيط كمثال — استبدل بمنطقك
      double sum = 0;
      for(int k = 0; k < InpPeriod; k++) sum += close[i - k];
      g_line[i] = sum / InpPeriod;

      // اللون حسب الميل
      g_lineClr[i] = (i > 0 && g_line[i] > g_line[i-1]) ? 1 :
                     (i > 0 && g_line[i] < g_line[i-1]) ? 2 : 0;

      // الإشارات على الشموع المغلقة فقط (i < rates_total-1) لمنع إعادة الرسم
      g_buy[i]  = EMPTY_VALUE;
      g_sell[i] = EMPTY_VALUE;
      if(i < rates_total - 1 && i > InpPeriod)
      {
         double gap = (high[i] - low[i]) * ARROW_GAP;
         bool crossUp = close[i]   > g_line[i]   && close[i-1] <= g_line[i-1];
         bool crossDn = close[i]   < g_line[i]   && close[i-1] >= g_line[i-1];
         if(crossUp) g_buy[i]  = low[i]  - gap;   // السهم تحت الشمعة
         if(crossDn) g_sell[i] = high[i] + gap;   // السهم فوق الشمعة
      }
   }
   return rates_total;    // إشارة الجاهزية — إلزامي
}
//+------------------------------------------------------------------+
