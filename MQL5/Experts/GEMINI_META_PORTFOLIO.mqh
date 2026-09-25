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
   
   // Count currently active trades across the entire MT5 terminal
   int active_trades = PositionsTotal();
   
   if(active_trades >= MInpMaxPortfolioHeat)
     {
      // If we are full, we evaluate Opportunity Cost.
      // E.g., if a 5-star TRIAD setup appears but a 1-star GOLD setup is running, 
      // advanced logic would close GOLD and take TRIAD. For now, strict lock:
      Print("[GEMINI META] REJECT: Portfolio heat maxed (",active_trades,"/",MInpMaxPortfolioHeat,") - ",symbol," rejected.");
      return false;
     }
     
   Print("[GEMINI META] ACCEPT: Slot granted to ",symbol," (Heat: ",active_trades,"/",MInpMaxPortfolioHeat,")");
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
      // We use a custom comment or magic tag, or check if volume is < original
      // A simple proxy: if SL is at or better than breakeven, we already processed it.
      bool is_breakeven = (type == POSITION_TYPE_BUY && sl >= open_px) || (type == POSITION_TYPE_SELL && sl <= open_px);
      
      if(current_r >= 1.0 && !is_breakeven)
        {
         double close_vol = NormalizeDouble(vol * (MInpPartialClosePercent / 100.0), 2);
         if(close_vol > 0.0)
           {
            CTrade meta_trade;
            meta_trade.SetExpertMagicNumber(magic);
            if(meta_trade.PositionClosePartial(pos_ticket, close_vol))
              {
               Print("[GEMINI META] +1R Partial Exit on ",sym," (Closed ",close_vol," lots)");
               // Move remaining to Breakeven + small padding
               double point = SymbolInfoDouble(sym, SYMBOL_POINT);
               double new_sl = (type == POSITION_TYPE_BUY) ? open_px + (2*point) : open_px - (2*point);
               meta_trade.PositionModify(pos_ticket, new_sl, PositionGetDouble(POSITION_TP));
               Print("[GEMINI META] Runner SL moved to Breakeven on ",sym);
              }
           }
        }
     }
  }


