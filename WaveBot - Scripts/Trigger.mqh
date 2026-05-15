#ifndef WAVEBOT_TRIGGER_MQH
#define WAVEBOT_TRIGGER_MQH

#include <WaveBot/Types.mqh>
#include <WaveBot/Markers.mqh>
#include <WaveBot/WaveBotLogger.mqh>
#include <WaveBot/WB15_SignalBridge.mqh>
#include <WaveBot/Flip.mqh>
#include <WaveBot/Majicflip.mqh>
#include <WaveBot/TriggerSLTP.mqh>

void TriggerStatement_OnNewTriggerAt(const datetime trigger_time);
bool TriggerStatement_ScheduledOutputMaybeAt(const datetime current_time);

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
   int       context_id;
   int       zone_id;
   int       m1_window_id;
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
   int       context_id;
   int       zone_id;
   int       m1_window_id;
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
   int           active_context_id;
   int           active_zone_id;
   int           active_m1_window_id;

   datetime      last_processed_time;
   int           last_processed_idx;

   int           up_counter;
   int           dn_counter;
};

static TriggerWindowCore g_trigger_core;
static TriggerEvent      g_trigger_events[];
static string            g_trigger_symbol = "";
static datetime          g_trigger_pending_refresh_time = 0;
static int               g_trigger_apply_next_event = 0;
static datetime          g_trigger_apply_last_time  = 0;

// Streaming M15->M1 safety boundary. While the M15 master is still scanning,
// the M1 slave may scan its own candles, but trigger evaluation must only run
// up to the latest M15 progress point for which all bridge START/STOP events
// are already known.
static bool              g_trigger_bridge_safe_until_enabled = false;
static datetime          g_trigger_bridge_safe_until_time    = 0;

// Hard terminal boundary for the historical M1 scan.
// When WaveBot.mq5 finishes the one-shot M1 pass, live timer processing must not
// rewind into the last few days and rescan already-processed candles.
static bool              g_trigger_m1_hard_stop_enabled    = false;
static datetime          g_trigger_m1_hard_stop_time       = 0;
static bool              g_trigger_m1_terminal_stop_mode   = false;
static bool              g_trigger_m1_finalize_requested   = false;
static datetime          g_trigger_m1_finalize_time        = 0;

// Hard terminal boundary for the historical M15 master scan.
// This is separated from the M1 hard stop: the M15 master can stop only its own
// chart after publishing DONE, while the M1 slave continues from bridge events.
static bool              g_trigger_m15_hard_stop_enabled   = false;
static datetime          g_trigger_m15_hard_stop_time      = 0;
static bool              g_trigger_m15_terminal_stop_mode  = false;
static bool              g_trigger_m15_finalize_requested  = false;
static datetime          g_trigger_m15_finalize_time       = 0;

// Public functions implemented by Trigger_Type1.mqh / Trigger_Type2.mqh.
void Trigger_Type1_ResetGlobals();
bool Trigger_Type1_ProcessUP(const MqlRates &rates[], const int n, const int bar_idx, const datetime from_time, const datetime to_time);
bool Trigger_Type1_ProcessDOWN(const MqlRates &rates[], const int n, const int bar_idx, const datetime from_time, const datetime to_time);
void Trigger_Type2_ResetGlobals();
bool Trigger_Type2_ProcessUP(const MqlRates &rates[], const int n, const int bar_idx, const datetime from_time, const datetime to_time);
bool Trigger_Type2_ProcessDOWN(const MqlRates &rates[], const int n, const int bar_idx, const datetime from_time, const datetime to_time);

inline void Trigger_SetM1HardStop(const datetime stop_time, const bool terminal_stop_mode)
{
   if(stop_time > 0)
   {
      g_trigger_m1_hard_stop_enabled  = true;
      g_trigger_m1_hard_stop_time     = stop_time;
      g_trigger_m1_terminal_stop_mode = terminal_stop_mode;

      if(!terminal_stop_mode)
      {
         g_trigger_m1_finalize_requested = false;
         g_trigger_m1_finalize_time      = 0;
      }
   }
   else
   {
      g_trigger_m1_hard_stop_enabled     = false;
      g_trigger_m1_hard_stop_time        = 0;
      g_trigger_m1_terminal_stop_mode    = false;
      g_trigger_m1_finalize_requested    = false;
      g_trigger_m1_finalize_time         = 0;
   }
}

