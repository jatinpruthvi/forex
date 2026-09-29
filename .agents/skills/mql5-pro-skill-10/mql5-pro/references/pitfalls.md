# MQL5 Pitfalls, Errors, Tester, Performance, Code Economy

## Contents
1. Top compile-time traps
2. Top runtime traps
3. Runtime error codes worth memorizing
4. Strategy Tester / optimization pitfalls
5. OnTester custom criteria
6. Performance techniques
7. Code-shortening and structuring techniques
8. MQL4 contamination scan + conversion table
9. WebRequest, files, and sandbox rules

## 1. Top compile-time traps

- **`try/catch` does not exist.** Generated code containing it is invalid. Replace with return-value checks + `GetLastError()`.
- **Method hiding (build 5260+)**: same-name method in derived class hides ALL base overloads. Fix: `using CBase::Method;` in the derived class, or rename. Watch the compiler warning "call resolves to ... due to new rules of method hiding" — it means a silent behavior change, not just style.
- **Struct self-assignment**: `this = value;` inside struct operators no longer compiles. Use composition or per-field copy.
- **`input` is const**: `InpLots = 0.1;` in code is an error. Copy: `double g_lots; int OnInit(){ g_lots = InpLots; ... }`.
- **Implicit enum↔int**: requires explicit cast in many contexts: `(ENUM_TIMEFRAMES)tfInt`, `(int)PositionGetInteger(...)` (returns long).
- **Array parameters need `&`**: `void f(double &arr[])`. Returning arrays: fill a reference parameter; functions cannot return arrays.
- **String in switch**: not allowed; switch works on integral types only.
- **`#property strict` is MQL4-only**; MQL5 is always strict. Including it is harmless but signals converted-not-rewritten code.
- **Datetime literals**: `D'2026.01.30 00:00'`; arithmetic is in seconds.
- Object pointers: `CObj obj;` (auto) vs `CObj *p = new CObj();` — calling a method on a NULL/invalid pointer is a runtime crash; guard with `CheckPointer`.
- **`StringTrimLeft` / `StringTrimRight` return `int`, not string.** Both functions modify their argument IN-PLACE and return the count of characters removed. Assigning the return value to a string gives a number string, not the trimmed text:
```mql5
// WRONG — assigns the int "3" (chars removed), not the trimmed text
string clean = StringTrimLeft(rawLine);

// CORRECT — modify in place; discard the return value
string line = rawLine;
StringTrimLeft(line);
StringTrimRight(line);
```
- **`StringTrimLeft/Right` strip only ASCII whitespace** (space 0x20, tab 0x09, CR 0x0D, LF 0x0A). They do NOT strip the UTF-8 BOM (U+FEFF) that appears as the first character of UTF-8 files opened by some editors. Strip it manually after trimming:
```mql5
if(StringLen(line) > 0 && StringGetCharacter(line, 0) == 0xFEFF)
   line = StringSubstr(line, 1);
```

## 2. Top runtime traps

