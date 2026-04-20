#ifndef WAVEBOT_TRIGGER_MQH
#define WAVEBOT_TRIGGER_MQH

#include <WaveBot/Types.mqh>
#include <WaveBot/Markers.mqh>
#include <WaveBot/WB15_SignalBridge.mqh>
#include <WaveBot/TriggerSLTP.mqh>

void TriggerStatement_OnNewTrigger();

// ============================================================================
// Trigger.mqh
//
// Independent trigger engine driven only by the M15 -> worker bridge and the
// raw worker-TF candles.
//
// Current rules implemented:
//   - Trigger starts from the worker candle that receives M15 signal on.
//   - Trigger stops immediately on the worker candle that receives M15 signal off.
//   - The engine is completely independent from the normal wave/candle scan.
//   - Every worker candle is processed, even if it is an inside bar or ignored
//     by the normal engine.
//   - The engine works step-by-step with a single 5-phase FSM per active window.
//   - Type-1 and type-2 triggers are both detected inside the same active window.
//   - Bullish side uses an initial floor (L). If that floor breaks, F is drawn
//     on the breaker candle and the whole trigger FSM is restarted from there.
//   - Bearish side is the exact mirror and uses an initial roof (H).
//   - Candle labels:
//        L / H = initial boundary candle
//        1..5  = phase membership of that candle
//        F     = reset candle that breaks the initial boundary
//        T     = final trigger candle
//
// NOTE:
//   This module runs in a hybrid mode.
//   The existing Trigger_OnBarCandidate(...) hooks in API.mqh / API_Down.mqh
//   are reused as a chronological feeder, and Trigger_OnTimer(...) also advances
//   the worker-TF trigger state on closed candles so no live window is skipped.
// ============================================================================

#define TRG_MAX_ACTIVE_SESSIONS  32

#define TRG_PHASE_NONE 0
#define TRG_PHASE_1    1
#define TRG_PHASE_2    2
#define TRG_PHASE_3    3
#define TRG_PHASE_4    4
#define TRG_PHASE_5    5

struct TriggerEvent
{
   datetime  t;         // raw bridge time
   datetime  bar_time;  // effective worker-TF bar open time
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

struct TriggerCore
{
   // Bridge snapshot
   double        run_id;
   int           bridge_seq;

   // Active H4-triggered window on worker TF
   bool          active;
   int           active_start_seq;
   int           active_start_kind;
   int           active_start_ns;
   Direction     active_dir;
   datetime      active_start_time;
   datetime      active_start_bar_time;

   // Mother boundary
   bool          mother_set;
   double        mother_level;      // bullish: initial low | bearish: initial high
   int           mother_idx;
   datetime      mother_time;

   // Five-phase FSM
   int           phase;

   // Bullish: phase1 high, phase2 low, phase3 high, phase4 low
   // Bearish: phase1 low,  phase2 high, phase3 low,  phase4 high
   double        phase1_level;
   int           phase1_idx;

   double        phase2_level;
   int           phase2_idx;

   double        phase3_level;
   int           phase3_idx;

   double        phase4_level;
   int           phase4_idx;

   // Current in-progress phase-2 build
   // bullish: latest pullback low candidate before a new phase-3 is confirmed
   // bearish: latest pullback high candidate before a new phase-3 is confirmed
   bool          phase2_build_active;
   double        phase2_build_level;
   int           phase2_build_idx;

   // Type discrimination
   bool          phase3_break1_seen;   // type-2 path if true
   bool          phase4_break2_seen;   // phase-4 already broke phase-2 reference?

   // Dedup / rewind shield
   datetime      last_processed_time;
   int           last_processed_idx;

