//+------------------------------------------------------------------+
//|                                           Panel_Template.mq5     |
//|  قالب لوحة تحكم كاملة — واجهة رسومية فقط بدون منطق تداول       |
//|  مستخرج 1:1 من H.TA Dashboard (H_TA_GUI.mqh)                    |
//|  يستخدم CAppDialog من Controls library بنفس البنية الأصلية      |
//+------------------------------------------------------------------+
#property copyright "Panel_Template"
#property version   "1.00"
#property description "H.TA Panel Template - UI only, no trading logic"

#include <Controls\Dialog.mqh>
#include <Controls\Button.mqh>
#include <Controls\Edit.mqh>
#include <Controls\ComboBox.mqh>
#include <Controls\Label.mqh>
#include <Controls\CheckBox.mqh>

//+------------------------------------------------------------------+
//| INPUT — نفس مدخلات H.TA الأصلية                                 |
//+------------------------------------------------------------------+
input group "═══════════ Default Settings ═══════════"
input double InpFixedVolume  = 0.01;    // Fixed Volume Default
input double InpMoneyRisk    = 100.0;   // Money Risk Default ($)
input double InpBalanceRisk  = 1.0;     // Balance Risk Default (%)
input double InpEquityRisk   = 1.0;     // Equity Risk Default (%)
input int    InpStopLoss     = 1000;    // Stop Loss Default (Points)
input int    InpTakeProfit   = 1000;    // Take Profit Default (Points)
input bool   InpShowPanel    = true;    // Show Control Panel

input group "═══════════ Auto Coordinator ═══════════"
input bool   Enable_Auto_Manager = false;  // Enable Auto Coordinator
input double Default_TP_Dollar   = 8.0;   // Default TP ($)
input double Initial_SL_Dollar   = 3.0;   // Initial SL ($)

//+------------------------------------------------------------------+
//| أبعاد اللوحة — نفس ثوابت H.TA                                   |
//+------------------------------------------------------------------+
const int PANEL_WIDTH    = 245;
const int PANEL_HEIGHT   = 520;
const int MARGIN         = 6;
const int LABEL_HEIGHT   = 16;
const int CONTROL_HEIGHT = 20;
const int SECTION_SPACING = 5;

#define COLOR_BUY   C'170,251,161'
#define COLOR_SELL  C'251,170,161'
#define COLOR_DR    C'250,206,0'

//+------------------------------------------------------------------+
//| متغيرات الواجهة — نفس إعلانات H_TA_GUI.mqh                     |
//+------------------------------------------------------------------+
CAppDialog TradingDashboard;

// قسم الحجم والوضعية
CLabel    lblLotMode, lblLotSize;
CComboBox cmbLotMode;
CEdit     edtLotSize;

// قسم المخاطر
CLabel    lblStopLoss, lblTakeProfit, lblOrdersLabel, lblTpIncrement;
CEdit     edtStopLoss, edtTakeProfit;
CButton   btnTp1, btnTp3, btnTp6;
CComboBox cmbTpIncrement, cmbTpMultiplier;

// قسم التداول
CButton   btnBuyNow, btnSellNow, btnDr, btnEntrySetup;
CEdit     edtEntryPrice;

// قسم التذاكر
CLabel    lblOrderTickets;
CButton   btnRefresh;
CComboBox cmbTicketSelect;

// قسم إدارة التداول
CLabel    lblTradeManagement, lblTriggerDist, lblTrailingDist;
CComboBox cmbTradeManagement;
CButton   btnBreakEven, btnCloseNow, btnBreakEvenNow;
CEdit     edtTriggerDist, edtTrailingDist;

// قسم الفلاتر
CLabel    lblCloseFilter;
CCheckBox chkBuy, chkSell, chkProfit, chkLoss;
CButton   btnClosePosition, btnDeleteOrder;

// قسم المنسق التلقائي
CLabel    lblAutoMgr, lblAutoTrail, lblAutoTP, lblAutoSL;
CCheckBox chkAutoEnable;
CComboBox cmbAutoTrail;
CEdit     edtAutoTP, edtAutoSL;

//+------------------------------------------------------------------+
//| هيكل بيانات ComponentInfo — نسخة H.TA الأصلية                  |
//+------------------------------------------------------------------+
struct ComponentInfo
{
   int    x, y, width, height;
   string text;
   color  bgColor;
};

