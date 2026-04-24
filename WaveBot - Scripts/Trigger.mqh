#ifndef WAVEBOT_TRIGGER_MQH
#define WAVEBOT_TRIGGER_MQH

#include <WaveBot/Types.mqh>
#include <WaveBot/Markers.mqh>
#include <WaveBot/WB15_SignalBridge.mqh>
#include <WaveBot/TriggerSLTP.mqh>

void TriggerStatement_OnNewTriggerAt(const datetime trigger_time);

// ============================================================================
// Trigger.mqh
//
// Orchestrator for two fully independent trigger engines:
//   - TriggerType1.mqh  -> dedicated type-1 search engine
//   - TriggerType2.mqh  -> dedicated type-2 search engine
//
// Both engines:
//   - run on every worker-TF candle,
//   - rebuild the active window from the same M15->worker bridge,
//   - stay fully independent in detection/state/visuals,
//   - share the same downstream SL/TP record store and statement/trade layer.
//
// Public API is intentionally kept unchanged so the rest of WaveBot does not
// need any rename/refactor:
//   - Trigger_ResetGlobals()
//   - Trigger_OnTimer()
//   - Trigger_OnBarCandidate()
//
// TriggerStatement.mqh also depends on these bridge helpers/state, therefore
// they are preserved here:
//   - TriggerEvent
//   - g_trigger_events[]
//   - __TRG_IsStartKind()
//   - __TRG_IsStopKind()
//   - __TRG_RebuildBridgeEvents()
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

struct TriggerBridgeState
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
};

struct TriggerEngineCore
{
   bool          mother_set;
   double        mother_level;
   int           mother_idx;
   datetime      mother_time;

   int           phase;

   double        phase1_level;
   int           phase1_idx;

   double        phase2_level;
   int           phase2_idx;

   double        phase3_level;
   int           phase3_idx;

   double        phase4_level;
   int           phase4_idx;

   bool          phase2_build_active;
   double        phase2_build_level;
   int           phase2_build_idx;

   bool          phase3_break1_seen;
   bool          phase4_break2_seen;

   datetime      last_processed_time;
   int           last_processed_idx;

   int           up_counter;
   int           dn_counter;
};

static TriggerBridgeState g_trigger_bridge;
static TriggerEvent       g_trigger_events[];
static string             g_trigger_symbol = "";

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

inline datetime __TRG_WorkerBarOpen(const datetime t)
{
   int sec = PeriodSeconds((ENUM_TIMEFRAMES)Period());
   if(sec <= 0)
      sec = 60;

   long ts = (long)t;
   long ss = (long)sec;
   return (datetime)(ts - (ts % ss));
}

inline string __TRG_RunTag()
{
   return IntegerToString((int)g_trigger_bridge.run_id);
}

inline string __TRG_WindowTag()
{
   return IntegerToString(g_trigger_bridge.active_start_seq);
}

// ----------------------------------------------------------------------------
// Generic engine-core helpers shared by TriggerType1 and TriggerType2
// ----------------------------------------------------------------------------
inline void __TRGCORE_ClearPhase2Build(TriggerEngineCore &ctx)
{
   ctx.phase2_build_active = false;
   ctx.phase2_build_level  = 0.0;
   ctx.phase2_build_idx    = -1;
}

inline void __TRGCORE_ClearFSM(TriggerEngineCore &ctx)
{
   ctx.mother_set         = false;
   ctx.mother_level       = 0.0;
   ctx.mother_idx         = -1;
   ctx.mother_time        = 0;

   ctx.phase              = TRG_PHASE_NONE;

   ctx.phase1_level       = 0.0;
   ctx.phase1_idx         = -1;
   ctx.phase2_level       = 0.0;
   ctx.phase2_idx         = -1;
   ctx.phase3_level       = 0.0;
   ctx.phase3_idx         = -1;
   ctx.phase4_level       = 0.0;
   ctx.phase4_idx         = -1;

   ctx.phase3_break1_seen = false;
   ctx.phase4_break2_seen = false;

   __TRGCORE_ClearPhase2Build(ctx);

   ctx.last_processed_time = 0;
   ctx.last_processed_idx  = -1;
}

inline void __TRGCORE_ResetGlobals(TriggerEngineCore &ctx)
{
   ctx.up_counter = 0;
   ctx.dn_counter = 0;
   __TRGCORE_ClearFSM(ctx);
}

