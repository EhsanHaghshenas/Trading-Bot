// Include\WaveBot\Coordinator.mqh
#ifndef WAVEBOT_COORDINATOR_MQH
#define WAVEBOT_COORDINATOR_MQH

#include <WaveBot/Types.mqh>
#include <WaveBot/Bootstrap.mqh>
#include <WaveBot/API.mqh>        // UP
#include <WaveBot/API_Down.mqh>   // DOWN
#include <WaveBot/Hunter.mqh>
#include <WaveBot/Hunter_Down.mqh>
#include <WaveBot/ExtLQ.mqh>
#include <WaveBot/ExtLQ_Down.mqh>
#include <WaveBot/Markers.mqh>
#include <WaveBot/Data.mqh>
#include <WaveBot/Bodies.mqh>
#include <WaveBot/Utils.mqh>

// مارکرهای mtc
inline void Mark_MTC_UP (const datetime t){ if(InpDrawMarkers) MarkV("MTC_UP",  t, clrGold); }
inline void Mark_MTC_DOWN(const datetime t){ if(InpDrawMarkers) MarkV("MTC_DOWN",t, clrGold); }

// ——— کمک‌تابع: اولین SW-UP پس از seed معتبر
bool FindFirstSW_UP_AfterSeed(const string sym, const ENUM_TIMEFRAMES tf,
                                     const datetime from_t, const datetime to_t,
                                     datetime &sw_time_out)
{
   sw_time_out=0;
   if(!SW_UP_SeedActive()) return false;

   MqlRates r[]; int n = LoadRatesRange(sym, tf, from_t - PeriodSeconds(tf)*10, to_t, r);
   if(n<=0) return false;

   double bodyLowEff[], bodyHighEff[]; BuildEffectiveBodies(r, n, bodyLowEff, bodyHighEff);
   bool insideHL[];                    BuildInsideClusterFlagsHL(r, n, insideHL);

   enum State { SEARCH_W2, WAIT_CONFIRM };
   State state = SEARCH_W2;

   int idx=0; int c1=-1,c2=-1,c3=-1,c4=-1,cend=-1;
   bool have_w3=false; int w3_c1=-1,k2=-1,k3=-1,k4=-1,w3_end=-1;
   bool breakAchieved=false; int bodyBreakIdx=-1; double bodyBreakLevel=0.0;
   int w3_cand=-1; double w3_cand_high=-DBL_MAX;

   for(; idx<n; )
   {
      if(state==SEARCH_W2)
      {
         bool f=false;
         for(int i=idx;i<n;++i)
         {
            if(insideHL[i]) continue;
            int i2=-1,i3=-1,i4=-1;
            if(!CheckWave2_FromIndex_LocalOnly(r,insideHL,bodyLowEff,bodyHighEff,n,i,i2,i3,i4)) continue;

            c1=i; c2=i2; c3=i3; c4=i4; cend=(c4>=0?c4:c3);
            if(r[c1].time>to_t){ idx=n; break; }
            have_w3=false; w3_c1=-1; k2=k3=k4=-1; w3_end=-1; w3_cand=-1; w3_cand_high=-DBL_MAX;
            breakAchieved=false; bodyBreakIdx=-1; bodyBreakLevel=r[c1].high;
            idx=cend; state=WAIT_CONFIRM; f=true; break;
         }
         if(!f) break;
      }
      else
      {
         for(int j=idx;j<n;++j)
         {
            if(r[j].time>to_t){ idx=n; break; }

            if(!breakAchieved)
            {
               if(r[j].high > bodyBreakLevel)
               {
                  if(r[j].close > bodyBreakLevel){ breakAchieved=true; bodyBreakIdx=j; }
                  else { bodyBreakLevel = r[j].high; }
               }
            }

            if(j>=cend && (w3_cand<0 || r[j].high>w3_cand_high))
            { w3_cand=j; w3_cand_high=r[j].high; have_w3=false; }

            int startIdx=-1; if(w3_c1>=0) startIdx=w3_c1; else if(w3_cand>=0) startIdx=w3_cand;
            if(!have_w3 && startIdx>=0 && !insideHL[startIdx])
            {
               int a2=-1,a3=-1,a4=-1, w3e=-1;
               if(CheckWave3CountOnly_Local(r,insideHL,bodyLowEff,bodyHighEff,n,startIdx,a2,a3,a4,w3e))
               { have_w3=true; if(w3_c1<0) w3_c1=startIdx; k2=a2;k3=a3;k4=a4; w3_end=w3e; }
            }

            if(have_w3 && breakAchieved)
            {
               if(SW_UP_SeedActive() && r[w3_c1].time >= SW_UP_SeedTime() && r[bodyBreakIdx].close > SW_UP_Level())
               {
                  SW_UP_TryMarkOnConfirmedW3(r, n, w3_c1, bodyBreakIdx);
                  sw_time_out = r[bodyBreakIdx].time;
                  return true;
               }
               ExtLQ_Set(r[w3_c1].low, r[w3_c1].time);
               Hunter_OnExtLQUpdated();
               idx=j; state=SEARCH_W2; break;
            }
         }
      }
   }
   return false;
}

