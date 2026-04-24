#ifndef WAVEBOT_TRIGGER_TYPE1_MQH
#define WAVEBOT_TRIGGER_TYPE1_MQH

static TriggerEngineCore g_trg1_ctx;

inline datetime TriggerType1_LastProcessedTime()
{
   return g_trg1_ctx.last_processed_time;
}

inline void TriggerType1_ResetGlobals()
{
   __TRGCORE_ResetGlobals(g_trg1_ctx);
}

inline void TriggerType1_OnWindowChanged()
{
   __TRGCORE_ClearFSM(g_trg1_ctx);
}

inline void __TRG1_DrawPhaseLabel(const MqlRates &bar,
                                  const int       phase_id)
{
   __TRG_DrawPhaseLabelEx("TRG1",
                          g_trigger_bridge.active_dir,
                          bar,
                          phase_id,
                          clrAqua);
}

inline void __TRG1_DrawBoundaryLabel(const MqlRates &bar)
{
   __TRG_DrawBoundaryLabelEx("TRG1",
                             g_trigger_bridge.active_dir,
                             bar,
                             clrYellow);
}

inline void __TRG1_DrawResetLabel(const MqlRates &bar)
{
   __TRG_DrawResetLabelEx("TRG1",
                          g_trigger_bridge.active_dir,
                          bar,
                          clrRed);
}

inline void __TRG1_StartBullCycle(const MqlRates &rates[],
                                  const int       n,
                                  const int       bar_idx,
                                  const bool      draw_reset,
                                  const bool      draw_anchor,
                                  const bool      draw_phase)
{
   __TRGCORE_StartBullCycle(g_trg1_ctx, rates, n, bar_idx);

   if(bar_idx < 0 || bar_idx >= n)
      return;

   const MqlRates bar = rates[bar_idx];
   if(draw_reset)  __TRG1_DrawResetLabel(bar);
   if(draw_anchor) __TRG1_DrawBoundaryLabel(bar);
   if(draw_phase)  __TRG1_DrawPhaseLabel(bar, TRG_PHASE_1);
}

inline void __TRG1_StartBearCycle(const MqlRates &rates[],
                                  const int       n,
                                  const int       bar_idx,
                                  const bool      draw_reset,
                                  const bool      draw_anchor,
                                  const bool      draw_phase)
{
   __TRGCORE_StartBearCycle(g_trg1_ctx, rates, n, bar_idx);

   if(bar_idx < 0 || bar_idx >= n)
      return;

   const MqlRates bar = rates[bar_idx];
   if(draw_reset)  __TRG1_DrawResetLabel(bar);
   if(draw_anchor) __TRG1_DrawBoundaryLabel(bar);
   if(draw_phase)  __TRG1_DrawPhaseLabel(bar, TRG_PHASE_1);
}

inline void __TRG1_StartCycleAt(const MqlRates &rates[],
                                const int       n,
                                const int       bar_idx,
                                const bool      draw_reset,
                                const bool      draw_anchor,
                                const bool      draw_phase)
{
   if(g_trigger_bridge.active_dir == DIR_UP)
      __TRG1_StartBullCycle(rates, n, bar_idx, draw_reset, draw_anchor, draw_phase);
   else
      __TRG1_StartBearCycle(rates, n, bar_idx, draw_reset, draw_anchor, draw_phase);
}

inline void __TRG1_RestartAfterHit(const MqlRates &rates[],
                                   const int       n,
                                   const int       hit_idx)
{
   __TRG1_StartCycleAt(rates, n, hit_idx, false, false, false);
}

inline void __TRG1_FireTrigger(const int       src_idx,
                               const double    level,
                               const int       hit_idx,
                               const MqlRates &rates[],
                               const int       n)
{
   if(src_idx < 0 || src_idx >= n)
      return;
   if(hit_idx < 0 || hit_idx >= n)
      return;

   __TRG_RecordTriggerHit(g_trigger_bridge.active_dir,
                          1,
                          src_idx,
                          level,
                          hit_idx,
                          rates,
                          n);

   __TRG_DrawTriggerMarkerEx(g_trg1_ctx,
                             "TRG1",
                             g_trigger_bridge.active_dir,
                             1,
                             rates[src_idx].time,
                             rates[hit_idx].time,
                             level,
                             clrYellow);

   __TRG1_RestartAfterHit(rates, n, hit_idx);
}

