//+------------------------------------------------------------------+
//| WaveBot - Transition (Auto Switch Manager)                      |
//| سازوکار: ورود به ترنزیشن با body-break هانتر روی ext lq         |
//| و دو مسیر همزمان: A) SW هم‌جهت  B) جفت W2→W3 خلاف‌جهت           |
//+------------------------------------------------------------------+
#ifndef WAVEBOT_TRANSITION_MQH
#define WAVEBOT_TRANSITION_MQH

#include <WaveBot/Types.mqh>
#include <WaveBot/Utils.mqh>
#include <WaveBot/Markers.mqh>
#include <WaveBot/Bootstrap.mqh>   // Boot_FindFirstPair_UP/DOWN
#include <WaveBot/Hunter.mqh>      // دسترسی به بذر SW-UP
#include <WaveBot/Hunter_Down.mqh> // دسترسی به بذر SW-DOWN
#include <WaveBot/Data.mqh>
#include <WaveBot/Bodies.mqh>
#include <WaveBot/Wave2.mqh>
#include <WaveBot/Wave3.mqh>
#include <WaveBot/Wave2_Down.mqh>
#include <WaveBot/Wave3_Down.mqh>

// ---------- وضعیت در حال سوئیچ ----------
static bool       g_switch_pending     = false;
static Direction  g_switch_to          = DIR_UP;
static datetime   g_switch_time        = 0;
static int        g_mtc_counter        = 0;

// دسترسی ساده
inline bool     Transition_SwitchScheduled(){ return g_switch_pending; }
inline datetime Transition_ScheduledTime() { return g_switch_time;     }
inline Direction Transition_ScheduledMode(){ return g_switch_to;       }
inline void     Transition_ResetPending(){ g_switch_pending=false; g_switch_time=0; }

// مارک mtc
inline void Transition_DrawMTC(const Direction toMode, const datetime t)
{
   if(!InpDrawMarkers) return;
   ++g_mtc_counter;
   string tag = IntegerToString(g_mtc_counter);
   if(toMode==DIR_UP)
      MarkV("mtc_up_"+tag,   t, clrDodgerBlue);
   else
      MarkV("mtc_down_"+tag, t, clrOrangeRed);
}

