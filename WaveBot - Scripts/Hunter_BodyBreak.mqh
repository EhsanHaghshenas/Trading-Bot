#ifndef WAVEBOT_HUNTER_BODYBREAK_MQH
#define WAVEBOT_HUNTER_BODYBREAK_MQH

#include <WaveBot/Markers.mqh>
#include <WaveBot/ExtLQ.mqh>
#include <WaveBot/ExtLQ_Down.mqh>
#include <WaveBot/Hunter.mqh>       // برای دسترسی به SW_UP_Seed* (بذرهانتر معتبر)
#include <WaveBot/Hunter_Down.mqh>  // برای دسترسی به SW_DOWN_Seed*
#include <WaveBot/RaceCoordinator.mqh>
#include <WaveBot/FSMS_Lifecycle.mqh>
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

// -------------------- Context for Hunter_BodyBreak (UP + DOWN) --------------------
struct HWBBContext
{
   // UP side
   datetime bb_lq_time_u;      // ext lq فعال (UP) - زمان
   bool     bb_done_u;         // آیا برای این LQ مارک زده‌ایم؟
   bool     bb_armed_u;        // بازوگذاری پس از Hunter معتبر
   double   bb_level_u;        // سطح جاریِ شکست با بدنه (ارتقاپذیر)
   datetime bb_cross_time_u;   // از این زمان به بعد پایش می‌کنیم
   int      bb_counter_u;      // شمارنده‌ی مارکرها (UP)

   // DOWN side
   datetime bb_lq_time_d;      // ext lq فعال (DOWN) - زمان
   bool     bb_done_d;
   bool     bb_armed_d;
   double   bb_level_d;
   datetime bb_cross_time_d;
   int      bb_counter_d;      // شمارنده‌ی مارکرها (DOWN)
};

// مقداردهی اولیهٔ یک کانتکست خالی (برای شروع دنیای ماژور/مینور)
inline void HW_BB_ContextInit(HWBBContext &ctx)
{
   // UP
   ctx.bb_lq_time_u    = 0;
   ctx.bb_done_u       = false;
   ctx.bb_armed_u      = false;
   ctx.bb_level_u      = 0.0;
   ctx.bb_cross_time_u = 0;
   ctx.bb_counter_u    = 0;

   // DOWN
   ctx.bb_lq_time_d    = 0;
   ctx.bb_done_d       = false;
   ctx.bb_armed_d      = false;
   ctx.bb_level_d      = 0.0;
   ctx.bb_cross_time_d = 0;
   ctx.bb_counter_d    = 0;
}

// Export: کپی‌کردن وضعیت فعلی globalها به داخل کانتکست (برای ذخیره‌ی world فعلی)
inline void HW_BB_ContextExport(HWBBContext &ctx)
{
   // UP
   ctx.bb_lq_time_u    = g_bb_lq_time_u;
   ctx.bb_done_u       = g_bb_done_u;
   ctx.bb_armed_u      = g_bb_armed_u;
   ctx.bb_level_u      = g_bb_level_u;
   ctx.bb_cross_time_u = g_bb_cross_time_u;
   ctx.bb_counter_u    = g_bb_counter_u;

   // DOWN
   ctx.bb_lq_time_d    = g_bb_lq_time_d;
   ctx.bb_done_d       = g_bb_done_d;
   ctx.bb_armed_d      = g_bb_armed_d;
   ctx.bb_level_d      = g_bb_level_d;
   ctx.bb_cross_time_d = g_bb_cross_time_d;
   ctx.bb_counter_d    = g_bb_counter_d;
}

// Import: برگرداندن وضعیت ذخیره‌شده‌ی یک کانتکست به globalها (برای سوییچ world)
inline void HW_BB_ContextImport(const HWBBContext &ctx)
{
   // UP
   g_bb_lq_time_u    = ctx.bb_lq_time_u;
   g_bb_done_u       = ctx.bb_done_u;
   g_bb_armed_u      = ctx.bb_armed_u;
   g_bb_level_u      = ctx.bb_level_u;
   g_bb_cross_time_u = ctx.bb_cross_time_u;
   g_bb_counter_u    = ctx.bb_counter_u;

   // DOWN
   g_bb_lq_time_d    = ctx.bb_lq_time_d;
   g_bb_done_d       = ctx.bb_done_d;
   g_bb_armed_d      = ctx.bb_armed_d;
   g_bb_level_d      = ctx.bb_level_d;
   g_bb_cross_time_d = ctx.bb_cross_time_d;
   g_bb_counter_d    = ctx.bb_counter_d;
}

