#ifndef WAVEBOT_TRIGGER_M15_SIGNAL_GATE_MQH
#define WAVEBOT_TRIGGER_M15_SIGNAL_GATE_MQH

#include <WaveBot/Types.mqh>

#define TRGM15G_KIND_START_HWX         1
#define TRGM15G_KIND_START_HWBB        2
#define TRGM15G_KIND_START_FSMS        3
#define TRGM15G_KIND_START_GOOZ        4

#define TRGM15G_KIND_STOP_MTC          10
#define TRGM15G_KIND_STOP_MINORSTARTER 11
#define TRGM15G_KIND_STOP_MINOROFF     12

struct TriggerM15SignalGateEvent
{
   string    symbol;
   datetime  t;
   datetime  bar_time;
   Direction dir;
   int       kind;
   int       ns;
   int       seq;
};

static TriggerM15SignalGateEvent g_trgm15_events[];
static int                       g_trgm15_seq = 0;

inline void TriggerM15SignalGate_ResetGlobals()
{
   ArrayResize(g_trgm15_events, 0);
   g_trgm15_seq = 0;
}

inline bool __TRGM15_ShouldRecord(const string sym)
{
   if(sym == "")
      return false;

   if((ENUM_TIMEFRAMES)Period() != PERIOD_M15)
      return false;

   return true;
}

inline bool __TRGM15_IsStartKind(const int kind)
{
   return (kind == TRGM15G_KIND_START_HWX ||
           kind == TRGM15G_KIND_START_HWBB ||
           kind == TRGM15G_KIND_START_FSMS ||
           kind == TRGM15G_KIND_START_GOOZ);
}

inline bool __TRGM15_IsStopKind(const int kind)
{
   return (kind == TRGM15G_KIND_STOP_MTC ||
           kind == TRGM15G_KIND_STOP_MINORSTARTER ||
           kind == TRGM15G_KIND_STOP_MINOROFF);
}

inline string TriggerM15SignalGate_KindName(const int kind)
{
   if(kind == TRGM15G_KIND_START_HWX)         return "HWX";
   if(kind == TRGM15G_KIND_START_HWBB)        return "HWBB";
   if(kind == TRGM15G_KIND_START_FSMS)        return "FSMS";
   if(kind == TRGM15G_KIND_START_GOOZ)        return "GOOZBAGHALI";
   if(kind == TRGM15G_KIND_STOP_MTC)          return "MTC";
   if(kind == TRGM15G_KIND_STOP_MINORSTARTER) return "MINORSTARTER";
   if(kind == TRGM15G_KIND_STOP_MINOROFF)     return "MINOROFF_ZONE";
   return "UNKNOWN";
}

inline int TriggerM15SignalGate_EventCount()
{
   return ArraySize(g_trgm15_events);
}

inline bool TriggerM15SignalGate_EventGet(const int index,
                                          TriggerM15SignalGateEvent &out)
{
   if(index < 0)
      return false;

   int total = ArraySize(g_trgm15_events);
   if(index >= total)
      return false;

   out = g_trgm15_events[index];
   return true;
}

inline datetime __TRGM15_M15CloseActivationTime(const datetime bar_open_time)
{
   if(bar_open_time <= 0)
      return 0;

   int sec = PeriodSeconds(PERIOD_M15);
   if(sec <= 0)
      sec = 900;

   return (bar_open_time + (datetime)sec);
}

inline bool __TRGM15_EventExists(const string    sym,
                                 const int       kind,
                                 const int       ns,
                                 const Direction dir,
                                 const datetime  t,
                                 const datetime  bar_time)
{
   int total = ArraySize(g_trgm15_events);
   for(int i = 0; i < total; ++i)
   {
      if(g_trgm15_events[i].symbol != sym)
         continue;
      if(g_trgm15_events[i].kind != kind)
         continue;
      if(g_trgm15_events[i].ns != ns)
         continue;
      if(g_trgm15_events[i].dir != dir)
         continue;
      if(g_trgm15_events[i].t != t)
         continue;
      if(g_trgm15_events[i].bar_time != bar_time)
         continue;
      return true;
   }

   return false;
}

inline void __TRGM15_Record(const string    sym,
                            const int       kind,
                            const int       ns,
                            const Direction dir,
                            const datetime  t,
                            const datetime  bar_time)
{
   if(!__TRGM15_ShouldRecord(sym))
      return;

   if(t <= 0 || bar_time <= 0)
      return;

   if(!__TRGM15_IsStartKind(kind) && !__TRGM15_IsStopKind(kind))
      return;

   if(ns <= 0)
      return;

   if(__TRGM15_EventExists(sym, kind, ns, dir, t, bar_time))
      return;

   int pos = ArraySize(g_trgm15_events);
   ArrayResize(g_trgm15_events, pos + 1);

   g_trgm15_seq++;

   g_trgm15_events[pos].symbol   = sym;
   g_trgm15_events[pos].t        = t;
   g_trgm15_events[pos].bar_time = bar_time;
   g_trgm15_events[pos].dir      = dir;
   g_trgm15_events[pos].kind     = kind;
   g_trgm15_events[pos].ns       = ns;
   g_trgm15_events[pos].seq      = g_trgm15_seq;
}

inline void TriggerM15SignalGate_RecordExact(const string    sym,
                                             const int       kind,
                                             const int       ns,
                                             const Direction dir,
                                             const datetime  bar_time)
{
   __TRGM15_Record(sym, kind, ns, dir, bar_time, bar_time);
}

inline void TriggerM15SignalGate_RecordClose(const string    sym,
                                             const int       kind,
                                             const int       ns,
                                             const Direction dir,
                                             const datetime  signal_bar_open_time)
{
   datetime activation_time = __TRGM15_M15CloseActivationTime(signal_bar_open_time);
   if(activation_time <= 0)
      return;

   __TRGM15_Record(sym, kind, ns, dir, signal_bar_open_time, activation_time);
}

#endif // WAVEBOT_TRIGGER_M15_SIGNAL_GATE_MQH
