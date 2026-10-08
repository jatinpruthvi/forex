//+------------------------------------------------------------------+
//|                                   EA_CF_LowVolumeNode.mq5        |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Carmine Rosato's Low Volume Node Playbook (PDF, Apr 2025)         |
//| Card    : chartfanatics/todos/low-volume-node.md  (#19)            |
//| Source  : chartfanatics/pdf/low-volume-node.pdf                    |
//| Magic   : 3222                                                     |
//|                                                                    |
//| THE MODEL: price moves impulsively through areas of low volume so  |
//| that large participants can reload or defend later.  The playbook's |
//| sequence is carried in literally:                                   |
//|                                                                    |
//|   (1) identify a level of interest - a consolidation followed by an |
//|       impulsive move away ("this move confirms the presence of      |
//|       strong buyers or sellers");                                   |
//|   (2) wait - the move away is not an entry;                         |
//|   (3) find the LOW VOLUME NODE with a volume-by-price profile: the  |
//|       thin bins the impulse travelled through (a zone, not one tick);|
//|   (4) wait for price to revisit the LVN;                            |
//|   (5) look for confirmation that the level is being defended:       |
//|       absorption - each new low is bought back and the zone is not  |
//|       closed through, on above-average participation;               |
//|   (6) enter with a TIGHT stop just beyond the LVN / recent extreme, |
//|       size from the stop distance ("keep dollar risk the same");    |
//|   (7) target logical levels - the session extreme (high/low of day), |
//|       another LVN, or the prior day's extreme - and scale out        |
//|       (engine 1R partial) with the runner left for the objective.    |
//|                                                                    |
//| `[interpretation]`: the playbook confirms with heatmaps, footprint   |
//| charts and delta, which no MetaTrader EA can read - the engine has   |
//| bars and tick volume, so the defense is read as absorption on the    |
//| revisit (wick pierces the node, close returns inside it, the zone is |
//| not closed through) with above-average participation, and the LVN    |
//| itself is built from tick-volume bins (the same proxy as the library |
//| volume-profile EAs).  The base/impulse windows, the thin-bin          |
//| fraction, the revisit window and the tight-stop cap are numbers the   |
//| document does not state and are labelled here.  The document lists    |
//| "another supply or demand zone" and "support/resistance levels" as    |
//| targets; the objective ones it also lists - the session extreme, the  |
//| prior day's extreme and another LVN - are what this EA can measure.   |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "Carmine Rosato low volume node - base + impulse zone, thin volume node revisit with absorption, tight stop, logical-level targets"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade   = "US500,US100";     // the playbook's example is index futures (ES)
input ulong             InpMagicNumber      = 3222;              // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct          = 0.50;              // Risk per trade (% of equity) - sized from the stop distance
input int               InpStage             = 5;                // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input int               InpServerGmtOffset  = 2;                 // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;     // Log verbosity
input double            InpCommissionPerLotRT = 0.0;             // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.12;            // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;            // Write the engine evidence ledger CSV
//--- the level of interest: consolidation then impulse
input int    InpScanBars        = 200;   // execution bars scanned for a base + impulse
input int    InpBaseBars        = 8;     // the consolidation window
input double InpBaseMaxRangeAtr = 1.20;  // a base is a range no wider than this (execution ATR)
input int    InpImpulseBars     = 6;     // the impulsive move away
input double InpImpulseMinAtr   = 1.50;  // "rallied with strong momentum" - how far the leg must travel
//--- the low volume node
input int    InpProfileBins     = 24;    // volume-by-price buckets over the leg
input double InpThinFrac        = 0.50;  // a bucket below this fraction of the average is THIN
//--- the revisit and the defense
input int    InpConfirmBars     = 6;     // bars the revisit may have printed in
input double InpDefenseVolMult  = 1.20;  // defense participation vs the leg's average bar volume
input double InpMaxChaseAtr     = 0.25;  // the entry must sit at the node, never after a run away from it
input double InpStopBufferAtr   = 0.15;  // stop buffer beyond the node / recent extreme
input double InpMaxStopAtr      = 1.50;  // "tight stop": setups needing more are skipped
//--- targets / management
input double InpMinRr           = 2.00;  // "aim for a high reward-to-risk setup"
input double InpTargetR         = 2.00;  // runner fallback when no objective level is beyond
input double InpPartial1R       = 1.00;  // scale out: first partial at 1R
input int    InpPartialPct      = 50;    // ... half
//--- session
input int    InpSessionStartHour = 14;   // New York session, London clock
input int    InpSessionStartMin  = 30;   // 09:30 ET
input int    InpSessionEndHour   = 21;   // 16:00 ET
input int    InpSessionEndMin    = 0;
input int    InpMaxTradesPerDay  = 3;    // [interpretation]: the doc sets no daily cap