inline bool __TRGCORE_HasConfirmedPhase3(const TriggerEngineCore &ctx)
{
   return (ctx.phase3_idx >= 0);
}

inline int __TRGCORE_BullPhase3StartRefIdx(const TriggerEngineCore &ctx)
{
   if(ctx.phase2_build_active && ctx.phase2_build_idx >= 0)
      return ctx.phase2_build_idx;

   return ctx.phase2_idx;
}

inline int __TRGCORE_BearPhase3StartRefIdx(const TriggerEngineCore &ctx)
{
   if(ctx.phase2_build_active && ctx.phase2_build_idx >= 0)
      return ctx.phase2_build_idx;

   return ctx.phase2_idx;
}

inline bool __TRGCORE_BullCanStartType1Phase3(const TriggerEngineCore &ctx,
                                              const MqlRates         &rates[],
                                              const int               n,
                                              const int               bar_idx)
{
   if(n <= 0 || bar_idx < 0 || bar_idx >= n)
      return false;

   int ref_idx = __TRGCORE_BullPhase3StartRefIdx(ctx);
   if(ref_idx < 0 || ref_idx >= n)
      return false;

   if(__TRG_BreakAboveStrict(rates[bar_idx].high, ctx.phase1_level))
      return false;

   return __TRG_BreakAboveStrict(rates[bar_idx].high, rates[ref_idx].high);
}

inline bool __TRGCORE_BearCanStartType1Phase3(const TriggerEngineCore &ctx,
                                              const MqlRates         &rates[],
                                              const int               n,
                                              const int               bar_idx)
{
   if(n <= 0 || bar_idx < 0 || bar_idx >= n)
      return false;

   int ref_idx = __TRGCORE_BearPhase3StartRefIdx(ctx);
   if(ref_idx < 0 || ref_idx >= n)
      return false;

   if(__TRG_BreakBelowStrict(rates[bar_idx].low, ctx.phase1_level))
      return false;

   return __TRG_BreakBelowStrict(rates[bar_idx].low, rates[ref_idx].low);
}

inline void __TRGCORE_BeginBullPhase2Build(TriggerEngineCore &ctx,
                                           const int          bar_idx,
                                           const MqlRates    &bar,
                                           const bool         sync_confirmed_phase2)
{
   ctx.phase               = TRG_PHASE_2;
   ctx.phase2_build_active = true;
   ctx.phase2_build_level  = bar.low;
   ctx.phase2_build_idx    = bar_idx;

   if(sync_confirmed_phase2)
   {
      ctx.phase2_level = bar.low;
      ctx.phase2_idx   = bar_idx;
   }
}

inline void __TRGCORE_BeginBearPhase2Build(TriggerEngineCore &ctx,
                                           const int          bar_idx,
                                           const MqlRates    &bar,
                                           const bool         sync_confirmed_phase2)
{
   ctx.phase               = TRG_PHASE_2;
   ctx.phase2_build_active = true;
   ctx.phase2_build_level  = bar.high;
   ctx.phase2_build_idx    = bar_idx;

   if(sync_confirmed_phase2)
   {
      ctx.phase2_level = bar.high;
      ctx.phase2_idx   = bar_idx;
   }
}

inline void __TRGCORE_UpdateBullPhase2Build(TriggerEngineCore &ctx,
                                            const int          bar_idx,
                                            const MqlRates    &bar,
                                            const bool         sync_confirmed_phase2)
{
   if(!ctx.phase2_build_active)
   {
      __TRGCORE_BeginBullPhase2Build(ctx, bar_idx, bar, sync_confirmed_phase2);
      return;
   }

   if(bar.low < ctx.phase2_build_level)
   {
      ctx.phase2_build_level = bar.low;
      ctx.phase2_build_idx   = bar_idx;

      if(sync_confirmed_phase2)
      {
         ctx.phase2_level = bar.low;
         ctx.phase2_idx   = bar_idx;
      }
   }
}

inline void __TRGCORE_UpdateBearPhase2Build(TriggerEngineCore &ctx,
                                            const int          bar_idx,
                                            const MqlRates    &bar,
                                            const bool         sync_confirmed_phase2)
{
   if(!ctx.phase2_build_active)
   {
      __TRGCORE_BeginBearPhase2Build(ctx, bar_idx, bar, sync_confirmed_phase2);
      return;
   }

   if(bar.high > ctx.phase2_build_level)
   {
      ctx.phase2_build_level = bar.high;
      ctx.phase2_build_idx   = bar_idx;

      if(sync_confirmed_phase2)
      {
         ctx.phase2_level = bar.high;
         ctx.phase2_idx   = bar_idx;
      }
   }
}