// ——— کمک‌تابع: اولین SW-DOWN پس از seed معتبر
bool FindFirstSW_DOWN_AfterSeed(const string sym, const ENUM_TIMEFRAMES tf,
                                       const datetime from_t, const datetime to_t,
                                       datetime &sw_time_out)
{
   sw_time_out=0;
   if(!SW_DOWN_SeedActive()) return false;

   MqlRates r[]; int n = LoadRatesRange(sym, tf, from_t - PeriodSeconds(tf)*10, to_t, r);
   if(n<=0) return false;

   double bodyLowEff[], bodyHighEff[]; BuildEffectiveBodies(r, n, bodyLowEff, bodyHighEff);
   bool insideHL[];                    BuildInsideClusterFlagsHL(r, n, insideHL);

   enum State { SEARCH_W2, WAIT_CONFIRM };
   State state = SEARCH_W2;

   int idx=0; int c1=-1,c2=-1,c3=-1,c4=-1,cend=-1;
   bool have_w3=false; int w3_c1=-1,k2=-1,k3=-1,k4=-1,w3_end=-1;
   bool breakAchieved=false; int bodyBreakIdx=-1; double bodyBreakLevel=0.0;
   int w3_cand=-1; double w3_cand_low=DBL_MAX;

   for(; idx<n; )
   {
      if(state==SEARCH_W2)
      {
         bool f=false;
         for(int i=idx;i<n;++i)
         {
            if(insideHL[i]) continue;
            int i2=-1,i3=-1,i4=-1;
            if(!CheckWave2_FromIndex_LocalOnly_Down(r,insideHL,bodyLowEff,bodyHighEff,n,i,i2,i3,i4)) continue;

            c1=i; c2=i2; c3=i3; c4=i4; cend=(c4>=0?c4:c3);
            if(r[c1].time>to_t){ idx=n; break; }
            have_w3=false; w3_c1=-1; k2=k3=k4=-1; w3_end=-1; w3_cand=-1; w3_cand_low=DBL_MAX;
            breakAchieved=false; bodyBreakIdx=-1; bodyBreakLevel=r[c1].low;
            idx=cend; state=WAIT_CONFIRM; f=true; break;
         }
         if(!f) break;
      }
      else
      {
         for(int j=idx;j<n;++j)
         {
            if(r[j].time>to_t){ idx=n; break; }

            if(!breakAchieved)
            {
               if(r[j].low < bodyBreakLevel)
               {
                  if(r[j].close < bodyBreakLevel){ breakAchieved=true; bodyBreakIdx=j; }
                  else { bodyBreakLevel = r[j].low; }
               }
            }

            if(j>=cend && (w3_cand<0 || r[j].low<w3_cand_low))
            { w3_cand=j; w3_cand_low=r[j].low; have_w3=false; }

            int startIdx=-1; if(w3_c1>=0) startIdx=w3_c1; else if(w3_cand>=0) startIdx=w3_cand;
            if(!have_w3 && startIdx>=0 && !insideHL[startIdx])
            {
               int a2=-1,a3=-1,a4=-1, w3e=-1;
               if(CheckWave3CountOnly_Local_Down(r,insideHL,bodyLowEff,bodyHighEff,n,startIdx,a2,a3,a4,w3e))
               { have_w3=true; if(w3_c1<0) w3_c1=startIdx; k2=a2;k3=a3;k4=a4; w3_end=w3e; }
            }

            if(have_w3 && breakAchieved)
            {
               if(SW_DOWN_SeedActive() && r[w3_c1].time >= SW_DOWN_SeedTime() && r[bodyBreakIdx].close < SW_DOWN_Level())
               {
                  SW_DOWN_TryMarkOnConfirmedW3(r, n, w3_c1, bodyBreakIdx);
                  sw_time_out = r[bodyBreakIdx].time;
                  return true;
               }
               ExtLQ_Down_Set(r[w3_c1].high, r[w3_c1].time);
               Hunter_Down_OnExtLQUpdated();
               idx=j; state=SEARCH_W2; break;
            }
         }
      }
   }
   return false;
}