// ریست‌کردن خود globalها (مثلاً برای شروع یک ریس جدید در همان کانتکست فعال)
inline void HW_BB_ResetGlobals()
{
   // UP
   g_bb_lq_time_u    = 0;
   g_bb_done_u       = false;
   g_bb_armed_u      = false;
   g_bb_level_u      = 0.0;
   g_bb_cross_time_u = 0;
   g_bb_counter_u    = 0;

   // DOWN
   g_bb_lq_time_d    = 0;
   g_bb_done_d       = false;
   g_bb_armed_d      = false;
   g_bb_level_d      = 0.0;
   g_bb_cross_time_d = 0;
   g_bb_counter_d    = 0;
}

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
   // HWBB فقط وقتی مجاز است که بذر Hunter متعلق به همین چرخه‌ی W2 و همین ext lq باشد.
   if(!SWGate_UP_IsOpen())
   {
      g_bb_armed_u = false;
      return;
   }
   if(!SW_UP_SeedActive())
   {
      g_bb_armed_u = false;
      return;
   }
   if(SW_UP_SeedTime() < SWGate_UP_W2Time() || SW_UP_SeedTime() < g_bb_lq_time_u)
   {
      g_bb_armed_u = false;
      return;
   }

   if(!g_bb_armed_u)
   {
      g_bb_armed_u      = true;
      g_bb_level_u      = ExtLQ_Get();
      g_bb_cross_time_u = SW_UP_SeedTime();
   }

   if(r.time < g_bb_cross_time_u) return;

   // 1) BODY close below (level may have been escalated by previous wicks)
   if(r.close < g_bb_level_u)
   {
      ++g_bb_counter_u;
      if(InpDrawMarkers) MarkV("HWBB_U_"+IntegerToString(g_bb_counter_u), r.time, clrRoyalBlue);
      bool __m15new_hwbb_up_ok = M15NewMarker_OnTarget(DIR_UP, WB_M15NEW_TARGET_HWBB, rates, n, j);
      Trigger_M1LocalGateRegister(DIR_UP, WB15_KIND_START_HWBB, rates, n, j, SW_UP_C1Index());

      FSMSLC_RequestTerminal(FSMSLC_TERM_HWBB, r.time);

      // M15->M1 Stage-1 is now exclusive to FSMS/HWX/HWBB candles tagged "new".
      if(__m15new_hwbb_up_ok)
         WB15_PublishStartHWBB(InpSymbol, DIR_UP, r.time, g_bb_level_u, g_bb_cross_time_u);

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

   // HWBB فقط وقتی مجاز است که بذر Hunter متعلق به همین چرخه‌ی W2 و همین ext lq باشد.
   if(!SWGate_DN_IsOpen())
   {
      g_bb_armed_d = false;
      return;
   }
   if(!SW_DOWN_SeedActive())
   {
      g_bb_armed_d = false;
      return;
   }
   if(SW_DOWN_SeedTime() < SWGate_DN_W2Time() || SW_DOWN_SeedTime() < g_bb_lq_time_d)
   {
      g_bb_armed_d = false;
      return;
   }

   if(!g_bb_armed_d)
   {
      g_bb_armed_d      = true;
      g_bb_level_d      = ExtLQ_Down_Get();
      g_bb_cross_time_d = SW_DOWN_SeedTime();
   }

   if(r.time < g_bb_cross_time_d) return;

   if(r.close > g_bb_level_d)
   {
      ++g_bb_counter_d;
      if(InpDrawMarkers) MarkV("HWBB_D_"+IntegerToString(g_bb_counter_d), r.time, clrDarkOrange);
      bool __m15new_hwbb_dn_ok = M15NewMarker_OnTarget(DIR_DOWN, WB_M15NEW_TARGET_HWBB, rates, n, j);
      Trigger_M1LocalGateRegister(DIR_DOWN, WB15_KIND_START_HWBB, rates, n, j, SW_DOWN_C1Index());

      FSMSLC_RequestTerminal(FSMSLC_TERM_HWBB, r.time);

      // M15->M1 Stage-1 is now exclusive to FSMS/HWX/HWBB candles tagged "new".
      if(__m15new_hwbb_dn_ok)
         WB15_PublishStartHWBB(InpSymbol, DIR_DOWN, r.time, g_bb_level_d, g_bb_cross_time_d);

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

      g_bb_done_d  = true;
      g_bb_armed_d = false;
      return;
   }

   if(r.high > g_bb_level_d)
      g_bb_level_d = r.high;
}

#endif // WAVEBOT_HUNTER_BODYBREAK_MQH
