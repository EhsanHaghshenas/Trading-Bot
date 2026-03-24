#property strict
#property description "WaveBot – W2/W3 + Hunter + ExtLQ + SW (Bootstrap Direction Race)"

#include <Trade/Trade.mqh>
#include <WaveBot/Types.mqh>      // Direction ?? ??? ?? ??????? ??? ???????
CTrade trade;

// ===== Inputs =====
input string            InpSymbol              = "EURUSD";
input ENUM_TIMEFRAMES   InpTF                  = PERIOD_H4;
input int               InpLookbackBars        = 20000;
input int               InpMaxBarsInWave       = 1000;
input bool              InpDrawMarkers         = true;
input bool              InpDebugPrints         = true;

// ????? ??? (??? ?? ???? ??? ??? ???? ????? ??????? ??????)
input Direction         InpDirection           = DIR_DOWN;

// scan window
input bool              InpMostRecentOnly      = false;
input bool              InpUseMonthsAgo        = false;
input int               InpMonthsAgo           = 40;
input datetime          InpScanFromDate        = D'2025.04.00 00:00';

// --- ???? ????????? ????? ????? (???? ?????) ---
input bool              InpRequireCloseBreakAboveW2H1 = true;
input bool              InpDrawExtLQ  = false;
input color             InpExtLQColor = clrMagenta;
input bool              InpEnableHunterMarkers = true;

input bool InpRunShadowBreakerOnce = false;  // ??? true ????? ?????? SB_RunOneShot ???? ??????

// ===== Includes (??? ?? Inputs) =====
#include <WaveBot/Utils.mqh>
#include <WaveBot/Data.mqh>
#include <WaveBot/Markers.mqh>
// NEW: Simple H4->M15 bridge (signals + candle counting)
#include <WaveBot/WB15_SignalBridge.mqh>
#include <WaveBot/Wave2.mqh>
#include <WaveBot/Wave3.mqh>
#include <WaveBot/Wave2_Down.mqh>
#include <WaveBot/Wave3_Down.mqh>
#include <WaveBot/API.mqh>        // UP
#include <WaveBot/API_Down.mqh>   // DOWN
#include <WaveBot/Bootstrap.mqh>  // Bootstrap race
#include <WaveBot/SWGate.mqh>
#include <WaveBot/ShadowBreaker.mqh>
#include <WaveBot/FSMS_SW.mqh>   // ???? FSMS_SW_Session_* ? FSMS_SW_MinorSession
#include <WaveBot/W3ChainGuard.mqh>   // ???? W3CG_ResetGlobals()

// ===== Lifecycle =====
bool g_once=false;

// --- Unique scan namespace for all markers in a single run ---
int g_scan_id = 0;

// --- NEW: Auto Master/Slave role based on chart timeframe (H4=Master, M15=Slave) ---
enum WBRole { WBROLE_STANDALONE=0, WBROLE_MASTER_H4=1, WBROLE_SLAVE_M15=2 };
WBRole g_role = WBROLE_STANDALONE;

inline WBRole __WB_DetectRole()
{
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Period();
   if(tf == PERIOD_H4)  return WBROLE_MASTER_H4;
   if(tf == PERIOD_M15) return WBROLE_SLAVE_M15;
   return WBROLE_STANDALONE;
}

inline ENUM_TIMEFRAMES __WB_EffectiveTF()
{
   if(g_role == WBROLE_MASTER_H4)  return PERIOD_H4;
   if(g_role == WBROLE_SLAVE_M15) return PERIOD_M15;
   return InpTF; // legacy standalone mode
}

inline void __WB_ApplyHiddenVisualPolicies()
{
   ExtLQ_DeleteAllVisuals_AllScans();
   ExtLQ_Down_DeleteAllVisuals_AllScans();
   Race_DeleteRefVisuals_AllScans();
}
// ============================================================================
// Minor session runner (Phase-1: Minor inside Major)
// ============================================================================

// Reset ExtLQ-UP globals by importing a blank context (no drawing, no history push)
inline void __WB_ResetExtLQ_UP()
{
   ExtLQContext ctx;
   ctx.ext_has   = false;
   ctx.ext_price = 0.0;
   ctx.ext_time  = 0;
   ArrayResize(ctx.hist, 0);
   ctx.prev_idx  = -1;
   ExtLQ_ContextImport(ctx);
}

