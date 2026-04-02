
#ifndef WAVEBOT_TRIGGER_MQH
#define WAVEBOT_TRIGGER_MQH

#include <WaveBot/Types.mqh>
#include <WaveBot/Markers.mqh>
#include <WaveBot/WB15_SignalBridge.mqh>

// ============================================================================
// Trigger.mqh
// Independent trigger engine driven only by the H4->worker bridge and
// worker-TF candles. It must remain fully passive relative to the normal
// wave/candle engine.
//
// Core rules implemented:
//   - Start only after an effective H4 START signal reaches the worker bar.
//   - Stop immediately when the effective H4 window is no longer active.
//   - Max 3 triggers per active H4 window.
//   - A mother boundary (bullish = mother low, bearish = mother high) governs
//     the whole trigger cycle.
//   - Inside one mother range, multiple gates can be open simultaneously.
//   - Type-1 and Type-2 are evaluated in parallel on every gate.
//   - If multiple gates hit on the same bar, the latest-created gate wins.
//   - All logic is candle-by-candle, wick/body agnostic for the final break.
//   - API rewinds / duplicate bar calls must not reset the trigger engine.
// ============================================================================

#define TRG_MAX_ACTIVE_SESSIONS  32
#define TRG_MAX_CLOSED_LEGS       8
#define TRG_MAX_HITS_PER_WINDOW   3

enum TriggerLegDir
{
   TRG_LEG_NONE = 0,
   TRG_LEG_UP   = 1,
   TRG_LEG_DN   = -1
};

struct TriggerEvent
{
   datetime  t;         // raw bridge time
   datetime  bar_time;  // effective worker-TF bar open time
   Direction dir;
   int       kind;
   int       ns;
   int       seq;
};

struct TriggerLeg
{
   bool   used;
   int    dir;
   int    start_idx;
   int    end_idx;

   double high;
   int    high_idx;

   double low;
   int    low_idx;
};

struct TriggerGate
{
   bool     used;
   int      serial;
   int      birth_idx;
   datetime birth_time;

   // base boundary for this gate
   double   base_level;   // bullish: floor | bearish: roof
   int      base_idx;

   // Phase-1 / Phase-2 stored levels
   double   phase1_level; // bullish: ceiling-1 | bearish: floor-1
   int      phase1_idx;

   double   phase2_level; // bullish: floor-2   | bearish: roof-2
   int      phase2_idx;

   // Type-1 path
   bool     type1_possible;
   bool     type1_middle_seen;
   bool     type1_arm_final;
   double   type1_target;
   int      type1_src_idx;
   int      type1_arm_idx;

   // Type-2 path
   bool     type2_possible;
   bool     type2_break1_seen;
   double   phase3_level; // bullish: ceiling-3 | bearish: floor-3
   int      phase3_idx;
   bool     type2_arm_final;
   double   type2_target;
   int      type2_src_idx;
   int      type2_arm_idx;
};

struct TriggerHitCandidate
{
   bool   hit;
   int    gate_index;
   int    gate_serial;
   int    gate_birth_idx;
   int    type_id;
   int    bar_idx;
   double level;
   int    src_idx;
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
   // bridge snapshot
   double        run_id;
   int           bridge_seq;

   // active worker window
   bool          active;
   int           active_start_seq;
   int           active_start_kind;
   int           active_start_ns;
   Direction     active_dir;
   datetime      active_start_time;
   datetime      active_start_bar_time;

   // independent trigger engine state
   int           window_hit_count;

   bool          mother_set;
   double        mother_level;  // bullish: mother low | bearish: mother high
   int           mother_idx;
   datetime      mother_time;

   int           gate_serial_seq;

   TriggerLeg    closed_legs[TRG_MAX_CLOSED_LEGS];
   int           closed_count;
   TriggerLeg    current_leg;
   bool          current_leg_active;

   // dedupe / rewind shield
   datetime      last_processed_time;
   int           last_processed_idx;

   // marker counters
   int           up_counter;
   int           dn_counter;
};

static TriggerCore g_trigger_ctx;
static TriggerEvent g_trigger_events[];
static TriggerGate  g_trigger_gates[];

