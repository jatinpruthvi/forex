# MQL5 Custom Indicators — Production Reference

## Contents
1. Buffer/plot anatomy
2. OnCalculate loop — the canonical pattern
3. Indexing convention discipline
4. Color buffers, draw begin, empty values
5. Using indicator handles (built-in and iCustom)
6. Multi-timeframe / multi-symbol indicators
7. Indicator-in-EA correct consumption
8. Performance rules

## 1. Buffer/plot anatomy

```mql5
#property indicator_chart_window          // أو indicator_separate_window
#property indicator_buffers 3             // إجمالي المصفوفات المسجلة (بما فيها الحسابية)
#property indicator_plots   2             // المرسومة فقط
#property indicator_label1  "Up"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  2
#property indicator_label2  "Down"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed

double upBuf[], dnBuf[], workBuf[];

int OnInit()
{
   SetIndexBuffer(0, upBuf,   INDICATOR_DATA);
   SetIndexBuffer(1, dnBuf,   INDICATOR_DATA);
   SetIndexBuffer(2, workBuf, INDICATOR_CALCULATIONS);   // غير مرسوم، يُعاد حسابه تلقائياً
   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   IndicatorSetString(INDICATOR_SHORTNAME, "MyInd(" + (string)InpPeriod + ")");
   return INIT_SUCCEEDED;
}
```
- Buffers bound with `SetIndexBuffer` are auto-resized by the terminal — never `ArrayResize` them.
- `indicator_buffers` count must include calculation buffers; mismatch = silent garbage.
- DRAW types: DRAW_LINE, DRAW_HISTOGRAM, DRAW_ARROW, DRAW_SECTION, DRAW_ZIGZAG (2 buffers), DRAW_FILLING (2), DRAW_CANDLES (4), DRAW_COLOR_* variants need an extra INDICATOR_COLOR_INDEX buffer.

## 2. OnCalculate loop — the canonical pattern

```mql5
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[], const double &high[],
                const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
{
   if(rates_total < InpPeriod) return 0;            // بيانات غير كافية
   if(rates_total < prev_calculated) return 0;      // حارس ضد حالة تبديل السيرفر النادرة

   int start;
   if(prev_calculated == 0)
   {
      ArrayInitialize(upBuf, EMPTY_VALUE);          // تهيئة عند أول تشغيل/إعادة تحميل التاريخ
      ArrayInitialize(dnBuf, EMPTY_VALUE);
      start = InpPeriod;                            // فترة الإحماء
   }
   else
      start = prev_calculated - 1;                  // أعد حساب آخر شمعة (المتكونة)

   for(int i = start; i < rates_total && !IsStopped(); i++)
   {
      // المنطق هنا — i يتزايد نحو الأحدث (فهرسة غير series)
   }
   return rates_total;                              // دائماً — وإلا تختفي القيم من Data Window
}
```
Facts encoded here:
- `prev_calculated == 0` also occurs when deeper history loads or gaps fill — the terminal forces full recalc. Re-initialize state then.
- `prev_calculated - 1` recalculates the forming bar every tick — required for any indicator reading the current bar.
- Return `rates_total` even when drawing a limited window; it is the readiness signal to EAs via `BarsCalculated`.
- Returning 0 hides the indicator from the Data Window.
- Repaint avoidance: signals confirmed on bar close read index `rates_total-2` (last closed) and never rewrite older cells after confirmation.

## 3. Indexing convention discipline

Pick ONE convention per indicator and enforce it everywhere:
- **Non-series (default, recommended)**: 0 = oldest. Input arrays of OnCalculate arrive non-series. Loop forward as above.
- **Series (MQL4 style)**: call `ArraySetAsSeries(buf, true)` on EVERY buffer AND every input array used, loop `for(int i = limit; i >= 0; i--)`.

Mixing conventions is the #1 cause of "indicator draws only the first bar" / mirrored output. The input arrays' direction can be flipped too: `ArraySetAsSeries(close, true)` inside OnCalculate is legal and local to the call.

## 4. Color buffers, draw begin, empty values

```mql5
#property indicator_type1 DRAW_COLOR_LINE
#property indicator_color1 clrGray,clrLime,clrRed   // فهارس الألوان 0,1,2
double lineBuf[]; double colorBuf[];
// OnInit:
SetIndexBuffer(0, lineBuf,  INDICATOR_DATA);
SetIndexBuffer(1, colorBuf, INDICATOR_COLOR_INDEX);
// OnCalculate:
lineBuf[i]  = value;
colorBuf[i] = (value > prev) ? 1 : 2;               // فهرس اللون، ليس اللون نفسه
```
- `PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, InpPeriod)` hides garbage warm-up cells.
- Gap in a DRAW_LINE: write `EMPTY_VALUE` (with PLOT_EMPTY_VALUE set); for histograms use 0 only if 0 is the configured empty value.

## 5. Using indicator handles (built-in and iCustom)

