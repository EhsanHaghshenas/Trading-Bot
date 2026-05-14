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
#include <WaveBot/C1PreLock.mqh>   // NEW: early C1 pre-lock for SEARCH_W2
#include <WaveBot/W2W3_ChainInvalidation.mqh>
#include <WaveBot/ShadowBreaker.mqh>    // NEW: Shadow Breaker (UP/DOWN)
#include <WaveBot/FSMS.mqh>   // NEW: early FSMS detector (pre-HWBB)
#include <WaveBot/FSMS.mqh>   // NEW: early FSMS detector (pre-HWBB)
#include <WaveBot/StrongRange.mqh>  // NEW: Strong range painter
#include <WaveBot/SR_Gate.mqh>   // NEW: gating/cleanup for Strong Range
#include <WaveBot/SR_Mitigator.mqh>   // NEW
#include <WaveBot/SR_GoozBaghali.mqh>  // NEW: ????? ???? gooz baghali ?? unmitigated SR
#include <WaveBot/ExtLQ_Down.mqh>   // ???? ???? ???? ??? ????? ????? init-extLQ
#include <WaveBot/WorldManager.mqh>

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
// init extLQ for this scan (optional)
inline void __API_InitExtLQ_ForScan_UP(const bool enable, const double price, const datetime t)
{
   if(!enable) return;

   // reset UP extLQ
   ExtLQContext u;
   u.ext_has   = false;
   u.ext_price = 0.0;
   u.ext_time  = 0;
   ArrayResize(u.hist, 0);
   u.prev_idx  = -1;
   ExtLQ_ContextImport(u);

   // reset DOWN extLQ too (to keep world clean)
   ExtLQDownContext d;
   ExtLQ_Down_ContextReset(d);
   ExtLQ_Down_ContextImport(d);

   // set initial extLQ (and sync hunter)
   if(price > 0.0 && t > 0)
   {
      ExtLQ_Set(price, t);
      Hunter_OnExtLQUpdated();
   }
}

inline void __API_DrawConfirmedPair_UP(const string tag,
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

   MarkV("W2_" + tag + "_C1", rates[c1].time, clrDeepSkyBlue);
   MarkV("W2_" + tag + "_C2", rates[c2].time, clrDodgerBlue);
   MarkV("W2_" + tag + "_C3", rates[c3].time, clrRoyalBlue);
   if(c4 >= 0) MarkV("W2_" + tag + "_C4", rates[c4].time, clrBlue);

   MarkV("W3_" + tag + "_C1", rates[w3_c1].time,  clrLime);
   MarkV("W3_" + tag + "_C2", rates[k2].time,     clrSpringGreen);
   MarkV("W3_" + tag + "_C3", rates[k3].time,     clrGreen);
   if(k4 >= 0) MarkV("W3_" + tag + "_C4", rates[k4].time, clrDarkGreen);
}


inline int __API_TriggerPickLatestIndex(const int current_best, const int candidate)
{
   if(candidate < 0) return current_best;
   if(current_best < 0) return candidate;
   if(candidate > current_best) return candidate;
   return current_best;
}

inline int __API_TriggerActiveCandidate_ANY_UP(const int fallback_idx)
{
   int best = fallback_idx;

   if(C1Pre_UP_IsActive())
      best = __API_TriggerPickLatestIndex(best, C1Pre_UP_CurrentIndex());
   if(C1W2_UP_IsActive())
      best = __API_TriggerPickLatestIndex(best, C1W2_UP_CurrentIndex());
   if(C1W2_PB_UP_IsActive())
      best = __API_TriggerPickLatestIndex(best, C1W2_PB_UP_CurrentIndex());

   if(SW_UP_SeedActive())
      best = __API_TriggerPickLatestIndex(best, SW_UP_C1Index());
   if(SW_DOWN_SeedActive())
      best = __API_TriggerPickLatestIndex(best, SW_DOWN_C1Index());

   if(FSMS_SW_UP_SeedActive())
      best = __API_TriggerPickLatestIndex(best, FSMS_SW_UP_C1Index());
   if(FSMS_SW_DN_SeedActive())
      best = __API_TriggerPickLatestIndex(best, FSMS_SW_DN_C1Index());

   return best;
}

