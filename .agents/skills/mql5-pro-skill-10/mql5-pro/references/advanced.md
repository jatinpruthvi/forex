# MQL5 Advanced Patterns — Collections, Timers, Network, ONNX, Persistence, Multi-Symbol

## Contents
1. CObject/CArrayObj collections — managing sets of trades/zones/widgets
2. OnTimer state machine — the correct replacement for Sleep
3. WebRequest — complete working pattern
4. Sockets — push connections
5. ONNX machine-learning inference (build 5570+, CUDA)
6. Settings persistence — FileWriteStruct / key=value
7. Multi-symbol EA architecture
8. Position reversal (DEAL_ENTRY_INOUT) handling summary

## 1. CObject/CArrayObj collections

For grid/hedging EAs, zone managers, and widget lists, raw arrays of structs don't scale (no polymorphism, manual lifetime). Standard Library collections solve it:

```mql5
#include <Arrays\ArrayObj.mqh>

// كل عنصر يرث CObject — شرط الدخول في CArrayObj
class CGridLevel : public CObject
{
public:
   ulong  ticket;
   double entryPrice;
   double lot;
   int    level;
   CGridLevel(ulong t, double p, double l, int lv) : ticket(t), entryPrice(p), lot(l), level(lv) {}
   // فرز/بحث اختياري: التعليق على المقارنة بالسعر
   virtual int Compare(const CObject *node, const int mode=0) const override
   {
      const CGridLevel *o = (const CGridLevel*)node;   // التحويل الصريح إلزامي في MQL5
      return (entryPrice > o.entryPrice) - (entryPrice < o.entryPrice);
   }
};

CArrayObj g_grid;          // STATE — المالك الوحيد للعناصر

void GridAdd(ulong ticket, double price, double lot, int level)
{
   CGridLevel *gl = new CGridLevel(ticket, price, lot, level);
   if(!g_grid.Add(gl)) delete gl;            // فشل الإضافة = حرر فوراً
}

CGridLevel* GridFindByTicket(ulong ticket)
{
   for(int i = 0; i < g_grid.Total(); i++)
   {
      CGridLevel *gl = g_grid.At(i);
      if(gl != NULL && gl.ticket == ticket) return gl;
   }
   return NULL;
}

void GridRemoveByTicket(ulong ticket)
{
   for(int i = g_grid.Total() - 1; i >= 0; i--)
   {
      CGridLevel *gl = g_grid.At(i);
      if(gl != NULL && gl.ticket == ticket) { g_grid.Delete(i); return; } // Delete يحرر العنصر
   }
}

void OnDeinit(const int reason) { g_grid.Clear(); }   // Clear يحرر كل العناصر (FreeMode=true افتراضياً)
```
Rules:
- `FreeMode(true)` (default) = the array OWNS elements: `Delete/Clear/Shutdown` call `delete` for you. Set `FreeMode(false)` only when elements are shared — then YOU delete them.
- `At(i)` returns NULL past bounds — always NULL-check.
- Sorted use: `g_grid.Sort(0);` then `Search(&probe)` for O(log n) lookups (requires Compare).
- Related containers: `CArrayInt/CArrayLong/CArrayDouble/CArrayString` (value arrays with Add/Insert/Search), `CList` (linked list, cheap middle insertion).
- This replaces parallel arrays (`tickets[]`, `prices[]`, `lots[]`) — parallel arrays drift out of sync and are a defect.

## 2. OnTimer state machine — the correct replacement for Sleep

Sleep blocks the entire program thread (and is forbidden in indicators). Any "wait then act" logic becomes a state machine driven by OnTimer:

