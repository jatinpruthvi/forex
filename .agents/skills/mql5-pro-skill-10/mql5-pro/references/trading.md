# MQL5 Trading Operations — Production Reference

## Contents
1. Order/position model (MQL5 vs MQL4)
2. Netting vs hedging
3. CTrade correctly configured
4. Manual MqlTradeRequest + retcode handling
5. Volume and price normalization
6. Stops level / freeze level validation
7. Risk-based position sizing
8. Iterating positions/orders safely
9. Trailing stop pattern
10. OnTradeTransaction — reliable event detection
11. History access rules

## 1. Order/position model

MQL5 separates three entities (MQL4 merged them):
- **Order**: a request (market or pending). Live pending orders: `OrdersTotal()` + `OrderGetTicket(i)`.
- **Deal**: an execution fact (history only). `HistoryDealGetTicket(i)` after `HistorySelect`.
- **Position**: net result of deals per symbol (netting) or per entry (hedging). `PositionsTotal()` + `PositionGetTicket(i)`.

A market OrderSend produces: order → deal(s) → position. `result.order` is the order ticket; on hedging accounts the position ticket equals the opening order ticket; safest universal link is `POSITION_IDENTIFIER` / `DEAL_POSITION_ID`.

## 2. Netting vs hedging

```mql5
bool IsHedging()
{
   return (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)
          == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
}
```
- Netting (`RETAIL_NETTING`, `EXCHANGE`): one position per symbol. Opening opposite volume reduces/reverses it. `PositionSelect(symbol)` works.
- Hedging (`RETAIL_HEDGING`): many positions per symbol, each with its own ticket. Always use `PositionSelectByTicket`. Partial close = `trade.PositionClosePartial(ticket, volume)` (hedging) or opposite-direction deal (netting).
- Code intended for the Market or unknown brokers must branch on this, or state its requirement in `OnInit` and return `INIT_FAILED` with a clear Print.

## 3. CTrade correctly configured

```mql5
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
CTrade        trade;
CPositionInfo pos;
CSymbolInfo   sym;

int OnInit()
{
   if(!sym.Name(_Symbol)) return INIT_FAILED;
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFillingBySymbol(_Symbol);  // ← يحل خطأ 10030 Unsupported filling mode
   trade.LogLevel(LOG_LEVEL_ERRORS);
   return INIT_SUCCEEDED;
}
```

Result inspection after any call:
```mql5
if(!trade.Buy(lot, _Symbol, 0, sl, tp, "comment"))
   PrintFormat("فشل الشراء — retcode=%u (%s)", trade.ResultRetcode(), trade.ResultRetcodeDescription());
else
{
   ulong dealTicket  = trade.ResultDeal();
   ulong orderTicket = trade.ResultOrder();
}
```
`trade.Buy()` returning true means the request was accepted — still verify `ResultRetcode()==TRADE_RETCODE_DONE` (10009) for sync mode. With `SetAsyncMode(true)`, success only means "sent"; confirmation arrives in `OnTradeTransaction`.

## 4. Manual MqlTradeRequest + retcode handling

Use raw OrderSend when CTrade is insufficient (close-by, custom expiration, stop-limit):

```mql5
bool SendDeal(ENUM_ORDER_TYPE type, double volume, double sl, double tp)
{
   MqlTradeRequest req; MqlTradeResult res;
   ZeroMemory(req); ZeroMemory(res);                 // إلزامي — حقول غير مهيأة = رفض عشوائي
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = volume;
   req.type      = type;
   req.price     = (type==ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol,SYMBOL_ASK)
                                          : SymbolInfoDouble(_Symbol,SYMBOL_BID);
   req.sl        = sl;
   req.tp        = tp;
   req.deviation = 10;
   req.magic     = InpMagic;
   req.type_filling = GetFilling(_Symbol);

   for(int attempt = 0; attempt < 3; attempt++)
   {
      if(OrderSend(req, res) && (res.retcode==TRADE_RETCODE_DONE || res.retcode==TRADE_RETCODE_DONE_PARTIAL))
         return true;
      // retcodes قابلة لإعادة المحاولة فقط
      if(res.retcode==TRADE_RETCODE_REQUOTE || res.retcode==TRADE_RETCODE_PRICE_CHANGED ||
         res.retcode==TRADE_RETCODE_PRICE_OFF)
      {
         req.price = (type==ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol,SYMBOL_ASK)
                                            : SymbolInfoDouble(_Symbol,SYMBOL_BID);
         continue;
      }
      break; // أخطاء غير قابلة لإعادة المحاولة
   }
   PrintFormat("OrderSend failed retcode=%u comment=%s", res.retcode, res.comment);
   return false;
}
```

Key retcodes:

