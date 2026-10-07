//+------------------------------------------------------------------+
//|                               EA_CF_MarketAuctionTheory.mq5      |
//|                                  Copyright 2026, Master Strategy |
//|                                                                  |
//| Rajan Dhall's Market Auction Theory Playbook (PDF, Apr 2025)       |
//| Card    : chartfanatics/todos/market-auction-theory.md  (#20)      |
//| Source  : chartfanatics/pdf/market-auction-theory.pdf              |
//| Magic   : 3223                                                     |
//|                                                                    |
//| THE MODEL - top down, and both timeframes must agree:               |
//|                                                                    |
//|   (1) the DAILY chart sets the bias: the previous day's candle must |
//|       have closed strongly in one direction (bearish -> short bias, |
//|       bullish -> long bias) and the daily must show a clear         |
//|       45-degree trend;                                              |
//|   (2) the 5-MINUTE chart must mirror that trend - price on the same |
//|       side of the moving averages, which "confirm alignment, then   |
//|       are not trade signals";                                       |
//|   (3) the AUCTION ZONE is the congestion after the open where price |
//|       found balance ("a place where short-term buyers and sellers   |
//|       had found a temporary balance");                              |
//|   (4) price must LEAVE the zone in the trend direction (the         |
//|       breakdown's "broke down from this zone, confirming trend      |
//|       continuation"), then RETURN to it;                            |
//|   (5) the setup is the REJECTION candle - it trades into the zone   |
//|       and closes back out of it in the trend direction; the entry   |
//|       is made immediately after that candle closes;                 |
//|   (6) the stop sits just beyond the setup candle's high (shorts) /  |
//|       low (longs), and the target is a minimum 2:1 reward-to-risk   |
//|       ("most trades target 2:1");                                   |
//|   (7) time of day: the FIRST HOUR after the open; the middle and    |
//|       late session are avoided unless conditions clearly align.     |
//|                                                                    |
//| No-trade conditions the EA enforces: the timeframes disagree, the   |
//| auction structure is messy (the post-open congestion is not a        |
//| range), price never left the zone, price never retests it, or the    |
//| engine's calendar flags a high-impact release (the mechanical        |
//| stand-in for "conflicting news headlines").                          |
//|                                                                    |
//| `[interpretation]`: the document's numbers are illustrative, so the  |
//| formation window and the congestion cap that define the auction      |
//| zone, the daily 45-degree slope threshold, the "strongly" body       |
//| threshold, the stop tick buffer and the second-entry allowance are   |
//| labelled here.  The daily 21/50 pair the document quotes is computed |
//| locally (the engine carries only the daily 200), with the same EMA   |
//| definition.  The extended window (the doc's "unless conditions       |
//| clearly align") is an input, off by default.                         |
//+------------------------------------------------------------------+
#property copyright "Master Strategy"
#property link      ""
#property version   "1.00"
#property description "Rajan Dhall market auction theory - daily bias + 5m alignment, post-open auction zone, rejection entry, 2:1 target, first-hour window"

#include "..\..\Include\EACommon.mqh"

//--- identity / risk
input string            InpSymbolsToTrade   = "US500,US100";     // stocks / indices / crypto - the doc's own list
input ulong             InpMagicNumber      = 3223;              // UNIQUE MAGIC NUMBER FOR THIS STRATEGY
input double            InpRiskPct          = 0.50;              // Risk per trade (% of equity)
input int               InpStage             = 5;                // 5-Stage framework stage (1 novice .. 5 pro; 5 = policy off)
input int               InpServerGmtOffset  = 2;                 // Broker server clock minus GMT (winter)
input ENUM_EA_LOG_LEVEL InpLogLevel         = EA_LOG_EVENTS;     // Log verbosity
input double            InpCommissionPerLotRT = 0.0;             // Round-turn commission per lot (engine cost gate)
input double            InpMaxCostR           = 0.12;            // Cost gate: (spread + commission) <= xR
input bool              InpLedger             = true;            // Write the engine evidence ledger CSV
//--- the daily bias
input double InpBiasBodyMin     = 0.60;  // "closed strongly bearish / bullish": body fraction of the candle
input int    InpSlopeDays      = 5;      // days the 45-degree trend is measured over
input double InpSlopeAtr       = 1.50;   // a clear trend moves at least this many daily ATRs over those days
input bool   InpRequireGap      = true;  // the open/gap context must agree with the bias (the breakdown's gap down)
//--- the auction zone
input int    InpFormationMin    = 20;    // the post-open congestion window (minutes) that becomes the zone
input double InpZoneMaxAtr      = 1.60;  // a balance is no wider than this (5m ATR); wider = "messy structure"
input int    InpConfirmBars     = 3;     // bars the rejection must have printed in (the entry is right after)
//--- entry / stop / target
input double InpStopBufferTicks = 2.0;   // buffer beyond the setup candle's extreme
input double InpTargetR         = 2.0;   // "minimum 2:1 risk-to-reward"
//--- session
input int    InpOpenHour        = 14;    // New York open, London clock
input int    InpOpenMin         = 30;    // 09:30 ET
input int    InpWindowMinutes   = 60;    // "focus on the first hour after the open"
input bool   InpExtendedWindow  = false; // [interpretation] the doc's "unless conditions clearly align"
input int    InpExtendedEndHour = 21;    // extended window end (London) when InpExtendedWindow is on
input int    InpMaxTradesPerDay = 2;     // the breakdown's first and second retest