// === Parallel Race after a Trigger (Mode=UP) ===
// از trig_time رو به جلو، به صورت همزمان دو مسیر را پایش می‌کنیم:
// A) اولین SW-UP پس از seed معتبر
// B) اولین جفت W2->W3 DOWN با بریکِ بدنه (کندل بریک = MTC_DOWN)
// خروجی: win_is_sw=true => SW برنده، false => MTC برنده. win_time = زمان کندل برنده.
bool Race_FromTrigger_UP(const string sym, const ENUM_TIMEFRAMES tf,
                                const datetime trig_time, const datetime to_t,
                                bool &win_is_sw, datetime &win_time)
{
   win_is_sw=false; win_time=0;
   MqlRates rates[]; int n = LoadRatesRange(sym, tf, trig_time - PeriodSeconds(tf)*10, to_t, rates);
   if(n<=0) return false;

   double bodyLowEff[], bodyHighEff[]; BuildEffectiveBodies(rates, n, bodyLowEff, bodyHighEff);
   bool insideHL[];                    BuildInsideClusterFlagsHL(rates, n, insideHL);

   // شاخه A: SW-UP (پس از seed معتبر)
   const bool seed_ok = SW_UP_SeedActive();
   const datetime seed_t = seed_ok ? SW_UP_SeedTime() : 0;
   const double   seed_lv= seed_ok ? SW_UP_Level()   : 0.0;

   // شاخه B: جفت W2->W3 DOWN
   enum State { SRCH_W2, WAIT_W3 };
   State st = SRCH_W2;
   int c1=-1,c2=-1,c3=-1,c4=-1,cend=-1;
   bool have_w3=false; int w3_c1=-1,k2=-1,k3=-1,k4=-1,w3_end=-1;
   bool brk=false; int brk_idx=-1; double brk_lv=0.0;

   // از اولین ایندکس >= trig_time شروع کن
   int j0=0; while(j0<n && rates[j0].time < trig_time) j0++;

   for(int j=j0; j<n; ++j)
   {
      // ===== شاخه A: SW-UP =====
      if(seed_ok && rates[j].time >= seed_t)
      {
         // شرط SW: W3 صعودی تایید شود و کندل body-break بالاتر از seed_lv ببندد.
         // اینجا فقط شرط بدنه را پایش می‌کنیم؛ شمارش W3 را با همان CheckWave3CountOnly_Local می‌گیریم.
         // انتخاب C1_W3 مانند API: بهترین کاندید بعد از cend قبلی.
         static int sw_c1=-1; static int sw_cand=-1; static double sw_cand_hi=-DBL_MAX;
         static int sw_a2=-1, sw_a3=-1, sw_a4=-1, sw_end=-1;
         static bool sw_have=false; static bool sw_brk=false; static int sw_brk_idx=-1;

         if(!sw_brk)
         {
            // اگر هنوز W3 انتخاب نشده، بهترین کاندید را از همین بار به بعد بردار
            if(sw_c1<0 && (sw_cand<0 || rates[j].high>sw_cand_hi))
            { sw_cand=j; sw_cand_hi=rates[j].high; }

            int stIdx = (sw_c1>=0? sw_c1 : sw_cand);
            if(stIdx>=0 && !insideHL[stIdx] && !sw_have)
            {
               int a2=-1,a3=-1,a4=-1, w3e=-1;
               if(CheckWave3CountOnly_Local(rates,insideHL,bodyLowEff,bodyHighEff,n,stIdx,a2,a3,a4,w3e))
               { sw_have=true; if(sw_c1<0) sw_c1=stIdx; sw_a2=a2; sw_a3=a3; sw_a4=a4; sw_end=w3e; }
            }

            if(sw_have && rates[j].close > seed_lv)
            {
               sw_brk=true; sw_brk_idx=j;
               // مارک استاندارد SW از توابع پروژه
               SW_UP_TryMarkOnConfirmedW3(rates, n, sw_c1, sw_brk_idx);
               win_is_sw=true; win_time=rates[sw_brk_idx].time;
               return true;
            }
         }
      }

      // ===== شاخه B: جفت DOWN =====
      if(st==SRCH_W2)
      {
         if(!insideHL[j])
         {
            int i2=-1,i3=-1,i4=-1;
            if(CheckWave2_FromIndex_LocalOnly_Down(rates,insideHL,bodyLowEff,bodyHighEff,n,j,i2,i3,i4))
            {
               c1=j; c2=i2; c3=i3; c4=i4; cend=(c4>=0?c4:c3);
               brk=false; brk_idx=-1; brk_lv=rates[c1].low;
               have_w3=false; w3_c1=-1; k2=k3=k4=-1; w3_end=-1;
               j = cend; st=WAIT_W3; // از انتهای W2 ادامه می‌دهیم
               continue;
            }
         }
      }
      else // WAIT_W3
      {
         if(!brk)
         {
            if(rates[j].low < brk_lv)
            {
               if(rates[j].close < brk_lv){ brk=true; brk_idx=j; }
               else { brk_lv = rates[j].low; } // ارتقای سطح با شدو
            }
         }

         // انتخاب C1_W3 (DOWN): کمترین Low بعد از cend
         static int w3cand=-1; static double w3cand_lo=DBL_MAX;
         if(j>=cend && (w3cand<0 || rates[j].low<w3cand_lo))
         { w3cand=j; w3cand_lo=rates[j].low; }

         int stIdx = (w3_c1>=0? w3_c1 : w3cand);
         if(!have_w3 && stIdx>=0 && !insideHL[stIdx])
         {
            int a2=-1,a3=-1,a4=-1, w3e=-1;
            if(CheckWave3CountOnly_Local_Down(rates,insideHL,bodyLowEff,bodyHighEff,n,stIdx,a2,a3,a4,w3e))
            { have_w3=true; if(w3_c1<0) w3_c1=stIdx; k2=a2; k3=a3; k4=a4; w3_end=w3e; }
         }

         if(have_w3 && brk)
         {
            // جفت DOWN کامل شد ⇒ این کندل همان کندل MTC_DOWN است
            MarkV("MTC_DOWN", rates[brk_idx].time, clrGold);
            win_is_sw=false; win_time=rates[brk_idx].time;
            // به‌روزرسانی ext lq طبق قرارداد پروژه (بعد از تایید W3)
            ExtLQ_Down_Set(rates[w3_c1].high, rates[w3_c1].time);
            Hunter_Down_OnExtLQUpdated();
            return true;
         }
      }
   }
   return false;
}