- **Order spam**: trading logic on raw ticks without new-bar gating + open-position check. Backtest "Open prices only" hides it; live exposes it. Always gate.
- **Handle churn**: `iMA(...)` inside OnTick/OnCalculate → error 4806 "indicator data not found" after handle table fills. Handles in OnInit only.
- **Unchecked Copy***: `CopyBuffer/CopyRates/CopyTime` can return -1 or fewer elements (history loading). Using the array anyway → array out of range (critical, EA removed from chart). Always compare returned count.
- **Series confusion**: reading `close[0]` expecting newest while the array is non-series (default in OnCalculate). Establish convention per §indicators.md.
- **Double equality**: `if(price == level)` virtually never true. Use `MathAbs(a-b) < tolerance`.
- **Division by zero**: tick size, point, ATR value can be 0 at startup — guard every divisor.
- **`TimeCurrent()` vs `TimeLocal()` vs `TimeTradeServer()`**: TimeCurrent = last known server tick time — it advances ONLY when a tick arrives, so it stalls on weekends, in dead markets, and between ticks. Any elapsed-time/throttle math built on it (`if(TimeCurrent()-last < N)`) freezes exactly when ticks are sparse — including inside `OnTimer`, which fires on the real clock independent of ticks, so reading TimeCurrent there reintroduces the freeze. For real elapsed intervals use the monotonic millisecond counters `GetTickCount()`/`GetTickCount64()` (immune to ticks and to manual clock changes; `GetTickCount` wraps every ~49.7 days but `uint` subtraction stays correct across one wrap, `GetTickCount64` never wraps). Use `TimeLocal` only for wall-clock date/time, and reserve `TimeCurrent` for "time of the last quote" semantics.
- **Magic missing on SL/TP deals** (broker-side execution): filter exit deals by `DEAL_POSITION_ID`, not magic (details in trading.md §10).
- **Sleep in indicators**: ignored/forbidden; in EAs Sleep blocks the whole EA thread including ChartEvents. Use OnTimer state machines.
- **GlobalVariables of terminal** (`GlobalVariableSet`) are floats-only, shared across all charts, persist 4 weeks; in the tester they live in a sandbox per pass. Not a config store — use files for structured data.
- **Comment()/Print() flooding** in OnTick degrades performance massively in live and tester. Rate-limit logs.
- **Object updates without ChartRedraw()** appear frozen.
- **Uninitialized MqlTradeRequest**: missing ZeroMemory → garbage fields → random 10013. Always ZeroMemory both structs.
- **ArrayResize per tick**: allocating/resizing work arrays inside OnTick/OnCalculate thrashes memory. Declare reusable arrays globally (or in STATE), size once, refill in place; if growth is unavoidable use the reserve parameter `ArrayResize(arr, n, 1024)`.
- **Alert() habits**: Alert pops a modal-style window per call — never per tick; it is suppressed in optimization but still pollutes visual/live runs. Gate alerts behind a state change (signal flipped) and prefer `PrintFormat` + push `SendNotification` for unattended EAs.
- **History depth assumption**: "find my last closed deal" logic fails silently when the requested range exceeds loaded history (terminal Max-bars / server depth). Bound `HistorySelect` to a realistic window, and warn in OnInit when the strategy needs more history than `Bars(_Symbol,_Period)` provides.
- **Trade cooldown**: position-count checks alone don't stop rapid open→close→open loops (SL hit then instant re-entry on the same bar). Store the last action time/bar in STATE and require N seconds or a new bar before re-entering.

## 3. Runtime error codes worth memorizing

| Code | Meaning | Typical fix |
|---|---|---|
| 4101–4109 | chart errors (wrong chart id, etc.) | validate chart id, guard tester |
| 4203/4204 | unknown object type/name | prefix discipline, ObjectFind first |
| 4301/4302 | unknown symbol / not selected | SymbolSelect(s, true) before use |
| 4401–4407 | history not found/not synchronized | retry pattern, check returned counts |
| 4756 | trade request send failed | inspect retcode in MqlTradeResult |
| 4806 | indicator data not found | handle in OnInit; check BarsCalculated |
| 4807 | wrong indicator handle | handle lifetime bug; INVALID_HANDLE check |
| 5002–5008 | file errors (wrong name, too many open, cannot open) | FILE_COMMON flag, close handles |
| 5203 | WebRequest URL not allowed | add URL in Tools→Options→Expert Advisors |

`_LastError` resets only via `ResetLastError()` — call it before an operation you intend to diagnose, else you read a stale code.

## 4. Strategy Tester / optimization pitfalls

