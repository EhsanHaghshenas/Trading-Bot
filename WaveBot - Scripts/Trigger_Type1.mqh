// ============================================================================
#ifndef WAVEBOT_TRIGGER_TYPE1_MQH
#define WAVEBOT_TRIGGER_TYPE1_MQH

// ============================================================================
// Dedicated search engine for Trigger Type-1
// New definition: every valid Flip candle from Flip.mqh is Trigger Type-1.
//
// Performance note:
// The previous implementation called __Flip_BuildType2* for up to
// InpMaxBarsInWave possible mother candles on every M1 bar. Each builder then
// scanned forward through the inside-candle run again. This preserved logic but
// made active trigger windows extremely slow on long M1 histories.
//
// The fast builders below keep the exact same acceptance rules and the same
// "nearest mother first" priority, but maintain the inside-run high/low envelope
// incrementally while scanning backward. Therefore each M1 candle is evaluated
// in one linear pass instead of many nested forward scans.
// ============================================================================

static int g_trg1_flip_up_draw_count = 0;
static int g_trg1_flip_dn_draw_count = 0;

// Shared per-bar pattern cache used by both Trigger_Type1 and Trigger_Type2.
// Type1 and Type2 are called sequentially for the same M1 candle; without this
// cache, both engines scan the same mother/inside history separately.
static datetime      g_trg_cache_up_bar_time   = 0;
static datetime      g_trg_cache_up_from_time  = 0;
static datetime      g_trg_cache_up_to_time    = 0;
static int           g_trg_cache_up_bar_idx    = -1;
static bool          g_trg_cache_up_ready      = false;
static FlipZone      g_trg_cache_up_direct;
static FlipZone      g_trg_cache_up_mother;
static MajicFlipZone g_trg_cache_up_mflip;

static datetime      g_trg_cache_dn_bar_time   = 0;
static datetime      g_trg_cache_dn_from_time  = 0;
static datetime      g_trg_cache_dn_to_time    = 0;
static int           g_trg_cache_dn_bar_idx    = -1;
static bool          g_trg_cache_dn_ready      = false;
static FlipZone      g_trg_cache_dn_direct;
static FlipZone      g_trg_cache_dn_mother;
static MajicFlipZone g_trg_cache_dn_mflip;

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
   g_trg_cache_up_ready = false;
   g_trg_cache_dn_ready = false;
   g_trg_cache_up_bar_idx = -1;
   g_trg_cache_dn_bar_idx = -1;
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

inline void __TRG1_FillType2UP(const MqlRates &rates[],
                               const int mother_idx,
                               const int flip_idx,
                               FlipZone &out)
{
   out.used        = true;
   out.kind        = 2;
   out.anchor_idx  = mother_idx;
   out.flip_idx    = flip_idx;
   out.anchor_time = rates[mother_idx].time;
   out.flip_time   = rates[flip_idx].time;

   out.anchor_high = rates[mother_idx].high;
   out.anchor_low  = rates[mother_idx].low;
   out.flip_high   = rates[flip_idx].high;
   out.flip_low    = rates[flip_idx].low;

   out.price_top    = rates[mother_idx].high;
   out.price_bottom = rates[mother_idx].low;
}

inline void __TRG1_FillType2DOWN(const MqlRates &rates[],
                                 const int mother_idx,
                                 const int flip_idx,
                                 FlipZone &out)
{
   out.used        = true;
   out.kind        = 2;
   out.anchor_idx  = mother_idx;
   out.flip_idx    = flip_idx;
   out.anchor_time = rates[mother_idx].time;
   out.flip_time   = rates[flip_idx].time;

   out.anchor_high = rates[mother_idx].high;
   out.anchor_low  = rates[mother_idx].low;
   out.flip_high   = rates[flip_idx].high;
   out.flip_low    = rates[flip_idx].low;

   out.price_top    = rates[mother_idx].high;
   out.price_bottom = rates[mother_idx].low;
}


inline void __TRG_CACHE_ClearFlip(FlipZone &z)
{
   z.used = false;
   z.kind = 0;
   z.anchor_idx = -1;
   z.flip_idx = -1;
   z.anchor_time = 0;
   z.flip_time = 0;
   z.anchor_high = 0.0;
   z.anchor_low = 0.0;
   z.flip_high = 0.0;
   z.flip_low = 0.0;
   z.price_top = 0.0;
   z.price_bottom = 0.0;
}

inline void __TRG_CACHE_ClearMFlip(MajicFlipZone &z)
{
   z.used = false;
   z.mother_idx = -1;
   z.breaker_idx = -1;
   z.mother_time = 0;
   z.breaker_time = 0;
   z.mother_high = 0.0;
   z.mother_low = 0.0;
   z.breaker_high = 0.0;
   z.breaker_low = 0.0;
   z.price_top = 0.0;
   z.price_bottom = 0.0;
}

