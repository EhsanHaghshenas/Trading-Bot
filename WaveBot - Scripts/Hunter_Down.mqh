#ifndef WAVEBOT_HUNTER_DOWN_MQH
#define WAVEBOT_HUNTER_DOWN_MQH

#include <WaveBot/Markers.mqh>
#include <WaveBot/ExtLQ_Down.mqh>
#include <WaveBot/Utils.mqh>
#include <WaveBot/RaceCoordinator.mqh>
#include <WaveBot/SWGate.mqh>

// ---------------- Hunter (DOWN) state ----------------
static int      g_hw_counter_d     = 0;
static datetime g_lq_time_seen_d   = 0;
static bool     g_marked_for_lq_d  = false;

// ---------------- Strong Wave (DOWN) seed ----------------
static bool     g_sw_seed_d_active = false;
static int      g_sw_seed_d_c1     = -1;     // اندیس C1 هانتر
static datetime g_sw_seed_d_xtime  = 0;      // زمان کراس ext lq
static double   g_sw_seed_d_level  = 0.0;    // Low(C1 هانتر)
static int      g_sw_counter_d     = 0;

// ext lq جدید ثبت شد
inline void Hunter_Down_OnExtLQUpdated()
{
   // ریست وضعیت hunter برای ext lq جدید (سمت DOWN)
   g_lq_time_seen_d  = ExtLQ_Down_Has() ? ExtLQ_Down_Time() : 0;
   g_marked_for_lq_d = false;

   // --- NEW: اگر مسابقه قفل است و Mode=UP بوده، همین ext lq(DOWN) یعنی برنده مشخص شده
   if(ExtLQ_Down_Has())
      Race_TryUnlockOnNewLQ_Notify(DIR_DOWN, ExtLQ_Down_Time());
}

// عبور از ext lq (DOWN) ⇒ کراس به بالا (بدنه یا شدو)
inline bool Hunter_Down_IsExtLQCross(const MqlRates &r)
{
   if(!ExtLQ_Down_Has()) return false;
   const double lq = ExtLQ_Down_Get();
   return (r.high >= lq || r.close > lq);
}

// ابطال Hunter قبل از کراس: اگر تا پیش از کراس، Low < Low(C1) شود ⇒ Hunter نامعتبر
inline bool Hunter_IsC1Invalidated_BeforeCross_DOWN(const MqlRates &rates[], const int n,
                                                    const int c1_index, const int cross_idx)
{
   if(c1_index < 0 || cross_idx < 0 || c1_index >= n || cross_idx >= n) return true;
   if(cross_idx <= c1_index) return true;

   const double lC1 = rates[c1_index].low;
   for(int i=c1_index+1; i<cross_idx; ++i)
      if(rates[i].low < lC1) return true;

   return false;
}

// فعال‌سازی بذر SW پس از Hunter معتبر
inline void SW_DOWN_ActivateSeed(const MqlRates &rates[], const int n,
                                 const int c1_index, const int cross_idx)
{
   g_sw_seed_d_active = true;
   g_sw_seed_d_c1     = c1_index;
   g_sw_seed_d_xtime  = rates[cross_idx].time;
   g_sw_seed_d_level  = rates[c1_index].low;
}

// دسترسی به بذر SW-DOWN
inline bool     SW_DOWN_SeedActive()      { return g_sw_seed_d_active; }
inline double   SW_DOWN_Level()           { return g_sw_seed_d_level;  }
inline datetime SW_DOWN_SeedTime()        { return g_sw_seed_d_xtime;  }
inline void     SW_DOWN_ClearSeed()       { g_sw_seed_d_active=false;  }

// ثبت Hunter در لحظه‌ی «کراس»
inline void Hunter_Down_TryMarkIfValid(const MqlRates &rates[], const int n,
                                       const int c1_index, const int cross_idx)
{
   if(!ExtLQ_Down_Has()) return;

   const datetime lqt = ExtLQ_Down_Time();
   if(lqt != g_lq_time_seen_d){ g_lq_time_seen_d = lqt; g_marked_for_lq_d = false; }
   if(g_marked_for_lq_d) return;

   if(Hunter_IsC1Invalidated_BeforeCross_DOWN(rates, n, c1_index, cross_idx))
      return;

   ++g_hw_counter_d;
   string tag = IntegerToString(g_hw_counter_d);

   if(InpDrawMarkers)
   {
      MarkV("HW_"+tag+"_C1", rates[c1_index].time, clrViolet);
      MarkV("HW_"+tag+"_X",  rates[cross_idx].time, clrMagenta);
   }
   g_marked_for_lq_d = true;

   // بذر SW نزولی را فعال کن (Lowِ C1 هانتر)
   SW_DOWN_ActivateSeed(rates, n, c1_index, cross_idx);

   if(InpDebugPrints)
      Print("[Hunter-DOWN] OK | C1=",T(rates[c1_index].time),
            " | CROSS=",T(rates[cross_idx].time),
            " | ext lq=",DoubleToString(ExtLQ_Down_Get(),_Digits),
            " | SW seed Lvl(L)= ",DoubleToString(g_sw_seed_d_level,_Digits));
}

// هنگام تایید یک W3 نزولی، بررسی کن آیا شرایط SW برقرار است
inline void SW_DOWN_TryMarkOnConfirmedW3(const MqlRates &rates[], const int n,
                                         const int w3_c1, const int bodyBreakIdx)
{
   Race_OnSWConfirmed_DOWN(rates, n, w3_c1, bodyBreakIdx);
   
   if(!SWGate_DN_IsOpen()) return;
   if(!SW_DOWN_SeedActive()) return;
   if(w3_c1 < 0 || bodyBreakIdx < 0) return;
   if(SW_DOWN_SeedTime() < SWGate_DN_W2Time()) return;

   if(!g_sw_seed_d_active) return;
   if(w3_c1 < 0 || bodyBreakIdx < 0)     return;
   if(rates[w3_c1].time < g_sw_seed_d_xtime) return;

   // شرط SW: کندل بریکِ W3 پایین‌تر از Low(C1_Hunter) «با بدنه» بسته شود
   if(rates[bodyBreakIdx].close < g_sw_seed_d_level)
   {
      ++g_sw_counter_d;
      string tag = IntegerToString(g_sw_counter_d);

      if(InpDrawMarkers)
      {
         MarkV("SW_"+tag+"_C1", rates[w3_c1].time,    clrOrangeRed);
         MarkV("SW_"+tag+"_B" , rates[bodyBreakIdx].time, clrDarkOrange);
      }

      if(InpDebugPrints)
         Print("[SW-DOWN] OK | W3_C1=",T(rates[w3_c1].time),
               " | BODY-BREAK=",T(rates[bodyBreakIdx].time),
               " | < L(HW_C1)=",DoubleToString(g_sw_seed_d_level,_Digits));

      g_sw_seed_d_active = false; // بذر مصرف شد
   }
   
   SWGate_DN_OnPairFinalized();
}

#endif // WAVEBOT_HUNTER_DOWN_MQH