inline int __API_TriggerCandidate_WAIT_UP(const int fallback_idx, const int w3_c1, const int w3_cand)
{
   int best = __API_TriggerActiveCandidate_ANY_UP(fallback_idx);
   if(w3_c1 >= 0)
      best = __API_TriggerPickLatestIndex(best, w3_c1);
   if(w3_cand >= 0)
      best = __API_TriggerPickLatestIndex(best, w3_cand);
   return best;
}


// M1 performance cache for the deterministic Wave3 count check used inside the
// main UP scan.  The original CheckWave3CountOnly_Local() scans forward up to
// InpMaxBarsInWave from the same C1.  During M1 WAIT_CONFIRM the same startIdx
// can be tested many times while the rates[] buffer is unchanged, so caching the
// last result avoids repeated identical work without changing the trading logic.
struct __API_W3Cache_UP
{
   bool     ready;
   int      start_idx;
   int      n;
   datetime c1_time;
   datetime last_time;
   bool     ok;
   int      k2;
   int      k3;
   int      k4;
   int      end_idx;
};

inline void __API_W3Cache_UP_Reset(__API_W3Cache_UP &C)
{
   C.ready     = false;
   C.start_idx = -1;
   C.n         = -1;
   C.c1_time   = 0;
   C.last_time = 0;
   C.ok        = false;
   C.k2        = -1;
   C.k3        = -1;
   C.k4        = -1;
   C.end_idx   = -1;
}

inline bool __API_CheckWave3_UP_Cached(__API_W3Cache_UP &C,
                                       const bool use_cache,
                                       const MqlRates &rates[],
                                       const bool &insideHL[],
                                       const double &bodyLowEff[],
                                       const double &bodyHighEff[],
                                       const int n,
                                       const int startIdx,
                                       int &a2, int &a3, int &a4, int &w3e)
{
   a2 = -1;
   a3 = -1;
   a4 = -1;
   w3e = -1;

   const datetime c1_time   = (startIdx >= 0 && startIdx < n ? rates[startIdx].time : 0);
   const datetime last_time = (n > 0 ? rates[n-1].time : 0);

   if(use_cache && C.ready &&
      C.start_idx == startIdx &&
      C.n         == n &&
      C.c1_time   == c1_time &&
      C.last_time == last_time)
   {
      a2   = C.k2;
      a3   = C.k3;
      a4   = C.k4;
      w3e  = C.end_idx;
      return C.ok;
   }

   bool ok = CheckWave3CountOnly_Local(rates, insideHL, bodyLowEff, bodyHighEff,
                                       n, startIdx, a2, a3, a4, w3e);

   if(use_cache)
   {
      C.ready     = true;
      C.start_idx = startIdx;
      C.n         = n;
      C.c1_time   = c1_time;
      C.last_time = last_time;
      C.ok        = ok;
      C.k2        = a2;
      C.k3        = a3;
      C.k4        = a4;
      C.end_idx   = w3e;
   }

   return ok;
}

