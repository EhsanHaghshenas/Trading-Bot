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
#include <WaveBot/Hunter_BodyBreak.mqh>  // NEW: ????? ???? ???????? Hunter ???? ?? ext lq (UP/DOWN)
#include <WaveBot/RaceCoordinator.mqh>
#include <WaveBot/C1W2Gate.mqh>
#include <WaveBot/C1PreLock.mqh>   // NEW: early C1 pre-lock for SEARCH_W2
#include <WaveBot/W2W3_ChainInvalidation.mqh>
#include <WaveBot/ShadowBreaker.mqh>
#include <WaveBot/FSMS.mqh>   // NEW: early FSMS detector (pre-HWBB)
#include <WaveBot/FSMS.mqh>   // NEW: early FSMS detector (pre-HWBB)
#include <WaveBot/StrongRange.mqh>  // NEW: Strong range painter
#include <WaveBot/SR_Gate.mqh>   // NEW: gating/cleanup for Strong Range
#include <WaveBot/SR_Mitigator.mqh>   // NEW
#include <WaveBot/SR_GoozBaghali.mqh>  // NEW: ???? gooz baghali ???? unmitigated SR (DOWN)
#include <WaveBot/ExtLQ.mqh>   // ???? ???? ???? ??? ????? ????? init-extLQ
#include <WaveBot/WorldManager.mqh>

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
// init extLQ for this scan (optional)
inline void __API_InitExtLQ_ForScan_DN(const bool enable, const double price, const datetime t)
{
   if(!enable) return;

   // reset DOWN extLQ
   ExtLQDownContext d;
   ExtLQ_Down_ContextReset(d);
   ExtLQ_Down_ContextImport(d);

   // reset UP extLQ too (to keep world clean)
   ExtLQContext u;
   u.ext_has   = false;
   u.ext_price = 0.0;
   u.ext_time  = 0;
   ArrayResize(u.hist, 0);
   u.prev_idx  = -1;
   ExtLQ_ContextImport(u);

   // set initial extLQ (and sync hunter-down)
   if(price > 0.0 && t > 0)
   {
      ExtLQ_Down_Set(price, t);
      Hunter_Down_OnExtLQUpdated();
   }
}

inline void __API_DrawConfirmedPair_DN(const string tag,
                                       const MqlRates &rates[],
                                       const int c1, const int c2, const int c3, const int c4,
                                       const int w3_c1, const int k2, const int k3, const int k4)
{
   if(!InpDrawMarkers) return;

   W2_ClearTag(tag);
   ClearIfExists("W3_" + tag + "_C1");
   ClearIfExists("W3_" + tag + "_C2");
   ClearIfExists("W3_" + tag + "_C3");
   ClearIfExists("W3_" + tag + "_C4");

   MarkV("W2_" + tag + "_C1", rates[c1].time, clrDeepPink);
   MarkV("W2_" + tag + "_C2", rates[c2].time, clrPlum);
   MarkV("W2_" + tag + "_C3", rates[c3].time, clrMediumVioletRed);
   if(c4 >= 0) MarkV("W2_" + tag + "_C4", rates[c4].time, clrCrimson);

   MarkV("W3_" + tag + "_C1", rates[w3_c1].time,  clrFireBrick);
   MarkV("W3_" + tag + "_C2", rates[k2].time,     clrTomato);
   MarkV("W3_" + tag + "_C3", rates[k3].time,     clrBrown);
   if(k4 >= 0) MarkV("W3_" + tag + "_C4", rates[k4].time, clrMaroon);
}


inline int __API_Down_TriggerPickLatestIndex(const int current_best, const int candidate)
{
   if(candidate < 0) return current_best;
   if(current_best < 0) return candidate;
   if(candidate > current_best) return candidate;
   return current_best;
}

