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
//   - Imported M15 "new" ON opens an M1 search window and carries the exact
//     same-moment M15 NEW-zone bounds.
//   - M1 waits for a same-direction HWX/HWBB/FSMS candle that is fully inside
//     that imported M15 NEW zone; after local expiry it may accept the next one.
//   - Only after that local reference is accepted, Trigger Type 1 = Flip.mqh
//     and Trigger Type 2 = Majicflip.mqh can become trades.
//   - A Flip/MajicFlip trigger must be closer to the accepted local reference
//     candle than to the relevant first-candle barrier.
//   - Each accepted local M1 HWX/HWBB/FSMS reference is valid for max 2
//     accepted trades only; after that, M1 must wait for the next local reference.
//   - If any MTC forms after the accepted local M1 reference, that local reference
//     is invalidated immediately and no further Flip/MajicFlip trigger may use it.
//   - Each imported M15 "new" signal is still retired after 4 actual trades.
//   - Legacy execution restrictions are disabled in TriggerStatement.mqh.
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
   double    zone_low;
   double    zone_high;
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
   double        active_zone_low;
   double        active_zone_high;

   int           active_trade_count;
   int           retired_start_seq;

   bool          local_ref_ready;
   int           local_ref_kind;
   int           local_ref_idx;
   int           local_ref_barrier_idx;
   datetime      local_ref_time;
   int           local_ref_trade_count;

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
   g_trigger_core.local_ref_ready       = false;
   g_trigger_core.local_ref_kind        = 0;
   g_trigger_core.local_ref_idx         = -1;
   g_trigger_core.local_ref_barrier_idx = -1;
   g_trigger_core.local_ref_time        = 0;
   g_trigger_core.local_ref_trade_count = 0;
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

inline void __TRG_ResetLocalM1Reference()
{
   g_trigger_core.local_ref_ready       = false;
   g_trigger_core.local_ref_kind        = 0;
   g_trigger_core.local_ref_idx         = -1;
   g_trigger_core.local_ref_barrier_idx = -1;
   g_trigger_core.local_ref_time        = 0;
   g_trigger_core.local_ref_trade_count = 0;
}

inline void __TRG_InvalidateLocalM1Reference(const string reason,
                                             const datetime t)
{
   if(!g_trigger_core.local_ref_ready)
      return;

   const datetime old_ref_time = g_trigger_core.local_ref_time;
   const int      old_ref_kind = g_trigger_core.local_ref_kind;
   const int      old_ref_trades = g_trigger_core.local_ref_trade_count;

   __TRG_ResetLocalM1Reference();
   Trigger_Type1_ResetGlobals();
   Trigger_Type2_ResetGlobals();
   Flip_ResetGlobals();
   MajicFlip_ResetGlobals();

   if(InpDebugPrints)
   {
      Print("[TRG-M1-REF] Invalidated local reference",
            " | reason=", reason,
            " | old_kind=", IntegerToString(old_ref_kind),
            " | old_ref=", TimeToString(old_ref_time, TIME_DATE|TIME_SECONDS),
            " | trades=", IntegerToString(old_ref_trades),
            " | event=", TimeToString(t, TIME_DATE|TIME_SECONDS));
   }
}

