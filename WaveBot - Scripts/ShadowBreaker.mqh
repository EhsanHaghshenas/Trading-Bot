// ============================================================================
// WaveBot/ShadowBreaker.mqh

// WaveBot/ShadowBreaker.mqh
#ifndef WAVEBOT_SHADOWBREAKER_MQH
#define WAVEBOT_SHADOWBREAKER_MQH

#include <WaveBot/Markers.mqh>
#include <WaveBot/Hunter.mqh>        // SW_UP_* access
#include <WaveBot/Hunter_Down.mqh>   // SW_DOWN_* access
#include <WaveBot/SWGate.mqh>        // SWGate_* access

// ---------- drawing helpers ----------
inline void __SB_DrawV(const string base, const datetime t, const color col)
{
   if(!Markers_ShouldRender()) return;
   const string name = __ScanPrefix() + base;
   if(ObjectFind(0, name) != -1) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_VLINE, 0, t, 0);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASHDOT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
}
inline void __SB_DrawTempC1(const string base, const datetime t)
{
   if(!Markers_ShouldRender()) return;
   const string name = __ScanPrefix() + base;
   if(ObjectFind(0, name) != -1) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_VLINE, 0, t, 0);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrSkyBlue);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
}
inline void __SB_DrawInvalidator(const string base, const datetime t)
{
   if(!Markers_ShouldRender()) return;
   const string name = __ScanPrefix() + base;
   if(ObjectFind(0, name) != -1) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_VLINE, 0, t, 0);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
}

// ---------- local anchors ----------
inline int __SB_LeftmostMinLow_ExInside(const MqlRates &rates[], const bool &insideHL[],
                                        const int from, const int to)
{
   if(from>to) return -1;
   double mn = DBL_MAX; int idx = -1;
   for(int i=from; i<=to; ++i)
   {
      if(insideHL[i]) continue;
      const double l = rates[i].low;
      if(l < mn){ mn = l; idx = i; }
   }
   if(idx < 0) return from;
   return idx;
}
inline int __SB_LeftmostMaxHigh_ExInside(const MqlRates &rates[], const bool &insideHL[],
                                         const int from, const int to)
{
   if(from>to) return -1;
   double mx = -DBL_MAX; int idx = -1;
   for(int i=from; i<=to; ++i)
   {
      if(insideHL[i]) continue;
      const double h = rates[i].high;
      if(h > mx){ mx = h; idx = i; }
   }
   if(idx < 0) return from;
   return idx;
}

// ===================== UP =====================
static datetime g_sb_up_seed_time = 0;
static double   g_sb_up_level     = 0.0;

// SB/Temp/Invalidator state
static bool     g_sb_up_sb_marked      = false; // SB رسم شده؟
static int      g_sb_up_counter        = 0;     // شمارنده‌ی سری
static int      g_sb_up_serial_current = 0;     // سری همین SB
static int      g_sb_up_temp_idx       = -1;    // ایندکس temp-c1-sw
static double   g_sb_up_temp_level     = 0.0;   // Low(temp-c1-sw)
static bool     g_sb_up_watch_active   = false; // پایش فعال تا قبل از تأیید SW
static bool     g_sb_up_inval_done     = false; // invalidator رسم شد؟

// زمان‌های هر مارکر برای «BringToFront»
static datetime g_sb_up_time_sb    = 0;
static datetime g_sb_up_time_temp  = 0;
static datetime g_sb_up_time_inval = 0;

inline void SB_UP_Reset()
{
   g_sb_up_seed_time = 0;
   g_sb_up_level     = 0.0;
   g_sb_up_sb_marked = false;
   g_sb_up_watch_active = false;
   g_sb_up_inval_done   = false;
   g_sb_up_temp_idx     = -1;
   g_sb_up_temp_level   = 0.0;
   g_sb_up_serial_current = 0;
   g_sb_up_time_sb = g_sb_up_time_temp = g_sb_up_time_inval = 0;
}
inline void SB_UP_SyncWithSeed()
{
   // SW باید در همان چرخه پس از قفل W2 باشد
   if(!SW_UP_SeedActive() || !SWGate_UP_IsOpen() || SW_UP_SeedTime() < SWGate_UP_W2Time())
   { SB_UP_Reset(); return; }

   const datetime st = SW_UP_SeedTime();
   if(st != g_sb_up_seed_time)
   {
      SB_UP_Reset();
      g_sb_up_seed_time = st;
      g_sb_up_level     = SW_UP_Level();
   }
}

