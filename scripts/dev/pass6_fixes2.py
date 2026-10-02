#!/usr/bin/env python3
"""Sixth pass, batch 2 (#59-#66): break-even confirmation semantics + ladders.

Engine:
  * `SEASettings.beConfirmTf` (PERIOD_CURRENT = the EA's signal timeframe) lets
    an EA confirm the break-even move on the timeframe its document names.

Specs:
  #59 round10_gemini  : documented ladder is 60% at +1.5R with BE at +1.5R and a
      12-minute time stop that only fires below +1R - the EA had 50% at +1R,
      BE at +1R and a flat 10-minute stop.
  #60 round8_d        : 40% at +1R / 30% at +2R (EA paid 50% at +1R and left 50%
      riding the trail).
  #61 round12_b       : 50% at +1R / 30% at +2R (EA paid 40%/30%).
  #62 round12_c       : +2R rung (30%) was missing.
  #63 round12_f       : BE only on a candle close (doc), EA was touch-based.
  #64 BE-on-close family: 14 EAs whose documents gate the BE move on a completed
      bar close but ran the touch-based engine BE (opus/kimi/qwen10/r11a/r11f/
      r12a/r12c/r12fable/r12f/r12qwen/r4d/r8a/r8d + r8_c keeps touch per doc).
  #65 THE5ERS_V2      : manual BE read the second-to-last M5 close (one bar late).
  #66 TRIAD_SURVIVE   : the +1R ladder was triggered by a touch; the document
      requires an M5 candle CLOSE.
"""
import re
import sys

failures = []


def patch_file(path, edits):
    global failures
    s = open(path, encoding="utf-8").read()
    for old, new, why in edits:
        n = s.count(old)
        if n != 1:
            failures.append(("%s: %s" % (path, why), "matches %d != 1" % n))
            continue
        s = s.replace(old, new, 1)
    return s


# ------------------------------------------------------------------ engine --
CORE = "MQL5_Master/Include/EACore.mqh"
core = patch_file(CORE, [
    ("   bool                 breakEvenOnBarClose;     // require a completed bar beyond +1R\n",
     "   bool                 breakEvenOnBarClose;     // require a completed bar beyond +1R\n"
     "   ENUM_TIMEFRAMES      beConfirmTf;            // bar used for that confirmation (PERIOD_CURRENT = signal TF)\n",
     "beConfirmTf field"),
    ("      breakEvenOnBarClose    = false;\n",
     "      breakEvenOnBarClose    = false;\n"
     "      beConfirmTf            = PERIOD_CURRENT;\n",
     "beConfirmTf reset"),
])

TRADE = "MQL5_Master/Include/EATrade.mqh"
trade = patch_file(TRADE, [
    ("            MqlRates br[];\n"
     "            if(EA_Rates(sym, g_eaCfg.signalTimeframe, 0, 2, br) >= 2)   // br[1] = last closed bar\n",
     "            MqlRates br[];\n"
     "            ENUM_TIMEFRAMES beTf = (g_eaCfg.beConfirmTf == PERIOD_CURRENT)\n"
     "                                   ? g_eaCfg.signalTimeframe : g_eaCfg.beConfirmTf;\n"
     "            if(EA_Rates(sym, beTf, 0, 2, br) >= 2)   // br[1] = last closed bar of the doc's timeframe\n",
     "beConfirmTf use"),
])

# -------------------------------------------------- #64 BE-on-close wiring --
GEN = "scripts/gen_additional_eas.py"
gen = open(GEN, encoding="utf-8").read()

BE_CLOSE = {
    "EA_studyarena_round10_claude_opus_5_high_reasoning": "   cfg.beConfirmTf            = PERIOD_M5;    // doc: M5 close\n",
    "EA_studyarena_round10_kimi_k3_high_reasoning": "",
    "EA_studyarena_round10_qwen3_8_2_4t_a95b_high_reasoning": "",
    "EA_studyarena_round11_contestant_a": "   cfg.beConfirmTf            = PERIOD_M1;    // doc: M1 close\n",
    "EA_studyarena_round11_contestant_f": "",
    "EA_studyarena_round12_claude_fable_5_high_reasoning": "",
    "EA_studyarena_round12_contestant_a": "",
    "EA_studyarena_round12_contestant_c": "",
    "EA_studyarena_round12_contestant_f": "",
    "EA_studyarena_round12_qwen3_8_2_4t_a95b_high_reasoning": "",
    "EA_studyarena_round4_contestant_d": "",
    "EA_studyarena_round8_contestant_a": "",
    "EA_studyarena_round8_contestant_d": "   cfg.beConfirmTf            = PERIOD_M15;   // doc: M15 close\n",
}

