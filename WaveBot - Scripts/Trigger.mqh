#ifndef WAVEBOT_TRIGGER_MQH
#define WAVEBOT_TRIGGER_MQH

#include <WaveBot/Types.mqh>
#include <WaveBot/Markers.mqh>
#include <WaveBot/WB15_SignalBridge.mqh>
#include <WaveBot/Flip.mqh>
#include <WaveBot/Majicflip.mqh>
#include <WaveBot/TriggerSLTP.mqh>

void TriggerStatement_OnNewTriggerAt(const datetime trigger_time);

// ============================================================================
// Trigger.mqh
//
// Current trigger architecture:
//   - Trigger Type 1 = Flip.mqh.
//     Every valid Flip candle becomes a Type-1 trigger on that same closed bar.
//   - Trigger Type 2 = Majicflip.mqh.
//     Every valid MajicFlip breaker candle becomes a Type-2 trigger on that
//     same closed bar.
//   - Both engines are evaluated on every worker M1 candle while an imported
//     M15->M1 signal window is active.
//   - Entry/breakout level is the close of the Flip/MajicFlip trigger candle.
//   - TriggerSLTP.mqh builds SL/TP from the trigger candle itself.
//   - No M1 trend-alignment check is performed here; the imported M15->M1
//     bridge window is the only activation context for trigger search.
// ============================================================================

#define TRG_MAX_ACTIVE_SESSIONS  32
#define TRG_ENGINE_TYPE1         1
#define TRG_ENGINE_TYPE2         2

struct TriggerEvent
{
   datetime  t;
   datetime  bar_time;
   Direction dir;
   int       kind;
   int       ns;
   int       seq;
};

struct TriggerStartSession
{
   bool      active;
   int       kind;
   int       ns;
   Direction dir;
   datetime  t;
   datetime  bar_time;
   int       seq;
};

struct TriggerWindowCore
{
   double        run_id;
   int           bridge_seq;

   bool          active;
   int           active_start_seq;
   int           active_start_kind;
   int           active_start_ns;
   Direction     active_dir;
   datetime      active_start_time;
   datetime      active_start_bar_time;

   datetime      last_processed_time;
   int           last_processed_idx;

   int           up_counter;
   int           dn_counter;
};

static TriggerWindowCore g_trigger_core;
static TriggerEvent      g_trigger_events[];
static string            g_trigger_symbol = "";
static datetime          g_trigger_pending_refresh_time = 0;

// Public functions implemented by Trigger_Type1.mqh / Trigger_Type2.mqh.
void Trigger_Type1_ResetGlobals();
bool Trigger_Type1_ProcessUP(const MqlRates &rates[], const int n, const int bar_idx, const datetime from_time, const datetime to_time);
bool Trigger_Type1_ProcessDOWN(const MqlRates &rates[], const int n, const int bar_idx, const datetime from_time, const datetime to_time);
void Trigger_Type2_ResetGlobals();
bool Trigger_Type2_ProcessUP(const MqlRates &rates[], const int n, const int bar_idx, const datetime from_time, const datetime to_time);
bool Trigger_Type2_ProcessDOWN(const MqlRates &rates[], const int n, const int bar_idx, const datetime from_time, const datetime to_time);

// ----------------------------------------------------------------------------
// Worker / bridge helpers
// ----------------------------------------------------------------------------
inline bool __TRG_IsWorkerTF()
{
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Period();
   return (tf == PERIOD_M1);
}

inline bool __TRG_IsMajorWorld()
{
   string ns = Markers_GetNamespace();
   return (ns == "" || ns == "MAJ");
}

inline datetime __TRG_WorkerBarOpen(const datetime t)
{
   int sec = PeriodSeconds((ENUM_TIMEFRAMES)Period());
   if(sec <= 0)
      sec = 60;

   long ts = (long)t;
   long ss = (long)sec;
   return (datetime)(ts - (ts % ss));
}

