//+------------------------------------------------------------------+
//| WaveBot - API (no pivots, global inside-skip, Hunter simple)     |
//+------------------------------------------------------------------+
#ifndef WAVEBOT_API_MQH
#define WAVEBOT_API_MQH

#include <WaveBot/Utils.mqh>
#include <WaveBot/Markers.mqh>
#include <WaveBot/Data.mqh>
#include <WaveBot/Bodies.mqh>
#include <WaveBot/Wave2.mqh>
#include <WaveBot/Wave3.mqh>
#include <WaveBot/ExtLQ.mqh>
#include <WaveBot/Hunter.mqh>

// نزدیک‌ترین W2 صرفاً برای نمایش سریع (بدون پیوت)
bool FindMostRecentWave2(const string sym, const ENUM_TIMEFRAMES tf,
                         const int lookback, int &c1, int &c2, int &c3, int &c4,
                         MqlRates &rates[], int &n)
{
   n = LoadRates(sym, tf, lookback, rates);
   if(n<=0){ if(InpDebugPrints) Print("LoadRates failed"); return false; }

   double bodyLowEff[], bodyHighEff[]; BuildEffectiveBodies(rates, n, bodyLowEff, bodyHighEff);
   bool insideHL[];                   BuildInsideClusterFlagsHL(rates, n, insideHL);

   int lastEnd=-1; int bc1=-1,bc2=-1,bc3=-1,bc4=-1;

   for(int i=0; i<n; ++i)
   {
      if(insideHL[i]) continue;

      int a2=-1,a3=-1,a4=-1;
      if(!CheckWave2_FromIndex_LocalOnly(rates, insideHL, bodyLowEff, bodyHighEff, n, i, a2, a3, a4))
         continue;

      int end=(a4>=0? a4:a3);
      if(end>lastEnd){ lastEnd=end; bc1=i; bc2=a2; bc3=a3; bc4=a4; }
      i=end;
   }
   if(lastEnd<0) return false;
   c1=bc1; c2=bc2; c3=bc3; c4=bc4;
   return true;
}

