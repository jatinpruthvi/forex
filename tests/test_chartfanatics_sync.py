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
  * EA_CF_MarketDna (card #21): the playbook reads the tape and Level II depth - not readable from an EA - so
    the order-flow proxy is used: aggression is a displacement bar (strong body, close out of the zone) on
    above-average participation, absorption failure is the zone being closed through, and the catalyst
    (earnings / news) becomes relative volume plus the engine's calendar gate.  The DNA move multiple, zone
    width, body/volume thresholds, chase cap and fractal trail are numbers the document does not state.  The
    document's instrument rule is honoured by configuration: stocks and futures only, forex deliberately out.
  * EA_CF_MarketAuctionTheory (card #20): the document's numbers are illustrative, so the post-open
    formation window and the congestion cap that define the auction zone, the daily 45-degree slope
    threshold, the "strongly" body threshold, the stop tick buffer and the second-entry allowance are
    labelled.  The daily 21/50 pair the document quotes is computed locally (the engine only carries the
    daily 200), with the same EMA definition; "conflicting news headlines" is read as the engine's
    calendar gate, and the extended window is an input that is off by default.
  * EA_CF_LowVolumeNode (card #19): the playbook confirms with heatmaps, footprint charts and delta - data
    no MetaTrader EA can read - so the defense is read as absorption on the revisit (a wick into the node,
    the close back inside it, no close through) with above-average participation, and the LVN itself from
    tick-volume bins (the same proxy as the library's volume-profile EAs).  The base/impulse windows, the
    thin-bin fraction, the revisit window, the tight-stop cap and the daily trade cap are numbers the
    document does not state.  Targets use the objective levels the doc itself lists (session extreme,
    prior day extreme, another LVN); "support/resistance" and "another supply or demand zone" in the
    abstract are not measurable without a historical structure map, so they are represented by those.
  * EA_CF_LiquidityStrategy (card #18): the playbook states the method but no parameters, so every number
    is labelled: swing strength and context depth (30-minute level chart, 5-minute execution, per its own
    breakdown), the ATR move-away that qualifies a level as respected, the equal-highs/lows cluster
    tolerance, trap freshness, the entry zone around the swept level (the doc's "sell above the high,
    never below" plus its "entered right after the rejection"), the stop buffer, the 1R trade floor and
    the 50% partial.  Partials are taken at liquidity pools (the engine's R grid is switched off) and the
    stop only ratchets to a new structural higher low / lower high, never to break-even before a partial.
    The session window is the doc's own example (New York open); the doc states no sizing rule, so the
    engine risk percent applies - the same caveat as the playbook's "fits any asset" claim.
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
  * EA_CF_MomentumModelPerformanceDevelopment (card #24): the source is a process video, so the EA is a
    monitor that runs the four-element momentum model against the account and never trades.  The daily
    report-card slots are the three mistakes the document names ("sold too early, didn't respect stop,
    held too long") plus the same discipline vocabulary's revenge entry, which is labelled; the grade
    thresholds (A+ >= 2R, A >= 1R, B > 0, C <= 0 or flagged), the A allocation band (40% - the document
    gives only A+/B/C), the early/late/oversized thresholds and the "held too long" holding-time proxy are
    engineering numbers.  The R multiple is the engine's own planned risk, snapshotted into a registry
    while the position is live because the executor deletes its risk key on close; a trade whose risk was
    never captured is reported as ungraded, never guessed.  Pods, the 10-year horizon, "study the new
    market" and the qualitative setup grade are organisational / human judgements: disclosed, not faked.
  * EA_CF_NasdaqIctAndOrderFlowScalpingStrategy (card #25): bookmap's heatmap, volume dots and spoof
    detection cannot be read from an EA, so the orderflow layer is a tick-volume proxy - the session POC,
    VWAP and body-direction aggression the document itself names - with absorption read as a heavy
    directional bar that fails to take the prior extreme; "watch for spoofing" stays a human task and is
    not faked.  Asia is the default window because the document prefers it, with the New-York window
    alongside it because a CFD broker's US100 may be closed or untradeably wide in Asia while the doc
    trades CME NQ.  The fractal strengths, sweep tolerance, gap floors, freshness windows, aggression
    ratio, POC bin count, the sketchy thresholds, the stop cap, the target floor, the partial and the flip
    confirmation are engineering numbers the document does not state.
  * EA_CF_NqLiquiditySweepReversalScalpingStrategy (card #26): both windows are gated on the document's
    fixed EST clock (UTC-5, never DST-shifted) rather than a local clock; 15/30-second monitoring is not a
    MetaTrader timeframe, so "speed and displacement" is read from M1 bar internals (body share of range,
    range against ATR, tick volume); the document's "points" are NQ index points - one index point = one
    price unit, the family's existing 80/20 convention, exposed as InpIndexPointSize for brokers that quote
    otherwise.  The sweep tolerance, gap floors, freshness windows, the equal-run tolerance and count, the
    confluence threshold for A+ sizing, the daily loss percentage (the document quotes $3,000 on a $160,000
    account = 1.875%) and the RTH scan depth are engineering numbers.  Disclosed, not faked: scale-ins on
    additional FVGs (the engine holds one position per symbol), the "outage gap" reference, copy trading
    across 20 Apex accounts, and the personality / lifestyle / back-test-the-templates / mental-capital
    sections, which are human decisions.
  * EA_CF_OptionsTradingMasterclass (card #27): the document is a fundamentals masterclass - strike,
    expiration and premium, calls and puts, intrinsic vs extrinsic value, time decay, implied volatility,
    the Greeks, liquidity and sizing - and states no entry rule, no exit rule, no stop and no target.  An
    MT5 EA cannot read an option chain either, so the EA is a MONITOR that never trades and audits the
    account against the five operational lessons the playbook teaches: premium as maximum risk, time
    decay, liquidity read as fill quality, the volatility-crush analogue and position sizing.  The premium
    budget, the deployment cap, both style horizons, the slip / spread / expansion flags and the median
    baseline window are engineering numbers and are marked [interpretation]; delta, gamma, theta, vega
    and open interest are option-chain quantities with no CFD feed and are disclosed as not implemented -
    nothing is faked.
  * EA_CF_OrderFlowStrategy (card #28): the document works from a real order feed (75 lots for NQ / 200 for
    ES) and a delta profile; MT5 exposes neither, so "big trades" is a bar far above the window median that
    touches the level and "delta" is body-directional tick volume, with absorption read as a heavy bar that
    tests the level and closes back on the defended side - every stand-in is labelled.  The volume profile
    is built from tick volume in price bins (the family's proxy), the 70% value area and the thin-bin cut
    are the document's own 70% plus an engineering share, and the overnight window is 02:00-14:29 London
    (21:00-09:29 ET all year).  The document's add-on ("averaging up" after confirmation) cannot exist while
    the engine holds one position per symbol: the confirmation instead banks the 1R partial and moves the
    stop to break-even.  NQ runs 2-minute and ES 3-minute charts; one signal timeframe per EA means M2 for
    both.  The DOM speed read and the trader's psychology sections are human, disclosed, not faked.
  * EA_CF_ParabolicShort (card #30): the playbook quotes cap-tier percentages (200 / 100 / 50) measured
    from "the last time price touched the 20-day moving average before the strong move" - the EA implements
    that geometry on D1 and exposes the touch tolerance, the accelerating-leg and base windows, the
    acceleration multiple, the pullback cap, the swing wing/size, the two-day top window, the entry-grade
    selector, the VWAP reclaim/rejection tolerances, the stop buffer, the expected-move target and the
    risk-free add cover multiple as inputs.  "A large part of the move has already happened" is a fraction
    of the expected move; the optional strengthening signs (volume record, round numbers) only raise the
    score.  The risk-free add is enforced literally: the banked partial profit must cover the add risk.
  * EA_CF_PriceAction (card #31): the video-derived playbook is a discretionary routine, so the EA
    implements the mechanical spine only - the H1 pivot levels taken from the pivot candle OPEN (the
    document's own rule), their confidence scores (5/5 strong pivots, 3/5 opening prices, 2.5/5
    invalidated), the three candle patterns on M5, and the stated risk plan (2R target, 50% trim at 2R,
    stop shifted above entry, candle-by-candle trail, two attempts per setup, 2-3 trades a day, one and
    done after a win).  The "[interpretation]" numbers are the pivot wing, tolerances, probe and entry
    distances, the stop buffer, the break-even offset, the second trim and the trail buffer.  The
    pre-market 10-name plan, the calendar check, hiding the P&L and the journaling stars stay human;
    "optional orderflow" (bookmap) has no MT5 signal and is a labelled tick-volume skew, off by default.
    SigFractals is bound to the signal timeframe and returns wick prices, so the H1 open-price scan is
    local by necessity.
  * EA_CF_OrderflowTradingMasterclass (card #29): the document's tools - DOM, heatmap, footprint - do not
    exist in MetaTrader, so "aggression" is body-directional tick volume, the delta divergence is that
    skew failing to progress price, and a "liquidity wall" is a level the session has tested and held
    repeatedly (plus a high-volume node in the tick-volume value profile).  The document states no stop
    size, no target rule, no sizing ladder and no session window: the stop is structural (beyond the
    flush / test extreme), the target is the rotation back to the session's far extreme with a minimum R
    floor, the size is single-risk (a hook exists for the 4-5-touch levels the case study names), and the
    RTH window is the case studies' own context.  The engine's partial / break-even / trailing machinery
    is off because the document states no management rules - the plan's target is the exit.
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
        (r"input double\s+InpStopBufferAtr\s*=\s*0\.15;", '"wide enough to allow the trade to breathe" - an ATR buffer beyond the level'),
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
    # ------------------------------------------- Liquidity trap Playbook (card #18)
    "EA_CF_LiquidityStrategy.mq5": [
        (r"input ENUM_TIMEFRAMES\s+InpContextTf\s*=\s*PERIOD_M30;", '"the focus was on the 30-minute chart" - the level chart'),
        (r"cfg\.signalTimeframe\s*=\s*PERIOD_M5;", '"set up forms on the 5-minute chart" - the execution chart'),
        (r"input int\s+InpFractalBars\s*=\s*2;", "[interpretation]: the swing strength that makes a level"),
        (r"input double\s+InpAwayAtr\s*=\s*1\.0;", '"a high that was respected and caused the price to move away" - the move-away filter'),
        (r"if\(away < InpAwayAtr \* atrCtx\) return false;", "a level that never moved price away holds no liquidity"),
        (r"if\(MathAbs\(levels\[i\]\.level - level\) > InpEqualTolAtr \* atrCtx\) continue;", '"equal lows, meaning multiple lows sitting at the same level" - one pool, not many'),
        (r"levels\[i\]\.touches\+\+;", "the cluster count that marks the playbook's equal highs/lows"),
        (r"if\(side > 0 && r\[i\]\.close > level\) return false;", "a CLOSE through the level consumes the liquidity - the sweep only wicks through"),
        (r"if\(run > InpTrapBars\) return false;", '"the entry came right after the trap was confirmed" - freshness'),
        (r"for\(int i = run \+ 1; i < got; i\+\+\)", '"there was no trade before the level was run" - intactness before the sweep'),
        (r"runExtreme = \(side > 0\) \? MathMax\(runExtreme, r\[i\]\.high\) : MathMin\(runExtreme, r\[i\]\.low\);", '"always cover the last high/low with your stop"'),
        (r"bool rejected = \(side > 0\) \? \(r\[1\]\.close < level\) : \(r\[1\]\.close > level\);", '"right after the break, the price rejected back below the level" - the trap confirmation'),
        (r"int\s+dir\s+= -side;", "the level was taken -> trade the reversal (buy below lows / sell above highs)"),
        (r"if\(dir < 0 && \(ctx\.mid > levels\[i\]\.level \|\| ctx\.mid < levels\[i\]\.level - InpMaxChaseAtr \* ctx\.atr\)\) continue;", '"sell above the high, never below" - the short is taken at the level, never chased'),
        (r"if\(dir > 0 && \(ctx\.mid < levels\[i\]\.level \|\| ctx\.mid > levels\[i\]\.level \+ InpMaxChaseAtr \* ctx\.atr\)\) continue;", "the mirrored buy discipline"),
        (r"cfg\.useLimitEntry\s*=\s*false;", '"use market execution once the high/low is taken and the trap is confirmed"'),
        (r"input double\s+InpStopBufferAtr\s*=\s*0\.10;", "stop just beyond the level that was taken ([interpretation]: the doc quotes no buffer)"),
        (r"double firstPool = PoolTarget\(ctx, dir, entry, levels, count, risk, false\);", '"target liquidity at lows/highs" - the nearest opposing pool'),
        (r"if\(firstPool <= 0\.0\) continue;", '"don\'t trade unless liquidity is built" - no resting pool ahead, no trade'),
        (r"if\(dist < floorDist\) continue;", "[interpretation]: a 1R floor keeps a trade from aiming nearer than its own stop"),
        (r"input double\s+InpClusterReach\s*=\s*1\.6;", "the playbook's own target example is the equal-lows cluster - it wins over a nearer single level"),
        (r"cfg\.partial1AtR\s*=\s*0\.0;", '"don\'t take partials at arbitrary R-multiples" - the engine grid is off'),
        (r"if\(firstPool > 0\.0 && TargetReached\(ctx, dir, firstPool\)\)", '"take them only at actual liquidity targets (internal or external)"'),
        (r"if\(g_eaExec\.ClosePartial\(ticket, InpPartialPct\)\)", "the partial is executed at the pool"),
        (r"cfg\.breakEvenAtR\s*=\s*0\.0;", '"no break-even stops unless partials have been taken"'),
        (r"if\(dir > 0 && newSl >= entry\) continue;", "before a partial the stop may follow structure but never reach break-even"),
        (r"if\(InpMoveStopAfterPartial && !g_eaTrack\[idx\]\.p1Done\) continue;", "no stop management at all before the first partial ([interpretation] of the same rule)"),
        (r"bool improved = \(dir > 0\) \? \(first > second\) : \(first < second\);", '"only move your stop after price moves in your favour and forms a higher low or lower high"'),
        (r"cfg\.trailAtR\s*=\s*0\.0;", '"let trades run to meaningful areas" - no R grid trailing'),
        (r"double runTarget = PoolTarget\(ctx, dir, entry, levels, count, risk, true\);", "the runner is aimed at the furthest resting pool"),
        (r"if\(!ctx\.inSession \|\| ctx\.atr <= 0\.0\) return false;", '"ignore price action outside your session"'),
        (r"cfg\.sessionStartHour = InpSessionStartHour;", '"have a specific session window (e.g. New York Open)"'),
        (r"input int\s+InpMaxTradesPerDay\s*=\s*2;", "[interpretation]: the doc sets no daily trade cap"),
        (r"int idx = EA_TrackIndex\(ticket\);", "engine position tracking is reused for the entry, initial risk and partial state"),
        (r"EA_ApplyStagePolicy\(cfg, InpStage\);", "card #01's stage policy stays available"),
        (r"\[interpretation\]", "every number the playbook leaves open stays labelled"),
    ],
    # ------------------------------------------- Low Volume Node (card #19)
    "EA_CF_LowVolumeNode.mq5": [
        (r"cfg\.signalTimeframe\s*=\s*PERIOD_M5;", "day-trading / scalping playbook - the execution chart"),
        (r"input int\s+InpBaseBars\s*=\s*8;", "[interpretation]: the consolidation window the doc does not state"),
        (r"if\(baseRange <= 0\.0 \|\| baseRange > InpBaseMaxRangeAtr \* atr\) continue;", '"look for a period of market consolidation"'),
        (r"if\(move < InpImpulseMinAtr \* atr\) continue;", '"an impulsive move away ... confirms the presence of strong buyers"'),
        (r"if\(-move < InpImpulseMinAtr \* atr\) continue;", "the mirrored supply case"),
        (r"if\(legLow < bLo\) continue;", "the leg must move AWAY - not back through the base"),
        (r"bool thin = \(k < nb\) && \(binVol\[k\] < InpThinFrac \* avg\);", '"an area where price moved quickly with little to no volume" - the LVN'),
        (r"if\(dir > 0 && zHi < baseHi\) continue;", "demand: the node sits above the base it was left behind from"),
        (r"for\(int dir = 1; dir >= -1; dir -= 2\)", '"go long if you are bouncing off demand or support" first, then the supply side'),
        (r"if\(r\[i\]\.low <= lvHi\) touched = true;", '"now wait for the market to pull back into the LVN"'),
        (r"if\(r\[i\]\.close < lvLo\) return false;", '"aggressive sellers tried to push the price lower, but the price failed to break" - no close-through'),
        (r"bool refused = \(dir > 0\) \? \(r\[1\]\.low <= lvHi && r\[1\]\.close > lvLo\)", '"each time the price broke a low, it was quickly bought back" - absorption'),
        (r"if\(legVol > 0\.0 && avgVol < InpDefenseVolMult \* legVol\) return false;", '"passive buyers were sitting at the level" - participation proxy ([interpretation]: tick volume, not heatmaps)'),
        (r"stopRef = \(dir > 0\) \? MathMin\(ext, lvLo\) : MathMax\(ext, lvHi\);", '"tight stop just below the zone" (or below the recent low)'),
        (r"if\(risk > InpMaxStopAtr \* ctx\.atr\) continue;", "[interpretation]: the tight-stop cap - a setup needing more is skipped"),
        (r"input double InpMaxChaseAtr\s*=\s*0\.25;", "the entry must sit at the node - the doc enters on the defense, never after the run"),
        (r"if\(SigRangeForDay\(ctx\.symbol, g_eaIndTf, 0, nowMin, 0, hod, lod, bars\) && bars > 0\)", '"target ... high of day / low of day"'),
        (r"double prior = \(dir > 0\) \? d\[0\]\.high : d\[0\]\.low;", '"another supply or demand zone" - the prior day extreme'),
        (r"if\(entry >= lvLo\[i\] - tol && entry <= lvHi\[i\] \+ tol\) continue;", '"another LVN" - the runner objective, never the node the trade came from'),
        (r"if\(rr < InpMinRr\) continue;", '"aim for a high reward-to-risk setup"'),
        (r"cfg\.partial1AtR\s*=\s*InpPartial1R;", '"you can scale out or take full profits based on context and volatility"'),
        (r"cfg\.riskPct\s*=\s*InpRiskPct;", '"adjust position size based on stop distance to keep dollar risk the same"'),
        (r"g_eaExec\.Close\(ticket, \"LVN closed through\"\);", "premise exit: a close through the node means the defense failed"),
        (r"if\(barTime == m_lastPremiseBar\) return;", "the premise is evaluated on bar closes, not on every tick"),
        (r"input int\s+InpMaxTradesPerDay\s*=\s*3;", "[interpretation]: the doc sets no daily cap"),
        (r"EA_ApplyStagePolicy\(cfg, InpStage\);", "card #01's stage policy stays available"),
        (r"\[interpretation\]", "every number the playbook leaves open stays labelled"),
    ],
    # ------------------------------------------- Market Auction Theory (card #20)
    "EA_CF_MarketAuctionTheory.mq5": [
        (r"cfg\.signalTimeframe\s*=\s*PERIOD_M5;", '"5-minute chart: execution timeframe"'),
        (r"input double InpBiasBodyMin\s*=\s*0\.60;", '"if the prior day closed strongly bearish, the next day\'s bias is short"'),
        (r"bias = \(d\[1\]\.close < d\[1\]\.open\) \? -1 : \+1;", "the bias comes from the previous day's daily candle"),
        (r"if\(MathAbs\(travel\) < InpSlopeAtr \* ctx\.atrD1\) return false;", '"the daily chart must show a clear 45-degree trend"'),
        (r"if\(bias < 0 && travel >= 0\.0\) return false;", "the slope must run in the bias direction (the mirror check follows)"),
        (r"double ema21 = EmaClose\(d, 21, 1\);", '"use moving average (e.g., 21/50 MAs)" - computed locally, the engine carries the daily 200'),
        (r"if\(bias > 0 && !\(d\[1\]\.close > ema21 && d\[1\]\.close > ema50\)\) return false;", '"for longs: the price must be above the moving averages in both timeframes"'),
        (r"if\(bias < 0 && !\(d\[1\]\.close < ema21 && d\[1\]\.close < ema50\)\) return false;", "the short side of the same rule"),
        (r"if\(bias > 0 && d\[0\]\.open < priorClose\) return false;", '"SPY opened with a gap down ... this added to the bearish sentiment"'),
        (r"if\(bias < 0 && d\[0\]\.open > priorClose\) return false;", "the mirrored gap check"),
        (r"if\(!Aligned\(ctx, bias\)\) return false;", '"if the daily and 5-minute trades are not aligned, skip the trade"'),
        (r"if\(bias > 0\) return \(px > ctx\.ema20 && px > ctx\.ema50 && ctx\.ema20 > ctx\.ema50\);", '"5-minute chart must mirror the daily trend and be aligned with the moving average direction"'),
        (r"if\(!SigRangeForDay\(ctx\.symbol, g_eaIndTf, fromMin, toMin, 0, hi, lo, bars\)\) return false;", "the auction zone: the post-open congestion where price found balance"),
        (r"if\(\(zoneHi - zoneLo\) > InpZoneMaxAtr \* ctx\.atr\) return false;", '"if the auction structure is messy ... stay out"'),
        (r"if\(bias > 0 && m\[i\]\.close > zoneHi\) return true;", '"SPY broke down from this zone shortly after it formed, confirming trend continuation"'),
        (r"if\(m\[i\]\.time < sessionServer\) break;", "only today's bars count for the breakout"),
        (r"bool entered = \(bias < 0\) \? \(m\[i\]\.high >= zoneLo\) : \(m\[i\]\.low <= zoneHi\);", '"it went into the zone"'),
        (r"bool heldOut = \(bias < 0\) \? \(m\[i\]\.close < zoneLo\) : \(m\[i\]\.close > zoneHi\);", '"but then closed below it" - the rejection candle'),
        (r"if\(rejectBar < 0\) return false;", '"if price does not retest the auction zone ... skip"'),
        (r"cfg\.signalOnNewBarOnly\s*=\s*true;", '"entry is made immediately after candle confirmation"'),
        (r"double stop   = \(bias > 0\) \? m\[rejectBar\]\.low  - buffer : m\[rejectBar\]\.high \+ buffer;", '"place the stop loss just beyond the structure\'s high/low of the setup candle"'),
        (r"input double InpTargetR\s*=\s*2\.0;", '"use a minimum 2:1 risk-to-reward ratio"'),
        (r"int endMin = InpOpenMin \+ InpWindowMinutes;", '"focus on the first hour after the open"'),
        (r"input bool\s+InpExtendedWindow\s*=\s*false;", '"avoid trading in the middle or late session unless conditions clearly align"'),
        (r"cfg\.newsFilter\s*=\s*true;", '"if ... sentiment is unclear (e.g., conflicting news headlines), stay out" - the engine calendar gate'),
        (r"input int\s+InpMaxTradesPerDay\s*=\s*2;", "the breakdown's first and second retest"),
        (r"EA_ApplyStagePolicy\(cfg, InpStage\);", "card #01's stage policy stays available"),
        (r"\[interpretation\]", "every number the document leaves open stays labelled"),
    ],
    # ------------------------------------------- Market DNA (card #21)
    "EA_CF_MarketDna.mq5": [
        (r"input ENUM_TIMEFRAMES InpDnaTf\s*=\s*PERIOD_H1;", "[interpretation]: the structure chart the DNA points are read from"),
        (r"input double InpDnaMoveAtr\s*=\s*2\.50;", '"areas where momentum exploded" - the move that marks a DNA point'),
        (r"if\(bHi <= bLo \|\| \(bHi - bLo\) > InpZoneMaxAtr \* atr\) continue;", '"treat levels as zones with ranges, not exact lines"'),
        (r"if\(moveUp >= moveDn && moveUp >= InpDnaMoveAtr \* atr\) side = \+1;", "a demand DNA point: the base produced a big up move"),
        (r"else if\(moveDn > moveUp && moveDn >= InpDnaMoveAtr \* atr\) side = -1;", "the supply DNA point (the short side)"),
        (r"if\(side > 0 && r\[i\]\.close < bLo\) \{ consumed = true; break; \}", '"never let a trade run past the DNA zone once invalidated"'),
        (r"if\(EA_BodyRatio\(m\[1\]\) < InpBodyMin\) return false;", '"enter as close as possible to where aggression confirms" - the displacement bar'),
        (r"double volMult = \(double\)m\[1\]\.tick_volume / avg;", "aggression is measured against participation"),
        (r"if\(volMult < InpAggVolMult\) return false;", '"a valid setup occurs when aggression overwhelms absorption"'),
        (r"if\(m\[1\]\.low > zone\.hi\) return false;", "the bar must test the zone (price must be in play at the level)"),
        (r"if\(m\[1\]\.close <= zone\.hi\) return false;", '"passive sellers fail to hold their liquidity wall" - the close is out of the zone'),
        (r"stopRef = MathMin\(zone\.lo, m\[1\]\.low\);", "the stop reference beyond the zone and the aggression low"),
        (r"double stop = \(dir > 0\) \? stopRef - InpStopBufferAtr \* ctx\.atr", '"place stops just beyond the liquidity zone that defines the DNA level"'),
        (r"if\(risk > InpMaxStopAtr \* ctx\.atr\) continue;", '"risk is reduced ... by minimizing stop distance"'),
        (r"if\(dist < 0\.0 \|\| dist > InpMaxChaseAtr \* ctx\.atr\) continue;", "the entry stays at the level - never chased"),
        (r"input double InpMinRr\s*=\s*3\.00;", '"must achieve 3:1 R:R minimum"'),
        (r"cfg\.partial1AtR\s*=\s*InpPartial1R;", '"scale partials into the first strong reaction"'),
        (r"if\(moveR >= InpPartial1R \* risk && AggressionFlipped\(ctx, dir\)\)", '"hold the remainder until aggression flips on the tape"'),
        (r"if\(dir > 0\) return \(m\[1\]\.close < m\[1\]\.open && m\[1\]\.close < m\[2\]\.low\);", "the flip, read as an opposing displacement close"),
        (r"double structure = FractalStop\(ctx\.symbol, dir\);", '"trail stops behind newly formed aggressive zones"'),
        (r"if\(InpRequireCatalyst && !CatalystPresent\(ctx\)\) return false;", '"the best setups occur when news or earnings push participants into the market" - relative volume'),
        (r"if\(!SessionHasRange\(ctx\)\) return false;", '"no trades in flat/range-bound sessions where aggression is unclear"'),
        (r"input bool\s+InpNewsGate\s*=\s*true;", "the engine calendar stands in for the doc's news catalysts"),
        (r"the doc\'s instrument rule is honoured: stocks \+ futures", '"avoid Forex because you are getting lied to" - honoured by configuration'),
        (r"cfg\.signalTimeframe\s*=\s*PERIOD_M5;", "[interpretation]: M5 stands in for the tape (Level II is not readable by an EA)"),
        (r"input int\s+InpMaxTradesPerDay\s*=\s*2;", "[interpretation]: the doc sets no daily cap"),
        (r"EA_ApplyStagePolicy\(cfg, InpStage\);", "card #01's stage policy stays available"),
        (r"\[interpretation\]", "every reading of the tape stays labelled"),
    ],
    # ------------------------------------------- Mean Reversion (card #22)
    "EA_CF_MeanReversion.mq5": [
        (r"if\(expand < InpExpandMult\) return false;", '"large candles compared to the normal ranges" - the daily context first'),
        (r"if\(volMult < InpVolMult\) return false;", '"high trading volume" - a volume spike confirms the dislocation'),
        (r"double travel = \(d < 0\) \? \(m\[InpSpeedBars\]\.high - m\[1\]\.close\) : \(m\[1\]\.close - m\[InpSpeedBars\]\.low\);", '"the speed of the move is one of the most important factors" - a signed, positive travel'),
        (r"if\(travel < InpSpeedAtr \* ctx\.atr\) continue;", "far and fast: the displacement must be real"),
        (r"if\(run < InpStreakBars\)", '"when an asset moves several bars ... in the same direction, the probability of a reversal begins to increase"'),
        (r"bool panicCandle = false;", '"in rare situations where the move is extremely fast, the reversal may occur within a single candle"'),
        (r"if\(dir > 0 && m\[i\]\.close > m\[i \+ 1\]\.high\) \{ breakBar = i; return true; \}", '"the reversal begins when those highs are broken" - entry on the break'),
        (r"if\(dir < 0 && m\[i\]\.close < m\[i \+ 1\]\.low\) \{ breakBar = i; return true; \}", '"this indicates that buyers have lost control ... the entry occurs on the downside break"'),
        (r"double stop  = \(dir > 0\) \? capExtreme - InpStopBufferAtr \* ctx\.atr", '"the stop was placed below the low of the capitulation move"'),
        (r"if\(entry > 0\.0 && \(risk / entry\) \* 100\.0 > InpMaxStopPct\) return false;", '"the stop must clearly define the risk of the trade"'),
        (r"double mean = ctx\.ema20;", '"a useful reference for equilibrium is the 20-period moving average, which represents the center of the Bollinger Bands"'),
        (r"if\(toMean >= InpMinRr \* risk\) target = mean;", '"the first bounce often moves toward this level" - the realistic target'),
        (r"if\(score < 3\) return false;", '"lower quality setups may be traded smaller or avoided entirely"'),
        (r"m_qualityMult = \(score >= 5\) \? InpSizeHigh : \(\(score >= 4\) \? InpSizeMid : 1\.0\);", '"higher quality setups may justify larger position sizes"'),
        (r"if\(m_isShort\) mult \*= InpShortSizeMult;", '"short trades require additional risk management" - the structural asymmetry'),
        (r"if\(m_isPanic\) mult \*= InpPanicSizeMult;", '"position size should be smaller because the risk is less clearly defined"'),
        (r"double prior = PriorBarExtreme\(ctx\.symbol, dir\);", '"trailing the stop below prior bar lows" (above prior bar highs for shorts)'),
        (r"if\(dir > 0 && newSl >= ctx\.bid\) continue;", "the trail never parks the stop inside the market"),
        (r"cfg\.partial1AtR\s*=\s*1\.0;", '"the strategy focuses on capturing the initial retracement toward equilibrium"'),
        (r"input double InpMaxStopPct\s*=\s*4\.00;", "[interpretation]: the risk window the document leaves unstated"),
        (r"cfg\.signalTimeframe\s*=\s*PERIOD_M5;", "[interpretation]: the intraday execution chart"),
        (r'"News vs fundamental change"', '"news vs fundamental change" is disclosed: an EA cannot tell the two apart'),
        (r"input double InpDisplaceAtrD1\s*=\s*1\.00;", "[interpretation]: how far the displacement must travel"),
        (r"input int\s+InpMaxTradesPerDay\s*=\s*2;", "[interpretation]: the doc sets no daily cap"),
        (r"EA_ApplyStagePolicy\(cfg, InpStage\);", "card #01's stage policy stays available"),
        (r"\[interpretation\]", "every number the document leaves open stays labelled"),
    ],
    # ------------------------------------------- Measured Move Trend (card #23)
    "EA_CF_MeasuredMove.mq5": [
        (r"input ENUM_TIMEFRAMES InpStructTf\s*=\s*PERIOD_H4;", '"most effective on higher timeframes" - swing trading'),
        (r"if\(dir < 0\) trendOk = \(sh\[0\] < sh\[1\]\);", '"in a downtrend: price continues forming lower highs and lower lows"'),
        (r"else\s+trendOk = \(sh\[0\] > sh\[1\]\);", "the uptrend mirror"),
        (r"if\(dir < 0\) trendOk = trendOk && \(sl\[0\] < sl\[1\]\);", "lower lows complete the downtrend definition"),
        (r"a1 = sl\[1\]; a2 = sl\[0\];", '"a trendline across the pullback lows" for the mirrored structure'),
        (r"double lineAtExt = ValueOnLine\(b1, a1, b2, a2, extBar\);", '"measure vertically from that candle up to the trendline"'),
        (r"measure = \(dir < 0\) \? \(lineAtExt - ext\) : \(ext - lineAtExt\);", "the measured distance - the structure's height to the trendline"),
        (r"double target = \(dir > 0\) \? \(structHigh \+ measure\) : \(structLow - measure\);", '"project that same distance downward in a downtrend / upward in an uptrend"'),
        (r"if\(touchTol|touched = true; break;", '"wait for the pullback to form and begin rejecting the trendline"'),
        (r"bool reject = \(dir < 0\) \? \(m\[1\]\.close < m\[1\]\.open && m\[1\]\.close < m\[2\]\.low\)", '"enter as the price starts moving back in the direction of the trend"'),
        (r"double stopRef = \(dir > 0\) \? MathMin\(structLow,  lineNow\) : MathMax\(structHigh, lineNow\);", '"place the stop above the trendline or recent swing high" (below for longs)'),
        (r"input double InpStopBufferAtr\s*=\s*0\.20;", '"avoid placing stops too tight, as price may retest the trendline before continuing"'),
        (r"bool confirmed = \(dir < 0\) \? \(m\[1\]\.close > lineNow\) : \(m\[1\]\.close < lineNow\);", '"ideally, wait for a confirmed close above the trendline before invalidating"'),
        (r"cfg\.partial1AtR\s*=\s*0\.0;", '"the core idea is to allow the full move to play out"'),
        (r"if\(structBars > InpMaxStructBars\) return false;", '"the structure becomes too extended or irregular"'),
        (r"if\(structBars < InpMinPullbackBars\) return false;", '"price collapses sharply without forming a proper pullback"'),
        (r"if\(structures > InpMaxStructures\) continue;", '"by the fourth or fifth pattern, the move often becomes exhausted"'),
        (r"if\(InpShrinkIsWarning && nh >= 2 && nl >= 2\)", '"when the structures become smaller ... this signals that the trend may be ending"'),
        (r"bool stretched = false;", '"Bollinger Bands are used to determine whether the price is stretched"'),
        (r"stretched = \(dir < 0\) \? \(structHigh >= bbUp \* 0\.999\)", '"in a downtrend, early structures forming near the upper band are higher probability"'),
        (r": \(structLow  <= bbLo \* 1\.001\);", "the uptrend mirror near the lower band"),
        (r"double sd = MathSqrt\(var / \(double\)InpBbPeriod\);", "[interpretation]: the 2-sigma Bollinger setting the doc leaves to the platform default"),
        (r"if\(InpUseDailyContext && !DailyContext\(sym, dir\)\) return false;", '"identify direction on higher timeframes, execute on lower timeframes"'),
        (r"plan\.score    = 68\.0 \+ \(stretched \? 8\.0 : 0\.0\)", "the doc's higher-probability structures rank first"),
        (r"EA_ApplyStagePolicy\(cfg, InpStage\);", "card #01's stage policy stays available"),
        (r"\[interpretation\]", "every line the document draws by eye stays labelled"),
    ],
    # -------------------------------------- Momentum Model Performance Development (card #24)
    "EA_CF_MomentumModelPerformanceDevelopment.mq5": [
        (r"input string InpReportFile\s*=\s*\"cf_momentum_daily_report\.csv\";",
         '"Each day, traders list 3-4 mistakes without judgment" -> the daily report card file'),
        (r"DailyReportCard\(day - 86400\);", "the card is written for the day that just ended"),
        (r"input double InpStopTolR\s*=\s*0\.10;",
         '"didn\'t respect stop" -> a loss beyond -(1 + tol) R is a stop violation'),
        (r"input double InpEarlyExitR\s*=\s*0\.50;", '"sold too early" -> a winner taken below 0.5R'),
        (r"input int\s+InpEarlyExitMin\s*=\s*20;", '"sold too early" also read from the short hold'),
        (r"input int\s+InpMaxHoldMinutes\s*=\s*240;", '"held too long" -> a small winner held for hours'),
        (r"input int\s+InpRevengeMinutes\s*=\s*30;",
         "[interpretation] the 4th mistake slot: an entry straight after a losing close"),
        (r"fl\.grade\s*=\s*3;\s*// ungraded until proved otherwise",
         "a trade whose risk was never captured is reported as ungraded, never guessed"),
        (r"listed WITHOUT judgement", '"it is data collection, not self-criticism"'),
        (r"input string InpPromptFile\s*=\s*\"cf_momentum_five_whys\.txt\";",
         '"diagnose with five whys" -> the weekly prompt file'),
        (r"why 4: why did that happen", '"the real solution emerges at the fourth or fifth level"'),
        (r"the real solution appears at level 4-5", "the prompt says why the stop rules matter"),
        (r"input ENUM_CF_FOCUS_SKILL InpFocusSkill\s*=\s*CF_FOCUS_STOPLOSS;",
         '"one goal at a time ... risk management is the foundation"'),
        (r"directive = \"LOCK: fix stop-loss discipline before anything else \(one goal at a time\)\";",
         "with stop-loss as the one goal, a violation locks the day instead of being a note"),
        (r"input double InpBandAPlusPct\s*=\s*80\.0;", '"A+ gets 80% of daily stop"'),
        (r"input double InpBandBPct\s*=\s*15\.0;", '"B gets 15%"'),
        (r"input double InpBandCPct\s*=\s*5\.0;", '"C gets 5%"'),
        (r"input double InpBandAPct\s*=\s*40\.0;",
         "[interpretation] the document names an A grade but prints no percentage for it"),
        (r"\(rt\.riskMoney / InpDailyStopUsd\) \* 100\.0 > bandPct \+ InpBandTolPct",
         '"this prevents oversizing on weak setups" -> the risk actually taken is audited against the band'),
        (r"else if\(rt\.rMult >= 2\.0\)\s+fl\.grade = -1;",
         '"A+ opportunities do not happen often" -> only a 2R-plus trade grades A+'),
        (r"input int\s+InpMaxPlaybooksPerWeek\s*=\s*1;",
         '"master one playbook before adding others"'),
        (r"too many playbooks at once - master one first", "the weekly row flags trading several playbooks"),
        (r"if\(!fl\.stopViolation && !fl\.earlyExit && !fl\.heldTooLong && !fl\.revenge && !fl\.oversized\)\s*\n\s*smallWins\+\+;",
         '"stack small wins" -> rule-following trades are counted as the small wins'),
        (r"if\(oneTradeShare > 0\.6\)",
         '"not one big breakthrough moment" -> a week carried by a single trade is flagged'),
        (r"input int\s+InpWeeksForReview\s*=\s*5;",
         '"Track small wins weekly. After 4-5 weeks, review your progress"'),
        (r"weeksLogged % MathMax\(1, InpWeeksForReview\) == 0",
         "the process review fires every five logged weeks"),
        (r"the number of small wins generated",
         '"the number of small wins generated will dictate the success that you have as a trader"'),
        (r"input string InpWinsFile\s*=\s*\"cf_momentum_weekly_wins\.csv\";",
         "the weekly small-wins row is the deliverable the review reads"),
        (r"bool AllowTrading\(SEAContext &ctx\) \{ return false; \}",
         "a process is measured, not executed: the monitor never trades"),
        (r"string rk = \"EA_\" \+ IntegerToString\(\(long\)magic\) \+ \"_R\" \+ IntegerToString\(\(long\)t\);",
         "R is the engine's own planned risk: the executor's persisted key is snapshotted while live"),
        (r"rt\.rMult\s*=\s*\(rt\.riskMoney > 0\.0\)\s*\?\s*money / rt\.riskMoney\s*:\s*0\.0;",
         "R is defined exactly as the engine defines it (money over planned risk)"),
        (r"EA_ApplyStagePolicy\(cfg, InpStage\);", "card #01's stage policy stays available"),
        (r"\[interpretation\]", "every element the document leaves open stays labelled"),
        (r"10-year horizon",
         "pods, the 10-year career and studying a new market are disclosed, not faked"),
        (r"cfg\.sourceDoc\s*=\s*\"chartfanatics/glimpse/WDdvnd9vLbM\.md \(card #24\)\";",
         "the monitor names its source and board card"),
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
    ],    # -------------------------------------- Nasdaq ICT + Order Flow Scalping (card #25)
    "EA_CF_NasdaqIctAndOrderFlowScalpingStrategy.mq5": [
        (r"input ENUM_TIMEFRAMES   InpMacroTf\s*=\s*PERIOD_H4;",
         '"Use 4-hour and daily charts to identify the overall trend"'),
        (r"if\(sh\[0\] > sh\[1\] && sl\[0\] > sl\[1\]\) bias = \+1;",
         '"Markets move in trends with higher highs/lows"'),
        (r"if\(retrace < InpRetraceMin \|\| retrace > InpRetraceMax\) return false;",
         '"then pull back to fair value (internal range liquidity) before continuing" - the pullback-depth band'),
        (r"input bool              InpUseD1Filter\s*=\s*true;",
         '"4-hour and daily charts" - the daily sanity check beside the H4 structure'),
        (r"input ENUM_TIMEFRAMES   InpSecondTf\s*=\s*PERIOD_H1;",
         'STEP 2 - "On 15-minute and 1-hour charts"'),
        (r"if\(r\[1\]\.close >= sh\[0\]\) return false;",
         '"weakness in the secondary structure (volume, closure below previous highs) before shorting"'),
        (r"if\(dir < 0\) return \(dn >= InpVolumeMult \* up\);",
         '"... (volume, closure below previous highs)" - the volume half of the weakness read'),
        (r"if\(!\(left\.high < right\.low && \(right\.low - left\.high\) >= InpMinGapAtr \* ctx\.atr\)\) continue;",
         'IFBG - "creates a fair value gap"'),
        (r"bool swept = \(dir < 0\) \? \(m\[s\]\.high > prior \+ tol\) : \(m\[s\]\.low < prior - tol\);",
         '"Price takes liquidity above a previous high" / "Requires liquidity to be swept first"'),
        (r"bool closedThrough = \(dir < 0\) \? \(m\[1\]\.close < gapLow - tol\) : \(m\[1\]\.close > gapHigh \+ tol\);",
         'IFBG - "then closes with volume below that gap"'),
        (r"retest = \(m\[1\]\.high >= level - tol && m\[1\]\.close < level - tol\);",
         'change of character - "breaks, retests, and closes below with volume"'),
        (r"if\(!HasGap\(m, got, j, dir, level, ctx\.atr\)\) continue;",
         'break and retest - "Must see a fair value gap displacing the previous high"'),
        (r"if\(dn >= InpVolumeMult \* up\) return -1;",
         '"large volume spikes on the sell side (red), sellers are aggressive"'),
        (r"if\(flow\.poc > flow\.vwap\) return false;",
         '"If POC is moving down, bearish volume is dominating"'),
        (r"if\(prior > 0\.0 && m\[i\]\.high < prior - InpSweepTolAtr \* ctx\.atr\) return true;",
         '"If buyers can\'t push price above a level despite high buy volume, sellers are absorbing those buys"'),
        (r"input ENUM_CF_WINDOW    InpWindow\s*=\s*CF_WINDOW_ASIA;",
         '"Asia session on NASDAQ tends to have clearer structure and less manipulation"'),
        (r"cfg\.signalTimeframe\s*=\s*PERIOD_M1;",
         '"Trading 30-second or 1-minute charts reveals crystal-clear structure and allows tight stops"'),
        (r"return \(risk <= InpMaxStopAtr \* ctx\.atr\);",
         '"trading 5-minute charts results in huge stop-losses" - setups needing a wider stop are skipped'),
        (r"bool havePd = SigDonchian\(ctx\.symbol, \(int\)MathMax\(1, InpPoolDays\), pdHi, pdLo\);",
         '"took profit before hitting a strong resistance (previous daily high)"'),
        (r"g_eaExec\.Close\(ticket, .orderflow flipped - close early rather than risk reversal.\);",
         '"he closed early rather than risk reversal"'),
        (r"if\(flow\.sessionAvgVol > 0\.0 && recent < InpSketchyVolMult \* flow\.sessionAvgVol\) return true;",
         '"low volume" -> close at break-even or skip the trade'),
        (r"if\(flow\.sessionHi > flow\.sessionLo && \(flow\.sessionHi - flow\.sessionLo\) < InpSketchyRangeAtr \* ctx\.atr\)",
         '"piano-like price action"'),
        (r"if\(flow\.pocDominance > 0\.0 && flow\.pocDominance < InpSketchyPocDom\) return true;",
         '"unclear POC" from the action items'),
        (r"cfg\.partial1AtR\s*=\s*1\.0;",
         '"took profit before hitting a strong resistance" - the 1R partial'),
        (r"cfg\.trailAtR\s*=\s*1\.0;",
         '"He trailed his stop"'),
        (r"input double            InpCloseSketchyR\s*=\s*0\.50;",
         '"close at break-even ... Prioritize capital preservation"'),
    ],    # -------------------------------------- NQ liquidity sweep & reversal scalping (card #26)
    "EA_CF_NqLiquiditySweepReversalScalpingStrategy.mq5": [
        (r"input int\s+InpKzStartHourEst\s*=\s*2;",
         '"Candice only trades London session between 2am-5am EST"'),
        (r"input ENUM_CF_SESSION\s+InpSessions\s*=\s*CF_SESSION_BOTH;",
         '"She trades London and New York sessions"'),
        (r"return EA_ServerToUtc\(serverTime\) - \(datetime\)\(5 \* 3600\);",
         "the document's windows live on the fixed EST clock (UTC-5, never DST-shifted)"),
        (r"bool london = \(now >= kzS && now < kzE\);",
         '"She avoids pre-2am setups despite temptation"'),
        (r"bool sweptAsia  = haveAsia && \(\(dir > 0\) \? \(m\[sw\]\.low < asiaLo - tol\) : \(m\[sw\]\.high > asiaHi \+ tol\)\);",
         '"identifying where price has swept liquidity (Asia high/low ...)"'),
        (r"bool sweptSwing = \(dir > 0\) \? \(m\[sw\]\.low < prior - tol\) : \(m\[sw\]\.high > prior \+ tol\);",
         '"... swing highs/lows"'),
        (r"if\(!\(left\.low > right\.high && \(left\.low - right\.high\) >= minGap\)\) continue;",
         '"A bearish FVG forms when price gaps down without filling the gap"'),
        (r"if\(!\(m\[1\]\.close > gapFar \+ tol\)\) continue;",
         '"When a bullish candle closes above it, it becomes an inverted FVG"'),
        (r"if\(m\[2\]\.close > gapFar \+ tol\) continue;",
         '"conservative traders wait for the candle to fully close above it" - a fresh inversion'),
        (r"input double\s+InpLondonMaxStopPts = 25\.0;",
         '"London session: 20-25 point max stop loss"'),
        (r"input double\s+InpNyMaxStopPts\s*=\s*40\.0;",
         '"New York session: 30-40 points"'),
        (r"if\(MathAbs\(entry - candidate\) > maxStop\) continue;",
         '"If I had to use a larger stop loss to enter, that means that is not the entry point."'),
        (r"double need = InpMinRR \* risk;",
         '"a 1:2 minimum ratio"'),
        (r"q75 = lo \+ InpRthTargetPct / 100\.0 \* \(hi - lo\);",
         '"she targets the 75 percent level"'),
        (r"midnight = m\[i\]\.open;",
         '"mark your higher timeframe liquidity (... RTH gap, midnight opening price)"'),
        (r"return \(m_lastConf >= InpAPlusConfluences\) \? 1\.0 : InpBCSizeMult;",
         '"A+ setups with multiple confluences: 5 contracts ... B/C setups: 2 contracts"'),
        (r"return \(matches >= InpEqualCount\);",
         '"a series of equal highs or lows showing price is building momentum"'),
        (r"cfg\.dailyLossPct\s*=\s*InpDailyLossPct;",
         '"set a fixed daily loss limit in dollars ... Once hit, she stops trading"'),
        (r"cfg\.partial1AtR\s*=\s*1\.0;",
         '"takes partial profits at the first internal liquidity or swing high"'),
        (r"if\(g_eaExec\.ClosePartial\(ticket, \(double\)InpPartialPct\)\)",
         '"if price enters it during a trade, she closes at least half the position"'),
        (r"if\(newSl > sl \+ ctx\.point \* 0\.5\) g_eaExec\.Modify\(ticket, newSl, tp\);",
         '"she trails her stop to a tighter level - sometimes to break-even"'),
        (r"cfg\.signalTimeframe\s*=\s*PERIOD_M1;",
         '"Candice enters on 1-minute charts"'),
        (r"if\(IsDisplacement\(m\[1\], ctx\)\) conf\+\+;",
         '"speed and displacement: why seconds matter" - read from M1 bar internals'),
        (r"if\(InpOnlyAPlus && conf < InpAPlusConfluences\) continue;",
         '"On your first 20 trades, focus only on A+ setups" - off by default'),
        (r"if\(DailyFvgSwept\(ctx, m, s\.sweepBar, dir\)\) conf\+\+;",
         '"daily FVG sweep" confluence'),
        (r"if\(H1FvgAligned\(ctx, dir, h1a, h1b\)\) conf\+\+;",
         '"1-hour FVG fill" confluence'),
    ],    # -------------------------------------- options trading masterclass (card #27)
    "EA_CF_OptionsTradingMasterclass.mq5": [
        (r"input double\s+InpPremiumBudgetPct\s*=\s*1\.0;",
         'R1 premium: "The premium ... is also the maximum risk for the buyer" - money at risk per position stays inside the budget'),
        (r"double perLot = InpUseAllInRisk",
         'R1b "you pay only a fraction - known as the premium": the budget counts the full money at risk, commission included'),
        (r"bool\s+noStop\s*=\s*\(sl\s*<=\s*0\.0\);",
         'R2 "Buyers pay the premium ... Their risk is capped at that premium" - a CFD position with no stop has no defined premium and is flagged'),
        (r"double money\s*=\s*MoneyAtRisk\(sym, volume, dist\);",
         'R2b the premium analogy priced in account money: stop distance x volume through EA_LossPerLot'),
        (r"DayHoldStats\(day, avgHold, maxHold, trades, beyond\);",
         'R3 "time is constantly working against the buyer" - holding times read from the entry deal to the exit deal'),
        (r"input double\s+InpMaxHoldHoursDay\s*=\s*8\.0;",
         'R4 "Day traders may prefer weekly or zero-day contracts"'),
        (r"input double\s+InpMaxHoldHoursSwing\s*=\s*120\.0;",
         'R4b "swing traders often benefit from expirations weeks or months away"'),
        (r"double slipR\s*=\s*SlipAcrossScope\(\);",
         'R5 "Liquidity determines how easily you can get in and out of a trade without delays or poor fills"'),
        (r"double v = EA_SlipMedianR\(g_eaSymbols\[i\]\);",
         'R6 "if a strike only has 100 contracts of open interest and you want to buy 70 contracts, you may struggle to get filled quickly"'),
        (r"input double\s+InpSpreadFlagPts\s*=\s*5\.0;",
         'R6b "High open interest means more market participants at that strike, which generally leads to smoother and faster fills"'),
        (r"double ratio = VolExpansionRatio\(sym\);",
         'R7 "implied volatility usually spikes ... Once the news is released, IV often drops sharply" - the expansion is read at entry'),
        (r"input double\s+InpVolExpansionFlag\s*=\s*1\.50;",
         'R7b "This is known as volatility crush" - no IV feed exists for a CFD, so realised range expansion is the labelled proxy'),
        (r"input double\s+InpMaxDeployedPct\s*=\s*3\.0;",
         'R8 "how you size your positions matters"'),
        (r"bool sizingOk\s*=\s*\(m_dayMaxDeployedPct <= InpMaxDeployedPct\);",
         'R8b "Options offer incredible leverage - but without discipline, losses can compound just as quickly as gains."'),
        (r'input string\s+InpTentFile\s*=\s*\"cf_options_tenets\.txt\";',
         'R9 "Master the basics, respect the risks, and options can become one of the most effective tools in your trading arsenal."'),
        (r"option-chain quantities with no CFD feed",
         'R10 delta / gamma / theta / vega and open interest: disclosed as not implemented, no fake Greek is printed'),
        (r"bool BuildPlan\(SEAContext &ctx, SSignalPlan &plan\) \{ plan\.Reset\(\); return false; \}",
         'R11 the document states no entry rule - the EA is a monitor and never proposes a trade'),
    ],
    # -------------------------------------- order flow strategy (card #28)
    "EA_CF_OrderFlowStrategy.mq5": [
        (r"input int\s+InpOvernightFromMin = 120;",
         '"overnight high/low (9 PM-9:29 AM EST)" - 02:00 London all year'),
        (r"lv\.haveOn = SigRangeForDay\(sym, g_eaIndTf, InpOvernightFromMin, InpOvernightToMin, 0,",
         '"Price respects ... overnight high/low" - the engine session-range builder'),
        (r"lv\.haveOrb = SigRangeForDay\(sym, g_eaIndTf, InpOrbFromMin, InpOrbToMin, 0,",
         '"a 30-minute opening range breakout (ORB)"'),
        (r"int got = EA_Rates\(sym, PERIOD_D1, 1, 2, d\);",
         '"previous day high/low" as a generated level'),
        (r"input double InpValueAreaPct\s+= 0\.70;",
         '"Volume profile shows where 70% of transactions occur"'),
        (r"while\(covered < InpValueAreaPct \* total",
         'the value area expanded out of the POC until 70% is covered'),
        (r"input double InpThinBinPct\s+= 0\.35;",
         '"low volume nodes signal trending moves and breakouts"'),
        (r"if\(ThinZone\(prof, binVol, meanBin, dir, price, zoneLo, zoneHi\) && zoneLo > vaLo && zoneHi < vaHi\)",
         '"when price trades inside value areas with no low volume nodes"'),
        (r"input double InpBigTradeMult\s+= 2\.50;",
         '"filters orders above a threshold (75 lots for NQ, 200 for ES)" - a tick-volume proxy is used'),
        (r"input double InpDeltaLean\s+= 0\.20;",
         '"Delta = ask transactions minus bid transactions" - body-volume proxy'),
        (r"bool absorp\s+= Absorption\(ctx, level, dir\);",
         '"Absorption occurs when aggressive sellers hit the bid but price does not fall"'),
        (r"input int\s+InpMinCriteria\s+= 2;",
         '"At least two confirmations ... create a valid trade"'),
        (r"input int\s+InpAPlusCriteria\s+= 3;",
         '"three or four alignments create A+ setups"'),
        (r"return \(m_lastCrit >= InpAPlusCriteria\) \? 1\.0 : InpBCSizeMult;",
         '"Aggressive Entry = Smaller Size" - A+ full risk, B/C smaller'),
        (r"if\(!Chasing\(ctx\)\) best = c;",
         '"Never Trade Against Momentum"'),
        (r"bool MiddleOfRange\(const SEAContext &ctx, const SVolProfile &prof\)",
         '"Chop in the middle of ranges has poor risk-to-reward"'),
        (r"bool FadePlan\(const SEAContext &ctx, const SLevels &lv, const SVolProfile &prof, SCfCandidate &out\)",
         '"sell into breakouts (where they enter)" - the wick-through trap'),
        (r"cfg\.partial1AtR\s+= InpPartial1R;",
         '"target the midpoint first, then the opposite edge"'),
        (r"cfg\.breakEvenAtR\s+= InpBreakEvenR;",
         '"Never Let a Winner Go Red" / "move stop to break-even"'),
        (r"cfg\.maxTradesPerDay\s+= InpMaxTradesPerDay;",
         '"Trader limits himself to 2-3 trades per day"'),
        (r"input int\s+InpEntryToMin\s+= 1050;",
         '"Only Trade First 1-3 Hours" - 12:30 ET = 17:30 London'),
        (r"r\[0\]\.high < r\[1\]\.high && r\[1\]\.high < r\[2\]\.high",
         '"watching for lower highs (exit signal)"'),
        (r"input double InpTrendMinRR\s+= 1\.50;",
         '"on trend days with limited pullbacks, accept tighter ratios (1.5-2 R)"'),
        (r"input double InpRangeMinRR\s+= 2\.00;",
         'aggressive entries target 3-4 R, confirmation entries 2 R'),
    ],
    # -------------------------------------- orderflow masterclass (card #29)
    "EA_CF_OrderflowTradingMasterclass.mq5": [
        (r"input double InpAbsorbVolMult\s+= 2\.00;",
         '"Absorption happens when aggressive orders hit the market, but the price barely moves"'),
        (r"if\(\(double\)r\[i\]\.tick_volume < InpAbsorbVolMult \* med\) continue;",
         'the aggressive-side read comes from volume - it must be heavy to count'),
        (r"input int\s+InpDeltaBars\s+= 12;",
         '"Delta shows the difference between aggressive buyers and aggressive sellers" - body-volume proxy'),
        (r"if\(dir < 0 && lean <  InpDeltaLeanCut\) return false;",
         '"if you see a strong positive delta but the price fails to move higher, it means buyers were absorbed"'),
        (r"input double InpAbsorbMaxProgress\s+= 0\.25;",
         '"moving higher" never happened: progress beyond the level must stay tiny'),
        (r"if\(EA_WickRatio\(r\[i\], -1\) < InpWickPct\) continue;",
         'the rejection wick - the price was pushed back from the level'),
        (r"input int\s+InpStrongTouchCount\s+= 4;",
         '"it had already acted as support four or five times earlier in the session"'),
        (r"int TouchCount\(const string sym, const double price, const double tol\)",
         'a liquidity wall, proxied as a level the session has tested and held repeatedly'),
        (r"bool StopRunReclaim\(const SEAContext &ctx, const MqlRates &r\[\], const int got,",
         '"A stop run happens when the market pushes through obvious highs or lows to trigger stop losses"'),
        (r"if\(r\[k\]\.close > lvl\.price\) \{ reclaimed = true; break; \}",
         '"Once the price reclaimed the previous day.s low, that confirmed buyers had absorbed the selling"'),
        (r"out\.stop = r\[i\]\.low - buf;",
         '"a stop just below the low of the flush"'),
        (r"input int\s+InpReclaimBars\s+= 3;",
         '"the long entry came on the reclaim" - within this many bars'),
        (r"bool ImpulseContext\(const SEAContext &ctx\)",
         '"Context" - "aggressive participants reveal intent": a real push must exist'),
        (r"bool CollectLevels\(const SEAContext &ctx, const SVolProfile &prof, SLevelInfo &lv\[\], int &n\)",
         '"Location" - a documented level (previous day, session extreme, value area, repeated test)'),
        (r"bool AbsorptionAt\(const SEAContext &ctx, const MqlRates &r\[\], const int got,",
         '"Confirmation" - absorption at the level'),
        (r"input double InpValueAreaPct\s+= 0\.70;",
         '"The volume profile shows ... where the market accepted the value and where it rejected it"'),
        (r"input double InpMinRR\s+= 1\.50;",
         'the document states no target rule - the rotation must at least pay for the risk'),
        (r"cfg\.partial1AtR\s+= 0\.0;",
         'the document states no management rules: the plan.s target is the exit'),
        (r"return \(m_lastTouches >= InpStrongTouchCount\) \? InpStrongSizeMult : 1\.0;",
         'the well-tested levels get the size hook the document.s silence leaves open'),
        (r"input int\s+InpSessionStartHour\s+= 14;",
         'day trading: the regular session, 14:30 London = 09:30 ET'),
    ],
    # -------------------------------------- parabolic short (card #30)
    "EA_CF_ParabolicShort.mq5": [
        (r"CF_PS_SMALL = 200,",
         '"a small-cap stock generally needs to move around 200 percent or more from its last base"'),
        (r"CF_PS_LARGE = 50\s+// Large cap",
         '"a large-cap stock can qualify with a move closer to 50 percent"'),
        (r"input string\s+InpSymbolsToTrade",
         'the playbook trades stocks; the universe is the user list'),
        (r"//--- R2: the base - the most recent 20-day-MA touch BEFORE the accelerating leg",
         '"the move should always be measured from the most recent base, not the absolute bottom" / "the last time price touched the 20-day moving average before the strong move began"'),
        (r"if\(pc\.movePct < RequiredMovePct\(\)\) return false;",
         'the size filter is enforced: the extension from the base must clear the tier'),
        (r"pc\.accelOk = \(baseRange <= 0\.0\) \|\| \(pc\.accelRatio >= InpAccelMult\) \|\| gapUp;",
         '"price starts accelerating, candles become large, and the slope becomes steep"'),
        (r"if\(d\[i\]\.open > d\[i \+ 1\]\.high\) \{ gapUp = true; break; \}",
         '"in some cases, there are gaps between sessions"'),
        (r"if\(pc\.pullbackFrac > InpMaxPullbackFrac\) return false;",
         '"these pullbacks release pressure, which reduces the chance of a sharp reversal"'),
        (r"pc\.volRecord = \(bestI >= 1 && bestI <= InpAccelBars\);",
         '"when volume reaches the highest levels seen in recent history, it often means the final wave of buyers has entered the trade"'),
        (r"double level = MathFloor\(pc\.topHigh / InpRoundStep\) \* InpRoundStep;",
         '"round numbers like 100, 300, or 500 attract attention"'),
        (r"else if\(topYest > topPrev \+ tol\)",
         '"the exhaustion day usually happens on the same day as the final push higher, or the following day. If nothing happens within two days, the setup should be ignored"'),
        (r"input int\s+InpMaxDaysSinceTop\s+= 2;",
         'the two-day window is an input, not a hidden constant'),
        (r"ss\.belowVwap = \(m\[1\]\.close < ss\.vwap\);",
         '"on a true exhaustion day, price moves below VWAP and is unable to reclaim it"'),
        (r"ss\.strongReclaim = \(m\[1\]\.close > reclaim \|\| m\[2\]\.close > reclaim\);",
         '"if the price stays above VWAP and continues higher, the setup is not active"'),
        (r"ss\.lowerHighs = \(foundH >= 2 && ph0 < ph1\);",
         '"price stops making higher highs. Lower highs begin to form"'),
        (r"ss\.lowerLows  = \(foundL >= 2 && pl0 < pl1\);",
         '"followed by lower lows"'),
        (r"if\(!ss\.lowerHighs \|\| !ss\.lowerLows\) return false;",
         'every graded entry needs the broken structure first'),
        (r"CF_PS_STRUCTURE   = 0,",
         '"the first type of entry comes when price breaks its upward structure and starts forming lower highs and lower lows. This is earlier and carries more risk"'),
        (r"if\(m\[i\]\.close < ss\.vwap && foundL >= 2 && m\[i\]\.close < pl1\)",
         '"a stronger entry happens when price breaks structure and loses VWAP at the same time"'),
        (r"CF_PS_VWAP_REJECT = 2",
         '"the best entry occurs when price tries to move back above VWAP and fails"'),
        (r"if\(stayedBelow\) \{ ss\.vwapReject = true; break; \}",
         '"price tries to move back above VWAP and fails ... confirms that buyers cannot regain control"'),
        (r"if\(ctx\.tradesToday >= InpMaxAttempts\) return false;",
         '"if the setup fails once, a second attempt can be taken. If it fails again, it is best to move on"'),
        (r"double stopLevel = \(InpUseLowerHighStop && ss\.lastLowerHigh > ctx\.bid\)",
         '"a common stop level is the high of the day or the most recent lower high"'),
        (r"cfg\.partial1AtR\s+= InpPartialAtR;",
         '"partial profits should be taken once the trade moves in your favor"'),
        (r"cfg\.breakEvenAtR\s+= InpPartialAtR;",
         '"after that, the stop can be moved to break-even"'),
        (r"if\(posSl <= 0\.0 \|\| posSl > posEntry\) return false;",
         'the add only fires once the live leg stop is at or beyond break-even'),
        (r"double banked = BankedOutProfit\(\(ulong\)PositionGetInteger\(POSITION_IDENTIFIER\)\);",
         'the banked partial is read from the position deal history to prove the cover'),
        (r"if\(banked <= 0\.0 \|\| banked < cover\) return false;",
         '"because the stop is already at break-even, the added position does not increase overall risk ... earlier profits cover the loss"'),
        (r"if\(expected <= 0\.0 \|\| usedFrac >= InpMaxUsedMoveFrac\) return false;",
         '"if a large part of the move has already happened, for example after a big gap down, the trade may no longer be worth taking"'),
        (r"double want = MathMin\(expected \* InpTargetFrac, InpMaxTargetR \* risk\);",
         '"before entering any trade, it is important to estimate how much the stock can realistically move"'),
        (r"input double\s+InpExpectedMovePct\s+= 20\.0;",
         '"10 to 20 percent" (stable) / "20 to 40 percent or more" (hype-driven)'),
        (r"cfg\.sessionEndFlat        = true;",
         '"the trade should be closed before the end of the day. Holding overnight increases risk and is not part of the strategy"'),
        (r"if\(m\[1\]\.close <= vwap \+ InpReclaimBufferAtr \* ctx\.atr\) return;",
         '"if price reclaims VWAP strongly and continues higher, the setup is no longer valid"'),
        (r"dt\.hour = InpSessionStartHour; dt\.min = InpSessionStartMin; dt\.sec = 0;",
         'the day-trading session anchors both the VWAP and the session high'),
    ],
    # -------------------------------------- price action (card #31)
    "EA_CF_PriceAction.mq5": [
        (r"if\(hi0 > hi1 && lo0 > lo1\) return \+1;",
         '"an uptrend has higher highs and higher lows ... This determines which direction (calls or puts) to trade"'),
        (r"if\(hi0 < hi1 && lo0 < lo1\) return -1;",
         '"a downtrend has lower highs and lower lows"'),
        (r"openP\[n\] = h\[i\]\.open;",
         '"focusing on candle open prices rather than wicks" - the level is the pivot candle OPEN'),
        (r"lv\[m\]\.conf     = 3\.0;",
         '"3/5 for opening prices"'),
        (r"if\(lv\[j\]\.touches >= InpStrongTouches\) lv\[j\]\.conf = 5\.0;",
         '"5/5 for strong pivots"'),
        (r"if\(through\) \{ lv\[j\]\.conf = 2\.5; break; \}",
         '"2.5/5 for invalidated levels"'),
        (r"if\(conf >= 5\.0\) return 1\.00;",
         '"high-confidence levels get full size"'),
        (r"return InpMidConfSize;",
         '"low-confidence or off-plan setups get 25-50% size"'),
        (r"if\(InpAlignM2 && !M2Aligned\(ctx, s\.dir\)\) return false;",
         '"Prefer 5-minute candles for conviction, but use 2-minute if both align"'),
        (r"if\(ctx\.clockMinutes < openMin \+ InpSkipOpenMinutes\) return false;",
         '"Skip the first 5 minutes of market open to avoid volatility and false breakouts"'),
        (r"if\(ctx\.clockMinutes > InpEntryEndHour \* 60 \+ InpEntryEndMin\) return false;",
         '"The trader executes for only 1 hour daily (typically market open)"'),
        (r"double probe = \(m\[1\]\.low < level\) \? \(level - m\[1\]\.low\) : 0\.0;",
         '"Ideal setup has a small wick below the level but body above it"'),
        (r"out\.level = level; out\.stopLevel = m\[1\]\.low;",
         '"Enter as close to the level as possible with a tight stop-loss just below the wick"'),
        (r"out\.level = level; out\.stopLevel = m\[1\]\.high;",
         'the downside break and retest - "Price breaks above (or below) a level ... then retests it"'),
        (r"if\(MathMin\(m\[i\]\.open, m\[i\]\.close\) > level && m\[i\]\.low < level\)",
         '"creates 2-3 candles with bodies above the level but wicks probing below it"'),
        (r"out\.level = level; out\.stopLevel = lowest;",
         '"Enter near the level with stop-loss at the lowest wick point"'),
        (r"if\(MathMax\(m\[i\]\.open, m\[i\]\.close\) < level && m\[i\]\.high > level\)",
         '"multiple candles with bodies below the level but wicks pushing up unsuccessfully"'),
        (r"out\.level = level; out\.stopLevel = highest;",
         'the resistance the puts setup risks - the highest wick'),
        (r"if\(next > 0\.0 && next >= need\) dist = MathMin\(dist, next\);",
         '"Enter near the level targeting the next lower level"'),
        (r"input int\s+InpMaxAttemptsPerSetup = 2;",
         '"take a maximum of two entries. If stopped out once, you may retry once more"'),
        (r"if\(SameSetupAttempts\(ctx, s\.level, tol\) >= InpMaxAttemptsPerSetup\) return false;",
         '"A third entry on the same setup is overtrading"'),
        (r"HistoryDealGetDouble\(t, DEAL_PRICE\)",
         'the attempts are counted from the day own deals at that level (restart-proof)'),
        (r"cfg\.partial1AtR\s+= InpPartialAtR;",
         '"Once price reaches 2R ... trim 50% of position"'),
        (r"cfg\.beOffsetR\s+= InpBeOffsetR;",
         '"Shift stop-loss above entry so remaining contracts are profitable even if stopped out"'),
        (r"cfg\.partial2AtR\s+= InpPartial2AtR;",
         '"Continue trimming at higher multiples"'),
        (r"if\(moveR / risk < InpPartialAtR\) return;",
         'the candle trail starts with the first trim'),
        (r"if\(!better\) return;\s+// a trail never loosens",
         '"shifting stop-loss with each green candle to reduce stress and lock in gains"'),
        (r"double dist = InpTargetR \* risk;",
         '"Aim for 2R or 1.5R per trade, not 5R or 10R home runs"'),
        (r"if\(ctx\.tradesToday >= InpMaxTradesPerDay\) return false;",
         '"Aim for 2-3 high-quality trades per day; 4+ is overtrading"'),
        (r"cfg\.dayLockFirstWin\s+= true;",
         '"After a winning trade, stop trading for the day" - the one-and-done rule'),
        (r"//--- R10/R17: this setup may be entered at most twice a day",
         '"Never re-enter the same setup on the same day" - a win locks the day, a stop-out earns one retry'),
        (r"input bool\s+InpUseVolumeConfirm\s+= false;",
         '"optional orderflow (bookmap) as confirmation on liquid instruments like SPY and QQQ" - off by default, as the document marks it optional'),
        (r"double lean = VolumeLean\(ctx\.symbol, InpVolumeBars\);",
         'bookmap has no MT5 signal: the confirmation is a labelled body-volume skew'),
        (r"input string\s+InpSymbolsToTrade",
         'the document trades options on TSLA/SPY/QQQ and futures ES/NQ; the universe is the user list'),
        (r"input int\s+InpLevelLookbackHours\s+= 120;",
         'the hourly level window is an input, not a hidden constant'),
        (r"cfg\.sessionEndFlat\s+= true;",
         'no overnight holds - "Day trading is about here-and-now execution"'),
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
                     "EA_CF_LiquidityInversion.mq5", "EA_CF_LiquidityStrategy.mq5",
                     "EA_CF_LowVolumeNode.mq5", "EA_CF_MarketAuctionTheory.mq5",
                     "EA_CF_MarketDna.mq5", "EA_CF_NasdaqIctAndOrderFlowScalpingStrategy.mq5",
                     "EA_CF_NqLiquiditySweepReversalScalpingStrategy.mq5",
                     "EA_CF_OptionsTradingMasterclass.mq5",
                     "EA_CF_OrderFlowStrategy.mq5",
                     "EA_CF_OrderflowTradingMasterclass.mq5",
                     "EA_CF_ParabolicShort.mq5",
                     "EA_CF_PriceAction.mq5"):
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