inline bool Trigger_M1HardStopEnabled()
{
   return g_trigger_m1_hard_stop_enabled;
}

inline datetime Trigger_M1HardStopTime()
{
   return g_trigger_m1_hard_stop_time;
}

inline bool Trigger_M1TerminalStopMode()
{
   return g_trigger_m1_terminal_stop_mode;
}

inline bool Trigger_M1HardStopFinalizeRequested()
{
   return g_trigger_m1_finalize_requested;
}

inline datetime Trigger_M1HardStopFinalizeTime()
{
   return g_trigger_m1_finalize_time;
}

inline bool __TRG_M1HardStopBeyondAllowed(const datetime t)
{
   if(!g_trigger_m1_hard_stop_enabled)
      return false;
   if(g_trigger_m1_hard_stop_time <= 0)
      return false;
   if(t <= 0)
      return false;

   // The configured stop time is the last M1 candle that is allowed to be
   // processed. Only bars AFTER it are blocked before processing.
   return (t > g_trigger_m1_hard_stop_time);
}

inline bool __TRG_M1HardStopFinalBarReached(const datetime t)
{
   if(!g_trigger_m1_hard_stop_enabled)
      return false;
   if(g_trigger_m1_hard_stop_time <= 0)
      return false;
   if(t <= 0)
      return false;

   return (t >= g_trigger_m1_hard_stop_time);
}

inline bool Trigger_M1HardStopReached(const datetime t)
{
   return __TRG_M1HardStopBeyondAllowed(t);
}

inline void Trigger_RequestM1HardStopFinalize(const datetime reached_time)
{
   if(!g_trigger_m1_hard_stop_enabled)
      return;
   if(g_trigger_m1_hard_stop_time <= 0)
      return;

   datetime use_time = reached_time;
   if(use_time <= 0 || use_time > g_trigger_m1_hard_stop_time)
      use_time = g_trigger_m1_hard_stop_time;

   g_trigger_m1_finalize_requested = true;
   g_trigger_m1_finalize_time      = use_time;
}

inline bool Trigger_M1HardStopShouldStopBeforeBar(const datetime t)
{
   if(g_trigger_m1_terminal_stop_mode)
      return true;

   if(g_trigger_m1_finalize_requested)
      return true;

   if(__TRG_M1HardStopBeyondAllowed(t))
   {
      Trigger_RequestM1HardStopFinalize(g_trigger_m1_hard_stop_time);
      return true;
   }

   return false;
}

inline void Trigger_M1HardStopMarkFinalBarIfNeeded(const datetime t)
{
   if(g_trigger_m1_terminal_stop_mode)
      return;

   if(__TRG_M1HardStopFinalBarReached(t))
      Trigger_RequestM1HardStopFinalize(t);
}

inline bool __TRG_M1HardStopBlocksProcessing(const datetime t)
{
   if(!g_trigger_m1_hard_stop_enabled)
      return false;

   // Terminal mode is enabled only after the first complete historical M1 pass.
   // From that moment, even older bars must not be accepted again; otherwise a
   // timer/backfill call can jump back several days and duplicate statement trades.
   if(g_trigger_m1_terminal_stop_mode)
      return true;

   return __TRG_M1HardStopBeyondAllowed(t);
}

inline void Trigger_FinalizeM1HardStop(const datetime stop_time)
{
   Trigger_SetM1HardStop(stop_time, true);

   if(stop_time <= 0)
      return;

   g_trigger_m1_finalize_requested = true;
   g_trigger_m1_finalize_time      = stop_time;

   // Final hard stop means no historical or live replay may create another M1
   // trigger. Close the imported window locally and advance the bridge cursor
   // to the current event count so old bridge events cannot reopen it.
   g_trigger_core.active                = false;
   g_trigger_core.active_start_seq      = -1;
   g_trigger_core.active_start_kind     = 0;
   g_trigger_core.active_start_ns       = WB15_NS_NONE;
   g_trigger_core.active_dir            = DIR_UP;
   g_trigger_core.active_start_time     = 0;
   g_trigger_core.active_start_bar_time = 0;
   g_trigger_core.active_context_id     = 0;
   g_trigger_core.active_zone_id        = 0;
   g_trigger_core.active_m1_window_id   = 0;
   g_trigger_apply_next_event           = ArraySize(g_trigger_events);
   g_trigger_apply_last_time            = stop_time;
   g_trigger_pending_refresh_time       = 0;
}