// ----------------------------------------------------------------------------
// Basic helpers
// ----------------------------------------------------------------------------
inline bool __TRG_IsWorkerTF()
{
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Period();
   return (tf == PERIOD_M15 || tf == PERIOD_M1);
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

inline bool __TRG_TouchHigh(const double high_price, const double level)
{
   return (high_price >= (level - __TRG_Eps()));
}

inline bool __TRG_TouchLow(const double low_price, const double level)
{
   return (low_price <= (level + __TRG_Eps()));
}

inline bool __TRG_BreakAboveStrict(const double high_price, const double level)
{
   return (high_price > (level + __TRG_Eps()));
}

inline bool __TRG_BreakBelowStrict(const double low_price, const double level)
{
   return (low_price < (level - __TRG_Eps()));
}

inline datetime __TRG_WorkerBarOpen(const datetime t)
{
   int sec = PeriodSeconds((ENUM_TIMEFRAMES)Period());
   if(sec <= 0) sec = 60;

   long ts = (long)t;
   long ss = (long)sec;
   return (datetime)(ts - (ts % ss));
}

inline int __TRG_CandleDir(const MqlRates &bar)
{
   if(bar.close > bar.open) return TRG_LEG_UP;
   if(bar.close < bar.open) return TRG_LEG_DN;
   return TRG_LEG_NONE;
}

// ----------------------------------------------------------------------------
// Clear / reset helpers
// ----------------------------------------------------------------------------
inline void __TRG_ClearLeg(TriggerLeg &leg)
{
   leg.used      = false;
   leg.dir       = TRG_LEG_NONE;
   leg.start_idx = -1;
   leg.end_idx   = -1;
   leg.high      = 0.0;
   leg.high_idx  = -1;
   leg.low       = 0.0;
   leg.low_idx   = -1;
}

inline void __TRG_ClearGate(TriggerGate &gate)
{
   gate.used             = false;
   gate.serial           = 0;
   gate.birth_idx        = -1;
   gate.birth_time       = 0;

   gate.base_level       = 0.0;
   gate.base_idx         = -1;

   gate.phase1_level     = 0.0;
   gate.phase1_idx       = -1;
   gate.phase2_level     = 0.0;
   gate.phase2_idx       = -1;

   gate.type1_possible   = true;
   gate.type1_middle_seen= false;
   gate.type1_arm_final  = false;
   gate.type1_target     = 0.0;
   gate.type1_src_idx    = -1;
   gate.type1_arm_idx    = -1;

   gate.type2_possible   = true;
   gate.type2_break1_seen= false;
   gate.phase3_level     = 0.0;
   gate.phase3_idx       = -1;
   gate.type2_arm_final  = false;
   gate.type2_target     = 0.0;
   gate.type2_src_idx    = -1;
   gate.type2_arm_idx    = -1;
}

inline void __TRG_ClearHitCandidate(TriggerHitCandidate &hit)
{
   hit.hit            = false;
   hit.gate_index     = -1;
   hit.gate_serial    = 0;
   hit.gate_birth_idx = -1;
   hit.type_id        = 0;
   hit.bar_idx        = -1;
   hit.level          = 0.0;
   hit.src_idx        = -1;
}

inline void __TRG_ClearAllGates()
{
   ArrayResize(g_trigger_gates, 0);
}

inline void __TRG_ResetLegsOnly()
{
   for(int i=0; i<TRG_MAX_CLOSED_LEGS; ++i)
      __TRG_ClearLeg(g_trigger_ctx.closed_legs[i]);

   g_trigger_ctx.closed_count       = 0;
   g_trigger_ctx.current_leg_active = false;
   __TRG_ClearLeg(g_trigger_ctx.current_leg);
}

inline void __TRG_ResetWindowState(const bool reset_hit_count)
{
   __TRG_ClearAllGates();
   __TRG_ResetLegsOnly();

   g_trigger_ctx.mother_set   = false;
   g_trigger_ctx.mother_level = 0.0;
   g_trigger_ctx.mother_idx   = -1;
   g_trigger_ctx.mother_time  = 0;

   g_trigger_ctx.last_processed_time = 0;
   g_trigger_ctx.last_processed_idx  = -1;

   g_trigger_ctx.gate_serial_seq     = 0;
   if(reset_hit_count)
      g_trigger_ctx.window_hit_count = 0;
}

inline void __TRG_ResetForNewMother(const MqlRates &rates[], const int bar_idx)
{
   __TRG_ClearAllGates();
   __TRG_ResetLegsOnly();

   g_trigger_ctx.mother_set  = true;
   g_trigger_ctx.mother_idx  = bar_idx;
   g_trigger_ctx.mother_time = rates[bar_idx].time;
   g_trigger_ctx.mother_level = (g_trigger_ctx.active_dir == DIR_UP ? rates[bar_idx].low
                                                                    : rates[bar_idx].high);
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

   g_trigger_ctx.window_hit_count      = 0;
   g_trigger_ctx.mother_set            = false;
   g_trigger_ctx.mother_level          = 0.0;
   g_trigger_ctx.mother_idx            = -1;
   g_trigger_ctx.mother_time           = 0;

   g_trigger_ctx.gate_serial_seq       = 0;
   g_trigger_ctx.last_processed_time   = 0;
   g_trigger_ctx.last_processed_idx    = -1;

   g_trigger_ctx.up_counter            = 0;
   g_trigger_ctx.dn_counter            = 0;

   __TRG_ResetLegsOnly();
   ArrayResize(g_trigger_events, 0);
   ArrayResize(g_trigger_gates, 0);
}

// ----------------------------------------------------------------------------
// Bridge event helpers
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
   if(sess.kind != WB15_KIND_START_FSMS)
      return false;

   if(new_kind != WB15_KIND_START_HWX && new_kind != WB15_KIND_START_HWBB)
      return false;

   return (sess.ns == new_ns);
}

