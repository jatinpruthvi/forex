#!/usr/bin/env python3
"""Sixth-pass fixes (#52-#58), generator-side only.

#52 r4_b : London-open and NY sleeves are instrument-gated per the document's
           per-pair matrix (IsLondonPair was dead code; GBPJPY/USDCAD excluded
           because their documented triggers are not implemented).
#53 r12_b: dead RangeBetween() removed - the document has no range-quality rule.
#54 r4_c__1_: dead EndOfMonthWindow() ("Lever 3") wired as a rank bonus.
#55 r10_opus: document's session x symbol matrix + 2-entries/session + 1.5%
           open-risk caps implemented; GER40/US100 added to the universe.
#56 r10_qwen: pass-5 error corrected (the document has NO AUDUSD);
           DAX/US30/NAS100 added; London/NY windows aligned to the document;
           "max 2 per currency group" implemented.
#57 r11_f: sleeve B universe completed with DAX/US30 (broker-skipped if absent).
#58 r11_a: documented "spread + commission + slippage > 0.10R -> reject" wired
           through the engine's cost gate (commission input added).
"""
import sys

GEN = "scripts/gen_additional_eas.py"
src = open(GEN, encoding="utf-8").read()
failures = []
applied = []


def patch_ea(name, edits):
    """Apply edits inside one EA spec; all-or-nothing per EA."""
    global src
    i = src.index('name="%s"' % name)
    j = src.find("\nadd(", i)
    if j < 0:
        j = len(src)
    seg = src[i:j]
    local = []
    for old, new, why in edits:
        n = seg.count(old)
        if n != 1:
            local.append((why, "matches %d != 1" % n))
            continue
        seg = seg.replace(old, new, 1)
    if local:
        for why, err in local:
            failures.append(("%s: %s" % (name, why), err))
        return
    src = src[:i] + seg + src[j:]
    applied.append((name, len(edits)))


# ---------------------------------------------------------------- #52 r4_b --
patch_ea("EA_studyarena_round4_contestant_b", [
    ("   bool IsLondonPair(const string sym)\n"
     "   {\n"
     "      return (StringFind(sym, \"GBPUSD\") >= 0 || StringFind(sym, \"EURUSD\") >= 0 ||\n"
     "              StringFind(sym, \"GBPJPY\") >= 0 || StringFind(sym, \"XAUUSD\") >= 0);\n"
     "   }\n",
     "   //--- doc sleeve 1 (London-open sweep + range-break retest): GBPUSD, EURUSD, XAUUSD.\n"
     "   //--- GBPJPY is the document's momentum-break pair (\"no retest wait\"): that trigger\n"
     "   //--- is not implemented, so the pair is excluded rather than traded with the wrong one.\n"
     "   bool IsLondonPair(const string sym)\n"
     "   {\n"
     "      return (StringFind(sym, \"GBPUSD\") >= 0 || StringFind(sym, \"EURUSD\") >= 0 ||\n"
     "              StringFind(sym, \"XAUUSD\") >= 0);\n"
     "   }\n\n"
     "   //--- doc 13:30-16:00 NY sleeve: XAUUSD (EMA pullback), USDJPY (continuation).\n"
     "   //--- USDCAD's oil-divergence fade is not implemented, so it is excluded.\n"
     "   bool IsNySleevePair(const string sym)\n"
     "   {\n"
     "      return (StringFind(sym, \"XAUUSD\") >= 0 || StringFind(sym, \"USDJPY\") >= 0);\n"
     "   }\n",
     "London/NY sleeve gates"),
    ("   if(ctx.clockMinutes < 10 * 60)\n"
     "   {\n"
     "      SBreakRetestParams br;\n",
     "   if(ctx.clockMinutes < 10 * 60)\n"
     "   {\n"
     "      if(!IsLondonPair(ctx.symbol)) return false;              // doc sleeve 1 instruments\n"
     "      SBreakRetestParams br;\n",
     "London gate call"),
    ("   if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 16 * 60)\n"
     "   {\n"
     "      if(!SigEmaPullback(ctx, PullbackParams(), plan)) return false;\n",
     "   if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 16 * 60)\n"
     "   {\n"
     "      if(!IsNySleevePair(ctx.symbol)) return false;            // doc NY sleeve instruments\n"
     "      if(!SigEmaPullback(ctx, PullbackParams(), plan)) return false;\n",
     "NY gate call"),
])

