
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
input datetime          InpScanFromDate        = D'2025.4.00 00:00';

// --- ???? ????????? ????? ????? (???? ?????) ---
input bool              InpRequireCloseBreakAboveW2H1 = true;
input bool              InpDrawExtLQ  = false;
input color             InpExtLQColor = clrMagenta;
input bool              InpEnableHunterMarkers = true;

input bool InpRunShadowBreakerOnce = false;  // ??? true ????? ?????? SB_RunOneShot ???? ??????

// ===== Trigger statement (text report) =====
input bool              InpEnableTriggerStatement          = true;
input double            InpTriggerStatementInitialCapital  = 10000.0;
input double            InpTriggerStatementRiskPercent     = 1.0;
input string            InpTriggerStatementFileTag         = "WaveBot_TriggerStatement";

// ===== Includes (??? ?? Inputs) =====
#include <WaveBot/Utils.mqh>
#include <WaveBot/Data.mqh>
#include <WaveBot/Markers.mqh>
// NEW: Simple H4->M15 bridge (signals + candle counting)
#include <WaveBot/WB15_SignalBridge.mqh>
#include <WaveBot/Trigger.mqh>
#include <WaveBot/TriggerStatement.mqh>
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

// --- Trigger statement scan window snapshot ---
datetime g_stmt_scan_start = 0;
datetime g_stmt_scan_stop  = 0;
bool     g_stmt_window_set = false;
bool     g_stmt_first_write_done = false;
datetime g_stmt_last_write_attempt = 0;

// --- Auto role based on chart timeframe (H4 -> M15 -> M1) ---
enum WBRole
{
   WBROLE_STANDALONE = 0,
   WBROLE_MASTER_H4  = 1,
   WBROLE_MIDDLE_M15 = 2,
   WBROLE_TRIGGER_M1 = 3
};
WBRole g_role = WBROLE_STANDALONE;

inline WBRole __WB_DetectRole()
{
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Period();

   if(tf == PERIOD_H4)  return WBROLE_MASTER_H4;
   if(tf == PERIOD_M15) return WBROLE_MIDDLE_M15;
   if(tf == PERIOD_M1)  return WBROLE_TRIGGER_M1;

   return WBROLE_STANDALONE;
}

inline bool __WB_IsRoleH4()
{
   return (g_role == WBROLE_MASTER_H4);
}

inline bool __WB_IsRoleM15()
{
   return (g_role == WBROLE_MIDDLE_M15);
}

inline bool __WB_IsRoleM1()
{
   return (g_role == WBROLE_TRIGGER_M1);
}

inline ENUM_TIMEFRAMES __WB_EffectiveTF()
{
   if(__WB_IsRoleH4())  return PERIOD_H4;
   if(__WB_IsRoleM15()) return PERIOD_M15;
   if(__WB_IsRoleM1())  return PERIOD_M1;

   return InpTF; // legacy standalone mode
}

inline bool __WB_ShouldRunTriggerEngine()
{
   return __WB_IsRoleM1();
}

void ResolveWindow(datetime &start, datetime &stop);

inline void __WB_ApplyHiddenVisualPolicies()
{
   ExtLQ_DeleteAllVisuals_AllScans();
   ExtLQ_Down_DeleteAllVisuals_AllScans();
   Race_DeleteRefVisuals_AllScans();
}