inline bool __TRG_SessionMatchesStop(const TriggerStartSession &sess,
                                     const int stop_kind,
                                     const int stop_ns,
                                     const Direction stop_dir)
{
   if(!sess.active) return false;
   if(stop_dir != __WB15_Opposite(sess.dir)) return false;

   if(sess.kind == WB15_KIND_START_FSMS)
   {
      if(sess.ns == WB15_NS_MAJ)
      {
         if(stop_ns != WB15_NS_MAJ) return false;
         return (stop_kind == WB15_KIND_STOP_MINORSTARTER || stop_kind == WB15_KIND_STOP_MTC);
      }

      if(sess.ns == WB15_NS_MIN)
      {
         if(stop_kind != WB15_KIND_STOP_MTC) return false;
         return (stop_ns == WB15_NS_MIN || stop_ns == WB15_NS_MAJ);
      }

      return false;
   }

   if(stop_kind == WB15_KIND_STOP_MINOROFF_ZONE)
      return (sess.ns == WB15_NS_MIN && stop_ns == WB15_NS_MAJ);

   if(stop_kind != WB15_KIND_STOP_MTC)
      return false;

   if(sess.ns == WB15_NS_MAJ)
      return (stop_ns == WB15_NS_MAJ);

   if(sess.ns == WB15_NS_MIN)
      return (stop_ns == WB15_NS_MIN || stop_ns == WB15_NS_MAJ);

   return false;
}

inline bool __TRG_LoadBridgeEvents(const string sym)
{
   const string kRun = __WB15_Key(sym, "RUN");
   const string kSeq = __WB15_Key(sym, "SEQ");

   if(!GlobalVariableCheck(kRun) || !GlobalVariableCheck(kSeq))
      return false;

   const double run_id = GlobalVariableGet(kRun);
   const int    seq    = (int)GlobalVariableGet(kSeq);

   if(run_id <= 0.0 || seq < 0)
      return false;

   if(g_trigger_ctx.run_id == run_id && g_trigger_ctx.bridge_seq == seq)
      return true;

   g_trigger_ctx.run_id     = run_id;
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

   g_trigger_ctx.active                = false;
   g_trigger_ctx.active_start_seq      = -1;
   g_trigger_ctx.active_start_kind     = 0;
   g_trigger_ctx.active_start_ns       = WB15_NS_NONE;
   g_trigger_ctx.active_dir            = DIR_UP;
   g_trigger_ctx.active_start_time     = 0;
   g_trigger_ctx.active_start_bar_time = 0;

   __TRG_ResetWindowState(true);
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
         {
            if(sessions[s].active && __TRG_ShouldAutoStopOnNewStart(sessions[s], evt.kind, evt.ns))
               sessions[s].active = false;
         }

         if(session_count < TRG_MAX_ACTIVE_SESSIONS)
         {
            sessions[session_count].active   = true;
            sessions[session_count].kind     = evt.kind;
            sessions[session_count].ns       = evt.ns;
            sessions[session_count].dir      = evt.dir;
            sessions[session_count].t        = evt.t;
            sessions[session_count].bar_time = evt.bar_time;
            sessions[session_count].seq      = evt.seq;
            session_count++;
         }
         else
         {
            for(int k=1; k<TRG_MAX_ACTIVE_SESSIONS; ++k)
               sessions[k-1] = sessions[k];

            const int last = TRG_MAX_ACTIVE_SESSIONS - 1;
            sessions[last].active   = true;
            sessions[last].kind     = evt.kind;
            sessions[last].ns       = evt.ns;
            sessions[last].dir      = evt.dir;
            sessions[last].t        = evt.t;
            sessions[last].bar_time = evt.bar_time;
            sessions[last].seq      = evt.seq;
            session_count = TRG_MAX_ACTIVE_SESSIONS;
         }
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
      __TRG_ResetWindowState(true);
}

// ----------------------------------------------------------------------------
// Marker helpers
// ----------------------------------------------------------------------------
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

