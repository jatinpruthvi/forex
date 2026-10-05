#!/usr/bin/env python3
"""Pass-5 follow-up: complete the round10_qwen Step-4 rule.

The document's Step 4 requires the displacement candle to *close beyond the
prior (reclaim) candle's midpoint* in addition to the body-ratio test, and an
entry limit cancelled after 3 x M5 candles.  The body test and the 50%
retracement limit existed; the midpoint test and the 15-minute expiry did not.

Adds an opt-in SSweepParams.requireMidpointBreak (default false, so no other
EA changes behaviour) and wires it for round10_qwen together with the
document's 3-candle expiry.  Two-phase: validate every anchor first, write
only when all of them match exactly once.
"""
import re
import sys

G = "scripts/gen_additional_eas.py"
E = "MQL5_Master/Include/EASignals.mqh"

files = {G: open(G, encoding="utf-8").read(), E: open(E, encoding="utf-8").read()}
orig = dict(files)
failures = []


def patch(path, pattern, repl, count, why):
    n = len(re.findall(pattern, files[path], re.S))
    if n != count:
        failures.append((path, why, "matches %d != %d" % (n, count)))
        return
    files[path] = re.sub(pattern, lambda _m: repl, files[path], count=count, flags=re.S)


# ---------------------------------------------------------- engine (sweep) --
patch(E,
      r"   bool     requireDisplacement;\n   bool     tradeBothWays;",
      "   bool     requireDisplacement;\n"
      "   bool     requireMidpointBreak;   // displacement must close beyond the reclaim candle's midpoint\n"
      "   bool     tradeBothWays;",
      1, "SSweepParams field")

patch(E,
      r"      targetR = 1\.5; entryRetrace = 0\.0; requireDisplacement = true;\n"
      r"      tradeBothWays = true; scoreBase = 60\.0;",
      "      targetR = 1.5; entryRetrace = 0.0; requireDisplacement = true;\n"
      "      requireMidpointBreak = false;\n"
      "      tradeBothWays = true; scoreBase = 60.0;",
      1, "SSweepParams.Reset default")

patch(E,
      r"         if\(sweptLow && EA_WickRatio\(sw, \+1\) >= p\.wickRatio && recl\.close > rLo && \(!p\.requireDisplacement \|\| dispUp\)\)",
      "         bool midUp = (!p.requireMidpointBreak) || (disp.close > 0.5 * (recl.high + recl.low));\n"
      "         if(sweptLow && EA_WickRatio(sw, +1) >= p.wickRatio && recl.close > rLo &&\n"
      "            (!p.requireDisplacement || dispUp) && midUp)",
      1, "bullish midpoint condition")

patch(E,
      r"         if\(sweptHigh && EA_WickRatio\(sw, -1\) >= p\.wickRatio && recl\.close < rHi && \(!p\.requireDisplacement \|\| dispDn\)\)",
      "         bool midDn = (!p.requireMidpointBreak) || (disp.close < 0.5 * (recl.high + recl.low));\n"
      "         if(sweptHigh && EA_WickRatio(sw, -1) >= p.wickRatio && recl.close < rHi &&\n"
      "            (!p.requireDisplacement || dispDn) && midDn)",
      1, "bearish midpoint condition")

# ------------------------------------------------------------- generator ----
_qwen_key = 'name="EA_studyarena_round10_qwen3_8_2_4t_a95b_high_reasoning"'
_i = files[G].index(_qwen_key)
_j = files[G].find("\nadd(", _i)
if _j < 0:
    _j = len(files[G])
_seg = files[G][_i:_j]


def patch_qwen(pattern, repl, count, why):
    global _seg
    n = len(re.findall(pattern, _seg, re.S))
    if n != count:
        failures.append((G + " [qwen]", why, "matches %d != %d" % (n, count)))
        return
    _seg = re.sub(pattern, lambda _m: repl, _seg, count=count, flags=re.S)


patch_qwen(r"   p\.entryRetrace = 0\.50; p\.targetR = 2\.0;\n"
           r"   if\(!SigSweepReclaim\(ctx, p, plan\)\) return false;",
           "   p.entryRetrace = 0.50; p.targetR = 2.0;\n"
           "   p.requireMidpointBreak = true;   // doc Step 4: displacement closes beyond the prior candle's midpoint\n"
           "   if(!SigSweepReclaim(ctx, p, plan)) return false;",
           1, "Step-4 midpoint rule")

patch_qwen(r"   cfg\.signalOnNewBarOnly    = true;\n"
           r"   cfg\.partial1AtR           = 1\.00;  cfg\.partial1Pct = 40\.0;",
           "   cfg.signalOnNewBarOnly    = true;\n"
           "   cfg.useLimitEntry         = true;   // doc Step 4: limit at the 50% retracement of the displacement body\n"
           "   cfg.pendingExpiryMinutes  = 15;     // doc Step 4: cancel if unfilled after 3 x M5 candles\n"
           "   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;",
           1, "entry mode + 3-candle expiry")

if not failures:
    files[G] = files[G][:_i] + _seg + files[G][_j:]

if failures:
    print("ABORTED - no write. %d failures:" % len(failures))
    for path, why, err in failures:
        print("   %-46s %s\n      -> %s" % (path, err, why))
    sys.exit(2)

for path, text in files.items():
    if text != orig[path]:
        open(path, "w", encoding="utf-8").write(text)
        print("patched %s (%+d bytes)" % (path, len(text) - len(orig[path])))
print("OK - round10_qwen Step-4 rule implemented")
