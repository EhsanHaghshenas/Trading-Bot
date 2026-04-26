#ifndef WAVEBOT_WB15_SIGNAL_BRIDGE_MQH
#define WAVEBOT_WB15_SIGNAL_BRIDGE_MQH

#include <WaveBot/Types.mqh>
#include <WaveBot/Markers.mqh>
#include <WaveBot/TriggerM15SignalGate.mqh>

// ============================================================================
// WB15_SignalBridge.mqh
// ----------------------------------------------------------------------------
// This file now hosts TWO live parent->child bridges:
//
//   1) H4  -> M15   (legacy bridge, names kept for compatibility)
//   2) M15 -> M1    (new bridge for the 3-timeframe architecture)
//
// The existing wrapper names WB15_Publish* are intentionally preserved because
// the wider codebase already calls them from signal-detection modules.
// Routing is chart-aware:
//
//   - on H4  : publish to the H4 -> M15 bridge
//   - on M15 : publish to the M15 -> M1 bridge
//   - on M1  : do not publish to a lower chart; record only the local worker
//              gate events used by TriggerStatement / local trigger gating
//
// Important priority rule:
//   When a parent H4 stop closes the active M15 window, the M15 chart cascades
//   the same stop event into the M15 -> M1 bridge immediately, so every active
//   M1 window is force-stopped even if local M15 stop has not formed yet.
// ============================================================================

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

   WB15_KIND_STOP_MTC           = 10,
   WB15_KIND_STOP_MINORSTARTER  = 11,
   WB15_KIND_STOP_MINOROFF_ZONE = 12
};

// ---- Internal state (child chart) ----
struct WB15ActiveState
{
   bool      active;
   int       start_kind;
   int       start_ns;
   Direction start_dir;
   datetime  start_time;
   int       start_evt_seq;
   double    run_id;
   datetime  start_bar_time;
   datetime  last_count_bar_time;
   int       count;
};

static int             g_wb15_processed_seq = 0;
static double          g_wb15_run_seen      = 0.0;
static WB15ActiveState g_wb15_state;

static int             g_wb1_processed_seq  = 0;
static double          g_wb1_run_seen       = 0.0;
static WB15ActiveState g_wb1_state;

// H4 -> M15 historical parent-window cache used by M15 while publishing to M1.
struct WB15HistEvent
{
   datetime  t;
   int       kind;
   int       ns;
   Direction dir;
   int       seq;
};

static WB15HistEvent g_wb15_hist_events[];
static double        g_wb15_hist_run_seen = 0.0;
static int           g_wb15_hist_seq_seen = -1;

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

inline string __WB1_Base(const string sym)
{
   return "WB1SIG_" + __WB15_SanitizeSymbol(sym);
}

inline string __WB15_Key(const string sym, const string suffix)
{
   return __WB15_Base(sym) + "_" + suffix;
}

inline string __WB1_Key(const string sym, const string suffix)
{
   return __WB1_Base(sym) + "_" + suffix;
}

inline string __WB15_KeyT(const string sym, const int seq)
{
   return __WB15_Key(sym, "T_" + IntegerToString(seq));
}

inline string __WB15_KeyC(const string sym, const int seq)
{
   return __WB15_Key(sym, "C_" + IntegerToString(seq));
}

inline string __WB1_KeyT(const string sym, const int seq)
{
   return __WB1_Key(sym, "T_" + IntegerToString(seq));
}

inline string __WB1_KeyC(const string sym, const int seq)
{
   return __WB1_Key(sym, "C_" + IntegerToString(seq));
}

inline bool __WB15_IsMaster()
{
   return ((ENUM_TIMEFRAMES)Period() == PERIOD_H4);
}

inline bool __WB15_IsSlave()
{
   return ((ENUM_TIMEFRAMES)Period() == PERIOD_M15);
}

inline bool __WB1_IsMaster()
{
   return ((ENUM_TIMEFRAMES)Period() == PERIOD_M15);
}

inline bool __WB1_IsSlave()
{
   return ((ENUM_TIMEFRAMES)Period() == PERIOD_M1);
}

