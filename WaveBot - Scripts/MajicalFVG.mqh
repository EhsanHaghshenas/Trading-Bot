#ifndef WAVEBOT_MAJICAL_FVG_MQH
#define WAVEBOT_MAJICAL_FVG_MQH

#include <WaveBot/Utils.mqh>
#include <WaveBot/Markers.mqh>
#include <WaveBot/Types.mqh>

// ============================================================================
// Majical FVG
// Scope: visual detection only on H4 and M15 major worlds.
// UP  : bearish mother candle -> inside cluster -> bullish body break -> first
//       penetration into the break-body zone -> reference-high break.
// DOWN: bullish mother candle -> inside cluster -> bearish body break -> first
//       penetration into the break-body zone -> reference-low break.
// ============================================================================

struct MajicalFVGTrack
{
   bool     used;
   bool     entered;
   bool     done;

   int      mother_idx;
   int      breaker_idx;
   int      entry_idx;

   datetime mother_time;
   datetime breaker_time;
   datetime entry_time;

   double   base_level;       // UP: High(mother) | DOWN: Low(mother)
   double   zone_far_level;   // UP: body high of breaker | DOWN: body low of breaker
   double   ref_level;        // UP: highest high before first entry | DOWN: lowest low before first entry
   double   deepest_level;    // UP: lowest valid penetration | DOWN: highest valid penetration
};

struct MajicalFVGZone
{
   bool     used;
   bool     keep;

   int      mother_idx;
   int      breaker_idx;
   int      entry_idx;

   datetime mother_time;
   datetime breaker_time;
   datetime entry_time;

   double   base_level;
   double   zone_far_level;
   double   ref_level;
   double   deepest_level;
};

inline bool __MFVG_ShouldRunOnTF(const ENUM_TIMEFRAMES tf)
{
   if(tf != PERIOD_H4 && tf != PERIOD_M15)
      return false;

   // The user requested H4/M15 chart detection only.  Minor-world scans on H4
   // are intentionally skipped so local minor sessions do not create MFVGs.
   if(Markers_GetNamespace() == "MIN")
      return false;

   return true;
}

inline bool __MFVG_IsBull(const MqlRates &r)
{
   return (r.close > r.open);
}

inline bool __MFVG_IsBear(const MqlRates &r)
{
   return (r.close < r.open);
}

inline bool __MFVG_InsideMotherHL(const MqlRates &mother, const MqlRates &r)
{
   return (r.high <= mother.high && r.low >= mother.low);
}

inline double __MFVG_BodyHigh(const MqlRates &r)
{
   return MathMax(r.open, r.close);
}

inline double __MFVG_BodyLow(const MqlRates &r)
{
   return MathMin(r.open, r.close);
}

inline double __MFVG_Eps()
{
   double eps = _Point * 2.0;
   if(eps <= 0.0) eps = 0.00000001;
   return eps;
}

inline double __MFVG_HighestHigh(const MqlRates &rates[], const int from, const int to)
{
   if(from > to) return -DBL_MAX;

   double best = -DBL_MAX;
   for(int i = from; i <= to; ++i)
   {
      if(rates[i].high > best)
         best = rates[i].high;
   }
   return best;
}

inline double __MFVG_LowestLow(const MqlRates &rates[], const int from, const int to)
{
   if(from > to) return DBL_MAX;

   double best = DBL_MAX;
   for(int i = from; i <= to; ++i)
   {
      if(rates[i].low < best)
         best = rates[i].low;
   }
   return best;
}

inline bool __MFVG_TimeInWindow(const datetime t, const datetime from_time, const datetime to_time)
{
   if(t <= 0) return false;
   if(from_time > 0 && t < from_time) return false;
   if(to_time   > 0 && t > to_time)   return false;
   return true;
}

inline void __MFVG_RemoveTrack(MajicalFVGTrack &tracks[], int &count, const int pos)
{
   if(pos < 0 || pos >= count) return;

   for(int i = pos; i < count - 1; ++i)
      tracks[i] = tracks[i + 1];

   count--;
   if(count < 0) count = 0;
   ArrayResize(tracks, count);
}

inline void __MFVG_AddTrack(MajicalFVGTrack &tracks[], int &count, const MajicalFVGTrack &z)
{
   int pos = count;
   ArrayResize(tracks, count + 1);
   tracks[pos] = z;
   count++;
}

