
#ifndef WAVEBOT_TRIGGER_TYPE2_MQH
#define WAVEBOT_TRIGGER_TYPE2_MQH

// ============================================================================
// Dedicated search engine for Trigger Type-2
// ============================================================================

inline int __TRG2_BullHandlePhase4Break(const MqlRates &rates[],
                                        const int       n,
                                        const int       bar_idx)
{
   if(bar_idx < 0 || bar_idx >= n)
      return TRG_PHASE_NONE;

   const MqlRates bar = rates[bar_idx];

   g_trigger_type2.phase              = TRG_PHASE_4;
   g_trigger_type2.phase4_level       = bar.low;
   g_trigger_type2.phase4_idx         = bar_idx;
   g_trigger_type2.phase4_break2_seen = true;
   __TRG_ClearPhase2Build(g_trigger_type2);

   __TRG_DrawPhaseLabel(TRG_ENGINE_TYPE2, bar, TRG_PHASE_4);

   if(g_trigger_type2.phase3_idx >= 0 &&
      __TRG_TouchHigh(bar.high, g_trigger_type2.phase3_level) &&
      __TRG_BullSameBarTriggerAllowed(bar))
   {
      __TRG_FireTrigger(TRG_ENGINE_TYPE2,
                        g_trigger_type2.phase3_idx,
                        g_trigger_type2.phase3_level,
                        bar_idx,
                        rates,
                        n);
      return TRG_PHASE_4;
   }

   g_trigger_type2.phase = TRG_PHASE_5;
   return TRG_PHASE_4;
}

inline int __TRG2_BearHandlePhase4Break(const MqlRates &rates[],
                                        const int       n,
                                        const int       bar_idx)
{
   if(bar_idx < 0 || bar_idx >= n)
      return TRG_PHASE_NONE;

   const MqlRates bar = rates[bar_idx];

   g_trigger_type2.phase              = TRG_PHASE_4;
   g_trigger_type2.phase4_level       = bar.high;
   g_trigger_type2.phase4_idx         = bar_idx;
   g_trigger_type2.phase4_break2_seen = true;
   __TRG_ClearPhase2Build(g_trigger_type2);

   __TRG_DrawPhaseLabel(TRG_ENGINE_TYPE2, bar, TRG_PHASE_4);

   if(g_trigger_type2.phase3_idx >= 0 &&
      __TRG_TouchLow(bar.low, g_trigger_type2.phase3_level) &&
      __TRG_BearSameBarTriggerAllowed(bar))
   {
      __TRG_FireTrigger(TRG_ENGINE_TYPE2,
                        g_trigger_type2.phase3_idx,
                        g_trigger_type2.phase3_level,
                        bar_idx,
                        rates,
                        n);
      return TRG_PHASE_4;
   }

   g_trigger_type2.phase = TRG_PHASE_5;
   return TRG_PHASE_4;
}

