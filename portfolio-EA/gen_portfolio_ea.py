#!/usr/bin/env python3
"""Generate a one-chart portfolio EA from the 65 delivered EAs.

NEW FILES ONLY.  This reads the delivered EAs and the engine headers, and writes
everything it needs into ``portfolio-EA/build/`` - no original file (not one of
the 65 EAs, not the engine includes) is touched.

    python3 portfolio-EA/gen_portfolio_ea.py            # writes build/
    python3 portfolio-EA/gen_portfolio_ea.py --check    # verify build/ is current

What it emits
-------------
``build/PortfolioStrategies.mqh``
    All 65 strategy classes, taken from the delivered EAs, with:
      * class names prefixed  (CGrid -> P2048_CGrid)          - no collisions
      * EA-local enums prefixed, merged into one namespace
      * ``input`` declarations converted to prefixed ``const`` globals holding
        the delivered defaults (one program cannot have 65 x InpMagicNumber)
      * the per-EA ``OnInit/OnTick/OnDeinit`` and the global instance dropped
    The strategy *logic* is copied verbatim; nothing inside the classes is
    rewritten except the identifiers above.

``build/PortfolioEA.mq5``
    The host: one chart, one EA, all 65 strategies.  MT5 allows one EA per
    chart, so this is the only way to get a genuinely single-chart book.  The
    engine is used **unchanged**; the host snapshots the engine's per-strategy
    globals around each strategy's tick:

        cfg / symbols / indicator sets / position tracks / spread-stat symbol
        table / news cache            -> saved and restored per strategy
        risk governor + executor      -> refreshed per switch via their own
                                         Init(), which reloads the magic-scoped
                                         GlobalVariables they persist to

    See README.md for the fidelity table and the one optional engine accessor.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "validation" / "mt5_harness"))

import gen_tester_configs as gtc  # noqa: E402  (EA spec loader)

EA_DIR = REPO / "MQL5_Master" / "Experts" / "additionalEAs"
INCLUDE_DIR = REPO / "MQL5_Master" / "Include"
BUILD = Path(__file__).resolve().parent / "build"

INC_MARKER = '#include "..\\..\\Include\\EACommon.mqh"'
HANDLERS_MARKER = "//| MQL5 event handlers"

# trailing "// comment" is normal on every delivered input line
TF_LABEL = {"PERIOD_M1": "M1", "PERIOD_M5": "M5", "PERIOD_M15": "M15",
            "PERIOD_M30": "M30", "PERIOD_H1": "H1", "PERIOD_H4": "H4",
            "PERIOD_D1": "D1"}


def strategy_label(ea) -> str:
    """cfg.strategyName from the delivered EA (the label used in its logs)."""
    m = re.search(r'cfg\.strategyName\s*=\s*"([^"]+)"', ea.configure)
    return m.group(1) if m else ea.name


INPUT_LINE_RE = re.compile(r"^\s*input\s+(\w+)\s+(\w+)\s*=\s*(.*?);\s*(?://.*)?$", re.M)
ENUM_RE = re.compile(r"^\s*enum\s+(\w+)\s*\{(.*?)\}\s*;", re.M | re.S)
CLASS_RE = re.compile(r"^\s*class\s+(\w+)\s*:\s*public\s+CEAStrategy\s*\{", re.M)
IDENT_RE = re.compile(r"[A-Za-z_]\w*")
TIMEFRAME_RE = re.compile(r"cfg\.signalTimeframe\s*=\s*(PERIOD_\w+)")


# --------------------------------------------------------------------------
# engine knowledge (read-only)
# --------------------------------------------------------------------------
def engine_enum_values() -> set[str]:
    """Every enum value name the engine headers already define."""
    vals: set[str] = set()
    for header in INCLUDE_DIR.glob("*.mqh"):
        src = header.read_text(encoding="utf-8", errors="replace")
        for _, body in ENUM_RE.findall(src):
            body = re.sub(r"//.*", "", body)
            for item in body.split(","):
                item = item.strip()
                if not item:
                    continue
                name = item.split("=")[0].strip()
                if IDENT_RE.fullmatch(name):
                    vals.add(name)
    return vals


def strategy_source(name: str) -> str:
    """The 'strategy only' section of a delivered EA (no properties/handlers)."""
    p = EA_DIR / f"{name}.mq5"
    src = p.read_text(encoding="utf-8")
    if INC_MARKER not in src:
        raise SystemExit(f"{p}: unexpected layout (engine include line missing)")
    part = src.split(INC_MARKER, 1)[1]
    if HANDLERS_MARKER not in part:
        raise SystemExit(f"{p}: unexpected layout (event-handler marker missing)")
    return part.split(HANDLERS_MARKER, 1)[0]


# --------------------------------------------------------------------------
# transform one EA into a portfolio-friendly block
# --------------------------------------------------------------------------
def transform(ea, engine_values: set[str]) -> dict:
    src = strategy_source(ea.name)
    prefix = f"P{ea.magic}_"

    class_m = CLASS_RE.search(src)
    if not class_m:
        raise SystemExit(f"{ea.name}: no 'class X : public CEAStrategy' found")
    cls = class_m.group(1)

    enums = ENUM_RE.findall(src)
    enum_types = [t for t, _ in enums]

    # enum values that would collide in one program get the per-EA prefix
    renamed_values: dict[str, str] = {}
    local_values: list[str] = []
    for _, body in enums:
        for item in re.sub(r"//.*", "", body).split(","):
            item = item.strip()
            if not item:
                continue
            v = item.split("=")[0].strip()
            if IDENT_RE.fullmatch(v):
                local_values.append(v)

    seen: dict[str, int] = {}
    for v in local_values:
        seen[v] = seen.get(v, 0) + 1
    for v in local_values:
        if v in engine_values or seen[v] > 1:
            renamed_values[v] = prefix + v

    # the delivered layout puts a banner around the inputs; the declarations are
    # replaced by consts above the class, so the empty banner goes away
    src = src.replace(
        "//+------------------------------------------------------------------+\n"
        "//| Inputs                                                           |\n"
        "//+------------------------------------------------------------------+\n", "")

    inputs = [(t, n, d) for t, n, d in INPUT_LINE_RE.findall(src)]
    if not inputs:
        raise SystemExit(f"{ea.name}: no input declarations found")

    body = src
    # drop the input declarations and the file-scope instance
    body = INPUT_LINE_RE.sub("", body)
    body = re.sub(rf"^\s*{re.escape(cls)}\s+\w+\s*;\s*$", "", body, flags=re.M)

    # rename identifiers (whole words only, longest first to avoid partial hits)
    def rename(text: str, mapping: dict[str, str]) -> str:
        for old in sorted(mapping, key=len, reverse=True):
            text = re.sub(rf"(?<![\w]){re.escape(old)}(?![\w])", mapping[old], text)
        return text

    id_map: dict[str, str] = {}
    for t, n, _d in inputs:
        id_map[n] = prefix + n
    for v, newv in renamed_values.items():
        id_map[v] = newv
    id_map[cls] = prefix + cls

    body = rename(body, id_map)
    body = re.sub(r"\n{3,}", "\n\n", body)

    # const definitions with the delivered defaults
    consts = [f"//--- {ea.name}  (magic {ea.magic}, {ea.title})"]
    for t, n, default in inputs:
        tname = prefix + t if t in enum_types else t
        default = default.strip()
        if tname == "string" and not default.startswith('"'):
            default = '"' + default.strip('"') + '"'
        consts.append(f"const {tname:<22} {prefix}{n:<26} = {default};")
    consts_txt = "\n".join(consts)

    return {"ea": ea, "class": cls, "class_new": prefix + cls, "body": body,
            "consts": consts_txt, "inputs": inputs,
            "enum_types": enum_types, "renamed_values": renamed_values}


# --------------------------------------------------------------------------
# host template
# --------------------------------------------------------------------------
HOST_TEMPLATE = r'''//+------------------------------------------------------------------+
//| AllEnginesEA.mq5                                                    |
//|                                                                    |
//| GENERATED by portfolio-EA/gen_portfolio_ea.py - do not hand-edit.   |
//| Regenerate with:  python3 portfolio-EA/gen_portfolio_ea.py          |
//|                                                                    |
//| One chart, @@COUNT@@ engines.  MT5 attaches one EA per chart, so     |
//| this host runs the whole book in a single program and validates the |
//| engine's per-strategy state around each strategy's tick.  The       |
//| delivered EAs and the engine headers are NOT modified.              |
//|                                                                    |
//| How state is isolated (see portfolio-EA/README.md):                 |
//|   snapshot/restore : cfg, symbols, indicator sets, position tracks, |
//|                      spread-stat symbol table, news cache           |
//|   per-switch refresh: risk governor + executor Init(), which reload |
//|                      the magic-scoped GlobalVariables they persist  |
//|   shared (market-level, symbol-keyed): spread/slippage/outcome rings |
//|                                                                    |
//| Requires MQL5_Master/Include/*.mqh in <data>\MQL5\Include\ and this  |
//| folder in <data>\MQL5\Experts\portfolio\.                           |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property version   "1.00"
#property description "All engines - runs @@COUNT@@ delivered strategies in one chart (one attach)."
#property description "Order policy: one position per symbol, many symbols. Each engine keeps its magic."
#property description "Comment tag P<magic>| identifies every order. Switches InpRun_<magic> enable/disable."
#property description "Performance tracking lives in the separate PortfolioEA tracker - not here."

#include "..\..\Include\EACommon.mqh"

//--- hooks the generated strategy wrappers call (defined further down)
bool   PortEntryGate(const string sym);   // book caps + per-symbol policy
string PortTagOf(const long magic);       // "P<magic>|" identity prefix

#include "PortfolioStrategies.mqh"

#define PORT_MAX      @@COUNT@@
#define PORT_NEWS_MAX 512      // news events cached per strategy (see README)

//--- portfolio-level inputs ------------------------------------------------
input double InpRiskScale           = 1.0;    // multiplies every engine's delivered riskPct
input string InpOnlyMagics          = "";     // whitelist: run only these magics (empty = all)
input string InpDisableMagics       = "";     // blacklist: never run these magics (e.g. "2035,2027")
input string InpKeepDeliveredPolicy = "2006"; // engines that keep their delivered order policy
input int    InpMaxPerEngine        = 0;      // max open positions per engine (0 = its symbol count)
input int    InpMaxBookPositions    = 0;      // max positions across ALL engines (0 = off)
input int    InpMaxBookPerSymbol    = 0;      // max engines holding one symbol (0 = off)
input double InpBookRiskPct         = 0.0;    // max aggregate open risk, % of balance (0 = off)
input bool   InpQuietInit           = true;   // hide the per-switch 'risk init' log line
input bool   InpSummary             = true;   // log the init summary

//--- per-strategy switches (magic = strategy) ------------------------------
//--- After demo testing, untick a strategy here to disable it - no recompile.
input group "@@GROUP_NAME@@"
@@ENABLE_INPUTS@@

//--- everything the engine keeps for ONE EA --------------------------------
struct SPortState
{
   SEASettings    cfg;
   string         symbols[EA_MAX_SYMBOLS];
   int            symbolCount;
   datetime       lastSignalBar;
   SIndSet        ind[EA_MAX_SYMBOLS];
   int            indCount;
   ENUM_TIMEFRAMES indTf;
   SPosTrack      track[EA_MAX_POSITIONS];
   int            trackCount;
   string         statSym[EA_STAT_MAX_SYMBOLS];
   bool           statUsed[EA_STAT_MAX_SYMBOLS];
   datetime       newsStamp;
   string         newsFile;
};

SPortState   g_portState[PORT_MAX];
CEAStrategy *g_portStrategy[PORT_MAX];
long         g_portMagic[PORT_MAX];
string       g_portName[PORT_MAX];
string       g_portLabel[PORT_MAX];        // cfg.strategyName from the delivered EA
string       g_portSymbolsTxt[PORT_MAX];
string       g_portTfTxt[PORT_MAX];
string       g_portRiskTxt[PORT_MAX];
bool         g_portEnableReq[PORT_MAX];    // its own InpRun_<magic> switch
bool         g_portEnabled[PORT_MAX];      // initialised successfully
bool         g_portAllowed[PORT_MAX];      // passes the switches/whitelist/blacklist
datetime     g_portLastBar[PORT_MAX][EA_MAX_SYMBOLS];
datetime     g_portNews[PORT_MAX][PORT_NEWS_MAX];
int          g_portNewsCount[PORT_MAX];
int          g_portCount = 0;
bool         g_portReady = false;
int          g_portLive = 0;

//+------------------------------------------------------------------+
//| registry (generated)                                              |
//+------------------------------------------------------------------+
void PortBuildRegistry()
{
@@REGISTRY@@
   g_portCount = PORT_MAX;
}

//+------------------------------------------------------------------+
//| the engine globals, saved and restored per strategy                |
//+------------------------------------------------------------------+
void PortSaveState(const int i)
{
   g_portState[i].cfg         = g_eaCfg;
   g_portState[i].symbolCount = g_eaSymbolCount;
   for(int k = 0; k < EA_MAX_SYMBOLS; k++)
      g_portState[i].symbols[k] = g_eaSymbols[k];
   g_portState[i].lastSignalBar = g_eaLastSignalBar;

   g_portState[i].indCount = g_eaIndCount;
   g_portState[i].indTf    = g_eaIndTf;
   for(int k = 0; k < EA_MAX_SYMBOLS; k++)
      g_portState[i].ind[k] = g_eaInd[k];

   g_portState[i].trackCount = g_eaTrackCount;
   for(int k = 0; k < EA_MAX_POSITIONS; k++)
      g_portState[i].track[k] = g_eaTrack[k];

   for(int k = 0; k < EA_STAT_MAX_SYMBOLS; k++)
   {
      g_portState[i].statSym[k]  = g_eaStatSym[k];
      g_portState[i].statUsed[k] = g_eaStatUsed[k];
   }

   g_portState[i].newsStamp = g_eaNewsLoadStamp;
   g_portState[i].newsFile  = g_eaNewsLoadedFile;
   int n = (int)MathMin(g_eaNewsCount, PORT_NEWS_MAX);
   g_portNewsCount[i] = n;
   for(int k = 0; k < n; k++)
      g_portNews[i][k] = g_eaNewsTimes[k];
}

void PortLoadState(const int i)
{
   g_eaCfg         = g_portState[i].cfg;
   g_eaStrategy    = g_portStrategy[i];
   g_eaSymbolCount = g_portState[i].symbolCount;
   for(int k = 0; k < EA_MAX_SYMBOLS; k++)
      g_eaSymbols[k] = g_portState[i].symbols[k];
   g_eaLastSignalBar = g_portState[i].lastSignalBar;

   g_eaIndCount = g_portState[i].indCount;
   g_eaIndTf    = g_portState[i].indTf;
   for(int k = 0; k < EA_MAX_SYMBOLS; k++)
      g_eaInd[k] = g_portState[i].ind[k];

   g_eaTrackCount = g_portState[i].trackCount;
   for(int k = 0; k < EA_MAX_POSITIONS; k++)
      g_eaTrack[k] = g_portState[i].track[k];

   for(int k = 0; k < EA_STAT_MAX_SYMBOLS; k++)
   {
      g_eaStatSym[k]  = g_portState[i].statSym[k];
      g_eaStatUsed[k] = g_portState[i].statUsed[k];
   }

   g_eaNewsLoadStamp  = g_portState[i].newsStamp;
   g_eaNewsLoadedFile = g_portState[i].newsFile;
   g_eaNewsCount      = g_portNewsCount[i];
   ArrayResize(g_eaNewsTimes, g_eaNewsCount);
   for(int k = 0; k < g_eaNewsCount; k++)
      g_eaNewsTimes[k] = g_portNews[i][k];
}

//--- the indicator registry must start empty for each EA_Init, or the
//--- next strategy would append past EA_MAX_SYMBOLS (engine appends at
//--- g_eaIndCount, and the handles created for a previous strategy are
//--- already stored in that strategy's snapshot)
void PortClearEngineState()
{
   g_eaSymbolCount = 0;
   g_eaIndCount    = 0;
   g_eaTrackCount  = 0;
   g_eaLastSignalBar = 0;
   g_eaNewsCount   = 0;
   g_eaNewsLoadedFile = "";
   g_eaNewsLoadStamp  = 0;
   g_eaStrategy    = NULL;
   ArrayResize(g_eaNewsTimes, 0);
   for(int k = 0; k < EA_MAX_SYMBOLS; k++)
   {
      g_eaSymbols[k] = "";
      g_eaInd[k].valid = false;
   }
   for(int k = 0; k < EA_MAX_POSITIONS; k++)
      g_eaTrack[k].ticket = 0;
   for(int k = 0; k < EA_STAT_MAX_SYMBOLS; k++)
   {
      g_eaStatSym[k]  = "";
      g_eaStatUsed[k] = false;
   }
}

//--- the risk governor and executor hold their state privately, but both
//--- persist it to magic-scoped GlobalVariables and reload it in Init(),
//--- so a switch is equivalent to the restart path the engine already supports
void PortRefreshRiskExec()
{
   ENUM_EA_LOG_LEVEL keep = g_eaCfg.logLevel;
   if(InpQuietInit) g_eaCfg.logLevel = EA_LOG_ERRORS;   // silence the per-switch init line
   g_eaRisk.Init();
   if(InpQuietInit) g_eaCfg.logLevel = keep;
   g_eaExec.Init();
}

//+------------------------------------------------------------------+
//| scheduling: work only when a strategy has exposure or a new bar    |
//+------------------------------------------------------------------+
void PortScanExposure(bool &flag[])
{
   for(int i = 0; i < g_portCount; i++) flag[i] = false;

   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      ulong t = PositionGetTicket(p);
      if(t == 0) continue;
      long mg = (long)PositionGetInteger(POSITION_MAGIC);
      for(int i = 0; i < g_portCount; i++)
         if(g_portMagic[i] == mg) { flag[i] = true; break; }
   }
   for(int o = OrdersTotal() - 1; o >= 0; o--)
   {
      ulong t = OrderGetTicket(o);
      if(t == 0) continue;
      long mg = (long)OrderGetInteger(ORDER_MAGIC);
      for(int i = 0; i < g_portCount; i++)
         if(g_portMagic[i] == mg) { flag[i] = true; break; }
   }
}

bool PortNewBar(const int i)
{
   bool any = false;
   for(int k = 0; k < g_portState[i].symbolCount; k++)
   {
      string sym = g_portState[i].symbols[k];
      if(StringLen(sym) == 0) continue;
      datetime t = iTime(sym, g_portState[i].cfg.signalTimeframe, 0);
      if(t == 0) continue;
      if(t != g_portLastBar[i][k])
      {
         g_portLastBar[i][k] = t;
         any = true;
      }
   }
   return any;
}

bool PortInList(const string csv, const long magic)
{
   if(StringLen(csv) == 0) return false;
   string parts[];
   int n = StringSplit(csv, ',', parts);
   for(int i = 0; i < n; i++)
   {
      string p = parts[i];
      StringTrimLeft(p);
      StringTrimRight(p);
      if(StringLen(p) == 0) continue;
      if((long)StringToInteger(p) == magic) return true;
   }
   return false;
}

//--- a strategy runs when it is inside the whitelist (if one was given), its
//--- own InpRun_<magic> switch is ticked, and it is not blacklisted
bool PortAllowed(const int i)
{
   if(StringLen(InpOnlyMagics) > 0 && !PortInList(InpOnlyMagics, g_portMagic[i])) return false;
   if(!g_portEnableReq[i]) return false;
   if(PortInList(InpDisableMagics, g_portMagic[i])) return false;
   return true;
}

//+------------------------------------------------------------------+
//| book-level entry gate (called by every generated strategy wrapper)  |
//|                                                                     |
//| Per-symbol rule: the engine already refuses a symbol that this      |
//| engine is positioned on (EA_SelectPlan -> AllowMultipleOnSymbol()), |
//| so "one order if the symbol is already placed, many symbols" is     |
//| enforced by the engine itself.  This gate adds the book-level caps. |
//+------------------------------------------------------------------+
bool PortKeepDelivered(const long magic)
{
   string parts[];
   int n = StringSplit(InpKeepDeliveredPolicy, ',', parts);
   for(int i = 0; i < n; i++)
   {
      string t = parts[i];
      StringTrimLeft(t);
      StringTrimRight(t);
      if(StringLen(t) > 0 && (long)StringToInteger(t) == magic) return true;
   }
   return false;
}

bool PortIsRegistryMagic(const long magic)
{
   for(int i = 0; i < g_portCount; i++)
      if(g_portMagic[i] == magic) return true;
   return false;
}

int PortCountBookPositions()
{
   int n = 0;
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      ulong t = PositionGetTicket(p);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PortIsRegistryMagic((long)PositionGetInteger(POSITION_MAGIC))) n++;
   }
   return n;
}

int PortCountBookSymbol(const string sym)
{
   int n = 0;
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      ulong t = PositionGetTicket(p);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) == 0) continue;
      if(!PortIsRegistryMagic((long)PositionGetInteger(POSITION_MAGIC))) continue;
      if(PositionGetString(POSITION_SYMBOL) == sym) n++;
   }
   return n;
}

//--- aggregate open risk as % of balance (stop distance x tick value x volume;
//--- positions without a stop are counted at zero - documented approximation)
double PortBookRiskPct()
{
   double base = AccountInfoDouble(ACCOUNT_BALANCE);
   if(base <= 0.0) return 0.0;
   double risk = 0.0;
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      ulong t = PositionGetTicket(p);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(!PortIsRegistryMagic((long)PositionGetInteger(POSITION_MAGIC))) continue;
      double sl = PositionGetDouble(POSITION_SL);
      if(sl <= 0.0) continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      double ts  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
      double tv  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
      if(ts <= 0.0 || tv <= 0.0) continue;
      double dist = MathAbs(PositionGetDouble(POSITION_PRICE_OPEN) - sl);
      risk += dist / ts * tv * PositionGetDouble(POSITION_VOLUME);
   }
   return 100.0 * risk / base;
}

bool PortEntryGate(const string sym)
{
   long magic = (long)g_eaCfg.magic;
   if(PortKeepDelivered(magic)) return true;                     // exempt engine
   if(InpMaxBookPositions > 0 && PortCountBookPositions() >= InpMaxBookPositions) return false;
   if(InpMaxBookPerSymbol > 0 && PortCountBookSymbol(sym) >= InpMaxBookPerSymbol) return false;
   if(InpBookRiskPct > 0.0 && PortBookRiskPct() >= InpBookRiskPct) return false;
   return true;
}

string PortTagOf(const long magic)
{
   return "P" + IntegerToString(magic) + "|";
}

//+------------------------------------------------------------------+
//| lifecycle                                                         |
//+------------------------------------------------------------------+
int OnInit()
{
   PortBuildRegistry();

   for(int i = 0; i < g_portCount; i++)
   {
      g_portEnabled[i] = false;
      g_portAllowed[i] = PortAllowed(i);
      for(int k = 0; k < EA_MAX_SYMBOLS; k++) g_portLastBar[i][k] = 0;
      g_portNewsCount[i] = 0;
   }

   int disabled = 0;
   for(int i = 0; i < g_portCount; i++)
      if(!g_portAllowed[i]) disabled++;

   for(int i = 0; i < g_portCount; i++)
   {
      if(!g_portAllowed[i])
      {
         if(InpSummary)
            PrintFormat("[portfolio] %-45s magic=%-5s DISABLED (switch=%s, list=%s%s)",
                        g_portName[i], IntegerToString(g_portMagic[i]),
                        g_portEnableReq[i] ? "on" : "OFF",
                        InpOnlyMagics, InpDisableMagics);
         continue;
      }

      PortClearEngineState();
      ResetLastError();
      int rc = EA_Init(g_portStrategy[i]);
      if(rc != INIT_SUCCEEDED)
      {
         PrintFormat("[portfolio] %-45s INIT FAILED (rc=%d, err=%d) - disabled",
                     g_portName[i], rc, GetLastError());
         continue;
      }

      g_eaCfg.riskPct *= InpRiskScale;          // portfolio-level scaling only

      //--- order policy: one position per SYMBOL (engine-enforced), as many
      //--- symbols as the engine trades.  46 of the delivered engines cap
      //--- maxOpenPositions at 1 and 8 add oneEntryAccountWide, which would
      //--- limit them to a single position book-wide; the host raises the cap
      //--- to the engine's symbol count.  Engines in InpKeepDeliveredPolicy
      //--- keep the delivered policy (2006 is an intentional ladder).
      if(!PortKeepDelivered(g_portMagic[i]))
      {
         int cap = (InpMaxPerEngine > 0) ? InpMaxPerEngine : g_eaSymbolCount;
         g_eaCfg.maxOpenPositions    = (int)MathMax(1, cap);
         g_eaCfg.oneEntryAccountWide = false;
      }
      PortSaveState(i);
      g_portEnabled[i] = true;
      g_portLive++;

      if(InpSummary)
         PrintFormat("[portfolio] %-45s ready  magic=%-5s tag=%-6s %s %s risk=%.3f%% "
                     "maxOpen=%d oneEntryAccountWide=%s%s",
                     g_portName[i], IntegerToString(g_portMagic[i]), PortTagOf(g_portMagic[i]),
                     g_portSymbolsTxt[i], g_portTfTxt[i], g_eaCfg.riskPct,
                     g_eaCfg.maxOpenPositions, g_eaCfg.oneEntryAccountWide ? "true" : "false",
                     PortKeepDelivered(g_portMagic[i]) ? " (delivered policy kept)" : "");
   }

   if(g_portLive == 0)
   {
      Print("[portfolio] no strategy enabled/initialised - nothing to run");
      return INIT_FAILED;
   }

   g_eaInitialised = true;      // engine's global readiness flag
   g_portReady     = true;
   PrintFormat("[portfolio] %d/%d strategies live on one chart (%d disabled, risk scale %.2f)",
               g_portLive, g_portCount, disabled, InpRiskScale);
   return INIT_SUCCEEDED;
}

void OnTick()
{
   if(!g_portReady) return;

   bool exposure[PORT_MAX];
   PortScanExposure(exposure);

   for(int i = 0; i < g_portCount; i++)
   {
      if(!g_portEnabled[i]) continue;
      if(!exposure[i] && !PortNewBar(i)) continue;

      PortLoadState(i);
      PortRefreshRiskExec();
      EA_Tick();                    // engine pipeline for this strategy
      PortSaveState(i);
   }
}

void OnDeinit(const int reason)
{
   g_portReady = false;
   for(int i = 0; i < g_portCount; i++)
   {
      if(!g_portEnabled[i]) continue;
      PortLoadState(i);
      EA_Deinit(reason);            // tester: one result row per strategy
      if(g_portStrategy[i] != NULL)
      {
         delete g_portStrategy[i];
         g_portStrategy[i] = NULL;
      }
      g_portEnabled[i] = false;
   }
}
//+------------------------------------------------------------------+
'''


# --------------------------------------------------------------------------
def render(engine_values: set[str], specs) -> tuple[str, str, list[dict]]:
    blocks, registry, manifest, wrappers = [], [], [], []
    for i, ea in enumerate(specs):
        tr = transform(ea, engine_values)
        wrappers.append(
            f"//--- portfolio wrapper for {ea.name} (magic {ea.magic}, tag P{ea.magic}|)\n"
            f"class P{ea.magic}_Port : public {tr['class_new']}\n"
            "{\n"
            "public:\n"
            "   virtual bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)\n"
            "   {\n"
            "      if(!PortEntryGate(ctx.symbol)) return false;      "
            "    // book caps (host)\n"
            f"      if(!{tr['class_new']}::BuildPlan(ctx, plan)) return false;\n"
            f"      if(plan.dir != 0) plan.reason = \"P{ea.magic}|\" + plan.reason;  "
            " // identity, front-loaded\n"
            "      return true;\n"
            "   }\n"
            "};\n\n")
        blocks.append(
            "//==================================================================\n"
            f"//| from {ea.name}  |  magic {ea.magic}\n"
            f"//| source document: {ea.doc}\n"
            "//==================================================================\n"
            f"{tr['consts']}\n\n{tr['body'].strip()}\n")
        tf = TIMEFRAME_RE.search(ea.configure)
        tf_label = TF_LABEL.get(tf.group(1) if tf else "PERIOD_M5", "M5")
        label = strategy_label(ea)
        registry.append(
            f"   g_portStrategy[{i}]   = new P{ea.magic}_Port();\n"
            f"   g_portMagic[{i}]      = {ea.magic};\n"
            f"   g_portName[{i}]       = \"{ea.name}\";\n"
            f"   g_portLabel[{i}]      = \"{label}\";\n"
            f"   g_portSymbolsTxt[{i}] = \"{','.join(gtc.symbols_of(ea))}\";\n"
            f"   g_portTfTxt[{i}]      = \"{tf_label}\";\n"
            f"   g_portRiskTxt[{i}]    = \"{ea.common.get('risk', '')}\";\n"
            f"   g_portEnableReq[{i}]  = InpRun_{ea.magic};")
        symbols = gtc.symbols_of(ea)
        manifest.append({
            "index": i, "expert": ea.name, "class": tr["class_new"],
            "magic": ea.magic, "title": ea.title, "doc": ea.doc,
            "strategy": label, "enable_input": f"InpRun_{ea.magic}",
            "tag": f"P{ea.magic}|", "wrapper": f"P{ea.magic}_Port",
            "order_policy": ("delivered (kept)" if ea.magic == 2006
                             else "one per symbol, cap = symbol count"),
            "timeframe": (tf.group(1) if tf else "PERIOD_M5"),
            "timeframe_label": tf_label,
            "risk_pct": ea.common.get("risk", ""),
            "symbols": symbols,
            "inputs": len(tr["inputs"]),
            "renamed_enum_values": sorted(tr["renamed_values"]),
        })

    header = ("//+------------------------------------------------------------------+\n"
              "//| PortfolioStrategies.mqh                                             |\n"
              "//|                                                                     |\n"
              "//| GENERATED by portfolio-EA/gen_portfolio_ea.py - do not hand-edit.    |\n"
              f"//| {len(specs)} strategies taken from MQL5_Master/Experts/additionalEAs/       |\n"
              "//| Class names, enum values and inputs are prefixed per EA (P<magic>_)  |\n"
              "//| so the whole book shares one program namespace.  Strategy logic is   |\n"
              f"//| copied verbatim.  Requires EACommon.mqh to be included first.        |\n"
              "//+------------------------------------------------------------------+\n"
              "#ifndef PORTFOLIO_STRATEGIES_MQH\n"
              "#define PORTFOLIO_STRATEGIES_MQH\n\n")
    note = ("//--- NOTE: the wrappers below call PortEntryGate()/tags; the including\n"
            "//--- translation unit must declare those hooks before this include.\n\n")
    strategies = header + "\n".join(blocks) + "\n" + note + "\n".join(wrappers) + \
        "\n#endif // PORTFOLIO_STRATEGIES_MQH\n"

    def enable_input(m: dict) -> str:
        syms = ",".join(m["symbols"][:4]) + ("..." if len(m["symbols"]) > 4 else "")
        comment = f"{m['magic']} | {m['strategy']} | {syms} {m['timeframe_label']}"
        return f"input bool InpRun_{m['magic']} = true; // {comment}"

    host = (HOST_TEMPLATE
            .replace("@@COUNT@@", str(len(specs)))
            .replace("@@GROUP_NAME@@", "Per-strategy switches - magic = strategy (untick to disable)")
            .replace("@@ENABLE_INPUTS@@", "\n".join(enable_input(m) for m in manifest))
            .replace("@@REGISTRY@@", "\n".join(registry)))
    return strategies, host, manifest


def registry_docs(manifest: list[dict]) -> tuple[str, str]:
    """Human + machine registry: magic -> strategy -> switch, for demo decisions."""
    header = ("| magic | tag | switch (EA input) | EA file | strategy | tf | symbols | "
              "risk % | order policy | source document |")
    sep = "| ---: | --- | --- | --- | --- | --- | --- | ---: | --- | --- |"
    rows = []
    for m in manifest:
        rows.append(f"| {m['magic']} | `{m['tag']}` | `{m['enable_input']}` | {m['expert']} | "
                    f"{m['strategy']} | {m['timeframe_label']} | "
                    f"{','.join(m['symbols'])} | {m['risk_pct']} | {m['order_policy']} | {m['doc']} |")
    md = ("# Strategy registry - magic numbers and switches\n\n"
          "Generated by `portfolio-EA/gen_portfolio_ea.py`. Untick the input in the "
          "second column inside `PortfolioEA` (one chart) to disable that strategy - "
          "no recompile. The same magics are used by the standalone EAs, so demo "
          "results in the terminal map 1:1 to this table.\n\n"
          "Live equivalent at runtime: `MQL5\\Files\\PortfolioEA\\roster.csv` "
          "(magic, strategy, switch, allowed, ready, positions, floating P/L).\n\n"
          + header + "\n" + sep + "\n" + "\n".join(rows) + "\n")

    lines = ["magic,tag,switch,ea,strategy,timeframe,symbols,risk_pct,source_doc"]
    for m in manifest:
        lines.append(",".join([str(m["magic"]), m["tag"], m["enable_input"], m["expert"],
                               m["strategy"], m["timeframe_label"],
                               ";".join(m["symbols"]), str(m["risk_pct"]), m["doc"]]))
    return md, "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="fail if build/ is not up to date")
    args = ap.parse_args()

    gen = gtc.load_generator()
    specs = list(gen.EAS)
    engine_values = engine_enum_values()
    strategies, host, manifest = render(engine_values, specs)

    BUILD.mkdir(parents=True, exist_ok=True)
    reg_md, reg_csv = registry_docs(manifest)
    engines_csv = ("magic,tag,ea,strategy,symbols,timeframe,risk_pct,switch,order_policy,source_doc\n"
                   + "\n".join(
                       ",".join([str(m["magic"]), m["tag"], m["expert"], m["strategy"],
                                 ";".join(m["symbols"]), m["timeframe_label"],
                                 str(m["risk_pct"]), m["enable_input"],
                                 m["order_policy"], m["doc"]]) for m in manifest) + "\n")
    files = {"PortfolioStrategies.mqh": strategies, "AllEnginesEA.mq5": host,
             "STRATEGY_REGISTRY.md": reg_md, "strategy_registry.csv": reg_csv,
             "engines.csv": engines_csv,
             "portfolio_manifest.json": json.dumps({
                 "generated_by": "portfolio-EA/gen_portfolio_ea.py",
                 "strategies": len(specs),
                 "note": "one-chart host; the 65 delivered EAs and the engine are unmodified",
                 "entries": manifest}, indent=2) + "\n"}

    if args.check:
        stale = [n for n, txt in files.items()
                 if not (BUILD / n).exists() or (BUILD / n).read_text(encoding="utf-8") != txt]
        if stale:
            print("STALE: " + ", ".join(stale), file=sys.stderr)
            return 2
        print(f"OK - build/ is current ({len(specs)} strategies)")
        return 0

    originals = sorted(EA_DIR.glob("EA_*.mq5")) + sorted(INCLUDE_DIR.glob("*.mqh"))
    import hashlib
    lines = []
    for f in originals:
        if f.parent == EA_DIR and f.stem not in {e.name for e in specs}:
            continue
        lines.append(f"{hashlib.sha256(f.read_bytes()).hexdigest()}  {f.relative_to(REPO)}")
    files["originals.sha256"] = ("# sha256 of every original file this generator read\n"
                                 "# (the 65 delivered EAs + the engine headers) - the portfolio EA\n"
                                 "# is generated from them and never writes to them\n"
                                 + "\n".join(lines) + "\n")

    for name, txt in files.items():
        (BUILD / name).write_text(txt, encoding="utf-8")

    total_renames = sum(len(m["renamed_enum_values"]) for m in manifest)
    print(f"OK - wrote {BUILD}")
    print(f"     strategies : {len(specs)}")
    print(f"     inputs     : {sum(m['inputs'] for m in manifest)} converted to consts")
    print(f"     enum values: {total_renames} prefixed to avoid collisions")
    print(f"     host       : AllEnginesEA.mq5 (registry, snapshot/restore, scheduler, tags)")
    print("     next       : python3 portfolio-EA/verify_portfolio.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
