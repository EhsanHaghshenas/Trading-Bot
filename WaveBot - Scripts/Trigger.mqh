#ifndef WAVEBOT_TRIGGER_MQH
#define WAVEBOT_TRIGGER_MQH

#include <WaveBot/Types.mqh>
#include <WaveBot/Markers.mqh>
#include <WaveBot/WB15_SignalBridge.mqh>

// ============================================================================
// Trigger.mqh
// Dedicated lower-TF trigger detector driven by H4 bridge events.
//
// This module is intentionally passive:
// - it never changes the normal wave / candle detection logic;
// - it only watches the already-running scan through Trigger_OnBarCandidate().
//
// Current rules implemented here:
//  1) trigger detection starts only after a valid incoming H4 START signal;
//  2) any H4 STOP signal halts trigger detection immediately;
//  3) a new H4 START signal resets the trigger scan from scratch;
//  4) trigger detection is always bound to the current candidate first candle
//     of the in-progress wave; when that candidate changes, the trigger scan
//     resets completely;
//  5) inside bars are fully allowed to participate in trigger formation;
//  6) Type-1 and Type-2 are evaluated in parallel on every bar and whichever
//     completes first wins;
//  7) for bullish triggers, the shared lower boundary is Low(anchor candidate),
//     and the primary ceiling is the highest high formed before or during the
//     first down leg;
//  8) for bearish triggers, the shared upper boundary is High(anchor candidate),
//     and the primary floor is the lowest low formed before or during the first
//     up leg;
//  9) once a trigger fires, the trigger range is reset and a new range must be
//     rebuilt from scratch under the still-active H4 START window.
// ============================================================================

enum TriggerLegDir
{
   TRG_LEG_NONE = 0,
   TRG_LEG_UP   = 1,
   TRG_LEG_DN   = -1
};

struct TriggerBridgeEvent
{
   datetime  t;
   Direction dir;
   int       kind;
   int       seq;
   bool      is_start;
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

struct TriggerContext
{
   // H4 bridge snapshot
   double             run_id;
   int                bridge_seq;
   TriggerBridgeEvent events[];

   // active bridge window
   bool      active;
   int       active_event_pos;
   int       active_start_seq;
   Direction active_dir;
   datetime  active_start_time;

   // current anchor = candidate first candle of the in-progress wave
   int       anchor_idx;
   datetime  anchor_time;
   double    anchor_level;
   bool      anchor_blocked;

   // fixed trigger range inside the current anchor cycle
   bool      range_ready;
   double    range_primary_level;
   int       range_primary_idx;
   datetime  range_primary_time;

   // candle-chain FSM (recent legs only; range itself is stored separately)
   TriggerLeg closed_legs[4];
   int        closed_count;
   TriggerLeg current_leg;
   bool       current_leg_active;

   // duplicate / rewind guards
   datetime   last_bar_time;
   int        last_bar_idx;
   int        last_anchor_idx;
   int        last_start_seq;

   // last emitted trigger (duplicate guard)
   datetime   last_hit_time;
   double     last_hit_level;
   Direction  last_hit_dir;
   int        last_hit_type;