inline bool __MFVG_BuildCandidateUP(const MqlRates &rates[], const int n,
                                    const int mother_idx,
                                    const datetime from_time,
                                    const datetime to_time,
                                    MajicalFVGTrack &out)
{
   if(mother_idx < 0 || mother_idx >= n - 2) return false;
   if(!__MFVG_TimeInWindow(rates[mother_idx].time, from_time, to_time)) return false;
   if(!__MFVG_IsBear(rates[mother_idx])) return false;

   int j = mother_idx + 1;
   int inside_count = 0;
   while(j < n && __MFVG_InsideMotherHL(rates[mother_idx], rates[j]))
   {
      inside_count++;
      j++;
   }

   if(inside_count <= 0) return false;
   if(j >= n) return false;
   if(to_time > 0 && rates[j].time > to_time) return false;

   if(!__MFVG_IsBull(rates[j])) return false;
   if(rates[j].close <= rates[mother_idx].high) return false;

   double base_level = rates[mother_idx].high;
   double zone_far   = __MFVG_BodyHigh(rates[j]);
   if(zone_far <= base_level + __MFVG_Eps()) return false;

   out.used           = true;
   out.entered        = false;
   out.done           = false;
   out.mother_idx     = mother_idx;
   out.breaker_idx    = j;
   out.entry_idx      = -1;
   out.mother_time    = rates[mother_idx].time;
   out.breaker_time   = rates[j].time;
   out.entry_time     = 0;
   out.base_level     = base_level;
   out.zone_far_level = zone_far;
   out.ref_level      = __MFVG_HighestHigh(rates, mother_idx, j);
   out.deepest_level  = 0.0;

   return true;
}

inline bool __MFVG_BuildCandidateDOWN(const MqlRates &rates[], const int n,
                                      const int mother_idx,
                                      const datetime from_time,
                                      const datetime to_time,
                                      MajicalFVGTrack &out)
{
   if(mother_idx < 0 || mother_idx >= n - 2) return false;
   if(!__MFVG_TimeInWindow(rates[mother_idx].time, from_time, to_time)) return false;
   if(!__MFVG_IsBull(rates[mother_idx])) return false;

   int j = mother_idx + 1;
   int inside_count = 0;
   while(j < n && __MFVG_InsideMotherHL(rates[mother_idx], rates[j]))
   {
      inside_count++;
      j++;
   }

   if(inside_count <= 0) return false;
   if(j >= n) return false;
   if(to_time > 0 && rates[j].time > to_time) return false;

   if(!__MFVG_IsBear(rates[j])) return false;
   if(rates[j].close >= rates[mother_idx].low) return false;

   double base_level = rates[mother_idx].low;
   double zone_far   = __MFVG_BodyLow(rates[j]);
   if(zone_far >= base_level - __MFVG_Eps()) return false;

   out.used           = true;
   out.entered        = false;
   out.done           = false;
   out.mother_idx     = mother_idx;
   out.breaker_idx    = j;
   out.entry_idx      = -1;
   out.mother_time    = rates[mother_idx].time;
   out.breaker_time   = rates[j].time;
   out.entry_time     = 0;
   out.base_level     = base_level;
   out.zone_far_level = zone_far;
   out.ref_level      = __MFVG_LowestLow(rates, mother_idx, j);
   out.deepest_level  = 0.0;

   return true;
}

inline bool __MFVG_DrawRect(const string base,
                            const datetime t1,
                            const double price_a,
                            const datetime t2,
                            const double price_b)
{
   if(!Markers_ShouldRender()) return false;

   datetime a = t1;
   datetime b = t2;
   if(b < a)
   {
      datetime tmp = a;
      a = b;
      b = tmp;
   }

   double p_top    = MathMax(price_a, price_b);
   double p_bottom = MathMin(price_a, price_b);

   if(p_top <= p_bottom + __MFVG_Eps())
      p_top = p_bottom + __MFVG_Eps();

   const string full = __ScanPrefix() + base;
   if(ObjectFind(0, full) != -1)
      ObjectDelete(0, full);

   if(!ObjectCreate(0, full, OBJ_RECTANGLE, 0, a, p_top, b, p_bottom))
   {
      if(InpDebugPrints)
         Print("[MFVG] ObjectCreate failed for ", full);
      return false;
   }

   ObjectSetInteger(0, full, OBJPROP_COLOR, (long)ColorToARGB(clrOrange, 70));
   ObjectSetInteger(0, full, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, full, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, full, OBJPROP_BACK, true);
   ObjectSetInteger(0, full, OBJPROP_FILL, true);
   ObjectSetInteger(0, full, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, full, OBJPROP_SELECTED, false);

   return true;
}


