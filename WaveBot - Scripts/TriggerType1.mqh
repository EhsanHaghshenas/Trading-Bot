#ifndef WAVEBOT_TRIGGER_TYPE1_MQH
#define WAVEBOT_TRIGGER_TYPE1_MQH

#include <WaveBot/Types.mqh>
#include <WaveBot/Markers.mqh>

// Trigger Type 1 is an analysis-only engine that is armed ONLY after the
// M15->M1 coordinator reaches TRIGGER_READY.  It never changes any upstream
// TC/MTC/HW/IMB predicate and it contains no order/trade execution logic.

enum T1_CANDIDATE_STAGE
{
   T1_WAIT_PULLBACK_END       = 0,
   T1_WAIT_PULLBACK_LOW_TOUCH = 1,
   T1_WAIT_FINAL_TRIGGER      = 2,
   T1_TRIGGERED               = 3,
   T1_INVALID                 = 4
};

struct T1Candidate
{
   int id;
   int parent_id;
   int validation_context_id;
   int child_context_id;
   string generation;
   Direction direction;
   datetime creation_time;
   datetime stage1_time;
   datetime stage2_time;
   datetime stage3_time;
   datetime triggered_time;
   ulong triggered_msc;
   T1_CANDIDATE_STAGE stage;

   // Direction-neutral storage.  For UP these map to
   // InitialValidationLow / PullbackStartHigh / PullbackLow /
   // FinalTriggerHigh.  For DOWN they are the exact mirror levels.
   double validation_level;
   double pullback_start_level;
   double pullback_extreme;
   double final_trigger_level;
   double running_final_extreme;

   // Exact candle ownership for visual trigger levels.  These timestamps
   // identify the candle whose wick created each reference price.
   datetime validation_time;
   datetime pullback_start_time;
   datetime pullback_extreme_time;
   datetime final_trigger_time;
   datetime running_final_extreme_time;

   int initial_move_bars;
   bool invalidated;
};

struct T1MoveSeed
{
   bool active;
   Direction direction;
   int bars;
   datetime first_time;
   datetime last_time;
   // Candidate validation is owned by the active Validation Context.  This
   // cached value is informational only and mirrors that context while the
   // move seed is active.
   double validation_level;
   int validation_context_id;
   double last_high;
   double last_low;

   // A contrary candle can START a pullback before the pullback is fully
   // confirmed.  Keep that pending structure alive across later candles so a
   // delayed touch of the last directional candle's opposite wick (or a later
   // lower-high / higher-low) is still recognised as the same pullback.
   bool pullback_pending;
   datetime pending_start_time;
   double pending_anchor_level;
   double pending_start_level;
   datetime pending_start_level_time;
   double pending_extreme;
   datetime pending_extreme_time;
   double pending_last_high;
   double pending_last_low;
};

// ------------------------------------------------------------------
// Validation context
// ------------------------------------------------------------------
// The red validation line is NOT owned by every candidate.  It is a shared,
// branch-aware context for NEW candidates.  Stage 3 pushes a nested context;
// completion/invalidation of that context owner closes it.  Existing
// candidates keep the context/price captured at their own creation time.
struct T1ValidationContext
{
   int id;
   int parent_id;
   int owner_candidate_id; // 0 for the root context
   Direction direction;
   double level;
   datetime level_time;
   datetime created_time;
   bool open;
};

// Before the first root context exists, an opposite-colour candle may own the
// bullish/bearish validation wick.  Example UP: a red candle becomes the
// validation source only if its HIGH is broken before its LOW is touched.
struct T1BootstrapAnchor
{
   bool active;
   datetime time;
   double high;
   double low;
};

static bool g_t1_ready=false;
static Direction g_t1_direction=DIR_UP;
static string g_t1_generation="";
static datetime g_t1_ready_time=0;
static datetime g_t1_last_bar_time=0;
static int g_t1_next_candidate_id=1;
static T1Candidate g_t1_candidates[];
static int g_t1_candidate_count=0;
static T1TriggerEvent g_t1_events[];
static int g_t1_event_count=0;
static T1MoveSeed g_t1_seed;
static T1ValidationContext g_t1_contexts[];
static int g_t1_context_count=0;
static int g_t1_next_context_id=1;
static int g_t1_active_context_id=0;
static T1BootstrapAnchor g_t1_bootstrap_anchor;

// Per-bar tick cache.  Historical same-candle stage ordering is derived from
// real tick sequence whenever MT5 has it; it is never guessed from OHLC.
static string g_t1_tick_symbol="";
static ENUM_TIMEFRAMES g_t1_tick_tf=PERIOD_CURRENT;
static datetime g_t1_tick_bar_time=0;
static MqlTick g_t1_ticks[];
static int g_t1_tick_count=-1;

inline string T1_DirectionText(const Direction dir)
{
   return (dir==DIR_UP ? "UP" : "DOWN");
}

inline void T1_ResetSeed()
{
   g_t1_seed.active=false;
   g_t1_seed.direction=DIR_UP;
   g_t1_seed.bars=0;
   g_t1_seed.first_time=0;
   g_t1_seed.last_time=0;
   g_t1_seed.validation_level=0.0;
   g_t1_seed.validation_context_id=0;
   g_t1_seed.last_high=0.0;
   g_t1_seed.last_low=0.0;
   g_t1_seed.pullback_pending=false;
   g_t1_seed.pending_start_time=0;
   g_t1_seed.pending_anchor_level=0.0;
   g_t1_seed.pending_start_level=0.0;
   g_t1_seed.pending_start_level_time=0;
   g_t1_seed.pending_extreme=0.0;
   g_t1_seed.pending_extreme_time=0;
   g_t1_seed.pending_last_high=0.0;
   g_t1_seed.pending_last_low=0.0;
}


inline void T1_ResetBootstrapAnchor()
{
   g_t1_bootstrap_anchor.active=false;
   g_t1_bootstrap_anchor.time=0;
   g_t1_bootstrap_anchor.high=0.0;
   g_t1_bootstrap_anchor.low=0.0;
}

inline void T1_ResetValidationContexts()
{
   ArrayResize(g_t1_contexts,0);
   g_t1_context_count=0;
   g_t1_next_context_id=1;
   g_t1_active_context_id=0;
   T1_ResetBootstrapAnchor();
}

inline int T1_FindContextIndexByID(const int id)
{
   if(id<=0) return -1;
   for(int i=0;i<g_t1_context_count;i++)
      if(g_t1_contexts[i].id==id) return i;
   return -1;
}

inline int T1_ActiveContextIndex()
{
   return T1_FindContextIndexByID(g_t1_active_context_id);
}

inline bool T1_GetActiveValidation(double &level,datetime &level_time,int &context_id)
{
   const int idx=T1_ActiveContextIndex();
   if(idx<0 || !g_t1_contexts[idx].open) return false;
   level=g_t1_contexts[idx].level;
   level_time=g_t1_contexts[idx].level_time;
   context_id=g_t1_contexts[idx].id;
   return true;
}

inline datetime T1_ActiveContextCreatedTime()
{
   const int idx=T1_ActiveContextIndex();
   if(idx<0 || !g_t1_contexts[idx].open) return 0;
   return g_t1_contexts[idx].created_time;
}

inline bool T1_ContextIsNestedValid(const Direction dir,const double child_level,
                                    const double parent_level)
{
   return (dir==DIR_UP ? child_level>parent_level : child_level<parent_level);
}

inline void T1_ResetTickCache()
{
   g_t1_tick_symbol="";
   g_t1_tick_tf=PERIOD_CURRENT;
   g_t1_tick_bar_time=0;
   g_t1_tick_count=-1;
   ArrayResize(g_t1_ticks,0);
}