   // marker counters
   int        up_counter;
   int        dn_counter;
};

static TriggerContext g_trigger_ctx;

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

inline void __TRG_ResetRange()
{
   g_trigger_ctx.range_ready         = false;
   g_trigger_ctx.range_primary_level = 0.0;
   g_trigger_ctx.range_primary_idx   = -1;
   g_trigger_ctx.range_primary_time  = 0;
}

inline void __TRG_ResetLegsOnly()
{
   for(int i=0; i<4; ++i)
      __TRG_ClearLeg(g_trigger_ctx.closed_legs[i]);

   g_trigger_ctx.closed_count       = 0;
   g_trigger_ctx.current_leg_active = false;
   __TRG_ClearLeg(g_trigger_ctx.current_leg);

   g_trigger_ctx.last_bar_time   = 0;
   g_trigger_ctx.last_bar_idx    = -1;
   g_trigger_ctx.last_anchor_idx = -1;
   g_trigger_ctx.last_start_seq  = -1;

   __TRG_ResetRange();
}

inline void __TRG_ResetAnchorAndLegs()
{
   g_trigger_ctx.anchor_idx     = -1;
   g_trigger_ctx.anchor_time    = 0;
   g_trigger_ctx.anchor_level   = 0.0;
   g_trigger_ctx.anchor_blocked = false;
   __TRG_ResetLegsOnly();
}

inline void Trigger_ResetGlobals()
{
   g_trigger_ctx.run_id            = 0.0;
   g_trigger_ctx.bridge_seq        = 0;
   ArrayResize(g_trigger_ctx.events, 0);

   g_trigger_ctx.active            = false;
   g_trigger_ctx.active_event_pos  = -1;
   g_trigger_ctx.active_start_seq  = -1;
   g_trigger_ctx.active_dir        = DIR_UP;
   g_trigger_ctx.active_start_time = 0;

   __TRG_ResetAnchorAndLegs();

   g_trigger_ctx.last_hit_time  = 0;
   g_trigger_ctx.last_hit_level = 0.0;
   g_trigger_ctx.last_hit_dir   = DIR_UP;
   g_trigger_ctx.last_hit_type  = 0;

   g_trigger_ctx.up_counter     = 0;
   g_trigger_ctx.dn_counter     = 0;
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

inline int __TRG_DecodeKind(const int code) { return (code / 100); }
inline int __TRG_DecodeDirCode(const int code) { return (code % 10); }

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
   ArrayResize(g_trigger_ctx.events, 0);

   for(int i=1; i<=seq; ++i)
   {
      const string kt = __WB15_KeyT(sym, i);
      const string kc = __WB15_KeyC(sym, i);
      if(!GlobalVariableCheck(kt) || !GlobalVariableCheck(kc))
         continue;

      const datetime t    = (datetime)GlobalVariableGet(kt);
      const int      code = (int)GlobalVariableGet(kc);
      const int      kind = __TRG_DecodeKind(code);
      const bool     is_start = __TRG_IsStartKind(kind);
      const bool     is_stop  = __TRG_IsStopKind(kind);
      if(!is_start && !is_stop)
         continue;

      TriggerBridgeEvent evt;
      evt.t        = t;
      evt.dir      = __WB15_CodeDir(__TRG_DecodeDirCode(code));
      evt.kind     = kind;
      evt.seq      = i;
      evt.is_start = is_start;

      int pos = ArraySize(g_trigger_ctx.events);
      ArrayResize(g_trigger_ctx.events, pos + 1);
      g_trigger_ctx.events[pos] = evt;
   }

   g_trigger_ctx.active           = false;
   g_trigger_ctx.active_event_pos = -1;
   g_trigger_ctx.active_start_seq = -1;
   g_trigger_ctx.active_start_time= 0;
   __TRG_ResetAnchorAndLegs();
   return true;
}

inline int __TRG_FindLatestEventPosAt(const datetime t)
{
   int count = ArraySize(g_trigger_ctx.events);
   for(int i=count-1; i>=0; --i)
   {
      if(g_trigger_ctx.events[i].t <= t)
         return i;
   }
   return -1;
}

inline void __TRG_ApplyEventAt(const datetime t)
{
   int pos = __TRG_FindLatestEventPosAt(t);
   if(pos == g_trigger_ctx.active_event_pos)
      return;

   g_trigger_ctx.active_event_pos = pos;

   if(pos < 0)
   {
      g_trigger_ctx.active            = false;
      g_trigger_ctx.active_start_seq  = -1;
      g_trigger_ctx.active_start_time = 0;
      __TRG_ResetAnchorAndLegs();
      return;
   }

   const TriggerBridgeEvent evt = g_trigger_ctx.events[pos];
   if(!evt.is_start)
   {
      g_trigger_ctx.active            = false;
      g_trigger_ctx.active_start_seq  = -1;
      g_trigger_ctx.active_start_time = 0;
      __TRG_ResetAnchorAndLegs();
      return;
   }

   g_trigger_ctx.active            = true;
   g_trigger_ctx.active_start_seq  = evt.seq;
   g_trigger_ctx.active_start_time = evt.t;
   g_trigger_ctx.active_dir        = evt.dir;
   __TRG_ResetAnchorAndLegs();
}

inline int __TRG_CandleDir(const MqlRates &bar)
{
   if(bar.close > bar.open) return TRG_LEG_UP;
   if(bar.close < bar.open) return TRG_LEG_DN;
   return TRG_LEG_NONE;
}

inline void __TRG_StartCurrentLeg(const int dir,
                                  const int idx,
                                  const double hi,
                                  const double lo)
{
   g_trigger_ctx.current_leg_active = true;
   g_trigger_ctx.current_leg.used   = true;
   g_trigger_ctx.current_leg.dir    = dir;
   g_trigger_ctx.current_leg.start_idx = idx;
   g_trigger_ctx.current_leg.end_idx   = idx;

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
      g_trigger_ctx.current_leg.low     = lo;
      g_trigger_ctx.current_leg.low_idx = idx;
   }
}

