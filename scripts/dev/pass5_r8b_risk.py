#!/usr/bin/env python3
"""Pass-5 follow-up 3: round8_contestant_b's missing documented risk rules.

The document's risk block reads:

    "One position per currency group. Max 2 trades/session, max open risk 1.5%."

None of the three was implemented (the EA only had the shared max-open-positions
and max-trades-per-day counters), so the "<10% DD" guarantee the document builds
on those three rules was not in effect.  Adds:

  * CurrencyGroupId()/GroupBlocked()  - one position per currency group
  * SessionEntries()                  - max 2 entries per session window
  * EA_OpenRiskPct() gate             - max 1.5% open risk (new input)
"""
import re
import sys

G = "scripts/gen_additional_eas.py"
src = open(G, encoding="utf-8").read()
orig = src
key = 'name="EA_studyarena_round8_contestant_b"'
i = src.index(key)
j = src.find("\nadd(", i)
if j < 0:
    j = len(src)
seg = src[i:j]
failures = []


def edit(pattern, repl, count, why):
    global seg
    n = len(re.findall(pattern, seg, re.S))
    if n != count:
        failures.append((why, "matches %d != %d" % (n, count)))
        return
    seg = re.sub(pattern, lambda _m: repl, seg, count=count, flags=re.S)


# --- new input --------------------------------------------------------------
edit(r"(input double InpAplusScore        = 90\.0;[^\n]*\n)",
     r"\1"
     "input double InpMaxOpenRiskPct   = 1.50;  // Doc: max open risk at any instant\n",
     1, "InpMaxOpenRiskPct declaration")

# --- plan gates -------------------------------------------------------------
edit(r"   if\(ctx\.clockMinutes >= sessTo\) return false;[^\n]*\n",
     "   if(ctx.clockMinutes >= sessTo) return false;   // doc: no entries outside the session's entry window\n\n"
     "   //--- doc risk block: one position per currency group, max 2 trades/session, max 1.5% open risk\n"
     "   if(GroupBlocked(ctx.symbol)) return false;\n"
     "   if(SessionEntries(ctx, sessFrom, sessTo) >= 2) return false;\n"
     "   if(EA_OpenRiskPct() >= InpMaxOpenRiskPct) return false;\n",
     1, "plan risk gates")

# --- helpers ---------------------------------------------------------------
edit(r"   //--- doc: the 30% runner trails at High - 2\.5 x H1 ATR, hourly, no TP\n",
     "   int CurrencyGroupId(const string sym)\n"
     "   {\n"
     "      //--- doc: one position per currency group; the USD block includes gold,\n"
     "      //--- USDJPY is counted as the JPY bet, AUDNZD and EURGBP stand alone\n"
     "      if(StringFind(sym, \"JPY\") >= 0) return 2;\n"
     "      if(StringFind(sym, \"USD\") >= 0 || StringFind(sym, \"XAU\") >= 0) return 1;\n"
     "      if(StringFind(sym, \"AUDNZD\") >= 0) return 3;\n"
     "      if(StringFind(sym, \"EURGBP\") >= 0) return 4;\n"
     "      return 5;\n"
     "   }\n\n"
     "   bool GroupBlocked(const string sym)\n"
     "   {\n"
     "      int g = CurrencyGroupId(sym);\n"
     "      for(int p = PositionsTotal() - 1; p >= 0; p--)\n"
     "      {\n"
     "         ulong t = PositionGetTicket(p);\n"
     "         if(t == 0) continue;\n"
     "         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;\n"
     "         if(CurrencyGroupId(PositionGetString(POSITION_SYMBOL)) == g) return true;\n"
     "      }\n"
     "      return false;\n"
     "   }\n\n"
     "   //--- doc: max 2 trades per session; entries are counted from the deal history\n"
     "   int SessionEntries(SEAContext &ctx, const int sessFrom, const int sessTo)\n"
     "   {\n"
     "      MqlDateTime dt;\n"
     "      if(!TimeToStruct(ctx.nowClock, dt)) return 0;\n"
     "      dt.hour = sessFrom / 60; dt.min = sessFrom % 60; dt.sec = 0;\n"
     "      datetime from = EA_ClockToServer(StructToTime(dt));\n"
     "      datetime to   = from + (datetime)((sessTo - sessFrom) * 60);\n"
     "      if(!HistorySelect(from, to)) return 0;\n"
     "      int n = 0;\n"
     "      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)\n"
     "      {\n"
     "         ulong t = HistoryDealGetTicket(i);\n"
     "         if(t == 0) continue;\n"
     "         if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagicNumber) continue;\n"
     "         if(HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;\n"
     "         n++;\n"
     "      }\n"
     "      return n;\n"
     "   }\n\n"
     "   //--- doc: the 30% runner trails at High - 2.5 x H1 ATR, hourly, no TP\n",
     1, "risk-rule helpers")

if failures:
    print("ABORTED - no write. %d failures:" % len(failures))
    for why, err in failures:
        print("   %s\n      -> %s" % (err, why))
    sys.exit(2)

open(G, "w", encoding="utf-8").write(src[:i] + seg + src[j:])
print("OK - r8_b documented risk rules implemented")