inline void __MFVG_ClearDirectionVisuals(const string tail_prefix)
{
   const string p = __ScanPrefix();
   const int plen = StringLen(p);

   for(int oi = ObjectsTotal(0) - 1; oi >= 0; --oi)
   {
      string on = ObjectName(0, oi);
      if(on == "" || StringLen(on) < plen) continue;
      if(StringSubstr(on, 0, plen) != p) continue;

      string tail = StringSubstr(on, plen);
      if(StringFind(tail, tail_prefix) == 0)
         ObjectDelete(0, on);
   }
}

inline void __MFVG_AddZone(MajicalFVGZone &zones[], int &count, const MajicalFVGTrack &z)
{
   int pos = count;
   ArrayResize(zones, count + 1);

   zones[pos].used           = true;
   zones[pos].keep           = true;
   zones[pos].mother_idx     = z.mother_idx;
   zones[pos].breaker_idx    = z.breaker_idx;
   zones[pos].entry_idx      = z.entry_idx;
   zones[pos].mother_time    = z.mother_time;
   zones[pos].breaker_time   = z.breaker_time;
   zones[pos].entry_time     = z.entry_time;
   zones[pos].base_level     = z.base_level;
   zones[pos].zone_far_level = z.zone_far_level;
   zones[pos].ref_level      = z.ref_level;
   zones[pos].deepest_level  = z.deepest_level;

   count++;
}

inline void __MFVG_StoreConfirmUP(const MqlRates &rates[], const int n,
                                  const MajicalFVGTrack &z,
                                  MajicalFVGZone &zones[],
                                  int &zone_count)
{
   if(z.mother_idx < 0 || z.mother_idx >= n) return;
   if(z.breaker_idx < 0 || z.breaker_idx >= n) return;
   if(z.entry_idx  < 0 || z.entry_idx  >= n) return;

   __MFVG_AddZone(zones, zone_count, z);
}

inline void __MFVG_StoreConfirmDOWN(const MqlRates &rates[], const int n,
                                    const MajicalFVGTrack &z,
                                    MajicalFVGZone &zones[],
                                    int &zone_count)
{
   if(z.mother_idx < 0 || z.mother_idx >= n) return;
   if(z.breaker_idx < 0 || z.breaker_idx >= n) return;
   if(z.entry_idx  < 0 || z.entry_idx  >= n) return;

   __MFVG_AddZone(zones, zone_count, z);
}

inline bool __MFVG_ZoneHasNestedPreferredMother(const MajicalFVGZone &outer,
                                                const MajicalFVGZone &inner)
{
   if(!outer.used || !inner.used) return false;

   // The nested mother is valid only when it is inside the candle group that
   // belonged to the outer mother before the outer body-break candle.
   if(inner.mother_idx <= outer.mother_idx) return false;
   if(outer.breaker_idx <= outer.mother_idx) return false;
   if(inner.mother_idx >= outer.breaker_idx) return false;

   return true;
}

inline void __MFVG_FilterNestedMotherPriority(MajicalFVGZone &zones[],
                                              const int count)
{
   for(int i = 0; i < count; ++i)
      zones[i].keep = zones[i].used;

   for(int i = 0; i < count; ++i)
   {
      if(!zones[i].used) continue;

      for(int j = 0; j < count; ++j)
      {
         if(i == j) continue;
         if(!zones[j].used) continue;

         if(__MFVG_ZoneHasNestedPreferredMother(zones[i], zones[j]))
         {
            zones[i].keep = false;

            if(InpDebugPrints)
            {
               Print("[MFVG] Nested mother priority: skip outer mother ",
                     T(zones[i].mother_time),
                     " because inner mother ",
                     T(zones[j].mother_time),
                     " created a valid Majical FVG.");
            }
            break;
         }
      }
   }
}

inline void __MFVG_DrawStoredUP(const MajicalFVGZone &z,
                                int &draw_count)
{
   double top = z.deepest_level;
   if(top <= z.base_level + __MFVG_Eps())
      top = z.base_level + __MFVG_Eps();

   draw_count++;
   string name = "MFVG_U_" + IntegerToString(draw_count) + "_" + IntegerToString((long)z.mother_time);

   if(__MFVG_DrawRect(name, z.mother_time, top, z.entry_time, z.base_level) && InpDebugPrints)
   {
      Print("[MFVG-UP] Draw #", draw_count,
            " | mother=", T(z.mother_time),
            " | entry=", T(z.entry_time),
            " | base=", DoubleToString(z.base_level, _Digits),
            " | deepest=", DoubleToString(top, _Digits),
            " | refH=", DoubleToString(z.ref_level, _Digits));
   }
}