inline void T1_ClearActiveCandidates()
{
   ArrayResize(g_t1_candidates,0);
   g_t1_candidate_count=0;
}

inline void T1_ResetGlobals()
{
   g_t1_ready=false;
   g_t1_direction=DIR_UP;
   g_t1_generation="";
   g_t1_ready_time=0;
   g_t1_last_bar_time=0;
   g_t1_next_candidate_id=1;
   T1_ClearActiveCandidates();
   ArrayResize(g_t1_events,0);
   g_t1_event_count=0;
   T1_ResetSeed();
   T1_ResetValidationContexts();
   T1_ResetTickCache();
}

inline void T1_OnPipelineReset(const datetime event_time,const string reason)
{
   const bool was_ready=g_t1_ready;
   g_t1_ready=false;
   g_t1_generation="";
   g_t1_ready_time=0;
   g_t1_last_bar_time=0;
   T1_ClearActiveCandidates();
   T1_ResetSeed();
   T1_ResetValidationContexts();
   T1_ResetTickCache();
   if(was_ready && InpDebugPrints)
      Print("[T1] STOP trigger scan | reason=",reason,
            " | time=",TimeToString(event_time,TIME_DATE|TIME_MINUTES));
}

inline void T1_OnTriggerReady(const Direction dir,const datetime event_time,
                              const string generation)
{
   // Every new ready attempt starts a fresh Trigger-Type-1 candidate world.
   // Historical trigger events already completed earlier in the scan remain
   // archived; only unfinished candidates are discarded.
   g_t1_ready=true;
   g_t1_direction=dir;
   g_t1_generation=generation;
   g_t1_ready_time=event_time;
   g_t1_last_bar_time=0;
   T1_ClearActiveCandidates();
   T1_ResetSeed();
   T1_ResetValidationContexts();
   T1_ResetTickCache();
   if(InpDebugPrints)
      Print("[T1] ARMED direction=",T1_DirectionText(dir),
            " generation=",generation,
            " time=",TimeToString(event_time,TIME_DATE|TIME_MINUTES));
}

inline bool T1_IsArmed()
{
   return g_t1_ready;
}

inline int T1_TriggerEventCount()
{
   return g_t1_event_count;
}

inline bool T1_GetTriggerEvent(const int index,T1TriggerEvent &out)
{
   if(index<0 || index>=g_t1_event_count) return false;
   out=g_t1_events[index];
   return true;
}

inline int T1_PrimaryCandidateID()
{
   int best=0;
   for(int i=0;i<g_t1_candidate_count;i++)
   {
      if(g_t1_candidates[i].invalidated ||
         g_t1_candidates[i].stage==T1_TRIGGERED ||
         g_t1_candidates[i].stage==T1_INVALID)
         continue;
      if(g_t1_candidates[i].id>best) best=g_t1_candidates[i].id;
   }
   return best;
}

inline double T1_TickPrice(const MqlTick &tick)
{
   if(tick.bid>0.0)  return tick.bid;
   if(tick.last>0.0) return tick.last;
   return tick.ask;
}

inline int T1_LoadTicks(const string sym,const ENUM_TIMEFRAMES tf,
                        const datetime bar_time)
{
   if(g_t1_tick_symbol==sym && g_t1_tick_tf==tf &&
      g_t1_tick_bar_time==bar_time && g_t1_tick_count>=0)
      return g_t1_tick_count;

   g_t1_tick_symbol=sym;
   g_t1_tick_tf=tf;
   g_t1_tick_bar_time=bar_time;
   g_t1_tick_count=0;
   ArrayResize(g_t1_ticks,0);

   const int seconds=PeriodSeconds(tf);
   if(seconds<=0 || bar_time<=0) return 0;
   const ulong from_msc=(ulong)((long)bar_time)*1000;
   const ulong to_msc=(ulong)((long)bar_time+seconds)*1000-1;
   int copied=-1;
   int last_error=0;
   for(int attempt=0;attempt<3;attempt++)
   {
      ResetLastError();
      copied=CopyTicksRange(sym,g_t1_ticks,COPY_TICKS_ALL,from_msc,to_msc);
      last_error=GetLastError();
      if(copied>=0) break;
      Sleep(20);
   }
   if(copied>0)
      g_t1_tick_count=copied;
   else
   {
      g_t1_tick_count=0;
      if(InpDebugPrints)
         Print("[T1] Tick sequence unavailable for ",sym," ",EnumToString(tf),
               " ",TimeToString(bar_time,TIME_DATE|TIME_MINUTES),
               " | same-candle ambiguous transitions will NOT be guessed | err=",
               last_error);
   }
   return g_t1_tick_count;
}

inline int T1_Stage1ActivationTickIndex(const T1MoveSeed &seed,
                                         const Direction dir)
{
   if(g_t1_tick_count<=0) return -1;
   // The user's explicit same-candle rule defines the pullback-side event as
   // touching/breaking the LAST directional candle's opposite wick while the
   // currently captured shared validation context remains intact.  For a one-candle initial move
   // this cannot happen without touching validation, so same-candle S1->S2 is
   // naturally unavailable; for multi-candle moves it is deterministic.
   for(int i=0;i<g_t1_tick_count;i++)
   {
      const double p=T1_TickPrice(g_t1_ticks[i]);
      if(p<=0.0) continue;
      if(dir==DIR_UP)
      {
         if(p<=seed.last_low && p>seed.validation_level) return i;
      }
      else
      {
         if(p>=seed.last_high && p<seed.validation_level) return i;
      }
   }
   return -1;
}

inline double T1_MarkerY(const MqlRates &bar,const Direction dir,const int slot)
{
   double point=SymbolInfoDouble(WB_ActiveSymbol(),SYMBOL_POINT);
   if(point<=0.0) point=_Point;
   const double candle=MathMax(0.0,bar.high-bar.low);
   const double step=MathMax(10.0*point,candle*0.18);
   return (dir==DIR_UP ? bar.low-step*(slot+1) : bar.high+step*(slot+1));
}

inline void T1_DrawMarker(const T1Candidate &c,const MqlRates &bar,
                          const string text,const string key,const int slot,
                          const color tone)
{
   if(!Markers_ShouldRender()) return;
   const string name=__ScanPrefix()+"T1_"+IntegerToString(c.id)+"_"+key+"_"+
                     IntegerToString((int)(long)bar.time);
   if(ObjectFind(0,name)!=-1) ObjectDelete(0,name);
   if(!ObjectCreate(0,name,OBJ_TEXT,0,bar.time,T1_MarkerY(bar,c.direction,slot)))
      return;
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,
                   text+" | Candidate="+IntegerToString(c.id)+
                   " | Parent="+IntegerToString(c.parent_id)+
                   " | "+T1_DirectionText(c.direction)+
                   " | "+TimeToString(bar.time,TIME_DATE|TIME_MINUTES));
   ObjectSetInteger(0,name,OBJPROP_COLOR,tone);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_CENTER);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
}

inline datetime T1_LevelEndTime(const string sym,const ENUM_TIMEFRAMES tf,
                                     const datetime source_time)
{
   if(source_time<=0) return 0;

   // Timeseries shift decreases as time moves forward.  Prefer the timestamp
   // of the actual third later candle so weekend/session gaps do not stretch
   // the visual by synthetic bars.
   const int shift=iBarShift(sym,tf,source_time,true);
   if(shift>=3)
   {
      const datetime actual=iTime(sym,tf,shift-3);
      if(actual>source_time) return actual;
   }

   // Near the live edge there may not yet be three future bars.  Project the
   // three-bar visual length; the analytical level itself is unaffected.
   const int seconds=PeriodSeconds(tf);
   if(seconds>0) return source_time+(datetime)(3*seconds);
   return source_time+180;
}