# ---------------------------------------------------------------- #53 r12_b --
patch_ea("EA_studyarena_round12_contestant_b", [
    ("   bool RangeBetween(const string sym, const int fromMin, const int toMin, double &hi, double &lo)\n"
     "   {\n"
     "      MqlRates r[];\n"
     "      if(EA_Rates(sym, PERIOD_M15, 1, 400, r) < 30) return false;\n"
     "      bool wrap = (fromMin > toMin);\n"
     "      int i = 0;\n"
     "      for(; i < 400; i++)\n"
     "      {\n"
     "         MqlDateTime t;\n"
     "         TimeToStruct(r[i].time, t);\n"
     "         int m = t.hour * 60 + t.min;\n"
     "         bool inWin = wrap ? (m >= fromMin || m < toMin) : (m >= fromMin && m < toMin);\n"
     "         if(inWin) break;\n"
     "      }\n"
     "      if(i >= 400) return false;\n"
     "      hi = 0.0; lo = 0.0;\n"
     "      bool found = false;\n"
     "      for(; i < 400; i++)\n"
     "      {\n"
     "         MqlDateTime t;\n"
     "         TimeToStruct(r[i].time, t);\n"
     "         int m = t.hour * 60 + t.min;\n"
     "         bool inWin = wrap ? (m >= fromMin || m < toMin) : (m >= fromMin && m < toMin);\n"
     "         if(!inWin) break;\n"
     "         if(!found) { hi = r[i].high; lo = r[i].low; found = true; }\n"
     "         else { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }\n"
     "      }\n"
     "      return found;\n"
     "   }\n\n",
     "", "removed dead RangeBetween (no doc rule)"),
])

# ------------------------------------------------------------- #54 r4_c__1_ --
patch_ea("EA_studyarena_round4_contestant_c__1_", [
    ("   ApplyRegime(plan);\n   return true;",
     "   if(EndOfMonthWindow()) plan.score += 5.0;   // Lever 3: end-of-month liquidity-harvest bias (rank only)\n"
     "   ApplyRegime(plan);\n   return true;",
     "wire Lever 3"),
])

# ------------------------------------------------------------- #55 r10_opus --
patch_ea("EA_studyarena_round10_claude_opus_5_high_reasoning", [
    ('common={"symbols": "AUDNZD,EURGBP,AUDUSD,EURUSD,GBPUSD,XAUUSD,USDJPY"',
     'common={"symbols": "AUDNZD,EURGBP,AUDUSD,EURUSD,GBPUSD,XAUUSD,GER40,USDJPY,US100"',
     "universe += GER40, US100"),
    ("input double InpCorrelationCap    = 0.70;  // |rho_60d| cap between open symbols''',",
     "input double InpCorrelationCap    = 0.70;  // |rho_60d| cap between open symbols\n"
     "input double InpMaxOpenRiskPct    = 1.50;  // Doc: max open risk at any instant''',",
     "InpMaxOpenRiskPct"),
    ("   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;\n",
     "   cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;   // doc: Asian window opens 00:00\n",
     "session starts 00:00"),
    ("   if(!SpreadOk(ctx)) return false;\n"
     "   if(!CorrelationOk(ctx)) return false;\n"
     "\n"
     "   SSweepParams p;\n"
     "   p.Reset();\n"
     "   p.rangeFromMin = 0; p.rangeToMin = 7 * 60;\n"
     "   p.sessionFromMin = 7 * 60; p.sessionToMin = 16 * 60;\n",
     "   if(!SpreadOk(ctx)) return false;\n"
     "   if(!CorrelationOk(ctx)) return false;\n"
     "   if(!CorrelationOk(ctx)) return false;\n"
     "\n"
     "   //--- doc session x symbol matrix (UK): 00:00-03:00 AUDNZD/EURGBP/AUDUSD,\n"
     "   //--- 07:00-10:30 EURUSD/GBPUSD/XAUUSD/GER40, 13:30-16:00 XAUUSD/USDJPY/US100\n"
     "   int rangeFrom = 0, rangeTo = 0, sessFrom = 0, sessTo = 0;\n"
     "   if(ctx.clockMinutes < 3 * 60)\n"
     "   {\n"
     "      if(!(StringFind(ctx.symbol, \"AUDNZD\") >= 0 || StringFind(ctx.symbol, \"EURGBP\") >= 0 ||\n"
     "           StringFind(ctx.symbol, \"AUDUSD\") >= 0)) return false;\n"
     "      rangeFrom = 21 * 60; rangeTo = 24 * 60; sessFrom = 0; sessTo = 3 * 60;\n"
     "   }\n"
     "   else if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 10 * 60 + 30)\n"
     "   {\n"
     "      if(!(StringFind(ctx.symbol, \"EURUSD\") >= 0 || StringFind(ctx.symbol, \"GBPUSD\") >= 0 ||\n"
     "           StringFind(ctx.symbol, \"XAUUSD\") >= 0 || StringFind(ctx.symbol, \"GER40\") >= 0)) return false;\n"
     "      rangeFrom = 0; rangeTo = 7 * 60; sessFrom = 7 * 60; sessTo = 10 * 60 + 30;\n"
     "   }\n"
     "   else if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 16 * 60)\n"
     "   {\n"
     "      if(!(StringFind(ctx.symbol, \"XAUUSD\") >= 0 || StringFind(ctx.symbol, \"USDJPY\") >= 0 ||\n"
     "           StringFind(ctx.symbol, \"US100\") >= 0)) return false;\n"
     "      rangeFrom = 7 * 60; rangeTo = 13 * 60 + 30; sessFrom = 13 * 60 + 30; sessTo = 16 * 60;\n"
     "   }\n"
     "   else return false;         // the document has no window outside these three\n"
     "\n"
     "   //--- doc caps: max 3 concurrent, max 2 entries per session, max 1.5% open risk\n"
     "   if(EA_CountPositions(\"\", false) >= 3) return false;\n"
     "   if(EA_OpenRiskPct() >= InpMaxOpenRiskPct) return false;\n"
     "   if(SessionEntries(ctx, sessFrom, sessTo) >= 2) return false;\n"
     "\n"
     "   SSweepParams p;\n"
     "   p.Reset();\n"
     "   p.rangeFromMin = rangeFrom; p.rangeToMin = rangeTo;\n"
     "   p.sessionFromMin = sessFrom; p.sessionToMin = sessTo;\n",
     "session matrix + caps"),
    ("   bool VolatilityRegimeOk(SEAContext &ctx)\n",
     "   //--- doc: max 2 entries per session; counted from the deal history\n"
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
     "   bool VolatilityRegimeOk(SEAContext &ctx)\n",
     "SessionEntries helper"),
])

