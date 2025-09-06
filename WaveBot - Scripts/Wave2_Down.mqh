#ifndef WAVEBOT_WAVE2_DOWN_MQH
#define WAVEBOT_WAVE2_DOWN_MQH

// بدنهٔ مؤثر C1 (Open[i]..Open[i+1]) از Bodies.mqh
inline bool InsideEffBodyC1_Down(const MqlRates &r, const double c1LowEff, const double c1HighEff)
{
   return (r.high <= c1HighEff && r.low >= c1LowEff);
}

// موج۲ صعودی (برای روند نزولی) + «اسکیپ همهٔ داخل‌ها»
// نکتهٔ کلیدی: barrierHigh = بزرگ‌ترین High دیده‌شده از آخرین قدم تأییدشده.
// هر کندلی (سبز/قرمز) می‌تواند barrierHigh را ارتقا بدهد؛ پذیرش قدمِ سبز فقط وقتی مجاز است
// که High آن از barrierHigh بزرگ‌تر باشد (بنابراین داخل هر کندل بزرگ‌تر اسکیپ می‌شود).
bool CheckWave2_FromIndex_LocalOnly_Down(const MqlRates &rates[],
                                         const bool &insideClusterHL[],
                                         const double &bodyLowEff[], const double &bodyHighEff[],
                                         const int n, const int i1,
                                         int &i2, int &i3, int &i4)
{
   i2=i3=i4=-1;
   if(i1<0 || i1>=n-1) return false;

   const double H1 = rates[i1].high;
   const double L1 = rates[i1].low;
   const bool   c1Bull = (rates[i1].close > rates[i1].open);
   const int    need   = (c1Bull ? 2 : 3);

   const double C1_LowEff  = bodyLowEff[i1];
   const double C1_HighEff = bodyHighEff[i1];

   int    found      = 0;
   double barrierHigh= H1; // سقف پویا از آخرین قدم تاییدشده یا C1

   for(int j=i1+1; j<n && (j-i1)<=InpMaxBarsInWave; ++j)
   {
      // اسکیپ خوشهٔ inside سراسری
      if(insideClusterHL[j])               { if(rates[j].high > barrierHigh) barrierHigh = rates[j].high; continue; }

      // ابطال: نباید L1 شکسته شود
      if(rates[j].low < L1) return false;

      // داخل بدنهٔ مؤثر C1 ⇒ اسکیپ (و ارتقای barrier در صورت لزوم)
      if(InsideEffBodyC1_Down(rates[j], C1_LowEff, C1_HighEff))
      { if(rates[j].high > barrierHigh) barrierHigh = rates[j].high; continue; }

      // بعد از C1 فقط سبزها شمارش می‌شوند؛ اما کندل قرمز می‌تواند barrier را ارتقا دهد
      if(rates[j].close <= rates[j].open)
      { if(rates[j].high > barrierHigh) barrierHigh = rates[j].high; continue; }

      // پذیرش قدمِ سبز فقط اگر High آن از «بزرگ‌ترین High از آخرین قدم» بالاتر رود
      if(rates[j].high > barrierHigh)
      {
         ++found;
         barrierHigh = rates[j].high; // گسترش سقف با قدم پذیرفته‌شده

         if(found==1) i2=j;
         if(found==2) i3=j;
         if(found==3) i4=j;

         if(found>=need) return true;
         continue;
      }

      // اگر قدم پذیرفته نشد، barrier را با این کندل به‌روز نگه‌دار
      if(rates[j].high > barrierHigh) barrierHigh = rates[j].high;
   }
   return false;
}

// نسخهٔ Hunter همان منطق W2 را استفاده می‌کند
bool CheckWave2FromIndex_Hunter_Down(const MqlRates &rates[],
                                     const bool &insideClusterHL[],
                                     const double &bodyLowEff[], const double &bodyHighEff[],
                                     const int n, const int i1,
                                     int &i2, int &i3, int &i4)
{
   return CheckWave2_FromIndex_LocalOnly_Down(rates,insideClusterHL,bodyLowEff,bodyHighEff,n,i1,i2,i3,i4);
}

#endif // WAVEBOT_WAVE2_DOWN_MQH
