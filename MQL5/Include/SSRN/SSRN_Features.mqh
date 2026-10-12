//+------------------------------------------------------------------+
//|                                                SSRN_Features.mqh |
//|  The feature vector of Agrawal, "Short-Term Trading Strategy on  |
//|  G10 Currencies" (SSRN 3693753), section 3.2.2.4-3.2.2.5.        |
//|                                                                  |
//|  NOTE ON FIDELITY. The paper lists its indicators and periods but |
//|  never publishes its trained weights, its fractional-differencing |
//|  parameter d, or the rule that turns a class label into a        |
//|  position. This header therefore implements the FEATURE ENGINEERING |
//|  faithfully and leaves the model to SSRN_Model.mqh, which loads  |
//|  weights you train yourself. Nothing here reproduces the paper's |
//|  reported 27% / Sharpe 1.60 - that number cannot be reproduced   |
//|  from what the paper publishes.                                  |
//|                                                                  |
//|  Two documented departures, because the paper is silent:         |
//|   * autocorrelation is computed on log returns over a 100-bar    |
//|     window (the paper gives neither window nor series choice);   |
//|   * the "*_side" features are signed normalised measures rather  |
//|     than the paper's unspecified transforms.                     |
//|                                                                  |
//|  Feature ORDER here is the contract with ssrn-ml/train_model.py. |
//|  Changing it invalidates every saved model.                      |
//+------------------------------------------------------------------+
#property copyright "SSRN ports - derived from SSRN working papers"
#ifndef SSRN_FEATURES_MQH
#define SSRN_FEATURES_MQH

#define SSRN_FEAT_COUNT 55
#define SSRN_FEAT_AC_WINDOW 100      // autocorrelation lookback (bars)
#define SSRN_FEAT_MIN_BARS  130      // need senkou_b52 + chikou26 + slack

//+------------------------------------------------------------------+
//| Canonical feature names, in the exact order of the weight vector.|
//+------------------------------------------------------------------+
void SSRN_FeatureNames(string &names[])
  {
   ArrayResize(names, SSRN_FEAT_COUNT);
   names[0]  = "ema_fast3";
   names[1]  = "ema_slow7";
   names[2]  = "ema_side";
   names[3]  = "bb_mid20";
   names[4]  = "bb_upper";
   names[5]  = "bb_lower";
   names[6]  = "bb_sd";
   names[7]  = "bb_side";
   names[8]  = "cci14";
   names[9]  = "stoch_k14";
   names[10] = "stoch_d14";
   names[11] = "stoch_side";
   names[12] = "willr14";
   names[13] = "willr_side";
   names[14] = "ichimoku_tenkan9";
   names[15] = "ichimoku_kijun26";
   names[16] = "ichimoku_senkou_a";
   names[17] = "ichimoku_senkou_b52";
   names[18] = "ichimoku_chikou";
   names[19] = "ichimoku_side";
   names[20] = "rsi14";
   names[21] = "rsi_side";
   names[22] = "close_t1";
   names[23] = "close_t2";
   names[24] = "close_t12";
   names[25] = "autocorr_lag1";
   names[26] = "autocorr_lag2";
   names[27] = "autocorr_lag4";
   names[28] = "autocorr_lag6";
   names[29] = "ret1_lag1";
   names[30] = "ret1_lag2";
   names[31] = "ret1_lag12";
   names[32] = "ret_period_lag1";
   names[33] = "ret_period_lag2";
   names[34] = "ret_period_lag12";
   names[35] = "ir_differential";
   names[36] = "dow_mon";
   names[37] = "dow_tue";
   names[38] = "dow_wed";
   names[39] = "dow_thu";
   names[40] = "dow_fri";
   names[41] = "dow_sun";
   names[42] = "month_jan";   names[43] = "month_feb";   names[44] = "month_mar";
   names[45] = "month_apr";   names[46] = "month_may";   names[47] = "month_jun";
   names[48] = "month_jul";   names[49] = "month_aug";   names[50] = "month_sep";
   names[51] = "month_oct";   names[52] = "month_nov";   names[53] = "month_dec";
   names[54] = "eom";
  }

//+------------------------------------------------------------------+
//| Small rolling primitives. All arrays OLDEST -> NEWEST.           |
//+------------------------------------------------------------------+
double SSRN_F_SMA(const double &s[], const int end, const int n)
  {
   if(end < n - 1) return 0.0;
   double sum = 0.0;
   for(int i = end - n + 1; i <= end; i++) sum += s[i];
   return sum / (double)n;
  }

double SSRN_F_Highest(const double &s[], const int end, const int n)
  {
   if(end < n - 1) return 0.0;
   double hi = s[end - n + 1];
   for(int i = end - n + 2; i <= end; i++) if(s[i] > hi) hi = s[i];
   return hi;
  }

double SSRN_F_Lowest(const double &s[], const int end, const int n)
  {
   if(end < n - 1) return 0.0;
   double lo = s[end - n + 1];
   for(int i = end - n + 2; i <= end; i++) if(s[i] < lo) lo = s[i];
   return lo;
  }

