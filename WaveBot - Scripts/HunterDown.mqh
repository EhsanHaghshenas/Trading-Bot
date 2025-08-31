#ifndef WAVEBOT_HUNTERDOWN_MQH
#define WAVEBOT_HUNTERDOWN_MQH

#include <WaveBot/Markers.mqh>
#include <WaveBot/ExtLQ.mqh>
#include <WaveBot/Utils.mqh>

static int      g_hwd_counter   = 0;
static datetime g_lq_time_seenU = 0;
static bool     g_marked_for_lqU= false;

inline void HunterDown_OnExtLQUpdated()
{
   g_lq_time_seenU  = ExtLQ_Has()? ExtLQ_Time():0;
   g_marked_for_lqU = false;
}

inline bool HunterDown_IsExtLQUpCross(const MqlRates &r)
{
   if(!ExtLQ_Has()) return false;
   const double lq = ExtLQ_Get();
   return (r.high >= lq || r.close > lq);
}

inline void HunterDown_MarkWithC1(const MqlRates &rates[], const int n,
                                  const int c1_index, const int cross_idx)
{
   if(!ExtLQ_Has()) return;
   if(c1_index<0 || c1_index>=n || cross_idx<0 || cross_idx>=n) return;
   if(c1_index>cross_idx) return;

   const datetime lqt = ExtLQ_Time();
   if(lqt != g_lq_time_seenU){ g_lq_time_seenU=lqt; g_marked_for_lqU=false; }
   if(g_marked_for_lqU) return;

   const double lq = ExtLQ_Get();
   const MqlRates rx = rates[cross_idx];
   if(!(rx.high >= lq || rx.close > lq)) return;

   ++g_hwd_counter;
   string tag=IntegerToString(g_hwd_counter);

   if(InpDrawMarkers)
   {
      MarkV("HWD_"+tag+"_C1", rates[c1_index].time, clrDarkOrange);
      MarkV("HWD_"+tag+"_X",  rates[cross_idx].time, clrSandyBrown);
   }
   g_marked_for_lqU=true;

   if(InpDebugPrints)
      Print("[HunterDown] with C1 | C1=",T(rates[c1_index].time),
            " | CROSS=",T(rates[cross_idx].time)," | ext lq=",DoubleToString(lq,_Digits));
}

#endif // WAVEBOT_HUNTERDOWN_MQH
