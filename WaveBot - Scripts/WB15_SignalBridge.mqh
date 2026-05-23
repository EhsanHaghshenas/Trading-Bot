// ============================================================================
#ifndef WAVEBOT_WB15_SIGNAL_BRIDGE_MQH
#define WAVEBOT_WB15_SIGNAL_BRIDGE_MQH

// ============================================================================
// WB15_SignalBridge.mqh
// Simple live bridge M15 -> M1 using Terminal Global Variables.
// M15 publishes START/STOP signals; M1 draws ON/OFF markers as an overlay.
// ============================================================================

// NOTE: This module is intentionally standalone and now publishes the M15->M1
// START directly from the confirmed Stage-1 "new" seed.  The legacy Stage-2/
// Stage-3 Flip/MajicFlip helpers are kept below for compatibility, but they no
// longer gate M1 activation.
#include <WaveBot/WaveBotLogger.mqh>

// ---- Signal namespace (world) ----
enum WB15_NS
{
   WB15_NS_NONE = 0,
   WB15_NS_MAJ  = 1,
   WB15_NS_MIN  = 2
};

// ---- Signal kind ----
enum WB15_KIND
{
   WB15_KIND_START_HWX          = 1,
   WB15_KIND_START_HWBB         = 2,
   WB15_KIND_START_FSMS         = 3,
   WB15_KIND_START_GOOZBAGHALI  = 4,

   WB15_KIND_STOP_MTC              = 10,
   WB15_KIND_STOP_MINORSTARTER     = 11,
   WB15_KIND_STOP_MINOROFF_ZONE    = 12,
   WB15_KIND_STOP_ZONE_INVALIDATED = 13
};

// ---- Internal state (M1) ----
struct WB15ActiveState
{
   bool      active;
   int       start_kind;
   int       start_ns;
   Direction start_dir;
   datetime  start_time;
   int       start_evt_seq;
   double    run_id;

   // Legacy counting fields are kept only for compatibility.
   // Candle numbering is enabled on the M1 chart.
   datetime  start_bar_time;
   datetime  last_count_bar_time;
   int       count;
};

static int             g_wb15_processed_seq = 0;
static double          g_wb15_run_seen      = 0.0;
static WB15ActiveState g_wb15_state;



// ============================================================================
// Helpers (GV naming / packing)
// ============================================================================

inline string __WB15_SanitizeSymbol(const string sym)
{
   string s = sym;
   StringReplace(s, ".", "_");
   StringReplace(s, "#", "_");
   StringReplace(s, "/", "_");
   StringReplace(s, "\\", "_");
   StringReplace(s, ":", "_");
   return s;
}

inline string __WB15_Base(const string sym)
{
   return "WB15SIG_" + __WB15_SanitizeSymbol(sym);
}

inline string __WB15_Key(const string sym, const string suffix)
{
   return __WB15_Base(sym) + "_" + suffix;
}

inline string __WB15_KeyT(const string sym, const int seq)
{
   return __WB15_Key(sym, "T_" + IntegerToString(seq));
}

inline string __WB15_KeyC(const string sym, const int seq)
{
   return __WB15_Key(sym, "C_" + IntegerToString(seq));
}

inline bool __WB15_IsMaster()
{
   return ((ENUM_TIMEFRAMES)Period() == PERIOD_M15);
}

inline bool __WB15_IsSlave()
{
   return ((ENUM_TIMEFRAMES)Period() == PERIOD_M1);
}

inline int __WB15_NS_FromMarkers()
{
   // Markers_GetNamespace() is defined in Markers.mqh (included before this module).
   string ns = Markers_GetNamespace();
   if(ns == "MAJ") return WB15_NS_MAJ;
   if(ns == "MIN") return WB15_NS_MIN;
   return WB15_NS_NONE;
}

inline int __WB15_DirCode(const Direction d)
{
   return (d == DIR_UP ? 1 : 2);
}

inline Direction __WB15_CodeDir(const int dc)
{
   return (dc == 1 ? DIR_UP : DIR_DOWN);
}

inline Direction __WB15_Opposite(const Direction d)
{
   return (d == DIR_UP ? DIR_DOWN : DIR_UP);
}
// ============================================================================
// SLAVE (M1): display helpers (signal type text)
// ============================================================================

inline string __WB15_NSLabel(const int ns)
{
   if(ns == WB15_NS_MAJ) return "Maj";
   if(ns == WB15_NS_MIN) return "Min";
   return "NA";
}

inline string __WB15_StartKindLabel(const int kind)
{
   if(kind == WB15_KIND_START_HWX)         return "Hwx";
   if(kind == WB15_KIND_START_HWBB)        return "Hwbb";
   if(kind == WB15_KIND_START_FSMS)        return "FSMS";
   if(kind == WB15_KIND_START_GOOZBAGHALI) return "Goozbaghali";
   return "Unknown";
}

inline string __WB15_DirLabel(const Direction dir)
{
   return (dir == DIR_UP ? "U" : "D");
}

inline string __WB15_StartTypeText(const int kind, const int ns, const Direction dir)
{
   return (__WB15_NSLabel(ns) + " " + __WB15_StartKindLabel(kind) + " " + __WB15_DirLabel(dir));
}

// ============================================================================
// MASTER (M15): direct Stage-1 publication to M1
// Stage-1: confirmed M15 "new" seed (FSMS / HWX / HWBB only)
// Result : publish the actual START event to M1 immediately at the mapped
//          Stage-1 event time.
// Legacy Stage-2/Stage-3 Flip/MajicFlip helpers remain in this file but are no
// longer reached because Stage-1 sets on_sent=true as soon as it is armed.
// ============================================================================

struct WB15StageState
{
   bool      active;          // Stage-1 is active
   bool      zone_active;     // Stage-2 is active
   bool      on_sent;         // direct Stage-1 START already published to M1

   int       start_kind;
   int       start_ns;
   Direction start_dir;
   datetime  start_time;      // real M1-mapped Stage-1 event time
   datetime  start_bar_time;  // M15 candle open time that produced Stage-1

   int       zone_source;     // 1=Flip, 2=MajicFlip
   int       zone_kind;       // Flip kind or 0 for MajicFlip
   datetime  zone_anchor_time;
   datetime  zone_flip_time;
   double    zone_top;
   double    zone_bottom;
   double    invalid_level;   // UP: below Flip/MajicFlip low | DOWN: above Flip/MajicFlip high

   // Diagnostic-only lineage IDs (do not affect bridge/trading logic).
   int       log_context_id;
   int       log_zone_id;
};

static WB15StageState g_wb15_stage_maj;
static WB15StageState g_wb15_stage_min;

// Fast event cache for FSMS-SW. FSMS-SW used to scan all chart objects on
// every candle to discover whether a later HWX/HWBB had invalidated the seed.
// Updating this timestamp at the actual Stage-1 source event makes that check
// O(1) and avoids the visible FSMS stalls.
static datetime g_wb15_last_hwx_hwbb_stage_time = 0;

inline datetime WB15_LastHWXHWBBStageTime()
{
   return g_wb15_last_hwx_hwbb_stage_time;
}

inline void __WB15_StageReset(WB15StageState &st)
{
   st.active           = false;
   st.zone_active      = false;
   st.on_sent          = false;
   st.start_kind       = 0;
   st.start_ns         = WB15_NS_NONE;
   st.start_dir        = DIR_UP;
   st.start_time       = 0;
   st.start_bar_time   = 0;
   st.zone_source      = 0;
   st.zone_kind        = 0;
   st.zone_anchor_time = 0;
   st.zone_flip_time   = 0;
   st.zone_top         = 0.0;
   st.zone_bottom      = 0.0;
   st.invalid_level    = 0.0;
   st.log_context_id   = 0;
   st.log_zone_id      = 0;
}

inline void __WB15_StageResetAll()
{
   __WB15_StageReset(g_wb15_stage_maj);
   __WB15_StageReset(g_wb15_stage_min);
   g_wb15_last_hwx_hwbb_stage_time = 0;
}



// ============================================================================
// MASTER: lifecycle + push events
// ============================================================================

inline void WB15_MasterBegin(const string sym)
{
   if(!__WB15_IsMaster()) return;

   const string base = __WB15_Base(sym);

   // Clear old variables for this symbol to prevent mixing runs
   const int total = GlobalVariablesTotal();
   for(int i = total - 1; i >= 0; --i)
   {
      const string name = GlobalVariableName(i);
      if(StringFind(name, base + "_") == 0)
         GlobalVariableDel(name);
   }

   // New run id (seconds)
   const double run_id = (double)TimeCurrent();
   GlobalVariableSet(__WB15_Key(sym, "RUN"), run_id);
   GlobalVariableSet(__WB15_Key(sym, "SEQ"), 0.0);
   GlobalVariableSet(__WB15_Key(sym, "DONE"), 0.0);
   GlobalVariableSet(__WB15_Key(sym, "DONE_SEQ"), 0.0);
   GlobalVariableSet(__WB15_Key(sym, "SCAN_END"), 0.0);

   __WB15_StageResetAll();
}