inline int __API_Down_TriggerActiveCandidate_ANY_DN(const int fallback_idx)
{
   int best = fallback_idx;

   if(C1Pre_DN_IsActive())
      best = __API_Down_TriggerPickLatestIndex(best, C1Pre_DN_CurrentIndex());
   if(C1W2_DN_IsActive())
      best = __API_Down_TriggerPickLatestIndex(best, C1W2_DN_CurrentIndex());
   if(C1W2_PB_DN_IsActive())
      best = __API_Down_TriggerPickLatestIndex(best, C1W2_PB_DN_CurrentIndex());

   if(SW_UP_SeedActive())
      best = __API_Down_TriggerPickLatestIndex(best, SW_UP_C1Index());
   if(SW_DOWN_SeedActive())
      best = __API_Down_TriggerPickLatestIndex(best, SW_DOWN_C1Index());

   if(FSMS_SW_UP_SeedActive())
      best = __API_Down_TriggerPickLatestIndex(best, FSMS_SW_UP_C1Index());
   if(FSMS_SW_DN_SeedActive())
      best = __API_Down_TriggerPickLatestIndex(best, FSMS_SW_DN_C1Index());

   return best;
}

inline int __API_Down_TriggerCandidate_WAIT_DN(const int fallback_idx, const int w3_c1, const int w3_cand)
{
   int best = __API_Down_TriggerActiveCandidate_ANY_DN(fallback_idx);
   if(w3_c1 >= 0)
      best = __API_Down_TriggerPickLatestIndex(best, w3_c1);
   if(w3_cand >= 0)
      best = __API_Down_TriggerPickLatestIndex(best, w3_cand);
   return best;
}

