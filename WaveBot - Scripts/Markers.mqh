#ifndef WAVEBOT_MARKERS_MQH
#define WAVEBOT_MARKERS_MQH

#include <WaveBot/Types.mqh>

extern int g_scan_id;  // defined in WaveBot.mq5

// Optional extra namespace for parallel worlds (e.g., "MAJ", "MIN").
// Empty => legacy behavior (no extra namespace).
static string g_markers_ns = "";

// Preview mode is used by WorldManager and by Central Multi-Symbol non-primary
// passes. In preview mode, chart objects stay silent only. Signal/bridge
// publication must remain active so non-visual symbols still generate valid
// M15->M1 windows and can be traded/reported independently.
static bool   g_markers_preview_mode = false;

// set/get world namespace (used later by WorldManager)
inline void   Markers_SetNamespace(const string ns){ g_markers_ns = ns; }
inline string Markers_GetNamespace(){ return g_markers_ns; }

inline void Markers_SetPreviewMode(const bool enabled){ g_markers_preview_mode = enabled; }
inline bool Markers_IsPreviewMode(){ return g_markers_preview_mode; }
inline bool Markers_ShouldRender()
{
   if(!InpDrawMarkers) return false;
   if(g_markers_preview_mode) return false;
   if(!WB_RuntimeAllowMarkerRender()) return false;
   return true;
}

// Scan prefix (unique per scan) + optional world namespace
inline string __ScanPrefix()
{
   if(g_markers_ns == "")
      return "S" + IntegerToString(g_scan_id) + "_";
   return "S" + IntegerToString(g_scan_id) + "_" + g_markers_ns + "_";
}

void MarkV(const string name, const datetime t, const color col)
{
   if(!Markers_ShouldRender()) return;
   const string full = __ScanPrefix() + name;
   if(ObjectFind(0,full)!=-1) ObjectDelete(0,full);
   ObjectCreate(0,full,OBJ_VLINE,0,t,0);
   ObjectSetInteger(0,full,OBJPROP_COLOR,col);
   ObjectSetInteger(0,full,OBJPROP_STYLE,STYLE_DOT);
   ObjectSetInteger(0,full,OBJPROP_WIDTH,1);
}

// ماکر متنی روی نمودار (کنار کندل – بر اساس time و price)
void MarkCandleText(const string name,
                    const datetime t,
                    const double   price,
                    const string   text,
                    const color    col)
{
   if(!Markers_ShouldRender()) return;

   const string full = __ScanPrefix() + name;

   if(ObjectFind(0, full) != -1)
      ObjectDelete(0, full);

   if(!ObjectCreate(0, full, OBJ_TEXT, 0, t, price))
   {
      Print(__FUNCTION__,": ObjectCreate failed for ", full);
      return;
   }

   ObjectSetString (0, full, OBJPROP_TEXT,      text);
   ObjectSetInteger(0, full, OBJPROP_COLOR,     col);
   ObjectSetInteger(0, full, OBJPROP_FONTSIZE,  8);
   ObjectSetInteger(0, full, OBJPROP_ANCHOR,    ANCHOR_CENTER);
   ObjectSetInteger(0, full, OBJPROP_BACK,      false);
   ObjectSetInteger(0, full, OBJPROP_SELECTABLE,false);
}

void ClearIfExists(const string name)
{
   const string full = __ScanPrefix() + name;
   if(ObjectFind(0, full) != -1) ObjectDelete(0, full);
}

void W2_ClearTag(const string tag)
{
   if(!InpDrawMarkers) return;
   ClearIfExists("W2_" + tag + "_C1");
   ClearIfExists("W2_" + tag + "_C2");
   ClearIfExists("W2_" + tag + "_C3");
   ClearIfExists("W2_" + tag + "_C4");
}

