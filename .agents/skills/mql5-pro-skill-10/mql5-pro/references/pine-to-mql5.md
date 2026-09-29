# Pine Script (v4–v6) → MQL5 Conversion — Production Reference

Goal: convert TradingView indicators/strategies to MQL5 with **1:1 mathematical match**, verified on chart. The two platforms differ in execution model, indexing, null semantics, and built-in formulas — every one of these differences is a documented source of silent value divergence. Follow the mapping rules here exactly.

## Contents
1. Execution-model mapping (the golden rule)
2. Bar indexing translation
3. `na` semantics → EMPTY_VALUE
4. `var` / `varip` / `:=` state translation
5. `ta.*` function mapping table (with formula mismatches flagged)
6. `request.security` → multi-timeframe without repainting
7. Plots, drawings, tables → buffers and objects
8. `strategy.*` → EA (CTrade)
9. Time, sessions, timezone re-anchoring
10. Verification protocol (mandatory)
11. Conversion bug checklist

---

## 1. Execution-model mapping (the golden rule)

Pine executes the **entire script body once per bar**, walking history left→right, then once per tick on the realtime bar. The exact MQL5 equivalent is the `OnCalculate` loop:

```mql5
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[], const double &high[],
                const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
{
   int start = MathMax(prev_calculated - 1, MIN_BARS_REQUIRED); // MIN_BARS = longest lookback
   for(int i = start; i < rates_total; i++)
   {
      // === Pine script body translates HERE, bar index = i ===
   }
   return rates_total;
}
```

- One pass of the loop body at index `i` == one execution of the Pine script on that bar.
- `prev_calculated` handling replaces Pine's automatic incremental execution. Guard the reset case: `if(rates_total <= prev_calculated && prev_calculated > 0) start = prev_calculated - 1;` and full recompute when `prev_calculated == 0`.
- The **realtime (forming) bar** is `i == rates_total-1`, revisited on every tick — identical to Pine's realtime bar. Pine's history/realtime asymmetry (history sees only bar close) is why `barstate.isconfirmed`-gated logic must translate to computing on `i-1` (the last **closed** bar) or new-bar gating in an EA.

Strategies (`strategy()`) convert to an EA (`OnTick`), not an indicator — see §8. Convert the indicator math first, verify it, then wrap the EA around it.

## 2. Bar indexing translation

Pine: `close` = current bar, `close[1]` = one bar back (history-reference operator).
MQL5 `OnCalculate` arrays arrive **non-series**: index 0 = oldest, `rates_total-1` = newest.

**Fixed convention for all conversions (do not mix):** keep arrays non-series.

| Pine | MQL5 (inside loop at `i`) |
|---|---|
| `close` | `close[i]` |
| `close[1]` | `close[i-1]` |
| `x[n]` | `x[i-n]` — guard `i-n >= 0` |
| `bar_index` | `i` |
| `last_bar_index` | `rates_total-1` |

- **Never** call `ArraySetAsSeries(true)` on OnCalculate input arrays in this convention — flipping direction mid-file is the #1 cause of reversed/garbage output in conversions.
- If the code must also read other-symbol/TF data via `Copy*`, those local arrays default non-series too — consistent. If any legacy snippet requires series arrays, isolate it in its own function and convert indices at the boundary.
- Own indicator buffers registered with `SetIndexBuffer` follow the same non-series layout by default; write `buf[i]`.

## 3. `na` semantics → EMPTY_VALUE

Pine `na` is a first-class null propagating through math. MQL5 has no null double; the convention is `EMPTY_VALUE` (DBL_MAX) in plot buffers.

```mql5
#property indicator_buffers 2
// ...
PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE); // gaps not drawn
PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, MIN_BARS_REQUIRED); // replaces leading na's
```

| Pine | MQL5 |
|---|---|
| `na` (assign) | `buf[i] = EMPTY_VALUE;` |
| `na(x)` (test) | `x == EMPTY_VALUE \|\| !MathIsValidNumber(x)` |
| `nz(x)` | `(x == EMPTY_VALUE \|\| !MathIsValidNumber(x)) ? 0 : x` |
| `nz(x, y)` | same with `y` |
| `fixnan(x)` | carry-forward: keep last valid value in a state variable |