inline void WB15_MasterEnd(const string sym, const datetime scan_end_time)
{
   if(!__WB15_IsMaster()) return;

   datetime use_end = scan_end_time;
   if(use_end <= 0)
      use_end = TimeCurrent();

   int seq = 0;
   const string kSeq = __WB15_Key(sym, "SEQ");
   if(GlobalVariableCheck(kSeq))
      seq = (int)GlobalVariableGet(kSeq);

   GlobalVariableSet(__WB15_Key(sym, "SCAN_END"), (double)use_end);
   GlobalVariableSet(__WB15_Key(sym, "DONE_SEQ"), (double)seq);
   GlobalVariableSet(__WB15_Key(sym, "DONE"), 1.0);
}

inline bool WB15_MasterDoneInfo(const string sym, datetime &scan_end_time, int &done_seq)
{
   scan_end_time = 0;
   done_seq = 0;

   const string kDone = __WB15_Key(sym, "DONE");
   if(!GlobalVariableCheck(kDone))
      return false;

   if(GlobalVariableGet(kDone) < 0.5)
      return false;

   const string kEnd = __WB15_Key(sym, "SCAN_END");
   if(GlobalVariableCheck(kEnd))
      scan_end_time = (datetime)GlobalVariableGet(kEnd);

   const string kDoneSeq = __WB15_Key(sym, "DONE_SEQ");
   if(GlobalVariableCheck(kDoneSeq))
      done_seq = (int)GlobalVariableGet(kDoneSeq);
   else
   {
      const string kSeq2 = __WB15_Key(sym, "SEQ");
      if(GlobalVariableCheck(kSeq2))
         done_seq = (int)GlobalVariableGet(kSeq2);
   }

   if(scan_end_time <= 0)
      scan_end_time = TimeCurrent();

   return true;
}

inline void WB15_MasterPushEvent(const string sym,
                                const int kind,
                                const int ns,
                                const Direction dir,
                                const datetime t,
                                const int m15_context_id = 0,
                                const int m15_zone_id = 0,
                                const int m1_window_id = 0,
                                const int zone_source = 0,
                                const int zone_kind = 0,
                                const double zone_low = 0.0,
                                const double zone_high = 0.0,
                                const string stop_reason = "")
{
   if(!__WB15_IsMaster()) return;
   if(t <= 0) return;

   // MIN world is executed by WorldManager in preview mode.
   // We still must publish bridge events there, otherwise M1 never sees
   // MIN-origin M15 signal on/off windows in real time.
   if(Markers_IsPreviewMode() && ns != WB15_NS_MIN)
      return;

   const string kDed = __WB15_Key(sym, "DED_"
                                       + IntegerToString(kind) + "_"
                                       + IntegerToString(ns) + "_"
                                       + IntegerToString(__WB15_DirCode(dir)) + "_"
                                       + IntegerToString((int)t));
   if(GlobalVariableCheck(kDed))
      return;
   GlobalVariableSet(kDed, 1.0);

   const string kSeq = __WB15_Key(sym, "SEQ");
   int seq = 0;
   if(GlobalVariableCheck(kSeq))
      seq = (int)GlobalVariableGet(kSeq);
   seq++;
   GlobalVariableSet(kSeq, (double)seq);

   const int code = kind * 100 + ns * 10 + __WB15_DirCode(dir);
   GlobalVariableSet(__WB15_KeyT(sym, seq), (double)t);
   GlobalVariableSet(__WB15_KeyC(sym, seq), (double)code);

   int effective_window_id = m1_window_id;
   if(effective_window_id <= 0)
      effective_window_id = seq;

   GlobalVariableSet(__WB15_Key(sym, "CTX_" + IntegerToString(seq)), (double)m15_context_id);
   GlobalVariableSet(__WB15_Key(sym, "ZONE_" + IntegerToString(seq)), (double)m15_zone_id);
   GlobalVariableSet(__WB15_Key(sym, "WIN_" + IntegerToString(seq)), (double)effective_window_id);
   GlobalVariableSet(__WB15_Key(sym, "ZL_" + IntegerToString(seq)), zone_low);
   GlobalVariableSet(__WB15_Key(sym, "ZH_" + IntegerToString(seq)), zone_high);

   string event_type = (kind < 10 ? "START" : "STOP");
   WBLOG_M15BridgeEvent(m15_context_id, m15_zone_id, effective_window_id, event_type, dir, t, t, kind, zone_source, zone_kind, zone_low, zone_high, (kind >= 10 ? t : 0), stop_reason, ns, seq);
}

// Convenience wrappers (called from signal detection points)

// --------------------------------------------------------------------------
// Time-mapping rule (M15 -> M1):
//  - HWX / HWBB / GOOZBAGHALI:
//      publish on the FIRST M1 candle inside the M15 bar where the event
//      really forms. The published timestamp is a stable point INSIDE that
//      M1 candle (bar_open + 1 second), so the slave resolves the same
//      live candle deterministically.
//  - FSMS / MTC / MinorStarter / MinorOff-zone:
//      publish ONLY after the M15 candle closes,
//      and their timestamp is the M15 CLOSE time (open time of next M15 bar).
// --------------------------------------------------------------------------

inline datetime __WB15_H4_CloseTime(const datetime h4_open_time)
{
   if(h4_open_time <= 0) return 0;

   // legacy helper name kept; close time now belongs to the M15 master bar
   int sec = PeriodSeconds(PERIOD_M15);
   if(sec <= 0) sec = 900; // safety fallback: 15M = 900 seconds

   return (h4_open_time + (datetime)sec);
}

inline datetime __WB15_CloseBasedEventTimeOrZero(const datetime h4_open_time)
{
   const datetime close_time = __WB15_H4_CloseTime(h4_open_time);
   if(close_time <= 0) return 0;

   // Wait for candle close (prevents early display on M1)
   if(TimeCurrent() < close_time) return 0;

   return close_time;
}

inline datetime __WB15_StableM15IntrabarTime(const datetime m15_bar_open_time)
{
   if(m15_bar_open_time <= 0) return 0;

   int sec = PeriodSeconds(PERIOD_M1);
   if(sec <= 0) sec = 60; // safety fallback: 1M = 60 seconds

   datetime t = m15_bar_open_time + 1;
   if(t >= (m15_bar_open_time + (datetime)sec))
      t = m15_bar_open_time;

   return t;
}

inline bool __WB15_BuildIntrabarSearchWindow(const datetime h4_open_time,
                                             datetime &from_time,
                                             datetime &to_time)
{
   from_time = 0;
   to_time   = 0;

   if(h4_open_time <= 0) return false;

   const datetime close_time = __WB15_H4_CloseTime(h4_open_time);
   if(close_time <= h4_open_time) return false;

   from_time = h4_open_time;
   to_time   = close_time - 1;

   const datetime now = TimeCurrent();
   if(now < to_time)
      to_time = now;

   if(to_time < from_time)
      to_time = from_time;

   return true;
}

inline int __WB15_LoadIntrabarM15(const string sym,
                                  const datetime from_time,
                                  const datetime to_time,
                                  MqlRates &bars[])
{
   ArrayFree(bars);

   if(from_time <= 0) return 0;
   if(to_time < from_time) return 0;

   int copied = CopyRates(sym, PERIOD_M1, from_time, to_time, bars);
   if(copied <= 0) return 0;

   ArraySetAsSeries(bars, false);
   return copied;
}

inline bool __WB15_FindFirstHWXIntrabarTime(const string sym,
                                            const Direction dir,
                                            const datetime h4_open_time,
                                            const double level,
                                            datetime &event_time)
{
   event_time = 0;
   if(level <= 0.0) return false;

   datetime from_time = 0;
   datetime to_time   = 0;
   if(!__WB15_BuildIntrabarSearchWindow(h4_open_time, from_time, to_time))
      return false;

   MqlRates bars[];
   int n = __WB15_LoadIntrabarM15(sym, from_time, to_time, bars);
   if(n <= 0) return false;

   for(int i = 0; i < n; ++i)
   {
      bool crossed = false;

      if(dir == DIR_UP)
         crossed = (bars[i].low <= level || bars[i].close < level);
      else
         crossed = (bars[i].high >= level || bars[i].close > level);

      if(crossed)
      {
         event_time = __WB15_StableM15IntrabarTime(bars[i].time);
         return (event_time > 0);
      }
   }

   return false;
}

inline bool __WB15_FindFirstHWBBIntrabarTime(const string sym,
                                             const Direction dir,
                                             const datetime h4_open_time,
                                             const double start_level,
                                             const datetime seed_h4_open_time,
                                             datetime &event_time)
{
   event_time = 0;
   if(start_level <= 0.0) return false;

   datetime min_event_time = h4_open_time;

   // If HWBB happens inside the very same M15 bar as the seed Hunter,
   // do not allow a time earlier than the real HWX formation moment.
   if(seed_h4_open_time > 0 && seed_h4_open_time == h4_open_time)
   {
      datetime hwx_time = 0;
      if(__WB15_FindFirstHWXIntrabarTime(sym, dir, seed_h4_open_time, start_level, hwx_time))
      {
         if(hwx_time > min_event_time)
            min_event_time = hwx_time;
      }
   }

   datetime from_time = 0;
   datetime to_time   = 0;
   if(!__WB15_BuildIntrabarSearchWindow(h4_open_time, from_time, to_time))
      return false;

   MqlRates bars[];
   int n = __WB15_LoadIntrabarM15(sym, from_time, to_time, bars);
   if(n <= 0) return false;

   double level = start_level;

   for(int i = 0; i < n; ++i)
   {
      const datetime bar_event_time = __WB15_StableM15IntrabarTime(bars[i].time);
      if(bar_event_time <= 0) continue;
      if(bar_event_time < min_event_time) continue;

      if(dir == DIR_UP)
      {
         if(bars[i].close < level)
         {
            event_time = bar_event_time;
            return true;
         }

         if(bars[i].low < level)
            level = bars[i].low;
      }
      else
      {
         if(bars[i].close > level)
         {
            event_time = bar_event_time;
            return true;
         }

         if(bars[i].high > level)
            level = bars[i].high;
      }
   }

   return false;
}