// اولویت‌دهیِ سه مارکر (بازرسم در انتهای کندل)
inline void SB_UP_BringToFront()
{
   if(!g_sb_up_sb_marked) return;
   const string tag = IntegerToString(g_sb_up_serial_current);
   if(g_sb_up_time_sb>0)
      __SB_DrawV("SHADOW_BREAK_U_" + tag, g_sb_up_time_sb, clrGold);
   if(g_sb_up_time_temp>0)
      __SB_DrawTempC1("temp-c1-sw_u_" + tag, g_sb_up_time_temp);
   if(g_sb_up_inval_done && g_sb_up_time_inval>0)
      __SB_DrawInvalidator("invalidator_u_" + tag, g_sb_up_time_inval);
}

// نسخه‌ی دارای کانتکست: SB + temp-c1-sw + invalidator
inline void SB_UP_OnBarCtx(const MqlRates &rates[], const bool &insideHL[],
                           const int n, const int cend, const int j)
{
   SB_UP_SyncWithSeed();
   if(g_sb_up_seed_time == 0) return;
   if(j<0 || j>=n) return;
   const MqlRates r = rates[j];
   if(r.time < g_sb_up_seed_time) return;

   // 1) اگر هنوز SB نداریم: شناسایی SB (wick-only)
   if(!g_sb_up_sb_marked)
   {
      if(r.high > g_sb_up_level && r.close <= g_sb_up_level)
      {
         ++g_sb_up_counter;
         g_sb_up_sb_marked      = true;
         g_sb_up_serial_current = g_sb_up_counter;

         // mark SB
         __SB_DrawV("SHADOW_BREAK_U_" + IntegerToString(g_sb_up_serial_current), r.time, clrGold);
         g_sb_up_time_sb = r.time;

         // temp-c1-sw: کمترین Low در [cend..j]
         int from = (cend>=0 ? cend : 0); if(from>j) from=j;
         g_sb_up_temp_idx   = __SB_LeftmostMinLow_ExInside(rates, insideHL, from, j);
         g_sb_up_temp_level = (g_sb_up_temp_idx>=0 && g_sb_up_temp_idx<n ? rates[g_sb_up_temp_idx].low : 0.0);
         if(g_sb_up_temp_idx>=0 && g_sb_up_temp_idx<n)
         {
            __SB_DrawTempC1("temp-c1-sw_u_" + IntegerToString(g_sb_up_serial_current), rates[g_sb_up_temp_idx].time);
            g_sb_up_time_temp = rates[g_sb_up_temp_idx].time;
         }
         
         // --- NEW: از لحظه تشخیص SB ⇒ مسابقه HWBB متوقف و موج‌ها پاک‌سازی شوند
         Race_InternalClearAll();          // توقف کامل مسابقه/Path-B (قفل و ref و ... ریست)
         Markers_Clear_Waves_CurrentScan(); // حذف مارکرهای W2/W3/HW/HWBB/SW همین اسکن

         // از حالا تا قبل از body-break پایش invalidator فعال است
         g_sb_up_watch_active = true;
         g_sb_up_inval_done   = false;
      }
      return;
   }

   // 2) اگر SB داریم و هنوز SW تایید نشده، پایش invalidator
   if(g_sb_up_watch_active && !g_sb_up_inval_done)
   {
      // الف) تأیید SW با بدنه (close > level) ⇒ پایش متوقف
      if(r.close > g_sb_up_level)
      {
         g_sb_up_watch_active = false;
         return;
      }
      // ب) ابطال temp-c1-sw (wick/body زیر Low(temp)) ⇒ invalidator
      if(g_sb_up_temp_idx>=0 && (r.low < g_sb_up_temp_level || r.close < g_sb_up_temp_level))
      {
         __SB_DrawInvalidator("invalidator_u_" + IntegerToString(g_sb_up_serial_current), r.time);
         g_sb_up_time_inval  = r.time;
         g_sb_up_inval_done  = true;
         g_sb_up_watch_active= false;   // این سیکل تمام
      }
   }   
}

// === Query helpers for external modules (UP) ===
inline bool     SB_UP_InvalidatorReady(){ return g_sb_up_inval_done; }
inline datetime SB_UP_SBTime()          { return g_sb_up_time_sb;    }
inline void     SB_UP_ClearCycle()      { SB_UP_Reset();             }
inline bool     SB_UP_BinaryPhaseActive(){ return (g_sb_up_sb_marked && g_sb_up_watch_active); }

// ===================== DOWN =====================
static datetime g_sb_dn_seed_time = 0;
static double   g_sb_dn_level     = 0.0;