inline void T1_DrawLevel(const T1Candidate &c,const string sym,
                         const ENUM_TIMEFRAMES tf,const string key,
                         const string label,const datetime source_time,
                         const double price,const color tone)
{
   if(!Markers_ShouldRender() || source_time<=0 || price<=0.0) return;
   const datetime end_time=T1_LevelEndTime(sym,tf,source_time);
   if(end_time<=source_time) return;

   const string name=__ScanPrefix()+"T1_"+IntegerToString(c.id)+"_LVL_"+key+"_"+
                     IntegerToString((int)(long)source_time);
   if(ObjectFind(0,name)!=-1) ObjectDelete(0,name);
   if(!ObjectCreate(0,name,OBJ_TREND,0,source_time,price,end_time,price))
      return;

   ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DASH);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_COLOR,tone);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,
                   label+" | Candidate="+IntegerToString(c.id)+
                   " | "+T1_DirectionText(c.direction)+
                   " | price="+DoubleToString(price,_Digits)+
                   " | source="+TimeToString(source_time,TIME_DATE|TIME_MINUTES));
}


inline void T1_DrawValidationContext(const T1ValidationContext &ctx,
                                     const string sym,const ENUM_TIMEFRAMES tf)
{
   // The user explicitly requested the bullish validation reference as a red
   // dashed line.  Keep the bearish context logical/mirrored without adding
   // extra visual noise that was not requested.
   if(ctx.direction!=DIR_UP || !Markers_ShouldRender() ||
      ctx.level_time<=0 || ctx.level<=0.0) return;
   const datetime end_time=T1_LevelEndTime(sym,tf,ctx.level_time);
   if(end_time<=ctx.level_time) return;

   const string name=__ScanPrefix()+"T1_CTX_"+IntegerToString(ctx.id)+"_VALID_"+
                     IntegerToString((int)(long)ctx.level_time);
   if(ObjectFind(0,name)!=-1) ObjectDelete(0,name);
   if(!ObjectCreate(0,name,OBJ_TREND,0,ctx.level_time,ctx.level,
                    end_time,ctx.level)) return;
   ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DASH);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrRed);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,
                   "ActiveValidationLow | Context="+IntegerToString(ctx.id)+
                   " | OwnerCandidate="+IntegerToString(ctx.owner_candidate_id)+
                   " | price="+DoubleToString(ctx.level,_Digits)+
                   " | source="+TimeToString(ctx.level_time,TIME_DATE|TIME_MINUTES));
}

inline int T1_CreateValidationContext(const string sym,const ENUM_TIMEFRAMES tf,
                                      const Direction dir,const double level,
                                      const datetime level_time,const int parent_id,
                                      const int owner_candidate_id,
                                      const datetime created_time)
{
   if(level<=0.0 || level_time<=0) return 0;
   if(parent_id>0)
   {
      const int pidx=T1_FindContextIndexByID(parent_id);
      if(pidx<0 || !T1_ContextIsNestedValid(dir,level,g_t1_contexts[pidx].level))
         return 0;
   }

   const int n=g_t1_context_count+1;
   if(ArrayResize(g_t1_contexts,n)!=n) return 0;
   const int idx=n-1;
   g_t1_contexts[idx].id=g_t1_next_context_id++;
   g_t1_contexts[idx].parent_id=parent_id;
   g_t1_contexts[idx].owner_candidate_id=owner_candidate_id;
   g_t1_contexts[idx].direction=dir;
   g_t1_contexts[idx].level=level;
   g_t1_contexts[idx].level_time=level_time;
   g_t1_contexts[idx].created_time=created_time;
   g_t1_contexts[idx].open=true;
   g_t1_context_count=n;
   g_t1_active_context_id=g_t1_contexts[idx].id;
   T1_DrawValidationContext(g_t1_contexts[idx],sym,tf);
   if(InpDebugPrints)
      Print("[T1] VALIDATION CONTEXT PUSH id=",g_t1_contexts[idx].id,
            " parent=",parent_id," owner=",owner_candidate_id,
            " level=",DoubleToString(level,_Digits),
            " source=",TimeToString(level_time,TIME_DATE|TIME_MINUTES));
   return g_t1_contexts[idx].id;
}

inline bool T1_ContextChainIsOpen(const int context_id)
{
   int current=context_id;
   int guard=0;
   while(current>0 && guard<64)
   {
      const int idx=T1_FindContextIndexByID(current);
      if(idx<0 || !g_t1_contexts[idx].open) return false;
      current=g_t1_contexts[idx].parent_id;
      guard++;
   }
   return (current==0);
}

inline void T1_ResolveActiveContext()
{
   // Only an open context with an entirely open ancestor chain may own NEW
   // candidates.  Existing candidates keep their captured validation even if
   // an ancestor context later closes.
   int newest_id=0;
   for(int i=0;i<g_t1_context_count;i++)
      if(g_t1_contexts[i].open && T1_ContextChainIsOpen(g_t1_contexts[i].id) &&
         g_t1_contexts[i].id>newest_id)
         newest_id=g_t1_contexts[i].id;
   g_t1_active_context_id=newest_id;
}

inline void T1_CloseContextByID(const int context_id,const string reason)
{
   const int idx=T1_FindContextIndexByID(context_id);
   if(idx<0 || !g_t1_contexts[idx].open) return;
   g_t1_contexts[idx].open=false;
   if(InpDebugPrints)
      Print("[T1] VALIDATION CONTEXT CLOSE id=",context_id,
            " owner=",g_t1_contexts[idx].owner_candidate_id," | ",reason);
   T1_ResolveActiveContext();
}

inline void T1_CloseOwnedContext(const int owner_candidate_id,const string reason)
{
   if(owner_candidate_id<=0) return;
   bool changed=false;
   for(int i=0;i<g_t1_context_count;i++)
   {
      if(g_t1_contexts[i].open &&
         g_t1_contexts[i].owner_candidate_id==owner_candidate_id)
      {
         g_t1_contexts[i].open=false;
         changed=true;
         if(InpDebugPrints)
            Print("[T1] VALIDATION CONTEXT POP id=",g_t1_contexts[i].id,
                  " owner=",owner_candidate_id," | ",reason);
      }
   }
   if(changed) T1_ResolveActiveContext();
}

inline void T1_PushStage3Context(T1Candidate &c,const string sym,
                                 const ENUM_TIMEFRAMES tf,const datetime event_time)
{
   if(c.child_context_id>0) return;
   // Stage 3 promotes this candidate's frozen PullbackLow/High into the
   // validation reference for NEWER structures.  Existing candidates retain
   // their own previously captured validation context.
   const int child=T1_CreateValidationContext(sym,tf,c.direction,
                    c.pullback_extreme,c.pullback_extreme_time,
                    c.validation_context_id,c.id,event_time);
   if(child>0) c.child_context_id=child;
}

inline void T1_MarkInvalid(T1Candidate &c,const string reason,
                           const datetime event_time)
{
   c.invalidated=true;
   c.stage=T1_INVALID;
   T1_CloseOwnedContext(c.id,"candidate invalidated");
   if(InpDebugPrints)
      Print("[T1] Candidate ",c.id," INVALID | ",reason,
            " | ",TimeToString(event_time,TIME_DATE|TIME_MINUTES));
}

