# MQL5 Module Integration — writing programs that merge cleanly later

Read this ONLY when the user states a program will later be combined with other EAs/indicators/panels into one `.mq5`. For standalone programs it adds pure overhead — do not apply it by default. Item 12 of the SKILL.md deliverable checklist gates this.

The goal: write program N today so that merging programs 1..N tomorrow needs **zero renaming and zero rewriting** — only `#include` + dispatch. Every rule below is justified on engineering merit (namespace, ownership, single-handler reality), not on who performs the merge.

The single biggest cause of a failed merge is two files each declaring a free global with the same name (`g_lastBar`) or an `input` with the same name (`InpRiskPct`): the compiler rejects it as a duplicate identifier. The standard below removes that class of collision structurally.

---

## §1 — Three code categories, only ONE ever takes a prefix

Classify every symbol into exactly one of:

| Category | What | Naming |
|---|---|---|
| **SHARED** | stateless helpers usable by any program: lot/price normalization, new-bar check, formatting, retcode→string | generic name, **no prefix** — lives in `Common.mqh`, written once |
| **MODULE-SPECIFIC** | the program's own logic (its signal, its panel build, its grid manager) | descriptive name, **no prefix** |
| **LIFECYCLE** | the module's entry points the merged file calls | fixed form `ModuleName_OnXxx` (§4) |

