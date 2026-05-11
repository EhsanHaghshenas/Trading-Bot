
#ifndef WAVEBOT_BOOTSTRAP_MQH
#define WAVEBOT_BOOTSTRAP_MQH

#include <WaveBot/Types.mqh>   // Direction اینجا تعریف شده
#include <WaveBot/Utils.mqh>
#include <WaveBot/Data.mqh>
#include <WaveBot/Bodies.mqh>
#include <WaveBot/Wave2.mqh>         // UP W2
#include <WaveBot/Wave3.mqh>         // UP W3
#include <WaveBot/Wave2_Down.mqh>    // DOWN W2
#include <WaveBot/Wave3_Down.mqh>    // DOWN W3
#include <WaveBot/W2W3_ChainInvalidation.mqh>

// خروجی بوت‌استرپ (همان‌طور که قبلاً استفاده می‌کردیم)
struct BootOutcome
{
   bool      ok;
   Direction mode;
   int       complete_index;   // ایندکس کندل body-break
   datetime  complete_time;    // زمان body-break
};

// ------------------------ اسکن «فقط اولین جفت کامل‌شده» (UP) ------------------------
bool Boot_FindFirstPair_UP(const string sym, const ENUM_TIMEFRAMES tf,
                           const datetime from_time, const datetime to_time,
                           int &out_bodyBreakIdx, datetime &out_bodyBreakTime)
{
   out_bodyBreakIdx = -1; out_bodyBreakTime = 0;

   const int tfsec = PeriodSeconds(tf);
   const int HISTORY_SKIP_BARS = 0;
   datetime effective_start = from_time + (HISTORY_SKIP_BARS * tfsec);
   datetime from_adj = from_time - tfsec*10;

   MqlRates rates[]; int n = LoadRatesRange(sym, tf, from_adj, to_time, rates);
   if(n<=0) return false;

   double bodyLowEff[], bodyHighEff[]; BuildEffectiveBodies(rates, n, bodyLowEff, bodyHighEff);
   bool insideHL[];                    BuildInsideClusterFlagsHL(rates, n, insideHL);

   int first_eff=0; while(first_eff<n && rates[first_eff].time<effective_start) first_eff++;
   int idx = MathMax(0, first_eff-2);

   enum State { SEARCH_W2, WAIT_CONFIRM };
   State state = SEARCH_W2;

   // W2 جاری
   int c1=-1,c2=-1,c3=-1,c4=-1, cend=-1;

   // وضعیت W3 (UP)
   bool   have_w3=false;
   int    w3_c1=-1, k2=-1,k3=-1,k4=-1, w3_end=-1;

   // مسیر مستقیم (کمترین Low از cend به بعد)
   int    w3_cand=-1; double w3_cand_low=DBL_MAX;

   // مدیریت بریک/ویک
   bool   wickActive=false;
   int    firstWickIdx=-1, wickBreakIdx=-1;
   double bodyBreakLevel=0.0;  // باید با «بدنه» به بالا شکسته شود
   bool   breakAchieved=false;
   int    bodyBreakIdx=-1;

   while(idx < n)
   {
      if(state==SEARCH_W2)
      {
         bool found=false;
         for(int i=idx; i<n; ++i)
         {
            if(insideHL[i]) continue;

            int i2=-1,i3=-1,i4=-1;
            if(!CheckWave2_FromIndex_LocalOnly(rates, insideHL, bodyLowEff, bodyHighEff, n, i, i2, i3, i4))
               continue;

            c1=i; c2=i2; c3=i3; c4=i4; cend=(c4>=0?c4:c3);

            if(rates[c1].time<effective_start || rates[c1].time>to_time)
            { idx=cend+1; continue; }

            // ریست W3/wick
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
      else // ============================ WAIT_CONFIRM (UP) ============================
      {
         const double H1_W2 = rates[c1].high;
         const double L1_W2 = rates[c1].low;

         bool progressed=false;

         for(int j=idx; j<n; ++j)
         {
            if(insideHL[j]) continue;

            // ارتقای سطح بریک با شدو (رو به بالا)
            if(!breakAchieved)
            {
               if(rates[j].high > bodyBreakLevel)
               {
                  if(rates[j].close > bodyBreakLevel)
                  { breakAchieved = true; bodyBreakIdx = j; }
                  else
                  {
                     bodyBreakLevel = rates[j].high; // ارتقا با شدو
                     if(firstWickIdx < 0)
                     {
                        firstWickIdx = j; wickBreakIdx = j; wickActive = true;
                        // قفل C1: کمترین Low بین [cend..firstWickIdx]، با اسکیپ inside
                        int anchorC1 = IndexOfLeftmostMinLow_ExInside(rates, insideHL, cend, firstWickIdx);
                        have_w3=false; w3_c1 = anchorC1;
                        // مسیر مستقیم را کنار بگذار
                        w3_cand=-1; w3_cand_low=DBL_MAX;
                     }
                  }
               }
            }

            // --- NEW: Chain-Invalidation of W2 & W3 in wick-window (pre body-break)
            {
               int __rew = -1;
               if(ChainInv_PreBody_WickWindow_UP_OnBar(
                     rates, insideHL, n, j,
                     breakAchieved, wickActive, firstWickIdx,
                     w3_c1, w3_cand, __rew))
               {
                  if(InpDebugPrints)
                     Print("[BOOT:ChainInv-UP] W2 & W3 INVALID (pre-body, wick-window via C1_W3 break).",
                           " Rewind to wick @ ", T(rates[__rew].time));
                  idx = __rew; state = SEARCH_W2; progressed = true; break;
               }
            }

            // RESET W3 (قبل از body-break، غیر-ویکی): L < L(C1_W3)
            if(!wickActive && !breakAchieved)
            {
               int c1_eff = (w3_c1>=0 ? w3_c1 : w3_cand);
               if(c1_eff >= 0 && rates[j].low < rates[c1_eff].low)
               {
                  have_w3=false; w3_end=-1; k2=k3=k4=-1;
                  w3_c1 = -1;
                  w3_cand     = j;
                  w3_cand_low = rates[j].low;
                  continue;
               }
            }

            // مسیر مستقیم: C1 از cend به بعد
            if(!wickActive)
            {
               if(j >= cend && (w3_cand < 0 || rates[j].low < w3_cand_low))
               {
                  w3_cand     = j;
                  w3_cand_low = rates[j].low;
                  have_w3     = false;
               }
            }

            // انتخاب startIdx برای شمارش W3
            int startIdx = -1;
            if(w3_c1  >= 0)       startIdx = w3_c1;     // مسیر ویکی
            else if(w3_cand >= 0) startIdx = w3_cand;   // مسیر مستقیم

            // شمارش W3 (UP)
            if(!have_w3 && startIdx >= 0 && !insideHL[startIdx])
            {
               int a2=-1,a3=-1,a4=-1, w3e=-1;
               if(CheckWave3CountOnly_Local(rates, insideHL, bodyLowEff, bodyHighEff, n, startIdx, a2, a3, a4, w3e))
               {
                  have_w3=true;
                  if(w3_c1 < 0) w3_c1 = startIdx;
                  k2=a2; k3=a3; k4=a4; w3_end=w3e;
               }
            }

            // ابطال W2 پس از بریک و قبل از اتمام W3: L < L(C1_W3)
            if(breakAchieved && !have_w3)
            {
               int c1_eff = (w3_c1>=0 ? w3_c1 : w3_cand);
               if(c1_eff >= 0 && rates[j].low < rates[c1_eff].low)
               {
                  idx = (bodyBreakIdx>=0 ? bodyBreakIdx : j);
                  state = SEARCH_W2; progressed = true; break;
               }
            }

            // نهایی‌سازی: هر دو شرط لازم (شمارش W3 + بریک با بدنه)
            if(have_w3 && breakAchieved)
            {
               out_bodyBreakIdx  = (bodyBreakIdx>=0? bodyBreakIdx : j);
               out_bodyBreakTime = rates[out_bodyBreakIdx].time;
               return true; // فقط اولین جفت
            }
         }

         if(!progressed) break;
      }
   }
   return false;
}

// ------------------------ اسکن «فقط اولین جفت کامل‌شده» (DOWN) ------------------------
bool Boot_FindFirstPair_DOWN(const string sym, const ENUM_TIMEFRAMES tf,
                             const datetime from_time, const datetime to_time,
                             int &out_bodyBreakIdx, datetime &out_bodyBreakTime)
{
   out_bodyBreakIdx = -1; out_bodyBreakTime = 0;

   const int tfsec = PeriodSeconds(tf);
   const int HISTORY_SKIP_BARS = 0;
   datetime effective_start = from_time + (HISTORY_SKIP_BARS * tfsec);
   datetime from_adj = from_time - tfsec*10;

   MqlRates rates[]; int n = LoadRatesRange(sym, tf, from_adj, to_time, rates);
   if(n<=0) return false;

   double bodyLowEff[], bodyHighEff[]; BuildEffectiveBodies(rates, n, bodyLowEff, bodyHighEff);
   bool insideHL[];                    BuildInsideClusterFlagsHL(rates, n, insideHL);

   int first_eff=0; while(first_eff<n && rates[first_eff].time<effective_start) first_eff++;
   int idx = MathMax(0, first_eff-2);

   enum State { SEARCH_W2, WAIT_CONFIRM };
   State state = SEARCH_W2;

   // current W2 (DOWN)
   int c1=-1,c2=-1,c3=-1,c4=-1, cend=-1;

   // W3 state (DOWN)
   bool   have_w3=false;
   int    w3_c1=-1, k2=-1,k3=-1,k4=-1, w3_end=-1;

   // direct-path candidate for C1 (بزرگ‌ترین High از cend به بعد)
   int    w3_cand=-1; double w3_cand_high=-DBL_MAX;

   // wick-path & body-break
   bool   wickActive=false;
   int    firstWickIdx=-1, wickBreakIdx=-1;
   double bodyBreakLevel=0.0;     // باید با بدنه زیر سطح بسته شود
   bool   breakAchieved=false;
   int    bodyBreakIdx=-1;

   while(idx < n)
   {
      if(state==SEARCH_W2)
      {
         bool found=false;
         for(int i=idx; i<n; ++i)
         {
            if(insideHL[i]) continue;

            int i2=-1,i3=-1,i4=-1;
            if(!CheckWave2_FromIndex_LocalOnly_Down(rates, insideHL, bodyLowEff, bodyHighEff, n, i, i2, i3, i4))
               continue;

            c1=i; c2=i2; c3=i3; c4=i4; cend=(c4>=0?c4:c3);

            if(rates[c1].time<effective_start || rates[c1].time>to_time)
            { idx=cend+1; continue; }

            // reset W3 state
            have_w3=false; w3_c1=-1; k2=k3=k4=-1; w3_end=-1;
            w3_cand=-1;   w3_cand_high=-DBL_MAX;

            wickActive=false; firstWickIdx=-1; wickBreakIdx=-1;
            bodyBreakLevel = rates[c1].low;  // L1_W2
            breakAchieved  = false;
            bodyBreakIdx   = -1;

            idx=cend; state=WAIT_CONFIRM; found=true; break;
         }
         if(!found) break;
      }
      else // ============================ WAIT_CONFIRM (DOWN) ============================
      {
         const double L1_W2 = rates[c1].low;

         bool progressed=false;

         for(int j=idx; j<n; ++j)
         {
            if(insideHL[j]) continue;

            // wick escalation (DOWN)
            if(!breakAchieved)
            {
               if(rates[j].low < bodyBreakLevel)
               {
                  if(rates[j].close < bodyBreakLevel)
                  { breakAchieved = true; bodyBreakIdx = j; }
                  else
                  {
                     bodyBreakLevel = rates[j].low; // ارتقا با شدو
                     if(firstWickIdx < 0)
                     {
                        firstWickIdx = j; wickBreakIdx = j; wickActive = true;
                        // lock C1: بیشترین High بین [cend..firstWickIdx]، با اسکیپ inside
                        int anchorC1 = IndexOfLeftmostMaxHigh_ExInside(rates, insideHL, cend, firstWickIdx);
                        have_w3=false; w3_c1 = anchorC1;
                        w3_cand=-1;   w3_cand_high=-DBL_MAX;
                     }
                  }
               }
            }

            // --- NEW: Chain-Invalidation of W2 & W3 in wick-window (pre body-break)
            {
               int __rew = -1;
               if(ChainInv_PreBody_WickWindow_DN_OnBar(
                     rates, insideHL, n, j,
                     breakAchieved, wickActive, firstWickIdx,
                     w3_c1, w3_cand, __rew))
               {
                  if(InpDebugPrints)
                     Print("[BOOT:ChainInv-DOWN] W2 & W3 INVALID (pre-body, wick-window via C1_W3 break).",
                           " Rewind to wick @ ", T(rates[__rew].time));
                  idx = __rew; state = SEARCH_W2; progressed = true; break;
               }
            }

            // RESET W3 (قبل از body-break، غیر-ویکی): H > H(C1_W3)
            if(!wickActive && !breakAchieved)
            {
               int c1_eff = (w3_c1>=0 ? w3_c1 : w3_cand);
               if(c1_eff >= 0 && rates[j].high > rates[c1_eff].high)
               {
                  have_w3=false; w3_end=-1; k2=k3=k4=-1;
                  w3_c1 = -1;
                  w3_cand      = j;
                  w3_cand_high = rates[j].high;
                  continue;
               }
            }

            // مسیر مستقیم: بزرگ‌ترین High از cend به بعد
            if(!wickActive)
            {
               if(j >= cend && (w3_cand < 0 || rates[j].high > w3_cand_high))
               {
                  w3_cand      = j;
                  w3_cand_high = rates[j].high;
                  have_w3      = false;
               }
            }

            // انتخاب startIdx برای شمارش W3
            int startIdx = -1;
            if(w3_c1  >= 0)       startIdx = w3_c1;     // مسیر ویکی
            else if(w3_cand >= 0) startIdx = w3_cand;   // مسیر مستقیم

            // شمارش W3 (DOWN)
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

            // POST body-break ولی قبل از اتمام W3: H > H(C1_W3) ⇒ invalidate W2
            if(breakAchieved && !have_w3)
            {
               int c1_eff = (w3_c1>=0 ? w3_c1 : w3_cand);
               if(c1_eff >= 0 && rates[j].high > rates[c1_eff].high)
               {
                  idx = (bodyBreakIdx>=0 ? bodyBreakIdx : j);
                  state = SEARCH_W2; progressed = true; break;
               }
            }

            // نهایی‌سازی: هر دو شرط لازم (شمارش W3 + بریک با بدنه)
            if(have_w3 && breakAchieved)
            {
               out_bodyBreakIdx  = (bodyBreakIdx>=0? bodyBreakIdx : j);
               out_bodyBreakTime = rates[out_bodyBreakIdx].time;
               return true; // فقط اولین جفت
            }
         }

         if(!progressed) break;
      }
   }
   return false;
}

// ----------------------------- ریس و تشخیص Mode اولیه -----------------------------
BootOutcome Bootstrap_RaceDetect(const string sym, const ENUM_TIMEFRAMES tf,
                                 const datetime from_time, const datetime to_time)
{
   BootOutcome out; out.ok=false; out.mode=DIR_UP; out.complete_index=-1; out.complete_time=0;

   int u_idx=-1, d_idx=-1; datetime u_t=0, d_t=0;
   bool up_ok   = Boot_FindFirstPair_UP(sym, tf, from_time, to_time, u_idx, u_t);
   bool down_ok = Boot_FindFirstPair_DOWN(sym, tf, from_time, to_time, d_idx, d_t);

   if(!up_ok && !down_ok) return out;

   if( up_ok && !down_ok){ out.ok=true; out.mode=DIR_UP;   out.complete_index=u_idx; out.complete_time=u_t; return out; }
   if(!up_ok &&  down_ok){ out.ok=true; out.mode=DIR_DOWN; out.complete_index=d_idx; out.complete_time=d_t; return out; }

   // هر دو پیدا شدند: هر کدام زودتر body-break داده، برنده است
   if(u_t <= d_t){ out.ok=true; out.mode=DIR_UP;   out.complete_index=u_idx; out.complete_time=u_t; }
   else          { out.ok=true; out.mode=DIR_DOWN; out.complete_index=d_idx; out.complete_time=d_t; }

   return out;
}

#endif // WAVEBOT_BOOTSTRAP_MQH