inline void __TRG_ShiftClosedLegsLeft()
{
   for(int i=1; i<4; ++i)
      g_trigger_ctx.closed_legs[i-1] = g_trigger_ctx.closed_legs[i];
}

inline void __TRG_PushCurrentLegToClosed()
{
   if(!g_trigger_ctx.current_leg_active || !g_trigger_ctx.current_leg.used)
      return;

   if(g_trigger_ctx.closed_count < 4)
   {
      g_trigger_ctx.closed_legs[g_trigger_ctx.closed_count] = g_trigger_ctx.current_leg;
      g_trigger_ctx.closed_count++;
   }
   else
   {
      __TRG_ShiftClosedLegsLeft();
      g_trigger_ctx.closed_legs[3] = g_trigger_ctx.current_leg;
   }

   g_trigger_ctx.current_leg_active = false;
   __TRG_ClearLeg(g_trigger_ctx.current_leg);
}

inline bool __TRG_LegIsUp(const TriggerLeg &leg) { return (leg.used && leg.dir == TRG_LEG_UP); }
inline bool __TRG_LegIsDn(const TriggerLeg &leg) { return (leg.used && leg.dir == TRG_LEG_DN); }

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

inline void __TRG_DrawMarker(const string base,
                             const datetime ref_t,
                             const datetime hit_t,
                             const double   level)
{
   __TRG_DrawDashedLine(base + "_L", ref_t, hit_t, level, clrYellow);
   __TRG_DrawTextUnique(base + "_T", hit_t, level, "T", clrYellow, 10);
}

inline void __TRG_SelectMaxHigh(const TriggerLeg &leg, double &best_price, int &best_idx)
{
   if(!leg.used) return;
   if(best_idx < 0 || leg.high > best_price)
   {
      best_price = leg.high;
      best_idx   = leg.high_idx;
   }
}

inline void __TRG_SelectMinLow(const TriggerLeg &leg, double &best_price, int &best_idx)
{
   if(!leg.used) return;
   if(best_idx < 0 || leg.low < best_price)
   {
      best_price = leg.low;
      best_idx   = leg.low_idx;
   }
}

inline void __TRG_ProcessMaxHigh2(const TriggerLeg &L0,
                                  const TriggerLeg &L1,
                                  double &price,
                                  int &idx)
{
   idx = -1;
   price = 0.0;
   __TRG_SelectMaxHigh(L0, price, idx);
   __TRG_SelectMaxHigh(L1, price, idx);
}

inline void __TRG_ProcessMinLow2(const TriggerLeg &L0,
                                 const TriggerLeg &L1,
                                 double &price,
                                 int &idx)
{
   idx = -1;
   price = 0.0;
   __TRG_SelectMinLow(L0, price, idx);
   __TRG_SelectMinLow(L1, price, idx);
}