// Reset ExtLQ-DOWN globals by importing a blank context
inline void __WB_ResetExtLQ_DN()
{
   ExtLQDownContext ctx;
   ExtLQ_Down_ContextReset(ctx);
   // ContextReset already clears hist and sets ext_has=false
   ExtLQ_Down_ContextImport(ctx);
}

// Reset all stateful modules to start a fresh Minor world (no object deletions)
inline void __WB_ResetMinorWorldGlobals()
{
   // ExtLQ states
   __WB_ResetExtLQ_UP();
   __WB_ResetExtLQ_DN();

   // Hunters
   Hunter_UP_ResetGlobals();
   Hunter_DN_ResetGlobals();

   // HWBB
   HW_BB_ResetGlobals();

   // Race (use context reset to also clear active refs)
   RaceContext rc;
   Race_ContextReset(rc);
   Race_ContextImport(rc);

   // Gates / guards
   C1Pre_ResetGlobals();
   C1W2Gate_ResetGlobals();
   SWGate_ResetGlobals();
   SB_ResetGlobals();
   W3CG_ResetGlobals();

   // FSMS + FSMS_SW
   FSMS_ResetGlobals();
   FSMS_SW_ResetGlobals();

   // SR stack
   SR_ResetGlobals();
   SRMIT_ResetGlobals();
   SR_GoozBaghali_ResetAll();
   SR_AllowBoth(); // SR_Gate has no context; ensure neutral start
}

// Apply initial ext LQ for the Minor world (NO drawing; just state for logic)
inline void __WB_ApplyMinorInitialExtLQ(const FSMS_SW_MinorSession &s)
{
   if(s.dir == DIR_UP)
   {
      // ext lq minor ????? = Low(C1_W3_minor) @ time(C1_W3_minor)
      ExtLQContext e;
      e.ext_has   = true;
      e.ext_price = s.ext_init_price;
      e.ext_time  = s.ext_init_time;
      ArrayResize(e.hist, 0);
      e.prev_idx  = -1;
      ExtLQ_ContextImport(e);

      Hunter_OnExtLQUpdated(); // sync hunter-UP to this LQ
   }
   else
   {
      // ext lq minor ????? = High(C1_W3_minor) @ time(C1_W3_minor)
      ExtLQDownContext d;
      ExtLQ_Down_ContextReset(d);
      d.ext_has   = true;
      d.ext_price = s.ext_init_price;
      d.ext_time  = s.ext_init_time;
      // d.hist already empty, d.prev_idx=-1
      ExtLQ_Down_ContextImport(d);

      Hunter_Down_OnExtLQUpdated(); // sync hunter-DOWN to this LQ
   }
}

// Run a single closed minor session (starter..off) as an independent scan
inline void __WB_RunOneMinorSession(const FSMS_SW_MinorSession &s)
{
   if(!s.used) return;
   if(s.open)  return;                 // ???? ???? ????
   if(s.starter_time <= 0) return;
   if(s.off_time     <= 0) return;

   datetime from_time = s.starter_time;
   datetime to_time   = s.off_time;

   if(to_time < from_time)
   {
      datetime tmp = from_time;
      from_time = to_time;
      to_time   = tmp;
   }

   // Minor world namespace
   Markers_SetNamespace("MIN");

   // Fresh Minor world states
   __WB_ResetMinorWorldGlobals();

   // Apply initial LQ anchor for Minor
   __WB_ApplyMinorInitialExtLQ(s);

   // Run scan only in the default direction of the session
   // + init-extLQ from session + tagSuffix "_minor"
   if(s.dir == DIR_UP)
      API_RunScanSequential_W2W3_Hunter(InpSymbol, InpTF, from_time, to_time,
                                        true, s.ext_init_price, s.ext_init_time, "_minor");
   else
      API_Down_RunScanSequential_W2W3_Hunter(InpSymbol, InpTF, from_time, to_time,
                                             true, s.ext_init_price, s.ext_init_time, "_minor");
}

// --- ???? ???? ---
void ResolveWindow(datetime &start, datetime &stop)
{
   if(InpMostRecentOnly){ start=0; stop=TimeCurrent(); return; }
   start = ResolveScanStart(InpUseMonthsAgo, InpMonthsAgo, InpScanFromDate);
   stop  = TimeCurrent();
}

