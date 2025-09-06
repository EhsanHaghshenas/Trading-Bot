#ifndef WAVEBOT_HUNTER_DOWN_MQH
#define WAVEBOT_HUNTER_DOWN_MQH

#include <WaveBot/Markers.mqh>
#include <WaveBot/ExtLQ_Down.mqh>
#include <WaveBot/Utils.mqh>

// شمارنده
static int      g_hw_counter_d     = 0;

// وضعیت ext lq (DOWN)
static datetime g_lq_time_seen_d   = 0;
static bool     g_marked_for_lq_d  = false;

// وقتی ext lq (DOWN) به‌روزرسانی شد
inline void Hunter_Down_OnExtLQUpdated()
{
   g_lq_time_seen_d  = ExtLQ_Down_Has() ? ExtLQ_Down_Time() : 0;
   g_marked_for_lq_d = false;
}

// عبور از ext lq برای جهت نزولی ⇒ cross-up (بدنه یا شدو)
inline bool Hunter_Down_IsExtLQCross(const MqlRates &r)
{
   if(!ExtLQ_Down_Has()) return false;
   const double lq = ExtLQ_Down_Get();
   return (r.high >= lq || r.close > lq);
}

// ابطال Hunter (DOWN) قبل از شکست ext lq:
// اگر از بعد C1 تا قبل cross، Low < Low(C1) رخ بدهد ⇒ Hunter باطل.
inline bool Hunter_IsC1Invalidated_BeforeCross_DOWN(const MqlRates &rates[], const int n,
                                                    const int c1_index, const int cross_idx)
{
   if(c1_index < 0 || cross_idx < 0 || c1_index >= n || cross_idx >= n) return true;
   if(cross_idx <= c1_index) return true;

   const double lC1 = rates[c1_index].low;
   for(int i=c1_index+1; i<cross_idx; ++i)
   {
      if(rates[i].low < lC1) return true;
   }
   return false;
}

// فقط «اولین عبور معتبر» را نمایش بده
inline void Hunter_Down_TryMarkIfValid(const MqlRates &rates[], const int n,
                                       const int c1_index, const int cross_idx)
{
   if(!ExtLQ_Down_Has()) return;

   const datetime lqt = ExtLQ_Down_Time();
   if(lqt != g_lq_time_seen_d){ g_lq_time_seen_d = lqt; g_marked_for_lq_d = false; }
   if(g_marked_for_lq_d) return;

   // اگر قبل از شکست ext lq، Low(C1) شکسته شده ⇒ باطل
   if(Hunter_IsC1Invalidated_BeforeCross_DOWN(rates, n, c1_index, cross_idx))
      return;

   ++g_hw_counter_d;
   string tag = IntegerToString(g_hw_counter_d);

   if(InpDrawMarkers)
   {
      MarkV("HW_"+tag+"_C1", rates[c1_index].time, clrViolet);
      MarkV("HW_"+tag+"_X",  rates[cross_idx].time, clrMagenta);
   }
   g_marked_for_lq_d = true;

   if(InpDebugPrints)
      Print("[Hunter-DOWN] OK | C1=",T(rates[c1_index].time),
            " | CROSS=",T(rates[cross_idx].time),
            " | ext lq=",DoubleToString(ExtLQ_Down_Get(),_Digits));
}

#endif // WAVEBOT_HUNTER_DOWN_MQH
