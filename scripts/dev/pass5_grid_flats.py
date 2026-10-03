#!/usr/bin/env python3
"""Pass-5 follow-up 2: the documented grid flats that were never armed.

Documents that run a Tokyo/Asian grid sleeve all carry the same risk rule:
"flat by 07:00 UK (or 06:30) - London volume destroys grids".  Three EAs
implement the grid entries but never close them at the flat time, so the legs
can be carried straight into the London expansion the document warns about.

  * round4_contestant_b  - doc: "Time stop: flat by 07:00 UK regardless of P/L."
  * round7_contestant_b  - doc sleeve C: "3 legs, flat by 07:00".
  * round5_contestant_e  - doc: "Flat by 07:00, no exceptions. Never over a weekend."

Each flat closes only the EA's own positions in the current (grid) symbol,
so the trend sleeves are untouched.
"""
import re
import sys

G = "scripts/gen_additional_eas.py"
files = {G: open(G, encoding="utf-8").read()}
failures = []


def patch_block(block_name, pattern, repl, count, why):
    key = 'name="%s"' % block_name
    i = files[G].index(key)
    j = files[G].find("\nadd(", i)
    if j < 0:
        j = len(files[G])
    seg = files[G][i:j]
    n = len(re.findall(pattern, seg, re.S))
    if n != count:
        failures.append((block_name, why, "matches %d != %d" % (n, count)))
        return
    seg = re.sub(pattern, lambda _m: repl, seg, count=count, flags=re.S)
    files[G] = files[G][:i] + seg + files[G][j:]


GRID_FLAT = (
    "   //--- doc: flat by 07:00 UK - London volume destroys grids\n"
    "   void Manage(SEAContext &ctx)\n"
    "   {\n"
    "      if(ctx.clockMinutes < 7 * 60) return;\n"
    "      if(!IsGridPair(ctx.symbol)) return;\n"
    "      for(int t = g_eaTrackCount - 1; t >= 0; t--)\n"
    "      {\n"
    "         if(g_eaTrack[t].symbol != ctx.symbol) continue;\n"
    "         if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;\n"
    "         g_eaExec.Close(g_eaTrack[t].ticket, \"grid flat 07:00\");\n"
    "      }\n"
    "   }\n\n"
)

# --- round4_contestant_b: insert the flat before the grid-pair helper --------
patch_block("EA_studyarena_round4_contestant_b",
            r"   bool IsGridPair\(const string sym\)",
            GRID_FLAT + "   bool IsGridPair(const string sym)",
            1, "Tokyo-grid flat by 07:00 missing")

# --- round7_contestant_b: sleeve C grid is EURGBP / AUDNZD ------------------
patch_block("EA_studyarena_round7_contestant_b",
            r"   int m_sleeve;",
            "   //--- doc sleeve C: flat by 07:00 UK - London volume destroys grids\n"
            "   void Manage(SEAContext &ctx)\n"
            "   {\n"
            "      if(ctx.clockMinutes < 7 * 60) return;\n"
            "      if(StringFind(ctx.symbol, \"EURGBP\") < 0 && StringFind(ctx.symbol, \"AUDNZD\") < 0) return;\n"
            "      for(int t = g_eaTrackCount - 1; t >= 0; t--)\n"
            "      {\n"
            "         if(g_eaTrack[t].symbol != ctx.symbol) continue;\n"
            "         if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;\n"
            "         g_eaExec.Close(g_eaTrack[t].ticket, \"grid flat 07:00\");\n"
            "      }\n"
            "   }\n\n"
            "   int m_sleeve;",
            1, "sleeve-C grid flat by 07:00 missing")

# --- round5_contestant_e: Manage already guards IsGridPair ------------------
patch_block("EA_studyarena_round5_contestant_e",
            r"      if\(ctx\.floatingPl < -InpBasketCapPct / 100\.0 \* ctx\.equity\)\n"
            r"         g_eaExec\.CloseAll\(\"0\.5% basket cap\"\);\n   \}",
            "      if(ctx.floatingPl < -InpBasketCapPct / 100.0 * ctx.equity)\n"
            "         g_eaExec.CloseAll(\"0.5% basket cap\");\n"
            "      //--- doc: flat by 07:00, no exceptions - never hold the grid into London\n"
            "      if(ctx.clockMinutes >= 7 * 60)\n"
            "      {\n"
            "         for(int t = g_eaTrackCount - 1; t >= 0; t--)\n"
            "         {\n"
            "            if(g_eaTrack[t].symbol != ctx.symbol) continue;\n"
            "            if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;\n"
            "            g_eaExec.Close(g_eaTrack[t].ticket, \"grid flat 07:00\");\n"
            "         }\n"
            "      }\n   }",
            1, "grid flat by 07:00 missing")

if failures:
    print("ABORTED - no write. %d failures:" % len(failures))
    for name, why, err in failures:
        print("   %-46s %s\n      -> %s" % (name, err, why))
    sys.exit(2)

open(G, "w", encoding="utf-8").write(files[G])
print("OK - 3 grid-flat fixes written")
