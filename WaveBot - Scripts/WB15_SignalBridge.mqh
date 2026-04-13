#ifndef WAVEBOT_WB15_SIGNAL_BRIDGE_MQH
#define WAVEBOT_WB15_SIGNAL_BRIDGE_MQH

// ============================================================================
// WB15_SignalBridge.mqh
// Simple live bridge H4 -> M15 using Terminal Global Variables.
// H4 publishes START/STOP signals; M15 draws ON/OFF markers as an overlay.
// ============================================================================

// NOTE: This module is intentionally standalone (no extra includes).

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

// ---- Internal state (M15) ----
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
   // Candle numbering is enabled on the M15 chart.
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
   return ((ENUM_TIMEFRAMES)Period() == PERIOD_H4);
}

inline bool __WB15_IsSlave()
{
   return ((ENUM_TIMEFRAMES)Period() == PERIOD_M15);
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
// SLAVE (M15): display helpers (signal type text)
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
}

inline void WB15_MasterPushEvent(const string sym,
                                const int kind,
                                const int ns,
                                const Direction dir,
                                const datetime t)
{
   if(!__WB15_IsMaster()) return;
   if(t <= 0) return;

   // MIN world is executed by WorldManager in preview mode.
   // We still must publish bridge events there, otherwise M15 never sees
   // MIN-origin 4H signal on/off windows in real time.
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
}

// Convenience wrappers (called from signal detection points)

// --------------------------------------------------------------------------
// Time-mapping rule (H4 -> M15):
//  - HWX / HWBB / GOOZBAGHALI:
//      publish on the FIRST M15 candle inside the H4 bar where the event
//      really forms. The published timestamp is a stable point INSIDE that
//      M15 candle (bar_open + 1 second), so the slave resolves the same
//      live candle deterministically.
//  - FSMS / MTC / MinorStarter / MinorOff-zone:
//      publish ONLY after the H4 candle closes,
//      and their timestamp is the H4 CLOSE time (open time of next H4 bar).
// --------------------------------------------------------------------------

inline datetime __WB15_H4_CloseTime(const datetime h4_open_time)
{
   if(h4_open_time <= 0) return 0;

   int sec = PeriodSeconds(PERIOD_H4);
   if(sec <= 0) sec = 14400; // safety fallback: 4H = 14400 seconds

   return (h4_open_time + (datetime)sec);
}

inline datetime __WB15_CloseBasedEventTimeOrZero(const datetime h4_open_time)
{
   const datetime close_time = __WB15_H4_CloseTime(h4_open_time);
   if(close_time <= 0) return 0;

   // Wait for candle close (prevents early display on M15)
   if(TimeCurrent() < close_time) return 0;

   return close_time;
}

