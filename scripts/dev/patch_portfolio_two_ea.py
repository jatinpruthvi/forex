#!/usr/bin/env python3
"""One-off patch: portfolio-EA generator -> AllEnginesEA (trader) per PLAN.md.

Decisions taken (user asked for the two-EA layout; the 4 questions were skipped,
so the plan's recommended defaults are applied and documented):

  * trader renamed  PortfolioEA.mq5 -> AllEnginesEA.mq5   (the tracker keeps the
    name PortfolioEA, as the user described it)
  * one position per SYMBOL stays engine-enforced; the host raises each engine's
    maxOpenPositions to its symbol count and clears oneEntryAccountWide so an
    engine may hold one position on each of its symbols (46 engines capped at 1,
    8 THE5ERS engines account-wide).  Engines listed in InpKeepDeliveredPolicy
    (default "2006", the intentional ladder) keep their delivered policy.
  * comment identity: every engine gets a generated wrapper class
    P<magic>_Port that prefixes plan.reason with "P<magic>|" (front-loaded, so
    MT5's 31-char comment limit cannot cut it) and applies the book-level entry
    gate.
  * book caps: InpMaxBookPositions / InpMaxBookPerSymbol / InpBookRiskPct.
  * engines.csv: static magic -> tag -> strategy map for the tracker EA
    (MQL5\Files\PortfolioEA\engines.csv).
  * no runtime files in the trader: roster writer removed (dashboard boundary).
"""
from pathlib import Path
import re

p = Path(__file__).resolve().parents[2] / "portfolio-EA" / "gen_portfolio_ea.py"
s = p.read_text(encoding="utf-8")


def sub(old: str, new: str, count: int = 1) -> None:
    global s
    n = s.count(old)
    assert n == count, f"anchor count {n} != {count} for: {old[:70]!r}"
    s = s.replace(old, new, count)


# ---------------------------------------------------------------- 1. inputs
sub("""//--- portfolio-level inputs ------------------------------------------------
input double InpRiskScale     = 1.0;  // multiplies every strategy's delivered riskPct
input string InpOnlyMagics    = "";   // whitelist: run only these magics (empty = all)
input string InpDisableMagics = "";   // blacklist: never run these magics (e.g. "2035,2027")
input bool   InpQuietInit     = true; // hide the per-switch 'risk init' log line
input bool   InpSummary       = true; // log the init summary + refresh the live roster
input bool   InpRosterFile    = true; // write MQL5\\Files\\PortfolioEA\\roster.csv""",
"""//--- portfolio-level inputs ------------------------------------------------
input double InpRiskScale           = 1.0;    // multiplies every engine's delivered riskPct
input string InpOnlyMagics          = "";     // whitelist: run only these magics (empty = all)
input string InpDisableMagics       = "";     // blacklist: never run these magics (e.g. "2035,2027")
input string InpKeepDeliveredPolicy = "2006"; // engines that keep their delivered order policy
input int    InpMaxPerEngine        = 0;      // max open positions per engine (0 = its symbol count)
input int    InpMaxBookPositions    = 0;      // max positions across ALL engines (0 = off)
input int    InpMaxBookPerSymbol    = 0;      // max engines holding one symbol (0 = off)
input double InpBookRiskPct         = 0.0;    // max aggregate open risk, % of balance (0 = off)
input bool   InpQuietInit           = true;   // hide the per-switch 'risk init' log line
input bool   InpSummary             = true;   // log the init summary""")

# ------------------------------------------------- 2. host hooks / includes
sub("""#include "..\\..\\Include\\EACommon.mqh"
#include "PortfolioStrategies.mqh\"""",
"""#include "..\\..\\Include\\EACommon.mqh"

//--- hooks the generated strategy wrappers call (defined further down)
bool   PortEntryGate(const string sym);   // book caps + per-symbol policy
string PortTagOf(const long magic);       // "P<magic>|" identity prefix

#include "PortfolioStrategies.mqh\"""")

# ------------------------------------------------- 3. globals: drop the stamp
sub("""bool         g_portAllowed[PORT_MAX];      // passes the switches/whitelist/blacklist
datetime     g_portRosterStamp = 0;""",
"""bool         g_portAllowed[PORT_MAX];      // passes the switches/whitelist/blacklist""")

