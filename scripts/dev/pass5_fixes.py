#!/usr/bin/env python3
"""Pass-5 fidelity fixes for scripts/gen_additional_eas.py.

Every edit is a regex anchored inside one spec block (located by name="...")
and asserted to match exactly once, so a drifted anchor fails loudly instead
of patching the wrong EA.  Nothing is written unless every assertion holds.

Each edit cites the source-document rule it restores (or the code/doc
contradiction it removes).  Run:  python3 scripts/dev/pass5_fixes.py
"""
import re
import sys

PATH = "scripts/gen_additional_eas.py"
src = open(PATH, encoding="utf-8").read()
_orig = src


def block_span(name):
    key = 'name="%s"' % name
    i = src.index(key)
    j = src.find("\nadd(", i)
    if j < 0:
        j = len(src)
    return i, j


# (EA name, regex, replacement, expected matches, one-line rationale)
EDITS = [
    # ------------------------------------------------------------------ R5C --
    # doc: "Trail the last 25% on 1H swing structure, hard flat 16:00 unless
    # that runner is already > 2R" -- the runner trail is the 1H chandelier in
    # Manage(); the engine R-trail is not in the doc and only cut it short.
    ("EA_studyarena_round5_contestant_c",
     r"cfg\.trailAtR\s*=\s*1\.00;\s*cfg\.trailDistanceR = 1\.00;[^\n]*",
     "cfg.trailAtR              = 0.0;   // doc: the 1H-swing chandelier in Manage() is the runner trail\n"
     "   cfg.trailDistanceR        = 1.00;",
     1, "R5C: engine R-trail replaced the documented 1H-swing chandelier"),
    # doc: "hard flat 16:00 unless that runner is already > 2R"
    ("EA_studyarena_round5_contestant_c",
     r"   cfg\.sessionEndHour\s*=\s*16;  cfg\.sessionEndMin   = 0;",
     "   cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;\n"
     "   cfg.sessionEndFlat        = true;   // doc: hard flat 16:00 (the >2R runner exemption is not implemented)",
     1, "R5C: session-end flat (16:00) was never armed"),
    # real H1 ATR (ctx.atrH1 exists since the fourth pass; D1/6 kept as fallback)
    ("EA_studyarena_round5_contestant_c",
     r"      double d1 = av\[0\];\n      return \(d1 > 0\.0\) \? d1 / 6\.0 : 0\.0;[^\n]*",
     "      double d1 = av[0];\n"
     "      if(ctx.atrH1 > 0.0) return ctx.atrH1;                 // real H1 ATR\n"
     "      return (d1 > 0.0) ? d1 / 6.0 : 0.0;       // fallback: ~H1 ATR from the daily ATR",
     1, "R5C: chandelier used D1/6 as a fake H1 ATR"),

    # ------------------------------------------------------------------ R7C --
    # doc: "Instrument set: EURUSD, GBPUSD, XAUUSD only."
    ("EA_studyarena_round7_contestant_c",
     r'common=\{"symbols": "EURUSD,GBPUSD", "risk": "0\.75"',
     'common={"symbols": "EURUSD,GBPUSD,XAUUSD", "risk": "0.75"',
     1, "R7C: gold missing from the universe"),
    # doc caps fuel only for EURUSD 35p/GBPUSD 45p; gold fell to the 35p cap
    ("EA_studyarena_round7_contestant_c",
     r"      return \(pips <= InpEurFuelPips\);",
     "      if(StringFind(ctx.symbol, \"XAUUSD\") >= 0) return true;   // doc caps only EURUSD/GBPUSD; the 35-75% ADR ratio governs gold\n"
     "      return (pips <= InpEurFuelPips);",
     1, "R7C: gold could never pass the EURUSD fuel cap"),
    # doc: "Setup - London sweep-and-reclaim, 07:00-10:30 UK"
    ("EA_studyarena_round7_contestant_c",
     r"   p\.sessionFromMin = 7 \* 60; p\.sessionToMin = 12 \* 60;",
     "   p.sessionFromMin = 7 * 60; p.sessionToMin = 10 * 60 + 30;   // doc: 07:00-10:30 UK",
     1, "R7C: entries admitted 1.5h past the documented window"),
    # doc: "Hard flat by 21:00 UK"
    ("EA_studyarena_round7_contestant_c",
     r"   cfg\.sessionEndHour\s*=\s*16;  cfg\.sessionEndMin   = 0;",
     "   cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;   // doc: hard flat by 21:00 UK\n"
     "   cfg.sessionEndFlat        = true;",
     1, "R7C: no 21:00 flat; runners could sit overnight"),
    # doc: the hourly chandelier is the runner's trail
    ("EA_studyarena_round7_contestant_c",
     r"cfg\.trailAtR\s*=\s*1\.00;\s*cfg\.trailDistanceR = 1\.00;",
     "cfg.trailAtR              = 0.0;   // doc: the hourly chandelier in Manage() is the runner trail\n"
     "   cfg.trailDistanceR        = 1.00;",
     1, "R7C: engine R-trail truncated the documented runner tail"),
    # doc: "Trade only Tuesday-Thursday."
    ("EA_studyarena_round7_contestant_c",
     r"plan='''if\(!FuelAvailable\(ctx\)\) return false;",
     "plan='''if(ctx.dayOfWeek < 2 || ctx.dayOfWeek > 4) return false;   // doc: Tuesday-Thursday only\n"
     "   if(!FuelAvailable(ctx)) return false;",
     1, "R7C: day-of-week filter absent"),
    # real H1 ATR
    ("EA_studyarena_round7_contestant_c",
     r"      return \(av\[0\] > 0\.0\) \? av\[0\] / 6\.0 : 0\.0;\n   \}",
     "      if(ctx.atrH1 > 0.0) return ctx.atrH1;                 // real H1 ATR\n"
     "      return (av[0] > 0.0) ? av[0] / 6.0 : 0.0;   // fallback: ~H1 ATR from the daily ATR\n   }",
     1, "R7C: chandelier used D1/6 as a fake H1 ATR"),

    # ------------------------------------------------------------------ R8A --
    # doc: "Instruments: EURUSD, GBPUSD, XAUUSD."
    ("EA_studyarena_round8_contestant_a",
     r'common=\{"symbols": "EURUSD,GBPUSD", "risk": "0\.75"',
     'common={"symbols": "EURUSD,GBPUSD,XAUUSD", "risk": "0.75"',
     1, "R8A: gold missing from the universe"),
    # doc caps fuel only for EURUSD/GBPUSD
    ("EA_studyarena_round8_contestant_a",
     r"      return \(pips <= 35\.0\);[^\n]*",
     "      if(StringFind(ctx.symbol, \"XAUUSD\") >= 0) return true;   // doc caps only EURUSD/GBPUSD; the 35-75% ADR ratio governs gold\n"
     "      return (pips <= 35.0);                             // fuel already burned above this",
     1, "R8A: gold could never pass the EURUSD fuel cap"),
    # doc: "Window: 07:00-10:30 UK"
    ("EA_studyarena_round8_contestant_a",
     r"   p\.sessionFromMin = 7 \* 60; p\.sessionToMin = 12 \* 60;",
     "   p.sessionFromMin = 7 * 60; p.sessionToMin = 10 * 60 + 30;   // doc: 07:00-10:30 UK",
     1, "R8A: entries admitted 1.5h past the documented window"),
    # doc: the mechanical chandelier is the runner's trail
    ("EA_studyarena_round8_contestant_a",
     r"cfg\.trailAtR\s*=\s*1\.00;\s*cfg\.trailDistanceR = 1\.00;",
     "cfg.trailAtR              = 0.0;   // doc: the mechanical chandelier in Manage() is the runner trail\n"
     "   cfg.trailDistanceR        = 1.00;",
     1, "R8A: engine R-trail truncated the documented runner tail"),
    # doc: "Days: Tuesday-Thursday only."
    ("EA_studyarena_round8_contestant_a",
     r"plan='''if\(!RangeQualifies\(ctx\)\) return false;",
     "plan='''if(ctx.dayOfWeek < 2 || ctx.dayOfWeek > 4) return false;   // doc: Tuesday-Thursday only\n"
     "   if(!RangeQualifies(ctx)) return false;",
     1, "R8A: day-of-week filter absent"),
    # real H1 ATR
    ("EA_studyarena_round8_contestant_a",
     r"      return \(av\[0\] > 0\.0\) \? av\[0\] / 6\.0 : 0\.0;\n   \}",
     "      if(ctx.atrH1 > 0.0) return ctx.atrH1;                 // real H1 ATR\n"
     "      return (av[0] > 0.0) ? av[0] / 6.0 : 0.0;   // fallback: ~H1 ATR from the daily ATR\n   }",
     1, "R8A: chandelier used D1/6 as a fake H1 ATR"),

    # ------------------------------------------------------------------ R8B --
    # doc schedule: Asian entries 00:00-03:00, London 07:00-10:00, NY
    # 13:30-15:30; the code admitted entries until 21:00 in every session.
    ("EA_studyarena_round8_contestant_b",
     r"   int rangeFrom = 0, rangeTo = 0, sessFrom = 0, sessTo = 0;\n"
     r"   if\(ctx\.clockMinutes < 7 \* 60\)            \{ rangeFrom = 21 \* 60; rangeTo = 24 \* 60; sessFrom = 0;   sessTo = 7 \* 60; \}\n"
     r"   else if\(ctx\.clockMinutes < 13 \* 60 \+ 30\) \{ rangeFrom = 0;  rangeTo = 7 \* 60;  sessFrom = 7 \* 60;    sessTo = 12 \* 60; \}\n"
     r"   else                                     \{ rangeFrom = 7 \* 60; rangeTo = 13 \* 60; sessFrom = 13 \* 60 \+ 30; sessTo = 21 \* 60; \}",
     "   int rangeFrom = 0, rangeTo = 0, sessFrom = 0, sessTo = 0;\n"
     "   if(ctx.clockMinutes < 7 * 60)            { rangeFrom = 21 * 60; rangeTo = 24 * 60; sessFrom = 0;   sessTo = 3 * 60; }           // doc: Asian entries 00:00-03:00\n"
     "   else if(ctx.clockMinutes < 13 * 60 + 30) { rangeFrom = 0;  rangeTo = 7 * 60;  sessFrom = 7 * 60;    sessTo = 10 * 60; }          // doc: London entries 07:00-10:00\n"
     "   else                                     { rangeFrom = 7 * 60; rangeTo = 13 * 60; sessFrom = 13 * 60 + 30; sessTo = 15 * 60 + 30; }  // doc: NY entries 13:30-15:30\n"
     "   if(ctx.clockMinutes >= sessTo) return false;   // doc: no entries outside the session's entry window",
     1, "R8B: session entry windows were 4h too wide"),
    # doc: "Breakeven stop only after a M5 close beyond +1R (not a touch)"
    ("EA_studyarena_round8_contestant_b",
     r"   cfg\.breakEvenAtR          = 1\.00;\n"
     r"   cfg\.trailAtR              = 2\.00;  cfg\.trailDistanceR = 1\.00;",
     "   cfg.breakEvenAtR          = 1.00;\n"
     "   cfg.breakEvenOnBarClose   = true;   // doc: BE only after an M5 close beyond +1R\n"
     "   cfg.trailAtR              = 0.0;    // doc: the 30% runner trails on the chandelier in Manage()\n"
     "   cfg.trailDistanceR        = 1.00;",
     1, "R8B: touch-based BE + engine R-trail instead of the documented close-based BE and chandelier"),
    # doc: "30% runner trailed at High - 2.5xH1-ATR, hourly, no TP"
    ("EA_studyarena_round8_contestant_b",
     r"      double risk = InpBaseRiskPct \+ \(\(m_setupScore >= InpAplusScore\) \? InpAplusBoostPct : 0\.0\);\n"
     r"      return MathMax\(0\.0, risk / ctx\.riskPct\);\n   \}",
     "      double risk = InpBaseRiskPct + ((m_setupScore >= InpAplusScore) ? InpAplusBoostPct : 0.0);\n"
     "      return MathMax(0.0, risk / ctx.riskPct);\n   }\n\n"
     "   //--- doc: the 30% runner trails at High - 2.5 x H1 ATR, hourly, no TP\n"
     "   void Manage(SEAContext &ctx)\n   {\n"
     "      for(int t = 0; t < g_eaTrackCount; t++)\n      {\n"
     "         if(g_eaTrack[t].symbol != ctx.symbol) continue;\n"
     "         if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;\n"
     "         double entry = PositionGetDouble(POSITION_PRICE_OPEN);\n"
     "         double cur   = PositionGetDouble(POSITION_PRICE_CURRENT);\n"
     "         double risk  = g_eaTrack[t].riskDist;\n"
     "         if(risk <= 0.0) continue;\n"
     "         double rMult = (g_eaTrack[t].dir > 0) ? (cur - entry) / risk : (entry - cur) / risk;\n"
     "         if(rMult < 1.0) continue;\n"
     "         double h1Atr = H1Atr(ctx);\n"
     "         if(h1Atr <= 0.0) continue;\n"
     "         MqlRates r[];\n"
     "         if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 20, r) < 5) continue;\n"
     "         double hh = r[0].high, ll = r[0].low;\n"
     "         for(int i = 1; i < 20; i++) { hh = MathMax(hh, r[i].high); ll = MathMin(ll, r[i].low); }\n"
     "         double newSl = (g_eaTrack[t].dir > 0) ? hh - InpChandelierMult * h1Atr\n"
     "                                               : ll + InpChandelierMult * h1Atr;\n"
     "         double oldSl = PositionGetDouble(POSITION_SL);\n"
     "         if(g_eaTrack[t].dir > 0 && newSl > oldSl) g_eaExec.Modify(g_eaTrack[t].ticket, newSl, 0.0);\n"
     "         if(g_eaTrack[t].dir < 0 && (oldSl == 0.0 || newSl < oldSl))\n"
     "            g_eaExec.Modify(g_eaTrack[t].ticket, newSl, 0.0);\n"
     "      }\n   }\n\n"
     "   double H1Atr(SEAContext &ctx)\n   {\n"
     "      if(ctx.atrH1 > 0.0) return ctx.atrH1;                 // real H1 ATR\n"
     "      double av[];\n"
     "      if(EA_BufN(g_eaInd[ctx.index].hAtrD1, 0, 1, 20, av) < 5) return 0.0;\n"
     "      return (av[0] > 0.0) ? av[0] / 6.0 : 0.0;   // fallback: ~H1 ATR from the daily ATR\n   }",
     1, "R8B: the documented chandelier runner was never implemented"),

    # ------------------------------------------------------------------ R8C --
    # doc: "The 30% Runner: Trail your stop loss exactly 2.5 x H1 ATR behind
    # the highest/lowest point reached. Do not set a Take Profit."
    ("EA_studyarena_round8_contestant_c",
     r"cfg\.trailAtR\s*=\s*2\.00;\s*cfg\.trailDistanceR = 1\.00;",
     "cfg.trailAtR              = 0.0;   // doc: the 30% runner trails on the 2.5 x H1-ATR chandelier in Manage()\n"
     "   cfg.trailDistanceR        = 1.00;",
     1, "R8C: engine R-trail replaced the documented chandelier"),
    # doc: "Hard Time Stop: Close everything manually at 16:30 UK time."
    ("EA_studyarena_round8_contestant_c",
     r"   cfg\.sessionEndHour\s*=\s*16;  cfg\.sessionEndMin   = 0;\n   cfg\.sessionEndFlat        = true;",
     "   cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 30;   // doc: hard time stop 16:30 UK\n"
     "   cfg.sessionEndFlat        = true;",
     1, "R8C: the documented 16:30 hard time stop was 16:00"),
    # doc: "Schedule: Tuesday to Thursday only."
    ("EA_studyarena_round8_contestant_c",
     r"plan='''//--- immediate entry on the reclaim close",
     "plan='''if(ctx.dayOfWeek < 2 || ctx.dayOfWeek > 4) return false;   // doc: Tuesday-Thursday only\n"
     "   //--- immediate entry on the reclaim close",
     1, "R8C: day-of-week filter absent"),
    # real H1 ATR
    ("EA_studyarena_round8_contestant_c",
     r"      return \(av\[0\] > 0\.0\) \? av\[0\] / 6\.0 : 0\.0;\n   \}",
     "      if(ctx.atrH1 > 0.0) return ctx.atrH1;                 // real H1 ATR\n"
     "      return (av[0] > 0.0) ? av[0] / 6.0 : 0.0;   // fallback: ~H1 ATR from the daily ATR\n   }",
     1, "R8C: chandelier used D1/6 as a fake H1 ATR"),

    # --------------------------------------------------------------- R10GEM --
    # doc: "Instruments: EURUSD, GBPUSD, USDJPY, XAUUSD"
    ("EA_studyarena_round10_gemini_3_1_pro_preview_high_reasoning",
     r'common=\{"symbols": "EURUSD,GBPUSD,XAUUSD", "risk": "0\.50"',
     'common={"symbols": "EURUSD,GBPUSD,USDJPY,XAUUSD", "risk": "0.50"',
     1, "R10GEM: USDJPY missing from the declared instrument list"),

    # -------------------------------------------------------------- R10OPUS --
    # doc session x symbol matrix: AUDNZD/EURGBP/AUDUSD (00:00-03:00),
    # EURUSD/GBPUSD/XAUUSD/GER40 (07:00-10:30), XAUUSD/USDJPY/US100
    # (13:30-16:00).  The old universe traded USDCAD (absent from the doc)
    # and none of the Asian or gold sleeves.
    ("EA_studyarena_round10_claude_opus_5_high_reasoning",
     r'common=\{"symbols": "EURUSD,GBPUSD,USDJPY,AUDUSD,USDCAD", "risk": "1\.0"',
     'common={"symbols": "AUDNZD,EURGBP,AUDUSD,EURUSD,GBPUSD,XAUUSD,USDJPY", "risk": "1.0"',
     1, "R10OPUS: universe contradicted the document's session x symbol matrix"),

    # --------------------------------------------------------------- R10QW ---
    # real H1 ATR (the bias slope is quoted as a fraction of H1 ATR)
    ("EA_studyarena_round10_qwen3_8_2_4t_a95b_high_reasoning",
     r"      double h1Atr = \(ctx\.atrD1 > 0\.0\) \? ctx\.atrD1 / 6\.0 : 0\.0;",
     "      double h1Atr = (ctx.atrH1 > 0.0) ? ctx.atrH1\n"
     "                                      : ((ctx.atrD1 > 0.0) ? ctx.atrD1 / 6.0 : 0.0);   // real H1 ATR, daily/6 as fallback",
     1, "R10QW: H1 slope tolerance used D1/6 as a fake H1 ATR"),

    # ---------------------------------------------------------------- R11A ---
    # real H1 ATR (the EMA distance gate is quoted in H1 ATR)
    ("EA_studyarena_round11_contestant_a",
     r"      double h1Atr = \(ctx\.atrD1 > 0\.0\) \? ctx\.atrD1 / 6\.0 : 0\.0;",
     "      double h1Atr = (ctx.atrH1 > 0.0) ? ctx.atrH1\n"
     "                                      : ((ctx.atrD1 > 0.0) ? ctx.atrD1 / 6.0 : 0.0);   // real H1 ATR, daily/6 as fallback",
     1, "R11A: EMA distance gate used D1/6 as a fake H1 ATR"),

    # ---------------------------------------------------------------- R11F ---
    # doc sleeve A: EURUSD, GBPUSD, USDJPY, AUDUSD
    ("EA_studyarena_round11_contestant_f",
     r'common=\{"symbols": "EURUSD,GBPUSD,USDJPY,XAUUSD,EURGBP,AUDNZD,EURCHF", "risk": "0\.24"',
     'common={"symbols": "EURUSD,GBPUSD,USDJPY,AUDUSD,XAUUSD,EURGBP,AUDNZD,EURCHF", "risk": "0.24"',
     1, "R11F: AUDUSD missing from sleeve A's universe"),
    ("EA_studyarena_round11_contestant_f",
     r"   //--- Sleeve A: session-open sweep & reclaim \(the core, M5\)\n"
     r"   if\(TotalForSleeve\(1\) < InpMaxPerSleeve\)",
     "   //--- Sleeve A: session-open sweep & reclaim (the core, M5) - doc: EURUSD, GBPUSD, USDJPY, AUDUSD\n"
     "   if(TotalForSleeve(1) < InpMaxPerSleeve && IsSleeveASymbol(ctx.symbol))",
     1, "R11F: sleeve A was not gated to the document's instruments"),
    ("EA_studyarena_round11_contestant_f",
     r"   if\(TotalForSleeve\(2\) < InpMaxPerSleeve && ctx\.adx14 > 25\.0\)",
     "   if(TotalForSleeve(2) < InpMaxPerSleeve && ctx.adx14 > 25.0 && IsSleeveBSymbol(ctx.symbol))",
     1, "R11F: sleeve B was not gated to the document's instruments"),
    # doc sleeve C: 00:00-06:30, hard flat at 06:30
    ("EA_studyarena_round11_contestant_f",
     r"   if\(TotalForSleeve\(3\) < InpMaxPerSleeve && ctx\.clockMinutes < 7 \* 60 &&\n"
     r"      \(StringFind\(ctx\.symbol, \"EURGBP\"\) >= 0 \|\| StringFind\(ctx\.symbol, \"AUDNZD\"\) >= 0 \|\|\n"
     r"       StringFind\(ctx\.symbol, \"EURCHF\"\) >= 0\)\)[^\n]*",
     "   if(TotalForSleeve(3) < InpMaxPerSleeve && ctx.clockMinutes < 6 * 60 + 30 &&   // doc sleeve C: 00:00-06:30 only\n"
     "      IsSleeveCSymbol(ctx.symbol))",
     1, "R11F: sleeve C admitted entries 06:30-07:00"),
    ("EA_studyarena_round11_contestant_f",
     r"   int m_sleeve;",
     "   bool IsSleeveASymbol(const string sym)\n   {\n"
     "      //--- doc sleeve A: EURUSD, GBPUSD, USDJPY, AUDUSD\n"
     "      return (StringFind(sym, \"EURUSD\") >= 0 || StringFind(sym, \"GBPUSD\") >= 0 ||\n"
     "              StringFind(sym, \"USDJPY\") >= 0 || StringFind(sym, \"AUDUSD\") >= 0);\n   }\n\n"
     "   bool IsSleeveBSymbol(const string sym)\n   {\n"
     "      //--- doc sleeve B: XAUUSD, DAX, US30 (the two indices are outside this broker universe)\n"
     "      return (StringFind(sym, \"XAUUSD\") >= 0);\n   }\n\n"
     "   bool IsSleeveCSymbol(const string sym)\n   {\n"
     "      //--- doc sleeve C: AUDNZD, EURGBP, EURCHF\n"
     "      return (StringFind(sym, \"AUDNZD\") >= 0 || StringFind(sym, \"EURGBP\") >= 0 ||\n"
     "              StringFind(sym, \"EURCHF\") >= 0);\n   }\n\n"
     "   //--- doc sleeve C: hard flat at 06:30 UK (sleeve-C symbols only)\n"
     "   void Manage(SEAContext &ctx)\n   {\n"
     "      if(ctx.clockMinutes < 6 * 60 + 30 || ctx.clockMinutes >= 7 * 60) return;\n"
     "      if(!IsSleeveCSymbol(ctx.symbol)) return;\n"
     "      for(int t = g_eaTrackCount - 1; t >= 0; t--)\n      {\n"
     "         if(g_eaTrack[t].symbol != ctx.symbol) continue;\n"
     "         if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;\n"
     "         g_eaExec.Close(g_eaTrack[t].ticket, \"sleeve C flat 06:30\");\n"
     "      }\n   }\n\n"
     "   int m_sleeve;",
     1, "R11F: sleeve C had no hard flat at 06:30"),

    # ------------------------------------------------------------ R5B-2048 ---
    # doc sleeve B (NY continuation): USDJPY, XAUUSD
    ("EA_studyarena_round5_contestant_b_2048",
     r'common=\{"symbols": "EURGBP,AUDNZD,EURUSD,GBPUSD,USDJPY", "risk": "1\.0"',
     'common={"symbols": "EURGBP,AUDNZD,EURUSD,GBPUSD,USDJPY,XAUUSD", "risk": "1.0"',
     1, "R5B-2048: XAUUSD missing from sleeve B's universe"),
    ("EA_studyarena_round5_contestant_b_2048",
     r"   //--- NY pullback sleeve\n"
     r"   if\(ctx\.clockMinutes >= 13 \* 60 \+ 30 && ctx\.clockMinutes < 16 \* 60\)",
     "   //--- NY pullback sleeve - doc: USDJPY, XAUUSD only\n"
     "   if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 16 * 60 &&\n"
     "      (StringFind(ctx.symbol, \"USDJPY\") >= 0 || StringFind(ctx.symbol, \"XAUUSD\") >= 0))",
     1, "R5B-2048: NY sleeve was open to the Asian-grid pairs"),

    # ------------------------------------------------------------- THE5ERS ---
    # doc: three instrument/session combinations (EURUSD + GBPUSD London,
    # USDJPY New York).  The universe enabled only EURUSD, so the USDJPY
    # window branch in the EA could never fire.
    ("EA_THE5ERS_CHALLENGE_STRATEGY_V2",
     r'common=\{"symbols": "EURUSD", "risk": "0\.5"',
     'common={"symbols": "EURUSD,GBPUSD,USDJPY", "risk": "0.5"',
     1, "THE5ERS-V2: two of the three documented instrument/session combinations were dead"),

    # ------------------------------------------------------------------ R7D --
    # doc strategy 1: 40% at +1R, 30% at +2R, 30% runner; BE only after a
    # close beyond +1R; close the runner by 16:30 London.
    ("EA_studyarena_round7_contestant_d",
     r"   cfg\.partial2AtR           = 2\.00;  cfg\.partial2Pct = 40\.0;\n"
     r"   cfg\.breakEvenAtR          = 1\.00;",
     "   cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 30.0;   // doc: 40% / 30% / 30% runner\n"
     "   cfg.breakEvenAtR          = 1.00;\n"
     "   cfg.breakEvenOnBarClose   = true;    // doc: BE only after a close beyond +1R",
     1, "R7D: ladder paid 40% at +2R (doc 30%) and BE on touch (doc: on close)"),
    ("EA_studyarena_round7_contestant_d",
     r"   cfg\.sessionEndHour\s*=\s*16;  cfg\.sessionEndMin   = 0;",
     "   cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 30;   // doc: close the runner by 16:30 London\n"
     "   cfg.sessionEndFlat        = true;",
     1, "R7D: no 16:30 runner flat"),

    # ----------------------------------------------------------------- R12C --
    # real H1 ATR (the H1 direction slope is quoted in H1 ATR)
    ("EA_studyarena_round12_contestant_c",
     r"      double h1Atr = \(ctx\.atrD1 > 0\.0\) \? ctx\.atrD1 / 6\.0 : 0\.0;",
     "      double h1Atr = (ctx.atrH1 > 0.0) ? ctx.atrH1\n"
     "                                      : ((ctx.atrD1 > 0.0) ? ctx.atrD1 / 6.0 : 0.0);   // real H1 ATR, daily/6 as fallback",
     1, "R12C: H1 slope gate used D1/6 as a fake H1 ATR"),

    # ------------------------------------------------------------- R12QW ----
    # real H1 ATR (the bias slope is quoted as a fraction of H1 ATR)
    ("EA_studyarena_round12_qwen3_8_2_4t_a95b_high_reasoning",
     r"      double h1Atr = \(ctx\.atrD1 > 0\.0\) \? ctx\.atrD1 / 6\.0 : 0\.0;",
     "      double h1Atr = (ctx.atrH1 > 0.0) ? ctx.atrH1\n"
     "                                      : ((ctx.atrD1 > 0.0) ? ctx.atrD1 / 6.0 : 0.0);   // real H1 ATR, daily/6 as fallback",
     1, "R12QW: H1 slope tolerance used D1/6 as a fake H1 ATR"),
]


def main():
    global src
    failures = []
    applied = 0
    seen = {}
    for name, pattern, repl, count, why in EDITS:
        try:
            i, j = block_span(name)
        except ValueError:
            failures.append((name, why, "BLOCK NOT FOUND"))
            continue
        seg = src[i:j]
        m = re.findall(pattern, seg, re.S)
        if len(m) != count:
            failures.append((name, why, "matches %d != %d" % (len(m), count)))
            continue
        src = src[:i] + re.sub(pattern, lambda _m: repl, seg, count=count, flags=re.S) + src[j:]
        applied += 1
        seen[name] = seen.get(name, 0) + 1
    if failures:
        print("ABORTED - no write. %d/%d edits failed:" % (len(failures), len(EDITS)))
        for name, why, err in failures:
            print("   %-58s %s\n      -> %s" % (name, err, why))
        return 2
    open(PATH, "w", encoding="utf-8").write(src)
    print("OK - %d/%d edits applied to %d EAs (%+d bytes)" %
          (applied, len(EDITS), len(seen), len(src) - len(_orig)))
    for name, n in sorted(seen.items()):
        print("   %2d  %s" % (n, name))
    return 0


if __name__ == "__main__":
    sys.exit(main())