```mql5
enum ENUM_APP_STATE { ST_IDLE, ST_WAIT_DATA, ST_SEND_REQUEST, ST_WAIT_RESPONSE, ST_PROCESS };

// STATE
ENUM_APP_STATE g_appState   = ST_IDLE;
datetime       g_stateSince = 0;

// CONFIG
#define STATE_TIMEOUT_SEC  15

void SetState(ENUM_APP_STATE s) { g_appState = s; g_stateSince = TimeLocal(); }
bool StateTimedOut()            { return TimeLocal() - g_stateSince > STATE_TIMEOUT_SEC; }

int OnInit()
{
   EventSetMillisecondTimer(250);     // دورة الآلة — لا تستخدم EventSetTimer(0)
   SetState(ST_IDLE);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) { EventKillTimer(); }

void OnTimer()
{
   switch(g_appState)
   {
      case ST_IDLE:
         if(NeedCycle()) SetState(ST_WAIT_DATA);
         break;
      case ST_WAIT_DATA:
         if(DataReady())          SetState(ST_SEND_REQUEST);
         else if(StateTimedOut()) SetState(ST_IDLE);          // لا انتظار أبدي
         break;
      case ST_SEND_REQUEST:
         SetState(SendIt() ? ST_WAIT_RESPONSE : ST_IDLE);
         break;
      case ST_WAIT_RESPONSE:
         if(ResponseArrived())    SetState(ST_PROCESS);
         else if(StateTimedOut()) SetState(ST_IDLE);
         break;
      case ST_PROCESS:
         Process();
         SetState(ST_IDLE);
         break;
   }
}
```
- Every waiting state has a timeout exit — a state machine without timeouts deadlocks silently.
- OnTick stays pure trading logic; slow work (HTTP, file scans, heavy stats) lives entirely in this machine.
- The same pattern inside indicators handles deferred HTF data loading (indicators.md §6).

## 3. WebRequest — complete working pattern

EA/script/service only (never indicators), URL must be whitelisted: Tools → Options → Expert Advisors → "Allow WebRequest for listed URL" — instruct the user explicitly. Disabled in the Strategy Tester.

```mql5
// CONFIG
#define API_URL      "https://api.example.com/v1/quote"
#define HTTP_TIMEOUT 5000

bool HttpGetJson(const string url, string &outBody)
{
   char post[];                       // فارغ لطلب GET
   char result[];
   string resultHeaders;
   ResetLastError();
   int code = WebRequest("GET", url, "Content-Type: application/json\r\n",
                         HTTP_TIMEOUT, post, result, resultHeaders);
   if(code == -1)
   {
      int err = GetLastError();
      if(err == 4014 || err == 5203)
         Print("WebRequest blocked: add the URL in Tools > Options > Expert Advisors");
      else
         Print("WebRequest error: ", err);
      return false;
   }
   if(code != 200) { PrintFormat("HTTP %d", code); return false; }
   outBody = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
   return true;
}

bool HttpPostJson(const string url, const string json, string &outBody)
{
   char post[]; StringToCharArray(json, post, 0, StringLen(json), CP_UTF8); // بدون NUL الختامي
   char result[]; string hdrs;
   int code = WebRequest("POST", url, "Content-Type: application/json\r\n",
                         HTTP_TIMEOUT, post, result, hdrs);
   if(code != 200 && code != 201) return false;
   outBody = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
   return true;
}
```
- `StringToCharArray` appends a terminating 0 by default — pass count=StringLen to exclude it, or servers reject the body.
- WebRequest is BLOCKING: call it only from the OnTimer state machine (§2), never from OnTick.
- Telegram alert = HttpGetJson on `https://api.telegram.org/bot<TOKEN>/sendMessage?chat_id=<ID>&text=<urlencoded>` — encode text with custom UrlEncode (replace space→%20 etc.).

### JSON helpers — builder + extractor

No native JSON in MQL5. Use the helpers below for simple flat payloads; embed `JAson.mqh` (place inside project folder, quoted include) for nested objects and arrays.