inline int __TRG1_BullHandlePhase4Break(const MqlRates &rates[],
                                        const int       n,
                                        const int       bar_idx)
{
   if(bar_idx < 0 || bar_idx >= n)
      return TRG_PHASE_NONE;

   const MqlRates bar = rates[bar_idx];

   g_trg1_ctx.phase              = TRG_PHASE_4;
   g_trg1_ctx.phase4_level       = bar.low;
   g_trg1_ctx.phase4_idx         = bar_idx;
   g_trg1_ctx.phase4_break2_seen = true;
   __TRGCORE_ClearPhase2Build(g_trg1_ctx);

   __TRG1_DrawPhaseLabel(bar, TRG_PHASE_4);

   if(g_trg1_ctx.phase1_idx >= 0 &&
      __TRG_TouchHigh(bar.high, g_trg1_ctx.phase1_level) &&
      __TRG_BullSameBarTriggerAllowed(bar))
   {
      __TRG1_FireTrigger(g_trg1_ctx.phase1_idx,
                         g_trg1_ctx.phase1_level,
                         bar_idx,
                         rates,
                         n);
      return TRG_PHASE_4;
   }

   g_trg1_ctx.phase = TRG_PHASE_5;
   return TRG_PHASE_4;
}

inline int __TRG1_BearHandlePhase4Break(const MqlRates &rates[],
                                        const int       n,
                                        const int       bar_idx)
{
   if(bar_idx < 0 || bar_idx >= n)
      return TRG_PHASE_NONE;

   const MqlRates bar = rates[bar_idx];

   g_trg1_ctx.phase              = TRG_PHASE_4;
   g_trg1_ctx.phase4_level       = bar.high;
   g_trg1_ctx.phase4_idx         = bar_idx;
   g_trg1_ctx.phase4_break2_seen = true;
   __TRGCORE_ClearPhase2Build(g_trg1_ctx);

   __TRG1_DrawPhaseLabel(bar, TRG_PHASE_4);

   if(g_trg1_ctx.phase1_idx >= 0 &&
      __TRG_TouchLow(bar.low, g_trg1_ctx.phase1_level) &&
      __TRG_BearSameBarTriggerAllowed(bar))
   {
      __TRG1_FireTrigger(g_trg1_ctx.phase1_idx,
                         g_trg1_ctx.phase1_level,
                         bar_idx,
                         rates,
                         n);
      return TRG_PHASE_4;
   }

   g_trg1_ctx.phase = TRG_PHASE_5;
   return TRG_PHASE_4;
}

