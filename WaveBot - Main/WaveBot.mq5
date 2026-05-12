#property strict
#property description "WaveBot – W2/W3 + Hunter + ExtLQ + SW (Bootstrap Direction Race)"

#include <Trade/Trade.mqh>
#include <WaveBot/Types.mqh>      // Direction ?? ??? ?? ??????? ??? ???????
CTrade trade;

// ===== Inputs =====
input string            InpSymbol              = "EURUSD";
input ENUM_TIMEFRAMES   InpTF                  = PERIOD_M15;
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
input datetime          InpScanFromDate        = D'2026.01.00 00:00';

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
#include <WaveBot/WaveBotLogger.mqh>
// NEW: Simple M15->M1 bridge (signals + candle counting)
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

// --- M1 hard end-of-scan stop guard ---
bool     g_final_outputs_written = false;
bool     g_m1_scan_hard_stopped  = false;
datetime g_m1_scan_hard_stop_time = 0;

// --- NEW: Auto Master/Slave role based on chart timeframe (M15=Master, M1=Slave) ---
enum WBRole { WBROLE_STANDALONE=0, WBROLE_MASTER_M15=1, WBROLE_SLAVE_M1=2 };
WBRole g_role = WBROLE_STANDALONE;

inline WBRole __WB_DetectRole()
{
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Period();
   if(tf == PERIOD_M15) return WBROLE_MASTER_M15;
   if(tf == PERIOD_M1)  return WBROLE_SLAVE_M1;
   return WBROLE_STANDALONE;
}