inline void __MFVG_DrawStoredDOWN(const MajicalFVGZone &z,
                                  int &draw_count)
{
   double bottom = z.deepest_level;
   if(bottom >= z.base_level - __MFVG_Eps())
      bottom = z.base_level - __MFVG_Eps();

   draw_count++;
   string name = "MFVG_D_" + IntegerToString(draw_count) + "_" + IntegerToString((long)z.mother_time);

   if(__MFVG_DrawRect(name, z.mother_time, z.base_level, z.entry_time, bottom) && InpDebugPrints)
   {
      Print("[MFVG-DOWN] Draw #", draw_count,
            " | mother=", T(z.mother_time),
            " | entry=", T(z.entry_time),
            " | base=", DoubleToString(z.base_level, _Digits),
            " | deepest=", DoubleToString(bottom, _Digits),
            " | refL=", DoubleToString(z.ref_level, _Digits));
   }
}

inline void __MFVG_DrawStoredZonesUP(MajicalFVGZone &zones[],
                                     const int zone_count,
                                     int &draw_count)
{
   __MFVG_FilterNestedMotherPriority(zones, zone_count);

   for(int i = 0; i < zone_count; ++i)
   {
      if(!zones[i].used) continue;
      if(!zones[i].keep) continue;

      __MFVG_DrawStoredUP(zones[i], draw_count);
   }
}

inline void __MFVG_DrawStoredZonesDOWN(MajicalFVGZone &zones[],
                                       const int zone_count,
                                       int &draw_count)
{
   __MFVG_FilterNestedMotherPriority(zones, zone_count);

   for(int i = 0; i < zone_count; ++i)
   {
      if(!zones[i].used) continue;
      if(!zones[i].keep) continue;

      __MFVG_DrawStoredDOWN(zones[i], draw_count);
   }
}

inline void __MFVG_ProcessTrackUP(const MqlRates &rates[], const int n,
                                  MajicalFVGTrack &z,
                                  const int bar_idx,
                                  MajicalFVGZone &zones[],
                                  int &zone_count)
{
   if(!z.used || z.done) return;
   if(bar_idx <= z.breaker_idx) return;
   if(bar_idx < 0 || bar_idx >= n) return;

   const MqlRates r = rates[bar_idx];

   if(!z.entered)
   {
      bool touches_zone = (r.low <= z.zone_far_level && r.high >= z.base_level);
      if(!touches_zone)
      {
         if(r.high > z.ref_level)
            z.ref_level = r.high;
         return;
      }

      if(r.low < z.base_level)
      {
         z.done = true;
         return;
      }

      z.entered       = true;
      z.entry_idx     = bar_idx;
      z.entry_time    = r.time;
      z.deepest_level = MathMin(r.low, z.zone_far_level);
      if(z.deepest_level < z.base_level)
         z.deepest_level = z.base_level;

      if(r.high > z.ref_level)
      {
         __MFVG_StoreConfirmUP(rates, n, z, zones, zone_count);
         z.done = true;
      }
      return;
   }

   if(r.low < z.base_level)
   {
      z.done = true;
      return;
   }

   if(r.low <= z.zone_far_level && r.high >= z.base_level)
   {
      double p = MathMin(r.low, z.zone_far_level);
      if(p < z.base_level) p = z.base_level;
      if(p < z.deepest_level)
         z.deepest_level = p;
   }

   if(r.high > z.ref_level)
   {
      __MFVG_StoreConfirmUP(rates, n, z, zones, zone_count);
      z.done = true;
   }
}