inline int __TRG1_ProcessBull(const MqlRates &rates[],
                              const int       n,
                              const int       bar_idx)
{
   if(bar_idx < 0 || bar_idx >= n)
      return TRG_PHASE_NONE;

   const MqlRates bar = rates[bar_idx];

   if(!g_trg1_ctx.mother_set)
   {
      __TRG1_StartBullCycle(rates, n, bar_idx, false, true, true);
      return TRG_PHASE_1;
   }

   bool allow_phase1_mother_update = false;
   if(g_trg1_ctx.phase == TRG_PHASE_1 &&
      __TRG_BreakAboveStrict(bar.high, g_trg1_ctx.phase1_level))
   {
      allow_phase1_mother_update = true;
   }

   if(__TRG_BreakBelowStrict(bar.low, g_trg1_ctx.mother_level) &&
      !allow_phase1_mother_update)
   {
      __TRG1_StartBullCycle(rates, n, bar_idx, true, true, true);
      return TRG_PHASE_1;
   }

   if(g_trg1_ctx.phase <= TRG_PHASE_NONE || g_trg1_ctx.phase > TRG_PHASE_5)
   {
      __TRG1_StartBullCycle(rates, n, bar_idx, false, true, true);
      return TRG_PHASE_1;
   }

   if(bar_idx == g_trg1_ctx.mother_idx && g_trg1_ctx.phase == TRG_PHASE_1)
   {
      __TRG1_DrawPhaseLabel(bar, TRG_PHASE_1);
      return TRG_PHASE_1;
   }

   switch(g_trg1_ctx.phase)
   {
      case TRG_PHASE_1:
      {
         bool extended_phase1 = false;

         if(__TRG_BreakAboveStrict(bar.high, g_trg1_ctx.phase1_level))
         {
            g_trg1_ctx.phase1_level = bar.high;
            g_trg1_ctx.phase1_idx   = bar_idx;
            extended_phase1 = true;
         }

         if(bar.low < g_trg1_ctx.mother_level)
         {
            g_trg1_ctx.mother_level = bar.low;
            g_trg1_ctx.mother_idx   = bar_idx;
            g_trg1_ctx.mother_time  = bar.time;
            __TRG1_DrawBoundaryLabel(bar);
         }

         if(extended_phase1)
         {
            __TRG1_DrawPhaseLabel(bar, TRG_PHASE_1);
            return TRG_PHASE_1;
         }

         __TRGCORE_SetBullPhase2Latest(g_trg1_ctx, bar_idx, bar);
         __TRG1_DrawPhaseLabel(bar, TRG_PHASE_2);
         return TRG_PHASE_2;
      }

      case TRG_PHASE_2:
      {
         if(!__TRGCORE_HasConfirmedPhase3(g_trg1_ctx))
         {
            if(__TRG_BreakAboveStrict(bar.high, g_trg1_ctx.phase1_level))
            {
               __TRG1_StartBullCycle(rates, n, bar_idx, false, true, true);
               return TRG_PHASE_1;
            }

            if(__TRGCORE_BullCanStartType1Phase3(g_trg1_ctx, rates, n, bar_idx))
            {
               __TRGCORE_SetBullPhase3Latest(g_trg1_ctx, bar_idx, bar, false);
               __TRG1_DrawPhaseLabel(bar, TRG_PHASE_3);
               return TRG_PHASE_3;
            }

            __TRGCORE_SetBullPhase2Latest(g_trg1_ctx, bar_idx, bar);
            __TRG1_DrawPhaseLabel(bar, TRG_PHASE_2);
            return TRG_PHASE_2;
         }

         if(g_trg1_ctx.phase2_idx >= 0 &&
            __TRG_BreakBelowStrict(bar.low, g_trg1_ctx.phase2_level))
         {
            return __TRG1_BullHandlePhase4Break(rates, n, bar_idx);
         }

         if(__TRG_BreakAboveStrict(bar.high, g_trg1_ctx.phase1_level))
         {
            __TRG1_StartBullCycle(rates, n, bar_idx, false, true, true);
            return TRG_PHASE_1;
         }

         if(__TRGCORE_BullCanStartType1Phase3(g_trg1_ctx, rates, n, bar_idx))
         {
            __TRGCORE_SetBullPhase3Latest(g_trg1_ctx, bar_idx, bar, false);
            __TRG1_DrawPhaseLabel(bar, TRG_PHASE_3);
            return TRG_PHASE_3;
         }

         __TRGCORE_SetBullPhase2Candidate(g_trg1_ctx, bar_idx, bar);
         __TRG1_DrawPhaseLabel(bar, TRG_PHASE_2);
         return TRG_PHASE_2;
      }

      case TRG_PHASE_3:
      {
         if(g_trg1_ctx.phase2_idx >= 0 &&
            __TRG_BreakBelowStrict(bar.low, g_trg1_ctx.phase2_level))
         {
            return __TRG1_BullHandlePhase4Break(rates, n, bar_idx);
         }

         if(__TRG_BreakAboveStrict(bar.high, g_trg1_ctx.phase1_level))
         {
            __TRG1_StartBullCycle(rates, n, bar_idx, false, true, true);
            return TRG_PHASE_1;
         }

         if(__TRG_BreakAboveStrict(bar.high, g_trg1_ctx.phase3_level))
         {
            __TRGCORE_SetBullPhase3Latest(g_trg1_ctx, bar_idx, bar, false);
            __TRG1_DrawPhaseLabel(bar, TRG_PHASE_3);
            return TRG_PHASE_3;
         }

         __TRGCORE_SetBullPhase2Candidate(g_trg1_ctx, bar_idx, bar);
         __TRG1_DrawPhaseLabel(bar, TRG_PHASE_2);
         return TRG_PHASE_2;
      }

      case TRG_PHASE_4:
      {
         g_trg1_ctx.phase = TRG_PHASE_5;
         __TRG1_DrawPhaseLabel(bar, TRG_PHASE_5);

         if(g_trg1_ctx.phase1_idx >= 0 &&
            __TRG_TouchHigh(bar.high, g_trg1_ctx.phase1_level))
         {
            __TRG1_FireTrigger(g_trg1_ctx.phase1_idx,
                               g_trg1_ctx.phase1_level,
                               bar_idx,
                               rates,
                               n);
         }

         return TRG_PHASE_5;
      }

      case TRG_PHASE_5:
      {
         __TRG1_DrawPhaseLabel(bar, TRG_PHASE_5);

         if(g_trg1_ctx.phase1_idx >= 0 &&
            __TRG_TouchHigh(bar.high, g_trg1_ctx.phase1_level))
         {
            __TRG1_FireTrigger(g_trg1_ctx.phase1_idx,
                               g_trg1_ctx.phase1_level,
                               bar_idx,
                               rates,
                               n);
         }

         return TRG_PHASE_5;
      }
   }

   return TRG_PHASE_NONE;
}

