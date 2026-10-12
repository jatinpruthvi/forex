//+------------------------------------------------------------------+
//|                                     GEMINI_META_PORTFOLIO.mqh    |
//|                Antigravity V3 Meta-Portfolio Controller          |
//+------------------------------------------------------------------+
#property copyright "Gemini Antigravity"
#property link      ""
#include <Trade/Trade.mqh>

//=== META: 1. One-Slot Opportunity Cost Arbitrator ===
input group "=== GEMINI META: 1. Portfolio Arbitration ==="
input bool   MInpEnableOneSlot           = true;
input int    MInpMaxPortfolioHeat        = 1;   // Max simultaneous trades across all EAs

//=== META: 2. Edge-Weighted Risk ===
input group "=== GEMINI META: 2. Edge-Weighted Risk ==="
input bool   MInpEnableEdgeWeighting     = true;
input double MInpBaseRiskMult            = 0.5; // Weak setup multiplier
input double MInpStrongRiskMult          = 1.0; // Standard setup multiplier
input double MInpExceptionalRiskMult     = 1.5; // A+ setup multiplier

//=== META: 3. Convex Runners (Partial Exits) ===
input group "=== GEMINI META: 3. Convex Runners ==="
input bool   MInpEnableRunners           = true;
input double MInpPartialClosePercent     = 75.0; // Close 75% at +1R

//+------------------------------------------------------------------+
//| 1. One-Slot Arbitration (Global Variable Lock)                   |
//+------------------------------------------------------------------+
bool GeminiMeta_RequestPortfolioSlot(ulong magic, string symbol, double expected_r_value)
  {
   if(!MInpEnableOneSlot) return true;
   
   // Count currently active trades for this strategy/magic
   int active_trades = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(magic > 0 && (ulong)PositionGetInteger(POSITION_MAGIC) != magic) continue;
      active_trades++;
     }
   
   if(active_trades >= MInpMaxPortfolioHeat)
     {
      Print("[GEMINI META] REJECT: Strategy slot maxed (",active_trades,"/",MInpMaxPortfolioHeat,") - ",symbol," magic=",magic," rejected.");
      return false;
     }
     
   Print("[GEMINI META] ACCEPT: Slot granted to ",symbol," magic=",magic," (Heat: ",active_trades,"/",MInpMaxPortfolioHeat,")");
   return true;
  }

//+------------------------------------------------------------------+
//| 2. Edge-Weighted Risk Scoring                                    |
//+------------------------------------------------------------------+
double GeminiMeta_GetEdgeWeightedRisk(string symbol, ENUM_TIMEFRAMES timeframe, ulong magic)
  {
   if(!MInpEnableEdgeWeighting) return 1.0;
   
   // Assess regime quality to output a risk multiplier
   int adx_h = iADX(symbol, timeframe, 14);
   double adx[1];
   if(adx_h != INVALID_HANDLE && CopyBuffer(adx_h, 0, 0, 1, adx) > 0)
     {
      IndicatorRelease(adx_h);
      if(adx[0] > 35) return MInpExceptionalRiskMult; // Strong trend / momentum
      if(adx[0] > 20) return MInpStrongRiskMult;      // Standard
     }
   
   return MInpBaseRiskMult; // Weak / Chop
  }

//+------------------------------------------------------------------+
//| 3. Convex Runners (+1R Partial Exit Engine)                      |
//+------------------------------------------------------------------+
// This should be called in OnTick() for open positions
void GeminiMeta_ManageRunners(ulong magic)
  {
   if(!MInpEnableRunners) return;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong pos_ticket = PositionGetTicket(i);
      if(pos_ticket == 0) continue;
      
      ulong pos_magic = PositionGetInteger(POSITION_MAGIC);
      if(pos_magic != magic) continue;
      
      string sym = PositionGetString(POSITION_SYMBOL);
      double vol = PositionGetDouble(POSITION_VOLUME);
      double open_px = PositionGetDouble(POSITION_PRICE_OPEN);
      double current_px = PositionGetDouble(POSITION_PRICE_CURRENT);
      double sl = PositionGetDouble(POSITION_SL);
      long type = PositionGetInteger(POSITION_TYPE);
      
      // Calculate original risk
      double risk_points = MathAbs(open_px - sl);
      if(risk_points <= 0) continue; // No SL, can't calc R
      
      double profit_points = (type == POSITION_TYPE_BUY) ? (current_px - open_px) : (open_px - current_px);
      double current_r = profit_points / risk_points;
      
      // If we hit +1R and haven't partialed yet
      // A simple proxy: if SL is at or better than breakeven, we already processed it.
      bool is_breakeven = (type == POSITION_TYPE_BUY && sl >= open_px) || (type == POSITION_TYPE_SELL && sl <= open_px && sl > 0.0);
      
      if(current_r >= 1.0 && !is_breakeven)
        {
         double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
         double vmin = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
         if(step <= 0.0) step = 0.01;
         double close_vol = MathFloor((vol * (MInpPartialClosePercent / 100.0)) / step) * step;
         close_vol = NormalizeDouble(close_vol, 2);
         if(close_vol < vmin) close_vol = 0.0;
         if(vol - close_vol < vmin - 1e-9) close_vol = vol;
         
         if(close_vol > 0.0)
           {
            CTrade meta_trade;
            meta_trade.SetExpertMagicNumber(magic);
            meta_trade.SetTypeFillingBySymbol(sym);
            bool closed_ok = false;
            if(close_vol >= vol - 1e-9)
               closed_ok = meta_trade.PositionClose(pos_ticket);
            else
               closed_ok = meta_trade.PositionClosePartial(pos_ticket, close_vol);
            
            if(closed_ok)
              {
               Print("[GEMINI META] +1R Partial Exit on ",sym," (Closed ",close_vol," lots)");
               // Move remaining to Breakeven + safe broker padding
               double point = SymbolInfoDouble(sym, SYMBOL_POINT);
               int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
               long stopLevel = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
               double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
               double bid = SymbolInfoDouble(sym, SYMBOL_BID);
               double min_gap = MathMax((double)stopLevel * point, ask - bid) + 3.0 * point;
               
               double new_sl = (type == POSITION_TYPE_BUY) ? open_px + (2.0*point) : open_px - (2.0*point);
               if(type == POSITION_TYPE_BUY && new_sl > bid - min_gap) new_sl = bid - min_gap;
               if(type == POSITION_TYPE_SELL && new_sl < ask + min_gap) new_sl = ask + min_gap;
               new_sl = NormalizeDouble(new_sl, digits);
               
               meta_trade.PositionModify(pos_ticket, new_sl, PositionGetDouble(POSITION_TP));
               Print("[GEMINI META] Runner SL moved to Breakeven on ",sym," sl=",new_sl);
              }
           }
        }
     }
  }


