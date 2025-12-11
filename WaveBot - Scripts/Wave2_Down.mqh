#ifndef WAVEBOT_WAVE2_DOWN_MQH
#define WAVEBOT_WAVE2_DOWN_MQH

// -------------------- Wave2_Down: Context --------------------
struct W2DownContext
{
   bool last_result;     // نتیجهٔ آخرین تشخیص W2_Down
   int  last_c1_index;   // ایندکس C1 که از آن شروع کردیم (i1)
   int  last_i2;         // قدم اول موج۲ (اگر پیدا شد)
   int  last_i3;         // قدم دوم موج۲ (اگر پیدا شد)
   int  last_i4;         // قدم سوم موج۲ (اگر نیاز بود و پیدا شد)
   int  last_need;       // تعداد قدم‌های لازم (۲ اگر C1 قرمز، ۳ اگر C1 سبز)
   int  last_scanned_to; // آخرین ایندسی که عملاً تا آنجا اسکن/بررسی شد (برای دیباگ)
};

// کانتکست پیش‌فرض برای دنیای ماژور (جهت سازگاری)
static W2DownContext g_w2d_ctx_major;

inline void W2Down_ResetCtx(W2DownContext &ctx)
{
   ctx.last_result     = false;
   ctx.last_c1_index   = -1;
   ctx.last_i2         = -1;
   ctx.last_i3         = -1;
   ctx.last_i4         = -1;
   ctx.last_need       =  0;
   ctx.last_scanned_to = -1;
}

inline void W2Down_ResetMajor()
{
   W2Down_ResetCtx(g_w2d_ctx_major);
}

// بدنهٔ مؤثر C1 (Open[i]..Open[i+1]) از Bodies.mqh
inline bool InsideEffBodyC1_Down(const MqlRates &r, const double c1LowEff, const double c1HighEff)
{
   return (r.high <= c1HighEff && r.low >= c1LowEff);
}

// -------------------- Wave2_Down: Context-based wrappers --------------------
// همان منطق تابع‌های اصلی را صدا می‌کنیم، ولی نتیجه و ایندکس‌ها را در کانتکست ذخیره می‌کنیم
// تا بتوانیم در دنیاهای موازی (ماژور/مینور) بدون تداخل state کار کنیم.

// نسخهٔ context-based برای تابع اصلی LocalOnly_Down
inline bool CheckWave2_FromIndex_LocalOnly_Down_Ctx(W2DownContext &ctx,
                                                     const MqlRates &rates[],
                                                     const bool &insideClusterHL[],
                                                     const double &bodyLowEff[],
                                                     const double &bodyHighEff[],
                                                     const int n, const int i1,
                                                     int &i2, int &i3, int &i4)
{
   // اجرای منطق اصلی بدون تغییر
   bool ok = CheckWave2_FromIndex_LocalOnly_Down(rates,
                                                 insideClusterHL,
                                                 bodyLowEff,
                                                 bodyHighEff,
                                                 n, i1, i2, i3, i4);

   // به‌روزرسانی کانتکست
   ctx.last_result   = ok;
   ctx.last_c1_index = i1;
   ctx.last_i2       = i2;
   ctx.last_i3       = i3;
   ctx.last_i4       = i4;

   // مشابه Wave2: تعداد قدم‌های لازم بر اساس رنگ C1
   if(i1 >= 0 && i1 < n)
   {
      const bool c1Bull = (rates[i1].close > rates[i1].open);
      ctx.last_need = (c1Bull ? 2 : 3);
   }
   else
   {
      ctx.last_need = 0;
   }

   // آخرین ایندکس مؤثرِ اسکن‌شده (برای دیباگ مسیر موج۲)
   ctx.last_scanned_to = (i4 >= 0 ? i4
                         : (i3 >= 0 ? i3
                         : (i2 >= 0 ? i2
                         : i1)));

   return ok;
}

// نسخهٔ context-based برای Hunter_Down
inline bool CheckWave2FromIndex_Hunter_Down_Ctx(W2DownContext &ctx,
                                                const MqlRates &rates[],
                                                const bool &insideClusterHL[],
                                                const double &bodyLowEff[],
                                                const double &bodyHighEff[],
                                                const int n, const int i1,
                                                int &i2, int &i3, int &i4)
{
   // Hunter نسخهٔ رپِر روی LocalOnly است؛ همان را صدا می‌زنیم
   bool ok = CheckWave2FromIndex_Hunter_Down(rates,
                                             insideClusterHL,
                                             bodyLowEff,
                                             bodyHighEff,
                                             n, i1, i2, i3, i4);

   // به‌روزرسانی کانتکست مشابه بالا
   ctx.last_result   = ok;
   ctx.last_c1_index = i1;
   ctx.last_i2       = i2;
   ctx.last_i3       = i3;
   ctx.last_i4       = i4;

   if(i1 >= 0 && i1 < n)
   {
      const bool c1Bull = (rates[i1].close > rates[i1].open);
      ctx.last_need = (c1Bull ? 2 : 3);
   }
   else
   {
      ctx.last_need = 0;
   }

   ctx.last_scanned_to = (i4 >= 0 ? i4
                         : (i3 >= 0 ? i3
                         : (i2 >= 0 ? i2
                         : i1)));

   return ok;
}

// نسخه‌های کمکی برای دنیای ماژور (اختیاری؛ برای سازگاری ساده‌تر)
inline bool CheckWave2_FromIndex_LocalOnly_Down_Major(const MqlRates &rates[],
                                                      const bool &insideClusterHL[],
                                                      const double &bodyLowEff[],
                                                      const double &bodyHighEff[],
                                                      const int n, const int i1,
                                                      int &i2, int &i3, int &i4)
{
   return CheckWave2_FromIndex_LocalOnly_Down_Ctx(g_w2d_ctx_major,
                                                  rates,
                                                  insideClusterHL,
                                                  bodyLowEff,
                                                  bodyHighEff,
                                                  n, i1, i2, i3, i4);
}

inline bool CheckWave2FromIndex_Hunter_Down_Major(const MqlRates &rates[],
                                                  const bool &insideClusterHL[],
                                                  const double &bodyLowEff[],
                                                  const double &bodyHighEff[],
                                                  const int n, const int i1,
                                                  int &i2, int &i3, int &i4)
{
   return CheckWave2FromIndex_Hunter_Down_Ctx(g_w2d_ctx_major,
                                              rates,
                                              insideClusterHL,
                                              bodyLowEff,
                                              bodyHighEff,
                                              n, i1, i2, i3, i4);
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