inline void Trigger_SetM15HardStop(const datetime stop_time, const bool terminal_stop_mode)
{
   if(stop_time > 0)
   {
      g_trigger_m15_hard_stop_enabled  = true;
      g_trigger_m15_hard_stop_time     = stop_time;
      g_trigger_m15_terminal_stop_mode = terminal_stop_mode;

      if(!terminal_stop_mode)
      {
         g_trigger_m15_finalize_requested = false;
         g_trigger_m15_finalize_time      = 0;
      }
   }
   else
   {
      g_trigger_m15_hard_stop_enabled     = false;
      g_trigger_m15_hard_stop_time        = 0;
      g_trigger_m15_terminal_stop_mode    = false;
      g_trigger_m15_finalize_requested    = false;
      g_trigger_m15_finalize_time         = 0;
   }
}

inline bool Trigger_M15HardStopEnabled()
{
   return g_trigger_m15_hard_stop_enabled;
}

inline datetime Trigger_M15HardStopTime()
{
   return g_trigger_m15_hard_stop_time;
}

inline bool Trigger_M15TerminalStopMode()
{
   return g_trigger_m15_terminal_stop_mode;
}

inline bool Trigger_M15HardStopFinalizeRequested()
{
   return g_trigger_m15_finalize_requested;
}

inline datetime Trigger_M15HardStopFinalizeTime()
{
   return g_trigger_m15_finalize_time;
}

inline bool __TRG_M15HardStopBeyondAllowed(const datetime t)
{
   if(!g_trigger_m15_hard_stop_enabled)
      return false;
   if(g_trigger_m15_hard_stop_time <= 0)
      return false;
   if(t <= 0)
      return false;

   // The configured stop time is the last M15 candle that is allowed to be
   // processed. Only bars AFTER it are blocked before processing.
   return (t > g_trigger_m15_hard_stop_time);
}

inline bool __TRG_M15HardStopFinalBarReached(const datetime t)
{
   if(!g_trigger_m15_hard_stop_enabled)
      return false;
   if(g_trigger_m15_hard_stop_time <= 0)
      return false;
   if(t <= 0)
      return false;

   return (t >= g_trigger_m15_hard_stop_time);
}

inline bool Trigger_M15HardStopReached(const datetime t)
{
   return __TRG_M15HardStopBeyondAllowed(t);
}

inline void Trigger_RequestM15HardStopFinalize(const datetime reached_time)
{
   if(!g_trigger_m15_hard_stop_enabled)
      return;
   if(g_trigger_m15_hard_stop_time <= 0)
      return;

   datetime use_time = reached_time;
   if(use_time <= 0 || use_time > g_trigger_m15_hard_stop_time)
      use_time = g_trigger_m15_hard_stop_time;

   g_trigger_m15_finalize_requested = true;
   g_trigger_m15_finalize_time      = use_time;
}

inline bool Trigger_M15HardStopShouldStopBeforeBar(const datetime t)
{
   if(g_trigger_m15_terminal_stop_mode)
      return true;

   if(g_trigger_m15_finalize_requested)
      return true;

   if(__TRG_M15HardStopBeyondAllowed(t))
   {
      Trigger_RequestM15HardStopFinalize(g_trigger_m15_hard_stop_time);
      return true;
   }

   return false;
}

inline void Trigger_M15HardStopMarkFinalBarIfNeeded(const datetime t)
{
   if(g_trigger_m15_terminal_stop_mode)
      return;

   if(__TRG_M15HardStopFinalBarReached(t))
      Trigger_RequestM15HardStopFinalize(t);
}

inline bool __TRG_M15HardStopBlocksProcessing(const datetime t)
{
   if(!g_trigger_m15_hard_stop_enabled)
      return false;

   if(g_trigger_m15_terminal_stop_mode)
      return true;

   return __TRG_M15HardStopBeyondAllowed(t);
}