//+------------------------------------------------------------------+
//| دوال المصانع الموحدة — طبق الأصل من H_TA_GUI.mqh               |
//+------------------------------------------------------------------+
void CreateLabel(CLabel &lbl, string name, ComponentInfo &info)
{
   lbl.Create(0, name, 0, info.x, info.y,
              info.x + info.width, info.y + info.height);
   lbl.Text(info.text);
   TradingDashboard.Add(lbl);
}

void CreateButton(CButton &btn, string name, ComponentInfo &info)
{
   btn.Create(0, name, 0, info.x, info.y,
              info.x + info.width, info.y + info.height);
   btn.Text(info.text);
   if(info.bgColor != clrNONE)
      btn.ColorBackground(info.bgColor);
   TradingDashboard.Add(btn);
}

void CreateEdit(CEdit &edt, string name, ComponentInfo &info)
{
   edt.Create(0, name, 0, info.x, info.y,
              info.x + info.width, info.y + info.height);
   edt.Text(info.text);
   TradingDashboard.Add(edt);
}

void CreateComboBox(CComboBox &cmb, string name, ComponentInfo &info,
                    string &items[], int selectedIndex = 0)
{
   cmb.Create(0, name, 0, info.x, info.y,
              info.x + info.width, info.y + info.height);
   for(int i = 0; i < ArraySize(items); i++)
      cmb.AddItem(items[i]);
   cmb.Select(selectedIndex);
   TradingDashboard.Add(cmb);
}

//+------------------------------------------------------------------+
//| SECTION 1 — Lot Size Mode + Lot Size                            |
//| [Label: "Lot Size Mode"] [Label: "Lot Size (Lots)"]            |
//| [ComboBox: Fixed/Money/Balance/Equity] [Edit: 0.01]            |
//+------------------------------------------------------------------+
void CreateLotSizeSection(int &yPos)
{
   ComponentInfo lbl0 = {MARGIN, yPos, 119, LABEL_HEIGHT, "Lot Size Mode", clrNONE};
   ComponentInfo lbl1 = {125,    yPos, 125, LABEL_HEIGHT, "Lot Size (Lots)", clrNONE};
   CreateLabel(lblLotMode, "lblLotMode", lbl0);
   CreateLabel(lblLotSize, "lblLotSize", lbl1);
   yPos += LABEL_HEIGHT + 2;

   string modeItems[4] = {"Fixed Lots","Money Risk","Balance Risk","Equity Risk"};
   ComponentInfo cmb = {MARGIN, yPos, 119, CONTROL_HEIGHT, "", clrNONE};
   CreateComboBox(cmbLotMode, "cmbLotMode", cmb, modeItems, 0);

   ComponentInfo edt = {125, yPos, 125, CONTROL_HEIGHT,
                        DoubleToString(InpFixedVolume, 2), clrNONE};
   CreateEdit(edtLotSize, "edtLotSize", edt);
   yPos += CONTROL_HEIGHT + SECTION_SPACING;
}

