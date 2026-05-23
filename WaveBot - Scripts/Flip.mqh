// ============================================================================
#ifndef WAVEBOT_FLIP_MQH
#define WAVEBOT_FLIP_MQH

#include <WaveBot/Utils.mqh>
#include <WaveBot/Markers.mqh>

// ============================================================================
// Flip
// Visual module.
// Type 1 UP  : bullish flip candle wicks below previous Low and closes above
//              previous High. Range = previous High .. flip-candle Low.
// Type 1 DOWN: bearish flip candle wicks above previous High and closes below
//              previous Low. Range = flip-candle High .. previous Low.
// Type 2 UP  : bearish mother contains one or more inside candles, then a
//              bullish candle body-breaks mother High. Range = mother High..Low.
// Type 2 DOWN: bullish mother contains one or more inside candles, then a
//              bearish candle body-breaks mother Low. Range = mother High..Low.
// NOTE: Only Type 1 and Type 2 are active in WaveBot trigger logic.
// ============================================================================

struct FlipZone
{
   bool     used;
   int      kind;          // 1 = direct previous-candle Flip, 2 = opposite-color mother Flip, 3 = same-color mother Flip
   int      anchor_idx;    // previous candle for kind 1, mother candle for kind 2/3
   int      flip_idx;      // Flip candle

   datetime anchor_time;
   datetime flip_time;

   double   anchor_high;
   double   anchor_low;
   double   flip_high;
   double   flip_low;

   double   price_top;
   double   price_bottom;
};

static FlipZone g_flip_up_zones[];
static FlipZone g_flip_dn_zones[];
static int      g_flip_up_count = 0;
static int      g_flip_dn_count = 0;

inline bool __Flip_ShouldRunOnTF(const ENUM_TIMEFRAMES tf)
{
   // Must run in both MAJ and MIN namespaces: M15 stage-2 zones are valid
   // regardless of the world that produced the stage-1 seed. Visual drawing is
   // still governed by Markers_ShouldRender()/preview policy downstream.
   if(tf <= 0) return false;
   return true;
}

inline double __Flip_Eps()
{
   double eps = _Point * 2.0;
   if(eps <= 0.0) eps = 0.00000001;
   return eps;
}

inline bool __Flip_IsBull(const MqlRates &r)
{
   return (r.close > r.open);
}

inline bool __Flip_IsBear(const MqlRates &r)
{
   return (r.close < r.open);
}

inline bool __Flip_InsideMotherHL(const MqlRates &mother, const MqlRates &r)
{
   return (r.high <= mother.high && r.low >= mother.low);
}

inline bool __Flip_TimeInWindow(const datetime t, const datetime from_time, const datetime to_time)
{
   if(t <= 0) return false;
   if(from_time > 0 && t < from_time) return false;
   if(to_time   > 0 && t > to_time)   return false;
   return true;
}

inline void __Flip_ResetUP()
{
   ArrayResize(g_flip_up_zones, 0);
   g_flip_up_count = 0;
}

inline void __Flip_ResetDOWN()
{
   ArrayResize(g_flip_dn_zones, 0);
   g_flip_dn_count = 0;
}

inline void __Flip_AddUP(const FlipZone &z)
{
   int pos = g_flip_up_count;
   ArrayResize(g_flip_up_zones, pos + 1);
   g_flip_up_zones[pos] = z;
   g_flip_up_count = pos + 1;
}

inline void __Flip_AddDOWN(const FlipZone &z)
{
   int pos = g_flip_dn_count;
   ArrayResize(g_flip_dn_zones, pos + 1);
   g_flip_dn_zones[pos] = z;
   g_flip_dn_count = pos + 1;
}

inline int Flip_UP_Count()
{
   return g_flip_up_count;
}

inline int Flip_DOWN_Count()
{
   return g_flip_dn_count;
}

inline bool Flip_UP_Get(const int index, FlipZone &out)
{
   if(index < 0 || index >= g_flip_up_count) return false;
   out = g_flip_up_zones[index];
   return true;
}

inline bool Flip_DOWN_Get(const int index, FlipZone &out)
{
   if(index < 0 || index >= g_flip_dn_count) return false;
   out = g_flip_dn_zones[index];
   return true;
}

inline void Flip_ResetGlobals()
{
   __Flip_ResetUP();
   __Flip_ResetDOWN();
}