inline void Trigger_FinalizeM15HardStop(const datetime stop_time)
{
   Trigger_SetM15HardStop(stop_time, true);

   if(stop_time <= 0)
      return;

   g_trigger_m15_finalize_requested = true;
   g_trigger_m15_finalize_time      = stop_time;
}

inline bool Trigger_AnyHistoricalHardStopFinalizeRequested()
{
   if(Trigger_M1HardStopFinalizeRequested())
      return true;
   if(Trigger_M15HardStopFinalizeRequested())
      return true;
   return false;
}

inline void Trigger_SetBridgeSafeUntil(const datetime safe_until_time)
{
   if(safe_until_time > 0)
   {
      g_trigger_bridge_safe_until_enabled = true;
      g_trigger_bridge_safe_until_time    = safe_until_time;
   }
   else
   {
      g_trigger_bridge_safe_until_enabled = false;
      g_trigger_bridge_safe_until_time    = 0;
   }
}

inline bool Trigger_BridgeSafeUntilEnabled()
{
   return g_trigger_bridge_safe_until_enabled;
}

inline datetime Trigger_BridgeSafeUntilTime()
{
   return g_trigger_bridge_safe_until_time;
}

inline bool Trigger_BridgeSafeUntilBlocksProcessing(const datetime bar_time)
{
   if(!g_trigger_bridge_safe_until_enabled)
      return false;
   if(g_trigger_bridge_safe_until_time <= 0)
      return false;
   if(bar_time <= 0)
      return false;

   return (bar_time > g_trigger_bridge_safe_until_time);
}

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
           kind == WB15_KIND_STOP_MINOROFF_ZONE ||
           kind == WB15_KIND_STOP_ZONE_INVALIDATED);
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
   s.context_id = 0;
   s.zone_id = 0;
   s.m1_window_id = 0;
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

inline datetime __TRG_EarliestEventBarTime()
{
   int n = ArraySize(g_trigger_events);
   if(n <= 0)
      return 0;

   datetime best = 0;
   for(int i=0; i<n; ++i)
   {
      datetime t = g_trigger_events[i].bar_time;
      if(t <= 0)
         continue;
      if(best <= 0 || t < best)
         best = t;
   }

   return best;
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
   g_trigger_core.active_context_id     = 0;
   g_trigger_core.active_zone_id        = 0;
   g_trigger_core.active_m1_window_id   = 0;

   g_trigger_core.last_processed_time   = 0;
   g_trigger_core.last_processed_idx    = -1;
   g_trigger_core.up_counter            = 0;
   g_trigger_core.dn_counter            = 0;

   g_trigger_symbol = "";
   ArrayResize(g_trigger_events, 0);
   g_trigger_pending_refresh_time = 0;
   g_trigger_apply_next_event = 0;
   g_trigger_apply_last_time  = 0;
   g_trigger_m1_hard_stop_enabled     = false;
   g_trigger_m1_hard_stop_time        = 0;
   g_trigger_m1_terminal_stop_mode    = false;
   g_trigger_m1_finalize_requested    = false;
   g_trigger_m1_finalize_time         = 0;

   g_trigger_m15_hard_stop_enabled    = false;
   g_trigger_m15_hard_stop_time       = 0;
   g_trigger_m15_terminal_stop_mode   = false;
   g_trigger_m15_finalize_requested   = false;
   g_trigger_m15_finalize_time        = 0;

   g_trigger_bridge_safe_until_enabled = false;
   g_trigger_bridge_safe_until_time    = 0;

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
      evt.context_id = 0;
      evt.zone_id = 0;
      evt.m1_window_id = i;

      const string kctx  = __WB15_Key(sym, "CTX_" + IntegerToString(i));
      const string kzone = __WB15_Key(sym, "ZONE_" + IntegerToString(i));
      const string kwin  = __WB15_Key(sym, "WIN_" + IntegerToString(i));
      if(GlobalVariableCheck(kctx))  evt.context_id = (int)GlobalVariableGet(kctx);
      if(GlobalVariableCheck(kzone)) evt.zone_id = (int)GlobalVariableGet(kzone);
      if(GlobalVariableCheck(kwin))  evt.m1_window_id = (int)GlobalVariableGet(kwin);
      if(evt.m1_window_id <= 0) evt.m1_window_id = i;

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
      g_trigger_core.active_context_id     = 0;
      g_trigger_core.active_zone_id        = 0;
      g_trigger_core.active_m1_window_id   = 0;
      __TRG_ResetWindowState();
      Flip_ResetGlobals();
      MajicFlip_ResetGlobals();
      TriggerSLTP_ResetGlobals();
      g_trigger_apply_next_event = 0;
      g_trigger_apply_last_time  = 0;
   }

   return true;
}

