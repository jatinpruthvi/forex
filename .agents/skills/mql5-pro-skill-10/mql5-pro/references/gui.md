# MQL5 GUI — Chart Objects, Controls Library, Canvas

## Contents
1. Choosing the right GUI approach
2. THEME + METRICS libraries — mandatory foundation of every GUI
3. Coordinate systems — the root cause of broken drawings
4. Native chart objects — factory pattern (screen-anchored UI)
5. Price/time-anchored drawing — lines, rectangles, zones, circles, text on candles
6. OnChartEvent — full event handling
7. Standard Library panels (CAppDialog + Controls)
7b. Controls library — complete control reference (each control's read/write API + events)
8. Customizing Controls appearance (Defines.mqh trick)
9. Panel persistence across timeframe changes
10. CCanvas custom rendering
11. Layout engine — grid/row helpers to kill coordinate arithmetic
12. GUI layering standard (UI/EVENTS separation)
13. UI text language policy

## 1. Choosing the right GUI approach

| Approach | Use for | Cost |
|---|---|---|
| Native objects (OBJ_BUTTON, OBJ_LABEL, OBJ_RECTANGLE_LABEL, OBJ_EDIT) | Simple HUDs, a few buttons, info rows, trade lines, drawings on candles | Lowest; fast |
| Controls library (CAppDialog) | Forms: combo boxes, lists, check groups, spin edits, draggable dialog | Medium; classic look, solid event plumbing |
| CCanvas | Custom-drawn dashboards, charts-in-chart, gradients, transparency, pixel control | Highest; full freedom, you own hit-testing |

Hybrid is normal: CAppDialog frame + CCanvas content cell, or native objects only.

## 2. THEME + METRICS libraries — mandatory foundation of every GUI

Every GUI program starts with two constant blocks: a color library and a dimensions library. This is the MQL5 equivalent of CSS `:root` variables. **No raw color literal and no raw pixel number may appear anywhere outside these blocks.** This single rule eliminates the chaos of scattered `clrRed`/`15`/`C'30,30,30'` and makes restyling a one-block edit.

```mql5
//+------------------------------------------------------------------+
//| THEME — مكتبة الألوان: كل لون في البرنامج يُعرّف هنا فقط          |
//+------------------------------------------------------------------+
#define THEME_BG            C'22,26,34'      // خلفية اللوحة
#define THEME_BG_HEADER     C'30,36,48'      // شريط العنوان
#define THEME_ACCENT        C'0,120,215'     // اللون الرئيسي
#define THEME_TEXT          clrWhiteSmoke    // النص الأساسي
#define THEME_TEXT_DIM      C'140,148,160'   // نص ثانوي
#define THEME_BUY           C'38,166,91'     // أخضر الشراء
#define THEME_SELL          C'214,69,65'     // أحمر البيع
#define THEME_WARN          C'243,156,18'    // تحذير
#define THEME_BORDER        C'58,64,78'      // حدود
#define THEME_ZONE_BULL     C'18,60,40'      // منطقة صاعدة (مستطيلات الشارت)
#define THEME_ZONE_BEAR     C'70,28,28'      // منطقة هابطة

//+------------------------------------------------------------------+
//| METRICS — مكتبة الأبعاد: كل قياس بكسل يُعرّف هنا فقط             |
//+------------------------------------------------------------------+
#define UI_PREFIX           "APP_"           // بادئة كل الكائنات
#define UI_PAD              8                // الهامش الموحد
#define UI_ROW_H            26               // ارتفاع الصف
#define UI_BTN_W            96               // عرض الزر القياسي
#define UI_FONT             "Segoe UI"       // الخط الموحد
#define UI_FONT_SIZE        10               // حجم الخط الأساسي
#define UI_FONT_SIZE_TITLE  12               // حجم خط العناوين
#define UI_PANEL_W          300              // عرض اللوحة
#define UI_CORNER           CORNER_LEFT_UPPER // زاوية تثبيت اللوحة
```
- For class-based projects, the same as static members of a `CTheme` class or a `STheme` struct instance in CONFIG — the rule is identical: one source of truth.
- DPI scaling applies to METRICS once, at startup:
```mql5
int Dpi(const int base)   // كل قياس يمر عبر هذه الدالة عند الإنشاء
{
   static int dpi = (int)TerminalInfoInteger(TERMINAL_SCREEN_DPI);
   return base * dpi / 96;
}
```

## 3. Coordinate systems — the root cause of broken drawings

MQL5 has TWO unrelated coordinate systems. 90% of "the drawing is in the wrong place / invisible / detached from candles" bugs come from using the wrong one or mixing them.

**A) Pixel coordinates (screen-anchored)** — for panels, buttons, labels, HUDs:
- Used by: OBJ_LABEL, OBJ_BUTTON, OBJ_EDIT, OBJ_RECTANGLE_LABEL, OBJ_BITMAP_LABEL (and CCanvas bitmap labels).
- Position = `OBJPROP_CORNER` (which chart corner is origin) + `OBJPROP_XDISTANCE`/`OBJPROP_YDISTANCE` (pixels from that corner, always positive, growing INTO the chart).
- `OBJPROP_ANCHOR` selects which point OF THE OBJECT sits at (X,Y). For right-corner layouts use right anchors, else text grows off-screen.
- These objects NEVER move with price/scroll. Created with zeroed time/price: `ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)`.

**B) Time/price coordinates (chart-anchored)** — for drawings on candles:
- Used by: OBJ_TREND, OBJ_HLINE, OBJ_VLINE, OBJ_RECTANGLE, OBJ_ELLIPSE, OBJ_TRIANGLE, OBJ_ARROW*, OBJ_TEXT, OBJ_FIBO*, OBJ_CHANNEL.
- Position = (datetime, double price) per anchor point: `ObjectCreate(0, name, OBJ_RECTANGLE, 0, time1, price1, time2, price2)`.
- These move with the chart, scale with zoom, and stay glued to candles. This is what "draw a rectangle on the order block" means.

