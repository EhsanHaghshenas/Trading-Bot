#ifndef WAVEBOT_TRIGGER_TYPE2_MQH
#define WAVEBOT_TRIGGER_TYPE2_MQH

static TriggerEngineCore g_trg2_ctx;

inline datetime TriggerType2_LastProcessedTime()
{
   return g_trg2_ctx.last_processed_time;
}

inline void TriggerType2_ResetGlobals()
{
   __TRGCORE_ResetGlobals(g_trg2_ctx);
}

inline void TriggerType2_OnWindowChanged()
{
   __TRGCORE_ClearFSM(g_trg2_ctx);
}

inline void __TRG2_StartBullCycle(const MqlRates &rates[],
                                  const int       n,
                                  const int       bar_idx)
{
   __TRGCORE_StartBullCycle(g_trg2_ctx, rates, n, bar_idx);
}

inline void __TRG2_StartBearCycle(const MqlRates &rates[],
                                  const int       n,
                                  const int       bar_idx)
{
   __TRGCORE_StartBearCycle(g_trg2_ctx, rates, n, bar_idx);
}

inline void __TRG2_StartCycleAt(const MqlRates &rates[],
                                const int       n,
                                const int       bar_idx)
{
   if(g_trigger_bridge.active_dir == DIR_UP)
      __TRG2_StartBullCycle(rates, n, bar_idx);
   else
      __TRG2_StartBearCycle(rates, n, bar_idx);
}

inline void __TRG2_RestartAfterHit(const MqlRates &rates[],
                                   const int       n,
                                   const int       hit_idx)
{
   __TRG2_StartCycleAt(rates, n, hit_idx);
}

inline void __TRG2_FireTrigger(const int       src_idx,
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
                          2,
                          src_idx,
                          level,
                          hit_idx,
                          rates,
                          n);

   __TRG_DrawTriggerMarkerEx(g_trg2_ctx,
                             "TRG2",
                             g_trigger_bridge.active_dir,
                             2,
                             rates[src_idx].time,
                             rates[hit_idx].time,
                             level,
                             clrDodgerBlue);

   __TRG2_RestartAfterHit(rates, n, hit_idx);
}

inline int __TRG2_BullHandlePhase4Break(const MqlRates &rates[],
                                        const int       n,
                                        const int       bar_idx)
{
   if(bar_idx < 0 || bar_idx >= n)
      return TRG_PHASE_NONE;

   const MqlRates bar = rates[bar_idx];

   g_trg2_ctx.phase              = TRG_PHASE_4;
   g_trg2_ctx.phase4_level       = bar.low;
   g_trg2_ctx.phase4_idx         = bar_idx;
   g_trg2_ctx.phase4_break2_seen = true;
   __TRGCORE_ClearPhase2Build(g_trg2_ctx);

   if(g_trg2_ctx.phase3_break1_seen)
   {
      if(g_trg2_ctx.phase3_idx >= 0 &&
         __TRG_TouchHigh(bar.high, g_trg2_ctx.phase3_level) &&
         __TRG_BullSameBarTriggerAllowed(bar))
      {
         __TRG2_FireTrigger(g_trg2_ctx.phase3_idx,
                            g_trg2_ctx.phase3_level,
                            bar_idx,
                            rates,
                            n);
         return TRG_PHASE_4;
      }
   }
   else
   {
      if(g_trg2_ctx.phase1_idx >= 0 &&
         __TRG_TouchHigh(bar.high, g_trg2_ctx.phase1_level) &&
         __TRG_BullSameBarTriggerAllowed(bar))
      {
         __TRG2_RestartAfterHit(rates, n, bar_idx);
         return TRG_PHASE_4;
      }
   }

   g_trg2_ctx.phase = TRG_PHASE_5;
   return TRG_PHASE_4;
}