inline void __TRG_ProcessMaxHigh2_FromLegs(const TriggerLeg &L2,
                                           const TriggerLeg &L3,
                                           double &price,
                                           int &idx)
{
   idx = -1;
   price = 0.0;
   __TRG_SelectMaxHigh(L2, price, idx);
   __TRG_SelectMaxHigh(L3, price, idx);
}

inline void __TRG_ProcessMinLow2_FromLegs(const TriggerLeg &L2,
                                          const TriggerLeg &L3,
                                          double &price,
                                          int &idx)
{
   idx = -1;
   price = 0.0;
   __TRG_SelectMinLow(L2, price, idx);
   __TRG_SelectMinLow(L3, price, idx);
}

inline void __TRG_AfterHitReset()
{
   __TRG_ResetLegsOnly();
   g_trigger_ctx.anchor_blocked = false;
}

inline void __TRG_RecordHit(const MqlRates &rates[],
                            const int       n,
                            const int       bar_idx,
                            const int       src_idx,
                            const double    level,
                            const int       trig_type)
{
   if(bar_idx < 0 || bar_idx >= n) return;
   if(src_idx < 0 || src_idx >= n) return;
   if(level <= 0.0) return;

   const datetime t = rates[bar_idx].time;
   if(g_trigger_ctx.last_hit_time  == t &&
      MathAbs(g_trigger_ctx.last_hit_level - level) <= __TRG_Eps() &&
      g_trigger_ctx.last_hit_dir   == g_trigger_ctx.active_dir &&
      g_trigger_ctx.last_hit_type  == trig_type)
   {
      return;
   }

   string name;
   if(g_trigger_ctx.active_dir == DIR_UP)
   {
      g_trigger_ctx.up_counter++;
      name = "TRG_U_" + IntegerToString(g_trigger_ctx.up_counter)
           + "_S" + IntegerToString(g_trigger_ctx.active_start_seq)
           + "_A" + IntegerToString(g_trigger_ctx.anchor_idx)
           + "_T" + IntegerToString(trig_type);
   }
   else
   {
      g_trigger_ctx.dn_counter++;
      name = "TRG_D_" + IntegerToString(g_trigger_ctx.dn_counter)
           + "_S" + IntegerToString(g_trigger_ctx.active_start_seq)
           + "_A" + IntegerToString(g_trigger_ctx.anchor_idx)
           + "_T" + IntegerToString(trig_type);
   }

   __TRG_DrawMarker(name, rates[src_idx].time, t, level);

   g_trigger_ctx.last_hit_time  = t;
   g_trigger_ctx.last_hit_level = level;
   g_trigger_ctx.last_hit_dir   = g_trigger_ctx.active_dir;
   g_trigger_ctx.last_hit_type  = trig_type;

   if(InpDebugPrints)
      Print("[TRIGGER] Hit | dir=", (g_trigger_ctx.active_dir==DIR_UP?"UP":"DOWN"),
            " | type=", trig_type,
            " | time=", T(t),
            " | level=", DoubleToString(level, _Digits),
            " | start_seq=", g_trigger_ctx.active_start_seq,
            " | anchor_idx=", g_trigger_ctx.anchor_idx);

   __TRG_AfterHitReset();
}

inline void __TRG_MaybeEstablishBullishRange()
{
   if(g_trigger_ctx.range_ready) return;
   if(g_trigger_ctx.closed_count < 2) return;
   if(g_trigger_ctx.anchor_idx < 0) return;

   const TriggerLeg L0 = g_trigger_ctx.closed_legs[g_trigger_ctx.closed_count - 2];
   const TriggerLeg L1 = g_trigger_ctx.closed_legs[g_trigger_ctx.closed_count - 1];
   if(!__TRG_LegIsUp(L0) || !__TRG_LegIsDn(L1))
      return;

   const double floor = g_trigger_ctx.anchor_level;
   if(L1.low <= (floor + __TRG_Eps()))
      return;

   double ceiling = 0.0;
   int    ceil_idx = -1;
   __TRG_ProcessMaxHigh2(L0, L1, ceiling, ceil_idx);
   if(ceil_idx < 0) return;

   g_trigger_ctx.range_ready         = true;
   g_trigger_ctx.range_primary_level = ceiling;
   g_trigger_ctx.range_primary_idx   = ceil_idx;
   g_trigger_ctx.range_primary_time  = g_trigger_ctx.anchor_time;
}