**Conversions** when one system must meet the other (e.g., a tooltip near a candle):
```mql5
int x, y;
ChartTimePriceToXY(0, 0, barTime, price, x, y);     // سعر/زمن → بكسل
datetime t; double p; int subwin;
ChartXYToTimePrice(0, x, y, subwin, t, p);          // بكسل → سعر/زمن (نقرات الماوس)
```

**Decision rule**: element belongs to the MARKET (level, zone, signal arrow, swing label) → time/price objects (§5). Element belongs to the APP (button, status row, dashboard) → pixel objects (§4) or canvas (§10).

**Subwindow rule**: indicators in a separate window pass their own subwindow index (find it with `ChartWindowFind()`), never hardcode 0; for EAs drawing on the main chart, subwindow = 0.

**Pixel/price desync in a linked overlay (custom drag, snapping, or a HUD glued to a level).** Price-anchored objects (OBJ_HLINE via `OBJPROP_PRICE`) re-track the chart automatically every render — pane scroll, zoom, and any external price change move them for free. Pixel-anchored objects (a box/label/edit positioned with `XDISTANCE/YDISTANCE`) move ONLY when you explicitly re-position them. So a system where a pixel box must sit on a price line (info box beside an SL line, an edit field on a level) goes out of sync the moment the price moves by any path you did not personally trigger — chart scroll, zoom, OR an external write to the order (e.g. a protection/trailing engine resetting SL). The line jumps, the box stays, until something forces a redraw. Fixes:
- Re-run the reposition routine (price→`ChartTimePriceToXY`→set XDISTANCE/YDISTANCE for every pixel widget) on **`CHARTEVENT_CHART_CHANGE`** (scroll/zoom/resize) AND once per tick in `OnTick` while the overlay is visible. Both, not either — CHART_CHANGE misses tick-driven external writes, OnTick misses scroll between ticks.
- If the overlay live-tracks a selected order, use a **dirty flag**: while the user is actively dragging/editing, set `dirty=true` so the per-tick reload does not fight the drag; on commit/release, set `dirty=false` to resume reloading the broker truth — then the line AND its box follow any engine-side change together, in the same reposition pass.

## 4. Native chart objects — factory pattern (screen-anchored UI)

One generic factory per object kind, parameterized, theme-driven. Never repeat ObjectCreate blocks.

```mql5
// مصنع التهيئة المشتركة — يستدعى من كل المصانع الأخرى (DRY)
bool UiCreate(const string id, ENUM_OBJECT type, string &outName)
{
   outName = UI_PREFIX + id;
   if(ObjectFind(0, outName) >= 0) return true;          // موجود — لا تكرار
   if(!ObjectCreate(0, outName, type, 0, 0, 0)) return false;
   ObjectSetInteger(0, outName, OBJPROP_CORNER,     UI_CORNER);
   ObjectSetInteger(0, outName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, outName, OBJPROP_HIDDEN,     true);   // إخفاء من قائمة الكائنات
   ObjectSetInteger(0, outName, OBJPROP_BACK,       false);
   return true;
}

bool UiLabel(const string id, int x, int y, const string text,
             color clr = THEME_TEXT, int fs = UI_FONT_SIZE,
             ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER)
{
   string n; if(!UiCreate(id, OBJ_LABEL, n)) return false;
   ObjectSetInteger(0, n, OBJPROP_ANCHOR,    anchor);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,  fs);
   ObjectSetString (0, n, OBJPROP_FONT,      UI_FONT);
   ObjectSetString (0, n, OBJPROP_TEXT,      text);
   return true;
}

bool UiButton(const string id, int x, int y, int w, int h, const string text,
              color bg = THEME_ACCENT, color fg = THEME_TEXT)
{
   string n; if(!UiCreate(id, OBJ_BUTTON, n)) return false;
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,     w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE,     h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,   bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR,     fg);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, THEME_BORDER);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,  UI_FONT_SIZE);
   ObjectSetString (0, n, OBJPROP_FONT,      UI_FONT);
   ObjectSetString (0, n, OBJPROP_TEXT,      text);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,    10);            // فوق الخلفية
   return true;
}

bool UiPanel(const string id, int x, int y, int w, int h, color bg = THEME_BG)
{
   string n; if(!UiCreate(id, OBJ_RECTANGLE_LABEL, n)) return false;
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,   x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,   y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,       w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE,       h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,     bg);
   ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, n, OBJPROP_COLOR,       THEME_BORDER);
   ObjectSetInteger(0, n, OBJPROP_ZORDER,      0);            // الخلفية أسفل دائماً
   return true;
}

// مساعدات التحديث — التحديث لا يعيد الإنشاء أبداً
void UiSetText(const string id, const string text, color clr = clrNONE)
{
   string n = UI_PREFIX + id;
   ObjectSetString(0, n, OBJPROP_TEXT, text);
   if(clr != clrNONE) ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, UI_PREFIX);   // التنظيف الكامل — إلزامي
   ChartRedraw();
}
```
Rules:
- `ChartRedraw()` after every BATCH of changes, not after every Set — once per refresh cycle.
- Buttons: read `OBJPROP_STATE`; after handling, RESET it (`ObjectSetInteger(0, n, OBJPROP_STATE, false)`) and ChartRedraw, or it sticks pressed.
- Z-order: background panel lowest (0), interactive elements higher; equal zorder → creation order decides hit priority unpredictably, so always set it explicitly. **Caveat (rendering, not hit-testing):** `OBJPROP_ZORDER` governs mouse-hit priority, and across most object pairs it also reflects draw order — but an `OBJ_LABEL` does NOT reliably paint above an `OBJ_RECTANGLE_LABEL` no matter how much higher its ZORDER, so a text label placed on a filled rectangle can be swallowed by it. When you need text/info to render ON TOP of a filled rectangle (an info chip on a colored box), use an **`OBJ_BUTTON`** for the top element instead of OBJ_LABEL — a button (with its border/3D disabled if you want a flat look) always paints above rectangle labels. This is purely about visible layering; for clickable widgets the button is wanted anyway.
- OBJ_EDIT: set `OBJPROP_ALIGN` (ALIGN_LEFT/CENTER/RIGHT); read text on CHARTEVENT_OBJECT_ENDEDIT via `ObjectGetString(0, n, OBJPROP_TEXT)`; cast numerics with `StringToDouble` + validate.
- Create once / update many: factories early-return if the object exists; per-tick code calls only `UiSetText`-style setters. Recreating objects per tick = flicker + CPU burn.
- **Instance-unique prefix**: the same program on multiple charts (or multiple EAs sharing a chart) collides on object names. Build the prefix at runtime from a constant + identity: `string UiPrefix() { static string p = "APP_" + (string)InpMagic + "_"; return p; }` (or `ChartID()` for per-chart uniqueness) and use it everywhere the examples show `UI_PREFIX` — including the `ObjectsDeleteAll` cleanup.
- **Responsive positioning**: read the live chart size instead of assuming it — `(int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS)` / `CHART_HEIGHT_IN_PIXELS` — and re-anchor on `CHARTEVENT_CHART_CHANGE` (fires on resize). Example: bottom-right HUD = `x = chartW - UI_PANEL_W - UI_PAD` with CORNER_LEFT_UPPER, or simply use CORNER_RIGHT_LOWER and let distances stay constant.