static bool     g_sb_dn_sb_marked      = false;
static int      g_sb_dn_counter        = 0;
static int      g_sb_dn_serial_current = 0;
static int      g_sb_dn_temp_idx       = -1;
static double   g_sb_dn_temp_level     = 0.0;   // High(temp-c1-sw)
static bool     g_sb_dn_watch_active   = false;
static bool     g_sb_dn_inval_done     = false;

static datetime g_sb_dn_time_sb    = 0;
static datetime g_sb_dn_time_temp  = 0;
static datetime g_sb_dn_time_inval = 0;
// ------------------------------
// Context snapshot for ShadowBreaker (UP + DOWN)
// ------------------------------
struct SBContext
{
   // ===== UP state =====
   datetime sb_up_seed_time;
   double   sb_up_level;

   bool     sb_up_sb_marked;
   int      sb_up_counter;
   int      sb_up_serial_current;
   int      sb_up_temp_idx;
   double   sb_up_temp_level;
   bool     sb_up_watch_active;
   bool     sb_up_inval_done;

   datetime sb_up_time_sb;
   datetime sb_up_time_temp;
   datetime sb_up_time_inval;

   // ===== DOWN state =====
   datetime sb_dn_seed_time;
   double   sb_dn_level;

   bool     sb_dn_sb_marked;
   int      sb_dn_counter;
   int      sb_dn_serial_current;
   int      sb_dn_temp_idx;
   double   sb_dn_temp_level;
   bool     sb_dn_watch_active;
   bool     sb_dn_inval_done;

   datetime sb_dn_time_sb;
   datetime sb_dn_time_temp;
   datetime sb_dn_time_inval;
};

// مقداردهی اولیهٔ یک کانتکست خالی (برای ساخت world جدید: ماژور/مینور)
inline void SB_ContextInit(SBContext &ctx)
{
   // UP
   ctx.sb_up_seed_time      = 0;
   ctx.sb_up_level          = 0.0;
   ctx.sb_up_sb_marked      = false;
   ctx.sb_up_counter        = 0;
   ctx.sb_up_serial_current = 0;
   ctx.sb_up_temp_idx       = -1;
   ctx.sb_up_temp_level     = 0.0;
   ctx.sb_up_watch_active   = false;
   ctx.sb_up_inval_done     = false;
   ctx.sb_up_time_sb        = 0;
   ctx.sb_up_time_temp      = 0;
   ctx.sb_up_time_inval     = 0;

   // DOWN
   ctx.sb_dn_seed_time      = 0;
   ctx.sb_dn_level          = 0.0;
   ctx.sb_dn_sb_marked      = false;
   ctx.sb_dn_counter        = 0;
   ctx.sb_dn_serial_current = 0;
   ctx.sb_dn_temp_idx       = -1;
   ctx.sb_dn_temp_level     = 0.0;
   ctx.sb_dn_watch_active   = false;
   ctx.sb_dn_inval_done     = false;
   ctx.sb_dn_time_sb        = 0;
   ctx.sb_dn_time_temp      = 0;
   ctx.sb_dn_time_inval     = 0;
}

// Export: کپی وضعیت فعلی globalها به داخل کانتکست
inline void SB_ContextExport(SBContext &ctx)
{
   // UP
   ctx.sb_up_seed_time      = g_sb_up_seed_time;
   ctx.sb_up_level          = g_sb_up_level;
   ctx.sb_up_sb_marked      = g_sb_up_sb_marked;
   ctx.sb_up_counter        = g_sb_up_counter;
   ctx.sb_up_serial_current = g_sb_up_serial_current;
   ctx.sb_up_temp_idx       = g_sb_up_temp_idx;
   ctx.sb_up_temp_level     = g_sb_up_temp_level;
   ctx.sb_up_watch_active   = g_sb_up_watch_active;
   ctx.sb_up_inval_done     = g_sb_up_inval_done;
   ctx.sb_up_time_sb        = g_sb_up_time_sb;
   ctx.sb_up_time_temp      = g_sb_up_time_temp;
   ctx.sb_up_time_inval     = g_sb_up_time_inval;

   // DOWN
   ctx.sb_dn_seed_time      = g_sb_dn_seed_time;
   ctx.sb_dn_level          = g_sb_dn_level;
   ctx.sb_dn_sb_marked      = g_sb_dn_sb_marked;
   ctx.sb_dn_counter        = g_sb_dn_counter;
   ctx.sb_dn_serial_current = g_sb_dn_serial_current;
   ctx.sb_dn_temp_idx       = g_sb_dn_temp_idx;
   ctx.sb_dn_temp_level     = g_sb_dn_temp_level;
   ctx.sb_dn_watch_active   = g_sb_dn_watch_active;
   ctx.sb_dn_inval_done     = g_sb_dn_inval_done;
   ctx.sb_dn_time_sb        = g_sb_dn_time_sb;
   ctx.sb_dn_time_temp      = g_sb_dn_time_temp;
   ctx.sb_dn_time_inval     = g_sb_dn_time_inval;
}

