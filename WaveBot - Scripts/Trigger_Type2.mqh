#ifndef WAVEBOT_TRIGGER_TYPE2_MQH
#define WAVEBOT_TRIGGER_TYPE2_MQH

// ============================================================================
// Dedicated search engine for Trigger Type-2
// New definition: every valid MajicFlip candle from Majicflip.mqh is Trigger
// Type-2. The engine is evaluated on every worker candle while an imported M15
// signal window is active. It never uses the old phase-based FSM.
// ============================================================================

static int g_trg2_mflip_up_draw_count = 0;
static int g_trg2_mflip_dn_draw_count = 0;

inline int __TRG2_BackScanLimitBars()
{
   int limit = InpMaxBarsInWave;
   if(limit <= 0)
      limit = 1000;
   if(limit < 10)
      limit = 10;
   return limit;
}

inline void Trigger_Type2_ResetGlobals()
{
   g_trg2_mflip_up_draw_count = 0;
   g_trg2_mflip_dn_draw_count = 0;
   MajicFlip_ResetGlobals();
}

inline bool __TRG2_DrawAndFireUP(const MajicFlipZone &z,
                                 const MqlRates &rates[],
                                 const int n)
{
   if(!z.used) return false;
   if(z.breaker_idx < 0 || z.breaker_idx >= n) return false;

   __MFlip_AddUP(z);
   __MFlip_DrawUP(z, g_trg2_mflip_up_draw_count);

   __TRG_FirePatternTrigger(TRG_ENGINE_TYPE2,
                            z.mother_idx,
                            z.breaker_idx,
                            rates,
                            n);
   return true;
}

inline bool __TRG2_DrawAndFireDOWN(const MajicFlipZone &z,
                                   const MqlRates &rates[],
                                   const int n)
{
   if(!z.used) return false;
   if(z.breaker_idx < 0 || z.breaker_idx >= n) return false;

   __MFlip_AddDOWN(z);
   __MFlip_DrawDOWN(z, g_trg2_mflip_dn_draw_count);

   __TRG_FirePatternTrigger(TRG_ENGINE_TYPE2,
                            z.mother_idx,
                            z.breaker_idx,
                            rates,
                            n);
   return true;
}

inline bool Trigger_Type2_ProcessUP(const MqlRates &rates[],
                                    const int n,
                                    const int bar_idx,
                                    const datetime from_time,
                                    const datetime to_time)
{
   if(bar_idx < 0 || bar_idx >= n) return false;

   int n_limit = bar_idx + 1;
   if(n_limit > n)
      n_limit = n;

   int from_idx = bar_idx - __TRG2_BackScanLimitBars();
   if(from_idx < 0)
      from_idx = 0;

   for(int mother_idx = bar_idx - 2; mother_idx >= from_idx; --mother_idx)
   {
      MajicFlipZone z;
      if(__MFlip_BuildUP(rates, n_limit, mother_idx, from_time, to_time, z) && z.breaker_idx == bar_idx)
         return __TRG2_DrawAndFireUP(z, rates, n);
   }

   return false;
}

inline bool Trigger_Type2_ProcessDOWN(const MqlRates &rates[],
                                      const int n,
                                      const int bar_idx,
                                      const datetime from_time,
                                      const datetime to_time)
{
   if(bar_idx < 0 || bar_idx >= n) return false;

   int n_limit = bar_idx + 1;
   if(n_limit > n)
      n_limit = n;

   int from_idx = bar_idx - __TRG2_BackScanLimitBars();
   if(from_idx < 0)
      from_idx = 0;

   for(int mother_idx = bar_idx - 2; mother_idx >= from_idx; --mother_idx)
   {
      MajicFlipZone z;
      if(__MFlip_BuildDOWN(rates, n_limit, mother_idx, from_time, to_time, z) && z.breaker_idx == bar_idx)
         return __TRG2_DrawAndFireDOWN(z, rates, n);
   }

   return false;
}

#endif // WAVEBOT_TRIGGER_TYPE2_MQH
