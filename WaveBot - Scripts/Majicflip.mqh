#ifndef WAVEBOT_MAJIC_FLIP_MQH
#define WAVEBOT_MAJIC_FLIP_MQH

#include <WaveBot/Utils.mqh>
#include <WaveBot/Markers.mqh>

// ============================================================================
// Majic Flip
// Visual module.
// UP  : bearish mother -> at least one inside candle -> bullish body-break
//       above mother High, while the same breaker candle wicks below mother Low.
// DOWN: bullish mother -> at least one inside candle -> bearish body-break
//       below mother Low, while the same breaker candle wicks above mother High.
// The rectangle is limited from mother candle time to breaker candle time.
// ============================================================================

struct MajicFlipZone
{
   bool     used;
   int      mother_idx;
   int      breaker_idx;

   datetime mother_time;
   datetime breaker_time;

   double   mother_high;
   double   mother_low;
   double   breaker_high;
   double   breaker_low;

   double   price_top;
   double   price_bottom;
};

static MajicFlipZone g_mflip_up_zones[];
static MajicFlipZone g_mflip_dn_zones[];
static int           g_mflip_up_count = 0;
static int           g_mflip_dn_count = 0;

inline bool __MFlip_ShouldRunOnTF(const ENUM_TIMEFRAMES tf)
{
   if(Markers_GetNamespace() == "MIN")
      return false;

   return true;
}

inline double __MFlip_Eps()
{
   double eps = _Point * 2.0;
   if(eps <= 0.0) eps = 0.00000001;
   return eps;
}

inline bool __MFlip_IsBull(const MqlRates &r)
{
   return (r.close > r.open);
}

inline bool __MFlip_IsBear(const MqlRates &r)
{
   return (r.close < r.open);
}

inline bool __MFlip_InsideMotherHL(const MqlRates &mother, const MqlRates &r)
{
   return (r.high <= mother.high && r.low >= mother.low);
}

inline bool __MFlip_TimeInWindow(const datetime t, const datetime from_time, const datetime to_time)
{
   if(t <= 0) return false;
   if(from_time > 0 && t < from_time) return false;
   if(to_time   > 0 && t > to_time)   return false;
   return true;
}

inline void __MFlip_ResetUP()
{
   ArrayResize(g_mflip_up_zones, 0);
   g_mflip_up_count = 0;
}

inline void __MFlip_ResetDOWN()
{
   ArrayResize(g_mflip_dn_zones, 0);
   g_mflip_dn_count = 0;
}

inline void __MFlip_AddUP(const MajicFlipZone &z)
{
   int pos = g_mflip_up_count;
   ArrayResize(g_mflip_up_zones, pos + 1);
   g_mflip_up_zones[pos] = z;
   g_mflip_up_count = pos + 1;
}

inline void __MFlip_AddDOWN(const MajicFlipZone &z)
{
   int pos = g_mflip_dn_count;
   ArrayResize(g_mflip_dn_zones, pos + 1);
   g_mflip_dn_zones[pos] = z;
   g_mflip_dn_count = pos + 1;
}

inline int MajicFlip_UP_Count()
{
   return g_mflip_up_count;
}

inline int MajicFlip_DOWN_Count()
{
   return g_mflip_dn_count;
}

inline bool MajicFlip_UP_Get(const int index, MajicFlipZone &out)
{
   if(index < 0 || index >= g_mflip_up_count) return false;
   out = g_mflip_up_zones[index];
   return true;
}

inline bool MajicFlip_DOWN_Get(const int index, MajicFlipZone &out)
{
   if(index < 0 || index >= g_mflip_dn_count) return false;
   out = g_mflip_dn_zones[index];
   return true;
}

inline void MajicFlip_ResetGlobals()
{
   __MFlip_ResetUP();
   __MFlip_ResetDOWN();
}

inline void __MFlip_ClearDirectionVisuals(const string tail_prefix)
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