inline bool __TRG_IsStartKind(const int kind)
{
   return (kind == WB15_KIND_START_HWX ||
           kind == WB15_KIND_START_HWBB ||
           kind == WB15_KIND_START_FSMS ||
           kind == WB15_KIND_START_GOOZBAGHALI);
}

inline bool __TRG_IsStopKind(const int kind)
{
   return (kind == WB15_KIND_STOP_MTC ||
           kind == WB15_KIND_STOP_MINORSTARTER ||
           kind == WB15_KIND_STOP_MINOROFF_ZONE);
}

inline int __TRG_DecodeKind(const int code)    { return (code / 100); }
inline int __TRG_DecodeNS(const int code)      { return ((code / 10) % 10); }
inline int __TRG_DecodeDirCode(const int code) { return (code % 10); }

inline void __TRG_ClearSession(TriggerStartSession &s)
{
   s.active   = false;
   s.kind     = 0;
   s.ns       = WB15_NS_NONE;
   s.dir      = DIR_UP;
   s.t        = 0;
   s.bar_time = 0;
   s.seq      = -1;
}

inline int __TRG_CompareEvent(const TriggerEvent &a,
                              const TriggerEvent &b)
{
   if(a.bar_time < b.bar_time) return -1;
   if(a.bar_time > b.bar_time) return 1;

   if(a.t < b.t) return -1;
   if(a.t > b.t) return 1;

   if(a.seq < b.seq) return -1;
   if(a.seq > b.seq) return 1;

   return 0;
}

inline void __TRG_SortBridgeEvents()
{
   int n = ArraySize(g_trigger_events);
   if(n <= 1)
      return;

   for(int i=0; i<n-1; ++i)
   {
      int best = i;
      for(int j=i+1; j<n; ++j)
      {
         if(__TRG_CompareEvent(g_trigger_events[j], g_trigger_events[best]) < 0)
            best = j;
      }

      if(best != i)
      {
         TriggerEvent tmp = g_trigger_events[i];
         g_trigger_events[i] = g_trigger_events[best];
         g_trigger_events[best] = tmp;
      }
   }
}

inline void __TRG_ResetWindowState()
{
   Trigger_Type1_ResetGlobals();
   Trigger_Type2_ResetGlobals();
   g_trigger_core.last_processed_time = 0;
   g_trigger_core.last_processed_idx  = -1;
   g_trigger_pending_refresh_time     = 0;
}

inline void Trigger_ResetGlobals()
{
   g_trigger_core.run_id                = 0.0;
   g_trigger_core.bridge_seq            = 0;

   g_trigger_core.active                = false;
   g_trigger_core.active_start_seq      = -1;
   g_trigger_core.active_start_kind     = 0;
   g_trigger_core.active_start_ns       = WB15_NS_NONE;
   g_trigger_core.active_dir            = DIR_UP;
   g_trigger_core.active_start_time     = 0;
   g_trigger_core.active_start_bar_time = 0;

   g_trigger_core.last_processed_time   = 0;
   g_trigger_core.last_processed_idx    = -1;
   g_trigger_core.up_counter            = 0;
   g_trigger_core.dn_counter            = 0;

   g_trigger_symbol = "";
   ArrayResize(g_trigger_events, 0);
   g_trigger_pending_refresh_time = 0;

   Trigger_Type1_ResetGlobals();
   Trigger_Type2_ResetGlobals();
   TriggerSLTP_ResetGlobals();
   Flip_ResetGlobals();
   MajicFlip_ResetGlobals();
}

inline bool __TRG_SessionMatchesStop(const TriggerStartSession &sess,
                                     const int                  stop_kind,
                                     const int                  stop_ns,
                                     const Direction            stop_dir)
{
   if(!sess.active) return false;
   if(!__TRG_IsStopKind(stop_kind)) return false;

   if(stop_dir != __WB15_Opposite(sess.dir))
      return false;

   if(stop_ns < WB15_NS_NONE)
      return false;

   return true;
}