// Import: برگرداندن وضعیت ذخیره‌شدهٔ کانتکست به متغیرهای global
inline void SB_ContextImport(const SBContext &ctx)
{
   // UP
   g_sb_up_seed_time      = ctx.sb_up_seed_time;
   g_sb_up_level          = ctx.sb_up_level;
   g_sb_up_sb_marked      = ctx.sb_up_sb_marked;
   g_sb_up_counter        = ctx.sb_up_counter;
   g_sb_up_serial_current = ctx.sb_up_serial_current;
   g_sb_up_temp_idx       = ctx.sb_up_temp_idx;
   g_sb_up_temp_level     = ctx.sb_up_temp_level;
   g_sb_up_watch_active   = ctx.sb_up_watch_active;
   g_sb_up_inval_done     = ctx.sb_up_inval_done;
   g_sb_up_time_sb        = ctx.sb_up_time_sb;
   g_sb_up_time_temp      = ctx.sb_up_time_temp;
   g_sb_up_time_inval     = ctx.sb_up_time_inval;

   // DOWN
   g_sb_dn_seed_time      = ctx.sb_dn_seed_time;
   g_sb_dn_level          = ctx.sb_dn_level;
   g_sb_dn_sb_marked      = ctx.sb_dn_sb_marked;
   g_sb_dn_counter        = ctx.sb_dn_counter;
   g_sb_dn_serial_current = ctx.sb_dn_serial_current;
   g_sb_dn_temp_idx       = ctx.sb_dn_temp_idx;
   g_sb_dn_temp_level     = ctx.sb_dn_temp_level;
   g_sb_dn_watch_active   = ctx.sb_dn_watch_active;
   g_sb_dn_inval_done     = ctx.sb_dn_inval_done;
   g_sb_dn_time_sb        = ctx.sb_dn_time_sb;
   g_sb_dn_time_temp      = ctx.sb_dn_time_temp;
   g_sb_dn_time_inval     = ctx.sb_dn_time_inval;
}

// ریست کامل وضعیت ShadowBreaker در world فعلی
inline void SB_ResetGlobals()
{
   // UP
   g_sb_up_seed_time      = 0;
   g_sb_up_level          = 0.0;
   g_sb_up_sb_marked      = false;
   g_sb_up_counter        = 0;
   g_sb_up_serial_current = 0;
   g_sb_up_temp_idx       = -1;
   g_sb_up_temp_level     = 0.0;
   g_sb_up_watch_active   = false;
   g_sb_up_inval_done     = false;
   g_sb_up_time_sb        = 0;
   g_sb_up_time_temp      = 0;
   g_sb_up_time_inval     = 0;

   // DOWN
   g_sb_dn_seed_time      = 0;
   g_sb_dn_level          = 0.0;
   g_sb_dn_sb_marked      = false;
   g_sb_dn_counter        = 0;
   g_sb_dn_serial_current = 0;
   g_sb_dn_temp_idx       = -1;
   g_sb_dn_temp_level     = 0.0;
   g_sb_dn_watch_active   = false;
   g_sb_dn_inval_done     = false;
   g_sb_dn_time_sb        = 0;
   g_sb_dn_time_temp      = 0;
   g_sb_dn_time_inval     = 0;
}

inline void SB_DN_Reset()
{
   g_sb_dn_seed_time = 0;
   g_sb_dn_level     = 0.0;
   g_sb_dn_sb_marked = false;
   g_sb_dn_watch_active = false;
   g_sb_dn_inval_done   = false;
   g_sb_dn_temp_idx     = -1;
   g_sb_dn_temp_level   = 0.0;
   g_sb_dn_serial_current = 0;
   g_sb_dn_time_sb = g_sb_dn_time_temp = g_sb_dn_time_inval = 0;
}
inline void SB_DN_SyncWithSeed()
{
   if(!SW_DOWN_SeedActive() || !SWGate_DN_IsOpen() || SW_DOWN_SeedTime() < SWGate_DN_W2Time())
   { SB_DN_Reset(); return; }

   const datetime st = SW_DOWN_SeedTime();
   if(st != g_sb_dn_seed_time)
   {
      SB_DN_Reset();
      g_sb_dn_seed_time = st;
      g_sb_dn_level     = SW_DOWN_Level();
   }
}

