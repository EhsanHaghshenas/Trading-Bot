// WaveBot/SWGate.mqh
#ifndef WAVEBOT_SWGATE_MQH
#define WAVEBOT_SWGATE_MQH

// یک «دروازهٔ چرخه» برای الزام اینکه SW فقط در همان چرخه‌ای مجاز باشد
// که بعد از قفل‌شدن W2 و بعد از Hunter شکل گرفته است.

// -------- UP --------
static bool     g_sw_up_cycle_open = false;
static datetime g_sw_up_w2lock_time = 0;

inline void SWGate_UP_OnW2Locked(const MqlRates &rates[], const int c1_idx)
{
   g_sw_up_cycle_open = true;
   g_sw_up_w2lock_time = (c1_idx>=0 ? rates[c1_idx].time : 0);
}
inline void SWGate_UP_OnPairFinalized()
{
   g_sw_up_cycle_open = false;
   g_sw_up_w2lock_time = 0;
}
inline bool     SWGate_UP_IsOpen()   { return g_sw_up_cycle_open; }
inline datetime SWGate_UP_W2Time()   { return g_sw_up_w2lock_time; }

// -------- DOWN ------
static bool     g_sw_dn_cycle_open = false;
static datetime g_sw_dn_w2lock_time = 0;

inline void SWGate_DN_OnW2Locked(const MqlRates &rates[], const int c1_idx)
{
   g_sw_dn_cycle_open = true;
   g_sw_dn_w2lock_time = (c1_idx>=0 ? rates[c1_idx].time : 0);
}
inline void SWGate_DN_OnPairFinalized()
{
   g_sw_dn_cycle_open = false;
   g_sw_dn_w2lock_time = 0;
}
inline bool     SWGate_DN_IsOpen()   { return g_sw_dn_cycle_open; }
inline datetime SWGate_DN_W2Time()   { return g_sw_dn_w2lock_time; }

#endif // WAVEBOT_SWGATE_MQH