inline void __Flip_ClearDirectionVisuals(const string tail_prefix)
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

inline bool __Flip_DrawRect(const string base,
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
   if(p_top <= p_bot + __Flip_Eps())
      p_top = p_bot + __Flip_Eps();

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
         Print("[Flip] ObjectCreate failed for ", full);
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

inline bool __Flip_BuildType1UP(const MqlRates &rates[],
                                const int n,
                                const int flip_idx,
                                const datetime from_time,
                                const datetime to_time,
                                FlipZone &out)
{
   if(flip_idx <= 0 || flip_idx >= n) return false;
   if(!__Flip_TimeInWindow(rates[flip_idx].time, from_time, to_time)) return false;

   int prev_idx = flip_idx - 1;

   if(!__Flip_IsBull(rates[flip_idx])) return false;
   if(rates[flip_idx].low   >= rates[prev_idx].low)  return false;
   if(rates[flip_idx].close <= rates[prev_idx].high) return false;

   out.used        = true;
   out.kind        = 1;
   out.anchor_idx  = prev_idx;
   out.flip_idx    = flip_idx;
   out.anchor_time = rates[prev_idx].time;
   out.flip_time   = rates[flip_idx].time;

   out.anchor_high = rates[prev_idx].high;
   out.anchor_low  = rates[prev_idx].low;
   out.flip_high   = rates[flip_idx].high;
   out.flip_low    = rates[flip_idx].low;

   out.price_top    = rates[prev_idx].high;
   out.price_bottom = rates[flip_idx].low;

   return true;
}

inline bool __Flip_BuildType1DOWN(const MqlRates &rates[],
                                  const int n,
                                  const int flip_idx,
                                  const datetime from_time,
                                  const datetime to_time,
                                  FlipZone &out)
{
   if(flip_idx <= 0 || flip_idx >= n) return false;
   if(!__Flip_TimeInWindow(rates[flip_idx].time, from_time, to_time)) return false;

   int prev_idx = flip_idx - 1;

   if(!__Flip_IsBear(rates[flip_idx])) return false;
   if(rates[flip_idx].high  <= rates[prev_idx].high) return false;
   if(rates[flip_idx].close >= rates[prev_idx].low)  return false;

   out.used        = true;
   out.kind        = 1;
   out.anchor_idx  = prev_idx;
   out.flip_idx    = flip_idx;
   out.anchor_time = rates[prev_idx].time;
   out.flip_time   = rates[flip_idx].time;

   out.anchor_high = rates[prev_idx].high;
   out.anchor_low  = rates[prev_idx].low;
   out.flip_high   = rates[flip_idx].high;
   out.flip_low    = rates[flip_idx].low;

   out.price_top    = rates[flip_idx].high;
   out.price_bottom = rates[prev_idx].low;

   return true;
}

inline bool __Flip_BuildType2UP(const MqlRates &rates[],
                                const int n,
                                const int mother_idx,
                                const datetime from_time,
                                const datetime to_time,
                                FlipZone &out)
{
   if(mother_idx < 0 || mother_idx >= n - 2) return false;
   if(!__Flip_TimeInWindow(rates[mother_idx].time, from_time, to_time)) return false;
   if(!__Flip_IsBear(rates[mother_idx])) return false;

   int j = mother_idx + 1;
   int inside_count = 0;

   while(j < n && __Flip_InsideMotherHL(rates[mother_idx], rates[j]))
   {
      inside_count++;
      j++;
   }

   if(inside_count <= 0) return false;
   if(j >= n) return false;
   if(!__Flip_TimeInWindow(rates[j].time, from_time, to_time)) return false;

   if(!__Flip_IsBull(rates[j])) return false;
   if(rates[j].close <= rates[mother_idx].high) return false;

   out.used        = true;
   out.kind        = 2;
   out.anchor_idx  = mother_idx;
   out.flip_idx    = j;
   out.anchor_time = rates[mother_idx].time;
   out.flip_time   = rates[j].time;

   out.anchor_high = rates[mother_idx].high;
   out.anchor_low  = rates[mother_idx].low;
   out.flip_high   = rates[j].high;
   out.flip_low    = rates[j].low;

   out.price_top    = rates[mother_idx].high;
   out.price_bottom = rates[mother_idx].low;

   return true;
}

inline bool __Flip_BuildType2DOWN(const MqlRates &rates[],
                                  const int n,
                                  const int mother_idx,
                                  const datetime from_time,
                                  const datetime to_time,
                                  FlipZone &out)
{
   if(mother_idx < 0 || mother_idx >= n - 2) return false;
   if(!__Flip_TimeInWindow(rates[mother_idx].time, from_time, to_time)) return false;
   if(!__Flip_IsBull(rates[mother_idx])) return false;

   int j = mother_idx + 1;
   int inside_count = 0;

   while(j < n && __Flip_InsideMotherHL(rates[mother_idx], rates[j]))
   {
      inside_count++;
      j++;
   }

   if(inside_count <= 0) return false;
   if(j >= n) return false;
   if(!__Flip_TimeInWindow(rates[j].time, from_time, to_time)) return false;

   if(!__Flip_IsBear(rates[j])) return false;
   if(rates[j].close >= rates[mother_idx].low) return false;

   out.used        = true;
   out.kind        = 2;
   out.anchor_idx  = mother_idx;
   out.flip_idx    = j;
   out.anchor_time = rates[mother_idx].time;
   out.flip_time   = rates[j].time;

   out.anchor_high = rates[mother_idx].high;
   out.anchor_low  = rates[mother_idx].low;
   out.flip_high   = rates[j].high;
   out.flip_low    = rates[j].low;

   out.price_top    = rates[mother_idx].high;
   out.price_bottom = rates[mother_idx].low;

   return true;
}

inline bool __Flip_BuildType3UP(const MqlRates &rates[],
                                const int n,
                                const int mother_idx,
                                const datetime from_time,
                                const datetime to_time,
                                FlipZone &out)
{
   if(mother_idx < 0 || mother_idx >= n - 2) return false;
   if(!__Flip_TimeInWindow(rates[mother_idx].time, from_time, to_time)) return false;
   if(!__Flip_IsBull(rates[mother_idx])) return false;

   int j = mother_idx + 1;
   int inside_count = 0;

   while(j < n && __Flip_InsideMotherHL(rates[mother_idx], rates[j]))
   {
      inside_count++;
      j++;
   }

   if(inside_count <= 0) return false;
   if(j >= n) return false;
   if(!__Flip_TimeInWindow(rates[j].time, from_time, to_time)) return false;

   if(!__Flip_IsBull(rates[j])) return false;
   if(rates[j].close <= rates[mother_idx].high) return false;

   out.used        = true;
   out.kind        = 3;
   out.anchor_idx  = mother_idx;
   out.flip_idx    = j;
   out.anchor_time = rates[mother_idx].time;
   out.flip_time   = rates[j].time;

   out.anchor_high = rates[mother_idx].high;
   out.anchor_low  = rates[mother_idx].low;
   out.flip_high   = rates[j].high;
   out.flip_low    = rates[j].low;

   out.price_top    = rates[mother_idx].high;
   out.price_bottom = rates[mother_idx].low;

   return true;
}

inline bool __Flip_BuildType3DOWN(const MqlRates &rates[],
                                  const int n,
                                  const int mother_idx,
                                  const datetime from_time,
                                  const datetime to_time,
                                  FlipZone &out)
{
   if(mother_idx < 0 || mother_idx >= n - 2) return false;
   if(!__Flip_TimeInWindow(rates[mother_idx].time, from_time, to_time)) return false;
   if(!__Flip_IsBear(rates[mother_idx])) return false;

   int j = mother_idx + 1;
   int inside_count = 0;

   while(j < n && __Flip_InsideMotherHL(rates[mother_idx], rates[j]))
   {
      inside_count++;
      j++;
   }

   if(inside_count <= 0) return false;
   if(j >= n) return false;
   if(!__Flip_TimeInWindow(rates[j].time, from_time, to_time)) return false;

   if(!__Flip_IsBear(rates[j])) return false;
   if(rates[j].close >= rates[mother_idx].low) return false;

   out.used        = true;
   out.kind        = 3;
   out.anchor_idx  = mother_idx;
   out.flip_idx    = j;
   out.anchor_time = rates[mother_idx].time;
   out.flip_time   = rates[j].time;

   out.anchor_high = rates[mother_idx].high;
   out.anchor_low  = rates[mother_idx].low;
   out.flip_high   = rates[j].high;
   out.flip_low    = rates[j].low;

   out.price_top    = rates[mother_idx].high;
   out.price_bottom = rates[mother_idx].low;

   return true;
}

inline void __Flip_DrawUP(const FlipZone &z, int &draw_count)
{
   draw_count++;
   string name = "FLIP_U_T" + IntegerToString(z.kind) + "_" + IntegerToString(draw_count) + "_" + IntegerToString((long)z.anchor_time);

   if(__Flip_DrawRect(name, z.anchor_time, z.price_top, z.flip_time, z.price_bottom, clrDeepPink, 42) && InpDebugPrints)
   {
      Print("[FLIP-UP] Draw #", draw_count,
            " | type=", z.kind,
            " | anchor=", T(z.anchor_time),
            " | flip=", T(z.flip_time),
            " | top=", DoubleToString(z.price_top, _Digits),
            " | bottom=", DoubleToString(z.price_bottom, _Digits));
   }
}

inline void __Flip_DrawDOWN(const FlipZone &z, int &draw_count)
{
   draw_count++;
   string name = "FLIP_D_T" + IntegerToString(z.kind) + "_" + IntegerToString(draw_count) + "_" + IntegerToString((long)z.anchor_time);

   if(__Flip_DrawRect(name, z.anchor_time, z.price_top, z.flip_time, z.price_bottom, clrDeepPink, 42) && InpDebugPrints)
   {
      Print("[FLIP-DOWN] Draw #", draw_count,
            " | type=", z.kind,
            " | anchor=", T(z.anchor_time),
            " | flip=", T(z.flip_time),
            " | top=", DoubleToString(z.price_top, _Digits),
            " | bottom=", DoubleToString(z.price_bottom, _Digits));
   }
}

inline void Flip_RunScan_UP(const string sym,
                            const ENUM_TIMEFRAMES tf,
                            const MqlRates &rates[],
                            const int n,
                            const datetime from_time,
                            const datetime to_time)
{
   if(!__Flip_ShouldRunOnTF(tf)) return;
   __Flip_ResetUP();
   if(n < 2) return;

   __Flip_ClearDirectionVisuals("FLIP_U_");

   int draw_count = 0;

   for(int i = 0; i < n; ++i)
   {
      if(to_time > 0 && rates[i].time > to_time)
         break;

      FlipZone t1;
      if(__Flip_BuildType1UP(rates, n, i, from_time, to_time, t1))
      {
         __Flip_AddUP(t1);
         __Flip_DrawUP(t1, draw_count);
      }

      FlipZone t2;
      if(__Flip_BuildType2UP(rates, n, i, from_time, to_time, t2))
      {
         __Flip_AddUP(t2);
         __Flip_DrawUP(t2, draw_count);
      }

      // Type 3 is intentionally disabled.
   }

   if(InpDebugPrints && draw_count > 0)
      Print("[FLIP-UP] Completed scan | symbol=", sym,
            " | tf=", EnumToString(tf),
            " | rectangles=", draw_count);
}

inline void Flip_RunScan_DOWN(const string sym,
                              const ENUM_TIMEFRAMES tf,
                              const MqlRates &rates[],
                              const int n,
                              const datetime from_time,
                              const datetime to_time)
{
   if(!__Flip_ShouldRunOnTF(tf)) return;
   __Flip_ResetDOWN();
   if(n < 2) return;

   __Flip_ClearDirectionVisuals("FLIP_D_");

   int draw_count = 0;

   for(int i = 0; i < n; ++i)
   {
      if(to_time > 0 && rates[i].time > to_time)
         break;

      FlipZone t1;
      if(__Flip_BuildType1DOWN(rates, n, i, from_time, to_time, t1))
      {
         __Flip_AddDOWN(t1);
         __Flip_DrawDOWN(t1, draw_count);
      }

      FlipZone t2;
      if(__Flip_BuildType2DOWN(rates, n, i, from_time, to_time, t2))
      {
         __Flip_AddDOWN(t2);
         __Flip_DrawDOWN(t2, draw_count);
      }

      // Type 3 is intentionally disabled.
   }

   if(InpDebugPrints && draw_count > 0)
      Print("[FLIP-DOWN] Completed scan | symbol=", sym,
            " | tf=", EnumToString(tf),
            " | rectangles=", draw_count);
}

#endif // WAVEBOT_FLIP_MQH