inline int __TRG2_BearHandlePhase4Break(const MqlRates &rates[],
                                        const int       n,
                                        const int       bar_idx)
{
   if(bar_idx < 0 || bar_idx >= n)
      return TRG_PHASE_NONE;

   const MqlRates bar = rates[bar_idx];

   g_trg2_ctx.phase              = TRG_PHASE_4;
   g_trg2_ctx.phase4_level       = bar.high;
   g_trg2_ctx.phase4_idx         = bar_idx;
   g_trg2_ctx.phase4_break2_seen = true;
   __TRGCORE_ClearPhase2Build(g_trg2_ctx);

   if(g_trg2_ctx.phase3_break1_seen)
   {
      if(g_trg2_ctx.phase3_idx >= 0 &&
         __TRG_TouchLow(bar.low, g_trg2_ctx.phase3_level) &&
         __TRG_BearSameBarTriggerAllowed(bar))
      {
         __TRG2_FireTrigger(g_trg2_ctx.phase3_idx,
                            g_trg2_ctx.phase3_level,
                            bar_idx,
                            rates,
                            n);
         return TRG_PHASE_4;
      }
   }
   else
   {
      if(g_trg2_ctx.phase1_idx >= 0 &&
         __TRG_TouchLow(bar.low, g_trg2_ctx.phase1_level) &&
         __TRG_BearSameBarTriggerAllowed(bar))
      {
         __TRG2_RestartAfterHit(rates, n, bar_idx);
         return TRG_PHASE_4;
      }
   }

   g_trg2_ctx.phase = TRG_PHASE_5;
   return TRG_PHASE_4;
}

