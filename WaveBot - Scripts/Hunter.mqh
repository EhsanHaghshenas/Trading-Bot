
#ifndef WAVEBOT_HUNTER_MQH
#define WAVEBOT_HUNTER_MQH

#include <WaveBot/Markers.mqh>
#include <WaveBot/ExtLQ.mqh>
#include <WaveBot/Utils.mqh>
#include <WaveBot/RaceCoordinator.mqh>
#include <WaveBot/SWGate.mqh>

// ---------------- Hunter (UP) state ----------------
static int      g_hw_counter_u     = 0;
static datetime g_lq_time_seen_u   = 0;
static bool     g_marked_for_lq_u  = false; // فقط «اولین عبور معتبر» برای هر ext lq

// ---------------- Strong Wave (UP) seed ----------------
static bool     g_sw_seed_u_active = false;
static int      g_sw_seed_u_c1     = -1;     // اندیس C1 هانتر
static datetime g_sw_seed_u_xtime  = 0;      // زمان شکست ext lq
static double   g_sw_seed_u_level  = 0.0;    // High(C1 هانتر)
static int      g_sw_counter_u     = 0;      // شمارندهٔ مارکرهای SW
// ---------------- Hunter-UP Context (for major/minor worlds) ----------------
struct HunterUpContext
{
   int      hw_counter;      // همان g_hw_counter_u
   datetime lq_time_seen;    // همان g_lq_time_seen_u
   bool     marked_for_lq;   // همان g_marked_for_lq_u

   bool     sw_seed_active;  // همان g_sw_seed_u_active
   int      sw_seed_c1;      // همان g_sw_seed_u_c1
   datetime sw_seed_xtime;   // همان g_sw_seed_u_xtime
   double   sw_seed_level;   // همان g_sw_seed_u_level
   int      sw_counter;      // همان g_sw_counter_u
};

// مقداردهی اولیهٔ یک کانتکست خالی (شروع یک دنیا)
inline void Hunter_UP_ContextInit(HunterUpContext &ctx)
{
   ctx.hw_counter    = 0;
   ctx.lq_time_seen  = 0;
   ctx.marked_for_lq = false;

   ctx.sw_seed_active = false;
   ctx.sw_seed_c1     = -1;
   ctx.sw_seed_xtime  = 0;
   ctx.sw_seed_level  = 0.0;
   ctx.sw_counter     = 0;
}

// خروجی گرفتن از وضعیت فعلی ماژول به داخل کانتکست
inline void Hunter_UP_ContextExport(HunterUpContext &ctx)
{
   ctx.hw_counter    = g_hw_counter_u;
   ctx.lq_time_seen  = g_lq_time_seen_u;
   ctx.marked_for_lq = g_marked_for_lq_u;

   ctx.sw_seed_active = g_sw_seed_u_active;
   ctx.sw_seed_c1     = g_sw_seed_u_c1;
   ctx.sw_seed_xtime  = g_sw_seed_u_xtime;
   ctx.sw_seed_level  = g_sw_seed_u_level;
   ctx.sw_counter     = g_sw_counter_u;
}

// لود کردن وضعیت از کانتکست به متغیرهای داخلی ماژول
inline void Hunter_UP_ContextImport(const HunterUpContext &ctx)
{
   g_hw_counter_u     = ctx.hw_counter;
   g_lq_time_seen_u   = ctx.lq_time_seen;
   g_marked_for_lq_u  = ctx.marked_for_lq;

   g_sw_seed_u_active = ctx.sw_seed_active;
   g_sw_seed_u_c1     = ctx.sw_seed_c1;
   g_sw_seed_u_xtime  = ctx.sw_seed_xtime;
   g_sw_seed_u_level  = ctx.sw_seed_level;
   g_sw_counter_u     = ctx.sw_counter;
}

// ریست کامل وضعیت داخلی Hunter-UP (برای شروع از صفر)
inline void Hunter_UP_ResetGlobals()
{
   g_hw_counter_u     = 0;
   g_lq_time_seen_u   = 0;
   g_marked_for_lq_u  = false;

   g_sw_seed_u_active = false;
   g_sw_seed_u_c1     = -1;
   g_sw_seed_u_xtime  = 0;
   g_sw_seed_u_level  = 0.0;
   g_sw_counter_u     = 0;
}

// === NEW: expose C1 index/time for the last valid Hunter-UP seed ===
inline int SW_UP_C1Index()
{
   // فرض: متغیر داخلی بذرِ SW-UP به‌نام g_sw_seed_u_c1 در همین فایل تعریف شده است
   return g_sw_seed_u_c1;
}

inline datetime SW_UP_C1Time(const MqlRates &rates[], const int n)
{
   int i = SW_UP_C1Index();
   return (i>=0 && i<n ? rates[i].time : 0);
}

// فراخوانی هنگام ست‌شدن ext lq بعد از تایید هر W3
inline void Hunter_OnExtLQUpdated()
{
   // ریست وضعیت hunter برای ext lq جدید (سمت UP)
   g_lq_time_seen_u  = ExtLQ_Has() ? ExtLQ_Time() : 0;
   g_marked_for_lq_u = false;

   // --- NEW: اگر مسابقه قفل است و Mode=DOWN بوده، همین ext lq(UP) یعنی برنده مشخص شده
   if(ExtLQ_Has())
      Race_TryUnlockOnNewLQ_Notify(DIR_UP, ExtLQ_Time());
}

// عبور از ext lq (UP) ⇒ کراس رو به پایین (بدنه یا شدو)
inline bool Hunter_IsExtLQCross(const MqlRates &r)
{
   if(!ExtLQ_Has()) return false;
   const double lq = ExtLQ_Get();
   return (r.low <= lq || r.close < lq);
}