//+------------------------------------------------------------------+
//| SECTION 2 — Risk Parameters                                     |
//| Row A: [Label SL] [Label TP]                                    |
//| Row B: [Edit SL ] [Edit TP 80px][Btn 1][Btn 3][Btn 6]          |
//| Row C: [Label Orders] [Label Tp Increment]                      |
//| Row D: [ComboBox Orders] [ComboBox Multiplier]                  |
//+------------------------------------------------------------------+
void CreateRiskManagementSection(int &yPos)
{
   // عناوين SL / TP
   ComponentInfo lSL = {MARGIN, yPos, 119, LABEL_HEIGHT, "Stop Loss (Points)", clrNONE};
   ComponentInfo lTP = {125,    yPos, 80,  LABEL_HEIGHT, "Take Profit (Points)", clrNONE};
   CreateLabel(lblStopLoss,   "lblStopLoss",   lSL);
   CreateLabel(lblTakeProfit, "lblTakeProfit", lTP);
   yPos += LABEL_HEIGHT + 2;

   // حقول SL / TP + أزرار سريعة
   ComponentInfo eSL = {MARGIN, yPos, 119, CONTROL_HEIGHT,
                        IntegerToString(InpStopLoss), clrNONE};
   ComponentInfo eTP = {125,    yPos, 80,  CONTROL_HEIGHT,
                        IntegerToString(InpTakeProfit), clrNONE};
   CreateEdit(edtStopLoss,   "edtStopLoss",   eSL);
   CreateEdit(edtTakeProfit, "edtTakeProfit", eTP);

   // أزرار TP السريعة 1 | 3 | 6  (عرض 15px لكل منها)
   CButton*  tpBtns[3]  = {&btnTp1, &btnTp3, &btnTp6};
   string    tpNames[3] = {"btnTp1","btnTp3","btnTp6"};
   string    tpTexts[3] = {"1","3","6"};
   for(int i = 0; i < 3; i++)
   {
      ComponentInfo b = {205 + i*15, yPos, 15, CONTROL_HEIGHT, tpTexts[i], clrNONE};
      CreateButton(*tpBtns[i], tpNames[i], b);
   }
   yPos += CONTROL_HEIGHT + 5;

   // عناوين Orders / Tp Increment
   ComponentInfo lOrd = {MARGIN, yPos, 119, LABEL_HEIGHT, "Orders",       clrNONE};
   ComponentInfo lInc = {125,    yPos, 125, LABEL_HEIGHT, "Tp Increment", clrNONE};
   CreateLabel(lblOrdersLabel,  "lblOrdersLabel",  lOrd);
   CreateLabel(lblTpIncrement,  "lblTpIncrement",  lInc);
   yPos += LABEL_HEIGHT + 2;

   // قوائم Orders / Multiplier
   string ordItems[6] = {"1 Order","2 Orders","3 Orders","4 Orders","5 Orders","6 Orders"};
   string incItems[6] = {"None","1x","2x","3x","4x","5x"};
   ComponentInfo cOrd = {MARGIN, yPos, 119, CONTROL_HEIGHT, "", clrNONE};
   ComponentInfo cInc = {125,    yPos, 125, CONTROL_HEIGHT, "", clrNONE};
   CreateComboBox(cmbTpIncrement, "cmbTpIncrement", cOrd, ordItems, 0);
   CreateComboBox(cmbTpMultiplier,"cmbTpMultiplier",cInc, incItems, 0);
   yPos += CONTROL_HEIGHT + SECTION_SPACING;
}

//+------------------------------------------------------------------+
//| SECTION 3 — Trading Buttons + Entry Row                         |
//| Row A: [BUY NOW 118px green] [SELL NOW 124px red] height=30    |
//| Row B: [Draw 65px yellow] [Edit EntryPrice 95px] [EntrySetup]  |
//+------------------------------------------------------------------+
void CreateTradingSection(int &yPos)
{
   ComponentInfo bBuy  = {MARGIN, yPos, 118, 30, "BUY NOW",  COLOR_BUY};
   ComponentInfo bSell = {126,    yPos, 124, 30, "SELL NOW", COLOR_SELL};
   CreateButton(btnBuyNow,  "btnBuyNow",  bBuy);
   CreateButton(btnSellNow, "btnSellNow", bSell);
   yPos += 35;

   ComponentInfo bDr    = {MARGIN, yPos, 65,  CONTROL_HEIGHT, "Draw",        COLOR_DR};
   ComponentInfo ePrc   = {75,     yPos, 95,  CONTROL_HEIGHT, "Entry Price:...", clrNONE};
   ComponentInfo bSetup = {175,    yPos, 75,  CONTROL_HEIGHT, "Entry Setup", clrNONE};
   CreateButton(btnDr,          "btnDr",         bDr);
   CreateEdit  (edtEntryPrice,  "edtEntryPrice", ePrc);
   CreateButton(btnEntrySetup,  "btnEntrySetup", bSetup);
   yPos += CONTROL_HEIGHT + SECTION_SPACING;
}

//+------------------------------------------------------------------+
//| SECTION 4 — Order Tickets                                       |
//| [Label "Order Tickets"]                                         |
//| [Btn Ref 32px] [ComboBox ticket list full-width]               |
//+------------------------------------------------------------------+
void CreateTradeTicketsSection(int &yPos)
{
   ComponentInfo hdr = {MARGIN, yPos, 250, LABEL_HEIGHT, "Order Tickets", clrNONE};
   CreateLabel(lblOrderTickets, "lblOrderTickets", hdr);
   yPos += LABEL_HEIGHT + 2;

   ComponentInfo bRef = {MARGIN, yPos, 32,  CONTROL_HEIGHT, "Ref", clrNONE};
   CreateButton(btnRefresh, "btnRefresh", bRef);

   cmbTicketSelect.Create(0, "cmbTicketSelect", 0,
                          40, yPos, 250, yPos + CONTROL_HEIGHT);
   cmbTicketSelect.AddItem("Select a ticket...");
   cmbTicketSelect.Select(0);
   TradingDashboard.Add(cmbTicketSelect);
   yPos += CONTROL_HEIGHT + SECTION_SPACING;
}