inline bool __WB15_FindFirstRangeTouchIntrabarTime(const string sym,
                                                   const datetime h4_open_time,
                                                   const double price_a,
                                                   const double price_b,
                                                   datetime &event_time)
{
   event_time = 0;

   double bottom = price_a;
   double top    = price_b;

   if(bottom > top)
   {
      double tmp = bottom;
      bottom     = top;
      top        = tmp;
   }

   if(top <= 0.0) return false;

   datetime from_time = 0;
   datetime to_time   = 0;
   if(!__WB15_BuildIntrabarSearchWindow(h4_open_time, from_time, to_time))
      return false;

   MqlRates bars[];
   int n = __WB15_LoadIntrabarM15(sym, from_time, to_time, bars);
   if(n <= 0) return false;

   const double eps = (2.0 * _Point);

   for(int i = 0; i < n; ++i)
   {
      if(bars[i].low <= (top + eps) && bars[i].high >= (bottom - eps))
      {
         event_time = __WB15_StableM15IntrabarTime(bars[i].time);
         return (event_time > 0);
      }
   }

   return false;
}

inline string __WB15_StageSourceLabel(const int source, const int kind)
{
   if(source == 1)
      return "Flip T" + IntegerToString(kind);
   if(source == 2)
      return "MajicFlip";
   return "NA";
}

inline datetime __WB15_M15CloseTime(const datetime m15_open_time)
{
   if(m15_open_time <= 0) return 0;
   int sec = PeriodSeconds(PERIOD_M15);
   if(sec <= 0) sec = 900;
   return (m15_open_time + (datetime)sec);
}

inline bool __WB15_IsClosedM15Bar(const MqlRates &bar)
{
   const datetime close_time = __WB15_M15CloseTime(bar.time);
   if(close_time <= 0) return false;
   return (TimeCurrent() >= close_time);
}

inline bool __WB15_StageIsBull(const MqlRates &r)
{
   return (r.close > r.open);
}

inline bool __WB15_StageIsBear(const MqlRates &r)
{
   return (r.close < r.open);
}

inline bool __WB15_StageInsideMotherHL(const MqlRates &mother, const MqlRates &r)
{
   return (r.high <= mother.high && r.low >= mother.low);
}

inline double __WB15_StageEps()
{
   double eps = 2.0 * _Point;
   if(eps <= 0.0) eps = 0.00000001;
   return eps;
}

inline void __WB15_StageNormalizeZone(WB15StageState &st)
{
   if(st.zone_bottom > st.zone_top)
   {
      double tmp = st.zone_bottom;
      st.zone_bottom = st.zone_top;
      st.zone_top = tmp;
   }
}

inline void __WB15_StageClearZone(WB15StageState &st)
{
   st.zone_active      = false;
   st.on_sent          = false;
   st.zone_source      = 0;
   st.zone_kind        = 0;
   st.zone_anchor_time = 0;
   st.zone_flip_time   = 0;
   st.zone_top         = 0.0;
   st.zone_bottom      = 0.0;
   st.invalid_level    = 0.0;
   st.log_zone_id      = 0;
}

inline void __WB15_StagePublishDirectON(const string sym,
                                          WB15StageState &st)
{
   if(!__WB15_IsMaster()) return;
   if(!st.active) return;
   if(st.on_sent) return;
   if(st.start_time <= 0) return;

   // Direct Stage-1 mode:
   // The confirmed M15 "new" seed is the actual M1 activation point.
   // No M15 Flip/MajicFlip zone and no retouch are required anymore.
   // However, the M1 trigger gate must know the exact NEW-zone bounds from
   // the same M15 moment, so the current visual NEW zone is packed with the ON.
   double direct_zone_low  = 0.0;
   double direct_zone_high = 0.0;
   int    direct_zone_id   = 0;

   if(M15NewZone_CurrentDisplayBounds(st.start_dir, direct_zone_low, direct_zone_high))
      direct_zone_id = M15NewZone_CurrentId();

   if(direct_zone_id <= 0)
      direct_zone_id = st.log_zone_id;

   st.log_zone_id = direct_zone_id;

   TriggerM15SignalGate_RecordExact(sym, st.start_kind, st.start_ns, st.start_dir, st.start_time);

   WB15_MasterPushEvent(sym,
                        st.start_kind,
                        st.start_ns,
                        st.start_dir,
                        st.start_time,
                        st.log_context_id,
                        direct_zone_id,
                        0,
                        0,
                        0,
                        direct_zone_low,
                        direct_zone_high,
                        "STAGE1_NEW_DIRECT_ON");

   st.on_sent = true;

   WBLOG_LogM15GateEvent(st.log_context_id,
                         0,
                         "M1_START_SENT",
                         st.start_dir,
                         st.start_time,
                         (int)st.start_time,
                         0.0, 0.0, 0.0, 0.0,
                         0.0, 0.0,
                         "stage1_new_direct_start_published_to_m1");

   WBLOG_LogStateTransition("WB15_SignalBridge",
                            "STAGE_1_NEW_ACTIVE",
                            "M1_ON_SENT_DIRECT",
                            st.start_dir,
                            st.log_context_id,
                            0,
                            0,
                            0,
                            "STAGE1_NEW_DIRECT_ON",
                            st.start_time,
                            PERIOD_M15,
                            (int)st.start_time,
                            0.0, 0.0, 0.0, 0.0);

   if(InpDebugPrints)
      Print("[WB15-STAGE] Stage-1 NEW -> direct M1 ON | kind=", __WB15_StartKindLabel(st.start_kind),
            " | ns=", __WB15_NSLabel(st.start_ns),
            " | dir=", (st.start_dir==DIR_UP ? "UP" : "DOWN"),
            " | t=", TimeToString(st.start_time, TIME_DATE|TIME_SECONDS));
}

inline void __WB15_StageStartState(const string sym,
                                   WB15StageState &st,
                                   const int kind,
                                   const int ns,
                                   const Direction dir,
                                   const datetime event_time,
                                   const datetime stage1_bar_time)
{
   st.active           = true;
   st.zone_active      = false;
   st.on_sent          = false;
   st.start_kind       = kind;
   st.start_ns         = ns;
   st.start_dir        = dir;
   st.start_time       = event_time;
   st.start_bar_time   = stage1_bar_time;
   st.zone_source      = 0;
   st.zone_kind        = 0;
   st.zone_anchor_time = 0;
   st.zone_flip_time   = 0;
   st.zone_top         = 0.0;
   st.zone_bottom      = 0.0;
   st.invalid_level    = 0.0;
   st.log_zone_id      = 0;
   st.log_context_id   = WBLOG_M15MainSignalStart(sym, kind, ns, dir, event_time, stage1_bar_time);

   if(InpDebugPrints)
      Print("[WB15-STAGE] Stage-1 NEW armed | kind=", __WB15_StartKindLabel(kind),
            " | ns=", __WB15_NSLabel(ns),
            " | dir=", (dir==DIR_UP ? "UP" : "DOWN"),
            " | t=", TimeToString(event_time, TIME_DATE|TIME_SECONDS),
            " | bar=", TimeToString(stage1_bar_time, TIME_DATE|TIME_SECONDS));

   __WB15_StagePublishDirectON(sym, st);
}

inline void __WB15_StageStart(const string sym,
                              const int kind,
                              const int ns,
                              const Direction dir,
                              const datetime event_time,
                              const datetime stage1_bar_time)
{
   if(!__WB15_IsMaster()) return;
   if(event_time <= 0) return;
   if(stage1_bar_time <= 0) return;

   // Direct M15->M1 Stage-1 is intentionally restricted to the three
   // "new"-eligible families only. GoozBaghali and any legacy start wrapper
   // must not open an M1 signal window.
   if(kind != WB15_KIND_START_HWX && kind != WB15_KIND_START_HWBB && kind != WB15_KIND_START_FSMS)
      return;

   if((kind == WB15_KIND_START_HWX || kind == WB15_KIND_START_HWBB) && event_time > g_wb15_last_hwx_hwbb_stage_time)
      g_wb15_last_hwx_hwbb_stage_time = event_time;

   if(ns == WB15_NS_MAJ)
      __WB15_StageStartState(sym, g_wb15_stage_maj, kind, ns, dir, event_time, stage1_bar_time);
   else if(ns == WB15_NS_MIN)
      __WB15_StageStartState(sym, g_wb15_stage_min, kind, ns, dir, event_time, stage1_bar_time);
}

