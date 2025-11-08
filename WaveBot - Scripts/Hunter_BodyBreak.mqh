#ifndef WAVEBOT_HUNTER_BODYBREAK_MQH
#define WAVEBOT_HUNTER_BODYBREAK_MQH

#include <WaveBot/Markers.mqh>
#include <WaveBot/ExtLQ.mqh>
#include <WaveBot/ExtLQ_Down.mqh>
#include <WaveBot/Hunter.mqh>       // برای دسترسی به SW_UP_Seed* (بذرهانتر معتبر)
#include <WaveBot/Hunter_Down.mqh>  // برای دسترسی به SW_DOWN_Seed*
#include <WaveBot/RaceCoordinator.mqh>
#include <WaveBot/ShadowBreaker.mqh>   // brings SB_*_BinaryPhaseActive definitions

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
inline void HW_BB_UP_OnBar(const MqlRates &r, const MqlRates &rates[], const int n, const int j)
{
   if(Race_IsLocked()) return;
   if(!ExtLQ_Has())    return;
   
   // --- NEW: بین SB و نتیجه، Path-B ممنوع است
   if(SB_UP_BinaryPhaseActive()) return;

   HW_BB_UP_ResetIfNewLQ();
   if(g_bb_done_u) return;

   // arm only after a valid Hunter (we read seed time/level from SW_UP seed)
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

   if(r.time < g_bb_cross_time_u) return;

   // 1) BODY close below (level may have been escalated by previous wicks)
   if(r.close < g_bb_level_u)
   {
      ++g_bb_counter_u;
      if(InpDrawMarkers) MarkV("HWBB_U_"+IntegerToString(g_bb_counter_u), r.time, clrRoyalBlue);

      // set ref for POSSIBLE MTC_DOWN (High of Hunter-UP C1) + draw ref history now
      Race_SetRefLevelForMTC_Down(SW_UP_Level());
      //Race_DrawRefHistory_Down(SW_UP_Level(), r.time);

      // start race from this bar (Mode=UP)
      Race_Start_UP(rates, n, j);

      // ---------------- SPECIAL CASE: active ref-up broken by THIS body close ----------------
      if(Race_RefUp_IsActive() && r.close < Race_ActiveRef_Up())
      {
         // 1) NEW: move ext lq (DOWN) to HIGH of the 1st candle of the offending Hunter-UP
         int      c1u   = SW_UP_C1Index();
         datetime c1u_t = (c1u>=0 && c1u<n ? rates[c1u].time : r.time);
         double   lq_dn = SW_UP_Level();               // High(C1 of Hunter-UP)
         ExtLQ_Down_Set(lq_dn, c1u_t);                 // draw/update ext lq (DOWN)
         Hunter_Down_OnExtLQUpdated();                 // reset hunter-DN state on new LQ
      
         // 2) announce immediate Path-B win with MTC_DOWN on this same candle
         Race_SpecialRefBreak_MTC_Down(rates, n, j);
      
         g_bb_done_u  = true;
         g_bb_armed_u = false;
         return;
      }

      // ---------------------------------------------------------------------------------------

      g_bb_done_u  = true;
      g_bb_armed_u = false;
      return;
   }

   // 2) wick-only pass ⇒ escalate level until we see the first body close beyond it
   if(r.low < g_bb_level_u)
      g_bb_level_u = r.low;
}

// -------------------------- DOWN: OnBar --------------------------
inline void HW_BB_DOWN_OnBar(const MqlRates &r, const MqlRates &rates[], const int n, const int j)
{
   if(Race_IsLocked()) return;
   if(!ExtLQ_Down_Has()) return;
   
   // --- NEW: بین SB و نتیجه، Path-B ممنوع است
   if(SB_DN_BinaryPhaseActive()) return;
   
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

      // set ref for POSSIBLE MTC_UP (Low of Hunter-DOWN C1) + draw ref history now
      Race_SetRefLevelForMTC_Up(SW_DOWN_Level());
      //Race_DrawRefHistory_Up(SW_DOWN_Level(), r.time);

      // start race from this bar (Mode=DOWN)
      Race_Start_DOWN(rates, n, j);

      // ---------------- SPECIAL CASE: active ref-down broken by THIS body close --------------
      if(Race_RefDown_IsActive() && r.close > Race_ActiveRef_Down())
      {
         // 1) NEW: move ext lq (UP) to LOW of the 1st candle of the offending Hunter-DOWN
         int      c1d   = SW_DOWN_C1Index();
         datetime c1d_t = (c1d>=0 && c1d<n ? rates[c1d].time : r.time);
         double   lq_up = SW_DOWN_Level();             // Low(C1 of Hunter-DOWN)
         ExtLQ_Set(lq_up, c1d_t);                      // draw/update ext lq (UP)
         Hunter_OnExtLQUpdated();                      // reset hunter-UP state on new LQ
      
         // 2) announce immediate Path-B win with MTC_UP on this same candle
         Race_SpecialRefBreak_MTC_Up(rates, n, j);
      
         g_bb_done_d  = true;
         g_bb_armed_d = false;
         return;
      }

      // ---------------------------------------------------------------------------------------

      g_bb_done_d  = true;
      g_bb_armed_d = false;
      return;
   }

   if(r.high > g_bb_level_d)
      g_bb_level_d = r.high;
}

#endif // WAVEBOT_HUNTER_BODYBREAK_MQH
