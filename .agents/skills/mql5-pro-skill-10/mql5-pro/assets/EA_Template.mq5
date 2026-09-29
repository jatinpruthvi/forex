//+------------------------------------------------------------------+
//|                                                  EA_Template.mq5 |
//|  Production-grade EA skeleton: new-bar driven, risk-sized,       |
//|  netting/hedging aware, retcode-handled, tester-safe.            |
//|  قالب إكسبيرت جاهز: كل الأقسام مرتبة بنظام الطبقات              |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property version   "1.00"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| CONFIG — المدخلات والثوابت: لا تتغير بعد التحميل                |
//+------------------------------------------------------------------+
input group "=== Trade Settings ==="
input long              InpMagic        = 246810;   // Magic Number
input double            InpRiskPct      = 1.0;      // Risk Percent
input int               InpSlAtrMult    = 2;        // SL = ATR x
input int               InpTpAtrMult    = 3;        // TP = ATR x
input group "=== Filters ==="
input int               InpAtrPeriod    = 14;       // ATR Period
input int               InpMaxSpreadPts = 30;       // Max Spread (points)

#define RETRY_MAX        3                          // محاولات إعادة الإرسال
#define LOG_PREFIX       "EA_TPL: "                 // بادئة السجل

//+------------------------------------------------------------------+
//| STATE — كل المتغيرات القابلة للتغير في struct واحد              |
//+------------------------------------------------------------------+
struct SState
{
   datetime lastBar;       // آخر شمعة معالجة
   int      hATR;          // مؤشر ATR — handle يُنشأ مرة واحدة
};
SState g_st;

CTrade g_trade;

//+------------------------------------------------------------------+
//| EVENTS — معالجات الأحداث: استدعاء فقط، لا حسابات هنا            |
//+------------------------------------------------------------------+
int OnInit()
{
   g_st.lastBar = 0;
   g_st.hATR = iATR(_Symbol, PERIOD_CURRENT, InpAtrPeriod);
   if(g_st.hATR == INVALID_HANDLE)
   {
      Print(LOG_PREFIX, "ATR handle failed: ", GetLastError());
      return INIT_FAILED;
   }
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(10);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.LogLevel(LOG_LEVEL_ERRORS);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_st.hATR != INVALID_HANDLE) IndicatorRelease(g_st.hATR);
}

void OnTick()
{
   if(!IsNewBar()) return;            // إستراتيجية على إغلاق الشموع
   if(!SpreadOK()) return;            // فلتر السبريد
   App_ProcessSignal();
}

//+------------------------------------------------------------------+
//| CORE — منطق صافٍ: لا تداول ولا رسم مباشر                        |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime cur = iTime(_Symbol, _Period, 0);
   if(cur == 0 || cur == g_st.lastBar) return false;
   g_st.lastBar = cur;
   return true;
}

bool SpreadOK()
{
   return SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) <= InpMaxSpreadPts;
}

double GetATR()
{
   double v[1];
   if(CopyBuffer(g_st.hATR, 0, 1, 1, v) != 1) return 0;   // قيمة آخر شمعة مغلقة
   return v[0];
}

// الإشارة: عدّل هذه الدالة فقط لتغيير الإستراتيجية
// تعيد: +1 شراء، -1 بيع، 0 لا شيء
int GetSignal()
{
   double c1 = iClose(_Symbol, _Period, 1);
   double c2 = iClose(_Symbol, _Period, 2);
   if(c1 == 0 || c2 == 0) return 0;
   if(c1 > c2) return  1;
   if(c1 < c2) return -1;
   return 0;
}

void App_ProcessSignal()
{
   if(CountMyPositions() > 0) return;          // مركز واحد كحد أقصى في هذا القالب
   int sig = GetSignal();
   if(sig == 0) return;
   double atr = GetATR();
   if(atr <= 0) return;
   OpenTrade(sig > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
             atr * InpSlAtrMult, atr * InpTpAtrMult);
}

//+------------------------------------------------------------------+
//| TRADE — كل نداءات التداول هنا حصراً                              |
//+------------------------------------------------------------------+
int CountMyPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)  continue;
      count++;
   }
   return count;
}

double NormalizeVolume(double vol)
{
   double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) return 0;
   vol = MathFloor(vol / step) * step;
   return MathMin(MathMax(vol, minV), maxV);
}

double NormalizePrice(double price)
{
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0) tick = _Point;
   return MathRound(price / tick) * tick;
}

double MinStopDistance()
{
   long pts = MathMax(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
                      SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL));
   if(pts == 0) pts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * 3;
   return pts * _Point;
}

double LotsForRisk(double slDistance)
{
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0) tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0 || tickValue <= 0 || slDistance <= 0) return 0;
   double riskMoney  = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPct / 100.0;
   double lossPerLot = (slDistance / tickSize) * tickValue;
   return NormalizeVolume(riskMoney / lossPerLot);
}

bool OpenTrade(ENUM_ORDER_TYPE type, double slDist, double tpDist)
{
   bool   isBuy = (type == ORDER_TYPE_BUY);
   int    dir   = isBuy ? 1 : -1;
   double price = SymbolInfoDouble(_Symbol, isBuy ? SYMBOL_ASK : SYMBOL_BID);

   // ضمان الحد الأدنى لمسافة الوقف
   slDist = MathMax(slDist, MinStopDistance());
   double sl = NormalizePrice(price - dir * slDist);
   double tp = NormalizePrice(price + dir * tpDist);

   double lot = LotsForRisk(slDist);
   if(lot <= 0) { Print(LOG_PREFIX, "Lot calc failed or below minimum"); return false; }

   // فحص الهامش قبل الإرسال
   double need;
   if(!OrderCalcMargin(type, _Symbol, lot, price, need) ||
      need > AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.9)
   { Print(LOG_PREFIX, "Insufficient margin"); return false; }

   for(int attempt = 0; attempt < RETRY_MAX; attempt++)
   {
      bool ok = isBuy ? g_trade.Buy(lot, _Symbol, 0, sl, tp)
                      : g_trade.Sell(lot, _Symbol, 0, sl, tp);
      uint rc = g_trade.ResultRetcode();
      if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL)) return true;
      if(rc != TRADE_RETCODE_REQUOTE && rc != TRADE_RETCODE_PRICE_CHANGED &&
         rc != TRADE_RETCODE_PRICE_OFF) break;     // غير قابل لإعادة المحاولة
   }
   PrintFormat("%sOpen failed retcode=%u (%s)", LOG_PREFIX,
               g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   return false;
}

//+------------------------------------------------------------------+
//| OnTradeTransaction — رصد الإغلاقات (SL/TP) بشكل موثوق           |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_INOUT)
   {
      long reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
      double pl = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
      PrintFormat("%sClosed (%s) P/L=%.2f", LOG_PREFIX,
                  reason == DEAL_REASON_SL ? "SL" :
                  reason == DEAL_REASON_TP ? "TP" : "other", pl);
   }
}

//+------------------------------------------------------------------+
//| OnTester — معيار تحسين مخصص (اختياري)                            |
//+------------------------------------------------------------------+
double OnTester()
{
   double trades = TesterStatistics(STAT_TRADES);
   if(trades < 30) return 0;                       // ارفض العينات الصغيرة
   double pf = TesterStatistics(STAT_PROFIT_FACTOR);
   double dd = MathMax(TesterStatistics(STAT_BALANCE_DDREL_PERCENT), 1);
   return TesterStatistics(STAT_PROFIT) * pf / dd;
}
//+------------------------------------------------------------------+