inline int __WB15_NS_FromMarkers()
{
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

inline bool __WB15_IsStartKind(const int kind)
{
   return (kind == WB15_KIND_START_HWX ||
           kind == WB15_KIND_START_HWBB ||
           kind == WB15_KIND_START_FSMS ||
           kind == WB15_KIND_START_GOOZBAGHALI);
}

inline bool __WB15_IsStopKind(const int kind)
{
   return (kind == WB15_KIND_STOP_MTC ||
           kind == WB15_KIND_STOP_MINORSTARTER ||
           kind == WB15_KIND_STOP_MINOROFF_ZONE);
}

// Bridge-neutral helpers used by Trigger.mqh / TriggerStatement.mqh
inline bool WBBridge_UseM1Parent()
{
   return ((ENUM_TIMEFRAMES)Period() == PERIOD_M1);
}

inline string WBBridge_Key(const string sym, const string suffix)
{
   if(WBBridge_UseM1Parent())
      return __WB1_Key(sym, suffix);
   return __WB15_Key(sym, suffix);
}

inline string WBBridge_KeyT(const string sym, const int seq)
{
   if(WBBridge_UseM1Parent())
      return __WB1_KeyT(sym, seq);
   return __WB15_KeyT(sym, seq);
}

inline string WBBridge_KeyC(const string sym, const int seq)
{
   if(WBBridge_UseM1Parent())
      return __WB1_KeyC(sym, seq);
   return __WB15_KeyC(sym, seq);
}

inline Direction WBBridge_CodeDir(const int dc)
{
   return __WB15_CodeDir(dc);
}

inline Direction WBBridge_Opposite(const Direction d)
{
   return __WB15_Opposite(d);
}

inline string WBBridge_WorkerLabel()
{
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Period();
   if(tf == PERIOD_M1)  return "M1";
   if(tf == PERIOD_M15) return "M15";
   if(tf == PERIOD_H4)  return "H4";
   return "WORKER";
}

inline string WBBridge_ParentLabel()
{
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Period();
   if(tf == PERIOD_M1)  return "M15";
   if(tf == PERIOD_M15) return "H4";
   return "PARENT";
}

// ============================================================================
// Display helpers
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
// Generic time-mapping helpers
// ============================================================================

inline int __WBX_TFSec(const ENUM_TIMEFRAMES tf)
{
   int sec = PeriodSeconds(tf);
   if(sec > 0) return sec;

   if(tf == PERIOD_H4)  return 14400;
   if(tf == PERIOD_M15) return 900;
   if(tf == PERIOD_M1)  return 60;
   return 60;
}

inline datetime __WBX_CloseTime(const ENUM_TIMEFRAMES parent_tf,
                                const datetime        parent_open_time)
{
   if(parent_open_time <= 0) return 0;
   return (parent_open_time + (datetime)__WBX_TFSec(parent_tf));
}

inline datetime __WBX_CloseBasedEventTimeOrZero(const ENUM_TIMEFRAMES parent_tf,
                                                const datetime        parent_open_time)
{
   const datetime close_time = __WBX_CloseTime(parent_tf, parent_open_time);
   if(close_time <= 0) return 0;

   if(TimeCurrent() < close_time)
      return 0;

   return close_time;
}

inline datetime __WBX_StableChildIntrabarTime(const ENUM_TIMEFRAMES child_tf,
                                              const datetime        child_bar_open_time)
{
   if(child_bar_open_time <= 0) return 0;

   int sec = __WBX_TFSec(child_tf);
   datetime t = child_bar_open_time + 1;
   if(t >= (child_bar_open_time + (datetime)sec))
      t = child_bar_open_time;

   return t;
}

inline bool __WBX_BuildIntrabarSearchWindow(const ENUM_TIMEFRAMES parent_tf,
                                            const datetime        parent_open_time,
                                            datetime              &from_time,
                                            datetime              &to_time)
{
   from_time = 0;
   to_time   = 0;

   if(parent_open_time <= 0) return false;

   const datetime close_time = __WBX_CloseTime(parent_tf, parent_open_time);
   if(close_time <= parent_open_time) return false;

   from_time = parent_open_time;
   to_time   = close_time - 1;

   const datetime now = TimeCurrent();
   if(now < to_time)
      to_time = now;

   if(to_time < from_time)
      to_time = from_time;

   return true;
}

inline int __WBX_LoadIntrabar(const string          sym,
                              const ENUM_TIMEFRAMES child_tf,
                              const datetime        from_time,
                              const datetime        to_time,
                              MqlRates              &bars[])
{
   ArrayFree(bars);

   if(from_time <= 0) return 0;
   if(to_time < from_time) return 0;

   int copied = CopyRates(sym, child_tf, from_time, to_time, bars);
   if(copied <= 0) return 0;

   ArraySetAsSeries(bars, false);
   return copied;
}

inline bool __WBX_ResolveChildBarTime(const string          sym,
                                      const ENUM_TIMEFRAMES child_tf,
                                      const datetime        t,
                                      datetime              &bar_time)
{
   int sh = iBarShift(sym, child_tf, t, false);
   if(sh < 0) return false;

   bar_time = iTime(sym, child_tf, sh);
   return (bar_time > 0);
}

inline datetime __WBX_FallbackIntrabarTime(const string          sym,
                                           const ENUM_TIMEFRAMES child_tf,
                                           const datetime        parent_open_time)
{
   datetime child_bar_time = 0;
   if(!__WBX_ResolveChildBarTime(sym, child_tf, parent_open_time, child_bar_time))
      child_bar_time = parent_open_time;

   return __WBX_StableChildIntrabarTime(child_tf, child_bar_time);
}

inline bool __WBX_FindFirstHWXIntrabarTime(const string          sym,
                                           const ENUM_TIMEFRAMES parent_tf,
                                           const ENUM_TIMEFRAMES child_tf,
                                           const Direction       dir,
                                           const datetime        parent_open_time,
                                           const double          level,
                                           datetime              &event_time)
{
   event_time = 0;
   if(level <= 0.0) return false;

   datetime from_time = 0;
   datetime to_time   = 0;
   if(!__WBX_BuildIntrabarSearchWindow(parent_tf, parent_open_time, from_time, to_time))
      return false;

   MqlRates bars[];
   int n = __WBX_LoadIntrabar(sym, child_tf, from_time, to_time, bars);
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
         event_time = __WBX_StableChildIntrabarTime(child_tf, bars[i].time);
         return (event_time > 0);
      }
   }

   return false;
}