inline void __WB_DeleteAllM15NumberingObjects()
{
   // Legacy function name kept intentionally.
   // We also purge old local minor-world artifacts from M1 because minor logic
   // is no longer allowed to execute on M15 or M1.
   ENUM_TIMEFRAMES chart_tf = (ENUM_TIMEFRAMES)Period();
   if(chart_tf != PERIOD_M15 && chart_tf != PERIOD_M1) return;

   for(int i = ObjectsTotal(0) - 1; i >= 0; --i)
   {
      string on = ObjectName(0, i);
      if(on == "") continue;

      bool kill = false;

      if(StringFind(on, "WB15_CNT_") == 0)
         kill = true;

      if(!kill && StringFind(on, "MinorSeq_U_") >= 0)
         kill = true;

      if(!kill && StringFind(on, "MinorSeq_D_") >= 0)
         kill = true;

      if(!kill && StringFind(on, "w2_minor_") >= 0)
         kill = true;

      if(!kill && StringFind(on, "w3_minor_") >= 0)
         kill = true;

      if(!kill && StringFind(on, "FSMS_Minor_U_") >= 0)
         kill = true;

      if(!kill && StringFind(on, "FSMS_Minor_D_") >= 0)
         kill = true;

      if(!kill && StringFind(on, "MinorStarter_U_") >= 0)
         kill = true;

      if(!kill && StringFind(on, "MinorStarter_D_") >= 0)
         kill = true;

      if(!kill && StringFind(on, "MinorOff_U_") >= 0)
         kill = true;

      if(!kill && StringFind(on, "MinorOff_D_") >= 0)
         kill = true;

      if(!kill && StringFind(on, "C1_W2_MinorZone_U_") >= 0)
         kill = true;

      if(!kill && StringFind(on, "C1_W2_MinorZone_D_") >= 0)
         kill = true;

      if(!kill && StringFind(on, "C1_W3_MinorZone_U_") >= 0)
         kill = true;

      if(!kill && StringFind(on, "C1_W3_MinorZone_D_") >= 0)
         kill = true;

      if(kill)
         ObjectDelete(0, on);
   }
}

inline bool __WB_ShouldHandleTriggerStatement()
{
   if(!InpEnableTriggerStatement)
      return false;

   return ((ENUM_TIMEFRAMES)Period() == PERIOD_M1);
}

inline void __WB_RememberTriggerStatementWindow(const datetime start,
                                                const datetime stop)
{
   g_stmt_scan_start = start;
   g_stmt_scan_stop  = stop;
   g_stmt_window_set = true;
}

inline void __WB_WriteTriggerStatementReport()
{
   if(!__WB_ShouldHandleTriggerStatement())
      return;

   datetime stmt_start = 0;
   datetime stmt_stop  = 0;

   if(g_stmt_window_set)
   {
      stmt_start = g_stmt_scan_start;
      stmt_stop  = TimeCurrent();
      if(stmt_stop <= 0)
         stmt_stop = g_stmt_scan_stop;
   }
   else
   {
      ResolveWindow(stmt_start, stmt_stop);
   }

   if(stmt_stop <= 0)
      stmt_stop = TimeCurrent();
   if(stmt_start > stmt_stop)
      stmt_start = 0;

<<<<<<< HEAD
=======
   g_stmt_last_write_attempt = TimeCurrent();

>>>>>>> e5da32fe47c817fae05de25b108d1646fb695725
   bool ok = TriggerStatement_WriteTextReport(InpSymbol,
                                              (ENUM_TIMEFRAMES)Period(),
                                              stmt_start,
                                              stmt_stop,
                                              InpTriggerStatementInitialCapital,
                                              InpTriggerStatementRiskPercent,
                                              InpTriggerStatementFileTag);
   if(ok)
   {
<<<<<<< HEAD
      g_stmt_scan_stop = stmt_stop;
      TriggerSLTP_ClearStatementDirty();
   }
=======
      g_stmt_first_write_done = true;
      g_stmt_scan_stop = stmt_stop;
      TriggerSLTP_ClearStatementDirty();
   }
   else if(InpDebugPrints)
   {
      Print("[WB] Trigger statement write failed | last_path=", TriggerStatement_LastFullPath(),
            " | records=", TriggerStatement_LastRecordCount());
   }
}

inline void __WB_MaybeWriteTriggerStatementReport()
{
   if(!__WB_ShouldHandleTriggerStatement())
      return;

   // The first write creates the TXT file even before the first valid trade.
   // Later writes are event-driven through TriggerSLTP's dirty flag.
   if(!g_stmt_first_write_done || TriggerSLTP_IsStatementDirty())
      __WB_WriteTriggerStatementReport();
}

