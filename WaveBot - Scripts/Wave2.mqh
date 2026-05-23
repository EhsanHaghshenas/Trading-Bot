// ============================================================================
#ifndef WAVEBOT_WAVE2_MQH
#define WAVEBOT_WAVE2_MQH

// بدنهٔ مؤثر C1 (Open[i]..Open[i+1]) از Bodies.mqh
inline bool InsideEffBodyC1_Up(const MqlRates &r, const double c1LowEff, const double c1HighEff)
{
   return (r.high <= c1HighEff && r.low >= c1LowEff);
}

// موج۲ نزولی (برای روند صعودی) + «اسکیپ همهٔ داخل‌ها»
// نکتهٔ کلیدی: barrierLow = کوچک‌ترین Low دیده‌شده از آخرین قدم تاییدشده.
// هر کندلی (سبز/قرمز) می‌تواند barrierLow را کاهش دهد؛ پذیرش قدمِ قرمز فقط وقتی مجاز است
// که Low آن از barrierLow پایین‌تر برود (بنابراین هر کندلِ داخلِ کندلِ بزرگ‌تر اسکیپ می‌شود).
bool CheckWave2_FromIndex_LocalOnly(const MqlRates &rates[],
                                    const bool &insideClusterHL[],
                                    const double &bodyLowEff[], const double &bodyHighEff[],
                                    const int n, const int i1,
                                    int &i2, int &i3, int &i4)
{
   i2=i3=i4=-1;
   if(i1<0 || i1>=n-1) return false;

   const double H1 = rates[i1].high;
   const double L1 = rates[i1].low;
   const bool   c1Bear = (rates[i1].close < rates[i1].open);
   const int    need   = (c1Bear ? 2 : 3);   // قانون پروژه: C1 قرمز ⇒ ۲ قدم، C1 سبز ⇒ ۳ قدم

   const double C1_LowEff  = bodyLowEff[i1];
   const double C1_HighEff = bodyHighEff[i1];

   int    found     = 0;
   double barrierLow= L1; // کف پویا از آخرین قدم تاییدشده یا C1

   for(int j=i1+1; j<n && (j-i1)<=InpMaxBarsInWave; ++j)
   {
      // اسکیپ خوشهٔ inside سراسری + به‌روزرسانی barrier
      if(insideClusterHL[j]) { if(rates[j].low < barrierLow) barrierLow = rates[j].low; continue; }

      // ابطال: نباید H1 شکسته شود
      if(rates[j].high > H1) return false;

      // داخل بدنهٔ مؤثر C1 ⇒ اسکیپ (و به‌روزرسانی barrier)
      if(InsideEffBodyC1_Up(rates[j], C1_LowEff, C1_HighEff))
      { if(rates[j].low < barrierLow) barrierLow = rates[j].low; continue; }

      // بعد از C1 فقط قرمزها شمارش می‌شوند؛ اما کندل سبز می‌تواند barrier را کاهش دهد
      if(rates[j].close >= rates[j].open)
      { if(rates[j].low < barrierLow) barrierLow = rates[j].low; continue; }

      // پذیرش قدمِ قرمز فقط اگر Low آن از «کوچک‌ترین Low از آخرین قدم» پایین‌تر رود
      if(rates[j].low < barrierLow)
      {
         ++found;
         barrierLow = rates[j].low; // تعمیق کف با قدم پذیرفته‌شده

         if(found==1) i2=j;
         if(found==2) i3=j;
         if(found==3) i4=j;

         if(found>=need) return true;
         continue;
      }

      // اگر قدم پذیرفته نشد، barrier را با این کندل به‌روز نگه‌دار
      if(rates[j].low < barrierLow) barrierLow = rates[j].low;
   }
   return false;
}

// نسخهٔ Hunter همان منطق W2 را استفاده می‌کند
bool CheckWave2FromIndex_Hunter(const MqlRates &rates[],
                                const bool &insideClusterHL[],
                                const double &bodyLowEff[], const double &bodyHighEff[],
                                const int n, const int i1,
                                int &i2, int &i3, int &i4)
{
   return CheckWave2_FromIndex_LocalOnly(rates,insideClusterHL,bodyLowEff,bodyHighEff,n,i1,i2,i3,i4);
}

#endif // WAVEBOT_WAVE2_MQH