inline void T1_MarkStage2(T1Candidate &c,const string sym,
                          const ENUM_TIMEFRAMES tf,const MqlRates &bar)
{
   if(c.stage!=T1_WAIT_PULLBACK_END) return;
   c.stage2_time=bar.time;
   c.stage=T1_WAIT_PULLBACK_LOW_TOUCH;
   c.running_final_extreme=c.pullback_start_level;
   c.running_final_extreme_time=c.pullback_start_time;
   T1_DrawMarker(c,bar,"T1-S2","S2",1,clrDeepSkyBlue);
   // Stage 3 now waits for the frozen PullbackLow/High.  Draw that exact
   // wick-owned reference for three candles from the candle that created it.
   T1_DrawLevel(c,sym,tf,"PB_EXT",
                (c.direction==DIR_UP ? "PullbackLow" : "PullbackHigh"),
                c.pullback_extreme_time,c.pullback_extreme,clrGold);
}

inline void T1_MarkStage3(T1Candidate &c,const string sym,
                          const ENUM_TIMEFRAMES tf,const MqlRates &bar)
{
   if(c.stage!=T1_WAIT_PULLBACK_LOW_TOUCH) return;
   c.stage3_time=bar.time;
   c.final_trigger_level=c.running_final_extreme;
   c.final_trigger_time=c.running_final_extreme_time;
   c.stage=T1_WAIT_FINAL_TRIGGER;
   T1_DrawMarker(c,bar,"T1-S3","S3",2,clrGold);
   // Stage 4 waits for this exact FinalTriggerHigh/Low.
   T1_DrawLevel(c,sym,tf,"FINAL",
                (c.direction==DIR_UP ? "FinalTriggerHigh" : "FinalTriggerLow"),
                c.final_trigger_time,c.final_trigger_level,clrLime);
   T1_PushStage3Context(c,sym,tf,bar.time);
}

inline void T1_EmitTrigger(T1Candidate &c,const MqlRates &bar,const ulong trigger_msc)
{
   if(c.stage!=T1_WAIT_FINAL_TRIGGER) return;
   const int n=g_t1_event_count+1;
   ArrayResize(g_t1_events,n);
   const int e=n-1;
   g_t1_events[e].candidate_id=c.id;
   g_t1_events[e].parent_candidate_id=c.parent_id;
   g_t1_events[e].generation=c.generation;
   g_t1_events[e].direction=c.direction;
   g_t1_events[e].trigger_time=bar.time;
   g_t1_events[e].trigger_msc=trigger_msc;
   g_t1_events[e].validation_level=c.validation_level;
   g_t1_events[e].pullback_start_level=c.pullback_start_level;
   g_t1_events[e].pullback_extreme=c.pullback_extreme;
   g_t1_events[e].final_trigger_level=c.final_trigger_level;
   g_t1_event_count=n;

   c.triggered_time=bar.time;
   c.triggered_msc=trigger_msc;
   c.stage=T1_TRIGGERED;
   T1_CloseOwnedContext(c.id,"trigger completed");
   // Final marker text is intentionally EXACTLY T1-1.
   T1_DrawMarker(c,bar,"T1-1","FINAL",3+(c.id%3),clrLime);
   if(InpDebugPrints)
      Print("[T1] ",(c.direction==DIR_UP ? "TRIGGER_TYPE_1_BULLISH" :
                                      "TRIGGER_TYPE_1_BEARISH"),
            " | candidate=",c.id,
            " parent=",c.parent_id,
            " generation=",c.generation,
            " time=",TimeToString(bar.time,TIME_DATE|TIME_MINUTES),
            " tick_msc=",trigger_msc,
            " validation=",DoubleToString(c.validation_level,_Digits),
            " pullbackStart=",DoubleToString(c.pullback_start_level,_Digits),
            " pullbackExtreme=",DoubleToString(c.pullback_extreme,_Digits),
            " final=",DoubleToString(c.final_trigger_level,_Digits));
}

inline void T1_ProcessCandidateTickAt(T1Candidate &c,const string sym,
                                      const ENUM_TIMEFRAMES tf,const MqlRates &bar,
                                      const int tick_index)
{
   if(c.invalidated || c.stage==T1_TRIGGERED || c.stage==T1_INVALID) return;
   if(tick_index<0 || tick_index>=g_t1_tick_count) return;
   const double p=T1_TickPrice(g_t1_ticks[tick_index]);
   if(p<=0.0) return;

   // Re-evaluate this exact market tick after a stage transition.  This keeps
   // a candidate internally deterministic while the caller advances ALL
   // candidates through the bar in one shared chronological tick stream.
   for(int guard=0;guard<4;guard++)
   {
      if(c.invalidated || c.stage==T1_TRIGGERED || c.stage==T1_INVALID)
         return;
      const T1_CANDIDATE_STAGE before=c.stage;

      if(c.direction==DIR_UP)
      {
         if(p<=c.validation_level)
         {
            T1_MarkInvalid(c,"InitialValidationLow touched",bar.time);
            return;
         }
         if(c.stage==T1_WAIT_PULLBACK_END)
         {
            if(p<c.pullback_extreme)
            {
               c.pullback_extreme=p;
               c.pullback_extreme_time=bar.time;
            }
            if(p>=c.pullback_start_level)
            {
               T1_MarkStage2(c,sym,tf,bar);
               c.running_final_extreme=p;
               c.running_final_extreme_time=bar.time;
            }
         }
         else if(c.stage==T1_WAIT_PULLBACK_LOW_TOUCH)
         {
            if(p>c.running_final_extreme)
            {
               c.running_final_extreme=p;
               c.running_final_extreme_time=bar.time;
            }
            if(p<=c.pullback_extreme)
               T1_MarkStage3(c,sym,tf,bar);
         }
         else if(c.stage==T1_WAIT_FINAL_TRIGGER)
         {
            if(p>=c.final_trigger_level)
               T1_EmitTrigger(c,bar,g_t1_ticks[tick_index].time_msc);
         }
      }
      else
      {
         if(p>=c.validation_level)
         {
            T1_MarkInvalid(c,"InitialValidationHigh touched",bar.time);
            return;
         }
         if(c.stage==T1_WAIT_PULLBACK_END)
         {
            if(p>c.pullback_extreme)
            {
               c.pullback_extreme=p;
               c.pullback_extreme_time=bar.time;
            }
            if(p<=c.pullback_start_level)
            {
               T1_MarkStage2(c,sym,tf,bar);
               c.running_final_extreme=p;
               c.running_final_extreme_time=bar.time;
            }
         }
         else if(c.stage==T1_WAIT_PULLBACK_LOW_TOUCH)
         {
            if(p<c.running_final_extreme)
            {
               c.running_final_extreme=p;
               c.running_final_extreme_time=bar.time;
            }
            if(p>=c.pullback_extreme)
               T1_MarkStage3(c,sym,tf,bar);
         }
         else if(c.stage==T1_WAIT_FINAL_TRIGGER)
         {
            if(p<=c.final_trigger_level)
               T1_EmitTrigger(c,bar,g_t1_ticks[tick_index].time_msc);
         }
      }

      if(c.stage==before) break;
   }
}

inline void T1_ProcessCandidateTicks(T1Candidate &c,const string sym,
                                     const ENUM_TIMEFRAMES tf,const MqlRates &bar,
                                     const int first_tick)
{
   if(c.invalidated || c.stage==T1_TRIGGERED || c.stage==T1_INVALID) return;
   int start=first_tick;
   if(start<0) start=0;
   if(start>=g_t1_tick_count) return;
   for(int k=start;k<g_t1_tick_count;k++)
   {
      T1_ProcessCandidateTickAt(c,sym,tf,bar,k);
      if(c.invalidated || c.stage==T1_TRIGGERED || c.stage==T1_INVALID) return;
   }
}

