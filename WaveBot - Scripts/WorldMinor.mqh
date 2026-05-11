
#ifndef WAVEBOT_WORLDMINOR_MQH
#define WAVEBOT_WORLDMINOR_MQH

#include <WaveBot/Types.mqh>
#include <WaveBot/FSMS_SW.mqh>

// ============================================================================
// WorldMinor: runtime controller for MIN world
// - Holds current active minor session
// - Checks MinorOff (only for stopping MIN)
// - Provides an Off-event pulse to detect the exact stop moment
// ============================================================================

static bool                 g_wminor_active            = false;
static FSMS_SW_MinorSession g_wminor_sess;

static bool                 g_wminor_off_detected      = false;
static bool                 g_wminor_off_evt_pending   = false;
static int                  g_wminor_off_idx           = -1;
static datetime             g_wminor_off_time          = 0;

static int                  g_wminor_scan_seq          = 0;
static int                  g_wminor_scan_id           = 0;

// ------------------------------ basic state ------------------------------
inline bool WorldMinor_IsActive()            { return g_wminor_active; }
inline bool WorldMinor_OffDetected()         { return g_wminor_off_detected; }
inline int  WorldMinor_OffIndex()            { return g_wminor_off_idx; }
inline datetime WorldMinor_OffTime()         { return g_wminor_off_time; }
inline int  WorldMinor_ScanId()              { return g_wminor_scan_id; }

inline datetime WorldMinor_StarterTime()     { return g_wminor_sess.starter_time; }
inline int      WorldMinor_StarterIndex()    { return g_wminor_sess.starter_idx; }
inline Direction WorldMinor_Direction()      { return g_wminor_sess.dir; }
inline string   WorldMinor_Tag()             { return g_wminor_sess.tag; }

inline void WorldMinor_GetSession(FSMS_SW_MinorSession &out)
{
   out = g_wminor_sess;
}

inline void WorldMinor_Reset()
{
   g_wminor_active          = false;
   g_wminor_off_detected    = false;
   g_wminor_off_evt_pending = false;
   g_wminor_off_idx         = -1;
   g_wminor_off_time        = 0;

   g_wminor_scan_id         = 0;
}

// Stable object prefix for this MIN session
inline string WorldMinor_ObjectPrefix()
{
   return "S" + IntegerToString(g_wminor_scan_id) + "_MIN_";
}

inline void WorldMinor_Start(const FSMS_SW_MinorSession &s)
{
   g_wminor_active          = true;
   g_wminor_sess            = s;

   g_wminor_off_detected    = false;
   g_wminor_off_evt_pending = false;
   g_wminor_off_idx         = -1;
   g_wminor_off_time        = 0;

   // fixed scan id for this session
   g_wminor_scan_id = (1000000 + (++g_wminor_scan_seq));
}

inline void WorldMinor_Deactivate()
{
   g_wminor_active = false;
}

// Pop Off event (one-shot)
inline bool WorldMinor_PopOffEvent(datetime &off_time, int &off_idx)
{
   if(!g_wminor_off_evt_pending) return false;
   off_time = g_wminor_off_time;
   off_idx  = g_wminor_off_idx;
   g_wminor_off_evt_pending = false;
   return true;
}

// ------------------------------ Off rule ------------------------------
inline bool __WorldMinor_Crossed(const double level, const double low, const double high)
{
   if(level <= 0.0) return false;
   if(low <= level && high >= level) return true;
   return false;
}

// Check MinorOff on THIS candle.
// If Off is hit => marks Off event + deactivates MIN immediately.
inline bool WorldMinor_CheckMinorOff(const MqlRates &bar, const int bar_idx)
{
   if(!g_wminor_active) return false;
   if(g_wminor_off_detected) return true;

   // Off is only valid after starter candle
   if(bar.time <= g_wminor_sess.starter_time) return false;

   bool crossed = false;

   if(__WorldMinor_Crossed(g_wminor_sess.off_level_1, bar.low, bar.high))
      crossed = true;
   else if(__WorldMinor_Crossed(g_wminor_sess.off_level_2, bar.low, bar.high))
      crossed = true;

   if(crossed)
   {
      g_wminor_off_detected    = true;
      g_wminor_off_evt_pending = true;
      g_wminor_off_time        = bar.time;
      g_wminor_off_idx         = bar_idx;

      // Turn OFF MIN world immediately
      g_wminor_active          = false;
      return true;
   }

   return false;
}

#endif // WAVEBOT_WORLDMINOR_MQH