   // Marker counters
   int           up_counter;
   int           dn_counter;
};

static TriggerCore  g_trigger_ctx;
static TriggerEvent g_trigger_events[];
static string       g_trigger_symbol = "";

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

inline double __TRG_Eps()
{
   return (_Point * 0.10);
}

inline bool __TRG_TouchHigh(const double price, const double level)
{
   return (price >= (level - __TRG_Eps()));
}

inline bool __TRG_TouchLow(const double price, const double level)
{
   return (price <= (level + __TRG_Eps()));
}

inline bool __TRG_BreakAboveStrict(const double price, const double level)
{
   return (price > (level + __TRG_Eps()));
}

inline bool __TRG_BreakBelowStrict(const double price, const double level)
{
   return (price < (level - __TRG_Eps()));
}

inline bool __TRG_IsBullCandle(const MqlRates &bar)
{
   return (bar.close > bar.open);
}

inline bool __TRG_IsBearCandle(const MqlRates &bar)
{
   return (bar.close < bar.open);
}

inline bool __TRG_IsInsideBar(const MqlRates &bar,
                              const MqlRates &ref_bar)
{
   const double eps = __TRG_Eps();
   return (bar.high <= (ref_bar.high + eps) &&
           bar.low  >= (ref_bar.low  - eps));
}

inline void __TRG_GetBullTriggerTarget(int    &type_id,
                                       double &target_level,
                                       int    &target_idx)
{
   type_id      = 0;
   target_level = 0.0;
   target_idx   = -1;

   if(g_trigger_ctx.phase3_idx < 0)
      return;

   if(g_trigger_ctx.phase3_break1_seen)
   {
      type_id      = 2;
      target_level = g_trigger_ctx.phase3_level;
      target_idx   = g_trigger_ctx.phase3_idx;
      return;
   }

   if(!g_trigger_ctx.phase4_break2_seen)
      return;
   if(g_trigger_ctx.phase1_idx < 0)
      return;

   type_id      = 1;
   target_level = g_trigger_ctx.phase1_level;
   target_idx   = g_trigger_ctx.phase1_idx;
}


inline void __TRG_GetBearTriggerTarget(int    &type_id,
                                       double &target_level,
                                       int    &target_idx)
{
   type_id      = 0;
   target_level = 0.0;
   target_idx   = -1;

   if(g_trigger_ctx.phase3_idx < 0)
      return;

   if(g_trigger_ctx.phase3_break1_seen)
   {
      type_id      = 2;
      target_level = g_trigger_ctx.phase3_level;
      target_idx   = g_trigger_ctx.phase3_idx;
      return;
   }

   if(!g_trigger_ctx.phase4_break2_seen)
      return;
   if(g_trigger_ctx.phase1_idx < 0)
      return;

   type_id      = 1;
   target_level = g_trigger_ctx.phase1_level;
   target_idx   = g_trigger_ctx.phase1_idx;
}


inline bool __TRG_HasConfirmedPhase3()
{
   return (g_trigger_ctx.phase3_idx >= 0);
}

inline void __TRG_ClearPhase2Build()
{
   g_trigger_ctx.phase2_build_active = false;
   g_trigger_ctx.phase2_build_level  = 0.0;
   g_trigger_ctx.phase2_build_idx    = -1;
}

inline int __TRG_BullPhase3StartRefIdx()
{
   if(g_trigger_ctx.phase2_build_active && g_trigger_ctx.phase2_build_idx >= 0)
      return g_trigger_ctx.phase2_build_idx;

   return g_trigger_ctx.phase2_idx;
}

inline int __TRG_BearPhase3StartRefIdx()
{
   if(g_trigger_ctx.phase2_build_active && g_trigger_ctx.phase2_build_idx >= 0)
      return g_trigger_ctx.phase2_build_idx;

   return g_trigger_ctx.phase2_idx;
}

inline bool __TRG_BullCanStartType1Phase3(const MqlRates &rates[],
                                          const int       n,
                                          const int       bar_idx)
{
   if(n <= 0 || bar_idx < 0 || bar_idx >= n)
      return false;

   int ref_idx = __TRG_BullPhase3StartRefIdx();
   if(ref_idx < 0 || ref_idx >= n)
      return false;

   if(__TRG_BreakAboveStrict(rates[bar_idx].high, g_trigger_ctx.phase1_level))
      return false;

   return __TRG_BreakAboveStrict(rates[bar_idx].high, rates[ref_idx].high);
}

inline bool __TRG_BearCanStartType1Phase3(const MqlRates &rates[],
                                          const int       n,
                                          const int       bar_idx)
{
   if(n <= 0 || bar_idx < 0 || bar_idx >= n)
      return false;

   int ref_idx = __TRG_BearPhase3StartRefIdx();
   if(ref_idx < 0 || ref_idx >= n)
      return false;

   if(__TRG_BreakBelowStrict(rates[bar_idx].low, g_trigger_ctx.phase1_level))
      return false;

   return __TRG_BreakBelowStrict(rates[bar_idx].low, rates[ref_idx].low);
}


inline void __TRG_BeginBullPhase2Build(const int bar_idx,
                                       const MqlRates &bar,
                                       const bool sync_confirmed_phase2)
{
   g_trigger_ctx.phase = TRG_PHASE_2;
   g_trigger_ctx.phase2_build_active = true;
   g_trigger_ctx.phase2_build_level  = bar.low;
   g_trigger_ctx.phase2_build_idx    = bar_idx;

   if(sync_confirmed_phase2)
   {
      g_trigger_ctx.phase2_level = bar.low;
      g_trigger_ctx.phase2_idx   = bar_idx;
   }
}

inline void __TRG_BeginBearPhase2Build(const int bar_idx,
                                       const MqlRates &bar,
                                       const bool sync_confirmed_phase2)
{
   g_trigger_ctx.phase = TRG_PHASE_2;
   g_trigger_ctx.phase2_build_active = true;
   g_trigger_ctx.phase2_build_level  = bar.high;
   g_trigger_ctx.phase2_build_idx    = bar_idx;

   if(sync_confirmed_phase2)
   {
      g_trigger_ctx.phase2_level = bar.high;
      g_trigger_ctx.phase2_idx   = bar_idx;
   }
}

inline void __TRG_UpdateBullPhase2Build(const int bar_idx,
                                        const MqlRates &bar,
                                        const bool sync_confirmed_phase2)
{
   if(!g_trigger_ctx.phase2_build_active)
   {
      __TRG_BeginBullPhase2Build(bar_idx, bar, sync_confirmed_phase2);
      return;
   }

   if(bar.low < g_trigger_ctx.phase2_build_level)
   {
      g_trigger_ctx.phase2_build_level = bar.low;
      g_trigger_ctx.phase2_build_idx   = bar_idx;

      if(sync_confirmed_phase2)
      {
         g_trigger_ctx.phase2_level = bar.low;
         g_trigger_ctx.phase2_idx   = bar_idx;
      }
   }
}

inline void __TRG_UpdateBearPhase2Build(const int bar_idx,
                                        const MqlRates &bar,
                                        const bool sync_confirmed_phase2)
{
   if(!g_trigger_ctx.phase2_build_active)
   {
      __TRG_BeginBearPhase2Build(bar_idx, bar, sync_confirmed_phase2);
      return;
   }

   if(bar.high > g_trigger_ctx.phase2_build_level)
   {
      g_trigger_ctx.phase2_build_level = bar.high;
      g_trigger_ctx.phase2_build_idx   = bar_idx;

      if(sync_confirmed_phase2)
      {
         g_trigger_ctx.phase2_level = bar.high;
         g_trigger_ctx.phase2_idx   = bar_idx;
      }
   }
}

inline void __TRG_CommitPhase2Build()
{
   if(!g_trigger_ctx.phase2_build_active)
      return;

   g_trigger_ctx.phase2_level = g_trigger_ctx.phase2_build_level;
   g_trigger_ctx.phase2_idx   = g_trigger_ctx.phase2_build_idx;
}

inline void __TRG_SetBullPhase2Latest(const int bar_idx,
                                      const MqlRates &bar)
{
   g_trigger_ctx.phase = TRG_PHASE_2;
   __TRG_UpdateBullPhase2Build(bar_idx, bar, true);
}

inline void __TRG_SetBearPhase2Latest(const int bar_idx,
                                      const MqlRates &bar)
{
   g_trigger_ctx.phase = TRG_PHASE_2;
   __TRG_UpdateBearPhase2Build(bar_idx, bar, true);
}

inline void __TRG_SetBullPhase2Candidate(const int bar_idx,
                                         const MqlRates &bar)
{
   g_trigger_ctx.phase = TRG_PHASE_2;
   __TRG_UpdateBullPhase2Build(bar_idx, bar, false);
}

inline void __TRG_SetBearPhase2Candidate(const int bar_idx,
                                         const MqlRates &bar)
{
   g_trigger_ctx.phase = TRG_PHASE_2;
   __TRG_UpdateBearPhase2Build(bar_idx, bar, false);
}

inline void __TRG_SetBullPhase3Latest(const int        bar_idx,
                                      const MqlRates &bar,
                                      const bool       broke_phase1)
{
   if(g_trigger_ctx.phase2_build_active)
      __TRG_CommitPhase2Build();

   g_trigger_ctx.phase = TRG_PHASE_3;
   g_trigger_ctx.phase3_level = bar.high;
   g_trigger_ctx.phase3_idx   = bar_idx;

   g_trigger_ctx.phase3_break1_seen = broke_phase1;
   g_trigger_ctx.phase4_break2_seen = false;
   __TRG_ClearPhase2Build();
}


inline void __TRG_SetBearPhase3Latest(const int        bar_idx,
                                      const MqlRates &bar,
                                      const bool       broke_phase1)
{
   if(g_trigger_ctx.phase2_build_active)
      __TRG_CommitPhase2Build();

   g_trigger_ctx.phase = TRG_PHASE_3;
   g_trigger_ctx.phase3_level = bar.low;
   g_trigger_ctx.phase3_idx   = bar_idx;

   g_trigger_ctx.phase3_break1_seen = broke_phase1;
   g_trigger_ctx.phase4_break2_seen = false;
   __TRG_ClearPhase2Build();
}


inline bool __TRG_BullSameBarType2TriggerAllowed(const MqlRates &bar)
{
   return __TRG_IsBullCandle(bar);
}

inline bool __TRG_BearSameBarType2TriggerAllowed(const MqlRates &bar)
{
   return __TRG_IsBearCandle(bar);
}

inline datetime __TRG_WorkerBarOpen(const datetime t)
{
   int sec = PeriodSeconds((ENUM_TIMEFRAMES)Period());
   if(sec <= 0) sec = 60;

   long ts = (long)t;
   long ss = (long)sec;
   return (datetime)(ts - (ts % ss));
}

// ----------------------------------------------------------------------------
// Reset helpers
// ----------------------------------------------------------------------------
inline void __TRG_ClearFSM()
{
   g_trigger_ctx.mother_set        = false;
   g_trigger_ctx.mother_level      = 0.0;
   g_trigger_ctx.mother_idx        = -1;
   g_trigger_ctx.mother_time       = 0;

   g_trigger_ctx.phase             = TRG_PHASE_NONE;

   g_trigger_ctx.phase1_level      = 0.0;
   g_trigger_ctx.phase1_idx        = -1;
   g_trigger_ctx.phase2_level      = 0.0;
   g_trigger_ctx.phase2_idx        = -1;
   g_trigger_ctx.phase3_level      = 0.0;
   g_trigger_ctx.phase3_idx        = -1;
   g_trigger_ctx.phase4_level      = 0.0;
   g_trigger_ctx.phase4_idx        = -1;

   g_trigger_ctx.phase3_break1_seen= false;
   g_trigger_ctx.phase4_break2_seen= false;

   __TRG_ClearPhase2Build();

   g_trigger_ctx.last_processed_time = 0;
   g_trigger_ctx.last_processed_idx  = -1;
}

inline void __TRG_ResetWindowState()
{
   __TRG_ClearFSM();
}

inline void Trigger_ResetGlobals()
{
   g_trigger_ctx.run_id                = 0.0;
   g_trigger_ctx.bridge_seq            = 0;

   g_trigger_ctx.active                = false;
   g_trigger_ctx.active_start_seq      = -1;
   g_trigger_ctx.active_start_kind     = 0;
   g_trigger_ctx.active_start_ns       = WB15_NS_NONE;
   g_trigger_ctx.active_dir            = DIR_UP;
   g_trigger_ctx.active_start_time     = 0;
   g_trigger_ctx.active_start_bar_time = 0;

   g_trigger_ctx.up_counter            = 0;
   g_trigger_ctx.dn_counter            = 0;

   g_trigger_symbol                    = "";

   __TRG_ClearFSM();
   ArrayResize(g_trigger_events, 0);
   TriggerSLTP_ResetGlobals();
}

// ----------------------------------------------------------------------------
// Bridge event loading / active-window reconstruction
// ----------------------------------------------------------------------------
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
   if(n <= 1) return;

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
         TriggerEvent tmp  = g_trigger_events[i];
         g_trigger_events[i] = g_trigger_events[best];
         g_trigger_events[best] = tmp;
      }
   }
}

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

