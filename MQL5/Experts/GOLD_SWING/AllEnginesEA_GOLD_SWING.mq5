//+------------------------------------------------------------------+
//|                                    AllEnginesEA_GOLD_SWING.mq5   |
//|                 Daily Donchian N=55 Swing Portfolio - All Engines |
//|  Runs all 4 versions (V1, V2, V3, V4) concurrently on ONE chart   |
//+------------------------------------------------------------------+
#property copyright "Jatin"
#property link      ""
#property version   "1.00"
#property description "GOLD_SWING Master - runs V1, V2, V3, V4 on ONE chart with isolated Magic Numbers."

#include "../GEMINI_ROI_MODULE.mqh"
#include "../GEMINI_ALPHA_MODULE.mqh"
#include "../GEMINI_META_PORTFOLIO.mqh"
#include "../GEMINI_V4_QUANT.mqh"

// --- Inputs ---
input group "=== GOLD_SWING VERSION SWITCHES (RUN ALL OR ANY ON 1 CHART) ==="
input bool   InpRun_V1 = true; // [55551] GOLD_SWING_V1 (Donchian N=55 + Chandelier ATR)
input bool   InpRun_V2 = true; // [55552] GOLD_SWING_V2 (+ Volatility Squeeze Filter)
input bool   InpRun_V3 = true; // [55553] GOLD_SWING_V3 (+ 1-Slot Arbitration & Convex Runners)
input bool   InpRun_V4 = true; // [55554] GOLD_SWING_V4 (+ Macro Guard, Equity Curve & FVG)

#define MAGIC_GOLD_V1 55551
#define MAGIC_GOLD_V2 55552
#define MAGIC_GOLD_V3 55553
#define MAGIC_GOLD_V4 55554

input group "=== Strategy Parameters ==="
input string InpGoldSymbol       = "XAUUSD"; // Target Instrument (independent of chart symbol)
input int    InpDonchianPeriod   = 55;      // 55-Day Donchian Breakout
input double InpChandelierAtrMult = 2.5;     // 2.5x ATR Trailing Stop
input int    InpAtrPeriod        = 14;      // ATR calculation period
input double InpRiskPercent      = 1.0;     // 1.0% fixed risk per trade

int handle_atr;
CTrade trade;

//+------------------------------------------------------------------+
//| Check if position already open on symbol for this magic           |
//+------------------------------------------------------------------+
bool PositionOpenOnMagic(const string sym, const long magic)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      const ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == magic && PositionGetString(POSITION_SYMBOL) == sym)
          return true;
     }
    return false;
  }

//+------------------------------------------------------------------+
//| Normalise lot size to broker constraints                         |
//+------------------------------------------------------------------+
double NormaliseLots(const string sym, const double lots)
  {
   const double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   const double vmin = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   const double vmax = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   if(step <= 0.0) return (vmin > 0.0) ? vmin : 0.01;

   double clean = MathFloor(lots / step) * step;
   int digits_lot = (step == 0.1) ? 1 : 2;
   clean = NormalizeDouble(clean, digits_lot);
   if(clean < vmin) clean = vmin;
   if(clean > vmax) clean = vmax;
   return clean;
  }

string g_gold_symbol = "";