inline void __TRG_MaybeEstablishBearishRange()
{
   if(g_trigger_ctx.range_ready) return;
   if(g_trigger_ctx.closed_count < 2) return;
   if(g_trigger_ctx.anchor_idx < 0) return;

   const TriggerLeg L0 = g_trigger_ctx.closed_legs[g_trigger_ctx.closed_count - 2];
   const TriggerLeg L1 = g_trigger_ctx.closed_legs[g_trigger_ctx.closed_count - 1];
   if(!__TRG_LegIsDn(L0) || !__TRG_LegIsUp(L1))
      return;

   const double ceiling = g_trigger_ctx.anchor_level;
   if(L1.high >= (ceiling - __TRG_Eps()))
      return;

   double floor = 0.0;
   int    floor_idx = -1;
   __TRG_ProcessMinLow2(L0, L1, floor, floor_idx);
   if(floor_idx < 0) return;

   g_trigger_ctx.range_ready         = true;
   g_trigger_ctx.range_primary_level = floor;
   g_trigger_ctx.range_primary_idx   = floor_idx;
   g_trigger_ctx.range_primary_time  = g_trigger_ctx.anchor_time;
}

inline void __TRG_ResolvePrimarySourceTime(const MqlRates &rates[], const int n, datetime &t)
{
   t = 0;
   if(g_trigger_ctx.range_primary_idx >= 0 && g_trigger_ctx.range_primary_idx < n)
      t = rates[g_trigger_ctx.range_primary_idx].time;
   if(t <= 0)
      t = g_trigger_ctx.anchor_time;
}

inline void __TRG_EvalBullish(const MqlRates &rates[], const int n, const int bar_idx)
{
   if(g_trigger_ctx.anchor_idx < 0 || g_trigger_ctx.anchor_idx >= n) return;
   if(!g_trigger_ctx.range_ready) return;
   if(!g_trigger_ctx.current_leg_active) return;
   if(g_trigger_ctx.current_leg.dir != TRG_LEG_UP) return;
   if(g_trigger_ctx.closed_count < 4) return;

   const TriggerLeg L0 = g_trigger_ctx.closed_legs[g_trigger_ctx.closed_count - 4];
   const TriggerLeg L1 = g_trigger_ctx.closed_legs[g_trigger_ctx.closed_count - 3];
   const TriggerLeg L2 = g_trigger_ctx.closed_legs[g_trigger_ctx.closed_count - 2];
   const TriggerLeg L3 = g_trigger_ctx.closed_legs[g_trigger_ctx.closed_count - 1];

   if(!__TRG_LegIsUp(L0) || !__TRG_LegIsDn(L1) || !__TRG_LegIsUp(L2) || !__TRG_LegIsDn(L3))
      return;

   const double floor      = g_trigger_ctx.anchor_level;
   const double primary_hi = g_trigger_ctx.range_primary_level;
   const double eps        = __TRG_Eps();

   if(primary_hi <= 0.0) return;
   if(L1.low <= (floor + eps)) return;
   if(L3.low <= (floor + eps)) return;
   if(L3.low >= (L1.low - eps)) return;

   // Type-1: the second up-leg must stay inside the primary ceiling,
   // and the final current up-leg must break that primary ceiling.
   if(L2.high <= (primary_hi + eps) &&
      g_trigger_ctx.current_leg.high > (primary_hi + eps))
   {
      int src_idx = g_trigger_ctx.range_primary_idx;
      if(src_idx < 0) src_idx = L0.high_idx;
      __TRG_RecordHit(rates, n, bar_idx, src_idx, primary_hi, 1);
      return;
   }

   // Type-2: the second up-leg must already break the primary ceiling,
   // then the next down-leg breaks the recent source low, and the final
   // current up-leg breaks the highest high seen between break-1 and break-2.
   if(L2.high > (primary_hi + eps))
   {
      double sec_hi = 0.0;
      int    sec_hi_idx = -1;
      __TRG_ProcessMaxHigh2_FromLegs(L2, L3, sec_hi, sec_hi_idx);
      if(sec_hi_idx >= 0 && sec_hi > (primary_hi + eps) &&
         g_trigger_ctx.current_leg.high > (sec_hi + eps))
      {
         __TRG_RecordHit(rates, n, bar_idx, sec_hi_idx, sec_hi, 2);
         return;
      }
   }
}