inline bool __TRG_ShouldAutoStopOnNewStart(const TriggerStartSession &sess,
                                           const int new_kind,
                                           const int new_ns)
{
   // Simplified lifecycle: a fresh M15 signal on replaces the previous window.
   // No synthetic stop is generated on start.
   if(!sess.active) return false;
   if(new_kind <= 0) return false;
   if(new_ns < 0) return false;
   return false;
}

inline bool __TRG_SessionMatchesStop(const TriggerStartSession &sess,
                                     const int stop_kind,
                                     const int stop_ns,
                                     const Direction stop_dir)
{
   if(!sess.active) return false;
   if(!__TRG_IsStopKind(stop_kind)) return false;

   // Simplified rule:
   //   any M15 signal off closes the active trigger window,
   //   provided that its direction is the opposite of the active signal direction.
   // Namespace and signal kind no longer affect stop matching.
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
   if(g_trigger_ctx.run_id != run_id)
   {
      g_trigger_ctx.run_id = run_id;
      full_reset = true;
   }

   if(!full_reset && g_trigger_ctx.bridge_seq == seq)
      return true;

   g_trigger_ctx.bridge_seq = seq;
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
      g_trigger_ctx.active                = false;
      g_trigger_ctx.active_start_seq      = -1;
      g_trigger_ctx.active_start_kind     = 0;
      g_trigger_ctx.active_start_ns       = WB15_NS_NONE;
      g_trigger_ctx.active_dir            = DIR_UP;
      g_trigger_ctx.active_start_time     = 0;
      g_trigger_ctx.active_start_bar_time = 0;
      __TRG_ResetWindowState();
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
         // Simplified lifecycle:
         // every new M15 signal on replaces the previously active window,
         // regardless of type or namespace.
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
   if(new_active     != g_trigger_ctx.active) changed = true;
   if(new_start_seq  != g_trigger_ctx.active_start_seq) changed = true;
   if(new_start_kind != g_trigger_ctx.active_start_kind) changed = true;
   if(new_start_ns   != g_trigger_ctx.active_start_ns) changed = true;
   if(new_dir        != g_trigger_ctx.active_dir) changed = true;
   if(new_start_time != g_trigger_ctx.active_start_time) changed = true;
   if(new_start_bar  != g_trigger_ctx.active_start_bar_time) changed = true;

   g_trigger_ctx.active                = new_active;
   g_trigger_ctx.active_start_seq      = new_start_seq;
   g_trigger_ctx.active_start_kind     = new_start_kind;
   g_trigger_ctx.active_start_ns       = new_start_ns;
   g_trigger_ctx.active_dir            = new_dir;
   g_trigger_ctx.active_start_time     = new_start_time;
   g_trigger_ctx.active_start_bar_time = new_start_bar;

   if(changed)
      __TRG_ResetWindowState();
}

