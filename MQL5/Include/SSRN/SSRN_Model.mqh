//+------------------------------------------------------------------+
//|                                                   SSRN_Model.mqh  |
//|  Multinomial logistic regression loaded from a CSV you train.    |
//|                                                                  |
//|  The G10 ML paper (SSRN 3693753) publishes no weights, so there |
//|  is nothing to embed. Run ssrn-ml/train_model.py on your own     |
//|  broker's exported OHLC, drop the resulting file in              |
//|  MQL5\Files\, and this loader picks it up.                       |
//|                                                                  |
//|  IT REFUSES TO RUN IF THE FILE IS ABSENT OR ITS FEATURE ORDER    |
//|  DOES NOT MATCH SSRN_Features.mqh EXACTLY. That is deliberate:   |
//|  silently scoring against a scrambled feature vector would look  |
//|  like a working strategy while trading nonsense.                 |
//|                                                                  |
//|  FILE FORMAT (plain text, one directive per line):               |
//|    SSRN_ML_MODEL_V1                                              |
//|    feature=<name>          <- exactly SSRN_FEAT_COUNT lines,     |
//|    ...                    <- in the canonical order              |
//|    bias=<b0>,<b1>,<b2>                                          |
//|    w=<w0>,<w1>,<w2>          <- one line per feature             |
//|                                                                  |
//|  CLASS INDEX SEMANTICS: 0 = short, 1 = flat, 2 = long.           |
//+------------------------------------------------------------------+
#property copyright "SSRN ports - derived from SSRN working papers"
#ifndef SSRN_MODEL_MQH
#define SSRN_MODEL_MQH

#include <Files\File.mqh>
#include "SSRN_Features.mqh"

#define SSRN_MODEL_MAGIC "SSRN_ML_MODEL_V1"
#define SSRN_CLASS_SHORT 0
#define SSRN_CLASS_FLAT  1
#define SSRN_CLASS_LONG  2