// === Parallel Race after a Trigger (Mode=DOWN) ===
bool Race_FromTrigger_DOWN(const string sym, const ENUM_TIMEFRAMES tf,
                                  const datetime trig_time, const datetime to_t,
                                  bool &win_is_sw, datetime &win_time)
{
   win_is_sw=false; win_time=0;
   MqlRates rates[]; int n = LoadRatesRange(sym, tf, trig_time - PeriodSeconds(tf)*10, to_t, rates);
   if(n<=0) return false;

   double bodyLowEff[], bodyHighEff[]; BuildEffectiveBodies(rates, n, bodyLowEff, bodyHighEff);
   bool insideHL[];                    BuildInsideClusterFlagsHL(rates, n, insideHL);

   // شاخه A: SW-DOWN
   const bool seed_ok = SW_DOWN_SeedActive();
   const datetime seed_t = seed_ok ? SW_DOWN_SeedTime() : 0;
   const double   seed_lv= seed_ok ? SW_DOWN_Level()   : 0.0;

   // شاخه B: جفت W2->W3 UP
   enum State { SRCH_W2, WAIT_W3 };
   State st = SRCH_W2;
   int c1=-1,c2=-1,c3=-1,c4=-1,cend=-1;
   bool have_w3=false; int w3_c1=-1,k2=-1,k3=-1,k4=-1,w3_end=-1;
   bool brk=false; int brk_idx=-1; double brk_lv=0.0;

   int j0=0; while(j0<n && rates[j0].time < trig_time) j0++;

   for(int j=j0; j<n; ++j)
   {
      // ===== شاخه A: SW-DOWN =====
      if(seed_ok && rates[j].time >= seed_t)
      {
         static int sw_c1=-1; static int sw_cand=-1; static double sw_cand_lo=DBL_MAX;
         static int sw_a2=-1, sw_a3=-1, sw_a4=-1, sw_end=-1;
         static bool sw_have=false; static bool sw_brk=false; static int sw_brk_idx=-1;

         if(!sw_brk)
         {
            if(sw_c1<0 && (sw_cand<0 || rates[j].low<sw_cand_lo))
            { sw_cand=j; sw_cand_lo=rates[j].low; }

            int stIdx = (sw_c1>=0? sw_c1 : sw_cand);
            if(stIdx>=0 && !insideHL[stIdx] && !sw_have)
            {
               int a2=-1,a3=-1,a4=-1, w3e=-1;
               if(CheckWave3CountOnly_Local_Down(rates,insideHL,bodyLowEff,bodyHighEff,n,stIdx,a2,a3,a4,w3e))
               { sw_have=true; if(sw_c1<0) sw_c1=stIdx; sw_a2=a2; sw_a3=a3; sw_a4=a4; sw_end=w3e; }
            }

            if(sw_have && rates[j].close < seed_lv)
            {
               sw_brk=true; sw_brk_idx=j;
               SW_DOWN_TryMarkOnConfirmedW3(rates, n, sw_c1, sw_brk_idx);
               win_is_sw=true; win_time=rates[sw_brk_idx].time;
               return true;
            }
         }
      }

      // ===== شاخه B: جفت UP =====
      if(st==SRCH_W2)
      {
         if(!insideHL[j])
         {
            int i2=-1,i3=-1,i4=-1;
            if(CheckWave2_FromIndex_LocalOnly(rates,insideHL,bodyLowEff,bodyHighEff,n,j,i2,i3,i4))
            {
               c1=j; c2=i2; c3=i3; c4=i4; cend=(c4>=0?c4:c3);
               brk=false; brk_idx=-1; brk_lv=rates[c1].high;
               have_w3=false; w3_c1=-1; k2=k3=k4=-1; w3_end=-1;
               j = cend; st=WAIT_W3;
               continue;
            }
         }
      }
      else
      {
         if(!brk)
         {
            if(rates[j].high > brk_lv)
            {
               if(rates[j].close > brk_lv){ brk=true; brk_idx=j; }
               else { brk_lv = rates[j].high; }
            }
         }

         static int w3cand=-1; static double w3cand_hi=-DBL_MAX;
         if(j>=cend && (w3cand<0 || rates[j].high>w3cand_hi))
         { w3cand=j; w3cand_hi=rates[j].high; }

         int stIdx = (w3_c1>=0? w3_c1 : w3cand);
         if(!have_w3 && stIdx>=0 && !insideHL[stIdx])
         {
            int a2=-1,a3=-1,a4=-1, w3e=-1;
            if(CheckWave3CountOnly_Local(rates,insideHL,bodyLowEff,bodyHighEff,n,stIdx,a2,a3,a4,w3e))
            { have_w3=true; if(w3_c1<0) w3_c1=stIdx; k2=a2; k3=a3; k4=a4; w3_end=w3e; }
         }

         if(have_w3 && brk)
         {
            MarkV("MTC_UP", rates[brk_idx].time, clrGold);
            win_is_sw=false; win_time=rates[brk_idx].time;
            ExtLQ_Set(rates[w3_c1].low, rates[w3_c1].time);
            Hunter_OnExtLQUpdated();
            return true;
         }
      }
   }
   return false;
}