inline void T1_ProcessCandidateOHLCFallback(T1Candidate &c,const string sym,
                                            const ENUM_TIMEFRAMES tf,const MqlRates &bar,
                                            const bool created_this_bar)
{
   if(c.invalidated || c.stage==T1_TRIGGERED || c.stage==T1_INVALID) return;

   // Fail closed whenever OHLC alone cannot establish intrabar order.  This
   // keeps historical reconstruction deterministic instead of inventing the
   // required Low->High / High->Low sequence.
   if(c.direction==DIR_UP)
   {
      if(bar.low<=c.validation_level)
      {
         T1_MarkInvalid(c,"validation touched while tick order unavailable",bar.time);
         return;
      }
      if(c.stage==T1_WAIT_PULLBACK_END)
      {
         if(created_this_bar)
         {
            if(bar.high>=c.pullback_start_level)
               T1_MarkInvalid(c,"ambiguous same-candle S1/S2 without ticks",bar.time);
            return;
         }
         if(bar.high>=c.pullback_start_level)
         {
            if(bar.low<c.pullback_extreme)
            {
               T1_MarkInvalid(c,"ambiguous Stage2 pullback-low order without ticks",bar.time);
               return;
            }
            T1_MarkStage2(c,sym,tf,bar);
            c.running_final_extreme=bar.high;
            c.running_final_extreme_time=bar.time;
            return; // do not guess S2->S3 order on this candle
         }
         if(bar.low<c.pullback_extreme)
         {
            c.pullback_extreme=bar.low;
            c.pullback_extreme_time=bar.time;
         }
         return;
      }
      if(c.stage==T1_WAIT_PULLBACK_LOW_TOUCH)
      {
         if(bar.low<=c.pullback_extreme)
         {
            if(bar.high>=c.running_final_extreme)
            {
               T1_MarkInvalid(c,"ambiguous Stage3/Stage4 order without ticks",bar.time);
               return;
            }
            T1_MarkStage3(c,sym,tf,bar);
            return;
         }
         if(bar.high>c.running_final_extreme)
         {
            c.running_final_extreme=bar.high;
            c.running_final_extreme_time=bar.time;
         }
         return;
      }
      if(c.stage==T1_WAIT_FINAL_TRIGGER)
      {
         if(bar.high>=c.final_trigger_level)
            T1_EmitTrigger(c,bar,0);
      }
      return;
   }

   if(bar.high>=c.validation_level)
   {
      T1_MarkInvalid(c,"validation touched while tick order unavailable",bar.time);
      return;
   }
   if(c.stage==T1_WAIT_PULLBACK_END)
   {
      if(created_this_bar)
      {
         if(bar.low<=c.pullback_start_level)
            T1_MarkInvalid(c,"ambiguous same-candle S1/S2 without ticks",bar.time);
         return;
      }
      if(bar.low<=c.pullback_start_level)
      {
         if(bar.high>c.pullback_extreme)
         {
            T1_MarkInvalid(c,"ambiguous Stage2 pullback-high order without ticks",bar.time);
            return;
         }
         T1_MarkStage2(c,sym,tf,bar);
         c.running_final_extreme=bar.low;
         c.running_final_extreme_time=bar.time;
         return;
      }
      if(bar.high>c.pullback_extreme)
      {
         c.pullback_extreme=bar.high;
         c.pullback_extreme_time=bar.time;
      }
      return;
   }
   if(c.stage==T1_WAIT_PULLBACK_LOW_TOUCH)
   {
      if(bar.high>=c.pullback_extreme)
      {
         if(bar.low<=c.running_final_extreme)
         {
            T1_MarkInvalid(c,"ambiguous Stage3/Stage4 order without ticks",bar.time);
            return;
         }
         T1_MarkStage3(c,sym,tf,bar);
         return;
      }
      if(bar.low<c.running_final_extreme)
      {
         c.running_final_extreme=bar.low;
         c.running_final_extreme_time=bar.time;
      }
      return;
   }
   if(c.stage==T1_WAIT_FINAL_TRIGGER)
   {
      if(bar.low<=c.final_trigger_level)
         T1_EmitTrigger(c,bar,0);
   }
}

inline double T1_CandidateOpenBoundary(const T1Candidate &c)
{
   if(c.stage==T1_WAIT_PULLBACK_END)
      return c.pullback_start_level;
   if(c.stage==T1_WAIT_PULLBACK_LOW_TOUCH)
      return c.running_final_extreme;
   if(c.stage==T1_WAIT_FINAL_TRIGGER)
      return c.final_trigger_level;
   return c.pullback_start_level;
}

inline int T1_FindNewestContainingParent(const double new_validation,
                                         const double new_start)
{
   int id=0;
   for(int i=0;i<g_t1_candidate_count;i++)
   {
      const T1Candidate c=g_t1_candidates[i];
      if(c.invalidated || c.stage==T1_INVALID || c.stage==T1_TRIGGERED ||
         c.direction!=g_t1_direction)
         continue;
      const double open_boundary=T1_CandidateOpenBoundary(c);
      bool inside=false;
      if(g_t1_direction==DIR_UP)
         inside=(new_validation>=c.validation_level &&
                 new_start<=open_boundary);
      else
         inside=(new_validation<=c.validation_level &&
                 new_start>=open_boundary);
      if(inside && c.id>id) id=c.id;
   }
   return id;
}

inline int T1_CreateCandidateFromSeed(const string sym,const ENUM_TIMEFRAMES tf,
                                      const MqlRates &bar,
                                      const double pullback_start_level,
                                      const datetime pullback_start_time,
                                      const double pullback_extreme,
                                      const datetime pullback_extreme_time)
{
   double active_validation=0.0;
   datetime active_validation_time=0;
   int active_context_id=0;
   if(!T1_GetActiveValidation(active_validation,active_validation_time,active_context_id))
      return -1;

   // A candidate created under the current red context must already respect
   // that context.  Do not let an older move seed manufacture a candidate
   // whose pullback has crossed the newly-active validation line.
   if(g_t1_direction==DIR_UP && pullback_extreme<=active_validation) return -1;
   if(g_t1_direction==DIR_DOWN && pullback_extreme>=active_validation) return -1;

   const int n=g_t1_candidate_count+1;
   if(ArrayResize(g_t1_candidates,n)!=n) return -1;
   const int idx=n-1;
   T1Candidate c;
   c.id=g_t1_next_candidate_id++;
   const double new_start=pullback_start_level;
   c.parent_id=T1_FindNewestContainingParent(active_validation,new_start);
   c.validation_context_id=active_context_id;
   c.child_context_id=0;
   c.generation=g_t1_generation;
   c.direction=g_t1_direction;
   c.creation_time=bar.time;
   c.stage1_time=bar.time;
   c.stage2_time=0;
   c.stage3_time=0;
   c.triggered_time=0;
   c.triggered_msc=0;
   c.stage=T1_WAIT_PULLBACK_END;
   c.validation_level=active_validation;
   c.pullback_start_level=pullback_start_level;
   c.pullback_extreme=pullback_extreme;
   c.final_trigger_level=0.0;
   c.running_final_extreme=0.0;
   c.validation_time=active_validation_time;
   c.pullback_start_time=pullback_start_time;
   c.pullback_extreme_time=pullback_extreme_time;
   c.final_trigger_time=0;
   c.running_final_extreme_time=0;
   c.initial_move_bars=g_t1_seed.bars;
   c.invalidated=false;
   g_t1_candidates[idx]=c;
   g_t1_candidate_count=n;
   T1_DrawMarker(g_t1_candidates[idx],bar,"T1-S1","S1",0,clrSilver);

   // Stage 2 target is the structural wick that must be reclaimed after the
   // pullback.  Normal lower-high/higher-low pullbacks keep the last
   // directional candle's wick.  An outside/pending pullback uses the actual
   // highest/lowest wick created by the pullback-start sequence itself.
   T1_DrawLevel(g_t1_candidates[idx],sym,tf,"PB_START",
                (g_t1_direction==DIR_UP ? "PullbackStartHigh" : "PullbackStartLow"),
                g_t1_candidates[idx].pullback_start_time,
                g_t1_candidates[idx].pullback_start_level,clrDeepSkyBlue);


   if(InpDebugPrints)
      Print("[T1] Stage1 candidate=",g_t1_candidates[idx].id,
            " parent=",g_t1_candidates[idx].parent_id,
            " initialBars=",g_t1_candidates[idx].initial_move_bars,
            " direction=",T1_DirectionText(g_t1_direction),
            " time=",TimeToString(bar.time,TIME_DATE|TIME_MINUTES),
            " pullbackStart=",DoubleToString(pullback_start_level,_Digits));
   return idx;
}

