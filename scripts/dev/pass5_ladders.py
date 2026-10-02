#!/usr/bin/env python3
"""Pass-5 follow-up: fix the doc-quoted partial ladders and the scalping time stop.

1. Engine: `CEAStrategy`'s time stop always closed the trade once the age was
   reached - even a runner at +3R.  The round-10 Claude Fable 5 document (and
   the input comment it generated, `// If not +1R in 30 minutes, close at
   market`) wants the exit only while the premise is dead.  New opt-in
   `SEASettings.timeStopUnlessR` (default 0 = old behaviour): the time stop is
   skipped once the trade is at or above that R multiple.

2. `round10_claude_fable_5`: wires `timeStopUnlessR = 1.0`, adds the document's
   second rung (40 % at +2.5R) and switches BE to close-based (the document
   requires an M1 *close* beyond +1R).

3. `round5_contestant_c`: the document's ladder is 50 % at +1R, 25 % at +2R,
   last 25 % trailed - the second rung was missing, so 50 % of the position ran
   all the way on the chandelier.
"""
import re
import sys

failures = []


def patch(path, edits):
    global failures
    s = open(path, encoding="utf-8").read()
    for old, new, why in edits:
        n = s.count(old)
        if n != 1:
            failures.append((path, why, "matches %d != 1" % n))
            continue
        s = s.replace(old, new, 1)
    return s


EACORE = "MQL5_Master/Include/EACore.mqh"
EATRADE = "MQL5_Master/Include/EATrade.mqh"
GEN = "scripts/gen_additional_eas.py"

core = patch(EACORE, [
    ("   int                  timeStopMinutes;       // 0 = disabled\n",
     "   int                  timeStopMinutes;       // 0 = disabled\n"
     "   double               timeStopUnlessR;      // 0 = unconditional; else skip the time stop at/above this R\n",
     "timeStopUnlessR field"),
    ("      timeStopMinutes        = 0;\n",
     "      timeStopMinutes        = 0;\n"
     "      timeStopUnlessR        = 0.0;\n",
     "timeStopUnlessR default"),
])

trade = patch(EATRADE, [
    ("      if(g_eaCfg.timeStopMinutes > 0)\n",
     "      if(g_eaCfg.timeStopMinutes > 0 &&\n"
     "         !(g_eaCfg.timeStopUnlessR > 0.0 && rMult >= g_eaCfg.timeStopUnlessR))\n",
     "conditional time stop"),
])

gen = open(GEN, encoding="utf-8").read()


def edit_spec(src, name, edits):
    global failures
    i = src.index('name="%s"' % name)
    j = src.find("\nadd(", i)
    if j < 0:
        j = len(src)
    seg = src[i:j]
    for old, new, why in edits:
        n = seg.count(old)
        if n != 1:
            failures.append((name, why, "matches %d != 1" % n))
            continue
        seg = seg.replace(old, new, 1)
    return src[:i] + seg + src[j:]


gen = edit_spec(gen, "EA_studyarena_round5_contestant_c", [
    ("   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;   // 50% off at 1R\n",
     "   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;   // 50% off at 1R\n"
     "   cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 25.0;   // doc: 25% at 2R or the prior-day extreme\n",
     "r5_c 25% at 2R"),
])

gen = edit_spec(gen, "EA_studyarena_round10_claude_fable_5_high_reasoning", [
    ("input int    InpScalpTimeStopMin  = 30;    // If not +1R in 30 minutes, close at market\n",
     "input int    InpScalpTimeStopMin  = 30;    // If not +1R in 30 minutes, close at market\n"
     "input double InpTimeStopUnlessR    = 1.00;  // the 30-min exit is skipped at/above this R\n",
     "fable input"),
    ("   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 60.0;   // 60% off at +1R\n",
     "   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 60.0;   // 60% off at +1R\n"
     "   cfg.partial2AtR           = 2.50;  cfg.partial2Pct = 40.0;   // doc: 40% at +2.5R, then an M5-swing trail\n",
     "fable 40% at 2.5R"),
    ("   cfg.breakEvenAtR          = 1.00;\n",
     "   cfg.breakEvenAtR          = 1.00;\n"
     "   cfg.breakEvenOnBarClose   = true;   // doc: BE only after an M1 close beyond +1R\n",
     "fable BE on close"),
    ("   cfg.timeStopMinutes       = InpScalpTimeStopMin;   // the biggest EV upgrade\n",
     "   cfg.timeStopMinutes       = InpScalpTimeStopMin;   // the biggest EV upgrade\n"
     "   cfg.timeStopUnlessR       = InpTimeStopUnlessR;    // doc: only fires while the trade is below +1R\n",
     "fable time-stop guard"),
])

if failures:
    print("ABORTED - no write. %d failures:" % len(failures))
    for path, why, err in failures:
        print("   %s: %s\n      -> %s" % (path, why, err))
    sys.exit(2)

open(EACORE, "w", encoding="utf-8").write(core)
open(EATRADE, "w", encoding="utf-8").write(trade)
open(GEN, "w", encoding="utf-8").write(gen)
print("OK - time-stop guard + two partial ladders written")
