#ifndef WAVEBOT_CONCEPTS_MQH
#define WAVEBOT_CONCEPTS_MQH

#include <WaveBot/Utils.mqh>
#include <WaveBot/Data.mqh>
#include <WaveBot/Markers.mqh>
#include <WaveBot/MajicalFVG.mqh>
#include <WaveBot/Flip.mqh>
#include <WaveBot/MajicFlip.mqh>

// ============================================================================
// Independent concept scanner
// MFVG, Flip and Majic Flip are scanned in BOTH directions from the full chart
// window, before the normal W2/W3 mode scan starts. Therefore the result does
// not depend on the active UP/DOWN trend/mode chosen by Bootstrap or input.
// ============================================================================

static bool            g_wbc_last_valid = false;
static string          g_wbc_last_symbol = "";
static ENUM_TIMEFRAMES g_wbc_last_tf = PERIOD_CURRENT;
static datetime        g_wbc_last_from = 0;
static datetime        g_wbc_last_to = 0;

inline bool __WBC_SameRequest(const string sym,
                              const ENUM_TIMEFRAMES tf,
                              const datetime from_time,
                              const datetime to_time)
{
   if(!g_wbc_last_valid) return false;
   if(g_wbc_last_symbol != sym) return false;
   if(g_wbc_last_tf != tf) return false;
   if(g_wbc_last_from != from_time) return false;
   if(g_wbc_last_to != to_time) return false;
   return true;
}

inline void __WBC_SaveRequest(const string sym,
                              const ENUM_TIMEFRAMES tf,
                              const datetime from_time,
                              const datetime to_time)
{
   g_wbc_last_valid = true;
   g_wbc_last_symbol = sym;
   g_wbc_last_tf = tf;
   g_wbc_last_from = from_time;
   g_wbc_last_to = to_time;
}

inline bool __WBC_IsConceptObjectName(const string on)
{
   if(on == "") return false;

   if(StringFind(on, "MFVG_U_") >= 0) return true;
   if(StringFind(on, "MFVG_D_") >= 0) return true;
   if(StringFind(on, "FLIP_U_") >= 0) return true;
   if(StringFind(on, "FLIP_D_") >= 0) return true;
   if(StringFind(on, "MAJIC_FLIP_U_") >= 0) return true;
   if(StringFind(on, "MAJIC_FLIP_D_") >= 0) return true;

   return false;
}

inline void WaveBotConcepts_DeleteAllVisuals_AllScans()
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; --i)
   {
      string on = ObjectName(0, i);
      if(__WBC_IsConceptObjectName(on))
         ObjectDelete(0, on);
   }
}

inline datetime __WBC_AdjustedFromTime(const datetime from_time,
                                       const ENUM_TIMEFRAMES tf)
{
   int tfsec = PeriodSeconds(tf);
   if(tfsec <= 0) return from_time;

   datetime back = (datetime)(tfsec * 10);
   if(from_time > back)
      return (from_time - back);

   return 0;
}

inline void WaveBotConcepts_RunAllDirections(const string sym,
                                             const ENUM_TIMEFRAMES tf,
                                             const datetime from_time,
                                             const datetime to_time)
{
   datetime start = from_time;
   datetime stop  = to_time;

   if(stop <= 0)
      stop = TimeCurrent();

   if(start > stop)
   {
      datetime tmp = start;
      start = stop;
      stop = tmp;
   }

   if(__WBC_SameRequest(sym, tf, start, stop))
      return;

   string old_ns = Markers_GetNamespace();
   Markers_SetNamespace("MAJ");

   MqlRates rates[];
   datetime from_adj = __WBC_AdjustedFromTime(start, tf);
   int n = LoadRatesRange(sym, tf, from_adj, stop, rates);
   if(n <= 0)
   {
      if(InpDebugPrints)
         Print("[WBC] LoadRatesRange failed | symbol=", sym,
               " | tf=", EnumToString(tf),
               " | from=", TimeToString(from_adj, TIME_DATE|TIME_SECONDS),
               " | to=", TimeToString(stop, TIME_DATE|TIME_SECONDS));
      Markers_SetNamespace(old_ns);
      return;
   }

   WaveBotConcepts_DeleteAllVisuals_AllScans();

   MajicalFVG_ResetGlobals();
   Flip_ResetGlobals();
   MajicFlip_ResetGlobals();

   MajicalFVG_RunScan_UP(sym, tf, rates, n, start, stop);
   MajicalFVG_RunScan_DOWN(sym, tf, rates, n, start, stop);

   Flip_RunScan_UP(sym, tf, rates, n, start, stop);
   Flip_RunScan_DOWN(sym, tf, rates, n, start, stop);

   MajicFlip_RunScan_UP(sym, tf, rates, n, start, stop);
   MajicFlip_RunScan_DOWN(sym, tf, rates, n, start, stop);

   __WBC_SaveRequest(sym, tf, start, stop);

   if(InpDebugPrints)
   {
      Print("[WBC] Independent concept scan completed | symbol=", sym,
            " | tf=", EnumToString(tf),
            " | MFVG_UP=", MajicalFVG_UP_ConfirmedCount(),
            " | MFVG_DN=", MajicalFVG_DOWN_ConfirmedCount(),
            " | FLIP_UP=", Flip_UP_Count(),
            " | FLIP_DN=", Flip_DOWN_Count(),
            " | MFLIP_UP=", MajicFlip_UP_Count(),
            " | MFLIP_DN=", MajicFlip_DOWN_Count());
   }

   Markers_SetNamespace(old_ns);
}

inline void WaveBotConcepts_ResetGlobals()
{
   g_wbc_last_valid = false;
   g_wbc_last_symbol = "";
   g_wbc_last_tf = PERIOD_CURRENT;
   g_wbc_last_from = 0;
   g_wbc_last_to = 0;

   MajicalFVG_ResetGlobals();
   Flip_ResetGlobals();
   MajicFlip_ResetGlobals();
}

#endif // WAVEBOT_CONCEPTS_MQH
