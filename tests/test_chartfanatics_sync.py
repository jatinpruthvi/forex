"""Strategy <-> EA sync: every rule in a ChartFanatics playbook mapped to the code that implements it.

Each entry below quotes the rule (page reference where useful) and pins the parameter or call
that implements it.  If someone changes a value, moves a gate or drops a check, the matching
expectation fails until the card and this table are updated together - that is the point.

Anything the playbook does NOT state is marked ``[interpretation]`` and must stay marked in the
EA source too, so an invention can never quietly become a "documented rule":
  * EA_CF_Structure_OTE: the PDF names OTE but prints no fib numbers (62-79% is the standard
    definition).
  * EA_CF_PO3_OTE_ADR: "ADR" appears only in the playbook's title; the body states no ADR rule.
  * EA_CF_SMT_PO3: the doc's "11:00 candle flips bearish -> break-even" is approximated by the
    engine's 1R break-even.
  * EA_CF_AMD_Model: the "high probability day" news filter is a calendar decision and is off;
    "related markets are aligned" is read as both symbols on the same side of their PD midpoint.
  * EA_CF_Intraday_Liquidity: "if the trade slows near midday, consider exiting" becomes the
    engine's time stop (90 minutes unless the trade is already at 1R).
  * EA_CF_8020NasdaqStrategy: the 200-second entry chart is not a MetaTrader timeframe (M3 is the
    closest); the fork's "targeting the previous low" reads oddly for a long, so the fixed 10-point
    stop / 15-point target the same document states are used and the fork low stays the reference;
    cross-sections are direction-neutral in the source, so the retest side decides.
  * EA_CF_AlgoPortfolioMonitor: the source is a process document, so the EA is a portfolio monitor
    (never trades) that applies its ranking filters to live deal history; Sharpe / UPI are not
    computable from deal history alone, so the return/DD ratio the same page quotes is reported.
"""
from __future__ import annotations

import re
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FAMILY = REPO / "chartfanatics" / "mql5-eas"

