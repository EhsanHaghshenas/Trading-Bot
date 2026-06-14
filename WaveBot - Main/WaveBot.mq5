// UPDATE APPLIED: Central MULTI embedded detail SkipReason normalization
// - Combined/MULTI writer now normalizes embedded detail lines so central RefCap/M15Cap skips never display the legacy ONE_OPEN_TRADE_ALREADY_OPEN reason.
// - Output-only statement/reporting fix; no candle scan, trigger, SL/TP, bridge, or execution logic changed.
#property strict
#property description "WaveBot – W2/W3 + Hunter + ExtLQ + SW (Bootstrap Direction Race)"

#include <Trade/Trade.mqh>
#include <WaveBot/Types.mqh>      // Direction ?? ??? ?? ??????? ??? ???????
CTrade trade;

// ===== Inputs =====
input string            InpSymbol              = "EURUSD";
input bool              InpEnableCentralMultiSymbol = true;
input string            InpMultiSymbolList     = "EURUSD,GBPUSD,AUDUSD";
input bool              InpDrawOnlyChartSymbol = true;
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

// ===== M1 trade-limit and SL runtime settings =====
// These inputs are saved by the M15 chart and automatically reused by the M1 chart
// through MetaTrader terminal GlobalVariables, so the same values do not need to
// be entered twice when running the M15 master first and the M1 slave second.
input int               InpM1MaxTradesPerM15NewSignal = 4;
input int               InpM1MaxOpenTrades            = 1;
input double            InpM1MinSLPips                 = 1.4;
input double            InpM1MaxSLPips                 = 6.0;
input int               InpM1MaxTradesPerLocalRef     = 2;

#define WB_CFG_DEFAULT_MAX_TRADES_PER_M15_NEW 4
#define WB_CFG_DEFAULT_MAX_OPEN_TRADES        1
#define WB_CFG_DEFAULT_MIN_SL_PIPS            1.4
#define WB_CFG_DEFAULT_MAX_SL_PIPS            6.0
#define WB_CFG_DEFAULT_MAX_TRADES_LOCAL_REF   2

int    g_WB_M1MaxTradesPerM15NewSignal = WB_CFG_DEFAULT_MAX_TRADES_PER_M15_NEW;
int    g_WB_M1MaxOpenTrades            = WB_CFG_DEFAULT_MAX_OPEN_TRADES;
double g_WB_M1MinSLPips                 = WB_CFG_DEFAULT_MIN_SL_PIPS;
double g_WB_M1MaxSLPips                 = WB_CFG_DEFAULT_MAX_SL_PIPS;
int    g_WB_M1MaxTradesPerLocalRef     = WB_CFG_DEFAULT_MAX_TRADES_LOCAL_REF;
bool   g_WB_M1RuntimeConfigLoadedFromTerminal = false;

inline string __WB_ConfigSymbolKeyPart()
{
   string sym = InpSymbol;
   if(sym == "")
      sym = _Symbol;
   if(sym == "")
      sym = "DEFAULT";
   return sym;
}

inline string __WB_ConfigGVKey(const string suffix)
{
   return "WaveBot.M1RuntimeConfig." + __WB_ConfigSymbolKeyPart() + "." + suffix;
}

inline int __WB_ConfigNormalizeInt(const int value, const int fallback, const int minimum)
{
   int v = value;
   if(v < minimum)
      v = fallback;
   if(v < minimum)
      v = minimum;
   return v;
}

inline double __WB_ConfigNormalizeDouble(const double value, const double fallback, const double minimum)
{
   double v = value;
   if(v < minimum)
      v = fallback;
   if(v < minimum)
      v = minimum;
   return v;
}

inline void __WB_ConfigNormalizeRuntime()
{
   g_WB_M1MaxTradesPerM15NewSignal = __WB_ConfigNormalizeInt(g_WB_M1MaxTradesPerM15NewSignal,
                                                             WB_CFG_DEFAULT_MAX_TRADES_PER_M15_NEW,
                                                             1);
   g_WB_M1MaxOpenTrades            = __WB_ConfigNormalizeInt(g_WB_M1MaxOpenTrades,
                                                             WB_CFG_DEFAULT_MAX_OPEN_TRADES,
                                                             1);
   g_WB_M1MaxTradesPerLocalRef     = __WB_ConfigNormalizeInt(g_WB_M1MaxTradesPerLocalRef,
                                                             WB_CFG_DEFAULT_MAX_TRADES_LOCAL_REF,
                                                             1);

   g_WB_M1MinSLPips = __WB_ConfigNormalizeDouble(g_WB_M1MinSLPips,
                                                 WB_CFG_DEFAULT_MIN_SL_PIPS,
                                                 0.0);
   g_WB_M1MaxSLPips = __WB_ConfigNormalizeDouble(g_WB_M1MaxSLPips,
                                                 WB_CFG_DEFAULT_MAX_SL_PIPS,
                                                 0.0);

   if(g_WB_M1MaxSLPips <= 0.0)
      g_WB_M1MaxSLPips = WB_CFG_DEFAULT_MAX_SL_PIPS;

   if(g_WB_M1MinSLPips > g_WB_M1MaxSLPips)
   {
      double tmp = g_WB_M1MinSLPips;
      g_WB_M1MinSLPips = g_WB_M1MaxSLPips;
      g_WB_M1MaxSLPips = tmp;
   }
}

inline void __WB_ConfigApplyInputs()
{
   g_WB_M1MaxTradesPerM15NewSignal = InpM1MaxTradesPerM15NewSignal;
   g_WB_M1MaxOpenTrades            = InpM1MaxOpenTrades;
   g_WB_M1MinSLPips                = InpM1MinSLPips;
   g_WB_M1MaxSLPips                = InpM1MaxSLPips;
   g_WB_M1MaxTradesPerLocalRef     = InpM1MaxTradesPerLocalRef;
   g_WB_M1RuntimeConfigLoadedFromTerminal = false;
   __WB_ConfigNormalizeRuntime();
}

inline bool __WB_ConfigLoadInt(const string suffix, int &out_value)
{
   string key = __WB_ConfigGVKey(suffix);
   if(!GlobalVariableCheck(key))
      return false;

   out_value = (int)MathRound(GlobalVariableGet(key));
   return true;
}

inline bool __WB_ConfigLoadDouble(const string suffix, double &out_value)
{
   string key = __WB_ConfigGVKey(suffix);
   if(!GlobalVariableCheck(key))
      return false;

   out_value = GlobalVariableGet(key);
   return true;
}

inline bool __WB_ConfigLoadFromTerminal()
{
   bool loaded = false;

   int vi = 0;
   double vd = 0.0;

   if(__WB_ConfigLoadInt("MaxTradesPerM15NewSignal", vi))
   {
      g_WB_M1MaxTradesPerM15NewSignal = vi;
      loaded = true;
   }
   if(__WB_ConfigLoadInt("MaxOpenTrades", vi))
   {
      g_WB_M1MaxOpenTrades = vi;
      loaded = true;
   }
   if(__WB_ConfigLoadDouble("MinSLPips", vd))
   {
      g_WB_M1MinSLPips = vd;
      loaded = true;
   }
   if(__WB_ConfigLoadDouble("MaxSLPips", vd))
   {
      g_WB_M1MaxSLPips = vd;
      loaded = true;
   }
   if(__WB_ConfigLoadInt("MaxTradesPerLocalRef", vi))
   {
      g_WB_M1MaxTradesPerLocalRef = vi;
      loaded = true;
   }

   __WB_ConfigNormalizeRuntime();
   g_WB_M1RuntimeConfigLoadedFromTerminal = loaded;
   return loaded;
}

inline void __WB_ConfigSaveToTerminal()
{
   __WB_ConfigNormalizeRuntime();

   GlobalVariableSet(__WB_ConfigGVKey("MaxTradesPerM15NewSignal"), (double)g_WB_M1MaxTradesPerM15NewSignal);
   GlobalVariableSet(__WB_ConfigGVKey("MaxOpenTrades"),            (double)g_WB_M1MaxOpenTrades);
   GlobalVariableSet(__WB_ConfigGVKey("MinSLPips"),                g_WB_M1MinSLPips);
   GlobalVariableSet(__WB_ConfigGVKey("MaxSLPips"),                g_WB_M1MaxSLPips);
   GlobalVariableSet(__WB_ConfigGVKey("MaxTradesPerLocalRef"),     (double)g_WB_M1MaxTradesPerLocalRef);
   GlobalVariableSet(__WB_ConfigGVKey("SavedAt"),                  (double)TimeCurrent());
}

inline void WB_ConfigInitialize(const bool save_inputs_to_terminal,
                                const bool load_saved_from_terminal)
{
   __WB_ConfigApplyInputs();

   if(load_saved_from_terminal)
      __WB_ConfigLoadFromTerminal();

   if(save_inputs_to_terminal)
      __WB_ConfigSaveToTerminal();
}

inline int WB_Config_MaxTradesPerM15NewSignal()
{
   return __WB_ConfigNormalizeInt(g_WB_M1MaxTradesPerM15NewSignal,
                                  WB_CFG_DEFAULT_MAX_TRADES_PER_M15_NEW,
                                  1);
}

inline int WB_Config_MaxOpenTrades()
{
   return __WB_ConfigNormalizeInt(g_WB_M1MaxOpenTrades,
                                  WB_CFG_DEFAULT_MAX_OPEN_TRADES,
                                  1);
}

inline double WB_Config_MinSLPips()
{
   return g_WB_M1MinSLPips;
}