## 5. Price/time-anchored drawing — lines, rectangles, zones, circles, text on candles

Generic creator for ALL time/price objects, then thin wrappers. This is the correct way to draw market structures (order blocks, FVGs, liquidity lines, swing labels, signal arrows):

```mql5
// المُنشئ العام لكائنات السعر/الزمن — نقطتان كحد أقصى تكفيان لمعظم الأنواع
bool DrawCreate(const string id, ENUM_OBJECT type,
                datetime t1, double p1, datetime t2 = 0, double p2 = 0,
                color clr = THEME_ACCENT, int width = 1,
                ENUM_LINE_STYLE style = STYLE_SOLID, bool back = true, bool fill = false)
{
   string n = UI_PREFIX + id;
   if(ObjectFind(0, n) < 0)
   {
      bool ok = (t2 == 0) ? ObjectCreate(0, n, type, 0, t1, p1)
                          : ObjectCreate(0, n, type, 0, t1, p1, t2, p2);
      if(!ok) return false;
   }
   else // موجود — حدّث الإحداثيات بدل إعادة الإنشاء
   {
      ObjectMove(0, n, 0, t1, p1);
      if(t2 != 0) ObjectMove(0, n, 1, t2, p2);
   }
   ObjectSetInteger(0, n, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, n, OBJPROP_WIDTH,      width);
   ObjectSetInteger(0, n, OBJPROP_STYLE,      style);
   ObjectSetInteger(0, n, OBJPROP_BACK,       back);     // خلف الشموع — للمناطق
   ObjectSetInteger(0, n, OBJPROP_FILL,       fill);     // تعبئة المستطيل/الدائرة
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN,     true);
   return true;
}

// ===== أغلفة رقيقة — كل أشكال الرسم على الشموع =====

// خط أفقي (مستوى سعري ممتد)
bool DrawHLine(const string id, double price, color clr, ENUM_LINE_STYLE st = STYLE_DASH)
{ return DrawCreate(id, OBJ_HLINE, 0, price, 0, 0, clr, 1, st, false); }

// خط اتجاه بين شمعتين — RAY عبر OBJPROP_RAY_RIGHT
bool DrawTrend(const string id, datetime t1, double p1, datetime t2, double p2,
               color clr, bool rayRight = false, int width = 2)
{
   if(!DrawCreate(id, OBJ_TREND, t1, p1, t2, p2, clr, width, STYLE_SOLID, false)) return false;
   ObjectSetInteger(0, UI_PREFIX + id, OBJPROP_RAY_RIGHT, rayRight);
   return true;
}

// منطقة/مستطيل على الشموع (Order Block / FVG / Supply-Demand)
bool DrawZone(const string id, datetime t1, double pHigh, datetime t2, double pLow, color clr)
{ return DrawCreate(id, OBJ_RECTANGLE, t1, pHigh, t2, pLow, clr, 1, STYLE_SOLID, true, true); }

// دائرة/قطع ناقص حول منطقة سعرية — النقطتان قطرا الإطار المحيط
bool DrawEllipse(const string id, datetime t1, double p1, datetime t2, double p2, color clr)
{ return DrawCreate(id, OBJ_ELLIPSE, t1, p1, t2, p2, clr, 1, STYLE_SOLID, true, false); }

// سهم إشارة فوق/تحت شمعة — الكود من خط Wingdings (233=فوق، 234=تحت، 159=نقطة)
bool DrawArrow(const string id, datetime t, double price, uchar code, color clr,
               ENUM_ARROW_ANCHOR anchor = ANCHOR_TOP)
{
   if(!DrawCreate(id, OBJ_ARROW, t, price, 0, 0, clr, 2, STYLE_SOLID, false)) return false;
   ObjectSetInteger(0, UI_PREFIX + id, OBJPROP_ARROWCODE, code);
   ObjectSetInteger(0, UI_PREFIX + id, OBJPROP_ANCHOR,    anchor); // ANCHOR_TOP = الرأس عند السعر
   return true;
}

// نص ملتصق بشمعة (تسمية قمة/قاع، قيمة)
bool DrawText(const string id, datetime t, double price, const string text,
              color clr = THEME_TEXT, int fs = UI_FONT_SIZE,
              ENUM_ANCHOR_POINT anchor = ANCHOR_LOWER)
{
   if(!DrawCreate(id, OBJ_TEXT, t, price, 0, 0, clr, 1, STYLE_SOLID, false)) return false;
   string n = UI_PREFIX + id;
   ObjectSetString (0, n, OBJPROP_TEXT,     text);
   ObjectSetString (0, n, OBJPROP_FONT,     UI_FONT);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, fs);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR,   anchor);  // ANCHOR_LOWER = النص فوق السعر
   return true;
}
```