// زمان اولین SW-UP بعد از «ازکجا» (اگر بذر فعال باشد)
inline bool FindFirstSW_UP_From(const string sym, const ENUM_TIMEFRAMES tf,
                                const datetime from_time, const datetime to_time,
                                int &out_break_idx, datetime &out_break_time)
{
   out_break_idx=-1; out_break_time=0;
   if(!SW_UP_SeedActive()) return false;

   const int tfsec = PeriodSeconds(tf);
   datetime effective_start = from_time + (3*tfsec);
   datetime from_adj = from_time - tfsec*10;

   MqlRates rates[]; int n = LoadRatesRange(sym, tf, from_adj, to_time, rates);
   if(n<=0) return false;

   double bodyLowEff[], bodyHighEff[]; BuildEffectiveBodies(rates, n, bodyLowEff, bodyHighEff);
   bool insideHL[];                    BuildInsideClusterFlagsHL(rates, n, insideHL);

   int first_eff=0; while(first_eff<n && rates[first_eff].time<effective_start) first_eff++;
   int idx = MathMax(0, first_eff-2);

   enum State { SEARCH_W2, WAIT_CONFIRM };
   State state=SEARCH_W2;

   int c1=-1,c2=-1,c3=-1,c4=-1, cend=-1;
   bool have_w3=false;
   int  w3_c1=-1,k2=-1,k3=-1,k4=-1,w3_end=-1;
   int  w3_cand=-1; double w3_cand_low=DBL_MAX;

   bool   wickActive=false;
   int    firstWickIdx=-1, wickBreakIdx=-1;
   double bodyBreakLevel=0.0;
   bool   breakAchieved=false;
   int    bodyBreakIdx=-1;

   while(idx<n)
   {
      if(state==SEARCH_W2)
      {
         bool found=false;
         for(int i=idx;i<n;++i)
         {
            if(insideHL[i]) continue;
            int a2=-1,a3=-1,a4=-1;
            if(!CheckWave2_FromIndex_LocalOnly(rates, insideHL, bodyLowEff, bodyHighEff, n, i, a2, a3, a4))
               continue;

            c1=i; c2=a2; c3=a3; c4=a4; cend=(c4>=0?c4:c3);
            if(rates[c1].time<effective_start || rates[c1].time>to_time)
            { idx=cend+1; continue; }

            // reset W3 state
            have_w3=false; w3_c1=-1; k2=k3=k4=-1; w3_end=-1;
            w3_cand=-1;   w3_cand_low=DBL_MAX;

            // wick/body-break gear
            wickActive=false; firstWickIdx=-1; wickBreakIdx=-1;
            bodyBreakLevel = rates[c1].high;  // برای UP، بریکِ بدنه به بالای H1_W2
            breakAchieved  = false;
            bodyBreakIdx   = -1;

            idx=cend; state=WAIT_CONFIRM; found=true; break;
         }
         if(!found) break;
      }
      else // WAIT_CONFIRM (UP)
      {
         bool progressed=false;
         for(int j=idx;j<n;++j)
         {
            if(insideHL[j]) continue;

            // ارتقای سطح بریک با شدو
            if(!breakAchieved)
            {
               if(rates[j].high > bodyBreakLevel)
               {
                  if(rates[j].close > bodyBreakLevel)
                  { breakAchieved=true; bodyBreakIdx=j; }
                  else
                  { bodyBreakLevel=rates[j].high;
                    if(firstWickIdx<0){ firstWickIdx=j; wickBreakIdx=j; wickActive=true;
                       int anchorC1 = IndexOfLeftmostMinLow_ExInside(rates, insideHL, cend, firstWickIdx);
                       have_w3=false; w3_c1 = anchorC1;
                       w3_cand=-1; w3_cand_low=DBL_MAX;
                    }
                  }
               }
            }

            // مسیر مستقیم: کمترین Low از cend به بعد
            if(!wickActive)
            {
               if(j>=cend && (w3_cand<0 || rates[j].low < w3_cand_low))
               { w3_cand=j; w3_cand_low=rates[j].low; have_w3=false; }
            }

            // انتخاب استارت شمارش W3
            int startIdx=-1;
            if(w3_c1>=0)      startIdx=w3_c1;
            else if(w3_cand>=0) startIdx=w3_cand;

            // شمارش W3 (UP)
            if(!have_w3 && startIdx>=0 && !insideHL[startIdx])
            {
               int a2=-1,a3=-1,a4=-1, w3e=-1;
               if(CheckWave3CountOnly_Local(rates, insideHL, bodyLowEff, bodyHighEff, n, startIdx, a2, a3, a4, w3e))
               { have_w3=true; if(w3_c1<0) w3_c1=startIdx; k2=a2;k3=a3;k4=a4; w3_end=w3e; }
            }

            // نهایی‌سازی SW: W3 تایید + body-break بالای بذر
            if(have_w3 && breakAchieved)
            {
               // باید بعد از هانتر باشد و از سطح بذر عبور کند
               if(rates[w3_c1].time >= SW_UP_SeedTime() && rates[bodyBreakIdx].close > SW_UP_Level())
               {
                  out_break_idx  = bodyBreakIdx;
                  out_break_time = rates[bodyBreakIdx].time;
                  return true;
               }
               // اگر W3 تایید شد ولی بالای بذر بسته نشد => این W3 برای SW معتبر نیست، به جستجو ادامه بده
               // (هیچ تغییر حالت لازم نیست)
            }
         }
         if(!progressed) break;
      }
   }
   return false;
}

