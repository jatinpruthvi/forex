#!/usr/bin/env python3
"""Generate AllChartFanaticsEA.mq5 - a single-chart Master EA running all 47 ChartFanatics strategies.

One chart, 47 strategies.
Loads all 47 ChartFanatics strategies in one program on any chart.
Produces:
- chartfanatics/mql5-eas/AllChartFanaticsEA.mq5
- MQL5/Experts/chartfanatics/AllChartFanaticsEA.mq5
- MQL5/Profiles/Templates/AllChartFanatics.tpl
"""

import json
import os
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
CF_DIR = REPO_ROOT / "chartfanatics"
MANIFEST_PATH = CF_DIR / "mql5-eas" / "manifest.json"
EAS_DIR = CF_DIR / "mql5-eas"
INCLUDE_DIR = REPO_ROOT / "MQL5_Master" / "Include"

APPDATA = os.environ.get("APPDATA", "")
TERMINAL_ID = "930119AA53207C8778B41171FBFFB46F"
MT5_MQL5 = Path(APPDATA) / "MetaQuotes" / "Terminal" / TERMINAL_ID / "MQL5"

INC_MARKER = '#include "..\\..\\Include\\EACommon.mqh"'
HANDLERS_MARKER = "//| MQL5 event handlers"

INPUT_LINE_RE = re.compile(
    r"^\s*input\s+([A-Za-z0-9_]+)\s+([A-Za-z0-9_]+)\s*=\s*([^;]+);", re.M
)
CLASS_RE = re.compile(r"class\s+([A-Za-z0-9_]+)\s*:\s*public\s+CEAStrategy")
ENUM_RE = re.compile(r"enum\s+([A-Za-z0-9_]+)\s*\{([^}]*)\}\s*;", re.M | re.S)
STRUCT_RE = re.compile(r"struct\s+([A-Za-z0-9_]+)", re.M)
IDENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def engine_enum_values() -> set[str]:
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


def transform_ea(ea_file: Path, magic: int, engine_enums: set[str]) -> dict:
    src = ea_file.read_text(encoding="utf-8", errors="replace")
    prefix = f"P{magic}_"

    part = src.split(INC_MARKER, 1)[1]
    body = part.split(HANDLERS_MARKER, 1)[0]

    class_m = CLASS_RE.search(body)
    if not class_m:
        raise ValueError(f"{ea_file.name}: class inheriting CEAStrategy not found")
    orig_class = class_m.group(1)
    new_class = prefix + orig_class

    # Enums
    enums = ENUM_RE.findall(body)
    enum_types = [t for t, _ in enums]
    renamed_enums: dict[str, str] = {}
    for t in enum_types:
        renamed_enums[t] = prefix + t

    for t, ebody in enums:
        clean_ebody = re.sub(r"//.*", "", ebody)
        for item in clean_ebody.split(","):
            item = item.strip()
            if not item:
                continue
            val_name = item.split("=")[0].strip()
            if IDENT_RE.fullmatch(val_name):
                renamed_enums[val_name] = prefix + val_name

    # Structs
    structs = STRUCT_RE.findall(body)
    renamed_structs: dict[str, str] = {}
    for s in structs:
        if s not in {"SEAContext", "SSignalPlan", "SEASettings", "MqlRates", "MqlTick", "MqlTradeRequest", "MqlTradeResult"}:
            renamed_structs[s] = prefix + s

    # Inputs
    inputs = []
    for m in INPUT_LINE_RE.finditer(body):
        t, n, d = m.group(1), m.group(2), m.group(3).strip()
        inputs.append((t, n, d))

    # Remove raw inputs from body
    body_clean = INPUT_LINE_RE.sub("", body)

    # Remove global instance e.g. CCf... g_ea;
    body_clean = re.sub(rf"^\s*{re.escape(orig_class)}\s+\w+\s*;\s*$", "", body_clean, flags=re.M)

    # Identifiers mapping
    id_map: dict[str, str] = {}
    for t, n, _ in inputs:
        id_map[n] = prefix + n
    for k, v in renamed_enums.items():
        id_map[k] = v
    for k, v in renamed_structs.items():
        id_map[k] = v
    id_map[orig_class] = new_class

    # Rename in body (longest first)
    for old in sorted(id_map, key=len, reverse=True):
        body_clean = re.sub(rf"(?<![\w]){re.escape(old)}(?![\w])", id_map[old], body_clean)

    # Extract enums to place before consts
    enum_decl_re = re.compile(r"^\s*enum\s+\w+\s*\{.*?\}\s*;\s*", re.M | re.S)
    enums_txt = "\n\n".join(m.group(0).strip() for m in enum_decl_re.finditer(body_clean))
    body_clean = enum_decl_re.sub("", body_clean)
    body_clean = re.sub(r"\n{3,}", "\n\n", body_clean)

    # Generate const inputs
    const_lines = [f"//--- {ea_file.name} (magic {magic})"]
    for t, n, d in inputs:
        tname = prefix + t if t in enum_types else t
        for k, v in renamed_enums.items():
            d = re.sub(rf"(?<![\w]){re.escape(k)}(?![\w])", v, d)
        if tname == "string" and not d.startswith('"'):
            d = '"' + d.strip('"') + '"'
        const_lines.append(f"const {tname:<22} {prefix}{n:<28} = {d};")
    consts_txt = "\n".join(const_lines)

    # Extract symbols string if present
    syms = "EURUSD"
    for t, n, d in inputs:
        if n == "InpSymbolsToTrade":
            syms = d.strip('"')

    return {
        "ea_name": ea_file.name,
        "magic": magic,
        "class_new": new_class,
        "enums": enums_txt,
        "consts": consts_txt,
        "body": body_clean.strip(),
        "symbols": syms,
    }