inline void __WB15_StageStopState(WB15StageState &st,
                                  const Direction stop_dir,
                                  const datetime stop_time)
{
   if(!st.active) return;
   if(stop_dir != __WB15_Opposite(st.start_dir)) return;

   if(InpDebugPrints)
      Print("[WB15-STAGE] Reset by original OFF | active_kind=", __WB15_StartKindLabel(st.start_kind),
            " | dir=", (st.start_dir==DIR_UP ? "UP" : "DOWN"),
            " | off=", TimeToString(stop_time, TIME_DATE|TIME_SECONDS));

   WBLOG_M15MainSignalOff(st.log_context_id, st.start_dir, stop_time, "ORIGINAL_OFF");
   if(st.on_sent)
      WBLOG_LogM15GateEvent(st.log_context_id, st.log_zone_id, "M1_STOP_SENT", st.start_dir, stop_time, (int)stop_time, 0.0, 0.0, 0.0, 0.0, st.zone_bottom, st.zone_top, "original_off_after_m1_start");

   __WB15_StageReset(st);
}

inline void __WB15_StageStop(const Direction stop_dir, const datetime stop_time)
{
   __WB15_StageStopState(g_wb15_stage_maj, stop_dir, stop_time);
   __WB15_StageStopState(g_wb15_stage_min, stop_dir, stop_time);
}

inline bool __WB15_StageBreakerAfterStart(const WB15StageState &st,
                                          const datetime breaker_open_time)
{
   if(!st.active) return false;
   if(breaker_open_time <= 0) return false;

   const datetime breaker_close_time = __WB15_M15CloseTime(breaker_open_time);
   if(breaker_close_time <= 0) return false;

   // Stage-2 must happen after the M15 candle that produced Stage-1.
   // This prevents the primary seed candle itself from also becoming the
   // Flip/MajicFlip confirmation candle.
   if(st.start_bar_time > 0 && breaker_open_time <= st.start_bar_time)
      return false;

   // Close-based seeds such as FSMS are activated at the next M15 open; keep
   // the event-time guard as an additional safety rule.
   return (breaker_close_time > st.start_time);
}

inline bool __WB15_StageBuildDirectFlipUP(const MqlRates &rates[],
                                          const int n,
                                          const int idx,
                                          const WB15StageState &st,
                                          WB15StageState &out)
{
   if(idx <= 0 || idx >= n) return false;
   if(!__WB15_StageBreakerAfterStart(st, rates[idx].time)) return false;
   if(!__WB15_StageIsBull(rates[idx])) return false;
   if(rates[idx].low   >= rates[idx-1].low)  return false;
   if(rates[idx].close <= rates[idx-1].high) return false;

   out = st;
   out.zone_active      = true;
   out.on_sent          = false;
   out.zone_source      = 1;
   out.zone_kind        = 1;
   out.zone_anchor_time = rates[idx-1].time;
   out.zone_flip_time   = rates[idx].time;
   out.zone_top         = rates[idx-1].high;
   out.zone_bottom      = rates[idx].low;
   out.invalid_level    = rates[idx].low;
   __WB15_StageNormalizeZone(out);
   return true;
}

inline bool __WB15_StageBuildDirectFlipDOWN(const MqlRates &rates[],
                                            const int n,
                                            const int idx,
                                            const WB15StageState &st,
                                            WB15StageState &out)
{
   if(idx <= 0 || idx >= n) return false;
   if(!__WB15_StageBreakerAfterStart(st, rates[idx].time)) return false;
   if(!__WB15_StageIsBear(rates[idx])) return false;
   if(rates[idx].high  <= rates[idx-1].high) return false;
   if(rates[idx].close >= rates[idx-1].low)  return false;

   out = st;
   out.zone_active      = true;
   out.on_sent          = false;
   out.zone_source      = 1;
   out.zone_kind        = 1;
   out.zone_anchor_time = rates[idx-1].time;
   out.zone_flip_time   = rates[idx].time;
   out.zone_top         = rates[idx].high;
   out.zone_bottom      = rates[idx-1].low;
   out.invalid_level    = rates[idx].high;
   __WB15_StageNormalizeZone(out);
   return true;
}

inline bool __WB15_StageBuildMotherFlipUP(const MqlRates &rates[],
                                          const int n,
                                          const int idx,
                                          const WB15StageState &st,
                                          const bool majic,
                                          WB15StageState &out)
{
   if(idx < 2 || idx >= n) return false;
   if(!__WB15_StageBreakerAfterStart(st, rates[idx].time)) return false;
   if(!__WB15_StageIsBull(rates[idx])) return false;

   // Fast one-pass version of the original mother+inside scan. It preserves the
   // same nearest-mother priority but avoids rescanning the inside range for each
   // candidate mother on every M15 candle.
   // Bound the historical mother search by InpMaxBarsInWave to prevent long
   // full-history back scans after FSMS stage-1 starts.
   int min_m = idx - InpMaxBarsInWave;
   if(min_m < 0) min_m = 0;

   double mid_max_high = -DBL_MAX;
   double mid_min_low  = DBL_MAX;

   for(int m = idx - 2; m >= min_m; --m)
   {
      int mid_idx = m + 1;
      if(mid_idx >= 0 && mid_idx < idx)
      {
         if(rates[mid_idx].high > mid_max_high) mid_max_high = rates[mid_idx].high;
         if(rates[mid_idx].low  < mid_min_low)  mid_min_low  = rates[mid_idx].low;
      }

      if(!__WB15_StageIsBear(rates[m]))
         continue;

      if(mid_max_high > rates[m].high) continue;
      if(mid_min_low  < rates[m].low)  continue;

      if(rates[idx].close <= rates[m].high)
         continue;
      if(majic && rates[idx].low >= rates[m].low)
         continue;

      out = st;
      out.zone_active      = true;
      out.on_sent          = false;
      out.zone_source      = (majic ? 2 : 1);
      out.zone_kind        = (majic ? 0 : 2);
      out.zone_anchor_time = rates[m].time;
      out.zone_flip_time   = rates[idx].time;
      out.zone_top         = rates[m].high;
      out.zone_bottom      = rates[idx].low;
      out.invalid_level    = rates[idx].low;
      __WB15_StageNormalizeZone(out);
      return true;
   }

   return false;
}

inline bool __WB15_StageBuildMotherFlipDOWN(const MqlRates &rates[],
                                            const int n,
                                            const int idx,
                                            const WB15StageState &st,
                                            const bool majic,
                                            WB15StageState &out)
{
   if(idx < 2 || idx >= n) return false;
   if(!__WB15_StageBreakerAfterStart(st, rates[idx].time)) return false;
   if(!__WB15_StageIsBear(rates[idx])) return false;

   // Fast one-pass version of the original mother+inside scan. It preserves the
   // same nearest-mother priority but avoids rescanning the inside range for each
   // candidate mother on every M15 candle.
   // Bound the historical mother search by InpMaxBarsInWave to prevent long
   // full-history back scans after FSMS stage-1 starts.
   int min_m = idx - InpMaxBarsInWave;
   if(min_m < 0) min_m = 0;

   double mid_max_high = -DBL_MAX;
   double mid_min_low  = DBL_MAX;

   for(int m = idx - 2; m >= min_m; --m)
   {
      int mid_idx = m + 1;
      if(mid_idx >= 0 && mid_idx < idx)
      {
         if(rates[mid_idx].high > mid_max_high) mid_max_high = rates[mid_idx].high;
         if(rates[mid_idx].low  < mid_min_low)  mid_min_low  = rates[mid_idx].low;
      }

      if(!__WB15_StageIsBull(rates[m]))
         continue;

      if(mid_max_high > rates[m].high) continue;
      if(mid_min_low  < rates[m].low)  continue;

      if(rates[idx].close >= rates[m].low)
         continue;
      if(majic && rates[idx].high <= rates[m].high)
         continue;

      out = st;
      out.zone_active      = true;
      out.on_sent          = false;
      out.zone_source      = (majic ? 2 : 1);
      out.zone_kind        = (majic ? 0 : 2);
      out.zone_anchor_time = rates[m].time;
      out.zone_flip_time   = rates[idx].time;
      out.zone_top         = rates[idx].high;
      out.zone_bottom      = rates[m].low;
      out.invalid_level    = rates[idx].high;
      __WB15_StageNormalizeZone(out);
      return true;
   }

   return false;
}

inline bool __WB15_StageBuildZoneOnClosedBar(const MqlRates &rates[],
                                             const int n,
                                             const int idx,
                                             const WB15StageState &st,
                                             WB15StageState &out)
{
   if(!st.active) return false;
   if(st.zone_active) return false;
   if(st.on_sent) return false;
   if(idx < 0 || idx >= n) return false;
   if(!__WB15_IsClosedM15Bar(rates[idx])) return false;

   // Prefer MajicFlip when both patterns complete on the same M15 candle,
   // then fall back to normal Flip. The Stage-3 zone always follows the new
   // user rule: breaker-candle extreme to the body-broken candle level.
   if(st.start_dir == DIR_UP)
   {
      if(__WB15_StageBuildMotherFlipUP(rates, n, idx, st, true, out))  return true;
      if(__WB15_StageBuildDirectFlipUP(rates, n, idx, st, out))        return true;
      if(__WB15_StageBuildMotherFlipUP(rates, n, idx, st, false, out)) return true;
   }
   else
   {
      if(__WB15_StageBuildMotherFlipDOWN(rates, n, idx, st, true, out))  return true;
      if(__WB15_StageBuildDirectFlipDOWN(rates, n, idx, st, out))        return true;
      if(__WB15_StageBuildMotherFlipDOWN(rates, n, idx, st, false, out)) return true;
   }

   return false;
}