- **No chart services in optimization**: ObjectCreate, ChartIndicatorGet, Comment are no-ops (non-visual). Read signals via handles only; guard UI with `if(!MQLInfoInteger(MQL_OPTIMIZATION))`.
- **WebRequest forbidden in tester** entirely; Sleep is skipped (virtual time); DLL calls disabled in Cloud agents; FILE_COMMON is shared with agents — regular files live in a per-agent sandbox and vanish.
- **Modeling modes**: "Every tick based on real ticks" = highest fidelity; "Open prices only" valid ONLY for strictly new-bar EAs with no intra-bar SL/TP logic dependence (SL/TP still emulated, but trailing per tick is distorted). 1-minute OHLC is the practical default for bar-close strategies.
- **Visual vs non-visual discrepancies** usually mean incorrect buffer updates / reading the forming bar — re-test signal indices.
- **"Run single backtest" from optimization results** may not transfer all inputs — verify the Inputs tab before trusting a reproduction.
- **Custom symbols / different servers**: prev_calculated edge case rates_total=1 — guard `rates_total < prev_calculated`.
- **Agent CPU**: heavy `Print` and file writes dominate runtime; silence logs for optimization via input flag.
- **TesterStop()** ends a pass early (e.g., max drawdown breached) — saves optimization hours. `TesterWithdrawal/TesterDeposit` simulate cash flows.
- Determinism: random seeds (`MathSrand`) and TimeLocal-based logic make passes non-reproducible.

**MQL5 Market automatic-validation checklist** (required to publish; also a quality bar for any EA):
- Zero critical runtime errors on EURUSD/GBPUSD/XAUUSD across H1/M30/D1/M1, multiple leverages and account currencies — no array-out-of-range, no zero divide (guard EVERY division), no invalid pointer.
- Volume validated against VOLUME_MIN/MAX/STEP, money via OrderCheck/OrderCalcMargin, stops via STOPS_LEVEL — before every send (the validator deliberately tests tiny deposits and exotic specs).
- No 10025: never send a modify that changes nothing.
- "There are no trading operations" failure = the EA never traded on some symbol/TF combo: caused by hardcoded symbol names, digit/point assumptions (3/5-digit only), fixed lot above the validator's margin, or TF-locked logic. The EA must place at least one trade on every tested combo or explicitly document supported symbols/TFs in code via `INIT_FAILED` with a clear message.
- No external dependencies: DLLs forbidden in Market products; WebRequest unavailable during validation.

## 5. OnTester custom criteria

```mql5
double OnTester()
{
   double profit  = TesterStatistics(STAT_PROFIT);
   double ddPct   = TesterStatistics(STAT_BALANCE_DDREL_PERCENT);
   double trades  = TesterStatistics(STAT_TRADES);
   double pf      = TesterStatistics(STAT_PROFIT_FACTOR);
   if(trades < 30) return 0;                       // ارفض العينات الصغيرة
   double score = profit * pf / MathMax(ddPct, 1); // مثال: ربح×عامل ربح ÷ سحب
   return score;
}
```
Select "Custom max" in tester settings. Genetic optimization sorts descending on this value; returning 0 culls the pass from breeding. Use it to encode multi-objective fitness (trade count floors, R² of equity curve via OnTester + frame functions).
`OnTesterInit/OnTesterPass/OnTesterDeinit` + `FrameAdd/FrameNext` enable collecting per-pass data into the terminal chart EA during optimization.

## 6. Performance techniques

- Incremental indicator math (running sums/recurrences) — biggest single win.
- `CopySeries` over `CopyRates` when only some fields are needed (no MqlRates struct unpacking).
- Cache `SymbolInfo*` values that don't change (digits, point, tick size) in OnInit; refresh volatile ones (stops level can change!) periodically, not per use.
- Strings: avoid concatenation in loops; build with `StringFormat` once; `StringSetLength`/preallocation for builders.
- Arrays: `ArraySetAsSeries` is O(1) (flag flip), `ArrayCopy` ranges instead of element loops, `ArrayResize(arr, n, reserve)` third parameter prevents repeated reallocation in growing buffers.
- `matrix`/`vector` types with built-in methods (MatMul, Std, Mean, CopyRates into matrix) are OpenBLAS-backed — orders of magnitude faster than hand loops for linear algebra/statistics.
- Profile with `ulong t0 = GetMicrosecondCount(); ...; PrintFormat("%.1f ms", (GetMicrosecondCount()-t0)/1000.0);` and the MetaEditor built-in profiler.
- OnTimer granularity: `EventSetTimer(seconds)` min 1s; `EventSetMillisecondTimer(ms)` for UI animation (≥10–16ms practical).
- ONNX models: run on GPU with CUDA flags (build 5570+) for ML inference; resources up to 1 GB.

