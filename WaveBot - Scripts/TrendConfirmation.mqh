// WaveBot/TrendConfirmation.mqh
#ifndef WAVEBOT_TREND_CONFIRMATION_MQH
#define WAVEBOT_TREND_CONFIRMATION_MQH

#include <WaveBot/Types.mqh>
#include <WaveBot/Markers.mqh>

// Analysis-only confirmation: one TC for the first standard Strong Range
// in the direction of each actual MTC. No signal/trade side effects.
static bool      g_tc_waiting_for_sr = false;
static bool      g_tc_waiting_for_next_bar = false;
static bool      g_tc_confirmed = false;
static Direction g_tc_mtc_direction = DIR_UP;
static datetime  g_tc_mtc_time = 0;
static datetime  g_tc_first_sr_time = 0;
static datetime  g_tc_confirmation_time = 0;

inline void TC_ResetGlobals()
{
   g_tc_waiting_for_sr = false;
   g_tc_waiting_for_next_bar = false;
   g_tc_confirmed = false;
   g_tc_mtc_direction = DIR_UP;
   g_tc_mtc_time = 0;
   g_tc_first_sr_time = 0;
   g_tc_confirmation_time = 0;
}

// Do not erase a pending/confirmed TC on duplicate replays of the same MTC.
// Reject older MTC events encountered in rewound/nested analysis scans.
inline void TC_OnMTC(const Direction dir, const datetime mtc_time)
{
   if(mtc_time <= 0 || mtc_time < g_tc_mtc_time) return;
   if(mtc_time == g_tc_mtc_time && dir == g_tc_mtc_direction) return;

   g_tc_mtc_direction = dir;
   g_tc_mtc_time = mtc_time;
   g_tc_first_sr_time = 0;
   g_tc_confirmation_time = 0;
   g_tc_waiting_for_sr = true;
   g_tc_waiting_for_next_bar = false;
   g_tc_confirmed = false;
}

// The label is anchored to the NEXT REAL bar, not to a calculated time:
// weekends and missing candles must not shift TC to a non-existent candle.
inline void __TC_DrawOnCandle(const MqlRates &bar)
{
   if(g_tc_confirmed || g_tc_mtc_time <= 0) return;
   if(bar.time <= g_tc_first_sr_time) return;

   g_tc_confirmation_time = bar.time;
   g_tc_waiting_for_next_bar = false;
   g_tc_confirmed = true;

   const double candle_range = bar.high - bar.low;
   const double margin = MathMax(3.0 * _Point, candle_range * 0.20);
   const bool up = (g_tc_mtc_direction == DIR_UP);
   const double label_price = (up ? bar.low - margin : bar.high + margin);
   const color label_color = (up ? clrLimeGreen : clrOrangeRed);
   const string id = "TC_" + IntegerToString((long)g_tc_mtc_time)
                     + (up ? "_UP" : "_DN");
   MarkCandleText(id, bar.time, label_price, "TC", label_color);
}

// Called ONLY from the existing StrongRange.mqh creation branches.
// Do not alter Strong Range detection conditions or SR mitigator logic.
inline void TC_OnNewStrongRange(const Direction dir,
                                const MqlRates &rates[],
                                const int n,
                                const int sr_bar_index)
{
   if(!g_tc_waiting_for_sr) return;
   if(dir != g_tc_mtc_direction) return;
   if(sr_bar_index < 0 || sr_bar_index >= n) return;

   const datetime sr_time = rates[sr_bar_index].time;
   if(sr_time <= g_tc_mtc_time) return;

   // Lock to FIRST qualifying SR for this MTC before any other SR is processed.
   g_tc_waiting_for_sr = false;
   g_tc_first_sr_time = sr_time;
   g_tc_waiting_for_next_bar = true;

   // Historical scan already has the actual following candle: draw at once.
   // If SR is the final loaded candle, leave it pending until later data exists.
   if(sr_bar_index + 1 < n)
      __TC_DrawOnCandle(rates[sr_bar_index + 1]);
}

// Fallback for scan buffers in which the next candle was not loaded when SR
// was first detected. Call for bars in BOTH directions' existing scan loops.
inline void TC_OnProcessedBar(const MqlRates &rates[], const int n, const int i)
{
   if(!g_tc_waiting_for_next_bar || g_tc_confirmed) return;
   if(i <= 0 || i >= n) return;
   if(rates[i-1].time != g_tc_first_sr_time) return;
   if(rates[i].time <= g_tc_first_sr_time) return;
   __TC_DrawOnCandle(rates[i]);
}

// Upgrade/re-run hygiene: delete ONLY annotations created by this module;
// leave MTC, SW, Strong Range and all other analysis objects untouched.
inline void TC_DeletePreviousMarkers()
{
   for(int i = ObjectsTotal(0)-1; i >= 0; --i)
   {
      const string name = ObjectName(0, i);
      if(StringLen(name) < 6 || StringSubstr(name,0,1) != "S") continue;
      if(StringFind(name,"_TC_") < 0) continue;
      // Our own marker IDs always end with _UP or _DN.
      const int len = StringLen(name);
      if(StringSubstr(name,len-3) == "_UP" || StringSubstr(name,len-3) == "_DN")
         ObjectDelete(0,name);
   }
}

inline bool TC_IsConfirmed() { return g_tc_confirmed; }
inline datetime TC_ConfirmationTime() { return g_tc_confirmation_time; }

#endif // WAVEBOT_TREND_CONFIRMATION_MQH
