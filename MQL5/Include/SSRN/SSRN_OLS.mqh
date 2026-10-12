//+------------------------------------------------------------------+
//|                                                   SSRN_OLS.mqh    |
//|  Ordinary least squares + Augmented Dickey-Fuller, hand-rolled.  |
//|                                                                  |
//|  MQL5 ships neither. These are the two statistical primitives the |
//|  SSRN cointegration port needs (Lemishko/Landi/Caicedo-Llano,     |
//|  SSRN 4771108, section 3.3).                                     |
//|                                                                  |
//|  All series are passed OLDEST -> NEWEST (index 0 = oldest).       |
//|                                                                  |
//|  The numerics are terminal-free; the two series-copy helpers at  |
//|  the bottom are the only part that touches MT5, and both live    |
//|  here so the cointegration and momentum EAs share one copy.      |
//+------------------------------------------------------------------+
#property copyright "SSRN ports - derived from SSRN working papers"
#ifndef SSRN_OLS_MQH
#define SSRN_OLS_MQH

//+------------------------------------------------------------------+
//| Solve A x = b by Gaussian elimination with partial pivoting.     |
//| A is n*n row-major and is DESTROYED. x receives the solution.    |
//+------------------------------------------------------------------+
bool SSRN_Solve(double &A[], double &b[], double &x[], const int n)
  {
   if(n <= 0 || ArraySize(A) < n * n || ArraySize(b) < n) return false;
   ArrayResize(x, n);
   for(int i = 0; i < n; i++) x[i] = b[i];

   for(int col = 0; col < n; col++)
     {
      //--- pivot on the largest magnitude below (and including) col
      int piv = col;
      double best = MathAbs(A[col * n + col]);
      for(int r = col + 1; r < n; r++)
        {
         double v = MathAbs(A[r * n + col]);
         if(v > best) { best = v; piv = r; }
        }
      if(best < 1.0e-12) return false;   // singular

      if(piv != col)
        {
         for(int c = 0; c < n; c++)
           {
            double t = A[col * n + c];
            A[col * n + c] = A[piv * n + c];
            A[piv * n + c] = t;
           }
         double tv = x[col]; x[col] = x[piv]; x[piv] = tv;
        }

      double d = A[col * n + col];
      for(int r = col + 1; r < n; r++)
        {
         double f = A[r * n + col] / d;
         if(f == 0.0) continue;
         for(int c = col; c < n; c++) A[r * n + c] -= f * A[col * n + c];
         x[r] -= f * x[col];
        }
     }

   for(int i = n - 1; i >= 0; i--)
     {
      double s = x[i];
      for(int c = i + 1; c < n; c++) s -= A[i * n + c] * x[c];
      if(MathAbs(A[i * n + i]) < 1.0e-12) return false;
      x[i] = s / A[i * n + i];
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Invert a small matrix by Gauss-Jordan with partial pivoting.     |
//| A is n*n row-major and is DESTROYED; inv[] receives the inverse. |
//+------------------------------------------------------------------+
bool SSRN_Inverse(const double &Ain[], double &inv[], const int n)
  {
   if(n <= 0 || ArraySize(Ain) < n * n) return false;
   double A[]; ArrayResize(A, n * n);
   for(int i = 0; i < n * n; i++) A[i] = Ain[i];

   ArrayResize(inv, n * n);
   ArrayInitialize(inv, 0.0);
   for(int i = 0; i < n; i++) inv[i * n + i] = 1.0;

   for(int col = 0; col < n; col++)
     {
      int piv = col;
      double best = MathAbs(A[col * n + col]);
      for(int r = col + 1; r < n; r++)
        {
         double v = MathAbs(A[r * n + col]);
         if(v > best) { best = v; piv = r; }
        }
      if(best < 1.0e-12) return false;

      if(piv != col)
        {
         for(int c = 0; c < n; c++)
           {
            double t = A[col * n + c]; A[col * n + c] = A[piv * n + c]; A[piv * n + c] = t;
            double u = inv[col * n + c]; inv[col * n + c] = inv[piv * n + c]; inv[piv * n + c] = u;
           }
        }

      double d = A[col * n + col];
      for(int c = 0; c < n; c++) { A[col * n + c] /= d; inv[col * n + c] /= d; }

      for(int r = 0; r < n; r++)
        {
         if(r == col) continue;
         double f = A[r * n + col];
         if(f == 0.0) continue;
         for(int c = 0; c < n; c++)
           {
            A[r * n + c] -= f * A[col * n + c];
            inv[r * n + c] -= f * inv[col * n + c];
           }
        }
     }
   return true;
  }

//+------------------------------------------------------------------+
//| OLS fit of y on k regressors.                                    |
//| Xr is n*k row-major, row i already holds its regressor vector    |
//| (the constant must be included as column 0 if you want one).     |
//| beta is length k; resid is length n.                             |
//| Returns false if the system is singular or n <= k.               |
//+------------------------------------------------------------------+
bool SSRN_OLSFit(const double &Xr[], const double &y[],
                 const int n, const int k,
                 double &beta[], double &resid[], double &stderr[])
  {
   if(k <= 1 || n <= k) return false;
   if(ArraySize(Xr) < n * k || ArraySize(y) < n) return false;

   double XtX[]; ArrayResize(XtX, k * k); ArrayInitialize(XtX, 0.0);
   double Xty[]; ArrayResize(Xty, k);     ArrayInitialize(Xty, 0.0);

   for(int i = 0; i < n; i++)
     {
      for(int a = 0; a < k; a++)
        {
         double xa = Xr[i * k + a];
         Xty[a] += xa * y[i];
         for(int b2 = a; b2 < k; b2++) XtX[a * k + b2] += xa * Xr[i * k + b2];
        }
     }
   //--- mirror the upper triangle built above
   for(int a = 0; a < k; a++)
      for(int b2 = 0; b2 < a; b2++)
         XtX[a * k + b2] = XtX[b2 * k + a];

   double A[]; ArrayResize(A, k * k);
   for(int i = 0; i < k * k; i++) A[i] = XtX[i];

   if(!SSRN_Solve(A, Xty, beta, k)) return false;

   //--- residuals and sigma^2
   ArrayResize(resid, n);
   double ssr = 0.0;
   for(int i = 0; i < n; i++)
     {
      double f = 0.0;
      for(int a = 0; a < k; a++) f += Xr[i * k + a] * beta[a];
      resid[i] = y[i] - f;
      ssr += resid[i] * resid[i];
     }

   ArrayResize(stderr, k);
   ArrayInitialize(stderr, 0.0);
   double sigma2 = ssr / (double)(n - k);
   double invk[]; ArrayResize(invk, k * k);
   if(SSRN_Inverse(XtX, invk, k))
      for(int a = 0; a < k; a++)
         stderr[a] = MathSqrt(sigma2 * invk[a * k + a]);

   return true;
  }

//+------------------------------------------------------------------+
//| Augmented Dickey-Fuller with a constant, no trend.               |
//| Regresses dy(t) on [1, y(t-1), dy(t-1) ... dy(t-p)] and returns  |
//| the t-statistic on the coefficient of y(t-1).                    |
//|                                                                  |
//| Reject the unit root (i.e. conclude the series is stationary)    |
//| when tstat < critical. These are NOT the usual N(0,1) critical   |
//| values - use the MacKinnon values, roughly -3.45 / -2.87 / -2.57 |
//| at 1% / 5% / 10% for n around 257.                               |
//+------------------------------------------------------------------+
bool SSRN_ADF(const double &s[], const int n, const int plags,
              double &tstat, double &betaUnit, double &adfN)
  {
   tstat = 0.0; betaUnit = 0.0; adfN = 0.0;
   int p = plags;
   if(p < 0) p = 0;
   if(p > 5) p = 5;                      // guard against absurd input

   int k = 2 + p;                        // const + y(t-1) + p lagged diffs
   int first = 1 + p;                    // index of the first usable level
   int rows = n - first;
   if(rows <= k) return false;           // not enough data

   double Xr[]; ArrayResize(Xr, rows * k);
   double yv[]; ArrayResize(yv, rows);

   for(int r = 0; r < rows; r++)
     {
      int t = first + r;                 // index of the level being differenced
      Xr[r * k + 0] = 1.0;
      Xr[r * k + 1] = s[t - 1];          // y(t-1)
      for(int j = 0; j < p; j++)
         Xr[r * k + 2 + j] = s[t - 1 - j] - s[t - 2 - j];   // dy(t-j)
      yv[r] = s[t] - s[t - 1];           // dy(t)
     }

   double beta[]; double resid[]; double se[];
   if(!SSRN_OLSFit(Xr, yv, rows, k, beta, resid, se)) return false;
   if(se[1] <= 0.0) return false;

   betaUnit = beta[1];
   tstat    = beta[1] / se[1];
   adfN     = (double)rows;
   return true;
  }

//+------------------------------------------------------------------+
//| Rolling standard deviation over `len` bars of series[], ending   |
//| at index `end` (inclusive). Returns 0 when there is not enough.  |
//| Series is OLDEST -> NEWEST.                                      |
//+------------------------------------------------------------------+
double SSRN_StdDev(const double &s[], const int end, const int len)
  {
   if(len < 2) return 0.0;
   if(end < len - 1) return 0.0;
   int from = end - len + 1;
   double sum = 0.0;
   for(int i = from; i <= end; i++) sum += s[i];
   double mean = sum / (double)len;
   double acc = 0.0;
   for(int i = from; i <= end; i++) { double d = s[i] - mean; acc += d * d; }
   double v = acc / (double)(len - 1);   // sample variance (n-1)
   if(v <= 0.0) return 0.0;
   return MathSqrt(v);
  }

//+------------------------------------------------------------------+
//| Mean of s[from..end] inclusive.                                  |
//+------------------------------------------------------------------+
double SSRN_Mean(const double &s[], const int from, const int end)
  {
   if(end < from) return 0.0;
   double sum = 0.0;
   int c = 0;
   for(int i = from; i <= end; i++) { sum += s[i]; c++; }
   if(c == 0) return 0.0;
   return sum / (double)c;
  }

//+------------------------------------------------------------------+
//| Copy close prices for a symbol, OLDEST -> NEWEST, returning the  |
//| number of bars actually copied.                                  |
//+------------------------------------------------------------------+
int SSRN_CopyClose(const string sym, const ENUM_TIMEFRAMES tf,
                   const int count, double &out[])
  {
   ArraySetAsSeries(out, false);              // we want oldest first
   ArrayResize(out, 0);
   int got = CopyClose(sym, tf, 0, count, out);
   if(got <= 0) { ArrayResize(out, 0); return 0; }
   return got;
  }

//+------------------------------------------------------------------+
//| Verify two symbols produced the same bar times over `count` bars. |
//| Majors on the same timeframe line up, but a missing bar on one   |
//| side would silently shift every spread - worth one check.        |
//+------------------------------------------------------------------+
bool SSRN_BarsAligned(const string symA, const string symB,
                      const ENUM_TIMEFRAMES tf, const int count)
  {
   for(int i = 0; i < 4; i++)
     {
      int shift = 1 + i;                       // a few sampled offsets
      if(shift >= count) break;
      datetime ta = iTime(symA, tf, shift);
      datetime tb = iTime(symB, tf, shift);
      if(ta == 0 || tb == 0) return false;
      if(ta != tb) return false;
     }
   return true;
  }

#endif // SSRN_OLS_MQH
