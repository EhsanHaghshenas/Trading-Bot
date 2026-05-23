// ============================================================================
#ifndef WAVEBOT_TRIGGER_TYPE2_MQH
#define WAVEBOT_TRIGGER_TYPE2_MQH

// ============================================================================
// Dedicated search engine for Trigger Type-2
// New definition: every valid MajicFlip candle from Majicflip.mqh is Trigger
// Type-2. The engine is evaluated on every worker candle while an imported M15
// signal window is active. It never uses the old phase-based FSM.
//
// Performance note:
// The previous version re-ran __MFlip_Build* for up to InpMaxBarsInWave mother
// candidates on every M1 bar. Each builder rescanned the same inside-candle run.
// The fast builders below preserve the exact MajicFlip rules and nearest-mother
// priority, but check the inside envelope incrementally in one backward pass.
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

inline void __TRG2_FillUP(const MqlRates &rates[],
                          const int mother_idx,
                          const int breaker_idx,
                          MajicFlipZone &out)
{
   out.used         = true;
   out.mother_idx   = mother_idx;
   out.breaker_idx  = breaker_idx;

   out.mother_time  = rates[mother_idx].time;
   out.breaker_time = rates[breaker_idx].time;

   out.mother_high  = rates[mother_idx].high;
   out.mother_low   = rates[mother_idx].low;
   out.breaker_high = rates[breaker_idx].high;
   out.breaker_low  = rates[breaker_idx].low;

   out.price_top    = rates[mother_idx].high;
   out.price_bottom = rates[breaker_idx].low;
}

inline void __TRG2_FillDOWN(const MqlRates &rates[],
                            const int mother_idx,
                            const int breaker_idx,
                            MajicFlipZone &out)
{
   out.used         = true;
   out.mother_idx   = mother_idx;
   out.breaker_idx  = breaker_idx;

   out.mother_time  = rates[mother_idx].time;
   out.breaker_time = rates[breaker_idx].time;

   out.mother_high  = rates[mother_idx].high;
   out.mother_low   = rates[mother_idx].low;
   out.breaker_high = rates[breaker_idx].high;
   out.breaker_low  = rates[breaker_idx].low;

   out.price_top    = rates[breaker_idx].high;
   out.price_bottom = rates[mother_idx].low;
}

inline bool __TRG2_BuildUPFast(const MqlRates &rates[],
                               const int n,
                               const int bar_idx,
                               const datetime from_time,
                               const datetime to_time,
                               const int from_idx,
                               MajicFlipZone &out)
{
   if(bar_idx < 2 || bar_idx >= n) return false;
   if(!__MFlip_TimeInWindow(rates[bar_idx].time, from_time, to_time)) return false;
   if(!__MFlip_IsBull(rates[bar_idx])) return false;

   double mid_max_high = -DBL_MAX;
   double mid_min_low  = DBL_MAX;

   int start_mother = bar_idx - 2;
   int stop_mother  = from_idx;
   if(stop_mother < 0)
      stop_mother = 0;

   for(int mother_idx = start_mother; mother_idx >= stop_mother; --mother_idx)
   {
      int mid_idx = mother_idx + 1;
      if(mid_idx >= 0 && mid_idx < bar_idx)
      {
         if(rates[mid_idx].high > mid_max_high) mid_max_high = rates[mid_idx].high;
         if(rates[mid_idx].low  < mid_min_low)  mid_min_low  = rates[mid_idx].low;
      }

      if(mother_idx < 0 || mother_idx >= n - 2) continue;
      if(from_time > 0 && rates[mother_idx].time < from_time) break;
      if(!__MFlip_TimeInWindow(rates[mother_idx].time, from_time, to_time)) continue;
      if(!__MFlip_IsBear(rates[mother_idx])) continue;

      if(mid_max_high > rates[mother_idx].high) continue;
      if(mid_min_low  < rates[mother_idx].low)  continue;

      if(rates[bar_idx].close <= rates[mother_idx].high) continue;
      if(rates[bar_idx].low   >= rates[mother_idx].low)  continue;

      __TRG2_FillUP(rates, mother_idx, bar_idx, out);
      return true;
   }

   return false;
}

inline bool __TRG2_BuildDOWNFast(const MqlRates &rates[],
                                 const int n,
                                 const int bar_idx,
                                 const datetime from_time,
                                 const datetime to_time,
                                 const int from_idx,
                                 MajicFlipZone &out)
{
   if(bar_idx < 2 || bar_idx >= n) return false;
   if(!__MFlip_TimeInWindow(rates[bar_idx].time, from_time, to_time)) return false;
   if(!__MFlip_IsBear(rates[bar_idx])) return false;

   double mid_max_high = -DBL_MAX;
   double mid_min_low  = DBL_MAX;

   int start_mother = bar_idx - 2;
   int stop_mother  = from_idx;
   if(stop_mother < 0)
      stop_mother = 0;

   for(int mother_idx = start_mother; mother_idx >= stop_mother; --mother_idx)
   {
      int mid_idx = mother_idx + 1;
      if(mid_idx >= 0 && mid_idx < bar_idx)
      {
         if(rates[mid_idx].high > mid_max_high) mid_max_high = rates[mid_idx].high;
         if(rates[mid_idx].low  < mid_min_low)  mid_min_low  = rates[mid_idx].low;
      }

      if(mother_idx < 0 || mother_idx >= n - 2) continue;
      if(from_time > 0 && rates[mother_idx].time < from_time) break;
      if(!__MFlip_TimeInWindow(rates[mother_idx].time, from_time, to_time)) continue;
      if(!__MFlip_IsBull(rates[mother_idx])) continue;

      if(mid_max_high > rates[mother_idx].high) continue;
      if(mid_min_low  < rates[mother_idx].low)  continue;

      if(rates[bar_idx].close >= rates[mother_idx].low)  continue;
      if(rates[bar_idx].high  <= rates[mother_idx].high) continue;

      __TRG2_FillDOWN(rates, mother_idx, bar_idx, out);
      return true;
   }

   return false;
}

inline bool Trigger_Type2_ProcessUP(const MqlRates &rates[],
                                    const int n,
                                    const int bar_idx,
                                    const datetime from_time,
                                    const datetime to_time)
{
   if(bar_idx < 0 || bar_idx >= n) return false;

   __TRG_CACHE_BuildUP(rates, n, bar_idx, from_time, to_time);

   if(g_trg_cache_up_mflip.used)
      return __TRG2_DrawAndFireUP(g_trg_cache_up_mflip, rates, n);

   return false;
}

inline bool Trigger_Type2_ProcessDOWN(const MqlRates &rates[],
                                      const int n,
                                      const int bar_idx,
                                      const datetime from_time,
                                      const datetime to_time)
{
   if(bar_idx < 0 || bar_idx >= n) return false;

   __TRG_CACHE_BuildDOWN(rates, n, bar_idx, from_time, to_time);

   if(g_trg_cache_dn_mflip.used)
      return __TRG2_DrawAndFireDOWN(g_trg_cache_dn_mflip, rates, n);

   return false;
}

#endif // WAVEBOT_TRIGGER_TYPE2_MQH
