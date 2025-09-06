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

// کمترین Low (leftmost) در بازه [from..to] با اسکیپ inside-bar
int IndexOfLeftmostMinLow_ExInside(const MqlRates &rates[], const bool &insideHL[],
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
   // اگر تمام بازه inside بود، حداقل از from یک ایندکس برگردانیم
   if(idx<0) idx = from;
   return idx;
}

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
            ExtLQ_OnBar(rates[i]);                 // به‌روزرسانی رزروها

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
      else // WAIT_CONFIRM
      {
         const double H1_W2 = rates[c1].high;
         string tag=IntegerToString(pairs+1);
         bool progressed=false;
      
         // متغیرهای تبصره‌ی شدو / لنگر C1
         int  firstWickIdx   = -1;            // اولین شدوی عبوری
         int  anchorC1       = -1;            // C1 قفل‌شده پس از اولین شدو
         int  wickBreakIdx   = -1;
         double bodyBreakLevel = H1_W2;       // با شدو ارتقاء می‌یابد
         bool breakAchieved  = false;
         bool wickActive     = false;
      
         // کاندید داینامیک برای حالت «بدون شدوی قبلی»
         int    w3_cand=-1; double w3_cand_low=DBL_MAX;
      
         for(int j=idx; j<n; ++j)
         {
            ExtLQ_OnBar(rates[j]);                 // ext lq رزروها
      
            // Hunter: اگر از ext lq عبور شد، Hunter را با C1 موج۲ نشان بده
            if(Hunter_IsExtLQCross(rates[j]))
               Hunter_MarkWithC1(rates, n, c1, j);
      
            if(insideHL[j]) continue;
      
            // --- مدیریت شکست با بدنه/شدو و قفل کردن C1 روی اولین شدو ---
            if(!breakAchieved)
            {
               if(rates[j].high > bodyBreakLevel)
               {
                  if(rates[j].close > bodyBreakLevel)
                  {
                     breakAchieved = true; // بریک با بدنه
                  }
                  else
                  {
                     bodyBreakLevel = rates[j].high; // ارتقا با شدو
                     if(firstWickIdx < 0)
                     {
                        firstWickIdx = j;
                        wickBreakIdx = j;
                        wickActive   = true;
                        // قفل C1: کمترین Low بین پایان W2 تا اولین شدو
                        anchorC1 = IndexOfLeftmostMinLow_ExInside(rates, insideHL, cend, firstWickIdx);
                        // ریست شمارش تا از anchorC1 بشماریم
                        have_w3 = false;
                     }
                  }
               }
            }
      
            // اگر در فاز شدو هستیم و Low < Lowِ C1 قفل‌شده ⇒ ابطال
            if(wickActive && anchorC1>=0 && rates[j].low < rates[anchorC1].low)
            {
               if(InpDebugPrints)
                  Print("#",tag," W2 invalidated (fell below locked C1). Restart from ",T(rates[wickBreakIdx].time));
               idx=wickBreakIdx; state=SEARCH_W2; progressed=true; break;
            }
      
            // --- شمارش W3 ---
            int startIdx = -1;
            if(anchorC1 >= 0)            // مسیر شدویی: از C1 قفل‌شده بشمار
               startIdx = anchorC1;
            else
            {                            // مسیر بریکِ مستقیم: کمترین Low تا این لحظه
               if(j >= cend && (w3_cand < 0 || rates[j].low < w3_cand_low))
               {
                  w3_cand      = j;            // اجازه شروع از cend (C3 یا C4 موج۲ صعودی)
                  w3_cand_low  = rates[j].low;
                  have_w3      = false;
               }
               startIdx = w3_cand;
            }
      
            if(!have_w3 && startIdx>=0 && !insideHL[startIdx])
            {
               int a2=-1,a3=-1,a4=-1, w3e=-1;
               if(CheckWave3CountOnly_Local(rates, insideHL, bodyLowEff, bodyHighEff, n, startIdx, a2, a3, a4, w3e))
               {
                  have_w3=true; w3_c1=startIdx; k2=a2; k3=a3; k4=a4; w3_end=w3e;
               }
            }
      
            // --- نهایی‌سازی: دو شرط بدون ترتیب ---
            if(!breakAchieved && rates[j].close > bodyBreakLevel) breakAchieved = true;
      
            if(have_w3 && breakAchieved)
            {
               // رسم W3
               MarkV("W3_"+tag+"_C1", rates[w3_c1].time,  clrLime);
               MarkV("W3_"+tag+"_C2", rates[k2].time,     clrGreen);
               MarkV("W3_"+tag+"_C3", rates[k3].time,     clrTeal);
               if(k4>=0) MarkV("W3_"+tag+"_C4", rates[k4].time, clrSeaGreen);
      
               // ext lq جدید
               ExtLQ_Set(rates[w3_c1].low, rates[w3_c1].time);
               Hunter_OnExtLQUpdated();
      
               if(InpDebugPrints)
                  Print("#",tag," Pair OK | W3 C1 locked=",T(rates[w3_c1].time),
                        " | break-by-body @ ",T(rates[j].time));
      
               idx=j; state=SEARCH_W2; ++pairs; progressed=true; break;
            }
         }
      
         if(!progressed)
         {
            if(InpDebugPrints)
               Print("W2 @ ",T(rates[c1].time)," NOT confirmed by W3 until end-of-range (strict gate).");
            break;
         }
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