Precision rules that prevent "wrong place" bugs:
- **Anchor times come from bar times**: `iTime(_Symbol, _Period, shift)` — never computed datetimes; a time between bars snaps unpredictably on some TFs.
- **Zone right edge that extends with time**: set t2 = `iTime(...,0) + PeriodSeconds()*N` and update it on each new bar (via ObjectMove of point 1), or use OBJ_RECTANGLE + periodic extension; there is no native "ray rectangle".
- **OBJ_ARROW anchor matters**: ANCHOR_TOP puts the symbol's top at the price (use for arrows BELOW a low: price = low - offset). Offset arrows from candles by a fraction of ATR or `N*_Point`, never a fixed pixel count (pixels don't exist in this coordinate system).
- **Unique IDs per structure**: build from bar time — `"OB_" + TimeToString(t1, TIME_DATE|TIME_MINUTES)` — so updates target the same object and history scans don't duplicate.
- **OBJPROP_BACK = true for filled zones** so candles stay visible; false for lines that must overlay candles.
- **Filled vs outline**: OBJPROP_FILL=true fills RECTANGLE/ELLIPSE/TRIANGLE with OBJPROP_COLOR; for translucent-looking zones on builds without alpha, use a dark theme zone color (THEME_ZONE_*) + BACK=true.
- **OBJ_VLINE** spans all subwindows; **OBJ_HLINE** is infinite — for a bounded horizontal segment use OBJ_TREND with equal prices.
- Object count hygiene: indicators drawing per-bar structures must cap history (input `InpMaxObjects`) and delete oldest via stored ID ring buffer; thousands of objects freeze the chart.
- **`ChartRedraw()` applies here too**: ObjectMove/ObjectSet changes (including zone extension on new bars) render lazily — call ChartRedraw once after the drawing batch, same rule as §4.

## 6. OnChartEvent — full event handling

```mql5
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   switch(id)
   {
      case CHARTEVENT_OBJECT_CLICK:                 // sparam = اسم الكائن
         if(sparam == UI_PREFIX + "btnClose") { App_OnCloseAll(); ResetButton(sparam); }
         break;
      case CHARTEVENT_OBJECT_ENDEDIT:               // انتهاء تحرير OBJ_EDIT
         if(sparam == UI_PREFIX + "edLots") App_OnLotsChanged();
         break;
      case CHARTEVENT_OBJECT_DRAG:   break;         // سحب كائن selectable — غير موثوق للخطوط، انظر §6.1
      case CHARTEVENT_KEYDOWN:       /* lparam = key code */ break;
      case CHARTEVENT_MOUSE_MOVE:    /* يتطلب التفعيل أدناه */ break;
      case CHARTEVENT_CHART_CHANGE:  App_OnResize(); break;   // تغيير حجم/إعدادات الشارت
      default:
         if(id >= CHARTEVENT_CUSTOM) { /* أحداث مخصصة عبر EventChartCustom */ }
   }
}
```
- Mouse move/wheel events require opt-in in OnInit: `ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);` (and `CHART_EVENT_MOUSE_WHEEL`). For mouse move: lparam=X, dparam=Y, sparam=button-state flags.
- Custom events between programs: `EventChartCustom(chartId, eventId, lparam, dparam, sparam)` arrives as `CHARTEVENT_CUSTOM + eventId`. When several panels/modules coexist on one chart, give each emitter a base ID range (`#define RP_EVT_BASE 1000`) so `CHARTEVENT_CUSTOM+0` from two modules does not cross-trigger — see `references/module-integration.md` §8.
- Object click coordinates available via CHARTEVENT_CLICK (lparam=X, dparam=Y).
- Disable chart scroll while dragging custom UI: `ChartSetInteger(0, CHART_MOUSE_SCROLL, false)` temporarily.

### 6.1 Dragging chart objects reliably — DO NOT rely on CHARTEVENT_OBJECT_DRAG for thin price objects

`CHARTEVENT_OBJECT_DRAG` only fires for objects with `OBJPROP_SELECTABLE=true`, and native dragging of a selectable object depends on the terminal option **"Select objects by single click"** (Chart → Properties, or the terminal toolbar). When that option is off (the default for most users), the user must double/right-select first, so single-click drag silently does nothing — the EA looks broken on the tester's machine but "works" on yours. On top of that, `CHARTEVENT_CLICK` fires on the press BEFORE selection completes, so a click handler can steal the gesture. **Conclusion: never build dragging of trade lines / level lines (OBJ_HLINE, OBJ_TREND) on OBJECT_DRAG + SELECTABLE.** It is terminal-setting-dependent and unreliable.

**Reliable pattern — custom drag via MOUSE_MOVE, fully self-contained:**

1. All draggable lines are `OBJPROP_SELECTABLE=false` (so the platform never competes for the gesture and never hijacks a click).
2. Opt in: `ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);` in OnInit.
3. In `CHARTEVENT_MOUSE_MOVE`: `lparam`=X px, `dparam`=Y px, and the **left-button state is bit 0 of sparam**: `bool down = (bool)(StringToInteger(sparam) & 1);`
4. **HOVER-LATCH (the core fix).** A line is ~1px tall; by the time you detect the press (first move event WITH the button down) the cursor has usually already left the line, so hit-testing AT the press misses. Instead, on every move with the button UP, record which line is under the cursor (`hover_target`). On the press transition (down && !down_prev), latch `drag_target = hover_target`. Then follow the cursor while down; commit on release (down==false && down_prev).
5. **PRE-EMPTIVE scroll lock.** Toggle `CHART_MOUSE_SCROLL=false` the moment the cursor merely HOVERS a draggable line (button still up) — not when the drag starts. If you wait for the press, MT5 has already begun scrolling the chart under the press and the grab is lost. Re-enable it the instant the cursor leaves all draggable lines and no drag is active.

```mql5
// STATE: int hover_target, drag_target; bool down_prev; bool scroll_locked;
void OnMouseMove(int x, int y, bool down)
{
   int hov = HitLine(y);                       // أي خط تحت المؤشر هندسياً (نطاق ~10px)، 0=لا شيء
   if(!down) hover_target = hov;               // التقاط استباقي قبل الضغط
   bool want_lock = (hov > 0) || (drag_target > 0);   // اقفل التمرير بمجرد التحويم
   if(want_lock != scroll_locked)
   { ChartSetInteger(0, CHART_MOUSE_SCROLL, !want_lock); scroll_locked = want_lock; }
   if(down && !down_prev) drag_target = (hov > 0 ? hov : hover_target);   // مزلاج الضغط
   else if(down && drag_target > 0) MoveLineTo(drag_target, y);           // اتبع المؤشر
   else if(!down && down_prev && drag_target > 0)                         // الإفلات ⇒ التزام
   { CommitLine(drag_target); drag_target = 0; suppress_click = true; }
   down_prev = down;
}
```