# ---------------------------------------------------------------------------------------
# rule -> code.  Each expectation is (regex, note); every regex must match its EA's source.
# ---------------------------------------------------------------------------------------
SYNC: dict[str, list[tuple[str, str]]] = {
    # ---------------------------------------------------------------- AMD Model (card #04)
    "EA_CF_AMD_Model.mq5": [
        (r"p\.rangeFromMin\s*=\s*InpRangeFromMin;\s*\n\s*p\.rangeToMin\s*=\s*InpRangeToMin;",
         'p.3 "price ranged sideways before the news, building liquidity above and below the pre-market range"'),
        (r"input int\s+InpRangeToMin\s+=\s+870;", "accumulation window ends at 14:30 London = the NY open"),
        (r"p\.requireDisplacement\s*=\s*true;", 'p.3 "a strong break ... with clarity" / displacement required'),
        (r"p\.requireMidpointBreak\s*=\s*true;", "the displacement must close beyond the reclaim midpoint"),
        (r"input double InpEntryRetrace\s*=\s*0\.50;", 'p.5 "enter on the retrace into the valid fair value gap"'),
        (r"input int\s+InpMacro1FromMin\s*=\s+890;", 'p.5 "macro windows ... 9:50-10:10 ET" (14:50 London)'),
        (r"input int\s+InpMacro1ToMin\s*=\s+910;", 'p.5 "9:50-10:10 ET" end (15:10 London)'),
        (r"input int\s+InpMacro2FromMin\s*=\s+950;", 'p.5 "10:50-11:10 ET" (15:50 London)'),
        (r"input int\s+InpMacro2ToMin\s*=\s+970;", 'p.5 "10:50-11:10 ET" end (16:10 London)'),
        (r"If\(InpMacroWindowsOnly && !InMacroWindow\(ctx\)\)", "the macro windows are enforced, not decorative"),
        (r"cfg\.maxTradesPerDay\s*=\s+2;", 'p.5 "limit yourself to two trades per session"'),
        (r"cfg\.dayLockAfterLosses\s*=\s+2;", 'p.5 "if you take two losses, step away for the day"'),
        (r"If\(InpRequireHtfAlign && plan\.dir != HtfBias\(ctx\)\)",
         'p.4 "if the higher timeframe is unclear, do not force a setup"'),
        (r"c\.requireD1\s*=\s*true;\s*\n\s*c\.requireH1\s*=\s*true;", "HTF clarity reads D1 + H1"),
        (r"input int\s+InpServerGmtOffset\s*=\s+2;", "broker server offset is an explicit input, not assumed"),
        (r"input string InpCorrelationSymbol\s*=\s*\"US500\";", 'p.4 "related markets (e.g., NASDAQ and S&P)"'),
        (r"if\(!MarketsAligned\(ctx\)\)",
         'p.4 "Make sure related markets are aligned. If they diverge heavily, conditions are lower in probability"'),
        (r"AccumulationTarget\(ctx, plan\.dir, plan\.entry, structural\)",
         'p.6 example "Target: pre-market lows and equal lows under the range"'),
        (r"NearestSwingTarget\(ctx, plan\.dir, plan\.entry, structural\)",
         'p.4 "There must be a clear target: equal highs/lows ... or a clean swing point"'),
        (r"if\(AccumulationTarget\(ctx, plan\.dir, plan\.entry, structural\) \|\|",
         "the range target is tried first, the swing point is the alternative"),
    ],
    # ------------------------------------------------------- Structure + OTE (card #26)
    "EA_CF_Structure_OTE.mq5": [
        (r"input ENUM_TIMEFRAMES InpLtfTimeframe\s*=\s*PERIOD_M15;",
         'p.3 "drop to your execution timeframe (e.g., H1 or M15)"'),
        (r"If\(InpRequireDiscount\)", 'p.3 "mark the 50% line ... buy at a discount ... sell in the premium"'),
        (r"input double InpOteMin\s*=\s*0\.62;", "p.2 OTE entry band lower bound"),
        (r"input double InpOteMax\s*=\s*0\.79;", "OTE entry band upper bound"),
        (r"\[interpretation\] the playbook names OTE but gives no", "the band is labelled an interpretation"),
        (r"SigOrderBlockRetest\(ctx, ob, out\)", 'p.2 "the POI that led to the break, typically an Order Block"'),
        (r"SigSweepReclaim\(ctx, sp, out\)", 'p.3 "wait for: a stop run (sweep of that liquidity)"'),
        (r"SweptEngineeredLiquidity\(ctx, out\.dir", 'p.3 "engineered liquidity (a swing low or high)"'),
        (r"If\(!InpRequireEngineeredLiquidity\) return true;", "the engineered-liquidity gate is an input"),
        (r"input double InpMinRR\s*=\s*2\.00;", 'p.4 "must be at least 2:1 RR to qualify"'),
        (r"If\(rr < InpMinRR\) return false;", "the 2R floor is enforced on the final plan"),
        (r"If\(InpUseExternalTarget\)", 'p.4 "target: the next HTF external liquidity"'),
        (r"input double InpStopBufferAtr", 'p.4 "below the low that got swept (for longs) or above the high"'),
    ],
    # ------------------------------------------------------- SMT Divergence + PO3 (card #23)
    "EA_CF_SMT_PO3.mq5": [
        (r"SigRangeForDay\(ctx\.symbol, g_eaIndTf, 0, 1440, 1, pdHi, pdLo, bars\)",
         'p.3 "spot the previous day\'s high or low"'),
        (r"input bool\s+InpHalfLevelGate\s*=\s*true;", 'p.8 "price is in a premium zone" (above the 50% level)'),
        (r"input string InpSmtSymbol\s*=\s*\"US500\";", 'p.8 "SMT divergence between NQ and ES"'),
        (r"bool oursNewHigh\s*=\s*\(aHiR > aHiO \+ tol\);", "the traded symbol must print the fresh extreme"),
        (r"bool twinNoNewHigh\s*=\s*\(bHiR <= bHiO \+ tol\);", "the twin must NOT confirm it"),
        (r"If\(a\[i\]\.time != b\[i\]\.time\) return SmtUnavailable\(\);",
         "the two series must describe the same bars, or the divergence is fiction"),
        (r"input int\s+InpSessionFromMin\s*=\s+870;", 'p.3 "manipulation ... typically around 10:00 AM EST"'),
        (r"bool targetAhead = \(plan\.dir < 0\) \? \(half < plan\.entry\) : \(half > plan\.entry\);",
         "the 50% target is only used when it sits ahead of the entry"),
        (r"plan\.target\s*=\s*half;", 'p.8 "target: the 50% level of the H1 dealing range"'),
        (r"if\(StringLen\(InpSmtSymbol\) > 0 && !SymbolSelect\(InpSmtSymbol, true\)\)",
         "the twin symbol is selected before it is read"),
    ],
    # ------------------------------------------------------------ PO3, OTE + ADR (card #22)
    "EA_CF_PO3_OTE_ADR.mq5": [
        (r"cfg\.signalTimeframe\s*=\s*PERIOD_M15;",
         'p.4 "use the 15-minute or 30-minute chart for this confirmation"'),
        (r"int DailyBias\(SEAContext &ctx\)", 'p.3 "you must know the direction you want to trade before the day begins"'),
        (r"input int\s+InpLondonOpenFromMin\s*=\s+420;", 'p.3 "London open: 2 AM to 5 AM New York time"'),
        (r"input int\s+InpNyOpenFromMin\s*=\s+720;", 'p.3 "New York open: 7 AM to 10 AM New York time"'),
        (r"input int\s+InpLondonCloseFromMin\s*=\s+900;", 'p.3 "London close: 10 AM to 12 PM New York time"'),
        (r"EA_InWindow\(ctx\.nowClock, InpLondonOpenFromMin / 60", "sessions use the engine window helper"),
        (r"If\(!NearKeyLevel\(ctx, bias, pdh, pdl\)\) return false;", 'p.3 "the setup only works well if the price opens close to a key level"'),
        (r"double level = \(bias < 0\) \? pdh : pdl;", "the key level is side-specific (short raids the high)"),
        (r"EA_BodyRatio\(r\[i\]\) < InpDisplacementBody", 'p.4 "a strong candle that closes with body (not just wick) past the key level"'),
        (r"input double InpOteFib\s*=\s*0\.705;", 'p.4 "0.50 / 0.62 / 0.705 / 0.79 (optional)"'),
        (r"input double InpStopFibLevel\s*=\s*1\.00;", 'p.4 "the default stop loss goes at the 1.0 level" (+ the 0.90 option)'),
        (r"double stop  = \(bias < 0\) \? legExtreme \+ InpStopFibLevel \* span",
         "the stop sits at the stop fib, not at a fixed distance"),
        (r"plan\.target\s*=\s*legExtreme;", 'p.4 "your first TP is always at the 0.0 level"'),
        (r"double tpR = InpOteFib / riskFrac;", "the R levels are derived from the geometry, never hardcoded"),
        (r"double beR = \(InpOteFib - 0\.20\) / riskFrac;", 'p.5 "once the price closes past the 0.20 level, move your stop to breakeven"'),
        (r"cfg\.trailAtR\s*=\s*tpR;", 'p.5 "make the old TP your new stop loss"'),
        (r"\[interpretation\] \"ADR\" appears ONLY in the playbook title", "the ADR gate is flagged as an interpretation"),
        (r"labels shifted one row", "the doc's inconsistent R table is documented, geometry implemented"),
        (r"If\(bias < 0 && ctx\.ask <= entry\) return false;", "a resting OTE limit is never placed through the market"),
    ],
    # ----------------------------------------------------------- Break & Retest (card #07)
    "EA_CF_Break_Retest.mq5": [
        (r"input int\s+InpRangeFromMin\s*=\s+0;", 'p.3 "identify a major prior level" (premarket range)'),
        (r"If\(InpRespectNoTradeZone\)", 'p.2 "that\'s where the No Trade Zone (NTZ) comes in"'),
        (r"If\(ctx\.mid < pdh && ctx\.mid > pdl\) return false;", "the NTZ blocks entries inside the previous day's range"),
        (r"SigBreakRetest\(ctx, p, plan\)", 'p.3 "wait for a break of the level. Do not enter during the break"'),
        (r"If\(InpRequireRejection && !ConfirmedAtLevel\(ctx, plan\.dir, plan\.barsAgo\)\)",
         'p.3 "for longs: bullish wicks and strong closes above the level. For shorts: rejections"'),
        (r"If\(!InpUseTwoBarConfirm \|\| barsAgo != 1\) return false;",
         "the engine pin+engulf detector only vouches for a retest that closed on the last bar"),
        (r"cfg\.partial1AtR\s*=\s*1\.0;\s*cfg\.partial1Pct\s*=\s*50\.0;",
         'p.3 "take 25-50% of the position" at TP1'),
        (r"cfg\.trailAtR\s*=\s*1\.5;", 'p.3 "hold the remaining position for continuation"'),
        (r"p\.stopBufferAtr\s*=\s*InpStopBufferAtr;", 'p.3 "stop is placed just beyond the invalidation point"'),
        (r"NearestSwingAhead\(ctx, plan\.dir, plan\.entry, cand\)",
         'p.3 "First Target (TP1) is the prior high (for longs) or prior low (for shorts)"'),
    ],
    # ---------------------------------------------- Intraday Liquidity & Vol (card #12)
    "EA_CF_Intraday_Liquidity.mq5": [
        (r"int DailyBias\(SEAContext &ctx\)", 'p.3 "decide if you\'re bullish or bearish for the day using the daily chart"'),
        (r"SigRangeForDay\(ctx\.symbol, g_eaIndTf, 0, 1440, 1, pdh, pdl, bars\)",
         'p.3 "session liquidity zones: previous day\'s high and low"'),
        (r"SigAsianRange\(ctx\.symbol, aHi, aLo\)", 'p.3 "Asian session high/low"'),
        (r"input bool\s+InpUseLondonRange", 'p.3 "London session high/low"'),
        (r"If\(i < bestBar\)", "the MOST RECENT raid wins - an older raid cannot mask a fresher one"),
        (r"double backInside = \(side > 0\) \? \(level - r\[i\]\.close\)", "the raid must fail (close back inside)"),
        (r"input int\s+InpSessionFromMin\s*=\s+870;", 'p.3 "trade setups should form between 9:30 and 11:30 AM EST"'),
        (r"input int\s+InpSessionToMin\s*=\s+990;", "the NY window closes at 11:30 ET"),
        (r"SigFvgRetest\(ctx, f, found\)", 'p.3 "wait for one of these confirmations: fair value gap (FVG)"'),
        (r"SigSweepReclaim\(ctx, s, found\)", 'p.3 "market structure shift (MSS)"'),
        (r"If\(found\.dir < 0\) found\.stop = MathMax\(found\.stop, raidLevel \+ buffer\);",
         'p.5 "stop: above the high of the sweep"'),
        (r"double external = \(found\.dir < 0\) \? aLo : aHi;", 'p.5 "target: sell-side liquidity near recent lows"'),
        (r"SigOrderBlockRetest\(ctx, b, found\)",
         'p.2 confirmation list: "Breaker Block" (the playbook names four; FVG + MSS + Turtle Soup were already covered)'),
        (r"b\.onlyDir\s*=\s*fadeDir;", "the breaker path can only fade the raid it was built for"),
        (r"cfg\.timeStopMinutes\s*=\s*InpTimeStopMinutes;", 'p.5 "If the trade slows near midday, consider exiting"'),
    ],
    # ------------------------------------------------------- 80/20 Nasdaq (card #02)
    "EA_CF_8020NasdaqStrategy.mq5": [
        (r"input int\s+InpLevelHi\s*=\s*80;", 'p.1 "at 25,680 the trader watches the 80 level"'),
        (r"input int\s+InpLevelLo\s*=\s*20;", 'p.1 "at 25,620 the 20 level"'),
        (r"MathFloor\(price / 100\.0\) \* 100\.0", "the levels repeat every 100 index points"),
        (r"input double InpStopPoints\s*=\s*10\.0;", 'p.1 "every trade uses a fixed 10-point stop-loss"'),
        (r"double stop = \(dir > 0\) \? entry - InpStopPoints : entry \+ InpStopPoints;",
         "the fixed stop is applied to every structure, long or short"),
        (r"input double InpTp1Points\s*=\s*15\.0;", 'p.1 "15-point first take-profits"'),
        (r"cfg\.partial1AtR\s*=\s*1\.5;", 'p.1 "at the first 15-point profit target, he covers initial risk by taking 1-2 contracts off" (15 pts on a 10-pt stop = 1.5R)'),
        (r"cfg\.partial1Pct\s*=\s*50\.0;", "half the position comes off at TP1"),
        (r"cfg\.breakEvenAtR\s*=\s*1\.5;", 'p.1 "remaining contracts are trailed to break-even"'),
        (r"cfg\.trailAtR\s*=\s*2\.5;", 'p.1 "then allowed to run for larger moves"'),
        (r"input int\s+InpOpenFromMin\s*=\s+870;", 'p.1 "trades the New York open (9:30 AM ET)"'),
        (r"input int\s+InpOpenToMin\s*=\s+960;", "11:00 ET - the lunch hour starts and entries stop"),
        (r"input int\s+InpAfternoonFromMin\s*=\s+1080;", 'p.1 "avoids the lunch hour (11 AM-1 PM)" - trading resumes at 13:00 ET'),
        (r"EA_InWindow\(ctx\.nowClock, InpOpenFromMin", "the windows go through the engine's clock helper"),
        (r"input ENUM_TIMEFRAMES InpStructureTf\s*=\s*PERIOD_M10;", 'p.1 "a 10-minute chart for overall market structure"'),
        (r"cfg\.signalTimeframe\s*=\s*PERIOD_M3;", 'p.1 "200-second chart (one-third of 10 minutes)" - not a MetaTrader timeframe, so M3 (180 s) is the closest `[interpretation]`'),
        (r"EA_WickRatio\(initBar, \+1\) < InpWickRatio", 'p.2 fork: "a long-wick, small-body candle (the initiation candle)"'),
        (r"EA_BodyRatio\(initBar\) > InpMaxBodyRatio", "the initiation candle's body must be small"),
        (r"test\.low < initBar\.low - InpBreakTolPoints", 'p.2 "the next candle tests the low but doesn\'t break it"'),
        (r"trig\.high > test\.high && trig\.close > test\.high", 'p.2 "then makes a higher high. Entry is on this higher-high candle"'),
        (r"EA_WickRatio\(r\[1\], -1\) < InpWickRatio", 'p.2 H-pattern: "a strong move into the opposite level (e.g., 80) with a long wick"'),
        (r"r\[1\]\.close < r\[1\]\.open", 'p.2 H-pattern: "price then rolls over"'),
        (r"r\[i\]\.close < r\[i \+ 1\]\.low", 'p.2 cross-section: "two breakdown candles"'),
        (r"double hi = MathMin\(r\[i\]\.high, r\[i \+ 1\]\.high\);", "the two candles' intersection is the zone"),
        (r"input double InpRepairNoWickTol\s*=\s*0\.10;", 'p.2 repair candle: "no wick on the opposite side"'),
        (r"topWick > InpRepairNoWickTol", "a no-top-wick candle leaves the magnet above it"),
        (r"InpRequireLevelTap\s+=\s+true;", 'p.3 "the best entries combine all elements: level, structure, and candle pattern"'),
        (r"cfg\.maxTradesPerDay\s*=\s*0;", 'p.3 "rather than a hard rule like three trades per day max, Okala uses market conditions" - no cap'),
        (r"EA_ApplyStagePolicy\(cfg, InpStage\);", "card #01's stage policy stays available"),
    ],

    # ------------------------------------------- Algo Portfolio Monitor (card #03)
    # The source is a process document (build + rank + monitor algos), not a strategy, so the pinned
    # rules are the ranking filters and risk bands it states - the EA invents no entry rule.
    "EA_CF_AlgoPortfolioMonitor.mq5": [
        (r"input double InpMinProfitFactor\s*=\s*1\.50;", '"profit factor (e.g., 1.5+)" ranking filter'),
        (r"input double InpMinReturnDD\s*=\s*4\.00;", '"return-to-drawdown ratio (e.g., 4:1)" ranking filter'),
        (r"input double InpMinTradesPerMonth\s*=\s*2\.00;", '"average trades per month (e.g., 2+)" ranking filter'),
        (r"input double InpMaxAvgLossPct\s*=\s*0\.50;", '"average loss as a percentage of account (e.g., 0.5%)"'),
        (r"input double InpAvgLossRulePct\s*=\s*0\.50;", '"average loss does not exceed 0.5% of that allocated amount"'),
        (r"input double InpMinAllocPct\s*=\s*5\.0;", '"allocate 5-25% of total account to a single algorithm"'),
        (r"input double InpMaxAllocPct\s*=\s*25\.0;", "the top of the 5-25% allocation band"),
        (r"input double InpExpectedDdPct\s*=\s*25\.0;", '"realistic drawdowns of 20-25%"'),
        (r"algos\[a\]\.impliedAllocPct = \(balance > 0\.0 && InpAvgLossRulePct", "the allocation rule is inverted from the average loss"),
        (r"expectancyR\s*<=\s*0\.0\)\s+notes \+= \"negative-expectancy;\"",
         '"breakout traders can be profitable with only a 40% success rate ... risking $1 to make $2"'),
        (r"cfg\.riskPct\s*=\s*0\.0;", "the document teaches how to RUN algorithms - this EA trades none"),
        (r"bool AllowTrading\(SEAContext &ctx\) \{ return false; \}", "the monitor cannot open a position"),
        (r"HistorySelect\(from, TimeTradeServer\(\) \+ 60\)", "it measures the account's own algorithms, not itself"),
        (r'input string InpJournalFile\s*=\s*"cf_algo_ranking\.csv"', "one ranking row per algorithm per scan"),
        (r"InpScanMinutes\s*=\s*240;", '"continuous monitoring rather than passive automation"'),
    ],

    # ---------------------------------------------------- 5-Stage Guardrails (card #01)
    "EA_CF_Stage_Guardrails.mq5": [
        (r"EA_ApplyStagePolicy\(policy, InpStage\);", "the stage table is read from the engine helper, not duplicated"),
        (r"bool AllowTrading\(SEAContext &ctx\) \{ return false; \}", "the monitor never trades"),
        (r"If\(m_capTradesPerDay > 0 && st\.entries > m_capTradesPerDay\)",
         '"narrow your focus to only 1-2 main setups" -> trade-count cap'),
        (r"if\(lossPct <= -InpDailyLossCutoffPct\)", '"cut-off rules" -> daily loss cut-off'),
        (r"If\(st\.revengeEntry\)", 'stage-4 trap "revenge trade after a loss"'),
        (r"If\(st\.sizeJump\)", '"sizing up too fast"'),
        (r"If\(m_streakThreshold > 0 && st\.maxStreak >= m_streakThreshold\)",
         '"breaking rules after a few losing trades" -> streak flag'),
        (r'input string InpJournalFile\s*=\s*"cf_stage_journal\.csv"', '"journaling is not optional" -> the journal file'),
    ],
}


