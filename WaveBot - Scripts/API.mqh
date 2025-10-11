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
#include <WaveBot/Hunter_BodyBreak.mqh>  // NEW: ????? ???? ???????? Hunter ???? ?? ext lq (UP/DOWN)
#include <WaveBot/RaceCoordinator.mqh>
#include <WaveBot/C1W2Gate.mqh>
#include <WaveBot/W2W3_ChainInvalidation.mqh>

// ??? C1 ?? ??????? ??? (?????? Low ?? ????? ?? ????? inside)
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

// (???????) ?????? ????? W2 - ???? ???? ?????
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

// ???? ???? (UP): W2 -> WAIT_CONFIRM(W3) + Hunter + ExtLQ
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

   // W2 ????
   int c1=-1,c2=-1,c3=-1,c4=-1, cend=-1;

   // ????? W3 (UP)
   bool   have_w3=false;
   int    w3_c1=-1, k2=-1,k3=-1,k4=-1, w3_end=-1;

   // ?????? ???? ?????? (?????? Low ?? cend ?? ???)
   int    w3_cand=-1; double w3_cand_low=DBL_MAX;

   // ???/?????? ??? ????
   bool   wickActive=false;
   int    firstWickIdx=-1, wickBreakIdx=-1;
   double bodyBreakLevel=0.0;            // ???? ?? "????" ?? ???? ????? ???
   bool   breakAchieved=false;
   int    bodyBreakIdx=-1;               // ????? ???? ???? ?? ????
   // --- Guard: detect any post body-break C1_W3 change until W3 completes
   bool   postBreak_c1_lock = false;
   int    postBreak_c1_ref  = -1;

   while(idx < n)
   {
      if(state==SEARCH_W2)
      {
         bool found=false;
         for(int i=idx; i<n; ++i)
         {
            ExtLQ_OnBar(rates[i]);
            HW_BB_UP_OnBar(rates[i], rates, n, i);   // NEW (???? ???? ??? ?? ?? Seed ???? ??????)
 
            if(insideHL[i]) continue;
            
            bool __reanched = false;
            if(!C1W2_UP_ShouldAllowAt(rates, i, __reanched))
            {
               // ???? ?????? ?????? ????? ? ??? ???????/?????? ????? ????
               ExtLQ_OnBar(rates[i]);
               HW_BB_UP_OnBar(rates[i], rates, n, i);
               continue;
            }
            // ??? __reanched == true ??? ???? ???? ???? i ?????? ???? ??? ? ??????? ?? ???? ????? W2 ?? ?? ?? ????.

            int i2=-1,i3=-1,i4=-1;
            if(!CheckWave2_FromIndex_LocalOnly(rates, insideHL, bodyLowEff, bodyHighEff, n, i, i2, i3, i4))
               continue;

            c1=i; c2=i2; c3=i3; c4=i4; cend=(c4>=0?c4:c3);

            if(rates[c1].time<effective_start || rates[c1].time>to_time)
            { idx=cend+1; continue; }

            string tag = IntegerToString(pairs+1);
            if(InpDrawMarkers)
            {
               // NEW: clear old markers for this attempt (prevents orphan C4)
               W2_ClearTag(tag);
            
               MarkV("W2_"+tag+"_C1", rates[c1].time, clrDeepSkyBlue);
               MarkV("W2_"+tag+"_C2", rates[c2].time, clrDodgerBlue);
               MarkV("W2_"+tag+"_C3", rates[c3].time, clrRoyalBlue);
               if(c4 >= 0) MarkV("W2_"+tag+"_C4", rates[c4].time, clrBlue);
            }

            if(InpDebugPrints) Print("#",tag," W2(UP) found @ ",T(rates[c1].time));

            // ???? ????? W3/wick
            have_w3=false; w3_c1=-1; k2=k3=k4=-1; w3_end=-1;
            w3_cand=-1;   w3_cand_low=DBL_MAX;

            wickActive=false; firstWickIdx=-1; wickBreakIdx=-1;
            bodyBreakLevel = rates[c1].high;   // H1_W2
            breakAchieved  = false;
            bodyBreakIdx   = -1;
            C1W2_UP_OnW2Locked();
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

            Race_OnBar_UP(rates, insideHL, bodyLowEff, bodyHighEff, n, j);
            HW_BB_UP_OnBar(rates[j],rates, n, j);

            //if(insideHL[j]) continue;

            // ?????? ??? ???? ?? ??? (?? ?? ????)
            if(!breakAchieved)
            {
               if(rates[j].high > bodyBreakLevel)
               {
                  if(rates[j].close > bodyBreakLevel)
                  {
                     breakAchieved = true;      // BODY-BREAK ????? ???
                     bodyBreakIdx  = j;
                     // Lock current C1 reference right after body-break (if any)
                     int __c1_eff = (w3_c1>=0 ? w3_c1 : w3_cand);
                     postBreak_c1_ref  = __c1_eff;
                     postBreak_c1_lock = (__c1_eff >= 0);
                  }
                  else
                  {
                     bodyBreakLevel = rates[j].high; // ????? ?? ???
                     if(firstWickIdx < 0)
                     {
                        firstWickIdx = j;       // ????? ?? ???? ?????? ??? H1 ?? ?? ??? ????
                        wickBreakIdx = j;
                        wickActive   = true;

                        // ??? C1: ?????? Low ??? [cend..firstWickIdx]
                        int anchorC1 = IndexOfLeftmostMinLow_ExInside(rates, insideHL, cend, firstWickIdx);
                        have_w3=false; w3_c1 = anchorC1;

                        // ???? ?????? ?? ???? ?????
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
                     Print("[ChainInv-UP] W2 & W3 INVALID (pre-body, wick-window via C1_W3 break).",
                           " Rewind to wick @ ", T(rates[__rew].time));
                  idx = __rew; state = SEARCH_W2; progressed = true; break;
               }
            }

            // ================= NEW: RESET W3 (pre body-break, NON-WICK) =================
            // ??? ??? ?? ???? ?? ???? ? ?? ???? ??? ????? Low ?? Low(C1_W3) ???? ????
            // ????? W3 ?? ???? ????? ????? ?? ?? ???? ??????.
            if(!wickActive && !breakAchieved)
            {
               int c1_eff = (w3_c1>=0 ? w3_c1 : w3_cand); // ?????? ???? C1 ?? ?? ?? ????
               if(c1_eff >= 0 && rates[j].low < rates[c1_eff].low)
               {
                  if(InpDebugPrints)
                     Print("#",tag," W3(UP) RESET (non-wick): L < L(C1) before body-break. Restart W3 from this bar.");
                  have_w3=false; w3_end=-1; k2=k3=k4=-1;
                  w3_c1 = -1;
                  w3_cand     = j;                 // ???? ????? C1 ????
                  w3_cand_low = rates[j].low;
                  continue;
               }
            }
            // ============================================================================

            // ???? ??????: ?????? C1 ?? ??? cend ?? ??? (????????? ????)
            if(!wickActive)
            {
               if(j >= cend && (w3_cand < 0 || rates[j].low < w3_cand_low))
               {
                  w3_cand     = j;                 // ???? ??? j == cend ????
                  w3_cand_low = rates[j].low;
                  have_w3     = false;
               }
            }

            // ?????? startIdx ???? ????? W3
            int startIdx = -1;
            if(w3_c1  >= 0)       startIdx = w3_c1;     // ???? ???? (???)
            else if(w3_cand >= 0) startIdx = w3_cand;   // ???? ??????

            // ????? W3 (UP) - ?????? "????? inside" + "barrier" ?? Wave3.mqh ????? ??????
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
            
            // Guard (UP): after body-break & before W3 completes, ANY change in C1_W3 => invalidate W2
            if(breakAchieved && !have_w3)
            {
               int __c1_now = (w3_c1>=0 ? w3_c1 : w3_cand);
            
               // if no lock yet (e.g., C1 formed after the body-break), lock the first seen C1
               if(!postBreak_c1_lock && __c1_now >= 0)
               {
                  postBreak_c1_ref  = __c1_now;
                  postBreak_c1_lock = true;
               }
               else
               // if locked and now changed => rollback W2 to the body-break bar
               if(postBreak_c1_lock && __c1_now >= 0 && __c1_now != postBreak_c1_ref)
               {
                  if(InpDebugPrints)
                     Print("#",tag," W2(UP) INVALIDATED (C1_W3 changed after body-break). Restart from body-break @ ",
                           T(rates[bodyBreakIdx>=0?bodyBreakIdx:j].time));
                  idx       = (bodyBreakIdx>=0 ? bodyBreakIdx : j);
                  state     = SEARCH_W2;
                  progressed= true;
                  break;
               }
            }
   
            // ????? W2 ?? ?? ???? (??? ?? ????? W3): L < L(C1_W3)
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

            // ??????????: ?? ?? ??? ???? (????? W3 + ???? ?? ????)
            if(have_w3 && breakAchieved)
            {
               if(InpDrawMarkers)
               {
                  MarkV("W3_"+tag+"_C1", rates[w3_c1].time,  clrLime);
                  MarkV("W3_"+tag+"_C2", rates[k2].time,     clrSpringGreen);
                  MarkV("W3_"+tag+"_C3", rates[k3].time,     clrGreen);
                  if(k4>=0) MarkV("W3_"+tag+"_C4", rates[k4].time, clrDarkGreen);
               }
            
               // ext lq ???? (UP)
               ExtLQ_Set(rates[w3_c1].low, rates[w3_c1].time);
               Hunter_OnExtLQUpdated();
            
               // --- NEW: Strong Wave (UP) ?? ???? ??? ??????? ???? Hunter
               SW_UP_TryMarkOnConfirmedW3(rates, n, w3_c1, bodyBreakIdx);
               // NEW: c1_w2 (UP) ? ?????? ??? = ???? ????? ???? W3
               C1W2_UP_Start(rates, (bodyBreakIdx>=0 ? bodyBreakIdx : idx));

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

// ????? ???? ??? [0..now]
void API_ShowMostRecent_W2W3_Hunter(const string sym, const ENUM_TIMEFRAMES tf, const int /*lookback*/)
{
   datetime start=0, stop=TimeCurrent();
   API_RunScanSequential_W2W3_Hunter(sym, tf, start, stop);
}

#endif // WAVEBOT_API_MQH
