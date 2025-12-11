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
   const string name = __ScanPrefix() + base;
   if(ObjectFind(0, name) != -1) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_VLINE, 0, t, 0);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASHDOT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
}
inline void __SB_DrawTempC1(const string base, const datetime t)
{
   const string name = __ScanPrefix() + base;
   if(ObjectFind(0, name) != -1) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_VLINE, 0, t, 0);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrSkyBlue);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
}
inline void __SB_DrawInvalidator(const string base, const datetime t)
{
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

// هر prefix (برگشتی از __ScanPrefix) یک اسلات مستقل دارد
struct SB_UP_State
{
   bool     used;
   string   prefix;

   datetime seed_time;
   double   level;

   bool     sb_marked;
   int      counter;          // شمارندهٔ داخلی این context
   int      serial_current;   // شمارهٔ SB فعلی همین context
   int      temp_idx;
   double   temp_level;
   bool     watch_active;
   bool     inval_done;

   datetime time_sb;
   datetime time_temp;
   datetime time_inval;
};

// آرایهٔ اسلات‌ها برای همهٔ contextها (MAJOR / MINOR / …)
static SB_UP_State g_sb_up_states[];

// شمارندهٔ سراسری فقط برای یکتاسازی نام (در صورت نیاز)
static int g_sb_up_global_counter = 0;

// --- reset یک اسلات ---
inline void __SB_UP_ResetState(SB_UP_State &S)
{
   S.seed_time      = 0;
   S.level          = 0.0;
   S.sb_marked      = false;
   S.watch_active   = false;
   S.inval_done     = false;
   S.temp_idx       = -1;
   S.temp_level     = 0.0;
   S.serial_current = 0;
   S.time_sb        = 0;
   S.time_temp      = 0;
   S.time_inval     = 0;
}

// --- پیدا کردن اسلات بر اساس prefix ---
inline int __SB_UP_FindSlot(const string prefix)
{
   const int count = ArraySize(g_sb_up_states);
   for(int i = 0; i < count; ++i)
   {
      if(!g_sb_up_states[i].used) continue;
      if(g_sb_up_states[i].prefix == prefix)
         return i;
   }
   return -1;
}

// --- گرفتن یا ساختن اسلات برای context فعلی ---
inline int __SB_UP_EnsureSlot()
{
   const string prefix = __ScanPrefix();
   int idx = __SB_UP_FindSlot(prefix);
   if(idx >= 0)
      return idx;

   int count = ArraySize(g_sb_up_states);
   ArrayResize(g_sb_up_states, count + 1);
   idx = count;

   g_sb_up_states[idx].used   = true;
   g_sb_up_states[idx].prefix = prefix;
   g_sb_up_states[idx].counter= 0;
   __SB_UP_ResetState(g_sb_up_states[idx]);
   return idx;
}

// --- Reset عمومی برای context فعلی (همان SB_UP_Reset قدیمی، ولی context-based) ---
inline void SB_UP_Reset()
{
   int idx = __SB_UP_EnsureSlot();
   __SB_UP_ResetState(g_sb_up_states[idx]);
}

// --- Sync با Seed فعلی SW (برای context فعلی) ---
inline void SB_UP_SyncWithSeed()
{
   const int idx = __SB_UP_EnsureSlot();
   SB_UP_State S = g_sb_up_states[idx];

   // SW باید در همان چرخه پس از قفل W2 باشد
   if(!SW_UP_SeedActive() || !SWGate_UP_IsOpen() || SW_UP_SeedTime() < SWGate_UP_W2Time())
   {
      __SB_UP_ResetState(S);
      return;
   }

   const datetime st = SW_UP_SeedTime();
   if(st != S.seed_time)
   {
      __SB_UP_ResetState(S);
      S.seed_time = st;
      S.level     = SW_UP_Level();
   }
}

// --- اولویت‌دهی سه مارکر (بازرسم در انتهای کندل) برای context فعلی ---
inline void SB_UP_BringToFront()
{
   const int idx = __SB_UP_EnsureSlot();
   SB_UP_State S = g_sb_up_states[idx];

   if(!S.sb_marked) return;
   const string tag = IntegerToString(S.serial_current);
   if(S.time_sb > 0)
      __SB_DrawV("SHADOW_BREAK_U_" + tag, S.time_sb, clrGold);
   if(S.time_temp > 0)
      __SB_DrawTempC1("temp-c1-sw_u_" + tag, S.time_temp);
   if(S.inval_done && S.time_inval > 0)
      __SB_DrawInvalidator("invalidator_u_" + tag, S.time_inval);
}

// --- نسخهٔ context-based از منطق اصلی SB برای UP ---
inline void SB_UP_OnBarCtx(const MqlRates &rates[], const bool &insideHL[],
                           const int n, const int cend, const int j)
{
   const int idx = __SB_UP_EnsureSlot();
   SB_UP_State S = g_sb_up_states[idx];

   SB_UP_SyncWithSeed();             // با Seed فعلی همگام شو
   if(S.seed_time == 0) return;
   if(j < 0 || j >= n) return;

   const MqlRates r = rates[j];
   if(r.time < S.seed_time) return;

   // 1) اگر هنوز SB نداریم: شناسایی SB (wick-only)
   if(!S.sb_marked)
   {
      if(r.high > S.level && r.close <= S.level)
      {
         ++g_sb_up_global_counter;
         ++S.counter;
         S.sb_marked      = true;
         S.serial_current = S.counter;

         const string tag = IntegerToString(S.serial_current);

         // mark SB
         __SB_DrawV("SHADOW_BREAK_U_" + tag, r.time, clrGold);
         S.time_sb = r.time;

         // temp-c1-sw: کمترین Low در [cend..j] (با حذف insideHL)
         int from = (cend >= 0 ? cend : 0);
         if(from > j) from = j;
         S.temp_idx   = __SB_LeftmostMinLow_ExInside(rates, insideHL, from, j);
         S.temp_level = (S.temp_idx >= 0 && S.temp_idx < n ? rates[S.temp_idx].low : 0.0);

         if(S.temp_idx >= 0 && S.temp_idx < n)
         {
            __SB_DrawTempC1("temp-c1-sw_u_" + tag, rates[S.temp_idx].time);
            S.time_temp = rates[S.temp_idx].time;
         }

         // از لحظهٔ تشخیص SB ⇒ مسابقه HWBB متوقف و موج‌ها پاک‌سازی شوند (برای همین context)
         Race_InternalClearAll();
         Markers_Clear_Waves_CurrentScan();

         // از حالا تا قبل از body-break پایش invalidator فعال است
         S.watch_active = true;
         S.inval_done   = false;
      }
      return;
   }

   // 2) اگر SB داریم و هنوز SW تایید نشده، پایش invalidator
   if(S.watch_active && !S.inval_done)
   {
      // الف) تأیید SW با بدنه (close > level) ⇒ پایش متوقف
      if(r.close > S.level)
      {
         S.watch_active = false;
         return;
      }

      // ب) ابطال temp-c1-sw (wick/body زیر Low(temp)) ⇒ invalidator
      if(S.temp_idx >= 0 && (r.low < S.temp_level || r.close < S.temp_level))
      {
         __SB_DrawInvalidator("invalidator_u_" + IntegerToString(S.serial_current), r.time);
         S.time_inval   = r.time;
         S.inval_done   = true;
         S.watch_active = false;   // این سیکل تمام
      }
   }
}

// === Query helpers برای context فعلی (UP) ===
inline bool     SB_UP_InvalidatorReady()
{
   const int idx = __SB_UP_EnsureSlot();
   const SB_UP_State S = g_sb_up_states[idx];
   return S.inval_done;
}

inline datetime SB_UP_SBTime()
{
   const int idx = __SB_UP_EnsureSlot();
   const SB_UP_State S = g_sb_up_states[idx];
   return S.time_sb;
}

inline void     SB_UP_ClearCycle()
{
   SB_UP_Reset();
}

inline bool     SB_UP_BinaryPhaseActive()
{
   const int idx = __SB_UP_EnsureSlot();
   const SB_UP_State S = g_sb_up_states[idx];
   return (S.sb_marked && S.watch_active);
}

// ===================== DOWN =====================

struct SB_DN_State
{
   bool     used;
   string   prefix;

   datetime seed_time;
   double   level;

   bool     sb_marked;
   int      counter;
   int      serial_current;
   int      temp_idx;
   double   temp_level;
   bool     watch_active;
   bool     inval_done;

   datetime time_sb;
   datetime time_temp;
   datetime time_inval;
};

static SB_DN_State g_sb_dn_states[];
static int         g_sb_dn_global_counter = 0;

// --- reset یک اسلات DOWN ---
inline void __SB_DN_ResetState(SB_DN_State &S)
{
   S.seed_time      = 0;
   S.level          = 0.0;
   S.sb_marked      = false;
   S.watch_active   = false;
   S.inval_done     = false;
   S.temp_idx       = -1;
   S.temp_level     = 0.0;
   S.serial_current = 0;
   S.time_sb        = 0;
   S.time_temp      = 0;
   S.time_inval     = 0;
}

inline int __SB_DN_FindSlot(const string prefix)
{
   const int count = ArraySize(g_sb_dn_states);
   for(int i = 0; i < count; ++i)
   {
      if(!g_sb_dn_states[i].used) continue;
      if(g_sb_dn_states[i].prefix == prefix)
         return i;
   }
   return -1;
}

inline int __SB_DN_EnsureSlot()
{
   const string prefix = __ScanPrefix();
   int idx = __SB_DN_FindSlot(prefix);
   if(idx >= 0)
      return idx;

   int count = ArraySize(g_sb_dn_states);
   ArrayResize(g_sb_dn_states, count + 1);
   idx = count;

   g_sb_dn_states[idx].used   = true;
   g_sb_dn_states[idx].prefix = prefix;
   g_sb_dn_states[idx].counter= 0;
   __SB_DN_ResetState(g_sb_dn_states[idx]);
   return idx;
}

// Reset عمومی برای context فعلی (DOWN)
inline void SB_DN_Reset()
{
   int idx = __SB_DN_EnsureSlot();
   __SB_DN_ResetState(g_sb_dn_states[idx]);
}

// Sync با Seed فعلی SW-DOWN
inline void SB_DN_SyncWithSeed()
{
   const int idx = __SB_DN_EnsureSlot();
   SB_DN_State S = g_sb_dn_states[idx];

   if(!SW_DOWN_SeedActive() || !SWGate_DN_IsOpen() || SW_DOWN_SeedTime() < SWGate_DN_W2Time())
   {
      __SB_DN_ResetState(S);
      return;
   }

   const datetime st = SW_DOWN_SeedTime();
   if(st != S.seed_time)
   {
      __SB_DN_ResetState(S);
      S.seed_time = st;
      S.level     = SW_DOWN_Level();
   }
}

// اولویت‌دهی (بازرسم) برای context فعلی (DOWN)
inline void SB_DN_BringToFront()
{
   const int idx = __SB_DN_EnsureSlot();
   SB_DN_State S = g_sb_dn_states[idx];

   if(!S.sb_marked) return;
   const string tag = IntegerToString(S.serial_current);
   if(S.time_sb > 0)
      __SB_DrawV("SHADOW_BREAK_D_" + tag, S.time_sb, clrGold);
   if(S.time_temp > 0)
      __SB_DrawTempC1("temp-c1-sw_d_" + tag, S.time_temp);
   if(S.inval_done && S.time_inval > 0)
      __SB_DrawInvalidator("invalidator_d_" + tag, S.time_inval);
}

// نسخهٔ context-based منطق اصلی برای DOWN
inline void SB_DN_OnBarCtx(const MqlRates &rates[], const bool &insideHL[],
                           const int n, const int cend, const int j)
{
   const int idx = __SB_DN_EnsureSlot();
   SB_DN_State S = g_sb_dn_states[idx];

   SB_DN_SyncWithSeed();
   if(S.seed_time == 0) return;
   if(j < 0 || j >= n) return;

   const MqlRates r = rates[j];
   if(r.time < S.seed_time) return;

   // 1) اگر هنوز SB نداریم: شناسایی SB (wick-only)
   if(!S.sb_marked)
   {
      if(r.low < S.level && r.close >= S.level)
      {
         ++g_sb_dn_global_counter;
         ++S.counter;
         S.sb_marked      = true;
         S.serial_current = S.counter;

         const string tag = IntegerToString(S.serial_current);

         __SB_DrawV("SHADOW_BREAK_D_" + tag, r.time, clrGold);
         S.time_sb = r.time;

         int from = (cend >= 0 ? cend : 0);
         if(from > j) from = j;
         S.temp_idx   = __SB_LeftmostMaxHigh_ExInside(rates, insideHL, from, j);
         S.temp_level = (S.temp_idx >= 0 && S.temp_idx < n ? rates[S.temp_idx].high : 0.0);

         if(S.temp_idx >= 0 && S.temp_idx < n)
         {
            __SB_DrawTempC1("temp-c1-sw_d_" + tag, rates[S.temp_idx].time);
            S.time_temp = rates[S.temp_idx].time;
         }

         // NEW: از لحظهٔ تشخیص SB ⇒ مسابقه HWBB متوقف و موج‌ها پاک‌سازی شوند
         Race_InternalClearAll();
         Markers_Clear_Waves_CurrentScan();

         S.watch_active = true;
         S.inval_done   = false;
      }
      return;
   }

   // 2) پایش invalidator برای DOWN
   if(S.watch_active && !S.inval_done)
   {
      // الف) تأیید SW با بدنه (close < level) ⇒ پایش متوقف
      if(r.close < S.level)
      {
         S.watch_active = false;
         return;
      }

      // ب) ابطال temp-c1-sw (wick/body بالاتر از High(temp)) ⇒ invalidator
      if(S.temp_idx >= 0 && (r.high > S.temp_level || r.close > S.temp_level))
      {
         __SB_DrawInvalidator("invalidator_d_" + IntegerToString(S.serial_current), r.time);
         S.time_inval   = r.time;
         S.inval_done   = true;
         S.watch_active = false;
      }
   }
}

// Query helpers برای context فعلی (DOWN)
inline bool     SB_DN_InvalidatorReady()
{
   const int idx = __SB_DN_EnsureSlot();
   const SB_DN_State S = g_sb_dn_states[idx];
   return S.inval_done;
}

inline datetime SB_DN_SBTime()
{
   const int idx = __SB_DN_EnsureSlot();
   const SB_DN_State S = g_sb_dn_states[idx];
   return S.time_sb;
}

inline void     SB_DN_ClearCycle()
{
   SB_DN_Reset();
}

inline bool     SB_DN_BinaryPhaseActive()
{
   const int idx = __SB_DN_EnsureSlot();
   const SB_DN_State S = g_sb_dn_states[idx];
   return (S.sb_marked && S.watch_active);
}

#endif // WAVEBOT_SHADOWBREAKER_MQH