```mql5
// Builder
string JsonStr(const string k, const string v)
   { return "\""+k+"\":\""+v+"\""; }
string JsonNum(const string k, double v, int d=5)
   { return "\""+k+"\":"+DoubleToString(v,d); }
string JsonBool(const string k, bool v)
   { return "\""+k+"\":"+(v?"true":"false"); }
string JsonObj(const string body) { return "{"+body+"}"; }
string JsonArr(const string body) { return "["+body+"]"; }

// Usage: JsonObj(JsonStr("sym",_Symbol)+","+JsonNum("bid",bid,5))
// → {"sym":"EURUSD","bid":1.08520}

// Extractor — string field: "key":"VALUE"
string JsonGetStr(const string json, const string key)
{
   string tag = "\""+key+"\":\"";
   int s = StringFind(json, tag);
   if(s < 0) return "";
   s += StringLen(tag);
   int e = StringFind(json, "\"", s);
   return e < 0 ? "" : StringSubstr(json, s, e-s);
}

// Extractor — numeric field: "key":NUMBER (no quotes)
double JsonGetNum(const string json, const string key)
{
   string tag = "\""+key+"\":";
   int s = StringFind(json, tag);
   if(s < 0) return 0;
   s += StringLen(tag);
   int e = s;
   while(e < StringLen(json))
   {
      ushort c = StringGetCharacter(json, e);
      if(c==',' || c=='}' || c==']') break;
      e++;
   }
   return StringToDouble(StringSubstr(json, s, e-s));
}

// URL-encode for query params / Telegram text
string UrlEncode(const string s)
{
   string out = "";
   for(int i = 0; i < StringLen(s); i++)
   {
      ushort c = StringGetCharacter(s, i);
      if((c>='A'&&c<='Z')||(c>='a'&&c<='z')||
         (c>='0'&&c<='9')||c=='-'||c=='_'||c=='.'||c=='~')
         out += ShortToString(c);
      else
         out += StringFormat("%%%02X", c);
   }
   return out;
}
```
Limitations of the extractors above: first occurrence only, no escaped-quote handling, string fields only for `JsonGetStr`. For arrays, nested objects, or repeated keys → use `JAson.mqh`.

## 4. Sockets — push connections

For streaming feeds (custom server, bridge) where polling is too slow. EA/script/service only, same URL whitelist (host without scheme):
```mql5
int s = SocketCreate();
if(s != INVALID_HANDLE && SocketConnect(s, "feed.example.com", 443, 3000))
{
   if(SocketTlsHandshake(s, "feed.example.com"))      // TLS عند المنفذ 443
   {
      string req = "GET /stream HTTP/1.1\r\nHost: feed.example.com\r\n\r\n";
      char out[]; StringToCharArray(req, out, 0, StringLen(req));
      SocketTlsSend(s, out, ArraySize(out));
      // القراءة داخل OnTimer: SocketIsReadable ثم SocketTlsRead — لا حلقة انتظار
   }
}
// SocketClose(s) في OnDeinit
```
Read inside the timer machine: `if(SocketIsReadable(s) > 0) SocketTlsRead/SocketRead` — never spin-wait.

## 5. ONNX machine-learning inference (build 5570+, CUDA)

