//+------------------------------------------------------------------+
//| WaveBot - API (UP)                                               |
//| Scan W2 -> wait W3 (count + body-break), STRICT gate             |
//| Rules (UP):                                                      |
//|  • Overlap: W3 can start from cend (j >= cend).                  |
//|  • NEW (pre body-break, non-wick): if L < L(C1_W3) before body-  |
//|    break -> RESET W3 and restart from the same breaking bar.     |
//|  • Pre body-break (wick case): wick-up above H1 then L1 breaks   |
//|    down (wick/body) -> INVALIDATE W2 and restart from wick bar.  |
//|  • Post body-break: after body-break above H1_W2 but BEFORE W3   |
//|    finishes, if L < L(C1_W3) -> INVALIDATE W2 and restart from   |
//|    the body-break bar.                                           |
//+------------------------------------------------------------------+
#ifndef WAVEBOT_API_MQH
#define WAVEBOT_API_MQH

#include <WaveBot/Utils.mqh>
#include <WaveBot/Markers.mqh>
#include <WaveBot/Data.mqh>
#include <WaveBot/Bodies.mqh>
#include <WaveBot/Wave2.mqh>    // UP W2
#include <WaveBot/Wave3.mqh>    // UP W3
#include <WaveBot/ExtLQ.mqh>    // UP ext lq (cross-down)
#include <WaveBot/Hunter.mqh>   // UP hunter
#include <WaveBot/Hunter_BodyBreak.mqh>  // NEW: نمایش کندل بدنه‌شکن Hunter نسبت به ext lq (UP/DOWN)

// قفل C1 در سناریوی شدو (کمترین Low در بازه، با اسکیپ inside)
inline int IndexOfLeftmostMinLow_ExInside(const MqlRates &rates[], const bool &insideHL[],
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
   if(idx<0) idx = from;
   return idx;
}

// (اختیاری) جستجوی آخرین W2 – امضا بدون تغییر
bool FindMostRecentWave2_UP(const string sym, const ENUM_TIMEFRAMES tf,
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

      const int end=(a4>=0? a4:a3);
      if(end>lastEnd){ lastEnd=end; bc1=i; bc2=a2; bc3=a3; bc4=a4; }
      i=end;
   }
   if(lastEnd<0) return false;
   c1=bc1; c2=bc2; c3=bc3; c4=bc4;
   return true;
}

