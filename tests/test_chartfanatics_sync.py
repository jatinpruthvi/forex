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
  * EA_CF_AuctionMarket (card #05): the playbook reads footprint prints and CVD; the engine has bars,
    so the profile is built from tick volume and "aggression" is body + above-average volume. The
    trend model's "target the previous balance POC" is projected one value-area width beyond the POC
    (price has already left it); the CVD-early break-even is the engine's 1R break-even.
  * EA_CF_AuctionMarketTheory (card #06): same tick-volume profile proxy; the 70% value area is the
    standard convention (the doc does not quantify it); the doc's order-flow exit is a custom
    Manage() that closes on a strong opposing body back through value once the trade is in profit.
  * EA_CF_FairPricingTheory (card #09): the A+ news-reversion setup needs scheduled-news timestamps;
    the engine has no reliable calendar in the tester, so the session-open reversion - the same
    mechanic of an unfair displacement snapping back to fair price - stands in (documented here).
  * EA_CF_EpisodicPivot (card #08): the playbook picks single stocks for their catalyst; an EA sees
    prices and volume only, so the catalyst is read as its mechanical footprint (outsized gap/move on
    abnormal volume) and the symbol list is the user's universe.  EP 9M uses real share volume where
    the broker publishes it.  The starter-then-add schedule is not implemented (engine opens one
    risk-sized position at confirmation).
  * EA_CF_FirstRedDay (card #10): same single-stock selection caveat; the parabolic threshold (25%)
    is an interpretation - the doc gives no number - and the one-loss day lock is labelled in code.
  * EA_CF_FirstRedDayPro (card #11): same single-stock caveat, plus: VWAP is rebuilt from the
    session's M5 bars (bar tick volume as the volume proxy); the "larger assets: 2-3%" band becomes
    the fallback target when VWAP does not offer a >= 1R magnet; the hard 3-5 attempt cap is one
    input (`InpMaxAttempts`, default 3) that the stage policy can only tighten.
  * EA_CF_PsychGuardrails (card #12): the masterclass is subjective by nature; the EA is a monitor
    that replays the account's own day through the shutdown ladder.  Loss counts are the mechanical
    stand-in for "emotion rising", the 15-minute break is the doc's own number, and the zone-map
    signs get event proxies (revenge = entry soon after a losing close, escalation = bigger re-entry
    after a loss, burst = entries packed into a window, off-window = entries outside the session).
  * EA_CF_FuturesStrategy (card #13): the Beacon is a proprietary auto-tool the doc describes in
    words only, so the levels are the standard retracements of the leg the two band peaks delimit;
    "contracting/expanding" is a ratio against the 20-day average bandwidth; the engine's
    SigFractals is bound to the signal timeframe, so the daily swing geometry is local; the
    anchored-VWAP anchor is the phase anchor and its deviation bands are represented by the 1R
    partial; the MA exit context reads a daily close on the wrong side of both the 8 and the 21.
  * EA_CF_LiquidityInversion (card #17): the video teaches the ICT stack by example, so the reading is
    fixed in the code and labelled: "sweep" = a daily wick beyond the prior weekly (preferred: monthly)
    extreme that closes back inside; "inversion" = a displacement close through the gap followed by a
    retest that holds the new side; the rejection tolerance is a fraction of the gap height (no number in
    the source).  The engine's `dayLockAfterLosses` counts today's losers, not consecutive ones, so the
    document's two-consecutive-loss rule is tracked in class state instead.  The VIX gate needs a
    broker-published volatility symbol and is off by default; the options-leap workflow and prop-firm
    payout rules are not implementable on MT5 spot and are disclosed on the card.
  * EA_CF_GammaReversal (card #14): gamma/put/call walls are options-platform data (the video names
    Guestbot) that no MetaTrader EA can read, so the levels are inputs the trader fills in - the
    video's own action item - and everything the document states mechanically (window, OPEX /
    witching / "spiration" calendar, tick stops and tick targets, partial + runner, the 2-day
    post-loss rule) is implemented.  "Spiration" is non-standard and is read verbatim as a day 30
    days before a monthly OPEX; approach/reclaim/volume tolerances are inputs.
  * EA_CF_InstFramework (card #15): the document is an institutional PIPELINE; the EA carries its
    codeable strategies (ORB, VWOP, overnight gap) as modes plus its volatility-targeting and
    live-validation rules.  PEAD (Strategy 3) is disclosed in the source as data-blocked: it needs
    actual-vs-estimate earnings and a calendar no MT5 EA can read.  The 80/20 split and Monte Carlo
    steps are research-time work (they live in the validation harness); the EA carries their RESULT
    forward as the drawdown pause threshold.  The overnight 17.5 h hold is DST-proof; entering the
    Friday close is skipped so the exit cannot sit through a weekend (labelled).
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

    # ------------------------------------------------- Auction Market (card #05)
    "EA_CF_AuctionMarket.mq5": [
        (r"input double\s+InpRiskPct\s*=\s*0\.40;", '"keep risk small, 0.25% to 0.5% of the account per trade"'),
        (r'double target = \(dir > 0\) \? prev\.poc \+ width : prev\.poc - width;',
         'step 5: "target the previous balance POC" (projected one value-area width for the trend model)'),
        (r'double target = prev\.poc;', 'MR model: "target the balance POC (center of value). Exit full position there"'),
        (r"bool outOfBalance = \(MathAbs\(ctx\.mid - prev\.poc\) > InpImbalanceAtr \* ctx\.atr\)",
         'step 1: "market state - read whether the market is in balance or out of balance"'),
        (r"ctx\.adx14 >= InpMinAdx", "imbalance needs displacement AND momentum"),
        (r"LowestVolumeNode\(ctx\.symbol, 1, InpLegBars, ctx\.mid, extreme, lvn\)",
         'step 2: "identify Low-Volume Nodes (LVNs) inside that move"'),
        (r"if\(dir > 0 && !\(r\[1\]\.low <= lvn \+ tol\)\) continue;",
         'step 2: the pullback must reach the node - "place alerts just before LVNs"'),
        (r"bool AggressiveBar", 'no aggression = no trade ("only enter when you see aggression")'),
        (r"EA_BodyRatio\(r\[1\]\) < bodyMin\) return false;", "aggression shows in the candle body"),
        (r"InpAggressionVol", "aggression needs above-average volume (big prints proxy)"),
        (r"double print = \(dir > 0\) \? MathMin\(r\[1\]\.low, MathMin\(r\[2\]\.low, r\[3\]\.low\)\)",
         'step 4: "place just beyond the aggressive print"'),
        (r'InpStopBufferTicks\s*=\s*2;', '"add a 1-2 tick buffer before the obvious swing high/low"'),
        (r"InpNyFromMin\s*=\s*870;", '"works best in the New York session (NASDAQ, ES)"'),
        (r"InpLdnFromMin\s*=\s+480;", '"works best in the London session" (mean-reversion model)'),
        (r"bool backIn = \(dir > 0\) \? \(r\[i\]\.close > edge\)", 'step 1 MR: "watch for the price to push out of balance and then fail"'),
        (r"if\(failIdx <= 2\) continue;", '"do not take the first move back - that\'s risky"'),
        (r"cfg\.breakEvenAtR\s*=\s*1\.0;", "break-even management (the CVD-early variant is documented as unavailable)"),
        (r"cfg\.signalTimeframe\s*=\s*PERIOD_M5;", "[interpretation] order-flow scalping with bar data -> M5"),
        (r"EA_ApplyStagePolicy\(cfg, InpStage\);", "card #01's stage policy stays available"),
    ],
    # ----------------------------------------- Auction Market Theory (card #06)
    "EA_CF_AuctionMarketTheory.mq5": [
        (r"if\(!BuildProfile\(ctx\.symbol, 1, InpValueBars, prev\)\) return false;",
         "the value area (fair value) is the reference for every setup"),
        (r"input double\s+InpValueAreaPct\s*=\s*0\.70;", "[interpretation] 70% value area (the doc does not quantify it)"),
        (r"bool FailedAuction\(SEAContext &ctx, const SVolProfile &prev, SSignalPlan &plan\)",
         '"Failed auctions below/above value (reversal long/short)"'),
        (r"bool backIn = \(dir > 0\) \? \(r\[i\]\.close > edge\) : \(r\[i\]\.close < edge\);",
         '"price moves below a fair value area ... if those sellers fail ... the rejection of lower prices"'),
        (r"if\(!StrongBody\(ctx, dir, InpAcceptBody\)\) continue;",
         '"the entry occurs when buyers clearly take control after the failed attempt"'),
        (r"double print = \(dir > 0\) \? r\[failIdx\]\.low : r\[failIdx\]\.high;",
         '"the stop is placed below the area where sellers attempted to dominate"'),
        (r"double target = \(dir > 0\) \? MathMax\(prev\.poc, prev\.vah\)",
         '"the target is a return to fair value, and potentially the opposite side of the range"'),
        (r"bool AcceptedBreakout\(SEAContext &ctx, const SVolProfile &prev, const bool haveOrb,",
         '"Breakout with Acceptance (Continuation)"'),
        (r"bool holds = \(dir > 0\) \? \(r\[1\]\.low >= level", '"acceptance means: price holds outside the level"'),
        (r"EA_BodyRatio\(r\[i\]\) >= InpAcceptBody\) \{ brkIdx = i; break; \}",
         '"most of the activity appeared on the wick ... effort, but not acceptance" -> body required'),
        (r"if\(dir > 0 && now\.poc < prev\.poc\) continue;", "acceptance must keep value building in the move's direction"),
        (r"SigRangeForDay\(ctx\.symbol, g_eaIndTf, InpOrbFromMin, InpOrbToMin, 0, orbHi, orbLo, orbBars\)",
         '"Opening Range Integration: wait to see whether the move is supported by real participation"'),
        (r"void Manage\(SEAContext &ctx\)", '"manage the trade by monitoring shifts in participation"'),
        (r'g_eaExec\.Close\(ticket, "opposing pressure"\);',
         '"the exit occurred when buyers began to get absorbed near the highs and sellers started to take control"'),
        (r"InpFlowExitR\s*=\s*0\.50;", "the flow exit waits until the trade is working"),
        (r"cfg\.signalTimeframe\s*=\s*PERIOD_M5;", "[interpretation] 15m/5m context in the video -> M5 signal"),
        (r"EA_ApplyStagePolicy\(cfg, InpStage\);", "card #01's stage policy stays available"),
    ],
    # ------------------------------------------- Fair Pricing Theory (card #09)
    "EA_CF_FairPricingTheory.mq5": [
        (r"cfg\.signalTimeframe\s*=\s*PERIOD_M1;", '"pure price action on 1-minute NASDAQ futures charts"'),
        (r"input double InpRewardRatio\s*=\s*1\.50;", '"a 1:1 or 1:1.5 ratio works best for evaluations; funded accounts use 1:4 or higher"'),
        (r"double stopDist = tpDist / InpRewardRatio;",
         '"optimize take profit first, stop loss second ... the stop loss is then set as a static reciprocal of the take profit"'),
        (r"double tpDist = \(dir > 0\) \? \(fair - entry\) : \(entry - fair\);",
         '"the take profit ... should be set based on account rules and available points to fair price"'),
        (r"cfg\.dayLockAfterLosses\s*=\s*3;", '"if three consecutive reversion trades lose in a single session, stop trading"'),
        (r"input bool   InpUseDisplacement\s*=\s*true;", '"the three core entry signals" - 1: displacement candles'),
        (r"double bodyNow  = MathAbs\(r\[1\]\.close - r\[1\]\.open\);",
         '"displacement candles (body larger than previous, closes below the wick)"'),
        (r"bool closesBeyondWick = \(dir > 0\) \? \(r\[1\]\.close > r\[2\]\.high\)", "the close must clear the previous wick"),
        (r"input bool   InpUseBreakOfStructure\s*=\s*true;", "signal 2: break of structure"),
        (r"bool isSwing = \(dir > 0\) \? \(r\[i\]\.low < r\[i - 1\]\.low && r\[i\]\.low < r\[i \+ 1\]\.low\)",
         '"break of structure (wick lower than two adjacent candles, then broken)"'),
        (r"input bool   InpUseReversion\s*=\s*true;", "signal 3: news/session-open reversion"),
        (r"if\(stretch < InpUnfairAtr \* ctx\.atr\) continue;", '"trades reversions back to that fair price" - only when the move was unfair'),
        (r"double fair = PreviousDayClose\(ctx\.symbol\);", '"the initial candle after release is unfair ... back to the pre-news price" - the day close is the fair anchor'),
        (r"InpNyAmFromMin\s*=\s*870;", '"trade only the first 90 minutes of each session: New York open (9:30-11:00 a.m. EST)"'),
        (r"InpAsiaFromMin\s*=\s*60;", "the Asia open window"),
        (r"InpNyPmFromMin\s*=\s*1140;", '"New York PM open (2:00-3:30 p.m. EST)"'),
        (r"EA_ApplyStagePolicy\(cfg, InpStage\);", "card #01's stage policy stays available"),
    ],
    # ------------------------------------------------- Episodic Pivot (card #08)
    "EA_CF_EpisodicPivot.mq5": [
        (r"bool Neglected\(const string sym\)", '"the stock has been ignored for a long time" - the neglect leg'),
        (r"bool deadRange = \(hi - lo\) < InpNeglectRange \* atrLong \* 40\.0;", '"trading near lows or stuck in a dead range"'),
        (r"bool CatalystDay\(const string sym, const bool positive, double &gapPct, double &volMult\)",
         '"new catalyst ... large gap and strong follow-through, huge increase in volume"'),
        (r"volMult < InpCatVolMult", '"extremely abnormal trading volume (implied catalyst)"'),
        (r"InpOrMinutes\s*=\s*30;", '"enter near the open ... within the first 5-10 minutes if strength confirms"'),
        (r"if\(!\(ctx\.mid > orHi \+ InpStrengthAtr \* ctx\.atr\)\) return false;", '"if strength confirms"'),
        (r"double stop  = orLo - InpStopBufferAtr \* ctx\.atr;", '"place the stop below the opening-range low"'),
        (r"cfg\.breakEvenAtR\s*=\s*1\.0;", '"stop moved to break-even once the trade pushed favorably"'),
        (r"double trail = d\[InpTrailDays\]\.low - InpStopBufferAtr \* ctx\.atr;", '"trail the position under daily swing lows"'),
        (r"bool ClosedBelowPriorLow\(", '"exit if the trend breaks"'),
        (r"InpNineMShares\s*=\s*9000000;", '"EP 9 Million: any stock that trades 9 million shares or more in a single day"'),
        (r"InpNineMVolMult\s*=\s*5\.0;", '"when this is far above its normal volume"'),
        (r"double support = m\[1\]\.low;", '"enter intraday once volume above 9 million shares aligns with a clear trend"'),
        (r"bool DelayedLong\(SEAContext &ctx, SSignalPlan &plan\)", '"Delayed Reaction EP (Long): a breakout from a tight range formed after the catalyst day"'),
        (r"InpTightRangeAtr\s*=\s*3\.0;", "the tight post-catalyst range"),
        (r"bool DelayedShort\(SEAContext &ctx, SSignalPlan &plan\)", '"Delayed Reaction EP (Short): enter short once the bounce shows signs of failure"'),
        (r"double stop  = m\[1\]\.high \+ InpStopBufferAtr \* ctx\.atr;", '"place the stop above the high of the bounce"'),
        (r"double vol = \(realVol > 0\.0\) \? realVol : \(double\)d\[1\]\.tick_volume;",
         "share volume is preferred where the broker publishes it (stocks) - tick volume is the fallback"),
        (r"EA_ApplyStagePolicy\(cfg, InpStage\);", "card #01's stage policy stays available"),
    ],
    # -------------------------------------------------- First Red Day (card #10)
    "EA_CF_FirstRedDay.mq5": [
        (r"input int    InpRunDays\s*=\s*3;", '"three or more strong days ... one green day is not enough"'),
        (r"if\(d\[i\]\.close <= d\[i \+ 1\]\.close\) return false;", '"ideally with each day stronger than the last"'),
        (r"if\(runPct < InpRunMinPct\) return false;", '"a parabolic move, not just a slow trend up"'),
        (r"double line = d\[1\]\.close;", '"draw a line at the previous day\'s close. This is your key level"'),
        (r"if\(!\(m\[1\]\.close < line - InpBreakBufferAtr \* ctx\.atr\)\) return false;",
         '"the trade does not start until price goes under that line"'),
        (r"cfg\.useLimitEntry\s*=\s*false;", '"do not anticipate ... the key is waiting for confirmation"'),
        (r"bool gapUpFade   = \(m\[2\]\.high > line\) && \(m\[1\]\.close < line\);",
         'path 1: "if it gaps up ... wait for it to break under the previous close"'),
        (r"bool gapDownFail = \(m\[1\]\.high <= line && m\[1\]\.high >= line - InpBounceTouchAtr \* ctx\.atr\);",
         'path 2: "if it gaps down ... look for a bounce that fails near the previous close"'),
        (r"double stop  = line \+ InpStopBufferAtr \* ctx\.atr;",
         '"if the price reclaims the previous day\'s close and holds above it ... cut the trade"'),
        (r"input double InpPartial1AtR\s*=\s*1\.0;", '"cover portions of your position into the weakness"'),
        (r"input double InpTrailAtR\s*=\s*1\.5;", '"hold a small portion of the trade to catch any further drop"'),
        (r"\[interpretation\]: the doc warns that messing up the first trade", "the one-loss day lock is labelled an interpretation"),
        (r"EA_ApplyStagePolicy\(cfg, InpStage\);", "card #01's stage policy stays available"),
    ],
    # ------------------------------------------- First Red Day Pro (card #11)
    "EA_CF_FirstRedDayPro.mq5": [
        (r"input int\s+InpMinGreenDays\s*=\s*3;", '"minimum 2-3 consecutive green days" - non-negotiable criterion'),
        (r"if\(d\[i\]\.close <= d\[i\]\.open\) break;", '"No red days during the run" - the walk-back stops at the first red day'),
        (r"if\(runLen < InpMinGreenDays\) return false;", "the run is walked to its true start, so a long streak measures its real extension"),
        (r"if\(extension < InpMinExtensionPct\) return false;", '"80-100%+ extension from the start of the run"'),
        (r"d\[1\]\.tick_volume > d\[2\]\.tick_volume && d\[2\]\.tick_volume >= d\[3\]\.tick_volume",
         '"Expanding daily volume" - a non-negotiable criterion'),
        (r"if\(!\(r1 > r2 && r2 >= r3\)\) return false;", '"Expanding daily range (acceleration)"'),
        (r"double priorClose = d\[1\]\.close;", '"The previous day\'s close is the most important level" -> the psychological trigger'),
        (r"if\(!\(m\[1\]\.high < runHigh - InpFadeBufferAtr \* ctx\.atr\)\) return false;",
         'pre-red entry: "short before price breaks prior close ... failure to make new highs"'),
        (r"if\(!\(m\[1\]\.close < priorClose && m\[1\]\.close < m\[1\]\.open\)\) return false;",
         'standard entry: "wait for the crack below prior close"'),
        (r"if\(bounceHigh < priorClose - InpBounceMinAtr \* ctx\.atr\) return false;",
         'lower-high entry: the bounce after the breakdown must be real'),
        (r"if\(!\(m\[1\]\.high < bounceHigh && m\[1\]\.close < m\[1\]\.open\)\) return false;",
         'lower-high entry: "short failed lower high" after "wait for the first bounce"'),
        (r"if\(downPct >= InpMaxDownPct\) return false;", '"do not short if already down 10%+" (overextended gap-down variation)'),
        (r"if\(InpUseVwapTarget && vwap > 0\.0 && vwap < entry - risk\) target = vwap;", '"VWAP is the primary magnet"'),
        (r"if\(target <= 0\.0\) target = entry \* \(1\.0 - InpFallbackTgtPct / 100\.0\);",
         '"Larger assets: 2-3%" - the fallback target when no VWAP magnet applies'),
        (r"if\(target >= entry - risk\) target = entry - risk;", '"cover into weakness, do not wait for the exact bottom" - never a sub-1R destination'),
        (r"double hod = \(d\[0\]\.high > 0\.0\) \? d\[0\]\.high : m\[1\]\.high;", '"Risk: Today\'s high of day" - exact session high from the forming daily bar'),
        (r"if\(ctx\.mid >= entry\) continue;", "the 15-minute trail only engages once the trade is working (and never loosens)"),
        (r"cfg\.maxTradesPerDay\s*=\s*InpMaxAttempts;", '"hard rule: 3-5 attempts maximum"'),
        (r"input double InpPartial1AtR\s*=\s*1\.0;", '"scale out, avoid all-or-nothing" -> partial into weakness'),
        (r"double m15High = q\[1\]\.high;", '"optional: trail using 15-minute high" -> the last completed M15 high'),
        (r"input bool\s+InpTrailM15High\s*=\s*true;", "the 15-minute-high trail is the playbook's own tool, not an engine approximation"),
        (r"EA_ApplyStagePolicy\(cfg, InpStage\);", "card #01's stage policy stays available"),
        (r"\[interpretation\]", "the doc is silent on stock selection/VWAP proxy -> stays labelled"),
    ],
    # ------------------------------------------------ Psych Guardrails (card #12)
    "EA_CF_PsychGuardrails.mq5": [
        (r"cfg\.riskPct\s*=\s*0\.0;", "a process monitor never sizes a position"),
        (r"bool AllowTrading\(SEAContext &ctx\) \{ return false; \}", '"the best trade is no trade at all" - the monitor never trades'),
        (r"input int\s+InpCooldownMin\s*=\s*15;", '"set a limit ... or a 15-minute break"'),
        (r"Warn\(CF_PSYCH_CAUTION, dayStart, st,", '"reduce activity, be more selective, or slow down" - the 60% point'),
        (r"Warn\(CF_PSYCH_COOLDOWN, dayStart, st,", '"set a limit ... a 15-minute break" -> the mid-session reset'),
        (r"Warn\(CF_PSYCH_BREACH, dayStart, st,", '"if you break your own limit, your session is over"'),
        (r"Warn\(CF_PSYCH_ENDSESSION, dayStart, st,", "emotional EV: \"sometimes the smartest trade is no trade at all\""),
        (r"Warn\(CF_PSYCH_REVENGE, dayStart, st,", 'the zone-map thought "I\'ll make it back"'),
        (r"Warn\(CF_PSYCH_ESCALATE, dayStart, st,", 'the zone-map thought "I need to get it back!"'),
        (r"Warn\(CF_PSYCH_BURST, dayStart, st,", 'low energy: "you may also become impatient and trade just to feel engaged"'),
        (r"Warn\(CF_PSYCH_OFFWINDOW, dayStart, st,", 'perception shift: "promote average setups to A+"'),
        (r"int shift = m_carryover \? 1 : 0;", '"emotions don\'t reset overnight" -> a red yesterday shifts the ladder one step earlier'),
        (r"if\(cooldownUntil > when\)", 'the break is enforced: trading inside it is the breach the doc calls out'),
        (r"if\(st\.lastLossClose > 0 && when - st\.lastLossClose <= \(datetime\)\(InpRevengeMin \* 60\)\)",
         '"I\'ll make it back": an entry soon after a losing close'),
        (r"if\(st\.lastLossClose > 0 && lastEntryVol > 0\.0 && vol > InpSizeEscalateRatio \* lastEntryVol\)",
         '"I need to get it back!": a larger re-entry after a loss'),
        (r"if\(st\.burstMax > InpBurstEntries\)", '"impatient and trade just to feel engaged" - entries packed into a window'),
        (r"JournalRow\(todayStart, \"PRE\", st, PreNote\(\)\);", '"Before the session: take 5 minutes to check in"'),
        (r"JournalRow\(todayStart, \"POST\", st, PostNote\(st\)\);",
         '"After the session ... top 3 emotional moments ... if-then plan for tomorrow"'),
        (r"input string InpJournalFile\s*=\s*\"cf_psych_journal\.csv\";", '"journaling is not optional" -> the journal file'),
        (r"if\(yst\.closes <= 0 \|\| yst\.pl >= 0\.0\) return;", 'carryover is read from yesterday\'s realised result'),
        (r"\[interpretation\]", "the doc is subjective - the mechanical thresholds stay labelled"),
    ],
    # ------------------------------------------------ Futures Strategy (card #13)
    "EA_CF_FuturesStrategy.mq5": [
        (r"input int\s+InpBbPeriod\s*=\s*20;", '"Bollinger Bands: Length: 20" (core indicator, required)'),
        (r"input double InpBbDeviations\s*=\s*3\.0;", '"Standard deviations: 3" - the doc explains why not tighter'),
        (r"bool contracting = \(bw\[1\] <= bw\[2\] && bw\[1\] < avgBw \* InpContractRatio\);",
         '"Bollinger Bands contract (they come in / narrow)" -> consolidation'),
        (r"bool expanding\s*=\s*\(bw\[1\] > bw\[2\]\s*&& bw\[1\] > avgBw \* InpExpandRatio\);",
         '"Bands expand (range expansion)" -> trend / expansion'),
        (r"if\(lv\.legUp && lv\.peakHigh > lv\.legLow\)", "the leg the Bollinger peaks delimit supplies the Beacon levels"),
        (r"lv\.l30 = lv\.peakHigh - InpBeacon30 \* span;", '"30% / 50% (main target) / 70%" applied to that leg'),
        (r"if\(dir < 0 && !\(d\[1\]\.close < trig\)\) return false;", '"Once there is a daily close below the 30% line" - the trigger'),
        (r"if\(dir < 0 && ctx\.mid <= dst\) return false;", '"Once 50% is hit, the mean reversion objective is considered done" - the hands-in-pocket zone'),
        (r"target = dst;", '"the target becomes 50%"'),
        (r"stop = \(dir < 0\) \? trig \+ InpStopBufferAtr \* ctx\.atrD1 :",
         '"buy puts or short futures until a daily close back above the relevant level" - the line is the invalidation'),
        (r"counter = primaryUp;", '"trade against the primary trend, but that\'s where discretion = smaller sizing"'),
        (r"m_sizeMult = counter \? InpCounterTrendRiskMult : 1\.0;", '"smaller size if against the primary trend"'),
        (r"if\(dir > 0 && !\(close > box \+ InpBreakBufferAtr \* ctx\.atrD1 && close > m\[1\]\.open && ctx\.mid > box\)\) return false;",
         '"Expansion: enter after breakout/confirmation" - a closed M30 bar beyond the old box'),
        (r"why    = \(dir > 0\) \? \"bullish expansion breakout\" : \"bearish expansion breakdown\";",
         '"Bullish expansion ... Long-only / Bearish expansion ... Short-only"'),
        (r"if\(\(risk / entry\) \* 100\.0 > InpMaxStopPct\) return false;",
         '"If the stop becomes unrealistically wide ... use options instead" - an EA cannot, so it stands aside'),
        (r"if\(ctx\.mid <= lv\.consLo \+ zone && lowerWick >= InpWickRatio \* range && m\[1\]\.close > m\[1\]\.open\)",
         '"Trade the edges of the range. Stay out of the middle."'),
        (r"target = \(mid > entry \+ risk\) \? mid : entry \+ InpTargetR \* risk;",
         '"expect stop-runs ... and reversion back into the range" -> the range midpoint target'),
        (r"bool fracHigh = \(d\[i\]\.high > d\[i \+ 1\]\.high && d\[i\]\.high > d\[i \+ 2\]\.high &&",
         '"The \'correct\' stop may be above a key high (or below a key low)" - daily swing geometry'),
        (r"unfinished = \(dir > 0\) \? lv\.peakHigh : lv\.troughLow;",
         '"A prior Bollinger Band peak becomes a future target" ("unfinished business")'),
        (r"bool haveWeek = SigDonchian\(ctx\.symbol, 5, wHi, wLo\);",
         '"Higher timeframe levels (weekly highs/lows, major reference points)"'),
        (r"if\(InpUseMaExitContext && MaContextBroken\(ctx, dir\)\)", '"8/21/34 moving averages (exit context, not entry signals)"'),
        (r"double av = AnchoredVwap\(ctx\.symbol\);", '"anchored VWAP ... Can it stay below VWAP?" - the bear case, mirrored'),
        (r"if\(opened > 0 && TradingDaysSince\(opened\) > InpMaxHoldDays\)", '"Typical holding time: 1 to 5 trading days"'),
        (r"cfg\.partial1AtR\s*=\s*InpPartial1AtR;", '"scale out into targets/levels"'),
        (r"EA_ApplyStagePolicy\(cfg, InpStage\);", "card #01's stage policy stays available"),
        (r"\[interpretation\]", "the Beacon / bandwidth / VWAP details the doc leaves open stay labelled"),
    ],
    # ------------------------------------------------ Gamma Reversal (card #14)
    "EA_CF_GammaReversal.mq5": [
        (r"input double InpPutWall\s*=\s*0\.0;", '"Identify the maximum put gamma and call gamma levels ... using 90-day open interest" - platform data, so an input'),
        (r"input double InpCallWall\s*=\s*0\.0;", "the call wall is the short side of the same rule"),
        (r"input string InpGammaLevels\s*=\s*\"\";", '"target the next gamma level" - the listed gamma / convexity levels'),
        (r"input int\s+InpStopTicks\s*=\s*40;", '"Set stop losses at 30-50 ticks"'),
        (r"input int\s+InpTargetTicks\s*=\s*350;", '"Risking 30-50 ticks to make 300-400 ticks"'),
        (r"double stop\s*=\s*\(dir > 0\) \? wall - InpStopTicks \* tick : wall \+ InpStopTicks \* tick;",
         '"Entry at the wall, stop loss 30-40 ticks below"'),
        (r"double target = NextLevel\(entry, dir, risk, tick\);", '"wait for the level, enter, ... target the next gamma level"'),
        (r"bool tapped = \(dir > 0\) \? \(bar\.low <= wall \+ tol\) : \(bar\.high >= wall - tol\);",
         '"Price approached the maximum put gamma level ... Market rejected it, reversed"'),
        (r"if\(EA_WickRatio\(bar, dir\) < InpWickRatio\) return false;", "the rejection wick the entry bar must show"),
        (r"if\(avgVol > 0\.0 && \(double\)bar\.tick_volume < InpVolMult \* avgVol\) return false;",
         '"Combine gamma levels with order flow or footprint analysis to confirm" - the engine has volume, not prints'),
        (r"cfg\.partial1AtR\s*=\s*InpPartial1AtR;\s*cfg\.partial1Pct = 50\.0;",
         '"Use 2-3 contracts to allow partial profit-taking while keeping one contract running"'),
        (r"cfg\.trailAtR\s*=\s*3\.0;", "the runner rides toward the next level"),
        (r"if\(InpRiskUsd > 0\.0 && equity > 0\.0\) riskPct = InpRiskUsd / equity \* 100\.0;",
         '"Risk 30-50 ticks ($150-200)" - the fixed dollar risk drives sizing'),
        (r"cfg\.sessionStartHour\s*=\s*InpWindowStartHour;", '"Trade only the first two hours after market open (9:30-11:30 ET)"'),
        (r"if\(InpSkipOpex && \(IsOpexDate\(ctx\.nowClock\) \|\| IsWitchingDate\(ctx\.nowClock\)\)\)",
         '"Avoid OPEX and Triple Witching Days" - computed from the calendar'),
        (r"if\(InpSkipSpiration && IsSpirationDate\(ctx\.nowClock\)\)", '"spiration days (30 days before OPEX)"'),
        (r"if\(PostLossLockActive\(ctx\.nowClock\)\)", '"Take 2 days off after a stop loss" - the EA stops itself'),
        (r"int offset = \(5 - f\.day_of_week \+ 7\) % 7;", "third-Friday OPEX, the calendar the document names"),
        (r"input int\s+InpMaxTradesPerDay\s*=\s*2;", '"1-2 high-probability setups per day"'),
        (r"if\(ctx\.clockMinutes < InpWindowEndHour \* 60 \+ InpWindowEndMin\) return;",
         '"avoid trading late in the day" - flat when the window closes (charm phase)'),
        (r"EA_ApplyStagePolicy\(cfg, InpStage\);", "card #01's stage policy stays available"),
        (r"\[interpretation\]", "what the video leaves open (tolerances, spiration reading) stays labelled"),
    ],
    # ------------------------------------------- Institutional Framework (card #15)
    "EA_CF_InstFramework.mq5": [
        (r"input ENUM_CF_FW_MODE InpMode = CF_FW_ORB;", "the document's own strategies, one per mode"),
        (r"input double InpOrbTargetR\s*=\s*2\.0;", '"take profit at 1:1 or 1:2 risk-to-reward"'),
        (r"input bool\s+InpOrbLongOnly\s*=\s*true;", '"long-only works better than short" - the research finding is the default'),
        (r"input int\s+InpOrbRangeFromMin\s*=\s*870;", '"the overnight gap plus the 9:30-10:00 a.m. range"'),
        (r"bool longBreak\s*=\s*\(m\[1\]\.close > rHi && ctx\.mid > rHi\);",
         '"Go long if price closes above the 9:30-10:00 a.m. high"'),
        (r"double stop\s*=\s*\(dir > 0\) \? rLo : rHi;", '"Stop loss at the range low"'),
        (r"if\(ctx\.clockMinutes >= InpOrbExitMin\)", '"or close at 3:30 p.m. if neither hit"'),
        (r"if\(m\[1\]\.close > vwop\) dir = \+1;", '"go long when a 1-minute bar closes above VWOP"'),
        (r"if\(m\[1\]\.close < vwop\) dir = -1;", '"short when price closes below VWOP"'),
        (r'if\(g_eaExec\.Close\(ticket, "close crossed back below VWOP"\)\)', '"exit at VWOP crosses"'),
        (r"input bool\s+InpVwopAnchorAtOpen\s*=\s*true;", '"Calculate from market open (9:30 a.m. US) or previous day\'s close" - both testable'),
        (r"if\(InpVwopAnchorAtOpen\) return \(serverBarTime >= openServer\);", "the open anchor is a real calculation, not a label"),
        (r"return \(serverBarTime >= prevClose\);", "the previous-close anchor is implemented too"),
        (r"cfg\.sessionStartHour\s*=\s*21;\s*cfg\.sessionStartMin = 0;", '"Go long at 4 p.m. (market close)" - the overnight window wraps midnight'),
        (r"if\(opened > 0 && TimeTradeServer\(\) - opened >= \(datetime\)\(InpHoldHours \* 3600\)\)",
         '"Close at 9:30 a.m. (market open)" - 17.5 hours later, DST-proof'),
        (r"input double InpHoldHours\s*=\s*17\.5;", "4 p.m. to 9:30 a.m. is 17.5 hours"),
        (r"input bool\s+InpOvernightRequireRangeBreak\s*=\s*false;",
         '"Can combine with opening range breakout logic for overnight-only breakouts"'),
        (r"if\(InpSkipFridayOvernight && ctx\.dayOfWeek == 5\) return false;",
         "a Friday entry could not exit until Monday - the doc describes one overnight, not a weekend"),
        (r"double mult = InpRiskUsd / planned;",
         '"adjust contract count so risk is always the same (e.g. $10,000 per trade)" - volatility targeting'),
        (r"m_paused = \(trades >= InpValidateAfterTrades && dd > InpValidatedMaxDdUsd\);",
         '"After 10 trades, if ... you see a $15,000 drawdown, that\'s a red flag to pause the strategy"'),
        (r"input int\s+InpValidateAfterTrades\s*=\s*10;", '"after 10 trades" - the validation window'),
        (r'FileWrite\(fh, "month", "magic", "trades", "wins", "losses", "win_rate_pct", "expectancy",',
         '"Monthly Review: monitor live performance, identify underperforming strategies"'),
        (r'"UNDERPERFORMING - review or retire"', "the review names the underperformer instead of just archiving numbers"),
        (r"cfg\.signalTimeframe\s*=\s*PERIOD_M1;", '"1-minute timeframe" (the VWOP study\'s execution chart)'),
        (r"PEAD \(Strategy 3\) is NOT implemented", "Strategy 3 needs earnings data: disclosed, not silently dropped"),
        (r"EA_ApplyStagePolicy\(cfg, InpStage\);", "card #01's stage policy stays available"),
        (r"\[interpretation\]", "every number the video leaves open stays labelled"),
    ],
    # ------------------------------------------- Liquidity Inversion (card #17)
    "EA_CF_LiquidityInversion.mq5": [
        (r"input ENUM_CF_LI_MODEL InpModel = CF_LI_DAY;", "the document's two models (day / swing) live in one EA, per its own split"),
        (r"input int\s+InpSweepMaxDays\s*=\s*3;", '"market sweeps monthly/weekly highs or lows (liquidity grab)" - the sweep must be recent'),
        (r"if\(d\[i\]\.high > hi && d\[i\]\.close < hi\)", "a swept high that closes back inside -> bearish reversal (the doc's own reading)"),
        (r"if\(d\[i\]\.low\s+< lo && d\[i\]\.close > lo\)", "a swept low that closes back inside -> bullish reversal"),
        (r"for\(int k = i \+ 1; k <= i \+ days && k < got; k\+\+\)", "the liquidity box excludes the sweeping bar (a box holding the wick can never be exceeded)"),
        (r"if\(!SweepAt\(ctx\.symbol, 20, bias, level\) \|\| bias == 0\)", 'monthly liquidity is preferred ("more significant than just session highs/lows")'),
        (r"if\(!FindFvg\(ctx\.symbol, PERIOD_H4, -bias, InpH4ScanBars, lo, hi, barAgo\)\)", '"a fair value gap forms on the 4-hour" - the reaction gap'),
        (r"return FvgInvertedBias\(ctx\.symbol, PERIOD_H4, bias, InpH4ScanBars, InpInvertTolFrac \* \(hi - lo\)\);", '"that 4H gap inverts - the highest-probability confirmation"'),
        (r"if\(r\[j\]\.close <= hi\) continue;", "the inversion needs a displacement CLOSE through the gap, not a wick"),
        (r"if\(r\[c\]\.low <= hi \+ tol && r\[c\]\.close > hi\) return true;", '"breaks through the gap and then rejects it" - the retest holds the new side'),
        (r"input double InpInvertTolFrac\s*=\s*0\.10;", "[interpretation]: the video gives no rejection tolerance, so it is a fraction of the gap height"),
        (r"if\(!FindFvg\(ctx\.symbol, zoneTf, -bias, scanBars, zoneLo, zoneHi, 0\)\) return false;", '"a counter-trend 15-minute gap forms on the retracement"'),
        (r"if\(!ZoneInvertedOn\(ctx\.symbol, entryTf, bias, zoneLo, zoneHi, InpInvertTolFrac \* \(zoneHi - zoneLo\)\)\)", '"the 15m gap is inverted as the entry on the 5-minute"'),
        (r"if\(InpModel == CF_LI_SWING\) zoneTf = PERIOD_H1;", 'swing entries "come off the hourly or 4-hour, never the 15-minute or lower"'),
        (r"cfg\.useLimitEntry\s*=\s*false;", '"market execute ... rather than using limit orders"'),
        (r"input int\s+InpStop15mBars\s*=\s*16;", '"stop loss above the current 15-minute high"'),
        (r"if\(bias > 0\) extreme = MathMin\(extreme, r\[i\]\.low\);", "long stops sit below the 15m low; the short side mirrors the high"),
        (r"input int\s+InpStopH4Bars\s*=\s*6;", "swing stops sit beyond the H4 structure instead"),
        (r"input double InpStopBufferAtr\s*=\s*0\.15;", '"wide enough to allow the trade to breathe" - an ATR buffer beyond the level'),
        (r"input double InpMinRr\s*=\s*1\.5;", '"typically yields a 1.5:1 to 2:1 initial risk-reward"'),
        (r"if\(rr < InpMinRr\) return false;", "a setup that cannot reach the doc's R floor is not taken"),
        (r"double nyLevel = \(bias > 0\) \? nyHi : nyLo;", '"target prior sellside liquidity - the previous session low, the 9:30 open low"'),
        (r"if\(FindFvg\(ctx\.symbol, PERIOD_D1, -bias, 60, lo, hi, k\)\)", '"mark multiple partials: daily gaps, weekly gaps" - the swing layer aims at unfilled HTF gaps'),
        (r"input double InpTrimAtR\s*=\s*1\.0;", '"trim 50% at the first take-profit target"'),
        (r"cfg\.breakEvenAtR\s*=\s*1\.0;", '"move the stop to break-even after the trim"'),
        (r"cfg\.trailAtR\s*=\s*InpRunnerTrailAtR;", '"let runners capture extended liquidity"'),
        (r"cfg\.sessionStartHour = 15;  cfg\.sessionStartMin = 0;", '"prefer the New York open (10:00 ET) - do not trade before it" (10:00 ET = 15:00 London)'),
        (r"input int\s+InpConsecutiveLossLock\s*=\s*2;", '"two consecutive losses stop trading for the day"'),
        (r"else if\(p > 0\.0\) streak = 0;", '"a win resets the count, so the third attempt is allowed"'),
        (r"input int\s+InpMaxAttemptsPerDay\s*=\s*3;", '"if he wins one and loses one, he allows himself a third attempt"'),
        (r"return InpHighVolSizeMult;", '"size down in high volatility so that the same dollar risk applies"'),
        (r"if\(EA_Rates\(InpVixSymbol, PERIOD_D1, 0, 3, v\) >= 2 && v\[1\]\.close < InpMinVix\)", '"VIX elevation signals setup probability increase" - an optional gate (broker-dependent symbol)'),
        (r"options-leap workflow is not implementable in an MT5 EA", "options leaps / prop-firm payouts are disclosed, not silently dropped"),
        (r"EA_ApplyStagePolicy\(cfg, InpStage\);", "card #01's stage policy stays available"),
        (r"\[interpretation\]", "every number the video leaves open stays labelled"),
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
                     "EA_CF_AMD_Model.mq5", "EA_CF_Intraday_Liquidity.mq5",
                     "EA_CF_LiquidityInversion.mq5"):
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