bool WaveBot_RequestImmediateTriggerStatementWrite()
{
   if(!__WB_ShouldHandleTriggerStatement())
      return false;

   __WB_WriteTriggerStatementReport();
   return TriggerStatement_LastWriteOK();
>>>>>>> e5da32fe47c817fae05de25b108d1646fb695725
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
   const ENUM_TIMEFRAMES tf = __WB_EffectiveTF();

   if(s.dir == DIR_UP)
      API_RunScanSequential_W2W3_Hunter(InpSymbol, tf, from_time, to_time,
                                        true, s.ext_init_price, s.ext_init_time, "_minor");
   else
      API_Down_RunScanSequential_W2W3_Hunter(InpSymbol, tf, from_time, to_time,
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
   Trigger_ResetGlobals();
   TriggerStatement_ResetGlobals();
   TriggerM15SignalGate_ResetGlobals();

   g_stmt_scan_start = 0;
   g_stmt_scan_stop  = 0;
   g_stmt_window_set = false;
<<<<<<< HEAD
=======
   g_stmt_first_write_done = false;
   g_stmt_last_write_attempt = 0;
>>>>>>> e5da32fe47c817fae05de25b108d1646fb695725

   __WB_ApplyHiddenVisualPolicies();
   __WB_DeleteAllM15NumberingObjects();

   if(__WB_IsRoleM15())
   {
      WB15_SlaveInit();
   }
   else if(__WB_IsRoleM1())
   {
      WB1_SlaveInit();
   }

<<<<<<< HEAD
=======
   if(__WB_ShouldHandleTriggerStatement())
   {
      datetime stmt_start = 0;
      datetime stmt_stop  = 0;
      ResolveWindow(stmt_start, stmt_stop);
      __WB_RememberTriggerStatementWindow(stmt_start, stmt_stop);
      __WB_WriteTriggerStatementReport();
   }

>>>>>>> e5da32fe47c817fae05de25b108d1646fb695725
   EventSetTimer((__WB_IsRoleM15() || __WB_IsRoleM1()) ? 1 : 2);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   __WB_ApplyHiddenVisualPolicies();
   __WB_DeleteAllM15NumberingObjects();
   __WB_WriteTriggerStatementReport();

   Trigger_ResetGlobals();
   TriggerStatement_ResetGlobals();
   TriggerM15SignalGate_ResetGlobals();

   EventKillTimer();
}

void OnTick(){}

// --- One-shot ShadowBreaker scan (migrated from old OnStart) ---
static bool g_sb_ran = false;   // guard: execute once inside EA

void SB_RunOneShot()
{
   ++g_scan_id;                 // prefix ????
   datetime start=0, stop=0;
   ResolveWindow(start, stop);  // ???? ???? ?? ??? ?? WaveBot.mq5 ???. :contentReference[oaicite:1]{index=1}

   const ENUM_TIMEFRAMES tf = __WB_EffectiveTF();

   // ????? ???? ?? ?? ?? ???? Shadow Breaker ???? API ?? ????? ??????
   int upPairs   = API_RunScanSequential_W2W3_Hunter(InpSymbol, tf, start, stop);
   int downPairs = API_Down_RunScanSequential_W2W3_Hunter(InpSymbol, tf, start, stop);

   if(InpDebugPrints)
      Print("[SB] Scan done. Pairs UP=", upPairs, " | Pairs DOWN=", downPairs,
            " | NOTE: Only SHADOW_BREAK_* markers are drawn by the ShadowBreaker module.");
}

// --- OnTimer: bridge sync + one-shot scan on the current role + live trigger on M1 ---
void OnTimer()
{
   if(__WB_IsRoleM15())
   {
      WB15_Slave_OnTimer(InpSymbol);
      __WB_DeleteAllM15NumberingObjects();
   }
   else if(__WB_IsRoleM1())
   {
      WB1_Slave_OnTimer(InpSymbol);
      __WB_DeleteAllM15NumberingObjects();
   }

   // Major namespace (default world)
   Markers_SetNamespace("MAJ");
   __WB_ApplyHiddenVisualPolicies();

   if(__WB_ShouldRunTriggerEngine())
      Trigger_OnTimer(InpSymbol);
<<<<<<< HEAD
=======

   // On M1, live trigger processing can happen before the initial one-shot scan
   // finishes or before parent-readiness allows the scan branch below to run.
   // Therefore statement writing must be checked immediately after Trigger_OnTimer.
   __WB_MaybeWriteTriggerStatementReport();
>>>>>>> e5da32fe47c817fae05de25b108d1646fb695725

   // --- optional one-shot ShadowBreaker run (replacement for old OnStart)
   if(InpRunShadowBreakerOnce && !g_sb_ran)
   {
      SB_RunOneShot();
      g_sb_ran = true;
   }

   if(g_once)
   {
<<<<<<< HEAD
      if(__WB_ShouldHandleTriggerStatement() && TriggerSLTP_IsStatementDirty())
         __WB_WriteTriggerStatementReport();
=======
      __WB_MaybeWriteTriggerStatementReport();
>>>>>>> e5da32fe47c817fae05de25b108d1646fb695725
      return;
   }

   // Readiness / lifecycle across the 3 charts
   if(__WB_IsRoleH4())
   {
      WB15_MasterBegin(InpSymbol);
   }
   else if(__WB_IsRoleM15())
   {
      if(!WB15_MasterIsReadyForChild(InpSymbol))
         return;

      WB1_MasterBegin(InpSymbol);
   }
   else if(__WB_IsRoleM1())
   {
      if(!WB1_MasterIsReadyForChild(InpSymbol))
         return;
   }

   datetime start = 0;
   datetime stop  = 0;
   ResolveWindow(start, stop);
   __WB_RememberTriggerStatementWindow(start, stop);

   ENUM_TIMEFRAMES tf = __WB_EffectiveTF();

   // 1) بوت‌استرپ: تعیین جهت اولیه با اولین جفت کامل‌شده
   BootOutcome boot = Bootstrap_RaceDetect(InpSymbol, tf, start, stop);

   Direction mode_for_run = InpDirection;   // fallback
   datetime  resume_from  = start;          // شروع اسکن اصلی در صورت نبود بوت‌استرپ

   if(boot.ok)
   {
      mode_for_run = boot.mode;

      // از بعدِ کندل body-break اسکن اصلی ادامه پیدا می‌کند
      resume_from = boot.complete_time + PeriodSeconds(tf);

      if(InpDebugPrints)
         Print("[BOOT] Winner=", (mode_for_run==DIR_UP ? "UP" : "DOWN"),
               " | first pair @ ", TimeToString(boot.complete_time, TIME_DATE|TIME_SECONDS),
               " | resume_from=", TimeToString(resume_from, TIME_DATE|TIME_SECONDS));
   }
   else
   {
      if(InpDebugPrints)
         Print("[BOOT] No completed pair found in window. Fallback to input direction.");
   }

   // 2) اجرای اسکن Major با Mode تعیین‌شده (یا Fallback)
   if(mode_for_run == DIR_UP)
      API_RunScanSequential_W2W3_Hunter(InpSymbol, tf, resume_from, stop);
   else
      API_Down_RunScanSequential_W2W3_Hunter(InpSymbol, tf, resume_from, stop);

   if(__WB_IsRoleH4())
      WB15_MasterMarkScanDone(InpSymbol);
   else if(__WB_IsRoleM15())
      WB1_MasterMarkScanDone(InpSymbol);

   __WB_WriteTriggerStatementReport();

   g_once = true;  // فقط یک‌بار اسکن کامل در هر اجرای EA
}