inline int __TRG2_ProcessBull(const MqlRates &rates[],
                              const int       n,
                              const int       bar_idx)
{
   if(bar_idx < 0 || bar_idx >= n) return TRG_PHASE_NONE;

   const MqlRates bar = rates[bar_idx];

   if(!g_trigger_type2.mother_set)
   {
      __TRG_StartBullCycle(g_trigger_type2, TRG_ENGINE_TYPE2, rates, n, bar_idx, false, true, true);
      return TRG_PHASE_1;
   }

   bool allow_phase1_mother_update = false;
   if(g_trigger_type2.phase == TRG_PHASE_1 &&
      __TRG_BreakAboveStrict(bar.high, g_trigger_type2.phase1_level))
   {
      allow_phase1_mother_update = true;
   }

   if(__TRG_BreakBelowStrict(bar.low, g_trigger_type2.mother_level) &&
      !allow_phase1_mother_update)
   {
      __TRG_StartBullCycle(g_trigger_type2, TRG_ENGINE_TYPE2, rates, n, bar_idx, true, true, true);
      return TRG_PHASE_1;
   }

   if(g_trigger_type2.phase <= TRG_PHASE_NONE || g_trigger_type2.phase > TRG_PHASE_5)
   {
      __TRG_StartBullCycle(g_trigger_type2, TRG_ENGINE_TYPE2, rates, n, bar_idx, false, true, true);
      return TRG_PHASE_1;
   }

   if(bar_idx == g_trigger_type2.mother_idx && g_trigger_type2.phase == TRG_PHASE_1)
   {
      __TRG_DrawPhaseLabel(TRG_ENGINE_TYPE2, bar, TRG_PHASE_1);
      return TRG_PHASE_1;
   }

   switch(g_trigger_type2.phase)
   {
      case TRG_PHASE_1:
      {
         bool extended_phase1 = false;

         if(__TRG_BreakAboveStrict(bar.high, g_trigger_type2.phase1_level))
         {
            g_trigger_type2.phase1_level = bar.high;
            g_trigger_type2.phase1_idx   = bar_idx;
            extended_phase1 = true;
         }

         if(bar.low < g_trigger_type2.mother_level)
         {
            g_trigger_type2.mother_level = bar.low;
            g_trigger_type2.mother_idx   = bar_idx;
            g_trigger_type2.mother_time  = bar.time;
            __TRG_DrawBoundaryLabel(TRG_ENGINE_TYPE2, bar);
         }

         if(extended_phase1)
         {
            __TRG_DrawPhaseLabel(TRG_ENGINE_TYPE2, bar, TRG_PHASE_1);
            return TRG_PHASE_1;
         }

         __TRG_SetBullPhase2Latest(g_trigger_type2, bar_idx, bar);
         __TRG_DrawPhaseLabel(TRG_ENGINE_TYPE2, bar, TRG_PHASE_2);
         return TRG_PHASE_2;
      }

      case TRG_PHASE_2:
      {
         if(!__TRG_EngineHasPhase3(g_trigger_type2))
         {
            if(__TRG_BreakAboveStrict(bar.high, g_trigger_type2.phase1_level))
            {
               __TRG_SetBullPhase3Latest(g_trigger_type2, bar_idx, bar);
               __TRG_DrawPhaseLabel(TRG_ENGINE_TYPE2, bar, TRG_PHASE_3);
               return TRG_PHASE_3;
            }

            __TRG_SetBullPhase2Latest(g_trigger_type2, bar_idx, bar);
            __TRG_DrawPhaseLabel(TRG_ENGINE_TYPE2, bar, TRG_PHASE_2);
            return TRG_PHASE_2;
         }

         if(g_trigger_type2.phase2_idx >= 0 &&
            __TRG_BreakBelowStrict(bar.low, g_trigger_type2.phase2_level))
         {
            return __TRG2_BullHandlePhase4Break(rates, n, bar_idx);
         }

         if(__TRG_BreakAboveStrict(bar.high, g_trigger_type2.phase3_level))
         {
            __TRG_SetBullPhase3Latest(g_trigger_type2, bar_idx, bar);
            __TRG_DrawPhaseLabel(TRG_ENGINE_TYPE2, bar, TRG_PHASE_3);
            return TRG_PHASE_3;
         }

         __TRG_SetBullPhase2Candidate(g_trigger_type2, bar_idx, bar);
         __TRG_DrawPhaseLabel(TRG_ENGINE_TYPE2, bar, TRG_PHASE_2);
         return TRG_PHASE_2;
      }

      case TRG_PHASE_3:
      {
         if(g_trigger_type2.phase2_idx >= 0 &&
            __TRG_BreakBelowStrict(bar.low, g_trigger_type2.phase2_level))
         {
            return __TRG2_BullHandlePhase4Break(rates, n, bar_idx);
         }

         if(__TRG_BreakAboveStrict(bar.high, g_trigger_type2.phase3_level))
         {
            __TRG_SetBullPhase3Latest(g_trigger_type2, bar_idx, bar);
            __TRG_DrawPhaseLabel(TRG_ENGINE_TYPE2, bar, TRG_PHASE_3);
            return TRG_PHASE_3;
         }

         __TRG_SetBullPhase2Candidate(g_trigger_type2, bar_idx, bar);
         __TRG_DrawPhaseLabel(TRG_ENGINE_TYPE2, bar, TRG_PHASE_2);
         return TRG_PHASE_2;
      }

      case TRG_PHASE_4:
      {
         g_trigger_type2.phase = TRG_PHASE_5;
         __TRG_DrawPhaseLabel(TRG_ENGINE_TYPE2, bar, TRG_PHASE_5);

         if(g_trigger_type2.phase3_idx >= 0 &&
            __TRG_TouchHigh(bar.high, g_trigger_type2.phase3_level))
         {
            __TRG_FireTrigger(TRG_ENGINE_TYPE2,
                              g_trigger_type2.phase3_idx,
                              g_trigger_type2.phase3_level,
                              bar_idx,
                              rates,
                              n);
         }

         return TRG_PHASE_5;
      }

      case TRG_PHASE_5:
      {
         __TRG_DrawPhaseLabel(TRG_ENGINE_TYPE2, bar, TRG_PHASE_5);

         if(g_trigger_type2.phase3_idx >= 0 &&
            __TRG_TouchHigh(bar.high, g_trigger_type2.phase3_level))
         {
            __TRG_FireTrigger(TRG_ENGINE_TYPE2,
                              g_trigger_type2.phase3_idx,
                              g_trigger_type2.phase3_level,
                              bar_idx,
                              rates,
                              n);
         }

         return TRG_PHASE_5;
      }
   }

   return TRG_PHASE_NONE;
}