### 6.2 CHARTEVENT_CLICK vs CHARTEVENT_OBJECT_CLICK — and the deselect-on-click trap

- `CHARTEVENT_OBJECT_CLICK` fires when a **selectable** object is clicked (`sparam`=name). `CHARTEVENT_CLICK` fires for clicks on the bare chart OR on non-selectable objects (`lparam`=X, `dparam`=Y). Because the reliable drag pattern makes lines `SELECTABLE=false`, clicks on them arrive as `CHARTEVENT_CLICK`, not OBJECT_CLICK.
- **Trap:** a selection system that does "click empty space ⇒ deselect" will wrongly deselect when the user clicks **its own** lines/boxes/edit-fields (those are non-selectable ⇒ they come through CHARTEVENT_CLICK too). Before deselecting, test "is this point over any of my own widgets (line hit-band, box rect, edit field)?" and only deselect when it is genuinely outside everything.
- **Post-drag phantom click:** finishing a custom MOUSE_MOVE drag can emit a trailing `CHARTEVENT_CLICK` at the drop point. Set a `suppress_click` flag on drag-release and consume it in the click handler (clear & return) so the drop does not cancel the current selection. Clear the flag at the start of every fresh press so it never lingers.

## 7. Standard Library panels (CAppDialog + Controls)

Available controls (MQL5\Include\Controls\): `CButton, CEdit, CLabel, CPanel, CPicture, CBmpButton, CCheckBox, CCheckGroup, CRadioButton, CRadioGroup, CComboBox, CListView, CSpinEdit, CDatePicker, CScrollV/H, CWndClient` (scrollable container), `CDialog, CAppDialog`.

```mql5
#include <Controls\Dialog.mqh>
#include <Controls\Button.mqh>
#include <Controls\Edit.mqh>
#include <Controls\ComboBox.mqh>

class CPanelApp : public CAppDialog
{
private:
   CButton   m_btnBuy;
   CEdit     m_edLots;
   CComboBox m_cbMode;
public:
   virtual bool Create(const long chart, const string name, const int subwin,
                       const int x1, const int y1, const int x2, const int y2);
   virtual bool OnEvent(const int id, const long &lparam, const double &dparam, const string &sparam);
protected:
   bool CreateControls();
   void OnClickBuy();
   void OnChangeMode();
};

bool CPanelApp::Create(const long chart,const string name,const int subwin,
                       const int x1,const int y1,const int x2,const int y2)
{
   if(!CAppDialog::Create(chart, name, subwin, x1, y1, x2, y2)) return false;
   return CreateControls();
}

bool CPanelApp::CreateControls()
{
   // الإحداثيات نسبية لمنطقة العميل ClientArea
   if(!m_btnBuy.Create(m_chart_id, m_name+"BtnBuy", m_subwin, 10, 10, 110, 40)) return false;
   m_btnBuy.Text("BUY");   // نص الواجهة إنجليزي دائماً
   if(!Add(m_btnBuy)) return false;          // Add إلزامي — بدونه لا أحداث ولا رسم

   if(!m_edLots.Create(m_chart_id, m_name+"EdLots", m_subwin, 120, 10, 220, 40)) return false;
   m_edLots.Text("0.10");
   if(!Add(m_edLots)) return false;
   return true;
}

// خريطة الأحداث — أنظف من override يدوي لـ OnEvent
EVENT_MAP_BEGIN(CPanelApp)
   ON_EVENT(ON_CLICK,  m_btnBuy, OnClickBuy)
   ON_EVENT(ON_CHANGE, m_cbMode, OnChangeMode)
EVENT_MAP_END(CAppDialog)

// البديل اليدوي المكافئ — استخدمه إذا فشلت الماكروهات في الترجمة على build المستخدم
// bool CPanelApp::OnEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
// {
//    if(id == CHARTEVENT_CUSTOM + ON_CLICK && lparam == m_btnBuy.Id()) { OnClickBuy(); return true; }
//    if(id == CHARTEVENT_CUSTOM + ON_CHANGE && lparam == m_cbMode.Id()) { OnChangeMode(); return true; }
//    return CAppDialog::OnEvent(id, lparam, dparam, sparam);
// }

CPanelApp g_panel;

int OnInit()
{
   if(!g_panel.Create(0, "Trade Panel", 0, 20, 20, 360, 240)) return INIT_FAILED;
   g_panel.Run();
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) { g_panel.Destroy(reason); }
void OnChartEvent(const int id,const long &l,const double &d,const string &s)
{ g_panel.ChartEvent(id, l, d, s); }
```
Non-negotiables:
- `Add(control)` after every Create — forgotten Add = invisible/dead control.
- `Run()` in OnInit, `Destroy(reason)` in OnDeinit, `ChartEvent` forwarding in OnChartEvent. Missing any of the three breaks the panel.
- Event macros (`EVENT_MAP_BEGIN`, `ON_EVENT`, ON_CLICK/ON_CHANGE/ON_END_EDIT/ON_DRAG_END...) come from `Controls\Defines.mqh` (included via Dialog.mqh).
- In an indicator the panel works the same; in the Strategy Tester panels render only in visual mode.
- Multiple panels on one chart (or merging panel programs): each `CAppDialog` needs a UNIQUE `name` argument to `Create` — all child object names derive from it, so duplicate names kill one panel's controls. See `references/module-integration.md` §8.

## 7b. Controls library — complete control reference

§7 shows the skeleton. This is the per-control read/write API, so a panel built from the standard library alone (no native objects, no factory pattern) needs no improvisation. Method names below are exact — the standard library varies across classes (`CComboBox`/`CListView` accept both `AddItem` and `ItemAdd`; `CCheckGroup`/`CRadioGroup` expose only `AddItem`), so copy them verbatim.