//+------------------------------------------------------------------+
//| SECTION 5 — Close Management                                    |
//| [Label "Close Management"]                                      |
//| [ComboBox mode 125px] [Btn Br.ev/Trailing.SL 125px]           |
//| [Label Trigger Dist.] [Label Trailing Dist.]  ← hidden/shown   |
//| [Edit trigger]        [Edit trailing]         ← hidden/shown   |
//| [Btn Partial Close Now — full width]          ← hidden/shown   |
//| [Btn Break Even Now   — full width]           ← hidden/shown   |
//|                                                                  |
//| FIX vs original: btnCloseNow & btnBreakEvenNow get SEPARATE    |
//| yPos increments so they never overlap.                          |
//+------------------------------------------------------------------+
void CreateTradeManagementSection(int &yPos)
{
   ComponentInfo hdr = {MARGIN, yPos, 250, LABEL_HEIGHT, "Close Management", clrNONE};
   CreateLabel(lblTradeManagement, "lblTradeManagement", hdr);
   yPos += LABEL_HEIGHT + 2;

   string mgmtItems[4] = {"Disable","Partial Close","Break Even","Trailing Stop"};
   ComponentInfo cMgmt = {MARGIN, yPos, 125, CONTROL_HEIGHT, "", clrNONE};
   ComponentInfo bBE   = {125,    yPos, 125, CONTROL_HEIGHT, "Br.ev/Trailing.SL", clrNONE};
   CreateComboBox(cmbTradeManagement, "cmbTradeManagement", cMgmt, mgmtItems, 0);
   CreateButton  (btnBreakEven,       "btnBreakEven",       bBE);
   yPos += CONTROL_HEIGHT + 5;

   // عناوين المسافات
   ComponentInfo lTrig  = {MARGIN, yPos, 119, LABEL_HEIGHT, "Trigger Dist. (pts)", clrNONE};
   ComponentInfo lTrail = {125,    yPos, 125, LABEL_HEIGHT, "Trailing Dist.",       clrNONE};
   CreateLabel(lblTriggerDist,  "lblTriggerDist",  lTrig);
   CreateLabel(lblTrailingDist, "lblTrailingDist", lTrail);
   yPos += LABEL_HEIGHT + 2;

   // حقول المسافات
   ComponentInfo eTrig  = {MARGIN, yPos, 119, CONTROL_HEIGHT, "0", clrNONE};
   ComponentInfo eTrail = {125,    yPos, 125, CONTROL_HEIGHT, "0", clrNONE};
   CreateEdit(edtTriggerDist,  "edtTriggerDist",  eTrig);
   CreateEdit(edtTrailingDist, "edtTrailingDist", eTrail);
   yPos += CONTROL_HEIGHT + 5;

   // زر Partial Close Now — الصف الخاص به
   ComponentInfo bPCN = {MARGIN, yPos, 244, CONTROL_HEIGHT, "Partial Close Now", clrNONE};
   CreateButton(btnCloseNow, "btnCloseNow", bPCN);
   yPos += CONTROL_HEIGHT + 3;   // ← زيادة yPos قبل الزر الثاني (الإصلاح الرئيسي)

   // زر Break Even Now — الصف الخاص به
   ComponentInfo bBEN = {MARGIN, yPos, 244, CONTROL_HEIGHT, "Break Even Now", clrNONE};
   CreateButton(btnBreakEvenNow, "btnBreakEvenNow", bBEN);
   yPos += CONTROL_HEIGHT + SECTION_SPACING;

   // الحالة الافتراضية: إخفاء كل العناصر (وضع Disable)
   UpdateMgmtVisibility(0);
}

