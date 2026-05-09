#ifndef WAVEBOT_TRIGGER_TYPE1_MQH
#define WAVEBOT_TRIGGER_TYPE1_MQH

// ============================================================================
// Dedicated search engine for Trigger Type-1
// New definition: every valid Flip candle from Flip.mqh is Trigger Type-1.
// The engine is evaluated on every worker candle while an imported M15 signal
// window is active. It never uses the old phase-based FSM.
// ============================================================================

static int g_trg1_flip_up_draw_count = 0;
static int g_trg1_flip_dn_draw_count = 0;

inline int __TRG1_BackScanLimitBars()
{
   int limit = InpMaxBarsInWave;
   if(limit <= 0)
      limit = 1000;
   if(limit < 10)
      limit = 10;
   return limit;
}

inline void Trigger_Type1_ResetGlobals()
{
   g_trg1_flip_up_draw_count = 0;
   g_trg1_flip_dn_draw_count = 0;
   Flip_ResetGlobals();
}

inline bool __TRG1_DrawAndFireUP(const FlipZone &z,
                                 const MqlRates &rates[],
                                 const int n)
{
   if(!z.used) return false;
   if(z.flip_idx < 0 || z.flip_idx >= n) return false;

   __Flip_AddUP(z);
   __Flip_DrawUP(z, g_trg1_flip_up_draw_count);

   __TRG_FirePatternTrigger(TRG_ENGINE_TYPE1,
                            z.anchor_idx,
                            z.flip_idx,
                            rates,
                            n);
   return true;
}

inline bool __TRG1_DrawAndFireDOWN(const FlipZone &z,
                                   const MqlRates &rates[],
                                   const int n)
{
   if(!z.used) return false;
   if(z.flip_idx < 0 || z.flip_idx >= n) return false;

   __Flip_AddDOWN(z);
   __Flip_DrawDOWN(z, g_trg1_flip_dn_draw_count);

   __TRG_FirePatternTrigger(TRG_ENGINE_TYPE1,
                            z.anchor_idx,
                            z.flip_idx,
                            rates,
                            n);
   return true;
}

inline bool Trigger_Type1_ProcessUP(const MqlRates &rates[],
                                    const int n,
                                    const int bar_idx,
                                    const datetime from_time,
                                    const datetime to_time)
{
   if(bar_idx < 0 || bar_idx >= n) return false;

   int n_limit = bar_idx + 1;
   if(n_limit > n)
      n_limit = n;

   // Direct previous-candle Flip: the current candle itself is the Flip candle.
   FlipZone direct;
   if(__Flip_BuildType1UP(rates, n_limit, bar_idx, from_time, to_time, direct))
      return __TRG1_DrawAndFireUP(direct, rates, n);

   // Mother + inside + breaker Flip: current candle is the breaker/Flip candle.
   int from_idx = bar_idx - __TRG1_BackScanLimitBars();
   if(from_idx < 0)
      from_idx = 0;

   for(int mother_idx = bar_idx - 2; mother_idx >= from_idx; --mother_idx)
   {
      FlipZone z;
      if(__Flip_BuildType2UP(rates, n_limit, mother_idx, from_time, to_time, z) && z.flip_idx == bar_idx)
         return __TRG1_DrawAndFireUP(z, rates, n);
   }

   return false;
}

inline bool Trigger_Type1_ProcessDOWN(const MqlRates &rates[],
                                      const int n,
                                      const int bar_idx,
                                      const datetime from_time,
                                      const datetime to_time)
{
   if(bar_idx < 0 || bar_idx >= n) return false;

   int n_limit = bar_idx + 1;
   if(n_limit > n)
      n_limit = n;

   // Direct previous-candle Flip: the current candle itself is the Flip candle.
   FlipZone direct;
   if(__Flip_BuildType1DOWN(rates, n_limit, bar_idx, from_time, to_time, direct))
      return __TRG1_DrawAndFireDOWN(direct, rates, n);

   // Mother + inside + breaker Flip: current candle is the breaker/Flip candle.
   int from_idx = bar_idx - __TRG1_BackScanLimitBars();
   if(from_idx < 0)
      from_idx = 0;

   for(int mother_idx = bar_idx - 2; mother_idx >= from_idx; --mother_idx)
   {
      FlipZone z;
      if(__Flip_BuildType2DOWN(rates, n_limit, mother_idx, from_time, to_time, z) && z.flip_idx == bar_idx)
         return __TRG1_DrawAndFireDOWN(z, rates, n);
   }

   return false;
}

#endif // WAVEBOT_TRIGGER_TYPE1_MQH
