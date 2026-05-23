// ============================================================================
// WaveBot/W2W3_ChainInvalidation.mqh
#ifndef WAVEBOT_W2W3_CHAININVALIDATION_MQH
#define WAVEBOT_W2W3_CHAININVALIDATION_MQH

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

#endif // WAVEBOT_W2W3_CHAININVALIDATION_MQH
