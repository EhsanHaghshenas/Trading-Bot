// ============================================================================
#ifndef WAVEBOT_WAVE3_DOWN_MQH
#define WAVEBOT_WAVE3_DOWN_MQH

// -------------------- Wave3_Down: Context --------------------
struct W3DownContext
{
   bool last_result;      // نتیجهٔ آخرین تشخیص موج۳ نزولی
   int  last_c1_index;    // i1_w3 : کندل شروع موج۳ نزولی
   int  last_k2;          // قدم اول موج۳ (اگر پیدا شد)
   int  last_k3;          // قدم دوم موج۳
   int  last_k4;          // قدم سوم موج۳ (اگر نیاز بود)
   int  last_need;        // تعداد قدم‌های لازم (۲ یا ۳)
   int  last_end_index;   // end_index_out : نقطهٔ پایان موج۳ در آخرین تشخیص
};

// کانتکست پیش‌فرض برای دنیای ماژور
static W3DownContext g_w3d_ctx_major;

inline void W3Down_ResetCtx(W3DownContext &ctx)
{
   ctx.last_result    = false;
   ctx.last_c1_index  = -1;
   ctx.last_k2        = -1;
   ctx.last_k3        = -1;
   ctx.last_k4        = -1;
   ctx.last_need      =  0;
   ctx.last_end_index = -1;
}

inline void W3Down_ResetMajor()
{
   W3Down_ResetCtx(g_w3d_ctx_major);
}

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
      if(insideClusterHL[j])
      {
         if(rates[j].low < barrierLow)
            barrierLow = rates[j].low;
         continue;
      }

      // ابطال: نباید H1 شکسته شود
      if(rates[j].high > H1)
         return false;

      // داخل بدنهٔ مؤثر C1 ⇒ اسکیپ (و به‌روزرسانی barrier)
      if(rates[j].high <= C1_HighEff && rates[j].low >= C1_LowEff)
      {
         if(rates[j].low < barrierLow)
            barrierLow = rates[j].low;
         continue;
      }

      // بعد از C1 فقط قرمزها شمارش می‌شوند؛ اما کندل سبز می‌تواند barrier را کاهش دهد
      if(rates[j].close >= rates[j].open)
      {
         if(rates[j].low < barrierLow)
            barrierLow = rates[j].low;
         continue;
      }

      // پذیرش قدمِ قرمز فقط اگر Low آن از «کوچک‌ترین Low از آخرین قدم» پایین‌تر رود
      if(rates[j].low < barrierLow)
      {
         ++found;
         barrierLow = rates[j].low; // تعمیق کف با قدم پذیرفته‌شده

         if(found==1) k2=j;
         if(found==2) k3=j;
         if(found==3) k4=j;

         if(found>=need)
         {
            end_index_out = (k4>=0 ? k4 : k3);
            return true;
         }
         continue;
      }

      // اگر قدم پذیرفته نشد، barrier را با این کندل به‌روز نگه‌دار
      if(rates[j].low < barrierLow)
         barrierLow = rates[j].low;
   }
   return false;
}

// -------------------- Wave3_Down: Context-based wrappers --------------------
// همان منطق تابع اصلی را اجرا می‌کنیم، اما خروجی و اطلاعات موج۳ را در کانتکست
// ذخیره می‌کنیم تا در دنیاهای ماژور/مینور بدون تداخل state استفاده شوند.

inline bool CheckWave3CountOnly_Local_Down_Ctx(
      W3DownContext    &ctx,
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
   bool ok = CheckWave3CountOnly_Local_Down(
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

   // ذخیرهٔ نتایج در کانتکست
   ctx.last_result    = ok;
   ctx.last_c1_index  = i1_w3;
   ctx.last_k2        = k2;
   ctx.last_k3        = k3;
   ctx.last_k4        = k4;
   ctx.last_end_index = end_index_out;

   // مشابه Wave3 صعودی: تعداد قدم‌ها بر اساس رنگ C1
   if(i1_w3 >= 0 && i1_w3 < n)
   {
      const bool c1Bear = (rates[i1_w3].close < rates[i1_w3].open);
      ctx.last_need = (c1Bear ? 2 : 3);
   }
   else
   {
      ctx.last_need = 0;
   }

   return ok;
}

// نسخهٔ کمکی برای دنیای ماژور (برای راحتی و سازگاری در آینده)
inline bool CheckWave3CountOnly_Local_Down_Major(
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
   return CheckWave3CountOnly_Local_Down_Ctx(
             g_w3d_ctx_major,
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

#endif // WAVEBOT_WAVE3_DOWN_MQH
