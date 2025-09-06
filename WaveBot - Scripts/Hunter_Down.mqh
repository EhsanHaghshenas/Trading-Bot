#ifndef WAVEBOT_HUNTER_DOWN_MQH
#define WAVEBOT_HUNTER_DOWN_MQH

#include <WaveBot/Markers.mqh>
#include <WaveBot/ExtLQ_Down.mqh>
#include <WaveBot/Utils.mqh>

// شمارنده‌ی نام‌گذاری
static int g_hw_counter_d = 0;

// «فقط اولین عبور برای هر ext lq»
static datetime g_lq_time_seen_d  = 0;
static bool     g_marked_for_lq_d = false;

inline void Hunter_Down_OnExtLQUpdated()
{
   g_lq_time_seen_d  = ExtLQ_Down_Has() ? ExtLQ_Down_Time() : 0;
   g_marked_for_lq_d = false;
}

inline bool Hunter_Down_IsExtLQCross(const MqlRates &r)
{
   if(!ExtLQ_Down_Has()) return false;
   const double lq = ExtLQ_Down_Get();
   return (r.high >= lq || r.close > lq); // بدنه یا شدو (cross-up)
}

// مارک Hunter با C1 داده‌شده (C1 همان C1 موج۲)
inline void Hunter_Down_MarkWithC1(const MqlRates &rates[], const int n,
                                   const int c1_index, const int cross_idx)
{
   if(!ExtLQ_Down_Has()) return;

   const datetime lqt = ExtLQ_Down_Time();
   if(lqt != g_lq_time_seen_d){ g_lq_time_seen_d=lqt; g_marked_for_lq_d=false; }
   if(g_marked_for_lq_d) return;

   if(c1_index<0 || c1_index>=n || cross_idx<0 || cross_idx>=n) return;
   if(c1_index > cross_idx) return;

   const double lq = ExtLQ_Down_Get();
   const MqlRates rx = rates[cross_idx];
   if(!(rx.high >= lq || rx.close > lq)) return; // واقعاً عبور کرده باشد

   ++g_hw_counter_d;
   string tag = IntegerToString(g_hw_counter_d);

   if(InpDrawMarkers)
   {
      MarkV("HW_"+tag+"_C1", rates[c1_index].time, clrViolet);
      MarkV("HW_"+tag+"_X",  rates[cross_idx].time, clrMagenta);
   }
   g_marked_for_lq_d = true;

   if(InpDebugPrints)
      Print("[Hunter-DOWN] with C1 | C1=",T(rates[c1_index].time),
            " | CROSS=",T(rates[cross_idx].time),
            " | ext lq=",DoubleToString(lq,_Digits));
}

#endif // WAVEBOT_HUNTER_DOWN_MQH