# ------------------------------------- 4. replace the roster with gate helpers
i = s.index("void PortWriteRoster()")
j = s.index("\n}\n", i) + len("\n}\n")
k = s.rindex("//+", 0, s.index("//| live roster"))
roster_block = s[k:j]
assert "PortWriteRoster" in roster_block and len(roster_block) < 3500, len(roster_block)

gate_block = """//+------------------------------------------------------------------+
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
"""
s = s[:k] + gate_block + s[j:]

# ------------------------------------------- 5. drop the roster call sites
sub("""   g_portRosterStamp = TimeLocal();
   PortWriteRoster();           // magic -> strategy map, live and on disk
""", "")
sub("""   //--- refresh the magic -> strategy roster (live/demo only, every 5 min)
   if(!MQLInfoInteger(MQL_TESTER) && InpRosterFile &&
      TimeLocal() - g_portRosterStamp >= 300)
   {
      g_portRosterStamp = TimeLocal();
      PortWriteRoster();
   }

""", "")
sub("""   g_portReady = false;
   PortWriteRoster();               // final snapshot (shows the end state)""",
"""   g_portReady = false;""")

# ------------------------------- 6. per-engine order policy + policy logging
sub("""      g_eaCfg.riskPct *= InpRiskScale;          // portfolio-level scaling only
      PortSaveState(i);""",
"""      g_eaCfg.riskPct *= InpRiskScale;          // portfolio-level scaling only

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
      PortSaveState(i);""")

sub("""         PrintFormat("[portfolio] %-45s ready  magic=%-5I64d %s %s risk=%.3f%%",
                     g_portName[i], g_portMagic[i], g_portSymbolsTxt[i],
                     g_portTfTxt[i], g_eaCfg.riskPct);""",
"""         PrintFormat("[portfolio] %-45s ready  magic=%-5I64d tag=%-6s %s %s risk=%.3f%% "
                     "maxOpen=%d oneEntryAccountWide=%s%s",
                     g_portName[i], g_portMagic[i], PortTagOf(g_portMagic[i]),
                     g_portSymbolsTxt[i], g_portTfTxt[i], g_eaCfg.riskPct,
                     g_eaCfg.maxOpenPositions, g_eaCfg.oneEntryAccountWide ? "true" : "false",
                     PortKeepDelivered(g_portMagic[i]) ? " (delivered policy kept)" : "");""")

# --------------------------------- 7. wrappers + registry class names
sub("""        blocks.append(""", """        wrappers.append(
            f"//--- portfolio wrapper for {ea.name} (magic {ea.magic}, tag P{ea.magic}|)\\n"
            f"class P{ea.magic}_Port : public {tr['class_new']}\\n"
            "{\\n"
            "public:\\n"
            "   virtual bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)\\n"
            "   {\\n"
            "      if(!PortEntryGate(ctx.symbol)) return false;      "
            "    // book caps (host)\\n"
            f"      if(!{tr['class_new']}::BuildPlan(ctx, plan)) return false;\\n"
            f"      if(plan.dir != 0) plan.reason = \\"P{ea.magic}|\\" + plan.reason;  "
            " // identity, front-loaded\\n"
            "      return true;\\n"
            "   }\\n"
            "};\\n\\n")
        blocks.append(""")

sub("""    blocks, registry, manifest = [], [], []""",
    """    blocks, registry, manifest, wrappers = [], [], [], []""")

sub("""            f"   g_portStrategy[{i}]   = new {tr['class_new']}();\\n\"""",
    """            f"   g_portStrategy[{i}]   = new P{ea.magic}_Port();\\n\"""")

# include the wrappers in the generated strategies file
sub("""    strategies = header + "\\n".join(blocks) + "\\n#endif // PORTFOLIO_STRATEGIES_MQH\\n\"""",
    """    note = ("//--- NOTE: the wrappers below call PortEntryGate()/tags; the including\\n"
            "//--- translation unit must declare those hooks before this include.\\n\\n")
    strategies = header + "\\n".join(blocks) + "\\n" + note + "\\n".join(wrappers) + \\
        "\\n#endif // PORTFOLIO_STRATEGIES_MQH\\n\"""")