inline void __TRG_CACHE_FillMFlipUP(const MqlRates &rates[],
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

inline void __TRG_CACHE_FillMFlipDOWN(const MqlRates &rates[],
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

inline void __TRG_CACHE_BuildUP(const MqlRates &rates[],
                                const int n,
                                const int bar_idx,
                                const datetime from_time,
                                const datetime to_time)
{
   if(bar_idx >= 0 && bar_idx < n &&
      g_trg_cache_up_ready &&
      g_trg_cache_up_bar_idx == bar_idx &&
      g_trg_cache_up_bar_time == rates[bar_idx].time &&
      g_trg_cache_up_from_time == from_time &&
      g_trg_cache_up_to_time == to_time)
      return;

   g_trg_cache_up_ready = true;
   g_trg_cache_up_bar_idx = bar_idx;
   g_trg_cache_up_bar_time = (bar_idx >= 0 && bar_idx < n ? rates[bar_idx].time : 0);
   g_trg_cache_up_from_time = from_time;
   g_trg_cache_up_to_time = to_time;
   __TRG_CACHE_ClearFlip(g_trg_cache_up_direct);
   __TRG_CACHE_ClearFlip(g_trg_cache_up_mother);
   __TRG_CACHE_ClearMFlip(g_trg_cache_up_mflip);

   if(bar_idx < 0 || bar_idx >= n) return;

   int n_limit = bar_idx + 1;
   if(n_limit > n) n_limit = n;

   __Flip_BuildType1UP(rates, n_limit, bar_idx, from_time, to_time, g_trg_cache_up_direct);

   if(bar_idx < 2) return;
   if(!__Flip_TimeInWindow(rates[bar_idx].time, from_time, to_time)) return;
   if(!__Flip_IsBull(rates[bar_idx])) return;

   int from_idx = bar_idx - __TRG1_BackScanLimitBars();
   if(from_idx < 0) from_idx = 0;

   double mid_max_high = -DBL_MAX;
   double mid_min_low  = DBL_MAX;

   for(int mother_idx = bar_idx - 2; mother_idx >= from_idx; --mother_idx)
   {
      int mid_idx = mother_idx + 1;
      if(mid_idx >= 0 && mid_idx < bar_idx)
      {
         if(rates[mid_idx].high > mid_max_high) mid_max_high = rates[mid_idx].high;
         if(rates[mid_idx].low  < mid_min_low)  mid_min_low  = rates[mid_idx].low;
      }

      if(from_time > 0 && rates[mother_idx].time < from_time) break;
      if(!__Flip_TimeInWindow(rates[mother_idx].time, from_time, to_time)) continue;
      if(!__Flip_IsBear(rates[mother_idx])) continue;

      if(mid_max_high > rates[mother_idx].high) continue;
      if(mid_min_low  < rates[mother_idx].low)  continue;
      if(rates[bar_idx].close <= rates[mother_idx].high) continue;

      if(!g_trg_cache_up_mother.used)
         __TRG1_FillType2UP(rates, mother_idx, bar_idx, g_trg_cache_up_mother);

      if(!g_trg_cache_up_mflip.used && rates[bar_idx].low < rates[mother_idx].low)
         __TRG_CACHE_FillMFlipUP(rates, mother_idx, bar_idx, g_trg_cache_up_mflip);

      if(g_trg_cache_up_mother.used && g_trg_cache_up_mflip.used)
         break;
   }
}

inline void __TRG_CACHE_BuildDOWN(const MqlRates &rates[],
                                  const int n,
                                  const int bar_idx,
                                  const datetime from_time,
                                  const datetime to_time)
{
   if(bar_idx >= 0 && bar_idx < n &&
      g_trg_cache_dn_ready &&
      g_trg_cache_dn_bar_idx == bar_idx &&
      g_trg_cache_dn_bar_time == rates[bar_idx].time &&
      g_trg_cache_dn_from_time == from_time &&
      g_trg_cache_dn_to_time == to_time)
      return;

   g_trg_cache_dn_ready = true;
   g_trg_cache_dn_bar_idx = bar_idx;
   g_trg_cache_dn_bar_time = (bar_idx >= 0 && bar_idx < n ? rates[bar_idx].time : 0);
   g_trg_cache_dn_from_time = from_time;
   g_trg_cache_dn_to_time = to_time;
   __TRG_CACHE_ClearFlip(g_trg_cache_dn_direct);
   __TRG_CACHE_ClearFlip(g_trg_cache_dn_mother);
   __TRG_CACHE_ClearMFlip(g_trg_cache_dn_mflip);

   if(bar_idx < 0 || bar_idx >= n) return;

   int n_limit = bar_idx + 1;
   if(n_limit > n) n_limit = n;

   __Flip_BuildType1DOWN(rates, n_limit, bar_idx, from_time, to_time, g_trg_cache_dn_direct);

   if(bar_idx < 2) return;
   if(!__Flip_TimeInWindow(rates[bar_idx].time, from_time, to_time)) return;
   if(!__Flip_IsBear(rates[bar_idx])) return;

   int from_idx = bar_idx - __TRG1_BackScanLimitBars();
   if(from_idx < 0) from_idx = 0;

   double mid_max_high = -DBL_MAX;
   double mid_min_low  = DBL_MAX;

   for(int mother_idx = bar_idx - 2; mother_idx >= from_idx; --mother_idx)
   {
      int mid_idx = mother_idx + 1;
      if(mid_idx >= 0 && mid_idx < bar_idx)
      {
         if(rates[mid_idx].high > mid_max_high) mid_max_high = rates[mid_idx].high;
         if(rates[mid_idx].low  < mid_min_low)  mid_min_low  = rates[mid_idx].low;
      }

      if(from_time > 0 && rates[mother_idx].time < from_time) break;
      if(!__Flip_TimeInWindow(rates[mother_idx].time, from_time, to_time)) continue;
      if(!__Flip_IsBull(rates[mother_idx])) continue;

      if(mid_max_high > rates[mother_idx].high) continue;
      if(mid_min_low  < rates[mother_idx].low)  continue;
      if(rates[bar_idx].close >= rates[mother_idx].low) continue;

      if(!g_trg_cache_dn_mother.used)
         __TRG1_FillType2DOWN(rates, mother_idx, bar_idx, g_trg_cache_dn_mother);

      if(!g_trg_cache_dn_mflip.used && rates[bar_idx].high > rates[mother_idx].high)
         __TRG_CACHE_FillMFlipDOWN(rates, mother_idx, bar_idx, g_trg_cache_dn_mflip);

      if(g_trg_cache_dn_mother.used && g_trg_cache_dn_mflip.used)
         break;
   }
}

inline bool __TRG1_BuildType2UPFast(const MqlRates &rates[],
                                    const int n,
                                    const int bar_idx,
                                    const datetime from_time,
                                    const datetime to_time,
                                    const int from_idx,
                                    FlipZone &out)
{
   if(bar_idx < 2 || bar_idx >= n) return false;
   if(!__Flip_TimeInWindow(rates[bar_idx].time, from_time, to_time)) return false;
   if(!__Flip_IsBull(rates[bar_idx])) return false;

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
      if(!__Flip_TimeInWindow(rates[mother_idx].time, from_time, to_time)) continue;
      if(!__Flip_IsBear(rates[mother_idx])) continue;

      if(mid_max_high > rates[mother_idx].high) continue;
      if(mid_min_low  < rates[mother_idx].low)  continue;

      if(rates[bar_idx].close <= rates[mother_idx].high) continue;

      __TRG1_FillType2UP(rates, mother_idx, bar_idx, out);
      return true;
   }

   return false;
}

inline bool __TRG1_BuildType2DOWNFast(const MqlRates &rates[],
                                      const int n,
                                      const int bar_idx,
                                      const datetime from_time,
                                      const datetime to_time,
                                      const int from_idx,
                                      FlipZone &out)
{
   if(bar_idx < 2 || bar_idx >= n) return false;
   if(!__Flip_TimeInWindow(rates[bar_idx].time, from_time, to_time)) return false;
   if(!__Flip_IsBear(rates[bar_idx])) return false;

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
      if(!__Flip_TimeInWindow(rates[mother_idx].time, from_time, to_time)) continue;
      if(!__Flip_IsBull(rates[mother_idx])) continue;

      if(mid_max_high > rates[mother_idx].high) continue;
      if(mid_min_low  < rates[mother_idx].low)  continue;

      if(rates[bar_idx].close >= rates[mother_idx].low) continue;

      __TRG1_FillType2DOWN(rates, mother_idx, bar_idx, out);
      return true;
   }

   return false;
}