Warning: arithmetic on EMPTY_VALUE doesn't propagate like `na` — it produces huge garbage numbers silently. Every expression whose Pine original could receive `na` needs an explicit validity check before the math, not after.

## 4. `var` / `varip` / `:=` state translation

| Pine | Meaning | MQL5 translation |
|---|---|---|
| `x = expr` | recomputed every bar | local inside the loop |
| `var x = init` | initialized once, value **persists across bars** | dedicated state — see below |
| `varip x = init` | persists across **ticks** intra-bar too | global/static variable (natural MQL5 behavior) — but output becomes non-reproducible on reload, exactly like Pine varip repaint |
| `x := expr` | reassignment | plain `=` |

`var` is the trap. A global MQL5 variable persists across **calls**, not across **bars in a single pass** — during full recalculation the loop walks all bars in one call, so a global works; but on terminal restart/timeframe switch recalculation restarts from bar 0 and the state rebuilds — which matches Pine. What breaks it: reading the state at `prev_calculated` resume without having stored per-bar history. Rule: **any `var` whose value is later read with `[n]` history-offset must become a full buffer** (`INDICATOR_CALCULATIONS` buffer), not a scalar. A `var` only ever read at current bar can stay a scalar global updated inside the loop.

## 5. `ta.*` mapping table

⚠ rows marked **≠** have a **formula mismatch** with the nearest MQL5 built-in — implement manually or values will not match TradingView.

| Pine | MQL5 | Notes |
|---|---|---|
| `ta.sma(src,n)` | `iMA(..., MODE_SMA, ...)` or manual loop | exact match |
| `ta.ema(src,n)` | `iMA(..., MODE_EMA, ...)` | exact; seed = SMA of first n in both |
| `ta.rma(src,n)` | `iMA(..., MODE_SMMA, ...)` | RMA = Wilder = SMMA. exact |
| `ta.wma(src,n)` | `iMA(..., MODE_LWMA, ...)` | exact |
| `ta.vwma(src,n)` | manual: `Σ(src·vol)/Σvol` over n | no built-in |
| `ta.rsi(src,n)` | `iRSI` | both RMA-based. exact on close; custom `src` → manual |
| `ta.atr(n)` | `iATR` | both RMA-based. exact |
| `ta.macd(...)` | **≠** manual | Pine signal = **EMA**; `iMACD` signal = **SMA**. Always implement MACD manually: EMA(fast)−EMA(slow), signal = EMA(macd, 9) |
| `ta.stoch` | **≠** check smoothing | Pine %K smoothing arguments differ from iStochastic defaults; map k, k-smooth, d explicitly |
| `ta.stdev(src,n)` | `iStdDev` / manual | Pine uses population (biased) stdev; iStdDev matches. exact |
| `ta.bb` | `iBands` | verify deviation and shift args |
| `ta.supertrend` | manual | no built-in; ATR(RMA) based |
| `ta.crossover(a,b)` | `a[i] > b[i] && a[i-1] <= b[i-1]` | |
| `ta.crossunder(a,b)` | `a[i] < b[i] && a[i-1] >= b[i-1]` | |
| `ta.cross(a,b)` | either of the above | |
| `ta.highest(src,n)` / `ta.lowest` | loop over `[i-n+1..i]`, or `high[ArrayMaximum(high, i-n+1, n)]` | includes current bar, window = n bars ending at i |
| `ta.highestbars(n)` | offset of that max relative to i (negative in Pine) | |
| `ta.change(x)` | `x[i] - x[i-1]` | `ta.change(x,n)` → `x[i]-x[i-n]` |
| `ta.mom(src,n)` | `src[i] - src[i-n]` | |
| `ta.roc` | `100*(src[i]-src[i-n])/src[i-n]` | guard zero |
| `ta.cum(x)` | running-sum state buffer | needs full buffer (see §4 rule) |
| `ta.barssince(cond)` | backward loop from i until cond true; cap search depth | store as INT state buffer if used with `[]` |
| `ta.valuewhen(cond, src, k)` | backward loop counting cond occurrences, return src at the (k+1)-th | expensive — cache per bar |
| `ta.pivothigh(l, r)` | at bar `i`, check center `i-r` is strict max of window `[i-l-r .. i]` | confirmed r bars late — identical delay to Pine; value belongs to bar `i-r` |
| `ta.vwap` | session-anchored cumulative `Σ(hlc3·vol)/Σvol`, reset at session start (§9) | |
| `math.*`, `math.abs/max/min/pow/sqrt/log` | `MathAbs/MathMax/MathMin/MathPow/MathSqrt/MathLog` | |
| `math.round(x, p)` | `NormalizeDouble(x, p)` | display only — never for order prices (trading.md §5) |
| `int` division | Pine promotes to float; MQL5 `int/int` **truncates** | cast: `(double)a / b` |