class SSRN_LogitModel
  {
private:
   double            m_bias[3];
   double            m_w[SSRN_FEAT_COUNT][3];
   string            m_names[SSRN_FEAT_COUNT];
   bool              m_loaded;
   string            m_reason;

public:
                     SSRN_LogitModel(void) : m_loaded(false), m_reason("not loaded")
     {
      for(int c = 0; c < 3; c++) m_bias[c] = 0.0;
      for(int i = 0; i < SSRN_FEAT_COUNT; i++)
         for(int c = 0; c < 3; c++) m_w[i][c] = 0.0;
     }

   bool              IsLoaded(void) const { return m_loaded; }
   string            Reason(void)   const { return m_reason; }

   //+--------------------------------------------------------------+
   //| Load and validate. path is relative to MQL5\Files\.          |
   //+--------------------------------------------------------------+
   bool Load(const string filename)
     {
      m_loaded = false;
      m_reason = "not loaded";

      if(filename == "")
        { m_reason = "no model file configured"; return false; }

      //--- The strategy tester agents run in their own sandbox and WIPE
      //--- their MQL5\Files at startup, so a file placed there is never
      //--- visible to a backtest. The common Files folder is shared by the
      //--- terminal and by every tester agent, so try that as a fallback.
      int fh = FileOpen(filename, FILE_READ | FILE_TXT | FILE_ANSI);
      if(fh == INVALID_HANDLE)
         fh = FileOpen(filename, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
      if(fh == INVALID_HANDLE)
         {
          m_reason = "cannot open MQL5\\Files\\" + filename
                     + " (nor the common Files folder) - train a model first";
          return false;
         }

      string expected[SSRN_FEAT_COUNT];
      SSRN_FeatureNames(expected);

      string seenNames[SSRN_FEAT_COUNT];
      int    nNames = 0;
      bool   haveMagic = false;
      bool   haveBias  = false;
      int    nW = 0;

      while(!FileIsEnding(fh))
        {
         string line = FileReadString(fh);
         StringTrimLeft(line); StringTrimRight(line);
         if(line == "" || StringGetCharacter(line, 0) == '#') continue;

         //--- The banner is a bare token with no '=' on it, so it has to be
         //--- matched BEFORE the key=value split - otherwise StringSplit
         //--- returns 1, the np<2 guard below discards the line, and every
         //--- valid model file is rejected as "missing banner".
         if(line == SSRN_MODEL_MAGIC) { haveMagic = true; continue; }

         string parts[];
         int np = StringSplit(line, StringGetCharacter("=", 0), parts);
         if(np < 2) continue;

         string key = parts[0];
         StringTrimLeft(key); StringTrimRight(key);

         //--- rejoin the value in case a name itself contained '='
         string val = "";
         for(int i = 1; i < np; i++)
            val += (i > 1 ? "=" : "") + parts[i];
         StringTrimLeft(val); StringTrimRight(val);

         if(key == "feature")
           {
            if(nNames < SSRN_FEAT_COUNT) seenNames[nNames] = val;
            nNames++;
            continue;
           }

         if(key == "bias")
           {
            string b[];
            if(StringSplit(val, StringGetCharacter(",", 0), b) == 3)
              {
               for(int c = 0; c < 3; c++) m_bias[c] = StringToDouble(b[c]);
               haveBias = true;
              }
            continue;
           }

         if(key == "w")
           {
            if(nW < SSRN_FEAT_COUNT)
              {
               string v[];
               if(StringSplit(val, StringGetCharacter(",", 0), v) == 3)
                  for(int c = 0; c < 3; c++) m_w[nW][c] = StringToDouble(v[c]);
               else
                 { FileClose(fh); m_reason = "line " + IntegerToString(nW) + " of w= has the wrong field count"; return false; }
              }
            nW++;
            continue;
           }
        }
      FileClose(fh);

      if(!haveMagic)
        { m_reason = "missing banner " + SSRN_MODEL_MAGIC + " - not an SSRN model file"; return false; }
      if(nNames != SSRN_FEAT_COUNT)
        { m_reason = "expected " + IntegerToString(SSRN_FEAT_COUNT) + " feature lines, found " + IntegerToString(nNames); return false; }
      if(!haveBias)
        { m_reason = "missing bias= line"; return false; }
      if(nW != SSRN_FEAT_COUNT)
        { m_reason = "expected " + IntegerToString(SSRN_FEAT_COUNT) + " w= lines, found " + IntegerToString(nW); return false; }

      //--- order is the contract; a reordered vector must be rejected
      for(int i = 0; i < SSRN_FEAT_COUNT; i++)
        {
         if(seenNames[i] != expected[i])
           {
            m_reason = "feature " + IntegerToString(i) + " is '" + seenNames[i]
                       + "' but the EA expects '" + expected[i] + "' - regenerate the model";
            return false;
           }
         m_names[i] = seenNames[i];
        }

      m_loaded = true;
      m_reason = "loaded " + filename;
      return true;
     }

   //+--------------------------------------------------------------+
   //| Softmax over the three logits.                                |
   //+--------------------------------------------------------------+
   void Probabilities(const double &feat[], double &prob[])
     {
      ArrayResize(prob, 3);
      double logits[3];
      for(int c = 0; c < 3; c++)
        {
         double v = m_bias[c];
         for(int i = 0; i < SSRN_FEAT_COUNT; i++) v += feat[i] * m_w[i][c];
         logits[c] = v;
        }
      double mx = MathMax(logits[0], MathMax(logits[1], logits[2]));
      double ex[3]; double sum = 0.0;
      for(int c = 0; c < 3; c++) { ex[c] = MathExp(logits[c] - mx); sum += ex[c]; }
      if(sum <= 0.0) { prob[0] = 0.0; prob[1] = 1.0; prob[2] = 0.0; return; }
      for(int c = 0; c < 3; c++) prob[c] = ex[c] / sum;
     }

   //+--------------------------------------------------------------+
   //| Predicted class and its confidence. Returns -1 when unloaded.|
   //+--------------------------------------------------------------+
   int Predict(const double &feat[], double &confidence)
     {
      confidence = 0.0;
      if(!m_loaded) return -1;
      double p[];
      Probabilities(feat, p);
      int best = 0;
      if(p[1] > p[best]) best = 1;
      if(p[2] > p[best]) best = 2;
      confidence = p[best];
      return best;
     }
  };

#endif // SSRN_MODEL_MQH