//+------------------------------------------------------------------+
class CCfMarketAuctionTheory : public CEAStrategy
{
public:
   void Configure(SEASettings &cfg)
   {
      cfg.strategyName          = "CF_MARKET_AUCTION_THEORY";
      cfg.sourceDoc             = "chartfanatics/pdf/market-auction-theory.pdf (card #20)";
      cfg.symbols               = InpSymbolsToTrade;
      cfg.magic                 = InpMagicNumber;
      cfg.riskPct               = InpRiskPct;
      cfg.signalTimeframe       = PERIOD_M5;      // "5-minute chart: execution timeframe"
      cfg.clock                 = EA_CLOCK_LONDON;
      cfg.serverWinterGmtOffset = InpServerGmtOffset;
      cfg.maxSpreadPoints       = 3.0;
      cfg.dailyLossPct          = 1.50;
      cfg.weeklyLossPct         = 3.0;
      cfg.totalDdPct            = 8.0;
      cfg.maxTradesPerDay       = InpMaxTradesPerDay;
      cfg.maxOpenPositions      = 1;
      cfg.minSecondsBetweenTrades = 120;
      cfg.signalOnNewBarOnly    = true;           // "entry is made immediately after candle confirmation"
      cfg.useLimitEntry         = false;
      cfg.newsFilter            = true;           // the mechanical stand-in for "conflicting news headlines"
      cfg.ledgerEnabled         = InpLedger;
      cfg.ledgerFile            = "cf_market_auction_theory_ledger.csv";
      cfg.logLevel              = InpLogLevel;
      cfg.sessionStartHour = InpOpenHour;  cfg.sessionStartMin = InpOpenMin;
      int endMin = InpOpenMin + InpWindowMinutes;
      int endHour = InpOpenHour + endMin / 60;
      endMin = endMin % 60;
      if(InpExtendedWindow) { endHour = InpExtendedEndHour; endMin = 0; }
      cfg.sessionEndHour   = endHour;  cfg.sessionEndMin = endMin;
      cfg.noTradeAfterHour = endHour;  cfg.noTradeAfterMin = endMin;
      cfg.partial1AtR      = 1.0;   // scale out on the way to the doc's 2:1 objective
      cfg.partial1Pct      = 50;
      cfg.breakEvenAtR     = 0.0;   // the document stops at the setup candle and targets 2:1
      cfg.trailAtR         = 0.0;
      EA_ApplyStagePolicy(cfg, InpStage);
   }

   void OnInitStrategy()
   {
      EA_Log(EA_LOG_EVENTS, StringFormat(
             "market auction theory armed: daily bias (body >= %.2f, 45-degree slope >= %.2f ATR/%d days) + 5m alignment, zone = first %d min congestion, first-hour window from %02d:%02d London, target %.1fR",
             InpBiasBodyMin, InpSlopeAtr, InpSlopeDays, InpFormationMin,
             InpOpenHour, InpOpenMin, InpTargetR), true);
   }