inline void __MFVG_ProcessTrackDOWN(const MqlRates &rates[], const int n,
                                    MajicalFVGTrack &z,
                                    const int bar_idx,
                                    MajicalFVGZone &zones[],
                                    int &zone_count)
{
   if(!z.used || z.done) return;
   if(bar_idx <= z.breaker_idx) return;
   if(bar_idx < 0 || bar_idx >= n) return;

   const MqlRates r = rates[bar_idx];

   if(!z.entered)
   {
      bool touches_zone = (r.high >= z.zone_far_level && r.low <= z.base_level);
      if(!touches_zone)
      {
         if(r.low < z.ref_level)
            z.ref_level = r.low;
         return;
      }

      if(r.high > z.base_level)
      {
         z.done = true;
         return;
      }

      z.entered       = true;
      z.entry_idx     = bar_idx;
      z.entry_time    = r.time;
      z.deepest_level = MathMax(r.high, z.zone_far_level);
      if(z.deepest_level > z.base_level)
         z.deepest_level = z.base_level;

      if(r.low < z.ref_level)
      {
         __MFVG_StoreConfirmDOWN(rates, n, z, zones, zone_count);
         z.done = true;
      }
      return;
   }

   if(r.high > z.base_level)
   {
      z.done = true;
      return;
   }

   if(r.high >= z.zone_far_level && r.low <= z.base_level)
   {
      double p = MathMax(r.high, z.zone_far_level);
      if(p > z.base_level) p = z.base_level;
      if(p > z.deepest_level)
         z.deepest_level = p;
   }

   if(r.low < z.ref_level)
   {
      __MFVG_StoreConfirmDOWN(rates, n, z, zones, zone_count);
      z.done = true;
   }
}

inline void MajicalFVG_RunScan_UP(const string sym,
                                  const ENUM_TIMEFRAMES tf,
                                  const MqlRates &rates[],
                                  const int n,
                                  const datetime from_time,
                                  const datetime to_time)
{
   if(!__MFVG_ShouldRunOnTF(tf)) return;
   if(n < 4) return;

   __MFVG_ClearDirectionVisuals("MFVG_U_");

   MajicalFVGTrack tracks[];
   int track_count = 0;

   MajicalFVGZone zones[];
   int zone_count = 0;
   int draw_count = 0;

   for(int i = 0; i < n; ++i)
   {
      if(to_time > 0 && rates[i].time > to_time)
         break;

      // First update already-created zones on this candle.
      for(int k = track_count - 1; k >= 0; --k)
      {
         __MFVG_ProcessTrackUP(rates, n, tracks[k], i, zones, zone_count);
         if(tracks[k].done)
            __MFVG_RemoveTrack(tracks, track_count, k);
      }

      // Then register new mother/inside/body-break structures.
      MajicalFVGTrack z;
      if(__MFVG_BuildCandidateUP(rates, n, i, from_time, to_time, z))
         __MFVG_AddTrack(tracks, track_count, z);
   }

   __MFVG_DrawStoredZonesUP(zones, zone_count, draw_count);

   if(InpDebugPrints && draw_count > 0)
      Print("[MFVG-UP] Completed scan | symbol=", sym,
            " | tf=", EnumToString(tf),
            " | rectangles=", draw_count,
            " | confirmed_candidates=", zone_count);
}

inline void MajicalFVG_RunScan_DOWN(const string sym,
                                    const ENUM_TIMEFRAMES tf,
                                    const MqlRates &rates[],
                                    const int n,
                                    const datetime from_time,
                                    const datetime to_time)
{
   if(!__MFVG_ShouldRunOnTF(tf)) return;
   if(n < 4) return;

   __MFVG_ClearDirectionVisuals("MFVG_D_");

   MajicalFVGTrack tracks[];
   int track_count = 0;

   MajicalFVGZone zones[];
   int zone_count = 0;
   int draw_count = 0;

   for(int i = 0; i < n; ++i)
   {
      if(to_time > 0 && rates[i].time > to_time)
         break;

      // First update already-created zones on this candle.
      for(int k = track_count - 1; k >= 0; --k)
      {
         __MFVG_ProcessTrackDOWN(rates, n, tracks[k], i, zones, zone_count);
         if(tracks[k].done)
            __MFVG_RemoveTrack(tracks, track_count, k);
      }

      // Then register new mother/inside/body-break structures.
      MajicalFVGTrack z;
      if(__MFVG_BuildCandidateDOWN(rates, n, i, from_time, to_time, z))
         __MFVG_AddTrack(tracks, track_count, z);
   }

   __MFVG_DrawStoredZonesDOWN(zones, zone_count, draw_count);

   if(InpDebugPrints && draw_count > 0)
      Print("[MFVG-DOWN] Completed scan | symbol=", sym,
            " | tf=", EnumToString(tf),
            " | rectangles=", draw_count,
            " | confirmed_candidates=", zone_count);
}

#endif // WAVEBOT_MAJICAL_FVG_MQH