inline bool __MFlip_DrawRect(const string base,
                             const datetime t1,
                             const double price_a,
                             const datetime t2,
                             const double price_b,
                             const color col,
                             const int alpha)
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

   double p_top = MathMax(price_a, price_b);
   double p_bot = MathMin(price_a, price_b);
   if(p_top <= p_bot + __MFlip_Eps())
      p_top = p_bot + __MFlip_Eps();

   int alpha_i = alpha;
   if(alpha_i < 0)   alpha_i = 0;
   if(alpha_i > 255) alpha_i = 255;
   const uchar alpha_u = (uchar)alpha_i;

   const string full = __ScanPrefix() + base;
   if(ObjectFind(0, full) != -1)
      ObjectDelete(0, full);

   if(!ObjectCreate(0, full, OBJ_RECTANGLE, 0, a, p_top, b, p_bot))
   {
      if(InpDebugPrints)
         Print("[MajicFlip] ObjectCreate failed for ", full);
      return false;
   }

   ObjectSetInteger(0, full, OBJPROP_COLOR, (long)ColorToARGB(col, alpha_u));
   ObjectSetInteger(0, full, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, full, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, full, OBJPROP_BACK, true);
   ObjectSetInteger(0, full, OBJPROP_FILL, true);
   ObjectSetInteger(0, full, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, full, OBJPROP_SELECTED, false);

   return true;
}

inline bool __MFlip_BuildUP(const MqlRates &rates[],
                            const int n,
                            const int mother_idx,
                            const datetime from_time,
                            const datetime to_time,
                            MajicFlipZone &out)
{
   if(mother_idx < 0 || mother_idx >= n - 2) return false;
   if(!__MFlip_TimeInWindow(rates[mother_idx].time, from_time, to_time)) return false;
   if(!__MFlip_IsBear(rates[mother_idx])) return false;

   int j = mother_idx + 1;
   int inside_count = 0;

   while(j < n && __MFlip_InsideMotherHL(rates[mother_idx], rates[j]))
   {
      inside_count++;
      j++;
   }

   if(inside_count <= 0) return false;
   if(j >= n) return false;
   if(!__MFlip_TimeInWindow(rates[j].time, from_time, to_time)) return false;

   if(!__MFlip_IsBull(rates[j])) return false;
   if(rates[j].close <= rates[mother_idx].high) return false;
   if(rates[j].low  >= rates[mother_idx].low)  return false;

   out.used         = true;
   out.mother_idx   = mother_idx;
   out.breaker_idx  = j;
   out.mother_time  = rates[mother_idx].time;
   out.breaker_time = rates[j].time;

   out.mother_high  = rates[mother_idx].high;
   out.mother_low   = rates[mother_idx].low;
   out.breaker_high = rates[j].high;
   out.breaker_low  = rates[j].low;

   out.price_top    = rates[mother_idx].high;
   out.price_bottom = rates[j].low;

   return true;
}

inline bool __MFlip_BuildDOWN(const MqlRates &rates[],
                              const int n,
                              const int mother_idx,
                              const datetime from_time,
                              const datetime to_time,
                              MajicFlipZone &out)
{
   if(mother_idx < 0 || mother_idx >= n - 2) return false;
   if(!__MFlip_TimeInWindow(rates[mother_idx].time, from_time, to_time)) return false;
   if(!__MFlip_IsBull(rates[mother_idx])) return false;

   int j = mother_idx + 1;
   int inside_count = 0;

   while(j < n && __MFlip_InsideMotherHL(rates[mother_idx], rates[j]))
   {
      inside_count++;
      j++;
   }

   if(inside_count <= 0) return false;
   if(j >= n) return false;
   if(!__MFlip_TimeInWindow(rates[j].time, from_time, to_time)) return false;

   if(!__MFlip_IsBear(rates[j])) return false;
   if(rates[j].close >= rates[mother_idx].low)  return false;
   if(rates[j].high  <= rates[mother_idx].high) return false;

   out.used         = true;
   out.mother_idx   = mother_idx;
   out.breaker_idx  = j;
   out.mother_time  = rates[mother_idx].time;
   out.breaker_time = rates[j].time;

   out.mother_high  = rates[mother_idx].high;
   out.mother_low   = rates[mother_idx].low;
   out.breaker_high = rates[j].high;
   out.breaker_low  = rates[j].low;

   out.price_top    = rates[j].high;
   out.price_bottom = rates[mother_idx].low;

   return true;
}