inline void Coordinator_RunAuto(const string sym, const ENUM_TIMEFRAMES tf,
                                const Direction start_mode,
                                const datetime from_t, const datetime to_t)
{
   Direction mode = start_mode;
   datetime  cursor = from_t;
   const int tfsec = PeriodSeconds(tf);

   while(cursor < to_t)
   {
      bool trig=false; datetime trig_time=0; int trig_idx=-1;

      if(mode==DIR_UP)
      {
         API_RunScanSequential_W2W3_Hunter_UntilTransitionTrigger(sym, tf, cursor, to_t,
                                                                  trig, trig_time, trig_idx);
         if(!trig) break;

         bool win_is_sw=false; datetime win_time=0;
         if(Race_FromTrigger_UP(sym, tf, trig_time, to_t, win_is_sw, win_time))
         {
            if(win_is_sw) // SW-UP
            { cursor = win_time + tfsec; mode=DIR_UP; }
            else         // MTC-DOWN
            { cursor = win_time + tfsec; mode=DIR_DOWN; }
            continue;
         }
         else break;
      }
      else // DIR_DOWN
      {
         API_Down_RunScanSequential_W2W3_Hunter_UntilTransitionTrigger(sym, tf, cursor, to_t,
                                                                       trig, trig_time, trig_idx);
         if(!trig) break;

         bool win_is_sw=false; datetime win_time=0;
         if(Race_FromTrigger_DOWN(sym, tf, trig_time, to_t, win_is_sw, win_time))
         {
            if(win_is_sw) // SW-DOWN
            { cursor = win_time + tfsec; mode=DIR_DOWN; }
            else         // MTC-UP
            { cursor = win_time + tfsec; mode=DIR_UP; }
            continue;
         }
         else break;
      }
   }
}

#endif // WAVEBOT_COORDINATOR_MQH