inline bool __TRG_RebuildBridgeEvents(const string sym)
{
   const string kRun = __WB15_Key(sym, "RUN");
   const string kSeq = __WB15_Key(sym, "SEQ");

   if(!GlobalVariableCheck(kRun) || !GlobalVariableCheck(kSeq))
      return false;

   const double run_id = GlobalVariableGet(kRun);
   const int    seq    = (int)GlobalVariableGet(kSeq);

   if(run_id <= 0.0 || seq < 0)
      return false;

   bool full_reset = false;
   if(g_trigger_core.run_id != run_id)
   {
      g_trigger_core.run_id = run_id;
      full_reset = true;
   }

   if(!full_reset && g_trigger_core.bridge_seq == seq)
      return true;

   g_trigger_core.bridge_seq = seq;
   ArrayResize(g_trigger_events, 0);

   for(int i=1; i<=seq; ++i)
   {
      const string kt = __WB15_KeyT(sym, i);
      const string kc = __WB15_KeyC(sym, i);

      if(!GlobalVariableCheck(kt) || !GlobalVariableCheck(kc))
         continue;

      const datetime t    = (datetime)GlobalVariableGet(kt);
      const int      code = (int)GlobalVariableGet(kc);
      const int      kind = __TRG_DecodeKind(code);

      if(!__TRG_IsStartKind(kind) && !__TRG_IsStopKind(kind))
         continue;

      TriggerEvent evt;
      evt.t        = t;
      evt.bar_time = __TRG_WorkerBarOpen(t);
      evt.kind     = kind;
      evt.ns       = __TRG_DecodeNS(code);
      evt.dir      = __WB15_CodeDir(__TRG_DecodeDirCode(code));
      evt.seq      = i;

      int pos = ArraySize(g_trigger_events);
      ArrayResize(g_trigger_events, pos + 1);
      g_trigger_events[pos] = evt;
   }

   __TRG_SortBridgeEvents();

   if(full_reset)
   {
      g_trigger_core.active                = false;
      g_trigger_core.active_start_seq      = -1;
      g_trigger_core.active_start_kind     = 0;
      g_trigger_core.active_start_ns       = WB15_NS_NONE;
      g_trigger_core.active_dir            = DIR_UP;
      g_trigger_core.active_start_time     = 0;
      g_trigger_core.active_start_bar_time = 0;
      __TRG_ResetWindowState();
      Flip_ResetGlobals();
      MajicFlip_ResetGlobals();
      TriggerSLTP_ResetGlobals();
   }

   return true;
}