inline bool __WB15_StageM1TouchInvalidTimes(const string sym,
                                            const Direction dir,
                                            const datetime m15_open_time,
                                            const double zone_top,
                                            const double zone_bottom,
                                            const double invalid_level,
                                            datetime &touch_time,
                                            datetime &invalid_time)
{
   touch_time   = 0;
   invalid_time = 0;

   datetime from_time = 0;
   datetime to_time   = 0;
   if(!__WB15_BuildIntrabarSearchWindow(m15_open_time, from_time, to_time))
      return false;

   MqlRates bars[];
   int n = __WB15_LoadIntrabarM15(sym, from_time, to_time, bars);
   if(n <= 0) return false;

   const double eps = __WB15_StageEps();
   double top = zone_top;
   double bottom = zone_bottom;
   if(bottom > top)
   {
      double tmp = bottom;
      bottom = top;
      top = tmp;
   }

   for(int i = 0; i < n; ++i)
   {
      bool touched = (bars[i].low <= (top + eps) && bars[i].high >= (bottom - eps));
      bool invalid = false;

      if(dir == DIR_UP)
         invalid = (bars[i].low < invalid_level);
      else
         invalid = (bars[i].high > invalid_level);

      datetime event_time = __WB15_StableM15IntrabarTime(bars[i].time);
      if(event_time <= 0)
         continue;

      // Conservative priority rule:
      // if a single M1 candle both touches and pierces the invalidation edge,
      // the zone is considered invalid immediately.  MQL rates do not expose
      // the intrabar tick order, and accepting a trigger from such a candle can
      // create trades from a dead M15 Flip/MajicFlip zone.
      if(invalid && invalid_time <= 0)
         invalid_time = event_time;

      if(touched && touch_time <= 0)
         touch_time = event_time;

      if(invalid_time > 0 && (touch_time <= 0 || invalid_time <= touch_time))
         return true;

      if(touch_time > 0 && invalid_time > 0)
         return true;
   }

   return (touch_time > 0 || invalid_time > 0);
}

inline void __WB15_StageInvalidateZone(const string sym,
                                       WB15StageState &st,
                                       const datetime invalid_time,
                                       const string reason,
                                       const bool send_m1_stop)
{
   if(!st.active) return;
   if(!st.zone_active) return;
   if(invalid_time <= 0) return;

   const bool had_m1_on = st.on_sent;
   const Direction stop_dir = __WB15_Opposite(st.start_dir);

   if(InpDebugPrints)
      Print("[WB15-STAGE] Stage-2 zone invalidated | zone=",
            __WB15_StageSourceLabel(st.zone_source, st.zone_kind),
            " | dir=", (st.start_dir==DIR_UP ? "UP" : "DOWN"),
            " | t=", TimeToString(invalid_time, TIME_DATE|TIME_SECONDS),
            " | reason=", reason);

   WBLOG_M15ZoneStatus(st.log_zone_id, "INVALIDATED", invalid_time, (int)invalid_time, reason);
   WBLOG_LogM15GateEvent(st.log_context_id, st.log_zone_id, "ZONE_INVALIDATED", st.start_dir, invalid_time, (int)invalid_time,
                         0.0, 0.0, 0.0, 0.0, st.zone_bottom, st.zone_top, reason);

   if(send_m1_stop && had_m1_on)
   {
      // This is not the original Stage-1 OFF.  It only closes the already-open
      // M1 trigger window because the Stage-2 Flip/MajicFlip zone has died.
      TriggerM15SignalGate_RecordExact(sym, WB15_KIND_STOP_ZONE_INVALIDATED, st.start_ns, stop_dir, invalid_time);

      WB15_MasterPushEvent(sym,
                           WB15_KIND_STOP_ZONE_INVALIDATED,
                           st.start_ns,
                           stop_dir,
                           invalid_time,
                           st.log_context_id,
                           st.log_zone_id,
                           0,
                           st.zone_source,
                           st.zone_kind,
                           st.zone_bottom,
                           st.zone_top,
                           reason);

      WBLOG_LogM15GateEvent(st.log_context_id, st.log_zone_id, "M1_STOP_SENT", st.start_dir, invalid_time, (int)invalid_time,
                            0.0, 0.0, 0.0, 0.0, st.zone_bottom, st.zone_top, "zone_invalidated_after_m1_start");
   }

   WBLOG_LogResetEvent("ZONE_ONLY_RESET",
                       st.start_dir,
                       st.log_context_id,
                       st.log_zone_id,
                       0,
                       "ZONE_INVALIDATED",
                       (had_m1_on ? "STAGE_3_M1_ON_SENT" : "STAGE_2_ZONE_ACTIVE"),
                       "STAGE_2_SEARCH",
                       invalid_time,
                       PERIOD_M15,
                       0.0,
                       0.0,
                       0.0);

   __WB15_StageClearZone(st);
}

inline void __WB15_StagePublishON(const string sym,
                                  WB15StageState &st,
                                  const datetime touch_time)
{
   if(!st.active) return;
   if(!st.zone_active) return;
   if(st.on_sent) return;
   if(touch_time <= 0) return;

   // The SignalGate record must represent the real M1 activation time,
   // not the Stage-1 seed candle.
   TriggerM15SignalGate_RecordExact(sym, st.start_kind, st.start_ns, st.start_dir, touch_time);

   WBLOG_M15ZoneStatus(st.log_zone_id, "RETOUCHED", touch_time, (int)touch_time, "ZONE_RETOUCH_M1_START_SENT");
   WBLOG_LogM15GateEvent(st.log_context_id, st.log_zone_id, "ZONE_RETOUCH", st.start_dir, touch_time, (int)touch_time, 0.0, 0.0, 0.0, 0.0, st.zone_bottom, st.zone_top, "retouch_confirmed");

   WB15_MasterPushEvent(sym, st.start_kind, st.start_ns, st.start_dir, touch_time,
                        st.log_context_id, st.log_zone_id, 0, st.zone_source, st.zone_kind, st.zone_bottom, st.zone_top, "");
   st.on_sent = true;

   WBLOG_LogM15GateEvent(st.log_context_id, st.log_zone_id, "M1_START_SENT", st.start_dir, touch_time, (int)touch_time, 0.0, 0.0, 0.0, 0.0, st.zone_bottom, st.zone_top, "stage3_start_published_to_m1");
   WBLOG_LogStateTransition("WB15_SignalBridge", "STAGE_2_ZONE_ACTIVE", "STAGE_3_M1_ON_SENT", st.start_dir, st.log_context_id, st.log_zone_id, 0, 0, "ZONE_RETOUCH", touch_time, PERIOD_M15, (int)touch_time, 0.0, 0.0, 0.0, 0.0);

   if(InpDebugPrints)
      Print("[WB15-STAGE] Stage-3 retouch -> M1 ON | kind=", __WB15_StartKindLabel(st.start_kind),
            " | zone=", __WB15_StageSourceLabel(st.zone_source, st.zone_kind),
            " | dir=", (st.start_dir==DIR_UP ? "UP" : "DOWN"),
            " | touch=", TimeToString(touch_time, TIME_DATE|TIME_SECONDS));
}

inline void __WB15_StageProcessZoneRetouch(const string sym,
                                           WB15StageState &st,
                                           const MqlRates &bar)
{
   if(!st.active) return;
   if(!st.zone_active) return;
   if(bar.time <= st.zone_flip_time) return;

   datetime touch_time = 0;
   datetime invalid_time = 0;
   bool got_m1 = __WB15_StageM1TouchInvalidTimes(sym,
                                                 st.start_dir,
                                                 bar.time,
                                                 st.zone_top,
                                                 st.zone_bottom,
                                                 st.invalid_level,
                                                 touch_time,
                                                 invalid_time);

   if(got_m1)
   {
      // BEFORE M1 ON: invalidation has priority over retouch when both are
      // detected on the same M1 candle.  If retouch happened earlier and the
      // invalidation happened later in the same M15 candle, publish ON and then
      // immediately publish a zone-invalidation STOP at the invalid M1 candle.
      if(!st.on_sent)
      {
         if(invalid_time > 0 && (touch_time <= 0 || invalid_time <= touch_time))
         {
            __WB15_StageInvalidateZone(sym, st, invalid_time, "ZONE_INVALIDATED_BEFORE_RETOUCH", false);
            return;
         }

         if(touch_time > 0)
         {
            __WB15_StagePublishON(sym, st, touch_time);

            if(invalid_time > 0 && invalid_time > touch_time)
            {
               __WB15_StageInvalidateZone(sym, st, invalid_time, "ZONE_INVALIDATED_AFTER_RETOUCH", true);
               return;
            }

            return;
         }
      }
      else
      {
         // AFTER M1 ON: keep the Flip/MajicFlip zone alive only while price has
         // not pierced its invalidation edge.  This closes the M1 trigger window
         // before any trigger on the invalidating M1 candle can become a trade.
         if(invalid_time > 0)
         {
            __WB15_StageInvalidateZone(sym, st, invalid_time, "ZONE_INVALIDATED_AFTER_M1_START", true);
            return;
         }
      }
   }

   // Fallback when M1 intrabar data is unavailable.
   // Conservative priority: an M15 bar that both touches and pierces the invalid
   // edge invalidates the zone instead of opening/keeping a trigger window.
   const double eps = __WB15_StageEps();
   bool touched_fallback = (bar.low <= (st.zone_top + eps) && bar.high >= (st.zone_bottom - eps));
   bool invalid_fallback = false;

   if(st.start_dir == DIR_UP)
      invalid_fallback = (bar.low < st.invalid_level);
   else
      invalid_fallback = (bar.high > st.invalid_level);

   if(invalid_fallback)
   {
      __WB15_StageInvalidateZone(sym,
                                 st,
                                 bar.time,
                                 (st.on_sent ? "ZONE_INVALIDATED_AFTER_M1_START_M15_FALLBACK" : "ZONE_INVALIDATED_BEFORE_RETOUCH_M15_FALLBACK"),
                                 st.on_sent);
      return;
   }

   if(!st.on_sent && touched_fallback)
   {
      datetime te = 0;
      if(!__WB15_FindFirstRangeTouchIntrabarTime(sym, bar.time, st.zone_bottom, st.zone_top, te))
         te = __WB15_StableM15IntrabarTime(bar.time);
      __WB15_StagePublishON(sym, st, te);
      return;
   }
}

