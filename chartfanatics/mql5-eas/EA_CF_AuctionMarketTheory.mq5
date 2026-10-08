//+------------------------------------------------------------------+
//|                                  EA_CF_AuctionMarketTheory.mq5   |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| ChartFanatics playbook: Auction Market Theory (Andrea Cimita)     |
//| Card    : chartfanatics/todos/auction-market-theory-strategy.md   |
//|           (#06)                                                  |
//| Source  : chartfanatics/pdf/auction-market-theory-strategy.pdf    |
//| Magic   : 3211                                                   |
//|                                                                  |
//| The playbook's core question is one: "Is the aggressive side      |
//| being accepted or absorbed?"  Everything below is that question   |
//| made mechanical, around a volume-profile value area (VAL/VAH/POC):|
//|                                                                  |
//|   SETUP 1  Failed auction BELOW value -> reversal long            |
//|   SETUP 2  Failed auction ABOVE value -> reversal short           |
//|   SETUP 3  Breakout WITH acceptance -> continuation               |
//|                                                                  |
//| The trade breakdown in the playbook is exactly these three plus   |
//| the opening range: price at the value area low (confluence with   |
//| the previous day's VAL); aggressive sellers fail to continue      |
//| (absorption); buyers take control (confirmation, not the first    |
//| move); stop under the area where the aggressive sellers worked;   |
//| target the rotation across value.  The ORB follow-up is traded    |
//| only when participation shows in the BODY - activity on the wick  |
//| is effort without acceptance and is refused.                      |
//|                                                                  |
//| Exit: "the exit occurred when buyers began to get absorbed near   |
//| the highs and sellers started to take control" -> the custom      |
//| Manage() below closes the position when a strong opposing bar     |
//| closes back through the value edge the trade came from, once the  |
//| trade is in profit.  That is the playbook's own exit rule, not a  |
//| generic trailing stop.                                            |
//|                                                                  |
//| `[interpretation]`: the engine has bar tick volume rather than a  |
//| real volume profile or footprint data, so the profile is built    |
//| from tick volume and "aggression" is read as body + volume.  See  |
//| mql5-eas/README.md for the full list.                             |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "ChartFanatics Auction Market Theory - failed auctions and accepted breakouts around the value area"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade   = "US100,US500,GER40";  // Futures per the playbook
input ulong             InpMagicNumber      = 3211;                 // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct          = 0.40;                 // "tight and efficient risk" - 0.25-0.5% band
input int               InpStage             = 5;                   // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input double            InpMaxSpreadPoints  = 3.0;                  // Spread gate in points (0 = off)
input double            InpDailyLossPct     = 1.50;                 // Halt for the day at -x% (0 = off)
input int               InpServerGmtOffset  = 2;                    // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;        // Log verbosity
input double            InpCommissionPerLotRT = 0.0;                // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.12;               // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;               // Write the engine evidence ledger CSV
//--- value area (the "fair value" reference)
input int    InpProfileBins   = 40;     // Price bins for the tick-volume profile
input double InpValueAreaPct  = 0.70;   // [interpretation] standard 70% value area (the doc does not quantify it)
input int    InpValueBars     = 288;    // Bars of the value reference (one M5 day = 288)
input int    InpFailLookback  = 12;     // Bars a failed auction may have printed in
//--- acceptance / confirmation
input double InpAcceptBody    = 0.55;   // "activity in the body, not the wick" - body ratio
input double InpAcceptVol     = 1.15;   // Participation continues: volume vs its 20-bar average
input double InpMinStopAtr    = 0.15;   // Reject stops tighter than this
input int    InpStopBufferTicks = 2;    // Buffer before the obvious swing (keeps the stop off the wick)
input double InpStopBufferAtr = 0.08;
input double InpMinRR         = 1.20;   // POC rotation must pay for the risk
//--- setups and windows (London clock; New York = London - 5 in winter)
input bool   InpTradeReversal = true;   // Setups 1 & 2
input bool   InpTradeBreakout = true;   // Setup 3 (with acceptance)
input int    InpOrbFromMin    = 870;    // 14:30 London = 09:30 ET - opening range start
input int    InpOrbToMin      = 900;    // the first 30 minutes: the opening range itself
input int    InpEntryToMin    = 1200;   // 20:00 London = 15:00 ET - last entries
//--- the playbook's own exit ("opposing pressure takes over")
input bool   InpUseFlowExit   = true;   // Close when the opposing side prints its control back
input double InpFlowExitR     = 0.50;   // Only once the trade is this far in profit

//+------------------------------------------------------------------+
struct SVolProfile
{
   double poc, val, vah;
   bool   ok;
};