// ابطال Hunter پیش از کراس: اگر تا قبل از کراس، High > High(C1) شود ⇒ Hunter نامعتبر
inline bool Hunter_IsC1Invalidated_BeforeCross_UP(const MqlRates &rates[], const int n,
                                                  const int c1_index, const int cross_idx)
{
   if(c1_index < 0 || cross_idx < 0 || c1_index >= n || cross_idx >= n) return true;
   if(cross_idx <= c1_index) return true;

   const double hC1 = rates[c1_index].high;
   for(int i=c1_index+1; i<cross_idx; ++i)
      if(rates[i].high > hC1) return true;

   return false;
}

// فعال‌سازی بذر SW پس از ثبت Hunter معتبر
inline void SW_UP_ActivateSeed(const MqlRates &rates[], const int n,
                               const int c1_index, const int cross_idx)
{
   g_sw_seed_u_active = true;
   g_sw_seed_u_c1     = c1_index;
   g_sw_seed_u_xtime  = rates[cross_idx].time;
   g_sw_seed_u_level  = rates[c1_index].high;
}

// دسترسی به بذر SW-UP
inline bool     SW_UP_SeedActive()      { return g_sw_seed_u_active; }
inline double   SW_UP_Level()           { return g_sw_seed_u_level;  }
inline datetime SW_UP_SeedTime()        { return g_sw_seed_u_xtime;  }
inline void     SW_UP_ClearSeed()       { g_sw_seed_u_active=false;  }

// تلاش برای نمایش Hunter فقط هنگام وقوع «کراس» و در صورت اعتبار
inline void Hunter_TryMarkIfValid(const MqlRates &rates[], const int n,
                                  const int c1_index, const int cross_idx)
{
   if(!ExtLQ_Has()) return;

   const datetime lqt = ExtLQ_Time();
   if(lqt != g_lq_time_seen_u){ g_lq_time_seen_u = lqt; g_marked_for_lq_u = false; }
   if(g_marked_for_lq_u) return; // اولین عبور معتبر قبلاً ثبت شده

   if(Hunter_IsC1Invalidated_BeforeCross_UP(rates, n, c1_index, cross_idx))
      return; // Hunter نامعتبر؛ بذر SW هم فعال نشود

   // --- ثبت Hunter (اولین عبور معتبر)
   ++g_hw_counter_u;
   string tag = IntegerToString(g_hw_counter_u);

   if(InpDrawMarkers)
   {
      MarkV("HW_"+tag+"_C1", rates[c1_index].time, clrViolet);
      MarkV("HW_"+tag+"_X",  rates[cross_idx].time, clrMagenta);
   }
   g_marked_for_lq_u = true;

   // NEW (H4->M15 bridge): HWX is a START trigger (intrabar)
   WB15_PublishStartHWX(InpSymbol, DIR_UP, rates[cross_idx].time);

   // --- بذر SW را فعال کن (Highِ C1 هانتر)
   SW_UP_ActivateSeed(rates, n, c1_index, cross_idx);

   if(InpDebugPrints)
      Print("[Hunter-UP] OK | C1=",T(rates[c1_index].time),
            " | CROSS=",T(rates[cross_idx].time),
            " | ext lq=",DoubleToString(ExtLQ_Get(),_Digits),
            " | SW seed Lvl(H)= ",DoubleToString(g_sw_seed_u_level,_Digits));
}

// هنگام تایید یک W3 صعودی، بررسی کن آیا شرایط SW برقرار است
inline void SW_UP_TryMarkOnConfirmedW3(const MqlRates &rates[], const int n,
                                       const int w3_c1, const int bodyBreakIdx)
{
   Race_OnSWConfirmed_UP(rates, n, w3_c1, bodyBreakIdx);
   
   // --- HARD GATE: SW فقط زمانی مجاز است که چرخهٔ W2 قفل شده باشد
   // و زمان Hunter (seed) بعد از زمان قفل W2 همین چرخه باشد.
   if(!SWGate_UP_IsOpen()) return;
   if(!SW_UP_SeedActive()) return;
   if(w3_c1 < 0 || bodyBreakIdx < 0) return;
   if(SW_UP_SeedTime() < SWGate_UP_W2Time()) return; // Hunter باید بعد از قفل W2 باشد

   if(!g_sw_seed_u_active) return;
   if(w3_c1 < 0 || bodyBreakIdx < 0)    return;
   if(rates[w3_c1].time < g_sw_seed_u_xtime) return; // باید بعد از Hunter باشد

   // شرط SW: کندل بریکِ W3 بالاتر از High(C1_Hunter) «با بدنه» بسته شود
   if(rates[bodyBreakIdx].close > g_sw_seed_u_level)
   {
      ++g_sw_counter_u;
      string tag = IntegerToString(g_sw_counter_u);

      if(InpDrawMarkers)
      {
         MarkV("SW_"+tag+"_C1", rates[w3_c1].time,    clrAqua);
         MarkV("SW_"+tag+"_B" , rates[bodyBreakIdx].time, clrCyan);
      }

      if(InpDebugPrints)
         Print("[SW-UP] OK | W3_C1=",T(rates[w3_c1].time),
               " | BODY-BREAK=",T(rates[bodyBreakIdx].time),
               " | > H(HW_C1)=",DoubleToString(g_sw_seed_u_level,_Digits));

      g_sw_seed_u_active = false; // بذر مصرف شد
   }
   
   SWGate_UP_OnPairFinalized();
}

#endif // WAVEBOT_HUNTER_MQH