inline void __TRGCORE_CommitPhase2Build(TriggerEngineCore &ctx)
{
   if(!ctx.phase2_build_active)
      return;

   ctx.phase2_level = ctx.phase2_build_level;
   ctx.phase2_idx   = ctx.phase2_build_idx;
}

inline void __TRGCORE_SetBullPhase2Latest(TriggerEngineCore &ctx,
                                          const int          bar_idx,
                                          const MqlRates    &bar)
{
   ctx.phase = TRG_PHASE_2;
   __TRGCORE_UpdateBullPhase2Build(ctx, bar_idx, bar, true);
}

inline void __TRGCORE_SetBearPhase2Latest(TriggerEngineCore &ctx,
                                          const int          bar_idx,
                                          const MqlRates    &bar)
{
   ctx.phase = TRG_PHASE_2;
   __TRGCORE_UpdateBearPhase2Build(ctx, bar_idx, bar, true);
}

inline void __TRGCORE_SetBullPhase2Candidate(TriggerEngineCore &ctx,
                                             const int          bar_idx,
                                             const MqlRates    &bar)
{
   ctx.phase = TRG_PHASE_2;
   __TRGCORE_UpdateBullPhase2Build(ctx, bar_idx, bar, false);
}

inline void __TRGCORE_SetBearPhase2Candidate(TriggerEngineCore &ctx,
                                             const int          bar_idx,
                                             const MqlRates    &bar)
{
   ctx.phase = TRG_PHASE_2;
   __TRGCORE_UpdateBearPhase2Build(ctx, bar_idx, bar, false);
}

inline void __TRGCORE_SetBullPhase3Latest(TriggerEngineCore &ctx,
                                          const int          bar_idx,
                                          const MqlRates    &bar,
                                          const bool         broke_phase1)
{
   if(ctx.phase2_build_active)
      __TRGCORE_CommitPhase2Build(ctx);

   ctx.phase              = TRG_PHASE_3;
   ctx.phase3_level       = bar.high;
   ctx.phase3_idx         = bar_idx;
   ctx.phase3_break1_seen = broke_phase1;
   ctx.phase4_break2_seen = false;

   __TRGCORE_ClearPhase2Build(ctx);
}

inline void __TRGCORE_SetBearPhase3Latest(TriggerEngineCore &ctx,
                                          const int          bar_idx,
                                          const MqlRates    &bar,
                                          const bool         broke_phase1)
{
   if(ctx.phase2_build_active)
      __TRGCORE_CommitPhase2Build(ctx);

   ctx.phase              = TRG_PHASE_3;
   ctx.phase3_level       = bar.low;
   ctx.phase3_idx         = bar_idx;
   ctx.phase3_break1_seen = broke_phase1;
   ctx.phase4_break2_seen = false;

   __TRGCORE_ClearPhase2Build(ctx);
}

inline void __TRGCORE_StartBullCycle(TriggerEngineCore &ctx,
                                     const MqlRates    &rates[],
                                     const int          n,
                                     const int          bar_idx)
{
   if(bar_idx < 0 || bar_idx >= n)
      return;

   const MqlRates bar = rates[bar_idx];

   ctx.mother_set         = true;
   ctx.mother_level       = bar.low;
   ctx.mother_idx         = bar_idx;
   ctx.mother_time        = bar.time;

   ctx.phase              = TRG_PHASE_1;
   ctx.phase1_level       = bar.high;
   ctx.phase1_idx         = bar_idx;
   ctx.phase2_level       = 0.0;
   ctx.phase2_idx         = -1;
   ctx.phase3_level       = 0.0;
   ctx.phase3_idx         = -1;
   ctx.phase4_level       = 0.0;
   ctx.phase4_idx         = -1;
   ctx.phase3_break1_seen = false;
   ctx.phase4_break2_seen = false;

   __TRGCORE_ClearPhase2Build(ctx);
}