//+------------------------------------------------------------------+
//| Resolve Gold symbol name against broker aliases                  |
//+------------------------------------------------------------------+
string ResolveGoldSymbol(const string requested)
  {
   if(SymbolSelect(requested, true)) return requested;
   string aliases[] = {"XAUUSD", "GOLD", "XAUUSD.pro", "XAUUSD.raw", "XAUUSDm", "XAUUSD.cash", "GOLD.pro", "GOLD.m"};
   for(int i = 0; i < ArraySize(aliases); i++)
     {
      if(SymbolSelect(aliases[i], true)) return aliases[i];
     }
   return requested;
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   GeminiROIInit();

   g_gold_symbol = ResolveGoldSymbol(InpGoldSymbol);
   SymbolSelect(g_gold_symbol, true);

   handle_atr = iATR(g_gold_symbol, PERIOD_D1, InpAtrPeriod);
   if(handle_atr == INVALID_HANDLE)
     {
      PrintFormat("[ERROR] Failed to create ATR indicator handle for %s", g_gold_symbol);
      return(INIT_FAILED);
     }

   PrintFormat("[INIT] GOLD_SWING using symbol '%s'", g_gold_symbol);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(handle_atr != INVALID_HANDLE)
      IndicatorRelease(handle_atr);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(InpRun_V1) GeminiROITick(MAGIC_GOLD_V1);
   if(InpRun_V2) GeminiROITick(MAGIC_GOLD_V2);
   if(InpRun_V3) { GeminiROITick(MAGIC_GOLD_V3); GeminiMeta_ManageRunners(MAGIC_GOLD_V3); }
   if(InpRun_V4) { GeminiROITick(MAGIC_GOLD_V4); GeminiMeta_ManageRunners(MAGIC_GOLD_V4); }

   // Wait for a new Daily bar close on Gold
   static datetime last_bar = 0;
   datetime current_bar = iTime(g_gold_symbol, PERIOD_D1, 0);
   if(current_bar <= 0) return;
   if(last_bar == 0)
     {
      last_bar = current_bar;
      return;
     }
   if(current_bar == last_bar) return;
   last_bar = current_bar;

   // 1. Read ATR for Chandelier Exit
   double atr_val[1];
   if(CopyBuffer(handle_atr, 0, 1, 1, atr_val) < 1) return;

   // 2. Read Donchian Channel of preceding completed bars (bars 2..56)
   int highest_idx = iHighest(g_gold_symbol, PERIOD_D1, MODE_HIGH, InpDonchianPeriod, 2);
   int lowest_idx  = iLowest(g_gold_symbol, PERIOD_D1, MODE_LOW, InpDonchianPeriod, 2);
   if(highest_idx < 0 || lowest_idx < 0) return;

   double hh = iHigh(g_gold_symbol, PERIOD_D1, highest_idx);
   double ll = iLow(g_gold_symbol, PERIOD_D1, lowest_idx);

   MqlTick tick;
   if(!SymbolInfoTick(g_gold_symbol, tick)) return;
   double ask = tick.ask;
   double bid = tick.bid;

   double close_px = iClose(g_gold_symbol, PERIOD_D1, 1);

   bool is_long_breakout  = (close_px > hh);
   bool is_short_breakout = (close_px < ll);

   if(!is_long_breakout && !is_short_breakout) return;

   ENUM_ORDER_TYPE type = is_long_breakout ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double sl = 0;
   if(is_long_breakout)  sl = bid - (atr_val[0] * InpChandelierAtrMult);
   if(is_short_breakout) sl = ask + (atr_val[0] * InpChandelierAtrMult);

   double risk_money = AccountInfoDouble(ACCOUNT_EQUITY) * (InpRiskPercent / 100.0);
   double sl_dist    = atr_val[0] * InpChandelierAtrMult;
   double tick_val   = SymbolInfoDouble(g_gold_symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tick_val <= 0.0) tick_val = SymbolInfoDouble(g_gold_symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size  = SymbolInfoDouble(g_gold_symbol, SYMBOL_TRADE_TICK_SIZE);
   double base_lots  = 0.01;
   if(sl_dist > 0.0 && tick_size > 0.0 && tick_val > 0.0 && risk_money > 0.0)
     {
      double loss_per_lot = (sl_dist / tick_size) * tick_val;
      if(loss_per_lot > 0.0)
         base_lots = risk_money / loss_per_lot;
     }

   // Multi-Version Dispatch (V1..V4)
   long magics[4] = {MAGIC_GOLD_V1, MAGIC_GOLD_V2, MAGIC_GOLD_V3, MAGIC_GOLD_V4};
   bool runs[4]   = {InpRun_V1, InpRun_V2, InpRun_V3, InpRun_V4};

   for(int v = 1; v <= 4; v++)
     {
      if(!runs[v - 1]) continue;
      long magic = magics[v - 1];

      if(PositionOpenOnMagic(g_gold_symbol, magic)) continue;

      // Version-specific gates
      if(v >= 2)
        {
         if(!GeminiAlpha_VolatilitySqueeze(g_gold_symbol)) continue;
        }

      if(!GeminiEntryGate(g_gold_symbol, type, magic)) continue;

      if(v >= 3)
        {
         if(!GeminiMeta_RequestPortfolioSlot(magic, g_gold_symbol, 1.0)) continue;
        }

      if(v == 4)
        {
         if(!GeminiV4_MacroGuard(g_gold_symbol, type)) continue;
        }

      // Sizing
      double volume = base_lots;
      if(v >= 3)
        {
         volume *= GeminiMeta_GetEdgeWeightedRisk(g_gold_symbol, PERIOD_D1, magic);
        }
      if(v == 4)
        {
         volume *= GeminiV4_EquityCurveSizing(magic) * GeminiV4_FVG_Score(g_gold_symbol, type);
        }

      trade.SetExpertMagicNumber(magic);
      trade.SetDeviationInPoints(20);
      trade.SetTypeFillingBySymbol(g_gold_symbol);

      int digits = (int)SymbolInfoInteger(g_gold_symbol, SYMBOL_DIGITS);
      double point = SymbolInfoDouble(g_gold_symbol, SYMBOL_POINT);
      long stopLevel = SymbolInfoInteger(g_gold_symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double min_gap = MathMax((double)stopLevel * point, ask - bid) + 3.0 * point;

      double norm_sl = sl;
      if(norm_sl > 0.0)
      {
         if(is_long_breakout && norm_sl > bid - min_gap) norm_sl = bid - min_gap;
         if(!is_long_breakout && norm_sl < ask + min_gap) norm_sl = ask + min_gap;
         norm_sl = NormalizeDouble(norm_sl, digits);
      }
      double norm_vol = NormaliseLots(g_gold_symbol, volume);

      // Pre-trade Margin Validation
      double margin_req = 0.0;
      if(OrderCalcMargin(type, g_gold_symbol, norm_vol, (type == ORDER_TYPE_BUY ? ask : bid), margin_req))
        {
         double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
         if(margin_req > free_margin * 0.90)
           {
            PrintFormat("[WARN] GOLD_SWING V%d margin required %.2f exceeds free margin %.2f - skip", v, margin_req, free_margin);
            continue;
           }
        }

      string comment  = StringFormat("GOLD_V%d", v);
      bool ok = false;
      if(is_long_breakout)
         ok = trade.Buy(norm_vol, g_gold_symbol, 0.0, norm_sl, 0.0, comment);
      else
         ok = trade.Sell(norm_vol, g_gold_symbol, 0.0, norm_sl, 0.0, comment);

      if(!ok)
        {
         PrintFormat("[ERROR] GOLD_SWING V%d order failed retcode=%u (%s)", v, trade.ResultRetcode(), trade.ResultRetcodeDescription());
        }
      else
        {
         PrintFormat("[FILLED] GOLD_SWING V%d %.2f lots on %s (magic=%d)", v, norm_vol, g_gold_symbol, magic);
        }
     }
  }