| Code | Constant | Meaning / action |
|---|---|---|
| 10008 | PLACED | pending placed — success for pendings |
| 10009 | DONE | executed — success |
| 10010 | DONE_PARTIAL | partial fill — track remaining volume |
| 10004 | REQUOTE | retry with fresh price |
| 10013 | INVALID | malformed request — fix code, no retry |
| 10014 | INVALID_VOLUME | normalize to step/min/max |
| 10015 | INVALID_PRICE | round to tick size |
| 10016 | INVALID_STOPS | SL/TP too close — see §6 |
| 10017 | TRADE_DISABLED | AutoTrading off / EA trading disabled |
| 10018 | MARKET_CLOSED | check session times, no retry now |
| 10019 | NO_MONEY | reduce volume via OrderCalcMargin pre-check |
| 10021 | PRICE_OFF | no quotes — retry with fresh price |
| 10025 | NO_CHANGES | request changes nothing — compare new SL/TP with current BEFORE any modify (see below) |
| 10027 | CLIENT_DISABLES_AT | Algo button off in terminal |
| 10030 | INVALID_FILL | wrong filling mode — use SetTypeFillingBySymbol |

Filling mode detection:
```mql5
ENUM_ORDER_TYPE_FILLING GetFilling(const string s)
{
   long mode = SymbolInfoInteger(s, SYMBOL_FILLING_MODE);
   if((mode & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((mode & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}
```

Pre-check margin before sending:
```mql5
double need;
if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lot, ask, need)) return false;
if(need > AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.9) return false;  // هامش أمان
```

Full server-side pre-validation with `OrderCheck` (the documented recommendation, and a Market-validation requirement): it simulates the request against the account and returns the same retcode the server would, without sending:
```mql5
MqlTradeCheckResult chk; ZeroMemory(chk);
if(!OrderCheck(req, chk))
{
   PrintFormat("Pre-check failed retcode=%u (%s)", chk.retcode, chk.comment);
   return false;   // لا تُرسل طلباً سيُرفض حتماً
}
// chk.margin_free بعد الصفقة، chk.margin_level — متاحة للفحص الإضافي
```

## 5. Volume and price normalization

```mql5
double NormalizeVolume(const string s, double vol)
{
   double minV = SymbolInfoDouble(s, SYMBOL_VOLUME_MIN);
   double maxV = SymbolInfoDouble(s, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(s, SYMBOL_VOLUME_STEP);
   vol = MathFloor(vol / step) * step;          // Floor = لا تخاطر بأكثر من المحسوب
   return MathMin(MathMax(vol, minV), maxV);
}

double NormalizePrice(const string s, double price)
{
   double tick = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0) tick = SymbolInfoDouble(s, SYMBOL_POINT);
   return MathRound(price / tick) * tick;       // وليس NormalizeDouble فقط
}
```
`NormalizeDouble(price,_Digits)` alone fails on indices/metals where tick size is 0.25, 0.5 etc. Always round to tick size, then `NormalizeDouble` for cosmetic digit count if needed.

## 6. Stops level / freeze level validation

```mql5
// المسافة الدنيا المسموحة من السعر الحالي (بالنقاط Points)
double MinStopDistance(const string s)
{
   long stops  = SymbolInfoInteger(s, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze = SymbolInfoInteger(s, SYMBOL_TRADE_FREEZE_LEVEL);
   long pts = MathMax(stops, freeze);
   if(pts == 0) pts = (long)(SymbolInfoInteger(s, SYMBOL_SPREAD) * 3); // احتياط لبروكر يعيد 0
   return pts * SymbolInfoDouble(s, SYMBOL_POINT);
}
```
Rules (both values are already in points — never multiply by Point twice):
- BUY: SL must be `< Bid - dist`, TP `> Bid + dist` (protective levels of a buy are measured against **Bid**).
- SELL: SL `> Ask + dist`, TP `< Ask - dist`.
- Pending order open price must be at least `dist` from the relevant current price (Ask for buys, Bid for sells).
- FREEZE_LEVEL additionally blocks modifying/deleting orders or stops already within the band — skip modification attempts inside it instead of hammering the server.
- Some brokers return 0 for stops level but still reject; the spread-based fallback above plus retcode 10016 handling covers it.

## 7. Risk-based position sizing