**Coordinate model inside CAppDialog.** All child coordinates are relative to the dialog's **client area**, not the chart. In `Create(chart, name, subwin, x1, y1, x2, y2)`, `x2/y2` are the **absolute right/bottom edge**, NOT width/height — the #1 cause of "controls fall outside the panel". A control at `Create(..., 10, 10, 110, 40)` is 100 px wide × 30 px tall, placed 10 px in from the client-area origin. Client-area extent is `ClientAreaWidth()`/`ClientAreaHeight()`; derive child x2/y2 from those, never from chart pixels.

```mql5
// CCheckBox — صندوق اختيار منفرد
CCheckBox m_chk;
m_chk.Create(m_chart_id, m_name+"Chk", m_subwin, 10, 10, 200, 30);
m_chk.Text("Trail enabled");          // نص الواجهة إنجليزي
if(!Add(m_chk)) return false;
bool on = m_chk.Checked();            // قراءة
m_chk.Checked(true);                  // كتابة
// الحدث: ON_CHANGE على m_chk

// CCheckGroup — مجموعة صناديق، القيمة bitmask
CCheckGroup m_grp;
m_grp.Create(m_chart_id, m_name+"Grp", m_subwin, 10, 40, 200, 140);
m_grp.AddItem("News filter", 1);      // bit 0
m_grp.AddItem("Spread filter", 2);    // bit 1
m_grp.AddItem("Time filter", 4);      // bit 2
if(!Add(m_grp)) return false;
long flags = m_grp.Value();           // قراءة كل الأعلام مجمّعة
bool spreadOn = (flags & 2) != 0;     // فحص bit مفرد
m_grp.Value(1|4);                     // كتابة — تفعيل News + Time

// CRadioGroup — اختيار واحد حصري تلقائياً
CRadioGroup m_radio;
m_radio.AddItem("Conservative", 0);
m_radio.AddItem("Balanced", 1);
m_radio.AddItem("Aggressive", 2);
long mode = m_radio.Value();          // قيمة العنصر المحدد فقط، لا bitmask

// CSpinEdit — عدّاد صحيح. القيم int (m_min/m_max/m_value كلها int): Value()/MinValue()/MaxValue() تُرجع/تأخذ int
CSpinEdit m_spin;
m_spin.Create(m_chart_id, m_name+"Spin", m_subwin, 10, 150, 120, 175);
m_spin.MinValue(1); m_spin.MaxValue(100); m_spin.Value(10);
int v = m_spin.Value();
// لا يمثّل قيماً كسرية (0.01 lot) إطلاقاً: استخدم عدداً صحيحاً للخطوات
//   int steps = m_spin.Value(); double lots = steps * 0.01;  ← الكسر يُحسب خارج الـ control
// أو استبدله بـ CEdit + تحقّق يدوي، أو كلاس فرعي تكتبه أنت يرث CSpinEdit (مثل CSpinEditDouble — ليس ضمن المكتبة القياسية).

// CComboBox — قائمة منسدلة. كلا ItemAdd و AddItem يعملان (AddItem غلاف لـ ItemAdd)
CComboBox m_cb;
m_cb.Create(m_chart_id, m_name+"Cb", m_subwin, 10, 185, 200, 210);
m_cb.ItemAdd("M1",  PERIOD_M1);       // (نص، قيمة) — أو m_cb.AddItem("M1", PERIOD_M1)
m_cb.ItemAdd("H1",  PERIOD_H1);
m_cb.SelectByValue(PERIOD_H1);        // أو SelectByText("H1") أو Select(index)
if(!Add(m_cb)) return false;
// الحدث ON_CHANGE → اقرأ m_cb.Value() لقيمة العنصر المحدد

// CListView — قائمة. الإضافة القانونية AddItem (ItemAdd alias)، الحذف ItemDelete(index)
CListView m_lv;
m_lv.Create(m_chart_id, m_name+"Lv", m_subwin, 10, 220, 200, 340);
m_lv.AddItem("EURUSD", 1);
m_lv.AddItem("GBPUSD", 2);
m_lv.ItemDelete(0);                   // حذف بالفهرس
m_lv.ItemsClear();                    // مسح الكل
int sel = m_lv.Current();             // فهرس المحدد
m_lv.Select(1);                       // تحديد بالفهرس

// CWndClient — حاوية متمررة متداخلة: أضف الأبناء إليها هي، لا إلى الـ dialog
CWndClient m_client;
m_client.Create(m_chart_id, m_name+"Cl", m_subwin, 0, 0, 200, 400);
if(!Add(m_client)) return false;
if(!m_client.Add(m_chk)) return false;   // ← m_client.Add وليس this->Add

// CBmpButton — زر بصورتين on/off عبر #resource
CBmpButton m_bmp;
m_bmp.Create(m_chart_id, m_name+"Bmp", m_subwin, 10, 350, 42, 382);
m_bmp.BmpNames("::img\\off.bmp", "::img\\on.bmp");
m_bmp.Pressed(false);
```

**Event constants (from `Controls\Defines.mqh`), used in `ON_EVENT(EVENT, control, handler)`:**

| Event | Fired by |
|---|---|
| `ON_CLICK` | CButton, CBmpButton, CCheckBox |
| `ON_CHANGE` | CCheckBox, CCheckGroup, CRadioGroup, CComboBox, CSpinEdit |
| `ON_START_EDIT` | CEdit (entered edit mode) |
| `ON_END_EDIT` | CEdit (committed — read value here into STATE) |
| `ON_SCROLL_INC` / `ON_SCROLL_DEC` | CScrollV, CScrollH (separate up/down constants — there is no single `ON_SCROLL`) |
| `ON_DRAG_START` / `ON_DRAG_PROCESS` / `ON_DRAG_END` | draggable dialog / objects (there is no `ON_OBJECT_DRAG`) |
| `ON_MOUSE_FOCUS_SET` / `ON_MOUSE_FOCUS_KILL` | hover enter / leave |