// اسکن کامل (UP): W2 -> WAIT_CONFIRM(W3) + Hunter + ExtLQ
int API_RunScanSequential_W2W3_Hunter(const string sym, const ENUM_TIMEFRAMES tf,
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

   // W2 جاری
   int c1=-1,c2=-1,c3=-1,c4=-1, cend=-1;

   // وضعیت W3 (UP)
   bool   have_w3=false;
   int    w3_c1=-1, k2=-1,k3=-1,k4=-1, w3_end=-1;

   // کاندید مسیر مستقیم (کمترین Low از cend به بعد)
   int    w3_cand=-1; double w3_cand_low=DBL_MAX;

   // شدو/ارتقای سطح بریک
   bool   wickActive=false;
   int    firstWickIdx=-1, wickBreakIdx=-1;
   double bodyBreakLevel=0.0;            // باید با «بدنه» به بالا شکسته شود
   bool   breakAchieved=false;
   int    bodyBreakIdx=-1;               // اندیس کندل بریک با بدنه

   while(idx < n)
   {
      if(state==SEARCH_W2)
      {
         bool found=false;
         for(int i=idx; i<n; ++i)
         {
            ExtLQ_OnBar(rates[i]);
            HW_BB_UP_OnBar(rates[i]);   // NEW (ایمن است؛ فقط پس از Seed فعال می‌شود)
 
            if(insideHL[i]) continue;

            int i2=-1,i3=-1,i4=-1;
            if(!CheckWave2_FromIndex_LocalOnly(rates, insideHL, bodyLowEff, bodyHighEff, n, i, i2, i3, i4))
               continue;

            c1=i; c2=i2; c3=i3; c4=i4; cend=(c4>=0?c4:c3);

            if(rates[c1].time<effective_start || rates[c1].time>to_time)
            { idx=cend+1; continue; }

            string tag=IntegerToString(pairs+1);
            if(InpDrawMarkers)
            {
               MarkV("W2_"+tag+"_C1", rates[c1].time, clrDeepSkyBlue);
               MarkV("W2_"+tag+"_C2", rates[c2].time, clrDodgerBlue);
               MarkV("W2_"+tag+"_C3", rates[c3].time, clrRoyalBlue);
               if(c4>=0) MarkV("W2_"+tag+"_C4", rates[c4].time, clrBlue);
            }
            if(InpDebugPrints) Print("#",tag," W2(UP) found @ ",T(rates[c1].time));

            // ریست وضعیت W3/wick
            have_w3=false; w3_c1=-1; k2=k3=k4=-1; w3_end=-1;
            w3_cand=-1;   w3_cand_low=DBL_MAX;

            wickActive=false; firstWickIdx=-1; wickBreakIdx=-1;
            bodyBreakLevel = rates[c1].high;   // H1_W2
            breakAchieved  = false;
            bodyBreakIdx   = -1;

            idx=cend; state=WAIT_CONFIRM; found=true; break;
         }
         if(!found) break;
      }
      else // ============================ WAIT_CONFIRM ============================
      {
         const double H1_W2 = rates[c1].high;
         const double L1_W2 = rates[c1].low;
         string tag=IntegerToString(pairs+1);
         bool progressed=false;

         for(int j=idx; j<n; ++j)
         {
            ExtLQ_OnBar(rates[j]);
            if(Hunter_IsExtLQCross(rates[j]))
               Hunter_TryMarkIfValid(rates, n, c1, j);
            HW_BB_UP_OnBar(rates[j]);   // NEW

            if(insideHL[j]) continue;

            // ارتقای سطح بریک با شدو (رو به بالا)
            if(!breakAchieved)
            {
               if(rates[j].high > bodyBreakLevel)
               {
                  if(rates[j].close > bodyBreakLevel)
                  {
                     breakAchieved = true;      // BODY-BREAK بالای سطح
                     bodyBreakIdx  = j;
                  }
                  else
                  {
                     bodyBreakLevel = rates[j].high; // ارتقا با شدو
                     if(firstWickIdx < 0)
                     {
                        firstWickIdx = j;       // کندلی که برای نخستین بار H1 را با شدو شکست
                        wickBreakIdx = j;
                        wickActive   = true;

                        // قفل C1: کمترین Low بین [cend..firstWickIdx]
                        int anchorC1 = IndexOfLeftmostMinLow_ExInside(rates, insideHL, cend, firstWickIdx);
                        have_w3=false; w3_c1 = anchorC1;

                        // مسیر مستقیم را کنار بگذار
                        w3_cand=-1; w3_cand_low=DBL_MAX;
                     }
                  }
               }
            }

            // ابطال W2 قبل از بریک (سناریوی ویک: wick-up سپس شکست L1)
            if(!breakAchieved && firstWickIdx>=0 &&
               (rates[j].low < L1_W2 || rates[j].close < L1_W2))
            {
               if(InpDebugPrints)
                  Print("#",tag," W2(UP) INVALIDATED (wick-up then L1 broken).",
                        " Restart from wick bar @ ",T(rates[firstWickIdx].time));
               idx = firstWickIdx; state = SEARCH_W2; progressed = true; break;
            }

            // ================= NEW: RESET W3 (pre body-break, NON-WICK) =================
            // اگر قبل از بریک با بدنه و در مسیر غیر ویکی، Low از Low(C1_W3) عبور کند،
            // شمارش W3 از همان کندلِ متخلف از نو آغاز می‌شود.
            if(!wickActive && !breakAchieved)
            {
               int c1_eff = (w3_c1>=0 ? w3_c1 : w3_cand); // کاندید جاری C1 در هر دو مسیر
               if(c1_eff >= 0 && rates[j].low < rates[c1_eff].low)
               {
                  if(InpDebugPrints)
                     Print("#",tag," W3(UP) RESET (non-wick): L < L(C1) before body-break. Restart W3 from this bar.");
                  have_w3=false; w3_end=-1; k2=k3=k4=-1;
                  w3_c1 = -1;
                  w3_cand     = j;                 // همان کندل، C1 جدید
                  w3_cand_low = rates[j].low;
                  continue;
               }
            }
            // ============================================================================

            // مسیر مستقیم: انتخاب C1 از خود cend به بعد (هم‌پوشانی مجاز)
            if(!wickActive)
            {
               if(j >= cend && (w3_cand < 0 || rates[j].low < w3_cand_low))
               {
                  w3_cand     = j;                 // ممکن است j == cend باشد
                  w3_cand_low = rates[j].low;
                  have_w3     = false;
               }
            }

            // انتخاب startIdx برای شمارش W3
            int startIdx = -1;
            if(w3_c1  >= 0)       startIdx = w3_c1;     // مسیر ویکی (قفل)
            else if(w3_cand >= 0) startIdx = w3_cand;   // مسیر مستقیم

            // شمارش W3 (UP) — قوانین «اسکیپ inside» + «barrier» در Wave3.mqh اعمال می‌شود
            if(!have_w3 && startIdx >= 0 && !insideHL[startIdx])
            {
               int a2=-1,a3=-1,a4=-1, w3e=-1;
               if(CheckWave3CountOnly_Local(rates, insideHL, bodyLowEff, bodyHighEff, n,
                                            startIdx, a2, a3, a4, w3e))
               {
                  have_w3=true;
                  if(w3_c1 < 0) w3_c1 = startIdx;
                  k2=a2; k3=a3; k4=a4; w3_end=w3e;
               }
            }

            // ابطال W2 پس از بریک (قبل از اتمام W3): L < L(C1_W3)
            if(breakAchieved && !have_w3)
            {
               int c1_eff = (w3_c1>=0 ? w3_c1 : w3_cand);
               if(c1_eff >= 0 && rates[j].low < rates[c1_eff].low)
               {
                  if(InpDebugPrints)
                     Print("#",tag," W2(UP) INVALIDATED after body-break: L < L(C1_W3).",
                           " Restart from body-break @ ",T(rates[bodyBreakIdx>=0?bodyBreakIdx:j].time));
                  idx = (bodyBreakIdx>=0 ? bodyBreakIdx : j);
                  state = SEARCH_W2;
                  progressed = true;
                  break;
               }
            }

            // نهایی‌سازی: هر دو شرط لازم (شمارش W3 + بریک با بدنه)
            if(have_w3 && breakAchieved)
            {
               if(InpDrawMarkers)
               {
                  MarkV("W3_"+tag+"_C1", rates[w3_c1].time,  clrLime);
                  MarkV("W3_"+tag+"_C2", rates[k2].time,     clrSpringGreen);
                  MarkV("W3_"+tag+"_C3", rates[k3].time,     clrGreen);
                  if(k4>=0) MarkV("W3_"+tag+"_C4", rates[k4].time, clrDarkGreen);
               }
            
               // ext lq جدید (UP)
               ExtLQ_Set(rates[w3_c1].low, rates[w3_c1].time);
               Hunter_OnExtLQUpdated();
            
               // --- NEW: Strong Wave (UP) بر اساس بذر ثبت‌شده توسط Hunter
               SW_UP_TryMarkOnConfirmedW3(rates, n, w3_c1, bodyBreakIdx);
            
               if(InpDebugPrints)
                  Print("#",tag," Pair(UP) OK | W3 C1=",T(rates[w3_c1].time),
                        " | body-break @ ",T(rates[bodyBreakIdx>=0?bodyBreakIdx:idx].time));
            
               idx=j; state=SEARCH_W2; ++pairs; progressed=true; break;
            }
         }

         if(!progressed)
         {
            if(InpDebugPrints)
               Print("W2(UP) @ ",T(rates[c1].time),
                     " NOT confirmed (W3 not done / reset / W2 invalidated). STRICT gate.");
            break;
         }
      }
   }

   if(InpDebugPrints)
      Print("STRICT(UP): pairs=",pairs,
            (ExtLQ_Has()? StringFormat(" | ext lq=%.5f",ExtLQ_Get()) : " | ext lq:n/a"));
   return pairs;
}

// اجرای سریع روی [0..now]
void API_ShowMostRecent_W2W3_Hunter(const string sym, const ENUM_TIMEFRAMES tf, const int /*lookback*/)
{
   datetime start=0, stop=TimeCurrent();
   API_RunScanSequential_W2W3_Hunter(sym, tf, start, stop);
}

#endif // WAVEBOT_API_MQH