inline void __TRG_DrawMarker(const int type_id,
                             const int gate_serial,
                             const datetime ref_t,
                             const datetime hit_t,
                             const double level)
{
   string dir_tag = (g_trigger_ctx.active_dir == DIR_UP ? "U" : "D");
   string seq_tag = IntegerToString(g_trigger_ctx.active_start_seq);
   string hit_tag = IntegerToString(g_trigger_ctx.window_hit_count + 1);
   string gate_tag= IntegerToString(gate_serial);
   string type_tag= IntegerToString(type_id);
   string base = StringFormat("TRG_%s_%s_%s_%s_%s", dir_tag, seq_tag, hit_tag, gate_tag, type_tag);

   __TRG_DrawDashedLine(base + "_L", ref_t, hit_t, level, clrYellow);
   __TRG_DrawTextUnique(base + "_T", hit_t, level, "T", clrYellow, 10);
}

// ----------------------------------------------------------------------------
// Leg processing / gate creation
// ----------------------------------------------------------------------------
inline void __TRG_StartCurrentLeg(const int dir,
                                  const int idx,
                                  const double hi,
                                  const double lo)
{
   g_trigger_ctx.current_leg_active   = true;
   g_trigger_ctx.current_leg.used     = true;
   g_trigger_ctx.current_leg.dir      = dir;
   g_trigger_ctx.current_leg.start_idx= idx;
   g_trigger_ctx.current_leg.end_idx  = idx;
   g_trigger_ctx.current_leg.high     = hi;
   g_trigger_ctx.current_leg.high_idx = idx;
   g_trigger_ctx.current_leg.low      = lo;
   g_trigger_ctx.current_leg.low_idx  = idx;
}

inline void __TRG_ExtendCurrentLeg(const int idx,
                                   const double hi,
                                   const double lo)
{
   if(!g_trigger_ctx.current_leg_active) return;

   g_trigger_ctx.current_leg.end_idx = idx;
   if(hi > g_trigger_ctx.current_leg.high)
   {
      g_trigger_ctx.current_leg.high     = hi;
      g_trigger_ctx.current_leg.high_idx = idx;
   }
   if(lo < g_trigger_ctx.current_leg.low)
   {
      g_trigger_ctx.current_leg.low      = lo;
      g_trigger_ctx.current_leg.low_idx  = idx;
   }
}

inline void __TRG_PushCurrentLegToClosed()
{
   if(!g_trigger_ctx.current_leg_active || !g_trigger_ctx.current_leg.used)
      return;

   if(g_trigger_ctx.closed_count < TRG_MAX_CLOSED_LEGS)
   {
      g_trigger_ctx.closed_legs[g_trigger_ctx.closed_count] = g_trigger_ctx.current_leg;
      g_trigger_ctx.closed_count++;
   }
   else
   {
      for(int i=1; i<TRG_MAX_CLOSED_LEGS; ++i)
         g_trigger_ctx.closed_legs[i-1] = g_trigger_ctx.closed_legs[i];
      g_trigger_ctx.closed_legs[TRG_MAX_CLOSED_LEGS - 1] = g_trigger_ctx.current_leg;
   }

   g_trigger_ctx.current_leg_active = false;
   __TRG_ClearLeg(g_trigger_ctx.current_leg);
}

inline bool __TRG_LegIsUp(const TriggerLeg &leg)
{
   return (leg.used && leg.dir == TRG_LEG_UP);
}

inline bool __TRG_LegIsDn(const TriggerLeg &leg)
{
   return (leg.used && leg.dir == TRG_LEG_DN);
}

inline bool __TRG_GateExists(const int base_idx, const int phase2_idx)
{
   int cnt = ArraySize(g_trigger_gates);
   for(int i=0; i<cnt; ++i)
   {
      if(!g_trigger_gates[i].used) continue;
      if(g_trigger_gates[i].base_idx == base_idx && g_trigger_gates[i].phase2_idx == phase2_idx)
         return true;
   }
   return false;
}