inline void __TRG_ApplyWindowAt(const datetime bar_time)
{
   TriggerStartSession sessions[TRG_MAX_ACTIVE_SESSIONS];
   for(int i=0; i<TRG_MAX_ACTIVE_SESSIONS; ++i)
      __TRG_ClearSession(sessions[i]);

   int session_count = 0;
   const int evt_count = ArraySize(g_trigger_events);

   for(int i=0; i<evt_count; ++i)
   {
      TriggerEvent evt = g_trigger_events[i];
      if(evt.bar_time > bar_time)
         break;

      if(__TRG_IsStartKind(evt.kind))
      {
         for(int s=0; s<session_count; ++s)
            sessions[s].active = false;

         if(session_count <= 0)
            session_count = 1;
         if(session_count > TRG_MAX_ACTIVE_SESSIONS)
            session_count = TRG_MAX_ACTIVE_SESSIONS;

         sessions[0].active   = true;
         sessions[0].kind     = evt.kind;
         sessions[0].ns       = evt.ns;
         sessions[0].dir      = evt.dir;
         sessions[0].t        = evt.t;
         sessions[0].bar_time = evt.bar_time;
         sessions[0].seq      = evt.seq;
      }
      else
      {
         for(int s=session_count-1; s>=0; --s)
         {
            if(__TRG_SessionMatchesStop(sessions[s], evt.kind, evt.ns, evt.dir))
            {
               sessions[s].active = false;
               break;
            }
         }
      }
   }

   bool      new_active     = false;
   int       new_start_seq  = -1;
   int       new_start_kind = 0;
   int       new_start_ns   = WB15_NS_NONE;
   Direction new_dir        = DIR_UP;
   datetime  new_start_time = 0;
   datetime  new_start_bar  = 0;

   for(int s=session_count-1; s>=0; --s)
   {
      if(!sessions[s].active) continue;

      new_active     = true;
      new_start_seq  = sessions[s].seq;
      new_start_kind = sessions[s].kind;
      new_start_ns   = sessions[s].ns;
      new_dir        = sessions[s].dir;
      new_start_time = sessions[s].t;
      new_start_bar  = sessions[s].bar_time;
      break;
   }

   bool changed = false;
   if(new_active     != g_trigger_core.active) changed = true;
   if(new_start_seq  != g_trigger_core.active_start_seq) changed = true;
   if(new_start_kind != g_trigger_core.active_start_kind) changed = true;
   if(new_start_ns   != g_trigger_core.active_start_ns) changed = true;
   if(new_dir        != g_trigger_core.active_dir) changed = true;
   if(new_start_time != g_trigger_core.active_start_time) changed = true;
   if(new_start_bar  != g_trigger_core.active_start_bar_time) changed = true;

   g_trigger_core.active                = new_active;
   g_trigger_core.active_start_seq      = new_start_seq;
   g_trigger_core.active_start_kind     = new_start_kind;
   g_trigger_core.active_start_ns       = new_start_ns;
   g_trigger_core.active_dir            = new_dir;
   g_trigger_core.active_start_time     = new_start_time;
   g_trigger_core.active_start_bar_time = new_start_bar;

   if(changed)
   {
      __TRG_ResetWindowState();
      Flip_ResetGlobals();
      MajicFlip_ResetGlobals();
   }
}

// ----------------------------------------------------------------------------
// Drawing helpers
// ----------------------------------------------------------------------------
inline string __TRG_RunTag()
{
   return IntegerToString((int)g_trigger_core.run_id);
}

inline string __TRG_WindowTag()
{
   return IntegerToString(g_trigger_core.active_start_seq);
}

inline string __TRG_EngineTag(const int engine_type)
{
   if(engine_type == TRG_ENGINE_TYPE2)
      return "T2";
   return "T1";
}

inline color __TRG_EngineColor(const int engine_type)
{
   if(engine_type == TRG_ENGINE_TYPE2)
      return clrDodgerBlue;
   return clrYellow;
}

inline string __TRG_HitText(const int engine_type)
{
   if(engine_type == TRG_ENGINE_TYPE2)
      return "T2";
   return "T1";
}

inline double __TRG_LabelPad(const MqlRates &bar)
{
   double span = bar.high - bar.low;
   if(span <= 0.0)
      span = 10.0 * _Point;

   double pad = span * 0.28;
   if(pad < 4.0 * _Point)
      pad = 4.0 * _Point;
   return pad;
}

inline void __TRG_DrawTextUnique(const string base,
                                 const datetime t,
                                 const double price,
                                 const string text,
                                 const color col,
                                 const int font_size)
{
   if(!InpDrawMarkers) return;

   const string name = __ScanPrefix() + base;
   if(ObjectFind(0, name) != -1)
      ObjectDelete(0, name);

   if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, price))
      return;

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

inline void __TRG_DrawDashedLine(const string base,
                                 datetime t1,
                                 datetime t2,
                                 const double level,
                                 const color col)
{
   if(!InpDrawMarkers) return;
   if(t1 <= 0 || t2 <= 0) return;

   if(t2 < t1)
   {
      datetime tmp = t1;
      t1 = t2;
      t2 = tmp;
   }
   if(t2 == t1)
      t2 = (t1 + 1);

   const string name = __ScanPrefix() + base;
   if(ObjectFind(0, name) != -1)
      ObjectDelete(0, name);

   if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, level, t2, level))
      return;

   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