inline void T1_StartSeed(const string sym,const ENUM_TIMEFRAMES tf,const MqlRates &bar)
{
   if(g_t1_active_context_id<=0)
      T1_CreateValidationContext(sym,tf,g_t1_direction,
                                 (g_t1_direction==DIR_UP ? bar.low : bar.high),
                                 bar.time,0,0,bar.time);

   double active_validation=0.0;
   datetime active_validation_time=0;
   int active_context_id=0;
   if(!T1_GetActiveValidation(active_validation,active_validation_time,active_context_id))
      return;

   g_t1_seed.active=true;
   g_t1_seed.direction=g_t1_direction;
   g_t1_seed.bars=1;
   g_t1_seed.first_time=bar.time;
   g_t1_seed.last_time=bar.time;
   g_t1_seed.validation_level=active_validation;
   g_t1_seed.validation_context_id=active_context_id;
   g_t1_seed.last_high=bar.high;
   g_t1_seed.last_low=bar.low;
   g_t1_seed.pullback_pending=false;
   g_t1_seed.pending_start_time=0;
   g_t1_seed.pending_anchor_level=0.0;
   g_t1_seed.pending_start_level=0.0;
   g_t1_seed.pending_start_level_time=0;
   g_t1_seed.pending_extreme=0.0;
   g_t1_seed.pending_extreme_time=0;
   g_t1_seed.pending_last_high=0.0;
   g_t1_seed.pending_last_low=0.0;
}

inline bool T1_IsDirectionalCandle(const MqlRates &bar)
{
   return (g_t1_direction==DIR_UP ? bar.close>bar.open : bar.close<bar.open);
}

inline void T1_BeginPendingPullback(const MqlRates &bar)
{
   g_t1_seed.pullback_pending=true;
   g_t1_seed.pending_start_time=bar.time;
   g_t1_seed.pending_anchor_level=(g_t1_direction==DIR_UP ?
                                   g_t1_seed.last_low : g_t1_seed.last_high);
   g_t1_seed.pending_start_level=(g_t1_direction==DIR_UP ? bar.high : bar.low);
   g_t1_seed.pending_start_level_time=bar.time;
   g_t1_seed.pending_extreme=(g_t1_direction==DIR_UP ? bar.low : bar.high);
   g_t1_seed.pending_extreme_time=bar.time;
   g_t1_seed.pending_last_high=bar.high;
   g_t1_seed.pending_last_low=bar.low;
}

inline void T1_UpdatePendingPullback(const MqlRates &bar)
{
   if(!g_t1_seed.pullback_pending) return;
   if(g_t1_direction==DIR_UP)
   {
      if(bar.high>g_t1_seed.pending_start_level)
      {
         g_t1_seed.pending_start_level=bar.high;
         g_t1_seed.pending_start_level_time=bar.time;
      }
      if(bar.low<g_t1_seed.pending_extreme)
      {
         g_t1_seed.pending_extreme=bar.low;
         g_t1_seed.pending_extreme_time=bar.time;
      }
   }
   else
   {
      if(bar.low<g_t1_seed.pending_start_level)
      {
         g_t1_seed.pending_start_level=bar.low;
         g_t1_seed.pending_start_level_time=bar.time;
      }
      if(bar.high>g_t1_seed.pending_extreme)
      {
         g_t1_seed.pending_extreme=bar.high;
         g_t1_seed.pending_extreme_time=bar.time;
      }
   }
}

inline void T1_ProcessNewCandidateSameBar(const string sym,const ENUM_TIMEFRAMES tf,
                                          const MqlRates &bar,const int ci,
                                          const bool activation_by_anchor,
                                          const double prior_extreme,
                                          const datetime prior_extreme_time)
{
   const int ticks=T1_LoadTicks(sym,tf,bar.time);
   if(ticks>0 && activation_by_anchor)
   {
      const int activation=T1_Stage1ActivationTickIndex(g_t1_seed,g_t1_direction);
      if(activation>=0)
      {
         // Rebuild the PullbackLow/High only from information that actually
         // existed AT the activation tick.  Never seed it with this candle's
         // final OHLC extreme, because that could occur later in the bar.
         const double p=T1_TickPrice(g_t1_ticks[activation]);
         if(prior_extreme>0.0)
         {
            if(g_t1_direction==DIR_UP)
            {
               if(prior_extreme<p)
               {
                  g_t1_candidates[ci].pullback_extreme=prior_extreme;
                  g_t1_candidates[ci].pullback_extreme_time=prior_extreme_time;
               }
               else
               {
                  g_t1_candidates[ci].pullback_extreme=p;
                  g_t1_candidates[ci].pullback_extreme_time=bar.time;
               }
            }
            else
            {
               if(prior_extreme>p)
               {
                  g_t1_candidates[ci].pullback_extreme=prior_extreme;
                  g_t1_candidates[ci].pullback_extreme_time=prior_extreme_time;
               }
               else
               {
                  g_t1_candidates[ci].pullback_extreme=p;
                  g_t1_candidates[ci].pullback_extreme_time=bar.time;
               }
            }
         }
         else
         {
            g_t1_candidates[ci].pullback_extreme=p;
            g_t1_candidates[ci].pullback_extreme_time=bar.time;
         }

         // If the Stage-2 reference High/Low itself belongs to THIS pullback
         // candle (e.g. the bearish outside candle requested by the user), its
         // final wick is only known at candle close.  Therefore it may be
         // reclaimed only from the NEXT candle onward; do not look ahead.
         if(g_t1_candidates[ci].pullback_start_time<bar.time)
            T1_ProcessCandidateTicks(g_t1_candidates[ci],sym,tf,bar,activation+1);
      }
      return;
   }

   // A lower-high / higher-low is only knowable after the candle is complete.
   // Do not invent an intrabar activation time for it.  OHLC fallback keeps
   // same-candle S1->S2 fail-closed in exactly that case.
   if(ticks<=0)
      T1_ProcessCandidateOHLCFallback(g_t1_candidates[ci],sym,tf,bar,true);
}


inline void T1_SetBootstrapAnchor(const MqlRates &bar)
{
   g_t1_bootstrap_anchor.active=true;
   g_t1_bootstrap_anchor.time=bar.time;
   g_t1_bootstrap_anchor.high=bar.high;
   g_t1_bootstrap_anchor.low=bar.low;
}

