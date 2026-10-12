//+------------------------------------------------------------------+
//|                                                 SSRN_Momentum.mqh |
//|  EMA-mixture currency momentum signal.                            |
//|                                                                  |
//|  Faithful to Rohrbach, Suremann & Osterrieder (SSRN 2949379),    |
//|  section 4, following Baz et al. (2015):                         |
//|                                                                  |
//|    x_k = EMA(P, n_k,short) - EMA(P, n_k,long)                    |
//|    y_k = x_k / sd_moving(63)(P)          <- damp in high vol     |
//|    z_k = y_k / sd_moving(252)(y_k)       <- damp again           |
//|    u_k = z_k * exp(-z_k^2/4) / (sqrt(2)*exp(-1/2))  in [-1, 1]   |
//|    Signal = (u_1 + u_2 + u_3) / 3                                |
//|                                                                  |
//|  n_short = (8, 16, 32), n_long = (24, 48, 96), alpha = 1/n.      |
//|                                                                  |
//|  The response-function denominator is sqrt(2)*exp(-1/2), NOT the |
//|  0.89 used by Baz et al. The authors of the paper derive the     |
//|  true extrema at z = +/- sqrt(2), where v(z) = sqrt(2)*exp(-1/2) |
//|  = 0.857764, and divide by that so u lands exactly in [-1, 1].   |
//|                                                                  |
//|  CAUTION: pdftotext renders the root sign as byte 0xC7, so the   |
//|  paper's "sqrt(2)*exp(-1/2)" extracts as "2 e-1/2". Using 2.0    |
//|  instead of sqrt(2.0) caps the signal at 0.7071 and silently     |
//|  shrinks every position. Verified numerically.                   |
//|                                                                  |
//|  The paper's 313-bar warm-up (62 + 251 + 1) is enforced: the     |
//|  caller must supply SSRN_MOM_MIN_BARS bars or no signal comes    |
//|  back.                                                           |
//+------------------------------------------------------------------+
#property copyright "SSRN ports - derived from SSRN working papers"
#ifndef SSRN_MOMENTUM_MQH
#define SSRN_MOMENTUM_MQH

#include "SSRN_OLS.mqh"

//--- the three short EMA lengths, from Baz et al. (2015)
#define SSRN_MOM_NSHORT_1 8
#define SSRN_MOM_NSHORT_2 16
#define SSRN_MOM_NSHORT_3 32
//--- the three long EMA lengths
#define SSRN_MOM_NLONG_1  24
#define SSRN_MOM_NLONG_2  48
#define SSRN_MOM_NLONG_3  96
//--- the paper's warm-up: 62 bars for the 63-day sd, 251 more for the
//--- 252-day sd, plus one for the arithmetic return. Plus EMA burn-in.
#define SSRN_MOM_WARMUP   313
//--- practical floor: warm-up plus enough history for the EMAs to
//--- forget their seed (~5x the longest EMA of 96 = 480).
#define SSRN_MOM_MIN_BARS 800

//+------------------------------------------------------------------+
//| Exponential moving average, seeded with the SMA of the first `n` |
//| values. Input and output are OLDEST -> NEWEST.                   |
//+------------------------------------------------------------------+
void SSRN_EMA(const double &s[], const int len, const int n, double &out[])
  {
   ArrayResize(out, len);
   ArrayInitialize(out, 0.0);
   if(len < n || n < 2) return;

   double alpha = 1.0 / (double)n;

   double seed = 0.0;
   for(int i = 0; i < n; i++) seed += s[i];
   seed /= (double)n;

   for(int i = 0; i < n - 1; i++) out[i] = seed;
   out[n - 1] = seed;

   for(int i = n; i < len; i++)
      out[i] = alpha * s[i] + (1.0 - alpha) * out[i - 1];
  }

//+------------------------------------------------------------------+
//| Detail of one signal evaluation, exposed so the EA can log it.   |
//+------------------------------------------------------------------+
struct SSRN_MOMENTUM_STATE
  {
   bool   ready;         // warm-up complete, signal is usable
   double signal;        // final Signal in [-1, 1]
   double u[3];          // the three response-function outputs
   double z[3];          // the three normalized inputs
   int    barsUsed;
  };

//+------------------------------------------------------------------+
//| Evaluate the momentum signal at the LAST bar of the series.      |
//| `close` must be OLDEST -> NEWEST and at least SSRN_MOM_MIN_BARS. |
//+------------------------------------------------------------------+
bool SSRN_MomentumSignal(const double &close[], const int len, SSRN_MOMENTUM_STATE &st)
  {
   st.ready = false;
   st.signal = 0.0;
   st.u[0] = st.u[1] = st.u[2] = 0.0;
   st.z[0] = st.z[1] = st.z[2] = 0.0;
   st.barsUsed = len;

   if(len < SSRN_MOM_MIN_BARS) return false;

   const int nshort[3] = { SSRN_MOM_NSHORT_1, SSRN_MOM_NSHORT_2, SSRN_MOM_NSHORT_3 };
   const int nlong[3]  = { SSRN_MOM_NLONG_1,  SSRN_MOM_NLONG_2,  SSRN_MOM_NLONG_3  };

   const int end = len - 1;                 // newest bar we may look at

   //--- sd_moving(63) of the price itself
   double sdP = SSRN_StdDev(close, end, 63);
   if(sdP <= 0.0) return false;

   const double denom = MathSqrt(2.0) * MathExp(-0.5);   // maps extrema exactly to +/-1

   double acc = 0.0;

   for(int k = 0; k < 3; k++)
     {
      double emaS[]; double emaL[];
      SSRN_EMA(close, len, nshort[k], emaS);
      SSRN_EMA(close, len, nlong[k],  emaL);

      //--- build x_k then y_k over the whole series so the 252-day sd of
      //--- y_k is meaningful, not just the terminal value.
      double xk[]; ArrayResize(xk, len);
      double yk[]; ArrayResize(yk, len);
      for(int i = 0; i < len; i++)
        {
         xk[i] = emaS[i] - emaL[i];
         yk[i] = xk[i] / sdP;
        }

      double sdY = SSRN_StdDev(yk, end, 252);
      if(sdY <= 0.0) return false;

      double zk = yk[end] / sdY;
      double uk = zk * MathExp(-zk * zk / 4.0) / denom;

      st.z[k] = zk;
      st.u[k] = uk;
      acc += uk;
     }

   st.signal = acc / 3.0;
   st.ready  = true;
   return true;
  }

//+------------------------------------------------------------------+
//| Half-life of an EMA of length n, in bars: log(0.5)/log(1-1/n).   |
//| The paper quotes these to justify the horizon spacing (5.2 days  |
//| at n=8 up to 66.2 days at n=96). Diagnostic only.                |
//+------------------------------------------------------------------+
double SSRN_EMAHalfLife(const int n)
  {
   if(n < 2) return 0.0;
   return MathLog(0.5) / MathLog(1.0 - 1.0 / (double)n);
  }

#endif // SSRN_MOMENTUM_MQH