inline void __TRG_AddBullGate(const TriggerLeg &up_leg,
                              const TriggerLeg &dn_leg,
                              const int birth_idx,
                              const MqlRates &rates[],
                              const int n)
{
   if(birth_idx < 0 || birth_idx >= n) return;
   if(up_leg.low_idx < 0 || dn_leg.low_idx < 0) return;
   if(__TRG_GateExists(up_leg.low_idx, dn_leg.low_idx)) return;

   TriggerGate gate;
   __TRG_ClearGate(gate);

   gate.used       = true;
   gate.serial     = (++g_trigger_ctx.gate_serial_seq);
   gate.birth_idx  = birth_idx;
   gate.birth_time = rates[birth_idx].time;

   gate.base_level = up_leg.low;
   gate.base_idx   = up_leg.low_idx;

   gate.phase1_level = up_leg.high;
   gate.phase1_idx   = up_leg.high_idx;
   if(dn_leg.high > gate.phase1_level)
   {
      gate.phase1_level = dn_leg.high;
      gate.phase1_idx   = dn_leg.high_idx;
   }

   gate.phase2_level = dn_leg.low;
   gate.phase2_idx   = dn_leg.low_idx;

   int pos = ArraySize(g_trigger_gates);
   ArrayResize(g_trigger_gates, pos + 1);
   g_trigger_gates[pos] = gate;
}

inline void __TRG_AddBearGate(const TriggerLeg &dn_leg,
                              const TriggerLeg &up_leg,
                              const int birth_idx,
                              const MqlRates &rates[],
                              const int n)
{
   if(birth_idx < 0 || birth_idx >= n) return;
   if(dn_leg.high_idx < 0 || up_leg.high_idx < 0) return;
   if(__TRG_GateExists(dn_leg.high_idx, up_leg.high_idx)) return;

   TriggerGate gate;
   __TRG_ClearGate(gate);

   gate.used       = true;
   gate.serial     = (++g_trigger_ctx.gate_serial_seq);
   gate.birth_idx  = birth_idx;
   gate.birth_time = rates[birth_idx].time;

   gate.base_level = dn_leg.high;
   gate.base_idx   = dn_leg.high_idx;

   gate.phase1_level = dn_leg.low;
   gate.phase1_idx   = dn_leg.low_idx;
   if(up_leg.low < gate.phase1_level)
   {
      gate.phase1_level = up_leg.low;
      gate.phase1_idx   = up_leg.low_idx;
   }

   gate.phase2_level = up_leg.high;
   gate.phase2_idx   = up_leg.high_idx;

   int pos = ArraySize(g_trigger_gates);
   ArrayResize(g_trigger_gates, pos + 1);
   g_trigger_gates[pos] = gate;
}

inline void __TRG_TrySpawnGateOnReversal(const MqlRates &rates[],
                                         const int n,
                                         const int birth_idx)
{
   if(g_trigger_ctx.closed_count < 2) return;

   TriggerLeg leg_a = g_trigger_ctx.closed_legs[g_trigger_ctx.closed_count - 2];
   TriggerLeg leg_b = g_trigger_ctx.closed_legs[g_trigger_ctx.closed_count - 1];

   if(g_trigger_ctx.active_dir == DIR_UP)
   {
      if(g_trigger_ctx.current_leg_active && g_trigger_ctx.current_leg.dir == TRG_LEG_UP &&
         __TRG_LegIsUp(leg_a) && __TRG_LegIsDn(leg_b))
      {
         __TRG_AddBullGate(leg_a, leg_b, birth_idx, rates, n);
      }
   }
   else
   {
      if(g_trigger_ctx.current_leg_active && g_trigger_ctx.current_leg.dir == TRG_LEG_DN &&
         __TRG_LegIsDn(leg_a) && __TRG_LegIsUp(leg_b))
      {
         __TRG_AddBearGate(leg_a, leg_b, birth_idx, rates, n);
      }
   }
}

inline void __TRG_ProcessBarToLegs(const MqlRates &rates[],
                                   const bool &insideHL[],
                                   const int n,
                                   const int bar_idx)
{
   if(bar_idx < 0 || bar_idx >= n) return;

   const MqlRates bar = rates[bar_idx];
   const int dir      = __TRG_CandleDir(bar);
   const bool inside  = insideHL[bar_idx];

   if(!g_trigger_ctx.current_leg_active)
   {
      if(dir == TRG_LEG_NONE)
         return;

      __TRG_StartCurrentLeg(dir, bar_idx, bar.high, bar.low);
      return;
   }

   if(inside || dir == TRG_LEG_NONE || dir == g_trigger_ctx.current_leg.dir)
   {
      __TRG_ExtendCurrentLeg(bar_idx, bar.high, bar.low);
      return;
   }

   __TRG_PushCurrentLegToClosed();
   __TRG_StartCurrentLeg(dir, bar_idx, bar.high, bar.low);
   __TRG_TrySpawnGateOnReversal(rates, n, bar_idx);
}