inline bool __TRG_SetActiveWindow(const bool      new_active,
                                  const int       new_start_seq,
                                  const int       new_start_kind,
                                  const int       new_start_ns,
                                  const Direction new_dir,
                                  const datetime  new_start_time,
                                  const datetime  new_start_bar,
                                  const int       new_context_id,
                                  const int       new_zone_id,
                                  const int       new_window_id,
                                  const datetime  event_bar_time,
                                  const bool      emit_logs)
{
   bool      old_active     = g_trigger_core.active;
   int       old_context_id = g_trigger_core.active_context_id;
   int       old_zone_id    = g_trigger_core.active_zone_id;
   int       old_window_id  = g_trigger_core.active_m1_window_id;
   Direction old_dir        = g_trigger_core.active_dir;

   bool changed = false;
   if(new_active     != g_trigger_core.active) changed = true;
   if(new_start_seq  != g_trigger_core.active_start_seq) changed = true;
   if(new_start_kind != g_trigger_core.active_start_kind) changed = true;
   if(new_start_ns   != g_trigger_core.active_start_ns) changed = true;
   if(new_dir        != g_trigger_core.active_dir) changed = true;
   if(new_start_time != g_trigger_core.active_start_time) changed = true;
   if(new_start_bar  != g_trigger_core.active_start_bar_time) changed = true;
   if(new_context_id != g_trigger_core.active_context_id) changed = true;
   if(new_zone_id    != g_trigger_core.active_zone_id) changed = true;
   if(new_window_id  != g_trigger_core.active_m1_window_id) changed = true;

   if(!changed)
      return false;

   g_trigger_core.active                = new_active;
   g_trigger_core.active_start_seq      = new_start_seq;
   g_trigger_core.active_start_kind     = new_start_kind;
   g_trigger_core.active_start_ns       = new_start_ns;
   g_trigger_core.active_dir            = new_dir;
   g_trigger_core.active_start_time     = new_start_time;
   g_trigger_core.active_start_bar_time = new_start_bar;
   g_trigger_core.active_context_id     = new_context_id;
   g_trigger_core.active_zone_id        = new_zone_id;
   g_trigger_core.active_m1_window_id   = new_window_id;

   __TRG_ResetWindowState();
   Flip_ResetGlobals();
   MajicFlip_ResetGlobals();

   if(emit_logs)
   {
      if(new_active)
      {
         WBLOG_LogStateTransition("Trigger", "M1_IDLE", "M1_WINDOW_ACTIVE", new_dir, new_context_id, new_zone_id, new_window_id, 0,
                                  "BRIDGE_START_RECEIVED", new_start_time, PERIOD_M1, (int)new_start_bar, 0.0, 0.0, 0.0, 0.0);
      }
      else if(old_active)
      {
         WBLOG_LogResetEvent("M1_WINDOW_RESET", old_dir, old_context_id, old_zone_id, old_window_id,
                             "BRIDGE_STOP_OR_NO_ACTIVE_SESSION", "M1_WINDOW_ACTIVE", "M1_IDLE", event_bar_time, PERIOD_M1, 0.0, 0.0, 0.0);
      }
   }

   return true;
}

