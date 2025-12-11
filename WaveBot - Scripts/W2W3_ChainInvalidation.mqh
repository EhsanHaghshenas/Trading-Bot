// WaveBot/W2W3_ChainInvalidation.mqh
#ifndef WAVEBOT_W2W3_CHAININVALIDATION_MQH
#define WAVEBOT_W2W3_CHAININVALIDATION_MQH

// -------------------- W2/W3 Chain Invalidation: Context --------------------
struct W2W3ChainCtx
{
   // آخرین نتیجه برای UP/DOWN
   bool last_up_trigger;
   bool last_dn_trigger;

   // آخرین j که باعث تریگر شد (برای دیباگ)
   int  last_up_j;
   int  last_dn_j;

   // آخرین firstWickIdx (محل بازگشت) برای UP/DOWN
   int  last_up_rewind_idx;
   int  last_dn_rewind_idx;

   // آخرین C1_W3 مؤثر (w3_c1 یا w3_cand) برای UP/DOWN
   int  last_up_c1_eff;
   int  last_dn_c1_eff;
};

// کانتکست پیش‌فرض برای دنیای ماژور
static W2W3ChainCtx g_w2w3_chain_major;

inline void W2W3Chain_ResetCtx(W2W3ChainCtx &ctx)
{
   ctx.last_up_trigger     = false;
   ctx.last_dn_trigger     = false;

   ctx.last_up_j           = -1;
   ctx.last_dn_j           = -1;

   ctx.last_up_rewind_idx  = -1;
   ctx.last_dn_rewind_idx  = -1;

   ctx.last_up_c1_eff      = -1;
   ctx.last_dn_c1_eff      = -1;
}

inline void W2W3Chain_ResetMajor()
{
   W2W3Chain_ResetCtx(g_w2w3_chain_major);
}

#include <WaveBot/Utils.mqh>

// قانون: اگر W2 و W3 هر دو کامل شده‌اند و C1_W2 با شدو شکسته شده
// (wickActive=true, firstWickIdx>=0, breakAchieved=false) و سپس C1_W3 ابطال شود:
//   UP  : L(j) < L(C1_W3)
//   DOWN: H(j) > H(C1_W3)
// آنگاه هر دو موج W2 و W3 باطل و اسکن از firstWickIdx آغاز می‌شود.

// ---------- UP ----------
inline bool ChainInv_PreBody_WickWindow_UP_OnBar(
      const MqlRates &rates[],
      const bool     &insideHL[],
      const int       n,
      const int       j,               // کندل جاری در حلقه WAIT_CONFIRM
      const bool      breakAchieved,   // آیا شکست بدنه‌ای رخ داده؟
      const bool      wickActive,      // آیا در پنجره‌ی شدویی هستیم؟
      const int       firstWickIdx,    // اولین کندلِ شکستِ شدویی C1_W2
      const int       w3_c1,           // C1_W3 قفل‌شده (در مسیر ویکی)
      const int       w3_cand,         // C1_W3 در مسیر مستقیم (اگر قفل نشده)
      int            &rewind_to_idx    // خروجی: نقطه‌ی بازگشت (اولین کندلِ شدویی)
   )
{
   if(breakAchieved || !wickActive || firstWickIdx < 0) return false;
   int c1_eff = (w3_c1>=0 ? w3_c1 : w3_cand);
   if(c1_eff < 0) return false;

   // ابطال C1_W3 (UP): Low جدید < Low(C1_W3)
   if(rates[j].low < rates[c1_eff].low)
   {
      rewind_to_idx = firstWickIdx;
      return true;
   }
   return false;
}

// ---------- DOWN ----------
inline bool ChainInv_PreBody_WickWindow_DN_OnBar(
      const MqlRates &rates[],
      const bool     &insideHL[],
      const int       n,
      const int       j,
      const bool      breakAchieved,
      const bool      wickActive,
      const int       firstWickIdx,
      const int       w3_c1,
      const int       w3_cand,
      int            &rewind_to_idx
   )
{
   if(breakAchieved || !wickActive || firstWickIdx < 0) return false;
   int c1_eff = (w3_c1>=0 ? w3_c1 : w3_cand);
   if(c1_eff < 0) return false;

   // ابطال C1_W3 (DOWN): High جدید > High(C1_W3)
   if(rates[j].high > rates[c1_eff].high)
   {
      rewind_to_idx = firstWickIdx;
      return true;
   }
   return false;
}
// -------------------- W2/W3 Chain Invalidation: Context-based wrappers --------------------