def main():
    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        manifest = json.load(f)["eas"]

    print(f"Generating AllChartFanaticsEA for {len(manifest)} strategies...")
    engine_enums = engine_enum_values()

    transformed = []
    for entry in manifest:
        ea_file = EAS_DIR / entry["ea"]
        magic = entry["magic"]
        tr = transform_ea(ea_file, magic, engine_enums)
        tr["strategy_title"] = entry["strategy"]
        tr["timeframe"] = entry["timeframe"]
        transformed.append(tr)

    # Generate strategy blocks and wrappers
    strategy_blocks = []
    wrappers = []
    registry = []
    enable_inputs = []

    for idx, tr in enumerate(transformed):
        magic = tr["magic"]
        cls = tr["class_new"]
        ea_name = tr["ea_name"]
        title = tr["strategy_title"]
        syms = tr["symbols"]
        tf = tr["timeframe"]

        enable_inputs.append(
            f"input bool   InpRun_{magic:<5} = true;   // [{magic}] {title} ({tf})"
        )

        wrappers.append(
            f"//--- wrapper for {ea_name} (magic {magic})\n"
            f"class P{magic}_Port : public {cls}\n"
            f"{{\n"
            f"public:\n"
            f"   virtual bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)\n"
            f"   {{\n"
            f"      if(!PortEntryGate(ctx.symbol)) return false;\n"
            f"      if(!{cls}::BuildPlan(ctx, plan)) return false;\n"
            f"      if(plan.dir != 0) plan.reason = \"P{magic}|\" + plan.reason;\n"
            f"      return true;\n"
            f"   }}\n"
            f"}};\n"
        )

        block = (
            f"//==================================================================\n"
            f"//| from {ea_name}  |  magic {magic}  |  {title}\n"
            f"//==================================================================\n"
        )
        if tr["enums"]:
            block += tr["enums"] + "\n\n"
        block += tr["consts"] + "\n\n"
        block += tr["body"] + "\n"
        strategy_blocks.append(block)

        registry.append(
            f"   g_portStrategy[{idx}]   = new P{magic}_Port();\n"
            f"   g_portMagic[{idx}]      = {magic};\n"
            f"   g_portName[{idx}]       = \"{ea_name.replace('.mq5', '')}\";\n"
            f"   g_portLabel[{idx}]      = \"{title}\";\n"
            f"   g_portSymbolsTxt[{idx}] = \"{syms}\";\n"
            f"   g_portTfTxt[{idx}]      = \"{tf}\";\n"
            f"   g_portEnableReq[{idx}]  = InpRun_{magic};"
        )

    strategies_combined = "\n\n".join(strategy_blocks)
    wrappers_combined = "\n".join(wrappers)
    registry_combined = "\n".join(registry)
    enable_inputs_combined = "\n".join(enable_inputs)

    count = len(manifest)

    host_source = f"""//+------------------------------------------------------------------+
//|                                        AllChartFanaticsEA.mq5    |
//|                                  Copyright 2026, Master Strategy  |
//|                                                                   |
//| All ChartFanatics Strategies - runs all {count} strategies on ONE chart. |
//| Every strategy keeps its own unique magic number (3201-3247).     |
//| Execution: 1-second OnTimer tick distribution across all symbols. |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics Master Portfolio - runs all {count} playbook strategies in one chart."

#include "..\\..\\Include\\EACommon.mqh"

bool   PortEntryGate(const string sym);
string PortTagOf(const long magic);

#define PORT_MAX      {count}
#define PORT_NEWS_MAX 2048

//--- portfolio inputs
input double InpStaticLotSize           = 0.01;   // Default static lot size for ALL strategies (<= 0 to use riskPct sizing)
input double InpRiskScale               = 1.0;    // Multiplies every strategy's risk (if InpStaticLotSize <= 0)
input string InpOnlyMagics              = "";     // Whitelist: run only these magics (empty = all)
input string InpDisableMagics           = "";     // Blacklist: never run these magics (e.g. "3201,3205")
input int    InpMaxBookPositions        = 0;      // Max total positions across ALL strategies (0 or -1 = unlimited)
input int    InpMaxBookPerSymbol        = 0;      // Max total positions on ONE symbol (0 or -1 = unlimited)
input double InpBookRiskPct             = 0.0;    // Max total portfolio open risk % (0 = off)
input bool   InpLogPerformance          = true;   // Log performance breakdown on deinit

input group "=== PER-STRATEGY SWITCHES (TICK TO ENABLE) ==="
{enable_inputs_combined}

//--- state structure per strategy
struct SPortState
{{
   SEASettings     cfg;
   string          symbols[EA_MAX_SYMBOLS];
   int             symbolCount;
   datetime        lastSignalBar;
   SIndSet         ind[EA_MAX_SYMBOLS];
   int             indCount;
   ENUM_TIMEFRAMES indTf;
   SPosTrack       track[EA_MAX_POSITIONS];
   int             trackCount;
   datetime        newsStamp;
   string          newsFile;
   bool            newsServerFrame;
}};

SPortState   g_portState[PORT_MAX];
CEAStrategy *g_portStrategy[PORT_MAX];
long         g_portMagic[PORT_MAX];
string       g_portName[PORT_MAX];
string       g_portLabel[PORT_MAX];
string       g_portSymbolsTxt[PORT_MAX];
string       g_portTfTxt[PORT_MAX];
bool         g_portEnableReq[PORT_MAX];
bool         g_portEnabled[PORT_MAX];
datetime     g_portLastBar[PORT_MAX][EA_MAX_SYMBOLS];
datetime     g_portNews[PORT_MAX][PORT_NEWS_MAX];
int          g_portNewsCount[PORT_MAX];
int          g_portCount = 0;
bool         g_portReady = false;

//=== BEGIN STRATEGIES ===
{strategies_combined}
//=== END STRATEGIES ===

//=== BEGIN WRAPPERS ===
{wrappers_combined}
//=== END WRAPPERS ===

void PortBuildRegistry()
{{
{registry_combined}
   g_portCount = PORT_MAX;
}}

void PortSaveState(const int i)
{{
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

   g_portState[i].newsStamp = g_eaNewsLoadStamp;
   g_portState[i].newsFile  = g_eaNewsLoadedFile;
   g_portState[i].newsServerFrame = g_eaNewsServerFrame;
   int n = (int)MathMin(g_eaNewsCount, PORT_NEWS_MAX);
   g_portNewsCount[i] = n;
   for(int k = 0; k < n; k++)
      g_portNews[i][k] = g_eaNewsTimes[k];
}}

void PortLoadState(const int i)
{{
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

   g_eaNewsLoadStamp   = g_portState[i].newsStamp;
   g_eaNewsLoadedFile  = g_portState[i].newsFile;
   g_eaNewsServerFrame = g_portState[i].newsServerFrame;
   g_eaNewsCount       = g_portNewsCount[i];
   ArrayResize(g_eaNewsTimes, g_eaNewsCount);
   for(int k = 0; k < g_eaNewsCount; k++)
      g_eaNewsTimes[k] = g_portNews[i][k];
}}

void PortClearEngineState()
{{
   g_eaSymbolCount = 0;
   g_eaIndCount    = 0;
   g_eaTrackCount  = 0;
   g_eaLastSignalBar = 0;
   g_eaNewsCount   = 0;
   g_eaNewsLoadedFile = "";
   g_eaNewsLoadStamp  = 0;
   g_eaNewsServerFrame = false;
   g_eaStrategy    = NULL;
   ArrayResize(g_eaNewsTimes, 0);
   for(int k = 0; k < EA_MAX_SYMBOLS; k++)
   {{
      g_eaSymbols[k] = "";
      g_eaInd[k].valid = false;
   }}
   for(int k = 0; k < EA_MAX_POSITIONS; k++)
      g_eaTrack[k].ticket = 0;
}}

void PortRefreshServices()
{{
   ENUM_EA_LOG_LEVEL keep = g_eaCfg.logLevel;
   g_eaCfg.logLevel = EA_LOG_ERRORS;
   g_eaRisk.Init();
   g_eaCfg.logLevel = keep;
   g_eaExec.Init();
}}

bool PortInList(const string csv, const long magic)
{{
   if(StringLen(csv) == 0) return false;
   string parts[];
   int n = StringSplit(csv, ',', parts);
   for(int i = 0; i < n; i++)
   {{
      string p = parts[i];
      StringTrimLeft(p);
      StringTrimRight(p);
      if(StringLen(p) == 0) continue;
      if((long)StringToInteger(p) == magic) return true;
   }}
   return false;
}}

bool PortAllowed(const int i)
{{
   if(StringLen(InpOnlyMagics) > 0 && !PortInList(InpOnlyMagics, g_portMagic[i])) return false;
   if(!g_portEnableReq[i]) return false;
   if(PortInList(InpDisableMagics, g_portMagic[i])) return false;
   return true;
}}

bool PortEntryGate(const string sym)
{{
   if(InpMaxBookPositions > 0)
   {{
      int total = 0;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
         if(PositionGetTicket(p) > 0) total++;
      if(total >= InpMaxBookPositions) return false;
   }}
   if(InpMaxBookPerSymbol > 0)
   {{
      int onSym = 0;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {{
         ulong t = PositionGetTicket(p);
         if(t > 0 && PositionGetString(POSITION_SYMBOL) == sym) onSym++;
      }}
      if(onSym >= InpMaxBookPerSymbol) return false;
   }}
   if(InpBookRiskPct > 0.0)
   {{
      double base = AccountInfoDouble(ACCOUNT_BALANCE);
      if(base > 0.0)
      {{
         double risk = 0.0;
         for(int p = PositionsTotal() - 1; p >= 0; p--)
         {{
            ulong t = PositionGetTicket(p);
            if(t == 0) continue;
            double sl = PositionGetDouble(POSITION_SL);
            if(sl <= 0.0) continue;
            string s = PositionGetString(POSITION_SYMBOL);
            double ts = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_SIZE);
            double tv = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_VALUE);
            if(ts > 0.0 && tv > 0.0)
            {{
               double dist = MathAbs(PositionGetDouble(POSITION_PRICE_OPEN) - sl);
               risk += dist / ts * tv * PositionGetDouble(POSITION_VOLUME);
            }}
         }}
         if((100.0 * risk / base) >= InpBookRiskPct) return false;
      }}
   }}
   return true;
}}

void PortProcess()
{{
   if(!g_portReady) return;
   for(int i = 0; i < g_portCount; i++)
   {{
      if(!g_portEnabled[i] || !PortAllowed(i)) continue;
      PortLoadState(i);
      PortRefreshServices();
      EA_Tick();
      PortSaveState(i);
   }}
}}

int OnInit()
{{
   PrintFormat("[AllChartFanatics] Initialising master EA with %d strategies...", PORT_MAX);
   PortBuildRegistry();

   int initOk = 0;
   for(int i = 0; i < g_portCount; i++)
   {{
      g_portEnabled[i] = false;
      if(!PortAllowed(i)) continue;

      PortClearEngineState();
      g_eaStrategy = g_portStrategy[i];
      int rc = EA_Init(g_portStrategy[i]);
      if(rc != INIT_SUCCEEDED)
      {{
         PrintFormat("[AllChartFanatics] Strategy #%d (Magic %d, %s) init failed (rc=%d, err=%d)",
                     i, g_portMagic[i], g_portName[i], rc, GetLastError());
         EA_IndReleaseAll();
         continue;
      }}
      if(InpStaticLotSize > 0.0)
         g_eaCfg.staticLots = InpStaticLotSize;
      else if(InpRiskScale > 0.0 && InpRiskScale != 1.0)
         g_eaCfg.riskPct *= InpRiskScale;

      PortSaveState(i);
      g_portEnabled[i] = true;
      initOk++;
   }}

   PrintFormat("[AllChartFanatics] Successfully initialised %d of %d strategies", initOk, g_portCount);
   if(initOk == 0) return INIT_FAILED;

   EventSetTimer(1);
   g_portReady = true;
   return INIT_SUCCEEDED;
}}

void OnTick()
{{
   PortProcess();
}}

void OnTimer()
{{
   PortProcess();
}}

void OnDeinit(const int reason)
{{
   g_portReady = false;
   EventKillTimer();
   for(int i = 0; i < g_portCount; i++)
   {{
      if(!g_portEnabled[i]) continue;
      PortLoadState(i);
      EA_Deinit(reason);
      g_portEnabled[i] = false;
   }}
   for(int i = 0; i < g_portCount; i++)
   {{
      if(g_portStrategy[i] != NULL)
      {{
         delete g_portStrategy[i];
         g_portStrategy[i] = NULL;
      }}
   }}
}}
"""

    out_file = EAS_DIR / "AllChartFanaticsEA.mq5"
    out_file.write_text(host_source, encoding="utf-8")
    print(f"[OK] Generated {out_file} ({len(host_source)} chars)")

    # Copy to MT5 terminal
    mt5_target = MT5_MQL5 / "Experts" / "chartfanatics" / "AllChartFanaticsEA.mq5"
    mt5_target.write_text(host_source, encoding="utf-8")
    print(f"[OK] Deployed to {mt5_target}")

    # Generate AllChartFanatics.tpl template
    tpl_source = (
        "<chart>\n"
        "id=0\n"
        "symbol=EURUSD\n"
        "period_type=1\n"
        "period_size=5\n"
        "scale=4\n"
        "mode=1\n"
        "grid=1\n"
        "volume=0\n"
        "scroll=1\n"
        "shift=1\n"
        "bidline=1\n"
        "background_color=0\n"
        "foreground_color=16777215\n"
        "barup_color=65280\n"
        "bardown_color=65280\n"
        "bullcandle_color=0\n"
        "bearcandle_color=16777215\n"
        "<window>\n"
        "height=100\n"
        "fixed_height=0\n"
        "<indicator>\n"
        "name=main\n"
        "</indicator>\n"
        "</window>\n"
        "<expert>\n"
        "name=Experts\\chartfanatics\\AllChartFanaticsEA\n"
        "flags=343\n"
        "window_num=0\n"
        "<inputs>\n"
        "InpStaticLotSize=0.01\n"
        "InpRiskScale=1.0\n"
        "InpOnlyMagics=\n"
        "InpDisableMagics=\n"
        "InpMaxBookPositions=0\n"
        "InpMaxBookPerSymbol=0\n"
        "InpBookRiskPct=0.0\n"
        "InpLogPerformance=true\n"
        + "\n".join(f"InpRun_{tr['magic']}=true" for tr in transformed) + "\n"
        "</inputs>\n"
        "</expert>\n"
        "</chart>\n"
    )

    repo_tpl = CF_DIR / "templates" / "AllChartFanatics.tpl"
    repo_tpl.parent.mkdir(parents=True, exist_ok=True)
    repo_tpl.write_text(tpl_source, encoding="utf-16le")
    print(f"[OK] Saved Repo Template: {repo_tpl}")

    tpl_path = MT5_MQL5 / "Profiles" / "Templates" / "AllChartFanatics.tpl"
    tpl_path.write_text(tpl_source, encoding="utf-16le")
    print(f"[OK] Generated Master Template: {tpl_path}")


if __name__ == "__main__":
    main()