inline int __TRG2_ProcessBear(const MqlRates &rates[],
                              const int       n,
                              const int       bar_idx)
{
   if(bar_idx < 0 || bar_idx >= n) return TRG_PHASE_NONE;

   const MqlRates bar = rates[bar_idx];

   if(!g_trigger_type2.mother_set)
   {
      __TRG_StartBearCycle(g_trigger_type2, TRG_ENGINE_TYPE2, rates, n, bar_idx, false, true, true);
      return TRG_PHASE_1;
   }

   bool allow_phase1_mother_update = false;
   if(g_trigger_type2.phase == TRG_PHASE_1 &&
      __TRG_BreakBelowStrict(bar.low, g_trigger_type2.phase1_level))
   {
      allow_phase1_mother_update = true;
   }

   if(__TRG_BreakAboveStrict(bar.high, g_trigger_type2.mother_level) &&
      !allow_phase1_mother_update)
   {
      __TRG_StartBearCycle(g_trigger_type2, TRG_ENGINE_TYPE2, rates, n, bar_idx, true, true, true);
      return TRG_PHASE_1;
   }

   if(g_trigger_type2.phase <= TRG_PHASE_NONE || g_trigger_type2.phase > TRG_PHASE_5)
   {
      __TRG_StartBearCycle(g_trigger_type2, TRG_ENGINE_TYPE2, rates, n, bar_idx, false, true, true);
      return TRG_PHASE_1;
   }

   if(bar_idx == g_trigger_type2.mother_idx && g_trigger_type2.phase == TRG_PHASE_1)
   {
      __TRG_DrawPhaseLabel(TRG_ENGINE_TYPE2, bar, TRG_PHASE_1);
      return TRG_PHASE_1;
   }

   switch(g_trigger_type2.phase)
   {
      case TRG_PHASE_1:
      {
         bool extended_phase1 = false;

         if(__TRG_BreakBelowStrict(bar.low, g_trigger_type2.phase1_level))
         {
            g_trigger_type2.phase1_level = bar.low;
            g_trigger_type2.phase1_idx   = bar_idx;
            extended_phase1 = true;
         }

         if(bar.high > g_trigger_type2.mother_level)
         {
            g_trigger_type2.mother_level = bar.high;
            g_trigger_type2.mother_idx   = bar_idx;
            g_trigger_type2.mother_time  = bar.time;
            __TRG_DrawBoundaryLabel(TRG_ENGINE_TYPE2, bar);
         }

         if(extended_phase1)
         {
            __TRG_DrawPhaseLabel(TRG_ENGINE_TYPE2, bar, TRG_PHASE_1);
            return TRG_PHASE_1;
         }

         __TRG_SetBearPhase2Latest(g_trigger_type2, bar_idx, bar);
         __TRG_DrawPhaseLabel(TRG_ENGINE_TYPE2, bar, TRG_PHASE_2);
         return TRG_PHASE_2;
      }

      case TRG_PHASE_2:
      {
         if(!__TRG_EngineHasPhase3(g_trigger_type2))
         {
            if(__TRG_BreakBelowStrict(bar.low, g_trigger_type2.phase1_level))
            {
               __TRG_SetBearPhase3Latest(g_trigger_type2, bar_idx, bar);
               __TRG_DrawPhaseLabel(TRG_ENGINE_TYPE2, bar, TRG_PHASE_3);
               return TRG_PHASE_3;
            }

            __TRG_SetBearPhase2Latest(g_trigger_type2, bar_idx, bar);
            __TRG_DrawPhaseLabel(TRG_ENGINE_TYPE2, bar, TRG_PHASE_2);
            return TRG_PHASE_2;
         }

         if(g_trigger_type2.phase2_idx >= 0 &&
            __TRG_BreakAboveStrict(bar.high, g_trigger_type2.phase2_level))
         {
            return __TRG2_BearHandlePhase4Break(rates, n, bar_idx);
         }

         if(__TRG_BreakBelowStrict(bar.low, g_trigger_type2.phase3_level))
         {
            __TRG_SetBearPhase3Latest(g_trigger_type2, bar_idx, bar);
            __TRG_DrawPhaseLabel(TRG_ENGINE_TYPE2, bar, TRG_PHASE_3);
            return TRG_PHASE_3;
         }

         __TRG_SetBearPhase2Candidate(g_trigger_type2, bar_idx, bar);
         __TRG_DrawPhaseLabel(TRG_ENGINE_TYPE2, bar, TRG_PHASE_2);
         return TRG_PHASE_2;
      }

      case TRG_PHASE_3:
      {
         if(g_trigger_type2.phase2_idx >= 0 &&
            __TRG_BreakAboveStrict(bar.high, g_trigger_type2.phase2_level))
         {
            return __TRG2_BearHandlePhase4Break(rates, n, bar_idx);
         }

         if(__TRG_BreakBelowStrict(bar.low, g_trigger_type2.phase3_level))
         {
            __TRG_SetBearPhase3Latest(g_trigger_type2, bar_idx, bar);
            __TRG_DrawPhaseLabel(TRG_ENGINE_TYPE2, bar, TRG_PHASE_3);
            return TRG_PHASE_3;
         }

         __TRG_SetBearPhase2Candidate(g_trigger_type2, bar_idx, bar);
         __TRG_DrawPhaseLabel(TRG_ENGINE_TYPE2, bar, TRG_PHASE_2);
         return TRG_PHASE_2;
      }

      case TRG_PHASE_4:
      {
         g_trigger_type2.phase = TRG_PHASE_5;
         __TRG_DrawPhaseLabel(TRG_ENGINE_TYPE2, bar, TRG_PHASE_5);

         if(g_trigger_type2.phase3_idx >= 0 &&
            __TRG_TouchLow(bar.low, g_trigger_type2.phase3_level))
         {
            __TRG_FireTrigger(TRG_ENGINE_TYPE2,
                              g_trigger_type2.phase3_idx,
                              g_trigger_type2.phase3_level,
                              bar_idx,
                              rates,
                              n);
         }

         return TRG_PHASE_5;
      }

      case TRG_PHASE_5:
      {
         __TRG_DrawPhaseLabel(TRG_ENGINE_TYPE2, bar, TRG_PHASE_5);

         if(g_trigger_type2.phase3_idx >= 0 &&
            __TRG_TouchLow(bar.low, g_trigger_type2.phase3_level))
         {
            __TRG_FireTrigger(TRG_ENGINE_TYPE2,
                              g_trigger_type2.phase3_idx,
                              g_trigger_type2.phase3_level,
                              bar_idx,
                              rates,
                              n);
         }

         return TRG_PHASE_5;
      }
   }

   return TRG_PHASE_NONE;
}

#endif // WAVEBOT_TRIGGER_TYPE2_MQH