inline datetime __WB15_StableM15IntrabarTime(const datetime m15_bar_open_time)
{
   if(m15_bar_open_time <= 0) return 0;

   int sec = PeriodSeconds(PERIOD_M15);
   if(sec <= 0) sec = 900; // safety fallback: 15M = 900 seconds

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

   int copied = CopyRates(sym, PERIOD_M15, from_time, to_time, bars);
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

   // If HWBB happens inside the very same H4 bar as the seed Hunter,
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

// START (EXACT FORMATION MOMENT): HWX
inline void WB15_PublishStartHWX(const string sym,
                                 const Direction dir,
                                 const datetime h4_open_time,
                                 const double level)
{
   const int ns = __WB15_NS_FromMarkers();
   if(ns != WB15_NS_NONE)
      TriggerM15SignalGate_RecordExact(sym, WB15_KIND_START_HWX, ns, dir, h4_open_time);

   datetime te = 0;
   if(!__WB15_FindFirstHWXIntrabarTime(sym, dir, h4_open_time, level, te))
      te = __WB15_StableM15IntrabarTime(h4_open_time);

   if(te <= 0) return;

   WB15_MasterPushEvent(sym, WB15_KIND_START_HWX, ns, dir, te);
}

// Legacy fallback overload (kept for compatibility)
inline void WB15_PublishStartHWX(const string sym, const Direction dir, const datetime t)
{
   const int ns = __WB15_NS_FromMarkers();
   if(ns != WB15_NS_NONE)
      TriggerM15SignalGate_RecordExact(sym, WB15_KIND_START_HWX, ns, dir, t);

   WB15_MasterPushEvent(sym, WB15_KIND_START_HWX, ns, dir, t);
}

// START (EXACT FORMATION MOMENT): HWBB
inline void WB15_PublishStartHWBB(const string sym,
                                  const Direction dir,
                                  const datetime h4_open_time,
                                  const double start_level,
                                  const datetime seed_h4_open_time)
{
   const int ns = __WB15_NS_FromMarkers();
   if(ns != WB15_NS_NONE)
      TriggerM15SignalGate_RecordExact(sym, WB15_KIND_START_HWBB, ns, dir, h4_open_time);

   datetime te = 0;
   if(!__WB15_FindFirstHWBBIntrabarTime(sym, dir, h4_open_time, start_level, seed_h4_open_time, te))
      te = __WB15_StableM15IntrabarTime(h4_open_time);

   if(te <= 0) return;

   WB15_MasterPushEvent(sym, WB15_KIND_START_HWBB, ns, dir, te);
}

// Legacy fallback overload (kept for compatibility)
inline void WB15_PublishStartHWBB(const string sym, const Direction dir, const datetime t)
{
   const int ns = __WB15_NS_FromMarkers();
   if(ns != WB15_NS_NONE)
      TriggerM15SignalGate_RecordClose(sym, WB15_KIND_START_HWBB, ns, dir, t);

   const datetime te = __WB15_CloseBasedEventTimeOrZero(t);
   if(te <= 0) return;

   WB15_MasterPushEvent(sym, WB15_KIND_START_HWBB, ns, dir, te);
}

// START (ON H4 CLOSE): FSMS
// NOTE: legacy function name is kept to avoid touching the wider codebase.
// It now publishes in BOTH MAJ and MIN namespaces, based on the active world.
inline void WB15_PublishStartFSMS_MAJONLY(const string sym, const Direction dir, const datetime t)
{
   const int ns = __WB15_NS_FromMarkers();
   if(ns == WB15_NS_NONE) return;

   TriggerM15SignalGate_RecordClose(sym, WB15_KIND_START_FSMS, ns, dir, t);

   const datetime te = __WB15_CloseBasedEventTimeOrZero(t);
   if(te <= 0) return;

   WB15_MasterPushEvent(sym, WB15_KIND_START_FSMS, ns, dir, te);
}

// START (EXACT FORMATION MOMENT): GOOZBAGHALI
inline void WB15_PublishStartGooz(const string sym,
                                  const Direction dir,
                                  const datetime h4_open_time,
                                  const double price_a,
                                  const double price_b)
{
   const int ns = __WB15_NS_FromMarkers();
   if(ns != WB15_NS_NONE)
      TriggerM15SignalGate_RecordExact(sym, WB15_KIND_START_GOOZBAGHALI, ns, dir, h4_open_time);

   datetime te = 0;
   if(!__WB15_FindFirstRangeTouchIntrabarTime(sym, h4_open_time, price_a, price_b, te))
      te = __WB15_StableM15IntrabarTime(h4_open_time);

   if(te <= 0) return;

   WB15_MasterPushEvent(sym, WB15_KIND_START_GOOZBAGHALI, ns, dir, te);
}

// Legacy fallback overload (kept for compatibility)
inline void WB15_PublishStartGooz(const string sym, const Direction dir, const datetime t)
{
   const int ns = __WB15_NS_FromMarkers();
   if(ns != WB15_NS_NONE)
      TriggerM15SignalGate_RecordExact(sym, WB15_KIND_START_GOOZBAGHALI, ns, dir, t);

   WB15_MasterPushEvent(sym, WB15_KIND_START_GOOZBAGHALI, ns, dir, t);
}

// STOP (ON CLOSE): MTC must wait for H4 close
inline void WB15_PublishStopMTC(const string sym, const Direction dir, const datetime t)
{
   const int ns = __WB15_NS_FromMarkers();
   if(ns != WB15_NS_NONE)
      TriggerM15SignalGate_RecordClose(sym, WB15_KIND_STOP_MTC, ns, dir, t);

   const datetime te = __WB15_CloseBasedEventTimeOrZero(t);
   if(te <= 0) return;

   WB15_MasterPushEvent(sym, WB15_KIND_STOP_MTC, ns, dir, te);
}

// STOP (ON CLOSE, MAJ-only): MinorStarter must wait for H4 close
inline void WB15_PublishStopMinorStarter(const string sym, const Direction dir, const datetime t)
{
   TriggerM15SignalGate_RecordClose(sym, WB15_KIND_STOP_MINORSTARTER, WB15_NS_MAJ, dir, t);

   const datetime te = __WB15_CloseBasedEventTimeOrZero(t);
   if(te <= 0) return;

   WB15_MasterPushEvent(sym, WB15_KIND_STOP_MINORSTARTER, WB15_NS_MAJ, dir, te);
}

// STOP (ON CLOSE, MAJ-only): MinorOff zone must wait for H4 close
inline void WB15_PublishStopMinorOffZone_MAJONLY(const string sym, const Direction dir, const datetime t)
{
   // Stop trigger: MAJ MinorOff breaks C1-W2 Minorzone boundary (used to stop MIN-start M15 sessions)
   if(Markers_GetNamespace() != "MAJ") return;

   TriggerM15SignalGate_RecordClose(sym, WB15_KIND_STOP_MINOROFF_ZONE, WB15_NS_MAJ, dir, t);

   const datetime te = __WB15_CloseBasedEventTimeOrZero(t);
   if(te <= 0) return;

   WB15_MasterPushEvent(sym, WB15_KIND_STOP_MINOROFF_ZONE, WB15_NS_MAJ, dir, te);
}


// ============================================================================
// SLAVE (M15): drawing helpers
// ============================================================================

inline bool __WB15_GetBarHL(const string sym, const datetime t, double &hi, double &lo)
{
   int sh = iBarShift(sym, PERIOD_M15, t, false);
   if(sh < 0) return false;
   MqlRates rr[1];
   if(CopyRates(sym, PERIOD_M15, sh, 1, rr) != 1) return false;
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

   // BIGGER vertical distance from candles (for clarity on M15)
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

      __WB15_DrawTextUnique(hname, t, y, "4H Signal on", clrBlue, 10);

      // Put type line under the main label (lower price), but keep it far from candles
      double gap = pad * 0.30;
      if(gap < 10.0 * _Point) gap = 10.0 * _Point;

      double y2 = y - gap;
      __WB15_DrawTextUnique(tname, t, y2, __WB15_StartTypeText(kind, ns, dir), clrBlue, 9);
   }
   else
   {
      string tname = vname + "_TXT";
      __WB15_DrawTextUnique(tname, t, y, "4H Signal off", clrBlue, 10);
   }
}