//+------------------------------------------------------------------+
class CCfLowVolumeNode : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_LOW_VOLUME_NODE";
      cfg.sourceDoc             = "chartfanatics/pdf/low-volume-node.pdf (card #19)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;     // the playbook is a day-trading / scalping model
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = 3.0;
      cfg.dailyLossPct          = 1.50;
      cfg.weeklyLossPct         = 3.0;
      cfg.totalDdPct            = 8.0;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 120;
      cfg.signalOnNewBarOnly    = true;
      cfg.useLimitEntry         = false;
      cfg.newsFilter            = false;
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_low_volume_node_ledger.csv";
      cfg.logLevel              = InpLogLevel;
      cfg.sessionStartHour = InpSessionStartHour;  cfg.sessionStartMin = InpSessionStartMin;
      cfg.sessionEndHour   = InpSessionEndHour;    cfg.sessionEndMin   = InpSessionEndMin;
      cfg.noTradeAfterHour = InpSessionEndHour;    cfg.noTradeAfterMin = InpSessionEndMin;
      //--- "you can scale out or take full profits based on context and volatility"
      cfg.partial1AtR      = InpPartial1R;  cfg.partial1Pct = InpPartialPct;
      cfg.breakEvenAtR     = 0.0;              // the doc asks for neither of these
      cfg.trailAtR         = 0.0;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   void OnInitStrategy()
   {
      m_lastPremiseBar = 0;
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "low volume node armed: base (%d bars, <= %.2f ATR) + impulse (%.2f ATR), thin bins < %.0f%% of average, revisit defense on >= %.1fx leg volume, stop <= %.2f ATR",
             InpBaseBars, InpBaseMaxRangeAtr, InpImpulseMinAtr, 100.0 * InpThinFrac,
             InpDefenseVolMult, InpMaxStopAtr), true);
   }

   //-------------------------------------------------------------------
   // LVN revisit after an impulsive move away from a consolidation
   //-------------------------------------------------------------------
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession || ctx.atr <= 0.0) return false;

      for(int dir = 1; dir >= -1; dir -= 2)       // the demand case (long) first, then supply
      {
         double baseLo = 0.0, baseHi = 0.0, legVol = 0.0;
         if(!FindZone(ctx, dir, baseLo, baseHi, legVol)) continue;

         double lvLo[]; double lvHi[];
         int    count = 0;
         if(!ThinNodes(ctx, dir, baseLo, baseHi, lvLo, lvHi, count)) continue;

         for(int i = 0; i < count; i++)
         {
            double stopRef = 0.0, defendMult = 0.0;
            if(!Defended(ctx, dir, lvLo[i], lvHi[i], legVol, stopRef, defendMult)) continue;

            //--- we are entering AT the node (the defense just held), not chasing a run away from it
            if(dir > 0 && (ctx.mid > lvHi[i] + InpMaxChaseAtr * ctx.atr || ctx.mid < lvLo[i] - InpMaxChaseAtr * ctx.atr)) continue;
            if(dir < 0 && (ctx.mid < lvLo[i] - InpMaxChaseAtr * ctx.atr || ctx.mid > lvHi[i] + InpMaxChaseAtr * ctx.atr)) continue;

            double entry = (dir > 0) ? ctx.ask : ctx.bid;
            double stop  = (dir > 0) ? stopRef - InpStopBufferAtr * ctx.atr
                                     : stopRef + InpStopBufferAtr * ctx.atr;
            double risk  = (dir > 0) ? entry - stop : stop - entry;
            if(risk <= 0.0) continue;
            if(risk > InpMaxStopAtr * ctx.atr) continue;            // "tight stop just below the zone"

            double target = BestTarget(ctx, dir, entry, risk, lvLo, lvHi, count);
            if(target <= 0.0) continue;
            double rr = MathAbs(target - entry) / risk;
            if(rr < InpMinRr) continue;                            // "aim for a high reward-to-risk setup"

            plan.dir   = dir;
            plan.entry = entry;
            plan.stop  = stop;
            plan.target = target;
            plan.riskDist = risk;
            plan.barsAgo  = 1;
            plan.score    = 74.0;
            plan.isLimit  = false;
            plan.reason   = StringFormat("LVN %s revisit: node %.2f-%.2f defended on %.1fx volume, stop %.2f, target %.2f (%.2fR)",
                                         (dir > 0) ? "demand" : "supply", lvLo[i], lvHi[i], defendMult, stop, target, rr);
            return true;
         }
      }
      return false;
   }

   //-------------------------------------------------------------------
   // Premise exit: the node is closed through - the defense failed
   //-------------------------------------------------------------------
   void Manage(SEAContext &ctx)
   {
      //--- the premise is a CLOSE through the node: evaluate once per new bar, not on every tick
      datetime barTime = iTime(ctx.symbol, g_eaIndTf, 0);
      if(barTime == m_lastPremiseBar) return;
      m_lastPremiseBar = barTime;

      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong ticket = PositionGetTicket(p);
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != ctx.symbol) continue;

         int    dir   = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? +1 : -1;
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         MqlRates m[];
         if(EA_Rates(ctx.symbol, g_eaIndTf, 0, 4, m) < 3) continue;
         //--- a close back through the node's far edge means price accepted beyond the level:
         //--- the premise ("large traders defending") is dead, exit rather than wait for the stop
         double lvLo = 0.0, lvHi = 0.0;
         if(!NodeAtPrice(ctx, dir, entry, lvLo, lvHi)) continue;
         bool through = (dir > 0) ? (m[1].close < lvLo) : (m[1].close > lvHi);
         if(!through) continue;
         EA_Log(EA_LOG_EVENTS, StringFormat("node closed through (%.2f) - the defense failed, exiting", m[1].close), true);
         g_eaExec.Close(ticket, "LVN closed through");
      }
   }

