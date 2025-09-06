#ifndef WAVEBOT_WAVE3_DOWN_MQH
#define WAVEBOT_WAVE3_DOWN_MQH

#include <WaveBot/Wave2_Down.mqh>

// موج۳ نزولی + «اسکیپ همهٔ داخل‌ها»
// نکتهٔ کلیدی: barrierLow = کوچک‌ترین Low دیده‌شده از آخرین قدم تأییدشده.
// هر کندلی (سبز/قرمز) می‌تواند barrierLow را کاهش دهد؛ پذیرش قدمِ قرمز فقط وقتی مجاز است
// که Low آن از barrierLow پایین‌تر برود (بنابراین داخل هر کندل بزرگ‌تر اسکیپ می‌شود).
bool CheckWave3CountOnly_Local_Down(const MqlRates &rates[],
                                    const bool &insideClusterHL[],
                                    const double &bodyLowEff[], const double &bodyHighEff[],
                                    const int n, const int i1_w3,
                                    int &k2, int &k3, int &k4, int &end_index_out)
{
   k2=k3=k4=-1; end_index_out=-1;
   if(i1_w3<0 || i1_w3>=n-1) return false;

   const double L1 = rates[i1_w3].low;
   const double H1 = rates[i1_w3].high;
   const bool   c1Bear = (rates[i1_w3].close < rates[i1_w3].open);
   const int    need   = (c1Bear ? 2 : 3);

   const double C1_LowEff  = bodyLowEff[i1_w3];
   const double C1_HighEff = bodyHighEff[i1_w3];

   int    found     = 0;
   double barrierLow= L1; // کف پویا از آخرین قدم تاییدشده یا C1

   for(int j=i1_w3+1; j<n && (j-i1_w3)<=InpMaxBarsInWave; ++j)
   {
      // اسکیپ خوشهٔ inside سراسری
      if(insideClusterHL[j])               { if(rates[j].low < barrierLow) barrierLow = rates[j].low; continue; }

      // ابطال: نباید H1 شکسته شود
      if(rates[j].high > H1) return false;

      // داخل بدنهٔ مؤثر C1 ⇒ اسکیپ (و به‌روزرسانی barrier)
      if(rates[j].high <= C1_HighEff && rates[j].low >= C1_LowEff)
      { if(rates[j].low < barrierLow) barrierLow = rates[j].low; continue; }

      // بعد از C1 فقط قرمزها شمارش می‌شوند؛ اما کندل سبز می‌تواند barrier را کاهش دهد
      if(rates[j].close >= rates[j].open)
      { if(rates[j].low < barrierLow) barrierLow = rates[j].low; continue; }

      // پذیرش قدمِ قرمز فقط اگر Low آن از «کوچک‌ترین Low از آخرین قدم» پایین‌تر رود
      if(rates[j].low < barrierLow)
      {
         ++found;
         barrierLow = rates[j].low; // تعمیق کف با قدم پذیرفته‌شده

         if(found==1) k2=j;
         if(found==2) k3=j;
         if(found==3) k4=j;

         if(found>=need){ end_index_out=(k4>=0?k4:k3); return true; }
         continue;
      }

      // اگر قدم پذیرفته نشد، barrier را با این کندل به‌روز نگه‌دار
      if(rates[j].low < barrierLow) barrierLow = rates[j].low;
   }
   return false;
}

#endif // WAVEBOT_WAVE3_DOWN_MQH