// ----------------------------------------------------------------------------
// Hit selection helpers
// ----------------------------------------------------------------------------
inline bool __TRG_IsBetterHit(const TriggerHitCandidate &cand,
                              const TriggerHitCandidate &best)
{
   if(!cand.hit)  return false;
   if(!best.hit)  return true;

   if(cand.bar_idx < best.bar_idx) return true;
   if(cand.bar_idx > best.bar_idx) return false;

   if(cand.gate_birth_idx > best.gate_birth_idx) return true;
   if(cand.gate_birth_idx < best.gate_birth_idx) return false;

   if(g_trigger_ctx.active_dir == DIR_UP)
   {
      if(cand.level < (best.level - __TRG_Eps())) return true;
      if(cand.level > (best.level + __TRG_Eps())) return false;
   }
   else
   {
      if(cand.level > (best.level + __TRG_Eps())) return true;
      if(cand.level < (best.level - __TRG_Eps())) return false;
   }

   return (cand.type_id < best.type_id);
}

inline void __TRG_ConsiderHit(TriggerHitCandidate &best,
                              const int gate_index,
                              const TriggerGate &gate,
                              const int type_id,
                              const int bar_idx,
                              const double level,
                              const int src_idx)
{
   if(gate_index < 0) return;
   if(bar_idx < 0) return;
   if(src_idx < 0) return;

   TriggerHitCandidate cand;
   __TRG_ClearHitCandidate(cand);

   cand.hit            = true;
   cand.gate_index     = gate_index;
   cand.gate_serial    = gate.serial;
   cand.gate_birth_idx = gate.birth_idx;
   cand.type_id        = type_id;
   cand.bar_idx        = bar_idx;
   cand.level          = level;
   cand.src_idx        = src_idx;

   if(__TRG_IsBetterHit(cand, best))
      best = cand;
}

// ----------------------------------------------------------------------------
// Gate evaluation
// ----------------------------------------------------------------------------
inline void __TRG_UpdateBullGate(const int gate_index,
                                 TriggerGate &gate,
                                 const MqlRates &rates[],
                                 const int n,
                                 const int bar_idx,
                                 TriggerHitCandidate &best)
{
   const MqlRates bar = rates[bar_idx];
   const int cur_dir = (g_trigger_ctx.current_leg_active ? g_trigger_ctx.current_leg.dir
                                                         : __TRG_CandleDir(bar));

   if(__TRG_BreakBelowStrict(bar.low, gate.base_level))
   {
      gate.used = false;
      return;
   }

   if(cur_dir == TRG_LEG_UP)
   {
      if(!gate.type1_arm_final && !gate.type2_arm_final)
      {
         if(bar.low < gate.phase2_level && !__TRG_BreakBelowStrict(bar.low, gate.base_level))
         {
            gate.phase2_level = bar.low;
            gate.phase2_idx   = bar_idx;
         }
      }

      if(gate.type2_possible && gate.type2_break1_seen && !gate.type2_arm_final)
      {
         if(bar.high > gate.phase3_level)
         {
            gate.phase3_level = bar.high;
            gate.phase3_idx   = bar_idx;
         }
      }

      if(!gate.type2_break1_seen)
      {
         if(__TRG_BreakAboveStrict(bar.high, gate.phase1_level))
         {
            gate.type1_possible    = false;
            gate.type2_break1_seen = true;
            gate.phase3_level      = bar.high;
            gate.phase3_idx        = bar_idx;
         }
         else if(gate.type1_possible)
         {
            gate.type1_middle_seen = true;
         }
      }
   }
   else if(cur_dir == TRG_LEG_DN)
   {
      if(gate.type2_possible && gate.type2_break1_seen && !gate.type2_arm_final)
      {
         if(bar.high > gate.phase3_level)
         {
            gate.phase3_level = bar.high;
            gate.phase3_idx   = bar_idx;
         }
      }

      if(gate.type1_possible && gate.type1_middle_seen && !gate.type1_arm_final)
      {
         if(__TRG_BreakBelowStrict(bar.low, gate.phase2_level))
         {
            if(__TRG_BreakBelowStrict(bar.low, gate.base_level))
            {
               gate.used = false;
               return;
            }

            gate.type1_arm_final = true;
            gate.type1_target    = gate.phase1_level;
            gate.type1_src_idx   = gate.phase1_idx;
            gate.type1_arm_idx   = bar_idx;
         }
      }

      if(gate.type2_possible && gate.type2_break1_seen && !gate.type2_arm_final)
      {
         if(__TRG_BreakBelowStrict(bar.low, gate.phase2_level))
         {
            if(__TRG_BreakBelowStrict(bar.low, gate.base_level))
            {
               gate.used = false;
               return;
            }

            gate.type2_arm_final = true;
            gate.type2_target    = gate.phase3_level;
            gate.type2_src_idx   = gate.phase3_idx;
            gate.type2_arm_idx   = bar_idx;
         }
      }
   }

   if(gate.type1_arm_final && gate.type1_src_idx >= 0 && bar_idx > gate.type1_arm_idx)
   {
      if(__TRG_TouchHigh(bar.high, gate.type1_target))
         __TRG_ConsiderHit(best, gate_index, gate, 1, bar_idx, gate.type1_target, gate.type1_src_idx);
   }

   if(gate.type2_arm_final && gate.type2_src_idx >= 0 && bar_idx > gate.type2_arm_idx)
   {
      if(__TRG_TouchHigh(bar.high, gate.type2_target))
         __TRG_ConsiderHit(best, gate_index, gate, 2, bar_idx, gate.type2_target, gate.type2_src_idx);
   }
}