   //-------------------------------------------------------------------
   // Bias -> alignment -> zone -> breakout -> retest rejection
   //-------------------------------------------------------------------
   bool BuildPlan(SEAContext &ctx, SSignalPlan &plan)
   {
      plan.Reset();
      if(!ctx.inSession || ctx.atr <= 0.0) return false;

      int bias = 0;
      if(!DailyBias(ctx, bias)) return false;
      if(!Aligned(ctx, bias)) return false;                 // "skip the trade" when the timeframes disagree

      //--- the auction zone: the post-open congestion (engine range helper over the formation window)
      double zoneHi = 0.0, zoneLo = 0.0;
      if(!AuctionZone(ctx, zoneHi, zoneLo)) return false;
      if((zoneHi - zoneLo) > InpZoneMaxAtr * ctx.atr) return false;   // "messy structure" - stay out

      //--- price must have left the zone in the trend direction first
      if(!LeftZone(ctx, bias, zoneHi, zoneLo)) return false;

      //--- ... and must now return and reject it
      MqlRates m[];
      if(EA_Rates(ctx.symbol, g_eaIndTf, 0, InpConfirmBars + 4, m) < InpConfirmBars + 3) return false;
      int    rejectBar = -1;
      for(int i = 1; i <= InpConfirmBars; i++)
      {
         bool entered = (bias < 0) ? (m[i].high >= zoneLo) : (m[i].low <= zoneHi);
         bool heldOut = (bias < 0) ? (m[i].close < zoneLo) : (m[i].close > zoneHi);
         bool candle  = (bias < 0) ? (m[i].close < m[i].open) : (m[i].close > m[i].open);
         if(entered && heldOut && candle) { rejectBar = i; break; }
      }
      if(rejectBar < 0) return false;                       // "if price does not retest the auction zone ... skip"

      double tickSize = SymbolInfoDouble(ctx.symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickSize <= 0.0) tickSize = ctx.point;
      double buffer = InpStopBufferTicks * tickSize;
      double entry  = (bias > 0) ? ctx.ask : ctx.bid;
      double stop   = (bias > 0) ? m[rejectBar].low  - buffer : m[rejectBar].high + buffer;
      double risk   = (bias > 0) ? (entry - stop) : (stop - entry);
      if(risk <= 0.0) return false;
      double target = (bias > 0) ? (entry + InpTargetR * risk) : (entry - InpTargetR * risk);

      plan.dir     = bias;
      plan.entry   = entry;
      plan.stop    = stop;
      plan.target  = target;
      plan.riskDist = risk;
      plan.barsAgo  = rejectBar;
      plan.score    = 76.0;
      plan.isLimit  = false;
      plan.reason   = StringFormat("auction zone %.2f-%.2f: %s rejection candle at %.2f, stop beyond its %s, %.1fR target, %s bias + 5m alignment",
                                   zoneLo, zoneHi, (bias > 0) ? "bullish" : "bearish", m[rejectBar].close,
                                   (bias > 0) ? "low" : "high", InpTargetR, (bias > 0) ? "long" : "short");
      return true;
   }

private:
   //-------------------------------------------------------------------
   // (1) the daily bias: a strong prior candle, a clear 45-degree trend
   //-------------------------------------------------------------------
   bool DailyBias(SEAContext &ctx, int &bias)
   {
      bias = 0;
      MqlRates d[];
      int got = EA_Rates(ctx.symbol, PERIOD_D1, 0, InpSlopeDays + 8, d);
      if(got < InpSlopeDays + 6 || ctx.atrD1 <= 0.0) return false;

      double bodyMin = InpBiasBodyMin;
      double range = d[1].high - d[1].low;
      if(range <= 0.0) return false;
      double body = MathAbs(d[1].close - d[1].open) / range;
      if(body < bodyMin) return false;                      // the prior day must have closed "strongly"
      bias = (d[1].close < d[1].open) ? -1 : +1;

      //--- the 45-degree trend: the same direction, and travel >= InpSlopeAtr daily ATRs
      double travel = d[1].close - d[1 + InpSlopeDays].close;
      if(bias < 0 && travel >= 0.0) return false;
      if(bias > 0 && travel <= 0.0) return false;
      if(MathAbs(travel) < InpSlopeAtr * ctx.atrD1) return false;

      //--- price on the correct side of the daily moving averages (21/50, computed locally - the
      //--- engine carries only the daily 200; same EMA definition as the engine's helpers)
      double ema21 = EmaClose(d, 21, 1);
      double ema50 = EmaClose(d, 50, 1);
      if(ema21 <= 0.0 || ema50 <= 0.0) return false;
      if(bias > 0 && !(d[1].close > ema21 && d[1].close > ema50)) return false;
      if(bias < 0 && !(d[1].close < ema21 && d[1].close < ema50)) return false;

      //--- the open/gap context (the breakdown's gap down agreed with the short bias)
      if(InpRequireGap && d[0].open > 0.0 && d[1].close > 0.0)
      {
         double priorClose = d[1].close;      // d[0] is today's forming day, d[1] the completed one
         if(bias > 0 && d[0].open < priorClose) return false;   // a gap down against a long bias
         if(bias < 0 && d[0].open > priorClose) return false;   // a gap up against a short bias
      }
      return true;
   }