// زمان اولین SW-DOWN بعد از «ازکجا» (اگر بذر فعال باشد)
inline bool FindFirstSW_DOWN_From(const string sym, const ENUM_TIMEFRAMES tf,
                                  const datetime from_time, const datetime to_time,
                                  int &out_break_idx, datetime &out_break_time)
{
   out_break_idx=-1; out_break_time=0;
   if(!SW_DOWN_SeedActive()) return false;

   const int tfsec = PeriodSeconds(tf);
   datetime effective_start = from_time + (3*tfsec);
   datetime from_adj = from_time - tfsec*10;

   MqlRates rates[]; int n = LoadRatesRange(sym, tf, from_adj, to_time, rates);
   if(n<=0) return false;

   double bodyLowEff[], bodyHighEff[]; BuildEffectiveBodies(rates, n, bodyLowEff, bodyHighEff);
   bool insideHL[];                    BuildInsideClusterFlagsHL(rates, n, insideHL);

   int first_eff=0; while(first_eff<n && rates[first_eff].time<effective_start) first_eff++;
   int idx = MathMax(0, first_eff-2);

   enum State { SEARCH_W2, WAIT_CONFIRM };
   State state=SEARCH_W2;

   int c1=-1,c2=-1,c3=-1,c4=-1, cend=-1;
   bool have_w3=false;
   int  w3_c1=-1,k2=-1,k3=-1,k4=-1,w3_end=-1;
   int  w3_cand=-1; double w3_cand_high=-DBL_MAX;

   bool   wickActive=false;
   int    firstWickIdx=-1, wickBreakIdx=-1;
   double bodyBreakLevel=0.0;
   bool   breakAchieved=false;
   int    bodyBreakIdx=-1;

   while(idx<n)
   {
      if(state==SEARCH_W2)
      {
         bool found=false;
         for(int i=idx;i<n;++i)
         {
            if(insideHL[i]) continue;
            int a2=-1,a3=-1,a4=-1;
            if(!CheckWave2_FromIndex_LocalOnly_Down(rates, insideHL, bodyLowEff, bodyHighEff, n, i, a2, a3, a4))
               continue;

            c1=i; c2=a2; c3=a3; c4=a4; cend=(c4>=0?c4:c3);
            if(rates[c1].time<effective_start || rates[c1].time>to_time)
            { idx=cend+1; continue; }

            // reset W3 state
            have_w3=false; w3_c1=-1; k2=k3=k4=-1; w3_end=-1;
            w3_cand=-1;   w3_cand_high=-DBL_MAX;

            wickActive=false; firstWickIdx=-1; wickBreakIdx=-1;
            bodyBreakLevel = rates[c1].low;  // برای DOWN، بریکِ بدنه به زیر L1_W2
            breakAchieved  = false; bodyBreakIdx=-1;

            idx=cend; state=WAIT_CONFIRM; found=true; break;
         }
         if(!found) break;
      }
      else // WAIT_CONFIRM (DOWN)
      {
         bool progressed=false;
         for(int j=idx;j<n;++j)
         {
            if(insideHL[j]) continue;

            // ارتقای سطح بریک با شدو
            if(!breakAchieved)
            {
               if(rates[j].low < bodyBreakLevel)
               {
                  if(rates[j].close < bodyBreakLevel)
                  { breakAchieved=true; bodyBreakIdx=j; }
                  else
                  {
                     bodyBreakLevel=rates[j].low;
                     if(firstWickIdx<0){ firstWickIdx=j; wickBreakIdx=j; wickActive=true;
                        int anchorC1 = IndexOfLeftmostMaxHigh_ExInside(rates, insideHL, cend, firstWickIdx);
                        have_w3=false; w3_c1=anchorC1;
                        w3_cand=-1; w3_cand_high=-DBL_MAX;
                     }
                  }
               }
            }

            // مسیر مستقیم: بزرگ‌ترین High از cend به بعد
            if(!wickActive)
            {
               if(j>=cend && (w3_cand<0 || rates[j].high > w3_cand_high))
               { w3_cand=j; w3_cand_high=rates[j].high; have_w3=false; }
            }

            int startIdx=-1;
            if(w3_c1>=0) startIdx=w3_c1;
            else if(w3_cand>=0) startIdx=w3_cand;

            if(!have_w3 && startIdx>=0 && !insideHL[startIdx])
            {
               int a2=-1,a3=-1,a4=-1,w3e=-1;
               if(CheckWave3CountOnly_Local_Down(rates, insideHL, bodyLowEff, bodyHighEff, n, startIdx, a2, a3, a4, w3e))
               { have_w3=true; if(w3_c1<0) w3_c1=startIdx; k2=a2;k3=a3;k4=a4; w3_end=w3e; }
            }

            // نهایی‌سازی SW-DOWN: W3 تایید + body-break زیر بذر
            if(have_w3 && breakAchieved)
            {
               if(rates[w3_c1].time >= SW_DOWN_SeedTime() && rates[bodyBreakIdx].close < SW_DOWN_Level())
               { out_break_idx=bodyBreakIdx; out_break_time=rates[bodyBreakIdx].time; return true; }
            }
         }
         if(!progressed) break;
      }
   }
   return false;
}