//+------------------------------------------------------------------+
class CCfAuctionMarketTheory : public CEAStrategy
{
public:
   void OnInitStrategy()
   {
      EA_Log(EA_LOG_EVENTS, StringFormat("5-stage policy: stage %d active (risk %.3f%%, %d trades/day max)",
             InpStage, g_eaCfg.riskPct, g_eaCfg.maxTradesPerDay), true);
      EA_Log(EA_LOG_EVENTS, "AMT armed: failed auctions -> rotation to POC; breakouts only WITH acceptance", true);
   }

   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_AUCTION_MARKET_THEORY";
      cfg.sourceDoc             = "chartfanatics/pdf/auction-market-theory-strategy.pdf (card #06)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = InpMaxSpreadPoints;
      cfg.dailyLossPct          = InpDailyLossPct;
      cfg.weeklyLossPct         = 3.0;
      cfg.totalDdPct            = 8.0;
      cfg.maxTradesPerDay       = 3;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 180;
      cfg.sessionStartHour      = 14;  cfg.sessionStartMin = 25;   // before the 09:30 ET opening range
      cfg.sessionEndHour        = 20;  cfg.sessionEndMin   = 0;
      cfg.noTradeAfterHour      = 20;  cfg.noTradeAfterMin = 0;
      cfg.fridayFlat            = true;  cfg.fridayFlatHour = 18;  cfg.fridayFlatMin = 0;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = false;                            // confirmation entries, never blind limits
      cfg.breakEvenAtR          = 1.0;                              // "risk is defined by logic" - protect it
      cfg.partial1AtR           = 1.0;  cfg.partial1Pct = 50.0;     // rotation to POC: bank half on the way
      cfg.trailAtR              = 1.5;  cfg.trailDistanceR = 0.75;
      cfg.commissionPerLotRT    = InpCommissionPerLotRT;
      cfg.maxCostR              = InpMaxCostR;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_auction_amt_ledger.csv";
      cfg.newsFilter            = false;
      cfg.logLevel              = InpLogLevel;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession || ctx.atr <= 0.0) return false;
      if(ctx.clockMinutes > InpEntryToMin) return false;

      SVolProfile prev;
      if(!BuildProfile(ctx.symbol, 1, InpValueBars, prev)) return false;

      //--- the opening range (the playbook's ORB layer)
      double orbHi = 0.0, orbLo = 0.0;
      int orbBars = 0;
      bool haveOrb = SigRangeForDay(ctx.symbol, g_eaIndTf, InpOrbFromMin, InpOrbToMin, 0, orbHi, orbLo, orbBars);

      if(InpTradeReversal && FailedAuction(ctx, prev, plan)) return true;
      if(InpTradeBreakout && AcceptedBreakout(ctx, prev, haveOrb, orbHi, orbLo, plan)) return true;
      return false;
   }

   //--- the playbook's exit: "monitor shifts in participation. Exit when opposing pressure takes
   //--- over."  Mechanized as: while the trade is in profit, a strong opposing body that closes
   //--- back through the value edge the trade came from ends it.  Never widens anything.
   void Manage(SEAContext &ctx)
   {
      if(!InpUseFlowExit) return;
      if(ctx.atr <= 0.0) return;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;

         int    dir   = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? +1 : -1;
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl    = PositionGetDouble(POSITION_SL);
         double risk  = (sl > 0.0) ? MathAbs(entry - sl) : ctx.atr;   // ATR fallback if the stop is unset
         double moveR = (dir > 0) ? (ctx.mid - entry) : (entry - ctx.mid);
         if(moveR < InpFlowExitR * risk) continue;            // only once the trade is working

         MqlRates r[];
         if(EA_Rates(ctx.symbol, g_eaIndTf, 0, 24, r) < 21) continue;
         double avg = 0.0;
         for(int k = 2; k <= 21; k++) avg += (double)r[k].tick_volume;
         avg /= 20.0;
         bool strong = (EA_BodyRatio(r[1]) >= InpAcceptBody) && (avg <= 0.0 ||
                       (double)r[1].tick_volume >= InpAcceptVol * avg);
         if(!strong) continue;

         SVolProfile p;
         if(!BuildProfile(ctx.symbol, 1, InpValueBars, p)) continue;
         bool opposing = (dir > 0) ? (r[1].close < r[1].open && r[1].close < p.val)
                                   : (r[1].close > r[1].open && r[1].close > p.vah);
         if(!opposing) continue;

         EA_Log(EA_LOG_EVENTS, StringFormat(
                "flow exit: opposing pressure closed back through value (%.2fR) - closing", moveR / risk), true);
         g_eaExec.Close(ticket, "opposing pressure");
      }
   }