inline void __TRGCORE_StartBearCycle(TriggerEngineCore &ctx,
                                     const MqlRates    &rates[],
                                     const int          n,
                                     const int          bar_idx)
{
   if(bar_idx < 0 || bar_idx >= n)
      return;

   const MqlRates bar = rates[bar_idx];

   ctx.mother_set         = true;
   ctx.mother_level       = bar.high;
   ctx.mother_idx         = bar_idx;
   ctx.mother_time        = bar.time;

   ctx.phase              = TRG_PHASE_1;
   ctx.phase1_level       = bar.low;
   ctx.phase1_idx         = bar_idx;
   ctx.phase2_level       = 0.0;
   ctx.phase2_idx         = -1;
   ctx.phase3_level       = 0.0;
   ctx.phase3_idx         = -1;
   ctx.phase4_level       = 0.0;
   ctx.phase4_idx         = -1;
   ctx.phase3_break1_seen = false;
   ctx.phase4_break2_seen = false;

   __TRGCORE_ClearPhase2Build(ctx);
}

inline double __TRG_LabelPad(const MqlRates &bar)
{
   double span = bar.high - bar.low;
   if(span <= 0.0)
      span = (10.0 * _Point);

   double pad = (span * 0.28);
   if(pad < (4.0 * _Point))
      pad = (4.0 * _Point);

   return pad;
}

inline double __TRG_PhaseLabelY(const Direction dir,
                                const MqlRates &bar)
{
   double pad = __TRG_LabelPad(bar);
   if(dir == DIR_UP)
      return (bar.high + pad);

   return (bar.low - pad);
}

inline double __TRG_AnchorLabelY(const Direction dir,
                                 const MqlRates &bar)
{
   double pad = __TRG_LabelPad(bar);
   if(dir == DIR_UP)
      return (bar.low - pad);

   return (bar.high + pad);
}

inline double __TRG_ResetLabelY(const Direction dir,
                                const MqlRates &bar)
{
   double pad = __TRG_LabelPad(bar);
   if(dir == DIR_UP)
      return (bar.low - (pad * 2.0));

   return (bar.high + (pad * 2.0));
}

