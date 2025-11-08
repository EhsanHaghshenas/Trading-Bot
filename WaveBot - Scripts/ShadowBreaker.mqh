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
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrSkyBlue); // تمایز با Gold
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
}

// ---------- local anchors (avoid name clash with API helpers) ----------
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
static bool     g_sb_up_done      = false;
static int      g_sb_up_counter   = 0;

inline void SB_UP_Reset()
{
   g_sb_up_seed_time = 0;
   g_sb_up_level     = 0.0;
   g_sb_up_done      = false;
}

inline void SB_UP_SyncWithSeed()
{
   // نیاز به بذر SW و گیتِ باز: Hunter باید بعد از قفل W2 باشد
   if(!SW_UP_SeedActive() || !SWGate_UP_IsOpen() || SW_UP_SeedTime() < SWGate_UP_W2Time())
   { SB_UP_Reset(); return; }

   const datetime st = SW_UP_SeedTime();
   if(st != g_sb_up_seed_time){ g_sb_up_seed_time = st; g_sb_up_level = SW_UP_Level(); g_sb_up_done = false; }
}

// نسخه قدیمی برای سازگاری (فقط Shadow Breaker را رسم می‌کند)
inline void SB_UP_OnBar(const MqlRates &r)
{
   SB_UP_SyncWithSeed();
   if(g_sb_up_seed_time == 0 || g_sb_up_done) return;
   if(r.time < g_sb_up_seed_time) return;

   if(r.high > g_sb_up_level)
   {
      if(r.close > g_sb_up_level){ g_sb_up_done = true; return; }
      ++g_sb_up_counter;
      __SB_DrawV("SHADOW_BREAK_U_" + IntegerToString(g_sb_up_counter), r.time, clrGold);
      g_sb_up_done = true;
   }
}

// نسخهٔ دارای کانتکست: همراه با Shadow Breaker، temp-c1-sw را هم نشان می‌دهد
inline void SB_UP_OnBarCtx(const MqlRates &rates[], const bool &insideHL[],
                           const int n, const int cend, const int j)
{
   SB_UP_SyncWithSeed();
   if(g_sb_up_seed_time == 0 || g_sb_up_done) return;
   if(j<0 || j>=n) return;
   const MqlRates r = rates[j];
   if(r.time < g_sb_up_seed_time) return;

   if(r.high > g_sb_up_level)
   {
      if(r.close > g_sb_up_level){ g_sb_up_done = true; return; }

      ++g_sb_up_counter;
      // 1) Shadow Breaker
      __SB_DrawV("SHADOW_BREAK_U_" + IntegerToString(g_sb_up_counter), r.time, clrGold);

      // 2) temp-c1-sw (کمترین Low از [cend..j] با اسکیپ inside)
      int from = (cend>=0 ? cend : 0);
      if(from > j) from = j;
      int c1idx = __SB_LeftmostMinLow_ExInside(rates, insideHL, from, j);
      if(c1idx>=0 && c1idx<n)
         __SB_DrawTempC1("temp-c1-sw_u_" + IntegerToString(g_sb_up_counter), rates[c1idx].time);

      g_sb_up_done = true;
   }
}

// ===================== DOWN =====================
static datetime g_sb_dn_seed_time = 0;
static double   g_sb_dn_level     = 0.0;
static bool     g_sb_dn_done      = false;
static int      g_sb_dn_counter   = 0;

inline void SB_DN_Reset()
{
   g_sb_dn_seed_time = 0;
   g_sb_dn_level     = 0.0;
   g_sb_dn_done      = false;
}

inline void SB_DN_SyncWithSeed()
{
   if(!SW_DOWN_SeedActive() || !SWGate_DN_IsOpen() || SW_DOWN_SeedTime() < SWGate_DN_W2Time())
   { SB_DN_Reset(); return; }

   const datetime st = SW_DOWN_SeedTime();
   if(st != g_sb_dn_seed_time){ g_sb_dn_seed_time = st; g_sb_dn_level = SW_DOWN_Level(); g_sb_dn_done = false; }
}

// نسخه قدیمی برای سازگاری
inline void SB_DN_OnBar(const MqlRates &r)
{
   SB_DN_SyncWithSeed();
   if(g_sb_dn_seed_time == 0 || g_sb_dn_done) return;
   if(r.time < g_sb_dn_seed_time) return;

   if(r.low < g_sb_dn_level)
   {
      if(r.close < g_sb_dn_level){ g_sb_dn_done = true; return; }
      ++g_sb_dn_counter;
      __SB_DrawV("SHADOW_BREAK_D_" + IntegerToString(g_sb_dn_counter), r.time, clrGold);
      g_sb_dn_done = true;
   }
}

// نسخهٔ دارای کانتکست: همراه با Shadow Breaker، temp-c1-sw را هم نشان می‌دهد
inline void SB_DN_OnBarCtx(const MqlRates &rates[], const bool &insideHL[],
                           const int n, const int cend, const int j)
{
   SB_DN_SyncWithSeed();
   if(g_sb_dn_seed_time == 0 || g_sb_dn_done) return;
   if(j<0 || j>=n) return;
   const MqlRates r = rates[j];
   if(r.time < g_sb_dn_seed_time) return;

   if(r.low < g_sb_dn_level)
   {
      if(r.close < g_sb_dn_level){ g_sb_dn_done = true; return; }

      ++g_sb_dn_counter;
      // 1) Shadow Breaker
      __SB_DrawV("SHADOW_BREAK_D_" + IntegerToString(g_sb_dn_counter), r.time, clrGold);

      // 2) temp-c1-sw (بیشترین High از [cend..j] با اسکیپ inside)
      int from = (cend>=0 ? cend : 0);
      if(from > j) from = j;
      int c1idx = __SB_LeftmostMaxHigh_ExInside(rates, insideHL, from, j);
      if(c1idx>=0 && c1idx<n)
         __SB_DrawTempC1("temp-c1-sw_d_" + IntegerToString(g_sb_dn_counter), rates[c1idx].time);

      g_sb_dn_done = true;
   }
}

#endif // WAVEBOT_SHADOWBREAKER_MQH