inline void __TRG_ResetWindowState()
{
   Trigger_Type1_ResetGlobals();
   Trigger_Type2_ResetGlobals();
   __TRG_ResetLocalM1Reference();
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
   g_trigger_core.active_zone_low       = 0.0;
   g_trigger_core.active_zone_high      = 0.0;

   g_trigger_core.active_trade_count    = 0;
   g_trigger_core.retired_start_seq     = -1;

   g_trigger_core.local_ref_ready       = false;
   g_trigger_core.local_ref_kind        = 0;
   g_trigger_core.local_ref_idx         = -1;
   g_trigger_core.local_ref_barrier_idx = -1;
   g_trigger_core.local_ref_time        = 0;
   g_trigger_core.local_ref_trade_count = 0;

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

      evt.zone_low  = 0.0;
      evt.zone_high = 0.0;

      const string kctx  = __WB15_Key(sym, "CTX_" + IntegerToString(i));
      const string kzone = __WB15_Key(sym, "ZONE_" + IntegerToString(i));
      const string kwin  = __WB15_Key(sym, "WIN_" + IntegerToString(i));
      const string kzl   = __WB15_Key(sym, "ZL_" + IntegerToString(i));
      const string kzh   = __WB15_Key(sym, "ZH_" + IntegerToString(i));
      if(GlobalVariableCheck(kctx))  evt.context_id = (int)GlobalVariableGet(kctx);
      if(GlobalVariableCheck(kzone)) evt.zone_id = (int)GlobalVariableGet(kzone);
      if(GlobalVariableCheck(kwin))  evt.m1_window_id = (int)GlobalVariableGet(kwin);
      if(GlobalVariableCheck(kzl))   evt.zone_low = GlobalVariableGet(kzl);
      if(GlobalVariableCheck(kzh))   evt.zone_high = GlobalVariableGet(kzh);
      if(evt.zone_high < evt.zone_low)
      {
         double tmpz = evt.zone_high;
         evt.zone_high = evt.zone_low;
         evt.zone_low = tmpz;
      }
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
      g_trigger_core.active_zone_low       = 0.0;
      g_trigger_core.active_zone_high      = 0.0;
      g_trigger_core.active_trade_count    = 0;
      g_trigger_core.retired_start_seq     = -1;
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
                                  const double    new_zone_low,
                                  const double    new_zone_high,
                                  const datetime  event_bar_time,
                                  const bool      emit_logs)
{
   bool      old_active     = g_trigger_core.active;
   int       old_context_id = g_trigger_core.active_context_id;
   int       old_zone_id    = g_trigger_core.active_zone_id;
   int       old_window_id  = g_trigger_core.active_m1_window_id;
   Direction old_dir        = g_trigger_core.active_dir;

   bool      eff_active     = new_active;
   int       eff_start_seq  = new_start_seq;
   int       eff_start_kind = new_start_kind;
   int       eff_start_ns   = new_start_ns;
   Direction eff_dir        = new_dir;
   datetime  eff_start_time = new_start_time;
   datetime  eff_start_bar  = new_start_bar;
   int       eff_context_id = new_context_id;
   int       eff_zone_id    = new_zone_id;
   int       eff_window_id  = new_window_id;
   double    eff_zone_low   = new_zone_low;
   double    eff_zone_high  = new_zone_high;

   if(eff_zone_high < eff_zone_low)
   {
      double tmpz = eff_zone_high;
      eff_zone_high = eff_zone_low;
      eff_zone_low = tmpz;
   }

   // A M15 "new" window is retired after 4 actual trades. Historical window
   // recomputation must not revive the same start sequence again.
   if(eff_active && eff_start_seq == g_trigger_core.retired_start_seq)
   {
      eff_active     = false;
      eff_start_seq  = -1;
      eff_start_kind = 0;
      eff_start_ns   = WB15_NS_NONE;
      eff_dir        = DIR_UP;
      eff_start_time = 0;
      eff_start_bar  = 0;
      eff_context_id = 0;
      eff_zone_id    = 0;
      eff_window_id  = 0;
      eff_zone_low   = 0.0;
      eff_zone_high  = 0.0;
   }

   bool changed = false;
   if(eff_active     != g_trigger_core.active) changed = true;
   if(eff_start_seq  != g_trigger_core.active_start_seq) changed = true;
   if(eff_start_kind != g_trigger_core.active_start_kind) changed = true;
   if(eff_start_ns   != g_trigger_core.active_start_ns) changed = true;
   if(eff_dir        != g_trigger_core.active_dir) changed = true;
   if(eff_start_time != g_trigger_core.active_start_time) changed = true;
   if(eff_start_bar  != g_trigger_core.active_start_bar_time) changed = true;
   if(eff_context_id != g_trigger_core.active_context_id) changed = true;
   if(eff_zone_id    != g_trigger_core.active_zone_id) changed = true;
   if(eff_window_id  != g_trigger_core.active_m1_window_id) changed = true;
   if(eff_zone_low   != g_trigger_core.active_zone_low) changed = true;
   if(eff_zone_high  != g_trigger_core.active_zone_high) changed = true;

   if(!changed)
      return false;

   const int old_start_seq = g_trigger_core.active_start_seq;

   g_trigger_core.active                = eff_active;
   g_trigger_core.active_start_seq      = eff_start_seq;
   g_trigger_core.active_start_kind     = eff_start_kind;
   g_trigger_core.active_start_ns       = eff_start_ns;
   g_trigger_core.active_dir            = eff_dir;
   g_trigger_core.active_start_time     = eff_start_time;
   g_trigger_core.active_start_bar_time = eff_start_bar;
   g_trigger_core.active_context_id     = eff_context_id;
   g_trigger_core.active_zone_id        = eff_zone_id;
   g_trigger_core.active_m1_window_id   = eff_window_id;
   g_trigger_core.active_zone_low       = eff_zone_low;
   g_trigger_core.active_zone_high      = eff_zone_high;

   if(eff_active && eff_start_seq != old_start_seq)
      g_trigger_core.active_trade_count = 0;
   if(!eff_active)
      g_trigger_core.active_trade_count = 0;

   __TRG_ResetWindowState();
   Flip_ResetGlobals();
   MajicFlip_ResetGlobals();

   if(emit_logs)
   {
      if(eff_active)
      {
         WBLOG_LogStateTransition("Trigger", "M1_IDLE", "M1_WINDOW_ACTIVE", eff_dir, eff_context_id, eff_zone_id, eff_window_id, 0,
                                  "BRIDGE_START_RECEIVED", eff_start_time, PERIOD_M1, (int)eff_start_bar, eff_zone_low, eff_zone_high, 0.0, 0.0);
      }
      else if(old_active)
      {
         WBLOG_LogResetEvent("M1_WINDOW_RESET", old_dir, old_context_id, old_zone_id, old_window_id,
                             "BRIDGE_STOP_OR_LIMIT", "M1_WINDOW_ACTIVE", "M1_IDLE", event_bar_time, PERIOD_M1, 0.0, 0.0, 0.0);
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
   double    new_zone_low   = 0.0;
   double    new_zone_high  = 0.0;

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
         new_zone_low   = evt.zone_low;
         new_zone_high  = evt.zone_high;
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
            new_zone_low   = 0.0;
            new_zone_high  = 0.0;
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
                                new_window_id, new_zone_low, new_zone_high, bar_time, emit_logs);
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
                                  evt.zone_low,
                                  evt.zone_high,
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
                                     0.0,
                                     0.0,
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


inline string __TRG_LocalRefKindName(const int kind)
{
   if(kind == WB15_KIND_START_HWX)  return "HWX";
   if(kind == WB15_KIND_START_HWBB) return "HWBB";
   if(kind == WB15_KIND_START_FSMS) return "FSMS";
   return "UNKNOWN";
}

inline double __TRG_AbsD(const double v)
{
   return (v < 0.0 ? -v : v);
}

inline double __TRG_DistanceToCandleRange(const double price,
                                          const MqlRates &bar)
{
   if(price >= bar.low && price <= bar.high)
      return 0.0;

   if(price < bar.low)
      return (bar.low - price);

   return (price - bar.high);
}

inline bool __TRG_ActiveNewZoneIsUsable()
{
   if(g_trigger_core.active_zone_high < g_trigger_core.active_zone_low)
      return false;

   return (g_trigger_core.active_zone_high > g_trigger_core.active_zone_low + (2.0 * _Point));
}

inline bool __TRG_BarFullyInsideActiveNewZone(const MqlRates &bar)
{
   if(!__TRG_ActiveNewZoneIsUsable())
      return false;

   double bottom = g_trigger_core.active_zone_low;
   double top    = g_trigger_core.active_zone_high;
   if(top < bottom)
   {
      double tmp = top;
      top = bottom;
      bottom = tmp;
   }

   double eps = 2.0 * _Point;
   if(eps <= 0.0)
      eps = 0.00000001;

   return (bar.low >= bottom - eps && bar.high <= top + eps);
}

inline bool __TRG_LocalReferenceDistanceOK(const MqlRates &rates[],
                                           const int n,
                                           const int hit_idx,
                                           string &why)
{
   why = "";

   if(!g_trigger_core.local_ref_ready)
   {
      why = "NO_M1_HWX_HWBB_FSMS_REFERENCE";
      return false;
   }

   if(hit_idx < 0 || hit_idx >= n)
   {
      why = "BAD_TRIGGER_INDEX";
      return false;
   }

   const int ref_idx = g_trigger_core.local_ref_idx;
   const int barrier_idx = g_trigger_core.local_ref_barrier_idx;

   if(ref_idx < 0 || ref_idx >= n)
   {
      why = "BAD_LOCAL_REFERENCE_INDEX";
      return false;
   }

   if(barrier_idx < 0 || barrier_idx >= n)
   {
      why = "BAD_LOCAL_BARRIER_INDEX";
      return false;
   }

   if(rates[hit_idx].time <= g_trigger_core.local_ref_time)
   {
      why = "TRIGGER_NOT_AFTER_LOCAL_REFERENCE";
      return false;
   }

   const double entry_level = rates[hit_idx].close;
   const double ref_dist    = __TRG_DistanceToCandleRange(entry_level, rates[ref_idx]);
   const double barrier     = (g_trigger_core.active_dir == DIR_UP ? rates[barrier_idx].high : rates[barrier_idx].low);
   const double barrier_dist= __TRG_AbsD(entry_level - barrier);

   double eps = 2.0 * _Point;
   if(eps <= 0.0)
      eps = 0.00000001;

   if(ref_dist <= barrier_dist + eps)
      return true;

   why = "TRIGGER_FARTHER_FROM_M1_REFERENCE_THAN_WAVE_FIRST_CANDLE";
   return false;
}

inline void __TRG_DrawLocalReferenceMarker(const int ref_kind,
                                           const Direction dir,
                                           const MqlRates &bar,
                                           const int start_seq)
{
   if(!InpDrawMarkers)
      return;

   double span = bar.high - bar.low;
   if(span <= 0.0)
      span = 10.0 * _Point;

   double pad = span * 0.42;
   if(pad < 6.0 * _Point)
      pad = 6.0 * _Point;

   const double y = (dir == DIR_UP ? bar.high + pad : bar.low - pad);

   string dir_tag = (dir == DIR_UP ? "U" : "D");
   string base = "TRG_M1_REF_" + IntegerToString(start_seq) + "_" + dir_tag + "_" +
                 __TRG_LocalRefKindName(ref_kind) + "_" + IntegerToString((long)bar.time);

   __TRG_DrawTextUnique(base, bar.time, y, "M1 " + __TRG_LocalRefKindName(ref_kind), clrGold, 9);
}

inline bool Trigger_M1LocalGateRegister(const Direction dir,
                                        const int       ref_kind,
                                        const MqlRates &rates[],
                                        const int       n,
                                        const int       ref_idx,
                                        const int       barrier_idx)
{
   if(!__TRG_IsWorkerTF()) return false;
   if(!__TRG_IsMajorWorld()) return false;
   if(n <= 0) return false;
   if(ref_idx < 0 || ref_idx >= n) return false;
   if(barrier_idx < 0 || barrier_idx >= n) return false;

   if(ref_kind != WB15_KIND_START_HWX &&
      ref_kind != WB15_KIND_START_HWBB &&
      ref_kind != WB15_KIND_START_FSMS)
      return false;

   const datetime ref_time = rates[ref_idx].time;
   if(ref_time <= 0) return false;

   if(!g_trigger_core.active)
      return false;

   if(g_trigger_core.active_start_seq == g_trigger_core.retired_start_seq)
      return false;

   if(g_trigger_core.active_trade_count >= 4)
      return false;

   if(g_trigger_core.local_ref_ready)
      return false;

   if(dir != g_trigger_core.active_dir)
      return false;

   if(ref_time < g_trigger_core.active_start_bar_time)
      return false;

   if(!__TRG_BarFullyInsideActiveNewZone(rates[ref_idx]))
      return false;

   g_trigger_core.local_ref_ready       = true;
   g_trigger_core.local_ref_kind        = ref_kind;
   g_trigger_core.local_ref_idx         = ref_idx;
   g_trigger_core.local_ref_barrier_idx = barrier_idx;
   g_trigger_core.local_ref_time        = ref_time;
   g_trigger_core.local_ref_trade_count = 0;

   Trigger_Type1_ResetGlobals();
   Trigger_Type2_ResetGlobals();
   Flip_ResetGlobals();
   MajicFlip_ResetGlobals();

   __TRG_DrawLocalReferenceMarker(ref_kind, dir, rates[ref_idx], g_trigger_core.active_start_seq);

   if(InpDebugPrints)
   {
      Print("[TRG-M1-REF] Accepted first local ", __TRG_LocalRefKindName(ref_kind),
            " | dir=", (dir == DIR_UP ? "UP" : "DOWN"),
            " | ref=", TimeToString(ref_time, TIME_DATE|TIME_SECONDS),
            " | barrier=", TimeToString(rates[barrier_idx].time, TIME_DATE|TIME_SECONDS),
            " | M15-new-zone=", DoubleToString(g_trigger_core.active_zone_low, _Digits),
            "..", DoubleToString(g_trigger_core.active_zone_high, _Digits));
   }

   return true;
}

inline bool Trigger_M1LocalGateOnMTC(const Direction mtc_dir,
                                     const datetime  mtc_time)
{
   if(!__TRG_IsWorkerTF()) return false;
   if(!__TRG_IsMajorWorld()) return false;
   if(mtc_time <= 0) return false;
   if(!g_trigger_core.active) return false;
   if(!g_trigger_core.local_ref_ready) return false;

   // Any MTC formed after the accepted M1 HWX/HWBB/FSMS reference invalidates
   // that local reference. No Flip/MajicFlip trigger on or after the MTC candle
   // may remain connected to it.
   if(mtc_time <= g_trigger_core.local_ref_time)
      return false;

   int removed = TriggerSLTP_RemoveRecordsAtOrAfter(mtc_time,
                                                    g_trigger_core.active_context_id,
                                                    g_trigger_core.active_zone_id,
                                                    g_trigger_core.active_m1_window_id);

   if(removed > 0)
   {
      g_trigger_core.active_trade_count -= removed;
      if(g_trigger_core.active_trade_count < 0)
         g_trigger_core.active_trade_count = 0;

      g_trigger_core.local_ref_trade_count -= removed;
      if(g_trigger_core.local_ref_trade_count < 0)
         g_trigger_core.local_ref_trade_count = 0;

      if(mtc_time > g_trigger_pending_refresh_time)
         g_trigger_pending_refresh_time = mtc_time;

      if(InpDebugPrints)
      {
         Print("[TRG-M1-REF] Removed trigger record(s) created on/after MTC",
               " | removed=", IntegerToString(removed),
               " | mtc_dir=", (mtc_dir == DIR_UP ? "UP" : "DOWN"),
               " | mtc=", TimeToString(mtc_time, TIME_DATE|TIME_SECONDS));
      }
   }

   __TRG_InvalidateLocalM1Reference("MTC_AFTER_LOCAL_REFERENCE", mtc_time);
   return true;
}

inline bool __TRG_CanAcceptPatternTrigger(const int       type_id,
                                          const int       hit_idx,
                                          const MqlRates &rates[],
                                          const int       n)
{
   if(!g_trigger_core.active)
      return false;

   if(g_trigger_core.active_start_seq == g_trigger_core.retired_start_seq)
      return false;

   if(g_trigger_core.active_trade_count >= 4)
      return false;

   if(g_trigger_core.local_ref_trade_count >= 2)
      return false;

   string reason = "";
   if(!__TRG_LocalReferenceDistanceOK(rates, n, hit_idx, reason))
   {
      if(InpDebugPrints && reason != "")
      {
         Print("[TRG-M1-GATE] Skip ", __TRG_EngineTag(type_id),
               " | reason=", reason,
               " | t=", (hit_idx >= 0 && hit_idx < n ? TimeToString(rates[hit_idx].time, TIME_DATE|TIME_SECONDS) : "n/a"));
      }
      return false;
   }

   return true;
}

inline void __TRG_RetireActiveWindowAfterTradeLimit(const datetime t)
{
   if(!g_trigger_core.active)
      return;

   g_trigger_core.retired_start_seq = g_trigger_core.active_start_seq;

   __TRG_SetActiveWindow(false,
                         -1,
                         0,
                         WB15_NS_NONE,
                         DIR_UP,
                         0,
                         0,
                         0,
                         0,
                         0,
                         0.0,
                         0.0,
                         t,
                         true);
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

   if(!__TRG_CanAcceptPatternTrigger(type_id, hit_idx, rates, n))
      return;

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
                              ref_idx,
                              entry_level,
                              hit_idx,
                              rates,
                              n);

   const bool __trgsl_record_added = (TriggerSLTP_RecordCount() > __trgsl_before);

   __TRG_DrawTriggerMarker(type_id,
                           rates[ref_idx].time,
                           rates[hit_idx].time,
                           entry_level);

   if(__trgsl_record_added)
   {
      g_trigger_core.active_trade_count++;
      g_trigger_core.local_ref_trade_count++;

      if(rates[hit_idx].time > g_trigger_pending_refresh_time)
         g_trigger_pending_refresh_time = rates[hit_idx].time;

      if(g_trigger_core.active_trade_count >= 4)
      {
         __TRG_RetireActiveWindowAfterTradeLimit(rates[hit_idx].time);
      }
      else
      if(g_trigger_core.local_ref_trade_count >= 2)
      {
         __TRG_InvalidateLocalM1Reference("LOCAL_REFERENCE_TWO_TRADE_LIMIT", rates[hit_idx].time);
      }
   }
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
      return;
   }
   if(bar_time < g_trigger_core.active_start_bar_time)
   {
      TriggerStatement_ScheduledOutputMaybeAt(bar_time);
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

   if(!g_trigger_core.local_ref_ready || g_trigger_core.active_trade_count >= 4)
   {
      TriggerStatement_ScheduledOutputMaybeAt(bar_time);
      g_trigger_core.last_processed_time = bar_time;
      g_trigger_core.last_processed_idx  = bar_idx;
      return;
   }

   datetime from_time = g_trigger_core.local_ref_time;
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

   if(g_trigger_m1_hard_stop_enabled)
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