inline bool T1_BootstrapAnchorBreaksTrendSideFirst(const string sym,
                                                   const ENUM_TIMEFRAMES tf,
                                                   const MqlRates &bar)
{
   if(!g_t1_bootstrap_anchor.active) return false;
   const int ticks=T1_LoadTicks(sym,tf,bar.time);
   if(ticks>0)
   {
      for(int k=0;k<ticks;k++)
      {
         const double p=T1_TickPrice(g_t1_ticks[k]);
         if(p<=0.0) continue;
         if(g_t1_direction==DIR_UP)
         {
            if(p<=g_t1_bootstrap_anchor.low) return false;
            if(p>=g_t1_bootstrap_anchor.high) return true;
         }
         else
         {
            if(p>=g_t1_bootstrap_anchor.high) return false;
            if(p<=g_t1_bootstrap_anchor.low) return true;
         }
      }
      return false;
   }

   // OHLC can prove the order only when the invalidation side was untouched.
   if(g_t1_direction==DIR_UP)
      return (bar.high>=g_t1_bootstrap_anchor.high &&
              bar.low>g_t1_bootstrap_anchor.low);
   return (bar.low<=g_t1_bootstrap_anchor.low &&
           bar.high<g_t1_bootstrap_anchor.high);
}

inline bool T1_TryCreateRootContextFromOppositeAnchor(const string sym,
                                                       const ENUM_TIMEFRAMES tf,
                                                       const MqlRates &bar)
{
   if(g_t1_active_context_id>0 || !g_t1_bootstrap_anchor.active) return false;
   if(!T1_BootstrapAnchorBreaksTrendSideFirst(sym,tf,bar)) return false;

   const double level=(g_t1_direction==DIR_UP ?
                       g_t1_bootstrap_anchor.low : g_t1_bootstrap_anchor.high);
   const datetime source_time=g_t1_bootstrap_anchor.time;
   const int ctx=T1_CreateValidationContext(sym,tf,g_t1_direction,level,
                                            source_time,0,0,bar.time);
   if(ctx<=0) return false;
   T1_ResetBootstrapAnchor();
   return true;
}

inline void T1_AdvanceSeedAndDetect(const string sym,const ENUM_TIMEFRAMES tf,
                                    const MqlRates &bar)
{
   const bool directional=T1_IsDirectionalCandle(bar);

   // Before the root validation context exists, an opposite-colour candle may
   // own it.  UP example: preserve the red candle Low only when its High is
   // broken first; touching its Low first invalidates that anchor.
   if(g_t1_active_context_id<=0)
   {
      const bool opposite=(g_t1_direction==DIR_UP ? bar.close<bar.open :
                                                    bar.close>bar.open);
      const bool activated=T1_TryCreateRootContextFromOppositeAnchor(sym,tf,bar);
      if(!activated && g_t1_bootstrap_anchor.active)
      {
         const bool invalidated=(g_t1_direction==DIR_UP ?
                                 bar.low<=g_t1_bootstrap_anchor.low :
                                 bar.high>=g_t1_bootstrap_anchor.high);
         if(invalidated) T1_ResetBootstrapAnchor();
      }
      if(g_t1_active_context_id<=0 && opposite)
         T1_SetBootstrapAnchor(bar);
   }

   if(!g_t1_seed.active)
   {
      if(directional) T1_StartSeed(sym,tf,bar);
      return;
   }

   // A Stage-3 push / Trigger pop changes the validation context for NEW
   // structures.  Rebind an unfinished move seed to that current context, but
   // never rewrite validation on candidates that already exist.
   double active_validation=0.0;
   datetime active_validation_time=0;
   int active_context_id=0;
   if(T1_GetActiveValidation(active_validation,active_validation_time,active_context_id) &&
      active_context_id!=g_t1_seed.validation_context_id)
   {
      g_t1_seed.validation_level=active_validation;
      g_t1_seed.validation_context_id=active_context_id;
   }

   // If the new context was created on THIS exact bar by Stage 3, the touch
   // that created it must not retroactively invalidate a seed earlier in the
   // same candle.  The new line governs subsequent price action/candidates.
   const bool context_created_this_bar=(T1_ActiveContextCreatedTime()==bar.time);
   const bool seed_invalid=(!context_created_this_bar &&
                            (g_t1_direction==DIR_UP ?
                             bar.low<=g_t1_seed.validation_level :
                             bar.high>=g_t1_seed.validation_level));
   if(seed_invalid)
   {
      T1_ResetSeed();
      if(directional) T1_StartSeed(sym,tf,bar);
      return;
   }

   // ---------------------------------------------------------------
   // Pending pullback
   // ---------------------------------------------------------------
   // A contrary candle is allowed to begin the pullback even when it first
   // extends the trend-side wick and has not yet touched the previous
   // directional candle's opposite wick.  The same pullback stays pending
   // across any number/colour of candles until either:
   //   1) that frozen opposite wick is touched, or
   //   2) a later candle prints a lower high (UP) / higher low (DOWN).
   // This directly covers the user's delayed red/green pullback sequences.
   if(g_t1_seed.pullback_pending)
   {
      const double prev_pending_high=g_t1_seed.pending_last_high;
      const double prev_pending_low =g_t1_seed.pending_last_low;
      const bool structure_turn=(g_t1_direction==DIR_UP ?
                                 bar.high<prev_pending_high :
                                 bar.low>prev_pending_low);
      const bool anchor_touch=(g_t1_direction==DIR_UP ?
                               bar.low<=g_t1_seed.pending_anchor_level :
                               bar.high>=g_t1_seed.pending_anchor_level);
      const double prior_pending_extreme=g_t1_seed.pending_extreme;
      const datetime prior_pending_extreme_time=g_t1_seed.pending_extreme_time;

      T1_UpdatePendingPullback(bar);

      if(structure_turn || anchor_touch)
      {
         const int ci=T1_CreateCandidateFromSeed(sym,tf,bar,
                        g_t1_seed.pending_start_level,
                        g_t1_seed.pending_start_level_time,
                        g_t1_seed.pending_extreme,
                        g_t1_seed.pending_extreme_time);
         if(ci>=0)
            T1_ProcessNewCandidateSameBar(sym,tf,bar,ci,anchor_touch,
                                       prior_pending_extreme,
                                       prior_pending_extreme_time);

         // Candidate creation never locks later/nested detection.  A
         // directional confirmation candle can seed a fresh move immediately.
         T1_ResetSeed();
         if(directional) T1_StartSeed(sym,tf,bar);
         return;
      }

      g_t1_seed.pending_last_high=bar.high;
      g_t1_seed.pending_last_low=bar.low;
      return;
   }

   // ---------------------------------------------------------------
   // Fresh pullback decision from the active initial move
   // ---------------------------------------------------------------
   if(g_t1_direction==DIR_UP)
   {
      const bool lower_high=(bar.high<g_t1_seed.last_high);
      const bool last_low_touch=(bar.low<=g_t1_seed.last_low);

      if(lower_high || last_low_touch)
      {
         // Normal lower-high pullback reclaims the LAST bullish candle High.
         // If a contrary (red) outside candle makes a Higher High AND sweeps
         // the prior bullish Low, that red candle's own wick High becomes the
         // Stage-2 reclaim level exactly as specified by the user.
         double start_level=g_t1_seed.last_high;
         datetime start_time=g_t1_seed.last_time;
         if(!directional && bar.high>g_t1_seed.last_high)
         {
            start_level=bar.high;
            start_time=bar.time;
         }

         const int ci=T1_CreateCandidateFromSeed(sym,tf,bar,
                        start_level,start_time,bar.low,bar.time);
         if(ci>=0)
            T1_ProcessNewCandidateSameBar(sym,tf,bar,ci,last_low_touch,0.0,0);
         T1_ResetSeed();
         if(directional) T1_StartSeed(sym,tf,bar);
         return;
      }

      if(!directional)
      {
         // Red candle made/held a Higher High but did not yet touch the last
         // bullish Low.  It starts a pending pullback; later red OR green bars
         // can confirm it without losing this starting structure.
         T1_BeginPendingPullback(bar);
         return;
      }

      // A bullish candle with a non-lower High and intact last Low continues
      // the initial move.  Equal/high extension is therefore not mistaken for
      // a pullback.
      g_t1_seed.bars++;
      g_t1_seed.last_time=bar.time;
      g_t1_seed.last_high=bar.high;
      g_t1_seed.last_low=bar.low;
      return;
   }

   // Bearish is the exact mirror of the bullish rules above.
   const bool higher_low=(bar.low>g_t1_seed.last_low);
   const bool last_high_touch=(bar.high>=g_t1_seed.last_high);

   if(higher_low || last_high_touch)
   {
      double start_level=g_t1_seed.last_low;
      datetime start_time=g_t1_seed.last_time;
      if(!directional && bar.low<g_t1_seed.last_low)
      {
         start_level=bar.low;
         start_time=bar.time;
      }

      const int ci=T1_CreateCandidateFromSeed(sym,tf,bar,
                     start_level,start_time,bar.high,bar.time);
      if(ci>=0)
         T1_ProcessNewCandidateSameBar(sym,tf,bar,ci,last_high_touch,0.0,0);
      T1_ResetSeed();
      if(directional) T1_StartSeed(sym,tf,bar);
      return;
   }

   if(!directional)
   {
      T1_BeginPendingPullback(bar);
      return;
   }

   g_t1_seed.bars++;
   g_t1_seed.last_time=bar.time;
   g_t1_seed.last_high=bar.high;
   g_t1_seed.last_low=bar.low;
}