// ============================================================================
// SLAVE (M15): live candle-by-candle numbering helpers
// (Uses the same bar-mapping logic as minor-range starter/ender numbering:
//  resolve event time -> M15 bar by iBarShift(..., false) then iTime(...))
// ============================================================================

inline bool __WB15_ResolveM15BarTime(const string sym, const datetime t, datetime &bar_time)
{
   int sh = iBarShift(sym, PERIOD_M15, t, false);
   if(sh < 0) return false;
   bar_time = iTime(sym, PERIOD_M15, sh);
   return (bar_time > 0);
}

inline int __WB15_BarShiftM15Safe(const string sym, const datetime bar_time)
{
   int sh = iBarShift(sym, PERIOD_M15, bar_time, true);
   if(sh < 0) sh = iBarShift(sym, PERIOD_M15, bar_time, false);
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
// - If until_exclusive_bar_time == 0: count forward up to the last CLOSED M15 candle.
// - If until_exclusive_bar_time  > 0: count forward, but do NOT count the candle whose open time == until_exclusive_bar_time
//   (i.e., stop before OFF candle).
inline void __WB15_LiveCountAdvance(const string sym, const datetime until_exclusive_bar_time)
{
   if(!__WB15_CountsEnabled()) return;
   if(!g_wb15_state.active) return;
   if(g_wb15_state.start_bar_time <= 0) return;

   // Only closed candles are eligible for numbering
   datetime last_closed_time = iTime(sym, PERIOD_M15, 1);
   if(last_closed_time <= 0) return;

   datetime cur = g_wb15_state.last_count_bar_time;
   if(cur <= 0) cur = g_wb15_state.start_bar_time;

   while(true)
   {
      int sh = __WB15_BarShiftM15Safe(sym, cur);
      if(sh < 0) break;

      int next_sh = sh - 1;
      if(next_sh < 1) break; // do not number current (forming) candle

      datetime next_time = iTime(sym, PERIOD_M15, next_sh);
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
      datetime bt = iTime(sym, PERIOD_M15, sh);
      if(bt <= 0) continue;

      num++;
      __WB15_DrawCountLabel(sym, run_id, start_evt_seq, bt, num, dir);
   }
}

// ============================================================================
// SLAVE (M15): match rules + OnTimer
// ============================================================================

inline bool __WB15_IsStartKind(const int kind)
{
   return (kind == WB15_KIND_START_HWX || kind == WB15_KIND_START_HWBB || kind == WB15_KIND_START_FSMS || kind == WB15_KIND_START_GOOZBAGHALI);
}

inline bool __WB15_IsStopKind(const int kind)
{
   return (kind == WB15_KIND_STOP_MTC || kind == WB15_KIND_STOP_MINORSTARTER || kind == WB15_KIND_STOP_MINOROFF_ZONE);
}

inline bool __WB15_ShouldStop(const WB15ActiveState &st, const int stop_kind, const int stop_ns, const Direction stop_dir)
{
   if(!st.active) return false;
   if(!__WB15_IsStopKind(stop_kind)) return false;

   // Simplified rule:
   //   any 4H signal off closes the current M15 trigger window,
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
   // A fresh 4H signal on simply restarts the active window from its own candle.
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

   // 1) Process new H4 events (ON/OFF markers)
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
            // Resolve ON candle open time on M15
            datetime on_bar_time = 0;
            if(!__WB15_ResolveM15BarTime(sym, t, on_bar_time))
               on_bar_time = t;

            // FSMS lifecycle mirror on M15:
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
                  // Resolve OFF candle open time on M15
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

   // 2) Keep candle numbering advancing live on M15 while the session is active.
   if(__WB15_CountsEnabled() && g_wb15_state.active)
      __WB15_LiveCountAdvance(sym, 0);
}

#endif // WAVEBOT_WB15_SIGNAL_BRIDGE_MQH
