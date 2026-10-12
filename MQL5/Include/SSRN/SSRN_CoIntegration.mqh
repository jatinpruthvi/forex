//+------------------------------------------------------------------+
//|                                             SSRN_CoIntegration.mqh |
//|  Engle-Granger cointegration gate + spread z-score.               |
//|                                                                  |
//|  Faithful to Lemishko, Landi & Caicedo-Llano (SSRN 4771108),     |
//|  sections 3.3 and 3.4:                                           |
//|                                                                  |
//|   * BOTH OLS orientations are tested and the one with the clearer |
//|     (more negative) residual ADF statistic wins, provided it     |
//|     passes at the chosen significance. This matters: the EG       |
//|     residual depends on which series is the regressand.           |
//|   * The spread actually traded is s = log(P1) - log(P2) with the  |
//|     legs in ALPHABETICAL ticker order, i.e. a unit hedge. The     |
//|     paper's equation (3) fixes beta at 1 and uses the EG test as  |
//|     a GATE only; the intercept cancels in the z-score.            |
//|   * z = (s - mu_train) / sigma_train over the training window.    |
//|                                                                  |
//|  Series are OLDEST -> NEWEST (index 0 = oldest).                  |
//+------------------------------------------------------------------+
#property copyright "SSRN ports - derived from SSRN working papers"
#ifndef SSRN_COINTEGRATION_MQH
#define SSRN_COINTEGRATION_MQH

#include "SSRN_OLS.mqh"

//--- MacKinnon response-surface critical values for an ADF with a
//--- constant, no trend, n ~ 257. Not N(0,1) values.
#define SSRN_ADF_CRIT_1PCT (-3.4534)
#define SSRN_ADF_CRIT_5PCT (-2.8715)
#define SSRN_ADF_CRIT_10PCT (-2.5721)

//+------------------------------------------------------------------+
//| Result of one cointegration screen.                              |
//+------------------------------------------------------------------+
struct SSRN_COINT_RESULT
  {
   bool   pass;         // accepted at the chosen significance
   double bestT;        // more-negative of the two residual t-stats
   double betaY;        // coefficient on the regressor, best orientation
   double tA;           // t-stat, orientation A (logA on logB)
   double tB;           // t-stat, orientation B (logB on logA)
   double nObs;         // effective ADF rows in the winning orientation
  };

//+------------------------------------------------------------------+
//| Engle-Granger screen over the LAST `trainLen` bars of two log     |
//| price series (both aligned, oldest -> newest).                   |
//+------------------------------------------------------------------+
void SSRN_EngleGranger(const double &logA[], const double &logB[],
                       const int seriesLen, const int trainLen,
                       const int plags, const double crit,
                       SSRN_COINT_RESULT &res)
  {
   res.pass   = false;
   res.bestT  = 0.0;
   res.betaY  = 0.0;
   res.tA     = 0.0;
   res.tB     = 0.0;
   res.nObs   = 0.0;

   int n = MathMin(trainLen, seriesLen);
   if(n < 60) return;                       // too little to test anything

   int from = seriesLen - n;                // window start (oldest side)

   double winA[]; ArrayResize(winA, n);
   double winB[]; ArrayResize(winB, n);
   for(int i = 0; i < n; i++) { winA[i] = logA[from + i]; winB[i] = logB[from + i]; }

   //--- orientation A: logA regressed on logB  ->  e = logA - a - b*logB
   double tA = 0.0, bA = 0.0, nA = 0.0;
   if(SSRN_EG_ResidT(winA, winB, n, plags, tA, bA, nA))
     {
      res.tA = tA;
      if(tA < res.bestT) { res.bestT = tA; res.betaY = bA; res.nObs = nA; res.pass = (tA < crit); }
     }

   //--- orientation B: logB regressed on logA
   double tB = 0.0, bB = 0.0, nB = 0.0;
   if(SSRN_EG_ResidT(winB, winA, n, plags, tB, bB, nB))
     {
      res.tB = tB;
      if(tB < res.bestT) { res.bestT = tB; res.betaY = bB; res.nObs = nB; res.pass = (tB < crit); }
     }
  }

//+------------------------------------------------------------------+
//| One Engle-Granger step: OLS y on x, then ADF on the residual.     |
//+------------------------------------------------------------------+
bool SSRN_EG_ResidT(const double &y[], const double &x[], const int n,
                    const int plags, double &tstat, double &betaX, double &adfN)
  {
   tstat = 0.0; betaX = 0.0; adfN = 0.0;
   if(n < 60) return false;

   double Xr[]; ArrayResize(Xr, n * 2);
   for(int i = 0; i < n; i++) { Xr[i * 2 + 0] = 1.0; Xr[i * 2 + 1] = x[i]; }

   double beta[]; double resid[]; double se[];
   if(!SSRN_OLSFit(Xr, y, n, 2, beta, resid, se)) return false;
   betaX = beta[1];

   double ts = 0.0, bu = 0.0, adfN2 = 0.0;
   if(!SSRN_ADF(resid, n, plags, ts, bu, adfN2)) return false;
   tstat = ts;
   adfN  = adfN2;
   return true;
  }

//+------------------------------------------------------------------+
//| Spread z-score for the CURRENT bar, using training-window moments |
//| taken from the `trainLen` bars that end one bar before it.       |
//|                                                                  |
//| s = log(P1) - log(P2)  (alphabetical, unit hedge)                |
//| z = (s_now - mu_train) / sigma_train                             |
//+------------------------------------------------------------------+
bool SSRN_SpreadZ(const double &logA[], const double &logB[],
                  const int seriesLen, const int trainLen,
                  double &z, double &mu, double &sd, double &sNow)
  {
   z = 0.0; mu = 0.0; sd = 0.0; sNow = 0.0;
   int n = MathMin(trainLen, seriesLen - 1);   // reserve the current bar
   if(n < 30) return false;

   int cur   = seriesLen - 1;                  // current bar (newest)
   int tEnd  = cur - 1;                        // last training bar
   int tFrom = tEnd - n + 1;
   if(tFrom < 1) return false;

   double s[]; ArrayResize(s, n);
   for(int i = 0; i < n; i++)
     {
      int idx = tFrom + i;
      s[i] = logA[idx] - logB[idx];
     }

   mu = SSRN_Mean(s, 0, n - 1);
   sd = SSRN_StdDev(s, n - 1, n);
   if(sd <= 0.0) return false;

   sNow = logA[cur] - logB[cur];
   z    = (sNow - mu) / sd;
   return true;
  }

//--- SSRN_CopyClose and SSRN_BarsAligned now live in SSRN_OLS.mqh so the
//--- momentum EA shares one copy rather than redefining them.

#endif // SSRN_COINTEGRATION_MQH