Correct universal formula (works for FX, metals, indices, account currency independent):
```mql5
double LotsForRisk(const string s, double riskMoney, double entry, double sl)
{
   double tickSize  = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_VALUE_LOSS); // قيمة الخسارة أدق من TICK_VALUE
   if(tickValue <= 0) tickValue = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0 || tickValue <= 0) return 0;
   double ticks = MathAbs(entry - sl) / tickSize;
   if(ticks <= 0) return 0;
   double lossPerLot = ticks * tickValue;
   return NormalizeVolume(s, riskMoney / lossPerLot);
}
// riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPct / 100.0;
```
Caveats:
- `SYMBOL_TRADE_TICK_VALUE` is unreliable on some non-FX symbols/brokers; prefer `TICK_VALUE_LOSS` for risk, `TICK_VALUE_PROFIT` for targets.
- The SL distance includes spread for sells closed at Ask. Add commission per lot for exact risk.
- After sizing, re-check margin (§4) and that result ≥ VOLUME_MIN, else skip the trade — do NOT silently bump to min lot in risk-strict systems; make it an input policy.

## 8. Iterating positions/orders safely

Always iterate descending when closing/modifying (indices shift on removal), always re-select by ticket, always filter magic+symbol:
```mql5
void CloseAllMine()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);            // يختار المركز أيضاً
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      trade.PositionClose(ticket);
   }
}
```
`PositionGetTicket(i)` selects the position for the subsequent `PositionGet*` calls — no separate select needed. Cache nothing across ticks except tickets; volumes/SL can change externally.

## 9. Trailing stop pattern

```mql5
void Trail(double trailPoints, double stepPoints)
{
   double pt = _Point;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t==0 || PositionGetInteger(POSITION_MAGIC)!=InpMagic
              || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      double sl  = PositionGetDouble(POSITION_SL);
      long  type = PositionGetInteger(POSITION_TYPE);
      double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double dist = MinStopDistance(_Symbol);

      if(type==POSITION_TYPE_BUY)
      {
         double newSL = NormalizePrice(_Symbol, bid - trailPoints*pt);
         if(newSL > sl + stepPoints*pt && newSL < bid - dist)      // step يمنع التعديل كل تيك
            trade.PositionModify(t, newSL, PositionGetDouble(POSITION_TP));
      }
      else
      {
         double newSL = NormalizePrice(_Symbol, ask + trailPoints*pt);
         if((sl==0 || newSL < sl - stepPoints*pt) && newSL > ask + dist)
            trade.PositionModify(t, newSL, PositionGetDouble(POSITION_TP));
      }
   }
}
```
The step condition is mandatory — modifying every tick triggers TOO_MANY_REQUESTS (10024) and broker complaints.

**Compare-before-modify rule (prevents 10025 NO_CHANGES)**: a modify request whose values equal the current ones is treated as an ERROR by the server. Before every `PositionModify`/`OrderModify`, compare against the live values with a tick-size tolerance and skip when nothing actually changes:
```mql5
bool LevelsDiffer(double a, double b)
{
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   return MathAbs(a - b) >= (tick > 0 ? tick : _Point) / 2;
}
// if(!LevelsDiffer(newSL, PositionGetDouble(POSITION_SL)) &&
//    !LevelsDiffer(newTP, PositionGetDouble(POSITION_TP))) skip;
```
The trailing pattern above already encodes this via the step condition; apply the same comparison in breakeven and partial-management code. This check is also enforced by MQL5 Market automatic validation.

## 10. OnTradeTransaction — reliable event detection

The handler fires multiple times per operation (request, order add, order delete, deal add, history add). Filter on `TRADE_TRANSACTION_DEAL_ADD` and select the deal before reading it:

```mql5
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;            // ← بدون هذا، كل HistoryDealGet* تعيد 0

   long  entry  = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   long  reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
   long  magic  = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   ulong posId  = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   string symb  = HistoryDealGetString(trans.deal, DEAL_SYMBOL);

   if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
   {
      if(reason == DEAL_REASON_SL) { /* ضرب وقف الخسارة */ }
      if(reason == DEAL_REASON_TP) { /* ضرب الهدف */ }
      double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                    + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                    + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   }
   else if(entry == DEAL_ENTRY_INOUT)
   {
      // انعكاس مركز (netting فقط): صفقة واحدة أغلقت المركز القديم وفتحت عكسياً
      // DEAL_VOLUME = الحجم الكلي؛ حجم المركز الجديد = DEAL_VOLUME - حجم المركز القديم
      // DEAL_PROFIT هنا = ربح/خسارة الجزء المُغلق — عالجه كإغلاق + فتح معاً
   }
}
```
Known traps:
- On SL/TP closes, `DEAL_MAGIC` may be 0 with some brokers (server-side deal). Match by `DEAL_POSITION_ID` against tickets you stored at open time instead of trusting magic on OUT deals.
- The account state may change WHILE the handler runs (queued events). Never assume a position still exists; re-check with `PositionSelectByTicket`.
- In async mode, correlate via `result.request_id` ↔ `trans.order` chains.
- `trans.type` enum, not raw numbers (avoid `if(trans.type != 6)` style).

