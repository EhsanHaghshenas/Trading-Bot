#ifndef WAVEBOT_WAVE3_MQH
#define WAVEBOT_WAVE3_MQH

// -------------------- Wave3: Context --------------------
struct W3Context
{
   bool last_result;      // نتیجهٔ آخرین تشخیص موج۳
   int  last_c1_index;    // i1_w3 : کندل شروع موج۳
   int  last_k2;          // قدم اول موج۳ (اگر پیدا شد)
   int  last_k3;          // قدم دوم موج۳
   int  last_k4;          // قدم سوم موج۳ (اگر نیاز بود)
   int  last_need;        // تعداد قدم‌های لازم (۲ یا ۳)
   int  last_end_index;   // end_index_out : جایی که موج۳ در آن تمام‌شده در آخرین تشخیص
};

// کانتکست پیش‌فرض برای دنیای ماژور
static W3Context g_w3_ctx_major;

inline void W3_ResetCtx(W3Context &ctx)
{
   ctx.last_result    = false;
   ctx.last_c1_index  = -1;
   ctx.last_k2        = -1;
   ctx.last_k3        = -1;
   ctx.last_k4        = -1;
   ctx.last_need      =  0;
   ctx.last_end_index = -1;
}

inline void W3_ResetMajor()
{
   W3_ResetCtx(g_w3_ctx_major);
}

#include <WaveBot/Wave2.mqh>

// موج۳ صعودی + «اسکیپ همهٔ داخل‌ها»
// نکتهٔ کلیدی: barrierHigh = بزرگ‌ترین High دیده‌شده از آخرین قدم تاییدشده.
// هر کندلی (سبز/قرمز) می‌تواند barrierHigh را افزایش دهد؛ پذیرش قدمِ سبز فقط وقتی مجاز است
// که High آن از barrierHigh بالاتر برود (بنابراین هر کندلِ داخلِ کندلِ بزرگ‌تر اسکیپ می‌شود).
bool CheckWave3CountOnly_Local(const MqlRates &rates[],
                               const bool &insideClusterHL[],
                               const double &bodyLowEff[], const double &bodyHighEff[],
                               const int n, const int i1_w3,
                               int &k2, int &k3, int &k4, int &end_index_out)
{
   k2=k3=k4=-1; end_index_out=-1;
   if(i1_w3<0 || i1_w3>=n-1) return false;

   const double L1 = rates[i1_w3].low;
   const double H1 = rates[i1_w3].high;
   const bool   c1Bull = (rates[i1_w3].close > rates[i1_w3].open);
   const int    need   = (c1Bull ? 2 : 3);  // قانون پروژه: C1 سبز ⇒ ۲ قدم، C1 قرمز ⇒ ۳ قدم

   const double C1_LowEff  = bodyLowEff[i1_w3];
   const double C1_HighEff = bodyHighEff[i1_w3];

   int    found      = 0;
   double barrierHigh= H1; // سقف پویا از آخرین قدم تاییدشده یا C1

   for(int j=i1_w3+1; j<n && (j-i1_w3)<=InpMaxBarsInWave; ++j)
   {
      // اسکیپ خوشهٔ inside سراسری + به‌روزرسانی barrier
      if(insideClusterHL[j]) { if(rates[j].high > barrierHigh) barrierHigh = rates[j].high; continue; }

      // ابطال: نباید L1 شکسته شود
      if(rates[j].low < L1) return false;

      // داخل بدنهٔ مؤثر C1 ⇒ اسکیپ (و به‌روزرسانی barrier)
      if(rates[j].high <= C1_HighEff && rates[j].low >= C1_LowEff)
      { if(rates[j].high > barrierHigh) barrierHigh = rates[j].high; continue; }

      // بعد از C1 فقط سبزها شمارش می‌شوند؛ اما کندل قرمز می‌تواند barrier را افزایش دهد
      if(rates[j].close <= rates[j].open)
      { if(rates[j].high > barrierHigh) barrierHigh = rates[j].high; continue; }

      // پذیرش قدمِ سبز فقط اگر High آن از «بزرگ‌ترین High از آخرین قدم» بالاتر رود
      if(rates[j].high > barrierHigh)
      {
         ++found;
         barrierHigh = rates[j].high; // گسترش سقف با قدم پذیرفته‌شده

         if(found==1) k2=j;
         if(found==2) k3=j;
         if(found==3) k4=j;

         if(found>=need){ end_index_out=(k4>=0?k4:k3); return true; }
         continue;
      }

      // اگر قدم پذیرفته نشد، barrier را با این کندل به‌روز نگه‌دار
      if(rates[j].high > barrierHigh) barrierHigh = rates[j].high;
   }
   return false;
}

// -------------------- Wave3: Context-based wrappers --------------------
// همان منطق تابع اصلی را اجرا می‌کنیم، ولی خروجی و اطلاعات مهم را در کانتکست ذخیره می‌کنیم
// تا در دنیاهای ماژور/مینور بدون تداخل state استفاده شود.

inline bool CheckWave3CountOnly_Local_Ctx(
      W3Context        &ctx,
      const MqlRates   &rates[],
      const bool       &insideClusterHL[],
      const double     &bodyLowEff[],
      const double     &bodyHighEff[],
      const int         n,
      const int         i1_w3,
      int              &k2,
      int              &k3,
      int              &k4,
      int              &end_index_out
   )
{
   // اجرای منطق اصلی بدون هیچ تغییری
   bool ok = CheckWave3CountOnly_Local(
                rates,
                insideClusterHL,
                bodyLowEff,
                bodyHighEff,
                n,
                i1_w3,
                k2,
                k3,
                k4,
                end_index_out
             );

   // پر کردن کانتکست
   ctx.last_result    = ok;
   ctx.last_c1_index  = i1_w3;
   ctx.last_k2        = k2;
   ctx.last_k3        = k3;
   ctx.last_k4        = k4;
   ctx.last_end_index = end_index_out;

   // تعداد قدم‌های لازم را مشابه تابع اصلی از رنگ C1 استخراج می‌کنیم
   if(i1_w3 >= 0 && i1_w3 < n)
   {
      const bool c1Bull = (rates[i1_w3].close > rates[i1_w3].open);
      ctx.last_need = (c1Bull ? 2 : 3);
   }
   else
   {
      ctx.last_need = 0;
   }

   return ok;
}

// نسخهٔ کمکی برای دنیای ماژور (در صورت نیاز، برای استفاده ساده‌تر بدون مدیریت مستقیم کانتکست)
inline bool CheckWave3CountOnly_Local_Major(
      const MqlRates   &rates[],
      const bool       &insideClusterHL[],
      const double     &bodyLowEff[],
      const double     &bodyHighEff[],
      const int         n,
      const int         i1_w3,
      int              &k2,
      int              &k3,
      int              &k4,
      int              &end_index_out
   )
{
   return CheckWave3CountOnly_Local_Ctx(
             g_w3_ctx_major,
             rates,
             insideClusterHL,
             bodyLowEff,
             bodyHighEff,
             n,
             i1_w3,
             k2,
             k3,
             k4,
             end_index_out
          );
}

#endif // WAVEBOT_WAVE3_MQH