inline bool __TRG_RecomputeWindowAt(const datetime bar_time, const bool emit_logs)
{
   bool      new_active     = false;
   int       new_start_seq  = -1;
   int       new_start_kind = 0;
   int       new_start_ns   = WB15_NS_NONE;
   Direction new_dir        = DIR_UP;
   datetime  new_start_time = 0;
   datetime  new_start_bar  = 0;
   int       new_context_id = 0;
   int       new_zone_id    = 0;
   int       new_window_id  = 0;

   const int evt_count = ArraySize(g_trigger_events);
   int next_pos = 0;

   for(int i=0; i<evt_count; ++i)
   {
      TriggerEvent evt = g_trigger_events[i];
      if(evt.bar_time > bar_time)
      {
         next_pos = i;
         break;
      }

      next_pos = i + 1;

      if(__TRG_IsStartKind(evt.kind))
      {
         new_active     = true;
         new_start_seq  = evt.seq;
         new_start_kind = evt.kind;
         new_start_ns   = evt.ns;
         new_dir        = evt.dir;
         new_start_time = evt.t;
         new_start_bar  = evt.bar_time;
         new_context_id = evt.context_id;
         new_zone_id    = evt.zone_id;
         new_window_id  = evt.m1_window_id;
      }
      else
      {
         TriggerStartSession sess;
         __TRG_ClearSession(sess);
         sess.active = new_active;
         sess.kind   = new_start_kind;
         sess.ns     = new_start_ns;
         sess.dir    = new_dir;
         if(__TRG_SessionMatchesStop(sess, evt.kind, evt.ns, evt.dir))
         {
            new_active     = false;
            new_start_seq  = -1;
            new_start_kind = 0;
            new_start_ns   = WB15_NS_NONE;
            new_dir        = DIR_UP;
            new_start_time = 0;
            new_start_bar  = 0;
            new_context_id = 0;
            new_zone_id    = 0;
            new_window_id  = 0;
         }
      }
   }

   if(evt_count <= 0)
      next_pos = 0;
   else if(next_pos > evt_count)
      next_pos = evt_count;

   g_trigger_apply_next_event = next_pos;
   g_trigger_apply_last_time  = bar_time;

   return __TRG_SetActiveWindow(new_active, new_start_seq, new_start_kind, new_start_ns, new_dir,
                                new_start_time, new_start_bar, new_context_id, new_zone_id,
                                new_window_id, bar_time, emit_logs);
}