inline void __TRG_UpdateBearGate(const int gate_index,
                                 TriggerGate &gate,
                                 const MqlRates &rates[],
                                 const int n,
                                 const int bar_idx,
                                 TriggerHitCandidate &best)
{
   const MqlRates bar = rates[bar_idx];
   const int cur_dir = (g_trigger_ctx.current_leg_active ? g_trigger_ctx.current_leg.dir
                                                         : __TRG_CandleDir(bar));

   if(__TRG_BreakAboveStrict(bar.high, gate.base_level))
   {
      gate.used = false;
      return;
   }

   if(cur_dir == TRG_LEG_DN)
   {
      if(!gate.type1_arm_final && !gate.type2_arm_final)
      {
         if(bar.high > gate.phase2_level && !__TRG_BreakAboveStrict(bar.high, gate.base_level))
         {
            gate.phase2_level = bar.high;
            gate.phase2_idx   = bar_idx;
         }
      }

      if(gate.type2_possible && gate.type2_break1_seen && !gate.type2_arm_final)
      {
         if(bar.low < gate.phase3_level)
         {
            gate.phase3_level = bar.low;
            gate.phase3_idx   = bar_idx;
         }
      }

      if(!gate.type2_break1_seen)
      {
         if(__TRG_BreakBelowStrict(bar.low, gate.phase1_level))
         {
            gate.type1_possible    = false;
            gate.type2_break1_seen = true;
            gate.phase3_level      = bar.low;
            gate.phase3_idx        = bar_idx;
         }
         else if(gate.type1_possible)
         {
            gate.type1_middle_seen = true;
         }
      }
   }
   else if(cur_dir == TRG_LEG_UP)
   {
      if(gate.type2_possible && gate.type2_break1_seen && !gate.type2_arm_final)
      {
         if(bar.low < gate.phase3_level)
         {
            gate.phase3_level = bar.low;
            gate.phase3_idx   = bar_idx;
         }
      }

      if(gate.type1_possible && gate.type1_middle_seen && !gate.type1_arm_final)
      {
         if(__TRG_BreakAboveStrict(bar.high, gate.phase2_level))
         {
            if(__TRG_BreakAboveStrict(bar.high, gate.base_level))
            {
               gate.used = false;
               return;
            }

            gate.type1_arm_final = true;
            gate.type1_target    = gate.phase1_level;
            gate.type1_src_idx   = gate.phase1_idx;
            gate.type1_arm_idx   = bar_idx;
         }
      }

      if(gate.type2_possible && gate.type2_break1_seen && !gate.type2_arm_final)
      {
         if(__TRG_BreakAboveStrict(bar.high, gate.phase2_level))
         {
            if(__TRG_BreakAboveStrict(bar.high, gate.base_level))
            {
               gate.used = false;
               return;
            }

            gate.type2_arm_final = true;
            gate.type2_target    = gate.phase3_level;
            gate.type2_src_idx   = gate.phase3_idx;
            gate.type2_arm_idx   = bar_idx;
         }
      }
   }

   if(gate.type1_arm_final && gate.type1_src_idx >= 0 && bar_idx > gate.type1_arm_idx)
   {
      if(__TRG_TouchLow(bar.low, gate.type1_target))
         __TRG_ConsiderHit(best, gate_index, gate, 1, bar_idx, gate.type1_target, gate.type1_src_idx);
   }

   if(gate.type2_arm_final && gate.type2_src_idx >= 0 && bar_idx > gate.type2_arm_idx)
   {
      if(__TRG_TouchLow(bar.low, gate.type2_target))
         __TRG_ConsiderHit(best, gate_index, gate, 2, bar_idx, gate.type2_target, gate.type2_src_idx);
   }
}

inline void __TRG_CompactGates()
{
   int cnt = ArraySize(g_trigger_gates);
   if(cnt <= 0) return;

   int write_pos = 0;
   for(int i=0; i<cnt; ++i)
   {
      if(!g_trigger_gates[i].used) continue;
      if(write_pos != i)
         g_trigger_gates[write_pos] = g_trigger_gates[i];
      write_pos++;
   }

   if(write_pos != cnt)
      ArrayResize(g_trigger_gates, write_pos);
}