inline void __TRG_DrawTextUnique(const string   base,
                                 const datetime t,
                                 const double   price,
                                 const string   text,
                                 const color    col,
                                 const int      font_size)
{
   if(!InpDrawMarkers)
      return;

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

inline void __TRG_DrawDashedLine(const string   base,
                                 datetime       t1,
                                 datetime       t2,
                                 const double   level,
                                 const color    col)
{
   if(!InpDrawMarkers)
      return;
   if(t1 <= 0 || t2 <= 0)
      return;

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

inline void __TRG_DrawPhaseLabelEx(const string    engine_tag,
                                   const Direction dir,
                                   const MqlRates &bar,
                                   const int       phase_id,
                                   const color     col)
{
   if(phase_id < TRG_PHASE_1 || phase_id > TRG_PHASE_5)
      return;

   string base = engine_tag + "_PHASE_" + __TRG_RunTag() + "_" + __TRG_WindowTag() + "_"
               + IntegerToString((int)bar.time);

   __TRG_DrawTextUnique(base,
                        bar.time,
                        __TRG_PhaseLabelY(dir, bar),
                        IntegerToString(phase_id),
                        col,
                        9);
}

inline void __TRG_DrawBoundaryLabelEx(const string    engine_tag,
                                      const Direction dir,
                                      const MqlRates &bar,
                                      const color     col)
{
   string text = (dir == DIR_UP ? "L" : "H");
   string base = engine_tag + "_BOUND_" + __TRG_RunTag() + "_" + __TRG_WindowTag();

   __TRG_DrawTextUnique(base,
                        bar.time,
                        __TRG_AnchorLabelY(dir, bar),
                        text,
                        col,
                        9);
}

inline void __TRG_DrawResetLabelEx(const string    engine_tag,
                                   const Direction dir,
                                   const MqlRates &bar,
                                   const color     col)
{
   string base = engine_tag + "_RESET_" + __TRG_RunTag() + "_" + __TRG_WindowTag() + "_"
               + IntegerToString((int)bar.time);

   __TRG_DrawTextUnique(base,
                        bar.time,
                        __TRG_ResetLabelY(dir, bar),
                        "F",
                        col,
                        10);
}

inline void __TRG_DrawTriggerMarkerEx(TriggerEngineCore &ctx,
                                      const string       engine_tag,
                                      const Direction    dir,
                                      const int          type_id,
                                      const datetime     ref_t,
                                      const datetime     hit_t,
                                      const double       level,
                                      const color        col)
{
   int serial = 0;
   string dir_tag = "U";

   if(dir == DIR_UP)
   {
      ctx.up_counter++;
      serial  = ctx.up_counter;
      dir_tag = "U";
   }
   else
   {
      ctx.dn_counter++;
      serial  = ctx.dn_counter;
      dir_tag = "D";
   }

   string base = engine_tag + "_HIT_" + __TRG_RunTag() + "_" + __TRG_WindowTag() + "_"
               + dir_tag + "_" + IntegerToString(serial) + "_"
               + IntegerToString(type_id);

   __TRG_DrawDashedLine(base + "_L", ref_t, hit_t, level, col);
   __TRG_DrawTextUnique(base + "_T", hit_t, level, "T", col, 10);
}

inline void __TRG_RecordTriggerHit(const Direction dir,
                                   const int       type_id,
                                   const int       src_idx,
                                   const double    level,
                                   const int       hit_idx,
                                   const MqlRates &rates[],
                                   const int       n)
{
   string sym = g_trigger_symbol;
   if(sym == "")
      sym = _Symbol;

   TriggerSLTP_OnTriggerFired(sym,
                              dir,
                              type_id,
                              src_idx,
                              level,
                              hit_idx,
                              rates,
                              n);

   TriggerStatement_OnNewTriggerAt(rates[hit_idx].time);
}

inline bool __TRG_BullSameBarTriggerAllowed(const MqlRates &bar)
{
   return __TRG_IsBullCandle(bar);
}

inline bool __TRG_BearSameBarTriggerAllowed(const MqlRates &bar)
{
   return __TRG_IsBearCandle(bar);
}

// ----------------------------------------------------------------------------
// Engine forward declarations (implemented in TriggerType1/TriggerType2)
// ----------------------------------------------------------------------------
void TriggerType1_ResetGlobals();
void TriggerType2_ResetGlobals();
void TriggerType1_OnWindowChanged();
void TriggerType2_OnWindowChanged();
void TriggerType1_ProcessBar(const string sym,
                             const MqlRates &rates[],
                             const int n,
                             const int bar_idx);
void TriggerType2_ProcessBar(const string sym,
                             const MqlRates &rates[],
                             const int n,
                             const int bar_idx);

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
   if(n <= 1)
      return;

   for(int i = 0; i < n - 1; ++i)
   {
      int best = i;
      for(int j = i + 1; j < n; ++j)
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

inline bool __TRG_SessionMatchesStop(const TriggerStartSession &sess,
                                     const int                  stop_kind,
                                     const int                  stop_ns,
                                     const Direction            stop_dir)
{
   if(!sess.active)
      return false;
   if(!__TRG_IsStopKind(stop_kind))
      return false;

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
   if(g_trigger_bridge.run_id != run_id)
   {
      g_trigger_bridge.run_id = run_id;
      full_reset = true;
   }

   if(!full_reset && g_trigger_bridge.bridge_seq == seq)
      return true;

   g_trigger_bridge.bridge_seq = seq;
   ArrayResize(g_trigger_events, 0);

   for(int i = 1; i <= seq; ++i)
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
      g_trigger_bridge.active                = false;
      g_trigger_bridge.active_start_seq      = -1;
      g_trigger_bridge.active_start_kind     = 0;
      g_trigger_bridge.active_start_ns       = WB15_NS_NONE;
      g_trigger_bridge.active_dir            = DIR_UP;
      g_trigger_bridge.active_start_time     = 0;
      g_trigger_bridge.active_start_bar_time = 0;

      TriggerType1_OnWindowChanged();
      TriggerType2_OnWindowChanged();
   }

   return true;
}

inline void __TRG_ApplyWindowAt(const datetime bar_time)
{
   TriggerStartSession sessions[TRG_MAX_ACTIVE_SESSIONS];
   for(int i = 0; i < TRG_MAX_ACTIVE_SESSIONS; ++i)
      __TRG_ClearSession(sessions[i]);

   int session_count = 0;
   int evt_count = ArraySize(g_trigger_events);

   for(int i = 0; i < evt_count; ++i)
   {
      TriggerEvent evt = g_trigger_events[i];
      if(evt.bar_time > bar_time)
         break;

      if(__TRG_IsStartKind(evt.kind))
      {
         for(int s = 0; s < session_count; ++s)
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
         for(int s = session_count - 1; s >= 0; --s)
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

   for(int s = session_count - 1; s >= 0; --s)
   {
      if(!sessions[s].active)
         continue;

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
   if(new_active     != g_trigger_bridge.active) changed = true;
   if(new_start_seq  != g_trigger_bridge.active_start_seq) changed = true;
   if(new_start_kind != g_trigger_bridge.active_start_kind) changed = true;
   if(new_start_ns   != g_trigger_bridge.active_start_ns) changed = true;
   if(new_dir        != g_trigger_bridge.active_dir) changed = true;
   if(new_start_time != g_trigger_bridge.active_start_time) changed = true;
   if(new_start_bar  != g_trigger_bridge.active_start_bar_time) changed = true;

   g_trigger_bridge.active                = new_active;
   g_trigger_bridge.active_start_seq      = new_start_seq;
   g_trigger_bridge.active_start_kind     = new_start_kind;
   g_trigger_bridge.active_start_ns       = new_start_ns;
   g_trigger_bridge.active_dir            = new_dir;
   g_trigger_bridge.active_start_time     = new_start_time;
   g_trigger_bridge.active_start_bar_time = new_start_bar;

   if(changed)
   {
      TriggerType1_OnWindowChanged();
      TriggerType2_OnWindowChanged();
   }
}

#include <WaveBot/TriggerType1.mqh>
#include <WaveBot/TriggerType2.mqh>

// ----------------------------------------------------------------------------
// Public feeder
// ----------------------------------------------------------------------------
inline void Trigger_ResetGlobals()
{
   g_trigger_bridge.run_id                = 0.0;
   g_trigger_bridge.bridge_seq            = 0;
   g_trigger_bridge.active                = false;
   g_trigger_bridge.active_start_seq      = -1;
   g_trigger_bridge.active_start_kind     = 0;
   g_trigger_bridge.active_start_ns       = WB15_NS_NONE;
   g_trigger_bridge.active_dir            = DIR_UP;
   g_trigger_bridge.active_start_time     = 0;
   g_trigger_bridge.active_start_bar_time = 0;

   g_trigger_symbol = "";
   ArrayResize(g_trigger_events, 0);

   TriggerType1_ResetGlobals();
   TriggerType2_ResetGlobals();
   TriggerSLTP_ResetGlobals();
}

inline void __TRG_ProcessLoadedBar(const string    sym,
                                   const MqlRates &rates[],
                                   const int       n,
                                   const int       bar_idx)
{
   if(sym == "")
      return;

   if(n <= 0 || bar_idx < 0 || bar_idx >= n)
      return;

   g_trigger_symbol = sym;

   const datetime bar_time = rates[bar_idx].time;
   __TRG_ApplyWindowAt(bar_time);

   if(!g_trigger_bridge.active)
      return;
   if(bar_time < g_trigger_bridge.active_start_bar_time)
      return;

   TriggerType1_ProcessBar(sym, rates, n, bar_idx);
   TriggerType2_ProcessBar(sym, rates, n, bar_idx);
}

inline void Trigger_OnTimer(const string sym)
{
   if(!__TRG_IsWorkerTF())
      return;
   if(sym == "")
      return;
   if(!__TRG_IsMajorWorld())
      return;

   g_trigger_symbol = sym;

   if(!__TRG_RebuildBridgeEvents(sym))
      return;

   const datetime probe_bar_time = __TRG_WorkerBarOpen(TimeCurrent());
   __TRG_ApplyWindowAt(probe_bar_time);

   datetime seed_time = 0;
   if(g_trigger_bridge.active && g_trigger_bridge.active_start_bar_time > 0)
      seed_time = g_trigger_bridge.active_start_bar_time;

   datetime t1 = TriggerType1_LastProcessedTime();
   datetime t2 = TriggerType2_LastProcessedTime();

   if(t1 > seed_time)
      seed_time = t1;
   if(t2 > seed_time)
      seed_time = t2;

   if(seed_time <= 0)
      return;

   int tfsec = PeriodSeconds((ENUM_TIMEFRAMES)Period());
   if(tfsec <= 0)
      tfsec = 60;

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
   if(!__TRG_IsWorkerTF())
      return;
   if(!__TRG_IsMajorWorld())
      return;
   if(sym == "")
      return;
   if(n <= 0 || bar_idx < 0 || bar_idx >= n)
      return;
   if(candidate_idx < -1)
      return;

   bool __unused_inside = insideHL[bar_idx];
   if(__unused_inside) { /* intentionally ignored */ }

   if(!__TRG_RebuildBridgeEvents(sym))
      return;

   __TRG_ProcessLoadedBar(sym, rates, n, bar_idx);
}

#endif // WAVEBOT_TRIGGER_MQH