inline bool __WB15_StageTryArmZoneOnBar(const string sym,
                                        WB15StageState &st,
                                        const MqlRates &rates[],
                                        const int n,
                                        const int bar_idx)
{
   if(!st.active) return false;
   if(st.zone_active) return false;
   if(st.on_sent) return false;
   if(bar_idx < 0 || bar_idx >= n) return false;

   WB15StageState candidate;
   if(!__WB15_StageBuildZoneOnClosedBar(rates, n, bar_idx, st, candidate))
      return false;

   st = candidate;
   st.log_zone_id = WBLOG_M15FlipZoneCreated(sym,
                                             st.log_context_id,
                                             st.zone_source,
                                             st.zone_kind,
                                             st.start_dir,
                                             st.zone_flip_time,
                                             st.zone_anchor_time,
                                             st.zone_bottom,
                                             st.zone_top,
                                             st.invalid_level);

   if(InpDebugPrints)
      Print("[WB15-STAGE] Stage-2 zone armed | kind=", __WB15_StartKindLabel(st.start_kind),
            " | zone=", __WB15_StageSourceLabel(st.zone_source, st.zone_kind),
            " | top=", DoubleToString(st.zone_top, _Digits),
            " | bottom=", DoubleToString(st.zone_bottom, _Digits),
            " | invalid=", DoubleToString(st.invalid_level, _Digits),
            " | flip=", TimeToString(st.zone_flip_time, TIME_DATE|TIME_SECONDS));

   return true;
}

inline void __WB15_StageProcessStateOnBar(const string sym,
                                          WB15StageState &st,
                                          const MqlRates &rates[],
                                          const int n,
                                          const int bar_idx)
{
   if(!__WB15_IsMaster()) return;
   if(!st.active) return;
   if(bar_idx < 0 || bar_idx >= n) return;

   // Direct Stage-1 mode: a confirmed "new" seed publishes M1 ON immediately
   // inside __WB15_StageStartState().  Once on_sent=true, Stage-2 and Stage-3
   // must stay disabled so M15 Flip/MajicFlip zones cannot change the window.
   if(st.on_sent)
      return;

   bool had_zone_before_process = st.zone_active;

   if(!st.zone_active)
      __WB15_StageTryArmZoneOnBar(sym, st, rates, n, bar_idx);

   __WB15_StageProcessZoneRetouch(sym, st, rates[bar_idx]);

   if(had_zone_before_process && !st.zone_active && !st.on_sent && st.active)
      __WB15_StageTryArmZoneOnBar(sym, st, rates, n, bar_idx);
}

inline void WB15_MasterOnM15Bar(const string sym,
                                const MqlRates &rates[],
                                const int n,
                                const int bar_idx)
{
   if(!__WB15_IsMaster()) return;
   if(n <= 0) return;
   if(bar_idx < 0 || bar_idx >= n) return;

   WBLOG_LogCandleAndFeatures(sym, PERIOD_M15, rates, n, bar_idx);

   __WB15_StageProcessStateOnBar(sym, g_wb15_stage_maj, rates, n, bar_idx);
   __WB15_StageProcessStateOnBar(sym, g_wb15_stage_min, rates, n, bar_idx);
}



// START (EXACT FORMATION MOMENT): HWX
inline void WB15_PublishStartHWX(const string sym,
                                 const Direction dir,
                                 const datetime h4_open_time,
                                 const double level)
{
   const int ns = __WB15_NS_FromMarkers();

   datetime te = 0;
   if(!__WB15_FindFirstHWXIntrabarTime(sym, dir, h4_open_time, level, te))
      te = __WB15_StableM15IntrabarTime(h4_open_time);

   if(te <= 0) return;

   __WB15_StageStart(sym, WB15_KIND_START_HWX, ns, dir, te, h4_open_time);
}

// Legacy fallback overload (kept for compatibility)
inline void WB15_PublishStartHWX(const string sym, const Direction dir, const datetime t)
{
   const int ns = __WB15_NS_FromMarkers();
   __WB15_StageStart(sym, WB15_KIND_START_HWX, ns, dir, t, t);
}

// START (EXACT FORMATION MOMENT): HWBB
inline void WB15_PublishStartHWBB(const string sym,
                                  const Direction dir,
                                  const datetime h4_open_time,
                                  const double start_level,
                                  const datetime seed_h4_open_time)
{
   const int ns = __WB15_NS_FromMarkers();

   datetime te = 0;
   if(!__WB15_FindFirstHWBBIntrabarTime(sym, dir, h4_open_time, start_level, seed_h4_open_time, te))
      te = __WB15_StableM15IntrabarTime(h4_open_time);

   if(te <= 0) return;

   __WB15_StageStart(sym, WB15_KIND_START_HWBB, ns, dir, te, h4_open_time);
}

// Legacy fallback overload (kept for compatibility)
inline void WB15_PublishStartHWBB(const string sym, const Direction dir, const datetime t)
{
   const int ns = __WB15_NS_FromMarkers();

   const datetime te = __WB15_CloseBasedEventTimeOrZero(t);
   if(te <= 0) return;

   __WB15_StageStart(sym, WB15_KIND_START_HWBB, ns, dir, te, t);
}

// START (ON M15 CLOSE): FSMS
// NOTE: legacy function name is kept to avoid touching the wider codebase.
// It now publishes in BOTH MAJ and MIN namespaces, based on the active world.
inline void WB15_PublishStartFSMS_MAJONLY(const string sym, const Direction dir, const datetime t)
{
   const int ns = __WB15_NS_FromMarkers();
   if(ns == WB15_NS_NONE) return;

   const datetime te = __WB15_CloseBasedEventTimeOrZero(t);
   if(te <= 0) return;

   __WB15_StageStart(sym, WB15_KIND_START_FSMS, ns, dir, te, t);
}

// START (EXACT FORMATION MOMENT): GOOZBAGHALI
inline void WB15_PublishStartGooz(const string sym,
                                  const Direction dir,
                                  const datetime h4_open_time,
                                  const double price_a,
                                  const double price_b)
{
   const int ns = __WB15_NS_FromMarkers();

   datetime te = 0;
   if(!__WB15_FindFirstRangeTouchIntrabarTime(sym, h4_open_time, price_a, price_b, te))
      te = __WB15_StableM15IntrabarTime(h4_open_time);

   if(te <= 0) return;

   __WB15_StageStart(sym, WB15_KIND_START_GOOZBAGHALI, ns, dir, te, h4_open_time);
}

// Legacy fallback overload (kept for compatibility)
inline void WB15_PublishStartGooz(const string sym, const Direction dir, const datetime t)
{
   const int ns = __WB15_NS_FromMarkers();
   __WB15_StageStart(sym, WB15_KIND_START_GOOZBAGHALI, ns, dir, t, t);
}

// STOP (ON CLOSE): MTC must wait for M15 close
inline void WB15_PublishStopMTC(const string sym, const Direction dir, const datetime t)
{
   const int ns = __WB15_NS_FromMarkers();
   if(ns != WB15_NS_NONE)
      TriggerM15SignalGate_RecordClose(sym, WB15_KIND_STOP_MTC, ns, dir, t);

   const datetime te = __WB15_CloseBasedEventTimeOrZero(t);
   if(te <= 0) return;

   __WB15_StageStop(dir, te);

   WB15_MasterPushEvent(sym, WB15_KIND_STOP_MTC, ns, dir, te, 0, 0, 0, 0, 0, 0.0, 0.0, "MTC_OFF");
}

// STOP (ON CLOSE, MAJ-only): MinorStarter must wait for M15 close
inline void WB15_PublishStopMinorStarter(const string sym, const Direction dir, const datetime t)
{
   TriggerM15SignalGate_RecordClose(sym, WB15_KIND_STOP_MINORSTARTER, WB15_NS_MAJ, dir, t);

   const datetime te = __WB15_CloseBasedEventTimeOrZero(t);
   if(te <= 0) return;

   __WB15_StageStop(dir, te);

   WB15_MasterPushEvent(sym, WB15_KIND_STOP_MINORSTARTER, WB15_NS_MAJ, dir, te, 0, 0, 0, 0, 0, 0.0, 0.0, "MINORSTARTER_OFF");
}