// فراخوانی از API(UP): آغاز مسابقه از کندل body-break هانتر
inline void Transition_RaceFromTrigger_UP(const string sym, const ENUM_TIMEFRAMES tf,
                                          const datetime trigger_time, const datetime to_time)
{
   // مسیر A: SW-UP
   int a_idx=-1; datetime a_t=0;
   bool a_ok = FindFirstSW_UP_From(sym, tf, trigger_time, to_time, a_idx, a_t);

   // مسیر B: اولین جفت DOWN
   int b_idx=-1; datetime b_t=0;
   bool b_ok = Boot_FindFirstPair_DOWN(sym, tf, trigger_time, to_time, b_idx, b_t);

   if(!a_ok && !b_ok) return;
   if( a_ok && !b_ok) { /* باقی در همان مود UP، ترنزیشن بعد از SW پایان می‌یابد */ return; }
   if(!a_ok &&  b_ok) { g_switch_pending=true; g_switch_to=DIR_DOWN; g_switch_time=b_t; Transition_DrawMTC(DIR_DOWN, b_t); return; }

   // هر دو رخ می‌دهند: زودتر اولویت دارد (طبق توضیح شما «همزمان دقیق روی یک کندل رخ نمی‌دهد»)
   if(a_t < b_t) return; // A برنده: ادامه در UP
   else          { g_switch_pending=true; g_switch_to=DIR_DOWN; g_switch_time=b_t; Transition_DrawMTC(DIR_DOWN, b_t); }
}

// فراخوانی از API(DOWN): آغاز مسابقه از کندل body-break هانتر
inline void Transition_RaceFromTrigger_DOWN(const string sym, const ENUM_TIMEFRAMES tf,
                                            const datetime trigger_time, const datetime to_time)
{
   // مسیر A: SW-DOWN
   int a_idx=-1; datetime a_t=0;
   bool a_ok = FindFirstSW_DOWN_From(sym, tf, trigger_time, to_time, a_idx, a_t);

   // مسیر B: اولین جفت UP
   int b_idx=-1; datetime b_t=0;
   bool b_ok = Boot_FindFirstPair_UP(sym, tf, trigger_time, to_time, b_idx, b_t);

   if(!a_ok && !b_ok) return;
   if( a_ok && !b_ok) { return; }
   if(!a_ok &&  b_ok) { g_switch_pending=true; g_switch_to=DIR_UP; g_switch_time=b_t; Transition_DrawMTC(DIR_UP, b_t); return; }

   if(a_t < b_t) return; // A برنده
   else          { g_switch_pending=true; g_switch_to=DIR_UP; g_switch_time=b_t; Transition_DrawMTC(DIR_UP, b_t); }
}

#endif // WAVEBOT_TRANSITION_MQH