double SSRN_F_EMA(const double &s[], const int end, const int n)
  {
   if(end < n - 1) return 0.0;
   double alpha = 1.0 / (double)n;
   double seed = 0.0;
   for(int i = end - n + 1; i <= end; i++) seed += s[i];
   double e = seed / (double)n;
   for(int i = end - n + 2; i <= end; i++)
      e = alpha * s[i] + (1.0 - alpha) * e;
   return e;
  }

double SSRN_F_RSI(const double &c[], const int end, const int n)
  {
   if(end < n) return 50.0;
   double up = 0.0, dn = 0.0;
   int from = end - n + 1;
   for(int i = from; i <= end; i++)
     {
      double ch = c[i] - c[i - 1];
      if(ch > 0) up += ch; else dn -= ch;
     }
   if(dn <= 0.0) return 100.0;
   double rs = (up / (double)n) / (dn / (double)n);
   return 100.0 - 100.0 / (1.0 + rs);
  }

//--- mean absolute deviation, for CCI
double SSRN_F_MeanDev(const double &s[], const int end, const int n)
  {
   if(end < n - 1) return 0.0;
   double m = SSRN_F_SMA(s, end, n);
   double acc = 0.0;
   for(int i = end - n + 1; i <= end; i++) acc += MathAbs(s[i] - m);
   return acc / (double)n;
  }

//+------------------------------------------------------------------+
//| Pearson correlation of log returns against themselves lagged L.  |
//+------------------------------------------------------------------+
double SSRN_F_AutoCorr(const double &c[], const int end, const int lag, const int window)
  {
   if(lag < 1) return 0.0;
   if(end < window + lag) return 0.0;

   double r1[]; double r2[];
   ArrayResize(r1, window); ArrayResize(r2, window);
   int base = end - window - lag + 1;
   for(int i = 0; i < window; i++)
     {
      int a = base + i;              // return at t
      int b = a - lag;               // return at t-lag
      if(b < 1) return 0.0;
      r1[i] = MathLog(c[a] / c[a - 1]);
      r2[i] = MathLog(c[b] / c[b - 1]);
     }
   double m1 = 0.0, m2 = 0.0;
   for(int i = 0; i < window; i++) { m1 += r1[i]; m2 += r2[i]; }
   m1 /= (double)window; m2 /= (double)window;

   double cov = 0.0, v1 = 0.0, v2 = 0.0;
   for(int i = 0; i < window; i++)
     {
      double d1 = r1[i] - m1, d2 = r2[i] - m2;
      cov += d1 * d2; v1 += d1 * d1; v2 += d2 * d2;
     }
   if(v1 <= 0.0 || v2 <= 0.0) return 0.0;
   return cov / MathSqrt(v1 * v2);
  }