inline int __TRG1_ProcessBear(const MqlRates &rates[],
                              const int       n,
                              const int       bar_idx)
{
   if(bar_idx < 0 || bar_idx >= n)
      return TRG_PHASE_NONE;

   const MqlRates bar = rates[bar_idx];

   if(!g_trg1_ctx.mother_set)
   {
      __TRG1_StartBearCycle(rates, n, bar_idx, false, true, true);
      return TRG_PHASE_1;
   }

   bool allow_phase1_mother_update = false;
   if(g_trg1_ctx.phase == TRG_PHASE_1 &&
      __TRG_BreakBelowStrict(bar.low, g_trg1_ctx.phase1_level))
   {
      allow_phase1_mother_update = true;
   }

   if(__TRG_BreakAboveStrict(bar.high, g_trg1_ctx.mother_level) &&
      !allow_phase1_mother_update)
   {
      __TRG1_StartBearCycle(rates, n, bar_idx, true, true, true);
      return TRG_PHASE_1;
   }

   if(g_trg1_ctx.phase <= TRG_PHASE_NONE || g_trg1_ctx.phase > TRG_PHASE_5)
   {
      __TRG1_StartBearCycle(rates, n, bar_idx, false, true, true);
      return TRG_PHASE_1;
   }

   if(bar_idx == g_trg1_ctx.mother_idx && g_trg1_ctx.phase == TRG_PHASE_1)
   {
      __TRG1_DrawPhaseLabel(bar, TRG_PHASE_1);
      return TRG_PHASE_1;
   }

   switch(g_trg1_ctx.phase)
   {
      case TRG_PHASE_1:
      {
         bool extended_phase1 = false;

         if(__TRG_BreakBelowStrict(bar.low, g_trg1_ctx.phase1_level))
         {
            g_trg1_ctx.phase1_level = bar.low;
            g_trg1_ctx.phase1_idx   = bar_idx;
            extended_phase1 = true;
         }

         if(bar.high > g_trg1_ctx.mother_level)
         {
            g_trg1_ctx.mother_level = bar.high;
            g_trg1_ctx.mother_idx   = bar_idx;
            g_trg1_ctx.mother_time  = bar.time;
            __TRG1_DrawBoundaryLabel(bar);
         }

         if(extended_phase1)
         {
            __TRG1_DrawPhaseLabel(bar, TRG_PHASE_1);
            return TRG_PHASE_1;
         }

         __TRGCORE_SetBearPhase2Latest(g_trg1_ctx, bar_idx, bar);
         __TRG1_DrawPhaseLabel(bar, TRG_PHASE_2);
         return TRG_PHASE_2;
      }

      case TRG_PHASE_2:
      {
         if(!__TRGCORE_HasConfirmedPhase3(g_trg1_ctx))
         {
            if(__TRG_BreakBelowStrict(bar.low, g_trg1_ctx.phase1_level))
            {
               __TRG1_StartBearCycle(rates, n, bar_idx, false, true, true);
               return TRG_PHASE_1;
            }

            if(__TRGCORE_BearCanStartType1Phase3(g_trg1_ctx, rates, n, bar_idx))
            {
               __TRGCORE_SetBearPhase3Latest(g_trg1_ctx, bar_idx, bar, false);
               __TRG1_DrawPhaseLabel(bar, TRG_PHASE_3);
               return TRG_PHASE_3;
            }

            __TRGCORE_SetBearPhase2Latest(g_trg1_ctx, bar_idx, bar);
            __TRG1_DrawPhaseLabel(bar, TRG_PHASE_2);
            return TRG_PHASE_2;
         }

         if(g_trg1_ctx.phase2_idx >= 0 &&
            __TRG_BreakAboveStrict(bar.high, g_trg1_ctx.phase2_level))
         {
            return __TRG1_BearHandlePhase4Break(rates, n, bar_idx);
         }

         if(__TRG_BreakBelowStrict(bar.low, g_trg1_ctx.phase1_level))
         {
            __TRG1_StartBearCycle(rates, n, bar_idx, false, true, true);
            return TRG_PHASE_1;
         }

         if(__TRGCORE_BearCanStartType1Phase3(g_trg1_ctx, rates, n, bar_idx))
         {
            __TRGCORE_SetBearPhase3Latest(g_trg1_ctx, bar_idx, bar, false);
            __TRG1_DrawPhaseLabel(bar, TRG_PHASE_3);
            return TRG_PHASE_3;
         }

         __TRGCORE_SetBearPhase2Candidate(g_trg1_ctx, bar_idx, bar);
         __TRG1_DrawPhaseLabel(bar, TRG_PHASE_2);
         return TRG_PHASE_2;
      }

      case TRG_PHASE_3:
      {
         if(g_trg1_ctx.phase2_idx >= 0 &&
            __TRG_BreakAboveStrict(bar.high, g_trg1_ctx.phase2_level))
         {
            return __TRG1_BearHandlePhase4Break(rates, n, bar_idx);
         }

         if(__TRG_BreakBelowStrict(bar.low, g_trg1_ctx.phase1_level))
         {
            __TRG1_StartBearCycle(rates, n, bar_idx, false, true, true);
            return TRG_PHASE_1;
         }

         if(__TRG_BreakBelowStrict(bar.low, g_trg1_ctx.phase3_level))
         {
            __TRGCORE_SetBearPhase3Latest(g_trg1_ctx, bar_idx, bar, false);
            __TRG1_DrawPhaseLabel(bar, TRG_PHASE_3);
            return TRG_PHASE_3;
         }

         __TRGCORE_SetBearPhase2Candidate(g_trg1_ctx, bar_idx, bar);
         __TRG1_DrawPhaseLabel(bar, TRG_PHASE_2);
         return TRG_PHASE_2;
      }

      case TRG_PHASE_4:
      {
         g_trg1_ctx.phase = TRG_PHASE_5;
         __TRG1_DrawPhaseLabel(bar, TRG_PHASE_5);

         if(g_trg1_ctx.phase1_idx >= 0 &&
            __TRG_TouchLow(bar.low, g_trg1_ctx.phase1_level))
         {
            __TRG1_FireTrigger(g_trg1_ctx.phase1_idx,
                               g_trg1_ctx.phase1_level,
                               bar_idx,
                               rates,
                               n);
         }

         return TRG_PHASE_5;
      }

      case TRG_PHASE_5:
      {
         __TRG1_DrawPhaseLabel(bar, TRG_PHASE_5);

         if(g_trg1_ctx.phase1_idx >= 0 &&
            __TRG_TouchLow(bar.low, g_trg1_ctx.phase1_level))
         {
            __TRG1_FireTrigger(g_trg1_ctx.phase1_idx,
                               g_trg1_ctx.phase1_level,
                               bar_idx,
                               rates,
                               n);
         }

         return TRG_PHASE_5;
      }
   }

   return TRG_PHASE_NONE;
}

inline void TriggerType1_ProcessBar(const string    sym,
                                    const MqlRates &rates[],
                                    const int       n,
                                    const int       bar_idx)
{
   if(sym == "")
      return;
   if(n <= 0 || bar_idx < 0 || bar_idx >= n)
      return;

   datetime bar_time = rates[bar_idx].time;
   if(g_trg1_ctx.last_processed_time > 0 && bar_time <= g_trg1_ctx.last_processed_time)
      return;

   if(g_trigger_bridge.active_dir == DIR_UP)
      __TRG1_ProcessBull(rates, n, bar_idx);
   else
      __TRG1_ProcessBear(rates, n, bar_idx);

   g_trg1_ctx.last_processed_time = bar_time;
   g_trg1_ctx.last_processed_idx  = bar_idx;
}

#endif // WAVEBOT_TRIGGER_TYPE1_MQH