// STOP (ON CLOSE, MAJ-only): MinorOff zone must wait for M15 close
inline void WB15_PublishStopMinorOffZone_MAJONLY(const string sym, const Direction dir, const datetime t)
{
   // Stop trigger: MAJ MinorOff breaks C1-W2 Minorzone boundary (used to stop MIN-start M1 sessions)
   if(Markers_GetNamespace() != "MAJ") return;

   TriggerM15SignalGate_RecordClose(sym, WB15_KIND_STOP_MINOROFF_ZONE, WB15_NS_MAJ, dir, t);

   const datetime te = __WB15_CloseBasedEventTimeOrZero(t);
   if(te <= 0) return;

   __WB15_StageStop(dir, te);

   WB15_MasterPushEvent(sym, WB15_KIND_STOP_MINOROFF_ZONE, WB15_NS_MAJ, dir, te, 0, 0, 0, 0, 0, 0.0, 0.0, "MINOROFF_ZONE_OFF");
}


// ============================================================================
// SLAVE (M1): drawing helpers
// ============================================================================

inline bool __WB15_GetBarHL(const string sym, const datetime t, double &hi, double &lo)
{
   int sh = iBarShift(sym, PERIOD_M1, t, false);
   if(sh < 0) return false;
   MqlRates rr[1];
   if(CopyRates(sym, PERIOD_M1, sh, 1, rr) != 1) return false;
   hi = rr[0].high;
   lo = rr[0].low;
   return true;
}

inline void __WB15_DrawVLineUnique(const string name, const datetime t, const color col, const int width)
{
   if(!InpDrawMarkers) return;
   if(ObjectFind(0, name) != -1) return;
   if(!ObjectCreate(0, name, OBJ_VLINE, 0, t, 0)) return;
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

inline void __WB15_DrawTextUnique(const string name, const datetime t, const double price,
                                 const string text, const color col, const int fontSize)
{
   if(!InpDrawMarkers) return;
   if(ObjectFind(0, name) != -1) return;
   if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, price)) return;
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

inline void __WB15_DrawSignalMarker(const string sym,
                                   const double run_id,
                                   const int evt_seq,
                                   const datetime t,
                                   const bool is_on,
                                   const Direction dir,
                                   const int kind,
                                   const int ns)
{
   double hi=0.0, lo=0.0;
   if(!__WB15_GetBarHL(sym, t, hi, lo))
   {
      // fallback: draw vline at time without label
      string vname = "WB15_V_" + DoubleToString(run_id, 0) + "_" + IntegerToString(evt_seq) + (is_on?"_ON":"_OFF");
      __WB15_DrawVLineUnique(vname, t, clrRed, 3);
      return;
   }

   double span = hi - lo;
   if(span <= 0.0) span = 10.0 * _Point;

   // BIGGER vertical distance from candles (for clarity on M1)
   double pad = span * 0.60;
   if(pad < 8.0 * _Point) pad = 8.0 * _Point;

   double y = (dir == DIR_UP ? hi + pad : lo - pad);

   string tag   = DoubleToString(run_id, 0) + "_" + IntegerToString(evt_seq);
   string vname = "WB15_SIG_" + tag + (is_on?"_ON":"_OFF");

   // VLine
   __WB15_DrawVLineUnique(vname, t, clrRed, 3);

   // Texts
   if(is_on)
   {
      string hname = vname + "_TXT_H";
      string tname = vname + "_TXT_T";

      __WB15_DrawTextUnique(hname, t, y, "15M Signal on", clrBlue, 10);

      // Put type line under the main label (lower price), but keep it far from candles
      double gap = pad * 0.30;
      if(gap < 10.0 * _Point) gap = 10.0 * _Point;

      double y2 = y - gap;
      __WB15_DrawTextUnique(tname, t, y2, __WB15_StartTypeText(kind, ns, dir), clrBlue, 9);
   }
   else
   {
      string tname = vname + "_TXT";
      __WB15_DrawTextUnique(tname, t, y, "15M Signal off", clrBlue, 10);
   }
}

// ============================================================================
// SLAVE (M1): live candle-by-candle numbering helpers
// (Uses the same bar-mapping logic as minor-range starter/ender numbering:
//  resolve event time -> M1 bar by iBarShift(..., false) then iTime(...))
// ============================================================================

inline bool __WB15_ResolveM15BarTime(const string sym, const datetime t, datetime &bar_time)
{
   int sh = iBarShift(sym, PERIOD_M1, t, false);
   if(sh < 0) return false;
   bar_time = iTime(sym, PERIOD_M1, sh);
   return (bar_time > 0);
}

inline int __WB15_BarShiftM15Safe(const string sym, const datetime bar_time)
{
   int sh = iBarShift(sym, PERIOD_M1, bar_time, true);
   if(sh < 0) sh = iBarShift(sym, PERIOD_M1, bar_time, false);
   return sh;
}

inline bool __WB15_CountsEnabled()
{
   // Signal-window numbering is intentionally disabled.
   // Only trigger-phase labels from Trigger.mqh should remain on chart.
   return false;
}

inline void __WB15_DeleteAllCountLabels()
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; --i)
   {
      string on = ObjectName(0, i);
      if(on == "") continue;
      if(StringFind(on, "WB15_CNT_") == 0)
         ObjectDelete(0, on);
   }
}

inline void __WB15_DrawCountLabel(const string sym,
                                 const double run_id,
                                 const int start_evt_seq,
                                 const datetime bar_time,
                                 const int num,
                                 const Direction dir)
{
   if(!__WB15_CountsEnabled()) return;

   double hi=0.0, lo=0.0;
   if(!__WB15_GetBarHL(sym, bar_time, hi, lo))
      return;

   double span = hi - lo;
   if(span <= 0.0) span = 10.0 * _Point;
   double pad = span * 0.25;
   if(pad < 3.0 * _Point) pad = 3.0 * _Point;

   double y = (dir == DIR_UP ? hi + pad : lo - pad);

   string name = "WB15_CNT_" + DoubleToString(run_id, 0) + "_" + IntegerToString(start_evt_seq) + "_" + IntegerToString(num);
   __WB15_DrawTextUnique(name, bar_time, y, IntegerToString(num), clrAqua, 8);
}

inline void __WB15_DeleteCountLabels(const double run_id,
                                    const int start_evt_seq,
                                    const int from_num,
                                    const int to_num)
{
   if(!__WB15_CountsEnabled()) return;
   if(from_num > to_num) return;

   for(int n = from_num; n <= to_num; ++n)
   {
      string name = "WB15_CNT_" + DoubleToString(run_id, 0) + "_" + IntegerToString(start_evt_seq) + "_" + IntegerToString(n);
      if(ObjectFind(0, name) != -1)
         ObjectDelete(0, name);
   }
}

inline int __WB15_CountBarsExclusiveM15(const string sym, const datetime start_bar_time, const datetime stop_bar_time)
{
   if(!__WB15_CountsEnabled()) return 0;
   if(start_bar_time <= 0 || stop_bar_time <= 0) return 0;

   int sh_start = __WB15_BarShiftM15Safe(sym, start_bar_time);
   int sh_stop  = __WB15_BarShiftM15Safe(sym, stop_bar_time);
   if(sh_start < 0 || sh_stop < 0) return 0;
   if(sh_start <= sh_stop) return 0;

   int cnt = sh_start - sh_stop - 1; // exclude both boundary candles
   if(cnt < 0) cnt = 0;
   return cnt;
}

// Advance the live counter forward (no look-ahead).
// - If until_exclusive_bar_time == 0: count forward up to the last CLOSED M1 candle.
// - If until_exclusive_bar_time  > 0: count forward, but do NOT count the candle whose open time == until_exclusive_bar_time
//   (i.e., stop before OFF candle).
inline void __WB15_LiveCountAdvance(const string sym, const datetime until_exclusive_bar_time)
{
   if(!__WB15_CountsEnabled()) return;
   if(!g_wb15_state.active) return;
   if(g_wb15_state.start_bar_time <= 0) return;

   // Only closed candles are eligible for numbering
   datetime last_closed_time = iTime(sym, PERIOD_M1, 1);
   if(last_closed_time <= 0) return;

   datetime cur = g_wb15_state.last_count_bar_time;
   if(cur <= 0) cur = g_wb15_state.start_bar_time;

   while(true)
   {
      int sh = __WB15_BarShiftM15Safe(sym, cur);
      if(sh < 0) break;

      int next_sh = sh - 1;
      if(next_sh < 1) break; // do not number current (forming) candle

      datetime next_time = iTime(sym, PERIOD_M1, next_sh);
      if(next_time <= 0) break;

      // Safety: should never exceed the last closed candle, but keep guard
      if(next_time > last_closed_time) break;

      // Upper bound (OFF candle open time) if provided
      if(until_exclusive_bar_time > 0 && next_time >= until_exclusive_bar_time)
         break;

      g_wb15_state.count++;
      __WB15_DrawCountLabel(sym,
                           g_wb15_state.run_id,
                           g_wb15_state.start_evt_seq,
                           next_time,
                           g_wb15_state.count,
                           g_wb15_state.start_dir);

      g_wb15_state.last_count_bar_time = next_time;
      cur = next_time;
   }
}