   //--- EMA of closes ending at series bar `endBar` (inclusive), over `period` bars
   double EmaClose(const MqlRates &d[], const int period, const int endBar)
   {
      int got = ArraySize(d);
      if(got < endBar + period) return 0.0;
      double k = 2.0 / (period + 1.0);
      double ema = d[endBar + period - 1].close;              // seed with the oldest close of the window
      for(int i = endBar + period - 2; i >= endBar; i--)
         ema = d[i].close * k + ema * (1.0 - k);
      return ema;
   }

   //-------------------------------------------------------------------
   // (2) the 5-minute chart must mirror the daily trend
   //-------------------------------------------------------------------
   bool Aligned(const SEAContext &ctx, const int bias)
   {
      if(ctx.ema20 <= 0.0 || ctx.ema50 <= 0.0) return false;
      MqlRates m[];
      if(EA_Rates(ctx.symbol, g_eaIndTf, 0, 3, m) < 2) return false;
      double px = m[1].close;
      if(bias > 0) return (px > ctx.ema20 && px > ctx.ema50 && ctx.ema20 > ctx.ema50);
      return (px < ctx.ema20 && px < ctx.ema50 && ctx.ema20 < ctx.ema50);
   }

   //-------------------------------------------------------------------
   // (3) the auction zone: the post-open congestion the doc's example uses
   //-------------------------------------------------------------------
   bool AuctionZone(const SEAContext &ctx, double &zoneHi, double &zoneLo)
   {
      zoneHi = 0.0; zoneLo = 0.0;
      int    bars = 0;
      double hi = 0.0, lo = 0.0;
      int fromMin = InpOpenHour * 60 + InpOpenMin;
      int toMin   = fromMin + InpFormationMin;
      if(!SigRangeForDay(ctx.symbol, g_eaIndTf, fromMin, toMin, 0, hi, lo, bars)) return false;
      if(bars < MathMax(2, InpFormationMin / 5)) return false;   // the congestion must have formed
      if(hi <= lo) return false;
      zoneHi = hi; zoneLo = lo;
      return true;
   }

   //--- "SPY broke down from this zone shortly after it formed, confirming trend continuation"
   bool LeftZone(const SEAContext &ctx, const int bias, const double zoneHi, const double zoneLo)
   {
      MqlRates m[];
      int got = EA_Rates(ctx.symbol, g_eaIndTf, 0, 240, m);
      if(got < 6) return false;

      //--- only today's bars count: the zone formed at today's open, so a close beyond it on a
      //--- previous session says nothing about today's continuation
      MqlDateTime cdt;
      if(!TimeToStruct(EA_ClockNow(), cdt)) return false;
      cdt.hour = 0; cdt.min = 0; cdt.sec = 0;
      datetime clockOpen = StructToTime(cdt) + (datetime)((InpOpenHour * 60 + InpOpenMin) * 60);
      datetime sessionServer = EA_ClockToServer(clockOpen);

      for(int i = 1; i < got; i++)
      {
         if(m[i].time < sessionServer) break;
         if(bias > 0 && m[i].close > zoneHi) return true;
         if(bias < 0 && m[i].close < zoneLo) return true;
      }
      return false;
   }
};

CCfMarketAuctionTheory g_cfMarketAuctionTheory;

//+------------------------------------------------------------------+
//| MQL5 event handlers                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   return EA_Init(&g_cfMarketAuctionTheory);
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