## 7. Code-shortening and structuring techniques

- **Generic functions over duplicates**:
```mql5
bool OpenTrade(ENUM_ORDER_TYPE type, double lot, double slPts, double tpPts)
{
   bool isBuy = (type == ORDER_TYPE_BUY);
   double prc = SymbolInfoDouble(_Symbol, isBuy ? SYMBOL_ASK : SYMBOL_BID);
   int dir = isBuy ? 1 : -1;
   double sl = slPts>0 ? NormalizePrice(_Symbol, prc - dir*slPts*_Point) : 0;
   double tp = tpPts>0 ? NormalizePrice(_Symbol, prc + dir*tpPts*_Point) : 0;
   return isBuy ? trade.Buy(lot,_Symbol,0,sl,tp) : trade.Sell(lot,_Symbol,0,sl,tp);
}
```
The `dir = ±1` trick collapses every buy/sell duplication (SL math, trailing, breakeven) into one path.
- **Templates** for type-generic utilities:
```mql5
template<typename T>
T Clamp(T v, T lo, T hi) { return v<lo ? lo : (v>hi ? hi : v); }
```
- **Function pointers (typedef)** for pluggable strategies/filters:
```mql5
typedef bool(*TSignalFn)(int shift);
bool RunIf(TSignalFn fn, int shift) { return fn != NULL && fn(shift); }
```
- **Macros with parameters** for boilerplate (use sparingly, only proven idioms):
```mql5
#define CHECKED(call) if(!(call)) { Print(#call, " failed err=", GetLastError()); return false; }
```
- **input group + enums** instead of magic int inputs:
```mql5
input group "=== إدارة المخاطر ==="
enum ENUM_LOT_MODE { LOT_FIXED, LOT_RISK_PCT, LOT_PER_BALANCE };
input ENUM_LOT_MODE InpLotMode = LOT_RISK_PCT;  // وضع حساب اللوت
```
The comment after an input becomes its display name; enum member comments (`LOT_FIXED, // ثابت`) become dropdown labels — free localized UI.
- **.mqh modularization**: one concern per include (Signals.mqh, Risk.mqh, Panel.mqh, Trade.mqh); the .mq5 file holds only inputs + event handlers + wiring. All project includes live in the project folder and are referenced with quoted relative paths (`#include "Signals.mqh"`) — `<...>` only for the standard library, so the folder stays portable (full rule in SKILL.md).
- **Single STATE struct** instead of scattered globals — serializable in one FileWriteStruct for persistence.
- **Centralized logging** — one function, every error message uniform and contextual; no scattered Print calls:
```mql5
void LogError(const string context, const int code = -1)
{
   PrintFormat("[%s] %s | err=%d | %s", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
               context, code >= 0 ? code : GetLastError(), _Symbol);
   ResetLastError();
}
```
Severity policy: recoverable errors → log + retry/skip; fatal config errors in OnInit → `return INIT_FAILED` (never ExpertRemove there — INIT_FAILED is the correct channel); unrecoverable runtime corruption (e.g. license check, destroyed state) → log + `ExpertRemove()`.
- **#include vs #import**: `#include` pastes MQL5 source (.mqh) at compile time — the normal mechanism; `#import "lib.ex5"`/`#import "x.dll"` binds to compiled exports at runtime (DLLs need user permission and break portability/tester-cloud — avoid unless unavoidable, and document the exact version).
- Resource embedding for single-file delivery: `#resource "\\Indicators\\Helper.ex5"`, `#resource "img.bmp" as bitmap img[]`.

