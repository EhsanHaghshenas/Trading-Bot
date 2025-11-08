// WaveBot/ShadowBreaker.mqh
#ifndef WAVEBOT_SHADOWBREAKER_MQH
#define WAVEBOT_SHADOWBREAKER_MQH

#include <WaveBot/Markers.mqh>
#include <WaveBot/Hunter.mqh>        // SW_UP_* access
#include <WaveBot/Hunter_Down.mqh>   // SW_DOWN_* access
#include <WaveBot/SWGate.mqh>        // SWGate_* access

// ---------- helpers ----------
inline void __SB_DrawV(const string base, const datetime t, const color col)
{
   const string name = __ScanPrefix() + base;
   if(ObjectFind(0, name) != -1) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_VLINE, 0, t, 0);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASHDOT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
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

// فراخوانی روی هر کندل در اسکن UP
inline void SB_UP_OnBar(const MqlRates &r)
{
   SB_UP_SyncWithSeed();
   if(g_sb_up_seed_time == 0 || g_sb_up_done) return;
   if(r.time < g_sb_up_seed_time) return;

   // Wick-only pass over HW C1 high
   if(r.high > g_sb_up_level)
   {
      // اگر با بدنه هم شکست، دیگر ShadowBreaker نیست
      if(r.close > g_sb_up_level){ g_sb_up_done = true; return; }

      ++g_sb_up_counter;
      __SB_DrawV("SHADOW_BREAK_U_" + IntegerToString(g_sb_up_counter), r.time, clrGold);
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

// فراخوانی روی هر کندل در اسکن DOWN
inline void SB_DN_OnBar(const MqlRates &r)
{
   SB_DN_SyncWithSeed();
   if(g_sb_dn_seed_time == 0 || g_sb_dn_done) return;
   if(r.time < g_sb_dn_seed_time) return;

   // Wick-only pass under HW C1 low
   if(r.low < g_sb_dn_level)
   {
      if(r.close < g_sb_dn_level){ g_sb_dn_done = true; return; } // Body-break ⇒ SW تایید شده

      ++g_sb_dn_counter;
      __SB_DrawV("SHADOW_BREAK_D_" + IntegerToString(g_sb_dn_counter), r.time, clrGold);
      g_sb_dn_done = true;
   }
}

#endif // WAVEBOT_SHADOWBREAKER_MQH
