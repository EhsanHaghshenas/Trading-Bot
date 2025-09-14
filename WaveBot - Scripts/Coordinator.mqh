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

// ——— حلقه‌ی هماهنگ‌کننده با سوئیچ خودکار
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

         // دو شاخه موازی
         datetime sw_time=0; bool sw = FindFirstSW_UP_AfterSeed(sym, tf, trig_time, to_t, sw_time);

         int mtc_idx=-1; datetime mtc_time=0;
         bool opp = Boot_FindFirstPair_DOWN(sym, tf, trig_time, to_t, mtc_idx, mtc_time);

         if(sw && (!opp || sw_time <= mtc_time))
         {
            // تداوم روند: SW_UP برنده
            cursor = sw_time + tfsec;
            mode   = DIR_UP;
            continue;
         }
         else if(opp)
         {
            // چرخش روند: mtc down
            Mark_MTC_DOWN(mtc_time);
            cursor = mtc_time + tfsec;
            mode   = DIR_DOWN;
            continue;
         }
         else
         {
            // هیچ‌کدام رخ نداد ⇒ خروج از حلقه
            break;
         }
      }
      else // DIR_DOWN
      {
         API_Down_RunScanSequential_W2W3_Hunter_UntilTransitionTrigger(sym, tf, cursor, to_t,
                                                                       trig, trig_time, trig_idx);
         if(!trig) break;

         datetime sw_time=0; bool sw = FindFirstSW_DOWN_AfterSeed(sym, tf, trig_time, to_t, sw_time);

         int mtc_idx=-1; datetime mtc_time=0;
         bool opp = Boot_FindFirstPair_UP(sym, tf, trig_time, to_t, mtc_idx, mtc_time);

         if(sw && (!opp || sw_time <= mtc_time))
         {
            cursor = sw_time + tfsec;
            mode   = DIR_DOWN;
            continue;
         }
         else if(opp)
         {
            Mark_MTC_UP(mtc_time);
            cursor = mtc_time + tfsec;
            mode   = DIR_UP;
            continue;
         }
         else
         {
            break;
         }
      }
   }
}

#endif // WAVEBOT_COORDINATOR_MQH