private:
   //--- aggression / acceptance proxy from bars: a strong body in the given direction with
   //--- above-average participation.  `[interpretation]` (tick volume, not footprint prints).
   bool StrongBody(const SEAContext &ctx, const int dir, const double bodyMin)
   {
      MqlRates r[];
      if(EA_Rates(ctx.symbol, g_eaIndTf, 0, 24, r) < 21) return false;
      if(EA_BodyRatio(r[1]) < bodyMin) return false;
      if(dir > 0 && !(r[1].close > r[1].open)) return false;
      if(dir < 0 && !(r[1].close < r[1].open)) return false;
      double avg = 0.0;
      for(int i = 2; i <= 21; i++) avg += (double)r[i].tick_volume;
      avg /= 20.0;
      return (avg <= 0.0 || (double)r[1].tick_volume >= InpAcceptVol * avg);
   }

   double StopFor(const SEAContext &ctx, const int dir, const double printExtreme)
   {
      double tick = SymbolInfoDouble(ctx.symbol, SYMBOL_TRADE_TICK_SIZE);
      double buffer = MathMax((double)InpStopBufferTicks * tick, InpStopBufferAtr * ctx.atr);
      return (dir > 0) ? printExtreme - buffer : printExtreme + buffer;
   }

   //--- SETUPS 1 & 2: a failed auction at a value edge, absorbed, then reclaimed.  Entry on the
   //--- confirmation bar; stop beyond the place where the failing side was aggressive; target the
   //--- rotation back to the POC (and, when it is ahead, the opposite value edge).
   bool FailedAuction(SEAContext &ctx, const SVolProfile &prev, SSignalPlan &plan)
   {
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, InpFailLookback + 6, r);
      if(got < InpFailLookback + 2) return false;

      for(int dir = +1; dir >= -1; dir -= 2)
      {
         double edge = (dir > 0) ? prev.val : prev.vah;
         //--- the failed auction: a bar beyond the edge that closed back inside (absorption)
         int failIdx = -1;
         for(int i = 2; i <= InpFailLookback && i < got; i++)
         {
            bool beyond = (dir > 0) ? (r[i].low < edge) : (r[i].high > edge);
            bool backIn = (dir > 0) ? (r[i].close > edge) : (r[i].close < edge);
            if(beyond && backIn) { failIdx = i; break; }
         }
         if(failIdx < 3) continue;                 // the confirmation bar must be separate

         //--- confirmation: the aggressive side has switched (body + participation, in `dir`)
         if(!StrongBody(ctx, dir, InpAcceptBody)) continue;

         //--- the failing side's extreme is where the idea dies
         double print = (dir > 0) ? r[failIdx].low : r[failIdx].high;
         double entry = (dir > 0) ? ctx.ask : ctx.bid;
         double stop  = StopFor(ctx, dir, print);
         double risk  = MathAbs(entry - stop);
         if(risk < InpMinStopAtr * ctx.atr) return false;

         //--- "The target is a return to fair value, and potentially the opposite side of the range"
         double target = (dir > 0) ? MathMax(prev.poc, prev.vah) : MathMin(prev.poc, prev.val);
         if(dir > 0 && target <= entry) target = prev.poc;
         if(dir < 0 && target >= entry) target = prev.poc;
         if(dir > 0 && target <= entry) return false;
         if(dir < 0 && target >= entry) return false;
         if(MathAbs(target - entry) < InpMinRR * risk) return false;

         plan.dir = dir; plan.entry = entry; plan.stop = stop; plan.target = target;
         plan.riskDist = risk; plan.barsAgo = 1; plan.score = 72.0; plan.isLimit = false;
         plan.reason = StringFormat("failed auction %s value %.2f -> POC %.2f",
                                    (dir > 0 ? "below" : "above"), edge, prev.poc);
         return true;
      }
      return false;
   }

   //--- SETUP 3: a breakout with acceptance.  Acceptance = price HOLDS outside the level, on the
   //--- body, with participation - the playbook's own contrast between the wick attempt (refused)
   //--- and the body attempt (taken).  The opening range is the level when it exists.
   bool AcceptedBreakout(SEAContext &ctx, const SVolProfile &prev, const bool haveOrb,
                         const double orbHi, const double orbLo, SSignalPlan &plan)
   {
      MqlRates r[];
      if(EA_Rates(ctx.symbol, g_eaIndTf, 0, 8, r) < 6) return false;

      for(int dir = +1; dir >= -1; dir -= 2)
      {
         if(!haveOrb) continue;
         double level = (dir > 0) ? orbHi : orbLo;
         if(level <= 0.0) continue;

         //--- the breakout bar (two bars back at most): closed beyond the level with a body
         int brkIdx = -1;
         for(int i = 2; i <= 3; i++)
         {
            bool beyond = (dir > 0) ? (r[i].close > level) : (r[i].close < level);
            if(beyond && EA_BodyRatio(r[i]) >= InpAcceptBody) { brkIdx = i; break; }
         }
         if(brkIdx < 0) continue;

         //--- acceptance on the last closed bar: HOLDS outside, no immediate rejection, participation.
         //--- "Activity on the wick, not the body" (the refused first attempt) is exactly what this
         //--- body+hold test excludes.
         bool holds = (dir > 0) ? (r[1].low >= level - 0.10 * ctx.atr && r[1].close > level)
                                : (r[1].high <= level + 0.10 * ctx.atr && r[1].close < level);
         if(!holds) continue;
         if(!StrongBody(ctx, dir, InpAcceptBody)) continue;

         //--- location matters too: the acceptance should happen on the aggressive side of value
         SVolProfile now;
         if(BuildProfile(ctx.symbol, 1, 96, now))
         {
            if(dir > 0 && now.poc < prev.poc) continue;      // buying under the old value centre: skip
            if(dir < 0 && now.poc > prev.poc) continue;
         }

         double entry = (dir > 0) ? ctx.ask : ctx.bid;
         double structure = (dir > 0) ? MathMin(r[1].low, r[brkIdx].low)
                                      : MathMax(r[1].high, r[brkIdx].high);
         double stop = StopFor(ctx, dir, structure);
         double risk = MathAbs(entry - stop);
         if(risk < InpMinStopAtr * ctx.atr) return false;

         //--- "target is continuation in the direction of the move": one value-area width, R floor
         double width = MathAbs(prev.vah - prev.val);
         double target = (dir > 0) ? entry + MathMax(width, 2.0 * risk)
                                   : entry - MathMax(width, 2.0 * risk);
         if(MathAbs(target - entry) < InpMinRR * risk) return false;

         plan.dir = dir; plan.entry = entry; plan.stop = stop; plan.target = target;
         plan.riskDist = risk; plan.barsAgo = 1; plan.score = 70.0; plan.isLimit = false;
         plan.reason = StringFormat("accepted breakout %s %.2f (body held outside value)",
                                    (dir > 0 ? "above" : "below"), level);
         return true;
      }
      return false;
   }

   //--- tick-volume profile over bars [fromBar..toBar]; same construction as card #05's EA
   //--- `[interpretation]`: bar tick volume stands in for a true volume profile.
   bool BuildProfile(const string sym, const int fromBar, const int toBar, SVolProfile &out)
   {
      out.ok = false; out.poc = 0.0; out.val = 0.0; out.vah = 0.0;
      if(InpProfileBins < 8) return false;
      MqlRates r[];
      int got = EA_Rates(sym, g_eaIndTf, 0, toBar + 2, r);
      if(got < toBar + 1) return false;

      double hi = -DBL_MAX, lo = DBL_MAX;
      for(int i = fromBar; i <= toBar && i < got; i++)
      { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }
      if(hi <= lo) return false;

      int nb = InpProfileBins;
      double binVol[]; ArrayResize(binVol, nb); ArrayInitialize(binVol, 0.0);
      double size = (hi - lo) / nb;
      for(int i = fromBar; i <= toBar && i < got; i++)
      {
         int b1 = (int)MathMax(0, MathMin(nb - 1, (int)MathFloor((r[i].low - lo) / size)));
         int b2 = (int)MathMax(0, MathMin(nb - 1, (int)MathFloor((r[i].high - lo) / size)));
         double v = (double)r[i].tick_volume;
         int span = b2 - b1 + 1;
         for(int b = b1; b <= b2; b++) binVol[b] += v / (double)span;
      }

      int pocBin = 0;
      double total = 0.0;
      for(int b = 0; b < nb; b++)
      {
         total += binVol[b];
         if(binVol[b] > binVol[pocBin]) pocBin = b;
      }
      if(total <= 0.0) return false;

      int loBin = pocBin, hiBin = pocBin;
      double covered = binVol[pocBin];
      while(covered < InpValueAreaPct * total && (loBin > 0 || hiBin < nb - 1))
      {
         double below = (loBin > 0) ? binVol[loBin - 1] : -1.0;
         double above = (hiBin < nb - 1) ? binVol[hiBin + 1] : -1.0;
         if(above >= below) { hiBin++; covered += binVol[hiBin]; }
         else               { loBin--; covered += binVol[loBin]; }
      }

      out.poc = lo + (pocBin + 0.5) * size;
      out.val = lo + loBin * size;
      out.vah = lo + (hiBin + 1) * size;
      out.ok  = true;
      return true;
   }
};

CCfAuctionMarketTheory g_cfAuctionMarketTheory;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfAuctionMarketTheory);
}

void OnTick()
{
   EA_Tick();
}

void OnDeinit(const int reason)
{
   EA_Deinit(reason);
}
//+------------------------------------------------------------------+