// پاک‌سازی همه‌ی مارکرهای موج در همین اسکن (W2/W3/HW/HWBB/SW) –
// مارکرهای Shadow Breaker/temp/invalidator حذف نمی‌شوند.
inline void Markers_Clear_Waves_CurrentScan()
{
   const string p   = __ScanPrefix();
   const int    plen= StringLen(p);

   for(int i=ObjectsTotal(0)-1; i>=0; --i)
   {
      string on = ObjectName(0,i);
      if(on=="" || StringLen(on)<plen) continue;
      if(StringSubstr(on,0,plen)!=p)   continue;

      string tail = StringSubstr(on, plen);
      bool isWave =
         (StringFind(tail,"W2_")   == 0) ||
         (StringFind(tail,"W3_")   == 0) ||
         (StringFind(tail,"HW_")   == 0) ||
         (StringFind(tail,"HWBB_") == 0) ||
         (StringFind(tail,"SW_")   == 0);

      if(isWave) ObjectDelete(0,on);
   }
}

// ============================================================================
// M15 "new" marker + Stage-1 eligibility gate + final NEW-zone display
// ----------------------------------------------------------------------------
// Purpose:
//   On M15 only, when the first same-direction FSMS/HWX/HWBB event happens
//   immediately after a normal MTC, draw a small "new" text on that event candle
//   and return TRUE so the M15->M1 Stage-1 START may be published.
//
//   Additionally, after the confirmed "new" candle, a dynamic NEW zone is tracked:
//     UP   : top    = highest High between NORMAL MTC and NEW candle (inclusive)
//            bottom = lowest Low after the NEW candle until finalization
//            final display = lower two thirds of the zone, green
//     DOWN : bottom = lowest Low between NORMAL MTC and NEW candle (inclusive)
//            top    = highest High after the NEW candle until finalization
//            final display = upper two thirds of the zone, red
//
//   The dynamic zone is finalized and drawn only when price breaks the fixed
//   top/bottom boundary, or when any new MTC event appears.
// Important:
//   This module is visual/gating only. It does not change how FSMS/HWX/HWBB,
//   MTC, M15->M1 bridge events, M1 triggers/trades or Statement logic work.
// ============================================================================
#define WB_M15NEW_TARGET_FSMS 1
#define WB_M15NEW_TARGET_HWX  2
#define WB_M15NEW_TARGET_HWBB 3

static bool      g_m15new_pending       = false;
static Direction g_m15new_dir           = DIR_UP;
static datetime  g_m15new_mtc_time      = 0;
static int       g_m15new_mtc_index     = -1;
static bool      g_m15new_consumed      = false;
static int       g_m15new_mark_counter  = 0;

static bool      g_m15new_zone_active      = false;
static Direction g_m15new_zone_dir         = DIR_UP;
static datetime  g_m15new_zone_start_time  = 0;
static datetime  g_m15new_zone_last_time   = 0;
static double    g_m15new_zone_top         = 0.0;
static double    g_m15new_zone_bottom      = 0.0;
static int       g_m15new_zone_id          = 0;
static int       g_m15new_zone_counter     = 0;

inline bool M15NewMarker_ShouldRun()
{
   if((ENUM_TIMEFRAMES)Period() != PERIOD_M15)
      return false;

   const string ns = Markers_GetNamespace();
   if(ns != "" && ns != "MAJ")
      return false;

   return true;
}

inline double __M15NewZone_Eps()
{
   double eps = _Point * 2.0;
   if(eps <= 0.0)
      eps = 0.00000001;
   return eps;
}

inline void M15NewZone_ClearActive()
{
   g_m15new_zone_active     = false;
   g_m15new_zone_dir        = DIR_UP;
   g_m15new_zone_start_time = 0;
   g_m15new_zone_last_time  = 0;
   g_m15new_zone_top        = 0.0;
   g_m15new_zone_bottom     = 0.0;
   g_m15new_zone_id         = 0;
}

inline int M15NewZone_CurrentId()
{
   if(!g_m15new_zone_active)
      return 0;

   return g_m15new_zone_id;
}