inline void __MFlip_DrawUP(const MajicFlipZone &z, int &draw_count)
{
   draw_count++;
   string name = "MAJIC_FLIP_U_" + IntegerToString(draw_count) + "_" + IntegerToString((long)z.mother_time);

   if(__MFlip_DrawRect(name, z.mother_time, z.price_top, z.breaker_time, z.price_bottom, clrPurple, 50) && InpDebugPrints)
   {
      Print("[MAJIC-FLIP-UP] Draw #", draw_count,
            " | mother=", T(z.mother_time),
            " | breaker=", T(z.breaker_time),
            " | rangeLow=", DoubleToString(z.price_bottom, _Digits),
            " | motherHigh=", DoubleToString(z.price_top, _Digits));
   }
}

inline void __MFlip_DrawDOWN(const MajicFlipZone &z, int &draw_count)
{
   draw_count++;
   string name = "MAJIC_FLIP_D_" + IntegerToString(draw_count) + "_" + IntegerToString((long)z.mother_time);

   if(__MFlip_DrawRect(name, z.mother_time, z.price_top, z.breaker_time, z.price_bottom, clrPurple, 50) && InpDebugPrints)
   {
      Print("[MAJIC-FLIP-DOWN] Draw #", draw_count,
            " | mother=", T(z.mother_time),
            " | breaker=", T(z.breaker_time),
            " | rangeHigh=", DoubleToString(z.price_top, _Digits),
            " | motherLow=", DoubleToString(z.price_bottom, _Digits));
   }
}

inline void MajicFlip_RunScan_UP(const string sym,
                                 const ENUM_TIMEFRAMES tf,
                                 const MqlRates &rates[],
                                 const int n,
                                 const datetime from_time,
                                 const datetime to_time)
{
   if(!__MFlip_ShouldRunOnTF(tf)) return;
   __MFlip_ResetUP();
   if(n < 3) return;

   __MFlip_ClearDirectionVisuals("MAJIC_FLIP_U_");

   int draw_count = 0;

   for(int i = 0; i < n; ++i)
   {
      if(to_time > 0 && rates[i].time > to_time)
         break;

      MajicFlipZone z;
      if(__MFlip_BuildUP(rates, n, i, from_time, to_time, z))
      {
         __MFlip_AddUP(z);
         __MFlip_DrawUP(z, draw_count);
      }
   }

   if(InpDebugPrints && draw_count > 0)
      Print("[MAJIC-FLIP-UP] Completed scan | symbol=", sym,
            " | tf=", EnumToString(tf),
            " | rectangles=", draw_count);
}

inline void MajicFlip_RunScan_DOWN(const string sym,
                                   const ENUM_TIMEFRAMES tf,
                                   const MqlRates &rates[],
                                   const int n,
                                   const datetime from_time,
                                   const datetime to_time)
{
   if(!__MFlip_ShouldRunOnTF(tf)) return;
   __MFlip_ResetDOWN();
   if(n < 3) return;

   __MFlip_ClearDirectionVisuals("MAJIC_FLIP_D_");

   int draw_count = 0;

   for(int i = 0; i < n; ++i)
   {
      if(to_time > 0 && rates[i].time > to_time)
         break;

      MajicFlipZone z;
      if(__MFlip_BuildDOWN(rates, n, i, from_time, to_time, z))
      {
         __MFlip_AddDOWN(z);
         __MFlip_DrawDOWN(z, draw_count);
      }
   }

   if(InpDebugPrints && draw_count > 0)
      Print("[MAJIC-FLIP-DOWN] Completed scan | symbol=", sym,
            " | tf=", EnumToString(tf),
            " | rectangles=", draw_count);
}

#endif // WAVEBOT_MAJIC_FLIP_MQH