for name, tf_line in BE_CLOSE.items():
    i = gen.index('name="%s"' % name)
    j = gen.find("\nadd(", i)
    seg = gen[i:j]
    m = re.search(r"   cfg\.breakEvenAtR[^\n]*\n", seg)
    if not m:
        failures.append(("%s: BE-on-close wiring" % name, "no breakEvenAtR line"))
        continue
    ins = ("   cfg.breakEvenOnBarClose   = true;    // doc: BE only after a completed bar close\n"
           + tf_line)
    seg = seg[:m.end()] + ins + seg[m.end():]
    gen = gen[:i] + seg + gen[j:]

# ------------------------------------------------------------ #59 gemini ----
def patch_ea(name, edits, src=None):
    global gen
    i = gen.index('name="%s"' % name)
    j = gen.find("\nadd(", i)
    seg = gen[i:j]
    for old, new, why in edits:
        n = seg.count(old)
        if n != 1:
            failures.append(("%s: %s" % (name, why), "matches %d != 1" % n))
            continue
        seg = seg.replace(old, new, 1)
    gen = gen[:i] + seg + gen[j:]


patch_ea("EA_studyarena_round10_gemini_3_1_pro_preview_high_reasoning", [
    ("   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;\n",
     "   cfg.partial1AtR           = 1.50;  cfg.partial1Pct = 60.0;   // doc TP1: 60% at +1.5R\n",
     "TP1 60% at 1.5R"),
    ("   cfg.breakEvenAtR          = 1.00;\n",
     "   cfg.breakEvenAtR          = 1.50;   // doc: BE at TP1 (+1.5R)\n",
     "BE at 1.5R"),
    ("   cfg.timeStopMinutes       = 10;\n",
     "   cfg.timeStopMinutes       = 12;     // doc: 12 minutes (12 M1 candles)\n"
     "   cfg.timeStopUnlessR       = 1.00;   // doc: only while the trade is below +1R\n",
     "12-min conditional time stop"),
])

# ------------------------------------------------------------- #60 r8_d -----
patch_ea("EA_studyarena_round8_contestant_d", [
    ("   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;\n",
     "   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;   // doc: 40% at +1R\n"
     "   cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 30.0;   // doc: 30% at +2R\n",
     "40/30 ladder"),
])

# ------------------------------------------------------------ #61 r12_b -----
patch_ea("EA_studyarena_round12_contestant_b", [
    ("   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;\n",
     "   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;   // doc TP1: 50% at +1R\n",
     "TP1 50%"),
])

# ------------------------------------------------------------ #62 r12_c -----
patch_ea("EA_studyarena_round12_contestant_c", [
    ("   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;\n",
     "   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;\n"
     "   cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 30.0;   // doc +2R: close 30%\n",
     "+2R rung"),
])

# ------------------------------------------------------- #65 THE5ERS_V2 -----
patch_ea("EA_THE5ERS_CHALLENGE_STRATEGY_V2", [
    ("         double d = (g_eaTrack[t].dir > 0) ? (m[1].close - g_eaTrack[t].entry) : (g_eaTrack[t].entry - m[1].close);\n",
     "         double d = (g_eaTrack[t].dir > 0) ? (m[0].close - g_eaTrack[t].entry) : (g_eaTrack[t].entry - m[0].close);\n",
     "last completed M5 close"),
])

# ----------------------------------------------------------- #66 TRIAD ------
patch_ea("EA_TRIAD_SURVIVE", [
    ("         //--- ladder: +1R closes 40% (60% for XAUUSD) and moves the stop to entry\n"
     "         bool isXau = (ctx.symbol == \"XAUUSD\");\n"
     "         if(rMult >= 1.0 && !g_eaTrack[t].p1Done)\n",
     "         //--- doc 2.2: the +1R rung must be confirmed by an M5 candle CLOSE (not a wick)\n"
     "         double rClose = rMult;\n"
     "         MqlRates cbr[];\n"
     "         if(EA_Rates(ctx.symbol, PERIOD_M5, 1, 1, cbr) >= 1)\n"
     "            rClose = ((dir > 0) ? (cbr[0].close - entry) : (entry - cbr[0].close)) / risk;\n"
     "         bool isXau = (ctx.symbol == \"XAUUSD\");\n"
     "         if(rClose >= 1.0 && !g_eaTrack[t].p1Done)\n",
     "M5-close-gated +1R rung"),
])

if failures:
    print("FAILED - %d edit(s) did not match; nothing written:" % len(failures))
    for who, err in failures:
        print("   %s -> %s" % (who, err))
    sys.exit(2)

open(CORE, "w", encoding="utf-8").write(core)
open(TRADE, "w", encoding="utf-8").write(trade)
open(GEN, "w", encoding="utf-8").write(gen)
print("OK - engine beConfirmTf + %d BE-on-close EAs + 6 ladder/semantic fixes" % len(BE_CLOSE))