inline bool __TRG_ApplyWindowAt(const datetime bar_time)
{
   if(bar_time <= 0)
      return false;

   const int evt_count = ArraySize(g_trigger_events);

   if(g_trigger_apply_next_event < 0 ||
      g_trigger_apply_next_event > evt_count ||
      (g_trigger_apply_last_time > 0 && bar_time < g_trigger_apply_last_time))
   {
      g_trigger_apply_next_event = 0;
      g_trigger_apply_last_time  = 0;
      return __TRG_RecomputeWindowAt(bar_time, false);
   }

   bool any_changed = false;

   while(g_trigger_apply_next_event < evt_count)
   {
      TriggerEvent evt = g_trigger_events[g_trigger_apply_next_event];
      if(evt.bar_time > bar_time)
         break;

      g_trigger_apply_next_event++;

      if(__TRG_IsStartKind(evt.kind))
      {
         if(__TRG_SetActiveWindow(true,
                                  evt.seq,
                                  evt.kind,
                                  evt.ns,
                                  evt.dir,
                                  evt.t,
                                  evt.bar_time,
                                  evt.context_id,
                                  evt.zone_id,
                                  evt.m1_window_id,
                                  evt.bar_time,
                                  true))
            any_changed = true;
      }
      else
      {
         TriggerStartSession sess;
         __TRG_ClearSession(sess);
         sess.active = g_trigger_core.active;
         sess.kind   = g_trigger_core.active_start_kind;
         sess.ns     = g_trigger_core.active_start_ns;
         sess.dir    = g_trigger_core.active_dir;

         if(__TRG_SessionMatchesStop(sess, evt.kind, evt.ns, evt.dir))
         {
            if(__TRG_SetActiveWindow(false,
                                     -1,
                                     0,
                                     WB15_NS_NONE,
                                     DIR_UP,
                                     0,
                                     0,
                                     0,
                                     0,
                                     0,
                                     evt.bar_time,
                                     true))
               any_changed = true;
         }
      }
   }

   g_trigger_apply_last_time = bar_time;
   return any_changed;
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

   WBLOG_SetCurrentTriggerContext(g_trigger_core.active_context_id,
                                  g_trigger_core.active_zone_id,
                                  g_trigger_core.active_m1_window_id,
                                  g_trigger_core.active_start_kind,
                                  g_trigger_core.active_start_ns,
                                  g_trigger_core.active_dir,
                                  g_trigger_core.active_start_time,
                                  g_trigger_core.active_start_bar_time);

   WBLOG_LogM1TriggerCandidate(type_id,
                               g_trigger_core.active_dir,
                               rates[hit_idx].time,
                               hit_idx,
                               rates[hit_idx].open,
                               rates[hit_idx].high,
                               rates[hit_idx].low,
                               rates[hit_idx].close,
                               g_trigger_core.active,
                               true,
                               "",
                               "Trigger.mqh");

   const int __trgsl_before = TriggerSLTP_RecordCount();

   TriggerSLTP_OnTriggerFired(sym,
                              g_trigger_core.active_dir,
                              type_id,
                              src_idx,
                              level,
                              hit_idx,
                              rates,
                              n);

   const bool __trgsl_record_added = (TriggerSLTP_RecordCount() > __trgsl_before);

   __TRG_DrawTriggerMarker(type_id,
                           rates[src_idx].time,
                           rates[hit_idx].time,
                           level);

   if(__trgsl_record_added && rates[hit_idx].time > g_trigger_pending_refresh_time)
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

   WBLOG_SetCurrentTriggerContext(g_trigger_core.active_context_id,
                                  g_trigger_core.active_zone_id,
                                  g_trigger_core.active_m1_window_id,
                                  g_trigger_core.active_start_kind,
                                  g_trigger_core.active_start_ns,
                                  g_trigger_core.active_dir,
                                  g_trigger_core.active_start_time,
                                  g_trigger_core.active_start_bar_time);

   WBLOG_LogM1TriggerCandidate(type_id,
                               g_trigger_core.active_dir,
                               rates[hit_idx].time,
                               hit_idx,
                               rates[hit_idx].open,
                               rates[hit_idx].high,
                               rates[hit_idx].low,
                               rates[hit_idx].close,
                               g_trigger_core.active,
                               true,
                               "",
                               (type_id == TRG_ENGINE_TYPE2 ? "Trigger_Type2.mqh" : "Trigger_Type1.mqh"));

   const int __trgsl_before = TriggerSLTP_RecordCount();

   TriggerSLTP_OnTriggerFired(sym,
                              g_trigger_core.active_dir,
                              type_id,
                              hit_idx,
                              entry_level,
                              hit_idx,
                              rates,
                              n);

   const bool __trgsl_record_added = (TriggerSLTP_RecordCount() > __trgsl_before);

   __TRG_DrawTriggerMarker(type_id,
                           rates[ref_idx].time,
                           rates[hit_idx].time,
                           entry_level);

   if(__trgsl_record_added && rates[hit_idx].time > g_trigger_pending_refresh_time)
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
                                   const int       bar_idx,
                                   const bool      force_reprocess=false)
{
   if(sym == "") return;
   g_trigger_symbol = sym;
   if(n <= 0 || bar_idx < 0 || bar_idx >= n) return;

   const datetime bar_time = rates[bar_idx].time;
   if(bar_time <= 0) return;
   if(__TRG_M1HardStopBlocksProcessing(bar_time))
   {
      TriggerStatement_ScheduledOutputMaybeAt(bar_time);
      return;
   }

   if(Trigger_BridgeSafeUntilBlocksProcessing(bar_time))
   {
      TriggerStatement_ScheduledOutputMaybeAt(g_trigger_bridge_safe_until_time);
      return;
   }

   if(!force_reprocess &&
      g_trigger_core.last_processed_time > 0 &&
      bar_time <= g_trigger_core.last_processed_time)
      return;

   WBLOG_LogCandleAndFeatures(sym, (ENUM_TIMEFRAMES)Period(), rates, n, bar_idx);
   bool window_changed = __TRG_ApplyWindowAt(bar_time);

   if(force_reprocess &&
      !window_changed &&
      g_trigger_core.last_processed_time > 0 &&
      bar_time <= g_trigger_core.last_processed_time)
   {
      TriggerStatement_ScheduledOutputMaybeAt(bar_time);
      return;
   }

   if(!g_trigger_core.active)
   {
      TriggerStatement_ScheduledOutputMaybeAt(bar_time);
      g_trigger_core.last_processed_time = bar_time;
      g_trigger_core.last_processed_idx  = bar_idx;
      return;
   }
   if(bar_time < g_trigger_core.active_start_bar_time)
   {
      TriggerStatement_ScheduledOutputMaybeAt(bar_time);
      g_trigger_core.last_processed_time = bar_time;
      g_trigger_core.last_processed_idx  = bar_idx;
      return;
   }

   g_trigger_pending_refresh_time = 0;

   WBLOG_SetCurrentTriggerContext(g_trigger_core.active_context_id,
                                  g_trigger_core.active_zone_id,
                                  g_trigger_core.active_m1_window_id,
                                  g_trigger_core.active_start_kind,
                                  g_trigger_core.active_start_ns,
                                  g_trigger_core.active_dir,
                                  g_trigger_core.active_start_time,
                                  g_trigger_core.active_start_bar_time);

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

   TriggerStatement_ScheduledOutputMaybeAt(bar_time);

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

   if(g_trigger_m1_terminal_stop_mode)
   {
      TriggerStatement_ScheduledOutputMaybeAt(g_trigger_m1_hard_stop_time);
      return;
   }

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
      seed_time = __TRG_EarliestEventBarTime();

   if(seed_time <= 0)
      return;

   if(g_trigger_bridge_safe_until_enabled &&
      g_trigger_bridge_safe_until_time > 0 &&
      g_trigger_core.last_processed_time > 0 &&
      g_trigger_core.last_processed_time >= g_trigger_bridge_safe_until_time)
   {
      TriggerStatement_ScheduledOutputMaybeAt(g_trigger_bridge_safe_until_time);
      return;
   }

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

   datetime to_time = TimeCurrent();
   if(g_trigger_bridge_safe_until_enabled &&
      g_trigger_bridge_safe_until_time > 0 &&
      g_trigger_bridge_safe_until_time < to_time)
      to_time = g_trigger_bridge_safe_until_time;

   if(g_trigger_m1_hard_stop_enabled &&
      g_trigger_m1_hard_stop_time > 0 &&
      g_trigger_m1_hard_stop_time < to_time)
      to_time = g_trigger_m1_hard_stop_time;

   if(to_time <= from_time)
      return;

   MqlRates rates[];
   int n = CopyRates(sym, (ENUM_TIMEFRAMES)Period(), from_time, to_time, rates);
   if(n <= 0)
      return;

   ArraySetAsSeries(rates, false);

   datetime last_closed_time = iTime(sym, (ENUM_TIMEFRAMES)Period(), 1);
   if(last_closed_time <= 0)
      return;

   if(g_trigger_bridge_safe_until_enabled &&
      g_trigger_bridge_safe_until_time > 0 &&
      g_trigger_bridge_safe_until_time < last_closed_time)
      last_closed_time = g_trigger_bridge_safe_until_time;

   if(g_trigger_m1_hard_stop_enabled &&
      g_trigger_m1_hard_stop_time > 0 &&
      g_trigger_m1_hard_stop_time < last_closed_time)
      last_closed_time = g_trigger_m1_hard_stop_time;

   for(int i = 0; i < n; ++i)
   {
      if(rates[i].time <= 0)
         continue;
      if(rates[i].time > last_closed_time)
         break;
      if(g_trigger_core.last_processed_time > 0 && rates[i].time <= g_trigger_core.last_processed_time)
         continue;

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

   const datetime bar_time = rates[bar_idx].time;
   if(bar_time <= 0) return;
   if(__TRG_M1HardStopBlocksProcessing(bar_time)) return;

   int previous_bridge_seq = g_trigger_core.bridge_seq;
   if(!__TRG_RebuildBridgeEvents(sym))
      return;

   bool bridge_changed = (previous_bridge_seq != g_trigger_core.bridge_seq);
   if(!bridge_changed &&
      g_trigger_core.last_processed_time > 0 &&
      bar_time <= g_trigger_core.last_processed_time)
   {
      return;
   }

   bool __unused_inside = insideHL[bar_idx];
   if(__unused_inside) { /* intentionally ignored */ }

   __TRG_ProcessLoadedBar(sym, rates, n, bar_idx, bridge_changed);
}

#endif // WAVEBOT_TRIGGER_MQH