# ------------------------------------------------------------- #56 r10_qwen --
patch_ea("EA_studyarena_round10_qwen3_8_2_4t_a95b_high_reasoning", [
    ('common={"symbols": "AUDNZD,EURGBP,EURUSD,GBPUSD,AUDUSD,XAUUSD,GBPJPY,USDJPY"',
     'common={"symbols": "AUDNZD,EURGBP,EURUSD,GBPUSD,XAUUSD,GBPJPY,USDJPY,DAX,US30,NAS100"',
     "universe per doc (no AUDUSD; +DAX/US30/NAS100)"),
    ("   int fromMin = 21 * 60, toMin = 24 * 60, sessFrom = 0, sessTo = 6 * 60 + 30;\n"
     "   if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 13 * 60)\n"
     "   { fromMin = 0; toMin = 7 * 60; sessFrom = 7 * 60; sessTo = 12 * 60; }\n"
     "   else if(ctx.clockMinutes >= 13 * 60)\n"
     "   { fromMin = 7 * 60; toMin = 13 * 60; sessFrom = 13 * 60 + 30; sessTo = 21 * 60; }\n",
     "   //--- doc windows (UK): Asian 00:00-06:30, London 07:00-16:30, NY 13:30-20:30\n"
     "   int fromMin = 21 * 60, toMin = 24 * 60, sessFrom = 0, sessTo = 6 * 60 + 30;\n"
     "   if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 13 * 60 + 30)\n"
     "   { fromMin = 0; toMin = 7 * 60; sessFrom = 7 * 60; sessTo = 13 * 60 + 30; }\n"
     "   else if(ctx.clockMinutes >= 13 * 60 + 30)\n"
     "   { fromMin = 7 * 60; toMin = 13 * 60 + 30; sessFrom = 13 * 60 + 30; sessTo = 20 * 60 + 30; }\n",
     "session windows per doc"),
    ("         if(StringFind(ctx.symbol, \"GBPJPY\") >= 0 || StringFind(ctx.symbol, \"GER\") >= 0) return 2;",
     "         if(StringFind(ctx.symbol, \"GBPJPY\") >= 0 || StringFind(ctx.symbol, \"GER\") >= 0 ||\n"
     "            StringFind(ctx.symbol, \"DAX\") >= 0) return 2;",
     "London secondary += DAX"),
    ("   int tier = SessionTier(ctx);\n   if(tier == 0) return false;\n",
     "   int tier = SessionTier(ctx);\n   if(tier == 0) return false;\n"
     "   if(CurrencyGroupCount(ctx.symbol) >= 2) return false;   // doc: max 2 per currency group\n",
     "currency-group cap call"),
    ("   int m_tier;\n",
     "   //--- doc: max 2 concurrent positions per currency group (max 4 total overall;\n"
     "   //--- the EA keeps the stricter maxOpenPositions = 3)\n"
     "   int CurrencyGroupCount(const string sym)\n"
     "   {\n"
     "      if(StringLen(sym) < 6) return 0;\n"
     "      bool idxSym = (StringFind(sym, \"US30\") >= 0 || StringFind(sym, \"NAS\") >= 0 ||\n"
     "                     StringFind(sym, \"DAX\") >= 0 || StringFind(sym, \"GER\") >= 0);\n"
     "      string b1 = StringSubstr(sym, 0, 3), q1 = StringSubstr(sym, 3, 3);\n"
     "      int n = 0;\n"
     "      for(int p = PositionsTotal() - 1; p >= 0; p--)\n"
     "      {\n"
     "         ulong t = PositionGetTicket(p);\n"
     "         if(t == 0) continue;\n"
     "         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;\n"
     "         string s = PositionGetString(POSITION_SYMBOL);\n"
     "         if(StringLen(s) < 6) continue;\n"
     "         bool idxOther = (StringFind(s, \"US30\") >= 0 || StringFind(s, \"NAS\") >= 0 ||\n"
     "                          StringFind(s, \"DAX\") >= 0 || StringFind(s, \"GER\") >= 0);\n"
     "         if(idxSym || idxOther)\n"
     "         {\n"
     "            if(idxSym && idxOther) n++;     // indices count as one exposure group\n"
     "            continue;\n"
     "         }\n"
     "         string b2 = StringSubstr(s, 0, 3), q2 = StringSubstr(s, 3, 3);\n"
     "         if(b1 == b2 || b1 == q2 || q1 == b2 || q1 == q2) n++;\n"
     "      }\n"
     "      return n;\n"
     "   }\n\n"
     "   int m_tier;\n",
     "CurrencyGroupCount helper"),
])

