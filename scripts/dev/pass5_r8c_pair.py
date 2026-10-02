#!/usr/bin/env python3
"""Pass-5 follow-up: round8_contestant_c's explicit pair-exclusion rule.

Document (docs/research/study_arena/studyarena-round8-contestant-c.md L18):

    "**Instruments:** EURUSD or GBPUSD (trade only the one with the cleanest
     setup; never both on the same day)."

The EA had `maxTradesPerDay = 2` and an M5 sweep signal that fires on either
pair, so it could take EURUSD in the morning and GBPUSD in the afternoon -
exactly the correlated double the document forbids.  Adds a magic-scoped
history gate: once a position has been opened today in the other pair, no
entry follows on this one.
"""
import re
import sys

G = "scripts/gen_additional_eas.py"
src = open(G, encoding="utf-8").read()
key = 'name="EA_studyarena_round8_contestant_c"'
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


# --- plan gate --------------------------------------------------------------
edit(r"if\(ctx\.dayOfWeek < 2 \|\| ctx\.dayOfWeek > 4\) return false;[^\n]*\n",
     "if(ctx.dayOfWeek < 2 || ctx.dayOfWeek > 4) return false;   // doc: Tuesday-Thursday only\n"
     "   if(TradedOtherPairToday(ctx, ctx.symbol)) return false;         // doc: never both pairs on the same day\n",
     1, "pair-exclusion gate")

# --- helper -----------------------------------------------------------------
edit(r"   int LosingStreak\(\)\n",
     "   //--- doc: \"trade only the one with the cleanest setup; never both on the same day\"\n"
     "   bool TradedOtherPairToday(SEAContext &ctx, const string sym)\n"
     "   {\n"
     "      MqlDateTime dt;\n"
     "      if(!TimeToStruct(ctx.nowClock, dt)) return false;\n"
     "      dt.hour = 0; dt.min = 0; dt.sec = 0;\n"
     "      datetime from = EA_ClockToServer(StructToTime(dt));\n"
     "      if(!HistorySelect(from, TimeCurrent())) return false;\n"
     "      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)\n"
     "      {\n"
     "         ulong t = HistoryDealGetTicket(i);\n"
     "         if(t == 0) continue;\n"
     "         if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagicNumber) continue;\n"
     "         if(HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;\n"
     "         string s = HistoryDealGetString(t, DEAL_SYMBOL);\n"
     "         if(StringFind(s, \"EURUSD\") >= 0 && StringFind(sym, \"GBPUSD\") >= 0) return true;\n"
     "         if(StringFind(s, \"GBPUSD\") >= 0 && StringFind(sym, \"EURUSD\") >= 0) return true;\n"
     "      }\n"
     "      return false;\n"
     "   }\n\n"
     "   int LosingStreak()\n",
     1, "TradedOtherPairToday helper")

if failures:
    print("ABORTED - no write. %d failures:" % len(failures))
    for why, err in failures:
        print("   %s\n      -> %s" % (err, why))
    sys.exit(2)
open(G, "w", encoding="utf-8").write(src[:i] + seg + src[j:])
print("OK - r8_c pair-exclusion rule implemented")