inline bool __WBX_FindFirstHWBBIntrabarTime(const string          sym,
                                            const ENUM_TIMEFRAMES parent_tf,
                                            const ENUM_TIMEFRAMES child_tf,
                                            const Direction       dir,
                                            const datetime        parent_open_time,
                                            const double          start_level,
                                            const datetime        seed_parent_open_time,
                                            datetime              &event_time)
{
   event_time = 0;
   if(start_level <= 0.0) return false;

   datetime min_event_time = parent_open_time;

   if(seed_parent_open_time > 0 && seed_parent_open_time == parent_open_time)
   {
      datetime hwx_time = 0;
      if(__WBX_FindFirstHWXIntrabarTime(sym,
                                        parent_tf,
                                        child_tf,
                                        dir,
                                        seed_parent_open_time,
                                        start_level,
                                        hwx_time))
      {
         if(hwx_time > min_event_time)
            min_event_time = hwx_time;
      }
   }

   datetime from_time = 0;
   datetime to_time   = 0;
   if(!__WBX_BuildIntrabarSearchWindow(parent_tf, parent_open_time, from_time, to_time))
      return false;

   MqlRates bars[];
   int n = __WBX_LoadIntrabar(sym, child_tf, from_time, to_time, bars);
   if(n <= 0) return false;

   double level = start_level;

   for(int i = 0; i < n; ++i)
   {
      const datetime bar_event_time = __WBX_StableChildIntrabarTime(child_tf, bars[i].time);
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

inline bool __WBX_FindFirstRangeTouchIntrabarTime(const string          sym,
                                                  const ENUM_TIMEFRAMES parent_tf,
                                                  const ENUM_TIMEFRAMES child_tf,
                                                  const datetime        parent_open_time,
                                                  const double          price_a,
                                                  const double          price_b,
                                                  datetime              &event_time)
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
   if(!__WBX_BuildIntrabarSearchWindow(parent_tf, parent_open_time, from_time, to_time))
      return false;

   MqlRates bars[];
   int n = __WBX_LoadIntrabar(sym, child_tf, from_time, to_time, bars);
   if(n <= 0) return false;

   const double eps = (2.0 * _Point);

   for(int i = 0; i < n; ++i)
   {
      if(bars[i].low <= (top + eps) && bars[i].high >= (bottom - eps))
      {
         event_time = __WBX_StableChildIntrabarTime(child_tf, bars[i].time);
         return (event_time > 0);
      }
   }

   return false;
}

// ============================================================================
// Generic master helpers
// ============================================================================

inline string __WBX_BaseByChild(const string          sym,
                                const ENUM_TIMEFRAMES child_tf)
{
   if(child_tf == PERIOD_M1)
      return __WB1_Base(sym);
   return __WB15_Base(sym);
}

inline string __WBX_KeyByChild(const string          sym,
                               const ENUM_TIMEFRAMES child_tf,
                               const string          suffix)
{
   if(child_tf == PERIOD_M1)
      return __WB1_Key(sym, suffix);
   return __WB15_Key(sym, suffix);
}

inline string __WBX_KeyTByChild(const string          sym,
                                const ENUM_TIMEFRAMES child_tf,
                                const int             seq)
{
   if(child_tf == PERIOD_M1)
      return __WB1_KeyT(sym, seq);
   return __WB15_KeyT(sym, seq);
}

inline string __WBX_KeyCByChild(const string          sym,
                                const ENUM_TIMEFRAMES child_tf,
                                const int             seq)
{
   if(child_tf == PERIOD_M1)
      return __WB1_KeyC(sym, seq);
   return __WB15_KeyC(sym, seq);
}

inline void __WBX_MasterBegin(const string          sym,
                              const ENUM_TIMEFRAMES parent_tf,
                              const ENUM_TIMEFRAMES child_tf)
{
   if((ENUM_TIMEFRAMES)Period() != parent_tf) return;

   const string base = __WBX_BaseByChild(sym, child_tf);

   const int total = GlobalVariablesTotal();
   for(int i = total - 1; i >= 0; --i)
   {
      const string name = GlobalVariableName(i);
      if(StringFind(name, base + "_") == 0)
         GlobalVariableDel(name);
   }

   const double run_id = (double)TimeCurrent();
   GlobalVariableSet(__WBX_KeyByChild(sym, child_tf, "RUN"), run_id);
   GlobalVariableSet(__WBX_KeyByChild(sym, child_tf, "SEQ"), 0.0);
   GlobalVariableSet(__WBX_KeyByChild(sym, child_tf, "SCAN_DONE"), 0.0);
}

inline void __WBX_MasterMarkScanDone(const string          sym,
                                     const ENUM_TIMEFRAMES parent_tf,
                                     const ENUM_TIMEFRAMES child_tf)
{
   if((ENUM_TIMEFRAMES)Period() != parent_tf) return;

   const string key = __WBX_KeyByChild(sym, child_tf, "SCAN_DONE");
   GlobalVariableSet(key, 1.0);
}

inline bool __WBX_MasterIsReadyForChild(const string          sym,
                                        const ENUM_TIMEFRAMES child_tf)
{
   const string kRun  = __WBX_KeyByChild(sym, child_tf, "RUN");
   const string kSeq  = __WBX_KeyByChild(sym, child_tf, "SEQ");
   const string kDone = __WBX_KeyByChild(sym, child_tf, "SCAN_DONE");

   if(!GlobalVariableCheck(kRun) || !GlobalVariableCheck(kSeq) || !GlobalVariableCheck(kDone))
      return false;

   if(GlobalVariableGet(kRun) <= 0.0)
      return false;

   return (GlobalVariableGet(kDone) > 0.5);
}

inline void __WBX_MasterPushEvent(const string          sym,
                                  const ENUM_TIMEFRAMES parent_tf,
                                  const ENUM_TIMEFRAMES child_tf,
                                  const int             kind,
                                  const int             ns,
                                  const Direction       dir,
                                  const datetime        t)
{
   if((ENUM_TIMEFRAMES)Period() != parent_tf) return;
   if(t <= 0) return;

   if(Markers_IsPreviewMode() && ns != WB15_NS_MIN)
      return;

   const string base = __WBX_BaseByChild(sym, child_tf);
   const string kDed = base + "_DED_"
                     + IntegerToString(kind) + "_"
                     + IntegerToString(ns) + "_"
                     + IntegerToString(__WB15_DirCode(dir)) + "_"
                     + IntegerToString((int)t);

   if(GlobalVariableCheck(kDed))
      return;
   GlobalVariableSet(kDed, 1.0);

   const string kSeq = __WBX_KeyByChild(sym, child_tf, "SEQ");
   int seq = 0;
   if(GlobalVariableCheck(kSeq))
      seq = (int)GlobalVariableGet(kSeq);

   seq++;
   GlobalVariableSet(kSeq, (double)seq);

   const int code = kind * 100 + ns * 10 + __WB15_DirCode(dir);
   GlobalVariableSet(__WBX_KeyTByChild(sym, child_tf, seq), (double)t);
   GlobalVariableSet(__WBX_KeyCByChild(sym, child_tf, seq), (double)code);
}

inline void WB15_MasterBegin(const string sym)
{
   __WBX_MasterBegin(sym, PERIOD_H4, PERIOD_M15);
}

inline void WB1_MasterBegin(const string sym)
{
   __WBX_MasterBegin(sym, PERIOD_M15, PERIOD_M1);
}

inline void WB15_MasterMarkScanDone(const string sym)
{
   __WBX_MasterMarkScanDone(sym, PERIOD_H4, PERIOD_M15);
}

inline void WB1_MasterMarkScanDone(const string sym)
{
   __WBX_MasterMarkScanDone(sym, PERIOD_M15, PERIOD_M1);
}

inline bool WB15_MasterIsReadyForChild(const string sym)
{
   return __WBX_MasterIsReadyForChild(sym, PERIOD_M15);
}

inline bool WB1_MasterIsReadyForChild(const string sym)
{
   return __WBX_MasterIsReadyForChild(sym, PERIOD_M1);
}

inline void WB15_MasterPushEvent(const string sym,
                                 const int kind,
                                 const int ns,
                                 const Direction dir,
                                 const datetime t)
{
   __WBX_MasterPushEvent(sym, PERIOD_H4, PERIOD_M15, kind, ns, dir, t);
}

inline void WB1_MasterPushEvent(const string sym,
                                const int kind,
                                const int ns,
                                const Direction dir,
                                const datetime t)
{
   __WBX_MasterPushEvent(sym, PERIOD_M15, PERIOD_M1, kind, ns, dir, t);
}

// ============================================================================
// Historical H4 -> M15 window evaluation on the M15 chart
// Used to prevent M15 -> M1 publication outside the active parent window.
// ============================================================================

inline int __WB15_CompareHistEvent(const WB15HistEvent &a,
                                   const WB15HistEvent &b)
{
   if(a.t < b.t) return -1;
   if(a.t > b.t) return 1;

   if(a.seq < b.seq) return -1;
   if(a.seq > b.seq) return 1;

   return 0;
}

inline void __WB15_SortHistEvents()
{
   int n = ArraySize(g_wb15_hist_events);
   if(n <= 1) return;

   for(int i = 0; i < n - 1; ++i)
   {
      int best = i;
      for(int j = i + 1; j < n; ++j)
      {
         if(__WB15_CompareHistEvent(g_wb15_hist_events[j],
                                    g_wb15_hist_events[best]) < 0)
            best = j;
      }

      if(best != i)
      {
         WB15HistEvent tmp = g_wb15_hist_events[i];
         g_wb15_hist_events[i] = g_wb15_hist_events[best];
         g_wb15_hist_events[best] = tmp;
      }
   }
}

inline bool __WB15_RebuildParentHistory(const string sym)
{
   if((ENUM_TIMEFRAMES)Period() != PERIOD_M15)
      return false;

   const string kRun = __WB15_Key(sym, "RUN");
   const string kSeq = __WB15_Key(sym, "SEQ");

   if(!GlobalVariableCheck(kRun) || !GlobalVariableCheck(kSeq))
      return false;

   const double run_id = GlobalVariableGet(kRun);
   const int    seq    = (int)GlobalVariableGet(kSeq);

   if(run_id <= 0.0 || seq < 0)
      return false;

   if(g_wb15_hist_run_seen == run_id && g_wb15_hist_seq_seen == seq)
      return true;

   g_wb15_hist_run_seen = run_id;
   g_wb15_hist_seq_seen = seq;

   ArrayResize(g_wb15_hist_events, 0);

   for(int i = 1; i <= seq; ++i)
   {
      const string kt = __WB15_KeyT(sym, i);
      const string kc = __WB15_KeyC(sym, i);

      if(!GlobalVariableCheck(kt) || !GlobalVariableCheck(kc))
         continue;

      const datetime t    = (datetime)GlobalVariableGet(kt);
      const int      code = (int)GlobalVariableGet(kc);
      const int      kind = code / 100;

      if(!__WB15_IsStartKind(kind) && !__WB15_IsStopKind(kind))
         continue;

      int pos = ArraySize(g_wb15_hist_events);
      ArrayResize(g_wb15_hist_events, pos + 1);

      g_wb15_hist_events[pos].t    = t;
      g_wb15_hist_events[pos].kind = kind;
      g_wb15_hist_events[pos].ns   = (code / 10) % 10;
      g_wb15_hist_events[pos].dir  = __WB15_CodeDir(code % 10);
      g_wb15_hist_events[pos].seq  = i;
   }

   __WB15_SortHistEvents();
   return true;
}

inline bool WB15_ParentWindowAlignedAt(const string    sym,
                                       const datetime  at_time,
                                       const Direction dir)
{
   if((ENUM_TIMEFRAMES)Period() != PERIOD_M15)
      return true;

   if(at_time <= 0)
      return false;

   if(!__WB15_RebuildParentHistory(sym))
      return false;

   bool      active     = false;
   Direction active_dir = DIR_UP;

   int total = ArraySize(g_wb15_hist_events);
   for(int i = 0; i < total; ++i)
   {
      WB15HistEvent evt = g_wb15_hist_events[i];
      if(evt.t > at_time)
         break;

      if(__WB15_IsStartKind(evt.kind))
      {
         active     = true;
         active_dir = evt.dir;
      }
      else if(active && evt.dir == __WB15_Opposite(active_dir))
      {
         active = false;
      }
   }

   if(!active)
      return false;

   return (active_dir == dir);
}

// ============================================================================
// Drawing helpers
// ============================================================================

inline bool __WBX_GetBarHL(const string          sym,
                           const ENUM_TIMEFRAMES child_tf,
                           const datetime        t,
                           double                &hi,
                           double                &lo)
{
   int sh = iBarShift(sym, child_tf, t, false);
   if(sh < 0) return false;

   MqlRates rr[1];
   if(CopyRates(sym, child_tf, sh, 1, rr) != 1)
      return false;

   hi = rr[0].high;
   lo = rr[0].low;
   return true;
}

inline void __WBX_DrawVLineUnique(const string   name,
                                  const datetime t,
                                  const color    col,
                                  const int      width)
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

inline void __WBX_DrawTextUnique(const string   name,
                                 const datetime t,
                                 const double   price,
                                 const string   text,
                                 const color    col,
                                 const int      font_size)
{
   if(!InpDrawMarkers) return;
   if(ObjectFind(0, name) != -1) return;
   if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, price)) return;

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