// ???? ???? (UP): W2 -> WAIT_CONFIRM(W3) + Hunter + ExtLQ
int API_RunScanSequential_W2W3_Hunter(const string sym, const ENUM_TIMEFRAMES tf,
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
      // major scans always run in MAJ namespace
      Markers_SetNamespace("MAJ");
      ++g_scan_id;
      __maj_scan_id = g_scan_id;
   }

   const int __api_token = Race_EnterAPIScan();

   __API_InitExtLQ_ForScan_UP(init_ext, init_ext_price, init_ext_time);

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
   C1Pre_UP_Reset();   // NEW: start a fresh pre-lock C1 for this scan

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

   __API_W3Cache_UP w3_cache_up;
   __API_W3Cache_UP_Reset(w3_cache_up);
   const bool w3_cache_up_enabled = (tf == PERIOD_M1);

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

            Trigger_OnBarCandidate(InpSymbol, rates, insideHL, n, i, __API_TriggerActiveCandidate_ANY_UP(i));

            ExtLQ_OnBar(rates[i]);
            HW_BB_UP_OnBar(rates[i], rates, n, i);   // NEW (???? ???? ??? ?? ?? Seed ??????)
            if(Race_ConsumeAbortAPIScan(__api_token))
            {
               Race_LeaveAPIScan(__api_token);
               return pairs;
            }

            Race_OnBar_UP(rates, insideHL, bodyLowEff, bodyHighEff, n, i);
            if(Race_ConsumeAbortAPIScan(__api_token))
            {
               Race_LeaveAPIScan(__api_token);
               return pairs;
            }
            SR_Mitigator_OnBar_UP(rates, n, i);   // NEW
            SR_GoozBaghali_OnBar_UP(rates, n, i);
            FSMS_SW_OnBarCtx(rates, insideHL, bodyLowEff, bodyHighEff, n, i);   // NEW: parallel guard for FSMS–SW
            if(WBWM_MinorWorldEnabledOnThisChart())
               WBWM_ProcessMinorStarterEvents(rates, n, i, __api_stop_time);
            if(Race_ShouldAllowFSMS())
            {
               FSMS_OnBarCtx(rates, insideHL, bodyLowEff, bodyHighEff, n, i);
            }
            WB15_MasterOnM15Bar(sym, rates, n, i);
            if(insideHL[i]) continue;
            
            bool __reanched = false;
            if(!C1W2_UP_ShouldAllowAt(rates, i, __reanched))
            {
               // Side-effect modules for this bar were already updated above.
               // Avoid running FSMS/FSMS-SW/WB15 twice on the same candle.
               continue;
            }
            // ????: C1W2 ??? ??? ??? ?? ??? ???? ???? ???? FSMS ?? ?? ?? ??? ????????.
            
            // --- NEW: Early C1 Loyalty Gate (pre-lock) + FSMS sync -----------------
            bool __pre_re = false;
            if(!C1Pre_UP_ShouldAllowAt(rates, i, __pre_re))
            {
               // ???? ?? C1 ???? ????????? ?????? ????? i ???? ??????
               continue;
            }
            // ?? ??? ?? C1 ???? ?????? (??? ?? ??? W3) ??/??????? ??????? ?????? FSMS ?? ?? ??? ??? C1 ????? ???
            if(__pre_re)
            {
               FSMS_OnSameDirC1_Reanchor_UP(rates, n, i);
            }

            Trigger_OnBarCandidate(InpSymbol, rates, insideHL, n, i, __API_TriggerActiveCandidate_ANY_UP(i));

            int i2=-1,i3=-1,i4=-1;
            if(!CheckWave2_FromIndex_LocalOnly(rates, insideHL, bodyLowEff, bodyHighEff, n, i, i2, i3, i4))
               continue;

            c1=i; c2=i2; c3=i3; c4=i4; cend=(c4>=0?c4:c3);

            if(rates[c1].time<effective_start || rates[c1].time>__api_stop_time)
            { idx=cend+1; continue; }

            string tag_num = IntegerToString(pairs+1);
            string tag = (tag_suffix=="" ? tag_num : (tag_num + tag_suffix));

            if(InpDebugPrints) Print("#",tag," W2(UP) found @ ",T(rates[c1].time));

            // ???? ????? W3/wick
            have_w3=false; w3_c1=-1; k2=k3=k4=-1; w3_end=-1;
            w3_cand=-1;   w3_cand_low=DBL_MAX;

            wickActive=false; firstWickIdx=-1; wickBreakIdx=-1;
            bodyBreakLevel = rates[c1].high;   // H1_W2
            breakAchieved  = false;
            bodyBreakIdx   = -1;
            C1W2_UP_OnW2Locked();
            SWGate_UP_OnW2Locked(rates, c1);
            C1Pre_UP_OnW2Locked();   // NEW: ????? ??? ???????? C1

            idx=cend; state=WAIT_CONFIRM; found=true; break;
         }
         if(!found) break;
      }
      else // ============================ WAIT_CONFIRM ============================
      {
         const double H1_W2 = rates[c1].high;
         const double L1_W2 = rates[c1].low;
         string tag_num = IntegerToString(pairs+1);
         string tag = (tag_suffix=="" ? tag_num : (tag_num + tag_suffix));

         bool progressed=false;

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

            Trigger_OnBarCandidate(InpSymbol, rates, insideHL, n, j, __API_TriggerCandidate_WAIT_UP(c1, w3_c1, w3_cand));

            ExtLQ_OnBar(rates[j]);
            if(Hunter_IsExtLQCross(rates[j]))
               Hunter_TryMarkIfValid(rates, n, c1, j);
            HW_BB_UP_OnBar(rates[j],rates, n, j);
            if(Race_ConsumeAbortAPIScan(__api_token))
            {
               Race_LeaveAPIScan(__api_token);
               return pairs;
            }
            Race_OnBar_UP(rates, insideHL, bodyLowEff, bodyHighEff, n, j);
            if(Race_ConsumeAbortAPIScan(__api_token))
            {
               Race_LeaveAPIScan(__api_token);
               return pairs;
            }
            SR_Mitigator_OnBar_UP(rates, n, j);   // NEW: ???? ?????? ?? ????

            SB_UP_OnBarCtx(rates, insideHL, n, cend, j);   // ShadowBreaker + temp-c1-sw
            SR_GoozBaghali_OnBar_UP(rates, n, j);
            FSMS_SW_OnBarCtx(rates, insideHL, bodyLowEff, bodyHighEff, n, j);   // NEW: parallel guard for FSMS–SW
            if(WBWM_MinorWorldEnabledOnThisChart())
               WBWM_ProcessMinorStarterEvents(rates, n, j, __api_stop_time);
            if(Race_ShouldAllowFSMS())
            {
               FSMS_OnBarCtx(rates, insideHL, bodyLowEff, bodyHighEff, n, j);
            }
            WB15_MasterOnM15Bar(sym, rates, n, j);
            
            // --- NEW: Chain invalidation after ShadowBreaker (UP) -----------------
            if(SB_UP_InvalidatorReady())
            {  
               SR_DeleteAllObjects();           // NEW: remove any displayed Strong Range immediately

               // [A] ?????/????? ??????? ????
               Race_InternalClearAll();          // ??? ???????? HWBB ??? ???? ???? ??????
               Markers_Clear_Waves_CurrentScan();// ??? W2/W3/HW/HWBB/SW ???? ????
               SW_UP_ClearSeed();

               // [B]
               bool promoted = ExtLQ_PromotePrevToCurrent();
               if(promoted)
                  Hunter_OnExtLQUpdated();
               else
               {
                  ExtLQ_ClearAll(false);
                  Hunter_OnExtLQUpdated();
               }

               FSMS_OnSameDirW2Invalidated_UP();   // NEW

               // [C]
               datetime sbt = SB_UP_SBTime();
               int sb_idx = j;
               if(sbt>0){ for(int rr=j; rr>=0; --rr){ if(rates[rr].time==sbt){ sb_idx=rr; break; } } }

               idx        = sb_idx;
               state      = SEARCH_W2;
               C1Pre_UP_Reset();   // NEW

               progressed = true;

               SB_UP_ClearCycle();
               break;
            }

            // NEW: ???? gooz baghali ??? unmitigated SR (UP)
            SR_GoozBaghali_OnBar_UP(rates, n, j);

            if(insideHL[j]) continue;
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
                        FSMS_OnSameDirW2Invalidated_UP();   // NEW: ?????????? C1 ?????? ? ???? ???? ?????? FSMS
                        FSMS_OnSameDirC1_First_UP(rates, n, j);
                        
                        wickBreakIdx = j;
                        wickActive   = true;

                        // ??? C1: ?????? Low ??? [cend..firstWickIdx]
                        int anchorC1 = IndexOfLeftmostMinLow_ExInside(rates, insideHL, cend, firstWickIdx);
                        have_w3=false; w3_c1 = anchorC1;

                        // ???? ?????? ?? ???? ?????
                        w3_cand=-1; w3_cand_low=DBL_MAX;
                        Trigger_OnBarCandidate(InpSymbol, rates, insideHL, n, j, __API_TriggerCandidate_WAIT_UP(c1, w3_c1, w3_cand));
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
                  FSMS_OnSameDirW2Invalidated_UP();   // NEW: reset FSMS window due to same-dir W2 invalidation
         
                  idx = __rew; state = SEARCH_W2;
                  C1Pre_UP_Reset();   // NEW: ??????? ?? ??
                  progressed = true; break;
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
                  Trigger_OnBarCandidate(InpSymbol, rates, insideHL, n, j, __API_TriggerCandidate_WAIT_UP(c1, w3_c1, w3_cand));
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
                  Trigger_OnBarCandidate(InpSymbol, rates, insideHL, n, j, __API_TriggerCandidate_WAIT_UP(c1, w3_c1, w3_cand));
               }
            }

            // ?????? startIdx ???? ????? W3
            int startIdx = -1;
            if(w3_c1  >= 0)       startIdx = w3_c1;     // ???? ???? (???)
            else if(w3_cand >= 0) startIdx = w3_cand;   // ???? ??????
            
            // NEW: Strong range (UP) – ?????? ?? ??? SW ?? FSMS?SW ?? ??? ???????? ???
            // NEW: Strong range (UP) – only when SR is allowed for UP
            if(startIdx >= 0 && SR_ShouldProcess_UP())
               SR_OnBar_UP(rates, n, j, startIdx);


            // ????? W3 (UP) - ?????? "????? inside" + "barrier" ?? Wave3.mqh ????? ??????
            if(!have_w3 && startIdx >= 0 && !insideHL[startIdx])
            {
               int a2=-1,a3=-1,a4=-1, w3e=-1;
               if(__API_CheckWave3_UP_Cached(w3_cache_up, w3_cache_up_enabled,
                                            rates, insideHL, bodyLowEff, bodyHighEff, n,
                                            startIdx, a2, a3, a4, w3e))
               {
                  have_w3=true;
                  if(w3_c1 < 0) w3_c1 = startIdx;
                  k2=a2; k3=a3; k4=a4; w3_end=w3e;
                  Trigger_OnBarCandidate(InpSymbol, rates, insideHL, n, j, __API_TriggerCandidate_WAIT_UP(c1, w3_c1, w3_cand));
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
                  FSMS_OnSameDirW2Invalidated_UP();          
                  idx       = (bodyBreakIdx>=0 ? bodyBreakIdx : j);
                  state     = SEARCH_W2;
                  C1Pre_UP_Reset();
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
                  FSMS_OnSameDirW2Invalidated_UP();         
                  idx = (bodyBreakIdx>=0 ? bodyBreakIdx : j);
                  state = SEARCH_W2;
                  C1Pre_UP_Reset();   // NEW: ??????? ?? ??

                  progressed = true;
                  break;
               }
            }

            if(have_w3 && breakAchieved)
            {
               __API_DrawConfirmedPair_UP(tag, rates, c1, c2, c3, c4, w3_c1, k2, k3, k4);

               // ext lq ???? (UP)
               ExtLQ_Set(rates[w3_c1].low, rates[w3_c1].time);
               Hunter_OnExtLQUpdated();
            
               SW_UP_TryMarkOnConfirmedW3(rates, n, w3_c1, bodyBreakIdx);
               FSMS_SW_UP_TryMarkOnConfirmedW3(rates, n, w3_c1, bodyBreakIdx);   // NEW: finalize FSMS–SW if armed

               FSMS_OnW3Confirmed_UP(rates, n, w3_c1);

               C1W2_UP_Start(rates, (bodyBreakIdx>=0 ? bodyBreakIdx : idx));  // ??? W2 ?????? ???? ??? ????
               // ????: ?? ??? ?? ???? ????? C1 ????? ???? ?????? ?? ???? C1Pre_UP ?? SEARCH_W2
               // ?? ?????? ? ??????? FSMS_OnSameDirC1_Reanchor_UP ???????? ???????.

               SWGate_UP_OnPairFinalized();
               SB_UP_BringToFront();  // PRIORITY: redraw SB/temp/invalidator on top for this bar

               if(InpDebugPrints)
                  Print("#",tag," Pair(UP) OK | W3 C1=",T(rates[w3_c1].time),
                        " | body-break @ ",T(rates[bodyBreakIdx>=0?bodyBreakIdx:idx].time));
            
               idx=j; state=SEARCH_W2;
               C1Pre_UP_Reset(); ++pairs; progressed=true; break;
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

   // NEW: ?? ?????? ????? ???? ???? ???? w2_minor ?? ?? ??? ??
   FSMS_SW_MinorLog_Dump();

   Race_LeaveAPIScan(__api_token);
   return pairs;
}

// ????? ???? ??? [0..now]
void API_ShowMostRecent_W2W3_Hunter(const string sym, const ENUM_TIMEFRAMES tf, const int /*lookback*/)
{
   datetime start=0, stop=TimeCurrent();
   API_RunScanSequential_W2W3_Hunter(sym, tf, start, stop);
}

#endif // WAVEBOT_API_MQH
