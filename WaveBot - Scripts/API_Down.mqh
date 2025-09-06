//+------------------------------------------------------------------+
//| WaveBot - API_Down (mirror: no pivots, global inside, Hunter)   |
//+------------------------------------------------------------------+
#ifndef WAVEBOT_API_DOWN_MQH
#define WAVEBOT_API_DOWN_MQH

#include <WaveBot/Utils.mqh>
#include <WaveBot/Markers.mqh>
#include <WaveBot/Data.mqh>
#include <WaveBot/Bodies.mqh>
#include <WaveBot/Wave2_Down.mqh>
#include <WaveBot/Wave3_Down.mqh>
#include <WaveBot/ExtLQ_Down.mqh>
#include <WaveBot/Hunter_Down.mqh>

// بیشینه High (leftmost) در بازه [from..to] با اسکیپ inside-bar
int IndexOfLeftmostMaxHigh_ExInside(const MqlRates &rates[], const bool &insideHL[],
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
   if(idx<0) idx = from;
   return idx;
}

// نزدیک‌ترین W2 صرفاً برای نمایش سریع (سمت نزولی)
bool FindMostRecentWave2_Down(const string sym, const ENUM_TIMEFRAMES tf,
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
      if(!CheckWave2_FromIndex_LocalOnly_Down(rates, insideHL, bodyLowEff, bodyHighEff, n, i, a2, a3, a4))
         continue;

      int end=(a4>=0? a4:a3);
      if(end>lastEnd){ lastEnd=end; bc1=i; bc2=a2; bc3=a3; bc4=a4; }
      i=end;
   }
   if(lastEnd<0) return false;
   c1=bc1; c2=bc2; c3=bc3; c4=bc4;
   return true;
}