private:
   datetime m_lastPremiseBar;

   //-------------------------------------------------------------------
   // (1)+(2) consolidation, then the impulsive move away
   //-------------------------------------------------------------------
   bool FindZone(const SEAContext &ctx, const int dir, double &baseLo, double &baseHi, double &legVol)
   {
      baseLo = 0.0; baseHi = 0.0; legVol = 0.0;
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, InpScanBars + 2, r);
      if(got < InpBaseBars + InpImpulseBars + 4) return false;

      double atr = ctx.atr;
      for(int b = 3; b <= got - InpBaseBars - InpImpulseBars - 1; b++)
      {
         //--- the base: bars [b .. b + InpBaseBars - 1] (older), a tight consolidation
         double bLo = DBL_MAX, bHi = -DBL_MAX;
         for(int i = b; i < b + InpBaseBars; i++)
         { bLo = MathMin(bLo, r[i].low); bHi = MathMax(bHi, r[i].high); }
         double baseRange = bHi - bLo;
         if(baseRange <= 0.0 || baseRange > InpBaseMaxRangeAtr * atr) continue;

         //--- the impulse: bars [b - InpImpulseBars .. b - 1] (newer) moving away from the base
         double move = r[b - 1].close - r[b].close;
         double legHigh = -DBL_MAX, legLow = DBL_MAX;
         for(int i = b - InpImpulseBars; i <= b - 1; i++)
         { legHigh = MathMax(legHigh, r[i].high); legLow = MathMin(legLow, r[i].low); }
         if(dir > 0)
         {
            if(move < InpImpulseMinAtr * atr) continue;            // up and away: a demand base
            if(legLow < bLo) continue;                             // the leg must not trade back through the base low
         }
         else
         {
            if(-move < InpImpulseMinAtr * atr) continue;           // down and away: a supply base
            if(legHigh > bHi) continue;
         }

         //--- the leg's average bar volume (the participation baseline for the defense test)
         double vol = 0.0;
         int n = 0;
         for(int i = b - InpImpulseBars; i <= b + InpBaseBars - 1; i++) { vol += (double)r[i].tick_volume; n++; }
         if(n <= 0 || vol <= 0.0) continue;

         baseLo = bLo; baseHi = bHi; legVol = vol / (double)n;
         return true;
      }
      return false;
   }

   //-------------------------------------------------------------------
   // (3) the low volume node(s) inside the leg, from tick-volume bins
   //-------------------------------------------------------------------
   //--- `[interpretation]`: the playbook reads a real volume profile; the engine has bar
   //--- tick volume, so that is what is bucketed - the same proxy as the library's
   //--- volume-profile EAs.  Thin bins are merged into zones ("an LVN can be a zone").
   bool ThinNodes(const SEAContext &ctx, const int dir, const double baseLo, const double baseHi,
                  double &lvLo[], double &lvHi[], int &count)
   {
      ArrayResize(lvLo, 0); ArrayResize(lvHi, 0); count = 0;
      if(InpProfileBins < 8) return false;

      MqlRates r[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, InpScanBars + 2, r);
      if(got < InpBaseBars + InpImpulseBars + 4) return false;

      //--- re-find the leg window (the base end bar): the newest base+impulse that matches the zone
      for(int b = 3; b <= got - InpBaseBars - InpImpulseBars - 1; b++)
      {
         double bLo = DBL_MAX, bHi = -DBL_MAX;
         for(int i = b; i < b + InpBaseBars; i++)
         { bLo = MathMin(bLo, r[i].low); bHi = MathMax(bHi, r[i].high); }
         if(MathAbs(bLo - baseLo) > 1e-9 || MathAbs(bHi - baseHi) > 1e-9) continue;

         int from = b - InpImpulseBars, to = b + InpBaseBars - 1;
         double pHi = -DBL_MAX, pLo = DBL_MAX;
         for(int i = from; i <= to; i++)
         { pHi = MathMax(pHi, r[i].high); pLo = MathMin(pLo, r[i].low); }
         if(pHi <= pLo) return false;

         int    nb = InpProfileBins;
         double binVol[]; ArrayResize(binVol, nb); ArrayInitialize(binVol, 0.0);
         double size = (pHi - pLo) / nb;
         for(int i = from; i <= to; i++)
         {
            int b1 = (int)MathFloor((r[i].low - pLo) / size);
            int b2 = (int)MathFloor((r[i].high - pLo) / size);
            b1 = (int)MathMax(0, MathMin(nb - 1, b1));
            b2 = (int)MathMax(0, MathMin(nb - 1, b2));
            double v = (double)r[i].tick_volume;
            int span = b2 - b1 + 1;
            for(int k = b1; k <= b2; k++) binVol[k] += v / (double)span;
         }

         double total = 0.0;
         for(int k = 0; k < nb; k++) total += binVol[k];
         if(total <= 0.0) return false;
         double avg = total / (double)nb;

         //--- merge contiguous thin bins into zones, keeping them on the impulse side of the base
         int run = -1;
         for(int k = 0; k <= nb; k++)
         {
            bool thin = (k < nb) && (binVol[k] < InpThinFrac * avg);
            if(thin && run < 0) run = k;
            if(thin) continue;
            if(run >= 0)
            {
               double zLo = pLo + run * size;
               double zHi = pLo + k * size;
               run = -1;
               if(dir > 0 && zHi < baseHi) continue;               // demand: the node sits above the base
               if(dir < 0 && zLo > baseLo) continue;               // supply: the node sits below the base
               ArrayResize(lvLo, count + 1); ArrayResize(lvHi, count + 1);
               lvLo[count] = zLo; lvHi[count] = zHi; count++;
            }
         }
         return (count > 0);
      }
      return false;
   }

   //-------------------------------------------------------------------
   // (4)+(5) the revisit and the absorption that confirms defense
   //-------------------------------------------------------------------
   bool Defended(const SEAContext &ctx, const int dir, const double lvLo, const double lvHi,
                 const double legVol, double &stopRef, double &defendMult)
   {
      stopRef = 0.0; defendMult = 0.0;
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, InpConfirmBars + 24, r);
      if(got < InpConfirmBars + 4) return false;

      //--- price had to move away first and is now back inside the node
      bool touched = false;
      double ext = (dir > 0) ? DBL_MAX : -DBL_MAX;
      double vol = 0.0;
      int    n = 0;
      for(int i = 1; i <= InpConfirmBars; i++)
      {
         if(dir > 0)
         {
            if(r[i].low <= lvHi) touched = true;
            ext = MathMin(ext, r[i].low);
            //--- a close through the node: price accepted below it, no defense
            if(r[i].close < lvLo) return false;
         }
         else
         {
            if(r[i].high >= lvLo) touched = true;
            ext = MathMax(ext, r[i].high);
            if(r[i].close > lvHi) return false;
         }
         vol += (double)r[i].tick_volume; n++;
      }
      if(!touched || n <= 0) return false;

      //--- absorption: the newest completed bar refused the extension and closed back inside the node
      bool refused = (dir > 0) ? (r[1].low <= lvHi && r[1].close > lvLo)
                               : (r[1].high >= lvLo && r[1].close < lvHi);
      if(!refused) return false;

      //--- participation: defenders show up with above-average volume against the leg's baseline
      double avgVol = vol / (double)n;
      if(legVol > 0.0 && avgVol < InpDefenseVolMult * legVol) return false;

      //--- the tight stop: beyond the node's far edge and the revisit extreme
      stopRef = (dir > 0) ? MathMin(ext, lvLo) : MathMax(ext, lvHi);
      defendMult = (legVol > 0.0) ? avgVol / legVol : 0.0;
      return true;
   }

   //-------------------------------------------------------------------
   // (7) targets: the session extreme, another LVN, the prior day
   //-------------------------------------------------------------------
   double BestTarget(const SEAContext &ctx, const int dir, const double entry, const double risk,
                     const double &lvLo[], const double &lvHi[], const int count)
   {
      double floorDist = InpMinRr * risk;         // "high reward-to-risk": the objective must clear the floor
      double best = 0.0, bestDist = 0.0;

      //--- high / low of day (the playbook's own example target)
      double hod = 0.0, lod = 0.0;
      int    bars = 0;
      int    nowMin = 0;
      MqlDateTime dt;
      if(TimeToStruct(EA_ClockNow(), dt)) nowMin = dt.hour * 60 + dt.min;
      if(nowMin <= 0) nowMin = 1;
      if(SigRangeForDay(ctx.symbol, g_eaIndTf, 0, nowMin, 0, hod, lod, bars) && bars > 0)
      {
         double dayLevel = (dir > 0) ? hod : lod;
         double dist = (dir > 0) ? (dayLevel - entry) : (entry - dayLevel);
         if(dist >= floorDist) { best = dayLevel; bestDist = dist; }
      }

      //--- the prior day's extreme
      MqlRates d[];
      if(EA_Rates(ctx.symbol, PERIOD_D1, 1, 3, d) >= 2)
      {
         double prior = (dir > 0) ? d[0].high : d[0].low;
         double dist = (dir > 0) ? (prior - entry) : (entry - prior);
         if(dist >= floorDist && (best == 0.0 || dist < bestDist)) { best = prior; bestDist = dist; }
      }

      //--- another node further along the path (never the node the trade is taken from)
      for(int i = 0; i < count; i++)
      {
         double tol = 0.10 * risk;
         if(entry >= lvLo[i] - tol && entry <= lvHi[i] + tol) continue;   // this is our own node
         double node = (dir > 0) ? lvHi[i] : lvLo[i];
         double dist = (dir > 0) ? (node - entry) : (entry - node);
         if(dist < floorDist) continue;
         if(best != 0.0 && dist >= bestDist) continue;
         best = node; bestDist = dist;
      }

      if(best == 0.0) best = (dir > 0) ? (entry + InpTargetR * risk) : (entry - InpTargetR * risk);
      return best;
   }

   //--- the node the open position was taken from (its zone contains the entry region)
   bool NodeAtPrice(const SEAContext &ctx, const int dir, const double entry, double &lvLo, double &lvHi)
   {
      lvLo = 0.0; lvHi = 0.0;
      MqlRates r[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, InpScanBars + 2, r);
      if(got < InpBaseBars + InpImpulseBars + 4) return false;
      for(int b = 3; b <= got - InpBaseBars - InpImpulseBars - 1; b++)
      {
         double bLo = DBL_MAX, bHi = -DBL_MAX;
         for(int i = b; i < b + InpBaseBars; i++)
         { bLo = MathMin(bLo, r[i].low); bHi = MathMax(bHi, r[i].high); }
         double baseRange = bHi - bLo;
         if(baseRange <= 0.0) continue;
         double lLo[]; double lHi[]; int count = 0;
         if(!ThinNodes(ctx, dir, bLo, bHi, lLo, lHi, count)) continue;
         for(int i = 0; i < count; i++)
         {
            if(lHi[i] < bHi && dir > 0) continue;
            if(lLo[i] > bLo && dir < 0) continue;
            if(MathAbs(entry - (lLo[i] + lHi[i]) / 2.0) > (lHi[i] - lLo[i]) + ctx.atr) continue;
            lvLo = lLo[i]; lvHi = lHi[i];
            return true;
         }
      }
      return false;
   }
};

CCfLowVolumeNode g_cfLowVolumeNode;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfLowVolumeNode);
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