inline double WB_Config_MaxSLPips()
{
   return g_WB_M1MaxSLPips;
}

inline int WB_Config_MaxTradesPerLocalRef()
{
   return __WB_ConfigNormalizeInt(g_WB_M1MaxTradesPerLocalRef,
                                  WB_CFG_DEFAULT_MAX_TRADES_LOCAL_REF,
                                  1);
}

inline string WB_Config_SourceText()
{
   return (g_WB_M1RuntimeConfigLoadedFromTerminal ? "terminal-global-from-M15" : "ea-inputs");
}

// ===== Central Multi-Symbol runtime symbol routing =====
// InpSymbol remains the primary/chart symbol. During a multi-symbol pass,
// g_wb_active_symbol is switched to the symbol currently being processed.
// All downstream modules still use the familiar InpSymbol token through the
// macro below, so the original wave/trigger logic does not need to be rewritten.
string g_wb_active_symbol = "";

inline string WB_PrimaryInputSymbol()
{
   string s = InpSymbol;
   if(s == "") s = _Symbol;
   if(s == "") s = "EURUSD";
   return s;
}

inline string WB_ActiveSymbol()
{
   if(g_wb_active_symbol != "")
      return g_wb_active_symbol;
   return WB_PrimaryInputSymbol();
}

inline void WB_SetActiveSymbol(const string sym)
{
   g_wb_active_symbol = sym;
}

inline bool WB_IsPrimaryVisualSymbol()
{
   string a = WB_ActiveSymbol();
   string p = WB_PrimaryInputSymbol();
   return (a == p || a == _Symbol);
}

inline bool WB_RuntimeAllowMarkerRender()
{
   if(!InpDrawOnlyChartSymbol) return true;
   return WB_IsPrimaryVisualSymbol();
}

#define InpSymbol WB_ActiveSymbol()

// ===== Includes (??? ?? Inputs) =====
#include <WaveBot/Utils.mqh>
#include <WaveBot/Data.mqh>
#include <WaveBot/Markers.mqh>
#include <WaveBot/WaveBotLogger.mqh>
#include <WaveBot/WaveBotRiskManager.mqh>
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

// --- M15 hard end-of-scan stop guard ---
bool     g_m15_scan_hard_stopped      = false;
datetime g_m15_scan_hard_stop_time    = 0;
bool     g_m15_master_end_published   = false;

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
   ENUM_TIMEFRAMES chart_tf = (ENUM_TIMEFRAMES)Period();
   if(chart_tf != PERIOD_M1 && chart_tf != PERIOD_M15)
      return;

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
      // M1 final-only output mode: write the final Statement only.
      // CSV diagnostics are disabled in this build to keep scanning fast.
      WBLOG_BeginScheduledOutputWrite();
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

inline bool __WB_ShouldHardStopM15Chart()
{
   return (g_role == WBROLE_MASTER_M15);
}

inline datetime __WB_ResolveM15HardStopBoundary(const datetime requested_stop)
{
   datetime use_stop = requested_stop;
   if(use_stop <= 0)
      use_stop = TimeCurrent();

   // Freeze M15 to the last CLOSED candle. This prevents the live edge of the
   // M15 chart from opening the final-days replay loop after the historical pass
   // reaches today's market boundary.
   datetime last_closed_m15 = iTime(InpSymbol, PERIOD_M15, 1);
   if(last_closed_m15 > 0 && last_closed_m15 < use_stop)
      use_stop = last_closed_m15;

   if(use_stop <= 0)
      use_stop = TimeCurrent();

   return use_stop;
}

inline void __WB_PrimeM15HardStopBoundary(const datetime requested_stop)
{
   if(!__WB_ShouldHardStopM15Chart())
   {
      Trigger_SetM15HardStop(0, false);
      return;
   }

   if(g_m15_scan_hard_stop_time <= 0)
      g_m15_scan_hard_stop_time = __WB_ResolveM15HardStopBoundary(requested_stop);

   if(g_m15_scan_hard_stop_time > 0)
      Trigger_SetM15HardStop(g_m15_scan_hard_stop_time, false);
}

inline void __WB_PublishM15MasterEndOnce(const datetime scan_stop)
{
   if(g_role != WBROLE_MASTER_M15)
      return;

   if(g_m15_master_end_published)
      return;

   datetime use_stop = scan_stop;
   if(use_stop <= 0)
      use_stop = TimeCurrent();

   WB15_MasterEnd(InpSymbol, use_stop);
   g_m15_master_end_published = true;
}

