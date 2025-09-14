#ifndef WAVEBOT_SWITCH_MQH
#define WAVEBOT_SWITCH_MQH

#include <WaveBot/Types.mqh>
#include <WaveBot/Markers.mqh>
#include <WaveBot/Bootstrap.mqh>
#include <WaveBot/Utils.mqh>

// وضعیت ترنزیشن
enum TransitionState { TRANSITION_NONE=0, TRANSITION_FROM_UP=1, TRANSITION_FROM_DOWN=2 };

static TransitionState g_trans_state = TRANSITION_NONE;
static datetime        g_trans_start = 0;

// درخواست ورود به ترنزیشن
inline void Switch_RequestEnter_FromUP(const datetime at_time)
{
   if(g_trans_state==TRANSITION_NONE){ g_trans_state=TRANSITION_FROM_UP; g_trans_start=at_time; }
}
inline void Switch_RequestEnter_FromDOWN(const datetime at_time)
{
   if(g_trans_state==TRANSITION_NONE){ g_trans_state=TRANSITION_FROM_DOWN; g_trans_start=at_time; }
}

inline bool      Switch_IsActive()     { return (g_trans_state!=TRANSITION_NONE); }
inline bool      Switch_FromUP()       { return (g_trans_state==TRANSITION_FROM_UP); }
inline bool      Switch_FromDOWN()     { return (g_trans_state==TRANSITION_FROM_DOWN); }
inline datetime  Switch_StartTime()    { return  g_trans_start; }
inline void      Switch_Clear()        { g_trans_state=TRANSITION_NONE; g_trans_start=0; }

// --- کمکی: خواندن Close در یک زمان مشخص (برای سنجش SW)
inline bool GetCloseAtTime(const string sym, const ENUM_TIMEFRAMES tf, const datetime t, double &out_close)
{
   MqlRates r[]; int n = LoadRatesRange(sym, tf, t-PeriodSeconds(tf)*2, t+PeriodSeconds(tf)*2, r);
   if(n<=0) return false;
   for(int i=0;i<n;++i) if(r[i].time==t){ out_close=r[i].close; return true; }
   return false;
}

#endif // WAVEBOT_SWITCH_MQH