## 11. History access rules

Every `HistoryDeal*/HistoryOrder*` query requires a prior selection:
```mql5
HistorySelect(0, TimeCurrent());                 // أو نطاق أضيق للأداء
// أو لمركز محدد:
HistorySelectByPosition(positionId);
int total = HistoryDealsTotal();
for(int i = 0; i < total; i++)
{
   ulong d = HistoryDealGetTicket(i);
   // HistoryDealGetDouble(d, DEAL_PROFIT) ...
}
```
On large accounts, `HistorySelect(0, TimeCurrent())` is expensive — narrow the window or cache results per session. Daily P/L pattern: select from day start, sum `DEAL_PROFIT+DEAL_SWAP+DEAL_COMMISSION` of `DEAL_ENTRY_OUT` deals filtered by magic.

## 12. Funded / Prop Firm Account Protection

Prop firm rules vary; implement what the user states. The pattern below covers the three universal constraints.

```mql5
// CONFIG
input group "=== Funded Account Protection ==="
input double InpMaxDailyLossPct  = 5.0;    // Max daily loss (% of day-start balance)
input double InpMaxTotalDDPct    = 10.0;   // Max total drawdown (% of peak equity)
input bool   InpHaltOnBreach     = true;   // Close all and halt EA on breach

// STATE — add these fields to your SState struct
struct SFundedState
{
   double   dayStartBalance;   // balance at trading day open
   double   peakEquity;        // high-water mark
   bool     halted;            // EA halted after breach
   datetime lastDayTs;         // timestamp of last day-reset
};
SFundedState g_funded;

// Call once in OnInit:
void FundedInit()
{
   g_funded.dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_funded.peakEquity      = AccountInfoDouble(ACCOUNT_EQUITY);
   g_funded.halted          = false;
   g_funded.lastDayTs       = 0;
}

// Call at the TOP of OnTick/OnTimer before any signal logic:
// Returns false = do not trade.
bool FundedCheck()
{
   if(g_funded.halted) return false;

   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);

   // --- daily reset (server time day boundary) ---
   datetime now = TimeCurrent();
   MqlDateTime dt; TimeToStruct(now, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime dayOpen = StructToTime(dt);
   if(dayOpen > g_funded.lastDayTs)
   {
      g_funded.dayStartBalance = balance;
      g_funded.lastDayTs       = dayOpen;
   }

   // --- update peak ---
   if(equity > g_funded.peakEquity) g_funded.peakEquity = equity;

   // --- daily loss check ---
   double dailyLoss    = g_funded.dayStartBalance - equity;
   double maxDailyLoss = g_funded.dayStartBalance * InpMaxDailyLossPct / 100.0;
   if(dailyLoss >= maxDailyLoss)
   {
      FundedBreach(StringFormat("Daily loss %.2f >= limit %.2f", dailyLoss, maxDailyLoss));
      return false;
   }

   // --- total drawdown check ---
   double totalDD    = g_funded.peakEquity - equity;
   double maxTotalDD = g_funded.peakEquity * InpMaxTotalDDPct / 100.0;
   if(totalDD >= maxTotalDD)
   {
      FundedBreach(StringFormat("Total DD %.2f >= limit %.2f", totalDD, maxTotalDD));
      return false;
   }

   return true;
}

void FundedBreach(const string reason)
{
   PrintFormat("[FUNDED BREACH] %s — closing all positions", reason);
   if(InpHaltOnBreach)
   {
      // Close all positions belonging to this EA
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
         trade.PositionClose(t);
      }
      // Cancel pending orders
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong t = OrderGetTicket(i);
         if(t == 0) continue;
         if(OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
         trade.OrderDelete(t);
      }
      g_funded.halted = true;
   }
}
```

**Trailing drawdown (some prop firms):** instead of a fixed peak, the max-loss floor rises as balance increases — but never falls. Replace `g_funded.peakEquity` with a `floorBalance` that updates only when `balance > peakBalance`:
```mql5
// update floor every new balance high
if(balance > g_funded.peakEquity)
{
   g_funded.peakEquity = balance;
   // floor = peak minus allowed DD amount (firm-specific rule)
}
```

**Integration rules:**
- `FundedInit()` → end of `OnInit`.
- `if(!FundedCheck()) return;` → first line of `OnTick` / signal processing.
- Persist `g_funded` with `StateSave/StateLoad` (advanced.md §6) so breach state survives EA restarts (prevents halted EA from re-entering on reload).
- Daily reset time = server time midnight (`TimeCurrent`); if the broker's trading day resets at a different hour, adjust the `dayOpen` calculation.
- Do not rely on `g_funded.halted` alone after a restart unless you persist it — always reconcile with the account state on `OnInit`.