inline bool M15NewZone_CurrentDisplayBounds(const Direction dir,
                                            double &out_bottom,
                                            double &out_top)
{
   out_bottom = 0.0;
   out_top    = 0.0;

   if(!M15NewMarker_ShouldRun())
      return false;

   if(!g_m15new_zone_active)
      return false;

   if(dir != g_m15new_zone_dir)
      return false;

   double top    = g_m15new_zone_top;
   double bottom = g_m15new_zone_bottom;

   if(top < bottom)
   {
      double tmp = top;
      top = bottom;
      bottom = tmp;
   }

   const double height = (top - bottom);
   if(height <= __M15NewZone_Eps())
      return false;

   if(dir == DIR_UP)
   {
      // Same visual zone that is drawn for bullish NEW: lower two thirds.
      out_bottom = bottom;
      out_top    = bottom + (height * 2.0 / 3.0);
   }
   else
   {
      // Same visual zone that is drawn for bearish NEW: upper two thirds.
      out_top    = top;
      out_bottom = top - (height * 2.0 / 3.0);
   }

   if(out_top < out_bottom)
   {
      double tmp2 = out_top;
      out_top = out_bottom;
      out_bottom = tmp2;
   }

   return (out_top > out_bottom + __M15NewZone_Eps());
}

inline bool __M15NewZone_DrawRect(const string base,
                                  const datetime t1,
                                  const double price_a,
                                  const datetime t2,
                                  const double price_b,
                                  const color col,
                                  const int alpha)
{
   if(!Markers_ShouldRender())
      return false;

   datetime a = t1;
   datetime b = t2;
   if(a <= 0 || b <= 0)
      return false;

   if(b <= a)
      b = (datetime)(a + (datetime)PeriodSeconds(PERIOD_M15));

   double p_top = MathMax(price_a, price_b);
   double p_bot = MathMin(price_a, price_b);
   if(p_top <= p_bot + __M15NewZone_Eps())
      return false;

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
         Print("[M15NewZone] ObjectCreate failed for ", full);
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

inline void M15NewZone_Finalize(const datetime end_time,
                                const string reason)
{
   if(!M15NewMarker_ShouldRun())
      return;

   if(!g_m15new_zone_active)
      return;

   if(end_time <= 0)
      return;

   double top = g_m15new_zone_top;
   double bottom = g_m15new_zone_bottom;
   if(top < bottom)
   {
      double tmp = top;
      top = bottom;
      bottom = tmp;
   }

   double height = top - bottom;
   if(height <= __M15NewZone_Eps())
   {
      M15NewZone_ClearActive();
      return;
   }

   double rect_top = top;
   double rect_bottom = bottom;
   color rect_col = clrGreen;

   if(g_m15new_zone_dir == DIR_UP)
   {
      // Bullish NEW zone: show the lower two thirds.
      rect_bottom = bottom;
      rect_top    = bottom + (height * 2.0 / 3.0);
      rect_col    = clrGreen;
   }
   else
   {
      // Bearish NEW zone: show the upper two thirds.
      rect_top    = top;
      rect_bottom = top - (height * 2.0 / 3.0);
      rect_col    = clrRed;
   }

   ++g_m15new_zone_counter;

   string name = "M15_NEW_ZONE_" +
                 (g_m15new_zone_dir == DIR_UP ? "U_" : "D_") +
                 IntegerToString(g_m15new_zone_id) + "_" +
                 IntegerToString(g_m15new_zone_counter) + "_" +
                 reason + "_" +
                 IntegerToString((long)g_m15new_zone_start_time);

   __M15NewZone_DrawRect(name,
                         g_m15new_zone_start_time,
                         rect_top,
                         end_time,
                         rect_bottom,
                         rect_col,
                         55);

   M15NewZone_ClearActive();
}

inline bool __M15NewZone_FindIndexByTime(const MqlRates &rates[],
                                         const int n,
                                         const datetime t,
                                         int &out_idx)
{
   out_idx = -1;
   if(t <= 0 || n <= 0)
      return false;

   for(int i = 0; i < n; ++i)
   {
      if(rates[i].time == t)
      {
         out_idx = i;
         return true;
      }
   }

   return false;
}

inline void M15NewZone_StartFromTarget(const Direction dir,
                                       const MqlRates &rates[],
                                       const int n,
                                       const int mtc_idx_raw,
                                       const datetime mtc_time,
                                       const int new_idx)
{
   if(!M15NewMarker_ShouldRun())
      return;

   if(n <= 0 || new_idx < 0 || new_idx >= n)
      return;

   int mtc_idx = mtc_idx_raw;
   if(mtc_idx < 0 || mtc_idx >= n || rates[mtc_idx].time != mtc_time)
   {
      int found_idx = -1;
      if(!__M15NewZone_FindIndexByTime(rates, n, mtc_time, found_idx))
         return;
      mtc_idx = found_idx;
   }

   int from = MathMin(mtc_idx, new_idx);
   int to   = MathMax(mtc_idx, new_idx);

   double range_high = -DBL_MAX;
   double range_low  =  DBL_MAX;

   for(int k = from; k <= to; ++k)
   {
      if(rates[k].high > range_high)
         range_high = rates[k].high;
      if(rates[k].low < range_low)
         range_low = rates[k].low;
   }

   if(range_high <= -DBL_MAX / 2.0 || range_low >= DBL_MAX / 2.0)
      return;

   g_m15new_zone_active     = true;
   g_m15new_zone_dir        = dir;
   g_m15new_zone_start_time = rates[new_idx].time;
   g_m15new_zone_last_time  = rates[new_idx].time;
   g_m15new_zone_id         = g_m15new_mark_counter;

   if(dir == DIR_UP)
   {
      g_m15new_zone_top    = range_high;
      g_m15new_zone_bottom = rates[new_idx].low;
   }
   else
   {
      g_m15new_zone_bottom = range_low;
      g_m15new_zone_top    = rates[new_idx].high;
   }

   if(g_m15new_zone_top <= g_m15new_zone_bottom + __M15NewZone_Eps())
      M15NewZone_ClearActive();
}

inline void M15NewZone_OnBar(const MqlRates &rates[],
                             const int n,
                             const int idx)
{
   if(!M15NewMarker_ShouldRun())
      return;

   if(!g_m15new_zone_active)
      return;

   if(idx < 0 || idx >= n)
      return;

   const datetime t = rates[idx].time;
   if(t <= g_m15new_zone_start_time)
      return;

   // Historical scans can rewind after invalidations. Do not let an older bar
   // shrink/expand an already-progressed dynamic NEW zone.
   if(g_m15new_zone_last_time > 0 && t <= g_m15new_zone_last_time)
      return;

   if(g_m15new_zone_dir == DIR_UP)
   {
      if(rates[idx].low < g_m15new_zone_bottom)
         g_m15new_zone_bottom = rates[idx].low;

      g_m15new_zone_last_time = t;

      // Bullish finalization: fixed top is broken by wick/body.
      if(rates[idx].high > g_m15new_zone_top || rates[idx].close > g_m15new_zone_top)
         M15NewZone_Finalize(t, "BREAK_TOP");
   }
   else
   {
      if(rates[idx].high > g_m15new_zone_top)
         g_m15new_zone_top = rates[idx].high;

      g_m15new_zone_last_time = t;

      // Bearish finalization: fixed bottom is broken by wick/body.
      if(rates[idx].low < g_m15new_zone_bottom || rates[idx].close < g_m15new_zone_bottom)
         M15NewZone_Finalize(t, "BREAK_BOTTOM");
   }
}

inline void M15NewZone_OnMTCEvent(const datetime t)
{
   if(!M15NewMarker_ShouldRun())
      return;

   if(!g_m15new_zone_active)
      return;

   if(t <= g_m15new_zone_start_time)
      return;

   M15NewZone_Finalize(t, "NEW_MTC");
}

inline void M15NewMarker_ClearPending()
{
   g_m15new_pending   = false;
   g_m15new_dir       = DIR_UP;
   g_m15new_mtc_time  = 0;
   g_m15new_mtc_index = -1;
   g_m15new_consumed  = false;
}

inline void M15NewMarker_ResetGlobals()
{
   M15NewMarker_ClearPending();
   M15NewZone_ClearActive();
   g_m15new_mark_counter = 0;
   g_m15new_zone_counter = 0;
}

inline string M15NewMarker_TargetName(const int target_kind)
{
   if(target_kind == WB_M15NEW_TARGET_FSMS) return "FSMS";
   if(target_kind == WB_M15NEW_TARGET_HWX)  return "HWX";
   if(target_kind == WB_M15NEW_TARGET_HWBB) return "HWBB";
   return "UNKNOWN";
}

inline void M15NewMarker_OnMTC(const Direction dir,
                               const datetime t,
                               const int idx,
                               const bool is_normal_mtc)
{
   if(!M15NewMarker_ShouldRun())
      return;

   if(t <= 0)
   {
      M15NewMarker_ClearPending();
      return;
   }

   // Any new MTC event finalizes the currently tracked NEW zone first.
   M15NewZone_OnMTCEvent(t);

   // Only NORMAL MTC arms the one-shot "new" relationship.
   // Special MTC explicitly breaks any pending normal-MTC relationship.
   if(!is_normal_mtc)
   {
      if(g_m15new_pending && t >= g_m15new_mtc_time)
         M15NewMarker_ClearPending();
      return;
   }

   g_m15new_pending   = true;
   g_m15new_dir       = dir;
   g_m15new_mtc_time  = t;
   g_m15new_mtc_index = idx;
   g_m15new_consumed  = false;
}

inline void M15NewMarker_OnNewWavePair(const Direction dir,
                                        const datetime t)
{
   if(!M15NewMarker_ShouldRun())
      return;

   if(!g_m15new_pending)
      return;

   if(t <= 0)
      return;

   // The "new" tag must happen after the normal MTC and BEFORE the next
   // completed W2/W3 pair. Once a new pair forms, the old MTC can no longer
   // tag any later FSMS/HWX/HWBB candle. Active NEW zones are NOT finalized
   // by wave pairs; only price break or a new MTC finalizes them.
   if(t > g_m15new_mtc_time)
      M15NewMarker_ClearPending();
}

inline bool M15NewMarker_OnTarget(const Direction dir,
                                   const int target_kind,
                                   const MqlRates &rates[],
                                   const int n,
                                   const int idx)
{
   if(!M15NewMarker_ShouldRun())
      return false;

   if(idx < 0 || idx >= n)
      return false;

   if(target_kind != WB_M15NEW_TARGET_FSMS &&
      target_kind != WB_M15NEW_TARGET_HWX  &&
      target_kind != WB_M15NEW_TARGET_HWBB)
      return false;

   const datetime t = rates[idx].time;
   if(t <= 0)
      return false;

   if(!g_m15new_pending || g_m15new_consumed)
      return false;

   // Only events AFTER the normal MTC are considered. Same-candle or older
   // events are ignored so existing marker order and signal timing remain intact.
   if(t <= g_m15new_mtc_time)
      return false;

   // The first FSMS/HWX/HWBB event after the normal MTC decides this one-shot
   // relationship. If it is opposite-direction, the relationship is broken.
   if(dir != g_m15new_dir)
   {
      M15NewMarker_ClearPending();
      return false;
   }

   ++g_m15new_mark_counter;

   double span = rates[idx].high - rates[idx].low;
   if(span <= 0.0)
      span = 10.0 * _Point;

   double pad = span * 0.35;
   if(pad < 5.0 * _Point)
      pad = 5.0 * _Point;

   double y = (dir == DIR_UP ? rates[idx].high + pad : rates[idx].low - pad);

   string name = "M15_NEW_AFTER_MTC_" +
                 (dir == DIR_UP ? "U_" : "D_") +
                 M15NewMarker_TargetName(target_kind) + "_" +
                 IntegerToString(g_m15new_mark_counter) + "_" +
                 IntegerToString((long)t);

   MarkCandleText(name, t, y, "new", clrGold);

   // The confirmed NEW candle starts the dynamic visual zone. The zone remains
   // dynamic until price breaks its fixed boundary or a new MTC event appears.
   M15NewZone_StartFromTarget(dir,
                              rates,
                              n,
                              g_m15new_mtc_index,
                              g_m15new_mtc_time,
                              idx);

   // One NORMAL MTC is allowed to tag exactly one target candle only.
   g_m15new_consumed = true;
   M15NewMarker_ClearPending();

   return true;
}




#endif // WAVEBOT_MARKERS_MQH