inline void __TRG_DrawTriggerMarker(const int type_id,
                                    const datetime ref_t,
                                    const datetime hit_t,
                                    const double level)
{
   int serial = 0;
   string dir_tag = "U";

   if(g_trigger_core.active_dir == DIR_UP)
   {
      g_trigger_core.up_counter++;
      serial  = g_trigger_core.up_counter;
      dir_tag = "U";
   }
   else
   {
      g_trigger_core.dn_counter++;
      serial  = g_trigger_core.dn_counter;
      dir_tag = "D";
   }

   string base = "TRG_HIT_" + __TRG_RunTag() + "_" + __TRG_WindowTag() + "_"
               + dir_tag + "_" + IntegerToString(serial) + "_"
               + __TRG_EngineTag(type_id);

   __TRG_DrawDashedLine(base + "_L", ref_t, hit_t, level, __TRG_EngineColor(type_id));
   __TRG_DrawTextUnique(base + "_T", hit_t, level, __TRG_HitText(type_id), __TRG_EngineColor(type_id), 10);
}

inline void __TRG_FireTrigger(const int       type_id,
                              const int       src_idx,
                              const double    level,
                              const int       hit_idx,
                              const MqlRates &rates[],
                              const int       n)
{
   if(src_idx < 0 || src_idx >= n) return;
   if(hit_idx < 0 || hit_idx >= n) return;

   string sym = g_trigger_symbol;
   if(sym == "")
      sym = _Symbol;

   TriggerSLTP_OnTriggerFired(sym,
                              g_trigger_core.active_dir,
                              type_id,
                              src_idx,
                              level,
                              hit_idx,
                              rates,
                              n);

   __TRG_DrawTriggerMarker(type_id,
                           rates[src_idx].time,
                           rates[hit_idx].time,
                           level);

   if(rates[hit_idx].time > g_trigger_pending_refresh_time)
      g_trigger_pending_refresh_time = rates[hit_idx].time;
}

inline void __TRG_FirePatternTrigger(const int       type_id,
                                     const int       anchor_idx,
                                     const int       hit_idx,
                                     const MqlRates &rates[],
                                     const int       n)
{
   if(hit_idx < 0 || hit_idx >= n) return;

   int ref_idx = anchor_idx;
   if(ref_idx < 0 || ref_idx >= n)
      ref_idx = hit_idx;

   string sym = g_trigger_symbol;
   if(sym == "")
      sym = _Symbol;

   double entry_level = rates[hit_idx].close;

   TriggerSLTP_OnTriggerFired(sym,
                              g_trigger_core.active_dir,
                              type_id,
                              hit_idx,
                              entry_level,
                              hit_idx,
                              rates,
                              n);

   __TRG_DrawTriggerMarker(type_id,
                           rates[ref_idx].time,
                           rates[hit_idx].time,
                           entry_level);

   if(rates[hit_idx].time > g_trigger_pending_refresh_time)
      g_trigger_pending_refresh_time = rates[hit_idx].time;
}

#include <WaveBot/Trigger_Type1.mqh>
#include <WaveBot/Trigger_Type2.mqh>