**Runtime setters by base class (the inheritance split matters):** every control derives from `CWnd`, which provides `Show()`, `Hide()`, `Enable()`, `Disable()`, `Move(x,y)`, `Width()`, `Height()`. Color/font setters `Color(clr)`, `ColorBackground(clr)`, `Font(name)` live on `CWndObj` and therefore work on the SIMPLE object-backed controls only — `CButton`, `CEdit`, `CLabel`, `CPanel`, `CPicture`, `CBmpButton`. The compound controls (`CCheckBox`, `CComboBox`, `CSpinEdit` derive from `CWndContainer`; `CListView`, `CCheckGroup`, `CRadioGroup` from `CWndClient`) do NOT expose `Color`/`ColorBackground` directly — recolor their inner parts via the Defines overrides (§8) or per-subcontrol access. There is no `Tooltip()` method in this Controls library version. After mutating geometry/colors outside the event flow, call `ChartRedraw()`.

**Rules with no exception:**
- `Add()` (or `m_client.Add()`) after every `Create()` — a forgotten Add = invisible, dead control.
- Child coordinates are client-area-relative; `x2/y2` are edges, not sizes.
- `#include <Controls\Defines.mqh>` (or any control header that pulls it) must precede use of `ON_*`/`EVENT_MAP_*`; appearance `#undef`/`#define` overrides go BEFORE the control includes (§8).
- `CCheckGroup.Value()` is a bitmask; `CRadioGroup.Value()` is a single value — never read one as the other.
- `CSpinEdit` is `int`-only (`Value()/MinValue()/MaxValue()` are `int`); fractional lots are computed outside it (integer steps × increment) or via a developer-written subclass of `CSpinEdit` (e.g. a `CSpinEditDouble` you define yourself — it is NOT part of the standard library).

## 8. Customizing Controls appearance (Defines.mqh trick)

Colors/metrics are `#define`s — override BEFORE including controls:
```mql5
#include <Controls\Defines.mqh>
#undef  CONTROLS_DIALOG_COLOR_CLIENT_BG
#undef  CONTROLS_BUTTON_COLOR_BG
#undef  CONTROLS_FONT_NAME
#undef  CONTROLS_FONT_SIZE
#define CONTROLS_DIALOG_COLOR_CLIENT_BG  C'30,34,45'   // ← يكسر أيقونات الـ glyph، اقرأ التحذير أدناه
#define CONTROLS_BUTTON_COLOR_BG         C'0,120,215'
#define CONTROLS_FONT_NAME               "Segoe UI"
#define CONTROLS_FONT_SIZE               11
#include <Controls\Dialog.mqh>
#include <Controls\Button.mqh>
```
Per-control overrides at runtime: `m_btnBuy.ColorBackground(clr); m_btnBuy.Color(clrWhite); m_btnBuy.FontSize(12);` — runtime setters win over defines.

> **⚠ Dark themes break the bitmap-glyph controls.** `CCheckBox`, `CSpinEdit`,
> `CComboBox`, and the `CAppDialog` caption Close/Minimize buttons draw their
> glyphs from fixed `#resource` BMPs in `assets\Controls\res\`
> (`CheckBoxOn/Off`, `SpinInc/Dec`, `DropOn/Off`, and the caption `Close`,
> `Turn`, `Restore`). These glyphs are authored for the default LIGHT control
> surface and are NOT recolored by the Defines override. Overriding
> `CONTROLS_DIALOG_COLOR_CLIENT_BG` / `..._BG` to a dark value makes them render
> as solid/odd squares (fixed pixels + transparency key over a dark background).
> The `C'30,34,45'` example above triggers this if the panel uses any of those
> controls.
>
> The label inside `CCheckBox` is a read-only `CEdit` (`m_label`) using
> `CONTROLS_EDIT_COLOR_BG`; darkening the client bg without it leaves checkbox
> labels as mismatched light boxes.
>
> Safe rules:
> - Keep the default light palette, or override only colors of glyph-free controls
>   (`CButton`/`CEdit`/`CLabel` text + dialog caption text).
> - Override `CONTROLS_EDIT_COLOR_BG` together with the dialog bg so CEdit-based
>   labels (incl. CCheckBox labels) stay coherent.
> - For a true dark UI with standard controls, ship your own `#resource` BMPs and
>   assign them via `CBmpButton::BmpNames(...)`; the stock res glyphs won't adapt.
> - A plain `CAppDialog` with NO Defines override renders the stock bitmaps
>   correctly — confirming they only work on the light surface they were authored for.

## 9. Panel persistence across timeframe changes

OnDeinit fires on TF/symbol change (reason REASON_CHARTCHANGE) and destroys the panel at its default position. Persist geometry:
```mql5
void OnDeinit(const int reason)
{
   if(reason == REASON_CHARTCHANGE)
   {
      GlobalVariableTemp("PANEL_X");
      GlobalVariableSet("PANEL_X", g_panel.Left());
      GlobalVariableSet("PANEL_Y", g_panel.Top());
      GlobalVariableSet("PANEL_MIN", g_panel.IsMinimized() ? 1 : 0);
   }
   g_panel.Destroy(reason);
}
// وفي OnInit: اقرأ القيم إن وجدت ومرّرها إلى Create ثم Minimize() عند الحاجة
```
The same applies to native-object panels — store x/y of the container.

## 10. CCanvas custom rendering