inline void __WBX_DrawSignalMarker(const string          obj_prefix,
                                   const string          parent_label,
                                   const string          sym,
                                   const ENUM_TIMEFRAMES child_tf,
                                   const double          run_id,
                                   const int             evt_seq,
                                   const datetime        t,
                                   const bool            is_on,
                                   const Direction       dir,
                                   const int             kind,
                                   const int             ns)
{
   double hi = 0.0;
   double lo = 0.0;

   if(!__WBX_GetBarHL(sym, child_tf, t, hi, lo))
   {
      string vname = obj_prefix + "_V_" + DoubleToString(run_id, 0) + "_"
                   + IntegerToString(evt_seq) + (is_on ? "_ON" : "_OFF");
      __WBX_DrawVLineUnique(vname, t, clrRed, 2);
      return;
   }

   double span = hi - lo;
   if(span <= 0.0) span = 10.0 * _Point;

   double pad = span * 0.60;
   if(pad < 8.0 * _Point) pad = 8.0 * _Point;

   double y = (dir == DIR_UP ? hi + pad : lo - pad);

   string tag   = DoubleToString(run_id, 0) + "_" + IntegerToString(evt_seq);
   string vname = obj_prefix + "_SIG_" + tag + (is_on ? "_ON" : "_OFF");

   __WBX_DrawVLineUnique(vname, t, clrRed, 2);

   if(is_on)
   {
      string hname = vname + "_TXT_H";
      string tname = vname + "_TXT_T";

      __WBX_DrawTextUnique(hname, t, y, parent_label + " Signal on", clrBlue, 10);

      double gap = pad * 0.30;
      if(gap < 10.0 * _Point) gap = 10.0 * _Point;

      __WBX_DrawTextUnique(tname,
                           t,
                           y - gap,
                           __WB15_StartTypeText(kind, ns, dir),
                           clrBlue,
                           9);
   }
   else
   {
      string tname = vname + "_TXT";
      __WBX_DrawTextUnique(tname, t, y, parent_label + " Signal off", clrBlue, 10);
   }
}