## 8. MQL4 contamination scan + conversion table

**Mandatory pre-delivery scan.** Before presenting ANY code, search it for every token in the left column. One hit = that section is MQL4-contaminated and must be rewritten from the MQL5 model (the full forbidden-token table is in SKILL.md). Fast scan list:

```
start( init( deinit( IndicatorCounted RefreshRates MarketInfo
Bid Ask Close[ Open[ High[ Low[ Time[ Volume[
OrderSelect OrderClose OrderModify OrderDelete OrderTicket OrderLots
OrderType( OrderProfit OrderOpenPrice OrderStopLoss OrderTakeProfit
OP_BUY OP_SELL OP_BUYSTOP OP_SELLSTOP OP_BUYLIMIT OP_SELLLIMIT
SetIndexStyle SetIndexArrow SetIndexLabel SetIndexDrawBegin
WindowFind WindowRedraw ObjectSet( ObjectGet( #property strict
MODE_MINLOT MODE_MAXLOT MODE_TICKVALUE MODE_SPREAD MODE_STOPLEVEL
AccountBalance( AccountEquity( AccountFreeMargin(
iMA(...,...,...,...,...,...,shift_as_last_int_returning_double)
```
Subtle cases the token scan misses — verify by reading:
- An `OrderSend` with 7+ positional arguments returning an int ticket → MQL4 form.
- Indicator functions (`iRSI`, `iATR`, `iCustom`...) whose return value is used directly as a price/double → MQL4 form; MQL5 returns a handle.
- Loops over `OrdersTotal()` that treat entries as open POSITIONS → MQL4 model; in MQL5 OrdersTotal() = pending orders only.
- `Symbol()`/`Period()` are valid MQL5, but `Period()` returns ENUM_TIMEFRAMES — integer math on it (e.g., `Period()*60`) is an MQL4 habit; use `PeriodSeconds()`.

Conversion table (rewrite direction MQL4 → MQL5):

| MQL4 | MQL5 |
|---|---|
| `OrderSend(...)` 9-arg | MqlTradeRequest/OrderSend or CTrade |
| `OrderSelect(i, SELECT_BY_POS)` | `PositionGetTicket(i)` / `OrderGetTicket(i)` (orders=pending only) |
| `OrdersTotal()` (everything) | `PositionsTotal()` + `OrdersTotal()` + history |
| `OrderClose` | `trade.PositionClose(ticket)` |
| `iMA(...,shift)` returns value | returns HANDLE; value via CopyBuffer |
| `Close[i] / Time[i]` | `iClose(_Symbol,_Period,i)` or copied arrays |
| `Bars` | `Bars(_Symbol,_Period)` or rates_total |
| `Point / Digits` | `_Point / _Digits` |
| `MarketInfo(s, MODE_X)` | `SymbolInfoDouble/Integer(s, SYMBOL_X)` |
| `RefreshRates()` | not needed; SymbolInfoTick gives fresh quotes |
| `IndicatorCounted()` | prev_calculated |
| `start()/init()/deinit()` | OnTick(or OnCalculate)/OnInit/OnDeinit |
| `AccountBalance()` | `AccountInfoDouble(ACCOUNT_BALANCE)` |
| string as char array ops | StringGetCharacter/StringSetCharacter (ushort) |

Behavioral: MQL4 order tickets ≠ MQL5 position lifecycle; rewrite trade management around positions/deals, do not transliterate.

## 9. WebRequest, files, and sandbox rules