// نسخهٔ Context-based برای UP
inline bool ChainInv_PreBody_WickWindow_UP_OnBar_Ctx(
      W2W3ChainCtx    &ctx,
      const MqlRates  &rates[],
      const bool      &insideHL[],
      const int        n,
      const int        j,
      const bool       breakAchieved,
      const bool       wickActive,
      const int        firstWickIdx,
      const int        w3_c1,
      const int        w3_cand,
      int             &rewind_to_idx
   )
{
   // محاسبهٔ C1_W3 مؤثر (همان منطق داخل تابع اصلی)
   int c1_eff = (w3_c1>=0 ? w3_c1 : w3_cand);

   // فراخوانی منطق اصلی بدون تغییر
   bool triggered = ChainInv_PreBody_WickWindow_UP_OnBar(
                       rates,
                       insideHL,
                       n,
                       j,
                       breakAchieved,
                       wickActive,
                       firstWickIdx,
                       w3_c1,
                       w3_cand,
                       rewind_to_idx
                    );

   // پر کردن کانتکست برای دنیای مربوطه
   ctx.last_up_trigger    = triggered;
   ctx.last_up_j          = j;
   ctx.last_up_rewind_idx = (triggered ? rewind_to_idx : -1);
   ctx.last_up_c1_eff     = c1_eff;

   return triggered;
}

// نسخهٔ Context-based برای DOWN
inline bool ChainInv_PreBody_WickWindow_DN_OnBar_Ctx(
      W2W3ChainCtx    &ctx,
      const MqlRates  &rates[],
      const bool      &insideHL[],
      const int        n,
      const int        j,
      const bool       breakAchieved,
      const bool       wickActive,
      const int        firstWickIdx,
      const int        w3_c1,
      const int        w3_cand,
      int             &rewind_to_idx
   )
{
   int c1_eff = (w3_c1>=0 ? w3_c1 : w3_cand);

   bool triggered = ChainInv_PreBody_WickWindow_DN_OnBar(
                       rates,
                       insideHL,
                       n,
                       j,
                       breakAchieved,
                       wickActive,
                       firstWickIdx,
                       w3_c1,
                       w3_cand,
                       rewind_to_idx
                    );

   ctx.last_dn_trigger    = triggered;
   ctx.last_dn_j          = j;
   ctx.last_dn_rewind_idx = (triggered ? rewind_to_idx : -1);
   ctx.last_dn_c1_eff     = c1_eff;

   return triggered;
}

// نسخه‌های کمکی برای دنیای ماژور (اختیاری؛ برای استفاده ساده)
inline bool ChainInv_PreBody_WickWindow_UP_OnBar_Major(
      const MqlRates &rates[],
      const bool     &insideHL[],
      const int       n,
      const int       j,
      const bool      breakAchieved,
      const bool      wickActive,
      const int       firstWickIdx,
      const int       w3_c1,
      const int       w3_cand,
      int            &rewind_to_idx
   )
{
   return ChainInv_PreBody_WickWindow_UP_OnBar_Ctx(
             g_w2w3_chain_major,
             rates,
             insideHL,
             n,
             j,
             breakAchieved,
             wickActive,
             firstWickIdx,
             w3_c1,
             w3_cand,
             rewind_to_idx
          );
}

inline bool ChainInv_PreBody_WickWindow_DN_OnBar_Major(
      const MqlRates &rates[],
      const bool     &insideHL[],
      const int       n,
      const int       j,
      const bool      breakAchieved,
      const bool      wickActive,
      const int       firstWickIdx,
      const int       w3_c1,
      const int       w3_cand,
      int            &rewind_to_idx
   )
{
   return ChainInv_PreBody_WickWindow_DN_OnBar_Ctx(
             g_w2w3_chain_major,
             rates,
             insideHL,
             n,
             j,
             breakAchieved,
             wickActive,
             firstWickIdx,
             w3_c1,
             w3_cand,
             rewind_to_idx
          );
}

#endif // WAVEBOT_W2W3_CHAININVALIDATION_MQH