# --------------------------------------------------------------- #57 r11_f --
patch_ea("EA_studyarena_round11_contestant_f", [
    ('common={"symbols": "EURUSD,GBPUSD,USDJPY,AUDUSD,XAUUSD,EURGBP,AUDNZD,EURCHF"',
     'common={"symbols": "EURUSD,GBPUSD,USDJPY,AUDUSD,XAUUSD,EURGBP,AUDNZD,EURCHF,DAX,US30"',
     "universe += DAX, US30"),
    ("      //--- doc sleeve B: XAUUSD, DAX, US30 (the two indices are outside this broker universe)\n"
     "      return (StringFind(sym, \"XAUUSD\") >= 0);\n",
     "      //--- doc sleeve B: XAUUSD, DAX, US30 (the indices resolve only if the broker lists them;\n"
     "      //--- the engine skips any configured symbol the broker does not offer)\n"
     "      return (StringFind(sym, \"XAUUSD\") >= 0 || StringFind(sym, \"DAX\") >= 0 ||\n"
     "              StringFind(sym, \"US30\") >= 0);\n",
     "sleeve B gate"),
])

# --------------------------------------------------------------- #58 r11_a --
patch_ea("EA_studyarena_round11_contestant_a", [
    ("InpMaxEmaDistAtr      = 0.75;  // Distance from the H1 50-EMA (ATR_H1)''',",
     "InpMaxEmaDistAtr      = 0.75;  // Distance from the H1 50-EMA (ATR_H1)\n"
     "input double InpCommissionPerLotRT = 7.0;   // Round-turn commission per lot (broker figure)\n"
     "input double InpMaxCostR           = 0.10;  // Doc: reject when spread + commission exceeds 0.10R''',",
     "cost inputs"),
    ("   cfg.totalDdPct            = InpTotalDdPct;\n",
     "   cfg.totalDdPct            = InpTotalDdPct;\n"
     "   cfg.commissionPerLotRT    = InpCommissionPerLotRT;   // doc: cost gate uses commission\n"
     "   cfg.maxCostR              = InpMaxCostR;\n",
     "cost wiring"),
])

if failures:
    print("FAILED - %d edit(s) did not match; no file written:" % len(failures))
    for who, err in failures:
        print("   %s -> %s" % (who, err))
    sys.exit(2)

open(GEN, "w", encoding="utf-8").write(src)
print("OK - sixth-pass fixes written to %d EAs:" % len(applied))
for n, k in applied:
    print("   %-58s %d edit(s)" % (n.replace("EA_studyarena_", ""), k))
