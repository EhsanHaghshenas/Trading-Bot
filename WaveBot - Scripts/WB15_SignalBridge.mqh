#ifndef WAVEBOT_WB15_SIGNAL_BRIDGE_MQH
#define WAVEBOT_WB15_SIGNAL_BRIDGE_MQH

// ============================================================================
// WB15_SignalBridge.mqh
// Simple live bridge H4 -> M15 using Terminal Global Variables.
// H4 publishes START/STOP signals; M15 draws ON/OFF markers and counts candles.
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
   WB15_KIND_STOP_MINORSTARTER  = 11
};

// ---- Internal state (M15) ----
struct WB15ActiveState
{
   bool     active;
   int      start_kind;
   int      start_ns;
   Direction start_dir;
   datetime start_time;
   int      start_evt_seq;
   double   run_id;
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
inline void WB15_PublishStartHWX(const string sym, const Direction dir, const datetime t)
{
   WB15_MasterPushEvent(sym, WB15_KIND_START_HWX, __WB15_NS_FromMarkers(), dir, t);
}
inline void WB15_PublishStartHWBB(const string sym, const Direction dir, const datetime t)
{
   WB15_MasterPushEvent(sym, WB15_KIND_START_HWBB, __WB15_NS_FromMarkers(), dir, t);
}
inline void WB15_PublishStartFSMS_MAJONLY(const string sym, const Direction dir, const datetime t)
{
   // FSMS as a start trigger is MAJ-only by definition
   if(Markers_GetNamespace() != "MAJ") return;
   WB15_MasterPushEvent(sym, WB15_KIND_START_FSMS, WB15_NS_MAJ, dir, t);
}
inline void WB15_PublishStartGooz(const string sym, const Direction dir, const datetime t)
{
   WB15_MasterPushEvent(sym, WB15_KIND_START_GOOZBAGHALI, __WB15_NS_FromMarkers(), dir, t);
}
inline void WB15_PublishStopMTC(const string sym, const Direction dir, const datetime t)
{
   WB15_MasterPushEvent(sym, WB15_KIND_STOP_MTC, __WB15_NS_FromMarkers(), dir, t);
}
inline void WB15_PublishStopMinorStarter(const string sym, const Direction dir, const datetime t)
{
   WB15_MasterPushEvent(sym, WB15_KIND_STOP_MINORSTARTER, WB15_NS_MAJ, dir, t);
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
                                   const Direction dir)
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
   double pad = span * 0.25;
   if(pad < 3.0 * _Point) pad = 3.0 * _Point;

   double y = (dir == DIR_UP ? hi + pad : lo - pad);

   string tag = DoubleToString(run_id, 0) + "_" + IntegerToString(evt_seq);
   string vname = "WB15_SIG_" + tag + (is_on?"_ON":"_OFF");
   string tname = vname + "_TXT";
   __WB15_DrawVLineUnique(vname, t, clrRed, 3);
   __WB15_DrawTextUnique(tname, t, y, (is_on ? "4H Signal on" : "4H Signal off"), clrBlue, 10);
}

inline void __WB15_DrawCountSequence(const string sym,
                                    const double run_id,
                                    const int start_evt_seq,
                                    const datetime from_t,
                                    const datetime to_t,
                                    const Direction dir)
{
   if(to_t < from_t) return;

   MqlRates rr[];
   ArraySetAsSeries(rr, false);
   int got = CopyRates(sym, PERIOD_M15, from_t, to_t, rr);
   if(got <= 0) return;

   for(int i = 0; i < got; ++i)
   {
      const datetime bt = rr[i].time;
      if(bt < from_t || bt > to_t) continue;

      double hi = rr[i].high;
      double lo = rr[i].low;
      double span = hi - lo;
      if(span <= 0.0) span = 10.0 * _Point;
      double pad = span * 0.25;
      if(pad < 3.0 * _Point) pad = 3.0 * _Point;

      double y = (dir == DIR_UP ? hi + pad : lo - pad);
      int num = i + 1;

      string name = "WB15_CNT_" + DoubleToString(run_id, 0) + "_" + IntegerToString(start_evt_seq) + "_" + IntegerToString(num);
      __WB15_DrawTextUnique(name, bt, y, IntegerToString(num), clrAqua, 8);
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
   return (kind == WB15_KIND_STOP_MTC || kind == WB15_KIND_STOP_MINORSTARTER);
}

inline bool __WB15_ShouldStop(const WB15ActiveState &st, const int stop_kind, const int stop_ns, const Direction stop_dir)
{
   if(!st.active) return false;
   if(stop_dir != __WB15_Opposite(st.start_dir)) return false;

   // FSMS sessions are stopped by MinorStarter only
   if(st.start_kind == WB15_KIND_START_FSMS)
   {
      return (stop_kind == WB15_KIND_STOP_MINORSTARTER);
   }

   // HWX/HWBB/GOOZ sessions are stopped by MTC
   if(stop_kind != WB15_KIND_STOP_MTC) return false;

   if(st.start_ns == WB15_NS_MAJ)
      return (stop_ns == WB15_NS_MAJ);
   if(st.start_ns == WB15_NS_MIN)
      return (stop_ns == WB15_NS_MIN || stop_ns == WB15_NS_MAJ); // cross-stop allowed

   return false;
}

inline void WB15_SlaveInit()
{
   g_wb15_processed_seq = 0;
   g_wb15_run_seen      = 0.0;
   g_wb15_state.active  = false;
   g_wb15_state.start_kind = 0;
   g_wb15_state.start_ns   = 0;
   g_wb15_state.start_dir  = DIR_UP;
   g_wb15_state.start_time = 0;
   g_wb15_state.start_evt_seq = 0;
   g_wb15_state.run_id = 0.0;
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
   if(seq <= processed) return;

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
         if(!g_wb15_state.active)
         {
            g_wb15_state.active = true;
            g_wb15_state.start_kind = kind;
            g_wb15_state.start_ns   = ns;
            g_wb15_state.start_dir  = dir;
            g_wb15_state.start_time = t;
            g_wb15_state.start_evt_seq = i;
            g_wb15_state.run_id = run_id;

            __WB15_DrawSignalMarker(sym, run_id, i, t, true, dir);
         }
      }
      else if(__WB15_IsStopKind(kind))
      {
         if(__WB15_ShouldStop(g_wb15_state, kind, ns, dir))
         {
            __WB15_DrawSignalMarker(sym, run_id, i, t, false, g_wb15_state.start_dir);

            // Count & label candles on M15 between start and stop (inclusive)
            __WB15_DrawCountSequence(sym, run_id, g_wb15_state.start_evt_seq,
                                    g_wb15_state.start_time, t, g_wb15_state.start_dir);

            g_wb15_state.active = false;
         }
      }
   }

   GlobalVariableSet(kPrc, (double)seq);
}

#endif // WAVEBOT_WB15_SIGNAL_BRIDGE_MQH
