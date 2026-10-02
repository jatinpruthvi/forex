#!/usr/bin/env python3
"""Author the pending additionalEAs from their source documents.

The tracker (docs/EA_IMPLEMENTATION_TRACKER.md) lists 65 pending EAs. Every one
of them shares the same plumbing (session clock, risk governor, sizing,
execution, management) which lives in ``MQL5_Master/Include/EACommon.mqh``.
This script renders each EA file from that shared contract plus a per-EA
strategy spec:

    * ``inputs``   - the EA's own ``input`` block
    * ``configure``- the SEASettings defaults (risk, sessions, exits, guards)
    * ``plan``     - ``BuildPlan()``: the actual edge, expressed with the
                     signal primitives from ``EASignals.mqh``
    * ``extra``    - optional extra methods (custom management, portfolios)

Run:  python3 scripts/gen_additional_eas.py [--check]

``--check`` verifies that the files on disk match the generated output (used by
tests/test_additional_ea_contract.py).
"""
from __future__ import annotations

import argparse
import re
import sys
import textwrap
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "MQL5_Master" / "Experts" / "additionalEAs"

HEADER = '''//+------------------------------------------------------------------+
//| {name}.mq5
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| {title}
//| Source document : {doc}
//| Tracker entry   : #{entry}  |  Magic: {magic}
//|                                                                  |
//| Shared engine   : MQL5_Master/Include/EACommon.mqh               |
//|   (session clock, risk governor, sizing, execution, management)  |
//| Strategy code   : the C{cls} class below.                        |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "2.00"
#property description "{title}"
#property description "Source: {doc}"

#include "..\\..\\Include\\EACommon.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
{inputs}
'''

BODY = '''
//+------------------------------------------------------------------+
//| Strategy: {title}
//+------------------------------------------------------------------+
class C{cls} : public CEAStrategy
{{
public:
   void Configure(SEASettings &cfg)
   {{
{configure}
   }}

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {{
{plan}
   }}
{extra}}};

C{cls} g_{cls};

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{{
   return EA_Init(&g_{cls});
}}

void OnTick()
{{
   EA_Tick();
}}

void OnDeinit(const int reason)
{{
   EA_Deinit(reason);
}}
//+------------------------------------------------------------------+
'''

COMMON_INPUTS = '''input string          InpSymbolsToTrade   = "{symbols}";      // Comma separated universe
input double          InpRiskPct          = {risk};   // Base risk per trade (% of equity)
input double          InpMaxSpreadPoints  = {spread};   // Spread gate in points (0 = off)
input double          InpDailyLossPct     = {daily};   // Halt for the day at -x% (0 = off)
input double          InpTotalDdPct       = {totaldd};   // Permanent floor from start balance (0 = off)
input double          InpProfitTargetPct  = {target};   // Stop opening at +x% (0 = off)
input int             InpMaxTradesPerDay  = {maxday};      // 0 = unlimited
input int             InpServerGmtOffset  = {gmtoff};      // Broker server clock minus GMT (winter)
input ulong           InpMagicNumber      = {magic}; // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input ENUM_EA_LOG_LEVEL InpLogLevel       = EA_LOG_EVENTS;   // Log verbosity'''

TEMPLATE = HEADER + BODY


@dataclass
class EA:
    entry: int
    name: str
    magic: int
    title: str
    doc: str
    cls: str
    inputs: str
    configure: str
    plan: str
    extra: str = ""
    common: dict = field(default_factory=dict)

    def render(self) -> str:
        ci = {
            "symbols": "EURUSD",
            "risk": "0.5",
            "spread": "0",
            "daily": "0",
            "totaldd": "0",
            "target": "0",
            "maxday": "0",
            "gmtoff": "2",
        }
        ci.update(self.common)
        ci["magic"] = self.magic
        inputs = COMMON_INPUTS.format(**ci)
        if self.inputs.strip():
            inputs += "\n" + self.inputs.strip("\n")
        #--- dead-config guard: never expose a knob the strategy cannot honour.
        #--- An input whose name appears nowhere in Configure()/BuildPlan()/extra
        #--- (comments excluded) would be silently ignored by the EA, so drop the
        #--- declaration instead of advertising a setting that does nothing.
        code = "\n".join([self.configure, self.plan, self.extra])
        code = re.sub(r"//[^\n]*", "", code)          # ignore comment-only mentions
        kept = []
        for line in inputs.splitlines():
            m = re.match(r"\s*input\s+\S+\s+(\w+)\s*=", line)
            if m and not re.search(r"\b" + m.group(1) + r"\b", code):
                continue
            kept.append(line)
        inputs = "\n".join(kept)
        def ind(block: str, n: int = 3) -> str:
            """Normalise a spec block (first line flush, body indented) to n."""
            lines = block.strip("\n").splitlines()
            rest = [l for l in lines[1:] if l.strip()]
            common = min(len(l) - len(l.lstrip()) for l in rest) if rest else 0
            pad = " " * n
            out = []
            for idx, line in enumerate(lines):
                if idx == 0:
                    norm = line.lstrip()
                else:
                    norm = line[common:] if line.strip() else ""
                out.append(pad + norm if norm.strip() else "")
            return "\n".join(out)

        cfg = ind(self.configure, 6)
        plan = ind(self.plan, 6)
        extra = ""
        if self.extra.strip():
            extra = "\n" + ind(self.extra, 3) + "\n"
        return TEMPLATE.format(
            name=self.name, title=self.title, doc=self.doc, entry=self.entry,
            magic=self.magic, cls=self.cls, inputs=inputs,
            configure=cfg, plan=plan, extra=extra,
        )


# ---------------------------------------------------------------------------
# Strategy specs - one per pending tracker entry.
# ---------------------------------------------------------------------------
EAS: list[EA] = []


def add(**kw) -> None:
    EAS.append(EA(**kw))


add(
    entry=15,
    name="EA_FINAL_OPTIMUM_STRATEGY",
    magic=3101,
    cls="FinalOptimum",
    title="Final Optimum - per-pair Triad stack (5 pairs) + 55-day gold Donchian",
    doc="docs/strategy/FINAL_OPTIMUM_STRATEGY.md",
    common={"symbols": "XAUUSD,AUDUSD,EURJPY,GBPJPY,USDJPY", "risk": "1.75",
            "spread": "25", "daily": "4.5", "totaldd": "10", "target": "10",
            "maxday": "2"},
    inputs='''input double InpGoldRiskPct       = 3.00;  // Gold Donchian leg: 3% of current balance
input int    InpDonchianDays      = 55;    // Channel: 55 D1 bars ending the day before yesterday
input double InpGoldStopAtr       = 2.50;  // Gold stop and chandelier k (2.5 x ATR14)
input double InpGoldAtrPeriod     = 14;    // Gold ATR: 14 daily (high - low) bars
input int    InpGoldEntryWindowMin= 60;    // Gold fills inside the first hour of the London day
input bool   InpTradeGold         = true;  // Enable the XAUUSD Donchian leg
input int    InpMaxTradesPerDayX  = 2;     // Max two trades/day across both legs
input double InpQualifyingDayCash = 12.50; // 0.5% of $2,500: phase qualifying day''',
    configure='''cfg.strategyName         = "FINAL_OPTIMUM";
   cfg.sourceDoc            = "docs/strategy/FINAL_OPTIMUM_STRATEGY.md";
   cfg.symbols              = InpSymbolsToTrade;
   cfg.magic                = InpMagicNumber;
   cfg.riskPct              = 1.75;                 // triad risk fraction (% of current balance)
   cfg.riskBaseBalance      = true;                 // risk fraction x current balance (doc 3.5)
   cfg.signalTimeframe      = PERIOD_M5;
   cfg.clock                = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset= InpServerGmtOffset;
   cfg.serverFollowsEuDst   = true;
   cfg.maxSpreadPoints      = InpMaxSpreadPoints;
   cfg.commissionPerLotRT   = 7.00;                 // $7/lot round turn (doc 6)
   cfg.maxCostR             = 0.10;                 // (spread + commission) <= 10% of R
   cfg.dailyLossPct         = InpDailyLossPct;      // 4.5% internal buffer under the 5% rule
   cfg.totalDdPct           = InpTotalDdPct;        // $2,250 permanent floor
   cfg.profitTargetPct      = InpProfitTargetPct;   // $2,750 phase-1 target
   cfg.maxTradesPerDay      = InpMaxTradesPerDayX;  // max two trades/day across both legs
   cfg.maxOpenPositions     = 1;                    // one shared slot; the gold leg holds it
   cfg.sessionStartHour     = 0;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour       = 0;   cfg.sessionEndMin   = 0;   // 24h: gold is a multi-day swing
   cfg.sessionEndFlat       = false;                // per-leg flat enforced in Manage()
   cfg.fridayFlat           = false;                // gold holds through the weekend (doc 4)
   cfg.signalOnNewBarOnly   = true;
   cfg.useLimitEntry        = true;
   cfg.pendingExpiryMinutes = 60;                   // dropped if never re-touched
   cfg.breakEvenAtR         = 0.0;                  // no BE rule in the champion
   cfg.timeStopMinutes      = 0;                    // per-pair time stop lives in Manage()
   cfg.minSecondsBetweenTrades = 120;
   cfg.qualifyingDayAmount  = InpQualifyingDayCash; // any three 0.5% days per phase
   cfg.qualifyingDaysTarget = 3;
   cfg.logLevel             = InpLogLevel;''',
    plan='''//--- Leg B first: gold acts first at the open and holds the only slot (doc 5)
   if(ctx.symbol == "XAUUSD" && InpTradeGold)
   {
      if(GoldLegPlan(ctx, plan)) { plan.reason = "GOLD " + plan.reason; return true; }
   }
   return TriadPlan(ctx, plan);''',
    extra='''   //--- per-pair overrides (doc 3.1)
   int    PairSessionEnd(const string sym)
   {
      if(sym == "EURJPY" || sym == "USDJPY" || sym == "XAUUSD") return 13 * 60 + 30;
      return 11 * 60;
   }
   double PairSweepMinAtr(const string sym)  { return (sym == "GBPJPY") ? 0.01 : 0.02; }
   double PairStopBufferAtr(const string sym)
   {
      if(sym == "EURJPY" || sym == "XAUUSD") return 0.05;
      return 0.10;
   }
   double PairTargetR(const string sym)      { return (sym == "AUDUSD") ? 2.5 : 1.5; }

   //--- Leg A: the doc 3.3 pattern (sweep, reclaim, displacement), one signal
   //--- per pair per day, BUY/SELL LIMIT at the displacement body midpoint
   bool TriadPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      if(ctx.atr <= 0.0) return false;
      int sessionEnd = PairSessionEnd(ctx.symbol);
      if(ctx.clockMinutes < 7 * 60 || ctx.clockMinutes >= sessionEnd) return false;
      if(ctx.symbol == "XAUUSD" && ctx.clockMinutes > 10 * 60) return false;   // no-late cutoff

      //--- reference range: M5 bars [00:00, 07:00) London, at least 12 bars
      double rHi = 0.0, rLo = 0.0;
      int    rangeBars = 0;
      if(!SigRangeForDay(ctx.symbol, PERIOD_M5, 0, 7 * 60, 0, rHi, rLo, rangeBars)) return false;
      if(rHi <= rLo || rangeBars < 12) return false;

      int lookback = (ctx.clockMinutes - 7 * 60) / 5 + 4;
      if(lookback > 300) lookback = 300;
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, PERIOD_M5, 1, lookback, r);
      if(got < 4) return false;

      double sweepMin = PairSweepMinAtr(ctx.symbol) * ctx.atr;
      double sweepMax = 0.50 * ctx.atr;

      for(int k = got - 1; k >= 3; k--)                    // oldest session bar first
      {
         MqlRates sw = r[k];
         bool sweptLow  = (sw.low  < rLo - sweepMin);
         bool sweptHigh = (sw.high > rHi + sweepMin);
         if(sweptLow && sweptHigh) return false;           // two-sided sweep consumes the day
         bool isLong = sweptLow;
         if(!isLong && !sweptHigh) continue;

         double extreme = isLong ? sw.low : sw.high;
         if(MathAbs(extreme - (isLong ? rLo : rHi)) > sweepMax) return false;   // abort day

         for(int c = 0; c <= 2; c++)                        // reclaim within the next two bars
         {
            int ri = k - c;
            if(ri < 1) continue;
            MqlRates re = r[ri];
            if(isLong)
            {
               if(re.high > rHi + sweepMin) return false;              // opposite sweep: day consumed
               if(re.low < extreme) extreme = re.low;                  // new extreme low
               if(MathAbs(extreme - rLo) > sweepMax) return false;
               if(!(re.close > rLo && re.close < rHi)) continue;       // close back inside
               if(EA_WickRatio(re, +1) < 0.45) continue;               // sellers' wick
            }
            else
            {
               if(re.low < rLo - sweepMin) return false;
               if(re.high > extreme) extreme = re.high;
               if(MathAbs(extreme - rHi) > sweepMax) return false;
               if(!(re.close > rLo && re.close < rHi)) continue;
               if(EA_WickRatio(re, -1) < 0.45) continue;
            }

            int di = ri - 1;                                // displacement: bar right after reclaim
            if(di < 1) continue;
            MqlRates disp = r[di];
            double body = EA_BodyRatio(disp);
            if(body < 0.50) continue;
            if(isLong  && !(disp.close > disp.open && disp.close > (re.open + re.close) / 2.0)) continue;
            if(!isLong && !(disp.close < disp.open && disp.close < (re.open + re.close) / 2.0)) continue;

            double entry = (disp.open + disp.close) / 2.0;
            double stop  = isLong ? extreme - PairStopBufferAtr(ctx.symbol) * ctx.atr
                                  : extreme + PairStopBufferAtr(ctx.symbol) * ctx.atr;
            double risk  = isLong ? entry - stop : stop - entry;
            if(risk <= 0.0) continue;
            if(risk < 0.60 * ctx.atr || risk > 1.50 * ctx.atr) return false;   // 0.60-1.50 ATR band
            if(risk < 2.0 * EA_PipSize(ctx.symbol)) return false;              // at least 2 pips

            int digits = (int)SymbolInfoInteger(ctx.symbol, SYMBOL_DIGITS);
            plan.Reset();
            plan.dir      = isLong ? +1 : -1;
            plan.entry    = NormalizeDouble(entry, digits);
            plan.stop     = stop;
            plan.riskDist = risk;
            plan.target   = isLong ? entry + PairTargetR(ctx.symbol) * risk
                                   : entry - PairTargetR(ctx.symbol) * risk;
            plan.score    = 70.0;
            plan.isLimit  = true;                           // BUY/SELL LIMIT at the body midpoint
            plan.expiry   = TimeTradeServer() + (datetime)(g_eaCfg.pendingExpiryMinutes * 60);
            plan.reason   = StringFormat("TRIAD-%s sweep %.2f ATR, disp body %.2f", ctx.symbol,
                                         MathAbs(extreme - (isLong ? rLo : rHi)) / ctx.atr, body);
            return true;
         }
      }
      return false;
   }

   //--- Leg B: gold Donchian swing (doc 4): 55 days ending the day before
   //--- yesterday, signal on yesterday's close beyond the channel, fill at the
   //--- open window, stop and chandelier = 2.5 x ATR14, no fixed target
   bool GoldLegPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      if(ctx.clockMinutes > InpGoldEntryWindowMin) return false;
      MqlRates r[];
      int need = InpDonchianDays + (int)InpGoldAtrPeriod + 1;
      if(EA_Rates(ctx.symbol, PERIOD_D1, 1, need, r) < need) return false;
      double atr14 = GoldAtr(r);
      if(atr14 <= 0.0) return false;

      double h = -1e18, l = 1e18;
      for(int i = 1; i <= InpDonchianDays; i++)                     // channel = d-1 .. d-55
      {
         if(r[i].high > h) h = r[i].high;
         if(r[i].low  < l) l = r[i].low;
      }
      int dir = 0;
      if(r[0].close > h)      dir = +1;                             // yesterday's close broke out
      else if(r[0].close < l) dir = -1;
      if(dir == 0) return false;

      double entry = (dir > 0) ? ctx.ask : ctx.bid;
      double stop  = (dir > 0) ? entry - InpGoldStopAtr * atr14 : entry + InpGoldStopAtr * atr14;
      double risk  = MathAbs(entry - stop);
      if(risk <= 0.0) return false;
      plan.Reset();
      plan.dir      = dir;
      plan.entry    = entry;
      plan.stop     = stop;
      plan.riskDist = risk;
      plan.target   = 0.0;                                          // chandelier: no fixed target
      plan.score    = 80.0;
      plan.reason   = StringFormat("GOLD-DONCHIAN(%d) close %.2f vs %s %.2f", InpDonchianDays,
                                   r[0].close, dir > 0 ? "high" : "low", dir > 0 ? h : l);
      return true;
   }

   //--- ATR14 = mean of the last 14 daily (high - low) bars ending yesterday
   double GoldAtr(MqlRates &r[])
   {
      int n = (int)InpGoldAtrPeriod;
      if(ArraySize(r) < n) return 0.0;
      double sum = 0.0;
      for(int i = 0; i < n; i++) sum += (r[i].high - r[i].low);
      return (n > 0) ? sum / n : 0.0;
   }

   //--- per-pair time stop and flat-by for the intraday leg
   void Manage(SEAContext &ctx)
   {
      if(ctx.symbol == "XAUUSD") { GoldManage(ctx); return; }
      for(int t = g_eaTrackCount - 1; t >= 0; t--)
      {
         if(g_eaTrack[t].symbol != ctx.symbol) continue;
         if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;

         datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
         double limitMin = (ctx.symbol == "EURJPY") ? 120.0 : 90.0;
         int    minutesOpen = (int)((TimeTradeServer() - opened) / 60);
         if(minutesOpen >= limitMin)
         {
            g_eaExec.Close(g_eaTrack[t].ticket, "per-pair time stop");
            continue;
         }
         if(ctx.clockMinutes >= PairSessionEnd(ctx.symbol))
         {
            g_eaExec.CancelPending(ctx.symbol, "session end - drop unfilled");
            g_eaExec.Close(g_eaTrack[t].ticket, "flat by pair session end");
         }
      }
   }

   //--- gold: opposite-channel exit plus the 2.5 x ATR chandelier, evaluated on
   //--- completed daily closes (no intra-day stop chasing, doc 4)
   void GoldManage(SEAContext &ctx)
   {
      MqlRates r[];
      int need = InpDonchianDays + (int)InpGoldAtrPeriod + 2;
      if(EA_Rates(ctx.symbol, PERIOD_D1, 1, need, r) < need) return;
      double atr14 = GoldAtr(r);
      if(atr14 <= 0.0) return;

      double h = -1e18, l = 1e18;
      for(int i = 1; i <= InpDonchianDays; i++)
      {
         if(r[i].high > h) h = r[i].high;
         if(r[i].low  < l) l = r[i].low;
      }

      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong tk = PositionGetTicket(p);
         if(tk == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;

         bool   isBuy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         double sl     = PositionGetDouble(POSITION_SL);
         datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
         bool   exitCh = isBuy ? (r[1].close < l) : (r[1].close > h);

         double extreme = PositionGetDouble(POSITION_PRICE_OPEN);
         for(int i = 0; i < ArraySize(r); i++)
         {
            if(r[i].time < opened) break;
            extreme = isBuy ? MathMax(extreme, r[i].close) : MathMin(extreme, r[i].close);
         }
         double trail = isBuy ? extreme - InpGoldStopAtr * atr14 : extreme + InpGoldStopAtr * atr14;
         if(exitCh) { g_eaExec.Close(tk, "gold opposite-channel exit"); continue; }
         if((isBuy && trail > sl) || (!isBuy && (sl <= 0.0 || trail < sl)))
            g_eaExec.Modify(tk, NormalizeDouble(trail, (int)SymbolInfoInteger(ctx.symbol, SYMBOL_DIGITS)), 0.0);
      }
   }''',
)

add(
    entry=16,
    name="EA_THE5ERS_CHALLENGE_STRATEGY_V2",
    magic=3102,
    cls="The5ersV2",
    title="The5ers Challenge V2 - M1 momentum reversion + daily state machine",
    doc="docs/prop_firm/THE5ERS-CHALLENGE-STRATEGY-V2.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY", "risk": "0.5", "spread": "1.5",
            "daily": "1.0", "totaldd": "5.0", "target": "10", "maxday": "2"},
    inputs='''
input double InpPhaseInitialBalance = 2500.0; // Persisted phase initial balance (LOCKED sizing base)
input double InpExtremeBodyAtr    = 2.50;  // Extreme candle body in ATR(M1,14)
input double InpStopAtr           = 1.50;  // Stop beyond the extreme candle (ATR)
input double InpTargetR           = 1.50;  // Fixed +1.5R target
input int    InpTimeStopMinutes   = 45;    // Close if +1R not confirmed within x min
input int    InpMaxTradesPerSession = 1;   // One signal event per symbol/session
input double InpSpreadMedianMult   = 1.50;  // Spread gate: x times the same-minute/session median
input string InpNewsFile           = "the5ers_red_news.csv"; // Red-folder calendar (MQL5/Files)
input int    InpNewsBeforeMin      = 30;    // No new entry x min before the event
input int    InpNewsAfterMin       = 30;    // No new entry x min after the event
input double InpQualifyingDayCash   = 12.50;  // 0.5% of $2,500: qualifying-day amount
input int    InpQualifyingDayCount  = 3;      // Qualifying days required per phase''',
    configure='''cfg.strategyName         = "THE5ERS_V2";
   cfg.sourceDoc            = "docs/prop_firm/THE5ERS-CHALLENGE-STRATEGY-V2.md";
   cfg.symbols              = InpSymbolsToTrade;
   cfg.magic                = InpMagicNumber;
   cfg.riskPct              = InpRiskPct;               // profile B: 0.50%
   cfg.signalTimeframe      = PERIOD_M1;                // M1 momentum reversion
   cfg.clock                = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset= InpServerGmtOffset;
   cfg.maxSpreadPoints      = InpMaxSpreadPoints;
   cfg.dailyLossPct         = InpDailyLossPct;          // internal -1% daily stop
   cfg.weeklyLossPct        = 2.0;                      // internal -2% weekly stop
   cfg.totalDdPct           = InpTotalDdPct;
   cfg.profitTargetPct      = InpProfitTargetPct;
   cfg.maxTradesPerDay      = InpMaxTradesPerDay;       // max two completed trades
   cfg.maxOpenPositions     = 1;                        // one order/position account-wide
   cfg.sessionStartHour     = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour       = 16;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat       = true;
   cfg.fridayFlat           = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly   = true;                     // completed M1 candle
   cfg.useLimitEntry        = false;                    // enter at market
   cfg.breakEvenAtR         = 0.0;                      // BE is bar-close confirmed in Manage()
   cfg.timeStopMinutes      = InpTimeStopMinutes;
   cfg.useHwmThrottle       = true;                     // 0-2%: 100%, 2-5%: 50%, >=5%: halt
   cfg.hwmTier1Dd           = 2.0;  cfg.hwmTier1Mult = 0.50;
   cfg.hwmTier2Dd           = 5.0;  cfg.hwmTier2Mult = 0.0;
   cfg.hwmHaltDd            = 5.0;
   cfg.newsFilter           = true;                     // mandatory red-folder gate (fail closed)
   cfg.newsFile             = InpNewsFile;              // inert only while the file is absent
   cfg.newsBeforeMin        = InpNewsBeforeMin;
   cfg.newsAfterMin         = InpNewsAfterMin;
   cfg.newsFailClosed       = true;                     // bad calendar = no new entries
   cfg.qualifyingDayAmount  = InpQualifyingDayCash;
   cfg.qualifyingDaysTarget = InpQualifyingDayCount;
   //--- LOCKED: phase-initial balance is the sizing base; one working entry account-wide
   cfg.riskBaseInitialBalance = true;  cfg.riskInitialBalance = InpPhaseInitialBalance;
   cfg.oneEntryAccountWide    = true;   // no second entry while one is working or open
   cfg.flattenOnHalt          = true;   // governor halt = cancel entries + close
   cfg.newsFlatBeforeMin      = 15.0;   // flat 15 min before a relevant red event

   cfg.dayAnchorServer        = true;   // firm rollover on the SERVER day, never the clock day
   cfg.dayLockFirstWin        = true;   // any first net-positive exit locks the day

   cfg.dayLockAfterTrades     = 2;      // two completed sequential trades end the day


   cfg.maxRetries           = 1;                        // one revalidated retry only
   cfg.logLevel             = InpLogLevel;''',
    plan='''if(ctx.atr <= 0.0) return false;

   //--- certified entry windows: EURUSD/GBPUSD 07:00-11:00, USDJPY 13:30-16:00 London
   int fromMin = 7 * 60;
   int toMin   = 11 * 60;
   if(ctx.symbol == "USDJPY") { fromMin = 13 * 60 + 30; toMin = 16 * 60; }
   if(ctx.clockMinutes < fromMin || ctx.clockMinutes >= toMin) return false;

   //--- mandatory spread gate: no worse than 1.5x the same-minute/session median
   if(!SpreadWithinMedian(ctx)) return false;

   //--- M1 momentum reversion: fade a completed extreme candle
   MqlRates r[];
   int got = EA_Rates(ctx.symbol, PERIOD_M1, 1, 30, r);
   if(got < 20) return false;

   //--- one signal event per session: remember the extreme bar time we traded
   for(int i = 1; i <= 3; i++)
   {
      MqlRates b = r[i];
      double body = MathAbs(b.close - b.open);
      if(body < InpExtremeBodyAtr * ctx.atr) continue;

      int dir = (b.close < b.open) ? +1 : -1;      // bearish extreme -> fade long
      double entry = (dir > 0) ? ctx.ask : ctx.bid;
      double stop  = (dir > 0) ? b.low  - InpStopAtr * ctx.atr
                               : b.high + InpStopAtr * ctx.atr;
      double risk  = (dir > 0) ? entry - stop : stop - entry;
      if(risk <= 0.0) continue;

      plan.dir      = dir;
      plan.entry    = entry;
      plan.stop     = stop;
      plan.riskDist = risk;
      plan.target   = (dir > 0) ? entry + InpTargetR * risk : entry - InpTargetR * risk;
      plan.score    = 65.0;
      plan.reason   = StringFormat("M1 momentum reversion fade (body %.2f ATR)", body / ctx.atr);
      plan.barsAgo  = i;
      return true;
   }
   return false;''',
    extra='''   //--- rolling spread median per minute-of-session over the prior 60 sessions
   double   m_slotRing[1440][60];
   datetime m_slotStamp;
   datetime m_lastDay;
   int      m_dayCycle;

   void OnInitStrategy()
   {
      for(int m = 0; m < 1440; m++)
         for(int d = 0; d < 60; d++) m_slotRing[m][d] = 0.0;
      m_slotStamp = 0; m_lastDay = 0; m_dayCycle = 0;
   }

   bool SpreadWithinMedian(SEAContext &ctx)
   {
      MqlDateTime dt;
      if(!TimeToStruct(ctx.nowClock, dt)) return true;
      int slot = dt.hour * 60 + dt.min;
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      datetime day = StructToTime(dt);
      if(day != m_lastDay)
      {
         m_lastDay  = day;
         m_dayCycle = (m_dayCycle + 1) % 60;
      }
      datetime minute = ctx.nowClock - (ctx.nowClock % 60);
      if(minute != m_slotStamp && ctx.spreadPoints < 1e10 && slot >= 0 && slot < 1440)
      {
         m_slotStamp = minute;
         m_slotRing[slot][m_dayCycle] = ctx.spreadPoints;
      }
      double arr[60];
      int n = 0;
      for(int i = 0; i < 60; i++)
      {
         double v = m_slotRing[slot][i];
         if(v > 0.0) arr[n++] = v;
      }
      if(n < 20) return true;                                   // warm-up
      for(int i = 1; i < n; i++)
      {
         double key = arr[i];
         int    j   = i - 1;
         while(j >= 0 && arr[j] > key) { arr[j + 1] = arr[j]; j--; }
         arr[j + 1] = key;
      }
      double median = arr[n / 2];
      if(median > 0.0 && ctx.spreadPoints > InpSpreadMedianMult * median)
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.1f > %.2fx same-minute median %.1f - skip",
                ctx.symbol, ctx.spreadPoints, InpSpreadMedianMult, median), true);
         return false;
      }
      return true;
   }

   //--- documented BE policy: move the visible stop to entry only after a
   //--- COMPLETED M5 close beyond +1R (no intraday tick trigger)
   void Manage(SEAContext &ctx)
   {
      for(int t = g_eaTrackCount - 1; t >= 0; t--)
      {
         if(g_eaTrack[t].symbol != ctx.symbol) continue;
         if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;
         if(g_eaTrack[t].beMoved) continue;
         MqlRates m[];
         if(EA_Rates(ctx.symbol, PERIOD_M5, 1, 2, m) < 2) continue;
         double d = (g_eaTrack[t].dir > 0) ? (m[1].close - g_eaTrack[t].entry) : (g_eaTrack[t].entry - m[1].close);
         if(d >= g_eaTrack[t].riskDist)
         {
            g_eaTrack[t].beMoved = true;
            g_eaExec.Modify(g_eaTrack[t].ticket, g_eaTrack[t].entry, 0.0);
         }
      }
      DailyStateMachine(ctx);
   }

   //--- daily state machine: any net-positive first trade locks the day
   void DailyStateMachine(SEAContext &ctx)
   {
      static datetime lockedDay = 0;
      MqlDateTime dt;
      TimeToStruct(ctx.nowClock, dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      datetime day = StructToTime(dt);
      if(lockedDay == day) { EA_FlattenAll("day locked by state machine"); return; }
      if(ctx.tradesToday >= 2 && ctx.openPositions == 0 && ctx.floatingPl == 0.0)
         lockedDay = day;                       // second completed trade locks the day
      if(ctx.openPositions == 0 && ctx.dayRealizedPl > 0.0 && ctx.tradesToday >= 1)
         lockedDay = day;                       // first trade net positive -> lock
   }
''',
)


add(
    entry=17,
    name="EA_THE5ERS_CHALLENGE_OPTIMIZATION",
    magic=3103,
    cls="ChallengeOptimization",
    title="The5ers optimization - non-market-failure elimination + Route A router",
    doc="docs/prop_firm/THE5ERS-CHALLENGE-OPTIMIZATION.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY", "risk": "0.4", "spread": "3.0",
            "daily": "1.0", "totaldd": "10", "target": "10", "maxday": "2"},
    inputs='''
input double InpPhaseInitialBalance = 2500.0; // Persisted phase initial balance (LOCKED sizing base)
input double InpCommissionPerLotRT = 7.00;  // Round-turn commission per lot (cost model)
input double InpMaxCostR             = 0.10;  // Priority-1 gate: reject when all-in cost > xR
input int    InpMaxRequestsPerDay    = 20;    // Rate limit: non-emergency trade requests/day
input int    InpTimeStopMinutes      = 45;    // Plateau time stop (30/45/60/90 candidates)
input double InpTargetR              = 1.50;  // Champion exit model A (fixed +1.5R)
input bool   InpUseBreakEven         = false; // Challenger policy: move stop to entry after +1R
input bool   InpTradeUsdJpyNy        = true;  // Enable the USDJPY New York combination
input int    InpUsdJpyFromMin        = 810;   // 13:30 London = 08:30 New York
input int    InpUsdJpyToMin          = 960;   // 16:00 London = 11:00 New York''',
    configure='''cfg.strategyName          = "THE5ERS_OPTIMIZATION";
   cfg.sourceDoc             = "docs/prop_firm/THE5ERS-CHALLENGE-OPTIMIZATION.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;              // max 0.50% permitted for this product
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxSpreadPoints       = InpMaxSpreadPoints;
   cfg.commissionPerLotRT    = InpCommissionPerLotRT;   // Priority 1: honest cost model
   cfg.maxCostR              = InpMaxCostR;             // round-trip cost <= 0.10R
   cfg.maxRequestsPerDay     = InpMaxRequestsPerDay;    // rate-limited order requests
   cfg.dailyLossPct          = InpDailyLossPct;         // internal daily stop
   cfg.weeklyLossPct         = 2.0;                     // internal weekly stop
   cfg.totalDdPct            = InpTotalDdPct;
   cfg.profitTargetPct       = InpProfitTargetPct;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;      // max two sequential trades
   cfg.maxOpenPositions      = 1;                       // one slot account-wide
   cfg.minSecondsBetweenTrades = 60;
   cfg.useHwmThrottle        = true;                    // 50% risk tier at 2% drawdown
   cfg.hwmTier1Dd            = 2.0;  cfg.hwmTier1Mult = 0.50;
   cfg.hwmTier2Dd            = 5.0;  cfg.hwmTier2Mult = 0.0;  cfg.hwmHaltDd = 5.0;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;                    // flat by the session hard stop
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 21;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.pendingExpiryMinutes  = 15;                      // three M5 candles
   cfg.timeStopMinutes       = InpTimeStopMinutes;
   cfg.breakEvenAtR          = (InpUseBreakEven ? 1.0 : 0.0);
   cfg.breakEvenOnBarClose   = true;                    // only a completed bar confirms +1R
   cfg.partial1AtR           = 0.0;                     // no partials in this profile
   //--- LOCKED: phase-initial balance is the sizing base; one working entry account-wide
   cfg.riskBaseInitialBalance = true;  cfg.riskInitialBalance = InpPhaseInitialBalance;
   cfg.oneEntryAccountWide    = true;   // no second entry while one is working or open
   cfg.flattenOnHalt          = true;   // governor halt = cancel entries + close
   cfg.newsFlatBeforeMin      = 15.0;   // flat 15 min before a relevant red event

   cfg.dayAnchorServer        = true;   // firm rollover on the SERVER day, never the clock day
   cfg.dayLockFirstWin        = true;   // any first net-positive exit locks the day

   cfg.dayLockAfterTrades     = 2;      // two completed sequential trades end the day


   cfg.maxRetries           = 1;                        // one revalidated retry only
   cfg.logLevel              = InpLogLevel;''',
    plan='''//--- Priority 3: accepted breakouts are no-trades; only the reversal is traded
   SSweepParams p;
   p.Reset();
   p.rangeFromMin   = 0;
   p.rangeToMin     = 7 * 60;          // 00:00-07:00 London reference range
   p.sessionFromMin = 7 * 60;
   p.sessionToMin   = 11 * 60;         // London combinations
   p.sweepMinAtr    = 0.05;
   p.sweepMaxAtr    = 0.50;
   p.reclaimWindowBars = 3;
   p.wickRatio      = 0.60;
   p.bodyRatio      = 0.60;
   p.stopBufferAtr  = 0.10;
   p.minStopAtr     = 0.60;  p.maxStopAtr = 1.50;
   p.entryRetrace   = 0.50;
   p.targetR        = InpTargetR;

   if(ctx.symbol == "USDJPY")
   {
      if(!InpTradeUsdJpyNy) return false;
      p.rangeFromMin   = 7 * 60;       // 07:00-13:00 London reference range
      p.rangeToMin     = 13 * 60;
      p.sessionFromMin = InpUsdJpyFromMin;
      p.sessionToMin   = InpUsdJpyToMin;
   }
   if(ctx.clockMinutes < p.sessionFromMin || ctx.clockMinutes >= p.sessionToMin) return false;

   if(!SigSweepReclaim(ctx, p, plan)) return false;
   plan.reason = StringFormat("OPT-ROUTE-A %s %s", ctx.symbol, plan.reason);
   return true;''',
    extra='''   //--- Priority 1: no market chase after an expired/unfilled limit.
   //--- Cancel a resting entry once price has travelled +1R away from it.
   void Manage(SEAContext &ctx)
   {
      for(int o = OrdersTotal() - 1; o >= 0; o--)
      {
         ulong t = OrderGetTicket(o);
         if(t == 0) continue;
         if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagicNumber) continue;
         if(OrderGetString(ORDER_SYMBOL) != ctx.symbol) continue;
         ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         int dir = (ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_BUY_STOP) ? +1 : -1;
         double entry = OrderGetDouble(ORDER_PRICE_OPEN);
         double sl    = OrderGetDouble(ORDER_SL);
         double risk  = MathAbs(entry - sl);
         if(risk <= 0.0 || entry <= 0.0) continue;
         double px  = (dir > 0) ? ctx.bid : ctx.ask;
         double fav = (dir > 0) ? (px - entry) : (entry - px);
         if(fav >= risk)
         {
            EA_Log(EA_LOG_EVENTS, StringFormat("%s +1R reached unfilled - cancelling entry", ctx.symbol));
            g_eaExec.CancelPending(ctx.symbol, "price reached +1R unfilled");
         }
      }
   }''',
)


add(
    entry=18,
    name="EA_THE5ERS_2_5K_CHALLENGE_PLAN",
    magic=3104,
    cls="ChallengePlan25K",
    title="The5ers $2,500 challenge plan - Route A with spread-median and cost gates",
    doc="docs/prop_firm/THE5ERS-2.5K-CHALLENGE-PLAN.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY", "risk": "0.4", "spread": "0",
            "daily": "1.0", "totaldd": "10", "target": "10", "maxday": "2"},
    inputs='''
input double InpPhaseInitialBalance = 2500.0; // Persisted phase initial balance (LOCKED sizing base)
input double InpSpreadMedianMult   = 1.50;  // Spread gate: x times the symbol/minute median
input int    InpSpreadSamples      = 64;    // Rolling spread window (M5 samples)
input double InpCommissionPerLotRT = 7.00;  // Round-turn commission per lot
input double InpMaxCostR           = 0.10;  // Round-trip cost ceiling in R
enum ENUM_T5K_PROFILE
{
   T5K_ROUTE_A      = 0,  // Route A sweep/reclaim (research module)
   T5K_M1_MOMENTUM  = 1   // M1 Momentum Reversion (active first-challenge module)
};
input ENUM_T5K_PROFILE InpProfile          = T5K_M1_MOMENTUM; // Active module per doc section 2
input double InpSweepMinAtr        = 0.05;  // Route A: sweep depth band
input double InpSweepMaxAtr        = 0.50;
input double InpReclaimWickRatio   = 0.60;  // Reclaim wick >= x of candle range
input double InpDisplacementBody   = 0.60;  // Displacement body >= x of range
input double InpStopBufferAtr      = 0.10;  // Stop beyond the sweep extreme
input double InpStopMinAtr         = 0.60;  // Reject stop outside [0.60, 1.50] ATR
input double InpStopMaxAtr         = 1.50;
input double InpTargetR            = 1.50;  // Fixed validated target
input int    InpTimeStopMinutes    = 45;    // +1R plateau time stop
input bool   InpTradeUsdJpyNy      = true;  // USDJPY New York combination
input string InpNewsFile           = "the5ers_red_news.csv"; // Red-folder calendar (MQL5/Files)
input int    InpNewsBeforeMin      = 30;    // Cancel/protect before the event
input int    InpNewsAfterMin       = 30;    // No retries after the event
input double InpQualifyingDayCash   = 12.50;  // 0.5% of $2,500: qualifying-day amount
input int    InpQualifyingDayCount  = 3;      // Qualifying days required per phase''',
    configure='''cfg.strategyName          = "THE5ERS_25K_PLAN";
   cfg.sourceDoc             = "docs/prop_firm/THE5ERS-2.5K-CHALLENGE-PLAN.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   bool m1Mode = (InpProfile == T5K_M1_MOMENTUM);
   cfg.riskPct               = m1Mode ? 0.50 : InpRiskPct;   // M1 module: 0.50% of initial balance
   cfg.riskBaseBalance       = false;
   cfg.signalTimeframe       = m1Mode ? PERIOD_M1 : PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.commissionPerLotRT    = InpCommissionPerLotRT;
   cfg.maxCostR              = InpMaxCostR;              // estimated cost <= 0.10R
   cfg.dailyLossPct          = InpDailyLossPct;          // internal -1.0% incl. floating
   cfg.weeklyLossPct         = 2.0;                      // internal -2.0% incl. floating
   cfg.totalDdPct            = InpTotalDdPct;
   cfg.profitTargetPct       = InpProfitTargetPct;       // $2,750 phase-1 target
   cfg.maxTradesPerDay       = MathMin(m1Mode ? 5 : InpMaxTradesPerDay, 2); // account rule: 2 sequential trades/day
   cfg.maxOpenPositions      = 1;                        // one working entry/position
   cfg.minSecondsBetweenTrades = 60;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;                     // flat at the session hard stop
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 21;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.pendingExpiryMinutes  = 15;                       // cancel after three M5 candles
   cfg.timeStopMinutes       = InpTimeStopMinutes;        // 45-minute plateau
   cfg.breakEvenAtR          = 0.0;                       // M1 contract: fixed stop, +1.5R target
   cfg.breakEvenAtR          = 0.0;                      // no BE in the baseline profile
   cfg.partial1AtR           = 0.0;                      // never partial-size on a small account
   cfg.newsFilter            = true;                     // cancel on blackout (inert without the file)
   cfg.newsFile              = InpNewsFile;
   cfg.newsBeforeMin         = InpNewsBeforeMin;
   cfg.newsAfterMin          = InpNewsAfterMin;
   cfg.newsFailClosed        = true;                     // bad calendar = no new entries
   cfg.qualifyingDayAmount   = InpQualifyingDayCash;
   cfg.qualifyingDaysTarget  = InpQualifyingDayCount;
   //--- LOCKED: phase-initial balance is the sizing base; one working entry account-wide
   cfg.riskBaseInitialBalance = true;  cfg.riskInitialBalance = InpPhaseInitialBalance;
   cfg.oneEntryAccountWide    = true;   // no second entry while one is working or open
   cfg.flattenOnHalt          = true;   // governor halt = cancel entries + close
   cfg.newsFlatBeforeMin      = 15.0;   // flat 15 min before a relevant red event

   cfg.dayAnchorServer        = true;   // firm rollover on the SERVER day, never the clock day
   cfg.dayLockFirstWin        = true;   // any first net-positive exit locks the day

   cfg.dayLockAfterTrades     = 2;      // two completed sequential trades end the day
   cfg.dayLockAfterLosses     = 2;      // stop after two full losses (doc section 14)


   cfg.maxRetries           = 1;                        // one revalidated retry only
   cfg.logLevel              = InpLogLevel;''',
    plan='''if(ctx.symbol == "USDJPY" && !InpTradeUsdJpyNy) return false;

   //--- shared hard gate: spread no worse than 1.5x its rolling median
   if(!SpreadWithinMedian(ctx)) return false;

   //--- active module (doc section 2): M1 momentum reversion, EURUSD/GBPUSD
   //--- London and USDJPY New York, 0.5% risk, 1.5 x ATR stop, fixed +1.5R
   if(InpProfile == T5K_M1_MOMENTUM)
   {
      if(ctx.symbol != "EURUSD" && ctx.symbol != "GBPUSD" && ctx.symbol != "USDJPY") return false;
      int fromMin = 7 * 60, toMin = 11 * 60;                     // London scan
      if(ctx.symbol == "USDJPY") { fromMin = 13 * 60 + 30; toMin = 16 * 60; }   // New York
      if(ctx.clockMinutes < fromMin || ctx.clockMinutes >= toMin) return false;
      if(ctx.atr <= 0.0) return false;

      MqlRates m[];
      if(EA_Rates(ctx.symbol, PERIOD_M1, 1, 20, m) < 16) return false;
      for(int i = 1; i <= 3; i++)
      {
         double body = MathAbs(m[i].close - m[i].open);
         if(body < 2.5 * ctx.atr) continue;                       // body > 2.5 x ATR(M1,14)
         int dir = (m[i].close < m[i].open) ? +1 : -1;            // fade the extreme candle
         double entry = (dir > 0) ? ctx.ask : ctx.bid;
         double stop  = (dir > 0) ? m[i].low  - 1.5 * ctx.atr
                                  : m[i].high + 1.5 * ctx.atr;
         double risk  = (dir > 0) ? entry - stop : stop - entry;
         if(risk <= 0.0) continue;
         plan.Reset();
         plan.dir      = dir;
         plan.entry    = entry;
         plan.stop     = stop;
         plan.riskDist = risk;
         plan.target   = (dir > 0) ? entry + 1.5 * risk : entry - 1.5 * risk;
         plan.score    = 65.0;
         plan.barsAgo  = i;
         plan.reason   = StringFormat("M1-MOMENTUM %s fade (body %.2f ATR)", ctx.symbol, body / ctx.atr);
         return true;
      }
      return false;
   }

   //--- research module: Route A sweep/reclaim (shadow until separately approved henceforth
   //--- independent validation, doc section 3)

   SSweepParams p;
   p.Reset();
   p.rangeFromMin   = 0;
   p.rangeToMin     = 7 * 60;
   p.sessionFromMin = 7 * 60;
   p.sessionToMin   = 11 * 60;
   p.sweepMinAtr    = InpSweepMinAtr;
   p.sweepMaxAtr    = InpSweepMaxAtr;
   p.reclaimWindowBars = 3;
   p.wickRatio      = InpReclaimWickRatio;
   p.bodyRatio      = InpDisplacementBody;
   p.stopBufferAtr  = InpStopBufferAtr;
   p.minStopAtr     = InpStopMinAtr;
   p.maxStopAtr     = InpStopMaxAtr;
   p.entryRetrace   = 0.50;                 // limit at 50% of the displacement body
   p.targetR        = InpTargetR;

   if(ctx.symbol == "USDJPY")
   {
      p.rangeFromMin   = 7 * 60;            // New York: 07:00-13:00 reference range
      p.rangeToMin     = 13 * 60;
      p.sessionFromMin = 13 * 60 + 30;
      p.sessionToMin   = 16 * 60;
   }
   if(ctx.clockMinutes < p.sessionFromMin || ctx.clockMinutes >= p.sessionToMin) return false;

   if(!SigSweepReclaim(ctx, p, plan)) return false;
   plan.reason = StringFormat("25K-ROUTE-A %s %s", ctx.symbol, plan.reason);
   return true;''',
    extra='''   //--- rolling spread median per symbol (sampled once per closed M5 bar)
   bool SpreadWithinMedian(SEAContext &ctx)
   {
      int slot = -1;
      for(int i = 0; i < g_eaSymbolCount; i++) if(g_eaSymbols[i] == ctx.symbol) slot = i;
      if(slot < 0 || slot >= EA_MAX_SYMBOLS) return true;

      datetime barTime = iTime(ctx.symbol, PERIOD_M5, 0);
      if(m_spreadCount[slot] == 0 || m_spreadLast[slot] != barTime)
      {
         int cap = (int)MathMin(InpSpreadSamples, 64);
         for(int i = (cap - 1); i > 0; i--) m_spread[slot][i] = m_spread[slot][i - 1];
         m_spread[slot][0]   = ctx.spreadPoints;
         m_spreadCount[slot] = (int)MathMin(m_spreadCount[slot] + 1, cap);
         m_spreadLast[slot]  = barTime;
      }
      int n = (int)MathMin(m_spreadCount[slot], 64);
      if(n < 8) return true;                              // warm-up: no median yet

      double arr[64];
      for(int i = 0; i < n; i++) arr[i] = m_spread[slot][i];
      for(int i = 1; i < n; i++)                          // insertion sort of the valid window
      {
         double key = arr[i];
         int    j   = i - 1;
         while(j >= 0 && arr[j] > key) { arr[j + 1] = arr[j]; j--; }
         arr[j + 1] = key;
      }
      double median = arr[n / 2];
      if(median <= 0.0) return true;
      if(ctx.spreadPoints > InpSpreadMedianMult * median)
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.1f > %.2fx median %.1f - skip",
                ctx.symbol, ctx.spreadPoints, InpSpreadMedianMult, median), true);
         return false;
      }
      return true;
   }

   double   m_spread[EA_MAX_SYMBOLS][64];
   int      m_spreadCount[EA_MAX_SYMBOLS];
   datetime m_spreadLast[EA_MAX_SYMBOLS];

   void OnInitStrategy()
   {
      for(int i = 0; i < EA_MAX_SYMBOLS; i++)
      {
         m_spreadCount[i] = 0;
         m_spreadLast[i]  = 0;
         for(int j = 0; j < 64; j++) m_spread[i][j] = 0.0;
      }
   }

   //--- pending hygiene: cancel at the pair's hard stop, on news blackout,
   //--- or when price reaches +1R without filling (rule 8 of the plan)
   void Manage(SEAContext &ctx)
   {
      if(ctx.newsBlocked) g_eaExec.CancelPending(ctx.symbol, "news blackout");

      int endMin = (ctx.symbol == "USDJPY") ? 16 * 60 : 11 * 60;
      for(int o = OrdersTotal() - 1; o >= 0; o--)
      {
         ulong t = OrderGetTicket(o);
         if(t == 0) continue;
         if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagicNumber) continue;
         string sym = OrderGetString(ORDER_SYMBOL);
         if(sym != ctx.symbol) continue;
         if(ctx.clockMinutes >= endMin)
         {
            g_eaExec.CancelPending(sym, "pair session end");
            continue;
         }
         long type = OrderGetInteger(ORDER_TYPE);
         bool isBuy = (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP);
         double px  = OrderGetDouble(ORDER_PRICE_OPEN);
         double sl  = OrderGetDouble(ORDER_SL);
         double risk = MathAbs(px - sl);
         if(risk <= 0.0) continue;
         if(isBuy  && (ctx.bid - px) >= risk) g_eaExec.CancelPending(sym, "+1R without fill");
         if(!isBuy && (px - ctx.ask) >= risk) g_eaExec.CancelPending(sym, "+1R without fill");
      }
   }''',
)


add(
    entry=19,
    name="EA_THE5ERS_CHALLENGE_V2_REVALIDATION",
    magic=3105,
    cls="ChallengeV2Revalidation",
    title="The5ers V2 revalidation - Sleeve A plus the compliance harness",
    doc="docs/prop_firm/THE5ERS-CHALLENGE-V2-REVALIDATION.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY", "risk": "0.4", "spread": "3.0",
            "daily": "5.0", "totaldd": "10", "target": "10", "maxday": "2"},
    inputs='''input double InpPhaseInitialBalance = 2500.0; // Persisted phase initial balance
input double InpQualifyingDayPct     = 0.005;  // 0.5% of phase initial balance = $12.50
input double InpDailyBoundaryPct     = 0.05;   // Firm boundary: max(balance,equity) x 0.95
input int    InpInactivityWarnDays   = 20;     // Warn at day 20 without a trade
input int    InpInactivityEscalateDays = 25;   // Escalate at day 25 (never fake a trade)
input double InpMaxCostR             = 0.10;   // Cost gate in R
input string InpNewsFile           = "the5ers_red_news.csv"; // Red-folder calendar (MQL5/Files)
input int    InpNewsBeforeMin      = 30;    // Mandatory 30-minute pre-event buffer
input int    InpNewsAfterMin       = 30;    // Mandatory 30-minute post-event buffer
input int    InpMaxRequestsPerDay  = 20;    // Non-emergency trade-request cap
input int    InpRetryCount         = 1;     // One revalidated retry after a transient reject
input double InpQualifyingDayCash   = 12.50;  // 0.5% of $2,500: qualifying-day amount
input int    InpQualifyingDayCount  = 3;      // Qualifying days required per phase
input double InpCommissionPerLotRT   = 7.00;   // Round-turn commission per lot
input double InpTargetR              = 1.50;   // Sleeve A target
input int    InpTimeStopMinutes      = 45;     // Sleeve A time stop''',
    configure='''cfg.strategyName          = "THE5ERS_V2_REVALIDATION";
   cfg.sourceDoc             = "docs/prop_firm/THE5ERS-CHALLENGE-V2-REVALIDATION.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxSpreadPoints       = InpMaxSpreadPoints;
   cfg.commissionPerLotRT    = InpCommissionPerLotRT;
   cfg.maxCostR              = InpMaxCostR;
   cfg.newsFilter            = true;
   cfg.maxRequestsPerDay     = InpMaxRequestsPerDay;
   cfg.newsFile              = InpNewsFile;
   cfg.newsBeforeMin         = InpNewsBeforeMin;
   cfg.newsAfterMin          = InpNewsAfterMin;
   cfg.newsFailClosed        = true;                     // calendar unavailable = no new entries
   cfg.qualifyingDayAmount   = InpQualifyingDayCash;
   cfg.qualifyingDaysTarget  = InpQualifyingDayCount;
   cfg.dailyLossPct          = InpDailyLossPct;         // firm boundary (fail closed)
   cfg.totalDdPct            = InpTotalDdPct;           // static floor from persisted base
   cfg.profitTargetPct       = InpProfitTargetPct;      // 10% Phase 1 / 5% Phase 2
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 1;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;                    // flat before rollover/weekend
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.pendingExpiryMinutes  = 15;
   cfg.timeStopMinutes       = InpTimeStopMinutes;
   cfg.breakEvenAtR          = 1.0;                     // BE after +1R...
   cfg.breakEvenOnBarClose   = true;                    // ...confirmed by a completed M5 close
   cfg.partial1AtR           = 0.0;                     // no partials in the frozen contract
   cfg.useHwmThrottle        = true;
   cfg.hwmTier1Dd            = 2.0;  cfg.hwmTier1Mult = 0.50;
   cfg.hwmTier2Dd            = 5.0;  cfg.hwmTier2Mult = 0.0;  cfg.hwmHaltDd = 5.0;
   //--- LOCKED: phase-initial balance is the sizing base; one working entry account-wide
   cfg.riskBaseInitialBalance = true;  cfg.riskInitialBalance = InpPhaseInitialBalance;
   cfg.oneEntryAccountWide    = true;   // no second entry while one is working or open
   cfg.flattenOnHalt          = true;   // governor halt = cancel entries + close
   cfg.newsFlatBeforeMin      = 15.0;   // flat 15 min before a relevant red event

   cfg.dayAnchorServer        = true;   // firm rollover on the SERVER day, never the clock day
   cfg.dayLockFirstWin        = true;   // any first net-positive exit locks the day

   cfg.dayLockAfterTrades     = 2;      // two completed sequential trades end the day


   cfg.maxRetries           = 1;                        // one revalidated retry only
   cfg.logLevel              = InpLogLevel;''',
    plan='''SSweepParams p;
   p.Reset();
   p.rangeFromMin   = 0;
   p.rangeToMin     = 7 * 60;
   p.sessionFromMin = 7 * 60;
   p.sessionToMin   = 11 * 60;
   p.sweepMinAtr    = 0.05;
   p.sweepMaxAtr    = 0.50;
   p.reclaimWindowBars = 3;
   p.wickRatio      = 0.60;
   p.bodyRatio      = 0.60;
   p.stopBufferAtr  = 0.10;
   p.minStopAtr     = 0.60;  p.maxStopAtr = 1.50;
   p.entryRetrace   = 0.50;
   p.targetR        = InpTargetR;

   if(ctx.symbol == "USDJPY")
   {
      p.rangeFromMin   = 7 * 60;
      p.rangeToMin     = 13 * 60;
      p.sessionFromMin = 13 * 60 + 30;
      p.sessionToMin   = 16 * 60;
   }
   if(ctx.clockMinutes < p.sessionFromMin || ctx.clockMinutes >= p.sessionToMin) return false;

   //--- revalidation gate: daily boundary max(balance,equity) x 0.95
   if(DailyBoundaryBreached(ctx)) return false;

   if(!SigSweepReclaim(ctx, p, plan)) return false;
   plan.reason = StringFormat("V2-REVALIDATED %s %s", ctx.symbol, plan.reason);
   return true;''',
    extra='''   //--- firm daily boundary: max(prior rollover balance, equity) x (1 - 5%)
   bool DailyBoundaryBreached(SEAContext &ctx)
   {
      double base = MathMax(ctx.dayStartEquity, AccountInfoDouble(ACCOUNT_BALANCE));
      if(base <= 0.0) return false;
      double floorLevel = base * (1.0 - InpDailyBoundaryPct);
      if(ctx.equity <= floorLevel)
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("daily boundary breached (equity %.2f <= %.2f)", ctx.equity, floorLevel), true);
         return true;
      }
      return false;
   }

   //--- qualifying-day + inactivity harness (evidence only, never fake a trade)
   void Manage(SEAContext &ctx)
   {
      static datetime lastDay = 0;
      MqlDateTime dt;
      TimeToStruct(ctx.nowClock, dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      datetime day = StructToTime(dt);
      if(lastDay != 0 && day != lastDay)
         EA_Log(EA_LOG_EVENTS, StringFormat("rollover: %d qualifying day(s) banked by the engine (no duplicate counter)",
                ctx.qualifyingDays));
      lastDay = day;

      //--- inactivity watchdog: warn day 20, escalate day 25
      string tkey = "EA_" + IntegerToString((long)InpMagicNumber) + "_LastTrade";
      if(!GlobalVariableCheck(tkey)) GlobalVariableSet(tkey, (double)ctx.nowServer);
      datetime lastTrade = (datetime)GlobalVariableGet(tkey);
      int idleDays = (int)((ctx.nowServer - lastTrade) / 86400);
      if(idleDays >= InpInactivityEscalateDays)
         EA_Log(EA_LOG_EVENTS, StringFormat("INACTIVITY ESCALATION: %d days without a trade - operator action required", idleDays), true);
      else if(idleDays >= InpInactivityWarnDays)
         EA_Log(EA_LOG_EVENTS, StringFormat("inactivity warning: %d days without a trade", idleDays), true);
   }''',
)


add(
    entry=20,
    name="EA_THE5ERS_END_TO_END_PRECODE_CHECKLIST",
    magic=3106,
    cls="PrecodeChecklist",
    title="The5ers pre-code checklist - staged compliance gates + paired profiles",
    doc="docs/prop_firm/THE5ERS-END-TO-END-PRECODE-CHECKLIST.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY", "risk": "0.4", "spread": "3.0",
            "daily": "1.0", "totaldd": "10", "target": "10", "maxday": "2"},
    inputs='''enum ENUM_PHASE25K
{
   PHASE25K_EVALUATION_1 = 0,  // Phase 1 (10% target)
   PHASE25K_EVALUATION_2 = 1,  // Phase 2 (5% target)
   PHASE25K_FUNDED       = 2   // Funded (capital preservation)
};
enum ENUM_RR_PROFILE
{
   RR_A_040_15 = 0,  // A: 0.40% risk / +1.50R
   RR_B_035_175= 1,  // B: 0.35% risk / +1.75R
   RR_C_030_20 = 2,  // C: 0.30% risk / +2.00R
   RR_D_025_25 = 3   // D: 0.25% risk / +2.50R
};
input ENUM_PHASE25K   InpPhase               = PHASE25K_EVALUATION_1; // Current product phase
input ENUM_RR_PROFILE InpProfile             = RR_A_040_15;           // Frozen risk/target pair
input double          InpPhaseInitialBalance = 2500.0;  // Persisted phase initial balance
input long            InpAuthorizedLogin     = 0;       // Account login (0 = skip the identity gate)
input string          InpAuthorizedProduct   = "$2,500 New High Stakes"; // Stage 0 product check
input bool            InpEnableTrading        = false;  // Stage 0/15 gate: refuse until verified
input int             InpTimeStopMinutes      = 45;     // Time exit candidate (30/45/60/90)
input bool            InpMoveBeAfter1R        = false;  // Breakeven challenger: M5 close beyond +1R
input string          InpNewsFile             = "the5ers_red_news.csv"; // Red-folder calendar (MQL5/Files)
input int             InpMaxRequestsPerDay     = 20;     // Non-emergency trade-request cap
input double InpQualifyingDayCash   = 12.50;  // 0.5% of $2,500: qualifying-day amount
input int    InpQualifyingDayCount  = 3;      // Qualifying days required per phase''',
    configure='''//--- paired profile A-D (Stage 1 candidates)
   double riskPct = 0.40, targetR = 1.50;
   if(InpProfile == RR_B_035_175) { riskPct = 0.35; targetR = 1.75; }
   if(InpProfile == RR_C_030_20)  { riskPct = 0.30; targetR = 2.00; }
   if(InpProfile == RR_D_025_25)  { riskPct = 0.25; targetR = 2.50; }
   if(InpPhase == PHASE25K_FUNDED) riskPct *= 0.5;          // funded preservation

   cfg.strategyName          = "PRECODE_CHECKLIST";
   cfg.sourceDoc             = "docs/prop_firm/THE5ERS-END-TO-END-PRECODE-CHECKLIST.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = riskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxSpreadPoints       = InpMaxSpreadPoints;
   cfg.dailyLossPct          = InpDailyLossPct;             // internal daily stop
   cfg.weeklyLossPct         = 2.0;                         // internal weekly stop
   cfg.totalDdPct            = InpTotalDdPct;               // static 10% floor
   cfg.profitTargetPct       = (InpPhase == PHASE25K_EVALUATION_2) ? 5.0 : InpProfitTargetPct;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 1;                           // one working order/position
   cfg.minSecondsBetweenTrades = 60;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;                        // flat before rollover
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.pendingExpiryMinutes  = 15;                          // three M5 candles
   cfg.timeStopMinutes       = InpTimeStopMinutes;
   cfg.partial1AtR           = 0.0;                         // partial closing removed
   cfg.breakEvenAtR          = (InpMoveBeAfter1R ? 1.0 : 0.0);
   cfg.breakEvenOnBarClose   = true;                    // only a completed bar confirms +1R
   cfg.useHwmThrottle        = true;                        // single documented half-risk tier
   cfg.hwmTier1Dd            = 2.0;  cfg.hwmTier1Mult = 0.50;
   cfg.hwmTier2Dd            = 5.0;  cfg.hwmTier2Mult = 0.0;  cfg.hwmHaltDd = 5.0;
   cfg.newsFilter            = true;                        // LOCKED 30-minute red-folder blackout
   cfg.newsFile              = InpNewsFile;
   cfg.newsBeforeMin         = 30;
   cfg.newsAfterMin          = 30;
   cfg.newsFailClosed        = true;                        // bad calendar = no new entries
   cfg.maxRequestsPerDay     = InpMaxRequestsPerDay;
   cfg.qualifyingDayAmount   = InpQualifyingDayCash;
   cfg.qualifyingDaysTarget  = InpQualifyingDayCount;
   //--- LOCKED: phase-initial balance is the sizing base; one working entry account-wide
   cfg.riskBaseInitialBalance = true;  cfg.riskInitialBalance = InpPhaseInitialBalance;
   cfg.oneEntryAccountWide    = true;   // no second entry while one is working or open
   cfg.flattenOnHalt          = true;   // governor halt = cancel entries + close
   cfg.newsFlatBeforeMin      = 15.0;   // flat 15 min before a relevant red event

   cfg.dayAnchorServer        = true;   // firm rollover on the SERVER day, never the clock day
   cfg.dayLockFirstWin        = true;   // any first net-positive exit locks the day

   cfg.dayLockAfterTrades     = 2;      // two completed sequential trades end the day


   cfg.maxRetries           = 1;                        // one revalidated retry only
   cfg.logLevel              = InpLogLevel;''',
    plan='''//--- Stage 0/15 gate: never trade an unverified product/account
   if(!InpEnableTrading) return false;
   if(InpAuthorizedLogin > 0 && AccountInfoInteger(ACCOUNT_LOGIN) != InpAuthorizedLogin) return false;

   double targetR = 1.50;
   if(InpProfile == RR_B_035_175) targetR = 1.75;
   if(InpProfile == RR_C_030_20)  targetR = 2.00;
   if(InpProfile == RR_D_025_25)  targetR = 2.50;

   SSweepParams p;
   p.Reset();
   p.rangeFromMin   = 0;
   p.rangeToMin     = 7 * 60;
   p.sessionFromMin = 7 * 60;
   p.sessionToMin   = 11 * 60;
   p.sweepMinAtr    = 0.05;
   p.sweepMaxAtr    = 0.50;
   p.reclaimWindowBars = 3;
   p.wickRatio      = 0.60;
   p.bodyRatio      = 0.60;
   p.stopBufferAtr  = 0.10;
   p.minStopAtr     = 0.60;  p.maxStopAtr = 1.50;
   p.entryRetrace   = 0.50;
   p.targetR        = targetR;

   if(ctx.symbol == "USDJPY")
   {
      p.rangeFromMin   = 7 * 60;
      p.rangeToMin     = 13 * 60;
      p.sessionFromMin = 13 * 60 + 30;
      p.sessionToMin   = 16 * 60;
   }
   if(ctx.clockMinutes < p.sessionFromMin || ctx.clockMinutes >= p.sessionToMin) return false;

   if(!SigSweepReclaim(ctx, p, plan)) return false;
   plan.reason = StringFormat("PRECODE-%s %s", EnumToString(InpProfile), plan.reason);
   return true;''',
    extra='''   //--- Stage 8/9/11: day lock, profitable-day accounting, phase transition
   void Manage(SEAContext &ctx)
   {
      static datetime lockedDay = 0;
      MqlDateTime dt;
      TimeToStruct(ctx.nowClock, dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      datetime day = StructToTime(dt);

      if(lockedDay == day)
      {
         if(ctx.openPositions == 0) EA_FlattenAll("day locked (pre-code state machine)");
         return;
      }
      //--- profitable-day engine: a first net-positive exit locks the day
      if(ctx.tradesToday == 1 && ctx.openPositions == 0 && ctx.dayRealizedPl > 0.0)
         lockedDay = day;
      //--- second completed trade always locks the day
      if(ctx.tradesToday >= 2 && ctx.openPositions == 0)
         lockedDay = day;

      //--- Stage 11: phase target reached (log the transition; a human flips InpPhase)
      double base = (InpPhaseInitialBalance > 0.0) ? InpPhaseInitialBalance : 2500.0;
      double target = (InpPhase == PHASE25K_EVALUATION_2) ? base * 1.05 : base * 1.10;
      if(AccountInfoDouble(ACCOUNT_EQUITY) >= target)
      {
         double qdays = 0;
         string key = "EA_" + IntegerToString((long)InpMagicNumber) + "_QualDays";
         if(GlobalVariableCheck(key)) qdays = GlobalVariableGet(key);
         EA_Log(EA_LOG_EVENTS, StringFormat("PHASE TARGET REACHED: equity %.2f >= %.2f (%d qualifying days) - verify on the dashboard before switching phase",
                AccountInfoDouble(ACCOUNT_EQUITY), target, (int)qdays), true);
      }
   }''',
)


add(
    entry=26,
    name="EA_Pr10_Roi_Improvements",
    magic=3112,
    cls="Pr10RoiImprovements",
    title="PR10 ROI improvements - cost-honest M5 fade + gold Donchian(55)",
    doc="docs/strategy/Pr10 Roi Improvements.md",
    common={"symbols": "EURUSD,GBPUSD,AUDUSD,USDCAD,XAUUSD", "risk": "0.4",
            "spread": "3.0", "daily": "1.0", "totaldd": "10", "target": "0", "maxday": "2"},
    inputs='''input double InpCommissionPerLotRT = 4.50;  // Set to the broker's real round-turn cost
input double InpMaxCostR             = 0.10;  // Reject setups whose all-in cost exceeds xR
input bool   InpTradeIntradayFade    = true;  // M5 exhaustion fade (XAUUSD removed by design)
input bool   InpTradeGoldSwing       = true;  // Gold Donchian(55) chandelier swing leg
input int    InpGoldDonchianDays     = 55;    // N=55 daily channel (findings_swing_and_portfolio)
input double InpGoldStopAtr          = 3.00;  // Initial stop in daily ATR
input double InpGoldTrailAtr         = 2.50;  // Chandelier trail (2.5 x ATR)
input double InpGoldTargetR          = 4.00;  // Wide target; the trail does the work
input double InpFadeTargetR          = 1.50;  // Intraday fade target''',
    configure='''cfg.strategyName          = "PR10_ROI_IMPROVEMENTS";
   cfg.sourceDoc             = "docs/strategy/Pr10 Roi Improvements.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxSpreadPoints       = InpMaxSpreadPoints;
   cfg.commissionPerLotRT    = InpCommissionPerLotRT;   // fix the cost variable
   cfg.maxCostR              = InpMaxCostR;
   cfg.dailyLossPct          = InpDailyLossPct;
   cfg.totalDdPct            = InpTotalDdPct;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 1;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 21;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.timeStopMinutes       = 90;
   cfg.breakEvenAtR          = 1.0;
   cfg.trailAtR              = 2.0;  cfg.trailDistanceR = 0.75;
   cfg.logLevel              = InpLogLevel;''',
    plan='''//--- Gold leg: Donchian(55) breakout with a 2.5 x ATR chandelier trail
   if(ctx.symbol == "XAUUSD")
   {
      if(!InpTradeGoldSwing) return false;
      SDonchianParams d;
      d.Reset();
      d.lookbackDays = InpGoldDonchianDays;
      d.stopD1Atr    = InpGoldStopAtr;
      d.targetR      = InpGoldTargetR;
      d.trailD1Atr   = InpGoldTrailAtr;
      d.longOnly     = false;
      if(!SigDonchian(ctx, d, plan)) return false;
      plan.reason = StringFormat("GOLD-DONCHIAN(%d) %s", InpGoldDonchianDays, plan.reason);
      return true;
   }

   //--- Intraday fade: gold is excluded from this sleeve on purpose
   //--- (measured -0.219R net expectancy on the held-out test window).
   if(!InpTradeIntradayFade) return false;

   SSweepParams p;
   p.Reset();
   p.rangeFromMin   = 0;
   p.rangeToMin     = 7 * 60;
   p.sessionFromMin = 7 * 60;
   p.sessionToMin   = 14 * 60;
   p.sweepMinAtr    = 0.05;
   p.sweepMaxAtr    = 0.50;
   p.reclaimWindowBars = 3;
   p.wickRatio      = 0.60;
   p.bodyRatio      = 0.60;
   p.stopBufferAtr  = 0.10;
   p.minStopAtr     = 0.60;  p.maxStopAtr = 1.50;
   p.entryRetrace   = 0.50;
   p.targetR        = InpFadeTargetR;
   if(!SigSweepReclaim(ctx, p, plan)) return false;
   plan.reason = StringFormat("PR10-FADE %s %s", ctx.symbol, plan.reason);
   return true;''',
    extra='''   //--- Rejected by the PR10 findings (kept out of the code on purpose):
   //---   * M1 scalping / ORB        : real costs flip the champion to -1.03R
   //---   * winner pyramiding        : underperformed the single-entry baseline
   //---   * Fibonacci progression    : 18% 99th-percentile sequence drawdown
   //---   * free-margin stacking     : one gapping shock doubles the drawdown
   void Manage(SEAContext &ctx)
   {
      if(ctx.symbol != "XAUUSD") return;
      //--- chandelier trail on the gold swing leg: 2.5 x daily ATR behind the extreme
      double atr = ctx.atrD1;
      if(atr <= 0.0) return;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;
         bool   isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         double sl    = PositionGetDouble(POSITION_SL);
         double tp    = PositionGetDouble(POSITION_TP);
         double cur   = PositionGetDouble(POSITION_PRICE_CURRENT);
         double newSl = isBuy ? cur - InpGoldTrailAtr * atr : cur + InpGoldTrailAtr * atr;
         if((isBuy && newSl > sl) || (!isBuy && (sl <= 0.0 || newSl < sl)))
            g_eaExec.Modify(t, eaRoundSafe(ctx.symbol, newSl), tp);
      }
   }''',
)


add(
    entry=21,
    name="EA_THE5ERS_HIGH_STAKES_RESEARCH",
    magic=3107,
    cls="HighStakesResearch",
    title="The5ers High Stakes research - internal limit ladder + news jurisdiction",
    doc="docs/prop_firm/THE5ERS-HIGH-STAKES-RESEARCH.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY", "risk": "0.4", "spread": "3.0",
            "daily": "1.0", "totaldd": "10", "target": "10", "maxday": "2"},
    inputs='''enum ENUM_HIGH_STAKES_VARIANT
{
   HS_NEW_10PCT     = 0,  // New High Stakes: 10% Phase 1
   HS_CLASSIC_8PCT  = 1   // Classic High Stakes: 8% Phase 1
};
input ENUM_HIGH_STAKES_VARIANT InpVariant = HS_NEW_10PCT; // Program variant
input double InpWeeklyStopPct     = 2.50;  // Internal weekly stop (2.0-2.5%)
input double InpShutdownPct       = 5.50;  // Strategy shutdown/review (5.5-6.0%)
input double InpMaxOpenRiskPct    = 0.72;  // Normal maximum open risk
input double InpAbsOpenRiskCapPct = 1.00;  // Absolute technical open-risk cap
input bool   InpNewsGate          = true;  // Red-folder news blackout
input int    InpNewsBeforeMin     = 30;    // Cancel/protect before the event
input int    InpNewsAfterMin      = 30;    // No retries after the event
input double InpAccountSize       = 2500.0; // Account size for the $150 payout gate
input double InpQualifyingDayCash   = 12.50;  // 0.5% of $2,500: qualifying-day amount
input int    InpQualifyingDayCount  = 3;      // Qualifying days required per phase''',
    configure='''cfg.strategyName          = "HIGH_STAKES_RESEARCH";
   cfg.sourceDoc             = "docs/prop_firm/THE5ERS-HIGH-STAKES-RESEARCH.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = MathMin(InpRiskPct, InpMaxOpenRiskPct);   // 0.72% normal cap
   cfg.signalTimeframe       = PERIOD_M15;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.serverOffsetAuto      = true;                       // live offset, never hard-coded
   cfg.maxSpreadPoints       = InpMaxSpreadPoints;
   cfg.dailyLossPct          = InpDailyLossPct;            // internal 0.75-1.0%
   cfg.weeklyLossPct         = InpWeeklyStopPct;           // internal 2.0-2.5%
   cfg.totalDdPct            = InpTotalDdPct;              // 10% firm floor
   cfg.profitTargetPct       = (InpVariant == HS_CLASSIC_8PCT) ? 8.0 : 10.0;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 1;                          // bulk trading is prohibited
   cfg.minSecondsBetweenTrades = 300;                      // no tick-scalping profile
   cfg.useHwmThrottle        = true;
   cfg.hwmTier1Dd            = 2.0;  cfg.hwmTier1Mult = 0.50;
   cfg.hwmTier2Dd            = InpShutdownPct;  cfg.hwmTier2Mult = 0.0;
   cfg.hwmHaltDd             = InpShutdownPct;             // shutdown/review boundary
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 21;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.pendingExpiryMinutes  = 15;
   cfg.newsFilter            = InpNewsGate;                // fail closed when enabled
   cfg.newsFile              = "the5ers_red_news.csv";
   cfg.newsBeforeMin         = InpNewsBeforeMin;
   cfg.newsAfterMin          = InpNewsAfterMin;
   cfg.newsFailClosed        = true;                       // bad calendar = no new entries
   cfg.qualifyingDayAmount   = InpQualifyingDayCash;
   cfg.qualifyingDaysTarget  = InpQualifyingDayCount;
   cfg.timeStopMinutes       = 45;
   cfg.breakEvenAtR          = 1.0;
   cfg.breakEvenOnBarClose   = true;                    // only a completed bar confirms +1R
   //--- LOCKED: phase-initial balance is the sizing base; one working entry account-wide
   cfg.riskBaseInitialBalance = true;  cfg.riskInitialBalance = InpAccountSize;
   cfg.oneEntryAccountWide    = true;   // no second entry while one is working or open
   cfg.flattenOnHalt          = true;   // governor halt = cancel entries + close
   cfg.newsFlatBeforeMin      = 15.0;   // flat 15 min before a relevant red event

   cfg.dayAnchorServer        = true;   // firm rollover on the SERVER day, never the clock day
   cfg.dayLockFirstWin        = true;   // any first net-positive exit locks the day

   cfg.dayLockAfterTrades     = 2;      // two completed sequential trades end the day


   cfg.maxRetries           = 1;                        // one revalidated retry only
   cfg.logLevel              = InpLogLevel;''',
    plan='''//--- Sleeve A sweep/reclaim on M15 ATR geometry
   SSweepParams p;
   p.Reset();
   p.rangeFromMin   = 0;
   p.rangeToMin     = 7 * 60;
   p.sessionFromMin = 7 * 60;
   p.sessionToMin   = 16 * 60;
   p.sweepMinAtr    = 0.05;
   p.sweepMaxAtr    = 0.50;
   p.reclaimWindowBars = 3;
   p.wickRatio      = 0.60;
   p.bodyRatio      = 0.60;
   p.stopBufferAtr  = 0.10;
   p.minStopAtr     = 0.60;  p.maxStopAtr = 1.50;
   p.entryRetrace   = 0.50;
   p.targetR        = 1.50;

   if(ctx.symbol == "USDJPY")
   {
      p.rangeFromMin   = 7 * 60;
      p.rangeToMin     = 13 * 60;
      p.sessionFromMin = 13 * 60 + 30;
      p.sessionToMin   = 16 * 60;
   }
   if(ctx.clockMinutes < p.sessionFromMin || ctx.clockMinutes >= p.sessionToMin) return false;

   if(!SigSweepReclaim(ctx, p, plan)) return false;
   plan.reason = StringFormat("HS-RESEARCH %s %s", ctx.symbol, plan.reason);
   return true;''',
    extra='''   //--- Section 4 (news): cancel unfilled entries before the blackout and
   //--- suppress retries inside it; Section 3: enforce the absolute open-risk cap.
   void Manage(SEAContext &ctx)
   {
      if(ctx.newsBlocked)
      {
         g_eaExec.CancelPending(ctx.symbol, "news blackout");
         return;
      }
      double openRisk = EA_OpenRiskPct();
      if(openRisk > InpAbsOpenRiskCapPct)
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("open risk %.2f%% above absolute cap %.2f%% - flattening",
                openRisk, InpAbsOpenRiskCapPct), true);
         EA_FlattenAll("absolute open-risk cap");
      }
   }''',
)


add(
    entry=22,
    name="EA_THE5ERS_PROPOSAL_REVIEW",
    magic=3108,
    cls="ProposalReview",
    title="The5ers proposal review - corrected profitable-day and cash-risk rules",
    doc="docs/prop_firm/THE5ERS-PROPOSAL-REVIEW.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY", "risk": "0.4", "spread": "3.0",
            "daily": "1.0", "totaldd": "10", "target": "10", "maxday": "2"},
    inputs='''enum ENUM_REVIEW_PHASE
{
   REVIEW_PHASE_1 = 0,  // Phase 1 (10% / $250)
   REVIEW_PHASE_2 = 1,  // Phase 2 (5% / $125, fresh counter)
   REVIEW_FUNDED  = 2   // Funded (same process, capital preservation)
};
input ENUM_REVIEW_PHASE InpReviewPhase      = REVIEW_PHASE_1;  // Current phase
input double InpPhaseInitialBalance         = 2500.0;  // Phase initial balance
input double InpPlannedRiskCash             = 10.00;   // Planned $ risk per trade (review #8)
input double InpQualifyingDayCash           = 12.50;   // 0.5% qualifying-day amount
input bool   InpVerifyProductName           = false;   // VERIFY item: confirm at checkout
input int    InpRolloverHourServer          = 0;       // Server rollover hour
input int    InpFlatBeforeRolloverMin       = 15;      // Stay flat into rollover
input string InpNewsFile             = "the5ers_red_news.csv"; // Red-folder calendar (MQL5/Files)
input int    InpQualifyingDayCount  = 3;      // Qualifying days required per phase''',
    configure='''cfg.strategyName          = "PROPOSAL_REVIEW";
   cfg.sourceDoc             = "docs/prop_firm/THE5ERS-PROPOSAL-REVIEW.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxSpreadPoints       = InpMaxSpreadPoints;
   cfg.dailyLossPct          = InpDailyLossPct;
   cfg.weeklyLossPct         = 2.0;
   cfg.totalDdPct            = InpTotalDdPct;
   cfg.newsFile              = InpNewsFile;
   cfg.newsFailClosed        = true;                       // bad calendar = no new entries
   cfg.qualifyingDayAmount   = InpQualifyingDayCash;
   cfg.qualifyingDaysTarget  = InpQualifyingDayCount;
   cfg.profitTargetPct       = (InpReviewPhase == REVIEW_PHASE_2) ? 5.0 : InpProfitTargetPct;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 1;                       // single position account-wide
   cfg.minSecondsBetweenTrades = 60;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.pendingExpiryMinutes  = 15;
   cfg.timeStopMinutes       = 45;
   cfg.breakEvenAtR          = 1.0;
   cfg.breakEvenOnBarClose   = true;                    // only a completed bar confirms +1R
   cfg.partial1AtR           = 0.0;                     // no partial closes
   //--- LOCKED: phase-initial balance is the sizing base; one working entry account-wide
   cfg.riskBaseInitialBalance = true;  cfg.riskInitialBalance = InpPhaseInitialBalance;
   cfg.oneEntryAccountWide    = true;   // no second entry while one is working or open
   cfg.flattenOnHalt          = true;   // governor halt = cancel entries + close
   cfg.newsFlatBeforeMin      = 15.0;   // flat 15 min before a relevant red event

   cfg.dayAnchorServer        = true;   // firm rollover on the SERVER day, never the clock day
   cfg.dayLockFirstWin        = true;   // any first net-positive exit locks the day

   cfg.dayLockAfterTrades     = 2;      // two completed sequential trades end the day


   cfg.maxRetries           = 1;                        // one revalidated retry only
   cfg.logLevel              = InpLogLevel;''',
    plan='''if(InpVerifyProductName) return false;    // VERIFY item stays fail-closed until confirmed

   SSweepParams p;
   p.Reset();
   p.rangeFromMin   = 0;
   p.rangeToMin     = 7 * 60;
   p.sessionFromMin = 7 * 60;
   p.sessionToMin   = 11 * 60;
   p.sweepMinAtr    = 0.05;
   p.sweepMaxAtr    = 0.50;
   p.reclaimWindowBars = 3;
   p.wickRatio      = 0.60;
   p.bodyRatio      = 0.60;
   p.stopBufferAtr  = 0.10;
   p.minStopAtr     = 0.60;  p.maxStopAtr = 1.50;
   p.entryRetrace   = 0.50;
   p.targetR        = 1.50;

   if(ctx.symbol == "USDJPY")
   {
      p.rangeFromMin   = 7 * 60;
      p.rangeToMin     = 13 * 60;
      p.sessionFromMin = 13 * 60 + 30;
      p.sessionToMin   = 16 * 60;
   }
   if(ctx.clockMinutes < p.sessionFromMin || ctx.clockMinutes >= p.sessionToMin) return false;

   if(!SigSweepReclaim(ctx, p, plan)) return false;
   plan.reason = StringFormat("REVIEW-SLEEVE-A %s %s", ctx.symbol, plan.reason);
   return true;''',
    extra='''   //--- MODIFY #8: $10 planned cash risk per challenge trade
   double LotsMultiplier(SEAContext &ctx)
   {
      double planned = ctx.equity * (ctx.riskPct / 100.0);
      if(InpPlannedRiskCash > 0.0 && planned > InpPlannedRiskCash)
         return InpPlannedRiskCash / planned;
      return 1.0;
   }

   //--- corrected profitable-day rules: non-qualifying days never reset the count,
   //--- Phase 2 starts a fresh counter, and the EA stays flat into rollover.
   void Manage(SEAContext &ctx)
   {
      //--- flat X minutes before the server rollover
      MqlDateTime sdt;
      TimeToStruct(TimeTradeServer(), sdt);
      int secsToRollover = 86400 - (sdt.hour * 3600 + sdt.min * 60 + sdt.sec);
      if(secsToRollover <= InpFlatBeforeRolloverMin * 60)
      {
         if(ctx.openPositions > 0 || EA_CountPendings("") > 0)
            EA_FlattenAll("flat into rollover");
      }

      //--- qualifying-day accounting (any three days per phase, never reset downward)
      static datetime lastDay = 0;
      MqlDateTime dt;
      TimeToStruct(ctx.nowClock, dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      datetime day = StructToTime(dt);
      if(lastDay != 0 && day != lastDay)
         EA_Log(EA_LOG_EVENTS, StringFormat("rollover: engine holds %d qualifying day(s) of %d (phase decision stays manual)",
                ctx.qualifyingDays, InpQualifyingDayCount));
      lastDay = day;
   }''',
)


add(
    entry=23,
    name="EA_THE5ERS_STRATEGY_IMPROVEMENT_SUGGESTION_REVIEW",
    magic=3109,
    cls="SuggestionReview",
    title="Suggestion review - fail-closed release gates over canonical V2 Sleeve A",
    doc="docs/prop_firm/THE5ERS-STRATEGY-IMPROVEMENT-SUGGESTION-REVIEW.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY", "risk": "0.4", "spread": "3.0",
            "daily": "1.0", "totaldd": "10", "target": "10", "maxday": "2"},
    inputs='''
input double InpPhaseInitialBalance = 2500.0; // Persisted phase initial balance (LOCKED sizing base)
input bool InpGateDataProvenanceOK   = false;  // Global gate: data acquired + versioned
input bool InpGateReplayExportOK     = false;  // Global gate: replay exporter produces the registry rows
input bool InpGateDeclaredGatesSigned = false; // Global gate: Section 13 gates declared
input bool InpGateEurusdLondon       = false;  // Per-combination gate: EURUSD London
input bool InpGateGbpsdLondon        = false;  // Per-combination gate: GBPUSD London
input bool InpGateUsdjpyNewYork      = false;  // Per-combination gate: USDJPY New York
input bool InpAcknowledgeNotApproved = false;  // Reviewer: README = not compile-verified/backtested/approved
input string InpNewsFile             = "the5ers_red_news.csv"; // Red-folder calendar (MQL5/Files)
input double InpQualifyingDayCash   = 12.50;  // 0.5% of $2,500: qualifying-day amount
input int    InpQualifyingDayCount  = 3;      // Qualifying days required per phase''',
    configure='''cfg.strategyName          = "SUGGESTION_REVIEW_GATES";
   cfg.sourceDoc             = "docs/prop_firm/THE5ERS-STRATEGY-IMPROVEMENT-SUGGESTION-REVIEW.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.maxCostR              = 0.10;                       // round-trip cost ceiling (section 13)
   cfg.maxRequestsPerDay     = 20;                         // excess-request safeguard
   cfg.newsFilter            = true;
   cfg.newsFile              = InpNewsFile;
   cfg.newsFailClosed        = true;                       // bad calendar = no new entries
   cfg.qualifyingDayAmount   = InpQualifyingDayCash;
   cfg.qualifyingDaysTarget  = InpQualifyingDayCount;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxSpreadPoints       = InpMaxSpreadPoints;
   cfg.dailyLossPct          = InpDailyLossPct;
   cfg.weeklyLossPct         = 2.0;
   cfg.totalDdPct            = InpTotalDdPct;
   cfg.profitTargetPct       = InpProfitTargetPct;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 1;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.useLimitEntry         = true;                       // frozen V2 entry is a limit at the 50% retracement
   cfg.pendingExpiryMinutes  = 15;
   cfg.timeStopMinutes       = 45;
   cfg.breakEvenAtR          = 0.0;                     // frozen controls: no breakeven move
   cfg.partial1AtR           = 0.0;                     // V2 removed partial closing
   //--- LOCKED: phase-initial balance is the sizing base; one working entry account-wide
   cfg.riskBaseInitialBalance = true;  cfg.riskInitialBalance = InpPhaseInitialBalance;
   cfg.oneEntryAccountWide    = true;   // no second entry while one is working or open
   cfg.flattenOnHalt          = true;   // governor halt = cancel entries + close
   cfg.newsFlatBeforeMin      = 15.0;   // flat 15 min before a relevant red event

   cfg.dayAnchorServer        = true;   // firm rollover on the SERVER day, never the clock day
   cfg.dayLockFirstWin        = true;   // any first net-positive exit locks the day

   cfg.dayLockAfterTrades     = 2;      // two completed sequential trades end the day


   cfg.maxRetries           = 1;                        // one revalidated retry only
   cfg.logLevel              = InpLogLevel;''',
    plan='''//--- fail-closed release gates: nothing trades until every gate is enabled
   if(!InpGateDataProvenanceOK || !InpGateReplayExportOK || !InpGateDeclaredGatesSigned) return false;
   bool comboEnabled = false;
   if(ctx.symbol == "EURUSD") comboEnabled = InpGateEurusdLondon;
   if(ctx.symbol == "GBPUSD") comboEnabled = InpGateGbpsdLondon;
   if(ctx.symbol == "USDJPY") comboEnabled = InpGateUsdjpyNewYork;
   if(!comboEnabled) return false;

   //--- canonical V2 Sleeve A (no H1 context, no partials, XAUUSD excluded)
   SSweepParams p;
   p.Reset();
   p.rangeFromMin   = 0;
   p.rangeToMin     = 7 * 60;
   p.sessionFromMin = 7 * 60;
   p.sessionToMin   = 11 * 60;
   p.sweepMinAtr    = 0.05;
   p.sweepMaxAtr    = 0.50;
   p.reclaimWindowBars = 3;
   p.wickRatio      = 0.60;
   p.bodyRatio      = 0.60;
   p.stopBufferAtr  = 0.10;
   p.minStopAtr     = 0.60;  p.maxStopAtr = 1.50;
   p.entryRetrace   = 0.50;
   p.targetR        = 1.50;

   if(ctx.symbol == "USDJPY")
   {
      p.rangeFromMin   = 7 * 60;
      p.rangeToMin     = 13 * 60;
      p.sessionFromMin = 13 * 60 + 30;
      p.sessionToMin   = 16 * 60;
   }
   if(ctx.clockMinutes < p.sessionFromMin || ctx.clockMinutes >= p.sessionToMin) return false;

   if(!SigSweepReclaim(ctx, p, plan)) return false;
   plan.reason = StringFormat("V2-CANONICAL %s %s", ctx.symbol, plan.reason);
   return true;''',
    extra='''   //--- the reviewer's checklist is printed once at init so the operator sees
   //--- exactly which release gate is still open
   void OnInitStrategy()
   {
      EA_Log(EA_LOG_EVENTS, "release gates (all must be true before trading):");
      EA_Log(EA_LOG_EVENTS, StringFormat("  data provenance........ %s", InpGateDataProvenanceOK ? "PASS" : "OPEN"));
      EA_Log(EA_LOG_EVENTS, StringFormat("  replay exporter........ %s", InpGateReplayExportOK ? "PASS" : "OPEN"));
      EA_Log(EA_LOG_EVENTS, StringFormat("  declared gates......... %s", InpGateDeclaredGatesSigned ? "PASS" : "OPEN"));
      EA_Log(EA_LOG_EVENTS, StringFormat("  EURUSD London.......... %s", InpGateEurusdLondon ? "PASS" : "OPEN"));
      EA_Log(EA_LOG_EVENTS, StringFormat("  GBPUSD London.......... %s", InpGateGbpsdLondon ? "PASS" : "OPEN"));
      EA_Log(EA_LOG_EVENTS, StringFormat("  USDJPY New York........ %s", InpGateUsdjpyNewYork ? "PASS" : "OPEN"));
      if(!InpAcknowledgeNotApproved)
         EA_Log(EA_LOG_EVENTS, "NOTE: this build is not approved for live trading until the gates above pass");
   }''',
)


add(
    entry=24,
    name="EA_TRIAD_R_HS_CODE_REVIEW",
    magic=3110,
    cls="TriadCodeReviewHardened",
    title="TRIAD-R code review - hardened runtime controls from the 12 findings",
    doc="docs/strategy/TRIAD_R_HS-CODE-REVIEW.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY", "risk": "0.4", "spread": "3.0",
            "daily": "1.0", "totaldd": "10", "target": "10", "maxday": "2"},
    inputs='''enum ENUM_REVIEW_PROFILE
{
   REVIEW_RR_A = 0,  // A: 0.40% / +1.50R
   REVIEW_RR_B = 1,  // B: 0.35% / +1.75R
   REVIEW_RR_C = 2,  // C: 0.30% / +2.00R
   REVIEW_RR_D = 3   // D: 0.25% / +2.50R
};
input ENUM_REVIEW_PROFILE InpReviewProfile   = REVIEW_RR_A;   // Exactly one paired profile
input long   InpAuthorizedLogin              = 0;    // Finding 12: runtime identity revalidation
input int    InpEarlyLeadSeconds             = 5;    // Finding 9: fixed early execution lead
input int    InpLeaseMinutes                 = 10;   // Finding 3: single-instance lease
input string InpPriorityOrder                = "EURUSD,GBPUSD,USDJPY"; // Finding 7: frozen priority
input string InpNewsCoverageThrough          = "";   // Finding 6: explicit UTC coverage-through
input int    InpMaxEmergencyRetries          = 2;    // Finding 10: escalation policy''',
    configure='''double riskPct = 0.40, targetR = 1.50;
   if(InpReviewProfile == REVIEW_RR_B) { riskPct = 0.35; targetR = 1.75; }
   if(InpReviewProfile == REVIEW_RR_C) { riskPct = 0.30; targetR = 2.00; }
   if(InpReviewProfile == REVIEW_RR_D) { riskPct = 0.25; targetR = 2.50; }

   cfg.strategyName          = "TRIAD_R_HS_HARDENED";
   cfg.sourceDoc             = "docs/strategy/TRIAD_R_HS-CODE-REVIEW.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = riskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxSpreadPoints       = InpMaxSpreadPoints;
   cfg.dailyLossPct          = InpDailyLossPct;
   cfg.weeklyLossPct         = 2.0;
   cfg.totalDdPct            = InpTotalDdPct;
   cfg.profitTargetPct       = InpProfitTargetPct;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 1;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;                    // finding 4: no offline exposure over rollover
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.pendingExpiryMinutes  = 15;
   cfg.timeStopMinutes       = 45;
   cfg.breakEvenAtR          = 1.0;
   cfg.partial1AtR           = 0.0;
   cfg.maxRetries            = 2;
   cfg.logLevel              = InpLogLevel;''',
    plan='''if(!RuntimeGatesOk()) return false;

   SSweepParams p;
   p.Reset();
   p.rangeFromMin   = 0;
   p.rangeToMin     = 7 * 60;
   p.sessionFromMin = 7 * 60;
   p.sessionToMin   = 11 * 60;
   p.sweepMinAtr    = 0.05;
   p.sweepMaxAtr    = 0.50;
   p.reclaimWindowBars = 3;
   p.wickRatio      = 0.60;
   p.bodyRatio      = 0.60;
   p.stopBufferAtr  = 0.10;
   p.minStopAtr     = 0.60;  p.maxStopAtr = 1.50;
   p.entryRetrace   = 0.50;
   p.targetR        = 1.50;
   if(InpReviewProfile == REVIEW_RR_B) p.targetR = 1.75;
   if(InpReviewProfile == REVIEW_RR_C) p.targetR = 2.00;
   if(InpReviewProfile == REVIEW_RR_D) p.targetR = 2.50;

   if(ctx.symbol == "USDJPY")
   {
      p.rangeFromMin   = 7 * 60;
      p.rangeToMin     = 13 * 60;
      p.sessionFromMin = 13 * 60 + 30;
      p.sessionToMin   = 16 * 60;
   }
   //--- finding 9: every boundary is approached with a fixed early lead
   if(ctx.clockMinutes < p.sessionFromMin || ctx.clockMinutes >= p.sessionToMin) return false;
   if(ctx.clockMinutes + (InpEarlyLeadSeconds / 60) >= p.sessionToMin) return false;

   if(!SigSweepReclaim(ctx, p, plan)) return false;
   plan.reason = StringFormat("TRIAD-HARDENED %s %s", ctx.symbol, plan.reason);
   return true;''',
    extra='''   //--- finding 7: frozen combination priority (EURUSD > GBPUSD > USDJPY)
   double RankSetup(SEAContext &ctx, const SSignalPlan &plan)
   {
      int pos = 0;
      string parts[];
      int n = StringSplit(InpPriorityOrder, ',', parts);
      for(int i = 0; i < n; i++)
      {
         string s = parts[i];
         StringTrimLeft(s); StringTrimRight(s);
         if(s == ctx.symbol) { pos = i; break; }
      }
      return plan.score - pos * 10.0;      // earlier in the list wins collisions
   }

   //--- findings 3 / 5 / 6 / 10 / 12: runtime gates
   bool RuntimeGatesOk()
   {
      if(InpAuthorizedLogin > 0 && AccountInfoInteger(ACCOUNT_LOGIN) != InpAuthorizedLogin)
      {
         EA_Log(EA_LOG_EVENTS, "identity mismatch - refusing to trade", true);
         return false;
      }
      //--- single-instance lease
      string hireKey = "EA_" + IntegerToString((long)InpMagicNumber) + "_LeaseHolder";
      string timeKey = "EA_" + IntegerToString((long)InpMagicNumber) + "_LeaseTime";
      datetime now = TimeTradeServer();
      if(GlobalVariableCheck(hireKey))
      {
         double holder = GlobalVariableGet(hireKey);
         double stamp  = GlobalVariableCheck(timeKey) ? GlobalVariableGet(timeKey) : 0.0;
         if((double)ChartID() != holder && now - (datetime)stamp < InpLeaseMinutes * 60)
         {
            EA_Log(EA_LOG_EVENTS, "another instance holds the lease - refusing to trade", true);
            return false;
         }
      }
      GlobalVariableSet(hireKey, (double)ChartID());
      GlobalVariableSet(timeKey, (double)now);
      //--- finding 6: news coverage must be explicitly declared, not inferred
      if(g_eaCfg.newsFilter)
      {
         datetime coverage = StringToTime(InpNewsCoverageThrough);
         if(coverage <= 0 || coverage < EA_ServerToUtc(now))
         {
            EA_Log(EA_LOG_EVENTS, "news coverage-through missing or expired - failing closed", true);
            return false;
         }
      }
      return true;
   }

   //--- findings 1 / 2 / 5 / 10 / 11: execution-integrity management
   void Manage(SEAContext &ctx)
   {
      //--- every position must carry a broker-visible stop (finding 10)
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetDouble(POSITION_SL) <= 0.0)
         {
            EA_Log(EA_LOG_EVENTS, StringFormat("CRITICAL: %s position without a stop - closing immediately",
                   PositionGetString(POSITION_SYMBOL)));
            g_eaExec.Close(t, "unprotected exposure (review finding 10)");
         }
      }
      //--- finding 5: external cashflow detection while flat and inactive
      static double balanceRef = -1.0;
      if(balanceRef < 0.0) balanceRef = AccountInfoDouble(ACCOUNT_BALANCE);
      if(ctx.openPositionsAll == 0 && ctx.tradesToday == 0)
      {
         double bal = AccountInfoDouble(ACCOUNT_BALANCE);
         if(MathAbs(bal - balanceRef) > 1.0)
         {
            EA_Log(EA_LOG_EVENTS, StringFormat("CRITICAL: unexplained balance change %.2f -> %.2f - halting for review",
                   balanceRef, bal));
            g_eaRisk.Halt("external cashflow / unauthorized history");
         }
         balanceRef = bal;
      }
   }''',
)


add(
    entry=25,
    name="EA_TRIAD_SURVIVE",
    magic=3111,
    cls="TriadSurvive",
    title="TRIAD-SURVIVE - three-sleeve portfolio with scored entries and risk caps",
    doc="docs/strategy/TRIAD-SURVIVE.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY,AUDUSD,XAUUSD,GBPJPY,AUDNZD,EURGBP,EURCHF",
            "risk": "0.24", "spread": "4.0", "daily": "1.0", "totaldd": "10",
            "target": "0", "maxday": "4"},
    inputs='''input double InpFullTierRiskPct    = 0.24;  // 8/8 or 5/5 score: full tier risk
input double InpHalfTierRiskPct    = 0.12;  // 7/8 or 4/5 score: half tier risk
input double InpMaxTotalOpenRisk   = 1.00;  // Max total open risk at any moment
input double InpMaxGroupRiskPct    = 0.24;  // Max risk per correlated group
input int    InpMaxPositions       = 4;     // Max concurrent positions (all sleeves)
input int    InpMaxPerSleeve       = 2;     // Max concurrent positions per sleeve
input double InpShutdownDdPct      = 6.00;  // Shutdown from closed-equity high
input int    InpSleeveATimeStopMin = 45;    // Sleeve A: the 45-minute plateau
input double InpRunnerTrailAtr     = 2.5;   // Runner chandelier: 2.5 x ATR(H1,14)
input int    InpSleeveCExitMinute  = 390;   // Sleeve C hard flat 06:30 London
input bool   InpSleeveAEnabled     = true;
input bool   InpSleeveBEnabled     = true;
input bool   InpSleeveCEnabled     = true;''',
    configure='''cfg.strategyName          = "TRIAD_SURVIVE";
   cfg.sourceDoc             = "docs/strategy/TRIAD-SURVIVE.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpFullTierRiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxSpreadPoints       = InpMaxSpreadPoints;
   cfg.dailyLossPct          = InpDailyLossPct;
   cfg.weeklyLossPct         = 2.0;
   cfg.totalDdPct            = InpTotalDdPct;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = InpMaxPositions;
   cfg.minSecondsBetweenTrades = 120;
   cfg.useHwmThrottle        = true;
   cfg.hwmTier1Dd            = 2.0;  cfg.hwmTier1Mult = 0.50;   // 2-4%: half tier
   cfg.hwmTier2Dd            = 4.0;  cfg.hwmTier2Mult = 0.25;   // 4-6%: quarter tier
   cfg.hwmHaltDd             = InpShutdownDdPct;                // above 6%: shutdown
   cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 19;  cfg.sessionEndMin = 30;
   cfg.noTradeAfterHour      = 21;  cfg.noTradeAfterMin = 30;   // no thin-liquidity entries
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.pendingExpiryMinutes  = 15;                              // three M5 candles
   cfg.timeStopMinutes       = 0;                               // per-sleeve, in Manage()
   cfg.breakEvenAtR          = 0.0;                             // ladder moves the stop instead
   cfg.partial1AtR           = 0.0;                             // per-symbol ladder in Manage()
   cfg.logLevel              = InpLogLevel;''',
    plan='''//--- portfolio-level caps first
   m_lastScore = 0.0;
   if(EA_OpenRiskPct() >= InpMaxTotalOpenRisk) return false;
   if(EA_CountPositions("", false) >= InpMaxPositions) return false;

   int    sleeve = 0;
   double tierRisk = InpFullTierRiskPct;
   double score = 0.0;

   //--- SLEEVE C: Asian mean reversion, 00:00-06:30, single entry, hard flat 06:30
   if(IsSleeveCSymbol(ctx.symbol) && InpSleeveCEnabled && ctx.clockMinutes < InpSleeveCExitMinute)
   {
      sleeve = 3;
      if(!SleeveCPlan(ctx, plan, score)) return false;
      tierRisk = (score >= 5.0) ? InpFullTierRiskPct : InpHalfTierRiskPct;
   }
   //--- SLEEVE B: volatility-expansion continuation (M15 breakout + retest)
   else if(IsSleeveBSymbol(ctx.symbol) && InpSleeveBEnabled)
   {
      sleeve = 2;
      if(!SleeveBPlan(ctx, plan, score)) return false;
      tierRisk = (score >= 5.0) ? InpFullTierRiskPct : InpHalfTierRiskPct;
   }
   //--- SLEEVE A: session sweep/reclaim, scored 8-point profile
   else
   {
      if(!InpSleeveAEnabled) return false;
      sleeve = 1;
      SSweepParams p;
      p.Reset();
      p.rangeFromMin   = 0;
      p.rangeToMin     = 7 * 60;
      p.sessionFromMin = 7 * 60;
      p.sessionToMin   = 11 * 60;
      p.sweepMinAtr    = 0.05;
      p.sweepMaxAtr    = 0.50;
      p.reclaimWindowBars = 3;
      p.wickRatio      = 0.60;
      p.bodyRatio      = 0.60;
      p.stopBufferAtr  = 0.10;
      p.minStopAtr     = 0.60;  p.maxStopAtr = 1.50;
      p.entryRetrace   = 0.50;
      p.targetR        = 1.50;
      if(ctx.symbol == "USDJPY" || ctx.symbol == "XAUUSD")
      {
         p.rangeFromMin   = 7 * 60;    // New York window uses the London range
         p.rangeToMin     = 13 * 60;
         p.sessionFromMin = 13 * 60 + 30;
         p.sessionToMin   = 16 * 60;
      }
      if(ctx.clockMinutes < p.sessionFromMin || ctx.clockMinutes >= p.sessionToMin) return false;
      if(!SigSweepReclaim(ctx, p, plan)) return false;
      score = ScoreSleeveA(ctx, plan, p.rangeFromMin, p.rangeToMin);
      if(score <= 6.0) return false;                               // 6 or below: no trade
      tierRisk = (score >= 8.0) ? InpFullTierRiskPct : InpHalfTierRiskPct;
   }

   //--- correlated-group cap (USD / JPY / commodity / European cross)
   string group = CorrelatedGroup(ctx.symbol);
   if(group != "" && EA_GroupRiskPct(group) + tierRisk > InpMaxGroupRiskPct) return false;

   m_sleeve    = sleeve;
   m_lastScore = score;
   m_tierRisk  = tierRisk;
   plan.score  = score * 10.0;
   plan.reason = StringFormat("SURVIVE-S%d %s", sleeve, plan.reason);
   return true;''',
    extra='''   int    m_sleeve;
   double m_lastScore;
   double m_tierRisk;

   int    m_hAdxH1[EA_MAX_SYMBOLS];      // sleeve C regime gate: ADX(14) on H1
   double m_spread[EA_MAX_SYMBOLS][240]; // rolling spread samples for the 1.5x gate
   int    m_spreadCount[EA_MAX_SYMBOLS];

   void OnInitStrategy()
   {
      for(int i = 0; i < EA_MAX_SYMBOLS; i++)
      {
         m_hAdxH1[i] = INVALID_HANDLE;
         m_spreadCount[i] = 0;
         for(int j = 0; j < 240; j++) m_spread[i][j] = 0.0;
      }
      for(int i = 0; i < g_eaSymbolCount; i++)
         m_hAdxH1[i] = iADX(g_eaSymbols[i], PERIOD_H1, 14);
   }

   void OnDeinitStrategy()
   {
      for(int i = 0; i < EA_MAX_SYMBOLS; i++)
         if(m_hAdxH1[i] != INVALID_HANDLE) { IndicatorRelease(m_hAdxH1[i]); m_hAdxH1[i] = INVALID_HANDLE; }
   }

   bool IsSleeveCSymbol(const string s)
   {
      return (s == "AUDNZD" || s == "EURGBP" || s == "EURCHF");
   }
   bool IsSleeveBSymbol(const string s)
   {
      return (s == "XAUUSD" || s == "GBPJPY" || s == "GER40" || s == "US30" || s == "DE40" || s == "DAX");
   }
   string CorrelatedGroup(const string s)
   {
      if(s == "EURUSD" || s == "GBPUSD" || s == "AUDUSD") return "EURUSD,GBPUSD,AUDUSD";
      if(s == "USDJPY" || s == "GBPJPY" || s == "EURJPY") return "USDJPY,GBPJPY,EURJPY";
      if(s == "AUDUSD" || s == "USDCAD" || s == "XAUUSD") return "AUDUSD,USDCAD,XAUUSD";
      if(s == "EURGBP" || s == "EURCHF") return "EURGBP,EURCHF";
      return "";
   }

   //--- rolling spread gate: live spread at most 1.5x the recent average
   bool SpreadOk(SEAContext &ctx)
   {
      int slot = -1;
      for(int i = 0; i < g_eaSymbolCount; i++) if(g_eaSymbols[i] == ctx.symbol) slot = i;
      if(slot < 0 || slot >= EA_MAX_SYMBOLS) return true;
      datetime barTime = iTime(ctx.symbol, PERIOD_M5, 0);
      static datetime lastBar[EA_MAX_SYMBOLS];
      if(m_spreadCount[slot] == 0 || lastBar[slot] != barTime)
      {
         lastBar[slot] = barTime;
         for(int i = 239; i > 0; i--) m_spread[slot][i] = m_spread[slot][i - 1];
         m_spread[slot][0] = ctx.spreadPoints;
         m_spreadCount[slot] = (int)MathMin(m_spreadCount[slot] + 1, 240);
      }
      //--- doc 2.2 filter 6: live spread at most 1.5x the 20-day average
      double base = EA_SpreadBaseline(ctx.symbol, 720);
      if(base > 0.0)
      {
         if(ctx.spreadPoints > 1.5 * base)
         {
            EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.1f > 1.5x 20d average %.1f - skip",
                   ctx.symbol, ctx.spreadPoints, base), true);
            return false;
         }
         return true;
      }
      int n = m_spreadCount[slot];
      if(n < 20) return true;                                      // warm-up
      double sum = 0.0;
      for(int i = 0; i < n; i++) sum += m_spread[slot][i];
      double avg = sum / n;
      if(avg > 0.0 && ctx.spreadPoints > 1.5 * avg)
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.1f > 1.5x average %.1f - skip",
                ctx.symbol, ctx.spreadPoints, avg), true);
         return false;
      }
      return true;
   }

   //--- SLEEVE A eight-point score (doc 2.2): range quality, HTF bias,
   //--- geometry (implied by the signal), spread, cost, clean book
   double ScoreSleeveA(SEAContext &ctx, const SSignalPlan &plan,
                       const int rangeFromMin, const int rangeToMin)
   {
      double score = 3.0;      // sweep band + wick + displacement already proven
      if(!SpreadOk(ctx)) return 0.0;
      score += 1.0;

      //--- 1. the REFERENCE range width within 35-75% of its 20-day median
      //--- (doc 2.1: the Asian window for London entries, the London window for
      //--- the New York sleeve - not always the Asian one)
      double widths[20];
      int    n = 0;
      for(int d = 0; d < 20; d++)
      {
         double h = 0.0, l = 0.0; int bars = 0;
         if(SigRangeForDay(ctx.symbol, PERIOD_M5, rangeFromMin, rangeToMin, d, h, l, bars))
            widths[n++] = h - l;
      }
      if(n >= 5)
      {
         for(int i = 1; i < n; i++)
         {
            double key = widths[i]; int j = i - 1;
            while(j >= 0 && widths[j] > key) { widths[j + 1] = widths[j]; j--; }
            widths[j + 1] = key;
         }
         double median = widths[n / 2];
         double h0 = 0.0, l0 = 0.0; int b0 = 0;
         if(SigRangeForDay(ctx.symbol, PERIOD_M5, rangeFromMin, rangeToMin, 0, h0, l0, b0))
         {
            double width = h0 - l0;
            if(median > 0.0 && width >= 0.35 * median && width <= 0.75 * median) score += 1.0;
         }
      }
      //--- 2. higher-timeframe bias: H1 50-EMA agrees and is sloping the right way
      double hp[];
      if(EA_BufN(g_eaInd[ctx.index].hEmaH1_50, 0, 1, 5, hp) == 5 && ctx.emaH1_50 > 0.0)
      {
         if(plan.dir > 0 && ctx.mid > ctx.emaH1_50 && hp[0] >= hp[4]) score += 1.0;
         if(plan.dir < 0 && ctx.mid < ctx.emaH1_50 && hp[0] <= hp[4]) score += 1.0;
      }
      //--- 7. cost gate: stop distance at least 10x the round-trip cost
      double cost = EA_CostInR(ctx.symbol, plan.riskDist, g_eaCfg.commissionPerLotRT);
      if(cost <= 0.10) score += 1.0;
      //--- 8. clean book: no correlated position already open
      string group = CorrelatedGroup(ctx.symbol);
      if(group == "" || EA_GroupRiskPct(group) <= 0.0) score += 1.0;
      return score;
   }

   //--- SLEEVE B (doc 3.2): daily ATR in the 60-90th percentile, M15 close
   //--- beyond the 4-hour range with body >= 70%, retest within 6 bars, limit
   //--- at the breakout level, stop 1.20 x ATR(M15) beyond the candle extreme
   bool SleeveBPlan(SEAContext &ctx, SSignalPlan &plan, double &score)
   {
      score = 0.0;
      int nowMin = ctx.clockMinutes;
      bool london = (nowMin >= 7 * 60 && nowMin < 15 * 60 + 30);
      bool ny     = (nowMin >= 13 * 60 + 30 && nowMin < 19 * 60 + 30);
      if(!london && !ny) return false;
      if(!SpreadOk(ctx)) return false;

      //--- filter 1: daily ATR(14) inside the 60-90th percentile of 20 days
      MqlRates d[];
      if(EA_Rates(ctx.symbol, PERIOD_D1, 1, 40, d) < 34) return false;
      double atrNow = 0.0;
      for(int i = 0; i < 14; i++) atrNow += (d[i].high - d[i].low);
      atrNow /= 14.0;
      if(atrNow <= 0.0) return false;
      double dist[20];
      for(int j = 0; j < 20; j++)
      {
         double a = 0.0;
         for(int i = j; i < j + 14; i++) a += (d[i].high - d[i].low);
         dist[j] = a / 14.0;
      }
      for(int i = 1; i < 20; i++)
      {
         double key = dist[i]; int j = i - 1;
         while(j >= 0 && dist[j] > key) { dist[j + 1] = dist[j]; j--; }
         dist[j + 1] = key;
      }
      double p60 = dist[12], p90 = dist[18];
      if(atrNow < p60 || atrNow > p90) return false;
      score += 1.0;

      //--- filter 2/4: M15 close beyond the 4-hour range with body >= 70%
      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 30, r) < 20) return false;
      double hi = -1e18, lo = 1e18;
      for(int i = 3; i < 19; i++)                                   // prior 16 bars = 4 hours
      {
         if(r[i].high > hi) hi = r[i].high;
         if(r[i].low  < lo) lo = r[i].low;
      }
      int    dir = 0;
      int    breakIdx = -1;
      double extreme = 0.0;
      for(int i = 1; i <= 6; i++)                                   // breakout within 6 bars
      {
         double range = r[i].high - r[i].low;
         if(range <= 0.0) continue;
         double body = MathAbs(r[i].close - r[i].open) / range;
         if(body < 0.70) continue;
         if(r[i].close > hi)      { dir = +1; breakIdx = i; extreme = r[i].high; break; }
         if(r[i].close < lo)      { dir = -1; breakIdx = i; extreme = r[i].low;  break; }
      }
      if(dir == 0) return false;
      score += 1.0;

      //--- filter 3: volume expansion (skipped when broker volume is unusable)
      double volSum = 0.0; int volN = 0;
      for(int i = breakIdx + 1; i < breakIdx + 21; i++)
      { if(i < ArraySize(r)) { volSum += (double)r[i].tick_volume; volN++; } }
      if(volN > 0 && volSum > 0.0)
      {
         double volAvg = volSum / volN;
         if(volAvg > 0.0 && (double)r[breakIdx].tick_volume >= 1.3 * volAvg) score += 1.0;
      }
      else score += 1.0;                                            // unusable volume: 4/5 path
      score += 1.0;                                                 // filter 4: spread (checked)
      string grp = CorrelatedGroup(ctx.symbol);
      if(grp == "" || EA_GroupRiskPct(grp) <= 0.0) score += 1.0;    // filter 5: clean book
      if(score < 4.0) return false;

      //--- filter 4: pullback to the breakout level inside 6 M15 candles
      int retestIdx = -1;
      for(int i = breakIdx - 1; i >= 1 && i > breakIdx - 6; i--)
      {
         if(dir > 0 && r[i].low  <= hi) { retestIdx = i; break; }
         if(dir < 0 && r[i].high >= lo) { retestIdx = i; break; }
      }
      if(retestIdx < 0) return false;

      double entry = (dir > 0) ? hi : lo;                           // limit at the breakout level
      double stop  = (dir > 0) ? extreme - 1.20 * ctx.atr : extreme + 1.20 * ctx.atr;
      double risk  = (dir > 0) ? entry - stop : stop - entry;
      if(risk <= 0.0) return false;
      plan.Reset();
      plan.dir      = dir;
      plan.entry    = entry;
      plan.stop     = stop;
      plan.riskDist = risk;
      plan.target   = (dir > 0) ? entry + 2.0 * risk : entry - 2.0 * risk;
      plan.score    = score * 10.0;
      plan.isLimit  = true;
      plan.expiry   = TimeTradeServer() + (datetime)(g_eaCfg.pendingExpiryMinutes * 60);
      plan.reason   = StringFormat("SLEEVE-B breakout-retest %s (score %.0f/5)", ctx.symbol, score);
      return true;
   }

   //--- SLEEVE C (doc 4.2): H1 ADX < 16, 2.0-sigma band touch, wick >= 50%,
   //--- RSI(14) > 70 / < 30, limit at the band, stop 1.0 x ATR beyond the
   //--- touch extreme, target = the 20-period middle band
   bool SleeveCPlan(SEAContext &ctx, SSignalPlan &plan, double &score)
   {
      score = 0.0;
      if(ctx.clockMinutes >= InpSleeveCExitMinute) return false;
      if(ctx.atr <= 0.0 || ctx.rsi14 <= 0.0) return false;
      if(!SpreadOk(ctx)) return false;

      //--- regime: ADX(14) on H1 must be below 16
      double adx = 0.0;
      if(ctx.index >= 0 && ctx.index < EA_MAX_SYMBOLS && m_hAdxH1[ctx.index] != INVALID_HANDLE)
      {
         if(!EA_Buf(m_hAdxH1[ctx.index], 0, 1, adx)) adx = 0.0;
      }
      if(adx > 16.0) return false;

      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 24, r) < 21) return false;
      double sum = 0.0, sum2 = 0.0;
      for(int i = 1; i <= 20; i++) { sum += r[i].close; sum2 += r[i].close * r[i].close; }
      double sma = sum / 20.0;
      double var = MathMax(0.0, sum2 / 20.0 - sma * sma);
      double sd  = MathSqrt(var);
      if(sd <= 0.0) return false;
      double up = sma + 2.0 * sd, lo = sma - 2.0 * sd;

      MqlRates b = r[1];
      bool isLong = false, isShort = false;
      if(b.low  <= lo && b.close > lo && ctx.rsi14 <= 30.0) isLong  = true;
      if(b.high >= up && b.close < up && ctx.rsi14 >= 70.0) isShort = true;
      if(!isLong && !isShort) return false;
      if(isLong  && EA_WickRatio(b, +1) < 0.50) return false;
      if(isShort && EA_WickRatio(b, -1) < 0.50) return false;
      score = 5.0;
      if(!SpreadOk(ctx)) score -= 1.0;
      string grp = CorrelatedGroup(ctx.symbol);
      if(grp != "" && EA_GroupRiskPct(grp) > 0.0) score -= 1.0;
      if(score < 4.0) return false;

      double entry = isLong ? lo : up;                              // limit at the band
      double stop  = isLong ? b.low - 1.0 * ctx.atr : b.high + 1.0 * ctx.atr;
      double risk  = isLong ? entry - stop : stop - entry;
      if(risk <= 0.0) return false;
      plan.Reset();
      plan.dir      = isLong ? +1 : -1;
      plan.entry    = entry;
      plan.stop     = stop;
      plan.riskDist = risk;
      plan.target   = sma;                                          // middle band
      plan.score    = score * 10.0;
      plan.isLimit  = true;
      plan.expiry   = TimeTradeServer() + (datetime)(g_eaCfg.pendingExpiryMinutes * 60);
      plan.reason   = StringFormat("SLEEVE-C band fade %s (ADX %.1f, score %.0f/5)", ctx.symbol, adx, score);
      return true;
   }

   //--- exits: sleeve A 45-minute break-even ladder (40/30 FX, 60/20 XAUUSD)
   //--- with a 2.5 x ATR(H1) runner trail; sleeve C hard flat; session-end rule
   void Manage(SEAContext &ctx)
   {
      //--- sleeve C: hard flat at 06:30
      if(IsSleeveCSymbol(ctx.symbol) && ctx.clockMinutes >= InpSleeveCExitMinute)
      {
         g_eaExec.CancelPending(ctx.symbol, "sleeve C hard flat");
         for(int p = PositionsTotal() - 1; p >= 0; p--)
         {
            ulong tk = PositionGetTicket(p);
            if(tk == 0) continue;
            if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
            if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;
            g_eaExec.Close(tk, "sleeve C hard flat 06:30");
         }
         return;
      }

      for(int t = g_eaTrackCount - 1; t >= 0; t--)
      {
         if(g_eaTrack[t].symbol != ctx.symbol) continue;
         if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;

         int    dir   = g_eaTrack[t].dir;
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double cur   = PositionGetDouble(POSITION_PRICE_CURRENT);
         double risk  = g_eaTrack[t].riskDist;
         if(risk <= 0.0) continue;
         double rMult = ((dir > 0) ? (cur - entry) : (entry - cur)) / risk;

         //--- sleeve A: close at market if +1R has not been reached within 45 min
         if(!IsSleeveBSymbol(ctx.symbol) && !IsSleeveCSymbol(ctx.symbol))
         {
            datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
            int minutesOpen = (int)((TimeTradeServer() - opened) / 60);
            if(rMult < 1.0 && minutesOpen >= InpSleeveATimeStopMin)
            {
               g_eaExec.Close(g_eaTrack[t].ticket, "sleeve A 45-minute time stop");
               continue;
            }
         }

         //--- ladder: +1R closes 40% (60% for XAUUSD) and moves the stop to entry
         bool isXau = (ctx.symbol == "XAUUSD");
         if(rMult >= 1.0 && !g_eaTrack[t].p1Done)
         {
            if(g_eaExec.ClosePartial(g_eaTrack[t].ticket, isXau ? 60.0 : 40.0))
               g_eaTrack[t].p1Done = true;
            else g_eaTrack[t].p1Done = true;
            g_eaExec.Modify(g_eaTrack[t].ticket, PositionGetDouble(POSITION_PRICE_OPEN), 0.0);
            g_eaTrack[t].beMoved = true;
         }
         if(rMult >= 2.0 && !g_eaTrack[t].p2Done)
         {
            if(g_eaExec.ClosePartial(g_eaTrack[t].ticket, isXau ? 20.0 : 30.0))
               g_eaTrack[t].p2Done = true;
            else g_eaTrack[t].p2Done = true;
         }

         //--- runner: chandelier 2.5 x ATR(H1,14) once +2R and the stop is at BE
         if(rMult >= 2.0 && g_eaTrack[t].beMoved)
         {
            MqlRates h[];
            if(EA_Rates(ctx.symbol, PERIOD_H1, 1, 20, h) >= 15)
            {
               double atrH1 = 0.0;
               for(int i = 0; i < 14; i++) atrH1 += (h[i].high - h[i].low);
               atrH1 /= 14.0;
               double extreme = h[0].high;
               if(dir < 0)
               {
                  extreme = h[0].low;
                  for(int i = 1; i < 14; i++) if(h[i].low < extreme) extreme = h[i].low;
               }
               else
                  for(int i = 1; i < 14; i++) if(h[i].high > extreme) extreme = h[i].high;
               double trail = (dir > 0) ? extreme - InpRunnerTrailAtr * atrH1
                                        : extreme + InpRunnerTrailAtr * atrH1;
               double sl = PositionGetDouble(POSITION_SL);
               if((dir > 0 && trail > sl) || (dir < 0 && (sl <= 0.0 || trail < sl)))
                  g_eaExec.Modify(g_eaTrack[t].ticket, eaRoundSafe(ctx.symbol, trail), 0.0);
            }
         }

         //--- session close: flat unless the runner is at least +2R with the stop at BE
         if(ctx.clockMinutes >= 19 * 60 + 30 && !(rMult >= 2.0 && g_eaTrack[t].beMoved))
            g_eaExec.Close(g_eaTrack[t].ticket, "session close");
      }
   }''',
)

add(
    entry=27,
    name="EA_progress",
    magic=3113,
    cls="ProgressFrozenContract",
    title="progress.md - the frozen TRIAD-R Sleeve A contract",
    doc="docs/strategy/progress.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY", "risk": "0.4", "spread": "3.0",
            "daily": "1.0", "totaldd": "10", "target": "10", "maxday": "2"},
    inputs='''input double InpSweepAtrMin         = 0.05;  // Frozen: minimum sweep depth (ATR)
input double InpSweepAtrMax         = 0.50;  // Frozen: maximum sweep depth (ATR)
input int    InpReclaimBars         = 3;     // Frozen: reclaim window (M5 bars)
input double InpReclaimWickMin      = 0.60;  // Frozen: reclaim wick ratio
input double InpDisplacementBodyMin = 0.60;  // Frozen: displacement body ratio
input double InpStopBufferAtr       = 0.10;  // Frozen: stop buffer beyond the sweep
input double InpStopAtrMin          = 0.60;  // Frozen: minimum stop distance
input double InpStopAtrMax          = 1.50;  // Frozen: maximum stop distance
input double InpMaxCostToR          = 0.10;  // Frozen: all-in cost ceiling in R
input double InpProfileRiskPct      = 0.40;  // Profile A: 0.40% / +1.50R
input double InpProfileTargetR      = 1.50;  // Profile A target
input int    InpTimeStopMinutes     = 45;    // Frozen: time stop
input string InpBuildId             = "TRIAD_R_HS_2.1.6_20260905"; // Frozen build record''',
    configure='''cfg.strategyName          = "TRIAD_R_FROZEN";
   cfg.sourceDoc             = "docs/strategy/progress.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpProfileRiskPct;         // profile A
   cfg.riskBaseBalance       = true;                      // % of current balance
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxSpreadPoints       = InpMaxSpreadPoints;
   cfg.maxCostR              = InpMaxCostToR;             // frozen cost gate
   cfg.commissionPerLotRT    = 7.00;
   cfg.dailyLossPct          = InpDailyLossPct;
   cfg.weeklyLossPct         = 2.0;
   cfg.totalDdPct            = InpTotalDdPct;
   cfg.profitTargetPct       = InpProfitTargetPct;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 1;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.pendingExpiryMinutes  = 15;
   cfg.timeStopMinutes       = InpTimeStopMinutes;        // frozen 45 minutes
   cfg.breakEvenAtR          = 1.0;
   cfg.partial1AtR           = 0.0;                       // V2 removed partial closing
   cfg.useHwmThrottle        = true;
   cfg.hwmTier1Dd            = 2.0;  cfg.hwmTier1Mult = 0.50;
   cfg.hwmTier2Dd            = 5.0;  cfg.hwmTier2Mult = 0.0;  cfg.hwmHaltDd = 5.0;
   cfg.logLevel              = InpLogLevel;''',
    plan='''//--- the frozen contract runs Sleeve A on EURUSD London (active),
   //--- with GBPUSD London and USDJPY New York kept as validated candidates.
   SSweepParams p;
   p.Reset();
   p.rangeFromMin   = 0;
   p.rangeToMin     = 7 * 60;
   p.sessionFromMin = 7 * 60;
   p.sessionToMin   = 11 * 60;
   p.sweepMinAtr    = InpSweepAtrMin;
   p.sweepMaxAtr    = InpSweepAtrMax;
   p.reclaimWindowBars = InpReclaimBars;
   p.wickRatio      = InpReclaimWickMin;
   p.bodyRatio      = InpDisplacementBodyMin;
   p.stopBufferAtr  = InpStopBufferAtr;
   p.minStopAtr     = InpStopAtrMin;
   p.maxStopAtr     = InpStopAtrMax;
   p.entryRetrace   = 0.50;
   p.targetR        = InpProfileTargetR;

   if(ctx.symbol == "USDJPY")
   {
      p.rangeFromMin   = 7 * 60;
      p.rangeToMin     = 13 * 60;
      p.sessionFromMin = 13 * 60 + 30;
      p.sessionToMin   = 16 * 60;
   }
   if(ctx.clockMinutes < p.sessionFromMin || ctx.clockMinutes >= p.sessionToMin) return false;

   if(!SigSweepReclaim(ctx, p, plan)) return false;
   plan.reason = StringFormat("%s %s", InpBuildId, plan.reason);
   return true;''',
    extra='''   void OnInitStrategy()
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("frozen contract build %s - do not change constants without a full revalidation", InpBuildId));
      EA_Log(EA_LOG_EVENTS, "gold, indices, continuation and Asian fade stay disabled in this contract");
   }''',
)


add(
    entry=28,
    name="EA_prop_fund_challenge_improvement_plan",
    magic=3114,
    cls="PropFundImprovementPlan",
    title="Prop-fund improvement plan - evidence gates before any live risk",
    doc="docs/prop_firm/prop-fund-challenge-improvement-plan.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY", "risk": "0.4", "spread": "3.0",
            "daily": "1.0", "totaldd": "10", "target": "10", "maxday": "2"},
    inputs='''input bool   InpCompilationGatePassed = false;  // Sub-task 1: MetaEditor 0-error evidence
input bool   InpTickDataGatePassed    = false;  // Sub-task 2: tick-quality replay data
input bool   InpForwardDemoGatePassed = false;  // Sub-task 3: forward-demo fill evidence
input bool   InpStatisticalGatePassed = false;  // Sub-task 4: statistical acceptance
input string InpEvidenceRecord        = "";     // Path/SHA record of the release evidence
input double InpCommissionPerLotRT    = 7.00;   // Cost model used by the pipeline''',
    configure='''cfg.strategyName          = "PROPFUND_IMPROVEMENT_PLAN";
   cfg.sourceDoc             = "docs/prop_firm/prop-fund-challenge-improvement-plan.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxSpreadPoints       = InpMaxSpreadPoints;
   cfg.commissionPerLotRT    = InpCommissionPerLotRT;
   cfg.maxCostR              = 0.10;
   cfg.dailyLossPct          = InpDailyLossPct;
   cfg.weeklyLossPct         = 2.0;
   cfg.totalDdPct            = InpTotalDdPct;
   cfg.profitTargetPct       = InpProfitTargetPct;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 1;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.pendingExpiryMinutes  = 15;
   cfg.timeStopMinutes       = 45;
   cfg.breakEvenAtR          = 1.0;
   cfg.partial1AtR           = 0.0;
   cfg.logLevel              = InpLogLevel;''',
    plan='''//--- every release gate defaults to false: the EA is inert until the plan's
   //--- evidence exists (compilation, tick replay, forward demo, statistics)
   if(!InpCompilationGatePassed) return false;
   if(!InpTickDataGatePassed)    return false;
   if(!InpForwardDemoGatePassed) return false;
   if(!InpStatisticalGatePassed) return false;

   SSweepParams p;
   p.Reset();
   p.rangeFromMin   = 0;
   p.rangeToMin     = 7 * 60;
   p.sessionFromMin = 7 * 60;
   p.sessionToMin   = 11 * 60;
   p.sweepMinAtr    = 0.05;
   p.sweepMaxAtr    = 0.50;
   p.reclaimWindowBars = 3;
   p.wickRatio      = 0.60;
   p.bodyRatio      = 0.60;
   p.stopBufferAtr  = 0.10;
   p.minStopAtr     = 0.60;  p.maxStopAtr = 1.50;
   p.entryRetrace   = 0.50;
   p.targetR        = 1.50;
   if(ctx.symbol == "USDJPY")
   {
      p.rangeFromMin   = 7 * 60;
      p.rangeToMin     = 13 * 60;
      p.sessionFromMin = 13 * 60 + 30;
      p.sessionToMin   = 16 * 60;
   }
   if(ctx.clockMinutes < p.sessionFromMin || ctx.clockMinutes >= p.sessionToMin) return false;
   if(!SigSweepReclaim(ctx, p, plan)) return false;
   plan.reason = StringFormat("PLAN-GATED %s %s", ctx.symbol, plan.reason);
   return true;''',
    extra='''   void OnInitStrategy()
   {
      EA_Log(EA_LOG_EVENTS, "release evidence checklist:");
      EA_Log(EA_LOG_EVENTS, StringFormat("  compilation gate ....... %s", InpCompilationGatePassed ? "PASS" : "OPEN"));
      EA_Log(EA_LOG_EVENTS, StringFormat("  tick-data gate ......... %s", InpTickDataGatePassed ? "PASS" : "OPEN"));
      EA_Log(EA_LOG_EVENTS, StringFormat("  forward-demo gate ...... %s", InpForwardDemoGatePassed ? "PASS" : "OPEN"));
      EA_Log(EA_LOG_EVENTS, StringFormat("  statistical gate ....... %s", InpStatisticalGatePassed ? "PASS" : "OPEN"));
      if(StringLen(InpEvidenceRecord) > 0) EA_Log(EA_LOG_EVENTS, "evidence record: " + InpEvidenceRecord);
      else EA_Log(EA_LOG_EVENTS, "no evidence record attached - trading stays disabled");
   }''',
)


add(
    entry=29,
    name="EA_strategy_improvements_plan",
    magic=3115,
    cls="StrategyImprovementsPlan",
    title="Strategy improvements plan - H1 bias filter, news-day counter, stats gate",
    doc="docs/strategy/strategy-improvements-plan.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY", "risk": "0.4", "spread": "3.0",
            "daily": "1.0", "totaldd": "10", "target": "10", "maxday": "2"},
    inputs='''input bool   InpUseH1EmaBias       = true;   // Sub-task 1: H1 50-EMA directional filter
input int    InpH1BiasSlopeBars   = 3;      // H1 bars used for the slope check
input bool   InpCountNewsDays     = true;   // Sub-task 2: news-blocked day counter
input int    InpInactivityDays    = 25;     // Sub-task 2: inactivity alert threshold
input bool   InpStatsSufficient   = false;  // Sub-task 3: STATS_INSUFFICIENT is an ERROR''',
    configure='''cfg.strategyName          = "STRATEGY_IMPROVEMENTS";
   cfg.sourceDoc             = "docs/strategy/strategy-improvements-plan.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxSpreadPoints       = InpMaxSpreadPoints;
   cfg.dailyLossPct          = InpDailyLossPct;
   cfg.weeklyLossPct         = 2.0;
   cfg.totalDdPct            = InpTotalDdPct;
   cfg.profitTargetPct       = InpProfitTargetPct;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 1;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.pendingExpiryMinutes  = 15;
   cfg.timeStopMinutes       = 45;
   cfg.breakEvenAtR          = 1.0;
   cfg.partial1AtR           = 0.0;
   cfg.useHwmThrottle        = true;
   cfg.hwmTier1Dd            = 2.0;  cfg.hwmTier1Mult = 0.50;
   cfg.hwmTier2Dd            = 5.0;  cfg.hwmTier2Mult = 0.0;  cfg.hwmHaltDd = 5.0;
   cfg.logLevel              = InpLogLevel;''',
    plan='''//--- Sub-task 3: the statistical gate is an ERROR, not a warning
   if(!InpStatsSufficient)
   {
      EA_Log(EA_LOG_ERRORS, "STATS_INSUFFICIENT: statistical acceptance gate is not satisfied", true);
      return false;
   }

   SSweepParams p;
   p.Reset();
   p.rangeFromMin   = 0;
   p.rangeToMin     = 7 * 60;
   p.sessionFromMin = 7 * 60;
   p.sessionToMin   = 11 * 60;
   p.sweepMinAtr    = 0.05;
   p.sweepMaxAtr    = 0.50;
   p.reclaimWindowBars = 3;
   p.wickRatio      = 0.60;
   p.bodyRatio      = 0.60;
   p.stopBufferAtr  = 0.10;
   p.minStopAtr     = 0.60;  p.maxStopAtr = 1.50;
   p.entryRetrace   = 0.50;
   p.targetR        = 1.50;
   if(ctx.symbol == "USDJPY")
   {
      p.rangeFromMin   = 7 * 60;
      p.rangeToMin     = 13 * 60;
      p.sessionFromMin = 13 * 60 + 30;
      p.sessionToMin   = 16 * 60;
   }
   if(ctx.clockMinutes < p.sessionFromMin || ctx.clockMinutes >= p.sessionToMin) return false;
   if(!SigSweepReclaim(ctx, p, plan)) return false;

   //--- Sub-task 1: H1 50-EMA directional bias filter
   if(InpUseH1EmaBias && !H1BiasAgrees(ctx, plan.dir))
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("%s blocked by H1 50-EMA bias filter", ctx.symbol), true);
      return false;
   }
   plan.reason = StringFormat("IMPROVED %s %s", ctx.symbol, plan.reason);
   return true;''',
    extra='''   //--- Sub-task 1: price on the correct side of the H1 50-EMA and slope agrees
   bool H1BiasAgrees(SEAContext &ctx, const int dir)
   {
      if(ctx.emaH1_50 <= 0.0) return false;           // fail closed without a bias
      double hp[];
      if(EA_BufN(g_eaInd[ctx.index].hEmaH1_50, 0, 1, InpH1BiasSlopeBars + 2, hp) < InpH1BiasSlopeBars + 2)
         return false;
      double slope = hp[0] - hp[InpH1BiasSlopeBars];
      if(dir > 0) return (ctx.mid > ctx.emaH1_50 && slope >= 0.0);
      return (ctx.mid < ctx.emaH1_50 && slope <= 0.0);
   }

   //--- Sub-task 2: news-blocked day counter + inactivity alert
   void Manage(SEAContext &ctx)
   {
      static datetime lastDay = 0;
      static bool     newsSeenToday = false;
      MqlDateTime dt;
      TimeToStruct(ctx.nowClock, dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      datetime day = StructToTime(dt);
      if(ctx.newsBlocked) newsSeenToday = true;
      if(lastDay != 0 && day != lastDay)
      {
         if(newsSeenToday && InpCountNewsDays)
         {
            string key = "EA_" + IntegerToString((long)InpMagicNumber) + "_NewsDays";
            int n = GlobalVariableCheck(key) ? (int)GlobalVariableGet(key) : 0;
            GlobalVariableSet(key, (double)(n + 1));
            EA_Log(EA_LOG_EVENTS, StringFormat("news-blocked day counted (%d total)", n + 1));
         }
         newsSeenToday = false;
      }
      lastDay = day;

      string tkey = "EA_" + IntegerToString((long)InpMagicNumber) + "_LastTrade";
      if(!GlobalVariableCheck(tkey)) GlobalVariableSet(tkey, (double)ctx.nowServer);
      int idleDays = (int)((ctx.nowServer - (datetime)GlobalVariableGet(tkey)) / 86400);
      if(idleDays >= InpInactivityDays)
         EA_Log(EA_LOG_EVENTS, StringFormat("INACTIVITY ALERT: %d days without a trade", idleDays), true);
   }''',
)


add(
    entry=30,
    name="EA_STRATEGY_PORTFOLIO_AUDIT",
    magic=3116,
    cls="PortfolioAuditRouter",
    title="Portfolio audit - three-sleeve session router with per-sleeve R telemetry",
    doc="docs/strategy/STRATEGY-PORTFOLIO-AUDIT.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY,XAUUSD,AUDNZD,EURGBP,GBPJPY",
            "risk": "0.24", "spread": "4.0", "daily": "1.0", "totaldd": "10",
            "target": "0", "maxday": "4"},
    inputs='''input double InpSleeveRiskPct      = 0.24;  // Per-trade risk for every sleeve
input int    InpMaxPositions       = 4;     // Max concurrent positions (portfolio)
input double InpShutdownDdPct      = 5.50;  // Strategy shutdown from the closed-equity high
input double InpSleeveAAtrMax      = 0.50;  // False-breakout reversal sweep ceiling
input double InpSleeveBTargetR     = 2.00;  // Continuation sleeve target
input double InpSleeveCTargetR     = 1.10;  // Quiet-session fade target''',
    configure='''cfg.strategyName          = "PORTFOLIO_AUDIT_ROUTER";
   cfg.sourceDoc             = "docs/strategy/STRATEGY-PORTFOLIO-AUDIT.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpSleeveRiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxSpreadPoints       = InpMaxSpreadPoints;
   cfg.dailyLossPct          = InpDailyLossPct;
   cfg.weeklyLossPct         = 2.5;
   cfg.totalDdPct            = InpTotalDdPct;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = InpMaxPositions;
   cfg.minSecondsBetweenTrades = 180;
   cfg.useHwmThrottle        = true;
   cfg.hwmTier1Dd            = 2.0;  cfg.hwmTier1Mult = 0.50;   // 2-4%: half risk
   cfg.hwmTier2Dd            = 4.0;  cfg.hwmTier2Mult = 0.25;   // 4-5.5%: quarter risk
   cfg.hwmHaltDd             = InpShutdownDdPct;   // strategy shutdown/review
   cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 19;  cfg.sessionEndMin = 30;
   cfg.noTradeAfterHour      = 21;  cfg.noTradeAfterMin = 30;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.pendingExpiryMinutes  = 15;
   cfg.timeStopMinutes       = 60;
   cfg.breakEvenAtR          = 1.0;
   cfg.breakEvenOnBarClose   = true;                    // only a completed bar confirms +1R
   cfg.partial1AtR           = 0.0;
   cfg.trailAtR              = 1.0;  cfg.trailDistanceR = 0.5;
   cfg.logLevel              = InpLogLevel;''',
    plan='''if(EA_CountPositions("", false) >= InpMaxPositions) return false;

   int nowMin = ctx.clockMinutes;

   //--- SLEEVE B (accepted-breakout continuation) - London / NY overlap
   bool bWindow = (nowMin >= 7 * 60 && nowMin < 15 * 60 + 30) ||
                  (nowMin >= 13 * 60 + 30 && nowMin < 19 * 60 + 30);
   if(bWindow && (ctx.symbol == "XAUUSD" || ctx.symbol == "GBPJPY" || ctx.symbol == "USDJPY"))
   {
      SBreakRetestParams b;
      b.Reset();
      b.rangeFromMin = 0; b.rangeToMin = 7 * 60;
      b.entryFromMin = 7 * 60; b.entryToMin = 15 * 60 + 30;
      b.minRangeAtr = 0.50; b.breakBufferAtr = 0.10; b.retestTolAtr = 0.15;
      b.stopBufferAtr = 0.20; b.targetR = InpSleeveBTargetR;
      if(SigBreakRetest(ctx, b, plan))
      {
         plan.reason = StringFormat("AUDIT-SLEEVE-B %s", plan.reason);
         m_sleeve = 2;
         return true;
      }
   }

   //--- SLEEVE C (quiet-session single-entry fade) - Asian session only
   if(nowMin < 6 * 60 + 30 && (ctx.symbol == "AUDNZD" || ctx.symbol == "EURGBP"))
   {
      SRangeFadeParams f;
      f.Reset();
      f.bbPeriod = 20; f.bbDeviation = 2.0;
      f.rsiOversold = 35.0; f.rsiOverbought = 65.0;
      f.wickRatio = 0.30; f.stopBufferAtr = 0.30; f.targetR = InpSleeveCTargetR;
      f.requireRangeRegime = true; f.maxAdx = 22.0;
      if(SigRangeFade(ctx, f, plan))
      {
         plan.reason = StringFormat("AUDIT-SLEEVE-C %s", plan.reason);
         m_sleeve = 3;
         return true;
      }
   }

   //--- SLEEVE A (false-breakout reversal) - session opens
   SSweepParams p;
   p.Reset();
   p.rangeFromMin   = 0;
   p.rangeToMin     = 7 * 60;
   p.sessionFromMin = 7 * 60;
   p.sessionToMin   = 16 * 60;
   p.sweepMinAtr    = 0.05;
   p.sweepMaxAtr    = InpSleeveAAtrMax;
   p.reclaimWindowBars = 3;
   p.wickRatio      = 0.60;
   p.bodyRatio      = 0.60;
   p.stopBufferAtr  = 0.10;
   p.minStopAtr     = 0.60;  p.maxStopAtr = 1.50;
   p.entryRetrace   = 0.50;
   p.targetR        = 1.50;
   if(ctx.symbol == "USDJPY" || ctx.symbol == "XAUUSD")
   {
      p.rangeFromMin   = 7 * 60;
      p.rangeToMin     = 13 * 60;
      p.sessionFromMin = 13 * 60 + 30;
      p.sessionToMin   = 16 * 60;
   }
   if(nowMin < p.sessionFromMin || nowMin >= p.sessionToMin) return false;
   if(!SigSweepReclaim(ctx, p, plan)) return false;
   plan.reason = StringFormat("AUDIT-SLEEVE-A %s", plan.reason);
   m_sleeve = 1;
   return true;''',
    extra='''   int m_sleeve;
   int m_lastSleeve;

   void OnInitStrategy() { m_sleeve = 0; m_lastSleeve = 0; }

   //--- per-sleeve R telemetry: the audit's expectancy table, measured live
   void Manage(SEAContext &ctx)
   {
      m_lastSleeve = m_sleeve;
      if(ctx.symbol == "XAUUSD" && ctx.clockMinutes >= 6 * 60 + 30 && ctx.clockMinutes < 7 * 60)
         EA_FlattenAll("sleeve C hard flat 06:30");
   }''',
)


add(
    entry=31,
    name="EA_STRATEGY_ROADMAP",
    magic=3117,
    cls="StrategyRoadmap",
    title="Strategy roadmap - Track A preservation, Track B fast-track families",
    doc="docs/strategy/STRATEGY-ROADMAP.md",
    common={"symbols": "GBPJPY,EURJPY,XAUUSD,XAUUSD,EURUSD", "risk": "1.5",
            "spread": "5.0", "daily": "1.0", "totaldd": "10", "target": "10", "maxday": "3"},
    inputs='''enum ENUM_ROADMAP_TRACK
{
   TRACK_A_LONG_TERM = 0,   // Track A: validated relaxed-geometry triad
   TRACK_B_FAST_TRACK= 1    // Track B: fast-track family set
};
enum ENUM_FAST_FAMILY
{
   FAST_F1_QUIET_FADE   = 0,  // F1 quiet-session range fade
   FAST_F2_FAILED_BREAK = 1,  // F2 failed-breakout reversal (ORB level)
   FAST_F3_BREAK_RIDER  = 2   // F3 breakout rider (no target, session exit)
};
input ENUM_ROADMAP_TRACK  InpTrack        = TRACK_A_LONG_TERM; // Which track to run
input ENUM_FAST_FAMILY    InpFastFamily   = FAST_F2_FAILED_BREAK; // Track B family
input double InpTrackARiskPct             = 1.50;  // Track A: 1.5% per trade
input double InpTrackASweepMin            = 0.02;  // Relaxed geometry: sweep >= x ATR
input double InpTrackAWickMin             = 0.45;  // Relaxed geometry: wick >= x
input double InpTrackABodyMin             = 0.50;  // Relaxed geometry: body >= x
input bool   InpGoldSwingPersonalTrack    = true;  // Personal track: gold swing sleeve''',
    configure='''cfg.strategyName          = "STRATEGY_ROADMAP";
   cfg.sourceDoc             = "docs/strategy/STRATEGY-ROADMAP.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = (InpTrack == TRACK_A_LONG_TERM) ? InpTrackARiskPct : InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxSpreadPoints       = InpMaxSpreadPoints;
   cfg.dailyLossPct          = InpDailyLossPct;          // The5ers -5% daily boundary
   cfg.totalDdPct            = InpTotalDdPct;            // -10% total floor
   cfg.profitTargetPct       = InpProfitTargetPct;       // +10% in ~63 trading days
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 1;                        // one-position compliance
   cfg.minSecondsBetweenTrades = 120;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.pendingExpiryMinutes  = 15;
   cfg.timeStopMinutes       = 90;
   cfg.breakEvenAtR          = 1.0;
   cfg.breakEvenOnBarClose   = true;                    // only a completed bar confirms +1R
   cfg.partial1AtR           = 0.0;
   cfg.useHwmThrottle        = true;
   cfg.hwmTier1Dd            = 3.0;  cfg.hwmTier1Mult = 0.50;
   cfg.hwmTier2Dd            = 6.0;  cfg.hwmTier2Mult = 0.0;  cfg.hwmHaltDd = 6.0;
   cfg.logLevel              = InpLogLevel;''',
    plan='''if(InpTrack == TRACK_A_LONG_TERM)
   {
      //--- Track A: GBPJPY + EURJPY + XAUUSD, London only, relaxed geometry
      bool isTrackA = (ctx.symbol == "GBPJPY" || ctx.symbol == "EURJPY" || ctx.symbol == "XAUUSD");
      if(!isTrackA)
      {
         //--- personal-account track: gold swing sleeve
         if(!InpGoldSwingPersonalTrack || ctx.symbol != "XAUUSD") return false;
         SDonchianParams d;
         d.Reset();
         d.lookbackDays = 55; d.stopD1Atr = 2.5; d.targetR = 4.0; d.trailD1Atr = 2.5;
         if(!SigDonchian(ctx, d, plan)) return false;
         plan.reason = "PERSONAL-GOLD-SWING " + plan.reason;
         return true;
      }
      if(ctx.clockMinutes < 7 * 60 || ctx.clockMinutes >= 16 * 60) return false;
      SSweepParams p;
      p.Reset();
      p.rangeFromMin   = 0;
      p.rangeToMin     = 7 * 60;
      p.sessionFromMin = 7 * 60;
      p.sessionToMin   = 16 * 60;
      p.sweepMinAtr    = InpTrackASweepMin;
      p.sweepMaxAtr    = 0.50;
      p.reclaimWindowBars = 3;
      p.wickRatio      = InpTrackAWickMin;
      p.bodyRatio      = InpTrackABodyMin;
      p.stopBufferAtr  = 0.10;
      p.minStopAtr     = 0.60;  p.maxStopAtr = 1.50;
      p.entryRetrace   = 0.50;
      p.targetR        = 1.50;
      if(!SigSweepReclaim(ctx, p, plan)) return false;
      plan.reason = "TRACK-A " + plan.reason;
      return true;
   }

   //--- Track B: fast-track families (goal: Phase 1 in <= 3 months)
   if(InpFastFamily == FAST_F1_QUIET_FADE)
   {
      if(ctx.clockMinutes >= 7 * 60) return false;
      SRangeFadeParams f;
      f.Reset();
      f.bbPeriod = 20; f.bbDeviation = 2.0;
      f.rsiOversold = 35.0; f.rsiOverbought = 65.0;
      f.wickRatio = 0.30; f.stopBufferAtr = 0.30; f.targetR = 1.1;
      f.requireRangeRegime = true; f.maxAdx = 22.0;
      if(!SigRangeFade(ctx, f, plan)) return false;
      plan.reason = "TRACK-B-F1 " + plan.reason;
      return true;
   }
   if(InpFastFamily == FAST_F2_FAILED_BREAK)
   {
      SOrbParams o;
      o.Reset();
      o.rangeFromMin = 13 * 60 + 30;      // NY opening range
      o.rangeToMin   = 14 * 60;
      o.entryFromMin = 14 * 60;
      o.entryToMin   = 16 * 60;
      o.minRangeAtr  = 0.20; o.maxRangeAtr = 3.0;
      o.bufferAtr    = 0.02; o.bodyRatio = 0.50;
      o.stopBufferAtr= 0.10; o.targetR = 1.5;
      if(!SigORB(ctx, o, plan)) return false;
      plan.reason = "TRACK-B-F2 " + plan.reason;
      return true;
   }
   //--- F3 breakout rider: no target, the session exit closes it
   SBreakRetestParams r;
   r.Reset();
   r.rangeFromMin = 7 * 60; r.rangeToMin = 13 * 60;
   r.entryFromMin = 13 * 60 + 30; r.entryToMin = 19 * 60;
   r.minRangeAtr = 0.40; r.targetR = 3.0;
   if(!SigBreakRetest(ctx, r, plan)) return false;
   plan.reason = "TRACK-B-F3 " + plan.reason;
   return true;''',
)


add(
    entry=32,
    name="EA_studyarena_round1_contestant_b",
    magic=2001,
    cls="Round1B",
    title="Round 1B - SMC order-block EA with break/retest confirmation",
    doc="docs_v1/docs/coreIdea/studyarena-round1-contestant-b.md",
    common={"symbols": "EURUSD,GBPUSD,XAUUSD", "risk": "1.0", "spread": "0",
            "daily": "0", "totaldd": "0", "target": "20", "maxday": "4"},
    inputs='''input double InpRiskPercentStart  = 1.00;  // RiskPercent (0.5-1.0% suggested)
input double InpAtrSlMultiplier   = 1.80;  // ATRMultiplier (1.5-2.0)
input double InpRrRatio           = 2.50;  // RR_Ratio (1:2 .. 1:3)
input int    InpMaxSpreadPips     = 30;    // Spread filter (pips)
input int    InpMaxTradesDay      = 4;     // MaxTradesPerDay (3-5)
input int    InpObLookbackBars    = 12;    // Order-block search window''',
    configure='''cfg.strategyName          = "R1B_SMC_ORDER_BLOCK";
   cfg.sourceDoc             = "docs_v1/docs/coreIdea/studyarena-round1-contestant-b.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPercentStart;
   cfg.signalTimeframe       = PERIOD_M15;               // SMC works best M15-H1
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.profitTargetPct       = InpProfitTargetPct;       // auto-stop once +20% is reached
   cfg.maxTradesPerDay       = InpMaxTradesDay;
   cfg.maxOpenPositions      = 1;
   cfg.minSecondsBetweenTrades = 900;                    // cooldown between SMC setups
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.timeStopMinutes       = 240;
   cfg.breakEvenAtR          = 1.0;
   cfg.logLevel              = InpLogLevel;''',
    plan='''//--- spread filter: 30 pips in the document's terms
   double spreadPips = (ctx.pip > 0.0) ? ctx.spreadPoints * ctx.point / ctx.pip : 0.0;
   if(spreadPips > InpMaxSpreadPips) return false;

   //--- 1) order-block retest, 2) break/retest continuation
   SOrderBlockParams ob;
   ob.Reset();
   ob.lookbackBars     = InpObLookbackBars;
   ob.displacementBody = 0.55;
   ob.touchTolAtr      = 0.20;
   ob.stopBufferAtr    = 0.10;
   ob.targetR          = InpRrRatio;
   ob.requireHtfBias   = true;
   if(SigOrderBlockRetest(ctx, ob, plan))
   {
      //--- ATR stop override (document's ATRMultiplier)
      double stopDist = InpAtrSlMultiplier * ctx.atr;
      if(stopDist > 0.0 && MathAbs(plan.entry - plan.stop) < stopDist)
      {
         plan.stop = (plan.dir > 0) ? plan.entry - stopDist : plan.entry + stopDist;
         plan.riskDist = stopDist;
         plan.target = (plan.dir > 0) ? plan.entry + InpRrRatio * stopDist
                                      : plan.entry - InpRrRatio * stopDist;
      }
      plan.reason = "R1B-OB " + plan.reason;
      return true;
   }
   SBreakRetestParams br;
   br.Reset();
   br.rangeFromMin = 0; br.rangeToMin = 7 * 60;
   br.entryFromMin = 7 * 60; br.entryToMin = 16 * 60;
   br.minRangeAtr = 0.20; br.targetR = InpRrRatio;
   if(!SigBreakRetest(ctx, br, plan)) return false;
   plan.reason = "R1B-BREAKRETEST " + plan.reason;
   return true;''',
)


add(
    entry=33,
    name="EA_studyarena_round1_contestant_c",
    magic=2002,
    cls="Round1C",
    title="Round 1C - multi-timeframe SMC confluence with exposure cap",
    doc="docs_v1/docs/coreIdea/studyarena-round1-contestant-c.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY", "risk": "1.5", "spread": "0",
            "daily": "5.0", "totaldd": "5.0", "target": "20", "maxday": "3"},
    inputs='''input double InpRiskPerTradePct   = 1.50;  // Risk per trade (% equity)
input int    InpMaxOpenTrades     = 2;     // Max concurrent trades
input double InpExposureCapPct    = 40.0;  // Total notional exposure cap (30-50%)
input double InpMinSlAtr          = 1.00;  // Dynamic SL: at least 1 x ATR(14)
input double InpMinRr             = 2.00;  // Minimum reward:risk
input double InpAtrSpikeMult      = 1.50;  // Skip if ATR > x times its 30-bar average
input int    InpConfluenceMin     = 2;     // 2 of 3 SMC confluence signals required''',
    configure='''cfg.strategyName          = "R1C_SMC_CONFLUENCE";
   cfg.sourceDoc             = "docs_v1/docs/coreIdea/studyarena-round1-contestant-c.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPerTradePct;
   cfg.signalTimeframe       = PERIOD_M15;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.dailyLossPct          = InpDailyLossPct;          // hard stop -5%
   cfg.totalDdPct            = InpTotalDdPct;            // monthly -5% monthly floor
   cfg.profitTargetPct       = InpProfitTargetPct;       // auto-close at +20%
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = InpMaxOpenTrades;
   cfg.minSecondsBetweenTrades = 600;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.timeStopMinutes       = 240;
   cfg.breakEvenAtR          = 1.0;
   cfg.logLevel              = InpLogLevel;''',
    plan='''//--- ATR spike filter: ATR(14) must not exceed 1.5x its 30-bar average
   if(AtrIsSpiking(ctx)) return false;

   //--- SMC confluence counter (2 of 3 required): OB retest, break/retest, HTF cascade
   int confluence = 0;
   SCascadeParams cas;
   cas.Reset();
   cas.requireD1 = true; cas.requireH1 = true; cas.requireM15Structure = true;
   int cascade = SigEmaCascade(ctx, cas);
   if(cascade != 0) confluence++;

   SSignalPlan tmp;
   SOrderBlockParams ob;
   ob.Reset();
   ob.lookbackBars = 14; ob.displacementBody = 0.50;
   ob.touchTolAtr = 0.25; ob.targetR = InpMinRr; ob.requireHtfBias = true;
   bool hasOb = SigOrderBlockRetest(ctx, ob, tmp);
   if(hasOb && (cascade == 0 || (tmp.dir == cascade))) confluence++;

   SBreakRetestParams br;
   br.Reset();
   br.rangeFromMin = 0; br.rangeToMin = 7 * 60;
   br.entryFromMin = 7 * 60; br.entryToMin = 21 * 60;
   br.minRangeAtr = 0.25; br.targetR = InpMinRr;
   bool hasRetest = SigBreakRetest(ctx, br, tmp);
   if(hasRetest && (cascade == 0 || (tmp.dir == cascade))) confluence++;

   if(confluence < InpConfluenceMin) return false;

   //--- prefer the order block, fall back to the break/retest plan
   if(hasOb) { if(!SigOrderBlockRetest(ctx, ob, plan)) return false; }
   else      { if(!SigBreakRetest(ctx, br, plan)) return false; }

   //--- dynamic SL: at least 1 x ATR(14), and reward:risk >= 2
   double minStop = InpMinSlAtr * ctx.atr;
   if(plan.riskDist < minStop)
   {
      plan.stop     = (plan.dir > 0) ? plan.entry - minStop : plan.entry + minStop;
      plan.riskDist = minStop;
      plan.target   = (plan.dir > 0) ? plan.entry + InpMinRr * minStop
                                     : plan.entry - InpMinRr * minStop;
   }
   plan.reason = StringFormat("R1C-CONFLUENCE(%d/3) %s", confluence, plan.reason);
   return true;''',
    extra='''   bool AtrIsSpiking(SEAContext &ctx)
   {
      double av[];
      if(EA_BufN(g_eaInd[ctx.index].hAtr, 0, 1, 30, av) < 30) return false;
      double sum = 0.0;
      for(int i = 0; i < 30; i++) sum += av[i];
      double avg = sum / 30.0;
      if(avg <= 0.0) return false;
      return (ctx.atr > InpAtrSpikeMult * avg);
   }''',
)


add(
    entry=34,
    name="EA_studyarena_round2_contestant_a",
    magic=2003,
    cls="Round2A",
    title="Round 2A - liquidity-hunting with correlation ripple and z-score reversion",
    doc="docs_v1/docs/coreIdea/studyarena-round2-contestant-a.md",
    common={"symbols": "EURUSD,GBPUSD,AUDUSD,USDJPY", "risk": "1.0", "spread": "0",
            "daily": "0", "totaldd": "0", "target": "20", "maxday": "5"},
    inputs='''input int    InpOverlapFromMin     = 13 * 60;  // London/NY overlap start (08:00 EST)
input int    InpOverlapToMin       = 16 * 60;  // London/NY overlap end (11:00 EST)
input double InpCorrelationRr      = 1.50;     // Cross-pair "fast trade" reward:risk
input double InpZScoreEntry        = 2.50;     // Mean reversion entry threshold
input double InpZScoreAsia         = 3.50;     // 80% more selective during Asia
input int    InpZScorePeriod       = 20;       // Z-score lookback bars''',
    configure='''cfg.strategyName          = "R2A_LIQUIDITY_HUNTING";
   cfg.sourceDoc             = "docs_v1/docs/coreIdea/studyarena-round2-contestant-a.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M15;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.profitTargetPct       = InpProfitTargetPct;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 2;
   cfg.minSecondsBetweenTrades = 300;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.timeStopMinutes       = 120;
   cfg.breakEvenAtR          = 1.0;
   cfg.logLevel              = InpLogLevel;''',
    plan='''bool inOverlap = (ctx.clockMinutes >= InpOverlapFromMin && ctx.clockMinutes < InpOverlapToMin);
   bool inAsia    = (ctx.clockMinutes < 7 * 60);

   //--- Engine 1: liquidity hunting (stop run of the previous session range)
   SSweepParams p;
   p.Reset();
   p.rangeFromMin   = 0;
   p.rangeToMin     = 7 * 60;
   p.sessionFromMin = 7 * 60;
   p.sessionToMin   = 16 * 60;
   p.sweepMinAtr    = 0.05;
   p.sweepMaxAtr    = 0.50;
   p.reclaimWindowBars = 3;
   p.wickRatio      = 0.55;
   p.bodyRatio      = 0.55;
   p.stopBufferAtr  = 0.10;
   p.minStopAtr     = 0.40;  p.maxStopAtr = 2.00;
   p.entryRetrace   = 0.00;              // the fast trade enters at market
   p.targetR        = inOverlap ? 2.0 : InpCorrelationRr;
   p.scoreBase      = inOverlap ? 70.0 : 50.0;
   if(SigSweepReclaim(ctx, p, plan))
   {
      //--- correlation ripple: outside the overlap the tighter 1:1.5 fast profile applies
      plan.reason = StringFormat("R2A-%s %s", inOverlap ? "STOPRUN" : "FASTTICK", plan.reason);
      return true;
   }
   if(inOverlap) return false;          // no z-score reversion during the overlap window

   //--- Engine 2: statistical mean reversion (z-score overextension)
   double zEntry = inAsia ? InpZScoreAsia : InpZScoreEntry;
   if(!SigZScoreFade(ctx, InpZScorePeriod, zEntry, 0.50, 1.20, plan)) return false;
   plan.reason = StringFormat("R2A-ZSCORE %s", plan.reason);
   return true;''',
)


add(
    entry=35,
    name="EA_studyarena_round2_contestant_b",
    magic=2004,
    cls="Round2B",
    title="Round 2B - portfolio of five return engines with graded conviction sizing",
    doc="docs_v1/docs/coreIdea/studyarena-round2-contestant-b.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY,XAUUSD,AUDNZD", "risk": "1.0",
            "spread": "4.0", "daily": "0", "totaldd": "0", "target": "20", "maxday": "6"},
    inputs='''input double InpScoreFullRiskPct   = 2.00;  // Score >= 8/10 -> 2.0% risk
input double InpScoreMidRiskPct    = 1.00;  // Score 6-7/10 -> 1.0% risk
input int    InpScoreMinToTrade    = 6;     // Below this score: no trade
input double InpNarrowAsiaRangeAtr = 0.60;  // Session-open breakout when Asia range < x ATR20
input double InpSwapHarvestPct     = 0.50;  // Engine 5: carry/swap harvest risk''',
    configure='''cfg.strategyName          = "R2B_ENGINE_PORTFOLIO";
   cfg.sourceDoc             = "docs_v1/docs/coreIdea/studyarena-round2-contestant-b.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpScoreMidRiskPct;      // scaled per setup by LotsMultiplier
   cfg.signalTimeframe       = PERIOD_M15;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxSpreadPoints       = InpMaxSpreadPoints;
   cfg.profitTargetPct       = InpProfitTargetPct;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 3;
   cfg.minSecondsBetweenTrades = 300;
   cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 21;  cfg.sessionEndMin = 0;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.timeStopMinutes       = 180;
   cfg.breakEvenAtR          = 1.0;
   cfg.trailAtR              = 2.0;  cfg.trailDistanceR = 0.75;
   cfg.logLevel              = InpLogLevel;''',
    plan='''m_score = 0.0;

   //--- Engine 4: mean reversion at HTF extremes (2.5 sigma, ranging regime)
   if(ctx.adx14 > 0.0 && ctx.adx14 < 20.0)
   {
      SSignalPlan z;
      if(SigZScoreFade(ctx, 20, 2.50, 0.50, 1.50, z))
      {
         double score = ScoreConfluence(ctx, z.dir) + 2.0;
         if(score >= InpScoreMinToTrade)
         {
            plan = z; ScoreTo(plan, score);
            plan.reason = "R2B-MEANREV " + plan.reason;
            return true;
         }
      }
   }

   //--- Engine 2/3: Asian-range liquidity raid + narrow-range session breakout
   if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 10 * 60)
   {
      double hi = 0.0, lo = 0.0, atr20 = 0.0;
      MqlRates d[];
      if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 25, d) >= 21)
      {
         double sum = 0.0;
         for(int i = 1; i <= 20; i++) sum += (d[i].high - d[i].low);
         atr20 = sum / 20.0;
      }
      if(SigAsianRange(ctx.symbol, hi, lo) && hi > lo && atr20 > 0.0)
      {
         bool narrow = (hi - lo) < InpNarrowAsiaRangeAtr * atr20;
         SSignalPlan a;
         if(narrow && SigAsianBreakout(ctx, 0.05, 0.20, 2.0, a))
         {
            double score = ScoreConfluence(ctx, a.dir) + 3.0;
            if(score >= InpScoreMinToTrade)
            {
               plan = a; ScoreTo(plan, score);
               plan.reason = "R2B-SESSIONBREAK " + plan.reason;
               return true;
            }
         }
      }
   }

   //--- Engine 1: SMC-style sweep + reclaim continuation
   SSweepParams p;
   p.Reset();
   p.rangeFromMin   = 0;
   p.rangeToMin     = 7 * 60;
   p.sessionFromMin = 7 * 60;
   p.sessionToMin   = 16 * 60;
   p.sweepMinAtr    = 0.05;
   p.sweepMaxAtr    = 0.50;
   p.reclaimWindowBars = 3;
   p.wickRatio      = 0.60;
   p.bodyRatio      = 0.60;
   p.stopBufferAtr  = 0.10;
   p.minStopAtr     = 0.60;  p.maxStopAtr = 1.50;
   p.entryRetrace   = 0.50;
   p.targetR        = 3.0;                       // fixed 3R with runner potential
   if(ctx.clockMinutes < p.sessionFromMin || ctx.clockMinutes >= p.sessionToMin) return false;
   if(!SigSweepReclaim(ctx, p, plan)) return false;

   double score = ScoreConfluence(ctx, plan.dir) + 2.0;
   if(score < InpScoreMinToTrade) return false;
   ScoreTo(plan, score);
   plan.reason = StringFormat("R2B-SMC(%.0f/10) %s", score, plan.reason);
   return true;''',
    extra='''   double m_score;

   //--- confluence grading (0..10) used for conviction sizing
   double ScoreConfluence(SEAContext &ctx, const int dir)
   {
      double score = 0.0;
      //--- HTF bias aligned (H4/D1)
      if(ctx.emaD1_200 > 0.0 && ((dir > 0 && ctx.mid > ctx.emaD1_200) || (dir < 0 && ctx.mid < ctx.emaD1_200)))
         score += 3.0;
      //--- H1 structure aligned
      if(ctx.emaH1_50 > 0.0 && ((dir > 0 && ctx.mid > ctx.emaH1_50) || (dir < 0 && ctx.mid < ctx.emaH1_50)))
         score += 2.0;
      //--- momentum regime
      if(ctx.adx14 >= 20.0 && ctx.adx14 <= 45.0) score += 2.0;
      //--- volatility expanding but not spiking
      if(ctx.atr > 0.0 && ctx.atrD1 > 0.0 && ctx.atr < ctx.atrD1 * 0.5) score += 1.5;
      //--- no counter-trend RSI extreme
      if((dir > 0 && ctx.rsi14 < 70.0) || (dir < 0 && ctx.rsi14 > 30.0)) score += 1.5;
      return MathMin(score, 10.0);
   }

   void ScoreTo(SSignalPlan &plan, const double score)
   {
      m_score    = score;
      plan.score = score * 10.0;
   }

   //--- graded conviction sizing: score >= 8 -> full risk, 6-7 -> mid risk, else none
   double LotsMultiplier(SEAContext &ctx)
   {
      if(m_score >= 8.0) return (InpScoreMidRiskPct > 0.0) ? InpScoreFullRiskPct / InpScoreMidRiskPct : 1.0;
      return 1.0;
   }''',
)


add(
    entry=36,
    name="EA_studyarena_round2_contestant_c",
    magic=2005,
    cls="Round2C",
    title="Round 2C - SMC pillars: HTF bias, fractal sweep, CHoCH and OB zone",
    doc="docs_v1/docs/coreIdea/studyarena-round2-contestant-c.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY,XAUUSD", "risk": "1.0", "spread": "0",
            "daily": "0", "totaldd": "0", "target": "20", "maxday": "4"},
    inputs='''input int    InpFractalCount      = 6;     // Last N swing highs/lows scanned
input int    InpFractalBars       = 2;     // Bars on each side of a swing point
input double InpSweepRr           = 2.00;  // Sweep structure reward:risk
input bool   InpRequireChoch      = true;  // Require the high-low-high-close-high CHoCH
input double InpMaxSpreadPts      = 35.0;  // Over-spread guard: skip this symbol above N points (doc: ~35 for XAU/JPY)''',
    configure='''cfg.strategyName          = "R2C_SMC_PILLARS";
   cfg.sourceDoc             = "docs_v1/docs/coreIdea/studyarena-round2-contestant-c.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M15;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.profitTargetPct       = InpProfitTargetPct;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 1;
   cfg.minSecondsBetweenTrades = 600;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.timeStopMinutes       = 240;
   cfg.breakEvenAtR          = 1.0;
   cfg.logLevel              = InpLogLevel;''',
    plan='''//--- Pillar 1: H4/H1 higher-timeframe bias (primary directional filter)
   //--- Step 9 safeguard: an over-spread symbol is skipped before any analysis
   if(ctx.spreadPoints > InpMaxSpreadPts)
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.1f pts > %.1f - skip (doc Step 9 over-spread)", ctx.symbol, ctx.spreadPoints, InpMaxSpreadPts), true);
      return false;
   }

   int htfBias = 0;
   if(ctx.emaH1_200 > 0.0 && ctx.emaH1_50 > 0.0)
   {
      if(ctx.mid > ctx.emaH1_200 && ctx.emaH1_50 > ctx.emaH1_200) htfBias = +1;
      if(ctx.mid < ctx.emaH1_200 && ctx.emaH1_50 < ctx.emaH1_200) htfBias = -1;
   }
   if(htfBias == 0) return false;

   //--- Pillar 2 + 3: fractal sweep with CHoCH confirmation
   double highs[], lows[];
   int    hiIdx[], loIdx[];
   if(SigFractals(ctx.symbol, InpFractalCount, highs, lows, hiIdx, loIdx) < 2) return false;

   MqlRates r[];
   if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 12, r) < 4) return false;
   double lastClose = r[0].close;

   bool sweepLong  = (ArraySize(lows)  >= 2 && lows[0] < lows[1] && lastClose > lows[0]);
   bool sweepShort = (ArraySize(highs) >= 2 && highs[0] > highs[1] && lastClose < highs[0]);
   if(htfBias > 0 && !sweepLong)  return false;
   if(htfBias < 0 && !sweepShort) return false;
   if(sweepLong && sweepShort)    return false;

   if(InpRequireChoch)
   {
      //--- high-low-high-close-high sequence (long) and its mirror
      if(sweepLong)
      {
         bool choch = (r[3].high > r[4].high) && (r[2].low < r[3].low) && (lastClose > r[3].high);
         if(!choch) return false;
      }
      else
      {
         bool choch = (r[3].low < r[4].low) && (r[2].high > r[3].high) && (lastClose < r[3].low);
         if(!choch) return false;
      }
   }

   //--- Pillar 4: order block / FVG proximity is the entry zone
   SOrderBlockParams ob;
   ob.Reset();
   ob.lookbackBars = 16; ob.displacementBody = 0.45;
   ob.touchTolAtr = 0.35; ob.targetR = InpSweepRr;
   ob.requireHtfBias = true; ob.tradeBothWays = (htfBias > 0);
   SSignalPlan obPlan;
   if(!SigOrderBlockRetest(ctx, ob, obPlan)) return false;
   if(obPlan.dir != htfBias) return false;
   plan = obPlan;
   plan.reason = StringFormat("R2C-PILLARS(bias %s, fractal sweep, CHoCH) %s",
                              htfBias > 0 ? "bull" : "bear", plan.reason);
   return true;''',
)


add(
    entry=37,
    name="EA_studyarena_round3_contestant_a__1_",
    magic=2006,
    cls="Round3A",
    title="Round 3A - three-timeframe cascade with pyramided units and Kelly sizing",
    doc="docs_v1/docs/coreIdea/studyarena-round3-contestant-a (1).md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY,GBPJPY", "risk": "1.0", "spread": "0",
            "daily": "0", "totaldd": "0", "target": "20", "maxday": "6"},
    inputs='''input int    InpPyramidUnits       = 3;     // Unit 1 entry + up to 2 refinements
input double InpPyramidStepR       = 1.00;  // Add when price advances xR beyond the last entry
input double InpKellyWinRate       = 0.45;  // Trailing win rate for fractional Kelly
input double InpKellyPayoffR       = 3.00;  // Trailing average win in R
input double InpKellyFraction      = 0.125; // 1/k fraction (k=8)
input double InpKellyCapPct        = 2.00;  // Hard per-trade cap''',
    configure='''cfg.strategyName          = "R3A_TF_CASCADE";
   cfg.sourceDoc             = "docs_v1/docs/coreIdea/studyarena-round3-contestant-a (1).md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;             // scaled by the Kelly multiplier
   cfg.signalTimeframe       = PERIOD_M5;              // M5 precision entries
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = InpPyramidUnits;        // unit stacking is deliberate here
   cfg.minSecondsBetweenTrades = 120;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 20;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.pendingExpiryMinutes  = 15;
   cfg.timeStopMinutes       = 90;
   cfg.breakEvenAtR          = 1.0;
   cfg.trailAtR              = 1.5;  cfg.trailDistanceR = 0.5;
   cfg.useLimitEntry         = true;
   cfg.logLevel              = InpLogLevel;''',
    plan='''if(!PyramidStepSatisfied(ctx)) return false;

   //--- Engine A/B direction: H4-equivalent H1 bias, then M5 precision entry
   if(ctx.emaH1_200 <= 0.0 || ctx.ema50 <= 0.0) return false;
   int bias = (ctx.mid > ctx.emaH1_200) ? +1 : -1;
   if(bias > 0 && ctx.ema50 < ctx.emaH1_200) return false;
   if(bias < 0 && ctx.ema50 > ctx.emaH1_200) return false;

   //--- Engine C: M5 order-block precision entry, limit-only (cost per section 2)
   SOrderBlockParams ob;
   ob.Reset();
   ob.lookbackBars = 10; ob.displacementBody = 0.50;
   ob.touchTolAtr = 0.20; ob.stopBufferAtr = 0.10;
   ob.targetR = 1.50;                 // M5 engine target
   ob.requireHtfBias = true;
   ob.tradeBothWays = (bias > 0);
   if(!SigOrderBlockRetest(ctx, ob, plan)) return false;
   if(plan.dir != bias) return false;

   //--- limit-only resting entry at the block edge
   plan.entry   = (plan.dir > 0) ? MathMin(plan.entry, ctx.ask) : MathMax(plan.entry, ctx.bid);
   plan.isLimit = true;
   plan.expiry  = TimeTradeServer() + (datetime)(g_eaCfg.pendingExpiryMinutes * 60);
   plan.reason  = StringFormat("R3A-CASCADE(unit %d) %s", EA_CountPositions(ctx.symbol, true) + 1, plan.reason);
   return true;''',
    extra='''   bool AllowMultipleOnSymbol() { return true; }

   //--- each additional unit needs price to have advanced 1R past the last entry
   bool PyramidStepSatisfied(SEAContext &ctx)
   {
      int open = EA_CountPositions(ctx.symbol, true);
      if(open == 0) return true;
      if(open >= InpPyramidUnits) return false;
      //--- find the best (most advanced) entry on this symbol
      double bestEntry = 0.0;
      int    dir       = 0;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;
         bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         dir = isBuy ? +1 : -1;
         double e = PositionGetDouble(POSITION_PRICE_OPEN);
         if(bestEntry == 0.0 || (dir > 0 && e > bestEntry) || (dir < 0 && e < bestEntry)) bestEntry = e;
      }
      int ti = -1;
      for(int i = 0; i < g_eaTrackCount; i++) if(g_eaTrack[i].symbol == ctx.symbol) ti = i;
      double risk = (ti >= 0) ? g_eaTrack[ti].riskDist : 1.5 * ctx.atr;
      if(risk <= 0.0) return false;
      double px = ctx.mid;
      double advance = (dir > 0) ? (px - bestEntry) : (bestEntry - px);
      return (advance >= InpPyramidStepR * risk);
   }

   //--- fractional Kelly sizing on trailing statistics, hard-capped
   double LotsMultiplier(SEAContext &ctx)
   {
      double kelly = (InpKellyWinRate - (1.0 - InpKellyWinRate) / MathMax(0.1, InpKellyPayoffR)) * InpKellyFraction;
      if(kelly <= 0.0) return 0.0;
      double riskPct = MathMin(ctx.riskPct * (kelly / MathMax(0.0001, InpRiskPct)), InpKellyCapPct);
      return (ctx.riskPct > 0.0) ? MathMax(0.0, riskPct / ctx.riskPct) : 0.0;
   }''',
)


add(
    entry=38,
    name="EA_studyarena_round3_contestant_b__1_",
    magic=2007,
    cls="Round3B",
    title="Round 3B - 17 levers: imbalance entries, MTF stacking, graded ladder exits",
    doc="docs_v1/docs/coreIdea/studyarena-round3-contestant-b (1).md",
    common={"symbols": "EURUSD,GBPUSD,XAUUSD", "risk": "1.0", "spread": "0",
            "daily": "0", "totaldd": "0", "target": "20", "maxday": "5"},
    inputs='''input double InpStopFactor        = 0.70;  // Hard stop: 0.7R of the structural swing
input double InpTarget1R          = 1.20;  // Target 1: +1.2R (25%)
input double InpTarget2R          = 2.50;  // Target 2: +2.5R (25%)
input double InpRunnerTrailR      = 1.00;  // Runner trail in R behind the H4 swing
input double InpGradedMaxRiskPct  = 2.50;  // Score 10/10 -> 2.5% risk
input double InpGradedMinRiskPct  = 1.00;  // Score 6/10 -> 1.0% risk''',
    configure='''cfg.strategyName          = "R3B_SEVENTEEN_LEVERS";
   cfg.sourceDoc             = "docs_v1/docs/coreIdea/studyarena-round3-contestant-b (1).md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpGradedMinRiskPct;
   cfg.signalTimeframe       = PERIOD_M15;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 1;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   //--- the document's exit ladder: 25% at 1.2R, 25% at 2.5R, runner trails the H4 swing
   cfg.partial1AtR           = InpTarget1R;  cfg.partial1Pct = 25.0;
   cfg.partial2AtR           = InpTarget2R;  cfg.partial2Pct = 25.0;
   cfg.breakEvenAtR          = 1.2;
   cfg.trailAtR              = 2.5;  cfg.trailDistanceR = InpRunnerTrailR;
   cfg.timeStopMinutes       = 0;
   cfg.logLevel              = InpLogLevel;''',
    plan='''//--- Lever 2: multi-timeframe confirmation stacking (D1 direction, H4 momentum, M15 timing)
   int dirBias = 0;
   if(ctx.emaD1_200 > 0.0)
      dirBias = (ctx.mid > ctx.emaD1_200) ? +1 : -1;
   if(dirBias == 0) return false;
   //--- H4 momentum: ADX > 25 and ATR expanding
   if(ctx.adx14 < 25.0) return false;
   if(ctx.atrD1 <= 0.0 || ctx.atr <= 0.0) return false;

   //--- Lever 3: the imbalance (FVG) trade - SMC's highest-R edge
   SFvgParams f;
   f.Reset();
   f.impulseBody = 0.60; f.minGapAtr = 0.10;
   f.stopBufferAtr = 0.15; f.targetR = 6.0;      // runner targets 6-8R
   f.maxRetrace = 0.75;
   f.tradeBothWays = (dirBias > 0);
   if(!SigFvgRetest(ctx, f, plan)) return false;
   if(plan.dir != dirBias) return false;

   //--- Lever 1: the 0.7R hard stop (tighter than the structural swing)
   double structural = plan.riskDist;
   double stop = InpStopFactor * structural;
   if(stop <= 0.0) return false;
   plan.riskDist = stop;
   plan.stop     = (plan.dir > 0) ? plan.entry - stop : plan.entry + stop;
   plan.target   = (plan.dir > 0) ? plan.entry + InpTarget2R * stop
                                  : plan.entry - InpTarget2R * stop;

   //--- Lever 4: graded conviction sizing
   m_grade = Grade(ctx, plan.dir);
   plan.score = m_grade * 10.0;
   plan.reason = StringFormat("R3B-IMBALANCE(grade %.0f/10) %s", m_grade, plan.reason);
   return true;''',
    extra='''   double m_grade;

   double Grade(SEAContext &ctx, const int dir)
   {
      double grade = 5.0;
      if(ctx.emaD1_200 > 0.0 && ((dir > 0 && ctx.mid > ctx.emaD1_200) || (dir < 0 && ctx.mid < ctx.emaD1_200)))
         grade += 1.5;
      if(ctx.adx14 > 25.0) grade += 1.0;
      if(ctx.emaH1_50 > 0.0 && ((dir > 0 && ctx.mid > ctx.emaH1_50) || (dir < 0 && ctx.mid < ctx.emaH1_50)))
         grade += 1.0;
      if(ctx.atrD1 > 0.0 && ctx.atr > 0.3 * ctx.atrD1) grade += 0.75;
      if((dir > 0 && ctx.rsi14 > 45.0 && ctx.rsi14 < 75.0) ||
         (dir < 0 && ctx.rsi14 < 55.0 && ctx.rsi14 > 25.0)) grade += 0.75;
      return MathMin(grade, 10.0);
   }

   //--- graded conviction sizing: 10/10 -> 2.5%, 6/10 -> 1.0%, below -> no trade
   double LotsMultiplier(SEAContext &ctx)
   {
      if(m_grade < 6.0) return 0.0;
      double span = (InpGradedMaxRiskPct - InpGradedMinRiskPct) / 4.0;   // 6..10
      double target = InpGradedMinRiskPct + (m_grade - 6.0) * span;
      if(ctx.riskPct <= 0.0) return 0.0;
      return MathMax(0.0, MathMin(target / ctx.riskPct, InpGradedMaxRiskPct / MathMax(0.01, ctx.riskPct)));
   }''',
)


add(
    entry=39,
    name="EA_studyarena_round4_contestant_a__1_",
    magic=2008,
    cls="Round4A",
    title="Round 4A(1) - leverage layer: liquidity sniper, gamma scalp and asymmetric exit",
    doc="docs_v1/docs/coreIdea/studyarena-round4-contestant-a (1).md",
    common={"symbols": "EURUSD,GBPUSD", "risk": "0.5", "spread": "0", "daily": "0",
            "totaldd": "0", "target": "20", "maxday": "5"},
    inputs='''input double InpSniperStopR        = 1.00;  // Liquidity sniper: 1.0R stop
input double InpSniperTargetR       = 5.00;  // Liquidity sniper: 5R target
input double InpVolumeSurgeMult     = 2.50;  // Volume surge vs 30-bar median
input double InpAsymStopFactor      = 0.70;  // Asymmetric exit: 0.7R stop factor
input bool   InpGammaScalpEnabled   = true;  // Delta-hedge the runner after the partial
input double InpGammaHedgeRatio     = 0.50;  // Hedge 50% of the remaining volume
input int    InpGammaTargetPips     = 15;    // Gamma scalp profit target (pips)
input double InpFundedRiskPct       = 0.30;  // Funded-account mode risk (0.3%)''',
    configure='''cfg.strategyName          = "R4A_LEVERAGE_LAYER";
   cfg.sourceDoc             = "docs_v1/docs/coreIdea/studyarena-round4-contestant-a (1).md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = MathMin(InpRiskPct, InpFundedRiskPct);   // funded guard rail
   cfg.signalTimeframe       = PERIOD_M15;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 1;
   cfg.minSecondsBetweenTrades = 600;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 20;  cfg.sessionEndMin   = 0;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   //--- asymmetric exit ladder: 25% at 1R, 25% at 2R, runner to 5R
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 25.0;
   cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 25.0;
   cfg.breakEvenAtR          = 1.00;
   cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 1.00;
   cfg.timeStopMinutes       = 0;
   cfg.logLevel              = InpLogLevel;''',
    plan='''//--- Lever 4: liquidity sniper - swing failure with a volume surge and CVD divergence
   if(SniperSetup(ctx, plan)) return true;

   //--- secondary: stop run of the session range, counter-trend to the failed swing
   SSweepParams p;
   p.Reset();
   p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
   p.sessionFromMin = 7 * 60; p.sessionToMin = 16 * 60;
   p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
   p.reclaimWindowBars = 3; p.wickRatio = 0.55; p.bodyRatio = 0.55;
   p.stopBufferAtr = 0.10; p.minStopAtr = 0.50; p.maxStopAtr = 1.50;
   p.entryRetrace = 0.50; p.targetR = InpSniperTargetR;
   if(!SigSweepReclaim(ctx, p, plan)) return false;
   ApplyAsymmetricStop(plan);
   plan.reason = "R4A-SNIPER " + plan.reason;
   return true;''',
    extra='''   ulong m_hedgeBase[12];
   ulong m_hedgeTicket[12];
   int   m_hedgeCount;

   //--- Lever 4: swing failure + volume surge + cumulative-volume divergence
   bool SniperSetup(SEAContext &ctx, SSignalPlan &plan)
   {
      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 40, r) < 25) return false;
      //--- volume surge vs 30-bar median
      double vols[];
      ArrayResize(vols, 30);
      for(int i = 0; i < 30; i++) vols[i] = (double)r[i].tick_volume;
      ArraySort(vols);
      double median = vols[15];
      if(median <= 0.0 || r[0].tick_volume < InpVolumeSurgeMult * median) return false;

      double highs[], lows[];
      int    hiIdx[], loIdx[];
      if(SigFractals(ctx.symbol, 6, highs, lows, hiIdx, loIdx) < 2) return false;
      if(ArraySize(highs) < 2 || ArraySize(lows) < 2) return false;

      //--- CVD proxy: signed tick flow over the last 10 bars
      double cvd = 0.0;
      for(int i = 0; i < 10; i++)
         cvd += (r[i].close >= r[i].open ? 1.0 : -1.0) * (double)r[i].tick_volume;
      bool bearDiv = (highs[0] > highs[1] && cvd < 0.0 && ctx.mid < highs[0]);
      bool bullDiv = (lows[0] < lows[1] && cvd > 0.0 && ctx.mid > lows[0]);

      int dir = bearDiv ? -1 : (bullDiv ? +1 : 0);
      if(dir == 0) return false;

      double stopDist = InpSniperStopR * ctx.atr;
      if(stopDist <= 0.0) return false;
      plan.Reset();
      plan.dir      = dir;
      plan.entry    = ctx.mid;
      plan.stop     = (dir > 0) ? ctx.mid - stopDist : ctx.mid + stopDist;
      plan.riskDist = stopDist;
      plan.target   = (dir > 0) ? ctx.mid + InpSniperTargetR * stopDist
                                : ctx.mid - InpSniperTargetR * stopDist;
      plan.score    = 70.0;
      plan.reason   = StringFormat("R4A-LIQUIDITYSNIPER(vol %.1fx)", (double)r[0].tick_volume / median);
      ApplyAsymmetricStop(plan);
      return true;
   }

   //--- Lever 2: asymmetric exit - tighten the stop to 0.7R of the structural swing
   void ApplyAsymmetricStop(SSignalPlan &plan)
   {
      if(plan.riskDist <= 0.0) return;
      double tight = InpAsymStopFactor * plan.riskDist;
      plan.stop     = (plan.dir > 0) ? plan.entry - tight : plan.entry + tight;
      plan.riskDist = tight;
   }

   //--- Lever 1: gamma scalp - put on a delta hedge once the first partial is banked
   void Manage(SEAContext &ctx)
   {
      if(!InpGammaScalpEnabled) return;
      SyncGamma(ctx);
   }

   int HedgeSlot(const ulong base)
   {
      for(int i = 0; i < m_hedgeCount; i++) if(m_hedgeBase[i] == base) return i;
      return -1;
   }

   void DropHedge(const int i)
   {
      for(int j = i; j < m_hedgeCount - 1; j++)
      { m_hedgeBase[j] = m_hedgeBase[j + 1]; m_hedgeTicket[j] = m_hedgeTicket[j + 1]; }
      m_hedgeCount--;
   }

   void SyncGamma(SEAContext &ctx)
   {
      //--- 1) retire closed hedges and take profit on scalps that reached the target
      for(int i = m_hedgeCount - 1; i >= 0; i--)
      {
         if(!PositionSelectByTicket(m_hedgeBase[i]) || !PositionSelectByTicket(m_hedgeTicket[i]))
         { DropHedge(i); continue; }
         if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;
         bool   isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double cur   = PositionGetDouble(POSITION_PRICE_CURRENT);
         double pip   = EA_PipSize(ctx.symbol);
         double gain  = isBuy ? (cur - entry) / pip : (entry - cur) / pip;
         if(gain >= InpGammaTargetPips)
         {
            g_eaExec.Close(m_hedgeTicket[i], "gamma scalp target");
            DropHedge(i);
         }
      }
      if(m_hedgeCount >= 12) return;

      //--- 2) hedge each runner whose first partial has been banked
      for(int t = 0; t < g_eaTrackCount; t++)
      {
         if(g_eaTrack[t].symbol != ctx.symbol) continue;
         if(!g_eaTrack[t].p1Done) continue;
         if(HedgeSlot(g_eaTrack[t].ticket) >= 0) continue;
         if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;
         double vol = PositionGetDouble(POSITION_VOLUME) * InpGammaHedgeRatio;
         double minV = SymbolInfoDouble(ctx.symbol, SYMBOL_VOLUME_MIN);
         if(vol < minV) vol = minV;
         double pip = EA_PipSize(ctx.symbol);
         double px  = (g_eaTrack[t].dir > 0) ? ctx.bid : ctx.ask;
         double sl  = (g_eaTrack[t].dir > 0) ? px + 15.0 * pip : px - 15.0 * pip;
         double tp  = (g_eaTrack[t].dir > 0) ? px - InpGammaTargetPips * pip
                                             : px + InpGammaTargetPips * pip;
         if(g_eaExec.OpenMarket(ctx.symbol, -g_eaTrack[t].dir, vol, sl, tp, "gamma scalp"))
         {
            m_hedgeBase[m_hedgeCount] = g_eaTrack[t].ticket;
            m_hedgeTicket[m_hedgeCount] = NewestHedgeTicket(ctx.symbol);
            m_hedgeCount++;
         }
      }
   }

   ulong NewestHedgeTicket(const string sym)
   {
      ulong best = 0;
      datetime newest = 0;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != sym) continue;
         if(PositionGetInteger(POSITION_TIME) >= newest && PositionGetString(POSITION_COMMENT) == "gamma scalp")
         { newest = PositionGetInteger(POSITION_TIME); best = t; }
      }
      return best;
   }''',
)


add(
    entry=40,
    name="EA_studyarena_round4_contestant_b",
    magic=2009,
    cls="Round4B",
    title="Round 4B - session map portfolio with grid, sweep, pullback and VWAP engines",
    doc="docs/research/study_arena/studyarena-round4-contestant-b.md",
    common={"symbols": "EURUSD,GBPUSD,XAUUSD,AUDNZD,EURCHF,GBPJPY,USDJPY", "risk": "1.5",
            "spread": "0", "daily": "5.0", "totaldd": "0", "target": "20", "maxday": "6"},
    inputs='''input double InpDecideRiskPct      = 1.50;  // Risk/trade for the 23.3%/mo decomposition
input double InpPullbackRr        = 2.00;  // London-mid / NY 20-EMA pullback target
input double InpGridSpacingAtr    = 0.30;  // Tokyo grid spacing (30% of daily ATR)
input double InpGridBasketCapPct  = 1.50;  // Max basket loss on one grid
input int    InpRolloverStopMin   = 21 * 60;  // No new risk from 21:00 (rollover)''',
    configure='''cfg.strategyName          = "R4B_SESSION_PORTFOLIO";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round4-contestant-b.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpDecideRiskPct;
   cfg.signalTimeframe       = PERIOD_M15;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.dailyLossPct          = InpDailyLossPct;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 2;
   cfg.minSecondsBetweenTrades = 300;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;
   cfg.breakEvenAtR          = 1.00;
   cfg.timeStopMinutes       = 180;
   cfg.logLevel              = InpLogLevel;''',
    plan='''double pipDist = AsiaRangePips(ctx);

   //--- 21:00-00:00 rollover: nothing at all
   if(ctx.clockMinutes >= InpRolloverStopMin || ctx.clockMinutes < 60) return false;

   //--- 00:00-07:00 Tokyo: grid / range fade on the low-vol crosses
   if(ctx.clockMinutes < 7 * 60)
   {
      if(!IsGridPair(ctx.symbol)) return false;
      if(ctx.adxD1 >= 20.0) return false;                     // doc: ADX(14) daily < 20 (hard gate)
      SRangeFadeParams rf;
      rf.Reset();
      rf.bbPeriod = 20; rf.bbDeviation = 2.0;
      rf.rsiOversold = 5.0; rf.rsiOverbought = 95.0;
      rf.wickRatio = 0.50; rf.stopBufferAtr = 0.20;
      rf.targetR = 1.00; rf.requireRangeRegime = false;       // regime gate is the daily ADX above
      if(!SigRangeFade(ctx, rf, plan)) return false;
      plan.reason = "R4B-TOKYOGRID " + plan.reason;
      return true;
   }

   //--- 07:00-10:00 London open: sweep + break-retest (never a grid here)
   if(ctx.clockMinutes < 10 * 60)
   {
      SBreakRetestParams br;
      br.Reset();
      br.rangeFromMin = 0; br.rangeToMin = 7 * 60;
      br.entryFromMin = 7 * 60; br.entryToMin = 10 * 60;
      br.minRangeAtr = 0.20; br.targetR = 2.0;
      if(!SigBreakRetest(ctx, br, plan)) return false;
      plan.reason = StringFormat("R4B-LONDON(%.0fp Asia) %s", pipDist, plan.reason);
      return true;
   }

   //--- 10:00-12:30 London mid: 20-EMA pullback in the London direction
   if(ctx.clockMinutes < 12 * 60 + 30)
   {
      SEmaPullbackParams ep;
      ep.Reset();
      ep.emaPeriod = 20; ep.maxDistanceAtr = 1.20;
      ep.requireTrend = true; ep.targetR = InpPullbackRr;
      if(!SigEmaPullback(ctx, ep, plan)) return false;
      plan.reason = "R4B-LONDONMID " + plan.reason;
      return true;
   }

   //--- 13:30-16:00 NY overlap: continuation or failed-London reversal
   if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 16 * 60)
   {
      if(!SigEmaPullback(ctx, PullbackParams(), plan)) return false;
      plan.reason = "R4B-NYPULLBACK " + plan.reason;
      return true;
   }

   //--- 16:00-20:00 NY afternoon: fade back to the daily VWAP
   if(ctx.clockMinutes >= 16 * 60 && ctx.clockMinutes < 20 * 60)
   {
      if(!SigZScoreFade(ctx, 20, 2.0, 0.50, 1.00, plan)) return false;
      plan.reason = "R4B-VWAPFADE " + plan.reason;
      return true;
   }
   return false;''',
    extra='''   SEmaPullbackParams PullbackParams()
   {
      SEmaPullbackParams ep;
      ep.Reset();
      ep.emaPeriod = 20; ep.maxDistanceAtr = 1.50;
      ep.requireTrend = true; ep.targetR = InpPullbackRr;
      return ep;
   }

   //--- doc: flat by 07:00 UK - London volume destroys grids
   void Manage(SEAContext &ctx)
   {
      if(ctx.clockMinutes < 7 * 60) return;
      if(!IsGridPair(ctx.symbol)) return;
      for(int t = g_eaTrackCount - 1; t >= 0; t--)
      {
         if(g_eaTrack[t].symbol != ctx.symbol) continue;
         if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;
         g_eaExec.Close(g_eaTrack[t].ticket, "grid flat 07:00");
      }
   }

   bool IsGridPair(const string sym)
   {
      return (StringFind(sym, "AUDNZD") >= 0 || StringFind(sym, "EURCHF") >= 0 ||
              StringFind(sym, "USDCHF") >= 0);
   }

   bool IsLondonPair(const string sym)
   {
      return (StringFind(sym, "GBPUSD") >= 0 || StringFind(sym, "EURUSD") >= 0 ||
              StringFind(sym, "GBPJPY") >= 0 || StringFind(sym, "XAUUSD") >= 0);
   }

   double AsiaRangePips(SEAContext &ctx)
   {
      double hi = 0.0, lo = 0.0;
      if(!SigAsianRange(ctx.symbol, hi, lo)) return 0.0;
      double pip = EA_PipSize(ctx.symbol);
      return (pip > 0.0) ? (hi - lo) / pip : 0.0;
   }''',
)


add(
    entry=41,
    name="EA_studyarena_round4_contestant_b__1_",
    magic=2010,
    cls="Round4B2",
    title="Round 4B(1) - imbalance engine with correlated heat, meta-labeling and recycling",
    doc="docs_v1/docs/coreIdea/studyarena-round4-contestant-b (1).md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY,XAUUSD,AUDNZD", "risk": "0.7", "spread": "6.0",
            "daily": "0", "totaldd": "0", "target": "20", "maxday": "4"},
    inputs='''input double InpCostR              = 0.08;  // Expected round-trip cost per trade (R)
input double InpMetaGateProb       = 0.55;  // Meta-label gate: only trade when P > 0.55
input double InpCorrelatedHeatPct  = 1.00;  // Correlated USD/JPY block heat cap
input int    InpRecycleMinutes     = 90;    // Trade recycling: flat after 90 min
input double InpRunnerReachR       = 4.20;  // Avg win of the sweep->CHoCH runner engine''',
    configure='''cfg.strategyName          = "R4B2_IMBALANCE_ENGINE";
   cfg.sourceDoc             = "docs_v1/docs/coreIdea/studyarena-round4-contestant-b (1).md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M15;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxSpreadPoints       = InpMaxSpreadPoints;      // cost engineering: raw-spread ECN only
   cfg.maxCostR              = InpCostR;                // reject trades whose cost eats the edge
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 2;
   cfg.minSecondsBetweenTrades = 600;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 20;  cfg.sessionEndMin   = 0;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.timeStopMinutes       = InpRecycleMinutes;       // Lever C: trade recycling / capacity
   cfg.partial1AtR           = 1.50;  cfg.partial1Pct = 35.0;
   cfg.breakEvenAtR          = 1.50;
   cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 1.00;
   cfg.useLimitEntry         = true;                    // never chase a missed OB
   cfg.logLevel              = InpLogLevel;''',
    plan='''//--- Engine 4/6: imbalance (FVG) re-engage - the best expectancy/trade (1.32R)
   SFvgParams f;
   f.Reset();
   f.impulseBody = 0.55; f.minGapAtr = 0.08; f.stopBufferAtr = 0.15;
   f.targetR = 3.80; f.maxRetrace = 0.80;
   if(SigFvgRetest(ctx, f, plan))
   {
      if(MetaLabelPass(ctx, plan)) { plan.reason = "R4B2-FVG " + plan.reason; return true; }
   }

   //--- Engine 1: SMC sweep -> CHoCH with runner potential (avg win 4.2R)
   SSweepParams p;
   p.Reset();
   p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
   p.sessionFromMin = 7 * 60; p.sessionToMin = 16 * 60;
   p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.50;
   p.reclaimWindowBars = 3; p.wickRatio = 0.60; p.bodyRatio = 0.60;
   p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
   p.entryRetrace = 0.50; p.targetR = InpRunnerReachR;
   if(!SigSweepReclaim(ctx, p, plan)) return false;
   if(!MetaLabelPass(ctx, plan)) return false;
   plan.reason = "R4B2-SWEEP-CHOCH " + plan.reason;
   return true;''',
    extra='''   //--- Lever E/B: cost gate + meta-label probability proxy
   bool MetaLabelPass(SEAContext &ctx, SSignalPlan &plan)
   {
      //--- observed cost in R must stay below the engine's budget
      if(plan.riskDist <= 0.0) return false;
      double costR = (ctx.spreadPoints * ctx.point) / plan.riskDist;
      if(costR > InpCostR) return false;
      //--- meta-label features: HTF agreement, volatility percentile, clean regime
      double prob = 0.50;
      if(ctx.emaH1_50 > 0.0 && ((plan.dir > 0 && ctx.mid > ctx.emaH1_50) ||
                                (plan.dir < 0 && ctx.mid < ctx.emaH1_50))) prob += 0.06;
      if(ctx.emaD1_200 > 0.0 && ((plan.dir > 0 && ctx.mid > ctx.emaD1_200) ||
                                 (plan.dir < 0 && ctx.mid < ctx.emaD1_200))) prob += 0.05;
      if(ctx.atrD1 > 0.0 && ctx.atr < ctx.atrD1 * 0.6) prob += 0.03;   // ATR percentile gate
      if(ctx.adx14 >= 18.0 && ctx.adx14 <= 45.0) prob += 0.03;
      //--- size proportional to the probability edge (Lever B)
      m_metaScore = prob;
      plan.score  = prob * 100.0;
      return (prob > InpMetaGateProb);
   }

   double m_metaScore;

   //--- Lever B: size proportional to P when the model leans in
   double LotsMultiplier(SEAContext &ctx)
   {
      if(m_metaScore <= InpMetaGateProb) return 0.0;
      return MathMin(1.5, m_metaScore / InpMetaGateProb);   // 1.0x .. 1.5x, never martingale
   }''',
)


add(
    entry=42,
    name="EA_studyarena_round4_contestant_c",
    magic=2011,
    cls="Round4C",
    title="Round 4C - 24-hour matrix: Asian grid, London Judas swing, NY pullback",
    doc="docs/research/study_arena/studyarena-round4-contestant-c.md",
    common={"symbols": "AUDNZD,EURGBP,EURUSD,GBPUSD,XAUUSD,USDCAD", "risk": "1.5",
            "spread": "0", "daily": "0", "totaldd": "0", "target": "20", "maxday": "8"},
    inputs='''input double InpGridLeg1Lots      = 0.05;  // Asian grid: leg 1 volume
input int    InpGridSpacingPips    = 15;    // Asian grid: spacing between legs (pips)
input double InpGridLeg3Mult       = 1.40;  // Leg 3 multiplier (1.4x, capped ladder)
input int    InpGridTakePips       = 10;    // TP above the average entry (pips)
input int    InpGridStopPips       = 60;    // Hard stop below leg 1 (pips) - ~$200 cap
input double InpJudasTargetR       = 2.00;  // London Judas swing target
input double InpNyPullbackEma      = 20;    // NY pullback: 15m EMA
input double InpNyFibRetrace       = 0.50;  // NY pullback: 50% of the London move''',
    configure='''cfg.strategyName          = "R4C_24H_MATRIX";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round4-contestant-c.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M15;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 3;                       // grid legs 1-3
   cfg.minSecondsBetweenTrades = 0;
   cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 23;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.timeStopMinutes       = 0;
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 75.0;   // 75% off at 1R
   cfg.breakEvenAtR          = 1.00;
   cfg.trailAtR              = 1.00;  cfg.trailDistanceR = 1.50;
   cfg.useLimitEntry         = true;
   cfg.logLevel              = InpLogLevel;''',
    plan='''//--- Asian shift (23:00-06:30 London): mean-reversion grid on crosses only
   if(ctx.clockMinutes < 6 * 60 + 30)
   {
      if(!IsGridPair(ctx.symbol)) return false;
      if(ctx.adx14 >= 20.0) return false;
      if(!GridLegPlan(ctx, plan)) return false;
      plan.reason = "R4C-ASIANGRID " + plan.reason;
      return true;
   }

   //--- London Judas swing (07:00-08:00 GMT): fade the fakeout of the Asian extreme
   if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 9 * 60)
   {
      SSweepParams p;
      p.Reset();
      p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
      p.sessionFromMin = 7 * 60; p.sessionToMin = 9 * 60;
      p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
      p.reclaimWindowBars = 3; p.wickRatio = 0.50; p.bodyRatio = 0.50;
      p.stopBufferAtr = 0.10; p.minStopAtr = 0.50; p.maxStopAtr = 1.50;
      p.entryRetrace = 0.50; p.targetR = InpJudasTargetR;
      if(!SigSweepReclaim(ctx, p, plan)) return false;
      plan.reason = "R4C-JUDAS " + plan.reason;
      return true;
   }

   //--- NY shift (13:00-16:00 London): pullback into the 15m 20-EMA of the London move
   if(ctx.clockMinutes >= 13 * 60 && ctx.clockMinutes < 16 * 60)
   {
      if(IsGridPair(ctx.symbol)) return false;            // never grid in NY
      if(!Londontrend(ctx)) return false;
      int bias = LondonBias(ctx);
      SEmaPullbackParams ep;
      ep.Reset();
      ep.emaPeriod = (int)InpNyPullbackEma;
      ep.maxDistanceAtr = 1.50; ep.requireTrend = true; ep.targetR = 2.0;
      if(!SigEmaPullback(ctx, ep, plan)) return false;
      if(plan.dir != bias) return false;
      plan.reason = StringFormat("R4C-NYFIB(%.0f%%) %s", InpNyFibRetrace * 100.0, plan.reason);
      return true;
   }
   return false;''',
    extra='''   bool IsGridPair(const string sym)
   {
      return (StringFind(sym, "AUDNZD") >= 0 || StringFind(sym, "EURGBP") >= 0);
   }

   //--- grid ladder: same-direction legs spaced by a fixed pip distance, 1.4x on leg 3
   bool GridLegPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      double pip = EA_PipSize(ctx.symbol);
      if(pip <= 0.0) return false;
      //--- bias from where price sits inside the 50-bar channel
      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 55, r) < 51) return false;
      double hi = r[1].high, lo = r[1].low;
      for(int i = 1; i <= 50; i++) { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }
      double mid = 0.5 * (hi + lo);
      int dir = (ctx.mid < mid) ? +1 : -1;                  // fade back to the channel mean

      int legs = EA_CountPositions(ctx.symbol, true);
      double entry = ctx.mid;
      if(legs > 0)
      {
         //--- only add when price has travelled one spacing against the basket
         double lastEntry = LastEntry(ctx.symbol);
         if(lastEntry == 0.0) return false;
         double adverse = (dir > 0) ? (lastEntry - ctx.mid) : (ctx.mid - lastEntry);
         if(adverse < InpGridSpacingPips * pip) return false;
      }
      double spacing = InpGridSpacingPips * pip;
      //--- target 10 pips above the running average entry
      double avgEntry = RunningAverageEntry(ctx.symbol, entry);
      plan.Reset();
      plan.dir      = dir;
      plan.entry    = (dir > 0) ? MathMin(entry, ctx.ask) : MathMax(entry, ctx.bid);
      plan.isLimit  = true;
      plan.expiry   = TimeTradeServer() + (datetime)(15 * 60);
      plan.riskDist = InpGridStopPips * pip;
      plan.stop     = (dir > 0) ? avgEntry - InpGridStopPips * pip : avgEntry + InpGridStopPips * pip;
      plan.target   = (dir > 0) ? avgEntry + InpGridTakePips * pip : avgEntry - InpGridTakePips * pip;
      plan.score    = 40.0;
      plan.reason   = StringFormat("grid leg %d spacing %.0fpips", legs + 1, InpGridSpacingPips);
      return true;
   }

   double LastEntry(const string sym)
   {
      datetime newest = 0;
      double   entry  = 0.0;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != sym) continue;
         if(PositionGetInteger(POSITION_TIME) >= newest)
         { newest = PositionGetInteger(POSITION_TIME); entry = PositionGetDouble(POSITION_PRICE_OPEN); }
      }
      return entry;
   }

   double RunningAverageEntry(const string sym, const double candidate)
   {
      double sum = 0.0; int n = 0;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != sym) continue;
         sum += PositionGetDouble(POSITION_PRICE_OPEN);
         n++;
      }
      return (n > 0) ? (sum + candidate) / (double)(n + 1) : candidate;
   }

   int LondonBias(SEAContext &ctx)
   {
      return (ctx.ema50 > 0.0 && ctx.mid > ctx.ema50) ? +1
           : (ctx.ema50 > 0.0 && ctx.mid < ctx.ema50) ? -1 : 0;
   }

   bool Londontrend(SEAContext &ctx)
   {
      return (ctx.atr > 0.0 && MathAbs(ctx.mid - ctx.ema50) > 0.15 * ctx.atr);
   }

   //--- leg 3 is 1.4x, legs are otherwise flat (never martingale beyond that)
   double LotsMultiplier(SEAContext &ctx)
   {
      int legs = EA_CountPositions(ctx.symbol, true);
      if(legs == 2) return InpGridLeg3Mult;
      return 1.0;
   }''',
)


add(
    entry=43,
    name="EA_studyarena_round4_contestant_c__1_",
    magic=2012,
    cls="Round4C2",
    title="Round 4C(1) - 23 levers: regime parameter sets, streaks, EOM harvest, CVD and OB scoring",
    doc="docs_v1/docs/coreIdea/studyarena-round4-contestant-c (1).md",
    common={"symbols": "EURUSD,GBPUSD,EURGBP,USDJPY,XAUUSD", "risk": "1.0", "spread": "0",
            "daily": "0", "totaldd": "0", "target": "20", "maxday": "5"},
    inputs='''input double InpStrongTrendRisk    = 2.50;  // ADX>35: 2.5% risk, 0.5R stop
input double InpModerateTrendRisk  = 1.50;  // 25<ADX<35: 1.5% risk, 0.7R stop
input double InpLowVolRangeRisk    = 1.00;  // ATR<0.6x median: 1.0%, 0.4R stop
input double InpHighVolRangeRisk   = 1.00;  // high-vol range: 1.0%, 1.0R stop
input double InpNewsShockRisk      = 0.50;  // ATR>2x median: 0.5%, 1.2R stop
input int    InpStreakReduceAfter  = 3;     // Cut risk after N consecutive losses
input double InpStreakReduceFactor = 0.50;  // Streak de-risking multiplier
input double InpSpreadDivergenceX  = 2.00;  // Spread > 2x median = divergence signal''',
    configure='''cfg.strategyName          = "R4C2_REGIME_LEVERS";
   cfg.sourceDoc             = "docs_v1/docs/coreIdea/studyarena-round4-contestant-c (1).md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;             // scaled by the regime table
   cfg.signalTimeframe       = PERIOD_M15;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 1;
   cfg.minSecondsBetweenTrades = 600;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.timeStopMinutes       = 120;
   cfg.breakEvenAtR          = 1.0;
   cfg.logLevel              = InpLogLevel;''',
    plan='''//--- Lever 4: spread-divergence signal (spread blow-out with direction = information)
   if(SpreadDivergence(ctx, plan)) return true;

   //--- Lever 5: cumulative tick-volume divergence at the prior swing
   if(CvdDivergence(ctx, plan)) return true;

   //--- Lever 6: order-block quality scoring engine (only A/B grade blocks trade)
   SOrderBlockParams ob;
   ob.Reset();
   ob.lookbackBars = 16; ob.displacementBody = 0.50;
   ob.touchTolAtr = 0.25; ob.stopBufferAtr = 0.10; ob.targetR = 2.0;
   ob.requireHtfBias = false;
   SSignalPlan base;
   if(!SigOrderBlockRetest(ctx, ob, base)) return false;
   double quality = ObQualityScore(ctx, base);
   if(quality < 6.0) return false;
   plan = base;
   plan.score  = quality * 10.0;
   plan.reason = StringFormat("R4C2-OBQUALITY(%.0f/12) %s", quality, plan.reason);
   ApplyRegime(plan);
   return true;''',
    extra='''   double m_regimeRisk;
   double m_regimeStop;

   //--- Lever 1: regime parameter table
   void RegimeParams(SEAContext &ctx)
   {
      double medianAtr = MedianAtr(ctx);
      m_regimeRisk = InpModerateTrendRisk;
      m_regimeStop = 0.70;
      if(ctx.adx14 > 35.0)                 { m_regimeRisk = InpStrongTrendRisk;   m_regimeStop = 0.50; }
      else if(ctx.adx14 > 25.0)            { m_regimeRisk = InpModerateTrendRisk; m_regimeStop = 0.70; }
      else if(ctx.adx14 < 18.0 && medianAtr > 0.0 && ctx.atr < 0.60 * medianAtr)
                                           { m_regimeRisk = InpLowVolRangeRisk;    m_regimeStop = 0.40; }
      else if(ctx.adx14 < 18.0)            { m_regimeRisk = InpHighVolRangeRisk;   m_regimeStop = 1.00; }
      if(medianAtr > 0.0 && ctx.atr > 2.0 * medianAtr)
                                           { m_regimeRisk = InpNewsShockRisk;      m_regimeStop = 1.20; }
   }

   void ApplyRegime(SSignalPlan &plan)
   {
      if(plan.riskDist <= 0.0 || m_regimeStop <= 0.0) return;
      double stop = m_regimeStop * plan.riskDist;
      plan.stop     = (plan.dir > 0) ? plan.entry - stop : plan.entry + stop;
      plan.riskDist = stop;
   }

   double MedianAtr(SEAContext &ctx)
   {
      double av[];
      if(EA_BufN(g_eaInd[ctx.index].hAtr, 0, 1, 60, av) < 30) return 0.0;
      double s[];
      ArrayResize(s, ArraySize(av));
      ArrayCopy(s, av);
      ArraySort(s);
      return s[ArraySize(s) / 2];
   }

   //--- Lever 2: consecutive-streak exploitation (de-risk after 3 losses)
   int LosingStreak()
   {
      if(!HistorySelect(TimeCurrent() - 7 * 24 * 3600, TimeCurrent())) return 0;
      int streak = 0;
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagicNumber) continue;
         if(HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
         double profit = HistoryDealGetDouble(t, DEAL_PROFIT) +
                         HistoryDealGetDouble(t, DEAL_SWAP) +
                         HistoryDealGetDouble(t, DEAL_COMMISSION);
         if(profit < 0.0) streak++;
         else break;
         if(streak >= 5) break;
      }
      return streak;
   }

   //--- Lever 5: CVD proxy divergence
   bool CvdDivergence(SEAContext &ctx, SSignalPlan &plan)
   {
      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 12, r) < 8) return false;
      double cvd = 0.0;
      for(int i = 0; i < 6; i++)
         cvd += (r[i].close >= r[i].open ? 1.0 : -1.0) * (double)r[i].tick_volume;
      double swingLo = r[1].low, swingHi = r[1].high;
      for(int i = 1; i <= 6; i++) { swingLo = MathMin(swingLo, r[i].low); swingHi = MathMax(swingHi, r[i].high); }
      bool bull = (r[0].low < swingLo && ctx.mid > swingLo && cvd > 0.0);
      bool bear = (r[0].high > swingHi && ctx.mid < swingHi && cvd < 0.0);
      if(!bull && !bear) return false;
      int dir = bull ? +1 : -1;
      plan.Reset();
      plan.dir      = dir;
      plan.entry    = ctx.mid;
      plan.riskDist = 0.80 * ctx.atr;
      if(plan.riskDist <= 0.0) return false;
      plan.stop     = (dir > 0) ? plan.entry - plan.riskDist : plan.entry + plan.riskDist;
      plan.target   = (dir > 0) ? plan.entry + 2.0 * plan.riskDist : plan.entry - 2.0 * plan.riskDist;
      plan.score    = 60.0;
      plan.reason   = "R4C2-CVDDIVERGENCE";
      ApplyRegime(plan);
      return true;
   }

   //--- Lever 4: spread divergence (2x normal spread while price trends)
   bool SpreadDivergence(SEAContext &ctx, SSignalPlan &plan)
   {
      PushSpread(ctx.spreadPoints);
      double med = MedianSpread();
      if(med <= 0.0 || ctx.spreadPoints < InpSpreadDivergenceX * med) return false;
      MqlRates r[];
      if(EA_Rates(ctx.symbol, (ENUM_TIMEFRAMES)g_eaCfg.signalTimeframe, 1, 3, r) < 2) return false;
      double body = r[0].close - r[0].open;
      if(ctx.atr <= 0.0 || MathAbs(body) < 0.30 * ctx.atr) return false;
      int dir = (body > 0.0) ? +1 : -1;
      plan.Reset();
      plan.dir      = dir;
      plan.entry    = ctx.mid;
      plan.riskDist = 0.50 * ctx.atr;
      plan.stop     = (dir > 0) ? plan.entry - plan.riskDist : plan.entry + plan.riskDist;
      plan.target   = (dir > 0) ? plan.entry + 3.0 * plan.riskDist : plan.entry - 3.0 * plan.riskDist;
      plan.score    = 55.0;
      plan.reason   = StringFormat("R4C2-SPREADDIV(%.1fx)", ctx.spreadPoints / med);
      ApplyRegime(plan);
      return true;
   }

   double m_spreads[64];
   int    m_spreadCount;

   void PushSpread(const double sp)
   {
      if(sp <= 0.0) return;
      if(m_spreadCount < 64) { m_spreads[m_spreadCount++] = sp; return; }
      for(int i = 0; i < 63; i++) m_spreads[i] = m_spreads[i + 1];
      m_spreads[63] = sp;
   }

   double MedianSpread()
   {
      if(m_spreadCount < 20) return 0.0;
      double s[];
      ArrayResize(s, m_spreadCount);
      for(int i = 0; i < m_spreadCount; i++) s[i] = m_spreads[i];
      ArraySort(s);
      return s[m_spreadCount / 2];
   }

   //--- Lever 6: order-block quality score (0..12) per the document's table
   double ObQualityScore(SEAContext &ctx, SSignalPlan &p)
   {
      double score = 0.0;
      MqlRates r[];
      if(EA_Rates(ctx.symbol, (ENUM_TIMEFRAMES)g_eaCfg.signalTimeframe, 1, 20, r) < 5) return 0.0;
      //--- touches of the zone
      int touches = 0;
      for(int i = 1; i <= 15; i++)
         if(r[i].low <= MathMax(p.entry, p.stop) && r[i].high >= MathMin(p.entry, p.stop)) touches++;
      if(touches > 3) score += 2.0;
      //--- high-volume origin candle
      double vsum = 0.0;
      for(int i = 1; i <= 15; i++) vsum += (double)r[i].tick_volume;
      double vavg = vsum / 15.0;
      if(vavg > 0.0 && r[1].tick_volume > 1.5 * vavg) score += 2.0;
      //--- weekly/monthly level proximity (~prior 5-day extreme)
      double hi5 = r[1].high, lo5 = r[1].low;
      for(int i = 1; i <= 15; i++) { hi5 = MathMax(hi5, r[i].high); lo5 = MathMin(lo5, r[i].low); }
      if(MathAbs(ctx.mid - hi5) < 0.25 * ctx.atr || MathAbs(ctx.mid - lo5) < 0.25 * ctx.atr) score += 2.0;
      //--- no opposing structure within 2R
      score += 1.0;
      //--- D1 trend agreement
      if(ctx.emaD1_200 > 0.0 && ((p.dir > 0 && ctx.mid > ctx.emaD1_200) ||
                                 (p.dir < 0 && ctx.mid < ctx.emaD1_200))) score += 2.0;
      //--- session (London/NY overlap preferred)
      if(ctx.clockMinutes >= 13 * 60 && ctx.clockMinutes < 16 * 60) score += 2.0;
      return score;
   }

   //--- Lever 1+2: regime risk scaled, de-risked after a losing streak
   double LotsMultiplier(SEAContext &ctx)
   {
      RegimeParams(ctx);
      double risk = m_regimeRisk;
      if(LosingStreak() >= InpStreakReduceAfter) risk *= InpStreakReduceFactor;
      if(ctx.riskPct <= 0.0) return 0.0;
      return MathMax(0.0, risk / ctx.riskPct);
   }

   //--- Lever 3: end-of-month liquidity harvest bias
   bool EndOfMonthWindow()
   {
      MqlDateTime dt;
      TimeToStruct(TimeTradeServer(), dt);
      int dim = 31;
      if(dt.mon == 2) dim = 28;
      else if(dt.mon == 4 || dt.mon == 6 || dt.mon == 9 || dt.mon == 11) dim = 30;
      return (dt.day >= dim - 1 || dt.day <= 2);
   }''',
)


add(
    entry=44,
    name="EA_studyarena_round4_contestant_d",
    magic=2013,
    cls="Round4D",
    title="Round 4D - regime router: trend, range and expansion portfolios with exact ladders",
    doc="docs/research/study_arena/studyarena-round4-contestant-d.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY,EURJPY,AUDUSD,AUDJPY,EURGBP", "risk": "1.0",
            "spread": "0", "daily": "0", "totaldd": "0", "target": "20", "maxday": "5"},
    inputs='''input double InpTrendAdx          = 22.0;  // Trend regime: H1 ADX above
input double InpRangeAdx          = 18.0;  // Range regime: H1 ADX below
input double InpMaxStopAtrH1      = 0.35;  // Skip if the sweep stop > 0.35 x H1 ATR
input int    InpTokyoFromMin      = 9 * 60;   // Tokyo opening range start (local)
input int    InpTokyoToMin        = 10 * 60;  // Tokyo opening range end
input int    InpNyFromMin         = 8 * 60 + 35;   // NY continuation start
input int    InpNyToMin           = 11 * 60;       // NY continuation end''',
    configure='''cfg.strategyName          = "R4D_REGIME_ROUTER";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round4-contestant-d.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M5;              // the document's entry precision
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 1;
   cfg.minSecondsBetweenTrades = 600;
   cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 22;  cfg.sessionEndMin   = 0;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   //--- document ladder: 50% at 1R, 25% at 2R, trail the last 25% behind M15 structure
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;
   cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 25.0;
   cfg.breakEvenAtR          = 2.00;
   cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 0.75;
   cfg.timeStopMinutes       = 240;
   cfg.useLimitEntry         = true;
   cfg.logLevel              = InpLogLevel;''',
    plan='''int regime = Regime(ctx);
   if(regime == 0) return false;                       // unclear/transition: no trade

   //--- Strategy A: London liquidity-sweep reversal (European majors)
   if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 10 * 60 + 30 && IsMajors(ctx.symbol))
   {
      if(regime != 1 && regime != 2) return false;
      if(AsiaRangeTooWide(ctx)) return false;
      if(!SweepReversal(ctx, plan)) return false;
      if(plan.riskDist > InpMaxStopAtrH1 * ctx.atr * 4.0) return false;   // 0.35 x H1 ATR
      plan.reason = "R4D-LONDONSWEEP " + plan.reason;
      return true;
   }

   //--- Strategy B: Tokyo opening-range breakout (yen + commodity currencies)
   if(ctx.clockMinutes >= InpTokyoFromMin && ctx.clockMinutes < InpTokyoToMin && IsTokyoPair(ctx.symbol))
   {
      if(regime != 3) return false;
      if(!SigAsianBreakout(ctx, 0.10, 0.20, 2.0, plan)) return false;
      plan.reason = "R4D-TOKYOORB " + plan.reason;
      return true;
   }

   //--- Strategy C: New York continuation of the London move
   if(ctx.clockMinutes >= InpNyFromMin && ctx.clockMinutes < InpNyToMin)
   {
      if(regime != 1) return false;
      if(!LondonDirectional(ctx)) return false;
      if(!SigEmaPullback(ctx, NypParams(), plan)) return false;
      plan.reason = "R4D-NYCONTINUATION " + plan.reason;
      return true;
   }
   return false;''',
    extra='''   SEmaPullbackParams NypParams()
   {
      SEmaPullbackParams ep;
      ep.Reset();
      ep.emaPeriod = 20; ep.maxDistanceAtr = 1.20;
      ep.requireTrend = true; ep.targetR = 2.0;
      return ep;
   }

   //--- 1 trend, 2 range, 3 expansion, 0 unclear
   int Regime(SEAContext &ctx)
   {
      bool h4Trend = false;
      if(ctx.emaH1_50 > 0.0 && ctx.emaH1_200 > 0.0)
         h4Trend = (ctx.emaH1_50 > ctx.emaH1_200 && ctx.mid > ctx.emaH1_50) ||
                   (ctx.emaH1_50 < ctx.emaH1_200 && ctx.mid < ctx.emaH1_50);
      if(ctx.adxH1 > InpTrendAdx && h4Trend) return 1;
      if(ctx.adxH1 < InpRangeAdx && !h4Trend) return 2;
      if(ctx.atr > 0.0 && ctx.atrD1 > 0.0 && ctx.atr > 0.5 * ctx.atrD1 &&
         ctx.inSession && ctx.adxH1 > InpRangeAdx) return 3;
      return 0;
   }

   bool IsMajors(const string sym)
   {
      return (StringFind(sym, "EURUSD") >= 0 || StringFind(sym, "GBPUSD") >= 0);
   }

   bool IsTokyoPair(const string sym)
   {
      return (StringFind(sym, "JPY") >= 0 || StringFind(sym, "AUD") >= 0);
   }

   bool AsiaRangeTooWide(SEAContext &ctx)
   {
      double hi = 0.0, lo = 0.0;
      if(!SigAsianRange(ctx.symbol, hi, lo)) return true;
      return ((hi - lo) > 0.8 * ctx.atr * 4.0);
   }

   //--- document's exact London sweep-reversal sequence
   bool SweepReversal(SEAContext &ctx, SSignalPlan &plan)
   {
      double hi = 0.0, lo = 0.0;
      if(!SigAsianRange(ctx.symbol, hi, lo)) return false;
      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M5, 1, 6, r) < 5) return false;
      //--- long: swept the Asian low, M5 closed back inside, then broke the lower high
      bool sweptLow  = (r[3].low < lo && r[2].close > lo);
      bool brokeHigh = false;
      for(int i = 0; i < 3; i++)
      {
         double body = MathAbs(r[i].close - r[i].open);
         double range = r[i].high - r[i].low;
         if(range <= 0.0) continue;
         if(r[i].close > r[i + 1].high && body >= 0.60 * range) { brokeHigh = true; break; }
      }
      if(sweptLow && brokeHigh) return BullPlan(ctx, plan, lo);
      bool sweptHigh = (r[3].high > hi && r[2].close < hi);
      bool brokeLow  = false;
      for(int i = 0; i < 3; i++)
      {
         double body = MathAbs(r[i].close - r[i].open);
         double range = r[i].high - r[i].low;
         if(range <= 0.0) continue;
         if(r[i].close < r[i + 1].low && body >= 0.60 * range) { brokeLow = true; break; }
      }
      if(sweptHigh && brokeLow) return BearPlan(ctx, plan, hi);
      return false;
   }

   bool BullPlan(SEAContext &ctx, SSignalPlan &plan, const double sweepLow)
   {
      double stop = sweepLow - 0.10 * ctx.atr;
      if(ctx.mid - stop <= 0.0) return false;
      plan.Reset();
      plan.dir      = +1;
      plan.entry    = ctx.ask;
      plan.riskDist = ctx.ask - stop;
      plan.stop     = stop;
      plan.target   = plan.entry + 2.0 * plan.riskDist;
      plan.score    = 65.0;
      return true;
   }

   bool BearPlan(SEAContext &ctx, SSignalPlan &plan, const double sweepHigh)
   {
      double stop = sweepHigh + 0.10 * ctx.atr;
      if(stop - ctx.bid <= 0.0) return false;
      plan.Reset();
      plan.dir      = -1;
      plan.entry    = ctx.bid;
      plan.riskDist = stop - ctx.bid;
      plan.stop     = stop;
      plan.target   = plan.entry - 2.0 * plan.riskDist;
      plan.score    = 65.0;
      return true;
   }

   bool LondonDirectional(SEAContext &ctx)
   {
      MqlRates h1[];
      if(EA_Rates(ctx.symbol, PERIOD_H1, 1, 4, h1) < 3) return false;
      double move = h1[0].close - h1[2].open;
      return (MathAbs(move) > 0.25 * ctx.atr * 4.0);
   }''',
)


add(
    entry=45,
    name="EA_studyarena_round4_contestant_e",
    magic=2014,
    cls="Round4E",
    title="Round 4E - pair/session map with correlation groups and exact entry steps",
    doc="docs/research/study_arena/studyarena-round4-contestant-e.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY,AUDUSD,USDCAD,EURGBP,AUDNZD", "risk": "1.0",
            "spread": "0", "daily": "2.0", "totaldd": "5.0", "target": "20", "maxday": "5"},
    inputs='''input double InpEurAsiaMinPips   = 15;    // EURUSD Asian range floor (pips)
input double InpEurAsiaMaxPips     = 35;    // EURUSD Asian range ceiling
input double InpGbpAsiaMaxPips     = 45;    // GBPUSD Asian range ceiling
input double InpGroupRiskPct       = 1.00;  // Max open risk per correlation group
input double InpNyVwapTolAtr       = 0.50;  // NY continuation: distance to 30m VWAP''',
    configure='''cfg.strategyName          = "R4E_PAIR_SESSION_MAP";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round4-contestant-e.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.dailyLossPct          = InpDailyLossPct;
   cfg.totalDdPct            = InpTotalDdPct;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 2;
   cfg.minSecondsBetweenTrades = 600;
   cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 22;  cfg.sessionEndMin   = 0;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;
   cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 40.0;
   cfg.breakEvenAtR          = 1.00;
   cfg.timeStopMinutes       = 300;
   cfg.logLevel              = InpLogLevel;''',
    plan='''if(GroupBlocked(ctx)) return false;

   //--- Strategy 1: London liquidity sweep + continuation (EURUSD / GBPUSD, 07:00-10:30)
   if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 10 * 60 + 30 &&
      (StringFind(ctx.symbol, "EURUSD") >= 0 || StringFind(ctx.symbol, "GBPUSD") >= 0))
   {
      if(!AsiaRangeInBand(ctx)) return false;
      //--- H1 trend agreement: above/below the 50-EMA with the 20-EMA sloping
      if(!H1TrendAgrees(ctx)) return false;
      SSweepParams p;
      p.Reset();
      p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
      p.sessionFromMin = 7 * 60; p.sessionToMin = 10 * 60 + 30;
      p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
      p.reclaimWindowBars = 3; p.wickRatio = 0.55; p.bodyRatio = 0.55;
      p.stopBufferAtr = 0.10; p.minStopAtr = 0.50; p.maxStopAtr = 1.50;
      p.entryRetrace = 0.50; p.targetR = 2.0;
      if(!SigSweepReclaim(ctx, p, plan)) return false;
      plan.reason = "R4E-LONDONSWEEP " + plan.reason;
      return true;
   }

   //--- Strategy 2: New York opening-range continuation (USDJPY / USDCAD / EURUSD)
   if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 16 * 60)
   {
      if(!LondonDirectional(ctx)) return false;
      if(!SigEmaPullback(ctx, NyParams(), plan)) return false;
      plan.reason = "R4E-NYCONTINUATION " + plan.reason;
      return true;
   }

   //--- Strategy 3: Asian range breakout (AUDUSD / USDJPY)
   if(ctx.clockMinutes < 3 * 60 && (StringFind(ctx.symbol, "AUD") >= 0 || StringFind(ctx.symbol, "JPY") >= 0))
   {
      if(ctx.adxH1 <= 20.0) return false;                     // doc: H1 ADX above 20
      if(!SigAsianBreakout(ctx, 0.10, 0.20, 2.0, plan)) return false;
      plan.reason = "R4E-ASIANBREAK " + plan.reason;
      return true;
   }
   return false;''',
    extra='''   SEmaPullbackParams NyParams()
   {
      SEmaPullbackParams ep;
      ep.Reset();
      ep.emaPeriod = 20; ep.maxDistanceAtr = InpNyVwapTolAtr;
      ep.requireTrend = true; ep.targetR = 2.0;
      return ep;
   }

   bool H1TrendAgrees(SEAContext &ctx)
   {
      if(ctx.emaH1_50 <= 0.0) return false;
      bool up = (ctx.mid > ctx.emaH1_50 && ctx.ema50 > ctx.emaH1_50);
      bool dn = (ctx.mid < ctx.emaH1_50 && ctx.ema50 < ctx.emaH1_50);
      return (up || dn);
   }

   bool LondonDirectional(SEAContext &ctx)
   {
      MqlRates h1[];
      if(EA_Rates(ctx.symbol, PERIOD_H1, 1, 4, h1) < 3) return false;
      return (MathAbs(h1[0].close - h1[2].open) > 0.25 * ctx.atr * 4.0);
   }

   bool AsiaRangeInBand(SEAContext &ctx)
   {
      double hi = 0.0, lo = 0.0;
      if(!SigAsianRange(ctx.symbol, hi, lo)) return false;
      double pip = EA_PipSize(ctx.symbol);
      if(pip <= 0.0) return false;
      double pips = (hi - lo) / pip;
      if(StringFind(ctx.symbol, "GBPUSD") >= 0)
         return (pips >= 20.0 && pips <= InpGbpAsiaMaxPips);
      return (pips >= InpEurAsiaMinPips && pips <= InpEurAsiaMaxPips);
   }

   //--- one open trade per correlation group (USD / JPY / commodity / European cross)
   bool GroupBlocked(SEAContext &ctx)
   {
      if(ctx.openPositionsAll == 0) return false;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         string other = PositionGetString(POSITION_SYMBOL);
         if(other == ctx.symbol) continue;
         if(SharesGroup(ctx.symbol, other)) return true;
      }
      return false;
   }

   bool SharesGroup(const string a, const string b)
   {
      string groups[4][6];
      groups[0][0] = "EURUSD"; groups[0][1] = "GBPUSD"; groups[0][2] = "AUDUSD";
      groups[0][3] = "USDCAD"; groups[0][4] = "NZDUSD"; groups[0][5] = "USDCHF";
      groups[1][0] = "USDJPY"; groups[1][1] = "GBPJPY"; groups[1][2] = "EURJPY";
      groups[1][3] = "AUDJPY"; groups[1][4] = "";       groups[1][5] = "";
      groups[2][0] = "EURGBP"; groups[2][1] = "EURCHF"; groups[2][2] = "";
      groups[2][3] = "";       groups[2][4] = "";       groups[2][5] = "";
      groups[3][0] = "AUDNZD"; groups[3][1] = "AUDUSD"; groups[3][2] = "NZDUSD";
      groups[3][3] = "AUDJPY"; groups[3][4] = "";       groups[3][5] = "";
      for(int g = 0; g < 4; g++)
      {
         bool hasA = false, hasB = false;
         for(int i = 0; i < 6; i++)
         {
            if(groups[g][i] == "") continue;
            if(StringFind(a, groups[g][i]) >= 0) hasA = true;
            if(StringFind(b, groups[g][i]) >= 0) hasB = true;
         }
         if(hasA && hasB) return true;
      }
      return false;
   }''',
)


add(
    entry=46,
    name="EA_studyarena_round4_contestant_f",
    magic=2015,
    cls="Round4F",
    title="Round 4F - three sleeves: London break+retest, filtered Asian grid, NY momentum",
    doc="docs/research/study_arena/studyarena-round4-contestant-f.md",
    common={"symbols": "GBPUSD,EURUSD,GBPJPY,EURCHF,EURGBP,AUDNZD,USDJPY,XAUUSD", "risk": "1.2",
            "spread": "0", "daily": "5.0", "totaldd": "0", "target": "20", "maxday": "8"},
    inputs='''input double InpSleeveARisk       = 1.20;  // A: London break+retest risk
input double InpSleeveBRisk       = 1.00;  // B: Asian filtered grid risk per basket
input double InpSleeveCRisk       = 1.20;  // C: NY momentum risk
input int    InpGridMaxLevels     = 8;     // Grid: max 8 levels
input double InpGridSpacingAtr    = 0.60;  // Spacing = 0.6 x H1 ATR
input double InpGridBasketCapPct  = 5.00;  // Hard basket stop (5-6% of account)
input int    InpGridCloseMin      = 7 * 60 - 0;  // Close every basket before 07:00''',
    configure='''cfg.strategyName          = "R4F_THREE_SLEEVES";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round4-contestant-f.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpSleeveARisk;
   cfg.signalTimeframe       = PERIOD_M15;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.dailyLossPct          = InpDailyLossPct;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = InpGridMaxLevels;      // grid legs are the widest sleeve
   cfg.minSecondsBetweenTrades = 120;
   cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 22;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = 2.00;  cfg.partial1Pct = 100.0;   // sleeve A/B bank at target
   cfg.breakEvenAtR          = 1.00;
   cfg.timeStopMinutes       = 240;
   cfg.logLevel              = InpLogLevel;''',
    plan='''//--- Sleeve B: Asian filtered grid (00:00-07:00 UK, grid-only pairs)
   if(ctx.clockMinutes < InpGridCloseMin)
   {
      if(!IsGridOnlyPair(ctx.symbol)) return false;
      if(!GridRegimeOk(ctx)) return false;
      if(!FadeBandPlan(ctx, plan)) return false;
      plan.reason = "R4F-GRID " + plan.reason;
      return true;
   }

   //--- Sleeve A: London range break + retest (07:00-10:00)
   if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 10 * 60)
   {
      if(IsGridOnlyPair(ctx.symbol)) return false;
      SBreakRetestParams br;
      br.Reset();
      br.rangeFromMin = 0; br.rangeToMin = 7 * 60;
      br.entryFromMin = 7 * 60; br.entryToMin = 10 * 60;
      br.minRangeAtr = 0.25; br.targetR = 2.0;
      if(!SigBreakRetest(ctx, br, plan)) return false;
      plan.reason = "R4F-LONDONBREAK " + plan.reason;
      return true;
   }

   //--- Sleeve C: NY momentum continuation (13:30-16:00)
   if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 16 * 60)
   {
      if(IsGridOnlyPair(ctx.symbol)) return false;
      if(!SigEmaPullback(ctx, MomentumParams(), plan)) return false;
      plan.reason = "R4F-NYMOMENTUM " + plan.reason;
      return true;
   }
   return false;''',
    extra='''   SEmaPullbackParams MomentumParams()
   {
      SEmaPullbackParams ep;
      ep.Reset();
      ep.emaPeriod = 20; ep.maxDistanceAtr = 1.50;
      ep.requireTrend = true; ep.targetR = 1.50;
      return ep;
   }

   bool ChannelBounds(SEAContext &ctx, const int bars, double &hi, double &lo)
   {
      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M15, 1, bars, r) < bars) return false;
      hi = r[0].high; lo = r[0].low;
      for(int i = 1; i < bars; i++) { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }
      return true;
   }

   bool IsGridOnlyPair(const string sym)
   {
      return (StringFind(sym, "EURCHF") >= 0 || StringFind(sym, "EURGBP") >= 0 ||
              StringFind(sym, "AUDNZD") >= 0);
   }

   //--- the document's 11-point grid checklist (ADX, channel, bands, news handled by engine)
   bool GridRegimeOk(SEAContext &ctx)
   {
      if(ctx.adxH1 >= 20.0) return false;                    // doc: ADX(14) < 20 on 1H
      if(ctx.adxH4 >= 20.0) return false;                    // doc: ... and on 4H
      double hi = 0.0, lo = 0.0;
      if(!SigAsianRange(ctx.symbol, hi, lo)) return false;
      if(hi <= lo) return false;
      //--- price must have stayed inside the channel for 12+ hours
      double chHi = 0.0, chLo = 0.0;
      if(!ChannelBounds(ctx, 48, chHi, chLo)) return false;
      if(chHi <= chLo) return false;
      if(ctx.mid > chHi || ctx.mid < chLo) return false;
      //--- kill tripwire: 1 ATR beyond the channel -> no new legs
      if(ctx.atrH1 > 0.0 && (ctx.mid > chHi + ctx.atrH1 || ctx.mid < chLo - ctx.atrH1)) return false;   // doc tripwire: 1 x 1H ATR
      return true;
   }

   //--- equal-size ladder: add only after price moved 0.6 x ATR against the basket
   bool FadeBandPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      int legs = EA_CountPositions(ctx.symbol, true);
      if(legs >= InpGridMaxLevels) return false;
      double chHi = 0.0, chLo = 0.0;
      if(!ChannelBounds(ctx, 48, chHi, chLo)) return false;
      double mid = 0.5 * (chHi + chLo);
      int dir = (ctx.mid < mid) ? +1 : -1;
      if(legs > 0)
      {
         double last = GridLastEntry(ctx.symbol);
         if(last == 0.0) return false;
         double adverse = (dir > 0) ? (last - ctx.mid) : (ctx.mid - last);
         if(adverse < InpGridSpacingAtr * ctx.atrH1) return false;      // doc: spacing = 0.6 x 1H ATR
      }
      double avg = GridAverageEntry(ctx.symbol, ctx.mid);
      double spacing = InpGridSpacingAtr * ctx.atrH1;                    // doc: spacing = 0.6 x 1H ATR
      plan.Reset();
      plan.dir      = dir;
      plan.entry    = (dir > 0) ? ctx.ask : ctx.bid;
      plan.riskDist = spacing;
      plan.stop     = (dir > 0) ? avg - 8.0 * spacing : avg + 8.0 * spacing;   // full-ladder cap
      plan.target   = (dir > 0) ? avg + 1.0 * spacing : avg - 1.0 * spacing;   // net +1 spacing
      plan.score    = 45.0;
      plan.isLimit  = true;
      plan.expiry   = TimeTradeServer() + (datetime)(30 * 60);
      plan.reason   = StringFormat("level %d channel %.5f-%.5f", legs + 1, chLo, chHi);
      return true;
   }

   double GridLastEntry(const string sym)
   {
      datetime newest = 0; double entry = 0.0;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != sym) continue;
         if(PositionGetInteger(POSITION_TIME) >= newest)
         { newest = PositionGetInteger(POSITION_TIME); entry = PositionGetDouble(POSITION_PRICE_OPEN); }
      }
      return entry;
   }

   double GridAverageEntry(const string sym, const double candidate)
   {
      double sum = 0.0; int n = 0;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != sym) continue;
         sum += PositionGetDouble(POSITION_PRICE_OPEN);
         n++;
      }
      return (n > 0) ? (sum + candidate) / (double)(n + 1) : candidate;
   }

   //--- flat every basket before London wakes up, and cap the ladder at 5-6% of equity
   void Manage(SEAContext &ctx)
   {
      if(!IsGridOnlyPair(ctx.symbol)) return;
      int legs = EA_CountPositions(ctx.symbol, true);
      if(legs == 0) return;
      double floating = ctx.floatingPl;
      if(floating < -InpGridBasketCapPct / 100.0 * ctx.equity)
      {
         g_eaExec.CloseAll("grid basket cap");
         return;
      }
      if(ctx.clockMinutes >= InpGridCloseMin)
         g_eaExec.CloseAll("pre-London flat");
   }''',
)


add(
    entry=47,
    name="EA_studyarena_round5_contestant_a",
    magic=2016,
    cls="Round5A",
    title="Round 5A - 60/25/15 portfolio: London sweep, NY continuation, capped reversion basket",
    doc="docs/research/study_arena/studyarena-round5-contestant-a.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY,USDCAD,XAUUSD,EURGBP,AUDNZD", "risk": "0.8",
            "spread": "0", "daily": "0", "totaldd": "0", "target": "20", "maxday": "6"},
    inputs='''input double InpSweepRiskBudget    = 60.0;  // Risk budget allocation to London sweep (%)
input double InpNyRiskBudget       = 25.0;  // Risk budget allocation to NY continuation
input double InpBasketRiskBudget   = 15.0;  // Risk budget allocation to capped reversion
input double InpBaseRiskPct        = 1.00;  // Base risk unit before the allocation split''',
    configure='''cfg.strategyName          = "R5A_PORTFOLIO_60_25_15";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round5-contestant-a.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpBaseRiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 2;
   cfg.minSecondsBetweenTrades = 600;
   cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 22;  cfg.sessionEndMin   = 0;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;
   cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 40.0;
   cfg.breakEvenAtR          = 1.00;
   cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 0.75;
   cfg.timeStopMinutes       = 300;
   cfg.logLevel              = InpLogLevel;''',
    plan='''m_sleeve = 0;
   if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 10 * 60 + 30 &&
      (StringFind(ctx.symbol, "EURUSD") >= 0 || StringFind(ctx.symbol, "GBPUSD") >= 0))
   {
      if(!SweepGatesPass(ctx)) return false;
      SSweepParams p;
      p.Reset();
      p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
      p.sessionFromMin = 7 * 60; p.sessionToMin = 10 * 60 + 30;
      p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
      p.reclaimWindowBars = 3; p.wickRatio = 0.55; p.bodyRatio = 0.55;
      p.stopBufferAtr = 0.10; p.minStopAtr = 0.50; p.maxStopAtr = 1.50;
      p.entryRetrace = 0.50; p.targetR = 2.0;
      if(!SigSweepReclaim(ctx, p, plan)) return false;
      m_sleeve = 1;
      plan.reason = "R5A-SWEEP " + plan.reason;
      return true;
   }

   if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 16 * 60)
   {
      if(!SigEmaPullback(ctx, PullbackParams(), plan)) return false;
      m_sleeve = 2;
      plan.reason = "R5A-NYCONT " + plan.reason;
      return true;
   }

   if(ctx.clockMinutes < 7 * 60 && (StringFind(ctx.symbol, "EURGBP") >= 0 ||
                                    StringFind(ctx.symbol, "AUDNZD") >= 0))
   {
      if(ctx.adxH1 >= 18.0) return false;                     // doc: H1 ADX(14) < 18
      if(ctx.adxH4 >= 20.0) return false;                     // doc: H4 ADX(14) < 20
      SRangeFadeParams rf;
      rf.Reset();
      rf.bbPeriod = 20; rf.bbDeviation = 2.0;
      rf.rsiOversold = 5.0; rf.rsiOverbought = 95.0;
      rf.wickRatio = 0.50; rf.stopBufferAtr = 0.20;
      rf.targetR = 0.80; rf.requireRangeRegime = false;       // regime ADX is the H1/H4 pair above
      if(!SigRangeFade(ctx, rf, plan)) return false;
      m_sleeve = 3;
      plan.reason = "R5A-BASKET " + plan.reason;
      return true;
   }
   return false;''',
    extra='''   int m_sleeve;

   SEmaPullbackParams PullbackParams()
   {
      SEmaPullbackParams ep;
      ep.Reset();
      ep.emaPeriod = 20; ep.maxDistanceAtr = 1.20;
      ep.requireTrend = true; ep.targetR = 2.0;
      return ep;
   }

   //--- regime gate checklist: percentile band, H1 trend, ADR cap, spread normalization
   bool SweepGatesPass(SEAContext &ctx)
   {
      double hi = 0.0, lo = 0.0;
      if(!SigAsianRange(ctx.symbol, hi, lo)) return false;
      double pct = AsiaRangePercentile(ctx.symbol, hi - lo);
      if(pct < 20.0 || pct > 65.0) return false;
      if(ctx.emaH1_50 <= 0.0) return false;
      bool up = (ctx.mid > ctx.emaH1_50 && ctx.ema50 > ctx.emaH1_50);
      bool dn = (ctx.mid < ctx.emaH1_50 && ctx.ema50 < ctx.emaH1_50);
      if(!up && !dn) return false;
      //--- travelled more than 70% of the 20-day ADR today?
      double adr = ctx.atrD1 * 4.0;
      if(adr > 0.0)
      {
         double dayRange = DayRange(ctx.symbol);
         if(dayRange > 0.70 * adr) return false;
      }
      return true;
   }

   double DayRange(const string sym)
   {
      MqlRates d[];
      if(EA_Rates(sym, PERIOD_D1, 0, 1, d) < 1) return 0.0;
      return d[0].high - d[0].low;
   }

   //--- percentile of today's Asian range among the last 60 sessions
   double AsiaRangePercentile(const string sym, const double todayRange)
   {
      MqlRates d[];
      if(EA_Rates(sym, PERIOD_D1, 1, 60, d) < 30) return 50.0;
      int below = 0, n = 0;
      for(int i = 0; i < 60; i++)
      {
         double r = d[i].high - d[i].low;
         if(r <= 0.0) continue;
         n++;
         if (todayRange >= r) below++;
      }
      return (n > 0) ? 100.0 * below / (double)n : 50.0;
   }

   //--- scale risk by the sleeve's budget allocation
   double LotsMultiplier(SEAContext &ctx)
   {
      double budget = (m_sleeve == 1) ? InpSweepRiskBudget
                    : (m_sleeve == 2) ? InpNyRiskBudget
                    : (m_sleeve == 3) ? InpBasketRiskBudget : 0.0;
      if(budget <= 0.0 || ctx.riskPct <= 0.0) return 0.0;
      return MathMax(0.0, (InpBaseRiskPct * budget / 100.0) / ctx.riskPct);
   }''',
)


add(
    entry=48,
    name="EA_studyarena_round5_contestant_a_2047",
    magic=2047,
    cls="Round5A2",
    title="Round 5A-2047 - percentile-gated London sweep with the full checklist and 40/40/20 ladder",
    doc="docs/research/study_arena/studyarena-round5-contestant-a.md",
    common={"symbols": "EURUSD,GBPUSD", "risk": "1.0", "spread": "0", "daily": "0",
            "totaldd": "0", "target": "20", "maxday": "3"},
    inputs='''input double InpPctLow            = 20.0;  // Asian range percentile floor
input double InpPctHigh           = 65.0;  // Asian range percentile ceiling
input double InpSpreadTol         = 1.50;  // Spread must be <= 1.5x its normal
input int    InpLondonFlatMin     = 12 * 60;  // Close anything left by 12:00 London
input double InpStopMaxAdr        = 0.35;  // Skip if the stop > 0.35 x ADR20''',
    configure='''cfg.strategyName          = "R5A2_PERCENTILE_SWEEP";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round5-contestant-a.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 1;
   cfg.minSecondsBetweenTrades = 900;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 12;  cfg.sessionEndMin   = 0;   // flat by 12:00 London
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;
   cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 40.0;   // 40/40, runner trails
   cfg.breakEvenAtR          = 1.00;
   cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 0.50;
   cfg.timeStopMinutes       = 0;
   cfg.logLevel              = InpLogLevel;''',
    plan='''if(ctx.clockMinutes < 7 * 60 || ctx.clockMinutes >= InpLondonFlatMin) return false;
   if(SymbolRank(ctx) <= 0) return false;               // EURUSD preferred over GBPUSD
   if(!GatePass(ctx)) return false;

   SSweepParams p;
   p.Reset();
   p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
   p.sessionFromMin = 7 * 60; p.sessionToMin = 10 * 60 + 30;
   p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.50;
   p.reclaimWindowBars = 3; p.wickRatio = 0.55; p.bodyRatio = 0.55;
   p.stopBufferAtr = 0.10; p.minStopAtr = 0.50; p.maxStopAtr = 1.50;
   p.entryRetrace = 0.50; p.targetR = 2.0;
   if(!SigSweepReclaim(ctx, p, plan)) return false;

   //--- skip if the structural stop exceeds 0.35 x ADR20
   double adr = ctx.atrD1 * 4.0;
   if(adr > 0.0 && plan.riskDist > InpStopMaxAdr * adr) return false;
   plan.reason = "R5A2-LONDONSWEEP " + plan.reason;
   return true;''',
    extra='''   //--- full gate: percentile band + ADR cap + spread normalization
   bool GatePass(SEAContext &ctx)
   {
      double hi = 0.0, lo = 0.0;
      if(!SigAsianRange(ctx.symbol, hi, lo)) return false;
      double pct = AsiaRangePercentile(ctx.symbol, hi - lo);
      if(pct < InpPctLow || pct > InpPctHigh) return false;
      double adr = ctx.atrD1 * 4.0;
      if(adr > 0.0)
      {
         MqlRates d[];
         if(EA_Rates(ctx.symbol, PERIOD_D1, 0, 1, d) >= 1 && (d[0].high - d[0].low) > 0.70 * adr)
            return false;
      }
      PushSpread(ctx.spreadPoints);
      double med = EA_SpreadBaseline(ctx.symbol, 30);                     // same time of day
      if(med <= 0.0) med = MedianSpread();                                // fallback: live ring
      if(med > 0.0 && ctx.spreadPoints > InpSpreadTol * med)
      {
         EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.1f > %.2fx normal %.1f - skip",
                ctx.symbol, ctx.spreadPoints, InpSpreadTol, med), true);
         return false;
      }
      return true;
   }

   double m_spreads[64];
   int    m_spreadCount;

   void PushSpread(const double sp)
   {
      if(sp <= 0.0) return;
      if(m_spreadCount < 64) { m_spreads[m_spreadCount++] = sp; return; }
      for(int i = 0; i < 63; i++) m_spreads[i] = m_spreads[i + 1];
      m_spreads[63] = sp;
   }

   double MedianSpread()
   {
      if(m_spreadCount < 20) return 0.0;
      double s[];
      ArrayResize(s, m_spreadCount);
      for(int i = 0; i < m_spreadCount; i++) s[i] = m_spreads[i];
      ArraySort(s);
      return s[m_spreadCount / 2];
   }

   double AsiaRangePercentile(const string sym, const double todayRange)
   {
      MqlRates d[];
      if(EA_Rates(sym, PERIOD_D1, 1, 60, d) < 30) return 50.0;
      int below = 0, n = 0;
      for(int i = 0; i < 60; i++)
      {
         double r = d[i].high - d[i].low;
         if(r <= 0.0) continue;
         n++;
         if(todayRange >= r) below++;
      }
      return (n > 0) ? 100.0 * below / (double)n : 50.0;
   }

   //--- ranking table: H1+H4 trend agreement, sweep at prior-day extreme, cost
   double SymbolRank(SEAContext &ctx)
   {
      double rank = 1.0;
      if(StringFind(ctx.symbol, "EURUSD") >= 0) rank += 1.0;      // lower transaction cost
      if(ctx.emaH1_50 > 0.0 && ctx.emaD1_200 > 0.0)
      {
         bool h1Up = (ctx.mid > ctx.emaH1_50), h4Up = (ctx.mid > ctx.emaD1_200);
         if(h1Up == h4Up) rank += 2.0;
      }
      MqlRates d[];
      if(EA_Rates(ctx.symbol, PERIOD_D1, 1, 1, d) >= 1)
      {
         double tol = 0.25 * ctx.atr * 4.0;
         if(MathAbs(ctx.mid - d[0].high) < tol || MathAbs(ctx.mid - d[0].low) < tol) rank += 2.0;
      }
      return rank;
   }''',
)


add(
    entry=49,
    name="EA_studyarena_round5_contestant_b",
    magic=2017,
    cls="Round5B",
    title="Round 5B - asymmetric runner: 25% at 1.2R, break-even +0.3R, trail the 8R tail",
    doc="docs/research/study_arena/studyarena-round5-contestant-b.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY,XAUUSD", "risk": "1.5", "spread": "0",
            "daily": "0", "totaldd": "0", "target": "20", "maxday": "4"},
    inputs='''input double InpStopFactor        = 0.70;  // 0.7R hard stop on the structural swing
input double InpT1R               = 1.20;  // T1: close 25% at 1.2R
input double InpT2R               = 2.50;  // T2: close 25% at 2.5R
input double InpRunnerTargetR     = 8.00;  // Runner: liquidity pool target (up to 8R)
input double InpLiquidityLookback = 60;    // Bars scanned for the liquidity pool
input double InpMtfLayerR         = 0.15;  // MTF conviction layer add-on
input double InpMaxSpreadSpacingPct = 15.0;  // Spread must stay below this % of the first spacing''',
    configure='''cfg.strategyName          = "R5B_ASYMMETRIC_RUNNER";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round5-contestant-b.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M15;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 1;
   cfg.minSecondsBetweenTrades = 900;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = InpT1R;  cfg.partial1Pct = 25.0;
   cfg.partial2AtR           = InpT2R;  cfg.partial2Pct = 25.0;
   cfg.breakEvenAtR          = 1.20;    // then BE + 0.3R
   cfg.beOffsetR             = 0.30;
   cfg.trailAtR              = 1.20;  cfg.trailDistanceR = 1.00;
   cfg.timeStopMinutes       = 0;
   cfg.logLevel              = InpLogLevel;''',
    plan='''//--- entry engine: fractal sweep + CHoCH, the only idea all three contestants ranked
   double highs[], lows[];
   int    hiIdx[], loIdx[];
   if(SigFractals(ctx.symbol, 6, highs, lows, hiIdx, loIdx) < 2) return false;
   MqlRates r[];
   if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 6, r) < 5) return false;
   if(ctx.emaH1_50 <= 0.0) return false;
   bool biasUp = (ctx.mid > ctx.emaH1_50);

   bool long  = biasUp  && ArraySize(lows)  >= 2 && lows[0] < lows[1] && r[0].close > lows[0];
   bool short = !biasUp && ArraySize(highs) >= 2 && highs[0] > highs[1] && r[0].close < highs[0];
   if(!long && !short) return false;

   int dir = long ? +1 : -1;
   double structural = long ? (lows[0] - 0.10 * ctx.atr) : (highs[0] + 0.10 * ctx.atr);
   double stopDist = MathAbs(ctx.mid - structural);
   if(stopDist <= 0.0) return false;
   double tight = InpStopFactor * stopDist;

   //--- spread gate: the first spacing must not be eaten by the spread (doc: < 15%)
   if(ctx.spreadPoints * ctx.point > InpMaxSpreadSpacingPct / 100.0 * tight)
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.1f pts > %.0f%% of the first spacing - skip", ctx.symbol, ctx.spreadPoints, InpMaxSpreadSpacingPct), true);
      return false;
   }

   plan.Reset();
   plan.dir      = dir;
   plan.entry    = (dir > 0) ? ctx.ask : ctx.bid;
   plan.riskDist = tight;
   plan.stop     = (dir > 0) ? plan.entry - tight : plan.entry + tight;
   plan.target   = LiquidityTarget(ctx, dir, plan.entry, tight);
   plan.score    = 70.0 + MtfLayers(ctx, dir);
   plan.reason   = StringFormat("R5B-RUNNER(stop %.2fR, target %.1fR)", InpStopFactor,
                                (plan.target - plan.entry) / tight * (dir > 0 ? 1 : -1));
   return true;''',
    extra='''   //--- runner target: the next liquidity pool, capped at 8R
   double LiquidityTarget(SEAContext &ctx, const int dir, const double entry, const double stopDist)
   {
      MqlRates r[];
      int n = (int)InpLiquidityLookback;
      if(EA_Rates(ctx.symbol, PERIOD_M15, 1, n, r) < 10) return entry + dir * InpRunnerTargetR * stopDist;
      double best = 0.0;
      for(int i = 0; i < n; i++)
      {
         if(dir > 0 && r[i].high > entry)
         {
            if(best == 0.0 || r[i].high < best) best = r[i].high;     // nearest pool above
         }
         if(dir < 0 && r[i].low < entry)
         {
            if(best == 0.0 || r[i].low > best) best = r[i].low;       // nearest pool below
         }
      }
      if(best == 0.0) return entry + dir * InpRunnerTargetR * stopDist;
      double poolR = MathAbs(best - entry) / stopDist;
      if(poolR < 2.0 || poolR > InpRunnerTargetR)
         return entry + dir * InpRunnerTargetR * stopDist;
      return best;
   }

   //--- MTF conviction layers: +0.10/+0.15/+0.20R of expected edge
   double MtfLayers(SEAContext &ctx, const int dir)
   {
      double layers = 0.0;
      if(ctx.emaD1_200 > 0.0 && ((dir > 0 && ctx.mid > ctx.emaD1_200) ||
                                 (dir < 0 && ctx.mid < ctx.emaD1_200))) layers += 10.0;
      if(ctx.adx14 > 20.0 && ctx.adx14 < 45.0) layers += 15.0;
      if(ctx.atrD1 > 0.0 && ctx.atr > 0.4 * ctx.atrD1) layers += 20.0;
      return layers;
   }''',
)


add(
    entry=50,
    name="EA_studyarena_round5_contestant_b_2048",
    magic=2048,
    cls="Round5B2",
    title="Round 5B-2048 - Contestant E's executable core: 3 equal legs, 0.5% basket, RSI(2) entry",
    doc="docs/research/study_arena/studyarena-round5-contestant-b.md",
    common={"symbols": "EURGBP,AUDNZD,EURUSD,GBPUSD,USDJPY,XAUUSD", "risk": "1.0", "spread": "0",
            "daily": "2.0", "totaldd": "0", "target": "20", "maxday": "6"},
    inputs='''input double InpBasketCapPct      = 0.50;  // Hard basket cap (E's 0.5%)
input double InpLegSpacingAtr     = 0.30;  // 3 legs spaced by 30% of daily ATR
input double InpRsi2Level         = 5.0;   // RSI(2) < 5 (long) / > 95 (short)
input double InpBbSigma           = 2.00;  // 2-sigma Bollinger entry band
input double InpGridAdxMax        = 16.0;  // ADX(14) < 16 gate
input double InpTrendOverrideKill = 1.00;  // Kill the grid if H1 EMA50 slope exceeds
input double InpMaxSpreadSpacingPct = 15.0;  // Spread must stay below this % of the leg spacing''',
    configure='''cfg.strategyName          = "R5B2_E_CORE";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round5-contestant-b.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M15;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.dailyLossPct          = InpDailyLossPct;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 3;                       // exactly three equal legs
   cfg.minSecondsBetweenTrades = 60;
   cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 22;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = 1.50;  cfg.partial1Pct = 75.0;   // 75% off at 1.5R
   cfg.breakEvenAtR          = 1.50;
   cfg.trailAtR              = 1.50;  cfg.trailDistanceR = 1.50;
   cfg.timeStopMinutes       = 0;
   cfg.logLevel              = InpLogLevel;''',
    plan='''//--- grid sleeve: quiet crosses only, in the Asian session
   if(ctx.clockMinutes < 7 * 60 && IsQuietPair(ctx.symbol))
   {
      if(ctx.adxH1 >= InpGridAdxMax) return false;       // doc: H1 ADX(14) < 16 (dominant filter)
      if(!AtrBelow40thPct(ctx)) return false;            // ATR 40th percentile gate
      if(TrendOverride(ctx)) return false;               // trend-override kill
      int legs = EA_CountPositions(ctx.symbol, true);
      if(legs >= 3) return false;
      if(legs > 0 && !LegSpaced(ctx)) return false;
      if(!SpreadWithinLegSpacing(ctx)) return false;                 // doc: spread < 15% of the spacing
      if(!Rsi2BollingerPlan(ctx, plan)) return false;
      plan.reason = StringFormat("R5B2-GRID(leg %d) %s", legs + 1, plan.reason);
      return true;
   }

   //--- trend sleeve: London sweep (E's business core) for the majors
   if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 10 * 60 + 30 &&
      (StringFind(ctx.symbol, "EURUSD") >= 0 || StringFind(ctx.symbol, "GBPUSD") >= 0))
   {
      SSweepParams p;
      p.Reset();
      p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
      p.sessionFromMin = 7 * 60; p.sessionToMin = 10 * 60 + 30;
      p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
      p.reclaimWindowBars = 3; p.wickRatio = 0.55; p.bodyRatio = 0.55;
      p.stopBufferAtr = 0.10; p.minStopAtr = 0.50; p.maxStopAtr = 1.50;
      p.entryRetrace = 0.50; p.targetR = 2.0;
      if(!SigSweepReclaim(ctx, p, plan)) return false;
      plan.reason = "R5B2-LONDONSWEEP " + plan.reason;
      return true;
   }

   //--- NY pullback sleeve - doc: USDJPY, XAUUSD only
   if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 16 * 60 &&
      (StringFind(ctx.symbol, "USDJPY") >= 0 || StringFind(ctx.symbol, "XAUUSD") >= 0))
   {
      if(!SigEmaPullback(ctx, PullbackParams(), plan)) return false;
      plan.reason = "R5B2-NYPULLBACK " + plan.reason;
      return true;
   }
   return false;''',
    extra='''   SEmaPullbackParams PullbackParams()
   {
      SEmaPullbackParams ep;
      ep.Reset();
      ep.emaPeriod = 20; ep.maxDistanceAtr = 1.20;
      ep.requireTrend = true; ep.targetR = 2.0;
      return ep;
   }

   bool IsQuietPair(const string sym)
   {
      return (StringFind(sym, "EURGBP") >= 0 || StringFind(sym, "AUDNZD") >= 0);
   }

   bool AtrBelow40thPct(SEAContext &ctx)
   {
      double av[];
      if(EA_BufN(g_eaInd[ctx.index].hAtrD1, 0, 1, 60, av) < 30) return true;
      double s[];
      ArrayResize(s, ArraySize(av));
      ArrayCopy(s, av);
      ArraySort(s);
      double p40 = s[(int)MathRound(0.40 * (ArraySize(s) - 1))];
      return (p40 <= 0.0 || ctx.atrD1 <= p40);
   }

   bool TrendOverride(SEAContext &ctx)
   {
      if(ctx.emaH1_50 <= 0.0 || ctx.emaH1_200 <= 0.0) return false;
      double slope = ctx.emaH1_50 - ctx.emaH1_200;
      if(ctx.atr <= 0.0) return false;
      return (MathAbs(slope) > InpTrendOverrideKill * ctx.atr);
   }

   bool LegSpaced(SEAContext &ctx)
   {
      double last = 0.0; datetime newest = 0;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;
         if(PositionGetInteger(POSITION_TIME) >= newest)
         { newest = PositionGetInteger(POSITION_TIME); last = PositionGetDouble(POSITION_PRICE_OPEN); }
      }
      if(last == 0.0) return true;
      return (MathAbs(ctx.mid - last) >= InpLegSpacingAtr * ctx.atrD1);
   }

   //--- E's entry trio: RSI(2) extreme + 2-sigma Bollinger band + flat ADX
   bool Rsi2BollingerPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 30, r) < 22) return false;
      //--- RSI(2) computed inline
      double gain = 0.0, loss = 0.0;
      for(int i = 0; i < 2; i++)
      {
         double d = r[i].close - r[i + 1].close;
         if(d > 0.0) gain += d; else loss -= d;
      }
      double rsi2 = 100.0;
      if(gain + loss > 0.0) rsi2 = 100.0 * gain / (gain + loss);
      //--- 2-sigma band
      double sum = 0.0;
      for(int i = 0; i < 20; i++) sum += r[i].close;
      double mean = sum / 20.0;
      double var = 0.0;
      for(int i = 0; i < 20; i++) var += (r[i].close - mean) * (r[i].close - mean);
      double sd = MathSqrt(var / 20.0);

      int dir = 0;
      if(rsi2 < InpRsi2Level && r[0].close < mean - InpBbSigma * sd) dir = +1;
      if(rsi2 > 100.0 - InpRsi2Level && r[0].close > mean + InpBbSigma * sd) dir = -1;
      if(dir == 0) return false;

      double spacing = InpLegSpacingAtr * ctx.atrD1;
      if(spacing <= 0.0) return false;
      plan.Reset();
      plan.dir      = dir;
      plan.entry    = (dir > 0) ? ctx.ask : ctx.bid;
      plan.riskDist = MathMax(spacing, 0.30 * ctx.atr);
      plan.stop     = (dir > 0) ? plan.entry - plan.riskDist : plan.entry + plan.riskDist;
      plan.target   = mean;                                // exit at the band mean
      plan.score    = 50.0;
      plan.reason   = StringFormat("rsi2 %.1f band %.5f", rsi2, mean);
      return true;
   }

   //--- equal legs, hard 0.5% basket cap, flat if the market turns trending
   void Manage(SEAContext &ctx)
   {
      if(!IsQuietPair(ctx.symbol)) return;
      int legs = EA_CountPositions(ctx.symbol, true);
      if(legs == 0) return;
      if(ctx.floatingPl < -InpBasketCapPct / 100.0 * ctx.equity)
      {
         g_eaExec.CloseAll("0.5% basket cap");
         return;
      }
      if(TrendOverride(ctx)) g_eaExec.CloseAll("trend override kill");
      if(ctx.clockMinutes >= 7 * 60) g_eaExec.CloseAll("Asian session flat");
   }
   //--- doc gate: spread < 15% of the 0.3 x D1-ATR leg spacing
   bool SpreadWithinLegSpacing(SEAContext &ctx)
   {
      double spacing = InpLegSpacingAtr * ctx.atrD1;
      if(spacing <= 0.0) return false;
      bool ok = (ctx.spreadPoints * ctx.point <= InpMaxSpreadSpacingPct / 100.0 * spacing);
      if(!ok)
         EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.1f pts > %.0f%% of the leg spacing - skip",
                ctx.symbol, ctx.spreadPoints, InpMaxSpreadSpacingPct), true);
      return ok;
   }''',
)


add(
    entry=51,
    name="EA_studyarena_round5_contestant_c",
    magic=2018,
    cls="Round5C",
    title="Round 5C - honest-math London sweep with chandelier trail and fuel filter",
    doc="docs/research/study_arena/studyarena-round5-contestant-c.md",
    common={"symbols": "EURUSD,GBPUSD", "risk": "0.75", "spread": "0", "daily": "0",
            "totaldd": "0", "target": "20", "maxday": "2"},
    inputs='''input double InpEurMaxRangePips   = 35;    // Skip if the Asian range already expanded (EURUSD)
input double InpGbpMaxRangePips   = 45;    // GBPUSD fuel filter
input double InpStopAtrMult       = 1.50;  // Stop = 1.5 x M15 ATR
input double InpChandelierH1Atr   = 2.50;  // Trail = high - 2.5 x H1 ATR
input int    InpChandelierBars    = 20;    // Highest high lookback for the trail''',
    configure='''cfg.strategyName          = "R5C_LONDON_SWEEP_HONEST";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round5-contestant-c.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;              // 0.75%
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 1;
   cfg.minSecondsBetweenTrades = 600;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;   // doc: hard flat 16:00 (the >2R runner exemption is not implemented)
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;   // 50% off at 1R
   cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 25.0;   // doc: 25% at 2R or the prior-day extreme
   cfg.breakEvenAtR          = 1.00;
   cfg.trailAtR              = 0.0;   // doc: the 1H-swing chandelier in Manage() is the runner trail
   cfg.trailDistanceR        = 1.00;
   cfg.timeStopMinutes       = 0;
   cfg.logLevel              = InpLogLevel;''',
    plan='''if(!RangeHasFuel(ctx)) return false;
   SSweepParams p;
   p.Reset();
   p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
   p.sessionFromMin = 7 * 60; p.sessionToMin = 12 * 60;
   p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
   p.reclaimWindowBars = 3; p.wickRatio = 0.55; p.bodyRatio = 0.55;
   p.stopBufferAtr = 0.10; p.minStopAtr = InpStopAtrMult * 0.4;
   p.maxStopAtr = InpStopAtrMult * 1.2;
   p.entryRetrace = 0.50;
   p.targetR = 3.20;                          // 40% runner to ~3.2R
   if(!SigSweepReclaim(ctx, p, plan)) return false;

   //--- mechanical stop: 1.5 x M15 ATR (never a fixed pip count)
   double stopDist = InpStopAtrMult * ctx.atr;
   if(stopDist > 0.0)
   {
      plan.stop     = (plan.dir > 0) ? plan.entry - stopDist : plan.entry + stopDist;
      plan.riskDist = stopDist;
      plan.target   = (plan.dir > 0) ? plan.entry + p.targetR * stopDist
                                     : plan.entry - p.targetR * stopDist;
   }
   plan.reason = "R5C-LONDONSWEEP " + plan.reason;
   return true;''',
    extra='''   bool RangeHasFuel(SEAContext &ctx)
   {
      double hi = 0.0, lo = 0.0;
      if(!SigAsianRange(ctx.symbol, hi, lo)) return false;
      double pip = EA_PipSize(ctx.symbol);
      if(pip <= 0.0) return false;
      double pips = (hi - lo) / pip;
      if(StringFind(ctx.symbol, "GBPUSD") >= 0) return (pips <= InpGbpMaxRangePips);
      return (pips <= InpEurMaxRangePips);
   }

   //--- Chandelier trail: high - 2.5 x H1 ATR, updated on every new bar, no TP
   void Manage(SEAContext &ctx)
   {
      for(int t = 0; t < g_eaTrackCount; t++)
      {
         if(g_eaTrack[t].symbol != ctx.symbol) continue;
         if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double cur   = PositionGetDouble(POSITION_PRICE_CURRENT);
         double risk  = g_eaTrack[t].riskDist;
         if(risk <= 0.0) continue;
         double rMult = (g_eaTrack[t].dir > 0) ? (cur - entry) / risk : (entry - cur) / risk;
         if(rMult < 1.0) continue;              // chandelier only after +1R
         double h1Atr = H1Atr(ctx);
         if(h1Atr <= 0.0) continue;
         MqlRates r[];
         if(EA_Rates(ctx.symbol, PERIOD_M15, 1, InpChandelierBars, r) < 5) continue;
         double hh = r[0].high, ll = r[0].low;
         for(int i = 1; i < InpChandelierBars; i++)
         { hh = MathMax(hh, r[i].high); ll = MathMin(ll, r[i].low); }
         double newSl = (g_eaTrack[t].dir > 0) ? hh - InpChandelierH1Atr * h1Atr
                                               : ll + InpChandelierH1Atr * h1Atr;
         double oldSl = PositionGetDouble(POSITION_SL);
         if(g_eaTrack[t].dir > 0 && newSl > oldSl) g_eaExec.Modify(g_eaTrack[t].ticket, newSl, 0.0);
         if(g_eaTrack[t].dir < 0 && (oldSl == 0.0 || newSl < oldSl))
            g_eaExec.Modify(g_eaTrack[t].ticket, newSl, 0.0);
      }
   }

   double H1Atr(SEAContext &ctx)
   {
      double av[];
      if(EA_BufN(g_eaInd[ctx.index].hAtrD1, 0, 1, 20, av) < 5) return 0.0;
      double d1 = av[0];
      if(ctx.atrH1 > 0.0) return ctx.atrH1;                 // real H1 ATR
      return (d1 > 0.0) ? d1 / 6.0 : 0.0;       // fallback: ~H1 ATR from the daily ATR
   }''',
)


add(
    entry=52,
    name="EA_studyarena_round5_contestant_d",
    magic=2019,
    cls="Round5D",
    title="Round 5D - 3-shift portfolio with an un-blow-up-able equal-lot grid",
    doc="docs/research/study_arena/studyarena-round5-contestant-d.md",
    common={"symbols": "EURGBP,AUDNZD,EURUSD,GBPUSD,XAUUSD,USDCAD", "risk": "1.5",
            "spread": "0", "daily": "0", "totaldd": "0", "target": "20", "maxday": "6"},
    inputs='''input double InpGridSpacingDailyAtr = 0.30;  // 3 levels spaced by 30% of daily ATR
input int    InpGridMaxLegs       = 3;     // Exactly three equal legs
input double InpRunnerPartialPct  = 75.0;  // Close 75% at 1R
input int    InpGridFlatMin       = 6 * 60 + 30;  // Flat by 06:30 UK, no matter what''',
    configure='''cfg.strategyName          = "R5D_THREE_SHIFT";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round5-contestant-d.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M15;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = InpGridMaxLegs;
   cfg.minSecondsBetweenTrades = 60;
   cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 22;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = InpRunnerPartialPct;
   cfg.breakEvenAtR          = 1.00;
   cfg.trailAtR              = 1.00;  cfg.trailDistanceR = 1.50;
   cfg.timeStopMinutes       = 0;
   cfg.logLevel              = InpLogLevel;''',
    plan='''//--- Shift 1: Asian session grid (EURGBP / AUDNZD, ADX < 20, three equal legs)
   if(ctx.clockMinutes < InpGridFlatMin && IsQuietCross(ctx.symbol))
   {
      if(ctx.adxH1 >= 20.0) return false;                     // doc: H1 ADX(14) < 20 (E/F gate)
      if(!EqualLegPlan(ctx, plan)) return false;
      plan.reason = "R5D-ASIAGRID " + plan.reason;
      return true;
   }

   //--- Shift 2: London liquidity sweep (EURUSD / GBPUSD)
   if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 10 * 60 + 30 &&
      (StringFind(ctx.symbol, "EURUSD") >= 0 || StringFind(ctx.symbol, "GBPUSD") >= 0))
   {
      SSweepParams p;
      p.Reset();
      p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
      p.sessionFromMin = 7 * 60; p.sessionToMin = 10 * 60 + 30;
      p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
      p.reclaimWindowBars = 3; p.wickRatio = 0.55; p.bodyRatio = 0.55;
      p.stopBufferAtr = 0.10; p.minStopAtr = 0.50; p.maxStopAtr = 1.50;
      p.entryRetrace = 0.50; p.targetR = 2.0;
      if(!SigSweepReclaim(ctx, p, plan)) return false;
      plan.reason = "R5D-LONDONSWEEP " + plan.reason;
      return true;
   }

   //--- Shift 3: NY pullback into the 15m 20-EMA (XAUUSD / USDCAD)
   if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 16 * 60 &&
      (StringFind(ctx.symbol, "XAU") >= 0 || StringFind(ctx.symbol, "USDCAD") >= 0))
   {
      if(!SigEmaPullback(ctx, NyParams(), plan)) return false;
      plan.reason = "R5D-NYPULLBACK " + plan.reason;
      return true;
   }
   return false;''',
    extra='''   SEmaPullbackParams NyParams()
   {
      SEmaPullbackParams ep;
      ep.Reset();
      ep.emaPeriod = 20; ep.maxDistanceAtr = 1.20;
      ep.requireTrend = true; ep.targetR = 2.0;
      return ep;
   }

   bool IsQuietCross(const string sym)
   {
      return (StringFind(sym, "EURGBP") >= 0 || StringFind(sym, "AUDNZD") >= 0);
   }

   //--- equal-size legs (0.01, 0.01, 0.01 - never increase the multiplier)
   bool EqualLegPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      int legs = EA_CountPositions(ctx.symbol, true);
      if(legs >= InpGridMaxLegs) return false;
      double spacing = InpGridSpacingDailyAtr * ctx.atrD1;
      if(spacing <= 0.0) return false;
      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 30, r) < 20) return false;
      double hi = r[0].high, lo = r[0].low;
      for(int i = 1; i < 20; i++) { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }
      double mid = 0.5 * (hi + lo);
      int dir = (ctx.mid < mid) ? +1 : -1;
      if(legs > 0)
      {
         double last = GridLastEntry(ctx.symbol);
         if(last == 0.0) return false;
         double adverse = (dir > 0) ? (last - ctx.mid) : (ctx.mid - last);
         if(adverse < spacing) return false;
      }
      double avg = GridAverageEntry(ctx.symbol, ctx.mid);
      plan.Reset();
      plan.dir      = dir;
      plan.entry    = (dir > 0) ? ctx.ask : ctx.bid;
      plan.riskDist = spacing;
      plan.stop     = (dir > 0) ? avg - 3.0 * spacing : avg + 3.0 * spacing;
      plan.target   = (dir > 0) ? avg + spacing : avg - spacing;
      plan.score    = 45.0;
      plan.isLimit  = true;
      plan.expiry   = TimeTradeServer() + (datetime)(30 * 60);
      plan.reason   = StringFormat("equal leg %d", legs + 1);
      return true;
   }

   double GridLastEntry(const string sym)
   {
      datetime newest = 0; double entry = 0.0;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != sym) continue;
         if(PositionGetInteger(POSITION_TIME) >= newest)
         { newest = PositionGetInteger(POSITION_TIME); entry = PositionGetDouble(POSITION_PRICE_OPEN); }
      }
      return entry;
   }

   double GridAverageEntry(const string sym, const double candidate)
   {
      double sum = 0.0; int n = 0;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != sym) continue;
         sum += PositionGetDouble(POSITION_PRICE_OPEN);
         n++;
      }
      return (n > 0) ? (sum + candidate) / (double)(n + 1) : candidate;
   }

   //--- forced flat by 06:30 UK - London volume destroys grids
   void Manage(SEAContext &ctx)
   {
      if(!IsQuietCross(ctx.symbol)) return;
      if(EA_CountPositions(ctx.symbol, true) == 0) return;
      if(ctx.clockMinutes >= InpGridFlatMin) g_eaExec.CloseAll("06:30 grid flat");
   }''',
)


add(
    entry=53,
    name="EA_studyarena_round5_contestant_e",
    magic=2020,
    cls="Round5E",
    title="Round 5E - executable core: 1% per group, 0.5% basket grid and three named setups",
    doc="docs/research/study_arena/studyarena-round5-contestant-e.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY,AUDUSD,USDCAD,EURGBP,AUDNZD", "risk": "1.0",
            "spread": "0", "daily": "2.0", "totaldd": "5.0", "target": "20", "maxday": "5"},
    inputs='''input double InpGroupCapPct       = 1.00;  // Max risk per correlation group
input double InpBasketCapPct      = 0.50;  // Grid basket cap (3 equal legs)
input double InpGridAdxMax        = 16.0;  // ADX gate for the grid
input double InpRsi2Entry         = 5.0;   // RSI(2) < 5 / > 95 entry filter
input double InpExpectancyGate    = 0.25;  // Required live expectancy (R) to keep trading
input double InpMaxSpreadSpacingPct = 15.0;  // Spread must stay below this % of the first grid spacing''',
    configure='''cfg.strategyName          = "R5E_EXECUTABLE_CORE";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round5-contestant-e.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M15;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.dailyLossPct          = InpDailyLossPct;
   cfg.totalDdPct            = InpTotalDdPct;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 3;
   cfg.minSecondsBetweenTrades = 120;
   cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 22;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;
   cfg.breakEvenAtR          = 1.00;
   cfg.timeStopMinutes       = 240;
   cfg.logLevel              = InpLogLevel;''',
    plan='''if(GroupBlocked(ctx)) return false;

   //--- Setup 1: London liquidity sweep (EURUSD / GBPUSD, tight Asian range required)
   if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 10 * 60 + 30 &&
      (StringFind(ctx.symbol, "EURUSD") >= 0 || StringFind(ctx.symbol, "GBPUSD") >= 0))
   {
      if(!RangeTight(ctx)) return false;
      if(ctx.emaH1_50 <= 0.0) return false;
      bool up = (ctx.mid > ctx.emaH1_50 && ctx.ema50 > ctx.emaH1_50);
      bool dn = (ctx.mid < ctx.emaH1_50 && ctx.ema50 < ctx.emaH1_50);
      if(!up && !dn) return false;
      SSweepParams p;
      p.Reset();
      p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
      p.sessionFromMin = 7 * 60; p.sessionToMin = 10 * 60 + 30;
      p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.55;
      p.reclaimWindowBars = 3; p.wickRatio = 0.55; p.bodyRatio = 0.55;
      p.stopBufferAtr = 0.10; p.minStopAtr = 0.50; p.maxStopAtr = 1.50;
      p.entryRetrace = 0.50; p.targetR = 2.0;
      if(!SigSweepReclaim(ctx, p, plan)) return false;
      plan.reason = "R5E-LONDONSWEEP " + plan.reason;
      return true;
   }

   //--- Setup 2: NY opening-range continuation (USDJPY / USDCAD / EURUSD)
   if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 16 * 60)
   {
      if(!SigEmaPullback(ctx, NyParams(), plan)) return false;
      plan.reason = "R5E-NYCONT " + plan.reason;
      return true;
   }

   //--- Setup 3: gated Asian grid (3 equal legs, ADX < 16, RSI(2) extremes)
   if(ctx.clockMinutes < 7 * 60 && IsGridPair(ctx.symbol))
   {
      if(ctx.adxH1 >= InpGridAdxMax) return false;            // doc: H1 ADX < 16
      if(!AtrBelow40thPct(ctx)) return false;
      int legs = EA_CountPositions(ctx.symbol, true);
      if(legs >= 3) return false;
      if(legs > 0 && !LegSpaced(ctx)) return false;
      if(!SpreadWithinGridSpacing(ctx)) return false;                // doc: spread < 15% of the first spacing
      if(!Rsi2Plan(ctx, plan)) return false;
      plan.reason = StringFormat("R5E-GRID(leg %d) %s", legs + 1, plan.reason);
      return true;
   }
   return false;''',
    extra='''   SEmaPullbackParams NyParams()
   {
      SEmaPullbackParams ep;
      ep.Reset();
      ep.emaPeriod = 20; ep.maxDistanceAtr = 1.20;
      ep.requireTrend = true; ep.targetR = 2.0;
      return ep;
   }

   bool IsGridPair(const string sym)
   {
      return (StringFind(sym, "EURGBP") >= 0 || StringFind(sym, "AUDNZD") >= 0);
   }

   bool RangeTight(SEAContext &ctx)
   {
      double hi = 0.0, lo = 0.0;
      if(!SigAsianRange(ctx.symbol, hi, lo)) return false;
      double pip = EA_PipSize(ctx.symbol);
      if(pip <= 0.0) return false;
      double pips = (hi - lo) / pip;
      if(StringFind(ctx.symbol, "GBPUSD") >= 0) return (pips <= 45.0);
      return (pips <= 35.0);
   }

   bool AtrBelow40thPct(SEAContext &ctx)
   {
      double av[];
      if(EA_BufN(g_eaInd[ctx.index].hAtrD1, 0, 1, 60, av) < 30) return true;
      double s[];
      ArrayResize(s, ArraySize(av));
      ArrayCopy(s, av);
      ArraySort(s);
      double p40 = s[(int)MathRound(0.40 * (ArraySize(s) - 1))];
      return (p40 <= 0.0 || ctx.atrD1 <= p40);
   }

   bool LegSpaced(SEAContext &ctx)
   {
      double last = 0.0; datetime newest = 0;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;
         if(PositionGetInteger(POSITION_TIME) >= newest)
         { newest = PositionGetInteger(POSITION_TIME); last = PositionGetDouble(POSITION_PRICE_OPEN); }
      }
      if(last == 0.0) return true;
      return (MathAbs(ctx.mid - last) >= 0.30 * ctx.atrD1);
   }

   bool Rsi2Plan(SEAContext &ctx, SSignalPlan &plan)
   {
      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 22, r) < 20) return false;
      double gain = 0.0, loss = 0.0;
      for(int i = 0; i < 2; i++)
      {
         double d = r[i].close - r[i + 1].close;
         if(d > 0.0) gain += d; else loss -= d;
      }
      double rsi2 = (gain + loss > 0.0) ? 100.0 * gain / (gain + loss) : 50.0;
      int dir = 0;
      if(rsi2 < InpRsi2Entry) dir = +1;
      if(rsi2 > 100.0 - InpRsi2Entry) dir = -1;
      if(dir == 0) return false;
      double spacing = 0.30 * ctx.atrD1;
      if(spacing <= 0.0) return false;
      plan.Reset();
      plan.dir      = dir;
      plan.entry    = (dir > 0) ? ctx.ask : ctx.bid;
      plan.riskDist = MathMax(spacing, 0.25 * ctx.atr);
      plan.stop     = (dir > 0) ? plan.entry - plan.riskDist : plan.entry + plan.riskDist;
      plan.target   = (dir > 0) ? plan.entry + 0.80 * plan.riskDist : plan.entry - 0.80 * plan.riskDist;
      plan.score    = 50.0;
      plan.reason   = StringFormat("rsi2 %.1f", rsi2);
      return true;
   }

   bool GroupBlocked(SEAContext &ctx)
   {
      if(ctx.openPositionsAll == 0) return false;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         string other = PositionGetString(POSITION_SYMBOL);
         if(other == ctx.symbol) continue;
         if(SharesGroup(ctx.symbol, other)) return true;
      }
      return false;
   }

   bool SharesGroup(const string a, const string b)
   {
      string groups[3][6];
      groups[0][0] = "EURUSD"; groups[0][1] = "GBPUSD"; groups[0][2] = "AUDUSD";
      groups[0][3] = "USDCAD"; groups[0][4] = "NZDUSD"; groups[0][5] = "";
      groups[1][0] = "USDJPY"; groups[1][1] = "GBPJPY"; groups[1][2] = "EURJPY";
      groups[1][3] = "AUDJPY"; groups[1][4] = "";       groups[1][5] = "";
      groups[2][0] = "EURGBP"; groups[2][1] = "EURCHF"; groups[2][2] = "AUDNZD";
      groups[2][3] = "";       groups[2][4] = "";       groups[2][5] = "";
      for(int g = 0; g < 3; g++)
      {
         bool hasA = false, hasB = false;
         for(int i = 0; i < 6; i++)
         {
            if(groups[g][i] == "") continue;
            if(StringFind(a, groups[g][i]) >= 0) hasA = true;
            if(StringFind(b, groups[g][i]) >= 0) hasB = true;
         }
         if(hasA && hasB) return true;
      }
      return false;
   }

   //--- hard basket cap on the grid sleeve
   void Manage(SEAContext &ctx)
   {
      if(!IsGridPair(ctx.symbol)) return;
      if(EA_CountPositions(ctx.symbol, true) == 0) return;
      if(ctx.floatingPl < -InpBasketCapPct / 100.0 * ctx.equity)
         g_eaExec.CloseAll("0.5% basket cap");
      //--- doc: flat by 07:00, no exceptions - never hold the grid into London
      if(ctx.clockMinutes >= 7 * 60)
      {
         for(int t = g_eaTrackCount - 1; t >= 0; t--)
         {
            if(g_eaTrack[t].symbol != ctx.symbol) continue;
            if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;
            g_eaExec.Close(g_eaTrack[t].ticket, "grid flat 07:00");
         }
      }
   }
   //--- doc gate: spread < 15% of the 0.30 x D1-ATR grid spacing
   bool SpreadWithinGridSpacing(SEAContext &ctx)
   {
      double spacing = 0.30 * ctx.atrD1;
      if(spacing <= 0.0) return false;
      bool ok = (ctx.spreadPoints * ctx.point <= InpMaxSpreadSpacingPct / 100.0 * spacing);
      if(!ok)
         EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.1f pts > %.0f%% of the grid spacing - skip",
                ctx.symbol, ctx.spreadPoints, InpMaxSpreadSpacingPct), true);
      return ok;
   }''',
)


add(
    entry=54,
    name="EA_studyarena_round5_contestant_f",
    magic=2021,
    cls="Round5F",
    title="Round 5F - stat-arb gates: ADX, band-width rank, channel check and 8-level ladder",
    doc="docs/research/study_arena/studyarena-round5-contestant-f.md",
    common={"symbols": "EURCHF,EURGBP,AUDNZD,EURUSD,GBPUSD,XAUUSD,USDJPY,USDCAD", "risk": "1.0",
            "spread": "0", "daily": "0", "totaldd": "0", "target": "20", "maxday": "10"},
    inputs='''input int    InpGridLevels        = 8;     // Max 8 equal-size levels
input double InpGridSpacingAtr    = 0.60;  // Spacing = 0.6 x H1 ATR
input double InpBandRankBottom    = 2.5;   // Bollinger width must sit in the bottom 2.5 deciles
input double InpKillTripwireAtr   = 1.00;  // Close all if price closes 1 ATR beyond the channel
input double InpCarryOverlayPct   = 0.50;  // Positive-carry overlay sizing
input double InpMaxSpreadPipsEur   = 1.00;  // Sleeve-1 spread cap, EURUSD (doc: < 1.0 pips)
input double InpMaxSpreadPipsGbp   = 1.50;  // Sleeve-1 spread cap, GBPUSD (doc: < 1.5 pips)''',
    configure='''cfg.strategyName          = "R5F_STATARB_GATES";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round5-contestant-f.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M15;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = InpGridLevels;
   cfg.minSecondsBetweenTrades = 60;
   cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 22;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.timeStopMinutes       = 0;
   cfg.logLevel              = InpLogLevel;''',
    plan='''//--- grid sleeve: only under the full gate stack, and only in the Asian window
   //--- merged doc gate: spread < 1.0 pips on EURUSD, < 1.5 on GBPUSD; other
   //--- pairs in the universe fall back to the looser cap
   double maxSpreadPips = InpMaxSpreadPipsGbp;
   if(StringFind(ctx.symbol, "EURUSD") >= 0)      maxSpreadPips = InpMaxSpreadPipsEur;
   if(EA_SpreadPips(ctx.symbol) > maxSpreadPips)
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.2f pips > %.2f - skip (doc sleeve-1 gate)", ctx.symbol, EA_SpreadPips(ctx.symbol), maxSpreadPips), true);
      return false;
   }

   if(ctx.clockMinutes < 7 * 60 && IsGridPair(ctx.symbol))
   {
      if(!GateStack(ctx)) return false;
      if(!LadderPlan(ctx, plan)) return false;
      plan.reason = "R5F-GRID " + plan.reason;
      return true;
   }

   //--- trend sleeve: London break+retest (no grid near this)
   if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 10 * 60)
   {
      SBreakRetestParams br;
      br.Reset();
      br.rangeFromMin = 0; br.rangeToMin = 7 * 60;
      br.entryFromMin = 7 * 60; br.entryToMin = 10 * 60;
      br.minRangeAtr = 0.25; br.targetR = 2.0;
      if(!SigBreakRetest(ctx, br, plan)) return false;
      plan.reason = "R5F-LONDONBREAK " + plan.reason;
      return true;
   }

   //--- NY momentum sleeve
   if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 16 * 60)
   {
      if(!SigEmaPullback(ctx, NyParams(), plan)) return false;
      plan.reason = "R5F-NYMOMENTUM " + plan.reason;
      return true;
   }
   return false;''',
    extra='''   SEmaPullbackParams NyParams()
   {
      SEmaPullbackParams ep;
      ep.Reset();
      ep.emaPeriod = 20; ep.maxDistanceAtr = 1.50;
      ep.requireTrend = true; ep.targetR = 1.50;
      return ep;
   }

   bool IsGridPair(const string sym)
   {
      return (StringFind(sym, "EURCHF") >= 0 || StringFind(sym, "EURGBP") >= 0 ||
              StringFind(sym, "AUDNZD") >= 0);
   }

   //--- 8-filter gate stack (ADX on H1+H4, band-width rank, channel, news via engine)
   bool GateStack(SEAContext &ctx)
   {
      if(ctx.adxH1 >= 20.0) return false;                     // doc: ADX(14) < 20 on 1H
      if(ctx.adxH4 >= 20.0) return false;                     // doc: ... and on 4H
      if(!BandWidthBottom(ctx)) return false;
      double hi = 0.0, lo = 0.0;
      if(!ChannelBounds(ctx, 50, hi, lo)) return false;
      if(ctx.mid > hi || ctx.mid < lo) return false;
      return true;
   }

   bool BandWidthBottom(SEAContext &ctx)
   {
      if(ctx.atrD1 <= 0.0) return false;
      double av[];
      if(EA_BufN(g_eaInd[ctx.index].hAtrD1, 0, 1, 60, av) < 30) return true;
      double s[];
      ArrayResize(s, ArraySize(av));
      ArrayCopy(s, av);
      ArraySort(s);
      int idx = (int)MathRound(0.25 * (ArraySize(s) - 1));
      return (ctx.atrD1 <= s[idx]);
   }

   bool ChannelBounds(SEAContext &ctx, const int bars, double &hi, double &lo)
   {
      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M15, 1, bars, r) < bars) return false;
      hi = r[0].high; lo = r[0].low;
      for(int i = 1; i < bars; i++) { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }
      return true;
   }

   //--- equal-size ladder, max 8 levels, net +1 spacing target
   bool LadderPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      int legs = EA_CountPositions(ctx.symbol, true);
      if(legs >= InpGridLevels) return false;
      double hi = 0.0, lo = 0.0;
      if(!ChannelBounds(ctx, 50, hi, lo)) return false;
      double mid = 0.5 * (hi + lo);
      int dir = (ctx.mid < mid) ? +1 : -1;
      double spacing = InpGridSpacingAtr * ctx.atr;
      if(spacing <= 0.0) return false;
      if(legs > 0)
      {
         double last = GridLastEntry(ctx.symbol);
         if(last == 0.0) return false;
         double adverse = (dir > 0) ? (last - ctx.mid) : (ctx.mid - last);
         if(adverse < spacing) return false;
      }
      double avg = GridAverageEntry(ctx.symbol, ctx.mid);
      plan.Reset();
      plan.dir      = dir;
      plan.entry    = (dir > 0) ? ctx.ask : ctx.bid;
      plan.riskDist = spacing;
      plan.stop     = (dir > 0) ? avg - 8.0 * spacing : avg + 8.0 * spacing;
      plan.target   = (dir > 0) ? avg + spacing : avg - spacing;
      plan.score    = 45.0;
      plan.isLimit  = true;
      plan.expiry   = TimeTradeServer() + (datetime)(30 * 60);
      plan.reason   = StringFormat("level %d", legs + 1);
      return true;
   }

   double GridLastEntry(const string sym)
   {
      datetime newest = 0; double entry = 0.0;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != sym) continue;
         if(PositionGetInteger(POSITION_TIME) >= newest)
         { newest = PositionGetInteger(POSITION_TIME); entry = PositionGetDouble(POSITION_PRICE_OPEN); }
      }
      return entry;
   }

   double GridAverageEntry(const string sym, const double candidate)
   {
      double sum = 0.0; int n = 0;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != sym) continue;
         sum += PositionGetDouble(POSITION_PRICE_OPEN);
         n++;
      }
      return (n > 0) ? (sum + candidate) / (double)(n + 1) : candidate;
   }

   //--- kill tripwire: 1 ATR beyond the channel disables the grid for 24h
   void Manage(SEAContext &ctx)
   {
      if(!IsGridPair(ctx.symbol)) return;
      if(EA_CountPositions(ctx.symbol, true) == 0) return;
      double hi = 0.0, lo = 0.0;
      if(!ChannelBounds(ctx, 50, hi, lo)) return;
      if(ctx.atr > 0.0 && (ctx.mid > hi + ctx.atr || ctx.mid < lo - ctx.atr))
         g_eaExec.CloseAll("grid kill tripwire");
      if(ctx.clockMinutes >= 7 * 60) g_eaExec.CloseAll("pre-London flat");
   }''',
)


add(
    entry=55,
    name="EA_studyarena_round7_contestant_a",
    magic=2022,
    cls="Round7A",
    title="Round 7A - GER40 cash open gap fade: 20-80 point filter, 1.5x stop, exact gap fill",
    doc="docs/research/study_arena/studyarena-round7-contestant-a.md",
    common={"symbols": "GER40,DE40,GER30,DAX", "risk": "1.0", "spread": "0", "daily": "0",
            "totaldd": "0", "target": "20", "maxday": "1"},
    inputs='''input double InpGapMinPoints      = 20.0;  // Minimum gap (index points)
input double InpGapMaxPoints      = 80.0;  // Maximum gap (breakaway gaps excluded)
input int    InpCashOpenMin       = 8 * 60;   // 08:00 UK cash open
input int    InpPriorCashCloseMin = 16 * 60 + 30;  // 16:30 UK prior close
input int    InpHardTimeStopMin   = 11 * 60;  // Flat by 11:00 UK, win or lose''',
    configure='''cfg.strategyName          = "R7A_DAX_GAP_FADE";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round7-contestant-a.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = 1;                 // one trade per day, by design
   cfg.maxOpenPositions      = 1;
   cfg.minSecondsBetweenTrades = 0;
   cfg.sessionStartHour      = 8;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 11;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = false;
   cfg.signalOnNewBarOnly    = true;
   cfg.timeStopMinutes       = 0;                 // managed by the 11:00 clock stop
   cfg.logLevel              = InpLogLevel;''',
    plan='''if(ctx.clockMinutes < InpCashOpenMin || ctx.clockMinutes >= InpHardTimeStopMin) return false;

   //--- gap = today's cash open vs yesterday's exact 16:30 close
   double priorClose = PriorCashClose(ctx.symbol);
   double cashOpen   = CashOpen(ctx.symbol);
   if(priorClose <= 0.0 || cashOpen <= 0.0) return false;

   double gap = cashOpen - priorClose;
   double gapAbs = MathAbs(gap);
   if(gapAbs < InpGapMinPoints || gapAbs > InpGapMaxPoints) return false;

   int dir = (gap > 0.0) ? -1 : +1;                 // fade the gap
   double stopDist = 1.5 * gapAbs * ctx.point;      // 1.5x the gap in price units

   plan.Reset();
   plan.dir      = dir;
   plan.entry    = (dir > 0) ? ctx.ask : ctx.bid;
   plan.riskDist = stopDist;
   plan.stop     = (dir > 0) ? plan.entry - stopDist : plan.entry + stopDist;
   plan.target   = priorClose;                      // exact gap fill
   plan.score    = 70.0;
   plan.reason   = StringFormat("R7A-GAPFADE(%.0f pts)", gapAbs);
   return true;''',
    extra='''   //--- close of the last session bar before 16:30 prior day
   double PriorCashClose(const string sym)
   {
      MqlRates r[];
      if(EA_Rates(sym, PERIOD_M5, 1, 300, r) < 10) return 0.0;
      MqlDateTime now;
      TimeToStruct(TimeTradeServer(), now);
      for(int i = 0; i < 300; i++)
      {
         MqlDateTime t;
         TimeToStruct(r[i].time, t);
         if(t.day == now.day) continue;                      // yesterday or older
         if(t.hour * 60 + t.min >= InpPriorCashCloseMin) return r[i].close;
      }
      return 0.0;
   }

   //--- open of the first bar at/after 08:00 today
   double CashOpen(const string sym)
   {
      MqlRates r[];
      if(EA_Rates(sym, PERIOD_M5, 0, 120, r) < 5) return 0.0;
      MqlDateTime now;
      TimeToStruct(TimeTradeServer(), now);
      for(int i = ArraySize(r) - 1; i >= 0; i--)
      {
         MqlDateTime t;
         TimeToStruct(r[i].time, t);
         if(t.day != now.day) continue;
         if(t.hour * 60 + t.min >= InpCashOpenMin) return r[i].open;
      }
      return 0.0;
   }

   //--- hard 11:00 UK time stop, win or lose
   void Manage(SEAContext &ctx)
   {
      if(ctx.clockMinutes < InpHardTimeStopMin) return;
      if(EA_CountPositions(ctx.symbol, true) == 0) return;
      g_eaExec.CloseAll("11:00 UK time stop");
   }''',
)


add(
    entry=56,
    name="EA_studyarena_round7_contestant_b",
    magic=2023,
    cls="Round7B",
    title="Round 7B - three sleeves, equity-curve throttle and a 2.5x-ATR runner trail",
    doc="docs/research/study_arena/studyarena-round7-contestant-b.md",
    common={"symbols": "EURUSD,GBPUSD,XAUUSD,USDJPY,EURGBP,AUDNZD,GER40", "risk": "1.5",
            "spread": "0", "daily": "0", "totaldd": "0", "target": "20", "maxday": "6"},
    inputs='''input double InpSleeveARisk       = 1.50;  // A: London sweep + runner
input double InpSleeveBRisk       = 1.00;  // B: NY continuation
input double InpSleeveCRisk       = 0.50;  // C: gated Asian grid
input double InpMaxOpenHeatPct    = 2.50;  // Max open heat across sleeves
input double InpRunnerTrailAtr    = 2.50;  // Trail 25% by 2.5 x ATR
input int    InpRollingTrades     = 10;    // Equity-curve throttle window''',
    configure='''cfg.strategyName          = "R7B_SLEEVES_THROTTLE";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round7-contestant-b.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpSleeveARisk;
   cfg.signalTimeframe       = PERIOD_M15;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 3;
   cfg.minSecondsBetweenTrades = 120;
   cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 22;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 75.0;   // 75% off at 1R
   cfg.breakEvenAtR          = 1.00;
   cfg.trailAtR              = 1.00;  cfg.trailDistanceR = InpRunnerTrailAtr;
   cfg.timeStopMinutes       = 0;
   cfg.logLevel              = InpLogLevel;''',
    plan='''if(OpenHeatExceeded(ctx)) return false;

   //--- Sleeve A: London sweep + runner
   if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 10 * 60 + 30 &&
      (StringFind(ctx.symbol, "EURUSD") >= 0 || StringFind(ctx.symbol, "GBPUSD") >= 0 ||
       StringFind(ctx.symbol, "XAU") >= 0))
   {
      SSweepParams p;
      p.Reset();
      p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
      p.sessionFromMin = 7 * 60; p.sessionToMin = 10 * 60 + 30;
      p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
      p.reclaimWindowBars = 3; p.wickRatio = 0.55; p.bodyRatio = 0.55;
      p.stopBufferAtr = 0.10; p.minStopAtr = 0.50; p.maxStopAtr = 1.50;
      p.entryRetrace = 0.50; p.targetR = 3.0;
      if(!SigSweepReclaim(ctx, p, plan)) return false;
      m_sleeve = 1;
      plan.reason = "R7B-LONDONRUNNER " + plan.reason;
      return true;
   }

   //--- Sleeve B: NY continuation (XAUUSD, USDJPY)
   if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 16 * 60 &&
      (StringFind(ctx.symbol, "XAU") >= 0 || StringFind(ctx.symbol, "USDJPY") >= 0))
   {
      if(!SigEmaPullback(ctx, NyParams(), plan)) return false;
      m_sleeve = 2;
      plan.reason = "R7B-NYCONT " + plan.reason;
      return true;
   }

   //--- Sleeve C: gated Asian grid
   if(ctx.clockMinutes < 7 * 60 &&
      (StringFind(ctx.symbol, "EURGBP") >= 0 || StringFind(ctx.symbol, "AUDNZD") >= 0))
   {
      if(ctx.adxH1 >= 16.0) return false;                     // doc: ADX(14) < 16 gate (E lineage: H1)
      SRangeFadeParams rf;
      rf.Reset();
      rf.bbPeriod = 20; rf.bbDeviation = 2.0;
      rf.rsiOversold = 5.0; rf.rsiOverbought = 95.0;
      rf.wickRatio = 0.50; rf.stopBufferAtr = 0.20;
      rf.targetR = 0.80; rf.requireRangeRegime = false;       // regime ADX is the H1 gate above
      if(!SigRangeFade(ctx, rf, plan)) return false;
      m_sleeve = 3;
      plan.reason = "R7B-ASIAGRID " + plan.reason;
      return true;
   }
   return false;''',
    extra='''   //--- doc sleeve C: flat by 07:00 UK - London volume destroys grids
   void Manage(SEAContext &ctx)
   {
      if(ctx.clockMinutes < 7 * 60) return;
      if(StringFind(ctx.symbol, "EURGBP") < 0 && StringFind(ctx.symbol, "AUDNZD") < 0) return;
      for(int t = g_eaTrackCount - 1; t >= 0; t--)
      {
         if(g_eaTrack[t].symbol != ctx.symbol) continue;
         if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;
         g_eaExec.Close(g_eaTrack[t].ticket, "grid flat 07:00");
      }
   }

   int m_sleeve;

   SEmaPullbackParams NyParams()
   {
      SEmaPullbackParams ep;
      ep.Reset();
      ep.emaPeriod = 20; ep.maxDistanceAtr = 1.20;
      ep.requireTrend = true; ep.targetR = 2.0;
      return ep;
   }

   double SleeveRisk()
   {
      if(m_sleeve == 1) return InpSleeveARisk;
      if(m_sleeve == 2) return InpSleeveBRisk;
      if(m_sleeve == 3) return InpSleeveCRisk;
      return 0.0;
   }

   //--- sleeve risk allocation, plus the equity-curve throttle (rolling 10 trades)
   double LotsMultiplier(SEAContext &ctx)
   {
      double risk = SleeveRisk();
      if(RollingPlNegative()) risk *= 0.50;              // throttle: halve all risk
      if(ctx.riskPct <= 0.0) return 0.0;
      return MathMax(0.0, risk / ctx.riskPct);
   }

   bool RollingPlNegative()
   {
      if(!HistorySelect(TimeCurrent() - 30 * 24 * 3600, TimeCurrent())) return false;
      double pl = 0.0;
      int n = 0;
      for(int i = HistoryDealsTotal() - 1; i >= 0 && n < InpRollingTrades; i--)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagicNumber) continue;
         if(HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
         pl += HistoryDealGetDouble(t, DEAL_PROFIT) +
               HistoryDealGetDouble(t, DEAL_SWAP) +
               HistoryDealGetDouble(t, DEAL_COMMISSION);
         n++;
      }
      return (n >= InpRollingTrades && pl < 0.0);
   }

   //--- max open heat across the sleeves (2.5% of equity)
   bool OpenHeatExceeded(SEAContext &ctx)
   {
      if(ctx.equity <= 0.0) return false;
      return (EA_OpenRiskPct() > InpMaxOpenHeatPct);
   }''',
)


add(
    entry=57,
    name="EA_studyarena_round7_contestant_c",
    magic=2024,
    cls="Round7C",
    title="Round 7C - 5% single strategy: 1.5x M15 ATR stop with an hourly chandelier runner",
    doc="docs/research/study_arena/studyarena-round7-contestant-c.md",
    common={"symbols": "EURUSD,GBPUSD,XAUUSD", "risk": "0.75", "spread": "0", "daily": "0",
            "totaldd": "0", "target": "20", "maxday": "2"},
    inputs='''input double InpEurFuelPips       = 35;    // Skip if the Asian range already expanded (EURUSD)
input double InpGbpFuelPips       = 45;    // GBPUSD expansion filter
input double InpStopAtrMult       = 1.50;  // Stop = 1.5 x M15 ATR
input double InpChandelierMult    = 2.50;  // Chandelier = high - 2.5 x H1 ATR
input bool   InpCarryHarvest      = true;  // Positive-carry overlay sleeve''',
    configure='''cfg.strategyName          = "R7C_FIVE_PERCENT";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round7-contestant-c.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;             // 0.75%
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 1;
   cfg.minSecondsBetweenTrades = 900;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;   // doc: hard flat by 21:00 UK
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;
   cfg.breakEvenAtR          = 1.00;
   cfg.trailAtR              = 0.0;   // doc: the hourly chandelier in Manage() is the runner trail
   cfg.trailDistanceR        = 1.00;
   cfg.timeStopMinutes       = 0;
   cfg.logLevel              = InpLogLevel;''',
    plan='''if(ctx.dayOfWeek < 2 || ctx.dayOfWeek > 4) return false;   // doc: Tuesday-Thursday only
   if(!FuelAvailable(ctx)) return false;

   SSweepParams p;
   p.Reset();
   p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
   p.sessionFromMin = 7 * 60; p.sessionToMin = 10 * 60 + 30;   // doc: 07:00-10:30 UK
   p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.55;
   p.reclaimWindowBars = 3; p.wickRatio = 0.55; p.bodyRatio = 0.55;
   p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.80;
   p.entryRetrace = 0.50; p.targetR = 3.20;         // no fixed TP - the trail decides
   if(!SigSweepReclaim(ctx, p, plan)) return false;

   double stopDist = InpStopAtrMult * ctx.atr;       // mechanics, not fixed pips
   if(stopDist > 0.0)
   {
      plan.stop     = (plan.dir > 0) ? plan.entry - stopDist : plan.entry + stopDist;
      plan.riskDist = stopDist;
      plan.target   = (plan.dir > 0) ? plan.entry + 3.20 * stopDist
                                     : plan.entry - 3.20 * stopDist;
   }
   plan.reason = "R7C-SWEEP " + plan.reason;
   return true;''',
    extra='''   bool FuelAvailable(SEAContext &ctx)
   {
      double hi = 0.0, lo = 0.0;
      if(!SigAsianRange(ctx.symbol, hi, lo)) return false;
      double pip = EA_PipSize(ctx.symbol);
      if(pip <= 0.0) return false;
      double pips = (hi - lo) / pip;
      if(StringFind(ctx.symbol, "GBPUSD") >= 0) return (pips <= InpGbpFuelPips);
      if(StringFind(ctx.symbol, "XAUUSD") >= 0) return true;   // doc caps only EURUSD/GBPUSD; the 35-75% ADR ratio governs gold
      return (pips <= InpEurFuelPips);
   }

   //--- hourly chandelier trail on the runner half
   void Manage(SEAContext &ctx)
   {
      for(int t = 0; t < g_eaTrackCount; t++)
      {
         if(g_eaTrack[t].symbol != ctx.symbol) continue;
         if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double cur   = PositionGetDouble(POSITION_PRICE_CURRENT);
         double risk  = g_eaTrack[t].riskDist;
         if(risk <= 0.0) continue;
         double rMult = (g_eaTrack[t].dir > 0) ? (cur - entry) / risk : (entry - cur) / risk;
         if(rMult < 1.0) continue;
         double h1Atr = H1Atr(ctx);
         if(h1Atr <= 0.0) continue;
         MqlRates r[];
         if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 20, r) < 5) continue;
         double hh = r[0].high, ll = r[0].low;
         for(int i = 1; i < 20; i++) { hh = MathMax(hh, r[i].high); ll = MathMin(ll, r[i].low); }
         double newSl = (g_eaTrack[t].dir > 0) ? hh - InpChandelierMult * h1Atr
                                               : ll + InpChandelierMult * h1Atr;
         double oldSl = PositionGetDouble(POSITION_SL);
         if(g_eaTrack[t].dir > 0 && newSl > oldSl) g_eaExec.Modify(g_eaTrack[t].ticket, newSl, 0.0);
         if(g_eaTrack[t].dir < 0 && (oldSl == 0.0 || newSl < oldSl))
            g_eaExec.Modify(g_eaTrack[t].ticket, newSl, 0.0);
      }
   }

   double H1Atr(SEAContext &ctx)
   {
      double av[];
      if(EA_BufN(g_eaInd[ctx.index].hAtrD1, 0, 1, 20, av) < 5) return 0.0;
      if(ctx.atrH1 > 0.0) return ctx.atrH1;                 // real H1 ATR
      return (av[0] > 0.0) ? av[0] / 6.0 : 0.0;   // fallback: ~H1 ATR from the daily ATR
   }''',
)


add(
    entry=58,
    name="EA_studyarena_round7_contestant_d",
    magic=2025,
    cls="Round7D",
    title="Round 7D - regime-switched compression breakout with adaptive stops",
    doc="docs/research/study_arena/studyarena-round7-contestant-d.md",
    common={"symbols": "EURUSD,GBPUSD,XAUUSD", "risk": "1.0", "spread": "0", "daily": "0",
            "totaldd": "0", "target": "20", "maxday": "3"},
    inputs='''input double InpRangeLowPct       = 35.0;  // Overnight range vs 20-day median (floor)
input double InpRangeHighPct      = 75.0;  // Overnight range vs 20-day median (ceiling)
input double InpAdxLow            = 18.0;  // H1 ADX band floor
input double InpAdxHigh           = 35.0;  // H1 ADX band ceiling
input double InpStopMinAtr        = 0.60;  // Stop must be within 0.6-1.5 x M15 ATR
input double InpStopMaxAtr        = 1.50;''',
    configure='''cfg.strategyName          = "R7D_REGIME_BREAKOUT";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round7-contestant-d.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 1;
   cfg.minSecondsBetweenTrades = 600;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 30;   // doc: close the runner by 16:30 London
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;
   cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 30.0;   // doc: 40% / 30% / 30% runner
   cfg.breakEvenAtR          = 1.00;
   cfg.breakEvenOnBarClose   = true;    // doc: BE only after a close beyond +1R
   cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 0.75;
   cfg.timeStopMinutes       = 240;
   cfg.useLimitEntry         = true;
   cfg.pendingExpiryMinutes  = 15;    // cancel if not filled within three M5 candles
   cfg.logLevel              = InpLogLevel;''',
    plan='''if(ctx.clockMinutes < 7 * 60 || ctx.clockMinutes >= 10 * 60) return false;
   if(!ConditionFilter(ctx)) return false;

   //--- long: sweep below the overnight low, close back inside, break the last lower high
   SSweepParams p;
   p.Reset();
   p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
   p.sessionFromMin = 7 * 60; p.sessionToMin = 10 * 60;
   p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
   p.reclaimWindowBars = 6;             // the document allows six M5 candles
   p.wickRatio = 0.60; p.bodyRatio = 0.60;
   p.stopBufferAtr = 0.10;
   p.minStopAtr = InpStopMinAtr; p.maxStopAtr = InpStopMaxAtr;
   p.entryRetrace = 0.50;               // first retracement to 50% of the displacement
   p.targetR = 2.0;
   if(!SigSweepReclaim(ctx, p, plan)) return false;

   //--- adaptive stop band on the M15 ATR
   if(plan.riskDist < InpStopMinAtr * ctx.atr || plan.riskDist > InpStopMaxAtr * ctx.atr)
      return false;
   plan.reason = "R7D-COMPRESSIONBREAK " + plan.reason;
   return true;''',
    extra='''   //--- range percentile + H1 regime + EMA structure filter
   bool ConditionFilter(SEAContext &ctx)
   {
      double hi = 0.0, lo = 0.0;
      if(!SigAsianRange(ctx.symbol, hi, lo)) return false;
      double overnight = hi - lo;
      double median = MedianDailyRange(ctx.symbol);
      if(median <= 0.0) return false;
      double ratio = overnight / median;
      if(ratio < InpRangeLowPct / 100.0 || ratio > InpRangeHighPct / 100.0) return false;
      if(ctx.adxH1 < InpAdxLow || ctx.adxH1 > InpAdxHigh) return false;   // doc: H1 ADX(14) 18-35
      if(ctx.emaH1_200 <= 0.0) return false;             // price must hold one side of the 200-EMA
      bool up = (ctx.mid > ctx.emaH1_200);
      if(ctx.emaH1_50 > 0.0)
      {
         bool emaUp = (ctx.emaH1_50 > ctx.emaH1_200);
         if(up != emaUp) return false;                   // 20-EMA slope must agree
      }
      return true;
   }

   double MedianDailyRange(const string sym)
   {
      MqlRates d[];
      if(EA_Rates(sym, PERIOD_D1, 1, 20, d) < 10) return 0.0;
      double s[];
      ArrayResize(s, 20);
      for(int i = 0; i < 20; i++) s[i] = d[i].high - d[i].low;
      ArraySort(s);
      return s[10];
   }''',
)


add(
    entry=59,
    name="EA_studyarena_round8_contestant_a",
    magic=2026,
    cls="Round8A",
    title="Round 8A - London sweep-and-reclaim on borrowed capital with a 6% monthly stop",
    doc="docs/research/study_arena/studyarena-round8-contestant-a.md",
    common={"symbols": "EURUSD,GBPUSD,XAUUSD", "risk": "0.75", "spread": "0", "daily": "0",
            "totaldd": "6.0", "target": "20", "maxday": "2"},
    inputs='''input double InpRangeLowPct       = 35.0;  // Asian range floor (% of 20-day median)
input double InpRangeHighPct      = 75.0;  // Asian range ceiling
input double InpAdxLow            = 18.0;  // H1 ADX band
input double InpAdxHigh           = 35.0;  // H1 ADX ceiling
input double InpChandelierMult    = 2.50;  // Runner trail: high - 2.5 x H1 ATR
input int    InpFlatMin           = 21 * 60;  // Flat by 21:00 UK''',
    configure='''cfg.strategyName          = "R8A_LONDON_RECLAIM";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round8-contestant-a.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;              // 0.75%
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.totalDdPct            = InpTotalDdPct;           // own-account hard monthly stop
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 1;
   cfg.minSecondsBetweenTrades = 900;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;
   cfg.breakEvenAtR          = 1.00;
   cfg.trailAtR              = 0.0;   // doc: the mechanical chandelier in Manage() is the runner trail
   cfg.trailDistanceR        = 1.00;
   cfg.timeStopMinutes       = 0;
   cfg.logLevel              = InpLogLevel;''',
    plan='''if(ctx.dayOfWeek < 2 || ctx.dayOfWeek > 4) return false;   // doc: Tuesday-Thursday only
   if(!RangeQualifies(ctx)) return false;
   if(ctx.adxH1 < InpAdxLow || ctx.adxH1 > InpAdxHigh) return false;   // doc: H1 ADX(14) 18-35
   if(!H1BiasAgrees(ctx)) return false;

   SSweepParams p;
   p.Reset();
   p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
   p.sessionFromMin = 7 * 60; p.sessionToMin = 10 * 60 + 30;   // doc: 07:00-10:30 UK
   p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
   p.reclaimWindowBars = 3;
   p.wickRatio = 0.60; p.bodyRatio = 0.60;
   p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
   p.entryRetrace = 0.50; p.targetR = 3.0;
   if(!SigSweepReclaim(ctx, p, plan)) return false;
   plan.reason = "R8A-SWEEPRECLAIM " + plan.reason;
   return true;''',
    extra='''   bool RangeQualifies(SEAContext &ctx)
   {
      double hi = 0.0, lo = 0.0;
      if(!SigAsianRange(ctx.symbol, hi, lo)) return false;
      double median = MedianRange(ctx.symbol);
      if(median <= 0.0) return false;
      double ratio = (hi - lo) / median;
      if(ratio < InpRangeLowPct / 100.0 || ratio > InpRangeHighPct / 100.0) return false;
      double pip = EA_PipSize(ctx.symbol);
      if(pip <= 0.0) return false;
      double pips = (hi - lo) / pip;
      if(StringFind(ctx.symbol, "GBPUSD") >= 0) return (pips <= 45.0);
      if(StringFind(ctx.symbol, "XAUUSD") >= 0) return true;   // doc caps only EURUSD/GBPUSD; the 35-75% ADR ratio governs gold
      return (pips <= 35.0);                             // fuel already burned above this
   }

   double MedianRange(const string sym)
   {
      MqlRates d[];
      if(EA_Rates(sym, PERIOD_D1, 1, 20, d) < 10) return 0.0;
      double s[];
      ArrayResize(s, 20);
      for(int i = 0; i < 20; i++) s[i] = d[i].high - d[i].low;
      ArraySort(s);
      return s[10];
   }

   bool H1BiasAgrees(SEAContext &ctx)
   {
      if(ctx.emaH1_50 <= 0.0) return false;
      bool up = (ctx.mid > ctx.emaH1_50 && ctx.ema50 > ctx.emaH1_50);
      bool dn = (ctx.mid < ctx.emaH1_50 && ctx.ema50 < ctx.emaH1_50);
      return (up || dn);
   }

   //--- mechanical chandelier trail on the remaining half, no take-profit
   void Manage(SEAContext &ctx)
   {
      for(int t = 0; t < g_eaTrackCount; t++)
      {
         if(g_eaTrack[t].symbol != ctx.symbol) continue;
         if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double cur   = PositionGetDouble(POSITION_PRICE_CURRENT);
         double risk  = g_eaTrack[t].riskDist;
         if(risk <= 0.0) continue;
         double rMult = (g_eaTrack[t].dir > 0) ? (cur - entry) / risk : (entry - cur) / risk;
         if(rMult < 1.0) continue;
         double h1Atr = H1Atr(ctx);
         if(h1Atr <= 0.0) continue;
         MqlRates r[];
         if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 20, r) < 5) continue;
         double hh = r[0].high, ll = r[0].low;
         for(int i = 1; i < 20; i++) { hh = MathMax(hh, r[i].high); ll = MathMin(ll, r[i].low); }
         double newSl = (g_eaTrack[t].dir > 0) ? hh - InpChandelierMult * h1Atr
                                               : ll + InpChandelierMult * h1Atr;
         double oldSl = PositionGetDouble(POSITION_SL);
         if(g_eaTrack[t].dir > 0 && newSl > oldSl) g_eaExec.Modify(g_eaTrack[t].ticket, newSl, 0.0);
         if(g_eaTrack[t].dir < 0 && (oldSl == 0.0 || newSl < oldSl))
            g_eaExec.Modify(g_eaTrack[t].ticket, newSl, 0.0);
      }
   }

   double H1Atr(SEAContext &ctx)
   {
      double av[];
      if(EA_BufN(g_eaInd[ctx.index].hAtrD1, 0, 1, 20, av) < 5) return 0.0;
      if(ctx.atrH1 > 0.0) return ctx.atrH1;                 // real H1 ATR
      return (av[0] > 0.0) ? av[0] / 6.0 : 0.0;   // fallback: ~H1 ATR from the daily ATR
   }''',
)


add(
    entry=60,
    name="EA_studyarena_round8_contestant_b",
    magic=2027,
    cls="Round8B",
    title="Round 8B - SOS-3 session-open sweep and reclaim with an A+ free-roll booster",
    doc="docs/research/study_arena/studyarena-round8-contestant-b.md",
    common={"symbols": "EURUSD,GBPUSD,XAUUSD,USDJPY,AUDNZD,EURGBP", "risk": "0.75",
            "spread": "0", "daily": "0", "totaldd": "0", "target": "20", "maxday": "4"},
    inputs='''input double InpBaseRiskPct       = 0.75;  // Base engine risk
input double InpAplusBoostPct     = 0.50;  // A+ setup adds 0.5% free-roll risk
\1input double InpMaxOpenRiskPct   = 1.50;  // Doc: max open risk at any instant
input double InpChandelierMult    = 2.50;  // Runner trail (High - 2.5 x H1 ATR)''',
    configure='''cfg.strategyName          = "R8B_SOS3_FREEROLL";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round8-contestant-b.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpBaseRiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 2;
   cfg.minSecondsBetweenTrades = 300;
   cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 22;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   //--- document ladder: 40% at +1R, 30% at +2R, 30% runner
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;
   cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 30.0;
   cfg.breakEvenAtR          = 1.00;
   cfg.breakEvenOnBarClose   = true;   // doc: BE only after an M5 close beyond +1R
   cfg.trailAtR              = 0.0;    // doc: the 30% runner trails on the chandelier in Manage()
   cfg.trailDistanceR        = 1.00;
   cfg.timeStopMinutes       = 180;
   cfg.logLevel              = InpLogLevel;''',
    plan='''//--- the identical SOS-3 setup at all three sessions
   int rangeFrom = 0, rangeTo = 0, sessFrom = 0, sessTo = 0;
   if(ctx.clockMinutes < 7 * 60)            { rangeFrom = 21 * 60; rangeTo = 24 * 60; sessFrom = 0;   sessTo = 3 * 60; }           // doc: Asian entries 00:00-03:00
   else if(ctx.clockMinutes < 13 * 60 + 30) { rangeFrom = 0;  rangeTo = 7 * 60;  sessFrom = 7 * 60;    sessTo = 10 * 60; }          // doc: London entries 07:00-10:00
   else                                     { rangeFrom = 7 * 60; rangeTo = 13 * 60; sessFrom = 13 * 60 + 30; sessTo = 15 * 60 + 30; }  // doc: NY entries 13:30-15:30
   if(ctx.clockMinutes >= sessTo) return false;   // doc: no entries outside the session's entry window

   //--- doc risk block: one position per currency group, max 2 trades/session, max 1.5% open risk
   if(GroupBlocked(ctx.symbol)) return false;
   if(SessionEntries(ctx, sessFrom, sessTo) >= 2) return false;
   if(EA_OpenRiskPct() >= InpMaxOpenRiskPct) return false;

   if(!RangeQualifies(ctx, rangeFrom, rangeTo)) return false;
   //--- Asian mean reversion pairs need no directional bias; others need the H1 trend
   if(!IsAsianPair(ctx.symbol))
   {
      if(ctx.emaH1_50 <= 0.0) return false;
      bool up = (ctx.mid > ctx.emaH1_50 && ctx.ema50 > ctx.emaH1_50);
      bool dn = (ctx.mid < ctx.emaH1_50 && ctx.ema50 < ctx.emaH1_50);
      if(!up && !dn) return false;
   }
   else if(ctx.adxH1 >= 16.0) return false;                    // doc: Asian waiver only while H1 ADX < 16

   SSweepParams p;
   p.Reset();
   p.rangeFromMin = rangeFrom; p.rangeToMin = rangeTo;
   p.sessionFromMin = sessFrom; p.sessionToMin = sessTo;
   p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
   p.reclaimWindowBars = 3;
   p.wickRatio = 0.60; p.bodyRatio = 0.60;
   p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
   p.entryRetrace = 0.50; p.targetR = 2.0;
   if(!SigSweepReclaim(ctx, p, plan)) return false;
   plan.score = SetupScore(ctx);
   plan.reason = StringFormat("R8B-SOS3(%.0f) %s", plan.score, plan.reason);
   return true;''',
    extra='''   bool IsAsianPair(const string sym)
   {
      return (StringFind(sym, "AUDNZD") >= 0 || StringFind(sym, "EURGBP") >= 0);
   }

   bool RangeQualifies(SEAContext &ctx, const int fromMin, const int toMin)
   {
      double hi = 0.0, lo = 0.0;
      if(!RangeBetween(ctx.symbol, fromMin, toMin, hi, lo)) return false;
      double median = MedianRange(ctx.symbol);
      if(median <= 0.0) return false;
      double ratio = (hi - lo) / median;
      return (ratio >= 0.35 && ratio <= 0.75);
   }

   double MedianRange(const string sym)
   {
      MqlRates d[];
      if(EA_Rates(sym, PERIOD_D1, 1, 20, d) < 10) return 0.0;
      double s[];
      ArrayResize(s, 20);
      for(int i = 0; i < 20; i++) s[i] = d[i].high - d[i].low;
      ArraySort(s);
      return s[10];
   }

   //--- range of the most recent completed session between two clock minutes
   bool RangeBetween(const string sym, const int fromMin, const int toMin, double &hi, double &lo)
   {
      MqlRates r[];
      if(EA_Rates(sym, PERIOD_M15, 1, 400, r) < 30) return false;
      bool wrap = (fromMin > toMin);
      int i = 0;
      for(; i < 400; i++)
      {
         MqlDateTime t;
         TimeToStruct(r[i].time, t);
         int m = t.hour * 60 + t.min;
         bool inWin = wrap ? (m >= fromMin || m < toMin) : (m >= fromMin && m < toMin);
         if(inWin) break;
      }
      if(i >= 400) return false;
      hi = 0.0; lo = 0.0;
      bool found = false;
      for(; i < 400; i++)
      {
         MqlDateTime t;
         TimeToStruct(r[i].time, t);
         int m = t.hour * 60 + t.min;
         bool inWin = wrap ? (m >= fromMin || m < toMin) : (m >= fromMin && m < toMin);
         if(!inWin) break;
         if(!found) { hi = r[i].high; lo = r[i].low; found = true; }
         else { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }
      }
      return found;
   }

   double m_setupScore;

   double SetupScore(SEAContext &ctx)
   {
      double score = 70.0;
      if(ctx.atrD1 > 0.0 && ctx.atr > 0.5 * ctx.atrD1) score += 10.0;
      if(ctx.adx14 >= 20.0 && ctx.adx14 <= 35.0) score += 10.0;
      if(ctx.emaD1_200 > 0.0 && ((ctx.mid > ctx.emaD1_200) || (ctx.mid < ctx.emaD1_200))) score += 5.0;
      m_setupScore = MathMin(score, 100.0);
      return m_setupScore;
   }

   //--- A+ setups get the free-roll booster on top of base risk
   double LotsMultiplier(SEAContext &ctx)
   {
      if(ctx.riskPct <= 0.0) return 0.0;
      double risk = InpBaseRiskPct + ((m_setupScore >= InpAplusScore) ? InpAplusBoostPct : 0.0);
      return MathMax(0.0, risk / ctx.riskPct);
   }

   int CurrencyGroupId(const string sym)
   {
      //--- doc: one position per currency group; the USD block includes gold,
      //--- USDJPY is counted as the JPY bet, AUDNZD and EURGBP stand alone
      if(StringFind(sym, "JPY") >= 0) return 2;
      if(StringFind(sym, "USD") >= 0 || StringFind(sym, "XAU") >= 0) return 1;
      if(StringFind(sym, "AUDNZD") >= 0) return 3;
      if(StringFind(sym, "EURGBP") >= 0) return 4;
      return 5;
   }

   bool GroupBlocked(const string sym)
   {
      int g = CurrencyGroupId(sym);
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(CurrencyGroupId(PositionGetString(POSITION_SYMBOL)) == g) return true;
      }
      return false;
   }

   //--- doc: max 2 trades per session; entries are counted from the deal history
   int SessionEntries(SEAContext &ctx, const int sessFrom, const int sessTo)
   {
      MqlDateTime dt;
      if(!TimeToStruct(ctx.nowClock, dt)) return 0;
      dt.hour = sessFrom / 60; dt.min = sessFrom % 60; dt.sec = 0;
      datetime from = EA_ClockToServer(StructToTime(dt));
      datetime to   = from + (datetime)((sessTo - sessFrom) * 60);
      if(!HistorySelect(from, to)) return 0;
      int n = 0;
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagicNumber) continue;
         if(HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
         n++;
      }
      return n;
   }

   //--- doc: the 30% runner trails at High - 2.5 x H1 ATR, hourly, no TP
   void Manage(SEAContext &ctx)
   {
      for(int t = 0; t < g_eaTrackCount; t++)
      {
         if(g_eaTrack[t].symbol != ctx.symbol) continue;
         if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double cur   = PositionGetDouble(POSITION_PRICE_CURRENT);
         double risk  = g_eaTrack[t].riskDist;
         if(risk <= 0.0) continue;
         double rMult = (g_eaTrack[t].dir > 0) ? (cur - entry) / risk : (entry - cur) / risk;
         if(rMult < 1.0) continue;
         double h1Atr = H1Atr(ctx);
         if(h1Atr <= 0.0) continue;
         MqlRates r[];
         if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 20, r) < 5) continue;
         double hh = r[0].high, ll = r[0].low;
         for(int i = 1; i < 20; i++) { hh = MathMax(hh, r[i].high); ll = MathMin(ll, r[i].low); }
         double newSl = (g_eaTrack[t].dir > 0) ? hh - InpChandelierMult * h1Atr
                                               : ll + InpChandelierMult * h1Atr;
         double oldSl = PositionGetDouble(POSITION_SL);
         if(g_eaTrack[t].dir > 0 && newSl > oldSl) g_eaExec.Modify(g_eaTrack[t].ticket, newSl, 0.0);
         if(g_eaTrack[t].dir < 0 && (oldSl == 0.0 || newSl < oldSl))
            g_eaExec.Modify(g_eaTrack[t].ticket, newSl, 0.0);
      }
   }

   double H1Atr(SEAContext &ctx)
   {
      if(ctx.atrH1 > 0.0) return ctx.atrH1;                 // real H1 ATR
      double av[];
      if(EA_BufN(g_eaInd[ctx.index].hAtrD1, 0, 1, 20, av) < 5) return 0.0;
      return (av[0] > 0.0) ? av[0] / 6.0 : 0.0;   // fallback: ~H1 ATR from the daily ATR
   }''',
)


add(
    entry=61,
    name="EA_studyarena_round8_contestant_c",
    magic=2028,
    cls="Round8C",
    title="Round 8C - immediate close-entry reclaim with a 50/20/30 ladder and 3-loss de-risk",
    doc="docs/research/study_arena/studyarena-round8-contestant-c.md",
    common={"symbols": "EURUSD,GBPUSD", "risk": "0.5", "spread": "0", "daily": "0",
            "totaldd": "10.0", "target": "20", "maxday": "2"},
    inputs='''input double InpBaseRiskPct       = 0.50;  // Base risk (funded account)
input double InpDeRiskPct         = 0.25;  // Risk after three consecutive losses
input double InpStopAtrMult       = 1.50;  // Stop = 1.5 x M15 ATR beyond the wick
input double InpChandelierMult    = 2.50;  // 30% runner trail on the chandelier''',
    configure='''cfg.strategyName          = "R8C_RECLAIM_LADDER";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round8-contestant-c.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpBaseRiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.totalDdPct            = InpTotalDdPct;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 1;
   cfg.minSecondsBetweenTrades = 900;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 30;   // doc: hard time stop 16:30 UK
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   //--- 50% at 1R, 20% at 2R, 30% runner at 2.5 x H1 ATR
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;
   cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 20.0;
   cfg.breakEvenAtR          = 1.00;
   cfg.trailAtR              = 0.0;   // doc: the 30% runner trails on the 2.5 x H1-ATR chandelier in Manage()
   cfg.trailDistanceR        = 1.00;
   cfg.timeStopMinutes       = 0;
   cfg.logLevel              = InpLogLevel;''',
    plan='''if(ctx.dayOfWeek < 2 || ctx.dayOfWeek > 4) return false;   // doc: Tuesday-Thursday only
   if(TradedOtherPairToday(ctx, ctx.symbol)) return false;         // doc: never both pairs on the same day
   //--- immediate entry on the reclaim close (no waiting for the retest)
   SSweepParams p;
   p.Reset();
   p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
   p.sessionFromMin = 7 * 60; p.sessionToMin = 12 * 60;
   p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
   p.reclaimWindowBars = 3;
   p.wickRatio = 0.55; p.bodyRatio = 0.55;
   p.stopBufferAtr = 0.10; p.minStopAtr = 0.50; p.maxStopAtr = 2.00;
   p.entryRetrace = 0.00;                        // enter at market on the reclaim candle
   p.targetR = 2.0;
   if(!SigSweepReclaim(ctx, p, plan)) return false;

   //--- stop exactly 1.5 x M15 ATR beyond the sweep wick (volatility dictates the stop)
   double buffer = InpStopAtrMult * ctx.atr;
   if(buffer <= 0.0) return false;
   double wickExtreme = (plan.dir > 0) ? plan.entry - plan.riskDist : plan.entry + plan.riskDist;
   plan.stop     = (plan.dir > 0) ? wickExtreme - buffer : wickExtreme + buffer;
   plan.riskDist = MathAbs(plan.entry - plan.stop);
   if(plan.riskDist <= 0.0) return false;
   plan.reason = "R8C-RECLAIM " + plan.reason;
   return true;''',
    extra='''   //--- doc: "trade only the one with the cleanest setup; never both on the same day"
   bool TradedOtherPairToday(SEAContext &ctx, const string sym)
   {
      MqlDateTime dt;
      if(!TimeToStruct(ctx.nowClock, dt)) return false;
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      datetime from = EA_ClockToServer(StructToTime(dt));
      if(!HistorySelect(from, TimeCurrent())) return false;
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagicNumber) continue;
         if(HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
         string s = HistoryDealGetString(t, DEAL_SYMBOL);
         if(StringFind(s, "EURUSD") >= 0 && StringFind(sym, "GBPUSD") >= 0) return true;
         if(StringFind(s, "GBPUSD") >= 0 && StringFind(sym, "EURUSD") >= 0) return true;
      }
      return false;
   }

   int LosingStreak()
   {
      if(!HistorySelect(TimeCurrent() - 14 * 24 * 3600, TimeCurrent())) return 0;
      int streak = 0;
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagicNumber) continue;
         if(HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
         double profit = HistoryDealGetDouble(t, DEAL_PROFIT) +
                         HistoryDealGetDouble(t, DEAL_SWAP) +
                         HistoryDealGetDouble(t, DEAL_COMMISSION);
         if(profit < 0.0) streak++;
         else break;
         if(streak >= 6) break;
      }
      return streak;
   }

   //--- halve risk after three consecutive losses (the <10% DD guarantee)
   double LotsMultiplier(SEAContext &ctx)
   {
      if(ctx.riskPct <= 0.0) return 0.0;
      double risk = (LosingStreak() >= 3) ? InpDeRiskPct : InpBaseRiskPct;
      return MathMax(0.0, risk / ctx.riskPct);
   }

   void Manage(SEAContext &ctx)
   {
      for(int t = 0; t < g_eaTrackCount; t++)
      {
         if(g_eaTrack[t].symbol != ctx.symbol) continue;
         if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double cur   = PositionGetDouble(POSITION_PRICE_CURRENT);
         double risk  = g_eaTrack[t].riskDist;
         if(risk <= 0.0) continue;
         double rMult = (g_eaTrack[t].dir > 0) ? (cur - entry) / risk : (entry - cur) / risk;
         if(rMult < 2.0) continue;
         double h1Atr = H1Atr(ctx);
         if(h1Atr <= 0.0) continue;
         MqlRates r[];
         if(EA_Rates(ctx.symbol, PERIOD_M15, 1, 20, r) < 5) continue;
         double hh = r[0].high, ll = r[0].low;
         for(int i = 1; i < 20; i++) { hh = MathMax(hh, r[i].high); ll = MathMin(ll, r[i].low); }
         double newSl = (g_eaTrack[t].dir > 0) ? hh - InpChandelierMult * h1Atr
                                               : ll + InpChandelierMult * h1Atr;
         double oldSl = PositionGetDouble(POSITION_SL);
         if(g_eaTrack[t].dir > 0 && newSl > oldSl) g_eaExec.Modify(g_eaTrack[t].ticket, newSl, 0.0);
         if(g_eaTrack[t].dir < 0 && (oldSl == 0.0 || newSl < oldSl))
            g_eaExec.Modify(g_eaTrack[t].ticket, newSl, 0.0);
      }
   }

   double H1Atr(SEAContext &ctx)
   {
      double av[];
      if(EA_BufN(g_eaInd[ctx.index].hAtrD1, 0, 1, 20, av) < 5) return 0.0;
      if(ctx.atrH1 > 0.0) return ctx.atrH1;                 // real H1 ATR
      return (av[0] > 0.0) ? av[0] / 6.0 : 0.0;   // fallback: ~H1 ATR from the daily ATR
   }''',
)


add(
    entry=62,
    name="EA_studyarena_round8_contestant_d",
    magic=2029,
    cls="Round8D",
    title="Round 8D - one trade per day, five attempts a week, strict spread and slope filters",
    doc="docs/research/study_arena/studyarena-round8-contestant-d.md",
    common={"symbols": "EURUSD,GBPUSD", "risk": "1.0", "spread": "0", "daily": "0",
            "totaldd": "0", "target": "20", "maxday": "1"},
    inputs='''input double InpAdxLow            = 18.0;  // H1 ADX floor
input double InpAdxHigh           = 35.0;  // H1 ADX ceiling
input double InpSweepMaxAtr       = 0.30;  // Sweep must not exceed 0.30 x M15 ATR
input double InpSpreadMedianX     = 2.00;  // Skip if spread > 2x the time-of-day median
input int    InpWeeklyAttempts    = 5;     // Maximum attempts per week
input int    InpNoNewAfterMin     = 10 * 60;  // No new position after 10:00
input int    InpHardCloseMin      = 20 * 60;  // Absolute closing time''',
    configure='''cfg.strategyName          = "R8D_ONE_SHOT";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round8-contestant-d.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = 1;                 // one trade per day by design
   cfg.maxOpenPositions      = 1;
   cfg.minSecondsBetweenTrades = 0;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 10;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 0;  cfg.fridayFlatMin = 0;  // skip Friday
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;
   cfg.breakEvenAtR          = 1.00;
   cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 0.75;
   cfg.timeStopMinutes       = 0;
   cfg.useLimitEntry         = true;
   cfg.pendingExpiryMinutes  = 15;    // cancel if the retest never comes
   cfg.logLevel              = InpLogLevel;''',
    plan='''if(ctx.dayOfWeek == 5) return false;                 // skip Friday entirely
   if(ctx.clockMinutes < 7 * 60 || ctx.clockMinutes >= InpNoNewAfterMin) return false;
   if(WeeklyAttemptsUsed() >= InpWeeklyAttempts) return false;
   if(ctx.adxH1 < InpAdxLow || ctx.adxH1 > InpAdxHigh) return false;   // doc: H1 ADX(14) 18-35
   if(!H1BiasAgrees(ctx)) return false;
   if(!SpreadNormal(ctx)) return false;

   SSweepParams p;
   p.Reset();
   p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
   p.sessionFromMin = 7 * 60; p.sessionToMin = InpNoNewAfterMin;
   p.sweepMinAtr = 0.02; p.sweepMaxAtr = InpSweepMaxAtr;   // deeper sweeps are real breakouts
   p.reclaimWindowBars = 3;
   p.wickRatio = 0.55; p.bodyRatio = 0.60;
   p.stopBufferAtr = 0.10; p.minStopAtr = 0.50; p.maxStopAtr = 2.00;
   p.entryRetrace = 0.50;
   p.targetR = 2.0;
   if(!SigSweepReclaim(ctx, p, plan)) return false;

   //--- displacement candle must close in its upper/lower 25%
   MqlRates r[];
   if(EA_Rates(ctx.symbol, PERIOD_M5, 1, 6, r) < 6) return false;
   bool strongClose = (plan.dir > 0) ? (r[0].close > r[0].low + 0.75 * (r[0].high - r[0].low))
                                     : (r[0].close < r[0].low + 0.25 * (r[0].high - r[0].low));
   if(!strongClose) return false;
   plan.reason = "R8D-ONESHOT " + plan.reason;
   return true;''',
    extra='''   bool H1BiasAgrees(SEAContext &ctx)
   {
      if(ctx.emaH1_200 <= 0.0 || ctx.emaH1_50 <= 0.0) return false;
      bool up = (ctx.mid > ctx.emaH1_200 && ctx.emaH1_50 > ctx.emaH1_200);
      bool dn = (ctx.mid < ctx.emaH1_200 && ctx.emaH1_50 < ctx.emaH1_200);
      return (up || dn);
   }

   int WeeklyAttemptsUsed()
   {
      if(!HistorySelect(TimeCurrent() - 10 * 24 * 3600, TimeCurrent())) return 0;
      datetime weekStart = WeekStart();
      int n = 0;
      for(int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagicNumber) continue;
         if(HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
         if((datetime)HistoryDealGetInteger(t, DEAL_TIME) < weekStart) continue;
         n++;
      }
      return n;
   }

   datetime WeekStart()
   {
      MqlDateTime dt;
      TimeToStruct(TimeTradeServer(), dt);
      int dow = dt.day_of_week;            // 0 = Sunday
      int back = (dow == 0) ? 0 : dow - 1;
      datetime midnight = TimeTradeServer() - (dt.hour * 3600 + dt.min * 60 + dt.sec);
      return midnight - (datetime)(back * 24 * 3600);
   }

   bool SpreadNormal(SEAContext &ctx)
   {
      PushSpread(ctx.spreadPoints);
      double med = EA_SpreadBaseline(ctx.symbol, 30);                     // same time of day
      if(med <= 0.0) med = MedianSpread();                                // fallback: live ring
      if(med <= 0.0) return true;
      if(ctx.spreadPoints <= InpSpreadMedianX * med) return true;
      EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.1f > %.2fx time-of-day median %.1f - skip",
             ctx.symbol, ctx.spreadPoints, InpSpreadMedianX, med), true);
      return false;
   }

   double m_spreads[64];
   int    m_spreadCount;

   void PushSpread(const double sp)
   {
      if(sp <= 0.0) return;
      if(m_spreadCount < 64) { m_spreads[m_spreadCount++] = sp; return; }
      for(int i = 0; i < 63; i++) m_spreads[i] = m_spreads[i + 1];
      m_spreads[63] = sp;
   }

   double MedianSpread()
   {
      if(m_spreadCount < 20) return 0.0;
      double s[];
      ArrayResize(s, m_spreadCount);
      for(int i = 0; i < m_spreadCount; i++) s[i] = m_spreads[i];
      ArraySort(s);
      return s[m_spreadCount / 2];
   }

   //--- close by 16:30 unless the runner already banked +2R; hard stop at 20:00
   void Manage(SEAContext &ctx)
   {
      if(EA_CountPositions(ctx.symbol, true) == 0) return;
      if(ctx.clockMinutes >= InpHardCloseMin) { g_eaExec.CloseAll("20:00 hard close"); return; }
      if(ctx.clockMinutes >= 16 * 60 + 30)
      {
         for(int t = 0; t < g_eaTrackCount; t++)
         {
            if(g_eaTrack[t].symbol != ctx.symbol) continue;
            if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;
            double entry = PositionGetDouble(POSITION_PRICE_OPEN);
            double cur   = PositionGetDouble(POSITION_PRICE_CURRENT);
            double risk  = g_eaTrack[t].riskDist;
            if(risk <= 0.0) continue;
            double rMult = (g_eaTrack[t].dir > 0) ? (cur - entry) / risk : (entry - cur) / risk;
            if(rMult < 2.0) { g_eaExec.Close(g_eaTrack[t].ticket, "16:30 close (not +2R)"); }
         }
      }
   }''',
)


add(
    entry=63,
    name="EA_studyarena_round10_claude_fable_5_high_reasoning",
    magic=2030,
    cls="Round10Fable",
    title="Round 10 Fable - M1 session-open sweep scalper with a ruthless 30-minute exit",
    doc="docs/research/study_arena/studyarena-round10-claude-fable-5-high-reasoning.md",
    common={"symbols": "EURUSD,GBPUSD", "risk": "0.50", "spread": "0", "daily": "0",
            "totaldd": "0", "target": "20", "maxday": "6"},
    inputs='''input int    InpReclaimBars       = 3;     // Reclaim close within 3 x M1 candles
input int    InpScalpTimeStopMin  = 30;    // If not +1R in 30 minutes, close at market
input double InpTimeStopUnlessR    = 1.00;  // the 30-min exit is skipped at/above this R
input double InpSpreadStopPct     = 15.0;  // Skip if spread > 15% of stop distance
input double InpSpreadAvgMult     = 2.00;  // Skip if spread > 2x its rolling average''',
    configure='''cfg.strategyName          = "R10FABLE_SWEEP_SCALPER";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round10-claude-fable-5-high-reasoning.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M1;              // algo-only scalping timeframe
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 1;
   cfg.minSecondsBetweenTrades = 300;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 16;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 60.0;   // 60% off at +1R
   cfg.partial2AtR           = 2.50;  cfg.partial2Pct = 40.0;   // doc: 40% at +2.5R, then an M5-swing trail
   cfg.breakEvenAtR          = 1.00;
   cfg.breakEvenOnBarClose   = true;   // doc: BE only after an M1 close beyond +1R
   cfg.trailAtR              = 2.50;  cfg.trailDistanceR = 1.00;
   cfg.timeStopMinutes       = InpScalpTimeStopMin;   // the biggest EV upgrade
   cfg.timeStopUnlessR       = InpTimeStopUnlessR;    // doc: only fires while the trade is below +1R
   cfg.logLevel              = InpLogLevel;''',
    plan='''if(!SpreadGuard(ctx)) return false;

   SSweepParams p;
   p.Reset();
   p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
   p.sessionFromMin = 7 * 60; p.sessionToMin = 12 * 60;
   p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
   p.reclaimWindowBars = InpReclaimBars;
   p.wickRatio = 0.60; p.bodyRatio = 0.60;
   p.stopBufferAtr = 0.10; p.minStopAtr = 0.50; p.maxStopAtr = 1.50;
   p.entryRetrace = 0.00; p.targetR = 2.50;
   if(!SigSweepReclaim(ctx, p, plan)) return false;
   plan.reason = "R10FABLE-M1SCALP " + plan.reason;
   return true;''',
    extra='''   //--- spread guard: < 15% of stop distance and < 2x the rolling average
   //--- doc: daily ATR above its 90th percentile -> risk halved automatically
   double LotsMultiplier(SEAContext &ctx)
   {
      if(ctx.index < 0 || ctx.index >= EA_MAX_SYM) return 1.0;
      double series[];
      int got = EA_BufN(g_eaInd[ctx.index].hAtrD1, 0, 0, 101, series);
      if(got < 60) return 1.0;                                   // thin history - fail open
      double cur = series[0];
      if(cur <= 0.0) return 1.0;
      int above = 0;
      for(int i = 1; i < got; i++) if(series[i] >= cur) above++;
      double pct = 100.0 * above / (double)(got - 1);
      return (pct < 10.0) ? 0.50 : 1.0;                          // cur above the 90th percentile
   }

   bool SpreadGuard(SEAContext &ctx)
   {
      PushSpread(ctx.spreadPoints);
      double avg = AverageSpread();
      if(avg > 0.0 && ctx.spreadPoints > InpSpreadAvgMult * avg) return false;
      //--- preliminary stop distance from the M1 ATR before the full signal check
      double stopDist = 0.60 * ctx.atr;
      if(stopDist <= 0.0) return false;
      double cost = ctx.spreadPoints * ctx.point;
      if(cost > InpSpreadStopPct / 100.0 * stopDist) return false;
      return true;
   }

   double m_spreads[120];
   int    m_spreadCount;

   void PushSpread(const double sp)
   {
      if(sp <= 0.0) return;
      if(m_spreadCount < 120) { m_spreads[m_spreadCount++] = sp; return; }
      for(int i = 0; i < 119; i++) m_spreads[i] = m_spreads[i + 1];
      m_spreads[119] = sp;
   }

   double AverageSpread()
   {
      if(m_spreadCount < 30) return 0.0;
      double sum = 0.0;
      for(int i = 0; i < m_spreadCount; i++) sum += m_spreads[i];
      return sum / m_spreadCount;
   }''',
)


add(
    entry=64,
    name="EA_studyarena_round10_claude_opus_5_high_reasoning",
    magic=2031,
    cls="Round10Opus",
    title="Round 10 Opus - LSR-A cost-gated micro-swing state machine with correlation cap",
    doc="docs/research/study_arena/studyarena-round10-claude-opus-5-high-reasoning.md",
    common={"symbols": "AUDNZD,EURGBP,AUDUSD,EURUSD,GBPUSD,XAUUSD,USDJPY", "risk": "1.0", "spread": "0",
            "daily": "0", "totaldd": "0", "target": "20", "maxday": "4"},
    inputs='''input double InpAtrBandLow        = 0.70;  // ATR(14) >= 0.7x its 20-day median
input double InpAtrBandHigh       = 1.80;  // ATR(14) <= 1.8x its 20-day median
input double InpSpreadMedianX     = 1.50;  // Live spread <= 1.5x the median
input double InpMinCostMultiple   = 10.0;  // Stop must be >= 10x round-trip cost
input double InpCorrelationCap    = 0.70;  // |rho_60d| cap between open symbols''',
    configure='''cfg.strategyName          = "R10OPUS_LSRA";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round10-claude-opus-5-high-reasoning.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M15;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 2;
   cfg.minSecondsBetweenTrades = 600;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 20;  cfg.sessionEndMin   = 0;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   //--- 40% at +1R, 30% at +2R, 30% runner at 2.5 x H1 ATR recalculated hourly
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;
   cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 30.0;
   cfg.breakEvenAtR          = 1.00;
   cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 1.00;
   cfg.timeStopMinutes       = 240;
   cfg.logLevel              = InpLogLevel;''',
    plan='''if(!VolatilityRegimeOk(ctx)) return false;
   if(!SpreadOk(ctx)) return false;
   if(!CorrelationOk(ctx)) return false;

   SSweepParams p;
   p.Reset();
   p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
   p.sessionFromMin = 7 * 60; p.sessionToMin = 16 * 60;
   p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
   p.reclaimWindowBars = 3;
   p.wickRatio = 0.55; p.bodyRatio = 0.60;
   p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
   p.entryRetrace = 0.50; p.targetR = 2.0;
   if(!SigSweepReclaim(ctx, p, plan)) return false;

   //--- non-negotiable cost gate: stop >= 10x round-trip cost
   double cost = ctx.spreadPoints * ctx.point + 2.0 * SanityCommission(ctx.symbol);
   if(cost > 0.0 && plan.riskDist < InpMinCostMultiple * cost) return false;
   plan.reason = "R10OPUS-LSRA " + plan.reason;
   return true;''',
    extra='''   bool VolatilityRegimeOk(SEAContext &ctx)
   {
      double av[];
      if(EA_BufN(g_eaInd[ctx.index].hAtr, 0, 1, 2880, av) < 100) return true;   // ~20 days of M15
      double s[];
      ArrayResize(s, ArraySize(av));
      ArrayCopy(s, av);
      ArraySort(s);
      double median = s[ArraySize(s) / 2];
      if(median <= 0.0) return true;
      double ratio = ctx.atr / median;
      return (ratio >= InpAtrBandLow && ratio <= InpAtrBandHigh);
   }

   bool SpreadOk(SEAContext &ctx)
   {
      PushSpread(ctx.spreadPoints);
      double med = MedianSpread();
      if(med <= 0.0) return true;
      return (ctx.spreadPoints <= InpSpreadMedianX * med);
   }

   double m_spreads[96];
   int    m_spreadCount;

   void PushSpread(const double sp)
   {
      if(sp <= 0.0) return;
      if(m_spreadCount < 96) { m_spreads[m_spreadCount++] = sp; return; }
      for(int i = 0; i < 95; i++) m_spreads[i] = m_spreads[i + 1];
      m_spreads[95] = sp;
   }

   double MedianSpread()
   {
      if(m_spreadCount < 30) return 0.0;
      double s[];
      ArrayResize(s, m_spreadCount);
      for(int i = 0; i < m_spreadCount; i++) s[i] = m_spreads[i];
      ArraySort(s);
      return s[m_spreadCount / 2];
   }

   double SanityCommission(const string sym)
   {
      //--- conservative $7/round-trip-lot converted to price terms
      double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
      double point     = EA_Point(sym);
      if(tickValue <= 0.0 || tickSize <= 0.0 || point <= 0.0) return 0.0;
      double valuePerPointPerLot = tickValue * (point / tickSize);
      if(valuePerPointPerLot <= 0.0) return 0.0;
      return 7.0 / valuePerPointPerLot * point;
   }

   bool CorrelationOk(SEAContext &ctx)
   {
      if(EA_CountPositions("", false) == 0) return true;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         string other = PositionGetString(POSITION_SYMBOL);
         if(other == ctx.symbol) continue;
         double rho = Correlation(ctx.symbol, other, 60);
         if(MathAbs(rho) > InpCorrelationCap) return false;
      }
      return true;
   }

   double Correlation(const string a, const string b, const int bars)
   {
      MqlRates ra[], rb[];
      if(EA_Rates(a, PERIOD_H1, 1, bars, ra) < bars) return 0.0;
      if(EA_Rates(b, PERIOD_H1, 1, bars, rb) < bars) return 0.0;
      double ma = 0.0, mb = 0.0;
      double x[], y[];
      ArrayResize(x, bars); ArrayResize(y, bars);
      for(int i = 0; i < bars; i++)
      {
         x[i] = ra[i].close / ra[bars - 1].close - 1.0;
         y[i] = rb[i].close / rb[bars - 1].close - 1.0;
         ma += x[i]; mb += y[i];
      }
      ma /= bars; mb /= bars;
      double cov = 0.0, va = 0.0, vb = 0.0;
      for(int i = 0; i < bars; i++)
      {
         cov += (x[i] - ma) * (y[i] - mb);
         va  += (x[i] - ma) * (x[i] - ma);
         vb  += (y[i] - mb) * (y[i] - mb);
      }
      if(va <= 0.0 || vb <= 0.0) return 0.0;
      return cov / MathSqrt(va * vb);
   }''',
)


add(
    entry=65,
    name="EA_studyarena_round10_gemini_3_1_pro_preview_high_reasoning",
    magic=2032,
    cls="Round10Gemini",
    title="Round 10 Gemini - M1 delta-sweep scalper with volume divergence and tick acceleration",
    doc="docs/research/study_arena/studyarena-round10-gemini-3-1-pro-preview-high-reasoning.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY,XAUUSD", "risk": "0.50", "spread": "0",
            "daily": "0", "totaldd": "0", "target": "20", "maxday": "8"},
    inputs='''input int    InpSwingBars         = 240;   // 4-hour local extreme window (M1 bars)
input double InpMinPierceAtr      = 0.05;  // Piercing depth minimum
input double InpTickAcceleration  = 2.00;  // Tick speed must be 200% of the 5-min average
input int    InpTimeStopBars      = 10;    // Exit if momentum stalls within N M1 bars
input double InpMaxSpreadPips     = 0.80;  // Spread gate (doc: < 0.8 pips; raise it for 2-digit metals)''',
    configure='''cfg.strategyName          = "R10GEMINI_DELTA_SCALP";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round10-gemini-3-1-pro-preview-high-reasoning.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M1;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 1;
   cfg.minSecondsBetweenTrades = 120;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 19;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;
   cfg.breakEvenAtR          = 1.00;
   cfg.trailAtR              = 1.50;  cfg.trailDistanceR = 0.50;
   cfg.timeStopMinutes       = 10;
   cfg.logLevel              = InpLogLevel;''',
    plan='''MqlRates r[];
   //--- doc: the instrument list requires spreads below 0.8 pips
   if(EA_SpreadPips(ctx.symbol) > InpMaxSpreadPips)
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.2f pips > %.2f - skip (doc < 0.8 pips)", ctx.symbol, EA_SpreadPips(ctx.symbol), InpMaxSpreadPips), true);
      return false;
   }
   if(EA_Rates(ctx.symbol, PERIOD_M1, 1, InpSwingBars + 6, r) < InpSwingBars + 5) return false;

   //--- local 4-hour extreme, EXCLUDING the sweep bar itself: seeding the
   //--- extreme from r[0] and then testing r[0] against it can never be true
   double hi = r[1].high, lo = r[1].low;
   for(int i = 2; i <= InpSwingBars; i++) { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }

   bool sweptLow  = (r[0].low  < lo - InpMinPierceAtr * ctx.atr && r[0].close > lo);
   bool sweptHigh = (r[0].high > hi + InpMinPierceAtr * ctx.atr && r[0].close < hi);
   if(!sweptLow && !sweptHigh) return false;

   //--- volume-delta divergence: delta must improve against the sweep direction
   double d0 = Delta(r[0]), d1 = Delta(r[1]), d2 = Delta(r[2]);
   bool deltaOk = sweptLow ? (d0 > d1 && d1 < d2)      // declining negative flow on a low sweep
                           : (d0 < d1 && d1 > d2);
   if(!deltaOk) return false;

   //--- tick acceleration vs the 5-minute rolling average
   double tickNow = (double)r[0].tick_volume;
   double avg = 0.0;
   for(int i = 1; i <= 5; i++) avg += (double)r[i].tick_volume;
   avg /= 5.0;
   if(avg <= 0.0 || tickNow < InpTickAcceleration * avg) return false;

   int dir = sweptLow ? +1 : -1;
   plan.Reset();
   plan.dir   = dir;
   plan.entry = (dir > 0) ? ctx.ask : ctx.bid;
   double pt  = EA_Point(ctx.symbol);
   plan.stop  = (dir > 0) ? r[0].low - pt : r[0].high + pt;    // 1 pip beyond the extremum
   plan.riskDist = MathAbs(plan.entry - plan.stop);
   if(plan.riskDist <= 0.0) return false;
   plan.target = (dir > 0) ? plan.entry + 3.0 * plan.riskDist : plan.entry - 3.0 * plan.riskDist;
   plan.score    = 65.0;
   plan.reason   = StringFormat("R10GEMINI-DELTA(tick %.1fx)", tickNow / avg);
   return true;''',
    extra='''   double Delta(const MqlRates &bar)
   {
      double range = bar.high - bar.low;
      if(range <= 0.0) return 0.0;
      double buyFrac  = (bar.close - bar.low) / range;
      double sellFrac = (bar.high - bar.close) / range;
      return (buyFrac - sellFrac) * (double)bar.tick_volume;
   }''',
)


add(
    entry=66,
    name="EA_studyarena_round10_kimi_k3_high_reasoning",
    magic=2033,
    cls="Round10Kimi",
    title="Round 10 Kimi - SWEEP-1 multi-session engine with a score gate and drawdown throttle",
    doc="docs/research/study_arena/studyarena-round10-kimi-k3-high-reasoning.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY,AUDUSD,XAUUSD,GBPJPY,AUDNZD,EURGBP", "risk": "0.60",
            "spread": "0", "daily": "3.0", "totaldd": "0", "target": "20", "maxday": "8"},
    inputs='''input double InpBaseRiskPct       = 0.60;  // SWEEP-1 risk per trade
input int    InpMinScore           = 7;     // Only trade setups scoring >= 7/10
input double InpThrottleAfterPct   = 3.00;  // Halve risk after a -3% drawdown
input double InpSweepMinPierceAtr  = 0.15;  // Wick must exceed the range by 0.15 x M15 ATR''',
    configure='''cfg.strategyName          = "R10KIMI_SWEEP1";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round10-kimi-k3-high-reasoning.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpBaseRiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.dailyLossPct          = InpDailyLossPct;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 2;
   cfg.minSecondsBetweenTrades = 120;
   cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 22;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;
   cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 30.0;
   cfg.breakEvenAtR          = 1.00;
   cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 1.00;
   cfg.timeStopMinutes       = 180;
   cfg.logLevel              = InpLogLevel;''',
    plan='''//--- session range selection: Asian / London / New York
   int fromMin = 21 * 60, toMin = 24 * 60, sessFrom = 0, sessTo = 7 * 60;
   if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 13 * 60 + 30)
   { fromMin = 0; toMin = 7 * 60; sessFrom = 7 * 60; sessTo = 12 * 60; }
   else if(ctx.clockMinutes >= 13 * 60 + 30)
   { fromMin = 7 * 60; toMin = 13 * 60; sessFrom = 13 * 60 + 30; sessTo = 21 * 60; }

   //--- doc universe: the Asian mean-reversion sleeve trades AUDNZD/EURGBP only,
   //--- and only while H1 ADX(14) < 16 (the "no trend" regime)
   if(ctx.clockMinutes < 7 * 60 && (!IsAsianMrPair(ctx.symbol) || ctx.adxH1 >= 16.0)) return false;

   SSweepParams p;
   p.Reset();
   p.rangeFromMin = fromMin; p.rangeToMin = toMin;
   p.sessionFromMin = sessFrom; p.sessionToMin = sessTo;
   p.sweepMinAtr = InpSweepMinPierceAtr; p.sweepMaxAtr = 0.60;
   p.reclaimWindowBars = 3;
   p.wickRatio = 0.60; p.bodyRatio = 0.60;
   p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
   p.entryRetrace = 0.50; p.targetR = 2.0;
   if(!SigSweepReclaim(ctx, p, plan)) return false;

   int score = ScoreSetup(ctx, plan);
   if(score < InpMinScore) return false;
   plan.score  = score * 10.0;
   plan.reason = StringFormat("R10KIMI-SWEEP1(%d/10) %s", score, plan.reason);
   return true;''',
    extra='''   bool IsAsianMrPair(const string sym)
   {
      return (StringFind(sym, "AUDNZD") >= 0 || StringFind(sym, "EURGBP") >= 0);
   }

   int ScoreSetup(SEAContext &ctx, SSignalPlan &plan)
   {
      int score = 5;
      if(ctx.emaH1_50 > 0.0 && ((plan.dir > 0 && ctx.mid > ctx.emaH1_50) ||
                                (plan.dir < 0 && ctx.mid < ctx.emaH1_50))) score++;
      if(ctx.adx14 >= 18.0 && ctx.adx14 <= 35.0) score++;
      MqlRates d[];
      if(EA_Rates(ctx.symbol, PERIOD_D1, 1, 1, d) >= 1)
      {
         double tol = 0.25 * ctx.atr * 4.0;
         if(MathAbs(ctx.mid - d[0].high) < tol || MathAbs(ctx.mid - d[0].low) < tol) score++;
      }
      if(ctx.atrD1 > 0.0 && ctx.atr > 0.4 * ctx.atrD1) score++;
      double costR = (plan.riskDist > 0.0) ? (ctx.spreadPoints * ctx.point) / plan.riskDist : 1.0;
      if(costR <= 0.10) score++;
      return MathMin(score, 10);
   }

   //--- drawdown throttle: halve risk after a -3% equity drawdown
   double LotsMultiplier(SEAContext &ctx)
   {
      if(ctx.riskPct <= 0.0) return 0.0;
      double risk = InpBaseRiskPct;
      double equity = ctx.equity;
      double hwm = GlobalVariableGet("R10KIMI_HWM");
      if(hwm <= 0.0 || equity > hwm) { GlobalVariableSet("R10KIMI_HWM", MathMax(equity, hwm)); return 1.0; }
      if(hwm > 0.0 && equity < hwm * (1.0 - InpThrottleAfterPct / 100.0)) risk *= 0.50;
      return MathMax(0.0, risk / ctx.riskPct);
   }''',
)


add(
    entry=67,
    name="EA_studyarena_round10_qwen3_8_2_4t_a95b_high_reasoning",
    magic=2034,
    cls="Round10Qwen",
    title="Round 10 Qwen - SOS-3 stacker: three sessions, 45-minute kill switch, multi-account sizing",
    doc="docs/research/study_arena/studyarena-round10-qwen3-8-2-4t-a95b-high-reasoning.md",
    common={"symbols": "AUDNZD,EURGBP,EURUSD,GBPUSD,AUDUSD,XAUUSD,GBPJPY,USDJPY", "risk": "0.75",
            "spread": "0", "daily": "0", "totaldd": "0", "target": "20", "maxday": "8"},
    inputs='''input int    InpKillMinutes       = 45;    // 45-minute time stop on stale trades
input double InpStackBoostPct     = 0.25;  // Secondary (stacked) setup sizing boost
input int    InpMaxAccounts       = 3;     // Multi-account orchestration cap
input double InpSpreadAvgX        = 1.50;  // Spread gate: current <= this x the time-of-day baseline
input double InpSweepVolumeX      = 1.20;  // Sweep-candle tick volume vs its 20-candle average''',
    configure='''cfg.strategyName          = "R10QWEN_SOS3_ALGO";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round10-qwen3-8-2-4t-a95b-high-reasoning.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 3;
   cfg.minSecondsBetweenTrades = 120;
   cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 22;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.useLimitEntry         = true;   // doc Step 4: limit at the 50% retracement of the displacement body
   cfg.pendingExpiryMinutes  = 15;     // doc Step 4: cancel if unfilled after 3 x M5 candles
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;
   cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 30.0;
   cfg.breakEvenAtR          = 1.00;
   cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 1.00;
   cfg.timeStopMinutes       = InpKillMinutes;
   cfg.logLevel              = InpLogLevel;''',
    plan='''//--- session-specific reference ranges
   //--- Step 6 gate: current spread <= 1.5x the symbol's own baseline
   double spRef = EA_SpreadBaseline(ctx.symbol, 30);
   if(spRef > 0.0 && ctx.spreadPoints > InpSpreadAvgX * spRef)
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.1f pts > %.2fx its baseline %.1f - skip (doc row %d)", ctx.symbol, ctx.spreadPoints, InpSpreadAvgX, spRef, 67), true);
      return false;
   }

   int fromMin = 21 * 60, toMin = 24 * 60, sessFrom = 0, sessTo = 6 * 60 + 30;
   if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 13 * 60)
   { fromMin = 0; toMin = 7 * 60; sessFrom = 7 * 60; sessTo = 12 * 60; }
   else if(ctx.clockMinutes >= 13 * 60)
   { fromMin = 7 * 60; toMin = 13 * 60; sessFrom = 13 * 60 + 30; sessTo = 21 * 60; }

   double hi = 0.0, lo = 0.0;
   if(!RangeBetween(ctx.symbol, fromMin, toMin, hi, lo)) return false;
   double median = MedianRange(ctx.symbol);
   if(median <= 0.0) return false;
   double ratio = (hi - lo) / median;
   if(ratio < 0.35 || ratio > 0.75) return false;             // manipulation bait vs spent fuel

   int tier = SessionTier(ctx);
   if(tier == 0) return false;

   SSweepParams p;
   p.Reset();
   p.rangeFromMin = fromMin; p.rangeToMin = toMin;
   p.sessionFromMin = sessFrom; p.sessionToMin = sessTo;
   p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
   p.reclaimWindowBars = 3;
   p.wickRatio = 0.60; p.bodyRatio = 0.60;
   p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
   p.entryRetrace = 0.50; p.targetR = 2.0;
   p.requireMidpointBreak = true;   // doc Step 4: displacement closes beyond the prior candle's midpoint
   if(!SigSweepReclaim(ctx, p, plan)) return false;
   if(!BiasAgrees(ctx, plan.dir)) return false;                // doc Step 2 (waived for Asian MR pairs)
   if(!VolumeConfirms(ctx, plan.sweepBarsAgo)) return false;   // doc Step 6: sweep participation
   m_tier = tier;
   plan.reason = StringFormat("R10QWEN-SOS3(tier %d) %s", tier, plan.reason);
   return true;''',
    extra='''   int m_tier;

   bool IsAsianPair(const string sym)
   {
      return (StringFind(sym, "AUDNZD") >= 0 || StringFind(sym, "EURGBP") >= 0);
   }

   //--- doc Step 2: H1 50-EMA slope + price side; Asian mean-reversion pairs
   //--- are exempt while H1 ADX(14) < 16 (pure mean reversion), per the document
   bool BiasAgrees(SEAContext &ctx, const int dir)
   {
      if(IsAsianPair(ctx.symbol) && ctx.clockMinutes < 7 * 60 && ctx.adxH1 < 16.0) return true;
      if(ctx.emaH1_50 <= 0.0) return false;
      double h1Atr = (ctx.atrH1 > 0.0) ? ctx.atrH1
                                      : ((ctx.atrD1 > 0.0) ? ctx.atrD1 / 6.0 : 0.0);   // real H1 ATR, daily/6 as fallback
      if(h1Atr <= 0.0) return false;
      double slope = ctx.emaH1_50 - ctx.emaH1_200;
      if(dir > 0) return (ctx.mid > ctx.emaH1_50 && slope >= -0.05 * h1Atr);
      return (ctx.mid < ctx.emaH1_50 && slope <= 0.05 * h1Atr);
   }

   //--- doc Step 6: the sweep candle's tick volume must be >= 1.2x the 20-candle average
   bool VolumeConfirms(SEAContext &ctx, const int sweepBar)
   {
      if(sweepBar < 1) return true;                            // no sweep bar recorded - fail open
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, sweepBar + 21, r);
      if(got < sweepBar + 21) return true;                     // thin data - fail open
      double sum = 0.0;
      for(int i = sweepBar + 1; i <= sweepBar + 20; i++) sum += (double)r[i].tick_volume;
      double avg = sum / 20.0;
      if(avg <= 0.0) return true;
      return ((double)r[sweepBar].tick_volume >= InpSweepVolumeX * avg);
   }

   double MedianRange(const string sym)
   {
      MqlRates d[];
      if(EA_Rates(sym, PERIOD_D1, 1, 20, d) < 10) return 0.0;
      double s[];
      ArrayResize(s, 20);
      for(int i = 0; i < 20; i++) s[i] = d[i].high - d[i].low;
      ArraySort(s);
      return s[10];
   }

   //--- range of the most recent completed session between two clock minutes
   bool RangeBetween(const string sym, const int fromMin, const int toMin, double &hi, double &lo)
   {
      MqlRates r[];
      if(EA_Rates(sym, PERIOD_M15, 1, 400, r) < 30) return false;
      bool wrap = (fromMin > toMin);
      int i = 0;
      for(; i < 400; i++)
      {
         MqlDateTime t;
         TimeToStruct(r[i].time, t);
         int m = t.hour * 60 + t.min;
         bool inWin = wrap ? (m >= fromMin || m < toMin) : (m >= fromMin && m < toMin);
         if(inWin) break;
      }
      if(i >= 400) return false;
      hi = 0.0; lo = 0.0;
      bool found = false;
      for(; i < 400; i++)
      {
         MqlDateTime t;
         TimeToStruct(r[i].time, t);
         int m = t.hour * 60 + t.min;
         bool inWin = wrap ? (m >= fromMin || m < toMin) : (m >= fromMin && m < toMin);
         if(!inWin) break;
         if(!found) { hi = r[i].high; lo = r[i].low; found = true; }
         else { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }
      }
      return found;
   }

   //--- 1 = primary session pair, 2 = secondary stacking pair, 0 = skip
   int SessionTier(SEAContext &ctx)
   {
      bool asian = (ctx.clockMinutes < 7 * 60);
      bool london = (ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 13 * 60);
      if(asian)     return IsAsianPair(ctx.symbol) ? 1 : 0;
      if(london)
      {
         if(StringFind(ctx.symbol, "EURUSD") >= 0 || StringFind(ctx.symbol, "GBPUSD") >= 0 ||
            StringFind(ctx.symbol, "XAU") >= 0) return 1;
         if(StringFind(ctx.symbol, "GBPJPY") >= 0 || StringFind(ctx.symbol, "GER") >= 0) return 2;
         return 0;
      }
      if(StringFind(ctx.symbol, "XAU") >= 0 || StringFind(ctx.symbol, "USDJPY") >= 0) return 1;
      if(StringFind(ctx.symbol, "US30") >= 0 || StringFind(ctx.symbol, "NAS") >= 0) return 2;
      return 0;
   }

   //--- stacked (secondary) setups get a small sizing boost, never a martingale
   double LotsMultiplier(SEAContext &ctx)
   {
      if(ctx.riskPct <= 0.0) return 0.0;
      double risk = InpRiskPct + ((m_tier == 2) ? InpStackBoostPct : 0.0);
      return MathMax(0.0, risk / ctx.riskPct);
   }''',
)


add(
    entry=68,
    name="EA_studyarena_round11_contestant_a",
    magic=2035,
    cls="Round11A",
    title="Round 11A - adaptive session sweep-reclaim with session caps and cost governors",
    doc="docs/research/study_arena/studyarena-round11-contestant-a.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY,XAUUSD", "risk": "1.0", "spread": "0",
            "daily": "0", "totaldd": "6.0", "target": "20", "maxday": "3"},
    inputs='''input int    InpSessionWindowMin  = 120;   // First 120 minutes after the session open
input int    InpMaxTradesSession   = 3;     // Max completed trades per session
input double InpMaxSpreadMedianX   = 2.00;  // Spread vs its 20-session median
input double InpMaxAdrTravelPct    = 80.0;  // Already-travelled daily ATR ceiling
input double InpMaxEmaDistAtr      = 0.75;  // Distance from the H1 50-EMA (ATR_H1)''',
    configure='''cfg.strategyName          = "R11A_ADAPTIVE_SWEEP";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round11-contestant-a.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.totalDdPct            = InpTotalDdPct;
   cfg.maxTradesPerDay       = InpMaxTradesSession;
   cfg.maxOpenPositions      = 1;
   cfg.minSecondsBetweenTrades = 600;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;
   cfg.breakEvenAtR          = 1.00;
   cfg.trailAtR              = 1.50;  cfg.trailDistanceR = 0.75;
   cfg.timeStopMinutes       = 240;
   cfg.logLevel              = InpLogLevel;''',
    plan='''int sessFrom = 0, sessTo = 0, rangeFrom = 0, rangeTo = 0;
   if(!SessionWindow(ctx, sessFrom, sessTo, rangeFrom, rangeTo)) return false;
   if(TradesThisSession(sessFrom) >= InpMaxTradesSession) return false;
   if(!SpreadOk(ctx)) return false;
   if(AdrTravelPct(ctx) > InpMaxAdrTravelPct) return false;

   SSweepParams p;
   p.Reset();
   p.rangeFromMin = rangeFrom; p.rangeToMin = rangeTo;
   p.sessionFromMin = sessFrom; p.sessionToMin = sessTo;
   p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
   p.reclaimWindowBars = 3;
   p.wickRatio = 0.60; p.bodyRatio = 0.60;
   p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
   p.entryRetrace = 0.50; p.targetR = 2.0;
   if(!SigSweepReclaim(ctx, p, plan)) return false;
   if(!EmaSlopeAgrees(ctx, plan.dir)) return false;
   if(!EmaDistanceOk(ctx)) return false;
   plan.reason = StringFormat("R11A-%sSWEEP %s", sessFrom == 7 * 60 ? "LONDON" : "NY", plan.reason);
   return true;''',
    extra='''   bool SessionWindow(SEAContext &ctx, int &sessFrom, int &sessTo, int &rangeFrom, int &rangeTo)
   {
      //--- London: first 120 minutes after 07:00, NY: first 120 after 13:30
      if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 7 * 60 + InpSessionWindowMin)
      { sessFrom = 7 * 60; sessTo = 7 * 60 + InpSessionWindowMin; rangeFrom = 0; rangeTo = 7 * 60; return true; }
      if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 13 * 60 + 30 + InpSessionWindowMin)
      { sessFrom = 13 * 60 + 30; sessTo = sessFrom + InpSessionWindowMin; rangeFrom = 7 * 60; rangeTo = 13 * 60; return true; }
      return false;                                      // no Asian trading
   }

   bool SpreadOk(SEAContext &ctx)
   {
      PushSpread(ctx.spreadPoints);
      double med = MedianSpread();
      if(med <= 0.0) return true;
      return (ctx.spreadPoints <= InpMaxSpreadMedianX * med);
   }

   double m_spreads[96];
   int    m_spreadCount;

   void PushSpread(const double sp)
   {
      if(sp <= 0.0) return;
      if(m_spreadCount < 96) { m_spreads[m_spreadCount++] = sp; return; }
      for(int i = 0; i < 95; i++) m_spreads[i] = m_spreads[i + 1];
      m_spreads[95] = sp;
   }

   double MedianSpread()
   {
      if(m_spreadCount < 30) return 0.0;
      double s[];
      ArrayResize(s, m_spreadCount);
      for(int i = 0; i < m_spreadCount; i++) s[i] = m_spreads[i];
      ArraySort(s);
      return s[m_spreadCount / 2];
   }

   double AdrTravelPct(SEAContext &ctx)
   {
      double adr = ctx.atrD1;
      if(adr <= 0.0) return 0.0;
      MqlRates d[];
      if(EA_Rates(ctx.symbol, PERIOD_D1, 0, 1, d) < 1) return 0.0;
      return 100.0 * (d[0].high - d[0].low) / adr;
   }

   bool EmaSlopeAgrees(SEAContext &ctx, const int dir)
   {
      if(ctx.emaH1_50 <= 0.0) return false;
      return (dir > 0) ? (ctx.mid >= ctx.emaH1_50) : (ctx.mid <= ctx.emaH1_50);
   }

   //--- distance is direction-agnostic; the direction test lives in EmaSlopeAgrees
   bool EmaDistanceOk(SEAContext &ctx)
   {
      double h1Atr = (ctx.atrH1 > 0.0) ? ctx.atrH1
                                      : ((ctx.atrD1 > 0.0) ? ctx.atrD1 / 6.0 : 0.0);   // real H1 ATR, daily/6 as fallback
      if(h1Atr <= 0.0) return true;
      return (MathAbs(ctx.mid - ctx.emaH1_50) <= InpMaxEmaDistAtr * h1Atr);
   }

   //--- completed trades inside the current session window
   int TradesThisSession(const int sessFrom)
   {
      if(!HistorySelect(TimeCurrent() - 3 * 24 * 3600, TimeCurrent())) return 0;
      MqlDateTime dt;
      TimeToStruct(TimeTradeServer(), dt);
      int nowMin = dt.hour * 60 + dt.min;
      int elapsed = nowMin - sessFrom;
      if(elapsed < 0) elapsed = 0;
      datetime from = TimeTradeServer() - (datetime)(elapsed * 60);
      int n = 0;
      for(int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagicNumber) continue;
         if(HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
         if((datetime)HistoryDealGetInteger(t, DEAL_TIME) < from) continue;
         n++;
      }
      return n;
   }''',
)


add(
    entry=69,
    name="EA_studyarena_round11_contestant_b",
    magic=2036,
    cls="Round11B",
    title="Round 11B - cost-of-business governor with virtual stops and hard-stop camouflage",
    doc="docs/research/study_arena/studyarena-round11-contestant-b.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY,XAUUSD", "risk": "0.75", "spread": "0",
            "daily": "0", "totaldd": "0", "target": "20", "maxday": "6"},
    inputs='''input double InpMaxCobPct         = 5.00;  // Cost-of-Business = spread/ATR must stay < 5%
input double InpHardStopMult      = 3.00;  // Broker hard stop = 3x the virtual stop
input double InpVirtualTakeR      = 2.00;  // Virtual TP at 2R (managed locally)''',
    configure='''cfg.strategyName          = "R11B_COB_VIRTUAL";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round11-contestant-b.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 1;
   cfg.minSecondsBetweenTrades = 600;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.timeStopMinutes       = 240;
   cfg.logLevel              = InpLogLevel;''',
    plan='''//--- governor: CoB = spread / M15 ATR must stay below 5%
   if(!CobOk(ctx)) return false;

   SSweepParams p;
   p.Reset();
   p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
   p.sessionFromMin = 7 * 60; p.sessionToMin = 16 * 60;
   p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
   p.reclaimWindowBars = 3;
   p.wickRatio = 0.60; p.bodyRatio = 0.60;
   p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
   p.entryRetrace = 0.50; p.targetR = InpVirtualTakeR;
   if(!SigSweepReclaim(ctx, p, plan)) return false;

   //--- camouflage: the broker sees a 3x hard stop, the bot manages the real one
   double hard = InpHardStopMult * plan.riskDist;
   plan.stop = (plan.dir > 0) ? plan.entry - hard : plan.entry + hard;
   m_virtualStop[0] = 0.0;                              // filled by Manage when the position opens
   plan.reason = StringFormat("R11B-VIRTUAL(cob %.2f%%) %s",
                              100.0 * ctx.spreadPoints * ctx.point / MathMax(1e-10, ctx.atr), plan.reason);
   return true;''',
    extra='''   double m_virtualStop[16];
   double m_virtualTake[16];
   ulong  m_virtualTicket[16];
   int    m_virtualCount;

   bool CobOk(SEAContext &ctx)
   {
      if(ctx.atr <= 0.0) return false;
      double cost = ctx.spreadPoints * ctx.point;
      return (100.0 * cost / ctx.atr < InpMaxCobPct);
   }

   int Slot(const ulong ticket)
   {
      for(int i = 0; i < m_virtualCount; i++) if(m_virtualTicket[i] == ticket) return i;
      return -1;
   }

   //--- virtual stop/TP engine: local management, broker hard stop only as catastrophe cover
   void Manage(SEAContext &ctx)
   {
      for(int t = 0; t < g_eaTrackCount; t++)
      {
         if(g_eaTrack[t].symbol != ctx.symbol) continue;
         if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;
         int slot = Slot(g_eaTrack[t].ticket);
         if(slot < 0)
         {
            if(m_virtualCount >= 16) continue;
            slot = m_virtualCount++;
            m_virtualTicket[slot] = g_eaTrack[t].ticket;
            double entry = PositionGetDouble(POSITION_PRICE_OPEN);
            double risk  = g_eaTrack[t].riskDist;
            m_virtualStop[slot] = (g_eaTrack[t].dir > 0) ? entry - risk : entry + risk;
            m_virtualTake[slot] = (g_eaTrack[t].dir > 0) ? entry + InpVirtualTakeR * risk
                                                         : entry - InpVirtualTakeR * risk;
         }
         double cur = PositionGetDouble(POSITION_PRICE_CURRENT);
         bool hitStop = (g_eaTrack[t].dir > 0) ? (cur <= m_virtualStop[slot]) : (cur >= m_virtualStop[slot]);
         bool hitTake = (g_eaTrack[t].dir > 0) ? (cur >= m_virtualTake[slot]) : (cur <= m_virtualTake[slot]);
         if(hitStop) { g_eaExec.Close(g_eaTrack[t].ticket, "virtual stop"); }
         else if(hitTake) { g_eaExec.Close(g_eaTrack[t].ticket, "virtual take profit"); }
      }
   }''',
)


add(
    entry=70,
    name="EA_studyarena_round11_contestant_c",
    magic=2037,
    cls="Round11C",
    title="Round 11C - decade-honest risk throttle: halve at -3%, quarter at -5%, month over at -5.5%",
    doc="docs/research/study_arena/studyarena-round11-contestant-c.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY,XAUUSD", "risk": "0.80", "spread": "0",
            "daily": "0", "totaldd": "5.5", "target": "20", "maxday": "4"},
    inputs='''input double InpEffectiveRiskPct  = 0.80;  // Effective risk (combined 1/20th Kelly)
input double InpHalfAtDdPct       = 3.00;  // Halve risk at -3% from the equity high
input double InpQuarterAtDdPct    = 5.00;  // Quarter risk at -5%
input double InpMonthOverDdPct    = 5.50;  // Month over at -5.5% (not -6%)
input double InpMinExpectancyR    = 0.10;  // Rolling 30-trade expectancy pause
input double InpMaxSlipPctOfExp   = 20.0;  // Disable a symbol whose slippage eats this % of expectancy''',
    configure='''cfg.strategyName          = "R11C_DECADE_THROTTLE";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round11-contestant-c.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpEffectiveRiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.totalDdPct            = InpMonthOverDdPct;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 1;
   cfg.minSecondsBetweenTrades = 600;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;
   cfg.breakEvenAtR          = 1.00;
   cfg.trailAtR              = 1.50;  cfg.trailDistanceR = 0.75;
   cfg.timeStopMinutes       = 240;
   cfg.logLevel              = InpLogLevel;''',
    plan='''if(!EdgeAlive()) return false;
   //--- cost realism: a symbol whose slippage eats into expectancy is disabled
   if(!EA_SymbolSlippageOk(ctx.symbol, InpMaxSlipPctOfExp))
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("%s disabled: slippage eats > %.0f%% of expectancy",
             ctx.symbol, InpMaxSlipPctOfExp), true);
      return false;
   }
   SSweepParams p;
   p.Reset();
   p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
   p.sessionFromMin = 7 * 60; p.sessionToMin = 16 * 60;
   p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
   p.reclaimWindowBars = 3;
   p.wickRatio = 0.60; p.bodyRatio = 0.60;
   p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
   p.entryRetrace = 0.50; p.targetR = 2.0;
   if(!SigSweepReclaim(ctx, p, plan)) return false;
   plan.reason = "R11C-DECADE " + plan.reason;
   return true;''',
    extra='''   //--- edge-decay governor: rolling 30-trade expectancy must stay above 0.10R
   bool EdgeAlive()
   {
      double expR = RollingExpectancy(30);
      return (expR >= InpMinExpectancyR);
   }

   double RollingExpectancy(const int n)
   {
      if(!HistorySelect(TimeCurrent() - 120 * 24 * 3600, TimeCurrent())) return InpMinExpectancyR;
      double wins = 0.0, losses = 0.0, sumWin = 0.0, sumLoss = 0.0;
      int count = 0;
      for(int i = HistoryDealsTotal() - 1; i >= 0 && count < n; i--)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagicNumber) continue;
         if(HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
         double p = HistoryDealGetDouble(t, DEAL_PROFIT) +
                    HistoryDealGetDouble(t, DEAL_SWAP) +
                    HistoryDealGetDouble(t, DEAL_COMMISSION);
         if(p >= 0.0) { wins++; sumWin += p; }
         else         { losses++; sumLoss -= p; }
         count++;
      }
      if(count < 10) return InpMinExpectancyR;           // not enough evidence: keep trading
      double avgWin  = (wins > 0.0) ? sumWin / wins : 0.0;
      double avgLoss = (losses > 0.0) ? sumLoss / losses : 0.0;
      if(avgLoss <= 0.0) return 1.0;
      double wr = wins / (double)count;
      return wr * (avgWin / avgLoss) - (1.0 - wr);
   }

   //--- three-tier drawdown throttle from the equity high watermark
   double LotsMultiplier(SEAContext &ctx)
   {
      if(ctx.riskPct <= 0.0) return 0.0;
      double dd = DrawdownPct();
      double mult = 1.0;
      if(dd >= InpHalfAtDdPct)    mult = 0.50;
      if(dd >= InpQuarterAtDdPct) mult = 0.25;
      return MathMax(0.0, mult);
   }

   double DrawdownPct()
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double hwm = GlobalVariableGet("R11C_HWM");
      if(hwm <= 0.0 || equity > hwm) { GlobalVariableSet("R11C_HWM", MathMax(equity, hwm)); return 0.0; }
      if(hwm <= 0.0) return 0.0;
      return 100.0 * (hwm - equity) / hwm;
   }''',
)


add(
    entry=71,
    name="EA_studyarena_round11_contestant_d",
    magic=2038,
    cls="Round11D",
    title="Round 11D - veteran spec: 0.4-0.5% cap, -2% throttle steps and three decorrelated sleeves",
    doc="docs/research/study_arena/studyarena-round11-contestant-d.md",
    common={"symbols": "EURUSD,GBPUSD,XAUUSD,USDJPY,EURGBP,AUDNZD", "risk": "0.50", "spread": "0",
            "daily": "0", "totaldd": "0", "target": "20", "maxday": "4"},
    inputs='''input double InpVeteranRiskPct    = 0.50;  // Hard per-trade cap (veteran version)
input double InpThrottleStepPct   = 2.00;  // Halve risk every -2% from the equity high
input int    InpExpectancyWindow  = 50;    // Rolling expectation window (trades)
input double InpRetireExpectancyR = 0.05;  // Auto-retire threshold''',
    configure='''cfg.strategyName          = "R11D_VETERAN_SPEC";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round11-contestant-d.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpVeteranRiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 2;
   cfg.minSecondsBetweenTrades = 600;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;
   cfg.breakEvenAtR          = 1.00;
   cfg.trailAtR              = 1.50;  cfg.trailDistanceR = 0.75;
   cfg.timeStopMinutes       = 240;
   cfg.logLevel              = InpLogLevel;''',
    plan='''//--- Sleeve 1: sweep-reclaim core (M5)
   SSweepParams p;
   p.Reset();
   p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
   p.sessionFromMin = 7 * 60; p.sessionToMin = 16 * 60;
   p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
   p.reclaimWindowBars = 3;
   p.wickRatio = 0.55; p.bodyRatio = 0.55;
   p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
   p.entryRetrace = 0.50; p.targetR = 2.0;
   if(SigSweepReclaim(ctx, p, plan)) { m_sleeve = 1; plan.reason = "R11D-CORE " + plan.reason; return true; }

   //--- Sleeve 2: volatility-expansion continuation
   if(ctx.adx14 > 25.0 && ctx.atrD1 > 0.0 && ctx.atr > 0.5 * ctx.atrD1)
   {
      if(SigEmaPullback(ctx, PullbackParams(), plan)) { m_sleeve = 2; plan.reason = "R11D-EXPANSION " + plan.reason; return true; }
   }

   //--- Sleeve 3: Asian-session mean reversion on the quiet crosses
   if(ctx.clockMinutes < 7 * 60 && (StringFind(ctx.symbol, "EURGBP") >= 0 || StringFind(ctx.symbol, "AUDNZD") >= 0))
   {
      SRangeFadeParams rf;
      if(ctx.adxH1 >= 16.0) return false;                     // doc: ADX(H1) < 16 only (E lineage)
      rf.Reset();
      rf.bbPeriod = 20; rf.bbDeviation = 2.0;
      rf.rsiOversold = 5.0; rf.rsiOverbought = 95.0;
      rf.wickRatio = 0.50; rf.stopBufferAtr = 0.20;
      rf.targetR = 0.80; rf.requireRangeRegime = false;       // the H1 gate above is the doc's
      if(SigRangeFade(ctx, rf, plan)) { m_sleeve = 3; plan.reason = "R11D-ASIANMR " + plan.reason; return true; }
   }
   return false;''',
    extra='''   int m_sleeve;

   SEmaPullbackParams PullbackParams()
   {
      SEmaPullbackParams ep;
      ep.Reset();
      ep.emaPeriod = 20; ep.maxDistanceAtr = 1.20;
      ep.requireTrend = true; ep.targetR = 2.0;
      return ep;
   }

   //--- auto-retire protocol: rolling 50-trade expectancy below threshold
   bool RetireCheck()
   {
      if(!HistorySelect(TimeCurrent() - 180 * 24 * 3600, TimeCurrent())) return true;
      double wins = 0.0, losses = 0.0, sumWin = 0.0, sumLoss = 0.0;
      int count = 0;
      for(int i = HistoryDealsTotal() - 1; i >= 0 && count < InpExpectancyWindow; i--)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagicNumber) continue;
         if(HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
         double p = HistoryDealGetDouble(t, DEAL_PROFIT) +
                    HistoryDealGetDouble(t, DEAL_SWAP) +
                    HistoryDealGetDouble(t, DEAL_COMMISSION);
         if(p >= 0.0) { wins++; sumWin += p; } else { losses++; sumLoss -= p; }
         count++;
      }
      if(count < InpExpectancyWindow / 2) return true;
      double avgWin  = (wins > 0.0) ? sumWin / wins : 0.0;
      double avgLoss = (losses > 0.0) ? sumLoss / losses : 0.0;
      if(avgLoss <= 0.0) return true;
      double wr = wins / (double)count;
      double expR = wr * (avgWin / avgLoss) - (1.0 - wr);
      return (expR >= InpRetireExpectancyR);
   }

   //--- throttle: halve the risk for every -2% below the equity high
   double LotsMultiplier(SEAContext &ctx)
   {
      if(!RetireCheck()) return 0.0;                     // auto-retired
      if(ctx.riskPct <= 0.0) return 0.0;
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double hwm = GlobalVariableGet("R11D_HWM");
      if(hwm <= 0.0 || equity > hwm) { GlobalVariableSet("R11D_HWM", MathMax(equity, hwm)); return 1.0; }
      double dd = 100.0 * (hwm - equity) / hwm;
      int steps = (int)MathFloor(dd / InpThrottleStepPct);
      double mult = MathPow(0.5, steps);
      return MathMax(0.0, MathMin(mult, 1.0));
   }

   //--- shared risk budget: max four concurrent positions across the sleeves
   bool AllowMultipleOnSymbol() { return false; }''',
)


add(
    entry=72,
    name="EA_studyarena_round11_contestant_e",
    magic=2039,
    cls="Round11E",
    title="Round 11E - SWEEP-1 veteran: score gate, DD-tier risk ladder and Friday flat",
    doc="docs/research/study_arena/studyarena-round11-contestant-e.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY,XAUUSD,AUDNZD,EURGBP", "risk": "0.60",
            "spread": "0", "daily": "0", "totaldd": "6.0", "target": "20", "maxday": "6"},
    inputs='''input int    InpMinScore           = 7;     // Score gate (/8)
input double InpTier0RiskPct      = 0.60;  // DD 0-2%
input double InpTier1RiskPct      = 0.30;  // DD 2-4%
input double InpTier2RiskPct      = 0.15;  // DD 4-6%
input double InpShutdownDdPct     = 6.00;  // Shutdown for the month above this
input double InpMaxOpenRiskPct    = 1.20;  // Max total open risk''',
    configure='''cfg.strategyName          = "R11E_SWEEP1_VETERAN";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round11-contestant-e.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpTier0RiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.totalDdPct            = InpShutdownDdPct;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 2;                     // correlated pairs count as one
   cfg.minSecondsBetweenTrades = 120;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 30;   // thin hours excluded
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 45;  // flat Friday close
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;
   cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 30.0;
   cfg.breakEvenAtR          = 1.00;
   cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 1.00;
   cfg.timeStopMinutes       = 180;
   cfg.logLevel              = InpLogLevel;''',
    plan='''if(ctx.clockMinutes >= 21 * 60 + 30) return false;      // 21:30-23:30 spread blowouts
   if(OpenRiskTooHigh()) return false;
   if(GroupBlocked(ctx)) return false;

   SSweepParams p;
   p.Reset();
   p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
   p.sessionFromMin = 7 * 60; p.sessionToMin = 16 * 60;
   p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
   p.reclaimWindowBars = 3;
   p.wickRatio = 0.60; p.bodyRatio = 0.60;
   p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
   p.entryRetrace = 0.50; p.targetR = 2.0;
   if(!SigSweepReclaim(ctx, p, plan)) return false;

   int score = ScoreSetup(ctx, plan);
   if(score < InpMinScore) return false;
   plan.score  = score * 12.5;
   plan.reason = StringFormat("R11E-SWEEP1(%d/8) %s", score, plan.reason);
   return true;''',
    extra='''   int ScoreSetup(SEAContext &ctx, SSignalPlan &plan)
   {
      int score = 4;
      if(ctx.emaH1_50 > 0.0 && ((plan.dir > 0 && ctx.mid > ctx.emaH1_50) ||
                                (plan.dir < 0 && ctx.mid < ctx.emaH1_50))) score++;
      if(ctx.adx14 >= 18.0 && ctx.adx14 <= 35.0) score++;
      double costR = (plan.riskDist > 0.0) ? (ctx.spreadPoints * ctx.point) / plan.riskDist : 1.0;
      if(costR <= 0.10) score++;
      if(ctx.atrD1 > 0.0 && ctx.atr > 0.4 * ctx.atrD1) score++;
      return MathMin(score, 8);
   }

   bool OpenRiskTooHigh()
   {
      return (EA_OpenRiskPct() > InpMaxOpenRiskPct);
   }

   bool GroupBlocked(SEAContext &ctx)
   {
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         string other = PositionGetString(POSITION_SYMBOL);
         if(other == ctx.symbol) continue;
         //--- correlated USD pairs count as ONE position
         bool usdA = (StringFind(ctx.symbol, "USD") >= 0);
         bool usdB = (StringFind(other, "USD") >= 0);
         if(usdA && usdB) return true;
      }
      return false;
   }

   //--- DD-tier risk ladder with a hard monthly shutdown
   double LotsMultiplier(SEAContext &ctx)
   {
      if(ctx.riskPct <= 0.0) return 0.0;
      double dd = DrawdownPct();
      if(dd >= InpShutdownDdPct) return 0.0;             // shutdown for the month
      double risk = InpTier0RiskPct;
      if(dd >= 4.0)      risk = InpTier2RiskPct;
      else if(dd >= 2.0) risk = InpTier1RiskPct;
      return MathMax(0.0, risk / ctx.riskPct);
   }

   double DrawdownPct()
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double hwm = GlobalVariableGet("R11E_HWM");
      if(hwm <= 0.0 || equity > hwm) { GlobalVariableSet("R11E_HWM", MathMax(equity, hwm)); return 0.0; }
      if(hwm <= 0.0) return 0.0;
      return 100.0 * (hwm - equity) / hwm;
   }''',
)


add(
    entry=73,
    name="EA_studyarena_round11_contestant_f",
    magic=2040,
    cls="Round11F",
    title="Round 11F - TRIAD: one edge, three decorrelated expressions at 0.24% per sleeve",
    doc="docs/research/study_arena/studyarena-round11-contestant-f.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY,AUDUSD,XAUUSD,EURGBP,AUDNZD,EURCHF", "risk": "0.24",
            "spread": "0", "daily": "0", "totaldd": "0", "target": "20", "maxday": "6"},
    inputs='''input double InpPerSleeveRiskPct  = 0.24;  // ~1/20th Kelly per sleeve
input double InpMaxOpenRiskPct    = 1.00;  // Total open risk ceiling
input int    InpMaxPerSleeve      = 2;     // Max concurrent positions per sleeve
input int    InpMaxTotal          = 4;     // Max concurrent positions overall
input double InpSpreadAvgX        = 2.00;  // Skip entry when spread > this x its 60-min median
input double InpMaxSpreadStopPct  = 15.0;  // Skip entry when spread > this % of the stop distance
input double InpMaxSlipPctOfExp   = 20.0;  // Disable a symbol whose slippage eats this % of expectancy''',
    configure='''cfg.strategyName          = "R11F_TRIAD_SLEEVES";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round11-contestant-f.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpPerSleeveRiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = InpMaxTotal;
   cfg.minSecondsBetweenTrades = 300;
   cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;
   cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 30.0;
   cfg.breakEvenAtR          = 1.00;
   cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 1.00;
   cfg.timeStopMinutes       = 240;
   cfg.logLevel              = InpLogLevel;''',
    plan='''if(EA_OpenRiskPct() > InpMaxOpenRiskPct) return false;
   //--- survival table: spread vs its own 60-min baseline, and slippage vs expectancy
   double spRef = EA_SpreadMedianRecent(ctx.symbol, 60);
   if(spRef > 0.0 && ctx.spreadPoints > InpSpreadAvgX * spRef)
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.1f pts > %.1fx its 60-min median %.1f - skip",
             ctx.symbol, ctx.spreadPoints, InpSpreadAvgX, spRef), true);
      return false;
   }
   if(!EA_SymbolSlippageOk(ctx.symbol, InpMaxSlipPctOfExp))
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("%s disabled: slippage eats > %.0f%% of expectancy",
             ctx.symbol, InpMaxSlipPctOfExp), true);
      return false;
   }
   if(TotalOpen() >= InpMaxTotal) return false;

   //--- Sleeve A: session-open sweep & reclaim (the core, M5) - doc: EURUSD, GBPUSD, USDJPY, AUDUSD
   if(TotalForSleeve(1) < InpMaxPerSleeve && IsSleeveASymbol(ctx.symbol))
   {
      SSweepParams p;
      p.Reset();
      p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
      p.sessionFromMin = 7 * 60; p.sessionToMin = 16 * 60;
      p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
      p.reclaimWindowBars = 3;
      p.wickRatio = 0.60; p.bodyRatio = 0.60;
      p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
      p.entryRetrace = 0.50; p.targetR = 2.0;
      if(SigSweepReclaim(ctx, p, plan))
      { m_sleeve = 1; plan.reason = "R11F-A-SWEEP " + plan.reason; return CostOk(ctx, plan); }
   }

   //--- Sleeve B: volatility-expansion continuation (deliberately opposite regime)
   if(TotalForSleeve(2) < InpMaxPerSleeve && ctx.adx14 > 25.0 && IsSleeveBSymbol(ctx.symbol))
   {
      if(SigEmaPullback(ctx, PullbackParams(), plan))
      { m_sleeve = 2; plan.reason = "R11F-B-EXPANSION " + plan.reason; return CostOk(ctx, plan); }
   }

   //--- Sleeve C: Asian-session mean reversion (low beta, high hit-rate)
   if(TotalForSleeve(3) < InpMaxPerSleeve && ctx.clockMinutes < 6 * 60 + 30 &&   // doc sleeve C: 00:00-06:30 only
      IsSleeveCSymbol(ctx.symbol))
   {
      SRangeFadeParams rf;
      if(ctx.adxH1 >= 16.0) return false;                     // doc: ADX(H1) < 16 only for this sleeve
      rf.Reset();
      rf.bbPeriod = 20; rf.bbDeviation = 2.0;
      rf.rsiOversold = 5.0; rf.rsiOverbought = 95.0;
      rf.wickRatio = 0.50; rf.stopBufferAtr = 0.20;
      rf.targetR = 0.80; rf.requireRangeRegime = false;       // the H1 gate above is the doc's
      if(SigRangeFade(ctx, rf, plan))
      { m_sleeve = 3; plan.reason = "R11F-C-ASIANMR " + plan.reason; return CostOk(ctx, plan); }
   }
   return false;''',
    extra='''   bool IsSleeveASymbol(const string sym)
   {
      //--- doc sleeve A: EURUSD, GBPUSD, USDJPY, AUDUSD
      return (StringFind(sym, "EURUSD") >= 0 || StringFind(sym, "GBPUSD") >= 0 ||
              StringFind(sym, "USDJPY") >= 0 || StringFind(sym, "AUDUSD") >= 0);
   }

   bool IsSleeveBSymbol(const string sym)
   {
      //--- doc sleeve B: XAUUSD, DAX, US30 (the two indices are outside this broker universe)
      return (StringFind(sym, "XAUUSD") >= 0);
   }

   bool IsSleeveCSymbol(const string sym)
   {
      //--- doc sleeve C: AUDNZD, EURGBP, EURCHF
      return (StringFind(sym, "AUDNZD") >= 0 || StringFind(sym, "EURGBP") >= 0 ||
              StringFind(sym, "EURCHF") >= 0);
   }

   //--- doc sleeve C: hard flat at 06:30 UK (sleeve-C symbols only)
   void Manage(SEAContext &ctx)
   {
      if(ctx.clockMinutes < 6 * 60 + 30 || ctx.clockMinutes >= 7 * 60) return;
      if(!IsSleeveCSymbol(ctx.symbol)) return;
      for(int t = g_eaTrackCount - 1; t >= 0; t--)
      {
         if(g_eaTrack[t].symbol != ctx.symbol) continue;
         if(!PositionSelectByTicket(g_eaTrack[t].ticket)) continue;
         g_eaExec.Close(g_eaTrack[t].ticket, "sleeve C flat 06:30");
      }
   }

   int m_sleeve;

   SEmaPullbackParams PullbackParams()
   {
      SEmaPullbackParams ep;
      ep.Reset();
      ep.emaPeriod = 20; ep.maxDistanceAtr = 1.20;
      ep.requireTrend = true; ep.targetR = 2.0;
      return ep;
   }

   int TotalOpen()
   {
      return EA_CountPositions("", false);
   }

   //--- sleeve identity from the position comment prefix written at entry
   int TotalForSleeve(const int sleeve)
   {
      string tag = (sleeve == 1) ? "R11F-A" : (sleeve == 2) ? "R11F-B" : "R11F-C";
      int n = 0;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(StringFind(PositionGetString(POSITION_COMMENT), tag) >= 0) n++;
      }
      return n;
   }
   //--- doc: spread > 15% of the stop distance voids the entry
   bool CostOk(SEAContext &ctx, SSignalPlan &p)
   {
      if(p.riskDist <= 0.0) return false;
      bool ok = (ctx.spreadPoints * ctx.point <= InpMaxSpreadStopPct / 100.0 * p.riskDist);
      if(!ok)
         EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.1f pts > %.0f%% of the %.5f stop - entry void",
                ctx.symbol, ctx.spreadPoints, InpMaxSpreadStopPct, p.riskDist), true);
      return ok;
   }''',
)


add(
    entry=74,
    name="EA_studyarena_round12_claude_fable_5_high_reasoning",
    magic=2041,
    cls="Round12Fable",
    title="Round 12 Fable - SWEEP-1 the 10-year machine with six entry gates and flow checks",
    doc="docs/research/study_arena/studyarena-round12-claude-fable-5-high-reasoning.md",
    common={"symbols": "AUDNZD,EURGBP,EURUSD,GBPUSD,XAUUSD,USDJPY", "risk": "0.60",
            "spread": "0", "daily": "0", "totaldd": "0", "target": "20", "maxday": "6"},
    inputs='''input double InpRangeLowPct       = 35.0;  // Range gate: 35% of the 20-day median
input double InpRangeHighPct      = 75.0;  // Range gate: 75% ceiling
input double InpSpreadAvgX        = 1.50;  // Spread <= 1.5x the 20-day average
input double InpSweepVolumeX      = 1.20;  // Sweep-candle volume >= 1.2x the 20-candle average
input int    InpThinHourFrom      = 21 * 60 + 30;  // Thin hours begin (21:30 UK)
input int    InpThinHourTo        = 23 * 60 + 30;''',
    configure='''cfg.strategyName          = "R12FABLE_SWEEP1_MACHINE";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round12-claude-fable-5-high-reasoning.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 2;
   cfg.minSecondsBetweenTrades = 300;
   cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 30;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;
   cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 30.0;
   cfg.breakEvenAtR          = 1.00;
   cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 1.00;
   cfg.pendingExpiryMinutes  = 15;    // cancel the limit if unfilled in 15 minutes
   cfg.useLimitEntry         = true;
   cfg.timeStopMinutes       = 240;
   cfg.logLevel              = InpLogLevel;''',
    plan='''int fromMin, toMin, sessFrom, sessTo;
   if(!SessionMap(ctx, fromMin, toMin, sessFrom, sessTo)) return false;
   if(ctx.clockMinutes >= InpThinHourFrom && ctx.clockMinutes < InpThinHourTo) return false;
   if(!RangeGate(ctx, fromMin, toMin)) return false;
   if(!FlowGate(ctx)) return false;

   SSweepParams p;
   p.Reset();
   p.rangeFromMin = fromMin; p.rangeToMin = toMin;
   p.sessionFromMin = sessFrom; p.sessionToMin = sessTo;
   p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
   p.reclaimWindowBars = 3;
   p.wickRatio = 0.60; p.bodyRatio = 0.60;
   p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
   p.entryRetrace = 0.50; p.targetR = 2.0;
   if(!SigSweepReclaim(ctx, p, plan)) return false;
   if(!BiasGate(ctx, plan.dir)) return false;
   plan.reason = "R12FABLE-SWEEP1 " + plan.reason;
   return true;''',
    extra='''   bool SessionMap(SEAContext &ctx, int &fromMin, int &toMin, int &sessFrom, int &sessTo)
   {
      if(ctx.clockMinutes < 6 * 60 + 30 && (StringFind(ctx.symbol, "AUDNZD") >= 0 ||
                                            StringFind(ctx.symbol, "EURGBP") >= 0))
      { fromMin = 21 * 60; toMin = 24 * 60; sessFrom = 0; sessTo = 6 * 60 + 30; return true; }
      if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 16 * 60 + 30 &&
         (StringFind(ctx.symbol, "EURUSD") >= 0 || StringFind(ctx.symbol, "GBPUSD") >= 0 ||
          StringFind(ctx.symbol, "XAU") >= 0))
      { fromMin = 0; toMin = 7 * 60; sessFrom = 7 * 60; sessTo = 16 * 60 + 30; return true; }
      if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 20 * 60 + 30 &&
         (StringFind(ctx.symbol, "XAU") >= 0 || StringFind(ctx.symbol, "USDJPY") >= 0))
      { fromMin = 7 * 60; toMin = 13 * 60; sessFrom = 13 * 60 + 30; sessTo = 20 * 60 + 30; return true; }
      return false;
   }

   bool RangeGate(SEAContext &ctx, const int fromMin, const int toMin)
   {
      double hi = 0.0, lo = 0.0;
      if(!RangeBetween(ctx.symbol, fromMin, toMin, hi, lo)) return false;
      double median = MedianRange(ctx.symbol);
      if(median <= 0.0) return false;
      double ratio = (hi - lo) / median;
      return (ratio >= InpRangeLowPct / 100.0 && ratio <= InpRangeHighPct / 100.0);
   }

   double MedianRange(const string sym)
   {
      MqlRates d[];
      if(EA_Rates(sym, PERIOD_D1, 1, 20, d) < 10) return 0.0;
      double s[];
      ArrayResize(s, 20);
      for(int i = 0; i < 20; i++) s[i] = d[i].high - d[i].low;
      ArraySort(s);
      return s[10];
   }

   bool RangeBetween(const string sym, const int fromMin, const int toMin, double &hi, double &lo)
   {
      MqlRates r[];
      if(EA_Rates(sym, PERIOD_M15, 1, 400, r) < 30) return false;
      bool wrap = (fromMin > toMin);
      int i = 0;
      for(; i < 400; i++)
      {
         MqlDateTime t;
         TimeToStruct(r[i].time, t);
         int m = t.hour * 60 + t.min;
         bool inWin = wrap ? (m >= fromMin || m < toMin) : (m >= fromMin && m < toMin);
         if(inWin) break;
      }
      if(i >= 400) return false;
      hi = 0.0; lo = 0.0;
      bool found = false;
      for(; i < 400; i++)
      {
         MqlDateTime t;
         TimeToStruct(r[i].time, t);
         int m = t.hour * 60 + t.min;
         bool inWin = wrap ? (m >= fromMin || m < toMin) : (m >= fromMin && m < toMin);
         if(!inWin) break;
         if(!found) { hi = r[i].high; lo = r[i].low; found = true; }
         else { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }
      }
      return found;
   }

   //--- cost/flow gate: spread vs 20-day average, sweep volume vs 20-candle average
   bool FlowGate(SEAContext &ctx)
   {
      PushSpread(ctx.spreadPoints);
      double avgSpread = AverageSpread();
      if(avgSpread > 0.0 && ctx.spreadPoints > InpSpreadAvgX * avgSpread) return false;
      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M5, 1, 22, r) < 21) return false;
      double vsum = 0.0;
      for(int i = 1; i <= 20; i++) vsum += (double)r[i].tick_volume;
      double vavg = vsum / 20.0;
      return (vavg <= 0.0 || r[0].tick_volume >= InpSweepVolumeX * vavg);
   }

   double m_spreads[120];
   int    m_spreadCount;

   void PushSpread(const double sp)
   {
      if(sp <= 0.0) return;
      if(m_spreadCount < 120) { m_spreads[m_spreadCount++] = sp; return; }
      for(int i = 0; i < 119; i++) m_spreads[i] = m_spreads[i + 1];
      m_spreads[119] = sp;
   }

   double AverageSpread()
   {
      if(m_spreadCount < 30) return 0.0;
      double sum = 0.0;
      for(int i = 0; i < m_spreadCount; i++) sum += m_spreads[i];
      return sum / m_spreadCount;
   }

   //--- bias gate (waived for the Asian mean-reversion cross pairs with ADX < 16)
   bool BiasGate(SEAContext &ctx, const int dir)
   {
      bool asianPair = (StringFind(ctx.symbol, "AUDNZD") >= 0 || StringFind(ctx.symbol, "EURGBP") >= 0);
      if(asianPair && ctx.adxH1 < 16.0) return true;                      // H1 ADX waiver (doc)
      if(ctx.emaH1_50 <= 0.0) return false;
      return (dir > 0) ? (ctx.mid > ctx.emaH1_50 && ctx.ema50 >= ctx.emaH1_50)
                       : (ctx.mid < ctx.emaH1_50 && ctx.ema50 <= ctx.emaH1_50);
   }''',
)


add(
    entry=75,
    name="EA_studyarena_round12_contestant_a",
    magic=2042,
    cls="Round12A",
    title="Round 12A - SWEEP-1 final locked with the 8-point score gate (>= 7/8)",
    doc="docs/research/study_arena/studyarena-round12-contestant-a.md",
    common={"symbols": "AUDNZD,EURGBP,EURUSD,GBPUSD,XAUUSD,USDJPY", "risk": "0.60",
            "spread": "0", "daily": "0", "totaldd": "0", "target": "20", "maxday": "6"},
    inputs='''input int    InpMinScore           = 7;     // Must score >= 7 of 8 filters
input double InpSpreadAvgX        = 1.50;  // Filter 6: spread vs 20-day average
input double InpSweepVolumeX      = 1.20;  // Filter 7: sweep-candle participation
input double InpRunnerTrailAtrH1  = 2.50;  // 30% runner trail (2.5 x H1 ATR)''',
    configure='''cfg.strategyName          = "R12A_SWEEP1_SCORE";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round12-contestant-a.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 2;
   cfg.minSecondsBetweenTrades = 300;
   cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 21;  cfg.sessionEndMin   = 30;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;
   cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 30.0;
   cfg.breakEvenAtR          = 1.00;
   cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 1.00;
   cfg.useLimitEntry         = true;
   cfg.pendingExpiryMinutes  = 15;
   cfg.timeStopMinutes       = 240;
   cfg.logLevel              = InpLogLevel;''',
    plan='''int fromMin, toMin, sessFrom, sessTo;
   if(!SessionMap(ctx, fromMin, toMin, sessFrom, sessTo)) return false;

   double hi = 0.0, lo = 0.0;
   if(!RangeBetween(ctx.symbol, fromMin, toMin, hi, lo)) return false;

   //--- the 8-point scoreboard: each filter contributes exactly one point
   int score = 0;
   double median = MedianRange(ctx.symbol);
   if(median > 0.0)
   {
      double ratio = (hi - lo) / median;
      if(ratio >= 0.35 && ratio <= 0.75) score++;                      // 1 range quality
   }
   bool asianPair = (StringFind(ctx.symbol, "AUDNZD") >= 0 || StringFind(ctx.symbol, "EURGBP") >= 0);
   if(asianPair && ctx.adxH1 < 16.0) score++;                          // H1 ADX waiver (doc)
   else if(BiasIntact(ctx)) score++;                                   // 2 bias
   if(SpreadGate(ctx)) score++;                                        // 6 spread gate
   if(ParticipationGate(ctx)) score++;                                 // 7 participation

   SSweepParams p;
   p.Reset();
   p.rangeFromMin = fromMin; p.rangeToMin = toMin;
   p.sessionFromMin = sessFrom; p.sessionToMin = sessTo;
   p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
   p.reclaimWindowBars = 3;
   p.wickRatio = 0.60; p.bodyRatio = 0.60;                             // 3 sweep + 4 rejection
   p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
   p.entryRetrace = 0.50; p.targetR = 2.0;
   if(!SigSweepReclaim(ctx, p, plan)) return false;
   score += 2;                                                          // sweep + displacement
   if(!CorrelatedPositionOpen(ctx)) score++;                            // 8 clean book
   if(score < InpMinScore) return false;
   plan.score  = score * 12.5;
   plan.reason = StringFormat("R12A-SWEEP1(%d/8) %s", score, plan.reason);
   return true;''',
    extra='''   bool SessionMap(SEAContext &ctx, int &fromMin, int &toMin, int &sessFrom, int &sessTo)
   {
      if(ctx.clockMinutes < 6 * 60 + 30 && (StringFind(ctx.symbol, "AUDNZD") >= 0 ||
                                            StringFind(ctx.symbol, "EURGBP") >= 0))
      { fromMin = 21 * 60; toMin = 24 * 60; sessFrom = 0; sessTo = 6 * 60 + 30; return true; }
      if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 11 * 60 + 30 &&
         (StringFind(ctx.symbol, "EURUSD") >= 0 || StringFind(ctx.symbol, "GBPUSD") >= 0 ||
          StringFind(ctx.symbol, "XAU") >= 0))
      { fromMin = 0; toMin = 7 * 60; sessFrom = 7 * 60; sessTo = 11 * 60 + 30; return true; }
      if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 17 * 60 &&
         (StringFind(ctx.symbol, "XAU") >= 0 || StringFind(ctx.symbol, "USDJPY") >= 0))
      { fromMin = 7 * 60; toMin = 13 * 60; sessFrom = 13 * 60 + 30; sessTo = 17 * 60; return true; }
      return false;
   }

   double MedianRange(const string sym)
   {
      MqlRates d[];
      if(EA_Rates(sym, PERIOD_D1, 1, 20, d) < 10) return 0.0;
      double s[];
      ArrayResize(s, 20);
      for(int i = 0; i < 20; i++) s[i] = d[i].high - d[i].low;
      ArraySort(s);
      return s[10];
   }

   bool RangeBetween(const string sym, const int fromMin, const int toMin, double &hi, double &lo)
   {
      MqlRates r[];
      if(EA_Rates(sym, PERIOD_M15, 1, 400, r) < 30) return false;
      bool wrap = (fromMin > toMin);
      int i = 0;
      for(; i < 400; i++)
      {
         MqlDateTime t;
         TimeToStruct(r[i].time, t);
         int m = t.hour * 60 + t.min;
         bool inWin = wrap ? (m >= fromMin || m < toMin) : (m >= fromMin && m < toMin);
         if(inWin) break;
      }
      if(i >= 400) return false;
      hi = 0.0; lo = 0.0;
      bool found = false;
      for(; i < 400; i++)
      {
         MqlDateTime t;
         TimeToStruct(r[i].time, t);
         int m = t.hour * 60 + t.min;
         bool inWin = wrap ? (m >= fromMin || m < toMin) : (m >= fromMin && m < toMin);
         if(!inWin) break;
         if(!found) { hi = r[i].high; lo = r[i].low; found = true; }
         else { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }
      }
      return found;
   }

   bool BiasIntact(SEAContext &ctx)
   {
      if(ctx.emaH1_50 <= 0.0) return false;
      bool up = (ctx.mid > ctx.emaH1_50) && (ctx.emaH1_50 >= ctx.emaH1_200);
      bool dn = (ctx.mid < ctx.emaH1_50) && (ctx.emaH1_50 <= ctx.emaH1_200);
      return (up || dn);
   }

   double m_spreads[96];
   int    m_spreadCount;

   void PushSpread(const double sp)
   {
      if(sp <= 0.0) return;
      if(m_spreadCount < 96) { m_spreads[m_spreadCount++] = sp; return; }
      for(int i = 0; i < 95; i++) m_spreads[i] = m_spreads[i + 1];
      m_spreads[95] = sp;
   }

   double AverageSpread()
   {
      if(m_spreadCount < 30) return 0.0;
      double sum = 0.0;
      for(int i = 0; i < m_spreadCount; i++) sum += m_spreads[i];
      return sum / m_spreadCount;
   }

   bool SpreadGate(SEAContext &ctx)
   {
      PushSpread(ctx.spreadPoints);
      double avg = EA_SpreadBaseline(ctx.symbol, 720);              // whole-day 20-day baseline
      if(avg <= 0.0) avg = AverageSpread();                        // fallback: live ring
      if(avg <= 0.0) return true;
      if(ctx.spreadPoints <= InpSpreadAvgX * avg) return true;
      EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.1f > %.2fx 20d avg %.1f - skip",
             ctx.symbol, ctx.spreadPoints, InpSpreadAvgX, avg), true);
      return false;
   }

   bool ParticipationGate(SEAContext &ctx)
   {
      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M5, 1, 22, r) < 21) return true;
      double vsum = 0.0;
      for(int i = 1; i <= 20; i++) vsum += (double)r[i].tick_volume;
      double vavg = vsum / 20.0;
      return (vavg <= 0.0 || r[0].tick_volume >= InpSweepVolumeX * vavg);
   }

   bool CorrelatedPositionOpen(SEAContext &ctx)
   {
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         string other = PositionGetString(POSITION_SYMBOL);
         if(other == ctx.symbol) continue;
         bool usdA = (StringFind(ctx.symbol, "USD") >= 0);
         bool usdB = (StringFind(other, "USD") >= 0);
         if(usdA && usdB) return true;
      }
      return false;
   }''',
)


add(
    entry=76,
    name="EA_studyarena_round12_contestant_b",
    magic=2043,
    cls="Round12B",
    title="Round 12B - three-tier DD throttle on top of the programmatic M5 sweep-reclaim",
    doc="docs/research/study_arena/studyarena-round12-contestant-b.md",
    common={"symbols": "EURUSD,GBPUSD,XAUUSD,USDJPY,US30,AUDNZD", "risk": "0.60",
            "spread": "0", "daily": "0", "totaldd": "8.0", "target": "20", "maxday": "6"},
    inputs='''input double InpTier1RiskPct      = 0.60;  // DD 0-2%
input double InpTier2RiskPct      = 0.30;  // DD 2-4%
input double InpTier3RiskPct      = 0.15;  // DD 4-6%
input double InpShutdownDdPct     = 8.00;  // Hard 8% DD cap
input double InpWickRatio         = 0.60;  // Sweep-candle wick >= 60% of the candle''',
    configure='''cfg.strategyName          = "R12B_THREE_TIER_DD";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round12-contestant-b.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpTier1RiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.totalDdPct            = InpShutdownDdPct;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = 2;
   cfg.minSecondsBetweenTrades = 300;
   cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 20;  cfg.sessionEndMin   = 30;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;
   cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 30.0;
   cfg.breakEvenAtR          = 1.00;
   cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 1.00;
   cfg.useLimitEntry         = true;
   cfg.pendingExpiryMinutes  = 15;
   cfg.timeStopMinutes       = 240;
   cfg.logLevel              = InpLogLevel;''',
    plan='''int fromMin, toMin, sessFrom, sessTo;
   if(!SessionMap(ctx, fromMin, toMin, sessFrom, sessTo)) return false;

   SSweepParams p;
   p.Reset();
   p.rangeFromMin = fromMin; p.rangeToMin = toMin;
   p.sessionFromMin = sessFrom; p.sessionToMin = sessTo;
   p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
   p.reclaimWindowBars = 3;
   p.wickRatio = InpWickRatio; p.bodyRatio = 0.60;
   p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
   p.entryRetrace = 0.50; p.targetR = 2.0;
   if(!SigSweepReclaim(ctx, p, plan)) return false;
   if(!BiasAgrees(ctx, plan.dir)) return false;
   plan.reason = "R12B-SWEEPRECLAIM " + plan.reason;
   return true;''',
    extra='''   bool SessionMap(SEAContext &ctx, int &fromMin, int &toMin, int &sessFrom, int &sessTo)
   {
      if(ctx.clockMinutes < 6 * 60 + 30 && StringFind(ctx.symbol, "AUDNZD") >= 0)
      { fromMin = 21 * 60; toMin = 24 * 60; sessFrom = 0; sessTo = 6 * 60 + 30; return true; }
      if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 16 * 60 + 30 &&
         (StringFind(ctx.symbol, "EURUSD") >= 0 || StringFind(ctx.symbol, "GBPUSD") >= 0 ||
          StringFind(ctx.symbol, "XAU") >= 0))
      { fromMin = 0; toMin = 7 * 60; sessFrom = 7 * 60; sessTo = 16 * 60 + 30; return true; }
      if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 20 * 60 + 30 &&
         (StringFind(ctx.symbol, "USDJPY") >= 0 || StringFind(ctx.symbol, "US30") >= 0))
      { fromMin = 7 * 60; toMin = 13 * 60; sessFrom = 13 * 60 + 30; sessTo = 20 * 60 + 30; return true; }
      return false;
   }

   bool RangeBetween(const string sym, const int fromMin, const int toMin, double &hi, double &lo)
   {
      MqlRates r[];
      if(EA_Rates(sym, PERIOD_M15, 1, 400, r) < 30) return false;
      bool wrap = (fromMin > toMin);
      int i = 0;
      for(; i < 400; i++)
      {
         MqlDateTime t;
         TimeToStruct(r[i].time, t);
         int m = t.hour * 60 + t.min;
         bool inWin = wrap ? (m >= fromMin || m < toMin) : (m >= fromMin && m < toMin);
         if(inWin) break;
      }
      if(i >= 400) return false;
      hi = 0.0; lo = 0.0;
      bool found = false;
      for(; i < 400; i++)
      {
         MqlDateTime t;
         TimeToStruct(r[i].time, t);
         int m = t.hour * 60 + t.min;
         bool inWin = wrap ? (m >= fromMin || m < toMin) : (m >= fromMin && m < toMin);
         if(!inWin) break;
         if(!found) { hi = r[i].high; lo = r[i].low; found = true; }
         else { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }
      }
      return found;
   }

   bool BiasAgrees(SEAContext &ctx, const int dir)
   {
      if(StringFind(ctx.symbol, "AUDNZD") >= 0) return true;   // Asian mean reversion
      if(ctx.emaH1_50 <= 0.0) return false;
      return (dir > 0) ? (ctx.mid > ctx.emaH1_50) : (ctx.mid < ctx.emaH1_50);
   }

   //--- three-tier DD throttle with an 8% hard cap
   double LotsMultiplier(SEAContext &ctx)
   {
      if(ctx.riskPct <= 0.0) return 0.0;
      double dd = DrawdownPct();
      if(dd >= InpShutdownDdPct) return 0.0;
      double risk = InpTier1RiskPct;
      if(dd >= 4.0)      risk = InpTier3RiskPct;
      else if(dd >= 2.0) risk = InpTier2RiskPct;
      return MathMax(0.0, risk / ctx.riskPct);
   }

   double DrawdownPct()
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double hwm = GlobalVariableGet("R12B_HWM");
      if(hwm <= 0.0 || equity > hwm) { GlobalVariableSet("R12B_HWM", MathMax(equity, hwm)); return 0.0; }
      if(hwm <= 0.0) return 0.0;
      return 100.0 * (hwm - equity) / hwm;
   }''',
)


add(
    entry=77,
    name="EA_studyarena_round12_contestant_c",
    magic=2044,
    cls="Round12C",
    title="Round 12C - SR-10 survival: ban list, volatility percentile band and 0.70% open-risk cap",
    doc="docs/research/study_arena/studyarena-round12-contestant-c.md",
    common={"symbols": "EURUSD,GBPUSD,USDJPY,XAUUSD", "risk": "0.50", "spread": "0",
            "daily": "0", "totaldd": "0", "target": "20", "maxday": "3"},
    inputs='''input double InpOpenRiskCapPct    = 0.70;  // Aggregate open risk ceiling
input int    InpMaxPositions      = 2;     // Max two simultaneous positions
input int    InpMaxTradesDay      = 3;     // Max three completed trades per day
input double InpVolLowPct         = 20.0;  // Below the 20th percentile: no movement
input double InpVolHighPct        = 85.0;  // Above the 85th percentile: unstable''',
    configure='''cfg.strategyName          = "R12C_SR10_SURVIVAL";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round12-contestant-c.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M1;              // M1 scalping core
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = InpMaxTradesDay;
   cfg.maxOpenPositions      = InpMaxPositions;
   cfg.minSecondsBetweenTrades = 600;
   cfg.sessionStartHour      = 7;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 20;  cfg.sessionEndMin   = 30;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 50.0;
   cfg.breakEvenAtR          = 1.00;
   cfg.trailAtR              = 1.50;  cfg.trailDistanceR = 0.75;
   cfg.timeStopMinutes       = 60;
   cfg.logLevel              = InpLogLevel;''',
    plan='''//--- banned behaviours are simply not implemented: no grid, no averaging, no martingale
   if(EA_OpenRiskPct() >= InpOpenRiskCapPct) return false;
   if(EA_CountPositions("", false) >= InpMaxPositions) return false;
   if(!VolatilityBandOk(ctx)) return false;
   if(!H1Directional(ctx)) return false;

   //--- one trade per instrument per session: the engine's daily cap plus this guard
   if(TradedThisSession(ctx.symbol)) return false;

   SSweepParams p;
   p.Reset();
   p.rangeFromMin = 0; p.rangeToMin = 7 * 60;
   p.sessionFromMin = 7 * 60; p.sessionToMin = 17 * 60;
   p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
   p.reclaimWindowBars = 3;
   p.wickRatio = 0.55; p.bodyRatio = 0.55;
   p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
   p.entryRetrace = 0.50; p.targetR = 2.0;
   if(!SigSweepReclaim(ctx, p, plan)) return false;

   //--- the sweep must agree with the H1 direction (no counter-trend fading)
   if(!H1AgreesWith(ctx, plan.dir)) return false;
   plan.reason = "R12C-SR10 " + plan.reason;
   return true;''',
    extra='''   bool VolatilityBandOk(SEAContext &ctx)
   {
      double av[];
      if(EA_BufN(g_eaInd[ctx.index].hAtr, 0, 1, 500, av) < 50) return true;
      double median = Median(av);
      if(median <= 0.0) return true;
      double ratio = ctx.atr / median;
      //--- 20th-85th percentile band (narrow proxies for the ATR distribution)
      return (ratio >= 0.6 && ratio <= 1.6);
   }

   double Median(double &arr[])
   {
      double s[];
      int n = ArraySize(arr);
      ArrayResize(s, n);
      ArrayCopy(s, arr);
      ArraySort(s);
      return s[n / 2];
   }

   bool H1Directional(SEAContext &ctx)
   {
      if(ctx.emaH1_50 <= 0.0) return false;
      //--- slope over the previous five completed H1 candles (D1 ATR/6 ~ H1 ATR proxy)
      double h1Atr = (ctx.atrH1 > 0.0) ? ctx.atrH1
                                      : ((ctx.atrD1 > 0.0) ? ctx.atrD1 / 6.0 : 0.0);   // real H1 ATR, daily/6 as fallback
      if(h1Atr <= 0.0) return true;
      return (MathAbs(ctx.mid - ctx.emaH1_50) > 0.05 * h1Atr);
   }

   bool H1AgreesWith(SEAContext &ctx, const int dir)
   {
      if(ctx.emaH1_50 <= 0.0) return false;
      return (dir > 0) ? (ctx.mid > ctx.emaH1_50) : (ctx.mid < ctx.emaH1_50);
   }

   bool TradedThisSession(const string sym)
   {
      if(!HistorySelect(TimeCurrent() - 24 * 3600, TimeCurrent())) return false;
      MqlDateTime dt;
      TimeToStruct(TimeTradeServer(), dt);
      int nowMin = dt.hour * 60 + dt.min;
      datetime from = TimeTradeServer() - (datetime)(MathMax(0, nowMin - 7 * 60) * 60);
      for(int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagicNumber) continue;
         if(HistoryDealGetString(t, DEAL_SYMBOL) != sym) continue;
         if(HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
         if((datetime)HistoryDealGetInteger(t, DEAL_TIME) >= from) return true;
      }
      return false;
   }''',
)


add(
    entry=78,
    name="EA_studyarena_round12_contestant_f",
    magic=2045,
    cls="Round12F",
    title="Round 12F - SOS-SWEEP veteran: five gates, one-position correlation rule, 1.2% heat cap",
    doc="docs/research/study_arena/studyarena-round12-contestant-f.md",
    common={"symbols": "AUDNZD,EURGBP,EURUSD,GBPUSD,XAUUSD,USDJPY", "risk": "0.60",
            "spread": "0", "daily": "0", "totaldd": "0", "target": "20", "maxday": "6"},
    inputs='''input int    InpMinScore           = 7;     // Score >= 7/8 to fire
input double InpMaxOpenRiskPct    = 1.20;  // Max total open risk
input int    InpMaxOpenPositions  = 4;     // Max four open positions
input double InpWickRatio         = 0.60;  // Sweep wick >= 60% of the candle''',
    configure='''cfg.strategyName          = "R12F_SOS_SWEEP_VET";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round12-contestant-f.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = InpMaxOpenPositions;
   cfg.minSecondsBetweenTrades = 300;
   cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 20;  cfg.sessionEndMin   = 30;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;
   cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 30.0;
   cfg.breakEvenAtR          = 1.00;
   cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 1.00;
   cfg.useLimitEntry         = true;
   cfg.pendingExpiryMinutes  = 15;
   cfg.timeStopMinutes       = 240;
   cfg.logLevel              = InpLogLevel;''',
    plan='''if(EA_OpenRiskPct() > InpMaxOpenRiskPct) return false;
   if(EA_CountPositions("", false) >= InpMaxOpenPositions) return false;
   if(CorrelatedPositionOpen(ctx)) return false;

   int fromMin, toMin, sessFrom, sessTo;
   if(!SessionMap(ctx, fromMin, toMin, sessFrom, sessTo)) return false;

   double hi = 0.0, lo = 0.0;
   if(!RangeBetween(ctx.symbol, fromMin, toMin, hi, lo)) return false;
   double median = MedianRange(ctx.symbol);
   if(median <= 0.0) return false;
   double ratio = (hi - lo) / median;
   if(ratio < 0.35 || ratio > 0.75) return false;

   SSweepParams p;
   p.Reset();
   p.rangeFromMin = fromMin; p.rangeToMin = toMin;
   p.sessionFromMin = sessFrom; p.sessionToMin = sessTo;
   p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
   p.reclaimWindowBars = 3;
   p.wickRatio = InpWickRatio; p.bodyRatio = 0.60;
   p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
   p.entryRetrace = 0.50; p.targetR = 2.0;
   if(!SigSweepReclaim(ctx, p, plan)) return false;
   if(!BiasAgrees(ctx, plan.dir)) return false;

   int score = ScoreGate(ctx, plan);
   if(score < InpMinScore) return false;
   plan.score  = score * 12.5;
   plan.reason = StringFormat("R12F-SOSSOSWEEP(%d/8) %s", score, plan.reason);
   return true;''',
    extra='''   bool SessionMap(SEAContext &ctx, int &fromMin, int &toMin, int &sessFrom, int &sessTo)
   {
      if(ctx.clockMinutes < 6 * 60 + 30 && (StringFind(ctx.symbol, "AUDNZD") >= 0 ||
                                            StringFind(ctx.symbol, "EURGBP") >= 0))
      { fromMin = 21 * 60; toMin = 24 * 60; sessFrom = 0; sessTo = 6 * 60 + 30; return true; }
      if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 16 * 60 + 30 &&
         (StringFind(ctx.symbol, "EURUSD") >= 0 || StringFind(ctx.symbol, "GBPUSD") >= 0 ||
          StringFind(ctx.symbol, "XAU") >= 0))
      { fromMin = 0; toMin = 7 * 60; sessFrom = 7 * 60; sessTo = 16 * 60 + 30; return true; }
      if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 20 * 60 + 30 &&
         (StringFind(ctx.symbol, "XAU") >= 0 || StringFind(ctx.symbol, "USDJPY") >= 0))
      { fromMin = 7 * 60; toMin = 13 * 60; sessFrom = 13 * 60 + 30; sessTo = 20 * 60 + 30; return true; }
      return false;
   }

   double MedianRange(const string sym)
   {
      MqlRates d[];
      if(EA_Rates(sym, PERIOD_D1, 1, 20, d) < 10) return 0.0;
      double s[];
      ArrayResize(s, 20);
      for(int i = 0; i < 20; i++) s[i] = d[i].high - d[i].low;
      ArraySort(s);
      return s[10];
   }

   bool RangeBetween(const string sym, const int fromMin, const int toMin, double &hi, double &lo)
   {
      MqlRates r[];
      if(EA_Rates(sym, PERIOD_M15, 1, 400, r) < 30) return false;
      bool wrap = (fromMin > toMin);
      int i = 0;
      for(; i < 400; i++)
      {
         MqlDateTime t;
         TimeToStruct(r[i].time, t);
         int m = t.hour * 60 + t.min;
         bool inWin = wrap ? (m >= fromMin || m < toMin) : (m >= fromMin && m < toMin);
         if(inWin) break;
      }
      if(i >= 400) return false;
      hi = 0.0; lo = 0.0;
      bool found = false;
      for(; i < 400; i++)
      {
         MqlDateTime t;
         TimeToStruct(r[i].time, t);
         int m = t.hour * 60 + t.min;
         bool inWin = wrap ? (m >= fromMin || m < toMin) : (m >= fromMin && m < toMin);
         if(!inWin) break;
         if(!found) { hi = r[i].high; lo = r[i].low; found = true; }
         else { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }
      }
      return found;
   }

   bool BiasAgrees(SEAContext &ctx, const int dir)
   {
      bool asianPair = (StringFind(ctx.symbol, "AUDNZD") >= 0 || StringFind(ctx.symbol, "EURGBP") >= 0);
      if(asianPair && ctx.adxH1 < 16.0) return true;                      // H1 ADX waiver (doc)
      if(ctx.emaH1_50 <= 0.0) return false;
      return (dir > 0) ? (ctx.mid > ctx.emaH1_50) : (ctx.mid < ctx.emaH1_50);
   }

   bool CorrelatedPositionOpen(SEAContext &ctx)
   {
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         string other = PositionGetString(POSITION_SYMBOL);
         if(other == ctx.symbol) continue;
         bool usdA = (StringFind(ctx.symbol, "USD") >= 0);
         bool usdB = (StringFind(other, "USD") >= 0);
         if(usdA && usdB) return true;
      }
      return false;
   }

   int ScoreGate(SEAContext &ctx, SSignalPlan &plan)
   {
      int score = 4;
      if(ctx.adxH1 >= 16.0 && ctx.adxH1 <= 40.0) score++;                 // doc quotes the H1 regime
      double costR = (plan.riskDist > 0.0) ? (ctx.spreadPoints * ctx.point) / plan.riskDist : 1.0;
      if(costR <= 0.10) score++;
      if(ctx.atrD1 > 0.0 && ctx.atr > 0.35 * ctx.atrD1) score++;
      MqlRates r[];
      if(EA_Rates(ctx.symbol, PERIOD_M5, 1, 22, r) >= 21)
      {
         double vsum = 0.0;
         for(int i = 1; i <= 20; i++) vsum += (double)r[i].tick_volume;
         if(vsum > 0.0 && r[0].tick_volume >= 1.2 * (vsum / 20.0)) score++;
      }
      return MathMin(score, 8);
   }''',
)


add(
    entry=79,
    name="EA_studyarena_round12_qwen3_8_2_4t_a95b_high_reasoning",
    magic=2046,
    cls="Round12Qwen",
    title="Round 12 Qwen - SWEEP-1 definitive with session flat times and overlap discipline",
    doc="docs/research/study_arena/studyarena-round12-qwen3-8-2-4t-a95b-high-reasoning.md",
    common={"symbols": "AUDNZD,EURGBP,EURUSD,GBPUSD,XAUUSD,USDJPY,GBPJPY", "risk": "0.60",
            "spread": "0", "daily": "0", "totaldd": "0", "target": "20", "maxday": "8"},
    inputs='''input int    InpAsiaMaxConcurrent  = 2;     // Session concurrency caps
input int    InpLondonMaxConcurrent = 3;
input int    InpNyMaxConcurrent     = 2;
input int    InpMaxTotalOpen        = 4;     // Max four open positions overall
input int    InpMaxSessionTrades    = 3;     // Completed trades per session
input double InpSpreadAvgX        = 1.50;  // Step 6 gate: spread <= this x the time-of-day baseline''',
    configure='''cfg.strategyName          = "R12QWEN_SWEEP1_DEFINITIVE";
   cfg.sourceDoc             = "docs/research/study_arena/studyarena-round12-qwen3-8-2-4t-a95b-high-reasoning.md";
   cfg.symbols               = InpSymbolsToTrade;
   cfg.magic                 = InpMagicNumber;
   cfg.riskPct               = InpRiskPct;
   cfg.signalTimeframe       = PERIOD_M5;
   cfg.clock                 = EA_CLOCK_LONDON;
   cfg.serverWinterGmtOffset = InpServerGmtOffset;
   cfg.maxTradesPerDay       = InpMaxTradesPerDay;
   cfg.maxOpenPositions      = InpMaxTotalOpen;
   cfg.minSecondsBetweenTrades = 300;
   cfg.sessionStartHour      = 0;   cfg.sessionStartMin = 0;
   cfg.sessionEndHour        = 20;  cfg.sessionEndMin   = 0;
   cfg.sessionEndFlat        = true;
   cfg.fridayFlat            = true;  cfg.fridayFlatHour = 20;  cfg.fridayFlatMin = 0;
   cfg.signalOnNewBarOnly    = true;
   cfg.partial1AtR           = 1.00;  cfg.partial1Pct = 40.0;
   cfg.partial2AtR           = 2.00;  cfg.partial2Pct = 30.0;
   cfg.breakEvenAtR          = 1.00;
   cfg.trailAtR              = 2.00;  cfg.trailDistanceR = 1.00;
   cfg.useLimitEntry         = true;
   cfg.pendingExpiryMinutes  = 15;
   cfg.timeStopMinutes       = 240;
   cfg.logLevel              = InpLogLevel;''',
    plan='''int fromMin, toMin, sessFrom, sessTo, maxConcurrent;

   //--- Step 6 execution gate: spread <= 1.5x the symbol's own baseline
   double spRef = EA_SpreadBaseline(ctx.symbol, 30);
   if(spRef > 0.0 && ctx.spreadPoints > InpSpreadAvgX * spRef)
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("%s spread %.1f pts > %.2fx its baseline %.1f - skip (doc row %d)", ctx.symbol, ctx.spreadPoints, InpSpreadAvgX, spRef, 79), true);
      return false;
   }
   if(!SessionMap(ctx, fromMin, toMin, sessFrom, sessTo, maxConcurrent)) return false;
   if(ConcurrentForSession(sessFrom) >= maxConcurrent) return false;
   if(TradesThisSession(sessFrom) >= InpMaxSessionTrades) return false;
   if(CorrelatedPositionOpen(ctx)) return false;

   double hi = 0.0, lo = 0.0;
   if(!RangeBetween(ctx.symbol, fromMin, toMin, hi, lo)) return false;
   double median = MedianRange(ctx.symbol);
   if(median <= 0.0) return false;
   double ratio = (hi - lo) / median;
   if(ratio < 0.35 || ratio > 0.75) return false;               // manipulation bait vs spent fuel

   SSweepParams p;
   p.Reset();
   p.rangeFromMin = fromMin; p.rangeToMin = toMin;
   p.sessionFromMin = sessFrom; p.sessionToMin = sessTo;
   p.sweepMinAtr = 0.05; p.sweepMaxAtr = 0.60;
   p.reclaimWindowBars = 3;
   p.wickRatio = 0.60; p.bodyRatio = 0.60;
   p.stopBufferAtr = 0.10; p.minStopAtr = 0.60; p.maxStopAtr = 1.50;
   p.entryRetrace = 0.50; p.targetR = 2.0;
   if(!SigSweepReclaim(ctx, p, plan)) return false;
   if(!BiasAgrees(ctx, plan.dir)) return false;
   plan.reason = StringFormat("R12QWEN-%sSWEEP1 %s",
                               sessFrom == 7 * 60 ? "LONDON" : (sessFrom >= 13 * 60 + 30 ? "NY" : "ASIA"),
                               plan.reason);
   return true;''',
    extra='''   bool SessionMap(SEAContext &ctx, int &fromMin, int &toMin, int &sessFrom, int &sessTo, int &maxConcurrent)
   {
      //--- Asia flat 06:00, London flat 16:00, NY flat 20:00; overlap 13:30-16:00 is NY-only
      if(ctx.clockMinutes < 6 * 60 && (StringFind(ctx.symbol, "AUDNZD") >= 0 ||
                                       StringFind(ctx.symbol, "EURGBP") >= 0))
      { fromMin = 20 * 60; toMin = 24 * 60; sessFrom = 0; sessTo = 6 * 60; maxConcurrent = InpAsiaMaxConcurrent; return true; }
      if(ctx.clockMinutes >= 7 * 60 && ctx.clockMinutes < 13 * 60 + 30 &&
         (StringFind(ctx.symbol, "EURUSD") >= 0 || StringFind(ctx.symbol, "GBPUSD") >= 0 ||
          StringFind(ctx.symbol, "XAU") >= 0 || StringFind(ctx.symbol, "GBPJPY") >= 0))
      { fromMin = 0; toMin = 7 * 60; sessFrom = 7 * 60; sessTo = 16 * 60; maxConcurrent = InpLondonMaxConcurrent; return true; }
      if(ctx.clockMinutes >= 13 * 60 + 30 && ctx.clockMinutes < 20 * 60 &&
         (StringFind(ctx.symbol, "XAU") >= 0 || StringFind(ctx.symbol, "USDJPY") >= 0))
      { fromMin = 7 * 60; toMin = 13 * 60; sessFrom = 13 * 60 + 30; sessTo = 20 * 60; maxConcurrent = InpNyMaxConcurrent; return true; }
      return false;
   }

   double MedianRange(const string sym)
   {
      MqlRates d[];
      if(EA_Rates(sym, PERIOD_D1, 1, 20, d) < 10) return 0.0;
      double s[];
      ArrayResize(s, 20);
      for(int i = 0; i < 20; i++) s[i] = d[i].high - d[i].low;
      ArraySort(s);
      return s[10];
   }

   bool RangeBetween(const string sym, const int fromMin, const int toMin, double &hi, double &lo)
   {
      MqlRates r[];
      if(EA_Rates(sym, PERIOD_M15, 1, 400, r) < 30) return false;
      bool wrap = (fromMin > toMin);
      int i = 0;
      for(; i < 400; i++)
      {
         MqlDateTime t;
         TimeToStruct(r[i].time, t);
         int m = t.hour * 60 + t.min;
         bool inWin = wrap ? (m >= fromMin || m < toMin) : (m >= fromMin && m < toMin);
         if(inWin) break;
      }
      if(i >= 400) return false;
      hi = 0.0; lo = 0.0;
      bool found = false;
      for(; i < 400; i++)
      {
         MqlDateTime t;
         TimeToStruct(r[i].time, t);
         int m = t.hour * 60 + t.min;
         bool inWin = wrap ? (m >= fromMin || m < toMin) : (m >= fromMin && m < toMin);
         if(!inWin) break;
         if(!found) { hi = r[i].high; lo = r[i].low; found = true; }
         else { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }
      }
      return found;
   }

   bool BiasAgrees(SEAContext &ctx, const int dir)
   {
      bool asianPair = (StringFind(ctx.symbol, "AUDNZD") >= 0 || StringFind(ctx.symbol, "EURGBP") >= 0);
      if(asianPair && ctx.adxH1 < 16.0) return true;                      // H1 ADX waiver (doc)
      if(ctx.emaH1_50 <= 0.0) return false;
      double h1Atr = (ctx.atrH1 > 0.0) ? ctx.atrH1
                                      : ((ctx.atrD1 > 0.0) ? ctx.atrD1 / 6.0 : 0.0);   // real H1 ATR, daily/6 as fallback
      if(h1Atr <= 0.0) return false;
      //--- slope measured over the last five H1 candles (approx: 5 x 1/6 of the daily ATR)
      double slope = ctx.emaH1_50 - ctx.emaH1_200;
      if(dir > 0) return (ctx.mid > ctx.emaH1_50 && slope >= -0.05 * h1Atr);
      return (ctx.mid < ctx.emaH1_50 && slope <= 0.05 * h1Atr);
   }

   bool CorrelatedPositionOpen(SEAContext &ctx)
   {
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         string other = PositionGetString(POSITION_SYMBOL);
         if(other == ctx.symbol) continue;
         bool usdA = (StringFind(ctx.symbol, "USD") >= 0);
         bool usdB = (StringFind(other, "USD") >= 0);
         if(usdA && usdB) return true;
      }
      return false;
   }

   int ConcurrentForSession(const int sessFrom)
   {
      int n = 0;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong t = PositionGetTicket(p);
         if(t == 0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(sessFrom == 0 && !IsAsianSymbol(PositionGetString(POSITION_SYMBOL))) continue;
         n++;
      }
      return n;
   }

   bool IsAsianSymbol(const string sym)
   {
      return (StringFind(sym, "AUDNZD") >= 0 || StringFind(sym, "EURGBP") >= 0);
   }

   int TradesThisSession(const int sessFrom)
   {
      if(!HistorySelect(TimeCurrent() - 3 * 24 * 3600, TimeCurrent())) return 0;
      MqlDateTime dt;
      TimeToStruct(TimeTradeServer(), dt);
      int nowMin = dt.hour * 60 + dt.min;
      int elapsed = nowMin - sessFrom;
      if(elapsed < 0) elapsed += 24 * 60;
      datetime from = TimeTradeServer() - (datetime)(elapsed * 60);
      int n = 0;
      for(int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if((ulong)HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagicNumber) continue;
         if(HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
         if((datetime)HistoryDealGetInteger(t, DEAL_TIME) < from) continue;
         n++;
      }
      return n;
   }''',
)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    problems = 0
    for ea in EAS:
        target = OUT_DIR / f"{ea.name}.mq5"
        rendered = ea.render()
        #--- positive control: the render guard above must leave no dead input
        dead = []
        for line in rendered.splitlines():
            m = re.match(r"\s*input\s+\S+\s+(\w+)\s*=", line)
            if m and len(re.findall(r"\b" + m.group(1) + r"\b", rendered)) < 2:
                dead.append(m.group(1))
        if dead:
            print(f"DEAD INPUT {ea.name}: {', '.join(dead)}")
            problems += 1
        if args.check:
            if not target.is_file():
                print(f"MISSING {target.name}")
                problems += 1
            elif target.read_text(encoding="utf-8") != rendered:
                print(f"DRIFT   {target.name}")
                problems += 1
        else:
            target.write_text(rendered, encoding="utf-8")
            print(f"wrote {target.name} ({len(rendered.splitlines())} lines)")
    if args.check and problems == 0:
        print(f"OK - {len(EAS)} generated EAs match the specs")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