// ======================================================================
//  API_Down_RunScanSequential_W2W3_Hunter  (نسخه‌ی به‌روزشده با قوانین جدید)
// ======================================================================
int API_Down_RunScanSequential_W2W3_Hunter(const string sym, const ENUM_TIMEFRAMES tf,
                                           const datetime from_time, const datetime to_time)
{
   const int tfsec = PeriodSeconds(tf);
   const int HISTORY_SKIP_BARS = 3;
   datetime effective_start = from_time + (HISTORY_SKIP_BARS * tfsec);
   datetime from_adj = from_time - tfsec*10;

   MqlRates rates[]; int n = LoadRatesRange(sym, tf, from_adj, to_time, rates);
   if(n<=0){ if(InpDebugPrints) Print("LoadRatesRange failed"); return 0; }

   double bodyLowEff[], bodyHighEff[]; BuildEffectiveBodies(rates, n, bodyLowEff, bodyHighEff);
   bool insideHL[];                   BuildInsideClusterFlagsHL(rates, n, insideHL);

   int first_eff=0; while(first_eff<n && rates[first_eff].time<effective_start) first_eff++;
   int idx = MathMax(0, first_eff-2);

   enum State { SEARCH_W2, WAIT_CONFIRM };
   State state = SEARCH_W2;

   int pairs=0;

   // --- موج۲ جاری
   int c1=-1,c2=-1,c3=-1,c4=-1, cend=-1;

   // --- وضعیت موج۳ (DOWN)
   bool   have_w3=false;     // آیا شمارش W3 تکمیل شده؟
   int    w3_c1=-1, k2=-1, k3=-1, k4=-1, w3_end=-1;

   // --- کاندید C1 در مسیر بدون-شدو (بزرگ‌ترین High از cend به بعد)
   int    w3_cand=-1; double w3_cand_high=-DBL_MAX;

   // --- تبصره شدو/ارتقای سطح بریک
   bool   wickActive=false;
   int    firstWickIdx=-1, wickBreakIdx=-1;
   double bodyBreakLevel=0.0;     // سطح بریک با بدنه (زیر L1_W2 + ارتقای شدویی)
   bool   breakAchieved=false;

   while(idx < n)
   {
      if(state==SEARCH_W2)
      {
         bool found=false;
         for(int i=idx; i<n; ++i)
         {
            ExtLQ_Down_OnBar(rates[i]);
            if(insideHL[i]) continue;

            int i2=-1,i3=-1,i4=-1;
            if(!CheckWave2_FromIndex_LocalOnly_Down(rates,insideHL,bodyLowEff,bodyHighEff,n,i,i2,i3,i4))
               continue;

            c1=i; c2=i2; c3=i3; c4=i4; cend=(c4>=0?c4:c3);

            if(rates[c1].time<effective_start || rates[c1].time>to_time)
            { idx=cend+1; continue; }

            string tag=IntegerToString(pairs+1);
            if(InpDrawMarkers)
            {
               MarkV("W2_"+tag+"_C1", rates[c1].time, clrDeepPink);
               MarkV("W2_"+tag+"_C2", rates[c2].time, clrPlum);
               MarkV("W2_"+tag+"_C3", rates[c3].time, clrMediumVioletRed);
               if(c4>=0) MarkV("W2_"+tag+"_C4", rates[c4].time, clrCrimson);
            }
            if(InpDebugPrints) Print("#",tag," W2(DOWN) found @ ",T(rates[c1].time));

            // ریست وضعیت W3
            have_w3=false; w3_c1=-1; k2=k3=k4=-1; w3_end=-1;
            w3_cand=-1;   w3_cand_high=-DBL_MAX;

            wickActive=false; firstWickIdx=-1; wickBreakIdx=-1;
            bodyBreakLevel = rates[c1].low; // L1_W2
            breakAchieved  = false;

            idx=cend; state=WAIT_CONFIRM; found=true; break;
         }
         if(!found) break;
      }
      else // ============================ WAIT_CONFIRM ============================
      {
         const double L1_W2 = rates[c1].low;
         string tag=IntegerToString(pairs+1);
         bool progressed=false;

         for(int j=idx; j<n; ++j)
         {
            ExtLQ_Down_OnBar(rates[j]);                     // ext lq رزرو/بروز
            if(Hunter_Down_IsExtLQCross(rates[j]))          // Hunter: فقط «اولین عبور»
               Hunter_Down_MarkWithC1(rates, n, c1, j);

            // داخل-بار سراسری: همیشه اسکیپ
            if(insideHL[j]) continue;

            // --- ارتقای سطح بریک با شدو (قبل از شمارش W3)
            if(!breakAchieved)
            {
               if(rates[j].low < bodyBreakLevel)
               {
                  if(rates[j].close < bodyBreakLevel)
                  {
                     breakAchieved = true;                  // بریک با بدنه زیر سطح
                  }
                  else
                  {
                     bodyBreakLevel = rates[j].low;         // ارتقای سطح با شدو (رو به پایین)
                     if(firstWickIdx < 0)
                     {
                        firstWickIdx = j;
                        wickBreakIdx = j;
                        wickActive   = true;

                        // قفل C1 اولیه در سناریوی شدو (بزرگ‌ترین High بین پایان W2 تا اولین شدو)
                        int anchorC1 = IndexOfLeftmostMaxHigh_ExInside(rates, insideHL, cend, firstWickIdx);
                        have_w3=false; w3_c1 = anchorC1;
                        w3_cand = -1;  w3_cand_high = -DBL_MAX;
                     }
                  }
               }
            }

            // --- قانون جدید: ابطال W3 اگر Highِ C1 قبل از بریک با بدنه شکسته شد
            // این قاعده هم برای مسیر شدویی (w3_c1 قفل) و هم مسیر بدون شدو صدق می‌کند.
            if(!breakAchieved && w3_c1>=0 && rates[j].high > rates[w3_c1].high)
            {
               if(InpDebugPrints)
                  Print("#",tag," W3(DOWN) invalidated (H > H(C1) before body-break). Restart W3.");

               // ابطال فقط موج۳، موج۲ حفظ می‌شود (STRICT GATE)
               have_w3=false; w3_end=-1; k2=k3=k4=-1;

               // C1 قبلی دیگر معتبر نیست
               w3_c1 = -1;

               // از همین کندل به‌عنوان بزرگ‌ترین Highِ جدید شروع کن
               w3_cand      = j;
               w3_cand_high = rates[j].high;

               // در حالت ابطال، در همین state/loop ادامه بده
               continue;
            }

            // --- مسیر بدون شدو: انتخاب کاندید C1 از خود cend به بعد (j >= cend)
            if(!wickActive)
            {
               if(j >= cend && (w3_cand < 0 || rates[j].high > w3_cand_high))
               {
                  w3_cand      = j;               // اجازه: C1 می‌تواند خودِ cend هم باشد
                  w3_cand_high = rates[j].high;
                  have_w3      = false;
               }
            }

            // --- تعیین نقطه‌ی شروع شمارش W3
            int startIdx = -1;
            if(w3_c1 >= 0)          startIdx = w3_c1;   // مسیر شدویی (قفل)
            else if(w3_cand >= 0)   startIdx = w3_cand; // مسیر مستقیم

            // --- شمارش قدم‌های W3 نزولی (با اسکیپ همه‌ی inside ها و گاردِ barrier)
            if(!have_w3 && startIdx >= 0 && !insideHL[startIdx])
            {
               int a2=-1,a3=-1,a4=-1, w3e=-1;
               if(CheckWave3CountOnly_Local_Down(rates, insideHL, bodyLowEff, bodyHighEff, n, startIdx, a2, a3, a4, w3e))
               {
                  have_w3=true;
                  if(w3_c1 < 0) w3_c1 = startIdx;
                  k2=a2; k3=a3; k4=a4; w3_end=w3e;
               }
            }

            // --- نهایی‌سازی: هر دو شرط «شمارش W3» و «بریک با بدنه» لازم است
            if(have_w3 && breakAchieved)
            {
               if(InpDrawMarkers)
               {
                  MarkV("W3_"+tag+"_C1", rates[w3_c1].time,  clrFireBrick);
                  MarkV("W3_"+tag+"_C2", rates[k2].time,     clrTomato);
                  MarkV("W3_"+tag+"_C3", rates[k3].time,     clrBrown);
                  if(k4>=0) MarkV("W3_"+tag+"_C4", rates[k4].time, clrMaroon);
               }

               // ext lq جدید: Highِ C1_W3 (Down)  + Hunter reset
               ExtLQ_Down_Set(rates[w3_c1].high, rates[w3_c1].time);
               Hunter_Down_OnExtLQUpdated();

               if(InpDebugPrints)
                  Print("#",tag," Pair(DOWN) OK | W3 C1=",T(rates[w3_c1].time),
                        " | body-break @ ",T(rates[j].time));

               idx=j; state=SEARCH_W2; ++pairs; progressed=true; break;
            }
         }

         if(!progressed)
         {
            if(InpDebugPrints)
               Print("W2(DOWN) @ ",T(rates[c1].time)," NOT confirmed (no body-break or W3 reset). STRICT gate holds.");
            break;
         }
      }
   }

   if(InpDebugPrints)
      Print("STRICT(DOWN): pairs=",pairs,
            (ExtLQ_Down_Has()? StringFormat(" | ext lq=%.5f",ExtLQ_Down_Get()) : " | ext lq:n/a"));

   return pairs;
}


// نمایش سریع
void API_Down_ShowMostRecent_W2W3_Hunter(const string sym, const ENUM_TIMEFRAMES tf, const int /*lookback*/)
{
   datetime start=0, stop=TimeCurrent();
   API_Down_RunScanSequential_W2W3_Hunter(sym, tf, start, stop);
}

#endif // WAVEBOT_API_DOWN_MQH
