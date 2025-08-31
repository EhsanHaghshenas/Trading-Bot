#ifndef WAVEBOT_WAVE2DOWN_MQH
#define WAVEBOT_WAVE2DOWN_MQH

// موج۲ نزولی (پولبک صعودی در روند نزولی) - شمارش محلی بدون پیوت
// قوانین:
// - بعد از C1، فقط کندل‌های سبز را برای گام‌ها می‌شماریم (قرمزها اسکیپ).
// - خوشه‌های inside (HL) کامل اسکیپ می‌شود.
// - Highها باید گام‌به‌گام بالاتر روند: H1<H2<H3 (و اگر لازم H4).
// - Lowها فقط باید بالای L1 بمانند: هرگاه low<=L1 ⇒ ابطال و بازگشت false.
// - اگر C1 سبز بسته شود ⇒ 2 گام کافی (i2,i3). اگر C1 قرمز بسته شود ⇒ 3 گام لازم (i2,i3,i4).
// - بدنه‌ی مؤثر (Gap) قبلاً در لایه‌ی بالاتر اعمال شده است؛ اینجا روی rates استاندارد بررسی می‌کنیم.

bool CheckWave2Down_FromIndex_LocalOnly(const MqlRates &rates[], const bool &insideHL[],
                                        const double &/*bodyLowEff*/[], const double &/*bodyHighEff*/[],
                                        const int n, const int i1,
                                        int &i2, int &i3, int &i4)
{
   i2=i3=i4=-1;
   if(i1<0 || i1>=n-1) return false;

   const double H1 = rates[i1].high;
   const double L1 = rates[i1].low;
   const bool   c1Bull = (rates[i1].close > rates[i1].open);
   const int    stepsNeeded = (c1Bull ? 2 : 3);

   int found=0;
   double lastHigh = H1;

   for(int j=i1+1; j<n; ++j)
   {
      if(insideHL[j]) continue;

      // ابطال فوری: Low نباید L1 را بشکند
      if(rates[j].low <= L1) return false;

      // اسکیپ قرمزها؛ گام‌ها فقط سبز
      if(rates[j].close <= rates[j].open) continue;

      // High باید بالاتر از آخرین Highِ شمارش‌شده باشد
      if(rates[j].high > lastHigh)
      {
         ++found;
         lastHigh = rates[j].high;

         if(found==1) i2=j;
         if(found==2) i3=j;
         if(found==3) i4=j;

         if(found >= stepsNeeded)
            return true;
      }
   }
   return false;
}

#endif // WAVEBOT_WAVE2DOWN_MQH