inline bool T1_EventBefore(const T1TriggerEvent &a,const T1TriggerEvent &b)
{
   if(a.trigger_time!=b.trigger_time) return a.trigger_time<b.trigger_time;
   // Exact tick order wins whenever available.  A zero value means OHLC-only
   // timing; it must not be invented into a fake intrabar sequence.
   if(a.trigger_msc>0 && b.trigger_msc>0 && a.trigger_msc!=b.trigger_msc)
      return a.trigger_msc<b.trigger_msc;
   if(a.trigger_msc>0 && b.trigger_msc==0) return true;
   if(a.trigger_msc==0 && b.trigger_msc>0) return false;
   // Exact simultaneity / unknown intrabar order: keep deterministic newest
   // candidate preference without suppressing either completed trigger.
   return a.candidate_id>b.candidate_id;
}

inline void T1_SortTriggerEventsChronologically()
{
   // Stable-enough insertion sort: event counts are tiny and this avoids any
   // dependency on external sorting helpers.  Completed events are NEVER
   // deleted; only their observable order is corrected to market chronology.
   for(int i=1;i<g_t1_event_count;i++)
   {
      T1TriggerEvent key=g_t1_events[i];
      int j=i-1;
      while(j>=0 && T1_EventBefore(key,g_t1_events[j]))
      {
         g_t1_events[j+1]=g_t1_events[j];
         j--;
      }
      g_t1_events[j+1]=key;
   }
}

inline void T1_CompactCandidates()
{
   // Purge ONLY the candidate that itself reached a terminal state.  Completing
   // one trigger never clears, resets, or demotes any other valid candidate.
   int w=0;
   for(int r=0;r<g_t1_candidate_count;r++)
   {
      if(g_t1_candidates[r].invalidated ||
         g_t1_candidates[r].stage==T1_INVALID ||
         g_t1_candidates[r].stage==T1_TRIGGERED)
         continue;
      if(w!=r) g_t1_candidates[w]=g_t1_candidates[r];
      w++;
   }
   if(w!=g_t1_candidate_count)
   {
      ArrayResize(g_t1_candidates,w);
      g_t1_candidate_count=w;
   }
}

inline void T1_InvalidateActiveContextByBar(const MqlRates &bar)
{
   const int idx=T1_ActiveContextIndex();
   if(idx<0 || !g_t1_contexts[idx].open) return;

   // The Stage-3 touch itself creates a nested context, so it is never allowed
   // to invalidate that brand-new line retroactively on the same OHLC bar.
   if(g_t1_contexts[idx].created_time>=bar.time) return;

   const bool touched=(g_t1_contexts[idx].direction==DIR_UP ?
                       bar.low<=g_t1_contexts[idx].level :
                       bar.high>=g_t1_contexts[idx].level);
   if(!touched) return;

   const int closing_id=g_t1_contexts[idx].id;
   T1_CloseContextByID(closing_id,"validation level touched");
   if(g_t1_seed.active && g_t1_seed.validation_context_id==closing_id)
      T1_ResetSeed();
}

inline void T1_ProcessBar(const string sym,const ENUM_TIMEFRAMES tf,
                          const MqlRates &rates[],const int n,const int i)
{
   if(!g_t1_ready || tf!=PERIOD_M1 || i<0 || i>=n) return;
   const MqlRates bar=rates[i];
   // Trigger Type 1 starts on the SAME M1 candle that carries TRIGGER_READY.
   // The coordinator arms T1 earlier in this bar's chronological callback, so
   // equality is intentionally accepted here.
   if(bar.time<g_t1_ready_time || bar.time<=g_t1_last_bar_time) return;
   g_t1_last_bar_time=bar.time;

   int ticks=0;
   if(g_t1_candidate_count>0)
      ticks=T1_LoadTicks(sym,tf,bar.time);

   if(ticks>0)
   {
      // MARKET CHRONOLOGY, not candidate age, owns completion priority.
      // Advance every active candidate one real tick at a time.  Therefore a
      // large/older candidate that actually completes at tick N is emitted
      // before a small/newer candidate completing at tick N+K, and vice versa.
      for(int k=0;k<ticks;k++)
      {
         // Newest is still the visual/selection Primary while unfinished, but
         // processing order inside the SAME tick cannot suppress older peers.
         for(int c=g_t1_candidate_count-1;c>=0;c--)
            T1_ProcessCandidateTickAt(g_t1_candidates[c],sym,tf,bar,k);
      }
   }
   else
   {
      // With no tick sequence, preserve every candidate and fail closed on
      // ambiguous same-candle transitions; never infer a false priority.
      for(int c=g_t1_candidate_count-1;c>=0;c--)
         T1_ProcessCandidateOHLCFallback(g_t1_candidates[c],sym,tf,bar,false);
   }
   T1_CompactCandidates();

   // The shared red context itself expires when its validation wick is
   // touched.  This is separate from any one Candidate: existing candidates
   // already processed their own validation above, while NEW structures must
   // now fall back to the previous still-open context (or bootstrap a root).
   T1_InvalidateActiveContextByBar(bar);

   // Pullback/new-candidate detection always continues even while other
   // candidates wait in later stages, enabling nested structures.  A newly
   // created same-bar candidate may replay ticks after its Stage-1 activation;
   // sorting below then restores event order versus candidates that were
   // already active at bar open.
   T1_AdvanceSeedAndDetect(sym,tf,bar);
   T1_CompactCandidates();
   T1_SortTriggerEventsChronologically();
}

#endif // WAVEBOT_TRIGGER_TYPE1_MQH