//+------------------------------------------------------------------+
//| SECTION 6 — Close/Delete Filter                                 |
//| Row A: [Chk Buy] [Chk Profit] [Btn Close Position]             |
//| Row B: [Chk Sell][Chk Loss  ] [Btn Delete Order  ]             |
//+------------------------------------------------------------------+
void CreateCloseFilterSection(int &yPos)
{
   ComponentInfo hdr = {MARGIN, yPos, 250, LABEL_HEIGHT, "Close/Delete Filter", clrNONE};
   CreateLabel(lblCloseFilter, "lblCloseFilter", hdr);
   yPos += LABEL_HEIGHT + 2;

   // صف 1
   chkBuy.Create(0, "chkBuy", 0, MARGIN, yPos, MARGIN + 54, yPos + CONTROL_HEIGHT);
   chkBuy.Text("Buy"); chkBuy.Checked(true);
   TradingDashboard.Add(chkBuy);

   chkProfit.Create(0, "chkProfit", 0, 66, yPos, 130, yPos + CONTROL_HEIGHT);
   chkProfit.Text("Profit"); chkProfit.Checked(true);
   TradingDashboard.Add(chkProfit);

   ComponentInfo bClose = {134, yPos, 116, CONTROL_HEIGHT, "Close Position", clrNONE};
   CreateButton(btnClosePosition, "btnClosePosition", bClose);
   yPos += CONTROL_HEIGHT + 3;

   // صف 2
   chkSell.Create(0, "chkSell", 0, MARGIN, yPos, MARGIN + 54, yPos + CONTROL_HEIGHT);
   chkSell.Text("Sell"); chkSell.Checked(true);
   TradingDashboard.Add(chkSell);

   chkLoss.Create(0, "chkLoss", 0, 66, yPos, 130, yPos + CONTROL_HEIGHT);
   chkLoss.Text("Loss"); chkLoss.Checked(true);
   TradingDashboard.Add(chkLoss);

   ComponentInfo bDel = {134, yPos, 116, CONTROL_HEIGHT, "Delete Order", clrNONE};
   CreateButton(btnDeleteOrder, "btnDeleteOrder", bDel);
   yPos += CONTROL_HEIGHT + SECTION_SPACING;
}

//+------------------------------------------------------------------+
//| SECTION 7 — Auto Coordinator                                    |
//| [Label "Auto Coordinator"]                                      |
//| [CheckBox "Enable Auto Coordinator" full-width]                 |
//| [Label "Trail Mode" 70px] [ComboBox modes 170px]               |
//| [Label "TP $"][Edit autoTP][Label "SL $"][Edit autoSL]         |
//+------------------------------------------------------------------+
void CreateAutoManagerSection(int &yPos)
{
   ComponentInfo hdr = {MARGIN, yPos, 250, LABEL_HEIGHT, "Auto Coordinator", clrNONE};
   CreateLabel(lblAutoMgr, "lblAutoMgr", hdr);
   yPos += LABEL_HEIGHT + 2;

   chkAutoEnable.Create(0, "chkAutoEnable", 0,
                        MARGIN, yPos, 250, yPos + CONTROL_HEIGHT);
   chkAutoEnable.Text("Enable Auto Coordinator");
   chkAutoEnable.Checked(Enable_Auto_Manager);
   TradingDashboard.Add(chkAutoEnable);
   yPos += CONTROL_HEIGHT + 3;

   ComponentInfo lTrail = {MARGIN, yPos, 70, LABEL_HEIGHT, "Trail Mode", clrNONE};
   CreateLabel(lblAutoTrail, "lblAutoTrail", lTrail);
   string trailItems[5] = {"Fixed","ATR","Percentage","Stepped","Adaptive"};
   ComponentInfo cTrail = {80, yPos, 170, CONTROL_HEIGHT, "", clrNONE};
   CreateComboBox(cmbAutoTrail, "cmbAutoTrail", cTrail, trailItems, 0);
   yPos += CONTROL_HEIGHT + 3;

   ComponentInfo lTP = {MARGIN, yPos, 35, LABEL_HEIGHT, "TP $", clrNONE};
   ComponentInfo eTP = {45,     yPos, 75, CONTROL_HEIGHT,
                        DoubleToString(Default_TP_Dollar, 2), clrNONE};
   ComponentInfo lSL = {130,    yPos, 35, LABEL_HEIGHT, "SL $", clrNONE};
   ComponentInfo eSL = {170,    yPos, 80, CONTROL_HEIGHT,
                        DoubleToString(Initial_SL_Dollar, 2), clrNONE};
   CreateLabel(lblAutoTP, "lblAutoTP", lTP);
   CreateEdit  (edtAutoTP, "edtAutoTP", eTP);
   CreateLabel(lblAutoSL, "lblAutoSL", lSL);
   CreateEdit  (edtAutoSL, "edtAutoSL", eSL);
   yPos += CONTROL_HEIGHT + SECTION_SPACING;
}