# manifest: tag + policy + wrapper class
sub("""            "strategy": label, "enable_input": f"InpRun_{ea.magic}",""",
    """            "strategy": label, "enable_input": f"InpRun_{ea.magic}",
            "tag": f"P{ea.magic}|", "wrapper": f"P{ea.magic}_Port",
            "order_policy": ("delivered (kept)" if ea.magic == 2006
                             else "one per symbol, cap = symbol count"),""")

# --------------------------------- 8. engines.csv + renamed host + policy col
sub("""    files = {"PortfolioStrategies.mqh": strategies, "PortfolioEA.mq5": host,""",
    """    files = {"PortfolioStrategies.mqh": strategies, "AllEnginesEA.mq5": host,""")

sub("""             "STRATEGY_REGISTRY.md": reg_md, "strategy_registry.csv": reg_csv,""",
    """             "STRATEGY_REGISTRY.md": reg_md, "strategy_registry.csv": reg_csv,
             "engines.csv": engines_csv,""")

sub("""    reg_md, reg_csv = registry_docs(manifest)""",
    """    reg_md, reg_csv = registry_docs(manifest)
    engines_csv = ("magic,tag,ea,strategy,symbols,timeframe,risk_pct,switch,order_policy,source_doc\\n"
                   + "\\n".join(
                       ",".join([str(m["magic"]), m["tag"], m["expert"], m["strategy"],
                                 ";".join(m["symbols"]), m["timeframe_label"],
                                 str(m["risk_pct"]), m["enable_input"],
                                 m["order_policy"], m["doc"]]) for m in manifest) + "\\n")""")

# registry docs: tag + policy columns
sub("""    header = ("| magic | switch (EA input) | EA file | strategy | tf | symbols | "
              "risk % | source document |")
    sep = "| ---: | --- | --- | --- | --- | --- | ---: | --- |"
    rows = []
    for m in manifest:
        rows.append(f"| {m['magic']} | `{m['enable_input']}` | {m['expert']} | "
                    f"{m['strategy']} | {m['timeframe_label']} | "
                    f"{','.join(m['symbols'])} | {m['risk_pct']} | {m['doc']} |")""",
"""    header = ("| magic | tag | switch (EA input) | EA file | strategy | tf | symbols | "
              "risk % | order policy | source document |")
    sep = "| ---: | --- | --- | --- | --- | --- | --- | ---: | --- | --- |"
    rows = []
    for m in manifest:
        rows.append(f"| {m['magic']} | `{m['tag']}` | `{m['enable_input']}` | {m['expert']} | "
                    f"{m['strategy']} | {m['timeframe_label']} | "
                    f"{','.join(m['symbols'])} | {m['risk_pct']} | {m['order_policy']} | {m['doc']} |")""")

# registries doc text mentions the tracker
sub("""        lines.append(",".join([str(m["magic"]), m["enable_input"], m["expert"],""",
    """        lines.append(",".join([str(m["magic"]), m["tag"], m["enable_input"], m["expert"],""")
sub("""    lines = ["magic,switch,ea,strategy,timeframe,symbols,risk_pct,source_doc"]""",
    """    lines = ["magic,tag,switch,ea,strategy,timeframe,symbols,risk_pct,source_doc"]""")

# ------------------------------------------------------------- 9. header text
sub("""//| PortfolioEA.mq5                                                    |""",
    """//| AllEnginesEA.mq5                                                    |""")
sub("""//| One chart, @@COUNT@@ strategies.  MT5 attaches one EA per chart, so  |""",
    """//| One chart, @@COUNT@@ engines.  MT5 attaches one EA per chart, so     |""")
sub("""#property description "Portfolio host - runs @@COUNT@@ delivered strategies in one chart (one attach).\"""",
    """#property description "All engines - runs @@COUNT@@ delivered strategies in one chart (one attach)."
#property description "Order policy: one position per symbol, many symbols. Each engine keeps its magic."
#property description "Comment tag P<magic>| identifies every order. Switches InpRun_<magic> enable/disable."
#property description "Performance tracking lives in the separate PortfolioEA tracker - not here.\"""")


p.write_text(s, encoding="utf-8")
print("generator patched OK")