int OnInit()
{
   g_role = __WB_DetectRole();

   // Ensure WorldManager captures clean baselines before any scan starts
   Markers_SetNamespace("MAJ");
   WBWM_Init();
   __WB_ApplyHiddenVisualPolicies();

   // M15 Slave: start in idle mode and wait for Master signals
   if(g_role == WBROLE_SLAVE_M15)
      WB15_SlaveInit();

   EventSetTimer(g_role == WBROLE_SLAVE_M15 ? 1 : 2);
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason){ __WB_ApplyHiddenVisualPolicies(); EventKillTimer(); }
void OnTick(){}

// --- One-shot ShadowBreaker scan (migrated from old OnStart) ---
static bool g_sb_ran = false;   // guard: execute once inside EA

void SB_RunOneShot()
{
   ++g_scan_id;                 // prefix ????
   datetime start=0, stop=0;
   ResolveWindow(start, stop);  // ???? ???? ?? ??? ?? WaveBot.mq5 ???. :contentReference[oaicite:1]{index=1}

   // ????? ???? ?? ?? ?? ???? Shadow Breaker ???? API ?? ????? ??????
   int upPairs   = API_RunScanSequential_W2W3_Hunter(InpSymbol, InpTF, start, stop);
   int downPairs = API_Down_RunScanSequential_W2W3_Hunter(InpSymbol, InpTF, start, stop);

   if(InpDebugPrints)
      Print("[SB] Scan done. Pairs UP=", upPairs, " | Pairs DOWN=", downPairs,
            " | NOTE: Only SHADOW_BREAK_* markers are drawn by the ShadowBreaker module.");
}

// --- OnTimer: ??????? ????? + ????? ??? ?? Mode ????? + ????? Minor sessions ---
void OnTimer()
{
   // SLAVE (M15): only run the simple bridge (no bootstrap / no wave scan)
   if(g_role == WBROLE_SLAVE_M15)
   {
      WB15_Slave_OnTimer(InpSymbol);
      return;
   }

   // Major namespace (default world)
   Markers_SetNamespace("MAJ");
   __WB_ApplyHiddenVisualPolicies();

   // --- optional one-shot ShadowBreaker run (replacement for old OnStart)
   if(InpRunShadowBreakerOnce && !g_sb_ran)
   {
      SB_RunOneShot();
      g_sb_ran = true;
   }

   if(g_once) return;

   // MASTER (H4): start a fresh run for the M15 bridge (streamed signals)
   if(g_role == WBROLE_MASTER_H4)
      WB15_MasterBegin(InpSymbol);

   datetime start=0, stop=0;
   ResolveWindow(start, stop);

   ENUM_TIMEFRAMES tf = __WB_EffectiveTF();

   // 1) ?????????: ??????? ?????? ??? UP/DOWN ???? ??? ????? ??? ????????
   BootOutcome boot = Bootstrap_RaceDetect(InpSymbol, tf, start, stop);

   Direction mode_for_run = InpDirection;   // fallback
   datetime  resume_from  = start;          // ??? ??? ???? ????? ?? ?????? ????

   if(boot.ok)
   {
      mode_for_run = boot.mode;

      // ?? «???? ????? body-break» ????? ??? ?? ??????????? ??????? ?????? ?????
      resume_from = boot.complete_time + PeriodSeconds(tf);

      if(InpDebugPrints)
         Print("[BOOT] Winner=", (mode_for_run==DIR_UP?"UP":"DOWN"),
               " | first pair @ ", TimeToString(boot.complete_time, TIME_DATE|TIME_SECONDS),
               " | resume_from=", TimeToString(resume_from, TIME_DATE|TIME_SECONDS));
   }
   else
   {
      if(InpDebugPrints)
         Print("[BOOT] No completed pair found in window. Fallback to input direction.");
   }

   // 2) ????? Major scan ??? ?? Mode ????? (?? Fallback)
   if(mode_for_run==DIR_UP)
      API_RunScanSequential_W2W3_Hunter(InpSymbol, tf, resume_from, stop);
   else
      API_Down_RunScanSequential_W2W3_Hunter(InpSymbol, tf, resume_from, stop);

   g_once=true;  // ?????? ???? ???? ??? ?? ??? ???? ????? (??? ???? ????? ???? ???)
}