inline void __TRG_EvaluateGates(const MqlRates &rates[],
                                const int n,
                                const int bar_idx,
                                TriggerHitCandidate &best)
{
   int cnt = ArraySize(g_trigger_gates);
   for(int i=0; i<cnt; ++i)
   {
      if(!g_trigger_gates[i].used) continue;

      if(g_trigger_ctx.active_dir == DIR_UP)
         __TRG_UpdateBullGate(i, g_trigger_gates[i], rates, n, bar_idx, best);
      else
         __TRG_UpdateBearGate(i, g_trigger_gates[i], rates, n, bar_idx, best);
   }

   __TRG_CompactGates();
}

inline void __TRG_AfterHitKeepMother()
{
   __TRG_ClearAllGates();
   __TRG_ResetLegsOnly();
}

inline void __TRG_HandleHit(const TriggerHitCandidate &best,
                            const MqlRates &rates[],
                            const int n)
{
   if(!best.hit) return;
   if(best.bar_idx < 0 || best.bar_idx >= n) return;
   if(best.src_idx < 0 || best.src_idx >= n) return;

   __TRG_DrawMarker(best.type_id,
                    best.gate_serial,
                    rates[best.src_idx].time,
                    rates[best.bar_idx].time,
                    best.level);

   g_trigger_ctx.window_hit_count++;
   __TRG_AfterHitKeepMother();
}

// ----------------------------------------------------------------------------
// Per-bar engine
// ----------------------------------------------------------------------------
inline void __TRG_EnsureMother(const MqlRates &rates[], const int bar_idx)
{
   if(g_trigger_ctx.mother_set) return;

   g_trigger_ctx.mother_set   = true;
   g_trigger_ctx.mother_idx   = bar_idx;
   g_trigger_ctx.mother_time  = rates[bar_idx].time;
   g_trigger_ctx.mother_level = (g_trigger_ctx.active_dir == DIR_UP ? rates[bar_idx].low
                                                                    : rates[bar_idx].high);
}

inline void __TRG_CheckMotherReset(const MqlRates &rates[], const int bar_idx)
{
   if(!g_trigger_ctx.mother_set)
   {
      __TRG_EnsureMother(rates, bar_idx);
      return;
   }

   if(g_trigger_ctx.active_dir == DIR_UP)
   {
      if(__TRG_BreakBelowStrict(rates[bar_idx].low, g_trigger_ctx.mother_level))
         __TRG_ResetForNewMother(rates, bar_idx);
   }
   else
   {
      if(__TRG_BreakAboveStrict(rates[bar_idx].high, g_trigger_ctx.mother_level))
         __TRG_ResetForNewMother(rates, bar_idx);
   }
}

inline void Trigger_OnBarCandidate(const string sym,
                                   const MqlRates &rates[],
                                   const bool &insideHL[],
                                   const int       n,
                                   const int       bar_idx,
                                   const int       candidate_idx)
{
   if(!__TRG_IsWorkerTF()) return;
   if(!__TRG_IsMajorWorld()) return;
   if(n <= 0 || bar_idx < 0 || bar_idx >= n) return;
   if(candidate_idx < -1) return; // intentionally unused in the independent engine

   if(!__TRG_LoadBridgeEvents(sym))
      return;

   const datetime bar_time = rates[bar_idx].time;
   __TRG_ApplyWindowAt(bar_time);
   if(!g_trigger_ctx.active)
      return;

   // Start from the very worker candle that contains the H4 signal-on event.
   if(bar_time < g_trigger_ctx.active_start_bar_time)
      return;

   if(g_trigger_ctx.window_hit_count >= TRG_MAX_HITS_PER_WINDOW)
      return;

   // Passive shield against duplicate calls and historical rewinds from the API.
   if(g_trigger_ctx.last_processed_time > 0 && bar_time <= g_trigger_ctx.last_processed_time)
      return;

   __TRG_CheckMotherReset(rates, bar_idx);
   __TRG_EnsureMother(rates, bar_idx);

   __TRG_ProcessBarToLegs(rates, insideHL, n, bar_idx);

   TriggerHitCandidate best;
   __TRG_ClearHitCandidate(best);
   __TRG_EvaluateGates(rates, n, bar_idx, best);
   if(best.hit)
      __TRG_HandleHit(best, rates, n);

   g_trigger_ctx.last_processed_time = bar_time;
   g_trigger_ctx.last_processed_idx  = bar_idx;
}

#endif // WAVEBOT_TRIGGER_MQH