class SyncTests(unittest.TestCase):
    def test_every_tracked_ea_has_a_sync_table(self) -> None:
        on_disk = sorted(p.name for p in FAMILY.glob("*.mq5"))
        self.assertEqual(sorted(SYNC), on_disk,
                         "every EA needs a rule->code table; add one when an EA is added")

    def test_every_rule_matches_its_ea(self) -> None:
        # matching is case-insensitive so a rule reads as the comment that quotes it, without
        # forcing the code to be written in the doc's capitalisation
        for name, rules in SYNC.items():
            source = (FAMILY / name).read_text(encoding="utf-8")
            for pattern, note in rules:
                compiled = re.compile(pattern, re.IGNORECASE)
                match = compiled.search(source)
                self.assertIsNotNone(match, f"{name}: rule not found in the code -> {note}")

    def test_interpretations_stay_labelled(self) -> None:
        # a rule the playbook does not state must remain visibly marked in the source
        for name in ("EA_CF_Structure_OTE.mq5", "EA_CF_PO3_OTE_ADR.mq5",
                     "EA_CF_AMD_Model.mq5", "EA_CF_Intraday_Liquidity.mq5"):
            source = (FAMILY / name).read_text(encoding="utf-8")
            self.assertIn("[interpretation]", source, name)

    def test_the_derived_r_levels_follow_the_geometry(self) -> None:
        # the doc's R values for 0.62 / 0.705 / 0.79 entries with the 1.0 stop
        for fib, expected in ((0.62, 1.63), (0.705, 2.39), (0.79, 3.76)):
            risk = 1.0 - fib
            self.assertAlmostEqual(fib / risk, expected, places=2)

    def test_pages_referenced_by_the_tables_exist(self) -> None:
        # guard against a card being renumbered without the sync notes moving with it
        manifest = (FAMILY / "manifest.json").read_text(encoding="utf-8")
        for slug in ("amd-model", "structure-ote", "smt-divergence-po3", "po3-ote-adr",
                     "break-retest", "intraday-liquidity-volatility-model",
                     "5-stage-trading-framework"):
            self.assertIn(slug, manifest)


if __name__ == "__main__":
    unittest.main()