inline bool Trigger_Type1_ProcessUP(const MqlRates &rates[],
                                    const int n,
                                    const int bar_idx,
                                    const datetime from_time,
                                    const datetime to_time)
{
   if(bar_idx < 0 || bar_idx >= n) return false;

   __TRG_CACHE_BuildUP(rates, n, bar_idx, from_time, to_time);

   // Direct previous-candle Flip keeps priority over mother/inside Flip,
   // matching the original Type-1 engine.
   if(g_trg_cache_up_direct.used)
      return __TRG1_DrawAndFireUP(g_trg_cache_up_direct, rates, n);

   if(g_trg_cache_up_mother.used)
      return __TRG1_DrawAndFireUP(g_trg_cache_up_mother, rates, n);

   return false;
}

inline bool Trigger_Type1_ProcessDOWN(const MqlRates &rates[],
                                      const int n,
                                      const int bar_idx,
                                      const datetime from_time,
                                      const datetime to_time)
{
   if(bar_idx < 0 || bar_idx >= n) return false;

   __TRG_CACHE_BuildDOWN(rates, n, bar_idx, from_time, to_time);

   // Direct previous-candle Flip keeps priority over mother/inside Flip,
   // matching the original Type-1 engine.
   if(g_trg_cache_dn_direct.used)
      return __TRG1_DrawAndFireDOWN(g_trg_cache_dn_direct, rates, n);

   if(g_trg_cache_dn_mother.used)
      return __TRG1_DrawAndFireDOWN(g_trg_cache_dn_mother, rates, n);

   return false;
}

#endif // WAVEBOT_TRIGGER_TYPE1_MQH