inline void __WB_HardStopM15AtScanEnd(const datetime scan_stop)
{
   if(!__WB_ShouldHardStopM15Chart())
      return;

   datetime use_stop = scan_stop;
   if(g_m15_scan_hard_stop_time > 0)
      use_stop = g_m15_scan_hard_stop_time;
   else
      use_stop = __WB_ResolveM15HardStopBoundary(use_stop);

   if(use_stop <= 0)
      use_stop = TimeCurrent();

   if(g_m15_scan_hard_stopped)
   {
      EventKillTimer();
      return;
   }

   g_m15_scan_hard_stopped   = true;
   g_m15_scan_hard_stop_time = use_stop;

   Trigger_FinalizeM15HardStop(use_stop);
   TriggerStatement_SetBulkScanMode(false);

   // The M15 master must publish its final DONE marker before removing itself so
   // the M1 slave can start/finish its own terminal scan from a stable bridge.
   __WB_PublishM15MasterEndOnce(use_stop);

   if(!__WB_FinalScanOutputCompleted())
      __WB_FlushFinalScanOutputs(use_stop);

   WBLOG_LogParam("M15HardStop", "true", "M15_SCAN_REACHED_END_OF_CHART");
   WBLOG_LogParam("M15HardStopTime", WBLOG_Time(use_stop), "WaveBot.mq5");
   WBLOG_FlushSnapshotFilesIfDirty();
   WBLOG_FlushAllOpenFiles();

   EventKillTimer();

   if(InpDebugPrints)
   {
      Print("[WB-M15-HARD-STOP] Historical M15 scan reached final scan boundary @ ",
            TimeToString(use_stop, TIME_DATE|TIME_SECONDS),
            ". Master DONE published, timer killed, and M15 EA removal requested.");
   }

   // Do not call TesterStop() here: the M15 master may be feeding a separate M1
   // slave chart. ExpertRemove() stops only this chart/EA after final log flush.
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
   // is rebuilt once after the terminal hard stop; CSV diagnostics are disabled.
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

// ============================================================================
// Central Multi-Symbol phase-1 runner
// ============================================================================
#define WBMS_MAX_SYMBOLS 12

string g_wbms_symbols[];
int    g_wbms_count = 0;
string g_wbms_statement_files[];
TriggerStatementSummary g_wbms_summaries[];

// Diagnostics for the central M15->M1 bridge per symbol.
// These counters are written to the combined statement so it is immediately
// clear whether a symbol was actually scanned, whether M15 published events,
// and whether the M1 side had bridge input before evaluating Flip/MajicFlip.
string g_wbms_diag_symbols[];
int    g_wbms_diag_bridge_events[];
int    g_wbms_diag_bridge_starts[];
int    g_wbms_diag_scan_passes[];

inline string __WBMS_Trim(string s)
{
   // StringTrimLeft/Right modify the string by reference and return an int.
   // Keep the operations explicit to avoid implicit int->string conversion warnings.
   StringTrimLeft(s);
   StringTrimRight(s);
   return s;
}

inline bool WBMS_Enabled()
{
   if(!InpEnableCentralMultiSymbol)
      return false;
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Period();
   return (tf == PERIOD_M15 || tf == PERIOD_M1);
}

inline int WBMS_ParseSymbols()
{
   ArrayResize(g_wbms_symbols, 0);
   g_wbms_count = 0;

   string src = InpMultiSymbolList;
   if(src == "") src = WB_PrimaryInputSymbol();

   string parts[];
   int n = StringSplit(src, ',', parts);
   if(n <= 0)
   {
      ArrayResize(g_wbms_symbols, 1);
      g_wbms_symbols[0] = WB_PrimaryInputSymbol();
      g_wbms_count = 1;
      return g_wbms_count;
   }

   for(int i=0; i<n && g_wbms_count<WBMS_MAX_SYMBOLS; ++i)
   {
      string sym = __WBMS_Trim(parts[i]);
      if(sym == "") continue;

      bool dup = false;
      for(int j=0; j<g_wbms_count; ++j)
      {
         if(g_wbms_symbols[j] == sym)
         {
            dup = true;
            break;
         }
      }
      if(dup) continue;

      int pos = g_wbms_count;
      ArrayResize(g_wbms_symbols, pos + 1);
      g_wbms_symbols[pos] = sym;
      g_wbms_count++;
   }

   if(g_wbms_count <= 0)
   {
      ArrayResize(g_wbms_symbols, 1);
      g_wbms_symbols[0] = WB_PrimaryInputSymbol();
      g_wbms_count = 1;
   }

   return g_wbms_count;
}

inline string WBMS_SymbolListText()
{
   string out = "";
   for(int i=0; i<g_wbms_count; ++i)
   {
      if(i>0) out += ",";
      out += g_wbms_symbols[i];
   }
   return out;
}

inline void WBMS_SelectSymbols()
{
   if(g_wbms_count <= 0) WBMS_ParseSymbols();
   for(int i=0; i<g_wbms_count; ++i)
   {
      if(g_wbms_symbols[i] == "") continue;
      SymbolSelect(g_wbms_symbols[i], true);
   }
}

inline bool __WBMS_IsPrimaryVisualSymbolName(const string sym)
{
   string p = WB_PrimaryInputSymbol();
   return (sym == p || sym == _Symbol);
}

inline void WBMS_BuildProcessingOrder(string &ordered[])
{
   ArrayResize(ordered, 0);

   // The scan order is deliberately split:
   //   1) non-visual symbols first in silent preview mode
   //   2) the primary/chart symbol last
   // This prevents the tester chart from visually appearing to restart three
   // times.  Non-primary symbols are still fully scanned and reported; only
   // their chart objects are suppressed.
   int out_count = 0;

   for(int pass=0; pass<2; ++pass)
   {
      const bool want_primary = (pass == 1);

      for(int i=0; i<g_wbms_count; ++i)
      {
         string sym = g_wbms_symbols[i];
         if(sym == "") continue;

         bool is_primary = __WBMS_IsPrimaryVisualSymbolName(sym);
         if(is_primary != want_primary)
            continue;

         bool dup = false;
         for(int j=0; j<out_count; ++j)
         {
            if(ordered[j] == sym)
            {
               dup = true;
               break;
            }
         }
         if(dup) continue;

         ArrayResize(ordered, out_count + 1);
         ordered[out_count] = sym;
         out_count++;
      }
   }

   // Safety fallback: if the primary symbol was not present in the configured
   // list, still keep all configured symbols in their original order.
   if(out_count <= 0)
   {
      for(int k=0; k<g_wbms_count; ++k)
      {
         if(g_wbms_symbols[k] == "") continue;
         ArrayResize(ordered, out_count + 1);
         ordered[out_count] = g_wbms_symbols[k];
         out_count++;
      }
   }
}

inline string WBMS_OrderText(const string &ordered[])
{
   string out = "";
   const int n = ArraySize(ordered);
   for(int i=0; i<n; ++i)
   {
      if(i > 0) out += ",";
      out += ordered[i];
   }
   return out;
}

inline void WBMS_ResetDiagnostics()
{
   ArrayResize(g_wbms_diag_symbols, 0);
   ArrayResize(g_wbms_diag_bridge_events, 0);
   ArrayResize(g_wbms_diag_bridge_starts, 0);
   ArrayResize(g_wbms_diag_scan_passes, 0);
}

inline int __WBMS_FindDiagSymbol(const string sym)
{
   for(int i=0; i<ArraySize(g_wbms_diag_symbols); ++i)
   {
      if(g_wbms_diag_symbols[i] == sym)
         return i;
   }
   return -1;
}

inline void WBMS_StoreDiagnostics(const string sym,
                                  const int bridge_events,
                                  const int bridge_starts)
{
   if(sym == "") return;

   int pos = __WBMS_FindDiagSymbol(sym);
   if(pos < 0)
   {
      pos = ArraySize(g_wbms_diag_symbols);
      ArrayResize(g_wbms_diag_symbols,       pos + 1);
      ArrayResize(g_wbms_diag_bridge_events, pos + 1);
      ArrayResize(g_wbms_diag_bridge_starts, pos + 1);
      ArrayResize(g_wbms_diag_scan_passes,   pos + 1);

      g_wbms_diag_symbols[pos]       = sym;
      g_wbms_diag_bridge_events[pos] = 0;
      g_wbms_diag_bridge_starts[pos] = 0;
      g_wbms_diag_scan_passes[pos]   = 0;
   }

   g_wbms_diag_bridge_events[pos] = bridge_events;
   g_wbms_diag_bridge_starts[pos] = bridge_starts;
   g_wbms_diag_scan_passes[pos]++;
}

inline int WBMS_DiagBridgeEvents(const string sym)
{
   int pos = __WBMS_FindDiagSymbol(sym);
   if(pos < 0) return 0;
   return g_wbms_diag_bridge_events[pos];
}

inline int WBMS_DiagBridgeStarts(const string sym)
{
   int pos = __WBMS_FindDiagSymbol(sym);
   if(pos < 0) return 0;
   return g_wbms_diag_bridge_starts[pos];
}

inline int WBMS_DiagScanPasses(const string sym)
{
   int pos = __WBMS_FindDiagSymbol(sym);
   if(pos < 0) return 0;
   return g_wbms_diag_scan_passes[pos];
}

// Raw trigger storage for synchronized central execution.
// Each symbol is still scanned with its own isolated WaveBot state, but the
// raw TriggerSLTP records are stored and executed only after every configured
// symbol has completed its scan.  This is the point where account-wide rules
// such as MaxOpenTradesTotal=1 become meaningful across EURUSD/GBPUSD/AUDUSD.
struct WBMS_RawTriggerBucket
{
   bool              valid;
   string            symbol;
   TriggerSLTPRecord records[];
   TriggerM15SignalGateEvent gate_events[];
   int               gate_seq;
   datetime          scan_stop;
};

struct WBMS_GlobalTriggerCandidate
{
   bool              valid;
   string            symbol;
   int               bucket_index;
   int               record_index;
   TriggerSLTPRecord rec;
   TriggerStatementTrade trade;
   datetime          exit_time;
   bool              accepted;
   int               decision_reason;
};

struct WBMS_AcceptedPortfolioTrade
{
   bool              valid;
   string            symbol;
   datetime          entry_time;
   datetime          exit_time;
   double            result_r;
   double            pnl_money;
   double            balance_after;
   double            peak_after;
   double            dd_money_after;
   double            dd_pct_after;
};

struct WBMS_CapCounter
{
   string key;
   int    count;
};

WBMS_RawTriggerBucket g_wbms_raw_buckets[];
WBMS_AcceptedPortfolioTrade g_wbms_portfolio_trades[];
double g_wbms_portfolio_initial_balance = 0.0;
double g_wbms_portfolio_final_balance   = 0.0;
double g_wbms_portfolio_peak_balance    = 0.0;
double g_wbms_portfolio_max_dd_money    = 0.0;
double g_wbms_portfolio_max_dd_pct      = 0.0;
int    g_wbms_central_raw_candidates    = 0;
int    g_wbms_central_accepted          = 0;
int    g_wbms_central_skipped_open      = 0;
int    g_wbms_central_skipped_m15_cap   = 0;
int    g_wbms_central_skipped_local_cap = 0;
int    g_wbms_interleaved_steps         = 0;
datetime g_wbms_interleaved_first_time  = 0;
datetime g_wbms_interleaved_last_time   = 0;

inline void WBMS_ResetRawBuckets()
{
   ArrayResize(g_wbms_raw_buckets, 0);
   ArrayResize(g_wbms_portfolio_trades, 0);
   g_wbms_portfolio_initial_balance = 0.0;
   g_wbms_portfolio_final_balance   = 0.0;
   g_wbms_portfolio_peak_balance    = 0.0;
   g_wbms_portfolio_max_dd_money    = 0.0;
   g_wbms_portfolio_max_dd_pct      = 0.0;
   g_wbms_central_raw_candidates    = 0;
   g_wbms_central_accepted          = 0;
   g_wbms_central_skipped_open      = 0;
   g_wbms_central_skipped_m15_cap   = 0;
   g_wbms_central_skipped_local_cap = 0;
   g_wbms_interleaved_steps         = 0;
   g_wbms_interleaved_first_time    = 0;
   g_wbms_interleaved_last_time     = 0;
}

inline int WBMS_FindRawBucket(const string sym)
{
   for(int i=0; i<ArraySize(g_wbms_raw_buckets); ++i)
   {
      if(g_wbms_raw_buckets[i].valid && g_wbms_raw_buckets[i].symbol == sym)
         return i;
   }
   return -1;
}

inline int WBMS_EnsureRawBucket(const string sym)
{
   int pos = WBMS_FindRawBucket(sym);
   if(pos >= 0)
      return pos;

   pos = ArraySize(g_wbms_raw_buckets);
   ArrayResize(g_wbms_raw_buckets, pos + 1);
   g_wbms_raw_buckets[pos].valid = true;
   g_wbms_raw_buckets[pos].symbol = sym;
   g_wbms_raw_buckets[pos].gate_seq = 0;
   g_wbms_raw_buckets[pos].scan_stop = 0;
   ArrayResize(g_wbms_raw_buckets[pos].records, 0);
   ArrayResize(g_wbms_raw_buckets[pos].gate_events, 0);
   return pos;
}

inline void WBMS_StoreCurrentRawRecords(const string sym, const datetime scan_stop)
{
   int pos = WBMS_EnsureRawBucket(sym);
   g_wbms_raw_buckets[pos].scan_stop = scan_stop;

   TriggerSLTPRecord tmp[];
   int n = TriggerSLTP_RecordsExport(tmp);
   ArrayResize(g_wbms_raw_buckets[pos].records, n);
   for(int i=0; i<n; ++i)
      g_wbms_raw_buckets[pos].records[i] = tmp[i];

   TriggerM15SignalGateEvent ge[];
   int seq = 0;
   int gn = TriggerM15SignalGate_EventsExport(ge, seq);
   ArrayResize(g_wbms_raw_buckets[pos].gate_events, gn);
   for(int j=0; j<gn; ++j)
      g_wbms_raw_buckets[pos].gate_events[j] = ge[j];
   g_wbms_raw_buckets[pos].gate_seq = seq;
}

inline int WBMS_SymbolOrderIndex(const string sym)
{
   for(int i=0; i<g_wbms_count; ++i)
      if(g_wbms_symbols[i] == sym)
         return i;
   return 100000;
}

inline int WBMS_CompareGlobalCandidate(const WBMS_GlobalTriggerCandidate &a,
                                       const WBMS_GlobalTriggerCandidate &b)
{
   if(a.rec.hit_time < b.rec.hit_time) return -1;
   if(a.rec.hit_time > b.rec.hit_time) return 1;

   if(a.rec.src_time < b.rec.src_time) return -1;
   if(a.rec.src_time > b.rec.src_time) return 1;

   int ao = WBMS_SymbolOrderIndex(a.symbol);
   int bo = WBMS_SymbolOrderIndex(b.symbol);
   if(ao < bo) return -1;
   if(ao > bo) return 1;

   if(a.rec.serial < b.rec.serial) return -1;
   if(a.rec.serial > b.rec.serial) return 1;

   if(a.rec.type_id < b.rec.type_id) return -1;
   if(a.rec.type_id > b.rec.type_id) return 1;

   return 0;
}

inline void WBMS_SortGlobalCandidates(WBMS_GlobalTriggerCandidate &items[])
{
   int n = ArraySize(items);
   if(n <= 1) return;

   for(int i=0; i<n-1; ++i)
   {
      int best = i;
      for(int j=i+1; j<n; ++j)
      {
         if(WBMS_CompareGlobalCandidate(items[j], items[best]) < 0)
            best = j;
      }
      if(best != i)
      {
         WBMS_GlobalTriggerCandidate tmp = items[i];
         items[i] = items[best];
         items[best] = tmp;
      }
   }
}

inline bool WBMS_EvaluateCandidateTrade(const string sym,
                                        const ENUM_TIMEFRAMES tf,
                                        const datetime scan_to,
                                        const TriggerSLTPRecord &rec,
                                        TriggerStatementTrade &tr)
{
   int tfsec = PeriodSeconds(tf);
   if(tfsec <= 0) tfsec = 60;

   datetime load_from = rec.hit_time - (datetime)(tfsec * 2);
   if(load_from < 0) load_from = 0;

   datetime use_to = scan_to;
   if(use_to <= 0) use_to = TimeCurrent();

   MqlRates rates[];
   if(!__TRGSTM_LoadRates(sym, tf, load_from, use_to, rates))
   {
      __TRGSTM_ClearTrade(tr);
      tr.valid = true;
      tr.rec = rec;
      tr.result_status = TRGSTMT_RESULT_OPEN;
      tr.exit_time = use_to;
      tr.note = "NO_RATE_DATA_FOR_CENTRAL_EVAL";
      return false;
   }

   bool ok = __TRGSTM_EvaluateTrade(rec, rates, ArraySize(rates), use_to, tr);
   if(!ok)
   {
      tr.valid = true;
      tr.rec = rec;
      tr.result_status = TRGSTMT_RESULT_OPEN;
      tr.exit_time = use_to;
      tr.note = __TRGSTM_AppendNote(tr.note, "CENTRAL_EVAL_FALLBACK_OPEN");
   }

   if(tr.exit_time <= 0)
      tr.exit_time = use_to;
   return ok;
}

inline datetime WBMS_EvaluateCandidateExit(const string sym,
                                           const ENUM_TIMEFRAMES tf,
                                           const datetime scan_to,
                                           const TriggerSLTPRecord &rec)
{
   TriggerStatementTrade tr;
   WBMS_EvaluateCandidateTrade(sym, tf, scan_to, rec, tr);
   if(tr.result_status == TRGSTMT_RESULT_OPEN || tr.exit_time <= 0)
   {
      datetime use_to = scan_to;
      if(use_to <= 0) use_to = TimeCurrent();
      return use_to;
   }
   return tr.exit_time;
}

inline string WBMS_M15AcceptedCapKey(const WBMS_GlobalTriggerCandidate &c)
{
   return c.symbol + "|CTX=" + IntegerToString(c.rec.log_context_id)
                   + "|ZONE=" + IntegerToString(c.rec.log_zone_id);
}

inline string WBMS_LocalAcceptedCapKey(const WBMS_GlobalTriggerCandidate &c)
{
   return WBMS_M15AcceptedCapKey(c)
        + "|M1WIN=" + IntegerToString(c.rec.log_m1_window_id);
}

inline int WBMS_CounterGet(const WBMS_CapCounter &items[], const string key)
{
   for(int i=0; i<ArraySize(items); ++i)
      if(items[i].key == key)
         return items[i].count;
   return 0;
}

inline void WBMS_CounterIncrement(WBMS_CapCounter &items[], const string key)
{
   for(int i=0; i<ArraySize(items); ++i)
   {
      if(items[i].key == key)
      {
         items[i].count++;
         return;
      }
   }

   int n = ArraySize(items);
   ArrayResize(items, n + 1);
   items[n].key = key;
   items[n].count = 1;
}

inline int WBMS_ComparePortfolioTradeExit(const WBMS_AcceptedPortfolioTrade &a,
                                          const WBMS_AcceptedPortfolioTrade &b)
{
   if(a.exit_time < b.exit_time) return -1;
   if(a.exit_time > b.exit_time) return 1;
   if(a.entry_time < b.entry_time) return -1;
   if(a.entry_time > b.entry_time) return 1;
   int ao = WBMS_SymbolOrderIndex(a.symbol);
   int bo = WBMS_SymbolOrderIndex(b.symbol);
   if(ao < bo) return -1;
   if(ao > bo) return 1;
   return 0;
}

inline void WBMS_SortPortfolioTradesByExit(WBMS_AcceptedPortfolioTrade &items[])
{
   int n = ArraySize(items);
   for(int i=0; i<n-1; ++i)
   {
      int best = i;
      for(int j=i+1; j<n; ++j)
         if(WBMS_ComparePortfolioTradeExit(items[j], items[best]) < 0)
            best = j;
      if(best != i)
      {
         WBMS_AcceptedPortfolioTrade tmp = items[i];
         items[i] = items[best];
         items[best] = tmp;
      }
   }
}

inline void WBMS_RecalculatePortfolioChronologicalDrawdown()
{
   const double initial_capital = InpTriggerStatementInitialCapital;
   const double risk_money = initial_capital * (InpTriggerStatementRiskPercent / 100.0);

   g_wbms_portfolio_initial_balance = initial_capital;
   g_wbms_portfolio_final_balance   = initial_capital;
   g_wbms_portfolio_peak_balance    = initial_capital;
   g_wbms_portfolio_max_dd_money    = 0.0;
   g_wbms_portfolio_max_dd_pct      = 0.0;

   WBMS_SortPortfolioTradesByExit(g_wbms_portfolio_trades);

   double balance = initial_capital;
   double peak    = initial_capital;

   for(int i=0; i<ArraySize(g_wbms_portfolio_trades); ++i)
   {
      if(!g_wbms_portfolio_trades[i].valid) continue;

      balance += g_wbms_portfolio_trades[i].pnl_money;
      if(balance > peak)
         peak = balance;

      double dd_money = peak - balance;
      double dd_pct   = (peak > 0.0 ? (dd_money / peak) * 100.0 : 0.0);

      g_wbms_portfolio_trades[i].balance_after  = balance;
      g_wbms_portfolio_trades[i].peak_after     = peak;
      g_wbms_portfolio_trades[i].dd_money_after = dd_money;
      g_wbms_portfolio_trades[i].dd_pct_after   = dd_pct;

      if(dd_money > g_wbms_portfolio_max_dd_money)
         g_wbms_portfolio_max_dd_money = dd_money;
      if(dd_pct > g_wbms_portfolio_max_dd_pct)
         g_wbms_portfolio_max_dd_pct = dd_pct;
   }

   g_wbms_portfolio_final_balance = balance;
   g_wbms_portfolio_peak_balance  = peak;
}

inline void WBMS_BuildCentralExecutionGate(const datetime scan_from,
                                           const datetime scan_to)
{
   TriggerStatement_CentralGateReset();
   ArrayResize(g_wbms_portfolio_trades, 0);

   WBMS_GlobalTriggerCandidate candidates[];
   ArrayResize(candidates, 0);

   for(int b=0; b<ArraySize(g_wbms_raw_buckets); ++b)
   {
      if(!g_wbms_raw_buckets[b].valid) continue;

      string sym = g_wbms_raw_buckets[b].symbol;
      int rn = ArraySize(g_wbms_raw_buckets[b].records);
      for(int r=0; r<rn; ++r)
      {
         TriggerSLTPRecord rec = g_wbms_raw_buckets[b].records[r];
         if(!rec.valid) continue;
         if(scan_from > 0 && rec.hit_time < scan_from) continue;
         if(scan_to > 0 && rec.hit_time > scan_to) continue;

         int pos = ArraySize(candidates);
         ArrayResize(candidates, pos + 1);
         candidates[pos].valid = true;
         candidates[pos].symbol = sym;
         candidates[pos].bucket_index = b;
         candidates[pos].record_index = r;
         candidates[pos].rec = rec;
         WBMS_EvaluateCandidateTrade(sym, PERIOD_M1, scan_to, rec, candidates[pos].trade);
         candidates[pos].exit_time = candidates[pos].trade.exit_time;
         if(candidates[pos].exit_time <= 0)
            candidates[pos].exit_time = (scan_to > 0 ? scan_to : TimeCurrent());
         candidates[pos].accepted = false;
         candidates[pos].decision_reason = TRGSTMT_CENTRAL_DECISION_MISSING;
      }
   }

   WBMS_SortGlobalCandidates(candidates);

   g_wbms_central_raw_candidates    = ArraySize(candidates);
   g_wbms_central_accepted          = 0;
   g_wbms_central_skipped_open      = 0;
   g_wbms_central_skipped_m15_cap   = 0;
   g_wbms_central_skipped_local_cap = 0;
   g_wbms_interleaved_steps         = 0;
   g_wbms_interleaved_first_time    = (ArraySize(candidates) > 0 ? candidates[0].rec.hit_time : 0);
   g_wbms_interleaved_last_time     = (ArraySize(candidates) > 0 ? candidates[ArraySize(candidates)-1].rec.hit_time : 0);

   int max_open = WB_Config_MaxOpenTrades();
   if(max_open <= 0) max_open = 1;

   int max_m15 = WB_Config_MaxTradesPerM15NewSignal();
   if(max_m15 <= 0) max_m15 = 1;

   int max_local = WB_Config_MaxTradesPerLocalRef();
   if(max_local <= 0) max_local = 1;

   WBMS_CapCounter accepted_m15_counts[];
   WBMS_CapCounter accepted_local_counts[];
   ArrayResize(accepted_m15_counts, 0);
   ArrayResize(accepted_local_counts, 0);

   // Interleaved central timeline:
   // candidates from every configured symbol are already sorted by real M1 hit_time.
   // This loop is the account-wide minute/event clock.  It is deliberately outside
   // the per-symbol scanner, so max-open and trade-cap decisions are made exactly
   // once in chronological order across EURUSD/GBPUSD/AUDUSD.
   datetime current_clock = 0;

   for(int i=0; i<ArraySize(candidates); ++i)
   {
      datetime t = candidates[i].rec.hit_time;
      if(t != current_clock)
      {
         current_clock = t;
         g_wbms_interleaved_steps++;
      }

      int open_count = 0;
      for(int j=0; j<i; ++j)
      {
         if(!candidates[j].accepted) continue;
         if(candidates[j].rec.hit_time <= 0 || candidates[j].rec.hit_time > t) continue;

         // If a previous trade exits exactly on this trigger bar, it is treated
         // as closed before the next candidate on that same M1 timestamp.
         if(candidates[j].exit_time <= 0 || candidates[j].exit_time > t)
            open_count++;
      }

      string m15_key   = WBMS_M15AcceptedCapKey(candidates[i]);
      string local_key = WBMS_LocalAcceptedCapKey(candidates[i]);
      int m15_used     = WBMS_CounterGet(accepted_m15_counts, m15_key);
      int local_used   = WBMS_CounterGet(accepted_local_counts, local_key);

      bool accept = true;
      int reason  = TRGSTMT_CENTRAL_ALLOW;

      if(open_count >= max_open)
      {
         accept = false;
         reason = TRGSTMT_CENTRAL_BLOCK_MAX_OPEN;
         g_wbms_central_skipped_open++;
      }
      else if(m15_used >= max_m15)
      {
         accept = false;
         reason = TRGSTMT_CENTRAL_BLOCK_M15_CAP;
         g_wbms_central_skipped_m15_cap++;
      }
      else if(local_used >= max_local)
      {
         accept = false;
         reason = TRGSTMT_CENTRAL_BLOCK_LOCAL_REF_CAP;
         g_wbms_central_skipped_local_cap++;
      }

      candidates[i].accepted       = accept;
      candidates[i].decision_reason = reason;

      if(accept)
      {
         WBMS_CounterIncrement(accepted_m15_counts, m15_key);
         WBMS_CounterIncrement(accepted_local_counts, local_key);
         g_wbms_central_accepted++;

         int ppos = ArraySize(g_wbms_portfolio_trades);
         ArrayResize(g_wbms_portfolio_trades, ppos + 1);
         g_wbms_portfolio_trades[ppos].valid      = true;
         g_wbms_portfolio_trades[ppos].symbol     = candidates[i].symbol;
         g_wbms_portfolio_trades[ppos].entry_time = candidates[i].rec.hit_time;
         g_wbms_portfolio_trades[ppos].exit_time  = candidates[i].exit_time;
         g_wbms_portfolio_trades[ppos].result_r   = __TRGSTM_EffectiveR(candidates[i].trade);
         g_wbms_portfolio_trades[ppos].pnl_money  = __TRGSTM_EffectiveMoneyByRisk(candidates[i].trade,
                                                InpTriggerStatementInitialCapital * (InpTriggerStatementRiskPercent / 100.0));
         g_wbms_portfolio_trades[ppos].balance_after  = 0.0;
         g_wbms_portfolio_trades[ppos].peak_after     = 0.0;
         g_wbms_portfolio_trades[ppos].dd_money_after = 0.0;
         g_wbms_portfolio_trades[ppos].dd_pct_after   = 0.0;
      }

      TriggerStatement_CentralGateAddDecisionEx(candidates[i].rec, accept, reason);
   }

   WBMS_RecalculatePortfolioChronologicalDrawdown();
   TriggerStatement_CentralGateSetEnabled(true);

   if(InpDebugPrints)
      Print("[WBMS-INTERLEAVED-GATE] Chronological multi-symbol execution timeline built. Raw=",
            g_wbms_central_raw_candidates,
            " | accepted=", g_wbms_central_accepted,
            " | skipped_open=", g_wbms_central_skipped_open,
            " | skipped_m15_cap=", g_wbms_central_skipped_m15_cap,
            " | skipped_local_cap=", g_wbms_central_skipped_local_cap,
            " | timeline_steps=", g_wbms_interleaved_steps);
}

inline void WBMS_WriteDeferredSymbolStatements(const datetime scan_from,
                                               const datetime scan_to)
{
   ArrayResize(g_wbms_statement_files, 0);
   ArrayResize(g_wbms_summaries, 0);

   for(int order_i=0; order_i<g_wbms_count; ++order_i)
   {
      string sym = g_wbms_symbols[order_i];
      int b = WBMS_FindRawBucket(sym);
      if(b < 0) continue;

      WB_SetActiveSymbol(sym);
      TriggerSLTP_RecordsImport(g_wbms_raw_buckets[b].records);
      TriggerM15SignalGate_EventsImport(g_wbms_raw_buckets[b].gate_events,
                                        g_wbms_raw_buckets[b].gate_seq);

      string detail_tag = InpTriggerStatementFileTag + "_" + sym;
      TriggerStatement_WriteTextReport(sym,
                                       PERIOD_M1,
                                       scan_from,
                                       g_wbms_raw_buckets[b].scan_stop,
                                       InpTriggerStatementInitialCapital,
                                       InpTriggerStatementRiskPercent,
                                       detail_tag);

      int fpos = ArraySize(g_wbms_statement_files);
      ArrayResize(g_wbms_statement_files, fpos + 1);
      g_wbms_statement_files[fpos] = TriggerStatement_LastFileName();

      TriggerStatementSummary sum;
      TriggerStatementSummary_Clear(sum);
      if(TriggerStatement_LastSummary(sum))
      {
         int spos = ArraySize(g_wbms_summaries);
         ArrayResize(g_wbms_summaries, spos + 1);
         g_wbms_summaries[spos] = sum;
      }
   }

   WB_SetActiveSymbol(WB_PrimaryInputSymbol());
}

inline int WBMS_FindSummaryIndex(const string sym)
{
   for(int i=0; i<ArraySize(g_wbms_summaries); ++i)
   {
      if(g_wbms_summaries[i].valid && g_wbms_summaries[i].symbol == sym)
         return i;
   }
   return -1;
}

inline string WBMS_FindStatementFile(const string sym)
{
   for(int i=0; i<ArraySize(g_wbms_statement_files); ++i)
   {
      string f = g_wbms_statement_files[i];
      if(f == "") continue;

      if(StringFind(f, "_" + sym + "_") >= 0 || StringFind(f, sym) >= 0)
         return f;
   }
   return "";
}

inline void __WBMS_ResetCoreForSymbol(const bool m1_final_only_output)
{
   Markers_SetNamespace("MAJ");
   Markers_SetPreviewMode(false);
   __WB_ResetMinorWorldGlobals();
   Trigger_ResetGlobals();
   TriggerStatement_ResetGlobals();
   M15NewMarker_ResetGlobals();
   TriggerStatement_SetFinalOnlyOutput(m1_final_only_output);
   TriggerStatement_SetBulkScanMode(false);
   Trigger_SetM1HardStop(0, false);
   Trigger_SetM15HardStop(0, false);
}

inline datetime __WBMS_ResolveSymbolHardStop(const string sym,
                                             const ENUM_TIMEFRAMES tf,
                                             const datetime requested_stop)
{
   datetime use_stop = requested_stop;
   if(use_stop <= 0) use_stop = TimeCurrent();

   datetime last_closed = iTime(sym, tf, 1);
   if(last_closed > 0 && last_closed < use_stop)
      use_stop = last_closed;

   return use_stop;
}

inline void __WBMS_RunOneSymbolWavePass(const string sym,
                                        const ENUM_TIMEFRAMES tf,
                                        const datetime start,
                                        const datetime stop)
{
   BootOutcome boot = Bootstrap_RaceDetect(sym, tf, start, stop);

   Direction mode_for_run = InpDirection;
   datetime  resume_from  = start;

   if(boot.ok)
   {
      mode_for_run = boot.mode;
      resume_from = boot.complete_time + PeriodSeconds(tf);

      if(InpDebugPrints)
         Print("[WBMS-BOOT] Symbol=", sym,
               " | Winner=", (mode_for_run==DIR_UP?"UP":"DOWN"),
               " | first pair @ ", TimeToString(boot.complete_time, TIME_DATE|TIME_SECONDS),
               " | resume_from=", TimeToString(resume_from, TIME_DATE|TIME_SECONDS));
   }
   else if(InpDebugPrints)
   {
      Print("[WBMS-BOOT] Symbol=", sym, " | no completed pair. Fallback to input direction.");
   }

   if(mode_for_run==DIR_UP)
      API_RunScanSequential_W2W3_Hunter(sym, tf, resume_from, stop);
   else
      API_Down_RunScanSequential_W2W3_Hunter(sym, tf, resume_from, stop);
}


inline string __WBMS_EnsureCentralReasonToken(const string in_line, const string reason)
{
   string out = in_line;
   if(reason == "")
      return out;

   if(StringFind(out, " | CentralReason=") < 0)
   {
      int pos = StringFind(out, " | WouldHave=");
      if(pos >= 0)
      {
         string left  = StringSubstr(out, 0, pos);
         string right = StringSubstr(out, pos);
         out = left + " | CentralReason=" + reason + right;
      }
      else
      {
         out += " | CentralReason=" + reason;
      }
   }
   return out;
}

inline string __WBMS_NormalizeEmbeddedDetailLine(const string in_line)
{
   string out = in_line;

   // The combined MULTI statement embeds the already-written per-symbol detail
   // files.  This normalizer is intentionally output-only: it never changes
   // trigger detection, candle scanning, bridge publication, SL/TP, or execution.
   // It only prevents stale/legacy detail lines from showing
   // SkipReason=ONE_OPEN_TRADE_ALREADY_OPEN when the actual central reason was
   // M15-cap, local-ref-cap, or another central multi-symbol decision.
   string reason = "";
   if(StringFind(out, "CENTRAL_MULTI_SYMBOL_LOCAL_REF_CAP_BLOCK") >= 0)
      reason = "CENTRAL_MULTI_SYMBOL_LOCAL_REF_CAP_BLOCK";
   else if(StringFind(out, "CENTRAL_MULTI_SYMBOL_M15_NEW_CAP_BLOCK") >= 0)
      reason = "CENTRAL_MULTI_SYMBOL_M15_NEW_CAP_BLOCK";
   else if(StringFind(out, "CENTRAL_MULTI_SYMBOL_ONE_OPEN_BLOCK") >= 0)
      reason = "CENTRAL_MULTI_SYMBOL_ONE_OPEN_BLOCK";
   else if(StringFind(out, "CENTRAL_MULTI_SYMBOL_DECISION_MISSING") >= 0)
      reason = "CENTRAL_MULTI_SYMBOL_DECISION_MISSING";

   if(reason == "")
      return out;

   if(StringFind(out, "SkipReason=") >= 0)
   {
      StringReplace(out, "SkipReason=ONE_OPEN_TRADE_ALREADY_OPEN",          "SkipReason=" + reason);
      StringReplace(out, "SkipReason=CENTRAL_MULTI_SYMBOL_ONE_OPEN_BLOCK",  "SkipReason=" + reason);
      StringReplace(out, "SkipReason=CENTRAL_MULTI_SYMBOL_M15_NEW_CAP_BLOCK", "SkipReason=" + reason);
      StringReplace(out, "SkipReason=CENTRAL_MULTI_SYMBOL_LOCAL_REF_CAP_BLOCK", "SkipReason=" + reason);
      StringReplace(out, "SkipReason=CENTRAL_MULTI_SYMBOL_DECISION_MISSING", "SkipReason=" + reason);
      out = __WBMS_EnsureCentralReasonToken(out, reason);
   }

   return out;
}

inline void __WBMS_WriteCombinedStatement(const datetime scan_from,
                                          const datetime scan_to)
{
   if((ENUM_TIMEFRAMES)Period() != PERIOD_M1)
      return;
   if(!InpEnableTriggerStatement)
      return;

   string filename = InpTriggerStatementFileTag + "_MULTI_" + __TRGSTM_TimeframeTag(PERIOD_M1) + ".txt";
   int handle = FileOpen(filename, FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_UNICODE|FILE_SHARE_READ);
   if(handle == INVALID_HANDLE)
   {
      if(InpDebugPrints)
         Print("[WBMS-STATEMENT] FileOpen failed | file=", filename, " | error=", GetLastError());
      return;
   }

   int total_raw=0, total_exec=0, total_ignored=0, total_closed=0, total_open=0, total_wins=0, total_losses=0;
   double total_gross_profit=0.0, total_gross_loss=0.0, total_net=0.0, max_dd_money=0.0, max_dd_pct=0.0;

   for(int i=0; i<ArraySize(g_wbms_summaries); ++i)
   {
      if(!g_wbms_summaries[i].valid) continue;
      total_raw     += g_wbms_summaries[i].raw_valid_triggers;
      total_exec    += g_wbms_summaries[i].executed_trades;
      total_ignored += g_wbms_summaries[i].ignored_valid_triggers;
      total_closed  += g_wbms_summaries[i].closed_trades;
      total_open    += g_wbms_summaries[i].open_trades;
      total_wins    += g_wbms_summaries[i].wins;
      total_losses  += g_wbms_summaries[i].losses;
      total_gross_profit += g_wbms_summaries[i].gross_profit;
      total_gross_loss   += g_wbms_summaries[i].gross_loss;
      total_net          += g_wbms_summaries[i].net_profit;
      if(g_wbms_summaries[i].max_drawdown_money > max_dd_money)
         max_dd_money = g_wbms_summaries[i].max_drawdown_money;
      if(g_wbms_summaries[i].max_drawdown_pct > max_dd_pct)
         max_dd_pct = g_wbms_summaries[i].max_drawdown_pct;
   }

   double win_rate = 0.0;
   if(total_closed > 0)
      win_rate = ((double)total_wins / (double)total_closed) * 100.0;

   double pf = 0.0;
   if(total_gross_loss > 0.0)
      pf = total_gross_profit / total_gross_loss;

   __TRGSTM_WriteLine(handle, "WaveBot Central Multi-Symbol Statement");
   __TRGSTM_WriteLine(handle, "============================================================");
   __TRGSTM_WriteLine(handle, "Generated At           : " + __TRGSTM_SafeTime(TimeCurrent()));
   __TRGSTM_WriteLine(handle, "Symbols                : " + WBMS_SymbolListText());
   __TRGSTM_WriteLine(handle, "Primary Visual Symbol  : " + WB_PrimaryInputSymbol());
   __TRGSTM_WriteLine(handle, "Scan From              : " + __TRGSTM_SafeTime(scan_from));
   __TRGSTM_WriteLine(handle, "Scan To                : " + __TRGSTM_SafeTime(scan_to));
   __TRGSTM_WriteLine(handle, "Central Risk Manager   : WaveBotRiskManager.mqh | max open total=" + IntegerToString(WB_Config_MaxOpenTrades()) + " | one open WaveBot trade account-wide by default");
   __TRGSTM_WriteLine(handle, "Interleaved Engine     : ENABLED | central M1 trigger/execution timeline is merged chronologically across all configured symbols");
   __TRGSTM_WriteLine(handle, "Statement Write Policy : deferred until every configured symbol has completed its M1 scan");
   __TRGSTM_WriteLine(handle, "Cap Accounting Policy  : max " + IntegerToString(WB_Config_MaxTradesPerM15NewSignal()) + " per M15 NEW and max " + IntegerToString(WB_Config_MaxTradesPerLocalRef()) + " per local M1 reference are counted only after central-gate acceptance");
   __TRGSTM_WriteLine(handle, "Performance Guard      : no timer backfill/rescan after hard stop; primary chart symbol remains the only visual renderer");
   __TRGSTM_WriteLine(handle, "Visual Pass Policy     : only primary/chart symbol renders markers; non-primary symbols are scanned in preview mode but still publish M15->M1 bridge events");
   __TRGSTM_WriteLine(handle, "Gooz Baghali           : left as in this backup; no reactivation added by multi-symbol layer.");
   __TRGSTM_WriteLine(handle, "");

   __TRGSTM_WriteLine(handle, "MAIN SUMMARY - ALL SYMBOLS");
   __TRGSTM_WriteLine(handle, "------------------------------------------------------------");
   __TRGSTM_WriteLine(handle, "Raw Valid Triggers     : " + IntegerToString(total_raw));
   __TRGSTM_WriteLine(handle, "Executed Trades        : " + IntegerToString(total_exec));
   __TRGSTM_WriteLine(handle, "Ignored Valid Triggers : " + IntegerToString(total_ignored));
   __TRGSTM_WriteLine(handle, "Closed / Open Trades   : " + IntegerToString(total_closed) + " / " + IntegerToString(total_open));
   __TRGSTM_WriteLine(handle, "Wins / Losses          : " + IntegerToString(total_wins) + " / " + IntegerToString(total_losses));
   __TRGSTM_WriteLine(handle, "Win Rate               : " + __TRGSTM_Pct(win_rate));
   __TRGSTM_WriteLine(handle, "Gross Profit           : " + __TRGSTM_Money(total_gross_profit));
   __TRGSTM_WriteLine(handle, "Gross Loss             : " + __TRGSTM_Money(total_gross_loss));
   __TRGSTM_WriteLine(handle, "Net Profit             : " + __TRGSTM_Money(total_net));
   __TRGSTM_WriteLine(handle, "Profit Factor          : " + DoubleToString(pf, 2));
   __TRGSTM_WriteLine(handle, "Portfolio Chrono DD    : " + __TRGSTM_Money(g_wbms_portfolio_max_dd_money) + " | " + __TRGSTM_Pct(g_wbms_portfolio_max_dd_pct) + " (accepted central trades sorted by exit time)");
   __TRGSTM_WriteLine(handle, "Portfolio Balance      : " + __TRGSTM_Money(g_wbms_portfolio_initial_balance) + " -> " + __TRGSTM_Money(g_wbms_portfolio_final_balance) + " | Peak=" + __TRGSTM_Money(g_wbms_portfolio_peak_balance));
   __TRGSTM_WriteLine(handle, "Symbol-Block Max DD    : " + __TRGSTM_Money(max_dd_money) + " | " + __TRGSTM_Pct(max_dd_pct) + " (largest individual symbol block)");
   __TRGSTM_WriteLine(handle, "Central Raw Candidates : " + IntegerToString(g_wbms_central_raw_candidates));
   __TRGSTM_WriteLine(handle, "Central Accepted       : " + IntegerToString(g_wbms_central_accepted));
   __TRGSTM_WriteLine(handle, "Central Skipped Open   : " + IntegerToString(g_wbms_central_skipped_open));
   __TRGSTM_WriteLine(handle, "Central Skipped M15Cap : " + IntegerToString(g_wbms_central_skipped_m15_cap));
   __TRGSTM_WriteLine(handle, "Central Skipped RefCap : " + IntegerToString(g_wbms_central_skipped_local_cap));
   __TRGSTM_WriteLine(handle, "Interleaved Steps      : " + IntegerToString(g_wbms_interleaved_steps)
                                      + " | First=" + __TRGSTM_SafeTime(g_wbms_interleaved_first_time)
                                      + " | Last=" + __TRGSTM_SafeTime(g_wbms_interleaved_last_time));
   __TRGSTM_WriteLine(handle, "");

   for(int order_i=0; order_i<g_wbms_count; ++order_i)
   {
      string sym_order = g_wbms_symbols[order_i];
      int si = WBMS_FindSummaryIndex(sym_order);
      if(si < 0) continue;

      __TRGSTM_WriteLine(handle, "SUMMARY BLOCK - " + g_wbms_summaries[si].symbol);
      __TRGSTM_WriteLine(handle, "------------------------------------------------------------");
      __TRGSTM_WriteLine(handle, "Raw Valid Triggers     : " + IntegerToString(g_wbms_summaries[si].raw_valid_triggers));
      __TRGSTM_WriteLine(handle, "Executed Trades        : " + IntegerToString(g_wbms_summaries[si].executed_trades));
      __TRGSTM_WriteLine(handle, "Ignored Valid Triggers : " + IntegerToString(g_wbms_summaries[si].ignored_valid_triggers));
      __TRGSTM_WriteLine(handle, "Closed / Open Trades   : " + IntegerToString(g_wbms_summaries[si].closed_trades) + " / " + IntegerToString(g_wbms_summaries[si].open_trades));
      __TRGSTM_WriteLine(handle, "Wins / Losses          : " + IntegerToString(g_wbms_summaries[si].wins) + " / " + IntegerToString(g_wbms_summaries[si].losses));
      __TRGSTM_WriteLine(handle, "Win Rate               : " + __TRGSTM_Pct(g_wbms_summaries[si].win_rate));
      __TRGSTM_WriteLine(handle, "Net Profit             : " + __TRGSTM_Money(g_wbms_summaries[si].net_profit));
      __TRGSTM_WriteLine(handle, "Profit Factor          : " + DoubleToString(g_wbms_summaries[si].profit_factor, 2));
      __TRGSTM_WriteLine(handle, "Max Drawdown           : " + __TRGSTM_Money(g_wbms_summaries[si].max_drawdown_money) + " | " + __TRGSTM_Pct(g_wbms_summaries[si].max_drawdown_pct));
      __TRGSTM_WriteLine(handle, "M15 Bridge Events      : " + IntegerToString(WBMS_DiagBridgeEvents(g_wbms_summaries[si].symbol)));
      __TRGSTM_WriteLine(handle, "M15 Bridge STARTs      : " + IntegerToString(WBMS_DiagBridgeStarts(g_wbms_summaries[si].symbol)));
      __TRGSTM_WriteLine(handle, "M1 Scan Passes         : " + IntegerToString(WBMS_DiagScanPasses(g_wbms_summaries[si].symbol)));

      string detail_file = WBMS_FindStatementFile(g_wbms_summaries[si].symbol);
      if(detail_file != "")
         __TRGSTM_WriteLine(handle, "Detailed Block File    : " + detail_file);
      __TRGSTM_WriteLine(handle, "");
   }

   __TRGSTM_WriteLine(handle, "PORTFOLIO CHRONOLOGICAL EQUITY PATH");
   __TRGSTM_WriteLine(handle, "------------------------------------------------------------");
   if(ArraySize(g_wbms_portfolio_trades) <= 0)
   {
      __TRGSTM_WriteLine(handle, "No accepted central trades were available for portfolio drawdown calculation.");
   }
   else
   {
      for(int pi=0; pi<ArraySize(g_wbms_portfolio_trades); ++pi)
      {
         if(!g_wbms_portfolio_trades[pi].valid) continue;
         string line = "#" + IntegerToString(pi+1)
                     + " | Symbol=" + g_wbms_portfolio_trades[pi].symbol
                     + " | EntryTime=" + __TRGSTM_SafeTime(g_wbms_portfolio_trades[pi].entry_time)
                     + " | ExitTime=" + __TRGSTM_SafeTime(g_wbms_portfolio_trades[pi].exit_time)
                     + " | R=" + DoubleToString(g_wbms_portfolio_trades[pi].result_r, 2) + "R"
                     + " | P/L=" + __TRGSTM_Money(g_wbms_portfolio_trades[pi].pnl_money)
                     + " | Balance=" + __TRGSTM_Money(g_wbms_portfolio_trades[pi].balance_after)
                     + " | Peak=" + __TRGSTM_Money(g_wbms_portfolio_trades[pi].peak_after)
                     + " | DD=" + __TRGSTM_Money(g_wbms_portfolio_trades[pi].dd_money_after)
                     + " | DD%=" + __TRGSTM_Pct(g_wbms_portfolio_trades[pi].dd_pct_after);
         __TRGSTM_WriteLine(handle, line);
      }
   }
   __TRGSTM_WriteLine(handle, "");

   __TRGSTM_WriteLine(handle, "DETAIL BLOCKS");
   __TRGSTM_WriteLine(handle, "============================================================");

   for(int i=0; i<ArraySize(g_wbms_statement_files); ++i)
   {
      string f = g_wbms_statement_files[i];
      if(f == "") continue;

      __TRGSTM_WriteLine(handle, "");
      __TRGSTM_WriteLine(handle, "BEGIN SYMBOL DETAIL FILE: " + f);
      __TRGSTM_WriteLine(handle, "------------------------------------------------------------");

      int rh = FileOpen(f, FILE_READ|FILE_TXT|FILE_COMMON|FILE_UNICODE|FILE_SHARE_READ);
      if(rh == INVALID_HANDLE)
      {
         __TRGSTM_WriteLine(handle, "Could not read symbol detail file. Error=" + IntegerToString(GetLastError()));
         continue;
      }

      while(!FileIsEnding(rh))
      {
         string line = FileReadString(rh);
         line = __WBMS_NormalizeEmbeddedDetailLine(line);
         __TRGSTM_WriteLine(handle, line);
      }
      FileClose(rh);

      __TRGSTM_WriteLine(handle, "END SYMBOL DETAIL FILE: " + f);
   }

   FileFlush(handle);
   FileClose(handle);

   if(InpDebugPrints)
      Print("[WBMS-STATEMENT] Combined multi-symbol statement written: ", filename);
}

inline bool WBMS_AllM15MastersDone(datetime &common_end)
{
   common_end = 0;
   bool have_any = false;
   for(int i=0; i<g_wbms_count; ++i)
   {
      datetime end_t=0; int seq=0;
      if(!WB15_MasterDoneInfo(g_wbms_symbols[i], end_t, seq))
         return false;

      if(end_t > 0)
      {
         if(!have_any || end_t < common_end)
            common_end = end_t;
         have_any = true;
      }
   }
   return true;
}

inline void WBMS_RunHistoricalAllSymbols()
{
   if(g_wbms_count <= 0) WBMS_ParseSymbols();
   WBMS_SelectSymbols();

   datetime start=0, stop=0;
   ResolveWindow(start, stop);
   __WB_RememberTriggerStatementWindow(start, stop);

   const bool m1_mode  = ((ENUM_TIMEFRAMES)Period() == PERIOD_M1);
   const bool m15_mode = ((ENUM_TIMEFRAMES)Period() == PERIOD_M15);
   const ENUM_TIMEFRAMES tf = __WB_EffectiveTF();

   ArrayResize(g_wbms_statement_files, 0);
   ArrayResize(g_wbms_summaries, 0);
   WBMS_ResetDiagnostics();
   WBMS_ResetRawBuckets();

   string ordered_symbols[];
   WBMS_BuildProcessingOrder(ordered_symbols);

   if(InpDebugPrints)
      Print("[WBMS] Processing order=", WBMS_OrderText(ordered_symbols),
            " | central M1 triggers will be replayed through one interleaved chronological account timeline.");

   if(m1_mode)
   {
      datetime common_master_end = 0;
      if(!WBMS_AllM15MastersDone(common_master_end))
      {
         if(InpDebugPrints)
            Print("[WBMS-M1] Waiting until all M15 masters publish DONE for: ", WBMS_SymbolListText());
         return;
      }
      if(common_master_end > 0 && common_master_end < stop)
         stop = common_master_end;
   }

   TriggerStatement_SetBulkScanMode(true);

   for(int i=0; i<ArraySize(ordered_symbols); ++i)
   {
      string sym = ordered_symbols[i];
      if(sym == "") continue;

      WB_SetActiveSymbol(sym);
      SymbolSelect(sym, true);

      bool draw_this = (!InpDrawOnlyChartSymbol || sym == WB_PrimaryInputSymbol() || sym == _Symbol);
      if(!draw_this) Markers_SetPreviewMode(true);
      else           Markers_SetPreviewMode(false);

      __WBMS_ResetCoreForSymbol(m1_mode);
      if(m1_mode)
      {
         TriggerSLTP_SetPreMaxOpenGateEnabled(false);
         Trigger_SetCentralActualCapMode(true);
      }
      Markers_SetPreviewMode(!draw_this);

      datetime sym_stop = __WBMS_ResolveSymbolHardStop(sym, tf, stop);

      if(m15_mode)
      {
         WB15_MasterBegin(sym);
         Trigger_SetM15HardStop(sym_stop, false);
      }
      else if(m1_mode)
      {
         WB15_SlaveInit();
         WB15_Slave_OnTimer(sym);

         // Read bridge diagnostics after the M15 master has published DONE
         // and before the M1 wave pass starts.  These values do not affect
         // trading logic; they only prove whether the symbol had imported M15
         // events available for the M1 trigger engine.
         WBMS_StoreDiagnostics(sym,
                               WB15_BridgeEventCount(sym),
                               WB15_BridgeStartEventCount(sym));

         Trigger_SetM1HardStop(sym_stop, false);
      }

      if(InpDebugPrints)
         Print("[WBMS] Start symbol=", sym, " | tf=", EnumToString(tf),
               " | from=", TimeToString(start, TIME_DATE|TIME_SECONDS),
               " | to=", TimeToString(sym_stop, TIME_DATE|TIME_SECONDS));

      __WBMS_RunOneSymbolWavePass(sym, tf, start, sym_stop);

      if(m15_mode)
      {
         WB15_MasterEnd(sym, sym_stop);
         WBMS_StoreDiagnostics(sym,
                               WB15_BridgeEventCount(sym),
                               WB15_BridgeStartEventCount(sym));
      }
      else if(m1_mode && InpEnableTriggerStatement)
      {
         // Do not write any symbol statement inside the per-symbol scan loop.
         // Store raw triggers only.  After all symbols finish, WaveBot builds
         // one chronological, account-wide execution gate and then writes all
         // symbol detail files plus the combined statement.
         WBMS_StoreCurrentRawRecords(sym, sym_stop);
      }
   }

   if(m1_mode && InpEnableTriggerStatement)
   {
      WBMS_BuildCentralExecutionGate(start, stop);
      WBMS_WriteDeferredSymbolStatements(start, stop);
      TriggerStatement_CentralGateReset();
      Trigger_SetCentralActualCapMode(false);
   }

   TriggerStatement_SetBulkScanMode(false);
   Markers_SetPreviewMode(false);
   WB_SetActiveSymbol(WB_PrimaryInputSymbol());

   if(m1_mode)
      __WBMS_WriteCombinedStatement(start, stop);

   g_once = true;
   g_final_outputs_written = true;
   WBLOG_FlushSnapshotFilesIfDirty();
   WBLOG_FlushAllOpenFiles();
   EventKillTimer();

   if(m15_mode)
   {
      if(InpDebugPrints)
         Print("[WBMS-M15-HARD-STOP] Multi-symbol M15 pass completed. DONE published for ", WBMS_SymbolListText());
      ExpertRemove();
   }
   else if(m1_mode)
   {
      if(InpDebugPrints)
         Print("[WBMS-M1-HARD-STOP] Multi-symbol M1 pass completed. Combined statement written.");
      if((bool)MQLInfoInteger(MQL_TESTER)) TesterStop();
      else ExpertRemove();
   }
}

int OnInit()
{
   g_role = __WB_DetectRole();

   WBMS_ParseSymbols();
   WBMS_SelectSymbols();
   WB_SetActiveSymbol(WB_PrimaryInputSymbol());

   WB_ConfigInitialize((g_role == WBROLE_MASTER_M15 || g_role == WBROLE_STANDALONE),
                       (g_role == WBROLE_SLAVE_M1));

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

   WBLOG_LogParam("InpSymbol", WB_PrimaryInputSymbol(), "input");
   WBLOG_LogParam("InpEnableCentralMultiSymbol", (InpEnableCentralMultiSymbol ? "true" : "false"), "input");
   WBLOG_LogParam("InpMultiSymbolList", InpMultiSymbolList, "input");
   WBLOG_LogParam("WBMS_ParsedSymbols", WBMS_SymbolListText(), "runtime-config");
   WBLOG_LogParam("InpDrawOnlyChartSymbol", (InpDrawOnlyChartSymbol ? "true" : "false"), "input");
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
   WBLOG_LogParam("InpM1MaxTradesPerM15NewSignal", IntegerToString(InpM1MaxTradesPerM15NewSignal), "input");
   WBLOG_LogParam("InpM1MaxOpenTrades", IntegerToString(InpM1MaxOpenTrades), "input");
   WBLOG_LogParam("InpM1MinSLPips", DoubleToString(InpM1MinSLPips, 2), "input");
   WBLOG_LogParam("InpM1MaxSLPips", DoubleToString(InpM1MaxSLPips, 2), "input");
   WBLOG_LogParam("InpM1MaxTradesPerLocalRef", IntegerToString(InpM1MaxTradesPerLocalRef), "input");
   WBLOG_LogParam("M1RuntimeConfigSource", WB_Config_SourceText(), "WaveBot.mq5");
   WBLOG_LogParam("M1_MAX_TRADES_PER_M15_NEW_SIGNAL", IntegerToString(WB_Config_MaxTradesPerM15NewSignal()), "runtime-config");
   WBLOG_LogParam("M1_MAX_OPEN_TRADES", IntegerToString(WB_Config_MaxOpenTrades()), "runtime-config");
   WBLOG_LogParam("TRGSL_MIN_RISK_PIPS", DoubleToString(WB_Config_MinSLPips(), 2), "runtime-config");
   WBLOG_LogParam("TRGSL_MAX_RISK_PIPS", DoubleToString(WB_Config_MaxSLPips(), 2), "runtime-config");
   WBLOG_LogParam("TRGSL_R_MULTIPLE", "3.0", "TriggerSLTP.mqh");
   WBLOG_LogParam("M1_LOCAL_REF_MAX_TRADES", IntegerToString(WB_Config_MaxTradesPerLocalRef()), "runtime-config");
   WBLOG_LogParam("M1_LOCAL_REF_MTC_INVALIDATION", "true", "RaceCoordinator.mqh");

   // Ensure WorldManager captures clean baselines before any scan starts
   Markers_SetNamespace("MAJ");
   WBWM_Init();
   Trigger_ResetGlobals();
   TriggerStatement_ResetGlobals();
   M15NewMarker_ResetGlobals();
   TriggerStatement_SetFinalOnlyOutput(__m1_final_only_output);
   g_stmt_scan_start = 0;
   g_stmt_scan_stop  = 0;
   g_stmt_window_set = false;
   g_final_outputs_written = false;
   g_m1_scan_hard_stopped = false;
   g_m1_scan_hard_stop_time = 0;
   g_m15_scan_hard_stopped = false;
   g_m15_scan_hard_stop_time = 0;
   g_m15_master_end_published = false;
   Trigger_SetM1HardStop(0, false);
   Trigger_SetM15HardStop(0, false);
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
   WB_SetActiveSymbol(WB_PrimaryInputSymbol());
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
   M15NewMarker_ResetGlobals();
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

   if(g_role == WBROLE_MASTER_M15 && g_m15_scan_hard_stopped)
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

      if(g_role == WBROLE_MASTER_M15)
      {
         datetime final_stop15 = g_m15_scan_hard_stop_time;
         if(final_stop15 <= 0)
            final_stop15 = g_stmt_scan_stop;
         __WB_PrimeM15HardStopBoundary(final_stop15);
         final_stop15 = g_m15_scan_hard_stop_time;
         if(final_stop15 <= 0)
            final_stop15 = TimeCurrent();
         __WB_HardStopM15AtScanEnd(final_stop15);
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

   if(WBMS_Enabled())
   {
      WBMS_RunHistoricalAllSymbols();
      return;
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
   else
   if(g_role == WBROLE_MASTER_M15)
   {
      __WB_PrimeM15HardStopBoundary(stop);
      if(g_m15_scan_hard_stop_time > 0)
         stop = g_m15_scan_hard_stop_time;
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
   {
      __WB_PrimeM15HardStopBoundary(stop);
      if(Trigger_M15HardStopFinalizeRequested() && Trigger_M15HardStopFinalizeTime() > 0)
         stop = Trigger_M15HardStopFinalizeTime();
      else
      if(g_m15_scan_hard_stop_time > 0)
         stop = g_m15_scan_hard_stop_time;

      g_once = true;  // فقط یک‌بار اسکن کامل در هر اجرای EA
      __WB_HardStopM15AtScanEnd(stop);
      return;
   }

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
