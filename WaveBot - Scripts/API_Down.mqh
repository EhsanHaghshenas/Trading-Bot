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
#include <WaveBot/Hunter_BodyBreak.mqh>  // NEW: نمایش کندل بدنه‌شکن Hunter نسبت به ext lq (UP/DOWN)
#include <WaveBot/RaceCoordinator.mqh>
#include <WaveBot/C1W2Gate.mqh>

// helper: leftmost max-high in [from..to] excluding inside bars
inline int IndexOfLeftmostMaxHigh_ExInside(const MqlRates &rates[], const bool &insideHL[],
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

// quick display (signature unchanged)
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
      if(!CheckWave2_FromIndex_LocalOnly_Down(rates,insideHL,bodyLowEff,bodyHighEff,n,i,a2,a3,a4))
         continue;

      const int end=(a4>=0? a4:a3);
      if(end>lastEnd){ lastEnd=end; bc1=i; bc2=a2; bc3=a3; bc4=a4; }
      i=end;
   }
   if(lastEnd<0) return false;
   c1=bc1; c2=bc2; c3=bc3; c4=bc4;
   return true;
}

// full scan (DOWN)
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

   // current W2 (DOWN)
   int c1=-1,c2=-1,c3=-1,c4=-1, cend=-1;

   // W3 state (DOWN)
   bool   have_w3=false;                 // fully counted?
   int    w3_c1=-1, k2=-1,k3=-1,k4=-1, w3_end=-1;

   // direct-path candidate for C1 (largest High from cend onward)
   int    w3_cand=-1; double w3_cand_high=-DBL_MAX;

   // wick-path & body-break management
   bool   wickActive=false;
   int    firstWickIdx=-1, wickBreakIdx=-1;
   double bodyBreakLevel=0.0;            // must break BELOW by body
   bool   breakAchieved=false;
   int    bodyBreakIdx=-1;               // remember bar index of the body-break

   while(idx < n)
   {
      if(state==SEARCH_W2)
      {
         bool found=false;
         for(int i=idx; i<n; ++i)
         {
            ExtLQ_Down_OnBar(rates[i]);
            HW_BB_DOWN_OnBar(rates[i], rates, n, i);
            
            if(insideHL[i]) continue;
            
            bool __reanched = false;
            if(!C1W2_DN_ShouldAllowAt(rates, i, __reanched))
            {
               ExtLQ_Down_OnBar(rates[i]);
               HW_BB_DOWN_OnBar(rates[i], rates, n, i);
               continue;
            }
            // اگر __reanched == true شد، همین کندل j کاندید جدید است ⇒ از همین کندل، شمارش W2 نزولی را از نو شروع کن.


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

            // reset W3 state
            have_w3=false; w3_c1=-1; k2=k3=k4=-1; w3_end=-1;
            w3_cand=-1;   w3_cand_high=-DBL_MAX;

            wickActive=false; firstWickIdx=-1; wickBreakIdx=-1;
            bodyBreakLevel = rates[c1].low;  // L1_W2
            breakAchieved  = false;
            bodyBreakIdx   = -1;

            idx=cend; state=WAIT_CONFIRM; found=true; break;
            C1W2_DN_OnW2Locked();
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
            ExtLQ_Down_OnBar(rates[j]);
            if(Hunter_Down_IsExtLQCross(rates[j]))
               Hunter_Down_TryMarkIfValid(rates, n, c1, j);
            
            Race_OnBar_DOWN(rates, insideHL, bodyLowEff, bodyHighEff, n, j);
            HW_BB_DOWN_OnBar(rates[j],rates, n, j);

            if(insideHL[j]) continue;

            // wick escalation (DOWN)
            if(!breakAchieved)
            {
               if(rates[j].low < bodyBreakLevel)
               {
                  if(rates[j].close < bodyBreakLevel)
                  {
                     breakAchieved = true;      // BODY-BREAK under level
                     bodyBreakIdx  = j;
                  }
                  else
                  {
                     bodyBreakLevel = rates[j].low; // wick escalation
                     if(firstWickIdx < 0)
                     {
                        firstWickIdx = j;
                        wickBreakIdx = j;
                        wickActive   = true;

                        // lock C1 on wick-path
                        int anchorC1 = IndexOfLeftmostMaxHigh_ExInside(rates, insideHL, cend, firstWickIdx);
                        have_w3=false; w3_c1 = anchorC1;

                        w3_cand=-1; w3_cand_high=-DBL_MAX;
                     }
                  }
               }
            }

            // PRE body-break (wick-path): rise above locked C1 -> invalidate W2
            if(wickActive && w3_c1>=0 && !breakAchieved && rates[j].high > rates[w3_c1].high)
            {
               if(InpDebugPrints)
                  Print("#",tag," W2(DOWN) invalidated (rose above locked C1 before body-break).");
               idx=wickBreakIdx; state=SEARCH_W2; progressed=true; break;
            }

            // ===== NEW: PRE body-break (non-wick) — reset W3 if H > H(C1_W3) =====
            if(!wickActive && !breakAchieved)
            {
               int c1_eff = (w3_c1>=0 ? w3_c1 : w3_cand);
               if(c1_eff >= 0 && rates[j].high > rates[c1_eff].high)
               {
                  if(InpDebugPrints)
                     Print("#",tag," W3(DOWN) RESET (non-wick): H > H(C1) before body-break. Restart W3 from this bar.");
                  // reset ONLY W3 and restart from the very bar that caused invalidation
                  have_w3=false; w3_end=-1; k2=k3=k4=-1;
                  w3_c1 = -1;
                  w3_cand      = j;
                  w3_cand_high = rates[j].high;
                  continue;
               }
            }
            // =====================================================================

            // POST body-break but BEFORE W3 finishes: H > H(C1_W3) -> invalidate W2
            if(breakAchieved && !have_w3)
            {
               int c1_eff = (w3_c1>=0 ? w3_c1 : w3_cand);
               if(c1_eff >= 0 && rates[j].high > rates[c1_eff].high)
               {
                  if(InpDebugPrints)
                     Print("#",tag," W2(DOWN) INVALIDATED after body-break: H > H(C1_W3). Restart @ ",T(rates[bodyBreakIdx>=0?bodyBreakIdx:j].time));
                  idx = (bodyBreakIdx>=0 ? bodyBreakIdx : j);
                  state = SEARCH_W2;
                  progressed = true;
                  break;
               }
            }

            // direct-path candidate (no wick): choose largest High from cend onward
            if(!wickActive)
            {
               if(j >= cend && (w3_cand < 0 || rates[j].high > w3_cand_high))
               {
                  w3_cand      = j;            // may be j == cend (overlap)
                  w3_cand_high = rates[j].high;
                  have_w3      = false;
               }
            }

            // choose start index for W3 counting
            int startIdx = -1;
            if(w3_c1  >= 0)       startIdx = w3_c1;     // wick-path (locked C1)
            else if(w3_cand >= 0) startIdx = w3_cand;   // direct-path

            // count W3 (DOWN)
            if(!have_w3 && startIdx >= 0 && !insideHL[startIdx])
            {
               int a2=-1,a3=-1,a4=-1, w3e=-1;
               if(CheckWave3CountOnly_Local_Down(rates, insideHL, bodyLowEff, bodyHighEff, n,
                                                 startIdx, a2, a3, a4, w3e))
               {
                  have_w3=true;
                  if(w3_c1 < 0) w3_c1 = startIdx;
                  k2=a2; k3=a3; k4=a4; w3_end=w3e;
               }
            }

            // finalize only when BOTH conditions are met
            if(have_w3 && breakAchieved)
            {
               if(InpDrawMarkers)
               {
                  MarkV("W3_"+tag+"_C1", rates[w3_c1].time,  clrFireBrick);
                  MarkV("W3_"+tag+"_C2", rates[k2].time,     clrTomato);
                  MarkV("W3_"+tag+"_C3", rates[k3].time,     clrBrown);
                  if(k4>=0) MarkV("W3_"+tag+"_C4", rates[k4].time, clrMaroon);
               }
            
               // ext lq جدید (DOWN)
               ExtLQ_Down_Set(rates[w3_c1].high, rates[w3_c1].time);
               Hunter_Down_OnExtLQUpdated();
            
               // --- NEW: Strong Wave (DOWN) بر اساس بذر Hunter
               SW_DOWN_TryMarkOnConfirmedW3(rates, n, w3_c1, bodyBreakIdx);
               // NEW: c1_w2 (DOWN) ⇒ کاندید اول = همان کندلِ بریک W3
               C1W2_DN_Start(rates, (bodyBreakIdx>=0 ? bodyBreakIdx : idx));

               if(InpDebugPrints)
                  Print("#",tag," Pair(DOWN) OK | W3 C1=",T(rates[w3_c1].time),
                        " | body-break @ ",T(rates[bodyBreakIdx>=0?bodyBreakIdx:idx].time));
            
               idx=j; state=SEARCH_W2; ++pairs; progressed=true; break;
            }
         }

         if(!progressed)
         {
            if(InpDebugPrints)
               Print("W2(DOWN) @ ",T(rates[c1].time),
                     " NOT confirmed (W3 not done / reset / W2 invalidated). STRICT gate.");
            break;
         }
      }
   }

   if(InpDebugPrints)
      Print("STRICT(DOWN): pairs=",pairs,
            (ExtLQ_Down_Has()? StringFormat(" | ext lq=%.5f",ExtLQ_Down_Get()) : " | ext lq:n/a"));
   return pairs;
}

// quick show on [0..now]
void API_Down_ShowMostRecent_W2W3_Hunter(const string sym, const ENUM_TIMEFRAMES tf, const int /*lookback*/)
{
   datetime start=0, stop=TimeCurrent();
   API_Down_RunScanSequential_W2W3_Hunter(sym, tf, start, stop);
}

#endif // WAVEBOT_API_DOWN_MQH