inline int __TRG2_ProcessBull(const MqlRates &rates[],
                              const int       n,
                              const int       bar_idx)
{
   if(bar_idx < 0 || bar_idx >= n)
      return TRG_PHASE_NONE;

   const MqlRates bar = rates[bar_idx];

   if(!g_trg2_ctx.mother_set)
   {
      __TRG2_StartBullCycle(rates, n, bar_idx);
      return TRG_PHASE_1;
   }

   bool allow_phase1_mother_update = false;
   if(g_trg2_ctx.phase == TRG_PHASE_1 &&
      __TRG_BreakAboveStrict(bar.high, g_trg2_ctx.phase1_level))
   {
      allow_phase1_mother_update = true;
   }

   if(__TRG_BreakBelowStrict(bar.low, g_trg2_ctx.mother_level) &&
      !allow_phase1_mother_update)
   {
      __TRG2_StartBullCycle(rates, n, bar_idx);
      return TRG_PHASE_1;
   }

   if(g_trg2_ctx.phase <= TRG_PHASE_NONE || g_trg2_ctx.phase > TRG_PHASE_5)
   {
      __TRG2_StartBullCycle(rates, n, bar_idx);
      return TRG_PHASE_1;
   }

   switch(g_trg2_ctx.phase)
   {
      case TRG_PHASE_1:
      {
         bool extended_phase1 = false;

         if(__TRG_BreakAboveStrict(bar.high, g_trg2_ctx.phase1_level))
         {
            g_trg2_ctx.phase1_level = bar.high;
            g_trg2_ctx.phase1_idx   = bar_idx;
            extended_phase1 = true;
         }

         if(bar.low < g_trg2_ctx.mother_level)
         {
            g_trg2_ctx.mother_level = bar.low;
            g_trg2_ctx.mother_idx   = bar_idx;
            g_trg2_ctx.mother_time  = bar.time;
         }

         if(extended_phase1)
            return TRG_PHASE_1;

         __TRGCORE_SetBullPhase2Latest(g_trg2_ctx, bar_idx, bar);
         return TRG_PHASE_2;
      }

      case TRG_PHASE_2:
      {
         if(!__TRGCORE_HasConfirmedPhase3(g_trg2_ctx))
         {
            if(__TRG_BreakAboveStrict(bar.high, g_trg2_ctx.phase1_level))
            {
               __TRGCORE_SetBullPhase3Latest(g_trg2_ctx, bar_idx, bar, true);
               return TRG_PHASE_3;
            }

            if(__TRGCORE_BullCanStartType1Phase3(g_trg2_ctx, rates, n, bar_idx))
            {
               __TRGCORE_SetBullPhase3Latest(g_trg2_ctx, bar_idx, bar, false);
               return TRG_PHASE_3;
            }

            __TRGCORE_SetBullPhase2Latest(g_trg2_ctx, bar_idx, bar);
            return TRG_PHASE_2;
         }

         if(g_trg2_ctx.phase2_idx >= 0 &&
            __TRG_BreakBelowStrict(bar.low, g_trg2_ctx.phase2_level))
         {
            return __TRG2_BullHandlePhase4Break(rates, n, bar_idx);
         }

         if(g_trg2_ctx.phase3_break1_seen)
         {
            if(__TRG_BreakAboveStrict(bar.high, g_trg2_ctx.phase3_level))
            {
               __TRGCORE_SetBullPhase3Latest(g_trg2_ctx, bar_idx, bar, true);
               return TRG_PHASE_3;
            }
         }
         else
         {
            if(__TRG_BreakAboveStrict(bar.high, g_trg2_ctx.phase1_level))
            {
               __TRGCORE_SetBullPhase3Latest(g_trg2_ctx, bar_idx, bar, true);
               return TRG_PHASE_3;
            }

            if(__TRGCORE_BullCanStartType1Phase3(g_trg2_ctx, rates, n, bar_idx))
            {
               __TRGCORE_SetBullPhase3Latest(g_trg2_ctx, bar_idx, bar, false);
               return TRG_PHASE_3;
            }
         }

         __TRGCORE_SetBullPhase2Candidate(g_trg2_ctx, bar_idx, bar);
         return TRG_PHASE_2;
      }

      case TRG_PHASE_3:
      {
         if(g_trg2_ctx.phase2_idx >= 0 &&
            __TRG_BreakBelowStrict(bar.low, g_trg2_ctx.phase2_level))
         {
            return __TRG2_BullHandlePhase4Break(rates, n, bar_idx);
         }

         if(g_trg2_ctx.phase3_break1_seen)
         {
            if(__TRG_BreakAboveStrict(bar.high, g_trg2_ctx.phase3_level))
            {
               __TRGCORE_SetBullPhase3Latest(g_trg2_ctx, bar_idx, bar, true);
               return TRG_PHASE_3;
            }
         }
         else
         {
            if(__TRG_BreakAboveStrict(bar.high, g_trg2_ctx.phase1_level))
            {
               __TRGCORE_SetBullPhase3Latest(g_trg2_ctx, bar_idx, bar, true);
               return TRG_PHASE_3;
            }

            if(__TRG_BreakAboveStrict(bar.high, g_trg2_ctx.phase3_level))
            {
               __TRGCORE_SetBullPhase3Latest(g_trg2_ctx, bar_idx, bar, false);
               return TRG_PHASE_3;
            }
         }

         __TRGCORE_SetBullPhase2Candidate(g_trg2_ctx, bar_idx, bar);
         return TRG_PHASE_2;
      }

      case TRG_PHASE_4:
      {
         g_trg2_ctx.phase = TRG_PHASE_5;

         if(g_trg2_ctx.phase3_break1_seen)
         {
            if(g_trg2_ctx.phase3_idx >= 0 &&
               __TRG_TouchHigh(bar.high, g_trg2_ctx.phase3_level))
            {
               __TRG2_FireTrigger(g_trg2_ctx.phase3_idx,
                                  g_trg2_ctx.phase3_level,
                                  bar_idx,
                                  rates,
                                  n);
            }
         }
         else
         {
            if(g_trg2_ctx.phase1_idx >= 0 &&
               __TRG_TouchHigh(bar.high, g_trg2_ctx.phase1_level))
            {
               __TRG2_RestartAfterHit(rates, n, bar_idx);
            }
         }

         return TRG_PHASE_5;
      }

      case TRG_PHASE_5:
      {
         if(g_trg2_ctx.phase3_break1_seen)
         {
            if(g_trg2_ctx.phase3_idx >= 0 &&
               __TRG_TouchHigh(bar.high, g_trg2_ctx.phase3_level))
            {
               __TRG2_FireTrigger(g_trg2_ctx.phase3_idx,
                                  g_trg2_ctx.phase3_level,
                                  bar_idx,
                                  rates,
                                  n);
            }
         }
         else
         {
            if(g_trg2_ctx.phase1_idx >= 0 &&
               __TRG_TouchHigh(bar.high, g_trg2_ctx.phase1_level))
            {
               __TRG2_RestartAfterHit(rates, n, bar_idx);
            }
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
   if(bar_idx < 0 || bar_idx >= n)
      return TRG_PHASE_NONE;

   const MqlRates bar = rates[bar_idx];

   if(!g_trg2_ctx.mother_set)
   {
      __TRG2_StartBearCycle(rates, n, bar_idx);
      return TRG_PHASE_1;
   }

   bool allow_phase1_mother_update = false;
   if(g_trg2_ctx.phase == TRG_PHASE_1 &&
      __TRG_BreakBelowStrict(bar.low, g_trg2_ctx.phase1_level))
   {
      allow_phase1_mother_update = true;
   }

   if(__TRG_BreakAboveStrict(bar.high, g_trg2_ctx.mother_level) &&
      !allow_phase1_mother_update)
   {
      __TRG2_StartBearCycle(rates, n, bar_idx);
      return TRG_PHASE_1;
   }

   if(g_trg2_ctx.phase <= TRG_PHASE_NONE || g_trg2_ctx.phase > TRG_PHASE_5)
   {
      __TRG2_StartBearCycle(rates, n, bar_idx);
      return TRG_PHASE_1;
   }

   switch(g_trg2_ctx.phase)
   {
      case TRG_PHASE_1:
      {
         bool extended_phase1 = false;

         if(__TRG_BreakBelowStrict(bar.low, g_trg2_ctx.phase1_level))
         {
            g_trg2_ctx.phase1_level = bar.low;
            g_trg2_ctx.phase1_idx   = bar_idx;
            extended_phase1 = true;
         }

         if(bar.high > g_trg2_ctx.mother_level)
         {
            g_trg2_ctx.mother_level = bar.high;
            g_trg2_ctx.mother_idx   = bar_idx;
            g_trg2_ctx.mother_time  = bar.time;
         }

         if(extended_phase1)
            return TRG_PHASE_1;

         __TRGCORE_SetBearPhase2Latest(g_trg2_ctx, bar_idx, bar);
         return TRG_PHASE_2;
      }

      case TRG_PHASE_2:
      {
         if(!__TRGCORE_HasConfirmedPhase3(g_trg2_ctx))
         {
            if(__TRG_BreakBelowStrict(bar.low, g_trg2_ctx.phase1_level))
            {
               __TRGCORE_SetBearPhase3Latest(g_trg2_ctx, bar_idx, bar, true);
               return TRG_PHASE_3;
            }

            if(__TRGCORE_BearCanStartType1Phase3(g_trg2_ctx, rates, n, bar_idx))
            {
               __TRGCORE_SetBearPhase3Latest(g_trg2_ctx, bar_idx, bar, false);
               return TRG_PHASE_3;
            }

            __TRGCORE_SetBearPhase2Latest(g_trg2_ctx, bar_idx, bar);
            return TRG_PHASE_2;
         }

         if(g_trg2_ctx.phase2_idx >= 0 &&
            __TRG_BreakAboveStrict(bar.high, g_trg2_ctx.phase2_level))
         {
            return __TRG2_BearHandlePhase4Break(rates, n, bar_idx);
         }

         if(g_trg2_ctx.phase3_break1_seen)
         {
            if(__TRG_BreakBelowStrict(bar.low, g_trg2_ctx.phase3_level))
            {
               __TRGCORE_SetBearPhase3Latest(g_trg2_ctx, bar_idx, bar, true);
               return TRG_PHASE_3;
            }
         }
         else
         {
            if(__TRG_BreakBelowStrict(bar.low, g_trg2_ctx.phase1_level))
            {
               __TRGCORE_SetBearPhase3Latest(g_trg2_ctx, bar_idx, bar, true);
               return TRG_PHASE_3;
            }

            if(__TRGCORE_BearCanStartType1Phase3(g_trg2_ctx, rates, n, bar_idx))
            {
               __TRGCORE_SetBearPhase3Latest(g_trg2_ctx, bar_idx, bar, false);
               return TRG_PHASE_3;
            }
         }

         __TRGCORE_SetBearPhase2Candidate(g_trg2_ctx, bar_idx, bar);
         return TRG_PHASE_2;
      }

      case TRG_PHASE_3:
      {
         if(g_trg2_ctx.phase2_idx >= 0 &&
            __TRG_BreakAboveStrict(bar.high, g_trg2_ctx.phase2_level))
         {
            return __TRG2_BearHandlePhase4Break(rates, n, bar_idx);
         }

         if(g_trg2_ctx.phase3_break1_seen)
         {
            if(__TRG_BreakBelowStrict(bar.low, g_trg2_ctx.phase3_level))
            {
               __TRGCORE_SetBearPhase3Latest(g_trg2_ctx, bar_idx, bar, true);
               return TRG_PHASE_3;
            }
         }
         else
         {
            if(__TRG_BreakBelowStrict(bar.low, g_trg2_ctx.phase1_level))
            {
               __TRGCORE_SetBearPhase3Latest(g_trg2_ctx, bar_idx, bar, true);
               return TRG_PHASE_3;
            }

            if(__TRG_BreakBelowStrict(bar.low, g_trg2_ctx.phase3_level))
            {
               __TRGCORE_SetBearPhase3Latest(g_trg2_ctx, bar_idx, bar, false);
               return TRG_PHASE_3;
            }
         }

         __TRGCORE_SetBearPhase2Candidate(g_trg2_ctx, bar_idx, bar);
         return TRG_PHASE_2;
      }

      case TRG_PHASE_4:
      {
         g_trg2_ctx.phase = TRG_PHASE_5;

         if(g_trg2_ctx.phase3_break1_seen)
         {
            if(g_trg2_ctx.phase3_idx >= 0 &&
               __TRG_TouchLow(bar.low, g_trg2_ctx.phase3_level))
            {
               __TRG2_FireTrigger(g_trg2_ctx.phase3_idx,
                                  g_trg2_ctx.phase3_level,
                                  bar_idx,
                                  rates,
                                  n);
            }
         }
         else
         {
            if(g_trg2_ctx.phase1_idx >= 0 &&
               __TRG_TouchLow(bar.low, g_trg2_ctx.phase1_level))
            {
               __TRG2_RestartAfterHit(rates, n, bar_idx);
            }
         }

         return TRG_PHASE_5;
      }

      case TRG_PHASE_5:
      {
         if(g_trg2_ctx.phase3_break1_seen)
         {
            if(g_trg2_ctx.phase3_idx >= 0 &&
               __TRG_TouchLow(bar.low, g_trg2_ctx.phase3_level))
            {
               __TRG2_FireTrigger(g_trg2_ctx.phase3_idx,
                                  g_trg2_ctx.phase3_level,
                                  bar_idx,
                                  rates,
                                  n);
            }
         }
         else
         {
            if(g_trg2_ctx.phase1_idx >= 0 &&
               __TRG_TouchLow(bar.low, g_trg2_ctx.phase1_level))
            {
               __TRG2_RestartAfterHit(rates, n, bar_idx);
            }
         }

         return TRG_PHASE_5;
      }
   }

   return TRG_PHASE_NONE;
}

inline void TriggerType2_ProcessBar(const string    sym,
                                    const MqlRates &rates[],
                                    const int       n,
                                    const int       bar_idx)
{
   if(sym == "")
      return;
   if(n <= 0 || bar_idx < 0 || bar_idx >= n)
      return;

   datetime bar_time = rates[bar_idx].time;
   if(g_trg2_ctx.last_processed_time > 0 && bar_time <= g_trg2_ctx.last_processed_time)
      return;

   if(g_trigger_bridge.active_dir == DIR_UP)
      __TRG2_ProcessBull(rates, n, bar_idx);
   else
      __TRG2_ProcessBear(rates, n, bar_idx);

   g_trg2_ctx.last_processed_time = bar_time;
   g_trg2_ctx.last_processed_idx  = bar_idx;
}

#endif // WAVEBOT_TRIGGER_TYPE2_MQH