inline void __TRG_EvalBearish(const MqlRates &rates[], const int n, const int bar_idx)
{
   if(g_trigger_ctx.anchor_idx < 0 || g_trigger_ctx.anchor_idx >= n) return;
   if(!g_trigger_ctx.range_ready) return;
   if(!g_trigger_ctx.current_leg_active) return;
   if(g_trigger_ctx.current_leg.dir != TRG_LEG_DN) return;
   if(g_trigger_ctx.closed_count < 4) return;

   const TriggerLeg L0 = g_trigger_ctx.closed_legs[g_trigger_ctx.closed_count - 4];
   const TriggerLeg L1 = g_trigger_ctx.closed_legs[g_trigger_ctx.closed_count - 3];
   const TriggerLeg L2 = g_trigger_ctx.closed_legs[g_trigger_ctx.closed_count - 2];
   const TriggerLeg L3 = g_trigger_ctx.closed_legs[g_trigger_ctx.closed_count - 1];

   if(!__TRG_LegIsDn(L0) || !__TRG_LegIsUp(L1) || !__TRG_LegIsDn(L2) || !__TRG_LegIsUp(L3))
      return;

   const double ceiling    = g_trigger_ctx.anchor_level;
   const double primary_lo = g_trigger_ctx.range_primary_level;
   const double eps        = __TRG_Eps();

   if(primary_lo <= 0.0) return;
   if(L1.high >= (ceiling - eps)) return;
   if(L3.high >= (ceiling - eps)) return;
   if(L3.high <= (L1.high + eps)) return;

   // Type-1 mirror.
   if(L2.low >= (primary_lo - eps) &&
      g_trigger_ctx.current_leg.low < (primary_lo - eps))
   {
      int src_idx = g_trigger_ctx.range_primary_idx;
      if(src_idx < 0) src_idx = L0.low_idx;
      __TRG_RecordHit(rates, n, bar_idx, src_idx, primary_lo, 1);
      return;
   }

   // Type-2 mirror.
   if(L2.low < (primary_lo - eps))
   {
      double sec_lo = 0.0;
      int    sec_lo_idx = -1;
      __TRG_ProcessMinLow2_FromLegs(L2, L3, sec_lo, sec_lo_idx);
      if(sec_lo_idx >= 0 && sec_lo < (primary_lo - eps) &&
         g_trigger_ctx.current_leg.low < (sec_lo - eps))
      {
         __TRG_RecordHit(rates, n, bar_idx, sec_lo_idx, sec_lo, 2);
         return;
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
   const int dir = __TRG_CandleDir(bar);
   const bool is_inside = ((bar_idx >= 0 && bar_idx < n) ? insideHL[bar_idx] : false);

   // Inside bars must participate in trigger formation,
   // but they must never force a direction flip by themselves.
   if(is_inside)
   {
      if(!g_trigger_ctx.current_leg_active)
      {
         if(dir != TRG_LEG_NONE)
            __TRG_StartCurrentLeg(dir, bar_idx, bar.high, bar.low);
      }
      else
      {
         __TRG_ExtendCurrentLeg(bar_idx, bar.high, bar.low);
      }
   }
   else
   {
      if(dir == TRG_LEG_NONE)
      {
         if(g_trigger_ctx.current_leg_active)
            __TRG_ExtendCurrentLeg(bar_idx, bar.high, bar.low);
      }
      else if(!g_trigger_ctx.current_leg_active)
      {
         __TRG_StartCurrentLeg(dir, bar_idx, bar.high, bar.low);
      }
      else if(g_trigger_ctx.current_leg.dir == dir)
      {
         __TRG_ExtendCurrentLeg(bar_idx, bar.high, bar.low);
      }
      else
      {
         __TRG_PushCurrentLegToClosed();
         __TRG_StartCurrentLeg(dir, bar_idx, bar.high, bar.low);
      }
   }

   if(g_trigger_ctx.active_dir == DIR_UP)
   {
      __TRG_MaybeEstablishBullishRange();
      __TRG_EvalBullish(rates, n, bar_idx);
   }
   else
   {
      __TRG_MaybeEstablishBearishRange();
      __TRG_EvalBearish(rates, n, bar_idx);
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
   if(candidate_idx < 0 || candidate_idx >= n) return;

   if(!__TRG_LoadBridgeEvents(sym))
      return;

   const datetime bar_time = rates[bar_idx].time;
   __TRG_ApplyEventAt(bar_time);
   if(!g_trigger_ctx.active) return;

   // Detection starts strictly from the active H4 START signal onward.
   if(bar_time < g_trigger_ctx.active_start_time)
      return;

   // Rewind guard: if the API replays older bars inside the same start window,
   // only reset the trigger-local FSM; normal scan logic stays untouched.
   if(g_trigger_ctx.last_bar_time > 0 && bar_time < g_trigger_ctx.last_bar_time)
      __TRG_ResetLegsOnly();

   const double new_anchor_level = (g_trigger_ctx.active_dir == DIR_UP ? rates[candidate_idx].low
                                                                       : rates[candidate_idx].high);
   const datetime new_anchor_time = rates[candidate_idx].time;

   const bool anchor_changed =
      (candidate_idx != g_trigger_ctx.anchor_idx ||
       new_anchor_time != g_trigger_ctx.anchor_time ||
       MathAbs(new_anchor_level - g_trigger_ctx.anchor_level) > __TRG_Eps());

   if(anchor_changed)
   {
      g_trigger_ctx.anchor_idx     = candidate_idx;
      g_trigger_ctx.anchor_time    = new_anchor_time;
      g_trigger_ctx.anchor_level   = new_anchor_level;
      g_trigger_ctx.anchor_blocked = false;
      __TRG_ResetLegsOnly();
   }

   if(g_trigger_ctx.anchor_idx < 0)
      return;

   // Do not re-process the same bar for the same active start + same anchor.
   if(g_trigger_ctx.last_bar_time   == bar_time &&
      g_trigger_ctx.last_start_seq  == g_trigger_ctx.active_start_seq &&
      g_trigger_ctx.last_anchor_idx == g_trigger_ctx.anchor_idx)
   {
      return;
   }

   g_trigger_ctx.last_bar_time   = bar_time;
   g_trigger_ctx.last_bar_idx    = bar_idx;
   g_trigger_ctx.last_start_seq  = g_trigger_ctx.active_start_seq;
   g_trigger_ctx.last_anchor_idx = g_trigger_ctx.anchor_idx;

   // Trigger evaluation starts strictly AFTER the anchor candle itself.
   if(bar_idx <= g_trigger_ctx.anchor_idx)
      return;

   // Shared lower/upper boundary from the anchor candidate.
   if(g_trigger_ctx.active_dir == DIR_UP)
   {
      if(rates[bar_idx].low < (g_trigger_ctx.anchor_level - __TRG_Eps()))
      {
         g_trigger_ctx.anchor_blocked = true;
         __TRG_ResetLegsOnly();
         return;
      }
   }
   else
   {
      if(rates[bar_idx].high > (g_trigger_ctx.anchor_level + __TRG_Eps()))
      {
         g_trigger_ctx.anchor_blocked = true;
         __TRG_ResetLegsOnly();
         return;
      }
   }

   if(g_trigger_ctx.anchor_blocked)
      return;

   __TRG_ProcessBarToLegs(rates, insideHL, n, bar_idx);
}

#endif // WAVEBOT_TRIGGER_MQH
