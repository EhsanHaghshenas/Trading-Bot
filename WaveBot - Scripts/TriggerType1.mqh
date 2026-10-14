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
   double validation_level;
   double last_high;
   double last_low;
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
   g_t1_seed.last_high=0.0;
   g_t1_seed.last_low=0.0;
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
   // original validation wick remains intact.  For a one-candle initial move
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

inline void T1_MarkInvalid(T1Candidate &c,const string reason,
                           const datetime event_time)
{
   c.invalidated=true;
   c.stage=T1_INVALID;
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
         inside=(new_validation>c.validation_level &&
                 new_start<=open_boundary);
      else
         inside=(new_validation<c.validation_level &&
                 new_start>=open_boundary);
      if(inside && c.id>id) id=c.id;
   }
   return id;
}

inline int T1_CreateCandidateFromSeed(const string sym,const ENUM_TIMEFRAMES tf,
                                      const MqlRates &bar)
{
   const int n=g_t1_candidate_count+1;
   ArrayResize(g_t1_candidates,n);
   const int idx=n-1;
   T1Candidate c;
   c.id=g_t1_next_candidate_id++;
   const double new_start=(g_t1_direction==DIR_UP ?
                           g_t1_seed.last_high : g_t1_seed.last_low);
   c.parent_id=T1_FindNewestContainingParent(g_t1_seed.validation_level,new_start);
   c.generation=g_t1_generation;
   c.direction=g_t1_direction;
   c.creation_time=bar.time;
   c.stage1_time=bar.time;
   c.stage2_time=0;
   c.stage3_time=0;
   c.triggered_time=0;
   c.triggered_msc=0;
   c.stage=T1_WAIT_PULLBACK_END;
   c.validation_level=g_t1_seed.validation_level;
   c.pullback_start_level=new_start;
   c.pullback_extreme=(g_t1_direction==DIR_UP ? bar.low : bar.high);
   c.final_trigger_level=0.0;
   c.running_final_extreme=0.0;
   c.validation_time=g_t1_seed.first_time;
   c.pullback_start_time=g_t1_seed.last_time;
   c.pullback_extreme_time=bar.time;
   c.final_trigger_time=0;
   c.running_final_extreme_time=0;
   c.initial_move_bars=g_t1_seed.bars;
   c.invalidated=false;
   g_t1_candidates[idx]=c;
   g_t1_candidate_count=n;
   T1_DrawMarker(g_t1_candidates[idx],bar,"T1-S1","S1",0,clrSilver);
   // Stage 2 target: the wick High/Low of the LAST directional candle before
   // the pullback.  The short dashed line starts on that exact source candle.
   T1_DrawLevel(g_t1_candidates[idx],sym,tf,"PB_START",
                (g_t1_direction==DIR_UP ? "PullbackStartHigh" : "PullbackStartLow"),
                g_t1_candidates[idx].pullback_start_time,
                g_t1_candidates[idx].pullback_start_level,clrDeepSkyBlue);
   if(InpDebugPrints)
      Print("[T1] Stage1 candidate=",g_t1_candidates[idx].id,
            " parent=",g_t1_candidates[idx].parent_id,
            " initialBars=",g_t1_candidates[idx].initial_move_bars,
            " direction=",T1_DirectionText(g_t1_direction),
            " time=",TimeToString(bar.time,TIME_DATE|TIME_MINUTES));
   return idx;
}

inline void T1_StartSeed(const MqlRates &bar)
{
   g_t1_seed.active=true;
   g_t1_seed.direction=g_t1_direction;
   g_t1_seed.bars=1;
   g_t1_seed.first_time=bar.time;
   g_t1_seed.last_time=bar.time;
   g_t1_seed.validation_level=(g_t1_direction==DIR_UP ? bar.low : bar.high);
   g_t1_seed.last_high=bar.high;
   g_t1_seed.last_low=bar.low;
}

inline bool T1_IsDirectionalCandle(const MqlRates &bar)
{
   return (g_t1_direction==DIR_UP ? bar.close>bar.open : bar.close<bar.open);
}

inline void T1_AdvanceSeedAndDetect(const string sym,const ENUM_TIMEFRAMES tf,
                                    const MqlRates &bar)
{
   const bool directional=T1_IsDirectionalCandle(bar);
   if(!g_t1_seed.active)
   {
      if(directional) T1_StartSeed(bar);
      return;
   }

   // The main validation level belongs to the FIRST candle of the directional
   // move.  A later bar touching it kills this seed before a candidate exists.
   const bool seed_invalid=(g_t1_direction==DIR_UP ?
                            bar.low<=g_t1_seed.validation_level :
                            bar.high>=g_t1_seed.validation_level);
   if(seed_invalid)
   {
      T1_ResetSeed();
      if(directional) T1_StartSeed(bar);
      return;
   }

   bool continuation=false;
   bool valid_pullback=false;
   if(g_t1_direction==DIR_UP)
   {
      if(g_t1_seed.bars==1)
         valid_pullback=(bar.high<g_t1_seed.last_high &&
                         bar.low>g_t1_seed.validation_level);
      else
         valid_pullback=(bar.high<=g_t1_seed.last_high &&
                         bar.low>g_t1_seed.validation_level);
      // Consecutive bullish candles remain the initial move unless the
      // current candle already satisfies the explicit pullback range.  This
      // preserves an equal-high second bullish candle as part of the move.
      continuation=(directional && !valid_pullback);
   }
   else
   {
      if(g_t1_seed.bars==1)
         valid_pullback=(bar.low>g_t1_seed.last_low &&
                         bar.high<g_t1_seed.validation_level);
      else
         valid_pullback=(bar.low>=g_t1_seed.last_low &&
                         bar.high<g_t1_seed.validation_level);
      continuation=(directional && !valid_pullback);
   }

   if(continuation)
   {
      g_t1_seed.bars++;
      g_t1_seed.last_time=bar.time;
      g_t1_seed.last_high=bar.high;
      g_t1_seed.last_low=bar.low;
      return;
   }

   if(valid_pullback)
   {
      const int ci=T1_CreateCandidateFromSeed(sym,tf,bar);
      const int ticks=T1_LoadTicks(sym,tf,bar.time);
      if(ticks>0)
      {
         const int activation=T1_Stage1ActivationTickIndex(g_t1_seed,g_t1_direction);
         if(activation>=0)
         {
            // PullbackLow/High begins at the actual low-side/high-side Stage-1
            // event, not at a later global candle extreme.  The tick replay
            // then freezes the pullback extreme exactly when Stage 2 occurs.
            g_t1_candidates[ci].pullback_extreme=T1_TickPrice(g_t1_ticks[activation]);
            g_t1_candidates[ci].pullback_extreme_time=bar.time;
            T1_ProcessCandidateTicks(g_t1_candidates[ci],sym,tf,bar,activation+1);
         }
         // If the full candle satisfies the pullback range but never touched
         // the prior candle-side wick, Stage 1 is valid at candle level; no
         // same-candle Stage 2 is inferred because its order is unprovable.
      }
      else
         T1_ProcessCandidateOHLCFallback(g_t1_candidates[ci],sym,tf,bar,true);

      // Candidate creation must never lock detection of newer/nested moves.
      // A directional Stage-1 candle may simultaneously become the first
      // candle of a new directional move for a later nested candidate.
      T1_ResetSeed();
      if(directional) T1_StartSeed(bar);
      return;
   }

   // The prior consecutive directional move can no longer seed a valid
   // pullback.  A directional current candle starts a fresh move immediately.
   T1_ResetSeed();
   if(directional) T1_StartSeed(bar);
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