// Legacy compatibility wrappers kept for M15 overlay/object cleanup.
inline bool __WB15_GetBarHL(const string sym, const datetime t, double &hi, double &lo)
{
   return __WBX_GetBarHL(sym, PERIOD_M15, t, hi, lo);
}

inline bool __WB15_ResolveM15BarTime(const string sym, const datetime t, datetime &bar_time)
{
   return __WBX_ResolveChildBarTime(sym, PERIOD_M15, t, bar_time);
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

inline bool __WB15_CountsEnabled()
{
   return false;
}

// ============================================================================
// Local worker routing helpers
// ============================================================================

inline void __WBX_RecordLocalExactIfWorker(const string    sym,
                                           const int       kind,
                                           const int       ns,
                                           const Direction dir,
                                           const datetime  bar_time)
{
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Period();
   if(tf != PERIOD_M1 && tf != PERIOD_M15)
      return;

   TriggerM15SignalGate_RecordExact(sym, kind, ns, dir, bar_time);
}

inline void __WBX_RecordLocalCloseIfWorker(const string    sym,
                                           const int       kind,
                                           const int       ns,
                                           const Direction dir,
                                           const datetime  bar_open_time)
{
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Period();
   if(tf != PERIOD_M1 && tf != PERIOD_M15)
      return;

   TriggerM15SignalGate_RecordClose(sym, kind, ns, dir, bar_open_time);
}

// ============================================================================
// Convenience wrappers (called from signal detection points)
// ============================================================================

// START (EXACT FORMATION MOMENT): HWX
inline void WB15_PublishStartHWX(const string sym,
                                 const Direction dir,
                                 const datetime parent_open_time,
                                 const double level)
{
   const int ns = __WB15_NS_FromMarkers();
   if(ns == WB15_NS_NONE) return;

   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Period();

   if(tf == PERIOD_H4)
   {
      datetime te = 0;
      if(!__WBX_FindFirstHWXIntrabarTime(sym, PERIOD_H4, PERIOD_M15, dir, parent_open_time, level, te))
         te = __WBX_FallbackIntrabarTime(sym, PERIOD_M15, parent_open_time);

      if(te > 0)
         WB15_MasterPushEvent(sym, WB15_KIND_START_HWX, ns, dir, te);
      return;
   }

   if(tf == PERIOD_M15)
   {
      datetime te = 0;
      if(!__WBX_FindFirstHWXIntrabarTime(sym, PERIOD_M15, PERIOD_M1, dir, parent_open_time, level, te))
         te = __WBX_FallbackIntrabarTime(sym, PERIOD_M1, parent_open_time);

      if(te <= 0) return;
      if(!WB15_ParentWindowAlignedAt(sym, te, dir)) return;

      WB1_MasterPushEvent(sym, WB15_KIND_START_HWX, ns, dir, te);
      return;
   }

   if(tf == PERIOD_M1)
      __WBX_RecordLocalExactIfWorker(sym, WB15_KIND_START_HWX, ns, dir, parent_open_time);
}

// Legacy fallback overload
inline void WB15_PublishStartHWX(const string sym,
                                 const Direction dir,
                                 const datetime t)
{
   const int ns = __WB15_NS_FromMarkers();
   if(ns == WB15_NS_NONE) return;

   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Period();

   if(tf == PERIOD_H4)
   {
      WB15_MasterPushEvent(sym, WB15_KIND_START_HWX, ns, dir, t);
      return;
   }

   if(tf == PERIOD_M15)
   {
      if(!WB15_ParentWindowAlignedAt(sym, t, dir)) return;
      WB1_MasterPushEvent(sym, WB15_KIND_START_HWX, ns, dir, t);
      return;
   }

   if(tf == PERIOD_M1)
      __WBX_RecordLocalExactIfWorker(sym, WB15_KIND_START_HWX, ns, dir, t);
}

// START (EXACT FORMATION MOMENT): HWBB
inline void WB15_PublishStartHWBB(const string sym,
                                  const Direction dir,
                                  const datetime parent_open_time,
                                  const double start_level,
                                  const datetime seed_parent_open_time)
{
   const int ns = __WB15_NS_FromMarkers();
   if(ns == WB15_NS_NONE) return;

   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Period();

   if(tf == PERIOD_H4)
   {
      datetime te = 0;
      if(!__WBX_FindFirstHWBBIntrabarTime(sym,
                                          PERIOD_H4,
                                          PERIOD_M15,
                                          dir,
                                          parent_open_time,
                                          start_level,
                                          seed_parent_open_time,
                                          te))
      {
         te = __WBX_FallbackIntrabarTime(sym, PERIOD_M15, parent_open_time);
      }

      if(te > 0)
         WB15_MasterPushEvent(sym, WB15_KIND_START_HWBB, ns, dir, te);
      return;
   }

   if(tf == PERIOD_M15)
   {
      datetime te = 0;
      if(!__WBX_FindFirstHWBBIntrabarTime(sym,
                                          PERIOD_M15,
                                          PERIOD_M1,
                                          dir,
                                          parent_open_time,
                                          start_level,
                                          seed_parent_open_time,
                                          te))
      {
         te = __WBX_FallbackIntrabarTime(sym, PERIOD_M1, parent_open_time);
      }

      if(te <= 0) return;
      if(!WB15_ParentWindowAlignedAt(sym, te, dir)) return;

      WB1_MasterPushEvent(sym, WB15_KIND_START_HWBB, ns, dir, te);
      return;
   }

   if(tf == PERIOD_M1)
      __WBX_RecordLocalExactIfWorker(sym, WB15_KIND_START_HWBB, ns, dir, parent_open_time);
}

// Legacy fallback overload
inline void WB15_PublishStartHWBB(const string sym,
                                  const Direction dir,
                                  const datetime t)
{
   const int ns = __WB15_NS_FromMarkers();
   if(ns == WB15_NS_NONE) return;

   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Period();

   if(tf == PERIOD_H4)
   {
      const datetime te = __WBX_CloseBasedEventTimeOrZero(PERIOD_H4, t);
      if(te > 0)
         WB15_MasterPushEvent(sym, WB15_KIND_START_HWBB, ns, dir, te);
      return;
   }

   if(tf == PERIOD_M15)
   {
      const datetime te = __WBX_CloseBasedEventTimeOrZero(PERIOD_M15, t);
      if(te <= 0) return;
      if(!WB15_ParentWindowAlignedAt(sym, te, dir)) return;

      WB1_MasterPushEvent(sym, WB15_KIND_START_HWBB, ns, dir, te);
      return;
   }

   if(tf == PERIOD_M1)
      __WBX_RecordLocalCloseIfWorker(sym, WB15_KIND_START_HWBB, ns, dir, t);
}

// START (ON PARENT CLOSE): FSMS
// NOTE: legacy function name is kept to avoid touching the wider codebase.
inline void WB15_PublishStartFSMS_MAJONLY(const string sym,
                                          const Direction dir,
                                          const datetime parent_open_time)
{
   const int ns = __WB15_NS_FromMarkers();
   if(ns == WB15_NS_NONE) return;

   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Period();

   if(tf == PERIOD_H4)
   {
      const datetime te = __WBX_CloseBasedEventTimeOrZero(PERIOD_H4, parent_open_time);
      if(te > 0)
         WB15_MasterPushEvent(sym, WB15_KIND_START_FSMS, ns, dir, te);
      return;
   }

   if(tf == PERIOD_M15)
   {
      const datetime te = __WBX_CloseBasedEventTimeOrZero(PERIOD_M15, parent_open_time);
      if(te <= 0) return;
      if(!WB15_ParentWindowAlignedAt(sym, te, dir)) return;

      WB1_MasterPushEvent(sym, WB15_KIND_START_FSMS, ns, dir, te);
      return;
   }

   if(tf == PERIOD_M1)
      __WBX_RecordLocalCloseIfWorker(sym, WB15_KIND_START_FSMS, ns, dir, parent_open_time);
}

// START (EXACT FORMATION MOMENT): GOOZBAGHALI
inline void WB15_PublishStartGooz(const string sym,
                                  const Direction dir,
                                  const datetime parent_open_time,
                                  const double price_a,
                                  const double price_b)
{
   const int ns = __WB15_NS_FromMarkers();
   if(ns == WB15_NS_NONE) return;

   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Period();

   if(tf == PERIOD_H4)
   {
      datetime te = 0;
      if(!__WBX_FindFirstRangeTouchIntrabarTime(sym,
                                                PERIOD_H4,
                                                PERIOD_M15,
                                                parent_open_time,
                                                price_a,
                                                price_b,
                                                te))
      {
         te = __WBX_FallbackIntrabarTime(sym, PERIOD_M15, parent_open_time);
      }

      if(te > 0)
         WB15_MasterPushEvent(sym, WB15_KIND_START_GOOZBAGHALI, ns, dir, te);
      return;
   }

   if(tf == PERIOD_M15)
   {
      datetime te = 0;
      if(!__WBX_FindFirstRangeTouchIntrabarTime(sym,
                                                PERIOD_M15,
                                                PERIOD_M1,
                                                parent_open_time,
                                                price_a,
                                                price_b,
                                                te))
      {
         te = __WBX_FallbackIntrabarTime(sym, PERIOD_M1, parent_open_time);
      }

      if(te <= 0) return;
      if(!WB15_ParentWindowAlignedAt(sym, te, dir)) return;

      WB1_MasterPushEvent(sym, WB15_KIND_START_GOOZBAGHALI, ns, dir, te);
      return;
   }

   if(tf == PERIOD_M1)
      __WBX_RecordLocalExactIfWorker(sym, WB15_KIND_START_GOOZBAGHALI, ns, dir, parent_open_time);
}

// Legacy fallback overload
inline void WB15_PublishStartGooz(const string sym,
                                  const Direction dir,
                                  const datetime t)
{
   const int ns = __WB15_NS_FromMarkers();
   if(ns == WB15_NS_NONE) return;

   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Period();

   if(tf == PERIOD_H4)
   {
      WB15_MasterPushEvent(sym, WB15_KIND_START_GOOZBAGHALI, ns, dir, t);
      return;
   }

   if(tf == PERIOD_M15)
   {
      if(!WB15_ParentWindowAlignedAt(sym, t, dir)) return;
      WB1_MasterPushEvent(sym, WB15_KIND_START_GOOZBAGHALI, ns, dir, t);
      return;
   }

   if(tf == PERIOD_M1)
      __WBX_RecordLocalExactIfWorker(sym, WB15_KIND_START_GOOZBAGHALI, ns, dir, t);
}

// STOP (ON PARENT CLOSE): MTC
inline void WB15_PublishStopMTC(const string sym,
                                const Direction dir,
                                const datetime parent_open_time)
{
   const int ns = __WB15_NS_FromMarkers();
   if(ns == WB15_NS_NONE) return;

   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Period();

   if(tf == PERIOD_H4)
   {
      const datetime te = __WBX_CloseBasedEventTimeOrZero(PERIOD_H4, parent_open_time);
      if(te > 0)
         WB15_MasterPushEvent(sym, WB15_KIND_STOP_MTC, ns, dir, te);
      return;
   }

   if(tf == PERIOD_M15)
   {
      const datetime te = __WBX_CloseBasedEventTimeOrZero(PERIOD_M15, parent_open_time);
      if(te <= 0) return;

      // M15 -> M1 stop is only meaningful if the corresponding parent-aligned
      // M15 window is currently active in the opposite direction.
      if(!WB15_ParentWindowAlignedAt(sym, te, __WB15_Opposite(dir)))
         return;

      WB1_MasterPushEvent(sym, WB15_KIND_STOP_MTC, ns, dir, te);
      return;
   }

   if(tf == PERIOD_M1)
      __WBX_RecordLocalCloseIfWorker(sym, WB15_KIND_STOP_MTC, ns, dir, parent_open_time);
}

// STOP (ON PARENT CLOSE, MAJ-only): MinorStarter
inline void WB15_PublishStopMinorStarter(const string sym,
                                         const Direction dir,
                                         const datetime parent_open_time)
{
   // Minor-world stop publication is H4-origin only.
   // M15 and M1 may still CONSUME the parent result through the bridge, but
   // they must not generate/publish any new local minor stop signals.
   if((ENUM_TIMEFRAMES)Period() != PERIOD_H4)
      return;

   const int ns = WB15_NS_MAJ;
   const datetime te = __WBX_CloseBasedEventTimeOrZero(PERIOD_H4, parent_open_time);
   if(te > 0)
      WB15_MasterPushEvent(sym, WB15_KIND_STOP_MINORSTARTER, ns, dir, te);
}

// STOP (ON PARENT CLOSE, MAJ-only): MinorOff zone
inline void WB15_PublishStopMinorOffZone_MAJONLY(const string sym,
                                                 const Direction dir,
                                                 const datetime parent_open_time)
{
   if(Markers_GetNamespace() != "MAJ")
      return;

   // MinorOff-zone publication is H4-origin only.
   if((ENUM_TIMEFRAMES)Period() != PERIOD_H4)
      return;

   const int ns = WB15_NS_MAJ;
   const datetime te = __WBX_CloseBasedEventTimeOrZero(PERIOD_H4, parent_open_time);
   if(te > 0)
      WB15_MasterPushEvent(sym, WB15_KIND_STOP_MINOROFF_ZONE, ns, dir, te);
}

// ============================================================================
// Slave-side helpers
// ============================================================================

inline void __WBX_ClearActiveState(WB15ActiveState &st)
{
   st.active              = false;
   st.start_kind          = 0;
   st.start_ns            = WB15_NS_NONE;
   st.start_dir           = DIR_UP;
   st.start_time          = 0;
   st.start_evt_seq       = 0;
   st.run_id              = 0.0;
   st.start_bar_time      = 0;
   st.last_count_bar_time = 0;
   st.count               = 0;
}

inline bool __WBX_ShouldStop(const WB15ActiveState &st,
                             const int             stop_kind,
                             const int             stop_ns,
                             const Direction       stop_dir)
{
   if(!st.active) return false;
   if(!__WB15_IsStopKind(stop_kind)) return false;
   if(stop_ns < WB15_NS_NONE) return false;

   if(stop_dir != __WB15_Opposite(st.start_dir))
      return false;

   return true;
}

inline void WB15_SlaveInit()
{
   __WB15_DeleteAllCountLabels();
   g_wb15_processed_seq = 0;
   g_wb15_run_seen      = 0.0;
   __WBX_ClearActiveState(g_wb15_state);
}

inline void WB1_SlaveInit()
{
   g_wb1_processed_seq = 0;
   g_wb1_run_seen      = 0.0;
   __WBX_ClearActiveState(g_wb1_state);
}

inline void __WBX_HandleSlaveStart(const string          obj_prefix,
                                   const string          parent_label,
                                   const string          sym,
                                   const ENUM_TIMEFRAMES child_tf,
                                   const double          run_id,
                                   const int             evt_seq,
                                   const datetime        t,
                                   const int             kind,
                                   const int             ns,
                                   const Direction       dir,
                                   WB15ActiveState       &st)
{
   datetime on_bar_time = 0;
   if(!__WBX_ResolveChildBarTime(sym, child_tf, t, on_bar_time))
      on_bar_time = t;

   st.active         = true;
   st.start_kind     = kind;
   st.start_ns       = ns;
   st.start_dir      = dir;
   st.start_time     = t;
   st.start_evt_seq  = evt_seq;
   st.run_id         = run_id;
   st.start_bar_time = on_bar_time;

   __WBX_DrawSignalMarker(obj_prefix,
                          parent_label,
                          sym,
                          child_tf,
                          run_id,
                          evt_seq,
                          t,
                          true,
                          dir,
                          kind,
                          ns);
}

inline void __WBX_HandleSlaveStop(const string          obj_prefix,
                                  const string          parent_label,
                                  const string          sym,
                                  const ENUM_TIMEFRAMES child_tf,
                                  const double          run_id,
                                  const int             evt_seq,
                                  const datetime        t,
                                  WB15ActiveState       &st)
{
   __WBX_DrawSignalMarker(obj_prefix,
                          parent_label,
                          sym,
                          child_tf,
                          run_id,
                          evt_seq,
                          t,
                          false,
                          st.start_dir,
                          0,
                          0);

   __WBX_ClearActiveState(st);
   st.run_id = run_id;
}

inline void WB15_Slave_OnTimer(const string sym)
{
   if(!__WB15_IsSlave()) return;

   const string kRun = __WB15_Key(sym, "RUN");
   const string kSeq = __WB15_Key(sym, "SEQ");
   const string kPrc = __WB15_Key(sym, "SLVSEQ");
   const string kRsv = __WB15_Key(sym, "SLVRUN");

   if(!GlobalVariableCheck(kRun) || !GlobalVariableCheck(kSeq))
      return;

   const double run_id = GlobalVariableGet(kRun);
   if(run_id <= 0.0) return;

   double last_run = 0.0;
   if(GlobalVariableCheck(kRsv))
      last_run = GlobalVariableGet(kRsv);

   if(last_run != run_id)
   {
      WB15_SlaveInit();
      g_wb15_run_seen = run_id;
      GlobalVariableSet(kRsv, run_id);
      GlobalVariableSet(kPrc, 0.0);
   }

   int processed = 0;
   if(GlobalVariableCheck(kPrc))
      processed = (int)GlobalVariableGet(kPrc);

   int seq = (int)GlobalVariableGet(kSeq);

   if(seq > processed)
   {
      for(int i = processed + 1; i <= seq; ++i)
      {
         const string kt = __WB15_KeyT(sym, i);
         const string kc = __WB15_KeyC(sym, i);

         if(!GlobalVariableCheck(kt) || !GlobalVariableCheck(kc))
            continue;

         const datetime t    = (datetime)GlobalVariableGet(kt);
         const int      code = (int)GlobalVariableGet(kc);

         const int      kind = code / 100;
         const int      ns   = (code / 10) % 10;
         const Direction dir = __WB15_CodeDir(code % 10);

         if(__WB15_IsStartKind(kind))
         {
            __WBX_HandleSlaveStart("WB15",
                                   "H4",
                                   sym,
                                   PERIOD_M15,
                                   run_id,
                                   i,
                                   t,
                                   kind,
                                   ns,
                                   dir,
                                   g_wb15_state);
         }
         else if(__WB15_IsStopKind(kind))
         {
            if(__WBX_ShouldStop(g_wb15_state, kind, ns, dir))
            {
               // Parent priority cascade:
               // if H4 closes the active M15 window, close every active M1 window too.
               if(__WB1_IsMaster())
                  WB1_MasterPushEvent(sym, kind, WB15_NS_MAJ, dir, t);

               __WBX_HandleSlaveStop("WB15",
                                     "H4",
                                     sym,
                                     PERIOD_M15,
                                     run_id,
                                     i,
                                     t,
                                     g_wb15_state);
            }
         }
      }

      GlobalVariableSet(kPrc, (double)seq);
   }
}

inline void WB1_Slave_OnTimer(const string sym)
{
   if(!__WB1_IsSlave()) return;

   const string kRun = __WB1_Key(sym, "RUN");
   const string kSeq = __WB1_Key(sym, "SEQ");
   const string kPrc = __WB1_Key(sym, "SLVSEQ");
   const string kRsv = __WB1_Key(sym, "SLVRUN");

   if(!GlobalVariableCheck(kRun) || !GlobalVariableCheck(kSeq))
      return;

   const double run_id = GlobalVariableGet(kRun);
   if(run_id <= 0.0) return;

   double last_run = 0.0;
   if(GlobalVariableCheck(kRsv))
      last_run = GlobalVariableGet(kRsv);

   if(last_run != run_id)
   {
      WB1_SlaveInit();
      g_wb1_run_seen = run_id;
      GlobalVariableSet(kRsv, run_id);
      GlobalVariableSet(kPrc, 0.0);
   }

   int processed = 0;
   if(GlobalVariableCheck(kPrc))
      processed = (int)GlobalVariableGet(kPrc);

   int seq = (int)GlobalVariableGet(kSeq);

   if(seq > processed)
   {
      for(int i = processed + 1; i <= seq; ++i)
      {
         const string kt = __WB1_KeyT(sym, i);
         const string kc = __WB1_KeyC(sym, i);

         if(!GlobalVariableCheck(kt) || !GlobalVariableCheck(kc))
            continue;

         const datetime t    = (datetime)GlobalVariableGet(kt);
         const int      code = (int)GlobalVariableGet(kc);

         const int      kind = code / 100;
         const int      ns   = (code / 10) % 10;
         const Direction dir = __WB15_CodeDir(code % 10);

         if(__WB15_IsStartKind(kind))
         {
            __WBX_HandleSlaveStart("WB1",
                                   "M15",
                                   sym,
                                   PERIOD_M1,
                                   run_id,
                                   i,
                                   t,
                                   kind,
                                   ns,
                                   dir,
                                   g_wb1_state);
         }
         else if(__WB15_IsStopKind(kind))
         {
            if(__WBX_ShouldStop(g_wb1_state, kind, ns, dir))
            {
               __WBX_HandleSlaveStop("WB1",
                                     "M15",
                                     sym,
                                     PERIOD_M1,
                                     run_id,
                                     i,
                                     t,
                                     g_wb1_state);
            }
         }
      }

      GlobalVariableSet(kPrc, (double)seq);
   }
}

#endif // WAVEBOT_WB15_SIGNAL_BRIDGE_MQH