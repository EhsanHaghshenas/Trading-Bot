#ifndef WAVEBOT_HUNTER_BODYBREAK_MQH
#define WAVEBOT_HUNTER_BODYBREAK_MQH

#include <WaveBot/Markers.mqh>
#include <WaveBot/ExtLQ.mqh>
#include <WaveBot/ExtLQ_Down.mqh>
#include <WaveBot/Hunter.mqh>       // برای دسترسی به SW_UP_Seed* (بذرهانتر معتبر)
#include <WaveBot/Hunter_Down.mqh>  // برای دسترسی به SW_DOWN_Seed*
#include <WaveBot/RaceCoordinator.mqh>

// ============================================================================
// هدف: تنها «کندل بدنه‌شکن» نسبت به ext lq را بعد از یک Hunter معتبر نشان بدهیم.
// منطق ارتقای سطح (wick escalation):
//  - اگر ابتدا عبور با شدو رخ دهد و کلوز آن‌طرفِ سطح نباشد، سطح ← کمترین Low (UP)
//    یا بیشترین High (DOWN) همان عبور؛ سپس تا اولین کلوز فراتر از سطحِ ارتقایافته
//    صبر می‌کنیم و همان کندل را نمایش می‌دهیم.
//  - برای هر ext lq فقط یک‌بار مارک می‌زنیم (first-pass per LQ).
// ============================================================================

// -------------------- UP state --------------------
static datetime g_bb_lq_time_u   = 0;    // ext lq فعال (زمان)
static bool     g_bb_done_u      = false;// آیا برای این LQ مارک زده‌ایم؟
static bool     g_bb_armed_u     = false;// بازوگذاری پس از Hunter معتبر
static double   g_bb_level_u     = 0.0;  // سطح جاریِ شکست با بدنه (ارتقاپذیر)
static datetime g_bb_cross_time_u= 0;    // از این زمان به بعد پایش می‌کنیم
static int      g_bb_counter_u   = 0;    // شمارنده‌ی مارکرها

// -------------------- DOWN state ------------------
static datetime g_bb_lq_time_d   = 0;
static bool     g_bb_done_d      = false;
static bool     g_bb_armed_d     = false;
static double   g_bb_level_d     = 0.0;
static datetime g_bb_cross_time_d= 0;
static int      g_bb_counter_d   = 0;

// ---------- کمک‌کارها ----------
inline void HW_BB_UP_ResetIfNewLQ()
{
   const bool has = ExtLQ_Has();
   const datetime t = has ? ExtLQ_Time() : 0;
   if(t != g_bb_lq_time_u){
      g_bb_lq_time_u = t;
      g_bb_done_u    = false;
      g_bb_armed_u   = false;
      g_bb_level_u   = (has? ExtLQ_Get():0.0);
      g_bb_cross_time_u = 0;
   }
}

inline void HW_BB_DOWN_ResetIfNewLQ()
{
   const bool has = ExtLQ_Down_Has();
   const datetime t = has ? ExtLQ_Down_Time() : 0;
   if(t != g_bb_lq_time_d){
      g_bb_lq_time_d = t;
      g_bb_done_d    = false;
      g_bb_armed_d   = false;
      g_bb_level_d   = (has? ExtLQ_Down_Get():0.0);
      g_bb_cross_time_d = 0;
   }
}

// --------------------------- UP: OnBar ---------------------------
// شرط نمایش در مود صعودی: «کلوز زیر سطح (ext lq یا سطحِ ارتقایافته)»
// با رعایت: تنها بعد از Hunter معتبر (از بذر SW-UP استفاده می‌کنیم).
inline void HW_BB_UP_OnBar(const MqlRates &r, const MqlRates &rates[], const int n, const int j)
{
   if(Race_IsLocked()) return; // تا تعیین برنده، HWBB جدید ممنوع
   if(!ExtLQ_Has()) return;

   // اگر ext lq تازه شده، ریست محلی
   HW_BB_UP_ResetIfNewLQ();
   if(g_bb_done_u) return;

   // بازوگذاری تنها پس از Hunter معتبر (از Seed زمان کراس استفاده می‌کنیم)
   if(!g_bb_armed_u)
   {
      if(SW_UP_SeedActive() && SW_UP_SeedTime() >= g_bb_lq_time_u)
      {
         g_bb_armed_u      = true;
         g_bb_level_u      = ExtLQ_Get();
         g_bb_cross_time_u = SW_UP_SeedTime();
      }
      else return;
   }

   // فقط از زمان کراس هانتر به بعد پایش می‌کنیم
   if(r.time < g_bb_cross_time_u) return;

   // 1) اگر کلوز زیر سطحِ جاری است ⇒ همان کندل مطلوب ماست
   if(r.close < g_bb_level_u)
   {
      ++g_bb_counter_u;
      if(InpDrawMarkers) MarkV("HWBB_U_"+IntegerToString(g_bb_counter_u), r.time, clrRoyalBlue);
      // --- شروع مسابقه از همین کندل HWBB (Mode=UP)
      Race_Start_UP(rates, n, j);
      g_bb_done_u  = true;
      g_bb_armed_u = false;
      return;
   }

   // 2) اگر عبور فقط با شدو رخ داد ⇒ ارتقای سطح (wick escalation)
   if(r.low < g_bb_level_u)
   {
      g_bb_level_u = r.low; // ارتقا به Low عبور
   }
}

// -------------------------- DOWN: OnBar --------------------------
// شرط نمایش در مود نزولی: «کلوز بالای سطح (ext lq یا سطحِ ارتقایافته)»
// با رعایت: تنها بعد از Hunter معتبر (از Seed زمان کراس استفاده می‌کنیم).
inline void HW_BB_DOWN_OnBar(const MqlRates &r, const MqlRates &rates[], const int n, const int j)
{
   if(Race_IsLocked()) return; // تا تعیین برنده، HWBB جدید ممنوع
   if(!ExtLQ_Down_Has()) return;

   // اگر ext lq تازه شده، ریست محلی
   HW_BB_DOWN_ResetIfNewLQ();
   if(g_bb_done_d) return;

   if(!g_bb_armed_d)
   {
      if(SW_DOWN_SeedActive() && SW_DOWN_SeedTime() >= g_bb_lq_time_d)
      {
         g_bb_armed_d      = true;
         g_bb_level_d      = ExtLQ_Down_Get();
         g_bb_cross_time_d = SW_DOWN_SeedTime();
      }
      else return;
   }

   if(r.time < g_bb_cross_time_d) return;

   if(r.close > g_bb_level_d)
   {
      ++g_bb_counter_d;
      if(InpDrawMarkers) MarkV("HWBB_D_"+IntegerToString(g_bb_counter_d), r.time, clrDarkOrange);
      // --- شروع مسابقه از همین کندل HWBB (Mode=DOWN)
      Race_Start_DOWN(rates, n, j);
      g_bb_done_d  = true;
      g_bb_armed_d = false;
      return;
   }

   if(r.high > g_bb_level_d)
   {
      g_bb_level_d = r.high; // ارتقا به High عبور
   }
}

#endif // WAVEBOT_HUNTER_BODYBREAK_MQH