inline ENUM_TIMEFRAMES __WB_EffectiveTF()
{
   if(g_role == WBROLE_MASTER_M15) return PERIOD_M15;
   if(g_role == WBROLE_SLAVE_M1)   return PERIOD_M1;
   return InpTF; // legacy standalone mode
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
   if((ENUM_TIMEFRAMES)Period() != PERIOD_M1) return;

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

inline void __WB_WriteTriggerStatementReportCore(const datetime fixed_stop,
                                                const bool     force_even_if_scheduled)
{
   if(!__WB_ShouldHandleTriggerStatement())
      return;

   if(TriggerStatement_ScheduledOutputActive() && !force_even_if_scheduled)
      return;

   datetime stmt_start = 0;
   datetime stmt_stop  = 0;

   if(g_stmt_window_set)
   {
      stmt_start = g_stmt_scan_start;
      stmt_stop  = g_stmt_scan_stop;
   }
   else
   {
      ResolveWindow(stmt_start, stmt_stop);
   }

   if(fixed_stop > 0)
      stmt_stop = fixed_stop;

   if(stmt_stop <= 0)
      stmt_stop = TimeCurrent();

   if(!force_even_if_scheduled && stmt_stop < TimeCurrent())
      stmt_stop = TimeCurrent();

   bool stmt_ok = TriggerStatement_WriteTextReport(InpSymbol,
                                                (ENUM_TIMEFRAMES)Period(),
                                                stmt_start,
                                                stmt_stop,
                                                InpTriggerStatementInitialCapital,
                                                InpTriggerStatementRiskPercent,
                                                InpTriggerStatementFileTag);
   if(stmt_ok)
      TriggerStatement_LiveClearPendingAfterExternalWrite();
}

inline void __WB_WriteTriggerStatementReport()
{
   __WB_WriteTriggerStatementReportCore(0, false);
}

inline void __WB_WriteTriggerStatementReportFinal(const datetime final_stop)
{
   __WB_WriteTriggerStatementReportCore(final_stop, true);
}

inline datetime __WB_ResolveM1HardStopBoundary(const datetime requested_stop)
{
   datetime use_stop = requested_stop;
   if(use_stop <= 0)
      use_stop = TimeCurrent();

   // Freeze M1 to the last CLOSED candle. The current forming M1 candle can keep
   // changing near the live edge and can cause the final-days rescan loop.
   datetime last_closed_m1 = iTime(InpSymbol, PERIOD_M1, 1);
   if(last_closed_m1 > 0 && last_closed_m1 < use_stop)
      use_stop = last_closed_m1;

   if(use_stop <= 0)
      use_stop = TimeCurrent();

   return use_stop;
}

inline datetime __WB_M1ExclusiveBoundaryAfterStop(const datetime closed_stop)
{
   int tfsec = PeriodSeconds(PERIOD_M1);
   if(tfsec <= 0)
      tfsec = 60;
   if(closed_stop <= 0)
      return TimeCurrent();
   return (datetime)(closed_stop + (datetime)tfsec);
}

inline void __WB_PrimeM1HardStopBoundary(const datetime requested_stop)
{
   if(g_role != WBROLE_SLAVE_M1)
   {
      Trigger_SetM1HardStop(0, false);
      return;
   }

   if(g_m1_scan_hard_stop_time <= 0)
      g_m1_scan_hard_stop_time = __WB_ResolveM1HardStopBoundary(requested_stop);

   if(g_m1_scan_hard_stop_time > 0)
      Trigger_SetM1HardStop(g_m1_scan_hard_stop_time, false);
}

inline bool __WB_FinalScanOutputCompleted()
{
   return g_final_outputs_written;
}

inline void __WB_FlushFinalScanOutputs(const datetime scan_stop)
{
   datetime use_stop = scan_stop;
   if(use_stop <= 0)
      use_stop = TimeCurrent();

   datetime use_start = g_stmt_scan_start;
   if(!g_stmt_window_set || use_start <= 0)
   {
      datetime tmp_stop = use_stop;
      ResolveWindow(use_start, tmp_stop);
   }

   __WB_RememberTriggerStatementWindow(use_start, use_stop);

   if(TriggerStatement_ScheduledOutputActive())
   {
      // M1 final-only output mode: rebuild Statement and diagnostic CSV
      // snapshots once, exactly after the terminal M1 hard stop.
      WBLOG_BeginScheduledOutputWrite();
      WBLOG_ExportScheduledCandleSnapshots(InpSymbol, use_start, use_stop);
      __WB_WriteTriggerStatementReportFinal(use_stop);
      WBLOG_EndScheduledOutputWrite(TriggerStatement_LastWriteOK());
   }
   else
   {
      __WB_WriteTriggerStatementReportFinal(use_stop);
   }

   g_final_outputs_written = true;
   WBLOG_FlushSnapshotFilesIfDirty();
   WBLOG_FlushAllOpenFiles();
}

inline void __WB_HardStopM1AtScanEnd(const datetime scan_stop)
{
   if(g_role != WBROLE_SLAVE_M1)
      return;

   datetime use_stop = scan_stop;
   if(g_m1_scan_hard_stop_time > 0)
      use_stop = g_m1_scan_hard_stop_time;
   else
      use_stop = __WB_ResolveM1HardStopBoundary(use_stop);

   if(use_stop <= 0)
      use_stop = TimeCurrent();

   if(g_m1_scan_hard_stopped)
   {
      EventKillTimer();
      return;
   }

   g_m1_scan_hard_stopped   = true;
   g_m1_scan_hard_stop_time = use_stop;

   Trigger_FinalizeM1HardStop(use_stop);
   TriggerStatement_SetBulkScanMode(false);

   if(!__WB_FinalScanOutputCompleted())
      __WB_FlushFinalScanOutputs(use_stop);

   WBLOG_LogParam("M1HardStop", "true", "M1_SCAN_REACHED_END_OF_CHART");
   WBLOG_LogParam("M1HardStopTime", WBLOG_Time(use_stop), "WaveBot.mq5");
   WBLOG_FlushSnapshotFilesIfDirty();
   WBLOG_FlushAllOpenFiles();

   EventKillTimer();

   if(InpDebugPrints)
   {
      Print("[WB-M1-HARD-STOP] Historical M1 scan reached final scan boundary @ ",
            TimeToString(use_stop, TIME_DATE|TIME_SECONDS),
            ". Timer killed and EA removal requested after final Statement/Log flush.");
   }

   if((bool)MQLInfoInteger(MQL_TESTER))
      TesterStop();
   else
      ExpertRemove();
}

inline void __WB_EnsureLiveTriggerStatementFile()
{
   if(!__WB_ShouldHandleTriggerStatement())
      return;

   datetime stmt_start = 0;
   datetime stmt_stop  = 0;
   ResolveWindow(stmt_start, stmt_stop);
   __WB_RememberTriggerStatementWindow(stmt_start, stmt_stop);

   TriggerStatement_LiveConfigure(InpSymbol,
                                  (ENUM_TIMEFRAMES)Period(),
                                  stmt_start,
                                  InpTriggerStatementInitialCapital,
                                  InpTriggerStatementRiskPercent,
                                  InpTriggerStatementFileTag);

   datetime initial_cutoff = stmt_start;
   if(initial_cutoff <= 0)
      initial_cutoff = (datetime)1;

   // Do not write the Statement at initialization. On M1 the full Statement
   // and CSV diagnostics are rebuilt once after the terminal hard stop.
   TriggerStatement_LiveMarkDirty(initial_cutoff);
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

   datetime __wblog_scan_from = 0;
   datetime __wblog_scan_to   = 0;
   ResolveWindow(__wblog_scan_from, __wblog_scan_to);

   bool __m1_final_only_output = ((ENUM_TIMEFRAMES)Period() == PERIOD_M1);
   WBLOG_SetFinalOnlyOutput(__m1_final_only_output);

   WBLOG_Initialize(InpSymbol,
                    PERIOD_M15,
                    PERIOD_M1,
                    __wblog_scan_from,
                    __wblog_scan_to,
                    InpTriggerStatementInitialCapital,
                    InpTriggerStatementRiskPercent,
                    (InpDirection == DIR_UP ? "DIR_UP" : "DIR_DOWN"),
                    "WaveBot_160_M15_ThreeStage_FlipMajic_DiagnosticLogger",
                    (g_role == WBROLE_MASTER_M15 || g_role == WBROLE_STANDALONE));

   WBLOG_LogParam("InpSymbol", InpSymbol, "input");
   WBLOG_LogParam("InpTF", IntegerToString((int)InpTF), "input");
   WBLOG_LogParam("InpLookbackBars", IntegerToString(InpLookbackBars), "input");
   WBLOG_LogParam("InpMaxBarsInWave", IntegerToString(InpMaxBarsInWave), "input");
   WBLOG_LogParam("InpDirection", (InpDirection == DIR_UP ? "DIR_UP" : "DIR_DOWN"), "input");
   WBLOG_LogParam("InpMostRecentOnly", (InpMostRecentOnly ? "true" : "false"), "input");
   WBLOG_LogParam("InpUseMonthsAgo", (InpUseMonthsAgo ? "true" : "false"), "input");
   WBLOG_LogParam("InpMonthsAgo", IntegerToString(InpMonthsAgo), "input");
   WBLOG_LogParam("InpScanFromDate", WBLOG_Time(InpScanFromDate), "input");
   WBLOG_LogParam("InpEnableTriggerStatement", (InpEnableTriggerStatement ? "true" : "false"), "input");
   WBLOG_LogParam("InpTriggerStatementInitialCapital", DoubleToString(InpTriggerStatementInitialCapital, 2), "input");
   WBLOG_LogParam("InpTriggerStatementRiskPercent", DoubleToString(InpTriggerStatementRiskPercent, 4), "input");
   WBLOG_LogParam("TRGSL_MAX_RISK_PIPS", "25.0", "TriggerSLTP.mqh");
   WBLOG_LogParam("TRGSL_R_MULTIPLE", "3.0", "TriggerSLTP.mqh");

   // Ensure WorldManager captures clean baselines before any scan starts
   Markers_SetNamespace("MAJ");
   WBWM_Init();
   Trigger_ResetGlobals();
   TriggerStatement_ResetGlobals();
   TriggerStatement_SetFinalOnlyOutput(__m1_final_only_output);
   g_stmt_scan_start = 0;
   g_stmt_scan_stop  = 0;
   g_stmt_window_set = false;
   g_final_outputs_written = false;
   g_m1_scan_hard_stopped = false;
   g_m1_scan_hard_stop_time = 0;
   Trigger_SetM1HardStop(0, false);
   __WB_ApplyHiddenVisualPolicies();
   __WB_DeleteAllM15NumberingObjects();
   __WB_EnsureLiveTriggerStatementFile();

   // M1 Slave: start in idle mode and wait for Master signals
   if(g_role == WBROLE_SLAVE_M1)
      WB15_SlaveInit();

   EventSetTimer(g_role == WBROLE_SLAVE_M1 ? 1 : 2);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   __WB_ApplyHiddenVisualPolicies();
   __WB_DeleteAllM15NumberingObjects();
   if(!__WB_FinalScanOutputCompleted())
   {
      datetime final_stop = g_stmt_scan_stop;
      if(final_stop <= 0)
         final_stop = TimeCurrent();
      __WB_FlushFinalScanOutputs(final_stop);
   }
   WBLOG_Finalize();
   Trigger_ResetGlobals();
   TriggerStatement_ResetGlobals();
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

// --- OnTimer: ??????? ????? + ????? ??? ?? Mode ????? + ????? Minor sessions ---
void OnTimer()
{
   if(g_role == WBROLE_SLAVE_M1 && g_m1_scan_hard_stopped)
   {
      EventKillTimer();
      return;
   }

   // M1 keeps listening to the M15 bridge on every timer tick.
   // Local MIN-world execution on the slave is disabled and any old
   // local-minor artifacts are purged from the chart.
   if(g_role == WBROLE_SLAVE_M1)
   {
      WB15_Slave_OnTimer(InpSymbol);
      __WB_DeleteAllM15NumberingObjects();

      if(Trigger_M1HardStopFinalizeRequested())
      {
         datetime requested_stop = Trigger_M1HardStopFinalizeTime();
         if(requested_stop <= 0)
            requested_stop = g_m1_scan_hard_stop_time;
         if(requested_stop <= 0)
            requested_stop = TimeCurrent();
         __WB_HardStopM1AtScanEnd(requested_stop);
         return;
      }
   }

   // Major namespace (default world)
   Markers_SetNamespace("MAJ");
   __WB_ApplyHiddenVisualPolicies();

   // After the first full M1 scan is finished, the live trigger timer can
   // advance on newly closed bars. During the initial historical scan we keep
   // trigger -> trade evaluation fully synchronized with the normal wave scan.
   if(g_once)
   {
      if(g_role == WBROLE_SLAVE_M1)
      {
         datetime final_stop = g_m1_scan_hard_stop_time;
         if(final_stop <= 0)
            final_stop = g_stmt_scan_stop;
         __WB_PrimeM1HardStopBoundary(final_stop);
         final_stop = g_m1_scan_hard_stop_time;
         if(final_stop <= 0)
            final_stop = TimeCurrent();
         __WB_HardStopM1AtScanEnd(final_stop);
         return;
      }

      Trigger_OnTimer(InpSymbol);
      if(!TriggerStatement_ScheduledOutputActive())
         TriggerStatement_LiveFlushPendingIfDue(30);
      return;
   }

   // --- optional one-shot ShadowBreaker run (replacement for old OnStart)
   if(InpRunShadowBreakerOnce && !g_sb_ran)
   {
      SB_RunOneShot();
      g_sb_ran = true;
   }

   // MASTER (M15): start a fresh run for the M1 bridge (streamed signals)
   if(g_role == WBROLE_MASTER_M15)
      WB15_MasterBegin(InpSymbol);

   datetime master_scan_end = 0;
   int      master_done_seq = 0;
   if(g_role == WBROLE_SLAVE_M1)
   {
      // Do not start the terminal M1 historical pass until the M15 master has
      // published all M15->M1 bridge events and its final scan boundary.
      if(!WB15_MasterDoneInfo(InpSymbol, master_scan_end, master_done_seq))
      {
         if(InpDebugPrints)
            Print("[WB-M1] Waiting for M15 master DONE marker before terminal M1 historical scan.");
         return;
      }
   }

   datetime start=0, stop=0;
   ResolveWindow(start, stop);
   if(g_role == WBROLE_SLAVE_M1 && master_scan_end > 0 && master_scan_end < stop)
      stop = master_scan_end;
   if(g_role == WBROLE_SLAVE_M1)
   {
      __WB_PrimeM1HardStopBoundary(stop);
      if(g_m1_scan_hard_stop_time > 0)
         stop = g_m1_scan_hard_stop_time;
   }
   __WB_RememberTriggerStatementWindow(start, stop);

   // Bulk historical pass: avoid rebuilding the full Statement after each
   // trigger. The complete final Statement is written immediately after this
   // scan finishes; live mode keeps immediate refresh behavior.
   TriggerStatement_SetBulkScanMode(true);

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
         Print("[BOOT] Winner=", (mode_for_run==DIR_UP?"UP":"DOWN"),
               " | first pair @ ", TimeToString(boot.complete_time, TIME_DATE|TIME_SECONDS),
               " | resume_from=", TimeToString(resume_from, TIME_DATE|TIME_SECONDS));
   }
   else
   {
      if(InpDebugPrints)
         Print("[BOOT] No completed pair found in window. Fallback to input direction.");
   }

   // 2) اجرای اسکن Major با Mode تعیین‌شده (یا Fallback)
   if(mode_for_run==DIR_UP)
      API_RunScanSequential_W2W3_Hunter(InpSymbol, tf, resume_from, stop);
   else
      API_Down_RunScanSequential_W2W3_Hunter(InpSymbol, tf, resume_from, stop);

   TriggerStatement_SetBulkScanMode(false);

   if(g_role == WBROLE_MASTER_M15)
      WB15_MasterEnd(InpSymbol, stop);

   if(g_role == WBROLE_SLAVE_M1)
   {
      __WB_PrimeM1HardStopBoundary(stop);
      if(Trigger_M1HardStopFinalizeRequested() && Trigger_M1HardStopFinalizeTime() > 0)
         stop = Trigger_M1HardStopFinalizeTime();
      else
      if(g_m1_scan_hard_stop_time > 0)
         stop = g_m1_scan_hard_stop_time;

      g_once = true;  // فقط یک‌بار اسکن کامل در هر اجرای EA
      __WB_HardStopM1AtScanEnd(stop);
      return;
   }

   __WB_FlushFinalScanOutputs(stop);

   g_once = true;  // فقط یک‌بار اسکن کامل در هر اجرای EA
}