//+------------------------------------------------------------------+
//| إظهار / إخفاء عناصر قسم إدارة التداول حسب النمط المحدد        |
//| mode: 0=Disable  1=Partial Close  2=Break Even  3=Trailing Stop |
//+------------------------------------------------------------------+
void UpdateMgmtVisibility(int mode)
{
   bool any     = (mode != 0);
   bool partial = (mode == 1);
   bool be      = (mode == 2);

   lblTriggerDist .Visible(any);
   edtTriggerDist .Visible(any);
   lblTrailingDist.Visible(any);
   edtTrailingDist.Visible(any);
   btnBreakEven   .Visible(any);
   btnCloseNow    .Visible(partial);   // "Partial Close Now"
   btnBreakEvenNow.Visible(be);        // "Break Even Now"

   switch(mode)
   {
      case 1:
         lblTrailingDist.Text("Close Lots");
         btnBreakEven.Text("Partial Close");
         break;
      case 2:
         lblTrailingDist.Text("Offsets Dist.");
         btnBreakEven.Text("Break Even");
         break;
      case 3:
         lblTrailingDist.Text("Trailing Dist.");
         btnBreakEven.Text("Trailing SL");
         break;
      default:
         btnBreakEven.Text("Br.ev/Trailing.SL");
         break;
   }
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| GUI_Initialize — يبني اللوحة كاملة                              |
//+------------------------------------------------------------------+
bool GUI_Initialize()
{
   if(!TradingDashboard.Create(0, "H.TA 0.01", 0,
                               20, 20,
                               PANEL_WIDTH + 40,
                               PANEL_HEIGHT + 60))
      return false;

   int yPos = 5;
   CreateLotSizeSection       (yPos);   // 1
   CreateRiskManagementSection(yPos);   // 2
   CreateTradingSection       (yPos);   // 3
   CreateTradeTicketsSection  (yPos);   // 4
   CreateTradeManagementSection(yPos);  // 5
   CreateCloseFilterSection   (yPos);   // 6
   CreateAutoManagerSection   (yPos);   // 7

   TradingDashboard.Run();

   if(!InpShowPanel)
      TradingDashboard.Hide();

   ChartRedraw();
   return true;
}

//+------------------------------------------------------------------+
//| GUI_Deinitialize                                                 |
//+------------------------------------------------------------------+
void GUI_Deinitialize(const int reason)
{
   TradingDashboard.Destroy(reason);
}

//+------------------------------------------------------------------+
//| GUI_ChartEvent — يوجّه أحداث الواجهة فقط (بدون منطق تداول)    |
//+------------------------------------------------------------------+
void GUI_ChartEvent(const int id, const long &lparam,
                    const double &dparam, const string &sparam)
{
   TradingDashboard.ChartEvent(id, lparam, dparam, sparam);

   // تغيير نمط إدارة التداول → تحديث الرؤية
   if(sparam == "cmbTradeManagement")
      UpdateMgmtVisibility((int)cmbTradeManagement.Value());

   // تغيير وضع اللوت → تحديث التسمية
   else if(sparam == "cmbLotMode")
   {
      string unitTexts[4] = {"Lots","$","% Bal","% Eq"};
      int m = (int)cmbLotMode.Value();
      lblLotSize.Text("Lot Size (" + unitTexts[m] + ")");
      ChartRedraw();
   }
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!GUI_Initialize())
      return INIT_FAILED;
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   GUI_Deinitialize(reason);
}

//+------------------------------------------------------------------+
//| OnChartEvent                                                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam)
{
   GUI_ChartEvent(id, lparam, dparam, sparam);
}

//+------------------------------------------------------------------+
//| OnTick — فارغ (قالب واجهة فقط)                                 |
//+------------------------------------------------------------------+
void OnTick() {}
//+------------------------------------------------------------------+