- WebRequest: EA/script/service only (NOT indicators), URL must be whitelisted in terminal options (instruct the user), blocking call — run from OnTimer state machine, never OnTick hot path. Two forms; the array form gives headers control. Disabled in tester.
- Files: sandboxed to `MQL5\Files` (per terminal) or shared `FILE_COMMON` (Terminal\Common\Files — also visible to tester agents). Outside access only via DLLs (requires user permission) — avoid.
- File I/O pattern: `int h = FileOpen(name, FILE_WRITE|FILE_TXT|FILE_ANSI); ... FileClose(h);` always close in all branches; UTF-8 Arabic: FILE_TXT|FILE_ANSI with CP_UTF8 codepage parameter `FileOpen(name, FILE_WRITE|FILE_TXT, 0, CP_UTF8)`.
- Settings persistence: FileWriteStruct/FileReadStruct on the STATE struct, or key=value text for human-editable configs.
- Network alternatives inside MQL5: Socket* functions (raw TCP/TLS) for push feeds — EA/service only, same whitelist.

## 10. MT5 Log Autonomous Reading (agentic / Claude Code workflow)

MT5 writes `Print()`/`PrintFormat()` output and terminal journal events to a single UTF-16 LE file at:
```
{Terminal Data Path}\MQL5\Logs\YYYYMMDD.log
```
`Terminal Data Path` = `TerminalInfoString(TERMINAL_DATA_PATH)` from inside MQL5. From outside (agent):
```
%APPDATA%\MetaQuotes\Terminal\<GUID>\MQL5\Logs\YYYYMMDD.log
```
Multiple MT5 installations produce multiple `<GUID>` directories. Log files rotate daily.

**Get the path from within MQL5 (print it once on startup):**
```mql5
void PrintLogPath()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   string date = StringFormat("%04d%02d%02d", dt.year, dt.mon, dt.day);
   string path = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Logs\\" + date + ".log";
   Print("LOG_PATH=", path);   // Claude Code reads this from the log itself via the method below
}
```

**Python — read today's MT5 log (UTF-16 LE, all terminals):**
```python
import os, glob
from datetime import datetime

def read_mt5_logs(filter_str=""):
    date = datetime.now().strftime('%Y%m%d')
    pattern = os.path.join(os.environ['APPDATA'],
                           'MetaQuotes', 'Terminal', '*',
                           'MQL5', 'Logs', f'{date}.log')
    results = []
    for path in glob.glob(pattern):
        with open(path, 'rb') as f:
            raw = f.read()
        # strip BOM if present
        content = raw[2:].decode('utf-16-le') if raw[:2] == b'\xff\xfe' \
                  else raw.decode('utf-16-le', errors='replace')
        lines = [ln for ln in content.splitlines()
                 if not filter_str or filter_str.lower() in ln.lower()]
        results.extend(lines)
    return results

# Usage:
for line in read_mt5_logs("error"):   # or "" for everything
    print(line)
```

**PowerShell (Windows):**
```powershell
$date = Get-Date -Format "yyyyMMdd"
Get-ChildItem "$env:APPDATA\MetaQuotes\Terminal\*\MQL5\Logs\$date.log" |
    ForEach-Object { Get-Content $_ -Encoding Unicode } |
    Where-Object { $_ -match "(error|expert|Print|0)" }
```

**Grep pattern reference (most useful filters):**
```
error      — runtime / compile errors
0;         — lines ending in error code 0 (success) from OrderSend/CTrade
INIT_FAILED — EA init failures
expert     — EA name in log lines
Print      — raw Print() output marker
```

**Key encoding facts:**
- UTF-16 LE; some terminals write without BOM — always strip conditionally.
- Each line: `YYYY.MM.DD HH:MM:SS.mmm\t<source>\t<text>` (tab-separated fields).
- Log is locked by the terminal while running — open for reading only (`'rb'`), not writing.
- On date rollover the file path changes; reload it at midnight if running continuously.

**Agentic debug workflow:**
1. EA prints `LOG_PATH=<path>` in `OnInit`.
2. Claude Code reads the log from that path after each compile/run cycle.
3. Filter by the EA name or a unique tag (e.g. `[MY_EA]` prefix on all `PrintFormat` calls) to isolate that EA's output from terminal noise.
4. Check `BarsCalculated(handle)` output and `INIT_FAILED` lines before looking at signal logic.