// اسکن کامل W2→W3 + Hunter (Hunter صرفاً نشانه‌گذاری عبور از ext lq)
int API_RunScanSequential_W2W3_Hunter(const string sym, const ENUM_TIMEFRAMES tf,
                                      const datetime from_time, const datetime to_time)
{
   const int tfsec = PeriodSeconds(tf);

   // اسکیپ ۳ کندل نخست بازه
   const int HISTORY_SKIP_BARS = 3;
   datetime effective_start = from_time + (HISTORY_SKIP_BARS * tfsec);

   // کمی عقب‌تر برای ایمنی
   datetime from_adj = from_time - tfsec*10;

   // داده
   MqlRates rates[]; int n = LoadRatesRange(sym, tf, from_adj, to_time, rates);
   if(n<=0){ if(InpDebugPrints) Print("LoadRatesRange failed"); return 0; }

   // کمکی‌ها
   double bodyLowEff[], bodyHighEff[]; BuildEffectiveBodies(rates, n, bodyLowEff, bodyHighEff);
   bool insideHL[];                   BuildInsideClusterFlagsHL(rates, n, insideHL);

   // شروع مؤثر
   int first_eff=0; while(first_eff<n && rates[first_eff].time<effective_start) first_eff++;
   int idx = MathMax(0, first_eff-2);

   enum State { SEARCH_W2, WAIT_CONFIRM };
   State state = SEARCH_W2;

   int pairs=0;

   // موج۲
   int c1=-1,c2=-1,c3=-1,c4=-1, cend=-1;

   // تایید W3
   bool have_w3=false, have_break=false;
   int  w3_c1=-1, k2=-1,k3=-1,k4=-1, w3_end=-1;
   int  w3_cand=-1; double w3_cand_low=DBL_MAX;

   // تبصره شدو
   bool   wickBreakActive=false;
   int    wickBreakIdx=-1; double wickBreakHigh=DBL_MIN;

   while(idx < n)
   {
      // -------- جستجوی W2
      if(state==SEARCH_W2)
      {
         bool found=false;
         for(int i=idx; i<n; ++i)
         {
            // Hunter (ساده): هر عبور از ext lq را همان لحظه مارک کن
            if(Hunter_IsExtLQCross(rates[i]))
               Hunter_MarkSimple(rates, n, i, InpMaxBarsInWave);

            if(insideHL[i]) continue;

            int i2=-1,i3=-1,i4=-1;
            if(!CheckWave2_FromIndex_LocalOnly(rates, insideHL, bodyLowEff, bodyHighEff, n, i, i2, i3, i4))
               continue;

            c1=i; c2=i2; c3=i3; c4=i4; cend=(c4>=0?c4:c3);

            if(rates[c1].time<effective_start || rates[c1].time>to_time)
            { idx=cend+1; continue; }

            string tag=IntegerToString(pairs+1);
            MarkV("W2_"+tag+"_C1", rates[c1].time, clrDeepSkyBlue);
            MarkV("W2_"+tag+"_C2", rates[c2].time, clrYellow);
            MarkV("W2_"+tag+"_C3", rates[c3].time, clrOrange);
            if(c4>=0) MarkV("W2_"+tag+"_C4", rates[c4].time, clrTomato);
            if(InpDebugPrints) Print("#",tag," W2 found @ ",T(rates[c1].time));

            // ریست تایید
            have_w3=false; have_break=false;
            w3_c1=-1; k2=k3=k4=-1; w3_end=-1;
            w3_cand=-1; w3_cand_low=DBL_MAX;
            wickBreakActive=false; wickBreakIdx=-1; wickBreakHigh=DBL_MIN;

            idx=cend; state=WAIT_CONFIRM; found=true; break;
         }
         if(!found) break;
      }
      // -------- تایید W3 + بریک با بدنه
      else
      {
         const double H1_W2 = rates[c1].high;
         string tag=IntegerToString(pairs+1);
         bool progressed=false;

         for(int j=idx; j<n; ++j)
         {
            // Hunter (ساده) در فاز تایید
            if(Hunter_IsExtLQCross(rates[j]))
               Hunter_MarkSimple(rates, n, j, InpMaxBarsInWave);

            if(insideHL[j]) continue;

            // کاندید C1_W3 = کمترین Low پس از cend
            if(j>cend && (w3_cand<0 || rates[j].low < w3_cand_low))
            { w3_cand=j; w3_cand_low=rates[j].low; have_w3=false; }

            // شمارش W3 (بدون رسم تا تایید نهایی)
            if(!have_w3 && w3_cand>=0 && !insideHL[w3_cand])
            {
               int a2=-1,a3=-1,a4=-1, w3e=-1;
               if(CheckWave3CountOnly_Local(rates, insideHL, bodyLowEff, bodyHighEff, n, w3_cand, a2, a3, a4, w3e))
               { have_w3=true; w3_c1=w3_cand; k2=a2; k3=a3; k4=a4; w3_end=w3e; }
            }

            // تبصره شدو
            if(w3_c1>=0 && rates[j].high > H1_W2 && rates[j].close <= H1_W2 && !wickBreakActive)
            { wickBreakActive=true; wickBreakIdx=j; wickBreakHigh=rates[j].high; }

            if(wickBreakActive)
            {
               if(rates[j].low < rates[w3_c1].low)
               {
                  if(InpDebugPrints) Print("#",tag," W2 invalidated (shadow clause). Restart from ",T(rates[wickBreakIdx].time));
                  idx=wickBreakIdx; state=SEARCH_W2; progressed=true; break;
               }
               if(rates[j].close > wickBreakHigh)
               { have_break=true; wickBreakActive=false; }
            }

            // بریک با بدنه مستقیم
            if(!have_break && rates[j].close > H1_W2) have_break=true;

            // تایید نهایی W2→W3
            if(have_break && have_w3)
            {
               MarkV("W3_"+tag+"_C1", rates[w3_c1].time,  clrLime);
               MarkV("W3_"+tag+"_C2", rates[k2].time,     clrGreen);
               MarkV("W3_"+tag+"_C3", rates[k3].time,     clrTeal);
               if(k4>=0) MarkV("W3_"+tag+"_C4", rates[k4].time, clrSeaGreen);

               ExtLQ_Set(rates[w3_c1].low, rates[w3_c1].time);

               if(InpDebugPrints) Print("#",tag," Pair OK | ext lq=",DoubleToString(ExtLQ_Get(),_Digits),
                                        " @ ",T(ExtLQ_Time())," | break-by-body @ ",T(rates[j].time));

               idx=j; state=SEARCH_W2; ++pairs; progressed=true; break;
            }
         }
         if(!progressed) break;
      }
   }

   if(InpDebugPrints)
      Print("STRICT pairs (no pivots) + Hunter(simple) + global inside-skip: ",pairs,
            (ExtLQ_Has()? StringFormat(" | ext lq=%.5f",ExtLQ_Get()) : " | ext lq: n/a"));

   return pairs;
}

// نمایش سریع
void API_ShowMostRecent_W2W3_Hunter(const string sym, const ENUM_TIMEFRAMES tf, const int /*lookback*/)
{
   datetime start=0, stop=TimeCurrent();
   API_RunScanSequential_W2W3_Hunter(sym, tf, start, stop);
}

#endif // WAVEBOT_API_MQH