// اولویت‌دهی (بازرسم) برای DOWN
inline void SB_DN_BringToFront()
{
   if(!g_sb_dn_sb_marked) return;
   const string tag = IntegerToString(g_sb_dn_serial_current);
   if(g_sb_dn_time_sb>0)
      __SB_DrawV("SHADOW_BREAK_D_" + tag, g_sb_dn_time_sb, clrGold);
   if(g_sb_dn_time_temp>0)
      __SB_DrawTempC1("temp-c1-sw_d_" + tag, g_sb_dn_time_temp);
   if(g_sb_dn_inval_done && g_sb_dn_time_inval>0)
      __SB_DrawInvalidator("invalidator_d_" + tag, g_sb_dn_time_inval);
}

// نسخه‌ی دارای کانتکست: SB + temp-c1-sw + invalidator
inline void SB_DN_OnBarCtx(const MqlRates &rates[], const bool &insideHL[],
                           const int n, const int cend, const int j)
{
   SB_DN_SyncWithSeed();
   if(g_sb_dn_seed_time == 0) return;
   if(j<0 || j>=n) return;
   const MqlRates r = rates[j];
   if(r.time < g_sb_dn_seed_time) return;

   // 1) اگر هنوز SB نداریم: شناسایی SB (wick-only)
   if(!g_sb_dn_sb_marked)
   {
      if(r.low < g_sb_dn_level && r.close >= g_sb_dn_level)
      {
         ++g_sb_dn_counter;
         g_sb_dn_sb_marked      = true;
         g_sb_dn_serial_current = g_sb_dn_counter;

         __SB_DrawV("SHADOW_BREAK_D_" + IntegerToString(g_sb_dn_serial_current), r.time, clrGold);
         g_sb_dn_time_sb = r.time;

         int from = (cend>=0 ? cend : 0); if(from>j) from=j;
         g_sb_dn_temp_idx   = __SB_LeftmostMaxHigh_ExInside(rates, insideHL, from, j);
         g_sb_dn_temp_level = (g_sb_dn_temp_idx>=0 && g_sb_dn_temp_idx<n ? rates[g_sb_dn_temp_idx].high : 0.0);
         if(g_sb_dn_temp_idx>=0 && g_sb_dn_temp_idx<n)
         {
            __SB_DrawTempC1("temp-c1-sw_d_" + IntegerToString(g_sb_dn_serial_current), rates[g_sb_dn_temp_idx].time);
            g_sb_dn_time_temp = rates[g_sb_dn_temp_idx].time;
         }
         
         // --- NEW: از لحظه تشخیص SB ⇒ مسابقه HWBB متوقف و موج‌ها پاک‌سازی شوند
         Race_InternalClearAll();
         Markers_Clear_Waves_CurrentScan();

         g_sb_dn_watch_active = true;
         g_sb_dn_inval_done   = false;
      }
      return;
   }

   // 2) پایش invalidator تا قبل از تأیید SW
   if(g_sb_dn_watch_active && !g_sb_dn_inval_done)
   {
      // الف) تأیید SW با بدنه (close < level) ⇒ توقف پایش
      if(r.close < g_sb_dn_level)
      {
         g_sb_dn_watch_active = false;
         return;
      }
      // ب) ابطال temp-c1-sw (wick/body بالای High(temp))
      if(g_sb_dn_temp_idx>=0 && (r.high > g_sb_dn_temp_level || r.close > g_sb_dn_temp_level))
      {
         __SB_DrawInvalidator("invalidator_d_" + IntegerToString(g_sb_dn_serial_current), r.time);
         g_sb_dn_time_inval  = r.time;
         g_sb_dn_inval_done  = true;
         g_sb_dn_watch_active= false;
      }
   }
}

// === Query helpers for external modules (DOWN) ===
inline bool     SB_DN_InvalidatorReady(){ return g_sb_dn_inval_done; }
inline datetime SB_DN_SBTime()          { return g_sb_dn_time_sb;    }
inline void     SB_DN_ClearCycle()      { SB_DN_Reset();             }
inline bool     SB_DN_BinaryPhaseActive(){ return (g_sb_dn_sb_marked && g_sb_dn_watch_active); }

#endif // WAVEBOT_SHADOWBREAKER_MQH