```mql5
#include <Canvas\Canvas.mqh>

// مكتبة ألوان الكانفس — ARGB لدعم الشفافية، مشتقة من THEME
#define CV_BG      ARGB(200, 22, 26, 34)
#define CV_HEADER  ARGB(255, 0, 120, 215)
#define CV_BORDER  ARGB(255, 90, 96, 110)

CCanvas g_cv;

int OnInit()
{
   // bitmap label مثبت على الشاشة، صيغة ARGB لدعم الشفافية
   if(!g_cv.CreateBitmapLabel("MYCV", 20, 20, 420, 260, COLOR_FORMAT_ARGB_NORMALIZE))
      return INIT_FAILED;
   Redraw();
   return INIT_SUCCEEDED;
}

void Redraw()
{
   g_cv.Erase(CV_BG);                                  // خلفية شبه شفافة — من مكتبة الألوان
   g_cv.FillRectangle(0, 0, 419, 36, CV_HEADER);       // شريط العنوان
   g_cv.FontSet("Segoe UI", -140, FW_BOLD);            // -140 = 14.0 نقطة (القيمة السالبة = أعشار النقطة، مستقلة عن DPI)
   g_cv.TextOut(210, 18, "Risk Dashboard", ARGB(255,255,255,255), TA_CENTER|TA_VCENTER);
   g_cv.LineAA(10, 60, 410, 60, CV_BORDER);
   g_cv.Update();                                      // بدونها لا يظهر شيء
}

void OnDeinit(const int reason) { g_cv.Destroy(); }
```
- Primitive families: plain (Line, Rectangle, Circle...), filled (FillRectangle, FillCircle, FillPolygon, Fill flood), antialiased (LineAA, PolylineAA, CircleAA, TriangleAA, LineThick, CurveBezier), pixel (PixelSet/PixelSetAA, PixelGet).
- Coordinates are int pixels relative to the canvas; the canvas itself is positioned like a bitmap-label object (move via `ObjectSetInteger(0,"MYCV",OBJPROP_XDISTANCE,x)`).
- `FontSet(name, size, flags, angle)`: positive size = points (DPI-dependent); NEGATIVE size = tenths of a logical point and is DPI-independent (so `-140` = 14.0 pt, `-160` = 16.0 pt — the reliable choice for consistent layout across machines); flags FW_BOLD/FONT_ITALIC; TextOut alignment via TA_LEFT/CENTER/RIGHT | TA_TOP/VCENTER/BOTTOM. Measure with `TextWidth`/`TextHeight` for layout.
- Hit-testing is manual: store rects per widget, test in CHARTEVENT_MOUSE_MOVE/CHARTEVENT_OBJECT_CLICK on the canvas object, redraw hovering states.
- Performance: redraw only on state change, not per tick; Erase+full repaint of a 400×300 canvas is cheap, but `Update()` per tick on multiple canvases is not. Batch: change state → one Redraw → one Update.
- Transparency requires the ARGB color format and `ARGB(alpha,r,g,b)` colors; `ColorToARGB(clrRed, 255)` converts.

## 11. Layout engine — grid/row helpers to kill coordinate arithmetic

Hand-computed x/y per element is the second-biggest GUI bug source (overlaps, drift after one size change). Derive every coordinate from METRICS through a tiny layout helper:

```mql5
// مولّد صفوف — كل عنصر يأخذ موضعه من الشبكة، لا حساب يدوي
struct SLayout
{
   int x, y, w;          // مؤشر الموضع الحالي + عرض اللوحة
   void Begin(int startX, int startY, int width) { x=startX+UI_PAD; y=startY+UI_PAD; w=width; }
   int  RowY()      { int r = y; y += UI_ROW_H + UI_PAD; return r; }   // صف جديد
   int  ColX(int i, int cols)                                          // عمود i من cols
   { return x + i * ((w - 2*UI_PAD) / cols); }
   int  ColW(int cols) { return (w - 2*UI_PAD) / cols - UI_PAD; }
};

bool BuildPanel()
{
   SLayout L; L.Begin(20, 20, UI_PANEL_W);
   if(!UiPanel ("bg", 20, 20, UI_PANEL_W, 4*UI_ROW_H + 5*UI_PAD)) return false;
   if(!UiLabel ("title", L.x, L.RowY(), "Trade Panel", THEME_TEXT, UI_FONT_SIZE_TITLE)) return false;
   int rowBtns = L.RowY();
   if(!UiButton("btnBuy",  L.ColX(0,2), rowBtns, L.ColW(2), UI_ROW_H, "BUY",  THEME_BUY))  return false;
   if(!UiButton("btnSell", L.ColX(1,2), rowBtns, L.ColW(2), UI_ROW_H, "SELL", THEME_SELL)) return false;
   if(!UiLabel ("status", L.x, L.RowY(), "Status: idle", THEME_TEXT_DIM)) return false;
   ChartRedraw();
   return true;
}
```
Changing UI_ROW_H or UI_PAD now reflows the entire panel. The same SLayout works for CAppDialog client-area coordinates and CCanvas cells.

## 12. GUI layering standard (UI/EVENTS separation)

- UI layer: the only place calling ObjectCreate/ObjectSet*/Canvas/Controls methods. Exposes semantic functions: `UI_ShowProfit(double)`, `UI_SetState(string)`. The only place THEME/METRICS/TEXTS tokens are consumed.
- EVENTS layer: OnChartEvent maps raw events to App actions only — no calculations, no direct object manipulation.
- STATE drives UI: event → mutate STATE → single `UI_Refresh()` reading STATE. Never write UI from business logic mid-calculation.
- All object names from one CONFIG prefix; states stored in STATE, not read back from objects (objects are display, not storage) — except OBJ_EDIT user input, read once on ENDEDIT into STATE.
- DRY enforcement: one factory per object kind (§4), one generic creator for price/time drawings (§5), one layout struct (§11). A second near-identical creation block anywhere is a defect.
- Delete-dead-code rule applies to UI: any factory or token defined but never used is removed before delivery.

## 13. UI text language policy

**All user-visible text is English**: button captions, panel titles, status lines, input display names, Alert/Print/log messages, object tooltips. Arabic appears ONLY in source-code comments. Rationale: consistent rendering across fonts/builds (no bidi reordering issues), Market/CodeBase compatibility, broker-log readability.

Implementation details that still matter for English UI:
- Centralize every string in CONFIG (one `// TEXTS` block of `#define TXT_*` or a string table) — no inline literals in factories or logic; this keeps DRY and makes future localization a one-block job.
```mql5
// TEXTS — كل نصوص الواجهة هنا حصراً
#define TXT_TITLE       "Trade Panel"
#define TXT_BTN_BUY     "BUY"
#define TXT_BTN_SELL    "SELL"
#define TXT_STATUS_IDLE "Status: idle"
#define TXT_ERR_VOLUME  "Invalid volume"
```
- Mixed text+number rows: format once with `StringFormat("Risk: %.2f%%  P/L: %+.2f", riskPct, pl)` — single label per row, padded with spaces for column alignment, or split label/value into two objects when the value updates every tick (cheaper redraw).
- Fonts: "Segoe UI" / "Tahoma" / "Arial" for UI; "Consolas"/"Courier New" for aligned numeric columns.