Source series: `hl2 = (high[i]+low[i])/2`, `hlc3`, `ohlc4`, `hlcc4` — compute inline.

## 6. `request.security` → MTF without repainting

Pine `request.security(sym, tf, expr)` has two repaint regimes; MQL5 must reproduce the **non-repainting** one:

| Pine pattern | Meaning | MQL5 |
|---|---|---|
| `security(sym, tf, close[1], lookahead=on)` or `close[1]` with `barmerge.lookahead_on` | last **closed** HTF bar — non-repainting | read HTF handle/`Copy*` at HTF shift **1** |
| `security(sym, tf, close)` (default) | forming HTF bar on realtime, final value on history — **repaints** | HTF shift 0 — reproduce only if the original explicitly wanted live values, and document the repaint |

Implementation:
```mql5
int gHtfHandle;                       // OnInit: iRSI(sym, PERIOD_H1, ...) — handles in OnInit ONLY
// inside loop / OnTick:
int htfShift = iBarShift(sym, PERIOD_H1, time[i]);      // map current-TF bar → HTF bar
double v[1];
if(CopyBuffer(gHtfHandle, 0, htfShift + 1, 1, v) == 1)  // +1 = closed HTF bar (non-repaint)
   htfValue = v[0];
```
- `iBarShift` mapping per bar is mandatory on history — using a fixed shift only works on the realtime bar.
- HTF data may not be synchronized on first call: check `BarsCalculated(gHtfHandle) > 0` and returned counts; return `prev_calculated` to retry next tick (pitfalls.md §2/§3).
- Lower-TF requests (`request.security_lower_tf`) have no clean indicator equivalent — use `CopyRates` of the lower TF and aggregate manually.

## 7. Plots, drawings, tables → buffers and objects

| Pine | MQL5 |
|---|---|
| `plot(x)` | indicator buffer + `#property indicator_typeN/colorN/widthN`, `DRAW_LINE` |
| `plot(style=columns/histogram)` | `DRAW_HISTOGRAM` (from zero) / `DRAW_HISTOGRAM2` (two buffers) |
| `plotshape/plotchar` | buffer with `DRAW_ARROW` + `PlotIndexSetInteger(k, PLOT_ARROW, wingdingCode)`; `EMPTY_VALUE` where no shape |
| `fill(p1, p2, color)` | `DRAW_FILLING` (2 buffers, one plot) |
| `hline(y)` | `#property indicator_levelN` or OBJ_HLINE |
| `bgcolor(c)` | OBJ_RECTANGLE per zone (background=true) — no per-bar alpha shading on chart objects |
| `barcolor` | `DRAW_COLOR_CANDLES` (5 buffers: OHLC + color index) |
| `line.new / box.new / label.new` | OBJ_TREND / OBJ_RECTANGLE / OBJ_TEXT with strict name-prefix discipline + cleanup in OnDeinit (gui.md) |
| `label.delete(l[1])` idiom (one moving label) | one fixed object name, updated in place |
| `table.new` | Comment() for trivial cases; CCanvas panel for real tables (gui.md) |
| `color.new(c, transp)` | plots/objects have no alpha — nearest solid color; alpha only inside CCanvas via `ColorToARGB` |
| `alert() / alertcondition` | signal-edge-gated `Alert`/`SendNotification` (pitfalls.md §2 Alert rules) |

Plot count limit: 8 colors/styles per plot index in properties; total buffers must be registered `SetIndexBuffer` in order, calculations buffers last with `INDICATOR_CALCULATIONS`.

## 8. `strategy.*` → EA (CTrade)