Prefixes are NOT a collision-avoidance tool here. Two functions named `CalculateLotBySL` with identical logic must be ONE function in `Common.mqh`, not `RP_CalculateLot` + `TR_CalculateLot` (that duplicates code and violates the skill's "one generic function" rule). A textual prefix is correct in exactly the cases of §6, where the thing colliding is a **value on the chart/account/inputs**, not a symbolic name.

---

## §2 — STATE as a struct named after the module

Never scatter mutable globals (`datetime g_lastBar; ulong g_ticket;`). Two modules doing this collide on the global name = compile error, forcing manual renaming at merge time. Wrap each module's runtime state in ONE struct instance whose name carries the module identity:

```mql5
// State — حالة الموديول كلها في struct واحد باسم الموديول
struct RiskPanel_State
{
   datetime lastBar;
   ulong    activeTicket;
   int      signalDir;
};
RiskPanel_State g_riskPanel;   // الاسم الوحيد الذي يدخل النطاق العام
```

This is the SAME rule the skill already mandates for standalone programs ("STATE collected in one struct") — the only addition is the module-identity name. The fields stay short and unprefixed; the compiler's type system keeps two modules' state apart with zero duplication. Merge cost: none — `g_riskPanel` and `g_trailing` never clash.

---

## §3 — File header: include guard + manifest (mandatory on every mergeable `.mqh`)

**Include guard first — this is the #1 mechanical merge failure.** MQL5 `#include` is plain textual inclusion with NO automatic de-duplication. When `Common.mqh` is included by both `RiskPanel.mqh` and the top-level `.mq5`, every symbol in it is defined twice → "variable/function already defined" compile errors. Wrap EVERY shared and module `.mqh` in a guard:

```mql5
#ifndef RISKPANEL_MQH
#define RISKPANEL_MQH
// ... كل محتوى الملف ...
#endif // RISKPANEL_MQH
```

Then the manifest — a fixed comment block so the merge step reads the interface without scanning function bodies:

```mql5
//+------------------------------------------------------------------+
//| MODULE: RiskPanel                                                |
//| EXPORTS : RiskPanel_OnInit, RiskPanel_OnTick, RiskPanel_OnDeinit,|
//|           RiskPanel_OnChartEvent                                 |
//| STATE   : g_riskPanel (RiskPanel_State)                          |
//| INPUTS  : InpRP_RiskPct, InpRP_MaxLoss   (prefixed — see §6)     |
//| DEPENDS : Common.mqh (CalculateLotBySL, IsNewBar)                |
//| OBJECTS : prefix "RP_"                                           |
//| MAGIC   : InpRP_Magic                                            |
//| BUFFERS : 0   (indicators only — see §6)                         |
//| TIMER   : 1000 ms   (or "none" — see §4)                         |
//+------------------------------------------------------------------+
```

EXPORTS and DEPENDS make the public surface explicit (what may be called vs what is internal). STATE/OBJECTS/MAGIC/INPUTS/BUFFERS/TIMER list every globally-scoped thing the merge must reconcile. Reading five lines replaces reading the whole file.

---

## §4 — LIFECYCLE contract (the fixed entry-point form)

Each module exposes these instead of defining `OnInit`/`OnTick`/etc. directly (a program may have only ONE of each real handler — §5). Omit any the module does not need; declare which in the manifest.

```mql5
int  RiskPanel_OnInit();                                   // returns INIT_SUCCEEDED / INIT_FAILED
void RiskPanel_OnDeinit(const int reason);
void RiskPanel_OnTick();                                   // EA modules
void RiskPanel_OnTimer();                                  // if module needs a timer
void RiskPanel_OnChartEvent(const int id,const long &l,const double &d,const string &s);
void RiskPanel_OnTradeTransaction(const MqlTradeTransaction &t,
                                  const MqlTradeRequest &req,
                                  const MqlTradeResult &res);
double RiskPanel_OnTester();                               // at most ONE module may own this
```

This is the idiomatic way to compose several "sub-EAs" into one EA. Because the skill already requires every EA to filter positions by its own magic + symbol, modules compose without interfering: each `RiskPanel_OnTradeTransaction` ignores deals whose magic isn't its own.

---

## §5 — The merged `.mq5`: single real handlers that dispatch, no logic

A program has exactly ONE `OnInit/OnDeinit/OnTick/OnTimer/OnChartEvent/OnTradeTransaction/OnTester`. The merged file holds only `#include`s and dispatch — never business logic:

```mql5
#include "Common.mqh"
#include "RiskPanel.mqh"
#include "Trailing.mqh"

int OnInit()
{
   if(RiskPanel_OnInit() != INIT_SUCCEEDED) return INIT_FAILED;
   if(Trailing_OnInit()  != INIT_SUCCEEDED) return INIT_FAILED;
   EventSetTimer(1);                       // فترة واحدة مشتركة — انظر تحذير المؤقّت
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
   EventKillTimer();
   RiskPanel_OnDeinit(reason);
   Trailing_OnDeinit(reason);
}
void OnTick()            { RiskPanel_OnTick();  Trailing_OnTick(); }
void OnTimer()           { RiskPanel_OnTimer(); Trailing_OnTimer(); }
void OnChartEvent(const int id,const long &l,const double &d,const string &s)
{ RiskPanel_OnChartEvent(id,l,d,s); Trailing_OnChartEvent(id,l,d,s); }
void OnTradeTransaction(const MqlTradeTransaction &t,const MqlTradeRequest &q,const MqlTradeResult &r)
{ RiskPanel_OnTradeTransaction(t,q,r); Trailing_OnTradeTransaction(t,q,r); }
```

**Single-handler constraints the modules must respect:**
- **One timer per program.** A module must NOT call `EventSetTimer` itself. It declares its desired period in the manifest; the merged `OnInit` sets ONE period (the GCD or the smallest needed) and every `ModuleName_OnTimer` runs each tick of it, gating internally if it needs a slower cadence.
- **One `OnTester`.** At most one module may compute the optimization criterion; the rest must not define `_OnTester`.
- **Magic must differ per trading module** (§6) so the shared `OnTradeTransaction` dispatch routes deals correctly via each module's own magic filter.

---

## §6 — The ONLY cases that take a real prefix: value-space collisions

These collide by a **value placed on the chart, account, or inputs dialog**, not by a symbolic name — so a prefix is the correct fix, and this does not contradict §1–§2:

1. **Chart object names** — two modules drawing `"BG"` overwrite each other. Each module owns a unique object prefix (`"RP_"`, `"TR_"`) used in every create and in `ObjectsDeleteAll(0, prefix)`.
2. **Magic numbers** — distinct integer per trading module; otherwise position/deal filters cross-claim each other's trades.
3. **`input` names** — inputs share one global namespace; two `InpRiskPct` = duplicate-identifier compile error. Prefix every input per module: `InpRP_RiskPct`, `InpTR_Step`. This is the one identifier class that needs a textual prefix, because inputs cannot be hidden in a struct.
4. **`GlobalVariable*` names** and **persisted file names** — namespace them with the module/magic: `StringFormat("RP_%I64d_state", InpRP_Magic)`.

Everything else (functions, locals, the STATE struct fields) stays unprefixed.

---

## §7 — Indicators merge differently (buffers, not just dispatch)

§4–§5 compose EAs and panels cleanly. **Indicators do not compose by calling `ModuleA_OnCalculate` + `ModuleB_OnCalculate`** — there is ONE `OnCalculate`, and `#property indicator_buffers`/`indicator_plots` are global counts shared by all modules. To merge indicator modules:

1. Manifest `BUFFERS:` declares how many buffers each module needs.
2. The merged file sums them into `#property indicator_buffers N`, assigns each module a **base offset**, and the module binds its buffers relative to that offset (`SetIndexBuffer(base+0,...)`, `base+1`, ...) — never hardcoded absolute indices.
3. Each module exposes `ModuleName_Calc(rates_total, prev_calculated, base, /*price arrays*/)` instead of `OnCalculate`; the single real `OnCalculate` calls each with its base offset and a shared `prev_calculated`.
4. Plot styling (`PlotIndexSetInteger`) likewise uses plot offsets, not absolute indices.

If a module needs a panel + indicator buffers, split it: the buffer part follows this section, the panel part follows §4–§5.

---

## §8 — Merging GUI panel modules (CAppDialog / canvas / custom events)

EAs and panels compose via §4–§5 dispatch, but panels add their own collision surfaces — all in the **value space** of §6, so they take real namespacing:

1. **Unique dialog name per panel module.** `CAppDialog` derives every child object name from the `name` passed to `Create`. Two modules calling `Create(0, "Trade Panel", ...)` produce identical object names — one panel's controls become dead. Give each a distinct name: `RiskPanel_OnInit` → `m_dlg.Create(0, "RP_Panel", 0, x1, y1, x2, y2)`.
2. **Distinct initial positions.** Panels created at the same `(x1,y1)` stack and hide each other. Offset them, or persist per-panel geometry (gui.md §9) under namespaced GlobalVariable names (§6.4).
3. **Forward OnChartEvent to every panel.** The merged `OnChartEvent` calls each `ModuleName_OnChartEvent` → each dialog's `ChartEvent()`; every dialog internally filters by its own object names, so forwarding to all is correct and cheap.
4. **Namespace custom-event IDs.** Two modules both emitting `EventChartCustom(0, 0, ...)` arrive as the same `CHARTEVENT_CUSTOM+0` and cross-trigger. Each emitter owns a base range: `#define RP_EVT_BASE 1000` / `#define TR_EVT_BASE 2000`, emit `EventChartCustom(0, RP_EVT_BASE+n, ...)`, dispatch on the range. (Mirror this note in gui.md §6.)
5. **Canvas/bitmap-label names are object names.** `CreateBitmapLabel("MYCV", ...)` collides exactly like a chart object — prefix it (`"RP_CV"`).
6. **Non-overlapping object prefixes.** `ObjectsDeleteAll(0, "R_")` also deletes `"RP_..."`. Make prefixes mutually non-prefixing and end each with a separator: `"RP_"`, `"TR_"` — never `"R_"` + `"RP_"`.

## §9 — Trading module specifics

1. **Each trading module owns its own `CTrade`, configured with its own magic** in `ModuleName_OnInit`: `m_trade.SetExpertMagicNumber(InpRP_Magic)`. A single shared `CTrade` carries ONE magic; routing two modules through it stamps trades with the wrong owner and breaks every magic-filtered position/deal loop. (If a shared instance is unavoidable, call `SetExpertMagicNumber` before each module's trade batch — error-prone; prefer per-module instances.)
2. **`OnDeinit` must be idempotent.** If module B's `OnInit` returns `INIT_FAILED`, MQL5 still calls `OnDeinit`, which dispatches to module A (initialized) AND module B (never initialized). Each `ModuleName_OnDeinit` must guard: release handles only if created, `ObjectsDeleteAll(0, prefix)` (safe when none exist), never touch half-built STATE. Carry a `bool inited;` field in the module STATE struct and check it first.
3. **Partial-init rollback** falls out of (2): when a later module fails init, earlier modules' timer/handles/objects are freed by the dispatched idempotent `OnDeinit`.

## §10 — Indicator + EA: port the logic, don't merge the program

1. **A compiled `.ex5` has exactly ONE program type, fixed by the compiler** (`OnCalculate`/`#property indicator_*` → indicator; `OnTick` → EA). One file cannot be simultaneously an `iCustom`-loadable indicator that owns `indicator_buffers/plots` AND an EA that trades in `OnTick`. (This is also why a chart runs many indicators but one EA.)
2. **Porting indicator LOGIC into an EA is easy and is the normal path** — not a "merge". Copy the `OnCalculate` math as plain functions that compute into internal arrays, drop `SetIndexBuffer`/plots, and call them from `OnTick` (new-bar gated) as the signal source. To show the indicator's visuals from inside the EA, redraw them with chart objects (gui.md §5), since an EA has no indicator buffers.
3. **Keep it a separate indicator only when another program must read it** via `iCustom` + `CopyBuffer`. Then embed the compiled `.ex5` with `#resource` (portable-layout rule in SKILL.md) so the EA stays self-contained.
4. **`#property` is global and singular in the merged `.mq5`.** One `#property version`, one `#property indicator_buffers/plots` (summed per §7), one window/separate-window mode — all in the top-level `.mq5` only. Module `.mqh` files carry NO `#property indicator_*` lines (ignored inside includes, and stray version/copyright lines cause confusion).

---

## §11 — Merge-readiness checklist (apply ONLY when merge intent is declared)

1. Module file carries the §3 manifest; EXPORTS lists exactly the `ModuleName_OnXxx` it defines.
2. All runtime state is inside one `ModuleName_State` struct instance — zero free mutable globals.
3. Every stateless helper that another program could reuse is in `Common.mqh` with a generic name — not duplicated under a module-specific name.
4. Inputs, object prefix, magic, GlobalVariable names, and persisted filenames are all module-namespaced per §6.
5. No `EventSetTimer`/`OnTester` inside a module; timer period declared in manifest only.
6. If an indicator module: buffers bound via a base offset, count declared in manifest (§7).
7. `Common.mqh` collision check: if the same helper name exists in two modules with identical logic, keep one and delete the rest; if same name but genuinely different logic, rename the odd one *descriptively by behavior* (`CalculateLotByRisk` vs `CalculateLotFixed`) — never by module prefix.
8. Every shared and module `.mqh` is wrapped in an `#ifndef/#define/#endif` include guard (§3).
9. Each panel module uses a unique `CAppDialog` name, a non-overlapping object prefix ending in a separator, and namespaced canvas/bitmap-label names (§8).
10. Each trading module owns its own `CTrade` with its own magic; every `ModuleName_OnDeinit` is idempotent, guarded by a `bool inited` flag in its STATE struct (§9).
11. Custom-event emitters use a per-module base ID range (§8.4).
12. Only same-type programs are merged; cross-type composition is via `iCustom` handle + `#resource`; all `#property` lines live in the top-level `.mq5` only (§10).