// (Optional legacy helper) Draw counts for the whole range at once.
// This uses the same bar-resolution logic (iBarShift false -> iTime) and
// numbers candles strictly INSIDE [from_t .. to_t] (excluding both boundary candles).
inline void __WB15_DrawCountSequence(const string sym,
                                    const double run_id,
                                    const int start_evt_seq,
                                    const datetime from_t,
                                    const datetime to_t,
                                    const Direction dir)
{
   if(!__WB15_CountsEnabled()) return;
   if(to_t <= from_t) return;

   datetime start_bt = 0;
   datetime stop_bt  = 0;
   if(!__WB15_ResolveM15BarTime(sym, from_t, start_bt)) return;
   if(!__WB15_ResolveM15BarTime(sym, to_t,   stop_bt))  return;
   if(stop_bt <= start_bt) return;

   int sh_start = __WB15_BarShiftM15Safe(sym, start_bt);
   int sh_stop  = __WB15_BarShiftM15Safe(sym, stop_bt);
   if(sh_start < 0 || sh_stop < 0) return;
   if(sh_start <= sh_stop) return;

   int num = 0;
   // Candle order: from older (start) towards newer (stop)
   for(int sh = sh_start - 1; sh >= sh_stop + 1; --sh)
   {
      datetime bt = iTime(sym, PERIOD_M1, sh);
      if(bt <= 0) continue;

      num++;
      __WB15_DrawCountLabel(sym, run_id, start_evt_seq, bt, num, dir);
   }
}

// ============================================================================
// SLAVE (M1): match rules + OnTimer
// ============================================================================

inline bool __WB15_IsStartKind(const int kind)
{
   // M1 may only open a window from direct Stage-1 "new" signals.
   return (kind == WB15_KIND_START_HWX || kind == WB15_KIND_START_HWBB || kind == WB15_KIND_START_FSMS);
}

inline bool __WB15_IsStopKind(const int kind)
{
   return (kind == WB15_KIND_STOP_MTC || kind == WB15_KIND_STOP_MINORSTARTER || kind == WB15_KIND_STOP_MINOROFF_ZONE || kind == WB15_KIND_STOP_ZONE_INVALIDATED);
}

inline bool __WB15_ShouldStop(const WB15ActiveState &st, const int stop_kind, const int stop_ns, const Direction stop_dir)
{
   if(!st.active) return false;
   if(!__WB15_IsStopKind(stop_kind)) return false;

   // Simplified rule:
   //   any M15 signal off closes the current M1 trigger window,
   //   as long as the stop direction is the opposite of the active signal direction.
   // Namespace and signal type no longer participate in stop matching.
   if(stop_dir != __WB15_Opposite(st.start_dir))
      return false;

   return true;
}

inline bool __WB15_ShouldAutoStopOnNewStart(const WB15ActiveState &st,
                                            const int new_kind,
                                            const int new_ns)
{
   // A fresh M15 signal on simply restarts the active window from its own candle.
   // We no longer synthesize a pseudo-off when a new start arrives.
   if(!st.active) return false;
   if(new_kind <= 0) return false;
   if(new_ns < 0) return false;
   return false;
}


inline void WB15_SlaveInit()
{
   __WB15_DeleteAllCountLabels();

   g_wb15_processed_seq = 0;
   g_wb15_run_seen      = 0.0;

   g_wb15_state.active  = false;
   g_wb15_state.start_kind = 0;
   g_wb15_state.start_ns   = 0;
   g_wb15_state.start_dir  = DIR_UP;
   g_wb15_state.start_time = 0;
   g_wb15_state.start_evt_seq = 0;
   g_wb15_state.run_id = 0.0;

   g_wb15_state.start_bar_time      = 0;
   g_wb15_state.last_count_bar_time = 0;
   g_wb15_state.count              = 0;
}

inline void WB15_Slave_OnTimer(const string sym)
{
   if(!__WB15_IsSlave()) return;

   const string kRun = __WB15_Key(sym, "RUN");
   const string kSeq = __WB15_Key(sym, "SEQ");
   const string kPrc = __WB15_Key(sym, "SLVSEQ");
   const string kRsv = __WB15_Key(sym, "SLVRUN");

   if(!GlobalVariableCheck(kRun) || !GlobalVariableCheck(kSeq))
      return; // master not ready

   const double run_id = GlobalVariableGet(kRun);
   if(run_id <= 0.0) return;

   // Detect new master run
   double last_run = 0.0;
   if(GlobalVariableCheck(kRsv)) last_run = GlobalVariableGet(kRsv);
   if(last_run != run_id)
   {
      // reset only internal state; keep drawings as archive
      WB15_SlaveInit();
      g_wb15_run_seen = run_id;
      GlobalVariableSet(kRsv, run_id);
      GlobalVariableSet(kPrc, 0.0);
   }

   int processed = 0;
   if(GlobalVariableCheck(kPrc)) processed = (int)GlobalVariableGet(kPrc);
   int seq = (int)GlobalVariableGet(kSeq);

   // 1) Process new M15 events (ON/OFF markers)
   if(seq > processed)
   {
      for(int i = processed + 1; i <= seq; ++i)
      {
         const string kt = __WB15_KeyT(sym, i);
         const string kc = __WB15_KeyC(sym, i);
         if(!GlobalVariableCheck(kt) || !GlobalVariableCheck(kc))
            continue;

         const datetime t = (datetime)GlobalVariableGet(kt);
         const int code = (int)GlobalVariableGet(kc);

         const int kind = code / 100;
         const int ns   = (code / 10) % 10;
         const int dc   = code % 10;
         const Direction dir = __WB15_CodeDir(dc);

         if(__WB15_IsStartKind(kind))
         {
            // Resolve ON candle open time on M1
            datetime on_bar_time = 0;
            if(!__WB15_ResolveM15BarTime(sym, t, on_bar_time))
               on_bar_time = t;

            // FSMS lifecycle mirror on M1:
            // a fresh HWX/HWBB start closes the currently active FSMS session first.
            if(__WB15_ShouldAutoStopOnNewStart(g_wb15_state, kind, ns))
            {
               if(__WB15_CountsEnabled())
               {
                  if(g_wb15_state.start_bar_time > 0 && on_bar_time > 0 && on_bar_time >= g_wb15_state.start_bar_time)
                  {
                     __WB15_LiveCountAdvance(sym, on_bar_time);

                     int correct = __WB15_CountBarsExclusiveM15(sym, g_wb15_state.start_bar_time, on_bar_time);
                     if(g_wb15_state.count > correct)
                     {
                        __WB15_DeleteCountLabels(run_id, g_wb15_state.start_evt_seq, correct + 1, g_wb15_state.count);
                        g_wb15_state.count = correct;
                     }
                  }
               }

               __WB15_DrawSignalMarker(sym, run_id, i, t, false, g_wb15_state.start_dir, 0, 0);
               g_wb15_state.active = false;
            }

            // RE-ENTRY while already active:
            // finalize old count up to this new ON candle, then restart counting from here
            if(__WB15_CountsEnabled() && g_wb15_state.active)
            {
               if(g_wb15_state.start_bar_time > 0 && on_bar_time > 0 && on_bar_time >= g_wb15_state.start_bar_time)
               {
                  // Count candles up to (but NOT including) the new ON candle
                  __WB15_LiveCountAdvance(sym, on_bar_time);

                  // Cleanup any over-numbering beyond boundary
                  int correct = __WB15_CountBarsExclusiveM15(sym, g_wb15_state.start_bar_time, on_bar_time);
                  if(g_wb15_state.count > correct)
                  {
                     __WB15_DeleteCountLabels(run_id, g_wb15_state.start_evt_seq, correct + 1, g_wb15_state.count);
                     g_wb15_state.count = correct;
                  }
               }
            }

            // Start/restart state (always)
            g_wb15_state.active        = true;
            g_wb15_state.start_kind    = kind;
            g_wb15_state.start_ns      = ns;
            g_wb15_state.start_dir     = dir;
            g_wb15_state.start_time    = t;
            g_wb15_state.start_evt_seq = i;
            g_wb15_state.run_id        = run_id;

            g_wb15_state.start_bar_time      = on_bar_time;
            g_wb15_state.last_count_bar_time = on_bar_time;
            g_wb15_state.count               = 0;

            // Draw ON marker + type line
            __WB15_DrawSignalMarker(sym, run_id, i, t, true, dir, kind, ns);
         }
         else if(__WB15_IsStopKind(kind))
         {
            if(__WB15_ShouldStop(g_wb15_state, kind, ns, dir))
            {
               if(__WB15_CountsEnabled())
               {
                  // Resolve OFF candle open time on M1
                  datetime off_bar_time = 0;
                  if(__WB15_ResolveM15BarTime(sym, t, off_bar_time))
                  {
                     // Count candles up to (but NOT including) the OFF candle
                     __WB15_LiveCountAdvance(sym, off_bar_time);

                     // Cleanup any over-numbering beyond OFF
                     int correct = __WB15_CountBarsExclusiveM15(sym, g_wb15_state.start_bar_time, off_bar_time);
                     if(g_wb15_state.count > correct)
                     {
                        __WB15_DeleteCountLabels(run_id, g_wb15_state.start_evt_seq, correct + 1, g_wb15_state.count);
                        g_wb15_state.count = correct;
                     }
                  }
               }

               __WB15_DrawSignalMarker(sym, run_id, i, t, false, g_wb15_state.start_dir, 0, 0);

               g_wb15_state.active = false;
            }
         }
      }

      GlobalVariableSet(kPrc, (double)seq);
   }

   // 2) Keep candle numbering advancing live on M1 while the session is active.
   if(__WB15_CountsEnabled() && g_wb15_state.active)
      __WB15_LiveCountAdvance(sym, 0);
}

#endif // WAVEBOT_WB15_SIGNAL_BRIDGE_MQH