//+------------------------------------------------------------------+
//| Build the full feature vector for bar `end`.                     |
//| Arrays must be OLDEST -> NEWEST and longer by SSRN_FEAT_MIN_BARS.|
//| `irDiff` is the interest-rate differential from your rates CSV;  |
//| pass 0.0 when you have none (the feature is then inert).         |
//| `serverTime` supplies day-of-week and month.                     |
//+------------------------------------------------------------------+
bool SSRN_BuildFeatures(const double &o[], const double &h[], const double &l[], const double &c[],
                        const int len, const int end, const double irDiff,
                        const datetime serverTime, double &feat[])
  {
   ArrayResize(feat, SSRN_FEAT_COUNT);
   for(int i = 0; i < SSRN_FEAT_COUNT; i++) feat[i] = 0.0;

   if(end < SSRN_FEAT_MIN_BARS || end >= len) return false;

   double close = c[end];

   //--- EMA + Bollinger
   double ema3  = SSRN_F_EMA(c, end, 3);
   double ema7  = SSRN_F_EMA(c, end, 7);
   feat[0] = ema3;
   feat[1] = ema7;
   feat[2] = (ema3 > ema7) ? 1.0 : ((ema3 < ema7) ? -1.0 : 0.0);

   double mid20 = SSRN_F_SMA(c, end, 20);
   double sd20  = 0.0;
   if(end >= 19)
     {
      double acc = 0.0;
      for(int i = end - 19; i <= end; i++) { double d = c[i] - mid20; acc += d * d; }
      sd20 = MathSqrt(acc / 19.0);            // sample sd
     }
   feat[3] = mid20;
   feat[4] = mid20 + 2.0 * sd20;
   feat[5] = mid20 - 2.0 * sd20;
   feat[6] = sd20;
   feat[7] = (sd20 > 0.0) ? (close - mid20) / sd20 : 0.0;

   //--- CCI(14), the paper's modification: close replaces typical price
   double sma14 = SSRN_F_SMA(c, end, 14);
   double md14  = SSRN_F_MeanDev(c, end, 14);
   feat[8] = (md14 > 0.0) ? (close - sma14) / (0.015 * md14) : 0.0;

   //--- Stochastic(14)
   double hi14 = SSRN_F_Highest(h, end, 14);
   double lo14 = SSRN_F_Lowest(l, end, 14);
   double k = (hi14 > lo14) ? 100.0 * (close - lo14) / (hi14 - lo14) : 50.0;
   feat[9]  = k;
   double kPrev = 0.0, kPrev2 = 0.0;
   if(end - 1 >= 14 && end - 2 >= 14)
     {
      double hp1 = SSRN_F_Highest(h, end - 1, 14), lp1 = SSRN_F_Lowest(l, end - 1, 14);
      double hp2 = SSRN_F_Highest(h, end - 2, 14), lp2 = SSRN_F_Lowest(l, end - 2, 14);
      kPrev  = (hp1 > lp1) ? 100.0 * (c[end - 1] - lp1) / (hp1 - lp1) : 50.0;
      kPrev2 = (hp2 > lp2) ? 100.0 * (c[end - 2] - lp2) / (hp2 - lp2) : 50.0;
     }
   double d = (k + kPrev + kPrev2) / 3.0;
   feat[10] = d;
   feat[11] = k - d;

   //--- Williams %R(14)
   double wr = (hi14 > lo14) ? -100.0 * (hi14 - close) / (hi14 - lo14) : -50.0;
   feat[12] = wr;
   feat[13] = (wr + 50.0) / 50.0;            // signed, roughly [-1, 1]

   //--- Ichimoku, standard 9/26/52
   double tenkan = (SSRN_F_Highest(h, end, 9)  + SSRN_F_Lowest(l, end, 9))  / 2.0;
   double kijun  = (SSRN_F_Highest(h, end, 26) + SSRN_F_Lowest(l, end, 26)) / 2.0;
   double senka  = (SSRN_F_Highest(h, end, 52) + SSRN_F_Lowest(l, end, 52)) / 2.0;
   double sena   = (tenkan + kijun) / 2.0;
   double chikou = c[end - 26];
   feat[14] = tenkan;
   feat[15] = kijun;
   feat[16] = sena;
   feat[17] = senka;
   feat[18] = chikou;
   feat[19] = (close > sena) ? 1.0 : ((close < sena) ? -1.0 : 0.0);

   //--- RSI(14)
   double rsi = SSRN_F_RSI(c, end, 14);
   feat[20] = rsi;
   feat[21] = (rsi - 50.0) / 50.0;

   //--- lagged prices and returns
   feat[22] = c[end - 1];
   feat[23] = c[end - 2];
   feat[24] = c[end - 12];

   //--- autocorrelation of log returns
   feat[25] = SSRN_F_AutoCorr(c, end, 1, SSRN_FEAT_AC_WINDOW);
   feat[26] = SSRN_F_AutoCorr(c, end, 2, SSRN_FEAT_AC_WINDOW);
   feat[27] = SSRN_F_AutoCorr(c, end, 4, SSRN_FEAT_AC_WINDOW);
   feat[28] = SSRN_F_AutoCorr(c, end, 6, SSRN_FEAT_AC_WINDOW);

   //--- lagged one-period returns
   feat[29] = (c[end - 1] > 0.0) ? c[end] / c[end - 1] - 1.0 : 0.0;
   feat[30] = (c[end - 2] > 0.0) ? c[end - 1] / c[end - 2] - 1.0 : 0.0;
   feat[31] = (c[end - 12] > 0.0) ? c[end - 11] / c[end - 12] - 1.0 : 0.0;

   //--- lagged multi-period returns
   feat[32] = (c[end - 2] > 0.0) ? c[end - 1] / c[end - 2] - 1.0 : 0.0;
   feat[33] = (c[end - 3] > 0.0) ? c[end - 1] / c[end - 3] - 1.0 : 0.0;
   feat[34] = (c[end - 13] > 0.0) ? c[end - 1] / c[end - 13] - 1.0 : 0.0;

   //--- the one fundamental feature of the paper
   feat[35] = irDiff;

   //--- calendar dummies
   MqlDateTime dt;
   TimeToStruct(serverTime, dt);
   int dow = dt.day_of_week;                   // 0=Sunday ... 6=Saturday
   feat[36] = (dow == 1) ? 1.0 : 0.0;
   feat[37] = (dow == 2) ? 1.0 : 0.0;
   feat[38] = (dow == 3) ? 1.0 : 0.0;
   feat[39] = (dow == 4) ? 1.0 : 0.0;
   feat[40] = (dow == 5) ? 1.0 : 0.0;
   feat[41] = (dow == 0) ? 1.0 : 0.0;

   int mo = dt.mon;                              // 1..12
   for(int m = 1; m <= 12; m++) feat[41 + m] = (mo == m) ? 1.0 : 0.0;

   //--- end of month: last bar of the calendar month
   datetime nextDay = serverTime + 86400;
   MqlDateTime nd; TimeToStruct(nextDay, nd);
   feat[54] = (nd.mon != mo) ? 1.0 : 0.0;

   for(int i = 0; i < SSRN_FEAT_COUNT; i++)
      if(!MathIsValidNumber(feat[i])) feat[i] = 0.0;

   return true;
  }

#endif // SSRN_FEATURES_MQH