Run trained models (price prediction, classification) natively:
```mql5
#resource "model.onnx" as uchar g_modelBytes[]     // حتى 1GB من build 5570

long g_onnx = INVALID_HANDLE;

int OnInit()
{
   g_onnx = OnnxCreateFromBuffer(g_modelBytes, ONNX_DEFAULT);   // أو ONNX_NO_CONVERSION
   if(g_onnx == INVALID_HANDLE) return INIT_FAILED;
   // أشكال الإدخال/الإخراج يجب أن تطابق تدريب النموذج
   const long inShape[]  = {1, 10, 1};
   const long outShape[] = {1, 1};
   if(!OnnxSetInputShape(g_onnx, 0, inShape))   return INIT_FAILED;
   if(!OnnxSetOutputShape(g_onnx, 0, outShape)) return INIT_FAILED;
   return INIT_SUCCEEDED;
}

bool Predict(const float &features[], float &outValue)
{
   float out[1];
   if(!OnnxRun(g_onnx, ONNX_NO_CONVERSION, features, out)) return false;
   outValue = out[0];
   return true;
}

void OnDeinit(const int reason) { if(g_onnx != INVALID_HANDLE) OnnxRelease(g_onnx); }
```
- Input dtype must match the model exactly (usually float32 → `float[]`, not double).
- Normalize features with the SAME scaler parameters used in training — bake means/stds into CONFIG.
- CUDA acceleration is automatic when the GPU supports it (build 5570+, permissions in platform settings); logging via ONNX_LOGLEVEL_* flags.
- Tester-compatible: inference runs in backtests (model bytes travel with the .ex5 via #resource).

## 6. Settings persistence — FileWriteStruct / key=value

Binary snapshot of the STATE struct (fast, exact):
```mql5
// STATE قابل للحفظ — أنواع بسيطة فقط، لا string ولا مؤشرات داخل struct ثنائي
struct SPersist { datetime lastBar; ulong activeTicket; int signalDir; double anchorPrice; };

#define STATE_FILE "MyEA_state.bin"

bool StateSave(const SPersist &st)
{
   int h = FileOpen(STATE_FILE, FILE_WRITE|FILE_BIN);
   if(h == INVALID_HANDLE) return false;
   uint w = FileWriteStruct(h, st);
   FileClose(h);
   return w == sizeof(st);
}

bool StateLoad(SPersist &st)
{
   if(!FileIsExist(STATE_FILE)) return false;
   int h = FileOpen(STATE_FILE, FILE_READ|FILE_BIN);
   if(h == INVALID_HANDLE) return false;
   uint r = FileReadStruct(h, st);
   FileClose(h);
   return r == sizeof(st);
}
```
- Strings can't live in binary structs — store them separately (FILE_TXT key=value) or as fixed `char buf[64]` arrays.
- Versioning: first int field = struct version; on mismatch, discard and rebuild (recovering state from positions/history) instead of reading garbage.
- Survive restarts/TF changes: save on every state mutation that matters (cheap), load in OnInit, and RECONCILE with reality (does activeTicket still exist? `PositionSelectByTicket`).
- File name should embed symbol+magic for multi-chart safety: `StringFormat("MyEA_%s_%I64d.bin", _Symbol, InpMagic)`.

## 7. Multi-symbol EA architecture

One EA on ONE chart trading many symbols — the correct modern pattern (one chart, one thread, full control):

```mql5
// CONFIG
input string InpSymbols = "EURUSD,GBPUSD,XAUUSD";   // Symbols (comma-separated)

// لكل رمز حالته الكاملة — لا globals لكل رمز
class CSymbolWorker : public CObject
{
public:
   string   symbol;
   int      hATR;
   datetime lastBar;
   bool Init(const string s)
   {
      symbol = s;
      if(!SymbolSelect(s, true)) return false;       // إلزامي قبل أي وصول للبيانات
      hATR = iATR(s, PERIOD_CURRENT, 14);
      return hATR != INVALID_HANDLE;
   }
   bool IsNewBar()
   {
      datetime t = iTime(symbol, _Period, 0);
      if(t == 0 || t == lastBar) return false;       // 0 = التاريخ غير جاهز بعد
      lastBar = t; return true;
   }
   void Process()
   {
      if(!IsNewBar()) return;
      // الإشارة والتنفيذ — كل SymbolInfo* بمعامل symbol، لا _Symbol إطلاقاً هنا
   }
   void Release() { if(hATR != INVALID_HANDLE) IndicatorRelease(hATR); }
};

CArrayObj g_workers;

int OnInit()
{
   string parts[];
   int n = StringSplit(InpSymbols, ',', parts);
   for(int i = 0; i < n; i++)
   {
      StringTrimLeft(parts[i]); StringTrimRight(parts[i]);
      CSymbolWorker *w = new CSymbolWorker();
      if(w.Init(parts[i])) g_workers.Add(w);
      else { PrintFormat("Symbol init failed: %s", parts[i]); delete w; }
   }
   if(g_workers.Total() == 0) return INIT_FAILED;
   EventSetTimer(1);          // OnTick يصل لرمز الشارت فقط — التايمر يغطي بقية الرموز
   return INIT_SUCCEEDED;
}

void OnTick()  { ProcessAll(); }
void OnTimer() { ProcessAll(); }
void ProcessAll()
{
   for(int i = 0; i < g_workers.Total(); i++)
   {
      CSymbolWorker *w = g_workers.At(i);
      if(w != NULL) w.Process();
   }
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   for(int i = 0; i < g_workers.Total(); i++)
   { CSymbolWorker *w = g_workers.At(i); if(w != NULL) w.Release(); }
   g_workers.Clear();
}
```
Hard rules:
- **OnTick fires only for the chart symbol** — the OnTimer companion is mandatory or other symbols trade late.
- Every data/trade call takes the worker's symbol explicitly; a single bare `_Symbol`/`_Point` inside worker logic is a defect (use `SymbolInfoDouble(symbol, SYMBOL_POINT)`).
- Per-symbol magic or shared magic + symbol filter — pick one and document it.
- Tester: multi-symbol works in "every tick based on real ticks"; other symbols' history loads on demand — first bars may need the readiness guard (`iTime()==0` check above).
- Position iteration filters by BOTH magic and the worker's symbol (trading.md §8).

## 8. Position reversal (DEAL_ENTRY_INOUT) summary

Netting accounts only: sending volume larger than the open opposite position produces ONE deal with `DEAL_ENTRY_INOUT` — it closes the old position and opens the new direction in a single fill. Handle it as close+open: realize P/L (DEAL_PROFIT covers the closed part), then re-register the new position state (new direction, volume = DEAL_VOLUME − old volume, ticket = same POSITION_IDENTIFIER continues or new — verify via PositionSelect). EAs that only watch DEAL_ENTRY_OUT will miss these exits. Full handler context in trading.md §10.

## 9. Account-Based Licensing

Protect EAs from unauthorized use without DLLs. All validation logic runs inside MQL5 — no external process required.

### Level 1 — Compile-time allowlist (simple, reversible)

```mql5
bool IsLicensed()
{
   long  acc    = AccountInfoInteger(ACCOUNT_LOGIN);
   // Embed allowed accounts — obfuscate with XOR or split across constants in production
   long allowed[] = {1234567, 8901234};
   for(int i = 0; i < ArraySize(allowed); i++)
      if(acc == allowed[i]) return true;
   PrintFormat("Not licensed — account %I64d", acc);
   return false;
}
// OnInit: if(!IsLicensed()) return INIT_FAILED;
```
Weakness: account numbers are visible in the decompiled source. Use Level 2 for commercial EAs.

### Level 2 — Server-side validation via WebRequest

```mql5
#define LIC_URL "https://your-api.com/lic"

bool CheckLicenseOnline()
{
   long acc = AccountInfoInteger(ACCOUNT_LOGIN);
   string broker = AccountInfoString(ACCOUNT_COMPANY);

   string url = StringFormat("%s?acc=%I64d&broker=%s&magic=%I64d",
                             LIC_URL, acc, UrlEncode(broker), InpMagic);
   string body;
   if(!HttpGetJson(url, body)) return false;   // network / server failure → deny
   return JsonGetStr(body, "status") == "ok";
}
// OnInit: call once, store result in bool g_licensed; check in OnTick.
// Refresh: re-validate in OnTimer every N hours to catch revocations.
```

### Level 3 — Broker / demo guard

```mql5
bool IsAllowedMode()
{
   // Reject demo if required
   if(!InpAllowDemo &&
      AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO)
   { Print("Demo account not allowed"); return false; }

   // Reject if account is not in a specific currency
   if(AccountInfoString(ACCOUNT_CURRENCY) != "USD")
   { Print("USD account required"); return false; }

   return true;
}
```

### Obfuscation notes
- Split the license key across multiple constants and reconstruct at runtime.
- XOR the account number with a compile-time secret before comparison.
- MQL5 Cloud Protector (MQL5 Market product tool) applies additional bytecode obfuscation at the `.ex5` level — use it for Market-distributed EAs.
- Do NOT call `ExpertRemove()` inside `OnInit` on license failure; return `INIT_FAILED` instead (the correct channel — `ExpertRemove` inside `OnInit` causes a double-free crash on some builds).