Convert in two stages — indicator math verified first (§10), then the EA shell. Mapping:

| Pine | MQL5 |
|---|---|
| `strategy.entry("id", long)` | `CTrade::Buy/Sell` with magic; "id" → comment/magic scheme |
| `strategy.close / close_all` | close by position ticket loop (trading.md §8) |
| `strategy.exit(sl, tp, trail_*)` | SL/TP on the order + trailing pattern (trading.md §9); validate stops (trading.md §6) |
| `pyramiding=N` | count open positions with same magic before entry |
| `default_qty_type=percent_of_equity` | risk-based sizing (trading.md §7) — NOT equity%·price; replicate Pine's formula only if matching backtests is the goal |
| `process_orders_on_close=true` | new-bar gate: act once per bar on closed-bar signals — this is the default correct EA pattern |
| `process_orders_on_close=false` | intra-bar execution on ticks — document the divergence; Pine fills at next bar open on history regardless |
| `calc_on_every_tick` | OnTick without new-bar gate |
| `strategy.position_size` | `PositionSelect` + volume, signed by type |
| `commission/slippage inputs` | Strategy Tester settings, not code |

Execution divergence is structural: Pine strategies on history fill at **next bar open** after a close signal; MT5 tester fills on the tick following the signal. Expect equity-curve differences even with identical signals; profit-factor variance up to ~5% is normal — beyond that, suspect a logic bug, not "platform difference".

## 9. Time, sessions, timezone re-anchoring

- Pine `time` = bar open in **milliseconds** Unix; MQL5 `datetime` = **seconds**. Divide/multiply by 1000 at any boundary.
- Pine timestamps are exchange/chart timezone-aware; MT5 `time[]` is **broker server time** (usually EET/EEST, broker-specific). Every session constant ("0930-1600", `time("D", session)`) must be re-anchored: take the intended market timezone, compute its offset to the broker server (input parameter — do not hardcode; DST shifts twice a year).
- `dayofweek`, `hour`, `minute` → `MqlDateTime` via `TimeToStruct(time[i], dt)`.
- Session-anchored resets (VWAP, daily levels): detect new session by comparing `iTime(sym, PERIOD_D1, ...)` or day-of-year change in server time adjusted by the session offset input.

## 10. Verification protocol (mandatory)

Never declare a conversion done without value verification:
1. Convert the indicator math only. Compile, attach to the same symbol/TF as the TradingView chart.
2. Dump values: `FileWrite` time + all buffer values for the last 200 closed bars.
3. Compare against TradingView values (data window / exported chart data) on **closed bars only**.
4. Tolerance: ≤ 1 tick or ≤ 0.01% relative — differences beyond that on closed bars = formula mismatch (§5 table, check the ≠ rows first) or indexing bug (§2), never acceptable "platform difference".
5. Only then convert strategy logic (§8), and compare **signal bars** (entry/exit bar indices), not equity curves.
6. Data source caveat: TradingView and the broker feed differ (especially XAUUSD/indices — different liquidity providers, sessions, Sunday candles). Verify on a major FX pair first to isolate code errors from feed differences, then assess feed-driven divergence on the target symbol separately.

## 11. Conversion bug checklist

Run before delivery — each item is a documented recurring conversion failure:
- [ ] MACD signal implemented as EMA, not iMACD (≠ SMA signal)
- [ ] RSI/ATR use RMA (SMMA), not EMA/SMA
- [ ] No `ArraySetAsSeries(true)` on OnCalculate inputs; all indexing `i-n`
- [ ] Every `x[n]` access guarded `i-n >= 0`; `PLOT_DRAW_BEGIN` set
- [ ] `var` values read with history-offset promoted to full calculation buffers
- [ ] `request.security` reads closed HTF bar (shift+1) with `iBarShift` mapping
- [ ] All `na` paths use EMPTY_VALUE checks BEFORE arithmetic
- [ ] Integer division cast to double
- [ ] Session/time logic re-anchored to broker server time via input offset
- [ ] Signals evaluated on closed bar (`i-1` / new-bar gate) unless the original was explicitly intra-bar
- [ ] Handles created in OnInit only; `BarsCalculated` / returned-count checks on every Copy* (pitfalls.md)
- [ ] Values verified per §10 on closed bars