// ----------------------------------------------------------------------------
// Public feeder
// ----------------------------------------------------------------------------
inline void __TRG_ProcessLoadedBar(const string    sym,
                                   const MqlRates &rates[],
                                   const int       n,
                                   const int       bar_idx)
{
   if(sym == "") return;
   g_trigger_symbol = sym;
   if(n <= 0 || bar_idx < 0 || bar_idx >= n) return;

   const datetime bar_time = rates[bar_idx].time;
   __TRG_ApplyWindowAt(bar_time);

   if(!g_trigger_core.active)
      return;
   if(bar_time < g_trigger_core.active_start_bar_time)
      return;

   if(g_trigger_core.last_processed_time > 0 && bar_time <= g_trigger_core.last_processed_time)
      return;

   g_trigger_pending_refresh_time = 0;

   datetime from_time = g_trigger_core.active_start_bar_time;
   datetime to_time   = bar_time;

   if(g_trigger_core.active_dir == DIR_UP)
   {
      Trigger_Type1_ProcessUP(rates, n, bar_idx, from_time, to_time);
      Trigger_Type2_ProcessUP(rates, n, bar_idx, from_time, to_time);
   }
   else
   {
      Trigger_Type1_ProcessDOWN(rates, n, bar_idx, from_time, to_time);
      Trigger_Type2_ProcessDOWN(rates, n, bar_idx, from_time, to_time);
   }

   if(g_trigger_pending_refresh_time > 0)
      TriggerStatement_OnNewTriggerAt(g_trigger_pending_refresh_time);

   g_trigger_core.last_processed_time = bar_time;
   g_trigger_core.last_processed_idx  = bar_idx;
}

inline void Trigger_OnTimer(const string sym)
{
   if(!__TRG_IsWorkerTF()) return;
   if(sym != "")
      g_trigger_symbol = sym;
   if(!__TRG_IsMajorWorld()) return;
   if(sym == "") return;

   if(!__TRG_RebuildBridgeEvents(sym))
      return;

   const datetime probe_bar_time = __TRG_WorkerBarOpen(TimeCurrent());
   __TRG_ApplyWindowAt(probe_bar_time);

   datetime seed_time = 0;
   if(g_trigger_core.last_processed_time > 0)
      seed_time = g_trigger_core.last_processed_time;
   else if(g_trigger_core.active && g_trigger_core.active_start_bar_time > 0)
      seed_time = g_trigger_core.active_start_bar_time;
   else
      return;

   int tfsec = PeriodSeconds((ENUM_TIMEFRAMES)Period());
   if(tfsec <= 0)
      tfsec = 60;

   int back_bars = InpMaxBarsInWave;
   if(back_bars <= 0)
      back_bars = 1000;
   if(back_bars < 10)
      back_bars = 10;

   datetime from_time = (seed_time - (datetime)(tfsec * (back_bars + 5)));
   if(from_time < (datetime)0)
      from_time = 0;

   MqlRates rates[];
   int n = CopyRates(sym, (ENUM_TIMEFRAMES)Period(), from_time, TimeCurrent(), rates);
   if(n <= 0)
      return;

   ArraySetAsSeries(rates, false);

   datetime last_closed_time = iTime(sym, (ENUM_TIMEFRAMES)Period(), 1);
   if(last_closed_time <= 0)
      return;

   for(int i = 0; i < n; ++i)
   {
      if(rates[i].time <= 0)
         continue;
      if(rates[i].time > last_closed_time)
         break;

      __TRG_ProcessLoadedBar(sym, rates, n, i);
   }
}

inline void Trigger_OnBarCandidate(const string    sym,
                                   const MqlRates &rates[],
                                   const bool     &insideHL[],
                                   const int       n,
                                   const int       bar_idx,
                                   const int       candidate_idx)
{
   if(!__TRG_IsWorkerTF()) return;
   if(!__TRG_IsMajorWorld()) return;
   if(n <= 0 || bar_idx < 0 || bar_idx >= n) return;

   if(candidate_idx < -1) return;
   bool __unused_inside = insideHL[bar_idx];
   if(__unused_inside) { /* intentionally ignored */ }

   if(!__TRG_RebuildBridgeEvents(sym))
      return;

   __TRG_ProcessLoadedBar(sym, rates, n, bar_idx);
}

#endif // WAVEBOT_TRIGGER_MQH