// ----------------------------------------------------------------------------
// Drawing helpers
// ----------------------------------------------------------------------------
inline string __TRG_RunTag()
{
   return IntegerToString((int)g_trigger_ctx.run_id);
}

inline string __TRG_WindowTag()
{
   return IntegerToString(g_trigger_ctx.active_start_seq);
}

inline double __TRG_LabelPad(const MqlRates &bar)
{
   double span = bar.high - bar.low;
   if(span <= 0.0) span = 10.0 * _Point;

   double pad = span * 0.28;
   if(pad < 4.0 * _Point) pad = 4.0 * _Point;
   return pad;
}

inline double __TRG_PhaseLabelY(const MqlRates &bar)
{
   double pad = __TRG_LabelPad(bar);
   if(g_trigger_ctx.active_dir == DIR_UP)
      return (bar.high + pad);
   return (bar.low - pad);
}

inline double __TRG_AnchorLabelY(const MqlRates &bar)
{
   double pad = __TRG_LabelPad(bar);
   if(g_trigger_ctx.active_dir == DIR_UP)
      return (bar.low - pad);
   return (bar.high + pad);
}

inline double __TRG_ResetLabelY(const MqlRates &bar)
{
   double pad = __TRG_LabelPad(bar);
   if(g_trigger_ctx.active_dir == DIR_UP)
      return (bar.low - (pad * 2.0));
   return (bar.high + (pad * 2.0));
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

inline void __TRG_DrawPhaseLabel(const MqlRates &bar, const int phase_id)
{
   if(phase_id < TRG_PHASE_1 || phase_id > TRG_PHASE_5) return;

   string base = "TRG_PHASE_" + __TRG_RunTag() + "_" + __TRG_WindowTag() + "_"
               + IntegerToString((int)bar.time);

   __TRG_DrawTextUnique(base,
                        bar.time,
                        __TRG_PhaseLabelY(bar),
                        IntegerToString(phase_id),
                        clrAqua,
                        9);
}

inline void __TRG_DrawBoundaryLabel(const MqlRates &bar)
{
   string text = (g_trigger_ctx.active_dir == DIR_UP ? "L" : "H");
   string base = "TRG_BOUND_" + __TRG_RunTag() + "_" + __TRG_WindowTag();

   __TRG_DrawTextUnique(base,
                        bar.time,
                        __TRG_AnchorLabelY(bar),
                        text,
                        clrYellow,
                        9);
}


inline void __TRG_DrawResetLabel(const MqlRates &bar)
{
   string base = "TRG_RESET_" + __TRG_RunTag() + "_" + __TRG_WindowTag() + "_"
               + IntegerToString((int)bar.time);

   __TRG_DrawTextUnique(base,
                        bar.time,
                        __TRG_ResetLabelY(bar),
                        "F",
                        clrRed,
                        10);
}

inline void __TRG_DrawTriggerMarker(const int type_id,
                                    const datetime ref_t,
                                    const datetime hit_t,
                                    const double level)
{
   int serial = 0;
   string dir_tag = "U";

   if(g_trigger_ctx.active_dir == DIR_UP)
   {
      g_trigger_ctx.up_counter++;
      serial  = g_trigger_ctx.up_counter;
      dir_tag = "U";
   }
   else
   {
      g_trigger_ctx.dn_counter++;
      serial  = g_trigger_ctx.dn_counter;
      dir_tag = "D";
   }

   string base = "TRG_HIT_" + __TRG_RunTag() + "_" + __TRG_WindowTag() + "_"
               + dir_tag + "_" + IntegerToString(serial) + "_"
               + IntegerToString(type_id);

   __TRG_DrawDashedLine(base + "_L", ref_t, hit_t, level, clrYellow);
   __TRG_DrawTextUnique(base + "_T", hit_t, level, "T", clrYellow, 10);
}

// ----------------------------------------------------------------------------
// Cycle start / restart helpers
// ----------------------------------------------------------------------------
inline void __TRG_StartBullCycle(const MqlRates &rates[],
                                 const int       n,
                                 const int       bar_idx,
                                 const bool      draw_reset,
                                 const bool      draw_anchor,
                                 const bool      draw_phase)
{
   if(bar_idx < 0 || bar_idx >= n) return;

   const MqlRates bar = rates[bar_idx];

   g_trigger_ctx.mother_set   = true;
   g_trigger_ctx.mother_level = bar.low;
   g_trigger_ctx.mother_idx   = bar_idx;
   g_trigger_ctx.mother_time  = bar.time;

   g_trigger_ctx.phase        = TRG_PHASE_1;

   g_trigger_ctx.phase1_level = bar.high;
   g_trigger_ctx.phase1_idx   = bar_idx;

   g_trigger_ctx.phase2_level = 0.0;
   g_trigger_ctx.phase2_idx   = -1;
   g_trigger_ctx.phase3_level = 0.0;
   g_trigger_ctx.phase3_idx   = -1;
   g_trigger_ctx.phase4_level = 0.0;
   g_trigger_ctx.phase4_idx   = -1;

   g_trigger_ctx.phase3_break1_seen = false;
   g_trigger_ctx.phase4_break2_seen = false;

   __TRG_ClearPhase2Build();

   if(draw_reset) __TRG_DrawResetLabel(bar);
   if(draw_anchor) __TRG_DrawBoundaryLabel(bar);
   if(draw_phase) __TRG_DrawPhaseLabel(bar, TRG_PHASE_1);
}

inline void __TRG_StartBearCycle(const MqlRates &rates[],
                                 const int       n,
                                 const int       bar_idx,
                                 const bool      draw_reset,
                                 const bool      draw_anchor,
                                 const bool      draw_phase)
{
   if(bar_idx < 0 || bar_idx >= n) return;

   const MqlRates bar = rates[bar_idx];

   g_trigger_ctx.mother_set   = true;
   g_trigger_ctx.mother_level = bar.high;
   g_trigger_ctx.mother_idx   = bar_idx;
   g_trigger_ctx.mother_time  = bar.time;

   g_trigger_ctx.phase        = TRG_PHASE_1;

   g_trigger_ctx.phase1_level = bar.low;
   g_trigger_ctx.phase1_idx   = bar_idx;

   g_trigger_ctx.phase2_level = 0.0;
   g_trigger_ctx.phase2_idx   = -1;
   g_trigger_ctx.phase3_level = 0.0;
   g_trigger_ctx.phase3_idx   = -1;
   g_trigger_ctx.phase4_level = 0.0;
   g_trigger_ctx.phase4_idx   = -1;

   g_trigger_ctx.phase3_break1_seen = false;
   g_trigger_ctx.phase4_break2_seen = false;

   __TRG_ClearPhase2Build();

   if(draw_reset) __TRG_DrawResetLabel(bar);
   if(draw_anchor) __TRG_DrawBoundaryLabel(bar);
   if(draw_phase) __TRG_DrawPhaseLabel(bar, TRG_PHASE_1);
}

inline void __TRG_StartCycleAt(const MqlRates &rates[],
                               const int       n,
                               const int       bar_idx,
                               const bool      draw_reset,
                               const bool      draw_anchor,
                               const bool      draw_phase)
{
   if(g_trigger_ctx.active_dir == DIR_UP)
      __TRG_StartBullCycle(rates, n, bar_idx, draw_reset, draw_anchor, draw_phase);
   else
      __TRG_StartBearCycle(rates, n, bar_idx, draw_reset, draw_anchor, draw_phase);
}

inline void __TRG_RestartAfterHit(const MqlRates &rates[],
                                  const int       n,
                                  const int       hit_idx)
{
   // Start a fresh internal cycle from the trigger candle itself so the next
   // candles can continue without waiting for the normal scan to reset.
   // Visual re-anchoring is intentionally silent here to keep the chart clear.
   __TRG_StartCycleAt(rates, n, hit_idx, false, false, false);
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
                              g_trigger_ctx.active_dir,
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

   __TRG_RestartAfterHit(rates, n, hit_idx);
   TriggerStatement_OnNewTrigger();
}

inline int __TRG_BullHandlePhase4Break(const MqlRates &rates[],
                                       const int       n,
                                       const int       bar_idx)
{
   if(bar_idx < 0 || bar_idx >= n)
      return TRG_PHASE_NONE;

   const MqlRates bar = rates[bar_idx];

   int    type_id    = 2;
   double target     = 0.0;
   int    target_idx = -1;
   __TRG_GetBullTriggerTarget(type_id, target, target_idx);

   g_trigger_ctx.phase              = TRG_PHASE_4;
   g_trigger_ctx.phase4_level       = bar.low;
   g_trigger_ctx.phase4_idx         = bar_idx;
   g_trigger_ctx.phase4_break2_seen = true;
   __TRG_ClearPhase2Build();

   __TRG_DrawPhaseLabel(bar, TRG_PHASE_4);

   // Same-candle completion is valid only for a bullish (green) candle.
   if(target_idx >= 0 &&
      __TRG_TouchHigh(bar.high, target) &&
      __TRG_BullSameBarType2TriggerAllowed(bar))
   {
      __TRG_FireTrigger(type_id, target_idx, target, bar_idx, rates, n);
      return TRG_PHASE_4;
   }

   g_trigger_ctx.phase = TRG_PHASE_5;
   return TRG_PHASE_4;
}

inline int __TRG_BearHandlePhase4Break(const MqlRates &rates[],
                                       const int       n,
                                       const int       bar_idx)
{
   if(bar_idx < 0 || bar_idx >= n)
      return TRG_PHASE_NONE;

   const MqlRates bar = rates[bar_idx];

   int    type_id    = 2;
   double target     = 0.0;
   int    target_idx = -1;
   __TRG_GetBearTriggerTarget(type_id, target, target_idx);

   g_trigger_ctx.phase              = TRG_PHASE_4;
   g_trigger_ctx.phase4_level       = bar.high;
   g_trigger_ctx.phase4_idx         = bar_idx;
   g_trigger_ctx.phase4_break2_seen = true;
   __TRG_ClearPhase2Build();

   __TRG_DrawPhaseLabel(bar, TRG_PHASE_4);

   // Mirror rule: same-candle completion is valid only for a bearish (red) candle.
   if(target_idx >= 0 &&
      __TRG_TouchLow(bar.low, target) &&
      __TRG_BearSameBarType2TriggerAllowed(bar))
   {
      __TRG_FireTrigger(type_id, target_idx, target, bar_idx, rates, n);
      return TRG_PHASE_4;
   }

   g_trigger_ctx.phase = TRG_PHASE_5;
   return TRG_PHASE_4;
}

inline int __TRG_ProcessBull(const MqlRates &rates[],
                             const int       n,
                             const int       bar_idx)
{
   if(bar_idx < 0 || bar_idx >= n) return TRG_PHASE_NONE;

   const MqlRates bar = rates[bar_idx];

   if(!g_trigger_ctx.mother_set)
   {
      __TRG_StartBullCycle(rates, n, bar_idx, false, true, true);
      return TRG_PHASE_1;
   }

   bool allow_phase1_mother_update = false;
   if(g_trigger_ctx.phase == TRG_PHASE_1 &&
      __TRG_BreakAboveStrict(bar.high, g_trigger_ctx.phase1_level))
   {
      allow_phase1_mother_update = true;
   }

   if(__TRG_BreakBelowStrict(bar.low, g_trigger_ctx.mother_level) &&
      !allow_phase1_mother_update)
   {
      __TRG_StartBullCycle(rates, n, bar_idx, true, true, true);
      return TRG_PHASE_1;
   }

   if(g_trigger_ctx.phase <= TRG_PHASE_NONE || g_trigger_ctx.phase > TRG_PHASE_5)
   {
      __TRG_StartBullCycle(rates, n, bar_idx, false, true, true);
      return TRG_PHASE_1;
   }

   if(bar_idx == g_trigger_ctx.mother_idx && g_trigger_ctx.phase == TRG_PHASE_1)
   {
      __TRG_DrawPhaseLabel(bar, TRG_PHASE_1);
      return TRG_PHASE_1;
   }

   switch(g_trigger_ctx.phase)
   {
      case TRG_PHASE_1:
      {
         bool extended_phase1 = false;

         if(__TRG_BreakAboveStrict(bar.high, g_trigger_ctx.phase1_level))
         {
            g_trigger_ctx.phase1_level = bar.high;
            g_trigger_ctx.phase1_idx   = bar_idx;
            extended_phase1 = true;
         }

         if(bar.low < g_trigger_ctx.mother_level)
         {
            g_trigger_ctx.mother_level = bar.low;
            g_trigger_ctx.mother_idx   = bar_idx;
            g_trigger_ctx.mother_time  = bar.time;
            __TRG_DrawBoundaryLabel(bar);
         }

         if(extended_phase1)
         {
            __TRG_DrawPhaseLabel(bar, TRG_PHASE_1);
            return TRG_PHASE_1;
         }

         // After phase-1 stops extending, the next candle starts the phase-2 group.
         // The phase-4 break reference is the LOWEST low of that group.
         __TRG_SetBullPhase2Latest(bar_idx, bar);
         __TRG_DrawPhaseLabel(bar, TRG_PHASE_2);
         return TRG_PHASE_2;
      }

      case TRG_PHASE_2:
      {
         if(!__TRG_HasConfirmedPhase3())
         {
            // Type-2 path: a direct break of phase-1 high creates the first break-1 phase-3.
            if(__TRG_BreakAboveStrict(bar.high, g_trigger_ctx.phase1_level))
            {
               __TRG_SetBullPhase3Latest(bar_idx, bar, true);
               __TRG_DrawPhaseLabel(bar, TRG_PHASE_3);
               return TRG_PHASE_3;
            }

            // Type-1 path: a local bullish swing that stays below phase-1 high is a valid phase-3 group.
            if(__TRG_BullCanStartType1Phase3(rates, n, bar_idx))
            {
               __TRG_SetBullPhase3Latest(bar_idx, bar, false);
               __TRG_DrawPhaseLabel(bar, TRG_PHASE_3);
               return TRG_PHASE_3;
            }

            __TRG_SetBullPhase2Latest(bar_idx, bar);
            __TRG_DrawPhaseLabel(bar, TRG_PHASE_2);
            return TRG_PHASE_2;
         }

         // A break of the active phase-2 reference always starts phase-4,
         // regardless of whether the active path is type-1 or type-2.
         if(g_trigger_ctx.phase2_idx >= 0 &&
            __TRG_BreakBelowStrict(bar.low, g_trigger_ctx.phase2_level))
         {
            return __TRG_BullHandlePhase4Break(rates, n, bar_idx);
         }

         if(g_trigger_ctx.phase3_break1_seen)
         {
            // Type-2: the active trigger target is the latest confirmed phase-3,
            // so only a fresh break above that latest phase-3 creates the next phase-3.
            if(__TRG_BreakAboveStrict(bar.high, g_trigger_ctx.phase3_level))
            {
               __TRG_SetBullPhase3Latest(bar_idx, bar, true);
               __TRG_DrawPhaseLabel(bar, TRG_PHASE_3);
               return TRG_PHASE_3;
            }
         }
         else
         {
            // Type-1: before phase-4, a break of phase-1 high invalidates the type-1 path
            // and immediately converts the structure into the type-2 path.
            if(__TRG_BreakAboveStrict(bar.high, g_trigger_ctx.phase1_level))
            {
               __TRG_SetBullPhase3Latest(bar_idx, bar, true);
               __TRG_DrawPhaseLabel(bar, TRG_PHASE_3);
               return TRG_PHASE_3;
            }

            // Type-1 also allows many phase-2 / phase-3 groups under the same phase-1 high.
            // Any fresh local bullish swing from the latest phase-2 group becomes the next phase-3,
            // even if its سقف stays below the previous phase-3 سقف.
            if(__TRG_BullCanStartType1Phase3(rates, n, bar_idx))
            {
               __TRG_SetBullPhase3Latest(bar_idx, bar, false);
               __TRG_DrawPhaseLabel(bar, TRG_PHASE_3);
               return TRG_PHASE_3;
            }
         }

         __TRG_SetBullPhase2Candidate(bar_idx, bar);
         __TRG_DrawPhaseLabel(bar, TRG_PHASE_2);
         return TRG_PHASE_2;
      }

      case TRG_PHASE_3:
      {
         if(g_trigger_ctx.phase2_idx >= 0 &&
            __TRG_BreakBelowStrict(bar.low, g_trigger_ctx.phase2_level))
         {
            return __TRG_BullHandlePhase4Break(rates, n, bar_idx);
         }

         if(g_trigger_ctx.phase3_break1_seen)
         {
            if(__TRG_BreakAboveStrict(bar.high, g_trigger_ctx.phase3_level))
            {
               __TRG_SetBullPhase3Latest(bar_idx, bar, true);
               __TRG_DrawPhaseLabel(bar, TRG_PHASE_3);
               return TRG_PHASE_3;
            }
         }
         else
         {
            if(__TRG_BreakAboveStrict(bar.high, g_trigger_ctx.phase1_level))
            {
               __TRG_SetBullPhase3Latest(bar_idx, bar, true);
               __TRG_DrawPhaseLabel(bar, TRG_PHASE_3);
               return TRG_PHASE_3;
            }

            if(__TRG_BreakAboveStrict(bar.high, g_trigger_ctx.phase3_level))
            {
               __TRG_SetBullPhase3Latest(bar_idx, bar, false);
               __TRG_DrawPhaseLabel(bar, TRG_PHASE_3);
               return TRG_PHASE_3;
            }
         }

         __TRG_SetBullPhase2Candidate(bar_idx, bar);
         __TRG_DrawPhaseLabel(bar, TRG_PHASE_2);
         return TRG_PHASE_2;
      }

      case TRG_PHASE_4:
      {
         g_trigger_ctx.phase = TRG_PHASE_5;
         __TRG_DrawPhaseLabel(bar, TRG_PHASE_5);

         int    type_id    = 0;
         double target     = 0.0;
         int    target_idx = -1;
         __TRG_GetBullTriggerTarget(type_id, target, target_idx);

         if(target_idx >= 0 && __TRG_TouchHigh(bar.high, target))
            __TRG_FireTrigger(type_id, target_idx, target, bar_idx, rates, n);

         return TRG_PHASE_5;
      }

      case TRG_PHASE_5:
      {
         __TRG_DrawPhaseLabel(bar, TRG_PHASE_5);

         int    type_id    = 0;
         double target     = 0.0;
         int    target_idx = -1;
         __TRG_GetBullTriggerTarget(type_id, target, target_idx);

         if(target_idx >= 0 && __TRG_TouchHigh(bar.high, target))
            __TRG_FireTrigger(type_id, target_idx, target, bar_idx, rates, n);

         return TRG_PHASE_5;
      }
   }

   return TRG_PHASE_NONE;
}



// ----------------------------------------------------------------------------
// Bearish 5-phase FSM (mirror)
// ----------------------------------------------------------------------------
inline int __TRG_ProcessBear(const MqlRates &rates[],
                             const int       n,
                             const int       bar_idx)
{
   if(bar_idx < 0 || bar_idx >= n) return TRG_PHASE_NONE;

   const MqlRates bar = rates[bar_idx];

   if(!g_trigger_ctx.mother_set)
   {
      __TRG_StartBearCycle(rates, n, bar_idx, false, true, true);
      return TRG_PHASE_1;
   }

   bool allow_phase1_mother_update = false;
   if(g_trigger_ctx.phase == TRG_PHASE_1 &&
      __TRG_BreakBelowStrict(bar.low, g_trigger_ctx.phase1_level))
   {
      allow_phase1_mother_update = true;
   }

   if(__TRG_BreakAboveStrict(bar.high, g_trigger_ctx.mother_level) &&
      !allow_phase1_mother_update)
   {
      __TRG_StartBearCycle(rates, n, bar_idx, true, true, true);
      return TRG_PHASE_1;
   }

   if(g_trigger_ctx.phase <= TRG_PHASE_NONE || g_trigger_ctx.phase > TRG_PHASE_5)
   {
      __TRG_StartBearCycle(rates, n, bar_idx, false, true, true);
      return TRG_PHASE_1;
   }

   if(bar_idx == g_trigger_ctx.mother_idx && g_trigger_ctx.phase == TRG_PHASE_1)
   {
      __TRG_DrawPhaseLabel(bar, TRG_PHASE_1);
      return TRG_PHASE_1;
   }

   switch(g_trigger_ctx.phase)
   {
      case TRG_PHASE_1:
      {
         bool extended_phase1 = false;

         if(__TRG_BreakBelowStrict(bar.low, g_trigger_ctx.phase1_level))
         {
            g_trigger_ctx.phase1_level = bar.low;
            g_trigger_ctx.phase1_idx   = bar_idx;
            extended_phase1 = true;
         }

         if(bar.high > g_trigger_ctx.mother_level)
         {
            g_trigger_ctx.mother_level = bar.high;
            g_trigger_ctx.mother_idx   = bar_idx;
            g_trigger_ctx.mother_time  = bar.time;
            __TRG_DrawBoundaryLabel(bar);
         }

         if(extended_phase1)
         {
            __TRG_DrawPhaseLabel(bar, TRG_PHASE_1);
            return TRG_PHASE_1;
         }

         __TRG_SetBearPhase2Latest(bar_idx, bar);
         __TRG_DrawPhaseLabel(bar, TRG_PHASE_2);
         return TRG_PHASE_2;
      }

      case TRG_PHASE_2:
      {
         if(!__TRG_HasConfirmedPhase3())
         {
            if(__TRG_BreakBelowStrict(bar.low, g_trigger_ctx.phase1_level))
            {
               __TRG_SetBearPhase3Latest(bar_idx, bar, true);
               __TRG_DrawPhaseLabel(bar, TRG_PHASE_3);
               return TRG_PHASE_3;
            }

            if(__TRG_BearCanStartType1Phase3(rates, n, bar_idx))
            {
               __TRG_SetBearPhase3Latest(bar_idx, bar, false);
               __TRG_DrawPhaseLabel(bar, TRG_PHASE_3);
               return TRG_PHASE_3;
            }

            __TRG_SetBearPhase2Latest(bar_idx, bar);
            __TRG_DrawPhaseLabel(bar, TRG_PHASE_2);
            return TRG_PHASE_2;
         }

         if(g_trigger_ctx.phase2_idx >= 0 &&
            __TRG_BreakAboveStrict(bar.high, g_trigger_ctx.phase2_level))
         {
            return __TRG_BearHandlePhase4Break(rates, n, bar_idx);
         }

         if(g_trigger_ctx.phase3_break1_seen)
         {
            if(__TRG_BreakBelowStrict(bar.low, g_trigger_ctx.phase3_level))
            {
               __TRG_SetBearPhase3Latest(bar_idx, bar, true);
               __TRG_DrawPhaseLabel(bar, TRG_PHASE_3);
               return TRG_PHASE_3;
            }
         }
         else
         {
            if(__TRG_BreakBelowStrict(bar.low, g_trigger_ctx.phase1_level))
            {
               __TRG_SetBearPhase3Latest(bar_idx, bar, true);
               __TRG_DrawPhaseLabel(bar, TRG_PHASE_3);
               return TRG_PHASE_3;
            }

            if(__TRG_BearCanStartType1Phase3(rates, n, bar_idx))
            {
               __TRG_SetBearPhase3Latest(bar_idx, bar, false);
               __TRG_DrawPhaseLabel(bar, TRG_PHASE_3);
               return TRG_PHASE_3;
            }
         }

         __TRG_SetBearPhase2Candidate(bar_idx, bar);
         __TRG_DrawPhaseLabel(bar, TRG_PHASE_2);
         return TRG_PHASE_2;
      }

      case TRG_PHASE_3:
      {
         if(g_trigger_ctx.phase2_idx >= 0 &&
            __TRG_BreakAboveStrict(bar.high, g_trigger_ctx.phase2_level))
         {
            return __TRG_BearHandlePhase4Break(rates, n, bar_idx);
         }

         if(g_trigger_ctx.phase3_break1_seen)
         {
            if(__TRG_BreakBelowStrict(bar.low, g_trigger_ctx.phase3_level))
            {
               __TRG_SetBearPhase3Latest(bar_idx, bar, true);
               __TRG_DrawPhaseLabel(bar, TRG_PHASE_3);
               return TRG_PHASE_3;
            }
         }
         else
         {
            if(__TRG_BreakBelowStrict(bar.low, g_trigger_ctx.phase1_level))
            {
               __TRG_SetBearPhase3Latest(bar_idx, bar, true);
               __TRG_DrawPhaseLabel(bar, TRG_PHASE_3);
               return TRG_PHASE_3;
            }

            if(__TRG_BreakBelowStrict(bar.low, g_trigger_ctx.phase3_level))
            {
               __TRG_SetBearPhase3Latest(bar_idx, bar, false);
               __TRG_DrawPhaseLabel(bar, TRG_PHASE_3);
               return TRG_PHASE_3;
            }
         }

         __TRG_SetBearPhase2Candidate(bar_idx, bar);
         __TRG_DrawPhaseLabel(bar, TRG_PHASE_2);
         return TRG_PHASE_2;
      }

      case TRG_PHASE_4:
      {
         g_trigger_ctx.phase = TRG_PHASE_5;
         __TRG_DrawPhaseLabel(bar, TRG_PHASE_5);

         int    type_id    = 0;
         double target     = 0.0;
         int    target_idx = -1;
         __TRG_GetBearTriggerTarget(type_id, target, target_idx);

         if(target_idx >= 0 && __TRG_TouchLow(bar.low, target))
            __TRG_FireTrigger(type_id, target_idx, target, bar_idx, rates, n);

         return TRG_PHASE_5;
      }

      case TRG_PHASE_5:
      {
         __TRG_DrawPhaseLabel(bar, TRG_PHASE_5);

         int    type_id    = 0;
         double target     = 0.0;
         int    target_idx = -1;
         __TRG_GetBearTriggerTarget(type_id, target, target_idx);

         if(target_idx >= 0 && __TRG_TouchLow(bar.low, target))
            __TRG_FireTrigger(type_id, target_idx, target, bar_idx, rates, n);

         return TRG_PHASE_5;
      }
   }

   return TRG_PHASE_NONE;
}



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

   if(!g_trigger_ctx.active)
      return;
   if(bar_time < g_trigger_ctx.active_start_bar_time)
      return;

   if(g_trigger_ctx.last_processed_time > 0 && bar_time <= g_trigger_ctx.last_processed_time)
      return;

   if(g_trigger_ctx.active_dir == DIR_UP)
      __TRG_ProcessBull(rates, n, bar_idx);
   else
      __TRG_ProcessBear(rates, n, bar_idx);

   g_trigger_ctx.last_processed_time = bar_time;
   g_trigger_ctx.last_processed_idx  = bar_idx;
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
   if(g_trigger_ctx.last_processed_time > 0)
      seed_time = g_trigger_ctx.last_processed_time;
   else if(g_trigger_ctx.active && g_trigger_ctx.active_start_bar_time > 0)
      seed_time = g_trigger_ctx.active_start_bar_time;
   else
      return;

   int tfsec = PeriodSeconds((ENUM_TIMEFRAMES)Period());
   if(tfsec <= 0) tfsec = 60;

   datetime from_time = (seed_time - (datetime)(tfsec * 2));
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