// full scan (DOWN)
int API_Down_RunScanSequential_W2W3_Hunter(const string sym, const ENUM_TIMEFRAMES tf,
                                           const datetime from_time, const datetime to_time,
                                           const bool init_ext=false,
                                           const double init_ext_price=0.0,
                                           const datetime init_ext_time=0,
                                           const string tag_suffix="", const bool bump_scan_id=true)
{
   // --- HARD GUARD: MAJ scan must never be dragged into MIN namespace ---
   int __maj_scan_id = g_scan_id;

   if(bump_scan_id)
   {
      Markers_SetNamespace("MAJ");
      ++g_scan_id;
      __maj_scan_id = g_scan_id;
   }

   const int __api_token = Race_EnterAPIScan();

   __API_InitExtLQ_ForScan_DN(init_ext, init_ext_price, init_ext_time);

   const int tfsec = PeriodSeconds(tf);
      
   const int HISTORY_SKIP_BARS = 0;
   datetime effective_start = from_time + (HISTORY_SKIP_BARS * tfsec);
   datetime from_adj = from_time - tfsec*10;

   datetime __api_stop_time = to_time;
   if(tf == PERIOD_M1 && Trigger_M1HardStopEnabled())
   {
      datetime __hs = Trigger_M1HardStopTime();
      if(__hs > 0 && (__api_stop_time <= 0 || __api_stop_time > __hs))
         __api_stop_time = __hs;
   }
   else
   if(tf == PERIOD_M15 && bump_scan_id && Trigger_M15HardStopEnabled())
   {
      datetime __hs15 = Trigger_M15HardStopTime();
      if(__hs15 > 0 && (__api_stop_time <= 0 || __api_stop_time > __hs15))
         __api_stop_time = __hs15;
   }

   MqlRates rates[]; int n = LoadRatesRange(sym, tf, from_adj, __api_stop_time, rates);
   if(n<=0)
   {
      if(InpDebugPrints) Print("LoadRatesRange failed");
      Race_LeaveAPIScan(__api_token);
      return 0;
   }

   double bodyLowEff[], bodyHighEff[]; BuildEffectiveBodies(rates, n, bodyLowEff, bodyHighEff);
   bool insideHL[];                   BuildInsideClusterFlagsHL(rates, n, insideHL);

   int first_eff=0; while(first_eff<n && rates[first_eff].time<effective_start) first_eff++;
   int idx = MathMax(0, first_eff-2);
   C1Pre_DN_Reset();   // NEW

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
   // --- Guard: detect any post body-break C1_W3 change until W3 completes (DOWN)
   bool   postBreak_c1_lock = false;
   int    postBreak_c1_ref  = -1;

   while(idx < n)
   {
      if(state==SEARCH_W2)
      {
         bool found=false;
         for(int i=idx; i<n; ++i)
         {
                        // --- HARD GUARD: keep MAJ scan pinned to its namespace/scan_id ---
            if(bump_scan_id)
            {
               if(Markers_GetNamespace() != "MAJ")
                  Markers_SetNamespace("MAJ");
               g_scan_id = __maj_scan_id;
            }

            if(tf == PERIOD_M1)
            {
               if(Trigger_M1HardStopShouldStopBeforeBar(rates[i].time))
               {
                  Race_LeaveAPIScan(__api_token);
                  return pairs;
               }
               Trigger_M1HardStopMarkFinalBarIfNeeded(rates[i].time);
            }
            else
            if(tf == PERIOD_M15 && bump_scan_id)
            {
               if(Trigger_M15HardStopShouldStopBeforeBar(rates[i].time))
               {
                  Race_LeaveAPIScan(__api_token);
                  return pairs;
               }
               Trigger_M15HardStopMarkFinalBarIfNeeded(rates[i].time);
            }

            if(Race_CheckActiveRefBreak_Global(rates, n, i))
            {
               Race_LeaveAPIScan(__api_token);
               return pairs;
            }

            Trigger_OnBarCandidate(InpSymbol, rates, insideHL, n, i, __API_Down_TriggerActiveCandidate_ANY_DN(i));
            M15NewZone_OnBar(rates, n, i);

            ExtLQ_Down_OnBar(rates[i]);
            HW_BB_DOWN_OnBar(rates[i], rates, n, i);
            if(Race_ConsumeAbortAPIScan(__api_token))
            {
               Race_LeaveAPIScan(__api_token);
               return pairs;
            }

            Race_OnBar_DOWN(rates, insideHL, bodyLowEff, bodyHighEff, n, i);
            if(Race_ConsumeAbortAPIScan(__api_token))
            {
               Race_LeaveAPIScan(__api_token);
               return pairs;
            }
            SR_Mitigator_OnBar_DOWN(rates, n, i);   // NEW
            SR_GoozBaghali_OnBar_DOWN(rates, n, i);
            FSMS_SW_OnBarCtx(rates, insideHL, bodyLowEff, bodyHighEff, n, i);   // NEW: parallel guard for FSMS–SW^
            if(WBWM_MinorWorldEnabledOnThisChart())
               WBWM_ProcessMinorStarterEvents(rates, n, i, __api_stop_time);
            if(Race_ShouldAllowFSMS())
            {
               FSMS_OnBarCtx(rates, insideHL, bodyLowEff, bodyHighEff, n, i);
            }
            WB15_MasterOnM15Bar(sym, rates, n, i);
            if(insideHL[i]) continue;
            
            bool __reanched = false;
            if(!C1W2_DN_ShouldAllowAt(rates, i, __reanched))
            {
               // Side-effect modules for this bar were already updated above.
               // Avoid running FSMS/FSMS-SW/WB15 twice on the same candle.
               continue;
            }
            // C1W2 ??? ??? ??? ?? ??? ???? ???? FSMS ?? ?? C1Pre ??? ???????.
            
            // --- NEW: Early C1 Loyalty Gate (pre-lock) + FSMS sync -----------------
            bool __pre_re = false;
            if(!C1Pre_DN_ShouldAllowAt(rates, i, __pre_re))
            {
               continue;  // ??????? ?? C1 ????
            }
            if(__pre_re)
            {
               FSMS_OnSameDirC1_Reanchor_DOWN(rates, n, i);
            }

            Trigger_OnBarCandidate(InpSymbol, rates, insideHL, n, i, __API_Down_TriggerActiveCandidate_ANY_DN(i));

            int i2=-1,i3=-1,i4=-1;
            if(!CheckWave2_FromIndex_LocalOnly_Down(rates,insideHL,bodyLowEff,bodyHighEff,n,i,i2,i3,i4))
               continue;

            c1=i; c2=i2; c3=i3; c4=i4; cend=(c4>=0?c4:c3);

            if(rates[c1].time<effective_start || rates[c1].time>__api_stop_time)
            { idx=cend+1; continue; }

            string tag_num = IntegerToString(pairs+1);
            string tag = (tag_suffix=="" ? tag_num : (tag_num + tag_suffix));

            if(InpDebugPrints) Print("#",tag," W2(DOWN) found @ ",T(rates[c1].time));

            // reset W3 state
            have_w3=false; w3_c1=-1; k2=k3=k4=-1; w3_end=-1;
            w3_cand=-1;   w3_cand_high=-DBL_MAX;

            wickActive=false; firstWickIdx=-1; wickBreakIdx=-1;
            bodyBreakLevel = rates[c1].low;  // L1_W2
            breakAchieved  = false;
            bodyBreakIdx   = -1;
            C1W2_DN_OnW2Locked();
            SWGate_DN_OnW2Locked(rates, c1);
            C1Pre_DN_OnW2Locked();   // NEW

            idx=cend; state=WAIT_CONFIRM; found=true; break;
         }
         if(!found) break;
      }
      else // ============================ WAIT_CONFIRM ============================
      {
         const double L1_W2 = rates[c1].low;

         bool progressed=false;
         string tag_num = IntegerToString(pairs+1);
         string tag = (tag_suffix=="" ? tag_num : (tag_num + tag_suffix));

         for(int j=idx; j<n; ++j)
         {
                        // --- HARD GUARD: keep MAJ scan pinned to its namespace/scan_id ---
            if(bump_scan_id)
            {
               if(Markers_GetNamespace() != "MAJ")
                  Markers_SetNamespace("MAJ");
               g_scan_id = __maj_scan_id;
            }

            if(tf == PERIOD_M1)
            {
               if(Trigger_M1HardStopShouldStopBeforeBar(rates[j].time))
               {
                  Race_LeaveAPIScan(__api_token);
                  return pairs;
               }
               Trigger_M1HardStopMarkFinalBarIfNeeded(rates[j].time);
            }
            else
            if(tf == PERIOD_M15 && bump_scan_id)
            {
               if(Trigger_M15HardStopShouldStopBeforeBar(rates[j].time))
               {
                  Race_LeaveAPIScan(__api_token);
                  return pairs;
               }
               Trigger_M15HardStopMarkFinalBarIfNeeded(rates[j].time);
            }

            if(Race_CheckActiveRefBreak_Global(rates, n, j))
            {
               Race_LeaveAPIScan(__api_token);
               return pairs;
            }

            Trigger_OnBarCandidate(InpSymbol, rates, insideHL, n, j, __API_Down_TriggerCandidate_WAIT_DN(c1, w3_c1, w3_cand));
            M15NewZone_OnBar(rates, n, j);

            ExtLQ_Down_OnBar(rates[j]);
            if(Hunter_Down_IsExtLQCross(rates[j]))
               Hunter_Down_TryMarkIfValid(rates, n, c1, j);
            HW_BB_DOWN_OnBar(rates[j],rates, n, j);
            if(Race_ConsumeAbortAPIScan(__api_token))
            {
               Race_LeaveAPIScan(__api_token);
               return pairs;
            }
            Race_OnBar_DOWN(rates, insideHL, bodyLowEff, bodyHighEff, n, j);
            if(Race_ConsumeAbortAPIScan(__api_token))
            {
               Race_LeaveAPIScan(__api_token);
               return pairs;
            }
            SR_Mitigator_OnBar_DOWN(rates, n, j);   // NEW

            SB_DN_OnBarCtx(rates, insideHL, n, cend, j);   // ShadowBreaker + temp-c1-sw
            SR_GoozBaghali_OnBar_DOWN(rates, n, j);
            FSMS_SW_OnBarCtx(rates, insideHL, bodyLowEff, bodyHighEff, n, j);   // NEW: parallel guard for FSMS–SW
            if(WBWM_MinorWorldEnabledOnThisChart())
               WBWM_ProcessMinorStarterEvents(rates, n, j, __api_stop_time);
            if(Race_ShouldAllowFSMS())
            {
               FSMS_OnBarCtx(rates, insideHL, bodyLowEff, bodyHighEff, n, j);
            }
            WB15_MasterOnM15Bar(sym, rates, n, j);
            // --- NEW: Chain invalidation after ShadowBreaker (DOWN) --------------
            if(SB_DN_InvalidatorReady())
            {
               SR_DeleteAllObjects();           // NEW: remove any displayed Strong Range immediately
               // [A]
               Race_InternalClearAll();
               Markers_Clear_Waves_CurrentScan();
               SW_DOWN_ClearSeed();
            
               // [B]
               bool promoted = ExtLQ_Down_PromotePrevToCurrent();
               if(promoted)
                  Hunter_Down_OnExtLQUpdated();
               else
               {
                  ExtLQ_Down_ClearAll(false);
                  Hunter_Down_OnExtLQUpdated();
               }
            
               FSMS_OnSameDirW2Invalidated_DOWN();   // NEW

               // [C]
               datetime sbt = SB_DN_SBTime();
               int sb_idx = j;
               if(sbt>0){ for(int rr=j; rr>=0; --rr){ if(rates[rr].time==sbt){ sb_idx=rr; break; } } }
            
               idx        = sb_idx;
               state      = SEARCH_W2;
               C1Pre_DN_Reset();   // NEW

               progressed = true;
            
               SB_DN_ClearCycle();
               break;
            }

            // NEW: ????? ????? ?? ????? unmitigated SR ??? ?? ?? MTC/invalidator (DOWN)
            SR_GoozBaghali_OnBar_DOWN(rates, n, j);

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
                     int __c1_eff = (w3_c1>=0 ? w3_c1 : w3_cand);
                     postBreak_c1_ref  = __c1_eff;
                     postBreak_c1_lock = (__c1_eff >= 0);
                  }
                  else
                  {
                     bodyBreakLevel = rates[j].low; // wick escalation
                     if(firstWickIdx < 0)
                     {
                        firstWickIdx = j;
                        FSMS_OnSameDirW2Invalidated_DOWN(); // NEW: ?????????? C1 ?????? ? ???? ???? ?????? FSMS
                        FSMS_OnSameDirC1_First_DOWN(rates, n, j); // NEW: re-arm FSMS from this wick-broken same-dir C1

                        wickBreakIdx = j;
                        wickActive   = true;

                        // lock C1 on wick-path
                        int anchorC1 = IndexOfLeftmostMaxHigh_ExInside(rates, insideHL, cend, firstWickIdx);
                        have_w3=false; w3_c1 = anchorC1;

                        w3_cand=-1; w3_cand_high=-DBL_MAX;
                        Trigger_OnBarCandidate(InpSymbol, rates, insideHL, n, j, __API_Down_TriggerCandidate_WAIT_DN(c1, w3_c1, w3_cand));
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
                     Print("[ChainInv-DOWN] W2 & W3 INVALID (pre-body, wick-window via C1_W3 break).",
                           " Rewind to wick @ ", T(rates[__rew].time));
                  FSMS_OnSameDirW2Invalidated_DOWN();   // NEW         
                  idx = __rew; state = SEARCH_W2;
                  C1Pre_DN_Reset();   // NEW
                  progressed = true; break;
               }
            }
            
            // ===== NEW: PRE body-break (non-wick) - reset W3 if H > H(C1_W3) =====
            if(!wickActive && !breakAchieved)
            {
               int c1_eff = (w3_c1>=0 ? w3_c1 : w3_cand);
               if(c1_eff >= 0 && rates[j].high > rates[c1_eff].high)
               {
                  // Experts cleanup: noisy non-wick W3 reset message intentionally silenced.
                  // reset ONLY W3 and restart from the very bar that caused invalidation
                  have_w3=false; w3_end=-1; k2=k3=k4=-1;
                  w3_c1 = -1;
                  w3_cand      = j;
                  w3_cand_high = rates[j].high;
                  Trigger_OnBarCandidate(InpSymbol, rates, insideHL, n, j, __API_Down_TriggerCandidate_WAIT_DN(c1, w3_c1, w3_cand));
                  continue;
               }
            }

            // =====================================================================
            
            // Guard (DOWN): after body-break & before W3 completes, ANY change in C1_W3 => invalidate W2
            if(breakAchieved && !have_w3)
            {
               int __c1_now = (w3_c1>=0 ? w3_c1 : w3_cand);
            
               if(!postBreak_c1_lock && __c1_now >= 0)
               {
                  postBreak_c1_ref  = __c1_now;
                  postBreak_c1_lock = true;
               }
               else
               if(postBreak_c1_lock && __c1_now >= 0 && __c1_now != postBreak_c1_ref)
               {
                  if(InpDebugPrints)
                     Print("#",tag," W2(DOWN) INVALIDATED (C1_W3 changed after body-break). Restart @ ",
                           T(rates[bodyBreakIdx>=0?bodyBreakIdx:j].time));
                  FSMS_OnSameDirW2Invalidated_DOWN();
                  idx       = (bodyBreakIdx>=0 ? bodyBreakIdx : j);
                  state     = SEARCH_W2;
                  C1Pre_DN_Reset();   // NEW

                  progressed= true;
                  break;
               }
            }

            // POST body-break but BEFORE W3 finishes: H > H(C1_W3) -> invalidate W2
            if(breakAchieved && !have_w3)
            {
               int c1_eff = (w3_c1>=0 ? w3_c1 : w3_cand);
               if(c1_eff >= 0 && rates[j].high > rates[c1_eff].high)
               {
                  if(InpDebugPrints)
                     Print("#",tag," W2(DOWN) INVALIDATED after body-break: H > H(C1_W3). Restart @ ",T(rates[bodyBreakIdx>=0?bodyBreakIdx:j].time));
                  FSMS_OnSameDirW2Invalidated_DOWN();   // NEW
   
                  idx = (bodyBreakIdx>=0 ? bodyBreakIdx : j);
                  state = SEARCH_W2;
                  C1Pre_DN_Reset();   // NEW

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
                  Trigger_OnBarCandidate(InpSymbol, rates, insideHL, n, j, __API_Down_TriggerCandidate_WAIT_DN(c1, w3_c1, w3_cand));
               }
            }

            // choose start index for W3 counting
            int startIdx = -1;
            if(w3_c1  >= 0)       startIdx = w3_c1;     // wick-path (locked C1)
            else if(w3_cand >= 0) startIdx = w3_cand;   // direct-path
            
            // NEW: Strong range (DOWN) – ???? ???????
            // NEW: Strong range (DOWN) – only when SR is allowed for DOWN
            if(startIdx >= 0 && SR_ShouldProcess_DOWN())
               SR_OnBar_DOWN(rates, n, j, startIdx);

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
                  Trigger_OnBarCandidate(InpSymbol, rates, insideHL, n, j, __API_Down_TriggerCandidate_WAIT_DN(c1, w3_c1, w3_cand));
               }
            }

            // finalize only when BOTH conditions are met
            if(have_w3 && breakAchieved)
            {
               __API_DrawConfirmedPair_DN(tag, rates, c1, c2, c3, c4, w3_c1, k2, k3, k4);

               // ext lq ???? (DOWN)
               ExtLQ_Down_Set(rates[w3_c1].high, rates[w3_c1].time);
               Hunter_Down_OnExtLQUpdated();
            
               SW_DOWN_TryMarkOnConfirmedW3(rates, n, w3_c1, bodyBreakIdx);
               FSMS_SW_DN_TryMarkOnConfirmedW3(rates, n, w3_c1, bodyBreakIdx);   // NEW: finalize FSMS–SW if armed

               FSMS_OnW3Confirmed_DOWN(rates, n, w3_c1);

               C1W2_DN_Start(rates, (bodyBreakIdx>=0 ? bodyBreakIdx : idx)); // ??? W2 ?????? ???? ??? ????
               // ???? ??????? FSMS ?? ????? C1 ???? ?????? ???? ?? ???? C1Pre_DN ?? SEARCH_W2 ????? ??????.

               SWGate_DN_OnPairFinalized();
               SB_DN_BringToFront();  // PRIORITY: redraw SB/temp/invalidator on top for this bar

               if(InpDebugPrints)
                  Print("#",tag," Pair(DOWN) OK | W3 C1=",T(rates[w3_c1].time),
                        " | body-break @ ",T(rates[bodyBreakIdx>=0?bodyBreakIdx:idx].time));
            
               M15NewMarker_OnNewWavePair(DIR_DOWN, rates[(bodyBreakIdx>=0 ? bodyBreakIdx : j)].time);

               idx=j; state=SEARCH_W2;
               C1Pre_DN_Reset();   // NEW
               ++pairs; progressed=true; break;
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

   // NEW: ?? ?????? ????? ???? ???? ???? w2_minor ?? ?? ??? ??
   FSMS_SW_MinorLog_Dump();

   Race_LeaveAPIScan(__api_token);
   return pairs;
}

// quick show on [0..now]
void API_Down_ShowMostRecent_W2W3_Hunter(const string sym, const ENUM_TIMEFRAMES tf, const int /*lookback*/)
{
   datetime start=0, stop=TimeCurrent();
   API_Down_RunScanSequential_W2W3_Hunter(sym, tf, start, stop);
}

#endif // WAVEBOT_API_DOWN_MQH