```mql5
int hMA = INVALID_HANDLE, hCustom = INVALID_HANDLE;

int OnInit()
{
   hMA = iMA(_Symbol, PERIOD_CURRENT, 20, 0, MODE_EMA, PRICE_CLOSE);
   hCustom = iCustom(_Symbol, PERIOD_CURRENT, "MyFolder\\MyInd", Param1, Param2);
   if(hMA == INVALID_HANDLE || hCustom == INVALID_HANDLE)
   {
      Print("فشل إنشاء المؤشر: ", GetLastError());
      return INIT_FAILED;
   }
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(hMA != INVALID_HANDLE)     IndicatorRelease(hMA);
   if(hCustom != INVALID_HANDLE) IndicatorRelease(hCustom);
}

double GetMA(int shift)   // shift: 0=الشمعة الحالية، 1=آخر مغلقة
{
   double v[1];
   if(CopyBuffer(hMA, 0, shift, 1, v) != 1) return EMPTY_VALUE;  // تحقق دائماً
   return v[0];
}
```
- Handles in OnInit only. A handle created repeatedly with identical params returns the same handle but increments an internal counter — leaks until 4806/handle exhaustion.
- `CopyBuffer(handle, bufferIndex, start, count, array)` — bufferIndex matches `SetIndexBuffer` index in the source indicator, start=0 is the CURRENT bar regardless of array conventions.
- iCustom path: relative to MQL5\Indicators, `\\` separators, no .ex5 extension. Parameters must match the indicator's input order EXACTLY (type-sensitive). To ship a self-contained EA, place the indicator .ex5 INSIDE the project folder and embed it: `#resource "MyInd.ex5"` then `iCustom(..., "::MyInd.ex5", ...)` — keeps the project portable per the single-folder rule (SKILL.md). The `"\\Indicators\\..."` resource form also works but ties the source tree to MQL5\Indicators.

## 6. Multi-timeframe / multi-symbol indicators

Data for other symbols/TFs is built lazily. First access usually fails. Correct startup:

```mql5
int OnInit()
{
   hHTF = iMA(_Symbol, PERIOD_H4, 20, 0, MODE_EMA, PRICE_CLOSE);
   if(hHTF == INVALID_HANDLE) return INIT_FAILED;
   EventSetTimer(1);              // أعد المحاولة حتى تجهز البيانات
   return INIT_SUCCEEDED;
}

void OnTimer()
{
   if(BarsCalculated(hHTF) > 0 && Bars(_Symbol, PERIOD_H4) > 0)
   {
      EventKillTimer();
      g_htfReady = true;
      ChartSetSymbolPeriod(0, _Symbol, _Period);   // فرض إعادة حساب OnCalculate
   }
}
```
- In OnCalculate, if `CopyBuffer` from the HTF handle returns < requested: `return prev_calculated;` (keep what's drawn, retry next tick) — never return rates_total pretending success.
- Map HTF values to chart bars with `iBarShift(_Symbol, PERIOD_H4, time[i])`.
- In the tester, HTF data of the tested symbol is available; OTHER symbols require they be selected in Market Watch and may need the same readiness loop.

## 7. Indicator-in-EA correct consumption

EAs read indicators exclusively through handles + CopyBuffer (never `ChartIndicatorGet` — chart functions are dead in optimization):
```mql5
double ma[3];
ArraySetAsSeries(ma, true);
if(CopyBuffer(hMA, 0, 0, 3, ma) < 3) return;   // ma[1]=آخر مغلقة، ma[2]=ما قبلها
bool crossUp = ma[2] < priceClosed2 && ma[1] > priceClosed1; // مثال
```
Signals on closed bars (index 1,2 with series) are tester-consistent; index 0 values change intra-bar.

## 8. Performance rules

- Never recalc full history per tick: the prev_calculated pattern is mandatory, not optional.
- Heavy indicators block ALL indicators of the same symbol (shared thread). Move slow I/O to a service or EA timer.
- `tester_everytick_calculate` property: add `#property tester_everytick_calculate` only when an EA polls the indicator less than once per bar and you must avoid full recalcs in the tester; otherwise omit.
- Prefer incremental formulas (running sums, Wilder smoothing as recurrence) over windowed loops per bar: SMA as `sum += close[i] - close[i-p]` turns O(N·P) into O(N).
- `IsStopped()` check in long loops keeps the terminal responsive on TF switches.
- For min/max over a window use `ArrayMaximum/ArrayMinimum` on the input arrays with explicit start/count instead of manual scans.

## 9. ICT / SMC Detection Patterns

Minimal, reusable building blocks. All functions use non-series indexing (0 = oldest) matching the OnCalculate loop convention. Pass the OnCalculate `high[]`/`low[]`/`open[]`/`close[]` arrays directly.

### Fair Value Gap (FVG)

A 3-bar imbalance: the middle candle's range is not overlapped by the outer two.

```mql5
// Bullish FVG: candle[i-2].high < candle[i].low  → unfilled gap above
// Bearish FVG: candle[i-2].low  > candle[i].high → unfilled gap below
bool IsBullFVG(const double &high[], const double &low[], int i)
{
   if(i < 2) return false;
   return low[i] > high[i-2];
}
bool IsBearFVG(const double &high[], const double &low[], int i)
{
   if(i < 2) return false;
   return high[i] < low[i-2];
}
// FVG zone:
//   Bull → [high[i-2], low[i]]   — equilibrium at (high[i-2]+low[i])/2
//   Bear → [high[i], low[i-2]]
```

### Order Block (OB)

Last opposing candle before a strong impulse. Simple one-bar form:

```mql5
// Bullish OB: last bearish candle (close < open) immediately before bullish impulse
// Bearish OB: last bullish candle immediately before bearish impulse
// "Impulse" threshold: next candle body > ATR * multiplier
bool IsBullOB(const double &open[], const double &close[], const double &atr[], int i, double mult=1.5)
{
   if(i < 1) return false;
   bool prevBear  = close[i-1] < open[i-1];
   bool strongUp  = (close[i] - open[i]) > atr[i] * mult;
   return prevBear && strongUp;
}
bool IsBearOB(const double &open[], const double &close[], const double &atr[], int i, double mult=1.5)
{
   if(i < 1) return false;
   bool prevBull  = close[i-1] > open[i-1];
   bool strongDn  = (open[i] - close[i]) > atr[i] * mult;
   return prevBull && strongDn;
}
// OB zone:
//   Bull OB → [low[i-1], high[i-1]]
//   Bear OB → [low[i-1], high[i-1]]
```

### Break of Structure (BOS) / Change of Character (ChoCh)

Requires pre-computed swing highs and lows. Use a lookback-N swing detector:

```mql5
// Swing high at bar i: highest high in [i-N, i+N]
bool IsSwingHigh(const double &high[], int i, int N, int total)
{
   if(i < N || i+N >= total) return false;
   double h = high[i];
   for(int k = i-N; k <= i+N; k++)
      if(k != i && high[k] >= h) return false;
   return true;
}
bool IsSwingLow(const double &low[], int i, int N, int total)
{
   if(i < N || i+N >= total) return false;
   double l = low[i];
   for(int k = i-N; k <= i+N; k++)
      if(k != i && low[k] <= l) return false;
   return true;
}

// BOS Bull: close breaks above the most recent confirmed swing high
bool IsBOSBull(double closeNow, double prevSwingHigh)
{ return closeNow > prevSwingHigh && prevSwingHigh > 0; }

bool IsBOSBear(double closeNow, double prevSwingLow)
{ return closeNow < prevSwingLow && prevSwingLow > 0; }
```

In `OnCalculate`: scan for swing points on confirmed bars (`i < rates_total-1`), store the latest in STATE variables, check BOS on each new bar. Never check swing membership on the forming bar (index `rates_total-1`) to prevent repainting.

### Premium / Discount / Equilibrium

```mql5
// Range between two price levels (e.g. swing low to swing high)
double Equilibrium(double lo, double hi)  { return (lo + hi) / 2.0; }
bool   IsPremium(double price, double lo, double hi)
{ return price > Equilibrium(lo, hi); }
bool   IsDiscount(double price, double lo, double hi)
{ return price < Equilibrium(lo, hi); }
// ICT: look for longs in Discount, shorts in Premium
```

### Liquidity Sweep

```mql5
// Bull sweep: price briefly dips below a known swing low then closes above it
bool IsBullSweep(const double &low[], const double &close[], int i, double swingLow)
{
   if(i < 1) return false;
   return low[i] < swingLow && close[i] > swingLow;
}
bool IsBearSweep(const double &high[], const double &close[], int i, double swingHigh)
{
   if(i < 1) return false;
   return high[i] > swingHigh && close[i] < swingHigh;
}
```

### Drawing FVG / OB zones on chart

```mql5
// Draw a zone rectangle (call from indicator OnCalculate or EA OnTick)
// name must be unique — embed bar time and type
void DrawZone(const string prefix, datetime t1, datetime t2,
              double lo, double hi, color col, int alpha=60)
{
   string name = prefix + TimeToString(t1, TIME_DATE|TIME_MINUTES);
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, hi, t2, lo);
   ObjectSetInteger(0, name, OBJPROP_COLOR,   col);
   ObjectSetInteger(0, name, OBJPROP_FILL,    true);
   ObjectSetInteger(0, name, OBJPROP_BACK,    true);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,   1);
   // No native alpha in chart objects — simulate with a lighter color shade
}
// Remove: ObjectsDeleteAll(0, prefix)  in OnDeinit
```

### Integration checklist for ICT indicators
- Swing detection requires a lookback window on BOTH sides → signal is confirmed `N` bars after the swing bar. Set `PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, InpSwingN)` to hide warm-up cells.
- BOS/ChoCh signals placed at `rates_total-2` (last closed bar) are non-repainting. Never write to index `rates_total-1` in final signal buffers.
- Store the latest swing high/low prices and their bar indices in STATE (not recomputed every tick) — recompute only when a new bar forms.
- OB "mitigation" (invalidation when price enters and closes inside the zone) requires tracking zone state across bars: use a `CArrayObj` list of active zones (advanced.md §1).
